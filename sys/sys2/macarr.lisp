;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:10; Readtable:ZL -*-

;;;; maclisp braindamage --- very obsolete array-hackery

;; fillarray, listarray should also be here -- except that the system uses them. FMH!

(DEFMACRO ARRAY (X TYPE &REST DIMLIST)
  "Obsolete Maclisp function for creating an array.  Don't use it."
  `(*ARRAY ',X ',TYPE ,@DIMLIST))

(DEFUN *ARRAY (X TYPE &REST DIMLIST &AUX ARRAY)
  "Obsolete Maclisp function for growing an array.  Don't use it."
  (IF (MEMQ TYPE '(READTABLE OBARRAY))
      (FERROR NIL "The array type ~S is not defined in Zetalisp" TYPE))
  (SETQ ARRAY
	(MAKE-ARRAY DIMLIST :TYPE (IF (EQ TYPE 'FLONUM) 'ART-FLOAT 'ART-Q)))
  (IF (EQ TYPE 'FIXNUM)
      (FILL-ARRAY ARRAY NIL 0))
  (COND ((NULL X)
	 ARRAY)
	((SYMBOLP X)
	 (SETF (SYMBOL-FUNCTION X) ARRAY)
	 X)
	(T (FERROR NIL "~S is not a legal first arg for *ARRAY" X))))


(DEFMACRO GET-LOCATIVE-POINTER-INTO-ARRAY (ARRAY-REFERENCE &ENVIRONMENT ENV)
  "Similar to GET-LIST-POINTER-INTO-ARRAY except that it returns a
locative and doesn't require the array to be ART-Q-LIST.
Use LOCF of AREF instead of this in new programs."
  (LET* ((ARRAYCALL (MACROEXPAND ARRAY-REFERENCE ENV)))
    (CASE (CAR ARRAYCALL)
      (FUNCALL `(ALOC ,(CADR ARRAYCALL) . ,(CDDR ARRAYCALL)))
      (ARRAYCALL `(ALOC ,(CADDR ARRAYCALL) . ,(CDDDR ARRAYCALL)))
      ((APPLY FUNCALL* APPLY)
       `(APPLY #'ALOC ,(CADR ARRAYCALL) . ,(CDDR ARRAYCALL)))
      (T `(ALOC (FUNCTION ,(CAR ARRAYCALL)) . ,(CDR ARRAYCALL))))))

(DEFMACRO ARRAYCALL (IGNORE ARRAY &REST DIMS)
  `(FUNCALL ,ARRAY . ,DIMS))

(DEFUN ARRAYDIMS (ARRAY &AUX TYPE)
  "Return a list of the array-type and dimensions of ARRAY.
This is an obsolete Maclisp function."
  (AND (SYMBOLP ARRAY) (SETQ ARRAY (FSYMEVAL ARRAY)))
  (CHECK-TYPE ARRAY ARRAY)
	;SHOULD CHECK FOR INVZ
  (SETQ TYPE (NTH (%P-LDB-OFFSET %%ARRAY-TYPE-FIELD ARRAY 0) ARRAY-TYPES))
  (CONS TYPE (ARRAY-DIMENSIONS ARRAY)))


;;;; Store
; Copyright (c) Jan 1984 by Glenn S. Burke and Massachusetts Institute of Technology.


(DEFMACRO STORE (ARRAY-REFERENCE VALUE)
  (LET* ((ARRAYCALL (MACROEXPAND ARRAY-REFERENCE)))
    (SELECTQ (CAR ARRAYCALL)
      (FUNCALL `(ASET ,VALUE ,(CADR ARRAYCALL) . ,(CDDR ARRAYCALL)))
      (ARRAYCALL `(ASET ,VALUE ,(CADDR ARRAYCALL) . ,(CDDDR ARRAYCALL)))
      ((APPLY FUNCALL* APPLY)
       `(APPLY 'ASET ,VALUE ,(CADR ARRAYCALL) . ,(CDDR ARRAYCALL)))
      (T `(ASET ,VALUE (FUNCTION ,(CAR ARRAYCALL)) . ,(CDR ARRAYCALL))))))

;;;---!!! This version of STORE from NIL is not MACLISP compatible.
#|
(defmacro store (array-form value &environment env)
  (let* ((inversions '((global:aref . aset)
		       (char . aset)
		       (bit . aset)
		       (sbit . aset)
		       (svref . aset)
		       (schar . aset)
		       (funcall . maclisp-store-hack)))
	 (foo (macroexpand array-form env))
	 (invert (and (consp foo)
		      (symbolp (car foo))
		      (cdr (assq (car foo) inversions))))
	 (tem nil))
    (cond ((not (null invert)) `(,invert ,value ,@(cdr foo)))
	  ((and (consp foo) (symbolp (car foo)))
	   (cond ((not (memq (car foo) '(apply lexpr-funcall)))
		  `(maclisp-store-hack ,value ',(car foo) ,@(cdr foo)))
		 ((and (consp (setq tem (macroexpand (cadr foo) env)))
		       (memq (car tem) '(quote function))
		       (setq tem (cdr (assq (cadr tem) inversions))))
		  `(apply #',tem ,value ,@(cddr array-form)))
		 (t `(apply #'maclisp-store-hack ,value ,@(cdr foo)))))
	  (t `(store ,(cerror t nil :wrong-type-argument
			      "~*The array reference form ~S is not ~
			      understood by store."
			      nil array-form)
		     ,value)))))


(defun maclisp-store-hack (value frob &rest subscripts &aux tem)
  (do-forever
    (etypecase frob
      (array (return (apply #'aset value frob subscripts)))
      (symbol (and (fboundp frob)
		   (eq (car-safe (setq tem (symbol-function frob))) 'array)
		   (return (apply #'aset value (cdr tem) subscripts)))))
    (setq frob
	  (cerror t nil :wrong-type-argument
	       "~*The object ~S was used as a function within a STORE special form,~%~
		but is neither an array nor an array function."
	       '(or array symbol) frob))))
|#
