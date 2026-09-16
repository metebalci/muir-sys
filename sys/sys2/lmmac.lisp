;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:8; Readtable:ZL -*-
;;; These are the macros in the Lisp Machine system.

;	** (c) Copyright 1980 Massachusetts Institute of Technology **

(DEFPROP MACRO-TYPE-CHECK-WARNING T :ERROR-REPORTER)
(DEFUN MACRO-TYPE-CHECK-WARNING (MACRO OBJECT)
  "Detect attempts by macros to check type at compile time of an eval-at-load-time.
A macro should call this function with OBJECT being the subexpression whose
type is to be checked and MACRO being the macro name.  If OBJECT is an
eval-at-load-time, an error happens."
  (IF (EQ (CAR-SAFE OBJECT) COMPILER::EVAL-AT-LOAD-TIME-MARKER)
      (FERROR NIL "The macro ~S is attempting to check the type of an argument
at compile time, but the argument is #,~S,
whose type is not known until load time"
	      MACRO (CDR OBJECT))))

;;;; Macros which look at the processor type at run time.

(DEFPROP :CADR #.CADR-TYPE-CODE PROCESSOR-TYPE-CODE)
(DEFPROP :LAMBDA #.LAMBDA-TYPE-CODE PROCESSOR-TYPE-CODE)
(DEFPROP :EXPLORER #.EXPLORER-TYPE-CODE PROCESSOR-TYPE-CODE)

(DEFMACRO SELECT-PROCESSOR (&REST CLAUSES)
  "CLAUSES begin with :CADR, :LAMBDA or :EXPLORER (ugh!)"
  `(CASE PROCESSOR-TYPE-CODE
     ,@(MAPCAR #'(LAMBDA (CLAUSE)
		   (IF (MEMQ (CAR CLAUSE) '(T OTHERWISE))
		       CLAUSE
		     (CONS (MAPCAR #'(LAMBDA (X)
				       (OR (GET X 'PROCESSOR-TYPE-CODE)
					   (FERROR NIL "~S is an unknown processor-type" X)))
				   (IF (CLI:LISTP (CAR CLAUSE))
				       (CAR CLAUSE) (LIST (CAR CLAUSE))))
			   (CDR CLAUSE))))
	       CLAUSES)))

(DEFMACRO IF-IN-CADR (&BODY FORMS)
  "Uses FORMS only if running or compiling on a CADR."
  `(WHEN (EQ PROCESSOR-TYPE-CODE #.CADR-TYPE-CODE)
    ,@FORMS))

(DEFMACRO IF-IN-LAMBDA (&BODY FORMS)
  "Uses FORMS only if running or compiling on a Lambda machine."
  `(WHEN (EQ PROCESSOR-TYPE-CODE #.LAMBDA-TYPE-CODE)
    ,@FORMS))

(DEFMACRO IF-IN-CADR-ELSE-LAMBDA (CADR-FORM &BODY LAMBDA-FORMS)
  "Uses CADR-FORM if running or compiling on a CADR.  Otherwise uses LAMBDA-FORMS."
  `(IF (EQ PROCESSOR-TYPE-CODE #.CADR-TYPE-CODE)
      ,CADR-FORM
    ,@LAMBDA-FORMS))
(compiler:make-obsolete if-in-cadr-else-lambda "use SI:SELECT-PROCESSOR")
(DEFMACRO IF-IN-LAMBDA-ELSE-CADR (LAMBDA-FORM &BODY CADR-FORMS)
  "Uses LAMBDA-FORM if running or compiling on a LAMBDA.  Otherwise uses CADR-FORMS."
  `(IF (EQ PROCESSOR-TYPE-CODE #.LAMBDA-TYPE-CODE)
       ,LAMBDA-FORM
     ,@CADR-FORMS))
(compiler:make-obsolete if-in-lambda-else-cadr "use SI:SELECT-PROCESSOR")

;;; The IF-IN-MACLISP/IF-IN-LISPM conditionals have to do with not breaking
;;; the Maclisp environment when compiling.  The optimizers in COMPAT take
;;; over these functions when compiling in Maclisp.

(DEFMACRO IF-IN-MACLISP (&BODY FORMS)
  "Use FORMS only if running or compiling in Maclisp.  No-op on the Lisp machine."
  FORMS
  NIL)
(compiler:make-obsolete if-in-maclisp "use the #+MACLISP reader macro")

(DEFMACRO IF-IN-LISPM (&BODY FORMS)
  "Use FORMS only if running or compiling on the Lisp machine."
  `(PROGN . ,FORMS))
(compiler:make-obsolete if-in-maclisp "use the #+LISPM reader macro")

(DEFMACRO IF-FOR-MACLISP (&BODY FORMS)
  "Use FORMS only if evaluating on or compiling FOR Maclisp.
Nowadays this is the same as IF-IN-MACLISP since there is no longer
a cross-compiler in Maclisp for the Lisp machine."
  FORMS
  NIL)
(compiler:make-obsolete if-for-maclisp "use the #+MACLISP reader macro")

(DEFMACRO IF-FOR-LISPM (&BODY FORMS)
  "Use FORMS only if evaluating on or compiling FOR the Lisp machine.
Nowadays this is the same as IF-IN-LISPM since there is no longer
a cross-compiler in Maclisp for the Lisp machine."
  `(COMPILER-LET ((RUN-IN-MACLISP-SWITCH NIL))
     (PROGN . ,FORMS)))
(compiler:make-obsolete if-for-lispm "use the #+LISPM reader macro")

(DEFMACRO IF-FOR-MACLISP-ELSE-LISPM (MACLISP-FORM LISPM-FORM)
  "Use MACLISP-FORM only if in Maclisp, use LISPM-FORM if on the Lisp machine."
  MACLISP-FORM
  `(COMPILER-LET ((RUN-IN-MACLISP-SWITCH NIL))
     ,LISPM-FORM))
(compiler:make-obsolete if-for-maclisp-else-lispm "use the #+LISPM//#+MACLISP reader macro")


;; sigh
(DEFMACRO SEND (OBJECT OPERATION &REST ARGUMENTS)
  "Send a message to OBJECT, with operation OPERATION and ARGUMENTS."
  `(FUNCALL ,OBJECT ,OPERATION . ,ARGUMENTS))

;; sigh^2
;;>> this is a macro to get around fuxking bd in the sublis-eval-once crock.
;;>>  I want lunar language tools!!
(DEFMACRO LEXPR-SEND (OBJECT OPERATION &REST ARGS)
  "Send a message to OBJECT, with operation OPERATION and ARGUMENTS.
The last one of ARGUMENTS actually is a list of arguments, not one argument."
  `(APPLY ,OBJECT ,OPERATION . ,ARGS))

(DEFSUBST SEND-IF-HANDLES (OBJECT OPERATION &REST ARGUMENTS)
  "Send the message OPERATION to OBJECT if OBJECT handles that message.
If it does, return the result of sending it that message on the given ARGUMENTS.
Otherwise, return NIL."
  (LEXPR-SEND OBJECT :SEND-IF-HANDLES OPERATION ARGUMENTS))

(DEFSUBST LEXPR-SEND-IF-HANDLES (OBJECT OPERATION &REST ARGUMENTS)
  "Send the message OPERATION to OBJECT if OBJECT handles that message.
If it does, return the result of sending it that message on the given ARGUMENTS.
Otherwise, return NIL."
  (LEXPR-SEND #'LEXPR-SEND OBJECT :SEND-IF-HANDLES OPERATION ARGUMENTS))

(DEFSUBST OPERATION-HANDLED-P (OBJECT &REST OPERATION)
  "Non-NIL if OBJECT has a method defined for OPERATION."
  (LEXPR-SEND OBJECT :OPERATION-HANDLED-P OPERATION))


(DEFMACRO GETF (PLACE PROPERTY &OPTIONAL (DEFAULT NIL))
  "Returns the PROPERTY property from the plist stored in PLACE.
If there is no such property, DEFAULT is returned.
PLACE should be such that simply evaluating it would return
the contents of the property list."
  `(GET (LOCF ,PLACE) ,PROPERTY ,DEFAULT))

(DEFMACRO GET-PROPERTIES (PLACE LIST-OF-PROPERTIES)
  "Finds the first property of any in LIST-OF-PROPERTIES from the plist PLACE.
The first value is the property found first,
the second is the value of that property,
the third is the tail of the plist, whose car is the property
and whose cadr is the value.
PLACE should be such that simply evaluating it would return
the contents of the property list."
  `(GET-PROPERTIES-INTERNAL (LOCF ,PLACE) ,LIST-OF-PROPERTIES))

(DEFMACRO REMF (PLACE PROPERTY)
  "Removes the PROPERTY property from the plist stored in PLACE.
PLACE should be such that simply evaluating it would return
the contents of the property list."
  `(REMPROP (LOCF ,PLACE) ,PROPERTY))

(DEFMACRO DEFSUBST-WITH-PARENT (FUNCTION-SPEC PARENT LAMBDA-LIST . BODY)
  "Like DEFSUBST but says that the parent of FUNCTION-SPEC is PARENT.
This is for DEFSUBSTs generated by macros, as in DEFSTRUCT.
This tells the editor to find FUNCTION-SPEC's definition in PARENT's definition.
PARENT is either a symbol, or a list of a function spec and a definition type."
  (UNLESS (CONSP PARENT) (SETQ PARENT (LIST PARENT)))
  `(DEFSUBST ,FUNCTION-SPEC ,LAMBDA-LIST
     (DECLARE (FUNCTION-PARENT . , PARENT))
     . ,BODY))


;;;; Macros in Lambda position of function

(DEFMACRO LAMBDA-MACRO (LAMBDA-MACRO-NAME LAMBDA-LIST . BODY)
  (LET ((DEF1 `(NAMED-LAMBDA ,LAMBDA-MACRO-NAME ,LAMBDA-LIST . ,BODY)))
    `(PROGN (EVAL-WHEN (COMPILE)
		       (PUTDECL ',LAMBDA-MACRO-NAME 'LAMBDA-MACRO ',DEF1))
	    (DEFUN (:LAMBDA-MACRO ,LAMBDA-MACRO-NAME) . ,(CDDR DEF1)))))

(LAMBDA-MACRO DISPLACED (FCTN) ; moved from qfctns because it doesn't work in cold load.
  (CADDR FCTN))

(DEFMACRO DEFFUNCTION (FUNCTION-SPEC LAMBDA-TYPE LAMBDA-LIST &BODY REST)
  "Define FUNCTION-SPEC as a function, like DEFUN, but use LAMDBA-TYPE instead of 'LAMBDA.
With this you can define a function with a definition that uses a lambda macro.
The lambda macro is expanded and should yield a LAMBDA, SUBST or MACRO;
then this macro expands into a suitable use of DEFUN, DEFSUBST or MACRO."
  (LET ((FUNCTION (LAMBDA-MACRO-EXPAND `(,LAMBDA-TYPE ,LAMBDA-LIST . ,REST))))
    `(,(CASE (CAR FUNCTION)
	 ((LAMBDA NAMED-LAMBDA) 'DEFUN)
	 ((SUBST NAMED-SUBST CLI:SUBST) 'DEFSUBST)
	 (MACRO 'MACRO)
	 (T (FERROR NIL "~A (a lambda macro) did not expand into a suitable function"
		    LAMBDA-TYPE)))
      ,FUNCTION-SPEC
      . ,(CASE (CAR FUNCTION)
	   ((LAMBDA SUBST CLI:SUBST)
	    (CDR FUNCTION))
	   ((NAMED-LAMBDA NAMED-SUBST)
	    (CDDR FUNCTION))
	   (MACRO (CDDR FUNCTION))))))

(DEFMACRO DEFDECL (NAME PROP VALUE)
  "Declare that the PROP property of NAME is VALUE, for GETDECL.
When executed, this makes a property, like DEFPROP.
In file compilation, this makes a declaration, so that GETDECL
done in macros being expanded will see this property."
  `(PROGN
     (EVAL-WHEN (EVAL LOAD)
       (PUTPROP ',NAME ',VALUE ',PROP))
     (EVAL-WHEN (COMPILE)
       (PUTDECL ',NAME ',PROP ',VALUE))))

(DEFMACRO @DEFINE (&REST IGNORE) NIL)


(DEFSUBST FILL-POINTER (ARRAY)
  "Return the fill pointer of ARRAY."
  (ARRAY-LEADER ARRAY 0))

(DEFSUBST CAAR-SAFE (OBJECT)
  "Like CAAR, but treats all non-lists as NIL rather than getting an error."
  (CAR-SAFE (CAR-SAFE OBJECT)))

(DEFSUBST CDAR-SAFE (OBJECT)
  "Like CDAR, but treats all non-lists as NIL rather than getting an error."
  (CDR-SAFE (CAR-SAFE OBJECT)))

(DEFSUBST CADDR-SAFE (OBJECT)
  "Like CADDR, but treats all non-lists as NIL rather than getting an error."
  (CAR-SAFE (CDDR-SAFE OBJECT)))

(DEFSUBST CADDDR-SAFE (OBJECT)
  "Like CADDDR, but treats all non-lists as NIL rather than getting an error."
  (CADR-SAFE (CDDR-SAFE OBJECT)))

(DEFSUBST CDDDR-SAFE (OBJECT)
  "Like CDDDR, but treats all non-lists as NIL rather than getting an error."
  (CDR-SAFE (CDDR-SAFE OBJECT)))

(DEFSUBST FIRST (LIST)
  "Return the first element of LIST."
  (CAR LIST))

(DEFSUBST SECOND (LIST)
  "Return the second element of LIST."
  (CADR LIST))

(DEFSUBST THIRD (LIST)
  "Return the third element of LIST."
  (CADDR LIST))

(DEFSUBST FOURTH (LIST)
  "Return the fourth element of LIST."
  (CADDDR LIST))

(DEFSUBST FIFTH (LIST)
  "Return the fifth element of LIST."
  (CAR (CDDDDR LIST)))

(DEFSUBST SIXTH (LIST)
  "Return the sixth element of LIST."
  (CADR (CDDDDR LIST)))

(DEFSUBST SEVENTH (LIST)
  "Return the seventh element of LIST."
  (CADDR (CDDDDR LIST)))

(DEFSUBST EIGHTH (LIST)
  "Return the eighth element of LIST."
  (CADDDR (CDDDDR LIST)))

(DEFSUBST NINTH (LIST)
  "Return the ninth element of LIST."
  (CADDR (CDDR (CDDDDR LIST))))

(DEFSUBST TENTH (LIST)
  "Return the tenth element of LIST."
  (CADDR (CDDDR (CDDDDR LIST))))

(DEFSUBST REST (LIST)
  "Return LIST sans its first element."
  (CDR LIST))

(DEFSUBST REST1 (LIST)
  "Return LIST sans its first element."
  (CDR LIST))

(DEFSUBST REST2 (LIST)
  "Return LIST sans its first two elements."
  (CDDR LIST))

(DEFSUBST REST3 (LIST)
  "Return LIST sans its first three elements."
  (CDDDR LIST))

(DEFSUBST REST4 (LIST)
  "Return LIST sans its first four elements."
  (CDDDDR LIST))

(DEFSUBST CONTENTS (LOCATIVE)
  "Return the contents of the cell LOCATIVE points to.
/(CONTENTS (LOCF <expression>)) is equivalent to <expression>."
  (CDR LOCATIVE))

;; Brand S incompatibility. Sigh. Only took them 3 years to add this.
(DEFF LOCATION-CONTENTS 'CONTENTS)

(DEFSUBST CONSP (OBJECT)
  "T if OBJECT is a cons (a non-null list)."
  (NOT (ATOM OBJECT)))

(DEFSUBST HASH-TABLE-P (OBJECT)
  "T if OBJECT is a hash table."
  (TYPEP OBJECT 'HASH-TABLE))

(DEFSUBST CLI:LISTP (OBJECT)
  "T if OBJECT is a list (either a cons or NIL)."
  (COMMON-LISP-LISTP OBJECT))

(DEFSUBST CLI:NLISTP (OBJECT)
  "T if OBJECT is not a list (neither a cons nor NIL)."
  (NOT (COMMON-LISP-LISTP OBJECT)))

(DEFSUBST CLI:AREF (ARRAY &REST INDICES)
  "Access an element of ARRAY according to INDICES."
  (APPLY #'COMMON-LISP-AREF ARRAY INDICES))

(DEFSUBST CLI:AR-1 (ARRAY INDEX)
  "Access an element of ARRAY, an array of rank 1, according to INDEX."
  (COMMON-LISP-AR-1 ARRAY INDEX))

(DEFSUBST CLI:AR-1-FORCE (ARRAY INDEX)
  "Access an element of ARRAY, indexing it by INDEX as if it were one dimensional."
  (COMMON-LISP-AR-1-FORCE ARRAY INDEX))

;; brand s compatibility
(DEFF SYS:%1D-AREF 'GLOBAL:AR-1-FORCE)
(DEFF SYS:%1D-ASET 'AS-1-FORCE)
(DEFF SYS:%1D-ALOC 'AP-1-FORCE)

(DEFSUBST FIXP (OBJECT)
  "T if OBJECT is an integer; NIL for other numbers and non-numbers."
  (INTEGERP OBJECT))

(DEFSUBST CLOSUREP (X)
  "T if X is a closure."
  (EQ (%DATA-TYPE X) #.DTP-CLOSURE))

(DEFSUBST ENTITYP (X)
  "T if X is an entity."
  (EQ (%DATA-TYPE X) #.DTP-ENTITY))

(DEFSUBST RANDOM-STATE-P (OBJECT)
  "T if OBJECT is a random-state -- a seed for use by RANDOM."
  (TYPEP OBJECT 'RANDOM-STATE))

(DEFSUBST READTABLEP (OBJECT)
  "T if OBJECT is a readtable -- a syntax table for READ and PRINT."
  (TYPEP OBJECT 'READTABLE))

;;; PACKAGEP already exists.

(DEFSUBST COMPILED-FUNCTION-P (OBJECT)
  "T if OBJECT is a compiled function (a FEF)."
  (TYPEP OBJECT 'COMPILED-FUNCTION))

(DEFSUBST INSTANCEP (OBJECT)
  "T if OBJECT is an instance (of any flavor)."
  (TYPEP OBJECT 'INSTANCE))

(DEFSUBST KEYWORDP (SYMBOL)
  "T if SYMBOL belongs to the KEYWORD package."
  (AND (SYMBOLP SYMBOL)
       (EQ (SYMBOL-PACKAGE SYMBOL) PKG-KEYWORD-PACKAGE)))

(DEFSUBST SUBRP (OBJECT)
  "T if OBJECT is a compiled or built-in function."
  (MEMQ (%DATA-TYPE OBJECT) '(#.DTP-U-ENTRY #.DTP-FEF-POINTER)))

(DEFSUBST LOCATIVEP (X)
  "T if X is a locative."
  (EQ (%DATA-TYPE X) #.DTP-LOCATIVE))


(DEFSUBST %POINTERP (X)
  "T if X points to storage; NIL if it is an immediate quantity."
  (NOT (MEMQ (%DATA-TYPE X)
	     '(#.DTP-FIX #.DTP-SMALL-FLONUM #.DTP-U-ENTRY #.DTP-CHARACTER))))

(DEFSUBST %POINTER-TYPE-P (DATA-TYPE-CODE)
  "T if DATA-TYPE-CODE is a the code for a data type that points to storage."
  (NOT (MEMQ DATA-TYPE-CODE
	     '(#.DTP-FIX #.DTP-SMALL-FLONUM #.DTP-U-ENTRY #.DTP-CHARACTER
	       #.DTP-TRAP #.DTP-SELF-REF-POINTER #.DTP-HEADER #.DTP-ARRAY-HEADER))))

(DEFSUBST %P-POINTERP (POINTER)
  "T if the word POINTER points to contains a data type that points to some storage.
This includes various header and forwarding data types
which point to storage."
  (%POINTER-TYPE-P (%P-DATA-TYPE POINTER)))

(DEFSUBST %P-POINTERP-OFFSET (POINTER OFFSET)
  "T if the word POINTER+OFFSET points to contains a data type that points to some storage.
This includes various header and forwarding data types
which point to storage."
  (%POINTER-TYPE-P (%P-LDB-OFFSET %%Q-DATA-TYPE POINTER OFFSET)))

(DEFSUBST %DATA-TYPE-SAFE-P (DATA-TYPE)
  (MEMQ DATA-TYPE
	'(#.DTP-SYMBOL #.DTP-FIX #.DTP-EXTENDED-NUMBER #.DTP-LOCATIVE #.DTP-LIST
	  #.DTP-U-ENTRY #.DTP-FEF-POINTER #.DTP-ARRAY-POINTER
	  #.DTP-STACK-GROUP #.DTP-CLOSURE #.DTP-SMALL-FLONUM #.DTP-SELECT-METHOD
	  #.DTP-INSTANCE #.DTP-ENTITY #.DTP-STACK-CLOSURE #.DTP-CHARACTER)))

(DEFSUBST %P-CONTENTS-SAFE-P (POINTER)
  "T if the word POINTER points to contains data safe to read out.
It will be NIL if the word contains a forwarding pointer or a header."
  (%DATA-TYPE-SAFE-P (%P-DATA-TYPE POINTER)))

(DEFSUBST %P-CONTENTS-SAFE-P-OFFSET (POINTER OFFSET)
  "T if the word POINTER+OFFSET points to contains data safe to read out.
It will be NIL if the word contains a forwarding pointer or a header."
  (%DATA-TYPE-SAFE-P (%P-LDB-OFFSET %%Q-DATA-TYPE POINTER OFFSET)))

(DEFUN %P-SAFE-CONTENTS-OFFSET (POINTER OFFSET)
  "Extract the contents of a word (which contains typed data) in a way that is always safe.
The word is OFFSET words after where POINTER points.
If the contents are a valid Lisp data type, they are returned accurately.
If the contents point to storage but are not valid Lisp data
 (such as, forwarding pointers and symbol and instance headers)
 then a locative is returned.
If the contents do not point to storage and are not valid Lisp data
 (such as, a self-ref-pointer or an array header) then a fixnum is returned.
The second value is T if the accurate contents were returned."
  (IF (%P-CONTENTS-SAFE-P-OFFSET POINTER OFFSET)
      (VALUES (%P-CONTENTS-OFFSET POINTER OFFSET) T)
    (IF (%P-POINTERP-OFFSET POINTER OFFSET)
	(%P-CONTENTS-AS-LOCATIVE-OFFSET POINTER OFFSET)
      (%P-LDB-OFFSET %%Q-POINTER POINTER OFFSET))))

(DEFSUBST %POINTER-PLUS (PTR1 PTR2)
  "Return a fixnum which represents a pointer DISP words past PTR1.
The argumentts had better be locatives into the same object
for this operation to be meaningful;
otherwise, their relative position will be changed by GC."
  (%MAKE-POINTER-OFFSET DTP-FIX PTR1 PTR2))

(DEFSUBST %POINTER-LESSP (PTR1 PTR2)
  "T if PTR1 points to a lower memory address than PTR2"
  (MINUSP (%POINTER-DIFFERENCE PTR1 PTR2)))


(DEFSUBST NEQ (X Y)
  "T if X and Y are not the same object."
  (NOT (EQ X Y)))

;; actually microcoded itself
;(DEFSUBST ENDP (X)
;  "T if X as the cdr of a list terminates it."
;  (ATOM X))

(DEFSUBST BIT-TEST (BITS WORD)
  "T if the bits specified by BITS in WORD are not all zero.
BITS is a mask in which the bits to be tested are ones."
  (NOT (ZEROP (LOGAND BITS WORD))))
(DEFF LOGTEST 'BIT-TEST)

(DEFSUBST LDB-TEST (PPSS WORD)
  "T if the field specified by PPSS in WORD is not zero.
PPSS is a position (from the right) times 64., plus a size."
  (NOT (ZEROP (LDB PPSS WORD))))

(DEFSUBST %LOGLDB-TEST (PPSS WORD)
  "T if the field specified by PPSS in WORD is not zero.
PPSS is a position (from the right) times 64., plus a size.
Like LDB-TEST except that when SETF'd it does a %LOGDPB rather than a DPB."
  (NOT (ZEROP (%LOGLDB PPSS WORD))))

(DEFSUBST BYTE (WIDTH POSITION)
  "Return a byte specifier for a byte WIDTH bits long starting POSITION bits from the lsb."
  (+ WIDTH (DPB POSITION %%BYTE-SPECIFIER-POSITION 0)))

(DEFSUBST BYTE-POSITION (BYTE-SPECIFIER)
  "Return the byte position specified by BYTE-SPECIFIER.
This is the index of the least significant bit included in the byte."
  (LDB %%BYTE-SPECIFIER-POSITION BYTE-SPECIFIER))

(DEFSUBST BYTE-SIZE (BYTE-SPECIFIER)
  "Return the byte size specified by BYTE-SPECIFIER."
  (LDB %%BYTE-SPECIFIER-SIZE BYTE-SPECIFIER))

(DEFSUBST LOGBITP (INDEX INTEGER)
  "T if INTEGER's binary representation contains the 2^INDEX bit as a 1."
  (LDB-TEST (BYTE 1 INDEX) INTEGER))

(DEFSUBST SHORT-FLOAT (NUMBER)
  "Convert NUMBER to a short float."
  (SMALL-FLOAT NUMBER))

(DEFCONST NOCATCH (LIST NIL)
  "This is used as a catch tag when a conditional catch is not supposed to happen.")

(DEFMACRO CATCH-CONTINUATION (TAG-EXPRESSION
			      THROW-CONTINUATION NON-THROW-CONTINUATION
			      &BODY BODY)
  "Execute BODY with a catch for TAG-EXPRESSION, then call one continuation or the other.
If BODY THROWs to the tag, THROW-CONTINUATION is called with the values thrown as args,
 and the its values are returned.
 However, if THROW-CONTINUATION is NIL in the source code,
 the CATCH's values are returned directly.
If BODY returns normally, NON-THROW-CONTINUATION is called and its values returned,
 with the values of BODY as arguments.
 However, if NON-THROW-CONTINUATION is NIL in the source code,
 BODY's values are returned directly."
  (DECLARE (ZWEI:INDENTATION 1 3 3 1))
  `(CATCH-CONTINUATION-IF T ,TAG-EXPRESSION ,THROW-CONTINUATION ,NON-THROW-CONTINUATION
     . ,BODY))

(DEFMACRO CATCH-CONTINUATION-IF (COND-FORM TAG-EXPRESSION
				 THROW-CONTINUATION NON-THROW-CONTINUATION
				 &BODY BODY)
  "Like CATCH-CONTINUATION but catch only if COND-FORM evals non-NIL."
  ;; We don't use &BODY in the real arglist to avoid overriding
  ;; the special form of indentation on *INITIAL-LISP-INDENT-OFFSET-ALIST*
  (DECLARE (ZWEI:INDENTATION 2 3 4 1))
  (IF NON-THROW-CONTINUATION
      `(BLOCK CATCH-CONTINUATION-1
	 ,(IF THROW-CONTINUATION
	      `(CALL ,THROW-CONTINUATION
		     '(:SPREAD :OPTIONAL)
		     (MULTIPLE-VALUE-LIST
		       (CATCH (IF ,COND-FORM ,TAG-EXPRESSION NOCATCH)
			 (RETURN-FROM CATCH-CONTINUATION-1
			   (CALL ,NON-THROW-CONTINUATION
				 '(:SPREAD :OPTIONAL)
				 (MULTIPLE-VALUE-LIST
				   (PROGN ,@BODY)))))))
	    `(CATCH (IF ,COND-FORM ,TAG-EXPRESSION NOCATCH)
	       (RETURN-FROM CATCH-CONTINUATION-1
		 (CALL ,NON-THROW-CONTINUATION
		       '(:SPREAD :OPTIONAL)
		       (MULTIPLE-VALUE-LIST
			 (PROGN ,@BODY)))))))
    `(BLOCK CATCH-CONTINUATION-1
       ,(IF THROW-CONTINUATION
	    `(CALL ,THROW-CONTINUATION
		   '(:SPREAD :OPTIONAL)
		   (MULTIPLE-VALUE-LIST
		     (CATCH (IF ,COND-FORM ,TAG-EXPRESSION NOCATCH)
		       (RETURN-FROM CATCH-CONTINUATION-1 (PROGN . ,BODY)))))
	  `(CATCH (IF ,COND-FORM ,TAG-EXPRESSION NOCATCH)
	     (RETURN-FROM CATCH-CONTINUATION-1 (PROGN . ,BODY)))))))


;; condition-case, condition-case-if, condition-call, condition-call-if,
;; condition-bind, condition-bind-if, condition-bind-default, condition-bind-default-if,
;; errset, err, ignore-errors, error-restart, error-restart-loop, catch-error-restart,
;; catch-error-restart-if, catch-error-restart-explicit-if,
;; condition-resume, condition-resume-if, signal-proceed-case, catch-error
;;  moved to eh; errmac

(DEFMACRO CASE (TEST-OBJECT &BODY CLAUSES)
  "Execute the first clause that matches TEST-OBJECT.
The first element of each clause is a match value or a list of match values.
TEST-OBJECT is compared with the match values using EQL.
When a match-value matches, the rest of that clause is executed
and the value of the last thing in the clause is the value of the CASE.
T or OTHERWISE as the first element of a clause matches any test object."
  (LET (TEST-EXP COND-EXP)
    (SETQ TEST-EXP
	  ;; If TEST-OBJECT is an eval-at-load-time,
	  ;; we will treat it as a random expression, which is right.
	  (COND ((OR (ATOM TEST-OBJECT)
		     (AND (MEMQ (CAR TEST-OBJECT) '(CAR CDR CAAR CADR CDAR CDDR))
			  (ATOM (CADR TEST-OBJECT))))
		 TEST-OBJECT)
		(T '.SELECTQ.ITEM.)))
    (SETQ COND-EXP
	  (CONS 'COND
		(MAPCAR #'(LAMBDA (CLAUSE)
			    (MACRO-TYPE-CHECK-WARNING 'SELECTQ (CAR CLAUSE))
			    (COND ((MEMQ (CAR CLAUSE) '(OTHERWISE :OTHERWISE T))
				   (LIST* T NIL (CDR CLAUSE)))
				  ((ATOM (CAR CLAUSE))
				   `((EQL ,TEST-EXP ',(CAR CLAUSE)) NIL . ,(CDR CLAUSE)))
				  (T
				   `((MEMBER-EQL ,TEST-EXP ',(CAR CLAUSE)) NIL . ,(CDR CLAUSE)))))
			CLAUSES)))
    (DEAD-CLAUSES-WARNING (CDR COND-EXP) 'SELECTQ)
    (IF (EQL TEST-EXP TEST-OBJECT)
	COND-EXP
      `(LET ((.SELECTQ.ITEM. ,TEST-OBJECT))
	 ,COND-EXP))))
(DEFF-MACRO SELECTQ 'CASE)
(DEFF-MACRO CASEQ 'CASE)


(DEFUN DEAD-CLAUSES-WARNING (COND-CLAUSES FUNCTION-NAME)
  "Given a list of COND-clauses, warn if any but the last starts with T.
FUNCTION-NAME (usually a macro name) is used in the warning.
The warning is made iff we are now accumulating warnings for an object."
  (DO ((CLAUSES COND-CLAUSES (CDR CLAUSES)))
      ((NULL (CDR CLAUSES)))
    (AND (EQ (CAAR CLAUSES) T)
	 OBJECT-WARNINGS-OBJECT-NAME
	 (RETURN
	   (COMPILER:WARN 'DEAD-CODE :IMPLAUSIBLE
			  "Unreachable clauses following otherwise-clause in ~S." FUNCTION-NAME)))))

(DEFMACRO SELECT-MEMQ (TEST-LIST &BODY CLAUSES)
  "Execute the first clause that matches some element of TEST-LIST.
The first element of each clause is a match value or a list of match values.
Each match value is compare with each element of TEST-LIST, using EQ.
When a match-value matches, the rest of that clause is executed
and the value of the last thing in the clause is the value of the SELECT-MEMQ.
T or OTHERWISE as the first element of a clause matches any test object."
  (LET (TEST-EXP COND-EXP)
    (SETQ TEST-EXP
	  ;; If TEST-LIST is an eval-at-load-time,
	  ;; we will treat it as a random expression, which is right.
	  (COND ((OR (ATOM TEST-LIST)
		     (AND (MEMQ (CAR TEST-LIST) '(CAR CDR CAAR CADR CDAR CDDR))
			  (ATOM (CADR TEST-LIST))))
		 TEST-LIST)
		(T '.SELECTQ.ITEM.)))
    (SETQ COND-EXP
	  (CONS 'COND
		(MAPCAR #'(LAMBDA (CLAUSE)
			    (MACRO-TYPE-CHECK-WARNING 'SELECT-MEMQ (CAR CLAUSE))
			    (COND ((MEMQ (CAR CLAUSE) '(OTHERWISE :OTHERWISE T))
				   (LIST* T NIL (CDR CLAUSE)))
				  ((ATOM (CAR CLAUSE))
				   `((MEMQ ',(CAR CLAUSE) ,TEST-EXP) NIL . ,(CDR CLAUSE)))
				  (T
				   `((OR . ,(MAPCAR #'(LAMBDA (MATCH-VALUE)
							`(MEMQ ',MATCH-VALUE ,TEST-EXP))
						    (CAR CLAUSE)))
				     NIL . ,(CDR CLAUSE)))))
			CLAUSES)))
    (DEAD-CLAUSES-WARNING (CDR COND-EXP) 'SELECT-MEMQ)
    (COND ((EQ TEST-EXP TEST-LIST) COND-EXP)
	  (T
	   `(LET ((.SELECTQ.ITEM. ,TEST-LIST))
	      ,COND-EXP)))))

(DEFMACRO SELECT (TEST-OBJECT &BODY CLAUSES)
  "Execute the first clause that matches TEST-OBJECT.
The first element of each clause is a match value expression or a list of such.
TEST-OBJECT is compared with the VALUES of the match expressions, using EQ.
When a match-value matches, the rest of that clause is executed
and the value of the last thing in the clause is the value of the SELECT.
T or OTHERWISE as the first element of a clause matches any test object.
This is a special exception, in that OTHERWISE is not evaluated."
  (LET (TEST-EXP COND-EXP)
    (SETQ TEST-EXP
	  ;; If TEST-OBJECT is an eval-at-load-time,
	  ;; we will treat it as a random expression, which is right.
	  (IF (OR (ATOM TEST-OBJECT)
		  (AND (MEMQ (CAR TEST-OBJECT) '(CAR CDR CAAR CADR CDAR CDDR))
		       (ATOM (CADR TEST-OBJECT))))
	      TEST-OBJECT
	      '.SELECTQ.ITEM.))
    (SETQ COND-EXP
	  (CONS 'COND
		(MAPCAR #'(LAMBDA (CLAUSE)
			    (MACRO-TYPE-CHECK-WARNING 'SELECT (CAR CLAUSE))
			    (COND ((MEMQ (CAR CLAUSE) '(OTHERWISE :OTHERWISE T))
				   (LIST* T NIL (CDR CLAUSE)))
				  ((ATOM (CAR CLAUSE))
				   `((EQ ,TEST-EXP ,(CAR CLAUSE)) NIL . ,(CDR CLAUSE)))
				  (T
				   `((OR . ,(MAPCAR #'(LAMBDA (FORM)
							`(EQ ,TEST-EXP ,FORM))
					 (CAR CLAUSE)))
				     NIL . ,(CDR CLAUSE)))))
			CLAUSES)))
    (DEAD-CLAUSES-WARNING (CDR COND-EXP) 'SELECT)
    (COND ((EQ TEST-EXP TEST-OBJECT) COND-EXP)
	  (T
	   `(LET ((.SELECTQ.ITEM. ,TEST-OBJECT))
	      ,COND-EXP)))))

(DEFMACRO SELECTOR (TEST-OBJECT TEST-FUNCTION &BODY CLAUSES)
  "Execute the first clause that matches TEST-OBJECT.
The first element of each clause is a match value expression or a list of such.
TEST-OBJECT is compared with the VALUES of the match expressions, using TEST-FUNCTION.
When a match-value matches, the rest of that clause is executed
and the value of the last thing in the clause is the value of the SELECTOR.
T or OTHERWISE as the first element of a clause matches any test object.
This is a special exception, in that OTHERWISE is not evaluated."
  (LET (TEST-EXP COND-EXP)
    (SETQ TEST-EXP
	  ;; If TEST-OBJECT is an eval-at-load-time,
	  ;; we will treat it as a random expression, which is right.
	  (IF (OR (ATOM TEST-OBJECT)
		  (AND (MEMQ (CAR TEST-OBJECT) '(CAR CDR CAAR CADR CDAR CDDR))
		       (ATOM (CADR TEST-OBJECT))))
	      TEST-OBJECT
	      '.SELECTQ.ITEM.))
    (SETQ COND-EXP
	  (CONS 'COND
		(MAPCAR #'(LAMBDA (CLAUSE)
			    (MACRO-TYPE-CHECK-WARNING 'SELECTOR (CAR CLAUSE))
			    (COND ((MEMQ (CAR CLAUSE) '(OTHERWISE :OTHERWISE T))
				   (LIST* T NIL (CDR CLAUSE)))
				  ((ATOM (CAR CLAUSE))
				   `((,TEST-FUNCTION ,TEST-EXP ,(CAR CLAUSE))
				     NIL . ,(CDR CLAUSE)))
				  (T
				   `((OR . ,(MAPCAR #'(LAMBDA (FORM)
							`(,TEST-FUNCTION ,TEST-EXP ,FORM))
						    (CAR CLAUSE)))
				     NIL . ,(CDR CLAUSE)))))
			CLAUSES)))
    (DEAD-CLAUSES-WARNING (CDR COND-EXP) 'SELECTOR)
    (COND ((EQ TEST-EXP TEST-OBJECT) COND-EXP)
	  (T
	   `(LET ((.SELECTQ.ITEM. ,TEST-OBJECT))
	      ,COND-EXP)))))

;;; Eventually the micro compiler should be aware of this
(DEFMACRO DISPATCH (PPSS WORD &BODY CLAUSES)
  "Extract the byte PPSS from WORD and execute a clause selected by the value.
The first element of each clause is a value to compare with the byte value,
or a list of byte values.  These byte values are evaluated!.
T or OTHERWISE as the first element of a clause matches any test object.
This is a special exception, in that OTHERWISE is not evaluated."
  (LET ((FOO (GENSYM)))
    `(LET ((,FOO (LDB ,PPSS ,WORD)))
       (COND ,@(MAPCAR #'(LAMBDA (CLAUSE)
			   (MACRO-TYPE-CHECK-WARNING 'DISPATCH (CAR CLAUSE))
			   `(,(COND ((MEMQ (CAR CLAUSE) '(OTHERWISE :OTHERWISE T))
				     'T)
				    ((ATOM (CAR CLAUSE))
				     `(= ,FOO ,(CAR CLAUSE)))
				    (T
				     `(OR ,@(MAPCAR #'(LAMBDA (ITEM)
							`(= ,FOO ,ITEM))
						    (CAR CLAUSE)))))
			     NIL . ,(CDR CLAUSE)))
		       CLAUSES)))))

(DEFMACRO GLOBAL:EVERY (LIST PRED &OPTIONAL (STEP ''CDR))
  "T if every element of LIST satisfies PRED.
If STEP is specified, it is a function to move down the list
/(default is CDR.)."
  (LET ((TAIL (GENSYM)))
    (ONCE-ONLY (PRED STEP)
      `(DO ((,TAIL ,LIST (FUNCALL ,STEP ,TAIL)))
	   ((NULL ,TAIL) T)
	 (OR (FUNCALL ,PRED (CAR ,TAIL)) (RETURN NIL))))))

(DEFMACRO GLOBAL:SOME (LIST PRED &OPTIONAL (STEP ''CDR))
  "Non-NIL if some element of LIST satisfies PRED.
If STEP is specified, it is a function to move down the list
/(default is CDR.).  The actual value is the tail of the list
whose car is the first element that satisfies PRED."
  (LET ((TAIL (GENSYM)))
    (ONCE-ONLY (PRED STEP)
      `(DO ((,TAIL ,LIST (FUNCALL ,STEP ,TAIL)))
	   ((NULL ,TAIL) NIL)
	 (AND (FUNCALL ,PRED (CAR ,TAIL)) (RETURN ,TAIL))))))

(DEFMACRO LET-GLOBALLY-IF (COND-FORM VARLIST &BODY BODY)
  "Like LET-IF, but sets the variables on entry and sets them back on exit.
No new binding is created.  As a result, the changed values are visible
in other stack groups while this frame is dynamically active."
  (LET ((VARS (MAPCAR #'(LAMBDA (V) (COND ((ATOM V) V) (T (CAR V)))) VARLIST))
	(VALS (MAPCAR #'(LAMBDA (V) (COND ((ATOM V) NIL) (T (CADR V)))) VARLIST))
	(GENVARS (MAPCAR #'(LAMBDA (IGNORE) (GENSYM)) VARLIST))
	(CONDVAR (GENSYM)))
    `(LET ((,CONDVAR ,COND-FORM) . ,GENVARS)
       (UNWIND-PROTECT
	   (PROGN
	     (WHEN ,CONDVAR
	       ,@(MAPCAR #'(LAMBDA (GENVAR VAR)
			     `(COPY-VALUE (LOCF ,GENVAR) (LOCF ,VAR)))
			 GENVARS VARS)
	       (SETQ . ,(MAPCAN 'LIST VARS VALS)))
	     . ,BODY)
	 (WHEN ,CONDVAR
	   . ,(MAPCAR #'(LAMBDA (VAR GENVAR)
			  `(COPY-VALUE (LOCF ,VAR) (LOCF ,GENVAR)))
		      VARS GENVARS))))))

(DEFMACRO LET-GLOBALLY (VARLIST &BODY BODY)
  "Like LET, but sets the variables on entry and sets them back on exit.
No new binding is created.  As a result, the changed values are visible
in other stack groups while this frame is dynamically active."
  (LET ((VARS (MAPCAR #'(LAMBDA (V) (COND ((ATOM V) V) (T (CAR V)))) VARLIST))
	(VALS (MAPCAR #'(LAMBDA (V) (COND ((ATOM V) NIL) (T (CADR V)))) VARLIST))
	(GENVARS (MAPCAR #'(LAMBDA (IGNORE) (GENSYM)) VARLIST)))
     `(LET ,GENVARS
        (UNWIND-PROTECT (PROGN ,@(MAPCAR #'(LAMBDA (GENVAR VAR)
					     `(COPY-VALUE (LOCF ,GENVAR) (LOCF ,VAR)))
					 GENVARS VARS)
			       (SETQ . ,(MAPCAN 'LIST VARS VALS))
			       . ,BODY)
			. ,(MAPCAR #'(LAMBDA (VAR GENVAR)
				       `(COPY-VALUE (LOCF ,VAR) (LOCF ,GENVAR)))
				   VARS GENVARS)))))

(DEFUN COPY-VALUE (TO-CELL FROM-CELL)
  "Copy whatever value is in FROM-CELL into TO-CELL."
  (%P-STORE-CDR-CODE TO-CELL
		     (PROG1 (%P-CDR-CODE FROM-CELL)
			    (%BLT-TYPED FROM-CELL TO-CELL 1 0))))

;;; DEFUNP is like DEFUN but provides an implicit PROG.
;;; However, the value on falling off the end is the last thing in the body.
(DEFMACRO DEFUNP (&ENVIRONMENT ENV FUNCTION-SPEC LAMBDA-LIST &REST BODY)
  "Like DEFUN, but provides an implicit PROG of no variables around the BODY.
So you can use RETURN to return from the function, and use GO.
There is one difference from an ordinary PROG:
the value of the last element of the BODY is returned.
This is so even if it is an atom.  This is like ordinary DEFUNs."
  (LET ((DEFAULT-CONS-AREA WORKING-STORAGE-AREA)
	(LAST NIL)
	DECLARES DOC)
    (SETQ BODY (COPY-LIST BODY))
    (SETQ LAST (LAST BODY))
    (SETF (VALUES BODY DECLARES DOC)
	  (EXTRACT-DECLARATIONS BODY NIL T ENV))
    (WHEN (NEQ (CAAR-SAFE LAST) 'RETURN)
      (SETF (CAR LAST) `(RETURN ,(CAR LAST))))
    `(DEFUN ,FUNCTION-SPEC ,LAMBDA-LIST
       ,DOC
       (DECLARE . ,DECLARES)
       (PROG () . ,BODY))))

(DEFMACRO CATCH-ALL BODY
  "Catch all throws to all tags within the body, unless BODY itself CATCHes them"
  `(CATCH NIL (VALUES-LIST (APPEND (MULTIPLE-VALUE-LIST (PROGN . ,BODY)) '(NIL NIL NIL)))))

; Now special forms
;(DEFMACRO MULTIPLE-VALUE-CALL (FUNCTION &REST FORMS)
;  "Call FUNCTION like FUNCALL, but use all values returned by each of FORMS.
;FUNCALL would use only the first value returned by each of them.
;This conses, alas."
;  `(CALL ,FUNCTION
;	 . ,(MAPCAN #'(LAMBDA (FORM)
;			`(':SPREAD (MULTIPLE-VALUE-LIST ,FORM)))
;		    FORMS)))

;(DEFMACRO IF (TEST THEN &BODY ELSES)
;  "Execute THEN if TEST comes out non-NIL; otherwise, execute the ELSES."
;  (COND ((NULL TEST) (AND ELSES `(PROGN . ,ELSES)))	;macros can generate this case...
;	((EQ TEST T) THEN)			;and this one (avoids compiler error msg)
;	(T `(COND (,TEST ,THEN) (T . ,(OR ELSES '(NIL)))))))

;;; (WHEN pred {form}*)
(DEFMACRO WHEN (PRED &BODY BODY)
  "(WHEN pred form1 from2 ...) ==> (AND pred (PROGN form1 form2 ...))
WHEN first evaluates PRED.  If the result is (), WHEN returns ().
Otherwise, the BODY is executed and its last expression's value returned."
  `(AND ,PRED (PROGN ,@BODY)))

;;; (UNLESS pred {form}*)
(DEFMACRO UNLESS (PRED &BODY BODY)
  "(UNLESS pred form1 form2 ...) ==> (IF pred () form1 form2 ...)
UNLESS first evaluates PRED.  If the result is non-(), UNLESS returns ().
Otherwise, the BODY executed and its last expression's value is returned."
  `(IF ,PRED () ,@BODY))


;;;; CHECK-ARG, CHECK-TYPE, TYPECASE, CTYPECASE, ETYPECASE, CCASE, ECASE, ASSERT

;;; (CHECK-ARG <VARIABLE> <PREDICATE> <MESSAGE>), for example:
;;; (CHECK-ARG STRING STRINGP "a string") signals an error if STRING is not a string.
;;; The error signals condition :WRONG-TYPE-ARGUMENT with arguments
;;; which are STRINGP (the predicate), the value of STRING (the losing value),
;;; the name of the argument (STRING), and the string "a string".
;;; If you try to proceed and do not supply a valid string to replace it,
;;; the error happens again.
;;; The second form may be the name of a predicate function, or it may be a full
;;; predicate form, as in:
;;; (CHECK-ARG A (AND (NUMBERP A) (< A 10.) (> A 0.)) "a number from one to ten" ONE-TO-TEN)
;;; ONE-TO-TEN is a symbol for the "type" which the argument failed to be.
;;; It is used instead of the second argument (the predicate) when signalling the error,
;;; since the second argument is not a suitable symbol.
;;; The value returned by CHECK-ARG is the argument's (original or respecified) value.
;;; In general, the condition :WRONG-TYPE-ARGUMENT is signalled with arguments
;;;    (1) A symbol for the desired type (NIL if not supplied)
;;;    (2) The bad value
;;;    (3) The name of the argument
;;;    (4) A string for the desired type.
(DEFMACRO CHECK-ARG (ARG-NAME PREDICATE TYPE-STRING &OPTIONAL ERROR-TYPE-NAME)
  "Generate error if the value of ARG-NAME doesn't satisfy PREDICATE.
PREDICATE is a function name (a symbol) or an expression to compute.
TYPE-STRING is a string to use in the error message, such as /"a list/".
ERROR-TYPE-NAME is a keyword that tells condition handlers what type was desired.
This macro is somewhat obsolete: you should probably be using CHECK-TYPE instead."
    (AND (NULL ERROR-TYPE-NAME)
	 (SYMBOLP PREDICATE)
	 (SETQ ERROR-TYPE-NAME PREDICATE))
    `(DO () (,(COND ((SYMBOLP PREDICATE)
                     `(,PREDICATE ,ARG-NAME))
                    (T PREDICATE))
             ,ARG-NAME)
	 (SETQ ,ARG-NAME
	       (CERROR '(:ARGUMENT-VALUE) NIL 'WRONG-TYPE-ARGUMENT
		       "The argument ~2@*~A was ~1@*~S, which is not ~3@*~A."
		       ',ERROR-TYPE-NAME ,ARG-NAME ',ARG-NAME ',TYPE-STRING))))

(DEFMACRO CHECK-TYPE (ARG-NAME TYPE &OPTIONAL TYPE-STRING)
  "Generate an error unless (TYPEP ARG-NAME 'TYPE).
TYPE-STRING is a string to use in the error message, such as /"a list/".
If you omit it, it will be computed from TYPE's pname."
  `(DO () ((TYPEP ,ARG-NAME ',TYPE))
     (SETQ ,ARG-NAME
	   (CERROR '(:ARGUMENT-VALUE) NIL 'WRONG-TYPE-ARGUMENT
		   "The argument ~2@*~A was ~1@*~S, which is not ~3@*~A."
		   ',TYPE ,ARG-NAME ',ARG-NAME
		   ,(OR TYPE-STRING `(TYPE-PRETTY-NAME ',TYPE))))))

(DEFF-MACRO CHECK-ARG-TYPE 'CHECK-TYPE)
;(compiler:make-obsolete check-arg-type "the new name is CHECK-TYPE")

;; this really should try to be a lot smarter...
(DEFMACRO TYPECASE (OBJECT &BODY CLAUSES)
  "Execute the first clause whose type specifier OBJECT fits.
The first element of each clause is a type specifier.
It is used as the second argument to TYPEP to test the type of OBJECT.
If the result is T, the rest of that clause is excuted and the values
 of the last form in it are the values of the TYPECASE form.
If no clause fits, the value of the TYPECASE is NIL."
  (ONCE-ONLY (OBJECT)
    `(COND
       . ,(LOOP FOR (TYPE . CONSEQUENTS) IN CLAUSES
		COLLECT `(,(PROGN
			     (MACRO-TYPE-CHECK-WARNING 'TYPECASE TYPE)
			     (IF (MEMQ TYPE '(T OTHERWISE))
				 'T
			       `(TYPEP ,OBJECT ',TYPE)))
			  NIL . ,CONSEQUENTS)))))

(DEFMACRO ETYPECASE (OBJECT &BODY CLAUSES)
  "Execute the first clause whose type specifier OBJECT fits.
The first element of each clause is a type specifier.
It is used as the second argument to TYPEP to test the type of OBJECT.
If the result is T, the rest of that clause is excuted and the values
 of the last form in it are the values of the ETYPECASE form.
If no clause fits, an uncorrectable error is signaled."
  (LET ((SAVE-OBJECT OBJECT))
    (ONCE-ONLY (OBJECT)
      `(COND
	 ,@(LOOP FOR (TYPE . CONSEQUENTS) IN CLAUSES
		 COLLECT `(,(PROGN
			      (MACRO-TYPE-CHECK-WARNING 'TYPECASE TYPE)
				     `(TYPEP ,OBJECT ',TYPE))
			   NIL . ,CONSEQUENTS))
	 (T (FERROR NIL
		    "The argument ~2@*~A was ~1@*~S, which is not ~3@*~A."
		    '(OR . ,(MAPCAR 'CAR CLAUSES))
		    ,OBJECT ',SAVE-OBJECT
		    (TYPE-PRETTY-NAME '(OR . ,(MAPCAR 'CAR CLAUSES)))))))))

(DEFMACRO CTYPECASE (OBJECT &BODY CLAUSES)
  "Execute the first clause whose type specifier OBJECT fits.
The first element of each clause is a type specifier.
It is used as the second argument to TYPEP to test the type of OBJECT.
If the result is T, the rest of that clause is excuted and the values
 of the last form in it are the values of the CTYPECASE form.
If no clause fits, a correctable error is signaled.
The user can correct with a new value for OBJECT."
  (LET ((SAVE-OBJECT OBJECT))
    `(BLOCK CTYPECASE-LOOP
       (TAGBODY
      CTYPECASE-LOOP
	 (RETURN-FROM CTYPECASE-LOOP
	   ,(ONCE-ONLY (OBJECT)
	      `(COND
		 ,@(LOOP FOR (TYPE . CONSEQUENTS) IN CLAUSES
			 COLLECT `(,(PROGN
				      (MACRO-TYPE-CHECK-WARNING 'TYPECASE TYPE)
				      `(TYPEP ,OBJECT ',TYPE))
				   NIL . ,CONSEQUENTS))
		 (T (SETF ,SAVE-OBJECT
			  (CERROR '(:ARGUMENT-VALUE) NIL 'WRONG-TYPE-ARGUMENT
				  "The argument ~2@*~A was ~1@*~S, which is not ~3@*~A."
				  '(OR . ,(MAPCAR 'CAR CLAUSES))
				  ,OBJECT ',SAVE-OBJECT
				  (TYPE-PRETTY-NAME '(OR . ,(MAPCAR 'CAR CLAUSES)))))
		    (GO CTYPECASE-LOOP)))))))))

(DEFMACRO CCASE (TEST-OBJECT &BODY CLAUSES)
  "Execute the first clause that matches TEST-OBJECT.
The first element of each clause is a match value or a list of match values.
TEST-OBJECT is compared with the match values using EQ.
When a match-value matches, the rest of that clause is executed
and the value of the last thing in the clause is the value of the CCASE.
If no clause matches, a correctable error is signaled.
The user can correct with a new value for TEST-OBJECT."
  (LET (TEST-EXP COND-EXP TYPE-FOR-ERROR)
    (SETQ TEST-EXP
	  ;; If TEST-OBJECT is an eval-at-load-time,
	  ;; we will treat it as a random expression, which is right.
	  (COND ((OR (ATOM TEST-OBJECT)
		     (AND (MEMQ (CAR TEST-OBJECT) '(CAR CDR CAAR CADR CDAR CDDR))
			  (ATOM (CADR TEST-OBJECT))))
		 TEST-OBJECT)
		(T '.SELECTQ.ITEM.)))
    (SETQ TYPE-FOR-ERROR
	  `(CLI:MEMBER . ,(MAPCAN #'(LAMBDA (CLAUSE)
				      (LET ((MATCH (CAR CLAUSE)))
					(IF (NOT (CONSP MATCH))
					    (LIST MATCH)
					  (COPY-LIST MATCH))))
				  CLAUSES)))
    (SETQ COND-EXP
	  `(COND
	     ,@(MAPCAR #'(LAMBDA (CLAUSE)
			   (MACRO-TYPE-CHECK-WARNING 'CCASE (CAR CLAUSE))
			   (COND ((ATOM (CAR CLAUSE))
				  `((EQL ,TEST-EXP ',(CAR CLAUSE))
				    NIL . ,(CDR CLAUSE)))
				 (T
				  `((MEMBER-EQL ,TEST-EXP ',(CAR CLAUSE))
				    NIL . ,(CDR CLAUSE)))))
		       CLAUSES)
	     (T (SETF ,TEST-OBJECT
		      (CERROR '(:ARGUMENT-VALUE) NIL 'WRONG-TYPE-ARGUMENT
			      "The argument ~2@*~A was ~1@*~S, which is not ~3@*~A."
			      ',TYPE-FOR-ERROR
			      ,TEST-EXP ',TEST-OBJECT
			      (TYPE-PRETTY-NAME ',TYPE-FOR-ERROR)))
		(GO CCASE-LOOP))))
    (DEAD-CLAUSES-WARNING (CDR COND-EXP) 'CCASE)
    (UNLESS (EQL TEST-EXP TEST-OBJECT)
      (SETQ COND-EXP
	    `(LET ((.SELECTQ.ITEM. ,TEST-OBJECT))
	       ,COND-EXP)))
    `(BLOCK CCASE-LOOP
       (TAGBODY
      CCASE-LOOP
         (RETURN-FROM CCASE-LOOP
	   ,COND-EXP)))))

(DEFMACRO ECASE (TEST-OBJECT &BODY CLAUSES)
  "Execute the first clause that matches TEST-OBJECT.
The first element of each clause is a match value or a list of match values.
TEST-OBJECT is compared with the match values using EQ.
When a match-value matches, the rest of that clause is executed
and the value of the last thing in the clause is the value of the ECASE.
If no clause matches, an uncorrectable error is signaled."
  (LET (TEST-EXP COND-EXP TYPE-FOR-ERROR)
    (SETQ TEST-EXP
	  ;; If TEST-OBJECT is an eval-at-load-time,
	  ;; we will treat it as a random expression, which is right.
	  (COND ((OR (ATOM TEST-OBJECT)
		     (AND (MEMQ (CAR TEST-OBJECT) '(CAR CDR CAAR CADR CDAR CDDR))
			  (ATOM (CADR TEST-OBJECT))))
		 TEST-OBJECT)
		(T '.SELECTQ.ITEM.)))
    (SETQ TYPE-FOR-ERROR
	  `(CLI:MEMBER . ,(MAPCAN #'(LAMBDA (CLAUSE)
				      (LET ((MATCH (CAR CLAUSE)))
					(IF (NOT (CONSP MATCH))
					    (LIST MATCH)
					  (COPY-LIST MATCH))))
				  CLAUSES)))
    (SETQ COND-EXP
	  `(COND
	     ,@(MAPCAR #'(LAMBDA (CLAUSE)
			   (MACRO-TYPE-CHECK-WARNING 'ECASE (CAR CLAUSE))
			   (COND ((ATOM (CAR CLAUSE))
				  `((EQL ,TEST-EXP ',(CAR CLAUSE))
				    NIL . ,(CDR CLAUSE)))
				 (T
				  `((MEMBER-EQL ,TEST-EXP ',(CAR CLAUSE))
				    NIL . ,(CDR CLAUSE)))))
		       CLAUSES)
	     (T (FERROR NIL
			"The argument ~2@*~A was ~1@*~S, which is not ~3@*~A."
			',TYPE-FOR-ERROR
			,TEST-EXP ',TEST-OBJECT
			(TYPE-PRETTY-NAME ',TYPE-FOR-ERROR)))))
    (DEAD-CLAUSES-WARNING (CDR COND-EXP) 'ECASE)
    (UNLESS (EQL TEST-EXP TEST-OBJECT)
      (SETQ COND-EXP
	    `(LET ((.SELECTQ.ITEM. ,TEST-OBJECT))
	       ,COND-EXP)))
    COND-EXP))

(DEFMACRO ASSERT (TEST-FORM &OPTIONAL PLACES (FORMAT-STRING "Assertion failed.") &REST ARGS)
  "Signals an error if TEST-FORM evals to NIL.
PLACES are SETF'able things that the user should be able to change when proceeding.
Typically they are things used in TEST-FORM.
Each one becomes a proceed-type which means to set that place.
FORMAT-STRING and ARGS are passed to FORMAT to make the error message."
  (DECLARE (ARGLIST TEST-FORM &OPTIONAL PLACES FORMAT-STRING &REST ARGS))
  `(DO () (,TEST-FORM)
     (SIGNAL-PROCEED-CASE ((VALUE) 'EH:FAILED-ASSERTION
				   :PLACES ',PLACES
				   :FORMAT-STRING ,FORMAT-STRING
				   :FORMAT-ARGS (LIST . ,ARGS))
       . ,(MAPCAR #'(LAMBDA (PLACE)
		      `((,PLACE) (SETF ,PLACE VALUE)))
		  PLACES))))
      

(DEFMACRO PSETQ (&REST REST)
  "Like SETQ, but no variable value is changed until all the values are computed.
The returned value is undefined."
  ;; To improve the efficiency of do-stepping, by using the SETE-CDR, SETE-CDDR,
  ;; SETE-1+, and SETE-1- instructions, we try to do such operations with SETQ
  ;; rather than PSETQ.  To avoid having to do full code analysis, never rearrange
  ;; the order of any code when doing this, and only do it when there are no
  ;; variable name duplications.
  (LOOP FOR (VAL VAR) ON (REVERSE REST) BY 'CDDR
	WITH SETQS = NIL WITH PSETQS = NIL
	DO (UNLESS (EQ VAR VAL)
	     (IF (AND (NULL PSETQS)
		      (OR (AND (CONSP VAL)
			       (MEMQ (CAR VAL) '(1+ 1- CDR CDDR))
			       (EQ (CADR VAL) VAR))
			  (EQ VAR VAL))
		      (NOT (MEMQ VAR SETQS)))
		 (SETQ SETQS (CONS VAR (CONS VAL SETQS)))
	       (SETQ PSETQS (CONS VAR (CONS VAL PSETQS)))))
	FINALLY
	  (SETQ PSETQS (PSETQ-PROG1IFY PSETQS))
	  (RETURN (COND ((NULL SETQS) PSETQS)
			((NULL PSETQS) (CONS 'SETQ SETQS))
			(T `(PROGN ,PSETQS (SETQ . ,SETQS)))))))

(DEFUN PSETQ-PROG1IFY (X)
  (COND ((NULL X) NIL)
	((NULL (CDDR X)) (CONS 'SETQ X))
	(T `(SETQ ,(CAR X) (PROG1 ,(CADR X) ,(PSETQ-PROG1IFY (CDDR X)))))))

;;; (LOCAL-DECLARE ((SPECIAL FOO) (UNSPECIAL BAR)) code)
;;; declares FOO and BAR locally within <code>.
;;; LOCAL-DECLARE can also be used by macros to pass information down
;;; to other macros that expand inside the code they produce.
;;; The list of declarations (in this case, ((MUMBLE FOO BAR))) is appended
;;; onto the front of LOCAL-DECLARATIONS, which can be searched by
;;; macros expending inside of <code>.
(DEFMACRO LOCAL-DECLARE (DECLARATIONS &BODY BODY)
  "Evaluates or compiles BODY with DECLARATIONS in effect.
DECLARATIONS is a list of declarations, each of which is a list.
Declarations include (SPECIAL variables...), (UNSPECIAL argument-names...),
/(NOTINLINE function-names...), (:SELF-FLAVOR flavorname)."
  `(COMPILER-LET ((LOCAL-DECLARATIONS (APPEND ',DECLARATIONS LOCAL-DECLARATIONS)))
     . ,BODY))

(DEFMACRO INHIBIT-STYLE-WARNINGS (BODY)
  "Inhibit style warnings from compilation of BODY."
  BODY)


(DEFMACRO LET-CLOSED (VARS &BODY BODY)
  "Binds VARS like LET, then returns a closure of the value of BODY over those variables."
  (LET ((VARNAMES (MAPCAR (FUNCTION (LAMBDA (V) (COND ((ATOM V) V) (T (CAR V))))) VARS)))
    `(LET ,VARS
       (DECLARE (SPECIAL . ,VARNAMES))
       (CLOSURE ',VARNAMES (PROGN . ,BODY)))))

;(DEFMACRO DEF-OPEN-CODED (FUNCTION-SPEC DEFINITION)
;  "Define FUNCTION-SPEC with DEFINITION like DEFF, and tell the compiler to open-code it.
;The compiler will substitute the definition for FUNCTION-SPEC whenever FUNCTION-SPEC
;appears as the car of an expression."
;  `(PROGN (DEFDECL ,FUNCTION-SPEC INLINE ,DEFINITION)
;	  (DEFF ,FUNCTION-SPEC ',DEFINITION)))


;;;; DEFVAR, DEFPARAMETER, DEFCONSTANT

;;; Make a variable special and, optionally, initialize it.
;;; This is recorded as a definition by TAGS and ZWEI.
(DEFMACRO DEFVAR (VARIABLE . ARGS)
  "Define a special variable named VARIABLE, and initialize to INITIAL-VALUE if unbound.
Normally, reevaluating the DEFVAR does not change the variable's value.
But in patch files, and if you do C-Shift-E with no region on a DEFVAR,
the variable is reinitialized.  DOCUMENTATION is available if the user
asks for the documentation of the symbol VARIABLE.
If you want your variable to be initially unbound, yet have documentation, 
use :UNBOUND as the initial value."
  (DECLARE (ARGLIST VARIABLE &OPTIONAL INITIAL-VALUE DOCUMENTATION))
  `(PROGN (EVAL-WHEN (COMPILE)
	    (PROCLAIM '(SPECIAL ,VARIABLE)))
	  (EVAL-WHEN (LOAD EVAL)
	    (DEFVAR-1 ,VARIABLE . ,ARGS))))

(DEFMACRO DEFPARAMETER (VARIABLE INITIAL-VALUE . ARGS)
  "Define a special variable which the program won't change but the user may.
It is set unconditionally to the value of INITIAL-VALUE.
DOCUMENTATION is available if the user asks for the documentation of the symbol VARIABLE."
  (DECLARE (ARGLIST VARIABLE INITIAL-VALUE &OPTIONAL DOCUMENTATION))
  `(PROGN (EVAL-WHEN (COMPILE)
	    (PROCLAIM '(SPECIAL ,VARIABLE)))
	  (EVAL-WHEN (LOAD EVAL)
	    (DEFCONST-1 ,VARIABLE ,INITIAL-VALUE . ,ARGS))))
(DEFF-MACRO DEFCONST 'DEFPARAMETER)

;>> this isn't nearly adequate.
(DEFMACRO DEFCONSTANT (VARIABLE INITIAL-VALUE . ARGS)
  "Define a special variable which will never be changed, and the compiler may assume so.
It is set unconditionally to the value of INITIAL-VALUE.
DOCUMENTATION is available if the user asks for the documentation of the symbol VARIABLE."
  (DECLARE (ARGLIST VARIABLE INITIAL-VALUE &OPTIONAL DOCUMENTATION))
  `(PROGN (EVAL-WHEN (COMPILE)
	    (PROCLAIM '(SPECIAL ,VARIABLE)))
	  (EVAL-WHEN (LOAD EVAL)
	    (DEFPROP ,VARIABLE T COMPILER::SYSTEM-CONSTANT))
	  (EVAL-WHEN (LOAD EVAL)
	    (DEFCONST-1 ,VARIABLE ,INITIAL-VALUE . ,ARGS))))

(DEFMACRO DOTIMES ((VAR LIMIT RESULTFORM) &BODY BODY)
  "Iterate BODY with VAR bound to successive integers from 0 up to LIMIT's value.
LIMIT is evaluated only once.  When it is reached, RESULTFORM is executed and returned.
RETURN and GO can be used inside the BODY."
  (IF (FIXNUMP LIMIT)
      `(DO ((,VAR 0 (1+ ,VAR)))
	   (( ,VAR ,LIMIT) ,RESULTFORM)
	 . ,BODY)
    (LET ((ITERATION-VAR (GENSYM)))
      `(DO ((,VAR 0 (1+ ,VAR))
	    (,ITERATION-VAR ,LIMIT))
	   (( ,VAR ,ITERATION-VAR) ,RESULTFORM)
	 . ,BODY))))

(DEFMACRO DOLIST ((VAR LIST RESULTFORM) &BODY BODY)
  "Iterate BODY with VAR bound to successive elements of the value of LIST.
If LIST is exhausted, RESULTFORM is executed and returned.
RETURN and GO can be used inside the BODY."
  (LET ((ITERATION-VAR (GENSYM)))
    `(DO ((,ITERATION-VAR ,LIST (CDR ,ITERATION-VAR))
	  (,VAR ))
	 ((NULL ,ITERATION-VAR) ,RESULTFORM)
       (SETQ ,VAR (CAR ,ITERATION-VAR))
       . ,BODY)))

(DEFMACRO DO-FOREVER (&BODY BODY)
  "Execute BODY until it does a RETURN or a THROW."
  `(DO ()
       (())
     . ,BODY))

(DEFMACRO WITHOUT-INTERRUPTS (&REST BODY)
  "Execute BODY not allowing process-switching or sequence breaks.
If Control-Abort or Control-Break is typed while inside BODY,
it will not take effect until after they are finished."
  `(LET ((INHIBIT-SCHEDULING-FLAG T))
     . ,BODY))

(DEFMACRO WITHOUT-FLOATING-UNDERFLOW-TRAPS (&BODY BODY)
  "Executes BODY with floating-point underflow traps disabled.
If a floating-point operation within body would normally underflow, zero is used instead."
  `(LET ((ZUNDERFLOW T))
     . ,BODY))

(DEFMACRO INHIBIT-GC-FLIPS (&BODY BODY)
  "Execute the BODY making sure no GC flip happens during it."
  `(LET-GLOBALLY ((INHIBIT-GC-FLIPS T))
     . ,BODY))

;;;; WITH-OPEN-STREAM, WITH-OPEN-STREAM-CASE, WITH-OPEN-FILE, WITH-OPEN-FILE-CASE,
;;;;  WITH-OPEN-FILE-SEARCH
(DEFMACRO WITH-OPEN-STREAM ((STREAM CONSTRUCTION-FORM) &BODY BODY)
  "Execute the BODY with the variable STREAM bound to the value of CONSTRUCTOR-FORM.
On normal exit, close STREAM normally.
On abnormal exit (throwing, errors, etc) close STREAM with argument :ABORT."
  (LET ((GENSYM (GENSYM)))
    `(LET ((,GENSYM NIL)
	   (.FILE-ABORTED-FLAG. :ABORT))
       (UNWIND-PROTECT
	   (PROGN (SETQ ,GENSYM ,CONSTRUCTION-FORM)
		  (MULTIPLE-VALUE-PROG1 (LET ((,STREAM ,GENSYM))
					  . ,BODY)
					(SETQ .FILE-ABORTED-FLAG. NIL)))
	 (AND ,GENSYM (NOT (ERRORP ,GENSYM))
	      (SEND ,GENSYM :CLOSE .FILE-ABORTED-FLAG.))))))

(DEFMACRO WITH-OPEN-STREAM-CASE ((STREAM CONSTRUCTION-FORM) &BODY BODY)
  "Use CONSTRUCTOR-FORM to open a stream, using the CLAUSES as in CONDITION-CASE.
The CLAUSES may contain a :NO-ERROR clause which will be executed,
with STREAM bound to the resulting stream, if CONSTRUCTOR-FORM does not get an error.
On normal exit from the :NO-ERROR clause, STREAM is closed normally.
On abnormal exit (throwing, errors, etc) STREAM is closed with argument :ABORT."
  (LET ((GENSYM (GENSYM)))
    `(LET ((,GENSYM NIL)
	   (.FILE-ABORTED-FLAG. ':ABORT))
       (UNWIND-PROTECT
	   (MULTIPLE-VALUE-PROG1
	     (CONDITION-CASE (,STREAM) (SETQ ,GENSYM ,CONSTRUCTION-FORM)
	       . ,BODY)
	     (SETQ .FILE-ABORTED-FLAG. NIL))
	 (AND ,GENSYM (NOT (ERRORP ,GENSYM))
	      (SEND ,GENSYM :CLOSE .FILE-ABORTED-FLAG.))))))

(DEFMACRO WITH-OPEN-FILE ((STREAM FILENAME . OPTIONS) &BODY BODY)
  "Execute the BODY with the variable STREAM bound to a stream for file FILENAME.
FILENAME is opened using OPTIONS, which are the same as for the OPEN function.
On normal exit, close STREAM normally.
On abnormal exit (throwing, errors, etc) close STREAM with argument :ABORT."
  `(WITH-OPEN-STREAM (,STREAM (OPEN ,FILENAME . ,OPTIONS))
     . ,BODY))

(DEFMACRO WITH-OPEN-FILE-CASE ((STREAM FILENAME . OPTIONS) &BODY CLAUSES)
  "Use open a file stream from FILENAME and OPTIONS, using the CLAUSES as in CONDITION-CASE.
FILENAME and OPTIONS are passed to OPEN.
The CLAUSES may contain a :NO-ERROR clause which will be executed,
with STREAM bound to the resulting stream, if OPEN does not get an error.
On normal exit from the :NO-ERROR clause, STREAM is closed normally.
On abnormal exit (throwing, errors, etc) STREAM is closed with argument :ABORT."
  `(WITH-OPEN-STREAM-CASE (,STREAM (OPEN ,FILENAME . ,OPTIONS))
     . ,CLAUSES))

(DEFMACRO WITH-OPEN-FILE-SEARCH (&ENVIRONMENT ENV
				 (STREAM (OPERATION DEFAULTS AUTO-RETRY)
					 TYPE-LIST-AND-PATHNAME-FORM
					 . OPEN-OPTIONS)
				 &BODY BODY)
  "Open one of several filenames, the same except for the type component.
Binds the variable STREAM to the resulting stream, executes the BODY, then closes the stream.
OPEN-OPTIONS are alternating keywords and values, passed to OPEN.
TYPE-LIST-AND-PATHNAME-FORM is evaluated to get two values:
 a list of pathname types to try, and a base pathname.
The base pathname is merged successively with each type in the list.
This is done using FS:MERGE-PATHNAME-DEFAULTS, with DEFAULTS's value
used as the second argument and the type to be tried as the third argument.
As soon as a merged pathname succeeds in being opened, we execute BODY.
If they all fail, an error is signaled with condition FS:MULTIPLE-FILE-NOT-FOUND.
OPERATION should eval to the name of the calling function; it is used for signaling.
If AUTO-RETRY evals to non-NIL, then the user is asked to type a new
pathname to retry with."
  (LET ((BASE-PATHNAME-VAR (GENSYM))
	(TYPE-LIST-VAR (GENSYM))
	(DEFAULTS-VAR (GENSYM))
	(AUTO-RETRY-VAR (GENSYM)))
    (MULTIPLE-VALUE-BIND (REAL DECLS)
	(EXTRACT-DECLARATIONS BODY NIL NIL ENV)
      `(LET ((,DEFAULTS-VAR ,DEFAULTS)
	     (,AUTO-RETRY-VAR ,AUTO-RETRY))
	 (DECLARE . ,DECLS)
	 (MULTIPLE-VALUE-BIND (,TYPE-LIST-VAR ,BASE-PATHNAME-VAR)
	     ,TYPE-LIST-AND-PATHNAME-FORM
	   (DECLARE . ,DECLS)
	   (FILE-RETRY-NEW-PATHNAME-IF ,AUTO-RETRY-VAR (,BASE-PATHNAME-VAR FS:FILE-ERROR)
	     (WITH-OPEN-STREAM (,STREAM
				(FS:OPEN-FILE-SEARCH ,BASE-PATHNAME-VAR ,TYPE-LIST-VAR
						     ,DEFAULTS-VAR ,OPERATION
						     . ,OPEN-OPTIONS))
	       (DECLARE . ,DECLS)
	       . ,REAL)))))))


;;;; FILE-RETRY-NEW-PATHNAME, FILE-RETRY-NEW-PATHNAME-IF, WITH-OPEN-FILE-RETRY

(DEFMACRO FILE-RETRY-NEW-PATHNAME
	  ((PATHNAME-VARIABLE . CONDITION-NAMES) &BODY BODY)
  "Execute BODY with a handler for CONDITION-NAMES that reads a new pathname and tries again.
If one of those conditions is signaled within BODY, 
a new pathname is read and put in PATHNAME-VARIABLE,
and then BODY is executed again.
This is most useful when BODY is an OPEN, DELETEF, etc."
  (LET ((TAG (GENSYM)))
    `(BLOCK ,TAG
       (TAGBODY
	RETRY
	   (RETURN-FROM ,TAG
	     (CATCH-CONTINUATION ',TAG
		 #'(LAMBDA (NEW-PATHNAME) (SETQ ,PATHNAME-VARIABLE NEW-PATHNAME)
			   (GO RETRY))
		 NIL
	       (CONDITION-RESUME `(,',CONDITION-NAMES :NEW-PATHNAME T
				   ("Try again with a new pathname, not telling the callers.")
				   FILE-RETRY-RESUME-HANDLER ,',TAG)
		 (CONDITION-BIND ((,CONDITION-NAMES 'FILE-RETRY-HANDLER
				   ,PATHNAME-VARIABLE ',TAG))
		   . ,BODY))))))))

(DEFUN FILE-RETRY-RESUME-HANDLER (ERROR-OBJECT TAG &OPTIONAL NEW-PATHNAME)
  (DECLARE (IGNORE ERROR-OBJECT))
  (THROW TAG NEW-PATHNAME))

(DEFUN FILE-RETRY-HANDLER (ERROR-OBJECT PATHNAME TAG)
  (FORMAT *QUERY-IO* "~&~A" ERROR-OBJECT)
  (SETQ PATHNAME (FS:PARSE-PATHNAME PATHNAME))
  (LET* ((FS:*ALWAYS-MERGE-TYPE-AND-VERSION* T)
	 (FS:*NAME-SPECIFIED-DEFAULT-TYPE* NIL)
	 (INPUT
	   (PROMPT-AND-READ `(:PATHNAME-OR-END :DEFAULTS ,PATHNAME)
			    "~&Pathname to use instead (default ~A)~%or ~C to enter debugger: "
			    PATHNAME #/END)))
;character lossage (symbol*x lossage --- this SHOULD return the symbol :end)
    (IF (MEMQ INPUT '(#/END #/END))
	NIL
      (THROW TAG INPUT))))

(DEFMACRO FILE-RETRY-NEW-PATHNAME-IF
	  (COND-FORM (PATHNAME-VARIABLE . CONDITION-NAMES) &BODY BODY)
  "Execute BODY with a handler for CONDITION-NAMES that reads a new pathname and tries again.
If COND-FORM evaluates non-NIL, then if one of those conditions is signaled within BODY, 
a new pathname is read and put in PATHNAME-VARIABLE, and then BODY is executed again.
This is most useful when BODY is an OPEN, DELETEF, etc."
  (LET ((TAG (GENSYM)))
    `(BLOCK FILE-RETRY-NEW-PN
       (TAGBODY
	RETRY
	   (RETURN-FROM FILE-RETRY-NEW-PN
	     (CATCH-CONTINUATION ',TAG
		 #'(LAMBDA (NEW-PATHNAME) (SETQ ,PATHNAME-VARIABLE NEW-PATHNAME)
			   (GO RETRY))
		 NIL
	       (CONDITION-RESUME `(,',CONDITION-NAMES :NEW-PATHNAME T
				   ("Try again with a new pathname, not telling the callers.")
				   FILE-RETRY-RESUME-HANDLER ,',TAG)
		 (CONDITION-BIND-IF ,COND-FORM
				    ((,CONDITION-NAMES 'FILE-RETRY-HANDLER
				      ,PATHNAME-VARIABLE ',TAG))
		   . ,BODY))))))))

(DEFMACRO WITH-OPEN-FILE-RETRY ((STREAM (FILENAME . CONDITION-NAMES)
						 . OPTIONS)
					 &BODY BODY)
  "Like WITH-OPEN-FILE, but provides a :NEW-PATHNAME resume handler around the OPEN.
Thus, if the open fails, condition handlers or the user can specify a
new pathname and retry the open."
  `(WITH-OPEN-STREAM (,STREAM
		      (FILE-RETRY-NEW-PATHNAME-IF T (,FILENAME . ,CONDITION-NAMES)
			(OPEN ,FILENAME . ,OPTIONS)))
     . ,BODY))


;;;; FS:READING-FROM-STREAM, FS:READING-FROM-FILE-CASE FS:READING-FROM-FILE-CASE

(DEFUN READING-FROM-STREAM-EXPANDER (FORM STREAM STREAM-CONSTRUCTION-FORM BODY)
  (LET ((AVARS (GENSYM))
	(AVALS (GENSYM)))
    `(WITH-OPEN-STREAM (,STREAM ,STREAM-CONSTRUCTION-FORM)
       (MULTIPLE-VALUE-BIND (,AVARS ,AVALS)
	   (FS:EXTRACT-ATTRIBUTE-BINDINGS ,STREAM)
	 (LET ((.EOF. '(())))
	   (PROGV ,AVARS ,AVALS
	     (DO ((,FORM (CLI:READ ,STREAM NIL .EOF.) (CLI:READ ,STREAM NIL .EOF.)))
		 ((EQ ,FORM .EOF.))
	       ,@BODY)))))))

(DEFMACRO FS:READING-FROM-STREAM ((FORM STREAM-CONSTRUCTION-FORM) &BODY BODY)
  "Read one FORM at a file from FILE, reading till executing BODY each time.
Reads until end of STREAM."
  (READING-FROM-STREAM-EXPANDER FORM (GENSYM) STREAM-CONSTRUCTION-FORM BODY))

(DEFMACRO FS:READING-FROM-FILE ((FORM FILE) &BODY BODY)
  "Read one FORM at a time from FILE, executing BODY each time."
  `(READING-FROM-STREAM (,FORM (OPEN ,FILE :DIRECTION :INPUT :ERROR :REPROMPT))
     ,@BODY))

(DEFMACRO FS:READING-FROM-FILE-CASE ((FORM FILE ERROR) &BODY CLAUSES)
  "Like READING-FROM-FILE, but ERROR is bound to the error instance if
an error happens.  CLAUSES are are like those in WITH-OPEN-FILE-CASE;
:NO-ERROR must appear in one of them."
  ;; The implementation has to search for the clause containing :NO-ERROR
  ;; and wrap a READING-FROM-STREAM around its consequent body.
  ;; ERROR actually is the STREAM in the WITH-OPEN-FILE-CASE, though this
  ;; may change in the future.
  (LET ((NO-ERROR-CLAUSE ()) (FIRST-PART ()))
    (DOLIST (CLAUSE CLAUSES)
      (SETQ FIRST-PART (FIRST CLAUSE))
      (COND ((NULL FIRST-PART)			;Is this really the right thing ?
	     ())
	    ((EQ FIRST-PART :NO-ERROR)
	     (RETURN (SETQ NO-ERROR-CLAUSE CLAUSE)))
	    ((AND (CONSP FIRST-PART)
		  (MEMQ ':NO-ERROR FIRST-PART))
	     (RETURN (SETQ NO-ERROR-CLAUSE CLAUSE)))
	    (T ())))
    (IF (NOT NO-ERROR-CLAUSE)			; A little misleading, I must admit
	(FERROR NIL "~S must have a ~S clause" 'FS:READING-FROM-FILE-CASE ':NO-ERROR)
      (SETQ CLAUSES (DELQ NO-ERROR-CLAUSE (COPY-LIST CLAUSES))) ; Remove :NO-ERROR, 
      `(CONDITION-CASE (,ERROR) (OPEN ,FILE :DIRECTION :INPUT :ERROR ())
	 ,@CLAUSES
	 (,FIRST-PART
	  ,(READING-FROM-STREAM-EXPANDER FORM (GENSYM) ERROR (CDR NO-ERROR-CLAUSE)))))))

(DEFMACRO ONCE-ONLY (VARIABLE-LIST &BODY BODY)
  "Generate code that evaluates certain expressions only once.
This is used in macros, for computing expansions.
VARIABLE-LIST is a list of symbols, whose values are subexpressions
to be substituted into a larger expression.  BODY is what uses those
symbols' values and constructs the larger expression.

ONCE-ONLY modifies BODY so that it constructs a different expression,
which when run will evaluate the subsexpressions only once, save the
values in temporary variables, and use those from then on.
Example:
/(DEFMACRO DOUBLE (ARG) `(+ ,ARG ,ARG)) expands into code that computes ARG twice.
/(DEFMACRO DOUBLE (ARG) (ONCE-ONLY (ARG) `(+ ,ARG ,ARG))) will not."
  (DOLIST (VARIABLE VARIABLE-LIST)
    (IF (NOT (SYMBOLP VARIABLE))
	(FERROR NIL "~S is not a variable" VARIABLE)))
  (LET ((BIND-VARS (GENSYM))
	(BIND-VALS (GENSYM))
	(TEM (GENSYM)))
    `(LET ((,BIND-VARS NIL)
	   (,BIND-VALS NIL))
       (LET ((RESULT ((LAMBDA ,VARIABLE-LIST . ,BODY)
		      . ,(LOOP FOR VARIABLE IN VARIABLE-LIST
			       COLLECT `(IF (OR (ATOM ,VARIABLE)
						(EQ (CAR ,VARIABLE) 'QUOTE)
						(EQ (CAR ,VARIABLE) 'FUNCTION))
					    ,VARIABLE
					  (LET ((,TEM (GENSYM)))
					    (PUSH ,TEM ,BIND-VARS)
					    (PUSH ,VARIABLE ,BIND-VALS)
					    ,TEM))))))
	 (IF (NULL ,BIND-VARS)
	     RESULT
	   `((LAMBDA ,(NREVERSE ,BIND-VARS) ,RESULT) . ,(NREVERSE ,BIND-VALS)))))))

;;; (KEYWORD-EXTRACT <keylist> KEY (FOO (UGH BLETCH) BAR) (FLAG FALG) <otherwise> ...)
;;; parses a list of alternating keywords and values, <keylist>.
;;; The symbol KEY is bound internally to remaineder of the keyword list.
;;; The keywords recognized are :FOO, :BAR and UGH;  whatever follows
;;; the keyword UGH is put in the variable BLETCH, whatever follows the
;;; keyword :FOO is put in the variable FOO, and similar for BAR.
;;; The flags are :FLAG and :FALG;  if :FLAG is seen, FLAG is set to T.
;;; <otherwise> is one or more CASE clauses which can be used
;;; to recognize whatever else you like, in nonstandard format.
;;; To gobble the next thing from the <keylist>, say (CAR (SETQ KEY (CDR KEY))).
(DEFMACRO KEYWORD-EXTRACT (KEYLIST KEYVAR KEYWORDS &OPTIONAL FLAGS &BODY OTHERWISE)
  "Look through KEYLIST for keywords and set some variables and flags.
KEYLIST's value should be a list of keywords, some followed by values.
KEYWORDS describes the keywords to check for.  Each element describes one keyword.
An element can be a list of a keyword and the variable to store its value in,
or just the variable to store in (the keyword has the same pname, in the keyword package).
FLAGS is like KEYWORDS except that the flags are not followed by values;
the variable is set to T if the flag is present at all.

KEYVAR is a variable used internally by the generated code, to hold
the remaining part of the list.
OTHERWISE is some CASE clauses that will be executed if an element of KEYLIST
is not a recognized flag or keyword.  It can refer to KEYVAR."
  `(DO ((,KEYVAR ,KEYLIST (CDR ,KEYVAR)))
       ((NULL ,KEYVAR))
     (CASE (CAR ,KEYVAR)
       ,@(MAPCAR #'(LAMBDA (KEYWORD)
		     (COND ((ATOM KEYWORD)
			    `(,(INTERN (STRING KEYWORD) "KEYWORD")
			      (SETQ ,KEYWORD (CAR (SETQ ,KEYVAR (CDR ,KEYVAR))))))
			   (T `(,(CAR KEYWORD)
				(SETQ ,(CADR KEYWORD)
				      (CAR (SETQ ,KEYVAR (CDR ,KEYVAR))))))))
		 KEYWORDS)
       ,@(MAPCAR #'(LAMBDA (KEYWORD)
		     (COND ((ATOM KEYWORD)
			    `(,(INTERN (STRING KEYWORD) PKG-KEYWORD-PACKAGE)
			      (SETQ ,KEYWORD T)))
			   (T `(,(CAR KEYWORD)
				(SETQ ,(CADR KEYWORD) T)))))
		 FLAGS)
       ,@OTHERWISE
       ,@(IF (NOT (MEMQ (CAAR (LAST OTHERWISE)) '(T OTHERWISE)))
	     `((OTHERWISE
		 (FERROR NIL "~S is not a recognized keyword" (CAR ,KEYVAR))))))))

;;; PROCESS-DEFAULTS is for use in macros which handle keyword arguments
;;; (via KEYWORD-EXTRACT or whatever).
;;;
;;; Usage:
;;;   (PROCESS-DEFAULTS DEFAULT-LIST)
;;;
;;; DEFAULT-LIST is a list of two-element lists.  Each element of the list should
;;; contain the name of a variable to default as its CAR, and the default value
;;; as its CADR.  If the variable is NIL, its value will be set to the default.
;;;
;;; This macro-expands into a series of IF statements (with a SETQ statement as the
;;; consequent).  The variable and default-value names are copied directly into the
;;; SETQ's, so you probably want to quote the values.
;;;
;;; The DEFAULT-LIST is evaluated, so you have to quote it as well if it is constant.

(defmacro process-defaults (default-list)
  `(progn . ,(mapcar #'(lambda (default)
			 (let ((var (car default))
			       (val (cadr default)))
			   `(if (null ,var) (setq ,var ,val))))
		     (eval default-list))))
;;; Bind NAME-TO-BIND to a cleanup-list,
;;; and on exit do any cleanup-actions stored in the list.
;;; The body can pass NAME-TO-BIND to various allocation functions,
;;; which will attach cleanups to the car of the cleanup-list
;;; so that the objects they allocate will be returned.
;;; A cleanup is just a cons of a function and arguments.
;;; the arguments are not evaluated.
(DEFMACRO WITH-CLEANUP-LIST (&ENVIRONMENT ENV NAME-TO-BIND &BODY BODY)
  (MULTIPLE-VALUE-BIND (REAL DECLS)
      (EXTRACT-DECLARATIONS BODY NIL NIL ENV)
    `(LET ((,NAME-TO-BIND (LIST NIL)))
       (DECLARE . ,DECLS)
       (UNWIND-PROTECT
	   (PROGN . ,REAL)
	 (LOOP FOR ELEM IN (CAR ,NAME-TO-BIND)
			   DO (APPLY (CAR ELEM) (CDR ELEM)))))))

;;; Add a cleanup to a list, returns the cleanup object.
(DEFUN ADD-CLEANUP (CLEANUP-LIST FUNCTION &REST ARGS)
  (WITHOUT-INTERRUPTS
    (PUSH (CONS FUNCTION (COPYLIST ARGS))
	  (CAR CLEANUP-LIST))
    (CAAR CLEANUP-LIST)))

;;; Delete a cleanup from a list
(DEFUN DELETE-CLEANUP (CLEANUP CLEANUP-LIST)
  (WITHOUT-INTERRUPTS
    (SETF (CAR CLEANUP-LIST) (DELQ CLEANUP (CAR CLEANUP-LIST)))))

;;; Move a specific cleanup action from one cleanup-list to another, atomically.
(DEFUN MOVE-CLEANUP (CLEANUP FROM-CLEANUP-LIST TO-CLEANUP-LIST)
  (WITHOUT-INTERRUPTS
    (SETF (CAR FROM-CLEANUP-LIST) (DELQ CLEANUP (CAR FROM-CLEANUP-LIST)))
    (PUSH CLEANUP (CAR TO-CLEANUP-LIST))))

;;; Replace one cleanup with another, atomically.
(DEFUN REPLACE-CLEANUP (OLD-CLEANUP NEW-CLEANUP CLEANUP-LIST)
  (WITHOUT-INTERRUPTS
    (SETF (CAR CLEANUP-LIST) (CONS NEW-CLEANUP (DELQ OLD-CLEANUP (CAR CLEANUP-LIST))))))

;;;; Quiche

(DEFMACRO UNWIND-PROTECT-CASE ((&OPTIONAL ABORTED-P-VAR) BODY &REST CLAUSES)
  "Execute BODY inside an UNWIND-PROTECT form.
Each element of CLAUSES is a list of the form (<keyword> . <cruft>), where
<keyword> specifies under which condition to execute the associated <cruft>
Each keyword must be one of :ALWAYS, meaning to execute the cruft regardless
of whether BODY is exited non-locally or terminates normally,
:ABORT meaning to execute it only if BODY exits non-locally, or
:NORMAL meaning do it only if BODY returns /"normally./"
ABORTED-P-VAR, if supplied, is used to flag whether BODY exited abnormally:
 it is normally set to NIL by successful execution of BODY, but may be set to
 NIL within BODY, meaning not to execute :ABORT clauses even if BODY later exits abnormally.
The values returned are those of BODY.

This macro is for wimps who can't handle raw, manly UNWIND-PROTECT"
  (OR ABORTED-P-VAR (SETQ ABORTED-P-VAR '.ABORTED-P.))
  `(LET ((,ABORTED-P-VAR T))
     (UNWIND-PROTECT
	 (MULTIPLE-VALUE-PROG1 ,BODY (SETQ ,ABORTED-P-VAR NIL))
       ,@(LOOP FOR (KEYWORD . FORMS) IN CLAUSES
	       COLLECT (ECASE KEYWORD
			 (:NORMAL `(WHEN (NOT ,ABORTED-P-VAR) ,@FORMS))
			 (:ABORT `(WHEN ,ABORTED-P-VAR ,@FORMS))
			 (:ALWAYS `(PROGN ,@FORMS)))))))

;;; WITH-HELP-STREAM sets up a stream for printing a long help message.
;;; This is a pop-up window (like FINGER windows) if the parent stream is a window,
;;; otherwise the stream is simply the parent stream (this avoids lossage if the
;;; stream is a file stream or the cold-load stream.).
;;;
;;; Usage:
;;;   (WITH-HELP-STREAM (STREAM . OPTIONS) &BODY BOD)
;;;
;;; STREAM is a symbol to assign the new stream to.  Output operations in the body
;;; (PRINT, FORMAT, etc.) should use this symbol as the stream argument.
;;;
;;; OPTIONS is a keyword argument list.  The following options are recognized:
;;;   :LABEL     Label to give the help window.  Default is a null string.
;;;   :WIDTH     Symbol to take on the value of the width in characters of the stream.
;;;              An internal symbol is used (and ignored) if none is specified.
;;;   :HEIGHT    Symbol to take on the value of the height in characters of the stream.
;;;              An internal symbol is used (and ignored) if none is specified.
;;;   :SUPERIOR  The superior stream.  Defaults to *TERMINAL-IO*.

(defmacro with-help-stream (&environment env (stream . options) &body bod
			    &aux label width height superior)
  "Execute the BODY with STREAM bound to a stream for printing help text on.
If *TERMINAL-IO* or the specified superior is a window, a special /"help window/"
is popped up and used as STREAM. 
If *TERMINAL-IO* or the specified superior is not a window, it is used directly.
OPTIONS is a list of alternating keywords and values.
 :LABEL's value is a string to use as the label of the help window if one is used.
 :WIDTH's value is a symbol to bind to the width in characters of STREAM.
  It is bound while BODY is executed.
 :HEIGHT's value is a symbol to bind to the height in characters.
 :SUPERIOR's value is a window to use as the superior of the help window."
  (keyword-extract options *with-help-iter* (label width height superior) nil)
  (process-defaults '((label "") (width '*with-help-width*)
		      (height '*with-help-height*) (superior '*terminal-io*)))
  (multiple-value-bind (real decls)
      (extract-declarations bod nil nil env)
    `(with-help-stream-1 ,label ,superior
			 #'(lambda (,stream &aux ,width ,height)
			     (declare . ,decls)
			     (if (send ,stream :operation-handled-p :size-in-characters)
				 (multiple-value-setq (,width ,height)
				   (send ,stream :size-in-characters))
			       (setq ,width 85. ,height 66.))
			     . ,real))))

(defun with-help-stream-1 (label superior body-function &aux input-p)
  (cond ((typep superior 'tv:sheet)
	 (using-resource (stream tv::pop-up-finger-window)
	   (lexpr-send stream :set-edges (multiple-value-list (send superior :edges)))
	   (send stream :set-label label)
	   (tv::window-call (stream :deactivate)
	     (send stream :clear-window)
	     (funcall body-function stream)
	     (format stream "~2&Type any character to continue: ")
	     (send stream :wait-for-input-or-deexposure)
	     ;; This hair is so that if we woke up due to deexposure
	     ;; we do not try to read anything;
	     ;; if we woke up due to input, we do not read until after
	     ;; we deactivate the help window, so that if the input is Break
	     ;; the break-loop is not entered until our normal window is usable again.
	     (if (and (send stream :exposed-p)
		      (send stream :listen))
		 (setq input-p t)))
	   (if input-p
	       (send (if (send superior :operation-handled-p :tyi-no-hang)
			 superior
		         *terminal-io*)
		     :tyi-no-hang))))
	(t (funcall body-function superior))))

;;;; Macros relating to warnings (compiler, etc).

;;; Variables bound by the following macros.
(PROCLAIM '(SPECIAL OBJECT-WARNINGS-DATUM OBJECT-WARNINGS-LOCATION-FUNCTION
		    OBJECT-WARNINGS-OBJECT-NAME
		    OBJECT-WARNINGS-PUSHING-LOCATION)
	  '(SPECIAL FILE-WARNINGS-DATUM FILE-WARNINGS-PATHNAME
		    FILE-WARNINGS-PUSHING-LOCATION
		    PREMATURE-WARNINGS PREMATURE-WARNINGS-THIS-OBJECT))
;;; Use this around an operation that goes through some or all the objects in a file.
;;; WHOLE-FILE-P should evaluate to T if we are doing the entire file.
(DEFMACRO FILE-OPERATION-WITH-WARNINGS ((GENERIC-PATHNAME OPERATION-TYPE WHOLE-FILE-P)
					&BODY BODY)
  "Execute BODY, recording warnings for performing OPERATION-TYPE on file GENERIC-PATHNAME.
WHOLE-FILE-P should evaluate to non-NIL if the body will process all of the file.
OPERATION-TYPE is most frequently ':COMPILE, in the compiler."
  `(LET* ((FILE-WARNINGS-DATUM FILE-WARNINGS-DATUM)
	  (FILE-WARNINGS-PATHNAME FILE-WARNINGS-PATHNAME)
	  (FILE-WARNINGS-PUSHING-LOCATION FILE-WARNINGS-PUSHING-LOCATION)
	  (PREMATURE-WARNINGS PREMATURE-WARNINGS)
	  (PREMATURE-WARNINGS-THIS-OBJECT PREMATURE-WARNINGS-THIS-OBJECT)
	  (NEW-FILE-THIS-LEVEL
	    (BEGIN-FILE-OPERATION ,GENERIC-PATHNAME ,OPERATION-TYPE)))
     (MULTIPLE-VALUE-PROG1
       (PROGN . ,BODY)
       (DISPOSE-OF-WARNINGS-AFTER-LAST-OBJECT)
       (AND ,WHOLE-FILE-P NEW-FILE-THIS-LEVEL (END-FILE-OPERATION)))))

;;; Use this around operating on an individual object,
;;; inside (dynamically) a use of the preceding macro.
(DEFMACRO OBJECT-OPERATION-WITH-WARNINGS ((OBJECT-NAME LOCATION-FUNCTION INCREMENTAL)
					  &BODY BODY)
  "Execute BODY, recording warnings for OBJECT-NAME.
If INCREMENTAL evaluates to NIL, all previous warnings about that object
are discarded when the body is finished.  OBJECT-NAME is the name
of an object in the file set up with FILE-OPERATION-WITH-WARNINGS;
each file is its own space of object names, for recording warnings.
This macro's expansion must be executed inside the body of a
FILE-OPERATION-WITH-WARNINGS.  LOCATION-FUNCTION's value tells the editor
how to find this object's definition in the file; usually it is NIL."
  `(LET-IF (NOT (EQUAL ,OBJECT-NAME OBJECT-WARNINGS-OBJECT-NAME))
	   ((OBJECT-WARNINGS-DATUM OBJECT-WARNINGS-DATUM)
	    (OBJECT-WARNINGS-LOCATION-FUNCTION OBJECT-WARNINGS-LOCATION-FUNCTION)
	    (OBJECT-WARNINGS-OBJECT-NAME OBJECT-WARNINGS-OBJECT-NAME)
	    (OBJECT-WARNINGS-PUSHING-LOCATION OBJECT-WARNINGS-PUSHING-LOCATION))
     (LET ((NEW-OBJECT-THIS-LEVEL
	     (BEGIN-OBJECT-OPERATION ,OBJECT-NAME ,LOCATION-FUNCTION)))
       (MULTIPLE-VALUE-PROG1
	 (PROGN . ,BODY)
	 (AND ,(NOT INCREMENTAL) NEW-OBJECT-THIS-LEVEL (END-OBJECT-OPERATION))))))


;;;; WITH-INPUT-FROM-STRING, WITH-OUTPUT-TO-STRING

(defmacro with-input-from-string (&environment env (stream string . keyword-args) &body body)
  "Execute BODY with STREAM bound to a stream to output into STRING.
The values of BODY's last expression are returned.
Keywords allowed are :START, :END and :INDEX.
:START and :END can be used to specify a substring of STRING to be read from.
 Eof will then occur when :END is reached.
 If the :END value is NIL, that means the end of STRING.
:INDEX specifies a SETF-able place to store the index of where reading stopped.
 This is done after exit from the body.  It stores the index of the first unread character,
 or the index of eof if that was reached.

Old calling format: (STREAM STRING &OPTIONAL INDEX END), where INDEX serves
 as the value for the :START keyword and for the :INDEX keyword."
  (let (start end index decls realbody)
    (setf (values realbody decls)
	  (extract-declarations body nil nil env))
    (if (keywordp (car keyword-args))
	(setq start (getf keyword-args :start)
	      index (getf keyword-args :index)
	      end (getf keyword-args :end))
      (setq start (car keyword-args)
	    index (car keyword-args)
	    end (cadr keyword-args)))
    `(let ((,stream (make-string-input-stream ,string ,(or start 0) ,end)))
       (declare . ,decls)
       (unwind-protect
	   (progn . ,realbody)
	 ,(if index `(setf ,index (send ,stream :get-string-index)))))))

(defmacro with-output-to-string (&environment env (stream string index) &body body)
  "Execute BODY with STREAM bound to a stream to output into STRING.
If STRING is omitted, a new string with no fill pointer is created and returned.
If STRING is supplied, that string's contents are modified destructively,
and the values of BODY's last expression are returned.
If INDEX is supplied, it should be a SETFable accessor which describes
where to find the index to store into STRING, instead of at the end.
The value of INDEX will be updated after the BODY is finished."
  (multiple-value-bind (realbody decls)
      (extract-declarations body nil nil env)
    (if string
	`(let ((,stream (make-string-output-stream ,string ,index)))
	   (declare . ,decls)
	   (unwind-protect
	       (progn . ,realbody)
	     ,(if index `(setf ,index (send ,stream ':get-string-index)))))
      `(let ((,stream (make-string-output-stream)))
	 (declare . ,decls)
	 ,@realbody
	 (get-output-stream-string ,stream)))))

(defmacro with-input-editing ((stream rubout-options . brand-s-compatibility-args)
			      &body body)
  "Execute BODY inside of STREAM's :RUBOUT-HANDLER method.
If BODY does input from STREAM, it will be done with rubout processing
if STREAM implements any.
RUBOUT-OPTIONS should be the options for the :RUBOUT-HANDLER message, such as 
 (:NO-INPUT-SAVE T)   -- don't save this batch of input in the history.
 (:FULL-RUBOUT flag)  -- return from this construct if rubout buffer becomes empty
	with two values: NIL and flag.
 (:INITIAL-INPUT string) -- start out with that string in the buffer.
 (:INITIAL-INPUT-POINTER n) -- start out with editing pointer n chars from start.
 (:ACTIVATION fn x-args) -- fn is used to test characters for being activators.
	fn's args are the character read followed by the x-args from the option.
        If fn returns non-NIL, the character is an activation.
	It makes a blip (:ACTIVATION char numeric-arg)
	which BODY can read with :ANY-TYI.
 (:DO-NOT-ECHO chars...) -- poor man's activation characters.
	This is like the :ACTIVATION option except that: characters are listed explicitly;
	and the character itself is returned when it is read,
	rather than an :ACTIVATION blip.
 (:COMMAND fn x-args) -- tests like :ACTIVATION, but command chars do a different thing.
	If fn returns non-NIL, the character is a command character.
	The :RUBOUT-HANDLER operation (and therefore the WITH-INPUT-EDITING)
	returns instantly these two values: (:COMMAND char numeric-arg) :COMMAND.
	The input that was buffered remains in the buffer.
 (:PREEMPTABLE token) -- makes all blips act like command chars.
	If the rubout handler encounters a blip while reading input,
	it instantly returns two values: the blip itself, and the specified token.
	Any buffered input remains buffered for the next request for input editing.
 (:EDITING-COMMAND (char doc)...) -- user-implemented /"editing/" commands.
	If any char in the alist is read by the rubout handler,
	it is returned to the caller (that is, to an :ANY-TYI in BODY).
	BODY should process these characters in appropriate ways and keep reading.
 (:PASS-THROUGH chars...) -- makes chars not be treated specially by the rubout
	handler. Useful for getting characters such as  into the buffer.
	Only works for characters with no control, meta, etc bits set.
 (:PROMPT fn-or-string)
	Says how to prompt initially for the input.
	If a string, it is printed; otherwise it is called with two args,
	the stream and a character which is an editing command that says
	why the prompt is being printed.
 (:REPROMPT fn-or-string)
	Same as :PROMPT except used only if the input is reprinted
	for some reason after editing has begun.  The :REPROMPT option
	is not used on initial entry.  If both :PROMPT and :REPROMPT
        are specified, :PROMPT is used on initial entry and :REPROMPT thereafter.
 (:NONRECURSIVE T)
	Means to ignore previously-specified rubout-handler options and only use the
	options specified to this call to WITH-INPUT-EDITING."
  (declare (arglist (stream rubout-handler-options) &body body))
  (let ((keyword (cadr brand-s-compatibility-args))
	(strmvar (gensym)))
    `(flet ((.do.it. () . ,body))
       (let ((,strmvar (decode-read-arg ,stream)))
	 (if (send ,strmvar :operation-handled-p :rubout-handler)
	     ,(if keyword
		  `(with-stack-list* (options
				       ',(case keyword
					   (:end-activation '(:activation = #/End))
					   ((:line :line-activation)
					    '(:activation memq (#/End #/Return))))
				       ,rubout-options)
		     (send ,strmvar :rubout-handler options #'.do.it.))
		`(send ,strmvar :rubout-handler ,rubout-options #'.do.it.))
	   (let ((rubout-handler nil))
	     (.do.it.)))))))

(DEFMACRO WITH-LOCK ((LOCATOR . OPTIONS) &BODY BODY &AUX NORECURSIVE NOERROR)
  "Execute the BODY with a lock locked.
LOCATOR is an expression whose value is the lock status;
it should be suitable for use inside LOCF.
OPTIONS include :NORECURSIVE, do not allow locking a lock already locked by this process."
  ;; Ignore the old :NOERROR option -- it's always that way now.
  (KEYWORD-EXTRACT OPTIONS O () (NORECURSIVE NOERROR) (OTHERWISE NIL))
  `(LET* ((.POINTER. (LOCF ,LOCATOR))
	  (.ALREADY.MINE. (EQ (CAR .POINTER.) CURRENT-PROCESS)))
     (IF (CONSP .POINTER.)
	 (SETQ .POINTER. (CDR-LOCATION-FORCE .POINTER.)))
     (UNWIND-PROTECT
	 (PROGN (IF .ALREADY.MINE.
		    ,(IF NORECURSIVE `(FERROR NIL "Attempt to lock ~S recursively."
					      ',LOCATOR))
		  ;; Redundant, but saves time if not locked.
		  (OR (%STORE-CONDITIONAL .POINTER. NIL CURRENT-PROCESS)
		      (PROCESS-LOCK .POINTER.)))
		. ,BODY)
       (UNLESS .ALREADY.MINE.
	 (%STORE-CONDITIONAL .POINTER. CURRENT-PROCESS NIL)))))

(DEFMACRO WITH-TIMEOUT ((DURATION . TIMEOUT-FORMS) &BODY BODY)
  "Execute BODY with a timeout set for DURATION 60'ths of a second from time of entry.
If the timeout elapses while BODY is still in progress,
the TIMEOUT-FORMS are executed and their values returned, and
whatever is left of BODY is not done, except for its UNWIND-PROTECTs.
If BODY returns, is values are returned and the timeout is cancelled.
The timeout is also cancelled if BODY throws out of the WITH-TIMEOUT."
  `(LET ((.PROC. (PROCESS-RUN-FUNCTION "WITH-TIMEOUT"
				       'WITH-TIMEOUT-INTERNAL
				       ,DURATION CURRENT-PROCESS)))
     (CONDITION-CASE ()
	 (UNWIND-PROTECT
	   (PROGN . ,BODY)
	   (PROCESS-RESET .PROC.))
       (TIMEOUT
	. ,TIMEOUT-FORMS))))

(DEFMACRO WITH-SYS-HOST-ACCESSIBLE (&BODY BODY)
  "Execute the BODY, making sure we can read files without user interaction.
This is done by logging in if necessary (and logging out again when done)."
  `(LET (UNDO-FORM)
     (UNWIND-PROTECT
	 (PROGN (SETQ UNDO-FORM (MAYBE-SYS-LOGIN))
		. ,BODY)
       (EVAL UNDO-FORM))))

;; mucklisp array stuff (store, get-locative-pointer-into-array, arraycall)
;;  moved into sys2; macarr