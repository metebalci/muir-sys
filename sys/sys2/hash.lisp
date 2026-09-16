; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:8; Readtable:T -*-

;;; A hash table that the user sees is a flavor instance.
;;; The guts of it is a named-structure array defined below.

;;; The contents of the array is divided into n-word blocks.
;;; Each block corresponds to one hash key.  The first word of the block is the key.
;;; The remaining words are associated data.  Normally there is only one of them.
;;; Each key and its associated data words form a cdr-next list.
;;; The third value of GETHASH points to this list.
;;; Extra args to PUTHASH can be used to set data words past the first.

;;; A DTP-NULL is used in the table in the key position to mark an empty slot.
;;; DTP-NULL with nonzero pointer means a slot that was "deleted" and
;;; which search must continue past.

;;; A flavor's method hash table is actually the array, not the flavor instance.
;;; The array points to the flavor instance it belongs to, so that the
;;; flavor code can find the instance to send messages to it.
;;; This also enables flavors to be bootstrapped.

;;; This file defines only the low-level hash arrays.
;;; The file HASHFL, loaded after flavors are loaded,
;;; defines the hash table flavors and the user-level functions that work on them.

;;;; This page deals with defining and creating the hash arrays.

(defsubst hash-table-funcallable-p (hash-table)
  (and (array-has-leader-p hash-table)
       (not (zerop (%p-ldb-offset %%array-leader-funcall-as-hash-table hash-table -1)))))

;;; NOTE: the microcode knows the index of HASH-TABLE-MODULUS
;;;  as well as the organization of the entries and how to hash them,
;;;  in the special case that the modulus is a power of 2.
;;;  See label CALL-INSTANCE-ARRAY in the microcode.
(defstruct (hash-array :named :array-leader
		       (:constructor make-hash-array-internal) (:alterant nil))
  (hash-table-rehash-function 'hash-table-rehash :documentation
    "A function when rehash is required.  First argument is the hash-table,
second is NIL to just rehash or the rehash-size to grow it first.
The function must return the hash-table (which may have been moved by ADJUST-ARRAY-SIZE)")
  (hash-table-rehash-size 1.3s0 :documentation
    "How much to grow by when the time comes.  A flonum is the ratio to increase by,
a fixnum is the number of entries to add.
These will get rounded up to the next appropriate size.")
  (hash-table-gc-generation-number %gc-generation-number :documentation
    "Used to decide when rehash required because the GC may have moved
some objects, changing their %POINTER and hence their hash code.")
;>> need to record highest votility level of hash keys
  (hash-table-modulus nil :documentation
    "The number of blocks. Used for remainder to get hash code.")
  (hash-table-fullness 0 :documentation
    "The number of valid entries currently in the array.")
  (hash-table-block-length 2 :documentation
    nil)
  (hash-table-rehash-threshold 0.7s0 :documentation
    "Rehash if we get more than this fraction full.")
  (hash-table-number-of-deleted-entries 0 :documentation
    "Number of /"deleted/" entries (entries no longer valid but which you must keep
searching past). Used together with the FULLNESS to make sure there is always one
slot that has never been used.")
  (hash-table-lock nil :documentation
    nil)
  (hash-table-hash-function nil :documentation
    "This function computes a numeric key from an object. NIL means use the object.")
  (hash-table-compare-function 'eq :documentation
    "This function compares an object key with a key in the table.")
  (hash-table-instance nil :documentation
    "This is the instance whose HASH-ARRAY this hash table is."))


(defun make-hash-array (&key (size #o100) area
			((:rehash-function rhf) 'hash-table-rehash)
			((:rehash-size rhs) 1.3s0) growth-factor
			(number-of-values 1)
			actual-size
			(rehash-threshold 0.7s0)
			funcallable-p
			hash-function
			(compare-function 'eq)
			test
			instance
			&aux ht blen)
  (cond (funcallable-p
	 ;; Funcallable hash tables are looked at by the microcode
	 ;; and require that the modulus be a power of 2.
	 (setq rhf 'hash-table-double-size-rehash)
	 (setq size (or actual-size (lsh 1 (haulong size))))
	 (setq hash-function nil)
	 (setq compare-function 'eq)
	 (setq number-of-values 2))
	(t
	 (setq size (or actual-size
			(hash-table-good-size size)))))
  (when test
    (setq compare-function test)
    (setq hash-function
	  (select test
	    (('eq #'eq) nil)
	    (('equal #'equal) 'equal-hash)
	    (('eql #'eql) 'eql-hash)
	    (t (ferror nil "Argument TEST is not EQ, EQL or EQUAL.")))))
  (if (integerp rehash-threshold)
      (setq rehash-threshold
	    (cl:// (float rehash-threshold) actual-size)))
  (setq blen (+ 1 number-of-values (if hash-function 1 0)))
  (setq ht (make-hash-array-internal
	     :make-array (:length (* size blen) :area area :type art-q-list)
	     :hash-table-modulus size
	     :hash-table-block-length blen
	     :hash-table-rehash-threshold rehash-threshold
	     :hash-table-rehash-function rhf
	     :hash-table-rehash-size (or growth-factor rhs)
	     :hash-table-hash-function hash-function
	     :hash-table-compare-function compare-function
	     :hash-table-instance instance))
  (%p-dpb-offset (if funcallable-p 1 0) %%array-leader-funcall-as-hash-table
		 ht -1)
  (clear-hash-array ht)
  ht)

;;; Convert SIZE (a number of array elements) to a more-or-less prime.
(defun hash-table-good-size (size)
  (unless (oddp size) (incf size))			;Find next higher more-or-less prime
  (do () ((and (not (zerop (\ size 3)))
	       (not (zerop (\ size 5)))
	       (not (zerop (\ size 7)))))
    (incf size 2))
  size)

(defsubst hash-table-maximal-fullness (hash-table)
  (values (floor (* (if (floatp (hash-table-rehash-threshold hash-table))
			(hash-table-rehash-threshold hash-table)
		      ;; never a fixnum, as make-hash-array coerces fixnums to floats,
		      ;;  so non-float presumably means the value is NIL
		      0.7s0)
		    (- (hash-table-modulus hash-table) 2)))))

;;; This is a separate function from the :CLEAR-HASH operation
;;; for the sake of bootstrapping flavors.
(defun clear-hash-array (hash-array)
  "Clear out a hash array; leave it with no entries."
  (with-lock ((hash-table-lock hash-array))
    ;; Set all of hash table to NIL with cdr-next.
    (setf (cli:aref hash-array 0) nil)
    (%p-store-cdr-code (locf (cli:aref hash-array 0)) cdr-next)
    (%blt-typed (locf (cli:aref hash-array 0))
		(locf (cli:aref hash-array 1))
		(1- (array-length hash-array))
		1)
    ;; Set first word of each group to DTP-NULL, 0.
    (let ((elt-0 (locf (cli:aref hash-array 0)))
	  (blen (hash-table-block-length hash-array)))
      (%p-store-pointer elt-0 0)
      (%p-store-data-type elt-0 dtp-null)
      (%blt-typed elt-0
		  (%make-pointer-offset dtp-locative elt-0 blen)
		  (1- (truncate (array-length hash-array) blen))
		  blen)
      ;; Set last word of each group to CDR-NIL.
      (%p-store-cdr-code (locf (cli:aref hash-array (+ blen -1))) cdr-nil)
      (%blt-typed (locf (cli:aref hash-array (+ blen -1)))
		  (locf (cli:aref hash-array (+ blen blen -1)))
		  (1- (truncate (array-length hash-array) blen))
		  blen))
    (setf (hash-table-fullness hash-array) 0)
    (setf (hash-table-number-of-deleted-entries hash-array) 0)
    (setf (hash-table-gc-generation-number hash-array) %gc-generation-number)
    hash-array))

(defselect ((:property hash-array named-structure-invoke))
  (:fasload-fixup (self)
    ;; Force rehash as if due to gc, because hash codes are all wrong now.
    ;; Also fix up cdr codes.
    (setf (hash-table-gc-generation-number self) -1)
    (do ((i 0 (+ i blen))
	 (blen (hash-table-block-length self))
	 (length (array-length self)))
	(( i length))
      (%p-store-cdr-code (locf (cli:aref self (+ i blen -1))) cdr-nil)))
  (:describe (self)
    (describe-defstruct self)
    (format t "~&   Maximum fullness before rehash: ~S" (hash-table-maximal-fullness self)))
  (:print-self (self stream &optional ignore ignore)
    (printing-random-object (self stream :type)
      (print-hash-array self stream nil))))

(defun print-hash-array (hash-array stream for-print-hashtable-p)
  (format stream "~S~:[+~S~;~*~]//~S~@[ :test ~S~]~@[~A~]"
	  (hash-table-fullness hash-array)
	  (zerop (hash-table-number-of-deleted-entries hash-array))
	  (hash-table-number-of-deleted-entries hash-array)
	  (hash-table-maximal-fullness hash-array)
	  (let ((compare-function (hash-table-compare-function hash-array)))
	    (if (or for-print-hashtable-p
		    (and (neq compare-function 'eq) (neq compare-function #'eq)))
		(function-name compare-function)))
	  (and (not for-print-hashtable-p)
	       (hash-table-funcallable-p hash-array)
	       " (Funcallable)")))

;;;; Rehashing of hash arrays.

;;; Add a new entry to a hash table being constructed for rehashing an old one.
;;; CONTENTS is a pointer to the first word of the entry in the old hash table,
;;; so its CAR is the hash code.
;;; There is no need to lock the hash table since nobody else knows about it yet.
(defun rehash-put (hash-table contents &optional for-gc
		   &aux (hash-code
			  ;; Use the same hash code as before, to avoid swapping,
			  ;; unless this is rehashing due to GC.
			  (if (and for-gc (hash-table-hash-function hash-table))
			      (funcall (hash-table-hash-function hash-table)
				       (%p-contents-offset contents 1))
			    (car contents))))
  (do ((p (hash-block-pointer hash-table hash-code)
	  (%make-pointer-offset dtp-locative p blen))
       (blen (hash-table-block-length hash-table)))
      (())
    ;; Make P wrap around at end of table.
    ;; > is used because the pointer-difference, when time to wrap,
    ;; is actually 1 or 2 more than the array length (because it includes the header);
    ;; if BLEN is 2, we could wrap too soon if >= were used.
    (if (> (%pointer-difference p hash-table)
	   (array-length hash-table))
	(setq p (%make-pointer-offset dtp-locative p (- (array-length hash-table)))))
    ;; Install this key in the first empty slot.
    ;; We know the key cannot already be present, and there are no deleted slots,
    ;; and we don't need to rehash because that's what we are doing.
    (when (= (%p-data-type p) dtp-null)
      (%blt-typed contents p blen 1)
      (setf (car p) hash-code)
      (return))))

;;; Standard rehash function.  Returns new hash array (possibly the same one).
;;; GROW is either the hash table's rehash-size or NIL meaning use same size array.
;;; ACTUAL-SIZE is so that this can be used as a subroutine of another
;;; rehash function which differs only in how to compute the new size.
(defun hash-table-rehash (hash-table grow &optional actual-size)
  (setq hash-table (follow-structure-forwarding hash-table))
  (let* ((new-size (if (null grow)
		       (hash-table-modulus hash-table)
		     (hash-table-good-size
		       (if (floatp grow)
			   (fix (* (hash-table-modulus hash-table) grow))
			   (+ (hash-table-modulus hash-table) grow)))))
	 (new-hash-table (make-hash-array
			   :size new-size
			   :area (if grow
				     (sys:%area-number hash-table)
				     background-cons-area)
			   :rehash-function (hash-table-rehash-function hash-table)
			   :rehash-size (hash-table-rehash-size hash-table)
			   :hash-function (hash-table-hash-function hash-table)
			   :compare-function (hash-table-compare-function hash-table)
			   :funcallable-p (hash-table-funcallable-p hash-table)
			   :actual-size (if grow actual-size
					  (hash-table-modulus hash-table))
			   :number-of-values (- (hash-table-block-length hash-table)
						1
						(if (hash-table-hash-function hash-table)
						    1 0))
			   :rehash-threshold (hash-table-rehash-threshold hash-table))))
;   (declare (special new-hash-table))		;why was this special?
    ;; Scan the old hash table and find all nonempty entries.
    (do ((p (%make-pointer-offset dtp-locative hash-table
				  (1+ (%p-ldb %%array-long-length-flag hash-table)))
	    (%make-pointer-offset dtp-locative p blen))
	 (blen (hash-table-block-length hash-table))
	 (i 0 (+ i blen))
	 (n (array-length hash-table)))
	(( i n))
      (when ( (%p-data-type p) dtp-null)
	;; And store each one in the new hash table.
	(rehash-put new-hash-table p (null grow))))
    (setf (hash-table-fullness new-hash-table)
	  (hash-table-fullness hash-table))
    (setf (hash-table-instance new-hash-table)
	  (hash-table-instance hash-table))
    (cond ((null grow)
	   (setq hash-table (follow-structure-forwarding hash-table))
	   (setf (hash-table-lock new-hash-table)
		 (hash-table-lock hash-table))
	   (%blt-typed (%find-structure-leader new-hash-table)
		       (%find-structure-leader hash-table)
		       (%structure-total-size hash-table)
		       1)
	   (return-array new-hash-table)
	   hash-table)
	  (t
	   new-hash-table))))

;;; Rehash a hash table to be exactly double the size.
;;; Use this as a rehash function for a hash table.
;;; It ignores the :REHASH-SIZE parameter.
(defun hash-table-double-size-rehash (hash-table grow)
  (hash-table-rehash hash-table grow (* 2 (hash-table-modulus hash-table))))

;;; The flavor system needs to be able to do PUTHASH before hash table flavors can be used.

;;; Subroutine of hashing.
;;; Given a hash-table and a key, return a locative to the start
;;; of the block in the array which may contain an association from that key.
;;; Cannot use ALOC because it gets an error if there is a DTP-NULL in the array.
(defun hash-block-pointer (hash-table key)
  (%make-pointer-offset dtp-locative hash-table
			(+ (* (\ (ldb (byte #o23 0)
				      (rot (%pointer key)
					   (if (hash-table-funcallable-p hash-table) 0 3)))
				 (hash-table-modulus hash-table))
			      (hash-table-block-length hash-table))
			   (%p-ldb %%array-long-length-flag hash-table)
			   1)))

(defsubst %p-contents-eq (p x)
  (and (neq (%p-data-type p) dtp-null)
       (eq (car p) x)))

(defun puthash-bootstrap (key value hash-table &rest additional-values
			  &aux
			  (values-left (cons value additional-values))
			  (hash-function (hash-table-hash-function hash-table))
			  (compare-function (hash-table-compare-function hash-table))
			  (hash-code (if hash-function (funcall hash-function key) key)))
  (declare (return-list value old-value key-found-flag entry-pointer))
  (with-lock ((hash-table-lock hash-table))
    (setq hash-table (follow-structure-forwarding hash-table))
    (do ((p (hash-block-pointer hash-table hash-code)
	    (%make-pointer-offset dtp-locative p blen))
	 (blen (hash-table-block-length hash-table))
	 (old-value)
	 (emptyp nil))
	(())
      ;; Make P wrap around at end of table.
      ;; > is used because the pointer-difference, when time to wrap,
      ;; is actually 1 or 2 more than the array length (because it includes the header);
      ;; if BLEN is 2, we could wrap too soon if  were used.
      (if (> (%pointer-difference p hash-table)
	     (array-length hash-table))
	  (setq p (%make-pointer-offset dtp-locative p (- (array-length hash-table)))))
      (cond ((and (%p-contents-eq p hash-code)		;Found existing entry
		  (or (null hash-function)
		      (funcall compare-function (%p-contents-offset p 1) key)))
	     (let ((value-index (if hash-function 2 1)))
	       (setq old-value (%p-contents-offset p value-index))
	       (do ((i value-index (1+ i))) ((= i blen))
		 (%p-store-contents-offset (pop values-left) p i))
	       (return value old-value t (%make-pointer-offset dtp-list p (1- value-index)))))
	    ((= (%p-data-type p) dtp-null)
	     (or emptyp (setq emptyp p))
	     (when (zerop (%p-pointer p))
	       ;; Hash tables are not supposed to need rehash before HASHFL is loaded.
	       ;; It wouldn't work, since the hash table instance is not there
	       ;; for FLAVOR to use to find the new hash array.
	       (cond (( (hash-table-gc-generation-number hash-table) %gc-generation-number)
		      (ferror nil "~S claims to need rehash due to gc." hash-table))
		     (( (+ (hash-table-fullness hash-table)
			    (hash-table-number-of-deleted-entries hash-table))
			 (hash-table-maximal-fullness hash-table))
		      (ferror nil "~S is too full." hash-table))
		     (t				;Add to table using empty slot found
		      (%p-store-contents emptyp hash-code)
;>> have to check for volatility level of key here and inform hash-array that may
;>> need to rehash on a gc of that volatility
		      (without-interrupts
			(cond (hash-function
			       (%p-store-contents-offset key emptyp 1)
			       (do ((i 2 (1+ i))) ((= i blen))
				 (%p-store-contents-offset (pop values-left) emptyp i)))
			      (t
			       (do ((i 1 (1+ i))) ((= i blen))
				 (%p-store-contents-offset (pop values-left) emptyp i)))))
		      (incf (hash-table-fullness hash-table))
		      ;; If reusing a deleted slot, decrement number of them slots.
		      (or (eq emptyp p)
			  (decf (hash-table-number-of-deleted-entries hash-table)))
		      (return value)))))))))

(unless (fboundp 'puthash-array)
  (fset 'puthash-array 'puthash-bootstrap))

(unless (fboundp 'make-flavor-hash-array)
  (fset 'make-flavor-hash-array 'make-flavor-hash-array-bootstrap))

(defun make-flavor-hash-array-bootstrap (area size)
  (make-hash-array :area area
		   :size size
		   :funcallable-p t
		   :rehash-threshold 0.8s0
		   :number-of-values 2))

;;; Like MAPHASH but wants a hash-array rather than a hash table instance.
;;; So it can be used before HASHFL has been fully loaded and installed
;;; (such as, for composing the hash table flavors).
(defun maphash-array (function hash-table &rest extra-args)
  (with-lock ((hash-table-lock hash-table))
    (do ((blen (hash-table-block-length hash-table))
	 (block-offset (if (hash-table-hash-function hash-table) 1 0))
	 (i 0 (+ i blen))
	 (n (array-length hash-table)))
	(( i n))
      (when ( (%p-data-type (locf (cli:aref hash-table i))) dtp-null)
	(%open-call-block function 0 0)
	(dolist (i (%make-pointer-offset dtp-list (locf (aref hash-table i)) block-offset))
	  (%push i))
	(dolist (i extra-args)
	  (%push i))
	(%activate-open-call-block)))
    hash-table))
