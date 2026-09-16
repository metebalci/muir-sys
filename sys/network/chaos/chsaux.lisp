;;; -*- Mode:LISP; Package:CHAOS; Base:8; Readtable:T -*-
;;; Stuff that uses the NCP.  Servers, etc.

(DEFUN HOST-UP-P (HOST &OPTIONAL (TIMEOUT 180.) &AUX PKT)
  "Return T if the host is up, otherwise ().  Always () for non-chaosnet machines."
  (COND ((ON-CHAOSNET-P HOST)
	 (UNWIND-PROTECT
	     (CONDITION-CASE ()
		 (SETQ PKT (SIMPLE HOST "STATUS" TIMEOUT))
	       (SYS:REMOTE-NETWORK-ERROR NIL)
	       (:NO-ERROR T))
	   (AND PKT (RETURN-PKT PKT))))
	(T
	 NIL)))
(DEFF HOST-UP 'HOST-UP-P)			;s name. sigh

(DEFUN UP-HOSTS (LIST-OF-HOSTS &OPTIONAL NUMBER-OF-HOSTS (TIMEOUT 240.) 
		  &AUX CONNECTIONS TIME-BEGAN WINNERS)
  "Returns a list of hosts the hosts in LIST-OF-HOSTS that are deemed to be up.
IF NUMBER-OF-HOSTS not NIL, then return as soon as we determine that at least
NUMBER-OF-HOSTS are up.  In that case, we still return a list of hosts.
TIMEOUT is how long in sixtieths of a second to give each host a chance to respond
before deeming that that host is down.  All testing is done in parallel.
Non-chaosnet machines are presently not checked at all; they are assumed to be down."
  ;;the last line should be fixed in the future
  (SETQ LIST-OF-HOSTS (MAPCAR #'SI:PARSE-HOST LIST-OF-HOSTS))
  (*CATCH 'DONE
    (UNWIND-PROTECT
      (PROGN
	(SETQ CONNECTIONS (MAKE-FAST-CONNECTION-LIST LIST-OF-HOSTS "STATUS" 1))
	(PROCESS-ALLOW-SCHEDULE)		;wait around a bit
	(SETQ TIME-BEGAN (TIME))
	(DO () ((NULL CONNECTIONS))
	  (DOLIST (HOST-AND-CONNECTIONS CONNECTIONS)
	    (LET ((HOST (CAR HOST-AND-CONNECTIONS)))
	      (DOLIST (CONNECTION (CDR HOST-AND-CONNECTIONS))
		(LET ((ADDRESS (CAR CONNECTION)) (CONN (CDR CONNECTION)))
		  (IF (NOT CONN) (SETF (CDR CONNECTION)   ; MAKE-FAST-CONNECTION-LIST lost
				       (CONDITION-CASE () ; before, so try again.
					   (OPEN-CONNECTION ADDRESS "STATUS" 1)
					 (SYS:NETWORK-RESOURCES-EXHAUSTED ())))
		    (LET ((STATE (STATE CONN)))
		      (COND ((EQ STATE 'ANSWERED-STATE)
			     (DOLIST (C (CDR HOST-AND-CONNECTIONS)) ; Close all connections
			       (IF (CDR C) (CLOSE-CONN (CDR C))))
			     ; knock it off
			     (SETQ CONNECTIONS (DELQ HOST-AND-CONNECTIONS CONNECTIONS))
			     (PUSH HOST WINNERS))
			    ((MEMQ STATE '(OPEN-STATE CLS-RECEIVED-STATE LOS-RECEIVED-STATE))
			     (PUSH HOST WINNERS)
			     (CLOSE-CONN CONN)
			     (SETF (CDR HOST-AND-CONNECTIONS) ; Remove a single connection
				   (DELQ CONNECTION (CDR HOST-AND-CONNECTIONS))))
			    (T			;(this is primarily RFC-SENT-STATE)
			     (WHEN ( (TIME-DIFFERENCE (TIME) (TIME-LAST-RECEIVED CONN))
				      TIMEOUT)
			       (CLOSE-CONN CONN)	;loser
			       (SETF (CDR HOST-AND-CONNECTIONS)	;Remove a single connection
				     (DELQ CONNECTION (CDR HOST-AND-CONNECTIONS)))))))))
		(COND ((AND NUMBER-OF-HOSTS ;not NIL
			    ( (LENGTH WINNERS) NUMBER-OF-HOSTS))
		       (*THROW 'DONE WINNERS)))
		(IF (NULL (CDR HOST-AND-CONNECTIONS))
		    (SETQ CONNECTIONS (DELQ HOST-AND-CONNECTIONS CONNECTIONS)))))))
	(*THROW 'DONE WINNERS))
	 ; Remove host objects with no connections attached to them
     ;; Unwind-protect cleanup -- Flush any connections that remain
     (DOLIST (H-AND-C CONNECTIONS)
       (DOLIST (CONNECTION (CDR H-AND-C))
	 (IF (CDR CONNECTION) (REMOVE-CONN (CDR CONNECTION)))))))
  WINNERS)

    
;;; The following function is used whenever one wants to make many connections
;;; to many hosts quickly.  It is used as part of Hostat, Finger (all LMs),
;;; and find-user-logged-in...
(DEFUN MAKE-FAST-CONNECTION-LIST (HOSTS CONTACT-NAME
				  &OPTIONAL (WINDOW-SIZE 1) USE-ALL-ADDRESSES
				  &AUX TABLE-FULL)
  "Return a list of (HOST . CONNECTIONs) at CONTACT-NAME.  The caller is
responsible for checking the state of the connection.  CONNECTIONS is a list of
/(ADDRESS . CONN).  CONN is () if the connection table was full at the time."
  (ASSURE-ENABLED)
  (MAPCAR
    #'(LAMBDA (HOST)
	(CONS HOST
	      (MAPCAR
		#'(LAMBDA (ADDRESS)
		    (CONS ADDRESS
			  (CONDITION-CASE ()
			      (IF (NOT TABLE-FULL)
				  (OPEN-CONNECTION ADDRESS CONTACT-NAME WINDOW-SIZE)
				())		;not likely for table to shrink
			    (SYS:NETWORK-RESOURCES-EXHAUSTED (SETQ TABLE-FULL T) ()))))
		;; don't try to get other addresses if user just specified a number
		(IF (AND USE-ALL-ADDRESSES (NOT (FIXNUMP HOST)))
		    (SEND HOST :CHAOS-ADDRESSES)
		  (NCONS (IF (FIXNUMP HOST) HOST
			   (SEND HOST :CHAOS-ADDRESS)))))))
    HOSTS))
    

;;;; Poll hosts

(DEFUN POLL-HOSTS (HOSTS CONTACT-NAME STREAM HEADER-FUNCTION FORMAT-FUNCTION
		   &KEY IGNORE-STATES (WINDOW-SIZE 1) (TIMEOUT 600.) (WHOSTATE "Poll Hosts")
		   &AUX CONNECTIONS PKT (OPEN-CONNECTIONS 0))
  "Print the status of chaosnet hosts in HOSTS, or all known chaosnet hosts.
STREAM is where all of the information is printed.  
HOSTS is a list of hosts to report about.  If NIL, then all chaonset hosts are used.
HEADER-FUNCTION is a function called with one arg, STREAM, to print out the intial header.
FORMAT-FUNCTION is called on STREAM chaos address and response packet for successful
 connections.
WINDOW-SIZE defaults to 1 and the TIMEOUT defaults to 10 seconds (600.)
IGNORE-STATES is either NIL or a list of states for which nothing is printed if the
 connection goes into that state.
 The states can be any of CHAOS:RFC-SENT-STATE CHAOS:ANSWERED-STATE CHAOS:CLS-RECEIVED-STATE
 CHAOS:OPEN-STATE CHAOS:LOS-RECEIVED-STATE or OTHERWISE (any other state)"
  (UNWIND-PROTECT
      (PROGN
	(SETQ CONNECTIONS (IF HOSTS (LOOP FOR HOST IN HOSTS
					  COLLECT (IF (NUMBERP HOST)
						      (LIST NIL HOST NIL)
						    (MULTIPLE-VALUE-BIND (ADDRESS HOST)
							(ADDRESS-PARSE HOST)
						      (LIST HOST ADDRESS NIL))))
			            (CREATE-HOSTAT-CONNECTION-LIST HOSTS)))
	(FUNCALL HEADER-FUNCTION STREAM)
	(DO () ((NULL CONNECTIONS))		;loop until there are no more
	  ;; Handle any replies that have come in.
	  ;; Note host-name truncated to 27. characters to make more room for statistics
	  ;; Only have up to 20. outstanding connections at a time
	  (LOOP FOR ELEM IN CONNECTIONS
		WHILE (< OPEN-CONNECTIONS 20.)
		WITH NEW-CONN
		DO (WHEN (AND (NULL (THIRD ELEM))
			      (SECOND ELEM)
			      (SETQ NEW-CONN (CONDITION-CASE ()
						 (OPEN-CONNECTION (CADR ELEM)
								  CONTACT-NAME WINDOW-SIZE)
					       (SYS:NETWORK-RESOURCES-EXHAUSTED NIL))))
		     (INCF OPEN-CONNECTIONS)
		     (SETF (THIRD ELEM) NEW-CONN)))
	  ;; tell user that something is happening...
	  (PROCESS-WAIT-WITH-TIMEOUT WHOSTATE 120. #'(LAMBDA ()
						       (DOLIST (ELEM CONNECTIONS)
							 (WHEN (AND (THIRD ELEM)
								    (NEQ (STATE (THIRD ELEM))
									 'RFC-SENT-STATE))
							   (RETURN T)))))
	  (DOLIST (ELEM CONNECTIONS)
	    (LET ((HOST (CAR ELEM))
		  (ADDRESS (CADR ELEM))
		  (CONN (CADDR ELEM))
		  (PUNT 'CONN)
		  (PKT NIL))
	      (WHEN CONN
		(CASE (STATE CONN)
		  (RFC-SENT-STATE
		    (IF (< (TIME-DIFFERENCE (TIME) (TIME-LAST-RECEIVED CONN))
			   TIMEOUT)
			(SETQ PUNT NIL)
		      (UNLESS (MEMQ 'RFC-SENT-STATE IGNORE-STATES)
			(FORMAT STREAM "~O~7T~@[~A   ~]Host not responding~%" ADDRESS HOST))))
		  (ANSWERED-STATE
		    (UNWIND-PROTECT
			(PROGN (SETQ PKT (GET-NEXT-PKT CONN))
			       (UNLESS (MEMQ 'ANSWERED-STATE IGNORE-STATES)
				 (FUNCALL FORMAT-FUNCTION STREAM ADDRESS PKT)))
		      (AND PKT (RETURN-PKT PKT)))
		    ;; Delete not only this connection, but every one to this same host, in
		    ;; case it has multiple addresses.  One copy of the answer is enough, but
		    ;; if it fails we would like to see all paths.
		    (SETQ PUNT 'HOST))
		  (CLS-RECEIVED-STATE
		    (UNWIND-PROTECT
			(PROGN (SETQ PKT (GET-NEXT-PKT CONN))
			       (UNLESS (MEMQ 'CLS-RECEIVED-STATE IGNORE-STATES)
				 (FORMAT STREAM "~O~7T~@[~A   ~]returned a CLS:~A~%"
					 ADDRESS HOST (PKT-STRING PKT))))
		      (AND PKT (RETURN-PKT PKT))))
		  (OPEN-STATE
		    (UNLESS (MEMQ 'OPEN-STATE IGNORE-STATES)
		      (FORMAT STREAM "~#oO~7T~@[~A   ~]returned an OPN~%" ADDRESS HOST)))
		  (LOS-RECEIVED-STATE
		    (SETQ PKT (READ-PKTS-LAST CONN))
		    (UNLESS (MEMQ 'LOS-RECEIVED-STATE IGNORE-STATES)
		      (FORMAT STREAM "~O~7T~@[~A   ~]returned a LOS:~A~%"
			      ADDRESS HOST (PKT-STRING PKT))))
		  (OTHERWISE
		    (UNLESS (MEMQ 'OTHERWISE IGNORE-STATES)
		      (FORMAT STREAM "~O~7T~@[~A   ~]connection entered bad state: ~A~%"
			      ADDRESS HOST (STATE CONN)))))
		(CASE PUNT
		  (CONN (REMOVE-CONN CONN)
			(SETQ CONNECTIONS (DELQ ELEM CONNECTIONS))
			(DECF OPEN-CONNECTIONS))
		  (HOST (WHEN HOST
			  (DOLIST (C CONNECTIONS)
			    (WHEN (EQ (CAR C) HOST)
			      (WHEN (THIRD C) (REMOVE-CONN (THIRD C)))
			      (SETQ CONNECTIONS (DELQ C CONNECTIONS))
			      (DECF OPEN-CONNECTIONS)))))))))))
    ;; Remove host objects with no connections attached to them
    ;; Unwind-protect cleanup -- Flush any connections that remain
    (LOOP FOR (HOST ADDRESS CONN) IN CONNECTIONS
	  WHEN CONN DO (CLOSE-CONN CONN)))) 

;;; what a kludge 
(DEFVAR CANONICAL-HOSTAT-ALL-LIST NIL
  "Internal list in the form (host address nil) which is used to speed up hostat.")

(DEFUN INITIALIZE-CANONICAL-HOSTAT-ALL-LIST (&AUX HOSTS)
  "Initializes the variable CANONICAL-HOSTAT-ALL-LIST to have the right value."
  (SETQ CANONICAL-HOSTAT-ALL-LIST NIL
	HOSTS NIL)
  ;; reverse does a copylist which we need before sortcar
  (DOLIST (HOST (REVERSE (ALL-CHAOS-HOSTS))) 
    ;; speed up as this is likely to be in reverse alphabetical order
    (PUSH (CONS (SEND HOST :NAME) HOST) HOSTS))
  (SETQ HOSTS (SORTCAR HOSTS #'ALPHALESSP))
  (DOLIST (CONS HOSTS)
    (PUSH (LIST (CDR CONS) (ADDRESS-PARSE (CDR CONS)) NIL) CANONICAL-HOSTAT-ALL-LIST))
  (SETQ CANONICAL-HOSTAT-ALL-LIST (NREVERSE CANONICAL-HOSTAT-ALL-LIST)))

(DEFUN CREATE-HOSTAT-CONNECTION-LIST (HOSTS &AUX LIST)
  "Return a list in the form (host address nil) for each host in HOSTS, or for all chaos hosts"
  (COND ((NULL HOSTS)
	 (COPYTREE				;please don't mung this variable
	   (OR CANONICAL-HOSTAT-ALL-LIST	;could be NIL
	       (INITIALIZE-CANONICAL-HOSTAT-ALL-LIST))))
	(T
	 (DOLIST (HOST HOSTS)
	   (LET ((PARSED (SI:PARSE-HOST HOST T)))
	     (WHEN PARSED
	       (PUSH (LIST PARSED (ADDRESS-PARSE PARSED) NIL) LIST))))
	 LIST)))

;;;; The HOSTAT function

(DEFUN HOSTAT (&REST HOSTS)
  "Prints out information on STREAM on the status of all of the hosts specified by HOSTS."
  (POLL-HOSTS HOSTS "STATUS" *STANDARD-OUTPUT*
	      (IF (CDR HOSTS)
		  #'HOSTAT-HEADING
		  #'(LAMBDA (STREAM) (HOSTAT-HEADING STREAM NIL)))
	      #'HOSTAT-FORMAT-ANS
	      :WHOSTATE "Hostat Reply"))

(DEFUN HOSTAT-HEADING (STREAM &OPTIONAL (VERBOSE T))
  (FORMAT STREAM "~&Chaosnet host status report.  ~:[~;Type Control-Abort to quit.~]" VERBOSE)
  (FORMAT STREAM "~%~7A~25A" "Site" "Name//Status")
  (DO ((HEADS '("Subnet" "#-in" "#-out" "abort" "lost" "crc" "ram" "bitc" "other")
	      (CDR HEADS))
       (WIDTHS '(6 9 9 8 8 8 4 5 6) (CDR WIDTHS)))
      ((NULL HEADS) (WRITE-CHAR #/NEWLINE STREAM))
    (FORMAT STREAM "~V@A" (CAR WIDTHS) (CAR HEADS))))

(DEFUN HOSTAT-FORMAT-ANS (STREAM HOST PKT &AUX (NBYTES (PKT-NBYTES PKT)))
  (FORMAT STREAM "~7@<~O ~>~27A"		;Print host number and name as returned
	  HOST
	  (NSUBSTRING (PKT-STRING PKT) 0
		      (MIN NBYTES 27. (OR (STRING-SEARCH-CHAR 0 (PKT-STRING PKT) 0 32.)
					  ;; This line is temporary! *******
					  (STRING-SEARCH-CHAR #o200 (PKT-STRING PKT) 0 32.)
					  32.))))
  (HOSTAT-FORMAT-ANS-1 PKT 34. '(4 9 9 8 8 8 4 5 6) STREAM))

(DEFUN HOSTAT-FORMAT-ANS-1 (PKT START-COLUMN COLUMN-WIDTHS STREAM
			    &AUX (NBYTES (PKT-NBYTES PKT)))
  (DO ((I 24. (+ I 2 CT))		;Now display subnet meters
       (FIRST-LINE T NIL)
       (ID) (CT)
       (MAXI (+ 8 (TRUNCATE NBYTES 2))))
      (( I MAXI) (AND FIRST-LINE (WRITE-CHAR #/NEWLINE STREAM)))
    (SETQ ID (AREF PKT I) CT (AREF PKT (1+ I)))	;Block header
    (OR FIRST-LINE (FORMAT STREAM "~VA" START-COLUMN ""))
    (COND ((< ID #o400)				;Subnet info (old 16-bit format)
	   (FORMAT STREAM "~VO" (CAR COLUMN-WIDTHS) ID)
	   (DO ((J (+ I 2) (1+ J))		;Now print those meters that are present
		(L (CDR COLUMN-WIDTHS) (CDR L))
		(N (MIN CT 8) (1- N)))
	       ((ZEROP N))
	     (FORMAT STREAM "~VD" (CAR L) (AREF PKT J))))
	  ((< ID #o1000)			;Subnet info
	   (FORMAT STREAM "~VO" (CAR COLUMN-WIDTHS) (- ID #o400))
	   (DO ((J (+ I 2) (+ J 2))		;Now print those meters that are present
		(L (CDR COLUMN-WIDTHS) (CDR L))
		(N (MIN (TRUNCATE CT 2) 8) (1- N)))
	       ((ZEROP N))
	     (FORMAT STREAM "~VD" (CAR L) (DPB (AREF PKT (1+ J)) #o2020 (AREF PKT J)))))
	  (T					;I don't know about this
	   (FORMAT STREAM "~O unknown info block ID" ID)))
    (WRITE-CHAR #/NEWLINE STREAM)))

(DEFUN PRINT-HOST-TIMES (&OPTIONAL (HOSTS TIME-SERVER-HOSTS) (STREAM *STANDARD-OUTPUT*))
  (LET ((BEGIN-TIME (TIME:TIME))
	(TOTAL-TIME 0)
	(RESPONSES 0))
    (POLL-HOSTS HOSTS "TIME" STREAM
		#'(LAMBDA (STREAM) (FORMAT STREAM "~&Host~26TTime"))
		#'(LAMBDA (STREAM ADDRESS PKT)
		    (LET ((TIME (DECODE-CANONICAL-TIME-PACKET PKT)))
		      (FORMAT STREAM "~&~:[~;! ~]~A~22,2T~\TIME\~%"
			      (> (ABS (- (TIME:GET-UNIVERSAL-TIME) TIME)) 180.)
			      (SI:GET-HOST-FROM-ADDRESS ADDRESS :CHAOS)
			      TIME)
		      (INCF TOTAL-TIME TIME)
		      (INCF RESPONSES)))
		:WHOSTATE "Host time")
    (FORMAT STREAM "~2%Average time: ~\TIME\; total time elapsed: ~D seconds.~%"
	    (ROUND TOTAL-TIME RESPONSES) (TRUNCATE (- (TIME:TIME) BEGIN-TIME) 60.))))

;;;this time divided by 2 is significant
;(DEFUN MOST-PROBABLE-TIME (TIME-LIST &AUX L PUNT)
;  "Given a list of times, return what the time is most likely to be."
;  (SETQ L (LENGTH TIME-LIST))
;  (SETQ PUNT (IF (< L 3)			;if we just want to take the exact average
;		 0
;	       (+ 1 (// L 4))))			;it works
;  (SETQ TIME-LIST (SORT TIME-LIST #'>))
;  (LOOP FOR I FROM (+ 0 PUNT) TO (- L PUNT 1)
;	SUMMING (NTH I TIME-LIST) INTO SUM
;	FINALLY (// SUM (- L (* 2 PUNT)))))

;;; This always works for MINITS boxes
(DEFUN RESET-TIME-SERVER (HOST &AUX PKT)
  (SETQ HOST (SI:PARSE-HOST HOST))
  (PRINT-HOST-TIMES (LIST HOST))
  (UNWIND-PROTECT
      (CONDITION-CASE (RESULT)
	  (SETQ PKT (SIMPLE HOST "RESET-TIME-SERVER"))
	(SYS:NETWORK-ERROR
	 (FORMAT *ERROR-OUTPUT* "~&Network error: ")
	 (SEND RESULT :REPORT *ERROR-OUTPUT*)
	 (WRITE-CHAR #/NEWLINE *ERROR-OUTPUT*))
	(:NO-ERROR
	 (FORMAT T "~&Successfully reset the time of ~A." HOST)))
    (AND PKT (RETURN-PKT PKT))))

;;; SHOUT to all Lisp Machines.  
(DEFUN SHOUT (&AUX MSG-TEXT HOST PERSON)
  "Send a message to all Lisp machines.  The message is read from the terminal."
  (FS:FORCE-USER-TO-LOGIN)
  (FORMAT T "~%Message: (terminate with ~:@C)~%" #/END)
  (SETQ MSG-TEXT
	(STRING-APPEND "Everybody: "
		       (ZWEI:QSEND-GET-MESSAGE *QUERY-IO*
					       (FORMAT NIL
"You are typing a message which will be sent to everyone who is using a Lisp Machine.
If you want to quit, hit the ~:@C key.  To end your message, hit the ~:@C key."
#/ABORT #/END))
		       PERSON "anyone"))
  (DO ((MACHINE SI:MACHINE-LOCATION-ALIST (CDR MACHINE)))
      ((NULL MACHINE))
    (SETQ HOST (CAAR MACHINE))
    (WITH-OPEN-STREAM (STREAM (OPEN-STREAM HOST (STRING-APPEND "SEND " PERSON)
					   :ERROR NIL :DIRECTION :OUTPUT))
      (UNLESS (ERRORP STREAM)
	(FORMAT STREAM "~A@~A ~\DATIME\~%" USER-ID SI:LOCAL-HOST)
	(SEND STREAM :STRING-OUT MSG-TEXT)
	(SEND STREAM :CLOSE)))))

(DEFUN EXPAND-MAILING-LISTS (NAMES HOST &AUX RESULT STREAM BAD-ADDRESSES CHAR)
  "Return a list of the recipients of the addresses NAMES at HOST.
Returns either a list of addresses, and a list of bad addresses, or an error instance.
The NAMES should not contain atsigns."
  (DECLARE (VALUES ADDRESSES BAD-ADDRESSES))
  (UNWIND-PROTECT
      (PROGN
	(SETQ STREAM (OPEN-STREAM HOST "EXPAND-MAILING-LIST" :ERROR NIL))
	(IF (ERRORP STREAM) STREAM
	  (DOLIST (NAME NAMES (VALUES (NREVERSE RESULT) (NREVERSE BAD-ADDRESSES)))
	    (SEND STREAM :LINE-OUT NAME)
	    (SEND STREAM :FORCE-OUTPUT)
	    (COND ((CHAR= (SETQ CHAR (SEND STREAM :TYIPEEK)) #/-)
		   (SEND STREAM :LINE-IN)
		   (PUSH NAME BAD-ADDRESSES))
		  ((CHAR= CHAR #/+)
		   (SEND STREAM :LINE-IN)
		   (DO ((LINE (SEND STREAM :LINE-IN T) (SEND STREAM :LINE-IN T)))
		       ((ZEROP (STRING-LENGTH LINE)))
		     (PUSHNEW LINE RESULT :TEST #'STRING-EQUAL)))
		  (T
		   (FERROR () "Unknown character ~C in response" CHAR))))))
    (AND STREAM (NOT (ERRORP STREAM)) (SEND STREAM :CLOSE :ABORT))))
  

;;;; Finger server and NAME user end

(ADD-INITIALIZATION "FINGER" '(GIVE-FINGER) NIL 'SERVER-ALIST)

(DEFVAR GIVE-FINGER-SAVED-STRING NIL)
(DEFVAR GIVE-FINGER-SAVED-IDLE NIL)
(DEFVAR GIVE-FINGER-SAVED-USER-ID NIL)

;This runs in the background task now.
(DEFUN GIVE-FINGER (&AUX IDLE)
  (SETQ IDLE (FLOOR (TIME-DIFFERENCE (TIME) TV:KBD-LAST-ACTIVITY-TIME) 3600.)) ;Minutes
  ;; Making the string is expensive in terms of paging, and it is almost
  ;; always the same as last time.  So try to use a saved string.
  (COND ((OR (NEQ GIVE-FINGER-SAVED-IDLE IDLE)
	     (NEQ GIVE-FINGER-SAVED-USER-ID USER-ID))
	 (SETQ GIVE-FINGER-SAVED-IDLE IDLE
	       GIVE-FINGER-SAVED-USER-ID USER-ID
	       GIVE-FINGER-SAVED-STRING
	          (FORMAT NIL "~A~%~A~%~:[~3*~;~:[~D:~2,48D~;~*~D~]~]~%~A~%~C~%"
                          USER-ID
                          SI::LOCAL-FINGER-LOCATION
                          (NOT (ZEROP IDLE))
                          (ZEROP (FLOOR IDLE 60.))
                          (FLOOR IDLE 60.)
                          (\ IDLE 60.)
			  FS:USER-PERSONAL-NAME-FIRST-NAME-FIRST
			  FS:USER-GROUP-AFFILIATION))))
  (ERRSET (FAST-ANSWER-STRING "FINGER" GIVE-FINGER-SAVED-STRING) NIL))

;;; This can't run in the background process, since it uses a full byte-stream
;;; connection, which requires retransmission, which is done by the background process.
(ADD-INITIALIZATION "NAME" '(PROCESS-RUN-FUNCTION "NAME Server" 'GIVE-NAME)
		    NIL 'SERVER-ALIST)

(DEFUN GIVE-NAME (&AUX CONN IDLE)
  (SETQ CONN (LISTEN "NAME"))
  (SETQ IDLE (FLOOR (TIME-DIFFERENCE (TIME) TV:KBD-LAST-ACTIVITY-TIME) 3600.)) ;Minutes
  (ERRSET
    (FORMAT-AND-EOF CONN
		    "~6A ~C ~22A ~6A ~:[    ~3*~;~:[~D:~2,48D~;  ~*~D~]~]     ~A"
		    USER-ID
		    FS:USER-GROUP-AFFILIATION
		    FS:USER-PERSONAL-NAME-FIRST-NAME-FIRST
		    (USER-ACTIVITY-STRING)
		    (NOT (ZEROP IDLE))
		    (ZEROP (FLOOR IDLE 60.))
		    (FLOOR IDLE 60.)
		    (\ IDLE 60.)
		    SI:LOCAL-FINGER-LOCATION)
    NIL))

(DEFUN USER-ACTIVITY-STRING ()
  (LET ((W (DO ((W TV:SELECTED-WINDOW (SEND W :SUPERIOR))
		(W1 NIL W))
	       ((OR (NULL W) (TYPEP W 'TV:SCREEN)) W1))))
    (OR (IGNORE-ERRORS
	  (TYPECASE W
	    (SUPDUP "Supdup")
	    (ZWEI:ZMACS-FRAME "Zmacs")
	    (TV:PEEK-FRAME "Peek")
	    (ZWEI:CONVERSE-FRAME "Converse")
	    (TV:INSPECT-FRAME "Inspect")
	    (TV:LISP-LISTENER "Lisp")
	    (TELNET "Telnet")
	    (FED:FED-FRAME "Font Edit")
	    (ZWEI:ZMAIL-FRAME "ZMail")))
	SI:LOCAL-HOST-NAME)))

(DEFUN FINGER (&OPTIONAL SPEC (STREAM *STANDARD-OUTPUT*) HACK-BRACKETS-P
	       &AUX HOST HOST-NAME INDEX GATEWAY-P FIRST-LINE)
  "Print brief information about a user as specified by SPEC.
SPEC can be a user name, or user@host.
If HACK-BRACKETS-P is T, then make the first line show what host we are fingering."
  (COND ((NULL SPEC)
	 (SETQ HOST SI:ASSOCIATED-MACHINE))	;a reasonable default
	((SETQ INDEX (STRING-SEARCH-CHAR #/@ SPEC))
	 (SETQ HOST (SUBSTRING SPEC (1+ INDEX)))	;if there is an @, then a diff host
	 (LET ((HOST1 (SI:PARSE-HOST HOST T)))
	   (OR (AND HOST1			;Go directly if host is on ChaosNet
		    (SETQ HOST-NAME (SEND HOST1 :NAME));we parsed it, we know its name
		    (ON-CHAOSNET-P HOST1)
		    (SETQ SPEC (SUBSTRING SPEC 0 INDEX)))
	       (SETQ HOST NIL GATEWAY-P T))))
	;; Else use default host, but pass the string along
	(T (SETQ HOST SI:ASSOCIATED-MACHINE)))	;No explicit host, use default
  (AND (EQ HOST SI:ASSOCIATED-MACHINE) (SETQ HOST-NAME (SEND HOST :NAME)))
  (AND HOST (SETQ HOST (ADDRESS-PARSE HOST)))
  (SETQ SPEC (IF SPEC (STRING-APPEND "NAME" #/SP SPEC) "NAME"))
  ;;When are we going to win with which gateway we should use???
  ;;(if we are fingering multiple hosts, be smart, like mail, as to with gateway to use
  (DO ((DEFAULTS (SI:GET-SITE-OPTION :ARPA-GATEWAYS) (CDR DEFAULTS)))
      ((AND (NULL DEFAULTS) (NULL HOST))
       "No gateway available.")			;no arpa gateway that is
    (WITH-OPEN-STREAM (CSTREAM (OPEN-STREAM (OR HOST (CAR DEFAULTS)) SPEC
					   :DIRECTION :INPUT :ERROR NIL
					   ;; If going through an ITS gateway, character set
					   ;;  is ascii and has to be translated.
					   :ASCII-TRANSLATION GATEWAY-P))
      (IF (ERRORP CSTREAM)			;If attempt to connect failed
	  (AND HOST				;If explicit host, return reason for failure
	       (RETURN CSTREAM))		; else try next default
	(FORMAT STREAM "~2&")			;blank lines, to look pretty
	(SETQ FIRST-LINE (SEND CSTREAM :LINE-IN))	;try to find the brackets, 
	(IF (STRING-EQUAL "" FIRST-LINE)	;and gobble empty lines, we put them in ourself
	    (SETQ FIRST-LINE (SEND CSTREAM :LINE-IN)))	;really second line
	(AND HACK-BRACKETS-P			;if we want don't to mung the brackes
	     (AND (NOT (STRING-SEARCH-CHAR #/[ FIRST-LINE))
		  (NOT (STRING-SEARCH-CHAR #/] FIRST-LINE)))	;brackets aren't already there
	     (SEND STREAM :LINE-OUT (STRING-APPEND #/[ HOST-NAME #/])))	;put in the []
	(SEND STREAM :LINE-OUT FIRST-LINE)	;print out the original line
	(STREAM-COPY-UNTIL-EOF CSTREAM STREAM)	;now just print out the rest of the finger
	(RETURN NIL)))))			;unless there is an error

(DEFUN WHOIS (&OPTIONAL SPEC (STREAM *STANDARD-OUTPUT*))
  "Print verbose information about a user as specified by SPEC.
SPEC can be a user name, or user@host."
  (FINGER (STRING-APPEND "//W "
			 (IF SPEC SPEC (SEND SI:ASSOCIATED-MACHINE :SHORT-NAME)))
	  STREAM))

;yes, I've heard of selectq! - change this lossage to METHODS, except for :WAITS
(DEFVAR HOST-FINGER-PROTOCOL-ALIST
	'((:LISPM . PARSE-LISPM-FINGER)
	  (:TOPS-20 . PARSE-TWENEX-FINGER)
	  (:ITS . PARSE-ITS-FINGER)
	  (:WAITS . PARSE-WAITS-FINGER)
	  (:UNIX . PARSE-UNIX-FINGER)
	  (:MULTICS . PARSE-MULTICS-FINGER)
	  (:VMS . PARSE-VMS-FINGER)
	  (:TOPS-10 . PARSE-TENEX-FINGER))
  "This list is for use by chaos:user-logged-into-host-p.")

(DEFUN PARSE-TWENEX-FINGER (USER FINGER-INFO)
  "Return T if the USER is logged to a twenex site, based on the finger info we have."
  (IGNORE USER)
  (SETQ FINGER-INFO (STRING-UPCASE FINGER-INFO))
  (AND (NOT (STRING-SEARCH "LOGOUT" FINGER-INFO)) ;last logged out ==> not logged in.
       (NOT (STRING-EQUAL "" FINGER-INFO))
;      (OR (< (STRING-LENGTH FINGER-INFO) 4)  ;;don't lose with detached jobs
;      (NOT (STRING-EQUAL (STRING-APPEND "DET" #/CR)  ;this could be more clever
;			  (SUBSTRING FINGER-INFO (- (STRING-LENGTH FINGER-INFO) 4)))))
       (NOT (MEMQ (CHAR FINGER-INFO 0) '(#/? #/%)))
       ))

(DEFUN PARSE-MULTICS-FINGER (USER FINGER-INFO)
  "Return T if the USER is logged to a Multics site, based on the finger info we have."  
  (IGNORE USER)
  (NOT (STRING-SEARCH "Not logged in" FINGER-INFO)))

(DEFUN PARSE-UNIX-FINGER (USER FINGER-INFO)
  "Return T if the USER is logged to a Unix site, based on the finger info we have."  
  (IGNORE USER)
  (IF (STRING-SEARCH "On since" FINGER-INFO) T)) ;catch all  

(DEFUN PARSE-TENEX-FINGER (USER FINGER-INFO)
  "Return T if the USER is logged to a Tenex site, based on the finger info we have."  
  (IGNORE USER)
  (IF (STRING-SEARCH "Who What" FINGER-INFO) T)) 

(DEFUN PARSE-WAITS-FINGER (USER FINGER-INFO)	;this may not be exactly correct
  "Return T if the USER is logged to a waits site, based on the finger info we have."  
  (IGNORE USER)
  (IF (STRING-SEARCH "Logged in" FINGER-INFO) T)) ;catch all

(DEFUN PARSE-VMS-FINGER (USER FINGER-INFO)
  "Return T if the USER is logged to a VMS site, based on the finger info we have."  
  (IGNORE USER)
  (IF (STRING-SEARCH "Personal Name" FINGER-INFO) T)) ;catch all

(DEFUN PARSE-ITS-FINGER (USER FINGER-INFO)
  "Return T if the USER is logged to a ITS site, based on the finger info we have."  
  (IGNORE USER)
  (AND (NOT (STRING-SEARCH "Last logout" FINGER-INFO)) ;not logged in
       (NOT (STRING-SEARCH "user" FINGER-INFO))        ;"No users" -- no such user
       ))

(DEFUN PARSE-LISPM-FINGER (USER FINGER-INFO)
  "Return T if the USER is logged into a Lispm, based on the finger info we were given."
  (IF (STRING-EQUAL USER (SUBSTRING FINGER-INFO 0 (STRING-LENGTH USER))) T)) ;we don't ignore

(DEFUN USER-LOGGED-INTO-HOST-P (USER HOST &AUX FINGER-INFO HOST-TYPE FUNCTION)
  "Return T or NIL on the basis of whether USER is logged into HOST."
  (SETQ FINGER-INFO (WITH-OUTPUT-TO-STRING (FINGER-INFO)
		      (FINGER (STRING-APPEND (STRING-APPEND USER "@") HOST)
				    FINGER-INFO)))
  (SETQ FINGER-INFO (STRING-LEFT-TRIM #/RETURN FINGER-INFO))	;meaningless
  (SETQ HOST-TYPE (SEND (SI:PARSE-HOST HOST) :SYSTEM-TYPE))
  (SETQ FUNCTION (SYS:ASSOC-EQUAL HOST-TYPE HOST-FINGER-PROTOCOL-ALIST))
  (IF (NULL FUNCTION)				;
      (FERROR "~S is not a known type of host that supports the NAME protocol."
	      HOST-TYPE))
  (FUNCALL (CDR FUNCTION) USER FINGER-INFO))

;;; I'd like to see some parallelism here....
(DEFUN FIND-HOSTS-OR-LISPMS-LOGGED-IN-AS-USER (USER &OPTIONAL HOSTS NO-LISPMS-P &AUX LISPMS)
  "Return a list of host objects for hosts on which USER is logged in.
HOSTS is the list of hosts to check (in addition to all Lisp machines).
If NO-LISPMS-P is T, don't return any Lispms."
  (IF (NULL NO-LISPMS-P) (SETQ LISPMS (FIND-LISPMS-LOGGED-IN-AS-USER USER)))
  (DOLIST (HOST HOSTS)
    (IF (USER-LOGGED-INTO-HOST-P USER HOST)
	(PUSH (SI:PARSE-HOST HOST) LISPMS)))
  LISPMS)

(DEFUN FIND-ANY-UP-HOST-OF-TYPE  (TYPE &OPTIONAL DONT-USE-HOSTS EVEN-IF-DOWN (TIMEOUT 360.)
				  &AUX HOSTS-TO-TRY)
"Returns a host which is of that is of system type TYPE.
Will not return a host if it is in the list DONT-USE-HOSTS.
TIMEOUT specifies how long to wait before giving up, in 60ths of a sec.  Default is 6 seconds.
If DONT-USE-HOSTS is T, then use every host with that system type, instead of just one.
If EVEN-IF-DOWN is T, return all such hosts, regardless if they are up or not.
If you are using the EVEN-IF-DOWN argument, you probably want LIST-ALL-NET-MACHINES."
  (SETQ HOSTS-TO-TRY (LIST-ALL-NET-MACHINES TYPE))
  (IF (NEQ DONT-USE-HOSTS T)
      (DOLIST (HOST DONT-USE-HOSTS)
	(SETQ HOSTS-TO-TRY (DELQ (SI:PARSE-HOST HOST) HOSTS-TO-TRY))))
  (IF EVEN-IF-DOWN
      HOSTS-TO-TRY
    (UP-HOSTS HOSTS-TO-TRY (IF (EQ DONT-USE-HOSTS T)
			       NIL		;find all
			       1.)		;find any
	      TIMEOUT)))

(DEFUN LISPM-FINGER-INFO (LM-HOST)
  "Given a LispM, return its default finger info."
  (LET ((NAME (SEND (SI:PARSE-HOST LM-HOST) :NAME)))
    (OR (THIRD (SYS:ASSOC-EQUALP NAME SI:MACHINE-LOCATION-ALIST))
	"Unknown.")))

;;;; Finger All Lispms crap
(DEFVAR *SAVED-ALL-LISPMS* () "Generated first time we want to finger all LispMs.")
(DEFVAR *SAVED-LOCAL-LISPMS* () "Generated first time we want to finger local LispMs.")
(DEFVAR *SAVED-ALL-CHAOS-HOSTS* ()
  "Generated first time we want a list of every chaosnet hosts.")

(ADD-INITIALIZATION "Initialize host lists"
		    '(PROGN
		       (RESET-SAVED-HOST-LISTS T T T)
		       (INITIALIZE-CANONICAL-HOSTAT-ALL-LIST))
		    ()
		    'SI:SITE-INITIALIZATION-LIST)

(DEFUN ALL-LOCAL-LISPMS (&OPTIONAL RESET)
  "Returns a list of all local lisp machines.
If RESET is T, then generate the list from scratch."
  (IF (OR (NULL *SAVED-LOCAL-LISPMS*) RESET)
      (RESET-SAVED-HOST-LISTS NIL T NIL))
  *SAVED-LOCAL-LISPMS*)

(DEFUN ALL-LISPMS (&OPTIONAL RESET)
  "Returns a list of all lisp machines.
If RESET is T, then generate the list from scratch."
  (IF (OR (NULL *SAVED-ALL-LISPMS*) RESET)
      (RESET-SAVED-HOST-LISTS NIL NIL T))
  *SAVED-ALL-LISPMS*)

(DEFUN ALL-CHAOS-HOSTS (&OPTIONAL RESET)
  "Returns a list of all hosts which are known and on the chaosnet.
If RESET is T, then generate the list from scratch."
  (IF (OR (NULL *SAVED-ALL-CHAOS-HOSTS*) RESET)
      (RESET-SAVED-HOST-LISTS T NIL NIL))
  *SAVED-ALL-CHAOS-HOSTS*)

(DEFUN RESET-SAVED-HOST-LISTS (&OPTIONAL (DO-ALL-HOSTS T) DO-LOCAL-LISPMS DO-ALL-LISPMS)
  "Sets the magic variables that contain a list of all hosts for efficiency."
  (COND (DO-ALL-HOSTS
	 (SETQ *SAVED-ALL-CHAOS-HOSTS* NIL)	;reset
	 ;; code is from old hostat
	 ;; use SI:PARSE-HOST because it's faster on host objects
	 (DOLIST (H SI:HOST-ALIST)
	   (AND (OR (SECOND H) (SI:PARSE-HOST (FIRST H)))
		(SECOND H)
		(SEND (SECOND H) :NETWORK-TYPEP :CHAOS)
		(PUSH (SECOND H) *SAVED-ALL-CHAOS-HOSTS*)))))
  (WHEN DO-LOCAL-LISPMS
    (SETQ *SAVED-LOCAL-LISPMS* NIL)
    (DOLIST (ELEM SI:MACHINE-LOCATION-ALIST)
      (LET ((TEM (SI:PARSE-HOST (CAR ELEM) T)))
	(WHEN TEM (PUSH TEM *SAVED-LOCAL-LISPMS*))))
    (SETQ *SAVED-LOCAL-LISPMS* (NREVERSE *SAVED-LOCAL-LISPMS*)))
  (WHEN DO-ALL-LISPMS
    (SETQ *SAVED-ALL-LISPMS* (LIST-ALL-NET-MACHINES :LISPM))))	;already parsed

(DEFSUBST FCL-HOST (ELEM) (CAR ELEM))
(DEFSUBST FCL-CONN1 (ELEM) (CDADR ELEM))	; First CHAOS CONN in an element

;;; SYS: WINDOW; BASSTR wants to call these some of these, please don't rename recklessly

(DEFF FINGER-LOCAL-LISPMS 'FINGER-LISPMS)	;announced name
(DEFF FINGER-ALL-LMS 'FINGER-ALL-LISPMS)

(DEFUN FINGER-ALL-LISPMS (&OPTIONAL (STREAM *STANDARD-OUTPUT*) HOSTS
			  (PRINT-FREE T) RETURN-FREE (PRINT-INUSE T) (PRINT-DOWN T))
  "Display who is logged into the lispm machine HOSTS or all LispMs if HOSTS is NIL"
  (IF (NULL HOSTS)
      (SETQ HOSTS (ALL-LISPMS)))
  (FINGER-LISPMS STREAM HOSTS PRINT-FREE RETURN-FREE PRINT-INUSE PRINT-DOWN))

;;; INUSE is an option to the FAL server used by oz.
;;; list is a logical ordering of the args.  Remember, this is an interal function!
;;; look at tv:kbd-finger in SYS: WINDOW; BASSTR before changing the arglist!!!

(DEFUN FINGER-LISPMS (&OPTIONAL
		      (STREAM *STANDARD-OUTPUT*) HOSTS (PRINT-FREE T) RETURN-FREE
		      (PRINT-INUSE T) (PRINT-DOWN T)
		      &AUX FREE DOWN ELEMS HOST)
  "Print brief information about who is logged in to each Lisp machine.
STREAM is where to print it.
PRINT-FREE not NIL says print also lists of free and nonresponding Lisp machines.
RETURN-FREE not NIL says return information about free and nonresponding machines;
 in this case, the first value is a list of host objects of free machines
 and the second a list of host objects of nonresponding ones.
HOSTS is the list of hosts to check, defaulting to all known Lisp machines.
HOSTS should be a list of already parsed hosts, or NIL."
  (IF (NULL HOSTS)
      (SETQ HOSTS (ALL-LOCAL-LISPMS)))
  (SETQ ELEMS (MAKE-FAST-CONNECTION-LIST HOSTS "FINGER" 1))
  (UNWIND-PROTECT
      ;; If number of machines gets large enough,
      ;; put in a hack like HOSTAT's, to go around later and try again
      ;; to connect to machines which we couldn't get the first time
      ;; due to connection table full.
      (DO ((OLD-TIME (TIME)))
	  (NIL)
	(DOLIST (ELEM ELEMS)
	  (LET* ((CONN (FCL-CONN1 ELEM))
		 (STATE (AND CONN (STATE CONN))))
	    (UNLESS (EQ STATE 'RFC-SENT-STATE)
	      ;; Got some reply for this one.
	      (WHEN (EQ STATE 'ANSWERED-STATE)	;Got something meaningful
		(LET* ((PKT (GET-NEXT-PKT CONN))
		       (STR (PKT-STRING PKT))
		       (HOST-NAME (GET-SHORT-LM-NAME (FCL-HOST ELEM)))
		       (IDX))
		  (UNWIND-PROTECT
		      (COND ((NOT (MEMQ (CHAR STR 0) '(#/CR #/SP #/TAB)))	;Logged in
			     (WHEN PRINT-INUSE
			       (LET (USER (GROUP "") (NAME "") (IDLE "") (LOCATION ""))
				 (SETQ USER
				       (NSUBSTRING STR 0
						   (SETQ IDX (STRING-SEARCH-CHAR #/CR STR))))
				 (WHEN IDX
				   (SETQ LOCATION
					 (NSUBSTRING STR (1+ IDX)
						     (SETQ IDX (STRING-SEARCH-CHAR #/CR STR (1+ IDX))))))
				 
				 (WHEN IDX
				   (SETQ IDLE
					 (NSUBSTRING STR (1+ IDX)
						     (SETQ IDX (STRING-SEARCH-CHAR #/CR STR (1+ IDX))))))
				 (WHEN IDX
				   (SETQ NAME
					 (NSUBSTRING STR (1+ IDX)
						     (SETQ IDX (STRING-SEARCH-CHAR #/CR STR (1+ IDX))))))
				 (SETQ GROUP
				       (IF IDX (AREF STR (1+ IDX)) #/SP))
				 (FORMAT STREAM
					 "~&~10A ~C ~22A ~7A ~4@A    ~A~%"
					 USER GROUP NAME HOST-NAME IDLE LOCATION))))
			    ((OR PRINT-FREE RETURN-FREE)	;person CANNOT be logged in.
			     (PUSH (LIST HOST-NAME
					 (SUBSTRING STR 1	;Please don't search for the space!
						    (STRING-SEARCH-SET '(#/CR) STR 1)))
				   FREE)))
		    (RETURN-PKT PKT)))
		(SETQ ELEMS (DELQ ELEM ELEMS))
		(CLOSE-CONN CONN))
	      (AND CONN (REMOVE-CONN CONN)))))
	(OR ELEMS (RETURN NIL))
	(AND (> (TIME-DIFFERENCE (TIME) OLD-TIME) 240.)	;Allow 5 secs for this all
	     (RETURN NIL))			; someone can't tell time
	(PROCESS-WAIT "Finger Lispms"
		      #'(LAMBDA (OLD-TIME ELEMS)
			  (OR (> (TIME-DIFFERENCE (TIME) OLD-TIME) 240.)
			      (DO ((ELEMS ELEMS (CDR ELEMS)))
				  ((NULL ELEMS) NIL)
				(LET ((CONN (FCL-CONN1 (CAR ELEMS))))
				  (AND CONN (EQ (STATE CONN) 'RFC-SENT-STATE)
				       (RETURN T))))))
		      OLD-TIME ELEMS))
    ;; Flush all outstanding connections
    (SETQ DOWN (MAPCAR #'FCL-HOST ELEMS))
    (DOLIST (ELEM ELEMS)
      (LET ((CONN (FCL-CONN1 ELEM)))
	(AND CONN (REMOVE-CONN (FCL-CONN1 ELEM))))))
  ;; Print which machines responded that they are free.
  (AND PRINT-FREE
       (COND ((NULL FREE)
	      (FORMAT STREAM "~18@T ~2&No Free Lisp machines.~%"))
	     (T
	      (FORMAT STREAM "~18@T ~2&Free Lisp machines: ~2%")
	      (DOLIST (ENTRY FREE)
		(FORMAT:OSTRING (CAR ENTRY) 18.)
		(FORMAT STREAM "~A~&" (CADR ENTRY))))))
  ;; Print which machines did not respond.
  (AND PRINT-DOWN
       (COND ((NOT (NULL DOWN))
	      (FORMAT STREAM "~18@T ~2&Lisp machines not responding: ~2%")
	      (DOLIST (ENTRY DOWN)
		(SETQ HOST (THIRD (SEND ENTRY :HOST-NAMES)))	;winning name
		(IF (NULL HOST) (SETQ HOST (SEND ENTRY :SHORT-NAME)))
		(FORMAT:OSTRING HOST 18.)
		(FORMAT STREAM "~A~&" (LISPM-FINGER-INFO HOST))))))
  (AND RETURN-FREE
       (VALUES (MAPCAR #'CAR FREE) DOWN)))

(DEFUN LIST-ALL-NET-MACHINES (SYSTEM-TYPE &AUX M MS)
  "Return a list of parsed hosts which represents all the chaos hosts with SYSTEM-TYPE."
  (DOLIST (ELEM SI:HOST-ALIST MS)
    (COND ((SETQ M (SECOND ELEM))		; Parsed already
	   (AND (SEND M :NETWORK-TYPEP :CHAOS)
		(EQUAL (SEND M :SYSTEM-TYPE) SYSTEM-TYPE)
		(PUSH M MS)))
	  ((AND (EQUAL (FOURTH ELEM) SYSTEM-TYPE)	; Not parsed yet
		(MEMQ :CHAOS (NTHCDR 6. ELEM)))
	   (PUSH (SI:PARSE-HOST (FIRST ELEM)) MS)))))
  
(DEFF FINGER-ALL-NET-LMS 'FINGER-ALL-LISPMS)

(DEFUN FIND-LISPMS-LOGGED-IN-AS-USER (USER
				      &AUX (ELEMS (MAKE-FAST-CONNECTION-LIST
						    (LIST-ALL-NET-MACHINES :LISPM)
						    "FINGER" 1))
				      (HOST-LIST ()))
  "Return a list of (host objects of) lisp machines that USER is logged into."
  (DO ((OLD-TIME (TIME)))
      (NIL)
    (DOLIST (ELEM ELEMS)
      (LET* ((CONN (FCL-CONN1 ELEM))
	     (STATE (AND CONN (STATE CONN))))
	(COND ((NEQ STATE 'RFC-SENT-STATE)	;Still waiting
	       (AND (EQ STATE 'ANSWERED-STATE)	;Got something meaningful
		    (LET* ((PKT (GET-NEXT-PKT CONN))
			   (STR (PKT-STRING PKT)))
		      (AND (STRING-EQUAL STR USER :END1 (STRING-SEARCH-CHAR #/CR STR))
			   (PUSH (FCL-HOST ELEM) HOST-LIST))
		      (RETURN-PKT PKT)))
	       (SETQ ELEMS (DELQ ELEM ELEMS))
	       (WHEN CONN
		 (CLOSE-CONN CONN)
		 (REMOVE-CONN CONN))))))
      (OR ELEMS (RETURN NIL))			; Done with all of them
      (AND (> (TIME-DIFFERENCE (TIME) OLD-TIME) 240.)	;Allow 5 secs for this all
	   (RETURN NIL))
    (PROCESS-WAIT "Finger"
		  #'(LAMBDA (OLD-TIME ELEMS)
		      (OR (> (TIME-DIFFERENCE (TIME) OLD-TIME) 240.)
			  (DO ((ELEMS ELEMS (CDR ELEMS)))
			      ((NULL ELEMS) NIL)
			    (OR (EQ (STATE (FCL-CONN1 (CAR ELEMS))) 'RFC-SENT-STATE)
				(RETURN T)))))
		  OLD-TIME ELEMS))
  ;; Flush all outstanding connections
  (DOLIST (ELEM ELEMS)
    (REMOVE-CONN (FCL-CONN1 ELEM)))
  HOST-LIST)


(DEFUN SEND-CANONICAL-TIME-PACKET (CONN TIME)
  "Send the magic N bits that represent the TIME time on connection CONN."
  (LET ((PKT (GET-PKT)))
    (SETF (PKT-NBYTES PKT) 4)
    (ASET (LDB #o0020 TIME) PKT FIRST-DATA-WORD-IN-PKT)
    (ASET (LDB #o2020 TIME) PKT (1+ FIRST-DATA-WORD-IN-PKT))
    (ANSWER CONN PKT)))

(DEFUN DECODE-CANONICAL-TIME-PACKET (PKT)
  "Convert into an integral number of 60ths of a second, the time encoded in packet PKT."
  (DPB (AREF PKT (1+ FIRST-DATA-WORD-IN-PKT))
       #o2020
       (AREF PKT FIRST-DATA-WORD-IN-PKT)))  

;;; TIME server!!
(DEFUN TIME-SERVER ()
  "The function that is called when another host asks us what the time is."
  (LET ((CONN (LISTEN "TIME")))
    (COND ((NOT (NULL TIME:*LAST-TIME-UPDATE-TIME*))
	   (SEND-CANONICAL-TIME-PACKET
	     CONN (TIME:GET-UNIVERSAL-TIME)))
	  (T (REJECT CONN "I don't know what time it is.")))))

;;;; UPTIME server!!
(DEFUN UPTIME-SERVER ()
  "The function that is called when another host asks us how long we've been up."
  (LET ((CONN (LISTEN "UPTIME")))
    (COND ((AND (NOT (NULL TIME:*LAST-TIME-UPDATE-TIME*)) (NOT (NULL TIME:*UT-AT-BOOT-TIME*)))
	   (SEND-CANONICAL-TIME-PACKET
	     CONN (* 60. (- (TIME:GET-UNIVERSAL-TIME) TIME:*UT-AT-BOOT-TIME*))))
	  (T (REJECT CONN "I either don't know what time it is or how long I've been up.")))))

(ADD-INITIALIZATION "TIME" '(TIME-SERVER) NIL 'SERVER-ALIST)
(ADD-INITIALIZATION "UPTIME" '(UPTIME-SERVER) NIL 'SERVER-ALIST)

(DEFUN HOST-UPTIME (HOST &OPTIONAL (STREAM *STANDARD-OUTPUT*) (TIMEOUT 240.) &AUX PKT TIME)
  "Print a human readable time onto stream STREAM.
Returns the uptime (an integer) if host up, NIL if host down."
  (SETQ HOST (SI:PARSE-HOST HOST))
  (UNWIND-PROTECT
      (CONDITION-CASE ()
	  (SETQ PKT (SIMPLE HOST "UPTIME" TIMEOUT))
	(SYS:REMOTE-NETWORK-ERROR
	 (IF STREAM
	     (FORMAT STREAM "Host ~A is apparently not up." HOST))
	 NIL)
	(:NO-ERROR (SETQ TIME (// (DECODE-CANONICAL-TIME-PACKET PKT) 60.))
		   (IF STREAM (TIME:PRINT-INTERVAL-OR-NEVER TIME STREAM))
		   TIME))
    (AND PKT (RETURN-PKT PKT))))

(DEFUN UPTIME (&OPTIONAL (STREAM *STANDARD-OUTPUT*) &REST HOSTS)
  "Print onto STREAM a listing of the uptimes of HOSTS, or all chaosnet hosts if HOSTS is ()."
  (POLL-HOSTS HOSTS "UPTIME" STREAM
	      #'(LAMBDA (STREAM)
		  (FORMAT STREAM "~%~8A~25A~25A" "Address" "Host name" "Uptime"))
	      #'(LAMBDA (STREAM HOST PKT)
		  (FORMAT STREAM "~&~8@<~O ~>~25A~A~%" HOST (CHAOS:HOST-DATA HOST)
			  (TIME:PRINT-INTERVAL-OR-NEVER
			    (// (DECODE-CANONICAL-TIME-PACKET PKT) 60.) NIL)))
	      :IGNORE-STATES '(CLS-RECEIVED-STATE)
	      :WHOSTATE "Uptime reply" ))

;;; Dummy mail server, rejects all incoming mail
;;; It really should be more clever, and notify the user of something...
(DEFUN DUMMY-MAIL-SERVER (&AUX CONN STREAM RCPT)
  (SETQ CONN (LISTEN "MAIL"))
  (ACCEPT CONN)
  (SETQ STREAM (MAKE-STREAM CONN))
  (CONDITION-CASE ()
      (DO-FOREVER				;Read the rcpts
	(SETQ RCPT (SEND STREAM :LINE-IN NIL))
	(AND (ZEROP (STRING-LENGTH RCPT))	;Blank line = start text
	     (RETURN))
	(SEND STREAM :LINE-OUT
	      ;; "-" as first char indicates failure to sender
	      "-Lisp Machines do not accept mail, maybe you want the :LMSEND command.")
	(SEND STREAM :FORCE-OUTPUT))
    (SYS:REMOTE-NETWORK-ERROR NIL))
  (CLOSE-CONN CONN "all rcpts read"))

(ADD-INITIALIZATION "MAIL" '(PROCESS-RUN-FUNCTION "MAIL Server" 'DUMMY-MAIL-SERVER)
		    NIL 'SERVER-ALIST)

;;;; Remote disk facilities.

(ADD-INITIALIZATION "REMOTE-DISK"
		    '(PROCESS-RUN-FUNCTION "REMOTE-DISK Server" 'REMOTE-DISK-SERVER)
		    NIL 'SERVER-ALIST)

(DEFUN REMOTE-DISK-SERVER (&AUX CONN STREAM LINE CMD CMDX UNIT BLOCK N-BLOCKS RQB
				BLOCK-PKT-1 BLOCK-PKT-2 BLOCK-PKT-3)
  (SETQ CONN (LISTEN "REMOTE-DISK" 25.))
  (IF (SYMBOLICS-CONNECTION-P CONN)
      (SYMBOLICS-REJECT CONN)
    (UNWIND-PROTECT
      (CONDITION-CASE ()
	(PROGN
	  (ACCEPT CONN)
	  (SEND TV:WHO-LINE-FILE-STATE-SHEET :ADD-SERVER CONN "REMOTE-DISK")
	  (SETQ STREAM (MAKE-STREAM CONN))
	  (DO-FOREVER
	    (PROCESS-WAIT "Net Input" #'(LAMBDA (CONN) (OR (READ-PKTS CONN)
							   (NEQ (STATE CONN) 'OPEN-STATE)))
				 CONN)
	    (AND (NEQ (STATE CONN) 'OPEN-STATE) (RETURN NIL))
	    (SETQ LINE (READLINE STREAM)		;Get a command line
		  CMDX (STRING-SEARCH-CHAR #/SP LINE)
		  CMD (SUBSTRING LINE 0 CMDX))
	    (COND ((OR (STRING-EQUAL CMD "READ") (STRING-EQUAL CMD "WRITE"))
		   (LET ((*READ-BASE* 10.)
			 (POS CMDX))
		     (SETF (VALUES UNIT POS)
			   (CLI:READ-FROM-STRING LINE T NIL :START POS))
		     (SETF (VALUES BLOCK POS)
			   (CLI:READ-FROM-STRING LINE T NIL :START POS))
		     (SETF (VALUES N-BLOCKS POS)
			   (CLI:READ-FROM-STRING LINE T NIL :START POS))
		     (SETQ RQB NIL))
		   (UNWIND-PROTECT
		     (PROGN (SETQ RQB (GET-DISK-RQB N-BLOCKS)
				  BLOCK-PKT-1 (GET-DISK-STRING RQB 0 484. T)
				  BLOCK-PKT-2 (GET-DISK-STRING RQB 121. 484. T)
				  BLOCK-PKT-3 (GET-DISK-STRING RQB 242. 56. T))
			    (COND ((STRING-EQUAL CMD "READ")
				   (DISK-READ RQB UNIT BLOCK)
				   ;; Give to net
				   (DO ((BLOCK BLOCK (1+ BLOCK))
					(N-BLOCKS N-BLOCKS (1- N-BLOCKS)))
				       ((ZEROP N-BLOCKS))
				     ;; Transmit three packets from block in buffer
				     (SI:TRANSMIT-PARTITION-PACKET CONN BLOCK-PKT-1)
				     (SI:TRANSMIT-PARTITION-PACKET CONN BLOCK-PKT-2)
				     (SI:TRANSMIT-PARTITION-PACKET CONN BLOCK-PKT-3)
				     ;; Advance magic strings to next block
				     (%P-STORE-CONTENTS-OFFSET
				       (+ (%P-CONTENTS-OFFSET BLOCK-PKT-1 3) (* 4 PAGE-SIZE))
				       BLOCK-PKT-1 3)
				     (%P-STORE-CONTENTS-OFFSET
				       (+ (%P-CONTENTS-OFFSET BLOCK-PKT-2 3) (* 4 PAGE-SIZE))
				       BLOCK-PKT-2 3)
				     (%P-STORE-CONTENTS-OFFSET
				       (+ (%P-CONTENTS-OFFSET BLOCK-PKT-3 3) (* 4 PAGE-SIZE))
				       BLOCK-PKT-3 3)))
				  (T
				   ;; Get from net
				   (DO ((BLOCK BLOCK (1+ BLOCK))
					(N-BLOCKS N-BLOCKS (1- N-BLOCKS)))
				       ((ZEROP N-BLOCKS))
				     ;; Get 3 packets and form a block in the buffer
				     ;; RECEIVE-PARTITION-PACKET will throw if it gets to eof.
				     (SI:RECEIVE-PARTITION-PACKET CONN BLOCK-PKT-1)
				     (SI:RECEIVE-PARTITION-PACKET CONN BLOCK-PKT-2)
				     (SI:RECEIVE-PARTITION-PACKET CONN BLOCK-PKT-3)
				     ;; Advance magic strings to next block
				     (%P-STORE-CONTENTS-OFFSET
				       (+ (%P-CONTENTS-OFFSET BLOCK-PKT-1 3) (* 4 PAGE-SIZE))
				       BLOCK-PKT-1 3)
				     (%P-STORE-CONTENTS-OFFSET
				       (+ (%P-CONTENTS-OFFSET BLOCK-PKT-2 3) (* 4 PAGE-SIZE))
				       BLOCK-PKT-2 3)
				     (%P-STORE-CONTENTS-OFFSET
				       (+ (%P-CONTENTS-OFFSET BLOCK-PKT-3 3) (* 4 PAGE-SIZE))
				       BLOCK-PKT-3 3))
				   (DISK-WRITE RQB UNIT BLOCK))))
		     (AND BLOCK-PKT-3 (RETURN-ARRAY BLOCK-PKT-3))
		     (AND BLOCK-PKT-2 (RETURN-ARRAY BLOCK-PKT-2))
		     (AND BLOCK-PKT-1 (RETURN-ARRAY BLOCK-PKT-1))
		     (RETURN-DISK-RQB RQB)))
		  ((STRING-EQUAL CMD "SAY")
		   (PROCESS-RUN-FUNCTION "Notify" 'TV:NOTIFY
					 NIL "REMOTE-DISK-SERVER:~A"
					 (SUBSTRING LINE CMDX))))))
	(SYS:REMOTE-NETWORK-ERROR))
      (AND CONN (REMOVE-CONN CONN)))))

;;;; Babel server
(DEFVAR *BABEL-STRING*
	" !/"#$%&'()*+,-.//0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}"
  "This is the string which we send out over and over during the BABEL server.")

(DEFUN BABEL-SERVER (&AUX CONN STREAM)
	"Gives the same characters to a connection over and over.
Useful for debugging chaosnet."
  (SETQ CONN (LISTEN "BABEL"))
  (ACCEPT CONN)
  (SETQ STREAM (MAKE-STREAM CONN))
  (CONDITION-CASE ()
      (DO-FOREVER
	(FORMAT STREAM *BABEL-STRING*)
	(SEND STREAM :FORCE-OUTPUT))
    (SYS:REMOTE-NETWORK-ERROR (CLOSE-CONN CONN))))

(ADD-INITIALIZATION "BABEL"
		    '(PROCESS-RUN-FUNCTION "Babel Server" 'BABEL-SERVER)
		    NIL 'SERVER-ALIST)

;;;; for the spell server
(DEFUN UP-SPELL-HOST (&OPTIONAL ERROR-OK (TIMEOUT 240.))
  "Return any host that is up which supports the spell protocol.
If no such host, signal an error, unless ERROR-OK is T."
  (LET ((UP-HOST (UP-HOSTS (GET-SITE-OPTION :SPELL-SERVER-HOSTS) 1 TIMEOUT)))
    (AND (NULL UP-HOST)
	 (NOT ERROR-OK)
	 (FERROR 'SYS:NO-SERVER-UP "No host which supports the spell protocol is up now."))
    (CAR UP-HOST)))

(DEFUN CHECK-SPELLING-WORDLIST (WORDLIST &OPTIONAL HOST)
  "Ask a host about the spelling of each of the words in wordlist."
  (LET ((CONN (CONNECT (IF (NULL HOST) (UP-SPELL-HOST) HOST) "SPELL")))
    (SEND-STRING CONN WORDLIST) ;send it our stuff
    (PROCESS-WAIT "Dictionary" #'DATA-AVAILABLE CONN)
    (LET* ((PKT (GET-NEXT-PKT CONN))
	   (INFO (STRING-APPEND (PKT-STRING PKT)))) ;the data part of the packet
      (RETURN-PKT PKT) 
      (CLOSE-CONN CONN)
      INFO)))


;;;; Frobbing routing tables

;;; Routing table format: for N subnets, N*4 bytes of data, holding N*2 words
;;; For subnet n, pkt[2n] has the method; if this is less than 400 (octal), it's
;;; an interface number; otherwise, it's a host which will forward packets to that
;;; subnet.  pkt[2n+1] has the host's idea of the cost.

(DEFUN FORMAT-ROUTING-TABLE-PKT (PKT &OPTIONAL (STREAM *STANDARD-OUTPUT*)
				 &AUX METHOD COST (I first-data-word-in-pkt))
  (FORMAT STREAM "~%Subnet   Method                Cost~%")
  (DOTIMES (SUBNET (- (TRUNCATE (PKT-NWORDS PKT) 2) first-data-word-in-pkt))
     (SETQ METHOD (AREF PKT I))
     (INCF I)
     (SETQ COST (AREF PKT I))
     (INCF I)
     (AND (NOT (ZEROP METHOD)) (> MAXIMUM-ROUTING-COST COST)
	  (FORMAT STREAM "~3O      ~A~28T~6D~%"
		  SUBNET
		  (IF (< METHOD #o400) (FORMAT NIL "Interface ~D" METHOD)
		    (HOST-DATA METHOD))
		  COST))))

(DEFUN SHOW-ROUTING-TABLE (HOST &OPTIONAL (STREAM *STANDARD-OUTPUT*) &AUX PKT)
  (UNWIND-PROTECT
      (CONDITION-CASE (E) (SETQ PKT (SIMPLE HOST "DUMP-ROUTING-TABLE"))
	(SYS:NETWORK-ERROR
	 (SEND STREAM :FRESH-LINE)
	 (SEND STREAM :STRING-OUT "Network error: ")
	 (SEND E :REPORT STREAM))
	(:NO-ERROR
	 (FORMAT-ROUTING-TABLE-PKT PKT STREAM)))
    (AND PKT (RETURN-PKT PKT))))

(DEFUN SHOW-ROUTING-PATH (&KEY (FROM SI:LOCAL-HOST) TO (STREAM *STANDARD-OUTPUT*) (TO-HOST TO)
			  &AUX METHOD-AS-HOST PKT)
  "Show how packets would most likely from a host to TO.
The required TO argument can be a ChaosNet host/address or a subnet number."
  (OR (AND (NUMBERP TO) (< TO #2r11111111))
      (SETQ TO (LDB #o1010 (CHAOS:ADDRESS-PARSE TO))))
  (UNWIND-PROTECT
      (CONDITION-CASE (E)
	  (SETQ PKT (SIMPLE FROM "DUMP-ROUTING-TABLE"))
	(SYS:NETWORK-ERROR
	 (FORMAT STREAM "~&Network error: ")
	 (SEND E :REPORT STREAM))
	(:NO-ERROR
	 (LET ((METHOD (AREF PKT (+ FIRST-DATA-WORD-IN-PKT (* 2 TO))))
	       (COST (AREF PKT (+ FIRST-DATA-WORD-IN-PKT 1 (* 2 TO)))))
	   (COND ((OR (ZEROP METHOD)
		      ( TO (TRUNCATE (PKT-NBYTES PKT) 4)))
		  (FORMAT STREAM "~&No routing table entry for subnet ~O in ~A."
			  TO (HOST-DATA FROM)))
		 ((< METHOD #o400)
		  (FORMAT STREAM
		   "~&Direct path from ~A to host ~A on subnet ~O at interface ~D."
		   (HOST-DATA FROM) TO-HOST TO METHOD))
		 (T
		  (FORMAT STREAM "~&~A will bounce the packet off ~A at cost ~D."
			  (HOST-DATA FROM) (HOST-DATA METHOD) COST)
		  (SETQ METHOD-AS-HOST METHOD))))))
    (AND PKT (RETURN-PKT PKT)))
  (IF METHOD-AS-HOST (SHOW-ROUTING-PATH :FROM METHOD-AS-HOST :TO TO :TO-HOST TO-HOST
					:STREAM STREAM)))
  
(DEFUN DUMP-ROUTING-TABLE (&AUX (PKT (GET-PKT))
				(N-SUBNETS (MIN (ARRAY-LENGTH ROUTING-TABLE)
						(TRUNCATE MAX-DATA-WORDS-PER-PKT 2))))
  (DO ((SUBNET 0 (1+ SUBNET))
       (PKT-IDX FIRST-DATA-WORD-IN-PKT))
      ((= SUBNET N-SUBNETS))
    (SETF (AREF PKT PKT-IDX) (AREF ROUTING-TABLE SUBNET))
    (INCF PKT-IDX)				; deposit cost in next word
    (SETF (AREF PKT PKT-IDX) (AREF ROUTING-TABLE-COST SUBNET))
    (INCF PKT-IDX))
  (SETF (AREF PKT (+ FIRST-DATA-WORD-IN-PKT (* MY-SUBNET 2))) 1) ; Interface 1
  (SETF (AREF PKT (+ FIRST-DATA-WORD-IN-PKT 1 (* MY-SUBNET 2))) 15.)
  ;; set the number of bytes before actually sending....
  (SETF (PKT-NBYTES PKT) (* 4 N-SUBNETS))
  (ANSWER (LISTEN "DUMP-ROUTING-TABLE") PKT))

(ADD-INITIALIZATION "DUMP-ROUTING-TABLE" '(DUMP-ROUTING-TABLE) () 'SERVER-ALIST)

(DEFUN DISALLOW-CONNECTION? (WHAT CONN FASCISM-LEVEL)
  "Return a string explaining why someone can't use the server, or NIL if its allowed."
  (IF (MEMQ :NOTIFY FASCISM-LEVEL)
      (PROCESS-RUN-FUNCTION "Notify" 'TV:NOTIFY
			    NIL "Attempt to use ~A server by the user at ~A"
			    WHAT (HOST-SHORT-NAME (FOREIGN-ADDRESS CONN))))
  (COND ((AND (SYMBOLICS-CONNECTION-P CONN) (MEMQ :REJECT-SYMBOLICS FASCISM-LEVEL))
	 (FORMAT NIL "Symbolics personnel are not privileged enough to use ~A servers."
		 WHAT))
	((AND (MEMQ :NOT-LOGGED-IN FASCISM-LEVEL)
	      (SYS:MEMBER-EQUAL USER-ID '(NIL "")))
	 NIL)					;go ahead
	((MEMQ T FASCISM-LEVEL)
	 NIL)					;this is a winner
	(T
	 (IF (MEMQ :NOT-LOGGED-IN FASCISM-LEVEL)
	     (FORMAT NIL "This machine is in use by ~A, try again later." USER-ID)
	     (FORMAT NIL "Fascism at this site prevents the usage of the ~A server." WHAT)))))

;;; Values can be T, :NOTIFY, or NIL
(DEFVAR EVAL-SERVER-ON T
  "T => allow EVAL server requests; :NOTIFY => allow them but notify the user.")
(DEFVAR EVAL-SERVER-CONNECTIONS NIL)

;;; Call this if you want to enable the eval server on your machine
(DEFUN EVAL-SERVER-ON (&OPTIONAL (MODE T))
  "Allow remote connections to this machine's EVAL server.
If mode is :NOTIFY, you will be notified whenever an EVAL server is created."
  (SETQ EVAL-SERVER-ON MODE))

(DEFUNP EVAL-SERVER-FUNCTION (&AUX CONN)
  (SETQ CONN (LISTEN "EVAL"))
  (COND ((AND (NULL EVAL-SERVER-ON)
		  
	      (NOT (SYS:MEMBER-EQUAL USER-ID '(NIL ""))))
	 (REJECT CONN (FORMAT NIL "This machine is in use by ~A" USER-ID))
	 (RETURN NIL))
	((AND (SYMBOLICS-CONNECTION-P CONN T)
	      (SYS:MEMBER-EQUAL USER-ID '(NIL "")))
	 (SYMBOLICS-REJECT CONN)
	 (RETURN NIL))
	((EQ EVAL-SERVER-ON :NOTIFY)
	 (PROCESS-RUN-FUNCTION "Notify" 'TV:NOTIFY
			       NIL "Use of EVAL server by ~A"
			       (HOST-SHORT-NAME (FOREIGN-ADDRESS CONN)))
	 (PROCESS-ALLOW-SCHEDULE)
	 (ACCEPT CONN))
	(T (ACCEPT CONN)))
  (PUSH CONN EVAL-SERVER-CONNECTIONS)
  (SEND TV:WHO-LINE-FILE-STATE-SHEET :ADD-SERVER CONN "EVAL")
  (CATCH-ERROR
    (WITH-OPEN-STREAM (STREAM (MAKE-STREAM CONN :ASCII-TRANSLATION T))
      ;; Flush any number of telnet negotiations.  (We only understand the simplest kind).
      (DO-FOREVER
	(LET ((CH (TYI STREAM)))
	  (IF (= CH #o377)
	      (PROGN (TYI STREAM) (TYI STREAM))
	    (RETURN (SEND STREAM :UNTYI CH)))))
      (DO ((*TERMINAL-IO* STREAM)
	   (INPUT))
	  (NIL)
	(AND (EQ (SETQ INPUT (READ STREAM 'QUIT)) 'QUIT)
	     (RETURN NIL))
	(CATCH-ERROR (PRIN1 (MULTIPLE-VALUE-LIST (EVAL INPUT))) T)
	(WRITE-CHAR #/NEWLINE STREAM)
	(SEND STREAM :FORCE-OUTPUT)))
    NIL))

(ADD-INITIALIZATION "EVAL"
                    '(PROCESS-RUN-FUNCTION "EVAL Server" 'EVAL-SERVER-FUNCTION)
                    NIL
                    'SERVER-ALIST)

;; Values can be T, :NOT-LOGGED-IN :NOTIFY NIL
(DEFVAR TELNET-SERVER-ON T
  "T => always allow TELNET server requests, :NOTIFY => allow them but notify the user
 NIL means never to allow them and :not-logged-in means allow them wehn no-one is logged in.")

	 
(DEFUN TELNET-SERVER-FUNCTION (&AUX CONN)
  (SETQ CONN (LISTEN "TELNET"))
  (LET ((LOSE (DISALLOW-CONNECTION? "TELNET" CONN
				    (LIST TELNET-SERVER-ON :REJECT-SYMBOLICS))))
    (WHEN LOSE
      (REJECT CONN LOSE)
      (RETURN-FROM TELNET-SERVER-FUNCTION NIL))
    (ACCEPT CONN)
    (PUSH CONN EVAL-SERVER-CONNECTIONS)
    (SEND TV:WHO-LINE-FILE-STATE-SHEET :ADD-SERVER CONN "TELNET")
    (CONDITION-CASE ()
	(LET ((UNTYI-CHAR NIL))
	  (DECLARE (SPECIAL UNTYI-CHAR))
	  (WITH-OPEN-STREAM (STREAM (MAKE-STREAM CONN :ASCII-TRANSLATION T))
	    (DECLARE (SPECIAL STREAM))
	    (PRINT-HERALD STREAM)
	    (FORMAT STREAM "~&Telnet server here~2%")
	    (SEND STREAM :FORCE-OUTPUT)
	    ;; Flush any number of telnet negotiations.  (We only understand the simplest kind).
	    (DO-FOREVER
	      (LET ((CH (SEND STREAM :TYI)))
		(IF (= CH #o377)
		    (PROGN (SEND STREAM :TYI) (SEND STREAM :TYI))
		    (RETURN (SEND STREAM :UNTYI CH)))))
	    (SI:LISP-TOP-LEVEL1 (CLOSURE '(STREAM UNTYI-CHAR) 'ECHOING-STREAM))))
      (SYS:REMOTE-NETWORK-ERROR NIL))))

(ADD-INITIALIZATION "TELNET"
                    '(PROCESS-RUN-FUNCTION "TELNET Server" 'TELNET-SERVER-FUNCTION)
                    NIL
                    'SERVER-ALIST)

(DEFVAR RECORD-STREAM NIL)

(DEFVAR *TELNET-OUTPUT-TRANSLATION-TABLE* ; for 32 random LM-characters
	#("." "v" "a" "b" "^" "~" "e" "p"
	  "l" "g" "d" "^" "+-" "+" "infty" "d"
	  "<" ">" "^" "v" "A" "E" "x" "<->"
	  "<-" "->" "//=" "$" "<=" "=>" "=" "v"))

(DEFVAR *ENABLE-TELNET-OUTPUT-TRANSLATION* T)

(DEFUN ECHOING-STREAM (OP &REST ARGS)
  (DECLARE (SPECIAL STREAM UNTYI-CHAR))
  (CONDITION-CASE ()
      (CASE OP
	(:TYI
	 (OR (PROG1 UNTYI-CHAR (SETQ UNTYI-CHAR NIL))
	     (LET (CH)
	       (SEND STREAM :FORCE-OUTPUT)
	       (SETQ CH (SEND STREAM :TYI))
	       (IF RECORD-STREAM (SEND RECORD-STREAM :TYO CH))
	       (IF (> CH #O37) (SEND STREAM :TYO CH)
		 (SETQ CH (SET-CHAR-BIT (LOGIOR #O100 CH) :CONTROL 1))
		 (SEND STREAM :STRING-OUT "c-")
		 (SEND STREAM :TYO (CHAR-CODE CH)))
	       CH)))
	(:UNTYI (SETQ UNTYI-CHAR (CAR ARGS)))
	(:READ-CURSORPOS (VALUES 0 0))
	(:TYO
	 (LET ((C (CAR ARGS)))
	   (COND ((NOT *ENABLE-TELNET-OUTPUT-TRANSLATION*) (SEND STREAM :TYO C))
		 ((> C #O37) (SEND STREAM :TYO C))
		 (T (SEND STREAM :STRING-OUT (AREF *TELNET-OUTPUT-TRANSLATION-TABLE* C))))))
	(OTHERWISE (LEXPR-SEND STREAM OP ARGS)))
    (SYS:REMOTE-NETWORK-ERROR
     (PROCESS-RUN-FUNCTION "Kill"
			   CURRENT-PROCESS :KILL)
     (PROCESS-WAIT "Die" 'FALSE))))

(DEFUN SYMBOLICS-CONNECTION-P (CONN &OPTIONAL REJECT-UNKNOWN-HOSTS)
  (LET ((HOST (CATCH-ERROR (SI:GET-HOST-FROM-ADDRESS (FOREIGN-ADDRESS CONN) :CHAOS) NIL)))
    (IF HOST
	(OR (STRING-EQUAL (SEND HOST :NAME) "SCRC" :END1 4)
	    (STRING-EQUAL (SEND HOST :NAME) "SPA" :END1 3)
	    (STRING-EQUAL (SEND HOST :NAME) "SWW" :END1 3)
	    (STRING-EQUAL (SEND HOST :NAME) "SCH" :END1 3))
      (OR REJECT-UNKNOWN-HOSTS
	  (AND (SI:PARSE-HOST "SCRC-TENEX" T)	;In case some chaosnet not at MIT.
	       (MEMQ (LDB 1010 (FOREIGN-ADDRESS CONN))
		     '#o(36 37 40 41 42 43 44 45 46 51 52 53)))))
    NIL))

;;; Another winning feature copied from Symbolics (DLA 5/19/82).
(DEFUN SYMBOLICS-REJECT (CONN)
  (REJECT CONN "Sorry, service not available: microwave apparently down."))

(DEFVAR LAST-NOTIFICATION NIL
  "This variable contains the last string which was a notification for another chaos host.
If you want an older notification, try looking in TV:NOTIFICATION-HISTORY")

(DEFUN NOTIFY-SERVER ()
  (LET* ((CONN (LISTEN "NOTIFY"))
	 (PKT (READ-PKTS CONN))
	 (PKT-STRING (SUBSTRING (PKT-STRING PKT) 7))
	 (HOST (FOREIGN-ADDRESS CONN))
	 (INHIBIT-SCHEDULING-FLAG T))
    (COND ((OR (NULL LAST-NOTIFICATION)
	       (NOT (STRING-EQUAL LAST-NOTIFICATION PKT-STRING)))
	   (SETQ LAST-NOTIFICATION PKT-STRING)
	   (SETQ INHIBIT-SCHEDULING-FLAG NIL)
	   (SETQ HOST (OR (SI:GET-HOST-FROM-ADDRESS HOST :CHAOS)
			  (FORMAT NIL "chaos host ~O" HOST)))
	   (TV:NOTIFY NIL "From ~A: ~A" HOST PKT-STRING))
	  (T (RETURN-ARRAY (PROG1 PKT-STRING (SETQ PKT-STRING NIL)))))
    (ANSWER-STRING CONN "Done")))

(ADD-INITIALIZATION "NOTIFY" '(NOTIFY-SERVER) NIL 'SERVER-ALIST)

(DEFUN NOTIFY (HOST &OPTIONAL (MESSAGE (NOTIFY-GET-MESSAGE)))
  "Send a brief message MESSAGE to HOST.  It is printed as a notification.
If MESSAGE is omitted, it is read from the terminal."
  (LET ((PKT (SIMPLE HOST (STRING-APPEND "NOTIFY " MESSAGE))))
    (IF (STRINGP PKT) PKT
	(PROG1 (STRING-APPEND (PKT-STRING PKT))
	       (RETURN-PKT PKT)))))

(DEFUN NOTIFY-ALL-LMS (&OPTIONAL (MESSAGE (NOTIFY-GET-MESSAGE)) &AUX CONNS)
  "Send a brief message MESSAGE to all Lisp machines.  It is printed as a notification.
If MESSAGE is omitted, it is read from the terminal."
  (ASSURE-ENABLED)
  (UNWIND-PROTECT
    (PROGN (LOOP WITH CONTACT = (STRING-APPEND "NOTIFY " MESSAGE)
		 FOR (HOST) IN SI:MACHINE-LOCATION-ALIST
		 AS ADDRESS = (ADDRESS-PARSE HOST)
		 WHEN ADDRESS DO (PUSH (OPEN-CONNECTION ADDRESS CONTACT) CONNS))
	   (PROCESS-WAIT-WITH-TIMEOUT "Notify" (* 5 60.)
	     #'(LAMBDA (CONNS)
		 (LOOP FOR CONN IN CONNS ALWAYS (NEQ (STATE CONN) 'RFC-SENT-STATE)))
	     CONNS)
	   (LOOP FOR CONN IN CONNS
		 AS STATE = (STATE CONN)
		 DO (FORMAT T "~%~A: ~A" 
			    (SI:GET-HOST-FROM-ADDRESS (FOREIGN-ADDRESS CONN) :CHAOS)
			    (CASE STATE
			      (ANSWERED-STATE (PKT-STRING (READ-PKTS CONN)))
			      (RFC-SENT-STATE "Host not responding")
			      (OTHERWISE (FORMAT NIL "Connection in ~A?" STATE))))))
    (MAPC #'CHAOS:REMOVE-CONN CONNS)))

(DEFUN NOTIFY-GET-MESSAGE (&OPTIONAL STREAM)
  (FORMAT T "~&Message: (terminate with End)~%")
  (ZWEI:QSEND-GET-MESSAGE STREAM
			  (FORMAT NIL
"You are typing in a message which will be send to someone on another chaosnet machine.
If you want to quit, hit the ~:@C key, to end your message hit the ~:@C key."
#/ABORT #/END)))


;;;; Debugging Stuff

(DEFUN CD-SEND ( &AUX PKT)
  (DISABLE)
  (SETQ PKT (ALLOCATE-PKT))
  (TERPRI) (TERPRI)
  (SETF (PKT-OPCODE PKT) (PROMPT-AND-READ :EVAL-READ "~&Opcode: "))
  (SETF (PKT-DEST-ADDRESS PKT) (PROMPT-AND-READ :NUMBER "~&Destination: "))
  (SETF (PKT-DEST-INDEX-NUM PKT) (PROMPT-AND-READ :NUMBER "~&Destination index: "))
  (SETF (PKT-SOURCE-ADDRESS PKT) (PROMPT-AND-READ :NUMBER "~&Source address: "))
  (SETF (PKT-SOURCE-INDEX-NUM PKT) (PROMPT-AND-READ :NUMBER "~&Source index: "))
  (SETF (PKT-NUM PKT) (PROMPT-AND-READ :NUMBER "~&Packet number: "))
  (SETF (PKT-ACK-NUM PKT) (PROMPT-AND-READ :NUMBER "~&Ack packet number: "))
  (SETF (PKT-FWD-COUNT PKT) (PROMPT-AND-READ :NUMBER "~&Forwarding count: "))
  (SET-PKT-STRING PKT (PROMPT-AND-READ :STRING "~&Data (a string): "))
  (TRANSMIT-INT-PKT (CONVERT-TO-INT-PKT PKT))
  (FREE-PKT PKT))

(DEFUN CD-RECEIVE ( &AUX PKT)
  (DISABLE)
  (SETQ PKT (CONVERT-TO-PKT (RECEIVE-PROCESS-NEXT-INT-PKT)))
  (COND (PKT (PRINT-PKT PKT))
	(T NIL)))

(DEFUN SOAK (CONN &AUX PKT)
  (AND (NUMBERP CONN) (SETQ CONN (AREF INDEX-CONN CONN)))
  (SETQ PKT (GET-NEXT-PKT CONN))
  (COND ((= (PKT-OPCODE PKT) CLS-OP)
	 (FORMAT T "==> CLOSED!!! <===  ~S" (PKT-STRING PKT)))
	(PKT
	 (PRINT-PKT PKT)))
  (AND PKT (FREE-PKT PKT)))

(DEFUN SETUP (&OPTIONAL (CNAME "FOO"))
  (DECLARE (SPECIAL C L))
  (ENABLE)
  (SETQ C (OPEN-CONNECTION MY-ADDRESS CNAME))
  (SETQ L (LISTEN CNAME 5 NIL))
  (WAIT L 'LISTENING-STATE (* 10. 60.) "Listen")
  (IF (EQ (STATE L) 'LISTENING-STATE)
      (FORMAT T "Lost")
    (ACCEPT L))
  (PEEK 'K))

;;;; Stuff for PEEK.

(DEFVAR PEEK-SHORT-PKT-DISPLAY T
  "Display packets in short form in peek")

(DEFUN PEEK-DISPLAY (&AUX CONN)
  (FORMAT T "~&ChaosNet Status: ~O" (TIME))
  (FORMAT T (COND (ENABLE "   Active!~%")
		  (T "   Deactivated.~%")))
  (DO ((I 0 (1+ I))) (( I (ARRAY-LENGTH INDEX-CONN)))
    (COND ((ARRAYP (SETQ CONN (AR-1 INDEX-CONN I)))
	   (PRINT-CONN CONN PEEK-SHORT-PKT-DISPLAY)
	   (TERPRI))))
  (FORMAT T "~2%Forwarded: ~O  Overforwarded: ~O  Lost: ~O   Made: ~O  Free: ~O (+~O Recorded LOS packets)~%"
	  PKTS-FORWARDED PKTS-OVER-FORWARDED PKTS-LOST PKTS-MADE
	  (DO ((I 0 (1+ I))
	       (FP FREE-PKTS (PKT-LINK FP)))
	      ((SYMBOLP FP) I))
	  CURRENT-LOS-PKT-COUNT)
  (FORMAT T "Bad Destination: ~O   Bad Bit Count: ~O   Bad CRC-1: ~O  Bad CRC-2: ~O~%"
	  PKTS-BAD-DEST PKTS-BAD-BIT-COUNT PKTS-BAD-CRC-1 PKTS-BAD-CRC-2)
  (WHEN PENDING-LISTENS
    (FORMAT T "~%Pending LISTENs:~%")
    (DO ((L PENDING-LISTENS (CDR L))) ((NULL L))
	(FORMAT T "   Contact name: ~S~%" (CAR L))))
  (WHEN PENDING-RFC-PKTS
    (FORMAT T "~%Pending RFCs:~%")
    (DO ((PKT PENDING-RFC-PKTS (PKT-LINK PKT))) ((NULL PKT))
	(FORMAT T "   Contact name: ~S~%" (PKT-STRING PKT)))))

(DEFUN PRINT-BAD-PKTS ()
  (DO ((LIST BAD-PKT-LIST (CDR LIST)))
      ((NULL LIST))
    (FORMAT T "~&~A" (CAAR LIST))
    (PRINT-PKT (CADAR LIST))
    (TERPRI)))

(DEFUN PRINT-RECENT-HEADERS ( &OPTIONAL (NBR #o200))
  (DO ((I (\ (+ #o177 RECENT-HEADERS-POINTER) #o200) (IF (ZEROP I) #o177 (1- I)))
       (COUNT NBR (1- COUNT)))
      ((ZEROP COUNT))
    (FORMAT T "~%Nbr:~O Opcd:~O(~A). Len:~O bytes. "
	    (RCNT-PKT-NUM I)
	    (RCNT-OPCODE I)
	    (COND ((< (RCNT-OPCODE I) (LENGTH OPCODE-LIST))
		   (NTH (RCNT-OPCODE I) OPCODE-LIST))
		  (( (RCNT-OPCODE I) DAT-OP) 'DAT)
		  (T (FORMAT NIL "==> ~O <==" (RCNT-OPCODE I))))
	    (RCNT-NBYTES I))
    (FORMAT T "From ~O-~O to ~O-~O, Fwded ~O Times, Rcrded:~O"
	    (RCNT-SOURCE-ADDRESS I) (RCNT-SOURCE-INDEX I)
	    (RCNT-DEST-ADDRESS I) (RCNT-DEST-INDEX I)
	    (RCNT-FWD-COUNT I) (RCNT-TIME-RECORDED I))))

(DEFUN PRINT-ROUTING-TABLE (&OPTIONAL (STREAM *STANDARD-OUTPUT*))
  "Display onto STREAM a list of subnets, gateways, and chaonet costs for each subnet."
  (FORMAT STREAM "~&Subnet	Fastest Gateway~35TCost")
  (DOTIMES (I (ARRAY-LENGTH ROUTING-TABLE))
    (IF (= MY-SUBNET I) 
	(FORMAT STREAM "~&~3O          Direct" MY-SUBNET)
      (WHEN (< (CLI:AREF ROUTING-TABLE-COST I) #o1000)
	(LET ((GATEWAY (AREF ROUTING-TABLE I)))
	  (FORMAT STREAM "~&~3O	~O ~A~35T~O"
		  I GATEWAY (HOST-DATA GATEWAY)
		  (AREF ROUTING-TABLE-COST I)))))))
  
;;; Prints as much info as possible
(DEFUN DUMP-GUTS ( &AUX (PEEK-SHORT-PKT-DISPLAY NIL))
  (PEEK-DISPLAY)
  (FORMAT T "~2%Recent headers:")
  (PRINT-RECENT-HEADERS))


;;;; Host table frobs

(DEFUN GENERATE-HOST-TABLE (&OPTIONAL INPUT-FILE)
  (LET ((DEFAULT-INPUT-FILE "SYS: CHAOS; HOSTS TEXT >")
	(SI:*FORCE-PACKAGE* "CHAOS"))
    (COND ((AND (NOT INPUT-FILE)		;if not specified 
		(NOT (PROBEF DEFAULT-INPUT-FILE)))	;and reasonable file doesn't exist
	   (FORMAT *QUERY-IO* "~&Default host table input file not found.")
	   (SETQ INPUT-FILE (PROMPT-AND-READ `(:PATHNAME :DEFAULTS ,DEFAULT-INPUT-FILE)
					     "Please specify file to use instead: ")))
	  (T
	   (IF (NOT INPUT-FILE) (SETQ INPUT-FILE DEFAULT-INPUT-FILE))))
    (GENERATE-HOST-TABLE-1 INPUT-FILE "SYS: SITE; HSTTBL LISP >")))

;;; System system transformation
(DEFUN GENERATE-HOST-TABLE-1 (INPUT-FILE OUTPUT-FILE)
  (LET ((*PACKAGE* (FIND-PACKAGE "CHAOS"))
	(*READ-BASE* 8) (*PRINT-BASE* 8) (*PRINT-RADIX* T)
	(*READTABLE* SI:STANDARD-READTABLE))
    (WITH-OPEN-FILE (OUTPUT-STREAM OUTPUT-FILE :DIRECTION :OUTPUT :CHARACTERS T)
      (FORMAT OUTPUT-STREAM "~
;;; -*- Mode: LISP;~@[ Package: ~A;~] Base: 8; Readtable:T -*-
;;; *** THIS FILE WAS AUTOMATICALLY GENERATED BY A PROGRAM, DO NOT EDIT IT ***
;;; Host table made from ~A~%"
	      SI:*FORCE-PACKAGE* (SEND (FS:PARSE-PATHNAME INPUT-FILE) :TRUENAME))
      (SI::WRITE-RESPONSIBILITY-COMMENT OUTPUT-STREAM)
      (GENERATE-HOST-TABLE-2 INPUT-FILE OUTPUT-STREAM)
      (WHEN (GET-SITE-OPTION :NON-CHAOS-HOST-TABLE-FILE)
	(GENERATE-HOST-TABLE-2 (GET-SITE-OPTION :NON-CHAOS-HOST-TABLE-FILE)
			       OUTPUT-STREAM)))))

(DEFUN GENERATE-HOST-TABLE-2 (INPUT-FILE OUTPUT-STREAM)
  (WITH-OPEN-FILE (INPUT-STREAM INPUT-FILE :DIRECTION :INPUT :CHARACTERS T)
    (DO ((LINE) (EOF)
	 (I) (J)
	 (NI) (NJ)
	 (HOSTL) (NAMEL) (DELIM))
	(NIL)
      (MULTIPLE-VALUE (LINE EOF)
	(SEND INPUT-STREAM :LINE-IN NIL))
      (AND EOF (RETURN))
      (MULTIPLE-VALUE (I J)
	(PARSE-HOST-TABLE-TOKEN LINE 0))
      (COND ((AND I (STRING-EQUAL LINE "HOST" :START1 I :END1 J))
	     ;; Host name
	     (MULTIPLE-VALUE (NI NJ)
	       (PARSE-HOST-TABLE-TOKEN LINE (1+ J)))
	     (MULTIPLE-VALUE (I J DELIM)
	       (PARSE-HOST-TABLE-TOKEN LINE (1+ NJ)))
	     (SETQ HOSTL (NCONS (SUBSTRING LINE NI NJ)))
	     (IF (CHAR= DELIM #/[)
		 (DO ((L NIL)
		      (I1) (J1))
		     ((CHAR= DELIM #/])
		      (INCF J)
		      (NREVERSE L))
		   (MULTIPLE-VALUE (I1 J1 DELIM)
		     (PARSE-HOST-TABLE-TOKEN LINE (1+ J)))
		   (IF (CHAR= DELIM #/SP)
		       (MULTIPLE-VALUE (I J DELIM)
			 (PARSE-HOST-TABLE-TOKEN LINE (1+ J1)))
		       (SETQ I I1 J J1 J1 I1))
		   (ADD-HOST-TABLE-ADDRESS LINE I1 J1 I J HOSTL))
		 (LET ((I1 I) (J1 J))
		   (IF (= DELIM #/SP)
		       (MULTIPLE-VALUE (I J)
			 (PARSE-HOST-TABLE-TOKEN LINE (1+ J)))
		       (SETQ I I1 J J1 J1 I1))
		   (ADD-HOST-TABLE-ADDRESS LINE I1 J1 I J HOSTL)))
;	     (COND ((OR (GET HOSTL :CHAOS)	;If there were any chaosnet addresses
;			;; Include some popular ARPA sites for speed in SUPDUP/TELNET, etc.
;			(SYS:MEMBER-EQUAL (CAR HOSTL) INCLUDED-NON-CHAOS-HOSTS))
	     (DOTIMES (K 2)
	       (MULTIPLE-VALUE (I J DELIM)
		 (PARSE-HOST-TABLE-TOKEN LINE (1+ J))))
	     (WHEN I
	       (PUTPROP HOSTL (INTERN (SUBSTRING LINE I J) "") :SYSTEM-TYPE))
	     (MULTIPLE-VALUE (I J DELIM)
	       (PARSE-HOST-TABLE-TOKEN LINE (1+ J)))
	     (WHEN I
	       (PUTPROP HOSTL (INTERN (SUBSTRING LINE I J) "") :MACHINE-TYPE))
	     (MULTIPLE-VALUE (I J DELIM)
	       (PARSE-HOST-TABLE-TOKEN LINE (1+ J)))
	     (OR I (SETQ DELIM -1))
	     (SETQ NAMEL (NCONS (CAR HOSTL)))
	     (AND (CHAR= DELIM #/[)
		  (DO () ((CHAR= DELIM #/])
			  (SETQ NAMEL (STABLE-SORT NAMEL
						   #'(LAMBDA (X Y)
						       (< (STRING-LENGTH X)
							  (STRING-LENGTH Y))))))
		    (MULTIPLE-VALUE (I J DELIM)
		      (PARSE-HOST-TABLE-TOKEN LINE (1+ J)))
		    (PUSH (SUBSTRING LINE I J) NAMEL)))
	     (PUTPROP HOSTL NAMEL :HOST-NAMES)
	     (LET ((*PACKAGE* (OR (FIND-PACKAGE SI:*FORCE-PACKAGE*) *PACKAGE*)))
	       (FORMAT OUTPUT-STREAM "(~S ~S~{~%  '~S '~S~})~2%"
		       'SI::DEFINE-HOST (CAR HOSTL) (CDR HOSTL))))))))


(DEFUN PARSE-HOST-TABLE-TOKEN (STRING &OPTIONAL (START 0) END)
  (OR END (SETQ END (LENGTH STRING)))
  (DO ((IDX START (1+ IDX))
       (SIDX) (CH))
      (( IDX END)
       (VALUES SIDX IDX -1))
    (SETQ CH (CHAR STRING IDX))
    (OR SIDX
	(MEMQ CH '(#/SP #/TAB))
	(SETQ SIDX IDX))
    (AND SIDX
	 (MEMQ CH '(#/, #/SP #/TAB #/[ #/]))
	 (RETURN (VALUES SIDX IDX CH)))))

(DEFUN ADD-HOST-TABLE-ADDRESS (LINE NET-START NET-END ADDRESS-START ADDRESS-END HOSTL
			       &AUX SYMBOL PARSER)
  (SETQ SYMBOL (IF (= NET-START NET-END) :ARPA
		   (INTERN (SUBSTRING LINE NET-START NET-END) "")))
  (COND ((SETQ PARSER (GET SYMBOL 'HOST-ADDRESS-PARSER))
	 (SETF (GET HOSTL SYMBOL)		;Keep addresses in original order
	       (NCONC (GET HOSTL SYMBOL)
		      (NCONS (FUNCALL PARSER SYMBOL LINE ADDRESS-START ADDRESS-END)))))))

;;; For now, this is all we really support
(DEFUN (:CHAOS HOST-ADDRESS-PARSER) (IGNORE LINE START END)
  (ZWEI:PARSE-NUMBER LINE START END 8))

(DEFUN (:RU HOST-ADDRESS-PARSER) (IGNORE LINE START END)
  (ZWEI:PARSE-NUMBER LINE START END 8))

(DEFUN (:ARPA HOST-ADDRESS-PARSER) (IGNORE LINE START END &AUX SLASH)
  (SETQ SLASH (STRING-SEARCH-CHAR #// LINE START END))
  (DPB (ZWEI:PARSE-NUMBER LINE START SLASH) #o1110 (ZWEI:PARSE-NUMBER LINE (1+ SLASH) END)))

(DEFUN (:DIAL HOST-ADDRESS-PARSER) (IGNORE LINE START END)
  (SUBSTRING LINE START END))			;A phone number is just characters.

(DEFUN (:LCS HOST-ADDRESS-PARSER) (IGNORE LINE START END &AUX SLASH)
  (SETQ SLASH (STRING-SEARCH-CHAR #// LINE START END))
  (DPB (ZWEI:PARSE-NUMBER LINE START SLASH) #o1010 (ZWEI:PARSE-NUMBER LINE (1+ SLASH) END)))

(DEFUN (:SU HOST-ADDRESS-PARSER) (IGNORE LINE START END &AUX SHARP)
  (SETQ SHARP (STRING-SEARCH-CHAR #/# LINE START END))
  (DPB (ZWEI:PARSE-NUMBER LINE START SHARP) #o1010 (ZWEI:PARSE-NUMBER LINE (1+ SHARP) END)))

(DEFUN (:RCC HOST-ADDRESS-PARSER) (IGNORE LINE START END &AUX SLASH)
  (SETQ SLASH (STRING-SEARCH-CHAR #// LINE START END))
  (DPB (ZWEI:PARSE-NUMBER LINE START SLASH 10.)
       #o1010 (ZWEI:PARSE-NUMBER LINE (1+ SLASH) END 10.)))

(DEFUN (:INTERNET HOST-ADDRESS-PARSER) (IGNORE LINE START END)
  (SUBSTRING LINE START END))
