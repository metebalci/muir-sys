;;;   LOOP  -*- Mode:LISP; Package:System-Internals; Base:8; Lowercase:T -*-
;;;   **********************************************************************
;;;   ****** Universal ******** LOOP Iteration Macro ***********************
;;;   **********************************************************************
;;;   **** (C) COPYRIGHT 1980, 1981 MASSACHUSETTS INSTITUTE OF TECHNOLOGY **
;;;   ******** THIS IS A READ-ONLY FILE! (ALL WRITES RESERVED) *************
;;;   **********************************************************************

;>> This file copied from mit-corwin::nil$disk:[nil.src.spec]loop.lsp;829
;>>   5:34am Friday, 7 December 1984 by Mly
;>> PLEASE PLEASE in the name of sanity which can only be regarded as a fading
;>>  memory in this mindless corporate world try to return all fixes and 
;>>  improvements, so that others may use them, and so that the sources
;>>  maintain some similarity.  Of course, you'll probably just stick your
;>>   fucking corporation's copyright notice here in any case.
;;;; LOOP Iteration Macro

;The master copy of this file is on MC:LSB1;LOOP >    (formerly ML:)
;The current Lisp machine copy is on AI:LISPM2;LOOP >
; or more likely on P:>SYS>SYS2>LOOP and OZ:SRC:<L.SYS2>LOOP
;---> Actually, the most recent development copy is usually on
;---> CORWIN::NIL$DISK:[NIL.SRC.SPEC]LOOP.LSP, so one might need
;---> to contact GSB to ensure that the MC copy is in fact the most
;---> recent.
;The FASL and QFASL should also be accessible from LIBLSP; on all machines.
;(Is this necessary anymore? LOOP is now in the Lisp Machine system and
; is accessible on LISP; and distributed with PDP10 Maclisp.)
;Printed documentation is available as MIT-LCS Technical Memo 169,
; "LOOP Iteration Macro", from:
;	Publications
;	MIT Laboratory for Computer Science
;	545 Technology Square
;	Cambridge, MA 02139
; the text of which appears in only slightly modified form in the Lisp
; Machine manual.
;---> This technical memo is starting to become antiquated, and unfortunately
;---> may cease to be reissued by LCS because Gerry Brown doesn't want to
;---> stock any TM's under number 200 anymore because he says they aren't used.
;---> The most up-to-date LOOP document is included in the NIL manual, which
;---> is LCS Technical Report 311.
; Bugs/complaints/suggestions/solicitations-for-documentation to BUG-LOOP
; at any ITS site (MIT-MC preferred).

;;; the code for PDP-10 and Multics MacLisp, NIL and Franz is deleted.
;;; The #+ and #- conditionals that chose among them are resolved for the Lisp
;;; Machine, and so is the readtime environment that set up their features
;;; while compiling, which is gone with them.


;;;; Macro Environment Setup

;Wrapper for putting around DEFMACRO etc. forms to determine whether
; they are defined in the compiled output file or not.  (It is assumed
; that DEFMACRO forms will be.)  Making loop-macro-progn output for loading
; is convenient if loop will have incremental-recompilation done on it.

(defmacro loop-macro-progn (&rest forms)
  `(progn ,@forms))

; Hack up the stuff for data-types.  DATA-TYPE? will always be a macro
; so that it will not require the data-type package at run time if
; all uses of the other routines are conditionalized upon that value.
(eval-when (eval compile)
  ; Crock for DATA-TYPE? derives from DTDCL.  We just copy it rather
  ; than load it in, which requires knowing where it comes from (sigh).
  ; 
    (defmacro data-type? (frob)
      (let ((foo (gensym)))
	`((lambda (,foo)
	    ; NIL croaks if () given to GET...  No it doesn't any more!  But:
	    ; Every Lisp should (but doesn't) croak if randomness given to GET
	    ; LISPM croaks (of course) if randomness given to get-pname
	    (and (symbolp ,foo)
		 (or (get ,foo ':data-type)
		     (and (setq ,foo (intern-soft (get-pname ,foo) ""))
			  (get ,foo ':data-type)))))
	  ,frob))))

(declare (*lexpr variable-declarations)
	 ; Multics defaults to free-functional-variable since it is declared
	 ; special & used as function before it is defined:
	 (*expr loop-when-it-variable)
	 (*expr initial-value primitive-type))

(declare
  (setq open-code-map-switch t))

(loop-macro-progn
 (defmacro loop-copylist* (l)
    `(copylist* ,l)))


;;;; Random Macros

; Error macro.  Note that in the PDP10 version we call LOOP-DIE rather
; than ERROR -- there are so many occurences of it in this source that
; it is worth breaking off that function, since calling the lsubr ERROR
; takes more inline code.
(loop-macro-progn
 (defmacro loop-simple-error (unquoted-message &optional (datum () datump))
      `(ferror () ,(if datump (string-append "~S " unquoted-message)
		       unquoted-message)
	       . ,(and datump (list datum))))
 (defmacro loop-warn (unquoted-message &optional (datum nil datump))
      `(compiler:warn () ,(if datump
			      (string-append unquoted-message " -- ~{~S~^ ~}")
			      unquoted-message)
	       . ,(and datump (list datum)))))

; This is a KLUDGE.  But it apparently saves an average of two inline
; instructions per call in the PDP10 version...  The ACS prop is
; fairly gratuitous.

(loop-macro-progn
 (defmacro loop-pop-source () '(pop loop-source-code)))

(loop-macro-progn
 (defmacro object-that-cares-p (x)
   `(consp ,x)))

(loop-macro-progn
  (defmacro loop-gentemp (&optional (pref ''loopvar-))
    (declare (ignore pref))
    '(gensym)))


;;;; Variable defining macros

;There is some confusion among lisps as to whether or not a file containing
; a DEFVAR will declare the variable when the compiled file is loaded
; into a compiler.  LOOP assumes that DEFVAR does so (this is needed for
; various user-accessible variables).  DEFIVAR is for "private" variables.
; Note that this is moot for Lispm due to incremental-recompilation support
; anyway.

(loop-macro-progn
 ; A DEFVAR alternative - "DEFine Internal VARiable".
 (defmacro defivar (name &optional (init () initp))
    ; The Lispm choice here is based on likelihood of incremental compilation.
    `(defvar ,name ,@(and initp `(,init)))))




;;;; Setq Hackery

; Note:  LOOP-MAKE-PSETQ is NOT flushable depending on the existence
; of PSETQ, unless PSETQ handles destructuring.  Even then it is
; preferable for the code LOOP produces to not contain intermediate
; macros, especially in the PDP10 version.

(defun loop-make-psetq (frobs)
    (and frobs
	 (loop-make-setq
	    (list (car frobs)
		  (if (null (cddr frobs)) (cadr frobs)
		      `(prog1 ,(cadr frobs)
			      ,(loop-make-psetq (cddr frobs))))))))

(progn 'compile

(defvar si:loop-use-system-destructuring?
    ())

(defivar loop-desetq-temporary)

; Do we want this???  It is, admittedly, useful...
;(defmacro loop-desetq (&rest x)
;  (let ((loop-desetq-temporary ()))
;     (let ((setq-form (loop-make-desetq x)))
;	(if loop-desetq-temporary
;	    `((lambda (,loop-desetq-temporary) ,setq-form) ())
;	    setq-form))))


(defun loop-make-desetq (x)
  ;NIL does not support destructuring LET, however (mainly for LOOP) it
  ; supports a DESETQ special-form/macro.  We should use that to keep the
  ; interpreted code size down, and for better debugging in the interpreter.
   (if si:loop-use-system-destructuring?
       (cons (do ((l x (cddr l))) ((null l) 'setq)
	       (or (and (not (null (car l))) (symbolp (car l)))
		   (return 'desetq)))
	     x)
       (do ((x x (cddr x)) (r ()) (var) (val))
	   ((null x) (and r (cons 'setq r)))
	 (setq var (car x) val (cadr x))
	 (cond ((and (not (atom var))
		     (not (atom val))
		     (not (and (memq (car val)
				     '(car cdr cadr cddr caar cdar))
			       (atom (cadr val)))))
		  (setq x (list* (or loop-desetq-temporary
				     (setq loop-desetq-temporary
					   (loop-gentemp 'loop-desetq-)))
				 val var loop-desetq-temporary (cddr x)))))
	 (setq r (nconc r (loop-desetq-internal (car x) (cadr x)))))))

(defun loop-desetq-internal (var val)
  (cond ((null var) ())
	((atom var) (list var val))
	(t (nconc (loop-desetq-internal (car var) `(car ,val))
		  (loop-desetq-internal (cdr var) `(cdr ,val))))))
)


(defun loop-make-setq (pairs)
    (and pairs
	   (loop-make-desetq pairs)))


(defvar loop-when-function
  'and)

(defvar loop-unless-function
  'or)


(defconst loop-keyword-alist			;clause introducers
     '(
	(named loop-do-named)
	(initially loop-do-initially)
	(finally loop-do-finally)
	(nodeclare loop-nodeclare)
	(do loop-do-do)
	(doing loop-do-do)
	(return loop-do-return)
	(collect loop-do-collect list)
	(collecting loop-do-collect list)
	(append loop-do-collect append)
	(appending loop-do-collect append)
	(nconc loop-do-collect nconc)
	(nconcing loop-do-collect nconc)
	(count loop-do-collect count)
	(counting loop-do-collect count)
	(sum loop-do-collect sum)
	(summing loop-do-collect sum)
	(maximize loop-do-collect max)
	(minimize loop-do-collect min)
	(always loop-do-always nil) ;Normal, do always
	(never loop-do-always t)    ; Negate the test on always.
	(thereis loop-do-thereis)
	(while loop-do-while nil while)	    ; Normal, do while
	(until loop-do-while t until)	    ; Negate the test on while
	(when loop-do-when nil when)	    ; Normal, do when
	(if loop-do-when nil if)    ; synonymous
 	(unless loop-do-when t unless)	    ; Negate the test on when
	(with loop-do-with)))


(defconst loop-iteration-keyword-alist
    `((for loop-do-for)
      (as loop-do-for)
      (repeat loop-do-repeat)))


(defconst loop-for-keyword-alist			;Types of FOR
     '( (= loop-for-equals)
        (first loop-for-first)
	(in loop-list-stepper car)
	(on loop-list-stepper ())
	(from loop-for-arithmetic from)
	(downfrom loop-for-arithmetic downfrom)
	(upfrom loop-for-arithmetic upfrom)
	(below loop-for-arithmetic below)
	(to loop-for-arithmetic to)
	(being loop-for-being)))

(defivar loop-prog-names)

(defivar loop-macro-environment)	;Second arg to macro functions,
					;passed to macroexpand.

(defvar loop-path-keyword-alist ())		; PATH functions
(defivar loop-named-variables)			; see SI:LOOP-NAMED-VARIABLE
(defivar loop-variables)			;Variables local to the loop
(defivar loop-declarations)			; Local dcls for above
(defivar loop-nodeclare)			; but don't declare these
(defivar loop-variable-stack)
(defivar loop-declaration-stack)
(defivar loop-desetq-crocks)			; see loop-make-variable
(defivar loop-desetq-stack)			; and loop-translate-1
(defivar loop-prologue)				;List of forms in reverse order
(defivar loop-wrappers)				;List of wrapping forms, innermost first
(defivar loop-before-loop)
(defivar loop-body)				;..
(defivar loop-after-body)			;.. for FOR steppers
(defivar loop-epilogue)				;..
(defivar loop-after-epilogue)			;So COLLECT's RETURN comes after FINALLY
(defivar loop-conditionals)			;If non-NIL, condition for next form in body
  ;The above is actually a list of entries of the form
  ;(cond (condition forms...))
  ;When it is output, each successive condition will get
  ;nested inside the previous one, but it is not built up
  ;that way because you wouldn't be able to tell a WHEN-generated
  ;COND from a user-generated COND.
  ;When ELSE is used, each cond can get a second clause

(defivar loop-when-it-variable)			;See LOOP-DO-WHEN
(defivar loop-never-stepped-variable)		; see LOOP-FOR-FIRST
(defivar loop-emitted-body?)			; see LOOP-EMIT-BODY,
						; and LOOP-DO-FOR
(defivar loop-iteration-variables)		; LOOP-MAKE-ITERATION-VARIABLE
(defivar loop-iteration-variablep)		; ditto
(defivar loop-collect-cruft)			; for multiple COLLECTs (etc)
(defivar loop-source-code)
(defvar loop-duplicate-code ())  ; see LOOP-OPTIMIZE-DUPLICATED-CODE-ETC


;;;; Construct a value return


(defun loop-construct-return (form)
  (if loop-prog-names
      `(return-from ,(car loop-prog-names) ,form)
      `(return ,form)))



;;;; Token Hackery

;Compare two "tokens".  The first is the frob out of LOOP-SOURCE-CODE,
;the second a symbol to check against.

; Consider having case-independent comparison on Multics.

(progn 'compile
   (defun si:loop-tequal (x1 x2)
	(and (symbolp x1) (string-equal x1 x2)))
   (defun si:loop-tassoc (kwd alist)
	(and (symbolp kwd) (ass #'string-equal kwd alist)))
   (defun si:loop-tmember (kwd list)
	(and (symbolp kwd) (mem #'string-equal kwd list))))



(defmacro define-loop-macro (keyword)
  "Makes KEYWORD, which is a LOOP keyword, into a Lisp macro that may
introduce a LOOP form.  This facility exists mostly for diehard users of
a predecessor of LOOP.  Unconstrained use is not advised, as it tends to
decrease the transportability of the code and needlessly uses up a
function name."
  (or (eq keyword 'loop)
      (si:loop-tassoc keyword loop-keyword-alist)
      (si:loop-tassoc keyword loop-iteration-keyword-alist)
      (loop-simple-error "not a loop keyword - define-loop-macro" keyword))
    `(setf (macro-function ',keyword) 'loop-translate))

(define-loop-macro loop)

(defmacro loop-finish () 
  "Causes the iteration to terminate /"normally/", the same as implicit
termination by an iteration driving clause, or by use of WHILE or
UNTIL -- the epilogue code (if any) will be run, and any implicitly
collected result will be returned as the value of the LOOP."
  '(go end-loop))


(defun loop-translate (x loop-macro-environment)
  (loop-translate-1 x))


(defun loop-end-testify (list-of-forms)
    (if (null list-of-forms) ()
	`(,loop-when-function
	      ,(if (null (cdr (setq list-of-forms (nreverse list-of-forms))))
		   (car list-of-forms)
		   (cons 'or list-of-forms))
	      (go end-loop))))

(defun loop-optimize-duplicated-code-etc (&aux before after groupa groupb a b
					       lastdiff)
    (do ((l1 (nreverse loop-before-loop) (cdr l1))
	 (l2 (nreverse loop-after-body) (cdr l2)))
	((equal l1 l2)
	   (setq loop-body (nconc (delq '() l1) (nreverse loop-body))))
      (push (car l1) before) (push (car l2) after))
    (cond ((not (null loop-duplicate-code))
	     (setq loop-before-loop (nreverse (delq () before))
		   loop-after-body (nreverse (delq () after))))
	  (t (setq loop-before-loop () loop-after-body ()
		   before (nreverse before) after (nreverse after))
	     (do ((bb before (cdr bb)) (aa after (cdr aa)))
		 ((null aa))
	       (cond ((not (equal (car aa) (car bb))) (setq lastdiff aa))
		     ((not (si:loop-simplep (car aa)))	;Mustn't duplicate
		      (return ()))))
	     (cond (lastdiff  ;Down through lastdiff should be duplicated
		    (do () (())
		      (and (car before) (push (car before) loop-before-loop))
		      (and (car after) (push (car after) loop-after-body))
		      (setq before (cdr before) after (cdr after))
		      (and (eq after (cdr lastdiff)) (return ())))
		    (setq loop-before-loop (nreverse loop-before-loop)
			  loop-after-body (nreverse loop-after-body))))
	     (do ((bb (nreverse before) (cdr bb))
		  (aa (nreverse after) (cdr aa)))
		 ((null aa))
	       (setq a (car aa) b (car bb))
	       (cond ((and (null a) (null b)))
		     ((equal a b)
			(loop-output-group groupb groupa)
			(push a loop-body)
			(setq groupb () groupa ()))
		     (t (and a (push a groupa)) (and b (push b groupb)))))
	     (loop-output-group groupb groupa)))
    (and loop-never-stepped-variable
	 (push `(setq ,loop-never-stepped-variable ()) loop-after-body))
    ())


(defun loop-output-group (before after)
    (and (or after before)
	 (let ((v (or loop-never-stepped-variable
		      (setq loop-never-stepped-variable
			    (loop-make-variable
			      (loop-gentemp 'loop-iter-flag-) 't ())))))
	    (push (cond ((not before)
			  `(,loop-unless-function ,v (progn . ,after)))
			((not after)
			  `(,loop-when-function ,v (progn . ,before)))
			(t `(cond (,v . ,before) (t . ,after))))
		  loop-body))))


(defun loop-translate-1 (loop-source-code)
  (and (eq (car loop-source-code) 'loop)
       (setq loop-source-code (cdr loop-source-code)))
  (do ((loop-iteration-variables ())
       (loop-iteration-variablep ())
       (loop-variables ())
       (loop-nodeclare ())
       (loop-named-variables ())
       (loop-declarations ())
       (loop-desetq-crocks ())
       (loop-variable-stack ())
       (loop-declaration-stack ())
       (loop-desetq-stack ())
       (loop-prologue ())
       (loop-wrappers ())
       (loop-before-loop ())
       (loop-body ())
       (loop-emitted-body? ())
       (loop-after-body ())
       (loop-epilogue ())
       (loop-after-epilogue ())
       (loop-conditionals ())
       (loop-when-it-variable ())
       (loop-never-stepped-variable ())
       (loop-desetq-temporary ())
       (loop-prog-names ())
       (loop-collect-cruft ())
       (keyword)
       (tem)
       (progvars))
      ((null loop-source-code)
       (and loop-conditionals
	    (loop-simple-error "Hanging conditional in loop macro"
			       (caadar loop-conditionals)))
       (loop-optimize-duplicated-code-etc)
       (loop-bind-block)
       (and loop-desetq-temporary (push loop-desetq-temporary progvars))
       (setq tem `(prog ,.loop-prog-names
			,progvars
		      ,.(nreverse loop-prologue)
		      ,.loop-before-loop
		   next-loop
		      ,.loop-body
		      ,.loop-after-body
		      (go next-loop)
		      ; Multics complr notices when end-loop is not gone
		      ; to.  So we put in a dummy go.  This does not generate
		      ; extra code, at least in the simple example i tried,
		      ; but it does keep it from complaining about unused
		      ; go tag.
		   end-loop
		      ,.(nreverse loop-epilogue)
		      ,.(nreverse loop-after-epilogue)))
       (do ((vars) (dcls) (crocks))
	   ((null loop-variable-stack))
	 (setq vars (car loop-variable-stack)
	       loop-variable-stack (cdr loop-variable-stack)
	       dcls (car loop-declaration-stack)
	       loop-declaration-stack (cdr loop-declaration-stack)
	       tem (ncons tem))
	   (and (setq crocks (pop loop-desetq-stack))
		(push (loop-make-desetq crocks) tem))
	 (and dcls (push (cons 'declare dcls) tem))
	 (cond ((do ((l vars (cdr l))) ((null l) ())
		  (and (not (atom (car l)))
		       (or (null (caar l)) (not (symbolp (caar l))))
		       (return t)))
		  (setq tem `(let ,(nreverse vars) ,.tem)))
	       (t (let ((lambda-vars ()) (lambda-vals ()))
		    (do ((l vars (cdr l)) (v)) ((null l))
		      (cond ((atom (setq v (car l)))
			       (push v lambda-vars)
			       (push () lambda-vals))
			    (t (push (car v) lambda-vars)
			       (push (cadr v) lambda-vals))))
		    (setq tem `((lambda ,lambda-vars ,.tem)
				,.lambda-vals))))))
       (do ((l loop-wrappers (cdr l))) ((null l))
	 (setq tem (append (car l) (ncons tem))))
       tem)
    (if (symbolp (setq keyword (car loop-source-code)))
	(loop-pop-source)
      (setq keyword 'do))
    (if (setq tem (si:loop-tassoc keyword loop-keyword-alist))
	(apply (cadr tem) (cddr tem))
	(if (setq tem (si:loop-tassoc
			 keyword loop-iteration-keyword-alist))
	    (loop-hack-iteration tem)
	    (if (si:loop-tmember keyword '(and else))
		; Alternative is to ignore it, ie let it go around to the
		; next keyword...
		(loop-simple-error
		   "secondary clause misplaced at top level in LOOP macro"
		   (list keyword (car loop-source-code)
			 (cadr loop-source-code)))
		(loop-simple-error
		   "unknown keyword in LOOP macro" keyword))))))


(defun loop-bind-block ()
   (cond ((not (null loop-variables))
	    (push loop-variables loop-variable-stack)
	    (push loop-declarations loop-declaration-stack)
	    (setq loop-variables () loop-declarations ())
	      (progn (push loop-desetq-crocks loop-desetq-stack)
		     (setq loop-desetq-crocks ())))))


;Get FORM argument to a keyword.  Read up to atom.  PROGNify if necessary.
(defun loop-get-progn-1 ()
  (do ((forms (ncons (loop-pop-source)) (cons (loop-pop-source) forms))
       (nextform (car loop-source-code) (car loop-source-code)))
      ((atom nextform) (nreverse forms))))

(defun loop-get-progn ()
  (let ((forms (loop-get-progn-1)))
    (if (null (cdr forms)) (car forms) (cons 'progn forms))))

(defun loop-get-form (for)
  for					;upwards compat?  Maybe use in errors?
;  (let ((forms (loop-get-progn-1)))
;    (cond ((null (cdr forms)) (car forms))
;	  (t (loop-warn 
;"The use of multiple forms with an implicit PROGN in this context
;is considered obsolete, but is still supported for the time being.
;If you did not intend to use multiple forms here, you probably omitted a DO.
;If the use of multiple forms was intentional, put a PROGN in your code.
;The offending clause"
;		(if (atom for) (cons for forms) (append for forms)))
;	     (cons 'progn forms))))
  (loop-pop-source))


;Note that this function is not absolutely general.  For instance, in Maclisp,
; the functions < and > can only take 2 args, whereas greaterp and lessp
; may take any number.  Also, certain of the generic functions behave
; differently from the type-specific ones in "degenerate" cases, like
; QUOTIENT or DIFFERENCE of one arg.
;And of course one always must be careful doing textual substitution.
(defun loop-typed-arith (substitutable-expression data-type)
    (progn data-type substitutable-expression))

(defvar loop-floating-point-types
    '(flonum float short-float single-float double-float long-float
	     small-flonum))

(defun loop-typed-init (data-type)
  (let ((tem nil))
    (cond ((data-type? data-type) (initial-value data-type))
	  ((si:loop-tmember data-type '(fixnum integer number)) 0)
	  ((setq tem (car (si:loop-tmember
			    data-type loop-floating-point-types)))
	       (cond ((memq tem '(flonum float)) 0.0)
		     (t
			(coerce 0 tem)))))))


(defun loop-make-variable (name initialization dtype)
  (cond ((null name)
	   (cond ((not (null initialization))
		    (push (list 'ignore
				initialization)
			  loop-variables))))
	((atom name)
	   (cond (loop-iteration-variablep
		    (if (memq name loop-iteration-variables)
			(loop-simple-error
			   "Duplicated iteration variable somewhere in LOOP"
			   name)
			(push name loop-iteration-variables)))
		 ((assq name loop-variables)
		    (loop-simple-error
		       "Duplicated var in LOOP bind block" name)))
	   (or (symbolp name)
	       (loop-simple-error "Bad variable somewhere in LOOP" name))
	   (loop-declare-variable name dtype)
	   ; We use ASSQ on this list to check for duplications (above),
	   ; so don't optimize out this list:
	   (push (list name (or initialization (loop-typed-init dtype)))
		 loop-variables))
	(initialization
	     (cond (si:loop-use-system-destructuring?
		      (loop-declare-variable name dtype)
		      (push (list name initialization) loop-variables))
		   (t (let ((newvar (loop-gentemp 'loop-destructure-)))
			 (push (list newvar initialization) loop-variables)
			 ; LOOP-DESETQ-CROCKS gathered in reverse order.
			 (setq loop-desetq-crocks
			       (list* name newvar loop-desetq-crocks))
			 (loop-make-variable name () dtype)))))
	(t (let ((tcar) (tcdr))
	     (if (atom dtype) (setq tcar (setq tcdr dtype))
	       (setq tcar (car dtype) tcdr (cdr dtype)))
	     (loop-make-variable (car name) () tcar)
	     (loop-make-variable (cdr name) () tcdr))))
  name)


(defun loop-make-iteration-variable (name initialization dtype)
    (let ((loop-iteration-variablep 't))
       (loop-make-variable name initialization dtype)))


(defun loop-declare-variable (name dtype)
    (cond ((or (null name) (null dtype)) ())
	  ((symbolp name)
	     (cond ((memq name loop-nodeclare))
		   ((data-type? dtype)
		      (setq loop-declarations
			    (append (variable-declarations dtype name)
				    loop-declarations)))))
	  ((object-that-cares-p name)
	      (cond ((object-that-cares-p dtype)
		       (loop-declare-variable (car name) (car dtype))
		       (loop-declare-variable (cdr name) (cdr dtype)))
		    (t (loop-declare-variable (car name) dtype)
		       (loop-declare-variable (cdr name) dtype))))
	  (t (loop-simple-error "can't hack this"
				(list 'loop-declare-variable name dtype)))))


(defun loop-constantp (form)
  (constantp form))

(defun loop-maybe-bind-form (form data-type?)
    ; Consider implementations which will not keep EQ quoted constants
    ; EQ after compilation & loading.
    ; Note FUNCTION is not hacked, multiple occurences might cause the
    ; compiler to break the function off multiple times!
    ; Hacking it probably isn't too important here anyway.  The ones that
    ; matter are the ones that use it as a stepper (or whatever), which
    ; handle it specially.
    (if (loop-constantp form) form
	(loop-make-variable (loop-gentemp 'loop-bind-) form data-type?)))


(defun loop-optional-type ()
    (let ((token (car loop-source-code)))
	(and (not (null token))
	     (or (not (atom token))
		 (data-type? token)
		 (si:loop-tmember token '(fixnum integer number notype))
		 (si:loop-tmember token loop-floating-point-types))
	     (loop-pop-source))))


;Incorporates conditional if necessary
(defun loop-make-conditionalization (form)
  (cond ((not (null loop-conditionals))
	   (rplacd (last (car (last (car (last loop-conditionals)))))
		   (ncons form))
	   (cond ((si:loop-tequal (car loop-source-code) 'and)
		    (loop-pop-source)
		    ())
		 ((si:loop-tequal (car loop-source-code) 'else)
		    (loop-pop-source)
		    ;; If we are already inside an else clause, close it off
		    ;; and nest it inside the containing when clause
		    (let ((innermost (car (last loop-conditionals))))
		      (cond ((null (cddr innermost)))	;Now in a WHEN clause, OK
			    ((null (cdr loop-conditionals))
			     (loop-simple-error "More ELSEs than WHENs"
						(list 'else (car loop-source-code)
						      (cadr loop-source-code))))
			    (t (setq loop-conditionals (cdr (nreverse loop-conditionals)))
			       (rplacd (last (car (last (car loop-conditionals))))
				       (ncons innermost))
			       (setq loop-conditionals (nreverse loop-conditionals)))))
		    ;; Start a new else clause
		    (rplacd (last (car (last loop-conditionals)))
			    (ncons (ncons ''t)))
		    ())
		 (t ;Nest up the conditionals and output them
		     (do ((prev (car loop-conditionals) (car l))
			  (l (cdr loop-conditionals) (cdr l)))
			 ((null l))
		       (rplacd (last (car (last prev))) (ncons (car l))))
		     (prog1 (car loop-conditionals)
			    (setq loop-conditionals ())))))
	(t form)))

(defun loop-pseudo-body (form &aux (z (loop-make-conditionalization form)))
   (cond ((not (null z))
	    (cond (loop-emitted-body? (push z loop-body))
		  (t (push z loop-before-loop) (push z loop-after-body))))))

(defun loop-emit-body (form)
  (setq loop-emitted-body? 't)
  (loop-pseudo-body form))


(defun loop-do-named ()
    (let ((name (loop-pop-source)))
       (or (and name (symbolp name))
	   (loop-simple-error "Bad name for your loop construct" name))
       ;If this don't come first, LOOP will be confused about how to return
       ; from the prog when it tries to generate such code (as is necessary
       ; under #+Common-Lisp-PROGs).
       ;Should this error check be made always?
       (and (or loop-before-loop loop-body loop-after-epilogue)
	    (loop-simple-error "NAMED clause occurs too late" name))
       (and (cdr (setq loop-prog-names (cons name loop-prog-names)))
	    (loop-simple-error "Too many names for your loop construct"
			       loop-prog-names))))

(defun loop-do-initially ()
  (push (loop-get-progn) loop-prologue))

(defun loop-nodeclare (&aux (varlist (loop-pop-source)))
    (or (null varlist)
	(object-that-cares-p varlist)
	(loop-simple-error "Bad varlist to nodeclare loop clause" varlist))
    (setq loop-nodeclare (append varlist loop-nodeclare)))

(defun loop-do-finally ()
  (push (loop-get-progn) loop-epilogue))

(defun loop-do-do ()
  (loop-emit-body (loop-get-progn)))

(defun loop-do-return ()
   (loop-pseudo-body (loop-construct-return (loop-get-form 'return))))


;;;; Macro support for collection

; The way we collect (list-collect) things is to bind two variables.
; One is the final result, and is accessible for value during the
; loop compuation.  The second is the "tail".  In implementations where
; we can do so, the tail var is initialized to a locative of the first,
; such that it can be updated with RPLACD.  In other implementations,
; the update must be conditionalized (on whether or not the tail is NIL).

(progn 'compile

;This is an a-list with entries of the form (headvar tailvar), into which
; collection is being performed.  It is bound by the wrapper macro using
; compiler-let.  Note that there is an environment sort of bug, in that
; loop itself will be doing macro expansions of the code it generates, and
; as a result the loop-collect-rplacd form will barf because it is not within
; the loop-list-collector macro.  As a result, anything within loop which
; does macro expansion HAS to special case loop-collect-rplacd.
(defvar loop-collection-stack
  nil)

(defmacro loop-list-collector (headvar &body body)
  ;NIL cannot do variable-location directly, and had even more trouble doing
  ; so with special variables than with locals.  However there is a hack
  ; special-form which does all this for us.
    (let ((tailvar (gensym)))
      `(compiler-let ((loop-collection-stack
			(cons '(,headvar ,tailvar) loop-collection-stack)))
	 (let (,headvar ,tailvar)
	   (setq ,tailvar (variable-location ,headvar))
	   ,@body))))


(defmacro loop-collect-rplacd (headvar form)
    (let* ((data (or (assq headvar loop-collection-stack)
		     (error "What's going on here?")))
	   (tailvar (cadr data)))
      (cond ((and (consp form) (eq (car form) 'list) (cdr form))
	       (cond ((null (cddr form))
		       `(rplacd ,tailvar (setq ,tailvar (ncons ,(cadr form)))))
		     (t ;Kludginess for rplacd on cdr-coded lists...
			`(setq ,tailvar
			       ,(loop-cdrify
				  (cdr form)
				  `(rplacd ,tailvar
					   (list* ,@(cdr form) nil)))))))
	    (t ;This last may deserve modification to (setf (cdr ...) ...)
	       ; if the implementation can return the proper value more easily.
	       `(and (cdr (rplacd ,tailvar ,form))
		     (setq ,tailvar (last (cdr ,tailvar))))))))
);End of #+Hairy-Collection progn.


(defun loop-do-collect (type)
  (let ((var) (form) (tem) (tail) (dtype) (cruft) (rvar)
	(ctype (cond ((memq type '(max min)) 'maxmin)
		     ((memq type '(nconc list append)) 'list)
		     ((memq type '(count sum)) 'sum)
		     (t (loop-simple-error
			    "unrecognized LOOP collecting keyword" type)))))
    (setq form (loop-get-form type) dtype (loop-optional-type))
    (cond ((si:loop-tequal (car loop-source-code) 'into)
	     (loop-pop-source)
	     (setq rvar (setq var (loop-pop-source)))))
    ; CRUFT will be (varname ctype dtype var tail (optional tem))
    (cond ((setq cruft (assq var loop-collect-cruft))
	     (cond ((not (eq ctype (car (setq cruft (cdr cruft)))))
		      (loop-simple-error
		         "incompatible LOOP collection types"
			 (list ctype (car cruft))))
		   ((and dtype (not (eq dtype (cadr cruft))))
		      ;Conditional should be on data-type reality
		        (ferror () "~A and ~A Unequal data types into ~A"
				dtype (cadr cruft) (car cruft))))
	     (setq dtype (car (setq cruft (cdr cruft)))
		   var (car (setq cruft (cdr cruft)))
		   tail (car (setq cruft (cdr cruft)))
		   tem (cadr cruft))
	     (and (eq ctype 'maxmin)
		  (not (atom form)) (null tem)
		  (rplaca (cdr cruft)
			  (setq tem (loop-make-variable
				       (loop-gentemp 'loop-maxmin-)
				       () dtype)))))
	  (t (and (null dtype)
		  (setq dtype (cond ((eq type 'count) 'fixnum)
				    ((memq type '(min max sum)) 'number))))
	     (or var (push (loop-construct-return (setq var (loop-gentemp)))
			   loop-after-epilogue))
	     (or (eq ctype 'list) (loop-make-iteration-variable var () dtype))
	     (cond ((eq ctype 'maxmin)
		      ;Make a temporary.
		      (or (atom form)
			  (setq tem (loop-make-variable
				      (loop-gentemp) () dtype)))
		      ;Use the tail slot of the collect database to hold a
		      ; flag which says we have been around once already.
		      (setq tail (loop-make-variable
				   (loop-gentemp 'loop-maxmin-fl-) t nil)))
		   ((eq ctype 'list)
		    ;For dumb collection, we need both a tail and a flag var
		    ; to tell us whether we have iterated.
		    ;Gofoo-collection uses these collection crocks, and we also
		    ; have to manipulate the tail ourselves.
		    ;Under hairy-collection, the tail is manipulated by the
		    ; wrapper and the included loop-collect-rplacd form(s).
		    ; So we make no such variable here.  Just make the wrapper.
		      (push `(loop-list-collector ,var) loop-wrappers)))
	     (push (list rvar ctype dtype var tail tem)
		   loop-collect-cruft)))
    (loop-emit-body
	(caseq type
	  (count (setq tem `(setq ,var (,(loop-typed-arith 'add1 dtype)
					,var)))
		 (if (or (eq form 't) (equal form ''t))
		     tem
		     `(,loop-when-function ,form ,tem)))
	  (sum `(setq ,var (,(loop-typed-arith 'plus dtype) ,form ,var)))
	  ((max min)
	     (let ((forms ()) (arglist ()))
		; TEM is temporary, properly typed.
		(and tem (setq forms `((setq ,tem ,form)) form tem))
		(setq arglist (list var form))
		(push (if (si:loop-tmember dtype '(fixnum flonum
						     small-flonum))
			  ; no contagious arithmetic
			  `(,loop-when-function
				(or ,tail
				    (,(loop-typed-arith
				         (if (eq type 'max) 'lessp 'greaterp)
					 dtype)
				     . ,arglist))
				(setq ,tail () . ,arglist))
			  ; potentially contagious arithmetic -- must use
			  ; MAX or MIN so that var will be contaminated
			  `(setq ,var (cond (,tail (setq ,tail ()) ,form)
					    ((,type . ,arglist)))))
		      forms)
		(if (cdr forms) (cons 'progn (nreverse forms)) (car forms))))
	  (t (caseq type
		(list (setq form (list 'list form)))
		(append (or (and (not (atom form)) (eq (car form) 'list))
			    (setq form `(copylist* ,form)))))
	     `(loop-collect-rplacd ,var ,form))))))


(defun loop-cdrify (arglist form)
    (do ((size (length arglist) (- size 4)))
	((< size 4)
	 (if (zerop size) form
	     (list (cond ((= size 1) 'cdr) ((= size 2) 'cddr) (t 'cdddr))
		   form)))
      (setq form (list 'cddddr form))))



(defun loop-do-while (negate? kwd &aux (form (loop-get-form kwd)))
  (and loop-conditionals (loop-simple-error
			   "not allowed inside LOOP conditional"
			   (list kwd form)))
  (loop-pseudo-body `(,(if negate? loop-when-function loop-unless-function)
		      ,form (go end-loop))))


(defun loop-do-when (negate? kwd)
  (let ((form (loop-get-form kwd)) (cond))
    (cond ((si:loop-tequal (cadr loop-source-code) 'it)
	     ;WHEN foo RETURN IT and the like
	     (setq cond `(setq ,(loop-when-it-variable) ,form))
	     (setq loop-source-code		;Plug in variable for IT
		   (list* (car loop-source-code)
			  loop-when-it-variable
			  (cddr loop-source-code))))
	  (t (setq cond form)))
    (and negate? (setq cond `(not ,cond)))
    (setq loop-conditionals (nconc loop-conditionals `((cond (,cond)))))))

(defun loop-do-with ()
  (do ((var) (equals) (val) (dtype)) (())
    (setq var (loop-pop-source) equals (car loop-source-code))
    (cond ((si:loop-tequal equals '=)
	     (loop-pop-source)
	     (setq val (loop-get-form (list 'with var '=)) dtype ()))
	  ((or (si:loop-tequal equals 'and)
	       (si:loop-tassoc equals loop-keyword-alist)
	       (si:loop-tassoc equals loop-iteration-keyword-alist))
	     (setq val () dtype ()))
	  (t (setq dtype (loop-optional-type) equals (car loop-source-code))
	     (cond ((si:loop-tequal equals '=)
		      (loop-pop-source)
		      (setq val (loop-get-form (list 'with var dtype '=))))
		   ((and (not (null loop-source-code))
			 (not (si:loop-tassoc equals loop-keyword-alist))
			 (not (si:loop-tassoc
				 equals loop-iteration-keyword-alist))
			 (not (si:loop-tequal equals 'and)))
		      (loop-simple-error "Garbage where = expected" equals))
		   (t (setq val ())))))
    (loop-make-variable var val dtype)
    (if (not (si:loop-tequal (car loop-source-code) 'and)) (return ())
	(loop-pop-source)))
  (loop-bind-block))

(defun loop-do-always (negate?)
  (let ((form (loop-get-form 'always)))
    (loop-emit-body `(,(if negate?
			   'and
			   'or)
		      ,form
		      ,(loop-construct-return nil)))
    (push (loop-construct-return t) loop-after-epilogue)))

;THEREIS expression
;If expression evaluates non-nil, return that value.
(defun loop-do-thereis ()
   (loop-emit-body `(,loop-when-function
			 (setq ,(loop-when-it-variable)
			       ,(loop-get-form 'thereis))
			 ,(loop-construct-return loop-when-it-variable))))


;;;; Hacks

(defun si:loop-simplep (expr)
    (if (null expr) 0
	(*catch 'si:loop-simplep
	    (let ((ans (si:loop-simplep-1 expr)))
	       (and (< ans 20.) ans)))))

(defvar si:loop-simplep
  (append '(> < greaterp lessp plusp minusp typep zerop
	    plus difference + - add1 sub1 1+ 1-
	    +$ -$ 1+$ 1-$ boole rot ash ldb equal atom
	    setq prog1 prog2 and or =)
	  '(aref ar-1 ar-2 ar-3)
	  '#.(mapcar 'ascii '(#/ #/ #/))))

(defun si:loop-simplep-1 (x)
  (let ((z 0))
    (cond ((loop-constantp x) 0)
	  ((atom x) 1)
	  ((eq (car x) 'cond)
	     (do ((cl (cdr x) (cdr cl))) ((null cl))
	       (do ((f (car cl) (cdr f))) ((null f))
		 (setq z (+ (si:loop-simplep-1 (car f)) z 1))))
	     z)
	  ((symbolp (car x))
	     (let ((fn (car x)) (tem ()))
	       (cond ((setq tem (get fn 'si:loop-simplep))
		        (if (fixp tem) (setq z tem)
			    (setq z (funcall tem x) x ())))
		     ((memq fn '(null not eq go return progn)))
		     ((memq fn '(car cdr))
		        (setq z 1))
		     ((memq fn '(caar cadr cdar cddr)) (setq z 2))
		     ((memq fn '(caaar caadr cadar caddr
				 cdaar cdadr cddar cdddr))
		        (setq z 3))
		     ((memq fn '(caaaar caaadr caadar caaddr
				 cadaar cadadr caddar cadddr
				 cdaaar cdaadr cdadar cdaddr
				 cddaar cddadr cdddar cddddr))
		        (setq z 4))
		     ((memq fn si:loop-simplep)
		        (setq z 2))
		     ((eq fn 'loop-collect-rplacd)
		        (*throw 'si:loop-simplep-1 nil))
		     ((not (eq (setq tem (macroexpand-1 x loop-macro-environment))
				 x))
		      (setq z (si:loop-simplep-1 tem) x ()))
		     (t (*throw 'si:loop-simplep ())))
	       (do ((l (cdr x) (cdr l))) ((null l))
		 (setq z (+ (si:loop-simplep-1 (car l)) 1 z)))
	       z))
	  (t (*throw 'si:loop-simplep ())))))


;;;; The iteration driver
(defun loop-hack-iteration (entry)
  (do ((last-entry entry)
       (source loop-source-code loop-source-code)
       (pre-step-tests ())
       (steps ())
       (post-step-tests ())
       (pseudo-steps ())
       (pre-loop-pre-step-tests ())
       (pre-loop-steps ())
       (pre-loop-post-step-tests ())
       (pre-loop-pseudo-steps ())
       (tem) (data) (foo) (bar))
      (())
    ; Note we collect endtests in reverse order, but steps in correct
    ; order.  LOOP-END-TESTIFY does the nreverse for us.
    (setq tem (setq data (apply (cadr entry) (cddr entry))))
    (and (car tem) (push (car tem) pre-step-tests))
    (setq steps (nconc steps (loop-copylist* (car (setq tem (cdr tem))))))
    (and (car (setq tem (cdr tem))) (push (car tem) post-step-tests))
    (setq pseudo-steps
	  (nconc pseudo-steps (loop-copylist* (car (setq tem (cdr tem))))))
    (setq tem (cdr tem))
    (and (or loop-conditionals loop-emitted-body?)
	 (or tem pre-step-tests post-step-tests pseudo-steps)
	 (let ((cruft (list (car entry) (car source)
			    (cadr source) (caddr source))))
	    (if loop-emitted-body?
		(loop-simple-error
		   "Iteration is not allowed to follow body code" cruft)
		(loop-simple-error
		   "Iteration starting inside of conditional in LOOP"
		   cruft))))
    (or tem (setq tem data))
    (and (car tem) (push (car tem) pre-loop-pre-step-tests))
    (setq pre-loop-steps
	  (nconc pre-loop-steps (loop-copylist* (car (setq tem (cdr tem))))))
    (and (car (setq tem (cdr tem))) (push (car tem) pre-loop-post-step-tests))
    (setq pre-loop-pseudo-steps
	  (nconc pre-loop-pseudo-steps (loop-copylist* (cadr tem))))
    (cond ((or (not (si:loop-tequal (car loop-source-code) 'and))
	       (and loop-conditionals
		    (not (si:loop-tassoc (cadr loop-source-code)
					 loop-iteration-keyword-alist))))
	     (setq foo (list (loop-end-testify pre-loop-pre-step-tests)
			     (loop-make-psetq pre-loop-steps)
			     (loop-end-testify pre-loop-post-step-tests)
			     (loop-make-setq pre-loop-pseudo-steps))
		   bar (list (loop-end-testify pre-step-tests)
			     (loop-make-psetq steps)
			     (loop-end-testify post-step-tests)
			     (loop-make-setq pseudo-steps)))
	     (cond ((not loop-conditionals)
		      (setq loop-before-loop (nreconc foo loop-before-loop)
			    loop-after-body (nreconc bar loop-after-body)))
		   (t ((lambda (loop-conditionals)
			  (push (loop-make-conditionalization
				   (cons 'progn (delq () foo)))
				loop-before-loop))
		       (mapcar '(lambda (x)	;Copy parts that will get rplacd'ed
				  (cons (car x)
					(mapcar '(lambda (x) (loop-copylist* x)) (cdr x))))
			       loop-conditionals))
		      (push (loop-make-conditionalization
			       (cons 'progn (delq () bar)))
			    loop-after-body)))
	     (loop-bind-block)
	     (return ())))
    (loop-pop-source) ; flush the "AND"
    (setq entry (cond ((setq tem (si:loop-tassoc
				    (car loop-source-code)
				    loop-iteration-keyword-alist))
		         (loop-pop-source)
			 (setq last-entry tem))
		      (t last-entry)))))


;FOR variable keyword ..args..
(defun loop-do-for ()
  (let ((var (loop-pop-source))
	(data-type? (loop-optional-type))
	(keyword (loop-pop-source))
	(first-arg nil)
	(tem ()))
    (setq first-arg (loop-get-form (list 'for var keyword)))
    (or (setq tem (si:loop-tassoc keyword loop-for-keyword-alist))
	(loop-simple-error
	   "Unknown keyword in FOR or AS clause in LOOP"
	   (list 'for var keyword)))
    (lexpr-funcall (cadr tem) var first-arg data-type? (cddr tem))))


(defun loop-do-repeat ()
    (let ((var (loop-make-variable
		  (loop-gentemp 'loop-repeat-)
		  (loop-get-form 'repeat) 'fixnum)))
       `((not (,(loop-typed-arith 'plusp 'fixnum) ,var))
         () ()
         (,var (,(loop-typed-arith 'sub1 'fixnum) ,var)))))


; Kludge the First
(defun loop-when-it-variable ()
    (or loop-when-it-variable
	(setq loop-when-it-variable
	      (loop-make-variable (loop-gentemp 'loop-it-) () ()))))



(defun loop-for-equals (var val data-type?)
  (cond ((si:loop-tequal (car loop-source-code) 'then)
	   ;FOR var = first THEN next
	   (loop-pop-source)
	   (loop-make-iteration-variable var val data-type?)
	   `(() (,var ,(loop-get-form (list 'for var '= val 'then))) () ()
	     () () () ()))
	(t (loop-make-iteration-variable var () data-type?)
	   (let ((varval (list var val)))
	     (cond (loop-emitted-body?
		    (loop-emit-body (loop-make-setq varval))
		    '(() () () ()))
		   (`(() ,varval () ())))))))

(defun loop-for-first (var val data-type?)
    (or (si:loop-tequal (car loop-source-code) 'then)
	(loop-simple-error "found where THEN expected in FOR ... FIRST"
			   (car loop-source-code)))
    (loop-pop-source)
    (loop-make-iteration-variable var () data-type?)
    `(() (,var ,(loop-get-form (list 'for var 'first val 'then))) () ()
      () (,var ,val) () ()))


(defun loop-list-stepper (var val data-type? fn)
    (let ((stepper (cond ((si:loop-tequal (car loop-source-code) 'by)
			    (loop-pop-source)
			    (loop-get-form (list 'for var
						 (if (eq fn 'car) 'in 'on)
						 val 'by)))
			 (t '(function cdr))))
	  (var1 ()) (stepvar ()) (step ()) (et ()) (pseudo ()))
       (setq step (if (or (atom stepper)
			  (not (memq (car stepper) '(quote function))))
		      `(funcall ,(setq stepvar (loop-gentemp 'loop-fn-)))
		      (list (cadr stepper))))
       (cond ((and (atom var)
		   ;; (eq (car step) 'cdr)
		   (not fn))
	        (setq var1 (loop-make-iteration-variable var val data-type?)))
	     (t (loop-make-iteration-variable var () data-type?)
		(setq var1 (loop-make-variable
			     (loop-gentemp 'loop-list-) val ()))
		(setq pseudo (list var (if fn (list fn var1) var1)))))
       (rplacd (last step) (list var1))
       (and stepvar (loop-make-variable stepvar stepper ()))
       (setq stepper (list var1 step) et `(null ,var1))
       (if (not pseudo) `(() ,stepper ,et () () () ,et ())
	   (if (eq (car step) 'cdr) `(,et ,pseudo () ,stepper)
	       `((null (setq . ,stepper)) () () ,pseudo ,et () () ,pseudo)))))


(defun loop-for-arithmetic (var val data-type? kwd)
  ; Args to loop-sequencer:
  ; indexv indexv-type variable? vtype? sequencev? sequence-type
  ; stephack? default-top? crap prep-phrases
  (si:loop-sequencer
     var (or data-type? 'fixnum) () () () () () () `(for ,var ,kwd ,val)
     (cons (list kwd val)
	   (loop-gather-preps
	      '(from upfrom downfrom to upto downto above below by)
	      ()))))


(defun si:loop-named-variable (name)
    (let ((tem (si:loop-tassoc name loop-named-variables)))
       (cond ((null tem) (loop-gentemp))
	     (t (setq loop-named-variables (delq tem loop-named-variables))
		(cdr tem)))))

; Note:  path functions are allowed to use loop-make-variable, hack
; the prologue, etc.
(defun loop-for-being (var val data-type?)
   ; FOR var BEING something ... - var = VAR, something = VAL.
   ; If what passes syntactically for a pathname isn't, then
   ; we trap to the DEFAULT-LOOP-PATH path;  the expression which looked like
   ; a path is given as an argument to the IN preposition.  Thus,
   ; by default, FOR var BEING EACH expr OF expr-2
   ; ==> FOR var BEING DEFAULT-LOOP-PATH IN expr OF expr-2.
   (let ((tem) (inclusive?) (ipps) (each?) (attachment))
     (if (or (si:loop-tequal val 'each) (si:loop-tequal val 'the))
	 (setq each? 't val (car loop-source-code))
	 (push val loop-source-code))
     (cond ((and (setq tem (si:loop-tassoc val loop-path-keyword-alist))
		 (or each? (not (si:loop-tequal (cadr loop-source-code)
						'and))))
	      ;; FOR var BEING {each} path {prep expr}..., but NOT
	      ;; FOR var BEING var-which-looks-like-path AND {ITS} ...
	      (loop-pop-source))
	   (t (setq val (loop-get-form (list 'for var 'being)))
	      (cond ((si:loop-tequal (car loop-source-code) 'and)
		       ;; FOR var BEING value AND ITS path-or-ar
		       (or (null each?)
			   (loop-simple-error
			      "Malformed BEING EACH clause in LOOP" var))
		       (setq ipps `((of ,val)) inclusive? 't)
		       (loop-pop-source)
		       (or (si:loop-tmember (setq tem (loop-pop-source))
					    '(its his her their each))
			   (loop-simple-error
			      "found where ITS or EACH expected in LOOP path"
			      tem))
		       (if (setq tem (si:loop-tassoc
					(car loop-source-code)
					loop-path-keyword-alist))
			   (loop-pop-source)
			   (push (setq attachment
				       `(in ,(loop-get-form
					      `(for ,var being /././. in))))
				 ipps)))
		    ((not (setq tem (si:loop-tassoc
				       (car loop-source-code)
				       loop-path-keyword-alist)))
		       ; FOR var BEING {each} a-r ...
		       (setq ipps (list (setq attachment (list 'in val)))))
		    (t ; FOR var BEING {each} pathname ...
		       ; Here, VAL should be just PATHNAME.
		       (loop-pop-source)))))
     (cond ((not (null tem)))
	   ((not (setq tem (si:loop-tassoc 'default-loop-path
					   loop-path-keyword-alist)))
	      (loop-simple-error "Undefined LOOP iteration path"
				 (cadr attachment))))
     (setq tem (funcall (cadr tem) (car tem) var data-type?
			(nreconc ipps (loop-gather-preps (caddr tem) 't))
			inclusive? (caddr tem) (cdddr tem)))
     (and loop-named-variables
	  (loop-simple-error "unused USING variables" loop-named-variables))
     ; For error continuability (if there is any):
     (setq loop-named-variables ())
     ;; TEM is now (bindings prologue-forms . stuff-to-pass-back)
     (do ((l (car tem) (cdr l)) (x)) ((null l))
       (if (atom (setq x (car l)))
	   (loop-make-iteration-variable x () ())
	   (loop-make-iteration-variable (car x) (cadr x) (caddr x))))
     (setq loop-prologue (nconc (reverse (cadr tem)) loop-prologue))
     (cddr tem)))


(defun loop-gather-preps (preps-allowed crockp)
   (do ((token (car loop-source-code) (car loop-source-code)) (preps ()))
       (())
     (cond ((si:loop-tmember token preps-allowed)
	      (push (list (loop-pop-source)
			  (loop-get-form `(for /././. being /././. ,token)))
		    preps))
	   ((si:loop-tequal token 'using)
	      (loop-pop-source)
	      (or crockp (loop-simple-error
			    "USING used in illegal context"
			    (list 'using (car loop-source-code))))
	      (do ((z (car loop-source-code) (car loop-source-code)) (tem))
		  ((atom z))
		(and (or (atom (cdr z))
			 (not (null (cddr z)))
			 (not (symbolp (car z)))
			 (and (cadr z) (not (symbolp (cadr z)))))
		     (loop-simple-error
		        "bad variable pair in path USING phrase" z))
		(cond ((not (null (cadr z)))
		         (and (setq tem (si:loop-tassoc
					   (car z) loop-named-variables))
			      (loop-simple-error
			         "Duplicated var substitition in USING phrase"
				 (list tem z)))
			 (push (cons (car z) (cadr z)) loop-named-variables)))
		(loop-pop-source)))
	   (t (return (nreverse preps))))))

(defun loop-add-path (name data)
    (setq loop-path-keyword-alist
	  (cons (cons name data)
		; Don't change this to use DELASSQ in PDP10, the lsubr
		; calling sequence makes that lose.
		(delq (si:loop-tassoc name loop-path-keyword-alist)
		      loop-path-keyword-alist)))
    ())

(defmacro define-loop-path (names &rest cruft)
  "(DEFINE-LOOP-PATH NAMES PATH-FUNCTION LIST-OF-ALLOWABLE-PREPOSITIONS
DATUM-1 DATUM-2 ...)
Defines PATH-FUNCTION to be the handler for the path(s) NAMES, which may
be either a symbol or a list of symbols.  LIST-OF-ALLOWABLE-PREPOSITIONS
contains a list of prepositions allowed in NAMES. DATUM-i are optional;
they are passed on to PATH-FUNCTION as a list."
  (setq names (if (atom names) (list names) names))
    (let ((forms (mapcar #'(lambda (name) `(loop-add-path ',name ',cruft))
			 names)))
       `(eval-when (eval load compile)
	    ,@forms)))


(defun si:loop-sequencer (indexv indexv-type
			  variable? vtype?
			  sequencev? sequence-type?
			  stephack? default-top?
			  crap prep-phrases)
   (let ((endform) (sequencep) (test)
	 (step ; Gross me out!
	       (add1 (or (loop-typed-init indexv-type) 0)))
	 (dir) (inclusive-iteration?) (start-given?) (limit-given?))
     (and variable? (loop-make-iteration-variable variable? () vtype?))
     (do ((l prep-phrases (cdr l)) (prep) (form) (odir)) ((null l))
       (setq prep (caar l) form (cadar l))
       (cond ((si:loop-tmember prep '(of in))
		(and sequencep (loop-simple-error
				  "Sequence duplicated in LOOP path"
				  (list variable? (car l))))
		(setq sequencep 't)
		(loop-make-variable sequencev? form sequence-type?))
	     ((si:loop-tmember prep '(from downfrom upfrom))
	        (and start-given?
		     (loop-simple-error
		        "Iteration start redundantly specified in LOOP sequencing"
			(append crap l)))
		(setq start-given? 't)
		(cond ((si:loop-tequal prep 'downfrom) (setq dir 'down))
		      ((si:loop-tequal prep 'upfrom) (setq dir 'up)))
		(loop-make-iteration-variable indexv form indexv-type))
	     ((cond ((si:loop-tequal prep 'upto)
		       (setq inclusive-iteration? (setq dir 'up)))
		    ((si:loop-tequal prep 'to)
		       (setq inclusive-iteration? 't))
		    ((si:loop-tequal prep 'downto)
		       (setq inclusive-iteration? (setq dir 'down)))
		    ((si:loop-tequal prep 'above) (setq dir 'down))
		    ((si:loop-tequal prep 'below) (setq dir 'up)))
		(and limit-given?
		     (loop-simple-error
		       "Endtest redundantly specified in LOOP sequencing path"
		       (append crap l)))
		(setq limit-given? 't)
		(setq endform (loop-maybe-bind-form form indexv-type)))
	     ((si:loop-tequal prep 'by)
		(setq step (if (loop-constantp form) form
			       (loop-make-variable
				 (loop-gentemp 'loop-step-by-)
				 form 'fixnum))))
	     (t ; This is a fatal internal error...
	        (loop-simple-error "Illegal prep in sequence path"
				   (append crap l))))
       (and odir dir (not (eq dir odir))
	    (loop-simple-error
	       "Conflicting stepping directions in LOOP sequencing path"
	       (append crap l)))
       (setq odir dir))
     (and sequencev? (not sequencep)
	  (loop-simple-error "Missing OF phrase in sequence path" crap))
     ; Now fill in the defaults.
     (setq step (list indexv step))
     (cond ((memq dir '(() up))
	      (or start-given?
		  (loop-make-iteration-variable indexv 0 indexv-type))
	      (and (or limit-given?
		       (cond (default-top?
			        (loop-make-variable
				  (setq endform (loop-gentemp
						  'loop-seq-limit-))
				  () indexv-type)
				(push `(setq ,endform ,default-top?)
				      loop-prologue))))
		   (setq test (if inclusive-iteration? '(greaterp . args)
				  '(not (lessp . args)))))
	      (push 'plus step))
	   (t (cond ((not start-given?)
		       (or default-top?
			   (loop-simple-error
			      "Don't know where to start stepping"
			      (append crap prep-phrases)))
		       (loop-make-iteration-variable indexv 0 indexv-type)
		       (push `(setq ,indexv
				    (,(loop-typed-arith 'sub1 indexv-type)
				     ,default-top?))
			     loop-prologue)))
	      (cond ((and default-top? (not endform))
		       (setq endform (loop-typed-init indexv-type)
			     inclusive-iteration? 't)))
	      (and (not (null endform))
		   (setq test (if inclusive-iteration? '(lessp . args)
				  '(not (greaterp . args)))))
	      (push 'difference step)))
     (and (and (numberp (caddr step)) (= (caddr step) 1))	;Generic arith
	  (rplacd (cdr (rplaca step (if (eq (car step) 'plus) 'add1 'sub1)))
		  ()))
     (rplaca step (loop-typed-arith (car step) indexv-type))
     (setq step (list indexv step))
     (setq test (loop-typed-arith test indexv-type))
     (setq test (subst (list indexv endform) 'args test))
     (and stephack? (setq stephack? `(,variable? ,stephack?)))
     `(() ,step ,test ,stephack?
       () () ,test ,stephack?)))


; Although this function is no longer documented, the "SI:" is needed
; because compiled files may reference it that way (via
; DEFINE-LOOP-SEQUENCE-PATH).
(defun si:loop-sequence-elements-path (path variable data-type
				       prep-phrases inclusive?
				       allowed-preps data)
    allowed-preps ; unused
    (let ((indexv (si:loop-named-variable 'index))
	  (sequencev (si:loop-named-variable 'sequence))
	  (fetchfun ()) (sizefun ()) (type ()) (default-var-type ())
	  (crap `(for ,variable being the ,path)))
       (cond ((not (null inclusive?))
	        (rplacd (cddr crap) `(,(cadar prep-phrases) and its ,path))
		(loop-simple-error "Can't step sequence inclusively" crap)))
       (setq fetchfun (car data)
	     sizefun (car (setq data (cdr data)))
	     type (car (setq data (cdr data)))
	     default-var-type (cadr data))
       (list* () () ; dummy bindings and prologue
	      (si:loop-sequencer
	         indexv 'fixnum
		 variable (or data-type default-var-type)
		 sequencev type
		 `(,fetchfun ,sequencev ,indexv) `(,sizefun ,sequencev)
		 crap prep-phrases))))

(defmacro define-loop-sequence-path (path-name-or-names fetchfun sizefun
				     &optional sequence-type element-type)
  "Defines a sequence iiteration path.  PATH-NAME-OR-NAMES is either an
atomic path name or a list of path names.  FETCHFUN is a function of
two arguments, the sequence and the index of the item to be fetched.
/(Indexing is assumed to be zero-origined.  SIZEFUN is a function of
one argument, the sequence; it should return the number of elements in
the sequence.  SEQUENCE-TYPE is the name of the data-type of the
sequence, and ELEMENT-TYPE is the name of the data-type of the elements
of the sequence."
    `(define-loop-path ,path-name-or-names
	si:loop-sequence-elements-path
	(of in from downfrom to downto below above by)
	,fetchfun ,sizefun ,sequence-type ,element-type))


;;;; MIT/LMI interned-symbols path

(progn 'compile

 (defun loop-interned-symbols-path (path variable data-type prep-phrases
				    inclusive? allowed-preps data
				    &aux statev1 statev2 statev3 statev4
					 (localp (car data)))
    path data-type allowed-preps			; unused vars
    (and inclusive? (loop-simple-error
		       "INTERNED-SYMBOLS path doesn't work inclusively"
		       variable))
    (and (not (null prep-phrases))
	 (or (cdr prep-phrases)
	     (not (si:loop-tmember (caar prep-phrases) '(in of))))
	   (ferror () "Illegal prep phrase(s) in ~A path of ~A - ~A"
		   path variable prep-phrases))
    (loop-make-variable variable () data-type)
    (loop-make-variable
       (setq statev1 (loop-gentemp))
       (if prep-phrases `(pkg-find-package ,(cadar prep-phrases)) 'package)
       ())
    (loop-make-variable (setq statev2 (loop-gentemp)) () ())
    (loop-make-variable (setq statev3 (loop-gentemp)) () ())
    (loop-make-variable (setq statev4 (loop-gentemp)) () ())
    (push `(multiple-value (,statev1 ,statev2 ,statev3 ,statev4)
		  (loop-initialize-mapatoms-state ,statev1 ,localp))
	  loop-prologue)
    `(() () (multiple-value (nil ,statev1 ,statev2 ,statev3 ,statev4)
	       (loop-test-and-step-mapatoms
		,statev1 ,statev2 ,statev3 ,statev4))
      (,variable ,statev2)
      () ()))

 (defun loop-initialize-mapatoms-state (pkg localp)
    ; Return the initial values of the four state variables.
    ; This scheme uses them to be:
    ; (1)  Index into the package (decremented as we go)
    ; (2)  Temporary (to hold the symbol)
    ; (3)  the package
    ; (4)  a list of other packages to consider.
    (prog ()
       (return (dont-optimize (pkg-number-of-slots pkg))
	       () pkg
	       (and localp (package-use-list pkg)))))

 (defun loop-test-and-step-mapatoms (index temp pkg other-packages)
    temp ; ignored
    (prog ()
     lp (cond ((< (setq index (1- index)) 0)
	       (cond ((setq pkg (car other-packages))
		      (pop other-packages)
		      (setq index (dont-optimize (pkg-number-of-slots pkg)))
		      (go lp))
		     (t (return t))))
	      ((dont-optimize
		 (pkg-code-valid-p
		   (dont-optimize (pkg-slot-code pkg index))))
	       (return nil index
		       (dont-optimize (pkg-slot-symbol pkg index))
		       pkg other-packages))
	      (t (go lp)))))

 )


;;;; Symbolics interned-symbols path


;;;; LOOP iteration path for hash tables (NIL & Lispm)

(progn 'compile

(define-loop-path hash-elements loop-hash-elements-path (of with-key))

;MIT version of above.
(defun loop-hash-elements-path (ignore variable ignore prep-phrases
				inclusive? ignore ignore)
  (if inclusive?
      (ferror nil "Inclusive stepping not supported in HASH-ELEMENTS path for ~S."
	      variable))
  (unless (loop-tassoc 'of prep-phrases)
    (ferror nil "No OF phrase in HASH-ELEMENTS path for ~S." variable))
  (let (bindings prologue steps post-endtest pseudo-steps
	(blen-var (loop-gentemp 'loop-hash-block-len-))
	(ht-var (loop-gentemp 'loop-hash-table-))
	(i-var (loop-gentemp))
	(len-var (loop-gentemp 'loop-hash-len-))
	(tem (loop-gentemp))
	(key-var (or (cadr (loop-tassoc 'with-key prep-phrases))
		     (loop-gentemp 'loop-hash-key-)))
	(offset-var (loop-gentemp 'loop-hash-offset-)))
    (setq bindings `((,ht-var (send ,(cadr (loop-tassoc 'of prep-phrases)) ':hash-array))
		     (,blen-var nil) (,offset-var nil) (,variable nil)
		     (,i-var nil) (,key-var nil) (,len-var nil))
	  prologue `((setq ,blen-var
			   (hash-table-block-length ,ht-var))
		     (setq ,i-var (- ,blen-var))
		     (setq ,offset-var (if (hash-table-hash-function ,ht-var) 1 0))
		     (setq ,len-var (array-length ,ht-var)))
	  steps `(,i-var
		  (do ((,tem (+ ,blen-var ,i-var) (+ ,blen-var ,tem)))
		      ((or ( ,tem ,len-var)
			   ( (%p-data-type (aloc ,ht-var ,tem)) dtp-null))
		       ,tem)))
	  post-endtest `( ,i-var ,len-var)
	  pseudo-steps `(,key-var (aref ,ht-var (+ ,i-var ,offset-var))
			 ,variable (aref ,ht-var (+ ,i-var ,offset-var 1))))
    (list bindings prologue nil steps post-endtest pseudo-steps)))

) ;progn 'compile


;;;; Setup stuff


; We don't want these defined in the compilation environment because
; the appropriate environment hasn't been set up.  So, we just bootstrap
; them up.
(mapc '(lambda (x)
	  (mapc '(lambda (y)
		    (setq loop-path-keyword-alist
			  (cons (cons y (cdr x))
				(delq (si:loop-tassoc
				         y loop-path-keyword-alist)
				      loop-path-keyword-alist))))
		(car x)))
      '(
	((interned-symbols interned-symbol)
	   loop-interned-symbols-path (in))
	((local-interned-symbols local-interned-symbol)
	   loop-interned-symbols-path (in) t)
	))

(mapc #'(lambda (x)
	  (mapc #'(lambda (y)
		    (setq loop-path-keyword-alist
			  (cons `(,y si:loop-sequence-elements-path
				  (of in from downfrom to downto
				      below above by)
				  . ,(cdr x))
				(delq (si:loop-tassoc
					y loop-path-keyword-alist)
				      loop-path-keyword-alist))))
		(car x)))
      '(((array-element array-elements) ar-1-force array-active-length)
	((element elements) elt length sequence)
	((character characters string-element string-elements)
	    char length string string-char))
      )

  (or (status feature loop) (sstatus feature loop))
