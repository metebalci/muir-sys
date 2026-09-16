;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Lowercase:T; Base:8; Readtable:T -*-

#|
This file implements "encapsulations" of functions.
All symbols referred to in this documentation are in SYSTEM-INTERNALS by default.

An encapsulation is a new function definition put around an old one
to do certain things before and after calling the old definition.
Encapsulations are used for tracing, advising, etc.
An encapsulation is created with the macro ENCAPSULATE.
It is a new definition for the encapsulated function, which
replaces the old one.  It has a debugging-info item looking
like (encapsulated-definition unencapsulated-symbol type).
unencapsulated-symbol is an uninterned symbol whose definition
is the original definition which was replaced.  The encapsulation
also uses that symbol to call the original definition.
The type is a user-chosen name to identify the purpose of this
particular encapsulation.  (Examples: trace, advise).

The encapsulation type symbol should have a encapsulation-grind-function
property which tells grind what to do with one.
See the example for rename-within in this file.

Once an encapsulation is made, it stays around until deliberately flushed,
even if the function is redefined.  The encapsulations are considered
as in addition to the definition, not as part of the definition.

Encapsulations are normally interpreted, but it is ok to compile one.
At least, it is ok with the system.  The subsystem that manipulates
a particular type of encapsulation might be confused.
However, just calling COMPILE compiles only the original definition,
not the encapsulations.

It is possible for one function to be encapsulated more than once.
In this case, the order of encapsulations is independent of the
order in which they were made.  It depends instead on their types.
All possible encapsulation types have a total order and a new
encapsulation is put in the right place in the order.
Here is the order (innermost to outermost).
Any encapsulation type which anybody wants to use must be in this list.
No knowledge of the ordering appears anywhere but in this variable.
|#

(defconst encapsulation-standard-order '(advise breakon trace rename-within)
  "List of allowed encapsulation types, in the order in which encapsulations
are supposed to be kept (innermost encapsulations first).
Initial value is (ADVISE BREAKON TRACE SI:RENAME-WITHIN)")

#|
To find the right place in the ordering to insert a new encapsulation,
it is necessary to parse existing ones.  This is done with the function
UNENCAPSULATE-FUNCTION-SPEC.  It takes a function spec as an argument
and returns another function spec.  It may return the same one.
However, if the arg is defined and its definition is an encapsulation,
then the unencapsulated-symbol is returned.  This process repeats
until a symbol is reached whose definition is not an encapsulation.
A second argument to this function can be used to restrict which
types of encapsulations to pass through.  If the second arg is a list,
then that list says which types to process.  If the second arg is a symbol,
then it should be an encapsulation type, and the types which are processed
are those which are ordered outside of the specified one.  Thus, it takes
you to the level at which an encapsulation of that type is to be found
if there is one, or where a new encapsulation of that type should be created.

Examples: (UNENCAPSULATE-FUNCTION-SPEC FN 'TRACE) returns a function spec.
If there is any trace encapsulation anywhere in fn, then it appears
as the fdefinition of the spec which is returned.  If the fdefinition
of that spec is not a trace encapsulation, then there is none,
and a new one could be created by using ENCAPSULATE on that spec.
 (UNENCAPSULATE-FUNCTION-SPEC (UNENCAPSULATE-FUNCTION-SPEC FN 'TRACE) '(TRACE))
returns whatever is inside any encapsulation of type trace.
Fdefining (UNENCAPSULATE-FUNCTION-SPEC FN 'TRACE) to that would be a way of
getting rid of any such encapsulation.
 (EQ (UNENCAPSULATE-FUNCTION-SPEC FN 'TRACE)
     (UNENCAPSULATE-FUNCTION-SPEC (UNENCAPSULATE-FUNCTION-SPEC FN 'TRACE) '(TRACE)))
is T if an encapsulation of type TRACE exists in FN because one call to u.f.s.
moves up to it, and the other moves past it.

One special kind of encapsulation which is implemented in this file
is the type SI:RENAME-WITHIN.  This encapsulation goes around a definition
in which renamings of functions have been done.
How is this used?
Well, if you define, advise or trace (:WITHIN FOO BAR), then
BAR gets renamed to ALTERED-BAR-WITHIN-FOO wherever it is called from FOO,
and FOO gets a SI:RENAME-WITHIN encapsulation  to record the fact.
This causes GRINDEF to do the right things.
It also causes any changes to the definition of FOO to have
the same old renaming of BAR redone in them, to avoid pardoxical results.
This happens because everyone who inserts any new piece of list structure
inside the definition of FOO or any of its encapsulations always
does (RENAME-WITHIN-NEW-DEFINITION-MAYBE 'FOO NEW-STRUCTURE)
which returns a copy of NEW-STRUCTURE in which any renamings recorded for FOO
have been done.  For example, FSET-CAREFULLY does this.

For the most part, RENAME-WITHIN encapsulations are maintained automatically
by FDEFINE on function specs of the form (:WITHIN ...).  The only time any other code
must be concerned with them is when it changes part of the definition or encapsulations
of a function; then it must call RENAME-WITHIN-NEW-DEFINITION-MAYBE
in the right way.  Perhaps a new interface to FDEFINE can be designed
to make this unnecessary to worry about.

Only FDEFINE et al and GRIND know about encapsulations in any way except
as recomended above.
|#

;;; Two functions for looking at and decoding encapsulations.
;;; UNENCAPSULATE-FUNCTION-SPEC returns the copied symbol whose definition
;;; is the original definition of the symbol supplied as argument.
;;; RENAME-WITHIN-NEW-DEFINITION-MAYBE propagates existing renamings
;;; to some list structure which is to become part of the definition
;;; of a function which has a rename-within encapsulation already.
;;; See below for more information.

;;; Given a function spec, if the definition is traced or advised,
;;; return a function spec (a symbol, actually) for the encapsulated definition.
;;; If the function spec is not defined,
;;; or the outer definition is not an encapsulation,
;;; return the original function spec.

;;; ENCAPSULATION-TYPES is a list of which types of encapsulations to process.
;;; If another type is encountered, its spec is returned.
;;; If a symbol rather than a list is supplied for this arg,
;;; it stands for all types of encapsulations which standardly
;;; come outside the one specified.  Thus, specifying ADVISE
;;; is equivalent to specifying (TRACE RENAME-WITHIN)
;;; and specifying TRACE is equivalent to specifying (RENAME-WITHIN).

;;; To examine the encapsulated definition, do 
;;;   (FDEFINITION (UNENCAPSULATE-FUNCTION-SPEC ...))
;;; To alter that definition while preserving any encapsulation, do
;;;   (FDEFINE (UNENCAPSULATE-FUNCTION-SPEC ...) ...)
;;; Note that FDEFINE with CAREFULLY-FLAG=T does this for you.
(defun unencapsulate-function-spec
       (function-spec &optional encapsulation-types
		      &aux tem)
  "Return the unencapsulated function spec of FUNCTION-SPEC.
This may be FUNCTION-SPEC itself, if it contains no encapsulations
of the sorts we want to remove, or it may be an uninterned symbol
that lives inside the encapsulations removed and contains the
rest of the definition.
ENCAPSULATION-TYPES is a list of the types of encapsulation types
to remove.  The final definition, or any other type of encapsulation,
says where to stop removing them.  ENCAPSULATION-TYPES can also be
a single symbol.  Then all encapsulation types that conventionally
come outside that type are removed, stopping at that type or at
anything which conventionally comes inside that type."
  (prog ()
    ;; If a symbol was specified as the type of encapsulation,
    ;; then process all types which come outside of that type,
    ;; not including that type itself.
    (and encapsulation-types (symbolp encapsulation-types)
	 (or (setq encapsulation-types
		   (cdr (memq encapsulation-types encapsulation-standard-order)))
	     (return function-spec)))
    (multiple-value-bind (defp def)
	(fdefinedp-and-fdefinition function-spec)
      (return
	(cond ((not defp) function-spec)
	      ((and (progn (and (eq (car-safe def) 'macro)
				(setq def (cdr def)))
			   (not (symbolp def)))
		    (setq tem (assq 'encapsulated-definition
				    (function-debugging-info def)))
		    (or (null encapsulation-types)
			(memq (caddr tem) encapsulation-types)))
	       (unencapsulate-function-spec (cadr tem) encapsulation-types))
	      (t function-spec))))))

(defconst compile-encapsulations-flag nil
  "T means compile all advice, tracing, breakons etc. when they are made.")

(defun compile-encapsulations (function-spec &rest encapsulation-types
			       &aux def tem)
  "Compile the encapsulations of FUNCTION-SPEC, or those of the specified types.
The basic definition is not compiled.  Use COMPILE to compile that.
ENCAPSULATION-TYPES may be NIL to compile all encapsulations,
 or a list of types of encapsulations to compile if present.
Standard types include BREAKON, ADVISE, TRACE and SI:RENAME-WITHIN."
  (cond ((not (fdefinedp function-spec)) function-spec)
	((and (setq def (fdefinition function-spec))
	      (setq tem (assq 'encapsulated-definition
			      (function-debugging-info def))))
	 (when (or (null encapsulation-types)
		   (memq (caddr tem) encapsulation-types))
	   (fdefine function-spec (compile-lambda def function-spec)))
	 (compile-encapsulations (cadr tem) encapsulation-types)))
  function-spec)

;; When you alter any part of the definition of a function,
;; if the function has a rename-within encapsulation on it
;; then whatever renamings are recorded in it ought to be performed
;; on the new structure that you are putting into the definition.
;; To do that, use RENAME-WITHIN-NEW-DEFINITION-MAYBE.
;; Supply the function spec (outer, not unencapsulated at all)
;; and the new definition or part of a definition.
;; It returns a copy of the new definition or part with the right renamings done.

(defun rename-within-new-definition-maybe (function definition)
  "Process DEFINITION to become a part of the definition of FUNCTION.
Any renamings that are supposed to be in effect inside FUNCTION
are performed.
FUNCTION should be a function spec which has NOT been unencapsulated at all.
This should be used on anything that will be made part of the definition
of FUNCTION, including pieces of advice, etc."
  (let ((renamings (cadr (rename-within-renamings-slot function)))
	(default-cons-area background-cons-area))
    (dolist (tem renamings)
      (rename-within-replace-function (cadr tem) (car tem)
				      `(:location ,(locf definition)))))
  definition)

(defmacro encapsulate (function-spec outer-function-spec type body
		       &optional extra-debugging-info)
  "Encapsulate the function named FUNCTION-SPEC
with an encapsulation whose body is the value of BODY and whose type is TYPE.
The args are all evaluated, but BODY is evaluated inside some bindings.
OUTER-FUNCTION-SPEC is the function spec the user knows about;
FUNCTION-SPEC itself may be an unencapsulated version of OUTER-FUNCTION-SPEC
so as to cause this encapsulation to go inside other existing ones.

Inside BODY, refer to the variable ENCAPSULATED-FUNCTION to get an object
which you can funcall to invoke the original definition of the function.

FUNCTION-SPEC is redefined with the new encapsulation.
The value returned is the symbol used to hold the original definition.
Within the code which constructs the body, this symbol is the value of COPY."
  `(let* ((default-cons-area background-cons-area)
	  (copy (make-symbol (if (symbolp ,function-spec)
				 (symbol-name ,function-spec)
			       (format nil "~S" ,function-spec))))
	  (defp (fdefinedp ,function-spec))
	  (def (and defp (fdefinition ,function-spec)))
	  (self-flavor-decl (assq ':self-flavor (debugging-info def)))
	  encapsulated-function
	  lambda-list arglist-constructor macro-def)
     ;; Figure out whether we are operating on a macro, and in any case
     ;; compute the lambda list which the encapsulation will use.
     (if defp
	 (setq macro-def (encapsulation-macro-definition def)
	       lambda-list (encapsulation-lambda-list def))
       (setq lambda-list '(&rest .arglist.)))
     (and (symbolp lambda-list)
	  (ferror nil "~S cannot be encapsulated due to hairy arg quoting"
		      ,outer-function-spec))
     (setq arglist-constructor
	   `(encapsulation-list* . ,(cdr (encapsulation-arglist-constructor lambda-list))))
     ;; Copy the original definition, if any, to the copied symbol.
     (and defp (fset copy def))
     ;; Cons up what the body ought to use to call the original definition.
     (setq encapsulated-function (cond (macro-def
					`(encapsulation-macro-definition #',copy))
				       (t `#',copy)))
     (setq def
	   `(named-lambda
	     (,,function-spec (encapsulated-definition ,copy ,,type)
	      ,@(if self-flavor-decl (list self-flavor-decl))
	      . ,,extra-debugging-info)
	     ,lambda-list
	     (encapsulation-let ((arglist ,arglist-constructor))
		(declare (special arglist values))
		,,body)))
     ;; If this encapsulation goes inside rename-withins,
     ;; then do any renamings on it.
     (and (memq 'rename-within (cdr (memq ,type encapsulation-standard-order)))
	  (setq def (rename-within-new-definition-maybe ,outer-function-spec def)))
     (and macro-def (setq def (cons 'macro def)))
     (fdefine ,function-spec def nil t)
     copy))

(defun encapsulation-body (encapsulation)
  "Given a function made using SI:ENCAPSULATION,
return the object supplied by SI:ENCAPSULATION's caller as the body."
  (if (eq (car encapsulation) 'macro)
      (encapsulation-body (cdr encapsulation))
    (cdddr (cadddr encapsulation))))

;;; NOTE!! Each of these must have an optimizer in QCOPT.
(deff encapsulation-let #'let)
(deff encapsulation-list* #'list*)
;; in case #'let or #'let* is redefined (it really has happened to me!! -- Mly)
(add-initialization "Encapsulation technology" '(progn (fset 'encapsulation-let #'let)
						       (fset 'encapsulation-list* #'list*))
		    :cold)

;;; ENCAPSULATION-MACRO-DEFINITION, given a function definition,
;;; if it is a macro, or a symbol whose definition is a symbol whose ... is a macro,
;;; then return the function definition for expanding the macro.
;;; Encapsulations of macros call this function.

;;; ENCAPSULATION-LAMBDA-LIST, given a function definition,
;;; returns a suitable arglist for an encapsulation of that function.

;;; ENCAPSULATION-ARGLIST-CONSTRUCTOR, given such an arglist,
;;; returns an expression which would cons the values of the args
;;; into one list of all the actual arguments to the function.

(defun encapsulation-macro-definition (def)
  "If the function DEF is a macro (directly or indirectly)
then return the function which does the expansion for it.
Otherwise return nil."
  (cond ((consp def)
	 (and (eq (car def) 'macro)
	      (cdr def)))
	((symbolp def)
	 (and (fboundp def) (encapsulation-macro-definition (fdefinition def))))))

(defun encapsulation-lambda-list (function)
  "Return a lambda list good for use in an encapsulation to go around FUNCTION.
The lambda list we return is computed from FUNCTION's arglist."
  (cond ((null function)
	 '(&rest .arglist.))			;If fn is not defined, NIL is supplied to us.
						;Assume a typical function, since can't know.
	((symbolp function)
	 (cond ((fboundp function) (encapsulation-lambda-list (fsymeval function)))
	       (t '(&rest .arglist.))))
	((consp function)
	 (selectq (car function)
	   (lambda (encapsulation-convert-lambda (cadr function)))
	   (named-lambda
	    (encapsulation-convert-lambda (caddr function)))
	   (otherwise '(&rest .arglist.))))
	(t ;A compiled or microcode function
	 (encapsulation-convert-lambda (arglist function t)))))

(defun encapsulation-arglist-constructor (lambda-list &aux restarg optargs sofar)
  "Return an expression which would cons up the list of arguments, from LAMBDA-LIST.
We assume that the expression we return will be evaluated inside a function
whose lambda-list is as specified; the result of the evaluation will be
a list of all the arguments passed to that function."
  (setq restarg (memq '&rest lambda-list))
  (cond (restarg (setq sofar (cadr restarg)
		       lambda-list (ldiff lambda-list restarg))))
  (setq optargs (memq '&optional lambda-list))
  (cond (optargs (setq lambda-list (ldiff lambda-list optargs))
		 (setq optargs (subset-not #'(lambda (elt) (memq elt lambda-list-keywords))
					   optargs))
		 (dolist (a (reverse (cdr optargs)))
		   (setq sofar
			 `(encapsulation-cons-if ,(caddr a) ,(car a) ,sofar)))))
  (setq lambda-list (subset-not #'(lambda (elt) (memq elt lambda-list-keywords)) lambda-list))
  `(list* ,@lambda-list ,sofar))

(defun encapsulation-cons-if (condition new-car tail)
  (if condition (cons new-car tail) tail))

(defun encapsulation-convert-lambda (ll
	&aux evarg quarg evopt quopt evrest qurest)
  ;; First determine what types of evalage and quotage are present (set above aux vars)
  (do ((l ll (cdr l))
       (item)
       (optionalp nil)
       (quotep nil)
       (restp nil))
      ((null l))
    (setq item (car l))
    (cond ((eq item '&aux)
	   (return nil))
	  ((eq item '&eval)
	   (setq quotep nil))
	  ((eq item '&quote)
	   (setq quotep t))
	  ((eq item '&optional)
	   (setq optionalp t))
	  ((or (eq item '&rest) (eq item '&key))
	   (setq restp t))
	  ((memq item lambda-list-keywords))
	  (restp
	   (if quotep (setq qurest t) (setq evrest t))
	   (return nil))
	  (optionalp
	   (if quotep (setq quopt t) (setq evopt t)))
	  (t (cond (quotep (setq quarg t))
		   (t (setq evarg t))))))
  ;; Decide how hairy a lambda list is needed
  (cond ((and (not quarg) (not quopt) (not qurest))
	 '(&eval &rest .arglist.))
	((and (not evarg) (not evopt) (not evrest))
	 '(&quote &rest .arglist.))
	(t;; Need a hairy one.
	  (nreconc
	    (do ((l ll (cdr l))
	         (lambda-list nil)
		 optionalp
	         (item))
	        ((null l) lambda-list)
	      (setq item (car l))
	      (cond ((memq item '(&aux &rest &key))
		     (return lambda-list))
		    ((memq item '(&eval &quote))
		     (setq lambda-list (cons item lambda-list)))
		    ((eq item '&optional)
		     (or optionalp (setq lambda-list (cons item lambda-list)))
		     (setq optionalp t))
		    ((memq item lambda-list-keywords))
		    (optionalp
		     (setq lambda-list (cons (list (gensym) nil (gensym)) lambda-list)))
		    (t
		     (setq lambda-list (cons (gensym) lambda-list)))))
	    '(&rest .arglist.)))))

;;;; Implement RENAME-WITHIN encapsulations.

;;; Rename FUNCTION-TO-RENAME within WITHIN-FUNCTION
;;; and make an entry in WITHIN-FUNCTION's encapsulation to record the act.
;;; The renamed function is defined by a pointer
;;; to the original symbol FUNCTION-TO-RENAME.
;;; Return the renamed function name (a symbol).

(defun rename-within-add (within-function function-to-rename
			  &aux (default-cons-area background-cons-area))
  "Make FUNCTION-TO-RENAME be renamed for calls inside WITHIN-FUNCTION.
A new uninterned symbol will named ALTERED-function-to-rename-WITHIN-within-function
will be created, defined to call FUNCTION-TO-RENAME, and put in
place of FUNCTION-TO-RENAME wherever it is called inside WITHIN-FUCTION.
The uninterned symbol is returned so you can redefine it."
  (rename-within-init within-function)
  (let* ((tem (rename-within-renamings-slot within-function))
	 (new (cadr (assoc-equal function-to-rename (cadr tem)))))
    (unless new
      (setq new (make-symbol (format nil "ALTERED-~S-WITHIN-~S"
					 function-to-rename within-function)))
      (push (list function-to-rename new) (cadr tem))
      (rename-within-replace-function new function-to-rename within-function)
      (fset new function-to-rename))
    new))

(defvar rename-within-functions nil
  "List of functions that have had a rename-within encapsulation made.")

;;; Initialize a rename-within encapsulation on a given function.
;;; This can record that within the function's definition
;;; one or more other functions should be renamed
;;; (that is, be replaced by other names).
;;; The encapsulation contains a debugging info item called RENAMINGS
;;; whose value is an alist of (function-to-rename new-name).
;;; As created by this function, that alist is empty.

(defun rename-within-init (function &aux spec1)
  (setq spec1 (unencapsulate-function-spec function 'rename-within))
  (unless (and (fdefinedp spec1)
	       (rename-within-renamings-slot spec1))
    (push function rename-within-functions)
    (encapsulate spec1 function 'rename-within
		 `(apply ,encapsulated-function arglist)
		 (copy-tree '((renamings nil))))
    (if compile-encapsulations-flag
	(compile-encapsulations spec1 'rename-within)))
  function)

;;; Actually replace the function OLD with the function NEW
;;; throughout the definition of WITHIN.

(defun rename-within-replace-function (new old within &aux tem)
  (prog* ((spec1 (unencapsulate-function-spec (unencapsulate-function-spec within
									   'rename-within)
					      '(rename-within)))
	  (def (fdefinition spec1)))
    (cond ((consp def)
	   (fdefine spec1 (global:subst new old def))
	   (and (eq (car def) 'macro) (pop def))
	   (and (not (symbolp def))
		(setq tem (assq 'encapsulated-definition (function-debugging-info def)))
		(rename-within-replace-function new old (cadr tem))))
	  ((typep def 'compiled-function)
	   (let ((len (%structure-boxed-size def))
		 (%inhibit-read-only t))
	     (dotimes (i len)
	       (let ((dtype (%p-ldb-offset %%q-data-type def i)))
		 (and (= dtype dtp-external-value-cell-pointer)
		      (let ((obj (%p-contents-as-locative-offset def i)))
			(eq obj (locf (fsymeval old))))
		      (%p-dpb-offset (%pointer (locf (fsymeval new))) %%q-pointer
				     def i))))))
	  (t (return nil)))
    (return t)))

;;; Given a function spec of the form (:within within-function renamed-function),
;;; if such a renaming exists, flush it.
(defun rename-within-maybe-delete (function-spec)
  (let ((within-function (cadr function-spec))
	(renamed-function (caddr function-spec)))
    (and (fdefinedp within-function)
	 (let ((entry (assoc-equal renamed-function
				   (cadr (rename-within-renamings-slot within-function)))))
	   (and entry
		(rename-within-delete within-function renamed-function (cadr entry)))))))

;;; Unrename the function ORIGINAL within WITHIN-FUNCTION,
;;; replacing the new name RENAMED-NAME with the ORIGINAL name,
;;; and removing the renamings entry.
(defun rename-within-delete (within-function original renamed-name)
  (let ((renamingsslot (rename-within-renamings-slot within-function)))
    (rename-within-replace-function original renamed-name within-function)
    (setf (cadr renamingsslot)
	  (delq (assq original (cadr renamingsslot)) (cadr renamingsslot)))
    (or (cadr renamingsslot)
	(rename-within-flush within-function))))

;;; Delete the rename-within encapsulation from WITHIN-FUNCTION.
(defun rename-within-flush (within-function &aux def)
  (setq within-function (unencapsulate-function-spec within-function 'rename-within))
  (setq def (fdefinition (unencapsulate-function-spec within-function '(rename-within))))
  (and (eq (car-safe (fdefinition within-function)) 'macro)
       (setq def (cons 'macro def)))
  ;; don't want to use fdefine, as that would record source file name.
  ;;  So we resort to this kludge.
  (setf (contents (fdefinition-location within-function)) def)
  (setq rename-within-functions
	(delq within-function rename-within-functions)))

;;; Given a function which has a rename-within encapsulation,
;;; return the list (:RENAMINGS alist) from the debugging info
;;; which records which renamings are in effect.
;;; Given any other sort of function definition, return nil.
(defun rename-within-renamings-slot (function)
  (let* ((spec1 (unencapsulate-function-spec function 'rename-within))
	 (definition (fdefinition spec1)))
    (and (not (symbolp definition))
	 (cond ((and (consp definition)
		     (eq (car definition) 'macro))
		(and (not (symbolp (cdr definition)))
		     (assq 'renamings (function-debugging-info (cdr definition)))))
	       (t
		(assq 'renamings (function-debugging-info definition)))))))


;;;; Tell the function-spec system about it

(defun (:property rename-within encapsulation-grind-function)
       (function def width real-io untyo-p)
  (declare (ignore def))
  (dolist (entry (cadr (rename-within-renamings-slot function)))
    (grind-1 `(:within ,function ,(car entry)) width real-io untyo-p)))

;;; (:WITHIN within-function renamed-function) refers to renamed-function,
;;;   but only as called directly from within-function.
;;;   Actually, renamed-function is replaced throughout within-function
;;;   by an uninterned symbol whose definition is just renamed-function
;;;   as soon as an attempt is made to do anything to a function spec
;;;   of this form.  The function spec is from then on equivalent
;;;   to that uninterned symbol.
(defprop :within within-function-spec-handler function-spec-handler)
(defun within-function-spec-handler (function function-spec &optional arg1 arg2)
  (let ((within-function (second function-spec))
	(renamed-function (third function-spec)))
    (if (not (and (= (length function-spec) 3)
		  (validate-function-spec within-function)
		  (validate-function-spec renamed-function)
		  (fdefinedp within-function)))
	(unless (eq function 'validate-function-spec)
	  (ferror 'sys:invalid-function-spec
		  "The function spec ~S is invalid." function-spec))
      (case function
	(validate-function-spec t)
	(fdefine (if (eq arg1 renamed-function)
		     (rename-within-maybe-delete function-spec)
		   (fset (rename-within-add within-function renamed-function) arg1)))
	(fdefinition (let* ((def (fdefinition within-function))
			    (renamingsslot (assq 'renamings (debugging-info def)))
			    (entry (cadr (assoc-equal renamed-function (cadr renamingsslot)))))
		       (if entry
			   (symbol-function entry)
			   renamed-function)))
	(fdefinedp t)
	(fdefinition-location
	 (locf (fsymeval (rename-within-add within-function renamed-function))))
	;;--- Removes the renaming rather than renaming it to an undefined function
	(fundefine (rename-within-maybe-delete function-spec))
	(otherwise (function-spec-default-handler function function-spec arg1 arg2))))))
