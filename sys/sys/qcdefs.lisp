;;; -*- Mode:LISP; Package:COMPILER; Lowercase:T; Base:8; Readtable:T -*-
;;; Definitions and specials for the Lisp machine Lisp compiler
;	** (c) Copyright 1980 Massachusetts Institute of Technology **

;;     "This is insane.  What we clearly want to do is not completely
;;      clear, and is rooted in NCOMPLR."   -- BSG/Dissociated Press.

(DEFVAR QCOMPILE-TEMPORARY-AREA NIL
  "Area for compilation itself (within QC-TRANSLATE-FUNCTION) to cons in.")

(DEFVAR GENERATING-MICRO-COMPILER-INPUT-P NIL
  "This is T if the compiler is generating macro-code to pass to the micro compiler.
In that case, the code is generated a little differently
so as to lead to more optimal microcode.
/(Actually, it can fail to be valid macrocode, in little ways).")

(DEFVAR FUNCTION-BEING-PROCESSED :UNBOUND
  "Function the compiler was called on.  Bound only inside the closure used in EH:ERROR-MESSAGE-HOOK.")

(DEFVAR FUNCTION-TO-BE-DEFINED NIL
  "Function spec to be defined as the result of the current compilation.")

(DEFVAR NAME-TO-GIVE-FUNCTION NIL
  "This is the function spec to put in the name of the fef produced by the compilation.
Usually this is the same as FUNCTION-TO-BE-DEFINED.")

(DEFCONST COMPILER-VERBOSE NIL
  "T means print name of each function when its compilation begins.")

;;; Holds the arglist for the function being compiled, and the name that goes with it,
;;; to avoid mistaken warnings about wrong number of args in recursive function call.
(DEFVAR THIS-FUNCTION-ARGLIST nil
  "Arglist of the function being compiled.  Used for warnings on recursive calls.")
(DEFVAR THIS-FUNCTION-ARGLIST-FUNCTION-NAME NIL
  "Name of function that THIS-FUNCTION-ARGLIST is the arglist for.")

(DEFCONST HOLDPROG T
  "If NIL, the lap instructions are typed out on the terminal
instead of being saved up for lap.")

(DEFVAR SPECIALFLAG :UNBOUND
  "T means the function has bound a special variable.
This information goes into the FEF.")

;;; LOCAL-DECLARATIONS (on SYSTEM) is a list of local declarations.
;;; Each local declaration is a list starting with an atom which says
;;; what type of declaration it is.  The meaning of the rest of the
;;; list depends on the type of declaration.
;;; The compiler is interested only in SPECIAL and UNSPECIAL declarations,
;;; for which the rest of the list contains the symbols being declared,
;;; and MACRO declarations, which look like (DEF symbol MACRO LAMBDA args ..body...),
;;; and ARGLIST declarations, which specify arglists to go in the debugging info
;;; (to override the actual arglist of the function, for user information)
;;; which look like (ARGLIST FOO &OPTIONAL BAR ...), etc.

;;; Things get onto LOCAL-DECLARATIONS in two ways:
;;;  1) inside a LOCAL-DECLARE, the specified declarations are bound onto the front.
;;;  2) if UNDO-DECLARATIONS-FLAG is T, some kinds of declarations
;;;     in a file being compiled into a QFASL file
;;;     are consed onto the front, and not popped off until LOCAL-DECLARATIONS
;;;     is unbound at the end of the whole file.
(DEFVAR LOCAL-DECLARATIONS NIL
  "List of local declarations made by LOCAL-DECLARE or DECLARE.
Each one is a list starting with a local declaration type,
followed by more information meaningful according to that type.")
(DEFVAR UNDO-DECLARATIONS-FLAG NIL
  "T during file-to-file compilation, causes DEFMACRO and DEFSUBST to work differently.
They push elements on FILE-LOCAL-DECLARATIONS rather than
actually defining functions in the environment.")

(DEFVAR FILE-SPECIAL-LIST NIL
  "List of symbols declared globally special in file being compiled.")

(DEFVAR FILE-UNSPECIAL-LIST NIL
  "List of symbols declared globally unspecial in file being compiled.")

;;; FILE-LOCAL-DECLARATIONS is just like LOCAL-DECLARATIONS except that it is
;;; local to the file being compiled.  The reason this exists is so that if
;;; you have a (LOCAL-DECLARE ((ARGLIST ...)) ...) around a (MACRO...),
;;; at compile-time the macro wants to be saved on LOCAL-DECLARATIONS, but that
;;; is bound by the LOCAL-DECLARE, so it uses FILE-LOCAL-DECLARATIONS instead.
(DEFVAR FILE-LOCAL-DECLARATIONS NIL
  "Like LOCAL-DECLARATIONS for declarations at top level in file being compiled.
However, SPECIAL and UNSPECIAL declarations are handled differently
using FILE-SPECIALS and FILE-UNSPECIALS, for greater speed in SPECIALP.")

(DEFVAR SELF-FLAVOR-DECLARATION NIL
  "This is non-NIL if we are supposed to compile
direct accesses to instance variables of SELF.
Its value then is (flavor-name (special-instance-var-names...) instance-var-names...)")

;;; BARF-SPECIAL-LIST is a list of all variables automatically declared special
;;; by the compiler.  Those symbols are special merely by virtue of being on
;;; this list, which is bound for the duration of the compilation
;;; (for the whole file, whole editor buffer, or just the one function in COMPILE).
;;; All users of QC-TRANSLATE-FUNCTION MUST bind this variable.
;;; NOTE!! This list must not be CONSed in a temporary area!!  It lives across
;;;  whack boundaries.
(DEFVAR BARF-SPECIAL-LIST NIL
  "List of symbols automatically made special in this file.")

;;; This is like BARF-SPECIAL-LIST but only lists those symbols
;;; used in the function now being compiled.
;;; If a variable used free is not on this list, it gets a new warning
;;; even though it may already be special because it is on BARF-SPECIAL-LIST.
;;; So there is a new warning for each function that uses the symbol.
(DEFVAR THIS-FUNCTION-BARF-SPECIAL-LIST NIL
  "List of symbols used free in this function but not declared special.
These are the symbols that have been warned about for this function.")

;;; If this is not NIL, there is no warning about using an undeclared free variable.
;;; This is for compiling DEFSUBSTs, which often refer to free variables.
;;; That's ok if you intend them only for expansion.
(DEFVAR INHIBIT-SPECIAL-WARNINGS NIL
  "If non-NIL, no warning is made about free references to variables.")

;;; This is a list of lists; each element of each list
;;; is a symbol which is a variable in the function being compiled.
;;; When lap addresses are assigned, each variable which is not special
;;; is RPLAC'd with NIL.
;;; Further, each list is RPLACD'd with NIL after the last non-NIL element.
(DEFVAR CLOBBER-NONSPECIAL-VARS-LISTS)

(DEFVAR BINDP :UNBOUND
  "BINDP on pass 1 is T if %BIND is called in the current frame.
It is then consed into the internal form of the frame, for pass 2's sake.")

;;; Pass 2 variables needed only in QCP2 except for binding in QCOMPILE0:
;;; See the beginning of QCP2 for more information on them.
(PROCLAIM '(SPECIAL PDLLVL MAXPDLLVL TAGOUT DROPTHRU CALL-BLOCK-PDL-LEVELS))

(DEFVAR QCMP-OUTPUT :unbound
  "An ART-Q-LIST array into which the lap-instructions are stored by pass 2.")

(DEFVAR QC-TF-PROCESSING-MODE :unbound
  "What kind of compilation this is. Either MACRO-COMPILE or MICRO-COMPILE.")

(DEFVAR QC-TF-OUTPUT-MODE :unbound
  "QC-TF-OUTPUT-MODE is used by LAP to determine where to put the compiled code.
It is COMPILE-TO-CORE for making an actual FEF, or QFASL, or REL, or
QFASL-NO-FDEFINE to simply dump a FEF without trying to define a function
/(poor modularity).")

(DEFVAR TLEVEL :unbound
  "TLEVEL on pass 1 is T if we are at /"top level/" within the function being compiled,
not within any actual function calls.
If a PROG is seen when TLEVEL is set, the locals of the prog can
be initialized by the entry to the function.")

(DEFVAR TLFUNINIT :unbound
  "TLFUNINIT on pass 1 is T if we have already seen a variable initialized to the
result of a function call.  Such initializations can't be done except
by compiled code, and once we have initialized one thing that way
all succeeding variables must be initialized by code as well.
/(This applies to serial binding constructs. Parallel is a little different)")

(DEFVAR FAST-ARGS-POSSIBLE :unbound
  "FAST-ARGS-POSSIBLE on pass 1 is T if we haven't come across
any argument to this function with a non-NIL initialization.
If this remains T after all the arguments are processed,
then it is an optimization to make top-level prog vars
be initialized at function entry instead of by code.")

(DEFVAR P1VALUE :unbound
  "During pass 1, P1VALUE is NIL when compiling a form whose value is to be discarded.
P1VALUE is COMPILER::PREDICATE when compiling for predicate value (nilness or non-nilness)
P1VALUE is an integer n when compiling for at most n values (1  most-positive-fixnum)
P1VSALUE is T when compiling for all the values which the form will return.
On pass 2, /"destinations/" are used instead, with many more alternatives.")

(DEFVAR *CHECK-STYLE-P* T
  "During pass 1, means to perform style checking on the current outermost form being
compiler. Inner forms will have their style checked regardless of this flag, unless
somebody arranges otherwise.")

(DEFVAR SELF-REFERENCES-PRESENT :UNBOUND
  "Set to T during pass 1 if any SELF-REFs are generated.")

(DEFVAR PEEP-ENABLE T
  "PEEP-ENABLE, if T, means that the peephole optimizer should be used.
The only reason for setting this to NIL is f you suspect a bug in peephole optimization.")

(DEFVAR FUNCTIONS-REFERENCED :UNBOUND
  "FUNCTIONS-REFERENCED is a list of all functions referred to in the file being
compiled, and not defined in the world.  Each element has as its CAR the
name of the function, and as its CDR a list of the names of the functions
which referenced it.")


;;; Compiler switches:  set these with (EVAL-WHEN (COMPILE) (SETQ ...))
;;; These are reinitialized in QC-PROCESS-INITIALIZE

(DEFVAR OPEN-CODE-MAP-SWITCH T
  "This, if T, causes MAP, etc. to be open-coded.  It is normally T.")
;The use of this variable is obsolete: instead declare (NOTINLINE MAPCAR) or whatever.")

(DEFVAR ALLOW-VARIABLES-IN-FUNCTION-POSITION-SWITCH NIL
  "If T causes a check to be made for the use of a local variable
as a function to be called, meaning funcall.  This should be set to T
only for compiling very old-fashioned Maclisp code.")

(DEFVAR ALL-SPECIAL-SWITCH NIL
  "If T makes all variabes special.")

;;; This, if T (as it usually is), warns the user if any obsolete
;;; Maclisp functions are used.
(DEFVAR OBSOLETE-FUNCTION-WARNING-SWITCH T)

(DEFVAR RUN-IN-MACLISP-SWITCH NIL
  "If T warns the user if he does anything that clearly cannot work in Maclisp.
This is getting fairly useless, now that so little Lisp Machine code could possibly
run in Maclisp anymore.")

(DEFVAR INHIBIT-STYLE-WARNINGS-SWITCH NIL
  "If T prevents warnings about a lot of stylistic losses.")

;;; Counter for breakoff functions
(DEFVAR *BREAKOFF-COUNT*)

(DEFVAR *LEXICAL-CLOSURE-COUNT* :unbound
  "Counts number of lexical closures we had to make.")

(DEFVAR INSIDE-QC-TRANSLATE-FUNCTION NIL
  "T while inside QC-TRANSLATE-FUNCTION")

(ADD-INITIALIZATION "Compiler warm boot"
		    `(COMPILER-WARM-BOOT)
		    '(:WARM))

(DEFUN COMPILER-WARM-BOOT ()
  (DEALLOCATE-WHOLE-RESOURCE 'COMPILER-TEMPORARIES-RESOURCE)
  (SETQ QCOMPILE-TEMPORARY-AREA NIL)
  (SETQ INSIDE-QC-TRANSLATE-FUNCTION NIL)
  (SETQ COMPILER-WARNINGS-CONTEXT NIL))

(DEFMACRO LOCKING-RESOURCES (&BODY BODY)
  "Allocate a temporary area, QCMP-OUTPUT and fasd tables for this process."
  `(FLET ((FOO () . ,BODY))
     (IF QCOMPILE-TEMPORARY-AREA
	 (FOO)
       (USING-RESOURCE (TEMPS COMPILER-TEMPORARIES-RESOURCE)
	 (LET ((QCOMPILE-TEMPORARY-AREA (FIRST TEMPS))
	       (FASD-HASH-TABLE (SECOND TEMPS))
	       (FASD-EVAL-HASH-TABLE (THIRD TEMPS))
	       (QCMP-OUTPUT (FOURTH TEMPS)))
	   (RESET-TEMPORARY-AREA QCOMPILE-TEMPORARY-AREA)
	   (CLRHASH FASD-HASH-TABLE)
	   (CLRHASH FASD-EVAL-HASH-TABLE)
	   (SETF (FILL-POINTER QCMP-OUTPUT) 0)
	   (PROG1
	     (FOO)
	     ;; Get rid of as much as possible to make saved band smaller.
	     (RESET-TEMPORARY-AREA QCOMPILE-TEMPORARY-AREA)
	     ;; Get rid of pointers so GC can collect more stuff.
	     (CLRHASH FASD-HASH-TABLE)
	     (CLRHASH FASD-EVAL-HASH-TABLE)
	     (ARRAY-INITIALIZE QCMP-OUTPUT NIL)))))))

(DEFMACRO LOCKING-RESOURCES-NO-QFASL (&BODY BODY)
  "Allocate a temporary area and a QCMP-OUTPUT for this process.
Use this when compiling to core.
Does not set up fasd tables, to save time."
  `(FLET ((FOO () . ,BODY))
     (IF QCOMPILE-TEMPORARY-AREA
	 (FOO)
       (USING-RESOURCE (TEMPS COMPILER-TEMPORARIES-RESOURCE)
	 (LET ((QCOMPILE-TEMPORARY-AREA (FIRST TEMPS))
	       (FASD-HASH-TABLE NIL)
	       (FASD-EVAL-HASH-TABLE NIL)
	       (QCMP-OUTPUT (FOURTH TEMPS)))
	   (RESET-TEMPORARY-AREA QCOMPILE-TEMPORARY-AREA)
	   (SETF (FILL-POINTER QCMP-OUTPUT) 0)
	   (PROG1
	     (FOO)
	     ;; Get rid of as much as possible to make saved band smaller.
	     (RESET-TEMPORARY-AREA QCOMPILE-TEMPORARY-AREA)
	     (ARRAY-INITIALIZE QCMP-OUTPUT NIL)))))))

(DEFRESOURCE COMPILER-TEMPORARIES-RESOURCE ()
  :CONSTRUCTOR (LIST (MAKE-AREA :NAME (GENTEMP "COMPILATION-AREA-" SI:PKG-COMPILER-PACKAGE)
				:GC :TEMPORARY)
		     (MAKE-HASH-TABLE :SIZE #o40000 :AREA WORKING-STORAGE-AREA)
		     (MAKE-EQUAL-HASH-TABLE :SIZE #o400 :AREA WORKING-STORAGE-AREA)
		     (MAKE-ARRAY #o3000 :AREA WORKING-STORAGE-AREA
				 :TYPE 'ART-Q-LIST
				 :FILL-POINTER 0)))

(DEFVAR COMPILER-WARNINGS-CONTEXT NIL
  "Flag when compiler warnings are being saved for a higher level, like in MAKE-SYSTEM")

(DEFMACRO COMPILER-WARNINGS-CONTEXT-BIND (&BODY BODY)
  "Bind some variables used for compiler warnings."
  (LET ((TOP-LEVEL-P-VAR (GENSYM)))
    `(LET ((,TOP-LEVEL-P-VAR (NOT COMPILER-WARNINGS-CONTEXT)))
       (LET-IF ,TOP-LEVEL-P-VAR
	       ((COMPILER-WARNINGS-CONTEXT T)
		(LAST-ERROR-FUNCTION NIL)
		(FUNCTIONS-REFERENCED NIL)
		(BARF-SPECIAL-LIST NIL))
	 (PROG1 (PROGN . ,BODY)
		(COND (,TOP-LEVEL-P-VAR
		       (PRINT-FUNCTIONS-REFERENCED-BUT-NOT-DEFINED))))))))

(DEFUN FUNCTION-REFERENCED-P (FUNCTION)
  (ASSOC-EQUAL FUNCTION FUNCTIONS-REFERENCED))

(DEFUN COMPILATION-DEFINE (FUNCTION-SPEC)
  "Record that a definition of FUNCTION-SPEC has been compiled."
  (OR (CONSP FUNCTION-SPEC)
      (SI:FUNCTION-SPEC-PUTPROP FUNCTION-SPEC (OR FDEFINE-FILE-PATHNAME T)
				':COMPILATION-DEFINED)))

(DEFUN COMPILATION-DEFINEDP (FUNCTION-SPEC)
  "T if the function spec is defined or a definition of it has been compiled.
Always returns T if function spec is not a symbol."
  (OR (CONSP FUNCTION-SPEC)
      (AND FUNCTION-SPEC
	   (OR (FDEFINEDP FUNCTION-SPEC)
	       (NOT (MEMBER (SI:FUNCTION-SPEC-GET FUNCTION-SPEC ':COMPILATION-DEFINED)
			    '(NIL :UNDEFINED)))))))

(DEFMACRO EXTRACT-DECLARATIONS-RECORD-MACROS (&REST ARGS)
  "Like EXTRACT-DECLARATIONS, but also record names of macros that expand into declarations."
  (DECLARE (ARGLIST BODY &OPTIONAL INITIAL-DECLS DOC-STRING-VALID-P))
  `(LET ((RECORD-MACROS-EXPANDED T))
     (EXTRACT-DECLARATIONS . ,ARGS)))

;;; Inside WARN-ON-ERRORS, this is bound to the TYPE arg to pass to WARN
;;; when an error happens.
(DEFVAR ERROR-WARNING-TYPE :UNBOUND
  "Holds the WARNING-TYPE arg inside a WARN-ON-ERRORS.")

;;; This is a list of a format-string and some args, whose purpose is
;;; to describe the context in which an error generated a warning.
;;; For example, it might be ("Error expanding macro ~S" LOSING-MACRO).
(DEFVAR ERROR-WARNING-ARGS NIL
  "Holds the WARNING-FORMAT-STRING and WARNING-ARGS args inside a WARN-ON-ERRORS.")

(DEFVAR WARN-ON-ERRORS T
  "T to enable the WARN-ON-ERRORS feature while compiling. NIL means get an error.")

(DEFVAR WARN-ON-ERRORS-STREAM NIL
  "Non-NIL => this is stream that read errors are happening on.")

;;; Use this macro to turn errors into compiler warnings.
;;; Used around reading, macroexpanding, etc.
(DEFMACRO WARN-ON-ERRORS ((WARNING-TYPE WARNING-FORMAT-STRING . WARNING-ARGS)
			  &BODY BODY)
  "Execute the body, arranging to make a warning if any error happens.
WARNING-TYPE, WARNING-FORMAT-STRING and WARNING-ARGS
are used to create those warnings, together with the error message."
  `(*CATCH 'WARN-ON-ERRORS
     (CONDITION-RESUME-IF T '(ERROR
			      WARN-ON-ERRORS T
			      ("Continue with compilation.")
			      (LAMBDA (&REST IGNORE) (*THROW 'WARN-ON-ERRORS NIL)))
       (LET ((ERROR-WARNING-TYPE ,WARNING-TYPE)
	     (ERROR-WARNING-ARGS (LIST ,WARNING-FORMAT-STRING . ,WARNING-ARGS)))
	 (CONDITION-BIND ((ERROR 'WARN-ON-ERRORS-CONDITION-HANDLER))
	   . ,BODY)))))

(DEFUN WARN-ON-ERRORS-CONDITION-HANDLER (CONDITION
					 &AUX
					 (CONDITION-NAMES (SEND CONDITION ':CONDITION-NAMES))
					 (DEFAULT-CONS-AREA BACKGROUND-CONS-AREA))
  (IF SI:OBJECT-WARNINGS-OBJECT-NAME
      (PROGN (SI:MAYBE-PRINT-OBJECT-WARNINGS-HEADER)
	     (FORMAT T "~%Warning: ")
	     (APPLY #'FORMAT T ERROR-WARNING-ARGS))
    (PRINT-ERROR-WARNING-HEADER))
  (UNLESS EH:ERRSET-STATUS
    (COND ((AND (MEMQ 'SYS:PARSE-ERROR CONDITION-NAMES)
		(SEND CONDITION ':PROCEED-TYPE-P ':NO-ACTION))
	   (WARN 'READ-ERROR ':ERROR "~A" (SEND CONDITION ':REPORT-STRING))
	   (LET (BP REG)
	     (IF WARN-ON-ERRORS-STREAM
		 (SETQ BP (SEND WARN-ON-ERRORS-STREAM ':SEND-IF-HANDLES ':READ-BP)))
	     (AND BP
		  (SETQ REG (ZWEI:MAKE-REGISTER-NAME #/.))
		  (NOT (GET REG 'ZWEI:POINT))
		  (PROGN
		    (FORMAT T "~&Position of this error saved in ZWEI register /"./".")
		    (ZWEI:SAVE-POSITION-IN-REGISTER REG BP))))
	   ':NO-ACTION)
	  (T
	   (SI:RECORD-WARNING NIL ':ERROR NIL "~A"
			      (APPLY #'FORMAT NIL ERROR-WARNING-ARGS))
	   ;; Make a string now, in case the condition object points at data
	   ;; that is in a temporary area.
	   (WARN ERROR-WARNING-TYPE ':ERROR "~A" (SEND CONDITION ':REPORT-STRING))
	   (COND ((AND WARN-ON-ERRORS
		       (NOT (MEMQ 'SYS:PDL-OVERFLOW CONDITION-NAMES))
		       (NOT (SEND CONDITION ':DANGEROUS-CONDITION-P))
		       (NOT (SEND CONDITION ':DEBUGGING-CONDITION-P)))
		  (FORMAT T "~&TO DEBUG THIS, recompile with COMPILER:WARN-ON-ERRORS set to NIL.")
		  'WARN-ON-ERRORS))))))
  
(DEFUN PRINT-ERROR-WARNING-HEADER ()
  (FORMAT T "~%<< ~A >>"  (APPLY #'FORMAT NIL ERROR-WARNING-ARGS)))


(defun add-optimizer-internal (target-function optimizer-name &optional optimized-into)
  (let ((opts (get target-function 'optimizers)))
    (or (memq optimizer-name opts)
	(putprop target-function (nconc opts (ncons optimizer-name)) 'optimizers))
    (setq opts (get target-function 'optimized-into))
    (dolist (into optimized-into)
      (pushnew into opts :test #'eq))
    (and opts
	 (putprop target-function opts 'optimized-into))
    target-function))

;;; this now adds optimizers in the right order -- earliest-defined optimizations
;;; get done first.
(defmacro add-optimizer (target-function optimizer-name &rest optimized-into)
  "Add OPTIMIZER-NAME to TARGET-FUNCTION's list of optimizers.
Also records that TARGET-FUNCTION sometimes gets optimized into
the functions in OPTIMIZED-INTO, for the sake of WHO-CALLS.
Optimizations added latest get called first."
  `(add-optimizer-internal ',target-function ',optimizer-name ',optimized-into))

(defmacro defoptimizer (optimizer-name function-to-optimize
			&optional ((&rest optimizes-into)) arglist &body body)
  "(defoptimizer foo-optimizer foo (optfoo1 optfoo2) (form)
     (if (eq (cadr form) 'foo)
         `(and (optfoo . ,(cadr form))
               (optfoo2 . (caddr form)))
        form))
OR
/(defoptimizer foo-optimizer foo (optfoo1 optfoo2))"
  (if (null arglist)
      `(add-optimizer-internal ',function-to-optimize ',optimizer-name ',optimizes-into)
    `(progn (add-optimizer-internal ',function-to-optimize ',optimizer-name ',optimizes-into)
	    (defun ,optimizer-name ,arglist
	      (declare (function-parent ,optimizer-name defoptimizer))
	      . ,body))))

;; until there really is such a thing, this is just sylistic
(defmacro defrewrite (rewriter function-to-rewrite
		      #|| &optional ((&rest rewrites-into)) ||# arglist &body body)
  `(progn (add-optimizer-internal ',function-to-rewrite ',rewriter
				  nil #||',rewrites-into||#)
	  (defun ,rewriter ,arglist
	      (declare (function-parent ,rewriter defrewrite))
	      . ,body)))
	    
;; this is 
(defmacro defcompiler-synonym (function synonym-function)
  "Make the compiler substitute SYNONYM-FUNCTION for FUNCTION when compiling.
eg (defcompiler-synonym plus +)"
  `(defrewrite ,(intern (string-append function "-TO-" synonym-function)) ,function
	       #|| (,synonym-function) ||# (form)
     (cons ',synonym-function (cdr form))))


;;;; Variables data bases:

;;; Bound (local or special) variables are described by two lists of variable descriptors:
;;; VARS, which describes only variables visible from the current point of compilation,
;;; and ALLVARS, which describes all variables seen so far in the current compilation.

(DEFVAR VARS :UNBOUND
  "List of variable descriptors of currently lexically visible variables.")

;;; ALLVARS is passed to lap to allocate slots, while VARS is used on both passes
;;; for figuring out what to do with a variable.
(DEFVAR ALLVARS :UNBOUND
  "List of variable descriptors of all variables used within this function.")

(DEFVAR FREEVARS :unbound
  "List of all special variables references free.")

;;; By the time pass 2 is done, this is
;;; a list of VARS entries for the variables of the current function
;;; that are used in lexical closures within it.
(DEFVAR VARIABLES-USED-IN-LEXICAL-CLOSURES)

;;; ARG-MAP and LOCAL-MAP are given the arg map and local map for the debugging info.
;;; This is done by ASSIGN-LAP-ADDRESSES, so that special vars that get a slot
;;; can be put in the map even though their places in it will not be recogizable
;;; from their lap addresses.
(DEFVAR ARG-MAP)
(DEFVAR LOCAL-MAP)
(DEFVAR LOCAL-FUNCTION-MAP)

;;; Each elt of VARS or ALLVARS describes one variable and is called a VAR or a "home".
;;; VARS can also contain elements that represent local SPECIAL declarations
;;; and do not mean that any binding has taken place.  These have FEF-ARG-FREE as the KIND,
;;; FEF-SPECIAL as the TYPE, and the variable as the LAP-ADDRESS.

;;; A VAR has these components:

(DEFSTRUCT (VAR :LIST (:CONC-NAME VAR-) (:ALTERANT NIL))
  (NAME NIL :DOCUMENTATION "The variable's name.
If this is the gensym variable that is used to implement
a local (FLET) function, then the name has a LOCAL-FUNCTION-NAME property
which is the symbol actually defined as a function in the FLET.")
  (KIND NIL :DOCUMENTATION
    "One of FEF-ARG-REQ, FEF-ARG-OPT, FEF-ARG-REST, FEF-ARG-AUX, FEF-ARG-INTERNAL-AUX 
Can also be FEF-ARG-FREE for the entry pushed by a local SPECIAL declaration.")
  (TYPE NIL :DOCUMENTATION
    "Either FEF-LOCAL or FEF-SPECIAL.")
  (USE-COUNT 0 :DOCUMENTATION
    "Number of times variable is used, not counting binding and initialization.")
  (LAP-ADDRESS NIL :DOCUMENTATION
    "(ARG n) for an argument, (LOCAL n) for a local, (SPECIAL symbol) for a special variable.")
  (INIT NIL :DOCUMENTATION "Describes how the variable should be initted on binding.")
  ;; See below for how to interpret this field.
  (EVAL NIL :DOCUMENTATION "FEF-QT-QT for &QUOTE arg, otherwise FEF-QT-EVAL.")
  (MISC NIL :DOCUMENTATION
    "List of additional FEF-... symbols serving as flags about this variable.
FEF-ARG-FUNCTIONAL means it is an &FUNCTIONAL arg.
FEF-ARG-SPECIFIED-FLAG means it is the specified-p variable of an optional arg.
FEF-ARG-USED-IN-LEXICAL-CLOSURES means that lexical closures refer free to this variable.
FEF-ARG-OVERLAPPED means this is the OVERLAP-VAR of some other VAR.
Lap will add the values of these symbols into the ADL word for the variable.")
  (DECLARATIONS NIL :DOCUMENTATION "Declarations pertaining to this variable.")
  		    ;Not used currently.
  (OVERLAP-VAR NIL :DOCUMENTATION "Another VAR, the one whose slot this one shares;
or NIL if there is none."))


(DEFCONST FEF-ARG-SPECIFIED-FLAG 0)
(DEFCONST FEF-ARG-USED-IN-LEXICAL-CLOSURES 0)
(DEFCONST FEF-ARG-OVERLAPPED 0)

;;; The INIT is of the form ( <type> <data> . <arg-supplied-flag home>)
;;; The arg-supplied-flag name is the home of FOOP in &OPTIONAL (FOO NIL FOOP).
;;; It appears only for optional arguments which have such a flag.
;;; If there is none, the cddr of INIT will be nil.
;;; The type is of of several symbols starting with "FEF-INI-", that
;;; signify one of the ways of initializing the variable.
;;; FEF-INI-COMP-C indicates that compiled code will be used to
;;; do the initialization.  It is the most general.  The other types
;;; exist to make special cases more efficient.  They are:

;;; FEF-INI-NONE	No initialization (for a local variable which should be nil).
;;; FEF-INI-SELF	Initialize to self (for special variable).
;;; FEF-INI-NIL		Initialize to NIL (for special variable).
;;; FEF-INI-PNTR	Initialize to a constant.  <data> is that constant.
;;; FEF-INI-C-PNTR	Initialize to the contents of a location.  <data> points to it.
;;; FEF-INI-EFF-ADR	Initialize to the contents of an "effective address".
;;;			This is used to copy the value of a previous arg or local variable.
;;;			<data> specifies which one, using an instruction source field
;;;			which will specify the arg block or the local block, plus offset.
;;; FEF-INI-OPT-SA		For an optional variable with a complicated default value.
;;;			<data> specifies a starting address inside the function
;;;			which is where to start if the argument IS supplied.
;;;			It follows the code used to compute and store the default value.
;;; FEF-INI-COMP-C		Indicates that the variable will be initialized by the
;;;			compiled code of the function.

;;;	- IN GENERAL -
;;;	Internal variables are bound by internal LAMBDA's and PROGS
;;;	Others are bound at entry time
;;;	All internal variables are initialized by code
;;;	Arg variables are never initialized
;;;	Optional and aux variables are initialized at bind time
;;;	If possible otherwise by code
;;;	This "possibility" is determined as follows:
;;;		Initially, it is possible
;;;		It remains possible until you come to a variable
;;;		initialized to a fctn, at which point it is no longer possible
;;;	If var to be initialized by code, code 0 (special) or
;;;	1 (local) is used in initialization field

;;;; GO tag data base.

;;; The variable GOTAGS contains an alist describing all the tags
;;; of TAGBODYs the code we are currently compiling is contained in.
;;; Each element of GOTAGS is a GOTAG, as defined below.

;;; In addition, each BLOCK puts one GOTAG on the list.
;;; That is the block's rettag, which we jump to to return from the block.

(DEFVAR *GOTAG-ENVIRONMENT* :unbound
  "Alist of GOTAGs for each lexically visible tag meaningful to GO.")

;;; ALLGOTAGS is a list of all prog-tags defined so far in the current function,
;;; whether the progs defining them contain the current one or not.
;;; The elements are atoms (the actual tags).
;;; This list is not inherited from the lexically containing function.
;;; ALLGOTAGS is used to determine when the lap-tag of a new tag must be different
;;; from the user-specified prog-tag.
(DEFVAR ALLGOTAGS :unbound
  "List of all tags (actual symbols, not GOTAGs) defined within the current function.")

(DEFSTRUCT (GOTAG :LIST (:CONC-NAME GOTAG-) (:CONSTRUCTOR NIL) (:ALTERANT NIL))
  (PROG-TAG NIL :DOCUMENTATION
    "Actual tag name that the user used. For rettags of blocks, this is a gensym.")
  (LAP-TAG NIL :DOCUMENTATION
    "Tag name to use for LAP. May be the same as GOTAG-PROG-TAG.")
  (PDL-LEVEL NIL :DOCUMENTATION
    "Pdl level we are supposed to have at that point in the code.
Used to tell how many words to pop when you branch.")
  (PROGDESC NIL :DOCUMENTATION
    "Pointer to the element of PROGDESCS for the BLOCK or TAGBODY
that generated this GOTAG.")
  (USED-IN-LEXICAL-CLOSURES-FLAG NIL :DOCUMENTATION
    "T if this tag used in internal lambdas.
The PROGDESC-USED-IN-LEXICAL-CLOSURES-FLAG of our GOTAG-PROGDESC
will also be non-NIL in that case."))


(DEFMACRO MAKE-GOTAG (&OPTIONAL PROG-TAG LAP-TAG PDL-LEVEL PROGDESC)
  `(LIST ,PROG-TAG ,LAP-TAG ,PDL-LEVEL ,PROGDESC NIL))

(DEFVAR *PROGDESC-ENVIRONMENT* :UNBOUND
  "The elements describe the active BLOCK, LET and TAGBODY constructs, innermost first.
Each element is a PROGDESC structure.")

(DEFSTRUCT (PROGDESC :LIST (:CONC-NAME PROGDESC-) (:ALTERANT NIL) :COPIER)
  "Describes one element of PROGDESCS."
  (NAME NIL :DOCUMENTATION "Name of this block, or (TAGBODY) or (LET).
/(TAGBODY) is used for PROGDESCs for TAGBODY forms,
/(LET) is used for PROGDESCs for variable binding forms,
a symbol is used for BLOCKs.")
  (RETTAG NIL :DOCUMENTATION
   "Tag to branch to to exit this construct.  Used for blocks only.
The rettag is followed, if necessary, by code to transfer the
block's value from its IDEST to the actual destination.")
  (IDEST NIL :DOCUMENTATION "Destination to compile contents of block with, on pass 2.
Used for blocks only.")
  (M-V-TARGET NIL :DOCUMENTATION "Value of M-V-TARGET around this block.
Says whether the block's caller wants multiple values.  Used for blocks only.
If it is NIL, only one value is wanted.
If it is MULTIPLE-VALUE-LIST, then the block should really
return the list of the values that RETURN wants to return.
If it is THROW or RETURN, the block should do the hairy things
to pass all but the last value to the frame that is going to get them,
then return the last value on the stack.
If it is a number, the block should return that many values on the stack.")
  (PDL-LEVEL NIL :DOCUMENTATION
   "The <pdl-level> is the pdl level at entry to the construct,
which is also the level in between statements in the construct.
Used in all PROGDESCs, for blocks, binding forms and TAGBODYs.")
  (NBINDS NIL :DOCUMENTATION
   "Number of special bindings to unbind at exit from the construct.
Can also be a list containing the number to unbind, which means
that in addition an unknown number of %BINDs will be done
and therefore UNBIND-TO-INDEX must be used to unbind them
to a specpdl pointer saved at the beginning of the construct.")
  (VARS NIL :DOCUMENTATION "Value of VARS at entry to this block.  Used only in blocks.")
  (ENTRY-LEXICAL-CLOSURE-COUNT NIL :DOCUMENTATION
   "Unused.")
  (EXIT-LEXICAL-CLOSURE-COUNT NIL :DOCUMENTATION
   "Unused.")
  (USED-IN-LEXICAL-CLOSURES-FLAG NIL :DOCUMENTATION
   "For blocks, non-NIL if any lexical closure within this block tries to RETURN from it.
The actual value is a list which is used as a catch tag to implement such RETURNs."))

;(DEFVAR RETPROGDESC :UNBOUND
;  "PROGDESC element for the block that plain RETURN should return from, or NIL if none.")

;;; Queue of functions to be compiled.
;;; Any internal lambdas are put on the queue
;;; so that they get compiled after the containing function.
(DEFVAR COMPILER-QUEUE :UNBOUND
  "List of pending functions to be compiled inside QC-TRANSLATE-FUNCTION.
Each element is a COMPILER-QUEUE-ENTRY.")

;(defstruct (compiler-environment (:type :list) (:conc-name "COMPILER-ENVIRONMENT-")
;				 (:alterant nil) (:callable-constructors nil))
;  (functions nil :documentation "Lexical functions as estblished by FLET and MACROLET, etc.
;Same format as SI::*INTERPRETER-FUNCTION-ENVIRONMENT*")
;  (declarations nil :documentation nil)
;  (function-declarations nil :documentation "Declarations for local functions.
;Format of each elt is (function-name . declarations-list)
;When a new function becomes lexically visible, a new element is created with no delcarations.")
;  (local-functions nil :documentation "Lexical accessible functions.")
;  (variables nil :documentation "Lexically accessible variables.")
;  (progdescs nil :documentation "Structures created by BLOCK, TAGBODY and LET frames")
;  (gotags nil :documentation "Structures created by GO's")

;(defmacro binding-compiler-environment ((environment) &body body)
;  "Execute BODY with the compiler's environment initialized by ENVIRONMENT."
; ******

;(defmacro with-current-compiler-environment
; ******

(DEFSTRUCT (COMPILER-QUEUE-ENTRY :LIST (:CONC-NAME COMPILER-QUEUE-ENTRY-) (:ALTERANT NIL))
  "Describes one element of COMPILER-QUEUE."
  (FUNCTION-SPEC NIL :DOCUMENTATION
    "Function spec to define once compilation is done.")
  (FUNCTION-NAME NIL :DOCUMENTATION
    "Function spec to record in the compiled function as its name.")
  (DEFINITION NIL :DOCUMENTATION
    "Lambda expression to compile.")
;;eventually this slot will replace all those below.
; (environment nil :documentation
;   "Compiler environment we use to compile this function."
  (DECLARATIONS NIL :DOCUMENTATION "Declarations in effect from containing function.")
  (VARIABLES NIL :DOCUMENTATION "Variables accessible through containing function.
This becomes the value of *VARIABLE-ENVIRONMENT*.")
  (LOCAL-FUNCTIONS NIL :DOCUMENTATION "Lexical functions inherited from containing function.")
  (PROGDESCS NIL :DOCUMENTATION "PROGDESCS inherited from containing function.
This becomes the value of *PROGDESC-ENVIRONMENT*.")
  (GOTAGS NIL :DOCUMENTATION "GOTAGS from containing function that we can go to.
This becomes the value of *GOTAG-ENVIRONMENT*.")
  (FUNCTION-ENVIRONMENT NIL :DOCUMENTATION
   "Standard environment function environment frame containing local macros and functions
we are inheriting. This becomes the value of *FUNCTION-ENVIRONMENT*")
; (RETPROGDESC)					;no longer used
  )

(DEFVAR *OUTER-CONTEXT-VARIABLE-ENVIRONMENT* :UNBOUND
  "Intended lexical variable environment of the function being compiled.
For a top-level function in a file, it is NIL.
In general it is a list of VARS lists, to be scanned in the order listed.
Each element corresponds to one environment level,
and the position of a variable home within the element
is its index within that level.
The level number and the index within the level are the two quantities
that are passed to %LOCATE-IN-HIGHER-CONTEXT.")

(DEFVAR *OUTER-CONTEXT-LOCAL-FUNCTIONS* :UNBOUND
  "Used to initialize *LOCAL-FUNCTIONS* for compilation of one function.")

(DEFVAR *OUTER-CONTEXT-FUNCTION-ENVIRONMENT* :UNBOUND
  "Used to initialize *FUNCTION-ENVIRONMENT* for compilation of one function.")

(DEFVAR *OUTER-CONTEXT-PROGDESC-ENVIRONMENT* :UNBOUND
  "Used to initialize *PROGDESC-ENVIRONMENT* for compilation of one function.")

(DEFVAR *OUTER-CONTEXT-GOTAG-ENVIRONMENT* :UNBOUND
  "Used to initialize *GOTAG-ENVIRONMENT* for compilation of one function.")

(DEFVAR *FUNCTION-ENVIRONMENT* :UNBOUND
  "List of frames describing local macro and function definitions.
The format of this object is the same as that of SI::*INTERPRETER-FUNCTION-ENVIRONMENT*.")

(DEFVAR *LOCAL-FUNCTIONS* :UNBOUND
  "Alist of elements (local-function-name vars-entry function-definition)
It records, for each local function name (defined by FLET or LABELS)
the local variable in which the function definition actually lives.")

(defun fsymeval-in-function-environment (symbol &optional (fenv *function-environment*))
  "Returns SYMBOL's function or macro definition within the function environment FENV,
or NIL if it is not defined *by* the environment."
  (with-stack-list (env fenv)
    (fsymeval-in-environment symbol env nil)))
