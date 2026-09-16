;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Readtable:ZL; Base:10; Cold-Load:T -*-

;;;---!!! While loading SYS2; DEFSEL QFASL during SI:QLD, barfs
;;;---!!!   somewhere around:
;;;---!!!	INTERNAL-FUNCTION-SPEC-HANDLER (2 arguments, local block origin 5) continue-pc #o165, d-return [#xE0095120]
;;;---!!!	  FDEFINEDP
;;;---!!!	  (INTERNAL DEFSELECT-MAKE-WHICH-OPERATIONS 0)

#|
;;;; Function spec and source file name stuff

;;; this stff used to be in various places in qrand and qmisc

;;; A function-specifier is just a way of talking about a function
;;; for purposes other than applying it.  It can be a symbol, in which case
;;; the function cell of the symbol is used.  Or it can be a list of one of
;;; these formats:
;;; (:METHOD class-name operation) refers to the method in that class for
;;;   that operation; this works for both Class methods and Flavor methods.
;;;   In the case of Flavor methods, the specification may also be of the form
;;;   (:METHOD flavor-name type operation).
;;; (:INSTANCE-METHOD exp operation).  exp should evaluate to an entity.
;;;   Reference is then to the operation directly on that instance.
;;; (:HANDLER flavor operation) refers to the function that is called when
;;;   an object of flavor FLAVOR is sent the message OPERATION.
;;; (:WITHIN within-function renamed-function) refers to renamed-function,
;;;   but only as called directly from within-function.
;;;   Actually, renamed-function is replaced throughout within-function
;;;   by an uninterned symbol whose definition is just renamed-function
;;;   as soon as an attempt is made to do anything to a function spec
;;;   of this form.  The function spec is from then on equivalent
;;;   to that uninterned symbol.
;;; (:PROPERTY symbol property) refers to (GET symbol property).
;;; (:LOCATION locative-or-list-pointer) refers to the CDR of the pointer.
;;;   This is for pointing at an arbitrary place
;;;   which there is no special way to describe.
;;; One place you can use a function specifier is in DEFUN.

;;; For Maclisp compatibility, a list whose car is not recognized is taken
;;; to be a list of a symbol and a property, by DEFUN and DEFMACRO.  They
;;; standardize this by putting :PROPERTY on the front.  These
;;; non-standard function specs are not accepted by the rest of the
;;; system.  This is done to avoid ambiguities and inconsistencies.

;;; The SYS:FUNCTION-SPEC-HANDLER property of a symbol, if present means that that
;;; symbol is legal as the car of a function spec.  The value of the property
;;; is a function whose arguments are the function in behalf
;;; of which to act (not a keyword symbol!) and the arguments to that
;;; function (the first of which is always the function spec).
;;; Functions are:
;;;	FDEFINE definition
;;;	FDEFINEDP
;;;	FDEFINITION
;;;	FDEFINITION-LOCATION
;;;	FUNDEFINE
;;;	FUNCTION-PARENT
;;;	COMPILER-FDEFINEDP -- returns T if will be fdefinedp at run time
;;;	GET indicator default
;;;	PUTPROP value indicator
;;;	REMPROP indicator
;;;	DWIMIFY original-spec def-decoder (see below, DWIMIFY-PACKAGE-2).

(DEFVAR INHIBIT-FDEFINE-WARNINGS NIL
  "T turns off warnings of redefining function in different file.
:JUST-WARN turns off queries, leaving just warnings.")

(DEFUN VALIDATE-FUNCTION-SPEC (FUNCTION-SPEC &AUX HANDLER)
  "Predicate for use with CHECK-ARG.  Returns non-nil if FUNCTION-SPEC really is one.
The value is the type of function spec (T for a symbol)."
  (COND ((ATOM FUNCTION-SPEC)
	 (SYMBOLP FUNCTION-SPEC))
	((AND (SYMBOLP (CAR FUNCTION-SPEC))
	      (SETQ HANDLER (GET (CAR FUNCTION-SPEC) 'FUNCTION-SPEC-HANDLER))
	      (FUNCALL HANDLER 'VALIDATE-FUNCTION-SPEC FUNCTION-SPEC))
	 (CAR FUNCTION-SPEC))))

(DEFUN FDEFINE (FUNCTION-SPEC DEFINITION &OPTIONAL CAREFULLY-FLAG NO-QUERY-FLAG
					 &AUX TYPE INNER-SPEC DEFINEDP)
  "Alter the function definition of a function specifier.
CAREFULLY-FLAG means preserve any tracing or advice,
and save the old definition, when possible.
This function returns T if it does define the function, or NIL if it does not.
If FDEFINE-FILE-PATHNAME is non-NIL, then it is the file which this definition
was read from, and we make a note of that fact when possible."

  ;; Get error if invalid fun spec.  Also find out whether defined.
  (SETQ DEFINEDP (FDEFINEDP FUNCTION-SPEC))
  (IF (CONSP FUNCTION-SPEC) (SETQ TYPE (CAR FUNCTION-SPEC)))

  ;; Record the source file name, if desired, and check for redefinition errors
  (COND ((OR (EQ TYPE :INTERNAL)
	     (RECORD-SOURCE-FILE-NAME FUNCTION-SPEC
				      (IF CAREFULLY-FLAG 'DEFUN 'ENCAPSULATION)
				      (OR NO-QUERY-FLAG (NOT CAREFULLY-FLAG)
					  (EQ INHIBIT-FDEFINE-WARNINGS T))))

	 ;; If there is a previous definition, save it (if desired).
	 ;; Also if it is encapsulated, set INNER-SPEC to the symbol
	 ;; which holds the real definition before encapsulation, and
	 ;; save that definition.
	 (COND ((AND DEFINEDP CAREFULLY-FLAG)
		(SETQ INNER-SPEC (UNENCAPSULATE-FUNCTION-SPEC FUNCTION-SPEC))
		(MULTIPLE-VALUE-BIND (DEFP DEFN)
		    (FDEFINEDP-AND-FDEFINITION INNER-SPEC)
		  (AND DEFP
		       (FUNCTION-SPEC-PUTPROP FUNCTION-SPEC DEFN :PREVIOUS-DEFINITION)))
		;; Carry over renamings from previous definition
		(AND (NEQ FUNCTION-SPEC INNER-SPEC)	;Skip it if no encapsulations.
		     (FBOUNDP 'RENAME-WITHIN-NEW-DEFINITION-MAYBE)
		     (SETQ DEFINITION (RENAME-WITHIN-NEW-DEFINITION-MAYBE FUNCTION-SPEC
									  DEFINITION))))
	       (T (SETQ INNER-SPEC FUNCTION-SPEC)))

	 ;; Now store the new definition in type-dependent fashion
	 (IF (SYMBOLP INNER-SPEC) (FSET INNER-SPEC DEFINITION)
	     (FUNCALL (GET TYPE 'FUNCTION-SPEC-HANDLER) 'FDEFINE INNER-SPEC DEFINITION))

	 ;; Return T since we did define the function
	 T)
	;; Return NIL since we decided not to define the function
	(T NIL)))

;;; Is a function specifier defined?  A generalization of FBOUNDP.
(DEFUN FDEFINEDP (FUNCTION-SPEC &AUX HANDLER)
  "Returns T if the function spec has a function definition."
  ;; Then perform type-dependent code
  (COND ((SYMBOLP FUNCTION-SPEC) (FBOUNDP FUNCTION-SPEC))
	((AND (CONSP FUNCTION-SPEC)
	      (SETQ HANDLER (GET (CAR FUNCTION-SPEC) 'FUNCTION-SPEC-HANDLER)))
	 (FUNCALL HANDLER 'FDEFINEDP FUNCTION-SPEC))
	(T (FERROR 'SYS:INVALID-FUNCTION-SPEC
		   "The function spec ~S is invalid." FUNCTION-SPEC))))

;;; Get the definition of a function specifier.  Generalized FSYMEVAL.
(DEFUN FDEFINITION (FUNCTION-SPEC &AUX HANDLER)
  "Returns the function definition of a function spec"
  ;; First, validate the function spec.
  (SETQ FUNCTION-SPEC (DWIMIFY-ARG-PACKAGE FUNCTION-SPEC 'FUNCTION-SPEC))
  (COND ((SYMBOLP FUNCTION-SPEC) (SYMBOL-FUNCTION FUNCTION-SPEC))
	((AND (CONSP FUNCTION-SPEC)
	      (SETQ HANDLER (GET (CAR FUNCTION-SPEC) 'FUNCTION-SPEC-HANDLER)))
	 (FUNCALL HANDLER 'FDEFINITION FUNCTION-SPEC))
	(T (FERROR 'SYS:INVALID-FUNCTION-SPEC
		   "The function spec ~S is invalid." FUNCTION-SPEC))))

(DEFUN FDEFINEDP-AND-FDEFINITION (FUNCTION-SPEC &AUX HANDLER)
  "Returns whether the FUNCTION-SPEC is defined, and its definition if so.
The first value is T or NIL, the second is the definition if the first is T."
  ;; First, validate the function spec.
  (COND ((SYMBOLP FUNCTION-SPEC)
	 (IF (FBOUNDP FUNCTION-SPEC)
	     (VALUES T (SYMBOL-FUNCTION FUNCTION-SPEC))))
	((AND (CONSP FUNCTION-SPEC)
	      (SETQ HANDLER (GET (CAR FUNCTION-SPEC) 'FUNCTION-SPEC-HANDLER)))
	 (MULTIPLE-VALUE-BIND (DEFINEDP DEFN)
	     (FUNCALL HANDLER 'FDEFINEDP FUNCTION-SPEC)
	   (IF DEFINEDP
	       (VALUES T (OR DEFN (FDEFINITION FUNCTION-SPEC))))))
	(T (FERROR 'SYS:INVALID-FUNCTION-SPEC
		   "The function spec ~S is invalid." FUNCTION-SPEC))))

;;; This is useful for sorting function specs
(DEFUN FUNCTION-SPEC-LESSP (FS1 FS2)
  "Compares two function specs, approximately alphabetically."
  (STRING-LESSP (IF (SYMBOLP FS1) FS1 (SECOND FS1))
		(IF (SYMBOLP FS2) FS2 (SECOND FS2))))

(DEFUN FUNDEFINE (FUNCTION-SPEC)
  "Makes FUNCTION-SPEC not have a function definition."
  ;; First, validate the function spec and determine its type
  (SETQ FUNCTION-SPEC (DWIMIFY-ARG-PACKAGE FUNCTION-SPEC 'FUNCTION-SPEC))
  (IF (SYMBOLP FUNCTION-SPEC) (FMAKUNBOUND FUNCTION-SPEC)
      (FUNCALL (GET (CAR FUNCTION-SPEC) 'FUNCTION-SPEC-HANDLER) 'FUNDEFINE FUNCTION-SPEC)))

(DEFUN FDEFINITION-LOCATION (FUNCTION-SPEC &AUX HANDLER)
  "Returns a locative pointer to the cell containing FUNCTION-SPEC's definition."
  ;; First, validate the function spec and determine its type
  (COND ((SYMBOLP FUNCTION-SPEC) (LOCF (SYMBOL-FUNCTION FUNCTION-SPEC)))
	((AND (CONSP FUNCTION-SPEC)
	      (SETQ HANDLER (GET (CAR FUNCTION-SPEC) 'FUNCTION-SPEC-HANDLER)))
	 (FUNCALL HANDLER 'FDEFINITION-LOCATION FUNCTION-SPEC))
	(T (FERROR 'SYS:INVALID-FUNCTION-SPEC
		   "The function spec ~S is invalid." FUNCTION-SPEC))))

(DEFUN FUNCTION-PARENT (FUNCTION-SPEC &AUX DEF TEM)
  (DECLARE (VALUES NAME TYPE))
  "Returns NIL or the name of another definition which has the same source code.
The second value is the type of that definition (which can be NIL).
This is used for things like internal functions, methods automatically
created by a defflavor, and macros automatically created by a defstruct."
  (COND ((AND (FDEFINEDP FUNCTION-SPEC)
	      (SETQ TEM (CDR (ASSQ 'FUNCTION-PARENT
				   (DEBUGGING-INFO (SETQ DEF (FDEFINITION FUNCTION-SPEC))))))
	      ;; Don't get confused by circular function-parent pointers.
	      (NOT (EQUAL TEM FUNCTION-SPEC)))
	 (VALUES (CAR TEM) (CADR TEM)))
	;; for DEFSTRUCT
	((AND (EQ (CAR-SAFE DEF) 'MACRO)
	      (SYMBOLP (CDR DEF))
	      (SETQ DEF (GET (CDR DEF) 'MACROEXPANDER-FUNCTION-PARENT)))
	 (FUNCALL DEF FUNCTION-SPEC))
	((CONSP FUNCTION-SPEC)
	 (FUNCALL (GET (CAR FUNCTION-SPEC) 'FUNCTION-SPEC-HANDLER)
		  #'FUNCTION-PARENT FUNCTION-SPEC))))


;;; Default handler called by function-spec-handlers to do functions they don't
;;; handle specially.
(DEFUN FUNCTION-SPEC-DEFAULT-HANDLER (FUNCTION FUNCTION-SPEC &OPTIONAL ARG1 ARG2)
  "This subroutine handles various operations for other function spec handlers."
  (CASE FUNCTION
    (VALIDATE-FUNCTION-SPEC T)	;Used only during system build, via FUNCTION-SPEC-GET
    (FUNCTION-PARENT NIL)		;Default is no embedding in other definitions
    (COMPILER-FDEFINEDP NIL)		;Default is no remembering of compiled definitions
    (DWIMIFY NIL)
    (GET (IF FUNCTION-SPEC-HASH-TABLE
	     ;; Default is to use plist hash table
	     (WITH-STACK-LIST (KEY FUNCTION-SPEC ARG1)
	       (GETHASH KEY FUNCTION-SPEC-HASH-TABLE ARG2))
	   (LOOP FOR (FS IND PROP) IN COLD-LOAD-FUNCTION-PROPERTY-LISTS
		 WHEN (AND (EQUAL FS FUNCTION-SPEC) (EQ IND ARG1))
		 RETURN PROP
		 FINALLY (RETURN ARG2))))
    (PUTPROP (LET ((DEFAULT-CONS-AREA BACKGROUND-CONS-AREA)
		   (AREA (%AREA-NUMBER FUNCTION-SPEC)))
	       (IF (OR (AREA-TEMPORARY-P AREA)
		       (= AREA PDL-AREA))
		   (SETQ FUNCTION-SPEC (COPYTREE FUNCTION-SPEC)))
	       (IF FUNCTION-SPEC-HASH-TABLE
		   (SETF (GETHASH (LIST FUNCTION-SPEC ARG2) FUNCTION-SPEC-HASH-TABLE) ARG1)
		 (PUSH (LIST FUNCTION-SPEC ARG2 ARG1) COLD-LOAD-FUNCTION-PROPERTY-LISTS))))
    (REMPROP (IF FUNCTION-SPEC-HASH-TABLE
		 ;; Default is to use plist hash table
		 (WITH-STACK-LIST (KEY FUNCTION-SPEC ARG1)
		   (REMHASH KEY FUNCTION-SPEC-HASH-TABLE))
	       (LOOP FOR X IN COLD-LOAD-FUNCTION-PROPERTY-LISTS
		     WHEN (AND (EQUAL (CAR X) FUNCTION-SPEC)
			       (EQ (CADR X) ARG1))
		       (SETQ COLD-LOAD-FUNCTION-PROPERTY-LISTS
			     (DELQ X COLD-LOAD-FUNCTION-PROPERTY-LISTS))
		       (RETURN (CDDR X)))))     
    (PUSH-PROPERTY
     (WITH-STACK-LIST (KEY FUNCTION-SPEC ARG2)
       (PUSH ARG1 (GETHASH KEY FUNCTION-SPEC-HASH-TABLE))))
    (OTHERWISE (FERROR NIL "~S is not implemented by the function spec ~S"
		           FUNCTION FUNCTION-SPEC))))

;;; (:PROPERTY symbol property) refers to (GET symbol property).
;;; This has to be defined with a separate DEFPROP for reasons which should be obvious.
(DEFPROP :PROPERTY PROPERTY-FUNCTION-SPEC-HANDLER FUNCTION-SPEC-HANDLER)
(DEFUN PROPERTY-FUNCTION-SPEC-HANDLER (FUNCTION FUNCTION-SPEC &OPTIONAL ARG1 ARG2)
  (LET ((SYMBOL (SECOND FUNCTION-SPEC))
	(INDICATOR (THIRD FUNCTION-SPEC)))
    (IF (NOT (AND (= (LENGTH FUNCTION-SPEC) 3) (SYMBOLP SYMBOL)))
	(UNLESS (EQ FUNCTION 'VALIDATE-FUNCTION-SPEC)
	  (FERROR 'SYS:INVALID-FUNCTION-SPEC "Invalid function spec ~S." FUNCTION-SPEC))
      (CASE FUNCTION
	(VALIDATE-FUNCTION-SPEC T)
	(FDEFINE (SETF (GET SYMBOL INDICATOR) ARG1))
	((FDEFINITION FDEFINEDP) (GET SYMBOL INDICATOR))
	(FDEFINITION-LOCATION (LOCF (GET SYMBOL INDICATOR)))	;Not perfect, but close
	(FUNDEFINE (REMPROP SYMBOL INDICATOR))
	(DWIMIFY
	 (AND (SYMBOLP INDICATOR)
	      (MULTIPLE-VALUE-BIND (NEW-SYM DWIM-P)
		  (CATCH 'DWIMIFY-PACKAGE
		    (MAP-OVER-LOOKALIKE-SYMBOLS
		      (SYMBOL-NAME INDICATOR)
		      NIL
		      #'(LAMBDA (NEW-SYMBOL SPEC ORIGINAL-SPEC DWIMIFY-INFO)
			  (OR (EQ NEW-SYMBOL (CADDR SPEC))
			      (DWIMIFY-PACKAGE-2 `(,(CAR SPEC) ,(CADR SPEC) ,NEW-SYMBOL)
						 ORIGINAL-SPEC DWIMIFY-INFO T)))
		      FUNCTION-SPEC ARG1 ARG2))
		(AND DWIM-P NEW-SYM))))
	(OTHERWISE (FUNCTION-SPEC-DEFAULT-HANDLER FUNCTION FUNCTION-SPEC ARG1 ARG2))))))

;;; (:INTERNAL parent-function index) refers to the index'th unnamed
;;; broken-off lambda in the parent function.
;;; parent-function is normally a function-spec, but it may also be a FEF.
;;; Note that VALIDATE-FUNCTION-SPEC for :INTERNAL returns NIL if the
;;; function-spec itself is malformed, however if the spec is well-formed
;;; but the parent doesn't have internal functions, an error is signalled
;;; giving a detailed explanation.
(DEFPROP :INTERNAL INTERNAL-FUNCTION-SPEC-HANDLER FUNCTION-SPEC-HANDLER)
(DEFUN INTERNAL-FUNCTION-SPEC-HANDLER (FUNCTION FUNCTION-SPEC &OPTIONAL ARG1 ARG2)
  (LET ((PARENT (SECOND FUNCTION-SPEC))
	(INDEX (THIRD FUNCTION-SPEC))
	DIRECT-FEF)
    (SETQ DIRECT-FEF (TYPEP PARENT 'COMPILED-FUNCTION))
    (IF (NOT (AND (OR (AND (FIXNUMP INDEX) (NOT (MINUSP INDEX)))
		      (SYMBOLP INDEX))
		  (= (LENGTH FUNCTION-SPEC) 3)))
	(UNLESS (EQ FUNCTION 'VALIDATE-FUNCTION-SPEC)
	  (FERROR 'SYS:INVALID-FUNCTION-SPEC
		  "The function spec ~S is invalid." FUNCTION-SPEC))
      (IF (EQ FUNCTION 'VALIDATE-FUNCTION-SPEC)
	  (OR DIRECT-FEF
	      (AND (VALIDATE-FUNCTION-SPEC PARENT) (FDEFINEDP PARENT)))
	(LET ((FEF (IF DIRECT-FEF PARENT
		     (FDEFINITION (UNENCAPSULATE-FUNCTION-SPEC PARENT))))
	      TABLE OFFSET LOCAL-FUNCTION-MAP DEBUGGING-INFO)
	  (WHEN (EQ (CAR-SAFE FEF) 'MACRO)
	    (SETQ FEF (CDR FEF)))
	  (UNLESS (TYPEP FEF 'COMPILED-FUNCTION)
	    (FERROR 'SYS:INVALID-FUNCTION-SPEC
		    "The function spec ~S refers to ~S, which is not a FEF"
		    FUNCTION-SPEC FEF))
	  (SETQ DEBUGGING-INFO (FEF-DEBUGGING-INFO FEF)
		TABLE (CDR (ASSQ ':INTERNAL-FEF-OFFSETS DEBUGGING-INFO))
		LOCAL-FUNCTION-MAP (CADR (ASSQ 'COMPILER::LOCAL-FUNCTION-MAP DEBUGGING-INFO)))
	  (UNLESS TABLE
	    (FERROR 'SYS:INVALID-FUNCTION-SPEC
		    "The function spec ~S refers to ~S, which has no internal functions"
		    FUNCTION-SPEC FEF))
	  (WHEN (SYMBOLP INDEX)
	    (UNLESS (MEMQ INDEX LOCAL-FUNCTION-MAP)
	      (FERROR 'SYS:INVALID-FUNCTION-SPEC
		      "The function spec ~S refers to a non-existent internal function"
		      FUNCTION-SPEC))
	    (SETQ INDEX (POSITION INDEX LOCAL-FUNCTION-MAP)))		
	  (UNLESS (SETQ OFFSET (NTH INDEX TABLE))
	    (FERROR 'SYS:INVALID-FUNCTION-SPEC
		    "The function spec ~S is out of range" FUNCTION-SPEC))
	  
	  ;; Function spec fully parsed, we can now earn our living
	  (CASE FUNCTION
	    (VALIDATE-FUNCTION-SPEC T)
	    (FDEFINE (LET ((%INHIBIT-READ-ONLY T))
		       (%P-STORE-CONTENTS-OFFSET ARG1 FEF OFFSET)))
	    (FDEFINITION (%P-CONTENTS-OFFSET FEF OFFSET))
	    (FDEFINEDP		;Random: look for what the compiler puts there initially
	     (NOT (EQUAL (%P-CONTENTS-OFFSET FEF OFFSET) FUNCTION-SPEC)))
	    (FDEFINITION-LOCATION (%MAKE-POINTER-OFFSET DTP-LOCATIVE FEF OFFSET))
	    (FUNCTION-PARENT (VALUES PARENT 'DEFUN))
	    (OTHERWISE (FUNCTION-SPEC-DEFAULT-HANDLER FUNCTION FUNCTION-SPEC ARG1 ARG2))))))))


;;; This is setup by QLD as soon as everything it will need is loaded in and pathnames work
;;; and so on.
(DEFVAR FUNCTION-SPEC-HASH-TABLE NIL)
;;; In the meantime, and from the cold load, this remembers non symbol source files,
;;; elements are (function-spec indicator value).
(DEFVAR COLD-LOAD-FUNCTION-PROPERTY-LISTS)

(DEFUN FUNCTION-SPEC-PUTPROP (FUNCTION-SPEC VALUE PROPERTY)
  "Put a PROPERTY property with value VALUE on FUNCTION-SPEC.
For symbols, this is just PUTPROP, but it works on any function spec."
  (IF (SYMBOLP FUNCTION-SPEC)
      (SETF (GET FUNCTION-SPEC PROPERTY) VALUE)
    (LET ((HFUN (IF (NULL FUNCTION-SPEC-HASH-TABLE)
		    ;; While loading files with MINI during system build,
		    ;; always use the default handler,
		    ;; which stores on COLD-LOAD-FUNCTION-PROPERTY-LISTS.
		    ;; This is so that the property's pathnames will be canonicalized later.
		    'FUNCTION-SPEC-DEFAULT-HANDLER
		  (AND (CONSP FUNCTION-SPEC)
		       (SYMBOLP (CAR FUNCTION-SPEC))
		       (GET (CAR FUNCTION-SPEC) 'FUNCTION-SPEC-HANDLER)))))
      (IF HFUN
	  (FUNCALL HFUN 'PUTPROP FUNCTION-SPEC VALUE PROPERTY)
	(FERROR 'SYS:INVALID-FUNCTION-SPEC "The function spec ~S is invalid."
		FUNCTION-SPEC)))))

(DEFUN FUNCTION-SPEC-PUSH-PROPERTY (FUNCTION-SPEC VALUE PROPERTY)
  "PUSH VALUE onto the PROPERTY property of FUNCTION-SPEC.
Like (PUSH VALUE (FUNCTION-SPEC-GET FUNCTION-SPEC PROPERTY)) but faster."
  (IF (SYMBOLP FUNCTION-SPEC)
      (SETF (GET FUNCTION-SPEC PROPERTY) (CONS VALUE (GET FUNCTION-SPEC PROPERTY)))
    (LET ((HFUN (IF (NULL FUNCTION-SPEC-HASH-TABLE)
		    ;; While loading files with MINI during system build,
		    ;; always use the default handler,
		    ;; which stores on COLD-LOAD-FUNCTION-PROPERTY-LISTS.
		    ;; This is so that the property's pathnames will be canonicalized later.
		    'FUNCTION-SPEC-DEFAULT-HANDLER
		  (AND (CONSP FUNCTION-SPEC)
		       (SYMBOLP (CAR FUNCTION-SPEC))
		       (GET (CAR FUNCTION-SPEC) 'FUNCTION-SPEC-HANDLER)))))
      (IF HFUN
	  (FUNCALL HFUN 'PUSH-PROPERTY FUNCTION-SPEC VALUE PROPERTY)
	(FERROR 'SYS:INVALID-FUNCTION-SPEC "The function spec ~S is invalid."
		FUNCTION-SPEC)))))

(DEFUN FUNCTION-SPEC-GET (FUNCTION-SPEC PROPERTY &OPTIONAL DEFAULT)
  "Get the PROPERTY property of FUNCTION-SPEC.
For symbols, this is just GET, but it works on any function spec."
  (IF (SYMBOLP FUNCTION-SPEC)
      (GET FUNCTION-SPEC PROPERTY DEFAULT)
    ;; Look for a handler for this type of function spec.
    (LET ((HFUN
	    (IF (NULL FUNCTION-SPEC-HASH-TABLE)
		;; While loading files with MINI during system build,
		;; always use the default handler,
		;; which stores on COLD-LOAD-FUNCTION-PROPERTY-LISTS.
		;; This is so that the property's pathnames will be canonicalized later.
		'FUNCTION-SPEC-DEFAULT-HANDLER
	      (AND (CONSP FUNCTION-SPEC)
		   (SYMBOLP (CAR FUNCTION-SPEC))
		   (GET (CAR FUNCTION-SPEC) 'FUNCTION-SPEC-HANDLER)))))
      (IF HFUN
	  (AND (FUNCALL HFUN 'VALIDATE-FUNCTION-SPEC FUNCTION-SPEC)
	       ;;previous line avoids lossage when compiling defselects which aren't present
	       ;; in run time environment (yet), for example.		
	       (FUNCALL HFUN 'GET FUNCTION-SPEC PROPERTY DEFAULT))
	(FERROR 'SYS:INVALID-FUNCTION-SPEC "The function spec ~S is invalid."
		FUNCTION-SPEC)))))

(DEFUN FUNCTION-SPEC-REMPROP (FUNCTION-SPEC PROPERTY &OPTIONAL DEFAULT)
  "Get the PROPERTY property of FUNCTION-SPEC.
For symbols, this is just GET, but it works on any function spec."
  (IF (SYMBOLP FUNCTION-SPEC)
      (REMPROP FUNCTION-SPEC PROPERTY)
    ;; Look for a handler for this type of function spec.
    (LET ((HFUN (IF (NULL FUNCTION-SPEC-HASH-TABLE)
		    ;; While loading files with MINI during system build,
		    ;; always use the default handler,
		    ;; which stores on COLD-LOAD-FUNCTION-PROPERTY-LISTS.
		    ;; This is so that the property's pathnames will be canonicalized later.
		    'FUNCTION-SPEC-DEFAULT-HANDLER
		  (AND (CONSP FUNCTION-SPEC)
		       (SYMBOLP (CAR FUNCTION-SPEC))
		       (GET (CAR FUNCTION-SPEC) 'FUNCTION-SPEC-HANDLER)))))
      (IF HFUN
	  (AND (FUNCALL HFUN 'VALIDATE-FUNCTION-SPEC FUNCTION-SPEC)
	       ;;previous line avoids lossage when compiling defselects which aren't present
	       ;; in run time environment (yet), for example.		
	       (FUNCALL HFUN 'REMPROP FUNCTION-SPEC PROPERTY DEFAULT))
	(FERROR 'SYS:INVALID-FUNCTION-SPEC "The function spec ~S is invalid."
		FUNCTION-SPEC)))))


(SETQ FS:THIS-IS-A-PATCH-FILE NIL)	;For the cold load

(DEFVAR FDEFINE-FILE-PATHNAME NIL
  "Generic pathname of source file being loaded or evaluated, or NIL.")

(DEFVAR PATCH-SOURCE-FILE-NAMESTRING NIL
  "While loading a patch, holds namestring of generic pathname of the source of the patch.")

;;; If the above is not NIL, this variable accumulates a list of all function specs defined.
(DEFVAR FDEFINE-FILE-DEFINITIONS NIL
  "List of definitions made while loading this source file.")

(DEFVAR NON-FILE-REDEFINED-FUNCTIONS NIL
  "Functions from files redefined from the keyboard and confirmed by the user.")

;;; A :SOURCE-FILE-NAME property is a single pathname for DEFUN of a single file,
;;; or ((type . files) (type . files) ...).
;;; Value returned indicates whether to go ahead with the definition.
(DEFUN RECORD-SOURCE-FILE-NAME (FUNCTION-SPEC
				&OPTIONAL (TYPE 'DEFUN)
					  (NO-QUERY (EQ INHIBIT-FDEFINE-WARNINGS T))
				&AUX (DEFAULT-CONS-AREA BACKGROUND-CONS-AREA))
  "Record a definition of FUNCTION-SPEC, of type TYPE, in the current source file.
The source file's generic-pathname is found in FDEFINE-FILE-PATHNAME.
FUNCTION-SPEC is actually only a function spec if TYPE is 'DEFUN,
which is the default.  If TYPE is 'DEFVAR, the first arg is a variable name, etc.
NO-QUERY inhibits warnings about redefinition in a different file.

The value is T if you should go ahead and perform the definition,
NIL if the user was asked and said no."
  ;; When defining a function in a patch, record it as coming
  ;; from its real source file.  So the editor knows where to find it.
  (IF (AND FS:THIS-IS-A-PATCH-FILE PATCH-SOURCE-FILE-NAMESTRING)
      (LET* ((FDEFINE-FILE-DEFINITIONS NIL)
	     (FDEFINE-FILE-PATHNAME
	       (SEND (FS:PARSE-PATHNAME PATCH-SOURCE-FILE-NAMESTRING) :GENERIC-PATHNAME))
	     (PATCH-SOURCE-FILE-NAMESTRING NIL)
	     (PKG-SPEC (SEND FDEFINE-FILE-PATHNAME :GET :PACKAGE))
	     (*PACKAGE* (OR (PKG-FIND-PACKAGE PKG-SPEC :FIND) *PACKAGE*)))
	;; Record the source file as having defined this function.
	;; THIS-IS-A-PATCH-FILE is still set, to prevent querying,
	;; but PATCH-SOURCE-FILE-NAMESTRING is not, so we don't recurse forever.
	(RECORD-SOURCE-FILE-NAME FUNCTION-SPEC TYPE NO-QUERY)
	;; Add the function to the source's list of definitions.
	(RECORD-FILE-DEFINITIONS FDEFINE-FILE-PATHNAME FDEFINE-FILE-DEFINITIONS
				 NIL FDEFINE-FILE-PATHNAME)))
  (LET ((PATHNAME FDEFINE-FILE-PATHNAME)
	(DEF (CONS-IN-AREA FUNCTION-SPEC TYPE BACKGROUND-CONS-AREA))
	(PROPERTY (FUNCTION-SPEC-GET FUNCTION-SPEC :SOURCE-FILE-NAME)))
    (OR (NULL FDEFINE-FILE-PATHNAME)
	(MEMBER DEF FDEFINE-FILE-DEFINITIONS)
	(SETQ FDEFINE-FILE-DEFINITIONS
	      (CONS-IN-AREA DEF FDEFINE-FILE-DEFINITIONS BACKGROUND-CONS-AREA)))
    (COND ((AND (NULL PROPERTY)			;Check most common case first
		(EQ TYPE 'DEFUN))
	   ;; We don't record the keyboard as a "source file"
	   ;; so things like the editor don't get confused.
	   (IF FDEFINE-FILE-PATHNAME
	       (FUNCTION-SPEC-PUTPROP FUNCTION-SPEC PATHNAME :SOURCE-FILE-NAME))
	   T)
	  ((IF (ATOM PROPERTY)
	       (AND (EQ TYPE 'DEFUN) (EQ PATHNAME PROPERTY))
	     (EQ PATHNAME (CADR (ASSQ TYPE PROPERTY))))
	   T)					;This pathname already known
	  (T
	   (AND PROPERTY (ATOM PROPERTY)
		(SETQ PROPERTY `((DEFUN ,PROPERTY))))
	   (LET ((THIS-TYPE (ASSQ TYPE PROPERTY))
		 (OLD-FILE))
	     (COND ((COND ((NULL THIS-TYPE)
			   (IF FDEFINE-FILE-PATHNAME
			       (SETQ THIS-TYPE `(,TYPE)
				     PROPERTY (NCONC PROPERTY
						     (NCONS THIS-TYPE))))
			   T)
			  (NO-QUERY T)
			  (FS:THIS-IS-A-PATCH-FILE T)
			  ((AND (NOT FDEFINE-FILE-PATHNAME)
				(MEMBER FUNCTION-SPEC NON-FILE-REDEFINED-FUNCTIONS))
			   ;; If user has ever confirmed redefining this fn from the kbd,
			   ;; it is ok to do so again.
			   T)
			  ;; Before format is loaded, don't bomb out trying to query.
			  ((NOT (FBOUNDP 'FQUERY)) T)
			  ;; If all the old definitions are from patch files, don't query.
			  ((NULL (SETQ OLD-FILE
				       (LOOP FOR FILE IN (CDR THIS-TYPE)
					     UNLESS (OR (STRINGP FILE)	;During QLD
							(SEND FILE :GET :PATCH-FILE))
					     RETURN FILE)))
			   T)
			  ((QUERY-ABOUT-REDEFINITION FUNCTION-SPEC PATHNAME TYPE
						     OLD-FILE)
			   ;; Though we don't record the keyboard as a "source file",
			   ;; once the user confirms redefining a certain function
			   ;; from the keyboard, we don't ever ask about it again.
			   (UNLESS FDEFINE-FILE-PATHNAME
			     (PUSH FUNCTION-SPEC NON-FILE-REDEFINED-FUNCTIONS))
			   T))
		    ;; We don't record the keyboard as a "source file"
		    ;; so things like the editor don't get confused.
		    (WHEN FDEFINE-FILE-PATHNAME
		      (SETF (CDR THIS-TYPE)
			    (CONS PATHNAME (DELQ PATHNAME (CDR THIS-TYPE))))
		      (FUNCTION-SPEC-PUTPROP FUNCTION-SPEC PROPERTY :SOURCE-FILE-NAME))
		    T)
		   (T NIL)))))))

;;; (:LOCATION locative-or-list-pointer) refers to the CDR of the pointer.
;;; This is for pointing at an arbitrary place which there is no special
;;; way to describe.
(DEFPROP :LOCATION LOCATION-FUNCTION-SPEC-HANDLER FUNCTION-SPEC-HANDLER)
(DEFUN LOCATION-FUNCTION-SPEC-HANDLER (FUNCTION FUNCTION-SPEC &OPTIONAL ARG1 ARG2)
  (LET ((LOC (SECOND FUNCTION-SPEC)))
    (IF (NOT (AND (= (LENGTH FUNCTION-SPEC) 2)
		  (OR (= (%DATA-TYPE LOC) DTP-LOCATIVE)
		      (= (%DATA-TYPE LOC) DTP-LIST))))
	(UNLESS (EQ FUNCTION 'VALIDATE-FUNCTION-SPEC)
	  (FERROR 'SYS:INVALID-FUNCTION-SPEC
		  "The function spec ~S is invalid." FUNCTION-SPEC))
      (CASE FUNCTION
	(VALIDATE-FUNCTION-SPEC T)
	(FDEFINE (RPLACD LOC ARG1))
	(FDEFINITION (CDR LOC))
	(FDEFINEDP (AND ( (%P-DATA-TYPE LOC) DTP-NULL) (NOT (NULL (CDR LOC)))))
	(FDEFINITION-LOCATION LOC)
	;; FUNDEFINE could store DTP-NULL, which would only be right sometimes
	(OTHERWISE (FUNCTION-SPEC-DEFAULT-HANDLER FUNCTION FUNCTION-SPEC ARG1 ARG2))))))

;;; Convert old Maclisp-style property function specs
(DEFUN STANDARDIZE-FUNCTION-SPEC (FUNCTION-SPEC &OPTIONAL (ERRORP T))
  (AND (CONSP FUNCTION-SPEC)
       (= (LENGTH FUNCTION-SPEC) 2)
       (SYMBOLP (CAR FUNCTION-SPEC))
       (NOT (GET (CAR FUNCTION-SPEC) 'FUNCTION-SPEC-HANDLER))
       (SETQ FUNCTION-SPEC (CONS ':PROPERTY FUNCTION-SPEC)))
  (OR (NOT ERRORP)
      (VALIDATE-FUNCTION-SPEC FUNCTION-SPEC)
      (FERROR 'SYS:INVALID-FUNCTION-SPEC "~S is not a valid function spec." FUNCTION-SPEC))
  FUNCTION-SPEC)


(DEFPROP DEFUN "Function" DEFINITION-TYPE-NAME)
(DEFPROP DEFVAR "Variable" DEFINITION-TYPE-NAME)
(DEFPROP ENCAPSULATION "encapsulation" DEFINITION-TYPE-NAME)

(DEFVAR NON-PATHNAME-REDEFINED-FILES NIL
  "Files whose functions it is ok to redefine from the keyboard.")

;;; Query about any irregularities about redefining the given function symbol now.
;;; Return T to tell caller to go ahead and redefine the symbol
;;; (no problems or user says ok), NIL to leave it unchanged.
(DEFUN QUERY-ABOUT-REDEFINITION (FUNCTION-SPEC NEW-PATHNAME TYPE OLD-PATHNAME)
  ;; Detect any cross-file redefinition worth complaining about.
  (IF (OR (EQ (IF (STRINGP OLD-PATHNAME)
		  OLD-PATHNAME
		(AND OLD-PATHNAME (SEND OLD-PATHNAME :TRANSLATED-PATHNAME)))
	      (IF (STRINGP NEW-PATHNAME)
		  NEW-PATHNAME
		(AND NEW-PATHNAME (SEND NEW-PATHNAME :TRANSLATED-PATHNAME))))
	  (MEMQ OLD-PATHNAME
		(IF NEW-PATHNAME
		    (SEND NEW-PATHNAME :GET :REDEFINES-FILES)
		  NON-PATHNAME-REDEFINED-FILES)))
      T
    ;; This redefinition deserves a warning or query.
    ;; If it is within a file operation with warnings,
    ;; record a warning.
    (WHEN (AND (VARIABLE-BOUNDP FILE-WARNINGS-DATUM) FILE-WARNINGS-DATUM)
      (RECORD-AND-PRINT-WARNING 'REDEFINITION :PROBABLE-ERROR NIL
	(IF NEW-PATHNAME
	    "~A ~S being redefined by file ~A.
 It was previously defined by file ~A."
	  "~A ~S being redefined;~* it was previously defined by file ~A.")
	(OR (GET TYPE 'DEFINITION-TYPE-NAME) TYPE) FUNCTION-SPEC
	NEW-PATHNAME OLD-PATHNAME))
    (LET (CONDITION CHOICE)
      (SETQ CONDITION
	    (MAKE-CONDITION 'SYS:REDEFINITION
	      (IF NEW-PATHNAME
		  "~A ~S being redefined by file ~A.
It was previously defined by file ~A."
		"~A ~S being redefined;~* it was previously defined by file ~A.")
	      (OR (GET TYPE 'DEFINITION-TYPE-NAME) TYPE)
	      FUNCTION-SPEC
	      NEW-PATHNAME OLD-PATHNAME))
      (SETQ CHOICE (SIGNAL CONDITION))
      (UNLESS CHOICE
	(UNLESS (AND INHIBIT-FDEFINE-WARNINGS
		     (NEQ INHIBIT-FDEFINE-WARNINGS :JUST-WARN))
	  (FORMAT *QUERY-IO* "~&~A" CONDITION))
	(IF INHIBIT-FDEFINE-WARNINGS
	    (SETQ CHOICE T)
	  (SETQ CHOICE
		(FQUERY '(:CHOICES (((ERROR "Error.") #/E)
				    ((PROCEED "Proceed.") #/P)
				    . #.FORMAT:Y-OR-N-P-CHOICES)
				   :HELP-FUNCTION
				   (LAMBDA (STREAM &REST IGNORE)
				     (PRINC "
  Type Y to proceed to redefine the function, N to not redefine it, E to go into the
  error handler, or P to proceed and not ask in the future (for this pair of files): "
					    STREAM))
				   :CLEAR-INPUT T
				   :FRESH-LINE NIL)
			" OK? "))))
      (CASE CHOICE
	((T :NO-ACTION) T)
	((NIL :INHIBIT-DEFINITION) NIL)
	(ERROR
	 (ERROR CONDITION)
	 T)
	(PROCEED
	 (IF NEW-PATHNAME
	     (PUSH OLD-PATHNAME (GET NEW-PATHNAME :REDEFINES-FILES))
	   (PUSH OLD-PATHNAME NON-PATHNAME-REDEFINED-FILES))
	 T)))))

(DEFUN UNDEFUN (FUNCTION-SPEC &AUX TEM)
  "Restores the saved previous function definition of a function spec."
  (SETQ FUNCTION-SPEC (DWIMIFY-ARG-PACKAGE FUNCTION-SPEC 'FUNCTION-SPEC))
  (SETQ TEM (FUNCTION-SPEC-GET FUNCTION-SPEC :PREVIOUS-DEFINITION))
  (COND (TEM
	 (FSET-CAREFULLY FUNCTION-SPEC TEM T))
	((Y-OR-N-P (FORMAT NIL "~S has no previous definition.  Undefine it? "
			   FUNCTION-SPEC))
	 (FUNDEFINE FUNCTION-SPEC))))

;;; Some source file stuff that does not need to be in QRAND
(DEFUN GET-SOURCE-FILE-NAME (FUNCTION-SPEC &OPTIONAL TYPE)
  "Returns pathname of source file for definition of type TYPE of FUNCTION-SPEC.
If TYPE is NIL, the most recent definition is used, regardless of type.
FUNCTION-SPEC really is a function spec only if TYPE is DEFUN;
for example, if TYPE is DEFVAR, FUNCTION-SPEC is a variable name."
  (DECLARE (VALUES PATHNAME TYPE))
  (LET ((PROPERTY (FUNCTION-SPEC-GET FUNCTION-SPEC :SOURCE-FILE-NAME)))
    (COND ((NULL PROPERTY) NIL)
	  ((ATOM PROPERTY)
	   (AND (MEMQ TYPE '(DEFUN NIL))
		(VALUES PROPERTY 'DEFUN)))
	  (T
	   (LET ((LIST (IF TYPE (ASSQ TYPE PROPERTY) (CAR PROPERTY))))
	     (LOOP FOR FILE IN (CDR LIST)
		   WHEN (NOT (SEND FILE :GET :PATCH-FILE))
		   RETURN (VALUES FILE (CAR LIST))))))))

(DEFUN GET-ALL-SOURCE-FILE-NAMES (FUNCTION-SPEC)
  "Return list describing source files for all definitions of FUNCTION-SPEC.
Each element of the list has a type of definition as its car,
and its cdr is a list of generic pathnames that made that type of definition."
  (LET ((PROPERTY (FUNCTION-SPEC-GET FUNCTION-SPEC :SOURCE-FILE-NAME)))
    (COND ((NULL PROPERTY) NIL)
	  ((ATOM PROPERTY)
	   (SETQ PROPERTY `((DEFUN ,PROPERTY)))
	   ;; May as well save this consing.
	   (FUNCTION-SPEC-PUTPROP FUNCTION-SPEC PROPERTY :SOURCE-FILE-NAME)
	   PROPERTY)
	  (T PROPERTY))))
|#