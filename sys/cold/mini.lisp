;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Cold-Load:T; Base:8; Readtable:ZL -*-

;;; Miniature Chaosnet program.  Only good for reading ascii and binary files.
;;; The following magic number is in this program:  #o1200
;;; It also knows the format of a packet and the Chaosnet opcodes non-symbolically

(DEFVAR MINI-PKT)
(DEFVAR MINI-PKT-STRING)
(DEFVAR MINI-FILE-ID)
(DEFVAR MINI-OPEN-P)
(DEFVAR MINI-CH-IDX)
(DEFVAR MINI-UNRCHF)
(DEFVAR MINI-LOCAL-INDEX)
(DEFVAR MINI-LOCAL-HOST)
(DEFVAR MINI-REMOTE-INDEX)
(DEFVAR MINI-REMOTE-HOST)
(DEFVAR MINI-IN-PKT-NUMBER)
(DEFVAR MINI-OUT-PKT-NUMBER)
(DEFVAR MINI-EOF-SEEN)
(DEFVAR MINI-DESTINATION-ADDRESS)
(DEFVAR MINI-ROUTING-ADDRESS)
(DEFVAR MINI-PLIST-RECEIVER-POINTER)

;This is the filename (a string) on which MINI-FASLOAD was called.
(DEFVAR MINI-FASLOAD-FILENAME)

;;; Compile time chaosnet address lookup and routing.
(DEFMACRO GET-INTERESTING-CHAOSNET-ADDRESSES ()
;;;---!!! This hard coded to OZ (with new Chaosnet address), and on
;;;---!!!    the same subnet as LM1.
  `(SETQ MINI-DESTINATION-ADDRESS #o3060
	 MINI-ROUTING-ADDRESS 6))

(GET-INTERESTING-CHAOSNET-ADDRESSES)

;;; Contact name<space>user<space>password
(DEFVAR MINI-CONTACT-NAME "MINI LISPM ")

;;; Initialization, usually only called once.
(DEFUN MINI-INIT ()
  ;; Init lists microcode looks at
  (SETF (AREF (SYMBOL-FUNCTION 'SYSTEM-COMMUNICATION-AREA) %SYS-COM-CHAOS-FREE-LIST) NIL)
  (SETF (AREF (SYMBOL-FUNCTION 'SYSTEM-COMMUNICATION-AREA) %SYS-COM-CHAOS-RECEIVE-LIST) NIL)
  (SETF (AREF (SYMBOL-FUNCTION 'SYSTEM-COMMUNICATION-AREA) %SYS-COM-CHAOS-TRANSMIT-LIST) NIL)
  ;; Fake up a packet buffer for the microcode, locations #o1200-x through #o1377
  ;; I.e. in the unused portions of SCRATCH-PAD-INIT-AREA
  (%P-STORE-TAG-AND-POINTER #o1177 DTP-ARRAY-HEADER
			    (DPB 1 %%ARRAY-NUMBER-DIMENSIONS
				 (DPB #o400 %%ARRAY-INDEX-LENGTH-IF-SHORT
				      (DPB 1 %%ARRAY-LEADER-BIT
					   ART-16B))))
  (%P-STORE-TAG-AND-POINTER #o1176 DTP-FIX (LENGTH CHAOS-BUFFER-LEADER-QS))
  (%P-STORE-TAG-AND-POINTER (- #o1176 1 (LENGTH CHAOS-BUFFER-LEADER-QS))
			    DTP-HEADER
			    (DPB %HEADER-TYPE-ARRAY-LEADER %%HEADER-TYPE-FIELD
				 (+ 2 (LENGTH CHAOS-BUFFER-LEADER-QS))))
  (SETQ MINI-PKT (%MAKE-POINTER DTP-ARRAY-POINTER #o1177))
  (SETQ MINI-PKT-STRING (MAKE-STRING #o760
				     :DISPLACED-TO #o1204)) ;Just the data part of the packet
  (OR (BOUNDP 'MINI-LOCAL-INDEX)
      (SETQ MINI-LOCAL-INDEX 0))
  (SETQ MINI-OPEN-P NIL))

;;; Get a connection to a file server
(DEFUN MINI-OPEN-CONNECTION (HOST CONTACT-NAME)
  (OR (BOUNDP 'MINI-PKT) (MINI-INIT))
  (SETQ MINI-LOCAL-HOST (%UNIBUS-READ #o764142)
	MINI-REMOTE-HOST HOST
	MINI-OUT-PKT-NUMBER 1)
  (AND (= (LDB #o1010 MINI-LOCAL-HOST) (LDB #o1010 MINI-REMOTE-HOST))
       (SETQ MINI-ROUTING-ADDRESS MINI-REMOTE-HOST))
  (INCF MINI-LOCAL-INDEX)
  (IF (= MINI-LOCAL-INDEX #o200000) (SETQ MINI-LOCAL-INDEX 1))
  (SETQ MINI-REMOTE-INDEX 0
	MINI-IN-PKT-NUMBER 0)
  (DO ((RETRY-COUNT 10. (1- RETRY-COUNT)))
      ((ZEROP RETRY-COUNT) (MINI-BARF "RFC fail"))
    ;; Store contact name into packet
    (COPY-ARRAY-CONTENTS CONTACT-NAME MINI-PKT-STRING)
    (MINI-SEND-PKT 1 (ARRAY-LENGTH CONTACT-NAME))	;Send RFC
    (WHEN (EQ (MINI-NEXT-PKT NIL) 2)		;Look for a response of OPN
      (SETQ MINI-REMOTE-INDEX (AREF MINI-PKT 5)
	    MINI-IN-PKT-NUMBER (AREF MINI-PKT 6))
      (SETQ MINI-OUT-PKT-NUMBER (1+ MINI-OUT-PKT-NUMBER))
      (MINI-SEND-STS)
      (SETQ MINI-OPEN-P T)
      (RETURN T))))				;and exit.  Otherwise, try RFC again.

;;; Send a STS
(DEFUN MINI-SEND-STS ()
  (SETF (AREF MINI-PKT #o10) MINI-IN-PKT-NUMBER);Receipt
  (SETF (AREF MINI-PKT #o11) 1)			;Window size
  (MINI-SEND-PKT 7 4))				;STS

;;; Open a file for read
(DEFUN MINI-OPEN-FILE (FILENAME BINARY-P)
  (SETQ MINI-CH-IDX #o1000 MINI-UNRCHF NIL MINI-EOF-SEEN NIL)
  (UNLESS MINI-OPEN-P (MINI-OPEN-CONNECTION MINI-DESTINATION-ADDRESS MINI-CONTACT-NAME))
  (DO ((OP))					;Retransmission loop
      (NIL)
    ;; Send opcode #o200 (ascii open) or #o201 (binary open) with file name
    (COPY-ARRAY-CONTENTS FILENAME MINI-PKT-STRING)
    (MINI-SEND-PKT (IF BINARY-P #o201 #o200) (ARRAY-ACTIVE-LENGTH FILENAME))
    ;; Get back opcode #o202 (win) or #o203 (lose) or OPN if old STS lost
    (SETQ OP (MINI-NEXT-PKT NIL))
    (COND ((NULL OP))				;no response, retransmit
	  ((= OP 2)				;OPN
	   (MINI-SEND-STS))			;send STS and then retransmit
	  ((OR (= OP #o202) (= OP #o203))	;Win or Lose
	   (SETQ MINI-IN-PKT-NUMBER (LOGAND #o177777 (1+ MINI-IN-PKT-NUMBER))
		 MINI-OUT-PKT-NUMBER (LOGAND 177777 (1+ MINI-OUT-PKT-NUMBER)))
	   (LET* ((LENGTH (LOGAND #o7777 (AREF MINI-PKT 1)))
		  (CR (STRING-SEARCH-CHAR #/NEWLINE MINI-PKT-STRING 0 LENGTH)))
	     ;; Before pathnames and time parsing is loaded, things are stored as strings.
	     (SETQ MINI-FILE-ID (CONS (SUBSTRING MINI-PKT-STRING 0 CR)
						;Discard zero at front of month, so the format
						;matches that produced by PRINT-UNIVERSAL-TIME
						;and by QFILE before TIMPAR is loaded.
				      (STRING-LEFT-TRIM
					#/0 (SUBSTRING MINI-PKT-STRING (1+ CR) LENGTH)))))
	   (MINI-SEND-STS)			;Acknowledge packet just received
	   (IF (= OP #o202)
	       (RETURN T)
	     (MINI-BARF MINI-FILE-ID FILENAME)))))
  (IF BINARY-P #'MINI-BINARY-STREAM #'MINI-ASCII-STREAM))

;;; Doesn't use symbols for packet fields since not loaded yet
;;; This sends a packet and doesn't return until it has cleared microcode.
;;; You fill in the data part before calling, this fills in the header.
(DEFUN MINI-SEND-PKT (OPCODE N-BYTES)
  (SETF (AREF MINI-PKT 0) (LSH OPCODE 8))
  (SETF (AREF MINI-PKT 1) N-BYTES)
  (SETF (AREF MINI-PKT 2) MINI-REMOTE-HOST)
  (SETF (AREF MINI-PKT 3) MINI-REMOTE-INDEX)
  (SETF (AREF MINI-PKT 4) MINI-LOCAL-HOST)
  (SETF (AREF MINI-PKT 5) MINI-LOCAL-INDEX)
  (SETF (AREF MINI-PKT 6) MINI-OUT-PKT-NUMBER)	;PKT#
  (SETF (AREF MINI-PKT 7) MINI-IN-PKT-NUMBER)	;ACK#
  (LET ((WC (+ 8 (CEILING N-BYTES 2) 1)))	;Word count incl header and hardware dest word
    (SETF (ARRAY-LEADER MINI-PKT %CHAOS-LEADER-WORD-COUNT) WC)
    (SETF (AREF MINI-PKT (1- WC)) MINI-ROUTING-ADDRESS))	;Store hardware destination
  (SETF (ARRAY-LEADER MINI-PKT %CHAOS-LEADER-THREAD) NIL)
  (SETF (AREF (SYMBOL-FUNCTION 'SYSTEM-COMMUNICATION-AREA) %SYS-COM-CHAOS-TRANSMIT-LIST)
	MINI-PKT)
  (%CHAOS-WAKEUP)
  (DO ()					;Await completion of transmission
      ((NULL (AREF (SYMBOL-FUNCTION 'SYSTEM-COMMUNICATION-AREA)
		   %SYS-COM-CHAOS-TRANSMIT-LIST))))
  ;; Disallow use of the packet by the receive side, flush any received packet that snuck in
  (SETF (AREF (SYMBOL-FUNCTION 'SYSTEM-COMMUNICATION-AREA) %SYS-COM-CHAOS-FREE-LIST) NIL)
  (SETF (AREF (SYMBOL-FUNCTION 'SYSTEM-COMMUNICATION-AREA) %SYS-COM-CHAOS-RECEIVE-LIST) NIL)
  (COPY-ARRAY-CONTENTS "" MINI-PKT))		;Fill with zero

;; Return opcode of next packet other than those that are no good.
;; If the arg is NIL, can return NIL if no packet arrives after a while.
;; If T, waits forever.  Return value is the opcode of the packet in MINI-PKT.
(DEFUN MINI-NEXT-PKT (MUST-RETURN-A-PACKET &AUX OP)
  (DO ((TIMEOUT 20. (1- TIMEOUT)))		;A couple seconds
      ((AND (ZEROP TIMEOUT) (NOT MUST-RETURN-A-PACKET)) NIL)
    ;; Enable microcode to receive a packet
    (SETF (AREF (SYMBOL-FUNCTION 'SYSTEM-COMMUNICATION-AREA) %SYS-COM-CHAOS-FREE-LIST) NIL)
    (SETF (AREF (SYMBOL-FUNCTION 'SYSTEM-COMMUNICATION-AREA) %SYS-COM-CHAOS-RECEIVE-LIST) NIL)
    (SETF (ARRAY-LEADER MINI-PKT %CHAOS-LEADER-THREAD) NIL)
    (COPY-ARRAY-CONTENTS "" MINI-PKT)		;Fill with zero
    (SETF (AREF (SYMBOL-FUNCTION 'SYSTEM-COMMUNICATION-AREA) %SYS-COM-CHAOS-FREE-LIST)
	  MINI-PKT)
    (%CHAOS-WAKEUP)
    (DO ((N 2000. (1- N)))			;Give it time
	((OR (ZEROP N) (SYSTEM-COMMUNICATION-AREA %SYS-COM-CHAOS-RECEIVE-LIST))))
    (COND ((SYSTEM-COMMUNICATION-AREA %SYS-COM-CHAOS-RECEIVE-LIST)
	   (SETQ OP (LSH (AREF MINI-PKT 0) -8))
	   (COND ((AND (NOT (LDB-TEST %%CHAOS-CSR-CRC-ERROR
				       (ARRAY-LEADER MINI-PKT %CHAOS-LEADER-CSR-1)))
		       (NOT (LDB-TEST %%CHAOS-CSR-CRC-ERROR
				       (ARRAY-LEADER MINI-PKT %CHAOS-LEADER-CSR-2)))
		       (= (LDB 0004 (ARRAY-LEADER MINI-PKT %CHAOS-LEADER-BIT-COUNT)) 0)
		       (>= (ARRAY-LEADER MINI-PKT %CHAOS-LEADER-BIT-COUNT) 48.)
		       (ZEROP (LOGAND #o377 (AREF MINI-PKT 0)))	;Header version 0
		       (= (FLOOR (ARRAY-LEADER MINI-PKT %CHAOS-LEADER-BIT-COUNT)
				 #o20)
			  (+ #o10		;FIRST-DATA-WORD-IN-PKT
			     (LSH (1+ (LDB #o14 (AREF MINI-PKT 1))) -1)	;PKT-NWORDS
			     3))		;HEADER
		       (= (AREF MINI-PKT 2) MINI-LOCAL-HOST)
		       (= (AREF MINI-PKT 3) MINI-LOCAL-INDEX)
		       (OR (AND (MEMQ OP '(#o14 #o202 #o203 #o200 #o300));EOF, win, lose, data
				(= (AREF MINI-PKT 6)
				   (LOGAND #o177777 (1+ MINI-IN-PKT-NUMBER))))
			   (MEMQ OP '(#o2 #o3 #o11))))	;OPN, CLS, LOS
		  ;; This packet not to be ignored, return to caller
		  (COND ((MEMQ OP '(#o3 #o11))	;CLS, LOS
			 (LET ((MSG (MAKE-STRING (LOGAND #o7777 (AREF MINI-PKT 1)))))
			   (COPY-ARRAY-CONTENTS MINI-PKT-STRING MSG)
			   (MINI-BARF "Connection broken" MSG))))
		  (RETURN OP)))
	   ;; This packet to be ignored, get another
	   (WHEN MINI-OPEN-P			;Could be getting a retransmission of
		(MINI-SEND-STS))		; an old pkt due to lost STS
	   ))))

;;; Stream which does only 16-bit binary input
(DEFUN MINI-BINARY-STREAM (OP &OPTIONAL ARG1 ARG2)
  (CASE OP
    (:WHICH-OPERATIONS '(:TYI :READ-BYTE))
    ((:TYI :READ-BYTE)
     (COND (MINI-UNRCHF
	    (PROG1 MINI-UNRCHF (SETQ MINI-UNRCHF NIL)))
	   ((< MINI-CH-IDX (FLOOR (LOGAND #o7777 (AREF MINI-PKT 1)) 2))
	    (PROG1 (AREF MINI-PKT (+ #o10 MINI-CH-IDX))
		   (SETQ MINI-CH-IDX (1+ MINI-CH-IDX))))
	   (T					;Get another packet
	    (MINI-SEND-STS)			;Acknowledge packet just processed
	    (SETQ OP (MINI-NEXT-PKT T))
	    (SETQ MINI-IN-PKT-NUMBER (LOGAND #o177777 (1+ MINI-IN-PKT-NUMBER)))
	    (COND ((= OP #o14)			;EOF
		   (MINI-SEND-STS)		;Acknowledge the EOF
		   (SETQ MINI-EOF-SEEN T)
		   (COND ((EQ OP ':TYI)		;And tell caller
			  (AND ARG1 (ERROR ARG1))
			  NIL)
			 (ARG1 (ERROR "EOF"))
			 (T ARG2)))
		  ((= OP #o300)			;Data
		   (SETQ MINI-CH-IDX 0)
		   (MINI-BINARY-STREAM :TYI))
		  (T (MINI-BARF "Bad opcode received" OP))))))
    (:UNTYI (SETQ MINI-UNRCHF ARG1))
    (:PATHNAME MINI-FASLOAD-FILENAME)
    (:GENERIC-PATHNAME 'MINI-PLIST-RECEIVER)
    (:INFO MINI-FILE-ID)
    (:CLOSE (DO () (MINI-EOF-SEEN) (MINI-BINARY-STREAM :TYI)))
    (OTHERWISE (MINI-BARF "Unknown stream operation" OP))))

;;; stream which does only character input
(DEFUN MINI-ASCII-STREAM (OP &OPTIONAL ARG1 ARG2)
  (CASE OP
    (:WHICH-OPERATIONS '(:TYI :UNTYI :READ-CHAR :UNREAD-CHAR))
    ((:TYI :READ-CHAR)
     (LET ((TEM (COND (MINI-UNRCHF
		       (PROG1 MINI-UNRCHF (SETQ MINI-UNRCHF NIL)))
		      ((< MINI-CH-IDX (LOGAND #o7777 (AREF MINI-PKT 1)))
		       (PROG1 (AREF MINI-PKT-STRING MINI-CH-IDX)
			      (INCF MINI-CH-IDX)))
		      (T			;Get another packet
		       (MINI-SEND-STS)		;Acknowledge packet just processed
		       (SETQ OP (MINI-NEXT-PKT T))
		       (SETQ MINI-IN-PKT-NUMBER (LOGAND #o177777 (1+ MINI-IN-PKT-NUMBER)))
		       (COND ((= OP #o14)	;EOF
			      (MINI-SEND-STS)	;Acknowledge the EOF
			      (SETQ MINI-EOF-SEEN T)
			      (COND ((EQ OP ':TYI)	;and tell caller
				     (AND ARG1 (ERROR ARG1))
				     NIL)
				    (ARG1 (ERROR "EOF"))
				    (T (RETURN-FROM MINI-ASCII-STREAM ARG2))))
			     ((= OP #o200)	;Data
			      (SETQ MINI-CH-IDX 0)
			      (MINI-ASCII-STREAM :TYI))
			     (T (MINI-BARF "Bad opcode received" OP)))))))
       (IF (AND (EQ OP ':READ-CHAR) (FIXNUMP TEM))
	   (INT-CHAR TEM)
	   TEM)))
    ((:UNTYI :UNREAD-CHAR) (SETQ MINI-UNRCHF ARG1))
    (:PATHNAME MINI-FASLOAD-FILENAME)
    (:GENERIC-PATHNAME 'MINI-PLIST-RECEIVER)
    (:INFO MINI-FILE-ID)
    (:CLOSE (DO () (MINI-EOF-SEEN) (MINI-ASCII-STREAM :TYI)))
    (OTHERWISE (MINI-BARF "Unknown stream operation" OP))))

(DEFUN MINI-BARF (&REST ARGS)
  (SETQ MINI-OPEN-P NIL)			;Force re-open of connection
  ;; If inside the cold load, this will be FERROR-COLD-LOAD, else make debugging easier
  (APPLY #'FERROR 'MINI-BARF ARGS))

;;;; Higher-level stuff

;;; Load a file alist as setup by the cold load generator
(DEFUN MINI-LOAD-FILE-ALIST (ALIST)
  (LOOP FOR (FILE PACK QFASLP) IN ALIST
	DO (PRINT FILE)
	DO (FUNCALL (IF QFASLP #'MINI-FASLOAD #'MINI-READFILE) FILE PACK)))

;; initialized by the cold-load builder
(DEFVAR *COLD-LOADED-FILE-PROPERTY-LISTS*)

(DEFUN MINI-FASLOAD (MINI-FASLOAD-FILENAME PKG
		     &AUX FASL-STREAM TEM)
  ;; Set it up so that file properties get remembered for when there are pathnames
  (OR (SETQ TEM (ASSOC-EQUAL MINI-FASLOAD-FILENAME *COLD-LOADED-FILE-PROPERTY-LISTS*))
      (PUSH (SETQ TEM (NCONS MINI-FASLOAD-FILENAME)) *COLD-LOADED-FILE-PROPERTY-LISTS*))
  (SETQ MINI-PLIST-RECEIVER-POINTER TEM)
  ;;Open the input stream in binary mode, and load from it.
  (SETQ FASL-STREAM (MINI-OPEN-FILE MINI-FASLOAD-FILENAME T))
  (FASLOAD-INTERNAL FASL-STREAM PKG T)
  ;; FASLOAD Doesn't really read to EOF, must read rest to avoid getting out of phase
  (MINI-CLOSE FASL-STREAM)
  MINI-FASLOAD-FILENAME)

(DEFUN MINI-CLOSE (STREAM)
  (DO () (MINI-EOF-SEEN)
    (FUNCALL STREAM :TYI)))

;; This kludge simulates the behavior of PROPERTY-LIST-MIXIN.
;; It is used instead of the generic-pathname in fasloading and readfiling;
;; it handles the same messages that generic-pathnames are typically sent.
(DEFUN MINI-PLIST-RECEIVER (OP &REST ARGS)
  (CASE OP
    (:GET (GET MINI-PLIST-RECEIVER-POINTER (CAR ARGS)))
    (:GETL (GETL MINI-PLIST-RECEIVER-POINTER (CAR ARGS)))
    (:PUTPROP (PUTPROP MINI-PLIST-RECEIVER-POINTER (CAR ARGS) (CADR ARGS)))
    (:REMPROP (REMPROP MINI-PLIST-RECEIVER-POINTER (CAR ARGS)))
    (:PROPERTY-LIST (CONTENTS MINI-PLIST-RECEIVER-POINTER))
    (:SET (CASE (CAR ARGS)
	    (:PROPERTY-LIST (SETF (CONTENTS MINI-PLIST-RECEIVER-POINTER) (CAR (LAST ARGS))))
	    (:GET (SETF (GET MINI-PLIST-RECEIVER-POINTER (CADR ARGS)) (CAR (LAST ARGS))))
	    (T (PRINT "Bad :SET to MINI-PLIST-RECEIVED") (PRINT (CAR ARGS)) (%HALT))))
    (:PUSH-PROPERTY (PUSH (CAR ARGS) (GET MINI-PLIST-RECEIVER-POINTER (CADR ARGS))))
    (T (PRINT "Bad op to MINI-PLIST-RECEIVER ") (PRINT OP) (%HALT))))

(DEFUN MINI-READFILE (FILE-NAME PKG &AUX (FDEFINE-FILE-PATHNAME FILE-NAME) TEM)
  (LET ((EOF '(()))
	(*STANDARD-INPUT* (MINI-OPEN-FILE FILE-NAME NIL))
	(*PACKAGE* (PKG-FIND-PACKAGE PKG)))
    (DO ((FORM (CLI:READ *STANDARD-INPUT* NIL EOF) (CLI:READ *STANDARD-INPUT* NIL EOF)))
	((EQ FORM EOF))
      (EVAL FORM))
    (OR (SETQ TEM (ASSOC-EQUAL FILE-NAME *COLD-LOADED-FILE-PROPERTY-LISTS*))
	(PUSH (SETQ TEM (NCONS FILE-NAME)) *COLD-LOADED-FILE-PROPERTY-LISTS*))
    (LET ((MINI-PLIST-RECEIVER-POINTER TEM))
      (SET-FILE-LOADED-ID 'MINI-PLIST-RECEIVER MINI-FILE-ID PACKAGE))))

(DEFUN MINI-BOOT ()
  (SETQ MINI-OPEN-P NIL)
  (VARIABLE-MAKUNBOUND MINI-PKT)
  (VARIABLE-MAKUNBOUND MINI-PKT-STRING))

(ADD-INITIALIZATION "MINI" '(MINI-BOOT) '(WARM FIRST))
