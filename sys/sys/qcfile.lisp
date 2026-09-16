;;; -*- Mode:LISP; Package:COMPILER; Readtable:T; Base:8 -*-
;;; This SYS: SYS; QCFILE
;;;
;;;	** (c) Copyright 1980, 1984 Massachusetts Institute of Technology **

;;; Compile a LISP source file into a QFASL file.

(DEFVAR QC-FILE-LOAD-FLAG :UNBOUND
  "Holds an arg to QC-FILE which enables a feature that has bugs.
Make the arg NIL.")

(DEFVAR QC-FILE-IN-CORE-FLAG :UNBOUND
  "Holds an argument to QC-FILE which, if non-NIL, causes fasl-updating instead of compilation.")

(DEFVAR QC-FILE-IN-PROGRESS NIL
  "T while inside COMPILE-STREAM.")

(DEFVAR QC-FILE-READ-IN-PROGRESS NIL
  "T while inside READ within COMPILE-STREAM.")

(DEFCONST QC-FILE-WHACK-THRESHOLD #o40000
  "Generate a new whack in the output QFASL file when fasl table gets this big.")

(DEFVAR QC-FILE-REL-FORMAT NIL
  "T means COMPILE-STREAM writes a REL file.
If QC-FILE-REL-FORMAT-OVERRIDE is NIL (as it initially is),
 the file's attribute list can override this variable.
If the :FASL file attribute's value is :REL, a REL file is made.
If the value is :FASL, a QFASL file is made.
If there is no :FASL attribute, the global value of this variable decides.")

(DEFVAR QC-FILE-RECORD-MACROS-EXPANDED NIL
  "T if within QC-FILE; tells compiler to record macros expanded on QC-FILE-MACROS-EXPANDED.")

(DEFVAR QC-FILE-MACROS-EXPANDED :UNBOUND
  "Within QC-FILE, a list of all macros expanded.
The elements are macro names or lists (macro-name sxhash).")

(DEFCONST QC-FILE-CHECK-INDENTATION T
  "T => check the indentation of input expressions to detect missing closeparens.")

(DEFVAR QC-FILE-REL-FORMAT-OVERRIDE NIL
  "T means ignore the :FASL attribute in the file's attribute list.
The global value of QC-FILE-REL-FORMAT controls the output file format.")

(DEFVAR QC-FILE-FILE-GROUP-SYMBOL :UNBOUND
  "Within COMPILE-STREAM, holds the generic-pathname of the input file.")

;;; The package we compiled in is left here by COMPILE-STREAM.
;;; But that doesn't appear to be true now??
(DEFVAR QC-FILE-PACKAGE)

(DEFUN QC-FILE-LOAD (&REST QC-FILE-ARGS)
  "Compile a file and then load the binary file."
  (LOAD (APPLY #'QC-FILE QC-FILE-ARGS)))

(ADD-INITIALIZATION "QC-FILE warm boot" '(QC-FILE-RESET) '(:WARM))

;;; Call this function if the machine bombs out inside a QC-FILE.
;;; We do merely what stack unwinding ought to do.
(DEFUN QC-FILE-RESET ()
  (SETQ QC-FILE-IN-PROGRESS NIL)
  (SETQ UNDO-DECLARATIONS-FLAG NIL)
  (SETQ QC-FILE-READ-IN-PROGRESS NIL)
  (SETQ LOCAL-DECLARATIONS NIL)
  (SETQ FILE-SPECIAL-LIST NIL
	FILE-UNSPECIAL-LIST NIL)
  (SETQ FILE-LOCAL-DECLARATIONS NIL))

;;; Compile a source file, producing a QFASL file in the binary format.
;;; If QC-FILE-LOAD-FLAG is T, the stuff in the source file is left defined
;;; as well as written into the QFASL file.  If QC-FILE-IN-CORE-FLAG is T,
;;; then rather than recompiling anything, the definitions currently in core
;;; are written out into the QFASL file.

;;; While a QC-FILE is in progress the default CONS area is sometimes QCOMPILE-TEMPORARY-AREA,
;;; which will be flushed by the end of the next FASL-WHACK.  Note this can happen
;;; in the middle of single QC-FILE, (between function boundaries).
;;; **no** by the end of the QC-FILE or by the start of another.
;;; Therefore, if a breakpoint occurs during a QC-FILE, you must call (QC-FILE-RESET).
;;; This also clears out QC-FILE-IN-PROGRESS, which is T while a QC-FILE is being done.

;;; Note that macros and specials are put on LOCAL-DECLARATIONS to make them temporary.
;;; They are also sent over into the QFASL file.

(DEFUN FASD-UPDATE-FILE (INFILE &OPTIONAL OUTFILE)
  (QC-FILE INFILE OUTFILE NIL T))

;;; This function does all the "outer loop" of the compiler.  It is called
;;; by the editor as well as the compiler.
;;; INPUT-STREAM is what to compile.  GENERIC-PATHNAME is for the corresponding file.
;;; FASD-FLAG is NIL if not making a QFASL file.
;;; PROCESS-FN is called on each form.
;;; QC-FILE-LOAD-FLAG, QC-FILE-IN-CORE-FLAG, and PACKAGE-SPEC are options.
;;; FILE-LOCAL-DECLARATIONS is normally initialized to NIL,
;;; but you can optionally pass in an initializations for it.
;;; READ-THEN-PROCESS-FLAG means do all reading first, thus minimizing thrashing.

(DEFUN COMPILE-STREAM (INPUT-STREAM GENERIC-PATHNAME FASD-FLAG PROCESS-FN
		       QC-FILE-LOAD-FLAG QC-FILE-IN-CORE-FLAG PACKAGE-SPEC
		       &OPTIONAL (FILE-LOCAL-DECLARATIONS NIL) IGNORE
		                 COMPILING-WHOLE-FILE-P
		       &AUX (*PACKAGE* *PACKAGE*)
		            (*READ-BASE* *READ-BASE*) (*PRINT-BASE* *PRINT-BASE*)
			    FILE-SPECIAL-LIST FILE-UNSPECIAL-LIST
			    FDEFINE-FILE-PATHNAME
			    (READ-FUNCTION (IF QC-FILE-CHECK-INDENTATION
					       'READ-CHECK-INDENTATION
					       'READ)))
  "This function does all the /"outer loop/" of the compiler, for file and editor compilation.
 to be compiled are read from INPUT-STREAM.
The caller is responsible for handling any file attributes.
GENERIC-PATHNAME is the file to record information for and use the attributes of.
 It may be NIL if compiling to core.
FASD-FLAG is NIL if not making a QFASL file.
PROCESS-FN is called on each form.
QC-FILE-LOAD-FLAG, QC-FILE-IN-CORE-FLAG, and PACKAGE-SPEC are options.
FILE-LOCAL-DECLARATIONS is normally initialized to NIL,
but you can optionally pass in an initializations for it.
COMPILING-WHOLE-FILE-P should be T if you are processing all of the file."
  (FILE-OPERATION-WITH-WARNINGS (GENERIC-PATHNAME ':COMPILE COMPILING-WHOLE-FILE-P)
   (COMPILER-WARNINGS-CONTEXT-BIND
     ;; Override the package if required.  It has been bound in any case.
     (AND PACKAGE-SPEC (SETQ *PACKAGE* (PKG-FIND-PACKAGE PACKAGE-SPEC)))
     ;; Override the generic pathname
     (SETQ FDEFINE-FILE-PATHNAME
	   (LET ((PATHNAME (SEND INPUT-STREAM :SEND-IF-HANDLES :PATHNAME)))
	     (AND PATHNAME (SEND PATHNAME :GENERIC-PATHNAME))))
     ;; Having bound the variables, process the file.
     (LET ((QC-FILE-IN-PROGRESS T)
	   (UNDO-DECLARATIONS-FLAG (NOT QC-FILE-LOAD-FLAG))
	   (LOCAL-DECLARATIONS NIL)
	   (OPEN-CODE-MAP-SWITCH OPEN-CODE-MAP-SWITCH)
	   (RUN-IN-MACLISP-SWITCH RUN-IN-MACLISP-SWITCH)
	   (OBSOLETE-FUNCTION-WARNING-SWITCH OBSOLETE-FUNCTION-WARNING-SWITCH)
	   (ALL-SPECIAL-SWITCH ALL-SPECIAL-SWITCH)
	   (SOURCE-FILE-UNIQUE-ID)
	   (FASD-PACKAGE NIL))
       (WHEN FASD-FLAG
	 ;; Copy all suitable file properties into the fasl file
	 ;; Suitable means those that are lambda-bound when you read in a file.
	 (LET ((PLIST (COPY-LIST (SEND GENERIC-PATHNAME :PLIST))))
	   ;; Remove unsuitable properties
	   (DO ((L (LOCF PLIST)))
	       ((NULL (CDR L)))
	     (IF (NOT (NULL (GET (CADR L) 'FS:FILE-ATTRIBUTE-BINDINGS)))
		 (SETQ L (CDDR L))
	       (SETF (CDR L) (CDDDR L))))
	   ;; Make sure the package property is really the package compiled in
	   ;; Must load QFASL file into same package compiled in
	   ;; On the other hand, if we did not override it
	   ;; and the attribute list has a list for the package, write that list.
	   (UNLESS (AND (NOT (ATOM (GETF PLIST ':PACKAGE)))
			(STRING= (PACKAGE-NAME *PACKAGE*)
				 (CAR (GETF PLIST ':PACKAGE))))
	     (SETF (GETF PLIST ':PACKAGE)
		   (INTERN (PACKAGE-NAME *PACKAGE*) SI:PKG-KEYWORD-PACKAGE)))
	   (AND INPUT-STREAM
		(SEND INPUT-STREAM :OPERATION-HANDLED-P :TRUENAME)
		(SETQ SOURCE-FILE-UNIQUE-ID (SEND INPUT-STREAM :TRUENAME))
		(SETF (GETF PLIST ':QFASL-SOURCE-FILE-UNIQUE-ID) SOURCE-FILE-UNIQUE-ID))
	   ;; If a file is being compiled across directories, remember where the
	   ;; source really came from.
	   (AND FDEFINE-FILE-PATHNAME FASD-STREAM
		(LET ((OUTFILE (SEND FASD-STREAM :SEND-IF-HANDLES :PATHNAME)))
		  (WHEN OUTFILE
		    (SETQ OUTFILE (SEND OUTFILE :GENERIC-PATHNAME))
		    (AND (NEQ OUTFILE FDEFINE-FILE-PATHNAME)
			 (SETF (GETF PLIST ':SOURCE-FILE-GENERIC-PATHNAME)
			       FDEFINE-FILE-PATHNAME)))))
	   (MULTIPLE-VALUE-BIND (MAJOR MINOR)
	       (SI:GET-SYSTEM-VERSION "System")
	     (SETF (GETF PLIST ':COMPILE-DATA)
		   `(,USER-ID
		     ,SI:LOCAL-PRETTY-HOST-NAME
		     ,(TIME:GET-UNIVERSAL-TIME)
		     ,MAJOR ,MINOR
		     (NEW-DESTINATIONS T	; NOT :new-destinations!!
		      :SITE ,SI:SITE-NAME))))
	   ;; First thing in QFASL file must be property list
	   ;; These properties wind up on the GENERIC-PATHNAME.
	   (COND (QC-FILE-REL-FORMAT
		  (QFASL-REL::DUMP-FILE-PROPERTY-LIST
		    GENERIC-PATHNAME
		    PLIST))
		 (T
		  (FASD-FILE-PROPERTY-LIST PLIST)))))
       (QC-PROCESS-INITIALIZE)
       (DO ((EOF (NCONS NIL))
	    (FORM))
	   (())
	 ;; Detect EOF by peeking ahead, and also get an error now
	 ;; if the stream is wedged.  We really want to get an error
	 ;; in that case, not make a warning.
	 (LET ((CH (SEND INPUT-STREAM :TYI)))
	   (OR CH (RETURN))
	   (SEND INPUT-STREAM :UNTYI CH))
	 (SETQ SI::PREMATURE-WARNINGS
	       (APPEND SI::PREMATURE-WARNINGS SI::PREMATURE-WARNINGS-THIS-OBJECT))
	 (LET ((SI::PREMATURE-WARNINGS NIL))
	   (SETQ FORM
		 (LET ((READ-AREA (IF QC-FILE-LOAD-FLAG DEFAULT-CONS-AREA
				    QCOMPILE-TEMPORARY-AREA))
		       (WARN-ON-ERRORS-STREAM INPUT-STREAM)
		       (QC-FILE-READ-IN-PROGRESS FASD-FLAG))	;looked at by XR-#,-MACRO
		   (WARN-ON-ERRORS ('READ-ERROR "Error in reading")
		     (FUNCALL READ-FUNCTION INPUT-STREAM EOF))))
	   (SETQ SI::PREMATURE-WARNINGS-THIS-OBJECT SI::PREMATURE-WARNINGS))
	 (AND (EQ FORM EOF) (RETURN))
	 ;; Start a new whack if FASD-TABLE is getting too big.
	 (AND FASD-FLAG
	      ( (FASD-TABLE-LENGTH) QC-FILE-WHACK-THRESHOLD)
	      (FASD-END-WHACK))
	 (WHEN (AND (ATOM FORM) FASD-FLAG)
	   (WARN 'ATOM-AT-TOP-LEVEL ':IMPLAUSIBLE
		 "The atom ~S appeared at top level; this would do nothing at FASLOAD time."
		 FORM))
	 (FUNCALL PROCESS-FN FORM))))))

(DEFUN PRINT-FUNCTIONS-REFERENCED-BUT-NOT-DEFINED ()
  "Record and print warnings about any functions referenced in compilation but not defined."
  ;; Discard any functions that have since become defined.
  (SETQ FUNCTIONS-REFERENCED
	(DEL-IF #'(LAMBDA (X) (COMPILATION-DEFINEDP (CAR X)))
		FUNCTIONS-REFERENCED))
  ;; Record warnings about the callers, saying that they called an undefined function.
  (DOLIST (FREF FUNCTIONS-REFERENCED)
    (DOLIST (CALLER (CDR FREF))
      (OBJECT-OPERATION-WITH-WARNINGS (CALLER NIL T)
	(RECORD-WARNING 'UNDEFINED-FUNCTION-USED :PROBABLE-ERROR NIL
			"The undefined function ~S was called"
			(CAR FREF)))))
  ;; Now print messages describing the undefined functions used.
  (WHEN FUNCTIONS-REFERENCED
    (FORMAT *ERROR-OUTPUT*
	    "~&The following functions were referenced but don't seem defined:")
    (IF (SEND *ERROR-OUTPUT* :OPERATION-HANDLED-P :ITEM)
	(DOLIST (X FUNCTIONS-REFERENCED)
	  (FORMAT *ERROR-OUTPUT* "~& ~S referenced by " (CAR X))
	  (DO ((L (CDR X) (CDR L))
	       (LINEL (OR (SEND *ERROR-OUTPUT* :SEND-IF-HANDLES :SIZE-IN-CHARACTERS)
			  95.)))
	      ((NULL L))
	    (IF (> (+ (SEND *ERROR-OUTPUT* :READ-CURSORPOS :CHARACTER)
		      (FLATSIZE (CAR L))
		      3)
		   LINEL)
		(FORMAT *ERROR-OUTPUT* "~%  "))
	    (SEND *ERROR-OUTPUT* :ITEM 'ZWEI::FUNCTION-NAME (CAR L)
		  "~S" (CAR L))
	    (AND (CDR L) (PRINC ", " *ERROR-OUTPUT*)))
	  (FORMAT *ERROR-OUTPUT* "~&"))
      (DOLIST (X FUNCTIONS-REFERENCED)
	(FORMAT *ERROR-OUTPUT* "~& ~S referenced by " (CAR X))
	(FORMAT:PRINT-LIST *ERROR-OUTPUT* "~S" (CDR X))
	(FRESH-LINE *ERROR-OUTPUT*)))))

(DEFUN COMPILE-FILE (&OPTIONAL INPUT-FILENAME
		     &KEY OUTPUT-FILENAME
		     (SET-DEFAULT-PATHNAME T)
		     ((:PACKAGE PACKAGE-SPEC)) LOAD)
  "Compile file INPUT-FILE to a QFASL file named OUTPUT-FILE.
OUTPUT-FILE defaults based on INPUT-FILE, which defaults using the standard defaults.
SET-DEFAULT-PATHNAME if NIL means do not set the defaults.
PACKAGE if non-NIL is the package to compile in.
LOAD means to load the compiled file."
  (QC-FILE (OR INPUT-FILENAME "") OUTPUT-FILENAME
	   LOAD NIL PACKAGE-SPEC NIL
	   (NOT SET-DEFAULT-PATHNAME)))

(DEFUN QC-FILE (INFILE &OPTIONAL OUTFILE LOAD-FLAG IN-CORE-FLAG PACKAGE-SPEC
				 FILE-LOCAL-DECLARATIONS
				 DONT-SET-DEFAULT-P
				 READ-THEN-PROCESS-FLAG
		       &AUX GENERIC-PATHNAME QC-FILE-PACKAGE
			    QC-FILE-MACROS-EXPANDED
			    (QC-FILE-RECORD-MACROS-EXPANDED T)
			    (QC-FILE-REL-FORMAT QC-FILE-REL-FORMAT))
  "Compile Lisp source file INFILE, producing a binary file and calling it OUTFILE.
PACKAGE-SPEC specifies which package to read the source in
 (usually the file's attribute list provides the right default).
LOAD-FLAG and IN-CORE-FLAG are semi-losing features; leave them NIL.
READ-THEN-PROCESS-FLAG says read the entire file before compiling (less thrashing)."
  ;; Default the specified input and output file names.  Open files.
  (SETQ INFILE (FS:MERGE-PATHNAME-DEFAULTS INFILE FS:LOAD-PATHNAME-DEFAULTS NIL))
  (WITH-OPEN-STREAM (INPUT-STREAM
		      (FILE-RETRY-NEW-PATHNAME (INFILE FS:FILE-ERROR)
			(SEND INFILE :OPEN-CANONICAL-DEFAULT-TYPE :LISP)))
    ;; The input pathname might have been changed by the user in response to an error.
    ;; Also, find out what type field was actually found.
    (SETQ INFILE (SEND INPUT-STREAM :PATHNAME))
    (OR DONT-SET-DEFAULT-P (FS:SET-DEFAULT-PATHNAME INFILE FS:LOAD-PATHNAME-DEFAULTS))
    (SETQ GENERIC-PATHNAME (SEND INFILE :GENERIC-PATHNAME))
    (SETQ OUTFILE
	  (COND ((TYPEP OUTFILE 'PATHNAME)
		 (IF (SEND OUTFILE :VERSION)
		     OUTFILE
		   (SEND OUTFILE :NEW-PATHNAME
			 	 :VERSION (SEND (SEND INPUT-STREAM :TRUENAME) :VERSION))))
		(OUTFILE
		 (FS:MERGE-PATHNAME-DEFAULTS
		   OUTFILE INFILE (SI:PATHNAME-DEFAULT-BINARY-FILE-TYPE GENERIC-PATHNAME)
		   (SEND (SEND INPUT-STREAM :TRUENAME) :VERSION)))
		(T
		 (SEND INFILE :NEW-PATHNAME
		       	      :TYPE (SI:PATHNAME-DEFAULT-BINARY-FILE-TYPE GENERIC-PATHNAME)
			      :VERSION (SEND (SEND INPUT-STREAM :TRUENAME) :VERSION)))))
    ;; Get the file property list again, in case we don't have it already or it changed
    (FS:READ-ATTRIBUTE-LIST GENERIC-PATHNAME INPUT-STREAM)
    (OR QC-FILE-REL-FORMAT-OVERRIDE
	(CASE (SEND GENERIC-PATHNAME :GET :FASL)
	  (:REL (SETQ QC-FILE-REL-FORMAT T))
	  (:FASL (SETQ QC-FILE-REL-FORMAT NIL))
	  (NIL)
	  (T (FERROR NIL "File property FASL value not FASL or REL in file ~A"
		     GENERIC-PATHNAME))))
    ;; Bind all the variables required by the file property list.
    (MULTIPLE-VALUE-BIND (VARS VALS) (FS:FILE-ATTRIBUTE-BINDINGS GENERIC-PATHNAME)
      (PROGV VARS VALS
	(COND (QC-FILE-REL-FORMAT
	       (LET ((FASD-STREAM NIL))	;REL compiling doesn't work the same way
		 (LOCKING-RESOURCES
		   (QFASL-REL:DUMP-START)
		   (COMPILE-STREAM INPUT-STREAM GENERIC-PATHNAME FASD-STREAM
				   'QC-FILE-WORK-COMPILE
				   LOAD-FLAG IN-CORE-FLAG PACKAGE-SPEC
				   FILE-LOCAL-DECLARATIONS READ-THEN-PROCESS-FLAG)
		   ;; Output a record of the macros expanded and their current sxhashes.
		   (WHEN QC-FILE-MACROS-EXPANDED
		     (QFASL-REL:DUMP-FORM
		       `(SI::FASL-RECORD-FILE-MACROS-EXPANDED
			  ',QC-FILE-MACROS-EXPANDED)))
		   (LET ((*PACKAGE* QC-FILE-PACKAGE))
		     (QFASL-REL:WRITE-REL-FILE OUTFILE)))))
	      (T
	       (WITH-OPEN-FILE (FASD-STREAM OUTFILE
					    :DIRECTION :OUTPUT :CHARACTERS NIL :BYTE-SIZE 16.
					    :IF-EXISTS :SUPERSEDE)
		 (LOCKING-RESOURCES
		   (SETQ OUTFILE (SEND FASD-STREAM :PATHNAME))
		   (FASD-INITIALIZE)
		   (FASD-START-FILE)
		   (COMPILE-STREAM INPUT-STREAM GENERIC-PATHNAME FASD-STREAM
				   'QC-FILE-WORK-COMPILE
				   LOAD-FLAG IN-CORE-FLAG PACKAGE-SPEC
				   FILE-LOCAL-DECLARATIONS READ-THEN-PROCESS-FLAG
				   T)
		   ;; Output a record of the macros expanded and their current sxhashes.
		   (WHEN QC-FILE-MACROS-EXPANDED
		     (FASD-FORM
		       `(SI:FASL-RECORD-FILE-MACROS-EXPANDED
			  ',QC-FILE-MACROS-EXPANDED)))
		   (FASD-END-WHACK)
		   (FASD-END-FILE))))))))
  OUTFILE)

;;; COMPILE-STREAM when called by QC-FILE calls this on each form in the file
(DEFUN QC-FILE-WORK-COMPILE (FORM)
  ;; Maybe macroexpand in temp area.
  (LET-IF (NOT QC-FILE-LOAD-FLAG) ((DEFAULT-CONS-AREA QCOMPILE-TEMPORARY-AREA))
    ;; Macro-expand and output this form in the appropriate way.
    (COMPILE-DRIVER FORM 'QC-FILE-COMMON NIL)))

;;; Common processing of each form, for both QC-FILE and FASD-UPDATE-FILE.
(DEFUN QC-FILE-COMMON (FORM TYPE)
  (COND ((MEMQ TYPE '(SPECIAL DECLARE MACRO))
	 ;; While evaluating the thing, turn off the temporary area, and
	 ;; if this is an EVAL-WHEN (COMPILE), turn off the undo-declarations
	 ;; flag so that macro definitions will really happen.
	 ;;  NO, don't it screws DEFSTRUCT, which uses EVAL-WHEN (COMPILE LOAD EVAL).
	 ;; YES, do it, since DEFSTRUCT no longer uses EVAL-WHEN.
	 (LET ((DEFAULT-CONS-AREA BACKGROUND-CONS-AREA)
	       (UNDO-DECLARATIONS-FLAG (AND UNDO-DECLARATIONS-FLAG
					    (NEQ TYPE 'DECLARE))))
	   (OR QC-FILE-IN-CORE-FLAG (SYS:EVAL1 (COPYTREE FORM))))
	 ;; If supposed to compile or fasdump as well as eval, do so.
	 (COND ((EQ TYPE 'SPECIAL) (QC-FILE-FASD-FORM FORM NIL))
	       ((EQ TYPE 'MACRO)
		(QC-TRANSLATE-FUNCTION (CADR FORM)
				       (DECLARED-DEFINITION (CADR FORM)) 
				       'MACRO-COMPILE
				       (IF QC-FILE-REL-FORMAT 'REL 'QFASL)))))
	(QC-FILE-IN-CORE-FLAG (QC-FILE-FASD-FORM FORM T))
	(T (QC-FILE-FORM FORM))))

;;; Enable microcompilation (when it is requested).  NIL turns it off always.
(DEFVAR *MICROCOMPILE-SWITCH* T)

;;; Handle one form from the source file, in a QC-FILE which is actually recompiling.
;;; Only DEFUNs and random forms to be evaluated come here.
;;; We assume that DEFUNs have already been munged into the standard
;;; (DEFUN fn args . body) form.
(DEFUN QC-FILE-FORM (FORM)
  (PROG (TEM FV)
    (COND ((ATOM FORM))
	  ((EQ (CAR FORM) 'COMMENT))		;Delete comments entirely
	  ((EQ (CAR FORM) 'DEFUN)
	   (SETQ TEM (CADR FORM))
	   (SETQ FV (SI:PROCESS-DEFUN-BODY TEM (CDDR FORM)))
	   (COND (QC-FILE-LOAD-FLAG
		     (RPLACA (FUNCTION-CELL-LOCATION TEM) FV)	;In case used interpreted
		     (COMPILE-1 TEM FV)
		     (RETURN (QC-FILE-FASD-FORM FORM T))))
           (QC-TRANSLATE-FUNCTION TEM FV
				  'MACRO-COMPILE
				  (IF QC-FILE-REL-FORMAT 'REL 'QFASL))
	   (IF (AND *MICROCOMPILE-SWITCH*
		    (GETDECL TEM 'MICROCOMPILE))
	       (QC-TRANSLATE-FUNCTION
		 TEM FV				;Once more, with feeling
		 'MICRO-COMPILE
		 (COND (QC-FILE-REL-FORMAT 'REL)
		       (T 'QFASL))))
	   (RETURN NIL))
	  (QC-FILE-LOAD-FLAG (SYS:EVAL1 FORM)))
    (RETURN (QC-FILE-FASD-FORM FORM T))))
		      
;;; Dump out a form to be evaluated at load time.
;;; Method of dumping depends on format of file being written.
(DEFUN QC-FILE-FASD-FORM (FORM &OPTIONAL OPTIMIZE)
  (UNLESS (OR (NUMBERP FORM) (STRINGP FORM) (MEMQ FORM '(NIL T))
	      (AND (CONSP FORM) (EQ (CAR FORM) 'QUOTE)))
    (LET ((DEFAULT-CONS-AREA BACKGROUND-CONS-AREA))
      (IF QC-FILE-REL-FORMAT
	  (QFASL-REL:DUMP-FORM FORM OPTIMIZE)
	(FASD-FORM FORM OPTIMIZE)))))

;;; This is the heart of the M-X Fasl Update command.
;;; Reads from INPUT-STREAM using READ-FUNCTION (called with arguments like READ's)
;;; INFILE should be the name of the input file that INPUT-STREAM is reading from.
;;; OUTFILE is a pathname used to open an output file.
(DEFUN FASL-UPDATE-STREAM (INFILE OUTFILE INPUT-STREAM READ-FUNCTION
			   &AUX QC-FILE-LOAD-FLAG (QC-FILE-IN-CORE-FLAG T)
			   LAST-ERROR-FUNCTION
			   (DEFAULT-CONS-AREA DEFAULT-CONS-AREA))
  INFILE
  (UNWIND-PROTECT
    (LET ((QC-FILE-IN-PROGRESS T)
	  (LOCAL-DECLARATIONS NIL)
	  (FILE-LOCAL-DECLARATIONS NIL)
	  (FASD-PACKAGE NIL))
      (LOCKING-RESOURCES
	(WITH-OPEN-FILE (FASD-STREAM OUTFILE :DIRECTION :OUTPUT :CHARACTERS NIL :BYTE-SIZE 16.)
	  (FASD-INITIALIZE)
	  (FASD-START-FILE)
	  ;; First thing in QFASL file must be property list
	  ;; Only property supported just now is PACKAGE property
	  (FASD-ATTRIBUTES-LIST
	    (LIST ':PACKAGE (INTERN (PACKAGE-NAME *PACKAGE*) SI:PKG-KEYWORD-PACKAGE)))
	  (QC-PROCESS-INITIALIZE)
	  (DO ((EOF (NCONS NIL))
	       FORM)
	      (NIL)
	    ;; Start a new whack if FASD-TABLE is getting too big.
	    (AND ( (FASD-TABLE-LENGTH) QC-FILE-WHACK-THRESHOLD)
		 (FASD-END-WHACK))
	    ;; Read and macroexpand in temp area.
	    (SETQ DEFAULT-CONS-AREA QCOMPILE-TEMPORARY-AREA)
	    (LET ((QC-FILE-READ-IN-PROGRESS T))
	      (SETQ FORM (FUNCALL READ-FUNCTION INPUT-STREAM EOF)))
	    (AND (EQ EOF FORM)
		 (RETURN NIL))
	    (SETQ FORM (MACROEXPAND FORM))
	    (SETQ DEFAULT-CONS-AREA BACKGROUND-CONS-AREA)
	    ;; Output this form in the appropriate way.
	    (COMPILE-DRIVER FORM 'FASL-UPDATE-FORM NIL))
	  (FASD-END-WHACK)
	  (FASD-END-FILE))))
    (QC-FILE-RESET)))

;;; Process one form, for COMPILE-DRIVER.
(DEFUN FASL-UPDATE-FORM (FORM TYPE)
    (CASE TYPE
      (SPECIAL (FASD-FORM FORM NIL))
      (DECLARE)		;Ignore DECLAREs -- this may not always be right!
      ((DEFUN MACRO)	;Don't compile -- send over whatever is already compiled
        (OR (FDEFINEDP (CADR FORM))
	    (FERROR NIL "You forgot to define ~S" (CADR FORM)))
        (LET ((TEM (FDEFINITION (SI:UNENCAPSULATE-FUNCTION-SPEC (CADR FORM)))))
	  (AND (CONSP TEM) (EQ (CAR TEM) 'MACRO) (SETQ TEM (CDR TEM)))
	  (COND ((AND (CONSP TEM) (FUNCTIONP TEM T))
		 (FORMAT *ERROR-OUTPUT* "~&Compiling ~S~%" (CADR FORM))
		 (COMPILE (CADR FORM))))
	  ;; This works on this bodiless DEFUN by virtue of the fact that FASD-FORM in
	  ;; Optimize mode calls FDEFINITION rather than looking at the form.
	  (FASD-FORM FORM T)))
      (OTHERWISE (FASD-FORM FORM T))))

;;; (COMPILE-DRIVER form processing-function override-fn) should be used by anyone
;;; trying to do compilation of forms from source files, or any similar operation.
;;; It knows how to decipher DECLAREs, EVAL-WHENs, DEFUNs, macro calls, etc.
;;; It doesn't actually compile or evaluate anything,
;;; but instead calls the processing-function with two args:
;;;  a form to process, and a flag which is one of these atoms:
;;;   SPECIAL  -  QC-FILE should eval this and put it in the FASL file.
;;; 		UNDO-DECLARATIONS-FLAG, if on, should stay on for this.
;;;   DECLARE  -  QC-FILE should eval this.
;;;   PROCLAIM -  Hair.
;;;   DEFUN    -  QC-FILE should compile this and put the result in the FASL file.
;;;   MACRO    -  This defines a macro.  QC-FILE should record a declaration
;;;                and compile it into the FASL file.
;;;   RANDOM   -  QC-FILE should just put this in the FASL file to be evalled.
;;; Of course, operations other than QC-FILE will want to do different things
;;; in each case, but they will probably want to distinguish the same cases.
;;; That's why COMPILE-DRIVER will be useful to them.

;;; override-fn gets to look at each form just after macro expansion.
;;; If it returns T, nothing more is done to the form.  If it returns NIL,
;;; the form is processed as usual (given to process-fn, etc.).
;;; override-fn may be NIL.

(DEFUN COMPILE-DRIVER (FORM PROCESS-FN OVERRIDE-FN &OPTIONAL COMPILE-TIME-TOO (TOP-LEVEL-P T))
  (PROG (FN (OFORM FORM))
    ;; The following loop is essentially MACROEXPAND,
    ;; but for each expansion, we create an appropriate warn-on-errors message
    ;; containing the name of the macro about to be (perhaps) expanded this time.
    (DO ((NFORM))
	(())
      (IF (AND OVERRIDE-FN
	       (FUNCALL OVERRIDE-FN FORM))
	  (RETURN-FROM COMPILE-DRIVER NIL))
      (IF (ATOM FORM) (RETURN NIL))
      ;; Don't expand LOCALLY into PROGN here!
      ;; This way, we protect DECLAREs inside the LOCALLY
      ;; from being treated as top-level DECLARE, which would be erroneous.
      ;; The LOCALLY form will just be executed as a random form.
      (IF (EQ (CAR FORM) 'LOCALLY)
	  (RETURN))
      (SETQ NFORM
	    (WARN-ON-ERRORS ('MACRO-EXPANSION-ERROR "Error expanding macro ~S at top level"
			     (CAR FORM))
;>> Need current compilation macroenvironment!
;>> this presently uses the declared-definition crock implicitly within mexcrexpand-1. Bletch.
	      (MACROEXPAND-1 FORM)))
      (IF (EQ FORM NFORM) (RETURN)
	(SETQ FORM NFORM)))
    ;; If this was a top-level macro, supply a good guess
    ;; for the function-parent for any DEFUNs inside the expansion.
    (LET ((LOCAL-DECLARATIONS LOCAL-DECLARATIONS))
      (COND ((ATOM FORM))
	    ((AND (NEQ FORM OFORM) (SYMBOLP (CADR OFORM)))
	     (PUSH `(FUNCTION-PARENT ,(CADR OFORM)) LOCAL-DECLARATIONS))
	    ((EQ (CAR OFORM) 'DEFSTRUCT)
	     (PUSH `(FUNCTION-PARENT ,(IF (SYMBOLP (CADR OFORM)) (CADR OFORM) (CAADR OFORM)))
		   LOCAL-DECLARATIONS)))
      (AND (CONSP FORM)
	   (NEQ (CAR FORM) 'EVAL-WHEN)
	   COMPILE-TIME-TOO
	   (FUNCALL PROCESS-FN FORM 'DECLARE))
      (COND ((ATOM FORM)
	     (FUNCALL PROCESS-FN FORM 'RANDOM))
	    ((EQ (CAR FORM) 'EVAL-WHEN)
	     (OR (AND (CLI:LISTP (CADR FORM))
		      (LOOP FOR TIME IN (CADR FORM)
			    ALWAYS (MEMQ TIME '(EVAL LOAD COMPILE))))
		 (FERROR NIL "~S invalid EVAL-WHEN times;
must be a list of EVAL, LOAD, and//or COMPILE."
			     (CADR FORM)))
	     (LET* ((COMPILE (MEMQ 'COMPILE (CADR FORM)))
		    (LOAD (MEMQ 'LOAD (CADR FORM)))
		    (EVAL (MEMQ 'EVAL (CADR FORM)))
		    (EVAL-NOW (OR COMPILE (AND COMPILE-TIME-TOO EVAL))))
	       (DOLIST (FORM1 (CDDR FORM))
		 (IF LOAD
		     (IF EVAL-NOW
			 (COMPILE-DRIVER FORM1 PROCESS-FN OVERRIDE-FN T NIL)
		       (COMPILE-DRIVER FORM1 PROCESS-FN OVERRIDE-FN NIL NIL))
		   (IF EVAL-NOW
		       (FUNCALL PROCESS-FN FORM1 'DECLARE))))))
	    ((EQ (SETQ FN (CAR FORM)) 'DEFF)
	     (COMPILATION-DEFINE (CADR FORM))
	     (FUNCALL PROCESS-FN FORM 'RANDOM))
	    ((EQ FN 'DEF)
	     (COMPILATION-DEFINE (CADR FORM))
	     (MAPC #'(LAMBDA (FORM)
		       (COMPILE-DRIVER FORM PROCESS-FN OVERRIDE-FN COMPILE-TIME-TOO NIL))
		   (CDDR FORM)))
	    ((EQ FN 'WITH-SELF-ACCESSIBLE)
	     (MAPC #'(LAMBDA (FORM)
		       (COMPILE-DRIVER FORM PROCESS-FN OVERRIDE-FN COMPILE-TIME-TOO NIL))
		   (CDDR FORM)))
	    ((EQ FN 'PROGN)
	     (MAPC #'(LAMBDA (FORM)
		       (COMPILE-DRIVER FORM PROCESS-FN OVERRIDE-FN COMPILE-TIME-TOO T))
		   (CDR FORM)))
	    ((MEMQ FN '(MACRO DEFSUBST))
	     (FUNCALL PROCESS-FN FORM 'MACRO))
	    ((AND TOP-LEVEL-P
		  (MEMQ FN '(SPECIAL UNSPECIAL MAKE-PACKAGE IN-PACKAGE SHADOW SHADOWING-IMPORT
			     EXPORT UNEXPORT USE-PACKAGE UNUSE-PACKAGE IMPORT DEFF-MACRO
			     REQUIRE)))
	     (FUNCALL PROCESS-FN FORM 'SPECIAL))
	    ((EQ FN 'DECLARE)
	     (COMPILE-DECLARE (CDR FORM) PROCESS-FN))
	    ((EQ FN 'PROCLAIM)
	     (COMPILE-PROCLAIM (CDR FORM) PROCESS-FN))
	    ((EQ FN 'COMMENT) NIL)
	    ((EQ FN 'PATCH-SOURCE-FILE)
	     (COMPILE-DRIVER `(EVAL-WHEN (LOAD EVAL)
				(SETQ SI:PATCH-SOURCE-FILE-NAMESTRING ,(CADR FORM)))
			     PROCESS-FN OVERRIDE-FN COMPILE-TIME-TOO T)
	     (MAPC #'(LAMBDA (FORM)
		       (COMPILE-DRIVER FORM PROCESS-FN OVERRIDE-FN COMPILE-TIME-TOO T))
		   (CDDR FORM))
	     (COMPILE-DRIVER `(EVAL-WHEN (LOAD EVAL)
				(SETQ SI:PATCH-SOURCE-FILE-NAMESTRING NIL))
			     PROCESS-FN OVERRIDE-FN COMPILE-TIME-TOO T))
	    ((EQ FN 'COMPILER-LET)
	     (PROGW (CADR FORM)
	       (COMPILE-DRIVER `(PROGN . ,(CDDR FORM))
			       PROCESS-FN OVERRIDE-FN COMPILE-TIME-TOO T)))
	    ((EQ FN 'DEFUN)
	     (LET (TEM)
	       (WARN-ON-ERRORS ('MALFORMED-DEFUN "Malformed DEFUN")
		 (SETQ TEM (DEFUN-COMPATIBILITY (CDR FORM))))
	       (COND ((EQ (CDR TEM) (CDR FORM))
		      (IF (NULL (CDDR TEM))
			  (WARN 'MALFORMED-DEFUN ':IMPOSSIBLE
				"Malformed defun ~S" FORM)
			(FUNCALL PROCESS-FN FORM 'DEFUN)))
		     (T (COMPILE-DRIVER TEM PROCESS-FN OVERRIDE-FN COMPILE-TIME-TOO NIL)))))
	    (T (FUNCALL PROCESS-FN FORM 'RANDOM))))))

(DEFUN COMPILE-DECLARE (DECL-LIST PROCESS-FN)
  (MAPC #'(LAMBDA (DECL)
	    (FUNCALL PROCESS-FN DECL
		     (IF (MEMQ (CAR DECL) '(SPECIAL UNSPECIAL))
			 'SPECIAL
		       'DECLARE)))
	DECL-LIST))

(DEFUN COMPILE-PROCLAIM (DECL-LIST PROCESS-FN)
  (MAPC #'(LAMBDA (DECL &AUX X)
	    (CONDITION-CASE (ERROR)
		(SETQ X (SYS:EVAL1 DECL))
	      (ERROR (WARN 'BAD-DECLARATION :IMPOSSIBLE
			   "Error evaluating argument ~S to PROCLAIM~&~A"
			   DECL (SEND ERROR :REPORT NIL)))
	      (:NO-ERROR
	       (IF (NSYMBOLP (CAR X))
		   (WARN 'BAD-DECLARATION :IMPOSSIBLE
			 "An argument of PROCLAIM evaluated to ~S, which is not a valid declaration"
			 DECL)
		 (LET ((S (CAR X)))
		   (COND ((MEMQ S '(SPECIAL UNSPECIAL))
			  (FUNCALL PROCESS-FN X 'SPECIAL))
			 ((EQ S 'INLINE)
			  )
			 ((EQ S 'NOTINLINE)
			  )
			 ((EQ S 'DECLARATION)
			  )
			 (T
			  )))))))
	DECL-LIST))

(DEFPROP PATCH-SOURCE-FILE T SI:MAY-SURROUND-DEFUN)
(DEFUN PATCH-SOURCE-FILE (&QUOTE SI:PATCH-SOURCE-FILE-NAMESTRING &REST BODY)
  (MAPC #'EVAL BODY))

;;;; Handle SPECIAL and UNSPECIAL declarations.

;;; When not compiling a file, etc., or in Maclisp,
;;;  we simply put on or remove a SPECIAL property.
;;; When compiling a file (COMPILE-NO-LOAD-FLAG is T)
;;;  we just use FILE-LOCAL-DECLARATIONS to make the change.
;;; SPECIAL just pushes one big entry on FILE-LOCAL-DECLARATIONS, to save consing.
;;; UNSPECIAL, for each symbol, tries to avoid lossage in the case where a symbol
;;; is repeatedly made special and then unspecial again, by removing any existing
;;; unshadowed SPECIALs from FILE-LOCAL-DECLARATIONS, and then putting on an UNSPECIAL
;;; only if there isn't already one.  This way, FILE-LOCAL-DECLARATIONS doesn't keep growing.

;;; SPECIAL-1 and UNSPECIAL-1 can be used to make a computed symbol special or unspecial.

(REMPROP 'SPECIAL ':SOURCE-FILE-NAME)	;Avoid function redefinition message
(REMPROP 'UNSPECIAL ':SOURCE-FILE-NAME)

(DEFUN SPECIAL (&REST &QUOTE SYMBOLS)
  "Make all the SYMBOLS be marked as special 
ie make the scope of their value bindings be dynamic."
  (MAPC #'SPECIAL-1 SYMBOLS)
   T)

(DEFUN SPECIAL-1 (SYMBOL)
  "Make SYMBOL be marked special as special."
  (COND (UNDO-DECLARATIONS-FLAG
	 (SETQ FILE-UNSPECIAL-LIST (DELQ SYMBOL FILE-UNSPECIAL-LIST))
	 (UNLESS (MEMQ SYMBOL FILE-SPECIAL-LIST)
	   (PUSH SYMBOL FILE-SPECIAL-LIST)))
	(T (PUTPROP SYMBOL (OR FDEFINE-FILE-PATHNAME T) 'SPECIAL))))

(DEFUN UNSPECIAL (&REST &QUOTE SYMBOLS)
  "Make all the SYMBOLS not be marked special
ie make the scope of their value bindings be lexical."
  (MAPC #'UNSPECIAL-1 SYMBOLS)
  T)

(DEFUN UNSPECIAL-1 (SYMBOL)
  "Make SYMBOL not be marked as special."
  (COND (UNDO-DECLARATIONS-FLAG
	 (SETQ FILE-SPECIAL-LIST (DELQ SYMBOL FILE-SPECIAL-LIST))
	 (UNLESS (MEMQ SYMBOL FILE-UNSPECIAL-LIST)
	   (PUSH SYMBOL FILE-UNSPECIAL-LIST)))
	(T (REMPROP SYMBOL 'SPECIAL)
	   (REMPROP SYMBOL 'SYSTEM-CONSTANT))))

(DEFUN DEFUN-COMPATIBILITY (EXP)
  "Process the cdr of a DEFUN-form, converting old Maclisp formats into modern Lispm ones.
This must be done before the name of the function can be determined with certainty.
The value is an entire form, starting with DEFUN or MACRO.
If no change has been made, the cdr of the value will be EQ to the argument."
  (PROG (FCTN-NAME LL BODY TYPE)
	(SETQ TYPE 'EXPR)
	(SETQ FCTN-NAME (CAR EXP))
	(COND ((NOT (ATOM FCTN-NAME))		;Convert list function specs
	       (COND ((AND (= (LENGTH FCTN-NAME) 2)	;(DEFUN (FOO MACRO) ...)
			   (EQ (SECOND FCTN-NAME) 'MACRO))
		      (SETQ TYPE 'MACRO FCTN-NAME (CAR FCTN-NAME)))
		     ((EQ FCTN-NAME (SETQ FCTN-NAME (STANDARDIZE-FUNCTION-SPEC FCTN-NAME)))
		      (RETURN (CONS 'DEFUN EXP)))))	;Return if no conversion required
	      ((OR (NOT (ATOM (CADR EXP))) (NULL (CADR EXP))) ;Detect a valid DEFUN.
	       (RETURN (CONS 'DEFUN EXP)))
	      ((MEMQ (CADR EXP) '(FEXPR EXPR MACRO))
	       (SETQ TYPE (CADR EXP) EXP (CDR EXP)))
	      ((MEMQ FCTN-NAME '(FEXPR EXPR MACRO))
	       (SETQ TYPE FCTN-NAME FCTN-NAME (CADR EXP) EXP (CDR EXP))))
	;; Here if a new DEFUN has to be constructed
	(SETQ LL (CADR EXP))
	(SETQ BODY (CDDR EXP))
;Weird conversion hack to unconvert interlisp nlambdas that were previously converted
; By holloway's random hacker to kludgy fexpr's
	(COND ((AND (EQ TYPE 'FEXPR)
		    (EQUAL LL '(*ARGS*)))
		(SETQ TYPE 'EXPR)
		(SETQ LL (CONS '&QUOTE (CADAAR BODY)))	;Lambda list of internal lambda
		(SETQ BODY (CDDAAR BODY)) ))	;Body of internal lambda
; **END OF THAT HACK**
	(COND ((EQ TYPE 'FEXPR)
	       (SETQ LL (CONS '&QUOTE (CONS '&REST LL))))
	      ((EQ TYPE 'MACRO)
	       (RETURN (CONS 'MACRO (CONS FCTN-NAME (CONS LL BODY)))))
	      ((AND LL (ATOM LL))
	        (SETQ TYPE 'LEXPR
		     LL `(&EVAL &REST *LEXPR-ARGLIST* &AUX (,LL (LENGTH *LEXPR-ARGLIST*))))))
	(RETURN (CONS 'DEFUN (CONS FCTN-NAME (CONS LL BODY))))))

;;; BARF is how the compiler prints an error message.

;;; SEVERITY should be WARN for a warning (no break),
;;; DATA for something certainly very wrong in the user's input
;;; (something which can't be recovered from),
;;; BARF for an inconsistency in the compiler's data structures (not  the user's fault).

(PROCLAIM '(SPECIAL FUNCTION-BEING-PROCESSED))

(DEFVAR LAST-ERROR-FUNCTION)

(DEFSIGNAL-EXPLICIT INTERNAL-ERROR (ERROR) (EXP REASON)
  "Signalled for a compiler bug or fatal condition"
  :FORMAT-STRING "~A: ~S"
  :FORMAT-ARGS (LIST REASON EXP))

(DEFUN BARF (EXP REASON SEVERITY)
  "This is the old way to record a compiler warning.  Use COMPILER:WARN now.
EXP is a piece of data to include in the message,
REASON is a string, and SEVERITY is either WARN, DATA or BARF.
BARF means a bug in the compiler, and DATA means a severe error in input.
Both BARF and DATA enter the error handler."
  (LET ((DEFAULT-CONS-AREA BACKGROUND-CONS-AREA))	;Stream may cons
    (UNLESS (EQ FUNCTION-BEING-PROCESSED LAST-ERROR-FUNCTION)
      (SETQ LAST-ERROR-FUNCTION FUNCTION-BEING-PROCESSED)
      (FORMAT *ERROR-OUTPUT* "~%<< While compiling ~S >>" LAST-ERROR-FUNCTION))
    (IF (EQ SEVERITY 'WARN)
	(WARN 'COMPILATION-WARNING :FATAL "~A: ~S" REASON EXP)
      (SIGNAL 'INTERNAL-ERROR EXP REASON))))

;;; This is the modern way for the compiler to issue a warning.
(DEFUN WARN (TYPE SEVERITY FORMAT-STRING &REST ARGS)
  "Record and print a compiler warning.
TYPE describes the particular kind of problem, such as FUNCTION-NOT-VALID.
SEVERITY is a symbol in the keyword package giving a broader classification;
see the source for a list of possible severities.  FORMAT-STRING and ARGS
are used to print the warning."
  (APPLY 'SI:RECORD-AND-PRINT-WARNING TYPE SEVERITY NIL FORMAT-STRING
	 (LET ((DEFAULT-CONS-AREA BACKGROUND-CONS-AREA))
	   ;; Copy temp area data only; note that ARGS lives in PDL-AREA.
	   ;; on error for nonexistent package refname.
	   (MAPCAR #'(LAMBDA (ARG)
		       (SI:COPY-OBJECT-TREE ARG T 12.))
		   ARGS))))

;;; Severities for WARN include:
;;; :IMPLAUSIBLE - something that is not intrinsically wrong but is probably due
;;;  to a mistake of some sort.
;;; :IMPOSSIBLE - something that cannot have a meaning
;;; :MISSING-DECLARATION - free variable not declared special, usually.
;;; :PROBABLE-ERROR - something that is an error unless you have changed something else.
;;; :OBSOLETE - something that you shouldn't use any more
;;; :VERY-OBSOLETE - similar only more so.
;;; :MACLISP - something that doesn't work in Maclisp
;;; :FATAL - something that means the function just can't be made sense of.
;;; :ERROR - there was an error in reading or macro expansion.

(DEFUN MEMQL (A B)
  (PROG ()
     L	(COND ((NULL A) (RETURN NIL))
	      ((MEMQ (CAR A) B) (RETURN A)))
	(SETQ A (CDR A))
	(GO L)))

;;; World-load version of DEFMIC.
;;; Store into MICRO-CODE-ENTRY-ARGLIST-AREA
;;; Put on QLVAL and QINTCMP properties
(DEFUN DEFMIC (&QUOTE NAME OPCODE ARGLIST LISP-FUNCTION-P &OPTIONAL (NO-QINTCMP NIL)
	       &AUX FUNCTION-NAME INSTRUCTION-NAME MICRO-CODE-ENTRY-INDEX)
  "Define a function that is microcoded.  Used only in SYS:SYS;DEFMIC."
  (COND ((ATOM NAME)
	 (SETQ FUNCTION-NAME NAME INSTRUCTION-NAME NAME))
	((SETQ FUNCTION-NAME (CAR NAME) INSTRUCTION-NAME (CDR NAME))))
  (COND ((AND LISP-FUNCTION-P
	      (FBOUNDP FUNCTION-NAME) ;In case DEFMIC file edited after cold-load made
	      (= (%DATA-TYPE (FSYMEVAL FUNCTION-NAME)) DTP-U-ENTRY))
	 (SETQ MICRO-CODE-ENTRY-INDEX (%POINTER (FSYMEVAL FUNCTION-NAME)))
	 ;; there is no slot if it is not a LISP function.
	 (STORE (MICRO-CODE-ENTRY-ARGLIST-AREA MICRO-CODE-ENTRY-INDEX) ARGLIST))
	(T (PUTPROP FUNCTION-NAME ARGLIST 'ARGLIST)))
  (COND ((NOT NO-QINTCMP)
	 (PUTPROP INSTRUCTION-NAME (LENGTH ARGLIST) 'QINTCMP)
	 (UNLESS (EQ FUNCTION-NAME INSTRUCTION-NAME)
	   (PUTPROP FUNCTION-NAME INSTRUCTION-NAME 'MISC-INSN)
	   (PUTPROP FUNCTION-NAME (LENGTH ARGLIST) 'QINTCMP))))
  (PUTPROP INSTRUCTION-NAME OPCODE 'QLVAL))
