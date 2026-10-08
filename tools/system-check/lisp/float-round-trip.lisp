;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:10; Readtable:ZL -*-
;;; For the check float-round-trip (tools/system-check/README.md): every
;;; float prints, and its printed text reads back as the same float, bit for
;;; bit.  QUUX's one float is the IEEE 754 single, dtp-small-flonum, bits sign
;;; <31>, biased exponent <30:23>, fraction <22:0> (sys/sys2/numdef.lisp).
;;; Definitions only; the cases call them.  Values are built from bits and
;;; exact integers, never through the printer or the reader under test.

(defun frt-bits (x)
  "X's 32 bits."
  (logand (%pointer x) (1- (ash 1 32.))))

(defun frt-from-bits (bits)
  (single-float-from-bits bits))

(defun frt-decode (x)
  "X's exact value as (M E), M * 2^E with M odd, from its bits; (0 0) for zero."
  (let* ((b (frt-bits x))
	 (field (ldb (byte 8 23.) b))
	 (frac (logand b (1- (ash 1 23.))))
	 (m (if (zerop field) frac (+ frac (ash 1 23.))))
	 (e (if (zerop field) -149. (- field 150.))))
    (if (logbitp 31. b) (setq m (- m)))
    (if (zerop m) (list 0 0)
      (do () ((oddp m) (list m e))
	(setq m (ash m -1) e (1+ e))))))

(defun frt-make (m e)
  "The single M * 2^E, normal or subnormal, built from its bits; NIL when it
is not exactly a finite single."
  (let ((neg (minusp m)) (q (abs m)))
    (do () ((< q (ash 1 24.)))
      (if (oddp q) (return-from frt-make nil))
      (setq q (ash q -1) e (1+ e)))
    (do () ((or (>= q (ash 1 23.)) (<= e -149.)))
      (setq q (ash q 1) e (1- e)))
    (do () ((>= e -149.))
      (if (oddp q) (return-from frt-make nil))
      (setq q (ash q -1) e (1+ e)))
    (let ((field (if (>= q (ash 1 23.)) (+ e 150.) 0)))
      (when (<= field 254.)
	(frt-from-bits (logior (if neg (ash 1 31.) 0)
			       (ash field 23.)
			       (logand q (1- (ash 1 23.)))))))))

(defun frt-nearest (n d)
  "The single nearest N / D (D positive, N not 0), ties to even, subnormals
too; NIL past the largest."
  (let* ((a (abs n))
	 (e (- (integer-length a) (integer-length d) 24.))
	 q r den)
    (do-forever
      (multiple-value-setq (q r)
	(if (minusp e) (floor (ash a (- e)) d) (floor a (ash d e))))
      (cond ((< q (ash 1 23.)) (decf e))
	    ((>= q (ash 1 24.)) (incf e))
	    (t (return nil))))
    (when (< e -149.)
      (setq e -149.)
      (multiple-value-setq (q r) (floor (ash a 149.) d)))
    (setq den (if (minusp e) d (ash d e)))
    (when (or (> (* 2 r) den) (and (= (* 2 r) den) (oddp q)))
      (incf q))
    (and (plusp q) (frt-make (if (minusp n) (- q) q) e))))

(defun frt-text (x)
  (condition-case (err) (prin1-to-string x)
    (error (list 'print-error (send err :report-string)))))

(defun frt-trip (x)
  "NIL when X prints and reads back with X's bits; else (TEXT X's (M E) and
what it read back as, or the error)."
  (let ((s (frt-text x)))
    (if (not (stringp s))
	(list s (frt-decode x))
      (let ((y (condition-case (err) (read-from-string s)
		 (error (list 'read-error (send err :report-string))))))
	(if (and (floatp y) (= (frt-bits x) (frt-bits y)))
	    nil
	  (list s (frt-decode x) (if (floatp y) (frt-decode y) y)))))))

(defvar frt-samples nil)

(defun frt-lcg (seed)
  (logand (+ (* seed 1103515245.) 12345.) (1- (ash 1 31.))))

(defun frt-make-sample (set)
  (selectq set
    (:extremes
     (append (list most-positive-single-float least-positive-single-float
		   most-negative-single-float least-negative-single-float
		   single-float-positive-infinity single-float-negative-infinity)
	     (mapcar #'frt-from-bits '(#x7F7FFFFF #xFF7FFFFF #x00800000 #x80800000
				       #x00800001 #x80800001))
	     (list (frt-make 1 -20.) (frt-make -1 -20.)
		   (frt-nearest (* 602. (expt 10. 21.)) 1) (frt-nearest (- (* 602. (expt 10. 21.))) 1)
		   (frt-nearest 1 (expt 10. 37.)) (frt-nearest -1 (expt 10. 37.)))))
    (:powers-of-2
     (loop for k from -126. to 127.
	   nconc (loop for s in '(1 -1)
		       nconc (loop for (m e) in (list (list s k)
						      (list (* s (1+ (ash 1 23.))) (- k 23.))
						      (list (* s (1- (ash 1 24.))) (- k 24.)))
				   for x = (frt-make m e)
				   when (and x (not (zerop (ldb (byte 8 23.) (frt-bits x)))))
				     collect x))))
    (:powers-of-10
     (loop for k from -37. to 38.
	   nconc (loop for s in '(1 -1)
		       for x = (if (minusp k) (frt-nearest s (expt 10. (- k)))
				 (frt-nearest (* s (expt 10. k)) 1))
		       when x collect x)))
    (:random
     (loop with seed = 196.
	   repeat 3000.
	   for frac = (progn (setq seed (frt-lcg seed)) (logand seed (1- (ash 1 23.))))
	   for neg = (progn (setq seed (frt-lcg seed)) (oddp (ash seed -7)))
	   for field = (progn (setq seed (frt-lcg seed)) (1+ (\ (ash seed -3) 254.)))
	   collect (frt-from-bits (logior (if neg (ash 1 31.) 0) (ash field 23.) frac))))
    ;; subnormals: arithmetic makes none, and the reader underflows below the
    ;; least normal single (float-reading), so they print as a form that
    ;; makes them from their bits
    (:subnormal
     (append (mapcar #'frt-from-bits '(#x00000001 #x00400000 #x007FFFFF #x80000001 #x80400000))
	     (list (frt-nearest 1 (expt 10. 38.)) (frt-nearest -1 (expt 10. 38.))
		   (frt-nearest 1 (expt 10. 45.)))
	     (loop with seed = 1960.
		   repeat 200.
		   for frac = (progn (setq seed (frt-lcg seed)) (1+ (\ seed (1- (ash 1 23.)))))
		   collect (frt-from-bits frac))))))

(defun frt-sample (set)
  (let ((entry (assq set frt-samples)))
    (if entry (cdr entry)
      (let ((l (frt-make-sample set)))
	(push (cons set l) frt-samples)
	l))))

(defun frt-run (set &optional (start 0) end)
  (let ((fails 0) (tried 0) (shown nil))
    (loop for x in (nthcdr start (frt-sample set))
	  for i from start
	  until (and end (>= i end))
	  do (incf tried)
	     (let ((r (frt-trip x)))
	       (when r
		 (incf fails)
		 (if (< (length shown) 3) (push r shown)))))
    (list* fails tried (nreverse shown))))

(defun frt-length (set) (length (frt-sample set)))

(defun frt-epsilon (eps op)
  "T when EPS is the smallest positive single that makes a difference to 1.0
by OP: (OP 1.0 EPS) is not 1.0 and (OP 1.0 P) is, P the single below EPS."
  (let ((p (frt-from-bits (1- (frt-bits eps)))))
    (if (and (not (= (funcall op 1.0 eps) 1.0)) (= (funcall op 1.0 p) 1.0))
	t
      (list (funcall op 1.0 eps) (funcall op 1.0 p)))))
