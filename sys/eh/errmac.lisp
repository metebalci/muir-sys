;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Readtable:ZL; Base:10 -*-

;; Condition and error related macros used by the system.
;; Used to be in SYS2; LMMAC

(DEFMACRO CONDITION-CASE (VARIABLES BODY-FORM &BODY CLAUSES)
  "Execute BODY-FORM with conditions handled according to CLAUSES.
Each element of CLAUSES is a clause like those used in SELECTQ.
It specifies one or more condition names, and what to do if they are signalled.

If any of the conditions specified in the clauses happens during BODY-FORM,
it is handled by throwing to this level and executing the matching clause.
Within the clause, the first of VARIABLES is bound to the condition-object
that was signaled.
The values of the last form in the clause are returned from CONDITION-CASE.

If none of the conditions occurs, the values of BODY-FORM are returned
from CONDITION-CASE.

If there is a clause with keyword :NO-ERROR, it is executed after BODY-FORM
if conditions are NOT signaled.  During this clause, the variables VARIABLES
are bound to the values produced by BODY-FORM.  The values of the last form
in the clause are returned from CONDITION-CASE."
  (DECLARE (ZWEI:INDENTATION 1 3 2 1))
  `(CONDITION-CASE-IF T ,VARIABLES ,BODY-FORM . ,CLAUSES))

(DEFMACRO CONDITION-CASE-IF (&ENVIRONMENT ENV COND-FORM VARIABLES BODY-FORM &BODY CLAUSES)
  "Like CONDITION-CASE, but establishes condition handlers only if COND-FORM evaluates non-NIL.
Refer to the documentation of CONDITION-CASE for more information."
  (DECLARE (ZWEI:INDENTATION 2 3 3 1))
  (MULTIPLE-VALUE-BIND (REALCLAUSES DECLS)
      (EXTRACT-DECLARATIONS CLAUSES NIL NIL ENV)
    (LET* ((ALL-CONDITIONS
	     (MAPCAN #'(LAMBDA (CLAUSE)
			 (MACRO-TYPE-CHECK-WARNING 'CONDITION-CASE-IF (CAR CLAUSE))
			 (IF (EQ (CAR CLAUSE) ':NO-ERROR) NIL
			   (IF (CONSP (CAR CLAUSE)) (CAR CLAUSE)
			     (LIST (CAR CLAUSE)))))
		     REALCLAUSES))
	   (VAR (OR (CAR VARIABLES) (GENSYM)))
	   (NO-ERROR-CLAUSE (ASSQ ':NO-ERROR REALCLAUSES))
	   (TAG (GENSYM)))
      (IF (NULL (CDR ALL-CONDITIONS))
	  (SETQ ALL-CONDITIONS (CAR ALL-CONDITIONS)))
      (IF NO-ERROR-CLAUSE
	  `(LET ,VARIABLES
	     (DECLARE . ,DECLS)
	     (CATCH-CONTINUATION-IF T ',TAG
		 #'(LAMBDA (,VAR)
		     (DECLARE . ,DECLS)
		     (SELECT-MEMQ (SEND ,VAR :CONDITION-NAMES)
		       . ,(REMQ NO-ERROR-CLAUSE REALCLAUSES)))
		 #'(LAMBDA () . ,(CDR NO-ERROR-CLAUSE))
	       (CONDITION-BIND-IF ,COND-FORM ((,ALL-CONDITIONS 'CONDITION-CASE-THROW ',TAG))
		 (MULTIPLE-VALUE-SETQ ,VARIABLES ,BODY-FORM))))
	`(CATCH-CONTINUATION-IF T ',TAG
	     #'(LAMBDA (,VAR)
		 (DECLARE . ,DECLS)
		 (SELECT-MEMQ (SEND ,VAR :CONDITION-NAMES)
		   . ,REALCLAUSES))
	     ()
	   (CONDITION-BIND-IF ,COND-FORM ((,ALL-CONDITIONS 'CONDITION-CASE-THROW ',TAG))
	     ,BODY-FORM))))))

(DEFMACRO CONDITION-CALL (VARIABLES BODY-FORM &BODY CLAUSES)
  "Execute BODY-FORM with conditions handled according to CLAUSES.
Each element of CLAUSES is a clause like those used in COND.
This virtual COND is executed whenever a condition is signaled within BODY-FORM.
If the predicate at the start of a clause evaluates to non-NIL,
the rest of the clause is used to handle the condition.
The values of the last form in the clause are returned from CONDITION-CALL.
The predicate, and the rest of the clause, can find the condition object
that was signaled in the value of the first VARIABLE.

If no predicate evaluates to non-NIL, the condition is not handled
at this level.  Previously established handlers then get a chance.

The predicates may be evaluated more than once, and should have no side-effects.
They are evaluated within the context where the condition was signaled
and are evaluated again after throwing back to this level.
The rest of the clause is evaluated only after throwing back to this level.

The values of BODY-FORM are returned from the CONDITION-CALL if condition
handling does not cause something else to happen.  However, if there is
a :NO-ERROR clause (a clause whose first element is :NO-ERROR) then it
is executed and its values are returned from the CONDITION-CALL.
In this clause, the VARIABLES are bound to the values of the BODY-FORM."
  (DECLARE (ZWEI:INDENTATION 1 3 2 1))
  `(CONDITION-CALL-IF T ,VARIABLES ,BODY-FORM . ,CLAUSES))

(DEFMACRO CONDITION-CALL-IF (&ENVIRONMENT ENV COND-FORM VARIABLES BODY-FORM &BODY CLAUSES)
  "Like CONDITION-CALL, but establishes the handlers only if COND-FORM evaluates non-NIL.
See the documentation of CONDITION-CALL for more information."
  ;; We don't use &BODY in the real arglist to avoid overriding
  ;; the special form of indentation on *INITIAL-LISP-INDENT-OFFSET-ALIST*
  (DECLARE (ZWEI:INDENTATION 2 3 3 1))
  (MULTIPLE-VALUE-BIND (REALCLAUSES DECLS)
      (EXTRACT-DECLARATIONS CLAUSES NIL NIL ENV)
    (LET* ((ORDINARY-CLAUSES (SUBSET #'(LAMBDA (CLAUSE) (NEQ (CAR CLAUSE) ':NO-ERROR))
				     REALCLAUSES))
	   (NO-ERROR-CLAUSE (ASSQ ':NO-ERROR REALCLAUSES))
	   (PREDICATES (MAPCAR #'CAR ORDINARY-CLAUSES))
	   (VAR (OR (CAR VARIABLES) (GENSYM)))
	   (TAG (GENSYM))
	   (HANDLER `#'(LAMBDA (,VAR &REST IGNORE)
			 (DECLARE . ,DECLS)
			 (IF (OR . ,PREDICATES)
			     (THROW ',TAG ,VAR)))))
      `(CATCH-CONTINUATION-IF T ',TAG
	   #'(LAMBDA (,VAR)
	       (DECLARE . ,DECLS)
	       (COND . ,ORDINARY-CLAUSES))
	   ,(IF NO-ERROR-CLAUSE
		`#'(LAMBDA ,VARIABLES
		     (DECLARE . ,DECLS)
		     . ,(CDR NO-ERROR-CLAUSE)))
       (CONDITION-BIND-IF ,COND-FORM ((NIL ,HANDLER)) ,BODY-FORM)))))

(DEFMACRO CONDITION-BIND-IF (COND-FORM HANDLERS &BODY BODY)
  "Execute BODY, with condition handlers HANDLERS in effect iff COND-FORM evals non-NIL.
If COND-FORM's value is non-NIL, this acts just like CONDITION-BIND.
Otherwise, BODY is evaluated as if it were in a PROGN, with no condition handlers."
  (LET* ((VARS (MAPCAR #'(LAMBDA (IGNORE) (GENSYM)) HANDLERS))
	 (VAR1 (GENSYM))
	 (INSIDE
	   `(WITH-STACK-LIST* (,VAR1 ,@VARS EH:CONDITION-HANDLERS)
	      (LET-IF ,COND-FORM
		      ((EH:CONDITION-HANDLERS ,VAR1))
		. ,BODY))))
    (DO ((VS (REVERSE VARS) (CDR VS))
	 (HS (REVERSE HANDLERS) (CDR HS)))
	((NULL VS))
      (SETQ INSIDE
	    `(WITH-STACK-LIST (,(CAR VS) ',(CAR (CAR HS)) . ,(CDAR HS))
	       ,INSIDE)))
    INSIDE))

(DEFMACRO CONDITION-BIND (HANDLERS &BODY BODY)
  "Execute BODY with condition handlers HANDLERS in effect.
Each element of HANDLERS is a list of at least two elements:
 (CONDITIONS FUNCTION EXTRA-ARGUMENTS...).
CONDITIONS is not evaluated, and should be a condition name,
 a list of condition names, or NIL meaning all possible conditions.
FUNCTION is evaluated before BODY is entered to get a function to call
 to handle the condition(s); EXTRA-ARGUMENTS are evaluated then too.
When a one of the specified conditions is signaled, FUNCTION is called
 with arguments of the condition object followed by the EXTRA-ARGUMENTS.
FUNCTION should return two values.  If the first value is NIL,
the condition has not really been handled.  Otherwise, the two
values of FUNCTION will be returned from SIGNAL.
The conditions specified by CONDITIONS do not always have to be handled;
they are an initial filter that determines whether FUNCTION will be called.
Once function is called, it can then decide whether it will handle this SIGNAL."
  `(CONDITION-BIND-IF T ,HANDLERS . ,BODY))

(DEFMACRO CONDITION-BIND-DEFAULT-IF (COND-FORM HANDLERS &BODY BODY)
  "Execute BODY with default condition handlers HANDLERS in effect iff COND-FORM evals non-NIL.
Like CONDITION-BIND-IF except the condition handlers go on
the default handler list, EH:CONDITION-DEFAULT-HANDLERS, rather than
on the regular handler list.  The two lists work just the same
except that the default list is searched after the entire regular list."
  (LET* ((VARS (MAPCAR #'(LAMBDA (IGNORE) (GENSYM)) HANDLERS))
	 (VAR1 (GENSYM))
	 (INSIDE
	   `(WITH-STACK-LIST* (,VAR1 ,@VARS EH:CONDITION-DEFAULT-HANDLERS)
	      (LET-IF ,COND-FORM
		      ((EH:CONDITION-DEFAULT-HANDLERS ,VAR1))
		. ,BODY))))
    (DO ((VS (REVERSE VARS) (CDR VS))
	 (HS (REVERSE HANDLERS) (CDR HS)))
	((NULL VS))
      (SETQ INSIDE
	    `(WITH-STACK-LIST (,(CAR VS) ',(CAR (CAR HS)) . ,(CDAR HS))
	       ,INSIDE)))
    INSIDE))

(DEFMACRO CONDITION-BIND-DEFAULT (HANDLERS &BODY BODY)
  "Execute BODY with default condition handlers HANDLERS in effect.
Like CONDITION-BIND except the condition handlers go on
the default handler list, EH:CONDITION-DEFAULT-HANDLERS, rather than
on the regular handler list.  The two lists work just the same
except that the default list is searched after the entire regular list."
  `(CONDITION-BIND-DEFAULT-IF T ,HANDLERS . ,BODY))

(DEFMACRO ERRSET (BODY &OPTIONAL (PRINTFLAG T))
  "Execute body, trapping errors.  If no error, return a 1-list of the value of BODY.
If there is an error, return NIL (or at least not a list.)
An error message is printed unless PRINTFLAG is specified and evaluates to NIL."
  (LET ((TAG (GENSYM)))
    ;; Returning TEM is for the sake of ERR only.
    ;; If ERRSET-HANDLER actually runs, it throws NIL.
    `(CATCH-CONTINUATION ',TAG #'(LAMBDA (TEM) (VALUES TEM T)) NIL
       (CONDITION-BIND ((ERROR 'ERRSET-HANDLER ',TAG ,PRINTFLAG))
	  (LIST ,BODY)))))

(DEFMACRO ERR (&OPTIONAL VALUE-FORM FLAG)
    (COND ((OR VALUE-FORM FLAG)
	   `(LET ((.VALUE. ,VALUE-FORM))
	      (DOLIST (H EH:CONDITION-HANDLERS)
		(WHEN (AND (EQ (CAR H) 'ERROR)
			   (EQ (CADR H) 'ERRSET-HANDLER))
		  (THROW (CADDR H) .VALUE.)))
	      (FERROR "~S" .VALUE.)))
	  (T '(PROGN (DOLIST (H EH:CONDITION-HANDLERS)
		       (WHEN (AND (EQ (CAR H) 'ERROR)
				  (EQ (CADR H) 'ERRSET-HANDLER))
			 (THROW (CADDR H) NIL)))
		     (ERROR "")))))

(DEFMACRO IGNORE-ERRORS (&BODY BODY)
  "Evaluate BODY and return even if an error occurs.
If no error occurs, our first value is the first value of the last form in BODY,
 and our second value is NIL.
If an error does occur, our first value is NIL and our second value is T.
Dangerous errors such as running out of memory are not caught."
  (LET ((TAG (GENSYM)))
    `(CATCH-CONTINUATION ',TAG #'(LAMBDA () (VALUES NIL T)) NIL
       (CONDITION-BIND ((ERROR 'IGNORE-ERRORS-HANDLER ',TAG))
	 (VALUES (PROGN . ,BODY) NIL)))))

(DEFMACRO ERROR-RESTART ((CONDITION FORMAT-STRING . FORMAT-ARGS) &BODY BODY)
  "Execute BODY, with a restart for CONDITION in effect that will try BODY over.
FORMAT-STRING and FORMAT-ARGS are for the debugger to print a description
of what this restart is for, so the user can decide whether to use it.
They are all evaluated each time around the loop, before doing BODY.

If the user chooses to go to the restart we provide, it throws back to
the loop and BODY is executed again.  If BODY returns normally, the values
of the last form in BODY are returned from the ERROR-RESTART."
  (LET ((TAG (GENSYM)))
    `(BLOCK ERROR-RESTART-BLOCK
       (TAGBODY
	RETRY
	   (RETURN-FROM ERROR-RESTART-BLOCK
	     (WITH-STACK-LIST (,TAG ,FORMAT-STRING . ,FORMAT-ARGS)
	       (CATCH-CONTINUATION-IF T ,TAG #'(LAMBDA (IGNORE) (GO RETRY)) NIL
		 (WITH-STACK-LIST (,TAG ',CONDITION ,TAG T
				   ,TAG
				   'CATCH-ERROR-RESTART-THROW ,TAG)
		   (WITH-STACK-LIST* (EH:CONDITION-RESUME-HANDLERS
				       ,TAG
				       EH:CONDITION-RESUME-HANDLERS)
		     . ,BODY)))))))))

(DEFMACRO ERROR-RESTART-LOOP ((CONDITION FORMAT-STRING . FORMAT-ARGS) &BODY BODY)
  "Execute BODY over and over, with a restart for CONDITION in effect.
FORMAT-STRING and FORMAT-ARGS are for the debugger to print a description
of what this restart is for, so the user can decide whether to use it.
They are all evaluated each time around the loop, before doing BODY.

If the user chooses to go to the restart we provide, it throws back to
the loop and loops around again.  If BODY returns normally, it also loops around."
  (LET ((TAG (GENSYM)))
    `(TAGBODY
      RETRY
       (WITH-STACK-LIST (,TAG ,FORMAT-STRING . ,FORMAT-ARGS)
         (CATCH-CONTINUATION-IF T ,TAG NIL NIL
	   (WITH-STACK-LIST (,TAG ',CONDITION ,TAG T
			     ,TAG
			     'CATCH-ERROR-RESTART-THROW ,TAG)
	     (WITH-STACK-LIST* (EH:CONDITION-RESUME-HANDLERS
				,TAG
				EH:CONDITION-RESUME-HANDLERS)
	       . ,BODY))))
       (GO RETRY))))

(DEFMACRO CATCH-ERROR-RESTART ((CONDITION FORMAT-STRING . FORMAT-ARGS) &BODY BODY)
  "Provide a restart for CONDITION if signaled within BODY.
FORMAT-STRING and FORMAT-ARGS are for the debugger to print a description
of what this restart is for, so the user can decide whether to use it.
They are all evaluated when the CATCH-ERROR-RESTART is entered.
If the user chooses to go to the restart we provide,
CATCH-ERROR-RESTART returns NIL as first value and a non-NIL second value.
If CATCH-ERROR-RESTART is exited normally, it returns the values
of the last form in BODY."
  (LET ((TAG (GENSYM)))
    `(WITH-STACK-LIST (,TAG ,FORMAT-STRING . ,FORMAT-ARGS)
       (CATCH-CONTINUATION-IF T ,TAG #'(LAMBDA () (VALUES NIL T)) NIL
         (WITH-STACK-LIST (,TAG ',CONDITION ,TAG T
			   ,TAG
			   'CATCH-ERROR-RESTART-THROW ,TAG)
	   (WITH-STACK-LIST* (EH:CONDITION-RESUME-HANDLERS
			      ,TAG
			      EH:CONDITION-RESUME-HANDLERS)
	     . ,BODY))))))

(DEFMACRO CATCH-ERROR-RESTART-IF
		   (COND-FORM (CONDITION FORMAT-STRING . FORMAT-ARGS) &BODY BODY)
  "Provide a restart for CONDITION if signaled within BODY, if COND-FORM evals non-NIL.
FORMAT-STRING and FORMAT-ARGS are for the debugger to print a description
of what this restart is for, so the user can decide whether to use it.
They are all evaluated when the CATCH-ERROR-RESTART-IF is entered.
If the user chooses to go to the restart we provide,
CATCH-ERROR-RESTART-IF returns NIL as first value and a non-NIL second value.
If CATCH-ERROR-RESTART-IF is exited normally, it returns the values
of the last form in BODY."
  (LET ((TAG (GENSYM)))
    `(WITH-STACK-LIST (,TAG ,FORMAT-STRING . ,FORMAT-ARGS)
       (CATCH-CONTINUATION-IF T ,TAG #'(LAMBDA () (VALUES NIL T)) NIL
	 (WITH-STACK-LIST (,TAG ',CONDITION ,TAG T
			   ,TAG
			   'CATCH-ERROR-RESTART-THROW ,TAG)
	   (WITH-STACK-LIST* (,TAG
			      ,TAG
			      EH:CONDITION-RESUME-HANDLERS)
	     (LET-IF ,COND-FORM
		     ((EH:CONDITION-RESUME-HANDLERS ,TAG))
	       . ,BODY)))))))

(DEFMACRO CATCH-ERROR-RESTART-EXPLICIT-IF
		   (COND-FORM (CONDITION PROCEED-TYPE FORMAT-STRING . FORMAT-ARGS) &BODY BODY)
  "Provide a PROCEED-TYPE resume handler for CONDITION if signaled within BODY, if COND-FORM evals non-NIL.
PROCEED-TYPE, like CONDITION, is not evaluated.
FORMAT-STRING and FORMAT-ARGS are for the debugger to print a description
of what this restart is for, so the user can decide whether to use it.
They are all evaluated when the CATCH-ERROR-RESTART-IF is entered.
If the user chooses to go to the restart we provide,
CATCH-ERROR-RESTART-IF returns NIL as first value and a non-NIL second value.
If CATCH-ERROR-RESTART-IF is exited normally, it returns the values
of the last form in BODY."
  (LET ((TAG (GENSYM)))
    `(WITH-STACK-LIST (,TAG ,FORMAT-STRING . ,FORMAT-ARGS)
       (CATCH-CONTINUATION-IF T ,TAG #'(LAMBDA () (VALUES NIL T)) NIL
	 (WITH-STACK-LIST (,TAG ',CONDITION ',PROCEED-TYPE T
			   ,TAG
			   'CATCH-ERROR-RESTART-THROW ,TAG)
	   (WITH-STACK-LIST* (,TAG
			      ,TAG
			      EH:CONDITION-RESUME-HANDLERS)
	     (LET-IF ,COND-FORM
		     ((EH:CONDITION-RESUME-HANDLERS ,TAG))
	       . ,BODY)))))))

(DEFMACRO CONDITION-RESUME (HANDLER &BODY BODY)
  "Provide a resume handler for conditions signaled within BODY.
Each resume handler applies to certain conditions, and is named by a keyword.
The error system sees which resume handlers can apply to the condition being handled,
 and includes their names (keywords) in the available proceed-types.
If a condition handler or the debugger elects to proceed with a proceed-type
 which was supplied by a resume handler, the resume handler is called.
It should always do a throw; it should not return to its caller.

HANDLER is evaluated on entry to the CONDITION-RESUME-IF.  The value should
look like this:
 (CONDITION-NAMES PROCEED-TYPE PREDICATE (FORMAT-STRING FORMAT-ARGS...) FUNCTION EXTRA-ARGS...)
CONDITION-NAMES is as for CONDITION-BIND.  It says which conditions to consider applying to.
PROCEED-TYPE is a keyword that identifies the purpose of this resume handler.
 A resume handler is only considered for use when an attempt is made to
 proceed with this PROCEED-TYPE.
PREDICATE is a function of one arg (a condition object) which decides
 whether this resume handler is really applicable.
 PREDICATE can be T if you don't want to test anything.
FORMAT-STRING and FORMAT-ARGS are for the debugger to print a description
of what this resume handler is for, so the user can decide whether to use it.
FUNCTION is the actual resume handler function.  Its arguments are
 the condition object, the EXTRA-ARGS, and any any other values supplied by caller.

CONDITION-RESUME does not do a CATCH.
It simply establishes the resume handler and executes the body."
  `(WITH-STACK-LIST* (EH:CONDITION-RESUME-HANDLERS ,HANDLER EH:CONDITION-RESUME-HANDLERS)
     . ,BODY))

(DEFMACRO CONDITION-RESUME-IF
		   (COND-FORM HANDLER &BODY BODY)
  "Like CONDITION-RESUME, but provide the resume handler only if COND-FORM evals non-NIL."
  (LET ((TAG (GENSYM)))
    `(WITH-STACK-LIST* (,TAG ,HANDLER EH:CONDITION-RESUME-HANDLERS)
       (LET-IF ,COND-FORM
	       ((EH:CONDITION-RESUME-HANDLERS ,TAG))
	 . ,BODY))))

(DEFMACRO SIGNAL-PROCEED-CASE ((VARIABLES . SIGNAL-ARGS) &BODY CLAUSES)
  "Signal a condition and provide a SELECTQ for proceed-types in case it is handled.
The SIGNAL-ARGS are evaluated and passed to SIGNAL.  That is how the condition is signaled.
The VARIABLES are bound to all but the first of the values returned by SIGNAL.
 The first value is used to select one of the CLAUSES with a SELECTQ.
 The selected clause is executed and its values are returned.
SIGNAL is called with a :PROCEED-TYPES argument constructed by examining
 the cars of the CLAUSES.
If the condition is not handled, SIGNAL returns NIL.  If there is a clause
for NIL, it is run.  Otherwise, SIGNAL-PROCEED-CASE returns NIL."
  (LET ((PROCEED-TYPE-VARIABLE (GENSYM))
	(PROCEED-TYPES-IN-SIGNAL-ARGS)
	(PROCEED-TYPES
	  (MAPCAN #'(LAMBDA (CLAUSE)
		      (IF (SYMBOLP (CAR CLAUSE))
			  (NCONS (CAR CLAUSE))
			(COPY-LIST (CAR CLAUSE))))
		  CLAUSES)))
    (DO ((SA (CDR SIGNAL-ARGS) (CDDR SA)))
	((NULL SA))
      (IF (SYS:MEMBER-EQUAL (CAR SA) '(':PROCEED-TYPES :PROCEED-TYPES))
	  (SETQ PROCEED-TYPES-IN-SIGNAL-ARGS (CDR SA))))
    `(MULTIPLE-VALUE-BIND (,PROCEED-TYPE-VARIABLE . ,VARIABLES)
	 (SIGNAL (MAKE-CONDITION ,@SIGNAL-ARGS) ':PROCEED-TYPES
		 ,(IF PROCEED-TYPES-IN-SIGNAL-ARGS
		      (CAR PROCEED-TYPES-IN-SIGNAL-ARGS)
		    `',(DELQ NIL PROCEED-TYPES)))
       (SELECTQ ,PROCEED-TYPE-VARIABLE
	 . ,CLAUSES))))

(DEFMACRO CATCH-ERROR (BODY &OPTIONAL (PRINTFLAG T))
  "Execute body, trapping errors.  If no error, return the values of BODY.
If there is an error, return first value NIL, second non-NIL.
An error message is printed unless PRINTFLAG is specified and evaluates to NIL."
  (LET ((TAG (GENSYM)))
    `(CATCH-CONTINUATION ',TAG #'(LAMBDA () (VALUES NIL T)) NIL
       (VALUES (CONDITION-BIND ((ERROR 'ERRSET-HANDLER ',TAG ,PRINTFLAG))
		 ,BODY)))))
