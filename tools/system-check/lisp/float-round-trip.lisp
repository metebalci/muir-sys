;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:10; Readtable:ZL -*-
;;; For the checks float-round-trip and float-constants
;;; (tools/system-check/README.md): every float prints, and its printed text
;;; reads back as the same float, bit for bit; and the float constants have
;;; the values their definitions state.  Definitions only; the cases call them.
;;; Values are built and taken apart here from their bits and from exact
;;; integers, never through the printer or the reader under test.

;;; The formats (sys/sys2/numdef.lisp).  A short float is its pointer field:
;;; an exponent field of 8 bits, 17.-24., and 17 bits of mantissa, 0.-16.,
;;; whose bit 16 is 1 for a positive float, the mantissa a fraction in
;;; [1/2, 1), and 0 for a negative one, the mantissa then in [-1, -1/2) as
;;; two's complement with the sign bit implied; its value is the signed
;;; mantissa times 2^(field - 128 - 17).  A single float has an exponent
;;; field of 11 bits and a 32-bit two's complement mantissa, normalized the
;;; same way; its value is the mantissa times 2^(field - 1024 - 31).  A field
;;; of 0 is not used by a float other than zero.

(defun frt-bits (x)
  "X's bits: a short float's pointer field, or a single float's exponent field
and 32-bit mantissa as a list."
  (if (typep x 'short-float)
      (logand (%pointer x) (1- (ash 1 25.)))
    (list (%single-float-exponent x) (%single-float-mantissa x))))

(defun frt-decode (x)
  "X's exact value as a list (M E), X = M * 2^E with M odd, from X's bits alone;
(0 0) for zero."
  (if (zerop x)
      (list 0 0)
    (let (m e)
      (if (typep x 'short-float)
	  (let* ((p (logand (%pointer x) (1- (ash 1 25.))))
		 (mm (ldb (byte 17. 0) p)))
	    (setq m (if (ldb-test (byte 1 16.) mm) mm (- mm (ash 1 17.)))
		  e (- (ldb (byte 8 17.) p) 145.)))
	(let ((mm (%single-float-mantissa x)))
	  (setq m (if (ldb-test (byte 1 31.) mm) (- mm (ash 1 32.)) mm)
		e (- (%single-float-exponent x) 1055.))))
      (do () ((oddp m) (list m e))
	(setq m (ash m -1) e (1+ e))))))

(defun frt-odd (m e)
  "M * 2^E as a list (M E) with M odd; (0 0) for zero."
  (if (zerop m)
      (list 0 0)
    (do () ((oddp m) (list m e))
      (setq m (ash m -1) e (1+ e)))))

(defun frt-normalize (m e precision)
  "M and E moved so that M * 2^E is unchanged and M is a normalized mantissa of
PRECISION bits: in [2^(precision-1), 2^precision) when positive, and in
[-2^precision, -2^(precision-1)) when negative.  M must not be 0, nor have
more significant bits than that."
  (do () ((if (plusp m) (< m (ash 1 precision)) (>= m (- (ash 1 precision)))))
    (if (oddp m) (ferror nil "~D has more than ~D bits" m precision))
    (setq m (ash m -1) e (1+ e)))
  (do () ((if (plusp m) (>= m (ash 1 (1- precision))) (< m (- (ash 1 (1- precision))))))
    (setq m (ash m 1) e (1- e)))
  (values m e))

(defun frt-make-short (m e)
  "The short float M * 2^E, built from its bits; NIL when it is out of range."
  (multiple-value-bind (m e) (frt-normalize m e 17.)
    (let ((field (+ e 145.)))
      (when (< 0 field 256.)
	(let ((p (dpb field (byte 8 17.) (ldb (byte 17. 0) m))))
	  (%make-pointer dtp-small-flonum
			 (if (>= p (ash 1 24.)) (- p (ash 1 25.)) p)))))))

(defun frt-make-single (m e)
  "The single float M * 2^E; NIL when it is out of range.  It is made by
SCALE-FLOAT of M floated, which are exact for a mantissa of 31 bits, and its
bits are checked against M and E: a mismatch is an error."
  (multiple-value-bind (m e) (frt-normalize m e 31.)
    (when (< 0 (+ e 1055.) 2048.)
      (let ((x (scale-float (float m) e)))
	(if (equal (frt-decode x) (frt-odd m e))
	    x
	  (ferror nil "SCALE-FLOAT made ~S for ~D * 2^~D" (frt-decode x) m e))))))

(defun frt-make (format m e)
  "The float of FORMAT, :SHORT or :SINGLE, M * 2^E; NIL when it is out of range."
  (if (eq format :short) (frt-make-short m e) (frt-make-single m e)))

(defun frt-precision (format)
  (if (eq format :short) 17. 31.))

(defun frt-nearest (format n d)
  "The float of FORMAT, :SHORT or :SINGLE, nearest to N / D (integers, D positive,
N not 0), ties to an even mantissa; NIL when it is out of range.  Exact integer
arithmetic: the check's own rounding, to build values without the reader."
  (let* ((p (frt-precision format))
	 (a (abs n))
	 (e (- (integer-length a) (integer-length d) p))
	 q r)
    (do-forever
      ;; q = floor (a / (d * 2^e)), r the remainder
      (multiple-value-setq (q r)
	(if (minusp e) (floor (ash a (- e)) d) (floor a (ash d e))))
      (cond ((< q (ash 1 (1- p))) (decf e))
	    ((>= q (ash 1 p)) (incf e))
	    (t (return nil))))
    (let ((den (if (minusp e) d (ash d e))))
      (when (or (> (* 2 r) den) (and (= (* 2 r) den) (oddp q)))
	(incf q)))
    (frt-make format (if (minusp n) (- q) q) e)))

(defun frt-text (x)
  "X printed, or the error's message when printing signals."
  (condition-case (err) (prin1-to-string x)
    (error (list 'print-error (send err :report-string)))))

(defun frt-trip (x)
  "NIL when X prints and the printed text reads back as a float of X's format
with X's bits; else a list of the text, X's value as (M E) for M * 2^E, and
what the text read back as, its value likewise, or the error's message."
  (let ((s (frt-text x)))
    (if (not (stringp s))
	(list s (frt-decode x))
      (let ((y (condition-case (err) (read-from-string s)
		 (error (list 'read-error (send err :report-string))))))
	(if (and (floatp y)
		 (eq (typep x 'short-float) (typep y 'short-float))
		 (equal (frt-bits x) (frt-bits y)))
	    nil
	  (list s (frt-decode x) (if (floatp y) (frt-decode y) y)))))))

;;; The samples, each a list of floats, made once and kept.

(defvar frt-samples nil "An alist of (FORMAT SET) to its list of floats.")

(defun frt-pairs-floats (format pairs)
  "The floats of FORMAT for each (M E) of PAIRS that is in range."
  (loop for (m e) in pairs
	for x = (frt-make format m e)
	when x collect x))

(defun frt-make-sample (format set &aux (p (frt-precision format))
			(kind (if (consp set) (car set) set))
			(args (if (consp set) (cdr set))))
  ;; SET is a keyword, or a list of one and its arguments: (:POWERS-OF-2 EVERY
  ;; NEIGHBOURS-EVERY) takes 2^k only for every EVERY-th k (default 1) and the
  ;; floats beside it for every NEIGHBOURS-EVERY-th (default 8), the ends of
  ;; the range always; (:POWERS-OF-10 EVERY) every EVERY-th k (default 1)
  (selectq kind
    ;; the extremes of each sign, the constants as the system has them, and
    ;; the floats the faults were first seen with
    (:extremes
     (append
       (if (eq format :short)
	   (list most-positive-short-float least-positive-short-float
		 most-negative-short-float least-negative-short-float)
	 (list most-positive-single-float least-positive-single-float
	       most-negative-single-float least-negative-single-float))
       (frt-pairs-floats format
	 (list (list (1- (ash 1 p)) (if (eq format :short) 110. 992.))	;most positive
	       (list (- (1- (ash 1 p))) (if (eq format :short) 110. 992.))
	       (list -1 (if (eq format :short) 127. 1023.))		;most negative
	       (list 1 (if (eq format :short) -128. -1024.))		;least positive
	       (list (- (1+ (ash 1 (1- p)))) (if (eq format :short) -144. -1054.)) ;least negative
	       (list (1+ (ash 1 (1- p))) (if (eq format :short) -144. -1054.))	;the one above least positive
	       (list (- (+ (ash 1 (1- p)) 2)) (if (eq format :short) -144. -1054.))))
       (if (eq format :short)
	   (list (frt-make :short 1 -20.) (frt-make :short 1 -127.)
		 (frt-make :short -1 -20.) (frt-make :short -1 -127.)
		 (frt-nearest :short 602. 1000.) (frt-nearest :short 1 1000.))
	 (list (frt-nearest :single (* 602. (expt 10. 21.)) 1)
	       (frt-nearest :single (- (* 602. (expt 10. 21.))) 1)
	       (frt-nearest :single 1 (expt 10. 307.))
	       (frt-nearest :single -1 (expt 10. 307.))))))
    ;; 2^k of both signs for each k in range, and the floats on each side of
    ;; it for every eighth k and the eight at each end of the range
    (:powers-of-2
     (loop with lo = (if (eq format :short) -129. -1025.)
	   with every = (or (first args) 1)
	   with neighbours-every = (or (second args) 8)
	   for k from lo to (- 1 lo)
	   for at-end = (or (< k (+ lo 9.)) (> k (- -7. lo)))
	   when (or at-end (zerop (\ k every)))
	   nconc (frt-pairs-floats format
		   (loop for s in '(1 -1)
			 nconc (list* (list s k)
				      (and (or at-end (zerop (\ k neighbours-every)))
					   (list (list (* s (1+ (ash 1 (1- p)))) (- k p -1))
						 (list (* s (1- (ash 1 p))) (- k p)))))))))
    ;; the floats nearest 10^k of both signs for each k in range
    (:powers-of-10
     (loop with lo = (if (eq format :short) -40. -310.)
	   with every = (or (first args) 1)
	   for k from lo to (- -1 lo)
	   when (zerop (\ k every))
	   nconc (loop for s in '(1 -1)
		       for x = (if (minusp k) (frt-nearest format s (expt 10. (- k)))
				 (frt-nearest format (* s (expt 10. k)) 1))
		       when x collect x)))
    ;; pseudo-random floats of every exponent and sign, from a seeded LCG
    (:random
     (loop with seed = 196.
	   with fields = (if (eq format :short) 255. 2047.)
	   repeat 3000.
	   for m = (progn (setq seed (frt-lcg seed)) (logand seed (1- (ash 1 (1- p)))))
	   for neg = (progn (setq seed (frt-lcg seed)) (oddp (ash seed -7)))
	   for field = (progn (setq seed (frt-lcg seed)) (1+ (\ (ash seed -3) fields)))
	   collect (frt-make format
			     (if neg (- m (ash 1 p)) (+ m (ash 1 (1- p))))
			     (- field (if (eq format :short) 145. 1055.)))))))

(defun frt-lcg (seed)
  "The next of a linear congruential sequence of 31-bit integers."
  (logand (+ (* seed 1103515245.) 12345.) (1- (ash 1 31.))))

(defun frt-sample (format set)
  (let ((entry (assoc (list format set) frt-samples)))
    (if entry (cdr entry)
      (let ((l (frt-make-sample format set)))
	(push (cons (list format set) l) frt-samples)
	l))))

(defun frt-run (format set &optional (start 0) end)
  "Round trip the floats START to END of the sample SET of FORMAT: a list of the
number of floats that did not come back, the number tried, and up to three of
them as FRT-TRIP describes them."
  (let ((l (nthcdr start (frt-sample format set)))
	(fails 0) (tried 0) (shown nil))
    (loop for x in l
	  for i from start
	  until (and end (>= i end))
	  do (incf tried)
	     (let ((r (frt-trip x)))
	       (when r
		 (incf fails)
		 (if (< (length shown) 3) (push r shown)))))
    (list* fails tried (nreverse shown))))

(defun frt-length (format set)
  (length (frt-sample format set)))

(defun frt-previous (x)
  "The positive float of X's format just below the positive float X."
  (let ((format (if (typep x 'short-float) :short :single)))
    (multiple-value-bind (m e)
	(apply #'frt-normalize (append (frt-decode x) (list (frt-precision format))))
      (if (= m (ash 1 (1- (frt-precision format))))
	  (frt-make format (1- (* 2 m)) (1- e))
	(frt-make format (1- m) e)))))

(defun frt-epsilon (eps op)
  "T when EPS is the smallest positive float of its format that makes a
difference to one of that format by OP, + or -: (OP 1 EPS) is not 1 and
(OP 1 P) is 1 for P, the float just below EPS.  Else a list of those two
results."
  (let ((one (if (typep eps 'short-float) 1.0s0 1.0))
	(p (frt-previous eps)))
    (if (and (not (= (funcall op one eps) one)) (= (funcall op one p) one))
	t
      (list (funcall op one eps) (funcall op one p)))))
