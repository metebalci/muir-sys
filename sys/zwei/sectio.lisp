;;; -*- Mode:LISP; Package:ZWEI; Base:8; Readtable:ZL -*-
;;; ** (c) Copyright 1980 Massachusetts Institute of Technology **
;;; This file provides the section specific code for ZMACS
;;; It uses the utility file stuff in ZWEI; FILES.
;;; The simple stuff is in ZWEI; ZMACS

(DEFCOM COM-EDIT-CALLERS "Edit functions that call the specified one.
Searches the current package, or all packages with control-U, or asks for
a package with two control-U's." ()
  (MULTIPLE-VALUE-BIND (FUN CALLERS)
      (WHO-CALLS-INTERNAL "Edit")
    (LIST-ZMACS-CALLERS-TO-BE-EDITED "Callers of" FUN T CALLERS)))

(DEFCOM COM-LIST-CALLERS "List functions that use the specified function.
Searches the current package, or all packages with control-U, or asks for
a package with two control-U's." ()
  (MULTIPLE-VALUE-BIND (FUN CALLERS)
      (WHO-CALLS-INTERNAL "List")
    (LIST-ZMACS-CALLERS-TO-BE-EDITED "Callers of" FUN NIL CALLERS))
  DIS-NONE)

(DEFCOM COM-MULTIPLE-EDIT-CALLERS "Edit functions that use the specified functions.
Searches the current package, or all packages with control-U, or asks for
a package with two control-U's.
This is the same as Edit Callers except it keeps asking for callees until
you type just a carriage return." ()
  (MULTIPLE-VALUE-BIND (FUN CALLERS)
      (MULTIPLE-WHO-CALLS-INTERNAL "Edit")
    (LIST-ZMACS-CALLERS-TO-BE-EDITED "Callers of" FUN T CALLERS)))

(DEFCOM COM-MULTIPLE-LIST-CALLERS "List functions that use the specified functions.
Searches the current package, or all packages with control-U, or asks for
a package with two control-U's.
This is the same as List Callers except it keeps asking for callees until
you type just a carriage return." ()
  (MULTIPLE-VALUE-BIND (FUN CALLERS)
      (MULTIPLE-WHO-CALLS-INTERNAL "List")
    (LIST-ZMACS-CALLERS-TO-BE-EDITED "Callers of" FUN NIL CALLERS))
  DIS-NONE)

;;; Get a package and the name of it to go in the prompt string,
;;; based on numeric argument.
(DEFUN GET-PACKAGE-TO-SEARCH ()
  (LET ((PKG (COND ((< *NUMERIC-ARG* 4) *PACKAGE*)
		   ((< *NUMERIC-ARG* 16.) PKG-GLOBAL-PACKAGE)
		   (T (LET ((X ; this really ought to do a READ..
			      (STRING-UPCASE
				(TYPEIN-LINE-READLINE "Package to search (default ~A):"
						      *PACKAGE*))))
			(PKG-FIND-PACKAGE (IF (EQUAL X "") *PACKAGE* X)))))))
    (VALUES PKG
	    (IF (= *NUMERIC-ARG* 4) "all packages" (FORMAT NIL "package ~A" PKG)))))

(DEFUN WHO-CALLS-INTERNAL (PROMPT &OPTIONAL MUST-BE-DEFINED-FLAG)
  "Read a function name and find all functions that call it.
First value is function looked for, second value is list of callers' names."
  (MULTIPLE-VALUE-BIND (PKG PKG-NAME) (GET-PACKAGE-TO-SEARCH)
    (LET ((FUNCTION (READ-FUNCTION-NAME
		      (FORMAT NIL "~A callers in ~A of" PROMPT PKG-NAME)
		      (RELEVANT-FUNCTION-NAME (POINT))
		      MUST-BE-DEFINED-FLAG
		      'ALWAYS-READ)))
      (FORMAT *QUERY-IO* "~&~Aing callers in ~A of ~S" PROMPT PKG-NAME FUNCTION)
      (VALUES FUNCTION
	      (SETUP-ZMACS-CALLERS-TO-BE-EDITED (LIST-CALLERS FUNCTION PKG))))))

(DEFUN MULTIPLE-WHO-CALLS-INTERNAL (PROMPT)
  "Read several function names and find all functions that call any of them.
First value is functions looked for,
second value is list of their callers' names."
  (DECLARE (VALUES FUNCTIONS CALLERS))
  (MULTIPLE-VALUE-BIND (PKG PKG-NAME) (GET-PACKAGE-TO-SEARCH)
    (DO ((FUNCTIONS NIL) (FUNCTION)  (END "Stop")) (NIL)
      (SETQ FUNCTION (READ-FUNCTION-NAME
		       (FORMAT NIL "~A callers in ~A of" PROMPT PKG-NAME)
		       (IF (NULL FUNCTIONS) (RELEVANT-FUNCTION-NAME (POINT)) END)
		       NIL
		       'ALWAYS-READ))
      (IF (NEQ FUNCTION END)
	  (PUSH FUNCTION FUNCTIONS)
	(SETQ FUNCTIONS (NREVERSE FUNCTIONS))
	(RETURN (VALUES FUNCTIONS
			(SETUP-ZMACS-CALLERS-TO-BE-EDITED (LIST-CALLERS FUNCTIONS PKG))))))))

(DEFUN SETUP-ZMACS-CALLERS-TO-BE-EDITED (CALLERS)
  "Sort a list of function specs by pathname of source file.
Also discard any function specs that are for :PREVIOUS-DEFINITION properties."
  (SETQ CALLERS (DEL-IF #'(LAMBDA (X) (AND (EQ (CAR-SAFE X) :PROPERTY)
					   (EQ (CADDR X) :PREVIOUS-DEFINITION)))
			CALLERS))
  (SORT CALLERS #'(LAMBDA (X Y)
		    (LET ((XNAME (CAR (SOURCE-FILE-NAMES X NIL)))
			  (YNAME (CAR (SOURCE-FILE-NAMES Y NIL))))
		      (AND (EQ XNAME YNAME) (SETQ XNAME X YNAME Y))
		      (OR (SYMBOLP XNAME) (TYPEP XNAME 'PATHNAME)
			  (SETQ XNAME ""))
		      (OR (SYMBOLP YNAME) (TYPEP YNAME 'PATHNAME)
			  (SETQ YNAME ""))
		      (STRING-LESSP XNAME YNAME)))))

(DEFUN LIST-ZMACS-CALLERS-TO-BE-EDITED (TYPE FUNCTION JUST-EDIT CALLERS)
  (COMMAND-STORE 'COM-GO-TO-NEXT-TOP-LEVEL-POSSIBILITY #/C-/. *ZMACS-COMTAB*)
  (FUNCALL (IF JUST-EDIT #'EDIT-FUNCTIONS-NO-DISPLAY #'EDIT-FUNCTIONS-DISPLAY)
	   ;; We want the symbols to show with their proper package prefixes
	   (STABLE-SORTCAR (MAPCAR #'(LAMBDA (X)
				       (CONS (FORMAT NIL "~S" X) X))
				   CALLERS)
			   #'STRING-LESSP)
	   "~A~@[ ~S~]:"
	   "No ~A~@[ ~S~] found."
	   TYPE FUNCTION))

(DEFUN LISP-OBJECT-APROPOS (WHAT PREDICATE)
  (MULTIPLE-VALUE-BIND (PKG PKG-NAME) (GET-PACKAGE-TO-SEARCH)
    (MULTIPLE-VALUE-BIND (FUNCTION KEY STR)
	(GET-EXTENDED-SEARCH-STRINGS
	  (FORMAT NIL "List ~As in ~A containing substring:" WHAT PKG-NAME))
      (LIST-ZMACS-CALLERS-TO-BE-EDITED
	(FORMAT NIL "~@(~A~)s matching" WHAT) STR NIL
	(SETUP-ZMACS-CALLERS-TO-BE-EDITED
	    (LET ((L NIL))
	      (FUNCALL (IF (EQ PKG PKG-GLOBAL-PACKAGE) #'MAPATOMS-ALL #'MAPATOMS)
		       #'(LAMBDA (SYM)
			   (AND (FUNCALL FUNCTION KEY (STRING SYM))
				(FUNCALL PREDICATE SYM)
				(PUSH SYM L)))
		       PKG)
	      L)))))
  DIS-NONE)

(DEFCOM COM-FUNCTION-APROPOS "List functions containing the given substring.
Searches the current package, or all packages with control-U, or asks for
a package with two control-U's." ()
  (LISP-OBJECT-APROPOS "function" #'FBOUNDP))

(DEFCOM COM-LISP-VARIABLE-APROPOS "List variables containing the given substring.
Searches the current package, or all packages with control-U, or asks for
a package with two control-U's." ()
  (LISP-OBJECT-APROPOS "variable" #'BOUNDP))

(DEFCOM COM-FLAVOR-APROPOS "List flavors containing the given substring.
/Searches the current package, or all packages with control-U, or asks for
a package with two control-U's." ()
  (LISP-OBJECT-APROPOS "flavor" #'(LAMBDA (S) (GET S 'SI:FLAVOR))))

(DEFCOM COM-LIST-MATCHING-SYMBOLS "List symbols satisfying the given predicate.
Searches the current package, or all packages with control-U, or asks for
a package with two control-U's." ()
  (MULTIPLE-VALUE-BIND (PKG PKG-NAME) (GET-PACKAGE-TO-SEARCH)
    (LET ((FUNCTION (READ-EVALUATED-MINI-BUFFER
		      "'(LAMBDA (SYMBOL) )" 18.
		      "List functions in ~A satisfying: (end with ~C)" PKG-NAME #/END))
	  (SYMBOL (GENSYM)))
      (FSET SYMBOL FUNCTION)
      (COMPILE SYMBOL)
      (LET ((*PRINT-LENGTH* 3) (*PRINT-LEVEL* 3))
	(LIST-ZMACS-CALLERS-TO-BE-EDITED
	  "Symbols satisfying" FUNCTION NIL
	  (SETUP-ZMACS-CALLERS-TO-BE-EDITED (LIST-MATCHING-SYMBOLS SYMBOL PKG))))))
  DIS-NONE)

(DEFUN READ-EVALUATED-MINI-BUFFER (&OPTIONAL INITIAL-CONTENTS INITIAL-CHAR-POS
				   FORMAT-STRING &REST FORMAT-ARGS &AUX INTERVAL PROMPT)
  "Read and evaluate an expression in the mini buffer, returning the value.
INITIAL-CONTENTS is a string to start off with, and INITIAL-CHAR-POS if non-NIL
 is where to put the cursor in that string.
FORMAT-STRING and FORMAT-ARGS are used for prompting."
  (SETQ PROMPT (IF (NULL FORMAT-ARGS) FORMAT-STRING
		   (APPLY #'FORMAT NIL FORMAT-STRING FORMAT-ARGS)))
  (SETQ INTERVAL (NTH-VALUE 2
		   (EDIT-IN-MINI-BUFFER *MINI-BUFFER-MULTI-LINE-COMTAB*
					INITIAL-CONTENTS
					INITIAL-CHAR-POS
					(AND PROMPT (NCONS PROMPT)))))
  (LET ((FORM-STRING (STRING-INTERVAL INTERVAL))
	(FORM)
	(EOF '(())))
    (SETQ FORM (CLI:READ-FROM-STRING FORM-STRING NIL EOF :START 0))
    (AND (EQ FORM EOF) (BARF "Unbalanced parentheses."))
    (EVAL FORM)))

(DEFUN STRING-FROM-SPEC (SPEC)
  "Return a string for how function spec SPEC would look in a definition a source file.
For example, a (:PROPERTY x y) function spec looks like (x y)."
  (COND ((STRINGP SPEC) SPEC)
	((SYMBOLP SPEC) (SYMBOL-NAME SPEC))
	((ATOM SPEC) (FORMAT NIL "~S" SPEC))
	((MEMQ (CAR SPEC) '(:PROPERTY :METHOD :MAYBE-METHOD :HANDLER))
	 (DEFINITION-NAME-AS-STRING (CAR SPEC)
				    (IF (EQ (AND (CDDDR SPEC) (THIRD SPEC)) ':WRAPPER)
					(LIST (SECOND SPEC) (FOURTH SPEC))
				      (CDR SPEC))))
	((MEMQ (CAR SPEC) '(:DEFSTRUCT :DEFSELECT))
	 (DEFINITION-NAME-AS-STRING (CAR SPEC) (CADR SPEC)))
	((EQ (CAR SPEC) ':PROPERTY)
	 (DEFINITION-NAME-AS-STRING ':PROPERTY (CDR SPEC)))
	((EQ (CAR SPEC) ':INTERNAL)
	 (STRING-FROM-SPEC (CADR SPEC)))
	;; For random function specs, use as given.
	(T (DEFINITION-NAME-AS-STRING NIL SPEC))))

(DEFUN DEFINITION-NAME-AS-STRING (TYPE SPEC)
  "Like printing SPEC into a string, but faster, with a few quirks.
The quirk is that if TYPE is non-NIL the printing is done
in the package which the car of SPEC belongs to, if that is possible."
  (LET-IF (AND TYPE (TYPEP (CAR-SAFE SPEC) '(AND SYMBOL (NOT NULL)))
	       (LET ((TEM (SYMBOL-PACKAGE (CAR SPEC))))
		 (AND TEM (NEQ TEM SI:PKG-KEYWORD-PACKAGE)
		      (NEQ TEM SI:PKG-GLOBAL-PACKAGE)
		      (NEQ TEM SI:PKG-SYSTEM-PACKAGE))))
	  ((*PACKAGE* (SYMBOL-PACKAGE (CAR SPEC))))
    (COND ((AND (SYMBOLP SPEC)
		(LOOP WITH PNAME = (SYMBOL-NAME SPEC)
		      FOR I FROM 0 BELOW (LENGTH PNAME)
		      AS CH = (CHAR PNAME I)
		      ALWAYS (OR (CHAR #/A CH #/Z) (CHAR= CH #/-))))
	   (SYMBOL-NAME SPEC))
	  ((AND (CONSP SPEC)
		(LOOP FOR ELT IN SPEC
		      ALWAYS
		      (AND (SYMBOLP ELT)
			   (LET ((PNAME (SYMBOL-NAME ELT)))
			     (LOOP FOR I FROM 0 BELOW (LENGTH PNAME)
				   AS CH = (CHAR PNAME I)
				   ALWAYS (OR (CHAR #/A CH #/Z) (CHAR= CH #/-)))))))
	   (LET ((STRING (MAKE-STRING 40. :FILL-POINTER 0)))
	     (VECTOR-PUSH #/( STRING)
	     (LOOP FOR X IN SPEC
		   FOR POS FROM 0 BY 1
		   AS P = (SYMBOL-PACKAGE X)
		   AS PNAME = (SYMBOL-NAME X)
		   DO (OR (ZEROP POS) (STRING-NCONC STRING #/SP))
		   (IF (AND (NEQ P PACKAGE)
			    (NOT (MEMQ P (PACKAGE-USE-LIST PACKAGE))))
		       (STRING-NCONC STRING
				     (IF (EQ P SI:PKG-KEYWORD-PACKAGE)
					 ""
				       (SI:PKG-SHORTEST-NAME P SI:PKG-GLOBAL-PACKAGE))
				     #/: PNAME)
		     (STRING-NCONC STRING PNAME)))
	     (STRING-NCONC STRING #/))
	     STRING))
	  (T
	   ;; Not all symbols, stay on the safe side
	   (FORMAT:OUTPUT NIL
	     (PRIN1 SPEC))))))

;;; Derive function spec from defining form and/or function spec shorthand
;;; This all used to be inside SYMBOL-FROM-STRING

;;; Certain types of function specs have two ways to type them, with and without the leading
;;; type keyword.  Also certain types of functions and other definitions do not follow the
;;; standard form of (DEFxxx name options...).  What we do here is to recognize and
;;; standardize those cases.

(defstruct (def-pat (:type :list*) (:conc-name def-pat-)
		    (:alterant nil)
		    (:constructor make-def-pat
				  (def-name string length type sub-type)))
  def-name
  string
  length
  type
  sub-type)

(defvar *def-patterns* nil
  "Used by SYMBOL-FROM-STRING to record patterns of special defining forms.")

(defmacro def-definer (def-name type &optional sub-type)
  "Used to tell Zwei of the existence of a defining form.  
The TYPE is used to select an appropriate (:PROPERTY ... SYMBOL-FROM-STRING) function to
parse the the name into a function spec.  The optional SUB-TYPE is needed in cases where
one parsing function is shared by several defining forms.  For instance
/(:PROPERTY :ALWAYS-METHOD SYMBOL-FROM-STRING) is used for both DEFMETHOD and DEFWRAPPER,
but DEFWRAPPER needs an implicit :WRAPPER inserted into the function spec."
  `(progn 'compile
	  (setq *def-patterns*
		(delete-if #'(lambda (x) (eq ',def-name (car x))) *def-patterns*))
	  (let ((.string. (string-append "(" (string ',def-name))))
	    (push (make-def-pat ',def-name .string. (string-length .string.) ,type ,sub-type)
		  *def-patterns*))))

;;; (DEFMETHOD (FLAVOR ...) ... => (:METHOD FLAVOR ...)
;;; (DEFWRAPPER (FLAVOR :MESSAGE) ... => (:METHOD FLAVOR :WRAPPER :MESSAGE)

(def-definer defmethod :always-method)
(def-definer defwrapper :always-method :wrapper)

(defun (:property :ALWAYS-METHOD symbol-from-string) (spec str ignore meth-type ignore)
  (values (CONS :METHOD (if meth-type
			    (list* (first SPEC) meth-type (rest SPEC))
			  SPEC))
	  str))

;;; Some ambiguous cases, etc.

;;; :HANDLER doesn't appear in source files, but gets translated into an appropriate :METHOD
;;; here, by analyzing the combined method.

(defprop :MAYBE-METHOD maybe-method-symbol-from-string symbol-from-string)
(defprop :METHOD       maybe-method-symbol-from-string symbol-from-string)
(defprop :HANDLER      maybe-method-symbol-from-string symbol-from-string)

(defun maybe-method-symbol-from-string (spec str type ignore ok-to-ask
					&aux sym)
  (LET ((FLAVOR (CAR SPEC))
	(MESSAGE (IF (CDDR SPEC) (CADDR SPEC) (CADR SPEC)))
	FL)
    (COND ((SETQ FL (GET FLAVOR 'SI:FLAVOR)))
	  ;;>> Ugh
	  ((AND (VALIDATE-2-LONG-LIST SPEC) (CLASS-SYMBOLP FLAVOR))
	   (SETQ SYM (FUNCALL (SYMBOL-VALUE FLAVOR) ':METHOD-FOR (CADR SPEC))
		 FL T))
	  (OK-TO-ASK
	   (DOLIST (SYMBOL (PACKAGE-LOOKALIKE-SYMBOLS FLAVOR
						      NIL '(SI:FLAVOR)))
	     (IF (FQUERY () "Do you mean ~S? "
			 `(:METHOD ,SYMBOL . ,(CDR SPEC)))
		 (RETURN (SETQ FLAVOR SYMBOL
			       SPEC (CONS FLAVOR (CDR SPEC))
			       FL (GET FLAVOR 'SI:FLAVOR)))))))
    (or (COND ((SYMBOLP FL)				;T or NIL
	       (AND (EQ TYPE ':MAYBE-METHOD)
		    (VALIDATE-2-LONG-LIST SPEC)
		    (values (CONS ':PROPERTY SPEC)
			    str)))
	      ((FDEFINEDP `(:METHOD . ,SPEC))
	       (values `(:METHOD . ,SPEC)
		       str))
	      (OK-TO-ASK
	       (DOLIST (SYMBOL (OR (FIND-COMBINED-METHODS FLAVOR MESSAGE NIL)
				   (SI:FLAVOR-ALL-INHERITABLE-METHODS
				     FLAVOR MESSAGE)))
		 (IF (FQUERY '() "Do you mean ~S? " SYMBOL)
		     (return (values SYMBOL
				     str))))))
	       (values nil
		       str))))

;;; (DEFSTRUCT (NAME ... => NAME

(def-definer defstruct :defstruct)

(defun (:property :DEFSTRUCT symbol-from-string) (spec ignore ignore ignore ignore
						  &aux sym)
  (values (setq sym (car spec))
	  (symbol-name sym)))

;;; (DEFSELECT (FSPEC ...) ... => FSPEC

(def-definer defselect :defselect)

(defun (:property :DEFSELECT symbol-from-string) (spec ignore ignore ignore ignore
						  &aux sym)
  (SETQ SYM (CAR SPEC))
  (IF (SYMBOLP SYM)
      (values sym
	      (SYMBOL-NAME SYM))
    (MULTIPLE-VALUE-bind (SYM STR)
	(SYMBOL-FROM-STRING SYM)
      (values sym
	      str))))

;;; (DEFUN (INDICATOR SYMBOL) ... => (:PROPERTY INDICATOR SYMBOL)

(defun (:property :PROPERTY symbol-from-string) (spec str ignore ignore ignore)
  (if (VALIDATE-2-LONG-LIST SPEC)
      (values (CONS :property SPEC)
	      str)
    (values nil
	    str)))

;;; :INTERNAL doesn't appear in source files, but might be given as the argument to
;;; m-X Disassemble.  The code here just tries not to destory it.

(defun (:property :INTERNAL symbol-from-string) (spec ignore ignore ignore ignore)
  (values (CONS :internal SPEC)
	  (DEFINITION-NAME-AS-STRING NIL (CAR SPEC))))

;;; Obsolete randomness?

(defun (:property :INSTANCE-METHOD symbol-from-string) (spec str ignore ignore ignore)
  (if (BOUNDP (CAR SPEC))
      (values (FUNCALL (CLASS (SYMBOL-VALUE (CAR SPEC)))
		       :METHOD-FOR (CADR SPEC))
	      str)
    (values nil
	    str)))


(DEFUN SYMBOL-FROM-STRING (STR &OPTIONAL LINE OK-TO-ASK SYM
			   &AUX (EOF '(())) ERRORP)
  "Given a string STR as found after DEF..., return the name of the object being defined.
LINE is the line that the string was found in.  It is used for
finding the particular defining construct used; this affects the result
since (DEFUN (FOO BAR) defines (:PROPERTY FOO BAR)
while (DEFMETHOD (FOO BAR) defines (:METHOD FOO BAR).
OK-TO-ASK means in certain circumstances
where things are not clear, ask the user.  Otherwise we guess.

The arg can also be an object; then its printed representation is used as the string.

The second value is a canonicalized string for the object
 (maybe the same string specified, maybe not).
The third is T if there was a problem
 in parsing the string (such as unbalanced parens).

You can pass the read-in form of the object as the fourth arg
if you already know it."
  (DECLARE (VALUES SYM STR ERRORP))
  (IF (ARRAYP STR)
      (UNLESS SYM
	(MULTIPLE-VALUE-SETQ (SYM ERRORP)
	  (CATCH-ERROR (CLI:READ-FROM-STRING STR T EOF) NIL)))
    (SETQ SYM STR
	  STR (FORMAT NIL "~S" STR)))
  (COND (ERRORP
	 (VALUES NIL NIL ERRORP))
	((SYMBOLP SYM)
	 (VALUES SYM (SYMBOL-NAME SYM)))
	((OR (ATOM SYM) (EQ SYM EOF))
	 (VALUES NIL NIL T))
	(:else
	 ;; At this point we have a list to parse.  The variables are:
	 ;;	TYPE - the type of function spec or non-function definition
	 ;;	SYM - the function spec or definition name
	 ;;	SPEC - the variant of SYM which appears in the source code
	 ;;	STR - SPEC converted to a string
	 ;;     S-FROM-S-FN - a function which will return SYM and STR given
	 ;;                   these variables, SUB-TYPE, and OK-TO-ASK
	 (LET ((TYPE (CAR SYM))
	       (sub-type nil)
	       SPEC s-from-s-fn)
	   (IF (GET TYPE 'SI::FUNCTION-SPEC-HANDLER)
	       (SETQ SPEC (CDR SYM)
		     STR (DEFINITION-NAME-AS-STRING TYPE SPEC))
	     (SETQ SPEC SYM)
	     (let ((DELIM-IDX (AND LINE (STRING-SEARCH-SET "( " LINE 1))))
	       (setq type (COND ((NULL LINE)
				 :MAYBE-METHOD)
				((dolist (def-pat *def-patterns*)
				   (let ((def-pat-length (def-pat-length def-pat)))
				     (when (AND (= DELIM-IDX def-pat-length)
						(%STRING-EQUAL LINE 0
							       (def-pat-string def-pat)
							       0 def-pat-length))
				       (setq sub-type (def-pat-sub-type def-pat))
				       (return (def-pat-type def-pat))))))
				(T :PROPERTY)))))
	   (OR (and (setq s-from-s-fn (get type 'symbol-from-string))
		    ;; This function is required to pass STR through untouched if it loses
		    (multiple-value (sym str)
		      (funcall s-from-s-fn spec str type sub-type ok-to-ask)))
	       ;; Something we don't understand, make a bogus symbol to use as a property
	       ;; list to remember the location of this definition
	       (SETQ SYM (INTERN STR *UTILITY-PACKAGE*))))
	 (IF (NOT (SYS:VALIDATE-FUNCTION-SPEC SYM))
	     (VALUES NIL NIL T)
	     (VALUES SYM STR)))))

(DEFUN VALIDATE-2-LONG-LIST (L)
  "T if L is a list of exactly two symbols."
  (AND (CONSP L)
       (SYMBOLP (CAR L))
       (CONSP (CDR L))
       (SYMBOLP (CADR L))
       (NULL (CDDR L))))


;;; The properties this uses are defined in MODES.
;;; The mode's property is probably :LISP, :TEXT or NIL.
;;; Note that some things open-code this so they can do the GETs only once.
(DEFUN GET-SECTION-NAME (MODE LINE BP)
  "Determine whether LINE is a definition line, and if so return the name defined.
Determination is made according to MODE (which might be, eg, LISP-MODE).
BP should be a temporary BP that can be modified by this function.
The first value is the symbol or function spec defined, or NIL.
The second value is the string which appears in the line to specify that symbol or spec.
The third value is T if there is no definition on the line."
  (DECLARE (VALUES SYM STR ERRORP))
  (FUNCALL (GET (GET MODE 'EDITING-TYPE) 'GET-SECTION-NAME)
	   LINE BP))

;;; And here are the functions that actually implement GET-SECTION-NAME
;;; for various well-known modes.

(DEFVAR *SECTION-COUNT* 0)

(DEFUN (:PROPERTY :LISP GET-SECTION-NAME) (LINE BP &AUX STR SYM ERRORP
					   IDX END-IDX (EOF "") NON-FONT-LINE)
  (IF (NOT (AND (> (LENGTH LINE) 1)
		(= (CHAR-CODE (CHAR LINE 0)) (CHAR-CODE #/())))
      (VALUES NIL NIL T)
    (SETQ ERRORP T)
    (WHEN (AND (%STRING-EQUAL LINE 0 "(DEF" 0 4)
	       (NOT (%STRING-EQUAL LINE 0 "(DEFPROP " 0 9))
	       (SETQ IDX (STRING-SEARCH-SET *WHITESPACE-CHARS* LINE))
	       (SETQ IDX (STRING-SEARCH-NOT-SET *WHITESPACE-CHARS* LINE IDX)))
      (SETQ ERRORP NIL)
      (SETQ NON-FONT-LINE (STRING-REMOVE-FONTS LINE))
      (CONDITION-CASE ()
	  (SETF (VALUES SYM END-IDX)
		(READ-FROM-STRING NON-FONT-LINE EOF IDX))
	(:NO-ERROR
	 (IF (EQ SYM EOF)
	     (SETQ ERRORP T)
	   (SETQ STR (SUBSTRING NON-FONT-LINE IDX (MIN (LENGTH LINE) END-IDX)))))
	(SYS:READ-ERROR
	 (SETQ STR (GET-DEFUN-NAME (MOVE-BP BP LINE 0)))))
      (UNLESS ERRORP
	(MULTIPLE-VALUE-SETQ (SYM NIL ERRORP)
	  (SYMBOL-FROM-STRING STR NON-FONT-LINE NIL SYM))))
    (WHEN ERRORP
      (SETQ SYM (CONCATENATE 'STRING
			     (LET ((BUFFER (NODE-TOP-LEVEL-NODE (LINE-NODE LINE))))
			       (IF (BUFFER-PATHNAME BUFFER)
				   (LET ((NAME
					   (PATHNAME-NAME (BUFFER-PATHNAME BUFFER))))
				     (IF (CONSP NAME)
					 (APPLY #'STRING-APPEND
						(MAPCAR #'(LAMBDA (NAME-ELT)
							    (IF (CONSP NAME-ELT)
								(CAR NAME-ELT)
							        NAME-ELT))
							NAME))
				       (STRING NAME)))
				 (BUFFER-NAME BUFFER)))
			     "-"
			     (LET ((START-INDEX (STRING-SEARCH-NOT-CHAR #/( LINE)))
			       (SUBSTRING LINE START-INDEX
					  (AND START-INDEX
					       (STRING-SEARCH-SET *WHITESPACE-CHARS*
								  LINE START-INDEX))))
			     "-"
			     (PRIN1-TO-STRING (INCF *SECTION-COUNT*)))
	    STR SYM))
    (VALUES SYM STR NIL)))

(DEFUN GET-DEFUN-NAME (BP &AUX BP1)
  "Return the function spec defined by the defun starting at BP."
  (AND (SETQ BP (FORWARD-ATOM BP))
       (SETQ BP (FORWARD-OVER *WHITESPACE-CHARS* BP))
       (SETQ BP1 (FORWARD-SEXP BP))
       (STRING-REMOVE-FONTS (STRING-INTERVAL BP BP1))))

(DEFUN (:PROPERTY :TEXT GET-SECTION-NAME) (LINE BP &AUX STR SYM ERRORP)
  (IF (AND (%STRING-EQUAL LINE 0 ".DEF" 0 4)
	   (SETQ STR (GET-TEXT-DEFUN-NAME (MOVE-BP BP LINE 0))))
      (SETQ SYM (INTERN STR *UTILITY-PACKAGE*))
    (SETQ ERRORP T))
  (VALUES SYM STR ERRORP))

(DEFUN GET-TEXT-DEFUN-NAME (BP &AUX BP1)
  (ATOM-WORD-SYNTAX-BIND
    ;; Now get the second word after BP.
    (AND (SETQ BP (FORWARD-WORD BP))
	 (SETQ BP (FORWARD-OVER *BLANKS* BP))
	 (SETQ BP1 (FORWARD-WORD BP))
	 (STRING-REMOVE-FONTS (STRING-INTERVAL BP BP1)))))

(DEFUN (:PROPERTY NIL GET-SECTION-NAME) (LINE BP)
  (DECLARE (IGNORE LINE BP))
  (VALUES NIL NIL T))

;;; The SECTION-P is a function which takes a line as arg
;;; and returns T if the line looks likely to be the start of a section.
;;; You could use the GET-SECTION-NAME function, but that will not be
;;; guaranteed to be right if the following line(s) are not there,
;;; and if it is wrong it will return "no section".
;;; These functions err by returning T if in doubt;
;;; then you can use the GET-SECTION-NAME function after you prepare for it.
(DEFUN (:PROPERTY :LISP SECTION-P) (LINE)
  (AND (PLUSP (LENGTH LINE))
       (= (CHAR-CODE (CHAR LINE 0))
	  (CHAR-CODE #/())))

(DEFUN (:PROPERTY :TEXT SECTION-P) (LINE)
  (%STRING-EQUAL LINE 0 ".DEF" 0 4))

(DEFUN (:PROPERTY NIL SECTION-P) (IGNORE) NIL)

(DEFUN DEFINITION-LIKELY-POSITION (BP1 &OPTIONAL BP2 IN-ORDER-P SYMBOL
				       &AUX DEFUN-LINE NON-DEFUN-LINE COMMENT-LINE BUFFER)
  "Return a BP within specified interval to a line that might relate to defining SYMBOL.
SYMBOL is actually a function spec or a name being defined in any way.
The line is found by a textual search for SYMBOL.
However, lines starting with open parens get first priority.
Comment lines have lower priority than non-comment lines.
If nothing is found, the beginning of the interval is returned."
  (GET-INTERVAL BP1 BP2 IN-ORDER-P)
  (DO ((LINE (BP-LINE BP1) (LINE-NEXT LINE))
       (FROM-INDEX (BP-INDEX BP1) 0)
       (END-LINE (BP-LINE BP2))
       (KEY (STRING-FROM-SPEC SYMBOL))
       (INDEX) (TEM))
      (NIL)
    (AND (SETQ INDEX (STRING-SEARCH KEY LINE FROM-INDEX
				    (AND (EQ LINE END-LINE) (BP-INDEX BP2))))
	 (COND ((CHAR-EQUAL #/( (CHAR LINE 0))
		(SETQ DEFUN-LINE LINE)
		(RETURN T))
	       ((AND (NULL COMMENT-LINE)
		     (SETQ TEM (FIND-COMMENT-START LINE))
		     (< TEM INDEX))
		(SETQ COMMENT-LINE LINE))
	       ((NULL NON-DEFUN-LINE)
		(SETQ NON-DEFUN-LINE LINE))))
    (AND (EQ LINE END-LINE)
	 (RETURN NIL)))
  (SETQ BUFFER (BP-TOP-LEVEL-NODE BP1))  
  (VALUES (CREATE-BP (OR DEFUN-LINE NON-DEFUN-LINE COMMENT-LINE (BP-LINE BP1))
		     0)
	  BUFFER))

(DEFUN PACKAGE-LOOKALIKE-SYMBOLS (PNAME
				  &OPTIONAL IGNORE
					    (PROPERTIES '(:SOURCE-FILE-NAME ZMACS-BUFFERS))
					    &AUX LIST)
  "Return a list of symbols with pname PNAME in various packages.
Only symbols which possess one of the properties in PROPERTIES are considered."
  (DOLIST (PKG *ALL-PACKAGES*)
    (SETQ LIST (PACKAGE-LOOKALIKE-SYMBOLS-1 (STRING PNAME) PKG LIST PROPERTIES)))
  LIST)

(DEFUN PACKAGE-LOOKALIKE-SYMBOLS-1 (PNAME PKG LIST PROPERTIES &AUX TEM)
  (AND (SETQ TEM (INTERN-LOCAL-SOFT PNAME PKG))
       (NOT (MEMQ TEM LIST))
       ;; Used to be GETL, but that was fooled by a property of NIL
       (LOOP FOR PROP IN PROPERTIES
	     THEREIS (GET TEM PROP))
       (PUSH TEM LIST))
  LIST)

(defun definition-text-location-1 (spec)
  "Return a BP to SPEC's definition in ZMACS, if it has a unique definition.
If SPEC has no definition or more than one, return NIL.
Will read in a source file if there is a unique source file.
Does not select the buffer, and can be called from outside the editor.
If there is more than one definition, the user should be advised to
enter ZMACS, give C-M-X Make Correspondence on the definition he prefers,
and retry your operation."
  (declare (return-list bp buffer))
  (let ((chosen-def (si:function-spec-get spec 'zmacs-chosen-definition))
	(zbp (si:function-spec-get spec 'zmacs-buffers)))
    (cond (chosen-def
	   (values (create-bp (cdr chosen-def) 0) (car chosen-def)))
	  (zbp
	   (and (null (cdr zbp))
		(not (buffer-is-not-only-source-file-p (caar zbp) spec))
		(if (definition-still-real-p-new (caar zbp) (cdar zbp) spec)
		    (values (create-bp (cdar zbp) 0) (caar zbp))
		  (let ((package package))
		    (compute-buffer-package (caar zbp))
		    (sectionize-buffer (caar zbp))
		    (definition-text-location-1 spec)))))
	  (t
	   (let ((sources (subset-not 'find-buffer-named (source-file-names spec))))
	     (if (and sources (null (cdr sources)))
		 (progn (find-file (car sources))
			(definition-text-location-1 spec))))))))

;;;; Tag table stuff

(DEFCOM COM-VISIT-TAG-TABLE "Read in the specified tag table file.
Go through the tag table, and mark the name of each tag as being
a possible section of its file.  Later, the Edit Definition command
will see these marks and figure out which file to use.
Get the name of the file from the mini-buffer." ()
  (READ-TAG-TABLE (READ-DEFAULTED-PATHNAME "Tag Table:" (PATHNAME-DEFAULTS) "TAGS"))
  DIS-NONE)

(DEFUN READ-TAG-TABLE (FILE &AUX (ADDED-COMPLETIONS (MAKE-ARRAY #o1000 :TYPE 'ART-Q-LIST
								       :LEADER-LENGTH 2)))
  "Read in tag table file named FILE, recording source files of functions in it."
  (STORE-ARRAY-LEADER 0 ADDED-COMPLETIONS 0)
  (WITH-OPEN-FILE (STREAM FILE '(:READ :SUPER-IMAGE))
    (DO ((LINE) (EOF)
	 (FILE-LIST) (PATHNAME) (MODE))
	(NIL)
      (MULTIPLE-VALUE-SETQ (LINE EOF)
	(SEND STREAM :LINE-IN))
      (COND (EOF
	     (SEND FILE :PUTPROP (NREVERSE FILE-LIST) 'ZMACS-TAG-TABLE-FILE-SYMBOLS)
	     (OR (RASSQ FILE *ZMACS-TAG-TABLE-ALIST*)
		 (PUSH (CONS (STRING FILE) FILE) *ZMACS-TAG-TABLE-ALIST*))
	     (RETURN)))
      (SETQ PATHNAME (FS:MERGE-PATHNAME-DEFAULTS LINE *PATHNAME-DEFAULTS*))
      (PUSH PATHNAME FILE-LIST)
      (SETQ LINE (SEND STREAM :LINE-IN))	;Length,Mode
      (SETQ MODE (GET-FILE-MAJOR-MODE
		   (INTERN (SUBSTRING LINE (1+ (STRING-SEARCH-CHAR #/, LINE))) "USER")))
      (DO ((*PACKAGE* (PKG-FIND-PACKAGE (OR (SEND (SEND PATHNAME :GENERIC-PATHNAME)
						  :GET :PACKAGE)
					    *PACKAGE*)))
	   (SPACE-POS) (RUBOUT-POS)
	   (STR) (SNAME))
	  ((CHAR= (CHAR (SETQ LINE (SEND STREAM :LINE-IN)) 0) #/))
	(COND ((SETQ SPACE-POS (STRING-SEARCH-SET '(#/SP #/TAB) LINE))
	       (SETQ SPACE-POS (1+ SPACE-POS)
		     RUBOUT-POS (COND ((STRING-SEARCH-CHAR (INT-CHAR #o177) LINE SPACE-POS))
				      (T (SEND STREAM :LINE-IN)
					 (1+ (STRING-LENGTH LINE))))
		     STR (SUBSTRING LINE SPACE-POS (1- RUBOUT-POS)))
	       (COND ((CASE (GET MODE 'EDITING-TYPE)
			(:LISP
			 (AND (%STRING-EQUAL LINE 0 "(DEF" 0 4)
			      (NOT (%STRING-EQUAL LINE 0 "(DEFPROP " 0 9))
			      (SETQ SNAME (SYMBOL-FROM-STRING STR LINE))))
			(:TEXT
			 (AND (%STRING-EQUAL LINE 0 ".DEF" 0 4)
			      (SETQ SNAME (INTERN STR *UTILITY-PACKAGE*))))
			(OTHERWISE NIL))
		      (SECTION-COMPLETION SNAME STR ADDED-COMPLETIONS 1000)
		      (SECTION-COMPLETION SNAME (DEFINITION-NAME-AS-STRING NIL SNAME)
					  ADDED-COMPLETIONS 1000)
		      (OR (GET SNAME ':SOURCE-FILE-NAME)
			  (PUTPROP SNAME PATHNAME ':SOURCE-FILE-NAME))
		      (PUSH* PATHNAME (GET SNAME 'ZMACS-TAG-FILE-SYMBOLS)))))))))
  (SORT-COMPLETION-AARRAY ADDED-COMPLETIONS)
  (MERGE-COMPLETION-AARRAY *ZMACS-COMPLETION-AARRAY* ADDED-COMPLETIONS))

(DEFCOM COM-LIST-TAG-TABLES "List the names of all the tag table files read in" ()
  (DOLIST (TAG-TABLE *ZMACS-TAG-TABLE-ALIST*)
    (FORMAT T "~&~4TFiles in tag table ~A:~%" (CAR TAG-TABLE))
    (SEND *STANDARD-OUTPUT* :ITEM-LIST 'FILE
	  (SEND (CDR TAG-TABLE) :GET 'ZMACS-TAG-TABLE-FILE-SYMBOLS)))
  (FORMAT T "~&Done.~%")
  DIS-NONE)

(DEFCOM COM-NEXT-FILE "Move to the next file in the tags table" ()
  (NEXT-FILE *NUMERIC-ARG-P*)
  DIS-TEXT)

(DEFVAR *ZMACS-LAST-TAGS-FILE-LIST* NIL
  "List of pathnames of files for NEXT-FILE to go through.")

(DEFUN NEXT-FILE (RESTART &AUX PATHNAME BUFFER)
  "Select the next file in the selected tag table.
RESTART non-NIL means select the first file in the tag table
and reset the list of files to be gone through."
  (AND RESTART
       (SETQ *ZMACS-LAST-TAGS-FILE-LIST*
	     (SEND (SELECT-TAG-TABLE) :GET 'ZMACS-TAG-TABLE-FILE-SYMBOLS)))
  (OR *ZMACS-LAST-TAGS-FILE-LIST* (BARF "No more files"))
  (POP *ZMACS-LAST-TAGS-FILE-LIST* PATHNAME)
  (COND ((SETQ BUFFER (FIND-FILE-BUFFER PATHNAME))
	 (FORMAT *QUERY-IO* "~&~A~%" PATHNAME)
	 (MAKE-BUFFER-CURRENT BUFFER)
	 (MOVE-BP (POINT) (INTERVAL-FIRST-BP *INTERVAL*)))
	(T
	 (FIND-FILE PATHNAME))))

(DEFUN NEXT-FILE-BP (RESTART &AUX PATHNAME BUFFER)
  "Return BP to start of the next file in the selected tag table.
RESTART non-NIL means start again at first file in tag table."
  (AND RESTART
       (SETQ *ZMACS-LAST-TAGS-FILE-LIST*
	     (SEND (SELECT-TAG-TABLE) :GET 'ZMACS-TAG-TABLE-FILE-SYMBOLS)))
  (OR *ZMACS-LAST-TAGS-FILE-LIST* (BARF "No more files"))
  (POP *ZMACS-LAST-TAGS-FILE-LIST* PATHNAME)
  (COND ((SETQ BUFFER (FIND-FILE-BUFFER PATHNAME))
	 (FORMAT *QUERY-IO* "~&~A~%" PATHNAME)
	 (INTERVAL-FIRST-BP BUFFER))
	(T
	 (INTERVAL-FIRST-BP (FIND-FILE PATHNAME NIL)))))

(DEFUN TAG-TABLE-BUFFERS (READ-IN-ALL-FILES &AUX BUFFER-LIST FILE-LIST)
  "Return a list of all buffers in the selected tag table.
READ-IN-ALL-FILES means visit all the files;
otherwise, we return only the buffers for files already read in."
  (SETQ FILE-LIST (SEND (SELECT-TAG-TABLE) :GET 'ZMACS-TAG-TABLE-FILE-SYMBOLS))
  (DOLIST (FILE FILE-LIST)
    (LET ((BUFFER (FIND-FILE-BUFFER FILE)))
      (IF BUFFER (PUSH BUFFER BUFFER-LIST))
      (IF READ-IN-ALL-FILES (PUSH (FIND-FILE FILE NIL) BUFFER-LIST))))
  (NREVERSE BUFFER-LIST))

(DEFVAR *ZMACS-TAGS-SEARCH-KEY-STRING* "FOO")
(DEFVAR *ZMACS-TAGS-SEARCH-KEY*)
(DEFVAR *ZMACS-TAGS-SEARCH-FUNCTION*)

(DEFCOM COM-TAGS-SEARCH "Search for the specified string within files of the tags table" ()
  (LET ((*MINI-BUFFER-DEFAULT-STRING* *ZMACS-TAGS-SEARCH-KEY-STRING*))
    (MULTIPLE-VALUE-SETQ (*ZMACS-TAGS-SEARCH-FUNCTION* *ZMACS-TAGS-SEARCH-KEY*)
      (GET-EXTENDED-STRING-SEARCH-STRINGS NIL "Tags search:" *SEARCH-MINI-BUFFER-COMTAB*)))
  (SETQ *ZMACS-TAGS-SEARCH-KEY-STRING*
	(STRING-INTERVAL (WINDOW-INTERVAL (GET-SEARCH-MINI-BUFFER-WINDOW))))
  (COMMAND-STORE 'COM-TAGS-SEARCH-NEXT-OCCURRENCE #/. *ZMACS-COMTAB*)
  (MUST-REDISPLAY *WINDOW* DIS-TEXT)
  (TAGS-SEARCH-NEXT-OCCURRENCE T))


(DEFUN TAGS-SEARCH-ALTERNATIVE-STRINGS (&REST STRINGS)
  "Begin a tags search looking for any of STRINGS."
  (IF (= (LENGTH STRINGS) 1)
      (SETQ *ZMACS-TAGS-SEARCH-KEY-STRING* (CAR STRINGS)
	    *ZMACS-TAGS-SEARCH-KEY* (CAR STRINGS)
	    *ZMACS-TAGS-SEARCH-FUNCTION* 'SEARCH)
    (SETQ *ZMACS-TAGS-SEARCH-KEY* (COPYLIST STRINGS))
    (SETQ *ZMACS-TAGS-SEARCH-FUNCTION* 'FSM-SEARCH)
    (SETQ *ZMACS-TAGS-SEARCH-KEY-STRING*
	  (MAKE-ARRAY #o20 :TYPE ART-FAT-STRING :FILL-POINTER 0))
    (DO ((STRINGS STRINGS (CDR STRINGS)))
	((NULL STRINGS))
      (STRING-NCONC *ZMACS-TAGS-SEARCH-KEY-STRING*
		    (CAR STRINGS))
      (OR (NULL (CDR STRINGS))
	  (STRING-NCONC *ZMACS-TAGS-SEARCH-KEY-STRING*
			402))))
  (COMMAND-STORE 'COM-TAGS-SEARCH-NEXT-OCCURRENCE #/C-/. *ZMACS-COMTAB*)
  (MUST-REDISPLAY *WINDOW* DIS-TEXT)
  (TAGS-SEARCH-NEXT-OCCURRENCE T))

(DEFCOM COM-TAGS-SEARCH-NEXT-OCCURRENCE "Search for the next occurrence of search string" ()
  (TAGS-SEARCH-NEXT-OCCURRENCE NIL))

(DEFUN TAGS-SEARCH-NEXT-OCCURRENCE (RESTART)
  (DO ((BP)
       (PT (IF RESTART (NEXT-FILE-BP T) (POINT))))
      (NIL)
    (LET ((*INTERVAL* (BP-TOP-LEVEL-NODE PT)))
      (SETQ BP (FUNCALL *ZMACS-TAGS-SEARCH-FUNCTION* PT *ZMACS-TAGS-SEARCH-KEY*)))
    (COND (BP
	   (POINT-PDL-PUSH (POINT) *WINDOW*)
	   (MAKE-BUFFER-CURRENT (BP-TOP-LEVEL-NODE BP))
	   (MOVE-BP (POINT) BP)
	   (RETURN DIS-TEXT))
	  (T
	   (SETQ PT (NEXT-FILE-BP NIL))
	   (MUST-REDISPLAY *WINDOW* DIS-TEXT)))))

(DEFVAR *TAGS-QUERY-REPLACE-FROM*)
(DEFVAR *TAGS-QUERY-REPLACE-TO*)
(DEFVAR *TAGS-QUERY-REPLACE-DELIMITED*)

(DEFPROP COM-TAGS-QUERY-REPLACE KIND-OF-QUERY-REPLACE-DOCUMENTATION DOCUMENTATION-FUNCTION)
(DEFPROP COM-TAGS-QUERY-REPLACE T CONTROL-PERIOD)
(DEFCOM COM-TAGS-QUERY-REPLACE "Perform a query replace within the tags table files.
Does Query Replace over all the file in the selected tags table, one file at a time." ()
  (MULTIPLE-VALUE-SETQ (*TAGS-QUERY-REPLACE-FROM* *TAGS-QUERY-REPLACE-TO*)
    (QUERY-REPLACE-STRINGS NIL))
  (SETQ *TAGS-QUERY-REPLACE-DELIMITED* (AND *NUMERIC-ARG-P* *NUMERIC-ARG*))
  (COMMAND-STORE 'COM-CONTINUE-TAGS-QUERY-REPLACE #/. *ZMACS-COMTAB*)
  (CONTINUE-TAGS-QUERY-REPLACE T))

(DEFCOM COM-CONTINUE-TAGS-QUERY-REPLACE "Continue the last tags query replace" ()
  (CONTINUE-TAGS-QUERY-REPLACE NIL))

(DEFUN CONTINUE-TAGS-QUERY-REPLACE (RESTART)
  (DO ((BEGINNING RESTART)
       (VAL))
      (NIL)
    ;; Find the next buffer in the list which has an occurrence, select it.
    (DO (BP FOUND-AT) (())
      (SETQ BP (NEXT-FILE-BP BEGINNING))
      (SETQ BEGINNING NIL)
      (WHEN (LET ((*INTERVAL* (BP-TOP-LEVEL-NODE BP)))
	      (SETQ FOUND-AT (SEARCH BP *TAGS-QUERY-REPLACE-FROM*)))
	(POINT-PDL-PUSH (POINT) *WINDOW* NIL NIL)
	(MAKE-BUFFER-CURRENT (BP-TOP-LEVEL-NODE BP))
	;; Move bp to just before the occurrence, so we avoid
	;; re-scanning the part of the buffer already searched over.
	(MOVE-BP (POINT) (FORWARD-CHAR FOUND-AT (- (LENGTH *TAGS-QUERY-REPLACE-FROM*))))
	(RETURN)))
    (MUST-REDISPLAY *WINDOW* DIS-TEXT)
    ;; Query replace thru that buffer.
    (SETQ VAL (QUERY-REPLACE (POINT) (INTERVAL-LAST-BP *INTERVAL*)
			     *TAGS-QUERY-REPLACE-FROM* *TAGS-QUERY-REPLACE-TO*
			     *TAGS-QUERY-REPLACE-DELIMITED*))
    (AND (EQ VAL 'ABORTED) (RETURN DIS-TEXT))))

(DEFPROP COM-TAGS-MULTIPLE-QUERY-REPLACE KIND-OF-QUERY-REPLACE-DOCUMENTATION
	 DOCUMENTATION-FUNCTION)
(DEFPROP COM-TAGS-MULTIPLE-QUERY-REPLACE T CONTROL-PERIOD)
(DEFCOM COM-TAGS-MULTIPLE-QUERY-REPLACE "Perform a query replace within the tags table files"
	()
  (MULTIPLE-VALUE-BIND (FROM-LIST TO-LIST)
      (MULTIPLE-QUERY-REPLACE-STRINGS NIL)
    (TAGS-MULTIPLE-QUERY-REPLACE FROM-LIST TO-LIST (AND *NUMERIC-ARG-P* *NUMERIC-ARG*))))

(DEFPROP COM-TAGS-MULTIPLE-QUERY-REPLACE-FROM-BUFFER KIND-OF-QUERY-REPLACE-DOCUMENTATION
	 DOCUMENTATION-FUNCTION)
(DEFPROP COM-TAGS-MULTIPLE-QUERY-REPLACE-FROM-BUFFER T CONTROL-PERIOD)
(DEFCOM COM-TAGS-MULTIPLE-QUERY-REPLACE-FROM-BUFFER
	"Perform a multiple query replace from the contents of the specified buffer" ()
  (MULTIPLE-VALUE-BIND (FROM-LIST TO-LIST)
      (PARSE-BUFFER-REPLACE-PAIRS *INTERVAL*)
    (TAGS-MULTIPLE-QUERY-REPLACE FROM-LIST TO-LIST (AND *NUMERIC-ARG-P* *NUMERIC-ARG*))))

(DEFPROP COM-MULTIPLE-QUERY-REPLACE-FROM-BUFFER KIND-OF-QUERY-REPLACE-DOCUMENTATION
	 DOCUMENTATION-FUNCTION)
(DEFCOM COM-MULTIPLE-QUERY-REPLACE-FROM-BUFFER
	"Perform a multiple query replace from the contents of the specified buffer" ()
  (WITH-REGION-OR-WHOLE-INTERVAL (REGION-P)
    (LET ((*MODE-WORD-SYNTAX-TABLE* (IF (AND *NUMERIC-ARG-P* (MINUSP *NUMERIC-ARG*))
					*ATOM-WORD-SYNTAX-TABLE* *MODE-WORD-SYNTAX-TABLE*))
	  FROM-LIST TO-LIST)
      (MULTIPLE-VALUE-SETQ (FROM-LIST TO-LIST)
	(PARSE-BUFFER-REPLACE-PAIRS T))
      (QUERY-REPLACE-LIST (POINT) (INTERVAL-LAST-BP *INTERVAL*)
			  FROM-LIST TO-LIST *NUMERIC-ARG-P*)))
  DIS-TEXT)

(DEFUN TAGS-MULTIPLE-QUERY-REPLACE (FROM-LIST TO-LIST ARG)
  (SETQ *TAGS-QUERY-REPLACE-FROM* FROM-LIST
	*TAGS-QUERY-REPLACE-TO* TO-LIST
	*TAGS-QUERY-REPLACE-DELIMITED* ARG)
  (COMMAND-STORE 'COM-CONTINUE-TAGS-MULTIPLE-QUERY-REPLACE #/. *ZMACS-COMTAB*)
  (CONTINUE-TAGS-MULTIPLE-QUERY-REPLACE T))

(DEFCOM COM-CONTINUE-TAGS-MULTIPLE-QUERY-REPLACE "Continue the last tags query replace" ()
  (CONTINUE-TAGS-MULTIPLE-QUERY-REPLACE NIL))

(DEFUN CONTINUE-TAGS-MULTIPLE-QUERY-REPLACE (RESTART)
  (DO ((BEGINNING RESTART)
       (*MODE-WORD-SYNTAX-TABLE* (IF (AND *TAGS-QUERY-REPLACE-DELIMITED*
					  (MINUSP *TAGS-QUERY-REPLACE-DELIMITED*))
				*ATOM-WORD-SYNTAX-TABLE* *MODE-WORD-SYNTAX-TABLE*))
       (VAL))
      (NIL)
    ;; Find and select the next buffer that has an occurrence of any of the strings.
    (DO (BP) (())
      (SETQ BP (NEXT-FILE-BP BEGINNING))
      (SETQ BEGINNING NIL)
      (WHEN (LET ((*INTERVAL* (BP-TOP-LEVEL-NODE BP)))
	      (DOLIST (STR *TAGS-QUERY-REPLACE-FROM*)
		(IF (SEARCH BP STR) (RETURN T))))
	(POINT-PDL-PUSH (POINT) *WINDOW* NIL NIL)
	(MAKE-BUFFER-CURRENT (BP-TOP-LEVEL-NODE BP))
	(MOVE-BP (POINT) BP)
	(RETURN)))
    (MUST-REDISPLAY *WINDOW* DIS-TEXT)
    ;; Query replace thru that buffer.
    (SETQ VAL (QUERY-REPLACE-LIST (POINT) (INTERVAL-LAST-BP *INTERVAL*)
				  *TAGS-QUERY-REPLACE-FROM* *TAGS-QUERY-REPLACE-TO*
				  *TAGS-QUERY-REPLACE-DELIMITED*))
    (AND (EQ VAL 'ABORTED) (RETURN DIS-TEXT))))

(DEFCOM COM-SELECT-TAG-TABLE "Make a tag table current for commands like tags search" ()
  (SETQ *ZMACS-CURRENT-TAG-TABLE* (SELECT-TAG-TABLE NIL))
  DIS-NONE)

(DEFCOM COM-SELECT-SYSTEM-AS-TAG-TABLE "Make the files in a system behave like a tags file"
	()
  (LET ((SYSTEM-NAME (READ-SYSTEM-NAME "System to select as tag table:")))
    (SELECT-FILE-LIST-AS-TAG-TABLE
      (SI:SYSTEM-SOURCE-FILES SYSTEM-NAME SI:*SOURCE-FILE-TYPES* NIL NIL)
      SYSTEM-NAME))
  DIS-NONE)

(DEFUN SYSTEM-OF-PATHNAME (PATHNAME &OPTIONAL ALREADY-GENERIC)
  "Return the si:system defstruct for the system PATHNAME is in.
If none can be determined, return the one for the SYSTEM system.
ALREADY-GENERIC non-NIL says assume PATHNAME is already a generic pathname."
  ;;if there wasn't a pathname, return the SYSTEM system
  (IF (NULL PATHNAME) (SI:FIND-SYSTEM-NAMED "System")
      (LET* ((GENERIC-PATHNAME
	       (IF ALREADY-GENERIC PATHNAME (SEND PATHNAME :GENERIC-PATHNAME)))
	     (SYSTEMS (SEND GENERIC-PATHNAME :GET ':SYSTEMS)))
	;;if it wasn't defined as part of a system, use the SYSTEM system
	(IF (NULL SYSTEMS) (SI:FIND-SYSTEM-NAMED "System")
	  (SI:FIND-SYSTEM-NAMED (CAR SYSTEMS))))))

(DEFUN READ-SYSTEM-NAME (PROMPT
			 &OPTIONAL (DEFAULT (SYSTEM-OF-PATHNAME
					      (BUFFER-GENERIC-PATHNAME *INTERVAL*) T)))
  "Read a system name in the mini buffer, defaulting to DEFAULT.
Prompts with PROMPT (which should end with a colon and not mention the default).
DEFAULT defaults to a guess based on the current buffer."
  (LET ((SYSTEM-NAME (COMPLETING-READ-FROM-MINI-BUFFER
		       (IF DEFAULT
			   (FORMAT NIL "~A (Default ~A)" PROMPT (SI:SYSTEM-NAME DEFAULT))
			 PROMPT)
		       (SI:ALL-SYSTEMS-NAME-ALIST))))
    (IF (CONSP SYSTEM-NAME)
	(SETQ SYSTEM-NAME (CAR SYSTEM-NAME))
      (IF DEFAULT
	  (SETQ SYSTEM-NAME (SI:SYSTEM-NAME DEFAULT))
	(BARF)))
    SYSTEM-NAME))

(DEFCOM COM-SELECT-ALL-BUFFERS-AS-TAG-TABLE "Select all files currently read in as a tag table.
This causes commands such as Tags Search, Tags Query Replace, and
Tags Compile Changed Sections to look through all files now visited." ()
  (SELECT-FILE-LIST-AS-TAG-TABLE (LOOP FOR BUFFER IN *ZMACS-BUFFER-LIST*
				       AS FILE-ID = (BUFFER-FILE-ID BUFFER)
				       WHEN (OR (EQ FILE-ID T)
						(AND FILE-ID
						     (CONSP FILE-ID)
						     (NOT (NODE-SPECIAL-TYPE BUFFER))))
				       COLLECT (BUFFER-PATHNAME BUFFER))
				 "All buffers visiting files")
  DIS-NONE)

(DEFFLAVOR TAG-TABLE-DUMMY-FILE (NAME) (SI:PROPERTY-LIST-MIXIN)
  :INITTABLE-INSTANCE-VARIABLES
  :GETTABLE-INSTANCE-VARIABLES)

(DEFMETHOD (TAG-TABLE-DUMMY-FILE :PRINT-SELF) (STREAM IGNORE SLASHIFY-P)
  (IF SLASHIFY-P
      (SI:PRINTING-RANDOM-OBJECT (SELF STREAM) (PRINC NAME STREAM))
    (PRINC NAME STREAM)))

(DEFUN SELECT-FILE-LIST-AS-TAG-TABLE (FILE-LIST NAME)
  "Select a phony tag table named NAME consisting of the files in FILE-LIST.
This can be used to control commands such as Tags Search."
  (SETQ *ZMACS-CURRENT-TAG-TABLE* (MAKE-INSTANCE 'TAG-TABLE-DUMMY-FILE :NAME NAME))
  (SEND *ZMACS-CURRENT-TAG-TABLE* :PUTPROP
				  (MAPCAR #'(LAMBDA (X)
					      (FS:MERGE-PATHNAME-DEFAULTS
						X *PATHNAME-DEFAULTS*))
					  FILE-LIST)
				  'ZMACS-TAG-TABLE-FILE-SYMBOLS)
  (PUSH (CONS NAME *ZMACS-CURRENT-TAG-TABLE*) *ZMACS-TAG-TABLE-ALIST*))

(DEFUN SELECT-TAG-TABLE (&OPTIONAL (DEFAULT-P T))
  "Read a tag table name and return that tag table.
DEFAULT-P non-NIL (as it is if omitted) means if there is an
obvious default than just return it without asking the user at all."
  (COND ((NULL *ZMACS-TAG-TABLE-ALIST*)
	 (LET ((PATHNAME (READ-DEFAULTED-PATHNAME "Tag table:"
						    (PATHNAME-DEFAULTS) "TAGS")))
	   (READ-TAG-TABLE PATHNAME)
	   PATHNAME))
	((AND DEFAULT-P *ZMACS-CURRENT-TAG-TABLE*)
	 *ZMACS-CURRENT-TAG-TABLE*)
	((AND DEFAULT-P (NULL (CDR *ZMACS-TAG-TABLE-ALIST*)))
	 (CDAR *ZMACS-TAG-TABLE-ALIST*))
	(T
	 (LET ((TABLE (COMPLETING-READ-FROM-MINI-BUFFER "Tag table:"
							*ZMACS-TAG-TABLE-ALIST*)))
	   (COND ((EQUAL TABLE "")
		  (COND (*ZMACS-CURRENT-TAG-TABLE* *ZMACS-CURRENT-TAG-TABLE*)
			(T (BARF))))
		 (T
		  (CDR TABLE)))))))

(DEFUN PARSE-BUFFER-REPLACE-PAIRS (DEFAULT &AUX *INTERVAL*)
  "Parse a buffer as a list of string replacements.
Reads a buffer name from the user and parses that buffer.
Returns two values, a list of strings to replace and a list of replacement strings."
  (SETQ *INTERVAL* (READ-BUFFER-NAME "Use replacements in buffer:" DEFAULT))
  (DO ((BP (INTERVAL-FIRST-BP *INTERVAL*))
       (END-BP (INTERVAL-LAST-BP *INTERVAL*))
       (FROM-LIST) (TO-LIST) (TEM))
      (NIL)
    (SETQ BP (FORWARD-OVER *WHITESPACE-CHARS* BP))
    (AND (BP-= BP END-BP) (RETURN (NREVERSE FROM-LIST) (NREVERSE TO-LIST)))
    (IF (CHAR= (BP-CH-CHARACTER BP) #/;)
	(SETQ BP (BEG-LINE BP 1))
      (MULTIPLE-VALUE-SETQ (TEM BP)
	(PARSE-BUFFER-REPLACE-PAIRS-1 BP))
      (PUSH TEM FROM-LIST)
      (SETQ BP (FORWARD-OVER *BLANKS* BP))
      (AND (END-LINE-P BP) (BARF "Only one item on line ~S" (BP-LINE BP)))
      (MULTIPLE-VALUE-SETQ (TEM BP)
	(PARSE-BUFFER-REPLACE-PAIRS-1 BP))
      (PUSH TEM TO-LIST))))

(DEFUN PARSE-BUFFER-REPLACE-PAIRS-1 (BP &AUX BP1 STR)
  (OR (SETQ BP1 (FORWARD-SEXP BP)) (BARF "Premature eof on line ~S" (BP-LINE BP)))
  (SETQ STR (STRING-INTERVAL BP BP1 T))
  (AND (CHAR= (CHAR STR 0) #/")
       (SETQ STR (READ-FROM-STRING STR)))
  (VALUES STR BP1))

(TV:ADD-TYPEOUT-ITEM-TYPE *TYPEOUT-COMMAND-ALIST* FUNCTION-NAME "Arglist"
			  TYPEOUT-MENU-ARGLIST NIL
			  "Print arglist for this function.")

(DEFUN TYPEOUT-MENU-ARGLIST (FUNCTION)
  (FORMAT *QUERY-IO* "~&~S: ~A" FUNCTION (ARGLIST FUNCTION))
  T)                                            ;Leave the typeout window there

(DEFUN TYPEOUT-YES-OR-NO-P (&REST FORMAT-ARGS)
  "Ask the user Yes or No, printing in the typeout window."
  (LET ((*QUERY-IO* *STANDARD-OUTPUT*))
    (APPLY #'FQUERY '#,`(:TYPE :READLINE
			 :CHOICES ,FORMAT:YES-OR-NO-P-CHOICES)
	   FORMAT-ARGS)))

(TV:ADD-TYPEOUT-ITEM-TYPE *TYPEOUT-COMMAND-ALIST* BP "Move" MOVE-TO-BP T
			  "Move to this line.")

(DEFUN MOVE-TO-BP (BP &AUX INTERVAL)
  "Move point to BP, selecting its buffer if necessary."
  (AND (SETQ INTERVAL (BP-TOP-LEVEL-NODE BP))
       (NEQ INTERVAL *INTERVAL*)
       (PROGN (TYPEOUT-ABORT-MINI-BUFFER)
	      (MAKE-BUFFER-CURRENT INTERVAL)))
  (MOVE-BP (POINT) BP)
  NIL)

(TV:ADD-TYPEOUT-ITEM-TYPE *TYPEOUT-COMMAND-ALIST* FILE "Find" FIND-DEFAULTED-FILE T
			  "Find file this file.")

(DEFUN FIND-DEFAULTED-FILE (STRING &AUX PATHNAME VERSION)
  (TYPEOUT-ABORT-MINI-BUFFER)
  (SETQ PATHNAME (MAKE-DEFAULTED-PATHNAME (STRING STRING) (PATHNAME-DEFAULTS)))
  ;;It we get a specific file, see if that was the newest and if so, use that instead
  (AND (NOT (MEMQ (SETQ VERSION (SEND PATHNAME :VERSION)) '(:NEWEST :UNSPECIFIC)))
       (= VERSION (SEND (SEND (SEND PATHNAME :NEW-VERSION :NEWEST) :TRUENAME) :VERSION))
       (SETQ PATHNAME (SEND PATHNAME :NEW-VERSION :NEWEST)))
  (FIND-FILE PATHNAME))

(TV:ADD-TYPEOUT-ITEM-TYPE *TYPEOUT-COMMAND-ALIST* FILE "Load" LOAD-DEFAULTED-FILE NIL
			  "LOAD this file.")

(DEFUN LOAD-DEFAULTED-FILE (STRING)
  (LOAD (MAKE-DEFAULTED-PATHNAME (STRING STRING) (PATHNAME-DEFAULTS))))

(DEFCOM COM-EDIT-METHODS "Edit all methods for specified message." ()
  (MULTIPLE-VALUE-BIND (CLASSES-AND-FUNCTION-SYMBOLS MESSAGE)
      (LIST-METHODS-INTERNAL
	(READ-OPERATION-NAME "Edit classes and flavors with methods for"))
    (EDIT-FUNCTIONS-NO-DISPLAY ;; The printed-representation of each item is the flavor name,
			    ;; including package prefix if necessary, and the method type
			    ;; in parentheses.  The cdr (function-name)
			    ;; of each item is the mumble-class-mumble-method symbol.
			    (MAPCAR #'(LAMBDA (X)
					(CONS (FORMAT NIL "~S~@[ (:~A)~]" (CAR X) (CADR X))
					      (CADDR X)))
				    CLASSES-AND-FUNCTION-SYMBOLS)
			    "Classes and flavors with ~S methods:"
			    "No methods for ~S found."
			    MESSAGE)))

(DEFCOM COM-LIST-METHODS "List all classes and flavors with methods for specified message." ()
  (MULTIPLE-VALUE-BIND (CLASSES-AND-FUNCTION-SYMBOLS MESSAGE)
      (LIST-METHODS-INTERNAL
	(READ-OPERATION-NAME "List classes and flavors with methods for"))
    (EDIT-FUNCTIONS-DISPLAY ;; The printed-representation of each item is the flavor name,
			    ;; including package prefix if necessary, and the method type
			    ;; in parentheses.  The cdr (function-name)
			    ;; of each item is the mumble-class-mumble-method symbol.
			    (MAPCAR #'(LAMBDA (X)
					(CONS (FORMAT NIL "~S~@[ (:~A)~]" (CAR X) (CADR X))
					      (CADDR X)))
				    CLASSES-AND-FUNCTION-SYMBOLS)
			    "Classes and flavors with ~S methods:"
			    "No methods for ~S found."
			    MESSAGE))
  DIS-NONE)

(DEFUN LIST-METHODS-INTERNAL (OPERATION &AUX FL TEM)
  (LET ((CLASSES-AND-FUNCTION-SYMBOLS
	  (DO ((L (CONS OBJECT-CLASS (SI:ALL-SUBCLASSES-OF-CLASS OBJECT-CLASS)) (CDR L))
	       (R NIL)
	       (SYM))
	      ((NULL L) R)
	    (COND ((SETQ SYM (<- (CAR L) ':METHOD-FOR OPERATION NIL))
		   (PUSH (LIST (<- (CAR L) ':CLASS-SYMBOL) NIL SYM) R))))))
    (DOLIST (FLAVOR SI:*ALL-FLAVOR-NAMES*)
      (AND (SETQ FL (GET FLAVOR 'SI:FLAVOR))
	   (SETQ TEM (ASSQ OPERATION (SI:FLAVOR-METHOD-TABLE FL)))
	   (DOLIST (METH (CDDDR TEM))
	     (OR (EQ (SI:METH-METHOD-TYPE METH) ':COMBINED)
		 (AND (SI:METH-DEFINEDP METH)
		      (PUSH (LIST FLAVOR (SI:METH-METHOD-TYPE METH) (SI:METH-FUNCTION-SPEC METH))
			    CLASSES-AND-FUNCTION-SYMBOLS))))))
    (VALUES CLASSES-AND-FUNCTION-SYMBOLS OPERATION)))

(DEFF GET-MESSAGE-NAME 'READ-OPERATION-NAME)
(DEFUN READ-OPERATION-NAME (PROMPT)
  "Read an operation name in the minibuffer, prompting with PROMPT.
PROMPT should be a string ending in a colon, if you want a colon.
If point is inside a FUNCALL or similar function, a default
may be derived from it."
  (PKG-BIND SI:PKG-KEYWORD-PACKAGE	;So the colon can be omitted
    (MULTIPLE-VALUE-BIND (SYM STR)
	(READ-FUNCTION-NAME PROMPT
	  (LET ((FUN (RELEVANT-FUNCTION-NAME (POINT))))
	    (AND (MEMQ FUN '(FUNCALL LEXPR-FUNCALL SEND LEXPR-SEND
				     <- FUNCALL-SELF LEXPR-FUNCALL-SELF))
		 (RELEVANT-METHOD-NAME
		   (POINT) (IF (MEMQ FUN '(FUNCALL-SELF LEXPR-FUNCALL-SELF)) 1 2))))
	  NIL T)
      ;; Kludge around to not get screwed by completions to funny symbols
      ;; while still working if user points with the mouse
      (IF STR (CLI:READ-FROM-STRING STR) SYM))))

(DEFCOM COM-EDIT-COMBINED-METHODS
	"Edit all methods used for specified operation on specified flavor." ()
  (LIST-COMBINED-METHODS-INTERNAL "Edit" T)
  DIS-NONE)

(DEFCOM COM-LIST-COMBINED-METHODS
  "List all methods used for specified operation on specified flavor." ()
  (LIST-COMBINED-METHODS-INTERNAL "List" NIL)
  DIS-NONE)

(DEFUN LIST-COMBINED-METHODS-INTERNAL (OP JUST-EDIT &AUX MESSAGE FLAVOR METHODS)
  (SETQ MESSAGE (READ-OPERATION-NAME (FORMAT NIL "~A combined methods for operation" OP)))
  (SETQ FLAVOR (READ-FLAVOR-NAME (FORMAT NIL "~A combined methods for operation ~S on flavor"
					       OP MESSAGE)
			"You are typing the name of a flavor, to see its combined methods"))

  ;; Duplicates code from SETUP-ZMACS-CALLERS-TO-BE-EDITED in order to
  ;; put the methods in execution order rather than alphabetical order
  (SETQ METHODS (FIND-COMBINED-METHODS FLAVOR MESSAGE))
  (COMMAND-STORE 'COM-GO-TO-NEXT-TOP-LEVEL-POSSIBILITY #/C-/. *ZMACS-COMTAB*)
  ;; Duplicates code from LIST-ZMACS-CALLERS-TO-BE-EDITED in order to
  ;; put the methods in execution order rather than alphabetical order
  (FUNCALL (IF JUST-EDIT #'EDIT-FUNCTIONS-NO-DISPLAY #'EDIT-FUNCTIONS-DISPLAY)
	   (MAPCAR #'(LAMBDA (X) (CONS (FORMAT NIL "~S" X) X))
		   METHODS)
	   "Methods combined for operation ~S on flavor ~S:"
	   "No methods for operation ~S on flavor ~S."
	   MESSAGE FLAVOR))

(DEFUN FIND-COMBINED-METHODS (FLAVOR MESSAGE &OPTIONAL (ERROR T) &AUX FL SM METHOD)
  "Return a list of the non-combined methods involved in handling MESSAGE to FLAVOR"
  (BLOCK NIL
    (OR (SETQ FL (GET FLAVOR 'SI:FLAVOR))
	(IF ERROR (BARF "~S not DEFFLAVOR'ed" FLAVOR) (RETURN)))
    (OR (SI::FLAVOR-METHOD-HASH-TABLE FL)
	(IF (FQUERY NIL "~S's combined methods are not composed.  Compose them? "
		    FLAVOR)
	    (SI::RECOMPILE-FLAVOR FLAVOR NIL T NIL)
	  (IF ERROR (BARF "~S's methods are not composed" FLAVOR) (RETURN))))
    (SETQ METHOD
	  (IF (SI::FLAVOR-GET FL ':ABSTRACT-FLAVOR)
	      (AND (FDEFINEDP `(:METHOD ,FLAVOR :COMBINED ,MESSAGE))
		   (FDEFINITION `(:METHOD ,FLAVOR :COMBINED ,MESSAGE)))
	    (IGNORE-ERRORS
	      (SI::GET-FLAVOR-HANDLER-FOR FLAVOR MESSAGE))))
    (OR METHOD
	(IF ERROR
	    (BARF "Flavor ~S does not handle message ~S" FLAVOR MESSAGE)
	  (RETURN)))
    (SETQ METHOD (FUNCTION-NAME METHOD))
    (RETURN
      (COND ((SETQ SM
		   (CDDDR (OR (CADR (ASSQ 'SI::COMBINED-METHOD-DERIVATION
					  (DEBUGGING-INFO
					    (SI:UNENCAPSULATE-FUNCTION-SPEC METHOD))))
			      (SI:FUNCTION-SPEC-GET METHOD
						    'SI::COMBINED-METHOD-DERIVATION))))
	     (NCONC (REVERSE (CDR (ASSQ ':WRAPPER SM)))	;Try to approximate the order
		    (REVERSE (CDR (ASSQ ':BEFORE SM)))	;in which they're called
		    (REVERSE (CDR (ASSQ NIL SM)))
		    (COPYLIST (CDR (ASSQ ':AFTER SM)))
		    (MAPCAN #'(LAMBDA (X)
				(AND (NOT (MEMQ (CAR X) '(:WRAPPER :BEFORE NIL :AFTER)))
				     (REVERSE (CDR X))))
			    SM)))
	    (T (LIST METHOD))))))
