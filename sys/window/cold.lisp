;;; -*- Mode:LISP; Package:SI; Base:8; Cold-load:T -*-
;	** (c) Copyright 1980 Massachusetts Institute of Technology **

;;; This file contains those portions of the window system that need
;;; to be in the cold-load, including the basic keyboard software and
;;; the cold load stream.

;;; Note that this file has to be in the SYSTEM-INTERNALS (SI) package
;;; rather than TV because it is part of the cold-load.

;compare these with SI:PROCESSOR-TYPE-CODE to conditionalize code for a specific machine.
(DEFCONST CADR-TYPE-CODE 1
  "The value which SI:PROCESSOR-TYPE-CODE has when you run on a CADR.")
(DEFCONST LAMBDA-TYPE-CODE 2
  "The value which SI:PROCESSOR-TYPE-CODE has when you run on a LAMBDA.")
(DEFCONST EXPLORER-TYPE-CODE 3
  "The value which SI:PROCESSOR-TYPE-CODE has when you run on an Explorer.")

(SETQ TV:MORE-PROCESSING-GLOBAL-ENABLE T)

(DEFVAR TV:DEFAULT-BACKGROUND-STREAM 'TV:BACKGROUND-STREAM)
(DEFCONST TV:WHO-LINE-RUN-LIGHT-LOC 51765
  "Where the run-light goes, in Xbus I//O space")
(DEFVAR TV:KBD-LAST-ACTIVITY-TIME 0
  "Time user last typed a key or clicked mouse.")

;;;magic BOOLE numbers
(DEFCONST TV:ALU-SETA 5 "Alu function for copying bits to destination.")
(DEFCONST TV:ALU-XOR 6 "Alu function for flipping bits in destination.")
(DEFCONST TV:ALU-ANDCA 2 "Alu function for clearing bits in destination.")
(DEFCONST TV:ALU-IOR 7 "Alu function for setting bits in destination.")
(DEFCONST TV:ALU-SETZ 0 "Alu function for setting bits in destination to zero.")
(DEFCONST TV:ALU-AND 1 "Alu function for anding.")

;;; Call this when the state of a process may have changed.
;;; In the cold-load because called by process stuff, loaded before window stuff.
(DEFUN TV:WHO-LINE-PROCESS-CHANGE (PROC)
  (AND (FBOUNDP 'TV:WHO-LINE-RUN-STATE-UPDATE) (EQ PROC TV:LAST-WHO-LINE-PROCESS)
       (TV:WHO-LINE-RUN-STATE-UPDATE)))

;;; Copy from SYS2;FLAVOR, needed for setting up the sync program
(DEFSUBST SYMEVAL-IN-INSTANCE (INSTANCE PTR)
  "Return the value of instance variable PTR in INSTANCE.
PTR can be a pointer to a value cell instead of a symbol.
Error if PTR does not work out to be a symbol which is an
instance variable in INSTANCE."
  (CONTENTS (LOCATE-IN-INSTANCE INSTANCE PTR)))

;;; Macros for cold-load construction

(DEFMACRO DEFINSTANCE-IMMEDIATE (NAME . INSTANCE-VARIABLES)
  (LET ((INSTANCE-VARIABLE-LIST-NAME (INTERN (STRING-APPEND NAME "-INSTANCE-VARIABLES")))
	(METHOD-LIST-NAME (INTERN (STRING-APPEND NAME "-WHICH-OPERATIONS"))))
    (SET METHOD-LIST-NAME NIL)
    (SET INSTANCE-VARIABLE-LIST-NAME INSTANCE-VARIABLES)
    `(PROGN 'COMPILE
	    (SETQ ,INSTANCE-VARIABLE-LIST-NAME ',INSTANCE-VARIABLES)
	    (SETQ ,METHOD-LIST-NAME NIL)
	    (DEFPROP ,NAME T SI:FLAVOR)		;This makes M-. work
	    (DEFVAR ,NAME))))

(DEFMACRO DECLARE-INSTANCE-IMMEDIATE-INSTANCE-VARIABLES ((NAME) . BODY)
  (LET ((INSTANCE-VARIABLE-LIST-NAME (INTERN (STRING-APPEND NAME "-INSTANCE-VARIABLES"))))
    `(LOCAL-DECLARE ((SPECIAL . ,(SYMEVAL INSTANCE-VARIABLE-LIST-NAME)))
       . ,BODY)))
(EVAL-WHEN (COMPILE LOAD)
  (DEFPROP DECLARE-INSTANCE-IMMEDIATE-INSTANCE-VARIABLES T MAY-SURROUND-DEFUN))

(DEFMACRO DEFMETHOD-IMMEDIATE ((NAME MESSAGE) ARGLIST . BODY)
  (LET ((METHOD-LIST-NAME (INTERN (STRING-APPEND NAME "-WHICH-OPERATIONS")))
	(METHOD-NAME (INTERN (STRING-APPEND NAME #/- MESSAGE "-METHOD"))))
    (OR (MEMQ MESSAGE (SYMEVAL METHOD-LIST-NAME))
	(PUSH MESSAGE (SYMEVAL METHOD-LIST-NAME)))
    `(DECLARE-INSTANCE-IMMEDIATE-INSTANCE-VARIABLES (,NAME)
     (DEFUN ,METHOD-NAME (IGNORE . ,ARGLIST)
       . ,BODY))))

(DEFMACRO MAKE-INSTANCE-IMMEDIATE (NAME INIT-PLIST-GENERATOR)
  (LET ((INSTANCE-VARIABLE-LIST-NAME (INTERN (STRING-APPEND NAME "-INSTANCE-VARIABLES")))
	(METHOD-LIST-NAME (INTERN (STRING-APPEND NAME "-WHICH-OPERATIONS")))
	(SEND-IF-HANDLES-METHOD-NAME
	  (INTERN (STRING-APPEND NAME "-SEND-IF-HANDLES")))
	(OPERATION-HANDLED-P-METHOD-NAME
	  (INTERN (STRING-APPEND NAME "-OPERATION-HANDLED-P")))
	(GET-HANDLER-FOR-METHOD-NAME
	  (INTERN (STRING-APPEND NAME "-GET-HANDLER-FOR")))
	(METHOD-LIST 'SI:UNCLAIMED-MESSAGE))
    (DOLIST (MESSAGE (SYMEVAL METHOD-LIST-NAME))
      (LET ((METHOD-NAME (INTERN (STRING-APPEND NAME #/- MESSAGE "-METHOD"))))
	(PUSH (CONS MESSAGE METHOD-NAME) METHOD-LIST)))
    (PUSH (CONS ':WHICH-OPERATIONS METHOD-LIST-NAME) METHOD-LIST)
    (PUSH (CONS ':SEND-IF-HANDLES SEND-IF-HANDLES-METHOD-NAME) METHOD-LIST)
    (PUSH (CONS ':OPERATION-HANDLED-P OPERATION-HANDLED-P-METHOD-NAME) METHOD-LIST)
    (PUSH (CONS ':GET-HANDLER-FOR GET-HANDLER-FOR-METHOD-NAME) METHOD-LIST)
    `(PROGN 'COMPILE
       (DEFUN ,SEND-IF-HANDLES-METHOD-NAME (IGNORE OPERATION &REST ARGS)
	 (IF (MEMQ OPERATION (,METHOD-LIST-NAME NIL))
	     (LEXPR-SEND SELF OPERATION ARGS)))
       (DEFUN ,OPERATION-HANDLED-P-METHOD-NAME (IGNORE OPERATION)
	 (MEMQ OPERATION (,METHOD-LIST-NAME NIL)))
       (DEFUN ,GET-HANDLER-FOR-METHOD-NAME (IGNORE OPERATION)
	 (IF (MEMQ OPERATION (,METHOD-LIST-NAME NIL))
	     (INTERN (STRING-APPEND ',NAME "-" OPERATION)
		     ',(PKG-NAME PACKAGE))))
       (DEFUN ,METHOD-LIST-NAME (IGNORE)
	 ',(SYMEVAL METHOD-LIST-NAME))
       (SETQ ,NAME (FAKE-UP-INSTANCE ',NAME ',(SYMEVAL INSTANCE-VARIABLE-LIST-NAME)
				     ',METHOD-LIST ',INIT-PLIST-GENERATOR)))))

(DEFINSTANCE-IMMEDIATE COLD-LOAD-STREAM
  ARRAY						;The array into which bits go
  LOCATIONS-PER-LINE				;Number of words in a screen line
  HEIGHT					;Height of screen
  WIDTH						;Width of screen
  CURSOR-X					;Current x position
  CURSOR-Y					;Current y position
  FONT						;The one and only font
  CHAR-WIDTH					;Width of a character
  LINE-HEIGHT					;Height of line, including vsp
  BUFFER					;The hardward buffer location
  TV:CONTROL-ADDRESS				;Hardware controller address
  UNRCHF					;For :UNTYI
  RUBOUT-HANDLER-BUFFER				;For :RUBOUT-HANDLER
  )

(DEFMETHOD-IMMEDIATE (COLD-LOAD-STREAM :PRINT-SELF) (STREAM &REST IGNORE)
  (FORMAT STREAM "#<~A ~O>" (TYPEP SELF) (%POINTER SELF)))

(DEFMETHOD-IMMEDIATE (COLD-LOAD-STREAM :DESCRIBE) ()
  (FORMAT *STANDARD-OUTPUT* "~&#<~A ~O> is the cold-load stream."
	  (TYPEP SELF) (%POINTER SELF)))

(DEFMETHOD-IMMEDIATE (COLD-LOAD-STREAM :INIT) (PLIST)
  (OR (BOUNDP 'KBD-TRANSLATE-TABLE)
      (KBD-INITIALIZE))
  (OR (BOUNDP 'TV:DEFAULT-SCREEN)
      (SETQ TV:DEFAULT-SCREEN SELF))
  (SETQ CURSOR-X 0 CURSOR-Y 0
	FONT (OR (GET PLIST ':FONT) FONTS:CPTFONT)
	UNRCHF NIL
	WIDTH (GET PLIST ':WIDTH)
	HEIGHT (GET PLIST ':HEIGHT)
	BUFFER (GET PLIST ':BUFFER)
	TV:CONTROL-ADDRESS (GET PLIST ':CONTROL-ADDRESS)
	ARRAY (MAKE-ARRAY (LIST WIDTH HEIGHT) ':TYPE 'ART-1B ':DISPLACED-TO BUFFER)
	LOCATIONS-PER-LINE (TRUNCATE WIDTH 32.)
	CHAR-WIDTH (FONT-CHAR-WIDTH FONT)
	LINE-HEIGHT (+ 2 (FONT-CHAR-HEIGHT FONT))
	RUBOUT-HANDLER-BUFFER (MAKE-ARRAY 1000 ':TYPE ART-STRING ':LEADER-LIST '(0 0 NIL))))
        ; leader elements are fill-pointer, scan-pointer, status

(DEFMETHOD-IMMEDIATE (COLD-LOAD-STREAM :READ-CURSORPOS) (&OPTIONAL (UNITS ':PIXEL)
					       &AUX (X CURSOR-X) (Y CURSOR-Y))
  (IF (EQ UNITS ':CHARACTER)
      (VALUES (CEILING X CHAR-WIDTH)
	      (CEILING Y LINE-HEIGHT))
    (VALUES X Y)))

(DEFMETHOD-IMMEDIATE (COLD-LOAD-STREAM :SET-CURSORPOS) (X Y &OPTIONAL (UNITS ':PIXEL))
  (AND (NUMBERP UNITS)				;***CROCK***, flush when format fixed
       (PSETQ UNITS X X Y Y UNITS))
  (AND (EQ UNITS ':CHARACTER)
       (SETQ X (* X CHAR-WIDTH)
	     Y (* Y LINE-HEIGHT)))
  (SETQ CURSOR-X (MAX 0 (MIN WIDTH X))
	CURSOR-Y (MAX 0 (MIN (- HEIGHT LINE-HEIGHT) Y))))

(DEFMETHOD-IMMEDIATE (COLD-LOAD-STREAM :HOME-CURSOR) ()
  (SETQ CURSOR-X 0 CURSOR-Y 0))

(DEFMETHOD-IMMEDIATE (COLD-LOAD-STREAM :HANDLE-EXCEPTIONS) ())

(DEFMETHOD-IMMEDIATE (COLD-LOAD-STREAM :TYO) (CH)
  (LET ((CURRENTLY-PREPARED-SHEET SELF))
    (COND ((< CH 200)
	   (LET ((CHAR-WIDTHS (FONT-CHAR-WIDTH-TABLE FONT))
		 (FIT-ENTRY (FONT-INDEXING-TABLE FONT))
		 (DELTA-X))
	     (SETQ DELTA-X (IF CHAR-WIDTHS (AREF CHAR-WIDTHS CH) (FONT-CHAR-WIDTH FONT)))
	     (AND (> (+ CURSOR-X DELTA-X) WIDTH)	;End of line exception
		  (SEND SELF ':TYO #/RETURN))
	     (IF (NULL FIT-ENTRY)
		 (%DRAW-CHAR FONT CH CURSOR-X CURSOR-Y TV:ALU-IOR SELF)
		 (DO ((CH (AREF FIT-ENTRY CH) (1+ CH))
		      (LIM (AREF FIT-ENTRY (1+ CH)))
		      (XPOS CURSOR-X (+ XPOS (FONT-RASTER-WIDTH FONT))))
		     ((= CH LIM))
		   (%DRAW-CHAR FONT CH XPOS CURSOR-Y TV:ALU-IOR SELF)))
	     (SETQ CURSOR-X (+ CURSOR-X DELTA-X))))
	  ((= CH #/RETURN)
	   (SETQ CURSOR-X 0
		 CURSOR-Y (+ CURSOR-Y LINE-HEIGHT))
	   (COND (( CURSOR-Y HEIGHT)		;End-of-page exception
		  (SETQ CURSOR-Y 0))
		 (( CURSOR-Y (- HEIGHT (* 2 LINE-HEIGHT)))	;MORE exception
		  (SEND SELF ':CLEAR-EOL)	;In case wholine is there
		  (WHEN TV:MORE-PROCESSING-GLOBAL-ENABLE
		    (SEND SELF ':STRING-OUT "**MORE**")
		    (SEND SELF ':TYI))
		  (SETQ CURSOR-X 0)
		  (SEND SELF ':CLEAR-EOL)
		  (SETQ CURSOR-Y 0)))
	   (SEND SELF ':CLEAR-EOL))
	  ((= CH #/TAB)
	   (DOTIMES (I (- 8 (\ (TRUNCATE CURSOR-X CHAR-WIDTH) 8)))
	     (SEND SELF ':TYO #/SPACE)))
	  ((AND (< CH 240) (BOUNDP 'FONTS:5X5))
	   ;; This won't work in the initial cold-load environment, hopefully no one
	   ;; will touch those keys then, but if they do we just type nothing.
	   ;; This code is like SHEET-DISPLAY-LOZENGED-STRING
	   (LET* ((CHNAME (GET-PNAME (CAR (RASSOC CH XR-SPECIAL-CHARACTER-NAMES))))
		  (CHWIDTH (+ (* (ARRAY-ACTIVE-LENGTH CHNAME) 6) 10.)))
	     (AND (> (+ CURSOR-X CHWIDTH) WIDTH)	;Won't fit on line
		  (SEND SELF ':TYO #/CR))
	     ;; Put the string then the box around it
	     (LET ((X0 CURSOR-X)
		   (Y0 (1+ CURSOR-Y))
		   (X1 (+ CURSOR-X (1- CHWIDTH)))
		   (Y1 (+ CURSOR-Y 9)))
	       (DO ((X (+ X0 5) (+ X 6))
		    (I 0 (1+ I))
		    (N (ARRAY-ACTIVE-LENGTH CHNAME)))
		   (( I N))
		 (%DRAW-CHAR FONTS:5X5 (AREF CHNAME I) X (+ Y0 2) TV:ALU-IOR SELF))
	       (%DRAW-RECTANGLE (- CHWIDTH 8) 1 (+ X0 4) Y0 TV:ALU-IOR SELF)
	       (%DRAW-RECTANGLE (- CHWIDTH 8) 1 (+ X0 4) Y1 TV:ALU-IOR SELF)
	       (%DRAW-LINE X0 (+ Y0 4) (+ X0 3) (1+ Y0) TV:ALU-IOR T SELF)
	       (%DRAW-LINE (1+ X0) (+ Y0 5) (+ X0 3) (1- Y1) TV:ALU-IOR T SELF)
	       (%DRAW-LINE X1 (+ Y0 4) (- X1 3) (1+ Y0) TV:ALU-IOR T SELF)
	       (%DRAW-LINE (1- X1) (+ Y0 5) (- X1 3) (1- Y1) TV:ALU-IOR T SELF)
	       (SETQ CURSOR-X (1+ X1))))))
    CH))

(DEFMETHOD-IMMEDIATE (COLD-LOAD-STREAM :CLEAR-EOL) ()
  (LET ((CURRENTLY-PREPARED-SHEET SELF))
    (%DRAW-RECTANGLE (- WIDTH CURSOR-X) LINE-HEIGHT CURSOR-X CURSOR-Y TV:ALU-ANDCA SELF)))

(DEFMETHOD-IMMEDIATE (COLD-LOAD-STREAM :CLEAR-SCREEN) ()
  (SETQ CURSOR-X 0 CURSOR-Y 0)
  (LET ((CURRENTLY-PREPARED-SHEET SELF))
    (%DRAW-RECTANGLE WIDTH HEIGHT 0 0 TV:ALU-ANDCA SELF)))

(DEFMETHOD-IMMEDIATE (COLD-LOAD-STREAM :FRESH-LINE) ()
  (IF (ZEROP CURSOR-X)
      (SEND SELF ':CLEAR-EOL)
    (SEND SELF ':TYO #/RETURN)))

(DEFMETHOD-IMMEDIATE (COLD-LOAD-STREAM :STRING-OUT) (STRING &OPTIONAL (START 0) END)
  (DO ((I START (1+ I))
       (END (OR END (ARRAY-ACTIVE-LENGTH STRING))))
      (( I END))
    (SEND SELF ':TYO (AREF STRING I))))

(DEFMETHOD-IMMEDIATE (COLD-LOAD-STREAM :LINE-OUT) (STRING &OPTIONAL (START 0) END)
  (SEND SELF ':STRING-OUT STRING START END)
  (SEND SELF ':TYO #/RETURN))

(DEFMETHOD-IMMEDIATE (COLD-LOAD-STREAM :UNTYI) (CH)
  (IF (EQ RUBOUT-HANDLER SELF)
      (DECF (ARRAY-LEADER RUBOUT-HANDLER-BUFFER 1))
    (SETQ UNRCHF CH)))

(DEFMETHOD-IMMEDIATE (COLD-LOAD-STREAM :LISTEN) ()
  (OR UNRCHF
      (DO () ((NOT (KBD-HARDWARE-CHAR-AVAILABLE)) NIL)
	(AND (SETQ UNRCHF (KBD-CONVERT-TO-SOFTWARE-CHAR (KBD-GET-HARDWARE-CHAR)))
	     (RETURN T)))))

(DEFMETHOD-IMMEDIATE (COLD-LOAD-STREAM :ANY-TYI) (&OPTIONAL IGNORE)
  (SEND SELF ':TYI))

(DEFMETHOD-IMMEDIATE (COLD-LOAD-STREAM :ANY-TYI-NO-HANG) ()
  (SEND SELF ':TYI-NO-HANG))

(DEFMETHOD-IMMEDIATE (COLD-LOAD-STREAM :TYI) (&OPTIONAL IGNORE
							&AUX IDX (INHIBIT-SCHEDULING-FLAG T))
  (COND	((NEQ RUBOUT-HANDLER SELF)
	 (IF UNRCHF
	     (PROG1 UNRCHF (SETQ UNRCHF NIL))
	   (DO-FOREVER
	     (COLD-LOAD-STREAM-WAIT-FOR-CHAR)
	     (LET ((CHAR (KBD-CONVERT-TO-SOFTWARE-CHAR (KBD-GET-HARDWARE-CHAR))))
	       (SELECTQ CHAR
		 (NIL)				;Unreal character
		 (#/BREAK (BREAK "BREAK"))
		 ;; Kludge to make the debugger more usable in the cold-load stream
		 (#/ABORT (IF EH:READING-COMMAND (RETURN CHAR)
			    (SIGNAL EH:ABORT-OBJECT)))
		 (OTHERWISE (RETURN CHAR)))))))
	((> (FILL-POINTER RUBOUT-HANDLER-BUFFER)
	    (SETQ IDX (ARRAY-LEADER RUBOUT-HANDLER-BUFFER 1)))
	 (SETF (ARRAY-LEADER RUBOUT-HANDLER-BUFFER 1) (1+ IDX))
	 (AREF RUBOUT-HANDLER-BUFFER IDX))
	(T
	 (COLD-LOAD-STREAM-RUBOUT-HANDLER))))

(DEFMETHOD-IMMEDIATE (COLD-LOAD-STREAM :TYI-NO-HANG) ()
  (AND (SEND SELF ':LISTEN)
       (SEND SELF ':TYI)))

(DEFMETHOD-IMMEDIATE (COLD-LOAD-STREAM :LINE-IN) (&OPTIONAL ARG1)
  (LET ((BUF (MAKE-ARRAY 100 ':TYPE ART-STRING
			    ':LEADER-LENGTH (IF (NUMBERP ARG1) ARG1 1))))
       (STORE-ARRAY-LEADER 0 BUF 0)		;Fill pointer
       (VALUES BUF
	       (DO ((TEM (FUNCALL-SELF ':TYI NIL) (FUNCALL-SELF ':TYI NIL)))
		   ((OR (NULL TEM) (= TEM #\CR) (= TEM #\END))
		    (ADJUST-ARRAY-SIZE BUF (ARRAY-ACTIVE-LENGTH BUF))
		    (NULL TEM))
		 (ARRAY-PUSH-EXTEND BUF TEM)))))

(DEFVAR COLD-LOAD-STREAM-BLINKER-TIME 15.)
(DEFVAR COLD-LOAD-STREAM-WAIT-TIME 1000.)
(DECLARE-INSTANCE-IMMEDIATE-INSTANCE-VARIABLES (COLD-LOAD-STREAM)
(DEFUN COLD-LOAD-STREAM-WAIT-FOR-CHAR ()
  (DO ((PHASE NIL)
       (BLINKER-COUNT 0)
       (CURRENTLY-PREPARED-SHEET SELF))
      ((KBD-HARDWARE-CHAR-AVAILABLE)
       (AND PHASE
	    (%DRAW-RECTANGLE (FONT-BLINKER-WIDTH FONT) (FONT-BLINKER-HEIGHT FONT) CURSOR-X
			     CURSOR-Y TV:ALU-XOR SELF)))
    (COND ((MINUSP (SETQ BLINKER-COUNT (1- BLINKER-COUNT)))
	   (%DRAW-RECTANGLE (FONT-BLINKER-WIDTH FONT) (FONT-BLINKER-HEIGHT FONT) CURSOR-X
			     CURSOR-Y TV:ALU-XOR SELF)
	   (SETQ PHASE (NOT PHASE)
		 BLINKER-COUNT COLD-LOAD-STREAM-BLINKER-TIME)))
    (DOTIMES (I COLD-LOAD-STREAM-WAIT-TIME)))))

(defvar rubout-handler-options nil
  "The options supplied as first arg to :RUBOUT-HANDLER operation or to WITH-INPUT-EDITING.")

(defvar cold-load-stream-activation-character)

;;; Give a single character, or do rubout processing, throws to RUBOUT-HANDLER on editing.
(declare-instance-immediate-instance-variables (cold-load-stream)
(defun cold-load-stream-rubout-handler ()
  (declare (special tv:prompt-starting-x tv:prompt-starting-y))
  (when (= (array-leader rubout-handler-buffer 1) most-positive-fixnum)
    (setf (array-leader rubout-handler-buffer 1) 0)
    (*throw 'rubout-handler t))
  (if cold-load-stream-activation-character
      (return-from cold-load-stream-rubout-handler
	(prog1 cold-load-stream-activation-character
	       (setq cold-load-stream-activation-character nil))))
  (do ((ch)
       (rubbed-out-some)
       (len)
       (rubout-handler nil)
       (pass-through (cdr (assq ':pass-through rubout-handler-options)))
       (editing-command (cdr (assq ':editing-command rubout-handler-options)))
       (do-not-echo (cdr (assq ':do-not-echo rubout-handler-options)))
       (command-handler
	 (assq ':command rubout-handler-options))
       (activation-handler
	 (assq ':activation rubout-handler-options))
       (initial-input (cadr (assq ':initial-input rubout-handler-options)))
       (status (array-leader rubout-handler-buffer 2) nil))
      (nil)
    (setf (array-leader rubout-handler-buffer 2) nil)
    (when (memq status '(:initial-entry :restored))
      (multiple-value (tv:prompt-starting-x tv:prompt-starting-y)
	(send self ':read-cursorpos))
      (let ((prompt-option (assq ':prompt rubout-handler-options)))
	(when (and prompt-option (fboundp 'tv:rubout-handler-prompt))
	  (tv:rubout-handler-prompt (cadr prompt-option) self nil)))
      (when initial-input
	(let ((length (length initial-input)))
	  (send self ':string-out initial-input)
	  (if (< (array-length rubout-handler-buffer) length)
	      (setq rubout-handler-buffer (array-grow rubout-handler-buffer
						      (+ length length))))
	  (copy-array-portion initial-input 0 length rubout-handler-buffer 0 length)
	  (setf (fill-pointer rubout-handler-buffer) length)
	  (setq rubbed-out-some t))))
    (setq ch (send self ':tyi))
    (cond ((and command-handler
		(apply (cadr command-handler) ch (cddr command-handler)))
	     (setf (array-leader rubout-handler-buffer 1) 0)
	     (*throw 'tv:return-from-rubout-handler
		     (values
		       `(:command ,ch 1)
		       ':command)))
	  ;; Don't touch this character, just return it to caller.
	  ((or (memq ch editing-command)
	       (assq-careful ch editing-command))
	   ;; Cause rubout handler rescan next time the user does :TYI.
	   (if rubbed-out-some
	       (setf (array-leader rubout-handler-buffer 1) most-positive-fixnum))
	   (return ch))
	  ((and (not (or (memq ch do-not-echo)
			 (memq ch pass-through)
			 (and activation-handler
			      (apply (cadr activation-handler) ch (cddr activation-handler)))))
		(or (ldb-test %%kbd-control-meta ch)
		    (memq ch '(#/Rubout #/Clear-input #/Clear-screen #/Delete))))
	   (cond
	     ((= ch #/Clear)			;CLEAR flushes all buffered input
	      (setf (fill-pointer rubout-handler-buffer) 0)
	      (setq rubbed-out-some t)		;Will need to throw out
	      (send self ':tyo ch)		;Echo and advance to new line
	      (send self ':tyo #/Cr))
	     ((or (= ch #/Form) (= ch #/Delete));Retype buffered input
	      (send self ':tyo ch)		;Echo it
	      (if (= ch #/Form) (send self ':clear-screen) (send self ':tyo #/Return))
	      (let ((prompt (cadr (or (assq ':reprompt rubout-handler-options)
				      (assq ':prompt rubout-handler-options)))))
		(when (and prompt (fboundp 'tv:rubout-handler-prompt))
		  (tv:rubout-handler-prompt prompt self ch)))
	      (send self ':string-out rubout-handler-buffer))
	     ((= ch #/Rubout)
	      (cond ((not (zerop (setq len (fill-pointer rubout-handler-buffer))))
		     (setq cursor-x (max 0 (- cursor-x char-width)))
		     (send self ':clear-eol)
		     (setf (fill-pointer rubout-handler-buffer) (decf len))
		     (setq rubbed-out-some t)
		     (cond ((zerop len)
			    (setf (array-leader rubout-handler-buffer 1) 0)
			    (*throw 'rubout-handler t))))))
	     ((ldb-test %%kbd-control-meta ch)
	      (kbd-convert-beep)))
	   (cond ((and (zerop (fill-pointer rubout-handler-buffer))
		       (assq ':full-rubout rubout-handler-options))
		  (setf (array-leader rubout-handler-buffer 1) 0)
		  (*throw 'rubout-handler t))))
	  (t						;It's a self-inserting character
	   (cond ((memq ch do-not-echo)
		  (setq cold-load-stream-activation-character ch))
		 ((and activation-handler
		       (apply (cadr activation-handler) ch (cddr activation-handler)))
		  (setq ch `(:activation ,ch 1))
		  (setq cold-load-stream-activation-character ch))
		 (t
		  (if (ldb-test %%kbd-control-meta ch)	;in :pass-through, but had bucky bits
		      (kbd-convert-beep)
		    (send self ':tyo ch)
		    (array-push-extend rubout-handler-buffer ch))))
	   (cond ((and (atom ch)
		       (ldb-test %%kbd-control-meta ch)))	;do nothing
		 (rubbed-out-some
		  (setf (array-leader rubout-handler-buffer 1) 0)
		  (*throw 'rubout-handler t))
		 (t
		  (setf (array-leader rubout-handler-buffer 1)
			(fill-pointer rubout-handler-buffer))
		  (setq cold-load-stream-activation-character nil)
		  (return ch))))))))

(defmethod-immediate (cold-load-stream :rubout-handler)
		     (options function &rest args)
  (declare (arglist rubout-handler-options function &rest args))
  (if (and (eq rubout-handler self) (not (cdr (assq ':nonrecursive options))))
      (let ((rubout-handler-options (append options rubout-handler-options)))
	(apply function args))
    (let ((rubout-handler-options options))
      (setf (fill-pointer rubout-handler-buffer) 0)
      (setf (array-leader rubout-handler-buffer 1) 0)
      (setf (array-leader rubout-handler-buffer 2) ':initial-entry)
      (let (tv:prompt-starting-x tv:prompt-starting-y)
	(declare (special tv:prompt-starting-x tv:prompt-starting-y))
	(*catch 'tv:return-from-rubout-handler
	  (do ((rubout-handler self)			;Establish rubout handler
	       (inhibit-scheduling-flag t)		;Make sure all chars come here
	       (cold-load-stream-activation-character nil))
	      (nil)
	    (*catch 'rubout-handler			;Throw here when rubbing out
	      (condition-case (error)
		  (return (apply function args))	;Call read type function
		(parse-error
		 (send self ':fresh-line)
		 (princ ">>ERROR: " self)
		 (send error ':report self)
		 (send self ':fresh-line)
		 (send self ':string-out rubout-handler-buffer)	;On error, retype buffered
		 (do-forever (send self ':tyi)))))		;and force user to edit it
	    ;;Maybe return when user rubs all the way back
	    (and (zerop (fill-pointer rubout-handler-buffer))
		 (let ((full-rubout-option (assq ':full-rubout rubout-handler-options)))
		   (when full-rubout-option
		     ;; Get rid of the prompt, if any.
		     (send self ':set-cursorpos tv:prompt-starting-x tv:prompt-starting-y)
		     (send self ':clear-eol)
		     (return nil (cadr full-rubout-option)))))))))))


(DEFMETHOD-IMMEDIATE (COLD-LOAD-STREAM :CLEAR-INPUT) ()
  (SETQ UNRCHF NIL)
  (SETF (FILL-POINTER RUBOUT-HANDLER-BUFFER) 0)
  (SETF (ARRAY-LEADER RUBOUT-HANDLER-BUFFER 1) 0)
  (DO () ((NOT (KBD-HARDWARE-CHAR-AVAILABLE)))
    ;;Call the convert routine for up-shifts too
    (KBD-CONVERT-TO-SOFTWARE-CHAR (KBD-GET-HARDWARE-CHAR))))

(DEFMETHOD-IMMEDIATE (COLD-LOAD-STREAM :BEEP) (&OPTIONAL BEEP-TYPE) BEEP-TYPE
  (KBD-CONVERT-BEEP))

(DEFUN KBD-HARDWARE-CHAR-AVAILABLE ()
  "Returns T if a character is available in the microcode interrupt buffer"
  ( (%P-LDB %%Q-POINTER (+ 500 %UNIBUS-CHANNEL-BUFFER-IN-PTR))
     (%P-LDB %%Q-POINTER (+ 500 %UNIBUS-CHANNEL-BUFFER-OUT-PTR))))

(DEFUN KBD-GET-HARDWARE-CHAR (&AUX P)
  "Returns the next character in the microcode interrupt buffer, and NIL if there is none"
  (WHEN ( (%P-LDB %%Q-POINTER (+ 500 %UNIBUS-CHANNEL-BUFFER-IN-PTR))
	   (SETQ P (%P-LDB %%Q-POINTER (+ 500 %UNIBUS-CHANNEL-BUFFER-OUT-PTR))))
    (PROG1 (%P-LDB %%Q-POINTER P)
	   (INCF P)
	   (WHEN (= P (%P-LDB %%Q-POINTER (+ 500 %UNIBUS-CHANNEL-BUFFER-END)))
	     (SETQ P (%P-LDB %%Q-POINTER (+ 500 %UNIBUS-CHANNEL-BUFFER-START))))
	   (%P-DPB P %%Q-POINTER (+ 500 %UNIBUS-CHANNEL-BUFFER-OUT-PTR)))))

(DEFVAR SHIFT-LOCK-XORS NIL)	;If T, both SHIFT LOCK and SHIFT is the same as neither
				; if the character is alphabetic

(DEFUN KBD-CONVERT-TO-SOFTWARE-CHAR (HARD-CHAR &OPTIONAL (UPCASE-CONTROL-CHARS T)
				     &AUX ASC SHIFT BUCKY)
  "Convert hardware character to software character, or NIL to ignore.
UPCASE-CONTROL-CHARS if NIL means leave Meta-lowercase-letter, etc.,
not converted to upper case."
  (SELECTQ (LDB 2003 HARD-CHAR)			;Source ID
    (1 (KBD-CONVERT-NEW HARD-CHAR UPCASE-CONTROL-CHARS))		;New keyboard
    (2 (KBD-CONVERT-NEWER HARD-CHAR UPCASE-CONTROL-CHARS))  ;8 bit serial keyboard
    (6 (SET-MOUSE-MODE 'VIA-KBD)		;Mouse via keyboard - turn on remote mouse
       NIL)					; enable bit in IOB
    (7						;Old keyboard
      (SETQ SHIFT (COND ((BIT-TEST 1400 HARD-CHAR) 2)	;TOP
			((BIT-TEST 300 HARD-CHAR) 1)	;SHIFT
			(T 0)))				;VANILLA
      (SETQ BUCKY (+ (IF (BIT-TEST 06000 HARD-CHAR) 0400 0)	;CONTROL
		     (IF (BIT-TEST 30000 HARD-CHAR) 1000 0)))	;META
      (SETQ ASC (AREF KBD-TRANSLATE-TABLE SHIFT (LOGAND 77 HARD-CHAR)))
      (AND (BIT-TEST 40000 HARD-CHAR)			;SHIFT LOCK
	   (IF (AND SHIFT-LOCK-XORS (BIT-TEST 300 HARD-CHAR))
	       (AND ( ASC #/A) ( ASC #/Z) (SETQ ASC (+ ASC 40)))
	       (AND ( ASC #/a) ( ASC #/z) (SETQ ASC (- ASC 40)))))
      (AND (NOT (ZEROP BUCKY)) ( ASC #/a) ( ASC #/z)
	   (SETQ ASC (- ASC 40)))		;Control characters always uppercase
      (+ ASC BUCKY))))

;; Sys com locations 500-511 are reserved for the wired keyboard buffer:
;; Locations 501 through 511 contain the buffer header; the actual buffer
;; is in locations 200-377 (128. chars, 64. on new-keyboards)
;;
;; This is called when the machine is booted, warm or cold.  It's not an
;; initialization because it has to happen before all other initializations.
(DEFUN INITIALIZE-WIRED-KBD-BUFFER ()
  (COND ((= PROCESSOR-TYPE-CODE LAMBDA-TYPE-CODE)
	 (%NUBUS-WRITE TV:TV-SLOT-NUMBER 4
		       (LOGAND (LOGNOT 40) (COMPILER:%NUBUS-READ TV:TV-SLOT-NUMBER 4)))))
  (DO ((I 500 (1+ I))) ((= I 512))
    (%P-DPB 0 %%Q-LOW-HALF I)
    (%P-DPB 0 %%Q-HIGH-HALF I))
  (DO ((I 200 (1+ I))) ((= I 400))
    (%P-DPB 0 %%Q-LOW-HALF I)
    (%P-DPB 0 %%Q-HIGH-HALF I))
  (%P-DPB 260 %%Q-POINTER (+ 500 %UNIBUS-CHANNEL-VECTOR-ADDRESS))
  (%P-DPB (VIRTUAL-UNIBUS-ADDRESS 764112) %%Q-POINTER (+ 500 %UNIBUS-CHANNEL-CSR-ADDRESS))
  (%P-DPB 40 %%Q-POINTER (+ 500 %UNIBUS-CHANNEL-CSR-BITS))
  (%P-DPB 1 %%UNIBUS-CSR-TWO-DATA-REGISTERS (+ 500 %UNIBUS-CHANNEL-CSR-BITS))
  (%P-DPB 1 %%UNIBUS-CSR-SB-ENABLE (+ 500 %UNIBUS-CHANNEL-CSR-BITS))
  (%P-DPB (VIRTUAL-UNIBUS-ADDRESS 764100) %%Q-POINTER (+ 500 %UNIBUS-CHANNEL-DATA-ADDRESS))
;  (%P-DPB 1 %%Q-FLAG-BIT (+ 500 %UNIBUS-CHANNEL-DATA-ADDRESS))
  (%P-DPB 200 %%Q-POINTER (+ 500 %UNIBUS-CHANNEL-BUFFER-START))
  (%P-DPB 400 %%Q-POINTER (+ 500 %UNIBUS-CHANNEL-BUFFER-END))
;  (%P-DPB 1 %%Q-FLAG-BIT (+ 500 %UNIBUS-CHANNEL-BUFFER-END))	;Enable seq breaks.
  (%P-DPB 200 %%Q-POINTER (+ 500 %UNIBUS-CHANNEL-BUFFER-IN-PTR))
  (%P-DPB 200 %%Q-POINTER (+ 500 %UNIBUS-CHANNEL-BUFFER-OUT-PTR))
  (SETF (SYSTEM-COMMUNICATION-AREA %SYS-COM-UNIBUS-INTERRUPT-LIST) 500)
  (SET-MOUSE-MODE 'DIRECT))

(DEFUN SET-MOUSE-MODE (MODE)
  (SELECT PROCESSOR-TYPE-CODE
    (CADR-TYPE-CODE
     (SELECTQ MODE
       (DIRECT (%UNIBUS-WRITE 764112 4));Keyboard interrupt enable, local mouse
       (VIA-KBD (%UNIBUS-WRITE 764112 5))
       (OTHERWISE (FERROR NIL "UNKNOWN MOUSE MODE"))))
    (LAMBDA-TYPE-CODE
     NIL)))

;; Translate from a Unibus address to a Lisp machine virtual address, returning a fixnum.
(DEFUN VIRTUAL-UNIBUS-ADDRESS (ADR)
  (SELECT PROCESSOR-TYPE-CODE
    (CADR-TYPE-CODE
     (%MAKE-POINTER-OFFSET DTP-FIX (LSH 7740 12.) (LSH ADR -1)))
    (LAMBDA-TYPE-CODE
     (%MAKE-POINTER-OFFSET DTP-FIX (LSH 7737 12.) 7777))  ;will trap if ref'ed
    ))

(DEFVAR KBD-TRANSLATE-TABLE)
;Keyboard translate table is a 3 X 64 array.
;3 entries for each of 100 keys.  First is vanilla, second shift, third top.
;The function KBD-INITIALIZE is only called once, in order to setup this array.

(DEFUN KBD-INITIALIZE ()
  (SETQ KBD-TRANSLATE-TABLE (MAKE-ARRAY '(3 100)
					':AREA  WORKING-STORAGE-AREA
					':TYPE 'ART-8B))
  (DO ((I 0 (1+ I))  ;2ND DIMENSION
       (L '(
	#/BREAK	#/BREAK	#/NETWORK
	#/ESC	#/ESC	#/SYSTEM
	#/1	#/!	#/!
	#/2	#/"	#/"
	#/3	#/#	#/#
	#/4	#/$	#/$
	#/5	#/%	#/%
	#/6	#/&	#/&
	#/7	#/'	#/'
	#/8	#/(	#/(
	#/9	#/)	#/)
	#/0	#/_	#/_
	#/-	#/=	#/=
	#/@	#/`	#/`
	#/^	#/~	#/~
	#/BS	#/BS	#/BS
	#/CALL	#/CALL	#/ABORT
	#/CLEAR	#/CLEAR	#/CLEAR
	#/TAB	#/TAB	#/TAB
	#/	#/	#/
	#/q	#/Q	#/
	#/w	#/W	#/
	#/e	#/E	#/
	#/r	#/R	#/
	#/t	#/T	#/
	#/y	#/Y	#/
	#/u	#/U	#/
	#/i	#/I	#/
	#/o	#/O	#/
	#/p	#/P	#/
	#/[	#/{	#/{
	#/]	#/}	#/}
	#/\	#/|	#/|
	#//	#/	#/
	#/	#/
	#/ 
	#/	#/		#/	
	#/FORM	#/FORM	#/FORM
	#/VT	#/VT	#/VT
	#/RUBOUT #/RUBOUT #/RUBOUT
	#/a	#/A	#/
	#/s	#/S	#/
	#/d	#/D	#/
	#/f	#/F	#/
	#/g	#/G	#/
	#/h	#/H	#/HELP
	#/j	#/J	#/
	#/k	#/K	#/
	#/l	#/L	#/
	#/;	#/+	#/+
	#/:	#/*	#/*
	#/CR	#/CR	#/END
	#/LINE	#/LINE	#/LINE
	#/BACK-NEXT #/BACK-NEXT #/BACK-NEXT
	#/z	#/Z	#/
	#/x	#/X	#/
	#/c	#/C	#/
	#/v	#/V	#/
	#/b	#/B	#/
	#/n	#/N	#/
	#/m	#/M	#/
	#/,	#/<	#/<
	#/.	#/>	#/>
	#//	#/?	#/?
	#/SP	#/SP	#/SP
	) (CDDDR L)))
      ((NULL L))
    (AS-2 (CAR L) KBD-TRANSLATE-TABLE 0 I)
    (AS-2 (CADR L) KBD-TRANSLATE-TABLE 1 I)
    (AS-2 (CADDR L) KBD-TRANSLATE-TABLE 2 I)))

;Support for new keyboard

;These two variables are bit masks for the shifting keys held down.
;Bit numbers are the same as those in the all-keys-up code sent by the
;keyboard, i.e.
;	0 shift		3 caps lock	6 super		9 mode lock
;	1 greek		4 control	7 hyper		10 repeat
;	2 top		5 meta		8 alt lock
;There are two variables so that if both shifts of a given type are pushed
;down. then one is released, we can tell what's going on.

(DEFVAR KBD-LEFT-SHIFTS 0)
(DEFVAR KBD-RIGHT-SHIFTS 0)
(DEFVAR KBD-KEY-STATE-ARRAY			;1 if key with that ascii code is down
	(MAKE-ARRAY 400 ':TYPE 'ART-1B ':AREA PERMANENT-STORAGE-AREA))
(DEFVAR KBD-KEY-STATE-ARRAY-16B			;For fast clearing of above array
	(MAKE-ARRAY 20 ':TYPE 'ART-16B ':AREA PERMANENT-STORAGE-AREA
		    ':DISPLACED-TO KBD-KEY-STATE-ARRAY))

(DECLARE (SPECIAL KBD-NEW-TABLE))	;Array used as translation table.
;The second dimension is 200 long and indexed by keycode.
;The first dimension is the shifts:
; 0 unshifted
; 1 shift
; 2 top
; 3 greek
; 4 shift greek
;Elements in the table are 16-bit unsigned numbers.
;Bit 15 on and bit 14 on means undefined code, ignore and beep.
;Bit 15 on and bit 14 off means low bits are shift for bit in KBD-SHIFTS
;   (40 octal for right-hand key of a pair)
;Bit 15 off is ordinary code.

;Can return NIL if character wasn't really a character.
(DEFUN KBD-CONVERT-NEW (CH &OPTIONAL (CTL-CHARS-UPPERCASE T))
  (COND ((BIT-TEST 1_15. CH)		;An all-keys-up code, just update shifts mask
	 (COPY-ARRAY-CONTENTS "" KBD-KEY-STATE-ARRAY-16B)	;Mark all keys up
	 (SETQ CH (LDB 0017 CH))	;Get bits for keys or key-pairs still down
	 (SETQ KBD-LEFT-SHIFTS (LOGAND KBD-LEFT-SHIFTS CH)
	       KBD-RIGHT-SHIFTS (LOGAND KBD-RIGHT-SHIFTS CH)
	       KBD-LEFT-SHIFTS		;This is for keys that are down that we thought
	         (LOGIOR		; were up, e.g. caps lock.  Boole 10 is NOR.
		   (LOGAND (BOOLE 10 KBD-LEFT-SHIFTS KBD-RIGHT-SHIFTS) CH)
		   KBD-LEFT-SHIFTS)
	      TV:KBD-BUTTONS 0)		;analogous to mouse buttons, set by roman numerals
	 NIL)
	(T (LET* ((KBD-SHIFTS (LOGIOR KBD-LEFT-SHIFTS KBD-RIGHT-SHIFTS))
		  (NCH (AREF KBD-NEW-TABLE	;NCH gets translate-table entry
			     (COND ((BIT-TEST 2 KBD-SHIFTS)	;Greek
				    (+ (LOGAND 1 KBD-SHIFTS) 3))
				   ((BIT-TEST 4 KBD-SHIFTS) 2)	;Top
				   ((BIT-TEST 1 KBD-SHIFTS) 1)	;Shift
				   (T 0))
			     (LDB 0007 CH)))
		  (NCH0 (AREF KBD-NEW-TABLE 0 (LDB 0007 CH))))
	     (COND ((BIT-TEST 1_15. NCH)	;Not a real character
		    (COND ((BIT-TEST 1_14. NCH)	;Undefined key, beep if key-down
			   (OR (BIT-TEST 1_8 CH)
			       (KBD-CONVERT-BEEP)))
			  (T			;A shifting key, update KBD-SHIFTS
			    (LET ((BOOLE (IF (BIT-TEST 1_8 CH) 2 7))  ;Bit off, on
				  (BIT (LSH 1 (LOGAND NCH 37))))
			      (IF (BIT-TEST 40 NCH)
				  (SETQ KBD-RIGHT-SHIFTS (BOOLE BOOLE BIT KBD-RIGHT-SHIFTS))
				  (SETQ KBD-LEFT-SHIFTS (BOOLE BOOLE BIT KBD-LEFT-SHIFTS))))))
		    NIL)
		   ((BIT-TEST 1_8 CH)
		    (setf (aref KBD-KEY-STATE-ARRAY NCH0) 0)
		    (COND ((BIT-TEST 1_9 KBD-SHIFTS)	 ;Mode lock
			   (SELECTQ NCH
			     (#/ROMAN-I (SETQ TV:KBD-BUTTONS (BOOLE 4 TV:KBD-BUTTONS 1)))
			     (#/ROMAN-II (SETQ TV:KBD-BUTTONS (BOOLE 4 TV:KBD-BUTTONS 2)))
			     (#/ROMAN-III (SETQ TV:KBD-BUTTONS (BOOLE 4 TV:KBD-BUTTONS 4))))
			   (SETQ MOUSE-WAKEUP T)))
		    NIL)	 ;Just an up-code
		   ((AND (BIT-TEST 1_9 KBD-SHIFTS)	 ;Mode lock
			 (MEMQ NCH '(#/ROMAN-I #/ROMAN-II #/ROMAN-III)))
		    (setf (aref KBD-KEY-STATE-ARRAY NCH0) 1)
		    (SETQ TV:KBD-BUTTONS (LOGIOR TV:KBD-BUTTONS
						 (SELECTQ NCH (#/ROMAN-I 1)
							  (#/ROMAN-II 2)
							  (T 4))))
		    (SETQ MOUSE-WAKEUP T)
		    NIL)
		   (T ;A real key depression.  Check for caps-lock.
		    (setf (aref KBD-KEY-STATE-ARRAY NCH0) 1)
		    (SETQ NCH0 (LDB 0404 KBD-SHIFTS))	;Hyper, Super, Meta, Control bits
		    (IF (AND CTL-CHARS-UPPERCASE
			     (NOT (ZEROP NCH0)))
			(IF ( #/a NCH #/z)
			    (DECF NCH 40)	;Control characters always uppercase,
			  (IF ( #/A NCH #/Z)	;except if Shift is typed they are lowercase.
			      (INCF NCH 40)))
		      ;; Except for control chars for which Shift is reversed,
		      ;; consider the shift-lock key.
		      (AND (BIT-TEST 10 KBD-SHIFTS)	;Caps lock
			   (IF (AND SHIFT-LOCK-XORS (BIT-TEST 1 KBD-SHIFTS))
			       (AND ( NCH #/A) ( NCH #/Z) (SETQ NCH (+ NCH 40)))
			     (AND ( NCH #/a) ( NCH #/z) (SETQ NCH (- NCH 40))))))
		    (%LOGDPB NCH0 %%KBD-CONTROL-META NCH)))))))

(DEFUN KBD-MAKE-NEW-TABLE ()
  (LET ((TBL (MAKE-ARRAY '(5 200) ':AREA  PERMANENT-STORAGE-AREA ':TYPE 'ART-16B)))
    (DO ((J 0 (1+ J))
	 (L '( 
	()					 ;0 not used
	#/ROMAN-II				 ;1 Roman II
	#/ROMAN-IV				 ;2 Roman IV
	100011					 ;3 Mode lock
	()					 ;4 not used
	100006					 ;5 Left super
	()					 ;6 not used
	()					 ;7 not used
	()					 ;10 not used
	(#/4 #/$ #/$)				 ;11 Four
	(#/r #/R #/)				 ;12 R
	(#/f #/F)				 ;13 F
	(#/v #/V)				 ;14 V
	100008					 ;15 Alt Lock
	()					 ;16 not used
	#/HAND-RIGHT				 ;17 Hand Right
	100004					 ;20 Left control
	(#/: 14 14)				 ;21 plus-minus
	#/TAB					 ;22 tab
	#/RUBOUT				 ;23 rubout
	100000					 ;24 Left Shift
	100040					 ;25 Right Shift
	100044					 ;26 Right control
	()					 ;27 not used
	#/HOLD-OUTPUT				 ;30 hold output
	(#/8 #/* #/*)				 ;31 Eight
	(#/i #/I #/)				 ;32 I
	(#/k #/K #/)				 ;33 K
	(#/, #/< #/<)				 ;34 comma
	100041					 ;35 Right Greek
	#/LINE					 ;36 Line
	(#/\ #/| #/|)				 ;37 Backslash
	#/ESC					 ;40 terminal
	()					 ;41 not used
	#/NETWORK				 ;42 network
	()					 ;43 not used
	100001					 ;44 Left Greek
	100005					 ;45 Left Meta
	#/STATUS				 ;46 status
	#/RESUME				 ;47 resume
	#/FORM					 ;50 clear screen
	(#/6 #/^ #/^)				 ;51 Six
	(#/y #/Y #/)				 ;52 Y
	(#/h #/H #/)				 ;53 H
	(#/n #/N #/)				 ;54 N
	()					 ;55 not used
	()					 ;56 not used
	()					 ;57 not used
	()					 ;60 not used
	(#/2 #/@ #/@)				 ;61 Two
	(#/w #/W #/)				 ;62 W
	(#/s #/S)				 ;63 S
	(#/x #/X)				 ;64 X
	100046					 ;65 Right Super
	()					 ;66 not used
	#/ABORT					 ;67 Abort
	()					 ;70 not used
	(#/9 #/( #/( )				 ;71 Nine
	(#/o #/O #/)				 ;72 O
	(#/l #/L #/ 10)			 ;73 L/lambda
	(#/. #/> #/>)				 ;74 period
	()					 ;75 not used
	()					 ;76 not used
	(#/` #/~ #/~ #/)			 ;77 back quote
	#/BACK-NEXT				 ;100 macro
	#/ROMAN-I				 ;101 Roman I
	#/ROMAN-III				 ;102 Roman III
	()					 ;103 not used
	100002					 ;104 Left Top
	()					 ;105 not used
	#/HAND-UP				 ;106 Up Thumb
	#/CALL					 ;107 Call
	#/CLEAR					 ;110 Clear Input
	(#/5 #/% #/%)				 ;111 Five
	(#/t #/T #/)				 ;112 T
	(#/g #/G #/ 11)			 ;113 G/gamma
	(#/b #/B #/ #/)			 ;114 B
	()					 ;115 Repeat
	#/HELP					 ;116 Help
	(#/HAND-LEFT #/HAND-LEFT #/HAND-LEFT #/ #/) ;117 Hand Left
	#/QUOTE					 ;120 Quote
	(#/1 #/! #/!)				 ;121 One
	(#/q #/Q #/)				 ;122 Q
	(#/a #/A 140000 #/)			 ;123 A
	(#/z #/Z)				 ;124 Z
	100003					 ;125 Caps Lock
	(#/= #/+ #/+)				 ;126 Equals
	()					 ;127 not used
	()					 ;130 not used
	(#/- #/_ #/_)				 ;131 Minus
	(#/( #/[ #/[)				 ;132 Open parenthesis
	(#/' #/" #/" 0)				 ;133 Apostrophe/center-dot
	#/SP					 ;134 Space
	()					 ;135 not used
	#/CR					 ;136 Return
	(#/) #/] #/])				 ;137 Close parenthesis
	()					 ;140 not used
	#/SYSTEM				 ;141 system
	()					 ;142 not used
	#/					 ;143 Alt Mode
	()					 ;144 not used
	100007					 ;145 Left Hyper
	(#/} 140000 140000)			 ;146 }
	()					 ;147 not used
	()					 ;150 not used
	(#/7 #/& #/&)				 ;151 Seven
	(#/u #/U #/)				 ;152 U
	(#/j #/J #/)				 ;153 J
	(#/m #/M #/)				 ;154 M
	100042					 ;155 Right Top
	#/END					 ;156 End
	#/DELETE				 ;157 Delete
	#/OVERSTRIKE					 ;160 Overstrike
	(#/3 #/# #/#)				 ;161 Three
	(#/e #/E #/ #/)			 ;162 E
	(#/d #/D 140000 12)			 ;163 D/delta
	(#/c #/C #/)				 ;164 C
	100045					 ;165 Right Meta
	(#/{ 140000 140000)			 ;166 {
	#/BREAK					 ;167 Break
	#/STOP-OUTPUT				 ;170 Stop Output
	(#/0 #/) #/))				 ;171 Zero
	(#/p #/P #/ #/)			 ;172 P
	(#/; #/: #/:)				 ;173 Semicolon
	(#// #/? #/? 177)			 ;174 Question/Integral
	100047					 ;175 Right Hyper
	(#/HAND-DOWN #/HAND-DOWN #/HAND-DOWN #/ #/)	;176 Down Thumb
	()					 ;177 Not used
	      ) (CDR L)))
	((= J 200) TBL)
      (DO ((I 0 (1+ I))
	   (K (CAR L)))
	  ((= I 5))
	(setf (aref tbl i j) (COND ((ATOM K) (OR K 140000))
				   ((NULL (CAR K)) 140000)
				   (T (CAR K))))
	(AND (CONSP K) (SETQ K (CDR K)))))))

(DEFVAR KBD-NEW-TABLE (KBD-MAKE-NEW-TABLE))



(defvar saved-first-char 0)   ;;; put first char of pair here while waiting for second

;;; do the right thing if the "software character" read out of kbd-new-table had
;;; bit 15 set.  If bit 14 is set then the key is undefined.  Otherwise we should update 
;;; kbd-left-shifts and kbd-right-shifts.
(defun kbd-bit-15-on (soft-char down-p)
  (if (bit-test 1_14. soft-char);an undefined key
      (and down-p (kbd-convert-beep))
    ;;; not illegal, must be shift code for kbd-shifts
    
    (LET ((BOOLE (IF DOWN-P 7 2))
	  (BIT (LSH 1 (LOGAND soft-char 37))))
      (IF (BIT-TEST 40 soft-char)
	  (SETQ KBD-RIGHT-SHIFTS
		(BOOLE BOOLE BIT KBD-RIGHT-SHIFTS))
	(SETQ KBD-LEFT-SHIFTS
	      (BOOLE BOOLE BIT KBD-LEFT-SHIFTS)))))
  nil)

(defun kbd-convert-newer (char &optional (ctl-chars-uppercase t))
  (setq char (logand 377 char));strip of source bits
  (cond ((bit-test 1_7 char);is it a second-byte?
	 (cond ((bit-test 1_6 char);up or down code?
		(prog1
		 (multiple-value-bind (soft-char unshifted-soft-char)
		     (new-lookup saved-first-char)
		   (cond ((bit-test 1_15. soft-char)
			  (kbd-bit-15-on soft-char t)
			  nil)
			 (t      ;normal character
			  ;; set bitmap bit
			  (setf (aref kbd-key-state-array unshifted-soft-char) 1)
			  ;; A real key depression.  Check for caps-lock.
			  (let ((kbd-shifts (logior kbd-left-shifts kbd-right-shifts)))
			    ;; Hyper, Super, Meta, Control bits
			    (SETQ unshifted-soft-char (LDB 0404 KBD-SHIFTS))
			    (IF (AND CTL-CHARS-UPPERCASE
				     (NOT (ZEROP unshifted-soft-char)))
				(IF (<= #/a SOFT-CHAR #/z)
				    (DECF SOFT-CHAR 40)      ;Control characters always uppercase,
				  (IF (<= #/A SOFT-CHAR #/Z)   ;unless  Shift is typed
				      (INCF SOFT-CHAR 40)))
				;; Except for control chars for which Shift is reversed,
				;; consider the shift-lock key.
				(AND (BIT-TEST 10 KBD-SHIFTS)  ;Caps lock
				     (IF (AND SHIFT-LOCK-XORS (BIT-TEST 1 KBD-SHIFTS))
					 (AND (>= SOFT-CHAR #/A)
					      (<= SOFT-CHAR #/Z)
					      (SETQ SOFT-CHAR (+ SOFT-CHAR 40)))
				       (AND (>= SOFT-CHAR #/a)
					    (<= SOFT-CHAR #/z)
					    (SETQ SOFT-CHAR (- SOFT-CHAR 40))))))
			    (%LOGDPB unshifted-soft-char %%KBD-CONTROL-META SOFT-CHAR)))))
		 (insure-down-bucky-bit-consistency char)))   ;key-down
	       (t                    ;0: key up
		(multiple-value-bind (soft-char unshifted-soft-char)
		   (new-lookup saved-first-char)
		  (cond ((bit-test 1_15. soft-char)
			 (kbd-bit-15-on soft-char nil)
			 nil)
			(t (setf (aref kbd-key-state-array unshifted-soft-char) 0)))
		  (insure-up-bucky-bit-consistency char)
		  nil))))
	(t (setq saved-first-char (ldb 0007 char));its a first-byte
	   nil)))

;;; get the software char corresponding to hardware char and bucky bits
(defun new-lookup (char)
  (let ((kbd-shifts (logior kbd-left-shifts kbd-right-shifts)))
    (values (AREF KBD-NEW-TABLE
		  (COND ((BIT-TEST 2 KBD-SHIFTS)     ;Greek
			 (+ (LOGAND 1 KBD-SHIFTS) 3))
			((BIT-TEST 4 KBD-SHIFTS) 2)  ;Top
			((BIT-TEST 1 KBD-SHIFTS) 1)  ;Shift
			(T 0))
		  char)
	    (aref kbd-new-table 0 char))))

;;; The magical constants appearing below are derived from what the "newer" keyboard
;;; sends and how the shift keys are encoded in kbd-left-shifts and kbd-right-shifts.
;;; See the code for tv:key-state.  The byte specifiers for ldb are those corresponding
;;; to the bit of the keyboard's "second character" corresponding to the bucky key.
;;; The byte specifiers for dpb correspond to the bits in kbd-right-shifts and
;;; kbd-left-shifts for that key.  Mask1 has ones in the positions associated with those
;;; bucky keys whose states are send with this char.


(defun insure-down-bucky-bit-consistency (char)
  (let* ((mask 
	  (dpb (ldb 0001 char) 0101			;greek
	       (dpb (ldb 0101 char) 0701		;hyper
		    (dpb (ldb 0201 char) 0601		;super
			 (dpb (ldb 0301 char) 0501	;meta
			      (dpb (ldb 0401 char) 0401	;control
				   (dpb (ldb 0501 char) 0001 0)))))))	;shift
	 (mask1 363)
	 (wrong-bits (logxor mask
			     (logand mask1
				     (logior kbd-left-shifts
					     kbd-right-shifts)))))
    ;;; change the bits that disagree with the new information
    (setq kbd-left-shifts (logior kbd-left-shifts (logand wrong-bits mask))
	  kbd-right-shifts (logior kbd-right-shifts (logand wrong-bits mask)))
    (setq kbd-left-shifts (logand kbd-left-shifts
				  (lognot (logand wrong-bits (lognot mask))))
	  kbd-right-shifts (logand kbd-right-shifts
				   (lognot (logand wrong-bits (lognot mask)))))))


(defun insure-up-bucky-bit-consistency (char)
  (let* ((mask
	  (dpb (ldb 0001 char) 0201			;top
	       (dpb (ldb 0101 char) 1201		;repeat
		    (dpb (ldb 0201 char) 0301		;caps-lock
			 (dpb (ldb 0301 char) 1001	;alt-lock
			      (dpb (ldb 0401 char) 1101 0))))))	;mode-lock
	 (mask1 3414)
	 (wrong-bits (logxor mask
			     (logand mask1
				     (logior kbd-left-shifts
					     kbd-right-shifts)))))
    ;;; change the bits that disagree with the new information
    (setq kbd-left-shifts (logior kbd-left-shifts (logand wrong-bits mask))
	  kbd-right-shifts (logior kbd-right-shifts (logand wrong-bits mask)))
    (setq kbd-left-shifts (logand kbd-left-shifts
				  (lognot (logand wrong-bits (lognot mask))))
	  kbd-right-shifts (logand kbd-right-shifts
				   (lognot (logand wrong-bits (lognot mask)))))
    ))


(defun kbd-convert-beep ()
  (%beep 1350 400000))


;;; Hardware primitives
;;; Support for "Simple TV" (32-bit TV system)
;;;Some special variables used by the hardware routines
(DECLARE (SPECIAL CPT-SYNC2 COLOR-SYNC CPT-SYNC-60HZ))

;;; Read and write the sync program
(DEFUN READ-SYNC (ADR &OPTIONAL (TV-ADR TV:(SCREEN-CONTROL-ADDRESS DEFAULT-SCREEN)))
  (%XBUS-WRITE (+ TV-ADR 2) ADR)		;Set pointer
  (LOGAND 377 (%XBUS-READ (+ TV-ADR 1))))

(DEFUN WRITE-SYNC (ADR DATA &OPTIONAL (TV-ADR TV:(SCREEN-CONTROL-ADDRESS DEFAULT-SCREEN)))
  (%XBUS-WRITE (+ TV-ADR 2) ADR)		;Set pointer
  (%XBUS-WRITE (+ TV-ADR 1) DATA))

;;; Start and stop the sync program
(DEFUN START-SYNC (CLOCK BOW VSP
		   &OPTIONAL (TV-ADR TV:(SCREEN-CONTROL-ADDRESS DEFAULT-SCREEN)))
  (%XBUS-WRITE TV-ADR (+ (LSH BOW 2) CLOCK))
  (%XBUS-WRITE (+ TV-ADR 3) (+ 200 VSP)))

(DEFUN STOP-SYNC (&OPTIONAL (TV-ADR TV:(SCREEN-CONTROL-ADDRESS DEFAULT-SCREEN)))
  (%XBUS-WRITE (+ TV-ADR 3) 200))		;Disable output of sync

;;; Write into the sync program from a list with repeat-counts
;;; Sub-lists are repeated <car> times.
(DEFUN FILL-SYNC (L &OPTIONAL (ADR 0) (TV-ADR TV:(SCREEN-CONTROL-ADDRESS DEFAULT-SCREEN))
		    &AUX X)
  (DO ((L L (CDR L))) ((NULL L) ADR)
    (SETQ X (CAR L))
    (COND ((ATOM X) (WRITE-SYNC ADR X TV-ADR) (SETQ ADR (1+ ADR)))
	  (T (DO N (CAR X) (1- N) (ZEROP N)
		 (SETQ ADR (FILL-SYNC (CDR X) ADR TV-ADR)))))))

(DEFUN CHECK-SYNC (L &OPTIONAL (ADR 0)  (TV-ADR TV:(SCREEN-CONTROL-ADDRESS DEFAULT-SCREEN))
		   &AUX X)
  (DO ((L L (CDR L))) ((NULL L) ADR)
    (SETQ X (CAR L))
    (COND ((ATOM X)
	   (CHECK-SYNC-WD ADR X TV-ADR)
	   (SETQ ADR (1+ ADR)))
	  (T (DO N (CAR X) (1- N) (ZEROP N)
	       (SETQ ADR (CHECK-SYNC (CDR X) ADR TV-ADR)))))))

(DEFUN CHECK-SYNC-WD (ADR DATA TV-ADR &AUX MACH)
  (COND ((NOT (= DATA (SETQ MACH (READ-SYNC ADR TV-ADR))))
	 (FORMAT T "~%ADR:~S MACH: ~S should be ~S" ADR MACH DATA))))


;Initialize the TV.  Name of this function is obsolete.
;If FORCE-P is T, then SYNC-PROG is always loaded.
;Otherwise, it is a default to be loaded only if there is no prom.
(DEFUN SETUP-CPT (&OPTIONAL (SYNC-PROG CPT-SYNC2)
			    (TV-ADR NIL)
			    (FORCE-P NIL))
  (SELECT PROCESSOR-TYPE-CODE
    (CADR-TYPE-CODE
     FORCE-P
     (IF (NULL TV-ADR) (SETQ TV-ADR TV:(SCREEN-CONTROL-ADDRESS DEFAULT-SCREEN)))
     ;; Always turn on vertical sync interrupts if this is the first TV controller.
     ;; The microcode relies on these as a periodic clock for various purposes.
     ;; If not the first controller, leave the interrupt enable the way it is.
     (WITHOUT-INTERRUPTS
      (LET ((INTERRUPT-ENABLE (IF (= TV-ADR 377760) 10	;This is the number UCADR knows
				  (LOGAND (%XBUS-READ TV-ADR) 10)))
	    (STATUS (%XBUS-READ TV-ADR)))
	STATUS
	(COND (NIL
	       ;never using the prom, so as to assure software and hardware agree as to
	       ; what the screen geometry is.
	       (COMMENT
		(AND (NOT FORCE-P)			;Unless forced, try to use the PROM
		     (OR (ZEROP (LOGAND STATUS 200))	;Good, PROM already on
			 (PROGN (PROM-SETUP TV-ADR)	;Try turning it on
				(ZEROP (LOGAND (%XBUS-READ TV-ADR) 200)))))  ;On now?
		;; The hardware at least claims the PROM is turned on.  Actually
		;; checking for working sync does not work for some reason, so just
		;; assume that any board which can have a PROM does have one, and
		;; always use the PROM if it is there, since it is more likely to
		;; be right than the default sync program.
		;; Now turn on black-on-white mode, and interrupt enable if desired.
		(%XBUS-WRITE TV-ADR (+ 4 INTERRUPT-ENABLE))))
	      (T ;; Must be an ancient TV board at MIT, or else forced
	       ;; Use default (or forced) sync program
	       (STOP-SYNC TV-ADR)
	       (FILL-SYNC SYNC-PROG 0 TV-ADR)
	       (START-SYNC INTERRUPT-ENABLE 1 0 TV-ADR))))))  ;Clock 0, BOW 1, VSP 0
    (LAMBDA-TYPE-CODE
     NIL)))

(DEFUN PROM-SETUP (&OPTIONAL (TV-ADR TV:(SCREEN-CONTROL-ADDRESS DEFAULT-SCREEN)))
  (%XBUS-WRITE (+ TV-ADR 3) 0))


;sync program bits
;1  HSYNC
;2  VSYNC
;4  COMPOSITE - (not used really, encode on HSYNC)
;10  BLANKING
;     0  PROC CYC
;     20  REFRESH
;     40  INC TVMA
;     60  STEP TVMA
;     0    --
;     100  CLR TVMA
;     200  EOL
;     300  EOP
;Assume 60MHZ bit clock, therefore 15Mhz (66.7 ns) TTL clock, 533ns SYNC clk
; 30. sync clks per line, 10. for horz sync, 
;41.6 lines for 666 usec vertical
;1037 lines per 16.66 ms frame


; 640. X 896.
;(SETQ CPT-SYNC '(
;   1.  (2 33) (8 13) (18. 12) 212 112
;   45.  (2 33) (8 13) (18. 12) 212 12
;   8.  (2 33)  (6 13) 13 12 (18. 2) 202 2
;   255. (2 31) (6 11) 11 50 (9. 0 40) 200 0
;   255. (2 31) (6 11) 11 50 (9. 0 40) 200 0
;   255. (2 31) (6 11) 11 50 (9. 0 40) 200 0
;   131. (2 31) (6 11) 11 50 (9. 0 40) 200 0
;   8. (2 31) (6 11) 11 10 (8. 0 0) 0 0 300 0
;))

;704. x 896.
;(SETQ CPT-SYNC1 '(
;   1.  (1 33) (5 13) 12 12 (10. 12 12) 212 113			;VERT SYNC, CLEAR TVMA
;   53.  (1 33) (5 13) 12 12 (10. 12 12) 212 13			;VERT RETRACE
;   8.  (1 31)  (5 11) 11 10 (10. 0 0) 200 21		;8 LINES OF MARGIN
;   255. (1 31) (5 11) 11 50 (10. 0 40) 200 21
;   255. (1 31) (5 11) 11 50 (10. 0 40) 200 21
;   255. (1 31) (5 11) 11 50 (10. 0 40) 200 21
;   131. (1 31) (5 11) 11 50 (10. 0 40) 200 21
;   7. (1 31) (5 11) 11 10 (10. 0 0) 200 21
;   1. (1 31) (5 11) 11 10 (10. 0 0) 300 23
;))

;Sync for 64 Mhz crystal,  768. x 963.  (was 896 for CPT)
; This is the default thing.  The vertical repetition rate is 60Hz, 
;and the extra screen space is provided to the user 
;(as compared to the original CPT sync load).

(DEFCONST CPT-SYNC2 '(
   1.  (1 33) (5 13) 12 12 (11. 12 12) 212 113			;VERT SYNC, CLEAR TVMA
   53.  (1 33) (5 13) 12 12 (11. 12 12) 212 13			;VERT RETRACE
   8.  (1 31)  (5 11) 11 10 (11. 0 0) 200 21		;8 LINES OF MARGIN
   255. (1 31) (5 11) 11 50 (11. 0 40) 200 21
   255. (1 31) (5 11) 11 50 (11. 0 40) 200 21
   255. (1 31) (5 11) 11 50 (11. 0 40) 200 21
   198. (1 31) (5 11) 11 50 (11. 0 40) 200 21
   7. (1 31) (5 11) 11 10 (11. 0 0) 200 21
   1. (1 31) (5 11) 11 10 (11. 0 0) 300 23
))

;;; This is the CPT-SYNC2 program (locations are in octal, repeats in decimal)
;Loc	Rpt	Hsync	Vsync	Comp	Blank	Other1		Other2
;0	1
;1		X	X		X	Refresh
;2-6		X	X		X
;7-36			X		X
;37			X		X			Eol
;40		X	X		X			Clr MA
;41	53.
;42		X	X		X	Refresh
;43-47		X	X		X
;50-77			X		X
;100			X		X			Eol
;101		X	X		X			Clr MA
;102	8.
;103		X			X	Refresh
;104

;This is used for making an instance in the cold-load environment,
;so that we can display on the TV in the cold-load stream.
;The instance variable slots get initialized to NIL.  Note that
;the method-alist gets used as the dtp-select-method, so it must have
;the unknown-message handler in cdr of its last.
(DEFUN FAKE-UP-INSTANCE (TYPENAME INSTANCE-VARIABLES METHOD-ALIST INIT-PLIST-GENERATOR
			 &AUX INIT-OPTIONS SIZE BINDINGS INSTANCE DESCRIPTOR)
  (SETQ INIT-OPTIONS (FUNCALL INIT-PLIST-GENERATOR))
  ;; Note that the length of this array must agree with INSTANCE-DESCRIPTOR-OFFSETS in QCOM
  (SETQ DESCRIPTOR (MAKE-ARRAY 10 ':AREA PERMANENT-STORAGE-AREA))
  (setf (aref DESCRIPTOR (1- %INSTANCE-DESCRIPTOR-SIZE))
	(SETQ SIZE (1+ (LENGTH INSTANCE-VARIABLES))))
  (SETF (AREF DESCRIPTOR (1- %INSTANCE-DESCRIPTOR-ALL-INSTANCE-VARIABLES))
	INSTANCE-VARIABLES)
  (SETQ BINDINGS (MAKE-LIST (LENGTH INSTANCE-VARIABLES) :AREA PERMANENT-STORAGE-AREA))
  (DO ((B BINDINGS (CDR B))
       (L INSTANCE-VARIABLES (CDR L)))
      ((NULL L))
    (RPLACA B (VALUE-CELL-LOCATION (CAR L))))
  (SETF (AREF DESCRIPTOR (1- %INSTANCE-DESCRIPTOR-BINDINGS)) BINDINGS)
  (SETF (AREF DESCRIPTOR (1- %INSTANCE-DESCRIPTOR-FUNCTION))
	(%MAKE-POINTER DTP-SELECT-METHOD METHOD-ALIST))
  (SETF (AREF DESCRIPTOR (1- %INSTANCE-DESCRIPTOR-TYPENAME)) TYPENAME)
  (SETQ INSTANCE (%ALLOCATE-AND-INITIALIZE DTP-INSTANCE DTP-INSTANCE-HEADER
			   DESCRIPTOR NIL PERMANENT-STORAGE-AREA SIZE))
  (SEND INSTANCE ':INIT (LOCF INIT-OPTIONS))
  INSTANCE)

(DEFUN COLD-LOAD-STREAM-INIT-PLIST-GENERATOR NIL
  `(:WIDTH ,(SELECT PROCESSOR-TYPE-CODE
	      (CADR-TYPE-CODE 1400)
	      (LAMBDA-TYPE-CODE 1440))
    :HEIGHT ,(SELECT PROCESSOR-TYPE-CODE
	       (CADR-TYPE-CODE 1600)
	       (LAMBDA-TYPE-CODE 2000))
    :BUFFER ,IO-SPACE-VIRTUAL-ADDRESS
    :CONTROL-ADDRESS 377760))

(MAKE-INSTANCE-IMMEDIATE COLD-LOAD-STREAM COLD-LOAD-STREAM-INIT-PLIST-GENERATOR)


;Avoid lossage when processes are in use but window system is not loaded yet.
(OR (FBOUNDP 'TV:BACKGROUND-STREAM)
    (FSET 'TV:BACKGROUND-STREAM COLD-LOAD-STREAM))

;:NORMAL to not do when the ADD-INITIALIZATION is executed, only when it is
;time to do the system-initializations
; SETUP-CPT is now called directly from LISP-REINITIALIZE.  Problem was, on a cold boot,
;references to the video buffer could happen before the sync program was set up.
;This caused main memory parity errors even though the TV sends back ignore parity!
;One path that caused trouble was PROCESS-INITIALIZE, (PROCESS-CLASS :RESET),
;TV:WHO-LINE-PROCESS-CHANGE, etc.
;(ADD-INITIALIZATION "CPT-SYNC" '(SETUP-CPT CPT-SYNC2) '(:SYSTEM :NORMAL))


