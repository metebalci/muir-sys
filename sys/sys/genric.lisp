;;; -*- Mode:LISP; Package:SI; Lowercase:T; Base:8; Readtable:T -*-

;;>> many functions in this file have been rewritten by mly and not patched
;;>> in 99. If in doubt, CHECK!

(defsubst svref (vector index)
  "Accesses an element of a simple vector.  Actually the same as CLI:AREF."
  (common-lisp-aref vector index))

(defsubst bit (bitarray &rest subscripts)
  "Accesses an element of a bit array.  Actually the same as CLI:AREF."
  (apply #'common-lisp-aref bitarray subscripts))

(defsubst sbit (bitarray &rest subscripts)
  "Accesses an element of a simple bit array.  Actually the same as CLI:AREF."
  (apply #'common-lisp-aref bitarray subscripts))

;;; Primitives for fetching elements sequentially from either lists or arrays.
;;; You use an index variable which contains an array index if the
;;; sequence is an array, or a tail if the sequence is a list.

(defmacro seq-inc (indexvar)
  `(if (fixnump ,indexvar)
       (incf ,indexvar)
       (setq ,indexvar (cdr ,indexvar))))

(defmacro seq-fetch (sequence indexvar)
  `(if (fixnump ,indexvar)
       (cli:aref ,sequence ,indexvar)
       (car ,indexvar)))

(defmacro seq-fetch-inc (sequence indexvar)
  `(if (fixnump ,indexvar)
       (cli:aref ,sequence (prog1 ,indexvar (incf ,indexvar)))
       (pop ,indexvar)))

;;>> I'm allowed to write kludges like this. You're not.
(defmacro key-fetch (key sequence indexvar)
  `(progn (%push (if (fixnump ,indexvar)	;isn't lambda optimization a wonderful thing?
		     (cli:aref ,sequence ,indexvar)
		     (car ,indexvar)))
	  (if ,key (funcall ,key (%pop)) (%pop))))

(defmacro key-fetch-inc (key sequence indexvar)
  `(progn (%push (if (fixnump ,indexvar)
		     (cli:aref ,sequence (prog1 ,indexvar (incf ,indexvar)))
		     (pop ,indexvar)))
	  (if ,key (funcall ,key (%pop)) (%pop))))

(defmacro seq-store (sequence indexvar value)
  `(if (fixnump ,indexvar)
       (setf (cli:aref ,sequence ,indexvar) ,value)
       (setf (car ,indexvar) ,value)))

;;; This returns an index variable value that is ready to fetch the
;;; first element of the sequence.

(defmacro seq-start (sequence &optional numeric-index)
  (if numeric-index
      `(if (arrayp ,sequence)
	   ,numeric-index
	   (nthcdr ,numeric-index ,sequence))
      `(if (arrayp ,sequence) 0 ,sequence)))

;;; This returns a value for use in an end-test.
;;; Compare the index var against this value with EQ to see if you are at the end.
(defmacro seq-end (sequence &optional numeric-index)
  `(if (arrayp ,sequence)
       (or ,numeric-index (length ,sequence))
       (and ,numeric-index (nthcdr ,numeric-index ,sequence))))


(defun make-sequence (type size &key (initial-element nil initp))
  "Returns a sequence of SIZE elements, of type TYPE.
Each element is set to INITIAL-ELEMENT.
TYPE must be equivalent to either LIST or some sort of ARRAY.
If the value is a list, it is completely cdr-coded."
  (cond ((eq type 'list)
	 (if initp
	     (make-list size :initial-value initial-element)
	     (make-list size)))
	((or (memq type '(array simple-array vector simple-vector))
	     (and (memq (car-safe type) '(array simple-array vector simple-vector))
		  (eq (cadr type) 't)))
	 (if initp
	     (make-array size :initial-element initial-element)
	     (make-array size)))
	((memq type '(string simple-string))
	 (if initp
	     (make-array size :type art-string :initial-element initial-element)
	     (make-array size :type art-string)))
	(t
	 (let ((xtype (type-canonicalize type nil nil)))
	   (cond
	     ((eq xtype 'list)
	      (make-list size :initial-element initial-element))
	     ((or (memq xtype '(array simple-array))
		  (and (memq (car-safe xtype) '(array simple-array))
			   (memq (cadr xtype) '(t *))))
	      (if initp
		  (make-array size :initial-value initial-element)
		(make-array size)))
	     ((memq (car-safe xtype) '(array simple-array))
	      (if initp
		  (make-array size :element-type (cadr xtype)
				   :initial-element initial-element)
		(make-array size :element-type (cadr xtype))))
	     (t (ferror nil "Invalid sequence type ~S." type)))))))

(defvar temp-vector nil)

(defmacro get-temp-vector (size)
  `(or (do (old)
	   ((%store-conditional (locf temp-vector)
				(setq old temp-vector)
				nil)
	    (if ( (length old) ,size)
		old)))
       (make-array ,size :fill-pointer 0)))

(defun merge (result-type sequence1 sequence2 predicate &key key)
  "Return a single sequence containing the elements of SEQUENCE1 and SEQUENCE2 interleaved.
The interleaving is done by taking the next element of SEQUENCE1 unless
the next element of SEQUENCE2 is /"less/" than it according to PREDICATE.
KEY, if non-NIL, is applied to each element to get the object to
pass to PREDICATE, rather than the element itself.
RESULT-TYPE specifies the type of sequence returned."
  (let ((index-or-tail-1 (seq-start sequence1))
	(index-or-tail-2 (seq-start sequence2))
	(end1 (seq-end sequence1))
	(end2 (seq-end sequence2)))
    (do ((result (make-sequence result-type (+ (length sequence1) (length sequence2))))
	 (store-index 0 (1+ store-index))
	 val)
	(())
      (setq val (cond ((eq index-or-tail-1 end1)
		       (if (eq index-or-tail-2 end2)
			   (return result)
			 (seq-fetch-inc sequence2 index-or-tail-2)))
		      ((eq index-or-tail-2 end2)
		       (seq-fetch-inc sequence1 index-or-tail-1))
		      (t (let ((e1 (seq-fetch sequence1 index-or-tail-1))
			       (e2 (seq-fetch sequence2 index-or-tail-2)))
			   (cond ((apply-predicate-and-key predicate key e2 e1)
				  (seq-inc index-or-tail-2)
				  e2)
				 (t
				  (seq-inc index-or-tail-1)
				  e1))))))
      (if (arrayp result)
	  (setf (cli:aref result store-index) val)
	;; since a list constructud with make-list will be contiguous
	(%p-store-contents-offset val result store-index)))))

(defun subseq (sequence start &optional end)
  "Return a subsequence of SEQUENCE; a new sequence containing some of SEQUENCE's elements.
If SEQUENCE is a list, the value is also a list;
if it is an array, the value is an array of the same type.
START and END are the indices in SEQUENCE of the desired subsequence.
If END is NIL, it means the end of SEQUENCE."
  (if (vectorp sequence)
      (let ((len (length sequence))
	    vallen)
	(or (and (or (null end) ( end start))
		 ( start 0))
	    (ferror nil "Args ~S and ~S out of range for ~S" start end sequence))
	(if end
	    (setq vallen (- end start)
		  start (min len start)
		  end (min len end))
	    (setq start (min len start)
		  end len
		  vallen (- end start)))
	(let ((res (make-array vallen :type (%p-ldb-offset %%array-type-field sequence 0))))
	  (copy-array-portion sequence start end res 0 vallen)
	  res))
    (if end
	(firstn (- end start) (nthcdr start sequence))
        (nthcdr start sequence))))

(defsetf subseq subseq-setf)
(defun subseq-setf (sequence start end new-subsequence &optional (sub-start 0) sub-end)
  (if (and (vectorp sequence) (vectorp new-subsequence))
      (copy-array-portion new-subsequence sub-start (or sub-end (length new-subsequence))
			  sequence start (or end (length sequence)))
    (let ((store-index (if (vectorp sequence) start (nthcdr start sequence)))
	  (store-end (if end
			 (if (arrayp sequence) end (nthcdr sequence end))
		         (seq-end sequence)))
	  (fetch-end (seq-end new-subsequence sub-end))
	  (fetch-index (seq-start new-subsequence sub-start)))
      (do ()
	  ((or (eq store-index store-end)
	       (eq fetch-index fetch-end)))
	(seq-store sequence store-index
		   (seq-fetch-inc new-subsequence fetch-index))
	(seq-inc store-index))))
  sequence)

(defun replace (into-sequence-1 from-sequence-2 &key (start1 0) end1 (start2 0) end2)
  "Copy all or part of FROM-SEQUENCE-2 into INTO-SEQUENCE-1.
A sequence is either a list or a vector.
START1 and END1 specify the part of FROM-SEQUENCE-2 to be copied.
 They default to 0 and NIL (which means the end of the sequence).
START2 and END2 specify the part of INTO-SEQUENCE-1 to be copied into.
If the subsequence to be copied into is longer than the one to be copied,
 the extra elements of the to-subsequence are left unchanged.
If the two sequences are the same, the data is first copied to a
 intermediate location and then copied back in.
The value is INTO-SEQUENCE-1."
  (replace-1 into-sequence-1 from-sequence-2 start1 end1 start2 end2))

(defun replace-1 (into-sequence-1 from-sequence-2 &optional (start1 0) end1 (start2 0) end2)
  (or end1 (setq end1 (length into-sequence-1)))
  (or end2 (setq end2 (length from-sequence-2)))
  (if (eq into-sequence-1 from-sequence-2)
      (let* ((n-copy (min (- end2 start2) (- end1 start1)))
	     (temp (get-temp-vector n-copy)))
	(replace temp from-sequence-2 0 n-copy start2 end2)
	(replace into-sequence-1 temp start1 end1 0 n-copy)
	(setq temp-vector temp))
    (if (and (vectorp into-sequence-1) (vectorp from-sequence-2))
	(let ((n-copy (min (- end2 start2) (- end1 start1))))
	  (copy-array-portion from-sequence-2 start2 (+ start2 n-copy)
			      into-sequence-1 start1 (+ start1 n-copy)))
      (let ((store-index (if (arrayp into-sequence-1) start1 (nthcdr start1 into-sequence-1)))
	    (store-end (if (arrayp into-sequence-1) end1 (nthcdr into-sequence-1 end1)))
	    (fetch-end (if (arrayp from-sequence-2) end2 (nthcdr end2 from-sequence-2)))
	    (fetch-index (if (arrayp from-sequence-2)
			     start2 (nthcdr start2  from-sequence-2))))
	(do ()
	    ((or (eq store-index store-end)
		 (eq fetch-index fetch-end)))
	  (seq-store into-sequence-1 store-index
		     (seq-fetch-inc from-sequence-2 fetch-index))
	  (seq-inc store-index)))))
  into-sequence-1)

(defun reduce (&functional function sequence &key from-end (start 0) end
	       (initial-value nil initp))
  "Combine the elements of SEQUENCE using FUNCTION, a function of two args.
FUNCTION is applied to the first two elements; then to that result and the third element;
 then to that result and the fourth element; and so on.
START and END restrict the action to a part of SEQUENCE,
 as if the rest of SEQUENCE were not there.  They default to 0 and NIL
 (NIL for END means to the end of SEQUENCE).
If FROM-END is non-NIL, FUNCTION is applied to the last two elements;
 then to the previous element and that result; then to the previous
 element and that result; and so on.
If INITIAL-VALUE is specified, it acts like an extra element of SEQUENCE
 at the end (if FROM-END is non-NIL) or the beginning, in addition to
 the actual elements of the specified part of SEQUENCE.  Then there is
 effectively one more element to be processed.  The INITIAL-VALUE is
 used in the first call to FUNCTION.
If there is only one element to be processed,
 that element is returned and FUNCTION is not called.
If there are no elements (SEQUENCE is of length zero and no INITIAL-VALUE),
 FUNCTION is called with no arguments and its value is returned."
  (cond (from-end
	 (cond ((vectorp sequence)
		(do ((index (1- (or end (length sequence))) (1- index))
		     (notfirst initp t)
		     (accum initial-value))
		    ((< index start)
		     (if notfirst accum (funcall function)))
		  (if notfirst
		      (setq accum (funcall function (cli:aref sequence index) accum))
		    (setq accum (cli:aref sequence index)))))
	       (t
		(let ((tail-recursion-flag t))
		  (reduce-list-backwards function (nthcdr start sequence)
					 (if end (- end start) -1) initial-value initp)))))
	(t
	 (do ((index (seq-start sequence start))
	      (end-index (seq-end sequence end))
	      (notfirst initp t)
	      (accum initial-value))
	     ((eq index end-index)
	      (if notfirst accum (funcall function)))
	   (%push (seq-fetch-inc sequence index))
	   (setq accum (if notfirst (funcall function (%pop)) (%pop)))))))

(defun reduce-list-backwards (function list length initial initp)
  (if (or (null list) (eq length 0))
      (if initp initial (funcall function))
    (if (and (null initp) (or (null (cdr list)) (eq length 1)))
	(car list)
      (funcall function
	       (car list)
	       (reduce-list-backwards function (cdr list) (1- length) initial initp)))))

(defun concatenate (result-type &rest sequences)
  "Return a sequence of type RESULT-TYPE concatenating the contents of the SEQUENCES.
Each sequence argument may be a list or an array.
RESULT-TYPE must be a valid sequence type such as LIST or VECTOR."
  (let ((rlen 0))
    (dolist (s sequences)
      (incf rlen (length s)))
    (let ((result (make-sequence result-type rlen)))
      (let ((store-index (seq-start result)))
	(dolist (s sequences)
	  (if (and (arrayp result) (arrayp s))
	      (let ((len (length s)))
		(copy-array-portion s 0 len
				    result store-index (+ store-index len))
		(incf store-index len))
	    (do ((fetch-index (seq-start s))
		 (fetch-end (seq-end s)))
		((eq fetch-index fetch-end))
	      (seq-store result store-index
			 (seq-fetch-inc s fetch-index))
	      (seq-inc store-index)))))
      result)))

(defun fill (sequence item &key (start 0) end)
  "Set all the elements of SEQUENCE (or some subsequence of it) to ITEM.
START and END specify the subsequence; they default to 0 and NIL
/(NIL for END means to the end of SEQUENCE)."
  (if (arrayp sequence)
      (array-initialize sequence item start end)
    (let ((tail (nthcdr start sequence)))
      (do ((tail tail (cdr tail))
	   (stop (if end (nthcdr (- end start) tail))))
	  ((eq tail stop))
	(setf (car tail) item))))
  sequence)

(defun fill-array-from-sequences (array sequence dimension array-index)
  (if (= 0 (array-rank array))
      (setf (cli:aref array) sequence)
    (do ((index (seq-start sequence))
	 (i 0 (1+ i))
	 (last-dim-flag (= (1+ dimension) (array-rank array)))
	 (stop-i (array-dimension array dimension)))
	((= i stop-i))
      (if last-dim-flag
	  ;; Cut off one level of recursion - eliminates most of the function calls.
	  (setf (ar-1-force array (+ (* array-index stop-i) i))
		(seq-fetch-inc sequence index))
	(fill-array-from-sequences array (seq-fetch-inc sequence index) (1+ dimension)
				   (+ (* array-index stop-i) i))))))

(defun cli:map (result-type &functional fcn &eval &rest sequences)
  "Maps over successive elements of each SEQUENCE, returns a sequence of the results.
FCN is called first on the 0'th elements of all the sequences,
then on the 1st elements of all, and so on until some argument sequence is exhausted.
The values returned by FCN are put into a result sequence which is returned by MAP.
RESULT-TYPE is a sequence type; the result is of that type.
Or RESULT-TYPE can be NIL, meaning call FCN for effect only,
throw away the values, and return NIL."
 (block map
  (let (result-length)
    ;; Figure out the obvious things about the number of iterations
    ;; regardless of whether we are making a result sequence.
    ;; It makes the end tests faster anyway.
    (dolist (s sequences)
      (cond ((arrayp s)
	     (setq result-length
		   (if result-length (min result-length (length s)) (length s))))
	    ((null s)
	     (setq result-length 0)
	     (return))))
    ;; If some arg is length 0, return fast.
    (and (eql 0 result-length)
	 (return-from map
	   (and result-type
		(make-sequence result-type 0))))
    (if result-type
	(prog ((index 0) val s-tail result store-index)
	      (unless result-length
		;; If making a list and all args are lists,
		;; MAPCAR is suitable, and faster than figuring out
		;; the lengths of everything in advance.
		(and (eq result-type 'list)
		     (return-from map
		       (apply #'mapcar fcn sequences)))
		;; Otherwise, must find the length of the shortest arg
		;; without wasting too much time on any circular lists.
		(loop for s in sequences
		      with min = nil
		      do (let ((thislength
				 (if (consp s) (or (list-length s) min)
				   (length s))))
			   (if min (setq min (min min thislength))
			     (setq min thislength)))
		      finally (setq result-length min)))
	      (setq result (make-sequence result-type result-length))
	      (setq store-index (seq-start result))

	      ;; Now we are ready to do the actual mapping.
	      (%assure-pdl-room (+ (length sequences) 4))	;Make sure %PUSH's don't lose
	   nextcall  ;; Here to compute the next element of the result.
	      (when (= index result-length)
		(return result))
	      (%open-call-block fcn 0 1)	;Destination is stack
	      (setq s-tail sequences)
	   nextarg  ;; Here to push the next arg for FCN.
	      (%push (if (arrayp (car s-tail))
			 (cli:aref (car s-tail) index)
		         (pop (car s-tail))))
	      (pop s-tail)
	      (when s-tail (go nextarg))
	      ;; Now all the args are pushed.
	      (%activate-open-call-block)
	      (setq val (%pop))
	      (seq-store result store-index val)
	      (seq-inc store-index)
	      (incf index)
	      (go nextcall))
      (prog ((index 0) s-tail)
	    (%assure-pdl-room (+ (length sequences) 4))	;Make sure %PUSH's don't lose
	 nextcall
	    (when (eql index result-length)
	      (return nil))
	    (%open-call-block fcn 0 0)		;Destination is ignore
	    (setq s-tail sequences)
	 nextarg
	    (%push (if (arrayp (car s-tail))
		       (cli:aref (car s-tail) index)
		     (unless (car s-tail) (return nil))
		     (pop (car s-tail))))
	    (pop s-tail)
	    (when s-tail (go nextarg))
	    ;; Now all the args are pushed.
	    (%activate-open-call-block)
	    (incf index)
	    (go nextcall))))))

(defun cli:some (&functional predicate &eval &rest sequences)
  "Applies PREDICATE to successive elements of SEQUENCES; if it returns non-NIL, so does SOME.
PREDICATE gets one argument from each sequence; first element 0
of each sequence, then element 1, and so on.
If PREDICATE returns non-NIL, the value it returns is returned by SOME.
If one of the sequences is exhausted, SOME returns NIL."
  (block some
    (prog ((index 0) s-tail value)
	  (%assure-pdl-room (+ (length sequences) 4))	;Make sure %PUSH's don't lose
       nextcall
	  (%open-call-block predicate 0 1)		;Destination is stack
	  (setq s-tail sequences)
       nextarg
	  (%push (cond ((arrayp (car s-tail))
			(when (= index (length (car s-tail))) (return nil))
			(cli:aref (car s-tail) index))
		       (t
			(when (null (car s-tail)) (return nil))
			(pop (car s-tail)))))
	  (pop s-tail)
	  (when s-tail (go nextarg))
	  ;; Now all the args are pushed.
	  (%activate-open-call-block)
	  (setq value (%pop))
	  (when value (return value))
	  (incf index)
	  (go nextcall))))

(defun notevery (&functional predicate &eval &rest sequences)
  "Applies PREDICATE to successive elements of SEQUENCES; T if PREDICATE ever returns NIL.
PREDICATE gets one argument from each sequence; first element 0
of each sequence, then element 1, and so on.
If PREDICATE returns NIL, then NOTEVERY returns T.
If one of the sequences is exhausted, NOTEVERY returns NIL."
  (prog ((index 0) s-tail)
	(%assure-pdl-room (+ (length sequences) 4))	;Make sure %PUSH's don't lose
     nextcall
	(%open-call-block predicate 0 1)		;Destination is stack
	(setq s-tail sequences)
     nextarg
	(%push (cond ((arrayp (car s-tail))
		      (when (= index (length (car s-tail))) (return nil))
		      (cli:aref (car s-tail) index))
		     (t
		      (when (null (car s-tail)) (return nil))
		      (pop (car s-tail)))))
	(pop s-tail)
	(when s-tail (go nextarg))
	;; Now all the args are pushed.
	(%activate-open-call-block)
	(unless (%pop) (return t))
	(incf index)
	(go nextcall)))

(defun notany (&functional predicate &eval &rest sequences)
  "Applies PREDICATE to successive elements of SEQUENCES; T if PREDICATE always returns NIL.
PREDICATE gets one argument from each sequence; first element 0
of each sequence, then element 1, and so on.
If PREDICATE returns non-NIL, then NOTANY returns NIL.
If one of the sequences is exhausted, NOTANY returns T."
  (prog ((index 0) s-tail)
	(%assure-pdl-room (+ (length sequences) 4))	;Make sure %PUSH's don't lose
     nextcall
	(%open-call-block predicate 0 1)		;Destination is stack
	(setq s-tail sequences)
     nextarg
	(%push (cond ((arrayp (car s-tail))
		      (when (= index (length (car s-tail))) (return t))
		      (cli:aref (car s-tail) index))
		     (t
		      (when (null (car s-tail)) (return t))
		      (pop (car s-tail)))))
	(pop s-tail)
	(when s-tail (go nextarg))
	;; Now all the args are pushed.
	(%activate-open-call-block)
	(when (%pop) (return nil))
	(incf index)
	(go nextcall)))

(defun cli:every (&functional predicate &eval &rest sequences)
  "Applies PREDICATE to successive elements of SEQUENCES; T if PREDICATE always returns T.
PREDICATE gets one argument from each sequence; first element 0
of each sequence, then element 1, and so on.
If PREDICATE returns NIL, then EVERY returns NIL.
If one of the sequences is exhausted, EVERY returns T."
  (block every
    (prog ((index 0) s-tail)
	  (%assure-pdl-room (+ (length sequences) 4))	;Make sure %PUSH's don't lose
       nextcall
	  (%open-call-block predicate 0 1)		;Destination is stack
	  (setq s-tail sequences)
       nextarg
	  (%push (cond ((arrayp (car s-tail))
			(when (= index (length (car s-tail))) (return t))
			(cli:aref (car s-tail) index))
		       (t
			(when (null (car s-tail)) (return t))
			(pop (car s-tail)))))
	  (pop s-tail)
	  (when s-tail (go nextarg))
	  ;; Now all the args are pushed.
	  (%activate-open-call-block)
	  (unless (%pop) (return nil))
	  (incf index)
	  (go nextcall))))

(defun remove-if (predicate sequence &key (start 0) end count key from-end)
  "Return SEQUENCE, partially copied so that elements satisfying PREDICATE are omitted.
START and END specify a subsequence to consider; elements outside
 that subsequence will not be removed even if they would satisfy PREDICATE.
 They default to 0 and NIL (which means the end of the sequence).
KEY, if non-NIL, is a function to be applied to each element
 to get the object to pass to the PREDICATE.  If KEY is NIL,
 the element itself is passed to the PREDICATE.
COUNT can be used to specify how many elements to remove (at maximum);
 after that many have been found, the rest are left alone.
FROM-END, if non-NIL, means that the last COUNT matching elements
 should be removed, rather than the first COUNT many."
  (funcall (etypecase sequence
	     (list #'remove-from-list)
	     (vector #'remove-from-array))
	   nil sequence start end count nil nil key from-end predicate))

(defun remove-if-not (predicate sequence &key (start 0) end count key from-end)
  "Like REMOVE-IF but removes elements which do not satisfy PREDICATE."
  (funcall (etypecase sequence
	     (list #'remove-from-list)
	     (vector #'remove-from-array))
	   nil sequence start end count nil t key from-end predicate))

(defun cli:remove (item sequence &key test test-not (start 0) end count key from-end)
  "Return SEQUENCE, partially copied so that elements matching ITEM are omitted.
START and END specify a subsequence to consider; elements outside
 that subsequence will not be removed even if they would match.
 They default to 0 and NIL (which means the end of the sequence).
KEY, if non-NIL, is a function to be applied to each element
 to get the object to match against ITEM.  If KEY is NIL,
 the element itself is matched.
TEST is a function of two args to use to compare ITEM against an element (or key).
 An element matches when the TEST function returns non-NIL.
 Alternatively, specify as TEST-NOT a function to use which returns NIL if there is a match.
COUNT can be used to specify how many elements to remove (at maximum);
 after that many have been found, the rest are left alone.
FROM-END, if non-NIL, means that the last COUNT matching elements
 should be removed, rather than the first COUNT many."
  (funcall (etypecase sequence
	     (list #'remove-from-list)
	     (vector #'remove-from-array))
	   item sequence start end count (or test-not test) (not (null test-not))
	   key from-end nil))

(defun delete-if (predicate sequence &key (start 0) end count key from-end)
  "Return SEQUENCE, modified so that elements satisfying PREDICATE are omitted.
The value may be SEQUENCE itself destructively modified or it may be a copy.
START and END specify a subsequence to consider; elements outside
 that subsequence will not be removed even if they would satisfy PREDICATE.
 They default to 0 and NIL (which means the end of the sequence).
KEY, if non-NIL, is a function to be applied to each element
 to get the object to pass to the PREDICATE.  If KEY is NIL,
 the element itself is passed to the PREDICATE.
COUNT can be used to specify how many elements to remove (at maximum);
 after that many have been found, the rest are left alone.
FROM-END, if non-NIL, means that the last COUNT matching elements
 should be removed, rather than the first COUNT many."
  (funcall (etypecase sequence
	     (list #'delete-from-list)
	     (vector #'delete-from-array))
	   nil sequence start end count nil nil key from-end predicate))

(defun delete-if-not (predicate sequence &key (start 0) end count key from-end)
  "Like DELETE-IF but deletes elements which do not satisfy PREDICATE."
  (funcall (etypecase sequence
	     (list #'delete-from-list)
	     (vector #'delete-from-array))
	   nil sequence start end count nil t key from-end predicate))

(defun cli:delete (item sequence &key test test-not (start 0) end count key from-end)
  "Return SEQUENCE, partially copied so that elements matching ITEM are omitted.
START and END specify a subsequence to consider; elements outside
 that subsequence will not be removed even if they would match.
 They default to 0 and NIL (which means the end of the sequence).
KEY, if non-NIL, is a function to be applied to each element
 to get the object to match against ITEM.  If KEY is NIL,
 the element itself is matched.
TEST is a function of two args to use to compare ITEM against an element (or key).
 An element matches when the TEST function returns non-NIL.
 Alternatively, specify as TEST-NOT a function to use which returns NIL if there is a match.
COUNT can be used to specify how many elements to remove (at maximum);
 after that many have been found, the rest are left alone.
FROM-END, if non-NIL, means that the last COUNT matching elements
 should be removed, rather than the first COUNT many."
  (funcall (etypecase sequence
	     (list #'delete-from-list)
	     (vector #'delete-from-array))
	   item sequence start end count (or test-not test) (not (null test-not))
	   key from-end nil))

(defun remove-from-array (item vector
			  start end count test invertp key from-end one-arg-predicate)
  (or end (setq end (length vector)))
  (or count (setq count (length vector)))
  (let ((temp (get-temp-vector (min count (- end start))))
	elt)
    (setf (fill-pointer temp) 0)
    ;; Find the indices of all the things we want to remove.
    (if from-end
	(do ((i (1- end) (1- i)))
	    ((or (< i start)
		 ( (fill-pointer temp) count))
	     (nreverse temp))
	  (setq elt (if key (funcall key (cli:aref vector i)) (cli:aref vector i)))
	  (if (eq invertp (not (cond (one-arg-predicate
				      (funcall one-arg-predicate elt))
				     (test
				      (funcall test item elt))
				     (t
				      (eql item elt)))))
	    (vector-push i temp)))
      (do ((i start (1+ i)))
	  ((or ( i end) ( (fill-pointer temp) count)))
	(setq elt (if key (funcall key (cli:aref vector i)) (cli:aref vector i)))
	(if (eq invertp (not (cond (one-arg-predicate
				    (funcall one-arg-predicate elt))
				   (test
				    (funcall test item elt))
				   (t
				    (eql item elt)))))
	    (vector-push i temp))))
    ;; Now TEMP contains the indices of the elements to be removed, in ascending order.
    (cond ((zerop (fill-pointer temp))
	   (setq temp-vector temp)
	   vector)
	  (t
	   (let ((result (make-array (- (length vector) (fill-pointer temp))
				     :type (array-type vector))))
	     (copy-array-portion vector 0 (cli:aref temp 0) result 0 (cli:aref temp 0))
	     (do ((i 1 (1+ i))
		  (stop (fill-pointer temp)))
		 (( i stop)
		  (let ((x (1+ (cli:aref temp (1- i)))))
		    (copy-array-portion vector  x (length vector)
					result (- x i) (length result))))
	       (let ((x (1+ (cli:aref temp (1- i))))
		     (y (cli:aref temp i)))
		 (copy-array-portion vector x y result (- x i) (- y i))))
	     (setq temp-vector temp)
	     result)))))
(deff delete-from-array 'remove-from-array)

(defun remove-from-list (item list
			 start end count test invertp key from-end one-arg-predicate
			 &aux (skip-count 0))
  (or count (setq count most-positive-fixnum))
  (or end (setq end (length list)))
  (when from-end
    (unless (and end ( count (- end start)))
      (setq skip-count
	    (max 0 (- (count-1 item list start end test invertp key) count)))))
  (if (and (plusp count)
	   (or (null end) (> end start)))
      (let ((head (variable-location list))
	    elt)
	(loop for start-tail = (nthcdr start list) then (cdr head)
	      with end-tail = (and end (nthcdr (- end start) start-tail))
	      as tail = (do ((l start-tail (cdr l)))
			    ((eq l end-tail) l)
			  (setq elt (if key (funcall key (car l)) (car l)))
			  (if (eq invertp (not (cond (one-arg-predicate
						      (funcall one-arg-predicate elt))
						     (test
						      (funcall test item elt))
						     (t
						      (eql item elt)))))
			      (return l)))
	      until (eq tail end-tail)
	      when (minusp (decf skip-count))
	      do (loop until (eq (cdr head) tail)
		       do (setf (cdr head) (setq head (cons (cadr head) (cddr head)))))
	         (setf (cdr head) (cdr tail))
		 (when (zerop (decf count))
		   (return)))))
  list)

(defun delete-from-list (item list
			 start end count test invertp key from-end one-arg-predicate
			 &aux (skip-count 0))
  (or count (setq count most-positive-fixnum))
  (or end (setq end (length list)))
  (when from-end
    (unless (and end ( count (- end start)))
      (setq skip-count (max 0 (- (count-1 item list start end test invertp key) count)))))
  (if (and (plusp count)
	   (or (null end) (> end start)))
      (let* ((tail (nthcdr start (variable-location list)))
	     (end-tail (and end (nthcdr (- end start) (cdr tail)))))
	(do (elt)
	    ((eq (cdr tail) end-tail))
	  (setq elt (if key (funcall key (cadr tail)) (cadr tail)))
	  (cond ((and (eq invertp (not (cond (one-arg-predicate
					      (funcall one-arg-predicate elt))
					     (test
					      (funcall test item elt))
					     (t
					      (eql item elt)))))
		      (minusp (decf skip-count)))
		 (setf (cdr tail) (cddr tail))
		 (when (zerop (decf count))
		   (return)))
		(t (setq tail (cdr tail)))))))
  list)

(defun remove-duplicates (sequence &key (start 0) end key from-end test test-not)
  "Returns SEQUENCE, partially copied if necessary, omitting duplicate elements.
Elements are compared using TEST, a function of two arguments.
 Elements match if TEST returns non-NIL.  Alternatively, specify TEST-NOT;
 then elements match if TEST-NOT returns NIL.
If KEY is non-NIL, then it is a function of one arg, which is applied
 to each element to get the /"key/" which is passed to TEST or TEST-NOT.
START and END are indices specifying the part of SUBSEQUENCE considered.
 They default to 0 and NIL (which means the end of SEQUENCE).
 Elements outside this subsequence are not looked at.
Duplicate elements are not necessarily identical.
Normally the last duplicate element is the one retained.
If FROM-END is non-NIL, the first one is retained."
  (funcall (etypecase sequence
	     (list #'remove-duplicates-from-list)
	     (vector #'remove-duplicates-from-array))
	   sequence start end (or test-not test) (not (null test-not)) key from-end))

(defun delete-duplicates (sequence &key (start 0) end key from-end test test-not)
  "Like REMOVE-DUPLICATES except that SEQUENCE may be destructively modified.
/(If it is an array, it will probably be copied anyway.)
Returns SEQUENCE, sans any duplicate elements.
Elements are compared using TEST, a function of two arguments.
 Elements match if TEST returns non-NIL.  Alternatively, specify TEST-NOT;
 then elements match if TEST-NOT returns NIL.
If KEY is non-NIL, then it is a function of one arg, which is applied
 to each element to get the /"key/" which is passed to TEST or TEST-NOT.
START and END are indices specifying the part of SUBSEQUENCE considered.
 They default to 0 and NIL (which means the end of SEQUENCE).
 Elements outside this subsequence are not looked at.
Duplicate elements are not necessarily identical.
Normally the last duplicate element is the one retained.
If FROM-END is non-NIL, the first one is retained."
  (funcall (etypecase sequence
	     (list #'delete-duplicates-from-list)
	     (vector #'delete-duplicates-from-array))
	   sequence start end (or test-not test) (not (null test-not)) key from-end))

(defun remove-duplicates-from-array (sequence start end test invertp key from-end)
  (or end (setq end (length sequence)))
  (let ((temp (get-temp-vector (- end start))))
    (setf (fill-pointer temp) 0)
    ;; Find the indices of all the things we want to remove.
    (if from-end
	(do ((i (1- end) (1- i)))
	    ((< i start)
	     (nreverse temp))
	  (when (nth-value 1 (find-1 (if key (funcall key (cli:aref sequence i))
				       (cli:aref sequence i))
				     sequence start (1+ i) test invertp key))
	    (vector-push i temp)))
        (do ((i start (1+ i)))
	    (( i end))
	  (when (nth-value 1 (find-1 (if key (funcall key (cli:aref sequence i))
				       (cli:aref sequence i))
				     sequence i end test invertp key))
	    (vector-push i temp))))
    ;; Now TEMP contains the indices of the elements to be removed, in ascending order.
    (cond ((zerop (fill-pointer temp))
	   (setq temp-vector temp)
	   sequence)
	  (t
	   (let ((result (make-array (- (length sequence) (fill-pointer temp))
				     :type (array-type sequence))))
	     (copy-array-portion sequence 0 (cli:aref temp 0) result 0 (cli:aref temp 0))
	     (do ((i 1 (1+ i))
		  (stop (fill-pointer temp)))
		 (( i stop)
		  (let ((x (1+ (cli:aref temp (1- i)))))
		    (copy-array-portion sequence  x (length sequence)
					result (- x i) (length result))))
	       (let ((x (1+ (cli:aref temp (1- i))))
		     (y (cli:aref temp i)))
		 (copy-array-portion sequence x y
				     result (- x i) (- y i))))
	     (setq temp-vector temp)
	     result)))))
(deff delete-duplicates-from-array 'remove-duplicates-from-array)

(defun remove-duplicates-from-list (list start end test invertp key from-end)
  (if (or (null end) (> end start))
      (loop with head = (variable-location list)
	    for start-tail = (nthcdr start list) then (cdr head)
	    with end-tail = (and end (nthcdr (- end start) start-tail))
	    as tail = (do ((l start-tail (cdr l))
			   elt)
			  ((eq l end-tail) l)
			(setq elt (if key (funcall key (car l)) (car l)))
			(when (nth-value 1
				(if from-end
				    (find-1 elt list 0 l test invertp key)
				    (find-1 elt (cdr l) 0 end-tail test invertp key)))
			    (return l)))
	    until (eq tail end-tail)
	    do (loop until (eq (cdr head) tail)
		     do (setf (cdr head) (setq head (cons (cadr head) (cddr head)))))
	       (setf (cdr head) (cdr tail))))
  list)

(defun delete-duplicates-from-list (list start end test invertp key from-end)
  (if (or (null end) (> end start))
      (let* ((tail (nthcdr start (variable-location list)))
	     (end-tail (and end (nthcdr (- end start) (cdr tail)))))
	(do (elt)
	    ((eq (cdr tail) end-tail))
	  (setq elt (if key (funcall key (cadr tail)) (cadr tail)))
	  (if (nth-value 1
		(if from-end
		    (find-1 elt list 0 (cdr tail) test invertp key)
		    (find-1 elt (cddr tail) 0 end-tail test invertp key)))
	      (setf (cdr tail) (cddr tail))
	      (setq tail (cdr tail))))))
  list)

(defun substitute-if (newitem predicate sequence &key (start 0) end count key from-end)
  "Return SEQUENCE copied as necessary so that NEWITEM replaces any elements
satisfying PREDICATE.
SEQUENCE can be a list or an array.  A list may be copied partially.
If COUNT is non-NIL, it is the number of such elements to replace.
The first COUNT-many suitable elements are replaced, or,
 if FROM-END is non-NIL, the last COUNT-many are replaced.
KEY, if non-NIL, is a function to be applied to each element to get a key,
 which is passed to PREDICATE.  If KEY is NIL, the element itself is used.
START and END are indices restricting substitution to a subsequence of SEQUENCE.
 They default to 0 and NIL (which means the end of SEQUENCE).
 Elements outside that range are never substituted for."
  (funcall (etypecase sequence
	     (list #'substitute-in-list)
	     (vector #'substitute-in-array))
	   t newitem nil sequence start end count nil nil key from-end predicate))

(defun substitute-if-not (newitem predicate sequence &key (start 0) end count key from-end)
  "Like SUBSTITUTE-IF except the elements replaced are those for which PREDICATE returns NIL."
  (funcall (etypecase sequence
	     (list #'substitute-in-list)
	     (vector #'substitute-in-array))
	   t newitem nil sequence start end count nil t key from-end predicate))

(defun substitute (newitem olditem sequence
		   &key test test-not (start 0) end count key from-end)
  "Return SEQUENCE copied if necessary so that NEWITEM replaces any elements matching OLDITEM.
SEQUENCE can be a list or an array.  A list may be copied partially.
If COUNT is non-NIL, it is the number of such elements to replace.
The first COUNT-many suitable elements are replaced, or,
 if FROM-END is non-NIL, the last COUNT-many are replaced.
TEST is a function of two args to use to compare OLDITEM against an element (or key).
 An element matches when the TEST function returns non-NIL.
 Alternatively, specify as TEST-NOT a function to use which returns NIL if there is a match.
KEY, if non-NIL, is a function to be applied to each element to get a key,
 which is passed to TEST or TEST-NOT.  If KEY is NIL, the element itself is used.
START and END are indices restricting substitution to a subsequence of SEQUENCE.
 They default to 0 and NIL (which means the end of SEQUENCE).
 Elements outside that range are never substituted for."
  (funcall (etypecase sequence
	     (list #'substitute-in-list)
	     (vector #'substitute-in-array))
	   t newitem olditem sequence start end count (or test-not test) (not (null test-not))
	   key from-end nil))

(defun nsubstitute-if (newitem predicate sequence &key (start 0) end count key from-end)
  "Like SUBSTITUTE-IF except that SEQUENCE may be destructively modified rather than copied."
  (funcall (etypecase sequence
	     (list #'substitute-in-list)
	     (vector #'substitute-in-array))
	   nil newitem nil sequence start end count nil nil key from-end predicate))

(defun nsubstitute-if-not (newitem predicate sequence &key (start 0) end count key from-end)
  "Like SUBSTITUTE-IF-NOT except that SEQUENCE may be destructively modified
rather than copied."
  (funcall (etypecase sequence
	     (list #'substitute-in-list)
	     (vector #'substitute-in-array))
	   nil newitem nil sequence start end count nil t key from-end predicate))

(defun nsubstitute (newitem olditem sequence
		    &key test test-not (start 0) end count key from-end)
  "Like SUBSTITUTE except that SEQUENCE may be destructively modified rather than copied."
  (funcall (etypecase sequence
	     (list #'substitute-in-list)
	     (vector #'substitute-in-array))
	   nil newitem olditem sequence start end count
	   (or test-not test) (not (null test-not)) key from-end nil))

(defun substitute-in-array (copyflag newitem olditem sequence
			    start end count test invertp key from-end one-arg-predicate
			    &aux result)
  (or count (setq count (length sequence)))
  (or end (setq end (length sequence)))
  (or copyflag (setq result sequence))
  (do ((i (if from-end (1- end) start)
	  (+ i inc))
       (inc (if from-end -1 1))
       (num-replaced 0)
       elt)
      ((or (if from-end (< i start) ( i end))
	   ( num-replaced count)))
    (setq elt (if key (funcall key (cli:aref sequence i)) (cli:aref sequence i)))
    (when (eq invertp (not (cond (one-arg-predicate
				  (funcall one-arg-predicate elt))
				 (test
				  (funcall test olditem elt))
				 (t
				  (eql olditem elt)))))
      (unless result
	(setq result (make-array (length sequence) :type (array-type sequence)))
	(copy-array-contents sequence result))
      (setf (cli:aref result i) newitem)
      (incf num-replaced)))
  (or result sequence))

(defun substitute-in-list (copyflag newitem olditem list
			   start end count test invertp key from-end one-arg-predicate
			   &aux (skip-count 0))
  (or count (setq count most-positive-fixnum))
  (when from-end
    (unless (and end ( count (- end start)))
      (setq skip-count (max 0 (- (count-1 olditem list start end test invertp
					  key one-arg-predicate)
				 count)))))
  (if (and (plusp count)
	   (or (null end) (> end start)))
      (loop with head = (variable-location list)
	    for start-tail = (nthcdr start list) then (cdr head)
	    with end-tail = (and end (nthcdr (- end start) start-tail))
	    as tail = (do ((l start-tail (cdr l))
			   elt)
			  ((eq l end-tail) l)
			(setq elt (if key (funcall key (car l)) (car l)))
			(when (eq invertp (cond (one-arg-predicate
						 (funcall one-arg-predicate elt))
						(test
						 (funcall test olditem elt))
						(t
						 (eql olditem elt))))
			  (return l)))
	    until (eq tail end-tail)
	    when (minusp (decf skip-count))
	    do (if (not copyflag)
		   (setf (car tail) newitem)
		 (loop until (eq (cdr head) (cdr tail))
		       do (setf (cdr head) (setq head (cons (cadr head) (cddr head)))))
		 (setf (car head) newitem))
	       (when (zerop (setq count (1- count)))
		 (return))))
  list)

(defun position-if (predicate sequence &key from-end (start 0) end key)
  "Return index in SEQUENCE of first element that satisfies PREDICATE.
Value is NIL if no element satisfies PREDICATE.  SEQUENCE can be a list or an array.
KEY, if non-NIL, is a function to be applied to each element to get a key,
 which is passed to PREDICATE.  If KEY is NIL, the element itself is used.
START and END are indices restricting substitution to a subsequence of SEQUENCE.
 They default to 0 and NIL (which means the end of SEQUENCE).
 Elements outside that range are not tested.
 The value is the index in SEQUENCE, not in the subsequence which was searched.
If FROM-END is non-NIL, the value describes the LAST element in SEQUENCE
 (or specified subsequence) that satisfies the predicate."
  (nth-value 1 (find-1 nil sequence start end nil nil key from-end predicate)))

(defun position-if-not (predicate sequence &key from-end (start 0) end key)
  "Like POSITION-IF but looks for an element which does NOT satisfy PREDICATE."
  (nth-value 1 (find-1 nil sequence start end nil t key from-end predicate)))

(defun position (item sequence &key from-end test test-not (start 0) end key)
  "Return index in SEQUENCE of first element that matches ITEM.
Value is NIL if no element matches.  SEQUENCE can be a list or an array.
TEST is a function of two args to use to compare ITEM against an element (or key).
 An element matches when the TEST function returns non-NIL.
 Alternatively, specify as TEST-NOT a function to use which returns NIL if there is a match.
KEY, if non-NIL, is a function to be applied to each element to get a key,
 which is passed to TEST or TEST-NOT.  If KEY is NIL, the element itself is used.
START and END are indices restricting substitution to a subsequence of SEQUENCE.
 They default to 0 and NIL (which means the end of SEQUENCE).
 Elements outside that range are not tested.
 The value is the index in SEQUENCE, not in the subsequence which was searched.
If FROM-END is non-NIL, the value describes the LAST element in SEQUENCE
 (or specified subsequence) that matches."
  (nth-value 1 (find-1 item sequence start end (or test-not test) (not (null test-not))
		       key from-end nil)))

(defun find-if (predicate sequence &key from-end (start 0) end key)
  "Return the first element of SEQUENCE that satisfies PREDICATE.
Value is NIL if no element satisfies PREDICATE.  SEQUENCE can be a list or an array.
KEY, if non-NIL, is a function to be applied to each element to get a key,
 which is passed to PREDICATE.  If KEY is NIL, the element itself is used.
START and END are indices restricting substitution to a subsequence of SEQUENCE.
 They default to 0 and NIL (which means the end of SEQUENCE).
 Elements outside that range are not tested.
If FROM-END is non-NIL, the value is the LAST element in SEQUENCE
 (or specified subsequence) that satisfies the predicate."
  (values (find-1 nil sequence start end nil nil key from-end predicate)))

(defun find-if-not (predicate sequence &key from-end (start 0) end key)
  "Like FIND-IF but looks for an element which does NOT satisfy PREDICATE."
  (values (find-1 nil sequence start end nil t key from-end predicate)))

(defun find (item sequence &key from-end test test-not (start 0) end key)
  "Return first element of SEQUENCE that matches ITEM.
Value is NIL if no element matches.  SEQUENCE can be a list or an array.
TEST is a function of two args to use to compare ITEM against an element (or key).
 An element matches when the TEST function returns non-NIL.
 Alternatively, specify as TEST-NOT a function to use which returns NIL if there is a match.
KEY, if non-NIL, is a function to be applied to each element to get a key,
 which is passed to TEST or TEST-NOT.  If KEY is NIL, the element itself is used.
START and END are indices restricting substitution to a subsequence of SEQUENCE.
 They default to 0 and NIL (which means the end of SEQUENCE).
 Elements outside that range are not tested.
If FROM-END is non-NIL, the value is the LAST element in SEQUENCE
 (or specified subsequence) that matches."
  (values (find-1 item sequence start end (or test-not test) (not (null test-not))
		  key from-end nil)))

(defun find-1 (item sequence &optional (start 0) end
				       test invertp key from-end one-arg-predicate)
  (declare (values item index))
  (if (and from-end (arrayp sequence))
      (do ((index (1- (or end (length sequence))) (1- index))
	   elt)
	  ((< index start)
	   nil)
	(setq elt (if key (funcall key (cli:aref sequence index))
		    (cli:aref sequence index)))
	(when (eq invertp (not (cond (one-arg-predicate
				      (funcall one-arg-predicate elt))
				     (test
				      (funcall test item elt))
				     (t
				      (eql item elt)))))
	  (return (cli:aref sequence index) index)))
      (do ((index (seq-start sequence start))
	   (i start (1+ i))
	   (stop-index (if (consp end) end (seq-end sequence end)))
	   last-pos elt)
	  ((eq index stop-index)
	   (if last-pos (values elt last-pos)))
	(setq elt (key-fetch-inc key sequence index))
	(when (eq invertp (not (cond (one-arg-predicate
				      (funcall one-arg-predicate elt))
				     (test
				      (funcall test item elt))
				     (t
				      (eql item elt)))))
	  (if from-end
	      (setq last-pos i)
	    (return (values (elt sequence i) i)))))))

(defun count-if (predicate sequence &key (start 0) end key)
  "Return number of elements of SEQUENCE (a list or array) that satisfy PREDICATE.
KEY, if non-NIL, is a function to be applied to each element to get a key,
 which is passed to PREDICATE.  If KEY is NIL, the element itself is used.
START and END are indices restricting substitution to a subsequence of SEQUENCE.
 They default to 0 and NIL (which means the end of SEQUENCE).
 Elements outside that range are not counted."
  (count-1 nil sequence start end nil nil key predicate))

(defun count-if-not (predicate sequence &key (start 0) end key)
  "Like COUNT-IF but counts elements that do NOT satisfy PREDICATE."
  (count-1 nil sequence nil t start end key predicate))

(defun count (item sequence &key test test-not (start 0) end key)
  "Return number of elements of SEQUENCE (a list or vector) that match ITEM.
TEST is a function of two args to use to compare ITEM against an element (or key).
 An element matches when the TEST function returns non-NIL.
 Alternatively, specify as TEST-NOT a function to use which returns NIL if there is a match.
KEY, if non-NIL, is a function to be applied to each element to get a key,
 which is passed to TEST or TEST-NOT.  If KEY is NIL, the element itself is used.
START and END are indices restricting substitution to a subsequence of SEQUENCE.
 They default to 0 and NIL (which means the end of SEQUENCE).
 Elements outside that range are not counted."
  (count-1 item sequence start end (or test-not test) (not (null test-not)) key nil))

(defun count-1 (item sequence &optional (start 0) end test invertp key one-arg-predicate)
  (do ((index (seq-start sequence start))
       (count 0)
       (stop-index (seq-end sequence end))
       elt)
      ((eq index stop-index)
       count)
    (setq elt (key-fetch-inc key sequence index))
    (when (eq invertp (not (cond (one-arg-predicate
				  (funcall one-arg-predicate elt))
				 (test
				  (funcall test item elt))
				 (t
				  (eql item elt)))))
      (incf count))))

(defun mismatch (sequence1 sequence2 &key from-end test test-not key
					  (start1 0) end1 (start2 0) end2)
  "Return index in SEQUENCE1 of first mismatch between it and SEQUENCE2.
Elements are compared one by one, starting with elements at indexes START1 and START2
 and stopping when index 1 reaches END1 or index 2 reaches END2.
If sequences match, value is NIL.  If they match until one is exhausted but not both,
 the value is the index in SEQUENCE1 at which one sequence is exhausted.
TEST is a function of two args to use to compare two elements.
 The elements match when the TEST function returns non-NIL.
 Alternatively, specify as TEST-NOT a function to use which returns NIL if there is a match.
KEY, if non-NIL, is a function to be applied to each element to get a key,
 which is passed to TEST or TEST-NOT.  If KEY is NIL, the element itself is used.
FROM-END non-NIL means comparison aligns right ends of the specified
 subsequences and returns one plus the index of the rightmost mismatch."
  (mismatch-1 sequence1 sequence2 start1 end1 start2 end2
	      (or test-not test) (not (null test-not)) key from-end))

(defun mismatch-1 (sequence1 sequence2
		   &optional (start1 0) end1 (start2 0) end2 test invertp key from-end)
  (or end1 (setq end1 (length sequence1)))
  (or end2 (setq end2 (length sequence2)))
  (if from-end
      (funcall (if (and (arrayp sequence1) (arrayp sequence2))
		   #'mismatch-arrays-from-end
	           #'mismatch-sequences-from-end)
	       sequence1 sequence2 start1 end1 start2 end2 test invertp key)
    (or test (setq test #'eql))
    (do ((index1 (seq-start sequence1 start1))
	 (index2 (seq-start sequence2 start2))
	 (i start1 (1+ i))
	 (stop1 (seq-end sequence1 end1))
	 (stop2 (seq-end sequence2 end2)))
	((or (eq index1 stop1) (eq index2 stop2))
	 (unless (and (eq index1 stop1) (eq index2 stop2))
	   i))
      (unless (eq invertp (not (funcall test (key-fetch-inc key sequence1 index1)
					     (key-fetch-inc key sequence2 index2))))
	(return i)))))

(defun mismatch-arrays-from-end (sequence1 sequence2 start1 end1 start2 end2
				 test invertp key)
  (or test (setq test #'eql))
  (do ((index1 (1- end1) (1- index1))
       (index2 (1- end2) (1- index2)))
      ((or (< index1 start1) (< index2 start2))
       (unless (and (< index1 start1) (< index2 start2))
	 (1+ index1)))
    (unless (eq invertp (not (funcall test (progn (%push (cli:aref sequence1 index1))
						  (if key (funcall key (%pop)) (%pop)))
					   (progn (%push (cli:aref sequence2 index2))
						  (if key (funcall key (%pop)) (%pop))))))
      (return (1+ index1)))))

(defun mismatch-sequences-from-end (sequence1 sequence2 start1 end1 start2 end2
				    test invertp key)
  (or test (setq test #'eql))
  (let ((compare-length (min (- end1 start1) (- end2 start2))))
    (do ((index1 (seq-start sequence1 (- end1 compare-length)))
	 (index2 (seq-start sequence2 (- end2 compare-length)))
	 (i (- end1 compare-length) (1+ i))
	 (last-mismatch-index1 (unless (= (- end1 start1) (- end2 start2))
				 (- end1 compare-length))))
	((= i compare-length)
	 last-mismatch-index1)
      (unless (eq invertp (not (funcall test (key-fetch-inc key sequence1 index1)
					     (key-fetch-inc key sequence2 index2))))
	(setq last-mismatch-index1 (1+ i))))))


(defun search (for-sequence-1 in-sequence-2 &key (start1 0) end1 (start2 0) end2
						 from-end test test-not key)
  "Return index in IN-SEQUENCE-2 of first subsequence that matches FOR-SEQUENCE-1.
If no occurrence is found, the value is NIL.
MISMATCH is used to do the matching, with TEST, TEST-NOT and KEY passed along.
START1 and END1 are indices specifying a subsequence of FOR-SEQUENCE-1 to search for.
 The rest of FOR-SEQUENCE-1 might as well not be there.
START2 and END2 are indices specifying a subsequence of IN-SEQUENCE-2 to search through.
 However, the value returned is an index into the entire IN-SEQUENCE-2.
If FROM-END is non-NIL, the value is the index of the LAST subsequence that
 matches FOR-SEQUENCE-1 or the specified part of it.
In either case, the value returned is the index of the beginning of
 the subsequence (of IN-SEQUENCE-2) that matches."
  (let* ((length1 (- (or end1 (length for-sequence-1)) start1))
	 (really-backwards (and from-end (arrayp in-sequence-2)))
	 (pretend-backwards (and from-end (not (arrayp in-sequence-2))))
	 (real-end2 (- (or end2 (length in-sequence-2)) length1 -1))
	 (test (or test-not test #'eql))
	 (invertp (not (null test-not))))
    ;; If REALLY-BACKWARDS, we actually step backwards thru IN-SEQUENCE-2.
    ;; If PRETEND-BACKWARDS, we step forwards but remember the last thing we found.
    (do ((index (seq-start in-sequence-2 start2))
	 (inc (if really-backwards -1 1))
	 (i (if really-backwards (1- real-end2) start2)
	    (+ i inc))
	 last-index-if-from-end
	 (stop-index (if really-backwards (1- start2) (seq-end in-sequence-2 real-end2)))
	 (start-key-1 (key-fetch key for-sequence-1 (seq-start for-sequence-1 start1))))
	((eq index stop-index)
	 last-index-if-from-end)
      (if really-backwards (setq index i))
      (and (eq invertp (not (funcall test start-key-1
				     (key-fetch-inc key in-sequence-2 index))))
	   (not (mismatch-1 for-sequence-1 in-sequence-2 start1 end1 i (+ i length1)
			    test invertp key nil))
	   (if pretend-backwards
	       (setq last-index-if-from-end i)
	     (return i))))))

(defun bit-and (bit-array1 bit-array2 &optional result-bit-array)
  "Returns the bitwise AND of all the two bit arrays,
The result is stored into RESULT-BIT-ARRAY, or returned as a new bit array
if RESULT-BIT-ARRAY is NIL.  If it is T, BIT-ARRAY1 is used for the result."
  (unless result-bit-array
    (if (eq result-bit-array t)
	(setq result-bit-array bit-array1)
      (setq result-bit-array (copy-object bit-array1))))
  (bit-array-logical-op boole-and bit-array1 bit-array2 result-bit-array)
  result-bit-array)

(defun bit-ior (bit-array1 bit-array2 &optional result-bit-array)
  "Returns the bitwise OR of all the two bit arrays,
The result is stored into RESULT-BIT-ARRAY, or returned as a new bit array
if RESULT-BIT-ARRAY is NIL.  If it is T, BIT-ARRAY1 is used for the result."
  (unless result-bit-array
    (if (eq result-bit-array t)
	(setq result-bit-array bit-array1)
      (setq result-bit-array (copy-object bit-array1))))
  (bit-array-logical-op boole-ior bit-array1 bit-array2 result-bit-array)
  result-bit-array)

(defun bit-xor (bit-array1 bit-array2 &optional result-bit-array)
  "Returns the bitwise XOR of all the two bit arrays,
The result is stored into RESULT-BIT-ARRAY, or returned as a new bit array
if RESULT-BIT-ARRAY is NIL.  If it is T, BIT-ARRAY1 is used for the result."
  (unless result-bit-array
    (if (eq result-bit-array t)
	(setq result-bit-array bit-array1)
      (setq result-bit-array (copy-object bit-array1))))
  (bit-array-logical-op boole-xor bit-array1 bit-array2 result-bit-array)
  result-bit-array)

(defun bit-eqv (bit-array1 bit-array2 &optional result-bit-array)
  "Returns the bitwise EQV of all the two bit arrays,
The result is stored into RESULT-BIT-ARRAY, or returned as a new bit array
if RESULT-BIT-ARRAY is NIL.  If it is T, BIT-ARRAY1 is used for the result."
  (unless result-bit-array
    (if (eq result-bit-array t)
	(setq result-bit-array bit-array1)
        (setq result-bit-array (copy-object bit-array1))))
  (bit-array-logical-op boole-eqv bit-array1 bit-array2 result-bit-array)
  result-bit-array)

(defun bit-nand (bit-array1 bit-array2 &optional result-bit-array)
  "Returns the bitwise NAND of all the two bit arrays,
The result is stored into RESULT-BIT-ARRAY, or returned as a new bit array
if RESULT-BIT-ARRAY is NIL.  If it is T, BIT-ARRAY1 is used for the result."
  (unless result-bit-array
    (if (eq result-bit-array t)
	(setq result-bit-array bit-array1)
        (setq result-bit-array (copy-object bit-array1))))
  (bit-array-logical-op boole-nand bit-array1 bit-array2 result-bit-array)
  result-bit-array)

(defun bit-nor (bit-array1 bit-array2 &optional result-bit-array)
  "Returns the bitwise NOR of all the two bit arrays,
The result is stored into RESULT-BIT-ARRAY, or returned as a new bit array
if RESULT-BIT-ARRAY is NIL.  If it is T, BIT-ARRAY1 is used for the result."
  (unless result-bit-array
    (if (eq result-bit-array t)
	(setq result-bit-array bit-array1)
        (setq result-bit-array (copy-object bit-array1))))
  (bit-array-logical-op boole-nor bit-array1 bit-array2 result-bit-array)
  result-bit-array)

(defun bit-andc1 (bit-array1 bit-array2 &optional result-bit-array)
  "Returns the bitwise AND of BIT-ARRAY2 with the complement of BIT-ARRAY1.
The result is stored into RESULT-BIT-ARRAY, or returned as a new bit array
if RESULT-BIT-ARRAY is NIL.  If it is T, BIT-ARRAY1 is used for the result."
  (unless result-bit-array
    (if (eq result-bit-array t)
	(setq result-bit-array bit-array1)
        (setq result-bit-array (copy-object bit-array1))))
  (bit-array-logical-op boole-andc1 bit-array1 bit-array2 result-bit-array)
  result-bit-array)

(defun bit-andc2 (bit-array1 bit-array2 &optional result-bit-array)
  "Returns the bitwise AND of BIT-ARRAY1 with the complement of BIT-ARRAY2.
The result is stored into RESULT-BIT-ARRAY, or returned as a new bit array
if RESULT-BIT-ARRAY is NIL.  If it is T, BIT-ARRAY1 is used for the result."
  (unless result-bit-array
    (if (eq result-bit-array t)
	(setq result-bit-array bit-array1)
        (setq result-bit-array (copy-object bit-array1))))
  (bit-array-logical-op boole-andc2 bit-array1 bit-array2 result-bit-array)
  result-bit-array)

(defun bit-orc1 (bit-array1 bit-array2 &optional result-bit-array)
  "Returns the bitwise OR of BIT-ARRAY2 with the complement of BIT-ARRAY1.
The result is stored into RESULT-BIT-ARRAY, or returned as a new bit array
if RESULT-BIT-ARRAY is NIL.  If it is T, BIT-ARRAY1 is used for the result."
  (unless result-bit-array
    (if (eq result-bit-array t)
	(setq result-bit-array bit-array1)
        (setq result-bit-array (copy-object bit-array1))))
  (bit-array-logical-op boole-orc1 bit-array1 bit-array2 result-bit-array)
  result-bit-array)

(defun bit-orc2 (bit-array1 bit-array2 &optional result-bit-array)
  "Returns the bitwise OR of BIT-ARRAY1 with the complement of BIT-ARRAY2.
The result is stored into RESULT-BIT-ARRAY, or returned as a new bit array
if RESULT-BIT-ARRAY is NIL.  If it is T, BIT-ARRAY1 is used for the result."
  (unless result-bit-array
    (if (eq result-bit-array t)
	(setq result-bit-array bit-array1)
        (setq result-bit-array (copy-object bit-array1))))
  (bit-array-logical-op boole-orc2 bit-array1 bit-array2 result-bit-array)
  result-bit-array)

;Could be microcoded and made far faster, if anyone ever cares.
(defun bit-array-logical-op (alu-function bv1 bv2 bv-out)
  (dotimes (i (array-length bv-out))
    (setf (ar-1-force bv-out i)
	  (boole alu-function (ar-1-force bv1 i) (ar-1-force bv2 i))))
  bv-out)

(defun bit-not (bit-array &optional result-bit-array)
  "Returns a bit array containing the complements of the elements of BIT-ARRAY."
  (unless result-bit-array
    (if (eq result-bit-array t)
	(setq result-bit-array bit-array)
        (setq result-bit-array (copy-object bit-array))))
  (dotimes (i (array-length bit-array))
    (setf (ar-1-force result-bit-array i) (lognot (ar-1-force bit-array i))))
  result-bit-array)

(defun cli:subst (new old tree &key test test-not key)
  "Replace with NEW every atom or subtree in TREE which matches OLD.
List structure is copied as necessary so that the original TREE is not modified.
KEY, if non-NIL, is a function applied to each element to get the
 object to match against.  If KEY is NIL, the element itself is used.
TEST is a function passed OLD and the element (or its key).
 There is a match if TEST returns non-NIL.  TEST defaults to EQL.
Alternatively, pass TEST-NOT, a function to return NIL when there is a match."
  (subst-1 new old tree (or test-not test) (not (null test-not)) key nil))

(defun subst-if (new predicate tree &key key)
  "Replace with NEW every atom or subtree in TREE which satisfies PREDICATE.
List structure is copied as necessary so that the original TREE is not modified.
KEY, if non-NIL, is a function applied to each element to get the
 object to match against.  If KEY is NIL, the element itself is used."
  (subst-1 new nil tree nil nil key predicate))

(defun subst-if-not (new predicate tree &key key)
  "Replace with NEW every atom or subtree in TREE which doesn't satisfy PREDICATE.
List structure is copied as necessary so that the original TREE is not modified.
KEY, if non-NIL, is a function applied to each element to get the
 object to match against.  If KEY is NIL, the element itself is used."
  (subst-1 new nil tree nil t key predicate))

(defun subst-1 (new old tree &optional test invertp key one-arg-predicate)
  (cond ((let ((elt (if key (funcall key tree) tree)))
	   (eq invertp (not (cond (one-arg-predicate (funcall one-arg-predicate elt))
				  (test (funcall test old elt))
				  (t (eql old elt))))))
	 new)
	((atom tree)
	 tree)
	(t
	 (let ((newcar (subst-1 new old (car tree) test invertp key one-arg-predicate))
	       (newcdr (subst-1 new old (cdr tree) test invertp key one-arg-predicate)))
	   (if (and (eql newcar (car tree))
		    (eql newcdr (cdr tree)))
	       tree
	     (cons newcar newcdr))))))

(defun nsubst (new old tree &key test test-not key)
  "Destructively replace with NEW every atom or subtree in TREE which matches OLD.
KEY, if non-NIL, is a function applied to each element to get the
 object to match against.  If KEY is NIL, the element itself is used.
TEST is a function passed OLD and the element (or its key).
 There is a match if TEST returns non-NIL.  TEST defaults to EQL.
Alternatively, pass TEST-NOT, a function to return NIL when there is a match."
  (if (and (null test-not) (null key) (or (null key) (eq key 'eql) (eq key #'eql)))
      (nsubst-eql new old tree)
    (nsubst-1 new old tree (or test-not test) (not (null test-not)) key nil)))

(defun nsubst-if (new predicate tree &key key)
  "Destructively replace with NEW every atom or subtree in TREE which satisfies PREDICATE.
KEY, if non-NIL, is a function applied to each element to get the
 object to match against.  If KEY is NIL, the element itself is used."
  (nsubst-1 new nil tree nil nil key predicate))

(defun nsubst-if-not (new predicate tree &key key)
  "Destructively replace with NEW every atom or subtree in TREE not satisfying PREDICATE.
KEY, if non-NIL, is a function applied to each element to get the
 object to match against.  If KEY is NIL, the element itself is used."
  (nsubst-1 new nil tree nil t key predicate))

(defun nsubst-eql (new old s-exp)
  (cond ((eql old s-exp) new)
	((atom s-exp) s-exp)
	(t (do ((s s-exp (cdr s))
		(prev nil s))
	       ((atom s)
		(when (eql old s)
		  (setf (cdr prev) new)))
	     (if (atom (car s))
		 (when (eql old (car s))
		   (setf (car s) new))
	       (setf (car s) (nsubst-eql new old (car s)))))
	   s-exp)))

(defun nsubst-1 (new old tree &optional test invertp key one-arg-predicate)
  (cond ((let ((elt (if key (funcall key tree) tree)))
	   (eq invertp (not (cond (one-arg-predicate (funcall one-arg-predicate elt))
				  (test (funcall test old elt))
				  (t (eql old elt))))))
	 new)
	((atom tree)
	 tree)
	(t
	 (do ((tail tree (cdr tail)))
	     (())
	   (setf (car tail) (nsubst-1 new old (car tail) test invertp key one-arg-predicate))
	   (when (atom (cdr tail))
	     (let ((newcdr (nsubst-1 new old (cdr tail) test invertp key one-arg-predicate)))
	       ;; Avoid a RPLACD that could de-cdr-code the list, if it's not needed.
	       (unless (eq (cdr tail) newcdr)
		 (setf (cdr tail) newcdr)))
	     (return tree))))))

(defun cli:member (item list &key test test-not key)
  "Return a tail of LIST whose car is the first element of LIST that matches ITEM.
KEY, if non-NIL, is a function applied to each element to get the
 object to match against.  If KEY is NIL, the element itself is used.
TEST is a function passed ITEM and the element (or its key).
 There is a match if TEST returns non-NIL.  TEST defaults to EQL.
Alternatively, pass TEST-NOT, a function to return NIL when there is a match."
  ;; Use MEMQ whenever that will work, since it is microcoded.
  (block member
    (when (and (null key)
	       (null test-not))
      (cond ((or (eq test 'eq) (eq test #'eq))
	     (return-from member (memq item list)))
	    ((or (null test) (eq test 'eql) (eq test #'eql))
	     (return-from member (sys:member-eql item list)))))
    (do ((tail list (cdr tail)))
	((null tail))
      (let ((elt (if key (funcall key (car tail)) (car tail))))
	(if (cond (test-not (not (funcall test-not item elt)))
		  (test (funcall test item elt))
		  (t (eql item elt)))
	    (return tail))))))

(defun member-1 (item list &optional test test-not key)
  ;; Use MEMQ or MEMBER-EQL whenever they will work, since they are microcoded.
  (when (and (null key)
	     (null test-not))
    (cond ((or (eq test 'eq) (eq test #'eq))
	   (return-from member-1 (memq item list)))
	  ((or (null test) (eq test 'eql) (eq test #'eql))
	   (return-from member-1 (sys:member-eql item list)))))
  (do ((tail list (cdr tail)))
      ((null tail))
    (let ((elt (if key (funcall key (car tail)) (car tail))))
      (if (cond (test-not (not (funcall test-not item elt)))
		(test (funcall test item elt))
		(t (eql item elt)))
	  (return tail)))))

(defun member-if (predicate list &key key)
  "Return a tail of LIST whose car is the first element of LIST that satisfies PREDICATE."
  (do ((tail list (cdr tail)))
      ((null tail))
    (if (funcall predicate (if key (funcall key (car tail)) (car tail)))
	(return tail))))

(defun member-if-not (predicate list &key key)
  "Return a tail of LIST whose car is the first element that doesn't satisfy PREDICATE."
  (do ((tail list (cdr tail)))
      ((null tail))
    (unless (funcall predicate (if key (funcall key (car tail)) (car tail)))
      (return tail))))

(defun cli:assoc (item list &key test test-not)
  "Returns the first element of LIST whose car matches ITEM, or NIL if none.
TEST is a function used to compare ITEM with each car;
 they match if it returns non-NIL.  TEST defaults to EQL.
Alternatively, specify TEST-NOT, a function which returns NIL for a match."
  ;; Use ASSQ whenever that will work, since it is microcoded.
  (block assoc
    (if (or (eq test 'eq) (eq test #'eq)
	    (and (null test) (null test-not)
		 (typep item '(or fixnum short-float (not number)))))
	(assq item list)
      (do ((tail list (cdr tail)))
	  ((null tail))
	(when (car tail)
	  (if (cond (test-not (not (funcall test-not item (caar tail))))
		    (test (funcall test item (caar tail)))
		    (t (eql item (caar tail))))
	      (return (car tail))))))))

(defun assoc-1 (item list &optional test test-not)
  ;; Use ASSQ whenever that will work, since it is microcoded.
  (if (or (eq test 'eq) (eq test #'eq)
	  (and (null test) (null test-not)
	       (typep item '(or fixnum short-float (not number)))))
      (assq item list)
    (do ((tail list (cdr tail)))
	((null tail))
      (when (car tail)
	(if (cond (test-not (not (funcall test-not item (caar tail))))
		  (test (funcall test item (caar tail)))
		  (t (eql item (caar tail))))
	    (return (car tail)))))))

(defun assoc-if (predicate list)
  "Returns the first element of LIST whose car satisfies PREDICATE, or NIL if none."
  (do ((tail list (cdr tail)))
      ((null tail))
    (and (car tail)
	 (funcall predicate (caar tail))
	 (return (car tail)))))

(defun assoc-if-not (predicate list)
  "Returns the first element of LIST whose car does not satisfy PREDICATE, or NIL if none."
  (do ((tail list (cdr tail)))
      ((null tail))
    (and (car tail)
	 (not (funcall predicate (caar tail)))
	 (return (car tail)))))

(defun cli:rassoc (item list &key test test-not)
  "Returns the first element of LIST whose cdr matches ITEM, or NIL if none.
TEST is a function used to compare ITEM with each cdr;
 they match if it returns non-NIL.  TEST defaults to EQL.
Alternatively, specify TEST-NOT, a function which returns NIL for a match."
  (block rassoc
    ;; Use RASSQ whenever that will work, since it is microcoded.
    (if (or (eq test 'eq) (eq test #'eq)
	    (and (null test) (null test-not)
		 (typep item '(or fixnum short-float (not number)))))
	(rassq item list)
      (do ((tail list (cdr tail)))
	  ((null tail))
	(when (car tail)
	  (if (cond (test-not (not (funcall test-not item (cdar tail))))
		    (test (not (funcall test item (cdar tail))))
		    (t (eql item (cdar tail))))
	      (return (car tail))))))))

(defun rassoc-1 (item list &optional test test-not)
  ;; Use RASSQ whenever that will work, since it is microcoded.
  (if (and (null test-not)
	   (or (eq test 'eq) (eq test #'eq)
	       (and (or (null test) (eq test 'eql) (eq test #'eql))
		    (typep item '(or fixnum short-float (not number))))))
      (rassq item list)
    (setq test (or test-not test)
	  test-not (not (null test-not)))
    (do ((tail list (cdr tail)))
	((null tail))
      (and (car tail)
	   (eq test-not
	       (not (if test (funcall test item (cdar tail)) (eql item (cdar tail)))))
	   (return (car tail))))))

(defun rassoc-if (predicate list)
  "Returns the first element of LIST whose cdr satisfies PREDICATE, or NIL if none."
  (do ((tail list (cdr tail)))
      ((null tail))
    (and (car tail)
	 (funcall predicate (cdar tail))
	 (return (car tail)))))

(defun rassoc-if-not (predicate list)
  "Returns the first element of LIST whose cdr does not satisfy PREDICATE, or NIL if none."
  (do ((tail list (cdr tail)))
      ((null tail))
    (and (car tail)
	 (not (funcall predicate (cdar tail)))
	 (return (car tail)))))

(defun adjoin (item list &key test test-not key)
  "Return either LIST or (CONS ITEM LIST); the latter if no element of LIST matches ITEM.
KEY, if non-NIL, is a function applied ITEM and to each element of LIST
 to get the objects to match.  If KEY is NIL, ITEM and the element itself are used.
TEST is a function passed ITEM (or its key) and the element (or its key).
 There is a match if TEST returns non-NIL.  TEST defaults to EQL.
Alternatively, pass TEST-NOT, a function to return NIL when there is a match."
  ;; this is probably faster than checking for #'eq, #'eql, etc ourselves
  (if (member-1 (if key (funcall key item) item) list test test-not key)
      list
    (cons item list)))

;(defun copy-list-noncompact (list)
;  (do ((result nil)
;       (tail list (cdr tail)))
;      ((atom tail)
;       (nreconc result tail))
;    (push (car tail) result)))

(defun cli:union (list1 list2 &key test test-not key &aux (result list2))
  "Return the union of LIST1 and LIST2, regarded as sets.
The result is LIST1 plus any elements of LIST2 that match no element of LIST1.
If the first argument has no duplicate elements, neither does the value.
TEST is used to compare two elements; it returns T if they match.
 It defaults to EQL.
 Alternately, specify TEST-NOT, a function to return NIL if they match.
If KEY is non-NIL, it is a function to apply to each element
 to get a key which is then passed to TEST or TEST-NOT instead of the element."
  (block union
    (dolist (x list1)
      (unless (member-1 (if key (funcall key x) x) list2 test test-not key)
	(push x result)))
    result))

(defun cli:nunion (list1 list2 &key test test-not key)
  "Destructively modify LIST1 to be the union of LIST1 and LIST2, regarded as sets.
Any element of LIST that matches no element of LIST1 is NCONC'd at the end of LIST1.
TEST is used to compare two elements; it returns T if they match.
 It defaults to EQL.
 Alternately, specify TEST-NOT, a function to return NIL if they match.
If KEY is non-NIL, it is a function to apply to each element
 to get a key which is then passed to TEST or TEST-NOT instead of the element."
  (block nunion
    (let ((tail (or (last list1) (variable-location list1))))
      (dolist (elt list2)
	(or (member-1 (if key (funcall key elt) elt) list1 test test-not key)
	    (setf (cdr tail) (setq tail (ncons elt))))))
    list1))

(defun cli:intersection (list1 list2 &key test test-not key &aux result)
  "Return the intersection of LIST1 and LIST2, regarded as sets.
Any element of LIST1 which matches some element of LIST2 is included.
If the first argument has no duplicate elements, neither does the value.
TEST is used to compare two elements; it returns T if they match.
 It defaults to EQL.
 Alternately, specify TEST-NOT, a function to return NIL if they match.
If KEY is non-NIL, it is a function to apply to each element
 to get a key which is then passed to TEST or TEST-NOT instead of the element."
  (block intersection
    (dolist (x list1)
      (when (member-1 (if key (funcall key x) x) list2 test test-not key)
	(push x result)))
    result))

(defun cli:nintersection (list1 list2 &key test test-not key)
  "Destructively modify LIST1 to be the intersection of LIST1 and LIST2, regarded as sets.
Any element of LIST1 which fails to match some element of LIST2 is deleted.
TEST is used to compare two elements; it returns T if they match.
 It defaults to EQL.
 Alternately, specify TEST-NOT, a function to return NIL if they match.
If KEY is non-NIL, it is a function to apply to each element
 to get a key which is then passed to TEST or TEST-NOT instead of the element."
  (block nintersection
    (do ((list list1 (cdr list))
	 (result)
	 (old))
	((null list) result)
      (cond ((member-1 (if key (funcall key (car list)) (car list)) list2 test test-not key)
	     (or result (setq result list))
	     (setq old list))
	    (old
	     (setf (cdr old) (cdr list)))))))

(defun set-difference (list1 list2 &key test test-not key &aux result)
  "Return the difference of LIST1 minus LIST2, regarded as sets.
Any element of LIST1 which matches no element of LIST2 is included.
If the first argument has no duplicate elements, neither does the value.
TEST is used to compare two elements; it returns T if they match.
 It defaults to EQL.
 Alternately, specify TEST-NOT, a function to return NIL if they match.
If KEY is non-NIL, it is a function to apply to each element
 to get a key which is then passed to TEST or TEST-NOT instead of the element."
  (dolist (x list1)
    (unless (member-1 (if key (funcall key x) x) list2 test test-not key)
      (push x result)))
  result)
  

(defun nset-difference (list1 list2 &key test test-not key)
  "Destructively modify LIST1 to be the LIST1 minus LIST2, regarded as sets.
Any element of LIST1 which matches an element of LIST2 is deleted.
TEST is used to compare two elements; it returns T if they match.
 It defaults to EQL.
 Alternately, specify TEST-NOT, a function to return NIL if they match.
If KEY is non-NIL, it is a function to apply to each element
 to get a key which is then passed to TEST or TEST-NOT instead of the element."
  (do ((list list1 (cdr list))
       (result)
       (old))
      ((null list) result)
    (cond ((not (member-1 (if key (funcall key (car list)) (car list))
			  list2 test test-not key))
	   (or result (setq result list))
	   (setq old list))
	  (old
	   (setf (cdr old) (cdr list))))))

(defun set-exclusive-or (list1 list2 &key test test-not key &aux result)
  "Return the differences between LIST1 and LIST2, regarded as sets.
Any element of either list which matches nothing in the other list is in the result.
If neither argument has duplicate elements, neither does the value.
TEST is used to compare two elements; it returns T if they match.
 It defaults to EQL.
 Alternately, specify TEST-NOT, a function to return NIL if they match.
If KEY is non-NIL, it is a function to apply to each element
 to get a key which is then passed to TEST or TEST-NOT instead of the element."
  (dolist (x list1)
    (unless (member-1 (if key (funcall key x) x) list2 test test-not key)
      (push x result)))
  (dolist (x list2)
    (unless (member-1 (if key (funcall key x) x) list1 test test-not key)
      (push x result)))
  result)

(defun nset-exclusive-or (list1 list2 &rest rest &key test test-not key)
  "Destructively return the differences between LIST1 and LIST2, regarded as sets.
Any element of either list which matches nothing in the other list is in the result.
If neither argument has duplicate elements, neither does the value.
Both arguments can be chewed up in producing the result.
TEST is used to compare two elements; it returns T if they match.
 It defaults to EQL.
 Alternately, specify TEST-NOT, a function to return NIL if they match.
If KEY is non-NIL, it is a function to apply to each element
 to get a key which is then passed to TEST or TEST-NOT instead of the element."
  (do ((list list1 savecdr)
       (result)
       removed
       savecdr
       (old))
      ((null list)
       (nconc result (apply #'nset-difference list2 removed rest)))
    (setq savecdr (cdr list))
    (cond ((not (member-1 (if key (funcall key (car list)) (car list))
			  list2 test test-not key))
	   (or result (setq result list))
	   (setq old list))
	  (t
	   (if old (setf (cdr old) (cdr list)))
	   (setf (cdr list) removed)
	   (setq removed list)))))

(defun subsetp (list1 list2 &rest rest &key test test-not key)
  "T if every element of LIST1 matches some element of LIST2.
TEST is used to compare two elements; it returns T if they match.
 It defaults to EQL.
 Alternately, specify TEST-NOT, a function to return NIL if they match.
If KEY is non-NIL, it is a function to apply to each element
 to get a key which is then passed to TEST or TEST-NOT instead of the element."
  (do ((list list1 (cdr list)))
      ((null list) t)
    (unless (member-1 (if key (funcall key (car list)) (car list))
		      list2 test test-not key)
      (return nil))))

(defsubst acons (key datum alist)
  "(CONS (CONS KEY DATUM) ALIST). I don't know why this deserves a function of its own."
  (cons (cons key datum) alist))

(defun pairlis (keys data &optional starting-alist)
  "(NCONC (MAPCAR #'CONS KEYS DATA) STARTING-ALIST)"
  (nconc (mapcar #'cons keys data) starting-alist))

;;;; Random commonlisp turds

(defun lisp-implementation-type ()
  "Return the generic name of this Common Lisp implementation."
  "Zetalisp")			;Any lispmachine lisp is zetalisp.  If not, we're in trouble.

(defun lisp-implementation-version ()
  "Return a string that identifies the version of this particular implementation of Lisp."
  (with-output-to-string (version)
    (do ((sys patch-systems-list (cdr sys)))
	((null sys))
      (let ((system (car sys)))
	(format version "~A ~D.~D"
		(patch-name system)
		(patch-version system)
		(version-number (first (patch-version-list system)))))
      (when (cdr sys) (send version :string-out ", ")))))
(deff software-version 'lisp-implementation-version)

(defun machine-type ()
  "Return the generic name for the hardware that we are running on, as a string.
It is /"CADR/" or /"LAMBDA/"."
  (select-processor
    (:cadr "CADR")
    (:lambda "LAMBDA")))

(defun machine-version ()
  "Return a string that identifies which hardware and special microcode we are using."
  (format nil "~A, Microcode ~D" (machine-type) %microcode-version-number))

(defun machine-instance ()
  "Return a string that identifies which particular machine this implementation is."
  disk-pack-name)				;this is pretty much it

(defun software-type ()
  "Return the generic name of the host software, as a string."
  "Zetalisp")

(defun short-site-name ()
  "Return the abbreviated name for this site as a string, or NIL if we don't know it."
  (get-site-option :short-site-name))

(defun long-site-name ()
  "Return the long name for this site as a string, or NIL if we don't know it."
  (get-site-option :long-site-name))
