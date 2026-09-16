;;; -*- Mode:LISP; Package:COMPILER; Lowercase:T; Base:8; Readtable:T -*-
;;; This file contains the source-level optimizers of the Lisp machine compiler.

;	** (c) Copyright 1980 Massachusetts Institute of Technology **

;;     "This is insane.  What we clearly want to do is not completely
;;      clear, and is rooted in NCOMPLR."   -- BSG/Dissociated Press.

;;; this is for frobs which are DEFFed to functions rather than DEFSUBSTed,
;;;  and for various other hairyness
(defcompiler-synonym +$		+)
(defcompiler-synonym plus	+)
(defcompiler-synonym -$		-)
(defcompiler-synonym *$		*)
(defcompiler-synonym times	*)
(defcompiler-synonym //$	//)
(defcompiler-synonym ^$		^)
(defcompiler-synonym expt	^)
(defcompiler-synonym 1+$	1+)
(defcompiler-synonym 1-$	1-)
(defcompiler-synonym add1	1+)
(defcompiler-synonym sub1	1-)
(defcompiler-synonym gcd	\\)
(defcompiler-synonym remainder	\)
(defcompiler-synonym cli:rem	\)
(defcompiler-synonym greaterp	>)
(defcompiler-synonym lessp	<)
(defcompiler-synonym >=		)
(defcompiler-synonym <=		)
(defcompiler-synonym //=	)
(defcompiler-synonym short-float small-float)
(defcompiler-synonym null	not)
(defcompiler-synonym lexpr-funcall apply)
(defcompiler-synonym atan2	cli:atan)
(defcompiler-synonym catch	*catch)
(defcompiler-synonym throw	*throw)
(defcompiler-synonym multiple-value-setq multiple-value)
(defcompiler-synonym fixp	integerp)
(defcompiler-synonym bind	%bind)
(defcompiler-synonym global:map	mapl)
(defcompiler-synonym global:member member-equal)
(defcompiler-synonym global:assoc assoc-equal)
(defcompiler-synonym global:rassoc rassoc-equal)

;;; The following are here to make list-type structures work more efficiently.
;;; It's easier to put the optimization in the compiler than in DEFSTRUCT.
(defoptimizer nth-optimize nth (car cadr caddr cadddr) (x)
  (let ((tem (assq (cadr x) '((0 . car) (1 . cadr) (2 . caddr) (3 . cadddr)))))
    (if (and (= (length x) 3)
	     tem)
	`(,(cdr tem) ,(caddr x))
      x)))

(defoptimizer nthcdr-optimize nthcdr (cdr cddr cdddr cddddr) (x)
  (if (= (length x) 3)
      (let ((tem (assq (cadr x) '((1 . cdr) (2 . cddr) (3 . cdddr) (4 . cddddr)))))
	(cond ((eq (cadr x) 0) (caddr x))
	      (tem `(,(cdr tem) ,(caddr x)))
	      (t x)))
    x))

;;; Optimize (CAR (CDR X)) into (CADR X) -- LOOP generates this all the time.
;;; This is really the wrong place in the compiler for this...
;;; EVAL-WHEN so the #.'s below will win the first time.
(eval-when (compile load eval)
(defvar cxrs '(car cdr caar cadr cdar cddr caaar caadr
	       cadar caddr cdaar cdadr cddar cdddr
	       caaaar caaadr caadar caaddr cadaar cadadr
	       caddar cadddr cdaaar cdaadr cdadar cdaddr
	       cddaar cddadr cdddar cddddr))

(defvar 3cxrs '(car cdr caar cadr cdar cddr caaar caadr
	       cadar caddr cdaar cdadr cddar cdddr))
)

(defconst cxr-pop-table
	  '#.(loop for sym in (cddr cxrs) collecting
		   (cons sym (intern (string-append #/C (substring sym 2))))))

(defconst cxr-append-table
	  '#.(loop for sym in 3cxrs
		   as first = (substring (symbol-name sym)
					 0 (1- (array-active-length (symbol-name sym))))
		   collect (list sym
				 (intern (string-append first "AR"))
				 (intern (string-append first "DR")))))

(defoptimizer 3cxr-optimize	car)
(defoptimizer 3cxr-optimize	cdr)
(defoptimizer 3cxr-optimize	caar)
(defoptimizer 3cxr-optimize	cadr)
(defoptimizer 3cxr-optimize	cdar)
(defoptimizer 3cxr-optimize	cddr)
(defoptimizer 3cxr-optimize	caaar)
(defoptimizer 3cxr-optimize	caadr)
(defoptimizer 3cxr-optimize	cadar)
(defoptimizer 3cxr-optimize	caddr)
(defoptimizer 3cxr-optimize	cdaar)
(defoptimizer 3cxr-optimize	cdadr)
(defoptimizer 3cxr-optimize	cddar)
(defoptimizer 3cxr-optimize	cdddr)
(defun 3cxr-optimize (form)
  (or (when (= (length form) 2)
	(let ((argform (cadr form)))
	  (cond ((and (consp argform)
		      (memq (car argform) cxrs))
		 `(,(funcall (if (= (aref (symbol-name (car argform)) 1) #/A)
				 #'cadr #'caddr)
			     (assq (car form) cxr-append-table))
		   ,(let ((x (cdr (assq (car argform) cxr-pop-table))))
		      (if x `(,x . ,(cdr argform)) (cadr argform)))))
		((not (equal argform (cadr form)))
		 `(,(car form) ,argform)))))
      form))

;;; don't quote numbers or nil or t -- make life easier for other optimizers.
;;; The $64000 question is whether keywords should keep their QUOTEs... I wonder.
;;;  That would make some things much easier when real compiler support for
;;;  the commonlisp 69 different keyword argument functions is written.
(defoptimizer unquote quote () (form)
  (if (= (length form) 2)
      (if (or (numberp (cadr form))
	      (characterp (cadr form))
	      (eq (cadr form) t)
	      (eq (cadr form) nil))
	  (cadr form)
	form)
    form))

(defun fold-constants (form)
  "Replace an expression by its value...if it evaluates ok."
  (multiple-value-bind (value errorflag)
      (catch-error (multiple-value-list (eval form)))
    (cond (errorflag
	   (warn 'constant-folding ':error
		 "Error during constant-folding on expression ~S" form)
	   form)
	  (t
	   (if (= (length value) 1)
	       `',(first value)
	     `(values . ,(mapcar #'(lambda (elt) `',elt) value))))))) ; Get multiple-values

;;; Optimize forms such as (+ 3 2) and (+ 3 a 2).  These must be done before ARITHEXP
(defoptimizer arith-opt +)
(defoptimizer arith-opt *)
(defoptimizer arith-opt -)
(defoptimizer arith-opt difference)
(defoptimizer arith-opt //)
(defoptimizer arith-opt quotient)
(defoptimizer arith-opt cli://)
(defoptimizer arith-opt logior)
(defoptimizer arith-opt logand)
(defoptimizer arith-opt logxor)
(defoptimizer arith-opt min)
(defoptimizer arith-opt max)

(defun arith-opt (form)
  (if ( (length form) 2) form			;Let ARITHEXP handle this.
    (loop for arg in (cdr form)
	  when (numberp arg)
	       collect arg into winners
	  else collect arg into losers
	  finally
	  (return (cond ((null (cdr winners)) form)	;Can't hope to optimize.
			((null losers) (fold-constants form))	;Easy optimization.
			;; Now we are left with at least two args which are numbers, but at
			;; least one which is not.  Frobbing with divide from here on is
			;; dangerous, eg, (// 5 a 4) must not optimize into (// 1 a).
			((memq (car form) '(// quotient cli://)) form)
			;; The only special case left is DIFFERENCE, which treats
			;; its first arg differently.
			((or (not (memq (car form) '(- difference)))
			     (numberp (cadr form)))
			 `(,(car form) ,(apply (car form) winners) . ,losers))
			(t `(,(car form) ,@losers ,(apply #'+ winners))))))))

;;; Express multi-argument arithmetic functions in terms of two-argument versions.
(defoptimizer arithexp + (*plus))
(defoptimizer arithexp - (*dif))
(defoptimizer arithexp difference (*dif))
(defoptimizer arithexp * (*times))
(defoptimizer arithexp // (*quo))
(defoptimizer arithexp quotient (*quo))
(defoptimizer arithexp cli:// (%div))
(defoptimizer arithexp logand (*logand))
(defoptimizer arithexp logior (*logior))
(defoptimizer arithexp logxor (*logxor))
(defoptimizer arithexp min (*min))
(defoptimizer arithexp max (*max))

(defprop +		*plus	two-argument-function)
(defprop *		*times	two-argument-function)
(defprop -		*dif	two-argument-function)
(defprop difference	*dif	two-argument-function)
(defprop //		*quo	two-argument-function)
(defprop quotient	*quo	two-argument-function)
(defprop cli://		%div	two-argument-function)
(defprop logior		*logior	two-argument-function)
(defprop logand		*logand	two-argument-function)
(defprop logxor		*logxor	two-argument-function)
(defprop min		*min	two-argument-function)
(defprop max		*max	two-argument-function)

(defun arithexp (x &aux (l (length (cdr x))) (op (get (car x) 'two-argument-function)))
  (cond ((null op)
	 (barf x 'bad-op-arithexp 'barf))
	((= 0 l)
	 (or (setq l (assq op '((*plus . 0) (*dif . 0) (*times . 1) (*quo . 1) (%div . 1))))
	     (warn 'bad-arithmetic ':implausible
		   "~S with no arguments." x))
	 (cdr l))
	((= l 1)
	 (selectq (car x)
	   (-		`(minus ,(cadr x)))
	   (//		`(*quo 1 ,(cadr x)))
	   (cli://	`(%div 1 ,(cadr x)))
	   (t		(cadr x))))		;+ * logior logxor logand mix max
	((= l 2) `(,op . ,(cdr x)))
	(t `(,op (,(car x) . ,(butlast (cdr x))) . ,(last x)))))

(defoptimizer *plus-to-1+ *plus (1+) (form)
  (cond ((eq (cadr form) 1) `(1+ ,(caddr form)))	;(+ 1 x)
	((eq (caddr form) 1) `(1+ ,(cadr form)))	;(+ x 1)
	((eq (cadr form) 0) (caddr form))		;(+ 0 x)
	((eq (caddr form) 0) (cadr form))		;(+ x 0)
	(t form)))

(defoptimizer *dif-to-1- *dif (1-) (form)
  (cond ((eq (caddr form) 1) `(1- ,(cadr form)))	;(- x 1)
	((eq (cadr form) 0) `(minus ,(caddr form)))	;(- 0 x)
	((eq (caddr form) 0) (cadr form))		;(- x 0)
	(t form)))

;;; Forms such as (SQRT 5) optimize into 2.236
(defoptimizer arith-opt-non-associative sqrt)
(defoptimizer arith-opt-non-associative exp)
(defoptimizer arith-opt-non-associative log)
(defoptimizer arith-opt-non-associative sin)
(defoptimizer arith-opt-non-associative sind)
(defoptimizer arith-opt-non-associative cos)
(defoptimizer arith-opt-non-associative cosd)
(defoptimizer arith-opt-non-associative tan)
(defoptimizer arith-opt-non-associative tand)
(defoptimizer arith-opt-non-associative asin)
(defoptimizer arith-opt-non-associative acos)
(defoptimizer arith-opt-non-associative atan)
(defoptimizer arith-opt-non-associative cli:atan)
(defoptimizer arith-opt-non-associative sinh)
(defoptimizer arith-opt-non-associative cosh)
(defoptimizer arith-opt-non-associative tanh)
(defoptimizer arith-opt-non-associative asinh)
(defoptimizer arith-opt-non-associative acosh)
(defoptimizer arith-opt-non-associative atanh)
(defoptimizer arith-opt-non-associative ^)
(defoptimizer arith-opt-non-associative minus)
(defoptimizer arith-opt-non-associative 1+)
(defoptimizer arith-opt-non-associative 1-)
(defoptimizer arith-opt-non-associative ash)
(defoptimizer arith-opt-non-associative lsh)
(defoptimizer arith-opt-non-associative rot)
(defoptimizer arith-opt-non-associative dpb)
(defoptimizer arith-opt-non-associative ldb)
(defoptimizer arith-opt-non-associative deposit-byte)
(defoptimizer arith-opt-non-associative load-byte)
(defoptimizer arith-opt-non-associative floor)
(defoptimizer arith-opt-non-associative ceiling)
(defoptimizer arith-opt-non-associative truncate)
(defoptimizer arith-opt-non-associative round)
(defoptimizer arith-opt-non-associative not)
(defoptimizer arith-opt-non-associative eq)
(defoptimizer arith-opt-non-associative equal)
(defoptimizer arith-opt-non-associative =)
(defoptimizer arith-opt-non-associative \)
(defoptimizer arith-opt-non-associative \\)
(defoptimizer arith-opt-non-associative assq)
(defoptimizer arith-opt-non-associative cdr)
;(defoptimizer arith-opt-non-associative float)	;done in float-optimizer
(defoptimizer arith-opt-non-associative small-float)
(defoptimizer arith-opt-non-associative char-code)	;perhaps stretching "arith"
(defoptimizer arith-opt-non-associative char-bits)	; a little too far...
(defoptimizer arith-opt-non-associative char-int)	;
(defoptimizer arith-opt-non-associative int-char)	;


(defun arith-opt-non-associative (form)
  (if (loop for arg in (cdr form)
	    always (constantp arg))
      (fold-constants form)
    form))


(defoptimizer boole-expand boole (*boole) (x)
  (let ((l (length x))
	(op (cadr x))
	inst)
    (cond ((< l 3) x)
	  ((= l 3) (caddr x))
	  ((and (numberp op)
		(setq inst (assq op '((1 . logand)
				      (6 . logxor)
				      (7 . logior)))))
	   `(,(cdr inst) . ,(cddr x)))
	  ((= l 4) `(*boole . ,(cdr x)))
	  (t `(*boole ,op
		      (boole ,op . ,(butlast (cddr x)))
		      ,(car (last x)))))))

(defoptimizer byte-expand byte (dpb) (x)
  (or (when (and (= (length x) 3)
		 (numberp (cadr x))
		 (numberp (caddr x)))
	`(dpb ,(caddr x) ,%%byte-specifier-position ,(cadr x)))
      x))

;;; something that won't care about order of evaluation
(defun trivial-form-p (x)
  (or (constantp x)
      (symbolp x)))

(defoptimizer convert-\\ \\ (internal-\\) (form)
  (loop for arg-form in (cdddr form)
	with answer = `(internal-\\ ,(second form) ,(third form))
	do (setq answer `(internal-\\ ,answer ,arg-form))
	finally (return answer)))

(defoptimizer float-optimizer float (internal-float) (form)
  (cond ((null (cddr form))			;One arg
	 `(internal-float ,(cadr form)))
	((numberp (caddr form))			;Second arg a number
	 (if (small-floatp (caddr form))
	     (if (numberp (cadr form))
		 (small-float (cadr form))
	       `(small-float ,(cadr form)))
	   (if (numberp (cadr form))
	       (float (cadr form))
	     `(internal-float ,(cadr form)))))
	(t form)))

;;;; Expand the numerical equality/sign predicates.

(defoptimizer =-optimizer = (internal-=) (form)
  (let* ((args (cdr form))
	 (n-args (length args)))
    (cond ((< n-args 2)
	   (warn 'wrong-number-of-arguments ':implausible
		 "Too few arguments to ~S." (car form))
	   ''t)
	  ((= n-args 2)
	   (if (eq (second args) 0)
	       `(zerop ,(first args))
	     `(internal-= . ,args)))
	  ((every (cdr args) 'trivial-form-p)
	   `(and . ,(loop for arg in (cdr args)
			  and for last-arg first (car args) then arg
			  collect `(internal-= ,last-arg ,arg))))
	  (t form))))

(defoptimizer char-equal-optimizer char-equal (internal-char-equal) (form)
  (let* ((args (cdr form))
	 (n-args (length args)))
    (cond ((< n-args 2)
	   `(progn ,(car args) 't))
	  ((= n-args 2)
	   `(internal-char-equal . ,args))
	  ((every (cdr args) 'trivial-form-p)
	   `(and . ,(loop for arg in (cdr args)
			  and for last-arg first (car args) then arg
			  collect `(internal-char-equal ,last-arg ,arg))))
	  (t form))))

(defoptimizer >-optimizer > (internal-> plusp) (form)
  (let* ((args (cdr form))
	 (n-args (length args)))
    (cond ((< n-args 2)
	   `(progn ,(car args) 't))
	  ((= n-args 2)
	   (if (eq (second args) '0)
	       `(plusp ,(first args))
	     `(internal-> . ,args)))
	  ((every (cdr args) 'trivial-form-p)
	   `(and . ,(loop for arg in (cdr args)
			  and for last-arg first (car args) then arg
			  collect `(internal-> ,last-arg ,arg))))
	  (t form))))

(defoptimizer <-optimizer < (internal-< minusp) (form)
  (let* ((args (cdr form))
	 (n-args (length args)))
    (cond ((< n-args 2)
	   `(progn ,(car args) 't))
	  ((= n-args 2)
	   (if (eq (second args) 0)
	       `(minusp ,(first args))
	     `(internal-< . ,args)))
	  ((every (cdr args) 'trivial-form-p)
	   `(and . ,(loop for arg in (cdr args)
			  and for last-arg first (car args) then arg
			  collect `(internal-< ,last-arg ,arg))))
	  (t form))))


(defoptimizer -optimizer  (internal-< minusp not) (form)
  (let* ((args (cdr form))
	 (n-args (length args)))
    (cond ((< n-args 2)
	   `(progn ,(car args) 't))
	  ((= n-args 2)
	   (if (eq (second args) 0)
	       `(not (minusp ,(first args)))
	     `(not (internal-< . ,args))))
	  ((every (cdr args) 'trivial-form-p)
	   `(and . ,(loop for arg in (cdr args)
			  and for last-arg first (car args) then arg
			  collect `(not (internal-< ,last-arg ,arg)))))
	  (t form))))

(defoptimizer -optimizer  (internal-> plusp not) (form)
  (let* ((args (cdr form))
	 (n-args (length args)))
    (cond ((< n-args 2)
	   `(progn ,(car args) 't))
	  ((= n-args 2)
	   (if (eq (second args) 0)
	       `(not (plusp ,(first args)))
	     `(not (internal-> . ,args))))
	  ((every (cdr args) 'trivial-form-p)
	   `(and . ,(loop for arg in (cdr args)
			  and for last-arg first (car args) then arg
			  collect `(not (internal-> ,last-arg ,arg)))))
	  (t form))))

(defoptimizer -optimizer  (= zerop not) (form)
  (let* ((args (cdr form))
	 (n-args (length args)))
    (cond ((< n-args 2)
	   `(progn ,(car args) 't))
	  ((= n-args 2)
	   (if (eq (second args) 0)
	       `(not (zerop ,(first args)))
	     `(not (= . ,args))))
	  ((and (= n-args 3)
		(every args 'trivial-form-p))
 	   `(not (or (= ,(car args) ,(cadr args))
		     (= ,(car args) ,(caddr args))
		     (= ,(cadr args) ,(caddr args)))))
	  (t form))))

(defun constant-function-p (x)
  (and (consp x) (memq (car x) '(function quote))
       (functionp (cadr x))))

(defun call-function (function-exp arg-exps)
  (if (constant-function-p function-exp)
      `(,(cadr function-exp) . ,arg-exps)
    `(funcall ,function-exp . ,arg-exps)))

;;; Optimize (FUNCALL (FUNCTION (LAMBDA ...)) ...) into ((LAMBDA ...) ...).
;;; Does not optimize (FUNCALL (FUNCTION FOO) ...) if FOO is not defined
;;; or takes quoted args (FUNCTIONP checks for that).
(defoptimizer funcall-function funcall () (form)
  (if (constant-function-p (cadr form))
      `(,(cadr (cadr form)) . ,(cddr form))
    form))

(defoptimizer list-no-args list () (form)
  (if (equal form '(list))
      'nil
    form))

(defoptimizer call-to-multiple-value-list call (multiple-value-push %pop) (form)
  (if (not (and (= (length form) 4)
		(member-equal (third form) '('(:optional :spread) '(:spread :optional)))))
      form
    (let ((argform (fourth form))
	  (firstarg (second form)))
      (cond ((atom argform)
	     form)
	    ((and (eq (car argform) 'multiple-value-list)
		  (memq (car-safe firstarg) '(function quote))
		  (consp (cadr firstarg))
		  (eq (caadr firstarg) 'lambda)
		  (not (memq '&rest (cadadr firstarg)))
		  (not (memq '&key (cadadr firstarg))))
	     ;; (call #'(lambda (x y z) ..) '(:spread :optional) (multiple-value-list ...))
	     ;; and the lambda does not have a rest arg.
	     ;; since we know how many args it wants, we can avoid consing the list of vals.
	     ;; This weird optimization is for the sake of code made by CATCH-CONTINUATION.
	     (let ((nargs (ldb %%arg-desc-max-args (args-info (cadr firstarg)))))
	       (if (= nargs 1)
		   `(,(cadr firstarg) ,(cadr argform))
		 `(progn (multiple-value-push ,nargs ,(cadr argform))
			 (,(cadr firstarg)
			  . ,(make-list nargs :initial-element '(%pop)))))))
	    ;; The optimizations done on APPLY are not correct to do here,
	    ;; because they would cause the function to get an error
	    ;; if it does not want all the arguments.
	    (t form)))))

;; alas this conses...
(defoptimizer multiple-value-call-list multiple-value-call (call multiple-value-list) (form)
  (let ((args (mapcan #'(lambda (form) `(:spread (multiple-value-list ,form))) (cddr form))))
    `(funcall #'call ,(cadr form) . ,args)))

;;; Turn (MULTIPLE-VALUE-BIND (one-variable) (form) body...) into 
;;;   (LET ((one-variable form)) body...)
(defoptimizer optimize-simple-mv-bind multiple-value-bind (let) (form)
  (if ( (length (second form)) 1) form	; Actually looking for 2 values
    `(let ((,(car (second form)) ,(third form))) ,@(rest3 form))))

;;; Turn (FUNCALL SELF ...) into (FUNCALL-SELF ...) if within a method or a function with a
;;;   SELF-FLAVOR declaration.
;;; Leave it alone otherwise -- that would be a pessimization.
(defoptimizer optimize-funcall-self funcall (funcall-self) (form)
  (if (and (not (null self-flavor-declaration))
	   (eq (second form) 'self))
      `(funcall-self . ,(cddr form))
    form))

;;; note that this is not an optimizer for LEXPR-FUNCALL of SELF,
;;;  since LEXPR-FUNCALL has been rewritten into APPLY by this point
(defoptimizer optimize-apply-self apply (lexpr-funcall-self) (form)
  (if (and (not (null self-flavor-declaration))
	   (eq (second form) 'self))
      `(lexpr-funcall-self . ,(cddr form))
    form))

(defoptimizer apply-on-list apply (funcall) (form)
  (if (= (length form) 2)
      (let ((arg (cadr form)))
	(once-only (arg)
	  `(lexpr-funcall (car ,arg) (cdr ,arg))))
    (let ((lastarg (car (last form)))
	  (firstarg (cadr form)))
      (cond ((atom lastarg) form)
	    ((eq (car lastarg) 'list)
	     ;; If function to be called is quoted symbol, optimize out the "funcall"
	     ;; in case the symbol is a subst function.
	     (call-function firstarg (nconc (butlast (cddr form)) (cdr lastarg))))
	    ((memq (car lastarg) '(list* cons))
	     `(lexpr-funcall ,@(butlast (cdr form)) . ,(cdr lastarg)))
	    ((and (eq (car lastarg) 'quote)
		  (consp (cadr lastarg)))
	     `(funcall ,@(butlast (cdr form))
		       . ,(mapcar #'(lambda (x) (list 'quote x)) (cadr lastarg))))
	    (t form)))))

(defoptimizer and-or-no-op and)
(defoptimizer and-or-no-op or () (form)
  (cond ((null (cdr form))
	 (if (eq (car form) 'and)
	     ''t
	     ''nil))
	((null (cddr form))
	 (cadr form))
	(t form)))

(defoptimizer 1-arg-no-op progn)
(defoptimizer 1-arg-no-op list* () (form)
  (if (cddr form)
      form
    (cadr form)))

(defoptimizer prog2-no-op prog2 () (form)
  (if (or (cadr form) (cdddr form))
      form
    (caddr form)))

;;; Turn EQUAL into EQ when that is safe.
;;; EQUAL can never be turned into = alone because = signals an error if either
;;; arg is not a number, whereas EQUAL does not.  However, (EQUAL <fixnum> xxx)
;;; can be turned into EQ since EQ "works" for fixnums.
;;; Also EQUALwith one of the arguments a number turns into
;;; (AND (NUMBERP <form>) (= <number> <form>))
(defoptimizer equal-eq-= equal (eq) (form)
  (cond ((or (pointer-identity-p (cadr form))
	     (pointer-identity-p (caddr form)))
	 `(eq . ,(cdr form)))
	((and (numberp (cadr form)) (atom (caddr form)))
	 (equal-= (cadr form) (caddr form)))
	((and (numberp (caddr form)) (atom (cadr form)))
	 (equal-= (caddr form) (cadr form)))
	(t form)))

(defun equal-= (number atom)
  `(and (numberp ,atom) (= ,number ,atom)))

(defun pointer-identity-p (quan)
  (or (fixnump quan)
      (and (eq (car-safe quan) 'quote)
	   (or (fixnump (cadr quan))
	       (symbolp (cadr quan))))))

;;; Turn (EQ FOO NIL) into (NOT FOO).
(defoptimizer eq-nil eq (not) (form &aux x y)
  (or (when (= (length form) 3)
	(setq x (cadr form) y (caddr form))
        (cond ((null x) `(null ,y))
	      ((null y) `(null ,x))))
      form))

(defvar test-member-alist
	'((eq . memq)
	  (equal . member-equal)
	  (equal . global:member)
	  (eql . member-eql)
	  (equalp . member-equalp))
  "Alist of test functions and functions which can be used to check whether any member
of a list satisfies the test. Eg (EQ . MEMQ)")

;(defoptimizer memq-eq global:member)
(defoptimizer memq-eq member-equal)
(defoptimizer memq-eq member-eql)
(defoptimizer memq-eq member-equalp)
(defoptimizer memq-eq memq () (form)
  (or (when (= (length form) 3)
	(let ((item (cadr form))
	      (list (caddr form)))
	  (if (quotep list)
	      (selectq (length (cadr list))
		(0 `(progn ,item nil))
		(1 `(and (,(car (rassq (car form) test-member-alist))
			  ,item ',(car (cadr list)))
			 ',(cadr list)))))))
      form))

;;; (eql x 1) => (eq x 1)
(defoptimizer eql-eq eql (eq) (form)
  (or (when (and (= (length form) 3)
		 (or (and (constantp (cadr form))
			  (typep (cadr form) '(or (not number) fixnum short-float)))
		     (and (constantp (caddr form))
			  (typep (caddr form) '(or (not number) fixnum short-float)))))
	`(eq ,(cadr form) ,(caddr form)))
      form))

;;; (member-eql x '(a b c)) => (memq x '(a b c))
(defoptimizer member-eql-memq member-eql (memq) (form)
  (or (when (= (length form) 3)
	(let ((item (cadr form))
	      (list (caddr form)))
	  (if (or (and (constantp item)
		       (typep item '(or (not number) fixnum short-float)))
		  (and (quotep list)
		       (consp (cadr list))
		       (loop for x in (cadr list)
			     always (typep x '(or (not number) fixnum short-float)))))
	      `(memq ,item ,list))))
      form))

;;; Optimize (EQ (TYPEP ...) 'SYMBOL), etc.
(defoptimizer eq-typep eq (numberp symbolp consp listp stringp characterp fixnump
			   = %data-type)
	      (form)
  (and (not (atom (cadr form)))
       (not (atom (caddr form)))
       (cond ((and (memq (caadr form) '(typep type-of))
		   (null (cddadr form))  ;Check that TYPEP has only one arg!
		   (eq (caaddr form) 'quote))
	      (return-from eq-typep (eq-typep-1 (cadadr form) (cadr (caddr form)) form)))
	     ((and (eq (caadr form) 'quote)
		   (memq (caaddr form) '(typep type-of))
		   (null (cddr (caddr form))))
	      (return-from eq-typep (eq-typep-1 (cadr (caddr form)) (cadadr form) form)))))
  form)

(defun eq-typep-1 (form type topform &aux pred)
  (setq pred (or (car (rassq type '((stringp . string) (symbolp . symbol) (consp . list)
				    (stringp . :string) (symbolp . :symbol) (listp . :list))))
		 (car (rassoc-equal type si:typep-one-arg-alist))
		 (car (rassoc-equal type si:type-of-alist))))
  (cond ((null pred) topform)
	((numberp pred) `(= (%data-type ,form) ,pred))
	((symbolp pred) `(,pred ,form))
	(t topform)))

;;; Open coding of TYPEP and COERCE.  Optimizers defined in SYS; TYPES.
(defoptimizer si::typep-two-args typep
	      (si::typep-structure si::typep-flavor si::subinstance-of-class-symbol-p))
(defoptimizer si::coerce-optimizer coerce
	      (si::coerce-to-vector cli:character si::coerce-to-list float complex))

;;; modify signp to be (AND (NUMBERP <form>) (<op> <form>)) if form is an atom
;;; and therefore can't have side effects
(defoptimizer signp-expand signp (zerop minusp plusp numberp not) (x)
  (or (when (= (length x) 3)
	(let ((operation (cadr x))
	      (operand (caddr x))
	      new-form notp)
	  (when (atom operand)
	    (setq new-form
		  `(,(cond ((string-equal operation 'e) 'zerop)
			   ((string-equal operation 'n) (setq notp t) 'zerop)
			   ((string-equal operation 'l) 'minusp)
			   ((string-equal operation 'ge) (setq notp t) 'minusp)
			   ((string-equal operation 'g) 'plusp)
			   ((string-equal operation 'le) (setq notp t) 'plusp)
			   (t (warn 'bad-signp ':impossible
				    "~S is not a valid SIGNP condition." operation)
			      'progn))
		    ,operand))
	    (if notp (setq new-form `(not ,new-form)))
	    `(and (numberp ,operand) ,new-form))))
      x))

(defun simple-form-p (form)
  (or (atom form)		; Cautious about quoted lists that might get bashed
      (and (eq (car-safe form) 'quote)
	   (atom (second form)))))
      
(defsubst invariable-form-p (form)
  (constantp form))

(defoptimizer make-array-simple-make-array make-array (si:simple-make-array) (form)
  (let ((len (length form))
	(dimensions-form nil)
	(initial-value-form nil)
	(initial-value-specified nil)
	(area-form nil)
	(type-form ''art-q)
	(leader-length-form nil)
	(fill-pointer-form nil)
	(fill-pointer-specified nil)
	(named-structure-symbol-form nil)
	(named-structure-symbol-specified nil)
	out-of-order
	startform)
    (when (or (< len 2) (oddp len))
      (return-from make-array-simple-make-array form))
    (setq dimensions-form (second form))
    (loop for (keyword-form argument-form) on (rest2 form) by #'cddr
	  do (case (if (eq (car-safe keyword-form) 'quote)
			  (cadr keyword-form)
			keyword-form)
	       (:type
		(setq type-form argument-form)
		(or (constantp type-form)
		    (and (constantp area-form)
			 (constantp leader-length-form)
			 (constantp initial-value-form)
			 (constantp fill-pointer-form)
			 (constantp named-structure-symbol-form))
		    (setq out-of-order t)))
	       (:element-type
		(setq type-form argument-form)
		(or (constantp type-form)
		    (if (symbolp type-form)
			(and (trivial-form-p area-form)
			     (trivial-form-p leader-length-form)
			     (trivial-form-p initial-value-form)
			     (trivial-form-p fill-pointer-form)
			     (trivial-form-p named-structure-symbol-form))
		      (and (constantp area-form)
			   (constantp leader-length-form)
			   (constantp initial-value-form)
			   (constantp fill-pointer-form)
			   (constantp named-structure-symbol-form)))
		    (setq out-of-order t))
		(setq type-form
		      (if (constantp type-form)
			  `',(si::array-type-from-element-type (eval type-form))
			  `  (si::array-type-from-element-type ,type-form))))
			  
	       (:area
		(setq area-form argument-form)
		(or (constantp area-form)
		    (if (symbolp area-form)
			(and (trivial-form-p leader-length-form)
			     (trivial-form-p initial-value-form)
			     (trivial-form-p fill-pointer-form)
			     (trivial-form-p named-structure-symbol-form))
		      (and (constantp leader-length-form)
			   (constantp initial-value-form)
			   (constantp fill-pointer-form)
			   (constantp named-structure-symbol-form)))
		    (setq out-of-order t)))
	       (:leader-length
		(setq leader-length-form argument-form)
		(or (constantp leader-length-form)
		    (if (symbolp leader-length-form)
			(and (trivial-form-p initial-value-form)
			     (trivial-form-p fill-pointer-form)
			     (trivial-form-p named-structure-symbol-form))
		      (and (constantp initial-value-form)
			   (constantp fill-pointer-form)
			   (constantp named-structure-symbol-form)))
		    (setq out-of-order t)))
	       ((:initial-value :initial-element)
		(setq initial-value-form argument-form initial-value-specified t)
		(or (constantp initial-value-form)
		    (if (symbolp initial-value-form)
			(and (trivial-form-p fill-pointer-form)
			     (trivial-form-p named-structure-symbol-form))
		      (and (constantp fill-pointer-form)
			   (constantp named-structure-symbol-form)))
		    (setq out-of-order t)))
	       (:fill-pointer
		(setq fill-pointer-form argument-form fill-pointer-specified t)
		(or (constantp fill-pointer-form)
		    (if (symbolp fill-pointer-form)
			(trivial-form-p named-structure-symbol-form)
		      (constantp named-structure-symbol-form))
		    (setq out-of-order t)))
	       (:named-structure-symbol
		(setq named-structure-symbol-form argument-form
		      named-structure-symbol-specified t))
	       (otherwise
		(return-from make-array-simple-make-array form))))
    (if out-of-order
	;; Don't optimize if it means exchanging two subforms
	;; which could affect each other.
	form
      (if fill-pointer-specified
	  (setq leader-length-form
		(if leader-length-form
		    `(max 1 ,leader-length-form)
		  1)))
      (setq startform
	    (cond
	      (initial-value-specified
	       `(si:simple-make-array ,dimensions-form ,type-form ,area-form
				      ,leader-length-form ,initial-value-form))
	      (leader-length-form
	       `(si:simple-make-array ,dimensions-form ,type-form ,area-form
				      ,leader-length-form))
	      (area-form
	       `(si:simple-make-array ,dimensions-form ,type-form ,area-form))
	      (t
	       `(si:simple-make-array ,dimensions-form ,type-form))))
      (if (or fill-pointer-specified named-structure-symbol-specified)
	  (let ((array-var (gensym)))
	    `(let ((,array-var ,startform))
	       ,(if fill-pointer-specified
		    `(setf (fill-pointer ,array-var) ,fill-pointer-form))
	       ,(if named-structure-symbol-specified
		    `(make-array-into-named-structure
		       ,array-var ,named-structure-symbol-form))
	       , array-var))
	startform))))

(defoptimizer make-string-simple-make-array make-string (si:simple-make-array) (form)
  (let* ((loss `(make-array ,(cadr form) :type art-string . ,(cddr form)))
	 (loser (make-array-simple-make-array loss)))
    (if (eq loss loser) form loser)))

(defoptimizer aref-expander global:aref (ar-1 ar-2 ar-3) (form)
  (selectq (length form)
    (3 `(ar-1 . ,(cdr form)))
    (4 `(ar-2 . ,(cdr form)))	;note that ar-2, ar-3 are common-lisp-aref!
    (5 `(ar-3 . ,(cdr form)))	;ie return characters from strings.
    (t form)))

(defoptimizer common-lisp-aref-expander common-lisp-aref (common-lisp-ar-1 ar-2 ar-3) (form)
  (selectq (length form)
    (3 `(common-lisp-ar-1 . ,(cdr form)))
    (4 `(ar-2 . ,(cdr form)))
    (5 `(ar-3 . ,(cdr form)))
    (t form)))

(defoptimizer aset-expander aset (as-1 as-2 as-2) (form)
  (selectq (length form)
    (4 `(as-1 . ,(cdr form)))
    (5 `(as-2 . ,(cdr form)))
    (6 `(as-3 . ,(cdr form)))
    (t form)))

(defoptimizer set-aref-expander set-aref (set-ar-1 set-ar-2 set-ar-3) (form)
  (selectq (length form)
    (4 `(set-ar-1 . ,(cdr form)))
    (5 `(set-ar-2 . ,(cdr form)))
    (6 `(set-ar-3 . ,(cdr form)))
    (t form)))

(defoptimizer aloc-expander aloc (ap-1 ap-2 ap-3) (form)
  (selectq (length form)
    (3 `(ap-1 . ,(cdr form)))
    (4 `(ap-2 . ,(cdr form)))
    (5 `(ap-3 . ,(cdr form)))
    (t form)))

;;; Find simple calls to MAKE-LIST and convert them into calls to the
;;; microcoded %MAKE-LIST.  NOTE THAT THIS CHANGES ORDER OF EVALUATION!
(defoptimizer make-list-%make-list make-list (%make-list) (form)
  (or (let ((length-of-form (length form)))
	(if (= length-of-form 3)
	    ;; It is old-style.
	    `(%make-list 'nil ,(second form) ,(third form))
	  ;; It is new-style.
	  (if (evenp length-of-form)
	      (let ((area-form nil) (initial-value-form nil))
		(do ((options (cddr form) (cddr options)))
		    ((null options)
		     `(%make-list ,initial-value-form ,area-form ,(second form)))
		  (let ((keyword-form (car options))
			(value-form (cadr options)))
		    (if (eq (car-safe keyword-form) 'quote) (pop keyword-form))
		    (case keyword-form
		      (:area (setq area-form value-form))
		      ((:initial-value :initial-element)
		       (setq initial-value-form value-form))
		      (otherwise (return nil)))))))))
      form))

(defoptimizer status-optimizer status () (form)
  (let ((status-function (cadr form))
	(item-p (cddr form)))
    (selector status-function string-equal
      (('feature 'features) (if item-p
				(if (and (not (cdddr form))
					 (symbolp (caddr form)))
				    `(not (not (memq ',(intern (symbol-name (caddr form))
							       si:pkg-keyword-package)
						     *features*)))
				  form)
			      `*features*))
      (('tabsize) `8)
      (('userid) `user-id)
      (('site) `local-host-name)
      (('opsys) `':lispm)
      (otherwise (or (mem 'string-equal status-function si:status-status-list)
		     (warn 'unknown-status-function ':impossible "Unknown STATUS function ~A."
			   status-function))
		 form))))

;;; Next two are here mainly to avoid getting an error message from
;;;  GETARGDESC about random FSUBR.
(defoptimizer comment-expand declare)
(defoptimizer comment-expand comment () (ignore)
  `'comment)

(defoptimizer defprop-expand defprop (putprop) (x)
  `(putprop ',(cadr x) ',(caddr x) ',(cadddr x)))

;;; Make *CATCH compile arguments other than the first and the last for
;;; effect rather than for value.
(defoptimizer *catch-prognify *catch () (form)
  (if (cdddr form)
      `(*catch ,(cadr form) (progn . ,(cddr form)))
    form))

;;; Make PROGV work compiled.
(defoptimizer progv-expand progv () (form)
  (let ((varnames (cadr form)) (vals (caddr form)) (body (cdddr form))
	(vars-var (gensym))
	(vals-var (gensym)))
    `(prog ((,vars-var ,varnames) (,vals-var ,vals))
	loop (cond (,vars-var
		    (%bind (inhibit-style-warnings (value-cell-location (car ,vars-var)))
			   (car ,vals-var))
		    (unless ,vals-var
		      (makunbound (car ,vars-var)))
		    (setq ,vars-var (cdr ,vars-var))
		    (setq ,vals-var (cdr ,vals-var))
		    (go loop)))
	   (return (progn . ,body)))))

;;; Turn PROG1 into PROG2 since that is open-coded.
;;; Also turn (PROG1 FOO NIL) into FOO since PBIND generates that and it makes better code
(defoptimizer prog1-prog2 prog1 (prog2) (form)
  (if (equal (cddr form) '(nil))
      (cadr form)
    `(prog2 nil . ,(cdr form))))

(defoptimizer progw-expand progw (prog bind) (form)
  (destructuring-bind (ignore vars-and-vals &body body) form
    (let ((vars-and-vals-var (gensym)))
      `(prog ((,vars-and-vals-var ,vars-and-vals))
	  loop
	     (cond (,vars-and-vals-var
		    (%bind (value-cell-location (caar ,vars-and-vals-var))
			  (eval (cadar ,vars-and-vals-var)))
		    (setq ,vars-and-vals-var (cdr ,vars-and-vals-var))
		    (go loop)))
	     (return (progn . ,body))))))

(defun pbind (vars-and-vals loc)
  (when vars-and-vals
    `(%bind (,loc ,(caar vars-and-vals))
	   (prog1 ,(cadar vars-and-vals)
		  ,(pbind (cdr vars-and-vals) loc)))))

(defrewrite let-if-expand let-if (form)
  (destructuring-bind (ignore cond vars-and-vals &body body) form
    (cond ((null cond) `(let () . ,body))		;Macros generate this
	  ((eq cond t) `(let ,vars-and-vals . ,body))	;and this
	  (t (multiple-value-bind (body decls)
;>> need to pass environment into extract-declarations here
		 (extract-declarations body local-declarations nil)
	       `(let ()
		  (declare . ,decls)
		  (cond (,cond ,(pbind vars-and-vals 'variable-location)))
		  . ,body))))))

(defrewrite letf-expand letf (form)
  `(let ()
     ,(pbind (cadr form) 'locf)
     . ,(cddr form)))

(defrewrite letf*-expand letf* (form)
  `(let ()
     ,@(loop for (place value) in (cadr form)
	     collect `(%bind (locf ,place) ,value))
     . ,(cddr form)))

;;; Turn (CONS foo NIL) into (NCONS foo), saving one instruction.
(defoptimizer cons-ncons cons (ncons) (form)
  (or (and (= (length form) 2)
	   (null (caddr form))
	   `(ncons ,(cadr form)))
      form))

;;; Turn (CONS X (CONS Y NIL)) into (LIST X Y).  Doesn't change (CONS X NIL), though.
;;; Perhaps we want a hairier criterion, for the sake of
;;; those times when you create a list you are going to RPLACA
;;; and don't want LIST to be used.
(defoptimizer cons-list cons (list) (form)
  (cond ((atom (caddr form)) form)
	((eq (caaddr form) 'cons)
	 (let ((tem (cons-list (caddr form))))
	   (cond ((eq (car tem) 'list)
		  `(list ,(cadr form) . ,(cdr tem)))
		 ((member-equal (caddr tem) '(nil 'nil))
		  `(list ,(cadr form) ,(cadr tem)))
		 (t form))))
	(t form)))

(defoptimizer string-search-string-search-char string-search (string-search-char) (form)
  (let ((key (second form)) quotep)
    (if (quotep key)
	(setq key (cadr key) quotep t))
    (if (or (and (or (stringp key)
		     (and quotep (symbolp key)))
		 (= (string-length key) 1))
	    (typep key '(or character integer)))
	`(string-search-char ,(cli:character key) . ,(cddr form))
      form)))

;;;; Convert DOs into PROGs.
(defoptimizer doexpander	do)
(defoptimizer doexpander	do-named)
(defoptimizer doexpander	do*)
(defoptimizer doexpander	do*-named)

(defun doexpander (x)
  (let ((progname) (progrest) serial decls)
    (setq progrest
      (prog (dospecs endtest endvals tag1 tag3 pvars stepdvars once)
            (cond ((eq (car x) 'do-named)
                   (setq progname (cadr x))
                   (setq x (cddr x)))
		  ((eq (car x) 'do*-named)
		   (setq progname (cadr x))
		   (setq x (cddr x))
		   (setq serial t))
		  ((eq (car x) 'do*)
		   (setq x (cdr x))
		   (setq serial t))
                  (t (setq x (cdr x))))			;Get rid of "DO".
            (cond ((and (car x) (atom (car x)))
                   (setq  dospecs `((,(car x) ,(cadr x) ,(caddr x)))
                          endtest (car (setq x (cdddr x)))
                          endvals nil))
                  (t (setq dospecs (car x))
                     (setq x (cdr x))
                     (cond ((car x)
                            (setq endtest (caar x)
                                  endvals (and (or (cddar x)
                                                   (cadar x))
                                               (cdar x))))
                           (t (setq once t)))))
            (setq x (cdr x))
            (setq dospecs (reverse dospecs)); Do NOT use NREVERSE, or you will destroy
					    ; every macro definition in sight!! -DLW
            ;; DOVARS has new-style list of DO variable specs,
            ;; ENDTEST has the end test form,
            ;; ENDVALS has the list of forms to be evaluated when the end test succeeds,
            ;; ONCE is T if this is a DO-once as in (DO ((VAR)) () ...),
            ;; X has the body.
	    (setf (values x decls)
;>> need to pass environment into extract-declarations here
		  (extract-declarations-record-macros x nil nil))
            ;; Now process the variable specs.
            (do ((x dospecs (cdr x))) ((null x))
                (cond ((atom (car x))
		       (push (car x) pvars))
                      ((or (> (length (car x)) 3) (not (atom (caar x))))
		       (warn 'bad-binding-list ':impossible
			     "Malformatted DO-variable specification ~S"
			     (car x)))
		      (t (push `(,(caar x) ,(cadar x)) pvars)
                         (and (cddar x)
                              (push `(,(caar x) ,(caddar x)) stepdvars)))))
            (when once
	      (and stepdvars
		   (warn 'bad-do ':implausible
			 "A once-only DO contains variables to be stepped: ~S."
			 stepdvars))
	      (return `(,pvars . ,x)))
	    ;; Turn STEPDVARS into a PSETQ form to step the vars,
	    ;; or into NIL if there are no vars to be stepped.
            (setq stepdvars (apply #'nconc stepdvars))
	    (and stepdvars (setq stepdvars (cons (if serial 'setq 'psetq) stepdvars)))
            (setq tag3 (gensym))
            (setq tag1 (gensym))
	    (let ((p1value 'predicate))
	      (setq endtest (compiler-optimize endtest)))
            (cond ((null endtest)
		   (compiler-optimize endtest)	;Get any style warnings we were supposed to get,
					;since ENDTEST won't actually be compiled.
                   (and endvals
			(warn 'bad-do ':impossible
			      "The end-test of a DO is NIL, but it says to evaluate ~S on exit."
			      endvals))
                   (return `(,pvars ,tag1
                             ,@x
			     ,stepdvars
                             (go ,tag1)))))
	    (setq endvals `(return-from ,progname (progn nil . ,endvals)))
	    (return `(,pvars
		      (go ,tag3)
		      ,tag1
		      ,@x	;body
		      ,stepdvars
		      ,tag3
		      (or ,endtest (go ,tag1))
		      ,endvals))))
    (and progname (setq progrest (cons progname progrest)))
    (if decls
	`(,(if serial 'prog* 'prog)
	  ,(car progrest)
	  ,.(mapcar #'(lambda (d) `(declare ,d)) decls)
	  . ,(cdr progrest))
      	`(,(if serial 'prog* 'prog)
	  . ,progrest))))

(defoptimizer mapexpand	mapl)
(defoptimizer mapexpand	mapc)
(defoptimizer mapexpand	mapcar)
(defoptimizer mapexpand	maplist)
(defoptimizer mapexpand	mapcan)
(defoptimizer mapexpand	mapcon)

(defun mapexpand (form)
  (if (or (null (cddr form))		;Don't bomb out if no args for the function to map.
	  (not open-code-map-switch))
      form
    (let ((fn (cadr form))
	  call-fn
	  (take-cars (memq (car form) '(mapc mapcar mapcan)))
	  tem)
      ;; Expand maps only if specified function is a quoted LAMBDA or a SUBST,
      ;; or some arg is a call to CIRCULAR-LIST and we are mapping on cars.
      ;; or OPEN-CODE-MAP-SWITCH is set to :ALWAYS.
      (if (not (or (eq open-code-map-switch ':always)
		   (and (memq (car-safe fn) '(quote function))
			(not (atom (cadr fn))))
		   (and (eq (car-safe fn) 'function)
			(not (atom (setq tem (declared-definition (cadr fn)))))
			(memq (car tem) '(global:subst named-subst macro cli:subst))
			(and take-cars
			     (some (cddr form)
				   #'(lambda (x)
				       (and (not (atom x))
					    (null (cddr x))
					    (eq (car x) '(circular-list)))))))))
	  form
	(if (and (not (atom fn)) (memq (car fn) '(quote function)))
	    (setq call-fn (list (cadr fn)))
	  (setq call-fn (list 'funcall fn)))
	;; VARNMS gets a list of gensymmed variables to use to hold
	;; the tails of the lists we are mapping down.
	(let ((varnms) (doclauses) (endtest) (cars-or-tails) (tem))
	  ;; DOCLAUSES looks like ((#:G0001 expression (CDR #:G0001)) ...)
	  ;;  repeated for each variable.
	  ;; ENDTEST is (OR (NULL #:G0001) (NULL #:G0002) ...)
	  ;; CARS-OR-TAILS is what to pass to the specified function:
	  ;;  either (#:G0001 #:G0002 ...) or ((CAR #:G0001) (CAR #:G0002) ...)
	  (setq varnms (do ((l (cddr form) (cdr l)) (output) )
			   ((null l) output)
			 (push (gensym) output)))
	  (setq doclauses
		(mapcar #'(lambda (v l)
			    (cond ((and take-cars (not (atom l))
					(eq (car l) 'circular-list)
					(null (cddr l)))
				   `(,v ,(cadr l)))
				  (t `(,v ,l (cdr ,v)))))
			varnms (cddr form)))
	  (setq endtest
		(cons 'or (mapcan #'(lambda (vl)
				      (and (cddr vl) `((null ,(car vl)))))
				  doclauses)))
	  (setq cars-or-tails
		(cond (take-cars
		       (mapcar #'(lambda (dc)
				   (cond ((cddr dc) `(car ,(car dc)))
					 (t (car dc))))
			       doclauses))
		      (t varnms)))
	  (cond ((memq (car form) '(mapl mapc))	;No result
		 (setq tem `(inhibit-style-warnings
			      (do-named t ,doclauses
					(,endtest)
				(,@call-fn . ,cars-or-tails))))
		 ;; Special hack for MAPL or MAPC for value:
		 ;; Bind an extra local to 2nd list and return that.
		 (if p1value
		     `(let ((map-result ,(prog1 (cadar doclauses)
						(rplaca (cdar doclauses)
							'map-result))))
			,tem
			map-result)
		   tem))
		((memq (car form) '(mapcar maplist))
		 ;; Cons up result
		 (let ((map-result (gensym))
		       (map-temp (gensym)))
		   `(let ((,map-result))
		      (inhibit-style-warnings
			(do-named t ((,map-temp (inhibit-style-warnings
						  (variable-location ,map-result)))
				     . ,doclauses)
				  (,endtest)
			  (rplacd ,map-temp
				  (setq ,map-temp
					(ncons (,@call-fn . ,cars-or-tails))))))
		      ,map-result)))
		(t
		 ;; MAPCAN and MAPCON:  NCONC the result.
		 (let ((map-tem (gensym))
		       (map-result (gensym)))
		   `(inhibit-style-warnings
		      (do-named t (,@doclauses (,map-tem) (,map-result))
				(,endtest ,map-result)
			(setq ,map-tem (nconc ,map-tem (,@call-fn . ,cars-or-tails)))
			(or ,map-result (setq ,map-result ,map-tem))
			(setq ,map-tem (last ,map-tem)))))))
	  )))))


(defoptimizer subset-expand subset)
(defoptimizer subset-expand subset-not)
(defun subset-expand (form)
  (let ((fn (cadr form))
	predargs doclauses tem)
    (cond ((not open-code-map-switch) form)
	  ;; Expand only if specified function is a quoted LAMBDA or a SUBST,
	  ((not (or (and (not (atom fn))
			 (memq (car fn) '(quote function))
			 (not (atom (cadr fn))))
		    (and (not (atom fn))
			 (eq (car fn) 'function)
			 (not (atom (setq tem (declared-definition (cadr fn)))))
			 (memq (car tem) '(subst cli:subst named-subst macro)))))
	   form)
	  (t (setq fn (cadr fn)) ;Strip off the QUOTE or FUNCTION.
	     ;; Generate N local variable names.
	     (do ((l (cddr form) (cdr l)) (i 0 (1+ i)))
		 ((null l))
	       (let ((v (intern (format nil ".MAP-LOCAL-~D." i))))
		 (push `(,v ,(car l) (cdr ,v)) doclauses)
		 (push `(car ,v) predargs)))	       
	     (setq doclauses (nreverse doclauses)
		   predargs (nreverse predargs))
	     `(let (map-result)
		(inhibit-style-warnings
		  (do-named t
		     ((map-temp (inhibit-style-warnings (variable-location map-result)))
		      . ,doclauses)
		     ((null ,(caar doclauses)))	;Stop when first local variable runs out
		    (,(if (eq (car form) 'subset) 'and 'or)
		      (,fn . ,predargs)
		      (rplacd map-temp (setq map-temp (ncons ,(car predargs)))))))
		map-result)))))


(defun fix-synonym-special-form (form)
  `(,(function-name (symbol-function (car form))) . ,(cdr form)))

;;; These functions are defined in ENCAPS, but loaded here
(defoptimizer fix-synonym-special-form si:encapsulation-let (list))
(defoptimizer fix-synonym-special-form si:encapsulation-list* (list*))

(defoptimizer fix-synonym-special-form si:advise-prog (prog))
(defoptimizer fix-synonym-special-form si:advise-setq (setq))
(defoptimizer fix-synonym-special-form si:advise-progn (progn))
(defoptimizer fix-synonym-special-form si:advise-multiple-value-list (multiple-value-list))
(defoptimizer fix-synonym-special-form si:advise-return-list (return-list))
(defoptimizer fix-synonym-special-form si:advise-apply (apply))
(defoptimizer fix-synonym-special-form si:advise-let (let))
(defoptimizer fix-synonym-special-form si:advise-list* (list*))

;;; Style checkers are, unlike optimizers or macro definitions,
;;; run only on user-supplied input, not the results of expansions.
;;; Also, they are not expected to return any values.
;;; They do not alter the input, merely print warnings if there
;;; is anything ugly in it.

;;; Style checkers are used to implement RUN-IN-MACLISP-SWITCH
;;; and OBSOLETE-FUNCTION-WARNING-SWITCH.  They can also warn
;;; about anything else that is ugly or frowned upon, though legal.

(defun obsolete (form)
  (and obsolete-function-warning-switch
       (not run-in-maclisp-switch)
       (warn 'obsolete :obsolete
	     "~S ~A."
	     (car form)
	     (or (get (car form) 'obsolete)
		 "is an obsolete function"))))

(make-obsolete getchar "use strings")
(make-obsolete getcharn "use strings")
(make-obsolete implode "use strings")
(make-obsolete maknam "use strings")
(make-obsolete explode "use strings")
(make-obsolete explodec "use strings")
(make-obsolete exploden "use strings")
(make-obsolete samepnamep "use strings")
;;; This can't go in PROCES because it gets loaded before this file
(make-obsolete process-create "it has been renamed to MAKE-PROCESS")
(make-obsolete si:process-run-temporary-function "PROCESS-RUN-FUNCTION is identical.")
(make-obsolete fs:file-read-property-list "the new name is FS:READ-ATTRIBUTE-LIST")
(make-obsolete fs:file-property-list "the new name is FS:FILE-ATTRIBUTE-LIST")
(make-obsolete fs:file-property-bindings "the new name is FS:FILE-ATTRIBUTE-BINDINGS")
(make-obsolete print-loaded-band "use PRINT-HERALD")
(make-obsolete with-resource "the new name is USING-RESOURCE")

(defprop maknum unimplemented style-checker)
(defprop munkam unimplemented style-checker)
(defprop *rearray unimplemented style-checker)
(defprop *function unimplemented style-checker)
(defprop subrcall unimplemented style-checker)
(defprop lsubrcall unimplemented style-checker)
(defprop pnget unimplemented style-checker)
(defprop pnput unimplemented style-checker)
(defprop fsc unimplemented style-checker)

(defun unimplemented (form)
  (warn 'unimplemented ':implementation-limit
	"The function ~S is not implemented in Zetalisp."
	(car form)))

(defun need-two-args (form)
  (cond ((null (cddr form))
	 (warn 'wrong-number-of-arguments ':implausible
	       "~S used with fewer than two arguments" (car form)))))

;;; fascistic style checking to persecute mucklisp code
(defun (:property append style-checker) (form)
  (need-two-args form)
  (when (and (= (length form) 3)
	     (member-equal (third form) '(nil 'nil)))
    (let ((*print-length* 3) (*print-level* 2))
      (warn 'obsolete ':obsolete "~S is an obsolete way to copy lists;
   use (~S ~S) instead." form 'copy-list (cadr form)))))

(defun (:property global:subst style-checker) (form)
  (when (and (= (length form) 4)		;don't give too many warnings!
	     (member-equal (cadr form) '(nil 'nil))
	     (member-equal (caddr form) '(nil 'nil)))
    (let ((*print-length* 3) (*print-level* 2))
      (warn 'obsolete ':obsolete "~S is an obsolete way to copy trees;
   use (~S ~S) instead." form 'copy-tree (cadddr form)))))

(defun (:property make-list style-checker) (form)
  (if (= (length form) 3)
      (let ((*print-length* 3) (*print-level* 2))
	(warn 'obsolete ':obsolete "~S is an obsolete calling sequence.
   use (~S ~S~@[ ~*~S ~2:*~S~]) instead."
	      form
	      'make-list (third form)
	      (if (member-equal (second form) '(nil 'nil)) nil (second form)) :area))))

(defoptimizer break-decruftify break () (form)
  (if (not (and (symbolp (cadr-safe form)) (not (constantp (cadr-safe form)))))
      form
    (warn 'break-arg :obsolete
	  "A symbol as the first argument to BREAK is an obsolete construct;
change it to a string before it stops working: ~S" form)
    `(break ',(cadr form))))

(defprop setq need-an-arg style-checker)
(defprop psetq need-an-arg style-checker)
(defprop cond need-an-arg style-checker)
(defun need-an-arg (form)
  (or (cdr form)
      (warn 'wrong-number-of-arguments :implausible
	    "~S used with no arguments" (car form))))

(defun (:property format style-checker) (form)
   (need-two-args form)
   (if (stringp (cadr form))
       (warn 'bad-argument :implausible
	     "FORMAT is used with ~S as its first argument,
 which should be a stream, T or NIL." (cadr form))))

(defun (:property value-cell-location style-checker) (form)
  (not-maclisp form)
  (when (eq (car-safe (cadr form)) 'quote)
    (warn 'value-cell-location ':obsolete
	  "VALUE-CELL-LOCATION of quoted variable ~S is obsolete; use VARIABLE-LOCATION"
	  (cadr form))))

(defun (:property boundp style-checker) (form)
  (and (consp (cadr form))
       (eq (caadr form) 'quote)
       (not (specialp (cadadr form)))
       (warn 'boundp ':obsolete
	     "BOUNDP of a quoted nonspecial variable is obsolete; use VARIABLE-BOUNDP")))

;;;; Style-checkers for things that don't work in Maclisp.

;;; These symbols don't exist in Maclisp, though they could, but they are likely losers.
(defprop global:listp not-maclisp style-checker)
(defprop global:nlistp not-maclisp style-checker)
(defprop nsymbolp not-maclisp style-checker)

;;; These functions can't be added to Maclisp by a user.
(defprop intern-local not-maclisp style-checker)
(defprop intern-soft not-maclisp style-checker)
(defprop intern-local-soft not-maclisp style-checker)
(defprop make-array not-maclisp style-checker)
(defprop g-l-p not-maclisp style-checker)
(defprop array-leader not-maclisp style-checker)
(defprop store-array-leader not-maclisp style-checker)
(defprop multiple-value not-maclisp style-checker)
(defprop multiple-value-list not-maclisp style-checker)
(defprop do-named not-maclisp style-checker)
(defprop return-from not-maclisp style-checker)
(defprop return-list not-maclisp style-checker)
(defprop bind not-maclisp style-checker)
(defprop %bind not-maclisp style-checker)
(defprop compiler-let not-maclisp style-checker)
(defprop local-declare not-maclisp style-checker)
(defprop cons-in-area not-maclisp style-checker)
(defprop list-in-area not-maclisp style-checker)
(defprop ncons-in-area not-maclisp style-checker)
(defprop variable-location not-maclisp style-checker)
(defprop variable-boundp not-maclisp style-checker)
(defprop car-location not-maclisp style-checker)
(defprop property-cell-location not-maclisp style-checker)
(defprop function-cell-location not-maclisp style-checker)
(defprop fset not-maclisp style-checker)
(defprop fboundp not-maclisp style-checker)
(defprop fsymeval not-maclisp style-checker)
(defprop closure not-maclisp style-checker)

(defun not-maclisp (form)
  (and run-in-maclisp-switch
       (warn 'not-in-maclisp :maclisp
	     "~S is not implemented in Maclisp." (car form))))

;;; Return with more than one argument won't work in Maclisp.
(defprop return return-style style-checker)
(defun return-style (form)
  (and run-in-maclisp-switch
       (cddr form)
       (warn 'not-in-maclisp ':maclisp
	     "Returning multiple values doesn't work in Maclisp")))

;;; Named PROGs don't work in Maclisp.  PROG variables can't be initialized.
;;; Also, lots of tags and things like a GO to a RETURN are ugly.
(defprop prog prog-style style-checker)
(defun prog-style (form)
  (prog (progname)
	(and (atom (cadr form))
	     (cadr form)
	     (progn (setq progname (cadr form))
		    (setq form (cdr form))))
	(cond (run-in-maclisp-switch
	       (and progname (neq progname t)
		    (warn 'not-in-maclisp ':maclisp
			  "The PROG name ~S is used; PROG names won't work in Maclisp."
			  progname))
	       (dolist (var (cadr form))
		 (or (atom var)
		     (return
		       (warn 'not-in-maclisp ':maclisp
			     "The PROG variable ~S is initialized; this won't work in Maclisp."
			     (car var)))))))))

;;; Check a LAMBDA for things that aren't allowed in Maclisp.
;;; Called only if RUN-IN-MACLISP-SWITCH is set.
(defun lambda-style (lambda-exp)
  (do ((varlist (cadr lambda-exp) (cdr varlist)) (kwdbarf)) ((null varlist))
    (cond ((atom (car varlist))
	   (and (not kwdbarf)
		(memq (car varlist) lambda-list-keywords)
		(setq kwdbarf t)
		(warn 'not-in-maclisp ':maclisp
		      "Lambda-list keywords such as ~S don't work in Maclisp."
		      (car varlist))))
	  (t (warn 'not-in-maclisp ':maclisp
		   "The lambda-variable ~S is initialized; this won't work in Maclisp."
		   (caar varlist))))))


;;;; Turds
(defun *lexpr (&quote &rest l)
  "Declares each symbol in L to be the name of a function.  In
addition it prevents these functions from appearing in the list of
functions referenced but not defined, printed at the end of
compilation."
  (dolist (x l)
    (compilation-define x)
    (putprop x '((#o1005 (fef-arg-opt fef-qt-eval))) 'argdesc)))

(defun *expr (&quote &rest l)
  "Declares each symbol in L to be the name of a function.  In
addition it prevents these functions from appearing in the list of
functions referenced but not defined, printed at the end of
compilation."
  (dolist (x l)
    (compilation-define x)
    (putprop x '((#o1005 (fef-arg-opt fef-qt-eval))) 'argdesc)))

(defun *fexpr (&quote &rest l)
  "Declares each symbol in L to be the name of a special form.  In
addition it prevents these names from appearing in the list of
functions referenced but not defined, printed at the end of
compilation."
  (dolist (x l)
    (compilation-define x)
    (putprop x '((#o1005 (fef-arg-opt fef-qt-qt))) 'argdesc)))
