;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:10; Lowercase:T; Readtable:T -*-
;	** (c) Copyright 1980 Massachusetts Institute of Technology **

(defun expt-hard (base-number power-number)
  (cond ;; ((eq power-number 0)			;integer 0
	;;  (numeric-contage 1 base-number))
	((= power-number 0)
	 ;; (if (zerop base-number)
	 ;; (ferror 'sys:illegal-expt base-number power-number
	 ;;     "An attempt was made to raise zero to the power of a non-integer zero ~*~D")
	   (numeric-contage (numeric-contage 1 power-number) base-number))
	;;)
	((zerop base-number)
	 (if (plusp (realpart power-number))
	     (numeric-contage base-number power-number)
	   (ferror 'sys:illegal-expt base-number power-number
		   "An attempt was made to raise zero to power ~*~D, whose real part is not > 0")))
	((integerp power-number)
	 (let ((minusp (minusp power-number)))
	   (setq power-number (abs power-number))
	   (do ((ans (if (oddp power-number) base-number (numeric-contage 1 base-number))
		     (if (oddp power-number) (* ans base-number) ans)))
	       ((zerop (setq power-number (ash power-number -1)))
		(if minusp (cli:// ans) ans))
	     ;; to avoid overflow, procrastinate squaring
	     (setq base-number (* base-number base-number)))))
	;; this is a truly losing algorithm ...
	(t (exp (* power-number (log base-number))))))


;;; Integer square-root
(defun isqrt (n)
  "Square root of an integer; the greatest positive integer  (SQRT N)"
  (cond ((complexp n) (ferror nil "Foo. I haven't written this yet."))
	((< n 0)
	 (%complex 0 (isqrt (- n))))
	((= n 0) 0)				;otherwise, it would loop
	(t (do ((g (ash 1 (ash (1- (haulong n)) -1))
		   (+ g e))
		(e))
	       ((zerop (setq e (truncate (- n (* g g))
					 (ash g 1))))
		;; We are now within 1, but might be too high
		(if (> (* g g) n)
		    (1- g)
		  g))))))

(defun sqrt (number)
  "Square root of a number, as a float or complex.
Result is a short-float or complex short-float according to type of NUMBER"
  (let* ((n (if (complexp number)
		(if (zerop (%complex-imag-part number))
		    (float (%complex-real-part number))
		  (%complex-cons (float (%complex-real-part number))
				 (float (%complex-imag-part number))))
	      (float number)))
	 (val
	   (cond ((complexp n)
		  (let* ((abs (abs n))
			 (real (%complex-real-part n))
			 (imag (%complex-imag-part n))
			 (r (sqrt (// (+ real abs) 2))))
		    (%complex-cons r (// imag (+ r r)))))
		 ((< n 0.0)
		  (%complex-cons (- n n) (sqrt (- n))))
		 ((= n 0.0)
		  0.0)
		 (t
		  (let ((f (+ n 0.0f0))
			(i2 (%float-double 0 1))	;cons up a new one -- gets munged
			(exp (- (%single-float-exponent n) single-float-exponent-offset
				-2)))
                    (setf (%single-float-exponent f) single-float-exponent-offset)
                    (setf (%single-float-exponent i2)                            
                          (+ single-float-exponent-offset
			     (if (oddp exp)
				 (1+ (dpb (ldb #o0127 exp) #o0027 exp))
			         (dpb (ldb #o0127 exp) #o0027 exp))))
		    (do ((i 0 (1+ i))
			 (an (* i2 (+ 0.4826004 f (if (oddp exp) -0.25 0.0)))))
			((= i 4) an)
		      (setq an (* 0.5 (+ an (// n an))))))))))
    (if (complexp number)
	(if (typep (%complex-real-part number) 'short-float)
	    (%complex-cons (float (%complex-real-part val) 0s0)
			   (float (%complex-imag-part val) 0s0))
	  val)
      (if (typep number 'short-float)
	  (short-float val)
	val))))

(defun log (n &optional b &aux zero)
  "Log of N base BASE, which defaults to e
/(ie by default this is the /"natural/" logarithm function. Supply BASE for an unnatural log."
  (declare (arglist n &optional (base (exp 1))))
  (unless (typep n 'float) (setq n (float n 0f0)))
  (setq zero (- n n))
  (when b
    (if (and (zerop b) (not (zerop n)))
	(return-from log (numeric-contage b n))
      (setq zero (numeric-contage zero b))))
  (setq n (log-aux n))
  (if b (setq n (// n (log-aux b))))
  (float-coerce n zero))

(defun log-aux (n)
  (cond ((= n 0) (ferror 'sys:zero-log "Attempt to take logarithm of zero: ~S." n))
	((complexp n)
	 (%complex-cons (log-aux (abs n)) (phase n)))
        ((= n 1) 0.0)
        ((< n 0) (%complex-cons (log-aux (- n)) pi))
        (t
	 (let* ((f (float n 0f0))
		(i (1- (float-exponent f))))   	;i gets the base 2 exponent
	   ;; f gets the mantissa (1.0 to 2.0) ie 2x(float-fraction f)
	   (setf (%single-float-exponent f) (1+ single-float-exponent-offset))
	   (setq f (// (- f 1.414213562374)
		       (+ f 1.414213562374)))
	   (setq f (+ .5
		      (* f (+ 2.885390073
			      (* (setq f (* f f))
				 (+ 0.9618007623
				    (* f (+ 0.5765843421
					    (* 0.4342597513 f)))))))))
	   (* 0.69314718056 (+ i f))))))

(defun exp (n &aux m f)
  "e to power of a number, as a flonum.  Small flonum arg gets small flonum value."
  (cond ((zerop n)
	 (+ 1 n))
	((typep n 'complex)
	 (setq m (exp (%complex-real-part n))
	       f (%complex-imag-part n))
	 ;; If I can think of a better way of doing cis than cos + i sin, then change
	 ;; this to use that.
	 (%complex-cons (* m (cos f)) (* m (sin f))))
	((typep n 'short-float)
	 (setq m (* n 1.442695s0))		;lg e
	 (setq n (fix m) f (- m n))
	 (ash (+ .5s0 (// f			;no doubt  a simpler approx for small-floats
			  (+ 9.954596s0
			     (* 0.034657359s0 f f)
			     (- f)
			     (// -617.97227s0
				 (+ (* f f) 87.4174972s0)))))
	      (1+ n)))
	(t
	 (setq m (* n 1.44269504))		;lg e
	 (setq n (fix m) f (- m n))
	 (ash (+ .5 (// f			;replace this comment by a reference!
			(+ 9.95459578
			   (* 0.03465735903 f f)
			   (- f)
			   (// -617.97226953
			       (+ (* f f) 87.417497202)))))
	      (1+ n)))))

(defun cosd (ang)
  "Cosine of an angle measured in degrees.  Small flonum arg gets small flonum value."
  (sin (+ (* ang 0.0174532926) 1.570796326) ang))

(defun sind (ang)
  "Sine of an angle measured in degrees.  Small flonum arg gets small flonum value."
  (sin (* ang 0.0174532926) ang))

(defun cos (x)
  "Cosine of an angle measured in radians.  Small flonum arg gets small flonum value."
  (sin (+ x 1.570796326) x))

(defun sin (x &optional (type-specimen x))
  "Sine of an angle measured in radians.  Small flonum arg gets small flonum value.
If TYPE-SPECIMEN is specified, its type determines the type of the result."
  (let ((value (if (< (abs x) 1.0s-3)
		   x
		 (min (max (sin-aux x) -1.0) 1.0))))
    (if (small-floatp type-specimen)
	(small-float value)
      (float value))))

(defun sin-aux (x &aux (pi%2 1.570796326))
  (cond ((complexp x)
	 (ferror nil "Foo. I haven't written this yet."))
	(t
	 (let ((frac (// (abs x) pi%2))
	       (d)
	       (sign (cond ((> x 0) 1)
			   ((< x 0) -1))))
	   (setq d (fix frac))
	   (setq frac (- frac d))
	   (selectq (ldb #o0002 d)
	     (1 (setq sign (minus sign) frac (- frac 1)))
	     (2 (setq sign (minus sign)))
	     (3 (setq frac (- frac 1))))
	   (let ((y (* frac sign))
		 (y2 (* frac frac)))
	     (* y (+ 1.5707963185
		     (* y2 (+ -0.6459637111
			      (* y2 (+ 0.07968967928
				       (* y2 (+ -0.00467376557
						(* y2 0.00015148419))))))))))))))

(defun tan (x) (ferror nil "Foo. I haven't written this yet."))
(defun tand (x) (ferror nil "Foo. I haven't written this yet."))

(defun cli:atan (y x)
  "Arctangent in radians of y//x, between - and . Small flonum arg gets small flonum value."
   (if (< y 0)
       (- (atan (- y) x))
     (atan y x)))
(deff atan2 'cli:atan)

(defun atan (y x)
  "Arctangent in radians of y//x, between 0 and 2. Small flonum arg gets small flonum value."
  (cond ((complexp x)
	 (ferror nil "Foo. I haven't written this yet."))
	(t
	 (let ((absx (abs (float x)))
	       (absy (abs (float y)))
	       (temp)
	       (temp2)
	       (ans -0.004054058))
	   (setq temp (// (- absy absx) (+ absy absx))
		 temp2 (* temp temp))
	   (do ((l '( 0.0218612288 -0.0559098861  0.0964200441
		     -0.139085335   0.1994653499 -0.3332985605 0.9999993329)
		   (cdr l)))
	       ((null l))
	     (setq ans (+ (* ans temp2) (car l))))
	   (setq ans (* ans temp))
	   (setq temp (abs ans))
	   (cond ((or ( temp .7855) (< temp .7853))
		  (setq ans (+ ans 0.7853981634)))
		 ((< ans 0) (setq ans (// absy absx)))
		 (t (setq ans (+ (// absx absy) 1.5707963268))))
	   (setq temp ans
		 ans (- pi ans))
	   (if ( x 0) (swapf temp ans))
	   (when (< y 0)
	     (setq ans (+ ans (+ temp temp))))
	   (if (and (small-floatp x) (small-floatp y))
	       (small-float ans)
	     ans)))))


(defun asin (x) (ferror nil "Foo. I haven't written this yet."))
(defun acos (x) (ferror nil "Foo. I haven't written this yet."))

(defun sinh (x) (ferror nil "Foo. I haven't written this yet."))
(defun cosh (x) (ferror nil "Foo. I haven't written this yet."))
(defun tanh (x) (ferror nil "Foo. I haven't written this yet."))
(defun asinh (x) (ferror nil "Foo. I haven't written this yet."))
(defun acosh (x) (ferror nil "Foo. I haven't written this yet."))
(defun atanh (x) (ferror nil "Foo. I haven't written this yet."))

;;;; Randomness

(DEFVAR *RANDOM-STATE* NIL
  "Default random number generator data")

(DEFSTRUCT (RANDOM-STATE :NAMED-ARRAY (:CONSTRUCTOR MAKE-RANDOM-STATE-1) (:ALTERANT NIL)
			 (:PRINT-FUNCTION
			   (LAMBDA (RANDOM-STATE STREAM DEPTH)
			     (LET ((*PRINT-ARRAY* T))
			       (PRINT-NAMED-STRUCTURE 'RANDOM-STATE
						      RANDOM-STATE DEPTH STREAM
						      (WHICH-OPERATIONS-FOR-PRINT STREAM))))))

    RANDOM-SEED
    RANDOM-POINTER-1
    RANDOM-POINTER-2
    RANDOM-VECTOR)

(DEFUN MAKE-RANDOM-STATE (&OPTIONAL STATE)
  "Create a new random-state object for RANDOM to use.
If STATE is such a state object, it is copied.
If STATE is NIL or omitted, the default random-state is copied.
If STATE is T, a new state object is created and initialized based on the microsecond clock."
  (COND ((EQ STATE NIL)
	 (LET ((NEW (COPY-OBJECT *RANDOM-STATE*)))
	   (SETF (RANDOM-VECTOR NEW)
		 (COPY-OBJECT (RANDOM-VECTOR NEW)))
	   NEW))
	((EQ STATE T)
	 (RANDOM-CREATE-ARRAY 71. 35. (TIME:FIXNUM-MICROSECOND-TIME)))
	(T (LET ((NEW (COPY-OBJECT STATE)))
	     (SETF (RANDOM-VECTOR NEW)
		   (COPY-OBJECT (RANDOM-VECTOR NEW)))
	     NEW))))

(DEFUN RANDOM-CREATE-ARRAY (SIZE OFFSET SEED &OPTIONAL (AREA NIL))
  (LET ((DEFAULT-CONS-AREA (OR AREA DEFAULT-CONS-AREA)))
    (LET ((ARRAY (MAKE-RANDOM-STATE-1
		   :RANDOM-VECTOR (MAKE-ARRAY SIZE)
		   :RANDOM-SEED SEED
		   :RANDOM-POINTER-1 0
		   :RANDOM-POINTER-2 OFFSET)))
      (RANDOM-INITIALIZE ARRAY)
      ARRAY)))

(DEFUN RANDOM-INITIALIZE (ARRAY &OPTIONAL NEW-SEED &AUX SIZE X POINTER)
   (IF (NOT (NULL NEW-SEED))
       (SETF (RANDOM-SEED ARRAY) NEW-SEED))
   (SETQ SIZE (LENGTH (RANDOM-VECTOR ARRAY))
	 POINTER (ALOC (RANDOM-VECTOR ARRAY) 0))
   (SETF (RANDOM-POINTER-2 ARRAY) (\ (+ SIZE (- (RANDOM-POINTER-2 ARRAY)
						(RANDOM-POINTER-1 ARRAY)))
				     SIZE))
   (SETF (RANDOM-POINTER-1 ARRAY) 0)
   (ARRAY-INITIALIZE (RANDOM-VECTOR ARRAY) 0)
   (SETQ X (RANDOM-SEED ARRAY))
   (DOLIST (BYTE-SPEC
	     (CASE %%Q-POINTER
;	       (24. '(#o1414 #o0014))		;no more...
	       (25. '(#o1414 #o0014 #o3001))
	       (31. '(#o1414 #o0014 #o3011))
	       (T (FERROR NIL "Bug in RANDOM-INITIALIZE"))))
     (DO ((I 0 (1+ I))) ((= I SIZE))
       (SETQ X (%POINTER-TIMES X 4093.))			;4093. is a prime number.
       (%P-DPB-OFFSET (LDB #o1314 X) BYTE-SPEC POINTER I))))

(DEFUN RANDOM (&OPTIONAL HIGH ARRAY &AUX PTR1 PTR2 SIZE ANS VECTOR)
  "Returns a randomly chosen number.
With no argument, value is chosen randomly from all fixnums.
If HIGH is an integer, the value is a nonnegative integer and less than HIGH.
If HIGH is a flonum or small flonum, the value is a nonnegative
 number of the same type, and less than HIGH.
ARRAY can be an array used for data by the random number generator (and updated);
 you can create one with RANDOM-CREATE-ARRAY or MAKE-RANDOM-STATE."
  (WHEN HIGH
    (CHECK-TYPE HIGH (NON-COMPLEX-NUMBER 0) "a positive real number"))
  (WHEN (NULL ARRAY)
    (OR (AND (VARIABLE-BOUNDP *RANDOM-STATE*) *RANDOM-STATE*)
	(SETQ *RANDOM-STATE* (RANDOM-CREATE-ARRAY 71. 35. 105)))
    (SETQ ARRAY *RANDOM-STATE*))		;Initialization as optional arg loses on BOUNDP.
  (WITHOUT-INTERRUPTS
    (SETQ PTR1 (RANDOM-POINTER-1 ARRAY)
	  PTR2 (RANDOM-POINTER-2 ARRAY)
	  VECTOR (RANDOM-VECTOR ARRAY)
	  SIZE (LENGTH VECTOR))
    (OR (< (SETQ PTR1 (1+ PTR1)) SIZE)
	(SETQ PTR1 0))
    (OR (< (SETQ PTR2 (1+ PTR2)) SIZE)
	(SETQ PTR2 0))
    (SETF (RANDOM-POINTER-1 ARRAY) PTR1)
    (SETF (RANDOM-POINTER-2 ARRAY) PTR2)
    (SETQ ANS (%MAKE-POINTER-OFFSET DTP-FIX (AR-1 VECTOR PTR1) (AR-1 VECTOR PTR2)))
    (ASET ANS VECTOR PTR2))
  (COND ((SMALL-FLOATP HIGH)
	 (* HIGH (// (SMALL-FLOAT (LOGAND ANS (%LOGDPB 0 %%Q-BOXED-SIGN-BIT -1)))
		     (- (SMALL-FLOAT (%LOGDPB 1 %%Q-BOXED-SIGN-BIT 0))))))
	((FLOATP HIGH)
	 (* HIGH (// (FLOAT (LOGAND ANS (%LOGDPB 0 %%Q-BOXED-SIGN-BIT -1)))
		     (- (SMALL-FLOAT (%LOGDPB 1 %%Q-BOXED-SIGN-BIT 0))))))
	((NULL HIGH) ANS)
	(T
	 (DO ((BITS 14. (+ BITS %%Q-POINTER))
	      (NUMBER (LOGAND ANS (%LOGDPB 0 %%Q-BOXED-SIGN-BIT -1))
		      (+ (LOGAND (RANDOM) (%LOGDPB 0 %%Q-BOXED-SIGN-BIT -1))
			 (ASH ANS (1- %%Q-POINTER)))))
	     ((> BITS (HAULONG HIGH))
	      (MOD NUMBER HIGH))))))

;;; Return a randomly chosen number at least LOW and less than HIGH.
(DEFUN RANDOM-IN-RANGE (LOW HIGH)
  "Randomly chosen flonum not less than LOW and less than HIGH."
  (PROG* ((R (RANDOM))
	  (RNORM (// (LOGAND R #o777777) (FLOAT #o1000000))))
     (RETURN (+ LOW (* RNORM (- HIGH LOW))))))

;;; Force *RANDOM-STATE* to get a value.
(RANDOM)

;;;; Special floating arithmetic functions.

(defun float (number &optional other)
  "Convert NUMBER to floating point, of same precision as OTHER.
If OTHER is omitted, a full size flonum is returned."
  (if (small-floatp other)
      (small-float number)
    (float number)))

(defun ffloor (dividend &optional divisor)
  "Like FLOOR but converts first value to a float."
  (declare (values quotient remainder))
  (multiple-value-bind (quotient remainder)
      (floor dividend (or divisor 1))
    (values (float quotient) remainder)))

(defun fceiling (dividend &optional divisor)
  "Like CEILING but converts first value to a float."
  (declare (values quotient remainder))
  (multiple-value-bind (quotient remainder)
      (ceiling dividend (or divisor 1))
    (values (float quotient) remainder)))

(defun ftruncate (dividend &optional divisor)
  "Like TRUNCATE but converts first value to a float."
  (declare (values quotient remainder))
  (multiple-value-bind (quotient remainder)
      (truncate dividend (or divisor 1))
    (values (float quotient) remainder)))

(defun fround (dividend &optional divisor)
  "Like ROUND but converts first value to a float."
  (declare (values quotient remainder))
  (multiple-value-bind (quotient remainder)
      (round dividend (or divisor 1))
    (values (float quotient) remainder)))

(defun float-radix (float)
  "Returns the radix of the exponent of a float.  That is always 2."
  (check-type float float)
  2)

(defun float-digits (float)
  "Returns the number of bits of fraction part FLOAT has.
This depends only on the data type of FLOAT (single-float vs short-float)."
  (typecase float
    (short-float short-float-mantissa-length)
    (t           single-float-mantissa-length)))

(defun float-precision (float)
  "Returns the number of significant bits of fraction part FLOAT has.
For normalized arguments this is defined to be the same as FLOAT-DIGITS,
and all floats are normalized on the Lisp machine, so they are identical."
  (typecase float
    (short-float short-float-mantissa-length)
    (t           single-float-mantissa-length)))

(defun decode-float (float)
  "Returns three values describing the fraction part, exponent, and sign of FLOAT.
The first is a float between 1/2 and 1 (but zero if the arg is zero).
This value, times two to a suitable power, equals FLOAT except in sign.
The second value is an integer, the exponent of two needed for that calculation.
The third value is a float whose sign and type match FLOAT's
and whose magnitude is 1."
  (declare (values fraction-flonum exponent sign-flonum))
  (values (abs (float-fraction float))
	  (float-exponent float)
	  (if (minusp float)
	      (if (small-floatp float) -1.0s0 -1.0)
	      (if (small-floatp float) 1.0s0 1.0))))

(defun integer-decode-float (float)
  "Returns three values describing the fraction part, exponent, and sign of FLOAT.
The first is an integer representing the fraction part of FLOAT.
This value floated, times two to a suitable power, equals FLOAT except in sign.
The second value is an integer, the exponent of two needed for that calculation.
The third value is a float whose sign and type match FLOAT's
and whose magnitude is 1."
  (declare (values fraction exponent sign-flonum))
  (values (flonum-mantissa (abs float))
	  (flonum-exponent (abs float))
	  (if (minusp float)
	      (if (small-floatp float) -1.0s0 -1.0)
	      (if (small-floatp float) 1.0s0 1.0))))

(defun float-sign (sign-flonum &optional magnitude-flonum)
  "Returns a float whose sign matches SIGN-FLONUM and magnitude matches MAGNITUDE-FLONUM.
If MAGNITUDE-FLONUM is omitted, it defaults to 1.
The type of float returned matches MAGNITUDE-FLONUM
if that is specified; else SIGN-FLONUM."
  (if magnitude-flonum
      (if (eq (minusp sign-flonum) (minusp magnitude-flonum))
	  magnitude-flonum (- magnitude-flonum))
    (if (minusp sign-flonum)
	(if (small-floatp sign-flonum) -1.0s0 -1.0)
        (if (small-floatp sign-flonum) 1.0s0 1.0))))

(defconst pi 3.1415926535
  "The mathematical constant PI.")

;;; Same as BYTE, but for use below, when BYTE is not loaded yet.
(defun xbyte (size position)
  (dpb position %%byte-specifier-position size))

;; moved into qrand since need in the cold load
;(defconst most-negative-fixnum (%logdpb 1 %%q-boxed-sign-bit 0)
;  "Any integer smaller than this must be a bignum.")
;
;(defconst most-positive-fixnum (%logdpb 0 %%q-boxed-sign-bit -1)
;  "Any integer larger than this must be a bignum.")

(defconst most-positive-short-float (%make-pointer dtp-small-flonum -1)
  "No short float can be greater than this number.")

(defconst least-positive-short-float (%make-pointer dtp-small-flonum #o600000)
  "No positive short float can be closer to zero than this number.")

(defconst least-negative-short-float (%make-pointer dtp-small-flonum #o577777)
  "No negative short float can be closer to zero than this (unnormalized) number.")

(defconst most-negative-short-float (%make-pointer dtp-small-flonum
						   (lognot #o377777))
  "No short float can be less than this number.")

(defconst most-positive-single-float (%float-double (%logdpb 0 %%q-boxed-sign-bit -1)
						    (%logdpb 0 %%q-boxed-sign-bit -1))
  "No float can be greater than this number.")

(%p-dpb #o77777 (xbyte 11. 8) most-positive-single-float)
(%p-store-contents-offset -1 most-positive-single-float 1)

(defconst most-negative-single-float (- 1.0 1.0)
  "No float can be less than this number.")

(%p-dpb #o77777 (xbyte 12. 7) most-negative-single-float)

(defconst least-positive-single-float (- 1.0 1.0)
  "No positive float can be between zero and this number.")

(%p-dpb 1 (xbyte 11. 8) least-positive-single-float)
(%p-dpb 1 (xbyte 1 6) least-positive-single-float)


(defconst least-negative-single-float (- 1.0 1.0)
  "No negative float can be between zero and this number.")

(%p-dpb 1 (xbyte 11. 8) least-negative-single-float)
(%p-dpb 1 (xbyte 1 7) least-negative-single-float)
(%p-dpb #o777 (xbyte 5 0) least-negative-single-float)
(%p-store-contents-offset -1 least-negative-single-float 1)

(defconst most-positive-long-float most-positive-single-float)
(defconst most-negative-long-float most-negative-single-float)
(defconst least-positive-long-float least-positive-single-float)
(defconst least-negative-long-float least-negative-single-float)

(defconst most-positive-double-float most-positive-single-float)
(defconst most-negative-double-float most-negative-single-float)
(defconst least-positive-double-float least-positive-single-float)
(defconst least-negative-double-float least-negative-single-float)

(defconst short-float-epsilon
	  (+ (small-float (scale-float 1.0s0 -17.))
	     (small-float (scale-float 1.0s0 -31.))
	     (small-float (scale-float 1.0s0 -33.)))
  "Smallest positive short float which can be added to 1.0s0 and make a difference.")

(defconst single-float-epsilon (+ (scale-float 1.0 -37) (scale-float 1.0 -75))
  "Smallest positive float which can be added to 1.0 and make a difference.")

(defconst long-float-epsilon single-float-epsilon)
(defconst double-float-epsilon single-float-epsilon)

(defconst short-float-negative-epsilon
	  (+ (small-float (scale-float 1.0s0 -18.))
	     (small-float (scale-float 1.0s0 -32.))
	     (small-float (scale-float 1.0s0 -34.)))
  "Smallest positive short float which can be subtracted from 1.0s0 and make a difference.")

(defconst single-float-negative-epsilon (scale-float 1.0 -31.)
  "Smallest positive float which can be subtracted from 1.0 and make a difference.")

(defconst long-float-negative-epsilon single-float-negative-epsilon)
(defconst double-float-negative-epsilon single-float-negative-epsilon)

; todo
; cli:atan		complex, twoargs
; atan, atan2		complex, twoargs
; sin,cos		complex
; tan			define
; tand			define			
; asin,acos		define
; sinh,cosh,tanh	define
; asinh,acosh,atanh	define
