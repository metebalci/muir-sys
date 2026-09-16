;;; Matrix arithmetic.   MMcM  7/23/80  -*- Mode:LISP; Package:MATH; Base:8 -*-

(DEFSUBST 1D-ARRAYP (ARRAY)
  (AND (ARRAYP ARRAY)
       (= (ARRAY-RANK ARRAY) 1)))

(DEFSUBST 2D-ARRAYP (ARRAY)
  (AND (ARRAYP ARRAY)
       (= (ARRAY-RANK ARRAY) 2)))

(DEFSUBST 1-OR-2D-ARRAYP (ARRAY)
  (AND (ARRAYP ARRAY)
       (OR ( (ARRAY-RANK ARRAY) 2))))

(DEFSUBST 2D-SQUARE-ARRAYP (ARRAY)
  (AND (ARRAYP ARRAY)
       (= (ARRAY-RANK ARRAY) 2)
       (= (ARRAY-DIMENSION ARRAY 0) (ARRAY-DIMENSION ARRAY 1))))

;;; Convert a 2d array into a list of lists of the elements
(DEFUN LIST-2D-ARRAY (ARRAY)
  "Returns a list of lists containing the values in ARRAY, which must
be a two-dimensional array.  There is one element for each row; each
element is a list of the values in that row."
  (CHECK-ARG ARRAY 2D-ARRAYP "A Two-dimensional array")
  (DO ((I 0 (1+ I))
       (DIM-1 (ARRAY-DIMENSION ARRAY 0))
       (DIM-2 (ARRAY-DIMENSION ARRAY 1))
       (LIST NIL))
      (( I DIM-1)
       (NREVERSE LIST))
    (PUSH (DO ((J 0 (1+ J))
	       (LIST NIL))
	      (( J DIM-2)
	       (NREVERSE LIST))
	    (PUSH (AREF ARRAY I J) LIST))
	  LIST)))

;;; Fill up a 2d array from a list, like fillarray, the lists can wrap around as needed
(DEFUN FILL-2D-ARRAY (ARRAY LIST)
  "Fills the two-dimensional array ARRAY with elements from LIST.
LIST should be a list of lists, with each element being a list corresponding to a row.
ARRAY's elements are stored from the list.  Unlike FILLARRAY, if LIST is not long enough,
this function /"wraps around/", starting over at the beginning.
The lists which are elements of LIST also work this way."
  (CHECK-ARG ARRAY 2D-ARRAYP "A Two-dimensional array")
  (DO ((I 0 (1+ I))
       (DIM-1 (ARRAY-DIMENSION ARRAY 0))
       (DIM-2 (ARRAY-DIMENSION ARRAY 1))
       (L LIST (CDR L))
       (SUBLIST))
      (( I DIM-1))
    (AND (NULL L)
	 (SETQ L LIST))
    (SETQ SUBLIST (CAR L))
    (DO ((J 0 (1+ J))
	 (L SUBLIST (CDR L)))
	(( J DIM-2))
      (AND (NULL L)
	   (SETQ L SUBLIST))
      (SETF (AREF ARRAY I J) (CAR L)))))

;;; Multiply two matrices into a third.  
;;; A 1d array of dimension N is treated as a Nx1 array.
(DEFUN MULTIPLY-MATRICES (MATRIX-1 MATRIX-2 &OPTIONAL MATRIX-3 &AUX SAVED-MATRIX-3)
  "Multiply matrices MATRIX-1 and MATRIX-2, storing into MATRIX-3 if supplied.
If MATRIX-3 is not supplied, then a new (ART-Q type) array is returned, else
MATRIX-3 must have exactly the right dimensions for holding the result of the multiplication.
Both MATRIX-1 and MATRIX-2 must be either one- or two-diimensional.
The first dimension of MATRIX-2 must equal the second dimension of MATRIX-1, unless MATRIX-1
is one-dimensional, when the first dimensions must match (thus allowing multiplications of the
form VECTOR x MATRIX)"
  (CHECK-ARG MATRIX-1 1-OR-2D-ARRAYP "A one- or two-dimensional array")
  (CHECK-ARG MATRIX-2 1-OR-2D-ARRAYP "A one- or two-dimensional array")
  (CHECK-ARG MATRIX-3 (OR (NULL MATRIX-3) (1-OR-2D-ARRAYP MATRIX-3))
	     "A one- or two-dimensional array or NIL")
  (LET ((DIM-1-1 (IF (= (ARRAY-RANK MATRIX-1) 1) 1 (ARRAY-DIMENSION MATRIX-1 0)))
	(DIM-1-2 (IF (= (ARRAY-RANK MATRIX-1) 1) (ARRAY-DIMENSION MATRIX-1 0)
		   (ARRAY-DIMENSION MATRIX-1 1)))
	(DIM-2-1 (ARRAY-DIMENSION MATRIX-2 0))
	(DIM-2-2 (IF (= (ARRAY-RANK MATRIX-2) 1) 1 (ARRAY-DIMENSION MATRIX-2 1)))
	(DIM-3-1 (WHEN MATRIX-3
		   (IF (= (ARRAY-RANK MATRIX-3) 1) 1 (ARRAY-DIMENSION MATRIX-3 0))))
	(DIM-3-2 (WHEN MATRIX-3
		   (IF (= (ARRAY-RANK MATRIX-3) 1) (ARRAY-DIMENSION MATRIX-3 0)
		     (ARRAY-DIMENSION MATRIX-3 1)))))
    (UNLESS (= DIM-2-1 DIM-1-2)
      (FERROR NIL "The ~~Dx~D matrix ~S and the
~Dx~D matrix ~S cannot be multiplied~"
	      DIM-1-1 DIM-1-2 MATRIX-1 DIM-2-1 DIM-2-2 MATRIX-2))
    (IF MATRIX-3
	(IF (AND (= DIM-1-1 DIM-3-1)
		 (= DIM-2-2 DIM-3-2))
	    ;; We have a destination; see if it's the same as one of the sources,
	    ;; If it is, substitute a temporary for the destination.  We only check
	    ;; EQness, not displacements.
	    (WHEN (LET ((FORWARDED (FOLLOW-STRUCTURE-FORWARDING MATRIX-3)))
		    (OR (EQ FORWARDED (FOLLOW-STRUCTURE-FORWARDING MATRIX-1))
			(EQ FORWARDED (FOLLOW-STRUCTURE-FORWARDING MATRIX-2))))
	      (SETQ SAVED-MATRIX-3 MATRIX-3
		    MATRIX-3 (MAKE-ARRAY (ARRAY-DIMENSIONS MATRIX-3)
					 ':TYPE (ARRAY-TYPE MATRIX-3))))
	  (FERROR NIL "The ~~Dx~D matrix ~S is not the right size for multiplying the
~Dx~D matrix ~S and the
~Dx~D matrix ~S.~"
		  DIM-3-1 DIM-3-2 MATRIX-3 DIM-1-1 DIM-1-2 MATRIX-1
		  DIM-2-1 DIM-2-2 MATRIX-2))
      ;; we don't make a 1xn matrix here since the user probably wants a vector result.
      (SETQ MATRIX-3 (MAKE-ARRAY (IF (= (ARRAY-RANK MATRIX-1) 1) DIM-2-2 (LIST DIM-1-1 DIM-2-2)))))
    ;; Make indirect arrays to any vectors, so can use ar-2 everywhere below
    (LET ((MAT-1 (IF (= 2 (ARRAY-RANK MATRIX-1)) MATRIX-1
		   (MAKE-ARRAY (LIST DIM-1-1 DIM-2-1) ':TYPE (ARRAY-TYPE MATRIX-1)
			       ':DISPLACED-TO MATRIX-1)))
	  (MAT-2 (IF (= 2 (ARRAY-RANK MATRIX-2)) MATRIX-2
		   (MAKE-ARRAY (LIST DIM-2-1 DIM-2-2) ':TYPE (ARRAY-TYPE MATRIX-2)
			       ':DISPLACED-TO MATRIX-2)))
	  (MAT-3 (IF (= 2 (ARRAY-RANK MATRIX-3)) MATRIX-3
		   (MAKE-ARRAY (LIST DIM-1-1 DIM-2-2) ':TYPE (ARRAY-TYPE MATRIX-3)
			       ':DISPLACED-TO MATRIX-3))))
      ;; Do the actual multiplication
      (DOTIMES (I DIM-1-1)
	(DOTIMES (J DIM-2-2)
	  (SETF (AREF MAT-3 I J)
		(DO ((K 0 (1+ K))
		     (SUM 0 (+ SUM (* (AREF MAT-1 I K) (AREF MAT-2 K J)))))
		    (( K DIM-2-1) SUM)))))
      ;; Try to get rid of any temporary arrays we made
      (WHEN (NEQ MATRIX-3 MAT-3) (RETURN-ARRAY MAT-3))
      (WHEN (NEQ MATRIX-2 MAT-2) (RETURN-ARRAY MAT-2))
      (WHEN (NEQ MATRIX-1 MAT-1) (RETURN-ARRAY MAT-1))
      ;; if we substituted a temporary above, copy the result into the saved
      ;; destination and return the temporary to free storage.
      (WHEN SAVED-MATRIX-3
	(COPY-ARRAY-CONTENTS MATRIX-3 SAVED-MATRIX-3)
	(RETURN-ARRAY MATRIX-3)
	(SETQ MATRIX-3 SAVED-MATRIX-3))))
  MATRIX-3)
    
;;; Gauss-Jordan inversion
(DEFUN INVERT-MATRIX (MATRIX &OPTIONAL INTO-MATRIX &AUX DIM)
  "Computes the inverse of MATRIX using the Gauss-Jordan algorithm with partial pivoting.
If INTO-MATRIX is supplied, the result is stored into it and returned;
 otherwise an array is created to hold the result and that is returned.
MATRIX must be two-dimensional and square.
Note: if you want to solve a set of simultaneous equations, you should
not use this function; use MATH:DECOMPOSE and MATH:SOLVE. (That is more efficient)"  
  (CHECK-ARG MATRIX (2D-SQUARE-ARRAYP MATRIX)
	     "A square matrix")
  (SETQ DIM (ARRAY-DIMENSION MATRIX 0))
  (IF INTO-MATRIX
      (OR (AND (EQ DIM (ARRAY-DIMENSION INTO-MATRIX 0))
	       (EQ DIM (ARRAY-DIMENSION INTO-MATRIX 1)))
	  (FERROR NIL "~S is not correct for the inverse of ~S" INTO-MATRIX MATRIX))
    (SETQ INTO-MATRIX (MAKE-ARRAY (LIST DIM DIM)
				  ':ELEMENT-TYPE (IF (TYPEP MATRIX '(ARRAY INTEGER)) T
						   (ARRAY-ELEMENT-TYPE MATRIX)))))
  (COPY-ARRAY-CONTENTS MATRIX INTO-MATRIX)
  ;(DOTIMES (I (ARRAY-LENGTH INTO-MATRIX))
  ;  (SETF (AR-1-FORCE INTO-MATRIX I)
  ;        (+ 0.0s0 (AR-1-FORCE INTO-MATRIX I))))
  (LET ((COLS (MAKE-ARRAY DIM))
	(TEM (MAKE-ARRAY (LIST DIM DIM)))
	(COLS-USED (MAKE-ARRAY DIM ':TYPE 'ART-1B)))
    (FILLARRAY COLS-USED '(0))
    (DO ((I 0 (1+ I))
	 (J))
	(( I DIM))
      ;; Find the greatest element in this row in an unused column
      (SETQ J (DO ((J 0 (1+ J))
		   (MAX 0) POS TEM1)
		  (( J DIM)
		   (AND (ZEROP MAX)
			(FERROR 'SINGULAR-MATRIX "The matrix ~S is singular." MATRIX))
		   POS)
		(AND (ZEROP (AREF COLS-USED J))
		     (> (SETQ TEM1 (ABS (AREF INTO-MATRIX I J))) MAX)
		     (SETQ MAX TEM1 POS J))))
      (SETF (AREF COLS I) J)
      (SETF (AREF COLS-USED J) 1)
      ;; Pivot about I,J
      (DO ((K 0 (1+ K))
	   (ELEM-I-J (AREF INTO-MATRIX I J)))
	  (( K DIM))
	(DO ((L 0 (1+ L))
	     (ELEM-K-J (AREF INTO-MATRIX K J))
	     (ELEM))
	    (( L DIM))
	  (SETQ ELEM (AREF INTO-MATRIX K L))
	  (SETF (AREF TEM K L)
		(IF (= K I)			;Same row?
		    (IF (= L J)			;Corner itself?
			(CLI:// ELEM)
		      (CLI:// ELEM ELEM-I-J))
		  (IF (= L J)			;Same column?
		      (- (CLI:// ELEM ELEM-I-J))
		    (- ELEM (CLI:// (* ELEM-K-J (AREF INTO-MATRIX I L)) ELEM-I-J)))))))
      (COPY-ARRAY-CONTENTS TEM INTO-MATRIX))
    ;; And finally permute
    (DOTIMES (I DIM)
      (DO ((J 0 (1+ J))
	   (K (AREF COLS I)))
	  (( J DIM))
	(SETF (AREF TEM K J) (AREF INTO-MATRIX I J))))
    (DOTIMES (I DIM)
      (DO ((K 0 (1+ K))
	   (J (AREF COLS I)))
	  (( K DIM))
	(SETF (AREF INTO-MATRIX K I) (AREF TEM K J))))
    (RETURN-ARRAY TEM)
    (RETURN-ARRAY COLS))
  INTO-MATRIX)

(DEFUN TRANSPOSE-MATRIX (MATRIX &OPTIONAL INTO-MATRIX)
  "Transposes MATRIX. If INTO-MATRIX is supplied, the result is stored into it
and is returned; otherwise an array is created to hold the result and that is returned.
MATRIX must be a two-dimensional array. INTO-MATRIX, if provided, must be two-dimensional
and of exactly the right dimensions to hold the transpose."
  (CHECK-ARG MATRIX 2D-ARRAYP "A two-dimensional array")
  (CHECK-ARG INTO-MATRIX (OR (NULL INTO-MATRIX) (2D-ARRAYP INTO-MATRIX))
	     "A two-dimensional array, or NIL")
  (LET ((DIM-1 (ARRAY-DIMENSION MATRIX 0))
	(DIM-2 (ARRAY-DIMENSION MATRIX 1)))
    (IF INTO-MATRIX
	(UNLESS (AND (EQ DIM-1 (ARRAY-DIMENSION INTO-MATRIX 1))
		     (EQ DIM-2 (ARRAY-DIMENSION INTO-MATRIX 0)))
	  (FERROR NIL "The ~~Dx~D matrix ~S does not have
the right dimensions for containing the transpose of the
~Dx~D matrix ~S~"
		  (ARRAY-DIMENSION INTO-MATRIX 0) (ARRAY-DIMENSION INTO-MATRIX 1) INTO-MATRIX
		  DIM-1 DIM-2 MATRIX))
      (SETQ INTO-MATRIX (MAKE-ARRAY (LIST DIM-2 DIM-1) ':TYPE (ARRAY-TYPE MATRIX))))
    (IF (EQ MATRIX INTO-MATRIX)			;Special case
	(DOTIMES (I DIM-1)
	  (DO ((J I (1+ J)))
	      (( J DIM-1))
	    (SWAPF (AREF MATRIX I J) (AREF MATRIX J I))))
      (DOTIMES (I DIM-1)
	(DOTIMES (J DIM-2)
	  (SETF (AREF INTO-MATRIX J I) (AREF MATRIX I J))))))
  INTO-MATRIX)

;Determinant, based on the facts that the determinant of a triangular
;matrix is the product of the diagonal elements, and the determinant of
;the product of two matrices is the product of the determinants.
(DEFUN DETERMINANT (MATRIX)
  "Returns the determinant of MATRIX, which must be square."
  (CONDITION-CASE ()
    (MULTIPLE-VALUE-BIND (LU PS) (DECOMPOSE MATRIX)
      (DO ((I (1- (ARRAY-LENGTH PS)) (1- I))
	   (DET 1 (* DET (AREF LU (AREF PS I) I))))
	  ((MINUSP I)
	   (IF (MINUSP (PERMUTATION-SIGN PS)) (SETQ DET (- DET)))
	   (RETURN-ARRAY PS)
	   (RETURN-ARRAY LU)
	   DET)))
    (SINGULAR-MATRIX 0)))

;Note that this trashes its argument
(DEFUN PERMUTATION-SIGN (PS)
  (LOOP WITH SIGN = +1
	FOR I FROM 0 BELOW (ARRAY-LENGTH PS)
	AS J = (AREF PS I)
	WHEN ( I J)	;Found a cycle, determine its length-1
	  DO (LOOP AS K = (AREF PS J)
		   DO (ASET J PS J)
		      (SETQ SIGN (- SIGN))
		      (SETQ J K)
		   UNTIL (= J I))
	FINALLY (RETURN SIGN)))

;;; Linear equation solving.   DLW 8/4/80

;;; The functions below are useful for solving systems of simultaneous
;;; linear equations.  They are taken from the text "Computer Solution of
;;; Linear Algebraic Systems", by Forsythe and Moler, Prentice-Hall 1967.
;;; 
;;; The function DECOMPOSE takes a square matrix A (N by N elements) and
;;; returns a square matrix holding the LU decomposition of A.  The
;;; function finds the unique solution of L * U = A, where L is a lower
;;; triangular matrix with 1's along the diagonal, and U is an upper
;;; triangular matrix.  The function returns a square matrix holding L-I+U;
;;; that is, the lower triangle not including the diagonal holds L, and the
;;; rest holds U, with the 1's along the diagonal of L not actually stored.
;;; (Note: the LU decomposition exists uniquely only if all of the
;;; principle minor matrices made from the first K rows and columns are
;;; non-singular; see Forsythe and Moler, Theorem 9.2.)
;;; 
;;; The function SOLVE takes the LU decomposition of A, and a vector of
;;; solutions of the equations B, and returns X where A * X = B.
;;; 
;;; DECOMPOSE uses partial pivoting.  Rather than actually moving the
;;; elements of the array from one row to another, it returns a permutation
;;; array PS telling how the rows of LU are permuted.  The PS array must
;;; then be passed into SOLVE so that it can interpret LU properly.
;;;
;;; Iterative improvement is not yet implemented.


;;; DECOMPOSE
;;; A is an N by N array.
;;; Two values are returned: LU and PS.
;;; The caller may provide arrays to be used for LU and PS by passing
;;; the optional arguments; otherwise, new arrays will be allocated.
;;; If the same array is passed as A and LU, A is overwriten with
;;; the decomposition correctly.
;;; The condition SINGULAR-MATRIX is raised if the matrix is singular.

(DEFUN DECOMPOSE (A &OPTIONAL LU PS &AUX N)
  "Computes the LU decomposition of the matrix A.
Gaussian elimination with partial pivoting is used.
If LU supplied, the result is stored into that and returned;
 otherwise an array is created to hold the result and that is returned.
The LU array is permuted by rows according to the permutation array PS.
If PS is supplied, the permutation array is stored into it;
 otherwise an array is created to hold it."
  (DECLARE (RETURN-LIST LU PS))
  ;; Prepare arguments.
  (CHECK-ARG A 2D-ARRAYP "a two-dimensional array")
  (SETQ N (ARRAY-DIMENSION A 0))
  (CHECK-ARG A (= N (ARRAY-DIMENSION A 1)) "a square array.")
  (IF LU
      (CHECK-ARG LU 2D-ARRAYP "a two-dimensional array")
    (SETQ LU (MAKE-ARRAY (LIST N N) ':ELEMENT-TYPE (IF (TYPEP A '(ARRAY INTEGER)) T
						     (ARRAY-ELEMENT-TYPE A)))))
  (IF PS
      (CHECK-ARG PS 1D-ARRAYP "a one-dimensional array")
    (SETQ PS (MAKE-ARRAY N)))
  (LET ((SCALES (MAKE-ARRAY N)))
    ;; Init PS to the identity, LU to A, and SCALES to the reciprocal
    ;; of the largest-magnitude element on a given row.
    (DOTIMES (I N)
      (SETF (AREF PS I) I)
      (LET ((NORMROW 0))
	(DOTIMES (J N)
	  (LET ((AIJ (AREF A I J)))
	    (SETF (AREF LU I J) AIJ)
	    (SETQ NORMROW (MAX (ABS AIJ) NORMROW))))
	(IF (ZEROP NORMROW)
	    (FERROR 'SINGULAR-MATRIX "The matrix ~S is singular: it has a zero row." A))
	(SETF (AREF SCALES I) (CLI:// NORMROW))))

    ;; Gaussian elimination with partial pivoting.
    (DOTIMES (K (1- N))
       ;; Find the pivot index.
       (LET ((PIVOTINDEX NIL)
	     (BIGGEST 0))
	 (DO ((I K (1+ I)))
	     (( I N))
	   (LET ((SIZE (* (ABS (AREF LU (AREF PS I) K))
			  (AREF SCALES (AREF PS I)))))
	     (COND ((> SIZE BIGGEST)
		    (SETQ BIGGEST SIZE)
		    (SETQ PIVOTINDEX I)))))
	 (IF (ZEROP BIGGEST)
	     (FERROR 'SINGULAR-MATRIX "The matrix ~S is singular: SOLVE will divide by zero." A))
	 (SWAPF (AREF PS PIVOTINDEX) (AREF PS K)))

       ;; Do the elimination with that pivoting.
       (LET* ((PSK (AREF PS K))
	      (PIVOT (AREF LU PSK K)))
	 ; ;; For fixnum arguments, get an approximate answer, rather than the wrong
	 ; ;; answer, unless ALLOW-RATIONALS is specified, in which case get the
	 ; ;; exact answer slowly.  This is most useful for determinant where we know
	 ; ;; that the rationals will eventually cancel.
	 ; ;; Some day // will automatically switch to rationals.
	 ; (AND (FIXP PIVOT) ( PIVOT 1) ( PIVOT -1)
	 ;      (SETQ PIVOT (IF ALLOW-RATIONALS (SI:RATIONAL PIVOT) (FLOAT PIVOT))))
	 (DO ((I (1+ K) (1+ I)))
	     (( I N))
	   (LET ((PSI (AREF PS I)))
	     (LET ((MULT (CLI:// (AREF LU PSI K) PIVOT)))
	       (SETF (AREF LU PSI K) MULT)
	       (UNLESS (ZEROP MULT)
		 (DO ((J (1+ K) (1+ J)))
		     (( J N))
		   (SETF (AREF LU PSI J)
			 (- (AREF LU PSI J) (* MULT (AREF LU PSK J)))))))))))
    (IF (ZEROP (AREF LU (AREF PS (1- N)) (1- N)))
	(FERROR 'SINGULAR-MATRIX "The matrix ~S is singular: SOLVE will divide by zero." A))
    (RETURN-ARRAY SCALES))
  (VALUES LU PS))

;;; SOLVE
;;; LU is the N by N LU-decomposition of A.
;;; PS is the N-long permutation vector for LU.  B is an N-long array
;;; of solutions to the equations.
;;; The returned value is X: the solution of A * X = B.
;;; The caller may provide the array to be used as X by passing the optional
;;; argument.

(DEFUN SOLVE (LU PS B &OPTIONAL X &AUX N)
  "This function takes the LU decomposition and associated permutation
array produced by MATH:DECOMPOSE and solves the set of simultaneous
equations defined by the original matrix A given to MATH:DECOMPOSE and
the right-hand sides in the vector B. If X is supplied, the solutions
are stored into it and it is returned; otherwise an array is
created to hold the solutions and that is returned.
B must be a one-dimensional array."
  ;; Prepare arguments.
  (CHECK-ARG LU 2D-SQUARE-ARRAYP "a square two-dimensional array")
  (SETQ N (ARRAY-DIMENSION LU 0))
  (CHECK-ARG PS 1D-ARRAYP "a one-dimensional array")
  (CHECK-ARG B 1D-ARRAYP "a one-dimensional array")
  (IF X
      (CHECK-ARG X 1D-ARRAYP "a one-dimensional array")
    (SETQ X (MAKE-ARRAY N  ':TYPE (IF (TYPEP B '(ARRAY INTEGER)) T
				    (ARRAY-ELEMENT-TYPE B)))))
  (DOTIMES (I N)
    (LET ((PSI (AREF PS I))
	  (DOT 0))
      (DOTIMES (J I)
	(SETQ DOT (+ DOT (* (AREF LU PSI J) (AREF X J)))))
      (SETF (AREF X I) (- (AREF B PSI) DOT))))
  (DO ((I (1- N) (1- I)))
      ((< I 0))
    (LET ((PSI (AREF PS I))
	  (DOT 0))
      (DO ((J (1+ I) (1+ J)))
	  (( J N))
	(SETQ DOT (+ DOT (* (AREF LU PSI J) (AREF X J)))))
      (SETF (AREF X I)
	    (CLI:// (- (AREF X I) DOT) (AREF LU PSI I)))))
	    	       ;(LET ((D (AREF LU PSI I)))
		       ;  ;; Compensate for fixnum division--take this out when
		       ;  ;; there are "rational" numbers
		       ;  (AND (FIXP D) ( D 1) ( D -1) (SETQ D (FLOAT D)))
		       ;  D)
  X)
