;;; -*- Mode:LISP; Package:SI; Base:8; Readtable:ZL -*-

;;; hash table flavors.

;;; The actual hash table is an array called the hash-array.
;;; The flavor instance serves only to point to that.
;;; Hash arrays are defined in the file HASH.

(defvar *hash-tables-rehash-before-cold* nil
  "List of hash tables to rehash when DISK-SAVE is done.")

(add-initialization 'rehash-hash-tables
		    '(dolist (h *hash-tables-rehash-before-cold*)
		       (gethash h nil))
		    '(:before-cold))

(defflavor hash-table (hash-array) ()
  :gettable-instance-variables
  :inittable-instance-variables
  (:init-keywords :size :area :rehash-function :rehash-size :growth-factor
		  :number-of-values :actual-size :rehash-threshold :rehash-before-cold
		  :funcallable-p :hash-function :compare-function :test)
  (:default-init-plist :hash-function nil :compare-function #'eq))

(defflavor eq-hash-table () (hash-table)
  :alias-flavor)

(defflavor equal-hash-table () (hash-table)
  (:default-init-plist :hash-function #'equal-hash :compare-function #'equal))

(defmethod (hash-table :before :init) (plist)
  (unless (variable-boundp hash-array)
    (setq hash-array
	  (apply #'make-hash-array :instance self (contents plist))))
  (setf (hash-table-instance hash-array) self)
  (if (get plist ':rehash-before-cold)
      (push self *hash-tables-rehash-before-cold*)))

(defmethod (hash-table :fasd-form) ()
  (let ((array (make-array (array-length hash-array)
			   :type art-q
			   :leader-length (array-leader-length hash-array)
			   :displaced-to hash-array)))
    (%blt-typed (%find-structure-leader hash-array)
		(%find-structure-leader array)
		(1+ (array-leader-length array))
		1)
    ;; Get rid of circularity.
    (setf (hash-table-instance array) nil)
    (make-array-into-named-structure array 'hash-array)
    `(make-instance ',(type-of self) :hash-array ',array)))

(defmethod (hash-table :size) ()
  (hash-table-modulus hash-array))

(defmethod (hash-table :filled-entries) ()
  (hash-table-fullness hash-array))

(defmethod (hash-table :print-self) (stream &rest ignore)
  (printing-random-object (self stream :type)
    (print-hash-array hash-array stream t)))

(defmethod (hash-table :describe) ()
  (format t "~&~S is a hash-table with ~D entries out of a possible ~D (~D%).~%"
	  self (hash-table-fullness hash-array) (hash-table-modulus hash-array)
	  (truncate (* (hash-table-fullness hash-array) 100.)
		    (hash-table-modulus hash-array)))
  (if (and (hash-table-lock hash-array) (car (hash-table-lock hash-array)))
      (format t "Locked by ~S~%" (hash-table-lock hash-array)))
; But FUNCALLing the hashtable is the same as SENDing it! [sigh]
; This information pertains just to the hash-array itself
;  (if (hash-table-funcallable-p hash-array)
;      (format t "FUNCALLing it hashes on the first argument to get a function to call.~%"))
  (format t "There are ~D formerly used entries now deleted~%"
	  (hash-table-number-of-deleted-entries hash-array))
  (if (floatp (hash-table-rehash-threshold hash-array))
      (format t "Rehash if table gets more than ~S full~%"
	      (hash-table-rehash-threshold hash-array)))
  (if ( 1 (- (hash-table-block-length hash-array) 1
	      (if (hash-table-hash-function hash-array) 1 0)))
      (format t "Each key has ~D values associated.~%"
	      (- (hash-table-block-length hash-array) 1
		 (if (hash-table-hash-function hash-array) 1 0))))
  (unless (= (hash-table-gc-generation-number hash-array) %gc-generation-number)
    (format t " rehash is required due to GC.~%"))
  (format t " The rehash function is ~S with increase parameter ~D.~%"
	  (hash-table-rehash-function hash-array) (hash-table-rehash-size hash-array))
  (and (not (zerop (hash-table-fullness hash-array)))
       (y-or-n-p "Do you want to see the contents of the hash table? ")
       (if (not (y-or-n-p "Do you want it sorted? "))
	   (send self :map-hash
		 #'(lambda (key &rest values)
		     (format t "~& ~S -> ~S~%" key values)))
	 (let ((l nil))
	   (send self :map-hash #'(lambda (key &rest values)
				    (push (list key (copy-list values)) l)))
	   (setq l (sortcar l #'alphalessp))
	   (format t "~&~:{ ~S -> ~S~%~}" l)))))

(defmethod (hash-table :clear-hash) (&optional ignore &aux (hash-table hash-array))
  "Clear out a hash table; leave it with no entries."
  (with-lock ((hash-table-lock hash-table))
    ;; Set all of hash table to NIL with cdr-next.
    (setf (aref hash-table 0) nil)
    (%p-store-cdr-code (locf (aref hash-table 0)) cdr-next)
    (%blt (locf (aref hash-table 0)) (locf (aref hash-table 1))
	  (1- (array-length hash-table)) 1)
    ;; Set first word of each group to DTP-NULL, 0.
    (let ((elt-0 (locf (aref hash-table 0)))
	  (blen (hash-table-block-length hash-table)))
      (%p-store-pointer elt-0 0)
      (%p-store-data-type elt-0 dtp-null)
      (%blt-typed elt-0 (%make-pointer-offset dtp-locative elt-0 blen)
		  (1- (truncate (array-length hash-table) blen))
		  blen)
      ;; Set last word of each group to CDR-NIL.
      (%p-store-cdr-code (locf (aref hash-table (+ blen -1))) cdr-nil)
      (%blt-typed (locf (aref hash-table (+ blen -1)))
		  (locf (aref hash-table (+ blen blen -1)))
		  (1- (truncate (array-length hash-table) blen))
		  blen))
    (setf (hash-table-fullness hash-table) 0)
    (setf (hash-table-number-of-deleted-entries hash-table) 0)
    (setf (hash-table-gc-generation-number hash-table) %gc-generation-number)
    hash-table))

(defmethod (hash-table :get-hash)
	   (key &optional default-value
	    &aux
	    (hash-table hash-array)
	    (hash-function (hash-table-hash-function hash-table))
	    (compare-function (hash-table-compare-function hash-table))
	    (hash-code (if hash-function (funcall hash-function key) key)))
  (declare (values value key-found-p entry-pointer))
  (with-lock ((hash-table-lock hash-table))
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
      (when (and (%p-contents-eq p hash-code)
		 (or (null hash-function)
		     (funcall compare-function key (%p-contents-offset p 1))))
	(if hash-function (setq p (%make-pointer-offset dtp-list p 1)))
	(return (values (%p-contents-offset p 1)
			t
			(%make-pointer dtp-list p))))
      ;; If we find a slot that has never been used, this key is not present.
      ;; We assume that not all slots are used!
      (when (and (= (%p-data-type p) dtp-null)
		 (zerop (%p-pointer p)))
	(cond (( (hash-table-gc-generation-number hash-table) %gc-generation-number)
	       ;; Some %POINTER's may have changed, try rehashing
	       (setq hash-array
		     (funcall (hash-table-rehash-function hash-table) hash-table nil))
	       (return (send self :get-hash key)))
	      (t (return (values default-value	;Not found
				 nil
				 nil))))))))

;;; note that SETF cannot hope to give get-hash multiple VALUEs
(defmethod (hash-table :case :set :get-hash) (key &rest values)
  (declare (arglist (key value)))
  ;; use (car (last ...)) is to ignore optional default
  ;;  eg from "(push zap (send foo :get-hash bar baz))"
  (lexpr-send self :put-hash key (car (last values))))

(defmethod (hash-table :put-hash)
	   (key &rest values
	    &aux
	    (values-left values)
	    (hash-table hash-array)
	    (hash-function (hash-table-hash-function hash-table))
	    (compare-function (hash-table-compare-function hash-table))
	    (hash-code (if hash-function (funcall hash-function key) key)))
  (declare (values value old-value key-found-p entry-pointer))
  (with-lock ((hash-table-lock hash-table))
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
      (cond ((and (%p-contents-eq p hash-code)	;Found existing entry
		  (or (null hash-function)
		      (funcall compare-function (%p-contents-offset p 1) key)))
	     (let ((value-index (if hash-function 2 1)))
	       (setq old-value (%p-contents-offset p value-index))
	       (do ((i value-index (1+ i))) ((= i blen))
		 (%p-store-contents-offset (pop values-left) p i))
	       (return (values (car values)
			       old-value
			       t
			       (%make-pointer-offset dtp-list p (1- value-index))))))
	    ((= (%p-data-type p) dtp-null)
	     (or emptyp (setq emptyp p))
	     (when (zerop (%p-pointer p))
	       (cond (( (hash-table-gc-generation-number hash-table) %gc-generation-number)
		      ;; Some %POINTER's may have changed, try rehashing
		      (setq hash-array
			    (funcall (hash-table-rehash-function hash-table) hash-table nil))
		      (return (lexpr-send self :put-hash key values)))
		     ;; Also, if we are nearly full, rehash in a larger array.
		     ;; Don't allow the hash table to become full.
		     (( (+ (hash-table-fullness hash-table)
			    (hash-table-number-of-deleted-entries hash-table))
			 (hash-table-maximal-fullness hash-table))
		      (setq hash-array
			    (funcall (hash-table-rehash-function hash-table) hash-table
				     (hash-table-rehash-size hash-table)))
		      (return (lexpr-send self :put-hash key values)))
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
		      (return (car values))))))))))

(defmethod (hash-table :rem-hash)
	   (key &aux
	    (hash-table hash-array)
	    (hash-function (hash-table-hash-function hash-table))
	    (compare-function (hash-table-compare-function hash-table))
	    (hash-code (if hash-function (funcall hash-function key) key)))
  "Delete any entry for KEY in HASH-TABLE.  Return T if there was one."
  (with-lock ((hash-table-lock hash-table))
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
      (when (and (%p-contents-eq p hash-code)		;Found existing entry
		 (or (null hash-function)
		     (funcall compare-function (%p-contents-offset p 1) key)))
	(do ((i 1 (1+ i))) ((= i blen))
	  (%p-store-contents-offset nil p i))	;Wipe out old values
	(%p-store-data-type p dtp-null)
	(%p-store-pointer p 1)			;Remove entry
	(decf (hash-table-fullness hash-table))
	(incf (hash-table-number-of-deleted-entries hash-table))
	(return t))
      (if (and (= (%p-data-type p) dtp-null)
	       (zerop (%p-pointer p)))
	  (return
	    (cond (( (hash-table-gc-generation-number hash-table) %gc-generation-number)
		   ;; Some %POINTER's may have changed, try rehashing
		   (setq hash-array
			 (funcall (hash-table-rehash-function hash-table) hash-table nil))
		   (send self :rem-hash key))
		  (t nil)))))))			;Really not found

(defmethod (hash-table :modify-hash) (key function &rest additional-args)
  (multiple-value-bind (value key-found-p values-list)
      (send self :get-hash key)
    (setq value (apply function key value key-found-p additional-args))
    (if key-found-p
	(setf (cadr values-list) value)
        (send self :put-hash key value))
    value))

(defmethod (hash-table :swap-hash) (key &rest values)
  (declare (values old-value old-value-p location))
  (multiple-value-bind (nil old-value old-value-p location)
      (lexpr-send self :put-hash key values)
    (values old-value old-value-p location)))

;>> returns HASH-TABLE. CL maphash returns NIL. Should this?
(defmethod (hash-table :map-hash) (function &rest extra-args &aux (hash-table hash-array))
; (declare (values hash-table))
  (with-lock ((hash-table-lock hash-table))
    (do ((blen (hash-table-block-length hash-table))
	 (block-offset (if (hash-table-hash-function hash-table) 1 0))
	 (i 0 (+ i blen))
	 (n (array-length hash-table)))
	(( i n))
      (when ( (%p-data-type (locf (aref hash-table i))) dtp-null)
	(%open-call-block function 0 0)
	(dolist (i (%make-pointer-offset dtp-list (locf (aref hash-table i)) block-offset))
	  (%push i))
	(dolist (i extra-args)
	  (%push i))
	(%activate-open-call-block)))
    hash-table))

(defmethod (hash-table :map-hash-return) (function &optional (return-function 'list)
					  &aux values (hash-table hash-array))
  (with-lock ((hash-table-lock hash-table))
    (do ((blen (hash-table-block-length hash-table))
	 (block-offset (if (hash-table-hash-function hash-table) 1 0))
	 (i 0 (+ i blen))
	 (n (array-length hash-table)))
	(( i n))
      (when ( (%p-data-type (locf (aref hash-table i))) dtp-null)
	(let ((value (apply function
			    (%make-pointer-offset dtp-list (locf (aref hash-table i))
						  block-offset))))
	  (case return-function
	    (nconc (setq values (nconc value values)))
	    (t (push value values))))))
    (if (memq return-function '(list nconc))
	values
	(apply return-function values))))


(defflavor without-interrupts-hash-table ()
	   (hash-table)
  (:documentation "Hashing operations on this hash table happen uninterruptably")
  )

(defwrapper (without-interrupts-hash-table :get-hash) (ignore . body)
  `(without-interrupts
     . ,body))
(defwrapper (without-interrupts-hash-table :put-hash) (ignore . body)
  `(without-interrupts
     . ,body))
(defwrapper (without-interrupts-hash-table :clear-hash) (ignore . body)
  `(without-interrupts
     . ,body))

(compile-flavor-methods hash-table equal-hash-table without-interrupts-hash-table)

;;;; Compatibility functions.

(defun make-hash-table (&rest options)
  "Create a hash table.  Keyword args are as follows:
COMPARE-FUNCTION: the function for comparing the key against
 keys stored in the table.  Usually EQ or EQUAL.
HASH-FUNCTION: the function to compute a hash code from a key.
 NIL (the default) is for EQ hash tables,
 and SI:EQUAL-HASH is used for EQUAL hash tables.
TEST: Common Lisp way to specify the compare-function.
 It must be EQ, EQL (the default) or EQUAL.
 A suitable hash function will be used automatically.
AREA: area to cons the table in.
SIZE: lower bound for number of entries (this may be rounded up).
 Note that the table cannot actually hold that many keys; this value merely serves
 as an approximation of the expected number of keys.
ACTUAL-SIZE: precise number of entries worth of size to use.
NUMBER-OF-VALUES: number of values to associate with each key (default 1).
 Each PUTHASH can set all the values, and GETHASH retrieves them all.
 Note that SETF of GETHASH can only set one value.
REHASH-FUNCTION: a function which accepts a hash table
 and returns a larger one.
REHASH-THRESHOLD: determines what /"fullness/" will make a growth of the hashtable
 and corresponding rehash necessary.
 Either a flonum between 0 and 1 (default 0.7), meaning that rehash occurs
 if more than that fraction full, or a fixnum, meaning rehash if more than that
 number of slots are filled. If a fixnum, it is automatically proportionally
 increased when the hashtable grows.
REHASH-SIZE: the ratio by which the default REHASH-FUNCTION
 will increase the size of the table.  By default, 1.3.
 This may also be a fixnum, in which case it determines the number of extra slots
 which are added to the hastable's size when it grows."
  (declare (arglist &key (test #'eql) compare-function hash-function
		         area size actual-size number-of-values
			 rehash-threshold rehash-function rehash-size))
  (apply #'make-instance 'hash-table options))

(defsubst hash-table-count (hash-table)
  "Returns the number of associations currently stored in HASH-TABLE."
  (send hash-table :filled-entries))

(defsubst clrhash (hash-table &optional ignore)
  "Clear out a hash table; leave it with no entries. Returns HASH-TABLE"
  (send hash-table :clear-hash))

(defsubst gethash (key hash-table &optional default-value)
  "Read the values associated with KEY in HASH-TABLE.
Returns:
 1) The primary value associated with KEY (DEFAULT-VALUE if KEY is not found),
 2) a flag which is T if KEY was found,
 3) a pointer to the list (inside the hash table)
    which holds the key and the associated values
    (NIL if KEY is not found)."
  (declare (values value key-found-flag entry-pointer))
  (send hash-table :get-hash key default-value))

;;; Used by SETF of GETHASH.
;;;  Can't hope to win with multiple values
(defsubst sethash (key hash-table value)
  (send hash-table :put-hash key value))

(defsubst puthash (key value hash-table &rest additional-values)
  "Set the values associated with KEY in HASH-TABLE.
The first value is set from VALUE.  If the hash table associates more
than one value with each key, the remaining values are set from ADDITIONAL-VALUES.
Returns: 1) VALUE, 2) the previous value (or NIL),
 3) T if KEY already had an entry in the table,
 4) a pointer to the list (inside the hash table)
    which holds the key and the associated values."
  (declare (values value old-value key-found-flag entry-pointer))
  (lexpr-send hash-table :put-hash key value additional-values))

(defun swaphash (key value hash-table &rest additional-values)
  "Set the values associated with KEY in HASH-TABLE, returning the previous values.
The first value is set to VALUE.  If the hash table holds more than one
value per entry, the additional values are set from ADDITIONAL-VALUES.
The values returned by SWAPHASH are the same as those of GETHASH."
  (declare (values old-value old-value-p location))
  (multiple-value-bind (nil old-value old-value-p location)
      (lexpr-send hash-table :put-hash key value additional-values)
    (values old-value old-value-p location)))

(defsubst remhash (key hash-table)
  "Delete any entry for KEY in HASH-TABLE.  Return T if there was one."
  (send hash-table :rem-hash key))

(defsubst maphash (function hash-table &rest extra-args)
  "Apply FUNCTION to each item in HASH-TABLE; ignore values.
FUNCTION's arguments are the key followed by the values associated with it,
 followed by the EXTRA-ARGS.
Returns NIL."
  (lexpr-send hash-table :map-hash function extra-args)
  nil)

(defsubst maphash-return (function hash-table &optional (return-function 'list))
  "Apply FUNCTION to each item in HASH-TABLE; apply RETURN-FUNCTION to list of results.
FUNCTION's arguments are the key followed by the values associated with it.
The values returned by FUNCTION are put in a list.
At the end, RETURN-FUNCTION is applied to that list to get the final value."
  (lexpr-send hash-table :map-hash-return function return-function))

;;; EQUAL hash tables

(defun make-equal-hash-table (&rest options)
  "Creates an EQUAL hash table.  Valid keywords are the same as for
MAKE-HASH-TABLE, except for :HASH-FUNCTION, which should be NIL, since
the key is the code."
  (apply #'make-instance 'equal-hash-table options))

;;; The functions here have similar names to the EQ hashing ones.

(deff clrhash-equal 'clrhash)
(deff gethash-equal 'gethash)
(deff puthash-equal 'puthash)
(deff remhash-equal 'remhash)
(deff swaphash-equal 'swaphash)
(deff maphash-equal 'maphash)
(deff maphash-equal-return 'maphash-return)
(compiler:make-obsolete clrhash-equal "just use CLRHASH")
(compiler:make-obsolete gethash-equal "just use GETHASH")
(compiler:make-obsolete puthash-equal "just use PUTHASH")
(compiler:make-obsolete swaphash-equal "just use SWAPHASH")
(compiler:make-obsolete maphash-equal "just use MAPHASH")
(compiler:make-obsolete maphash-equal-return "just use MAPHASH-RETURN")

(defun equal-hash (key) (sxhash key t))
(deff sxhash-for-hash-table 'equal-hash)

(defun eql-hash (key)
  (if (and (numberp key) (not (fixnump key)))
      (sxhash key)
      key))

;;;; Bootstrapping of flavor hash tables.

;;; This is what the flavor system calls to puthash into a hash array

;;; HASH FSET's this to PUTHASH-BOOTSTRAP so FLAVOR can load.
(defun puthash-array (key value hash-array &rest additional-values)
  (let ((instance (hash-table-instance hash-array)))
    (if instance (lexpr-send instance :put-hash key value additional-values)
      (apply #'puthash-bootstrap key value hash-array additional-values))))

;;; Create a hash table suitable for a flavor's method hash table
;;; and return its hash array.
;;; Before this file is loaded, another definition in the file HASH is used
;;; which just makes a hash array with no instance.
(defun make-flavor-hash-array (area size)
  (send (instantiate-flavor 'hash-table `(nil :area ,area :size ,size
					      :funcallable-p t
					      :rehash-threshold 0.8s0
					      :number-of-values 2)
			    t nil area)

	:hash-array))

;;; When this file is first loaded, various flavors have been given hash arrays
;;; that have no hash instances associated with them.
;;; Find all those hash arrays and give them instances.
(defun hash-flavor-install ()
  (dolist (fn *all-flavor-names*)
    (let ((fl (compilation-flavor fn)))
      (and (typep fl 'flavor)
	   (let ((mht (flavor-method-hash-table fl)))
	     (and mht
		  (null (hash-table-instance mht))
		  (setf (hash-table-instance mht)
			(instantiate-flavor 'hash-table
					    `(nil :hash-array ,mht)
					    t nil permanent-storage-area))))))))

(add-initialization 'hash-flavor-install '(hash-flavor-install) '(:once))

;;;; LOOP iteration path HASH-ELEMENTS

(add-initialization 'add-loop-hash-elements-path '(add-hash-elements-path) '(:before-cold))

(defvar hash-elements-path-added nil
  "T if the HASH-ELEMENTS LOOP path has been added.")

;; Cannot just add it now because this file is loaded too early.
(defun add-hash-elements-path ()
  (unless hash-elements-path-added
    (setq hash-elements-path-added t)
    (define-loop-path hash-elements hash-elements-path-function (with-key of))))

;; now in sys2; loop
;(defun hash-elements-path-function (ignore variable ignore prep-phrases
;				    inclusive? ignore ignore)
;  (if inclusive?
;      (ferror nil "Inclusive stepping not supported in HASH-ELEMENTS path for ~S."
;	      variable))
;  (unless (loop-tassoc 'of prep-phrases)
;    (ferror nil "No OF phrase in HASH-ELEMENTS path for ~S." variable))
;  (let (bindings prologue steps post-endtest pseudo-steps
;	(blen-var (gensym))
;	(ht-var (gensym))
;	(i-var (gensym))
;	(len-var (gensym))
;	(tem (gensym))
;	(key-var (or (cadr (loop-tassoc 'with-key prep-phrases)) (gensym)))
;	(offset-var (gensym)))
;    (setq bindings `((,ht-var (send ,(cadr (loop-tassoc 'of prep-phrases)) :hash-array))
;		     (,blen-var nil) (,offset-var nil) (,variable nil)
;		     (,i-var nil) (,key-var nil) (,len-var nil))
;	  prologue `((setq ,blen-var
;			   (hash-table-block-length ,ht-var))
;		     (setq ,i-var (- ,blen-var))
;		     (setq ,offset-var (if (hash-table-hash-function ,ht-var) 1 0))
;		     (setq ,len-var (array-length ,ht-var)))
;	  steps `(,i-var
;		  (do ((,tem (+ ,blen-var ,i-var) (+ ,blen-var ,tem)))
;		      ((or ( ,tem ,len-var)
;			   ( (%p-data-type (locf (aref ,ht-var ,tem))) dtp-null))
;		       ,tem)))
;	  post-endtest `( ,i-var ,len-var)
;	  pseudo-steps `(,key-var (aref ,ht-var (+ ,i-var ,offset-var))
;			 ,variable (aref ,ht-var (+ ,i-var ,offset-var 1))))
;    (list bindings prologue nil steps post-endtest pseudo-steps)))
