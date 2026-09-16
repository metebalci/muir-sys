;;; -*- Mode:LISP; Package:SI; Cold-Load:T; Base:8; Readtable:T -*-

;	** (c) Copyright 1980 Massachusetts Institute of Technology **

;;; A BONUS DRIVEN READER!

(DEFVAR *READTABLE* :UNBOUND
  "Syntax table which controls operation of READ (and also PRINT, in limited ways).")
(DEFVAR READTABLE :UNBOUND
  "Syntax table which controls operation of READ (and also PRINT, in limited ways).")
(FORWARD-VALUE-CELL 'READTABLE '*READTABLE*)

(DEFVAR *ALL-READTABLES* NIL
  "A list of all the named readtables in the world")

(DEFVAR *READ-BASE* 10.
  "Default radix for reading rational numbers.")
(DEFVAR IBASE :UNBOUND
  "Default radix for reading rational numbers.")
(FORWARD-VALUE-CELL 'IBASE '*READ-BASE*)

(DEFVAR INITIAL-READTABLE :UNBOUND
  "A readtable defining the standard Zetalisp syntax and symbols.
This is a copy of the readtable that was current when the system was built.
It does not contain any changes you have made to SI:STANDARD-READTABLE.")

(DEFVAR COMMON-LISP-READTABLE :UNBOUND
  "A readtable for Common Lisp syntax.")

(DEFVAR INITIAL-COMMON-LISP-READTABLE :UNBOUND
  "A readtable defining the standard Common Lisp syntax and symbols.
This is a copy of the readtable that defined when the system was built.
It does not contain any changes you have made to SI:COMMON-LISP-READTABLE.")

(DEFVAR STANDARD-READTABLE :UNBOUND
  "A readtable defining the standard traditional Zetalisp syntax.")

(DEFVAR READ-PRESERVE-DELIMITERS NIL
  "If NIL, syntatically useless characters that terminate symbols and numbers are discarded.
If T, they are untyi'ed so that they can be seen by the caller of READ.
This variable should always be globally NIL so that
interactive READ-EVAL-PRINT loops work right, but certain reader macros
or other specialized applications may want to bind it to T.")

(DEFVAR *READ-SUPPRESS* NIL
  "T means do not actually intern symbols that are read.
Used by read-time conditionals to skip what is not wanted.")
(DEFVAR READ-DONT-INTERN :UNBOUND
  "T means do not actually intern symbols that are read.
Used by read-time conditionals to skip what is not wanted.")
(FORWARD-VALUE-CELL 'READ-DONT-INTERN '*READ-SUPPRESS*)

(DEFVAR READ-DISCARD-FONT-CHANGES NIL
  "T means input stream contains 's that signify font changes.
READ ignores the font information.")

(DEFVAR READ-CHECK-INDENTATION NIL
  "If T, do not allow an internal list to start in column 0.
It will get a SYS:MISSING-CLOSEPAREN error.  If you proceed
with :NO-ACTION, closeparens will be invented and then the
openparen will be re-read.")

(DEFVAR INSIDE-COLUMN-0-LIST NIL
  "T while we are reading the insides of a list that starts in column 0.")

(ADD-INITIALIZATION 'READ-CHECK-INDENTATION
		    '(SETQ READ-CHECK-INDENTATION NIL INSIDE-COLUMN-0-LIST NIL
;			   *DEFAULT-COMMON-LISP* NIL *READER-SYMBOL-SUBSTITUTIONS* NIL
			   *READ-SUPPRESS* NIL READ-DISCARD-FONT-CHANGES NIL
			   READ-PRESERVE-DELIMITERS NIL 
			   READ-INSIDE-MULTIPLE-ESCAPE NIL
			   READ-INTERN-FUNCTION 'INTERN)
		    '(:WARM))

(DEFVAR MISSING-CLOSEPAREN-REPORTED NIL
  "T after an invalid open paren in column 0 has been reported (as missing closeparens)
 until that open paren is successfully digested.
Used to cause the problem to be reported only once.")

(DEFVAR READ-INSIDE-MULTIPLE-ESCAPE NIL
  "T if inside vertical bars while reading a token.")

(DEFVAR READ-INTERN-FUNCTION 'INTERN
  "Function READ uses to get a symbol given a pname.")

(DEFCONST READ-COLON-ALLOW-INTERNALS T
  "T means that a colon prefix will find an internal symbol but print a warning.
NIL means it will get an error.")

;;; One peculiar feature of this reader is the ability to construct a table of correspondences
;;; between the s-expression read in and positions in the stream it was read from.
;;; This assumes that the stream responds to a :READ-BP operation with a position.
;;; The feature is activated by reading with XR-CORRESPONDENCE-FLAG set non-nil.
;;; The table is accumulated in XR-CORRESPONDENCE.
;;; The table is a list containing three elements for each list in the s-expression
;;; (not counting cdrs of other lists).
;;; The first of the three is the list that the three elements pertain to.
;;; The second is the position at which that list started.
;;; The third is a list of positions of the elements of that list which are atoms.
;;; NIL appears in that list for elements which are not atoms, since they have
;;; their own sets of three elements.
(DEFVAR XR-CORRESPONDENCE-FLAG)			;T if inside READ-ESTABLISH-CORRESPONDENCE.
(DEFVAR XR-CORRESPONDENCE)			;Each list we read puts its correspondence
						;entry on this list.

(DEFVAR XR-SHARP-ARGUMENT)

(SETQ RDTBL-ARRAY-SIZE #.RDTBL-ARRAY-SIZE)	;Have a reasonable value in the cold load

(DEFVAR READ-AREA NIL
  "Area in which most data read are consed (NIL means use DEFAULT-CONS-AREA).")

;;;; Low levels of READ

;;; These hold the last and next-to-last characters returned by XR-XRTYI.
;;; A circle-cross and its args are treated as a single character.
(DEFVAR XR-XRTYI-LAST-CHAR NIL)
(DEFVAR XR-XRTYI-PREV-CHAR)

(DEFUN XR-XRTYI (STREAM &OPTIONAL IGNORE-WHITESPACE NO-CHARS-SPECIAL NO-MULTIPLE-ESCAPES)
  "Read a character from STREAM, processing escapes (// and /) and multiple-escapes (/|).
IGNORE-WHITESPACE non-NIL means skip over whitespace characters.
NO-CHARS-SPECIAL means do not process escapes specially.
NO-MULTIPLE-ESCAPES means do not process multiple-escape characters specially.

The first value is the translated character.
The second is the index for looking in READ's FSM.
The third is the original, nontranslated character.
The fourth is T if the character was preceded by one or more
 multi-character escape characters that were passed over.

Has a kludge for *READ-BASE* > 10. where letters that should be digits
return the readtable code for EXTENDED-DIGIT rather than their own codes."
  (DECLARE (VALUES TRANSLATED-CHAR FSM-INDEX ACTUAL-CHAR FOUND-MULTI-ESCAPES))
  (PROG (CH BITS CODE CH-CHAR FOUND-MULTI-ESCAPES)
	(SETQ XR-XRTYI-PREV-CHAR XR-XRTYI-LAST-CHAR)
     L
	(DO-FOREVER
	  (SETQ CH (SEND STREAM (IF (EQ RUBOUT-HANDLER STREAM) :ANY-TYI :TYI)))
	  (if (fixnump ch) (setf (char-font ch) 0))
	  (COND ((NULL CH)
		 (RETURN-FROM XR-XRTYI (VALUES CH
					       (RDTBL-EOF-CODE *READTABLE*)
					       CH)))
		((CONSP CH)
		 (AND (EQ (CAR CH) :ACTIVATION)
		      ;; Ignore activations except in top-level context.
		      (NOT IGNORE-WHITESPACE)
		      (NOT NO-CHARS-SPECIAL)
		      (NOT NO-MULTIPLE-ESCAPES)
		      (LET ((CH1 (CAR (RDTBL-WHITESPACE *READTABLE*))))
			(RETURN-FROM XR-XRTYI (VALUES CH1
						      (RDTBL-CODE *READTABLE* CH1)
						      CH)))))
		((AND READ-DISCARD-FONT-CHANGES
		      (EQ CH #/))
		 (IF (EQ #/ (SEND STREAM :TYI))
		     (RETURN)))
		((NOT (> CH RDTBL-ARRAY-SIZE))
		 (RETURN))))
	(SETQ CH-CHAR (CHAR-CODE CH))
	(SETQ BITS (RDTBL-BITS *READTABLE* CH-CHAR))
	(SETQ CODE (RDTBL-CODE *READTABLE* CH-CHAR))
	(COND ((AND (NOT NO-CHARS-SPECIAL)
		    (NOT NO-MULTIPLE-ESCAPES)
		    (= CODE
		       (RDTBL-MULTIPLE-ESCAPE-CODE *READTABLE*)))
	       ;; Vertical bar.
	       (SETQ FOUND-MULTI-ESCAPES T)
	       (SETQ READ-INSIDE-MULTIPLE-ESCAPE
		     (IF READ-INSIDE-MULTIPLE-ESCAPE NIL
		       CH-CHAR))
	       (GO L))
	      ((AND (NOT NO-CHARS-SPECIAL)
		    (= CODE
		       (RDTBL-ESCAPE-CODE *READTABLE*)))
	       ;; Slash
	       (SETQ XR-XRTYI-PREV-CHAR CH)
	       (DO-FOREVER
		 (SETQ CH (SEND STREAM :TYI))
		 (COND ((AND READ-DISCARD-FONT-CHANGES
			     (EQ CH #/))
			(IF (EQ #/ (SEND STREAM :TYI))
			    (RETURN)))
		       (T (RETURN))))
	       (SETQ XR-XRTYI-LAST-CHAR CH)
	       (RETURN (VALUES (OR CH
				   (PROGN
				     (CERROR :NO-ACTION NIL 'SYS:READ-END-OF-FILE
					     "EOF on ~S after a ~S." STREAM
					     (STRING XR-XRTYI-PREV-CHAR))
				     #/SPACE))
			       (RDTBL-SLASH-CODE *READTABLE*)
			       CH)))
	      ((AND (NOT NO-CHARS-SPECIAL)
		    (= CODE
		       (RDTBL-CHARACTER-CODE-ESCAPE-CODE *READTABLE*)))
	       ;; circlecross
	       (SETQ XR-XRTYI-LAST-CHAR (XR-READ-CIRCLECROSS STREAM))
	       (RETURN (VALUES XR-XRTYI-LAST-CHAR
			       (RDTBL-SLASH-CODE *READTABLE*)
			       XR-XRTYI-LAST-CHAR)))
	      (READ-INSIDE-MULTIPLE-ESCAPE
	       ;; Ordinary character but within vertical bars.
	       (SETQ XR-XRTYI-LAST-CHAR CH)
	       (RETURN (VALUES (OR CH
				   (PROGN
				     (CERROR :NO-ACTION NIL 'SYS:READ-END-OF-FILE
					     "EOF on ~S inside a ~C-quoted token." STREAM
					     READ-INSIDE-MULTIPLE-ESCAPE)
				     #/SPACE))
			       (RDTBL-SLASH-CODE *READTABLE*)
			       CH)))
	      (T
	       ;; Ordinary character.
	       (COND ((AND IGNORE-WHITESPACE (NOT FOUND-MULTI-ESCAPES)
			   (BIT-TEST 1 BITS))
		      ;; Here if whitespace char to be ignored.
		      (SETQ XR-XRTYI-PREV-CHAR CH)
		      (GO L)))
	       ;; Here for ordinary, significant input char.
	       (SETQ XR-XRTYI-LAST-CHAR CH)
	       (RETURN (VALUES (RDTBL-TRANS *READTABLE* CH-CHAR)
			       ;; If not doing slashes, caller must not really want the
			       ;;  RDTBL-CODE, so return a value which, if passed to
			       ;;  XR-XRUNTYI, will prevent barfing.
			       (IF NO-CHARS-SPECIAL 0
				 (IF (AND (NUMBERP *READ-BASE*)
					  ( #/A (CHAR-UPCASE CH) (+ *READ-BASE* #/A -11.)))
				     (CDR (GETF (RDTBL-PLIST *READTABLE*) 'EXTENDED-DIGIT))
				   (RDTBL-CODE *READTABLE* CH-CHAR)))
			       CH
			       T))))))

(DEFUN XR-READ-CIRCLECROSS (STREAM &AUX CH1 CH2 CH3)
  (IF (NOT (AND (SETQ CH1 (XR-XRTYI STREAM))
		(SETQ CH2 (XR-XRTYI STREAM))
		(SETQ CH3 (XR-XRTYI STREAM))))
      (PROGN (CERROR :NO-ACTION NIL 'SYS:READ-END-OF-FILE "EOF during a circlecross.")
	     #/SPACE)
    (IF (OR (< CH1 #/0) (> CH1 #/7)
	    (< CH2 #/0) (> CH2 #/7)
	    (< CH3 #/0) (> CH3 #/7))
	;; The lack of an explicit  character here is to get around
	;; a stupid bug in the cold-load generator.
	(PROGN
	  (CERROR :NO-ACTION NIL 'SYS:READ-ERROR-1
		  "The three characters immediately following a circlecross must be octal -- ~C~C~C~C." #/ CH1 CH2 CH3)
	  #/SPACE)
      (+ (* 100 (- CH1 #/0))
	 (+ (* 10 (- CH2 #/0))
	    (- CH3 #/0))))))

;;; XR-XRUNTYI takes a stream to untyi to, a character to untyi (third result of XR-XRTYI
;;; please) and the magic number that character was read in with.
;;; This is where READ-PRESERVE-DELIMITERS is implemented.
(DEFUN XR-XRUNTYI (STREAM CH NUM)
  "XR-XRUNTYI is to XR-XRTYI as the :UNTYI operation is to :TYI.
CH and NUM should be the third and second values returned by XR-XRTYI."
  (WHEN (= NUM (RDTBL-SLASH-CODE *READTABLE*))
    (FERROR 'SYS:READ-ERROR-1
	    "The character /"~C/" was slashified and cannot be UNTYIed." CH))
  (WHEN (AND CH (NOT (CONSP CH))
	     (OR READ-PRESERVE-DELIMITERS (ZEROP (LOGAND 1 (RDTBL-BITS *READTABLE* CH)))))
    (SETQ XR-XRTYI-LAST-CHAR XR-XRTYI-PREV-CHAR)
    (SEND STREAM :UNTYI CH)))

;;;; Middle level of READ - the FSM processor.

(DEFVAR READ-TEMP-STRING NIL
  "String used for accumulating token by XR-READ-THING
and passed to read routines for types of tokens.
NIL means no string available for re-use now.")

(DEFVAR READ-STRING-COUNT 0
  "Counts each time READ makes a new temporary string.")

;; These save the time used by MAKE-ARRAY and also that used by RETURN-ARRAY.
(DEFMACRO RETURN-READ-STRING (STRING)
  `(SETQ READ-TEMP-STRING ,STRING))

(DEFMACRO GET-READ-STRING ()
  '(OR
     ;; WITHOUT-INTERRUPTS seems to take some time.
     (DO (OLD)
	 ((%STORE-CONDITIONAL (LOCF READ-TEMP-STRING) (SETQ OLD READ-TEMP-STRING) NIL)
	  OLD))
;     (WITHOUT-INTERRUPTS
;       (PROG1 READ-TEMP-STRING (SETQ READ-TEMP-STRING NIL)))
     (PROGN (INCF READ-STRING-COUNT)
	    (MAKE-STRING #o100 :FILL-POINTER 0))))

;;; The specific functions called by XR-READ-THING can return anything as a second value
;;; if that thing is the symbol "READER-MACRO" then the first thing is called as a
;;; standard reader macro.
;;; If a read function is going to call READ, it should do a RETURN-READ-STRING
;;; on its second arg if that is actually a string.
;;; Then it should return T as its third arg
;;; to tell XR-READ-THING not to do a RETURN-READ-STRING itself.
;;; (that could cause the same string to be used by two processes at once).
(DEFUN XR-READ-THING (STREAM)
  (PROG (CH NUM A B STRING (INDEX 0) STLEN REAL-CH ALREADY-RETURNED
	 (READTABLE-FSM (RDTBL-FSM *READTABLE*))
	 (FNPROP (RDTBL-READ-FUNCTION-PROPERTY *READTABLE*))
	 (STATE (RDTBL-STARTING-STATE *READTABLE*))
	 READ-INSIDE-MULTIPLE-ESCAPE FOUND-MULTI-ESCAPES)
	(MULTIPLE-VALUE (CH NUM REAL-CH FOUND-MULTI-ESCAPES) (XR-XRTYI STREAM T))
	(SETQ STATE (AREF READTABLE-FSM STATE NUM))
	;; Compensate for bad readtable in system 99.
	;; Detect the case of a whitespace char following a pair of vertical bars.
	(AND (NULL STATE) FOUND-MULTI-ESCAPES
	     (SETQ STATE '(UNTYI-FUNCTION . SYMBOL)))
	(UNLESS (NUMBERP STATE)
	  (LET ((FLAG (CAR STATE))
		(TODO (CDR STATE)))
	    (SELECTQ FLAG
	      (NO-UNTYI-QUOTE
	       (SETQ A TODO)
	       (SETQ B 'SPECIAL-TOKEN))
	      (LAST-CHAR
	       (MULTIPLE-VALUE (A B)
		 (FUNCALL (GET TODO FNPROP)
			  STREAM NIL CH)))
	      (NO-UNTYI-FUNCTION
	       (IF *READ-SUPPRESS*
		   (SETQ A NIL B NIL)
		 (SETQ STRING (GET-READ-STRING))
		 (SETF (FILL-POINTER STRING) 1)
		 (SETF (CHAR STRING 0) CH)
		 (MULTIPLE-VALUE (A B ALREADY-RETURNED)
		   (FUNCALL (GET TODO FNPROP) STREAM STRING))
		 (UNLESS ALREADY-RETURNED
		   (RETURN-READ-STRING STRING))))
	      (UNTYI-QUOTE
	       (FERROR 'SYS:READ-ERROR-1
		       "Reader in infinite loop reading character: /"~C/"."
		       REAL-CH))
	      (UNTYI-FUNCTION
	       (IF (NOT FOUND-MULTI-ESCAPES)
		   (FERROR 'SYS:READ-ERROR-1
			   "Reader in infinite loop reading character: /"~C/"."
			   REAL-CH)
		 (XR-XRUNTYI STREAM REAL-CH NUM)
		 (IF *READ-SUPPRESS*
		     (SETQ A NIL B NIL)
		   (MULTIPLE-VALUE (A B)
		     (FUNCALL (GET TODO FNPROP) STREAM "")))))
	      (OTHERWISE
	       (FERROR 'SYS:READ-ERROR-1
		       "The reader found ~S in the finite state machine."
		       FLAG)))
	    (RETURN A B)))
	(SETQ STRING (GET-READ-STRING))
	(SETQ STLEN (ARRAY-LENGTH STRING))
     L  (SETF (CHAR STRING INDEX) CH)
	(SETQ INDEX (1+ INDEX))
	(MULTIPLE-VALUE (CH NUM REAL-CH) (XR-XRTYI STREAM))
	(SETQ STATE (AREF READTABLE-FSM STATE NUM))
	(COND ((NUMBERP STATE)
	       (WHEN (= INDEX STLEN)
		 (SETQ STLEN (+ 32. STLEN))
		 (ADJUST-ARRAY-SIZE STRING STLEN)
		 (SETQ STRING (FOLLOW-STRUCTURE-FORWARDING STRING)))
	       (GO L)))
	(LET ((FLAG (CAR STATE))
	      (TODO (CDR STATE)))
	  (SELECTQ FLAG
	    (UNTYI-FUNCTION
	     (XR-XRUNTYI STREAM REAL-CH NUM)
	     (SETF (FILL-POINTER STRING) INDEX)
	     (IF *READ-SUPPRESS*
		 (SETQ A NIL B NIL)
	       (MULTIPLE-VALUE (A B ALREADY-RETURNED)
		 (FUNCALL (GET TODO FNPROP) STREAM STRING))))
	    (LAST-CHAR
	     (SETF (FILL-POINTER STRING) INDEX)
	     (MULTIPLE-VALUE (A B ALREADY-RETURNED)
	       (FUNCALL (GET TODO FNPROP)
			STREAM STRING CH)))
	    (NO-UNTYI-FUNCTION
	     (SETF (FILL-POINTER STRING) (1+ INDEX))
	     (SETF (CHAR STRING INDEX) CH)
	     (IF *READ-SUPPRESS*
		 (SETQ A NIL B NIL)
	       (MULTIPLE-VALUE (A B ALREADY-RETURNED)
		 (FUNCALL (GET TODO FNPROP) STREAM STRING))))
	    (UNTYI-QUOTE
	     (XR-XRUNTYI STREAM REAL-CH NUM)
	     (SETQ A TODO)
	     (SETQ B 'SPECIAL-TOKEN))
	    (NO-UNTYI-QUOTE
	     (SETQ A TODO)
	     (SETQ B 'SPECIAL-TOKEN))
	    (OTHERWISE
	     (FERROR 'SYS:READ-ERROR-1
		     "The reader found ~S in the finite state machine."
		     FLAG)))
	  (UNLESS ALREADY-RETURNED
	    (RETURN-READ-STRING STRING))
	  (RETURN A B))))

(DEFVAR XR-LIST-SO-FAR :UNBOUND
  "When a reader macro is called, this contains the list so far at the current level.")

(DEFVAR XR-SPLICE-P :UNBOUND
  "A reader macro can set this to NIL to indicate that it has modified XR-LIST-SO-FAR.")

(DEFVAR XR-MACRO-ALIST-ENTRY-CDR :UNBOUND)

(DEFUN INVOKE-READER-MACRO (MACRO STREAM)
  (LET ((XR-MACRO-ALIST-ENTRY-CDR MACRO))
    (MULTIPLE-VALUE-LIST (FUNCALL (IF (CONSP MACRO) (CAR MACRO) MACRO)
				  STREAM XR-XRTYI-LAST-CHAR))))

(DEFUN XR-DISPATCH-MACRO-DRIVER (STREAM MACRO-CHAR)
  (DO (ARG TEM CHAR)
      (())
    (SETQ CHAR (XR-XRTYI STREAM NIL T))
    (COND ((NULL CHAR)
	   (CERROR :NO-ACTION NIL 'READ-END-OF-FILE
		   "End of file after dispatch macro character ~C." MACRO-CHAR)
	   (RETURN NIL))
	  ((SETQ TEM (CDR (ASSQ CHAR
				'((#/ . 1) (#/ . 2) (#/ . 3)
				  (#/ . 4) (#/ . 8) ))))
	   (SETQ ARG (LOGIOR (OR ARG 0) TEM)))
	  (( #/0 CHAR #/9)
	   (SETQ ARG (+ (* 10. (OR ARG 0)) (- CHAR #/0))))
	  (T
	   (LET ((FN (CADR (ASSQ (CHAR-UPCASE CHAR)
				 (CDDR XR-MACRO-ALIST-ENTRY-CDR)))))
	     (IF (NULL FN)
		 (RETURN (CERROR :NO-ACTION NIL 'READ-ERROR-1
				 "Undefined dispatch macro combination ~C~C."
				 MACRO-CHAR CHAR))
	       (RETURN (FUNCALL FN STREAM CHAR ARG))))))))

;;;; Top levels of READ

;;; This variable helps implement the labeled object reader macros #n# and #n=.
;;; See the Common Lisp manual for how they are supposed to work.
(DEFVAR XR-LABEL-BINDINGS)
				      
(DEFUN READ-PRESERVING-WHITESPACE (&OPTIONAL (STREAM *STANDARD-INPUT*)
				   EOF-ERROR-P EOF-VALUE RECURSIVE-P)
  "Similar to INTERNAL-READ, but never discards the character that terminates an object.
If the object read required the following character to be seen to terminate it,
normally READ will discard that character if it is whitespace.
This function, by contrast, will never discard that character."
  (INTERNAL-READ STREAM EOF-ERROR-P EOF-VALUE RECURSIVE-P T))

(DEFUN READ-FOR-TOP-LEVEL (&REST READ-ARGS)
  "Similar to READ, but ignores stray closeparens and ignores end of file.
Interactive command loops such as the lisp listener use this function."
  (DECLARE (ARGLIST STREAM EOF-OPTION (RUBOUT-HANDLER-OPTIONS '((:ACTIVATION = #/END)))))
  (MULTIPLE-VALUE-BIND (STREAM NIL EOF-VALUE OPTIONS)
      (DECODE-KLUDGEY-MUCKLISP-READ-ARGS READ-ARGS 1)
    (WITH-INPUT-EDITING (STREAM (IF OPTIONS (CAR OPTIONS) '((:ACTIVATION = #/END))))
      (INTERNAL-READ STREAM NIL EOF-VALUE NIL NIL T))))

(DEFUN READ (&REST READ-ARGS)
  "Read an s-expression from a stream and return it.
EOF-OPTION, if supplied is returned if end of file is encountered.
If there is no EOF-OPTION, end of file is an error.
See the documentation for WITH-INPUT-EDITING for the format of RUBOUT-HANDLER-OPTIONS.
READ gets an error if an extraneous closeparen or dot is found.
Command loops should use READ-FOR-TOP-LEVEL instead, to discard them."
  (DECLARE (ARGLIST STREAM EOF-OPTION (RUBOUT-HANDLER-OPTIONS '((:ACTIVATION = #/END)))))
  (MULTIPLE-VALUE-BIND (STREAM EOF-ERROR-P EOF-VALUE OPTIONS)
      (DECODE-KLUDGEY-MUCKLISP-READ-ARGS READ-ARGS 1)
    (WITH-INPUT-EDITING (STREAM (IF OPTIONS (CAR OPTIONS) '((:ACTIVATION = #/END))))
      (INTERNAL-READ STREAM EOF-ERROR-P EOF-VALUE NIL NIL))))

(DEFUN READ-CHECK-INDENTATION (&REST READ-ARGS)
  "Read an s-expression from a stream and return it, requiring proper indentation.
We assume that all open parens in column zero are supposed
to be top-level lists, except that EVAL-WHEN's, etc, may surround them.
/(Symbols such as EVAL-WHEN should have a SI::MAY-SURROUND-DEFUN property).
If an open paren is encountered in column 0 and is not top level, sufficient
closeparens are /"imagined/" so as to close off enough pending lists to make
the data valid.  End of file closes off all pending lists.
In either case, the SYS:MISSING-CLOSEPAREN condition is signaled,
with an argument that is T for end of file, NIL for open paren encountered."
  (DECLARE (ARGLIST STREAM EOF-OPTION (RUBOUT-HANDLER-OPTIONS '((:ACTIVATION = #/END)))))
  (MULTIPLE-VALUE-BIND (STREAM EOF-ERROR-P EOF-VALUE OPTIONS)
      (DECODE-KLUDGEY-MUCKLISP-READ-ARGS READ-ARGS 1)
    (WITH-INPUT-EDITING (STREAM  (IF OPTIONS (CAR OPTIONS) '((:ACTIVATION = #/END))))
      (INTERNAL-READ STREAM EOF-ERROR-P EOF-VALUE NIL NIL NIL T))))

(DEFUN READ-RECURSIVE (&OPTIONAL (STREAM *STANDARD-INPUT*))
  "Readmacros that wish to read an expression should use this funtion instead of READ."
  (INTERNAL-READ STREAM T NIL T))

(DEFUN READ-OR-END (&REST READ-ARGS &AUX CH TEM)
  "Like GLOBAL:READ, except that if the first non-blank character that the user types
is END (the interactive input activation character), we immediately return two values:
NIL and :END.  Otherwise, read and return an s-expression from STREAM.
EOF-OPTION has the same meaning as it does for GLOABL:READ."
  (DECLARE (ARGLIST STREAM EOF-OPTION RUBOUT-HANDLER-OPTIONS))
  (MULTIPLE-VALUE-BIND (STREAM EOF-ERROR-P EOF-VALUE RH-OPTIONS)
      (DECODE-KLUDGEY-MUCKLISP-READ-ARGS READ-ARGS 1)
    (WITH-STACK-LIST* (RH-OPTIONS '(:ACTIVATION = #/END) RH-OPTIONS)
      (IF (ASSQ :ACTIVATION (CDR RH-OPTIONS)) (POP RH-OPTIONS))
      (WITH-INPUT-EDITING (STREAM RH-OPTIONS)
	(SETQ TEM (IF (SEND STREAM :OPERATION-HANDLED-P :ANY-TYI) :ANY-TYI :TYI))
	;; can't use PEEK-CHAR as that wouldn't get blips...
	(DO-FOREVER
	  (SETQ CH (SEND STREAM TEM EOF-ERROR-P))
	  (COND ((EQ (CAR-SAFE CH) :ACTIVATION) (RETURN (VALUES NIL :END)))
		;; should use the same readtable-based check that peek-char uses, but wtf
		((MEMQ CH '(#/SPACE #/TAB #/RETURN)))	;do nothing
		(T (SEND STREAM :UNTYI CH)
		   (RETURN (INTERNAL-READ STREAM EOF-ERROR-P EOF-VALUE NIL NIL T)))))))))

(DEFVAR READ-STREAM :UNBOUND
  "Within READ, the stream being read from.  For creating error objects.")

(DEFF CLI:READ 'INTERNAL-READ)
(DEFUN INTERNAL-READ (&OPTIONAL (STREAM *STANDARD-INPUT*)
		      (EOF-ERRORP T) EOF-VALUE RECURSIVE-P
		      PRESERVE-WHITESPACE DISCARD-CLOSEPARENS CHECK-INDENTATION
		      &AUX W-O)
  "Read an s-expression from STREAM and return it.
End of file within an s-expression is an error.
End of file with no s-expression seen is controlled by EOF-ERRORP.
T means it is an error then too.  NIL means that end of file
with no s-expression returns EOF-VALUE.

RECURSIVE-P non-NIL is used for recursive calls, e.g. from read macro definitions.
Recursive calls must be distinguished to make READ-PRESERVING-WHITESPACE
and #n= /"labels/" work properly.

PRESERVE-WHITESPACE if non-NIL says do not discard the terminating delimiter even
if it is whitespace.  This argument is ignored if RECURSIVE-P is non-NIL,
and the outer, nonrecursive call gets to control the matter.

DISCARD-CLOSEPARENS if non-NIL says if we see a close paren
just keep reading past it, with no error.

CHECK-INDENTATION controls whether indentation is checked within this
s-expression.  If RECURSIVE-P is non-NIL, this argument is ignored
and the outer, nonrecursive call gets to control the matter."
  (COND ((EQ STREAM T) (SETQ STREAM *TERMINAL-IO*))
	((EQ STREAM NIL) (SETQ STREAM *STANDARD-INPUT*)))
  (LET-IF (NOT RECURSIVE-P)
	  ((XR-LABEL-BINDINGS NIL)
	   (READ-PRESERVE-DELIMITERS PRESERVE-WHITESPACE)
	   (READ-CHECK-INDENTATION CHECK-INDENTATION)
	   (XR-XRTYI-LAST-CHAR #/RETURN)
	   (XR-XRTYI-PREV-CHAR NIL)
	   (READ-STREAM STREAM)
	   (MISSING-CLOSEPAREN-REPORTED NIL))
    (SETQ W-O (SEND STREAM :WHICH-OPERATIONS))
    (COND ((MEMQ :READ W-O)
	   (SEND STREAM :READ NIL))
	  ((AND (NOT RECURSIVE-P) (NEQ RUBOUT-HANDLER STREAM) (MEMQ :RUBOUT-HANDLER W-O))
	   ;;We must get inside the rubout handler's top-level CATCH
	   (WITH-INPUT-EDITING (STREAM '((:ACTIVATION = #/END)))
	     (INTERNAL-READ STREAM EOF-ERRORP EOF-VALUE T)))
	  ((PROG (THING TYPE XR-SHARP-ARGUMENT)
	       A (MULTIPLE-VALUE (THING TYPE) (XR-READ-THING STREAM))
		 (COND ((EQ TYPE 'READER-MACRO)
			(LET ((XR-LIST-SO-FAR :TOPLEVEL)
			      (XR-SPLICE-P NIL)
			      VALUES)
			  (SETQ VALUES (INVOKE-READER-MACRO THING STREAM))
			  (IF (OR XR-SPLICE-P
				  ( (LENGTH VALUES) 1))
			      (GO A))
			  (RETURN (CAR VALUES))))
		       ((EQ TYPE 'SPECIAL-TOKEN)
			(COND ((EQ THING 'EOF)
			       (IF EOF-ERRORP
				   (CERROR :NO-ACTION NIL 'SYS:READ-END-OF-FILE
					   "End of file encountered by READ on stream ~S."
					   STREAM)
				 (RETURN EOF-VALUE)))
			      ((AND DISCARD-CLOSEPARENS
				    (EQ THING 'CLOSE))
			       (GO A))
			      (T
			       (CERROR :NO-ACTION NIL 'SYS:READ-ERROR-1
				       "The special token ~S was read in at top level."
				       THING))))
		       (T (RETURN THING))))))))

(DEFUN READ-DELIMITED-LIST (STOP-CHAR &OPTIONAL (STREAM *STANDARD-INPUT*) RECURSIVE-P)
  "Read objects from STREAM until STOP-CHAR is seen; return a list of the objects read.
STOP-CHAR should not be a whitespace character in the current Readtable;
for best results, its syntax should be the standard syntax of closeparen.
RECURSIVE-P should be supplied non-NIL when this is called from a reader macro."
  (LET-IF (NOT RECURSIVE-P)
	  ((XR-LABEL-BINDINGS NIL)
	   (XR-XRTYI-LAST-CHAR #/RETURN)
	   (XR-XRTYI-PREV-CHAR NIL)
	   (READ-CHECK-INDENTATION NIL)
	   (READ-PRESERVE-DELIMITERS NIL))
    (IF (AND (NOT RECURSIVE-P) (NEQ RUBOUT-HANDLER STREAM)
	     (SEND STREAM :OPERATION-HANDLED-P :RUBOUT-HANDLER))
	;;We must get inside the rubout handler's top-level CATCH
	(WITH-INPUT-EDITING (STREAM '((:ACTIVATION = #/END)))
	  (READ-DELIMITED-LIST STOP-CHAR STREAM))
      (PROG (LIST THING TYPE END-OF-LIST BP CORRESPONDENCE-ENTRY
	     (INSIDE-COLUMN-0-LIST INSIDE-COLUMN-0-LIST)
	     (THIS-IS-COLUMN-0-LIST (AND READ-CHECK-INDENTATION
					 (EQ XR-XRTYI-PREV-CHAR #/RETURN))))
	    (AND THIS-IS-COLUMN-0-LIST
		 (NOT *READ-SUPPRESS*)
		 (IF (NOT INSIDE-COLUMN-0-LIST)
		     (SETQ INSIDE-COLUMN-0-LIST T)
		   ;; ( in column 0 when not allowed.
		   ;; Report it (but only report each occurrence once).
		   (OR MISSING-CLOSEPAREN-REPORTED
		       (PROGN (SETQ MISSING-CLOSEPAREN-REPORTED T)
			      (SIGNAL-PROCEED-CASE (() 'SYS:MISSING-CLOSEPAREN
						       "Open paren found in column zero; missing closeparens assumed.")
				(:NO-ACTION))))
		   ;; Unread it and pretend it was a ).
		   (XR-XRUNTYI STREAM XR-XRTYI-LAST-CHAR -1)
		   (RETURN 'CLOSE 'SPECIAL-TOKEN)))
	    (SETQ MISSING-CLOSEPAREN-REPORTED NIL)
	    (SETQ END-OF-LIST (LOCF LIST))
	    (WHEN XR-CORRESPONDENCE-FLAG
	      (SEND STREAM :UNTYI XR-XRTYI-LAST-CHAR)
	      (SETQ CORRESPONDENCE-ENTRY
		    `(NIL ,(SEND STREAM :READ-BP) NIL . ,XR-CORRESPONDENCE))
	      (SETQ XR-CORRESPONDENCE CORRESPONDENCE-ENTRY)
	      (SEND STREAM :TYI))
	 A
	    (AND XR-CORRESPONDENCE-FLAG
		 (PUSH (SEND STREAM :READ-BP) (CADDR CORRESPONDENCE-ENTRY)))
	    ;; Peek ahead to look for the terminator we expect.
	    (MULTIPLE-VALUE-BIND (CHAR NUM ACTUAL-CHAR)
		(XR-XRTYI STREAM T T)
	      (WHEN (= CHAR STOP-CHAR)
		(RETURN LIST))
	      (XR-XRUNTYI STREAM ACTUAL-CHAR NUM))
	    ;; Read the next token, or a macro character.
	    (MULTIPLE-VALUE-SETQ (THING TYPE) (XR-READ-THING STREAM))
	    ;; If this is the first element of a list starting in column 0,
	    ;; and it is EVAL-WHEN or something like that,
	    ;; say it is ok for our sublists to start in column 0.
	    (AND THIS-IS-COLUMN-0-LIST
		 (EQ END-OF-LIST (LOCF LIST))
		 (SYMBOLP THING)
		 ;; It is usually dangerous for READ to look at properties of symbols,
		 ;; but this will only happen for the symbol after a paren in column 0
		 ;; and never in lists read in interactively.
		 (GET THING 'MAY-SURROUND-DEFUN)
		 (SETQ INSIDE-COLUMN-0-LIST NIL))
	    (COND ((EQ TYPE 'READER-MACRO)
		   (WHEN XR-CORRESPONDENCE-FLAG
		     (SEND STREAM :UNTYI XR-XRTYI-LAST-CHAR)
		     (SETQ BP (SEND STREAM :READ-BP))
		     (SEND STREAM :TYI))
		   (LET ((XR-LIST-SO-FAR LIST)
			 (XR-SPLICE-P NIL)
			 VALUES)
		     (SETQ VALUES (INVOKE-READER-MACRO THING STREAM))
		     (COND (XR-SPLICE-P
			    (SETQ LIST XR-LIST-SO-FAR)
			    (AND XR-CORRESPONDENCE-FLAG
				 (SETF (CADDR CORRESPONDENCE-ENTRY)
				       (FIRSTN (LENGTH LIST) (CADDR CORRESPONDENCE-ENTRY))))
			    (SETQ END-OF-LIST (IF (ATOM LIST) (LOCF LIST) (LAST LIST))))
			   (VALUES
			    (SETF (CDR END-OF-LIST)
				  (SETQ VALUES (COPY-LIST VALUES READ-AREA)))
			    (SETQ END-OF-LIST (LAST VALUES))
			    (WHEN XR-CORRESPONDENCE-FLAG
			      (SETQ XR-CORRESPONDENCE
				    `(,(CAR VALUES) ,BP NIL . ,XR-CORRESPONDENCE))))))
		   (GO A))
		  ((EQ TYPE 'SPECIAL-TOKEN)
		   (COND ((EQ THING 'EOF)
			  (OR (AND READ-CHECK-INDENTATION MISSING-CLOSEPAREN-REPORTED)
			      (SIGNAL-PROCEED-CASE (() 'SYS:READ-LIST-END-OF-FILE
						       "End of file on ~S in the middle of the list ~:S."
						       STREAM LIST)
				(:NO-ACTION
				 (IF READ-CHECK-INDENTATION
				     (SETQ MISSING-CLOSEPAREN-REPORTED T)))))
			  (RETURN (VALUES LIST 'LIST)))
			 (T (CERROR :NO-ACTION NIL 'SYS:READ-ERROR-1
				    "Incorrect terminator, ~C not ~C."
				    XR-XRTYI-LAST-CHAR
				    STOP-CHAR))))
		  (T
		   (SETF (CDR END-OF-LIST)
			 (SETQ END-OF-LIST (NCONS-IN-AREA THING READ-AREA)))
		   (GO A)))))))


;;; This ends the reader proper. The things from here on are called only if they appear in
;;; the readtable itself.  However, XR-READ-LIST is somewhat special in that it handles
;;; splicing macros. 

;;; Symbols which can head lists which go around defuns
;;; are given the MAY-SURROUND-DEFUN property.
(DEFPROP EVAL-WHEN T MAY-SURROUND-DEFUN)
(DEFPROP PROGN T MAY-SURROUND-DEFUN)
(DEFPROP LOCAL-DECLARE T MAY-SURROUND-DEFUN)
(DEFPROP DECLARE-FLAVOR-INSTANCE-VARIABLES T MAY-SURROUND-DEFUN)
(DEFPROP COMPILER-LET T MAY-SURROUND-DEFUN)
(DEFPROP IF-FOR-MACLISP T MAY-SURROUND-DEFUN)
(DEFPROP IF-FOR-LISPM T MAY-SURROUND-DEFUN)
(DEFPROP IF-IN-MACLISP T MAY-SURROUND-DEFUN)
(DEFPROP IF-IN-LISPM T MAY-SURROUND-DEFUN)
(DEFPROP IF-FOR-MACLISP-ELSE-LISPM T MAY-SURROUND-DEFUN)
(DEFPROP IF-FOR-CADR-ELSE-LAMBDA T MAY-SURROUND-DEFUN)
(DEFPROP IF-FOR-LAMBDA-ELSE-CADR T MAY-SURROUND-DEFUN)
(DEFPROP IF-IN-CADR T MAY-SURROUND-DEFUN)
(DEFPROP IF-IN-LAMBDA T MAY-SURROUND-DEFUN)
(DEFPROP COMMENT T MAY-SURROUND-DEFUN)
(DEFPROP QUOTE T MAY-SURROUND-DEFUN)
(DEFPROP SETQ T MAY-SURROUND-DEFUN)

;;; Note that the second arg (FIFTY) should be a number (50) rather than a string ("(")
;;; due to the LAST-CHAR hack.
(DEFUN XR-READ-LIST (STREAM SHOULD-BE-NIL FIFTY)
  (DECLARE (IGNORE SHOULD-BE-NIL))		;This would be the string if there were one.
  (PROG (LIST THING TYPE END-OF-LIST BP CORRESPONDENCE-ENTRY
	 (INSIDE-COLUMN-0-LIST INSIDE-COLUMN-0-LIST)
	 (THIS-IS-COLUMN-0-LIST (AND READ-CHECK-INDENTATION
				     (= XR-XRTYI-PREV-CHAR #/RETURN))))
	(AND THIS-IS-COLUMN-0-LIST
	     (NOT *READ-SUPPRESS*)
	     (IF (NOT INSIDE-COLUMN-0-LIST)
		 (SETQ INSIDE-COLUMN-0-LIST T)
	       ;; ( in column 0 when not allowed.
	       ;; Report it (but only report each occurrence once).
	       (OR MISSING-CLOSEPAREN-REPORTED
		   (PROGN (SETQ MISSING-CLOSEPAREN-REPORTED T)
			  (SIGNAL-PROCEED-CASE (() 'SYS:MISSING-CLOSEPAREN
						   "Open paren found in column zero; missing closeparens assumed.")
			    (:NO-ACTION))))
	       ;; Unread it the char.  The -1 prevents barfage in XR-XRUNTYI, that's all.
	       (XR-XRUNTYI STREAM XR-XRTYI-LAST-CHAR -1)
	       ;; Set a signal for the XR-READ-LIST frame that called us.
	       (SETQ XR-SPLICE-P 'MISSING-CLOSEPAREN)
	       (RETURN NIL)))
	(SETQ MISSING-CLOSEPAREN-REPORTED NIL)
	(SETQ END-OF-LIST (LOCF LIST))
	(WHEN XR-CORRESPONDENCE-FLAG
	  (SEND STREAM :UNTYI FIFTY)
	  (SETQ CORRESPONDENCE-ENTRY
		`(NIL ,(SEND STREAM :READ-BP) NIL . ,XR-CORRESPONDENCE))
	  (SETQ XR-CORRESPONDENCE CORRESPONDENCE-ENTRY)
	  (SEND STREAM :TYI))
     A
	(WHEN XR-CORRESPONDENCE-FLAG
	  (PUSH (SEND STREAM :READ-BP) (CADDR CORRESPONDENCE-ENTRY)))
	(MULTIPLE-VALUE-SETQ (THING TYPE) (XR-READ-THING STREAM))
	;; If this is the first element of a list starting in column 0,
	;; and it is EVAL-WHEN or something like that,
	;; say it is ok for our sublists to start in column 0.
	(AND THIS-IS-COLUMN-0-LIST
	     (EQ END-OF-LIST (LOCF LIST))
	     (SYMBOLP THING)
	     ;; It is usually dangerous for READ to look at properties of symbols,
	     ;; but this will only happen for the symbol after a paren in column 0
	     ;; and never in lists read in interactively.
	     (GET THING 'MAY-SURROUND-DEFUN)
	     (SETQ INSIDE-COLUMN-0-LIST NIL))
	(COND ((EQ TYPE 'READER-MACRO)
	       (WHEN XR-CORRESPONDENCE-FLAG
		 (SEND STREAM :UNTYI FIFTY)
		 (SETQ BP (SEND STREAM :READ-BP))
		 (SEND STREAM :TYI))
	       (LET ((XR-LIST-SO-FAR LIST)
		     (XR-SPLICE-P NIL)
		     VALUES)
		 (SETQ VALUES (INVOKE-READER-MACRO THING STREAM))
		 (COND ((EQ XR-SPLICE-P 'MISSING-CLOSEPAREN)
			;; This means that the reader macro was (
			;; and it was unhappy about being at column 0
			;; inside another column 0 list.
			;; Pretend we saw a ).
			(AND XR-CORRESPONDENCE-FLAG
			     (SETF (CAR CORRESPONDENCE-ENTRY) LIST)
			     (SETF (CADDR CORRESPONDENCE-ENTRY)
				   (NREVERSE (CADDR CORRESPONDENCE-ENTRY))))
			(RETURN LIST 'LIST))
		       (XR-SPLICE-P
			(SETQ LIST XR-LIST-SO-FAR)
			(AND XR-CORRESPONDENCE-FLAG
			     (SETF (CADDR CORRESPONDENCE-ENTRY)
				   (FIRSTN (LENGTH LIST)
					   (CADDR CORRESPONDENCE-ENTRY))))
			(SETQ END-OF-LIST (IF (ATOM LIST) (LOCF LIST) (LAST LIST))))
		       (VALUES
			(SETF (CDR END-OF-LIST) (SETQ VALUES (COPY-LIST VALUES READ-AREA)))
			(SETQ END-OF-LIST (LAST VALUES))
			(WHEN XR-CORRESPONDENCE-FLAG
			  (SETQ XR-CORRESPONDENCE
				`(,(CAR VALUES) ,BP NIL . ,XR-CORRESPONDENCE))))))
	       (GO A))
	      ((EQ TYPE 'SPECIAL-TOKEN)
	       (COND ((EQ THING 'CLOSE)
		      (AND XR-CORRESPONDENCE-FLAG
			   (SETF (CAR CORRESPONDENCE-ENTRY) LIST)
			   (SETF (CADDR CORRESPONDENCE-ENTRY)
				 (NREVERSE (CADDR CORRESPONDENCE-ENTRY))))
		      (RETURN LIST 'LIST))
		     ((EQ THING 'EOF)
		      (OR (AND READ-CHECK-INDENTATION MISSING-CLOSEPAREN-REPORTED)
			  (SIGNAL-PROCEED-CASE (() 'SYS:READ-LIST-END-OF-FILE
						   "End of file on ~S in the middle of the list ~:S."
						   STREAM LIST)
			    (:NO-ACTION
			     (IF READ-CHECK-INDENTATION
				 (SETQ MISSING-CLOSEPAREN-REPORTED T)))))
		      (RETURN LIST 'LIST))
		     (*READ-SUPPRESS* NIL)
		     ((EQ THING 'CONSING-DOT)
		      (WHEN (NULL LIST)
			(CERROR :NO-ACTION NIL 'SYS:READ-ERROR-1
				"A dot was read before any list was accumulated.")
			(GO A))
		      (GO RDOT))
		     (T (CERROR :NO-ACTION NIL 'SYS:READ-ERROR-1
				"The special token ~S was read in the middle of the list ~:S."
				THING
				LIST))))
	      (T
	       (SETF (CDR END-OF-LIST) (SETQ END-OF-LIST (NCONS-IN-AREA THING READ-AREA)))
	       (GO A)))
     RDOT
	(MULTIPLE-VALUE (THING TYPE) (XR-READ-THING STREAM))
	(WHEN (EQ TYPE 'SPECIAL-TOKEN)
	  (CERROR :NO-ACTION NIL 'SYS:READ-ERROR-1
		  "The special token ~S was read after a dot."
		  THING)
	  (GO RDOT))
	(WHEN (EQ TYPE 'READER-MACRO)
	  (LET ((XR-LIST-SO-FAR :AFTER-DOT)
		(XR-SPLICE-P NIL)
		VALUES)
	    (SETQ VALUES (INVOKE-READER-MACRO THING STREAM))
	    (WHEN XR-SPLICE-P
	      (SETQ LIST XR-LIST-SO-FAR)
	      (GO RDOT))
	    (WHEN (NULL VALUES)
	      (GO RDOT))
	    (SETQ THING (CAR VALUES))))
	(SETF (CDR END-OF-LIST) THING)
     RDOT-1
	(MULTIPLE-VALUE (THING TYPE) (XR-READ-THING STREAM))
	(COND ((AND (EQ THING 'CLOSE) (EQ TYPE 'SPECIAL-TOKEN))
	       (AND XR-CORRESPONDENCE-FLAG
		    (SETF (CAR CORRESPONDENCE-ENTRY) LIST)
		    (SETF (CADDR CORRESPONDENCE-ENTRY)
			  (NREVERSE (CADDR CORRESPONDENCE-ENTRY))))
	       (RETURN LIST 'LIST))
	      ((EQ TYPE 'READER-MACRO)
	       (LET ((XR-LIST-SO-FAR :AFTER-DOT)
		     (XR-SPLICE-P NIL)
		     VALUES)
		 (SETQ VALUES (INVOKE-READER-MACRO THING STREAM))
		 (WHEN (OR XR-SPLICE-P (NULL VALUES))
		   (GO RDOT-1)))
	       (CERROR :NO-ACTION NIL 'SYS:READ-ERROR-1
		       "~S was read instead of a close paren (returned by a reader macro)."
		       THING))
	      (T (CERROR :NO-ACTION NIL 'SYS:READ-ERROR-1
			 "~S was read instead of a close paren."
			 THING)))
	;; Here only if error condition gets handled.
	(SETF (CDR END-OF-LIST) (LIST (CDR END-OF-LIST) THING))
	(SETQ END-OF-LIST (LAST END-OF-LIST))
	(GO A)))

(DEFUN (MULTI-DOT STANDARD-READ-FUNCTION) (STREAM STRING)
  (DECLARE (IGNORE STREAM))
  (CERROR :NO-ACTION NIL 'READ-ERROR-1
	  "~S was encountered on input by the reader." STRING)
  (VALUES NIL 'SYMBOL))

(DEFPROP SYMBOL XR-READ-SYMBOL STANDARD-READ-FUNCTION)
(DEFPROP SC-SYMBOL XR-READ-SYMBOL STANDARD-READ-FUNCTION)
(DEFPROP POTENTIAL-NUMBER XR-READ-SYMBOL STANDARD-READ-FUNCTION)
(DEFUN XR-READ-SYMBOL (STREAM STRING)
  (DECLARE (IGNORE STREAM))			;ignored, doesn't do any additional reading
  (LET (R)
    (LET-IF (VARIABLE-BOUNDP *PACKAGE*)
	    ((*PACKAGE* *PACKAGE*))
      (WHEN (VARIABLE-BOUNDP *PACKAGE*)
	(UNLESS (OR *PACKAGE* *READ-SUPPRESS*)
	  (CERROR :NO-ACTION NIL 'SYS:READ-ERROR-1
		  "*PACKAGE* is now NIL, and symbol ~S has no package prefix." string)
	  (SETQ *PACKAGE* PKG-USER-PACKAGE)))
      (IF *READ-SUPPRESS*
	  (SETQ R NIL)
	(SETQ R (FUNCALL READ-INTERN-FUNCTION STRING)))
      (LET ((S (CDR (ASSQ R (RDTBL-SYMBOL-SUBSTITUTIONS *READTABLE*)))))
	(AND S (NEQ *PACKAGE* (SYMBOL-PACKAGE R)) (SETQ R S)))
      (VALUES R 'SYMBOL))))

(DEFUN (MACRO-CHAR STANDARD-READ-FUNCTION) (STREAM SHOULD-BE-NIL LAST-CHAR &AUX TEM)
  (DECLARE (IGNORE STREAM SHOULD-BE-NIL))
  (IF (SETQ TEM (ASSQ LAST-CHAR (RDTBL-MACRO-ALIST *READTABLE*)))
      (IF (AND (CONSP (CDR TEM)) (EQ (CADR TEM) 'XR-CLOSEPAREN-MACRO))
	  (VALUES 'CLOSE 'SPECIAL-TOKEN)
	  (VALUES (CDR TEM) 'READER-MACRO))
    (CERROR :NO-ACTION NIL 'SYS:READ-ERROR-1
	    "No reader macro definition found for the character ~C." LAST-CHAR)))

;;; FOO: switches us to the package associated with the string "FOO"
;;; FOO:: is Common Lisp for "allow internal symbols", but we always do that.
(DEFUN (PACKAGE-PREFIX STANDARD-READ-FUNCTION) (STREAM STRING LAST-CH)
  (DECLARE (IGNORE LAST-CH))
  (PROG (THING PK
	 ;; Help un-screw the user if *PACKAGE* gets set to NIL.
	 (*PACKAGE* (OR *PACKAGE* PKG-USER-PACKAGE))
	 INTERNAL-OK ENTIRE-LIST-PREFIXED)
	;; Gobble the second colon, if any, and set flag if found.
	;; Note that we do not, currently, DO anything with the flag!
	(MULTIPLE-VALUE-BIND (CH NUM REAL-CH)
	    (XR-XRTYI STREAM NIL T)
	  (IF (= CH #/:)
	      (SETQ INTERNAL-OK T)
	    (IF (= CH #/()
		(SETQ ENTIRE-LIST-PREFIXED T))
	    (XR-XRUNTYI STREAM REAL-CH NUM)))
	;; Try to find the package.
	(DO ((STRING1 (OR STRING "")))
	    ;;don't try to find packages if we're not interning -- eg #+slime (dis:foo)
	    ((OR *READ-SUPPRESS*
		 (SETQ PK (FIND-PACKAGE STRING1 PACKAGE))))
	  ;; Package not found.
	  (SIGNAL-PROCEED-CASE ((PKG) 'SYS:READ-PACKAGE-NOT-FOUND
				      "Package ~S does not exist."
				      STRING1)
	    (:NO-ACTION
	     (RETURN))
	    (:NEW-NAME
	     (LET ((*PACKAGE* PKG-USER-PACKAGE))
	       (SETQ STRING1 (STRING (READ-FROM-STRING PKG)))))
	    (:CREATE-PACKAGE
	     (OR (FIND-PACKAGE STRING1 PACKAGE)
		 (MAKE-PACKAGE STRING1)))))
	(UNLESS PK
	  (SETQ PK PKG-USER-PACKAGE))
	(WHEN STRING (RETURN-READ-STRING STRING))
	(LET ((*PACKAGE* PK)
	      (READ-INTERN-FUNCTION
		(IF (OR (AND (PKG-AUTO-EXPORT-P PK)
			     (PACKAGE-USED-BY-LIST PK))
			(PKG-READ-LOCK-P PK))
		    'READ-INTERN-SOFT
		    'INTERN)
		;; This change may occur only in Common Lisp.
		#| (IF (OR ENTIRE-LIST-PREFIXED (EQ PK *PACKAGE*))
		       ;; Here for, e.g., SI: while in SI already.
		       ;; There are things in LOOP which MUST say "SI:" even though
		       ;; loop is loaded into SI on the Lisp machine.
		       ;; Also here for ZWEI:(BP-LINE (POINT));
		       ;; such constructs are not valid Common Lisp
		       ;; so let's keep their meaning the same.
		       READ-INTERN-FUNCTION
		     (IF READ-COLON-ALLOW-INTERNALS
			 'READ-PACKAGE-PREFIX-INTERN
		       'READ-PACKAGE-PREFIX-EXTERNAL-INTERN)) |#))
	  (SETQ THING (INTERNAL-READ STREAM T NIL T))
	  ;; Don't use symbol substitution if a package is explicitly specified!
	  (WHEN (SYMBOLP THING) (SETQ THING (INTERN THING *PACKAGE*))))
	(RETURN THING (TYPE-OF THING) T)))	;T means we already did RETURN-READ-STRING

(DEFUN READ-PACKAGE-PREFIX-EXTERNAL-INTERN (STRING)
  (MULTIPLE-VALUE-BIND (SYM FLAG PKG)
      (FIND-EXTERNAL-SYMBOL STRING)
    (UNLESS FLAG
      (CERROR :NO-ACTION NIL 'SYS:READ-ERROR-1
	      "Reference to nonexistent external symbol ~S in package ~A with a colon prefix."
	      STRING *PACKAGE*)
      (SETF (VALUES SYM FLAG PKG) (INTERN STRING PKG-KEYWORD-PACKAGE)))
    (VALUES SYM FLAG PKG)))

;;; Used instead of INTERN when reading inside a colon prefix,
;;; if READ-COLON-ALLOW-INTERNALS is non-NIL.
(DEFUN READ-PACKAGE-PREFIX-INTERN (STRING)
  (MULTIPLE-VALUE-BIND (SYM FLAG PKG)
      (IF (OR (AND (PKG-AUTO-EXPORT-P *PACKAGE*)
		   (PACKAGE-USED-BY-LIST *PACKAGE*))
	      (PKG-READ-LOCK-P *PACKAGE*))
	  (FIND-SYMBOL STRING)
	(INTERN STRING))
    (WHEN (EQ FLAG :INTERNAL)
      (CERROR :NO-ACTION NIL 'SYS:READ-ERROR-1
	      "Reference to internal symbol ~S in package ~A with a colon prefix."
	      SYM *PACKAGE*))
    (UNLESS (OR FLAG (NOT (OR (AND (PKG-AUTO-EXPORT-P *PACKAGE*)
				   (PACKAGE-USED-BY-LIST *PACKAGE*))
			      (PKG-READ-LOCK-P *PACKAGE*))))
      (CERROR :NO-ACTION NIL 'SYS:READ-ERROR-1
	      "Package ~A is ~:[autoexporting~;read-locked~]; READ cannot make a symbol ~S there."
	      (PACKAGE-NAME *PACKAGE*) (PKG-READ-LOCK-P *PACKAGE*) STRING)
      (SETF (VALUES SYM FLAG PKG)
	    (INTERN STRING PKG-KEYWORD-PACKAGE)))
    (VALUES SYM FLAG PKG)))

;;; FOO#: is like FOO: but ignores local nicknames.
;;; Just #: means make uninterned symbol.
(DEFUN (SHARP-PACKAGE-PREFIX STANDARD-READ-FUNCTION) (STREAM STRING LAST-CH)
  (DECLARE (IGNORE LAST-CH))
  (PROG (THING TYPE PK
	 ;; Help un-screw the user if *PACKAGE* gets set to NIL.
	 (*PACKAGE* (OR *PACKAGE* PKG-USER-PACKAGE))
	 (PKG-NAME (SUBSTRING STRING 0 (1- (LENGTH STRING)))))
	;; Try to find the package.
	(UNLESS
	  ;;don't tvy to find packages if we're not interning -- eg #+slime (dis:foo)
	  (OR *READ-SUPPRESS*
	      (SETQ PK (FIND-PACKAGE PKG-NAME NIL)))
	  ;; Package not found.
	  (CERROR :NO-ACTION NIL 'SYS:READ-ERROR-1
		  "Package ~S does not exist." PKG-NAME))
	(UNLESS PK
	  (SETQ PK PKG-USER-PACKAGE))
	(RETURN-READ-STRING STRING)
	(LET ((*PACKAGE* PK)
	      (READ-INTERN-FUNCTION
		(COND ((EQUAL PKG-NAME "")
		       'READ-UNINTERNED-SYMBOL)
		      ((OR (AND (PKG-AUTO-EXPORT-P PK)
				(PACKAGE-USED-BY-LIST PK))
			   (PKG-READ-LOCK-P PK))
		       'READ-INTERN-SOFT)
		      (T 'INTERN))))
	  (MULTIPLE-VALUE (THING TYPE)
	    (INTERNAL-READ STREAM T NIL T)))
	(RETURN-ARRAY PKG-NAME)
	(RETURN THING TYPE T)))			;T means we already did RETURN-READ-STRING.

;;; "Intern" function used within #: prefixes that specify uninterned symbols.
(DEFUN READ-UNINTERNED-SYMBOL (STRING)
  (VALUES (MAKE-SYMBOL STRING T) NIL T))	;Last value T avoids error in XR-READ-SYMBOL.

;;; Used for interning in auto-exporting packages.
(DEFUN READ-INTERN-SOFT (STRING)
  (MULTIPLE-VALUE-BIND (SYM FLAG PKG)
      (FIND-SYMBOL STRING)
    (UNLESS FLAG
      (CERROR :NO-ACTION NIL 'SYS:READ-ERROR-1
	      "Package ~A is ~:[autoexporting~;read-locked~]; READ cannot make a symbol ~S there."
	      (PACKAGE-NAME *PACKAGE*) (PKG-READ-LOCK-P *PACKAGE*) STRING)
      (SETF (VALUES SYM FLAG PKG)
	    (INTERN STRING PKG-KEYWORD-PACKAGE)))
    (VALUES SYM FLAG PKG)))

;;; This function is given a string, an index into the string, and the length
;;; of the string.  It looks for a signed, possibly decimal-pointed number,
;;; computes it, and returns two values: the fixnum, and the index in the
;;; string of where the first char was that caused it to stop.  The second
;;; value will equal the "length" argument if it got to the end of the string.
;;; it takes a base as well.
(DEFUN XR-READ-FIXNUM-INTERNAL (STRING II LEN &OPTIONAL (IBS *READ-BASE*)
				&AUX (SIGN 1) (NUM 0) CH)
  (SETQ CH (CHAR STRING II))
  (COND ((= CH #/+)
	 (INCF II))
	((= CH #/-)
	 (INCF II)
	 (SETQ SIGN -1)))
  (DO ((I II (1+ I)))
      (( I LEN)
       (VALUES (* SIGN NUM) LEN))
    (SETQ CH (CHAR STRING I))
    (COND (( #/0 CH #/9)
	   (SETQ NUM (+ (* NUM IBS) (- CH #/0))))
	  ((= CH #/.)
	   (COND ((= IBS 10.)
		  (RETURN (* SIGN NUM) (1+ I)))
		 (T
		  ;; Start from beginning, but base ten this time.
		  (SETQ IBS 10.)
		  (SETQ NUM 0)
		  (SETQ I (- II 1)))))
	  (( #/A CH #/Z)
	   (SETQ NUM (+ (* NUM IBS) (- CH (- #/A 10.)))))
	  (( #/a CH #/z)
	   (SETQ NUM (+ (* NUM IBS) (- CH (- #/a 10.)))))
	  (T (RETURN (* SIGN NUM) I)))))

;; This function takes a string which represents a fixnum (and a stream
;; which it doesn't use), and returns the fixnum.  It ASSUMES that the string
;; follows the format of the standard readtable.
(DEFPROP FIXNUM XR-READ-FIXNUM STANDARD-READ-FUNCTION)
(DEFUN XR-READ-FIXNUM (STREAM STRING &AUX NUM LEN I)
  (DECLARE (IGNORE STREAM))
  (UNLESS (AND (FIXNUMP *READ-BASE*)	;If it were a flonum, confusing things would happen
	       ( 2 *READ-BASE* 36.))
    (CERROR :NO-ACTION NIL NIL "~S bad value for *READ-BASE*.  Has been reset to 10."
	    (PROG1 *READ-BASE* (SETQ *READ-BASE* 10.))))
  (SETQ LEN (ARRAY-ACTIVE-LENGTH STRING))
  (MULTIPLE-VALUE-SETQ (NUM I)
    (XR-READ-FIXNUM-INTERNAL STRING 0 LEN))
  (VALUES
    (IF (= I LEN)
	NUM
      (LET ((NUM2 (XR-READ-FIXNUM-INTERNAL STRING (1+ I) LEN)))
	(IF (= (CHAR STRING I) #/_)
	    (ASH NUM NUM2)
	  (* NUM (^ *READ-BASE* NUM2)))))
    'FIXNUM))

(DEFMACRO SKIP-CHAR ()
  `(PROGN (DECF COUNT)
	  (INCF INDEX)))

(DEFVAR POWERS-OF-10f0-TABLE :UNBOUND
  "Vector which indexed by I contains (^ 10. I) as a single-float.")
(DEFVAR NEGATIVE-POWERS-OF-10f0-TABLE :UNBOUND
  "Vector which indexed by i contains (- (^ 10. I)) as a single-float.")
(DEFVAR POWERS-OF-10f0-TABLE-LENGTH 308.)

(DEFUN XR-READ-FLONUM (STRING SFL-P &AUX (POWER-10 0) (INDEX 0) (POSITIVE T)
                                         (HIGH-PART 0) (LOW-PART 0) (NDIGITS 12.)
                                         COUNT CHAR STRING-LENGTH)
  (DECLARE (SPECIAL HIGH-PART LOW-PART NDIGITS INDEX COUNT POWER-10))
  (SETQ COUNT (LENGTH STRING)
	STRING-LENGTH COUNT)
  (SETQ CHAR (CHAR STRING INDEX))
  ;; CHECK FOR PLUS OR MINUS
  (WHEN (OR (= CHAR #/+) (= CHAR #/-))
    (SKIP-CHAR)
    (SETQ POSITIVE (= CHAR #/+)))
  ;; skip leading zeros
  (DO ()
      (( (CHAR STRING INDEX) #/0))
    (SKIP-CHAR))
  (COND ((= (CHAR STRING INDEX) #/.)		;If we hit a point, keep stripping 0's
	 (SKIP-CHAR)
	 (DO ()
	     ((OR (< COUNT 2)			;Leave one digit at least
		  (NOT (= (CHAR STRING INDEX) #/0))))	;Or non-zero digit
	   (SKIP-CHAR)
	   (INCF POWER-10))
	 (XR-ACCUMULATE-DIGITS STRING T))
	;; Accumulate digits up to the point or exponent (these are free)
	(T (XR-ACCUMULATE-DIGITS STRING NIL)
	   (WHEN (= (CHAR STRING INDEX) #/. )
	     (SKIP-CHAR)
	     ;; Skip trailing zeros after the point.  This avoids having a
	     ;; one in the lsb of 2.0 due to dividing 20. by 10.
	     (LET ((IDX (STRING-SEARCH-NOT-SET '(#/0) STRING INDEX)))
	       (COND ((NULL IDX) (SETQ COUNT 0))	;Nothing but zeros there
		     ((NOT (MEMQ (CHAR STRING IDX) '(#/1 #/2 #/3 #/4 #/5
						     #/6 #/7 #/8 #/9)))
		      (SETQ INDEX IDX		;Not digits there except zeros
			    COUNT (- STRING-LENGTH INDEX)))
		     (T				;Real digits present, scan normally
		      (XR-ACCUMULATE-DIGITS STRING T)))))))
  ;; Here we have read something up to exponent if it exists, or end of string
  (WHEN (> COUNT 0)
    (SKIP-CHAR)					;Skip the exponent character
    (SETQ POWER-10 (- POWER-10
		      (XR-READ-FIXNUM-INTERNAL STRING
					       INDEX
					       STRING-LENGTH
					       10.))))
  (LET ((NUM (IF SFL-P (SMALL-FLOAT (XR-FLONUM-CONS HIGH-PART LOW-PART POWER-10))
	       (XR-FLONUM-CONS HIGH-PART LOW-PART POWER-10))))
    (IF POSITIVE NUM (- NUM))))

(DEFUN XR-ACCUMULATE-DIGITS (STRING POST-DECIMAL &AUX CHAR)
  (DECLARE (SPECIAL HIGH-PART LOW-PART NDIGITS INDEX COUNT POWER-10))
  (DO () ((= COUNT 0))
    (SETQ CHAR (CHAR STRING INDEX))
    (UNLESS ( #/0 CHAR #/9)
      (RETURN NIL))
    (IF ( NDIGITS 0)
	(UNLESS POST-DECIMAL (DECF POWER-10))
      (SETQ HIGH-PART (+ (* HIGH-PART 10.)
			 (LSH (%MULTIPLY-FRACTIONS LOW-PART 10.) 1))
	    LOW-PART (%POINTER-TIMES LOW-PART 10.))
      (WHEN (MINUSP LOW-PART)			;Carried into sign-bit
	(INCF HIGH-PART)
	(SETQ LOW-PART (LOGAND LOW-PART MOST-POSITIVE-FIXNUM)))
      (SETQ LOW-PART (%POINTER-PLUS LOW-PART (- CHAR #/0)))
      (WHEN (MINUSP LOW-PART)			;Carried into sign-bit
	(INCF HIGH-PART)
	(SETQ LOW-PART (LOGAND LOW-PART MOST-POSITIVE-FIXNUM)))
      (WHEN POST-DECIMAL (INCF POWER-10)))
    (SKIP-CHAR)
    (DECF NDIGITS)))

;;; Here POWER-10 is the power of 10 that the number in high,,low should be
;;; divided by.
(DEFUN XR-FLONUM-CONS (HIGH LOW POWER-10 &AUX FLOAT-NUMBER)
  (SETQ FLOAT-NUMBER (%FLOAT-DOUBLE (LSH HIGH -1)
				    (LOGIOR (ROT (LOGAND HIGH 1) -1) LOW)))
  (COND ((< POWER-10 0) (* FLOAT-NUMBER (XR-GET-POWER-10 (- POWER-10))))
	((> POWER-10 0) (// FLOAT-NUMBER (XR-GET-POWER-10 POWER-10)))
	(T FLOAT-NUMBER)))

(DEFUN XR-GET-POWER-10 (POWER)
  ;; This check detects things grossly out of range.  Numbers almost out of range
  ;; can still get floating-point overflow errors in the reader when multiplying
  ;; the mantissa by the power of 10
  (IF ( POWER POWERS-OF-10F0-TABLE-LENGTH)
      (PROGN (CERROR :NO-ACTION NIL 'SYS:READ-ERROR-1
		     "~D is larger than the maximum allowed exponent." POWER)
	     1)
    (AREF POWERS-OF-10F0-TABLE POWER)))

;;; Make a table of powers of 10 without accumulated roundoff error,
;;; by doing integer arithmetic and then floating.  Thus each table entry
;;; is the closest rounded flonum to that power of ten.
;;; It didn't used to work this way because there didn't use to be bignums.
(DEFUN XR-TABLE-SETUP ()
  (SETQ POWERS-OF-10F0-TABLE (MAKE-ARRAY POWERS-OF-10F0-TABLE-LENGTH
					 :TYPE 'ART-FLOAT :AREA CONTROL-TABLES))
  (SETQ NEGATIVE-POWERS-OF-10F0-TABLE (MAKE-ARRAY POWERS-OF-10F0-TABLE-LENGTH
					 :TYPE 'ART-FLOAT :AREA CONTROL-TABLES))
  (DO ((EXPT 0 (1+ EXPT))
       (POWER 1. (* POWER 10.))
       (FLOAT))
      (( EXPT POWERS-OF-10F0-TABLE-LENGTH))
    (SETQ FLOAT (FLOAT POWER))
    (SETF (AREF POWERS-OF-10F0-TABLE EXPT) FLOAT
	  (AREF NEGATIVE-POWERS-OF-10F0-TABLE EXPT) (- FLOAT))))

(XR-TABLE-SETUP)

(DEFVAR *READ-DEFAULT-FLOAT-FORMAT* 'SINGLE-FLOAT
  "Default floating point type for READ to create.
This is the type of flonum that READ makes when there is no exponent
or when the exponent is introduced with /"E/".  If the input being read
uses /"S/", /"F/", /"L/" or /"D/" then that specifies the type explicitly
and this default is not used.")

(DEFUN (FLOAT STANDARD-READ-FUNCTION) (STREAM STRING)
  (DECLARE (IGNORE STREAM))			;doesn't do any additional reading
  (XR-READ-FLONUM STRING (EQ *READ-DEFAULT-FLOAT-FORMAT* 'SHORT-FLOAT)))

(DEFUN (SINGLE-FLOAT STANDARD-READ-FUNCTION) (STREAM STRING)
  (DECLARE (IGNORE STREAM))			;doesn't do any additional reading
  (XR-READ-FLONUM STRING NIL))

(DEFUN (SHORT-FLOAT STANDARD-READ-FUNCTION) (STREAM STRING)
  (DECLARE (IGNORE STREAM))			;doesn't do any additional reading
  (XR-READ-FLONUM STRING T))

;;;; Standard reader macros:
(DEFUN XR-QUOTE-MACRO (STREAM IGNORE)
  (LIST-IN-AREA READ-AREA 'QUOTE (INTERNAL-READ STREAM T NIL T)))

(DEFUN XR-COMMENT-MACRO (STREAM IGNORE)
  (SETQ XR-XRTYI-LAST-CHAR #/NEWLINE)
  (LOOP AS CH = (SEND STREAM :TYI)
	WHILE (AND CH ( CH #/NEWLINE))
	FINALLY (RETURN)))

(DEFUN XR-OPENPAREN-MACRO (STREAM IGNORE)
  (VALUES (XR-READ-LIST STREAM NIL #/()))

(DEFUN XR-DOUBLEQUOTE-MACRO (STREAM MATCH)
  (LET* (CH NUM REAL-CH (I 0) (LEN #o100)
	 (STRING (MAKE-ARRAY LEN ':TYPE ART-STRING))
	 ;; Should have ':AREA READ-AREA, but leave this out for now because the
	 ;; compiler thinks it can use COPYTREE to copy forms out of the temp area.
	 (TEM (RDTBL-SLASH-CODE *READTABLE*)))
    (DO-FOREVER
      (MULTIPLE-VALUE-SETQ (CH NUM REAL-CH) (XR-XRTYI STREAM NIL NIL T))
      (COND ((NULL CH)
	     (CERROR ':NO-ACTION NIL 'SYS:READ-STRING-END-OF-FILE
		     "EOF on ~S in the middle of a string."
		     STREAM STRING)
	     (RETURN ""))
	    ((AND (= (CHAR-CODE REAL-CH) MATCH)
		  (NOT (= NUM TEM)))
	     (ADJUST-ARRAY-SIZE STRING I)
	     (RETURN STRING))
	    (T (SETF (CHAR STRING I) (CHAR-CODE REAL-CH))
	       (INCF I)
	       (WHEN (= I LEN)
		 (INCF LEN 32.)
		 (ADJUST-ARRAY-SIZE STRING LEN)))))))

;(DEFUN XR-VERTICALBAR-MACRO (STREAM MATCH)
;  (LET ((STRING (GET-READ-STRING)))
;    (UNWIND-PROTECT
;	(PROG (CH NUM REAL-CH (I 0) (LEN (ARRAY-LENGTH STRING)) R TEM)
;	      (SETQ TEM (RDTBL-SLASH-CODE *READTABLE*))
;	    L (MULTIPLE-VALUE (CH NUM REAL-CH) (XR-XRTYI STREAM))
;	      (COND ((NULL CH)
;		     (CERROR ':NO-ACTION NIL 'SYS:READ-SYMBOL-END-OF-FILE
;			     "EOF on ~S in the middle of a quoted symbol."
;			     STREAM STRING)
;		     (RETURN NIL))
;		    ((AND (= (LDB %%CH-CHAR REAL-CH) MATCH)
;			  (NOT (= NUM TEM)))
;		     (SETF (FILL-POINTER STRING) I)
;		     ;; See if a : or #: follows.
;		     ;; If so, this is really a package prefix.
;		     (MULTIPLE-VALUE-BIND (CH NUM REAL-CH)
;			 (XR-XRTYI STREAM NIL T)
;		       (WHEN CH
;			 (IF (= CH #/:)
;			     (RETURN (FUNCALL (GET 'PACKAGE-PREFIX 'STANDARD-READ-FUNCTION)
;					      STREAM STRING NIL)))
;			 (IF (NOT (= CH #/#))
;			     (XR-XRUNTYI STREAM REAL-CH NUM)
;			   (SETQ CH (XR-XRTYI STREAM))
;			   (WHEN (= CH #/:)
;			     (ARRAY-PUSH-EXTEND STRING #/#)
;			     (RETURN (FUNCALL (GET 'SHARP-PACKAGE-PREFIX
;						   'STANDARD-READ-FUNCTION)
;					      STREAM STRING NIL)))
;			   (CERROR ':NO-ACTION NIL 'SYS:READ-ERROR-1
;				   "#~C appeared immediately following a vertical-bar ending a quoted symbol." CH))))
;		     (IF *READ-SUPPRESS*
;			 (RETURN NIL 'SYMBOL))
;		     (SETF R (FUNCALL READ-INTERN-FUNCTION STRING))
;		     (RETURN (OR (CDR (ASSQ R (RDTBL-SYMBOL-SUBSTITUTIONS *READTABLE*))) R)))
;		    (T (AS-1 (LDB %%CH-CHAR REAL-CH) STRING I)
;		       (SETQ I (1+ I))
;		       (COND ((= I LEN)
;			      (SETQ LEN (+ LEN 32.))
;			      (ADJUST-ARRAY-SIZE STRING LEN)
;			      (SETQ STRING (FOLLOW-STRUCTURE-FORWARDING STRING))))
;		       (GO L))))
;      (RETURN-READ-STRING STRING))))

;;;BACKQUOTE:
;;; The flags passed back by BACKQUOTIFY can be interpreted as follows:
;;;
;;;   |`,|: [a] => a
;;;    NIL: [a] => a			;the NIL flag is used only when a is NIL
;;;      T: [a] => a			;the T flag is used when a is self-evaluating
;;;  QUOTE: [a] => (QUOTE a)
;;; APPEND: [a] => (APPEND . a)
;;;  NCONC: [a] => (NCONC . a)
;;;   LIST: [a] => (LIST . a)
;;;  LIST*: [a] => (LIST* . a)
;;;
;;; The flags are combined according to the following set of rules:
;;;  ([a] means that a should be converted according to the previous table)
;;;
;;;    \ car   ||    otherwise    |    QUOTE or     |     |`,@|      |     |`,.|      |
;;;  cdr \     ||		  |    T or NIL     |                |		      |
;;;====================================================================================
;;;    |`,|    || LIST* ([a] [d]) | LIST* ([a] [d]) | APPEND (a [d]) | NCONC  (a [d]) |
;;;    NIL     || LIST    ([a])   | QUOTE    (a)    | <hair>    a    | <hair>    a    |
;;; QUOTE or T || LIST* ([a] [d]) | QUOTE  (a . d)  | APPEND (a [d]) | NCONC  (a [d]) |
;;;   APPEND   || LIST* ([a] [d]) | LIST* ([a] [d]) | APPEND (a . d) | NCONC  (a [d]) |
;;;   NCONC    || LIST* ([a] [d]) | LIST* ([a] [d]) | APPEND (a [d]) | NCONC  (a . d) |
;;;    LIST    || LIST  ([a] . d) | LIST  ([a] . d) | APPEND (a [d]) | NCONC  (a [d]) |
;;;    LIST*   || LIST* ([a] . d) | LIST* ([a] . d) | APPEND (a [d]) | NCONC  (a [d]) |
;;;
;;;<hair> involves starting over again pretending you had read ".,a)" instead of ",@a)"

(DEFCONST **BACKQUOTE-/,-FLAG** (MAKE-SYMBOL ","))
(DEFCONST **BACKQUOTE-/,/@-FLAG** (MAKE-SYMBOL ",@"))
(DEFCONST **BACKQUOTE-/,/.-FLAG** (MAKE-SYMBOL ",."))

;Expansions of backquotes actually use these five functions
;so that one can recognize what came from backquote and what did not.

(DEFMACRO XR-BQ-CONS (CAR CDR)
  `(CONS ,CAR ,CDR))

(DEFMACRO XR-BQ-LIST (&REST ELEMENTS)
  `(LIST . ,ELEMENTS))

(DEFMACRO XR-BQ-LIST* (&REST ELEMENTS)
  `(LIST* . ,ELEMENTS))

(DEFMACRO XR-BQ-APPEND (&REST ELEMENTS)
  `(APPEND . ,ELEMENTS))

(DEFMACRO XR-BQ-NCONC (&REST ELEMENTS)
  `(NCONC . ,ELEMENTS))

(DEFMACRO XR-BQ-VECTOR (&REST ELEMENTS)
  `(VECTOR . ,ELEMENTS))

(DEFVAR **BACKQUOTE-REPEAT-VARIABLE-LISTS** NIL)

(DEFUN XR-BACKQUOTE-MACRO (STREAM IGNORE)
  (PROG ((FLAG NIL)
	 (THING NIL)
	 (**BACKQUOTE-REPEAT-VARIABLE-LISTS** (CONS T **BACKQUOTE-REPEAT-VARIABLE-LISTS**)))
	(MULTIPLE-VALUE (FLAG THING) (BACKQUOTIFY (INTERNAL-READ STREAM T NIL T)))
	(AND (EQ FLAG **BACKQUOTE-/,/@-FLAG**)
	     (RETURN
	       (CERROR ':NO-ACTION NIL 'SYS:READ-ERROR-1
		       " /",@/" right after a /"`/": `,@~S." THING)))
	(AND (EQ FLAG **BACKQUOTE-/,/.-FLAG**)
	     (RETURN
	       (CERROR ':NO-ACTION NIL 'SYS:READ-ERROR-1
		       " /",./" right after a /"`/": `,.~S." THING)))
	(RETURN (BACKQUOTIFY-1 FLAG THING))))

(DEFUN XR-#/`-MACRO (STREAM IGNORE &OPTIONAL IGNORE)
  (PROG ((FLAG NIL)
	 (THING NIL)
	 (**BACKQUOTE-REPEAT-VARIABLE-LISTS** (CONS NIL **BACKQUOTE-REPEAT-VARIABLE-LISTS**)))
	(MULTIPLE-VALUE (FLAG THING) (BACKQUOTIFY (INTERNAL-READ STREAM T NIL T)))
	(AND (EQ FLAG **BACKQUOTE-/,/@-FLAG**)
	     (RETURN
	       (CERROR ':NO-ACTION NIL 'SYS:READ-ERROR-1
		       " /",@/" right after a /"`/": `,@~S." THING)))
	(AND (EQ FLAG **BACKQUOTE-/,/.-FLAG**)
	     (RETURN
	       (CERROR ':NO-ACTION NIL 'SYS:READ-ERROR-1
		       " /",./" right after a /"`/": `,.~S." THING)))
	(RETURN (CONS 'PROGN
		      (NREVERSE
			(EVAL1 `(LET (ACCUM)
				  (DO ,(CAR **BACKQUOTE-REPEAT-VARIABLE-LISTS**)
				      ((NULL ,(CAAAR **BACKQUOTE-REPEAT-VARIABLE-LISTS**))
				       ACCUM)
				    (PUSH ,(BACKQUOTIFY-1 FLAG THING) ACCUM)))))))))

(DEFUN XR-COMMA-MACRO (STREAM IGNORE)
  (OR **BACKQUOTE-REPEAT-VARIABLE-LISTS**
      (CERROR ':NO-ACTION NIL 'SYS:READ-ERROR-1
	      "Comma not inside a backquote."))
  (PROG (C)
	(SETF (VALUES NIL NIL C) (XR-XRTYI STREAM NIL T))
	(OR (= C #/@) (= C #/.)
	    (SEND STREAM :UNTYI C))
	(LET ((COMMA-ARG
		(LET ((**BACKQUOTE-REPEAT-VARIABLE-LISTS**
			(CDR **BACKQUOTE-REPEAT-VARIABLE-LISTS**)))
		  (INTERNAL-READ STREAM T NIL T))))
	  (UNLESS (OR (NULL **BACKQUOTE-REPEAT-VARIABLE-LISTS**)
		      (EQ (CAR **BACKQUOTE-REPEAT-VARIABLE-LISTS**) T))
	    (IF (EQ (CAR COMMA-ARG) **BACKQUOTE-/,-FLAG**)
		(SETQ COMMA-ARG (LIST 'QUOTE COMMA-ARG))
	      (LET ((VAR (GENSYM)))
		(PUSH (LIST-IN-AREA READ-AREA VAR (LIST 'QUOTE COMMA-ARG) (LIST 'CDR VAR))
		      (CAR **BACKQUOTE-REPEAT-VARIABLE-LISTS**))
		(SETQ COMMA-ARG (LIST 'CAR VAR)))))
	  (RETURN
	    (COND ((= C #/@)
		   (CONS-IN-AREA **BACKQUOTE-/,/@-FLAG** COMMA-ARG READ-AREA))
		  ((= C #/.)
		   (CONS-IN-AREA **BACKQUOTE-/,/.-FLAG** COMMA-ARG READ-AREA))
		  (T (CONS-IN-AREA **BACKQUOTE-/,-FLAG** COMMA-ARG READ-AREA)))))))

(DEFUN BACKQUOTIFY (CODE)
  (PROG (AFLAG A DFLAG D)
	(COND ((SIMPLE-VECTOR-P CODE)
	       (RETURN 'VECTOR
		       (MAPCAR #'(LAMBDA (ELT)
				   (MULTIPLE-VALUE-BIND (FLAG CODE)
				       (BACKQUOTIFY ELT)
				     (BACKQUOTIFY-1 FLAG CODE)))
			       (LISTARRAY CODE))))
	      ((ATOM CODE)
	       (COND ((NULL CODE) (RETURN NIL NIL))
		     ((OR (NUMBERP CODE)
			  (EQ CODE T))
		      (RETURN T CODE))
		     (T (RETURN 'QUOTE CODE))))
	      ((EQ (CAR CODE) **BACKQUOTE-/,-FLAG**)
	       (SETQ CODE (CDR CODE))
	       (GO COMMA))
	      ((EQ (CAR CODE) **BACKQUOTE-/,/@-FLAG**)
	       (RETURN **BACKQUOTE-/,/@-FLAG** (CDR CODE)))
	      ((EQ (CAR CODE) **BACKQUOTE-/,/.-FLAG**)
	       (RETURN **BACKQUOTE-/,/.-FLAG** (CDR CODE))))
	(MULTIPLE-VALUE (AFLAG A) (BACKQUOTIFY (CAR CODE)))
	(MULTIPLE-VALUE (DFLAG D) (BACKQUOTIFY (CDR CODE)))
	(AND (EQ DFLAG **BACKQUOTE-/,/@-FLAG**)
	     (CERROR ':NO-ACTION NIL 'SYS:READ-ERROR-1
		     " /",@/" after a /"./": .,@~S in ~S." D CODE))
	(AND (EQ DFLAG **BACKQUOTE-/,/.-FLAG**)
	     (CERROR ':NO-ACTION NIL 'SYS:READ-ERROR-1
		     " /",./" after a /"./": .,.~S in ~S." D CODE))
	(COND ((EQ AFLAG **BACKQUOTE-/,/@-FLAG**)
	       (COND ((NULL DFLAG)
		      (SETQ CODE A)
		      (GO COMMA)))
	       (RETURN 'APPEND
		       (COND ((EQ DFLAG 'APPEND)
			      (CONS-IN-AREA A D READ-AREA))
			     (T (LIST-IN-AREA READ-AREA A (BACKQUOTIFY-1 DFLAG D))))))
	      ((EQ AFLAG **BACKQUOTE-/,/.-FLAG**)
	       (COND ((NULL DFLAG)
		      (SETQ CODE A)
		      (GO COMMA)))
	       (RETURN 'NCONC
		       (COND ((EQ DFLAG 'NCONC)
			      (CONS-IN-AREA A D READ-AREA))
			     (T (LIST-IN-AREA READ-AREA A (BACKQUOTIFY-1 DFLAG D))))))
	      ((NULL DFLAG)
	       (COND ((MEMQ AFLAG '(QUOTE T NIL))
		      (RETURN 'QUOTE (LIST A)))
		     (T (RETURN 'LIST
				(LIST-IN-AREA READ-AREA (BACKQUOTIFY-1 AFLAG A))))))
	      ((MEMQ DFLAG '(QUOTE T))
	       (COND ((MEMQ AFLAG '(QUOTE T NIL))
		      (RETURN 'QUOTE (CONS-IN-AREA A D READ-AREA)))
		     (T (RETURN 'LIST* (LIST-IN-AREA READ-AREA
						     (BACKQUOTIFY-1 AFLAG A)
						     (BACKQUOTIFY-1 DFLAG D)))))))
	(SETQ A (BACKQUOTIFY-1 AFLAG A))
	(AND (MEMQ DFLAG '(LIST LIST*))
	     (RETURN DFLAG (CONS A D)))
	(RETURN 'LIST* (LIST-IN-AREA READ-AREA A (BACKQUOTIFY-1 DFLAG D)))
     COMMA (COND ((ATOM CODE)
		  (COND ((NULL CODE)
			 (RETURN NIL NIL))
			((OR (NUMBERP CODE)
			     (EQ CODE 'T))
			 (RETURN T CODE))
			(T (RETURN **BACKQUOTE-/,-FLAG** CODE))))
		 ((EQ (CAR CODE) 'QUOTE)
		  (RETURN (CAR CODE) (CADR CODE)))
		 ((MEMQ (CAR CODE) '(APPEND LIST LIST* NCONC))
		  (RETURN (CAR CODE) (CDR CODE)))
		 ((EQ (CAR CODE) 'CONS)
		  (RETURN 'LIST* (CDR CODE)))
		 (T (RETURN **BACKQUOTE-/,-FLAG** CODE)))))

(DEFUN BACKQUOTIFY-1 (FLAG THING)
  (COND ((OR (EQ FLAG **BACKQUOTE-/,-FLAG**)
	     (MEMQ FLAG '(T NIL)))
	 THING)
	((EQ FLAG 'QUOTE)
	 (LIST-IN-AREA READ-AREA 'QUOTE THING))
	((EQ FLAG 'LIST*)
	 (COND ((NULL (CDDR THING))
		(CONS-IN-AREA 'XR-BQ-CONS THING READ-AREA))
	       (T (CONS-IN-AREA 'XR-BQ-LIST* THING READ-AREA))))
	(T (CONS-IN-AREA (CDR (ASSQ FLAG `((CONS . XR-BQ-CONS)
					   (LIST . XR-BQ-LIST)
					   (APPEND . XR-BQ-APPEND)
					   (NCONC . XR-BQ-NCONC)
					   (VECTOR . XR-BQ-VECTOR))))
			 THING
			 READ-AREA))))

;;;; # submacros.

(DEFUN XR-#B-MACRO (STREAM IGNORE &OPTIONAL IGNORE)
  (LET ((*READ-BASE* 2.))
    (VALUES (INTERNAL-READ STREAM T NIL T))))

(DEFUN XR-#O-MACRO (STREAM IGNORE &OPTIONAL IGNORE)
  (LET ((*READ-BASE* 8.))
    (VALUES (INTERNAL-READ STREAM T NIL T))))

(DEFUN XR-#X-MACRO (STREAM IGNORE &OPTIONAL IGNORE)
  (LET ((*READ-BASE* 16.))
    (VALUES (INTERNAL-READ STREAM T NIL T))))

(DEFUN XR-#R-MACRO (STREAM IGNORE &OPTIONAL (RADIX XR-SHARP-ARGUMENT))
  (UNLESS (INTEGERP RADIX)
    (UNLESS *READ-SUPPRESS*
      (CERROR ':NO-ACTION NIL 'SYS:READ-ERROR-1
	      "#R was read with no digits after the #."))
    (SETQ RADIX 10.))
  (LET ((*READ-BASE* RADIX))
    (VALUES (INTERNAL-READ STREAM T NIL T))))

(DEFUN XR-#/'-MACRO (STREAM IGNORE &OPTIONAL IGNORE)
  (LIST-IN-AREA READ-AREA 'FUNCTION (INTERNAL-READ STREAM T NIL T)))

(DEFVAR FILE-IN-COLD-LOAD NIL
  "T while evaluating text from a file which is in the cold load.
FILE-ATTRIBUTE-BINDINGS makes a binding for this from the Cold-load attribute.")

(DEFUN XR-#/,-MACRO (STREAM IGNORE &OPTIONAL IGNORE)
  (IF FILE-IN-COLD-LOAD
      (CERROR ':NO-ACTION NIL 'SYS:READ-ERROR-1
	      "#, cannot be used in files in the cold load."))
  (IF (AND (BOUNDP 'COMPILER::QC-FILE-READ-IN-PROGRESS) COMPILER::QC-FILE-READ-IN-PROGRESS)
      (CONS-IN-AREA COMPILER::EVAL-AT-LOAD-TIME-MARKER (INTERNAL-READ STREAM T NIL T)
		    READ-AREA)
    (VALUES (IF *READ-SUPPRESS*
		(PROGN (INTERNAL-READ STREAM T NIL T) NIL)
	      (EVAL1 (INTERNAL-READ STREAM T NIL T))))))

(DEFUN XR-#/:-MACRO (STREAM IGNORE IGNORE)
  (LET ((READ-INTERN-FUNCTION 'READ-UNINTERNED-SYMBOL))
    (VALUES (INTERNAL-READ STREAM T NIL T))))

(DEFUN XR-#/(-MACRO (STREAM IGNORE
		     &OPTIONAL (LENGTH (UNLESS *READ-SUPPRESS* XR-SHARP-ARGUMENT)))
  (XR-XRUNTYI STREAM #/( 0)
  (LET* ((ELEMENTS (INTERNAL-READ STREAM T NIL T))
	 (VECTOR (MAKE-ARRAY (OR LENGTH (LENGTH ELEMENTS))
			     :INITIAL-ELEMENT (CAR (LAST ELEMENTS)))))
    (IF (AND LENGTH (PLUSP LENGTH) (NULL ELEMENTS))
	(CERROR ':NO-ACTION NIL 'READ-ERROR-1
		"The construct #~D() is illegal; at least one element must be given."
		LENGTH))
    (IF (< (LENGTH VECTOR) (LENGTH ELEMENTS))
	(CERROR ':NO-ACTION NIL 'READ-ERROR-1
		"Elements specified are more than the specified length in #(..) vector construct."))
    (REPLACE VECTOR ELEMENTS)
    VECTOR))

(DEFUN XR-#*-MACRO (STREAM IGNORE &OPTIONAL (LENGTH XR-SHARP-ARGUMENT)
		    &AUX BIT-VECTOR LAST-ELEMENT-READ)
  (IF *READ-SUPPRESS*
      (PROGN (INTERNAL-READ STREAM T NIL T) NIL)
    (SETQ BIT-VECTOR (MAKE-ARRAY (OR LENGTH 8) :TYPE 'ART-1B :FILL-POINTER 0))
    (DO (CHAR INDEX ERROR-REPORTED) (())
      (SETF (VALUES CHAR INDEX) (XR-XRTYI STREAM NIL T))
      (CASE CHAR
	((#/0 #/1)
	 (SETQ LAST-ELEMENT-READ (- CHAR #/0))
	 (IF LENGTH
	     (UNLESS (OR (ARRAY-PUSH BIT-VECTOR LAST-ELEMENT-READ)
			 ERROR-REPORTED)
	       (CERROR :NO-ACTION NIL 'READ-ERROR-1
		       "Number of data bits exceeds specified length in #* bit vector construct.")
	       (SETQ ERROR-REPORTED T))
	   (VECTOR-PUSH-EXTEND LAST-ELEMENT-READ BIT-VECTOR)))
	(T
	 (IF (AND LENGTH (PLUSP LENGTH) (ZEROP (FILL-POINTER BIT-VECTOR)))
	     (CERROR :NO-ACTION NIL 'READ-ERROR-1
		     "The construct #~D* is illegal; at least one bit must be given."
		     LENGTH))
	 (AND LENGTH
	      ;; ARRAY-PUSH returns () when the fill pointer is at the end of the array.
	      (LOOP WHILE (ARRAY-PUSH BIT-VECTOR LAST-ELEMENT-READ)))
	 (XR-XRUNTYI STREAM CHAR INDEX)
	 (LET ((NVEC (MAKE-ARRAY (LENGTH BIT-VECTOR) :TYPE ART-1B)))
	   (COPY-ARRAY-CONTENTS BIT-VECTOR NVEC)
	   (RETURN NVEC)))))))

(DEFUN XR-#A-MACRO (STREAM IGNORE &OPTIONAL (RANK XR-SHARP-ARGUMENT))
  (IF *READ-SUPPRESS*
      (PROGN (INTERNAL-READ STREAM T NIL T) NIL)
    (IF (AND (FIXNUMP RANK) (PLUSP RANK))
	(LET (DIMENSIONS (SEQUENCES (INTERNAL-READ STREAM T NIL T)))
	  (DO ((DIM 0 (1+ DIM))
	       (STUFF SEQUENCES (ELT STUFF 0)))
	      ((= DIM RANK))
	    (PUSH (LENGTH STUFF) DIMENSIONS))
	  (VALUES (MAKE-ARRAY (NREVERSE DIMENSIONS) :INITIAL-CONTENTS SEQUENCES)))
      (IF (EQ RANK 0)
	  (VALUES (MAKE-ARRAY NIL ':INITIAL-ELEMENT (INTERNAL-READ STREAM T NIL T)))
	(CERROR ':NO-ACTION NIL 'READ-ERROR-1
		"~S is not a valid array rank." RANK)
	(INTERNAL-READ STREAM T NIL T)
	NIL))))

;*********************************************************************************************
;(DEFUN XR-#A-MACRO (STREAM IGNORE &OPTIONAL (RANK XR-SHARP-ARGUMENT))
;  (IF *READ-SUPPRESS*
;      (PROGN (INTERNAL-READ STREAM T NIL T) NIL)
;    (IF (AND (FIXNUMP RANK) (PLUSP RANK))
;	(LET (DIMENSIONS (SEQUENCES (INTERNAL-READ STREAM T NIL T)))
;	  (OR (CLI:LISTP SEQUENCES) (VECTORP SEQUENCES)
;	      (CERROR ':NO-ACTION NIL 'READ-ERROR-1
;		      "The argument to the #A reader macro must be a sequence."))
;	  (DOTIMES (I (1- RANK))
;	    
;
;
;
;	  (DO ((DIM 0 (1+ DIM))
;	       (STUFF SEQUENCES (ELT STUFF 0)))
;	      ((= DIM RANK))
;	    (PUSH (LENGTH STUFF) DIMENSIONS))
;	  (VALUES (MAKE-ARRAY (NREVERSE DIMENSIONS) ':INITIAL-CONTENTS SEQUENCES)))
;      (IF (EQ RANK 0)
;	  (VALUES (MAKE-ARRAY NIL ':INITIAL-ELEMENT (INTERNAL-READ STREAM T NIL T)))
;	(CERROR ':NO-ACTION NIL 'READ-ERROR-1
;		"~S is not a valid array rank." RANK)
;	(INTERNAL-READ STREAM T NIL T)
;	NIL))))

(DEFUN XR-#C-MACRO (STREAM IGNORE IGNORE)
  (IF *READ-SUPPRESS*
      (PROGN (INTERNAL-READ STREAM T NIL T) NIL)
    (APPLY 'COMPLEX (INTERNAL-READ STREAM T NIL T))))

(DEFUN XR-#S-MACRO (STREAM IGNORE &OPTIONAL IGNORE)
  (IF *READ-SUPPRESS*
      (PROGN (INTERNAL-READ STREAM T NIL T) NIL)
    (LET* ((ARGS (INTERNAL-READ STREAM T NIL T))
	   (CONSTRUCTOR
	     (DOLIST (C (DEFSTRUCT-DESCRIPTION-CONSTRUCTORS
			  (GET (CAR ARGS) 'DEFSTRUCT-DESCRIPTION)))
	       (IF (OR (NULL (CDR C))
		       (AND (STRINGP (CADR C)) (NULL (CDDR C))))
		   (RETURN (CAR C))))))
      (IF CONSTRUCTOR
	  (EVAL (CONS CONSTRUCTOR
		      (LOOP FOR (SLOT VALUE) ON (CDR ARGS) BY 'CDDR
			    APPEND `(,(INTERN (SYMBOL-NAME SLOT) PKG-KEYWORD-PACKAGE)
				     ',VALUE))))
	(CERROR ':NO-ACTION NIL 'READ-ERROR-1
		"~S is not a structure type with a standard keyword constructor." (CAR ARGS))
	NIL))))

;;; The following two sharp-sign reader macros allow tagged LISP objects to be read in.
;;; #n=object reads object and assigns the n label to it.  #n# refers that object
;;; (in other words it is EQ to it) later or at a lower level of S-expression.
;;; The variable XR-LABEL-BINDINGS is an alist of a cons: a label (number) and
;;; a list of one element; that element is the LISP object to which the label refers.
;;; (It has to be a list so the binding can be a distinct object that you can RPLACA into.
;;; Also, it means that cdr[assq[tag;.xr-label-bindings.]] be () is if the tag is
;;; defined.

(DEFUN FIND-ANY-THINGS (THINGS TREE)
  (IF (NULL THINGS) ()
    (FIND-ANY-THINGS-1 THINGS TREE)))

(DEFUN FIND-ANY-THINGS-1 (THINGS TREE)
  (IF (NULL TREE) ()
    (IF (CONSP TREE)
	(OR (FIND-ANY-THINGS-1 THINGS (CAR TREE))
	    (FIND-ANY-THINGS-1 THINGS (CDR TREE)))
      (MEMQ TREE THINGS))))			; TREE is an atom

(DEFUN XR-#=-MACRO (STREAM IGNORE &OPTIONAL (LABEL XR-SHARP-ARGUMENT)
		    &AUX LABEL-BINDING THING)
  (COND
    (*READ-SUPPRESS*
     (VALUES))
    ((NOT LABEL)
     (CERROR ':NO-ACTION NIL 'SYS:READ-ERROR-1 "No argument (label number) to #= given."))
    ((ASSQ LABEL XR-LABEL-BINDINGS)
     ; The label is already defined, but we can't tell what it is yet.
     (CERROR ':NO-ACTION NIL 'SYS:READ-ERROR-1
	     "Label ~S already defined in this expression." LABEL))
    (T ; Go for it and BIND
     (PUSH (LIST LABEL (NCONS NIL))		; Allocate a slot
	   XR-LABEL-BINDINGS)
     (LET ((LABEL-BINDING (ASSQ LABEL XR-LABEL-BINDINGS)))
       (IF (NULL LABEL-BINDING)
	   (FERROR 'SYS:READ-ERROR-1 "Internal error in #= after reading in label's value.")
	 ;; The preceding line should never happen.  By writing into the slot
	 ;; will RPLACD, we also cause other places that referred to the label
	 ;; to get the value, too.
	 (SETF (CONTENTS (CDR LABEL-BINDING)) (SETQ THING (INTERNAL-READ STREAM T NIL T)))
	 ;; If THING has no bindings in it, we can make the binding of THING itself instead of
	 ;; a locative
	 (IF (NOT (CONSP THING))
	     ;; Replace locative with object
	     (SETF (CDR LABEL-BINDING) (CONTENTS (CDR LABEL-BINDING)))
	   ;; If there are no bindings as locatives in it
	   ;; Now we examine the list
	   (NSUBST-EQ-SAFE THING (CDR LABEL-BINDING) THING)	; Substitute for `self'
           (SETF (CDR LABEL-BINDING) (CONTENTS (CDR LABEL-BINDING)))
	   ;; Catch the CDR - why does this happen ?
	   (LET ((LAST-CONS (NTHCDR (1- (LENGTH THING)) THING)))
	     (IF (LOCATIVEP (CDR LAST-CONS))
		 (SETF (CDR LAST-CONS) (CONTENTS (CDR LAST-CONS))))))
	 ; Replace locative with object
	 THING)))))


(DEFUN XR-##-MACRO (STREAM IGNORE &OPTIONAL (LABEL XR-SHARP-ARGUMENT))
  (DECLARE (IGNORE STREAM))
  (COND (*READ-SUPPRESS* NIL)
	((NOT LABEL)
	 (CERROR :NO-ACTION NIL 'SYS:READ-ERROR-1 "No argument (label number) to ## given."))
	((WITHOUT-INTERRUPTS
	   (LET ((LABEL-BINDING (ASSQ LABEL XR-LABEL-BINDINGS)))
	     (WHEN LABEL-BINDING
	       (INCF (CADR LABEL-BINDING))
	       LABEL-BINDING))))
	(T (CERROR :NO-ACTION NIL 'SYS:READ-ERROR-1 "The ##-label ~S is undefined." LABEL))))


(DEFUN XR-#.-MACRO (STREAM IGNORE &OPTIONAL IGNORE)
  (VALUES (IF *READ-SUPPRESS*
	      (PROGN (INTERNAL-READ STREAM T NIL T) NIL)
	    (EVAL1 (INTERNAL-READ STREAM T NIL T)))))

(DEFUN XR-#-MACRO (STREAM IGNORE &OPTIONAL ARG)
  (XR-XRTYI STREAM NIL T)			;Skip the / that follows.
  (%MAKE-POINTER DTP-CHARACTER
		 (%LOGDPB (OR ARG 0) %%CH-FONT
			  (XR-#\-MACRO STREAM NIL))))

(DEFUN XR-CL-#\-MACRO (STREAM IGNORE &OPTIONAL ARG)
  (%MAKE-POINTER DTP-CHARACTER
		 (%LOGDPB (OR ARG 0) %%CH-FONT
			  (XR-#\-MACRO STREAM NIL))))

(DEFUN XR-#\-MACRO (STREAM IGNORE &OPTIONAL (BITS XR-SHARP-ARGUMENT))
  (MULTIPLE-VALUE-BIND (NIL NIL CHAR)
      (XR-XRTYI STREAM NIL T)
    (LOGIOR
      (%LOGDPB (OR BITS 0) %%KBD-CONTROL-META 0)
      (IF (NOT (OR ( #/A CHAR #/Z) ( #/a CHAR #/z)))
	  CHAR
	(SEND STREAM ':UNTYI CHAR)
	(PKG-BIND PKG-KEYWORD-PACKAGE
	  (LET ((FROB (INTERNAL-READ STREAM T NIL T)))	;Get symbolic name of character
	    (IF *READ-SUPPRESS* 0			;READ returns NIL in this case; don't bomb.
	      (IF (= (STRING-LENGTH FROB) 1)
		  XR-XRTYI-PREV-CHAR 
		(OR (CDR (ASSQ FROB XR-SPECIAL-CHARACTER-NAMES))
		    (XR-PARSE-KEYBOARD-CHAR FROB)
		    (CERROR ':NO-ACTION NIL 'SYS:READ-ERROR-1
			    "#\~A is not a defined character-name." FROB))))))))))

(DEFMACRO XR-STR-CMP (STRING)
  `(AND (= LEN ,(STRING-LENGTH STRING))
	(%STRING-EQUAL ,STRING 0 STRING 1+PREV-HYPHEN-POS ,(STRING-LENGTH STRING))))

;;; This function is given a symbol whose print-name is expected to look
;;; like Control-Meta-A or Control-Meta-Abort or something.  It should return
;;; NIL if the print-name doesn't look like that, or the character code if
;;; it does.
(DEFUN XR-PARSE-KEYBOARD-CHAR (SYM)
  (WHEN (OR (SYMBOLP SYM) (STRINGP SYM))
    (LET ((STRING (IF (STRINGP SYM) SYM (GET-PNAME SYM)))
	  TOP-FLAG GREEK-FLAG SHIFT-FLAG)
      (LOOP WITH CHAR = 0
	    WITH END = (ARRAY-ACTIVE-LENGTH STRING)
	    WITH TEM = NIL
	    FOR START FIRST 0 THEN (1+ HYPHEN-POS)
	    FOR 1+PREV-HYPHEN-POS = 0 THEN (1+ HYPHEN-POS)
	    FOR HYPHEN-POS = (OR (STRING-SEARCH-CHAR #/- STRING START END) END)
	    DO (LET ((LEN (- HYPHEN-POS 1+PREV-HYPHEN-POS)))
		 (COND ((OR (XR-STR-CMP "CTRL")
			    (XR-STR-CMP "CONTROL"))
			(SETQ CHAR (DPB 1 %%KBD-CONTROL CHAR)))
		       ((XR-STR-CMP "META")
			(SETQ CHAR (DPB 1 %%KBD-META CHAR)))
		       ((XR-STR-CMP "HYPER")
			(SETQ CHAR (%LOGDPB 1 %%KBD-HYPER CHAR)))
		       ((XR-STR-CMP "SUPER")
			(SETQ CHAR (DPB 1 %%KBD-SUPER CHAR)))
		       ((XR-STR-CMP "GREEK")
			(SETQ GREEK-FLAG T))
		       ((XR-STR-CMP "FRONT")
			(SETQ GREEK-FLAG T))
		       ((XR-STR-CMP "TOP")
			(SETQ TOP-FLAG T))
		       ((OR (XR-STR-CMP "SHIFT")
			    (XR-STR-CMP "SH"))
			(SETQ SHIFT-FLAG T))
		       ((= 1+PREV-HYPHEN-POS (1- END))
			(RETURN (GREEKIFY-CHARACTER (CHAR STRING 1+PREV-HYPHEN-POS)
						    GREEK-FLAG TOP-FLAG SHIFT-FLAG
						    CHAR)))
		       ((= 1+PREV-HYPHEN-POS (1- HYPHEN-POS))
			(LET ((TEM (ASSQ (CHAR-UPCASE (CHAR-CODE (CHAR STRING
								       1+PREV-HYPHEN-POS)))
					 '((#/C . %%KBD-CONTROL)
					   (#/M . %%KBD-META)
					   (#/H . %%KBD-HYPER)
					   (#/S . %%KBD-SUPER)))))
			  (IF (NULL TEM)
			      (RETURN NIL)
			    (SETQ CHAR (%LOGDPB 1 (SYMBOL-VALUE (CDR TEM)) CHAR)))))
		       ;; See if we have a name of a special character "Return", "SP" etc.
		       ((SETQ TEM
			      (DOLIST (ELEM XR-SPECIAL-CHARACTER-NAMES)
				(LET ((TARGET (GET-PNAME (CAR ELEM))))
				  (IF (STRING-EQUAL TARGET STRING :START2 1+PREV-HYPHEN-POS)
				      (RETURN (CDR ELEM))))))
			;; Note: combine with LOGIOR rather than DPB, since mouse
			;; characters have the high %%KBD-MOUSE bit on.
			(RETURN (GREEKIFY-CHARACTER TEM GREEK-FLAG
						    TOP-FLAG SHIFT-FLAG
						    CHAR)))
		       (T (RETURN NIL))))))))

;;; Given a character, return the greek or top equivalent of it according to
;;; the specified flags.  If the flags are all NIL, the original character is returned.
(DEFUN GREEKIFY-CHARACTER (START-CHAR GREEK-FLAG TOP-FLAG SHIFT-FLAG
			   &OPTIONAL (METABITS 0))
  (COND ((AND TOP-FLAG GREEK-FLAG) NIL)
	(GREEK-FLAG
	 (LET* ((GREEK-CHAR
		  (DOTIMES (I #o200)
		    (AND (OR (= START-CHAR (AREF KBD-NEW-TABLE 0 I))
			     (= START-CHAR (AREF KBD-NEW-TABLE 1 I)))
			 (IF SHIFT-FLAG
			     (RETURN (AREF KBD-NEW-TABLE 4 I))
			   (RETURN (AREF KBD-NEW-TABLE 3 I)))))))
	   (AND GREEK-CHAR
		(NOT (BIT-TEST (LSH 1 15.) GREEK-CHAR))
		(LOGIOR METABITS GREEK-CHAR))))
	((AND SHIFT-FLAG
	      ( #/A (CHAR-CODE START-CHAR) #/Z))
	 ;; Shift on a letter lowercasifies.
	 (LOGIOR METABITS (CHAR-DOWNCASE START-CHAR)))
	;; Otherwise SHIFT is only allowed with GREEK.
	(SHIFT-FLAG NIL)
	(TOP-FLAG
	 (LET* ((TOP-CHAR
		  (DOTIMES (I #o200)
		    (AND (= START-CHAR (AREF KBD-NEW-TABLE 1 I))
			 (RETURN (AREF KBD-NEW-TABLE 2 I)))
		    (AND (= START-CHAR (AREF KBD-NEW-TABLE 0 I))
			 (RETURN (AREF KBD-NEW-TABLE 2 I))))))
	   (AND TOP-CHAR
		(NOT (BIT-TEST (LSH 1 15.) TOP-CHAR))
		(LOGIOR METABITS TOP-CHAR))))
	(T
	 (LOGIOR METABITS START-CHAR))))

(DEFUN XR-#^-MACRO (STREAM IGNORE &OPTIONAL IGNORE)
  (MULTIPLE-VALUE-BIND (NIL NIL CH)
      (XR-XRTYI STREAM NIL T)
    (DPB 1 %%KBD-CONTROL (CHAR-UPCASE CH))))

(DEFUN XR-#Q-MACRO (STREAM IGNORE &OPTIONAL IGNORE)	;For Lispm, gobble frob.
  (VALUES (INTERNAL-READ STREAM T NIL T)))

(DEFUN XR-#M-MACRO (STREAM IGNORE &OPTIONAL IGNORE)	;For Maclisp.  Flush frob.
  (LET ((*READ-SUPPRESS* T))
    (INTERNAL-READ STREAM T NIL T))
  (VALUES))

(DEFUN XR-#N-MACRO (STREAM IGNORE &OPTIONAL IGNORE)	;For NIL.  Flush frob.
  (LET ((*READ-SUPPRESS* T))
    (INTERNAL-READ STREAM T NIL T))
  (VALUES))

;;; #FOO ... represents an instance of flavor FOO.
;;; The flavor FOO should have a :READ-INSTANCE method, which is called
;;;  with SELF bound to nil, and arguments :READ-INSTANCE, the flavor name, and the stream.
;;; It should return the constructed instance
;;;  with the terminating  as the next character to be read.
;;; Alternatively, the symbol FOO should have a SI:READ-INSTANCE property.
;;; This property overrides the use of the flavor method.
;;; Using a property enables you to put it on any symbol you like,
;;; not necessarily the name of the (or any) flavor.  For example, you can
;;; put it in USER: this way, making it unnecessary to use a package prefix when you print.
(DEFUN XR-#-MACRO (STREAM IGNORE &OPTIONAL IGNORE)
  (IF *READ-SUPPRESS*
      (PROGN (READ-DELIMITED-LIST #/ STREAM T) NIL)
    (LET* ((FLAVOR-NAME
	     (INTERNAL-READ STREAM T NIL T))
	   (INSTANCE
	     (LET ((HANDLER (OR (GET FLAVOR-NAME 'READ-INSTANCE)
				(GET-FLAVOR-HANDLER-FOR FLAVOR-NAME :READ-INSTANCE)))
		   (SELF NIL))
	       (FUNCALL HANDLER :READ-INSTANCE FLAVOR-NAME STREAM)))
	   (CHAR (TYI STREAM)))
      ;; Make sure that the read-instance function read as much as it was supposed to.
      (IF (EQ CHAR #/)
	  INSTANCE
	(SEND STREAM :UNTYI CHAR)
	(CERROR :NO-ACTION NIL 'SYS:READ-ERROR-1
		"Malformatted #~S... encountered during READ." FLAVOR-NAME)))))

(DEFUN XR-#/|-MACRO (STREAM IGNORE &OPTIONAL IGNORE)
  (PROG ((N 0))
	(GO HOME)
     SHARP
	(CASE (SEND STREAM :TYI)
	  (#/# (GO SHARP))
	  (#/| (INCF N))
	  (#// (SEND STREAM :TYI))
	  ((NIL) (GO BARF)))
     HOME
	(CASE (SEND STREAM :TYI)
	  (#/| (GO BAR))
	  (#/# (GO SHARP))
	  (#// (SEND STREAM :TYI)
	       (GO HOME))
	  ((NIL) (GO BARF))
	  (T (GO HOME)))
     BAR
	(CASE (SEND STREAM :TYI)
	  (#/# (IF (ZEROP N) (RETURN)
		 (DECF N)
		 (GO HOME)))
	  (#/| (GO BAR))
	  (#// (SEND STREAM :TYI)
	       (GO HOME))
	  ((NIL) (GO BARF))
	  (T (GO HOME)))
     BARF
	(CERROR :NO-ACTION NIL 'SYS:READ-ERROR-1
		"The end of file was reached while reading a #/| comment.")))

;;;  Read-time conditionalization macros
;;;  <feature-form> ::= <symbol-or-number> | (NOT <feature-form>)
;;;		     | (AND . <feature-forms>) | (OR . <feature-forms>)

;;;  As an example, (AND MACSYMA (OR LISPM AMBER)) is a feature form
;;;  which represents the predicate
;;;  (AND (STATUS FEATURE MACSYMA) (OR (STATUS FEATURE LISPM) (STATUS FEATURE AMBER))).
;;;  The use of these forms in conjuction with the #+ reader macro
;;;  enables the read-time environment to conditionalize the
;;;  reading of forms in a file.

;;;  #+<FEATURE-FORM> <FORM> is read as <FORM> if <FEATURE-FORM> is true,
;;;  i.e. if the predicate associated with <FEATURE-FORM> is non-NIL when
;;;  evaluated in the read-time environment.
;;;  #+<FEATURE-FORM> <FORM> is read as whitespace if <FEATURE-FORM> is false.

;;;  #+LISPM <FORM> makes <FORM> exist if being read by the Lisp Machine.
;;;  #+(OR LISPM LISPM-COMPILER) <FORM> makes <FORM> exist if being
;;;  read either by the Lisp Machine or by QCMP.  This is equivalent
;;;  to #Q <FORM>.  Similarly, #+(AND MACLISP (NOT LISPM-COMPILER)) is
;;;  equivalent to #M.

(DEFUN XR-#+-MACRO (STREAM IGNORE &OPTIONAL IGNORE)
  (LET ((FEATURE (LET ((*PACKAGE* PKG-KEYWORD-PACKAGE)
		       (*READ-BASE* 10.))
		   (INTERNAL-READ STREAM T NIL T))))	;feature or feature list
    (COND (*READ-SUPPRESS*
	   (VALUES))
	  ((NOT (XR-FEATURE-PRESENT FEATURE))
	   (LET ((*READ-SUPPRESS* T))
	     (INTERNAL-READ STREAM T NIL T))
	   (VALUES))
	  (T
	   (VALUES (INTERNAL-READ STREAM T NIL T))))))

;;;  #-<FEATURE-FORM> is equivalent to #+(NOT FEATURE-FORM).

(DEFUN XR-#--MACRO (STREAM IGNORE &OPTIONAL IGNORE)
  (LET ((FEATURE (LET ((*PACKAGE* PKG-KEYWORD-PACKAGE)
		       (*READ-BASE* 10.))
		   (INTERNAL-READ STREAM T NIL T))))	;feature or feature list
    (COND (*READ-SUPPRESS*
	   (VALUES))
	  ((XR-FEATURE-PRESENT FEATURE)
	   (LET ((*READ-SUPPRESS* T))
	     (INTERNAL-READ STREAM T NIL T))
	   (VALUES))
	  (T
	   (VALUES (INTERNAL-READ STREAM T NIL T))))))

;;;  Here, FEATURE is either a symbol to be looked up in (STATUS FEATURES) or
;;;  a list whose car is either AND, OR, or NOT.
;;;  Numbers may also be used--they are always taken to be decimal.
;;;  This is useful since people tend to name computers with numbers for some reason.

(DEFUN XR-FEATURE-PRESENT (FEATURE)
    (COND ((SYMBOLP FEATURE)
	   (MEM #'STRING= FEATURE *FEATURES*))
	  ((NUMBERP FEATURE)
	   (MEMBER FEATURE *FEATURES*))
	  ((ATOM FEATURE)
	   (CERROR ':NO-ACTION NIL 'SYS:READ-ERROR-1
		   "Unknown form ~S in #+ or #- feature list." FEATURE))
	  ((EQ (CAR FEATURE) ':NOT)
	   (NOT (XR-FEATURE-PRESENT (CADR FEATURE))))
	  ((EQ (CAR FEATURE) ':AND)
	   (EVERY (CDR FEATURE) #'XR-FEATURE-PRESENT))
	  ((EQ (CAR FEATURE) ':OR)
	   (SOME (CDR FEATURE) #'XR-FEATURE-PRESENT))
	  (T (CERROR ':NO-ACTION NIL 'SYS:READ-ERROR-1
		     "Unknown form ~S in #+ or #- feature list." FEATURE))))

;;;; Common Lisp syntax-setting functions.

(DEFUN SET-SYNTAX-FROM-CHAR (TO-CHAR FROM-CHAR &OPTIONAL
			     (TO-READTABLE *READTABLE*) (FROM-READTABLE *READTABLE*))
  "Copy the syntax of FROM-CHAR in FROM-READTABLE to TO-CHAR in TO-READTABLE, Common Lisp style.
Common Lisp has a peculiar definition of just what it is about
the character syntax that can be copied, while other aspects
are supposed to be immutable for a particular character.
This function contains hair to copy only the mutable part of the syntax.
To copy all aspects of the syntax, use COPY-SYNTAX."
; character lossage
  (IF (CHARACTERP TO-CHAR) (SETQ TO-CHAR (CHAR-INT TO-CHAR)))
  (IF (CHARACTERP FROM-CHAR) (SETQ FROM-CHAR (CHAR-INT FROM-CHAR)))
  (LET ((BITS (RDTBL-BITS FROM-READTABLE FROM-CHAR))
	(CODE (RDTBL-CODE FROM-READTABLE FROM-CHAR))
	(FROM-AENTRY (ASSQ FROM-CHAR (RDTBL-MACRO-ALIST FROM-READTABLE)))
	(TO-AENTRY (ASSQ TO-CHAR (RDTBL-MACRO-ALIST TO-READTABLE)))
	SYNTAX-STANDARD)
    ;; Find a character which standardly posesses the syntax that is being copied.
    (DOTIMES (I (ARRAY-DIMENSION INITIAL-COMMON-LISP-READTABLE 1))
      (WHEN (AND (= (RDTBL-BITS INITIAL-COMMON-LISP-READTABLE I) BITS)
		 (= (RDTBL-CODE INITIAL-COMMON-LISP-READTABLE I) CODE))
	(SETQ SYNTAX-STANDARD I)))
    ;; Check for Space, Return, etc. set to Constituent syntax.
    (WHEN (AND (NULL SYNTAX-STANDARD)
	       (EQUAL (GET-SYNTAX-BITS FROM-CHAR INITIAL-COMMON-LISP-READTABLE)
		      (GETF (RDTBL-PLIST INITIAL-COMMON-LISP-READTABLE) 'ILLEGAL)))
      (SETQ SYNTAX-STANDARD #/A))
    (COND ((OR (NULL SYNTAX-STANDARD) (EQ SYNTAX-STANDARD #/#))
	   ;; Standardize any kind of nonterminating macro.
	   ;; NIL for SYNTAX-STANDARD must mean that, since that is the only kind of syntax
	   ;; that can get used due to Common Lisp actions
	   ;; which isn't present in the standard Common Lisp readtable.
	   (SETQ SYNTAX-STANDARD (IF (= TO-CHAR #/#) #/# NIL)))
	  ;; Standardize any kind of constituent character to an ordinary one.
	  ((OR (ALPHA-CHAR-P SYNTAX-STANDARD)
	       (MEMQ SYNTAX-STANDARD '(#/+ #/- #/. #// #/: #/^ #/_ #/!)))
	   (IF (OR (ALPHA-CHAR-P TO-CHAR)
		   (MEMQ TO-CHAR '(#/+ #/- #/. #// #/: #/^ #/_)))
	       (SETQ SYNTAX-STANDARD TO-CHAR)
	     (IF (MEMQ TO-CHAR '(#/SPACE #/RETURN #/LF #/TAB #/RUBOUT #/BS #/PAGE))
		 (SETQ SYNTAX-STANDARD 'ILLEGAL)
	       (SETQ SYNTAX-STANDARD #/!)))))
    (IF (NULL SYNTAX-STANDARD)
	(SET-SYNTAX-BITS TO-CHAR (GETF (RDTBL-PLIST INITIAL-COMMON-LISP-READTABLE)
				      'NON-TERMINATING-MACRO)
			 TO-READTABLE)
      (IF (EQ SYNTAX-STANDARD 'ILLEGAL)
	  (SET-SYNTAX-BITS TO-CHAR
			   (GETF (RDTBL-PLIST INITIAL-COMMON-LISP-READTABLE) 'ILLEGAL)
			   TO-READTABLE)
	(SET-SYNTAX-BITS TO-CHAR
			 (GET-SYNTAX-BITS SYNTAX-STANDARD INITIAL-COMMON-LISP-READTABLE)
			 TO-READTABLE)))
    (SETF (RDTBL-MACRO-ALIST TO-READTABLE)
	  (DELQ TO-AENTRY (RDTBL-MACRO-ALIST TO-READTABLE)))
    (IF FROM-AENTRY
	(PUSH (COPY-TREE FROM-AENTRY) (RDTBL-MACRO-ALIST TO-READTABLE)))))

(DEFUN SET-MACRO-CHARACTER (CHAR FUNCTION &OPTIONAL NON-TERMINATING-P
			    (A-READTABLE *READTABLE*))
  "Set the syntax of CHAR in A-READTABLE to be a macro character that invokes FUNCTION.
NON-TERMINATING-P non-NIL means the macro char is recognized only
 at the start of a token; it can appear unquoted in the middle of a symbol.
FUNCTION is passed the input stream and the character that invoked it.
It should return zero or more values, each of which is an object produced
by the macro.  Zero and one are the most common numbers of values.
More than one may not be accepted in certain contexts.

The function can examine the list of input so far at the current level
 through the special variable XR-LIST-SO-FAR.  It can also be
 :TOPLEVEL if not within list, or :AFTER-DOT if after a dot.

A function can also hairily mung the list so far.
To do this, modify XR-LIST-SO-FAR and return the modified list as
 the only value, after setting the special variable XR-SPLICE-P to T."
; character lossage
  (IF (CHARACTERP CHAR) (SETQ CHAR (CHAR-INT CHAR)))
  (LET ((SYNTAX (GETF (RDTBL-PLIST A-READTABLE)
		      (IF NON-TERMINATING-P 'NON-TERMINTING-MACRO 'MACRO))))
    (UNLESS (AND (CONSP SYNTAX)
		 (FIXNUMP (CAR SYNTAX))
		 (FIXNUMP (CDR SYNTAX)))
      (FERROR NIL "No saved syntax found for defining macro characters."))
    (SETF (RDTBL-BITS A-READTABLE CHAR) (CAR SYNTAX))
    (SETF (RDTBL-CODE A-READTABLE CHAR) (CDR SYNTAX))
    (LET ((X (ASSQ CHAR (RDTBL-MACRO-ALIST A-READTABLE))))
      (IF (NULL X)
	  (SETF (RDTBL-MACRO-ALIST A-READTABLE)
		(CONS (LIST CHAR FUNCTION NON-TERMINATING-P) (RDTBL-MACRO-ALIST A-READTABLE)))
	(SETF (CDR X) (LIST FUNCTION NON-TERMINATING-P)))))
  T)

(DEFUN GET-MACRO-CHARACTER (CHAR &OPTIONAL (A-READTABLE *READTABLE*))
  "Return the function called for macro character CHAR in readtable A-READTABLE.
Value is NIL if CHAR is not a macro character.
Second value is non-NIL if CHAR does not terminate symbols."
  (DECLARE (VALUES FUNCTION NON-TERMINATING-P))
;character lossage
  (IF (CHARACTERP CHAR) (SETQ CHAR (CHAR-INT CHAR)))
  (LET* ((AENTRY (ASSQ CHAR (RDTBL-MACRO-ALIST A-READTABLE))))
    (VALUES (CADR AENTRY)
	    (CADDR AENTRY))))

(DEFUN MAKE-DISPATCH-MACRO-CHARACTER (CHAR &OPTIONAL NON-TERMINATING-P
				      (A-READTABLE *READTABLE*))
  "Make CHAR be a dispatch macro character in readtable A-READTABLE.
NON-TERMINATING-P non-NIL means CHAR should not terminate symbols."
  (SET-MACRO-CHARACTER CHAR NIL A-READTABLE NON-TERMINATING-P)
  T)

(DEFUN SET-DISPATCH-MACRO-CHARACTER (DISP-CHAR SUB-CHAR FUNCTION
				     &OPTIONAL (A-READTABLE *READTABLE*))
  "Set the function run by SUB-CHAR when it is seen following DISP-CHAR.
DISP-CHAR must be a dispatch macro character, such as made by MAKE-DISPATCH-MACRO-CHARACTER.
FUNCTION is the function to be run.  It will receive three arguments:
 the input stream, the sub-character dispatched on, and the numeric argument
 that followed the dispatch character (or NIL if no numeric argument)."
;character lossage
  (IF (CHARACTERP DISP-CHAR) (SETQ DISP-CHAR (CHAR-INT DISP-CHAR)))
  (IF (CHARACTERP SUB-CHAR) (SETQ SUB-CHAR (CHAR-INT SUB-CHAR)))
  (LET* ((AENTRY (ASSQ DISP-CHAR (RDTBL-MACRO-ALIST A-READTABLE)))
	 (SUBAENTRY (ASSQ (CHAR-UPCASE SUB-CHAR) (CDDDR AENTRY))))
    (UNLESS AENTRY
      (FERROR NIL "~@C is not a macro character." DISP-CHAR))
    (UNLESS (EQ (CADR AENTRY) 'XR-DISPATCH-MACRO-DRIVER)
      (FERROR NIL "~@C is not a dispatch macro character." DISP-CHAR))
    (IF SUBAENTRY (SETF (CADR SUBAENTRY) FUNCTION)
      (PUSH (LIST (CHAR-UPCASE SUB-CHAR) FUNCTION) (CDDDR AENTRY)))))

(DEFUN GET-DISPATCH-MACRO-CHARACTER (DISP-CHAR SUB-CHAR
				     &OPTIONAL (A-READTABLE *READTABLE*))
  "Return the function run by SUB-CHAR when encountered after DISP-CHAR.
DISP-CHAR must be a dispatch macro character, such as made by MAKE-DISPATCH-MACRO-CHARACTER.
Value is NIL if SUB-CHAR is not defined (as a subcase of DISP-CHAR)."
  (IF (CHARACTERP DISP-CHAR) (SETQ DISP-CHAR (CHAR-INT DISP-CHAR)))
  (IF (CHARACTERP SUB-CHAR) (SETQ SUB-CHAR (CHAR-INT SUB-CHAR)))
  (LET* ((AENTRY (ASSQ DISP-CHAR (RDTBL-MACRO-ALIST A-READTABLE)))
	 (SUBAENTRY (ASSQ (CHAR-UPCASE SUB-CHAR) (CDDDR AENTRY))))
    (UNLESS AENTRY
      (FERROR NIL "~@C is not a macro character." DISP-CHAR))
    (UNLESS (EQ (CADR AENTRY) 'XR-DISPATCH-MACRO-DRIVER)
      (FERROR NIL "~@C is not a dispatch macro character." DISP-CHAR))
    (AND SUBAENTRY
	 (NOT ( #/0 SUB-CHAR #/9))
	 (CADR SUBAENTRY))))

;;; SETSYNTAX etc.
;;; Note: INITIAL-READTABLE is set up by LISP-REINITIALIZE to be the initial
;;; readtable (not a copy, should it be?).

(DEFUN COPY-SYNTAX (TO-CHAR FROM-CHAR &OPTIONAL
		    (TO-READTABLE *READTABLE*) (FROM-READTABLE *READTABLE*))
  "Copy the syntax of FROM-CHAR in FROM-READTABLE to TO-CHAR in TO-READTABLE.
All aspects of the syntax are copied, including macro definition if any.
However, the meaning as a subdispatch of any dispatch macro characters
is not affected; that is recorded separately under those dispatch macros."
; character lossage
  (IF (CHARACTERP TO-CHAR) (SETQ TO-CHAR (CHAR-INT TO-CHAR)))
  (IF (CHARACTERP FROM-CHAR) (SETQ FROM-CHAR (CHAR-INT FROM-CHAR)))
  (LET ((FROM-AENTRY (ASSQ FROM-CHAR (RDTBL-MACRO-ALIST FROM-READTABLE)))
	(TO-AENTRY (ASSQ TO-CHAR (RDTBL-MACRO-ALIST TO-READTABLE))))
    (SET-SYNTAX-BITS TO-CHAR
		     (GET-SYNTAX-BITS FROM-CHAR FROM-READTABLE)
		     TO-READTABLE)
    (SETF (RDTBL-MACRO-ALIST TO-READTABLE)
	  (DELQ TO-AENTRY (RDTBL-MACRO-ALIST TO-READTABLE)))
    (IF FROM-AENTRY
	(PUSH (COPY-TREE FROM-AENTRY) (RDTBL-MACRO-ALIST TO-READTABLE))))
  T)

(DEFUN SET-CHARACTER-TRANSLATION (CHAR VALUE &OPTIONAL (A-READTABLE *READTABLE*))
  "Set CHAR when read with A-READTABLE to translate in to character VALUE."
  (SETF (RDTBL-TRANS A-READTABLE CHAR) VALUE))

(DEFUN SET-SYNTAX-MACRO-CHAR (CHAR FUNCTION &OPTIONAL (A-READTABLE *READTABLE*))
  "Set the syntax of CHAR in A-READTABLE to be a macro character that invokes FUNCTION.
This expects FUNCTION to obey the old conventions for macro character functions
and encapsulates it into a closure that will obey the new conventions.
You should actually convert to using SET-MACRO-CHARACTER with
a function that obeys the new conventions, which are usually easier anyway."
  (SET-MACRO-CHARACTER
    CHAR
    (LET-CLOSED ((MACRO-FUNCTION FUNCTION))
      #'(LAMBDA (STREAM IGNORE)
	  (MULTIPLE-VALUE-BIND (THING NIL SPLICEP)
	      (FUNCALL MACRO-FUNCTION XR-LIST-SO-FAR STREAM)
	    (IF SPLICEP
		(SETQ XR-SPLICE-P T XR-LIST-SO-FAR THING)
	      THING))))
    NIL A-READTABLE)
  CHAR)

(DEFUN SET-SYNTAX-#-MACRO-CHAR (CHAR FUNCTION &OPTIONAL (A-READTABLE *READTABLE*))
  "Set the syntax of # followed by CHAR, in A-READTABLE, to invoke FUNCTION.
This expects FUNCTION to obey the old conventions for macro character functions
and encapsulates it into a closure that will obey the new conventions.
You should actually convert to using SET-DISPATCH-MACRO-CHARACTER with
a function that obeys the new conventions, which are usually easier anyway."
  (SET-DISPATCH-MACRO-CHARACTER
    #/# CHAR
    (LET-CLOSED ((MACRO-FUNCTION FUNCTION))
      #'(LAMBDA (STREAM IGNORE XR-SHARP-ARGUMENT)
	  (MULTIPLE-VALUE-BIND (THING NIL SPLICEP)
	      (FUNCALL MACRO-FUNCTION XR-LIST-SO-FAR STREAM)
	    (IF SPLICEP
		(SETQ XR-SPLICE-P T XR-LIST-SO-FAR THING)
	      THING))))
    A-READTABLE)
  CHAR)

(DEFUN SET-SYNTAX-FROM-DESCRIPTION (CHAR DESCRIPTION &OPTIONAL (A-READTABLE *READTABLE*))
  "Set the syntax of CHAR in A-READTABLE according to DESCRIPTION.
DESCRIPTION is a symbol defined in the readtable, such as SINGLE, SLASH, WHITESPACE."
  (LET ((SYNTAX (GETF (RDTBL-PLIST A-READTABLE) DESCRIPTION)))
    (OR (AND (CONSP SYNTAX)
	     (FIXNUMP (CAR SYNTAX))
	     (FIXNUMP (CDR SYNTAX)))
	(FERROR NIL "No syntax of description: ~A found." DESCRIPTION))
    (SETF (RDTBL-BITS A-READTABLE CHAR) (CAR SYNTAX))
    (SETF (RDTBL-CODE A-READTABLE CHAR) (CDR SYNTAX))))

;;; Retrieves the syntax of a character so you can save it or whatever.
(DEFUN GET-SYNTAX-BITS (CHAR &OPTIONAL (A-READTABLE *READTABLE*))
  (CONS (RDTBL-BITS A-READTABLE CHAR)
	(RDTBL-CODE A-READTABLE CHAR)))

(DEFUN SET-SYNTAX-BITS (CHAR SYNTAX &OPTIONAL (A-READTABLE *READTABLE*))
  (SETF (RDTBL-BITS A-READTABLE CHAR) (CAR SYNTAX))
  (SETF (RDTBL-CODE A-READTABLE CHAR) (CDR SYNTAX)))

;;; Returns a copy of the readtable
;;; or copys the readtable into another readtable (and returns that)
(DEFUN COPY-READTABLE (&OPTIONAL (A-READTABLE *READTABLE*) (ANOTHER-READTABLE NIL))
  "Copy a readtable into another readtable, or make a new readtable.
With two arguments, copies the first into the second.
Otherwise makes a new copy of the first readtable.
The first argument defaults to the current readtable.
If the first argument is explicitly supplied as NIL,
 a copy of the unmodified standard Common Lisp syntax is made.."
  (IF (NULL A-READTABLE) (SETQ A-READTABLE COMMON-LISP-READTABLE))
  (LET ((X (ARRAY-DIMENSION A-READTABLE 0))
	(Y (ARRAY-DIMENSION A-READTABLE 1))
	(L (ARRAY-LEADER-LENGTH A-READTABLE)))
    (LET ((NEW-READTABLE (OR ANOTHER-READTABLE
			     (MAKE-ARRAY (LIST X Y)
					 :TYPE 'ART-16B
					 :LEADER-LENGTH L))))
      (DOTIMES (I X)
	(DOTIMES (J Y)
	  (SETF (AREF NEW-READTABLE I J) (AREF A-READTABLE I J))))
      (DOTIMES (I L)
	(SETF (ARRAY-LEADER NEW-READTABLE I) (ARRAY-LEADER A-READTABLE I)))
      ;; Certain elements of the leader should not be shared.
      (SETF (RDTBL-MACRO-ALIST NEW-READTABLE)
	    (COPYTREE (RDTBL-MACRO-ALIST NEW-READTABLE)))
      (SETF (RDTBL-PLIST NEW-READTABLE)
	    (COPYLIST (RDTBL-PLIST NEW-READTABLE)))
      (AND (NAMED-STRUCTURE-P A-READTABLE)
	   (MAKE-ARRAY-INTO-NAMED-STRUCTURE NEW-READTABLE))
      (SETF (RDTBL-NAMES NEW-READTABLE) NIL)
;      (UNLESS ANOTHER-READTABLE		;old readtable presumably already there
;	(PUSH NEW-READTABLE *ALL-READTABLES*))
      NEW-READTABLE)))

(defun find-readtable-named (name &optional create-p &aux (rdtbl *readtable*))
  "Find or possibly create a readtable named NAME
If there is a readtable which has a name STRING-EQUAL it, we return that readtable.
Otherwise, we may create such a readtable, depending on CREATE-P.
Possible values of CREATE-P:
 NIL or :ERROR means get an error,
 :FIND means return NIL,
 :ASK means ask whether to create a readtable named NAME which is a copy of the current
   readtable, and returns it if so.
 T means create the readtable (a copy of *READTABLE*) and return it."
  (cond ((readtablep name)
	 name)
	((null name) *readtable*)
	(t
	 (setq name (string name))
	 (unless (dolist (r *all-readtables*)
		   (when (sys:member-equalp name (rdtbl-names r))
		     (return (setq rdtbl r))))
	   (ecase create-p
	     (:find nil)
	     (:ask
	      (if (fquery format:yes-or-no-p-options
			  "~&Readtable ~S not found. Create a copy of ~A and name it ~A? "
			  name *readtable* name)
		  (progn (setq rdtbl (copy-readtable))
			 (setf (rdtbl-names rdtbl) (list name)))
		(cerror "Proceed, once you have defined the readtable"
			"Please define a readtable named /"~A/" and then continue." name)
		(find-readtable-named name :error)))
	     ((t)
	      (setq rdtbl (copy-readtable rdtbl))
	      (setf (rdtbl-names rdtbl) (list name)))
	     ((nil :error)
	      (multiple-cerror 'readtable-not-found
			       (:readtable-name name)
			       ("Cannot find a readtable named ~S" name)
		((format nil "Create it, using a copy of ~A" *readtable*)
		 (setq rdtbl (copy-readtable rdtbl))
		 (setf (rdtbl-names rdtbl) (list name)))
		((format nil "Use ~A" rdtbl))
		("Try again to find the readtable"
		 (find-readtable-named name create-p))
		("Supply the name of a different readtable to use"
		 (setq rdtbl (find-readtable-named 
			       (let ((*query-io* *debug-io*))
				 (prompt-and-read :string-trim
						  "Name of readtable to use instead: "))
			       :error))))))
	   (if (rdtbl-names rdtbl)
	       (pushnew rdtbl *all-readtables* :test #'eq)))
	 rdtbl)))

;;; MacLisp compatible (sort of) setsyntax:

(DEFUN SETSYNTAX (CHAR MAGIC MORE-MAGIC)
  "A function of MacLisp compatibility.  Alters the syntax of CHAR in
the current readtable according to MAGIC and MORE-MAGIC.  CHAR can be a
anything accepted by the function CHARACTER.  MAGIC is usually a
keyword.  The following are some of the accepted keywords:

:MACRO    CHAR becomes a macro character.  MORE-MAGIC is the name of a
          function to be invoked when this character is read.  The
          function takes no arguments, may be TYI or READ from
          STANDARD-INPUT and returns an object which is taken as the
          result of the read.

:SPLICING Like :MACRO but the object returned by the macro function is a
          list that is NCONCed into the list being read.  If CHAR is
          read anywhere except inside a list, then it may return (),
          which means it is ignored, or (OBJ) which means that OBJ is
          read. 

:SINGLE   CHAR becomes a self-delimiting single-character symbol.  If
          MORE-MAGIC is a fixnum, CHAr is translated to that character.

NIL       The syntax of CHAR is not changed, but if MORE-MAGIC is a
          fixnum, CHAR is translated to that character.

a symbol  The syntax of the character is changed t be the same as that
          of the character MAGIC in the standard initial readtable.
          MAGIC is converted to a character by taking the first charcter
          of its print name.  If MORE-MAGIC is a fixnum, CHAR is
          translated to that character." 
  ;; Convert MacLisp character object (a symbol) to Lispm character object (a fixnum).
;character lossage
  (SETQ CHAR (CHAR-INT (COERCE CHAR 'CHARACTER)))
  (IF (CHARACTERP MAGIC) (SETQ MAGIC (CHAR-INT MAGIC)))
  (IF (CHARACTERP MORE-MAGIC) (SETQ MORE-MAGIC (CHAR-INT MORE-MAGIC)))
  ;; Keywords being used, so disable package feature.
  (IF (SYMBOLP MAGIC) (SETQ MAGIC (INTERN (SYMBOL-NAME MAGIC) PKG-KEYWORD-PACKAGE)))
  (COND ((EQ MAGIC ':MACRO)
	 ;; MacLisp reader macros get invoked on zero arguments.
	 (SET-SYNTAX-MACRO-CHAR CHAR
				`(LAMBDA (*IGNORED* *STANDARD-INPUT*)
				   (,MORE-MAGIC))))
	((EQ MAGIC ':SPLICING)
	 (LET ((SETSYNTAX-FUNCTION MORE-MAGIC))
	   (DECLARE (SPECIAL SETSYNTAX-FUNCTION))
	   (SET-SYNTAX-MACRO-CHAR CHAR
				  (CLOSURE '(SETSYNTAX-FUNCTION)
					   #'SETSYNTAX-1))))
	((FIXNUMP MAGIC)
	 (FERROR NIL
		 "You cannot give a fixnum syntax to SETSYNTAX (~O)." MAGIC))
	(T
	 (OR (NOT (FIXNUMP MORE-MAGIC))
	     (SET-CHARACTER-TRANSLATION CHAR MORE-MAGIC))
	 (COND ((EQ MAGIC ':SINGLE)
		(SET-SYNTAX-FROM-DESCRIPTION CHAR 'SINGLE))
	       ((NULL MAGIC))
	       (T
		(SET-SYNTAX-FROM-CHAR CHAR (CHARACTER MAGIC))))))
  T)

(DEFUN SETSYNTAX-1 (LIST-SO-FAR *STANDARD-INPUT* &AUX LST)
  (DECLARE (SPECIAL SETSYNTAX-FUNCTION))
  (SETQ LST (FUNCALL SETSYNTAX-FUNCTION))
  (COND ((NULL LST)
	 (VALUES LIST-SO-FAR NIL T))
	((MEMQ LIST-SO-FAR '(:TOPLEVEL :AFTER-DOT))
	 (IF (AND (NOT (ATOM LST))
		  (NULL (CDR LST)))
	     (VALUES (CAR LST) NIL NIL)
	   (FERROR NIL
		   "A SPLICING macro defined with SETSYNTAX attempted to return ~S
 in the context: ~S." LST LIST-SO-FAR)))
	(T
	 (VALUES (NCONC LIST-SO-FAR LST) NIL T))))

;;;; MacLisp compatible (sort of) setsyntax-sharp-macro

(DEFUN SETSYNTAX-SHARP-MACRO (CHAR TYPE FUN &OPTIONAL (RDTBL *READTABLE*))
  "Exists only for MACLISP compatibility.  Use SET-SYNTAX-#-MACRO-CHAR
instead."
  (SETQ CHAR (CHAR-UPCASE (CHAR-INT (COERCE CHAR 'CHARACTER))))
  (AND (SYMBOLP TYPE) (SETQ TYPE (INTERN (SYMBOL-NAME TYPE) PKG-KEYWORD-PACKAGE)))
  (LET ((SETSYNTAX-SHARP-MACRO-FUNCTION FUN)
	(SETSYNTAX-SHARP-MACRO-CHARACTER
	  (CASE TYPE
	    ((:PEEK-MACRO :PEEK-SPLICING) CHAR)
	    ((:MACRO :SPLICING) NIL))))
    (DECLARE (SPECIAL SETSYNTAX-SHARP-MACRO-FUNCTION SETSYNTAX-SHARP-MACRO-CHARACTER))
    (LET ((F (CASE TYPE
	       ((:MACRO :PEEK-MACRO)
		(CLOSURE '(SETSYNTAX-SHARP-MACRO-FUNCTION
			    SETSYNTAX-SHARP-MACRO-CHARACTER)
			 #'SETSYNTAX-SHARP-MACRO-1))
	       ((:SPLICING :PEEK-SPLICING)
		(CLOSURE '(SETSYNTAX-SHARP-MACRO-FUNCTION
			    SETSYNTAX-SHARP-MACRO-CHARACTER)
			 #'SETSYNTAX-SHARP-MACRO-2))
	       (OTHERWISE
		(FERROR NIL
			"SETSYNTAX-SHARP-MACRO never heard of the type ~S." TYPE)))))
      (SET-SYNTAX-#-MACRO-CHAR CHAR F RDTBL)))
  CHAR)

(DEFUN SETSYNTAX-SHARP-MACRO-1 (LIST-SO-FAR *STANDARD-INPUT*)
  (DECLARE (SPECIAL SETSYNTAX-SHARP-MACRO-FUNCTION SETSYNTAX-SHARP-MACRO-CHARACTER)
	   (IGNORE LIST-SO-FAR))
  (OR (NULL SETSYNTAX-SHARP-MACRO-CHARACTER)
      (SEND *STANDARD-INPUT* :UNTYI SETSYNTAX-SHARP-MACRO-CHARACTER))
  (FUNCALL SETSYNTAX-SHARP-MACRO-FUNCTION XR-SHARP-ARGUMENT))

(DEFUN SETSYNTAX-SHARP-MACRO-2 (LIST-SO-FAR *STANDARD-INPUT* &AUX LST)
  (DECLARE (SPECIAL SETSYNTAX-SHARP-MACRO-FUNCTION SETSYNTAX-SHARP-MACRO-CHARACTER))
  (OR (NULL SETSYNTAX-SHARP-MACRO-CHARACTER)
      (SEND *STANDARD-INPUT* :UNTYI SETSYNTAX-SHARP-MACRO-CHARACTER))
  (SETQ LST (FUNCALL SETSYNTAX-SHARP-MACRO-FUNCTION XR-SHARP-ARGUMENT))
  (COND ((NULL LST)
	 (VALUES LIST-SO-FAR NIL T))
	((MEMQ LIST-SO-FAR '(:TOPLEVEL :AFTER-DOT))
	 (IF (AND (NOT (ATOM LST))
		  (NULL (CDR LST)))
	     (VALUES (CAR LST) NIL NIL)
	   (FERROR NIL
		   "A SPLICING sharp macro defined with SETSYNTAX-SHARP-MACRO attempted
  to return ~S in the context: ~S." LST LIST-SO-FAR)))
	(T
	 (VALUES (NCONC LIST-SO-FAR LST) NIL T))))
