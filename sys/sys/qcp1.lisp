;;  -*- Mode:LISP; Package:COMPILER; Base:8; Readtable:T -*-
;;; This file contains pass 1 and the top level of the Lisp machine Lisp compiler

;	** (c) Copyright 1980 Massachusetts Institute of Technology **

;;     "This is insane.  What we clearly want to do is not completely
;;      clear, and is rooted in NCOMPLR."   -- BSG/Dissociated Press.

(PROCLAIM '(SPECIAL MC-HOLDPROG ULAP-DEBUG LAP-DEBUG))

;;; Initialize all global variables and compiler switches
(DEFUN QC-PROCESS-INITIALIZE ()
  (SETQ HOLDPROG T)
  (SETQ MC-HOLDPROG T)
  (SETQ ULAP-DEBUG NIL)
  (SETQ LAP-DEBUG NIL)
  (SETQ FUNCTION-BEING-PROCESSED NIL)	;For error printouts.  Avoid any unbound problems
  (SETQ OPEN-CODE-MAP-SWITCH T)
  (SETQ ALLOW-VARIABLES-IN-FUNCTION-POSITION-SWITCH NIL)
  (SETQ ALL-SPECIAL-SWITCH NIL)
  (SETQ OBSOLETE-FUNCTION-WARNING-SWITCH T)
  (SETQ RUN-IN-MACLISP-SWITCH NIL)
  (SETQ INHIBIT-STYLE-WARNINGS-SWITCH NIL)
  (SETQ *CHECK-STYLE-P* T))

;;; Compile a function which already has an interpreted definition,
;;; or define it to a newly supplied definition's compilation.
;;; If the definition is one which is legal but cannot meaningfully
;;; be compiled, we just leave it unchanged.
(DEFUN COMPILE (NAME &OPTIONAL LAMBDA-EXP)
  "Compile the definition of NAME,
or its previous interpreted definition if it is already compiled.
If LAMBDA-EXP is supplied, it is compiled and made the definition of NAME.
If NAME is NIL, LAMBDA-EXP is compiled and the result is just returned."
  (AND QC-FILE-IN-PROGRESS	;Check for condition likely to cause temporary area lossage
       (FORMAT *ERROR-OUTPUT* "~&COMPILE: Compiler recursively entered, you may lose.~%"))
  (IF (NULL NAME)
      (COMPILE-LAMBDA LAMBDA-EXP (GENSYM))
    (LOCKING-RESOURCES-NO-QFASL
      (FILE-OPERATION-WITH-WARNINGS (T ':COMPILE)
	(COMPILER-WARNINGS-CONTEXT-BIND
	  (LET (TEM FILE-SPECIAL-LIST FILE-UNSPECIAL-LIST FILE-LOCAL-DECLARATIONS)
	    (QC-PROCESS-INITIALIZE)
	    (OR LAMBDA-EXP
		(WHEN (FDEFINEDP NAME)
		  (SETQ TEM (FDEFINITION (SI:UNENCAPSULATE-FUNCTION-SPEC NAME)))
		  (cond ((consp tem)
			 (SETQ LAMBDA-EXP TEM))
			((SETQ TEM (ASSQ 'INTERPRETED-DEFINITION
					 (DEBUGGING-INFO TEM)))
			 (SETQ LAMBDA-EXP (CADR TEM)))))
		(FERROR NIL "Can't find ~S expression for ~S" 'lambda NAME))
	    (LET ((INHIBIT-FDEFINE-WARNINGS T))
	      (COMPILE-1 NAME LAMBDA-EXP))
	    NAME))))))

(DEFUN COMPILE-1 (NAME LAMBDA-EXP &OPTIONAL (PROCESSING-MODE 'MACRO-COMPILE)
		  (NAME-FOR-FUNCTION NAME))
  "Compile LAMBDA-EXP and define NAME, while already inside the compiler environment.
NAME-FOR-FUNCTION is recorded as the name of the compiled function 
 (the default is NAME).
PROCESSING-MODE is how to compile: COMPILER:MACRO-COMPILE or COMPILER:MICRO-COMPILE."
  (SETQ LAMBDA-EXP (LAMBDA-MACRO-EXPAND LAMBDA-EXP))
  (COND ((ATOM LAMBDA-EXP)
	 (FDEFINE NAME LAMBDA-EXP T))
	((OR (MEMQ (CAR LAMBDA-EXP) '(LAMBDA NAMED-LAMBDA SUBST NAMED-SUBST CLI:SUBST))
	     (AND (EQ (CAR LAMBDA-EXP) 'MACRO)
		  (CONSP (CDR LAMBDA-EXP))
		  (MEMQ (CADR LAMBDA-EXP)
			'(LAMBDA NAMED-LAMBDA))))
	 (QC-TRANSLATE-FUNCTION NAME LAMBDA-EXP PROCESSING-MODE 'COMPILE-TO-CORE
				NAME-FOR-FUNCTION))
	(T (FDEFINE NAME LAMBDA-EXP T))))

(DEFUN COMPILE-LAMBDA (LAMBDA-EXP &OPTIONAL NAME (PROCESSING-MODE 'MACRO-COMPILE))
  "Compile the function LAMBDA-EXP and return a compiled-function object.
That compiled function will record NAME as its name,
but we do not actually define NAME."
  (AND QC-FILE-IN-PROGRESS	;Check for condition likely to cause temporary area lossage
       (FORMAT *ERROR-OUTPUT* "~&COMPILE: Compiler recursively entered, you may lose.~%"))
  (LOCKING-RESOURCES-NO-QFASL
    (FILE-OPERATION-WITH-WARNINGS (T ':COMPILE)
      (COMPILER-WARNINGS-CONTEXT-BIND
	(LET (TEM
	      (FILE-SPECIAL-LIST NIL)
	      (FILE-UNSPECIAL-LIST NIL)
	      (FILE-LOCAL-DECLARATIONS NIL)
	      (INHIBIT-FDEFINE-WARNINGS T))
	  (QC-PROCESS-INITIALIZE)
	  (COMPILE-1 `(:LOCATION ,(LOCF TEM)) LAMBDA-EXP PROCESSING-MODE NAME)
	  TEM)))))

;;; Restore the saved old interpreted definition of a function on which
;;; COMPILE was used.

(DEFUN UNCOMPILE (FUNCTION-SPEC &OPTIONAL DONT-UNENCAPSULATE &AUX OLD)
  "Replaces compiled definition of FUNCTION-SPEC with interpreted definition.
If the interpreted function which was compiled is known,
installs that as the definition in place of the compiled one."
  (UNLESS DONT-UNENCAPSULATE
    (SETQ FUNCTION-SPEC (SI:UNENCAPSULATE-FUNCTION-SPEC FUNCTION-SPEC)))
  (LET ((DEF (FDEFINITION FUNCTION-SPEC)))
    (COND ((LIST-MATCH-P DEF `(MACRO . ,IGNORE))
	   (COND ((SETQ OLD (ASSQ 'INTERPRETED-DEFINITION (DEBUGGING-INFO (CDR DEF))))
		  (FDEFINE FUNCTION-SPEC `(MACRO . ,(CADR OLD)) (NOT DONT-UNENCAPSULATE) T))
		 ((TYPEP (CDR DEF) 'COMPILED-FUNCTION)
		  "No interpreted definition recorded")
		 (T "Not compiled")))
	  ((SETQ OLD (ASSQ 'INTERPRETED-DEFINITION (DEBUGGING-INFO DEF)))
	   (FDEFINE FUNCTION-SPEC (CADR OLD) (NOT DONT-UNENCAPSULATE) T))
	  ((TYPEP DEF 'COMPILED-FUNCTION)
	   "No interpreted definition recorded")
	  (T "Not compiled"))))

(DEFUN QC-TRANSLATE-FUNCTION (FUNCTION-SPEC EXP QC-TF-PROCESSING-MODE QC-TF-OUTPUT-MODE
			      &OPTIONAL (NAME-FOR-FUNCTION FUNCTION-SPEC))
  "Compile one function.  All styles of the compiler come through here.
QC-TF-PROCESSING-MODE should be MACRO-COMPILE or MICRO-COMPILE.
QC-TF-OUTPUT-MODE is used by LAP to determine where to put the compiled code.
 It is COMPILE-TO-CORE for making an actual FEF, QFASL, REL, or
 QFASL-NO-FDEFINE to simply dump a FEF without trying to define a function
EXP is the lambda-expression.
NAME-FOR-FUNCTION is what the FEF's name field should say;
 if omitted, FUNCTION-SPEC is used for that too.
In MACRO-COMPILE mode, the return value is the value of QLAPP for the first function."
 (WHEN COMPILER-VERBOSE
   (FORMAT T "~&Compiling ~S" FUNCTION-SPEC))
 (OBJECT-OPERATION-WITH-WARNINGS (NAME-FOR-FUNCTION)
  (LET ((ERROR-MESSAGE-HOOK
	  (LET-CLOSED ((FUNCTION-BEING-PROCESSED NAME-FOR-FUNCTION))
	    #'(LAMBDA () (AND FUNCTION-BEING-PROCESSED
      			      (FORMAT T "Error occurred while compiling ~S"
				      FUNCTION-BEING-PROCESSED)))))
	(COMPILER-QUEUE
	  (NCONS
	    (MAKE-COMPILER-QUEUE-ENTRY
	      :FUNCTION-SPEC FUNCTION-SPEC
	      :FUNCTION-NAME NAME-FOR-FUNCTION
	      :DEFINITION EXP
	      :DECLARATIONS LOCAL-DECLARATIONS)))
	(INSIDE-QC-TRANSLATE-FUNCTION T)
	VAL
	THIS-FUNCTION-BARF-SPECIAL-LIST
	VARIABLES-LISTS)
    (DO ((L COMPILER-QUEUE (CDR L))
	 (DEFAULT-CONS-AREA QCOMPILE-TEMPORARY-AREA)
	 FUNCTION-TO-DEFINE
	 *OUTER-CONTEXT-VARIABLE-ENVIRONMENT*
	 *OUTER-CONTEXT-LOCAL-FUNCTIONS*
	 *OUTER-CONTEXT-FUNCTION-ENVIRONMENT*
	 *OUTER-CONTEXT-PROGDESC-ENVIRONMENT*
	 *OUTER-CONTEXT-GOTAG-ENVIRONMENT*
	 (EXP)
	 NAME-FOR-FUNCTION
	 THIS-FUNCTION-ARGLIST
	 THIS-FUNCTION-ARGLIST-FUNCTION-NAME
	 (LOCAL-DECLARATIONS))
	((NULL L))
      (SETF (FILL-POINTER QCMP-OUTPUT) 0)
      (SETQ FUNCTION-TO-DEFINE (COMPILER-QUEUE-ENTRY-FUNCTION-SPEC (CAR L)))
      (SETQ NAME-FOR-FUNCTION (COMPILER-QUEUE-ENTRY-FUNCTION-NAME (CAR L)))
      (SETQ EXP (COMPILER-QUEUE-ENTRY-DEFINITION (CAR L)))
      (SETQ LOCAL-DECLARATIONS (COMPILER-QUEUE-ENTRY-DECLARATIONS (CAR L)))
      (SETQ *OUTER-CONTEXT-VARIABLE-ENVIRONMENT* (COMPILER-QUEUE-ENTRY-VARIABLES (CAR L)))
      (SETQ *OUTER-CONTEXT-LOCAL-FUNCTIONS* (COMPILER-QUEUE-ENTRY-LOCAL-FUNCTIONS (CAR L)))
      (SETQ *OUTER-CONTEXT-FUNCTION-ENVIRONMENT*
	    (COMPILER-QUEUE-ENTRY-FUNCTION-ENVIRONMENT (CAR L)))
      (SETQ *OUTER-CONTEXT-PROGDESC-ENVIRONMENT* (COMPILER-QUEUE-ENTRY-PROGDESCS (CAR L)))
      (SETQ *OUTER-CONTEXT-GOTAG-ENVIRONMENT* (COMPILER-QUEUE-ENTRY-GOTAGS (CAR L)))
      (OBJECT-OPERATION-WITH-WARNINGS (NAME-FOR-FUNCTION)
	(CATCH-ERROR-RESTART (ERROR "Give up on compiling ~S" NAME-FOR-FUNCTION)
	  (PUSH (QCOMPILE0 EXP FUNCTION-TO-DEFINE
			   (EQ QC-TF-PROCESSING-MODE 'MICRO-COMPILE)
			   NAME-FOR-FUNCTION)
		VARIABLES-LISTS)
	  (AND PEEP-ENABLE
	       (NEQ QC-TF-PROCESSING-MODE 'MICRO-COMPILE)
	       (PEEP QCMP-OUTPUT FUNCTION-TO-DEFINE))
	  (COND ((NULL HOLDPROG))
		((EQ QC-TF-PROCESSING-MODE 'MACRO-COMPILE)
		 (SETQ EXP (QLAPP (G-L-P QCMP-OUTPUT) QC-TF-OUTPUT-MODE))
		 (OR VAL (SETQ VAL EXP)))
		((EQ QC-TF-PROCESSING-MODE 'MICRO-COMPILE)
		 (LET ((DEFAULT-CONS-AREA BACKGROUND-CONS-AREA))
		   (MICRO-COMPILE (G-L-P QCMP-OUTPUT) QC-TF-OUTPUT-MODE)))))))
    (DOLIST (VL VARIABLES-LISTS)
      (DOLIST (V VL)
	(COND ((OR (STRING= (VAR-NAME V) "IGNORE")
		   (STRING= (VAR-NAME V) "IGNORED"))
	       (OR (ZEROP (VAR-USE-COUNT V))
		   (WARN 'NOT-IGNORED :IMPLAUSIBLE
			 "The variable ~S is bound and not ignored." (VAR-NAME V))))
	      ((GETF (VAR-DECLARATIONS V) 'IGNORE)
	       (OR (ZEROP (VAR-USE-COUNT V))
		   (WARN 'NOT-IGNORED :IMPLAUSIBLE
			 "The variable ~S, which is declared to be ignored, was referenced"
			 (VAR-NAME V))))
	      ((NOT (GET (VAR-NAME V) 'IGNORABLE-VARIABLE))
	       (AND (ZEROP (VAR-USE-COUNT V))
		    (EQ (VAR-TYPE V) 'FEF-LOCAL)
		    (IF (GET (VAR-NAME V) 'LOCAL-FUNCTION-NAME)
			(WARN 'NOT-USED :IMPLAUSIBLE
			      "The local function ~S is never used."
			      (GET (VAR-NAME V) 'LOCAL-FUNCTION-NAME))
		      (WARN 'NOT-USED :IMPLAUSIBLE
			    "The variable ~S is bound but never used." (VAR-NAME V))))))))
    VAL)))

(DEFUN COMPILE-NOW-OR-LATER (NAME LAMBDA-EXP)
  "Compile LAMBDA-EXP and define NAME, either now or on exit from the compiler.
If not within the compiler, it is done now.
Otherwise, it is done as soon as it is safe."
  (IF INSIDE-QC-TRANSLATE-FUNCTION
      (SETQ COMPILER-QUEUE
	    (NCONC COMPILER-QUEUE
		   (NCONS (MAKE-COMPILER-QUEUE-ENTRY
			    :FUNCTION-SPEC NAME
			    :FUNCTION-NAME NAME
			    :DEFINITION LAMBDA-EXP))))
    (COMPILE NAME LAMBDA-EXP)))

;;; Given a function, break it off if appropriate
;;; and return the result.
;;; This will be (FUNCTION symbol) or (BREAKOFF-FUNCTION list).
;;; If it doesn't need breaking off, return NIL.
(DEFUN MAYBE-BREAKOFF (FUNCTION &OPTIONAL LEXICAL)
  (SETQ FUNCTION (LAMBDA-MACRO-EXPAND FUNCTION))
  (COND ((ATOM FUNCTION) NIL)
	((MEMQ (CAR FUNCTION) '(LAMBDA NAMED-LAMBDA))
	 (BREAKOFF FUNCTION LEXICAL))))

;;; Compile an internal lambda which must be passed as an argument
;;; into a separate function, which has its own name which is a list.
;;; That name is returned.
(defun breakoff (x &optional lexical &aux fname fname-to-give local-name)
  (let ((non-instance-vars)
	(sfd self-flavor-declaration)
	;selfp
	)
    (dolist (home vars)
      (and (eq (var-type home) 'fef-local)
	   ;; Omit shadowed bindings.
	   (eq home (assq (var-name home) vars))
	   (pushnew (var-name home) non-instance-vars)))
    (dolist (elt *outer-context-variable-environment*)
      (dolist (home elt)
	(push (var-name home) non-instance-vars)))
    (multiple-value-bind (vars-needed-lexically functions-needed-lexically
			  block-names go-tags)
	(cw-top-level-lambda-expression
	  x					;form
	  (append (if sfd (list* 'self (cddr sfd)))
		  non-instance-vars)		;variables we're interested in
	  (mapcar #'car *local-functions*)	;functions we're interested in
	  *function-environment*)
      (let (tem w)
	(dolist (v vars-needed-lexically)
	  (cond ((and (memq v (cddr sfd)) (not (memq v non-instance-vars)))
		 (warn 'instance-variable-used-in-internal-lambda :unimplemented
		       "The ~:[~;special ~]instance variable ~S of flavor ~S
is being referenced by a lexically closed-over function.
This will not work outside of the dynamic scope of ~S.~:[
This problem will be fixed when Mly's brain hurts a little less.~]"
		     (memq v (cadr sfd)) v (car sfd) 'self (prog1 w (setq w t))))
		((and (eq v 'self) sfd)
		 (warn 'self-used-in-internal-lambda :unimplemented
		       "~S is being referenced by a lexically closed-over function.
This will not, of course, work outside of the dynamic scope of ~S.~:[
This problem will be fixed when Mly's brain hurts a little less.~]"
		       'self 'self (prog1 w (setq w t))))
		(t
		 ;; Note: if V is not on VARS, it must come from an outer lexical level.
		 ;; That is ok, and it still requires this LAMBDA to be lexical to access it.
		 (setq lexical t)
		 (setq tem (assq v vars))
		 (when tem
		   (pushnew 'fef-arg-used-in-lexical-closures (var-misc tem) :test #'eq))))))
      (dolist (f functions-needed-lexically)
	(let ((tem (assq f *local-functions*)))
	  (when tem
	    (setq lexical t)
	    (pushnew 'fef-arg-used-in-lexical-closures
		     (var-misc (cadr tem)) :test #'eq))))
      (dolist (b block-names)
	(let ((tem (assq b *progdesc-environment*)))
	  (when tem
	    (setq lexical t)
	    (setf (progdesc-used-in-lexical-closures-flag tem) t))))
      (dolist (g go-tags)
	(let ((tem (assoc-equal g *gotag-environment*)))
	  (when tem
	    (setq lexical t)
	    (setf (gotag-used-in-lexical-closures-flag tem) t)
	    (setf (progdesc-used-in-lexical-closures-flag (gotag-progdesc tem)) t))))))
  (if (and (eq (car x) 'named-lambda)
	   (not (memq (cadr x) local-function-map)))
      (setq local-name (cadr x))
      (setq local-name *breakoff-count*))
  (setq fname `(:internal ,function-to-be-defined ,*breakoff-count*)
	fname-to-give `(:internal ,name-to-give-function ,local-name))
  (push local-name local-function-map)
  (incf *breakoff-count*)
  (when lexical
    (incf *lexical-closure-count*))
  (let ((local-decls local-declarations))
;>> this is already in there.
;    ;; Pass along the parent function's self-flavor declaration.
;    (if sfd (push `(:self-flavor . ,sfd) local-decls))
    (setq compiler-queue
	  (nconc compiler-queue
		 (ncons
		   (make-compiler-queue-entry
		     :function-spec fname
		     :function-name fname-to-give
		     :definition x
		     :declarations local-decls
		     :variables (and lexical (cons t *outer-context-variable-environment*))
		     :local-functions (and lexical *local-functions*)
		     :progdescs *progdesc-environment*
		     :gotags *gotag-environment*
		     :function-environment *function-environment*
		     )))))
  (let ((tem `(breakoff-function ,fname)))
    (if lexical `(lexical-closure ,tem) tem)))

(DEFUN RECORD-VARIABLES-USED-IN-LEXICAL-CLOSURES ()
  (LET ((VARS-USED
	  (LOOP FOR HOME IN ALLVARS
		WHEN (MEMQ 'FEF-ARG-USED-IN-LEXICAL-CLOSURES
			   (VAR-MISC HOME))
		COLLECT HOME)))
    (DOLIST (ELT COMPILER-QUEUE)
      (LET ((TEM (MEMQ T (COMPILER-QUEUE-ENTRY-VARIABLES ELT))))
	(AND TEM (SETF (CAR TEM) VARS-USED))))
    VARS-USED))

(DEFUN LEXICAL-VAR-P (VAR)
  (DO ((I 0 (1+ I))
       (E *OUTER-CONTEXT-VARIABLE-ENVIRONMENT* (CDR E)))
      ((NULL E))
    (WHEN (ASSQ VAR (CAR E))
      (RETURN T))))

;;; Return a reference to VAR as a lexical variable from a higher context,
;;; or NIL if VAR is not a variable of that sort available now.
(DEFUN TRY-REF-LEXICAL-VAR (VAR &AUX HOME)
  (DO ((I 0 (1+ I))
       (E *OUTER-CONTEXT-VARIABLE-ENVIRONMENT* (CDR E)))
      ((NULL E))
    (WHEN (SETQ HOME (ASSQ VAR (CAR E)))
      (INCF (VAR-USE-COUNT HOME))
      (RETURN
	`(LEXICAL-REF ,(DPB I (BYTE 12. 12.)
			    (FIND-POSITION-IN-LIST HOME (CAR E))))))))

;;; Given a vars entry HOME, return a suitable pass 1 reference to it
;;; whether it is inherited lexically or not.
(DEFUN TRY-REF-LEXICAL-HOME (HOME)
  (INCF (VAR-USE-COUNT HOME))
  (DO ((I 0 (1+ I))
       (E *OUTER-CONTEXT-VARIABLE-ENVIRONMENT* (CDR E)))
      ((NULL E)
       (VAR-LAP-ADDRESS HOME))
    (WHEN (MEMQ HOME (CAR E))
      (RETURN
	`(LEXICAL-REF ,(DPB I (BYTE 12. 12.) (FIND-POSITION-IN-LIST HOME (CAR E))))))))

;;; The SELF-FLAVOR-DECLARATION variable looks like
;;; (flavor-name special-ivars instance-var-names...)
;;; and describes the flavor we are compiling access to instance vars of.
(DEFUN TRY-REF-SELF (VAR)
  (WHEN (MEMQ VAR (CDDR SELF-FLAVOR-DECLARATION))
    ;; If variable is explicitly declared special, use that instead.
    (COND ((LET ((BARF-SPECIAL-LIST NIL))
	     (SPECIALP VAR))
	   (OR (MEMQ VAR (CADR SELF-FLAVOR-DECLARATION))
	       (WARN 'SPECIAL-VARIABLE-IS-UNSPECIAL-INSTANCE-VARIABLE :IMPOSSIBLE
		     "The special variable ~S is an instance variable of ~S
but was not mentioned in a ~S in that flavor.
This function will not execute correctly unless the ~S is fixed."
		     VAR (CAR SELF-FLAVOR-DECLARATION)
		     :SPECIAL-INSTANCE-VARIABLES 'DEFFLAVOR))
	   (MAKESPECIAL VAR)
	   VAR)
	  (T
	   (SETQ SELF-REFERENCES-PRESENT T)
	   `(SELF-REF ,(CAR SELF-FLAVOR-DECLARATION) ,VAR)))))

;;;; QCOMPILE0 compiles one function, producing a list of lap code in QCMP-OUTPUT.
;;; The first argument is the lambda-expression which defines the function.
;;;   It must actually be a LAMBDA or NAMED-LAMBDA.  Other things are not allowed.
;;; The second argument is the name of the function.
;;; The third won't be useful till there's a microcompiler.

;;; We expect that DEFAULT-CONS-AREA has been bound to QCOMPILE-TEMPORARY-AREA.
;;; The compiler does ALL consing in that temporary area unless it specifies otherwise.

;;;Variables defined in QCP2, bound here but aside from that used only in QCP2.
(PROCLAIM '(SPECIAL WITHIN-CATCH CALL-BLOCK-PDL-LEVELS TAGOUT P2FN
		    BDEST DROPTHRU M-V-TARGET WITHIN-POSSIBLE-LOOP))

(DEFPROP COMPILER-ARGLIST T SI::DEBUG-INFO)

(DEFUN QCOMPILE0 (EXP FUNCTION-TO-BE-DEFINED GENERATING-MICRO-COMPILER-INPUT-P
		  &OPTIONAL (NAME-TO-GIVE-FUNCTION FUNCTION-TO-BE-DEFINED))
  (LET ((EXP1 EXP)
	(VARS ())
	(DEF-TO-BE-SXHASHED)
	(BODY)
	(PDLLVL 0)				;Runtine local pdllvl
	(CALL-BLOCK-PDL-LEVELS)
	(WITHIN-CATCH)
	(ALLGOTAGS)
	(TLEVEL T)
	(P1VALUE T)				;Compiling for value
	(BINDP NIL)				;%BIND not yet used in this frame
	(LVCNT)
	(DROPTHRU T)				;Can drop in if false, flush stuff till tag or
	(MAXPDLLVL 0)				;deepest lvl reached by local pdl

	(ALLVARS)
	(FREEVARS)
	(*LOCAL-FUNCTIONS* *OUTER-CONTEXT-LOCAL-FUNCTIONS*)
	(*FUNCTION-ENVIRONMENT* *OUTER-CONTEXT-FUNCTION-ENVIRONMENT*)
	(*PROGDESC-ENVIRONMENT* *OUTER-CONTEXT-PROGDESC-ENVIRONMENT*)
	(*GOTAG-ENVIRONMENT* *OUTER-CONTEXT-GOTAG-ENVIRONMENT*)
	(LL)
	(TAGOUT)
	(WITHIN-POSSIBLE-LOOP)
	(TLFUNINIT)
	(SPECIALFLAG)
	(MACROFLAG)
	(LOCAL-MAP ())				;names of local variables
	(ARG-MAP ())				;names of arguments
	(LOCAL-FUNCTION-MAP ())			;names of local functions
	(DOCUMENTATION)
	(EXPR-DEBUG-INFO)
	(FAST-ARGS-POSSIBLE T)
	(*BREAKOFF-COUNT* 0)			;no internal functions yet
	(*LEXICAL-CLOSURE-COUNT* 0)
	(VARIABLES-USED-IN-LEXICAL-CLOSURES)
	(MACROS-EXPANDED)			;List of all macros found in this function,
						; for the debugging info.
	(SELF-FLAVOR-DECLARATION (cdr (assq :self-flavor local-declarations)))
	(SELF-REFERENCES-PRESENT)		;Bound to T if any SELF-REFs are present
	(LOCAL-DECLARATIONS LOCAL-DECLARATIONS)	;Don't mung ouside value
	(SUBST-FLAG)				;T if this is a SUBST being compiled.
						; Always put interpreted defn in debug info.
	(INHIBIT-SPECIAL-WARNINGS)
	(CLOBBER-NONSPECIAL-VARS-LISTS))
    (BEGIN-PROCESSING-FUNCTION FUNCTION-TO-BE-DEFINED)
    (WHEN (LIST-MATCH-P FUNCTION-TO-BE-DEFINED
			`(:PROPERTY ,IGNORE :NAMED-STRUCTURE-INVOKE))
      (WARN 'OBSOLETE-PROPERTY :IMPLAUSIBLE
	    "NAMED-STRUCTURE-INVOKE, the property name, should not be a keyword."))
    ;; If compiling a macro, compile its expansion function
    ;; and direct lap to construct a macro later.
    (WHEN (EQ (CAR EXP1) 'MACRO)
      (SETQ MACROFLAG T)
      (SETQ EXP1 (CDR EXP1))
      (SETQ DEF-TO-BE-SXHASHED EXP1))
    (UNLESS (MEMQ (CAR EXP1) '(LAMBDA SUBST CLI:SUBST NAMED-LAMBDA NAMED-SUBST))
      (WARN 'FUNCTION-NOT-VALID :FATAL "The definition is not a function at all.")
      (RETURN-FROM QCOMPILE0 NIL))
    (IF (MEMQ (CAR EXP1) '(SUBST NAMED-SUBST CLI:SUBST))
	(SETQ SUBST-FLAG T INHIBIT-SPECIAL-WARNINGS T))
    ;; If a NAMED-LAMBDA, discard the name and save debug-info in special place.
    (WHEN (MEMQ (CAR EXP1) '(NAMED-LAMBDA NAMED-SUBST))
      (SETQ EXPR-DEBUG-INFO (CDR-SAFE (CADR EXP1))
	    EXP1 (CDR EXP1))
      ;; Debug info that is equivalent to declarations
      ;; should be turned back into declarations, coming before
      ;; declarations made outside of compilation
      ;; but after anything coming from a DECLARE in the body.
      (DOLIST (ELT (REVERSE EXPR-DEBUG-INFO))
	(WHEN (AND (NEQ (CAR ELT) 'DOCUMENTATION)
		   (GET (CAR ELT) 'SI::DEBUG-INFO))
	  (PUSH ELT LOCAL-DECLARATIONS))))
    (SETQ LL (CADR EXP1))			;lambda list.
    (SETQ BODY (CDDR EXP1))
    ;; Record the function's arglist for warnings about recursive calls.
    (OR THIS-FUNCTION-ARGLIST-FUNCTION-NAME
	(SETQ THIS-FUNCTION-ARGLIST-FUNCTION-NAME NAME-TO-GIVE-FUNCTION
	      THIS-FUNCTION-ARGLIST LL))
    ;; Extract documentation string and declarations from the front of the body.
    (MULTIPLE-VALUE-SETQ (BODY LOCAL-DECLARATIONS DOCUMENTATION)
;>> need to pass environment into extract-declarations here
      (EXTRACT-DECLARATIONS BODY LOCAL-DECLARATIONS T))
    (SETQ SELF-FLAVOR-DECLARATION
	  (CDR (ASSQ ':SELF-FLAVOR LOCAL-DECLARATIONS)))
    ;; If the user just did (declare (:self-flavor flname)),
    ;; compute the full declaration for that flavor.
    (WHEN (AND SELF-FLAVOR-DECLARATION
	       (NULL (CDR SELF-FLAVOR-DECLARATION)))
      (SETQ SELF-FLAVOR-DECLARATION
	    (CDR (SI::FLAVOR-DECLARATION (CAR SELF-FLAVOR-DECLARATION)))))
    ;; Actual DEFMETHODs must always have SELF-FLAVOR
    (WHEN (EQ (CAR-SAFE FUNCTION-TO-BE-DEFINED) :METHOD)
      (SETQ SELF-REFERENCES-PRESENT T))
    ;; Process &KEY and &AUX vars, if there are any.
    (WHEN (OR (MEMQ '&KEY LL) (MEMQ '&AUX LL))
      ;; Put arglist together with body again.
      (LET ((LAMEXP `(LAMBDA ,LL (DECLARE . ,LOCAL-DECLARATIONS) . ,BODY)))
	;; If there are keyword arguments, expand them.
	(AND (MEMQ '&KEY LL)
	     (SETQ LAMEXP (EXPAND-KEYED-LAMBDA LAMEXP)))
	;; Now turn any &AUX variables in the LAMBDA into a LET* in the body.
	(SETQ LAMEXP (P1AUX LAMEXP))
	;; Separate lambda list and body again.
	(SETQ LL (CADR LAMEXP) BODY (CDDR LAMEXP)))
      ;; Can just pop off the declarations as we have them already from above
      (DO () ((NEQ (CAR-SAFE (CAR BODY)) 'DECLARE))
	(POP BODY)))
    ;; Create the arglist accesible through (arglist foo 'compile)
    (LET ((L NIL))
      (DOLIST (X (CADR EXP1))
	(UNLESS (MEMQ X '(&SPECIAL &LOCAL))
	  (PUSH (COND ((EQ X '&AUX) (RETURN))
		      ((ATOM X) X)		;foo, &optional, etc
		      ((CONSP (CAR X))		;((:foo bar)), ((:foo bar) baz foop), etc
		       (IF (CADR X)
			   (LIST (CAAR X) (CADR X))
			 (CAAR X)))
		      (T			;(foo), (foo bar), (foo bar foop)
		       (IF (CADR X)
			   (LIST (CAR X) (CADR X))
			 (CAR X))))
		L)))
      (SETQ L (NREVERSE L))
      (UNLESS (EQUAL L LL)
	(PUSH (CONS 'COMPILER-ARGLIST L) LOCAL-DECLARATIONS)))
    ;; Now process the variables in the lambda list, after the local declarations.
    (SETQ LL (P1SBIND LL 'FEF-ARG-REQ NIL NIL LOCAL-DECLARATIONS))
    (COND ((NOT (NULL (CDR BODY)))
	   (SETQ EXP1 `(PROGN . ,BODY)))
	  ((SETQ EXP1 (CAR BODY))))
    (SETQ EXP1 (P1 EXP1))			;Do pass 1 to single-expression body
    (SETQ LVCNT (ASSIGN-LAP-ADDRESSES))
    ;; Now that we know all the variables needed by lexical closures,
    ;; make a list of them and put them into the entries in COMPILER-QUEUE
    ;; for each of those lexical closures.
    (UNLESS (ZEROP *LEXICAL-CLOSURE-COUNT*)
      (SETQ VARIABLES-USED-IN-LEXICAL-CLOSURES
	    (RECORD-VARIABLES-USED-IN-LEXICAL-CLOSURES)))
    (OUTF `(MFEF ,FUNCTION-TO-BE-DEFINED ,SPECIALFLAG
		 ,(ELIMINATE-DUPLICATES-AND-REVERSE ALLVARS)
		 ,FREEVARS ,NAME-TO-GIVE-FUNCTION))
    (IF MACROFLAG (OUTF `(CONSTRUCT-MACRO)))
    (OUTF `(QTAG S-V-BASE))
    (OUTF `(S-V-BLOCK))
    (IF (AND SELF-FLAVOR-DECLARATION SELF-REFERENCES-PRESENT)
	(OUTF `(SELF-FLAVOR . ,SELF-FLAVOR-DECLARATION)))
    (OUTF `(QTAG DESC-LIST-ORG))
    (OUTF `(PARAM LLOCBLOCK
		  ,(IF (ZEROP *LEXICAL-CLOSURE-COUNT*)
		       LVCNT
		     (+ LVCNT (* 4 *LEXICAL-CLOSURE-COUNT*) 3
			(LENGTH VARIABLES-USED-IN-LEXICAL-CLOSURES)))))
    (OUTF `(A-D-L))
    (OUTF `(QTAG QUOTE-BASE))
    (OUTF `(ENDLIST))				;Lap will insert quote vector here
    (WHEN (NOT (ZEROP *LEXICAL-CLOSURE-COUNT*))
      (OUTF `(VARIABLES-USED-IN-LEXICAL-CLOSURES
	       . ,(REVERSE (MAPCAR #'(LAMBDA (HOME)
				       (LET ((TEM (VAR-LAP-ADDRESS HOME)))
					 (SELECTQ (CAR TEM)
					   (ARG (CADR TEM))
					   (T (%LOGDPB 1 %%Q-BOXED-SIGN-BIT (CADR TEM))))))
				   VARIABLES-USED-IN-LEXICAL-CLOSURES)))))
    ;; Set up the debug info from the local declarations and other things
    (LET ((DEBUG-INFO NIL) TEM)
      (AND DOCUMENTATION (PUSH `(DOCUMENTATION ,DOCUMENTATION) DEBUG-INFO))
      (DOLIST (DCL LOCAL-DECLARATIONS)
	(WHEN (SYMBOLP (CAR DCL))
	  (SETQ TEM (GET (CAR DCL) 'SI::DEBUG-INFO))
	  (IF (EQ TEM T) (SETQ TEM (CAR DCL)))
	  (UNLESS (ASSQ TEM DEBUG-INFO)
	    (PUSH (IF (EQ TEM (CAR DCL)) DCL (CONS TEM (CDR DCL))) DEBUG-INFO))))
      ;; Propagate any other kinds of debug info from the expr definition.
      (DOLIST (DCL EXPR-DEBUG-INFO)
	(UNLESS (ASSQ (CAR DCL) DEBUG-INFO)
	  (PUSH DCL DEBUG-INFO)))
      (WHEN (PLUSP *BREAKOFF-COUNT*)		; local functions
	(LET ((INTERNAL-OFFSETS (MAKE-LIST *BREAKOFF-COUNT*)))
	  (OUTF `(BREAKOFFS ,INTERNAL-OFFSETS))
	  (PUSH `(:INTERNAL-FEF-OFFSETS . ,INTERNAL-OFFSETS) DEBUG-INFO)))
      ;; Include the local and arg maps if we have them.
      ;; They were built by ASSIGN-LAP-ADDRESSES.
      (WHEN LOCAL-MAP (PUSH `(LOCAL-MAP ,LOCAL-MAP) DEBUG-INFO))
      (WHEN ARG-MAP (PUSH `(ARG-MAP ,ARG-MAP) DEBUG-INFO))
      (WHEN LOCAL-FUNCTION-MAP (PUSH `(LOCAL-FUNCTION-MAP ,(NREVERSE LOCAL-FUNCTION-MAP))
				     DEBUG-INFO))
      ;; Include list of macros used, if any.
      (WHEN MACROS-EXPANDED
	(LET ((MACROS-AND-SXHASHES
		(MAPCAR #'(LAMBDA (MACRONAME)
			    (LET ((HASH (EXPR-SXHASH MACRONAME)))
			      (IF (OR HASH (CONSP MACRONAME))
				  (LIST MACRONAME HASH)
				MACRONAME)))
			MACROS-EXPANDED)))
	  (IF QC-FILE-RECORD-MACROS-EXPANDED
	      (PROGN
		;; If in QC-FILE, put just macro names in the function
		;; but put the names and sxhashes into the file's list.
		(PUSH `(:MACROS-EXPANDED ,MACROS-EXPANDED) DEBUG-INFO)
		(DOLIST (M MACROS-AND-SXHASHES)
		  (OR (MEMBER-EQUAL M QC-FILE-MACROS-EXPANDED)
		      (LET ((DEFAULT-CONS-AREA BACKGROUND-CONS-AREA))
			(PUSH (COPYTREE M) QC-FILE-MACROS-EXPANDED)))))
	    (PUSH `(:MACROS-EXPANDED ,MACROS-AND-SXHASHES)
		  DEBUG-INFO))))
      (AND (OR (EQ QC-TF-OUTPUT-MODE 'COMPILE-TO-CORE)
	       SUBST-FLAG)
	   (PUSH `(INTERPRETED-DEFINITION ,EXP) DEBUG-INFO))
      (WHEN SUBST-FLAG
	(LET* ((ARGS-INFO (ARGS-INFO EXP))
	       (DUMMY-FORM (CONS 'FOO
				 (MAKE-LIST (+ (LDB %%ARG-DESC-MAX-ARGS ARGS-INFO)
					       (IF (LDB-TEST %ARG-DESC-EVALED-REST ARGS-INFO)
						   1 0))
					    :INITIAL-ELEMENT '(GENSYM)))))
;>> this somewhat bogus. The environment should be much hairier. Or should it?
	  (UNLESS (WITH-STACK-LIST (ENV *FUNCTION-ENVIRONMENT*)
;>> BULLSHIT. this cannot hope to work. sigh.
		    (EQUAL (SI::SUBST-EXPAND EXP DUMMY-FORM ENV NIL)
			   (SI::SUBST-EXPAND EXP DUMMY-FORM ENV T)))
	    ;; If simple and thoughtful substitution give the same result
	    ;; even with the most intractable arguments,
	    ;; we need not use thoughtful substitution for this defsubst.
	    ;; Otherwise, mark it as requiring thoughtful substitution.
	    (PUSH '(:NO-SIMPLE-SUBSTITUTION T) DEBUG-INFO))))
      ;; Compute the sxhash now, after all displacing macros have been displaced
      (AND MACROFLAG
	   (PUSH `(:EXPR-SXHASH ,(FUNCTION-EXPR-SXHASH DEF-TO-BE-SXHASHED)) DEBUG-INFO))
      ;; If we aren't going to mark this function as requiring a mapping
      ;; table, provide anyway some info that the user declared it wanted one.
      (AND SELF-FLAVOR-DECLARATION (NOT SELF-REFERENCES-PRESENT)
	   (PUSH `(:SELF-FLAVOR ,(CAR SELF-FLAVOR-DECLARATION)) DEBUG-INFO))
      (AND DEBUG-INFO
	   (OUTF `(DEBUG-INFO . ,DEBUG-INFO))))
    (OUTF `PROGSA)
    (P2SBIND LL VARS NIL)			;Can compile initializing code
    (LET ((*LEXICAL-CLOSURE-COUNT* 0))
      (P2 EXP1 'D-RETURN))			;Do pass 2
    (OUTF `(PARAM MXPDL ,(1+ MAXPDLLVL)))
    ALLVARS))

(DEFUN FUNCTION-EXPR-SXHASH (FUNCTION)
  (LET ((FUNCTION (IF (AND (CONSP FUNCTION) (EQ (CAR FUNCTION) 'MACRO))
		      (CDR FUNCTION) FUNCTION)))
    (COND ((TYPEP FUNCTION 'COMPILED-FUNCTION)
	   (OR (CADR (ASSQ ':EXPR-SXHASH (DEBUGGING-INFO FUNCTION)))
	       (LET ((IDEF (CADR (ASSQ 'INTERPRETED-DEFINITION (DEBUGGING-INFO FUNCTION)))))
		 (AND IDEF (FUNCTION-EXPR-SXHASH IDEF)))))
	  ((NULL FUNCTION) NIL)
	  ((SYMBOLP FUNCTION) (EXPR-SXHASH FUNCTION))
	  ((CONSP FUNCTION)
	   (SXHASH (SI::LAMBDA-EXP-ARGS-AND-BODY FUNCTION))))))

;;; This must follow FUNCTION-EXPR-SXHASH or else FASLOAD bombs out
;;; loading this file for the first time.
(DEFUN EXPR-SXHASH (FUNCTION-SPEC)
  "Return the SXHASH of the interpreted definition of FUNCTION-SPEC.
If FUNCTION-SPEC's definition is compiled, the interpreted definition
or its SXHASH may be remembered in the debugging info.
If neither is remembered, the value is NIL."
  (FUNCTION-EXPR-SXHASH (DECLARED-DEFINITION FUNCTION-SPEC)))

;;; This should be called as each function is begun to be compiled
(DEFUN BEGIN-PROCESSING-FUNCTION (NAME)
  (COMPILATION-DEFINE NAME))

;;; There can be duplicates of local vars on allvars because of the variable overlaping hack.
;;; Don't disturb special vars.
(DEFUN ELIMINATE-DUPLICATES-AND-REVERSE (VAR-LIST)
  (PROG (ANS)
     L  (COND ((NULL VAR-LIST) (RETURN ANS))
	      ((NULL (DOLIST (V ANS)
		       (IF (AND (EQ (VAR-NAME V) (VAR-NAME (CAR VAR-LIST)))
				(NOT (EQ (CAR (VAR-LAP-ADDRESS V)) 'SPECIAL))
				(EQUAL (VAR-LAP-ADDRESS V) (VAR-LAP-ADDRESS (CAR VAR-LIST))))
			   (RETURN T))))	;this a local duplicate, flush
	       (SETQ ANS (CONS (CAR VAR-LIST) ANS))))
	(SETQ VAR-LIST (CDR VAR-LIST))
	(GO L)))

#|
Expand functions that want keyword arguments.
Make them take &REST args instead, and give them code to look up the keywords.

starting from this
(DEFUN FOO (X &REST Y &KEY MUMBLE (BLETCH T BLETCHP) &AUX BAZZZ)
   BODY)

We create this:
(We call with the rest arg starting with 'permutation-table <table>
 before the first keyword, if we want to memoize the keyword lookup.
 The permutation table gets filled with the index of each specified
 keyword in the list of allowed keywords, and then it is used to
 permute the args, rather than looking up the keywords again.
 The leader of the permutation table records the fef that the table
 was computed for.  If the function definition changes, the table
 is recomputed).
(DEFUN FOO (X &REST Y &AUX (MUMBLE KEYWORD-GARBAGE) (BLETCH T) BLETCHP)
  (SI:STORE-KEYWORD-ARG-VALUES (%STACK-FRAME-POINTER)
			       Y '(:MUMBLE :BLETCH)
			       NIL		;T if &ALLOW-OTHER-KEYS
			       2)		;1st 2 keywords required.
  (AND (EQ MUMBLE KEYWORD-GARBAGE) (FERROR ...))
  ((LAMBDA (&AUX BAZZZ)
     BODY)))

|#

;;; Given a lambda which uses &KEY, return an equivalent one
;;; which does not use &KEY.  It takes a &REST arg instead
;;; (though if the original one had a rest arg, it uses that one).
;;; If there is no ARGLIST declaration for this function, we make one
;;; so that the user is still told that the function wants keyword args.
(DEFUN EXPAND-KEYED-LAMBDA (LAMBDA-EXP)
  (LET (LAMBDA-LIST BODY
	MAYBE-REST-ARG KEYCHECKS
	POSITIONAL-ARGS AUXVARS REST-ARG POSITIONAL-ARG-NAMES
 	KEYKEYS KEYNAMES KEYINITS KEYFLAGS ALLOW-OTHER-KEYS
	PSEUDO-KEYNAMES DECLS)
    (IF (EQ (CAR LAMBDA-EXP) 'LAMBDA)
	(SETQ LAMBDA-LIST (CADR LAMBDA-EXP) BODY (CDDR LAMBDA-EXP))
      (SETQ LAMBDA-LIST (CADDR LAMBDA-EXP) BODY (CDDDR LAMBDA-EXP)))	;named-lambda
    (MULTIPLE-VALUE-SETQ (POSITIONAL-ARGS NIL AUXVARS
			  REST-ARG POSITIONAL-ARG-NAMES
			  KEYKEYS KEYNAMES KEYINITS KEYFLAGS ALLOW-OTHER-KEYS)
      (DECODE-KEYWORD-ARGLIST LAMBDA-LIST))
    (SETQ PSEUDO-KEYNAMES (COPY-LIST KEYNAMES))
    (MULTIPLE-VALUE-SETQ (NIL DECLS)
;>> need to pass environment into extract-declarations here
      (EXTRACT-DECLARATIONS BODY NIL NIL))
    (DO ((D DECLS (CDR D)))
	((NULL D))
      (SETF (CAR D) `(DECLARE ,(CAR D))))
    ;; For each keyword arg, decide whether we need to init it to KEYWORD-GARBAGE
    ;; and check explicitly whether that has been overridden.
    ;; If the arg is optional
    ;; and the initial value is a constant, we can really init it to that.
    ;; Otherwise we create a dummy variable initialized to KEYWORD-GARBAGE;
    ;; after all keywords are decoded, we bind the intended variable, in sequence.
    ;; However a var that can shadow something (including any special var)
    ;; must always be replaced with a dummy.
    (DO ((KIS KEYINITS (CDR KIS))
	 (KNS KEYNAMES (CDR KNS))
	 (PKNS PSEUDO-KEYNAMES (CDR PKNS))
	 (KFS KEYFLAGS (CDR KFS)))
	((NULL KNS))
      (LET ((KEYNAME (CAR KNS)) PSEUDO-KEYNAME
	    (KEYFLAG (CAR KFS)) (KEYINIT (CAR KIS)))
	(OR (AND (NULL KEYFLAG)
		 (CONSTANTP KEYINIT)
		 (NOT (ASSQ KEYNAME VARS))
		 (NOT (LEXICAL-VAR-P KEYNAME))
		 (NOT (SPECIALP KEYNAME)))
	    (PROGN (SETF (CAR KIS) 'SI::KEYWORD-GARBAGE)
		   (SETQ PSEUDO-KEYNAME (GENSYM))
		   (SETF (CAR PKNS) PSEUDO-KEYNAME)
		   (PUSH `(,KEYNAME
			   (COND ((EQ ,PSEUDO-KEYNAME SI::KEYWORD-GARBAGE)
				  ,KEYINIT)
				 (T ,(AND KEYFLAG `(SETQ ,KEYFLAG T))
				    ,PSEUDO-KEYNAME)))
			 KEYCHECKS)))))
    (SETQ KEYFLAGS (REMQ NIL KEYFLAGS))
    (SETQ KEYCHECKS (NREVERSE KEYCHECKS))

    ;; If the user didn't ask for a rest arg, make one for the
    ;; outer function anyway.
    (OR REST-ARG (SETQ REST-ARG (GENSYM)
		       MAYBE-REST-ARG (LIST '&REST REST-ARG)))
    `(LAMBDA (,@POSITIONAL-ARGS ,@MAYBE-REST-ARG)
       (LET* (,@(MAPCAR #'(LAMBDA (V INIT) `(,V ,INIT)) PSEUDO-KEYNAMES KEYINITS)
	      ,@KEYFLAGS)
;       (COND ((EQ (CAR ,REST-ARG) 'PERMUTATION-TABLE)
;	      (OR (%PERMUTE-ARGS)
;		  (PROGN (RECOMPUTE-KEYWORD-PERMUTATION-TABLE
;			   (CDR ,REST-ARG)
;			   (%P-CONTENTS-OFFSET (%STACK-FRAME-POINTER) %LP-FEF)
;			   ',KEYKEYS)
;			 (%PERMUTE-ARGS)))
;	      ;; If the function really wants the rest arg,
;	      ;; flush the permutation table and its keyword.
;	      ,(AND (NOT MAYBE-REST-ARG) `(SETQ ,REST-ARG (CDDR ,REST-ARG))))
;	     (T
	 (WHEN ,REST-ARG
	   (SI::STORE-KEYWORD-ARG-VALUES (%STACK-FRAME-POINTER)
					 ,REST-ARG ',KEYKEYS
					 ,ALLOW-OTHER-KEYS
					 ;; kludgey-compilation-variable-location is just like
					 ;; variable-location except that it doesn't increment
					 ;; the var-use-count of its arg
					 (KLUDGEY-COMPILATION-VARIABLE-LOCATION
					   ,(CAR PSEUDO-KEYNAMES))))
	 (LET* ,KEYCHECKS
	   ,@DECLS
	   ((LAMBDA ,AUXVARS . ,BODY)))))))

;This optimization isn't in use yet, and may never be
; if microcoding STORE-KEYWORD-ARG-VALUES is winning enough.

;;; Given a permutation table for keyword args whose contents are garbage,
;;; and the actual arglist with keywords,
;;; compute the contents of the permutation table
;;; based on calling the fef NEW-FEF.
;(DEFUN RECOMPUTE-KEYWORD-PERMUTATION-TABLE (TABLE-AND-ARGS NEW-FEF KEYWORDS)
;  (LET ((TABLE (CAR TABLE-AND-ARGS)))
;    (DO ((I 0 (1+ I))
;	 (ARGS1 (CDR TABLE-AND-ARGS) (CDDR ARGS1)))
;	((NULL ARGS1)
;	 (SETF (ARRAY-LEADER TABLE 0) NEW-FEF))
;      (LET ((KEYWORD (CAR ARGS1)))
;	(DO (INDEX) (())
;	  (SETQ INDEX (FIND-POSITION-IN-LIST KEYWORD KEYWORDS))
;	  (AND INDEX (RETURN (SETF (AREF TABLE I) INDEX)))
;	  (SETQ KEYWORD (CERROR T NIL :UNDEFINED-ARG-KEYWORD
;				"Keyword arg keyword ~S unrecognized"
;				KEYWORD)))))))

;;; Given a form that is a call to a function which takes keyword args,
;;; stick in a permutation table, if the keyword names are constant.
;;; The question of how calls to such functions are detected is still open.
;(DEFUN OPTIMIZE-KEYWORD-CALL (FORM)
;  (LET ((ARGS-INFO (ARGS-INFO (CAR FORM))))
;    (LET ((KEYARGS (CDR (NTHCDR (LDB %%ARG-DESC-MAX-ARGS ARGS-INFO) FORM))))
;      (COND ((DO ((TAIL KEYARGS (CDDR TAIL)))
;		 ((NULL TAIL) T)
;	       (OR (QUOTEP (CAR TAIL)) (RETURN NIL)))
;	     ;; Here if every keyword name is quoted.
;	     `(,@(LDIFF FORM KEYARGS)
;	       'PERMUTATION-TABLE
;	       ',(MAKE-ARRAY (TRUNCATE 2 (LENGTH KEYARGS))
;			     :LEADER-LENGTH 1 :TYPE ART-8B)
;	       . ,KEYARGS))
;	    (T FORM)))))

;;; Temporary definition for what ought to be defined in the microcode.
;;; Keyed functions' expansions call this, but until calls are open-coded
;;; the arguments will never be such as to make the call actually happen.
;;; The open-coding won't be installed until the ucode function works.
;;; Meanwhile this prevents warning messages when keyed functions are compiled.
;(DEFUN %PERMUTE-ARGS () (FERROR NIL "%PERMUTE-ARGS called"))


;;;; Pass 1.
;;; We expand all macros and perform source-optimizations
;;; according to the OPTIMIZERS properties.  Internal lambdas turn into progs.
;;; Free variables are made special and put on FREEVARS unless on INSTANCEVARS.
;;; PROGs are converted into an internal form which contains pointers
;;; to the VARS and *GOTAG-ENVIRONMENT* lists of bound variables and prog tags.
;;; All self-evaluating constants (including T and NIL) are replaced by
;;; quote of themselves.
;;; P1VALUE is NIL when compiling a form whose value is to be discarded.
;;; P1VALUE is PREDICATE when compiling for predicate value (nilness or non-nilness)
;;; P1VALUE is an integer n when compiling for at most n values (n  1)
;;; P1VALUE is T when all values are to be passed back
;;; Some macros and optimizers look at it.

(DEFUN P1V (FORM &OPTIONAL (P1VALUE T) DONT-OPTIMIZE)
  (P1 FORM DONT-OPTIMIZE))

(DEFUN P1 (FORM &OPTIONAL DONT-OPTIMIZE &AUX TM)
  (UNLESS DONT-OPTIMIZE
    (SETQ FORM (COMPILER-OPTIMIZE FORM)))
  (SETQ FORM (COND ((ATOM FORM)
		    (COND ((SELF-EVALUATING-P FORM)
			   `',FORM)
			  ((SETQ TM (ASSQ FORM VARS))
			   (AND (EQ (VAR-KIND TM) 'FEF-ARG-FREE)
				(ZEROP (VAR-USE-COUNT TM))
				(PUSH (VAR-NAME TM) FREEVARS))
			   (INCF (VAR-USE-COUNT TM))
			   (VAR-LAP-ADDRESS TM))
			  ((TRY-REF-SELF FORM))
			  ((SPECIALP FORM)
			   (MAKESPECIAL FORM) FORM)
			  ((TRY-REF-LEXICAL-VAR FORM))
			  (T (MAKESPECIAL FORM) FORM)))
		   ((EQ (CAR FORM) 'QUOTE) FORM)
		   ;; Certain constructs must be checked for here
		   ;; so we can call P1 recursively without setting TLEVEL to NIL.
		   ((NOT (ATOM (CAR FORM)))
		    ;; Expand any lambda macros -- just returns old function if none found
		    (LET ((FCTN (CAR FORM)))
		      (OR (SYMBOLP (CAR FCTN))
			  (WARN 'BAD-FUNCTION-CALLED :IMPOSSIBLE
				"There appears to be a call to a function whose CAR is ~S."
				(CAR FCTN)))
		      (IF (MEMQ (CAR FCTN) '(LAMBDA NAMED-LAMBDA))
			  (P1LAMBDA FCTN (CDR FORM))
			;; Old Maclisp evaluated functions.
			(WARN 'EXPRESSION-AS-FUNCTION :VERY-OBSOLETE
			      "The expression ~S is used as a function; use ~S."
			      (CAR FORM) 'FUNCALL)
			(P1 `(FUNCALL . ,FORM)))))
		   ((NOT (SYMBOLP (CAR FORM)))
		    (WARN 'BAD-FUNCTION-CALLED :IMPOSSIBLE
			  "~S is used as a function to be called." (CAR FORM))
		    (P1 `(PROGN . ,(CDR FORM))))
		   ((SETQ TM (ASSQ (CAR FORM) *LOCAL-FUNCTIONS*))
		    (INCF (VAR-USE-COUNT (CADR TM)))
		    `(FUNCALL ,(TRY-REF-LEXICAL-HOME (CADR TM))
			      . ,(P1PROGN-1 (CDR FORM))))
		   ((MEMQ (CAR FORM) '(PROG PROG*))
		    (P1PROG FORM))
		   ((MEMQ (CAR FORM) '(LET LET*))
		    (P1LET FORM))
		   ((EQ (CAR FORM) 'BLOCK)
		    (P1BLOCK FORM))
		   ((EQ (CAR FORM) 'TAGBODY)
		    (P1TAGBODY FORM))
		   ((EQ (CAR FORM) '%POP)	;P2 specially checks for this
		    FORM)
		   (T (SETQ TLEVEL NIL)
		      ;; Check for functions with special P1 handlers.
		      (IF (SETQ TM (GET (CAR FORM) 'P1))
			  (FUNCALL TM FORM)
			(IF (NOT (AND ALLOW-VARIABLES-IN-FUNCTION-POSITION-SWITCH
				      (ASSQ (CAR FORM) VARS)
				      (NULL (FUNCTION-P (CAR FORM)))))
			    (P1ARGC FORM (GETARGDESC (CAR FORM)))
			  (WARN 'EXPRESSION-AS-FUNCTION :VERY-OBSOLETE
				"The variable ~S is used in function position; use FUNCALL."
				(CAR FORM))
			  (P1 `(FUNCALL . ,FORM)))))))
  (IF (AND (ATOM FORM) (SELF-EVALUATING-P FORM))
      ;; a p1 handler may return :foo, for example
      `',FORM
      FORM))

(DEFUN FUNCTION-P (X)
  (COND ((SYMBOLP X)
	 (OR (FBOUNDP X) (GETL X '(*EXPR ARGDESC))))
	((FDEFINEDP X))
	(T (FUNCALL (GET (CAR X) 'FUNCTION-SPEC-HANDLER) 'SI::COMPILER-FDEFINEDP X))))

(DEFUN MSPL2 (X)
  (WHEN (LET ((BARF-SPECIAL-LIST THIS-FUNCTION-BARF-SPECIAL-LIST))
	  (NOT (SPECIALP X)))
    ;; Here unless this variable was either 1) declared special, or
    ;; 2) already used free in this function.
    (UNLESS INHIBIT-SPECIAL-WARNINGS
      (WARN 'FREE-VARIABLE :MISSING-DECLARATION
	    "The variable ~S is used free; assumed special." X))
    (LET ((DEFAULT-CONS-AREA BACKGROUND-CONS-AREA))
      (UNLESS INHIBIT-SPECIAL-WARNINGS  ;Free var in a DEFSUBST shouldn't be special for whole file.
	(PUSHNEW X BARF-SPECIAL-LIST :TEST #'EQ))
      (PUSH X THIS-FUNCTION-BARF-SPECIAL-LIST))
    (WHEN (ASSQ X ALLVARS)
      (WARN 'FREE-VARIABLE :IMPOSSIBLE
	    " ~S was previously assumed local; you will lose!" X))))

(DEFUN MAKESPECIAL (X)
  (MSPL2 X)
  (PUSHNEW X FREEVARS :TEST #'EQ)
  T)

;;; make the first cons of form a 3-hunk to flag that has been optimized
;;; what a hack! rms' idea
(defun flag-already-optimized (form &aux l)
  (if (not (consp form))
      form
    (without-interrupts
      (setq l (make-list 3 :initial-element 'already-optimized))
      (setf (car l) (car form)
	    (cadr l) (cdr form))
      (%p-dpb cdr-normal %%q-cdr-code (%pointer l))
      (%p-dpb cdr-normal %%q-cdr-code (1+ (%pointer l)))
      l)))

(defun already-optimized-p (form)
  (without-interrupts
    (or (atom form)
	(and (eq (%p-ldb %%q-cdr-code (%pointer form)) cdr-normal)
	     (eq (%p-ldb %%q-cdr-code (1+ (%pointer form))) cdr-normal)
	     (eq (%p-ldb %%q-pointer (+ (%pointer form) 2)) (%pointer 'already-optimized))))))

;;; Given a form, apply optimizations and expand macros until no more is possible
;;; (at the top level).  Also apply style-checkers to the supplied input
;;; but not to generated output.  This function is also in charge of checking for
;;; too few or too many arguments so that this happens before optimizers are applied.
;;; Note that this does not mean that optimizers will always get a form with the
;;; correct number of arguments; it just means that they shouldn't (in general) barf about
;;; the wrong number.
(defun compiler-optimize (form &aux (macro-cons-area
				      (if (eq qc-tf-output-mode 'compile-to-core)
					  background-cons-area
					  default-cons-area))
			  	    (*check-style-p* *check-style-p*))
  (if (already-optimized-p form)
      form
    (do (tm fn local-definition optimizations-begun-flag)
	((atom form))				;Do until no more expansions possible
      (let ((default-cons-area macro-cons-area))
	(setq fn (lambda-macro-expand (car form))))
      (unless (eq fn (car form)) (setq form (cons fn (cdr form))))
      (unless optimizations-begun-flag
	;; Check for too few or too many arguments
	(check-number-of-args form fn))
      (setq local-definition
	    (and (symbolp fn) (fsymeval-in-function-environment fn *function-environment*)))
      (unless (or optimizations-begun-flag
		  local-definition
		  (not *check-style-p*)
		  inhibit-style-warnings-switch)
	;; Do style checking
	(cond ((atom fn)
	       (and (symbolp fn)
		    (setq tm (get fn 'style-checker))
		    (funcall tm form)))
	      ((not run-in-maclisp-switch))
	      ((memq (car fn) '(lambda named-lambda))
	       (lambda-style fn))
	      ((memq (car fn) '(curry-before curry-after))
	       (warn 'not-in-maclisp :maclisp "~S does not work in Maclisp."
		     (car fn)))))
      ;; Optimize args to vanilla functions
      (when (symbolp fn)
	;; don't optimize args to macros of special forms, or to frobs with p1 handlers
	(unless (if local-definition
		    (eq (car-safe local-definition) 'macro)
		  (or (get fn 'p1)
		      (macro-function fn)
		      (special-form-p fn)))
	  (setq form `(,(car form) . ,(mapcar #'compiler-optimize (cdr form))))))
      (or (unless (or local-definition (not (symbolp fn)))
	    (dolist (opt (get fn 'optimizers))
	      (unless (eq form (setq form (funcall opt form)))
		;; Optimizer changed something, don't do macros this pass
		(setq optimizations-begun-flag t)
		(return t))))
	  ;; No optimizer did anything => try expanding macros.
	  (warn-on-errors ('macro-expansion-error "Error expanding macro ~S:" fn)
	    ;; This LET returns T if we expand something.
	    (or (let ((default-cons-area macro-cons-area)
		      (record-macros-expanded t))
		  (multiple-value-setq (form tm)
		    (compiler-macroexpand-1 form))
		  tm)				;non-nil if macroexpansion happened
		;; Stop looping, no expansions apply
		(return)))
	  ;; The body of the WARN-ON-ERRORS either does RETURN or returns T.
	  ;; So if we get here, there was an error inside it.
	  (return (setq form `(error-macro-expanding ',form))))
      ;; Only do style checking the first time around
      (setq *check-style-p* nil))
    ;; Result is FORM
    (flag-already-optimized form)))

(DEFPROP ERROR-MACRO-EXPANDING T :ERROR-REPORTER)
(DEFUN ERROR-MACRO-EXPANDING (FORM)
  (FERROR NIL "The form ~S which appeared at this point
was not compiled due to an error in macro expansion." FORM))

;;>> this should eventually be different from macroexpand-1, in that it supply a
;;>> *macroexpand-hook* which will not do mogus things with things we know about
;;>> specially (such as (common-lisp-only) "macros" which we really implement as
;;>> special forms, or things with p1 handlers or optimizers)
;;>> For now, macroexpand-1 doesn't hack the things with si::alternate-macro-definitions,
;;>> so this will do.
;;>> Also, we really should pass more than just the function env -- also need declarations &c.
(defun compiler-macroexpand-1 (form)
  ;; CAR of environment is local macros (and functions)
  (with-stack-list (env *function-environment*)
    (macroexpand-1 form env)))

;;; Given a non-atomic form issue any warnings required because of wrong number of arguments.
;;; This function has some of the same knowledge as GETARGDESC but doesn't call
;;; it because GETARGDESC has to do a lot more.
;;; This function should never get an error and never warn about
;;; anything that gets warned about elsewhere.
(DEFUN CHECK-NUMBER-OF-ARGS (FORM &OPTIONAL FUNCTION)
  (IF (NULL FUNCTION) (SETQ FUNCTION (CAR FORM)))
  (LET* (TEM
	 ARGLIST
	 NARGS
	 (MIN NIL)
	 (MAX 0)
	 (ARGS-INFO NIL)
	 (LOCALP NIL)
	 (FN FUNCTION))
    (AND (SYMBOLP FN)
	 ;; If FN is a name defined lexically by FLET or LABELS, use its definition.
	 (SETQ LOCALP (FSYMEVAL-IN-FUNCTION-ENVIRONMENT FN *FUNCTION-ENVIRONMENT*))
	 (SETQ FN LOCALP))
;	 (SETQ LOCALP (ASSQ FN *LOCAL-FUNCTIONS*)
;	 (SETQ FN (CADDR LOCALP)))
    (FLET ((BAD-ARGUMENTS (MSG &OPTIONAL (TYPE 'WRONG-NUMBER-OF-ARGUMENTS)
			       		 (SEVERITY :PROBABLE-ERROR))
	      (WARN TYPE SEVERITY (IF LOCALP
				      "Locally defined function ~S called with ~A"
				      "Function ~S called with ~A")
		    (CAR FORM) MSG)))
      (TAGBODY
       TOP
	  (SETQ FN (LAMBDA-MACRO-EXPAND FN))
	  (SETQ ARGLIST (IGNORE-ERRORS (ARGLIST FN 'COMPILE)))
	  (COND ((AND (CONSP FN) (FUNCTIONP FN T))
		 (UNLESS (CONSP ARGLIST) (RETURN-FROM CHECK-NUMBER-OF-ARGS))
		 (DOLIST (X ARGLIST)
		   (COND ((EQ X '&OPTIONAL) (SETQ MIN MAX))
			 ((OR (EQ X '&REST) (EQ X '&BODY) (EQ X '&KEY))
			  (UNLESS MIN (SETQ MIN MAX))
			  (SETQ MAX MOST-POSITIVE-FIXNUM)
			  (RETURN))
			 ((EQ X '&AUX) (RETURN))
			 ((MEMQ X LAMBDA-LIST-KEYWORDS))
			 (T (INCF MAX)))))
		((NOT (SYMBOLP FN))
		 ;; Unknown type, don't check
		 (RETURN-FROM CHECK-NUMBER-OF-ARGS))
		((SETQ TEM (GET FN 'ARGDESC))
		 (DOLIST (X TEM)
		   (COND ((MEMQ 'FEF-ARG-REQ (CADR X))
			  (INCF MAX (CAR X)))
			 ((MEMQ 'FEF-ARG-OPT (CADR X))
			  (OR MIN (SETQ MIN MAX))
			  (INCF MAX (CAR X)))
			 ((MEMQ 'FEF-ARG-REST (CADR X))
			  (OR MIN (SETQ MIN MAX))
			  (SETQ MAX MOST-POSITIVE-FIXNUM)))))
		((SETQ TEM (GET FN 'QINTCMP))
		 (SETQ MAX TEM))
		((SETQ TEM (GET FN 'Q-ARGS-PROP))
		 (SETQ ARGS-INFO TEM))
		;; Take care of recursive calls to function being compiled.
		((EQ FN THIS-FUNCTION-ARGLIST-FUNCTION-NAME)
		 (DOLIST (X THIS-FUNCTION-ARGLIST)
		   (COND ((EQ X '&OPTIONAL) (SETQ MIN MAX))
			 ((OR (EQ X '&REST) (EQ X '&BODY) (EQ X '&KEY))
			  (UNLESS MIN (SETQ MIN MAX))
			  (SETQ MAX MOST-POSITIVE-FIXNUM)
			  (RETURN))
			 ((EQ X '&AUX) (RETURN))
			 ((MEMQ X LAMBDA-LIST-KEYWORDS))
			 (T (INCF MAX)))))
		((FBOUNDP FN)
		 (SETQ TEM (SI:UNENCAPSULATE-FUNCTION-SPEC FN))
		 (COND ((NOT (EQ TEM FN))
			(SETQ FN TEM)
			(GO TOP)))
		 (SETQ TEM (FSYMEVAL FN))
		 (COND ((OR (SYMBOLP TEM) (CONSP TEM))
			(SETQ FN TEM)
			(GO TOP))
		       (T (SETQ ARGS-INFO (%ARGS-INFO TEM)))))
		(T ;;No information available
		 (RETURN-FROM CHECK-NUMBER-OF-ARGS))))
      (WHEN ARGS-INFO
	(SETQ MIN (LDB %%ARG-DESC-MIN-ARGS ARGS-INFO)
	      MAX (IF (BIT-TEST (LOGIOR %ARG-DESC-QUOTED-REST %ARG-DESC-EVALED-REST)
				ARGS-INFO)
		      MOST-POSITIVE-FIXNUM
		    (LDB %%ARG-DESC-MAX-ARGS ARGS-INFO))))
      (SETQ NARGS (LENGTH (CDR FORM)))	;Now that we know it's not a macro
      (COND ((< NARGS (OR MIN MAX))
	     (BAD-ARGUMENTS "too few arguments."))
	    ((> NARGS MAX)
	     (BAD-ARGUMENTS "too many arguments."))
	    ((CONSP ARGLIST)
	     (LET* ((KEYARGS (MEMQ '&KEY ARGLIST))
		    (KEYFORM (NTHCDR (OR MAX MIN) (CDR FORM))))
	       (WHEN (AND KEYARGS KEYFORM)
		 (IF (ODDP (LENGTH KEYFORM))
		     (BAD-ARGUMENTS "no value supplied for some keyword argument.")
		   (LET ((ALLOW-OTHER-KEYS (OR (MEMQ '&ALLOW-OTHER-KEYS ARGLIST)
					       (GETF KEYFORM ':ALLOW-OTHER-KEYS))))
		     (LOOP FOR KEY IN KEYFORM BY #'CDDR
			   WHEN (EQ (CAR-SAFE KEY) 'QUOTE) DO (SETQ KEY (CADR KEY))
			   DOING (COND ((KEYWORDP KEY)
					(UNLESS
					  (OR ALLOW-OTHER-KEYS
					      (DOLIST (X KEYARGS)
						(IF (MEMQ X LAMBDA-LIST-KEYWORDS)
						    NIL
						  (IF 
						    (IF (CONSP X)
							(IF (CONSP (CAR X))
							    ;; ((:frob foo) bar)
							    (EQ KEY (CAAR X))
							  ;; (foo bar)
							  (STRING= KEY (CAR X)))
						      ;; foo
						      (STRING= KEY X))
						    (RETURN T)))))
					  (BAD-ARGUMENTS
					    (FORMAT NIL "the unrecognized keyword ~S"
						    KEY))))
				       ((CONSTANTP KEY)
					(BAD-ARGUMENTS
					  (FORMAT NIL "~S appearing where a keyword should"
						  KEY))))))))))))))
		   

;;; Pass 1 processing for a call to an ordinary function (ordinary, at least, for pass 1).
;;; FORM is the call to the function, and DESC is the GETARGDESC of the function.
;;; Processing consists of P1'ing all evaluated arguments, but not the quoted ones.
;;; DESC is used to determine which is which.
;;; In addition, &FUNCTIONAL arguments are broken off and separately compiled.
;;; We process the args by copying the arglist,
;;;  and rplaca'ing each arg by P1 of itself if needed.
(DEFUN P1ARGC (FORM DESC)
  (IF (AND (MEMQ 'FEF-ARG-REST (CADAR DESC))
	   (MEMQ 'FEF-QT-QT (CADAR DESC)))
      FORM
    (DO* ((COUNT 0 (1- COUNT))
	  (ARGS-LEFT (COPY-LIST (CDR FORM)) (CDR ARGS-LEFT))
	  (ARG-P1-RESULTS ARGS-LEFT)
	  (FCTN (CAR FORM))
	  (P1VALUE 1)				;function calling uses only first value
	  (DESCS-LEFT DESC)
	  TOKEN-LIST
	  TM)
	 (())
      ;; If all arguments processed, return.
      (COND ((NULL ARGS-LEFT)
	     (RETURN (CONS FCTN ARG-P1-RESULTS)))
	    ((ATOM ARGS-LEFT)
	     (WARN :IMPOSSIBLE 'NON-NIL-END-OF-FORM
		   "The form ~S ends in a non-NIL atomic cdr."
		   FORM)
	     (IF (ATOM ARG-P1-RESULTS)
		 (RETURN (LIST FCTN))
	       (SETF (CDR (LAST ARG-P1-RESULTS)) NIL)
	       (RETURN (CONS FCTN ARG-P1-RESULTS)))))
	
      ;; Figure out what descriptor to use for the next argument.
      ;; TOKEN-LIST is the actual descriptor, and COUNT
      ;; is the number of arguments left for it to apply to.
      (WHEN (ZEROP COUNT)
	(COND ((NULL DESCS-LEFT)
	       ;; Out of descriptors => treat excess args as evalled.
	       (SETQ DESCS-LEFT '((#o1005 (FEF-ARG-OPT FEF-QT-EVAL))))))
	(SETQ COUNT (CAAR DESCS-LEFT))
	(SETQ TOKEN-LIST (CADAR DESCS-LEFT))
	(SETQ DESCS-LEFT (CDR DESCS-LEFT))
	(IF (MEMQ 'FEF-ARG-REST TOKEN-LIST)
	    (SETQ COUNT #o1005)))

      ;; Process the next argument according to its descriptor.
      (COND ((MEMQ 'FEF-QT-QT TOKEN-LIST))
	    ((OR (MEMQ 'FEF-QT-EVAL TOKEN-LIST)
		 (MEMQ 'FEF-QT-DONTCARE TOKEN-LIST))
	     (RPLACA ARGS-LEFT
		     (IF (AND (MEMQ 'FEF-FUNCTIONAL-ARG TOKEN-LIST)
			      (NOT (ATOM (SETQ TM (COMPILER-OPTIMIZE (CAR ARGS-LEFT)))))
			      (EQ (CAR TM) 'QUOTE))	;Look for '(LAMBDA...)
			 (P1FUNCTION TM)
		       (P1 (CAR ARGS-LEFT)))))
	    (T (BARF TOKEN-LIST 'BAD-EVAL-CODE 'BARF))))))

;;; Return T if OBJECT is something quoted.
(DEFSUBST QUOTEP (OBJECT)
  (EQ (CAR-SAFE OBJECT) 'QUOTE))

;;; When a var is handled by P1BINDVAR which is an optional arg with a specified-flag,
;;; we push the flag name onto SPECIFIED-FLAGS so that a home will be made for the flag.
(DEFVAR SPECIFIED-FLAGS)

;;; Process a Lambda-list (X), making the variables by default of kind KIND
;;; (FEF-ARG-REQ for the top-level lambda,
;;;  FEF-ARG-AUX or FEF-ARG-INTERNAL-AUX for progs).
;;; Return a prog variable list for the same variables with their initializations if any,
;;; with P1 done on each initialization.
;;; This function gobbles down the variables and processes keywords.
;;; Each variable, with its appropeiate keyword info, is passed to P1LMB.
;;; We can do either sequential or parallel binding.
;;; Processing of variables is done in two steps:
;;; First, create the homes
;;; Second, if these are not FEF-ARG-INTERNAL-AUX vars,
;;;  put the homes on VARS and ALLVARS.
;;; Third, process all the variables' initializations.
;;; Finally, put the homes on VARS and ALLVARS if not already there.

;;; For variables whose scope is the whole function (not FEF-ARG-INTERNAL-AUX),
;;; the order is designed so that variables bound inside their initializations
;;; all come after all the variables of the original (higher) level.
;;; This is needed to make sure that (DEFUN FOO (&OPTIONAL (A (LET ((C ...)) ...)) B) ...)
;;; does not put C into VARS before B.

;;; For FEF-ARG-INTERNAL-AUX variables, we want the variables bound
;;; inside the initializations to come first, since they are used first.
;;; That way, our own variables overlap with them rather than vice versa.
;;; As a result, the variable with the original home is always the first one used.
;;; This is important for deciding which variables need explicit initialization.

;;; The IGNORE-NIL-P argument is used by MULTIPLE-VALUE-BIND to say
;;;  that if NIL appears as a variable, its initial value should be evaluated
;;;  and discarded.
(DEFUN P1SBIND (X KIND PARALLEL IGNORE-NIL-P THIS-FRAME-DECLARATIONS &AUX MYVARS)
  ;; First look at the var specs and make homes, pushing them on MYVARS (reversed).
  (LET ((EVALCODE 'FEF-QT-DONTCARE)
	(SPECIALNESS NIL)
	(SPECIFIED-FLAGS NIL)
	(ALREADY-REST-ARG NIL)
	(ALREADY-AUX-ARG NIL)
	(MISC-TYPES NIL)
	(P1VALUE 1))
    (DO ((X X (CDR X))
	 TEM)
	((NULL X))
      (COND ((SETQ TEM (ASSQ (CAR X) '((&OPTIONAL . FEF-ARG-OPT)
				       (&REST . FEF-ARG-REST)
				       (&AUX . FEF-ARG-AUX))))
	     (IF (OR (EQ KIND 'FEF-ARG-AUX)
		     (EQ KIND 'FEF-ARG-INTERNAL-AUX))
		 (WARN 'BAD-BINDING-LIST :IMPOSSIBLE
		       "A lambda-list keyword (~S) appears in an internal binding list."
		       (CAR X))
	       (SETQ KIND (CDR TEM))))
	    ((SETQ TEM (ASSQ (CAR X) '((&EVAL . FEF-QT-EVAL)
				       (&QUOTE . FEF-QT-QT))))
	     (SETQ EVALCODE (CDR TEM)))
	    ((EQ (CAR X) '&FUNCTIONAL)
	     (PUSH 'FEF-FUNCTIONAL-ARG MISC-TYPES))
	    ((EQ (CAR X) '&SPECIAL)
	     (SETQ SPECIALNESS T))
	    ((EQ (CAR X) '&LOCAL)
	     (SETQ SPECIALNESS NIL))
	    ((EQ (CAR X) '&AUX)
	     (SETQ ALREADY-AUX-ARG T))
	    ((MEMQ (CAR X) LAMBDA-LIST-KEYWORDS))
	    (T
	     ;; Now (CAR X) should be a variable or (var init).
	     (LET ((VARN (IF (ATOM (CAR X)) (CAR X) (CAAR X))))
	       (IF (NOT (SYMBOLP VARN))
		   (WARN 'VARIABLE-NOT-SYMBOL :IMPOSSIBLE
			 "~S appears in a list of variables to be bound." VARN)
		 (AND (NOT (OR (STRING= VARN "IGNORE")
			       (STRING= VARN "IGNORED")
			       (NULL VARN)))
		      ;; Does this variable appear again later?
		      ;; An exception is made in that a function argument can be repeated
		      ;; after an &AUX.
		      (DOLIST (X1 (CDR X))
			(COND ((AND (EQ X1 '&AUX)
				    (NOT ALREADY-AUX-ARG))
			       (RETURN NIL))
			      ((OR (EQ X1 VARN)
				   (AND (NOT (ATOM X1)) (EQ (CAR X1) VARN)))
			       (RETURN T))))
		      (WARN 'BAD-BINDING-LIST :IMPLAUSIBLE
			    "The variable ~S appears twice in one binding list."
			    VARN))
		 (AND (EQ (CHAR (SYMBOL-NAME VARN) 0) #/&)
		      (WARN 'MISSPELLED-KEYWORD :IMPLAUSIBLE
			    "~S is probably a misspelled keyword." VARN))
		 (IF ALREADY-REST-ARG
		     (WARN 'BAD-LAMBDA-LIST :IMPOSSIBLE
			   "Argument ~S comes after the &REST argument." VARN))
		 (IF (EQ KIND 'FEF-ARG-REST)
		     (SETQ ALREADY-REST-ARG T))
		 (COND ((AND IGNORE-NIL-P (NULL VARN))
			(P1 (CADAR X)))		;Out of order, but works in these simple cases
		       ((OR (NULL VARN) (EQ VARN T))
			(WARN 'NIL-OR-T-SET :IMPOSSIBLE
			      "There is an attempt to bind ~S." VARN))
		       ((KEYWORDP VARN)
			(WARN 'KEYWORD-BOUND :IMPOSSIBLE
			      "There is an attempt to bind the keyword symbol ~S." VARN))
		       (T
			;; Make the variable's home.
			(IF SPECIALNESS
			    (LET ((DECL `(SPECIAL ,(COND ((SYMBOLP (CAR X)) (CAR X))
							 ((SYMBOLP (CAAR X)) (CAAR X))
							 (T (CADAAR X))))))
			      (PUSH DECL LOCAL-DECLARATIONS)
			      (PUSH DECL THIS-FRAME-DECLARATIONS)))
			(PUSH (P1BINDVAR (CAR X) KIND EVALCODE MISC-TYPES
					 THIS-FRAME-DECLARATIONS)
			      MYVARS)))
		 (SETQ MISC-TYPES NIL))))))

    ;; Arguments should go on ALLVARS now, so all args precede all boundvars.
    (OR (EQ KIND 'FEF-ARG-INTERNAL-AUX)
	(EQ KIND 'FEF-ARG-AUX)
	(SETQ ALLVARS (APPEND SPECIFIED-FLAGS MYVARS ALLVARS)))
    (MAPC #'VAR-COMPUTE-INIT SPECIFIED-FLAGS (CIRCULAR-LIST NIL))
    
    ;; Now do pass 1 on the initializations for the variables.
    (DO ((ACCUM)
	 (VS (REVERSE MYVARS) (CDR VS)))
	((NULL VS)
	 ;; If parallel binding, put all var homes on VARS
	 ;; after all the inits are through.
	 (COND (PARALLEL
		(SETQ VARS (APPEND MYVARS VARS))
		(COND ((OR (EQ KIND 'FEF-ARG-INTERNAL-AUX)
			   (EQ KIND 'FEF-ARG-AUX))
		       (MAPC #'VAR-CONSIDER-OVERLAP MYVARS)
		       (SETQ ALLVARS (APPEND MYVARS ALLVARS))))))
	 (NREVERSE ACCUM))
      (PUSH (VAR-COMPUTE-INIT (CAR VS) PARALLEL) ACCUM)
      ;; For sequential binding, put each var on VARS
      ;; after its own init.
      (UNLESS PARALLEL
	(COND ((OR (EQ KIND 'FEF-ARG-INTERNAL-AUX)
		   (EQ KIND 'FEF-ARG-AUX))
	       (VAR-CONSIDER-OVERLAP (CAR VS))
	       (PUSH (CAR VS) ALLVARS)))
	(PUSH (CAR VS) VARS)
	(LET ((TEM (CDDR (VAR-INIT (CAR VS)))))
	  (AND TEM (PUSH TEM VARS)))))))

;;; Create a home for a variable.
;;; We fill the variable's INIT slot with a list whose car is the init form
;;; and whose cadr may be the supplied-flag-name, or with nil if there is no init at all,
;;; rather than what is ultimately to go there (which gets there in VAR-COMPUTE-INIT).
(DEFUN P1BINDVAR (VARSPEC KIND EVAL-TYPE MISC-TYPES THIS-FRAME-DECLARATIONS)
  (LET (TYPE INIT-SPECS)
    (UNLESS (ATOM VARSPEC)
      (SETQ INIT-SPECS (CDR VARSPEC))
      (SETQ VARSPEC (CAR VARSPEC)))
    (IF (OR (EQ VARSPEC NIL) (EQ VARSPEC T))
	(WARN 'NIL-OR-T-SET :IMPOSSIBLE "There is an attempt to bind ~S." VARSPEC)
      ;; If this variable is an optional arg with a specified-flag,
      ;; remember to make a home for the flag as well.
      (WHEN (CADR INIT-SPECS)
	(COND ((NEQ KIND 'FEF-ARG-OPT)
	       (WARN 'BAD-ARGUMENT-LIST :IMPOSSIBLE
		     "The bound variable ~S has a specified-flag but isn't an optional arg."
		     VARSPEC))
	      ((NOT (SYMBOLP (CADR INIT-SPECS)))
	       (WARN 'BAD-ARGUMENT-LIST :IMPOSSIBLE
		     "The bound variable ~S has a specified-flag ~S which isn't a symbol."
		     VARSPEC (CADR INIT-SPECS)))
	      (T
	       (PUSH (CREATE-SPECIFIED-FLAG-HOME (CADR INIT-SPECS) THIS-FRAME-DECLARATIONS)
		     SPECIFIED-FLAGS))))
      (UNLESS (SYMBOLP VARSPEC)
	(WARN 'VARIABLE-NOT-SYMBOL :IMPOSSIBLE
	      "~S, not a symbol, appears as a variable to be bound."
	      VARSPEC))
      (SETQ TYPE (FIND-TYPE VARSPEC THIS-FRAME-DECLARATIONS))
      (IF (MEMQ TYPE '(FEF-SPECIAL FEF-REMOTE)) (SETQ SPECIALFLAG T))
      (VAR-MAKE-HOME VARSPEC TYPE KIND INIT-SPECS EVAL-TYPE MISC-TYPES
		     THIS-FRAME-DECLARATIONS))))

;;; Make a home for the "specified-flag" of an optional variable
;;; (such as, FOOP in &OPTIONAL (FOO 69 FOOP)).
;;; It is marked with FEF-ARG-SPECIFIED-FLAG in the misc flags.
;;; This home is pushed on VARS right after the last argument, before
;;; the first actual aux variable, and also before any locals bound
;;; in initializations of optionals, and its scope is the entire function.
;;; It is of kind "aux" and initialized to the constant T
;;; regardless of the fact that TLFUNINIT is already set and so
;;; (usually) only FEF-INI-COMP-C is allowed at this point.
(DEFUN CREATE-SPECIFIED-FLAG-HOME (NAME THIS-FRAME-DECLARATIONS)
  (VAR-MAKE-HOME NAME
		 (FIND-TYPE NAME THIS-FRAME-DECLARATIONS)
		 'FEF-ARG-AUX '('T)
		 'FEF-QT-DONTCARE '(FEF-ARG-SPECIFIED-FLAG)
		 THIS-FRAME-DECLARATIONS))

(DEFUN SPECIALP (SYMBOL)
  (DOLIST (DECL LOCAL-DECLARATIONS
		;; Here if no local declaration says anything.
		;; Try FILE-(UN)SPECIAL-LIST which reflect global decls in the file.
		(OR (MEMQ SYMBOL FILE-SPECIAL-LIST)
		    (AND (NOT (MEMQ SYMBOL FILE-UNSPECIAL-LIST))
			 (OR ALL-SPECIAL-SWITCH
			     (GET SYMBOL 'SPECIAL)
			     (GET SYMBOL 'SYSTEM-CONSTANT)
			     (MEMQ SYMBOL BARF-SPECIAL-LIST)))))
    (AND (MEMQ (CAR DECL) '(SPECIAL UNSPECIAL))
	 (MEMQ SYMBOL (CDR DECL))
	 (RETURN (EQ (CAR DECL) 'SPECIAL)))))

(DEFUN FIND-TYPE (SYMBOL THIS-FRAME-DECLARATIONS &AUX LOSE)
  (DOLIST (DECL THIS-FRAME-DECLARATIONS)
    (AND (MEMQ (CAR DECL) '(SPECIAL UNSPECIAL))
	 (MEMQ SYMBOL (CDR DECL))
	 (RETURN-FROM FIND-TYPE
	   (IF (EQ (CAR DECL) 'SPECIAL) 'FEF-SPECIAL 'FEF-LOCAL))))
  (DOLIST (DECL LOCAL-DECLARATIONS)
    (AND (MEMQ (CAR DECL) '(SPECIAL UNSPECIAL))
	 (MEMQ SYMBOL (CDR DECL))
	 (IF (EQ (CAR DECL) 'SPECIAL)
	     (RETURN-FROM NIL (SETQ LOSE T))
	   (RETURN-FROM FIND-TYPE 'FEF-LOCAL))))
  (IF (OR (MEMQ SYMBOL FILE-SPECIAL-LIST)
	  (AND (NOT (MEMQ SYMBOL FILE-UNSPECIAL-LIST))
	       (OR ALL-SPECIAL-SWITCH
		   (GET SYMBOL 'SPECIAL)
		   (GET SYMBOL 'SYSTEM-CONSTANT)
		   (MEMQ SYMBOL BARF-SPECIAL-LIST))))
      (RETURN-FROM FIND-TYPE 'FEF-SPECIAL))
  (IF (NOT LOSE)
      'FEF-LOCAL
    (WARN 'INHERITED-SPECIAL-DECLARATION :OBSOLETE
	  "A local SPECIAL declaration for ~S is being inherited.
The declaration should be at the beginning of the construct that binds the variable.
It still works now, but fix it quickly before it stops working." SYMBOL)
    'FEF-SPECIAL))
                                               
;;; Construct and return a variable home to go on VARS and ALLVARS.
;;; This home has, in the VAR-INIT slot, not what is supposed to be there
;;; but the actual initialization-form for the variable.
;;; Later, VAR-COMPUTE-INIT is called to fix that up.
(DEFUN VAR-MAKE-HOME (NAME TYPE KIND INIT-SPECS
		      EVAL-TYPE MISC-TYPES THIS-FRAME-DECLARATIONS &AUX HOME)
  (COND ((NULL (MEMQ KIND '(FEF-ARG-REQ FEF-ARG-OPT FEF-ARG-REST
			    FEF-ARG-AUX FEF-ARG-INTERNAL-AUX)))
	 (BARF KIND 'BAD-KIND 'BARF))
	((KEYWORDP NAME)
	 (WARN 'KEYWORD-BOUND :IMPOSSIBLE
	       "Binding the keyword symbol ~S." NAME))
	((CONSTANTP NAME)
	 (WARN 'SYSTEM-CONSTANT-BOUND :IMPLAUSIBLE
	       "Binding ~S, which is a constant." NAME))
	((MEMQ NAME (CDDR SELF-FLAVOR-DECLARATION))
	 (WARN 'INSTANCE-VARIABLE-BOUND :IMPLAUSIBLE
	       "Binding ~S, which has the same name as an instance variable of flavor ~S"
	       NAME (CAR SELF-FLAVOR-DECLARATION)))
	((AND (EQ NAME 'SELF)
	      SELF-FLAVOR-DECLARATION
	      (EQ TYPE 'FEF-SPECIAL))
	 (WARN 'SELF-BOUND :IMPLAUSIBLE
	       "Rebinding ~S. You may lose!" 'self)))
  ;; Rest args interfere with fast arg option except when there are no specials.
  ;; We need to look at this to
  ;;  decide how to process all the AUX variables and can't tell when processing
  ;;  the first one whether the next will be special.
  ;;  In any case, being wrong about this should not be able to produce
  ;;  incorrect code.
  (COND ((EQ KIND 'FEF-ARG-REST)
	 (SETQ FAST-ARGS-POSSIBLE NIL))
	((MEMQ KIND '(FEF-ARG-REQ FEF-ARG-OPT))
	 (AND INIT-SPECS (SETQ FAST-ARGS-POSSIBLE NIL))))
  ;; Detect vars bound to themselves which fail to be special.
  (WHEN (AND (EQ NAME (CAR INIT-SPECS))
	     (NOT (ASSQ NAME VARS))
	     ;; If variable is already accessible lexically, it need not be special.
	     (DOLIST (FRAME *OUTER-CONTEXT-VARIABLE-ENVIRONMENT* T)
	       (WHEN (ASSQ NAME FRAME) (RETURN NIL))))
    (MSPL2 NAME)
    (SETQ TYPE 'FEF-SPECIAL))
  ;; Cons up the variable descriptor.
  ;; Note that INIT-SPECS is not the final value that will go in the INIT slot.
  (SETQ HOME (MAKE-VAR :NAME NAME :KIND KIND :TYPE TYPE
		       :INIT INIT-SPECS :EVAL EVAL-TYPE :MISC MISC-TYPES
		       :DECLARATIONS (DECLARATIONS-FOR-VARIABLE NAME THIS-FRAME-DECLARATIONS)))
  (IF (AND (EQ TYPE 'FEF-SPECIAL) (GETF (VAR-DECLARATIONS HOME) 'IGNORE))
      (WARN 'NOT-IGNORED :IMPLAUSIBLE
	    "The special variable ~S was declared to be ignored" NAME))
  (SETF (VAR-LAP-ADDRESS HOME)
	;; Not the real lap address,
	;; but something for P1 to use for the value of the variable
	(IF (EQ TYPE 'FEF-SPECIAL) NAME `(LOCAL-REF ,HOME)))
  HOME)

(DEFUN DECLARATIONS-FOR-VARIABLE (NAME THIS-FRAME-DECLARATIONS &AUX RESULT)
  (DOLIST (X THIS-FRAME-DECLARATIONS)
    (CASE (CAR X)
      ((IGNORE)
       (IF (MEMQ NAME (CDR X)) (SETF (GETF RESULT 'IGNORE) T)))
      ((ARRAY ATOM BIGNUM BIT BIT-VECTOR CHARACTER CLI:CHARACTER COMMON COMPILED-FUNCTION
	COMPLEX CONS DOUBLE-FLOAT FIXNUM FLOAT FUNCTION HASH-TABLE INTEGER KEYWORD LIST
	LONG-FLOAT NIL NULL NUMBER PACKAGE PATHNAME RANDOM-STATE RATIO RATIONAL READTABLE
	SEQUENCE SHORT-FLOAT SIMPLE-ARRAY SIMPLE-BIT SIMPLE-STRING SIMPLE-VECTOR SINGLE-FLOAT
	STANDARD-CHAR STREAM STRING STRING-CHAR SYMBOL T VECTOR)
       (IF (MEMQ NAME (CDR X)) (SETF (GETF RESULT 'TYPE) (CAR X))))
      ((TYPE)
       (IF (MEMQ NAME (CDDR X)) (SETF (GETF RESULT 'TYPE) (CADR X))))
;     ((SPECIAL UNSPECIAL			;already processed
;	:SELF-FLAVOR FUNCTION-PARENT FTYPE	;irrelevant
;	FUNCTION INLINE NOTINLINE OPTIMIZE DECLARATION))
      ))
  RESULT)

(DEFUN MAKE-FREE-VAR-HOME (NAME)
  (MAKE-VAR :NAME NAME
	    :KIND 'FEF-ARG-FREE
	    :TYPE 'FEF-SPECIAL
	    :USE-COUNT 0
	    :LAP-ADDRESS NAME))

;;; For a variable whose scope is ready to begin (it's about to be put on VARS),
;;; look for another variable whose scope already ended, to share a slot with.
;;; If we find a suitable one, just clobber it in.
(DEFUN VAR-CONSIDER-OVERLAP (VAR)
  (AND (EQ (VAR-KIND VAR) 'FEF-ARG-INTERNAL-AUX)
       (DO ((VS ALLVARS (CDR VS)))
	   ((NULL VS))
	 ;; Look for other vars with the same name;
	 ;; for a gensym, look for another gensym.
	 (AND (OR (EQ (VAR-NAME VAR) (CAAR VS))
		  (AND (NULL (SYMBOL-PACKAGE (CAAR VS)))
		       (NULL (SYMBOL-PACKAGE (VAR-NAME VAR)))))
	      ;; But don't try to overlap a local with a special that happens to have the same
	      ;; name.
	      (NEQ (VAR-TYPE (CAR VS)) 'FEF-SPECIAL)
	      ;; And don't overlap with arguments
	      ;; (in (LAMBDA (&OPTIONAL (A (LET (B)...)) B) ...) we might otherwise try to do it)
	      (EQ (VAR-KIND (CAR VS)) 'FEF-ARG-INTERNAL-AUX)
	      ;; Insist on a slot that represents a canonical home (does not
	      ;; map to another slot), and that is not currently in use
	      (NOT (OR (VAR-OVERLAP-VAR (CAR VS))
		       (DOLIST (V VARS)
			 (AND (OR (EQ V (CAR VS))
				  (EQ (VAR-OVERLAP-VAR V) (CAR VS)))
			      (RETURN T)))))
	      (PROGN
		(PUSH 'FEF-ARG-OVERLAPPED (VAR-MISC (CAR VS)))
		(RETURN (SETF (VAR-OVERLAP-VAR VAR) (CAR VS))))))))


;;; After the end of pass 1, assign lap addresses to the variables.
;;; Returns the total number of local variable slots allocated.
(DEFUN ASSIGN-LAP-ADDRESSES ()
  (LET ((ARGN 0)   ;Next arg number to allocate.
	(LVCNT 0)) ;Next local block slot number to allocate.
		   ;Count rest arg, auxes, and internal-auxes if they are not special.
    (SETQ ARG-MAP NIL)				;We also build the arg map and local map,
    (SETQ LOCAL-MAP NIL)			;pushing things on in reverse order.
    (DOLIST (V (REVERSE ALLVARS))
      ;; Cons up the expression for Lap to use to refer to this variable.
      (LET ((TYPE (VAR-TYPE V))
            (KIND (VAR-KIND V))
	    (NAME (VAR-NAME V))
	    PERMANENT-NAME)
        (SETF (VAR-LAP-ADDRESS V)
              (COND ((EQ TYPE 'FEF-SPECIAL)
                     `(SPECIAL ,NAME))
                    ((EQ TYPE 'FEF-REMOTE)
                     `(REMOTE ,NAME))
                    ((MEMQ KIND '(FEF-ARG-REQ FEF-ARG-OPT))
                     `(ARG ,ARGN))
		    ((VAR-OVERLAP-VAR V)
		     (VAR-LAP-ADDRESS (VAR-OVERLAP-VAR V)))
                    (T `(LOCBLOCK ,LVCNT))))
	;; If the name is in the temporary area or is uninterned, don't put it in the
	;; arg/local map.  This is partly to avoid putting all these stupid gensyms
	;; into the qfasl file, but the real reason is to avoid the dreaded scourge
	;; of temporary area lossage in the error handler.
	(SETQ PERMANENT-NAME (UNLESS (= (%AREA-NUMBER NAME) QCOMPILE-TEMPORARY-AREA)
			       (WHEN (SYMBOL-PACKAGE NAME)
				 NAME)))
        ;; Now increment one or more of the counters of variables
        ;; and maybe make an entry on LOCAL-MAP or ARG-MAP
        (COND ((MEMQ KIND '(FEF-ARG-REQ FEF-ARG-OPT))
               (PUSH (AND PERMANENT-NAME (LIST PERMANENT-NAME)) ARG-MAP)
               (AND (= (SETQ ARGN (1+ ARGN)) #o101)
		    (WARN 'TOO-MANY-SLOTS :IMPLEMENTATION-LIMIT
			  "More than 64. arguments accepted by one function.")))
              ((OR (EQ TYPE 'FEF-LOCAL)
		   (NOT (MEMQ KIND '(FEF-ARG-INTERNAL FEF-ARG-INTERNAL-AUX))))
	       (COND ((NOT (VAR-OVERLAP-VAR V))
		      (PUSH (AND PERMANENT-NAME (LIST PERMANENT-NAME)) LOCAL-MAP)
		      (AND (= (SETQ LVCNT (1+ LVCNT)) #o101)
			   (WARN 'TOO-MANY-SLOTS :IMPLEMENTATION-LIMIT
				 "More than 64. local variable slots required by one function.")))
		     (T (LET ((L1 (NTHCDR (- (LENGTH LOCAL-MAP)
					     (CADR (VAR-LAP-ADDRESS V))
					     1)
					  LOCAL-MAP)))
			  (OR (NULL PERMANENT-NAME)
			      (MEMQ NAME (CAR L1))
			      (PUSH NAME (CAR L1))))))))))
    (DOLIST (V ALLVARS)				;Fix FIXE's put in by VAR-COMPUTE-INIT
      (AND (EQ (CAR (VAR-INIT V)) 'FEF-INI-EFF-ADR)
	   (EQ (CAADR (VAR-INIT V)) 'FIXE)
	   (SETF (CADADR (VAR-INIT V)) (VAR-LAP-ADDRESS (CADR (CADADR (VAR-INIT V)))))))
    (SETQ LOCAL-MAP (NREVERSE LOCAL-MAP)
          ARG-MAP (NREVERSE ARG-MAP))
    ;; Clobber all nonspecial varnames in elements of
    ;; CLOBBER-NONSPECIAL-VARS-LISTS with NIL.
    ;; Clobber away all-NIL tails of those lists with NIL.
    (DOLIST (L CLOBBER-NONSPECIAL-VARS-LISTS)
      (LET ((LAST-NON-NIL-PTR L))
	(DO ((L1 L (CDR L1)))
	    ((NULL L1))
	  (LET ((HOME (ASSQ (CAR L1) ALLVARS)))
	    (IF (AND HOME (EQ (VAR-TYPE HOME) 'FEF-LOCAL))
		(RPLACA L1 NIL)
		(SETQ LAST-NON-NIL-PTR L1))))
	(IF LAST-NON-NIL-PTR
	    (RPLACD LAST-NON-NIL-PTR NIL))))
    LVCNT))

;;; Given a variable home, compute its VAR-INIT and install it.
;;; When we are called, the VAR-INIT contains the data for us to work on
;;; which looks like (init-form arg-supplied-flag-name).
;;; Note that for a FEF-ARG-INTERNAL-AUX variable, the init-type will
;;; always be FEF-INI-COMP-C.
;;; At time of call, VARS should be bound to the environment for
;;; execution of the init form for this variable.
(DEFUN VAR-COMPUTE-INIT (HOME PARALLEL)
  (LET* ((NAME (VAR-NAME HOME))
	 (KIND (VAR-KIND HOME))
	 (TYPE (VAR-TYPE HOME))
	 (INIT-SPECS (VAR-INIT HOME))
	 (INIT-FORM (CAR INIT-SPECS))
	 (SPECIFIED-FLAG-NAME (CADR INIT-SPECS))
	 INIT-TYPE
	 INIT-DATA
	 (P1VALUE 1))
    (COND ((NULL INIT-FORM))
	  ((EQ (CAR-SAFE INIT-FORM) 'QUOTE))
	  ((AND (CONSTANTP INIT-FORM)
		(OR (NOT (SYMBOLP INIT-FORM))
		    (AND (BOUNDP INIT-FORM) (EQ INIT-FORM (SYMBOL-VALUE INIT-FORM)))))
	   (SETQ INIT-FORM `',INIT-FORM))
	  ((EQUAL INIT-FORM '(UNDEFINED-VALUE))
	   ;;This is simplest thing that works.
	   ;; More hair is not needed for the ways these are usually generated by SETF.
	   (SETQ TLFUNINIT T))
	  (T
	   ;; Init is not NIL, constant or self => must P1 it, and maybe set TLFUNINIT.
	   (LET ((TLEVEL NIL))
	     (SETQ INIT-FORM (P1 INIT-FORM)))
	   (COND ((NOT (ADRREFP INIT-FORM))
		  (SETQ TLFUNINIT T)))))
    ;; Now that we have processed the init form, determine the ADL initialization field.
    ;; First, must we, or would we rather, use code to initialize the variable?
    ;; Note: specified-flags MUST be initted at entry time regardless of anything else.
    (WHEN (AND (NOT (MEMQ 'FEF-ARG-SPECIFIED-FLAG (VAR-MISC HOME)))
	       (OR (EQ KIND 'FEF-ARG-INTERNAL-AUX) TLFUNINIT
		   ;; Don't spoil the fast arg option with nontrivial inits for aux's. 
		   (AND (EQ KIND 'FEF-ARG-AUX)
			FAST-ARGS-POSSIBLE
			(NOT (MEMBER-EQUAL INIT-FORM '(NIL 'NIL))))
		   (IF PARALLEL (NEQ TYPE 'FEF-LOCAL))))
      (SETQ INIT-TYPE 'FEF-INI-COMP-C)
      ;; Note: if we are initting by code, there is no advantage
      ;; in binding at function entry, and doing so would
      ;; make lap stupidly turn off the fast arg option!
      (AND (EQ KIND 'FEF-ARG-AUX)
	   (SETF (VAR-KIND HOME) (SETQ KIND 'FEF-ARG-INTERNAL-AUX)))
      (SETQ TLFUNINIT T))
    ;; If we aren't forced already not to use an init, figure out
    ;; what type of init to use if there's no init-form: either "none" or "nil".
    (UNLESS INIT-TYPE
      (SETQ INIT-TYPE
	    (IF (OR (EQ KIND 'FEF-ARG-OPT)
		    (AND (EQ KIND 'FEF-ARG-AUX)
			 (MEMQ TYPE '(FEF-SPECIAL FEF-REMOTE))))
		'FEF-INI-NIL
		'FEF-INI-NONE)))
    ;; Then, if there is an init form, gobble it.
    (WHEN (AND INIT-FORM (NEQ INIT-TYPE 'FEF-INI-COMP-C))
      (COND ((NOT (MEMQ KIND
			'(FEF-ARG-OPT FEF-ARG-AUX FEF-ARG-INTERNAL-AUX)))
	     (WARN 'BAD-ARGUMENT-LIST :IMPOSSIBLE
		   "The mandatory argument ~S was given a default value."
		   NAME))
	    ;; There's a hack for binding a special var to itself.
	    ((AND (EQ NAME INIT-FORM)
		  (NEQ TYPE 'FEF-LOCAL))
	     (SETQ INIT-TYPE 'FEF-INI-SELF))
	    ((ATOM INIT-FORM)
	     (SETQ INIT-TYPE 'FEF-INI-C-PNTR)
	     (SETQ INIT-DATA (LIST 'LOCATIVE-TO-S-V-CELL INIT-FORM)))
	    ((MEMQ (CAR INIT-FORM) '(LOCAL-REF))
	     (SETQ INIT-TYPE 'FEF-INI-EFF-ADR)	;Initted to value of local var
	     (SETQ INIT-DATA (LIST 'FIXE INIT-FORM)))
	    ((MEMQ (CAR INIT-FORM) '(QUOTE FUNCTION BREAKOFF-FUNCTION SELF-REF))
	     (SETQ INIT-TYPE 'FEF-INI-PNTR)
	     (SETQ INIT-DATA INIT-FORM))
	    (T (BARF INIT-FORM "Init-form calculation confused" 'BARF))))
    (COND ((AND (EQ KIND 'FEF-ARG-OPT)
		(OR TLFUNINIT SPECIFIED-FLAG-NAME))
	   ;; Once an opt arg gets an alternate starting address,
	   ;; all following args must be similar or else FEF-INI-COMP-C.
	   (SETQ TLFUNINIT T)
	   (SETQ INIT-TYPE 'FEF-INI-OPT-SA)
	   (SETQ INIT-DATA (GENSYM)))
	  ;; If something not an optional arg was given a specified-flag,
	  ;; discard that flag now.  There has already been an error message.
	  (T (SETQ SPECIFIED-FLAG-NAME NIL)))
    (SETF (VAR-INIT HOME)
	  (LIST* INIT-TYPE INIT-DATA
		 (AND SPECIFIED-FLAG-NAME
		      (DOLIST (V ALLVARS)
			(AND (EQ (VAR-NAME V) SPECIFIED-FLAG-NAME)
			     (MEMQ 'FEF-ARG-SPECIFIED-FLAG (VAR-MISC V))
			     (RETURN V))))))
    (IF (NULL INIT-FORM)
	NAME
        (LIST NAME INIT-FORM))))

;;; (MULTIPLE-VALUE-BIND variable-list m-v-returning-form . body)
;;; turns into (MULTIPLE-VALUE-BIND variable-list vars-segment m-v-returning-form . body)
;;; where vars-segment is a sublist of VARS that should be pushed onto VARS
;;; while this form is being processed on pass 2.
(DEFUN (:PROPERTY MULTIPLE-VALUE-BIND P1) (FORM)
  (LET ((VARIABLES (CADR FORM))
	(VARS VARS)
	OUTER-VARS
	(LOCAL-DECLARATIONS LOCAL-DECLARATIONS)
	(THIS-FRAME-DECLARATIONS NIL)
	(M-V-FORM (CADDR FORM))
	(BODY (CDDDR FORM)))
    (SETF (VALUES BODY THIS-FRAME-DECLARATIONS)
;>> need to pass environment into extract-declarations here
	  (EXTRACT-DECLARATIONS-RECORD-MACROS BODY NIL NIL))
    (PROCESS-SPECIAL-DECLARATIONS THIS-FRAME-DECLARATIONS)
    (SETQ OUTER-VARS VARS)
    (SETQ TLEVEL NIL)
    ;; P1 the m-v-returning-form outside the bindings we make.
    (SETQ M-V-FORM (P1 M-V-FORM))
    ;; The code should initialize each variable by popping off the stack.
    ;; The values will be in forward order so we must pop in reverse order.
    (SETQ VARIABLES (MAPCAR #'(LAMBDA (V) `(,V (%POP))) VARIABLES))
    (P1SBIND VARIABLES 'FEF-ARG-INTERNAL-AUX T T THIS-FRAME-DECLARATIONS)
    (SETQ LOCAL-DECLARATIONS (NCONC THIS-FRAME-DECLARATIONS LOCAL-DECLARATIONS))
    ;; Return something with the same sort of arguments a LET has when given to pass 2,
    ;; but with the multiple value producing form as an additional argument at the front.
    `(,(CAR FORM) ,M-V-FORM ,VARIABLES ,OUTER-VARS ,VARS
      . ,(CDDDDR (P1V `(LET () . ,BODY))))))

(DEFUN PROCESS-SPECIAL-DECLARATIONS (DECLS)
  (DOLIST (DECL DECLS)
    (IF (EQ (CAR DECL) 'SPECIAL)
	(DOLIST (VARNAME (CDR DECL))
	  (PUSHNEW VARNAME FREEVARS :TEST #'EQ)
	  (PUSH (MAKE-FREE-VAR-HOME VARNAME) VARS)))))

(DEFPROP WITH-STACK-LIST P1-WITH-STACK-LIST P1)
(DEFPROP WITH-STACK-LIST* P1-WITH-STACK-LIST P1)

(DEFUN P1-WITH-STACK-LIST (FORM &AUX MAKER)
  (SETQ MAKER (IF (EQ (CAR FORM) 'WITH-STACK-LIST*)
		  '%MAKE-EXPLICIT-STACK-LIST*
		  '%MAKE-EXPLICIT-STACK-LIST))
  (P1 `(BLOCK-FOR-WITH-STACK-LIST P1-WITH-STACK-LIST
	 (CHANGE-PDLLVL ,(LENGTH (CDADR FORM))
			(%PUSH (,MAKER . ,(CDADR FORM))))
	 (LET ((,(CAADR FORM) (%POP)))
	   . ,(CDDR FORM)))))

(DEFUN (:PROPERTY CHANGE-PDLLVL P1) (FORM)
  `(,(CAR FORM) ,(CADR FORM) . ,(MAPCAR #'P1 (CDDR FORM))))

(DEFPROP %MAKE-EXPLICIT-STACK-LIST P1EVARGS P1)
(DEFPROP %MAKE-EXPLICIT-STACK-LIST* P1EVARGS P1)

;;; Prevent warnings no matter how many args.
(DEFPROP LIST ((#o777777 (FEF-ARG-OPT FEF-QT-EVAL))) ARGDESC)
(DEFPROP LIST* ((#o777777 (FEF-ARG-OPT FEF-QT-EVAL))) ARGDESC)

(DEFPROP LIST P1ASSOC P1)
(DEFPROP NCONC P1ASSOC P1)
(DEFPROP APPEND P1ASSOC P1)
(DEFPROP LIST* P1ASSOC P1)

;; Convert single calls with too many args to multiple calls.
(DEFUN P1ASSOC (FORM)
  (IF (< (LENGTH FORM) 64.)
      (P1EVARGS FORM)
    (P1 `(,(IF (EQ (CAR FORM) 'LIST)
	       'LIST*
	       (CAR FORM))
	   ,@(FIRSTN 61. (CDR FORM))
	   (,(CAR FORM)
	    . ,(NTHCDR 61. (CDR FORM)))))))

(DEFUN UNDEFINED-VALUE () NIL)

;;; Analyze a LET's variable bindings and tags,
;;; and convert it to an internal form which looks like
;;; (LET* <variable list, with keywords processed and removed>
;;;       <value of VARS for body of this prog>
;;;       <T if %BIND used within this prog>
;;;       <*LEXICAL-CLOSURE-COUNT* at start of LET>
;;;       <*LEXICAL-CLOSURE-COUNT* at end of LET>
;;;       . <body, P1'ified>)

;;; LET* does sequential binding, and LET does parallel binding.
;;; P1LAMBDA and P1AUX generate LET or LET* as appropriate.

(DEFUN P1LET (FORM &OPTIONAL FOR-AUXVARS)
  (LET ((VARS VARS)
	OUTER-VARS
	(FN (CAR FORM))
	(BINDP)					;%bind not used
	(BODY)
	(VLIST)
	(LOCAL-DECLARATIONS LOCAL-DECLARATIONS)
	(THIS-FRAME-DECLARATIONS NIL)
	(ENTRY-LEXICAL-CLOSURE-COUNT *LEXICAL-CLOSURE-COUNT*))
    (SETQ VLIST (CADR FORM))
    (SETQ BODY (CDDR FORM))
    (IF (EQ FN 'LET-FOR-AUXVARS) (SETQ FN 'LET*))
    ;; Take all DECLAREs off the body.
    (SETF (VALUES BODY THIS-FRAME-DECLARATIONS)
;>> need to pass environment into extract-declarations here
	  (EXTRACT-DECLARATIONS-RECORD-MACROS BODY NIL NIL))
    (PROCESS-SPECIAL-DECLARATIONS THIS-FRAME-DECLARATIONS)
    (SETQ OUTER-VARS VARS)
    ;; Treat parallel binding as serial if it doesn't matter.
    (WHEN (OR ;; ie if only 1 symbol
	      (NULL (CDR VLIST))	  
	      (AND (EQ FN 'LET)
		   (DOLIST (XX VLIST)
		     ;; or if binding each symbol to NIL, a constant, or itself.
		     (OR (ATOM XX)		;(let (x) ...)
			 (CONSTANTP (CADR XX))	;(let ((x 'foo)) ...)
			 (EQ (CAR XX) (CADR XX));(let ((x x)) ...)
			 (RETURN NIL)))))
      (SETQ FN 'LET*))
    ;; Flush rebinding a var to itself if it isn't special
    ;; and range of rebinding is rest of function.
    (IF TLEVEL
	(SETQ VLIST (SUBSET-NOT #'(LAMBDA (VAR)
				    (AND (CONSP VAR)
					 (EQ (CAR VAR) (CADR VAR))
					 (EQ (FIND-TYPE (CAR VAR) THIS-FRAME-DECLARATIONS)
					     'FEF-LOCAL)
					 (EQ (VAR-TYPE (ASSQ (CAR VAR) VARS)) 'FEF-LOCAL)))
				VLIST)))
    ;; All the local declarations should be in effect for the init forms.
    (SETQ LOCAL-DECLARATIONS (APPEND THIS-FRAME-DECLARATIONS LOCAL-DECLARATIONS))
    ;; &AUX vars should be allowed to inherit special declarations
    ;; since that is what it looks like when you put a DECLARE inside the body.
    (IF FOR-AUXVARS
	(SETQ THIS-FRAME-DECLARATIONS LOCAL-DECLARATIONS))
    (SETQ VLIST (P1SBIND VLIST
			 (IF TLEVEL 'FEF-ARG-AUX 'FEF-ARG-INTERNAL-AUX)
			 (EQ FN 'LET)
			 NIL
			 THIS-FRAME-DECLARATIONS))
    ;; Now convert initial SETQs to variable initializations.
    ;; We win only for SETQs of variables bound but with no initialization spec'd,
    ;; which set them to constant values, and only if later vars' inits didn't use them.
    ;; When we come to anything other than a SETQ we can win for, we stop.
    ;; For LET*, we can't win for a special variable if anyone has called a function
    ;; to do initting, since that function might have referred to the special.
    ;; Even if we don't use tha ADL to init them,
    ;; we avoid redundant settings to NIL.
    (DO ((P1VALUE 1)				;setq only wants one value
	 TEM HOME)
	(())
      (COND ((EQUAL (CAR BODY) '((SETQ)))
	     (POP BODY))
	    ((OR (ATOM (CAR BODY))
		 (ATOM (SETQ TEM (COMPILER-OPTIMIZE (CAR BODY))))
		 (NOT (EQ (CAR TEM) 'SETQ))
		 (NOT (MEMQ (CADR TEM) VLIST))	;we're binding it
		 (NOT (CONSTANTP (CADDR TEM)))	;initializing to constant
		 (AND (SPECIALP (CADR TEM))
		      (OR TLFUNINIT (NOT TLEVEL))
		      (EQ FN 'LET*))
		 (NOT (ZEROP (VAR-USE-COUNT (SETQ HOME (ASSQ (CADR TEM) VARS))))))
	     (RETURN NIL))
	    (T (SETQ BODY (CONS `(SETQ . ,(CDDDR TEM)) (CDR BODY)))
	       (SETF (CAR (MEMQ (CADR TEM) VLIST))
		     `(,(CADR TEM) ,(P1 (CADDR TEM))))
	       ;; For a variable bound at function entry, really set up its init.
	       ;; Other vars (FEF-ARG-INTERNAL-AUX) will be initted by code,
	       ;; despite our optimization, but it will be better code.
	       (AND TLEVEL (EQ (VAR-KIND HOME) 'FEF-ARG-AUX)
		    (SETF (VAR-INIT HOME) `(FEF-INI-PNTR ,(P1 (CADDR TEM))))))))
    ;; Now P1 process what is left of the body.
    (WHEN (CDR BODY) (SETQ TLEVEL NIL))
    (SETQ BODY (P1PROGN-1 BODY))
    `(,FN ,VLIST ,OUTER-VARS ,VARS ,BINDP
      ,ENTRY-LEXICAL-CLOSURE-COUNT ,*LEXICAL-CLOSURE-COUNT*
      . ,BODY)))

;;; MEMQ and ASSQ together.  Find the tail of VLIST
;;; whose CAR or CAAR is VARNAME.
(DEFUN P1LET-VAR-FIND (VARNAME VLIST)
  (DO ((VL VLIST (CDR VL))) ((NULL VL) NIL)
    (AND (OR (EQ VARNAME (CAR VL))
	     (AND (CONSP (CAR VL))
		  (EQ VARNAME (CAAR VL))))
	 (RETURN VL))))

;;; This is what &AUX vars get bound by.
(DEFUN (:PROPERTY LET-FOR-AUXVARS P1) (FORM)
  (P1LET FORM T))

;;; This is supposed to differ from regular LET
;;; by preventing declarations in the body from applying to the variable init forms.
;;; It also must not turn SETQs into init forms, because the declarations
;;; do apply to the SETQs within the body.
(DEFUN (:PROPERTY LET-FOR-LAMBDA P1) (FORM)
  (LET ((VARS VARS)
	OUTER-VARS
	(BINDP)					;%bind not used
	(BODY)
	(VLIST)
	(LOCAL-DECLARATIONS LOCAL-DECLARATIONS)
	(THIS-FRAME-DECLARATIONS NIL)
	(ENTRY-LEXICAL-CLOSURE-COUNT *LEXICAL-CLOSURE-COUNT*))
    ;; Take all DECLAREs off the body.
    (SETF (VALUES BODY THIS-FRAME-DECLARATIONS)
;>> need to pass environment into extract-declarations here
	  (EXTRACT-DECLARATIONS-RECORD-MACROS (CDDR FORM) NIL NIL))
    (SETQ VLIST (P1SBIND (CADR FORM)
			 (IF TLEVEL 'FEF-ARG-AUX 'FEF-ARG-INTERNAL-AUX)
			 T
			 NIL
			 THIS-FRAME-DECLARATIONS))
    (SETQ OUTER-VARS VARS)
    (PROCESS-SPECIAL-DECLARATIONS THIS-FRAME-DECLARATIONS)
    ;; Do this here so that the local declarations
    ;; do not affect the init forms.
    (SETQ LOCAL-DECLARATIONS (NCONC THIS-FRAME-DECLARATIONS LOCAL-DECLARATIONS))
    ;; Now P1 process what is left of the body.
    (AND (CDR BODY) (SETQ TLEVEL NIL))
    (SETQ BODY (P1PROGN-1 BODY))
    `(LET-FOR-LAMBDA ,VLIST ,THIS-FRAME-DECLARATIONS ,OUTER-VARS ,BINDP
      ,ENTRY-LEXICAL-CLOSURE-COUNT ,*LEXICAL-CLOSURE-COUNT*
      . ,BODY)))

;;;; BLOCK and RETURN-FROM.
;;; These know how to turn into catches and throws
;;; when necessary for general lexical scoping.

(DEFPROP BLOCK P1BLOCK P1)
(DEFPROP BLOCK-FOR-WITH-STACK-LIST P1BLOCK P1)
(DEFUN P1BLOCK (FORM &OPTIONAL ALSO-BLOCK-NAMED-NIL)
  (LET* ((PROGNAME (CADR FORM)) (BODY (CDDR FORM))
	 (RETTAG (GENSYM))
	 (*GOTAG-ENVIRONMENT*)
	 (*PROGDESC-ENVIRONMENT* *PROGDESC-ENVIRONMENT*))
    (WHEN (OR (AND ALSO-BLOCK-NAMED-NIL (NEQ PROGNAME 'T))
	      (EQ PROGNAME 'NIL))
      (PUSH (MAKE-PROGDESC :NAME 'NIL
			   :RETTAG RETTAG
			   :NBINDS 0
			   :ENTRY-LEXICAL-CLOSURE-COUNT *LEXICAL-CLOSURE-COUNT*)
	      *PROGDESC-ENVIRONMENT*))
    (PUSH (MAKE-PROGDESC :NAME PROGNAME
			 :RETTAG RETTAG
			 :NBINDS 0
			 ;; :VARS VARS
			 :ENTRY-LEXICAL-CLOSURE-COUNT *LEXICAL-CLOSURE-COUNT*)
	  *PROGDESC-ENVIRONMENT*)
    (AND (CDR BODY) (SETQ TLEVEL NIL))
    (SETQ BODY (P1PROGN-1 BODY))
    ;; Push on *GOTAG-ENVIRONMENT* a description of this prog's "return tag",
    ;; a tag we generate and stick at the end of the prog.
    (PUSH (MAKE-GOTAG RETTAG RETTAG NIL (CAR *PROGDESC-ENVIRONMENT*)) *GOTAG-ENVIRONMENT*)
    (SETF (PROGDESC-EXIT-LEXICAL-CLOSURE-COUNT (CAR *PROGDESC-ENVIRONMENT*))
	  *LEXICAL-CLOSURE-COUNT*)
    (LET ((BLOCK
	    `(,(CAR FORM) ,*GOTAG-ENVIRONMENT* ,(CAR *PROGDESC-ENVIRONMENT*) . ,BODY)))
      (IF (PROGDESC-USED-IN-LEXICAL-CLOSURES-FLAG (CAR *PROGDESC-ENVIRONMENT*))
	  (LET ((VARNAME (GENSYM))
		HOME)
	    ;; For a BLOCK name used from internal lambdas,
	    ;; we make a local variable to hold the catch tag
	    ;; (which is a locative pointer to that variable's own slot).
	    ;; The internal lambda accesses this variable via the lexical scoping mechanism.
	    ;; This ensures the proper lexical scoping when there are
	    ;; multiple activations of the same block.
	    (SETQ HOME (VAR-MAKE-HOME VARNAME 'FEF-LOCAL 'FEF-ARG-INTERNAL-AUX
				      NIL 'FEF-QT-EVAL '(FEF-ARG-USED-IN-LEXICAL-CLOSURES)
				      NIL))
	    (SETF (PROGDESC-USED-IN-LEXICAL-CLOSURES-FLAG (CAR *PROGDESC-ENVIRONMENT*))
		  HOME)
	    (PUSH HOME ALLVARS)
	    (VAR-COMPUTE-INIT HOME NIL)
	    (INCF (VAR-USE-COUNT HOME))
	    `(PROGN
	       (SETQ (LOCAL-REF ,HOME) (VARIABLE-LOCATION (LOCAL-REF ,HOME)))
	       (*CATCH (LOCAL-REF ,HOME) ,BLOCK)))
	BLOCK))))

;;; Defines a block with two names, the specified name and NIL.
(DEFUN (:PROPERTY BLOCK-FOR-PROG P1) (FORM)
  (P1BLOCK FORM T))

(DEFPROP RETURN-FROM P1RETURN-FROM P1)
(DEFUN P1RETURN-FROM (FORM)
  (LET ((PROGDESC (ASSQ (CADR FORM) *PROGDESC-ENVIRONMENT*)))
    (IF (MEMQ PROGDESC *OUTER-CONTEXT-PROGDESC-ENVIRONMENT*)
	`(*THROW ,(TRY-REF-LEXICAL-HOME (PROGDESC-USED-IN-LEXICAL-CLOSURES-FLAG PROGDESC))
		 ,(IF (= (LENGTH (CDDR FORM)) 1)	;return all values of only form
		      (P1 (THIRD FORM))
		    (LET ((P1VALUE 1))		;else return each value of multiple forms
		      `(VALUES . ,(MAPCAR #'P1 (CDDR FORM))))))
      (LET ((P1VALUE 1))
	`(RETURN-FROM ,(CADR FORM) . ,(MAPCAR #'P1 (CDDR FORM)))))))

(DEFPROP RETURN P1RETURN P1)
(DEFUN P1RETURN (FORM)
  (P1RETURN-FROM `(RETURN-FROM NIL . ,(CDR FORM))))

(DEFPROP TAGBODY P1TAGBODY P1)
(DEFUN P1TAGBODY (FORM)
  (LET ((*GOTAG-ENVIRONMENT*)
	(P1VALUE NIL)				;Throw it all away...
	(BODY (CDR FORM))
	(MYPROGDESC (MAKE-PROGDESC :NAME '(TAGBODY) :NBINDS 0)))
    (WHEN (CDR BODY) (SETQ TLEVEL NIL))
    (DOLIST (ELT BODY)
      (WHEN (ATOM ELT)
	(P1TAGAD ELT MYPROGDESC)))
    (SETQ BODY (MAPCAR #'(LAMBDA (STMT) (IF (ATOM STMT) STMT (P1 STMT)))
		       BODY))
    (IF (PROGDESC-USED-IN-LEXICAL-CLOSURES-FLAG MYPROGDESC)
	(LET ((FRAMEWORK
		(P1 `(BLOCK P1TAGBODY
		       (LET (P1TAGBODY P1TAGCATCHTAG)
			 (SETQ P1TAGCATCHTAG (VARIABLE-LOCATION P1TAGCATCHTAG))
			 (TAGBODY
			  P1TAGBODY
			     (SETQ P1TAGBODY
				   (*CATCH P1TAGCATCHTAG
				     (PROGN
				       (CASE P1TAGBODY
					 ((NIL) NIL)
					 . ,(LOOP FOR G IN *GOTAG-ENVIRONMENT*
						  WHEN (GOTAG-USED-IN-LEXICAL-CLOSURES-FLAG G)
						  COLLECT `(,(GOTAG-PROG-TAG G)
							    (GO-HACK ,G))))
				       (RETURN-FROM P1TAGBODY
					 P1TAGBODY-SUBSTITUTE-FOR))))
			     (GO P1TAGBODY))))))
	      TEM)
	  (SETF (PROGDESC-USED-IN-LEXICAL-CLOSURES-FLAG MYPROGDESC)
		(CAR ALLVARS))
	  (PUSHNEW 'FEF-ARG-USED-IN-LEXICAL-CLOSURES
		   (VAR-MISC (CAR ALLVARS)))
	  ;; Get the generated TAGBODY.
	  (SETQ TEM (CAR (LAST (CAR (LAST FRAMEWORK)))))
	  ;; Get the SETQ.
	  (SETQ TEM (CAR (NLEFT 2 TEM)))
	  ;; Get the RETURN-FROM.
	  (SETQ TEM (CAR (LAST (CAR (LAST (CAR (LAST TEM)))))))
	  (SETF (CAR (LAST TEM))
		`(TAGBODY ,*GOTAG-ENVIRONMENT* . ,BODY))
	  FRAMEWORK)
      `(TAGBODY ,*GOTAG-ENVIRONMENT* . ,BODY))))

;;; Make P1 not barf when it finds this, in the code above.
(DEFVAR P1TAGBODY-SUBSTITUTE-FOR)

(DEFUN P1TAGAD (X &OPTIONAL PROGDESC)
  (COND ((ASSQ X *GOTAG-ENVIRONMENT*)
	 (AND X (WARN 'DUPLICATE-PROG-TAG :IMPLAUSIBLE
		      "The PROG tag ~S appears twice in one PROG." X))
	 ;; Replace duplicate progtags with something that
	 ;; will be ignored by pass 2, to avoid making LAP get unhappy.
	 '(QUOTE NIL))
	(T (PUSH X ALLGOTAGS)
	   (PUSH (MAKE-GOTAG X (IF (MEMBER-EQUAL X ALLGOTAGS) (GENSYM) X) NIL PROGDESC)
		 *GOTAG-ENVIRONMENT*)
	   X)))

(DEFPROP GO P1GO P1)
(DEFUN P1GO (FORM)
  (LET ((GOTAG (ASSOC-EQUAL (CADR FORM) *GOTAG-ENVIRONMENT*)))
    (IF (MEMQ GOTAG *OUTER-CONTEXT-GOTAG-ENVIRONMENT*)
	`(*THROW ,(TRY-REF-LEXICAL-HOME
		    (PROGDESC-USED-IN-LEXICAL-CLOSURES-FLAG
		      (GOTAG-PROGDESC GOTAG)))
		 ',(CADR FORM))
      FORM)))

(DEFPROP GO-HACK IDENTITY P1)

;;; PROG is now expanded into the standard primitives.
(DEFUN P1PROG (FORM)
  (LET ((FN (CAR FORM))
	PROGNAME VLIST DECLS BODY)
    (SETQ FORM (CDR FORM))
    ;; Extract the prog name if there is one.
    (WHEN (AND (CAR FORM)
	       (SYMBOLP (CAR FORM)))
      (SETQ PROGNAME (POP FORM)))
    (SETQ VLIST (POP FORM))
    (SETF (VALUES BODY DECLS)
;>> need to pass environment into extract-declarations here
	  (EXTRACT-DECLARATIONS-RECORD-MACROS FORM NIL NIL))
    (P1 `(BLOCK-FOR-PROG ,PROGNAME
			 (,(IF (EQ FN 'PROG) 'LET 'LET*)
			  ,VLIST
			  ,@(IF DECLS `((DECLARE . ,DECLS)))
			  (TAGBODY . ,BODY))))))

;;;; FLET, LABELS, MACROLET

(defun (:property flet p1) (form)
  (let* ((locals (mapcar #'(lambda (ignore) (gensym)) (cadr form))))
    ;; LOCALS are local variables that really hold the functions.
    (mapc #'(lambda (var fndef)
	      (putprop var (car fndef) 'local-function-name))
	  locals (cadr form))
    ;; P1 will translate any reference to a local function
    ;; into a FUNCALL to the corresponding variable.
    (p1 `(let ,(mapcar #'(lambda (var def)
			   `(,var #'(named-lambda . ,def)))
		       locals (cadr form))
	   (flet-internal ,(mapcar #'(lambda (var def)
				       (list (car def) var `(named-lambda . def)))
				   locals (cadr form))
			  . ,(cddr form)))
	t)))					;inhibit optimizations on this pass, since
						; functions with optimizers may be lexically
						; shadowed, and environment isn't set up until
						; flet-internal's p1 handler is executed.
						; We do the optimizations of the body forms in
						; that handler (by way of p1progn-1)

(defun (:property flet-internal p1) (form)
  (let ((*local-functions* *local-functions*)
	(*function-environment* *function-environment*)
	frame)
    (dolist (elt (reverse (cadr form)))
      ;; Each element of *local-functions* looks like:
      ;;  (local-function-name tempvar-name definition)
      (push `(,(car elt) ,(assq (cadr elt) vars) ,(caddr elt)) *local-functions*)
      (setq frame `(,(locf (symbol-function (car elt))) ,(caddr elt) . ,frame)))
    (push frame *function-environment*)
    `(progn . ,(p1progn-1 (cddr form)))))

(defun (:property labels p1) (form)
  (let* ((locals (mapcar #'(lambda (ignore) (gensym)) (cadr form))))
    ;; LOCALS are local variables that really hold the functions.
    (mapc #'(lambda (var fndef)
	      (putprop var (car fndef) 'local-function-name))
	  locals (cadr form))
    ;; P1 will translate any reference to a local function
    ;; into a FUNCALL to the corresponding variable.
    (p1 `(let ,locals
	   (labels-internal ,(mapcar #'(lambda (var def)
					 (list (car def) var `(named-lambda . ,def)))
				     locals (cadr form))
			    ,(mapcan #'(lambda (var def)
					 `(,var #'(named-lambda . ,def)))
				     locals (cadr form))
			    . ,(cddr form)))
	t)))					;see above note about why we do this

(defun (:property labels-internal p1) (form)
  (let ((*local-functions* *local-functions*)
	(*function-environment* *function-environment*)
	frame)
    (dolist (elt (reverse (cadr form)))
      (push `(,(car elt) ,(assq (cadr elt) vars) ,(caddr elt)) *local-functions*)
      (setq frame `(,(locf (symbol-function (car elt))) ,(caddr elt) . ,frame)))
    (push frame *function-environment*)
    `(progn ,(p1 `(psetq . ,(caddr form))) . ,(p1progn-1 (cdddr form)))))

(defun (:property macrolet p1) (exp)
  (let ((*function-environment* *function-environment*)
	;; If we define it as a local macro, that hides any local function definition.
	(*local-functions* (rem-if #'(lambda (elt) (assq (car elt) (cadr exp)))
				   *local-functions*))
	frame)
    (dolist (elt (reverse (cadr exp)))
      (setq frame (list* (locf (symbol-function (car elt)))
			 `(macro . ,(si::expand-defmacro elt *function-environment*))
			 frame)))
    (push frame *function-environment*)
    `(progn . ,(p1progn-1 (cddr exp)))))

;;; Turn an internal lambda containing &AUX variables
;;; into one containing a LET* and having no &AUX variables.
(DEFUN P1AUX (LAMBDA)
  (LET (STANDARDIZED AUXVARS AUXLIST NONAUXLIST DECLS BODY)
    (SETQ STANDARDIZED (SI::LAMBDA-EXP-ARGS-AND-BODY LAMBDA))
    (OR (SETQ AUXLIST (MEMQ '&AUX (CAR STANDARDIZED)))
	(RETURN-FROM P1AUX LAMBDA))
    (SETQ AUXVARS (CDR AUXLIST))
    (SETQ NONAUXLIST (LDIFF (CAR STANDARDIZED) AUXLIST))
    (DO ((VARLIST NONAUXLIST (CDR VARLIST))
	 SPECIAL-FLAG)
	((NULL VARLIST)
	 (IF SPECIAL-FLAG
	     (PUSH '&SPECIAL AUXVARS)))
      (COND ((EQ (CAR VARLIST) '&SPECIAL)
	     (SETQ SPECIAL-FLAG T))
	    ((EQ (CAR VARLIST) '&LOCAL)
	     (SETQ SPECIAL-FLAG NIL))))
    (SETQ BODY (CDR STANDARDIZED))
    ;; Take all DECLAREs off the body and put them on DECLS.
    (SETF (VALUES BODY DECLS)
	  (EXTRACT-DECLARATIONS-RECORD-MACROS BODY NIL *FUNCTION-ENVIRONMENT*))
    `(LAMBDA ,NONAUXLIST
       ,@(IF DECLS `((DECLARE . ,DECLS)))
       (LET* ,AUXVARS
	 ,@(IF DECLS `((DECLARE . ,DECLS)))
	 . ,BODY))))

;;; Turn a call to an internal lambda into a LET, and return P1 of that LET.
;;; All &AUX variables in the lambda list are extracted by P1AUX.
;;; We generate a LET, since the lambda variables should all be computed and then bound.
;;; This means that &OPTIONALs don't work quite right;
;;; but they never used to work at all in internal lambdas anyway.
;;; No checking of number of args here, because it is done elsewhere.
;;; We just eval and ignore extra args and take missing ones to be NIL.
(DEFUN P1LAMBDA (LAMBDA ARGS)
  (LET (ARGLIST BODY ARGS1 OPTIONAL PROGVARS VAR QUOTEFLAG
	SPECIAL-FLAG SPECIAL-VARS UNSPECIAL-FLAG UNSPECIAL-VARS
	DECLS KEYCHECKS BORDER-VARIABLE PSEUDO-KEYNAMES)
    (SETQ LAMBDA (SI::LAMBDA-EXP-ARGS-AND-BODY (P1AUX LAMBDA)))
    (SETQ ARGLIST (CAR LAMBDA) BODY (CDR LAMBDA))
    (MULTIPLE-VALUE-BIND (NIL NIL NIL
			  REST-ARG NIL KEYKEYS KEYNAMES KEYINITS KEYFLAGS ALLOW-OTHER-KEYS)
	(DECODE-KEYWORD-ARGLIST ARGLIST)
      (WHEN (AND KEYNAMES (NOT REST-ARG))
	(SETQ REST-ARG (GENSYM)))
      (SETQ ARGS1 ARGS)
      (DO ((ARGLIST1 ARGLIST (CDR ARGLIST1)))
	  (NIL)
	(SETQ VAR (CAR ARGLIST1))
	(COND ((NULL ARGLIST1)
	       (RETURN T))
	      ((EQ VAR '&KEY)
	       (PUSH (LIST REST-ARG `(LIST . ,ARGS1)) PROGVARS)
	       (RETURN (SETQ ARGS1 NIL)))
	      ((EQ VAR '&REST)
	       (POP ARGLIST1)
	       (PUSH (LIST (CAR ARGLIST1) `(LIST . ,ARGS1)) PROGVARS)
	       (RETURN (SETQ ARGS1 NIL)))
	      ((EQ VAR '&OPTIONAL)
	       (SETQ OPTIONAL T))
	      ((EQ VAR '&QUOTE)
	       (SETQ QUOTEFLAG T))
	      ((EQ VAR '&EVAL)
	       (SETQ QUOTEFLAG NIL))
	      ((EQ VAR '&SPECIAL)
	       (SETQ SPECIAL-FLAG T UNSPECIAL-FLAG NIL))
	      ((EQ VAR '&LOCAL)
	       (SETQ SPECIAL-FLAG NIL UNSPECIAL-FLAG T))
	      ((EQ VAR '&FUNCTIONAL))
	      ((MEMQ VAR LAMBDA-LIST-KEYWORDS)
	       (WARN 'BAD-INTERNAL-LAMBDA-KEYWORD :IMPOSSIBLE
		     "~S is not supported in internal lambdas." VAR))
	      (T (AND SPECIAL-FLAG (PUSH VAR SPECIAL-VARS))
		 (AND UNSPECIAL-FLAG (PUSH VAR UNSPECIAL-VARS))
		 (COND ((SYMBOLP VAR)
			(PUSH (LIST VAR (IF QUOTEFLAG `',(CAR ARGS1)
					  (CAR ARGS1)))
			      PROGVARS))
		       (T
			(UNLESS (NOT OPTIONAL)
			  (WARN 'BAD-ARGUMENT-LIST :IMPOSSIBLE
				"The mandatory argument ~S of an internal lambda was given a default value."
				(CAR VAR)))
			(PUSH (LIST (CAR VAR)
				    (IF ARGS1 (IF QUOTEFLAG `',(CAR ARGS1) (CAR ARGS1))
				      (CADR VAR)))
			      PROGVARS)))
		 (POP ARGS1))))
      (WHEN KEYNAMES
	(SETQ PSEUDO-KEYNAMES (COPY-LIST KEYNAMES))
	;; For each keyword arg, decide whether we need to init it to KEYWORD-GARBAGE
	;; and check explicitly whether that has been overridden.
	;; If the initial value is a constant, we can really init it to that.
	;; Otherwise we create a dummy variable initialized to KEYWORD-GARBAGE;
	;; after all keywords are decoded, we bind the intended variable, in sequence.
	;; However a var that can shadow something (including any special var)
	;; must always be replaced with a dummy.
	(DO ((KIS KEYINITS (CDR KIS))
	     (KNS KEYNAMES (CDR KNS))
	     (PKNS PSEUDO-KEYNAMES (CDR PKNS))
	     (KFS KEYFLAGS (CDR KFS)))
	    ((NULL KNS))
	  (LET ((KEYNAME (CAR KNS)) PSEUDO-KEYNAME
		(KEYFLAG (CAR KFS)) (KEYINIT (CAR KIS)))
	    (OR (AND (NULL KEYFLAG)
		     (CONSTANTP KEYINIT)
		     (NOT (ASSQ KEYNAME VARS))
		     (NOT (LEXICAL-VAR-P KEYNAME))
		     (NOT (SPECIALP KEYNAME)))
		(PROGN (SETF (CAR KIS) 'SI::KEYWORD-GARBAGE)
		       (SETQ PSEUDO-KEYNAME (GENSYM))
		       (SETF (CAR PKNS) PSEUDO-KEYNAME)
		       (PUSH `(,KEYNAME
			       (COND ((EQ ,PSEUDO-KEYNAME SI::KEYWORD-GARBAGE)
				      ,KEYINIT)
				     (T ,(AND KEYFLAG `(SETQ ,KEYFLAG T))
					,PSEUDO-KEYNAME)))
			     KEYCHECKS)))))
	(SETQ KEYFLAGS (REMQ NIL KEYFLAGS))
	(SETQ KEYCHECKS (NREVERSE KEYCHECKS))

	;; BORDER-VARIABLE is a local we put in the binding list
	;; as the easiest way of being able to get a locative to the
	;; slot before the first of our keyword arg locals.
	(SETQ BORDER-VARIABLE (GENSYM))
	(SETQ BODY
	      `((LET* (,BORDER-VARIABLE
		       ,@(MAPCAR #'(LAMBDA (V INIT) `(,V ,INIT)) PSEUDO-KEYNAMES KEYINITS)
		       ,@KEYFLAGS)
		  ,BORDER-VARIABLE
		  (WHEN ,REST-ARG
		    (SI::STORE-KEYWORD-ARG-VALUES-INTERNAL-LAMBDA
		      (VARIABLE-LOCATION ,BORDER-VARIABLE)
		      ,REST-ARG ',KEYKEYS
		      ,ALLOW-OTHER-KEYS
		      NIL))
		  (LET* ,KEYCHECKS
		    . ,BODY)))))
      ;; Take all DECLAREs off the body and put them on DECLS.
      (SETF (VALUES BODY DECLS)
;>> need to pass environment into extract-declarations here
	    (EXTRACT-DECLARATIONS-RECORD-MACROS BODY NIL NIL))
      (WHEN SPECIAL-VARS
	(PUSH `(SPECIAL . ,SPECIAL-VARS) DECLS))
      (WHEN UNSPECIAL-VARS
	(PUSH `(UNSPECIAL . ,UNSPECIAL-VARS) DECLS))
      (WHEN DECLS
	(PUSH `(DECLARE . ,DECLS) BODY))
      (P1 `(LET-FOR-LAMBDA ,(NRECONC PROGVARS (IF ARGS1 `((IGNORE (PROGN . ,ARGS1)))))
	     . ,BODY)))))

(DEFPROP *THROW P1EVARGS P1)

(DEFUN (:PROPERTY COND P1) (X)
  (COND ((NULL (CDR X))
	 ''NIL)
	((ATOM (CDR X))
	 (WARN 'BAD-COND :IMPOSSIBLE
	       "The atom ~S appears as the body of a ~S." (CDR X) 'COND)
	 ''NIL)
	(T `(COND . ,(MAPCAR #'(LAMBDA (CLAUSE)
				 (COND ((ATOM CLAUSE)
					(WARN 'BAD-COND :IMPOSSIBLE
					      "The atom ~S appears as a ~S-clause."
					      CLAUSE 'COND)
					NIL)
				       (T (P1COND-CLAUSE CLAUSE))))
			     (CDR X))))))

(DEFUN (:PROPERTY IF P1) (FORM)
  `(COND ,(P1COND-CLAUSE `(,(CADR FORM) ,(CADDR FORM)))
	 ,(P1COND-CLAUSE `(T NIL . ,(CDDDR FORM)))))

(DEFUN P1COND-CLAUSE (CLAUSE)
  (IF (CDR CLAUSE)
      `(,(P1V (CAR CLAUSE) 'PREDICATE) . ,(P1PROGN-1 (CDR CLAUSE)))
      `(,(P1 (CAR CLAUSE)))))

(DEFPROP PROGN P1PROGN P1)
(DEFUN P1PROGN (FORM)
  (SETQ TLEVEL NIL)
  (MULTIPLE-VALUE-BIND (BODY THIS-FRAME-DECLARATIONS)
;>> need to pass environment in to extract-declarations here
      (EXTRACT-DECLARATIONS-RECORD-MACROS (CDR FORM) NIL NIL)
    (LET ((VARS VARS)
	  (LOCAL-DECLARATIONS LOCAL-DECLARATIONS))
      (PROCESS-SPECIAL-DECLARATIONS THIS-FRAME-DECLARATIONS)
      (SETQ LOCAL-DECLARATIONS (NCONC THIS-FRAME-DECLARATIONS LOCAL-DECLARATIONS))
      `(PROGN-WITH-DECLARATIONS ,VARS . ,(P1PROGN-1 BODY)))))

(DEFUN P1PROGN-1 (FORMS)
  (SETQ FORMS (COPY-LIST FORMS))
  (DO ((FORMS-LEFT FORMS (CDR FORMS-LEFT)))
      ((NULL FORMS-LEFT) FORMS)
    (SETF (CAR FORMS-LEFT)
	  (IF (CDR FORMS-LEFT)
	      (P1V (CAR FORMS-LEFT) NIL)
	      (P1 (CAR FORMS-LEFT))))))

(DEFUN (:PROPERTY IGNORE P1) (FORM &AUX (P1VALUE NIL))
  `(PROGN . ,(MAPCAR #'P1 (APPEND (CDR FORM) '(NIL)))))

(DEFUN (:PROPERTY THE P1) (FORM)
  `(PROGN . ,(P1PROGN-1 (CADDR FORM))))

(DEFUN (:PROPERTY VALUES P1) (FORM &AUX (P1VALUE 1))
  `(VALUES . ,(MAPCAR #'P1 (CDR FORM))))

(DEFPROP MULTIPLE-VALUE P1-MULTIPLE-VALUE P1)
(DEFUN P1-MULTIPLE-VALUE (FORM)
  (WHEN (CDDDR FORM)
    (WARN 'WRONG-NUMBER-OF-ARGUMENTS :IMPOSSIBLE
	  "MULTIPLE-VALUE(-SETQ) is used with too many arguments."))
  (IF (NULL (CDR (CADR FORM)))			;(multiple-value-setq (foo) (bar))
      (IF (EQ (CAR (CADR FORM)) 'NIL)		;(multiple-value-setq (nil) (bar))
	  (P1V (CADDR FORM) NIL)
	(P1V `(SETQ ,(CAR (CADR FORM)) ,(CADDR FORM)) 1))
    `(MULTIPLE-VALUE ,(MAPCAR #'P1SETVAR (CADR FORM))
       ,(P1V (CADDR FORM) (LENGTH (CADR FORM))))))

(DEFUN (:PROPERTY NTH-VALUE P1) (FORM)
  (WHEN (CDDDR FORM)
    (WARN 'WRONG-NUMBER-OF-ARGUMENTS :IMPOSSIBLE
	  "~S is used with too many arguments." (CAR FORM)))
  (IF (TYPEP (CADR FORM) '(INTEGER 0 63.))
      `(NTH-VALUE ,(CADR FORM) ,(P1V (CADDR FORM) (1+ (CADR FORM))))
      `(NTH-VALUE ,(CADR FORM) ,(P1V (CADDR FORM) T))))

(DEFPROP MULTIPLE-VALUE-LIST ((1 (FEF-ARG-REQ FEF-QT-EVAL))) ARGDESC)

;;; In pass 1, pretend this isn't a special form
(DEFUN (:PROPERTY MULTIPLE-VALUE-PUSH P1) (FORM)
  (AND (CDDDR FORM)
       (WARN 'WRONG-NUMBER-OF-ARGUMENTS :IMPOSSIBLE
	     "MULTIPLE-VALUE-PUSH is used with too many arguments."))
  (COND ((ZEROP (CADR FORM))
	 ;; NO, it is not correct to throw away a form just because
	 ;; zero of its values are wanted!!!!
	 (P1 (CADDR FORM)))
	((TYPEP (CADR FORM) '(INTEGER 1 63.))
	 `(MULTIPLE-VALUE-PUSH ,(CADR FORM) ,(P1V (CADDR FORM) (CADR FORM))))
	(T
	 (WARN 'TOO-MANY-VALUES :IMPOSSIBLE
	       "The first argument of MULTIPLE-VALUE-PUSH must be a fixnum between 0 and 63.")
	 (P1V (CADDR FORM)))))

(DEFUN (:PROPERTY PROG1 P1) (FORM)
  `(,(CAR FORM) . ,(LOOP FOR ELT IN (CDR FORM)
			 FOR P1VALUE = (IF P1VALUE 1) THEN NIL
			 COLLECT (P1 ELT))))

(DEFPROP MULTIPLE-VALUE-PROG1 P1-MV-PROG1 P1)
(DEFPROP UNWIND-PROTECT P1-MV-PROG1 P1)
(DEFUN P1-MV-PROG1 (FORM)
  `(,(CAR FORM) . ,(LOOP FOR ELT IN (CDR FORM)
			 FOR P1VALUE = P1VALUE THEN NIL
			 COLLECT (P1 ELT))))

(DEFUN (:PROPERTY SETQ P1) (FORM)
  (LET ((DO-THE-SETS
	  `(SETQ . ,(P1SETQ-1 (CDR FORM)))))
    (IF P1VALUE
	;; If the last pair is of the form X X and was ignored,
	;; but we need X as the value of the SETQ form,
	;; put (PROGN ... X) around the actual variable setting.
	(DO ((TAIL (CDR FORM) (CDDR TAIL)))
	    ((NULL TAIL)
	     DO-THE-SETS)
	  (AND (CDR TAIL) (NULL (CDDR TAIL))
	       (EQ (CAR TAIL) (CADR TAIL))
	       (RETURN `(PROGN ,DO-THE-SETS ,(P1V (CAR TAIL) 1)))))
      DO-THE-SETS)))

(DEFUN P1SETQ-1 (PAIRS)
  (COND ((NULL PAIRS) NIL)
	((NULL (CDR PAIRS))
	 (WARN 'BAD-SETQ :IMPOSSIBLE
	       "SETQ appears with an odd number of arguments; the last one is ~S."
	       (CAR (LAST PAIRS)))
	 NIL)
	((MEMQ (CAR PAIRS) '(T NIL))
	 (WARN 'NIL-OR-T-SET :IMPOSSIBLE
	       "~S being SETQ'd; this will be ignored." (CAR PAIRS))
	 (P1V (CADR PAIRS) 1)			;Just to get warnings on it.
	 (P1SETQ-1 (CDDR PAIRS)))
	((GET (CAR PAIRS) 'SYSTEM-CONSTANT)
	 (WARN 'SYSTEM-CONSTANT-SET :IMPOSSIBLE
	       "Defined constant ~S being SETQ'd; this will be ignored." (CAR PAIRS))
	 (P1V (CADR PAIRS) 1)
	 (P1SETQ-1 (CDDR PAIRS)))
	((EQ (CAR PAIRS) (CADR PAIRS))
	 ;; Generate no code for (SETQ X X) unless returned value.
	 (P1SETVAR (CAR PAIRS))
	 (P1SETQ-1 (CDDR PAIRS)))
	(T
	 (CONS (P1SETVAR (CAR PAIRS))
	       (CONS (P1V (CADR PAIRS) 1) (P1SETQ-1 (CDDR PAIRS)))))))

(DEFUN P1SETVAR (VAR)
  (COND ((NULL VAR) NIL)			;For multiple-value
	((NOT (SYMBOLP VAR))
	 (WARN 'BAD-SETQ :IMPOSSIBLE
	       "~S cannot be SETQ'd." VAR)
	 NIL)
	(T (P1 VAR))))

;;; Given an entry on VARS, increment the usage count.
(DEFSUBST VAR-INCREMENT-USE-COUNT (VAR)
  (INCF (VAR-USE-COUNT VAR)))

;;; COMPILER-LET must be renamed to COMPILER-LET-INTERNAL
;;; by an "optimizer" so that its normal definition as a macro is bypassed.
(DEFOPTIMIZER COMPILER-LET-INTERNALIZE COMPILER-LET () (FORM)
  `(COMPILER-LET-INTERNAL . ,(CDR FORM)))

;;; (compiler-let ((var form) (var form) ...) body...)
(DEFUN (:PROPERTY COMPILER-LET-INTERNAL P1) (FORM)
  (PROGV (MAPCAR #'(LAMBDA (X) (IF (ATOM X) X (CAR X))) (CADR FORM))
	 (MAPCAR #'(LAMBDA (X) (IF (ATOM X) NIL (EVAL (CADR X)))) (CADR FORM))
    (P1 (IF (CDDDR FORM) `(PROGN . ,(CDDR FORM)) (CADDR FORM)))))

;;; DONT-OPTIMIZE is like PROGN, except that the arguments are not optimized.
;;; Actually, only the top level of the arguments are not optimized;
;;; their subexpressions are handled normally.
(DEFUN (:PROPERTY DONT-OPTIMIZE P1) (FORM &REST (FORMS (CDR FORM)))
  (DO ((FORMS-LEFT (SETQ FORMS (COPY-LIST FORMS)) (CDR FORMS-LEFT)))
      ((NULL FORMS-LEFT) `(PROGN . ,FORMS))
    (SETF (CAR FORMS-LEFT)
	  (P1V (CAR FORMS-LEFT) (IF (CDR FORMS) NIL P1VALUE) T))))

(DEFUN (:PROPERTY INHIBIT-STYLE-WARNINGS P1) (FORM &REST (FORMS (CDR FORM)))
  (DO ((FORMS-LEFT (SETQ FORMS (COPY-LIST FORMS)) (CDR FORMS-LEFT))
       (*CHECK-STYLE-P* NIL))
      ((NULL FORMS-LEFT) `(PROGN . ,FORMS))
    (SETF (CAR FORMS-LEFT)
	  (P1V (CAR FORMS-LEFT) (IF (CDR FORMS) NIL P1VALUE)))))

;;; Execute body with SELF's mapping table set up.
(DEFUN (:PROPERTY WITH-SELF-ACCESSIBLE P1) (FORM)
  (P1 `(LET ((SELF-MAPPING-TABLE (%GET-SELF-MAPPING-TABLE ',(CADR FORM))))
	 . ,(CDDR FORM))))

;;; Execute body with all instance variables of SELF bound as specials.
(DEFUN (:PROPERTY WITH-SELF-VARIABLES-BOUND P1) (FORM)
  (P1 `(LET ()
	 (%USING-BINDING-INSTANCES (SI::SELF-BINDING-INSTANCES))
	 . ,(CDR FORM))))

;;; The flavor system sometimes generates SELF-REFs by hand.
;;; Just let them through on pass 1.  Pass 2 will compile like refs to instance vars.
(DEFUN (:PROPERTY SELF-REF P1) (FORM)
  FORM)

(DEFUN (:PROPERTY LEXPR-FUNCALL-WITH-MAPPING-TABLE P1) (FORM)
  (P1 `(LET ((SELF-MAPPING-TABLE SELF-MAPPING-TABLE))
	 (LEXPR-FUNCALL-WITH-MAPPING-TABLE-INTERNAL . ,(CDR FORM)))))

(DEFUN (:PROPERTY FUNCALL-WITH-MAPPING-TABLE P1) (FORM)
  (P1 `(LET ((SELF-MAPPING-TABLE SELF-MAPPING-TABLE))
	 (FUNCALL-WITH-MAPPING-TABLE-INTERNAL . ,(CDR FORM)))))

;;; Make sure combined methods get marked as being methods.
(DEFUN (:PROPERTY LEXPR-FUNCALL-WITH-MAPPING-TABLE-INTERNAL P1) (FORM)
  (SETQ SELF-REFERENCES-PRESENT T)
  (P1EVARGS FORM))

(DEFUN (:PROPERTY FUNCALL-WITH-MAPPING-TABLE-INTERNAL P1) (FORM)
  (SETQ SELF-REFERENCES-PRESENT T)
  (P1EVARGS FORM))

(DEFUN (:PROPERTY QUOTE-EVAL-AT-LOAD-TIME P1) (FORM)
  (P1 (IF (EQ QC-TF-OUTPUT-MODE 'COMPILE-TO-CORE)
	  `(QUOTE ,(EVAL (CADR FORM)))
	`(QUOTE (,EVAL-AT-LOAD-TIME-MARKER . ,(CADR FORM))))))

;;; In the interpreter, this simply evals its arg.
(DEFUN QUOTE-EVAL-AT-LOAD-TIME (FORM) FORM)

(DEFPROP FUNCTION P1FUNCTION P1)
(DEFUN P1FUNCTION (FORM)
  (COND ((SYMBOLP (CADR FORM))
	 (LET ((TM (ASSQ (CADR FORM) *LOCAL-FUNCTIONS*)))
	   (IF TM				;Ref to a local fn made by FLET or LABELS:
	       (TRY-REF-LEXICAL-HOME (CADR TM))	;Really ref the local var that holds it.
	     FORM)))				;Global function definition.
	((FUNCTIONP (CADR FORM) T)		;Functional constant
	 (OR (MAYBE-BREAKOFF (CADR FORM)) (LIST 'QUOTE (CADR FORM))))
	((VALIDATE-FUNCTION-SPEC (CADR FORM))	;Function spec
	 FORM)
	(T (WARN 'BAD-ARGUMENT :IMPOSSIBLE
		 "The argument of FUNCTION is ~S, neither a function nor the name of one."
		 (CADR FORM))
	   ''NIL)))

;;; By special dispensation, VALUE-CELL-LOCATION of a quoted symbol
;;; gets the location of any sort of variable; but this is semi-obsolete.
(DEFUN (:PROPERTY VALUE-CELL-LOCATION P1) (FORM)
  (IF (EQ (CAR-SAFE (CADR FORM)) 'QUOTE)
      (LET ((VAR (CADADR FORM)) TEM)
	(COND ((NOT (SYMBOLP VAR))
	       (WARN 'VARIABLE-NOT-SYMBOL :IMPOSSIBLE
		     "The argument of VALUE-CELL-LOCATION is '~S." VAR)
	       ''NIL)
	      ((MEMQ VAR '(T NIL))
	       `(VALUE-CELL-LOCATION ',VAR))
	      (T
	       (SETQ TEM (P1V VAR 1))
	       (COND ((SYMBOLP TEM)
		      `(VALUE-CELL-LOCATION ',TEM))
		     (T `(VARIABLE-LOCATION ,TEM))))))
    (P1EVARGS FORM)))

(DEFUN (:PROPERTY VARIABLE-LOCATION P1) (FORM &AUX TEM)
  (COND ((NOT (SYMBOLP (CADR FORM)))
	 (WARN 'VARIABLE-NOT-SYMBOL :IMPOSSIBLE
	       "The argument of VARIABLE-LOCATION is ~S, which is not a symbol." (CADR FORM))
	 ''NIL)
	(T
	 (SETQ TEM (P1V (CADR FORM) 1))
	 (COND ((SYMBOLP TEM)
		`(%EXTERNAL-VALUE-CELL ',TEM))
	       (T `(VARIABLE-LOCATION ,TEM))))))

;;; this is for expand-keyed-lambda.
;;; Like variable-location, but doesn't increment var-use-count, so that
;;; (lambda (&key x y)) gets a bound-but-not-used warning for x as well as for y
(DEFUN (:PROPERTY KLUDGEY-COMPILATION-VARIABLE-LOCATION P1) (FORM &AUX TEM TEM1)
  (SETQ FORM (CADR FORM))
  (SETQ TEM (COND ((SETQ TEM1 (ASSQ FORM VARS))
		   (AND (EQ (VAR-KIND TEM1) 'FEF-ARG-FREE)
			(ZEROP (VAR-USE-COUNT TEM1))
			(PUSH (VAR-NAME TEM1) FREEVARS))
		   (VAR-LAP-ADDRESS TEM1))
		  ((SPECIALP FORM) FORM)
		  (T (BARF form "Lossage in keyed-lambda compilation" 'BARF))))
  (IF (SYMBOLP TEM)
      `(%EXTERNAL-VALUE-CELL ',TEM)
    `(VARIABLE-LOCATION ,TEM)))

(DEFUN (VARIABLE-MAKUNBOUND P1) (FORM &AUX TEM)
  (IF (COND ((NOT (SYMBOLP (CADR FORM)))
	     (WARN 'VARIABLE-NOT-SYMBOL :IMPOSSIBLE
		   "The argument of VARIABLE-MAKUNBOUND is ~S, which is not a symbol."
		   (CADR FORM))
	     NIL)
	    (T (SETQ TEM (P1V (CADR FORM) 1))
	       (COND ((SYMBOLP TEM))
		     ((EQ (CAR TEM) 'SELF-REF))
		     ((EQ (CAR TEM) 'LOCAL-REF)
		      (WARN 'VARIABLE-LOCAL :IMPOSSIBLE
			    "VARIABLE-MAKUNBOUND is not allowed on local variables such as ~S"
			    (CADR FORM))
		      NIL)
		     ((EQ (CAR TEM) 'LEXICAL-REF)
		      (WARN 'VARIABLE-LOCAL :IMPOSSIBLE
			    "VARIABLE-MAKUNBOUND is not allowed on lexical variables such as ~S"
			    (CADR FORM))
		      NIL))))
      (P1V `(LOCATION-MAKUNBOUND (VARIABLE-LOCATION ,(CADR FORM))) 1)
    ''NIL))

(DEFUN (:PROPERTY VARIABLE-BOUNDP P1) (FORM &AUX TEM)
  (COND ((NOT (SYMBOLP (CADR FORM)))
	 (WARN 'VARIABLE-NOT-SYMBOL :IMPOSSIBLE
	       "The argument of VARIABLE-BOUNDP is ~S, which is not a symbol." (CADR FORM))
	 ''NIL)
	(T (SETQ TEM (P1V (CADR FORM) 1))
	   (COND ((SYMBOLP TEM)
		  `(BOUNDP ',TEM))
		 ((EQ (CAR TEM) 'LOCAL-REF) ''T)
		 ((EQ (CAR TEM) 'SELF-REF)
		  (P1V `(NOT (= DTP-NULL (%P-DATA-TYPE (VARIABLE-LOCATION ,(CADR FORM)))))
		       'PREDICATE))
		 ((EQ (CAR TEM) 'LEXICAL-REF) ''T)))))

;;; BOUNDP of an instance variable of SELF does special things.
(DEFUN (:PROPERTY BOUNDP P1) (FORM)
  (COND ((EQ (CAR-SAFE (CADR FORM)) 'QUOTE)
	 (P1V `(VARIABLE-BOUNDP ,(CADADR FORM)) 'PREDICATE))
	(T (P1EVARGS FORM))))

(DEFPROP OR P1ANDOR P1)
(DEFPROP AND P1ANDOR P1)
(DEFUN P1ANDOR (FORM)
  `(,(CAR FORM) . ,(DO ((X (CDR FORM) (CDR X))
			RESULT)
		       ((NULL (CDR X))
			(PUSH (P1 (CAR X)) RESULT)
			(NREVERSE RESULT))
		     (PUSH (P1V (CAR X) 1) RESULT))))

(DEFUN P1EVARGS (FORM)
  "One value from each elt of (CDR FORM), including the last."
  (LET ((P1VALUE 1))
    `(,(CAR FORM) . ,(MAPCAR #'P1 (CDR FORM)))))

;;; Any use of BIND must set SPECIALFLAG.
(DEFPROP %BIND P1BIND P1)
(DEFPROP %USING-BINDING-INSTANCES P1BIND P1)
(DEFUN P1BIND (FORM)
  (SETQ SPECIALFLAG T)
  (SETQ BINDP T)
  (P1EVARGS FORM))
(MAKE-OBSOLETE BIND "use SYS:%BIND")

;; It turns out that there is no need to preserve the cdr-codes
;; when this is used in compiled code.
;; (It is used only in expansions of LET-GLOBALLY).
(DEFUN (:PROPERTY SI:COPY-VALUE P1) (FORM)
  (LET ((TO-CELL (CADR FORM))
	(FROM-CELL (CADDR FORM)))
    (P1 `(%BLT-TYPED ,FROM-CELL ,TO-CELL 1 0))))

;;; For (CLOSURE '(X Y Z) ...), make sure that X, Y, Z are special.
(DEFUN (:PROPERTY P1CLOSURE P1) (FORM)
  (AND (EQ (CAR-SAFE (CADR FORM)) 'QUOTE)
       (MAPC #'MSPL2 (CADADR FORM)))
  (P1EVARGS FORM))

;(DEFUN (:PROPERTY EVENP P1) (FORM)
;  (P1 `(NOT (BIT-TEST 1 ,(CADR FORM)))))

;(DEFUN (:PROPERTY ODDP P1) (FORM)
;  (P1 `(BIT-TEST 1 ,(CADR FORM))))

;;; ARGDESC properties for functions with hairy eval/quote argument patterns
(DEFPROP ARRAY ((2 (FEF-ARG-REQ FEF-QT-QT)) (#o20 (FEF-ARG-OPT FEF-QT-EVAL))) ARGDESC)

