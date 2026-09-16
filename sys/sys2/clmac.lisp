;;; -*- Mode:LISP; Readtable:T; Package:SYSTEM-INTERNALS; Base:8; Lowercase:T -*-

;;; this file contains macro definitions for zetalisp special forms
;;; for use with the common-lisp MACRO-FUNCTION function.

;;; Note that many special forms have been punted as they are either
;;; too obscure or kludgey or too implementation-dependant to make
;;; any sense to a common-lisp program in any case.

;;;; list of all fexprs in the source as of 23-Apr-84 09:12:05
;;; ;  perviously defined, or commonlisp special form
;;; *  defined in this file
;;; ~  puntable
;;; ?  ?
;;;------------------------------------------------------------------------------------------
;;; ? catch
;;; ? multiple-value-call
;;; ? the
;;;<L.DEMO>VOTRAX.LISP.1
;;; ~ (defun speak-words (&quote &rest list-of-words)
;;;<L.IO>GRIND.LISP.143
;;; ~ (defun grindef (&quote &rest fcns)
;;;<L.IO1>HACKS.LISP.190
;;; ~ (defun skipa (&quote var form)
;;; ~ (defun skipe (&quote var form)
;;; ~ (defun skipn (&quote var form)
;;;<L.SYS>CADRLP.LISP.148
;;; ~ (defun defmic (&quote name opcode arglist lisp-function-p &optional no-qintcmp
;;;<L.SYS>COLDUT.LISP.91
;;; ~ (defun defmic (&quote name opcode arglist lisp-function-p &optional no-qintcmp)
;;;<L.SYS>COMPAT.LISP.32
;;; ~ (defun include (&quote &rest ignore))
;;;<L.SYS>EVAL.LISP.43
;;; ~ (defun *catch-for-eval (tag &quote &rest body)
;;; ; (defun setq (&quote &rest symbols-and-values)
;;; ~ (defun variable-boundp (&quote variable)
;;; ~ (defun variable-location (&quote variable)
;;; ~ (defun variable-makunbound (&quote variable)
;;; * (defun multiple-value (&quote var-list exp)
;;; * (defun nth-value (value-number &quote exp)
;;; * (defun multiple-value-list (&quote exp)
;;; ; (defun multiple-value-prog1 (&quote value-form &rest forms)
;;; * (defun multiple-value-bind (&quote var-list exp &rest body)
;;; * (defun dont-optimize (&quote &rest body)
;;; ; (defun progn (&quote &rest body)
;;; * (defun comment (&quote &rest ignore)
;;; * (defun with-stack-list (&quote variable-and-elements &rest body)
;;; * (defun with-stack-list* (&quote variable-and-elements &rest body)
;;; * (defun and (&quote &rest expressions)
;;; * (defun or (&quote &rest expressions)
;;; * (defun cond (&quote &rest clauses)
;;; ; (defun let (&quote varlist &rest body)
;;; ; (defun let* (&quote varlist &rest body)
;;; ; (defun flet (&quote function-list &rest body)
;;; ; (defun macrolet (&quote macro-list &rest body)
;;; ; (defun labels (&quote function-list &rest body)
;;; ; (defun progv (vars vals &quote &rest body)
;;;(defun progw (vars-and-vals &quote &rest body)
;;;(defun let-if (cond &quote var-list &quote &rest body)
;;; ; (defun unwind-protect (&quote body-form &rest cleanup-forms)
;;; ; (defun *throw (tag &quote value-expression)
;;; ; (defun block (&quote name &rest body)
;;; ; (defun return-from (&quote blockname &rest vals)
;;; * (defun return (&quote &rest vals)
;;; ; (defun tagbody (&quote &rest body)
;;; ; (defun go (&quote tag &aux tem)
;;; * (defun prog (&quote &rest prog-arguments)
;;; * (defun prog* (&quote &rest prog-arguments)
;;; * (defun do (&quote &rest x)
;;; * (defun do-named (&quote name &rest x)
;;; * (defun do* (&quote &rest x)
;;; * (defun do*-named (&quote name &rest x)
;;; ; (defun function (&quote function)
;;; ; (defun quote (&quote x) x)
;;; ~ (defun functional-alist (&quote x)   ;just like quote interpreted.  however, the compiler
;;;<L.SYS>LTOP.LISP.464
;;;(defun break (&optional &quote format-string &eval &rest args
;;;<L.SYS>QCFILE.LISP.307
;;;(defun patch-source-file (&quote si:patch-source-file-namestring &rest body)
;;;(defun special (&rest &quote symbols)
;;;(defun unspecial (&rest &quote symbols)
;;; ~ (defun defmic (&quote name opcode arglist lisp-function-p &optional (no-qintcmp nil)
;;;<L.SYS>QCOPT.LISP.99
;;; ~ (defun *lexpr (&quote &rest l)
;;; ~ (defun *expr (&quote &rest l)
;;; ~ (defun *fexpr (&quote &rest l)
;;;<L.SYS>QFCTNS.LISP.734
;;; * (defun deff (&quote function-spec &eval definition)
;;; * (defun def (&quote function-spec &rest defining-forms)
;;; * (defun defun (&quote &rest arg)
;;; * (defun macro (&quote function-spec &rest def)
;;; * (defun deff-macro (&quote function &eval definition)
;;;(defun defsubst (&quote symbol &rest def)
;;; ~ (defun signp (&quote test &eval num)
;;; ~ (defun array (&quote x type &eval &rest dimlist)
;;; ; (defun declare (&quote &rest declarations)
;;; ; (defun eval-when (&quote times &rest forms &aux val)
;;;<L.SYS>QMISC.LISP.605
;;; ~ (defun status (&quote status-function &optional (item nil item-p))
;;; ~ (defun sstatus (&quote status-function item
;;; ; (defun compiler-let (&quote bindlist &rest body)
;;; ~ (defun lexpr-funcall-with-mapping-table (function &quote table &eval &rest args)
;;; ~ (defun funcall-with-mapping-table (function &quote table &eval &rest args)
;;;<L.SYS>QRAND.LISP.374
;;;(defun special (&rest &quote symbols)
;;;(defun unspecial (&rest &quote symbols)
;;; * (defun defprop (&quote symbol value property)
;;;(defun defvar-1 (&quote symbol &optional (value ':unbound) documentation)
;;;(defun defconst-1 (&quote symbol &eval value &optional documentation)
;;;<L.SYS2>CLASS.LISP.88
;;; ~ (defun defclass-1 (&quote class-symbol superclass-symbol instance-pattern)
;;; ~ (defun defclass-bootstrap (&quote nm c-s method-tail variables)
;;;<L.SYS2>FLAVOR.LISP.258
;;; ~ (defun with-self-accessible (&quote flavor-name &rest body)
;;;<L.SYS2>LOGIN.LISP.80
;;; ~ (defun login-setq (&quote &rest l)  ;undoing setq
;;;<L.SYS2>LOOP.LISP.795
;;; ~ (defun loop-featurep (&quote f)
;;; ~ (defun loop-nofeaturep (&quote f)
;;; ~ (defun loop-set-feature (&quote f)
;;; ~ (defun loop-set-nofeature (&quote f)
;;;<L.SYS2>QTRACE.LISP.149
;;; ? (defun trace (&quote &rest specs)
;;; ? (defun untrace (&quote &rest fns)
;;;<L.SYS2>SELEV.LISP.21
;;;(defun matchcarcdr (&quote arg car cdr)
;;;<L.SYS2>USYMLD.LISP.186
;;; ~ (defun ua-defmic (&quote name opcode arglist lisp-function-p &optional (no-qintcmp nil))
;;;<L.ZWEI>COMTAB.LISP.307
;;; ~ (defun set-comtab-return-undo (&rest &quote form &aux undo)

(defmacro (return alternate-macro-definition) (&rest values)
  `(return-from nil . ,values))

(defmacro (prog alternate-macro-definition) (&rest stuff)
  (if (atom (car stuff))
      `(block ,(pop stuff)
	 (block nil
	   (let ,(pop stuff)
	     (tagbody . ,stuff))))
    `(block nil
       (let ,(pop stuff)
	 (tagbody . ,stuff)))))

(defmacro (prog* alternate-macro-definition) (&rest stuff)
  (if (atom (car stuff))
      `(block ,(pop stuff)
	 (block nil
	   (let* ,(pop stuff)
	     (tagbody . ,stuff))))
    `(block nil
       (let* ,(pop stuff)
	 (tagbody . ,stuff)))))

(defmacro (nth-value alternate-macro-definition) (value-number exp)
  `(nth ,value-number (multiple-value-list ,exp)))

(defmacro (multiple-value-list alternate-macro-definition) (exp)
  `(multiple-value-call #'list ,exp))

(defmacro (multiple-value-bind alternate-macro-definition) (vars exp &body body)
  `(let ,vars
     (multiple-value-setq ,vars ,exp)
     . ,body))

(defmacro (multiple-value alternate-macro-definition) (vars exp)
  `(multiple-value-setq ,vars ,exp))

(defmacro (comment alternate-macro-definition) (&rest ignore)
  `'ignore)

(defmacro (with-stack-list alternate-macro-definition) ((var . elts) &body body)
  `(let ((,var (list . ,elts)))
     . ,body))

(defmacro (with-stack-list* alternate-macro-definition) ((var . elts) &body body)
  `(let ((,var (list* . ,elts)))
     . ,body))

(defmacro (dont-optimize alternate-macro-definition) (&body body)
  `(progn . ,body))

(defmacro (do alternate-macro-definition) (vars (test . result) &body body)
  (let ((tag (gensym)))
    `(prog ,(mapcar #'(lambda (x) (if (atom x) x
				    (list (car x) (cadr x))))
		    vars)
	,tag
	   (when ,test . ,result)
	   (progn . ,body)
	   (psetq . ,(loop for x in vars
			   when (and (not (atom x)) (cddr x))
			   collect (car x) and collect (caddr x)))
	   (go ,tag))))

(defmacro (do* alternate-macro-definition) (vars (test . result) &body body)
  (let ((tag (gensym)))
    `(prog* ,(mapcar #'(lambda (x) (if (atom x) x
				     (list (car x) (cadr x))))
		     vars)
	,tag
	   (when ,test . ,result)
	   (progn . ,body)
	   (setq . ,(loop for x in vars
			  when (and (not (atom x)) (cddr x))
			  collect (car x) and collect (caddr x)))
	   (go ,tag))))

(defmacro (do-named alternate-macro-definition) (name vars (test . result) &body body)
  (let ((tag (gensym)))
    `(prog ,name
	   ,(mapcar #'(lambda (x) (if (atom x) x
				    (list (car x) (cadr x))))
		    vars)
	,tag
	   (when ,test . ,result)
	   (progn . ,body)
	   (psetq . ,(loop for x in vars
			   when (and (not (atom x)) (cddr x))
			   collect (car x) and collect (caddr x)))
	   (go ,tag))))

(defmacro (do*-named alternate-macro-definition) (name vars (test . result) &body body)
  (let ((tag (gensym)))
    `(prog* ,name
	    ,(mapcar #'(lambda (x) (if (atom x) x
				     (list (car x) (cadr x))))
		     vars)
	,tag
	   (when ,test . ,result)
	   (progn . ,body)
	   (setq . ,(loop for x in vars
			  when (and (not (atom x)) (cddr x))
			  collect (car x) and collect (caddr x)))
	   (go ,tag))))

;; ; (or a c b d) => (cond (a) (b) (c) (t d))
(defmacro (or alternate-macro-definition) (&rest expressions)
  (case (length expressions)
    (0 nil)
    (1 (car expressions))
    (t (do ((x expressions (cdr x))
	    (result (list 'cond) (cons (list (car x)) result)))
	   ((null (cdr x))
	    (push (list t (car x)) result)
	    (nreverse result))))))

;;;(and a b c d) => (if a (if b (if c d)))
(defmacro (and alternate-macro-definition) (&rest expressions)
  (case (length expressions)
    (0 t)
    (1 (car expressions))
    (t (do* ((foo (cdr (reverse expressions)) (cdr foo))
	     (result `(,(car (last expressions)))))
	    ((null foo)
	     (car result))
	 (setq result `((if ,(car foo) . ,result)))))))

;;;(cond (a b c) (d) (e f)) => (if a (progn b c) (let (d) (if d (if e f)))
(defmacro (cond alternate-macro-definition) (&rest clauses)
  (do ((foo (reverse clauses) (cdr foo))
       (result nil)
       loser)
      ((null foo)
       (if loser `(let (,loser) . ,result) (car result)))
    (if (> (length (car foo)) 1)
	(setq result `((if ,(caar foo) (progn . ,(cdar foo)) . ,result)))
      (or loser (setq loser (make-symbol "LOSER" t)))
      (setq result `((if (setq ,loser ,(caar foo)) ,loser . ,result))))))

(defmacro (defun alternate-macro-definition) (name &rest body)
  `(progn (fdefine ',name (process-defun-body ',name ',body) t)
	  ',name))

(defmacro (macro alternate-macro-definition) (function-spec &rest def)
  (unless (symbolp function-spec)
    (setq function-spec (standardize-function-spec function-spec)))
  `(progn (fdefine ',function-spec (cons 'macro (process-defun-body ',function-spec ',def)) t)
	  ',function-spec))

(defmacro (deff-macro alternate-macro-definition) (function definition)
  `(progn (fdefine ',function ,definition t)
	  ',function))

(defmacro (deff alternate-macro-definition) (function-spec definition)
  `(progn (fset-carefully ',function-spec ,definition)
	  ,function-spec))

(defmacro (def alternate-macro-definition) (function-spec &rest defining-forms)
  `(progn (mapc 'eval1 ',defining-forms)
	  ,function-spec))

(defmacro (defprop alternate-macro-definition) (symbol value property)
  `(progn (putprop ',symbol ',value ',property)
	  ',symbol))
