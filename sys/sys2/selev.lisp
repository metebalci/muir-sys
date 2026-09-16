;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Readtable:ZL; Base:10 -*-

;;; Macros to do things similar to BLISS' SELECT.

(DEFMACRO COND-EVERY (&BODY CLAUSES)
  "COND-EVERY has a COND-like syntax.  Unlike COND, though, it executes all the
clauses whose tests succede.  It also recognizes two special keywords (instead of
a test):  :ALWAYS executes in all cases, and :OTHERWISE executes if no previous
clause has executed.  The value returned is that of the last clause executed,
or NIL if no clauses executed,  and the macro will not return multiple-values."
  (LET ((FLAG (GENSYM))
	(VALUE (GENSYM)))
    `(LET ((,FLAG) (,VALUE))
       ,@(DO ((CS CLAUSES (CDR CS))
	      (CLAUSE (CAR CLAUSES) (CADR CS))
	      (FORMS NIL)
	      (SEEN-OTHERWISE-OR-ALWAYS))
	     ((NULL CS) (NREVERSE FORMS))
	   (PUSH
	    (CASE (CAR CLAUSE)
	      ((:ALWAYS T ALWAYS)
	       (SETQ SEEN-OTHERWISE-OR-ALWAYS ':ALWAYS)
	       `(SETQ ,VALUE (PROGN . ,(CDR CLAUSE))))
	      ((:OTHERWISE OTHERWISE)
	       (IF SEEN-OTHERWISE-OR-ALWAYS
		   (FERROR NIL ":OTHERWISE after a previous :OTHERWISE or :ALWAYS")
		   (SETQ SEEN-OTHERWISE-OR-ALWAYS ':OTHERWISE)
		   `(OR ,FLAG
			(SETQ ,VALUE (PROGN . ,(CDR CLAUSE))))))
	      (OTHERWISE
	       `(AND ,(CAR CLAUSE)
		     (SETQ ,VALUE (PROGN . ,(CDR CLAUSE))
			   . ,(IF SEEN-OTHERWISE-OR-ALWAYS
				  NIL
				  `(,FLAG T))))))
	    FORMS))
       ,VALUE)))

(DEFMACRO SELECTQ-EVERY (OBJ &BODY CLAUSES)
  "Just like COND-EVERY but with SELECTQ-like syntax."
  (IF (ATOM OBJ)
      (SELECTQ-EVERY-GENERATE-CODE OBJ CLAUSES)
      (LET ((SYM (GENSYM)))
	`(LET ((,SYM ,OBJ))
	   ,(SELECTQ-EVERY-GENERATE-CODE SYM CLAUSES)))))

(DEFUN SELECTQ-EVERY-GENERATE-CODE (COMPARE-AGAINST CLAUSES)
  `(COND-EVERY
    . ,(DO ((CS CLAUSES (CDR CS))
	    (CLAUSE (CAR CLAUSES) (CADR CS))
	    (FORMS NIL))
	   ((NULL CS) (NREVERSE FORMS))
	   (PUSH
	    (COND ((MEMQ (CAR CLAUSE) '(:OTHERWISE :ALWAYS OTHERWISE ALWAYS T))
		   CLAUSE)
		  (T
		   `((,(IF (CONSP (CAR CLAUSE)) 'MEMQ 'EQ) ,COMPARE-AGAINST ',(CAR CLAUSE))
		     . ,(CDR CLAUSE))))
	    FORMS))))

;;;; SELECT-MATCH
#||
The syntax is 
   (SELECT-MATCH <object>
     (`<pattern> <condition> <sexp> ... <sexp>)
     (`<pattern> <condition> <sexp> ... <sexp>)
     ...
     (`<pattern> <condition> <sexp> ... <sexp>)
     (OTHERWISE <sexp> ... <sexp>))

The value of <object> is matched against the <pattern>s one at a time until a
match succeeds and the accompanying <condition> evaluates to something
non-null, at which point the <sexp>'s associated with the <pattern> and
<condition> are evaluated one at a time and the last value is returned.  The
<pattern>s can be arbitrary s-expressions, with variables signified by
,variable.  When the pattern is matched against the <object>'s value, the
variables are to bound to their matched values.  Different occurences of the
same variable in a given pattern must match to the same thing, so that

    (SELECT-MATCH '(A B C) 
      (`(,X B ,X) T 'LOSE)
      (`(,X B ,Y) T 'WIN)
      (OTHERWISE 'LOSE-BIG))

returns WIN.  The variables mentioned in the <pattern>s need not be bound by
the user; they are bound by the expression resulting from the expansion of the
macro.  (The variable ,IGNORE matches everything and doesn't become bound.
Using ,IGNORE for a variable you don't intend to make any use of avoids
"bound but not used" warnings from the compiler.)

The patterns are expanded into code to test their predicates and set their variables.
The example above expands into this code (which, surprisingly, compiles very well).

(LET ((#:G0036 '(A B C))
      X
      Y)
  (COND ((MATCHCARCDR #:G0036
		      (LAMBDA (OBJ)
			(PROGN (SETQ X OBJ)
			       T))
		      (LAMBDA (OBJ)
			(MATCHCARCDR OBJ
				     (LAMBDA (OBJ)
				       (EQUAL OBJ 'B))
				     (LAMBDA (OBJ)
				       (MATCHCARCDR OBJ
						    (LAMBDA (OBJ)
						      (EQUAL OBJ X))
						    (LAMBDA (OBJ)
						      (NULL OBJ)))))))
         'LOSE)
        ((MATCHCARCDR #:G0036
		      (LAMBDA (OBJ)
			(PROGN (SETQ X OBJ)
			       T))
		      (LAMBDA (OBJ)
			(MATCHCARCDR OBJ
				     (LAMBDA (OBJ)
				       (EQUAL OBJ 'B))
				     (LAMBDA (OBJ)
				       (MATCHCARCDR OBJ
						    (LAMBDA (OBJ)
						      (PROGN (SETQ Y OBJ)
							     T))
						    (LAMBDA (OBJ)
						      (NULL OBJ)))))))
         'WIN)
        (T 'LOSE-BIG)))

||#

(DEFMACRO SELECT-MATCH (OBJECT &BODY CLAUSES)
  (DECLARE (ZWEI:INDENTATION 1 1))		;indents like CASE
  "Execute the first clause whose pattern matches the value of OBJECT.
The syntax is 

   (SELECT-MATCH OBJECT
     (`PATTERN CONDITION CLAUSE-BODY...)
     (`PATTERN CONDITION CLAUSE-BODY...)
     ...
     (`PATTERN CONDITION CLAUSE-BODY...)
     (OTHERWISE CLAUSE-BODY...)

The value of OBJECT is matched against the PATTERNs one at a time until a
match succeeds and the accompanying CONDITION evaluates to non-NIL.
Then the CLAUSE-BODY of that clause is executed and its last expression's
value is returned.

,VARIABLE can appear in a pattern; it matches anything, and the variable
is bound to what it matched for the execution of the CONDITION and CLAUSE-BODY.
If one variable appears twice in a pattern, it must match EQUAL objects
in both occurrences:
    (SELECT-MATCH '(A B C) 
      (`(,X B ,X) T 'LOSE)
      (`(,X B ,Y) T 'WIN)
      (OTHERWISE 'LOSE-BIG))
returns WIN.  Use ,IGNORE to match anything and not use it."
  (LET* (BOUNDVARS
	 (GENVAR (GENSYM))
	 (CLAUSES (MAPCAR #'SELECT-MATCH-CLAUSE CLAUSES (CIRCULAR-LIST GENVAR))))
    (DECLARE (SPECIAL BOUNDVARS))
    `(LET ((,GENVAR ,OBJECT) . ,BOUNDVARS)
       (COND ,@CLAUSES))))

(DEFMACRO LIST-MATCH-P (LIST PATTERN)
  "T if the value of LIST matches PATTERN.  PATTERN is a backquote expression.
Constant parts of PATTERN are matched against the corresponsing parts of LIST.
Variables preceded by commas are SETQ'd to the corresponding parts of LIST.
If the same variable appears twice, it must match EQUAL objects both times.
Example: (LIST-MATCH-P '(FOO BAR BAR) `(FOO ,X ,X)) returns T and sets X to BAR."
  (LET (BOUNDVARS)
    (DECLARE (SPECIAL BOUNDVARS))
    (SELECT-MATCH-MATCHITEMS PATTERN LIST)))

;;; Return the COND clause corresponding to one SELECT-MATCH clause.
;;; Merges any pattern variables used into BOUNDVARS.
(DEFUN SELECT-MATCH-CLAUSE (CLAUSE OBJECTVAR)
  (IF (MEMQ (CAR CLAUSE) '(OTHERWISE :OTHERWISE T))
      `(T . ,(CDR CLAUSE))
    (LET ((PATCOND (SELECT-MATCH-MATCHITEMS (CAR CLAUSE) OBJECTVAR)))
      `((AND ,(IF (EQ (CADR CLAUSE) 'T)
		  PATCOND
		  `(AND ,PATCOND ,(CADR CLAUSE))))
	. ,(CDDR CLAUSE)))))

;;; MATCHCARCDR evals ARG, tests its car with CAR (a function of one arg)
;;; and its cdr with CDR.  The COMPILER::P1 property below takes care
;;; of open coding it with very fast code.
(DEFUN MATCHCARCDR (&QUOTE ARG CAR CDR)
  (LET ((ARGVAL (EVAL1 ARG)))
    (AND (CONSP ARGVAL)
	 (FUNCALL CAR (CAR ARGVAL))
	 (FUNCALL CDR (CDR ARGVAL)))))

(DEFUN (MATCHCARCDR COMPILER::P1) (FORM)
  (LET ((CAREXP (MATCHCARCDR-CONVERT-LAMBDA (CADDR FORM))))
    (COND ((EQ (CAR CAREXP) 'EQUAL)
	   `(AND (COMPILER::PUSH-CDR-IF-CAR-EQUAL ,(COMPILER::P1 (CADR FORM))
						  ,(COMPILER::P1 (CADDR CAREXP)))
		 ,(COMPILER::P1 (MATCHCARCDR-CONVERT-LAMBDA (CADDDR FORM)))))
	  ((AND (EQ (CAR CAREXP) 'PROGN)
		(EQ (CAR (CADR CAREXP)) 'SETQ))
	   (COMPILER::P1SETVAR (CADR (CADR CAREXP)))
	   `(AND (COMPILER::PUSH-CDR-STORE-CAR-IF-CONS ,(COMPILER::P1 (CADR FORM))
						       ,(COMPILER::P1 (CADR (CADR CAREXP))))
		 ,(COMPILER::P1 (MATCHCARCDR-CONVERT-LAMBDA (CADDDR FORM)))))
	  (T
	   `(AND (CONSP-OR-POP ,(COMPILER::P1 (CADR FORM)))
		 (PROGN (%PUSH (CARCDR (%POP)))
			(COND (,(COMPILER::P1 CAREXP)
			       ,(COMPILER::P1 (MATCHCARCDR-CONVERT-LAMBDA (CADDDR FORM))))
			      ('T (%POP) 'NIL))))))))

(DEFUN MATCHCARCDR-CONVERT-LAMBDA (LAMBDA-EXP)
  (LET ((ARGNAME (CAR (CADR LAMBDA-EXP))))
    (IF (AND (CONSP (THIRD LAMBDA-EXP))
	     (EQ (SECOND (THIRD LAMBDA-EXP))
		 ARGNAME))
	(LIST* (FIRST (THIRD LAMBDA-EXP)) '(%POP) (CDDR (THIRD LAMBDA-EXP)))
      (IF (AND (CONSP (THIRD LAMBDA-EXP))
	       (EQ (FIRST (THIRD LAMBDA-EXP)) 'PROGN)
	       (EQ (FIRST (SECOND (THIRD LAMBDA-EXP))) 'SETQ))
	  `(PROGN (SETQ ,(SECOND (SECOND (THIRD LAMBDA-EXP))) (%POP)) T)
	`(PROGN (%POP) ,(THIRD LAMBDA-EXP))))))

;;; Note that MATCHCARCDR-CONVERT-LAMBDA knows exactly what kinds of
;;; expressions this function can generate.
(DEFUN SELECT-MATCH-MATCHITEMS (PATT EXPR)
  (DECLARE (SPECIAL BOUNDVARS))
  (COND ((EQ (CAR-SAFE PATT) 'XR-BQ-CONS)
	 `(MATCHCARCDR ,EXPR
		       (LAMBDA (OBJ) ,(SELECT-MATCH-MATCHITEMS (CADR PATT) 'OBJ))
		       (LAMBDA (OBJ) ,(SELECT-MATCH-MATCHITEMS (CADDR PATT) 'OBJ))))
	((EQ (CAR-SAFE PATT) 'XR-BQ-LIST)
	 (LET ((EXP '(NULL OBJ))
	       (ELTMATCHES (MAPCAR #'SELECT-MATCH-MATCHITEMS
				   (CDR PATT) (CIRCULAR-LIST 'OBJ))))
	   (LOOP FOR ELTMATCH IN (REVERSE ELTMATCHES)
		 DO (SETQ EXP `(MATCHCARCDR OBJ
					    (LAMBDA (OBJ) ,ELTMATCH)
					    (LAMBDA (OBJ) ,EXP))))
	   `(MATCHCARCDR ,EXPR . ,(CDDR EXP))))
	((EQ (CAR-SAFE PATT) 'XR-BQ-LIST*)
	 (LET ((EXP (SELECT-MATCH-MATCHITEMS (CAR (LAST PATT)) 'OBJ)))
	   (LOOP FOR ELT IN (CDR (REVERSE (CDR PATT)))
		 DO (SETQ EXP `(MATCHCARCDR OBJ
					    (LAMBDA (OBJ) ,(SELECT-MATCH-MATCHITEMS ELT 'OBJ))
					    (LAMBDA (OBJ) ,EXP))))
	   `(MATCHCARCDR ,EXPR . ,(CDDR EXP))))
	((MEMQ (CAR-SAFE PATT) '(XR-BQ-APPEND XR-BQ-NCONC XR-BQ-VECTOR))
	 (FERROR NIL "Appending, nconcing or vector construction in SELECT-MATCH pattern."))
	((MEMQ (CAR-SAFE PATT) '(AND OR NOT))
	 `(,(CAR PATT) . ,(MAPCAR #'SELECT-MATCH-MATCHITEMS (CDR PATT) (CIRCULAR-LIST EXPR))))
	((AND (CONSTANTP PATT)
	      (OR (NOT (SYMBOLP PATT)) (EQ PATT (SYMBOL-VALUE PATT))))
	 (IF (CONSP PATT)
	     `(EQUAL ,EXPR ',(CADR PATT))
	     `(EQUAL ,EXPR ',PATT)))
	((SYMBOLP PATT)
	 (COND ((EQ PATT 'IGNORE) T)
	       ((MEMBER-EQUAL PATT BOUNDVARS) `(EQUAL ,EXPR ,PATT))
	       (T (PUSH PATT BOUNDVARS)
		  `(PROGN (SETQ ,PATT ,EXPR) T))))
	(T (FERROR NIL "Unexpected function ~S found in SELECT-MATCH pattern."
		   (CAR PATT)))))

;Note: value is a list of tests, to be ANDed together, rather than one test.
;(DEFUN SELECT-MATCH-MATCHITEMS (PATT EXPR)
;  (DECLARE (SPECIAL BOUNDVARS))
;  (COND	((NULL PATT) `((NULL ,EXPR)))
;	((SYMBOLP PATT)
;	 (COND ((EQ PATT 'IGNORE) NIL)
;	       ((MEMBER-EQUAL PATT BOUNDVARS) `(EQUAL ,PATT ,EXPR))
;	       (T (PUSH PATT BOUNDVARS)
;		  `(PROGN (SETQ ,PATT ,EXPR) T))))
;	((EQ (CAR PATT) 'XR-BQ-CONS)
;	 (CONS `(CONSP ,EXPR)
;	       (APPEND (SELECT-MATCH-MATCHITEMS (CADR PATT) `(CAR-SAFE ,EXPR))
;		       (SELECT-MATCH-MATCHITEMS (CADDR PATT) `(CDR-SAFE ,EXPR)))))
;	((EQ (CAR PATT) 'XR-BQ-LIST)
;	 (LIST* `(CONSP ,EXPR)
;		`(NULL (NTHCDR-SAFE ,(LENGTH (CDR PATT)) ,EXPR))
;		(LOOP FOR I = 0 THEN (1+ I)
;		      FOR ELT IN (CDR PATT)
;		      APPEND (SELECT-MATCH-MATCHITEMS ELT `(NTH-SAFE ,I ,EXPR)))))
;	((EQ (CAR PATT) 'XR-BQ-LIST*)
;	 (LIST* `(CONSP ,EXPR)
;		(APPEND
;		  (LOOP FOR I = 0 THEN (1+ I)
;			FOR ELT IN (BUTLAST (CDR PATT))
;			APPEND (SELECT-MATCH-MATCHITEMS ELT `(NTH-SAFE ,I ,EXPR)))
;		  (SELECT-MATCH-MATCHITEMS (CAR (LAST PATT))
;					   `(NTHCDR-SAFE ,(1- (LENGTH (CDR PATT))) ,EXPR)))))
;	((EQ (CAR PATT) 'QUOTE)
;	 `((EQUAL ,EXPR ',(CADR PATT))))
;	((MEMQ (CAR PATT) '(XR-BQ-APPEND XR-BQ-NCONC XR-BQ-VECTOR))
;	 (FERROR NIL "Appending, nconcing or vector construction in SELECT-MATCH pattern."))
;	(T (FERROR NIL "Unexpected function ~S found in SELECT-MATCH pattern."
;		   (CAR PATT)))))
