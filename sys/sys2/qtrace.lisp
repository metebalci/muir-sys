;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Readtable:T; Base:10 -*-
;;;	** (c) Copyright 1980 Massachusetts Institute of Technology **

;;; Trace package

;; ARGLIST and VALUES are bound special

;;;	"There is always a place for debugging.  No matter how
;;;	 hard you try to think of everything in advance, you
;;;	 will always find that there is something else that you
;;;	 hadn't thought of."
;;;			- My Life as a Mathematician
;;;			  by Hfpsh Dboups

;;;MISSING:
;;;	 - HAIRY DISPLAY FEATURES?
;;;	 - "TRACE-EDSUB"

;;;Non-nil to cause the traced definitions to be compiled.
;;;That way, PROG, COND, etc. can be traced.
(DEFVAR TRACE-COMPILE-FLAG NIL)

(DEFVAR TRACED-FUNCTIONS NIL
  "List of all traced function-specs.")

(DEFVAR INSIDE-TRACE NIL
  "T to disable tracing, while inside processing the tracing of something.")

(DEFVAR TRACE-LEVEL 0
  "Total depth within traced functions.  Controls indentation of trace output.")

(DEFVAR *TRACE-OUTPUT* NIL
  "Stream used for trace output.")
(DEFVAR TRACE-OUTPUT :UNBOUND
  "Stream used for trace output.")
(FORWARD-VALUE-CELL 'TRACE-OUTPUT '*TRACE-OUTPUT*)

(DEFF TRACE-APPLY 'APPLY)
(DEFF TRACE-STEP-APPLY 'STEP-APPLY)
;; need to do it this way since step-apply isn't loaded when this file is, and
;;  generally for safety... (if APPLY redefined, etc...) 
(add-initialization "Trace technology" '(progn (fset 'trace-apply #'apply)
					       (fset 'trace-step-apply #'step-apply))
		    :cold)

(DEFMACRO TRACE (&REST SPECS)
  "Trace one or more functions.
For anything but the simplest case of tracing symbol-functions this function
has such a bletcherous interface that you'd probably be better off trying to overcome
your fear of rodents and calling TV::TRACE-VIA-MENUS instead.
With nno args returns a list of all funnction-specs traced."
  (IF (NULL SPECS)
      `',TRACED-FUNCTIONS
    `(MAPCAN #'TRACE-1 ',SPECS)))

(DEFMACRO UNTRACE (&REST FNS)
  "Untrace one or more functions.  With no arg, untrace all traced functions."
  ;; try to prevent some lossage.
  ;; It may be best just to make this a special form, since then we can avoid
  ;;  *macroexpand-hook*, etc, lossages
  (LET ((INSIDE-TRACE T))
    `(MAPCAR #'UNTRACE-1 ',(OR FNS TRACED-FUNCTIONS))))

(DEFUN (:PROPERTY TRACE ENCAPSULATION-GRIND-FUNCTION) (FUNCTION DEF WIDTH REAL-IO UNTYO-P)
  (DECLARE (IGNORE FUNCTION DEF WIDTH REAL-IO UNTYO-P))
  (PRINC "
;Traced
"))

;;; A list in the args to UNTRACE is taken as a non-atomic function-name
;;; rather than a wherein-spec, as Maclisp would do, since UNTRACE WHEREIN
;;; is not implemented anyway, and since WHEREIN doesn't work that way in
;;; this TRACE anyway (that is, it still modifies the function cell.)
(DEFUN UNTRACE-1 (SPEC &AUX SPEC1 SPEC2)
  (SETQ SPEC (DWIMIFY-ARG-PACKAGE SPEC 'SPEC))
  (SETQ SPEC1 (UNENCAPSULATE-FUNCTION-SPEC SPEC 'TRACE))
  (COND ((NEQ SPEC1 (SETQ SPEC2 (UNENCAPSULATE-FUNCTION-SPEC SPEC1 '(TRACE))))
	 (FDEFINE SPEC1 (FDEFINITION SPEC2) NIL T)
	 (SETQ TRACED-FUNCTIONS (DELETE SPEC TRACED-FUNCTIONS))))
  SPEC)

(DEFUN TRACE-1 (SPEC)
  (PROG (BREAK EXITBREAK WHEREIN COND ENTRYCOND EXITCOND STEPCOND ARGPDL ENTRY EXIT
	 (ARG T) (VALUE T) STEP (BARFP T)
	 ENTRYVALS EXITVALS MUMBLE FCN SPEC1 TRFCN ERROR
	 (DEFAULT-CONS-AREA BACKGROUND-CONS-AREA))
	(IF (ATOM SPEC)
	    (SETQ FCN SPEC)
	  (COND ((EQ (CAR SPEC) ':FUNCTION)
		 (SETQ FCN (CADR SPEC) SPEC (CDR SPEC)))
		((ATOM (CAR SPEC))
		 (SETQ FCN (CAR SPEC)))
		(T (RETURN (LOOP FOR FCN IN (CAR SPEC)
				 NCONC (TRACE-1 `(:FUNCTION ,FCN . ,(CDR SPEC)))))))
	  (DO ((SPECS (CDR SPEC) (CDR SPECS)))
	      ((NULL SPECS))
	    (CASE (CAR SPECS)
	      (:BREAK (SETQ BARFP SPECS SPECS (CDR SPECS) BREAK (CAR SPECS)))
	      (:EXITBREAK (SETQ BARFP SPECS SPECS (CDR SPECS) EXITBREAK (CAR SPECS)))
	      (:STEPCOND (SETQ BARFP SPECS SPECS (CDR SPECS) STEPCOND (CAR SPECS)
			       STEP T))
	      (:STEP (SETQ STEP T))
	      (:ERROR (SETQ ERROR T))
	      (:COND (SETQ BARFP SPECS SPECS (CDR SPECS) COND (CAR SPECS)))
	      (:ENTRYCOND (SETQ BARFP SPECS SPECS (CDR SPECS) ENTRYCOND (CAR SPECS)))
	      (:EXITCOND (SETQ BARFP SPECS SPECS (CDR SPECS) EXITCOND (CAR SPECS)))
	      (:WHEREIN (SETQ BARFP SPECS SPECS (CDR SPECS) WHEREIN (CAR SPECS)))
	      (:ARGPDL (SETQ BARFP SPECS SPECS (CDR SPECS) ARGPDL (CAR SPECS)))
	      (:ENTRY (SETQ BARFP SPECS SPECS (CDR SPECS) ENTRY (CAR SPECS)))
	      (:EXIT (SETQ BARFP SPECS SPECS (CDR SPECS) EXIT (CAR SPECS)))
	      (:PRINT (SETQ BARFP SPECS
			    SPECS (CDR SPECS)
			    ENTRY (CONS (CAR SPECS) ENTRY)
			    EXIT (CONS (CAR SPECS) EXIT)))
	      (:ENTRYPRINT (SETQ BARFP SPECS SPECS (CDR SPECS)
				 ENTRY (CONS (CAR SPECS) ENTRY)))
	      (:EXITPRINT (SETQ BARFP SPECS SPECS (CDR SPECS) EXIT (CONS (CAR SPECS) EXIT)))
	      ((:ARG :VALUE :BOTH NIL)
	       (IF (MEMQ (CAR SPECS) '(:ARG NIL)) (SETQ VALUE NIL))
	       (IF (MEMQ (CAR SPECS) '(:VALUE NIL)) (SETQ ARG NIL))
	       (AND ARG (SETQ ENTRYVALS (CDR SPECS)))
	       (AND VALUE (SETQ EXITVALS (CDR SPECS)))
	       (RETURN NIL))
	      (OTHERWISE
	       (SETQ MUMBLE (CAR SPECS))
	       (RETURN NIL)))
	    (AND (NULL BARFP) (FERROR NIL "Parameter missing"))))
	(SETQ FCN (DWIMIFY-ARG-PACKAGE FCN 'FCN))
	(UNTRACE-1 FCN)
	(WHEN MUMBLE (RETURN (FERROR NIL "Meaningless TRACE keyword: ~S" MUMBLE)))
	(CHECK-TYPE ARGPDL SYMBOL)
	(SETQ SPEC1 (UNENCAPSULATE-FUNCTION-SPEC FCN 'TRACE))
	
	(SETQ TRFCN (ENCAPSULATE SPEC1 FCN 'TRACE
	   `(PROG* (,@(AND ARGPDL `((,ARGPDL (CONS (LIST (1+ ,COPY) ',FCN ARGLIST)
						   ,ARGPDL))))
		    (VALUES NIL)
		    (,COPY (1+ ,COPY))
		    (TRACE-LEVEL (1+ TRACE-LEVEL)))
		   (DECLARE (SPECIAL ,COPY VALUES))
		   ;; End of PROG var list.
		   ,(IF ERROR `(PROGN (LET ((EH:ERROR-DEPTH (1+ EH:ERROR-DEPTH))
					    (EH:CONDITION-PROCEED-TYPES '(:NO-ACTION)))
					(EH:INVOKE-DEBUGGER
					  (MAKE-CONDITION 'EH:TRACE-BREAKPOINT
							  "~S entered" ',FCN)))
				      (RETURN (APPLY ,ENCAPSULATED-FUNCTION ARGLIST)))
		      `(COND ((OR INSIDE-TRACE
				  ,(AND COND `(NOT ,COND))
				  ,(AND WHEREIN `(NOT (FUNCTION-ACTIVE-P ',WHEREIN))))
			      (RETURN (APPLY ,ENCAPSULATED-FUNCTION ARGLIST)))
			     (T (LET ((INSIDE-TRACE T))
				  ,(TRACE-MAYBE-CONDITIONALIZE ENTRYCOND
				      `(TRACE-PRINT ,COPY 'ENTER ',FCN ',ARG
						    ',ENTRY ',ENTRYVALS))
				  ,@(AND BREAK
					 `((AND ,BREAK (LET (INSIDE-TRACE)
							 (BREAK "Entering ~S." ',FCN)))))
				  (SETQ VALUES
					(LET ((INSIDE-TRACE NIL))
					  (MULTIPLE-VALUE-LIST
					    ,(IF (AND STEP STEPCOND)
						 ;; conditionally call the stepper.
						 `(IF ,STEPCOND
						      (TRACE-STEP-APPLY
							,ENCAPSULATED-FUNCTION
							ARGLIST)
						    (TRACE-APPLY
						      ,ENCAPSULATED-FUNCTION
						      ARGLIST))
					       `(,(IF STEP 'TRACE-STEP-APPLY 'TRACE-APPLY)
						 ,ENCAPSULATED-FUNCTION
						 ARGLIST)))))
				  ,(TRACE-MAYBE-CONDITIONALIZE EXITCOND
				      `(TRACE-PRINT ,COPY 'EXIT ',FCN ',VALUE
						    ',EXIT ',EXITVALS))
				  ,@(AND EXITBREAK
					 `((AND ,EXITBREAK (LET (INSIDE-TRACE)
							     (BREAK "Exiting ~S." ',FCN)))))
				  (RETURN-LIST VALUES))))))))
	(SET TRFCN 0)
	(PUSH FCN TRACED-FUNCTIONS)
	(IF (OR TRACE-COMPILE-FLAG COMPILE-ENCAPSULATIONS-FLAG)
	    (COMPILE-ENCAPSULATIONS SPEC1 'TRACE))
	(RETURN (NCONS FCN))))


(DEFUN TRACE-MAYBE-CONDITIONALIZE (CONDITION ACTION)
  (IF CONDITION
      `(AND (FUNCALL ',CONDITION) ,ACTION)
      ACTION))

(DEFUN TRACE-PRINT (DEPTH DIRECTION FUNCTION PRINT-ARGS-FLAG EXTRAS-1 EXTRAS-2)
 (DECLARE (SPECIAL ARGLIST VALUES))
 (TERPRI *TRACE-OUTPUT*)
 (DO ((N (* 2 TRACE-LEVEL) (1- N)))
     ((NOT (> N 2)))
   (WRITE-CHAR #/SP *TRACE-OUTPUT*))
 (FORMAT *TRACE-OUTPUT* "(~D ~A " DEPTH DIRECTION)
 (PRIN1 FUNCTION *TRACE-OUTPUT*)
 (LET ((STUFF (IF (EQ DIRECTION 'ENTER) ARGLIST VALUES)))
   (COND ((AND STUFF PRINT-ARGS-FLAG)
	  (PRINC ":" *TRACE-OUTPUT*)
	  (DO ((TAIL STUFF (CDR TAIL)))
	      ((ATOM TAIL)
	       (WHEN TAIL
		 (PRINC " . " *TRACE-OUTPUT*)
		 (PRIN1 TAIL *TRACE-OUTPUT*)))
	    (WRITE-CHAR #/SP *TRACE-OUTPUT*)
	    (PRIN1 (CAR TAIL) *TRACE-OUTPUT*)))))
 (WHEN EXTRAS-1
   (PRINC "  \\" *TRACE-OUTPUT*)
   (DOLIST (E EXTRAS-1)
     (PRINC " " *TRACE-OUTPUT*)
     (PRIN1 (EVAL E) *TRACE-OUTPUT*)))
 (WHEN EXTRAS-2
   (PRINC "  ////" *TRACE-OUTPUT*)
   (DOLIST (E EXTRAS-2)
     (WRITE-CHAR #/SP *TRACE-OUTPUT*)
     (PRIN1 (EVAL E) *TRACE-OUTPUT*)))
 (PRINC ")" *TRACE-OUTPUT*))

(DEFUN FUNCTION-ACTIVE-P (FUNCTION-SPEC)
  "T if dynamically within any activation of FUNCTION-SPEC."
  (LET* ((SG %CURRENT-STACK-GROUP)
	 (RP (SG-REGULAR-PDL SG))
	 (FNVAL (FDEFINITION FUNCTION-SPEC))
	 (INIFN (SG-INITIAL-FUNCTION-INDEX SG)))
    (do ((AP (%POINTER-DIFFERENCE (%STACK-FRAME-POINTER) RP)
	     (- AP (RP-DELTA-TO-ACTIVE-BLOCK RP AP))))
	(())
      (COND ((EQ FNVAL (RP-FUNCTION-WORD RP AP))
	     (RETURN AP))
	    (( AP INIFN) (RETURN NIL))))))
