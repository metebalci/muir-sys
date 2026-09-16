;;; -*- Mode:LISP; Package:SI; Cold-Load:T; Base:8; Readtable:ZL -*-
;	** (c) Copyright 1980 Massachusetts Institute of Technology **


(DEFVAR *PRINT-LEVEL* NIL
  "If non-NIL, maximum depth for printing list structure.
Any structure nested more deeply that this amount
is replaced by /"#/".")
(DEFVAR PRINLEVEL :UNBOUND
  "If non-NIL, maximum depth for printing list structure.
Any structure nested more deeply that this amount
is replaced by /"#/".")
(FORWARD-VALUE-CELL 'PRINLEVEL '*PRINT-LEVEL*)

(DEFVAR *PRINT-LENGTH* NIL
  "If non-NIL, maximum length of list to print.
Any elements past that many are replaced by /".../".")
(DEFVAR PRINLENGTH :UNBOUND
  "If non-NIL, maximum length of list to print.
Any elements past that many are replaced by /".../".")
(FORWARD-VALUE-CELL 'PRINLENGTH '*PRINT-LENGTH*)

(DEFVAR *STANDARD-OUTPUT* :UNBOUND
  "Default output stream for PRINT and TYO and many other functions.
Normally it is a synonym-stream pointing at *TERMINAL-IO*.")
(DEFVAR STANDARD-OUTPUT :UNBOUND
  "Default output stream for PRINT and TYO and many other functions.
Normally it is a synonym-stream pointing at *TERMINAL-IO*.")
(FORWARD-VALUE-CELL 'STANDARD-OUTPUT '*STANDARD-OUTPUT*)

(DEFVAR *PRINT-BASE* 10.
  "Radix for output of integers and rational numbers.")
(DEFVAR BASE :UNBOUND
  "Radix for output of numbers.")
(FORWARD-VALUE-CELL 'BASE '*PRINT-BASE*)

(DEFVAR *NOPOINT T
  "Non-NIL means do not print a period after decimal fixnums.")

(DEFVAR *PRINT-RADIX* NIL
  "Non-NIL means print a radix specifier when printing an integer.")

(DEFVAR *PRINT-ESCAPE* T
  "Non-NIL means print readably (PRIN1).  NIL means print with no quoting chars (PRINC).")

(DEFVAR *PRINT-PRETTY* NIL
  "Non-NIL means print objects with extra whitespace for clarity.")

(DEFVAR *PRINT-CIRCLE* NIL
  "Non-NIL means try to represent circular structure with #n# and #n= labels when printing.")

(DEFVAR *PRINT-CASE* ':UPCASE
  "Controls case used for printing uppercase letters in symbol pnames.
Value is :UPCASE, :DOWNCASE or :CAPITALIZE.")

(DEFVAR *PRINT-GENSYM* T
  "Non-NIL means print #: before a symbol which claims to be uninterned, such as gensyms.")

(DEFVAR *PRINT-ARRAY* NIL
  "Non-NIL means print arrays so they can be read back in.  NIL means use #< syntax.")

(DEFVAR PRIN1 NIL
  "If non-NIL, specifies a function to be used for printing the values returned by
read-eval-print loops. GRIND-TOP-LEVEL is a useful thing to which to SETQ this.")


(DEFMACRO PRINT-CIRCLE (&BODY BODY)
  `(IF (NOT *PRINT-CIRCLE*)
       (PROGN . ,BODY)
      (LET ((PRINT-LABEL-NUMBER 0)
	    (PRINT-HASH-TABLE NIL))
	(UNWIND-PROTECT
	    (PROGN
	      (SETQ PRINT-HASH-TABLE (GET-PRINT-HASH-TABLE))
	      (CLRHASH PRINT-HASH-TABLE)
	      (PRINT-RECORD-OCCURRENCES OBJECT)
	      . ,BODY)
	  (WHEN PRINT-HASH-TABLE
	    (RETURN-PRINT-HASH-TABLE PRINT-HASH-TABLE))))))

(DEFVAR PRINT-HASH-TABLE :UNBOUND
  "Hash table that records objects printed when *PRINT-CIRCLE*, for detecting shared structure.
Key is the object printed, value is its label number.")

(DEFVAR REUSABLE-PRINT-HASH-TABLE NIL)

;;>> keep these as functions rather than macros in case we try to be a little cleverer
;;>> about throwing away duplicate ht's
(DEFUN GET-PRINT-HASH-TABLE ()
  (OR (DO (OLD)
	  ((%STORE-CONDITIONAL (LOCF REUSABLE-PRINT-HASH-TABLE)
			       (SETQ OLD REUSABLE-PRINT-HASH-TABLE)
			       NIL)
	   OLD))
      (MAKE-HASH-TABLE)))

(DEFUN RETURN-PRINT-HASH-TABLE (HT)
  (SETQ REUSABLE-PRINT-HASH-TABLE HT))

(DEFVAR PRINT-LABEL-NUMBER :UNBOUND)

(DEFVAR PRINT-READABLY NIL
  "Non-NIL means signal SYS:PRINT-NOT-READABLE if attempt is made to print
some object whose printed representation cannot be read back in.")

;;; You will notice that there are no constant strings in the printer.
;;; All the strings come out of a part of the current readtable
;;; called the "printtable".  For example, the character to start a list
;;; comes from (PTTBL-OPEN-PAREN *READTABLE*).
;;; See the file RDDEFS for the definitions and the default contents of these slots.

;;;; Main entries.

;;; These are the external entrypoints which are in the usual documentation.
;;; They are vaguely compatible with Maclisp.

(DEFUN PRINT (OBJECT &OPTIONAL STREAM)
  "Print OBJECT on STREAM with quoting if needed, with a Return before and a Space after."
  (SETQ STREAM (DECODE-PRINT-ARG STREAM))
  (SEND STREAM :TYO (PTTBL-NEWLINE *READTABLE*))
  (LET ((*PRINT-ESCAPE* T))
    (PRINT-CIRCLE
      (PRINT-OBJECT OBJECT 0 STREAM)))
  (SEND STREAM :TYO (PTTBL-SPACE *READTABLE*))
  OBJECT)

(DEFUN PRIN1 (OBJECT &OPTIONAL STREAM)
  "Print OBJECT on STREAM with quoting if needed."
  (LET ((*PRINT-ESCAPE* T))
    (PRINT-CIRCLE
      (PRINT-OBJECT OBJECT 0 (DECODE-PRINT-ARG STREAM))))
  OBJECT)

(DEFUN PPRINT (OBJECT &OPTIONAL STREAM)
  "Print OBJECT on STREAM, with quoting and with extra whitespace to make it look pretty.
Returns zero values."
  (LET ((*PRINT-ESCAPE* T)
	(*PRINT-PRETTY* T))
    (GRIND-TOP-LEVEL OBJECT NIL (DECODE-PRINT-ARG STREAM)))
  (VALUES))

(DEFUN WRITE (OBJECT &KEY &OPTIONAL (STREAM *STANDARD-OUTPUT*)
	      ((:ESCAPE *PRINT-ESCAPE*) *PRINT-ESCAPE*)
	      ((:RADIX *PRINT-RADIX*) *PRINT-RADIX*)
	      ((:BASE *PRINT-BASE*) *PRINT-BASE*)
	      ((:CIRCLE *PRINT-CIRCLE*) *PRINT-CIRCLE*)
	      ((:PRETTY *PRINT-PRETTY*) *PRINT-PRETTY*)
	      ((:LEVEL *PRINT-LEVEL*) *PRINT-LEVEL*)
	      ((:LENGTH *PRINT-LENGTH*) *PRINT-LENGTH*)
	      ((:CASE *PRINT-CASE*) *PRINT-CASE*)
	      ((:GENSYM *PRINT-GENSYM*) *PRINT-GENSYM*)
	      ((:ARRAY *PRINT-ARRAY*) *PRINT-ARRAY*))
  "Print OBJECT on STREAM.  Keyword args control parameters affecting printing.
The argument ESCAPE specifies the value for the flag *PRINT-ESCAPE*, and so on.
For any flags not specified by keyword arguments, the current special binding is used."
  (PRINT-CIRCLE
    (PRINT-OBJECT OBJECT 0 (DECODE-PRINT-ARG STREAM)))
  OBJECT)
  
(DEFUN PRIN1-THEN-SPACE (OBJECT &OPTIONAL STREAM)
  "Print OBJECT on STREAM with quoting if needed, followed by a Space character."
  (SETQ STREAM (DECODE-PRINT-ARG STREAM))
  (LET ((*PRINT-ESCAPE* T))
    (PRINT-CIRCLE
      (PRINT-OBJECT OBJECT 0 STREAM)))
  (SEND STREAM :TYO (PTTBL-SPACE *READTABLE*))
  OBJECT)

(DEFUN PRINC (OBJECT &OPTIONAL STREAM)
  "Print OBJECT with no quoting, on STREAM.
Strings and characters print just their contents with no delimiters or quoting.
Pathnames, editor buffers, host objects, and many other hairy things
 print as their names with no delimiters."
  (LET ((*PRINT-ESCAPE* NIL))
    (PRINT-CIRCLE
      (PRINT-OBJECT OBJECT 0 (DECODE-PRINT-ARG STREAM))))
  OBJECT)

(DEFUN WRITE-TO-STRING (&REST ARGS)
  "Like WRITE but conses up a string to contain the output from printing OBJECT."
  (DECLARE (ARGLIST OBJECT &KEY ESCAPE RADIX BASE CIRCLE PRETTY LEVEL LENGTH CASE
		    		GENSYM ARRAY))
  (FORMAT:OUTPUT NIL (APPLY #'WRITE ARGS)))

(DEFUN PRIN1-TO-STRING (OBJECT)
  "Like PRIN1 but conses up a string to contain the output from printing OBJECT."
  (FORMAT:OUTPUT NIL (PRIN1 OBJECT)))

(DEFUN PRINC-TO-STRING (OBJECT)
  "Like PRINC but conses up a string to contain the output from printing OBJECT."
  (FORMAT:OUTPUT NIL (PRINC OBJECT)))

;;;; Subroutines

;;; Prevent lossage before the definitions of rationalp and complexp are loaded.
(OR (FBOUNDP 'RATIONALP)
    (FSET 'RATIONALP 'FIXNUMP))

(OR (FBOUNDP 'COMPLEXP)
    (FSET 'COMPLEXP '(LAMBDA (IGNORE) NIL)))

(DEFUN PRINT-RECORD-OCCURRENCES (OBJECT)
  (WHEN (AND (%POINTERP OBJECT)
	     (OR (NOT (SYMBOLP OBJECT))
		 (NOT (SYMBOL-PACKAGE OBJECT)))
	     (NOT (SEND PRINT-HASH-TABLE :MODIFY-HASH OBJECT #'(LAMBDA (OBJECT VALUE FOUND-P)
								 OBJECT VALUE
								 FOUND-P))))
    (TYPECASE OBJECT
      (LIST
	(DO ((TAIL OBJECT (CDR TAIL))
	     (FIRST T NIL))
	    ((ATOM TAIL)
	     (WHEN TAIL (PRINT-RECORD-OCCURRENCES TAIL)))
	  (UNLESS FIRST
	    (IF (SEND PRINT-HASH-TABLE :MODIFY-HASH TAIL
		      #'(LAMBDA (OBJECT VALUE FOUND-P)
			  OBJECT VALUE
			  FOUND-P))
		(RETURN)))
	  (PRINT-RECORD-OCCURRENCES (CAR TAIL))))
      (ARRAY
       (LET (TEM)
	 (UNLESS (IF (SETQ TEM (NAMED-STRUCTURE-P OBJECT))
		     (MEMQ :PRINT-SELF (NAMED-STRUCTURE-INVOKE :WHICH-OPERATIONS OBJECT))
		   (NULL *PRINT-ARRAY*))
	   (DOTIMES (I (ARRAY-LENGTH OBJECT))
	     (PRINT-RECORD-OCCURRENCES (AR-1-FORCE OBJECT I)))))))))


;;; This arg is only used to MEMQ for :PRINT or :STRING-OUT,
;;; so eliminate all other elements to make that faster.
(DEFUN WHICH-OPERATIONS-FOR-PRINT (STREAM &AUX TEM)
  (SETQ TEM (SEND STREAM :WHICH-OPERATIONS))
  (IF (MEMQ ':PRINT TEM)
      (IF (MEMQ ':STRING-OUT TEM)
	  '(:PRINT :STRING-OUT)
	  '(:PRINT))
      (IF (MEMQ :STRING-OUT TEM)
	  '(:STRING-OUT)
	  '())))

;;; Main routine, to print any lisp object.
;;; The WHICH-OPERATIONS argument is provided as an efficiency hack.  It also used
;;; by streams that have a :PRINT handler, and recursively call PRINT-OBJECT, to
;;; prevent themselves from being called again (they pass NIL or (:STRING-OUT)).
(DEFUN PRINT-OBJECT (EXP I-PRINDEPTH STREAM
		     &OPTIONAL
		     (WHICH-OPERATIONS (WHICH-OPERATIONS-FOR-PRINT STREAM))
		     &AUX NSS (FASTP (MEMQ :STRING-OUT WHICH-OPERATIONS)))
  (CATCH-CONTINUATION-IF T 'PRINT-OBJECT
      #'(LAMBDA () (FORMAT STREAM "...error printing ")
		(PRINTING-RANDOM-OBJECT (EXP STREAM :TYPE :FASTP FASTP))
		(FORMAT STREAM "..."))
      NIL
    (CONDITION-RESUME '((ERROR) :ABORT-PRINTING T ("Give up trying to print this object.")
			CATCH-ERROR-RESTART-THROW PRINT-OBJECT)
      (OR (AND (MEMQ :PRINT WHICH-OPERATIONS)	;Allow stream to intercept print operation
	       (SEND STREAM :PRINT EXP I-PRINDEPTH *PRINT-ESCAPE*))
	  (AND *PRINT-CIRCLE*
	       (%POINTERP EXP)
	       (OR (NOT (SYMBOLP EXP))
		   (NOT (SYMBOL-PACKAGE EXP)))
	       ;; This is a candidate for circular or shared structure printing.
	       ;; See what the hash table says about the object:
	       ;; NIL - occurs only once.
	       ;; T - occurs more than once, but no occurrences printed yet.
	       ;;  Allocate a label this time and print #label= as prefix.
	       ;; A number - that is the label.  Print only #label#.
	       (CATCH 'LABEL-PRINTED
		 (SEND PRINT-HASH-TABLE :MODIFY-HASH EXP
		       #'(LAMBDA (KEY VALUE KEY-FOUND-P STREAM)
			   KEY KEY-FOUND-P
			   (COND ((NULL VALUE) NIL)
				 ((EQ VALUE T)
				  (LET ((LABEL (INCF PRINT-LABEL-NUMBER))
					(*PRINT-BASE* 10.) (*PRINT-RADIX* NIL) (*NOPOINT T))
				    (SEND STREAM :TYO #/#)
				    (PRINT-FIXNUM LABEL STREAM)
				    (SEND STREAM :TYO #/=)
				    LABEL))
				 (T
				  (LET ((*PRINT-BASE* 10.) (*PRINT-RADIX* NIL) (*NOPOINT T))
				    (SEND STREAM :TYO #/#)
				    (PRINT-FIXNUM VALUE STREAM)
				    (SEND STREAM :TYO #/#)
				    (THROW 'LABEL-PRINTED T)))))
		       STREAM)
		 NIL))
	  (TYPECASE EXP
	    (FIXNUM (PRINT-FIXNUM EXP STREAM))
	    (SYMBOL (PRINT-PNAME-STRING EXP STREAM FASTP))
	    (LIST
	     (IF (AND *PRINT-LEVEL* ( I-PRINDEPTH *PRINT-LEVEL*))
		 (PRINT-RAW-STRING (PTTBL-PRINLEVEL *READTABLE*) STREAM FASTP)
	       (IF *PRINT-PRETTY*
		   (GRIND-TOP-LEVEL EXP NIL STREAM NIL 'DISPLACED NIL)
		 (PRINT-LIST EXP I-PRINDEPTH STREAM WHICH-OPERATIONS))))
	    (STRING
	     (IF ( (ARRAY-ACTIVE-LENGTH EXP) (ARRAY-LENGTH EXP))
		 (PRINT-QUOTED-STRING EXP STREAM FASTP)
	       (PRINT-RANDOM-OBJECT EXP STREAM FASTP I-PRINDEPTH WHICH-OPERATIONS)))
	    (INSTANCE
	      (SEND EXP :PRINT-SELF STREAM I-PRINDEPTH *PRINT-ESCAPE*))
	    (ENTITY
	     (IF (MEMQ :PRINT-SELF (SEND EXP :WHICH-OPERATIONS))
		 (SEND EXP :PRINT-SELF STREAM I-PRINDEPTH *PRINT-ESCAPE*) 
	       (PRINT-RANDOM-OBJECT EXP STREAM FASTP I-PRINDEPTH WHICH-OPERATIONS)))
	    (NAMED-STRUCTURE
	     (IGNORE-ERRORS
	       (SETQ NSS (NAMED-STRUCTURE-P EXP)))
	     (COND ((AND (SYMBOLP NSS)
			 (GET NSS 'NAMED-STRUCTURE-INVOKE)
			 (MEMQ :PRINT-SELF (NAMED-STRUCTURE-INVOKE EXP :WHICH-OPERATIONS)))
		    (NAMED-STRUCTURE-INVOKE :PRINT-SELF EXP STREAM I-PRINDEPTH *PRINT-ESCAPE*))
		   (T				;Named structure that doesn't print itself
		    (PRINT-NAMED-STRUCTURE NSS EXP I-PRINDEPTH STREAM WHICH-OPERATIONS))))
	    (ARRAY
	     (PRINT-ARRAY EXP STREAM FASTP I-PRINDEPTH WHICH-OPERATIONS))
	    (SHORT-FLOAT
	     (PRINT-FLONUM EXP STREAM FASTP T))
	    (SINGLE-FLOAT
	     (PRINT-FLONUM EXP STREAM FASTP NIL))
	    (BIGNUM
	     (PRINT-BIGNUM EXP STREAM FASTP))
	    (RATIONAL
	     (PRINT-RATIONAL EXP STREAM FASTP))
	    (COMPLEX
	     (PRINT-COMPLEX EXP STREAM FASTP))
	    (CHARACTER
	     (PRINT-CHARACTER EXP STREAM FASTP))
	    (NUMBER
	     (PRINT-RAW-STRING (CAR (PTTBL-RANDOM *READTABLE*)) STREAM FASTP)
	     (PRINT-RAW-STRING (SYMBOL-NAME (DATA-TYPE EXP))
			       STREAM
			       FASTP)
	     (SEND STREAM :TYO (PTTBL-SPACE *READTABLE*))
	     (LET ((*PRINT-BASE* 8) (*PRINT-RADIX* NIL))
	       (PRINT-FIXNUM (%POINTER EXP) STREAM))
	     (PRINT-RAW-STRING (CDR (PTTBL-RANDOM *READTABLE*)) STREAM FASTP))
	    (CLOSURE (PRINT-CLOSURE EXP STREAM FASTP))
	    (T
	     ;; Some random type we don't know about
	     (PRINT-RANDOM-OBJECT EXP STREAM FASTP I-PRINDEPTH WHICH-OPERATIONS))))))
   EXP)

(DEFUN PRINT-RANDOM-OBJECT (EXP STREAM FASTP I-PRINDEPTH WHICH-OPERATIONS)
  (PRINTING-RANDOM-OBJECT (EXP STREAM :FASTP FASTP)
    (PRINT-RAW-STRING (STRING (DATA-TYPE EXP))
		      STREAM
		      FASTP)
    (TYPECASE EXP
      ((OR COMPILED-FUNCTION MICROCODE-FUNCTION STACK-GROUP)
       (SEND STREAM :TYO (PTTBL-SPACE *READTABLE*))
       (PRINT-OBJECT (FUNCTION-NAME EXP)
		     I-PRINDEPTH STREAM WHICH-OPERATIONS)))))

;;; Print a list, hacking *print-length* and *print-level*.
(DEFUN PRINT-LIST (EXP I-PRINDEPTH STREAM WHICH-OPERATIONS)
  (SEND STREAM :TYO (PTTBL-OPEN-PAREN *READTABLE*))
  (DO ((I-PRINLENGTH 1 (1+ I-PRINLENGTH))
       (FIRST T NIL))
      ((OR (ATOM EXP)
	   (AND *PRINT-CIRCLE* (NOT FIRST) (SEND PRINT-HASH-TABLE :GET-HASH EXP)))
       (COND ((NOT (NULL EXP))
	      (PRINT-RAW-STRING (PTTBL-CONS-DOT *READTABLE*) STREAM
				(MEMQ :STRING-OUT WHICH-OPERATIONS))
	      (PRINT-OBJECT EXP (1+ I-PRINDEPTH) STREAM WHICH-OPERATIONS)))
       (SEND STREAM :TYO (PTTBL-CLOSE-PAREN *READTABLE*)))
    (OR FIRST (SEND STREAM :TYO (PTTBL-SPACE *READTABLE*)))
    (PRINT-OBJECT (CAR EXP) (1+ I-PRINDEPTH) STREAM WHICH-OPERATIONS)
    (SETQ EXP (CDR EXP))
    (AND *PRINT-LENGTH* ( I-PRINLENGTH *PRINT-LENGTH*)	;One frob gets printed before test.
	 (NOT (ATOM EXP))			;Don't do it uselessly
	 (PROGN (SEND STREAM :TYO (PTTBL-SPACE *READTABLE*))
		(PRINT-RAW-STRING (PTTBL-PRINLENGTH *READTABLE*) STREAM
				  (MEMQ :STRING-OUT WHICH-OPERATIONS))
		(SEND STREAM :TYO (PTTBL-CLOSE-PAREN *READTABLE*))
		(RETURN NIL)))))

(DEFUN PRINT-ARRAY (EXP STREAM FASTP I-PRINDEPTH
		    &OPTIONAL (WHICH-OPERATIONS (WHICH-OPERATIONS-FOR-PRINT STREAM))
		    &AUX (RANK (ARRAY-RANK EXP)))
  (IF *PRINT-ARRAY*
      (IF (AND (= RANK 1)
	       (EQ (ARRAY-TYPE EXP) 'ART-1B))
	  (PRINT-BIT-VECTOR EXP STREAM)
	(IF *PRINT-PRETTY*
	    (GRIND-TOP-LEVEL EXP NIL STREAM NIL 'DISPLACED NIL)
	  (IF (= RANK 1)
	      (PRINT-VECTOR EXP I-PRINDEPTH STREAM WHICH-OPERATIONS)
	      (PRINT-MULTIDIMENSIONAL-ARRAY EXP I-PRINDEPTH STREAM WHICH-OPERATIONS))))
    (PRINTING-RANDOM-OBJECT (EXP STREAM :FASTP FASTP)
      (PRINT-RAW-STRING (SYMBOL-NAME (ARRAY-TYPE EXP)) STREAM FASTP)
      (DOTIMES (I RANK)
	(SEND STREAM :TYO #/-)
	(PRINT-FIXNUM (ARRAY-DIMENSION EXP I) STREAM)))))

(DEFUN PRINT-VECTOR (EXP I-PRINDEPTH STREAM WHICH-OPERATIONS)
  (SEND STREAM :STRING-OUT (CAR (PTTBL-VECTOR *READTABLE*)))
  (DO ((I-PRINLENGTH 0 (1+ I-PRINLENGTH))
       (LENGTH (LENGTH EXP))
       (FIRST T NIL))
      ((= I-PRINLENGTH LENGTH)
       (SEND STREAM :STRING-OUT (CDR (PTTBL-VECTOR *READTABLE*))))
    (OR FIRST (SEND STREAM :TYO (PTTBL-SPACE *READTABLE*)))
    (PRINT-OBJECT (AREF EXP I-PRINLENGTH) (1+ I-PRINDEPTH) STREAM WHICH-OPERATIONS)
    (AND *PRINT-LENGTH* ( I-PRINLENGTH *PRINT-LENGTH*)	;One frob gets printed before test.
	 (PROGN (SEND STREAM :TYO (PTTBL-SPACE *READTABLE*))
		(PRINT-RAW-STRING (PTTBL-PRINLENGTH *READTABLE*) STREAM
				  (MEMQ :STRING-OUT WHICH-OPERATIONS))
		(SEND STREAM :TYO (PTTBL-CLOSE-PAREN *READTABLE*))
		(RETURN NIL)))))

(DEFUN PRINT-BIT-VECTOR (EXP STREAM)
  (SEND STREAM :STRING-OUT (CAR (PTTBL-BIT-VECTOR *READTABLE*)))
  (DOTIMES (I (LENGTH EXP))
    (SEND STREAM :TYO (+ #/0 (AREF EXP I))))
  (SEND STREAM :STRING-OUT (CAR (LAST (PTTBL-BIT-VECTOR *READTABLE*)))))

(DEFUN PRINT-MULTIDIMENSIONAL-ARRAY (EXP I-PRINDEPTH STREAM WHICH-OPERATIONS)
  (DOLIST (ELT (PTTBL-ARRAY *READTABLE*))
    (COND ((STRINGP ELT) (SEND STREAM :STRING-OUT ELT))
	  ((EQ ELT ':RANK)
	   (LET ((*PRINT-BASE* 10.) (*PRINT-RADIX* NIL) (*NOPOINT T))
	     (PRINT-FIXNUM (ARRAY-RANK EXP) STREAM)))
	  ((EQ ELT ':SEQUENCES)
	   (PRINT-ARRAY-CONTENTS EXP 0 0 I-PRINDEPTH STREAM WHICH-OPERATIONS)))))

(DEFVAR ARRAY-CONTENTS-ARRAY NIL)
(DEFUN PRINT-ARRAY-CONTENTS (ARRAY DIMENSION INDEX-SO-FAR I-PRINDEPTH STREAM W-O &AUX TEM)
  (IF (AND *PRINT-LEVEL* ( I-PRINDEPTH *PRINT-LEVEL*))
      (SEND STREAM :STRING-OUT (PTTBL-PRINLEVEL *READTABLE*))
    (IF (ZEROP (ARRAY-RANK ARRAY))
	(PRINT-OBJECT (AREF ARRAY) I-PRINDEPTH STREAM W-O)
      (LET ((INDEX (* INDEX-SO-FAR (ARRAY-DIMENSION ARRAY DIMENSION)))
	    (MODE (CAR (MEMQ (ARRAY-TYPE ARRAY) '(ART-1B ART-STRING ART-FAT-STRING))))
	    (LENGTH (ARRAY-DIMENSION ARRAY DIMENSION))
	    (RANK (ARRAY-RANK ARRAY)))
	(IF (AND MODE (= (1+ DIMENSION) RANK))
	    (LET ((KLUDGE (IF (AND (%STORE-CONDITIONAL (LOCF ARRAY-CONTENTS-ARRAY)
						       (SETQ TEM ARRAY-CONTENTS-ARRAY)
						       NIL)
				   TEM)
			      (SI:CHANGE-INDIRECT-ARRAY TEM MODE LENGTH ARRAY INDEX)
			    (MAKE-ARRAY LENGTH :TYPE MODE :DISPLACED-TO ARRAY
							  :DISPLACED-INDEX-OFFSET INDEX))))
	      (IF (EQ MODE 'ART-1B) (PRINT-BIT-VECTOR KLUDGE STREAM)
		(PRINT-QUOTED-STRING KLUDGE STREAM (MEMQ :STRING-OUT W-O)))
	      (SETQ ARRAY-CONTENTS-ARRAY KLUDGE))	;massachusetts
	  (SEND STREAM :TYO (PTTBL-OPEN-PAREN *READTABLE*))
	  (DOTIMES (I (ARRAY-DIMENSION ARRAY DIMENSION))
	    (OR (ZEROP I) (SEND STREAM :TYO (PTTBL-SPACE *READTABLE*)))
	    (COND ((AND *PRINT-LENGTH* (= I *PRINT-LENGTH*))
		   (SEND STREAM :STRING-OUT (PTTBL-PRINLENGTH *READTABLE*))
		   (RETURN))
		  ((= (1+ DIMENSION) (ARRAY-RANK ARRAY))
		   (PRINT-OBJECT (AR-1-FORCE ARRAY (+ INDEX I))
				 (1+ I-PRINDEPTH) STREAM W-O))
		  ((AND *PRINT-LEVEL*
			( (1+ I-PRINDEPTH) *PRINT-LEVEL*))
		   (SEND STREAM :STRING-OUT (PTTBL-PRINLEVEL *READTABLE*)))
		  (T
		   (PRINT-ARRAY-CONTENTS ARRAY (1+ DIMENSION)
					       (+ INDEX I)
					       (1+ I-PRINDEPTH)
					 STREAM W-O))))
	  (SEND STREAM :TYO (PTTBL-CLOSE-PAREN *READTABLE*)))))))

;;; conses!!
(defun print-named-structure (nss exp i-prindepth stream which-operations)
  (let ((description (get nss 'defstruct-description)))
    (if (not description)
	(printing-random-object (exp stream :type))
      (send stream :string-out "#S")		;use printtable??
      (let ((slot-alist (si:defstruct-description-slot-alist))
	    (l (list nss)))
	;;>> ** CONS **
	(dolist (s slot-alist)
	  (let* ((kwd (intern (symbol-name (car s)) pkg-keyword-package))
		 (fun (si:defstruct-slot-description-ref-macro-name (cdr s)))
		 (init (si:defstruct-slot-description-init-code (cdr s)))
		 (val (eval `(,fun ,exp))))	;Ugh!! watch out for macros!
	    (unless (equal val init)
	      (push kwd l) (push val l))))
	(print-list (nreverse l) i-prindepth stream which-operations)))))

(defun print-closure (closure stream fastp)
  (let ((bindings (closure-bindings closure)))
    (multiple-value-bind (function-name tem)
	(function-name (closure-function closure))
      (printing-random-object (closure stream :type :fastp fastp)
	(when tem
	  (print-object function-name 0 stream fastp)
	  (send stream :tyo #/space))
	(cond ((null bindings)
	       (send stream :tyo #/0))
	      ((null (cdr bindings))
	       (print-raw-string "(Lexical environment)" stream fastp))
	      ((interpreter-environment-closure-p closure)
	       (print-raw-string "(Interpreter)" stream fastp))
	      (t (print-fixnum (truncate (length bindings) 2) stream)))))))

(defun print-character (char stream fastp
			 &aux (*print-base* 10.) (*print-radix* nil) (*nopoint t))

  (declare (ignore fastp))
  (when *print-escape*
    (send stream :string-out (car (pttbl-character *readtable*)))
    (if (not (zerop (char-font char)))
	(prin1 (char-font char) stream))
    (send stream :string-out (cdr (pttbl-character *readtable*))))
  ;;>> ignore printing font of character when *print-escape* is nil for now...
  (let ((bits (char-bits char))
	(code (char-code char)))
    (send stream :string-out
	  (nth bits
	       '("" "c-" "m-" "c-m-"
		 "s-" "c-s-" "m-s-" "c-m-s-"
		 "h-" "c-h-" "m-h-" "c-m-h-"
		 "s-h-" "c-s-h-" "m-s-h-" "c-m-s-h-")))
    (cond ((tv:char-mouse-p char)
	   (send stream :string-out "Mouse-")
	   (send stream :string-out (nth (ldb %%kbd-mouse-button char)
					 '("Left-" "Middle-" "Right-")))
	   (prin1 (1+ (ldb %%kbd-mouse-n-clicks char)) stream))
	  (t
	   (let (chname)
	     (if (or *print-escape*
		     ( bits 0))
		 (setq chname (format:ochar-get-character-name code)))
	     (if chname
		 (send stream :string-out chname)
	       (and *print-escape*
		    ( bits 0)
		    (character-needs-quoting-p code)
		    (send stream :tyo (pttbl-slash *readtable*)))
	       (send stream :tyo code)))))))

;;; Print a fixnum, possibly with negation, decimal point, etc.
(DEFUN PRINT-FIXNUM (X STREAM &AUX TEM)
  (AND *PRINT-RADIX* (NUMBERP *PRINT-BASE*) (NEQ *PRINT-BASE* 10.)
       (CASE *PRINT-BASE*
	 (2 (SEND STREAM :STRING-OUT "#b"))
	 (8 (SEND STREAM :STRING-OUT "#o"))
	 (16. (SEND STREAM :STRING-OUT "#x"))
	 (T (SEND STREAM :TYO #/#)
	    (LET ((*PRINT-BASE* 10.) (*PRINT-RADIX* NIL) (*NOPOINT T) (TEM *READ-BASE*))
	      (PRINT-FIXNUM TEM STREAM))
	    (SEND STREAM :TYO #/r))))
  (IF (MINUSP X)
      (SEND STREAM :TYO (PTTBL-MINUS-SIGN *READTABLE*))
      (SETQ X (- X)))
  (COND ((AND (NUMBERP *PRINT-BASE*)
	      (< 1 *PRINT-BASE* 37.))
	 (PRINT-FIXNUM-1 X *PRINT-BASE* STREAM))
	((AND (SYMBOLP *PRINT-BASE*)
	      (SETQ TEM (GET *PRINT-BASE* 'PRINC-FUNCTION)))
	 (FUNCALL TEM X STREAM))
	(T
	 (FERROR NIL "A *PRINT-BASE* of ~S is meaningless. It has been reset to 10."
		 (PROG1 *PRINT-BASE* (SETQ *PRINT-BASE* 10.)))))
  (WHEN (AND (OR *PRINT-RADIX* (NOT *NOPOINT))
	     (EQ *PRINT-BASE* 10.))
    (SEND STREAM :TYO (PTTBL-DECIMAL-POINT *READTABLE*)))
  X)

(DEFCONST PRINT-FIXNUM-DIGITS "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  "Characters used as digits when printing fixnums (if *PRINT-BASE* is big enough).")
;;; Print the digits of the fixnum.  NUM is MINUS the fixnum to be printed!
(DEFUN PRINT-FIXNUM-1 (NUM RADIX STREAM &AUX TEM)
  (SETQ TEM (TRUNCATE NUM RADIX))
  (OR (ZEROP TEM)
      (PRINT-FIXNUM-1 TEM RADIX STREAM))
  (SEND STREAM :TYO (CHAR PRINT-FIXNUM-DIGITS (- (\ NUM RADIX)))))


(DEFUN PRINT-BIGNUM (BIGNUM STREAM FASTP &AUX TEM)
  FASTP	;ignored, don't care if the stream can string-out fast
  (WHEN (MINUSP BIGNUM)
    (SEND STREAM :TYO (PTTBL-MINUS-SIGN *READTABLE*)))
  (COND ((AND (FIXNUMP *PRINT-BASE*)
	      (< 1 *PRINT-BASE* 36.))
	 (PRINT-BIGNUM-1 BIGNUM *PRINT-BASE* STREAM))
	((AND (SYMBOLP *PRINT-BASE*)
	      (SETQ TEM (GET *PRINT-BASE* 'PRINC-FUNCTION)))
	 (FUNCALL TEM (- BIGNUM) STREAM))
	(T
	 (FERROR NIL "A BASE of ~S is meaningless" *PRINT-BASE*)))
  (WHEN (AND (EQ *PRINT-BASE* 10.) (NOT *NOPOINT))
    (SEND STREAM :TYO (PTTBL-DECIMAL-POINT *READTABLE*)))
  BIGNUM)

;;; Print the digits of a bignum
(DEFUN PRINT-BIGNUM-1 (NUM RADIX STREAM &AUX LENGTH MAX-RADIX DIGITS-PER-Q)
  (SETQ DIGITS-PER-Q (FLOOR %%Q-POINTER (HAULONG RADIX))
	MAX-RADIX (^ RADIX DIGITS-PER-Q)
	NUM (SI:BIGNUM-TO-ARRAY NUM MAX-RADIX)
	LENGTH (ARRAY-LENGTH NUM))
  (DO ((INDEX (1- LENGTH) (1- INDEX))
       (NDIGITS -1 DIGITS-PER-Q))
      ((MINUSP INDEX))
    (PRINT-BIGNUM-PIECE (AREF NUM INDEX) RADIX STREAM NDIGITS))
  (RETURN-ARRAY NUM))

(DEFUN PRINT-BIGNUM-PIECE (PIECE RADIX STREAM NDIGITS)
       (WHEN (OR (> NDIGITS 1) ( PIECE RADIX))
	 (PRINT-BIGNUM-PIECE (TRUNCATE PIECE RADIX) RADIX STREAM (1- NDIGITS)))
       (SEND STREAM :TYO (AREF PRINT-FIXNUM-DIGITS (\ PIECE RADIX))))

;;;; Printing flonums. 

;>> this needs a lot of work -- we are losing bits here!
;>>  (of course, this may be just the lousy floating-point machine representation and ucode)

;;; Note how the same code works for small flonums without consing and
;;; for big flonums with a certain amount of flonum and bignum consing.
;;; This code probably loses accuracy for large exponents.  Needs investigation.

(DEFUN PRINT-FLONUM (X STREAM FASTP SMALL
		     &OPTIONAL MAX-DIGITS (FORCE-E-FORMAT NIL)
		     &AUX EXPT)
  FASTP		;ignored, don't care if the stream can string-out fast
  (COND ((ZEROP X)
	 (SEND STREAM :STRING-OUT "0.0")
	 (IF (NEQ (NULL SMALL)
		  (NEQ *READ-DEFAULT-FLOAT-FORMAT* 'SHORT-FLOAT))
	     (SEND STREAM :STRING-OUT
		   (IF SMALL "s0" "f0"))))
	(T (IF (PLUSP X)
	       (SETQ X (- X))
	     (SEND STREAM :TYO (PTTBL-MINUS-SIGN *READTABLE*)))
	   ;; X is now negative
	   (COND ((OR (> X -1.0s-3) ( X -1.0s7) FORCE-E-FORMAT)
		  ;; Must go to E format.
		  (MULTIPLE-VALUE-SETQ (X EXPT) (SCALE-FLONUM X))
		  ;; X is now positive
		  (LET ((PLACE-MOVED (PRINT-FLONUM-INTERNAL X SMALL STREAM MAX-DIGITS
							    T)))
		    (WHEN PLACE-MOVED (INCF EXPT)))
		  (SEND STREAM :TYO
			(IF (NEQ (NULL SMALL)
				 (NEQ *READ-DEFAULT-FLOAT-FORMAT* 'SHORT-FLOAT))
			    (IF SMALL #/s #/f)
			  #/e))
		  (IF (MINUSP EXPT)
		      (SEND STREAM :TYO (PTTBL-MINUS-SIGN *READTABLE*))
		    (SETQ EXPT (- EXPT)))
		  (PRINT-FIXNUM-1 EXPT 10. STREAM))
		 (T
		  ;; It is in range, don't use E-format.
		  (PRINT-FLONUM-INTERNAL (- X) SMALL STREAM MAX-DIGITS)
		  (IF (NEQ (NULL SMALL)
			   (NEQ *READ-DEFAULT-FLOAT-FORMAT* 'SHORT-FLOAT))
		      (SEND STREAM :STRING-OUT
			    (IF SMALL "s0" "f0"))))))))

;;; Scale a positive flonum so that it is  1.0 and < 10.0
;;; Returns two values, the new flonum and the exponent scaled by,
;;; which is positive if the number was large and negative if it was small.
;;; Tries to minimize loss of precision.  Can lose up to 3 bits of precision
;;; for humongous numbers, but usually loses at most 1 bit.
;;; This still needs more work; perhaps it should do the scaling
;;; in fixed-point double-precision rather than in floating point;
;;; the result is consistently too low when expt is large and negtive.

;;; Note: X is -ve on entry, +ve on exit
(defun scale-flonum (x &aux (short (typep X 'short-float)) tem expt wastoobig)
  (setq expt (truncate (// (float-exponent x) (log 10s0 2s0))))
  (tagbody
      again
	 (if (minusp expt)
	     (setq tem (* x (aref powers-of-10f0-table (- expt))))
	   (setq tem (// x (aref powers-of-10f0-table expt))))
	 (cond ((and ( tem -10s0) (not wastoobig)) (incf expt) (go again))
	       ((> tem -1s0)  (decf expt) (setq wastoobig t) (go again))
	       (t (return-from scale-flonum (values (- (if short (float tem 0s0) tem))
						    expt))))))

;;; Print the mantissa.
;;; X is a positive non-zero flonum, SMALL is T if it's a small-flonum.
;;; Although X's magnitude is constrained to be between 0.1 and 100000.
;;; when called from the normal printer, this code should work for any X
;;; for the benefit of FORMAT.
;;; Note that ASH is the same as LSH except that it works for bignums and
;;; arbitrary amounts of shifting.  It is implemented with multiply and divide.
;;; Documentation in AI:QUUX;RADIX >
;;; Except that the bletcherous E-FORMAT hair in there has been flushed.
;;; It served only to avoid scaling the flonum to between 1 and 10 when
;;; printing in E-format, which this code wasn't using anyway.
;;; The MAX-DIGITS argument allows rounding off to a smaller precision
;;; than the true value.  However, it will only do this after the decimal point.
(DEFUN PRINT-FLONUM-INTERNAL (X SMALL STREAM MAX-DIGITS &OPTIONAL MOVE-DECIMAL-POINT)
  (LET (PLACE-MOVED)
    (MULTIPLE-VALUE-BIND (BUFER DECIMAL-PLACE)
	(FLONUM-TO-STRING X SMALL MAX-DIGITS NIL)
      (WHEN (AND MOVE-DECIMAL-POINT (= DECIMAL-PLACE 2))
	(SETF (AREF BUFER 2) (AREF BUFER 1))
	(SETF (AREF BUFER 1) #/.)
	(IF (= (AREF BUFER (1- (LENGTH BUFER))) #/0)
	    (DECF (FILL-POINTER BUFER)))
	(SETQ PLACE-MOVED T))
      (SEND STREAM :STRING-OUT BUFER)
      (RETURN-ARRAY (PROG1 BUFER (SETQ BUFER NIL)))
      PLACE-MOVED)))

;;; FORMAT also calls this
(DEFUN FLONUM-TO-STRING (FLONUM IGNORE MAX-DIGITS FRACTION-DIGITS &OPTIONAL DROP-LEADING-ZERO)
  "Return a string containing the printed representation of FLONUM.
At most MAX-DIGITS are printed if MAX-DIGITS is non-NIL.
If FRACTION-DIGITS is non-NIL, exactly FRACTION-DIGITS
 digits are printed after the decimal point.  This overrides the effect of MAX-DIGITS.
The second value is the number of digits that preceded the decimal point.
DROP-LEADING-ZERO means print .123 rather than 0.123 ."
  (DECLARE (VALUES BUFFER INTEGER-DIGITS))
  (LET ((EXPONENT (FLONUM-EXPONENT FLONUM))
	(MANTISSA (FLONUM-MANTISSA FLONUM))
	(BAS 10.)
	K M R Q U S DECIMAL-PLACE
	;; BUFFER is needed when MAX-DIGITS is supplied because the rounding
	;; can generate a carry that has to propagate back through the digits.
	(BUFFER (MAKE-STRING 100 :FILL-POINTER 0)))
    (OR MAX-DIGITS (SETQ MAX-DIGITS 1000.))	;Cause no effect.
    ;; Get integer part
    (SETQ R (ASH MANTISSA EXPONENT))
    (SETQ Q R)
    (SETQ M (ASH 1 (1- EXPONENT)))	;Actually 0 in most normal cases.
    ;; Instead of using a pdl, precompute S and K.
    ;; S gets the highest power of BAS <= R, and K is its logarithm.
    (SETQ S 1 K 0 U BAS)
    (DO () ((> U R))
      (SETQ S U U (* U BAS) K (1+ K)))
    (DO-FOREVER
      (SETF (VALUES U R) (TRUNCATE R S))
      (COND ((OR (< R M) (> R (- S M)))
	     (VECTOR-PUSH (+ #/0 (IF ( (* 2 R) S)
					  U
					(1+ U)))
			  BUFFER)
	     (DECF MAX-DIGITS)
	     ;; This is the LEFTFILL routine in the paper.
	     (DOTIMES (I K)
	       (VECTOR-PUSH #/0 BUFFER)
	       (DECF MAX-DIGITS))
	     (RETURN NIL)))
      ;; If number is < 1, and we want all digits as fraction digits,
      ;; optionally omit the usual single leading zero before the decimal point.
      (UNLESS (AND FRACTION-DIGITS
		   DROP-LEADING-ZERO
		   (ZEROP U)
		   (ZEROP (FILL-POINTER BUFFER))
		   (EQ MAX-DIGITS FRACTION-DIGITS))
	(ARRAY-PUSH BUFFER (+ #/0 U)))
      (DECF MAX-DIGITS)
      (DECF K)
      (IF (MINUSP K) (RETURN NIL))
      (SETQ S (TRUNCATE S 10.)))
    (SETQ DECIMAL-PLACE (ARRAY-ACTIVE-LENGTH BUFFER))
    (ARRAY-PUSH BUFFER (PTTBL-DECIMAL-POINT *READTABLE*))
    (IF FRACTION-DIGITS (SETQ MAX-DIGITS FRACTION-DIGITS))
    (IF (OR (NULL MAX-DIGITS) (PLUSP MAX-DIGITS))
	(IF (MINUSP EXPONENT)
	    ;; There is a fraction part.
	    (LET ((Z (- EXPONENT)))
	      ;; R/S is the fraction, M/S is the error tolerance
	      ;; The multiplication by 2 causes initial M to be 1/2 LSB
	      (SETQ R (* (IF ( Z 23.) (LDB Z MANTISSA) ;If fraction bits fit in a fixnum
			     (LOGAND MANTISSA (1- (ASH 1 Z))))
			 2)
		    S (ASH 2 Z)
		    M 1)
	      (DO-FOREVER
		(SETQ R (* R BAS))
		(SETF (VALUES U R) (TRUNCATE R S))
		(SETQ M (* M BAS))
		(AND (OR (< R M) (> R (- S M)) (< MAX-DIGITS 2))
		     (RETURN NIL))
		(ARRAY-PUSH BUFFER (+ U #/0))
		(DECF MAX-DIGITS))
	      (ARRAY-PUSH BUFFER (SETQ Z (+ (IF ( (* 2 R) S) U (1+ U)) #/0)))
	      (COND ((> Z #/9)
		     ;; Oops, propagate carry backward (MAX-DIGITS case)
		     (DO ((I (- (ARRAY-LEADER BUFFER 0) 2) (1- I)))
			 ((MINUSP I))
		       (SETF (AREF BUFFER (1+ I)) #/0)
		      SKIP-DECIMAL
		       (SETQ Z (AREF BUFFER I))
		       (COND ((= Z (PTTBL-DECIMAL-POINT *READTABLE*))
			      (SETQ I (1- I))
			      (GO SKIP-DECIMAL))
			     (( Z #/9)
			      (SETF (AREF BUFFER I) (1+ Z))
			      (RETURN NIL))
			     ((ZEROP I)
			      ;; Double oops, the carry has added a new digit
			      (LET ((LEN (- (ARRAY-LEADER BUFFER 0) 2)))
				(AND (= (AREF BUFFER LEN) (PTTBL-DECIMAL-POINT *READTABLE*))
				     ;;Must have some fraction part
				     (VECTOR-PUSH #/0 BUFFER))
				(DO ((I LEN (1- I)))
				    (( I 0))
				  (SETF (AREF BUFFER (1+ I)) (AREF BUFFER I)))
				(INCF DECIMAL-PLACE))
			      (SETF (AREF BUFFER 1) #/0)
			      (SETF (AREF BUFFER 0) #/1)
			      (RETURN NIL))))
		     ;Now truncate trailing zeros, except for one after the decimal point
		     (LOOP FOR I FROM (1- (ARRAY-ACTIVE-LENGTH BUFFER))
				 DOWNTO (+ DECIMAL-PLACE 2)
			   WHILE (= (AREF BUFFER I) #/0)
			   DO (STORE-ARRAY-LEADER I BUFFER 0)))))
	    ;; There is no fraction part at all.
	    (VECTOR-PUSH #/0 BUFFER)))
    ;; Now add trailing zeros if requested
    (IF (AND FRACTION-DIGITS (PLUSP FRACTION-DIGITS))
	(LOOP REPEAT (- (+ DECIMAL-PLACE FRACTION-DIGITS 1) (ARRAY-ACTIVE-LENGTH BUFFER))
	      DO (VECTOR-PUSH #/0 BUFFER)))
    (VALUES BUFFER DECIMAL-PLACE)))


(defun character-needs-quoting-p (char &optional (rdtbl *readtable*))
  "Returns T if CHAR needs to be quoted to be read in as a symbol using readtable RDTBL."
  (let ((state (rdtbl-starting-state rdtbl))
	(fsm (rdtbl-fsm rdtbl))
	(code (rdtbl-code rdtbl char)))
    (if (or (not (numberp state))		;FSM ran out OR
	    ( char (rdtbl-trans rdtbl char))	;Translated char? then fsm loses
	    (= code (rdtbl-escape-code rdtbl))
	    (= code (rdtbl-multiple-escape-code rdtbl))
	    (= code (rdtbl-character-code-escape-code rdtbl)))
	t
      (setq state (aref fsm state (if (and (numberp *print-base*) (> *print-base* 10.)
					   ( #/A char (+ *print-base* (- #/A 11.))))
				      (cdr (getf (rdtbl-plist rdtbl) 'extended-digit))
				    code)))
      (cond ((not (numberp state))
	     (dolist (l (rdtbl-make-symbol rdtbl) t)
	       (and (eq (car state) (car l))
		    (eq (cdr state) (cdr l))
		    (return nil))))
	    ((not (numberp (setq state (aref fsm state (rdtbl-break-code rdtbl)))))
	     (dolist (l (rdtbl-make-symbol-but-last rdtbl) t)
	       (and (eq (car state) (car l))
		    (eq (cdr state) (cdr l))
		    (return nil))))
	    (t t)))))

;;;The following functions print out strings, in three different ways.

;;;Print out a symbol's print-name.  If slashification is on, try slashify it
;;;so that if read in the right thing will happen.
(DEFUN PRINT-PNAME-STRING (SYMBOL STREAM FASTP &OPTIONAL NO-PACKAGE-PREFIXES
			   &AUX STRING LEN FSMWINS MUST// TEM)
  (DECLARE (SPECIAL XP-STREAM XP-FASTP XR-EXTENDED-IBASE-P))
  ;; Print a package prefix if appropriate.
  (WHEN (AND *PRINT-ESCAPE* (NOT NO-PACKAGE-PREFIXES)
	     (SYMBOLP SYMBOL))
    (COND ((NULL (SYMBOL-PACKAGE SYMBOL))
	   (AND *PRINT-GENSYM*
		(SEND STREAM :STRING-OUT
		      (PTTBL-UNINTERNED-SYMBOL-PREFIX *READTABLE*))))
	  (T
	   (MULTIPLE-VALUE-BIND (PKG-OR-STRING INTERNAL-FLAG)
	       (SI:PKG-PRINTING-PREFIX SYMBOL *PACKAGE*)
	     (MULTIPLE-VALUE-SETQ (PKG-OR-STRING INTERNAL-FLAG SYMBOL)
	       (LET* ((TEM1 (CAR (RASSQ SYMBOL (RDTBL-SYMBOL-SUBSTITUTIONS *READTABLE*))))
		      (TEM2 (UNLESS TEM1
			      (CDR (ASSQ SYMBOL (RDTBL-SYMBOL-SUBSTITUTIONS *READTABLE*)))))
		      POS IF)
		 (COND ((AND TEM1 (MEMBER-EQUAL (MULTIPLE-VALUE-SETQ (POS IF)
						  (SI:PKG-PRINTING-PREFIX TEM1 *PACKAGE*))
						'(NIL "")))
			(VALUES POS IF TEM1))
		       (TEM2 (MULTIPLE-VALUE-SETQ (NIL IF POS)
			       (INTERN TEM2 *PACKAGE*))
			     (VALUES POS (EQ IF ':INTERNAL) TEM2))
		       (T (VALUES PKG-OR-STRING INTERNAL-FLAG SYMBOL)))))
	     (WHEN PKG-OR-STRING
	       (UNLESS (EQUAL PKG-OR-STRING "")
		 (PRINT-PNAME-STRING (IF (STRINGP PKG-OR-STRING) PKG-OR-STRING
				       (PACKAGE-PREFIX-PRINT-NAME PKG-OR-STRING))
				     STREAM FASTP))
	       (SEND STREAM :STRING-OUT
		     (IF (AND (NOT (STRINGP PKG-OR-STRING))
			      *PACKAGE*
			      (ASSOC-EQUAL (PACKAGE-PREFIX-PRINT-NAME PKG-OR-STRING)
					   (DONT-OPTIMIZE (SI:PKG-REFNAME-ALIST PACKAGE))))
			 ;; Use #: to inhibit an interfering local nickname.
			 "#:"
		       (IF INTERNAL-FLAG
			   (PTTBL-PACKAGE-INTERNAL-PREFIX *READTABLE*)
			   (PTTBL-PACKAGE-PREFIX *READTABLE*)))))))))
  (SETQ STRING (STRING SYMBOL))
  (IF (NOT *PRINT-ESCAPE*)
      (CASE *PRINT-CASE*
	(:DOWNCASE (DOTIMES (I (LENGTH STRING))
		     (SEND STREAM :TYO (CHAR-DOWNCASE (CHAR STRING I)))))
	(:CAPITALIZE (DO ((LENGTH (LENGTH STRING)) CHAR PREV-LETTER
			  (I 0 (1+ I)))
			 ((= I LENGTH))
		       (SETQ CHAR (AREF STRING I))
		       (COND ((UPPER-CASE-P CHAR)
			      (SEND STREAM :TYO (IF PREV-LETTER (CHAR-DOWNCASE CHAR) CHAR))
			      (SETQ PREV-LETTER T))
			     ((LOWER-CASE-P CHAR)
			      (SEND STREAM :TYO (IF PREV-LETTER CHAR (CHAR-UPCASE CHAR)))
			      (SETQ PREV-LETTER T))
			     (( #/0 CHAR #/9)
			      (SEND STREAM :TYO CHAR)
			      (SETQ PREV-LETTER T))
			     (T (SEND STREAM :TYO CHAR)
				(SETQ PREV-LETTER NIL)))))
	(T (PRINT-RAW-STRING STRING STREAM FASTP))) 
    (SETQ FSMWINS
	  (AND (PLUSP (SETQ LEN (LENGTH STRING)))
	       (DO ((I 0 (1+ I))
		    (STATE (RDTBL-STARTING-STATE *READTABLE*))
		    (FSM (RDTBL-FSM *READTABLE*))
		    (CHAR)
		    (ESCAPE-CODE (RDTBL-ESCAPE-CODE *READTABLE*))
		    (MULTIPLE-ESCAPE-CODE (RDTBL-MULTIPLE-ESCAPE-CODE *READTABLE*))
		    (CHARACTER-CODE-ESCAPE-CODE (RDTBL-CHARACTER-CODE-ESCAPE-CODE *READTABLE*)))
		   ((= I LEN)
		    (COND ((NOT (NUMBERP STATE))
			   (DOLIST (L (RDTBL-MAKE-SYMBOL *READTABLE*))
			     (AND (EQ (CAR STATE) (CAR L))
				  (EQ (CDR STATE) (CDR L))
				  (RETURN T))))
			  ((NOT (NUMBERP (SETQ STATE
					       (AREF FSM
						     STATE
						     (RDTBL-BREAK-CODE *READTABLE*)))))
			   (DOLIST (L (RDTBL-MAKE-SYMBOL-BUT-LAST *READTABLE*))
			     (AND (EQ (CAR STATE) (CAR L))
				  (EQ (CDR STATE) (CDR L))
				  (RETURN T))))
			  (T NIL)))
		 (SETQ CHAR (AREF STRING I))
		 (COND ((OR (NOT (NUMBERP STATE))	;FSM ran out OR
			    (NOT			;Translated char? then fsm loses
			      (= CHAR (RDTBL-TRANS *READTABLE* CHAR))))
			(OR MUST//			;Must we slash?
			    (DO ((I I (1+ I))) ((= I LEN))
			      (LET ((CODE (RDTBL-CODE *READTABLE* (AREF STRING I))))
				(WHEN (OR (= CODE ESCAPE-CODE)
					  (= CODE MULTIPLE-ESCAPE-CODE)
					  (= CODE CHARACTER-CODE-ESCAPE-CODE))
				  (SETQ MUST// T)
				  (RETURN NIL)))))
			(RETURN NIL)))
		 (SETQ STATE
		       (AREF FSM
			     STATE
			     (COND ((LET ((CODE (RDTBL-CODE *READTABLE* (AREF STRING I))))
				      (OR (= CODE ESCAPE-CODE)
					  (= CODE MULTIPLE-ESCAPE-CODE)
					  (= CODE CHARACTER-CODE-ESCAPE-CODE)))
				    (SETQ MUST// T)
				    (RDTBL-SLASH-CODE *READTABLE*))
				   ((AND (NUMBERP *PRINT-BASE*) (> *PRINT-BASE* 10.)
					 ( #/A CHAR (+ *PRINT-BASE* #/A -11.)))
				    (CDR (GETF (RDTBL-PLIST *READTABLE*) 'EXTENDED-DIGIT)))
				   (T
				    (RDTBL-CODE *READTABLE* CHAR))))))))
    (UNLESS FSMWINS (SEND STREAM :TYO (PTTBL-OPEN-QUOTE-SYMBOL *READTABLE*)))
    (COND ((OR MUST//
	       (AND FSMWINS (NEQ *PRINT-CASE* ':UPCASE)))
	   (DO ((I 0 (1+ I))
		(ESCAPE-CODE (RDTBL-ESCAPE-CODE *READTABLE*))
		(MULTIPLE-ESCAPE-CODE (RDTBL-MULTIPLE-ESCAPE-CODE *READTABLE*))
		(CHARACTER-CODE-ESCAPE-CODE (RDTBL-CHARACTER-CODE-ESCAPE-CODE *READTABLE*))
		(PREV-CHAR 0)
		CODE)
	       ((= I LEN))
	     (SETQ TEM (AREF STRING I))
	     (SETQ CODE (RDTBL-CODE *READTABLE* TEM))
	     (COND ((OR (= CODE ESCAPE-CODE)
			(= CODE MULTIPLE-ESCAPE-CODE)
			(= CODE CHARACTER-CODE-ESCAPE-CODE))
		    (SEND STREAM :TYO (PTTBL-SLASH *READTABLE*))
		    (SEND STREAM :TYO TEM))
		   ((OR (EQ *PRINT-CASE* ':DOWNCASE)
			(AND (EQ *PRINT-CASE* ':CAPITALIZE)
			     (ALPHANUMERICP PREV-CHAR)))
		    (SEND STREAM :TYO (CHAR-DOWNCASE TEM)))
		   (T
		    (SEND STREAM :TYO TEM)))
	     (SETQ PREV-CHAR TEM)))
	  (T (PRINT-RAW-STRING STRING STREAM FASTP)))
    (UNLESS FSMWINS (SEND STREAM :TYO (PTTBL-CLOSE-QUOTE-SYMBOL *READTABLE*)))
    ))

;;; Print a string, and if slashification is on, slashify it appropriately.
(DEFUN PRINT-QUOTED-STRING (STRING STREAM FASTP &AUX LENGTH CHAR)
  (COND ((NOT *PRINT-ESCAPE*)
	 (PRINT-RAW-STRING STRING STREAM FASTP))
	(T
	 (SEND STREAM :TYO (PTTBL-OPEN-QUOTE-STRING *READTABLE*))
	 (SETQ LENGTH (ARRAY-ACTIVE-LENGTH STRING))
	 (COND ((AND (EQ (ARRAY-TYPE STRING) 'ART-STRING)
		     (DOTIMES (I LENGTH T)
		       (AND (< (SETQ CHAR (AREF STRING I)) #o220)
			    (NOT (ZEROP (LOGAND #o16 (RDTBL-BITS *READTABLE* CHAR))))
			    (RETURN NIL))))
		;; There are no double quotes, and so no slashifying.
		(SEND STREAM :STRING-OUT STRING))
	       (T
		(DOTIMES (I LENGTH)
		  (SETQ CHAR (CHAR-CODE (CHAR STRING I)))
		  (COND ((AND (< CHAR #o220)
			      (NOT (ZEROP (LOGAND #o16 (RDTBL-BITS *READTABLE* CHAR)))))
			 (SEND STREAM :TYO (PTTBL-SLASH *READTABLE*))))
		    (SEND STREAM :TYO CHAR))))
	 (SEND STREAM :TYO (PTTBL-CLOSE-QUOTE-STRING *READTABLE*))
	 )))

;;; Print the string, with no slashification at all.
(DEFUN PRINT-RAW-STRING (STRING STREAM FASTP)
  (COND ((AND FASTP (EQ (ARRAY-TYPE STRING) 'ART-STRING))
	 (SEND STREAM :STRING-OUT STRING))
	(T
	 (DOTIMES (I (LENGTH STRING))
	   (SEND STREAM :TYO (CHAR-CODE (AREF STRING I)))))))

(DEFPROP PRINT-NOT-READABLE T :ERROR-REPORTER)

(DEFUN PRINT-NOT-READABLE (EXP)
  (LET ((PRINT-READABLY NIL))
    (CERROR ':NO-ACTION NIL 'SYS:PRINT-NOT-READABLE "Can't print ~S readably." EXP)))

