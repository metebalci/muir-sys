;-*- Mode:LISP; Package:EH; Readtable:ZL; Base:8 -*-

(defmacro defsignal-explicit (signal-name flavor &optional args &body init-options)
  "Define a signal name, which can be used in ERROR, SIGNAL, FERROR, CERROR.
SIGNAL-NAME is the signal name to be defined.
FLAVOR is the flavor of condition object to make,
 or a list (FLAVOR . ADDITIONAL-CONDITION-NAMES), where ADDITIONAL-CONDITION-NAMES
 is a list of condition-names to signal in addition to the flavor components.
 If you specify just a flavor name, the SIGNAL-NAME itself is used
 as the sole additional condition name.
 If you specify a one-element list (FLAVOR), there are no additional
 condition names, and you can optionally use :CONDITION-NAMES as one of
 the INIT-OPTIONS to control them dynamically.
DOCUMENTATION is a documentation string describing what this signal-name is for.
When SIGNAL-NAME is used as the first arg to MAKE-CONDITION, ERROR, SIGNAL, etc.
then you can refer to the remaining args with the arglist ARGS.
The argument names in that list may be used in the INIT-OPTIONS,
which are arguments to pass to MAKE-INSTANCE in addition to the flavor name."
  (declare (arglist signal-name flavor &optional args documentation
		    &body init-options))
  (let ((flavor (if (consp flavor) (car flavor) flavor))
	(documentation (if (stringp (car init-options)) (pop init-options)))
	(condition-names
	  (or (cdr-safe flavor) (list signal-name))))
    `(progn (si:record-source-file-name ',signal-name 'defsignal)
	    ,(if documentation
		 `(setf (documentation ',signal-name 'signal) ,documentation))
	    (defun (:property ,signal-name make-condition-function) (ignore . ,args)
	      ,documentation
	      (declare (function-parent ,signal-name defsignal-explicit))
	      ,(if condition-names
		   `(make-instance ',flavor ,@init-options
				   :condition-names ',condition-names)
		 `(make-instance ',flavor ,@init-options))))))

(deff defsignal-format 'defsignal)

(defmacro defsignal (signal-name flavor args &body init-options)
  "Define a signal name, which can be used in ERROR, SIGNAL, FERROR, CERROR.
SIGNAL-NAME is the signal name to be defined.
FLAVOR is the flavor of condition object to make,
 or a list (FLAVOR . ADDITIONAL-CONDITION-NAMES), where ADDITIONAL-CONDITION-NAMES
 is a list of condition-names to signal in addition to the flavor components.
 If you specify just a flavor name, the SIGNAL-NAME itself is used
 as the sole additional condition name.
DOCUMENTATION is a documentation string describing what this signal-name is for.
When SIGNAL-NAME is used as the first arg to MAKE-CONDITION, ERROR, SIGNAL, etc.
then the remaining arguments are treated as a format string and format arguments.
In addition, the first few (not counting the string) can be given names,
which you specify as the list ARGS.
These names (moved into the keyword package) become messages
that can be sent to the condition object to get the corresponding values.
In addition, the values of the ARGS may be used in the INIT-OPTIONS,
which are additional arguments to pass to MAKE-INSTANCE."
  (declare (arglist signal-name flavor args &optional documentation &body init-options))
  (let ((flavor (if (consp flavor) (car flavor) flavor))
	(documentation (if (stringp (car init-options)) (pop init-options)))
	(condition-names
	  (or (cdr-safe flavor) (list signal-name)))
	(properties (mapcar #'(lambda (sym)
				`',(intern (symbol-name sym) si:pkg-keyword-package))
			    args)))
    `(progn (si:record-source-file-name ',signal-name 'defsignal)
	    ,(if documentation
		 `(setf (documentation ',signal-name 'signal) ,documentation))
	    (defun (:property ,signal-name make-condition-function)
		   (ignore format-string &optional ,@args &rest format-args)
	      ,documentation
	      (declare (function-parent ,signal-name defsignal))
	      (make-instance ',flavor
			     ,@init-options
			     :property-list
			     (list . ,(mapcan 'list properties args))
			     :format-string format-string
			     :format-args
			     (list* ,@args (copy-list format-args))
			     :condition-names ',condition-names)))))

(defun make-condition (signal-name &rest args)
  "Create a condition object using flavor or signal name SIGNAL-NAME.
If SIGNAL-NAME is a signal name defined with DEFSIGNAL or DEFSIGNAL-EXPLICIT,
the ARGS are interpreted according to what was specified in the definition.

If SIGNAL-NAME is a flavor name, the ARGS are init options to pass to MAKE-INSTANCE.

If SIGNAL-NAME is defined neither as a signal name nor as a flavor name,
we create an instance of FERROR with SIGNAL-NAME as an additional condition name."
  (if (typep signal-name 'instance)
      signal-name
    (apply (cond ((get signal-name 'make-condition-function))
		 ((get signal-name 'si:flavor) #'make-instance)
		 (t 'make-condition-default))
	   signal-name args)))

(defun make-condition-default (signal-name format-string &rest args)
  (make-instance 'ferror
		 :condition-names (list signal-name)
		 :format-string format-string
		 :format-args (copy-list args)))

(defvar error-identify-value (list nil)
  "This object is the first instance variable of every error object.
It is a fast way of identifying error objects.")

(defflavor condition ((condition-identify nil)
		      (si:property-list nil)
		      (condition-names nil)
		      (format-string nil)
		      (format-args nil))
	   (si:property-list-mixin si:print-readably-mixin)
  (:initable-instance-variables condition-names format-string format-args)
  (:gettable-instance-variables condition-names format-string format-args)
  :ordered-instance-variables
  (:init-keywords :proceed-types)
  (:default-handler condition-data-plist-lookup)
  (:method-combination (:or :base-flavor-last
			    :default-handler
			    :debugger-command-loop)
		       (:progn :base-flavor-last
			       :initialize-special-commands)
		       (:pass-on (:base-flavor-last proceed-types)
				 :user-proceed-types)
		       (:case :base-flavor-last
			      :proceed
			      :proceed-asking-user
			      :proceed-ucode-with-args
			      :document-proceed-type))
  (:outside-accessible-instance-variables condition-identify))

;Not patched in system 98 - omits AUTOMATIC-ABORT-DEBUGGER-MIXIN
;which has been eliminated from the source.
(defconst not-condition-flavors
	  '(si:vanilla-flavor si:property-list-mixin si:print-readably-mixin
			      no-action-mixin proceed-with-value-mixin)
  "These condition flavors are excluded from the condition names of a condition.")

(defmethod (condition :init) (&rest ignore)
  (let ((tem
	  (subset #'(lambda (symbol) (not (memq symbol not-condition-flavors)))
		  (dont-optimize (si:flavor-depends-on-all (si:instance-flavor self))))))
    (setq condition-names
	  (nunion tem (if (cl:listp condition-names)
			  condition-names (list condition-names))))))

;;; The following four operations must be redefined
;;; because we do handle operations that vanilla-flavor's methods
;;; do not realize that we handle.
(defmethod (condition :which-operations) (&aux accum)
  (do ((l si:property-list (cddr l)))
      ((null l))
    (push (car l) accum))
  (nreconc accum (funcall #'(:method si:vanilla-flavor :which-operations)
			  :which-operations)))

(defmethod (condition :operation-handled-p) (operation)
  (or (si:memq-alternated operation si:property-list)
      (funcall #'(:method si:vanilla-flavor :operation-handled-p)
	       ':operation-handled-p operation)))

(defmethod (condition :get-handler-for) (operation)
  (or (funcall #'(:method si:vanilla-flavor :get-handler-for)
	       ':get-handler-for operation)
      (and (si:memq-alternated operation si:property-list)
	   'condition-data-plist-lookup)))

(defmethod (condition :send-if-handles) (operation &rest args)
  (let ((handler (or (funcall #'(:method si:vanilla-flavor :get-handler-for)
			      ':get-handler-for operation)
		     (and (si:memq-alternated operation si:property-list)
			  'condition-data-plist-lookup))))
    (if handler (apply handler operation args))))

(defmethod (condition :set) (place &rest args)
  (let ((loc (get-location-or-nil place si:property-list)))
    (if loc
	(setf (contents loc) (car (last args)))
      (apply #'si:flavor-unclaimed-message :set place args))))

(defwrapper (condition :report) (ignore . body)
  `(let ((*print-level* error-message-prinlevel)
	 (*print-length* error-message-prinlength))
     ;; If there is an error printing some object,
     ;; Just give up on that object.
     (condition-bind ((error 'condition-report-abort-printing))
       . ,body)))

(defun condition-report-abort-printing (condition)
  (when (memq ':abort-printing (send condition :proceed-types))
    ':abort-printing))

(defmethod (condition :report) (stream)
  (apply #'format stream format-string (send self :format-args)))

(defprop condition-data-plist-lookup t :error-reporter)
;;; This is the default handler for format-string conditions.
;;; Any operation which is the same as the name of a property on the instance's plist
;;; just returns the value of the property.
;;; Anything else is an error, as usual.
(defun condition-data-plist-lookup (operation &rest args)
  (declare (:self-flavor condition))
  (if (si:memq-alternated operation si:property-list)
      (getf si:property-list operation)
    (apply #'si:flavor-unclaimed-message operation args)))

(defprop condition (condition-identify)
	 :dont-print-instance-variables)

(defflavor error ((condition-identify error-identify-value)) (condition))
(defflavor cl:error () (error) :alias-flavor)

(defun errorp (object)
  "T if OBJECT is a condition-object representing an error condition.
This is equivalent to (TYPEP OBJECT 'ERROR) but faster."
  (and (instancep object)
       (location-boundp (locf (condition-condition-identify object)))
       (eq (condition-condition-identify object) error-identify-value)))

(defun condition-typep (condition-instance condition-name)
  "T if CONDITION-NAME is one of the condition names possessed by CONDITION-INSTANCE."
  (condition-typep-1 (send condition-instance :condition-names) condition-name))

(defun condition-typep-1 (names frob)
  (if (atom frob) (memq frob names)
    (case (car frob)
      (and (dolist (c (cdr frob) t)
	     (when (not (condition-typep-1 names c)) (return nil))))
      ((or member) (dolist (c (cdr frob) nil)
		     (when (condition-typep-1 names c) (return t))))
      (not (not (condition-typep-1 names (cadr frob)))))))

(defmethod (condition :around :print-self) (continuation map args stream &rest ignore)
  (if *print-escape*
      (condition-bind ((error 'condition-report-abort-printing))
        (lexpr-funcall-with-mapping-table continuation map args))
    (send self :report stream)))
  
(defmethod (condition :reconstruction-init-plist) ()
  (let (accum)
    (with-self-variables-bound
      (dolist (var (or (get (type-of self) 'keyword-var-alist)
		       (setup-keyword-var-alist (type-of self))))
	;; Mention certain vars only if non-NIL.
	(if (if (memq (cdr var) '(si:property-list format-string format-args))
		(symeval (cdr var))
	      (boundp (cdr var)))
	    (setq accum (list* (car var) (symeval (cdr var)) accum)))))
    accum))

(defun setup-keyword-var-alist (flavor-name)
  (let ((flavor (get flavor-name 'si:flavor))
	accum
	dont-mention)
    (dolist (component (dont-optimize (si:flavor-depends-on-all flavor)))
      (setq dont-mention (si:union-eq (get component ':dont-print-instance-variables)
				      dont-mention)))
    (dolist (var (dont-optimize (si:flavor-all-instance-variables flavor)))
      (or (memq var dont-mention)
	  (push (cons (intern (string var) si:pkg-keyword-package) var)
		accum)))
    (putprop flavor-name accum 'keyword-var-alist)
    accum))

(defmethod (condition :string-for-printing) ()
  (format:output nil (send self :report *standard-output*)))

(defmethod (condition :report-string) ()
  (format:output nil (send self :report *standard-output*)))

(defmethod (condition :print-error-message-prefix) (sg brief stream)
  sg brief
  (princ ">>CONDITION: " stream))

(defmethod (error :print-error-message-prefix) (sg brief stream &aux tem flag)
  (cond ((not (symeval-in-stack-group 'ucode-error-status sg))
	 (princ ">>ERROR: " stream))
	(brief
	 (princ ">>TRAP: " stream))
	(t
	 (let (trap-micro-pc ete saved-micro-pcs)
	   (setf (list* trap-micro-pc ete 'a 'a saved-micro-pcs)
		 (symeval-in-stack-group 'ucode-error-status sg))
	   (format stream ">>TRAP ~A ~A"
		   trap-micro-pc ete)
	   (dolist (pc saved-micro-pcs)
	     (setq tem (assq (1- (%pointer pc)) calls-sub-list))
	     (cond (tem
		    (or flag (format stream " ->"))
		    (setq flag t)
		    (format stream "  ~A " (cdr tem)))))	     
	   (terpri)))))

(defmethod (condition :maybe-clear-input) (stream)
  (send stream :clear-input))

(defmethod (condition :print-error-message) (sg brief stream)
  (send self :print-error-message-prefix sg brief stream)
  (send self :report stream)
  (terpri stream))

;;; Four values, which are used to set ERROR-LOCUS-FRAME, CURRENT-FRAME,
;;; INNERMOST-VISIBLE-FRAME and INNERMOST-FRAME-IS-INTERESTING.
(defmethod (condition :find-current-frame) (sg)
  (let ((innermost-visible-frame (sg-ap sg))
	cf)
    (setq cf innermost-visible-frame)
    (do ((rp (sg-regular-pdl sg)))
	((not (let ((f (function-name (rp-function-word rp cf))))
		(and (symbolp f) (get f ':error-reporter)))))
      (and (eq (function-name (rp-function-word rp cf))
	       'signal-condition)
	   (eq (function-name (rp-function-word rp (sg-next-active sg cf)))
	       'fh-applier)
	   (eq (function-name (rp-function-word rp (sg-previous-nth-active sg cf -2)))
	       'foothold)
	   (return (setq cf (sg-previous-nth-active sg cf -3))))
      (setq cf (sg-next-active sg cf)))
    (values cf (sg-out-to-interesting-active sg cf) innermost-visible-frame)))

(defmethod (condition :debugger-command-loop) (sg &rest ignore)
  (command-loop sg self))

(defmethod (condition :bug-report-recipient-system) ()
  "CADR")					;We leave BUG-LISPM to the slimy world

(defconst default-bug-report-frames 5
  "Default number of frames to include in a bug report backtrace.")

(defmethod (condition :bug-report-description) (stream &optional n-frames)
  (send self :print-error-message error-sg nil stream)
  (format stream "Backtrace from the debugger:")
  (let ((*standard-output* stream)
	total-frames)
    (do ((frame error-locus-frame (sg-next-active error-sg frame))
	 (i 0 (1+ i)))
	((null frame) (setq total-frames i)))
    (do ((frame error-locus-frame (sg-next-active error-sg frame))
	 (i 0 (1+ i)))
	((null frame))
      (cond ((< i (or n-frames default-bug-report-frames))
	     (show-frame-for-bug-message error-sg frame))
	    ((= i (or n-frames default-bug-report-frames))
	     (format t "~%~%Remainder of stack:~%~%")
	     (show-frame-briefly-for-bug-message error-sg frame))
	    ((< i (+ 10. (or n-frames default-bug-report-frames)))
	     (show-frame-briefly-for-bug-message error-sg frame))
	    ((> i (- total-frames 10.))
	     (show-frame-briefly-for-bug-message error-sg frame))
	    ((= i (+ 10. (or n-frames default-bug-report-frames)))
	     (format t "~&..."))))))

(defmethod (condition :debugging-condition-p) () nil)
(defmethod (condition :dangerous-condition-p) () nil)

;;;; Proceeding, or trying to.

(defvar condition-resume-handlers nil
  "List of active RESUME handlers.  A resume handler has a keyword to name it
and also says which conditions it is applicable to.
A condition handler, or the debugger, can say to resume using a specified keyword
and the innermost resume handler for that keyword which is applicable to the
condition being handled will be run.  It is supposed to do a throw.
Elements of this list look like
 (CONDITION-NAMES KEYWORD PREDICATE (FORMAT-STRING FORMAT-ARGS...) HANDLER EXTRA-ARGS...).
CONDITION-NAMES is a condition name or list of such, or NIL.
 This is as for CONDITION-HANDLERS.
KEYWORD is the resume-type.
PREDICATE is called with one argument, the condition,
 and if the result is non-NIL, this handler is active for this condition.
 PREDICATE can be T, meaning handler is always active if CONDITION-NAMES match.
FORMAT-STRING and FORMAT-ARGS are used to print a message saying what
 this resume handler is intended for.
HANDLER is what to do if the debugger actually says to use this resume handler.
EXTRA-ARGS are passed to HANDLER, after the condition object which is its first arg.
Any additional values returned from the condition handler or from
the :PROCEED-ASKING-USER operation (not including the proceed-type)
are also passed to HANDLER, following the EXTRA-ARGS.

An element can also be just T, which means don't look past here when
looking for a resume handler for an unhandled SIGNAL on a non-error condition.")

;This is called by expansions of obsolete versions of CATCH-ERROR-RESTART, etc.
;(defun si:catch-error-restart-1 (&rest ignore) t)

;;; If the user has defined a case of :PROCEED instead of :PROCEED-ASKING-USER,
;;; call it.
(defmethod (condition :proceed-asking-user) (proceed-type continuation read-object-function)
  read-object-function
  (if (send self :proceed :operation-handled-p proceed-type)
      (let ((values (multiple-value-list
		      (send self :proceed proceed-type))))
	(if (car values)
	    ;; If :PROCEED handler returns NIL, don't really proceed.
	    (apply continuation values)))
    (funcall continuation proceed-type)))

;;; If a handler sends a :PROCEED message, do nothing (unless user has defined a :case);
;;; however, if there are no args, call the appropriate :PROCEED-ASKING-USER method if any.
(defmethod (condition :proceed) (&rest args &aux (proceed-type (car args)))
  (if (cdr args)
      (values-list args)
    (if (send self :proceed-asking-user :operation-handled-p proceed-type)
	(send self :proceed-asking-user proceed-type 'values 'read-object)
      proceed-type)))

(defmethod (condition :user-proceed-types) (proceed-types) proceed-types)

(defmethod (condition :document-proceed-type) (proceed-type stream
					       &optional (resume-handlers
							   condition-resume-handlers))
  (let ((string (or (send self :proceed-asking-user :case-documentation proceed-type)
		    (send self :proceed :case-documentation proceed-type))))
    (if string (princ string stream)
      (do ((handler-list resume-handlers (cdr handler-list))
	   (h))
	  ((eq handler-list (cdr handler-list)))
	(setq h (car handler-list))
	(and (consp h)
	     (cond ((null (car h)) t)
		   ((not (consp (car h)))
		    (memq (car h) condition-names))
		   (t (dolist (c (car h))
			(if (memq c condition-names) (return t)))))
	     (eq (cadr h) proceed-type)
	     (or (eq (caddr h) t) (funcall (caddr h) self))
	     (return (apply #'format stream (fourth h))))))))

(defmethod (condition :ucode-proceed-types) () nil)

;;; Make sure we have a combined method for this,
;;; so that the :WHICH-OPERATIONS suboperation works.
(defmethod (condition :special-command) (&rest ignore) nil)

(defmethod (condition :initialize-special-commands) () nil)

(defflavor proceed-with-value-mixin () ()
  (:required-flavors condition))

(defmethod (proceed-with-value-mixin :case :proceed-asking-user :new-value)
	   (continuation read-object-function)
  "Return a value; the value of an expression you type."
  (funcall continuation :new-value
	   (funcall read-object-function :eval-read
		    "Form to evaluate and return: ")))

(defflavor no-action-mixin () () (:required-flavors condition))

(defmethod (no-action-mixin :case :proceed-asking-user :no-action)
	   (continuation ignore)
  "Simply proceed."
  (funcall continuation :no-action))

(defflavor warning () (no-action-mixin condition))

(defmethod (warning :print-error-message-prefix) (ignore ignore stream)
  (princ ">>WARNING: " stream))

;;;; User entries to signaling.

(defprop signal t :error-reporter)
(defun signal (signal-name-or-condition-object &rest args
	       &key (proceed-types nil proceed-types-p) &allow-other-keys)
  "Signal a condition, allowing handlers to proceed with the specified PROCEED-TYPES.
SIGNAL-NAME-OR-CONDITION-OBJECT may be a condition object to be signaled,
or it and ARGS may be args to give to MAKE-CONDITION to create such an object.
Whether ARGS are needed for MAKE-CONDITION or not, they are also searched
for the keyword argument :PROCEED-TYPES, whose value should be a list
of proceed-types the caller offers to handle.  If the arguments for MAKE-CONDITION
for the particular SIGNAL-NAME-OR-CONDITION-OBJECT do not fit with this,
you should call MAKE-CONDITION yourself and pass the result.
If you do not specify the :PROCEED-TYPES argument, a list of all the
proceed-types which the specific flavor of condition can handle is used."
  (let ((condition
	  (if (typep signal-name-or-condition-object 'instance)
	      signal-name-or-condition-object
	    (apply #'make-condition signal-name-or-condition-object args))))
    (signal-condition condition
		      (if proceed-types-p
			  (if (or (consp proceed-types) (null proceed-types))
			      proceed-types
			    (list proceed-types))
			(union (send condition :proceed-asking-user :which-operations)
			       (send condition :proceed :which-operations))))))

(defprop error t :error-reporter)
;;; (ERROR <message> &optional <object> <interrupt>)
;;; is for Maclisp compatibility.  It makes the error message
;;; out of <message> and <object>, and the condition out of <interrupt>'s
;;; CONDITION-NAME property.  The error is proceedable if
;;; <interrupt> is given.
(defun error (signal-name-or-condition-object &rest args)
  "Signal a condition, not providing any way to proceed.
If no handler throws or uses any of the resume handlers,
the debugger is always entered, even if the condition is not an error.
SIGNAL-NAME-OR-CONDITION-OBJECT may be a condition object to be signaled,
or it and ARGS may be args to give to MAKE-CONDITION to create such an object."
  (if (or (stringp signal-name-or-condition-object)
	  (and (symbolp signal-name-or-condition-object)
	       (not (get signal-name-or-condition-object 'si:flavor))
	       (not (get signal-name-or-condition-object 'make-condition-function))))
      (signal-condition (make-condition 'maclisp-error
					signal-name-or-condition-object
					(car args)
					(cadr args))
			(if (get (cadr args) 'condition-name)
			    '(:new-value))
			t)
    (signal-condition (apply #'make-condition signal-name-or-condition-object args)
		      nil t)))

(defflavor multiple-cerror (proceed-alist) (error)
  :inittable-instance-variables
  (:documentation
    "A type of error which just provides a number of simple ways to proceed.
Like common-lisp CERROR with more than one proceed-type.
Usually used in conjunction with the macro MULTIPLE-CERROR"))

(defmethod (multiple-cerror :around :proceed-asking-user)
	   (cont mt args &optional subop arg1 arg2)
  (case subop
    (:which-operations
     (nconc (mapcar #'car proceed-alist)
	    (around-method-continue cont mt args)))
    (:operation-handled-p
     (not (not (or (assq arg1 proceed-alist)
		   (around-method-continue cont mt args)))))
    (:get-handler-for
     ;; Yow! lexical closures!
     (if (assq arg1 proceed-alist)
	 #'(lambda (continuation ignore) (funcall continuation arg1))
       (around-method-continue cont mt args)))
    (:case-documentation
     (let ((tem (assq arg1 proceed-alist)))
       (cond ((not tem)
	      (around-method-continue cont mt args))
	     ((cdr tem))
	     (t "Proceeds."))))			;what else is there say?
    (t
     (if (assq arg1 proceed-alist)
	 (funcall arg2 arg1)
       (around-method-continue cont mt args)))))

(defmacro multiple-cerror (condition-names
			   condition-properties
			   (error-format-string &rest format-args)
			   &body proceed-clauses)
  "Signal an error with condition, passing MAKE-CONDITIONS-ARGS to MAKE-CONDITION
ERROR-FORMAT-STRING and FORMAT-ARGS give a message to be printed describing the error.
PROCEED-CLAUSES are a list of different ways of proceeding from the error which will
 be offered to the user. Each is of the form (documentation-string statments ...)
 where documentation-string describes what proceeding the error in this way will do.
The values of the last statement in the clause whih is used to proceed are returned."
  (let (proceed-alist
	clauses)
    (dolist (c proceed-clauses)
      (let ((gensym (gensym)))
	(push `(cons ',gensym ,(car c)) proceed-alist)
	(push (cons gensym (cdr c)) clauses)))
    (setq clauses (nreverse clauses))
    `(signal-proceed-case (()
			   'multiple-cerror
			   :condition-names ,condition-names
			   :format-string ,error-format-string
			   :format-args (list . ,format-args)
			   :proceed-alist (list . ,proceed-alist)
			   :property-list (list . ,condition-properties))
       . ,clauses)))

;(defflavor common-lisp-cerror () (ferror))

;(defmethod (common-lisp-cerror :report) (stream)
;  (apply #'format stream format-string (send self :format-args)))

;(defmethod (common-lisp-cerror :case :proceed-asking-user :continue)
;	   (continuation ignore)
;  (funcall continuation :continue))

;(defmethod (common-lisp-cerror :case :document-proceed-type :continue)
;	   (stream &optional ignore)
;  (apply #'format stream (send self :continue-format-string) format-args))
  
(defprop cerror t :error-reporter)
(defun cerror (proceedable-flag unused &optional signal-name format-string &rest args)
  "Report a simple correctable error, using FORMAT and ARGS to print the message.
SIGNAL-NAME is a signal name or condition flavor name to be signalled,
or else a condition name to include in the signal, or NIL for none in particular.
 Actually, FORMAT-STRING and ARGS are just passed along to MAKE-CONDITION
 and SIGNAL-NAME controls how they are interpreted there.
PROCEEDABLE-FLAG = :YES means allow proceed-type :NO-ACTION,
 which returns NIL from CERROR.
PROCEEDABLE-FLAG = T means allow proceed-type :NEW-VALUE,
 and the value is returned from CERROR.
Any other non-NIL value for PROCEEDABLE-FLAG is either a proceed-type
 or a list of proceed-types.

For common-lisp compatibility, PROCEEDABLE-FLAG is a string describing the action to be
taken if the error is proceeded, UNUSED is a format string describing the error, and
the other arguments are used as other arguments to FORMAT.
In this case, NIL is always returned."
  (if (stringp proceedable-flag)
      ;; common-lisp cerror
      (with-stack-list* (format-args signal-name format-string args)
	(multiple-cerror 'common-lisp-cerror ()	;for compatabilty with manual.
			 ("~1{~:}" unused format-args)
	  ((apply #'format nil proceedable-flag format-args) nil)))	;returns nil
    (nth-value 1 (signal-condition
		   (apply #'make-condition signal-name format-string args)
		   (case proceedable-flag
		     ((t) '(:new-value))
		     ((nil) nil)
		     (:yes '(:no-action))
		     (t (if (atom proceedable-flag)
			    (list proceedable-flag) proceedable-flag)))))))

(defprop fsignal t :error-reporter)
(defun fsignal (format-string &rest args)
  (signal-condition (apply #'make-condition nil format-string args)
		    '(:no-action)))

(defprop cl:error t :error-reporter)
(deff cl:error 'ferror)

(defprop ferror t :error-reporter)
(defun ferror (signal-name &optional format-string &rest args)
  "Report an uncorrectable error, using FORMAT-STRING and ARGS to print the message.
SIGNAL-NAME is a signal name or condition flavor name to be signalled,
or else a condition name to include in the signal, or NIL for none in particular."
  (signal-condition
    (if (stringp signal-name)
	;; Symbolics calling sequence has no condition; 1st arg is really the format string.
	(funcall #'make-condition 'ferror :format-string signal-name
		 			  :format-args (cons format-string args))
      (apply #'make-condition signal-name format-string args))
    nil t))

(defun (:property maclisp-error make-condition-function) (ignore message object interrupt)
  (make-instance 'ferror
		 :format-string (if object "~S ~A" "~*~A")
		 :format-args (list object message)
		 :condition-names (list (get interrupt 'condition-name))))

(defflavor ferror ()
	   (proceed-with-value-mixin no-action-mixin error))


(defvar eh-ready nil
  "NIL until call to first level error handler after it has been preset.
Normal error processing has no chance until this is set")

(defconst *break-on-warnings* nil
  "Non-NIL means CL:WARN calls BREAK rather than just printing a message.")

(defun warn (format-string &rest args)
  "Use FORMAT to print a message on *ERROR-OUTPUT*.
If *BREAK-ON-WARNINGS* is non-NIL, call BREAK instead."
  (if *break-on-warnings*
      (apply #'break format-string args)
    (apply #'format *error-output* format-string args)))

;;;; Lower levels of signaling.

(defvar condition-handlers nil
  "List of active condition handlers.  Each element is (CONDITION-NAMES FUNCTION).
CONDITION-NAMES is either a condition name, a list of names, or NIL for all conditions.")

(defvar condition-default-handlers nil
  "List of active default condition handlers.  Each element is (CONDITION-NAMES FUNCTION).
CONDITION-NAMES is either a condition name, a list of names, or NIL for all conditions.
The handlers on this list are tried after all of CONDITION-HANDLERS.")

(defun invoke-handlers (condition condition-names &aux values)
  (do ((handler-list condition-handlers (cdr handler-list))
       (h))
      ((null handler-list) nil)
    (setq h (car handler-list))
    (when (cond ((null (car h)) t)
		((not (consp (car h)))
		 (memq (car h) condition-names))
		(t (dolist (c (car h))
		     (if (memq c condition-names) (return t)))))
      (setq values
	    (multiple-value-list
	      (let ((condition-handlers (cdr handler-list)))
		(apply (cadr h) condition (cddr h)))))
      (if (car values) (return-from invoke-handlers values))))
  (do ((handler-list condition-default-handlers (cdr handler-list))
       (h))
      ((null handler-list) nil)
    (setq h (car handler-list))
    (when (cond ((null (car h)) t)
		((not (consp (car h)))
		 (memq (car h) condition-names))
		(t (dolist (c (car h))
		     (if (memq c condition-names) (return t)))))
      (setq values
	    (multiple-value-list
	      (let ((condition-default-handlers (cdr handler-list)))
		(apply (cadr h) condition (cddr h)))))
      (if (car values) (return-from invoke-handlers values))))
  nil)

(defun condition-name-handled-p (condition-name)
  "Non-NIL if there is a handler that might handle CONDITION-NAME.
Use this to avoid signaling a condition that will not be handled;
this can often save a lot of time."
  (or (dolist (h condition-handlers)
	(if (cond ((null (car h)) t)
		  ((symbolp (car h))
		   (eq (car h) condition-name))
		  (t (memq condition-name (car h))))
	    (return (if (eq (cadr h) 'si::condition-case-throw) t 'maybe))))
      (dolist (h condition-default-handlers)
	(if (cond ((null (car h)) t)
		  ((symbolp (car h))
		   (eq (car h) condition-name))
		  (t (memq condition-name (car h))))
	    (return (if (eq (cadr h) 'si::condition-case-throw) t 'maybe))))
      (dolist (h condition-resume-handlers)
	(if (cond ((eq h t))
		  ((null (car h)) t)
		  ((symbolp (car h))
		   (eq (car h) condition-name))
		  (t (memq condition-name (car h))))
	    (return t)))))

;;; This saves each CONDITION-CASE from having to make a new function.
(defun condition-throw (condition tag)
  (throw tag condition))

(defvar condition-proceed-types :unbound
  "List of proceed types specified in call to SIGNAL.
This is an argument to the function SIGNAL, saved for use by condition handlers.")

(defvar ucode-error-status :unbound
  "Inside SIGNAL-CONDITION, contains info on where in the microcode the error happened.
If the error did not come from microcode, it is NIL.
Otherwise, it is a list (TRAP-MICRO-PC ETE SG-AP SG-IPMARK . MICRO-STACK-PCs).")

(defvar trace-conditions nil
  "List of condition names whose signaling should be traced, or T for all.")

(defprop signal-condition t :error-reporter)
(defun signal-condition (condition &optional condition-proceed-types
			 (use-debugger (errorp condition)) ucode-error-status
			 inhibit-resume-handlers
			 &aux tem1)
  "Signal CONDITION, running handlers, possibly enter debugger, possibly resume or proceed.
CONDITION-PROCEED-TYPES are the proceed-types the caller offers to handle.
 The value of the free variable CONDITION-RESUME-HANDLERS may provide
 additional proceed-types.
First, look for a handler or default handler that will handle CONDITION.
If none does, and USE-DEBUGGER is non-NIL, invoke the debugger.
 (USE-DEBUGGER's default is (ERRORP CONDITION)).
If either a handler or the debugger decided to proceed, then:
 if the proceed-type is in CONDITION-PROCEED-TYPES, just return
 the proceed-type and associated arguments as multiple values.
 Otherwise, look on CONDITION-RESUME-HANDLERS for a resume handler
 for the specified proceed-type.
If the condition is not an error, and no handler handled it,
 then if the first available proceed type is nonlocal,
 proceed using it.  Otherwise, return NIL.

If INHIBIT-RESUME-HANDLERS is non-NIL, resume handlers are not run.
Any attempt to proceed simply returns to SIGNAL-CONDITION's caller.

UCODE-ERROR-STATUS is non-NIL only when this function is called
 as a result of an error detected in the microcode; it is of interest
 only to routines of conditions that the microcode can signal."
  (let ((condition-names (send condition :condition-names))
	(debugger-called nil))
    (and trace-conditions
	 (or (eq trace-conditions t)
	     (dolist (c condition-names)
	       (if (if (symbolp trace-conditions)
		       (eq c trace-conditions)
		     (memq c trace-conditions))
		   (return t))))
	 (let (trace-conditions errset-status condition-handlers condition-default-handlers)
	   (cerror :no-action nil nil "A traced condition was signaled:~%~A" condition)))
    (when condition-names
      (setq tem1
	    (invoke-handlers condition condition-names)))
    (unless (car tem1)
      (when (and errset-status
		 (not errset)
		 (errorp condition)
		 (not (send condition :dangerous-condition-p))
		 (not (send condition :debugging-condition-p)))
	(if errset-print-msg
	    ;; Note: MUST be "brief", since some methods will lose
	    ;; if executed in this stack group and not brief.
	    (send condition :print-error-message current-stack-group t *standard-output*))
	(throw 'errset-catch nil))
      (if (or use-debugger ucode-error-status)
	  (setq debugger-called t
		tem1 (let ((error-depth (1+ error-depth)))
		       (invoke-debugger condition)))))
    (cond ((memq (car tem1) condition-proceed-types)
	   (values-list tem1))
	  (inhibit-resume-handlers (values-list tem1))
	  ((or tem1 (null condition-proceed-types))
	   ;; If debugger is invoking a resume handler,
	   ;; turn off trap-on-exit for frames out to there.
	   (when debugger-called
	     (debugger-prepare-for-resume-handler condition (car tem1)))
	   (apply #'invoke-resume-handler condition tem1)))))

(defun debugger-prepare-for-resume-handler (condition proceed-type)
  (let* ((rh (find-resume-handler condition proceed-type))
	 (to-frame
	   (sg-resume-handler-frame current-stack-group rh)))
    (when to-frame
      ;; It should never be NIL, but there can be bugs.
      (do ((frame (sg-next-active current-stack-group
				  ;; Note we don't clear the bit for THIS frame.
				  (%pointer-difference
				    (%stack-frame-pointer)
				    (aloc (sg-regular-pdl current-stack-group) 0)))
		  (sg-next-active current-stack-group frame)))
	  ((= frame to-frame))
	(setf (rp-trap-on-exit (sg-regular-pdl current-stack-group) frame) 0)))))

(defprop invoke-debugger t :error-reporter)
;;; This function's frame is returned from directly by ordinary proceeding.
;;; Therefore, it must not do anything after calling the other stack group.
(defun invoke-debugger (condition)
  "Enter the debugger for condition-object CONDITION.
If the debugger proceeds, returns a list of the values being proceeded with
/(so the CAR is the proceed-type).
Bind ERROR-DEPTH to one plus its current value before calling this."
  ;; It used to bind ERROR-DEPTH here, but I suspect that
  ;; binding specials in this function is unwise.
  (if (trapping-enabled-p)
      (funcall %error-handler-stack-group condition)
    ;; The above FUNCALL can screw up if the stack group exists
    ;; but is not initialized yet.
    (break "Attempting to invoke debugger for~%~A" condition))
  nil)

(defun invoke-restart-handlers (condition &key flavors)
  "For compatibility with Symbolics software only."
  (invoke-resume-handler (or condition
			     (and flavors
				  (make-instance 'condition :condition-names flavors)))))

(defprop invoke-resume-handler t :error-reporter)
(defun invoke-resume-handler (condition &optional proceed-type &rest args)
  "Invoke a resume handler for PROCEED-TYPE on CONDITION.
Recall that each resume handler is identified by a proceed-type
and has a list of condition-names it applies to, and a predicate to actually decide.
We run the innermost resume handler for the specified PROCEED-TYPE
which applies to CONDITION, based on CONDITION's condition names
and on applying the predicate to it.
If PROCEED-TYPE is NIL, the innermost resume handler that applies
is used regardless of its proceed type; however, in this case,
a T in the list CONDITION-RESUME-HANDLERS terminates the scan."
  (let ((h (find-resume-handler condition proceed-type)))
    (when h
      (call (fifth h) nil condition :spread (nthcdr 5 h) :spread args)
      (ferror nil "A condition resume handler for proceed-type ~S returned to its caller." proceed-type)))
  (and proceed-type
       (ferror nil "Invalid proceed-type ~S returned by handler for ~S."
	       proceed-type condition)))

(defun find-resume-handler (condition &optional proceed-type
			    (resume-handlers condition-resume-handlers)
			    &aux (condition-names
				   (and condition (send condition :condition-names))))
  "Return the resume handler that would be run for PROCEED-TYPE on CONDITION.
This is how INVOKE-RESUME-HANDLER finds the handler to run.
RESUME-HANDLERS is the list of resume handlers to search
/(the default is the current list);
this is useful for thinking about other stack groups.
The value is an element of RESUME-HANDLERS, or NIL if no handler is found."
  (do ((handler-list resume-handlers (cdr handler-list)))
      ((eq handler-list (cdr handler-list)))
    (let ((h (car handler-list)))
      (if (eq h t)
	  (if (null proceed-type) (return))
	(and (cond ((null (car h)) t)
		   ((null condition-names) t)
		   ((not (consp (car h)))
		    (memq (car h) condition-names))
		   (t (dolist (c (car h))
			(if (memq c condition-names) (return t)))))
	     (or (null proceed-type)
		 (eq (cadr h) proceed-type))
	     (or (eq (caddr h) t)
		 (funcall (caddr h) condition))
	     (return h))))))

;(def describe-proceed-types "Moved to SYS2; EHC")

(defmethod (condition :proceed-type-p) (proceed-type)
  (or (memq proceed-type condition-proceed-types)
      (do ((handler-list condition-resume-handlers (cdr handler-list))
	   (h))
	  ((eq handler-list (cdr handler-list)))
	(setq h (car handler-list))
	(and (consp h)
	     (cond ((null (car h)) t)
		   ((not (consp (car h)))
		    (memq (car h) condition-names))
		   (t (dolist (c (car h))
			(if (memq c condition-names) (return t)))))
	     (or (eq (caddr h) t) (funcall (caddr h) self))
	     (return t)))))

(defun sg-condition-proceed-types (sg condition)
  "In the debugger, return a list of CONDITION's proceed-types."
  (union (symeval-in-stack-group 'condition-proceed-types sg)
	 (condition-resume-types condition
				 (symeval-in-stack-group 'condition-resume-handlers sg))))

(defmethod (condition :proceed-types) ()
  (union condition-proceed-types
	 (condition-resume-types self)))

(defun condition-resume-types (condition &optional
			       (resume-handlers condition-resume-handlers))
  "Return a list of all resume handler keywords available for CONDITION's handlers.
These resume-types, together with the proceed-types specified in signaling,
are the possible keywords that a condition handler may return as its first value."
  (let ((condition-names (send condition :condition-names))
	types)
    (do ((handler-list resume-handlers (cdr handler-list))
	 (h))
	((eq handler-list (cdr handler-list)))
      (setq h (car handler-list))
      (and (consp h)
	   (cond ((null (car h)) t)
		 ((not (consp (car h)))
		  (memq (car h) condition-names))
		 (t (dolist (c (car h))
		      (if (memq c condition-names) (return t)))))
	   (or (eq (caddr h) t) (funcall (caddr h) condition))
	   (not (memq (cadr h) types))
	   (push (cadr h) types)))
    (setq types (nreverse types))
    ;; Put all proceed-types which are lists at the end.
    (nconc (subset #'atom types) (subset-not #'atom types))))

(defun sg-condition-handled-p (sg condition-names)
  "T if there is an active condition handler in SG that might handle one of CONDITION-NAMES."
  (do ((hh (symeval-in-stack-group 'condition-handlers sg) (cdr hh))
       (part nil))
      (())
    (if (null hh)
	(if part (return nil)
	  (setq hh (symeval-in-stack-group 'condition-default-handlers sg)
		part t)))
    (let ((h (car hh)))
      (and (cond ((null (car h)) t)
		 ((atom (car h))
		  (if (consp condition-names)
		      (memq (car h) condition-names)
		    (eq (car h) condition-names)))
		 ((atom condition-names)
		  (memq condition-names (car h)))
		 (t (dolist (c condition-names)
		      (if (memq c (car h))
			  (return t)))))
	   (return t)))))

;;;; Functions for finding the special pdl info associated with a stack frame.

(defmacro scan-specpdl-by-frames ((sg) (sp-var rp-var sp-start sp-end frame-var)
				  before-frame-body after-frame-body
				  &body body)
  `(let ((,sp-var (sg-special-pdl ,sg))
	 (,rp-var (sg-regular-pdl ,sg)))
     (do ((,frame-var (if (eq ,sg current-stack-group)
			  ;; Figure out RP index of our own frame!
			  (%pointer-difference
			    (%stack-frame-pointer)
			    (aloc ,rp-var 0))
			(sg-ap ,sg))
	   (sg-next-active ,sg ,frame-var))
	  (ignore-frame (eq ,sg current-stack-group) nil)
	  (,sp-end (if (eq ,sg current-stack-group)
			 (get-own-special-pdl-pointer ,sp-var)
		       (sg-special-pdl-pointer ,sg)))
	  (,sp-start))
	 ((null ,frame-var))
       (progn . ,before-frame-body)
       (cond ((and (not ignore-frame)
		   (not (zerop (rp-binding-block-pushed ,rp-var ,frame-var))))
	      (do ()
		  ((= (%p-data-type (aloc ,sp-var ,sp-end)) dtp-locative))
		;; Space back over a random non-binding frame
		(do ()
		    ((not (zerop (%p-ldb %%specpdl-block-start-flag (aloc ,sp-var ,sp-end)))))
		  (setq ,sp-end (1- ,sp-end)))
		(setq ,sp-end (1- ,sp-end)))
	      ;; Make SP-START and SP-END inclusive brackets for this binding frame
	      (setq ,sp-start (1- ,sp-end))
	      (do ()
		  ((not (zerop (%p-ldb %%specpdl-block-start-flag (aloc ,sp-var ,sp-start)))))
		(setq ,sp-start (- ,sp-start 2)))
	      ;; Do the body, now that SP-START and SP-END are set up.
	      (progn . ,body)
	      (setq ,sp-end (1- ,sp-start))))
       (progn . ,after-frame-body))))

;;; Get the special-pdl pointer for the running SG
(defun get-own-special-pdl-pointer (&optional (sp (sg-special-pdl current-stack-group)))
  "Return the current special pdl pointer of the current stack group.."
  (%pointer-difference (special-pdl-index)
		       (aloc sp 0)))

(defun sg-frame-special-pdl-range (sg frame &aux (rp (sg-regular-pdl sg)))
  "Return the range of indices in SG's special pdl that go with FRAME.
/(FRAME is an index in the regular pdl.)
The two values are a starting index and an ending index.
If there is no special pdl data for the frame, NIL is returned."
  (and (not (zerop (rp-binding-block-pushed rp frame)))
       (scan-specpdl-by-frames (sg) (sp rp i j frame1) nil nil
	 (and (= frame1 frame) (return i j)))))

(defun sg-frame-special-pdl-index (sg frame)
  "Return an index in SG's special pdl corresponding to just outside frame FRAME.
The value points to the last word of data pushed outside of this frame.
It is never NIL."
  (scan-specpdl-by-frames (sg) (sp rp i j frame1)
			  nil ((and (= frame1 frame) (return j)))))

(defun sg-frame-of-special-binding (sg location value)
  "Return the frame in SG where LOCATION (a value cell) is bound to VALUE.
The innermost binding that has that value is the one found."
  ;; If SG is not running, we scan outward till we find a binding with that value.
  ;; If SG is running, we scan outward till we find such a binding,
  ;; then keep scanning till the next binding.
  (prog (;; If the desired binding is the innermost one,
	 ;; set the flag to return on first binding found.
	 (return-on-next-binding
	   (and (eq sg current-stack-group)
		(eq (contents location) value))))
	(scan-specpdl-by-frames (sg) (sp rp i j frame1) nil nil
	  (do ((idx j (- idx 2)))
	      ((< idx i))
	    (when (eq (aref sp idx) location) 
	      (if return-on-next-binding
		  (return-from sg-frame-of-special-binding frame1))
	      (if (eq (aref sp (1- idx)) value)
		  (if (eq sg current-stack-group)
		      (setq return-on-next-binding t)
		    (return-from sg-frame-of-special-binding frame1))))))))

(defun sg-resume-handler-frame (sg resume-handler)
  "Return the index of the frame in SG in which RESUME-HANDLER was established.
RESUME-HANDLER should be an element of CONDITION-RESUME-HANDLERS' value in SG.
We assume that elements are pushed onto CONDITION-RESUME-HANDLERS
always one at a time."
  (sg-frame-of-special-binding sg (locf condition-resume-handlers)
			       (memq resume-handler
				     (symeval-in-stack-group 'condition-resume-handlers sg))))

;;;; Various non-microcode conditions.

(defsignal-explicit fquery condition (options format-string &rest format-args)
  "By default, calls to FQUERY signal this."
  :property-list (list :options options)		    
  :format-string format-string
  :format-args (copy-list format-args))

(defsignal zwei:barf condition ()
  "All calls to ZWEI:BARF signal this condition, normally ignored.")

(defsignal sys:abort condition ()
  "This is signaled to abort back to the innermost command loop.")

(defsignal sys:unknown-locf-reference error (form)
  "Means that LOCF was used on a form which it did not know how to handle.")

(defsignal sys:unknown-setf-reference error (form)
  "Means that SETF was used on a form which it did not know how to handle.")

(defsignal sys:zero-log sys:arithmetic-error (number)
  "NUMBER, which is a zero, was used as the argument to a logarithm function.")

(defsignal-explicit sys:illegal-expt sys:arithmetic-error
		    (base-number power-number format-string)
  "Attempt to raise BASE-NUMBER to power POWER-NUMBER
for cases in which the result is not defined"
  :format-string format-string
  :format-args (list base-number power-number))

(defsignal math:singular-matrix arithmetic-error (matrix)
  "Signaled when any matrix handling function finds a singular matrix.")

(defflavor unclaimed-message-error () (error))

(defmethod (unclaimed-message-error :case :proceed-asking-user :new-operation)
	   (proceed-function read-argument-function)
  "Use another operation instead.  You specify the operation."
  (funcall proceed-function :new-operation
	   (funcall read-argument-function :eval-read
		    "Form to evaluate to get operation to perform instead:~%")))

(defsignal sys:unclaimed-message unclaimed-message-error (object message arguments)
  "OBJECT, an instance, funcallable hash table or select-method, didn't recognize operation MESSAGE.")

(defsignal sys:invalid-form error (form)
  "EVAL was given FORM and couldn't make sense of it.")

(defsignal sys:invalid-function invalid-function (function)
  "FUNCTION was supposed to be applied, but it is malformatted, etc.")

(defsignal sys:invalid-function-spec error (function-spec)
  "Invalid function spec passed to FDEFINITION, etc.")

(defsignal sys:invalid-lambda-list invalid-function (function)
  "The interpreted function FUNCTION's lambda list is malformatted.")

(defsignal sys:undefined-keyword-argument sys:undefined-keyword-argument
  (keyword value)
  "A function wanting keyword args to KEYWORD with VALUE, which it wasn't expecting.")

(defflavor sys:undefined-keyword-argument () (error))

(defmethod (sys:undefined-keyword-argument :case :proceed-asking-user :new-keyword)
	   (continuation read-object-function)
  "Use a different keyword, which you must type in."
  (funcall continuation :new-keyword
	   (funcall read-object-function :eval-read
		    "Form to evaluate to get the keyword to use instead of ~S: "
		    (send self :keyword))))

(defsignal stream-closed (error stream-closed stream-invalid) (stream)
  "I//O to STREAM, which has been closed and no longer knows how to do I//O.")

(defsignal stream-invalid error (stream)
  "I//O to STREAM, which is in a state not valid for I//O.")

(defflavor end-of-file () (error))

(defsignal sys:end-of-file-1 end-of-file (stream)
  "End of file on STREAM, not within READ.")

(defflavor parse-error (stream) (ferror) :settable-instance-variables)
(defflavor parse-ferror () (parse-error) :alias-flavor)

(defsignal parse-error-1 parse-error ()
  "Error in parsing input; rubout handler should handle it.")

(defun parse-ferror (format-string &rest args)
  (apply #'cerror :no-action nil 'parse-error-1 format-string args))

(defmethod (parse-error :after :init) (ignore)
  (setq stream (and (variable-boundp si:read-stream) si:read-stream)))

(defmethod (parse-error :after :print-error-message) (ignore ignore -stream-)
  (when stream
    (format -stream- "Error occurred in reading from ~S.~%" stream)))

(defmethod (parse-error :case :proceed-asking-user :no-action) (continuation ignore)
  "Continue reading, trying to ignore the problem."
  (funcall continuation :no-action))

(defflavor package-error () (error)
  (:documentation "All package errors are based on this"))

(defflavor package-not-found (package-name
			      (relative-to))
	   (no-action-mixin package-error)
  :inittable-instance-variables
  :gettable-instance-variables
  ;(:documentation "")
  )

(defmethod (package-not-found :report) (stream)
  (format stream "No package named /"~A/"~@[ relative to ~A~]"
	  package-name relative-to))

(defmethod (package-not-found :case :proceed-asking-user :retry)
	   (proceed-function ignore)
  "Looks for the package again.  Use this if you create it by hand"
  (funcall proceed-function :retry))

(defmethod (package-not-found :case :proceed-asking-user :create-package)
	   (proceed-function ignore)
  "Creates the package (with default characteristics) and proceeds."
  (format t "Creating package ~A." (send self :package-name))
  (funcall proceed-function :create-package))

(defmethod (package-not-found :case :proceed-asking-user :new-name)
	   (proceed-function prompt-and-read-function)
  "Proceeds, asking for a name of a package to use instead."
  (funcall proceed-function :new-name
	   (funcall prompt-and-read-function :string
		    "Name (not local nickname) of package to use instead: ")))

(defsignal-explicit read-package-not-found (package-not-found parse-error) (string name)
  "Signaled when READ finds a package prefix for a nonexistent package"
  :format-string string
  :format-args (list name)
  :package-name name)


(defflavor package-name-conflict (in-package operation conflicts)
	   (package-error)
  :gettable-instance-variables
  :inittable-instance-variables
  (:default-init-plist :condition-names '(name-conflict))	;make alias name work right
  (:documentation "Base flavor for all error dealing with name conflicts"))
;;; what slime call it.
(defflavor name-conflict () (package-name-conflict) :alias-flavor)

;(defmethod (package-name-conflict :case :document-proceed-type :punt) (stream ignore)
;  (format stream "Returns without doing the ~A." (send self :operation)))

;(defmethod (package-name-conflict :case :document-proceed-type :shadow) (stream ignore)
;  (format stream "Leaves the symbols already in package ~A where they are."
;	  (send self :package)))

;(defmethod (package-name-conflict :case :document-proceed-type :export) (stream ignore)
;  (format stream "Puts the newly inheritable symbols into the package."))

;(defmethod (package-name-conflict :case :document-proceed-type :unintern) (stream ignore)
;  (format stream "Uninterns the conflicting symbol~:[ ~S~;s~]."
;	  (cdr (send self :losing-symbols))
;	  (send self :losing-symbols)))

;(defmethod (package-name-conflict :case :proceed-asking-user :shadowing-import)
;	   (proceed-function prompt-and-read-function)
;  (funcall proceed-function :shadowing-import
;	   (funcall prompt-and-read-function :string
;		    "Package name of the symbol you want to prefer.")))

;(defmethod (package-name-conflict :case :document-proceed-type :choose) (stream ignore)
;  (format stream "Pops up window to specify what to do in more detail."))

;(defmethod (package-name-conflict :case :document-proceed-type :share) (stream ignore)
;  (format stream "Forwards all the symbols together like GLOBALIZE."))

(defflavor use-package-name-conflict (in-package using-packages
				      (local-conflicts) (inherited-conflicts)
				      (external-conflicts))
	   (package-name-conflict)
  (:default-init-plist :operation 'use-package)
  :gettable-instance-variables
  :inittable-instance-variables
  ;(:documentation "")
  )

;(defmethod (use-package-name-conflict :after :init) (ignore)
;  (setq local-conflicts (sortcar local-conflicts #'string<)
;	inherited-conflicts (cons (car inherited-conflicts)
;				  (sortcar (cdr inherited-conflicts) #'string<))
;	external-conflicts (sortcar external-conflicts #'string<)))

(defmethod (use-package-name-conflict :report) (stream)
  (format stream "Calling USE-PACKAGE from package ~A on package~:[ ~{~A~^~}~;s
~{~#[~; and ~A~; ~A~:; ~A,~]~}~] caused the following name-conflict~P:"
	  in-package (cdr using-packages) using-packages (+ (length local-conflicts)
							    (length inherited-conflicts)
							    (length external-conflicts)))
  (dolist (c local-conflicts)
    (format stream "~&Package ~A already contains symbol /"~A/";
  it would inherit ~:[a conflicting symbol from package~;conflicting symbols from packages~]"
	    in-package (caar c) (cdr c))
    (dolist (loser c)
      (format stream " ~A" (cdr loser))))
  (dolist (c inherited-conflicts)
    (format stream "~&Package ~A already inherits symbol /"~A/" (from package ~A);
  it would inherit ~:[a conflicting symbol from package~;conflicting symbols from packages~]"
	    in-package (caar c) (cdar c) (cddr c))
    (dolist (loser (cdr c))
      (format stream " ~A" (cdr loser))))
  (dolist (c external-conflicts)
    (format stream "~&Package ~A would inherit a symbol named /"~A/" from multiple packages:"
	    in-package (caar c))
    (dolist (loser c)
      (format stream " ~A" (cdr loser)))))


;(defun choose-use-package-loss-avoidance (&aux tem (default '(())) (*package* in-package))
;  (declare (:self-flavor use-package-name-conflict))
;  (let ((title (format nil "(USE-PACKAGE '(~{~A~#[~:; ~A~]~}) '~A)"
;		       using-packages in-package))
;	(vars nil))
;    (when local-conflicts
;      (push vars `(nil ,(format nil "Symbols already present in ~A" in-package) nil))
;      (dolist (c local-conflicts)
;	(push vars `(shadow "Shadow old")
;	(dolist (loser c)
;	  (push vars `((use ,(cdr loser))
;		       ,(format nil "Unintern, USE ~A" (cdr loser)))))


(defflavor read-end-of-file () (end-of-file parse-error))

(defmethod (read-end-of-file :case :proceed-asking-user :no-action) (continuation ignore)
  "Close off all unfinished lists."
  (funcall continuation :no-action))

(defsignal read-end-of-file (read-end-of-file read-error) (stream)
  "End of file within READ on STREAM.
SYS:READ-LIST-END-OF-FILE or SYS:READ-STRING-END-OF-FILE should be used
if they apply.")

(defsignal read-list-end-of-file (read-end-of-file read-error read-list-end-of-file)
	   (stream list)
  "End of file within READ constructing a list, on STREAM.
LIST is the list constructed so far.")

(defsignal read-string-end-of-file (read-end-of-file read-error read-string-end-of-file)
	   (stream string)
  "End of file within READ constructing a string, on STREAM.
STRING is the string read so far.")

(defsignal read-symbol-end-of-file (read-end-of-file read-error read-symbol-end-of-file)
	   (stream string)
  "End of file within READ constructing a symbol, on STREAM.
Occurs only within a vertical-bar construct.  STRING is the string read so far.")

(defsignal read-error-1 (parse-error read-error) ()
  "Error other than end of file, within READ.")

(defsignal missing-closeparen (parse-error read-error missing-closeparen) ()
  "Error of open paren found in column 0 in middle of defun.")

(defsignal print-not-readable ferror (object)
  "Printing OBJECT, which cannot be printed so it can be read back.")

(defflavor disk-error () (error))

;;; It's best to encourage handlers to let the user see these!
(defmethod (disk-error :dangerous-condition-p) () t)

(defsignal sys:disk-error disk-error ()
 "A fatal disk error happened.")

(defmethod (disk-error :case :proceed-asking-user :retry-disk-operation)
	   (continuation read-object-function)
  "Try the disk operation again."
  (if (funcall read-object-function '(:fquery)
	       "Retry the disk operation? ")
      (funcall continuation :retry-disk-operation)))

(defflavor redefinition () (warning))

(defmethod (redefinition :case :proceed-asking-user :proceed) (continuation ignore)
  "Perform this and all further redefinitions of that file by this file."
  (funcall continuation :proceed))

(defmethod (redefinition :case :proceed-asking-user :inhibit-definition) (continuation ignore)
  "Continue execution but skip this redefinition."
  (funcall continuation :inhibit-definition))

(defsignal sys:redefinition redefinition
  (definition-type name new-pathname old-pathname)
  "NAME's definition of type DEFINITION-TYPE was redefined in a different file.
The old definition was in OLD-PATHNAME and the new one is in NEW-PATHNAME.
Both of the last two are generic pathnames or NIL.")

(defflavor network-error () (error))

(defflavor local-network-error () (network-error))

(defflavor remote-network-error (connection foreign-host) (network-error)
  :gettable-instance-variables
  :inittable-instance-variables)

(defmethod (remote-network-error :after :init) (ignore)
  (setq connection (getf si:property-list :connection))
  (setq foreign-host (or (getf si:property-list :foreign-host)
			 (and connection
			      (si:get-host-from-address
				(chaos:foreign-address connection) :chaos)))))

(defsignal sys:network-resources-exhausted local-network-error ()
  "The connection table was full, or something else has run out.")

(defsignal sys:unknown-address local-network-error (address)
  "ADDRESS was an /"address/" argument to CHAOS:CONNECT or some such.")

(defsignal sys:unknown-host-name local-network-error (name)
  "NAME was specified as a host name and not recognized.")

(defflavor bad-connection-state () (remote-network-error))

(defsignal sys:bad-connection-state-1 (bad-connection-state) (connection)
  "CONNECTION was in a bad state and some operation couldn't be done.
Use a more specified signal-name if one applies:
SYS:CONNECTION-NO-MORE-DATA, SYS:HOST-STOPPED-RESPONDING,
SYS:CONNECTION-CLOSED, or SYS:CONNECTION-LOST.")

(defflavor connection-error () (remote-network-error))

(defsignal sys:connection-error-1 (connection-error) (connection)
  "An error in making a connection.  CONNECTION is the connection-object.
Use a more specified signal-name if one applies:
SYS:HOST-NOT-RESPONDING-DURING-CONNECTION or SYS:CONNECTION-REFUSED.")

(defsignal sys:host-not-responding-during-connection
	   (connection-error
	     sys:host-not-responding-during-connection host-not-responding)
  (connection)
  "The foreign host did not respond when asked to make a connection.
CONNECTION is the connection object we used while trying.")

(defsignal sys:no-server-up connection-error ()
  "No server was available for some protocol this machine wanted to use.")

(defsignal sys:host-stopped-responding (bad-connection-state
					sys:host-stopped-responding
					host-not-responding)
  (connection)
  "The foreign host stopped responding while we were connected.
CONNECTION is the connection object.")

(defsignal sys:connection-refused connection-error
  (connection foreign-host reason)
  "FOREIGN-HOST refused a connection, giving REASON.  REASON is NIL
if none was given.  CONNECTION is the connection object.")

(defsignal sys:connection-closed bad-connection-state (connection reason)
  "Foreign host refused a connection, giving REASON.  REASON is NIL
if none was given.  CONNECTION is the connection object.")


(defsignal sys:connection-lost bad-connection-state (connection reason)
  "CONNECTION was broken for REASON.  REASON is NIL
if none was given.  CONNECTION is the connection object.")


(defsignal sys:connection-no-more-data bad-connection-state (connection foreign-host)
  "Attempt to read past all data received on closed connection CONNECTION.")

;; This is used for the M-Break and C-M-Break keys.
(defflavor break ((format-string "break.")) (condition))

(defmethod (break :debugging-condition-p) () t)

(defmethod (break :case :proceed-asking-user :no-action) (continuation ignore)
  "Proceed."
  (format t " Continue from break.~%")
  (funcall continuation :no-action))

(defmethod (break :print-error-message-prefix) (sg brief stream)
  sg brief
  (princ ">>Keyboard " stream))

;;; Conventions for the error handler routines:  how to add new ones.
;;;
;;; Each place in the microcode where TRAP can be called is followed by
;;; an ERROR-TABLE pseudo-op.  This should appear at the PC which is
;;; going to be TRAP's return address.  An example is
;;;    (ERROR-TABLE ARGTYP FIXNUM M-T 0)
;;; (for example).  The CDR of this list is the ETE.  So, the FIRST element
;;; is the name of the error, and the SECOND is the first "argument" to that
;;; error's associated routines.
;;;
;;; All ETEs should be a list whose car is a symbol.
;;; That symbol should be defined in a DEF-UCODE-ERROR in this file.
;;; Within the DEF-UCODE-ERROR, the variable ETE can be used to
;;; refer to the entire ETE list.

(defmacro def-ucode-error (error-name error-flavor &body init-options)
  (let ((error-flavor (if (consp error-flavor) (car error-flavor) error-flavor))
	(condition-names (if (consp error-flavor) (cdr error-flavor) (list error-name))))
    `(progn (si:record-source-file-name ',error-name 'defsignal)
	    (defun (:property ,error-name make-ucode-error-function) (ignore sg ete)
	      (declare (function-parent ,error-name def-ucode-error))
	      sg ete
	      (make-instance ',error-flavor
			     :condition-names ',condition-names
			     ,@init-options)))))

(defun make-ucode-error (error-name sg ete)
  (funcall (get error-name 'make-ucode-error-function)
	   error-name sg ete))

(defmacro def-ucode-format-error (error-name error-flavor &body format-args)
  (declare (arglist error-name error-flavor format-string &body format-args))
  `(def-ucode-error ,error-name ,error-flavor
     :format-string ,(car format-args)
     :format-args (list . ,(cdr format-args))))

(defun sg-proceed-micro-pc (sg tag)
  "Restart SG from an error in the microcode, at micro-pc determined by TAG.
TAG may be the name of an (ERROR-TABLE RESTART tag) in the microcode source.
If TAG is NIL, restart at the pc where the error happened.
If a PROCEED routine doesn't call SG-PROCEED-MICRO-PC, then
control will be returned from the micro-routine that got the error."
  ;; Operates by pushing the specified PC onto the saved microstack,
  ;; since resuming the stack group will do a POPJ.
  (let ((pc (if tag (cdr (assq tag restart-list)) (1+ (sg-trap-micro-pc sg)))))
    (when (null pc)
      (bad-hacker tag " no such restart!")
      (throw 'quit nil))
    ;; Since the micro stack is saved backwards, the top of the stack is buried
    ;; where it is hard to get at.
    (let ((rp (sg-regular-pdl sg))
	  (sp (sg-special-pdl sg))
	  (spp (sg-special-pdl-pointer sg))
	  (frame (sg-ap sg)))
      (or (zerop (rp-micro-stack-saved rp frame))	;Shuffle up stack to make room
	  (do ((flag 0)) ((not (zerop flag)))
	    (aset (aref sp spp) sp (1+ spp))
	    (%p-dpb 0 %%specpdl-block-start-flag (aloc sp (1+ spp)))
	    (setq flag (%p-ldb %%specpdl-block-start-flag (aloc sp spp)))
	    (setq spp (1- spp))))
      (aset pc sp (setq spp (1+ spp)))
      (%p-dpb 1 %%specpdl-block-start-flag (aloc sp spp))
      (setf (sg-special-pdl-pointer sg) (1+ (sg-special-pdl-pointer sg)))
      (setf (rp-micro-stack-saved rp frame) 1))))

(def-ucode-error argtyp (arg-type-error wrong-type-argument)
  :description (description-type-spec (second ete))
  :arg-location-in-sg (third ete)
  :arg-pointer (sg-pointer-careful sg (third ete))
  :arg-data-type (sg-data-type sg (third ete))
  :arg-number (fourth ete)
  :restart-tag (fifth ete)
  :function (or (sixth ete)
		(and (eq (fifth ete) 'array-decode-n-error-restart)
		     (not (memq (sg-erring-function sg) '(aref aset aloc)))
		     (aref (sg-regular-pdl sg) (sg-ipmark sg)))
		(sg-erring-function sg)))

(defun sg-data-type (sg register)
  (%p-data-type (sg-locate sg register)))

(defun sg-pointer-careful (sg register)
  (let* ((location (sg-locate sg register)))
    (cond ((%p-contents-safe-p location)
	   (contents location))
	  ((%p-pointerp location)
	   (%p-contents-as-locative location))
	  (t (%p-pointer location)))))

(defflavor arg-type-error
	(arg-number function arg-pointer arg-data-type description
		    arg-location-in-sg restart-tag)
	(error)
  :gettable-instance-variables
  :initable-instance-variables)

(defmethod (arg-type-error :arg-name) ()
  ;; This works for microcoded functions.
  (and arg-number
       (nth arg-number (arglist function))))

(defmethod (arg-type-error :old-value) ()
  (%make-pointer arg-data-type arg-pointer))

(defmethod (arg-type-error :report) (stream)
  (format:output stream
    (format t "~:[Some~*~*~;The~:[ ~:R~;~*~]~] argument to ~S, "
	    arg-number (eq arg-number t) (and (numberp arg-number) (1+ arg-number))
	    function)
    (if (null arg-data-type)
	(format t "whose value has not been preserved")
      (or (consp (errset (prin1 (%make-pointer arg-data-type arg-pointer)) nil))
	  (printing-random-object (nil *standard-output*)
	    (format t "~A #o~O" (nth arg-data-type q-data-types) arg-pointer))))
    (format t (if (arrayp function) ", was an invalid array subscript.~%Use "      
		", was of the wrong type.~%The function expected "))
    (princ (si:type-pretty-name description))
    "."))


;;; this stuff is pretty bogus nowadays...

;;; Translate symbols appearing in ARGTYP entries into type specs.
;;; Those that do not appear in the alist are left unchanged.
;;; SYMBOL-OR-LOCATIVE is translated because that's as good as defining it.
;;; The others are translated because they are global and we don't want
;;; to define any global type specs that aren't documented.
(defconst description-type-specs
  '((plusp positive-number)
    (nil null)
    (non-nil (not null))
    (art-q-array q-array)
    (symbol-or-locative (or symbol locative))))

(defun description-type-spec (desc)
  (if (symbolp desc)
      (or (cadr (assq desc description-type-specs))
	  desc)
    `(or . ,(mapcar 'description-type-spec desc))))

;;; Define, as type specs, all the symbols that appear in ARGTYP entries.
;;; Specify pretty names for those for which the default is not pretty.
;;; For some, we must define new predicates to make them work in TYPEP.

(deftype positive-fixnum () '(and fixnum (integer 0)))

(deftype nonnegative-fixnum () '(and fixnum (integer 0)))

(deftype fixnum-greater-than-0 () '(and fixnum (integer 1)))

(deftype fixnum-greater-than-1 () '(and fixnum (integer 2)))

(deftype positive-number () '(and number (satisfies plusp)))

(deftype art-q-list-array () '(and array (satisfies art-q-list-array-p)))
(defun art-q-list-array-p (array)
  (eq (array-type array) 'art-q-list))
(defprop art-q-list-array "an ART-Q-LIST array" si:type-name)

(deftype q-array () '(array t))
(deftype byte-array () '(and array (not (array t))))
(deftype numeric-array () '(and array (not (array t))))

(deftype art-4b-array () '(array (mod 16.)))
(defprop art-4b-array "an ART-4B array" si:type-name)

(deftype art-16b-array () '(array (unsigned-byte 16.)))
(defprop art-16b-array "an ART-16B array" si:type-name)

(deftype non-displaced-array () '(and array (not (satisfies array-displaced-p))))
(defprop non-displaced-array "a non-displaced array" si:type-name)

(deftype reasonable-size-array () '(and array (satisfies array-size-reasonable-p)))
(defun array-size-reasonable-p (array)
  array
  t)						; I wonder what uses this ...

(deftype fixnum-field () '(satisfies byte-spec-p))
(defun byte-spec-p (x)
  (and (fixnump x)
       (< (byte-size x) %%q-pointer)))
(defprop fixnum-field "a byte spec for a field that fits in a fixnum" si:type-name)

(deftype area () '(and fixnum (satisfies area-number-p)))
(defun area-number-p (number)
  (and (< -1 number (array-length #'area-name))
       (area-name number)))
(defprop area "a valid area number" si:type-name)

(defmethod (arg-type-error :ucode-proceed-types) ()
  (if restart-tag '(:argument-value)))

(defmethod (arg-type-error :case :proceed-asking-user :argument-value)
	   (continuation read-object-function)
  "Use a different argument.  You type an expression for the new value."
  (funcall continuation :argument-value
	   (funcall read-object-function :eval-read
		    "Form to evaluate and use as replacement argument: ")))

(defmethod (arg-type-error :case :proceed-ucode-with-args :argument-value)
	   (sg value &rest ignore)
  (sg-store value sg arg-location-in-sg)
  (sg-proceed-micro-pc sg (and (neq restart-tag 'fall-through) restart-tag)))

(def-ucode-error flonum-no-good (arg-type-error wrong-type-argument)
  :description 'integer
  :arg-location-in-sg nil
  :arg-pointer nil
  :arg-data-type nil
  :arg-number nil
  :restart-tag nil
  :function (sg-erring-function sg))

(defsignal-explicit wrong-type-argument wrong-type-argument-error
  (format-string &rest format-args)
  "Wrong type argument from a CHECK-TYPE macro."
  :format-string format-string
  :format-args (copy-list format-args)
  :property-list `(:description ,(first format-args)
				:old-value ,(second format-args)
				:arg-name ,(third format-args)
				:function
				,(let ((rp (sg-regular-pdl current-stack-group)))
				   (rp-function-word
				     rp
				     (sg-previous-nth-active current-stack-group
							     (%pointer-difference
							       (%stack-frame-pointer)
							       (aloc rp 0))
							     -3)))))

(defflavor wrong-type-argument-error () (error))

(defmethod (wrong-type-argument-error :case :proceed-asking-user :argument-value)
	   (continuation read-object-function)
  "Use a different argument.  You type an expression for the new value."
  (funcall continuation :argument-value
	   (funcall read-object-function :eval-read
	     (format nil "Form to be evaluated and used as replacement value for ~A:~%"
		     (send self :arg-name)))))

(defflavor failed-assertion (places) (error)
  :inittable-instance-variables
  :gettable-instance-variables)

(defmethod (failed-assertion :or :document-proceed-type)
	   (proceed-type stream ignore)
  (when (memq proceed-type places)
    (format stream "Try again, setting ~S.  You type an expression for it." proceed-type)
    t))

(defmethod (failed-assertion :or :proceed-asking-user)
	   (proceed-type continuation read-object-function)
  (when (memq proceed-type places)
    (funcall continuation proceed-type
	     (funcall read-object-function :eval-read
		      "Form to be evaluated and used as replacement value for ~S:~%"
		      proceed-type))
    t))

(defflavor arithmetic-error () (error))

;;; FIXNUM-OVERFLOW
;;; First arg is M-T to show that that is where the value should
;;;   get stored.  Maybe it will someday be other things, too.
;;; Second is either PUSH or NOPUSH.
;;; Recover by storing a new value in the place where the
;;;   value would have been stored if it hadn't overflowed.
;;;   This is M-T, and also the regpdl if the second arg is PUSH.
;;;   Force return from the microroutine executing at the time.

(def-ucode-error fixnum-overflow fixnum-overflow-error
  :function (sg-erring-function sg)
  :number (sg-contents sg (second ete))
  :location-in-sg (second ete)
  :push-new-value-flag
  (progn (or (memq (third ete) '(push nopush))
	     (bad-hacker ete "Bad ETE, must be PUSH or NOPUSH."))
	 (third ete)))

(defflavor fixnum-overflow-error (function location-in-sg push-new-value-flag number)
	   (arithmetic-error)
  :gettable-instance-variables
  :initable-instance-variables)

(defmethod (fixnum-overflow-error :report) (stream)
  (format stream "~S got a fixnum overflow." function))

(defmethod (fixnum-overflow-error :ucode-proceed-types) ()
  '(:new-value))

(defmethod (fixnum-overflow-error :case :proceed-asking-user :new-value)
	   (continuation read-object-function &aux num)
  "Return a value specified by you.  You type an expression for the new value."
  (setq num (funcall read-object-function :eval-read
		     "Form to evaluate to get fixnum to return instead: "))
  (check-type num fixnum)
  (funcall continuation :new-value num))

(defmethod (fixnum-overflow-error :case :proceed-ucode-with-args :new-value)
	   (sg value &rest ignore)
  (sg-fixnum-store value sg location-in-sg)
  (and (eq push-new-value-flag 'push)
       (sg-regpdl-push sg value)))

;;; FLOATING-EXPONENT-UNDERFLOW
;;; Arg is SFL or FLO

(def-ucode-error floating-exponent-underflow floating-exponent-underflow-error 
  :small-float-p (eq (second ete) 'sfl)
  :function (sg-erring-function sg))

(defflavor floating-exponent-underflow-error (function small-float-p)
	   (error)
  :gettable-instance-variables
  :initable-instance-variables)

(defmethod (floating-exponent-underflow-error :report) (stream)
  (format stream "~S produced a result too small in magnitude to be a ~:[~;short~] float."
	  function
	  small-float-p))

(defmethod (floating-exponent-underflow-error :ucode-proceed-types) ()
  '(:use-zero))

(defmethod (floating-exponent-underflow-error :case :proceed-asking-user
					      :use-zero)
	   (continuation read-object-function)
  "Use zero as the result."
  (when (funcall read-object-function
		 '(:fquery :list-choices nil :fresh-line nil)
		 "Proceeds using 0.0~:[s~;f~]0 as the value instead? "
		 (not small-float-p))
    (funcall continuation :use-zero)))

(defmethod (floating-exponent-underflow-error :case :proceed-ucode-with-args
					      :use-zero)
	   (sg &rest ignore)
  (sg-proceed-micro-pc sg nil))

;;; FLOATING-EXPONENT-OVERFLOW
;;; Result is to be placed in M-T and pushed on the pdl.
;;; Arg is SFL or FLO
;;; In the case of SFL the pdl has already been pushed.

(def-ucode-error floating-exponent-overflow floating-exponent-overflow-error
  :small-float-p (eq (second ete) 'sfl)
  :function (sg-erring-function sg))

(defflavor floating-exponent-overflow-error (small-float-p function)
	   (arithmetic-error)
  :gettable-instance-variables
  :initable-instance-variables)

(defmethod (floating-exponent-overflow-error :report) (stream)
  (format stream "~S produced a result too large in magnitude to be a ~:[~;short~] float."
	  function
	  small-float-p))

(defmethod (floating-exponent-overflow-error :ucode-proceed-types) ()
  '(:new-value))

(defmethod (floating-exponent-overflow-error :case :proceed-asking-user :new-value)
	   (continuation read-object-function &aux num)
  "Use a float specified by you as the result."
  (do-forever
    (setq num (funcall read-object-function :eval-read
		       (if small-float-p "Form evaluating to short-float to return instead: "
			 "Form evaluating to float to return instead: ")))
    (cond ((and small-float-p
		(small-floatp num))
	   (return nil))
	  ((floatp num)
	   (return nil)))
    (format t "Please use a ~:[~;short~] float.~%" small-float-p))
  (funcall continuation :new-value num))

(defmethod (floating-exponent-overflow-error :case :proceed-ucode-with-args :new-value)
	   (sg value &rest ignore)
  (sg-store value sg 'm-t)
  (and small-float-p
       (sg-regpdl-pop sg))
  (sg-regpdl-push value sg))


;;; DIVIDE-BY-ZERO
;;; You cannot recover.
;;; The second element of the ETE can be the location of the dividend.

(defun (:property divide-by-zero make-ucode-error-function) (ignore sg ete)
  (declare (ignore ete))
  (make-instance 'arithmetic-error
		 :condition-names
		 (if (eq (sg-erring-function sg) '^)
		     '(sys:illegal-expt sys:zero-to-negative-power)
		   '(sys:divide-by-zero))
		 :property-list
		 (if (second ete)
		     `(:function ,(sg-erring-function sg)
				 :dividend ,(sg-contents sg (second ete)))
		   `(:function ,(sg-erring-function sg)))
		 :format-string
		 (if (eq (sg-erring-function sg) '^)
		     "There was an attempt to raise zero to a negative power in ~S."
		   "There was an attempt to divide a number by zero in ~S.")
		 :format-args (list (sg-erring-function sg))))

(defflavor bad-array-mixin (array array-location-in-sg restart-tag)
	   ()
  (:required-flavors error)
  :gettable-instance-variables
  :inittable-instance-variables)

(defmethod (bad-array-mixin :case :proceed-asking-user :new-array)
	   (continuation read-object-function)
  "Use a different array.  You type an expression for the array to use."
  (funcall continuation :new-array
	   (funcall read-object-function :eval-read
		    "Form to eval to get array to use instead: ")))

(defmethod (bad-array-mixin :ucode-proceed-types) ()
  (if restart-tag '(:new-array)))

(defmethod (bad-array-mixin :case :proceed-ucode-with-args :new-array)
	   (sg -array-)
  (sg-store -array- sg array-location-in-sg)
  (sg-proceed-micro-pc sg restart-tag))

(defflavor bad-array-error ()
	   (bad-array-mixin error))

;;; ARRAY-NUMBER-DIMENSIONS
;;; First arg is no longer used.
;;; Second arg is how many dimensions we want (as a constant), or NIL if variable number.
;;; Third arg is the array
;;; Fourth arg is restart tag.
;;; Fourth arg is QARYR if this is array called as function.

(def-ucode-error array-number-dimensions
		 (array-number-dimensions-error array-wrong-number-of-dimensions)
  :array (sg-contents sg (fourth ete))
  :array-location-in-sg (fourth ete)
  :subscripts-used (array-number-dimensions-subscript-list sg ete)
  :restart-tag (fifth ete))

(defun array-number-dimensions-subscript-list (sg ete)
  (let* ((rp (sg-regular-pdl sg)))
    (if (not (fixnump (third ete)))
	;; This is AREF, ALOC, ASET or array called as function.
	(do ((p (sg-regular-pdl-pointer sg) (1- p))
	     subscripts
	     (c (sg-fixnum-contents sg 'm-r) (1- c)))
	    (( c 0) subscripts)
	  (push (aref rp p) subscripts))
      ;; (THIRD ETE) tells us whether the error was from ARRAY-DECODE-1, -2 or -3.
      (case (third ete)
	(1 (list (sg-fixnum-contents sg 'm-q)))
	(2 (list (sg-contents sg 'm-j)
		 (sg-contents sg 'm-q)))
	(3 (list (sg-contents sg 'm-i)
		 (sg-contents sg 'm-j)
		 (sg-contents sg 'm-q)))))))

(defflavor array-number-dimensions-error
	(subscripts-used)
	(bad-array-error)
  :initable-instance-variables
  :gettable-instance-variables)

(defmethod (array-number-dimensions-error :dimensions-expected) () (array-rank array))

(defmethod (array-number-dimensions-error :dimensions-given) ()
  (length subscripts-used))

(defmethod (array-number-dimensions-error :report) (stream)
  (format stream
	  ;; Was this array applied or aref'ed?
	  (if (eq restart-tag 'qaryr)
	      "The ~D-dimensional array ~S was erroneously applied to ~D argument~:P ~S."
	    "The ~D-dimensional array ~S was given ~D subscript~:P: ~S.")
	  (array-rank array) array
	  (length subscripts-used)
	  subscripts-used))

;;; NUMBER-ARRAY-NOT-ALLOWED
;;; First arg is where to find the array.
;;; Second arg is restart tag for new array.

(def-ucode-error number-array-not-allowed bad-array-error
  :array (sg-contents sg (second ete))
  :array-location-in-sg (second ete)
  :restart-tag (third ete)
  :format-string "The array ~S, which was given to ~S, is not allowed to be a number array."
  :format-args (list (sg-contents sg (second ete)) (sg-erring-function sg)))

;;; INDIVIDUAL-SUBSCRIPT-OOB
;;; First arg is location of array
;;; second arg is dimension number.
;;; We assume that the current frame's args are the array and the subscripts,
;;; and find the actual losing subscript that way.

(def-ucode-error individual-subscript-oob (subscript-error subscript-out-of-bounds)
  :function (sg-erring-function sg)
  :object (sg-contents sg (second ete))
  :subscripts-used (subscript-oob-subscript-list sg ete)
  :dimension-number (sg-contents sg (third ete))
  :restart-tag (fourth ete))

;;; SUBSCRIPT-OOB
;;; First arg is how many we gave.
;;; Second is the legal limit.
;;; Third optional arg is a restart tag.
;;;  It can also be a list of restart tags.  Then their addresses are pushed sequentially.
;;;  This is used to get the effect of making the microcode restart by calling
;;;  a subroutine which will return to the point of the error.
;;; Fourth optional arg is where the array is.
;;; Fifth is either T if indices are on the stack,
;;;  or 1 if this is AR-1-FORCE or such like and there is only one index (first arg says where)
;;;  or missing if this is AR-1, AR-2, AR-3 and the array's rank should be
;;;  used to decide where the args are.

(def-ucode-error subscript-oob (subscript-error subscript-out-of-bounds)
  :function (sg-erring-function sg)
  :index-location-in-sg (second ete)
  :subscript-used (sg-fixnum-contents sg (second ete))
  :subscripts-used (subscript-oob-subscript-list sg ete)
  :subscript-limit (sg-fixnum-contents sg (third ete))
  :restart-tag (fourth ete)
  :object (if (fifth ete) (sg-contents sg (fifth ete))))

(defun subscript-oob-subscript-list (sg ete)
  (let* ((object (if (fifth ete) (sg-contents sg (fifth ete))))
	 (frame (sg-ipmark sg))
	 (rp (sg-regular-pdl sg))
	 (fn (rp-function-word rp frame)))
    (if (and (arrayp object) (neq (sixth ete) 1))
	(if (sixth ete)
	    ;; This is AREF, ALOC, ASET or array called as function.
	    (do ((p (sg-regular-pdl-pointer sg) (1- p))
		 subscripts
		 (limit (+ frame (cond ((eq fn #'aset) 2)
				       ((typep fn 'array) 0)
				       (t 1)))))
		((= p limit) subscripts)
	      (push (aref rp p) subscripts))
	  ;; It is AX-1, AX-2 or AX-3.  Since we are past the point of getting
	  ;; a wrong-number-dimensions error, we can tell which by the rank of the array.
	  ;; The ETE cannot distinguish since the errors come from the same spot.
;	  (if array-index-order
	  (let ((rank (array-rank object)))
	    (case rank
	      (1 (list (sg-fixnum-contents sg (second ete))))
	      (2 (list (sg-contents sg 'm-j)
		       (- (sg-fixnum-contents sg (second ete))
			  (* (array-dimension object 1)
			     (sg-contents sg 'm-j)))))
	      (3 (list (sg-contents sg 'm-i)
		       (sg-contents sg 'm-j)
		       (- (sg-fixnum-contents sg (second ete))
			  (* (array-dimension object 2)
			     (+ (sg-contents sg 'm-j)
				(* (array-dimension object 1)
				   (sg-contents sg 'm-i)))))))))
;	    (let ((rank (array-rank object)))
;	      (case rank
;		(1 (list (sg-fixnum-contents sg (second ete))))
;		(2 (list (- (sg-fixnum-contents sg (second ete))
;			    (* (array-dimension object 0)
;			       (sg-contents sg 'm-j)))
;			 (sg-contents sg 'm-j)))
;		(3 (list (- (sg-fixnum-contents sg (second ete))
;			    (* (array-dimension object 0)
;			       (+ (sg-contents sg 'm-j)
;				  (* (array-dimension object 1)
;				     (sg-contents sg 'm-i)))))
;			 (sg-contents sg 'm-j)
;			 (sg-contents sg 'm-i))))))
	  )
      ;; If object is not known or not an array, or if AX-1-FORCE.
      (list (sg-fixnum-contents sg (second ete))))))

(defflavor subscript-error
	(function subscripts-used subscript-used index-location-in-sg
		  subscript-limit restart-tag object (dimension-number nil))
	(error)
  :gettable-instance-variables
  :initable-instance-variables)

(defmethod (subscript-error :report) (stream)
  (cond (dimension-number
	 (format stream "The subscript for dimension ~D was ~S, which is out of range for ~S."
		 dimension-number (nth dimension-number subscripts-used) object))
	(object
	 (if (= (length subscripts-used) 1)
	     (format stream "The subscript ~S for ~S was out of range in ~S."
		     subscript-used object function)
	   (format stream "The subscripts ~S for ~S were out of range in ~S."
		   subscripts-used object function)))
	((< subscript-used 0)
	 (format stream "The index, ~S, was negative in ~S."
		 subscript-used function))
	(t 
	 (format stream "The index, ~S, was beyond the length, ~S, in ~S."
		 subscript-used subscript-limit function))))

(defmethod (subscript-error :ucode-proceed-types) ()
  '(:new-subscript))

(defmethod (subscript-error :case :proceed-asking-user :new-subscript)
	   (continuation read-object-function)
  "Use different subscripts.  You type expressions for them."
  (if (or (not (arrayp object))
	  ( (length subscripts-used) (array-rank object)))
      (let (num)
	(do-forever
	  (setq num (funcall read-object-function :eval-read
			     "Form evaluating to index to use instead: "))
	  (if (and (integerp num)
		   (< -1 num subscript-limit))
	      (return))
	  (format t "Please use a positive fixnum less than ~D.~%" subscript-limit))
	(funcall continuation :new-subscript num))
    (do ((i 0 (1+ i))
	 subscripts)
	((= i (length subscripts-used))
	 (apply continuation :new-subscript (nreverse subscripts)))
      (push (funcall read-object-function :eval-read
		     " Subscript ~D: " i)
	    subscripts))))

(defmethod (subscript-error :case :proceed-ucode-with-args :new-subscript)
	   (sg &rest subscripts)
  (if dimension-number
      ;; For error in ARRAY-ROW-MAJOR-INDEX,
      ;; store back all the subscripts into the frame.
      ;; We will restart the function to examine them.
      (do ((tail subscripts (cdr tail))
	   (i 0 (1+ i)))
	  ((= i (length subscripts-used)))
	(setf (aref (sg-regular-pdl sg)
		    (+ (sg-ap sg) i 2))
	      (car tail)))
    ;; Errors based on the cumulative index: store the updated cumulative index.
    (sg-fixnum-store
;     (if array-index-order
      (do ((i 0 (1+ i))
	   (index 0)
	   (rest subscripts (cdr rest)))
	  ((null rest) index)
	(setq index (* index (array-dimension object i)))
	(incf index (car rest)))
;	(do ((i (array-rank object) (1- i))
;	     (index 0)
;	     (rest (reverse subscripts) (cdr rest)))
;	    ((null rest) index)
;	  (setq index (* index (array-dimension object (1- i))))
;	  (incf index (car rest))))
      sg
      index-location-in-sg))
  (if (consp restart-tag)
      (dolist (tag restart-tag)
	(sg-proceed-micro-pc sg tag))
    (sg-proceed-micro-pc sg restart-tag)))

;;; First arg is where to find array, second is where to find dimension number.
(def-ucode-format-error bad-array-dimension-number error
  "The dimension number ~S is out of range for ~S."
  (sg-fixnum-contents sg (third ete))
  (sg-contents sg (second ete)))

;;; BAD-ARRAY-TYPE
;;; First arg is where array header is. Note that it may well have a data type of DTP-TRAP.
;;; You cannot recover.

(def-ucode-format-error bad-array-type error
  "The array type, ~S, was invalid in ~S."
  (ldb %%array-type-field (%p-pointer (sg-locate sg (second ete))))
  (sg-erring-function sg))

;;; ARRAY-HAS-NO-LEADER
;;; First arg is where array pointer is.
;;; Second arg is restart tag for new array.

(def-ucode-error array-has-no-leader bad-array-error
  :array (sg-contents sg (second ete))
  :array-location-in-sg (second ete)
  :restart-tag (third ete)
  :format-string "The array given to ~S, ~S, has no leader."
  :format-args (list (sg-erring-function sg) (sg-contents sg (second ete))))

;;; FILL-POINTER-NOT-FIXNUM
;;; First arg is where array pointer is.
;;; Second arg is restart tag for new array.

(def-ucode-error fill-pointer-not-fixnum bad-array-error
  :array (sg-contents sg (second ete))
  :array-location-in-sg (second ete)
  :restart-tag (third ete)
  :format-string "The fill-pointer of the array given to ~S, ~S, is not a fixnum."
  :format-args (list (sg-erring-function sg) (sg-contents sg (second ete))))

;;;; More random losses.

;;; IALLB-TOO-SMALL
;;; First arg is how many we asked for.

(def-ucode-format-error iallb-too-small error
  "There was a request to allocate ~S cells."
  (sg-fixnum-contents sg (second ete)))

(def-ucode-format-error cons-zero-size error
  "There was an attempt to allocate zero storage by ~S."
  (sg-erring-function sg))

(def-ucode-error number-called-as-function (invalid-function)
  :property-list `(:function ,(sg-contents sg (second ete)))
;character lossage
  :format-string "The ~:[number~;character~], ~S, was called as a function"
  :format-args (list (characterp (sg-contents sg (second ete)))
		     (sg-contents sg (second ete))))

(defflavor invalid-function () (error))

(defmethod (invalid-function :case :proceed-asking-user :new-function)
	   (continuation read-object-function)
  "Use a different function.  You type an expression for one."
  (funcall continuation :new-function
	   (funcall read-object-function :eval-read "Form to evaluate to get function to use instead:~%")))

(defmethod (invalid-function :ucode-proceed-types) ()
  '(:new-function))

(defmethod (invalid-function :case :proceed-ucode-with-args :new-function)
	   (sg new-function)
  (sg-store new-function sg 'm-a)
  (sg-proceed-micro-pc sg nil))

;;; WRONG-SG-STATE
;;; Arg is where sg is.
;;; You cannot recover.

(def-ucode-error wrong-sg-state (error wrong-stack-group-state)
  :format-string "The state of the stack group, ~S, given to ~S, was invalid.~%"
  :format-args (list (sg-contents sg (second ete))
		     (sg-erring-function sg)))

;;; SG-RETURN-UNSAFE
;;; No args, since the frob is in the previous-stack-group of the current one.
;;; You cannot recover.

(def-ucode-format-error sg-return-unsafe error
  "An /"unsafe/" stack group attempted to STACK-GROUP-RETURN.")

;;; TV-ERASE-OFF-SCREEN
;;; No arg.

(def-ucode-format-error tv-erase-off-screen (error draw-off-end-of-screen)
  "An attempt was made to do graphics past the end of the screen.")

;;; THROW-TAG-NOT-SEEN
;;; The tag has been moved to M-A for the EH to find it!
;;; The value being thrown is in M-T, the *UNWIND-STACK count and action are in M-B and M-C.

(def-ucode-error throw-tag-not-seen throw-tag-not-seen-error
  :tag (sg-ac-a sg)
  :value (sg-ac-t sg)
  :count (sg-ac-b sg)
  :action (sg-ac-c sg))

(defflavor throw-tag-not-seen-error (tag value count action)
	   (error)
  :gettable-instance-variables
  :initable-instance-variables)

(defmethod (throw-tag-not-seen-error :values) ()
  (list value tag))

(defmethod (throw-tag-not-seen-error :report) (stream)
  (format:output stream
    "There was no pending *CATCH for the tag " (prin1 tag) "."))

(defmethod (throw-tag-not-seen-error :after :print-error-message) (sg brief stream)
  sg
  (unless brief
    (format:output stream
      "The value being thrown was " (prin1 value) ".")
    (and (or count action)
	 (format stream "~&While in a *UNWIND-STACK with remaining count of ~D and action ~S."
		 count action))))

(defmethod (throw-tag-not-seen-error :ucode-proceed-types) ()
  '(:new-tag))

(defmethod (throw-tag-not-seen-error :case :proceed-asking-user :new-tag)
	   (continuation read-object-function)
  "Throw to another tag.  You type an expression for it."
  (funcall continuation :new-tag
	   (funcall read-object-function :eval-read
		    "Form evaluating to tag to use instead: ")))

(defmethod (throw-tag-not-seen-error :case :proceed-ucode-with-args :new-tag)
	   (sg new-tag)
  (sg-store new-tag sg 'm-a))

;;; MVR-BAD-NUMBER
;;; Where the # is.

(def-ucode-format-error mvr-bad-number error
  "The function attempted to return ~D. values."
  (sg-fixnum-contents sg (second ete)))

(def-ucode-format-error zero-args-to-select-method error
  "~S was applied to no arguments."
  (sg-contents sg (second ete)))

(def-ucode-error selected-method-not-found (error sys:unclaimed-message)
  :format-string "No method for message ~S was found in a call to ~S."
  :format-args (list (sg-contents sg (third ete))
		     (sg-contents sg (second ete)))
  :property-list `(:object ,(sg-contents sg (second ete))
		   :message ,(sg-contents sg (third ete))
		   :arguments ,(cdr (sg-accumulated-arguments sg))))

(defun sg-accumulated-arguments (sg)
  (do ((idx (1+ (sg-ipmark sg)) (1+ idx))
       (limit (sg-regular-pdl-pointer sg))
       (rp (sg-regular-pdl sg))
       args)
      ((> idx limit)
       (nreverse args))
    (push (aref rp idx) args)))

(def-ucode-format-error select-method-garbage-in-select-method-list error
  "The weird object ~S was found in a select-method alist."
  (sg-contents sg (second ete)))

(def-ucode-format-error select-method-bad-subroutine-call error
  "A bad /"subroutine call/" was found inside ~S."
  (sg-contents sg (second ete)))

(def-ucode-format-error no-mapping-table error
  "Flavor ~S is not a component of SELF's flavor, ~S,
on a call to a function which assumes SELF is a ~S."
  (si:fef-flavor-name (aref (sg-regular-pdl sg) (sg-ap sg)))
  (type-of (symeval-in-stack-group 'self sg))
  (si:fef-flavor-name (aref (sg-regular-pdl sg) (sg-ap sg))))

(def-ucode-format-error no-mapping-table-1 error
  "SYS:SELF-MAPPING-TABLE is NIL in a combined method.")

(def-ucode-format-error self-not-instance error
  "A method is referring to an instance variable,
but SELF is ~S, not an instance."
  (symeval-in-stack-group 'self sg))

;;; Signaled by LOCATE-IN-INSTANCE
(def-ucode-format-error instance-lacks-instance-variable error
  "There is no instance variable ~S in ~S."
  (sg-contents sg (second ete))
  (sg-contents sg (third ete)))

(def-ucode-error nonexistent-instance-variable (error instance-lacks-instance-variable)
  :format-string "Compiled code referred to instance variable ~S, no longer present in flavor ~S."
  :format-args (decode-nonexistent-instance-variable sg))

(defun decode-nonexistent-instance-variable (sg)
  (let ((flavor (si:fef-flavor-name (aref (sg-regular-pdl sg) (sg-ap sg)))))
    (list (si:flavor-decode-self-ref-pointer flavor (%p-pointer (sg-saved-vma sg)))
	  flavor)))

(def-ucode-format-error micro-code-entry-out-of-range error
  "MISC-instruction ~S is not an implemented instruction."
  (sg-fixnum-contents sg (second ete)))

(def-ucode-format-error bignum-not-big-enough-dpb error
  "There is an internal error in bignums; please report this bug.")

(def-ucode-format-error bad-internal-memory-selector-arg error
  "~S is not valid as the first argument to %WRITE-INTERNAL-PROCESSOR-MEMORIES."
  (sg-contents sg (second ete)))

(def-ucode-format-error bitblt-destination-too-small error
  "The destination of a BITBLT was too small.")

(def-ucode-format-error bitblt-array-fractional-word-width error
  "An array passed to BITBLT has an invalid width.
The width, times the number of bits per pixel, must be a multiple of 32.")

(def-ucode-error write-in-read-only error
  :property-list `(:address ,(sg-contents sg (second ete)))
  :format-string "There was an attempt to write into ~S, which is a read-only address."
  :format-args (list (sg-contents sg (second ete))))

(def-ucode-error turd-alert (turd-alert-error draw-on-unprepared-sheet)
  :sheet (sg-contents sg (second ete))
  :format-string "There was an attempt to draw on the sheet ~S without preparing it first.~%"
  :format-args (list (sg-contents sg (second ete))))

(defflavor turd-alert-error (sheet) (error)
  :gettable-instance-variables
  :inittable-instance-variables)

(defmethod (turd-alert-error :ucode-proceed-types) ()
  '(:no-action))

(defmethod (turd-alert-error :case :proceed-asking-user :no-action) (continuation ignore)
  "Proceed, perhaps writing garbage on the screen."
  (funcall continuation :no-action))

(defmethod (turd-alert-error :case :proceed-ucode-with-args :no-action) (sg &rest ignore)
  (sg-proceed-micro-pc sg nil))

;;;; General Machine Lossages.

;;; PDL-OVERFLOW
;;; Arg is either SPECIAL or REGULAR

(def-ucode-error pdl-overflow pdl-overflow-error
  :pdl-name (cdr (assq (second ete) '((regular . :regular) (special . :special)))))

(defflavor pdl-overflow-error (pdl-name)
	   (error)
  :gettable-instance-variables
  :initable-instance-variables)

(defmethod (pdl-overflow-error :report) (stream)
  (format stream "The ~A push-down list has overflown."
	  (cadr (assq pdl-name '((:regular "regular") (:special "special"))))))

(defmethod (pdl-overflow-error :ucode-proceed-types) () '(:grow-pdl))

(defmethod (pdl-overflow-error :case :proceed-asking-user :grow-pdl) (continuation ignore)
  "Make the stack larger and proceed."
  (funcall continuation :grow-pdl))

(defmethod (pdl-overflow-error :case :proceed-ucode-with-args :grow-pdl) (sg &rest ignore)
  (format t "Continuing with more pdl.~%")
  (sg-maybe-grow-pdls sg t nil nil t)	;Make very sure that there is enough room
  (sg-proceed-micro-pc sg nil))		;Then continue after ucode check for room

;;; ILLEGAL-INSTRUCTION
;;; No args.

(def-ucode-format-error illegal-instruction error
  "There was an attempt to execute an invalid instruction: ~O."
  (let ((frame (sg-next-active sg (sg-ap sg))))
    (fef-instruction (aref (sg-regular-pdl sg) frame)
		     (rp-exit-pc (sg-regular-pdl sg) frame))))

;;; BAD-CDR-CODE
;;; Arg is where loser is.
(def-ucode-format-error bad-cdr-code error
  "A bad cdr-code was found in memory (at address ~O)."
  (sg-fixnum-contents sg (second ete)))  ;Can't use Lisp print since will err again

;;; DATA-TYPE-SCREWUP
;;; This happens when some internal data structure contains wrong data type.  arg is name.
;;; As it happens, all the names either start with a vowel or do if pronounced as letters
;;; Not continuable
(def-ucode-format-error data-type-screwup error
  "A bad data-type was found in the internal guts of an ~A."
  (second ete))

;;; STACK-FRAME-TOO-LARGE
(def-ucode-format-error stack-frame-too-large error
  "Attempt to make a stack frame larger than 256. words.")

;;; AREA-OVERFLOW
;;; arg is register containing area#
(def-ucode-format-error area-overflow error
  "Allocation in the /"~A/" area exceeded the maximum of ~D. words."
  (area-name (sg-fixnum-contents sg (second ete)))
  (area-maximum-size (sg-fixnum-contents sg (second ete))))

(defflavor dangerous-error () (error))
(defmethod (dangerous-error :dangerous-condition-p) () t)

;;; VIRTUAL-MEMORY-OVERFLOW
(def-ucode-format-error virtual-memory-overflow dangerous-error
  "You've used up all available virtual memory!")

;;; RCONS-FIXED
(def-ucode-error rcons-fixed (error cons-in-fixed-area)
  :property-list `(:area ,(area-name (sg-contents sg 'm-s)))
  :format-string "There was an attempt to allocate storage in the fixed area ~S."
  :format-args (list (area-name (sg-contents sg 'm-s))))

;;; REGION-TABLE-OVERFLOW
(def-ucode-format-error region-table-overflow dangerous-error
  "Unable to create a new region because the region tables are full.")

;;; RPLACD-WRONG-REPRESENTATION-TYPE
;;; arg is first argument to RPLACD
(def-ucode-format-error rplacd-wrong-representation-type error
  "Attempt to RPLACD a list which is embedded in a structure and therefore
cannot be RPLACD'ed.  The list is ~S."
  (sg-contents sg (second ete)))

;;;; Special cases.

;;; MAR-BREAK
;;; This code won't work if write-data is a DTP-NULL because of trap out of MAKUNBOUND

(def-ucode-error mar-break mar-break
  :direction (cdr (assq (second ete) '((write . :write) (read . :read))))
  :value (sg-contents sg 'pp)
  :object (let ((%mar-high -2) (%mar-low -1))
	    (%find-structure-header (sg-saved-vma sg)))
  :offset (let ((%mar-high -2) (%mar-low -1))
	    (%pointer-difference (sg-saved-vma sg)
				 (%find-structure-header (sg-saved-vma sg)))))

(defflavor mar-break (direction value object offset)
	   (condition)
  :gettable-instance-variables
  :initable-instance-variables)

(defmethod (mar-break :debugging-condition-p) () t)

(defmethod (mar-break :report) (stream)
  (if (eq direction ':write)
      (format stream
	      "The MAR has gone off because of an attempt to write ~S into offset ~O in ~S."
	      value offset object)
    (format stream "The MAR has gone off because of an attempt to read from offset ~O in ~S."
	    offset object)))

(defmethod (mar-break :ucode-proceed-types) ()
  (cond ((eq direction ':write)
	 '(:no-action :proceed-no-write))
	(t '(:no-action))))

(defmethod (mar-break :case :proceed-asking-user :no-action) (continuation ignore)
  "Proceed."
  (funcall continuation :no-action))

(defmethod (mar-break :case :proceed-asking-user :proceed-no-write) (continuation ignore)
  "Proceed, not changing the cell contents."
  (funcall continuation :proceed-no-write))

(defmethod (mar-break :case :proceed-ucode-with-args :no-action) (sg &rest ignore)
  ;; By simply returning without calling SG-PROCEED-MICRO-PC, the PGF-R will return
  (sg-funcall sg #'(lambda (vma md)				;Simulate the write
		     (let ((%mar-high -2) (%mar-low -1))	;Disable MAR
		       (rplaca vma md)))
	      (sg-saved-vma sg) (sg-regpdl-pop sg)))

(defmethod (mar-break :case :proceed-ucode-with-args :proceed-no-write) (&rest ignore)
  ;; By simply returning without calling SG-PROCEED-MICRO-PC, the PGF-R will return
  )

;;;; TRANS-TRAP

;;; Given the address on which a trans-trap occurred, determine where the contents
;;; of that address is stored now, and if it is a null pointer, what cell of which
;;; symbol was unbound.  The "symbol" can actually be a function-spec.
(defun trans-trap-decode (sg)
  (declare (values original-address current-address cell-type symbol))
  (let* ((original-address (sg-saved-vma sg))
	 (current-address (cell-location-in-stack-group original-address sg))
	 (cell-type nil)			;NIL means not a null pointer
	 symbol contents)
    (when (= (aref (sg-regular-pdl sg) (sg-regular-pdl-pointer sg)) dtp-null)
      (setq cell-type ':closure)		;Jumping to conclusions, default to this
      (setq contents (%make-pointer dtp-locative
				    (aref (sg-regular-pdl sg)
					  (1- (sg-regular-pdl-pointer sg))))
	    symbol (%find-structure-header contents))
      (cond ((symbolp symbol)
	     (case (%pointer-difference original-address symbol)
	       (1 (setq cell-type ':value))
	       (2 (setq cell-type ':function))))
	    ((and (consp symbol)
		  (= (%p-data-type symbol) dtp-list)
		  (si:%p-contents-eq (car symbol) ':method))
	     (setq cell-type ':function
		   symbol (si:meth-function-spec symbol)))
	    (t (setq cell-type nil))))
    (values original-address current-address cell-type symbol)))

(defun (:property trans-trap make-ucode-error-function) (ignore sg ete)
  (declare (ignore ete))
  (without-interrupts
    (multiple-value-bind (original-address current-address cell-type symbol)
	(trans-trap-decode sg)
      (make-instance (case cell-type
		       ((:value :closure)
			'unbound-variable)
		       (:function
			'undefined-function)
		       (t 'cell-contents-error))
		     :address original-address
		     :current-address current-address
		     :cell-type cell-type
		     :symbol symbol
		     :data-type (aref (sg-regular-pdl sg) (sg-regular-pdl-pointer sg))
		     :pointer (aref (sg-regular-pdl sg) (1- (sg-regular-pdl-pointer sg)))
		     :containing-structure (%find-structure-header original-address)
		     :condition-names (case cell-type
					(:value '(unbound-symbol))
					(:closure
					 (if (typep (%find-structure-header original-address)
						    'instance)
					     '(unbound-instance-variable)
					     '(unbound-closure-variable)))
					(:function `(undefined-function))
					(t '(bad-data-type-in-memory)))))))
  
(defflavor cell-contents-error
	(address current-address
	 cell-type symbol containing-structure
	 data-type pointer)
	(error)
  :gettable-instance-variables
  :initable-instance-variables)

(defflavor unbound-variable () (cell-contents-error))

(defmethod (unbound-variable :variable-name) () symbol)

(defmethod (unbound-variable :instance) ()
  (and (typep containing-structure 'instance) containing-structure))

(defflavor undefined-function () (cell-contents-error))

(defmethod (undefined-function :function-name) () symbol)

(defmethod (cell-contents-error :report) (stream &aux contents-changed verb)
  (setq contents-changed
	(or ( (%p-data-type current-address)
	       data-type)
	    ( (%p-pointer current-address)
	       pointer)))
  (setq verb (if contents-changed "was" "is"))
  (case cell-type
    (:value (format stream "The variable ~S ~A unbound." symbol verb))
    (:function (format stream "The function ~S ~A undefined." symbol verb))
    (:closure (if (typep containing-structure 'instance)
		  (format stream "The instance variable ~S ~A unbound in ~S."
			  symbol verb containing-structure)
		(format stream "The variable ~S ~A unbound (in a closure value-cell)."
			symbol verb)))
    (otherwise
     (format stream "The word #<~S ~S> was read from location ~O ~@[(in ~A)~]."
	     (q-data-types data-type)
	     pointer
	     (%pointer address)
	     (let ((area (%area-number address)))
	       (and area (area-name area)))))))

(defmethod (cell-contents-error :after :print-error-message)
	   (sg brief stream &aux prop contents-changed)
  (unless brief
    (setq contents-changed
	  (or ( (%p-data-type current-address)
		 data-type)
	      ( (%p-pointer current-address)
		 pointer)))
    (case cell-type
      (:value (if contents-changed
		  (cell-contents-error-print-new-contents-1 stream "It now has the value"
							    current-address)))
      (:function (if contents-changed
		     (cell-contents-error-print-new-contents-1
		       stream "It now has the definition"
		       current-address))
		 (and (symbolp symbol)
		      (get symbol 'compiler::qintcmp)
		      (let ((fn (rp-function-word (sg-regular-pdl sg)
						  (sg-out-to-interesting-active
						    sg error-locus-frame))))
			(format stream
				"Note: ~S is supported as a function when used in compiled code.~%"
				symbol)
			(if (consp fn)
			    (format stream
				    "You may have evaluated the definition of ~S, which is now not compiled.~%"
				    (function-name fn)))))
		 (and (symbolp symbol)
		      (setq prop (getl symbol '(expr fexpr macro subr fsubr lsubr autoload)))
		      (format stream "Note: the symbol has a ~S property, ~
				so this may be a Maclisp compatibility problem.~%"
			      (car prop))))
      (:closure (if contents-changed
		    (cell-contents-error-print-new-contents-1 stream "It now has the value"
							      current-address)))
      (otherwise
       (if contents-changed
	   (cell-contents-error-print-new-contents-1
	     stream "The cell now contains" current-address))))))

(defun cell-contents-error-print-new-contents-1 (stream cell-description address)
  (if (%p-contents-safe-p address)
      (format stream "~A ~S.~%" cell-description (%p-contents-offset address 0))
    (format stream "~A #<~S ~S>.~%" cell-description
	    (q-data-types (%p-data-type address))
	    (%p-pointer address))))

;;; Some people would rather not spend the time for this feature, so let them turn it off
(defconst enable-trans-trap-dwim t
  "Non-NIL means look spontaneously in other packages on undefined function or variable error.")

;;; If problem is symbol in wrong package, offer some dwimoid assistance.
(defmethod (cell-contents-error :debugger-command-loop)
	   (error-sg &optional (error-object self))
  (declare (special error-object))
  (catch 'quit
    (catch-error-restart ((sys:abort error) "Return to debugger command loop.")
      (and enable-trans-trap-dwim
	   (send error-object :proceed-asking-user :package-dwim
		 'proceed-error-sg 'read-object))))
  nil)

(defmethod (cell-contents-error :case :proceed-asking-user :package-dwim)
	   (continuation ignore &aux cell new-val)
  "Look for symbols with the same name but in different packages."
  (and (symbolp symbol)
       (setq cell (assq cell-type '((:value boundp symeval)
				    (:function fdefinedp fdefinition))))
       (car (setq new-val
		  (sg-funcall error-sg 'cell-contents-error-dwimify symbol cell terminal-io)))
       (funcall continuation :new-value (cadr new-val))))

;;; CELL is a list (symbolic-name dwimify-definition-type value-extractor)
(defun cell-contents-error-dwimify (sym cell *query-io*)
  (declare (return-list success-p new-value new-symbol))
  (let ((dwim-value (dwimify-package-0 sym (second cell))))
    (send *query-io* :fresh-line)
    (and dwim-value (values t (funcall (third cell) dwim-value) dwim-value))))

(defmethod (cell-contents-error :user-proceed-types) (proceed-types)
  (remq ':new-value proceed-types))

(defmethod (cell-contents-error :case :proceed-asking-user :no-action)
	   (continuation read-object-function)
  "Proceed, using current contents if legal, or reading replacement value."
  (if (not (%p-contents-safe-p current-address))
      ;; Location still contains garbage, get a replacement value.
      (send self :proceed-asking-user :new-value continuation read-object-function)
    (funcall continuation :no-action)))

(defmethod (cell-contents-error :case :proceed-asking-user :new-value)
	   (continuation read-object-function)
  "Use the value of an expression you type."
  (let ((prompt "Form to evaluate and use instead of cell's contents:~%"))
    (case cell-type
      (:value
       (setq prompt (format nil "Form to evaluate and use instead of ~S's value:~%"
			    symbol)))
      (:function
       (setq prompt (format nil
			    "Form to evaluate and use instead of ~S's function definition:~%"
			    symbol))))
    (funcall continuation :new-value (funcall read-object-function :eval-read prompt))))

(defmethod (cell-contents-error :case :proceed-asking-user :store-new-value)
	   (continuation read-object-function)
  "Use the value of an expression you type, and store that value."
  (let ((value (funcall read-object-function :eval-read
		 (or (case cell-type
		       (:value
			(format nil "Form to evaluate and ~S ~S to: " 'setq symbol))
		       (:function
			(format nil "Form to evaluate and FSET ~S to: " 'fset symbol)))
		     "Form to evaluate and store back: "))))
    (funcall continuation :store-new-value value)))

(defmethod (cell-contents-error :ucode-proceed-types) ()
  (if (memq cell-type '(:value :function))
      '(:no-action :new-value :store-new-value :package-dwim)
    '(:no-action :new-value :store-new-value)))

(defmethod (cell-contents-error :case :proceed-ucode-with-args :store-new-value) (sg value)
  (%p-store-contents current-address value)
  (sg-regpdl-push value sg)
  (sg-proceed-micro-pc sg 'trans-trap-restart))

(defmethod (cell-contents-error :case :proceed-ucode-with-args :new-value) (sg value)
  (sg-regpdl-push value sg)
  (sg-proceed-micro-pc sg 'trans-trap-restart))

;;; This has to exist, but it's not intended to ever be used,
;;; so do the same thing as :NO-ACTION if it ever does get used.
(defmethod (cell-contents-error :case :proceed-ucode-with-args :package-dwim) (sg)
  (sg-regpdl-push 0 sg)
  ;; Transfer the current contents to what MD will be got from.
  (%blt-typed current-address (sg-locate sg 'pp) 1 0)
  (sg-proceed-micro-pc sg 'trans-trap-restart))

(defmethod (cell-contents-error :case :proceed-ucode-with-args :no-action) (sg)
  (sg-regpdl-push 0 sg)
  ;; Transfer the current contents to what MD will be got from.
  (%blt-typed current-address (sg-locate sg 'pp) 1 0)
  (sg-proceed-micro-pc sg 'trans-trap-restart))

;;;; FUNCTION-ENTRY
;;; Special case.
;;; The ucode kindly leaves the M-ERROR-SUBSTATUS pushed onto the
;;; regular pdl so that we can find it.
;;; The meanings of %%M-ESUBS-BAD-QUOTED-ARG, %%M-ESUBS-BAD-EVALED-ARG
;;; and %%M-ESUBS-BAD-QUOTE-STATUS are not clear, as they are not used
;;; by the microcode.

(defun function-entry-error (sg)
  (loop with error-code = (aref (sg-regular-pdl sg) (sg-regular-pdl-pointer sg))
	for symbol in '(%%m-esubs-too-few-args %%m-esubs-too-many-args %%m-esubs-bad-dt)
	for flag in '(too-few-arguments too-many-arguments )
	when (ldb-test (symbol-value symbol) error-code)
	  return flag))

(defun (:property function-entry make-ucode-error-function) (ignore sg ignore)
  (make-instance 'function-entry-error
		 :function (aref (sg-regular-pdl sg) (sg-ap sg))
		 :argument-list (cdr (get-frame-function-and-args sg (sg-ap sg)))
		 :nargs (rp-number-args-supplied (sg-regular-pdl sg) (sg-ap sg))
		 :condition-names (list (function-entry-error sg))))

(defsignal-explicit sys:too-few-arguments (function-entry-error sys:too-few-arguments)
  (ignore function nargs argument-list)
  "FUNCTION was called with only NARGS args, which were ARGUMENT-LIST."
  :function function :nargs nargs :argument-list argument-list)

(defsignal-explicit sys:too-many-arguments (function-entry-error sys:too-many-arguments)
  (ignore function nargs argument-list)
  "FUNCTION was called with only NARGS args, which were ARGUMENT-LIST."
  :function function :nargs nargs :argument-list argument-list)

;Not patched in system 98 - omits AUTOMATIC-ABORT-DEBUGGER-MIXIN
;which has been eliminated from the source.
(defflavor function-entry-error
	(function argument-list nargs)
	(error)
  :gettable-instance-variables
  :initable-instance-variables)

(defmethod (function-entry-error :report) (stream)
  (cond
    ((memq 'too-few-arguments condition-names)
     (format stream "Function ~S called with only ~D argument~1@*~P."
	     (function-name function) nargs))
    ((memq 'too-many-arguments condition-names)
     (format stream "Function ~S called with too many arguments (~D)."
	     (function-name function) nargs))
    ((memq ' condition-names)
     (format stream "Function ~S called with an argument of bad data type."
	     (function-name function)))))

(defmethod (function-entry-error :ucode-proceed-types) ()
  (if (memq 'too-few-arguments condition-names)
      '(:additional-arguments :fewer-arguments :new-argument-list)
    '(:fewer-arguments :additional-arguments :new-argument-list)))

(defmethod (function-entry-error :user-proceed-types) (proceed-types)
  (let ((tem (copylist proceed-types))
	first)
    (dolist (p tem)
      (if (memq p '(:additional-arguments :fewer-arguments :new-argument-list))
	  (return (setq first p))))
    ;; Get rid of all occurrences of those three, except the first one.
    (if first
	(setf (cdr (memq first tem))
	      (delq ':additional-arguments
		    (delq ':fewer-arguments
			  (delq ':new-argument-list
				(cdr (memq first tem)))))))
    tem))

(defmethod (function-entry-error :case :proceed-asking-user :additional-arguments)
	   (continuation read-object-function)
  "Try again with additional arguments.  You type expressions for them."
  (send self :proceed-asking-user :new-argument-list continuation read-object-function))

(defmethod (function-entry-error :case :proceed-asking-user :fewer-arguments)
	   (continuation read-object-function)
  "Try again, dropping some of the arguments.  You must confirm."
  (send self :proceed-asking-user :new-argument-list continuation read-object-function))

(defmethod (function-entry-error :case :proceed-asking-user :new-argument-list)
	   (continuation read-object-function)
  (let* ((-function- (send self :function))
	 (-argument-list- (send self :argument-list))
	 (-nargs- (send self :nargs))
	 (form (cons -function- -argument-list-))
	 (args-info (args-info -function-))
	 (args-wanted (ldb %%arg-desc-min-args args-info))
	 (rest-flag (ldb-test %%arg-desc-any-rest args-info))
	 (max-args (ldb %%arg-desc-max-args args-info))
	 new-args)
    ;; Function may have been redefined to take the supplied number of arguments
    ;; so don't look at the original error, but check everything again.
    (cond ((< -nargs- args-wanted)
	   (do ((i -nargs- (1+ i)))
	       ((unless rest-flag (eq i max-args)))
	     (multiple-value-bind (value flag)
		 (funcall read-object-function
			  (if ( i args-wanted)
			      :eval-read-or-end :eval-read)
			  (if ( i args-wanted)
			      "Arg ~D~A, or ~C: " "Arg ~D~A: ")
			  i
			  (format:output nil (display-arg-name " (~A)" -function- i))
			  #/End)
	       (if flag (return))
	       (setq new-args
		     (nconc new-args
			    (ncons value)))))
	   (funcall continuation :new-argument-list
		    (append (cdr form) new-args)))
	  ((or ( -nargs- max-args)
	       (ldb-test %%arg-desc-any-rest args-info))
	   (if (funcall read-object-function '(:fquery) "Try ~S again? " form)
	       (funcall continuation :new-argument-list (cdr form))))
	  ((funcall read-object-function '(:fquery)
		    "Call again with the last ~[~1;~:;~:*~D ~]argument~:P dropped? "
		    (- -nargs- max-args))
	   (funcall continuation :new-argument-list
		    (firstn max-args (cdr form)))))))

(defmethod (function-entry-error :case :proceed-asking-user :return-value)
	   (continuation read-object-function)
  "Pretend the function ran; you type an expression for the value it (supposedly) returns."
  (funcall continuation :return-value
	   (funcall read-object-function :eval-read
		    "Form to evaluate and return from ~S: "
		    (function-name (send self :function)))))

(defmethod (function-entry-error :case :proceed-ucode-with-args :fewer-arguments)
	   (sg n)
  (send self :proceed-ucode-with-args :new-argument-list sg
	(firstn n argument-list)))

(defmethod (function-entry-error :case :proceed-ucode-with-args :additional-arguments)
	   (sg args)
  (send self :proceed-ucode-with-args :new-argument-list sg
	(append argument-list (copylist args))))

(defmethod (function-entry-error :case :proceed-ucode-with-args :new-argument-list)
	   (sg arguments &aux (form (cons function arguments)))
  (let* ((frame (sg-ap sg))
	 (error-locus-frame (sg-ap sg))
	 (current-frame (sg-ap sg))
	 (innermost-visible-frame (sg-ap sg)))
    ;; If we haven't quit before getting here, he wants to proceed and FORM is set up
    (sg-unwind-to-frame-and-reinvoke sg frame form)
    (leaving-error-handler)
    (without-interrupts
      (and error-handler-running
	   (free-second-level-error-handler-sg current-stack-group))
      (stack-group-resume sg nil))))

(defflavor dont-clear-input-ucode-breakpoint ()
	   (condition))

(defmethod (dont-clear-input-ucode-breakpoint :maybe-clear-input) (stream)
  (declare (ignore stream))
  nil)

(defmethod (dont-clear-input-ucode-breakpoint :print-error-message-prefix) (sg brief stream)
  (declare (ignore sg brief))
  (princ ">> " stream))

(defmethod (dont-clear-input-ucode-breakpoint :ucode-proceed-types) ()
  '(:no-action))

(defmethod (dont-clear-input-ucode-breakpoint :case :proceed-ucode-with-args :no-action)
	   (sg &rest ignore)
  (sg-proceed-micro-pc sg nil))

(defmethod (dont-clear-input-ucode-breakpoint :case :proceed-asking-user :no-action)
	   (continuation ignore)
  "Proceed."
  (format t " Continue from break.~%")
  (funcall continuation :no-action))

(defmethod (dont-clear-input-ucode-breakpoint :debugging-condition-p) ()
  t)

(defsignal trace-breakpoint step-break-error ()
  "Used by (TRACE (FOO ERROR))")

(def-ucode-error breakpoint step-break-error
  :format-string "Breakpoint")

(def-ucode-error step-break step-break-error
  :format-string "Step break")

(defflavor step-break-error () (dont-clear-input-ucode-breakpoint))

(defmethod (step-break-error :ucode-proceed-types) ()
  '(:no-action))

(def-ucode-error call-trap call-trap-error
  :function (rp-function-word (sg-regular-pdl sg) (sg-ipmark sg))
  :catch-value (aref (sg-regular-pdl sg) (+ (sg-ipmark sg) 2)))

(defflavor call-trap-error (function catch-value)
	   (dont-clear-input-ucode-breakpoint)
  :gettable-instance-variables
  :initable-instance-variables)

(defun (:property call-trap enter-error-handler) (sg ignore)
  (let ((innermost-visible-frame (sg-ipmark sg)))	;Make frame being entered visible.
    ;; Trap on exit from this frame -- unless it is a *CATCH.
    ;; In that case, it is redundant to trap again,
    ;; and suspected of causing bugs.
    (if (neq (rp-function-word (sg-regular-pdl sg) (sg-ipmark sg))
	     #'*catch)
	(setf (rp-trap-on-exit (sg-regular-pdl sg) innermost-visible-frame) 1))))

(defmethod (call-trap-error :around :find-current-frame) (cont mt args sg)
  (let ((ipmark (fourth (symeval-in-stack-group 'ucode-error-status sg))))
    (multiple-value-bind (nil nil innermost-frame innermost-visible-p)
	(lexpr-funcall-with-mapping-table cont mt args)
      (values ipmark ipmark innermost-frame innermost-visible-p))))

(defmethod (call-trap-error :report) (stream)
  (if (neq function #'*catch)
      (format stream "Break on entry to function ~S."
	      (function-name function))
    (format stream "Break on call to *CATCH (about to do normal exit from *CATCH frame); ~
value is ~S." catch-value)))

(def-ucode-error exit-trap exit-trap-error
  :function (rp-function-word (sg-regular-pdl sg) (sg-ap sg))
  :values (sg-frame-value-list sg (sg-ap sg)))

(defflavor exit-trap-error (function values)
	   (dont-clear-input-ucode-breakpoint)
  :gettable-instance-variables
  :initable-instance-variables)

(defun (:property exit-trap enter-error-handler) (sg ignore)
  ;; Don't catch this trap again if user tries to return, etc.
  (setf (rp-trap-on-exit (sg-regular-pdl sg) (sg-ap sg)) 0)
  (let ((innermost-visible-frame (sg-ap sg)))
    ;; Add our last value onto list of all multiple values returned
    ;; so the user sees them all in the same place.
    (sg-return-additional-value sg innermost-visible-frame (sg-ac-t sg))))

(defmethod (exit-trap-error :around :find-current-frame) (cont mt args sg)
  (let ((ap (third (symeval-in-stack-group 'ucode-error-status sg))))
    (multiple-value-bind (nil nil innermost-frame innermost-visible-p)
	(lexpr-funcall-with-mapping-table cont mt args)
      (values ap ap innermost-frame innermost-visible-p))))

(defmethod (exit-trap-error :report) (stream)
  (format stream "Break on exit from ~S." (function-name function)))

(defmethod (exit-trap-error :after :print-error-message) (sg brief stream)
  sg brief
  (if (null values)
      (format stream " No values being returned.~%")
    (format stream " Values being returned are:")
    (let ((*print-length* error-message-prinlength)
	  (*print-level* error-message-prinlevel))
      (dolist (val values)
	(format stream "~%    ~S" val)))
    (terpri)))

(defmethod (exit-trap-error :case :proceed-ucode-with-args :no-action) (sg &rest ignore)
  ;; Un-return the last returned value and put it in M-T to be returned over.
  ;; This is a no-op if we are not feeding multiple values
  ;; since the value just comes from M-T in that case.
  (setf (sg-ac-t sg) (sg-discard-last-value sg (sg-ap sg)))
  (sg-proceed-micro-pc sg nil))

;;; THROW-TRAP is used for both exit trap and tag not seen, starting in UCADR 260.
;;; If M-E contains NIL, the tag was not seen.
(defun (:property throw-trap make-ucode-error-function) (ignore sg ignore)
  (cond ((sg-contents sg 'm-e)
	 ;; If tag was found, it must be trap-on-exit.
	 (make-instance 'throw-exit-trap-error
			:function (function-name (car (%p-contents-as-locative
							(locf (sg-ac-d sg)))))))
	(t
	 ;; Otherwise tag was not found.
	 (make-instance 'throw-tag-not-seen-error
			:tag (sg-ac-a sg)
			:value (sg-ac-t sg)
			:count (sg-ac-b sg)
			:action (sg-ac-c sg)))))

(defun (:property throw-trap enter-error-handler) (sg ignore)
  (if (sg-contents sg 'm-e)
      ;; Do this only for trap-on-exit, not for tag not seen.
      (let ((cur-frame
	      (- (%pointer-difference (%p-contents-as-locative (locf (sg-ac-d sg)))
				      (sg-regular-pdl sg))
		 2)))
	(setf (rp-trap-on-exit (sg-regular-pdl sg) cur-frame) 0))))

;;; THROW-EXIT-TRAP was used up to system 97.
;
;(def-ucode-error throw-exit-trap throw-exit-trap-error
;  :function (function-name (car (%p-contents-as-locative (locf (sg-ac-d sg))))))
;
;(defun (:property throw-exit-trap enter-error-handler) (sg ignore)
;  (let ((cur-frame
;	  (- (%pointer-difference (%p-contents-as-locative (locf (sg-ac-d sg)))
;				  (sg-regular-pdl sg))
;	     2)))
;    (setf (rp-trap-on-exit (sg-regular-pdl sg) cur-frame) 0)))

(defflavor throw-exit-trap-error (function) (dont-clear-input-ucode-breakpoint)
  :gettable-instance-variables
  :initable-instance-variables)

(defmethod (throw-exit-trap-error :around :find-current-frame)
	   (cont mt args ignore)
  (multiple-value-bind (x y z)
      (around-method-continue cont mt args)
    (values x y z t)))

(defmethod (throw-exit-trap-error :report) (stream)
  (format stream "Break on throw through marked call to ~S." function))

;;; List problems with currently-loaded error table
(defun list-problems ()
  (let ((errors-with-no-error-messages nil)
	(missing-restart-tags nil)
	(argtyp-unknown-types nil)
	(tem))
    (dolist (ete error-table)
      (or (get (setq tem (second ete)) 'make-ucode-error-function)
	  (memq tem errors-with-no-error-messages)
	  (push tem errors-with-no-error-messages))
      (if (eq tem 'argtyp)
	  (let ((type (third ete)))
	    (if (symbolp type)
		(setq type (ncons type)))
	    (when (dolist (type type)
		    (or (type-defined-p type)
			(assq type description-type-specs)
			(return t)))
	      (pushnew (third ete) argtyp-unknown-types))))
      (and (setq tem (assq tem			;Anything that calls SG-PROCEED-MICRO-PC
			   '((argtyp . 5) (subscript-oob . 4))))
	   (setq tem (nth (cdr tem) ete))
	   (progn (if (consp tem) (setq tem (cadr tem))) t)
	   (neq tem 'fall-through)
	   (not (assq tem restart-list))
	   (pushnew tem missing-restart-tags)))
    (and errors-with-no-error-messages
	 (format t "~&Errors with no error messages: ~S" errors-with-no-error-messages))
    (and argtyp-unknown-types
	 (format t "~&ARGTYP types not defined for TYPEP: ~S" argtyp-unknown-types))
    (and missing-restart-tags
	 (format t "~&Missing RESTART tags: ~S" missing-restart-tags))))

(defun type-defined-p (type)
  (let ((type1 (if (consp type) (car type) type)))
    (and (symbolp type1)
	 (or (getl type1 'si:(type-predicate type-expander type-alias-for
		              flavor defstruct-description defstruct-named-p))
	     (rassq type si:type-of-alist) (rassq type si:typep-one-arg-alist)
	     (and (fboundp 'class-symbolp) (class-symbolp type1))))))

(defvar allow-pdl-grow-message t)
(defvar pdl-grow-ratio 1.5s0
  "Ratio by which to increase the size of a pdl, after overflow.")

(defun require-pdl-room (regpdl-words specpdl-words &aux cell)
  "Make sure of a minimum amount of free space in the running stack group.
REGPDL-WORDS is the desired number of free regular pdl words, beyond the
 current stack pointer, and SPECPDL-WORDS is for the special pdl.
The stacks are made at least that large if they are not already."
  (process-run-function "Grow pdls" #'sg-grow-pdl-on-request
			current-stack-group (locf cell) regpdl-words specpdl-words)
  (process-wait "Grow pdls" #'car (locf cell)))

(defun sg-grow-pdl-on-request (sg cell-pointer regpdl-words specpdl-words)
  (sg-maybe-grow-pdls sg nil regpdl-words specpdl-words t)
  (setf (contents cell-pointer) t))

;;; Make a stack-group's pdls larger if necessary
;;; Note that these ROOM numbers need to be large enough to avoid getting into
;;; a recursive trap situation, which turns out to be mighty big because footholds
;;; are large and because the microcode is very conservative.
(defun sg-maybe-grow-pdls (sg &optional (message-p allow-pdl-grow-message)
					regular-room special-room
					inhibit-error
			   &aux (rpp (sg-regular-pdl-pointer sg))
				(rpl (sg-regular-pdl-limit sg))
				(spp (sg-special-pdl-pointer sg))
				(spl (sg-special-pdl-limit sg))
				tem new-size new-limit did-grow)
  "Increase the size of SG's pdls if they are close to being full."
  (unless regular-room (setq regular-room #o2000))
  (unless special-room (setq special-room #o400))
  (when (> (setq tem (+ rpp regular-room)) rpl)
    (setq new-size (max (fix (* pdl-grow-ratio (array-length (sg-regular-pdl sg))))
			(+ tem #o100)))
    (setq new-limit (- new-size #o100))
    (and message-p
	 (format error-output "~&[Growing regular pdl of ~S from ~S to ~S]~%"
		 sg rpl new-limit))
    (setf (sg-regular-pdl sg) (sg-grow-pdl (sg-regular-pdl sg) rpp new-size))
    (setf (sg-regular-pdl-limit sg) new-limit)
    (setq did-grow ':regular))
  (when (> (setq tem (+ spp special-room)) spl)
    (setq new-size (max (fix (* pdl-grow-ratio (array-length (sg-special-pdl sg))))
			(+ tem #o100)))
    (setq new-limit (- new-size #o100))
    (and message-p
	 (format error-output "~&[Growing special pdl of ~S from ~S to ~S]~%"
		 sg spl new-limit))
    (let ((osp (locf (aref (sg-special-pdl sg) 0))))
      (setf (sg-special-pdl sg) (sg-grow-pdl (sg-special-pdl sg) spp new-size))
      (setf (sg-special-pdl-limit sg) new-limit)
      (unless (eq osp (locf (aref (sg-special-pdl sg) 0)))
	(relocate-locatives-to-specpdl (sg-regular-pdl sg)
				       (sg-regular-pdl-pointer sg)
				       osp
				       (locf (aref (sg-special-pdl sg) 0))
				       (sg-special-pdl-pointer sg))))
    (unless did-grow
      (setq did-grow ':special)))
  (when (and did-grow (not inhibit-error))
    (sg-funcall-no-restart sg 'cerror :grow-pdl nil 'pdl-overflow-error
						    :pdl-name did-grow)))

;;; If the SPECPDL has been forwarded, update pointers to it from the regular pdl.
;;; The third and fourth args are locatives to the first slot in the old and new specpdl.
(defun relocate-locatives-to-specpdl (regpdl regpdl-pointer
				      old-specpdl-start new-specpdl-start
				      specpdl-pointer)
  (do ((i 0 (1+ i)))
      ((> i regpdl-pointer))
    (and (location-boundp (locf (aref regpdl i)))
	 (locativep (aref regpdl i))
	 (let ((index (%pointer-difference (aref regpdl i)
					   old-specpdl-start)))
	   (and ( 0 index specpdl-pointer)
		(setf (aref regpdl i)
		      (%make-pointer-offset dtp-locative new-specpdl-start index)))))))

;;; Make a new array, copy the contents, store forwarding pointers, and return the new
;;; array.  Also we have to relocate the contents of the array as we move it because the
;;; microcode does not always check for forwarding pointers (e.g. in MKWRIT when
;;; returning multiple values).
(defun sg-grow-pdl (pdl pdl-ptr new-size
		    &aux new-pdl tem1 area)
  (setq pdl (follow-structure-forwarding pdl))
  (if ( new-size (array-length pdl))
      ;; Big enough, just adjust limit
      pdl
    (cond ((= (setq area (%area-number pdl)) linear-pdl-area)	;Stupid crock
	   (setq area pdl-area))				; with non-extendible areas
	  ((= area linear-bind-pdl-area)
	   (setq area working-storage-area)))
    (setq new-pdl (make-array new-size :type (array-type pdl)
				       :area area
				       :leader-length (array-leader-length pdl)))
    (dotimes (i (array-leader-length pdl))
      (store-array-leader (array-leader pdl i) new-pdl i))
    (%blt-typed (aloc pdl 0) (aloc new-pdl 0)
		(1+ pdl-ptr) 1)
    (do ((n pdl-ptr (1- n))
	 (to-p (aloc new-pdl 0) (%make-pointer-offset dtp-locative to-p 1))
	 (base (aloc pdl 0)))
	((minusp n))
      (select (%p-data-type to-p)
	((dtp-fix dtp-small-flonum dtp-u-entry))	;The only inum types we should see
	((dtp-header-forward dtp-body-forward)
	 (ferror nil "Already forwarded? -- get help"))
	(otherwise
	 (setq tem1 (%pointer-difference (%p-contents-as-locative to-p) base))
	 (and ( 0 tem1 pdl-ptr)
	      (%p-store-pointer to-p (aloc new-pdl tem1))))))
    (structure-forward pdl new-pdl)
    new-pdl))

(defun current-function-name (&aux dummy)
  "Returns the name of the function from which this one is called.
At compile time, it is open-coded to return the name of the function being compiled.
If called from the interpreter, it looks for a NAMED-LAMBDA on the stack."
  (let* ((rp (sg-regular-pdl current-stack-group))
	 (frame (%pointer-difference (locf dummy) (aloc rp 1))))
    (do ((f frame (sg-next-active current-stack-group f))
	 tem)
	((null f))
      (and (consp (rp-function-word rp f))
	   (neq (setq tem (function-name (rp-function-word rp f)))
		(rp-function-word rp f))
	   (return tem)))))

(defun (:property current-function-name compiler:p1) (ignore)
  `',compiler::name-to-give-function)

(compile-flavor-methods
 condition
 error
 warning
 ferror
;common-lisp-cerror
 multiple-cerror
 unclaimed-message-error
 undefined-keyword-argument
 dangerous-error
 parse-error
 end-of-file
 read-end-of-file
 package-not-found
 package-name-conflict
 disk-error
 redefinition
 network-error
 local-network-error
 remote-network-error
 bad-connection-state
 connection-error
 break
 arg-type-error
 wrong-type-argument-error
 arithmetic-error
 failed-assertion
 fixnum-overflow-error
 floating-exponent-underflow-error
 floating-exponent-overflow-error
 bad-array-error
 array-number-dimensions-error
 subscript-error
 invalid-function
 throw-tag-not-seen-error
 turd-alert-error
 pdl-overflow-error
 mar-break
 cell-contents-error
 unbound-variable
 undefined-function
 function-entry-error
 dont-clear-input-ucode-breakpoint
 step-break-error
 call-trap-error
 exit-trap-error
 throw-exit-trap-error
 )

(defconst abort-object (make-condition 'sys:abort "Abort.")
  "A condition-object for condition SYS:ABORT, used every time we want to abort.")

