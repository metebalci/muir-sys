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

;;; For the check format-float-digits (tools/system-check/README.md): FORMAT's
;;; ~E and ~G over the same samples.  ~E's digits are to be the printer's,
;;; FLONUM-DIGITS's, the fewest that read back as the float, at most D + 1 of
;;; them under ~,DE, the last rounded to the nearest (a half to the even
;;; digit) and the rest padded with zeros, and its
;;; exponent the power of ten they go with; ~G is to choose between ~F and ~E
;;; by the float's own power of ten, the N with 10^N <= |X| < 10^(N+1).  ~E
;;; and ~G took both from SI::SCALE-FLONUM, which scales X to [1, 10) by
;;; floating multiplication and loses bits.  The references below take the
;;; digits from FLONUM-DIGITS and N from X's bits in integers, never from
;;; SCALE-FLONUM.

(defun ffd-exponent (x)
  "The N with 10^N <= |X| < 10^(N+1), X finite and not zero, from its bits."
  (destructuring-bind (m e) (frt-decode x)
    (let* ((a (abs m))
	   (num (if (minusp e) a (ash a e)))
	   (den (if (minusp e) (ash 1 (- e)) 1))
	   (n (floor (* (+ e (integer-length a) -1) 77.) 256.)))
      (flet ((at-least (n)			;num/den >= 10^n
	       (if (minusp n)
		   (>= (* num (expt 10. (- n))) den)
		 (>= num (* den (expt 10. n))))))
	(do () ((at-least n)) (decf n))
	(do () ((not (at-least (1+ n)))) (incf n))
	n))))

(defun ffd-magnitude (x)
  "|X| from X's bits: ABS signals on a subnormal, as arithmetic makes none."
  (frt-from-bits (logand (frt-bits x) (1- (ash 1 31.)))))

(defun ffd-e-text (x d)
  "What FORMAT's ~E of X, or ~,DE with D, is to give: FLONUM-DIGITS's
digits, D.DDD, at least one after the point, and the exponent of the first,
in as many digits as the exponent of the uncut digits takes (MIT's ~E chooses
the width before the digits round), padded with zeros."
  (multiple-value-bind (digits k) (flonum-digits x (and d (1+ d)))
    (let* ((rest (substring digits 1))
	   (ex (1- k))
	   (e0 (abs (1- (second (multiple-value-list (flonum-digits x))))))
	   (*print-base* 10.) (*print-radix* nil)
	   (etext (princ-to-string (abs ex))))
      (cond (d (setq rest (string-append rest (make-string (- d (length rest))
							   :initial-element #/0))))
	    ((zerop (length rest)) (setq rest "0")))
      (loop while (< (length etext) (cond ((> e0 99.) 3) ((> e0 9) 2) (t 1)))
	    do (setq etext (string-append "0" etext)))
      (string-append (if (minusp x) "-" "") (string (aref digits 0)) "." rest
		     "e" (if (minusp ex) "-" "+") etext))))

(defun ffd-g-text (x d)
  "What FORMAT's ~G of X, or ~,DG with D, is to give, by MIT's rule
in FORMAT-CTL-HAIRY-G-FORMAT with X's own power of ten: ~F with D - N - 1
digits after the point and four spaces when that is between 0 and D, else ~E;
D, when not given, the digits ~F gives X (FLONUM-FIXED-TO-STRING), at least N + 1
up to 7."
  (let* ((n (ffd-exponent x))
	 (ad (or d (max (1- (length (flonum-fixed-to-string x nil nil t)))
			(min (1+ n) 7))))
	 (dd (- ad n 1)))
    (if (<= 0 dd ad)
	(string-append (format nil "~,vF" dd x) "    ")
      (if d (format nil "~,vE" d x) (format nil "~E" x)))))

(defun ffd-format (x kind d)
  (condition-case (err)
      (selectq kind
	(:e (if d (format nil "~,vE" d x) (format nil "~E" x)))
	(:g (if d (format nil "~,vG" d x) (format nil "~G" x))))
    (error (list 'format-error (send err :report-string)))))

(defun ffd-check (x kind d)
  "NIL when FORMAT's KIND (:E or :G) with D gives X as the reference does
and, for ~E of a normal float with no D, its text reads back as X; else
(WHAT-IT-GAVE WHAT-IT-SHOULD X's (M E))."
  (let ((got (ffd-format x kind d))
	(want (condition-case (err)
		  (if (eq kind :e) (ffd-e-text x d) (ffd-g-text x d))
		(error (list 'reference-error (send err :report-string))))))
    (cond ((not (and (stringp got) (equal got want)))
	   (list got want (frt-decode x)))
	  ((and (eq kind :e) (null d)
		(not (zerop (ldb (byte 8 23.) (frt-bits x))))
		(let ((y (condition-case () (read-from-string got) (error nil))))
		  (not (and (floatp y) (= (frt-bits y) (frt-bits x))))))
	   (list got 'does-not-read-back (frt-decode x))))))

(defun ffd-run (kind d set &optional (start 0) end)
  "FORMAT's KIND (:E or :G), with D digits after the point or none, over the
sample SET of float-round-trip, its infinities left out (check format-float):
the number that differ from the reference, the number tried, and up to three."
  (let ((fails 0) (tried 0) (shown nil))
    (loop for x in (nthcdr start (frt-sample set))
	  for i from start
	  until (and end (>= i end))
	  unless (= (ldb (byte 8 23.) (frt-bits x)) 255.)
	    do (incf tried)
	       (let ((r (ffd-check x kind d)))
		 (when r
		   (incf fails)
		   (if (< (length shown) 3) (push r shown)))))
    (list* fails tried (nreverse shown))))

;;; For the check format-float-fixed (tools/system-check/README.md): FORMAT's
;;; ~F, and ~G when it chooses ~F, over the same samples.  Their text, with no
;;; digits asked for, is to read back as the float: a normal one through the
;;; reader, a subnormal one, which the reader takes as an underflow, by its
;;; exact decimal value lying within half a gap of the float.
;;; FLONUM-TO-STRING carried nothing out of its integer part, so ~F of the
;;; single nearest 1e11 printed ":0000000000.0"; and ~F signalled on a
;;; subnormal, as ABS of one does.

(defun fff-format (x kind)
  (condition-case (err)
      (string-trim '(#/space) (selectq kind
				(:f (format nil "~F" x))
				(:g (format nil "~G" x))))
    (error (list 'format-error (send err :report-string)))))

(defun fff-parse (s)
  "S, [-]ddd.ddd with an exponent e[+-]ddd or none, as (N D), its value
N / 10^D; NIL when it is not that."
  (let ((n 0) (d nil) (neg nil) (any nil)
	(e (string-search-char #/e s)))
    (dotimes (i (or e (length s)))
      (let ((c (aref s i)))
	(cond ((and (= i 0) (= c #/-)) (setq neg t))
	      ((and (= c #/.) (null d)) (setq d 0))
	      ((digit-char-p c)
	       (setq n (+ (* n 10.) (digit-char-p c)) any t)
	       (if d (incf d)))
	      (t (return-from fff-parse nil)))))
    (let ((ex (if e (fff-parse-exponent (substring s (1+ e))) 0)))
      (and any ex
	   (let ((dd (- (or d 0) ex)))
	     (if (minusp dd)
		 (list (* (if neg (- n) n) (expt 10. (- dd))) 0)
	       (list (if neg (- n) n) dd)))))))

(defun fff-parse-exponent (s)
  (let ((v 0) (neg nil) (any nil))
    (dotimes (i (length s))
      (let ((c (aref s i)))
	(cond ((and (= i 0) (memq c '(#/+ #/-))) (setq neg (= c #/-)))
	      ((digit-char-p c) (setq v (+ (* v 10.) (digit-char-p c)) any t))
	      (t (return-from fff-parse-exponent nil)))))
    (and any (if neg (- v) v))))

(defun fff-within (x s)
  "T when the decimal text S lies within half a gap of the float X, X's
gap from its bits: 2^(field - 150), or 2^-149 for a subnormal."
  (let ((p (fff-parse s)))
    (when p
      (let* ((b (frt-bits x))
	     (field (ldb (byte 8 23.) b))
	     (sig (+ (logand b (1- (ash 1 23.))) (if (zerop field) 0 (ash 1 23.))))
	     (q (if (zerop field) -149. (- field 150.)))
	     (xs (if (logbitp 31. b) (- sig) sig))
	     (n (first p))
	     (ten (expt 10. (second p))))
	(if (>= q 0)
	    (<= (abs (- (* 2 n) (* 2 xs (ash 1 q) ten))) (* (ash 1 q) ten))
	  (<= (abs (- (* 2 n (ash 1 (- q))) (* 2 xs ten))) ten))))))

(defun fff-check (x kind)
  "NIL when FORMAT's KIND (:F or :G) of X reads back as X; else (TEXT X's (M E))."
  (let ((s (fff-format x kind)))
    (cond ((not (stringp s)) (list s (frt-decode x)))
	  ((zerop (ldb (byte 8 23.) (frt-bits x)))
	   (if (fff-within x s) nil (list s (frt-decode x))))
	  ((let ((y (condition-case () (read-from-string s) (error nil))))
	     (and (floatp y) (= (frt-bits y) (frt-bits x))))
	   nil)
	  (t (list s (frt-decode x))))))

(defun fff-run (kind set &optional (start 0) end)
  "FORMAT's KIND (:F or :G) over the sample SET of float-round-trip, its
infinities left out: the number that do not read back, the number tried, and
up to three."
  (let ((fails 0) (tried 0) (shown nil))
    (loop for x in (nthcdr start (frt-sample set))
	  for i from start
	  until (and end (>= i end))
	  unless (= (ldb (byte 8 23.) (frt-bits x)) 255.)
	    do (incf tried)
	       (let ((r (fff-check x kind)))
		 (when r
		   (incf fails)
		   (if (< (length shown) 3) (push r shown)))))
    (list* fails tried (nreverse shown))))

(defun fff-printer-differ (bits-list)
  "The floats of BITS-LIST that the printer and ~F print with other digits:
(BITS PRIN1 ~F)."
  (loop for b in bits-list
	for x = (frt-from-bits b)
	for p = (prin1-to-string x)
	for f = (format nil "~F" x)
	unless (string-equal p f)
	  collect (list b p f)))

(defun fff-printer-run (set)
  "The floats of the sample SET in [1e-3, 1e7), where the printer prints no
exponent, that the printer and ~F print with other digits: their number and
the number tried."
  (let ((differ 0) (tried 0))
    (dolist (x (frt-sample set))
      (let ((a (ffd-magnitude x))
	    (field (ldb (byte 8 23.) (frt-bits x))))
	(when (and (not (= field 255.)) (not (zerop field)) (>= a 1.0e-3) (< a 1.0e7))
	  (incf tried)
	  (unless (string-equal (prin1-to-string x) (format nil "~F" x))
	    (incf differ)))))
    (list differ tried)))
