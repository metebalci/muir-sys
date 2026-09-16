; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:8; Lowercase:T; Readtable:T -*-

(defun complex (realpart &optional (imagpart 0))
  "Return a complex number with specified real and imaginary parts.
If both realpart imagpart are rational and the imagpart is zero,
then the returned value will not be a complex number, but just realpart."
  (declare (arglist realpart &optional (imagpart (coerce 0 (type-of realpart)))))
  (check-type realpart non-complex-number)
  (check-type imagpart non-complex-number)
  (if (and (eq imagpart 0)				;don't use = or zerop
	   (rationalp realpart))
      realpart
    (%complex-cons (+ realpart (- imagpart imagpart)) (+ imagpart (- realpart realpart)))))

;; ucode
(defun numerator (x)
  "Return the numerator of X, which must be rational.
On integers, this is the identity function."
  (check-type x rational)
  (if (integerp x) x
    (%rational-numerator x)))

;; ucode
(defun denominator (x)
  "Return the denominator of X, which must be rational.
On integers, this returns 1."
  (check-type x rational)
  (if (integerp x) 1
    (%rational-denominator x)))

;; ucode
(defun realpart (x)
  "Return the real part of a complex number.  The real part of a real number is itself."
  (check-type x number)
  (if (complexp x)
      (%complex-real-part x)
    x))

;; ucode
(defun imagpart (x)
  "Return the imaginary part of a complex number, or 0 if given a real number."
  (check-type x number)
  (if (complexp x)
      (%complex-imag-part x)
    (- x x)))

(defun rational (x)
  "Convert X to a rational number.
If X is a floating point number, it is regarded as completely exact."
  (check-type x non-complex-number)
  (if (rationalp x)
      x
    (make-rational-from-float-exact x)))

(defun make-rational-from-float-exact (x &aux minusflag)
  (if (zerop x) 0
    (if (minusp x)
	(setq minusflag t x (- x)))
    (let* ((mant (flonum-mantissa x))
	   (expt (+ (haulong mant) (flonum-exponent x)))
	   (zeros (1- (haulong (logand (- mant) mant))))
	   (denom (ash 1 (- (haulong mant) zeros))))
      (cond ((plusp expt)
	     (setq mant (ash mant (- expt zeros))))
	    ((minusp expt)
	     (setq mant (ash mant (- zeros)))
	     (setq denom (ash denom (- expt))))
	    (t (setq mant (ash mant (- zeros)))))
      (if minusflag (setq mant (- mant)))
      (cli:// mant denom))))

(defun rationalize (x &optional tolerance)
  "Return the simplest rational that approximates X well.
TOLERANCE specifies how much precision of X to regard as valid:
 NIL means all that there is of X,
 a positive integer means that many bits of X,
 a negative integer is minus the number of low bits to ignore,
 a flonum is a ratio: it times X gives the magnitude of uncertainty."
  (check-type x number)
  (typecase x
    (integer x)
    (ratio (if tolerance
	       (make-rational-from-float (float x) single-float-mantissa-length tolerance)
	      x))
    (short-float (make-rational-from-float (float x) short-float-mantissa-length tolerance))
    (float (make-rational-from-float x single-float-mantissa-length tolerance))
    (complex (complex (rationalize (%complex-real-part x) tolerance)
		      (rationalize (%complex-imag-part x) tolerance)))))

(defun make-rational-from-float (x precision tolerance)
  (cond ((null tolerance))
	((floatp tolerance)
	 (setq precision (min 0 (max precision (- (float-exponent tolerance))))))
	((plusp tolerance)
	 (setq precision (min precision tolerance)))
	((minusp tolerance)
	 (setq precision (max 0 (+ precision tolerance)))))	
  ;; Continued fraction expansion. This keeps track of precision.
  ;; It also assumes only loss of precision is in the subtraction, and one in
  ;; the division. This seems to be a good assumption - BEE
  (loop with terms = ()
	with pow2 = (%single-float-exponent x)
	as int-part = (fix x)
	do (progn (push int-part terms)
		  (decf precision (1+ (haulong int-part)))
		  (decf x int-part))
	when (or (zerop x) (> (- pow2 (%single-float-exponent x)) precision))
	do (loop for term in terms
		 with num = 1 and den = 0
		 do (psetq num (+ (* term num) den)
			   den num)
		 finally (return-from make-rational-from-float (cli:// num den)))
	else do (setq x (// x))))


(defun conjugate (number)
  "Return the complex conjugate of NUMBER.  If NUMBER is real, NUMBER is returned."
  (check-type number number)
  (if (complexp number)
      (if (zerop (%complex-imag-part number))
	  number
	(%complex-cons (%complex-real-part number) (- (%complex-imag-part number))))
    number))

(defun phase (number)
  "Return the phase of NUMBER, in radians.
This is the angle in the complex plane from the positive real axis
to the ray from the origin through NUMBER.
It is between - (exclusive) and  (inclusive).
For a positive real, this is 0; for a negative real, this is . For 0, it is zero."
  (check-type number number)
  (if (complexp number)
      (if (zerop number)
	  number
	(cli:atan (%complex-imag-part number) (%complex-real-part number)))
    (if (minusp number)
	(typecase number
	  (short-float #.(coerce pi 'short-float))
	  (t pi))
      (- number number))))

;; need more efficient way to do this than calculate both cos AND sin separately
;; use (cos angle) = (sqrt (1- (sin angle))) ?? Can't be much less accurate.
(defun cis (angle)
  "Return the value of e^(i*ANGLE).  The inverse of the function PHASE."
  (complex (cos angle) (sin angle)))

(defun signum (number)
  "Return a number with the same phase as NUMBER but unit magnitude.
If NUMBER is zero, zero is returned.
For a nonzero non-complex number, the value is either 1 or -1."
  (check-type number number)
  (cond ((zerop number)
	 (zero-of-type number))
	((complexp number)
	 (cli:// number (abs number)))
	(t (+ (if (plusp number) 1 -1) (- number number)))))

(defun print-rational (number stream fastp)
  (and *print-radix*
       (numberp *print-base*)
       (case *print-base*
	 (2
	  (send stream :string-out "#b"))
	 (8
	  (send stream :string-out "#o"))
	 (16.
	  (send stream :string-out "#x"))
	 (t
	  (send stream :tyo #/#)
	  (let ((*print-base* 10.) (*nopoint t) (tem *print-base*))
	    (print-fixnum tem stream))
	  (send stream :tyo #/r))))
  (let ((*nopoint t)
	(*print-radix* nil))
    (let ((n (%rational-numerator number))
	  (d (%rational-denominator number)))
      (if (fixnump n)
	  (print-fixnum n stream)
	(print-bignum n stream fastp))
      (send stream :tyo (pttbl-rational-infix *readtable*))
      (if (fixnump d)
	  (print-fixnum d stream)
	(print-bignum d stream fastp)))))

(defun print-complex (cplx stream ignore)
  (send stream :string-out (first (pttbl-complex *readtable*)))
  (princ (%complex-real-part cplx) stream)
  (if (second (pttbl-complex *readtable*))
      (send stream :string-out (second (pttbl-complex *readtable*)))
    (unless (minusp (%complex-imag-part cplx))
      (send stream :tyo #/+)))
  (princ (%complex-imag-part cplx) stream)
  (send stream :string-out (third (pttbl-complex *readtable*))))

(defun (rational standard-read-function) (stream string &aux num i
					     (len (string-length string)))
   stream
   (multiple-value (num i)
     (xr-read-fixnum-internal string 0 len))
   (values
     (cli:// num (xr-read-fixnum-internal string (1+ i) len))
     'rational))

(defun (complex standard-read-function) (stream string &aux complex-start (zero 0))
  stream
  (do ((i 1 (1+ i)))
      ((= i (length string)))
    (when (and (memq (char string i) '(#/+ #/-))
	       (not (alpha-char-p (char string (1- i)))))
      (return (setq complex-start i))))
  (values
    (complex
      (cond (complex-start (with-input-from-string (strm string zero complex-start)
			     (xr-read-thing strm)))
	    (t (setq complex-start 0)))
      (with-input-from-string (strm string complex-start (1- (string-length string)))
	(xr-read-thing strm)))
    'complex))

;;;; Standard arithmetic functions.

(defun numeric-one-argument (code number)
  (unless (eq (%data-type number) dtp-extended-number)
    (ferror nil "Trap to macrocode for arithmetic on ~S" number))
  (selectq (%p-ldb-offset %%header-type-field number 0)
    ('#,%header-type-rational
     (let ((num (%rational-numerator number))
	   (den (%rational-denominator number)))
       (selectq (logand #o77 code)
	 (0 (if ( num 0)							;ABS
		number
	      (%ratio-cons (abs num) den)))
	 (1 (%ratio-cons (- num) den))						;MINUS
	 (2 (= num 0))								;ZEROP
	 (3 (> num 0))								;PLUSP
	 (4 (< num 0))								;MINUSP
	 (5 (%ratio-cons (+ num den) den))					;ADD1
	 (6 (%ratio-cons (- num den) den))					;SUB1
	 (7									;"FIX"
	  (selectq (ldb #o0603 code)
	    (0 (if (plusp num) (truncate num den)				; FLOOR
		 (truncate (- num den -1) den)))
	    (1 (if (minusp num) (truncate num den)				; CEILING
		 (truncate (+ num den -1) den)))
	    (2 (truncate num den))						; TRUNCATE
	    (3									; ROUND
	     (let* ((floor (if (plusp num) (truncate num den)
			     (truncate (- num den -1) den)))
		    (fraction-num (- num (* floor den)))
		    (half-indicator (- (+ fraction-num fraction-num) den)))
	       (if (or (plusp half-indicator)
		       (and (zerop half-indicator)
			    (oddp floor)))
		   (1+ floor)
		 floor)))))
	 (8   (// (float num) (float den)))					;FLOAT
	 (9   (// (small-float num) (small-float den)))				;SMALL-FLOAT
	 (10. (ferror nil "Illegal operation /"HAULONG/" on ~S" number))
	 (11. (ferror nil "Illegal operation /"LDB/" on ~S" number))
	 (12. (ferror nil "Illegal operation /"DPB/" on ~S" number))
	 (13. (ferror nil "Illegal operation /"ASH/" on ~S" number))
	 (14. (ferror nil "Illegal operation /"ODDP/" on ~S" number))
	 (15. (ferror nil "Illegal operation /"EVENP/" on ~S" number))
	 (t (ferror nil "Arith one-arg op code ~D on ~S" code number)))))
    ('#,%header-type-complex
     (let ((real (%complex-real-part number))
	   (imag (%complex-imag-part number)))
       (selectq code
	 (0									;ABS
	    (let ((min (min (abs real) (abs imag)))
		  (max (max (abs real) (abs imag)))
		  tem			    
		  (zunderflow t))
	      (if (rationalp max) (setq max (float max)))
	      (setq tem (// min max))
	      (* (sqrt (+ (* tem tem) 1)) max)))				;ABS
	 (1 (%complex-cons (- real) (- imag)))					;MINUS
	 (2 (and (zerop real) (zerop imag)))					;ZEROP
	 (3 (ferror nil "PLUSP applied to the complex number ~S" number))	;PLUSP
	 (4 (ferror nil "MINUSP applied to the complex number ~S" number))	;MINUSP
	 (5 (%complex-cons (1+ real) imag))					;ADD1
	 (6 (%complex-cons (1- real) imag))					;SUB1
;;; is it a good idea for the following three to work? I don't think so. Mly
	 (7 (%complex (fix real) (fix imag)))					;FIX
	 (8 (%complex-cons (float real) (float imag)))				;FLOAT
	 (9 (%complex-cons (small-float real) (small-float imag)))		;SMALL-FLOAT
	 (10. (ferror nil "Illegal operation /"HAULONG/" on ~S" number))
	 (11. (ferror nil "Illegal operation /"LDB/" on ~S" number))
	 (12. (ferror nil "Illegal operation /"DPB/" on ~S" number))
	 (13. (ferror nil "Illegal operation /"ASH/" on ~S" number))
	 (14. (and (zerop imag) (oddp real)))					;ODDP
	 (15. (and (zerop imag) (evenp real)))					;EVENP
	 (t (ferror nil "Arith one-arg op code ~D on ~S" code number)))))
    (t (ferror nil "Trap to macrocode for arithmetic on number ~S" number))))

(defun numeric-two-arguments (code number1 number2 &aux function)
  (setq function (nth code '(#,(function *plus)
			     #,(function *dif)
			     #,(function *times)
			     #,(function *quo)
			     #,(function internal-=)
			     #,(function internal->)
			     #,(function internal-<)
			     #,(function *min)
			     #,(function *max)
			     #,(function *boole)
			     #,(function %div))))
  (cond ((and (complexp number1) (complexp number2))
	 (complex-two-arguments code number1 number2))
	((complexp number1)
	 (complex-two-arguments code number1 (%complex-cons number2 (- number2 number2))))
	((complexp number2)
	 (complex-two-arguments code (%complex-cons number1 (- number1 number1)) number2))
	((floatp number1)
	 (funcall function number1 (float number2)))
	((floatp number2)
	 (funcall function (float number1) number2))
	((small-floatp number1)
	 (funcall function number1 (small-float number2)))
	((small-floatp number2)
	 (funcall function (small-float number1) number2))
	((and (rationalp number1) (rationalp number2))
	 (rational-two-arguments code number1 number2))
	((rationalp number1)
	 (rational-two-arguments code number1 (rational number2)))
	((rationalp number2)
	 (rational-two-arguments code (rational number1) number2))
	(t
	 (ferror nil "Arith two-arg op code ~D on ~S and ~S" code number1 number2))))

(defun rational-two-arguments (code number1 number2)
  (let (num1 den1 num2 den2)
    (if (integerp number1) (setq num1 number1 den1 1)
      (setq num1 (%rational-numerator number1)
	    den1 (%rational-denominator number1)))
    (if (integerp number2) (setq num2 number2 den2 1)
      (setq num2 (%rational-numerator number2)
	    den2 (%rational-denominator number2)))
    (selectq code
      (0 (cli:// (+ (* num1 den2) (* num2 den1)) (* den1 den2)))		;ADD
      (1 (cli:// (- (* num1 den2) (* num2 den1)) (* den1 den2)))		;SUB
      (2 (cli:// (* num1 num2) (* den1 den2)))					;MUL
      ((3 10.)
       (cli:// (* num1 den2) (* den1 num2)))					;DIV, %DIV
      ((4 11.) (and (= num1 num2) (= den1 den2)))				;=, EQL
      (5 (> (* num1 den2) (* num2 den1)))					;GREATERP
      (6 (< (* num1 den2) (* num2 den1)))					;LESSP
      (7 (if (> number1 number2) number2 number1))				;MIN
      (8 (if (> number1 number2) number1 number2))				;MAX
      (otherwise (ferror nil "Rational two arg op code ~D on ~S and ~S"
			 code number1 number2)))))

(defun complex-two-arguments (code number1 number2)
  (let ((real1 (%complex-real-part number1))
	(imag1 (%complex-imag-part number1))
	(real2 (%complex-real-part number2))
	(imag2 (%complex-imag-part number2)))
    (selectq code
      (0 (%complex (+ real1 real2) (+ imag1 imag2)))				;ADD
      (1 (%complex (- real1 real2) (- imag1 imag2)))				;SUB
      (2 (%complex (- (* real1 real2) (* imag1 imag2))				;MUL
		   (+ (* real1 imag2) (* imag1 real2))))
      ((3 10.)									;DIV, %DIV
       (let ((norm2 (+ (* real2 real2) (* imag2 imag2))))
	 (%complex (cli:// (+ (* real1 real2) (* imag1 imag2)) norm2)
		   (cli:// (- (* imag1 real2) (* real1 imag2)) norm2))))
      (4 (and (= real1 real2) (= imag1 imag2)))					;=
      (5 (ferror nil "GREATERP applied to complex numbers ~S and ~S." number1 number2))
      (6 (ferror nil "LESSP applied to complex numbers ~S and ~S." number1 number2))
      (7 (ferror nil "MIN applied to complex numbers ~S and ~S." number1 number2))
      (8 (ferror nil "MAX applied to complex numbers ~S and ~S." number1 number2))
      (11. (and (eql real1 real2) (eql imag1 imag2)))				;EQL
      (otherwise (ferror nil "Complex two arg op code ~D on ~S and ~S"
			 code number1 number2)))))



