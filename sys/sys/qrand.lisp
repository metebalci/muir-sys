;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Cold-Load:T; Base:8; Readtable:T -*-

;	** (c) Copyright 1980 Massachusetts Institute of Technology **

;;; This file contains random functions which must be in the cold load

;;; Used to be in sys2; numer but needed in the cold-load
(defconst most-negative-fixnum (%logdpb 1 %%q-boxed-sign-bit 0)
  "Any integer smaller than this must be a bignum.")

(defconst most-positive-fixnum (%logdpb 0 %%q-boxed-sign-bit -1)
  "Any integer larger than this must be a bignum.")

;;; SPECIAL, UNSPECIAL, PUTPROP, and REMPROP are here because
;;; various qfasl files in the cold load will cause these to
;;; be called at initial startup.

;;; These definitions of SPECIAL and UNSPECIAL are for QLD time only.
;;; They are replaced by other definitions in the compiler.
(DEFUN SPECIAL (&REST &QUOTE SYMBOLS)
  (MAPC #'(LAMBDA (X) (SETF (GET X 'SPECIAL) T))
	SYMBOLS)
  T)

(DEFUN UNSPECIAL (&REST &QUOTE SYMBOLS)
  (MAPC #'(LAMBDA (X) (REMPROP X 'SPECIAL))
	SYMBOLS)
  T)

(DEFUN IGNORE (&REST IGNORE)
  "Discard any number of arguments and return NIL."
  NIL)

;;; Note: this used to be done with an explicit SETQ so that it would happen
;;; inside the cold-load generator rather than as part of LISP-CRASH-LIST.
;;; However, now it should happen inside the cold load generator anyway.
(DEFVAR AREA-FOR-PROPERTY-LISTS PROPERTY-LIST-AREA
  "Area for consing property lists of interned symbols in.")

(DEFUN GET (SYMBOL-OR-PLIST PROPERTY &OPTIONAL DEFAULT)
  "Returns the value of SYMBOL-OR-PLIST's PROPERTY property.
If there is no property, DEFAULT is returned.
SYMBOL-OR-PLIST may be a symbol or a disembodied property list -
a list or locative whose cdr stores the properties.
It may also be an instance or named structure; then its :GET method is used."
  (GET SYMBOL-OR-PLIST PROPERTY DEFAULT))


(DEFUN GET-PROPERTIES-INTERNAL (LOCATION LIST-OF-PROPERTIES)
  (LET ((TEM (GETL LOCATION LIST-OF-PROPERTIES)))
    (IF TEM (VALUES (CAR TEM) (CADR TEM) TEM))))

(DEFUN PUTPROP (SYMBOL-OR-PLIST VALUE PROPERTY &AUX PLLOC)
  "Make the value of SYMBOL-OR-PLIST's PROPERTY property be VALUE.
SYMBOL-OR-PLIST may be a symbol or a disembodied property list -
a list or locative whose cdr stores the properties.
It may also be an instance or named structure; then its :PUTPROP method is used.
VALUE is returned."
;  (UNLESS (VARIABLE-BOUNDP AREA-FOR-PROPERTY-LISTS)
;    (SETQ AREA-FOR-PROPERTY-LISTS PROPERTY-LIST-AREA))
  (ETYPECASE SYMBOL-OR-PLIST
    ((OR SYMBOL CONS LOCATIVE)
     (WITHOUT-INTERRUPTS
       (SETQ PLLOC (GET-LOCATION-OR-NIL SYMBOL-OR-PLIST PROPERTY))
       (IF PLLOC
	   (SETF (CAR PLLOC) VALUE)
	 (SETQ PLLOC (COND ((SYMBOLP SYMBOL-OR-PLIST)
			    (PROPERTY-CELL-LOCATION SYMBOL-OR-PLIST))
			   (T SYMBOL-OR-PLIST)))
	 (RPLACD PLLOC (LIST*-IN-AREA (IF (= (%AREA-NUMBER SYMBOL-OR-PLIST)
					     NR-SYM)
					  PROPERTY-LIST-AREA
					BACKGROUND-CONS-AREA)
				      PROPERTY VALUE (CDR PLLOC))))))
    ((OR INSTANCE NAMED-STRUCTURE)
     (SEND SYMBOL-OR-PLIST :PUTPROP VALUE PROPERTY)))
  VALUE)

;;; Implements SETF of GET.
(DEFUN SETPROP (SYMBOL-OR-PLIST PROPERTY VALUE &AUX PLLOC)
;  (UNLESS (VARIABLE-BOUNDP AREA-FOR-PROPERTY-LISTS)
;    (SETQ AREA-FOR-PROPERTY-LISTS PROPERTY-LIST-AREA))
  (ETYPECASE SYMBOL-OR-PLIST
    ((OR SYMBOL CONS LOCATIVE)
     (WITHOUT-INTERRUPTS
       (SETQ PLLOC (GET-LOCATION-OR-NIL SYMBOL-OR-PLIST PROPERTY))
       (IF PLLOC
	   (SETF (CAR PLLOC) VALUE)
	 (SETQ PLLOC (COND ((SYMBOLP SYMBOL-OR-PLIST)
			    (PROPERTY-CELL-LOCATION SYMBOL-OR-PLIST))
			   (T SYMBOL-OR-PLIST)))
	 (RPLACD PLLOC (LIST*-IN-AREA (IF (= (%AREA-NUMBER SYMBOL-OR-PLIST)
					     NR-SYM)
					  PROPERTY-LIST-AREA
					BACKGROUND-CONS-AREA)
				      PROPERTY VALUE (CDR PLLOC))))))
    ((OR INSTANCE NAMED-STRUCTURE)
     (SEND SYMBOL-OR-PLIST :PUTPROP VALUE PROPERTY)))
  VALUE)

(DEFUN DEFPROP (&QUOTE SYMBOL VALUE PROPERTY)
  "Make the value of SYMBOL's PROPERTY property be VALUE."
  (PUTPROP SYMBOL VALUE PROPERTY)
  SYMBOL)

(DEFUN REMPROP (SYMBOL-OR-PLIST PROPERTY &AUX PLLOC)
  "Remove a property.  Returns NIL if not present, or a list whose CAR is the property.
SYMBOL-OR-PLIST may be a symbol or a disembodied property list -
a list or locative whose cdr stores the properties.
It may also be an instance or named structure; then it is sent a :REMPROP message."
  (ETYPECASE SYMBOL-OR-PLIST
    ((OR SYMBOL CONS LOCATIVE)
     (SETQ PLLOC (COND ((SYMBOLP SYMBOL-OR-PLIST)
			(PROPERTY-CELL-LOCATION SYMBOL-OR-PLIST))
		       (T SYMBOL-OR-PLIST)))
     (LET ((INHIBIT-SCHEDULING-FLAG T))		;atomic
       (DO ((PL (CDR PLLOC) (CDDR PL))
	    (PPL PLLOC (CDR PL)))
	   ((NULL PL) NIL)
	 (COND ((EQ (CAR PL) PROPERTY)
		(RPLACD PPL (CDDR PL))
		(RETURN (CDR PL)))))))
    ((OR INSTANCE NAMED-STRUCTURE)
     (SEND SYMBOL-OR-PLIST :REMPROP PROPERTY))))

(DEFUN PROPERTY-LIST-HANDLER (OP PLIST &REST ARGS)
  (CASE OP
    (:GET
     (GET PLIST (FIRST ARGS) (SECOND ARGS)))
    (:GET-LOCATION-OR-NIL
     (GET-LOCATION-OR-NIL PLIST (FIRST ARGS)))
    (:GET-LOCATION
      (LOCF (GET PLIST (FIRST ARGS))))
    (:GETL
     (GETL PLIST (CAR ARGS)))
    (:PUTPROP
     (SETF (GET PLIST (SECOND ARGS)) (FIRST ARGS)))
    (:REMPROP
     (REMPROP PLIST (CAR ARGS)))
    (:PUSH-PROPERTY
     (PUSH (FIRST ARGS) (GET PLIST (SECOND ARGS))))
    ((:PLIST :PROPERTY-LIST)
     (CONTENTS PLIST))
    ((:PLIST-LOCATION :PROPERTY-LIST-LOCATION)
     PLIST)
    ((:SETPLIST :SET-PROPERTY-LIST)
     (SETF (CONTENTS PLIST) (FIRST ARGS)))
    (:SET
     (CASE (FIRST ARGS)
       (:GET
	(SETF (GET PLIST (SECOND ARGS)) (CAR (LAST ARGS))))
       ((:PLIST :PROPERTY-LIST) (SETF (CONTENTS PLIST) (SECOND ARGS)))
       (:WHICH-OPERATIONS '(:GET :PLIST :PROPERTY-LIST :WHICH-OPERATIONS))
       (T (FERROR NIL "Don't know how to :SET ~S" (FIRST ARGS)))))
    (:WHICH-OPERATIONS '(:GET :GET-LOCATION :GET-LOCATION-OR-NIL :GETL :PUTPROP :REMPROP
			 :PUSH-PROPERTY :PLIST :PROPERTY-LIST :PLIST-LOCATION
			 :PROPERTY-LIST-LOCATION :SET :SETPLIST :SET-PROPERTY-LIST
			 :WHICH-OPERATIONS))
    (T (FERROR NIL "Don't know how to ~S a plist" OP))))

(DEFMACRO ROT-24-BIT (VALUE BITS)
  (ONCE-ONLY (VALUE BITS)
    `(DPB ,VALUE (BYTE (- 24. ,BITS) ,BITS)
	  (LSH ,VALUE (- ,BITS 24.)))))

;;; We hairily arrange to return the same value as we did in the days of 24 bit pointers.
;;; This is to avoid making everything look "changed" when the switch happens.
(DEFUN SXHASH (X &OPTIONAL RANDOM-OBJECT-ACTION)
  "Return a hash code for object X.  EQUAL objects have the same hash code.
The hash code is always a positive fixnum.
Flavor instances and named structures may handle the :SXHASH operation
/(with one arg, passed along from RANDOM-OBJECT-ACTION) to compute their hash codes.
If RANDOM-OBJECT-ACTION is non-NIL, the ultimate default is to use the
object's address to compute a hash code.  This only happens for
objects which cannot be EQUAL unless they are EQ.
If RANDOM-OBJECT-ACTION is NIL, the hash code of an object does not
change even if it is printed out and read into a different system version."
  (COND ((SYMBOLP X) (%SXHASH-STRING (SYMBOL-NAME X) #o337))
	((STRINGP X) (%SXHASH-STRING X #o337))	;Ignores case!
	((OR (INTEGERP X) (CHARACTERP X))
	 (IF (MINUSP X) (LOGXOR (LDB 23. X) 1) (LDB 23. X)))
	((CONSP X)		;Rotate car by 11. and cdr by 7, but do it efficiently
	 (DO ((ROT 4) (HASH 0) Y (X X))
	     ((ATOM X)
	      (OR (NULL X)
		  (SETQ HASH (LOGXOR (ROT-24-BIT (SXHASH X RANDOM-OBJECT-ACTION)
						 (- ROT 4))
				     HASH)))
	      (LOGAND #o37777777 (IF (LDB-TEST (BYTE 1 23.) HASH) (LOGXOR HASH 1) HASH)))
	   (SETQ Y (CAR X) X (CDR X))
	   (OR (< (SETQ ROT (+ ROT 7)) 24.) (SETQ ROT (- ROT 24.)))
	   (SETQ HASH (LOGXOR (ROT-24-BIT
				(COND ((SYMBOLP Y) (%SXHASH-STRING (SYMBOL-NAME Y) #o337))
				      ((STRINGP Y) (%SXHASH-STRING Y #o337))
				      ((OR (INTEGERP X) (CHARACTERP X))
				       (LDB 24. Y))
				      (T (SXHASH Y RANDOM-OBJECT-ACTION)))
				ROT)
			      HASH))))
	((FLONUMP X) (LOGXOR (%P-LDB-OFFSET #o0027 X 1)
			     (%P-LDB-OFFSET #o2701 X 1)
			     (%P-LDB #o0022 X)))
	((AND (TYPEP X 'INSTANCE)
	      (SEND X :SEND-IF-HANDLES :SXHASH RANDOM-OBJECT-ACTION)))
	((AND (TYPEP X 'NAMED-STRUCTURE)
	      (MEMQ :SXHASH (NAMED-STRUCTURE-INVOKE :WHICH-OPERATIONS X)))
	      (NAMED-STRUCTURE-INVOKE :SXHASH X RANDOM-OBJECT-ACTION))
	((OR RANDOM-OBJECT-ACTION
	     (SMALL-FLOATP X))
	 (SETQ X (%POINTER X))
	 (LET ((Y (LOGXOR (LDB (- %%Q-POINTER 24.) X)
			  (LSH X (- 24. %%Q-POINTER)))))
	 (LOGAND #o37777777
		 (IF (MINUSP X) (LOGXOR Y 1) Y))))
	((ARRAYP X)
	 (ARRAY-ACTIVE-LENGTH X))
	(T 0)))					;0 for things that can't be read

(DEFUN GET-MACRO-ARG-DESC-POINTER (FEF-POINTER &AUX ORIGIN)
  "Return a pointer to the argument descriptor list of a compiled function.
This list describes how to bind the arguments and how to initialize them."
  (CHECK-TYPE FEF-POINTER COMPILED-FUNCTION "a FEF pointer")
  (COND ((= 1 (%P-LDB-OFFSET %%FEFH-NO-ADL FEF-POINTER %FEFHI-IPC))
	 NIL)
	((= 0 (SETQ ORIGIN
		    (%P-LDB-OFFSET %%FEFHI-MS-ARG-DESC-ORG FEF-POINTER %FEFHI-MISC)))
	 NIL)
	(T (%MAKE-POINTER-OFFSET DTP-LIST FEF-POINTER ORIGIN))))

;;; Ordered as per ARRAY-TYPES
(DEFCONST ARRAY-ELEMENT-TYPE-ALIST
	  '((NIL . ART-ERROR)
	    (BIT . ART-1B)
	    ((MOD 4) . ART-2B)
	    ((MOD 8) . ART-4B)
	    ((MOD #o400) . ART-8B)
	    ((MOD #o200000) . ART-16B)
	    (FIXNUM . ART-32B)
	    (T . ART-Q)
	    (T . ART-Q-LIST)
	    (STRING-CHAR . ART-STRING)
	    (T . ART-STACK-GROUP-HEAD)
	    (T . ART-SPECIAL-PDL)
	    ((SIGNED-BYTE #o20) . ART-HALF-FIX)
	    (T . ART-REG-PDL)
	    (FLOAT . ART-FLOAT)
	    (FLOAT . ART-FPS-FLOAT)
	    (FAT-CHAR . ART-FAT-STRING)
	    ((COMPLEX FLOAT) . ART-COMPLEX-FLOAT)
	    (COMPLEX . ART-COMPLEX)
	    ((COMPLEX FLOAT) . ART-COMPLEX-FPS-FLOAT)
	    ((UNSIGNED-BYTE 1) . ART-1B)
	    ((UNSIGNED-BYTE 2) . ART-2B)
	    ((UNSIGNED-BYTE 4) . ART-4B)
	    ((UNSIGNED-BYTE #o10) . ART-8B)
	    ((UNSIGNED-BYTE #o20) . ART-16B)
	    ((SIGNED-BYTE #o20) . ART-HALF-FIX)))

;;; can't find anything that uses this...
(DEFCONST ARRAY-ELEMENT-SIZE-ALIST
	  '((#o2 . ART-1B)
	    (#o4 . ART-2B)
	    (#o20 . ART-4B)
	    (#o400 . ART-8B)
	    (#o200000 . ART-16B)))

;;; array-type-from-element-type now in SYS2; TYPES
	 
(DEFUN ARRAY-CANONICALIZE-TYPE (TYPE &AUX FOO)
  (COND ((MEMQ TYPE ARRAY-TYPES) TYPE)
	((SETQ FOO (FIND-POSITION-IN-LIST TYPE ARRAY-TYPE-KEYWORDS))
	 (NTH FOO ARRAY-TYPES))
	((FIXNUMP TYPE)
	 (IF (NOT (ZEROP (LDB %%ARRAY-TYPE-FIELD TYPE)))
	     (SETQ TYPE (LDB %%ARRAY-TYPE-FIELD TYPE)))
	 (NTH TYPE ARRAY-TYPES))
	(T (ARRAY-TYPE-FROM-ELEMENT-TYPE TYPE))))

(DEFUN ARRAY-TYPE-NULL-ELEMENT (TYPE)
  (CDR (ASSQ (ARRAY-CANONICALIZE-TYPE TYPE)
	     '((ART-ERROR . NIL)
	       (ART-1B . 0)
	       (ART-2B . 0)
	       (ART-4B . 0)
	       (ART-8B . 0)
	       (ART-16B . 0)
	       (ART-32B . 0)
	       (ART-Q . NIL)
	       (ART-Q-LIST . NIL)
	       (ART-STRING . #/ )
	       (ART-STACK-GROUP-HEAD . NIL)
	       (ART-SPECIAL-PDL . NIL)
	       (ART-HALF-FIX . 0)
	       (ART-REG-PDL . NIL)
	       (ART-FLOAT . 0f0)
	       (ART-FPS-FLOAT . 0f0)
	       (ART-FAT-STRING . #/ )
;;;---!!! MAKE-COLD doesn't support complex types.
;;;---!!!	       (ART-COMPLEX-FLOAT . 0f0+0f0i)
	       (ART-COMPLEX . 0)
;;;---!!! MAKE-COLD doesn't support complex types.
;;;---!!!	       (ART-COMPLEX-FPS-FLOAT 0f0+0f0i)
	       ))))

(DEFUN ARRAY-ELEMENT-TYPE (ARRAY)
  "Return a Common Lisp data type describing the objects that could be stored in ARRAY."
  (OR (CAR (RASSQ (ARRAY-TYPE ARRAY) ARRAY-ELEMENT-TYPE-ALIST))
      T))

(DEFUN ADJUSTABLE-ARRAY-P (ARRAY)
  "A Common Lisp function which returns T if ARRAY is an adjustable array (ie may have
ADJUST-ARRAY applied to it) This is true for all arrays on the Lisp Machine."
  (CHECK-TYPE ARRAY ARRAY)
  T)

;;; DEFVAR to NIL with a SETQ insures it will never be unbound.
;;; The SETQ now happens in installing packages.
(DEFVAR ARRAY-TYPE-KEYWORDS NIL
  "List of keywords which have pnames matching the array type symbols.")

(DEFCONST ARRAY-TOTAL-SIZE-LIMIT (ASH 1 %%Q-POINTER)
  "The total number of elements in any array must be less than this.")

(DEFCONST ARRAY-DIMENSION-LIMIT (ASH 1 %%Q-POINTER)
  "Every dimension of an array must be less than this.")

(DEFCONST ARRAY-RANK-LIMIT 8
  "The rank of an array must be less than this.")

;;; This is the new version of MAKE-ARRAY.  It takes the old argument
;;; format as well as the new one, with heuristics to disambiguate whether
;;; a given call is old-style or new-style.
(DEFUN MAKE-ARRAY (DIMENSIONS &REST OPTIONS)
  "Create an array of size DIMENSIONS (a number or list of numbers).
The keywords are as follows:
:TYPE - specify array type, controlling type of elements allowed.  Default is ART-Q.
 ART-Q (any elements), ART-Q-LIST (any elements, and the contents looks like a list),
 ART-STRING (elements 0 through 255, printed with quotes),
 ART-FAT-STRING (16 bit unsigned elements, printed with quotes),
 ART-1B (elements 0 and 1), ART-2B (elements 0 through 3), ART-4B, ART-8B, ART-16B,
 ART-32B (elements any fixnum), ART-FLOAT (elements any full-size flonum),
 ART-COMPLEX (elements any number including complex numbers),
 ART-COMPLEX-FLOAT (elements complex numbers composed of two full-size flonums),
 ART-HALF-FIX (16 bit signed fixnum elements),
 ART-FPS-FLOAT ART-COMPLEX-FPS-FLOAT (used with floating point array processor),
 ART-STACK-GROUP-HEAD, ART-REGULAR-PDL, ART-SPECIAL-PDL (parts of stack groups).
:ELEMENT-TYPE - specify array type by specifying Common Lisp
 data type of elements allowed.  For example,
 an :ELEMENT-TYPE of (MOD 4) would get an ART-2B array.
:AREA - specify area to create the array in.
:LEADER-LENGTH - specify number of elements of array leader to make.
:LEADER-LIST - list whose elements are used to initialize the leader.
:FILL-POINTER - specify initial fill pointer value (ARRAY-ACTIVE-LENGTH of the array).
 Requests a leader of length 1 and specifies the contents of the slot.
:INITIAL-ELEMENT - value used to initialize all elements of the array.
:DISPLACED-TO - array, locative or fixnum specifying address of data
 that this array should overlap.
:DISPLACED-INDEX-OFFSET - if displaced to another array, this specifies
 which element of that array should correspond to element 0 of the new one.
:NAMED-STRUCTURE-SYMBOL - if not NIL, specifies a named structure symbol
 to be stored in the array, which should have its named-structure bit set.
:INITIAL-CONTENTS - value is a sequence of sequences of sequences...
 where the leaves are the values to initialize the array from.
 The top level of sequence corresponds to the most slowly varying subscript."
  (DECLARE (ARGLIST DIMENSIONS &KEY ELEMENT-TYPE INITIAL-ELEMENT INITIAL-CONTENTS
		    		    FILL-POINTER DISPLACED-TO DISPLACED-INDEX-OFFSET
				    TYPE AREA LEADER-LENGTH LEADER-LIST NAMED-STRUCTURE-SYMBOL
				    ADJUSTABLE))
  (LET ((LENGTH-OF-OPTIONS (LENGTH OPTIONS))
	ENTRIES-PER-Q
	LEADER-LIST FILL-POINTER DISPLACED-TO DISPLACED-INDEX-OFFSET NAMED-STRUCTURE-SYMBOL
	(AREA NIL) (TYPE 'ART-Q) TYPE-P ELEMENT-TYPE-P
	INITIAL-ELEMENT INITIAL-ELEMENT-P INITIAL-CONTENTS INITIAL-CONTENTS-P
	ARRAY N-DIMENSIONS INDEX-LENGTH LONG-ARRAY-P LEADER-QS DATA-LENGTH LEADER-LENGTH)
    ;; Figure out whether it is old-style.
    (COND ((AND ( LENGTH-OF-OPTIONS 2)
		(OR (NUMBERP (FIRST OPTIONS))
		    (MEMQ (FIRST OPTIONS) ARRAY-TYPES)
		    (MEMQ (FIRST OPTIONS) ARRAY-TYPE-KEYWORDS)))
	   ;; It is old-style.  The first arg is actually AREA.
	   (SETQ AREA DIMENSIONS)
	   (SETQ TYPE (FIRST OPTIONS))
	   (SETQ DIMENSIONS (SECOND OPTIONS))
	   (SETQ DISPLACED-TO (THIRD OPTIONS))
	   (SETQ LEADER-LIST (FOURTH OPTIONS))
	   (SETQ DISPLACED-INDEX-OFFSET (FIFTH OPTIONS))
	   (SETQ NAMED-STRUCTURE-SYMBOL (SIXTH OPTIONS))
	   (IF (NUMBERP LEADER-LIST)
	       (SETQ LEADER-LENGTH LEADER-LIST
		     LEADER-LIST NIL)
	     (SETQ LEADER-LIST (REVERSE LEADER-LIST))))
	  (T
	   ;; It is new-style.
	   (UNLESS (EVENP LENGTH-OF-OPTIONS)
	     (FERROR NIL "Odd-length options list: ~S" OPTIONS))
	   (DO ((O OPTIONS (CDDR O)))
	       ((NULL O))
	     (LET ((VALUE (CADR O)))
	       (CASE (CAR O)
		 (:AREA (SETQ AREA VALUE))
		 (:TYPE (SETQ TYPE-P T)
			(SETQ TYPE (ARRAY-CANONICALIZE-TYPE VALUE)))
		 (:ELEMENT-TYPE (SETQ ELEMENT-TYPE-P T)
		  (SETQ TYPE (ARRAY-TYPE-FROM-ELEMENT-TYPE VALUE)))
		 (:DISPLACED-INDEX-OFFSET
		  (SETQ DISPLACED-INDEX-OFFSET VALUE))
		 (:DISPLACED-TO (SETQ DISPLACED-TO VALUE))
		 ((:INITIAL-ELEMENT :INITIAL-VALUE)
		  (SETQ INITIAL-ELEMENT VALUE INITIAL-ELEMENT-P T))
		 (:INITIAL-CONTENTS
		  (SETQ INITIAL-CONTENTS VALUE INITIAL-CONTENTS-P T))
		 (:FILL-POINTER (SETQ LEADER-LENGTH (MAX 1 (OR LEADER-LENGTH 1)))
				(SETQ FILL-POINTER VALUE))
		 (:ADJUSTABLE)
		 (:LEADER-LIST (SETQ LEADER-LIST VALUE))
		 (:LEADER-LENGTH (SETQ LEADER-LENGTH VALUE))
;		 (:OLD-LEADER-LENGTH-OR-LIST (IF (NUMBERP VALUE)
;						 (SETQ LEADER-LENGTH VALUE)
;					       (SETQ LEADER-LIST (REVERSE VALUE))))
		 (:NAMED-STRUCTURE-SYMBOL (SETQ NAMED-STRUCTURE-SYMBOL VALUE))
		 (OTHERWISE
		  (FERROR NIL "~S is not a known MAKE-ARRAY keyword." (FIRST OPTIONS))))))))
    (IF (AND TYPE-P ELEMENT-TYPE-P)
	(FERROR NIL "Both :TYPE and :ELEMENT-TYPE specified."))
    (IF (AND DISPLACED-INDEX-OFFSET (NOT DISPLACED-TO))
	(FERROR NIL "The :DISPLACED-INDEX-OFFSET option specified without :DISPLACED-TO."))
    (IF (AND INITIAL-ELEMENT-P INITIAL-CONTENTS-P)
	(FERROR NIL "Both :INITIAL-ELEMENT and :INITIAL-CONTENTS specified."))
    ;; Process the DIMENSIONS argument.
    (CHECK-TYPE DIMENSIONS (OR FIXNUM LIST))
    (COND ((FIXNUMP DIMENSIONS)
	   (IF (MINUSP DIMENSIONS)
	       (FERROR NIL "The negative array length ~S is illegal." DIMENSIONS))
	   (SETQ N-DIMENSIONS 1
		 INDEX-LENGTH DIMENSIONS))
	  ((OR (NULL DIMENSIONS) (CONSP DIMENSIONS))
	   (DOLIST (DIM DIMENSIONS)
	     (UNLESS (FIXNUMP DIM)
	       (FERROR NIL "The dimension ~S is not a fixnum." DIM))
	     (IF (MINUSP DIM)
		 (FERROR NIL "The negative array dimension ~S is illegal." DIM)))
	   (SETQ N-DIMENSIONS (LENGTH DIMENSIONS))
	   (IF (> N-DIMENSIONS ARRAY-RANK-LIMIT)
	       (FERROR NIL "Arrays may only at most ~D, dimensions, not ~S"
		       ARRAY-RANK-LIMIT N-DIMENSIONS))
	   (SETQ INDEX-LENGTH (APPLY #'TIMES DIMENSIONS))))	;* loses in cold load, TIMES wins.
    ;; Process the DISPLACED-TO argument.
    (CHECK-TYPE DISPLACED-TO (OR NULL FIXNUM ARRAY LOCATIVE))
    ;; See whether this is a "short" or "long" format array.
    (IF (AND (> INDEX-LENGTH %ARRAY-MAX-SHORT-INDEX-LENGTH)
	     (NOT DISPLACED-TO))
	(SETQ LONG-ARRAY-P T))
    (OR (FIXNUMP INDEX-LENGTH)
	(FERROR NIL "Attempt to make array too large; total length ~S" INDEX-LENGTH))
    ;; Process the LEADER and NAMED-STRUCTURE-SYMBOL arguments.
    (CHECK-TYPE LEADER-LIST LIST)
    (AND (NULL LEADER-LENGTH) (NOT (NULL LEADER-LIST))
	 (SETQ LEADER-LENGTH (LENGTH LEADER-LIST)))
    (IF (AND LEADER-LENGTH (> (LENGTH LEADER-LIST) LEADER-LENGTH))
	(FERROR NIL "Length of leader initialization list is greater than leader length"))
    (COND (NAMED-STRUCTURE-SYMBOL
	   (IF LEADER-LENGTH
	       (SETQ LEADER-LENGTH (MAX LEADER-LENGTH 2))
	     (UNLESS (= N-DIMENSIONS 1)
	       (FERROR NIL "A named-structure array may not be ~D-dimensional"
		       N-DIMENSIONS))))
	  (LEADER-LENGTH
	   (CHECK-TYPE LEADER-LENGTH (INTEGER 0))))
    (SETQ LEADER-QS (IF LEADER-LENGTH
			(+ 2 LEADER-LENGTH)
		        0))
    ;; Process the TYPE argument.
    (CHECK-ARG TYPE (OR (FIXNUMP TYPE)
			(MEMQ TYPE ARRAY-TYPES)
			(MEMQ TYPE ARRAY-TYPE-KEYWORDS))
	       "an array type")
    (IF (FIXNUMP TYPE)
	;; may be either a small integer, which is shifted over into the type field,
	;; or an already shifted over quantity (such as ART-Q, etc).
	(IF (NOT (ZEROP (LDB %%ARRAY-TYPE-FIELD TYPE)))
	    (SETQ TYPE (LDB %%ARRAY-TYPE-FIELD TYPE)))
      (IF (FIXNUMP (SYMBOL-VALUE TYPE))
	  (SETQ TYPE (LDB %%ARRAY-TYPE-FIELD (SYMBOL-VALUE TYPE)))
	(SETQ TYPE (FIND-POSITION-IN-LIST TYPE ARRAY-TYPE-KEYWORDS))))
    (SETQ ENTRIES-PER-Q (ARRAY-ELEMENTS-PER-Q TYPE))
    ;; This is positive if there are 1 or more entries per Q.  It is
    ;; negative if there are more than one Qs per entry.
    (SETQ DATA-LENGTH (IF (PLUSP ENTRIES-PER-Q)
			  (CEILING INDEX-LENGTH ENTRIES-PER-Q)
			(* INDEX-LENGTH (MINUS ENTRIES-PER-Q))))
    ;; Process the DISPLACED-INDEX-OFFSET argument.
    (CHECK-TYPE DISPLACED-INDEX-OFFSET (OR NULL (FIXNUM 0)))
    (LET ((HEADER-WORD
	    ;; Put in array type and number of dims.
	    (%LOGDPB N-DIMENSIONS %%ARRAY-NUMBER-DIMENSIONS
		     (%LOGDPB TYPE %%ARRAY-TYPE-FIELD 0))))
      ;; If there is a leader, set the flag.
      (IF LEADER-LENGTH
	  (SETQ HEADER-WORD (%LOGDPB 1 %%ARRAY-LEADER-BIT HEADER-WORD)))
      (SETQ HEADER-WORD
	    (COND (DISPLACED-TO
		   ;; Array is displaced; turn on the bit, and the array is 2 long
		   ;; plus one for the index-offset if any.
		   (+ (%LOGDPB 1 %%ARRAY-DISPLACED-BIT HEADER-WORD)
		      (IF DISPLACED-INDEX-OFFSET 3 2)))
		  (LONG-ARRAY-P
		   ;; It is local; if it is a long array, the length is not in the
		   ;; header at all; set the bit instead.
		   (%LOGDPB 1 %%ARRAY-LONG-LENGTH-FLAG HEADER-WORD))
		  (T
		   ;; It is a short array; the length is in the header.
		   (+ INDEX-LENGTH HEADER-WORD))))
      ;; Create the array.
      (SETQ ARRAY (%ALLOCATE-AND-INITIALIZE-ARRAY HEADER-WORD
						  INDEX-LENGTH
						  (OR LEADER-LENGTH 0)
						  AREA
						  (+ (MAX 1 N-DIMENSIONS)
						     LEADER-QS
						     (COND (DISPLACED-TO
							    (IF DISPLACED-INDEX-OFFSET 3 2))
							   (LONG-ARRAY-P
							    (1+ DATA-LENGTH))
							   (T DATA-LENGTH)))
						  )))
    (WHEN (CONSP DIMENSIONS)
      ;; It is a multi-dimensional array.  Fill in the "dope vector".
      ;; If last index varies fastest, put in all but first dimension,
      ;; and the last dimensions come last.
      (DO ((DIMLIST (CDR DIMENSIONS) (CDR DIMLIST))
	   (I (+ N-DIMENSIONS (IF LONG-ARRAY-P 0 -1)) (1- I)))
	  ((NULL DIMLIST))
	(%P-STORE-CONTENTS-OFFSET (CAR DIMLIST) ARRAY I)))
    (COND (DISPLACED-TO
	   ;; It is displaced.  Put information after the dope vector, and after
	   ;; the "long array" word if any.
	   (LET ((IDX (IF LONG-ARRAY-P (1+ N-DIMENSIONS) N-DIMENSIONS)))
	     (%P-STORE-CONTENTS-OFFSET DISPLACED-TO ARRAY IDX)
	     (%P-STORE-CONTENTS-OFFSET INDEX-LENGTH ARRAY (1+ IDX))
	     (COND (DISPLACED-INDEX-OFFSET
		    ;; Index offset feature is in use.
		    ;; Store the index offset in the next Q.
		    (%P-STORE-CONTENTS-OFFSET DISPLACED-INDEX-OFFSET ARRAY (+ IDX 2)))))))
    ;; The leader's initial values were specified.
    (DO ((I 0 (1+ I))
	 (LEADER-LIST LEADER-LIST (CDR LEADER-LIST)))
	((NULL LEADER-LIST))
      (SETF (ARRAY-LEADER ARRAY I) (CAR LEADER-LIST)))
    (AND FILL-POINTER
	 (SETF (FILL-POINTER ARRAY) FILL-POINTER))
    ;; Cretinism associated with make-array, in that the leader list can overlap
    ;; with the name-structure slot, which is how fasd dumps the named-structure-symbol
    ;; So we check for the symbol being t and not smash it in that case
    (WHEN NAMED-STRUCTURE-SYMBOL
      (IF (NULL LEADER-LENGTH)
	  ;; There is no leader; put it in element zero of the body.
	  (SETF (AREF ARRAY 0) NAMED-STRUCTURE-SYMBOL)
	;; There is a leader; use element one of the leader.
	(IF (NEQ NAMED-STRUCTURE-SYMBOL T)
	    (SETF (ARRAY-LEADER ARRAY 1) NAMED-STRUCTURE-SYMBOL)))
      ;; It is a named structure.  Set the flag.
      (%P-DPB-OFFSET 1 %%ARRAY-NAMED-STRUCTURE-FLAG ARRAY 0))
    (AND INITIAL-ELEMENT-P (NOT DISPLACED-TO)
	 (ARRAY-INITIALIZE ARRAY INITIAL-ELEMENT))
    (WHEN INITIAL-CONTENTS-P
      (FILL-ARRAY-FROM-SEQUENCES ARRAY INITIAL-CONTENTS 0 0))
    ;; If there is a fill pointer on an art-q-list array, then it should control
    ;; the length of the list as well.  See array-push and array-pop.
    (WHEN (AND (= N-DIMENSIONS 1)
	       (OR FILL-POINTER (NOT (NULL LEADER-LIST)))
	       ;; The cold load generator's frame builder isn't smart enough for a #, here.
	       (= TYPE #|'#,|# (LDB %%ARRAY-TYPE-FIELD ART-Q-LIST)))
      (OR FILL-POINTER (SETQ FILL-POINTER (CAR LEADER-LIST)))
      (WHEN (AND (FIXNUMP FILL-POINTER)
		 (> FILL-POINTER 0)
		 (< FILL-POINTER (ARRAY-LENGTH ARRAY)))
	(%P-DPB CDR-NIL %%Q-CDR-CODE (AP-1 ARRAY (1- FILL-POINTER)))))
    (VALUES ARRAY DATA-LENGTH)))

(DEFUN ADJUST-ARRAY (ARRAY NEW-DIMENSIONS &REST KEYARGS
		     &KEY ELEMENT-TYPE
		     (INITIAL-ELEMENT NIL INITIAL-ELEMENT-P)
		     (INITIAL-CONTENTS NIL INITIAL-CONTENTS-P)
		     FILL-POINTER DISPLACED-TO DISPLACED-INDEX-OFFSET)
  "Alter dimensions, contents or displacedness of ARRAY.
May modify ARRAY or forward it to a new array.  In either case ARRAY is returned.
The dimensions are altered to be those in the list NEW-DIMENSIONS.
DISPLACED-TO and DISPLACED-INDEX-OFFSET are used to make ARRAY be displaced.
 They mean the same as in MAKE-ARRAY.
INITIAL-CONTENTS is as in MAKE-ARRAY.
 ARRAY's entire contents are initialized from this
 after its shape has been changed.  The old contents become irrelevant.
If neither INITIAL-CONTENTS nor DISPLACED-TO is specified, the old contents
 of ARRAY are preserved.  Each element is preserved according to its subscripts.

INITIAL-ELEMENT, if specified, is used to init any new elements created
 by the reshaping; that is, elements at subscripts which were previously
 out of bounds.  If this is not specified, NIL, 0 or 0.0 is used acc. to array type.
ELEMENT-TYPE if non-NIL causes an error if ARRAY is not of the array type
 which MAKE-ARRAY would create given the same ELEMENT-TYPE.  Just an error check.
FILL-POINTER, if specified, sets the fill pointer of ARRAY."
  DISPLACED-INDEX-OFFSET
  (CHECK-TYPE ARRAY ARRAY)
  (UNLESS (= (LENGTH NEW-DIMENSIONS) (ARRAY-RANK ARRAY))
    (FERROR NIL "~S is the wrong number of dimensions for ~S."
	    NEW-DIMENSIONS ARRAY))
  (WHEN ELEMENT-TYPE
    (LET ((ARRAY-TYPE (ARRAY-TYPE-FROM-ELEMENT-TYPE ELEMENT-TYPE)))
      (DO () ((EQ (CAR (RASSQ ARRAY-TYPE ARRAY-ELEMENT-TYPE-ALIST))
		  (CAR (RASSQ (ARRAY-TYPE ARRAY) ARRAY-ELEMENT-TYPE-ALIST))))
	(SETQ ARRAY (CERROR :NEW-ARGUMENT NIL 'WRONG-TYPE-ARGUMENT
			    "The argument ~2@*~S was ~1@*~S, which is not an ~3@*~A array."
			    `(ARRAY ,(OR (CAR (RASSQ ARRAY-TYPE ARRAY-ELEMENT-TYPE-ALIST)) T))
			    ARRAY 'ARRAY ARRAY-TYPE)))))
  (IF DISPLACED-TO
      (IF (AND (ARRAY-DISPLACED-P ARRAY)
	       (EQ (NULL DISPLACED-INDEX-OFFSET)
		   (NULL (ARRAY-INDEX-OFFSET ARRAY))))
	  (CHANGE-INDIRECT-ARRAY ARRAY (ARRAY-TYPE ARRAY) NEW-DIMENSIONS
				 DISPLACED-TO DISPLACED-INDEX-OFFSET)
	(STRUCTURE-FORWARD ARRAY
			   (APPLY #'MAKE-ARRAY NEW-DIMENSIONS
					       :LEADER-LIST (LIST-ARRAY-LEADER ARRAY)
					       :TYPE (ARRAY-TYPE ARRAY)
					       KEYARGS)))
    (IF (= (ARRAY-RANK ARRAY) 1)
	(LET ((OLD-LEN (ARRAY-LENGTH ARRAY)))
	  (SETQ ARRAY (ADJUST-ARRAY-SIZE ARRAY (CAR NEW-DIMENSIONS)))
	  (WHEN INITIAL-ELEMENT-P
	    (ARRAY-INITIALIZE ARRAY INITIAL-ELEMENT OLD-LEN (CAR NEW-DIMENSIONS))))
      (ARRAY-GROW-1 ARRAY NEW-DIMENSIONS INITIAL-ELEMENT-P INITIAL-ELEMENT)))
  (IF INITIAL-CONTENTS-P
      (FILL-ARRAY-FROM-SEQUENCES ARRAY INITIAL-CONTENTS 0 0))
  (IF FILL-POINTER
      (SETF (FILL-POINTER ARRAY)
	    (IF (EQ FILL-POINTER T) (LENGTH ARRAY) FILL-POINTER)))
  ARRAY)

(DEFUN ARRAY-GROW-1 (ARRAY DIMENSIONS INITIAL-ELEMENT-P INITIAL-ELEMENT
		     &AUX (OLD-DIMS (ARRAY-DIMENSIONS ARRAY))
		     INDEX NEW-ARRAY)
    (PROG ()
	  ;; Make the new array.
	  (IF INITIAL-ELEMENT-P
	      (SETQ NEW-ARRAY (MAKE-ARRAY DIMENSIONS
					  :AREA (%AREA-NUMBER ARRAY)
					  :TYPE (ARRAY-TYPE ARRAY)
					  :INITIAL-ELEMENT INITIAL-ELEMENT
					  :LEADER-LENGTH (ARRAY-LEADER-LENGTH ARRAY)))
	    (SETQ NEW-ARRAY (MAKE-ARRAY DIMENSIONS
					:AREA (%AREA-NUMBER ARRAY)
					:TYPE (ARRAY-TYPE ARRAY)
					:LEADER-LENGTH (ARRAY-LEADER-LENGTH ARRAY))))
	  ;; Copy the array leader.
	  (DO ((I 0 (1+ I))
	       (N (OR (ARRAY-LEADER-LENGTH ARRAY) 0) (1- N)))
	      ((ZEROP N))
	    (SETF (ARRAY-LEADER NEW-ARRAY I) (ARRAY-LEADER ARRAY I)))
	  ;; Check for zero-size array, which the code below doesn't handle correctly
	  (DO ((L DIMENSIONS (CDR L)) (L1 OLD-DIMS (CDR L1)))
	      ((NULL L) NIL)
	    (WHEN (OR (ZEROP (CAR L)) (ZEROP (CAR L1)))
	      (GO DONE)))
	  ;; Create a vector of fixnums to use as subscripts to step through the arrays.
	  (SETQ INDEX (MAKE-LIST (LENGTH DIMENSIONS) :INITIAL-ELEMENT 0))
	  ;; Make the first increment of INDEX bring us to element 0 0 0 0..
	  (SETF (CAR INDEX) -1)
       LOOP
	  ;; Increment the vector of subscripts INDEX.
	  ;; Go to DONE if we have exhausted all elements that need copying.
	  (DO ((I INDEX (CDR I))
	       (O OLD-DIMS (CDR O))
	       (N DIMENSIONS (CDR N)))
	      ((NULL I) (GO DONE))
	    ;; Increment one index
	    (INCF (CAR I))
	    ;; and decide whether to "carry" to the next one.
	    (IF (OR ( (CAR I) (CAR O)) ( (CAR I) (CAR N)))
		(SETF (CAR I) 0)
	      (RETURN NIL)))
	  (APPLY #'ASET (APPLY #'AREF ARRAY INDEX) NEW-ARRAY INDEX)
	  (GO LOOP)
       DONE
	  ;; The contents have been copied.  Copy a few random things.
	  (%P-DPB (%P-LDB %%ARRAY-NAMED-STRUCTURE-FLAG ARRAY)
		  %%ARRAY-NAMED-STRUCTURE-FLAG NEW-ARRAY)
	  (%P-DPB (%P-LDB %%ARRAY-FLAG-BIT ARRAY)
		  %%ARRAY-FLAG-BIT NEW-ARRAY)
	  (STRUCTURE-FORWARD ARRAY NEW-ARRAY)
	  (RETURN NEW-ARRAY)))

(DEFUN VECTOR (&REST OBJECTS)
  "Return a vector (1-dimensional array) whose elements are the OBJECTS."
  (LET ((RESULT (MAKE-ARRAY (LENGTH OBJECTS))))
    (DO ((I 0 (1+ I))
	 (TAIL OBJECTS (CDR TAIL)))
	((NULL TAIL))
      (SETF (AREF RESULT I) (CAR TAIL)))
    RESULT))

(DEFUN MAKE-LIST (LENGTH &REST OPTIONS)
  "Create a list LENGTH long.  :AREA keyword says where, :INITIAL-ELEMENT sets each element."
  (DECLARE (ARGLIST LENGTH &KEY AREA INITIAL-ELEMENT))
  (LET ((LENGTH-OF-OPTIONS (LENGTH OPTIONS))
	(AREA NIL) (INITIAL-ELEMENT NIL))
    ;; Figure out whether it is old-style.
    (IF (= LENGTH-OF-OPTIONS 1)
	;; It is old-style.
	(SETQ AREA LENGTH
	      LENGTH (FIRST OPTIONS))
      ;; It is new-style.
      (IF (ODDP LENGTH-OF-OPTIONS)
	  (FERROR NIL "Odd-length options list: ~S" OPTIONS))
      (DO ((OPTIONS OPTIONS (CDDR OPTIONS)))
	  ((NULL OPTIONS))
	(LET ((VALUE (SECOND OPTIONS)))
	  (CASE (FIRST OPTIONS)
	    (:AREA (SETQ AREA VALUE))
	    ((:INITIAL-ELEMENT :INITIAL-VALUE)
	     (SETQ INITIAL-ELEMENT VALUE))
	    (OTHERWISE
	     (FERROR NIL "~S is not a known keyword." (FIRST OPTIONS)))))))
    (%MAKE-LIST INITIAL-ELEMENT AREA LENGTH)))

;;; This is an internal function designed to be called by code generated
;;; be a compiler optimizer of simple calls to MAKE-ARRAY.
(DEFUN SIMPLE-MAKE-ARRAY (DIMENSIONS &OPTIONAL (TYPE ART-Q) AREA LEADER-LENGTH
			  (INITIAL-ELEMENT NIL INITIAL-ELEMENT-P)
			  &AUX DATA-LENGTH LONG-ARRAY-P ARRAY)
  (COND ((OR (NULL DIMENSIONS) (CDR-SAFE DIMENSIONS))	;nil or a list of length > 1
	 (IF INITIAL-ELEMENT-P
	     (DONT-OPTIMIZE	       
	       (MAKE-ARRAY DIMENSIONS :TYPE TYPE :AREA AREA
			   :LEADER-LENGTH LEADER-LENGTH
			   :INITIAL-ELEMENT INITIAL-ELEMENT))
	   (DONT-OPTIMIZE
	     (MAKE-ARRAY DIMENSIONS :TYPE TYPE :AREA AREA
			 :LEADER-LENGTH LEADER-LENGTH))))
	(T
	 (IF (CONSP DIMENSIONS) (SETQ DIMENSIONS (CAR DIMENSIONS)))
	 (CHECK-TYPE DIMENSIONS FIXNUM "an integer or a list")
	 (IF (MINUSP DIMENSIONS)
	     (FERROR NIL "The negative array length ~S is illegal." DIMENSIONS))
	 (IF (> DIMENSIONS %ARRAY-MAX-SHORT-INDEX-LENGTH)
	     (SETQ LONG-ARRAY-P T))
	 (IF (NOT (NULL LEADER-LENGTH))
	     (CHECK-TYPE LEADER-LENGTH (INTEGER (0))))
	 (COND ((FIXNUMP TYPE)
		(IF (NOT (ZEROP (LDB %%ARRAY-TYPE-FIELD TYPE)))
		    (SETQ TYPE (LDB %%ARRAY-TYPE-FIELD TYPE))))
	       ((SYMBOLP TYPE)
		(ETYPECASE (SYMBOL-VALUE TYPE)
		  (FIXNUM
		   (SETQ TYPE (LDB %%ARRAY-TYPE-FIELD (SYMBOL-VALUE TYPE))))
		  (SYMBOL
		   (SETQ TYPE (FIND-POSITION-IN-LIST TYPE ARRAY-TYPE-KEYWORDS)))))
	       (T
		(CHECK-ARG TYPE (OR (FIXNUMP TYPE) (MEMQ TYPE ARRAY-TYPES)) "an array type")
		(IF (FIXNUMP TYPE)
		    (IF (NOT (ZEROP (LDB %%ARRAY-TYPE-FIELD TYPE)))
			(SETQ TYPE (LDB %%ARRAY-TYPE-FIELD TYPE)))
		  (SETQ TYPE (LDB %%ARRAY-TYPE-FIELD (SYMBOL-VALUE TYPE))))))
	 (LET ((ENTRIES-PER-Q (ARRAY-ELEMENTS-PER-Q TYPE)))
	   ;; This is positive if there are 1 or more entries per Q.  It is
	   ;; negative if there are more than one Qs per entry.
	   (SETQ DATA-LENGTH (IF (PLUSP ENTRIES-PER-Q)
				 (CEILING DIMENSIONS ENTRIES-PER-Q)
			       (* DIMENSIONS (MINUS ENTRIES-PER-Q))))
	   (LET ((HEADER-WORD
		   ;; Put in array type and number of dims.
		   (%LOGDPB 1 %%ARRAY-NUMBER-DIMENSIONS
			    (%LOGDPB TYPE %%ARRAY-TYPE-FIELD 0))))
	     ;; If there is a leader, set the flag.
	     (IF LEADER-LENGTH
		 (SETQ HEADER-WORD (%LOGDPB 1 %%ARRAY-LEADER-BIT HEADER-WORD)))
	     (SETQ HEADER-WORD
		   (COND (LONG-ARRAY-P
			  ;; It is local; if it is a long array, the length is not in the
			  ;; header at all; set the bit instead.
			  (%LOGDPB 1 %%ARRAY-LONG-LENGTH-FLAG HEADER-WORD))
			 (T
			  ;; It is a short array; the length is in the header.
			  (+ DIMENSIONS HEADER-WORD))))
	     ;; Create the array.
	     (SETQ ARRAY (%ALLOCATE-AND-INITIALIZE-ARRAY HEADER-WORD
							 DIMENSIONS
							 (OR LEADER-LENGTH 0)
							 AREA
							 (+ 1	;header
							    (IF LEADER-LENGTH
								(+ 2 LEADER-LENGTH)
							        0)
							    (IF LONG-ARRAY-P
								(1+ DATA-LENGTH)
							        DATA-LENGTH)))))
	   (IF INITIAL-ELEMENT-P (ARRAY-INITIALIZE ARRAY INITIAL-ELEMENT)))
	 (VALUES ARRAY DATA-LENGTH))))

(DEFUN FILL-ARRAY (ARRAY SIZE VALUE) (ARRAY-INITIALIZE ARRAY VALUE 0 SIZE))

(DEFUN ARRAY-INITIALIZE (ORIGINAL-ARRAY VALUE &OPTIONAL (START 0) END
			 &AUX (ARRAY ORIGINAL-ARRAY) (UNFORWARDED-ARRAY ORIGINAL-ARRAY)
			 (OFFSET 0))
  "Set all the elements of ARRAY to VALUE, or all elements from START to END.
If END is NIL or not specified, the active length of ARRAY is used."
  (UNLESS END
    (SETQ END (ARRAY-ACTIVE-LENGTH ARRAY)))
  (UNLESS ( 0 START END (ARRAY-LENGTH ARRAY))
    (FERROR NIL "START is ~S and END is ~S, for ~S." START END ARRAY))
  (IF (< END (+ START 30.))
      ;; If number of elements to be hacked is small, just do them.
      (DO ((I START (1+ I))) (( I END))
	(SETF (AR-1-FORCE ARRAY I) VALUE))
    ;; Handle indirect arrays by finding the array indirected to
    ;; and updating the start and end indices if appropriate.
    (DO () ((NOT (ARRAY-INDIRECT-P ARRAY)))
      (AND (ARRAY-INDEX-OFFSET ARRAY)
	   (INCF OFFSET (ARRAY-INDEX-OFFSET ARRAY)))
      (SETQ ARRAY (ARRAY-INDIRECT-TO ARRAY)))
    ;; Handle forwarded arrays.
    (UNLESS (= (%P-DATA-TYPE ARRAY) DTP-ARRAY-HEADER)
      (SETQ ARRAY (FOLLOW-STRUCTURE-FORWARDING ARRAY)))
    (UNLESS (= (%P-DATA-TYPE UNFORWARDED-ARRAY) DTP-ARRAY-HEADER)
      (SETQ UNFORWARDED-ARRAY (FOLLOW-STRUCTURE-FORWARDING UNFORWARDED-ARRAY)))
    (LET* ((ENTRIES-PER-Q (ARRAY-ELEMENTS-PER-Q (%P-LDB %%ARRAY-TYPE-FIELD UNFORWARDED-ARRAY)))
	   (BITS-PER-ELEMENT (ARRAY-BITS-PER-ELEMENT (%P-LDB %%ARRAY-TYPE-FIELD UNFORWARDED-ARRAY)))
	   (START (+ START OFFSET))
	   (END (+ END OFFSET))
	   (DATA-OFFSET (ARRAY-DATA-OFFSET ARRAY))
	   ;; Compute how many words are in the repeating unit that we replicate with %BLT.
	   ;; This is 1 word unless an element is bigger than that.
	   (BLT-DISTANCE (IF (PLUSP ENTRIES-PER-Q) 1 (- ENTRIES-PER-Q)))
	   ;; This is how many elements it takes to make BLT-DISTANCE words.
	   (Q-BOUNDARY-ELTS (MAX 1 ENTRIES-PER-Q))
	   ;; We must deposit element by element until this element
	   ;; in order to make sure we have a full word of elements stored
	   ;; Beyond this, we can blt entire words.
	   (STOP-ELEMENT-BY-ELEMENT
	     (MIN END
		  (* Q-BOUNDARY-ELTS
		     (1+ (CEILING START Q-BOUNDARY-ELTS)))))
	   ;; We must stop our word-wise copying before this element number
	   ;; to avoid clobbering any following elements which are beyond END.
	   (END-WORD-WISE
	     (MAX START (* Q-BOUNDARY-ELTS (FLOOR END Q-BOUNDARY-ELTS))))
	   ;; Compute index in words, wrt array data, of the first data word
	   ;; that we will not fill up an element at a time.
	   (UNINITIALIZED-DATA-OFFSET
	     (+ DATA-OFFSET
		(* BLT-DISTANCE (CEILING STOP-ELEMENT-BY-ELEMENT Q-BOUNDARY-ELTS))))
	   ;; Compute the length of the data in the array, in Qs, if caller didn't supply it.
	   (DATA-LENGTH
	     (IF (PLUSP ENTRIES-PER-Q)
		 (TRUNCATE END-WORD-WISE ENTRIES-PER-Q)
	       (* END-WORD-WISE (- ENTRIES-PER-Q)))))
      ;; Fill in any elements in an incomplete first word,
      ;; plus one full word's worth.
      ;; We must use the original array to store element by element,
      ;; since the element size of the array indirected to may be different.
      (DO ((I START (1+ I)))
	  ((= I STOP-ELEMENT-BY-ELEMENT))
	(SETF (AR-1-FORCE ORIGINAL-ARRAY (- I OFFSET)) VALUE))
      ;; Now fill in the elements in the incomplete last word.
      (DO ((I END-WORD-WISE (1+ I)))
	  (( I END))
	(SETF (AR-1-FORCE ORIGINAL-ARRAY (- I OFFSET)) VALUE))
      ;; Now copy the data word by word (or by two words for ART-FLOAT!)
      ;; There is no hope of passing %BLT pointers that are GC-safe.
      (IF (PLUSP (- DATA-LENGTH (- UNINITIALIZED-DATA-OFFSET DATA-OFFSET)))
	  (WITHOUT-INTERRUPTS
	    ;; If the array is displaced to a random location, use that location
	    ;; as the data start.  Arrays displaced to other arrays
	    ;; were handled above.
	    (IF (ARRAY-DISPLACED-P ARRAY)
		(SETQ ARRAY (- (%POINTER (ARRAY-INDIRECT-TO ARRAY)) DATA-OFFSET)))
	    (IF BITS-PER-ELEMENT
		;; Numeric array.
		(%BLT (%MAKE-POINTER-OFFSET DTP-FIX ARRAY
					    (- UNINITIALIZED-DATA-OFFSET BLT-DISTANCE))
		      (%MAKE-POINTER-OFFSET DTP-FIX ARRAY UNINITIALIZED-DATA-OFFSET)
		      (- DATA-LENGTH (- UNINITIALIZED-DATA-OFFSET DATA-OFFSET))
		      1)
	      (%BLT-TYPED (%MAKE-POINTER-OFFSET DTP-FIX ARRAY
						(- UNINITIALIZED-DATA-OFFSET BLT-DISTANCE))
			  (%MAKE-POINTER-OFFSET DTP-FIX ARRAY UNINITIALIZED-DATA-OFFSET)
			  (- DATA-LENGTH (- UNINITIALIZED-DATA-OFFSET DATA-OFFSET))
			  1))))))
  ORIGINAL-ARRAY)

(DEFUN ARRAY-DATA-OFFSET (ARRAY)
  "Return the offset in Qs of the first array element from the array header.
Not meaningful for displaced arrays."
  (+ (ARRAY-RANK ARRAY) (%P-LDB %%ARRAY-LONG-LENGTH-FLAG ARRAY)))


(DEFUN MAKE-SYMBOL (PNAME &OPTIONAL PERMANENT-P)
  "Create a symbol with name PNAME.
The symbol starts out with no value, definition or properties.
PERMANENT-P forces areas to those normally used for symbols."
  (CHECK-TYPE PNAME STRING)
  (AND PERMANENT-P (NOT (= (%AREA-NUMBER PNAME) P-N-STRING))
       (LET ((%INHIBIT-READ-ONLY T)
	     (DEFAULT-CONS-AREA P-N-STRING))
	 (SETQ PNAME (STRING-APPEND PNAME))))
  (LET ((SYMB (%ALLOCATE-AND-INITIALIZE DTP-SYMBOL	;Type to return.
			     DTP-SYMBOL-HEADER		;Type of header.
			     PNAME			;Pointer field of header.
			     NIL			;Value for second word.
			     (AND PERMANENT-P NR-SYM)	;Area.
			     LENGTH-OF-ATOM-HEAD)))	;Length.
    (MAKUNBOUND SYMB)				;Was initialized to NIL
    (FMAKUNBOUND SYMB)
    SYMB))

;;;; Runtime support for compiled functions that use &key.

;;; Required keyword args are initialized to this value.
;;; We compare the values against it to see which ones are missing.
;;; This number is used only at the beginning of cold-load time,
;;; because the value is set up by the cold-load builder
;;; and is available from the very beginning.
(DEFPARAMETER KEYWORD-GARBAGE #o643643)

(ADD-INITIALIZATION "Keyword-garbage" '(SETQ KEYWORD-GARBAGE (LIST NIL)) '(ONCE))

(DEFPROP STORE-KEYWORD-ARG-VALUES T :ERROR-REPORTER)

;;; Given ARGS, the list of key names and values;
;;; KEYKEYS, the list of keywords we understand, in their order;
;;; and FRAME-POINTER, a locative pointing at our caller's frame;
;;; decode the ARGS and stick the values into the right slots in the frame.
;;; SPECVAR-LIST is a list of NIL for nonspecial keyword args
;;; and symbols for special ones.
;;; It runs in parallel with KEYKEYS.
;;; If there are duplicate keywords in the supplied args, all but the first are ignored.

;;; New calling sequence:
;;;  FIRST-KEYARG-POINTER points to the local slot for the first keyword arg.
;;; Old calling sequence: FRAME-POINTER is a pointer to the calling stack frame.
;;;  This calling sequence assumes that the first keyword arg is in local slot 1,
;;;  which can fail to be true for certain unusual constructs.
;;; If FIRST-KEYARG-POINTER is a locative, the new calling sequence is in use.
;;; FRAME-POINTER is ignored in that case.
;;; Newly compiled calls do not pass SPECVAR-LIST; they handle special variables another way.
(DEFUN STORE-KEYWORD-ARG-VALUES (FRAME-POINTER ARGS KEYKEYS ALLOW-OTHER-KEYS
					       &OPTIONAL FIRST-KEYARG-POINTER
					       SPECVAR-LIST)
  (LET ((FIRST-KEYWORD-ARG-INDEX
	  (IF (LOCATIVEP FIRST-KEYARG-POINTER)
	      (PROGN (SETQ FRAME-POINTER FIRST-KEYARG-POINTER) -1)
	    (%P-LDB-OFFSET %%LP-ENS-MACRO-LOCAL-BLOCK-ORIGIN
			   FRAME-POINTER
			   %LP-ENTRY-STATE))))
    (IF (GETF ARGS :ALLOW-OTHER-KEYS)
	(SETQ ALLOW-OTHER-KEYS T))
    ;; First decode what was specified.
    (DO ((ARGS-LEFT ARGS (CDDR ARGS-LEFT))
	 (FOUND-FLAGS 0))
	((NULL ARGS-LEFT))
      (LET ((KEYWORD (CAR ARGS-LEFT)))
	(DO-FOREVER
	  (LET ((INDEX (FIND-POSITION-IN-LIST KEYWORD KEYKEYS)))
	    (COND (INDEX
		   (WHEN (ZEROP (LOGAND 1 (ASH FOUND-FLAGS (- INDEX))))
		     (SETQ FOUND-FLAGS
			   (DPB 1 (BYTE 1 INDEX) FOUND-FLAGS))
		     (LET ((SPECVAR (NTH INDEX SPECVAR-LIST)))
		       (IF SPECVAR
			   (SET SPECVAR (CADR ARGS-LEFT)))
		       (%P-STORE-CONTENTS-OFFSET (CADR ARGS-LEFT) FRAME-POINTER
						 (+ 1 INDEX FIRST-KEYWORD-ARG-INDEX))))
		   (RETURN))
		  (ALLOW-OTHER-KEYS (RETURN))
		  ((EQ KEYWORD :ALLOW-OTHER-KEYS) (RETURN))
		  (T
		   (SETQ KEYWORD (CERROR :NEW-KEYWORD NIL 'SYS:UNDEFINED-KEYWORD-ARGUMENT
					 "Keyword arg keyword ~S unrecognized."
					 KEYWORD (CADR ARGS-LEFT)))
		   (OR KEYWORD (RETURN))))))))))

;;; Given ARGS, the list of key names and values;
;;; KEYKEYS, the list of keywords we understand, in their order;
;;; and PREV-SLOT-POINTER, a locative pointing at the local slot
;;; just before the first of those for our keyword args;
;;; decode the ARGS and stick the values into the right slots in the frame.
;;; SPECVAR-LIST is a list of NIL for nonspecial keyword args
;;; and symbols for special ones.
;;; It runs in parallel with KEYKEYS.
;;; If there are duplicate keywords in the supplied args, all but the first are ignored.
(DEFUN STORE-KEYWORD-ARG-VALUES-INTERNAL-LAMBDA
       (PREV-SLOT-POINTER ARGS KEYKEYS ALLOW-OTHER-KEYS SPECVAR-LIST)
  (IF (GETF ARGS :ALLOW-OTHER-KEYS)
      (SETQ ALLOW-OTHER-KEYS T))
  ;; First decode what was specified.
  (DO ((ARGS-LEFT ARGS (CDDR ARGS-LEFT))
       (FOUND-FLAGS 0))
      ((NULL ARGS-LEFT))
    (LET ((KEYWORD (CAR ARGS-LEFT)))
      (DO-FOREVER
	(LET ((INDEX (FIND-POSITION-IN-LIST KEYWORD KEYKEYS)))
	  (COND (INDEX
		 (WHEN (ZEROP (LOGAND 1 (ASH FOUND-FLAGS (- INDEX))))
		   (SETQ FOUND-FLAGS
			 (DPB 1 (BYTE 1 INDEX) FOUND-FLAGS))
		   (LET ((SPECVAR (NTH INDEX SPECVAR-LIST)))
		     (IF SPECVAR
			 (SET SPECVAR (CADR ARGS-LEFT))
		       ;; This var is not special.
		       ;; Decrement INDEX by the number of preceding vars that are special,
		       ;; because they don't have local slots.
		       (DO ((I INDEX (1- I))
			    (TAIL SPECVAR-LIST (CDR TAIL)))
			   ((ZEROP I))
			 (WHEN (CAR TAIL)
			   (DECF INDEX)))
		       (%P-STORE-CONTENTS-OFFSET (CADR ARGS-LEFT) PREV-SLOT-POINTER
						 (+ 1 INDEX)))))
		 (RETURN))
		(ALLOW-OTHER-KEYS (RETURN))
		((EQ KEYWORD :ALLOW-OTHER-KEYS) (RETURN))
		(T
		 (SETQ KEYWORD (CERROR :NEW-KEYWORD NIL 'SYS:UNDEFINED-KEYWORD-ARGUMENT
				       "Keyword arg keyword ~S unrecognized."
				       KEYWORD (CADR ARGS-LEFT)))
		 (OR KEYWORD (RETURN)))))))))

;;Now Microcoded
;(DEFUN NTH (N OBJECT)
;   (CHECK-ARG N (AND (FIXNUMP N) (NOT (MINUSP N))) "a non-negative integer") 
;   (DO ((N N (1- N))
;	(OBJECT OBJECT (CDR OBJECT)))
;       ((ZEROP N) (CAR OBJECT))))

;;Now microcoded
;(DEFUN ARRAY-LEADER-LENGTH (ARRAY)
;  "Return the number of elements in ARRAY's leader, or NIL if no leader."
;  (COND ((ARRAY-HAS-LEADER-P ARRAY)
;	 (%P-LDB-OFFSET %%ARRAY-LEADER-LENGTH ARRAY -1)))))

;;Now microcoded
;(DEFUN ARRAY-DIMENSION (ARRAY DIMENSION-NUMBER &AUX RANK INDEX-LENGTH LONG-ARRAY-P)
;  "Return the length of dimension DIMENSION-NUMBER of ARRAY.  The first dimension is number 0."
;  (CHECK-ARG ARRAY ARRAYP "an array")
;  (SETQ LONG-ARRAY-P (%P-LDB-OFFSET %%ARRAY-LONG-LENGTH-FLAG ARRAY 0))
;  (SETQ RANK (%P-LDB-OFFSET %%ARRAY-NUMBER-DIMENSIONS ARRAY 0))
;  (COND ((NOT (< -1 DIMENSION-NUMBER RANK))
;	 NIL)
;	((AND (< DIMENSION-NUMBER (1- RANK)) (NOT ARRAY-INDEX-ORDER))
;	 (%P-LDB-OFFSET %%Q-POINTER ARRAY (+ DIMENSION-NUMBER 1 LONG-ARRAY-P)))
;	((AND (> DIMENSION-NUMBER 0) ARRAY-INDEX-ORDER)
;	 (%P-LDB-OFFSET %%Q-POINTER ARRAY (+ (- RANK DIMENSION-NUMBER) LONG-ARRAY-P)))
;	(T
;	 (SETQ INDEX-LENGTH
;	       (COND ((NOT (ZEROP (%P-LDB-OFFSET %%ARRAY-DISPLACED-BIT ARRAY 0)))
;		      (%P-LDB-OFFSET %%Q-POINTER ARRAY (1+ RANK)))
;		     ((= LONG-ARRAY-P 1) (%P-LDB-OFFSET %%Q-POINTER ARRAY 1))
;		     (T (%P-LDB-OFFSET %%ARRAY-INDEX-LENGTH-IF-SHORT ARRAY 0))))
;	 ;; As far as I can tell, there's no way to determine the last dimension
;	 ;; if the index-length is 0.  Might as well just give it as zero? -- DLA
;	 (OR (ZEROP INDEX-LENGTH)
;	     (DO I 1 (1+ I) ( I RANK)
;		 (SETQ INDEX-LENGTH
;		       (TRUNCATE INDEX-LENGTH 
;				 (%P-LDB-OFFSET %%Q-POINTER ARRAY (+ LONG-ARRAY-P I))))))
;	 INDEX-LENGTH)))

;;Now microcoded
;(DEFUN ARRAY-ROW-MAJOR-INDEX (ARRAY &REST SUBSCRIPTS)
;  "Return the combined index in ARRAY of the element identified by SUBSCRIPTS.
;This value could be used as the second argument of AR-1-FORCE to access that element.
;The calculation assumes row-major order; therefore, this function
;will not really be useful until row-major order is installed!"
;  (CHECK-ARG-TYPE ARRAY ARRAY)
;  (DO ((DIM 0 (1+ DIM))
;       (RANK (ARRAY-RANK ARRAY))
;       (RESULT 0)
;       (TAIL SUBSCRIPTS (CDR TAIL)))
;      ((= DIM RANK)
;       RESULT)
;    (LET ((SUBSCRIPT (CAR TAIL)))
;      (CHECK-ARG SUBSCRIPT (AND (NUMBERP SUBSCRIPT)
;				(< -1 SUBSCRIPT (ARRAY-DIMENSION ARRAY DIM)))
;		 "a number in the proper range")
;      (SETQ RESULT (+ (* RESULT (ARRAY-DIMENSION ARRAY DIM)) SUBSCRIPT)))))

;This is in microcode
;(DEFUN EQUAL (A B)
;  (PROG NIL 
;    L	(COND ((EQ A B) (RETURN T))
;	      ((NOT (= (%DATA-TYPE A) (%DATA-TYPE B))) (RETURN NIL))
;	      ((NUMBERP A) (RETURN (= A B)))
;	      ((ARRAYP A)
;	       (RETURN (AND (STRINGP A)
;			    (STRINGP B)
;			    (%STRING-EQUAL A 0 B 0 NIL))))
;	      ((ATOM A) (RETURN NIL))
;	      ((NOT (EQUAL (CAR A) (CAR B))) (RETURN NIL)))
;	(SETQ A (CDR A))
;	(SETQ B (CDR B))
;	(GO L)))

;;; This is here because the TV package calls it during initialization.
(DEFUN DELQ (ITEM LIST &OPTIONAL (/#TIMES -1))
  "Destructively remove some or all occurrences of ITEM from LIST.
If #TIMES is specified, it is a number saying how many occurrences to remove.
vYou must do (SETQ FOO (DELQ X FOO)) to make sure FOO changes,
in case the first element of FOO is X."
  (PROG (LL PL)
     A  (COND ((OR (= 0 /#TIMES) (ATOM LIST))
	       (RETURN LIST))
	      ((EQ ITEM (CAR LIST))
	       (SETQ LIST (CDR LIST))
	       (SETQ /#TIMES (1- /#TIMES))
	       (GO A)))
	(SETQ LL LIST)
     B  (COND ((OR (= 0 /#TIMES) (ATOM LL))
	       (RETURN LIST))
	      ((EQ ITEM (CAR LL))
	       (RPLACD PL (CDR LL))
	       (SETQ /#TIMES (1- /#TIMES)))
	      ((SETQ PL LL)))
	(SETQ LL (CDR LL))
	(GO B)))

;;; The following are here because MAKE-SYMBOL uses them.  Perhaps some of them should be in
;;;  microcode.

(DEFUN MAKUNBOUND (SYMBOL)
  "Cause SYMBOL to have no value.  It will be an error to evaluate it."
  (AND (MEMQ SYMBOL '(T NIL))			;I guess it's worth checking
       (FERROR NIL "Don't makunbound ~S please" SYMBOL))
  ;; Value cell could be forwarded somewhere, e.g. into microcode memory
  (DO ((LOC (VALUE-CELL-LOCATION SYMBOL) (%P-CONTENTS-AS-LOCATIVE LOC)))
      (( (%P-DATA-TYPE LOC) DTP-ONE-Q-FORWARD)
       (WITHOUT-INTERRUPTS
	 (%P-STORE-POINTER LOC SYMBOL)
	 (%P-STORE-DATA-TYPE LOC DTP-NULL))))
  SYMBOL)

(DEFUN FMAKUNBOUND (SYMBOL)
  "Cause SYMBOL to have no function definition.  It will be an error to call it."
  (WITHOUT-INTERRUPTS
    (%P-STORE-POINTER (FUNCTION-CELL-LOCATION SYMBOL) SYMBOL)
    (%P-STORE-DATA-TYPE (FUNCTION-CELL-LOCATION SYMBOL) DTP-NULL))
  SYMBOL)

(DEFUN LOCATION-MAKUNBOUND (LOCATION &OPTIONAL VARIABLE-NAME)
  "Cause the word LOCATION points to to be unbound.
If LOCATION points to a symbol value cell, the symbol becomes unbound.
VARIABLE-NAME is a value to put in the pointer field of the DTP-NULL
value; it should be the variable or function-spec whose value,
in some sense, LOCATION represents."
  (CHECK-TYPE LOCATION (OR CONS LOCATIVE) "a location (something to take CONTENTS of)")
  (TYPECASE LOCATION
    (CONS (LOCATION-MAKUNBOUND (CDR-LOCATION-FORCE LOCATION)))
    (T
      ;; Cell could be forwarded somewhere, e.g. into microcode memory
      (DO ((LOC LOCATION (%P-CONTENTS-AS-LOCATIVE LOC)))
	  (( (%P-DATA-TYPE LOC) DTP-ONE-Q-FORWARD)
	   (WITHOUT-INTERRUPTS
	     (%P-STORE-DATA-TYPE LOC DTP-NULL)
	     (%P-STORE-POINTER LOC (OR VARIABLE-NAME LOCATION))))))))

(DEFUN LOCATION-BOUNDP (LOCATION)
  "T if the contents of LOCATION is not /"unbound/"."
  (CHECK-TYPE LOCATION (OR CONS LOCATIVE) "a location (something to take CONTENTS of)")
  (TYPECASE LOCATION
    (CONS
      ;; If the list has an explicit cdr-pointer, check its data type.
      ;; Otherwise the answer is always T.
      (SELECTOR (%P-CDR-CODE LOCATION) =
	(#.CDR-NORMAL ( DTP-NULL (%P-LDB-OFFSET %%Q-DATA-TYPE
						 (IF (= (%P-DATA-TYPE LOCATION)
							DTP-HEADER-FORWARD)
						     (FOLLOW-STRUCTURE-FORWARDING LOCATION)
						   LOCATION)
						 1)))
	(#.CDR-ERROR (FERROR NIL "Invalid CDR code in list at #o~O." (%POINTER LOCATION)))
	(T T)))
    (T
      ;; Cell could be forwarded somewhere, e.g. into microcode memory
      (DO ((LOC LOCATION (%P-CONTENTS-AS-LOCATIVE LOC)))
	  (( (%P-DATA-TYPE LOC) DTP-ONE-Q-FORWARD)
	   ( DTP-NULL (%P-DATA-TYPE LOC)))))))

(DEFUN CDR-LOCATION-FORCE (LIST)
  "Return a locative pointing at the place where the cdr pointer of a list cell is stored.
This causes the list to be forwarded if it did not have an explicit cdr pointer."
  (SELECTOR (%P-CDR-CODE LIST) =
    (#.CDR-NORMAL
     (%MAKE-POINTER-OFFSET DTP-LOCATIVE
			   (IF (= (%P-DATA-TYPE LIST) DTP-HEADER-FORWARD)
			       (FOLLOW-STRUCTURE-FORWARDING LIST)
			     LIST)
			   1))
    (#.CDR-ERROR (FERROR NIL "Invalid CDR code in list at #o~O." (%POINTER LIST)))
    (T (WITHOUT-INTERRUPTS			;cdr-nil, cdr-next
	 (RPLACD LIST (CDR LIST)))
       (%MAKE-POINTER-OFFSET DTP-LOCATIVE (FOLLOW-STRUCTURE-FORWARDING LIST) 1))))

(DEFUN STORE-CONDITIONAL (LOCATION OLD NEW)
  "If the cdr of LOCATION matches OLD, store NEW there instead."
  (CHECK-TYPE LOCATION (OR CONS LOCATIVE) "a location (something to take CONTENTS of)")
  (WHEN (CONSP LOCATION) (SETQ LOCATION (CDR-LOCATION-FORCE LOCATION)))
  (%STORE-CONDITIONAL LOCATION OLD NEW))

(DEFUN SETPLIST (SYMBOL L)
  "Set the property list of SYMBOL to be L (a list of alternating properties and values).
SYMBOL may be an instance that handles the :SETPLIST operation, instead of a symbol."
  (ETYPECASE SYMBOL
    (SYMBOL 
     (RPLACA (PROPERTY-CELL-LOCATION SYMBOL)
	     L))
    ((OR INSTANCE NAMED-STRUCTURE)
     (SEND SYMBOL :SETPLIST L)))
  L)

(DEFUN FSET (SYMBOL DEFINITION)
  "Set the function definition of SYMBOL to DEFINITION.
This works only on symbols, and does not make warnings, record source files, etc.
To do those things, use FDEFINE."
  (CHECK-TYPE SYMBOL SYMBOL)
  (RPLACA (FUNCTION-CELL-LOCATION SYMBOL) DEFINITION)
  DEFINITION)

(COMPILER:MAKE-OBSOLETE NAMED-STRUCTURE-SYMBOL "use NAMED-STRUCTURE-P")
;;;Now microcoded.
;(DEFUN NAMED-STRUCTURE-SYMBOL (NAMED-STRUCTURE)
;  "Given an array which is a named structure, return its named structure type."
;  (LET ((SYM (IF (ARRAY-HAS-LEADER-P NAMED-STRUCTURE)
;		 (ARRAY-LEADER NAMED-STRUCTURE 1)
;	       (AREF NAMED-STRUCTURE 0))))
;    (IF (SYMBOLP SYM) SYM
;      (AND (CLOSUREP SYM)
;	   (SETQ SYM (CAR (%MAKE-POINTER DTP-LIST SYM))))
;      (OR (SYMBOLP SYM)
;	  (FERROR NIL "~S not a symbol in named-structure-symbol slot of ~S"
;		  SYM NAMED-STRUCTURE))
;      SYM)))

;;Now Microcoded
;(DEFUN NAMED-STRUCTURE-P (STRUCTURE)
;   "If argument is a named-structure, return its name, otherwise NIL"
;   (AND (ARRAYP STRUCTURE)
;	(NOT (ZEROP (%P-LDB-OFFSET %%ARRAY-NAMED-STRUCTURE-FLAG STRUCTURE 0)))
;	(CONDITION-CASE ()
;	    (NAMED-STRUCTURE-SYMBOL STRUCTURE)
;	  (ERROR NIL)))


;;; This function exists mostly for easing the phaseover to the new OBJECT scheme
;;;  (which flushes the SELF argument to the named-structure handler, and uses instead
;;;  a free reference to the variable SELF).
(DEFUN NAMED-STRUCTURE-INVOKE (OPERATION STRUCTURE &REST ARGS)
  ;; This function used to take its first two arguments in the other order.
  ;; We are comitted to supporting the old argument order indefinitely.
  (IF (ARRAYP OPERATION)
      (PSETQ OPERATION STRUCTURE STRUCTURE OPERATION))
  (CHECK-TYPE OPERATION SYMBOL)
  (CHECK-TYPE STRUCTURE ARRAY)
  (LET* ((SELF STRUCTURE)
	 (C (NAMED-STRUCTURE-P SELF)))
    (IF (SYMBOLP C)
	(SETQ C (OR (GET C 'NAMED-STRUCTURE-INVOKE)
		    (GET C ':NAMED-STRUCTURE-INVOKE))))
    (COND ((NULL C) NIL)
	  ((TYPEP C 'CLOSURE)				;If a closure, assume knows about SELF
	   (APPLY C OPERATION ARGS))
	  (T (APPLY C OPERATION SELF ARGS)))))		;flush the SELF arg
							;when the phaseover is made (if ever).

;;; Called by ucode through support vector when a named structure is funcalled.
;;; ARGS are operation and the associated args.
;;; The structure was pushed on the pdl after the last arg - ugh.
(DEFUN CALL-NAMED-STRUCTURE (&REST ARGS)
  (LET ((TEM (LAST ARGS)))
    (APPLY #'NAMED-STRUCTURE-INVOKE (CAR ARGS) (%P-CONTENTS-OFFSET TEM 1) (CDR ARGS))))


;;;; Basic Time Stuff

;;; A number which increments approximately 60 times a second, and wraps
;;; around now and then (about once a day); it's only 23 bits long.
;;; 60-cycle clock not hooked up yet, simulate with microsecond clock.

;;; Remembers high-order bits and detects carries
;;; Maintenance of this depends on TIME being called periodically by the scheduler
(DEFVAR TIME-LAST-VALUE 0)

(DEFUN TIME (&OPTIONAL FORM)
  "Time in 60'ths of a second.  Only differences between values are significant.
Time values wrap around about once a day, so use TIME-LESSP, TIME-INCREMENT
and TIME-DIFFERENCE to compare and compute times.

If FORM is specified, we evaluate it, return the values it returns,
while printing to *TRACE-OUTPUT* a message saying how long it took.
Blame Common Lisp for wanting this unrelated alternate meaning."
  (IF FORM
      (LET ((XTIME (TIME:MICROSECOND-TIME))
	    (OTIME (TIME:MICROSECOND-TIME))
	    (VALUES (MULTIPLE-VALUE-LIST (EVAL FORM)))
	    (NTIME (TIME:MICROSECOND-TIME)))
	(FORMAT *TRACE-OUTPUT*
		"~&Evaluation of ~S took ~:D microseconds."
		FORM (- (+ NTIME XTIME) OTIME OTIME))
	(VALUES-LIST VALUES))
    (SELECT-PROCESSOR
      (:CADR
       (WITHOUT-INTERRUPTS
	 (LET ((LOW (%UNIBUS-READ #o764120))	;Hardware synchronizes if you read this first
	       (HIGH (%UNIBUS-READ #o764122))
	       (SOFT (LDB 2205 TIME-LAST-VALUE)))
	   (LET ((LOWTIME (DPB HIGH #o0220 (LDB #o1602 LOW))))	;Low 18 bits
	     (SETQ TIME-LAST-VALUE
		   (DPB (IF (< LOWTIME (LDB #o0022 TIME-LAST-VALUE))
			    (1+ SOFT)
			  SOFT)
			#o2205 LOWTIME))))))
      (:LAMBDA
       (WITHOUT-INTERRUPTS
	 (LET ((LOWTIME (LDB #o1622 (COMPILER:%MICROSECOND-TIME)))
	       (SOFT (LDB #o2205 TIME-LAST-VALUE)))
	   (SETQ TIME-LAST-VALUE
		 (DPB (IF (< LOWTIME (LDB #o0022 TIME-LAST-VALUE))
			  (1+ SOFT)
			SOFT)
		      #o2205 LOWTIME))))))))


;;; These two functions deal with the wrap-around lossage
(DEFUN TIME-LESSP (TIME1 TIME2)
  "Compare two values of (TIME); return T if the first is less.
If two times too far apart are compared, you get the wrong answer,
since (TIME) wraps around.  Do not use (TIME) for applications where that can matter."
  (BIT-TEST #o20000000 (%POINTER-DIFFERENCE TIME1 TIME2)))

(DEFUN TIME-DIFFERENCE (TIME1 TIME2)
  "Subtract one value of (TIME) from another, or subtract an interval from a time.
Both the interval and the time are measured in 60'ths of a second.
This works correctly with wrap around provided times are not too far apart
or the interval is not too long."
  (LDB 23. (%POINTER-DIFFERENCE TIME1 TIME2)))

(DEFUN TIME-INCREMENT (TIME INCREMENT)
  "Add an interval to value of (TIME), both measured in 60'ths of a second.
This works correctly with wrap around provided times are not too far apart
or the interval is not too long."
  (LDB 23. (%MAKE-POINTER-OFFSET DTP-FIX TIME INCREMENT))) 

(DEFUN FUNCALL (&FUNCTIONAL FN &EVAL &REST ARGS)
  "Apply FN to the ARGS."
  (APPLY FN ARGS))

(DEFUN APPLY (FUNCTION &REST ARGS)
  "Apply FUNCTION to the ARGS, except that the last element of ARGS is a list of args.
Thus, (APPLY #'FOO 'X '(Y Z)) does (FOO 'X 'Y 'Z).
If there are no ARGS, the car of FUNCTION is applied to the cdr of FUNCTION."
  (COND ((NULL ARGS)
	 (APPLY (CAR FUNCTION) (CDR FUNCTION)))
	((NULL (CDR ARGS))
	 (APPLY FUNCTION (CAR ARGS)))
	(T
	 (%OPEN-CALL-BLOCK FUNCTION 0 4)	;No ADI, D-RETURN
	 (%ASSURE-PDL-ROOM (+ (1- (LENGTH ARGS)) (LENGTH (LAST ARGS))))
	 (DO ((ARGL ARGS (CDR ARGL)))
	     ((NULL (CDR ARGL))
	      (DO ((RESTARGL (CAR ARGL) (CDR RESTARGL)))
		  ((NULL RESTARGL)
		   (%ACTIVATE-OPEN-CALL-BLOCK))
		(%PUSH (CAR RESTARGL))))
	   (%PUSH (CAR ARGL))))))
;;; not a subst for speed. Has a decompiler-synonym to apply in SYS: SYS; QCOPT
(DEFF LEXPR-FUNCALL #'APPLY)

(DEFUN RESET-TEMPORARY-AREA (AREA)
  "Set all free pointers of an area to 0, deleting its entire contents."
  (UNLESS (AREA-TEMPORARY-P AREA)
    (MULTIPLE-CERROR () ()
		     ("The area ~S (~S) was not created as temporary." (AREA-NAME AREA) AREA)
      ("Don't reset this area" (RETURN-FROM RESET-TEMPORARY-AREA NIL))
      ("Make area temporary, and the reset it" (MAKE-AREA-TEMPORARY AREA))))
  (WITHOUT-INTERRUPTS				;don't let the area's region list change
    (DO REGION (AREA-REGION-LIST AREA) (REGION-LIST-THREAD REGION) (MINUSP REGION)
      (GC-RESET-FREE-POINTER REGION 0))))

;;; This function is used to adjust the free pointer of a region up or down,
;;; for functions other than the normal microcoded CONS and UN-CONS.
;;; It must do the following:
;;;  Store into REGION-FREE-POINTER
;;;  If REGION-GC-POINTER  the old free pointer, set it to the new free pointer
;;;    (This does not work for compact-consing list regions, but it won't be called for them)
;;;    (This is actually only necessary when decreasing the free pointer, but it
;;;     doesn't hurt to do it all the time.)
;;;  Reset the scavenger if it is in that region.  Could check for an actual
;;;   conflict, but that would be more difficult and wouldn't buy a great deal.
;;;  Adjust A-CONS-WORK-DONE
(DEFUN GC-RESET-FREE-POINTER (REGION NEWFP &OPTIONAL IGNORE-IF-DOWNWARD-FLAG)
  (OR INHIBIT-SCHEDULING-FLAG
      (FERROR NIL "This function must be called with scheduling inhibited"))
  (LET ((OLDFP (REGION-FREE-POINTER REGION)))
    (COND ((OR (< OLDFP NEWFP)
	       (NOT IGNORE-IF-DOWNWARD-FLAG))
	   (STORE (REGION-FREE-POINTER REGION) NEWFP)
	   (COND ((> (REGION-GC-POINTER REGION) OLDFP)
		  (FERROR NIL "The free pointer of region ~S is screwed" REGION))
		 ((OR (= (REGION-GC-POINTER REGION) OLDFP)
		      ( (REGION-GC-POINTER REGION) NEWFP))
		  (STORE (REGION-GC-POINTER REGION) NEWFP)))
	   (%GC-SCAV-RESET REGION)
	   (%GC-CONS-WORK (- NEWFP OLDFP))))))

(DEFUN MARK-NOT-FREE (POINTER)
  "Move up a region's free pointer, if necessary, so that location POINTER is not free."
  (WITHOUT-INTERRUPTS
    (GC-RESET-FREE-POINTER (%REGION-NUMBER POINTER)
			   (1+ (%POINTER-DIFFERENCE POINTER
						    (REGION-ORIGIN (%REGION-NUMBER POINTER))))
			   T)))

(DEFUN ADJUST-ARRAY-SIZE (ARRAY NEW-INDEX-LENGTH
			  &AUX REGION CURRENT-DATA-LENGTH ARRAY-TYPE-NUMBER 
			       NDIMS ENTRIES-PER-Q NEW-DATA-LENGTH NEW-ARRAY 
			       FREED-ARRAY-LOCN FREED-ARRAY-LENGTH
			       ARRAY-DATA-BASE LONG-ARRAY-BIT CURRENT-INDEX-LENGTH
			       ARRAY-DATA-BASE-RELATIVE-TO-REGION-ORIGIN)
"Make ARRAY larger or smaller.  NEW-INDEX-LENGTH is the new size.
For multi-dimensional arrays, changes the last dimension (the one which varies slowest).
If array displaced, adjust request refers to the displaced header, not pointed-to data.
Making an array larger may forward it.  The value returned is the new array,
not the old, forwarded one."
  (CHECK-TYPE ARRAY ARRAY)
  (WITHOUT-INTERRUPTS		;Disallow garbage collection (flipping), references
				; to the array, and allocation in the region.
    (SETQ ARRAY (FOLLOW-STRUCTURE-FORWARDING ARRAY))
    ;; By this point, ARRAY cannot be in oldspace
    (SETQ NDIMS (%P-LDB %%ARRAY-NUMBER-DIMENSIONS ARRAY)
	  LONG-ARRAY-BIT (%P-LDB %%ARRAY-LONG-LENGTH-FLAG ARRAY)
	  ARRAY-DATA-BASE (+ (%MAKE-POINTER DTP-FIX ARRAY)	;Safe since can't move now
			     LONG-ARRAY-BIT	;Careful, this can be a negative number!
			     NDIMS)
	  CURRENT-INDEX-LENGTH (IF (ZEROP LONG-ARRAY-BIT)
				   (%P-LDB %%ARRAY-INDEX-LENGTH-IF-SHORT ARRAY)
				 (%P-CONTENTS-OFFSET ARRAY 1))
	  REGION (%REGION-NUMBER ARRAY)
	  ARRAY-DATA-BASE-RELATIVE-TO-REGION-ORIGIN
	  	 (%POINTER-DIFFERENCE ARRAY-DATA-BASE
				      (REGION-ORIGIN REGION))				     
	  ARRAY-TYPE-NUMBER (%P-LDB %%ARRAY-TYPE-FIELD ARRAY)
	  ENTRIES-PER-Q (AR-1 (FUNCTION ARRAY-ELEMENTS-PER-Q) ARRAY-TYPE-NUMBER)
	  NEW-DATA-LENGTH (IF (PLUSP ENTRIES-PER-Q)
			      (CEILING NEW-INDEX-LENGTH ENTRIES-PER-Q)
			    (* NEW-INDEX-LENGTH (MINUS ENTRIES-PER-Q)))
	  CURRENT-DATA-LENGTH (IF (PLUSP ENTRIES-PER-Q)
				  (CEILING CURRENT-INDEX-LENGTH ENTRIES-PER-Q)
				(* CURRENT-INDEX-LENGTH (MINUS ENTRIES-PER-Q))))
    (COND ((NOT (ZEROP (%P-LDB %%ARRAY-DISPLACED-BIT ARRAY)))	;Displaced array
	   (SETQ CURRENT-INDEX-LENGTH (%P-CONTENTS-OFFSET ARRAY-DATA-BASE 1))
	   (COND ((> NEW-INDEX-LENGTH CURRENT-INDEX-LENGTH)
		  (FERROR NIL "Can't make displaced array ~S bigger" ARRAY)))
	   (%P-STORE-CONTENTS-OFFSET NEW-INDEX-LENGTH ARRAY-DATA-BASE 1)
	   ARRAY)
	  ((AND
	     ( NEW-DATA-LENGTH CURRENT-DATA-LENGTH)	;No new storage required
	     (NOT (AND (ZEROP LONG-ARRAY-BIT)		;and length field will not overflow.
		       (> NEW-INDEX-LENGTH %ARRAY-MAX-SHORT-INDEX-LENGTH))))
	   (AND (EQ (ARRAY-TYPE ARRAY) 'ART-Q-LIST)
		(%P-DPB-OFFSET CDR-NIL %%Q-CDR-CODE ARRAY-DATA-BASE (1- NEW-DATA-LENGTH)))
	   (COND ((= NEW-DATA-LENGTH CURRENT-DATA-LENGTH))	;No storage change
		 ((= (+ ARRAY-DATA-BASE-RELATIVE-TO-REGION-ORIGIN
			CURRENT-DATA-LENGTH)	;Give back from end of region
		     (REGION-FREE-POINTER REGION))
		  (GC-RESET-FREE-POINTER REGION
					 (+ ARRAY-DATA-BASE-RELATIVE-TO-REGION-ORIGIN
					    NEW-DATA-LENGTH)))
		 (T				;Fill hole in region with an ART-32B array
		  (%GC-SCAV-RESET REGION)	;Make scavenger forget about this region
		  (SETQ FREED-ARRAY-LOCN
			(%MAKE-POINTER-OFFSET DTP-FIX ARRAY-DATA-BASE NEW-DATA-LENGTH))
		  (COND (( (SETQ FREED-ARRAY-LENGTH
				  (1- (- CURRENT-DATA-LENGTH NEW-DATA-LENGTH)))
			    %ARRAY-MAX-SHORT-INDEX-LENGTH)
			 (%P-STORE-TAG-AND-POINTER FREED-ARRAY-LOCN DTP-ARRAY-HEADER 
						   (+ ARRAY-DIM-MULT ART-32B
						      FREED-ARRAY-LENGTH)))
			(T (%P-STORE-TAG-AND-POINTER FREED-ARRAY-LOCN DTP-ARRAY-HEADER 
						     (+ ARRAY-DIM-MULT ART-32B
							ARRAY-LONG-LENGTH-FLAG))
			   (%P-STORE-CONTENTS-OFFSET (1- FREED-ARRAY-LENGTH)
						     FREED-ARRAY-LOCN
						     1)))))
	   (IF (ZEROP LONG-ARRAY-BIT)
	       (%P-DPB NEW-INDEX-LENGTH %%ARRAY-INDEX-LENGTH-IF-SHORT ARRAY)
	       (%P-STORE-CONTENTS-OFFSET NEW-INDEX-LENGTH ARRAY 1))
	   ARRAY)
	  ;; Need increased storage.  Either make fresh copy or extend existing copy.
	  ((OR (AND (ZEROP LONG-ARRAY-BIT)	     ;See if need to make fresh copy because
		    (> NEW-INDEX-LENGTH %ARRAY-MAX-SHORT-INDEX-LENGTH)) ;need format change
	       (< (+ ARRAY-DATA-BASE-RELATIVE-TO-REGION-ORIGIN
		     CURRENT-DATA-LENGTH)	;or not at end of region
		  (REGION-FREE-POINTER REGION))
	       (> (+ ARRAY-DATA-BASE-RELATIVE-TO-REGION-ORIGIN
		     NEW-DATA-LENGTH)		;or region isn't big enough
		  (REGION-LENGTH REGION)))
	   (SETQ NEW-ARRAY (MAKE-ARRAY (IF (= NDIMS 1) NEW-INDEX-LENGTH
					   (LET ((DIMS (ARRAY-DIMENSIONS ARRAY)))
					     (RPLACA (LAST DIMS) 1)
					     (RPLACA (LAST DIMS)
						     (TRUNCATE NEW-INDEX-LENGTH
							       (APPLY #'* DIMS)))
					     DIMS))
				       :AREA (%AREA-NUMBER ARRAY)
				       :TYPE (AR-1 (FUNCTION ARRAY-TYPES) ARRAY-TYPE-NUMBER)
				       :LEADER-LENGTH (ARRAY-LEADER-LENGTH ARRAY)))
	   (COPY-ARRAY-CONTENTS-AND-LEADER ARRAY NEW-ARRAY)
	   (%P-DPB (%P-LDB %%ARRAY-NAMED-STRUCTURE-FLAG ARRAY)
		   %%ARRAY-NAMED-STRUCTURE-FLAG NEW-ARRAY)
	   (%P-DPB (%P-LDB %%ARRAY-FLAG-BIT ARRAY)
		   %%ARRAY-FLAG-BIT NEW-ARRAY)
	   (STRUCTURE-FORWARD ARRAY NEW-ARRAY)
	   NEW-ARRAY)
	  (T					;Array is at end of region, just make bigger
	   (GC-RESET-FREE-POINTER REGION (+ ARRAY-DATA-BASE-RELATIVE-TO-REGION-ORIGIN
					    NEW-DATA-LENGTH))
	   (SETQ AR-1-ARRAY-POINTER-1 NIL)
	   (SETQ AR-1-ARRAY-POINTER-2 NIL)
	   (IF (ZEROP LONG-ARRAY-BIT)
	       (%P-DPB NEW-INDEX-LENGTH %%ARRAY-INDEX-LENGTH-IF-SHORT ARRAY)
	     (%P-STORE-CONTENTS-OFFSET NEW-INDEX-LENGTH ARRAY 1))
	   (LET ((FILL-WITH-CDR-NEXT (AND (= ARRAY-TYPE-NUMBER ART-Q-LIST)
					  (NOT (AND (ARRAY-HAS-LEADER-P ARRAY)
						    (NUMBERP (ARRAY-LEADER ARRAY 0))))))
		 (ADR (%MAKE-POINTER-OFFSET DTP-FIX ARRAY-DATA-BASE CURRENT-DATA-LENGTH))
		 (N (- NEW-DATA-LENGTH CURRENT-DATA-LENGTH))
		 (NUMERIC-P (ARRAY-BITS-PER-ELEMENT ARRAY-TYPE-NUMBER)))
	     ;; Fill with NIL or 0
	     ;; For an ART-Q-LIST with no fill pointer, extend with CDR-NEXT codes.
	     (UNLESS (ZEROP N)
	       (COND (NUMERIC-P
		      (%P-DPB 0 %%Q-LOW-HALF ADR)
		      (%P-DPB 0 %%Q-HIGH-HALF ADR))
		     (FILL-WITH-CDR-NEXT
		      (%P-STORE-CONTENTS ADR NIL)
		      (%P-DPB CDR-NEXT %%Q-CDR-CODE ADR))
		     (T
		      (%P-STORE-CONTENTS ADR NIL)
		      (%P-DPB CDR-NIL %%Q-CDR-CODE ADR)))
	       (UNLESS (= N 1)
		 (IF NUMERIC-P
		     (%BLT ADR (%MAKE-POINTER-OFFSET DTP-FIX ADR 1) (1- N) 1)
		   (%BLT-TYPED ADR (%MAKE-POINTER-OFFSET DTP-FIX ADR 1) (1- N) 1))))
	     ;; But if we extended with cdr-next codes, fix up the boundaries.
	     (WHEN FILL-WITH-CDR-NEXT
	       (%P-DPB-OFFSET CDR-NEXT %%Q-CDR-CODE
			      ARRAY-DATA-BASE (1- CURRENT-DATA-LENGTH))
	       (%P-DPB-OFFSET CDR-NIL %%Q-CDR-CODE
			      ARRAY-DATA-BASE (1- NEW-DATA-LENGTH))))
	   ARRAY))))

(DEFCONST RETURN-STORAGE-GARBAGE-LIST (LIST NIL))
(DEFCONST RETURN-STORAGE-GARBAGE-ARRAY (MAKE-ARRAY 0))

(DEFUN RETURN-STORAGE (OBJECT &AUX REGION OBJECT-ORIGIN OBJECT-SIZE)
  "Dispose of OBJECT, returning its storage to free if possible.
If OBJECT is a displaced array, the displaced-array header is what is freed.
You had better get rid of all pointers to OBJECT before calling this,
 e.g. (RETURN-STORAGE (PROG1 FOO (SETQ FOO NIL)))
Returns T if storage really reclaimed, NIL if not."
  ;; Turn off garbage collection, allocation in this region
  (WITHOUT-INTERRUPTS		
    ;; Make sure object gets transported.
    (SETQ OBJECT-ORIGIN (%P-POINTER OBJECT))
    (SETQ REGION (%REGION-NUMBER OBJECT)
	  OBJECT-ORIGIN (%POINTER (%FIND-STRUCTURE-LEADER OBJECT))
	  OBJECT-SIZE (%STRUCTURE-TOTAL-SIZE OBJECT))
    (SETQ AR-1-ARRAY-POINTER-1 NIL)
    (SETQ AR-1-ARRAY-POINTER-2 NIL)
    (WHEN (= (%P-DATA-TYPE OBJECT) DTP-HEADER-FORWARD)
      (WHEN (RETURN-STORAGE (%FIND-STRUCTURE-HEADER (%P-POINTER OBJECT)))
	;; Get rid of the pointer to the object forwarded to.
	(%P-STORE-POINTER
	  OBJECT
	  (IF (= %REGION-REPRESENTATION-TYPE-LIST
		 (%LOGLDB %%REGION-REPRESENTATION-TYPE
			  (REGION-BITS REGION)))
	      RETURN-STORAGE-GARBAGE-LIST
	    RETURN-STORAGE-GARBAGE-ARRAY))))
    (COND ((= (%MAKE-POINTER-OFFSET DTP-FIX OBJECT-ORIGIN OBJECT-SIZE)
	      (%MAKE-POINTER-OFFSET DTP-FIX
				    (REGION-ORIGIN REGION) (REGION-FREE-POINTER REGION)))
	   (GC-RESET-FREE-POINTER REGION (%POINTER-DIFFERENCE OBJECT-ORIGIN
							      (REGION-ORIGIN REGION)))
	   T)
	  (T NIL))))

(DEFF RETURN-ARRAY 'RETURN-STORAGE)

;;; These are used by DEFVAR and DEFCONST in LMMAC
(DEFUN DEFVAR-1 (&QUOTE SYMBOL &OPTIONAL (VALUE :UNBOUND) DOCUMENTATION)
  (IF (EQ (CAR-SAFE SYMBOL) 'QUOTE) (SETQ SYMBOL (CADR SYMBOL)))
  (WHEN (RECORD-SOURCE-FILE-NAME SYMBOL 'DEFVAR)
    (SETF (GET SYMBOL 'SPECIAL) (OR FDEFINE-FILE-PATHNAME T))
    (AND (NEQ VALUE :UNBOUND)
	 (OR FS:THIS-IS-A-PATCH-FILE (NOT (BOUNDP SYMBOL)))
	 (SET SYMBOL (EVAL1 VALUE)))
    (SETF (DOCUMENTATION SYMBOL 'VARIABLE) DOCUMENTATION))
  SYMBOL)

(DEFUN DEFCONST-1 (&QUOTE SYMBOL &EVAL VALUE &OPTIONAL DOCUMENTATION)
  (IF (EQ (CAR-SAFE SYMBOL) 'QUOTE) (SETQ SYMBOL (CADR SYMBOL)))
  (WHEN (RECORD-SOURCE-FILE-NAME SYMBOL 'DEFVAR)
    (SETF (GET SYMBOL 'SPECIAL) (OR FDEFINE-FILE-PATHNAME T))
    (SET SYMBOL VALUE)
    (SETF (DOCUMENTATION SYMBOL 'VARIABLE) DOCUMENTATION))
  SYMBOL)

;;;; Function spec and source file name stuff

;;;---!!! The following functions and variables (everything up to next
;;;---!!!   page break) should be moved to SYS: SYS; FSPEC LISP, but due
;;;---!!!   to isseus (see FSPEC LISP) hasn't been done just yet.
;;;---!!!   
;;;---!!!	INHIBIT-FDEFINE-WARNINGS 
;;;---!!!	VALIDATE-FUNCTION-SPEC 
;;;---!!!	FDEFINE 
;;;---!!!	FDEFINEDP 
;;;---!!!	FDEFINITION 
;;;---!!!	FDEFINEDP-AND-FDEFINITION 

;;; (The rest of this is in QMISC)

;;; A function-specifier is just a way of talking about a function
;;; for purposes other than applying it.  It can be a symbol, in which case
;;; the function cell of the symbol is used.  Or it can be a list of one of
;;; these formats:
;;; (:METHOD class-name operation) refers to the method in that class for
;;;   that operation; this works for both Class methods and Flavor methods.
;;;   In the case of Flavor methods, the specification may also be of the form
;;;   (:METHOD flavor-name type operation).
;;; (:INSTANCE-METHOD exp operation).  exp should evaluate to an entity.
;;;   Reference is then to the operation directly on that instance.
;;; (:HANDLER flavor operation) refers to the function that is called when
;;;   an object of flavor FLAVOR is sent the message OPERATION.
;;; (:WITHIN within-function renamed-function) refers to renamed-function,
;;;   but only as called directly from within-function.
;;;   Actually, renamed-function is replaced throughout within-function
;;;   by an uninterned symbol whose definition is just renamed-function
;;;   as soon as an attempt is made to do anything to a function spec
;;;   of this form.  The function spec is from then on equivalent
;;;   to that uninterned symbol.
;;; (:PROPERTY symbol property) refers to (GET symbol property).
;;; (:LOCATION locative-or-list-pointer) refers to the CDR of the pointer.
;;;   This is for pointing at an arbitrary place
;;;   which there is no special way to describe.
;;; One place you can use a function specifier is in DEFUN.

;;; For Maclisp compatibility, a list whose car is not recognized is taken
;;; to be a list of a symbol and a property, by DEFUN and DEFMACRO.  They
;;; standardize this by putting :PROPERTY on the front.  These
;;; non-standard function specs are not accepted by the rest of the
;;; system.  This is done to avoid ambiguities and inconsistencies.

;;; The SYS:FUNCTION-SPEC-HANDLER property of a symbol, if present means that that
;;; symbol is legal as the car of a function spec.  The value of the property
;;; is a function whose arguments are the function in behalf
;;; of which to act (not a keyword symbol!) and the arguments to that
;;; function (the first of which is always the function spec).
;;; Functions are:
;;;	FDEFINE definition
;;;	FDEFINEDP
;;;	FDEFINITION
;;;	FDEFINITION-LOCATION
;;;	FUNDEFINE
;;;	FUNCTION-PARENT
;;;	COMPILER-FDEFINEDP -- returns T if will be fdefinedp at run time
;;;	GET indicator
;;;	PUTPROP value indicator
;;;	DWIMIFY original-spec def-decoder (see below, DWIMIFY-PACKAGE-2).

(DEFVAR INHIBIT-FDEFINE-WARNINGS NIL
  "T turns off warnings of redefining function in different file.
:JUST-WARN turns off queries, leaving just warnings.")

(DEFUN VALIDATE-FUNCTION-SPEC (FUNCTION-SPEC &AUX HANDLER)
  "Predicate for use with CHECK-ARG.  Returns non-nil if FUNCTION-SPEC really is one.
The value is the type of function spec (T for a symbol)."
  (COND ((ATOM FUNCTION-SPEC)
	 (SYMBOLP FUNCTION-SPEC))
	((AND (SYMBOLP (CAR FUNCTION-SPEC))
	      (SETQ HANDLER (GET (CAR FUNCTION-SPEC) 'FUNCTION-SPEC-HANDLER))
	      (FUNCALL HANDLER 'VALIDATE-FUNCTION-SPEC FUNCTION-SPEC))
	 (CAR FUNCTION-SPEC))))

(DEFPROP ENCAPSULATION "encapsulation" DEFINITION-TYPE-NAME)

(DEFUN FDEFINE (FUNCTION-SPEC DEFINITION &OPTIONAL CAREFULLY-FLAG NO-QUERY-FLAG
					 &AUX TYPE INNER-SPEC DEFINEDP)
  "Alter the function definition of a function specifier.
CAREFULLY-FLAG means preserve any tracing or advice,
and save the old definition, when possible.
This function returns T if it does define the function, or NIL if it does not.
If FDEFINE-FILE-PATHNAME is non-NIL, then it is the file which this definition
was read from, and we make a note of that fact when possible."

  ;; Get error if invalid fun spec.  Also find out whether defined.
  (SETQ DEFINEDP (FDEFINEDP FUNCTION-SPEC))
  (IF (CONSP FUNCTION-SPEC) (SETQ TYPE (CAR FUNCTION-SPEC)))

  ;; Record the source file name, if desired, and check for redefinition errors
  (COND ((OR (EQ TYPE :INTERNAL)
	     (RECORD-SOURCE-FILE-NAME FUNCTION-SPEC
				      (IF CAREFULLY-FLAG 'DEFUN 'ENCAPSULATION)
				      (OR NO-QUERY-FLAG (NOT CAREFULLY-FLAG)
					  (EQ INHIBIT-FDEFINE-WARNINGS T))))

	 ;; If there is a previous definition, save it (if desired).
	 ;; Also if it is encapsulated, set INNER-SPEC to the symbol
	 ;; which holds the real definition before encapsulation, and
	 ;; save that definition.
	 (COND ((AND DEFINEDP CAREFULLY-FLAG)
		(SETQ INNER-SPEC (UNENCAPSULATE-FUNCTION-SPEC FUNCTION-SPEC))
		(MULTIPLE-VALUE-BIND (DEFP DEFN)
		    (FDEFINEDP-AND-FDEFINITION INNER-SPEC)
		  (AND DEFP
		       (FUNCTION-SPEC-PUTPROP FUNCTION-SPEC DEFN :PREVIOUS-DEFINITION)))
		;; Carry over renamings from previous definition
		(AND (NEQ FUNCTION-SPEC INNER-SPEC)	;Skip it if no encapsulations.
		     (FBOUNDP 'RENAME-WITHIN-NEW-DEFINITION-MAYBE)
		     (SETQ DEFINITION (RENAME-WITHIN-NEW-DEFINITION-MAYBE FUNCTION-SPEC
									  DEFINITION))))
	       (T (SETQ INNER-SPEC FUNCTION-SPEC)))

	 ;; Now store the new definition in type-dependent fashion
	 (IF (SYMBOLP INNER-SPEC) (FSET INNER-SPEC DEFINITION)
	     (FUNCALL (GET TYPE 'FUNCTION-SPEC-HANDLER) 'FDEFINE INNER-SPEC DEFINITION))

	 ;; Return T since we did define the function
	 T)
	;; Return NIL since we decided not to define the function
	(T NIL)))

;;; Is a function specifier defined?  A generalization of FBOUNDP.
(DEFUN FDEFINEDP (FUNCTION-SPEC &AUX HANDLER)
  "Returns T if the function spec has a function definition."
  ;; Then perform type-dependent code
  (COND ((SYMBOLP FUNCTION-SPEC) (FBOUNDP FUNCTION-SPEC))
	((AND (CONSP FUNCTION-SPEC)
	      (SETQ HANDLER (GET (CAR FUNCTION-SPEC) 'FUNCTION-SPEC-HANDLER)))
	 (FUNCALL HANDLER 'FDEFINEDP FUNCTION-SPEC))
	(T (FERROR 'SYS:INVALID-FUNCTION-SPEC
		   "The function spec ~S is invalid." FUNCTION-SPEC))))

;;; Get the definition of a function specifier.  Generalized FSYMEVAL.
(DEFUN FDEFINITION (FUNCTION-SPEC &AUX HANDLER)
  "Returns the function definition of a function spec"
  ;; First, validate the function spec.
  (SETQ FUNCTION-SPEC (DWIMIFY-ARG-PACKAGE FUNCTION-SPEC 'FUNCTION-SPEC))
  (COND ((SYMBOLP FUNCTION-SPEC) (SYMBOL-FUNCTION FUNCTION-SPEC))
	((AND (CONSP FUNCTION-SPEC)
	      (SETQ HANDLER (GET (CAR FUNCTION-SPEC) 'FUNCTION-SPEC-HANDLER)))
	 (FUNCALL HANDLER 'FDEFINITION FUNCTION-SPEC))
	(T (FERROR 'SYS:INVALID-FUNCTION-SPEC
		   "The function spec ~S is invalid." FUNCTION-SPEC))))

(DEFUN FDEFINEDP-AND-FDEFINITION (FUNCTION-SPEC &AUX HANDLER)
  "Returns whether the FUNCTION-SPEC is defined, and its definition if so.
The first value is T or NIL, the second is the definition if the first is T."
  ;; First, validate the function spec.
  (COND ((SYMBOLP FUNCTION-SPEC)
	 (IF (FBOUNDP FUNCTION-SPEC)
	     (VALUES T (SYMBOL-FUNCTION FUNCTION-SPEC))))
	((AND (CONSP FUNCTION-SPEC)
	      (SETQ HANDLER (GET (CAR FUNCTION-SPEC) 'FUNCTION-SPEC-HANDLER)))
	 (MULTIPLE-VALUE-BIND (DEFINEDP DEFN)
	     (FUNCALL HANDLER 'FDEFINEDP FUNCTION-SPEC)
	   (IF DEFINEDP
	       (VALUES T (OR DEFN (FDEFINITION FUNCTION-SPEC))))))
	(T (FERROR 'SYS:INVALID-FUNCTION-SPEC
		   "The function spec ~S is invalid." FUNCTION-SPEC))))

(DEFF DWIMIFY-FUNCTION-SPEC 'DWIMIFY-PACKAGE)
(DEFUN DWIMIFY-PACKAGE (FUNCTION-SPEC &OPTIONAL (DEFINITION-TYPE 'FDEFINEDP))
  "Return a function spec similar to FUNCTION-SPEC but which is defined.
We check for symbols in the wrong package, and various other things.
The user is asked to confirm the candidate values.
If the user does not accept some candidate, we get an error and he can
continue with some other function spec.
DEFINITION-TYPE is a symbol which has properties that say what /"defined/" means.
Two possibilities are FDEFINEDP meaning /"is defined as a function/"
and BOUNDP meaning /"is a symbol with a value/"."
  (DO (TEM (DEF-DECODER (GET DEFINITION-TYPE 'DWIMIFY)))
      (())
    (COND ((AND (FUNCALL (FIRST DEF-DECODER) FUNCTION-SPEC)
		(FUNCALL (SECOND DEF-DECODER) FUNCTION-SPEC))
	   (RETURN FUNCTION-SPEC))
	  ((SETQ TEM (DWIMIFY-PACKAGE-0 FUNCTION-SPEC DEFINITION-TYPE))
	   (RETURN TEM)))
    (SETQ FUNCTION-SPEC
	  (CERROR T NIL :WRONG-TYPE-ARG "~1@*~S is not ~A"
		  DEFINITION-TYPE FUNCTION-SPEC
		  (GET DEFINITION-TYPE 'DWIMIFY-ERROR-MESSAGE)))))

;;; Do (SETQ FUNCTION-SPEC (DWIMIFY-ARG-PACKAGE FUNCTION-SPEC 'MY-ARG-NAME))
;;; to dwimify and get a suitable error message for MY-ARG-NAME if that fails.
(DEFPROP DWIMIFY-ARG-PACKAGE T :ERROR-REPORTER)
(DEFUN DWIMIFY-ARG-PACKAGE (FUNCTION-SPEC ARG-NAME &OPTIONAL (DEFINITION-TYPE 'FDEFINEDP))
  "Like DWIMIFY-PACKAGE but error message is different if fail to dwimify.
The error message says that the bad value was the arg named ARG-NAME
of the function that called this one."
  (DO (TEM (DEF-DECODER (GET DEFINITION-TYPE 'DWIMIFY)))
      (())
    (COND ((AND (FUNCALL (FIRST DEF-DECODER) FUNCTION-SPEC)
		(FUNCALL (SECOND DEF-DECODER) FUNCTION-SPEC))
	   (RETURN FUNCTION-SPEC))
	  ((SETQ TEM (DWIMIFY-PACKAGE-0 FUNCTION-SPEC DEFINITION-TYPE))
	   (RETURN TEM)))
    (SETQ FUNCTION-SPEC
	  (CERROR T NIL :WRONG-TYPE-ARG "The argument ~3@*~S is ~1@*~S,~%which is not ~A"
		  DEFINITION-TYPE FUNCTION-SPEC
		  (GET DEFINITION-TYPE 'DWIMIFY-ERROR-MESSAGE)
		  ARG-NAME))))

(DEFPROP FDEFINEDP (VALIDATE-FUNCTION-SPEC FDEFINEDP FDEFINITION-LOCATION "definition"
					   FUNCTION-SPEC-DWIMIFY)
	 DWIMIFY)
(DEFPROP FDEFINEDP "a valid, defined function spec" DWIMIFY-ERROR-MESSAGE)

(DEFPROP BOUNDP (SYMBOLP BOUNDP VALUE-CELL-LOCATION "value" IGNORE) DWIMIFY)
(DEFPROP BOUNDP "a symbol with a value" DWIMIFY-ERROR-MESSAGE)

;;; Given a maybe invalid, maybe undefined function spec (or other sort of object),
;;; ask the user about possible alternatives he might have meant.
;;; If the user accepts one, we return it.  Otherwise we return nil.
;;; DEFINITION-TYPE says what kind of object we are looking for.
;;; It should be a symbol with a SI:DWIMIFY property.
(DEFVAR DWIMIFY-PACKAGE-0-TOPIC-PRINTED NIL)
(DEFUN DWIMIFY-PACKAGE-0 (FUNCTION-SPEC DEFINITION-TYPE)
  "Like DWIMIFY-PACKAGE except return NIL we do not find a replacement function spec."
  (LET (DWIMIFY-PACKAGE-0-TOPIC-PRINTED)
    (DWIMIFY-PACKAGE-1 FUNCTION-SPEC FUNCTION-SPEC (GET DEFINITION-TYPE 'DWIMIFY))))

;;; DWIMIFY-INFO should be something like 
;;;  (VALIDATE-FUNCTION-SPEC FDEFINEDP FDEFINITION-LOCATION "defn" FUNCTION-SPEC-DWIMIFY)
;;; If the third element is nil, the option of linking the symbols is not offered.
(DEFUN DWIMIFY-PACKAGE-1 (FUNCTION-SPEC ORIGINAL-SPEC DWIMIFY-INFO
			  &AUX TEM (PREDICATE (SECOND DWIMIFY-INFO))
			  (VALIDATOR (FIRST DWIMIFY-INFO))
			  (AUX-DWIMIFIER (FIFTH DWIMIFY-INFO)))
  (COND ((AND (VALIDATE-FUNCTION-SPEC FUNCTION-SPEC)
	      (FUNCALL PREDICATE FUNCTION-SPEC))
	 FUNCTION-SPEC)
	((SYMBOLP FUNCTION-SPEC)
	 ;; If it's a symbol, try symbols in other packages.
	 (*CATCH 'DWIMIFY-PACKAGE
	   (MAP-OVER-LOOKALIKE-SYMBOLS (SYMBOL-NAME FUNCTION-SPEC) NIL
				       'DWIMIFY-PACKAGE-2
				       ORIGINAL-SPEC DWIMIFY-INFO)
	   NIL))
	((ATOM FUNCTION-SPEC) NIL)
	;; If the function spec's handler has any ideas, try them first.
	((AND (FUNCALL VALIDATOR FUNCTION-SPEC)
	      (FUNCALL AUX-DWIMIFIER FUNCTION-SPEC ORIGINAL-SPEC DWIMIFY-INFO)))
	;; Maybe we can get something by standardizing a maclisp function spec.
	((AND (NEQ (STANDARDIZE-FUNCTION-SPEC FUNCTION-SPEC NIL) FUNCTION-SPEC)
	      (DWIMIFY-PACKAGE-1 (STANDARDIZE-FUNCTION-SPEC FUNCTION-SPEC NIL)
				 ORIGINAL-SPEC DWIMIFY-INFO)))
	((AND (SYMBOLP (CAR FUNCTION-SPEC))
	      (SETQ TEM (INTERN-SOFT (CAR FUNCTION-SPEC) PKG-KEYWORD-PACKAGE))
	      (NEQ (CAR FUNCTION-SPEC) TEM)
	      ;; If list whose car is a symbol not in Keyword,
	      ;; try replacing the car with a symbol in Keyword.
	      (DWIMIFY-PACKAGE-1 (CONS TEM (CDR FUNCTION-SPEC))
				 ORIGINAL-SPEC DWIMIFY-INFO)))
	((AND (CDDR FUNCTION-SPEC) (SYMBOLP (CADDR FUNCTION-SPEC))
	      (SETQ TEM (INTERN-SOFT (CADDR FUNCTION-SPEC) PKG-KEYWORD-PACKAGE))
	      (NEQ (CADDR FUNCTION-SPEC) TEM)
	      ;; Try a similar thing with the third element
	      (DWIMIFY-PACKAGE-1
		`(,(CAR FUNCTION-SPEC) ,(CADR FUNCTION-SPEC)
		  ,TEM . ,(CDDDR FUNCTION-SPEC))
		ORIGINAL-SPEC DWIMIFY-INFO)))
	((AND (CDDDR FUNCTION-SPEC) (SYMBOLP (CADDDR FUNCTION-SPEC))
	      (SETQ TEM (INTERN-SOFT (CADDDR FUNCTION-SPEC) PKG-KEYWORD-PACKAGE))
	      (NEQ (CADDDR FUNCTION-SPEC) TEM)
	      ;; and the fourth element.
	      (DWIMIFY-PACKAGE-1
		`(,(CAR FUNCTION-SPEC) ,(CADR FUNCTION-SPEC) ,(CADDR FUNCTION-SPEC)
		  ,TEM . ,(CDDDDR FUNCTION-SPEC))
		ORIGINAL-SPEC DWIMIFY-INFO)))
	((AND (CDR FUNCTION-SPEC) (SYMBOLP (CADR FUNCTION-SPEC)))
	 ;; Try replacing the second element with symbols in other packages.
	 (*CATCH 'DWIMIFY-PACKAGE
	   (MAP-OVER-LOOKALIKE-SYMBOLS
	     (SYMBOL-NAME (CADR FUNCTION-SPEC))
	     NIL
	     #'(LAMBDA (NEW-SYMBOL SPEC ORIGINAL-SPEC DWIMIFY-INFO)
		 (OR (EQ NEW-SYMBOL (CADR SPEC))
		     (DWIMIFY-PACKAGE-2 `(,(CAR SPEC) ,NEW-SYMBOL . ,(CDDR SPEC))
					ORIGINAL-SPEC DWIMIFY-INFO)))
	     FUNCTION-SPEC ORIGINAL-SPEC DWIMIFY-INFO)
	   NIL))))

(DEFUN MAP-OVER-LOOKALIKE-SYMBOLS (PNAME IGNORE FUNCTION &REST ADDITIONAL-ARGS &AUX SYM)
  "Call FUNCTION for each symbol in any package whose name matches PNAME.
The args to FUNCTION are the symbol and the ADDITIONAL-ARGS."
  (DOLIST (PKG *ALL-PACKAGES*)
    (IF (AND (NEQ PKG PKG-KEYWORD-PACKAGE)
	     (SETQ SYM (INTERN-LOCAL-SOFT PNAME PKG)))
	(APPLY FUNCTION SYM ADDITIONAL-ARGS))))

;;; Consider one suggested dwimification, NEW-SPEC, of the ORIGINAL-SPEC.
;;; If the user accepts it, throw it to DWIMIFY-PACKAGE.
;;; DWIMIFY-INFO should be something like 
;;;  (VALIDATE-FUNCTION-SPEC FDEFINEDP FDEFINITION-LOCATION "defn" FUNCTION-SPEC-DWIMIFY)
;;; If the third element is nil, the option of linking the symbols is not offered.
(DEFUN DWIMIFY-PACKAGE-2 (NEW-SPEC ORIGINAL-SPEC DWIMIFY-INFO
			  &OPTIONAL NO-RECURSION &AUX ANS
			  (VALIDATOR (FIRST DWIMIFY-INFO))
			  (PREDICATE (SECOND DWIMIFY-INFO))
			  (LOCATOR (THIRD DWIMIFY-INFO))
			  (PRETTY-NAME (FOURTH DWIMIFY-INFO))
			  (AUX-DWIMIFIER (FIFTH DWIMIFY-INFO)))
  "Subroutine of DWIMIFY-PACKAGE: ask user about one candidate.
This can be used by handlers of types of function specs,
for handling the :DWIMIFY operation.
NEW-SPEC is the candidate.  ORIGINAL-SPEC is what was supplied to DWIMIFY-PACKAGE.
DWIMIFY-INFO is data on the type of definition being looked for, and what to tell the user.
ORIGINAL-SPEC and DWIMIFY-INFO are provided with the :DWIMIFY operation.
NO-RECURSION means do not use this candidate to generate other candidates."
  (AND (NOT (EQUAL NEW-SPEC ORIGINAL-SPEC))
       (FUNCALL VALIDATOR NEW-SPEC)
       (*CATCH 'QUIT
	 (OR (COND ((AND (FUNCALL PREDICATE NEW-SPEC)
			 (PROGN
			   (OR DWIMIFY-PACKAGE-0-TOPIC-PRINTED
			       (FORMAT *QUERY-IO* "~&~S does not have a ~A.~%"
				       ORIGINAL-SPEC PRETTY-NAME
				       (SETQ DWIMIFY-PACKAGE-0-TOPIC-PRINTED T)))
			   (SETQ ANS
				 (FQUERY `(:CHOICES
					    (((T "Yes.") #/Y #/T #/SPACE #/HAND-UP)
					     ((NIL "No.") #/N #/RUBOUT #/C-Z #/HAND-DOWN)
					     ,@(AND (SYMBOLP NEW-SPEC)
						    LOCATOR
						    '(((P "Permanently link ") #/P)))
					     ((G "Go to package ") #/G))
					    :HELP-FUNCTION DWIMIFY-PACKAGE-2-HELP)
					 "Use the ~A of ~S? "
					 PRETTY-NAME NEW-SPEC))))
		    (COND ((EQ ANS 'P)
			   (FORMAT *QUERY-IO* "~S to ~S." ORIGINAL-SPEC NEW-SPEC)
			   (LET ((LOC2 (FUNCALL LOCATOR ORIGINAL-SPEC))
				 (LOC1 (FUNCALL LOCATOR NEW-SPEC)))
			     (SETF (CDR LOC2) LOC1)
			     (%P-STORE-DATA-TYPE LOC2 DTP-ONE-Q-FORWARD)))
			  ((EQ ANS 'G)
			   (LET ((PKG (SYMBOL-PACKAGE
					(IF (SYMBOLP NEW-SPEC) NEW-SPEC
					  (CADR NEW-SPEC)))))
			     (FORMAT *QUERY-IO* "~A." (PKG-NAME PKG))
			     (PKG-GOTO PKG))))
		    (*THROW 'DWIMIFY-PACKAGE NEW-SPEC)))
	     ;; If this one isn't defined of isn't wanted,
	     ;; try any others suggested by this kind of function spec's handler.
	     ;; For :METHOD, this should try inherited methods.
	     ;; With each suggestion, the dwimifier should call this function again,
	     ;; perhaps setting NO-RECURSION.
	     (AND (NOT NO-RECURSION)
		  (LET ((VALUE
			  (FUNCALL AUX-DWIMIFIER NEW-SPEC ORIGINAL-SPEC DWIMIFY-INFO)))
		    (AND VALUE (*THROW 'DWIMIFY-PACKAGE VALUE))))))))

(DEFUN DWIMIFY-PACKAGE-2-HELP (S IGNORE IGNORE)
  (FORMAT S "~&Y to use it this time.
P to use it every time (permanently link the two symbols).
G to use it this time and do a pkg-goto.
N to do nothing special and enter the normal error handler.
"))

;;; This is the AUX-DWIMIFIER in the DWIMIFY property of FDEFINEDP.
(DEFUN FUNCTION-SPEC-DWIMIFY (NEW-SPEC ORIGINAL-SPEC DWIMIFY-INFO)
  (AND (CONSP NEW-SPEC)
       (LET ((HANDLER (GET (CAR NEW-SPEC) 'FUNCTION-SPEC-HANDLER)))
	 (CAR (ERRSET (FUNCALL HANDLER 'DWIMIFY NEW-SPEC
			       ORIGINAL-SPEC DWIMIFY-INFO)
		      NIL)))))

;;;---!!! The following functions and variables (everything up to next
;;;---!!!   page break, and the one after that) should be moved to
;;;---!!!   SYS: SYS; FSPEC LISP, but due to isseus (see FSPEC LISP)
;;;---!!!   hasn't been done just yet.
;;;---!!!   
;;;---!!!	FUNCTION-SPEC-DEFAULT-HANDLER 
;;;---!!!	INTERNAL-FUNCTION-SPEC-HANDLER 
;;;---!!!	FUNCTION-SPEC-HASH-TABLE 
;;;---!!!	COLD-LOAD-FUNCTION-PROPERTY-LISTS
;;;---!!!	FUNCTION-SPEC-PUTPROP 
;;;---!!!	FUNCTION-SPEC-PUSH-PROPERTY 
;;;---!!!	FUNCTION-SPEC-GET 
;;;---!!!	FDEFINE-FILE-PATHNAME 
;;;---!!!	PATCH-SOURCE-FILE-NAMESTRING 
;;;---!!!	FDEFINE-FILE-DEFINITIONS NIL
;;;---!!!	NON-FILE-REDEFINED-FUNCTIONS 
;;;---!!!	RECORD-SOURCE-FILE-NAME 

;;; Default handler called by function-spec-handlers to do functions they don't
;;; handle specially.
(DEFUN FUNCTION-SPEC-DEFAULT-HANDLER (FUNCTION FUNCTION-SPEC &OPTIONAL ARG1 ARG2)
  "This subroutine handles various operations for other function spec handlers."
  (CASE FUNCTION
    (VALIDATE-FUNCTION-SPEC T)	;Used only during system build, via FUNCTION-SPEC-GET
    (FUNCTION-PARENT NIL)		;Default is no embedding in other definitions
    (COMPILER-FDEFINEDP NIL)		;Default is no remembering of compiled definitions
    (DWIMIFY NIL)
    (GET (IF FUNCTION-SPEC-HASH-TABLE
	     ;; Default is to use plist hash table
	     (WITH-STACK-LIST (KEY FUNCTION-SPEC ARG1)
	       (GETHASH KEY FUNCTION-SPEC-HASH-TABLE ARG2))
	   (LOOP FOR (FS IND PROP) IN COLD-LOAD-FUNCTION-PROPERTY-LISTS
		 WHEN (AND (EQUAL FS FUNCTION-SPEC) (EQ IND ARG1))
		 RETURN PROP))
	 ARG2)
    (PUTPROP (LET ((DEFAULT-CONS-AREA BACKGROUND-CONS-AREA)
		   (AREA (%AREA-NUMBER FUNCTION-SPEC)))
	       (IF (OR (AREA-TEMPORARY-P AREA)
		       (= AREA PDL-AREA))
		   (SETQ FUNCTION-SPEC (COPYTREE FUNCTION-SPEC)))
	       (IF FUNCTION-SPEC-HASH-TABLE
		   (SETF (GETHASH (LIST FUNCTION-SPEC ARG2) FUNCTION-SPEC-HASH-TABLE) ARG1)
		 (PUSH (LIST FUNCTION-SPEC ARG2 ARG1) COLD-LOAD-FUNCTION-PROPERTY-LISTS))))
    (PUSH-PROPERTY
     (WITH-STACK-LIST (KEY FUNCTION-SPEC ARG2)
       (PUSH ARG1 (GETHASH KEY FUNCTION-SPEC-HASH-TABLE))))
    (OTHERWISE (FERROR NIL "~S is not implemented by the function spec ~S"
		           FUNCTION FUNCTION-SPEC))))

;;; (:PROPERTY symbol property) refers to (GET symbol property).
;;; This has to be defined with a separate DEFPROP for reasons which should be obvious.
(DEFPROP :PROPERTY PROPERTY-FUNCTION-SPEC-HANDLER FUNCTION-SPEC-HANDLER)
(DEFUN PROPERTY-FUNCTION-SPEC-HANDLER (FUNCTION FUNCTION-SPEC &OPTIONAL ARG1 ARG2)
  (LET ((SYMBOL (SECOND FUNCTION-SPEC))
	(INDICATOR (THIRD FUNCTION-SPEC)))
    (IF (NOT (AND (= (LENGTH FUNCTION-SPEC) 3) (SYMBOLP SYMBOL)))
	(UNLESS (EQ FUNCTION 'VALIDATE-FUNCTION-SPEC)
	  (FERROR 'SYS:INVALID-FUNCTION-SPEC "Invalid function spec ~S." FUNCTION-SPEC))
      (CASE FUNCTION
	(VALIDATE-FUNCTION-SPEC T)
	(FDEFINE (SETF (GET SYMBOL INDICATOR) ARG1))
	((FDEFINITION FDEFINEDP) (GET SYMBOL INDICATOR))
	(FDEFINITION-LOCATION (LOCF (GET SYMBOL INDICATOR)))	;Not perfect, but close
	(FUNDEFINE (REMPROP SYMBOL INDICATOR))
	(DWIMIFY
	 (AND (SYMBOLP INDICATOR)
	      (MULTIPLE-VALUE-BIND (NEW-SYM DWIM-P)
		  (*CATCH 'DWIMIFY-PACKAGE
		    (MAP-OVER-LOOKALIKE-SYMBOLS
		      (SYMBOL-NAME INDICATOR)
		      NIL
		      #'(LAMBDA (NEW-SYMBOL SPEC ORIGINAL-SPEC DWIMIFY-INFO)
			  (OR (EQ NEW-SYMBOL (CADDR SPEC))
			      (DWIMIFY-PACKAGE-2 `(,(CAR SPEC) ,(CADR SPEC) ,NEW-SYMBOL)
						 ORIGINAL-SPEC DWIMIFY-INFO T)))
		      FUNCTION-SPEC ARG1 ARG2))
		(AND DWIM-P NEW-SYM))))
	(OTHERWISE (FUNCTION-SPEC-DEFAULT-HANDLER FUNCTION FUNCTION-SPEC ARG1 ARG2))))))

;;; (:INTERNAL parent-function index) refers to the index'th unnamed
;;; broken-off lambda in the parent function.
;;; parent-function is normally a function-spec, but it may also be a FEF.
;;; Note that VALIDATE-FUNCTION-SPEC for :INTERNAL returns NIL if the
;;; function-spec itself is malformed, however if the spec is well-formed
;;; but the parent doesn't have internal functions, an error is signalled
;;; giving a detailed explanation.
(DEFPROP :INTERNAL INTERNAL-FUNCTION-SPEC-HANDLER FUNCTION-SPEC-HANDLER)
(DEFUN INTERNAL-FUNCTION-SPEC-HANDLER (FUNCTION FUNCTION-SPEC &OPTIONAL ARG1 ARG2)
  (LET ((PARENT (SECOND FUNCTION-SPEC))
	(INDEX (THIRD FUNCTION-SPEC))
	DIRECT-FEF)
    (SETQ DIRECT-FEF (TYPEP PARENT 'COMPILED-FUNCTION))
    (IF (NOT (AND (OR (AND (FIXNUMP INDEX) (NOT (MINUSP INDEX)))
		      (SYMBOLP INDEX))
		  (= (LENGTH FUNCTION-SPEC) 3)))
	(UNLESS (EQ FUNCTION 'VALIDATE-FUNCTION-SPEC)
	  (FERROR 'SYS:INVALID-FUNCTION-SPEC
		  "The function spec ~S is invalid." FUNCTION-SPEC))
      (IF (EQ FUNCTION 'VALIDATE-FUNCTION-SPEC)
	  (OR DIRECT-FEF
	      (AND (VALIDATE-FUNCTION-SPEC PARENT) (FDEFINEDP PARENT)))
	(LET ((FEF (IF DIRECT-FEF PARENT
		     (FDEFINITION (UNENCAPSULATE-FUNCTION-SPEC PARENT))))
	      TABLE OFFSET LOCAL-FUNCTION-MAP DEBUGGING-INFO)
	  (WHEN (EQ (CAR-SAFE FEF) 'MACRO)
	    (SETQ FEF (CDR FEF)))
	  (UNLESS (TYPEP FEF 'COMPILED-FUNCTION)
	    (FERROR 'SYS:INVALID-FUNCTION-SPEC
		    "The function spec ~S refers to ~S, which is not a FEF"
		    FUNCTION-SPEC FEF))
	  (SETQ DEBUGGING-INFO (DEBUGGING-INFO FEF)
		TABLE (CDR (ASSQ :INTERNAL-FEF-OFFSETS DEBUGGING-INFO))
		LOCAL-FUNCTION-MAP (CADR (ASSQ 'COMPILER::LOCAL-FUNCTION-MAP DEBUGGING-INFO)))
	  (UNLESS TABLE
	    (FERROR 'SYS:INVALID-FUNCTION-SPEC
		    "The function spec ~S refers to ~S, which has no internal functions"
		    FUNCTION-SPEC FEF))
	  (WHEN (SYMBOLP INDEX)
	    (UNLESS (MEMQ INDEX LOCAL-FUNCTION-MAP)
	      (FERROR 'SYS:INVALID-FUNCTION-SPEC
		      "The function spec ~S refers to a non-existent internal function"
		      FUNCTION-SPEC))
	    (SETQ INDEX (POSITION INDEX LOCAL-FUNCTION-MAP)))		
	  (UNLESS (SETQ OFFSET (NTH INDEX TABLE))
	    (FERROR 'SYS:INVALID-FUNCTION-SPEC
		    "The function spec ~S is out of range" FUNCTION-SPEC))
	  
	  ;; Function spec fully parsed, we can now earn our living
	  (CASE FUNCTION
	    (VALIDATE-FUNCTION-SPEC T)
	    (FDEFINE (LET ((%INHIBIT-READ-ONLY T))
		       (%P-STORE-CONTENTS-OFFSET ARG1 FEF OFFSET)))
	    (FDEFINITION (%P-CONTENTS-OFFSET FEF OFFSET))
	    (FDEFINEDP		;Random: look for what the compiler puts there initially
	     (NOT (EQUAL (%P-CONTENTS-OFFSET FEF OFFSET) FUNCTION-SPEC)))
	    (FDEFINITION-LOCATION (%MAKE-POINTER-OFFSET DTP-LOCATIVE FEF OFFSET))
	    (FUNCTION-PARENT (VALUES PARENT 'DEFUN))
	    (OTHERWISE (FUNCTION-SPEC-DEFAULT-HANDLER FUNCTION FUNCTION-SPEC ARG1 ARG2))))))))

;;; This is setup by QLD as soon as everything it will need is loaded in and pathnames work
;;; and so on.
(DEFVAR FUNCTION-SPEC-HASH-TABLE NIL)
;;; In the meantime, and from the cold load, this remembers non symbol source files,
;;; elements are (function-spec indicator value).
(DEFVAR COLD-LOAD-FUNCTION-PROPERTY-LISTS)

(DEFUN FUNCTION-SPEC-PUTPROP (FUNCTION-SPEC VALUE PROPERTY)
  "Put a PROPERTY property with value VALUE on FUNCTION-SPEC.
For symbols, this is just PUTPROP, but it works on any function spec."
  (IF (SYMBOLP FUNCTION-SPEC)
      (SETF (GET FUNCTION-SPEC PROPERTY) VALUE)
    (LET ((HFUN
	    (IF (NULL FUNCTION-SPEC-HASH-TABLE)
		;; While loading files with MINI during system build,
		;; always use the default handler,
		;; which stores on COLD-LOAD-FUNCTION-PROPERTY-LISTS.
		;; This is so that the property's pathnames will be canonicalized later.
		'FUNCTION-SPEC-DEFAULT-HANDLER
	      (AND (CONSP FUNCTION-SPEC)
		   (SYMBOLP (CAR FUNCTION-SPEC))
		   (GET (CAR FUNCTION-SPEC) 'FUNCTION-SPEC-HANDLER)))))
      (IF HFUN
	  (FUNCALL HFUN 'PUTPROP FUNCTION-SPEC VALUE PROPERTY)
	(FERROR 'SYS:INVALID-FUNCTION-SPEC "The function spec ~S is invalid."
		FUNCTION-SPEC)))))

(DEFUN FUNCTION-SPEC-PUSH-PROPERTY (FUNCTION-SPEC VALUE PROPERTY)
  "PUSH VALUE onto the PROPERTY property of FUNCTION-SPEC.
Like (PUSH VALUE (FUNCTION-SPEC-GET FUNCTION-SPEC PROPERTY)) but faster."
  (IF (SYMBOLP FUNCTION-SPEC)
      (SETF (GET FUNCTION-SPEC PROPERTY) (CONS VALUE (GET FUNCTION-SPEC PROPERTY)))
    (LET ((HFUN
	    (IF (NULL FUNCTION-SPEC-HASH-TABLE)
		;; While loading files with MINI during system build,
		;; always use the default handler,
		;; which stores on COLD-LOAD-FUNCTION-PROPERTY-LISTS.
		;; This is so that the property's pathnames will be canonicalized later.
		'FUNCTION-SPEC-DEFAULT-HANDLER
	      (AND (CONSP FUNCTION-SPEC)
		   (SYMBOLP (CAR FUNCTION-SPEC))
		   (GET (CAR FUNCTION-SPEC) 'FUNCTION-SPEC-HANDLER)))))
      (IF HFUN
	  (FUNCALL HFUN 'PUSH-PROPERTY FUNCTION-SPEC VALUE PROPERTY)
	(FERROR 'SYS:INVALID-FUNCTION-SPEC "The function spec ~S is invalid."
		FUNCTION-SPEC)))))

(DEFUN FUNCTION-SPEC-GET (FUNCTION-SPEC PROPERTY &OPTIONAL DEFAULT)
  "Get the PROPERTY property of FUNCTION-SPEC.
For symbols, this is just GET, but it works on any function spec."
  (IF (SYMBOLP FUNCTION-SPEC)
      (GET FUNCTION-SPEC PROPERTY DEFAULT)
    ;; Look for a handler for this type of function spec.
    (LET ((HFUN
	    (IF (NULL FUNCTION-SPEC-HASH-TABLE)
		;; While loading files with MINI during system build,
		;; always use the default handler,
		;; which stores on COLD-LOAD-FUNCTION-PROPERTY-LISTS.
		;; This is so that the property's pathnames will be canonicalized later.
		'FUNCTION-SPEC-DEFAULT-HANDLER
	      (AND (CONSP FUNCTION-SPEC)
		   (SYMBOLP (CAR FUNCTION-SPEC))
		   (GET (CAR FUNCTION-SPEC) 'FUNCTION-SPEC-HANDLER)))))
      (IF HFUN
	  (AND (FUNCALL HFUN 'VALIDATE-FUNCTION-SPEC FUNCTION-SPEC)
	       ;;previous line avoids lossage when compiling defselects which aren't present
	       ;; in run time environment (yet), for example.		
	       (FUNCALL HFUN 'GET FUNCTION-SPEC PROPERTY DEFAULT))
	(FERROR 'SYS:INVALID-FUNCTION-SPEC "The function spec ~S is invalid."
		FUNCTION-SPEC)))))


(SETQ FS:THIS-IS-A-PATCH-FILE NIL)	;For the cold load

(DEFVAR FDEFINE-FILE-PATHNAME NIL
  "Generic pathname of source file being loaded or evaluated, or NIL.")

(DEFVAR PATCH-SOURCE-FILE-NAMESTRING NIL
  "While loading a patch, holds namestring of generic pathname of the source of the patch.")

;;; If the above is not NIL, this variable accumulates a list of all function specs defined.
(DEFVAR FDEFINE-FILE-DEFINITIONS NIL
  "List of definitions made while loading this source file.")

(DEFVAR NON-FILE-REDEFINED-FUNCTIONS NIL
  "Functions from files redefined from the keyboard and confirmed by the user.")

;;; A :SOURCE-FILE-NAME property is a single pathname for DEFUN of a single file,
;;; or ((type . files) (type . files) ...).
;;; Value returned indicates whether to go ahead with the definition.
(DEFUN RECORD-SOURCE-FILE-NAME (FUNCTION-SPEC
				&OPTIONAL (TYPE 'DEFUN)
					  (NO-QUERY (EQ INHIBIT-FDEFINE-WARNINGS T))
				&AUX (DEFAULT-CONS-AREA BACKGROUND-CONS-AREA))
  "Record a definition of FUNCTION-SPEC, of type TYPE, in the current source file.
The source file's generic-pathname is found in FDEFINE-FILE-PATHNAME.
FUNCTION-SPEC is actually only a function spec if TYPE is 'DEFUN,
which is the default.  If TYPE is 'DEFVAR, the first arg is a variable name, etc.
NO-QUERY inhibits warnings about redefinition in a different file.

The value is T if you should go ahead and perform the definition,
NIL if the user was asked and said no."
  ;; When defining a function in a patch, record it as coming
  ;; from its real source file.  So the editor knows where to find it.
  (IF (AND FS:THIS-IS-A-PATCH-FILE PATCH-SOURCE-FILE-NAMESTRING)
      (LET* ((FDEFINE-FILE-DEFINITIONS NIL)
	     (FDEFINE-FILE-PATHNAME
	       (SEND (FS:PARSE-PATHNAME PATCH-SOURCE-FILE-NAMESTRING) :GENERIC-PATHNAME))
	     (PATCH-SOURCE-FILE-NAMESTRING NIL)
	     (PKG-SPEC (SEND FDEFINE-FILE-PATHNAME :GET :PACKAGE))
	     (*PACKAGE* (OR (PKG-FIND-PACKAGE PKG-SPEC :FIND) *PACKAGE*)))
	;; Record the source file as having defined this function.
	;; THIS-IS-A-PATCH-FILE is still set, to prevent querying,
	;; but PATCH-SOURCE-FILE-NAMESTRING is not, so we don't recurse forever.
	(RECORD-SOURCE-FILE-NAME FUNCTION-SPEC TYPE NO-QUERY)
	;; Add the function to the source's list of definitions.
	(RECORD-FILE-DEFINITIONS FDEFINE-FILE-PATHNAME FDEFINE-FILE-DEFINITIONS
				 NIL FDEFINE-FILE-PATHNAME)))
  (LET ((PATHNAME FDEFINE-FILE-PATHNAME)
	(DEF (CONS-IN-AREA FUNCTION-SPEC TYPE BACKGROUND-CONS-AREA))
	(PROPERTY (FUNCTION-SPEC-GET FUNCTION-SPEC :SOURCE-FILE-NAME)))
    (OR (NULL FDEFINE-FILE-PATHNAME)
	(MEMBER DEF FDEFINE-FILE-DEFINITIONS)
	(SETQ FDEFINE-FILE-DEFINITIONS
	      (CONS-IN-AREA DEF FDEFINE-FILE-DEFINITIONS BACKGROUND-CONS-AREA)))
    (COND ((AND (NULL PROPERTY)			;Check most common case first
		(EQ TYPE 'DEFUN))
	   ;; We don't record the keyboard as a "source file"
	   ;; so things like the editor don't get confused.
	   (IF FDEFINE-FILE-PATHNAME
	       (FUNCTION-SPEC-PUTPROP FUNCTION-SPEC PATHNAME :SOURCE-FILE-NAME))
	   T)
	  ((IF (ATOM PROPERTY)
	       (AND (EQ TYPE 'DEFUN) (EQ PATHNAME PROPERTY))
	     (EQ PATHNAME (CADR (ASSQ TYPE PROPERTY))))
	   T)					;This pathname already known
	  (T
	   (AND PROPERTY (ATOM PROPERTY)
		(SETQ PROPERTY `((DEFUN ,PROPERTY))))
	   (LET ((THIS-TYPE (ASSQ TYPE PROPERTY))
		 (OLD-FILE))
	     (COND ((COND ((NULL THIS-TYPE)
			   (IF FDEFINE-FILE-PATHNAME
			       (SETQ THIS-TYPE `(,TYPE)
				     PROPERTY (NCONC PROPERTY
						     (NCONS THIS-TYPE))))
			   T)
			  (NO-QUERY T)
			  (FS:THIS-IS-A-PATCH-FILE T)
			  ((AND (NOT FDEFINE-FILE-PATHNAME)
				(MEMBER FUNCTION-SPEC NON-FILE-REDEFINED-FUNCTIONS))
			   ;; If user has ever confirmed redefining this fn from the kbd,
			   ;; it is ok to do so again.
			   T)
			  ;; Before format is loaded, don't bomb out trying to query.
			  ((NOT (FBOUNDP 'FQUERY)) T)
			  ;; If all the old definitions are from patch files, don't query.
			  ((NULL (SETQ OLD-FILE
				       (LOOP FOR FILE IN (CDR THIS-TYPE)
					     UNLESS (OR (STRINGP FILE)	;During QLD
							(SEND FILE :GET :PATCH-FILE))
					     RETURN FILE)))
			   T)
			  ((QUERY-ABOUT-REDEFINITION FUNCTION-SPEC PATHNAME TYPE
						     OLD-FILE)
			   ;; Though we don't record the keyboard as a "source file",
			   ;; once the user confirms redefining a certain function
			   ;; from the keyboard, we don't ever ask about it again.
			   (UNLESS FDEFINE-FILE-PATHNAME
			     (PUSH FUNCTION-SPEC NON-FILE-REDEFINED-FUNCTIONS))
			   T))
		    ;; We don't record the keyboard as a "source file"
		    ;; so things like the editor don't get confused.
		    (WHEN FDEFINE-FILE-PATHNAME
		      (SETF (CDR THIS-TYPE)
			    (CONS PATHNAME (DELQ PATHNAME (CDR THIS-TYPE))))
		      (FUNCTION-SPEC-PUTPROP FUNCTION-SPEC PROPERTY :SOURCE-FILE-NAME))
		    T)
		   (T NIL)))))))

(DEFUN MAPATOMS-NR-SYM (FUNCTION)
  "Call FUNCTION on every symbol in the world, regardless of packages."
  (FUNCALL FUNCTION NIL)			;these two are stored elsewhere
  (FUNCALL FUNCTION T)
  (DO ((REGION (AREA-REGION-LIST NR-SYM) (REGION-LIST-THREAD REGION)))
      ((MINUSP REGION))
    (DO ((SYM (%MAKE-POINTER DTP-SYMBOL (REGION-ORIGIN REGION))
	      (%MAKE-POINTER-OFFSET DTP-SYMBOL SYM LENGTH-OF-ATOM-HEAD))
         (CT (TRUNCATE (REGION-FREE-POINTER REGION) LENGTH-OF-ATOM-HEAD) (1- CT)))
        ((ZEROP CT))
      (FUNCALL FUNCTION SYM)))
  (WHEN (BOUNDP 'WORTHLESS-SYMBOL-AREA)
    (DO ((REGION (AREA-REGION-LIST WORTHLESS-SYMBOL-AREA) (REGION-LIST-THREAD REGION)))
	((MINUSP REGION))
      (DO ((SYM (%MAKE-POINTER DTP-SYMBOL (REGION-ORIGIN REGION))
		(%MAKE-POINTER-OFFSET DTP-SYMBOL SYM LENGTH-OF-ATOM-HEAD))
	   (CT (TRUNCATE (REGION-FREE-POINTER REGION) LENGTH-OF-ATOM-HEAD) (1- CT)))
	  ((ZEROP CT))
	(FUNCALL FUNCTION SYM)))))

(DEFUN FOLLOW-STRUCTURE-FORWARDING (X)
  "Get the final structure this one may be forwarded to.
Given a pointer to a structure, if it has been forwarded by STRUCTURE-FORWARD,
ADJUST-ARRAY-SIZE, or the like, this will return the target structure,
following any number of levels of forwarding."
  (WITHOUT-INTERRUPTS
    (COND ((= (%P-DATA-TYPE X) DTP-HEADER-FORWARD)
	   (FOLLOW-STRUCTURE-FORWARDING
	     (%MAKE-POINTER (%DATA-TYPE X) (%P-CONTENTS-AS-LOCATIVE X))))
	  ((= (%P-DATA-TYPE X) DTP-BODY-FORWARD)
	   (LET ((HDRP (%P-CONTENTS-AS-LOCATIVE X)))
	     (FOLLOW-STRUCTURE-FORWARDING
	       (%MAKE-POINTER-OFFSET (%DATA-TYPE X)
				     (%P-CONTENTS-AS-LOCATIVE HDRP)
				     (%POINTER-DIFFERENCE X HDRP)))))
	  (T X))))

;;; This is defined here since macros can be defined before the editor is loaded
;;; In fact even before DEFMACRO is loaded
(DEFVAR ZWEI:*INITIAL-LISP-INDENT-OFFSET-ALIST* NIL)
(PROCLAIM '(SPECIAL ZWEI:*LISP-INDENT-OFFSET-ALIST*))

(DEFUN DEFMACRO-SET-INDENTATION-FOR-ZWEI (NAME NUMBER)
  (LET ((VARIABLE (IF (BOUNDP 'ZWEI:*LISP-INDENT-OFFSET-ALIST*)
		      'ZWEI:*LISP-INDENT-OFFSET-ALIST*
		      'ZWEI:*INITIAL-LISP-INDENT-OFFSET-ALIST*)))
    (LET ((X (ASSQ NAME (SYMBOL-VALUE VARIABLE))))
      (IF (NULL X)
	  (PUSH (LIST NAME NUMBER 1) (SYMBOL-VALUE VARIABLE))
	(SETF (CDR X) (LIST NUMBER 1))))))

(DEFUN DEFMACRO-COPY-INDENTATION-FOR-ZWEI (NAME NAME1)
  (LET ((VARIABLE (IF (BOUNDP 'ZWEI:*LISP-INDENT-OFFSET-ALIST*)
		      'ZWEI:*LISP-INDENT-OFFSET-ALIST*
		      'ZWEI:*INITIAL-LISP-INDENT-OFFSET-ALIST*)))
    (LET ((X (ASSQ NAME (SYMBOL-VALUE VARIABLE)))
	  (Y (ASSQ NAME1 (SYMBOL-VALUE VARIABLE))))
      (IF Y
	  (IF (NULL X)
	      (PUSH (CONS NAME (CDR Y)) (SYMBOL-VALUE VARIABLE))
	    (SETF (CDR X) (CDR Y)))))))
  
;;; Allow functions to be made obsolete wherever their definitions may be.
(DEFMACRO MAKE-OBSOLETE (FUNCTION REASON)
  "Mark FUNCTION as obsolete, with string REASON as the reason.
REASON should be a clause starting with a non-capitalized word.
Uses of FUNCTION will draw warnings from the compiler."
  `(PROGN (PUTPROP ',FUNCTION 'COMPILER::OBSOLETE 'COMPILER::STYLE-CHECKER)
	  (PUTPROP ',FUNCTION (STRING-APPEND "is an obsolete function; " ,REASON)
		   'COMPILER:OBSOLETE)))

;;; SETF of DOCUMENTATION expands into this.
(DEFUN SET-DOCUMENTATION (SYMBOL DOC-TYPE VALUE)
  (LET* ((S (SYMBOL-NAME DOC-TYPE))
	 (C (ASSOC-EQUAL S (GET SYMBOL 'DOCUMENTATION-PROPERTY))))
    (IF C
	(SETF (CDR C) VALUE)
      (PUSH (CONS S VALUE) (GET SYMBOL 'DOCUMENTATION-PROPERTY))))
  VALUE)

;;; These definitions work because the compiler open codes FLOOR, CEILING, TRUNCATE and ROUND.

(defun floor (dividend &optional (divisor 1))
  "Return DIVIDEND divided by DIVISOR, rounded down, and the remainder."
  (declare (values quotient remainder))
  (floor dividend divisor))

(defun ceiling (dividend &optional (divisor 1))
  "Return DIVIDEND divided by DIVISOR, rounded up, and the remainder."
  (declare (values quotient remainder))
  (ceiling dividend divisor))

;(eval-when (eval load)
;(defsubst ceil (dividend &optional (divisor 1))
;  "Return DIVIDEND divided by DIVISOR, rounded up, and the remainder."
;  (declare (values quotient remainder)
;	   (def ceiling))
;  (ceiling dividend divisor)))
;(make-obsolete ceil "the new name is CEILING.")

(defun truncate (dividend &optional (divisor 1))
  "Return DIVIDEND divided by DIVISOR, rounded toward zero, and the remainder."
  (declare (values quotient remainder))
  (truncate dividend divisor))

;(eval-when (eval load)
;(defsubst trunc (dividend &optional (divisor 1))
;  "Return DIVIDEND divided by DIVISOR, rounded toward zero, and the remainder."
;  (declare (values quotient remainder)
;	   (def truncate))
;  (truncate dividend divisor)))
;(make-obsolete trunc "the new name is TRUNCATE.")

(defun round (dividend &optional (divisor 1))
  "Return DIVIDEND divided by DIVISOR, rounded to nearest integer, and the remainder."
  (declare (values quotient remainder))
  (round dividend divisor))

