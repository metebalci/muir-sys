;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:8; Readtable:T -*-

; Miscellaneous functions not worthy of being in qfctns, or not able to be in the cold load.
;	** (c) Copyright 1980 Massachusetts Institute of Technology **

(DEFUN %POINTER-UNSIGNED (N)
  "Convert the fixnum N, regarded as unsigned number, into number (maybe big) with same value.
If the argument is negative (if regarded as signed), it is expanded into a bignum."
  (IF (MINUSP N) (+ N (ASH (%LOGDPB 1 %%Q-BOXED-SIGN-BIT 0) 1)) N))

(DEFUN %MAKE-POINTER-UNSIGNED (N)
  "Convert N to a fixnum which, regarded as unsigned, has same value as N.
Thus, a number just too big to be a signed fixnum
becomes a fixnum which, if regarded as signed, would be negative."
  (IF (FIXNUMP N)
      N
    (LOGIOR (LDB (1- %%Q-POINTER) N)
	    (ROT (LDB (BYTE 1 (1- %%Q-POINTER)) N) -1))))

(DEFUN SET-MEMORY-SIZE (NEW-SIZE)
  "Specify how much main memory is to be used, in words.
/(By default, all the memory on the machine is used.)
This is mainly useful running benchmarks with different memory sizes.
If you specify more memory than is present on the machine,
memory board construction starts; in the meantime, the machine crashes."
  (PROG (OLD-SIZE NEWP OLDP)
	(UNLESS ( NEW-SIZE (+ (SYSTEM-COMMUNICATION-AREA %SYS-COM-WIRED-SIZE) #o20000)) ;8K min
	  (FERROR NIL "#o~O is smaller than wired + 8K"  NEW-SIZE))
     L  (SETQ OLD-SIZE (SYSTEM-COMMUNICATION-AREA %SYS-COM-MEMORY-SIZE))
        (SETQ OLDP (CEILING OLD-SIZE PAGE-SIZE))
        (SETQ NEWP (CEILING NEW-SIZE PAGE-SIZE))
	(COND ((OR (> NEWP (REGION-LENGTH PHYSICAL-PAGE-DATA))
		   (> NEWP (TRUNCATE (* 4 (REGION-LENGTH PAGE-TABLE-AREA)) 9)))
	       (FERROR NIL "#o~O is bigger than page tables allow"  NEW-SIZE))
	      ((= NEWP OLDP) (RETURN T))
              ((< NEWP OLDP) (GO FLUSH)))
     MORE
	(WHEN (%DELETE-PHYSICAL-PAGE OLD-SIZE)
	  (PRINT (LIST OLD-SIZE "EXISTED")))
        (%CREATE-PHYSICAL-PAGE OLD-SIZE)
	(SETF (SYSTEM-COMMUNICATION-AREA %SYS-COM-MEMORY-SIZE)
	      (+ OLD-SIZE PAGE-SIZE))
        (GO L)

     FLUSH
	(WHEN (NULL (%DELETE-PHYSICAL-PAGE (- OLD-SIZE PAGE-SIZE)))
	  (PRINT (LIST (- OLD-SIZE PAGE-SIZE) "DID-NOT-EXIST")))
	(SETF (SYSTEM-COMMUNICATION-AREA %SYS-COM-MEMORY-SIZE)
	      (- OLD-SIZE PAGE-SIZE))
        (GO L)))

(DEFUN SET-ERROR-MODE (&OPTIONAL (CAR-SYM-MODE 1) (CDR-SYM-MODE 1)
			         (CAR-NUM-MODE 0) (CDR-NUM-MODE 0))
  "Sets the error mode.  For the arguments 0 means /"an error/" and 1
means /"NIL/". "
  (SETQ %MODE-FLAGS (%LOGDPB CAR-SYM-MODE %%M-FLAGS-CAR-SYM-MODE %MODE-FLAGS))
  (SETQ %MODE-FLAGS (%LOGDPB CDR-SYM-MODE %%M-FLAGS-CDR-SYM-MODE %MODE-FLAGS))
  (SETQ %MODE-FLAGS (%LOGDPB CAR-NUM-MODE %%M-FLAGS-CAR-NUM-MODE %MODE-FLAGS))
  (SETQ %MODE-FLAGS (%LOGDPB CDR-NUM-MODE %%M-FLAGS-CDR-NUM-MODE %MODE-FLAGS)))


(DEFUN APROPOS-LIST (SUBSTRING &OPTIONAL PKG)
  "Return a list of symbols whose names contain SUBSTRING, but don't print anything.
Like APROPOS with :DONT-PRINT specified as non-NIL."
  (APROPOS SUBSTRING PKG :DONT-PRINT T))

(DEFUN APROPOS (SUBSTRING
		&OPTIONAL (PKG *ALL-PACKAGES*)
		&KEY (INHERITORS NIL) (INHERITED T) DONT-PRINT PREDICATE BOUNDP FBOUNDP)
  "Find all symbols in one or more packages whose names contain SUBSTRING, or
containing each string in it, if SUBSTRING is a list of strings.
If PREDICATE is non-NIL, it is a function to be called with a symbol as arg;
only symbols for which the predicate returns non-NIL will be mentioned.
If BOUNDP is non-NIL, then only bound symbols are mentioned. Likewise FBOUNDP.
The :PACKAGE argument defaults to NIL, meaning do all packages.
The packages which USE that package are processed also, unless :INHERITORS is NIL.
The packages USEd by that package are processed also, unless :INHERITED is NIL.
/(Any other packages which inherit from them also are NOT processed in any case.)
The symbols are printed unless DONT-PRINT is set.
A list of the symbols found is returned."
  (LET (RETURN-LIST
	(APROPOS-PREDICATE PREDICATE)
	(APROPOS-DONT-PRINT DONT-PRINT)
	(APROPOS-SUBSTRING SUBSTRING)
	(APROPOS-BOUNDP BOUNDP)
	(APROPOS-FBOUNDP FBOUNDP))
    (DECLARE (SPECIAL RETURN-LIST APROPOS-PREDICATE APROPOS-SUBSTRING APROPOS-DONT-PRINT
		      APROPOS-BOUNDP APROPOS-FBOUNDP))
    (IF (NULL PKG) (SETQ PKG *ALL-PACKAGES*))
    (COND ((NOT (CLI:LISTP PKG))
	   (MAPATOMS #'APROPOS-1 PKG INHERITED)
	   (AND INHERITORS
		(DOLIST (P (PACKAGE-USED-BY-LIST PKG))
		  (MAPATOMS #'APROPOS-1 P))))
	  (T (LET ((I NIL))
	       (DOLIST (P PKG)
		 (UNLESS (MEMQ P I)
		   (MAPATOMS #'APROPOS-1 P INHERITED)
		   (PUSH P I))
		 (WHEN INHERITORS
		   (DOLIST (U (PKG-USED-BY-LIST PKG))
		     (PUSHNEW U I :TEST 'EQ))))
	       (DOLIST (P I)
		 (MAPATOMS #'APROPOS-1 P)))))
    RETURN-LIST))

(DEFUN APROPOS-1 (SYMBOL &AUX (P (SYMBOL-NAME SYMBOL)))
  (DECLARE (SPECIAL RETURN-LIST APROPOS-PREDICATE APROPOS-SUBSTRING
		    APROPOS-DONT-PRINT APROPOS-BOUNDP APROPOS-FBOUNDP))
  (COND ((AND (IF (CONSP APROPOS-SUBSTRING)
		  (DOLIST (S APROPOS-SUBSTRING T)
		    (UNLESS (STRING-SEARCH S P) (RETURN NIL)))
		(STRING-SEARCH APROPOS-SUBSTRING P))
	      (OR (NOT APROPOS-BOUNDP) (BOUNDP SYMBOL))
	      (OR (NOT APROPOS-FBOUNDP) (FBOUNDP SYMBOL))
	      (NOT (MEMQ SYMBOL RETURN-LIST))
	      (OR (NULL APROPOS-PREDICATE)
		  (FUNCALL APROPOS-PREDICATE SYMBOL)))
	 (PUSH SYMBOL RETURN-LIST)
	 (OR APROPOS-DONT-PRINT
	     (PROGN
	       ;; Binding the package to NIL forces the package to be printed.
	       ;; This is better than explicitly printing the package, because
	       ;; this way you get the "short" version.
	       (LET ((*PACKAGE* NIL))
		 (FORMAT T "~%~S" SYMBOL))
	       (AND (FBOUNDP SYMBOL)
		    (FORMAT T " - Function ~:S" (ARGLIST SYMBOL)))
	       (AND (BOUNDP SYMBOL)
		    (COND ((FBOUNDP SYMBOL) (PRINC ", Bound"))
			  (T (PRINC " - Bound"))))
	       (AND (GET SYMBOL 'FLAVOR)
		    (COND ((OR (BOUNDP SYMBOL) (FBOUNDP SYMBOL))
			   (PRINC ", Flavor"))
			  (T (PRINC " - Flavor")))))))))

(DEFUN SUB-APROPOS (SUBSTRING STARTING-LIST &KEY PREDICATE BOUNDP FBOUNDP DONT-PRINT)
  "Find all symbols in STARTING-LIST whose names contain SUBSTRING, or
containing each string in it, if SUBSTRING is a list of strings.
IF PREDICATE is supplied, it should be a function of one arg;
only symbols for which the predicate returns non-NIL are included.
If BOUNDP is non-NIL, then only bound symbols are included. Similarly with FBOUNDP.
The symbols are printed unless DONT-PRINT is non-NIL.
A list of the symbols found is returned."
  (LET (RETURN-LIST
	(APROPOS-PREDICATE PREDICATE)
	(APROPOS-SUBSTRING SUBSTRING)
	(APROPOS-BOUNDP BOUNDP)
	(APROPOS-FBOUNDP FBOUNDP)
	(APROPOS-DONT-PRINT DONT-PRINT))
    (DECLARE (SPECIAL RETURN-LIST APROPOS-PREDICATE APROPOS-BOUNDP APROPOS-FBOUNDP
		      APROPOS-SUBSTRING APROPOS-DONT-PRINT))
    (MAPC #'APROPOS-1 STARTING-LIST)
    RETURN-LIST))

(DEFUN SYMEVAL-IN-CLOSURE (CLOSURE PTR)
  "Return the value which the symbol or value cell locative PTR has in CLOSURE.
More precisely, the value which is visible within CLOSURE is returned.
If CLOSURE does not contain a binding for it, the current value is returned."
  (CHECK-TYPE CLOSURE (OR CLOSURE ENTITY))
  (ETYPECASE PTR
    (SYMBOL (SETQ PTR (LOCF (SYMBOL-VALUE PTR))))
    (LOCATIVE))
  (DO ((L (CDR (%MAKE-POINTER DTP-LIST CLOSURE)) (CDDR L)))
      ((NULL L)
       (CAR PTR))
    (WHEN (EQ (CAR L) PTR)
      (RETURN (CAADR L)))))

(DEFUN BOUNDP-IN-CLOSURE (CLOSURE PTR &AUX PTR1)
  "T if the symbol or value cell locative PTR is BOUNDP within CLOSURE.
More precisely, the binding which is visible within CLOSURE is tested.
If CLOSURE does not contain a binding for it, the current binding is tested."
  (CHECK-TYPE CLOSURE (OR CLOSURE ENTITY))
  (ETYPECASE PTR
    (SYMBOL (SETQ PTR (LOCF (SYMBOL-VALUE PTR))))
    (LOCATIVE))
  (SETQ PTR1 (IF (SYMBOLP PTR) (LOCF (SYMBOL-VALUE PTR)) PTR))
  (DO ((L (CDR (%MAKE-POINTER DTP-LIST CLOSURE)) (CDDR L)))
      ((NULL L)
       (LOCATION-BOUNDP PTR1))
    (AND (EQ (CAR L) PTR1)
	 (RETURN (LOCATION-BOUNDP (CADR L))))))

(DEFUN MAKUNBOUND-IN-CLOSURE (CLOSURE PTR &AUX PTR1)
  "Make the symbol or value cell locative PTR unbound in CLOSURE.
More precisely, the binding which is visible within CLOSURE is made unbound.
If CLOSURE does not contain a binding for it, the current binding is made unbound."
  (CHECK-TYPE CLOSURE (OR CLOSURE ENTITY))
  (SETQ PTR1 (ETYPECASE PTR
	       (SYMBOL (LOCF (SYMBOL-VALUE PTR)))
	       (LOCATIVE PTR)))
  (DO ((L (CDR (%MAKE-POINTER DTP-LIST CLOSURE)) (CDDR L)))
      ((NULL L)
       (IF (SYMBOLP PTR)
	   (MAKUNBOUND PTR)
	   (LOCATION-MAKUNBOUND PTR)))
    (IF (EQ (CAR L) PTR1)
	(RETURN (LOCATION-MAKUNBOUND (CADR L)))))
  NIL)

(DEFUN LOCATE-IN-CLOSURE (CLOSURE PTR)
  "Return the location of the value which the symbol or value cell locative PTR has in CLOSURE.
More precisely, the location of the binding visible within CLOSURE is returned.
If CLOSURE does not contain a binding for it, the value cell
locative itself, or the symbol's value cell location, is returned."
  (CHECK-TYPE CLOSURE (OR CLOSURE ENTITY))
  (ETYPECASE PTR
    (SYMBOL (SETQ PTR (LOCF (SYMBOL-VALUE PTR))))
    (LOCATIVE))
  (DO ((L (CDR (%MAKE-POINTER DTP-LIST CLOSURE)) (CDDR L)))
      ((NULL L)
       PTR)
    (AND (EQ (CAR L) PTR)
	 (RETURN (CADR L)))))

(DEFUN SET-IN-CLOSURE (CLOSURE PTR VAL)
  "Set the value which the symbol or value cell locative PTR has in CLOSURE to VAL.
More precisely, the binding which is visible within CLOSURE is set.
If CLOSURE does not contain a binding for it, the current binding is set."
  (CHECK-TYPE CLOSURE (OR CLOSURE ENTITY))
  (ETYPECASE PTR
    (SYMBOL (SETQ PTR (LOCF (SYMBOL-VALUE PTR))))
    (LOCATIVE))
  (DO ((L (CDR (%MAKE-POINTER DTP-LIST CLOSURE)) (CDDR L)))
      ((NULL L)
       (SETF (CONTENTS PTR) VAL))
    (IF (EQ (CAR L) PTR)
	(RETURN (SETF (CONTENTS (CADR L)) VAL)))))

;;;; Here are some random functions for poking around in ENTITYs and CLOSUREs.

(DEFUN CLOSURE-VARIABLES (CLOSURE)
  "Return a list of variables closed over by CLOSURE."
  (CHECK-TYPE CLOSURE (OR ENTITY CLOSURE))
  (IF (AND (CDR (%MAKE-POINTER DTP-LIST CLOSURE))
	   (NULL (CDDR (%MAKE-POINTER DTP-LIST CLOSURE))))
      '(LEXICAL-ENVIRONMENT)
    (DO ((L (CDR (%MAKE-POINTER DTP-LIST CLOSURE)) (CDDR L))
	 (ANS NIL (CONS (%MAKE-POINTER-OFFSET DTP-SYMBOL (CAR L) -1) ANS)))
	((NULL L) ANS))))

(DEFUN CLOSURE-ALIST (CLOSURE)
  "Return an alist of variables closed over by CLOSURE vs their values they have inside it.
If one of the variables is unbound in the closure,
the corresponding cdr in the alist will also be a DTP-NULL.
Storing into the alist cdr's does not affect the values in the closure."
  (CHECK-TYPE CLOSURE (OR ENTITY CLOSURE))
  (IF (AND (CDR (%MAKE-POINTER DTP-LIST CLOSURE))
	   (NULL (CDDR (%MAKE-POINTER DTP-LIST CLOSURE))))
      `((LEXICAL-ENVIRONMENT . ,(CADR (%MAKE-POINTER DTP-LIST CLOSURE))))
    (DO ((L (CDR (%MAKE-POINTER DTP-LIST CLOSURE)) (CDDR L))
	 (ANS))
	((NULL L) ANS)
      ;; value-cell is offset 1 from symbol pointer
      (PUSH (CONS (%MAKE-POINTER-OFFSET DTP-SYMBOL (CAR L) -1) NIL) ANS)
      ;; Copy (CAADR L) into (CDAR ANS)
      (%BLT-TYPED (CADR L) (CDR-LOCATION-FORCE (CAR ANS)) 1 1))))

(DEFUN CLOSURE-FUNCTION (CLOSURE)
  "Return the function closed over in CLOSURE."
  (CHECK-TYPE CLOSURE (OR ENTITY CLOSURE))
  (CAR (%MAKE-POINTER DTP-LIST CLOSURE)))

(DEFUN CLOSURE-BINDINGS (CLOSURE)
  "Return the bindings of CLOSURE, shared with CLOSURE.
This is suitable for use in SYS:%USING-BINDING-INSTANCES."
  (CHECK-TYPE CLOSURE (OR ENTITY CLOSURE))
  (CDR (%MAKE-POINTER DTP-LIST CLOSURE)))
(DEFF CLOSURE-COPY 'COPY-CLOSURE)
(compiler:make-obsolete closure-copy "the new name is COPY-CLOSURE")

(DEFUN COPY-CLOSURE (CLOSURE &AUX CLOSURE1)
  "Return a new closure with the same function, variables and initial values as CLOSURE.
However, the new and old closures do not share the same external value cells."
  (CHECK-TYPE CLOSURE (OR ENTITY CLOSURE))
  (SETQ CLOSURE1 (%MAKE-POINTER DTP-LIST CLOSURE))
  (IF (AND (CDR (%MAKE-POINTER DTP-LIST CLOSURE))
	   (NULL (CDDR (%MAKE-POINTER DTP-LIST CLOSURE))))
      (%MAKE-POINTER DTP-CLOSURE (COPY-LIST CLOSURE1))
    (LET ((ANS (MAKE-LIST (LENGTH CLOSURE1))))
      (SETF (CAR ANS) (CAR CLOSURE1))		;Close over same fctn
      (DO ((L (CDR CLOSURE1) (CDDR L))
	   (N (CDR ANS) (CDDR N)))
	  ((NULL L) (%MAKE-POINTER (%DATA-TYPE CLOSURE) ANS))
	(SETF (CAR N) (CAR L))			;Same internal value cell
	(LET ((NEW-EXVC (MAKE-LIST 1)))
	  (IF (NOT (LOCATION-BOUNDP (CADR L)))
	      (LOCATION-MAKUNBOUND NEW-EXVC)
	    (SETF (CAR NEW-EXVC) (CAR (CADR L))))
	  (SETF (CADR N) NEW-EXVC))))))

(DEFVAR ARRAY-ORDER-INITIALIZATION-LIST NIL
  "Initialization list run after changing the value of ARRAY-INDEX-ORDER.")

(DEFUN MAKE-PIXEL-ARRAY (WIDTH HEIGHT &REST OPTIONS)
  "Make a pixel array of WIDTH by HEIGHT.  You must specify :TYPE as in MAKE-ARRAY.
This will create an array of the apropriate shape and knows whether
the height is supposed to be the first dimension or the second.
Access the resulting array with AR-2-REVERSE and AS-2-REVERSE to make sure
that accessing also is independent of array dimension order."
  (APPLY #'MAKE-ARRAY (LIST HEIGHT WIDTH) OPTIONS))

(DEFUN PIXEL-ARRAY-WIDTH (ARRAY)
  "Return the width in pixels of an array of pixels.
The width is the dimension which varies more faster."
  (ARRAY-DIMENSION ARRAY 1))

(DEFUN PIXEL-ARRAY-HEIGHT (ARRAY)
  "Return the height in pixels of an array of pixels.
The height is the dimension which varies more slowly."
  (ARRAY-DIMENSION ARRAY 0))

;;; VECTOR-POP, eventually to be micro-coded
;;; undoes (ARRAY-PUSH <ARRAY> <DATA>) and returns <DATA>
(DEFUN VECTOR-POP (ARRAY)
  "Returns the last used element of ARRAY, and decrements the fill pointer.
For an ART-Q-LIST array, the cdr codes are updated so that the overlayed list
no longer contains the element removed. Signals an error if ARRAY is empty
/(has fill-pointer 0)
Uses CLI:AREF, so will pop character objects out of strings."
  (WITHOUT-INTERRUPTS
    (LET* ((INDEX (1- (FILL-POINTER ARRAY)))	;1- because fill-pointer is # active elements
	   (ARRAY-TYPE (AREF (SYMBOL-FUNCTION 'ARRAY-TYPES)
			     (%P-LDB-OFFSET %%ARRAY-TYPE-FIELD ARRAY 0)))
	   VAL)
      (WHEN (MINUSP INDEX)
	(FERROR NIL "~S Overpopped" ARRAY))
      (SETQ VAL (CLI:AREF ARRAY INDEX))
      (SETF (FILL-POINTER ARRAY) INDEX)
      (WHEN (AND (EQ ARRAY-TYPE 'ART-Q-LIST)
		 (NOT (ZEROP INDEX)))
	(%P-DPB CDR-NIL %%Q-CDR-CODE (LOCF (AREF ARRAY (1- INDEX)))))
      VAL)))

(DEFUN ARRAY-POP (ARRAY)
  "Returns the last used element of ARRAY, and decrements the fill pointer.
For an ART-Q-LIST array, the cdr codes are updated so that the overlayed list
no longer contains the element removed. Signals an error if ARRAY is empty
/(has fill-pointer 0)
Uses GLOBAL:AREF, so will pop fixnums out of strings."
  (WITHOUT-INTERRUPTS
    (LET* ((INDEX (1- (FILL-POINTER ARRAY)))	;1- because fill-pointer is # active elements
	   (ARRAY-TYPE (AREF (SYMBOL-FUNCTION ARRAY-TYPES)
			     (%P-LDB-OFFSET %%ARRAY-TYPE-FIELD ARRAY 0)))
	   VAL)
      (WHEN (MINUSP INDEX)
	(FERROR NIL "~S Overpopped" ARRAY))
      (SETQ VAL (GLOBAL:AREF ARRAY INDEX))
      (SETF (FILL-POINTER ARRAY) INDEX)
      (WHEN (AND (EQ ARRAY-TYPE 'ART-Q-LIST)
		 (NOT (ZEROP INDEX)))
	(%P-DPB CDR-NIL %%Q-CDR-CODE (LOCF (AREF ARRAY (1- INDEX)))))
      VAL)))

;;; The following definitions of FILLARRAY and LISTARRAY should be completely
;;; compatible with Maclisp.  Slow, maybe, but compatible.

;;; When filling from an array, extra elements in the destination get the default initial
;;; value for the array type.  When filling from a list it sticks at the last element.
;;; Extra elements in the source are ignored.  copy-array-contents
;;; does the right thing for one-d arrays, but for multi-dimensional arrays
;;; uses column-major rather than row-major order.

(DEFRESOURCE FILLARRAY-INDEX-ARRAYS ()
  "Resource of vectors used by FILLARRAY and LISTARRAY"
  :CONSTRUCTOR (MAKE-ARRAY 8.)
  :INITIAL-COPIES 2)

(DEFUN FILLARRAY (ARRAY SOURCE)
  "Fill the contents of ARRAY from SOURCE.
If SOURCE is a list, its last element is repeated to fill any part of ARRAY left over.
If SOURCE is an array, elements of ARRAY not filled by SOURCE are left untouched.
If SOURCE is NIL, the array is filled with the default type for the array; this is 0 or NIL.
If ARRAY is NIL, a new list as big as SOURCE is created."
  (LET ((ARRAY (COND ((NULL ARRAY)
		     (SETQ ARRAY
			   (MAKE-ARRAY
			     (COND ((NULL SOURCE) 0)
				   ((CONSP SOURCE) (LENGTH SOURCE))
				   ((ARRAYP SOURCE) (ARRAY-DIMENSIONS SOURCE))
				   (T (FERROR NIL
					      "Unable to default destination array"))))))
		    ((AND (SYMBOLP ARRAY)
			  (FBOUNDP ARRAY)
			  (ARRAYP (SYMBOL-FUNCTION ARRAY)))
		     (SYMBOL-FUNCTION ARRAY))
		    (T ARRAY))))
    (CHECK-TYPE ARRAY ARRAY)
    (CHECK-TYPE SOURCE (OR ARRAY LIST))
    (LET ((DEST-NDIMS (ARRAY-RANK ARRAY))
	  (SOURCE-IS-AN-ARRAY-P (ARRAYP SOURCE)))
      (COND (SOURCE-IS-AN-ARRAY-P
	     (LET ((SOURCE-NDIMS (ARRAY-RANK SOURCE)))
	       (COND ((AND (= DEST-NDIMS 1)
			   (= SOURCE-NDIMS 1))
		      ;; 1d array into a 1d array is in microcode!
		      (LET ((N-ELEMENTS (MIN (ARRAY-LENGTH SOURCE)
					     (ARRAY-LENGTH ARRAY))))
			(COPY-ARRAY-PORTION SOURCE 0 N-ELEMENTS ARRAY 0 N-ELEMENTS)))
		     (T
		      ;; Hairy case, some array is multi-dimensional.
		      (USING-RESOURCE (SOURCE-INDEX-ARRAY FILLARRAY-INDEX-ARRAYS)
			(USING-RESOURCE (DEST-INDEX-ARRAY FILLARRAY-INDEX-ARRAYS)
			  (DOTIMES (I 10)
			    (SETF (AREF SOURCE-INDEX-ARRAY I) 0)
			    (SETF (AREF DEST-INDEX-ARRAY I) 0))
			  (LET ((SOURCE-ELEMENTS (ARRAY-LENGTH SOURCE))
				(DEST-ELEMENTS (ARRAY-LENGTH ARRAY)))
			    (DOTIMES (I (MIN SOURCE-ELEMENTS DEST-ELEMENTS))
			      (FILLARRAY-PUT (FILLARRAY-GET SOURCE
							    SOURCE-INDEX-ARRAY
							    SOURCE-NDIMS)
					     ARRAY DEST-INDEX-ARRAY DEST-NDIMS)))))))))
	    ((NULL SOURCE) (COPY-ARRAY-PORTION ARRAY 0 0 ARRAY 0 (ARRAY-LENGTH ARRAY)))
	    (T
	     ;; Source is a list.
	     (COND ((= DEST-NDIMS 1)
		    (DOTIMES (X (ARRAY-DIMENSION ARRAY 0))
		      (SETF (AREF ARRAY X) (CAR SOURCE))
		      (IF (NOT (NULL (CDR SOURCE))) (SETQ SOURCE (CDR SOURCE)))))
		   ((= DEST-NDIMS 2)
		    (DOTIMES (X (ARRAY-DIMENSION ARRAY 0))
		      (DOTIMES (Y (ARRAY-DIMENSION ARRAY 1))
			(SETF (AREF ARRAY X Y) (CAR SOURCE))
			(IF (NOT (NULL (CDR SOURCE))) (SETQ SOURCE (CDR SOURCE))))))
		   ((= DEST-NDIMS 3)
		    (DOTIMES (X (ARRAY-DIMENSION ARRAY 0))
		      (DOTIMES (Y (ARRAY-DIMENSION ARRAY 1))
			(DOTIMES (Z (ARRAY-DIMENSION ARRAY 2))
			  (SETF (AREF ARRAY X Y Z) (CAR SOURCE))
			  (IF (NOT (NULL (CDR SOURCE))) (SETQ SOURCE (CDR SOURCE)))))))
		   (T
		    (USING-RESOURCE (DEST-INDEX-ARRAY FILLARRAY-INDEX-ARRAYS)
		      (DOTIMES (I 8.)
			(SETF (AREF DEST-INDEX-ARRAY I) 0))
		      (DOTIMES (I (ARRAY-LENGTH ARRAY))
			(FILLARRAY-PUT (CAR SOURCE) ARRAY DEST-INDEX-ARRAY DEST-NDIMS)
			(IF (NOT (NULL (CDR SOURCE))) (SETQ SOURCE (CDR SOURCE))))))))))
    ARRAY))

(DEFUN FILLARRAY-GET (ARRAY INDEX-ARRAY NDIMS)
  (%OPEN-CALL-BLOCK ARRAY 0 1)			;d-stack
  (%ASSURE-PDL-ROOM NDIMS)
  (DOTIMES (I NDIMS)
    (%PUSH (GLOBAL:AREF INDEX-ARRAY I)))
  (%ACTIVATE-OPEN-CALL-BLOCK)
  (FILLARRAY-INCREMENT-INDEX ARRAY INDEX-ARRAY NDIMS)
  (%POP))

(DEFUN FILLARRAY-PUT (VALUE ARRAY INDEX-ARRAY NDIMS)
  (%OPEN-CALL-BLOCK #'ASET 0 0)			;d-ignore
  (%ASSURE-PDL-ROOM (+ 2 NDIMS))
  (%PUSH VALUE)
  (%PUSH ARRAY)
  (DOTIMES (I NDIMS)
    (%PUSH (GLOBAL:AREF INDEX-ARRAY I)))
  (%ACTIVATE-OPEN-CALL-BLOCK)
  (FILLARRAY-INCREMENT-INDEX ARRAY INDEX-ARRAY NDIMS))

(DEFUN FILLARRAY-INCREMENT-INDEX (ARRAY INDEX-ARRAY NDIMS)
  (DO ((DIM (1- NDIMS) (1- DIM)))
      ((< DIM 0))
    (LET ((VAL (1+ (GLOBAL:AREF INDEX-ARRAY DIM))))
      (COND ((< VAL (ARRAY-DIMENSION ARRAY DIM))
	     (SETF (AREF INDEX-ARRAY DIM) VAL)
	     (RETURN))
	    (T
	     (SETF (AREF INDEX-ARRAY DIM) 0))))))

;;; LISTARRAY of a one-dimensional array respects the fill pointer, but
;;; for multi-dimensional arrays it ignores the fill pointer.
(DEFUN LISTARRAY (ARRAY &OPTIONAL LIMIT)
  "Return a list of the elements of ARRAY, up to index LIMIT.
If LIMIT is NIL, the array size is used; for one-dimensional arrays,
the fill pointer is used if there is one.
Uses GLOBAL:AREF, so will get fixnums out of strings."
  (IF (AND (SYMBOLP ARRAY)
	   (FBOUNDP ARRAY)
	   (ARRAYP (SYMBOL-FUNCTION ARRAY)))
      (SETQ ARRAY (SYMBOL-FUNCTION ARRAY)))
  (CHECK-TYPE ARRAY ARRAY)
  (CHECK-TYPE LIMIT (OR NULL INTEGER))
  (LET* ((NDIMS (ARRAY-RANK ARRAY))
	 (ELEMENTS (IF (= NDIMS 1)
		       (ARRAY-ACTIVE-LENGTH ARRAY)
		       (ARRAY-LENGTH ARRAY)))
	 (TIMES (IF (NULL LIMIT)
		    ELEMENTS
		    (MIN LIMIT ELEMENTS)))
	 (LIST (MAKE-LIST TIMES))
	 (L LIST)
	 (COUNT 0))
    (COND ((= NDIMS 1)
	   (DOTIMES (X (ARRAY-ACTIVE-LENGTH ARRAY))
	     (SETQ COUNT (1+ COUNT))
	     (IF (> COUNT TIMES)
		 (RETURN))
	     (SETF (CAR L) (GLOBAL:AREF ARRAY X))
	     (SETQ L (CDR L))))
	  ((= NDIMS 2)
	   (DOTIMES (X (ARRAY-DIMENSION ARRAY 0))
	     (DOTIMES (Y (ARRAY-DIMENSION ARRAY 1))
	       (SETQ COUNT (1+ COUNT))
	       (IF (> COUNT TIMES)
		   (RETURN))
	       (SETF (CAR L) (GLOBAL:AREF ARRAY X Y))
	       (SETQ L (CDR L)))))
	  ((= NDIMS 3)
	   (DOTIMES (X (ARRAY-DIMENSION ARRAY 0))
	     (DOTIMES (Y (ARRAY-DIMENSION ARRAY 1))
	       (DOTIMES (Z (ARRAY-DIMENSION ARRAY 2))
		 (SETQ COUNT (1+ COUNT))
		 (IF (> COUNT TIMES)
		     (RETURN))
		 (SETF (CAR L) (GLOBAL:AREF ARRAY X Y Z))
		 (SETQ L (CDR L))))))
	  (T
	   (USING-RESOURCE (INDEX-ARRAY FILLARRAY-INDEX-ARRAYS)
	     (DOTIMES (I 10) (SETF (AREF INDEX-ARRAY I) 0))
	     (DOTIMES (I TIMES)
	       (SETF (CAR L) (FILLARRAY-GET ARRAY INDEX-ARRAY NDIMS))
	       (SETQ L (CDR L))))))
    LIST))

(DEFUN LIST-ARRAY-LEADER (ARRAY &OPTIONAL LIMIT)
  "Return a list of the contents of ARRAY's leader, up to LIMIT."
  (IF (AND (SYMBOLP ARRAY)
	   (FBOUNDP ARRAY)
	   (ARRAYP (SYMBOL-FUNCTION ARRAY)))
      (SETQ ARRAY (SYMBOL-FUNCTION ARRAY)))
  (CHECK-TYPE ARRAY ARRAY)
  (IF (NULL LIMIT)
      (SETQ LIMIT (OR (ARRAY-LEADER-LENGTH ARRAY) 0)))
  (LET ((LIST (MAKE-LIST LIMIT)))
    (DO ((I 0 (1+ I))
	 (L LIST (CDR L)))
	(( I LIMIT)
	 LIST)
      (SETF (CAR L) (ARRAY-LEADER ARRAY I)))))

;;; isn't compatibility wonderful?
;(DEFVAR *RSET NIL)
;(DEFUN *RSET (&OPTIONAL (NEW-MODE T))
;  (SETQ *RSET NEW-MODE))

(DEFF ARRAY-/#-DIMS 'ARRAY-RANK)
(COMPILER:MAKE-OBSOLETE ARRAY-/#-DIMS "use ARRAY-RANK")

(COMPILER:MAKE-OBSOLETE ARRAY-DIMENSION-N
			 "use ARRAY-DIMENSION (with a different calling sequence)")
(DEFUN ARRAY-DIMENSION-N (N ARRAY)
  "Return the length of dimension N of ARRAY.  The first dimension is N=1.
If N is 0, the leader length is returned.  Use ARRAY-LEADER-LENGTH instead."
  (CHECK-TYPE ARRAY ARRAY)
  (COND ((> N (ARRAY-RANK ARRAY))
	 NIL)
	((NOT (PLUSP N))
	 (ARRAY-LEADER-LENGTH ARRAY))
	(T
	 (ARRAY-DIMENSION ARRAY (1- N)))))

;;microcoded now.
;(DEFUN ARRAY-RANK (ARRAY)
;  "Return the number of dimensions ARRAY has."
;  (CHECK-ARG ARRAY ARRAYP "an array")
;  (%P-LDB-OFFSET %%ARRAY-NUMBER-DIMENSIONS ARRAY 0))

(DEFUN DATA-TYPE (X)
  "Return the name for the data type of X."
  (AREF #'Q-DATA-TYPES (%DATA-TYPE X)))

;;; Facilities for looking through all functions in the world
;;; and finding out what they do.

(DEFUN WHO-CALLS (SYMBOL &OPTIONAL PKG (INHERITORS T) (INHERITED T))
  "Find all symbols in package PKG whose values, definitions or properties use SYMBOL.
PKG defaults to NIL, which means search all packages.
The packages which inherit from PKG are processed also, unless INHERITORS is NIL.
The packages PKG inherits from are processed also, unless INHERITED is NIL.
/(Other packages which merely inherit from the same ones are NOT processed.)
The symbols are printed and a list of them is returned."
  (LET ((RETURN-LIST ()))
    (FIND-CALLERS-OF-SYMBOLS SYMBOL PKG
      #'(LAMBDA (CALLER CALLEE HOW)
	  (FORMAT T "~&~S" CALLER)
	  (FORMAT T (CASE HOW
		      (:VARIABLE " uses ~S as a variable.")
		      (:FUNCTION " calls ~S as a function.")
		      (:MISC-FUNCTION " calls ~S via a 'misc' instruction.")
		      (:CONSTANT " uses ~S as a constant.")
		      (:FLAVOR " uses ~S's flavor definition.")
		      (:UNBOUND-FUNCTION " calls ~S, an undefined function.")
		      (NIL ", an interpreted function, uses ~S somehow."))
		  CALLEE)
	  (PUSHNEW CALLER RETURN-LIST :TEST #'EQ))
      INHERITORS INHERITED)
    RETURN-LIST))
(DEFF WHO-USES 'WHO-CALLS)			;old bogus name

(DEFUN WHAT-FILES-CALL (SYMBOL-OR-SYMBOLS &OPTIONAL PKG (INHERITORS T) (INHERITED T))
  "Find all files in package PKG which use SYMBOL.
PKG defaults to NIL, which means search all packages.
The packages which inherit from PKG are processed also, unless INHERITORS is NIL.
The packages PKG inherits from are processed also, unless INHERITED is NIL.
/(Other packages which merely inherit from the same ones are NOT processed.)
The files are printed and a list of them is returned."
  (LET ((L NIL))
    (FIND-CALLERS-OF-SYMBOLS SYMBOL-OR-SYMBOLS PKG
       #'(LAMBDA (CALLER IGNORE IGNORE)
	   (AND (SETQ CALLER (GET-SOURCE-FILE-NAME CALLER 'DEFUN))
		(NOT (MEMQ CALLER L))
		(PUSHNEW CALLER L :TEST #'EQ)))
       INHERITORS INHERITED)
    L))

(DEFUN FIND-CALLERS-OF-SYMBOLS (SYMBOL PKG FUNCTION
				&OPTIONAL (INHERITORS T) (INHERITED T))
  "This is the main driving function for WHO-CALLS and friends.
Looks at all symbols in PKG and USErs (if INHERITORS is T)
and the ones it USEs (if INHERITED is T).
If PKG is NIL, looks at all packages.
Looks at each symbol's function definition and if it
refers to SYMBOL calls FUNCTION with the function name, the symbol used,
and the type of use (:VARIABLE, :FUNCTION, :MISC-FUNCTION,
 :CONSTANT, :UNBOUND-FUNCTION, :FLAVOR,
 or NIL if used in an unknown way in an interpreted function.)
SYMBOL can be a single symbol or a list of symbols.
The symbol :UNBOUND-FUNCTION is treated specially."
  (DECLARE (SPECIAL SYMBOL FUNCTION))
  ;; Sorting first, in order of function definitions, didn't help much when
  ;; tried in the previous generation of this function.
  (WHEN PKG (SETQ PKG (PKG-FIND-PACKAGE PKG)))
  (CHECK-ARG SYMBOL
	     (OR (SYMBOLP SYMBOL)
		 (LOOP FOR SYM IN SYMBOL ALWAYS (SYMBOLP SYM)))
	     "a symbol or a list of symbols")
  (IF (SYMBOLP SYMBOL)
      (SETQ SYMBOL (ADD-SYMBOLS-OPTIMIZED-INTO SYMBOL (LIST SYMBOL)))
    (DOLIST (SYM SYMBOL)
      (SETQ SYMBOL (ADD-SYMBOLS-OPTIMIZED-INTO SYM SYMBOL))))
  (COND (PKG
	 (MAPATOMS #'FIND-CALLERS-OF-SYMBOLS-AUX PKG INHERITED)
	 (AND INHERITORS
	      (DOLIST (P (PACKAGE-USED-BY-LIST PKG))
		(MAPATOMS #'FIND-CALLERS-OF-SYMBOLS-AUX P NIL))))
	(T (DOLIST (P *ALL-PACKAGES*)
	     (MAPATOMS #'FIND-CALLERS-OF-SYMBOLS-AUX P NIL))))
  NIL)

(DEFUN ADD-SYMBOLS-OPTIMIZED-INTO (SYM LIST)
  (IF (SYMBOLP LIST) (SETQ LIST (LIST LIST)))
  (DOLIST (SYM1 (GET SYM 'COMPILER::OPTIMIZED-INTO))
    (UNLESS (MEMQ SYM1 LIST)
      (SETQ LIST (ADD-SYMBOLS-OPTIMIZED-INTO SYM1 (CONS SYM1 LIST)))))
  LIST)

(DEFUN FIND-CALLERS-OF-SYMBOLS-AUX (CALLER &AUX FL)
  (DECLARE (SPECIAL SYMBOL FUNCTION))
  ;; Ignore all symbols which are forwarded to others, to avoid duplication.
  (AND ( (%P-LDB-OFFSET %%Q-DATA-TYPE CALLER 2) DTP-ONE-Q-FORWARD)
       (FBOUNDP CALLER)
       (FIND-CALLERS-OF-SYMBOLS-AUX1 CALLER (SYMBOL-FUNCTION CALLER)))
  (UNLESS (= (%P-LDB-OFFSET %%Q-DATA-TYPE CALLER 3) DTP-ONE-Q-FORWARD)
    ;; Also look for properties
    (DO ((L (PLIST CALLER) (CDDR L)))
	((NULL L))
      (IF (TYPEP (CADR L) 'COMPILED-FUNCTION)
	  (FIND-CALLERS-OF-SYMBOLS-AUX-FEF
	    (LIST :PROPERTY CALLER (CAR L)) (CADR L))))
    ;; Also look for flavor methods
    (AND (SETQ FL (GET CALLER 'SI:FLAVOR))
	 (ARRAYP FL)				;Could be T
	 (DOLIST (MTE (FLAVOR-METHOD-TABLE FL))
	   (DOLIST (METH (CDDDR MTE))
	     (IF (METH-DEFINEDP METH)
		 (FIND-CALLERS-OF-SYMBOLS-AUX1 (METH-FUNCTION-SPEC METH)
					       (METH-DEFINITION METH))))))
    ;; Also look for initializations
    (IF (GET CALLER 'INITIALIZATION-LIST)
	;; It is an initialization list.
	(DOLIST (INIT-LIST-ENTRY (SYMBOL-VALUE CALLER))
	  (FIND-CALLERS-OF-SYMBOLS-AUX-LIST CALLER (INIT-FORM INIT-LIST-ENTRY))))))

(DEFUN FIND-CALLERS-OF-SYMBOLS-AUX1 (CALLER DEFN)
  (DECLARE (SPECIAL SYMBOL FUNCTION))
  ;; Don't be fooled by macros, interpreted or compiled.
  (IF (EQ (CAR-SAFE DEFN) 'MACRO) (SETQ DEFN (CDR DEFN)))
  (TYPECASE DEFN
    (COMPILED-FUNCTION (FIND-CALLERS-OF-SYMBOLS-AUX-FEF CALLER DEFN))
    (:LIST (FIND-CALLERS-OF-SYMBOLS-AUX-LAMBDA CALLER DEFN))
    (SELECT (FIND-CALLERS-OF-SYMBOLS-AUX-LIST CALLER (%MAKE-POINTER DTP-LIST DEFN))))
  ;; this function is traced, advised, etc.
  ;; then look through the actual definition.
  (IF (OR (CONSP DEFN) (TYPEP DEFN 'COMPILED-FUNCTION))
      (LET* ((DEBUG-INFO (FUNCTION-DEBUGGING-INFO DEFN))
	     (INNER (ASSQ 'SI:ENCAPSULATED-DEFINITION DEBUG-INFO)))
	(AND INNER (FIND-CALLERS-OF-SYMBOLS-AUX (CADR INNER))))))
		 
(DEFUN FIND-CALLERS-OF-SYMBOLS-AUX-FEF (CALLER DEFN &AUX TEM OFFSET SYM)
  (DECLARE (SPECIAL SYMBOL FUNCTION))
  (DO ((I %FEF-HEADER-LENGTH (1+ I))
       (LIM (TRUNCATE (FEF-INITIAL-PC DEFN) 2)))
      (( I LIM) NIL)
    (COND ((= (%P-LDB-OFFSET %%Q-DATA-TYPE DEFN I) DTP-EXTERNAL-VALUE-CELL-POINTER)
	   (SETQ TEM (%P-CONTENTS-AS-LOCATIVE-OFFSET DEFN I)
		 SYM (%FIND-STRUCTURE-HEADER TEM)
		 OFFSET (%POINTER-DIFFERENCE TEM SYM))
	   (COND ((NOT (SYMBOLP SYM)))
		 ((= OFFSET 2)			;Function cell reference
		  (IF (IF (ATOM SYMBOL) (EQ SYM SYMBOL) (MEMQ SYM SYMBOL))
		      (FUNCALL FUNCTION CALLER SYM :FUNCTION)
		      (AND (IF (ATOM SYMBOL) (EQ :UNBOUND-FUNCTION SYMBOL)
			       (MEMQ :UNBOUND-FUNCTION SYMBOL))
			   (NOT (FBOUNDP SYM))
			   (FUNCALL FUNCTION CALLER SYM :UNBOUND-FUNCTION))))
		 (T				;Value reference presumably
		  (IF (IF (ATOM SYMBOL) (EQ SYM SYMBOL) (MEMQ SYM SYMBOL))
		      (FUNCALL FUNCTION CALLER SYM :VARIABLE)))))
	  ((= (%P-LDB-OFFSET %%Q-DATA-TYPE DEFN I) DTP-SELF-REF-POINTER)
	   (LET* ((FN (FEF-FLAVOR-NAME DEFN)))
	     (IF FN
		 (MULTIPLE-VALUE-BIND (SYM USE)
		     (FLAVOR-DECODE-SELF-REF-POINTER FN (%P-LDB-OFFSET %%Q-POINTER DEFN I))
		   (IF (OR (EQ SYM SYMBOL)
			   (AND (CONSP SYMBOL) (MEMQ SYM SYMBOL)))
		       (FUNCALL FUNCTION CALLER SYM
				(IF USE :FLAVOR :VARIABLE)))))))
	  ((SYMBOLP (SETQ SYM (%P-CONTENTS-OFFSET DEFN I)))
	   (IF (IF (ATOM SYMBOL) (EQ SYM SYMBOL) (MEMQ SYM SYMBOL))
	       (FUNCALL FUNCTION CALLER SYM :CONSTANT)))))
  ;; See if the fef uses the symbol as a macro.
  (LET ((DI (DEBUGGING-INFO DEFN)))
    (DOLIST (M (CADR (ASSQ :MACROS-EXPANDED DI)))
      (IF (IF (ATOM SYMBOL)
	      (EQ SYMBOL (IF (CONSP M) (CAR M) M))
	    (MEMQ (IF (CONSP M) (CAR M) M) SYMBOL))
	  (FUNCALL FUNCTION CALLER SYMBOL :MACRO))))
  ;; See if we have a function reference compiled into a misc instruction
  (IF (SYMBOLP SYMBOL)
      (IF (FEF-CALLS-MISC-FUNCTION DEFN SYMBOL)
	  (FUNCALL FUNCTION CALLER SYMBOL :MISC-FUNCTION))
      (DOLIST (SYM SYMBOL)
	(IF (FEF-CALLS-MISC-FUNCTION DEFN SYM)
	    (FUNCALL FUNCTION CALLER SYM :MISC-FUNCTION))))
  (AND (LDB-TEST %%FEFHI-MS-DEBUG-INFO-PRESENT
		 (%P-CONTENTS-OFFSET DEFN %FEFHI-MISC))
       (SETQ TEM (CDR (ASSQ :INTERNAL-FEF-OFFSETS
			    (%P-CONTENTS-OFFSET DEFN (1- (%P-LDB %%FEFH-PC-IN-WORDS DEFN))))))
       (LOOP FOR OFFSET IN TEM
	     FOR I FROM 0
	     DO (FIND-CALLERS-OF-SYMBOLS-AUX-FEF `(:INTERNAL ,CALLER ,I)
						 (%P-CONTENTS-OFFSET DEFN OFFSET)))))

;;; See if this FEF uses a certain MISC instruction
(DEFUN FEF-CALLS-MISC-FUNCTION (FEF SYM &AUX TEM INST)
  (AND (GET SYM 'COMPILER::QINTCMP)
       (SETQ TEM (GET SYM 'COMPILER::QLVAL))
       (DO ((MISCINST				;Misc instruction sought
	      (IF ( TEM #o1000)
		  (+ #o35_11 (LOGAND #o777 TEM))
		(+ #o15_11 TEM)))
	    (MISCMASK #o37777)			;Masks out destination
	    (LONGJUMP #o14777)			;First word of 2-word jump instruction
	    (LONGJUMP1 #o34777)			;First word of 2-word jump instruction
	    (PC (FEF-INITIAL-PC FEF) (1+ PC))
	    (MAXPC (* (FEF-LENGTH FEF) 2)))
	   (( PC MAXPC) NIL)
	 (SETQ INST (LOGAND (%P-LDB-OFFSET (IF (ODDP PC) %%Q-HIGH-HALF %%Q-LOW-HALF)
					   FEF (TRUNCATE PC 2))
			    MISCMASK))
	 (COND ((= INST MISCINST) (RETURN T))
	       ((= INST LONGJUMP) (INCF PC))
	       ((= INST LONGJUMP1) (INCF PC))))))

;;; Tree-walk CALLER looking for FUNCTION.  CALLER should be the function name,
;;; and DEFN should be its definition.  Avoids listing symbols twice.
(DEFUN FIND-CALLERS-OF-SYMBOLS-AUX-LIST (CALLER DEFN)
  (LET ((SUPPRESS NIL))
    (DECLARE (SPECIAL SUPPRESS))
    (FIND-CALLERS-OF-SYMBOLS-AUX-LIST1 CALLER DEFN)))

(DEFUN FIND-CALLERS-OF-SYMBOLS-AUX-LAMBDA (CALLER DEFN)
  (DECLARE (SPECIAL SYMBOL FUNCTION))
  (LET ((SUPPRESS NIL))
    (DECLARE (SPECIAL SUPPRESS))
    (FIND-CALLERS-OF-SYMBOLS-AUX-LIST1 CALLER (LAMBDA-EXP-ARGS-AND-BODY DEFN))))

(DEFUN FIND-CALLERS-OF-SYMBOLS-AUX-LIST1 (CALLER DEFN)
  (DECLARE (SPECIAL SUPPRESS))
  (DECLARE (SPECIAL SYMBOL FUNCTION))
  (DO ((L DEFN (CDR L)))
      ((ATOM L))
    (COND ((AND (SYMBOLP (CAR L))
		(NOT (MEMQ (CAR L) SUPPRESS))
		(IF (ATOM SYMBOL) (EQ (CAR L) SYMBOL) (MEMQ (CAR L) SYMBOL)))
	   (PUSH (CAR L) SUPPRESS)
	   (FUNCALL FUNCTION CALLER (CAR L) NIL))
	  ((CONSP (CAR L))
	   (FIND-CALLERS-OF-SYMBOLS-AUX-LIST1 CALLER (CAR L))))))

(DEFUN %MAKE-PAGE-READ-ONLY (P)
  "Make virtual page at address P read only.  Lasts only until it is swapped out!"
  (%CHANGE-PAGE-STATUS P NIL (DPB 2 #o0603 (LDB %%REGION-MAP-BITS	;Change map-status
						(REGION-BITS (%REGION-NUMBER P))))))

;;;; MAR-hacking functions

(DEFUN CLEAR-MAR ()
  "Clear out the mar setting."
  (DO ((P %MAR-LOW (+ P #o200)))
      ((> P %MAR-HIGH)) ;TROUBLE WITH NEGATIVE NUMBERS HERE!
    (%CHANGE-PAGE-STATUS P NIL (LDB %%REGION-MAP-BITS
				    (REGION-BITS (%REGION-NUMBER P)))))
  (SETQ %MAR-LOW -1
	%MAR-HIGH -2
	%MODE-FLAGS (%LOGDPB 0 %%M-FLAGS-MAR-MODE %MODE-FLAGS))
  NIL)

;;;Not GC-safe, additional hair required, also negative number trouble
(DEFUN SET-MAR (LOCATION CYCLE-TYPE &OPTIONAL (N-WORDS 1))
					;N-WORDS SHOULD DEFAULT TO (SIZE LOCATION)
  "Set trap on reference to N-WORDS words starting at LOCATION.
N-WORDS defaults to 1.  CYCLE-TYPE is T, :READ or :WRITE."
  (SETQ CYCLE-TYPE (ECASE CYCLE-TYPE
		     (:READ 1)
		     (:WRITE 2)
		     ((T) 3)))
  (CLEAR-MAR)					;Clear old mar
  (SETQ %MAR-HIGH (+ (1- N-WORDS) (SETQ %MAR-LOW (%POINTER LOCATION))))
  ;; If MAR'ed pages are in core, set up their traps
  (DO ((P %MAR-LOW (+ P #o200)))
      ((> P %MAR-HIGH))
    (%CHANGE-PAGE-STATUS P NIL (DPB 6 #o0604 (LDB %%REGION-MAP-BITS  ;CHANGE MAP-STATUS
						  (REGION-BITS (%REGION-NUMBER P))))))
  (SETQ %MODE-FLAGS (%LOGDPB CYCLE-TYPE %%M-FLAGS-MAR-MODE %MODE-FLAGS))	;Energize!
  T)

(DEFUN MAR-MODE ()
  (LET ((MODE (LDB %%M-FLAGS-MAR-MODE %MODE-FLAGS)))
    (CASE MODE
      (0 NIL)
      (1 :READ)
      (2 :WRITE)
      (3 T)
      (OTHERWISE (FERROR NIL "The MAR mode, ~D, is invalid." MODE)))))

(DEFUN DEL-IF-NOT (PRED LIST)
  "Destructively remove all elements of LIST that don't satisfy PRED."
  (PROG (LST OLST)
     A	(COND ((ATOM LIST) (RETURN LIST))
	      ((FUNCALL PRED (CAR LIST)))
	      (T
	       (SETQ LIST (CDR LIST))
	       (GO A)))
	(SETQ OLST (SETQ LST LIST))
     B  (SETQ LST (CDR LST))
	(COND ((ATOM LST) (RETURN LIST))
	      ((FUNCALL PRED (CAR LST))
	       (SETQ OLST LST))
	      (T
	       (SETF (CDR OLST) (CDR LST))))
	(GO B)))

(DEFUN DEL-IF (PRED LIST)
  "Destructively remove all elements of LIST that satisfy PRED."
  (PROG (LST OLST)
     A  (COND ((ATOM LIST) (RETURN LIST))
	      ((FUNCALL PRED (CAR LIST))
	       (SETQ LIST (CDR LIST))
	       (GO A)))
	(SETQ OLST (SETQ LST LIST))
     B  (SETQ LST (CDR LST))
	(COND ((ATOM LST) (RETURN LIST))
	      ((FUNCALL PRED (CAR LST))
	       (SETF (CDR OLST) (CDR LST)))
	      (T
	       (SETQ OLST LST)))
	(GO B)))

(DEFUN HAIPART (X N &AUX TEM)
  "Return N significant bits of the absolute value of X.
N > 0 means high N bits; N < 0 means low -N bits.
If X is too small, all of it is returned."
  ;; Get number of significant bits
  (SETQ TEM (HAULONG (SETQ X (ABS X))))
  ;; Positive N means get high N bits, or as many as there are
  (COND	((> N 0)				;minus number of low bits to discard
	 (SETQ TEM (- N TEM))
	 (IF (< TEM 0)
	     (ASH X TEM)
	   X))
	;; Zero N means return no bits
	((= N 0) 0)
	;; Negative N means get low -N bits, or as many as there are
	((< (SETQ N (MINUS N)) TEM)
	 (\ X (ASH 1 N)))
	(T X)))

(DEFUN MEXP (&OPTIONAL FORM &AUX EXP)
  "Read-macroexpand-print loop, for seeing how macros expand.
MEXP reads s-expressions and macroexpands each one, printing the expansion.
Type NIL to exit (or Abort)."
  (DO-FOREVER
    (UNLESS FORM
      (FORMAT T "~2%Macro form ")
      (SEND *STANDARD-INPUT* :UNTYI (SEND *STANDARD-INPUT* :TYI)))	;Allow abort to exit
    (CATCH-ERROR-RESTART ((SYS:ABORT ERROR) "Return to MEXP input loop.")
      (SETQ EXP (OR FORM (READ-FOR-TOP-LEVEL)))
      (AND (SYMBOLP EXP) (RETURN NIL))
      (DO ((LAST NIL EXP))
	  ((EQ EXP LAST))
	(SETQ EXP (MACROEXPAND-1 EXP))
	(PRINC "  ")
	(GRIND-TOP-LEVEL EXP))
      (UNLESS (EQUAL EXP (SETQ EXP (MACROEXPAND-ALL EXP)))
	(PRINC "  ")
	(GRIND-TOP-LEVEL EXP)))
    (WHEN FORM (RETURN '*))))



;;;; STATUS and SSTATUS 
;;; Note that these have to be Maclisp compatible and therefore have to work
;;; independent of packages.  All symbols on feature lists are in the keyword package.

;;; status and sstaus are obsolete.
;;; Instead, frob the special variable *features* directly

(DEFVAR *FEATURES*
	'(:LISPM :MIT :LMI :COMMON	;":common" is what dec prolelisp says it is
	  :CHAOS :SORT :FASLOAD :STRING :NEWIO :ROMAN :TRACE :GRINDEF :GRIND))

(DEFUN PROB-FROCESSOR ()
  (PUSHNEW
    (SELECT-PROCESSOR
      (:CADR :CADR)
      (:LAMBDA :LAMBDA))
    *FEATURES*))

(ADD-INITIALIZATION "Frob *FEATURES* per processor" '(PROB-FROCESSOR) :COLD)

(DEFVAR STATUS-STATUS-LIST '(:FEATURE :FEATURES :NOFEATURE :STATUS :SSTATUS :TABSIZE
			     :USERID :SITE :OPSYS))

(DEFVAR STATUS-SSTATUS-LIST '(:FEATURE :NOFEATURE))

(DEFUN RETURN-STATUS (STATUS-LIST ITEM ITEM-P)
       (COND ((NOT ITEM-P) STATUS-LIST)
	     ((NUMBERP ITEM) (MEMBER-EQUAL ITEM STATUS-LIST))
	     (T (NOT (NULL (MEM #'STRING-EQUAL ITEM STATUS-LIST))))))

(DEFUN STATUS (&QUOTE STATUS-FUNCTION &OPTIONAL (ITEM NIL ITEM-P))
  "Obsolete Maclisp function. You really want to use the value of, or bind, *FEATURES*.
/(STATUS FEATURES) returns a list of symbols indicating features of the
Lisp environment. 
/(STATUS FEATURE SYMBOL) returns T if SYMBOL is on the (STATUS FEATURES)
list,  otherwise NIL.
/(STATUS NOFEATURE SYMBOL) returns T if SYMBOL in *FEATURES*, otherwise NIL.
/(STATUS STATUS) returns a list of all status operations, ie *FEATURES*.
/(STATUS SSTATUS) returns a list of all sstatus operations."
  (SELECTOR STATUS-FUNCTION STRING-EQUAL
    (('FEATURE 'FEATURES) (RETURN-STATUS *FEATURES* ITEM ITEM-P))
    (('NOFEATURE) (UNLESS ITEM-P
		    (FERROR NIL "Too few args to STATUS NOFEATURE."))
		  (NOT (RETURN-STATUS *FEATURES* ITEM ITEM-P)))
    (('STATUS) (RETURN-STATUS STATUS-STATUS-LIST ITEM ITEM-P))
    (('SSTATUS) (RETURN-STATUS STATUS-SSTATUS-LIST ITEM ITEM-P))
    (('TABSIZE) 8.)
    (('USERID) USER-ID)
    (('SITE) LOCAL-HOST-NAME)
    (('OPSYS) :LISPM)
    (OTHERWISE (FERROR NIL "~S is not a legal STATUS request." STATUS-FUNCTION))))

(DEFUN SSTATUS (&QUOTE STATUS-FUNCTION ITEM
		&AUX (DEFAULT-CONS-AREA WORKING-STORAGE-AREA))
  "(SSTATUS FEATURE ITEM) adds ITEM to the list of features.
/(SSTATUS NOFEATURE ITEM) removes ITEM from the list of features.
New programs should use the variable *FEATURES*"
  (IF (SYMBOLP ITEM)
      (SETQ ITEM (INTERN (STRING ITEM) PKG-KEYWORD-PACKAGE)))	;These are all keywords
  (SELECTOR STATUS-FUNCTION STRING-EQUAL
    (('FEATURE) (PUSHNEW ITEM *FEATURES* :TEST #'EQUAL)
		ITEM)
    (('NOFEATURE) (IF (SI:MEMBER-EQUAL ITEM *FEATURES*)
		      (SETQ *FEATURES* (DEL #'EQUAL ITEM *FEATURES*)))
		  ITEM)
    (OTHERWISE (FERROR NIL "~S is not a legal SSTATUS request." STATUS-FUNCTION))))

;;;; Site stuff

(DEFUN UPDATE-SITE-CONFIGURATION-INFO ()
  "Read the latest site configuration files, including the host table."
  (MAYBE-MINI-LOAD-FILE-ALIST SITE-FILE-ALIST)
  (INITIALIZATIONS 'SITE-INITIALIZATION-LIST T)
  (SET-LOCAL-HOST-VARIABLES))  ;Runs SITE-OPTION-INITIALIZATION-LIST

(DEFVAR SITE-NAME NIL)
(DEFVAR SITE-OPTION-ALIST NIL
  "Alist of site option keywords as specified in SYS:SITE;SITE LISP")

(DEFVAR HOST-OVERRIDDEN-SITE-OPTION-ALIST NIL
  "Alist of site-keywords overridden on a per-machine basis,
as specified in SYS:SITE;LMLOCS LISP")

(DEFVAR SITE-INITIALIZATION-LIST NIL
  "Initializations run after new site tables are loaded.")

(DEFVAR SITE-OPTION-INITIALIZATION-LIST NIL
  "Initializations run when site options change
/(after loading new site tables and after warm boot).")

(DEFMACRO DEFSITE (SITE &BODY OPTIONS)
  "DEFSITE is used only in the file SYS:SITE;SITE LISP."
  `(DEFSITE-1 ',SITE ',OPTIONS))

(DEFUN DEFSITE-1 (NEW-SITE OPTIONS)
  (SETQ SITE-NAME NEW-SITE)
  (SETQ SITE-OPTION-ALIST (LOOP FOR (KEY EXP) IN OPTIONS
				COLLECT `(,KEY . ,(EVAL EXP)))))

(DEFUN GET-SITE-OPTION (KEY)
  "Return the value at this site for site option KEY (a symbol in the keyword package).
The values of site options are specified in the file SYS:SITE;SITE LISP."
  (CDR (OR (ASSQ KEY HOST-OVERRIDDEN-SITE-OPTION-ALIST)
	   (ASSQ KEY SITE-OPTION-ALIST))))

(DEFMACRO DEFINE-SITE-VARIABLE (VAR KEY &OPTIONAL DOCUMENTATION)
  "Define a variable whose value is automatically updated from the site option KEY's value."
  `(PROGN
     ,(IF DOCUMENTATION
	  `(DEFVAR ,VAR :UNBOUND ,DOCUMENTATION)
	`(DEFVAR ,VAR))
     (ADD-INITIALIZATION ,(FORMAT NIL "SITE:~A" VAR)
			 `(SETQ ,',VAR (GET-SITE-OPTION ',',KEY))
			 '(SITE-OPTION))))

(DEFMACRO DEFINE-SITE-HOST-LIST (VAR KEY &OPTIONAL DOCUMENTATION)
  "Define a variable whose value is a list of hosts, specified by the site option KEY.
The option's value itself will be a list of strings,
but the variable's value is a list of hosts with those names."
  `(PROGN
     ,(IF DOCUMENTATION
	  `(DEFVAR ,VAR NIL ,DOCUMENTATION)
	`(DEFVAR ,VAR))
     (ADD-INITIALIZATION ,(FORMAT NIL "SITE:~A" VAR)
			 `(SETQ ,',VAR (MAPCAR #'PARSE-HOST (GET-SITE-OPTION ',',KEY)))
			 '(SITE-OPTION))))

;;; Set by major local network
;;; A function called with a host (string or host-object), a system-type and a local net
;;; address.
(DEFVAR NEW-HOST-VALIDATION-FUNCTION)

(DEFUN SET-SYS-HOST (HOST-NAME &OPTIONAL OPERATING-SYSTEM-TYPE HOST-ADDRESS
		     SITE-FILE-DIRECTORY
			       &AUX HOST-OBJECT)
  "Specify the host to read system files from.
You can specify the operating system type, host address, and the directory
for finding the site files, in case the system does not know that host yet."
  (CHECK-TYPE HOST-NAME (OR STRING HOST) "a host name")
  (CHECK-ARG OPERATING-SYSTEM-TYPE (OR (NULL OPERATING-SYSTEM-TYPE)
				       (GET OPERATING-SYSTEM-TYPE 'SYSTEM-TYPE-FLAVOR))
	     "an operating system type")
  (AND (SETQ HOST-OBJECT (OR (FS:GET-PATHNAME-HOST HOST-NAME T)
			     (SI:PARSE-HOST HOST-NAME T T)))
       OPERATING-SYSTEM-TYPE
       (NEQ OPERATING-SYSTEM-TYPE (SEND HOST-OBJECT :SYSTEM-TYPE))
       (FERROR NIL "~A is ~A, not ~A." HOST-OBJECT
	       (SEND HOST-OBJECT :SYSTEM-TYPE) OPERATING-SYSTEM-TYPE))
  (SETQ HOST-OBJECT (SEND NEW-HOST-VALIDATION-FUNCTION (OR HOST-OBJECT HOST-NAME)
			  OPERATING-SYSTEM-TYPE HOST-ADDRESS))
  (FS:DEFINE-SYS-LOGICAL-DEVICE HOST-OBJECT)
  (AND SITE-FILE-DIRECTORY
       (FS:CHANGE-LOGICAL-PATHNAME-DIRECTORY "SYS" "SITE" SITE-FILE-DIRECTORY))
  T)


#|
;;; Interfaces to chaosnet physical support facilities
(DEFUN CALL-ELEVATOR ()
  (COND ((TECH-SQUARE-FLOOR-P 8)
	 (CHAOS:HACK-DOOR "8"))
	((TECH-SQUARE-FLOOR-P 9)
	 (CHAOS:HACK-DOOR "9"))
	(T (TV:NOTIFY NIL "I don't know how to get an elevator to your location."))))

(DEFUN BUZZ-DOOR ()
  (COND ((TECH-SQUARE-FLOOR-P 9) (CHAOS:HACK-DOOR "D"))
	(T (TV:NOTIFY NIL "I can only open the 9th floor door at Tech square"))))

(DEFUN TECH-SQUARE-FLOOR-P (FLOOR)
  (AND LOCAL-FLOOR-LOCATION
       (EQ (FIRST LOCAL-FLOOR-LOCATION) 'MIT-NE43)
       (= (SECOND LOCAL-FLOOR-LOCATION) FLOOR)))
|#

;;;; Stuff for function specs

;;;---!!! The following functions and variables (everything up to next
;;;---!!!   page break) should be moved to SYS: SYS; FSPEC LISP, but due
;;;---!!!   to isseus (see FSPEC LISP) hasn't been done just yet.
;;;---!!! 
;;;---!!!	FUNCTION-SPEC-LESSP 
;;;---!!!	FUNDEFINE 
;;;---!!!	FDEFINITION-LOCATION 
;;;---!!!	FUNCTION-PARENT 
;;;---!!!	LOCATION-FUNCTION-SPEC-HANDLER 
;;;---!!!	STANDARDIZE-FUNCTION-SPEC 
;;;---!!!	NON-PATHNAME-REDEFINED-FILES NIL
;;;---!!!	QUERY-ABOUT-REDEFINITION 
;;;---!!!	UNDEFUN 
;;;---!!!	GET-SOURCE-FILE-NAME 
;;;---!!!	GET-ALL-SOURCE-FILE-NAMES 

;;; These are here because they must be loaded after the package system is operational
;;; (or maybe only because they aren't needed in the cold load?)

;;; This is useful for sorting function specs
(DEFUN FUNCTION-SPEC-LESSP (FS1 FS2)
  "Compares two function specs, approximately alphabetically."
  (STRING-LESSP (IF (SYMBOLP FS1) FS1 (SECOND FS1))
		(IF (SYMBOLP FS2) FS2 (SECOND FS2))))

(DEFUN FUNDEFINE (FUNCTION-SPEC)
  "Makes FUNCTION-SPEC not have a function definition."
  ;; First, validate the function spec and determine its type
  (SETQ FUNCTION-SPEC (DWIMIFY-ARG-PACKAGE FUNCTION-SPEC 'FUNCTION-SPEC))
  (IF (SYMBOLP FUNCTION-SPEC) (FMAKUNBOUND FUNCTION-SPEC)
      (FUNCALL (GET (CAR FUNCTION-SPEC) 'FUNCTION-SPEC-HANDLER) 'FUNDEFINE FUNCTION-SPEC)))

(DEFUN FDEFINITION-LOCATION (FUNCTION-SPEC &AUX HANDLER)
  "Returns a locative pointer to the cell containing FUNCTION-SPEC's definition."
  ;; First, validate the function spec and determine its type
  (COND ((SYMBOLP FUNCTION-SPEC) (LOCF (SYMBOL-FUNCTION FUNCTION-SPEC)))
	((AND (CONSP FUNCTION-SPEC)
	      (SETQ HANDLER (GET (CAR FUNCTION-SPEC) 'FUNCTION-SPEC-HANDLER)))
	 (FUNCALL HANDLER 'FDEFINITION-LOCATION FUNCTION-SPEC))
	(T (FERROR 'SYS:INVALID-FUNCTION-SPEC
		   "The function spec ~S is invalid." FUNCTION-SPEC))))

(DEFUN FUNCTION-PARENT (FUNCTION-SPEC &AUX DEF TEM)
  (DECLARE (VALUES NAME TYPE))
  "Returns NIL or the name of another definition which has the same source code.
The second value is the type of that definition (which can be NIL).
This is used for things like internal functions, methods automatically
created by a defflavor, and macros automatically created by a defstruct."
  (COND ((AND (FDEFINEDP FUNCTION-SPEC)
	      (SETQ TEM (CDR (ASSQ 'FUNCTION-PARENT
				   (DEBUGGING-INFO (SETQ DEF (FDEFINITION FUNCTION-SPEC))))))
	      ;; Don't get confused by circular function-parent pointers.
	      (NOT (EQUAL TEM FUNCTION-SPEC)))
	 (VALUES (CAR TEM) (CADR TEM)))
	((AND (CONSP DEF) (EQ (CAR DEF) 'MACRO) (SYMBOLP (CDR DEF))  ;for DEFSTRUCT
	      (SETQ DEF (GET (CDR DEF) 'MACROEXPANDER-FUNCTION-PARENT)))
	 (FUNCALL DEF FUNCTION-SPEC))
	((CONSP FUNCTION-SPEC)
	 (FUNCALL (GET (CAR FUNCTION-SPEC) 'FUNCTION-SPEC-HANDLER)
		  #'FUNCTION-PARENT FUNCTION-SPEC))))

;;; (:LOCATION locative-or-list-pointer) refers to the CDR of the pointer.
;;; This is for pointing at an arbitrary place which there is no special
;;; way to describe.
(DEFPROP :LOCATION LOCATION-FUNCTION-SPEC-HANDLER FUNCTION-SPEC-HANDLER)
(DEFUN LOCATION-FUNCTION-SPEC-HANDLER (FUNCTION FUNCTION-SPEC &OPTIONAL ARG1 ARG2)
  (LET ((LOC (SECOND FUNCTION-SPEC)))
    (IF (NOT (AND (= (LENGTH FUNCTION-SPEC) 2)
		  (OR (= (%DATA-TYPE LOC) DTP-LOCATIVE)
		      (= (%DATA-TYPE LOC) DTP-LIST))))
	(UNLESS (EQ FUNCTION 'VALIDATE-FUNCTION-SPEC)
	  (FERROR 'SYS:INVALID-FUNCTION-SPEC
		  "The function spec ~S is invalid." FUNCTION-SPEC))
      (CASE FUNCTION
	(VALIDATE-FUNCTION-SPEC T)
	(FDEFINE (RPLACD LOC ARG1))
	(FDEFINITION (CDR LOC))
	(FDEFINEDP (AND ( (%P-DATA-TYPE LOC) DTP-NULL) (NOT (NULL (CDR LOC)))))
	(FDEFINITION-LOCATION LOC)
	;; FUNDEFINE could store DTP-NULL, which would only be right sometimes
	(OTHERWISE (FUNCTION-SPEC-DEFAULT-HANDLER FUNCTION FUNCTION-SPEC ARG1 ARG2))))))

;;; Convert old Maclisp-style property function specs
(DEFUN STANDARDIZE-FUNCTION-SPEC (FUNCTION-SPEC &OPTIONAL (ERRORP T))
  (AND (CONSP FUNCTION-SPEC)
       (= (LENGTH FUNCTION-SPEC) 2)
       (SYMBOLP (CAR FUNCTION-SPEC))
       (NOT (GET (CAR FUNCTION-SPEC) 'FUNCTION-SPEC-HANDLER))
       (SETQ FUNCTION-SPEC (CONS :PROPERTY FUNCTION-SPEC)))
  (OR (NOT ERRORP)
      (VALIDATE-FUNCTION-SPEC FUNCTION-SPEC)
      (FERROR NIL "~S is not a valid function spec." FUNCTION-SPEC))
  FUNCTION-SPEC)

(DEFPROP DEFUN "Function" DEFINITION-TYPE-NAME)
(DEFPROP DEFVAR "Variable" DEFINITION-TYPE-NAME)

(DEFVAR NON-PATHNAME-REDEFINED-FILES NIL
  "Files whose functions it is ok to redefine from the keyboard.")

;;; Query about any irregularities about redefining the given function symbol now.
;;; Return T to tell caller to go ahead and redefine the symbol
;;; (no problems or user says ok), NIL to leave it unchanged.
(DEFUN QUERY-ABOUT-REDEFINITION (FUNCTION-SPEC NEW-PATHNAME TYPE OLD-PATHNAME)
  ;; Detect any cross-file redefinition worth complaining about.
  (IF (OR (EQ (IF (STRINGP OLD-PATHNAME)
		  OLD-PATHNAME
		(AND OLD-PATHNAME (SEND OLD-PATHNAME :TRANSLATED-PATHNAME)))
	      (IF (STRINGP NEW-PATHNAME)
		  NEW-PATHNAME
		(AND NEW-PATHNAME (SEND NEW-PATHNAME :TRANSLATED-PATHNAME))))
	  (MEMQ OLD-PATHNAME
		(IF NEW-PATHNAME
		    (SEND NEW-PATHNAME :GET :REDEFINES-FILES)
		  NON-PATHNAME-REDEFINED-FILES)))
      T
    ;; This redefinition deserves a warning or query.
    ;; If it is within a file operation with warnings,
    ;; record a warning.
    (WHEN (AND (VARIABLE-BOUNDP FILE-WARNINGS-DATUM) FILE-WARNINGS-DATUM)
      (RECORD-AND-PRINT-WARNING 'REDEFINITION :PROBABLE-ERROR NIL
	(IF NEW-PATHNAME
	    "~A ~S being redefined by file ~A.
 It was previously defined by file ~A."
	  "~A ~S being redefined;~* it was previously defined by file ~A.")
	(OR (GET TYPE 'DEFINITION-TYPE-NAME) TYPE) FUNCTION-SPEC
	NEW-PATHNAME OLD-PATHNAME))
    (LET (CONDITION CHOICE)
      (SETQ CONDITION
	    (MAKE-CONDITION 'SYS:REDEFINITION
	      (IF NEW-PATHNAME
		  "~A ~S being redefined by file ~A.
It was previously defined by file ~A."
		"~A ~S being redefined;~* it was previously defined by file ~A.")
	      (OR (GET TYPE 'DEFINITION-TYPE-NAME) TYPE)
	      FUNCTION-SPEC
	      NEW-PATHNAME OLD-PATHNAME))
      (SETQ CHOICE (SIGNAL CONDITION))
      (UNLESS CHOICE
	(UNLESS (AND INHIBIT-FDEFINE-WARNINGS
		     (NEQ INHIBIT-FDEFINE-WARNINGS :JUST-WARN))
	  (FORMAT *QUERY-IO* "~&~A" CONDITION))
	(IF INHIBIT-FDEFINE-WARNINGS
	    (SETQ CHOICE T)
	  (SETQ CHOICE
		(FQUERY '(:CHOICES (((ERROR "Error.") #/E)
				    ((PROCEED "Proceed.") #/P)
				    . #.FORMAT:Y-OR-N-P-CHOICES)
				   :HELP-FUNCTION
				   (LAMBDA (STREAM &REST IGNORE)
				     (PRINC "
  Type Y to proceed to redefine the function, N to not redefine it, E to go into the
  error handler, or P to proceed and not ask in the future (for this pair of files): "
					    STREAM))
				   :CLEAR-INPUT T
				   :FRESH-LINE NIL)
			" OK? "))))
      (CASE CHOICE
	((T :NO-ACTION) T)
	((NIL :INHIBIT-DEFINITION) NIL)
	(ERROR
	 (ERROR CONDITION)
	 T)
	(PROCEED
	 (IF NEW-PATHNAME
	     (PUSH OLD-PATHNAME (GET NEW-PATHNAME :REDEFINES-FILES))
	   (PUSH OLD-PATHNAME NON-PATHNAME-REDEFINED-FILES))
	 T)))))

(DEFUN UNDEFUN (FUNCTION-SPEC &AUX TEM)
  "Restores the saved previous function definition of a function spec."
  (SETQ FUNCTION-SPEC (DWIMIFY-ARG-PACKAGE FUNCTION-SPEC 'FUNCTION-SPEC))
  (SETQ TEM (FUNCTION-SPEC-GET FUNCTION-SPEC :PREVIOUS-DEFINITION))
  (COND (TEM
	 (FSET-CAREFULLY FUNCTION-SPEC TEM T))
	((Y-OR-N-P (FORMAT NIL "~S has no previous definition.  Undefine it? "
			   FUNCTION-SPEC))
	 (FUNDEFINE FUNCTION-SPEC))))

;;; Some source file stuff that does not need to be in QRAND
(DEFUN GET-SOURCE-FILE-NAME (FUNCTION-SPEC &OPTIONAL TYPE)
  "Returns pathname of source file for definition of type TYPE of FUNCTION-SPEC.
If TYPE is NIL, the most recent definition is used, regardless of type.
FUNCTION-SPEC really is a function spec only if TYPE is DEFUN;
for example, if TYPE is DEFVAR, FUNCTION-SPEC is a variable name."
  (DECLARE (VALUES PATHNAME TYPE))
  (LET ((PROPERTY (FUNCTION-SPEC-GET FUNCTION-SPEC :SOURCE-FILE-NAME)))
    (COND ((NULL PROPERTY) NIL)
	  ((ATOM PROPERTY)
	   (AND (MEMQ TYPE '(DEFUN NIL))
		(VALUES PROPERTY 'DEFUN)))
	  (T
	   (LET ((LIST (IF TYPE (ASSQ TYPE PROPERTY) (CAR PROPERTY))))
	     (LOOP FOR FILE IN (CDR LIST)
		   WHEN (NOT (SEND FILE :GET :PATCH-FILE))
		   RETURN (VALUES FILE (CAR LIST))))))))

(DEFUN GET-ALL-SOURCE-FILE-NAMES (FUNCTION-SPEC)
  "Return list describing source files for all definitions of FUNCTION-SPEC.
Each element of the list has a type of definition as its car,
and its cdr is a list of generic pathnames that made that type of definition."
  (LET ((PROPERTY (FUNCTION-SPEC-GET FUNCTION-SPEC :SOURCE-FILE-NAME)))
    (COND ((NULL PROPERTY) NIL)
	  ((ATOM PROPERTY)
	   (SETQ PROPERTY `((DEFUN ,PROPERTY)))
	   ;; May as well save this consing.
	   (FUNCTION-SPEC-PUTPROP FUNCTION-SPEC PROPERTY :SOURCE-FILE-NAME)
	   PROPERTY)
	  (T PROPERTY))))

(DEFUN DOCUMENTATION (SYMBOL &OPTIONAL (DOC-TYPE 'FUNCTION))
  "Try to return the documentation string for SYMBOL, else return NIL.
Standard values of DOC-TYPE are: FUNCTION, VARIABLE, TYPE, STRUCTURE and SETF,
but you can put on and retrieve documentation for any DOC-TYPE.
Documentation strings are installed by SETFing a call to DOCUMENTATION."
  (COND ((AND (EQ DOC-TYPE 'VALUE)
	      (GET SYMBOL :DOCUMENTATION)))
	((AND (SYMBOLP SYMBOL)
	      (LET ((DOC-PROP (GET SYMBOL 'DOCUMENTATION-PROPERTY)))
		(CDR (ASSOC-EQUAL (STRING DOC-TYPE) DOC-PROP)))))
	((AND (EQ DOC-TYPE 'TYPE)
	      (GET SYMBOL 'TYPE-EXPANDER)
	      (DOCUMENTATION (GET SYMBOL 'TYPE-EXPANDER) 'FUNCTION)))
	((AND (EQ DOC-TYPE 'SETF)
	      (GET SYMBOL 'SETF-METHOD)
	      (DOCUMENTATION (GET SYMBOL 'SETF-METHOD) 'FUNCTION)))
	((NEQ DOC-TYPE 'FUNCTION) NIL)
	((SYMBOLP SYMBOL)
	 (IF (FBOUNDP SYMBOL)
	     (DOCUMENTATION (FDEFINITION (UNENCAPSULATE-FUNCTION-SPEC SYMBOL)))))
	((CONSP SYMBOL)
	 (IF (FUNCTIONP SYMBOL T)
	     (IF (EQ (CAR SYMBOL) 'MACRO)
		 (DOCUMENTATION (CDR SYMBOL))
	       (OR (CADR (ASSQ 'DOCUMENTATION (DEBUGGING-INFO SYMBOL)))
		   ;; old name
		   (CADR (ASSQ :DOCUMENTATION (DEBUGGING-INFO SYMBOL)))
		   (NTH-VALUE 2 (EXTRACT-DECLARATIONS
				  (CDR (LAMBDA-EXP-ARGS-AND-BODY SYMBOL)) NIL T NIL))))
	   (AND (FDEFINEDP SYMBOL)
		(DOCUMENTATION (FDEFINITION (UNENCAPSULATE-FUNCTION-SPEC SYMBOL))))))
	((COMPILED-FUNCTION-P SYMBOL)
	 (IF (ASSQ 'COMBINED-METHOD-DERIVATION (DEBUGGING-INFO SYMBOL))
	     ;; its an FEF for a combined method, so do special handling
	     (COMBINED-METHOD-DOCUMENTATION SYMBOL)
	   (OR (CADR (ASSQ 'DOCUMENTATION (DEBUGGING-INFO SYMBOL)))
	       (CADR (ASSQ :DOCUMENTATION (DEBUGGING-INFO SYMBOL))))))))
;;; Old name.
;(DEFF FUNCTION-DOCUMENTATION 'DOCUMENTATION)
(MAKE-OBSOLETE FUNCTION-DOCUMENTATION
	       "use DOCUMENTATION with a second argument of 'FUNCTION.")

(DEFUN COMBINED-METHOD-DOCUMENTATION (METHOD &OPTIONAL STREAM &KEY (FRESH-LINE T))
  "Returns a string which documents Method.  Method must be a :combined method.
If Stream is a stream, then instead prints documentation to the stream.
Fresh-Line is only used if Stream is a stream.
This documentation string will have the format:

  method combination is <keyword for type>, order is <keyword for order>

  :wrapper methods
    flavor component-flavor-1, arglist: args
      doc string
    flavor component-flavor-2, arglist: args
      doc string
    ...

    :around methods
      flavor component-flavor-1, arglist: args
        doc string
      flavor component-flavor-2, arglist: args
        doc string
      ...

      etc. { the rest depends on which type of method combination is used.
             see SI::DEFINE-COMBINED-METHOD-DOCUMENTATION-HANDLER, SI::COMBINED-DOC-STRING,
	     and (:PROPERTY SI::COMBINED-METHOD-DOCUMENTATION <method combination keyword>) }

the ordering for component flavors is the order in which the components are combined to form
the combined method.  Note that the following orders always hold:
   :wrappers         :base-flavor-last
   :around methods   :base-flavor-last
   :before methods   :base-flavor-last
   :after methods    :base-flavor-first

A handler for the method-combination type used by the combined method must exist
/(see SI::DEFINE-COMBINED-METHOD-DOCUMENTATION-HANDLER to define new ones)."
  (LET* ((TEMP (CADR (ASSQ 'COMBINED-METHOD-DERIVATION (DEBUGGING-INFO METHOD))))
	 (TYPE (OR (CADR TEMP) :DAEMON))	; :daemon is default type
	 (HANDLER (GET 'COMBINED-METHOD-DOCUMENTATION TYPE))
	 (ORDER (IF (EQ TYPE :PASS-ON) (CAADDR TEMP) (CADDR TEMP)))
	 (DERIVATION (CDDDR TEMP))
	 (FLAVORS (FLAVOR-DEPENDS-ON-ALL (GET (FLAVOR-OF-METHOD METHOD) 'FLAVOR)))
	 (INDENT 0)
	 STRING ST)
    (WHEN (NULL HANDLER)
      (FERROR NIL "No combined method doc handler for ~S method combination." TYPE))
    (IF (OR (STREAMP STREAM) (EQ STREAM T)) (SETQ STRING STREAM)
      ;; only need string if no stream
      (SETQ STRING (MAKE-STRING (* #o100 (LENGTH DERIVATION)) :FILL-POINTER 0))
      (SETQ STREAM NIL))
    ;; put in header
    (SETQ ST (FORMAT STREAM "~@[~&~*~]method combination is ~S~@[, order is ~S~]"
		     (AND STREAM FRESH-LINE) TYPE (AND (NEQ TYPE :DAEMON) ORDER)))
    (UNLESS STREAM
      (STRING-NCONC STRING ST))
    ;; do :wrapper and :around methods
    (COMBINED-DOC-STRING STRING (ASSQ :WRAPPER DERIVATION) FLAVORS INDENT ORDER)
    (WHEN (ASSQ :WRAPPER DERIVATION) (INCF INDENT 2))
    (COMBINED-DOC-STRING STRING (ASSQ :AROUND DERIVATION) FLAVORS INDENT ORDER)
    (WHEN (ASSQ :AROUND DERIVATION) (INCF INDENT 2))
    ;; call the handler appropriate to the type of method combination
    (FUNCALL HANDLER STRING DERIVATION FLAVORS INDENT ORDER)
    (WHEN (AND (STRINGP STRING) (PLUSP (LENGTH STRING))) STRING)))

(DEFUN COMBINED-DOC-STRING (STRING COMPONENTS FLAVORS INDENT &OPTIONAL ORDER)
  "Add the documentation for a component method type to String.
The type of method is in the CAR of Components.  The component methods are the CDR of
Components.  Flavors is the list of component flavors, in the order of flavor combination.
Order is taken from the method combination specifier.  The result will look roughly like:

     <indentation>
    <method type> methods, order is <order of method combination>
      flavor <flavor of first component method>, arglist: <arglist of component method>
          <documentation string for component method>
      flavor <flavor of second component method>, arglist: <arglist of component method>
          <documentation string for component method>
      ...

:CASE methods vary slightly in that they include the suboperation at the beginning of the line
giving the flavor and arglist.  If Order is nil then the header will not include mention of
the order of combination.

String can be either a string (which must have a fill pointer), in which case the modified
string is returned, or it can be a stream."
  (LET ((TYPE (POP COMPONENTS))
	(STREAM (AND (OR (STREAMP STRING) (EQ STRING T)) STRING))
	METHODS ST)
    (IF (NULL COMPONENTS) STRING
      (PKG-BIND 'USER				; force printing of package prefix's
	(SETQ ST (FORMAT STREAM "~2%~V,0T~:[~*:PRIMARY~;~S~] method~P~@[, order is ~S~]"
			 INDENT TYPE TYPE (LENGTH COMPONENTS) ORDER))
	(UNLESS STREAM
	  (STRING-NCONC STRING ST))		 
	(DOLIST (FLAVOR FLAVORS STRING)
	  (SETQ METHODS (SUBSET `(LAMBDA (M) (EQ ',FLAVOR (FLAVOR-OF-METHOD M))) COMPONENTS))
	  (DOLIST (METHOD METHODS)
	    (SETQ ST (FORMAT STREAM "~%~V,0T~@[~S suboperation, ~]flavor ~S, arglist: ~S"
			     (+ INDENT 2)
			     (AND (EQ TYPE :CASE) (CAR (LAST (NAME-OF-METHOD METHOD))))
			     FLAVOR
			     (DO ((ARGS (ARGLIST METHOD) (CDR ARGS)))
				 ((NOT (MEMQ (CAR ARGS) '(.OPERATION. .SUBOPERATION.)))
				  ARGS))))
	    (UNLESS STREAM
	      (STRING-NCONC STRING ST))			
	    (LET ((DOC (DOCUMENTATION METHOD)))
	      (WHEN DOC
		(SETQ ST (FORMAT STREAM "~%~V,0T~~A~" (+ INDENT 4) DOC))
		(UNLESS STREAM
		  (STRING-NCONC STRING ST))))))))))

(DEFUN FLAVOR-OF-METHOD (METHOD)
  "Returns the symbol which is the flavor for Method.
Method may be either a method spec (ie. (:method flavor type operation suboperation)) or an
FEF for a method.  Error if Method is not a defined method."
  (COND ((TYPEP METHOD 'COMPILED-FUNCTION)
	 ;; get name of method from fef and extract flavor
	 (CADR (NAME-OF-METHOD METHOD)))
	((CONSP (SETQ METHOD (FDEFINITION (UNENCAPSULATE-FUNCTION-SPEC METHOD))))
	 (IF (EQ (CAR METHOD) 'MACRO)
	     (FLAVOR-OF-METHOD (CDR METHOD))
	   (CADR (ASSQ :SELF-FLAVOR		; named-lambda
		       (NTH-VALUE 1 (EXTRACT-DECLARATIONS
				      (CDR (LAMBDA-EXP-ARGS-AND-BODY METHOD)) NIL T NIL))))))
	(T (FLAVOR-OF-METHOD METHOD))))		; fef returned by fdefinition, try again

(DEFUN NAME-OF-METHOD (METHOD)
  "Returns the list which is the function spec for the method.
Method may be either a method spec (ie. (:method flavor type operation suboperation)) or an
FEF for a method.  Error if Method is not a defined method."
  (COND ((TYPEP METHOD 'COMPILED-FUNCTION)
	 (%P-CONTENTS-OFFSET METHOD %FEFHI-FCTN-NAME))
	((CONSP (SETQ METHOD (FDEFINITION (UNENCAPSULATE-FUNCTION-SPEC METHOD))))
	 (IF (EQ (CAR METHOD) 'MACRO)
	     (NAME-OF-METHOD (CDR METHOD))
	   (CAADR METHOD)))			; named-lambda
	(T (NAME-OF-METHOD METHOD))))		; fef, try again

(DEFMACRO DEFINE-COMBINED-METHOD-DOCUMENTATION-HANDLER (TYPE &BODY BODY)
  "Expands to define (:property si:combined-method-documentation <combination type>).
Body can reference the following variables (they are the args to the handler):
 String      the documentation string to be modified (use STRING-NCONC).
 Derivation  the list of component methods for this method.  it is an alist, with each element
             being a method type followed by the component methods of that type.
 Flavors     the list of component flavors, in the order of flavor combination.
 Indent      number of spaces to indent from the left, used for formatting.
 Order       from the method-combination declaration, a keyword.
Typically, Body consists of some number of calls to SI:COMBINED-DOC-STRING interspersed with
adjustments to the indentation."
  (DECLARE (ARGLIST (METHOD-COMBINATION-TYPE) &BODY BODY))
  (CHECK-TYPE TYPE SYMBOL)
  (MULTIPLE-VALUE-BIND (BODY DECLARATIONS DOCUMENTATION)
      (EXTRACT-DECLARATIONS BODY NIL T NIL)
    `(DEFUN (COMBINED-METHOD-DOCUMENTATION ,TYPE) (STRING DERIVATION FLAVORS INDENT ORDER)
       ,(FORMAT NIL "Add documentation to string according to ~S method combination.~@[~%~A~]"
		TYPE DOCUMENTATION)
       (DECLARE . ,DECLARATIONS)
       . ,BODY)))

;;; define combined-method-documentation handlers for each type of method combination
(DEFINE-COMBINED-METHOD-DOCUMENTATION-HANDLER :DAEMON
  "Format is --
  :BEFORE methods
    :PRIMARY method
  :AFTER methods"
  ORDER						; ignored arg
  (COMBINED-DOC-STRING STRING (ASSQ :BEFORE DERIVATION) FLAVORS INDENT)
  (WHEN (OR (ASSQ :BEFORE DERIVATION) (ASSQ :AFTER DERIVATION)) (INCF INDENT 2))
  (COMBINED-DOC-STRING STRING (ASSQ NIL DERIVATION) FLAVORS INDENT)
  (DECF INDENT 2)
  (COMBINED-DOC-STRING STRING (ASSQ :AFTER DERIVATION) (REVERSE FLAVORS) INDENT))

(DEFINE-COMBINED-METHOD-DOCUMENTATION-HANDLER :DAEMON-WITH-OR
  "Format is --
  :BEFORE methods
    :OR methods
      :PRIMARY method
  :AFTER methods"
  (COMBINED-DOC-STRING STRING (ASSQ :BEFORE DERIVATION) FLAVORS INDENT)
  (WHEN (OR (ASSQ :BEFORE DERIVATION) (ASSQ :AFTER DERIVATION)) (INCF INDENT 2))
  (COMBINED-DOC-STRING STRING (ASSQ :OR DERIVATION)
		       (IF (EQ ORDER :BASE-FLAVOR-FIRST) (REVERSE FLAVORS) FLAVORS)
		       INDENT ORDER)
  (WHEN (ASSQ :OR DERIVATION) (INCF INDENT 2))
  (COMBINED-DOC-STRING STRING (ASSQ NIL DERIVATION) FLAVORS INDENT)
  (WHEN (ASSQ :OR DERIVATION) (DECF INDENT 2))
  (DECF INDENT 2)
  (COMBINED-DOC-STRING STRING (ASSQ :AFTER DERIVATION) (REVERSE FLAVORS) INDENT))

(DEFINE-COMBINED-METHOD-DOCUMENTATION-HANDLER :DAEMON-WITH-AND
  "Format is --
  :BEFORE methods
    :AND methods
      :PRIMARY method
  :AFTER methods"
  (COMBINED-DOC-STRING STRING (ASSQ :BEFORE DERIVATION) FLAVORS INDENT)
  (WHEN (OR (ASSQ :BEFORE DERIVATION) (ASSQ :AFTER DERIVATION)) (INCF INDENT 2))
  (COMBINED-DOC-STRING STRING (ASSQ :AND DERIVATION)
		       (IF (EQ ORDER :BASE-FLAVOR-FIRST) (REVERSE FLAVORS) FLAVORS)
		       INDENT ORDER)
  (WHEN (ASSQ :AND DERIVATION) (INCF INDENT 2))
  (COMBINED-DOC-STRING STRING (ASSQ NIL DERIVATION) FLAVORS INDENT)
  (WHEN (ASSQ :AND DERIVATION) (DECF INDENT 2))
  (DECF INDENT 2)
  (COMBINED-DOC-STRING STRING (ASSQ :AFTER DERIVATION) (REVERSE FLAVORS) INDENT))

(DEFINE-COMBINED-METHOD-DOCUMENTATION-HANDLER :DAEMON-WITH-OVERRIDE
  "Format is --
  :OVERRIDE methods
    :BEFORE methods
      :PRIMARY method
    :AFTER methods"
  (COMBINED-DOC-STRING STRING (ASSQ :OVERRIDE DERIVATION)
		       (IF (EQ ORDER :BASE-FLAVOR-FIRST) (REVERSE FLAVORS) FLAVORS)
		       INDENT ORDER)
  (WHEN (ASSQ :OVERRIDE DERIVATION) (INCF INDENT 2))
  (COMBINED-DOC-STRING STRING (ASSQ :BEFORE DERIVATION) FLAVORS INDENT)
  (WHEN (OR (ASSQ :BEFORE DERIVATION) (ASSQ :AFTER DERIVATION)) (INCF INDENT 2))
  (COMBINED-DOC-STRING STRING (ASSQ NIL DERIVATION) FLAVORS INDENT)
  (DECF INDENT 2)
  (COMBINED-DOC-STRING STRING (ASSQ :AFTER DERIVATION) (REVERSE FLAVORS) INDENT))

(DEFINE-COMBINED-METHOD-DOCUMENTATION-HANDLER :CASE
  "Format is --
  :OR methods
    :CASE methods
      :PRIMARY method"
  (COMBINED-DOC-STRING STRING (ASSQ :OR DERIVATION)
		       (IF (EQ ORDER :BASE-FLAVOR-FIRST) (REVERSE FLAVORS) FLAVORS)
		       INDENT ORDER)
  (WHEN (ASSQ :OR DERIVATION) (INCF INDENT 2))
  (COMBINED-DOC-STRING STRING (ASSQ :CASE DERIVATION)
		       (IF (EQ ORDER :BASE-FLAVOR-FIRST) (REVERSE FLAVORS) FLAVORS)
		       INDENT ORDER)
  (WHEN (ASSQ :CASE DERIVATION) (INCF INDENT 2))
  (COMBINED-DOC-STRING STRING (ASSQ NIL DERIVATION) FLAVORS INDENT))

(DEFINE-COMBINED-METHOD-DOCUMENTATION-HANDLER :PROGN
  (COMBINED-DOC-STRING STRING (ASSQ NIL DERIVATION)
		       (IF (EQ ORDER :BASE-FLAVOR-FIRST) (REVERSE FLAVORS) FLAVORS)
		       INDENT ORDER))

(DEFINE-COMBINED-METHOD-DOCUMENTATION-HANDLER :OR
  (COMBINED-DOC-STRING STRING (ASSQ NIL DERIVATION)
		       (IF (EQ ORDER :BASE-FLAVOR-FIRST) (REVERSE FLAVORS) FLAVORS)
		       INDENT ORDER))

(DEFINE-COMBINED-METHOD-DOCUMENTATION-HANDLER :AND
  (COMBINED-DOC-STRING STRING (ASSQ NIL DERIVATION)
		       (IF (EQ ORDER :BASE-FLAVOR-FIRST) (REVERSE FLAVORS) FLAVORS)
		       INDENT ORDER))

(DEFINE-COMBINED-METHOD-DOCUMENTATION-HANDLER :APPEND
  (COMBINED-DOC-STRING STRING (ASSQ NIL DERIVATION)
		       (IF (EQ ORDER :BASE-FLAVOR-FIRST) (REVERSE FLAVORS) FLAVORS)
		       INDENT ORDER))

(DEFINE-COMBINED-METHOD-DOCUMENTATION-HANDLER :NCONC
  (COMBINED-DOC-STRING STRING (ASSQ NIL DERIVATION)
		       (IF (EQ ORDER :BASE-FLAVOR-FIRST) (REVERSE FLAVORS) FLAVORS)
		       INDENT ORDER))

(DEFINE-COMBINED-METHOD-DOCUMENTATION-HANDLER :LIST
  (COMBINED-DOC-STRING STRING (ASSQ NIL DERIVATION)
		       (IF (EQ ORDER :BASE-FLAVOR-FIRST) (REVERSE FLAVORS) FLAVORS)
		       INDENT ORDER))

(DEFINE-COMBINED-METHOD-DOCUMENTATION-HANDLER :INVERSE-LIST
  (COMBINED-DOC-STRING STRING (ASSQ NIL DERIVATION)
		       (IF (EQ ORDER :BASE-FLAVOR-FIRST) (REVERSE FLAVORS) FLAVORS)
		       INDENT ORDER))

(DEFINE-COMBINED-METHOD-DOCUMENTATION-HANDLER :PASS-ON
  (COMBINED-DOC-STRING STRING (ASSQ NIL DERIVATION)
		       (IF (EQ ORDER :BASE-FLAVOR-FIRST) (REVERSE FLAVORS) FLAVORS)
		       INDENT ORDER))

(DEFINE-COMBINED-METHOD-DOCUMENTATION-HANDLER :MAX
  (COMBINED-DOC-STRING STRING (ASSQ NIL DERIVATION)
		       (IF (EQ ORDER :BASE-FLAVOR-FIRST) (REVERSE FLAVORS) FLAVORS)
		       INDENT ORDER))

(DEFINE-COMBINED-METHOD-DOCUMENTATION-HANDLER :MIN
  (COMBINED-DOC-STRING STRING (ASSQ NIL DERIVATION)
		       (IF (EQ ORDER :BASE-FLAVOR-FIRST) (REVERSE FLAVORS) FLAVORS)
		       INDENT ORDER))

(DEFINE-COMBINED-METHOD-DOCUMENTATION-HANDLER :+
  (COMBINED-DOC-STRING STRING (ASSQ NIL DERIVATION)
		       (IF (EQ ORDER :BASE-FLAVOR-FIRST) (REVERSE FLAVORS) FLAVORS)
		       INDENT ORDER))

;;;; These are for reading in QCOM, and the like

;;; This barfola really makes my brain hurt.
(DEFUN ASSIGN-ALTERNATE (X)
   (PROG ()
      L	 (COND ((NULL X) (RETURN NIL)))
	 (SET (CAR X) (CADR X))
	 (SETQ X (CDDR X))
	 (GO L)))

(DEFUN GET-ALTERNATE (X)
  (PROG (Y)
     L	(COND ((NULL X) (RETURN (REVERSE Y))))
	(SETQ Y (CONS (CAR X) Y))
	(SETQ X (CDDR X))
	(GO L)))

(DEFUN ASSIGN-VALUES (INPUT-LIST &OPTIONAL (SHIFT 0) (INIT 0) (DELTA 1))
   (PROG ()
      L  (COND ((NULL INPUT-LIST) (RETURN INIT)))
	 (SET (CAR INPUT-LIST) (LSH INIT SHIFT))
	 (SETQ INPUT-LIST (CDR INPUT-LIST))
	 (SETQ INIT (+ INIT DELTA))
	 (GO L)))

(DEFUN ASSIGN-VALUES-INIT-DELTA (INPUT-LIST SHIFT INIT DELTA)
  (PROG () 
     L	(COND ((NULL INPUT-LIST) (RETURN INIT)))
	(SET (CAR INPUT-LIST) (LSH INIT SHIFT))
	(SETQ INPUT-LIST (CDR INPUT-LIST))
	(SETQ INIT (+ INIT DELTA))
	(GO L)))

(DEFSUBST GET-FROM-ALTERNATING-LIST (L KEY) 
  "Retreive associated item from an alternating list
Like GET, but no initial CAR"
  (GETF L KEY))
(COMPILER:MAKE-OBSOLETE GET-FROM-ALTERNATING-LIST "use GETF instead")

(DEFUN PUT-ON-ALTERNATING-LIST (ITEM L KEY)
  "Put ITEM on an alternating association list L
Modifies the current association, if any.
Otherwise adds one to the head of the list.  
Returns the augmented list as value.
The user should alway use this value unless he is
certain there is a current association."
  (PROG (PNTR)
	(SETQ PNTR L)
     L  (COND ((NULL L)
	       (RETURN (CONS KEY (CONS ITEM L))))
	      ((EQ KEY (CAR L))
	       (SETF (CADR L) ITEM)
	       (RETURN L)))
	(SETQ L (CDDR L))
	(GO L)))
(COMPILER:MAKE-OBSOLETE PUT-ON-ALTERNATING-LIST "This function is a crock")

(DEFUN CALL (FN &REST ALTERNATES
		&AUX (MAX-ARGS #o100) (ARGS-INF (ARGS-INFO FN)))
  "The first argument is a function to call.
The remaining arguments are in pairs, consisting of a descriptor arg and a data arg.
The descriptor arg says what to do with the data arg.
The descriptor arg value should be either a keyword or a list of keywords or NIL.
NIL means that the data argument is to be treated as a single argument to the
 function.
The allowed keywords are :SPREAD and :OPTIONAL.
:SPREAD means that the data argument is a list of arguments
 rather than a single argument.
:OPTIONAL means that the data argument can be ignored if
 the function being called doesn't ask for it.
 After the first :OPTIONAL, all args supplied are considered optional."
    (AND (ZEROP (LDB %%ARG-DESC-QUOTED-REST ARGS-INF))
         (ZEROP (LDB %%ARG-DESC-EVALED-REST ARGS-INF))
         (SETQ MAX-ARGS (LDB %%ARG-DESC-MAX-ARGS ARGS-INF)))
    (%OPEN-CALL-BLOCK FN 0 4)
    (DO ((Y ALTERNATES (CDDR Y)) (OPTIONAL-FLAG) (SPREAD-FLAG NIL NIL))
	((NULL Y))
      (IF (AND (SYMBOLP (CAR Y)) (CAR Y))
	  (CASE (CAR Y)
	    (:SPREAD (SETQ SPREAD-FLAG T))
	    (:OPTIONAL (SETQ OPTIONAL-FLAG T))
	    (OTHERWISE (FERROR NIL "Invalid ~S keyword ~S." 'CALL (CAR Y))))
	(DOLIST (X (CAR Y))
	  (CASE X
	    (:SPREAD (SETQ SPREAD-FLAG T))
	    (:OPTIONAL (SETQ OPTIONAL-FLAG T))
	    (OTHERWISE (FERROR NIL "Invalid ~S keyword ~S." 'CALL X)))))
      (AND OPTIONAL-FLAG ( MAX-ARGS 0)
	   (RETURN NIL))
      (IF SPREAD-FLAG
	  (DOLIST (X (CADR Y))
	    (IF (AND OPTIONAL-FLAG ( MAX-ARGS 0))
		(RETURN)
	      (%ASSURE-PDL-ROOM 1)
	      (%PUSH X)
	      (DECF MAX-ARGS)))
	(%ASSURE-PDL-ROOM 1)
	(%PUSH (CADR Y))
	(DECF MAX-ARGS)))
    (%ACTIVATE-OPEN-CALL-BLOCK))

;;;; Disk stuff

(DEFUN DISK-RESTORE (&OPTIONAL PARTITION &AUX NAME COMMENT DESIRED-UCODE)
  "Restore partition PARTITION as a saved Lisp world.
PARTITION can be either a string naming a partition, or a number
which signifies a partition whose name starts with LOD.
Note that this does not change the running microcode.
You cannot successfully DISK-RESTORE a world that will not work
with the microcode that is running."
  (LET ((L (DISK-RESTORE-DECODE PARTITION)) (RQB NIL) BLOCK)
    (UNWIND-PROTECT
      (PROGN
	(SETQ RQB (GET-DISK-LABEL-RQB))
	(READ-DISK-LABEL RQB 0)
	(SETQ NAME (IF PARTITION
		       (STRING-APPEND (LDB #o0010 (CADR L)) (LDB #o1010 (CADR L))
				      (LDB #o0010 (CAR L)) (LDB #o1010 (CAR L)))
		     (GET-DISK-STRING RQB 7 4)))
	(SETQ BLOCK (FIND-DISK-PARTITION-FOR-READ NAME RQB)
	      COMMENT (PARTITION-COMMENT NAME 0))
	(MULTIPLE-VALUE-BIND (BASE-BAND VALID-FLAG)
	    (INC-BAND-BASE-BAND NAME 0)
	  (WHEN (AND BASE-BAND (NOT VALID-FLAG))
	    (FERROR NIL "Band ~A is incremental, and the base band ~A is no longer valid."
		    NAME BASE-BAND)))
	(SETQ DESIRED-UCODE (GET-UCODE-VERSION-OF-BAND NAME)))
      (RETURN-DISK-RQB RQB))
    (AND ( DESIRED-UCODE %MICROCODE-VERSION-NUMBER)
	 (NOT (ZEROP DESIRED-UCODE))		;Not stored yet
	 (FORMAT *QUERY-IO*
		 "~&That band prefers microcode ~D but the running microcode is ~D.~%"
		 DESIRED-UCODE %MICROCODE-VERSION-NUMBER))
       (WHEN (FQUERY FORMAT:YES-OR-NO-QUIETLY-P-OPTIONS
		     "Do you really want to reload ~A (~A)? " NAME COMMENT)
	 (AND (FBOUNDP 'TV:CLOSE-ALL-SERVERS)
	      (TV:CLOSE-ALL-SERVERS "Disk-Restoring"))
	 (%DISK-RESTORE (CAR L) (CADR L)))))

(DEFVAR WHO-LINE-JUST-COLD-BOOTED-P NIL) ;Set to T upon cold boot for who-line's benefit

;;; Please do not add garbage to DISK-SAVE if possible.
;;; Put random initializations on the BEFORE-COLD initialization list.
(DEFUN DISK-SAVE (PARTITION &OPTIONAL NO-QUERY INCREMENTAL)
  "Save the current Lisp world in partition PARTITION.
PARTITION can be either a string naming a partition, or a number which signifies
 a partition whose name starts with LOD.
NO-QUERY says do not ask for confirmation (or any keyboard input at all).
INCREMENTAL means to write out only those parts of the world which have changed
 since the it was loaded from disk. (The effect of loading a world from a band
 saved incrementally is that the incremental saves /"patch/" the original full save."
  (PROG* ((L (DISK-RESTORE-DECODE PARTITION))
	  (PART-NAME (STRING-APPEND (LDB #o0010 (CADR L)) (LDB #o1010 (CADR L))
				    (LDB #o0010 (CAR L)) (LDB #o1010 (CAR L))))
	  PART-BASE PART-SIZE SYSTEM-VERSION MAX-ADDR
	  (INC-PAGES-SAVED 0))
    (OR (MULTIPLE-VALUE (PART-BASE PART-SIZE)
	  (IF NO-QUERY
	      (FIND-DISK-PARTITION-FOR-READ PART-NAME)
	    (FIND-DISK-PARTITION-FOR-WRITE PART-NAME)))
	(RETURN NIL))

    (UNLESS NO-QUERY
      (DOLIST (PATCH-SYSTEM PATCH-SYSTEMS-LIST)
	(WHEN (EQ (PATCH-STATUS PATCH-SYSTEM) :INCONSISTENT)
	  (BEEP)
	  (FORMAT *QUERY-IO* "~&You have loaded patches out of sequence,
 or loaded unreleased patches, in ~A.
As a result, the environment is probably inconsistent with the
current patches and will remain so despite attempts to update it.
Unless you understand these problems well and know how to
be sure whether they are occurring, or how to clean them up,
you should not save this environment."
		  (PATCH-NAME PATCH-SYSTEM))
	  (SEND *QUERY-IO* :CLEAR-INPUT)
	  (UNLESS (YES-OR-NO-P "Dump anyway? ")
	    (RETURN-FROM DISK-SAVE NIL)))))

    ;; This will catch most lossages before the user has waited.
    (UNLESS INCREMENTAL
      (CHECK-PARTITION-SIZE PART-SIZE))

    ;; Prompt now for this rather than waiting through all the initializations.
    (LET ((MAX (OR (MAXIMUM-PARTITION-COMMENT-LENGTH PART-NAME 0) 16.)))
      (SETQ SYSTEM-VERSION
	    (IF NO-QUERY
		(LET ((VERS (SYSTEM-VERSION-INFO T)))
		  (SUBSTRING VERS 0 (MIN (LENGTH VERS) MAX)))
	      (GET-NEW-SYSTEM-VERSION MAX :INCREMENTAL INCREMENTAL))))

    ;; Cause cold boot initializations to happen when rebooted
    ;; and do the BEFORE-COLD initializations now
    (INITIALIZATIONS 'BEFORE-COLD-INITIALIZATION-LIST T)
    (RESET-INITIALIZATIONS 'COLD-INITIALIZATION-LIST)
    (SETQ WHO-LINE-JUST-COLD-BOOTED-P T)
    (LOGOUT)

    ;; Help stop user from getting worried.
    (WHEN INCREMENTAL
      (FORMAT T "~&NOTE: Comparing current memory contents with the original band
will take a few minutes.")
      (PROCESS-SLEEP 120.))

    ;; This can't be a before-cold initialization, because some other
    ;; initializations sometimes type out
    TV:(SHEET-FORCE-ACCESS (INITIAL-LISP-LISTENER)
	 (SEND INITIAL-LISP-LISTENER :REFRESH)
	 (SEND INITIAL-LISP-LISTENER :HOME-CURSOR))

    (CHAOS:RESET)  ;Otherwise, UCODE could lose hacking packets as world dumped.

    ;; Compare all pages with band we booted from,
    ;; record unchanged pages in a bitmap in the band being saved in.
    (WHEN INCREMENTAL
      (SETQ INC-PAGES-SAVED (DISK-SAVE-INCREMENTAL PART-BASE)))

    ;; Check again before updating the partition comment.
    (CHECK-PARTITION-SIZE (+ INC-PAGES-SAVED PART-SIZE))
    (UPDATE-PARTITION-COMMENT PART-NAME SYSTEM-VERSION 0)

    ;; Now shut down the world and check the partition size for real, just
    ;; to make sure that we didn't exceed the size very recently.
    (DOLIST (S TV:ALL-THE-SCREENS) (TV:SHEET-GET-LOCK S))
    (TV:WITH-MOUSE-USURPED
      (WITHOUT-INTERRUPTS
	(SETQ TV:MOUSE-SHEET NIL)
	(DOLIST (S TV:ALL-THE-SCREENS)
	  (SEND S :DEEXPOSE)
	  (TV:SHEET-RELEASE-LOCK S))
	;; The process we are now executing in will look like it was warm-booted when
	;; this saved band is restored.  Suppress the warm-boot message, but disable
	;; and flush the process so it doesn't start running with its state destroyed.
	;; We'd like to :RESET it, but can't because we are still running in it.
	;; If the process is the initial process, it will get a new state and get enabled
	;; during the boot process.
	(PROCESS-DISABLE CURRENT-PROCESS)
	(SET-PROCESS-WAIT CURRENT-PROCESS 'FLUSHED-PROCESS NIL)
	(SETQ CURRENT-PROCESS NIL)
	;; Once more with feeling, and bomb out badly if losing.
	(SETQ MAX-ADDR (FIND-MAX-ADDR))
	(CHECK-PARTITION-SIZE (+ INC-PAGES-SAVED PART-SIZE) T)
	;; Store the size in words rather than pages.  But don't get a bignum!
	(SETF (CLI:AREF (FUNCTION SYSTEM-COMMUNICATION-AREA) %SYS-COM-HIGHEST-VIRTUAL-ADDRESS)
	      (LSH MAX-ADDR 8))
	(DO ((I #o600 (1+ I)))			;Clear the disk error log
	    ((= I #o640))
	  (%P-DPB 0 %%Q-LOW-HALF I)
	  (%P-DPB 0 %%Q-HIGH-HALF I))
	(%DISK-SAVE (IF INCREMENTAL
			(- (SYSTEM-COMMUNICATION-AREA %SYS-COM-MEMORY-SIZE))
		      (SYSTEM-COMMUNICATION-AREA %SYS-COM-MEMORY-SIZE))
		    (CAR L) (CADR L))))))

(DEFUN CHECK-PARTITION-SIZE (PART-SIZE &OPTIONAL EXPOSE-P)
  (LET ((DUMP-SIZE (ESTIMATE-DUMP-SIZE)))
    (WHEN (> DUMP-SIZE PART-SIZE)
      ;; This test is not necessarily accurate, since we have not
      ;; yet shut off the world.  However, it should catch most cases,
      ;; so that this error will be detected before the partition comment
      ;; gets clobbered.
      (AND EXPOSE-P (SEND TV:MAIN-SCREEN :EXPOSE))
      (FERROR NIL "Cannot save, partition too small.  Need at least ~D. pages.~@[~@
                      Warm Boot please.~]" DUMP-SIZE EXPOSE-P))
    DUMP-SIZE))

(DEFUN ESTIMATE-DUMP-SIZE NIL
  (DO ((REGION 0 (1+ REGION))
       (SIZE 0))
      ((= REGION (REGION-LENGTH REGION-LENGTH))
       SIZE)
    ;; Check each region.  If it is free, ignore it.  Otherwise,
    ;; add how many pages it will take to dump it.
    (IF ( (LDB %%REGION-SPACE-TYPE (REGION-BITS REGION))
	   %REGION-SPACE-FREE)
	(SETQ SIZE (+ SIZE (CEILING (REGION-TRUE-FREE-POINTER REGION) PAGE-SIZE))))))

;;; Find the highest address in the virtual memory.  If you call this without
;;; inhibiting interrupts, the result is not strictly correct since some
;;; other process could invalidate it at any time by CONSing.  However,
;;; it gives you a good idea and a lower bound.  The answer is in number
;;; of pages.
(DEFUN FIND-MAX-ADDR ()
  (DO ((REGION 0 (1+ REGION))
       (MAX-ADDR 0))
      ((= REGION (REGION-LENGTH REGION-LENGTH))
       (TRUNCATE MAX-ADDR PAGE-SIZE))
    ;; Check each region.  If it is free, ignore it.  Otherwise,
    ;; find the highest address of that region, and get the
    ;; highest such address.
    (IF ( (LDB %%REGION-SPACE-TYPE (REGION-BITS REGION))
	   %REGION-SPACE-FREE)
	(SETQ MAX-ADDR (MAX MAX-ADDR (+ (REGION-ORIGIN-TRUE-VALUE REGION)
					(REGION-TRUE-LENGTH REGION)))))))

(DEFUN REGION-ORIGIN-TRUE-VALUE (REGION)
  ;; below crock avoids returning a negative number if region starts above
  ;; half way point in address space.  It can make a bignum so be careful!
  (%POINTER-UNSIGNED (REGION-ORIGIN REGION)))

(DEFUN REGION-TRUE-LENGTH (REGION)
  ;; below crock avoids returning a negative number if region has a large
  ;; length. It can make a bignum so be careful!
  (%POINTER-UNSIGNED (REGION-LENGTH REGION)))

(DEFUN REGION-TRUE-FREE-POINTER (REGION)
  ;; below crock avoids returning a negative number if region has a large
  ;; length. It can make a bignum so be careful!
  (%POINTER-UNSIGNED (REGION-FREE-POINTER REGION)))

(DEFUN DISK-RESTORE-DECODE (PARTITION &AUX LOW-16-BITS HI-16-BITS)
  (COND ((NULL PARTITION)
	 (SETQ LOW-16-BITS 0 HI-16-BITS 0))
	((NUMBERP PARTITION)
	 (SETQ LOW-16-BITS (+ #/L (LSH #/O 8)))
	 (SETQ HI-16-BITS (+ #/D (LSH (+ #/0 PARTITION) 8))))
	((OR (SYMBOLP PARTITION) (STRINGP PARTITION))
	 (IF (= (STRING-LENGTH PARTITION) 1)
	     (SETQ PARTITION (STRING-APPEND "LOD" PARTITION))
	   (SETQ PARTITION (STRING PARTITION)))
	 (SETQ LOW-16-BITS (+ (CHAR-UPCASE (AREF PARTITION 0))
			      (LSH (CHAR-UPCASE (AREF PARTITION 1)) 8)))
	 (SETQ HI-16-BITS (+ (CHAR-UPCASE (AREF PARTITION 2))
			     (LSH (CHAR-UPCASE (AREF PARTITION 3)) 8))))
	(T (FERROR NIL "~S is not a valid partition name." PARTITION)))
  (LIST HI-16-BITS LOW-16-BITS))

(DEFUN READ-METER (NAME)
  "Returns the current value of the A Memory metering location named NAME.
A-MEMORY-COUNTER-BLOCK-NAMES is a list of meter names.
A meter stores 32 significant bits."
  (LET ((A-OFF (+ %COUNTER-BLOCK-A-MEM-ADDRESS
		  (OR (FIND-POSITION-IN-LIST NAME A-MEMORY-COUNTER-BLOCK-NAMES)
		      (FERROR NIL "~S is not a valid counter name." NAME)))))
    (WITHOUT-INTERRUPTS				;Try not to get inconsistent numbers
      (DPB (%P-LDB #o2020 (%POINTER-PLUS A-MEMORY-VIRTUAL-ADDRESS A-OFF))
	   #o2020
	   (%P-LDB #o0020 (%POINTER-PLUS A-MEMORY-VIRTUAL-ADDRESS A-OFF))))))

(DEFUN WRITE-METER (NAME VAL)
  "Sets the value of the A Memory metering location named NAME to integer VAL.
A-MEMORY-COUNTER-BLOCK-NAMES is a list of meter names.
A meter stores 32 significant bits."
  (LET ((A-OFF (+ %COUNTER-BLOCK-A-MEM-ADDRESS
		  (OR (FIND-POSITION-IN-LIST NAME A-MEMORY-COUNTER-BLOCK-NAMES)
		      (FERROR NIL "~S is not a valid counter name." NAME)))))
    (WITHOUT-INTERRUPTS
      (%P-DPB (LDB #o2020 VAL)
	      #o2020
	      (%POINTER-PLUS A-MEMORY-VIRTUAL-ADDRESS A-OFF))
      (%P-DPB (LDB #o0020 VAL)			;Must LDB to get correct low bits if bignum!
	      #o0020
	      (%POINTER-PLUS A-MEMORY-VIRTUAL-ADDRESS A-OFF)))))

(DEFUN CHANGE-INDIRECT-ARRAY (ARRAY TYPE DIMLIST DISPLACEDP INDEX-OFFSET
			      &AUX INDEX-LENGTH NDIMS INDIRECT-LENGTH TEM
				   OLD-NDIMS OLD-INDIRECT-LENGTH)
  "Change an indirect array ARRAY's type, size, or target pointed at.
TYPE specifies the new array type, DIMLIST its new dimensions,
DISPLACEDP the target it should point to (array, locative or fixnum),
INDEX-OFFSET the new offset in the new target."
  (CHECK-TYPE ARRAY (AND ARRAY (SATISFIES ARRAY-DISPLACED-P)) "a displaced array")
  (CHECK-TYPE DISPLACEDP (OR ARRAY INTEGER LOCATIVE)
	      "an array or physical address to which to indirect")
  (CHECK-ARG TYPE				;TEM gets the numeric array type
	     (SETQ TEM (COND ((NUMBERP TYPE) (LDB %%ARRAY-TYPE-FIELD TYPE))
			     ((FIND-POSITION-IN-LIST TYPE ARRAY-TYPES))))
	     "an array type")
  (SETQ TYPE TEM)
  (IF (NOT (CONSP DIMLIST))
      ;>> ** BRAINDAMAGE ALERT **
      (SETQ NDIMS 1 INDEX-LENGTH (EVAL DIMLIST))
    (SETQ NDIMS (LENGTH DIMLIST)
	  INDEX-LENGTH (LIST-PRODUCT DIMLIST)))
  (SETQ INDIRECT-LENGTH (IF INDEX-OFFSET 3 2)
	OLD-NDIMS (%P-LDB-OFFSET %%ARRAY-NUMBER-DIMENSIONS ARRAY 0)
	OLD-INDIRECT-LENGTH (%P-LDB-OFFSET %%ARRAY-INDEX-LENGTH-IF-SHORT ARRAY 0))
  (OR (= NDIMS OLD-NDIMS)
      (FERROR NIL "Attempt to change the number of dimensions from ~D to ~D."
	          OLD-NDIMS NDIMS))
  (OR (= INDIRECT-LENGTH OLD-INDIRECT-LENGTH)
      (FERROR NIL "Attempt to add or remove index-offset."))
  (%P-DPB-OFFSET TYPE %%ARRAY-TYPE-FIELD ARRAY 0)
  (AND ARRAY-INDEX-ORDER
       (CONSP DIMLIST)
       (SETQ DIMLIST (REVERSE DIMLIST)))
  (AND (CONSP DIMLIST)
       (DO ((I 1 (1+ I))
	    (N NDIMS (1- N)))
	   ((< N 2))
	 (%P-STORE-CONTENTS-OFFSET (EVAL (CAR DIMLIST)) ARRAY I)
	 (SETQ DIMLIST (CDR DIMLIST))))
  (%P-STORE-CONTENTS-OFFSET DISPLACEDP ARRAY NDIMS)
  (%P-STORE-CONTENTS-OFFSET INDEX-LENGTH ARRAY (1+ NDIMS))
  (WHEN INDEX-OFFSET
    (%P-STORE-CONTENTS-OFFSET INDEX-OFFSET ARRAY (+ NDIMS 2)))
  ARRAY)

(DEFUN LEXPR-FUNCALL-WITH-MAPPING-TABLE (FUNCTION &QUOTE TABLE &EVAL &REST ARGS)
  "Call FUNCTION like LEXPR-FUNCALL but provide mapping table TABLE.
If FUNCTION is a flavor method, this saves it from having to find
the correct flavor mapping table, but it will lose if you give the wrong one."
  (DECLARE (IGNORE TABLE))
  (APPLY #'LEXPR-FUNCALL FUNCTION ARGS))
(DEFF LEXPR-FUNCALL-WITH-MAPPING-TABLE-INTERNAL 'LEXPR-FUNCALL-WITH-MAPPING-TABLE)

(DEFUN FUNCALL-WITH-MAPPING-TABLE (FUNCTION &QUOTE TABLE &EVAL &REST ARGS)
  "Call FUNCTION like FUNCALL but provide mapping table TABLE.
If FUNCTION is a flavor method, this saves it from having to find
the correct flavor mapping table, but it will lose if you give the wrong one."
  (DECLARE (IGNORE TABLE))
  (APPLY FUNCTION ARGS))
(DEFF FUNCALL-WITH-MAPPING-TABLE-INTERNAL 'FUNCALL-WITH-MAPPING-TABLE)

;;; STRING-IO stream handler.  Note that DEFSELECT doesn't work in the cold load.
;;; WITH-INPUT-FROM-STRING and WITH-OUTPUT-FROM-STRING used to compile into calls to this.
;;; It is now obsolete, but present for the sake of old compiled code.

;;; Supported operations:
;;; :TYI, :TYO, :STRING-OUT, :LINE-OUT, :FRESH-LINE, :READ-POINTER -- these are normal
;;; :SET-POINTER -- This works to any location in the string.  If done to an output string,
;;;                 and it hasn't gotten there yet, the string will be extended.  (The
;;;                 elements in between will contain garbage.)
;;; :UNTYI -- you can UNTYI as many characters as you like.  The argument is ignored.
;;; :READ-CURSORPOS, :INCREMENT-CURSORPOS -- These work on the X axis only; they ignore Y.
;;;                 They are defined only for :CHARACTER units; :PIXEL will give an error.
;;; :UNTYO, :UNTYO-MARK -- These exist to keep the grinder happy.
;;; :CONSTRUCTED-STRING -- This is a special operation required by the operation of the
;;;                 WITH-OPEN-STRING macro.  This is how the string is extracted from the
;;;                 stream closure.  You shouldn't need to use this.

(defvar *string-io-string*)
(defvar *string-io-index*)
(defvar *string-io-limit*)
(defvar *string-io-direction*)
(defvar *string-io-stream*)

(defmacro maybe-grow-io-string (index)
  `(if ( ,index *string-io-limit*)
       (adjust-array-size *string-io-string*
			  (setq *string-io-limit* (fix (* (1+ ,index) 1.5s0))))))

(defmacro string-io-add-character (ch)
  `(progn (maybe-grow-io-string *string-io-index*)
	  (setf (char *string-io-string* *string-io-index*) ,ch)
	  (incf *string-io-index*)))

(defmacro string-io-add-line (string start end)
  `(let* ((string-io-length (- ,end ,start))
	  (string-io-finish-index (+ *string-io-index* string-io-length)))
     (maybe-grow-io-string string-io-finish-index)
     (copy-array-portion ,string ,start ,end
			 *string-io-string* *string-io-index* string-io-finish-index)
     (setq *string-io-index* string-io-finish-index)))

(defselect (string-io string-io-default-handler)
  (:tyi (&optional eof)
	(if (< *string-io-index* *string-io-limit*)
	    (prog1 (global:aref *string-io-string* *string-io-index*)
		   (incf *string-io-index*))
	  (and eof (ferror 'sys:end-of-file-1 "End of file on ~S." *string-io-stream*))))
  (:read-char (&optional (eof-error-p t) eof-value)
    (if (< *string-io-index* *string-io-limit*)
	(prog1 (char *string-io-string* *string-io-index*)
	       (incf *string-io-index*))
      (if eof-error-p
	  (ferror 'sys:end-of-file-1 "End of file on ~S." *string-io-stream*)
	eof-value)))
  ((:untyi :unread-char) (ignore)
   (if (minusp (decf *string-io-index*))
       (error "Attempt ~S past beginning -- ~S" :unread-char 'string-io)))
  ((:write-char :tyo) (ch)
   (string-io-add-character ch))
  (:string-out (string &optional (start 0) end)
    (or end (setq end (length string)))
    (string-io-add-line string start end))
  (:line-out (string &optional (start 0) end)
    (or end (setq end (length string)))
    (string-io-add-line string start end)
    (string-io-add-character #/Newline))
  (:fresh-line ()
    (and (plusp *string-io-index*)
	 ( (char *string-io-string* *string-io-index*) #/Newline)
	 (string-io-add-character #/Newline)))
  (:read-pointer ()
    *string-io-index*)
  (:set-pointer (ptr)
    (and (neq *string-io-direction* :in)
	 (< ptr *string-io-limit*)
	 (error "Attempt to ~S beyond end of string -- ~S" :set-pointer 'string-io))
    (setq *string-io-index* ptr))
  (:untyo-mark ()
    *string-io-index*)
  (:untyo (mark)
    (setq *string-io-index* mark))
  (:read-cursorpos (&optional (units :pixel))
    (string-io-confirm-movement-units units)
    (let ((string-io-return-index
	    (string-reverse-search-char #/Newline *string-io-string* *string-io-index*)))
      (if string-io-return-index
	  (- *string-io-index* string-io-return-index)
	*string-io-index*)))
  (:increment-cursorpos (x ignore &optional (units :pixel))
    (string-io-confirm-movement-units units)
    (dotimes (i x) (string-io-add-character #/Space)))
  (:constructed-string ()
    ;; Don't change allocated size if we have a fill pointer!
    (if (array-has-fill-pointer-p *string-io-string*)
	(setf (fill-pointer *string-io-string*) *string-io-index*)
      (setq *string-io-string*
	    (adjust-array-size *string-io-string* *string-io-index*)))))

(defun string-io-default-handler (op &optional arg1 &rest rest)
  (stream-default-handler 'string-io op arg1 rest))

(defun string-io-confirm-movement-units (units)
  (if (neq units :character)
      (ferror nil "Unimplemented cursor-movement unit ~A -- STRING-IO." units)))


;;;; Super-hairy module support

(DEFVAR *MODULES* NIL
  "List of modules marked present with PROVIDE.
All systems loaded with MAKE-SYSTEM are also present.
Keyed by STRING=")

(DEFUN PROVIDE (MODULE)
  "Mark MODULE as being already loaded."
  (PUSHNEW (STRING MODULE) *MODULES* :TEST #'STRING=))

(DEFUN REQUIRE (MODULE &OPTIONAL PATHNAMES)
  "Cause MODULE to be loaded if it isn't yet.
If PATHNAMES is specified, it should be a pathname or a list of pathnames;
 those files are loaded.
Otherwise, MAKE-SYSTEM is done on MODULE."
  (UNLESS (MEM #'STRING= MODULE *MODULES*)
    (COND ((CONSP PATHNAMES)
	   (MAPC #'LOAD PATHNAMES))
	  (PATHNAMES (LOAD PATHNAMES))
	  (T (MAKE-SYSTEM MODULE)))))
