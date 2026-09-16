;-*- Mode:LISP; Package:SI; Lowercase:T; Base:8; Cold-Load:T; Readtable:T -*-

; ** NOTE **
;>> needs new funcall-closure ucode to run. DO NOT PATCH unless that is installed!!
; eval1, eval-lambda, apply-lambda, apply-lambda-bindvar, gobble-declarations-internal,
; applyhook, applyhook1, applyhook2, apply-lambda(-bindvar(-1)) not patched in 99

;;; Simple lexical evaluator.  Written by RMS.
;;; You can use it, provided you return all improvements to me.

;;; NOTE: it is vital that every link of *INTERPRETER-VARIABLE-ENVIRONMENT*,
;;; *INTERPRETER-FRAME-ENVIRONMENT* and of *INTERPRETER-FUNCTION-ENVIRONMENT*
;;; be a full two-word pair.

(defvar *interpreter-variable-environment* nil
  "The current lexical environment for evaluation.
The value is a list of environment frames, each of which looks like
 (CELL VALUE CELL VALUE ...)
Each CELL is a locative (usually to a value cell),
and the following VALUE is the lexical value for that cell.
For a special binding, the VALUE is actually a DTP-ONE-Q-FORWARD to the cell.

Each place where a group of variables is bound (each LET, LAMBDA, PROG,...)
makes its own environment frame.

The tail of the list can be T rather than NIL.  This means
that all variables should be considered special if not found
in the entries in the environment.")

;;; This is a separate variable because usually will be NIL
;;; and that way the search for functions is not slowed down by local variables.
(defvar *interpreter-function-environment* nil
  "Like SI::*INTERPRETER-VARIABLE-ENVIRONMENT* but contains lexical functions
rather than variables.")

(defvar *interpreter-frame-environment* nil
  "Like SI::*INTERPRETER-VARIABLE-ENVIRONMENT* but contains stuff for TAGBODY and BLOCK, etc.
Each frame starts with the symbol BLOCK or TAGBODY;
the second element is a list of further data:
 for a BLOCK: (NAME CATCH-TAG-ADDR-ON-STACK)
 for a TAGBODY: (BODY CATCH-TAG-ADDR-ON-STACK)
SI::UNSTACKIFY-ENVIRONMENT needs to recognize these special kinds
of frames; if you add more, you may need to change it.") 

(defstruct (interpreter-environment (:type :list) (:conc-name "INTERPRETER-ENVIRONMENT-")
				    (:alterant nil))
  (functions nil :documentation "Stuff established by FLET and MACROLET, etc.")
  (declarations nil :documentation "Not used in the interpreter.
This slot is here for consistency with (forseen) compiler environment structures.")
  (variables nil :documentation "Stuff established by LAMBDA and LET, etc.")
  (frames nil :documentation "Stuff established by BLOCK and TAGBODY, etc.")
  ;(macrocache nil :documentation "Cached macro expansions.")
  ;; anything else?
  )

(defmacro binding-interpreter-environment ((environment) &body body)
  "Execute BODY with the interpreter's environment initialized by ENVIRONMENT."
  (once-only (environment)
    `(let ((*interpreter-variable-environment*
	     (interpreter-environment-variables ,environment))
	   (*interpreter-function-environment*
	     (interpreter-environment-functions ,environment))
	   (*interpreter-frame-environment*
	     (interpreter-environment-frames ,environment)))
       . ,body)))

(defmacro with-current-interpreter-environment
	  ((var &optional (vars-env '*interpreter-variable-environment*))
	   &body body)
  "Execute BODY with VAR bound to an environment object constructed from the current
interpreter environment."
  `(with-stack-list (,var *interpreter-function-environment*
		     	  nil			;declarations
		     	  ,vars-env
			  *interpreter-frame-environment*)
     . ,body))

(defmacro bash-to-current-interpreter-environment (env)
  "Make ENV be the current interpreter environment."
  (once-only (env)
    `(setf (interpreter-environment-variables ,env) *interpreter-variable-environment*
	   (interpreter-environment-functions ,env) *interpreter-function-environment*
	   (interpreter-environment-frames ,env) *interpreter-frame-environment*)))

(defparameter lambda-parameters-limit 60.
  "Functions accepting less than this many arguments are allowed.")

(defparameter call-arguments-limit 60.
  "Passing fewer than this many arguments in a function call is guaranteed to be ok.
Note that elements of a &rest arg that is never actually spread
do not count in this limit.")

(defparameter multiple-values-limit 60.
  "Ostensible upper bound on number of values a function call can return.
In fact, this is not what is limited, and you can get away with three times
as many if you don't fill up the maximum stack frame size in other ways.")

(defparameter lambda-list-keywords
	      '(&optional &rest &key &allow-other-keys &aux
		&special &local &functional &eval &quote
		&environment &list-of &body &whole)
  "List of all &-keywords that have special meanings in argument lists of functions.")

(defvar *evalhook* nil "Value is function used on calls to EVAL, inside calls to EVALHOOK.")
(defvar evalhook :unbound
  "Value is function used on calls to EVAL, inside calls to EVALHOOK.")
(forward-value-cell 'evalhook '*evalhook*)

(defvar *applyhook* nil
  "Value is function used on applications performed by EVAL, inside calls to EVALHOOK.
The function receives two arguments, like those which APPLY would receive.")
(defvar applyhook :unbound
  "Value is function used on applications performed by EVAL, inside calls to EVALHOOK.
The function receives two arguments, like those which APPLY would receive.")
(forward-value-cell 'applyhook '*applyhook*)


;;;; Basic primitives for operating on interpreter variables.

(defsubst interpreter-symeval (symbol)
  (let (mumble)
    (do ((tail *interpreter-variable-environment* (cdr tail)))
	((atom tail)				;assume free references are special
	 (or tail (getl symbol '(special system-constant))
	     (var-not-special symbol))
	 (symeval symbol))
      (and (setq mumble (get-lexical-value-cell (car tail) (locf (symbol-value symbol))))
	   (return (car mumble))))))

(defun interpreter-boundp (symbol &aux mumble)
  (do ((tail *interpreter-variable-environment* (cdr tail)))
      ((atom tail)				;assume free references are special
       (or tail (getl symbol '(special system-constant))
	   (var-not-special symbol))
       (boundp symbol))
    (and (setq mumble (get-lexical-value-cell (car tail) (locf (symbol-value symbol))))
	 (return t))))

(defsubst interpreter-set (symbol value)
  (let (mumble)
    (do ((tail *interpreter-variable-environment* (cdr tail)))
	((atom tail)				;assume free references are special
	 (or tail (getl symbol '(special system-constant))
	     (var-not-special symbol))
	 (set symbol value))
      (and (setq mumble (get-lexical-value-cell (car tail) (locf (symbol-value symbol))))
	   (return (setf (car mumble) value))))))

(defun interpreter-external-value-cell (symbol &aux mumble)
  (do ((tail *interpreter-variable-environment* (cdr tail)))
      ((atom tail)				;assume free references are special
       (or tail (getl symbol '(special system-constant))
	   (var-not-special symbol))
       (%external-value-cell symbol))
    (and (setq mumble (get-lexical-value-cell (car tail) (locf (symbol-value symbol))))
	 (return (follow-cell-forwarding mumble t)))))

(defun interpreter-fsymeval (symbol &aux mumble)
  (dolist (frame *interpreter-function-environment*
		 (symbol-function symbol))
    (and (setq mumble (get-location-or-nil (locf frame) (locf (symbol-function symbol))))
	 (return (car mumble)))))

(defvar *all-free-interpreter-variable-references-special* nil
  "T means to make all free references to variables in the interpreter
act as special references.
Its a much better idea to use the function SI:EVAL-SPECIAL-OK than to bind this.")

(defprop var-not-special t :error-reporter)
(defun var-not-special (symbol)
  (or *all-free-interpreter-variable-references-special*
      (multiple-cerror '(variable-not-special) ()
		       ("~S is referenced as a free variable but not declared special."
			symbol)
	("Use current dynamic binding and proceed.")
	("Make symbol globally special, and use current dynamic binding."
	 (putprop symbol t 'special))))
  t)

;;; T if there was a special declaration made in the current construct.
;;; FRAME-INTERPRETER-ENVIRONMENT should be specified as the NEWENV-VAR
;;; of the GOBBLE-DECLARATIONS-FROM-BODY done in that construct.
;;; Or it should be NIL if this construct doesn't process declarations,
;;; though in general a construct that binds variables ought to allow declarations!

;;; This one is unusual, as it is passed a locative to a cell rather than a symbol.
;;; It is interfaced this way due to the way the code works out in PARALLEL-BINDING-LIST.
(defmacro interpreter-variable-special-in-frame-p (cell frame &optional default defaultp)
  `(let ((mumble (compiler::undefined-value)))
     (setq mumble (get-lexical-value-cell (car ,frame) ,cell))
     (cond (mumble
	    (= (%p-data-type mumble) dtp-one-q-forward))
	   (,defaultp
	    ,default)
	   (t (cadr (getl (%find-structure-header ,cell) '(special system-constant)))))))

;;; Produce code to evaluate a special form body, found as the value of BODYVAR.
;;; The code produced will return multiple values from the last element of the body.
(defmacro eval-body (bodyvar)
  `(if (null ,bodyvar) nil
     (do ((l ,bodyvar (cdr l)))
	 ((null (cdr l))
	  (eval1 (car l)))
       (eval1 (car l)))))

(defun constantp (form)
  "T if FORM always evaluates to the same thing.
This includes keyword symbols, and lists starting with QUOTE."
  (cond ((consp form)
	 (eq (car form) 'quote))
	((symbolp form)
	 (or (eq form nil) (eq form t)
	     (keywordp form)
	     (get form 'system-constant)))
	(t t)))

;;; Same as constantp, except excludes defconstants...
;;; pleblisp doesn't specify this, but it's sure as hell useful...
(defun self-evaluating-p (form)
  "T if FORM always evaluates to itself."
  (cond ((consp form)
	 (eq (car form) 'quote))
	((symbolp form)
	 (or (eq form nil) (eq form t)
	     (keywordp form)))
	(t t)))

;;;; Processing of local declarations in special forms.

;;; When (PROGN (DECLARE (SPECIAL A)) ...) is seen,
;;; it is necessary to push a binding frame onto *INTERPRETER-VARIABLE-ENVIRONMENT*
;;; containing a binding for A to mark A as special.
;;; This binding contains as its value
;;; a one-q forward to the special value cell of A.

;;; GOBBLE-DECLARATIONS-FROM-BODY is the form PROGN uses to accomplish this.
;;; (GOBBLE-DECLARATIONS-FROM-BODY (vars-env-var body-exp)
;;;   (EVAL-BODY body-exp))
;;; causes the appropriate binding frame to be pushed
;;; for declarations at the front of body-exp's value
;;; before the EVAL-BODY is done.

;;; Forms such as LET which do variable binding
;;; must process the declarations FIRST so they know which vars are special.
;;; Also, these forms should note that the vars-env-var
;;; is bound to a list whose car is a frame that describes any SPECIAL declarations found.
;;; The vars-env-var's value should be passed to INTERPRETER-VARIABLE-SPECIAL-IN-FRAME-P
;;; in order to decide whether a binding done in this frame should be special.
;;; All macros for binding variables for Common Lisp (SERIAL-BINDING-LIST, etc.)
;;; expect the vars-env-var as an argument.

;;; UNSPECIAL declarations also work!

(defvar *interpreter-declaration-type-alist*
  '(;; declarations actually used by the interpreter
    ;;  --- done specially in GOBBLE-DECLARATIONS-INTERNAL
;   (SPECIAL special//unspecial-interpreter-declaration)
;   (UNSPECIAL special//unspecial-interpreter-declaration)

    ;; lispm declarations
    (:SELF-FLAVOR self-flavor-interpreter-declaration)
    (SELF-FLAVOR self-flavor-interpreter-declaration)
    (FUNCTION-PARENT ignore)

    ;; type declarations -- ignored
    (TYPE ignore)
    (ARRAY ignore)
    (ATOM ignore)
    (BIGNUM ignore)
    (BIT ignore)
    (BIT-VECTOR ignore)
    (CLI:CHARACTER ignore)
    (CHARACTER ignore)
    (COMMON ignore)
    (COMPILED-FUNCTION ignore)
    (COMPLEX ignore)
    (CONS ignore)
    (DOUBLE-FLOAT ignore)
    (FIXNUM ignore)
    (FLOAT ignore)
    (FUNCTION ignore)
    (HASH-TABLE ignore)
    (INTEGER ignore)
    (KEYWORD ignore)
    (LIST ignore)
    (LONG-FLOAT ignore)
    (NIL ignore)
    (NULL ignore)
    (NUMBER ignore)
    (PACKAGE ignore)
    (PATHNAME ignore)
    (RANDOM-STATE ignore)
    (RATIO ignore)
    (RATIONAL ignore)
    (READTABLE ignore)
    (SEQUENCE ignore)
    (SHORT-FLOAT ignore)
    (SIMPLE-ARRAY ignore)
    (SIMPLE-BIT-VECTOR ignore)
    (SIMPLE-STRING ignore)
    (SIMPLE-VECTOR ignore)
    (SINGLE-FLOAT ignore)
    (STANDARD-CHAR ignore)
    (STREAM ignore)
    (STRING ignore)
    (STRING-CHAR ignore)
    (SYMBOL ignore)
    (T ignore)
    (VECTOR ignore)

    (FTYPE ignore)
    (FUNCTION ignore)

    ;; can these mean anything to the interpreter?
    (INLINE ignore)
    (NOTINLINE ignore)
    (IGNORE ignore)
    (OPTIMIZE ignore)

    (DECLARATION define-declaration)
    (DOCUMENTATION ignore)

;;;---!!! Are these (ARGLIST, VALUES, ZWEI:INDENTATION) these needed?
    (arglist ignore)
    (values ignore)
    (zwei:indentation ignore)

;   ;; mucklisp turds
;   (*EXPR ignore)
;   (*FEXPR ignore)
;   (*LEXPR ignore)
    )
  "Alist of elements (decl-type interpreter-handler-function)
decl-type is a symbol such as SPECIAL or TYPE.
The handler-function is called with the declaration and the current interpreter environment
as args.")

(defun self-flavor-interpreter-declaration (decl ignore)
  (unless (typep self (cadr decl))
    (cerror "Ignore the ~S declaration (and hope for the best)"
	    "~S is declared to be ~S,~% but ~S is of type ~S"
	    'self-flavor (cadr decl) 'self (type-of self))))

;;; not really right since this defines a declaration gloablly, rather than
;;; just within  the scope of this declaration. Fuck that.
(defun define-declaration (declaration ignore)
  (dolist (decl (cdr declaration))
    (push `(,decl ignore) *interpreter-declaration-type-alist*)))

(defun proclaim (&rest declarations &aux d)
  "Make DECLARATIONS be in effect globally.
Only SPECIAL declarations make sense to do this way,
and they are better made using DEFVAR or DEFPARAMETER."
  (dolist (decl declarations)
    (when (or (atom decl) (not (atom (setq d (car decl)))))
      (ferror nil "~S is an invalid declaration" decl))
    (case d
      ((special unspecial)
       (eval1 decl))
      (inline
       )
      (notinline
       )
      (declaration
       (dolist (x (cdr decl))
	 (pushnew `(,(car decl) ignore) *interpreter-declaration-type-alist*
		  :test #'eq :key #'car)))
      (t (unless (assq d *interpreter-declaration-type-alist*)
	   (ferror nil "~S is an unknown declaration" decl))
	 ;; else do nothing...
	 )))
  nil)

(defmacro gobble-declarations-from-body ((vars-env-var caller-body-exp) &body macro-body)
  `(with-stack-list* (,vars-env-var nil *interpreter-variable-environment*)
     (when (eq (caar-safe ,caller-body-exp) 'declare)
;      (%bind (locf (symbol-value 'local-declarations)) local-declarations)
       (%bind (locf (symbol-value '*interpreter-variable-environment*)) ,vars-env-var)
       (gobble-declarations-internal ,caller-body-exp ,vars-env-var))
     . ,macro-body))

;;; This is called from expansions of the preceding macro.
;;; *INTERPRETER-VARIABLE-ENVIRONMENT* has already been rebound ;;(and LOCAL-DECLARATIONS)
;;; but this function actually puts the declaration info into their values.
;;; BODY is the body of the special form that the user is evaluating,
;;; at the front of which appear the declarations if any.
(defun gobble-declarations-internal (body vars-env &aux tem)
  (dolist (bodyelt body)
    (unless (eq (car-safe bodyelt) 'declare)
      (return nil))
;; what good is this?
;   (setq local-declarations
;	  (append (cdr bodyelt) local-declarations))
    (dolist (decl (cdr bodyelt))
      (case (car decl)
	;; these are the important ones.
	((special unspecial)
	 (dolist (var (cdr decl))
	   ;; ** CONS **
	   (setf (car vars-env) (list* (locf (symbol-value var)) nil (car vars-env)))
	   (if (eq (car decl) 'special)
	       (let ((slot (locf (cadr (car vars-env)))))
		 (%p-store-pointer slot (locf (symbol-value var)))
		 (%p-store-data-type slot dtp-one-q-forward)))))
	(t
	 (cond ((get (car decl) 'debug-info)
		nil)
	       ((setq tem (or (assq (car decl) *interpreter-declaration-type-alist*)
			      ;; gratuitous until ftype, etc globalized...
			      (assq (intern (car decl) (symbol-package 'foo))
				    *interpreter-declaration-type-alist*)))
		(with-current-interpreter-environment (env vars-env)
		  (funcall (cadr tem) decl env)))
	       (t (cerror "Proceeds, ignoring the declaration"
			  "The interpreter encountered the unknown declaration ~S"
			  decl))))))))

;;; EVAL cannot safely call LIST, since that would lose
;;; if the interpreter needs to pass an explicit rest arg
;;; (such as if there are more than 64 args).
;;; So it calls LIST-FOR-EVAL instead.
;;; Perhaps a new entry point named INTERNAL-LIST should be made
;;; and the compiler should make uses of LIST call INTERNAL-LIST instead.
;;; Then, once things are recompiled, LIST-FOR-EVAL could be renamed to LIST.

; must use setq rather than defvar so the cold-load builder has an evaluator!
(defparameter *list-etc-function-mappings* nil)
(setq *list-etc-function-mappings*
      (list (cons #'list 'list-for-eval)
	    (cons #'list* 'list*-for-eval)
	    (cons #'list-in-area 'list-in-area-for-eval)
	    (cons #'list*-in-area 'list*-in-area-for-eval)
	    (cons #'*catch 'catch-for-eval)
	    (cons #'catch 'catch-for-eval)))

(defun list-for-eval (&rest elements)
  (copylist elements))

(defun list-in-area-for-eval (default-cons-area &rest elements)
  (copylist elements))

(defun list*-for-eval (&rest elements)
  (cond ((null elements) nil)
	((null (cdr elements))
	 (car elements))
	(t
	 (let* ((l (copylist elements))
		(last (last l)))
	   (%p-dpb-offset cdr-error %%q-cdr-code last 0)
	   (%p-dpb-offset cdr-normal %%q-cdr-code last -1)
	   l))))

(defun list*-in-area-for-eval (default-cons-area &rest elements)
  (cond ((null elements) nil)
	((null (cdr elements))
	 (car elements))
	(t
	 (let* ((l (copylist elements))
		(last (last l)))
	   (%p-dpb-offset cdr-error %%q-cdr-code last 0)
	   (%p-dpb-offset cdr-normal %%q-cdr-code last -1)
	   l))))

;;; EVAL cannot just call CATCH, since then only one value of the
;;; body would be returned.  Instead it calls CATCH-FOR-EVAL,
;;; which takes a quoted rest arg (unlike CATCH).  It can
;;; eval the body carefully and return all the values.

;;; The cleaner solution that would work for LIST is not as easy for CATCH
;;; since there are things (in the error handler, and maybe elsewhere)
;;; that know that they can find catch frames by looking for
;;; frames that call #'*CATCH.  So #'*CATCH must be the real thing,
;;; or those places must be fixed up.

(defun catch-for-eval (tag &quote &rest body)
  (catch tag
    (eval-body body)))

;;; The standard externally called forms of EVAL are here.
;;; They handle all kinds of atoms themselves,
;;; to save the extra function call.
;;; They use EVAL1 to handle combinations.

(defun eval (form &optional nohook)
  "Evaluate FORM in the global environment, returning its value(s).
Free variables in FORM must be special.
If there is an *EVALHOOK*, it is invoked to do the work, unless NOHOOK is true."
  (binding-interpreter-environment (())
    (cond ((and *evalhook* (not nohook))
	   (let ((tem *evalhook*)
		 (*evalhook* nil)
		 (*applyhook* nil))
	     (with-current-interpreter-environment (env)
	       (funcall tem form env))))
	  ((symbolp form)
	   (or (keywordp form) (getl form '(special system-constant))
	       (var-not-special form))
	   (symeval form))
	  ((atom form) form)
	  (t
	   (eval1 form)))))

(defparameter specials-ok-environment nil)
(defun eval-special-ok (form &optional nohook)
  "Evaluate FORM in the global environment, allowing free variables, returning its value(s).
If there is an *EVALHOOK*, it is invoked to do the work, unless NOHOOK is true."
  (unless specials-ok-environment
    (setq specials-ok-environment (make-interpreter-environment :variables t)))
  (binding-interpreter-environment (specials-ok-environment)
    (cond ((and *evalhook* (not nohook))
	   (let ((tem *evalhook*)
		 (*evalhook* nil)
		 (*applyhook* nil))
	     (with-current-interpreter-environment (env)
	       (funcall tem form env))))
	  ((symbolp form)
	   (symeval form))
	  ((atom form) form)
	  (t
	   (eval1 form)))))

(defparameter old-dynamic-environment nil)
(defun old-dynamic-eval (form &optional nohook)
  "Evaluate FORM using the old-style dynamic evaluator
/(ie all variables and functions bound as specials,
 and free reference to non-special variables allowed)
This is a kludge: you should not be using this function for anything but to bootstrap old
code to make it work with the new winning interpreter.

This function will not be supported indefinitely: please update your code to reflect
the /"New Order/"."
  (unless old-dynamic-environment
    (setq old-dynamic-environment (make-interpreter-environment :functions t :variables t)))
  (binding-interpreter-environment (old-dynamic-environment)
    (cond ((and *evalhook* (not nohook))
	   (let ((tem *evalhook*)
		 (*evalhook* nil)
		 (*applyhook* nil))
	     (with-current-interpreter-environment (env)
	       (funcall tem form env))))
	  ((symbolp form)
	   (symbol-value form))
	  ((atom form) form)
	  (t
	   (eval1 form)))))

(defun eval-abort-trivial-errors (top-level-form)
  "Evaluate TOP-LEVEL-FORM, returning the value, but aborting on trivial errors.
A trivial error is one involving a symbol present in the form itself.
Aborting is done by signaling SYS:ABORT, like the Abort key.
The user gets to choose whether to do that or to enter the debugger as usual.
Uses SI:EVAL-SPECIAL-OK, so will not err on free variable references."
  (declare (special top-level-form))
  (condition-bind (((sys:too-few-arguments sys:too-many-arguments
		     sys:cell-contents-error sys:wrong-type-argument
		     sys:invalid-function-spec sys:unclaimed-message)
		    'eval-abort-trivial-errors-handler))
    ;; Eval, making all free variable references special
    (eval-special-ok top-level-form)))

(defun eval-abort-trivial-errors-handler (condition)
  (declare (special top-level-form))
  (when (cond ((condition-typep condition 'sys:cell-contents-error)
	       (and (symbolp (send condition :containing-structure))
		    (mem*q-fwd (send condition :containing-structure) top-level-form)))
	      ((condition-typep condition 'sys:invalid-function-spec)
	       (mem*q (send condition :function-spec) top-level-form))
	      ((condition-typep condition 'sys:unclaimed-message)
	       (mem*q (send condition :message) top-level-form))
	      (t (mem*q (function-name (send condition :function)) top-level-form)))
    (send *query-io* :fresh-line)
    (send condition :print-error-message current-stack-group t *query-io*)
    (send *query-io* :clear-input)
    (let ((*evalhook* nil)
	  (*applyhook* nil))
      (unless (fquery `(:choices
			 ,(mapcar #'(lambda (choice)
				      (if (eq (caar choice) nil)
					  (append choice '(#/c-Z))
					choice))
				  format:y-or-n-p-choices))
		      "Enter the debugger (No means abort instead)? ")
	(signal-condition eh:abort-object))))
  (values))

(defun mem*q-fwd (elt tree)
  "T if ELT is TREE or an element of TREE or an element of an element, etc.
Does not compare the CDRs (the links of the lists of TREE), just the elements.
Regards two symbols as equal if their value cells are forwarded together."
  ;; Cannot use MEMQ since it gets an error if a list ends in a non-NIL atom.
  (or (eq elt tree)
      (and (symbolp tree)
	   (symbolp elt)
	   (eq (follow-cell-forwarding (locf (symbol-value elt)) t)
	       (follow-cell-forwarding (locf (symbol-value tree)) t)))
      (do ((tail tree (cdr tail)))
	  ((atom tail) nil)
	(if (or (eq (car tail) elt)
		(mem*q-fwd elt (car tail)))
	    (return t)))))

(defun mem*q (elt tree)
  "T if ELT is TREE or an element of TREE or an element of an element, etc.
Does not compare the CDRs (the links of the lists of TREE), just the elements."
  ;; Cannot use MEMQ since it gets an error if a list ends in a non-NIL atom.
  (or (eq elt tree)
      (do ((tail tree (cdr tail)))
	  ((atom tail) nil)
	(if (or (eq (car tail) elt)
		(mem*q elt (car tail)))
	    (return t)))))


(defun evalhook (form *evalhook* *applyhook* &optional environment)
  "Evaluate FORM, using specified *EVALHOOK* and *APPLYHOOK* except at the top level.
ENVIRONMENT is the lexical environment to eval in.
Or use the environment argument passed to an EVALHOOK function."
  (binding-interpreter-environment (environment)
    (eval1 form t)))

(defun applyhook (function args *evalhook* *applyhook* &optional environment)
  "Apply FUNCTION to ARGS, using specified *EVALHOOK* and *APPLYHOOK* except at the top level.
ENVIRONMENT is the lexical environment to eval in.
 Or use the environment argument passed to an EVALHOOK function."
  (if (consp function)
      (apply-lambda function args environment)
      (apply function args)))

;;; This is the real guts of eval.  It uses the current lexical context.
;;; If that context includes *INTERPRETER-FUNCTION-ENVIRONMENT* = T,
;;; then Zetalisp evaluation is done.
;;; All special forms call EVAL1 directly to eval their arguments.

(defun eval1 (form &optional nohook)
  "Evaluate FORM in the current lexical environment, returning its value(s).
If the current environment says /"traditional Zetalisp/", we do that.
This is the function that special forms such as COND use to evaluate
their subexpressions, as it allows the subexpressions to access
lexical variables of the containing code.  Contrast with EVAL."
  ;; Make sure all instances of ARGNUM, below, are local slot 0.
  (let (argnum) argnum)
  (with-current-interpreter-environment (env)
    (cond ((and *evalhook* (not nohook))
	   (let ((tem *evalhook*)
		 (*evalhook* nil)
		 (*applyhook* nil))
	     (funcall tem form env)))
	  ((symbolp form)
	   (cond ((keywordp form)
		  form)
		 ((eq *interpreter-function-environment* t)
		  (symbol-value form))
	         (t (interpreter-symeval form))))
	  ((atom form) form)
	  ((eq (car form) 'quote)
	   (cadr form))
	  (t (let ((fctn (car form)) arg-desc num-args tem)
	       ;; Trace FCTN through symbols and closures to get the ultimate function
	       ;; which will tell us whether to evaluate the args.
	       (tagbody				;don't use DO-FOREVER!
		loop				; that would fuck over %using-bindings-instances
		   (typecase fctn
		     (symbol
		      (setq fctn
			    (if (eq *interpreter-function-environment* t)
				(symbol-function fctn)
			      (interpreter-fsymeval fctn)))
		      (go loop))
		     ((or closure entity) 
		      (setq tem (%make-pointer dtp-list fctn))
		      (%using-binding-instances (cdr tem))
		      ;;>> this grossness will be fixed when the format or interpreter envs
		      ;;>> is fixed
		      (if (interpreter-environment-closure-p fctn)
			  (bash-to-current-interpreter-environment env))
		      (setq fctn (car tem))
		      (go loop))
		     (t nil)))
	       (setq arg-desc (%args-info fctn))
	       (if (bit-test %arg-desc-interpreted arg-desc)
		   ;; Here if not a FEF.
		   (progn
		     ;; Detect ucode entry that is not actually microcoded.
		     (and (typep fctn 'microcode-function)
			  (not (integerp (system:micro-code-entry-area (%pointer fctn))))
			  (setq fctn (aref (symbol-function 'system:micro-code-entry-area)
					   (%pointer fctn))))
		     (typecase fctn
		       (cons
			(case (car fctn)
			  ((lambda subst cli:subst named-lambda named-subst)
			   (eval-lambda form fctn env))
			  (macro (eval1 (error-restart (error "Retry macro expansion.")
					  ;;>> UGH!!
					  (let ((*macroexpand-environment* env))
					    (automatic-displace (cdr fctn) form)))
					t))
			  ((curry-before curry-after)
			   (if *applyhook*
			       (progn (%open-call-block 'applyhook1 0 4)
				      (%push env)
				      (%push fctn))
			     (%open-call-block fctn 0 4))
			   (%assure-pdl-room (length (cdr form)))
			   (do ((argl (cdr form) (cdr argl))
				(argnum 0 (1+ argnum)))
			       ((null argl))
			     (%push (eval1 (car argl))))
			   (%activate-open-call-block))
			  (t (if (lambda-macro-call-p fctn)
				 (eval1 (cons (lambda-macro-expand fctn) (cdr form)))
			       (invalid-function form)))))
		       ((or select-method instance)
			(if *applyhook*
			    (progn (%open-call-block 'applyhook1 0 4)
				   (%push env)
				   (%push fctn))
			  (%open-call-block fctn 0 4))
			(%assure-pdl-room (length (cdr form)))
			(do ((argl (cdr form) (cdr argl))
			     (argnum 0 (1+ argnum)))
			    ((null argl))
			  (%push (eval1 (car argl))))
			(%activate-open-call-block))
		       (t (invalid-function form))))
		 ;; FEF (or ucode entry that's microcoded or a FEF).
		 ;; Open call block accordingly to whether there's a quoted rest arg.
		 ;; Also, if more than 64 args to fn taking evaled rest arg,
		 ;; we must make an explicit rest arg to avoid lossage.
		 ;; LIST, etc., may not be called directly because the ucode versions
		 ;; do not deal with explicitly passed rest arguments.
		 (and *list-etc-function-mappings*
		      (cdr (assq fctn *list-etc-function-mappings*))
		      (setq fctn (symbol-function
				   (cdr (assq fctn *list-etc-function-mappings*)))
			    arg-desc (%args-info fctn)))
		 (cond ((or (and (bit-test %arg-desc-quoted-rest arg-desc)
				 (> (length (cdr form)) (ldb %%arg-desc-max-args arg-desc)))
			    (and (bit-test %arg-desc-evaled-rest arg-desc)
				 (> (length (cdr form)) 63.)))
			;; NUM-ARGS includes only the spread args.
			(setq num-args (ldb %%arg-desc-max-args arg-desc))
			(if *applyhook*
			    (progn (%open-call-block 'applyhook2 0 4)
				   (%push env)
				   (%push fctn))
			  ;; ADI for fexpr-call.
			  (%push 0)
			  (%push #.(dpb adi-fexpr-call %%adi-type 0))
			  (%open-call-block fctn 1 4))
			;; We need room for the spread args, plus one word for the rest arg.
			(%assure-pdl-room (1+ num-args)))
		       (t
			(setq num-args (length (cdr form)))
			(if *applyhook*
			    (progn (%open-call-block 'applyhook1 0 4)
				   (%push env)
				   (%push fctn))
			  (%open-call-block fctn 0 4))
			(%assure-pdl-room num-args)))
		 ;; If some spread args are quoted, use the ADL to tell which.
		 (cond ((bit-test %arg-desc-fef-quote-hair arg-desc)
			;; Get the ADL pointer.
			(let ((adl (get-macro-arg-desc-pointer fctn)))
			  (do ((argl (cdr form) (cdr argl))
			       (argnum 0 (1+ argnum)))
			      ((= argnum num-args)
			       ;; Done with spread args => push rest arg if any.
			       (when argl
				 (%push
				   (if (bit-test %arg-desc-evaled-rest arg-desc)
				       (mapcar #'eval1 argl)
				       argl))))
			    (let ((item (or (car adl) fef-qt-eval)))
			      ;; Figure out how many extra words of ADL to skip for this arg.
			      (if (bit-test %fef-name-present item) (pop adl))
			      (selector (logand %fef-arg-syntax item) =
				(fef-arg-opt
				 (if (memq (logand item %fef-init-option)
					   '(#.fef-ini-pntr #.fef-ini-c-pntr
					     #.fef-ini-opt-sa #.fef-ini-eff-adr))
				     (pop adl)))
				(fef-arg-req)
				;; Note: does not get here for quoted rest arg.
				;; Gets here for evalled rest arg, or if no more args wanted
				;; (eval extra args supplied here; get error later).
				(t (setq adl nil)))
			      (pop adl)
			      ;; Eval the arg if the ADL says to do so.
			      (%push (if ( (logand %fef-quote-status item) fef-qt-qt)
					 (eval1 (car argl))
					 (car argl)))))))
		       (t
			;; No quoted args except possibly the rest arg.  Don't look at ADL.
			(do ((argnum 0 (1+ argnum))
			     (argl (cdr form) (cdr argl)))
			    ((= argnum num-args)
			     ;; Done with spread args => push the rest arg.
			     (when argl
			       (%push
				 (if (bit-test %arg-desc-evaled-rest arg-desc)
				     (mapcar #'eval1 argl)
				     argl))))
			  (%push (eval1 (car argl))))))
		 (%activate-open-call-block)))))))

(defun eval-lambda (form fctn env)
  (let ((lambda-list (if (memq (car fctn) '(named-lambda named-subst))
			 (caddr fctn)
		         (cadr fctn)))
	(num-args 0)
	args)
    ;; start of our manual list or list*
    (with-stack-list (tem nil)
      (setq args tem))
    (do ((ll lambda-list (cdr ll))
	 (quote-status '&eval)
	 rest-flag)
	((or (null ll)
	     (memq (car ll) '(&aux &key)))
	 (setq num-args (length (cdr form)))
	 (%assure-pdl-room num-args))
      (cond ((memq (car ll) '(&eval &quote))
	     (setq quote-status (car ll)))
	    ((eq (car ll) '&rest)
	     (setq rest-flag t))
	    ((memq (car ll) lambda-list-keywords))
	    (rest-flag
	     ;; Here if we encounter a rest arg.
	     (if ( (length (cdr form))
		    (if (eq quote-status '&quote)
			num-args
			;; stack frames may be moby!
		        200.))
		 ;; If there aren't enough args supplied to actually
		 ;; reach it, arrange to exit via the DO's end-test.
		 (setq ll nil)
	       ;; If the quoted rest arg is non-nil,
	       ;; set NUM-ARGS to number of spread args,
	       ;; and call with ADI.
	       (%assure-pdl-room (1+ num-args))
	       (return)))
	    (t (incf num-args))))
    ;; Now push the args, evalling those that need it.
    (do ((ll lambda-list (cdr ll))
	 (argl (cdr form) (cdr argl))
	 (quote-status '&eval)
	 (argnum 0 (1+ argnum))
	 tem)
	(())
      (do () ((null ll))
	(cond ((memq (car ll) '(&eval &quote))
	       (setq quote-status (car ll)))
	      ((memq (car ll) '(&rest &aux &key))
	       (setq ll nil))
	      ((memq (car ll) lambda-list-keywords))
	      (t (return)))
	(pop ll))
      (cond ((= argnum num-args)
	     ;; Done with spread args => push the rest arg.
	     (with-stack-list (tem1 nil)
	       (setq tem tem1))
	     (cond (argl
		    ;; push on either the quoted rest or the extra parameters beyond the
		    ;; stack-frame-size-limited number above
		    (let ((tem1  (if (eq quote-status '&eval)
				     (mapcar #'eval1 argl)
				     argl)))
		      (if (eq num-args 0)
			  (setq args tem1)
			(%push tem1)
			;; list*-ify to terminate the list of args
			(%p-dpb-offset cdr-normal %%q-cdr-code tem -1)
			(%p-dpb-offset cdr-nil %%q-cdr-code tem -0))))
		   ((eq num-args 0)
		    (setq args ()))
		   (t
		    ;; terminate the list of args
		    (%p-dpb-offset cdr-nil %%q-cdr-code tem -1)))
	     (return))
	    ((eq quote-status '&eval)
	     (%push (eval1 (car argl))))
	    (t
	     (%push (car argl)))))
    (if *applyhook*
	(let ((*evalhook* nil)
	      (*applyhook* nil)
	      (tem *applyhook*))
	  (funcall tem fctn args env))
      (apply-lambda fctn args env))))


(defprop invalid-function t :error-reporter)
(defun invalid-function (form)
  "Report an invalid-function error in FORM and reevaluate with a function the user supplies."
  (eval1 (cons (cerror :new-function nil 'sys:invalid-function
		       (if (symbolp (car form))
			   "The symbol ~S has an invalid function definition"
			   "The object ~S is not a valid function")
		       (car form))
	       (cdr form))
	 t))

;;; Invoke the applyhook on a function which does not have an explicitly passed rest arg.
(defun applyhook1 (env function &rest args)
  (let ((*evalhook* nil)
	(*applyhook* nil)
	(tem *applyhook*))
    (funcall tem function args env)))

;;; Invoke the applyhook for a function with an explicitly passed rest arg.
;;; ARGS* is like the arguments to LIST*.
(defun applyhook2 (env function &rest args*)
  (let ((*evalhook* nil)
	(*applyhook* nil)
	(tem *applyhook*)
	;; list* => list
	(args (if (cdr args*)
		  (let ((tem (last args*)))	;always stack-consed (I hope!!)
		    (%p-dpb-offset cdr-normal %%q-cdr-code tem -1)
		    args*)
		(car args*))))
    (funcall tem function args env)))


;;; compatibility (sigh)
(defun comment (&quote &rest ignore)
  "Ignores all arguments and returns the symbol COMMENT.  It is usually
preferable to comment code using the semicolon-macro feature of the
standard input syntax.  Comments using semicolons are ignored by the
Lisp reader."
  'comment)

(defun declare (&quote &rest declarations)
  "The body is made up of declarations,
which are in effect throughout the construct at the head of whose body the DECLARE appears.

DECLARE is also used at top level to be identical to
/(EVAL-WHEN (COMPILE) ...), but this is obsolete.
Either EVAL-WHEN or PROCLAIM should be used instead."
  declarations
  'declare)

;;; This definition assumes we are evalling.
;;; COMPILE-DRIVER takes care of compiling and loading.
(defun eval-when (&quote times &rest forms)
  "Process the FORMS only at the specified TIMES.
TIMES is a list which may include COMPILE, EVAL or LOAD.
EVAL means to eval the FORMS if the EVAL-WHEN is processed by the interpreter,
 or to compile and eval them when compiling to core.
LOAD means the compiler when compiling to a file should compile the FORMS
 if appropriate and then make them be executed when the QFASL file is loaded.
COMPILE means the compiler should execute the forms
 at compile time.
/(EVAL LOAD) is equivalent to the normal state of affairs."
  (declare (zwei:indentation 1 1))
  (unless (and (cli:listp times)
	       (loop for time in times always (memq time '(eval load compile))))
    (ferror nil "~S is an invalid specifier for ~S;
it should be a list consisting of ~S, ~S, and//or ~S."
	    times 'eval-when 'eval 'load 'compile))
    (when (memq 'eval times)
      (eval-body forms)))

(defun compiler-let (&quote bindlist &rest body)
  "Perform bindings in BINDLIST at evaluation or compilation time.
In interpreted code, this is the same as LET.
When found in code being compiled, the bindings are done at compile time,
and are not done when the compiled code is run."
  (declare (zwei:indentation 1 1))
  (eval1 `(let ,bindlist
;>> should this really happen?
	    (declare (special . ,(mapcar #'(lambda (x) (if (atom x) x (car x))) bindlist)))
	    . ,body)))

(defun the (&quote type value)
  "Returns the value(s) of VALUE, but declares them to be of type(s) TYPE."
  ;; run time type-checking is too much pain...
  (declare (ignore type))
  (eval1 value))

(defun quote (&quote x)
  "(quote X) returns X.  This is useful because X is not evaluated.  This is the same
thing as 'X"
  x)

(defun setq (&quote &rest symbols-and-values)
  "Given alternating variables and value expressions, sets each variable to following value.
Each variable is set before the following variable's new value is evaluated.
See also PSETQ which computes all the new values and then sets all the variables."
  (prog (val)
     l	(cond ((null symbols-and-values) (return val))
	      ((null (cdr symbols-and-values))
	       (ferror nil "Odd number of arguments to ~S" 'setq))
	      ;; checking for setqing defconstants would make life too hard for hacking
	      ((or (memq (car symbols-and-values) '(t nil))
		   (keywordp (car symbols-and-values)))
	       (ferror nil "Setting ~A is not allowed."
		       (if (keywordp (car symbols-and-values))
			   "keywords" (car symbols-and-values)))))
	(if (eq *interpreter-function-environment* t)
	    (set (car symbols-and-values)
		 (setq val (eval1 (cadr symbols-and-values))))
	    (interpreter-set (car symbols-and-values)
			     (setq val (eval1 (cadr symbols-and-values)))))
	(setq symbols-and-values (cddr symbols-and-values))
	(go l)))

(defun variable-boundp (&quote variable)
  "Return T if VARIABLE has a value (is not unbound)."
  (if (eq *interpreter-function-environment* t)
      (boundp variable)
      (interpreter-boundp variable)))

(defun variable-location (&quote variable)
  "Return a locative pointer to the place where the value of VARIABLE is stored."
  (if (eq *interpreter-function-environment* t)
      (%external-value-cell variable)
      (interpreter-external-value-cell variable)))

(defun variable-makunbound (&quote variable)
  "Make the VARIABLE unbound.  References to it will get errors."
  (if (eq *interpreter-function-environment* t)
      (location-makunbound (%external-value-cell variable))
      (location-makunbound (interpreter-external-value-cell variable))))

(defun multiple-value (&quote var-list exp)
  "Evaluate EXP, collecting multiple values, and set the variables in VAR-LIST to them.
Returns the first value of EXP."
  (declare (zwei:indentation 1 1))
  (let ((val-list (multiple-value-list (eval1 exp))))
    (do ((vars var-list (cdr vars))
	 (vals val-list (cdr vals)))
	((null vars))
      (when (car vars)				;allow (multiple-value-setq (nil foo) ...)
	(if (eq *interpreter-function-environment* t)
	    (set (car vars) (car vals))
	    (interpreter-set (car vars) (car vals)))))
    (car val-list)))
(deff multiple-value-setq #'multiple-value)

(defun nth-value (value-number &quote exp)
  "Returns the VALUE-NUMBER'th (0-based) value of EXP.
Compiles into fast code when VALUE-NUMBER is a constant."
  (declare (zwei:indentation 1 1))
  (nth value-number (multiple-value-list (eval1 exp))))

(defun multiple-value-call (function &quote &rest forms)
  "Call FUNCTION like FUNCALL, but use all values returned by each of FORMS.
FUNCALL would use only the first value returned by each of them.
This conses, alas."
  (let ((args (mapcan #'(lambda (form)
			  `(:spread ,(multiple-value-list (eval1 form))))
		      forms)))
    (apply #'call function args)))

(defun multiple-value-list (&quote exp)
  "Evaluate the expression EXP and return a list of the values it returns."
  (multiple-value-list (eval1 exp)))

(defun multiple-value-prog1 (&quote value-form &rest forms)
  "Evaluates VALUE-FORM followed by the FORMs, then returns ALL the values of VALUE-FORM."
  (multiple-value-prog1 (eval1 value-form)
			(mapc #'eval1 forms)))

(defun values (&rest values)
  "Return multiple values -- as many values as we have arguments."
  (values-list values))

(defun values-list (list-of-values)
  "Return multiple values -- each element of our arg is a separate value."
  (values-list list-of-values))

;;; Bind variables, given a list of variables and separate list of (already evaluated) values.
;;; This is needed for MULTIPLE-VALUE-BIND, which appears below.

;;; It does not work to have a CATCH around an invocation of this macro.
;;; It works properly only when compiled to exit to D-RETURN.
;;; Otherwise, it leave the stack screwed up due to the unknown number of %PUSHes executed.

(defmacro bind-variables-spread ((varlist value-list-exp vars-env) &body body)
  `(prog (vars-left bindframe vals-left thisvarloc)
	 ;; Trivial case of empty varlist would lose in code below.
	 (unless ,varlist
	   (go long))
	 (when (nthcdr #o20 ,varlist)
	   (setq bindframe
		 (mapcan #'list*
			 ,varlist ,value-list-exp
			 (circular-list nil)))
	   (go long))
	 ;; The following code is equivalent to the above mapcar
	 ;; except that the list is constructed on the stack
	 ;; by pushing the elements one by one and fiddling with cdr codes.
	 (with-stack-list (tem nil)
	   ;; BINDFRAME gets a pointer to where the list will go.
	   (setq bindframe tem))
	 ;; Now loop over the varlist, computing and pushing initial values.
	 (setq vars-left ,varlist)
	 (setq vals-left ,value-list-exp)
      short-nextvar
	 (unless vars-left (go short-varsdone))
	 (setq thisvarloc (locf (symbol-value (car vars-left))))
	 (%push thisvarloc)
	 (%push (car vals-left))
	 (pop vars-left)
	 (pop vals-left)
	 (go short-nextvar)
      short-varsdone
	 ;; Modify cdr-code of last word pushed, to terminate the list.
	 (with-stack-list (tem nil)
	   (%p-dpb-offset cdr-nil %%q-cdr-code tem -1))
      long
	 ;; Here BINDFRAME has the correct variables and values.
	 ;; Now for each variable that is supposed to be special
	 ;; bind it to its value (as found in BINDFRAME)
	 ;; and forward the BINDFRAME slot to the variable's value cell.

	 (setq vals-left bindframe)
      bindloop
	 (when vals-left
	   (setq thisvarloc (car vals-left))
	   (if (eq thisvarloc (locf (symbol-value 'nil)))
	       ;; allow (multiple-value-bind (foo nil bar) ...)
	       nil
	     (when (interpreter-variable-special-in-frame-p thisvarloc ,vars-env)
	       (%bind thisvarloc
		      (cadr vals-left))
	       (%p-store-data-type (locf (cadr vals-left))
				   dtp-one-q-forward)
	       (%p-store-pointer (locf (cadr vals-left))
				 thisvarloc)))
	   (setq vals-left (cddr vals-left))
	   (go bindloop))
	 (return
	   (with-stack-list* (*interpreter-variable-environment*
			       bindframe *interpreter-variable-environment*)
	     . ,body))))

(defmacro zl-bind-variables-spread ((varlist value-list-exp) &body body)
 `(prog (vars-left vals-left)
	;; Now loop over the varlist, computing and pushing initial values.
        (setq vars-left ,varlist)
	(setq vals-left ,value-list-exp)
     short-nextvar
	(unless vars-left
	  (return (progn . ,body)))
	(if (eq (car vars-left) 'nil)
	    ;; allow (multiple-value-bind (foo nil bar) ...)
	    nil
	  (%bind (locf (symbol-value (car vars-left)))
		 (car vals-left)))
	(pop vars-left)
	(pop vals-left)
	(go short-nextvar)))

(defun multiple-value-bind (&quote var-list exp &rest body)
  "Evaluate EXP, collecting multiple values, and set the variables to them."
  (declare (zwei:indentation 1 3 2 1))
  (let ((val-list (multiple-value-list (eval1 exp))))
    (if (eq *interpreter-function-environment* t)
	(zl-bind-variables-spread (var-list val-list)
	  (eval-body body))
      (gobble-declarations-from-body (vars-env body)
	(bind-variables-spread (var-list val-list vars-env)
	  (eval-body body))))))

;;; Produce code to bind a single variable in a special form.
;;; VARIABLE-EXP should be an expression that computes the variable (a symbol)
;;; and VALUE-EXP should compute the value for the variable (NOT code to compute the value).
(defmacro bind-variable ((variable-exp value-exp form-body) &body body)
 `(if (eq *interpreter-function-environment* t)
      (progn
	(%bind (locf (symbol-value ,variable-exp)) ,value-exp)
	. ,body)
    (gobble-declarations-from-body (vars-env ,form-body)
      (bind-variable-1 (,variable-exp ,value-exp vars-env)
        . ,body))))

(defmacro bind-variable-1 ((variable-exp value-exp vars-env) &body body)
  `(with-stack-list (frame (locf (symbol-value ,variable-exp)) ,value-exp)
     (when (interpreter-variable-special-in-frame-p (car frame) ,vars-env)
       (%bind (car frame)
	      (cadr frame))
       (%p-store-data-type (locf (cadr frame)) dtp-one-q-forward)
       (%p-store-pointer (locf (cadr frame)) (car frame)))
     (with-stack-list* (*interpreter-variable-environment*
			 frame *interpreter-variable-environment*)
       . ,body)))

(defun dont-optimize (&quote &rest body)
  "Prevent all optimization or open coding of the top-level forms of BODY.
Aside from that effect, it is equivalent to PROGN.
/(Note that the arguments to forms in BODY will still be optimized unless
there is another DONT-OPTIMIZE saying not to do that, and so on)"
  (eval-body body))

(defun locally (&quote &rest body)
  "Common Lisp local declaration construct.
LOCALLY is like PROGN except that Common Lisp says that declarations
are allowed only in LOCALLY, not in PROGN, and because PROGN is treated
specially as a top-level form by the compiler."
  (declare (zwei:indentation 0 1))
  (gobble-declarations-from-body (vars body)
    (eval-body body)))

(defun progn (&quote &rest body)
  "Evaluate all the arguments in order and return the value of the last one.
Multiple values are passed along from that argument's evaluation."
  (gobble-declarations-from-body (vars body)
    (eval-body body)))

;;; These functions have hair to implement the correct rules for multiple values

(defun prog2 (ignored value &rest ignored)
  "Return the second argument."
  value)

(defun prog1 (value &rest ignored)
  "Return the first argument."
  value)

(defun with-stack-list (&quote variable-and-elements &rest body)
  "Executes BODY with VARIABLE bound to a temporary list containing ELEMENTS.
In compiled code, the temporary list lives inside the stack, like a &REST argument.
It disappears when the WITH-STACK-LIST is exited.  No garbage is produced.
In interpreted code, this is equivalent to (LET ((VARIABLE (LIST . ELEMENTS))) . BODY)"
  (declare (arglist ((variable . elements) &rest body)))
  (declare (zwei:indentation 1 1))
  (bind-variable ((car variable-and-elements)
		  (mapcar #'eval1 (cdr variable-and-elements))
		  body)
    (eval-body body)))

(defun with-stack-list* (&quote variable-and-elements &rest body)
  "Executes BODY with VARIABLE bound to a temporary list equal to LIST* of ELEMENTS.
When compiled, The temporary list lives inside the stack, like a &REST argument.
It disappears when the WITH-STACK-LIST* is exited.  No garbage is produced.
When interpreted, this is just the same as (LET ((VARIABLE (LIST* . ELEMENTS))) . BODY)"
  (declare (arglist ((variable . elements) &rest body)))
  (declare (zwei:indentation 1 1))
  (bind-variable ((car variable-and-elements)
		  (apply #'list* (mapcar #'eval1 (cdr variable-and-elements)))
		  body)
    (eval-body body)))

(defun and (&quote &rest expressions)
  "Evaluates the EXPRESSIONS until one returns NIL or they are all done.
Returns NIL in the first case; the values of the last expression in the second."
  (if (null expressions) t
    (do ((l expressions (cdr l)))
	((null (cdr l))
	 (eval1 (car l)))
      (or (eval1 (car l))
	  (return nil)))))

(defun or (&quote &rest expressions)
  "Evaluates the EXPRESSIONS until one returns non-NIL or they are all done.
Returns the value of the last expression evaluated.
If all the expressions are evaluated, then all the multiple values of the
last expression are passed along."
  (if (null expressions) nil
    (do ((l expressions (cdr l))
	 (val))
	((null (cdr l))
	 (eval1 (car l)))
      (and (setq val (eval1 (car l)))
	   (return val)))))

(defun cond (&quote &rest clauses)
  "Looks for the first CLAUSE whose predicate is true, and executes that clause.
Each element of the body of a COND is called a CLAUSE.

The first element of each clause is a PREDICATE-EXPRESSION.
This is evaluated to see whether to execute the clause.
If the predicate's value is non-NIL, all the remaining elements of the clause
are executed, as in a PROGN, and the value(s) of the last one are returned by COND.
If the clause contains only one element, the predicate, then
the predicate's value is returned if non-NIL.
In this case, unless it is the last clause, the predicate is not
being called tail-recursively and so only its first value is returned.

If no clause's predicate evaluates non-NIL, the COND returns NIL."
  (do ((clauses clauses (cdr clauses))
       (predval) (expressions))
      ((null clauses) nil)
    (cond ((atom (car clauses))
	   (ferror nil "The atom ~S is not a valid COND clause." (car clauses)))
	  ((and (null (cdr clauses)) (null (cdar clauses)))
	   ;; If this is the last clause, then treat its predicate as part of
	   ;; the body instead of as the predicate, so that multiple values
	   ;; get propagated properly.
	   (setq expressions (car clauses)))
	  ((setq predval (eval1 (caar clauses)))
	   (or (setq expressions (cdar clauses))
	       (return predval)))
	  (t (go nextloop)))
    ;; Predicate true
    (return (eval-body expressions))
   nextloop
    ))

(defun if (&quote test then &rest elses)
  "Execute THEN if TEST comes out non-NIL; otherwise, execute the ELSES."
  (declare (zwei:indentation 2 1))
  (if (eval1 test)
      (eval1 then)
    (eval-body elses)))

;;;; Basic variable binding primitives.

;;; The following two macros implement binding variables according to a LET binding list,
;;; either in parallel or sequentially.

;;; It does not work to have a CATCH (such as ENTER-BLOCK)
;;; around an invocation of these macros.
;;; They work properly only when compiled to exit to D-RETURN.
;;; Otherwise, they leave the stack screwed up due to the unknown number of %PUSHes executed.
;;; (The compiler changes in system 98 will eliminate this problem).

(defmacro parallel-binding-list ((varlist vars-env) &body body)
  `(prog (vars-left bindframe vals-left thisvarloc)
	 ;; Trivial case of empty varlist would lose in code below.
	 (unless ,varlist
	   (go long))
	 (when (nthcdr #o20 ,varlist)
	   (setq bindframe
		 (mapcan #'(lambda (var)
			     (if (consp var)
				 (list* (locf (symbol-value (car var)))
					(eval1 (cadr var)) nil)
			         (list* (locf (symbol-value var)) nil nil)))
			 ,varlist))
	   (go long))
	 ;; The following code is equivalent to the above mapcar
	 ;; except that the list is constructed on the stack
	 ;; by pushing the elements one by one and fiddling with cdr codes.
	 (with-stack-list (tem nil)
	   ;; BINDFRAME gets a pointer to where the list will go.
	   (setq bindframe tem))
	 ;; Now loop over the varlist, computing and pushing initial values.
	 (setq vars-left ,varlist)
      short-nextvar
	 (unless vars-left (go short-varsdone))
	 (setq thisvarloc
	       (locf (symbol-value (if (consp (car vars-left))
				       (caar vars-left) (car vars-left)))))
	 (%push thisvarloc)
	 (%push (if (consp (car vars-left)) (eval1 (cadar vars-left))))
	 (pop vars-left)
	 (go short-nextvar)
      short-varsdone
	 ;; Modify cdr-code of last word pushed, to terminate the list.
	 (with-stack-list (tem nil)
	   (%p-dpb-offset cdr-nil %%q-cdr-code tem -1))
      long
	 ;; Here BINDFRAME has the correct variables and values.
	 ;; Now for each variable that is supposed to be special
	 ;; bind it to its value (as found in BINDFRAME)
	 ;; and forward the BINDFRAME slot to the variable's value cell.

	 (setq vals-left bindframe)
      bindloop
	 (when vals-left
	   (setq thisvarloc (car vals-left))
	   (when (eq thisvarloc (locf (symbol-value 'nil)))
	     (ferror nil "Attempt to bind NIL"))
	   (when (interpreter-variable-special-in-frame-p thisvarloc ,vars-env)
	     (%bind thisvarloc (cadr vals-left))
	     (%p-store-pointer (locf (cadr vals-left))
			       thisvarloc)
	     (%p-store-data-type (locf (cadr vals-left))
				 dtp-one-q-forward))
	   (setq vals-left (cddr vals-left))
	   (go bindloop))

	 (return
	   (with-stack-list* (*interpreter-variable-environment*
			       bindframe *interpreter-variable-environment*)
	     . ,body))))

(defmacro serial-binding-list ((varlist vars-env) &body body)
  `(with-stack-list* (*interpreter-variable-environment*
		       nil *interpreter-variable-environment*)
     (prog (bindframe vars-left vals-left thisvar thisval this-specialp)
	   ;; Trivial case of empty varlist would lose in code below.
	   (unless ,varlist
	     (go trivial))
	   (when (nthcdr #o20 ,varlist)
	     (go long))

	   ;; Here if varlist is less than 16. long.
	   ;; Construct BINDFRAME on the stack
	   ;; by pushing the elements one by one and fiddling with cdr codes.
	   (with-stack-list (tem nil)
	     ;; BINDFRAME gets a pointer to where the list will go.
	     (setq bindframe tem))
	   ;; Now loop over the varlist, computing and pushing initial values.
	   (setq vars-left ,varlist)
	short-nextvar
	   (unless vars-left (go varsdone))
	   (setq thisvar (if (symbolp (car vars-left))
			     (car vars-left) (caar vars-left)))
	   (setq this-specialp (interpreter-variable-special-in-frame-p
				 (locf (symbol-value thisvar)) ,vars-env))
	   (%push (locf (symbol-value thisvar)))
	   (%push (if (consp (car vars-left)) (eval1 (cadar vars-left))))
	   (setf (car *interpreter-variable-environment*) bindframe)
	   ;; Modify cdr-code of last word pushed, to terminate the list.
	   (with-stack-list (tem nil)
	     (%p-dpb-offset cdr-next %%q-cdr-code tem -3)
	     (%p-dpb-offset cdr-nil  %%q-cdr-code tem -1)
	     (setq thisval tem))
	   ;; Bind the variable as special, if appropriate.
	   (unless thisvar (ferror nil "Attempt to bind NIL"))
	   (when this-specialp
	     (%bind (locf (symbol-value thisvar)) (%p-contents-offset thisval -1))
	     (%p-store-data-type (%make-pointer-offset dtp-list thisval -1)
				 dtp-one-q-forward)
	     (%p-store-pointer (%make-pointer-offset dtp-list thisval -1)
			       (locf (symbol-value thisvar))))
	   (pop vars-left)
	   (go short-nextvar)
	long
	   ;; Now loop over the varlist, computing and pushing initial values.
	   (setq bindframe (make-list (* 2 (length ,varlist))))
	   (setf (car *interpreter-variable-environment*) bindframe)
	   (setq vars-left ,varlist)
	   (setq vals-left bindframe)
	long-nextvar
	   (unless vars-left (go varsdone))
	   (setq thisvar (if (symbolp (car vars-left))
			     (car vars-left) (caar vars-left)))
	   (setq this-specialp (interpreter-variable-special-in-frame-p
				 (locf (symbol-value thisvar)) ,vars-env))
	   (setf (car vals-left) (locf (symbol-value thisvar)))
	   (setf (cadr vals-left)
		 (if (consp (car vars-left)) (eval1 (cadar vars-left))))
	   ;; Bind the variable as special, if appropriate.
	   (unless thisvar (ferror nil "Attempt to bind NIL"))
	   (when this-specialp
	     (%bind (locf (symbol-value thisvar)) (cadr vals-left))
	     (%p-store-pointer (locf (cadr vals-left))
			       (locf (symbol-value thisvar)))
	     (%p-store-data-type (locf (cadr vals-left))
				 dtp-one-q-forward))
	   (pop vars-left)
	   (setq vals-left (cddr vals-left))
	   (go long-nextvar)

	varsdone
	trivial
	   (return
	     (progn . ,body)))))

(defmacro zl-serial-binding-list ((varlist) &body body)
  `(prog (vars-left)
	 (setq vars-left ,varlist)
      bindloop
	 (when vars-left
	   (cond ((atom (car vars-left))
		  (and (null (car vars-left)) (ferror nil "Attempt to bind NIL"))
		  (%bind (locf (symbol-value (car vars-left)))
			 nil))
		 (t (and (null (caar vars-left)) (ferror nil "Attempt to bind NIL"))
		    (%bind (locf (symbol-value (caar vars-left)))
			   (eval (cadar vars-left)))))
	   (setq vars-left (cdr vars-left))
	   (go bindloop))
	 
	 (return
	   (progn . ,body))))

(defmacro zl-parallel-binding-list ((varlist) &body body)
  `(prog (vars-left)
	 ;; Now bind all the prog-variables.
	 ;; DO cannot be used, since the scope of the BINDs would be wrong.
	 (setq vars-left ,varlist)
      bindloop
	 (when vars-left
	   ;; For each symbol, push 2 words on stack:
	   ;; value cell location and new value.
	   (cond ((atom (car vars-left))
		  (or (car vars-left) (ferror nil "Attempt to bind NIL"))
		  (%push (locf (symbol-value (car vars-left))))
		  (%push nil))
		 (t (or (caar vars-left) (ferror nil "Attempt to bind NIL"))
		    (%push (locf (symbol-value (caar vars-left))))
		    (%push (eval (cadar vars-left)))))
	   (pop vars-left)
	   (go bindloop))
	 
	 (setq vars-left ,varlist)
      bindloop1
	 (when vars-left
	   ;; Pop off next symbol and value, and bind them.
	   (%bind (%pop) (%pop))
	   ;; Step down VARS-LEFT just so we pop as many pairs as we pushed.
	   (pop vars-left)
	   (go bindloop1))
	 (return (progn . ,body))))

(defun let (&quote varlist &rest body)
  "Binds some variables and then evaluates the BODY.
VARLIST is a list of either variables or lists (variable init-exp).
The init-exps are evaluated, and then the variables are bound.
Then the body is evaluated sequentially and the values
of the last expression in it are returned."
  (declare (zwei:indentation 1 1))
  (if (eq *interpreter-function-environment* t)
      (zl-parallel-binding-list (varlist)
	(eval-body body))
    (gobble-declarations-from-body (vars-env body)
      (parallel-binding-list (varlist vars-env)
	(eval-body body)))))

(defun let* (&quote varlist &rest body)
  "Like LET, but binds each variable before evaluating the initialization for the next.
Thus, each variable's initialization can refer to the values of the previous ones."
  (declare (zwei:indentation 1 1))
  (if (eq *interpreter-function-environment* t)
      (zl-serial-binding-list (varlist)
	(eval-body body))
    (gobble-declarations-from-body (vars-env body)
      (serial-binding-list (varlist vars-env)
	(eval-body body)))))

;;;; Support for lexical function definitions (FLET and LABELS).

;; enclose is nil for labels. macroflag is t for macrolet
(defmacro parallel-function-binding-list ((varlist enclose macroflag) &body body)
  `(prog (vars-left bindframe)
	 ;; Trivial case of empty varlist would lose in code below.
	 (unless ,varlist
	   (go long))  
	 (when (nthcdr #o20 ,varlist)
	   (setq bindframe
		 (mapcan #'(lambda (var)
			     (list* (locf (symbol-function (car var)))
				    ,(cond (macroflag
					    ``(macro . ,(with-stack-list (env *interpreter-function-environment*)
							  (expand-defmacro var env))))
					   (enclose
					    `(interpreter-enclose `(lambda . ,(cdr var))))
					   (t ``(lambda . ,(cdr var))))
				    nil))
			 ,varlist))
	   (go long))
	 ;; The following code is equivalent to the above mapcar
	 ;; except that the list is constructed on the stack
	 ;; by pushing the elements one by one and fiddling with cdr codes.
	 (with-stack-list (tem nil)
	   ;; BINDFRAME gets a pointer to where the list will go.
	   (setq bindframe tem))
	 ;; Now loop over the varlist, computing and pushing initial values.
	 (setq vars-left ,varlist)
      short-nextvar
	 (when vars-left
	   (%push (locf (symbol-function (caar vars-left))))
	   (%push ,(cond (macroflag
			  ``(macro . ,(with-stack-list (env *interpreter-function-environment*)
					(expand-defmacro (car vars-left) env))))
			 (enclose
			  `(interpreter-enclose `(lambda . ,(cdar vars-left))))
			 (t
			  ``(lambda . ,(cdar vars-left)))))
	   (pop vars-left)
	   (go short-nextvar))
	 ;; Modify cdr-code of last word pushed, to terminate the list.
	 (with-stack-list (tem nil)
	   (%p-dpb-offset cdr-nil %%q-cdr-code tem -1))
      long
	 ;; Here BINDFRAME has the correct variables and values.
	 (return
	   (with-stack-list* (*interpreter-function-environment*
			       bindframe *interpreter-function-environment*)
	     . ,body))))

(defmacro zl-parallel-function-binding-list ((varlist ignore macroflag) &body body)
  `(prog (vars-left)
	 ;; Now bind all the prog-variables.
	 ;; DO cannot be used, since the scope of the BINDs would be wrong.
	 (setq vars-left ,varlist)
      bindloop
	 (when vars-left
	   ;; For each symbol, push 2 words on stack:
	   ;; value cell location and new value.
	   (%push (locf (symbol-function (caar vars-left))))
	   (%push ,(if macroflag
		      ``(macro . ,(expand-defmacro (car vars-left) nil))
		      ``(lambda . ,(cdar vars-left))))
	   (pop vars-left)
	   (go bindloop))
	 
	 (setq vars-left ,varlist)
      bindloop1
	 (when vars-left
	   ;; Pop off next symbol and value, and bind them.
	   (%bind (%pop) (%pop))
	   ;; Step down VARS-LEFT just so we pop as many pairs as we pushed.
	   (pop vars-left)
	   (go bindloop1))
	 (return (progn . ,body))))

(defun flet (&quote function-list &rest body)
  "Execute BODY with local function definitions as per FUNCTION-LIST.
Each element of FUNCTION-LIST looks like (NAME (ARGS...) BODY...).
FLET rebinds the function definition of each NAME lexically to
 (LAMBDA (ARGS...) BODY...), closed in the environment outside the FLET.
See also LABELS."
  (declare (zwei:indentation 1 1))
  (if (eq *interpreter-function-environment* t)
      (zl-parallel-function-binding-list (function-list nil nil)
	(eval-body body))
    (gobble-declarations-from-body (vars body)
      (parallel-function-binding-list (function-list t nil)
	(eval-body body)))))

(defun macrolet (&quote macro-list &rest body)
  "Execute BODY with macro function definitions as per MACRO-LIST.
Each element of MACRO-LIST looks like (NAME (ARGS...) BODY...).
MACROLET rebinds the function definition of each NAME lexically to
 a macro like the one you would get by doing
 (DEFMACRO NAME (ARGS...) BODY...)."
  (declare (zwei:indentation 1 1))
  (if (eq *interpreter-function-environment* t)
      (zl-parallel-function-binding-list (macro-list t t)
	(eval-body body))
    (gobble-declarations-from-body (vars body)
      (parallel-function-binding-list (macro-list t t)
	(eval-body body)))))

(defun labels (&quote function-list &rest body)
  "Execute BODY with local function definitions as per FUNCTION-LIST.
Each element of FUNCTION-LIST looks like (NAME (ARGS...) BODY...).
LABELS rebinds the function definition of each NAME lexically to
 (LAMBDA (ARGS...) BODY...), closed in the environment inside the LABELS.
This means that the functions defined by the LABELS can refer to
themselves and to each other.  See also FLET."
  (declare (zwei:indentation 1 1))
  (if (eq *interpreter-function-environment* t)
      (zl-parallel-function-binding-list (function-list nil nil)
	(eval-body body))
    (gobble-declarations-from-body (vars body)
      (parallel-function-binding-list (function-list nil nil)
	;; The values were not evaluated yet.
	;; The binding frame contains the expressions.
	;; Eval them now and store the values in their places.
	(do ((frametail (car *interpreter-function-environment*) (cddr frametail)))
	    ((null frametail))
	  (setf (cadr frametail) (interpreter-enclose (cadr frametail))))
	(eval-body body)))))

(defun progv (vars vals &quote &rest body)
  "Bind the VARS to the VALS and then execute the BODY.
Note that the expressions you write for VARS and VALS
are evaluated on each entry to PROGV,
so the variables bound may be different each time.
The variables are always bound as specials if they are bound;
therefore, strictly speaking only variables declared special should be used."
  (declare (zwei:indentation 2 1))
  (do ((vars vars (cdr vars))
       (vals vals (cdr vals)))
      ((null vars)
       (eval-body body))
    (%bind (locf (symbol-value (car vars))) (car vals))))

;;; (PROGW '((VAR-1 VAL-1) (VAR-2 VAL-2) ... (VAR-N VAL-N)) &BODY BODY)
;;; Binds VAR-I to VAL-I (evaluated) during execution of BODY
(defun progw (vars-and-vals &quote &rest body)
  "Perform bindings from a list of variables and expressions, then execute the BODY.
VARS-AND-VALS is a list of elements like (VARIABLE VALUE-FORM).
The VALUE-FORMs are all evaluated by PROGW, even when compiled.
Note that the value of VARS-AND-VALS is computed each time,
 and always in the global environment.
The variables are always bound as specials if they are bound;
therefore, strictly speaking only variables declared special should be used."
  (declare (zwei:indentation 1 1))
  (do ((vars-and-vals vars-and-vals (cdr vars-and-vals)))
      ((null vars-and-vals)
       (eval-body body))
    (%bind (locf (symbol-value (caar vars-and-vals)))
	   (eval (cadar vars-and-vals)))))

;;; (LET-IF <COND> ((VAR-1 VAL-1) (VAR-2 VAL-2) ... (VAR-N VAL-N)) &BODY BODY)
;;; If <COND> is not nil, binds VAR-I to VAL-I (evaluated) during execution of BODY,
;;; otherwise just evaluates BODY.
(defun let-if (cond &quote var-list &quote &rest body)
  "Perform the bindings in VAR-LIST only if COND is non-NIL; the execute the BODY.
Aside from the presence of COND, LET-IF is just like LET.
The variables are always bound as specials if they are bound;
therefore, strictly speaking only variables declared special should be used."
  (declare (zwei:indentation 2 1))
  (if (not cond)
      (if (eq *interpreter-function-environment* t)
	  (eval-body body)
	(gobble-declarations-from-body (vars-env body)
	  (eval-body body)))
    ;; Cannot use PROGW here; it calls EVAL rather than EVAL1.
    (if (eq *interpreter-function-environment* t)
	(zl-parallel-binding-list (var-list)
	  (eval-body body))
      (gobble-declarations-from-body (vars-env body)
	(parallel-binding-list (var-list vars-env)
	  (eval-body body))))))

(defun letf (&quote places-and-values &rest body)
  "LETF is like LET, except that it it can bind any storage cell
rather than just value cells.
PLACES-AND-VALUES is a list of lists of two elements, the car of each
 of which specifies a location to bind (this should be a form acceptable to LOCF)
 and the cadr the value to which to bind it.
The places are bound in parallel.
Then the body is evaluated sequentially and the values
of the last expression in it are returned.
/(Note that the bindings made by LETF are always /"special/")"
  (declare (zwei:indentation 1 1))
  (prog ((vars-left places-and-values))
     bindloop
   	(when vars-left
	  (%push (with-stack-list ((tem 'locf (caar vars-left)))
		   (eval1 tem)))
	  (%push (eval1 (cadar vars-left)))
	  (pop vars-left)
	  (go bindloop))
	(setq vars-left places-and-values)
     bindloop1
	(when vars-left
	  (%bind (%pop) (%pop))
	  (pop vars-left)
	  (go bindloop1))
	(return (eval-body body))))

(defun letf* (&quote places-and-values &rest body)
  "Like LETF except that binding of PLACES-AND-VALUES is done in series."
  (declare (zwei:indentation 1 1))
  (prog ((vars-left places-and-values))
     bindloop
   	(when vars-left
	  (%bind (with-stack-list ((tem 'locf (caar vars-left)))
		   (eval1 tem))
		 (eval1 (cadar vars-left)))
	  (pop vars-left)
	  (go bindloop))
	(return (eval-body body))))

;;; Interpreter version of UNWIND-PROTECT
;;; (UNWIND-PROTECT risky-stuff forms-to-do-when-unwinding-this-frame...)
;;; If risky-stuff returns, we return what it returns, doing forms-to-do
;;; (just as PROG1 would do).  If risky-stuff does a throw, we let the throw
;;; function as specified, but make sure that forms-to-do get done as well.
(defun unwind-protect (&quote body-form &rest cleanup-forms)
  "Execute BODY-FORM, and on completion or nonlocal exit execute the CLEANUP-FORMS."
  (declare (zwei:indentation 0 3 1 1))
  (unwind-protect (eval1 body-form)
    (dolist (form cleanup-forms)
      (eval1 form))))

(defun throw (tag &quote &rest value-expression)
  "Throw the values of VALUE-EXPRESSION to TAG.
The innermost catch for TAG will return these values to its caller.
 For backwards compatibility, there may be multiple values-expressions:
 (throw 'foo bar baz) is equivalent to (throw 'foo (values bar baz))
 New code should always use the two-argument form."
  (declare (arglist tag &quote value-expression))
  (throw tag
	 (if (or (null value-expression) (cdr value-expression))
	     (values-list (mapcar #'eval1 value-expression))
	     (eval1 (car value-expression)))))
(deff *throw #'throw)

;;;; PROG, GO, RETURN, RETURN-LIST, RETURN-FROM

(defmacro enter-block (name-exp &body body)
  `(with-stack-list (tem ,name-exp nil)
     (with-stack-list (frame 'block tem)
       (with-stack-list* (*interpreter-frame-environment*
			   frame *interpreter-frame-environment*)
	 (catch (cdr tem)
	   (with-stack-list (tem1 nil)
	     (setf (cadr tem) (%make-pointer-offset dtp-locative tem1 -1)))
	   (progn . ,body))))))

(defun block (&quote name &rest body)
  "Make nonlocal exit point named NAME for use with RETURN-FROM within BODY.
BODY is evaluated, and the value(s) of the last form in it are returned,
except that if RETURN-FROM is used with our NAME as its argument
during the execution of BODY, control immediately exits from this BLOCK
with values specified by the arguments to RETURN-FROM.
If NAME is NIL, RETURN can also be used to exit this block."
  (declare (zwei:indentation 1 1))
  (check-type name symbol)
  (enter-block name
    (if (eq *interpreter-function-environment* t)
	(eval-body body)
      (gobble-declarations-from-body (vars body)
	(eval-body body)))))

(defun return-from (&quote blockname &rest vals)
  "Return from a BLOCK named BLOCKNAME, or from a named PROG or DO.
The first arg (not evaluated) is the name.
If that is the only argument, zero values are returned.
With exactly one additional argument, its value(s) are returned.
With more arguments, each argument (except the first) produces
one value to be returned."
  (declare (zwei:indentation 1 1))
  (check-type blockname symbol)
  (let ((values (if (or (null vals) (cdr vals))
		    (mapcar #'eval1 vals)
		    (multiple-value-list (eval1 (car vals))))))
    (do ((tail *interpreter-frame-environment* (cdr tail)))
	((atom tail))
      (let ((bindframe (car tail)))
	(and (eq (car bindframe) 'block)
	     (eq blockname (car (cadr bindframe)))
	     (throw (cdr (cadr bindframe))
		    (values-list values)))))
    (ferror nil "There is no lexically-visible active ~S named ~S." 'block blockname)))

(defun return (&quote &rest vals)
  "Return from a BLOCK named NIL, or from the innermost PROG or DO.
Exactly the same as RETURN-FROM with NIL as first argument.
BLOCKs are candidates for RETURN only if named NIL,
but any PROG or DO is a candidate regardless of its name.
With exactly one argument, its value(s) are returned.
With zero or multiple arguments, each argument produces
one value to be returned."
  (let ((values (cond ((or (null vals) (cdr vals))
		       (mapcar #'eval1 vals))
		      (t (multiple-value-list (eval1 (car vals)))))))
    (do ((tail *interpreter-frame-environment* (cdr tail)))
	((atom tail))
      (let ((bindframe (car tail)))
	(and (eq (car bindframe) 'block)
	     (null (car (cadr bindframe)))
	     (throw (cdr (cadr bindframe))
		    (values-list values)))))
    (ferror nil "There is no lexically-visible active ~S named ~S." 'block nil)))

(defun return-list (values)
  "Return the elements of VALUES from a BLOCK named NIL, or from the innermost PROG or DO.
BLOCKs are candidates for RETURN only if named NIL,
but any PROG or DO is a candidate regardless of its name.
Each element of VALUES becomes a single returned value.
It is preferable to write (RETURN (VALUES-LIST values))."
  (do ((tail *interpreter-frame-environment* (cdr tail)))
      ((atom tail))
    (let ((bindframe (car tail)))
      (and (eq (car bindframe) 'block)
	   (null (car (cadr bindframe)))
	   (throw (cdr (cadr bindframe))
		  (values-list values)))))
  (ferror nil "There is no lexically-visible active ~S named ~S." 'block nil))

(defun tagbody (&quote &rest body)
  "Execute BODY, allowing GO to transfer control to go-tags in BODY.
Lists in BODY are expressions to be evaluated (/"statements/").
Symbols in BODY are tags, which are ignored when reached sequentially.
However, GO may be used within any of the statements
to transfer control to any of the tags in BODY.
After a GO, execution of the TAGBODY form will continue with
the next statement in BODY following the tag.

TAGBODY returns only when execution reaches the end.
Its value is always NIL.  A nonlocal exit of some sort
is the only way to get out with any other value."
  (declare (zwei:indentation zwei::indent-prog))
  (tagbody-internal body))

;;; Execute the body of a TAGBODY (or, a PROG).
;;; Puts a TAGBODY entry on *INTERPRETER-FRAME-ENVIRONMENT* so that GO can find
;;; which tags are available to go to, and where they are in the TAGBODY.
;;; The TAGBODY entry also contains a catch tag that GO can throw to
;;; to do a GO.  The arg thrown is the pointer to the spot in the TAGBODY
;;; where the desired tag appears.
(defun tagbody-internal (body)
  (with-stack-list (tem body nil)
    (with-stack-list (frame 'tagbody tem)
      (with-stack-list* (*interpreter-frame-environment*
			  frame *interpreter-frame-environment*)
	(do ((pc body))
	    (())
	  (cond ((null pc) (return nil))
		((atom pc)
		 (ferror nil "Non-~S atomic cdr in ~S form ~S." 'nil 'tagbody body)
		 (return nil)))
	  (let ((exp (car pc)))
	    (setq pc (cdr pc))
	    (if (atom exp) nil
	      (catch-continuation (cdr (cadr frame))
		  #'(lambda (gotag-pointer) (setq pc (cdr gotag-pointer)))
		  nil
		(with-stack-list (tem1 nil)
		  (setf (cadr tem) (%make-pointer-offset dtp-locative tem1 -1)))
		(eval1 exp)))))))))

(defun go (&quote tag &aux tem)
  "Transfer control to the tag TAG in a lexically containing TAGBODY or PROG, etc.
May be used within TAGBODY, PROG, PROG*, DO, DO*, or anything expanding into them.
TAG is not evaluated.
Control transfers instantaneously; the remainder of this statement
of the TAGBODY or PROG is not completed.
See the documentation of TAGBODY for more info."
  (do ((tail *interpreter-frame-environment* (cdr tail)))
      ((atom tail))
    (let ((bindframe (car tail)))
      (and (eq (car bindframe) 'tagbody)
	   (setq tem (memq tag (car (cadr bindframe))))
	   (throw (cdr (cadr bindframe)) tem))))
  (ferror nil "Unseen ~S tag ~S." 'go tag))

(defun prog (&quote &rest prog-arguments)
  "Old-fashioned form that combines a LET, a BLOCK and a TAGBODY.
Usage is (PROG name varlist body...) or (PROG varlist body...).
A non-NIL symbol is interpreted as a NAME; NIL or a cons is a VARLIST.
These two forms of usage are equivalent to
  (BLOCK name
    (BLOCK NIL
      (LET varlist
        (TAGBODY body...))))
or, in the case with no specified NAME,
  (BLOCK NIL
    (LET varlist
      (TAGBODY body...)))
BLOCK establishes the RETURN-point, LET binds the variables,
and TAGBODY executes the body and handles GO tags.
See the documentation of BLOCK, LET and TAGBODY for more information.
PROG is semi-obsolete, but too ancient to be flushed."
  (declare (arglist /[progname/] varlist &body body))
  (declare (zwei:indentation zwei::indent-prog))
  (let* ((progname (and (atom (car prog-arguments))
			(car prog-arguments)))
	 (varlist (if progname
		      (second prog-arguments)
		      (first prog-arguments)))
	 (progbody (if progname
		       (cddr prog-arguments)
		       (cdr prog-arguments))))
    (check-type progname symbol)
    (prog ()
	  (return
	    (if (eq *interpreter-function-environment* t)
		(enter-block (if (eq progname t) t nil)
		  (enter-block progname
		    (zl-parallel-binding-list (varlist)
		      (tagbody-internal progbody))))
	      (gobble-declarations-from-body (vars-env progbody)
		(parallel-binding-list (varlist vars-env)
		  (enter-block (if (eq progname t) t nil)
		    (enter-block progname
		      (tagbody-internal progbody)
		      (return nil))))))))))

(defun prog* (&quote &rest prog-arguments)
  "Old fashioned form that combines a LET*, a BLOCK and a TAGBODY.
PROG* is the same as PROG except that the variables are bound sequentially,
as in LET*, whereas PROG binds them in parallel, like LET."
  (declare (arglist /[progname/] varlist &body body))
  (declare (zwei:indentation zwei::indent-prog))
  (let* ((progname (and (atom (car prog-arguments))
			(car prog-arguments)))
	 (varlist (if progname
		      (second prog-arguments)
		      (first prog-arguments)))
	 (progbody (if progname
		       (cddr prog-arguments)
		       (cdr prog-arguments))))
    (check-type progname symbol)
    (prog ()
	  (return
	    (if (eq *interpreter-function-environment* t)
		(enter-block (if (eq progname t) t nil)
		  (enter-block progname
		    (zl-serial-binding-list (varlist)
		      (tagbody-internal progbody))))
	      (gobble-declarations-from-body (vars-env progbody)
		(serial-binding-list (varlist vars-env)
		  (enter-block (if (eq progname t) t nil)
		    (enter-block progname
		      (tagbody-internal progbody)
		      (return nil))))))))))

;;;; Various sorts of DOs.

(defun do (&quote &rest x)
  (declare (zwei:indentation 2 1))
  (do-internal x nil))

(defun do-named (&quote name &rest x)
  (declare (zwei:indentation 3 1))
  (enter-block name
    (do-internal x name)))

(defun do-internal (x name &aux varlist endtest retvals oncep)
  (if (and (car x) (atom (car x)))		;"OLD STYLE"
      (let ((body (cddddr x)))
	(bind-variable ((car x) (eval1 (cadr x)) body)
	  (do-body nil nil (cadddr x) nil  t x body)))
    (setq varlist (car x))
    (setq oncep (null (cadr x)))
    (or oncep (setq endtest (caadr x) retvals (cdadr x)))
    (if (eq *interpreter-function-environment* t)
	(zl-parallel-binding-list (varlist)
	  (do-body name oncep endtest retvals nil varlist (cddr x)))
      (gobble-declarations-from-body (vars-env (cddr x))
	(parallel-binding-list (varlist vars-env)
	  (do-body name oncep endtest retvals nil varlist (cddr x)))))))

(defun do* (&quote &rest x)
  (declare (zwei:indentation 2 1))
  (do*-internal x nil))

(defun do*-named (&quote name &rest x)
  (declare (zwei:indentation 3 1))
  (enter-block name
    (do*-internal x name)))

(defun do*-internal (x name &aux varlist endtest retvals oncep)
  (if (and (car x) (atom (car x)))		;"OLD STYLE"
      (let ((body (cddddr x)))
	(bind-variable ((car x) (eval1 (cadr x)) body)
	  (do-body nil nil (cadddr x) nil  t x body)))
    (setq varlist (car x))
    (setq oncep (null (cadr x)))
    (or oncep (setq endtest (caadr x) retvals (cdadr x)))
    (if (eq *interpreter-function-environment* t)
	(zl-serial-binding-list (varlist)
	  (do-body name oncep endtest retvals nil varlist (cddr x) t))
      (gobble-declarations-from-body (vars-env (cddr x))
	(serial-binding-list (varlist vars-env)
	  (do-body name oncep endtest retvals nil varlist (cddr x) t))))))

(defun do-body (name oncep endtest retvals oldp varlist body &optional serial-stepping)
  (enter-block (eq name t)
    (do ()
	((and (not oncep) (eval1 endtest))
	 ;; Now evaluate the exit actions.
	 ;; The last one should return its values out of the DO.
	 (eval-body retvals))
      ;; Now execute the body.
      (tagbody-internal body)
      
      ;; Here after finishing the body to step the DO-variables.
      (and oncep (return nil))
      (cond (oldp (if (eq *interpreter-function-environment* t)
		      (set (car varlist) (eval (caddr varlist)))
		      (interpreter-set (car varlist) (eval1 (caddr varlist)))))
	    (serial-stepping
	     (dolist (elt varlist)
	       (and (consp elt) (cddr elt)
		    (if (eq *interpreter-function-environment* t)
			(set (car elt) (eval (caddr elt)))
		        (interpreter-set (car elt) (eval1 (caddr elt)))))))
	    (t (do ((vl varlist (cdr vl))
		    (vals (do ((vl varlist (cdr vl))
			       (vals nil (cons (and (consp (car vl)) (cdar vl) (cddar vl)
						    (eval1 (caddar vl)))
					       vals)))	;******* CONS *******
			      ((null vl) (nreverse vals)))
			  (cdr vals)))
		   ((null vl))
		 (when (and (consp (car vl)) (cdar vl) (cddar vl))
		   (if (eq *interpreter-function-environment* t)
		       (set (caar vl) (car vals))
		       (interpreter-set (caar vl) (car vals))))))))))

(defun function (&quote function)
  "Quotes FUNCTION for use as a function.
If FUNCTION is a symbol, its function definition in the current environment is returned.
If FUNCTION is a list (presumably starting with LAMBDA or some lambda-macro),
 the compiler will compile it; the interpreter will make it into a closure
 that records the lexical variables of the current lexical context."
  (cond ((symbolp function)
	 (if (eq *interpreter-function-environment* t)
	     (symbol-function function)
	     (interpreter-fsymeval function)))
	((functionp function t)
	 (if (eq *interpreter-function-environment* t)
	     function
	   (interpreter-enclose function)))
	((validate-function-spec function)	;Function spec
	 (fdefinition function))
	(t (ferror nil "~S is neither a function nor the name of a function" function))))

(defun lambda (&quote &rest cruft)
  "Same as (FUNCTION (LAMBDA . CRUFT))
Encloses a lambda-expression in the current environment"
  (declare (zwei:indentation 1 1))
  (interpreter-enclose `(lambda . ,cruft)))

(defun interpreter-enclose (function)
  "Close over FUNCTION in the interpreter's current lexical environment"
  (let ((*interpreter-variable-environment*
	  (unstackify-environment *interpreter-variable-environment*))
	(*interpreter-function-environment*
	  (unstackify-environment *interpreter-function-environment*))
	(*interpreter-frame-environment*
	  (unstackify-environment *interpreter-frame-environment*)))
    (closure '(*interpreter-variable-environment*
		*interpreter-function-environment*
		*interpreter-frame-environment*)
	     function)))

(defun interpreter-environment-closure-p (closure &aux (bindings (closure-bindings closure)))
  "T if CLOSURE is a closure over the interpreter environment variables"
  (or (getf bindings (locf (symbol-value '*interpreter-variable-environment*)))
      (getf bindings (locf (symbol-value '*interpreter-function-environment*)))
      (getf bindings (locf (symbol-value '*interpreter-frame-environment*)))))

;;; Make sure that none of ENV lives in a stack.
;;; Copy any parts that do, forwarding the old parts to the new ones,
;;; and returning a pointer to the new one in case the first link was copied.
;;; NOTE: this function knows specially about frames made by BLOCK or TAGBODY
;;;  and copies them appropriately
(defun unstackify-environment (env &aux (newenv env))
  (when (consp env)
    (when (stack-list-p env)
      (setq newenv (cons (car env) (cdr env)))
      (%p-dpb dtp-one-q-forward %%q-data-type env)
      (%p-dpb newenv %%q-pointer env)
      (%p-dpb dtp-one-q-forward %%q-data-type (1+ (%pointer env)))
      (%p-dpb (1+ (%pointer newenv)) %%q-pointer (1+ (%pointer env)))
    (let* ((frame (car newenv))
	   (newframe frame))
      (when (stack-list-p frame)
	(setq newframe (make-list (length frame)))
	;; Copy each word of the old frame to the new, then
	;; forward each word of the old frame to the new.
	;; Uses %BLT-TYPED to copy in case what's there is a DTP-ONE-Q-FORWARD.
	(do ((l newframe (cdr l))
	     (m frame (cdr m)))
	    ((null l))
	  (%blt-typed m l 1 0)
	  (%p-store-pointer m l)
	  (%p-store-data-type m dtp-one-q-forward))
	(setf (car newenv) newframe)
	;; Special kinds of frames contain additional stack lists
	;; which point at words on the stack which hold catch tags.
	;; Copy the list and stick the in as the catch's tag.
	(when (and (memq (car newframe) '(block tagbody))
		   (stack-list-p (cadr newframe)))
	  (let ((newtem (copylist (cadr newframe))))
	    (setf (cadr newframe) newtem)
	    (setf (car (cadr newtem)) (cdr newtem))))))
    (when (cdr newenv)
      (let ((newrest (unstackify-environment (cdr newenv))))
	(unless (eq (cdr newenv) newrest)
	  (setf (cdr newenv) newrest)))))
    newenv))

(defun stack-list-p (list)
  "T if LIST resides in the stack of the current stack group."
  (and (plusp (%pointer-difference list (sg-regular-pdl current-stack-group)))
       (plusp (%pointer-difference (%stack-frame-pointer) list))))

;;; this is here rather than in sys2; describe to modularize knowledge about interpreter
;;;  internals
(defun describe-interpreter-closure (closure)
  (let ((venv (symeval-in-closure closure '*interpreter-variable-environment*))
	(fnenv (symeval-in-closure closure '*interpreter-function-environment*))
	(frenv (symeval-in-closure closure '*interpreter-frame-environment*))
	(*print-level* *describe-print-level*)
	(*print-length* *describe-print-length*)
	)
    (format t "~%~S is an interpreter closure of ~S~%  Environment is:"
	    closure (closure-function closure))
    (describe-interpreter-environment *standard-output* venv fnenv frenv))
  closure)

;;>> It would be nice to be able to say whether a given environment is stack-consed
;;>> To do this, a stack-group would be passed into this function and thence to stack-list-p
;;>> However, I don't know how to get %stack-frame-pointer out of a different stack group
;;>> sg-ap seems like the right thing, but I'm not counting on it...
(defun describe-interpreter-environment (stream venv fnenv frenv)
  (flet ((frob-bind-frames (env name &aux special-kludge)
	    (when (do ((frames env (cdr frames)))
		      ((atom frames)
		       (format stream "~&  (No ~A)" name)
		       nil)
		    (if (plusp (length frames)) (return t)))
	      (format stream "~&  ~A:" name)
	      (do ((frames env (cdr frames)))
		  ((atom frames))
		(loop for p on (car frames) by 'cddr
		      with kludge = nil
		      as slot-pointer = (locf (cadr p))
		      as slot-dtp = (%p-data-type slot-pointer)
		      as header = (%find-structure-header (car p))
		      do (cond ;; special
			       ((= slot-dtp dtp-one-q-forward)
				;; this is to get around the fact that specials occur in
				;;  in two successive bind-frames. Ugh!
				(unless (memq (car p) special-kludge)
				  (push (car p) kludge)
				  (format stream "~%    ~S:~30T(special)" header)))
			       ;; instance variable or lexical variable
			       (t
				(setq slot-pointer (follow-cell-forwarding slot-pointer t))
				(format stream "~%    ~:[~;Instance var ~]~S:~30T ~:[Void~;~S~]"
					(= slot-dtp dtp-external-value-cell-pointer)
					header
					(location-boundp slot-pointer)
					(and (location-boundp slot-pointer)
					     (contents slot-pointer)))))
		      finally (setq special-kludge kludge))
;		(format stream "~%")
		)))
	  (frob-block-frames (env name type fn)
	    (if (dolist (frame env t)
		  (when (eq (car frame) type) (return nil)))
		(format stream "~&  (No ~A)" name)
	      (format stream "~&  ~A:" name)
	      (dolist (frame env)
		(when (eq (car frame) type) (funcall fn frame))))))
    (if (eq fnenv t)
	(format stream "~& This is a old-dynamic-eval environment: ~
			All bindings and references are special"))
    (if (or (eq venv t)
	    (eq (cdr (last venv)) t))
	(format stream "~& All free variable references are special"))
    (frob-bind-frames venv "Variables")
    (unless (eq fnenv t)
      (frob-bind-frames fnenv "Functions"))
    (frob-block-frames frenv "Tagbodies" 'tagbody
		       #'(lambda (frame)
			   (let ((count (loop for x in (car (cadr frame))
					      count (not (consp x)))))
			     (if (zerop count)
				 (format stream "~%    A ~S with no ~S tags" 'tagbody 'go)
			       (format stream "~%    ~S with tag~P" 'tagbody count)
			       (loop for x in (car (cadr frame))
				     with firstp = t
				     (when (not (consp x))
				       (format stream "~:[,~] ~S" firstp x)
				       (setq firstp nil)))))))
    (frob-block-frames frenv "Blocks" 'block
		       #'(lambda (frame)
			   (format stream "~%    ~S named ~S"
				   'block (car (cadr frame)))))))


(defmacro apply-lambda-bindvar (var value vars-env &optional (specialf nil defaultp))
  `(progn
     (with-stack-list (tem1 nil)
       (setq thisval tem1)
       (if (null (car *interpreter-variable-environment*))
	   ;; start a new frame
	   (setf (car *interpreter-variable-environment*) thisval)
	 ;; nconc onto end of previous frame
	 (%p-dpb-offset cdr-next %%q-cdr-code thisval -1)))
     (%push (locf (symbol-value ,var)))
     (%push ,value)
     ;; Modify cdr-code of last word pushed, to terminate extended frame
     (with-stack-list (tem1 nil)
       (%p-dpb-offset cdr-nil %%q-cdr-code tem1 -1)
       (setq thisval tem1))
     ;; Bind the variable as special, if appropriate.
     (unless ,var (ferror nil "Attempt to bind ~S" 'nil))
     ,(unless (and defaultp (eq specialf 'nil))
	`(when (interpreter-variable-special-in-frame-p
		 (locf (symbol-value ,var)) ,vars-env ,specialf ,defaultp)
	   (%bind (locf (symbol-value ,var)) (%p-contents-offset thisval -1))
	   (%p-store-data-type (%make-pointer-offset dtp-list thisval -1)
			       dtp-one-q-forward)
	   (%p-store-pointer (%make-pointer-offset dtp-list thisval -1)
			     (locf (symbol-value ,var)))))))

(defmacro apply-lambda-bindvar-1 (varloc valloc vars-env)
  `(progn
     (with-stack-list (tem1 nil)
       (setq thisval tem1)
       (if (null (car ,vars-env))
	   ;; start new frame
	   (setf (car ,vars-env) tem1)
	 ;; extend previous frame
	 (%p-dpb-offset cdr-next %%q-cdr-code thisval -1)))
     (%push ,varloc)
     (%push ,valloc)
     ;; Modify cdr-code of last word pushed, to terminate the list.
     ;; Also modify the value, which was pushed as a locative, to be an EVCP.
     (with-stack-list (tem1 nil)
       (%p-dpb-offset dtp-external-value-cell-pointer %%q-data-type tem1 -1)
       (%p-dpb-offset cdr-nil %%q-cdr-code tem1 -1))))

;;; Ucode interpreter trap comes here.
;;; Note will never be called by fexpr-call; instead, the ucode
;;; will pseudo-spread the rest-argument-list by hacking the cdr codes.

;;; The non-special variable .slots.bound.instance.
;;; is bound lexically to the instance (if any)
;;; whose instance variables are lexically bound
;;; in the same environment.

(defun apply-lambda (fctn a-value-list &optional environment &aux tem)
    (block top
      (tagbody
       tail-recurse
	  (cond ((closurep fctn)
		 (setq tem (%make-pointer dtp-list fctn))
		 (setq fctn (car tem))
		 (%using-binding-instances (cdr tem))
		 (go tail-recurse))
		((not (consp fctn))
		 (go bad-function)))
	  (case (car fctn)
	    (curry-after
	     (tagbody
		 (setq tem (cddr fctn))
		 (%open-call-block (cadr fctn) 0 4)
		 (%assure-pdl-room (+ (length tem) (length a-value-list)))
  
	      loop1
		 (or a-value-list (go loop2))
		 (%push (car a-value-list))
		 (and (setq a-value-list (cdr a-value-list))
		      (go loop1))
  
	      loop2
		 (or tem (go done))
		 (%push (eval1 (car tem)))
		 (and (setq tem (cdr tem))
		      (go loop2))
  
	      done
		 (%activate-open-call-block)))
	    (curry-before
	     (tagbody
		 (setq tem (cddr fctn))
		 (%open-call-block (cadr fctn) 0 4)
		 (%assure-pdl-room (+ (length tem) (length a-value-list)))
  
	      loop1
		 (or tem (go loop2))
		 (%push (eval1 (car tem)))
		 (and (setq tem (cdr tem))
		      (go loop1))
  
	      loop2
		 (or a-value-list (go done))
		 (%push (car a-value-list))
		 (and (setq a-value-list (cdr a-value-list))
		      (go loop2))
  
	      done
		 (%activate-open-call-block)))
	    ((lambda named-lambda subst cli:subst named-subst)
	     (let* (optionalf quoteflag tem restf init this-restf specialf
		    (fctn1 (cond ((eq (car fctn) 'named-lambda) (cdr fctn))
				 ((eq (car fctn) 'named-subst) (cdr fctn))
				 (t fctn)))
		    (lambda-list (cadr fctn1))
		    (body (cddr fctn1))
		    (value-list a-value-list)
		    thisval			;Used by expansion of apply-lambda-bindvar
		    keynames keyinits keykeys keyflags
		    keynames1 keykeys1 keyflags1 (unspecified '(()))
		    allow-other-keys
		    thisvar)
	       (and (cdr body) (stringp (car body)) (pop body))	;doc string.

	       ;; Make a binding frame to represent any instance variables
	       (with-stack-list* (vars-env nil *interpreter-variable-environment*)
		 ;; If SELF is an instance, and instance vars aren't bound, bind them.
		 (when (typep self 'instance)
		   (unless (do ((tail (cdr vars-env) (cdr tail)))
			       ((atom tail) nil)
			     (when (setq tem (get-lexical-value-cell
					       (car tail)
					       ;; all this to avoid a compiler warning...
					       (locally
						 (declare (special .slots.bound.instance.))
						 (inhibit-style-warnings
						   (locf (symbol-value
							   '.slots.bound.instance.))))))
			       (return (eq (contents tem) self))))
		     ;;??? Here should take care of special instance variables!!!
		     ;; Probably just omit them, since they were bound when
		     ;; the message was sent, weren't they?
		     (tagbody
			 (setq tem (self-binding-instances))
		      loop
			 (when tem
			   (apply-lambda-bindvar-1 (car tem) (cadr tem) vars-env)
			   (setq tem (cddr tem))
			   (go loop)))
		     ;; now bind .slots.bound.instance. nonspecial
		     (with-stack-list (tem1 nil)
		       (if (null (car vars-env))
			   ;; start new frame
			   (setf (car vars-env) tem1)
			   ;; extend previous frame
			 (%p-dpb-offset cdr-next %%q-cdr-code thisval -1)))
		     (locally
		       (declare (special .slots.bound.instance.))
		       (inhibit-style-warnings
			 (%push (locf (symbol-value '.slots.bound.instance.)))))
		     (%push self)
		     (with-stack-list (tem1 nil)
		       (%p-dpb-offset cdr-nil %%q-cdr-code tem1 -1))))

		 ;; Make a bindframe to represent and SPECIAL or UNSPECIAL declarations
		 (with-stack-list* (vars-env nil vars-env)
		   ;; Find any declarations at the front of the function body
		   ;; and put them onto VARS-ENV ;;(and LOCAL-DECLARATIONS)
		   ;; Note that any declarations will override instance bindings made
		   (gobble-declarations-internal body vars-env)

		   ;; Now this bindframe is the one actually used to bind variables...
		   (with-stack-list* (*interpreter-variable-environment* nil vars-env)
		     (tagbody
		      l
			 (cond ((null value-list) (go lp1))
			       ((or (null lambda-list)
				    (eq (car lambda-list) '&aux)) 
				(cond (restf (go lp1)))
				(return-from top
				  (signal-proceed-case
				    ((args)
				     (make-condition 'sys:too-many-arguments
				       "Function ~S called with too many arguments (~D)."
				       fctn (length a-value-list) a-value-list))
				    (:fewer-arguments
				     (apply fctn (append a-value-list args)))
				    (:return-value args)
				    (:new-argument-list (apply fctn args)))))
			       ((eq (car lambda-list) '&key)
				(go key))
			       ((eq (car lambda-list) '&optional)
				(setq optionalf t)
				(go l1))		;Do next value.
			       ((eq (car lambda-list) '&quote)
				(setq quoteflag t)
				(go l1))
			       ((eq (car lambda-list) '&eval)
				(setq quoteflag nil)
				(go l1))
			       ((memq (car lambda-list) '(&special &local))
				(setq specialf (eq (car lambda-list) '&special))
				(go l1))
			       ((memq (car lambda-list) '(&rest &body))
				(setq this-restf t)
				(go l1))		;Do next value.
			       ((memq (car lambda-list) lambda-list-keywords)
				(go l1))
			       ((atom (car lambda-list))
				(setq thisvar (car lambda-list)))
			       ((atom (caar lambda-list))
				(setq thisvar (caar lambda-list))
				;; If it's &OPTIONAL (FOO NIL FOOP),
				;; bind FOOP to T since FOO was specified.
				(when (and optionalf (cddar lambda-list))
				  (and (null (caddar lambda-list)) (go bad-lambda-list))
				  (apply-lambda-bindvar (caddar lambda-list)
							t vars-env specialf)))
			       (t (go bad-lambda-list)))
			 ;; Get here if there was a real argname in (CAR LAMBDA-LIST).
			 ;;  It is in THISVAR.
			 (and (null thisvar) (go bad-lambda-list))
			 (cond (restf
				;; Something follows a &REST arg???
				(go bad-lambda-list))
			       (this-restf	;This IS the &REST arg.
				;; If quoted arg, and the list of values is in a pdl, copy it.
				(and quoteflag
				     (ldb-test %%pht2-map-access-code
					       (area-region-bits (%area-number value-list)))
				     (let ((default-cons-area background-cons-area))
				       (setq value-list (copy-list value-list))))
				(apply-lambda-bindvar thisvar value-list vars-env specialf)
				;; We don't clear out VALUE-LIST
				;; in case keyword args follow.
				(setq this-restf nil restf t)
				(go l1)))

			 (apply-lambda-bindvar thisvar (car value-list) vars-env specialf)
			 (pop value-list)
		      l1 (pop lambda-list)
			 (go l)

		      key
			 (multiple-value-setq (nil nil lambda-list nil nil
					       keykeys keynames keyinits keyflags
					       allow-other-keys)
			   (decode-keyword-arglist lambda-list t))
			 ;; Process the special keyword :ALLOW-OTHER-KEYS if present as arg.
			 (if (getf value-list ':allow-other-keys)
			     (setq allow-other-keys t))

			 (setq keykeys1 keykeys	;life is tough without LET...
			       keynames1 keynames
			       keyflags1 keyflags)
		      key1
			 (when keykeys1
			   (setq tem (getf value-list (pop keykeys1) unspecified))
			   (setq init (if (eq tem unspecified) (eval1 (car keyinits)) tem))
			   (apply-lambda-bindvar (car keynames1) init vars-env)
			   (if (car keyflags1)
			       (apply-lambda-bindvar (car keyflags1)
						     (neq tem unspecified)
						     vars-env))
			   (pop keynames1)
			   (pop keyflags1)
			   (pop keyinits)
			   (go key1))
			 (do ((x value-list (cddr x))
			      keyword)
			     ((null x))
			   (unless (cdr x)
			     (ferror 'sys:bad-keyword-arglist
				     "No argument after keyword ~S"
				     (car x)))
			   (setq keyword (car x))
			   (setq tem (find-position-in-list keyword keykeys))
			   (unless (or tem allow-other-keys)
			     (do-forever
			       (setq keyword
				     (cerror :new-keyword nil 'sys:undefined-keyword-argument
				       "Keyword arg keyword ~S, with value ~S, is unrecognized."
				       keyword (cadr value-list)))
			       (when (setq tem (find-position-in-list keyword keykeys))
				 (interpreter-set (nth tem keynames) (cadr x))
				 (and (setq tem (nth tem keyflags))
				      (interpreter-set tem t))
				 (return)))))
			 ;; Keyword args always use up all the values that are left...

			 ;; Here when all values used up.
		      lp1
			 (cond ((null lambda-list) (go ex1))
			       ((memq (car lambda-list) '(&rest &body))
				(and restf (go bad-lambda-list))
				(setq this-restf t)
				(go lp2))
			       ((eq (car lambda-list) '&key)
				(go key))
			       ((memq (car lambda-list) '(&optional &aux))
				(setq optionalf t)	;Suppress too few args error
				(go lp2))
			       ((memq (car lambda-list) '(&special &local))
				(setq specialf (eq (car lambda-list) '&special))
				(go lp2))
			       ((memq (car lambda-list) lambda-list-keywords)
				(go lp2))
			       ((and (null optionalf) (null this-restf))
				(and restf (go bad-lambda-list))
				(return-from top
				  (signal-proceed-case
				    ((args)
				     (make-condition 'sys:too-few-arguments
				       "Function ~S called with only ~D argument~1@*~P."
				       fctn (length a-value-list) a-value-list))
				    (:additional-arguments
				     (apply fctn (append a-value-list args)))
				    (:return-value args)
				    (:new-argument-list (apply fctn args)))))
			       ((atom (car lambda-list)) (setq tem (car lambda-list))
							 (setq init nil))
			       ((atom (caar lambda-list))
				(setq tem (caar lambda-list))
				(setq init (eval1 (cadar lambda-list)))
				;; For (FOO NIL FOOP), bind FOOP to NIL since FOO missing.
				(when (cddar lambda-list)
				  (and (null (caddar lambda-list)) (go bad-lambda-list))
				  (apply-lambda-bindvar (caddar lambda-list)
							nil vars-env specialf)))
			       (t (go bad-lambda-list)))
		      lp3
			 (and (null tem) (go bad-lambda-list))
			 (apply-lambda-bindvar tem init vars-env specialf)
			 (and this-restf (setq restf t))
			 (setq this-restf nil)
		      lp2
			 (setq lambda-list (cdr lambda-list))
			 (go lp1)

		      ex1
			 ;; Here to evaluate the body.
			 (return-from top (eval-body body))
		      bad-lambda-list
			 (setq fctn
			       (cerror :new-function nil 'sys:invalid-lambda-list
				       "~S has an invalid lambda list" fctn))
		      retry
			 (return-from top (apply fctn a-value-list))))))))
	    (macro
	     (ferror 'sys:funcall-macro
		     "Funcalling the macro ~S."
		     (function-name (cdr fctn)))
	     (return-from top
	       (eval1 (cons fctn (mapcar #'(lambda (arg) `',arg) a-value-list))))))
  
	  ;; A list, but don't recognize the keyword.  Check for a LAMBDA position macro.
	  (when (lambda-macro-call-p fctn)
	    (setq fctn (lambda-macro-expand fctn))
	    (go retry))
  
     bad-function
	  ;; Can drop through to here for a totally unrecognized function.
	  (setq fctn
		(cerror :new-function nil 'sys:invalid-function
			"~S is an invalid function." fctn))
	  (go retry)
  
	  ;; Errors jump out of the inner PROG to unbind any lambda-vars bound with %BIND.
     bad-lambda-list
	  (setq fctn
		(cerror :new-function nil 'sys:invalid-lambda-list
			"~S has an invalid lambda list" fctn))
     retry
	  (and (consp fctn) (go tail-recurse))
	  (return-from top (apply fctn a-value-list))
  
     too-few-args
	  (return-from top (signal-proceed-case
			     ((args)
			      (make-condition
				'sys:too-few-arguments
				"Function ~S called with only ~D argument~1@*~P."
				fctn (length a-value-list) a-value-list))
			     (:additional-arguments
			      (apply fctn (append a-value-list args)))
			     (:return-value args)
			     (:new-argument-list (apply fctn args))))
  
     too-many-args
	  (return-from top (signal-proceed-case
			     ((args)
			      (make-condition
				'sys:too-many-arguments
				"Function ~S called with too many arguments (~D)."
				fctn (length a-value-list) a-value-list))
			     (:fewer-arguments
			      (apply fctn (append a-value-list args)))
			     (:return-value args)
			     (:new-argument-list (apply fctn args)))))))

;;;; DECODE-KEYWORD-ARGLIST

;;; Given a lambda list, return a decomposition of it and a description
;;; of all the keyword args in it.
;;; POSITIONAL-ARGS is the segment of the front of the arglist before any keyword args.
;;; KEYWORD-ARGS is the segment containing the keyword args.
;;; AUXVARS is the segment containing the aux vars.
;;; REST-ARG is the name of the rest arg, if any, else nil.
;;; POSITIONAL-ARG-NAMES is a list of all positional args
;;;  and the supplied-flags of all optional positional args.
;;; The rest of the values describe the keyword args.
;;; There are several lists, equally long, with one element per arg.
;;; KEYNAMES contains the keyword arg variable names.
;;; KEYKEYS contains the key symbols themselves (in the keyword package).
;;; KEYOPTFS contains T for each optional keyword arg, NIL for each required one.
;;; KEYINITS contains for each arg the init-form, or nil if none.
;;; KEYFLAGS contains for each arg its supplied-flag's name, or nil if none.
;;; Finally,
;;;  ALLOW-OTHER-KEYS is T if &ALLOW-OTHER-KEYS appeared among the keyword args.

;;; POSITIONAL-ARGS, KEYWORD-ARGS, REST-ARG, POSITIONAL-ARG-NAMES, are not computed
;;;  if FOR-APPLY-LAMBDA


(defun decode-keyword-arglist (lambda-list &optional for-apply-lambda)
  (declare (values positional-args keyword-args auxvars
		   rest-arg positional-arg-names
		   keykeys keynames keyinits keyflags allow-other-keys))
  (let (positional-args keyword-args auxvars
	this-rest rest-arg positional-arg-names
	keykeys keynames keyinits keyflags allow-other-keys)
    (setq auxvars (memq '&aux lambda-list))
    (unless for-apply-lambda
      (setq positional-args (ldiff lambda-list auxvars))
      (setq keyword-args (memq '&key positional-args))
      (setq positional-args (ldiff positional-args keyword-args))
      (setq keyword-args (ldiff keyword-args auxvars))
      ;; Get names of all positional args and their supplied-flags.
      ;; Get name of rest arg if any.  Find out whether they end optional.
      (dolist (a positional-args)
	(cond ((eq a '&rest) (setq this-rest t))
	      ((memq a lambda-list-keywords))
	      (t (cond ((symbolp a) (push a positional-arg-names))
		       (t (and (cddr a) (push (caddr a) positional-arg-names))
			  (push (car a) positional-arg-names)))
		 (and this-rest (not rest-arg)
		      (setq rest-arg (car positional-arg-names))))))
      (setq positional-arg-names (nreverse positional-arg-names)))
    ;; Decode the keyword args.  Set up keynames, keyinits, keykeys, keyflags.
    (dolist (a (cdr (memq '&key lambda-list)))
      (cond ((eq a '&aux) (return))
	    ((eq a '&allow-other-keys) (setq allow-other-keys t))
	    ((memq a lambda-list-keywords))
	    (t (let (keyname keyinit keyflag keykey)
		 (if (and (consp a) (consp (car a)))	;((:foo foo) bar)
		     ;; Key symbol specified explicitly.
		     (setq keykey (caar a) keyname (cadar a))
		   ;; Else determine it from the variable name.
		   (setq keyname (if (consp a) (car a) a))	;(foo bar)
		   (unless (setq keykey (get keyname 'keykey))
		     (setq keykey (intern (symbol-name keyname) pkg-keyword-package))
		     (putprop keyname keykey 'keykey)))
		 (if (consp a) (setq keyinit (cadr a) keyflag (caddr a)))
		 (push keyname keynames)
		 (push keyinit keyinits)
		 (push keyflag keyflags)
		 (push keykey keykeys)))))
    ;; Get everything about the keyword args back into forward order.
    (setq keynames (nreverse keynames)
	  keyinits (nreverse keyinits)
	  keykeys (nreverse keykeys)
	  keyflags (nreverse keyflags))
    (values positional-args keyword-args auxvars
	    rest-arg positional-arg-names
	    keykeys keynames keyinits keyflags allow-other-keys)))

