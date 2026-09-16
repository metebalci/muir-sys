;;; -*- Mode:LISP; Readtable:T; Package:TV; Base:8 -*-
;;;	** (c) Copyright 1980 Massachusetts Institute of Technology **

;;; PEEK -- displays status information about the Lisp Machine

;; Define the Peek display modes, and how to select them.

(DEFVAR PEEK-DEFAULT-MODE-ALIST NIL
  "This variable has one element for each Peek display mode.
Elements are added by calls to DEFINE-PEEK-MODE which appear in this file
and the other source files of PEEK, and are executed at load time.
Each element looks like:
/(character display-function menu-item-string no-updating-flag long-documentation).
That is also what the five arguments to DEFINE-PEEK-MODE look like.
The menu-item-string is a short phrase of documentation which is also
what appears in the menu proper.
The display function is what is called to update the display.
NO-UPDATING-FLAG is either T or NIL.  If T, it means simply call the
function once and leave what it prints on the screen.  Normally it is NIL,
which means that the updating function returns a set of scroll items.")

(DEFVAR PEEK-MENU-ITEM-ALIST NIL
  "This is the item alist for the command menu.
The first element of each element is the menu item string.
The third element is the corresponding element of PEEK-DEFAULT-MODE-ALIST.")

(DEFMACRO DEFINE-PEEK-MODE (FUNCTION CHARACTER DOCUMENTATION &OPTIONAL FUNCTION-P
			    &BODY LONG-DOCUMENTATION)	;this is to get the indentation right
  (DECLARE (ARGLIST FUNCTION CHARACTER DOCUMENTATION &OPTIONAL FUNCTION-P LONG-DOCUMENTATION))
  `(DEFINE-PEEK-MODE-1 ',FUNCTION ,CHARACTER ,DOCUMENTATION ,FUNCTION-P ,(CAR LONG-DOCUMENTATION)))

(DEFUN DEFINE-PEEK-MODE-1 (FUNCTION CHARACTER DOCUMENTATION FUNCTION-P LONG-DOCUMENTATION)
;character lossage
  (IF (NUMBERP CHARACTER) (SETQ CHARACTER (INT-CHAR CHARACTER)))
  (SETQ PEEK-DEFAULT-MODE-ALIST
	(DEL #'(LAMBDA (CH ELT) (= CH (CAR ELT))) CHARACTER PEEK-DEFAULT-MODE-ALIST))
  (SETQ PEEK-DEFAULT-MODE-ALIST
	(NCONC PEEK-DEFAULT-MODE-ALIST
	       (NCONS (LIST CHARACTER FUNCTION DOCUMENTATION
			    FUNCTION-P LONG-DOCUMENTATION))))
  (SETQ PEEK-MENU-ITEM-ALIST
	(MAPCAR #'(LAMBDA (ELT)
		    `(,(THIRD ELT) :VALUE ,ELT
		      :DOCUMENTATION ,(OR (FIFTH ELT) "This PEEK mode is undocumented.")))
		PEEK-DEFAULT-MODE-ALIST)))

;;; This is meant to be called inside the PEEK-TOP-LEVEL,
;;; and MODE should be a character and the first arg can be a numeric argument.
(DEFUN PEEK-SET-MODE (WINDOW MODE &REST ARGS &AUX OLD-MODE)
;character lossage
  (IF (NUMBERP MODE) (SETQ MODE (INT-CHAR MODE)))
  (WHEN (SETQ MODE (ASSQ MODE PEEK-DEFAULT-MODE-ALIST))
    (SETQ OLD-MODE (LABEL-STRING (SEND WINDOW :LABEL)))
    (SEND (SEND (SEND WINDOW :SUPERIOR) :GET-PANE 'MENU)
	  :SET-HIGHLIGHTED-ITEMS
	  (LIST (SYS:ASSOC-EQUALP (THIRD MODE) PEEK-MENU-ITEM-ALIST)))
    (SEND WINDOW :SET-LABEL (THIRD MODE))
    (IF (FOURTH MODE)
	;; If you want to execute only once,
	(UNWIND-PROTECT
	    (APPLY (SECOND MODE) WINDOW ARGS)
	  ;; Then on exit restore the old mode in the menu and label.
	  ;; Since probably the typeout window is going away now
	  ;; and that old mode's data is reappearing.
	  (PEEK-ASSURE-NO-TYPEOUT WINDOW)
	  (DOLIST (ELT PEEK-DEFAULT-MODE-ALIST)
	    (IF (EQUALP OLD-MODE (THIRD ELT))
		(RETURN (SETQ MODE ELT))))
	  (SEND (SEND (SEND WINDOW :SUPERIOR) :GET-PANE 'MENU)
		:SET-HIGHLIGHTED-ITEMS
		(LIST (SYS:ASSOC-EQUALP (THIRD MODE) PEEK-MENU-ITEM-ALIST)))
	  (SEND WINDOW :SET-LABEL (THIRD MODE)))
      ;; Here if we are entering a mode that really does update.
      ;; We stay in it semipermanently.
      (PEEK-ASSURE-NO-TYPEOUT WINDOW)
      (SEND WINDOW :SET-DISPLAY-ITEM (APPLY (SECOND MODE) ARGS)))
    T))

;;;; Windows for PEEK.

(DEFFLAVOR BASIC-PEEK ((NEEDS-REDISPLAY NIL))
   (SCROLL-MOUSE-MIXIN SCROLL-WINDOW-WITH-TYPEOUT FULL-SCREEN-HACK-MIXIN)
  :SETTABLE-INSTANCE-VARIABLES
  :GETTABLE-INSTANCE-VARIABLES
  (:DEFAULT-INIT-PLIST :SAVE-BITS T
    		       :LABEL "Peek"
		       :TRUNCATION T)
  (:DOCUMENTATION :SPECIAL-PURPOSE "The actual peek window.  This has the capability
to display in a PEEK display mode."))

(DEFMETHOD (BASIC-PEEK :NAME-FOR-SELECTION) ()
  (STRING-APPEND "Peek: " (LABEL-STRING LABEL)))

(DEFFLAVOR PEEK-WINDOW () (PROCESS-MIXIN TV:INITIALLY-INVISIBLE-MIXIN BASIC-PEEK)
  (:DEFAULT-INIT-PLIST :PROCESS
		       '(PEEK-STANDALONE-TOP-LEVEL :SPECIAL-PDL-SIZE #o4000
						   :REGULAR-PDL-SIZE #o10000))
  (:DOCUMENTATION :COMBINATION "Peek window with a process.
Usable as a stand-alone window that does PEEK display,
but with no menu -- only keyboard commands will be available."))

(DEFUN PEEK-MOUSE-CLICK (ITEM LEADER-TO-COMPLEMENT)
  (DECLARE (:SELF-FLAVOR BASIC-PEEK))
  (SETQ NEEDS-REDISPLAY T)
  (SETF (ARRAY-LEADER ITEM (+ SCROLL-ITEM-LEADER-OFFSET LEADER-TO-COMPLEMENT))
	(NOT (ARRAY-LEADER ITEM (+ SCROLL-ITEM-LEADER-OFFSET LEADER-TO-COMPLEMENT)))))

;This is the top level function that runs in the process of a window of flavor PEEK.
(DEFUN PEEK-STANDALONE-TOP-LEVEL (WINDOW)
  (PEEK-TOP-LEVEL WINDOW #/HELP)
  (DO-FOREVER
    (DESELECT-AND-MAYBE-BURY-WINDOW (SEND WINDOW :ALIAS-FOR-SELECTED-WINDOWS) :FIRST)
    (PEEK-TOP-LEVEL WINDOW NIL)))

;;; Peek frames that have command menus of Peek modes, as well as a peek-window
;;; to do the actual displaying in.
(DEFFLAVOR PEEK-FRAME ()
	   (PROCESS-MIXIN
	    FRAME-DONT-SELECT-INFERIORS-WITH-MOUSE-MIXIN
	    BORDERED-CONSTRAINT-FRAME-WITH-SHARED-IO-BUFFER)
  (:DEFAULT-INIT-PLIST :SAVE-BITS :DELAYED :PROCESS ))

(DEFMETHOD (PEEK-FRAME :BEFORE :INIT) (INIT-PLIST)
  (SETQ PANES (LIST
		(IF (GETL INIT-PLIST '(:PROCESS))
		    `(PEEK PEEK-WINDOW :SAVE-BITS NIL :PROCESS ,(GET INIT-PLIST :PROCESS))
		    '(PEEK PEEK-WINDOW :SAVE-BITS NIL))
		`(MENU DYNAMIC-HIGHLIGHTING-COMMAND-MENU-PANE
		       :FONT-MAP ,(LIST FONTS:CPTFONT)	;not the usual large menu font
		       :LABEL "Peek Modes"
		       :ITEM-LIST-POINTER PEEK-MENU-ITEM-ALIST)))
  (SETQ CONSTRAINTS `((MAIN . ((MENU PEEK)
			       ((MENU :ASK :PANE-SIZE))
			       ((PEEK :EVEN)))))))

(DEFMETHOD (PEEK-FRAME :AFTER :INIT) (IGNORE)
  (LET ((PANE (SEND SELF :GET-PANE 'PEEK)))
    (SEND SELF :SELECT-PANE PANE)
    (SETQ PROCESS (SEND PANE :PROCESS))))

(DEFMETHOD (PEEK-FRAME :BEFORE :EXPOSE) (&REST IGNORE)
  (OR EXPOSED-P
      (EQUAL PEEK-MENU-ITEM-ALIST
	     (SEND (SEND SELF :GET-PANE 'MENU) :ITEM-LIST))
      (SEND SELF :SET-CONFIGURATION 'MAIN)))

(DEFFLAVOR DYNAMIC-HIGHLIGHTING-COMMAND-MENU-PANE ()
	   (DYNAMIC-ITEM-LIST-MIXIN MENU-HIGHLIGHTING-MIXIN COMMAND-MENU))

(COMPILE-FLAVOR-METHODS PEEK-FRAME PEEK-WINDOW DYNAMIC-HIGHLIGHTING-COMMAND-MENU-PANE)

(DEFUN PEEK (&OPTIONAL INITIAL-MODE)
  "Select a new or old Peek window.  An argument sets the Peek display mode."
  (SELECT-OR-CREATE-WINDOW-OF-FLAVOR 'PEEK-FRAME)
  (IF INITIAL-MODE
      (SEND SELECTED-WINDOW :FORCE-KBD-INPUT
	                    (TYPECASE INITIAL-MODE
			      (STRING (CHAR INITIAL-MODE 0))
			      (SYMBOL (CHAR (SYMBOL-NAME INITIAL-MODE) 0))
			      (T INITIAL-MODE))))
  (AWAIT-WINDOW-EXPOSURE))

(DEFVAR PEEK-SLEEP-TIME 120.
  "This is how long, in 60'ths of a second, to wait between updates of the screen in PEEK.")

;;; This is the command reading loop.
(DEFUN PEEK-TOP-LEVEL (WINDOW MODE)
  (COND-EVERY
    ((AND MODE (SYMBOLP MODE)) (SETQ MODE (SYMBOL-NAME MODE)))
    ((STRINGP MODE) (SETQ MODE (CHAR MODE 0)))
    ((CHARACTERP MODE) (SETQ MODE (CHAR-INT MODE)))
;character lossage
    ((NUMBERP MODE) (SEND WINDOW :FORCE-KBD-INPUT MODE)))
  (BLOCK PEEK
    (DO-FOREVER
      (CATCH-ERROR-RESTART ((SYS:ABORT ERROR) "Return to PEEK command level.")
	(DO ((SLEEP-TIME PEEK-SLEEP-TIME)
	     (WAKEUP-TIME (TIME-DIFFERENCE (TIME) (- PEEK-SLEEP-TIME)))
	     (*TERMINAL-IO* (SEND WINDOW :TYPEOUT-WINDOW))
	     (ARG)
	     (CHAR))
	    (())
	  (AND (TIME-LESSP WAKEUP-TIME (TIME))
	       (SETQ WAKEUP-TIME (TIME-DIFFERENCE (TIME) (- SLEEP-TIME))))
	  (OR (= SLEEP-TIME 0)
	      (PROCESS-WAIT "Peek Timeout or TYI"
			    #'(LAMBDA (TIME FLAG-LOC STREAM PEEK-WINDOW)
				(AND (SHEET-EXPOSED-P PEEK-WINDOW)
				     (OR (TIME-LESSP TIME (TIME))
					 (CAR FLAG-LOC)
					 (SEND STREAM :LISTEN))))
			    WAKEUP-TIME
			    (LOCATE-IN-INSTANCE WINDOW 'NEEDS-REDISPLAY)
			    *TERMINAL-IO*
			    (SEND WINDOW :ALIAS-FOR-SELECTED-WINDOWS)))
	  (DO ()
	      ((PROGN (PEEK-ASSURE-NO-TYPEOUT WINDOW)
		      (NULL (SETQ CHAR (SEND *TERMINAL-IO* :ANY-TYI-NO-HANG)))))
	    (COND-EVERY
	      ((CONSP CHAR)
	       ;; A special command (forced input, no doubt)
	       (CASE (CAR CHAR)
		 (SUPDUP (SUPDUP (CADR CHAR)))
		 (SUPDUP:TELNET (TELNET (CADR CHAR)))
		 (QSEND (QSEND (CADR CHAR))
			(SEND WINDOW :SET-NEEDS-REDISPLAY T)
			(SEND *TERMINAL-IO* :MAKE-COMPLETE))
		 (EH (EH (CADR CHAR)))
		 (INSPECT (INSPECT (CADR CHAR)))
		 (DESCRIBE (DESCRIBE (CADR CHAR)))
		 (:MENU (SETQ CHAR (FIRST (THIRD (SECOND CHAR)))))
		 (OTHERWISE (BEEP)))
	       (SETQ ARG NIL))
	      ((NUMBERP CHAR)
	       (SETQ CHAR (INT-CHAR CHAR)))
	      ((CHARACTERP CHAR)
	       ;; Standard character, either accumulate arg or select new mode
	       (SETQ CHAR (CHAR-UPCASE CHAR))
	       (IF (DIGIT-CHAR-P CHAR)
		   (SETQ ARG (+ (* 10. (OR ARG 0)) (DIGIT-CHAR-P CHAR)))
		 (IF (PEEK-SET-MODE WINDOW CHAR ARG)
		     (SETQ ARG NIL)
		   ;; Check for standard character assignments
		   (CASE CHAR
		     (#/HELP
		      (SEND *STANDARD-OUTPUT* :CLEAR-SCREEN)
		      (LET (INPUT)
			(SETQ INPUT (SEND *STANDARD-INPUT* :LISTEN))
			(UNLESS INPUT
			  (FORMAT T "The Peek program shows a continuously updating status display.
  There are several modes that display different status.
  Here is a list of modes.  Select a mode by typing the character
  or by clicking on the corresponding menu item.~2%"))
			(DOLIST (E PEEK-DEFAULT-MODE-ALIST)
			  (WHEN (OR INPUT (SETQ INPUT (SEND *STANDARD-INPUT* :LISTEN)))
			    (RETURN))
			  (FORMAT T "~:@C~5T~A~%~@[~6T~A~%~]"
				  (FIRST E) (THIRD E) (FIFTH E)))
			(UNLESS INPUT
			  (FORMAT T "~%Q~5TQuit.~%")
			  (FORMAT T "nZ~5TSets sleep time between updates to n seconds.~2%")
			  (FORMAT T "[Help]  Prints this message.~2%")))
		      (SETQ ARG NIL))
		     (#/Q
		      (RETURN-FROM PEEK NIL))
		     (#/Z
		      (AND ARG (SETQ SLEEP-TIME (* 60. ARG)))
		      (SEND WINDOW :SET-NEEDS-REDISPLAY T)
		      (SETQ ARG NIL))
		     (#/SPACE (SEND WINDOW :SET-NEEDS-REDISPLAY T))
		     (OTHERWISE (BEEP))))))))
	  (WHEN (OR (SEND WINDOW :NEEDS-REDISPLAY) (TIME-LESSP WAKEUP-TIME (TIME)))
	    ;; We want to redisplay.  If have typeout, hang until user confirms.
	    (SEND WINDOW :SET-NEEDS-REDISPLAY NIL)
	    (SEND WINDOW :REDISPLAY)))))))

(DEFUN PEEK-ASSURE-NO-TYPEOUT (WINDOW)
  (WHEN (SEND (SETQ WINDOW (SEND WINDOW :TYPEOUT-WINDOW)) :INCOMPLETE-P)
    (FORMAT T "~&Type any character to flush:")
    (LET ((CHAR (SEND *TERMINAL-IO* :TYI)))
      (SEND WINDOW :MAKE-COMPLETE)
      (UNLESS (= CHAR #/SPACE)
	(SEND *TERMINAL-IO* :UNTYI CHAR)))))

;;;; Processes, meters

(DEFINE-PEEK-MODE PEEK-PROCESSES #/P "Active Processes" NIL
  "List status of every process -- why waiting, how much run recently.")

(DEFUN PEEK-PROCESSES (IGNORE)
  "Shows state of all active processes."
  (LIST ()
	;; 30 of process name, 25 of state, 5 of priority, 10 of quantum left/quantum,
	;; 8 of percentage, followed by idle time (11 columns)
	(SCROLL-PARSE-ITEM (FORMAT NIL "~30A~21A~10A~10A~8A~8A"
				   "Process Name" "State" "Priority" "Quantum"
				   " %" "Idle"))
	(SCROLL-PARSE-ITEM "")
	(SCROLL-MAINTAIN-LIST #'(LAMBDA () ALL-PROCESSES)
			      #'(LAMBDA (PROCESS)
				  (SCROLL-PARSE-ITEM
				    `(:MOUSE-ITEM
				       (NIL :EVAL (PEEK-PROCESS-MENU ',PROCESS 'ITEM 0)
					    :DOCUMENTATION
					    "Menu of useful things to do to this process.")
				       :STRING ,(PROCESS-NAME PROCESS) 30.)
				    `(:FUNCTION ,#'PEEK-WHOSTATE ,(NCONS PROCESS) 25.)
				    `(:FUNCTION ,PROCESS (:PRIORITY) 5. ("~D."))
				    `(:FUNCTION ,PROCESS (:QUANTUM-REMAINING) 5. ("~4D//"))
				    `(:FUNCTION ,PROCESS (:QUANTUM) 5. ("~D."))
				    `(:FUNCTION ,PROCESS (:PERCENT-UTILIZATION) 8.
						("~1,1,4$%"))
				    `(:FUNCTION ,PROCESS (:IDLE-TIME) NIL
						("~\TV:PEEK-PROCESS-IDLE-TIME\"))))
			      NIL
			      NIL)
	(SCROLL-PARSE-ITEM "")
	(SCROLL-PARSE-ITEM "Clock Function List")
	(SCROLL-MAINTAIN-LIST #'(LAMBDA () SI:CLOCK-FUNCTION-LIST)
			      #'(LAMBDA (FUNC)
				  (SCROLL-PARSE-ITEM
				    `(:STRING ,(WITH-OUTPUT-TO-STRING (STR)
						 (PRINC FUNC STR))))))))

(FORMAT:DEFFORMAT PEEK-PROCESS-IDLE-TIME (:ONE-ARG) (ARG IGNORE)
  (COND ((NULL ARG) (SEND *STANDARD-OUTPUT* :STRING-OUT "forever"))	; character too small
	((ZEROP ARG))				;Not idle
	((< ARG 60.) (FORMAT *STANDARD-OUTPUT* "~D sec" ARG))
	((< ARG 3600.) (FORMAT *STANDARD-OUTPUT* "~D min" (TRUNCATE ARG 60.)))
	(T (FORMAT *STANDARD-OUTPUT* "~D hr" (TRUNCATE ARG 3600.)))))

(DEFUN PEEK-WHOSTATE (PROCESS)
  (COND ((SI:PROCESS-ARREST-REASONS PROCESS) "Arrest")
	((SI:PROCESS-RUN-REASONS PROCESS) (PROCESS-WHOSTATE PROCESS))
	(T "Stop")))

(DEFINE-PEEK-MODE PEEK-COUNTERS #/% "Statistics Counters" NIL
  "Display the values of all the microcode meters.")

(DEFUN PEEK-COUNTERS (IGNORE)
  "Statistics counters"
  (LIST ()
	(SCROLL-MAINTAIN-LIST #'(LAMBDA () SYS:A-MEMORY-COUNTER-BLOCK-NAMES)
			      #'(LAMBDA (COUNTER)
				  (SCROLL-PARSE-ITEM
				    `(:STRING ,(STRING COUNTER) 35.)
				    `(:FUNCTION READ-METER (,COUNTER) NIL ("~@15A" 10. T)))))))

;;;; Memory

(DEFUN PEEK-MEMORY-HEADER ()
  (SCROLL-PARSE-ITEM
      "Physical memory: "
      `(:FUNCTION ,#'(LAMBDA (&AUX (VAL (SYSTEM-COMMUNICATION-AREA %SYS-COM-MEMORY-SIZE)))
		       (SETF (VALUE 0) (TRUNCATE VAL #o2000))
		       VAL)
		  NIL NIL (NIL 8.))
      `(:VALUE 0 NIL (" (~DK), "))
      "Free space: "
      `(:FUNCTION ,#'(LAMBDA (&AUX (VAL (SI:GET-FREE-SPACE-SIZE)))
		       (SETF (VALUE 0) (TRUNCATE VAL #o2000))
		       VAL)
		  NIL NIL (NIL 8.))
      `(:VALUE 0 NIL (" (~DK)"))
      ", Wired pages "
      `(:FUNCTION ,#'(LAMBDA ()
		       (MULTIPLE-VALUE-BIND (N-WIRED-PAGES N-FIXED-WIRED-PAGES)
			   (SI:COUNT-WIRED-PAGES)
			 (SETF (VALUE 0) (- N-WIRED-PAGES N-FIXED-WIRED-PAGES))
			 (SETF (VALUE 1) (TRUNCATE N-WIRED-PAGES (TRUNCATE 2000 PAGE-SIZE)))
			 (SETF (VALUE 2) (\ N-WIRED-PAGES (TRUNCATE 2000 PAGE-SIZE)))
			 N-FIXED-WIRED-PAGES))
		  NIL NIL ("~D"))
      `(:VALUE 0 NIL ("+~D "))
      `(:VALUE 1 NIL ("(~D"))
      `(:VALUE 2 NIL ("~[~;.25~;.5~;.75~]K)"))))

(DEFINE-PEEK-MODE PEEK-AREAS #/A "Areas" NIL
  "Display status of areas, including how much memory allocated and used.")

(DEFUN PEEK-AREAS (IGNORE)
  "Areas"
  (LIST ()
    (PEEK-MEMORY-HEADER)
    (SCROLL-PARSE-ITEM "")
    (SCROLL-MAINTAIN-LIST
      #'(LAMBDA () 0)
      #'(LAMBDA (AREA)
	  (LIST '(:PRE-PROCESS-FUNCTION PEEK-AREAS-REGION-DISPLAY)
	    (SCROLL-PARSE-ITEM
	      :MOUSE-SELF '(NIL :EVAL (PEEK-MOUSE-CLICK 'SELF 0)
				 :DOCUMENTATION
				 "Insert//remove display of all regions in this area.")
	      :LEADER `(NIL ,AREA)
	      `(:FUNCTION IDENTITY (,AREA) 4 ("~3D"))
	      `(:STRING ,(STRING (AREA-NAME AREA)) 40.)
	      `(:FUNCTION ,#'(LAMBDA (AREA)
			       (MULTIPLE-VALUE-BIND (LENGTH USED N-REGIONS)
				   (SI:ROOM-GET-AREA-LENGTH-USED AREA)
				 (SETF (VALUE 0) USED)
				 (SETF (VALUE 1) LENGTH)
				 (SETF (VALUE 2)
				       (COND ((ZEROP LENGTH) 0)
					     ((< LENGTH #o40000)
					      (TRUNCATE (* 100. (- LENGTH USED)) LENGTH))
					     (T
					      (TRUNCATE (- LENGTH USED) (TRUNCATE LENGTH 100.)))))
				 N-REGIONS))
			  (,AREA) 15. ("(~D region~0@*~P)"))
	      `(:VALUE 2 NIL ("~@3A% free, " 10. T))
	      `(:VALUE 0 NIL ("~O"))
	      `(:VALUE 1 NIL ("//~O used")))))
      NIL
      #'(LAMBDA (STATE &AUX NEXT-ONE THIS-ONE (LEN (ARRAY-LENGTH #'AREA-NAME)))
	  (DO ((I STATE (1+ I)))
	      (( I LEN) NIL)
	    (COND ((AND (NULL THIS-ONE) (AREF #'AREA-NAME I))
		   (SETQ THIS-ONE I))
		  ((AND THIS-ONE (AREF #'AREA-NAME I))
		   (SETQ NEXT-ONE I)
		   (RETURN T))))
	  (VALUES THIS-ONE NEXT-ONE (NULL NEXT-ONE))))))

(DEFUN PEEK-AREAS-REGION-DISPLAY (ITEM)
  "Handles adding/deleting of the region display when a mouse button is clicked."
  (COND ((NULL (ARRAY-LEADER (CADR ITEM) SCROLL-ITEM-LEADER-OFFSET)))
	 ;; Clicked on this item, need to complement state
	((= (LENGTH ITEM) 2)
	 ;; If aren't displaying regions now, display them
	 (RPLACD (CDR ITEM)
		 (NCONS
		   (SCROLL-MAINTAIN-LIST
		   `(LAMBDA ()
		      (AREA-REGION-LIST (ARRAY-LEADER ',(FIRST (SCROLL-ITEMS ITEM))
						      (1+ SCROLL-ITEM-LEADER-OFFSET))))
		   #'(LAMBDA (REGION)
		       (SCROLL-PARSE-ITEM
			`(:STRING
			  ,(FORMAT NIL "  #~O: Origin ~O, Length ~O, "
				       REGION
				       (SI:REGION-ORIGIN-TRUE-VALUE REGION)
				       (REGION-LENGTH REGION)))
			`(:FUNCTION ,#'REGION-FREE-POINTER (,REGION) NIL ("Used ~O, "))
			`(:FUNCTION ,#'REGION-GC-POINTER (,REGION) NIL ("GC ~O, "))
			`(:FUNCTION ,#'(LAMBDA (REGION &AUX BITS)
					(SETQ BITS (REGION-BITS REGION))
					(SETF (VALUE 0)
					      (NTH (LDB %%REGION-SPACE-TYPE BITS)
						   '(FREE OLD
						     NEW NEW1 NEW2 NEW3 NEW4 NEW5 NEW6
						     STATIC FIXED EXTRA-PDL COPY
						     "TYPE=15" "TYPE=16" "TYPE=17")))
					(SETF (VALUE 1) (LDB %%REGION-MAP-BITS BITS))
					(SETF (VALUE 2) (LDB %%REGION-SCAVENGE-ENABLE BITS))
					(NTH (LDB %%REGION-REPRESENTATION-TYPE BITS)
					     '(LIST STRUC "REP=2" "REP=3")))
				    (,REGION) NIL ("Type ~A "))
			`(:VALUE 0 NIL ("~A, "))
			`(:VALUE 1 NIL ("Map ~O, "))
			`(:VALUE 2 NIL ("~[NoScav~;Scav~]"))))
		   NIL
		   #'(LAMBDA (STATE)
		       (VALUES STATE
			       (REGION-LIST-THREAD STATE)
			       (MINUSP (REGION-LIST-THREAD STATE))))))))
	(T (RPLACD (CDR ITEM) NIL)))
  (SETF (ARRAY-LEADER (CADR ITEM) SCROLL-ITEM-LEADER-OFFSET) NIL))

;;;; File system status

(DEFINE-PEEK-MODE PEEK-FILE-SYSTEM #/F "File System Status" NIL
  "Display status of FILE protocol connections to remote file systems.")

(DEFUN NEXT-INTERESTING-FILE-HOST-STEPPER (LIST)
  (LET ((GOOD (SOME LIST #'(LAMBDA (X) (SEND X :SEND-IF-HANDLES :ACCESS)))))
    (VALUES (CAR GOOD) (CDR GOOD) (NULL GOOD))))

(DEFUN PEEK-FILE-SYSTEM (IGNORE)
  "Display status of file system"
  (SCROLL-MAINTAIN-LIST 
    #'(LAMBDA () FS:*PATHNAME-HOST-LIST*)
    #'(LAMBDA (HOST)
	(APPEND '(())
	  (SEND HOST :PEEK-FILE-SYSTEM-HEADER)
	  (SEND HOST :PEEK-FILE-SYSTEM)))
    ()
    #'NEXT-INTERESTING-FILE-HOST-STEPPER))

(DEFMETHOD (SI:FILE-DATA-STREAM-MIXIN :PEEK-FILE-SYSTEM) (&OPTIONAL (INDENT 0) &AUX DIRECTION)
  "Returns a scroll item describing a stream"
  (TV:SCROLL-PARSE-ITEM
    :MOUSE `(NIL :EVAL (PEEK-FILE-SYSTEM-STREAM-MENU ',SELF)
		  :DOCUMENTATION "Menu of useful things to do to this open file.")
    (AND ( INDENT 0) (FORMAT NIL "~V@T" INDENT))
    (CASE (SETQ DIRECTION (SEND SELF :DIRECTION))
      (:INPUT "Input ")
      (:OUTPUT "Output ")
      (OTHERWISE "?Direction? "))
    (SEND (SEND SELF :PATHNAME) :STRING-FOR-PRINTING)
    (IF (SEND SELF :CHARACTERS)
	", Character, " ", Binary, ")
    `(:FUNCTION ,#'(LAMBDA (STREAM)
		     (SETF (TV:VALUE 0) (SEND STREAM :READ-POINTER))
		     (TV:VALUE 0))
		(,SELF) NIL ("~D"))
    (AND (EQ DIRECTION :INPUT)
	 `(:FUNCTION ,#'(LAMBDA (STREAM)
			  (LET ((LENGTH (SEND STREAM :LENGTH)))
			    (AND LENGTH (NOT (ZEROP LENGTH))
				 (TRUNCATE (* 100. (TV:VALUE 0)) LENGTH))))
		     (,SELF) NIL ("~@[ (~D%)~]")))
    " bytes"))

(DEFUN PEEK-FILE-SYSTEM-STREAM-MENU (STREAM)
  (APPLY #'PROCESS-RUN-FUNCTION "Peek File System Menu"
	 			SELF :PEEK-FILE-SYSTEM-MENU
				(LIST STREAM)))

(DEFMETHOD (BASIC-PEEK :PEEK-FILE-SYSTEM-MENU) (STREAM)
  (LET ((*TERMINAL-IO* TYPEOUT-WINDOW))
    (MENU-CHOOSE `(("Close" :EVAL (SEND ',STREAM :CLOSE)
		    :DOCUMENTATION "Close selected file (normally).")
		   ("Abort" :EVAL (SEND ',STREAM :CLOSE :ABORT)
		    :DOCUMENTATION "Close selected file (aborts writing).")
		   ("Delete" :EVAL (SEND ',STREAM :DELETE)
		    :DOCUMENTATION "Delete selected file, but don't close it.")
		   ("Describe" :EVAL (DESCRIBE ',STREAM)
		    :DOCUMENTATION "Describe the file's stream.")
		   ("Inspect" :EVAL (INSPECT ',STREAM)
		    :DOCUMENTATION "Inspect the file's stream.")
		   )
		 (STRING (SEND STREAM :TRUENAME)))))

(DEFUN PEEK-PROCESS-MENU (&REST ARGS)
  (APPLY #'PROCESS-RUN-FUNCTION "Peek Process Menu"
	 			SELF :PEEK-PROCESS-MENU ARGS))

(DEFMETHOD (BASIC-PEEK :PEEK-PROCESS-MENU) (PROCESS &REST IGNORE &AUX CHOICE)
  "Menu for interesting operations on processes in a peek display"
  (LET ((*TERMINAL-IO* TYPEOUT-WINDOW)
	(CHOICES '(("Debugger" :VALUE PROCESS-EH
		    :DOCUMENTATION
		    "Call the debugger to examine the selected process.")
		   ("Arrest" :VALUE PROCESS-ARREST
		    :DOCUMENTATION "Arrest the selected process.  Undone by Un-Arrest.")
		   ("Un-Arrest" :VALUE PROCESS-UN-ARREST
		    :DOCUMENTATION "Un-Arrest the selected process.  Complement of Arrest.")
		   ("Flush" :VALUE PROCESS-FLUSH
		    :DOCUMENTATION
		    "Unwind the selected process' stack and make it unrunnable.  Ask for confirmation.")
		   ("Reset" :VALUE PROCESS-RESET
		    :DOCUMENTATION "Reset the selected process.  Ask for confirmation.")
		   ("Kill" :VALUE PROCESS-KILL
		    :DOCUMENTATION
		    "Kill the selected process.  Ask for confirmation.")
		   ("Describe" :VALUE PROCESS-DESCRIBE
		    :DOCUMENTATION
		    "Call DESCRIBE on this process.")
		   ("Inspect" :VALUE PROCESS-INSPECT
		    :DOCUMENTATION
		    "Call INSPECT on this process."))))
    ;; Don't offer EH for a simple process.
    (OR (TYPEP (PROCESS-STACK-GROUP PROCESS) 'STACK-GROUP)
	(POP CHOICES))
    (SETQ CHOICE (MENU-CHOOSE CHOICES (PROCESS-NAME PROCESS)))
    (CASE CHOICE
      (PROCESS-ARREST (SEND PROCESS :ARREST-REASON))
      (PROCESS-UN-ARREST (SEND PROCESS :REVOKE-ARREST-REASON))
      (PROCESS-FLUSH (IF (MOUSE-Y-OR-N-P (FORMAT NIL "Flush ~A" PROCESS))
			 (SEND PROCESS :FLUSH)))
      (PROCESS-RESET (IF (MOUSE-Y-OR-N-P (FORMAT NIL "Reset ~A" PROCESS))
			 (SEND PROCESS :RESET)))
      (PROCESS-KILL (IF (MOUSE-Y-OR-N-P (FORMAT NIL "Kill ~A" PROCESS))
			(SEND PROCESS :KILL)))
      (PROCESS-EH (SEND SELF :FORCE-KBD-INPUT `(EH ,PROCESS)))
      (PROCESS-DESCRIBE (SEND SELF :FORCE-KBD-INPUT `(DESCRIBE ,PROCESS)))
      (PROCESS-INSPECT (SEND SELF :FORCE-KBD-INPUT `(INSPECT ,PROCESS)))
      (NIL)
      (OTHERWISE (BEEP)))))

;;;; Peeking at windows

(DEFINE-PEEK-MODE PEEK-WINDOW-HIERARCHY #/W "Window hierarchy" NIL
  "Display the hierarchy of window inferiors, saying which are exposed.")

(DEFUN PEEK-WINDOW-HIERARCHY (IGNORE)
  (SCROLL-MAINTAIN-LIST #'(LAMBDA () ALL-THE-SCREENS)
			#'(LAMBDA (SCREEN)
			    (LIST ()
			      (SCROLL-PARSE-ITEM (FORMAT NIL "Screen ~A" SCREEN))
			      (PEEK-WINDOW-INFERIORS SCREEN 2)
			      (SCROLL-PARSE-ITEM "")))))

(DEFUN PEEK-WINDOW-INFERIORS (WINDOW INDENT)
  (DECLARE (SPECIAL WINDOW INDENT))
  (SCROLL-MAINTAIN-LIST (CLOSURE '(WINDOW) #'(LAMBDA () (SHEET-INFERIORS WINDOW)))
			(CLOSURE '(INDENT)
			  #'(LAMBDA (SHEET)
			      (LIST ()
				    (SCROLL-PARSE-ITEM 
				      (FORMAT NIL "~V@T" INDENT)
				      `(:MOUSE
					 (NIL :EVAL (PEEK-WINDOW-MENU ',SHEET)
					      :DOCUMENTATION
					      "Menu of useful things to do to this window.")
					 :STRING
					 ,(SEND SHEET :NAME)))
				    (PEEK-WINDOW-INFERIORS SHEET (+ INDENT 4)))))))

(DEFUN PEEK-WINDOW-MENU (&REST ARGS)
  (APPLY #'PROCESS-RUN-FUNCTION "Peek Window Menu"
	 			#'PEEK-WINDOW-MENU-INTERNAL SELF ARGS))

(DEFUN PEEK-WINDOW-MENU-INTERNAL (PEEK-WINDOW SHEET &REST IGNORE &AUX CHOICE)
  "Menu for interesting operations on sheets in a peek display"
  (SETQ CHOICE
	(MENU-CHOOSE
	  '(("Deexpose" :VALUE :DEEXPOSE :DOCUMENTATION "Deexpose the window.")
	    ("Expose" :VALUE :EXPOSE :DOCUMENTATION "Expose the window.")
	    ("Select" :VALUE :SELECT :DOCUMENTATION "Select the window.")
	    ("Deselect" :VALUE :DESELECT :DOCUMENTATION "Deselect the window.")
	    ("Deactivate" :VALUE :DEACTIVATE :DOCUMENTATION "Deactivate the window.")
	    ("Kill" :VALUE :KILL :DOCUMENTATION "Kill the window.")
	    ("Bury" :VALUE :BURY :DOCUMENTATION "Bury the window.")
	    ("Inspect" :VALUE :INSPECT :DOCUMENTATION "Look at window data structure."))
	  (SEND SHEET :NAME)))
  (AND CHOICE
       (OR (NEQ CHOICE :KILL)
	   (MOUSE-Y-OR-N-P (FORMAT NIL "Kill ~A" (SEND SHEET :NAME))))
       (IF (EQ CHOICE :INSPECT)
	   (SEND PEEK-WINDOW :FORCE-KBD-INPUT `(INSPECT ,SHEET))
	   (SEND SHEET CHOICE))))

(DEFINE-PEEK-MODE PEEK-SERVERS #/S "Active Servers" NIL
  "List all servers, who they are serving, and their status.")

(DEFUN PEEK-SERVERS (IGNORE)
    (LIST ()
	  (SCROLL-PARSE-ITEM "Active Servers")
	  (SCROLL-PARSE-ITEM "Contact Name        Host                Process // State")
	  (SCROLL-PARSE-ITEM "                                                  Connection")
	  (SCROLL-PARSE-ITEM "")
	  (SCROLL-MAINTAIN-LIST
	    #'(LAMBDA () (SEND TV:WHO-LINE-FILE-STATE-SHEET :SERVERS))
	    #'(LAMBDA (SERVER-DESC)
		(LET* ((PROCESS (SERVER-DESC-PROCESS SERVER-DESC))
		       (CONN (SERVER-DESC-CONNECTION SERVER-DESC))
		       (HOST (SI:GET-HOST-FROM-ADDRESS (CHAOS:FOREIGN-ADDRESS CONN) :CHAOS)))
		  (LIST '(:PRE-PROCESS-FUNCTION PEEK-SERVER-PREPROCESS)
			(SCROLL-PARSE-ITEM
			  :LEADER '(NIL NIL NIL)
			  `(:FUNCTION ,#'SERVER-DESC-CONTACT-NAME (,SERVER-DESC) 20. ("~A"))
			  `(:MOUSE-ITEM
			     (NIL :EVAL (CHAOS:PEEK-CHAOS-HOST-MENU ',HOST 'TV:ITEM 0)
				  :DOCUMENTATION "Menu of useful things to do to this host.")
			     :FUNCTION ,#'VALUES (,HOST) 20. ("~A"))
			  `(:MOUSE
			     (NIL :EVAL (PEEK-PROCESS-MENU ',PROCESS)
				  :DOCUMENTATION
				  "Menu of useful things to do to this process.")
			     :STRING
			     ,(FORMAT NIL "~S" PROCESS))
			  "    "
			  `(:FUNCTION ,#'PEEK-WHOSTATE ,(NCONS PROCESS)))
			(SCROLL-PARSE-ITEM
			  :LEADER '(NIL NIL NIL NIL NIL NIL)	;6
			  "                                                  "
			  `(:MOUSE-ITEM
			     (NIL :EVAL (PEEK-CONNECTION-MENU ',CONN 'ITEM)
				  :DOCUMENTATION
				  "Menu of useful things to do this connection")
			     :STRING ,(FORMAT NIL "~S" CONN)))
			NIL			;Connection stat
		        NIL			;hostat
			(AND (SERVER-DESC-FUNCTION SERVER-DESC)
			     (APPLY (SERVER-DESC-FUNCTION SERVER-DESC)
				    (SERVER-DESC-ARGS SERVER-DESC)))))))))

(DEFUN PEEK-CONNECTION-MENU (CONN ITEM)
  (APPLY #'PROCESS-RUN-FUNCTION "Peek Server Connection Menu"
				SELF :PEEK-SERVER-CONNECTION-MENU
				(LIST CONN ITEM)))

(DEFMETHOD (BASIC-PEEK :PEEK-SERVER-CONNECTION-MENU) (CONN ITEM)
  (LET ((*TERMINAL-IO* TYPEOUT-WINDOW))
    (LET ((CHOICE
	    (MENU-CHOOSE `(("Close" :VALUE :CLOSE
			    :DOCUMENTATION "Close connection forcibly.")
			   ("Insert Detail" :VALUE :DETAIL
			    :DOCUMENTATION
			    "Insert detailed info about chaos connection.")
			   ("Remove Detail" :VALUE :UNDETAIL
			    :DOCUMENTATION
			    "Remove detailed info from Peek display.")
			   ("Inspect" :VALUE :INSPECT
			    :DOCUMENTATION "Inspect the connection"))
			 (STRING-APPEND
			   (SI:GET-HOST-FROM-ADDRESS (CHAOS:FOREIGN-ADDRESS CONN) :CHAOS)
			   (CHAOS:CONTACT-NAME CONN)))))
      (CASE CHOICE
	(:CLOSE    (CHAOS:CLOSE-CONN CONN "Manual Close from PEEK"))
	(:INSPECT  (INSPECT CONN))
	(:DETAIL   (SETF (ARRAY-LEADER ITEM (+ 4 TV:SCROLL-ITEM-LEADER-OFFSET)) CONN)
		   (SETF (ARRAY-LEADER ITEM (+ 5 TV:SCROLL-ITEM-LEADER-OFFSET)) T))
	(:UNDETAIL (SETF (ARRAY-LEADER ITEM (+ 4 TV:SCROLL-ITEM-LEADER-OFFSET)) NIL)
		   (SETF (ARRAY-LEADER ITEM (+ 5 TV:SCROLL-ITEM-LEADER-OFFSET)) NIL))))))

(DEFUN PEEK-SERVER-PREPROCESS (LIST-ITEM &AUX HOST)
  (LET* ((LINE-ITEM (THIRD LIST-ITEM))
	 (HOST-ITEM (SECOND LIST-ITEM))
	 (WANTED (ARRAY-LEADER LINE-ITEM (+ 4 TV:SCROLL-ITEM-LEADER-OFFSET)))
	 (GOT (ARRAY-LEADER LINE-ITEM (+ 5 TV:SCROLL-ITEM-LEADER-OFFSET))))
    (COND ((NULL WANTED)
	   (SETF (ARRAY-LEADER LINE-ITEM (+ 5 TV:SCROLL-ITEM-LEADER-OFFSET)) NIL)
	   (SETF (FOURTH LIST-ITEM) NIL))
	  ((EQ WANTED GOT))
	  (T
	   (SETF (FOURTH LIST-ITEM) (CHAOS:PEEK-CHAOS-CONN WANTED))
	   (SETF (ARRAY-LEADER LINE-ITEM (+ 5 TV:SCROLL-ITEM-LEADER-OFFSET)) WANTED)))
    ;; Hack hostat
    (COND ((ARRAY-LEADER HOST-ITEM TV:SCROLL-ITEM-LEADER-OFFSET)
	 ;; Want a hostat, make sure it's there and for the right host
	   (IF (AND (EQ (SETQ HOST (ARRAY-LEADER HOST-ITEM (1+ TV:SCROLL-ITEM-LEADER-OFFSET)))
			(ARRAY-LEADER HOST-ITEM  (+ TV:SCROLL-ITEM-LEADER-OFFSET 2)))
		    (FIFTH LIST-ITEM))
	       NIL
	     (SETF (FIFTH LIST-ITEM) (CONS '() (CHAOS:PEEK-CHAOS-HOSTAT HOST 1)))
	     (SETF (ARRAY-LEADER HOST-ITEM (+ TV:SCROLL-ITEM-LEADER-OFFSET 2)) HOST)))
	  (T (SETF (FIFTH LIST-ITEM) NIL)
	     (SETF (ARRAY-LEADER HOST-ITEM (+ TV:SCROLL-ITEM-LEADER-OFFSET 2)) NIL)))))


(MAKE-WINDOW 'PEEK-FRAME :ACTIVATE-P T)  ;Pre-create one for the system key
