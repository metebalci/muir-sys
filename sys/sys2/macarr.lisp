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
