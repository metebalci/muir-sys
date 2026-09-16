;;; -*- Mode:LISP; Package:EH; Lowercase:T; Base:10; Readtable:ZL -*-

;;;; Stepping commands.

;; C-X: Control the trap-on-exit bits of frames.
(defun com-toggle-frame-trap-on-exit (sg ignore &optional ignore)
  "Toggles whether we trap on exit from this frame."
  (let ((trap-p (not (trap-on-exit-p sg current-frame))))
    (set-trap-on-exit sg current-frame trap-p)
    (terpri)
    (princ (if (trap-on-exit-p sg current-frame) "Break" "Do not break"))
    (princ " on exit from this frame.")))

(defun set-trap-on-exit (sg frame trap-p)
  "Set or clear trap on exit from FRAME in SG.  TRAP-P = T means set, else clear."
  (let ((rp (sg-regular-pdl sg)))
    (if (eq (rp-function-word rp frame) #'*catch)
	(setq trap-p nil))
    (setf (rp-trap-on-exit rp frame) (if trap-p 1 0)))
  trap-p)

(defun trap-on-exit-p (sg frame)
  "T if FRAME in SG is set to trap on being exited."
  (not (zerop (rp-trap-on-exit (sg-regular-pdl sg) frame))))

;; Meta-X
(defun com-set-all-frames-trap-on-exit (sg ignore &optional ignore)
  "Makes all outer frames trap on exit."
  (do ((frame current-frame (sg-next-active sg frame)))
      ((null frame))
    (set-trap-on-exit sg frame t))
  (format t "~%Break on exit from this frame and all outer active frames."))

;; Control-Meta-X
(defun com-clear-all-frames-trap-on-exit (sg ignore &optional ignore)
  "Clears the trap-on-exit flag for all outer frames."
  (do ((frame current-frame (sg-next-open sg frame)))
      ((null frame))
    (set-trap-on-exit sg frame nil))
  (format t "~%Do not break on exit from this frame and all outer frames."))

;; Control-D
(defun com-proceed-trap-on-call (sg error-object &optional ignore)
  "Proceeds from this error (if that is possible) and traps on the next function call."
  (setf (sg-flags-trap-on-call sg) 1)
  (format t "Trap on next function call. ")
  (com-proceed sg error-object))

;; Meta-D
(defun com-toggle-trap-on-call (sg ignore &optional ignore)
  "Toggle whether to trap on next function call."
  (setf (sg-flags-trap-on-call sg) (logxor 1 (sg-flags-trap-on-call sg)))
  (terpri)
  (princ (if (zerop (sg-flags-trap-on-call sg)) "Do not break" "Break"))
  (princ " on next function call."))

(setf (documentation 'com-number 'function)
      "Used to give a numeric argument to debugger commands.")
	   
;;;; Breakon
(defvar breakon-functions nil
  "List of all function-specs that have BREAKONs.")

(defun breakon (&optional function-spec (condition t))
  "Break on entry to FUNCTION-SPEC, if CONDITION evaluates non-NIL.
If called repeatedly for one function-spec with different conditions,
a break will happen if any of the conditions evaluates non-NIL.

With no args, returns a list of function specs that have had
break-on-entry requested with BREAKON."
  (if (null function-spec)
      breakon-functions
    (setq function-spec (dwimify-arg-package function-spec 'function-spec))
    (breakon-init function-spec)
    (setq condition (si:rename-within-new-definition-maybe function-spec condition))
    (let* ((spec1 (si:unencapsulate-function-spec function-spec 'breakon)))
      (uncompile spec1 t)
      (let* ((def (fdefinition spec1))
	     (default-cons-area background-cons-area)
	     ;; Find our BREAKON-THIS-TIME.
	     ;; def looks like:
	     ;;   (named-lambda (foo debugging-info) arglist
	     ;;	    (si::encapsulation-let ((arglist (si::encapsulation-list* arglist)))
	     ;;	       (declare (special arglist))
	     ;;        (breakon-this-time conditions unencapsulated-function arglist)))
	     (defn-data (car (si::encapsulation-body def)))
	     (slot-loc (cadr defn-data)))	;Within that, find ptr to list of conditions.
	(or (member condition (cdr slot-loc)) (push condition (cdr slot-loc)))))
    (if compile-encapsulations-flag
	(compile-encapsulations function-spec 'breakon))
    function-spec))

(defun unbreakon (&optional function-spec (condition t))
  "Remove break on entry to FUNCTION-SPEC, or all functions if no arg.
If CONDITION is specified, we remove only that condition for breaking;
if other conditions have been specified with BREAKON on this function,
the other conditions remain in effect."
  (and function-spec
       (setq function-spec (dwimify-arg-package function-spec 'function-spec)))
  (let* ((spec1 (and function-spec (si:unencapsulate-function-spec function-spec 'breakon))))
    (cond ((null function-spec)
	   (mapc #'unbreakon breakon-functions))
	  ((eq condition t)
	   (fdefine spec1 (fdefinition (si:unencapsulate-function-spec spec1 '(breakon))))
	   (setq breakon-functions (delete function-spec breakon-functions))
	   function-spec)
	  ((neq spec1 (si:unencapsulate-function-spec spec1 '(breakon)))
	   (uncompile spec1 t)
	   (let* ((def (fdefinition spec1))
		  ;; Find our BREAKON-NEXT-TIME.
		  ;; def looks like:
		  ;;   (named-lambda (foo debugging-info) arglist
		  ;;	  (si::encapsulation-let ((arglist (si::encapsulation-list* arglist)))
		  ;;	    (declare (special arglist))
		  ;;        (breakon-this-time conditions unencapsulated-function arglist)))
		  (defn-data (car (si::encapsulation-body def)))
		  (slot-loc (cadr defn-data)))	;Within that, find ptr to list of conditions.
	     (setf (cdr slot-loc)
		   (delete condition (cdr slot-loc)))
	     (cond ((null (cdr slot-loc))
		    (fdefine spec1
			     (fdefinition (si:unencapsulate-function-spec spec1 '(breakon))))
		    (setq breakon-functions (delete function-spec breakon-functions)))
		   (compile-encapsulations-flag
		    (compile-encapsulations function-spec 'breakon))))
	   function-spec))))

;;; Make a specifed function into an broken-on function
;;; (with no conditions yet) if it isn't one already.
(defun breakon-init (function-spec)
  (let ((default-cons-area background-cons-area)
	(spec1 (si:unencapsulate-function-spec function-spec 'breakon)))
    (when (eq spec1 (si:unencapsulate-function-spec spec1 '(breakon)))
      (si:encapsulate spec1 function-spec 'breakon
		      ;; Must cons the (OR) afresh -- it gets RPLAC'd.
		      `(breakon-this-time ,(list 'or)
					  ,si::encapsulated-function
					  arglist))
      (push function-spec breakon-functions))))

(defun breakon-this-time (break-condition function args)
  (and break-condition (setf (ldb %%m-flags-trap-on-call %mode-flags) 1))
  ;; The next call ought to be the function the user is trying to call.
  ;; That will be so only if this function is compiled.
  (apply function args))
