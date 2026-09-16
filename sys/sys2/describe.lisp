;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:8; Readtable:ZL -*-

;This stuff used to be in SYS; QMISC

(defvar *describe-print-level* 2
  "Value of *PRINT-LEVEL* to use in DESCRIBE")
(defvar *describe-print-length* 3
  "Value of *PRINT-LENGTH* to use in DESCRIBE")
;(defvar *describe-print-pretty* nil
;  "Value of *PRINT-PRETTY* to use in DESCRIBE")

;;; Describe anything
(defun describe (anything &optional no-complaints)
  "Describe the value or components of any Lisp object.
This is a good way to find out more than the printed representation says."
  (unless (and (named-structure-p anything)
	       (cond ((and (get (named-structure-p anything) 'named-structure-invoke)
			   (memq ':describe
				 (named-structure-invoke anything :which-operations)))
		      (named-structure-invoke anything :describe)
		      anything)
		     ((get (named-structure-p anything) 'defstruct-description)
		      (describe-defstruct anything)
		      anything)
		     (t nil)))
    (typecase anything
      ((or entity instance)
       (send anything :describe))
      (array
       (describe-array anything))
      (closure
       (describe-closure anything))
      (compiled-function
       (describe-fef anything))
      (symbol
       (describe-symbol anything))
      (cons
       (describe-cons anything))
      (stack-group
       (describe-stack-group anything))
      (short-float
       (describe-small-flonum anything))
      (single-float
       (describe-flonum anything))
      (select
       (describe-select-method anything))
      (character
       (describe-character anything))
      (bignum
       (describe-bignum anything))
      (fixnum
       (format t "~%~R is ~:[even~;odd~]~&It is ~B in binary"
	       anything (oddp anything) anything))
      (ratio
       (describe-rational-number anything))
      (complex
       (describe-complex-number anything))
      (locative
       (describe-locative anything))
      (t (unless no-complaints
	   (format t "~%I don't know how to describe ~S" anything)))))
  (send *standard-output* :fresh-line)
  anything)

(defun describe-1 (thing)			;An internal subroutine
  (unless (or (null thing)			;Don't recursively describe boring things
	      (numberp thing) (symbolp thing) (stringp thing)
	      (consp thing))
    (send *standard-output* :fresh-line)
    (let ((*standard-output*			;Arrange for indentation by 5 spaces
	    (closure '(*standard-output*)
		     #'(lambda (&rest args)
			 (and (eq (send *standard-output* :send-if-handles :read-cursorpos)
				  0)
			      (send *standard-output* :string-out "     "))
			 (lexpr-send *standard-output* args)))))
      (describe thing t))))


(DEFUN DESCRIBE-FEF-ADL (FEF &AUX (ADL (GET-MACRO-ARG-DESC-POINTER FEF)))
  (PROG (OPT-Q INIT-OPTION (ARGNUM 0) (LOCALNUM 0) ARGP
	 ARG-SYNTAX)
     L	(IF (NULL ADL) (RETURN NIL))
    	(SETQ OPT-Q (CAR ADL) ADL (CDR ADL))
	(SETQ ARG-SYNTAX (NTH (LDB %%FEF-ARG-SYNTAX OPT-Q)
			      FEF-ARG-SYNTAX))
	(SETQ ARGP (MEMQ ARG-SYNTAX
			 '(FEF-ARG-REQ FEF-ARG-OPT FEF-ARG-REST)))
	(COND ((NOT (ZEROP (LOGAND OPT-Q %FEF-NAME-PRESENT)))
	       (SETQ ADL (CDR ADL))))
	(COND ((EQ (NTH (LDB %%FEF-ARG-SYNTAX OPT-Q) FEF-ARG-SYNTAX) 'FEF-ARG-REST)
	       (FORMAT T "~&Rest arg (~A) is " (EH:REST-ARG-NAME FEF))
	       (INCF LOCALNUM))
	      (ARGP
	       (FORMAT T "~&Arg ~D (~A) is " ARGNUM (EH:ARG-NAME FEF ARGNUM))
	       (INCF ARGNUM))
	      ((EQ ARG-SYNTAX 'FEF-ARG-FREE)
	       (GO L))
	      ((EQ ARG-SYNTAX 'FEF-ARG-INTERNAL-AUX)
	       (RETURN NIL))
	      (T
	       (FORMAT T "~&Local ~D (~A) is " LOCALNUM (EH:LOCAL-NAME FEF LOCALNUM))
	       (INCF LOCALNUM)))
	(PRINC (OR (NTH (LDB %%FEF-ARG-SYNTAX OPT-Q)
			'("required, " "optional, "))
		   ""))
	(IF (EQ (NTH (LDB %%FEF-QUOTE-STATUS OPT-Q)
		     FEF-QUOTE-STATUS)
		'FEF-QT-QT)
	    (PRINC "quoted, "))
	(PRINC (NTH (LDB %%FEF-SPECIALNESS OPT-Q)
		    '("local, " "special, " "" "remote, ")))
;	(PRINC (NTH (LDB %%FEF-DES-DT OPT-Q)
;			       FEF-DES-DT))
	(SETQ INIT-OPTION (NTH (LDB %%FEF-INIT-OPTION OPT-Q)
			       FEF-INIT-OPTION))
	(CASE INIT-OPTION
	  (FEF-INI-NIL (FORMAT T "initialized to NIL."))
	  (FEF-INI-NONE (FORMAT T "not initialized."))
	  (FEF-INI-SELF (FORMAT T "initialized by binding it to itself."))
	  (FEF-INI-COMP-C (FORMAT T "initialized by execution of the function."))
	  (FEF-INI-PNTR
	   (PRINC "initialized to ")
	   (LET ((COMPILER::DISASSEMBLE-OBJECT-OUTPUT-FUN NIL))
	     (COMPILER::DISASSEMBLE-POINTER FEF (%POINTER-DIFFERENCE ADL FEF) 0))
	   (PRINC ".")
	   (POP ADL))
	  (FEF-INI-C-PNTR
	   (LET ((LOC (CAR ADL))
		 (STR (%FIND-STRUCTURE-HEADER (CAR ADL))))
	     (COND ((SYMBOLP STR)
		    (FORMAT T "initialized to the ~A of ~S."
			    (CASE (%POINTER-DIFFERENCE LOC STR)
			      (1 "value")
			      (2 "function definition")
			      (3 "property list")
			      (4 "package"))
			    STR))
		   ((CONSP STR)
		    (FORMAT T "initialized to the function definition of ~S."
			    (CAR STR)))
		   (T (FORMAT T "initialized to the contents of ~S." (CAR ADL)))))
	   (POP ADL))
	  (FEF-INI-EFF-ADR
	   (FORMAT T "initialized to the value of ")
	   (LET ((SLOT (LOGAND #o77 (CAR ADL))))
	     (IF (= (LOGAND #o700 (CAR ADL)) (GET 'COMPILER::LOCBLOCK 'COMPILER::QLVAL))
		 (FORMAT T "local ~D (~S)." SLOT (EH:LOCAL-NAME FEF SLOT))
	       (FORMAT T "arg ~D (~S)." SLOT (EH:ARG-NAME FEF SLOT))))
	   (POP ADL))
	  (FEF-INI-OPT-SA (FORMAT T "initialized by the code up to pc ~D." (CAR ADL))
			  (POP ADL)))
	(GO L)
))

(DEFUN DESCRIBE-STACK-GROUP (SG &AUX TEM)
  (FORMAT T "~%Stack Group; name is ~S, current state ~S"
	  (SG-NAME SG)
	  (NTH (SG-CURRENT-STATE SG) SG-STATES))
  (COND ((NOT (ZEROP (SG-IN-SWAPPED-STATE SG)))
	 (FORMAT T "~%  Variables currently swapped out")))
  (COND ((NOT (ZEROP (SG-FOOTHOLD-EXECUTING-FLAG SG)))
	 (FORMAT T "~%  Foothold currently executing")))
  (COND ((NOT (ZEROP (SG-PROCESSING-ERROR-FLAG SG)))
	 (FORMAT T "~% Currently processing an error")))
  (COND ((NOT (ZEROP (SG-PROCESSING-INTERRUPT-FLAG SG)))
	 (FORMAT T "~% Currently processing an interrupt")))
  (FORMAT T "~%ERROR-MODE:")
     (PRINT-ERROR-MODE (SG-SAVED-M-FLAGS SG))
  (FORMAT T "~%SG-SAFE ~D, SG-SWAP-SV-ON-CALL-OUT ~D, SG-SWAP-SV-OF-SG-THAT-CALLS-ME ~D"
	  (SG-SAFE SG)
	  (SG-SWAP-SV-ON-CALL-OUT SG)
	  (SG-SWAP-SV-OF-SG-THAT-CALLS-ME SG))
  (FORMAT T "~%SG-INST-DISP: ~D (~:*~[Normal~;Debug~;Single-step~;Single-step done~])"
	    (SG-INST-DISP SG))
  (FORMAT T "~%SG-PREVIOUS-STACK-GROUP ~S, SG-CALLING-ARGS-NUMBER ~S, SG-CALLING-ARGS-POINTER ~S"
          (SG-PREVIOUS-STACK-GROUP SG)
	  (SG-CALLING-ARGS-NUMBER SG)
	  (SG-CALLING-ARGS-POINTER SG))
  (FORMAT T "~%Regular PDL pointer ~D, ~D available, ~D limit"
          (SG-REGULAR-PDL-POINTER SG)
	  (ARRAY-LENGTH (SG-REGULAR-PDL SG))
	  (SG-REGULAR-PDL-LIMIT SG))
  (FORMAT T "~%Special PDL pointer ~D, ~D available, ~D limit"
	  (SG-SPECIAL-PDL-POINTER SG)
	  (ARRAY-LENGTH (SG-SPECIAL-PDL SG))
	  (SG-SPECIAL-PDL-LIMIT SG))
  (COND ((SETQ TEM (SG-RECOVERY-HISTORY SG))
	 (FORMAT T "~%Recovery history ~S" TEM)))
  (COND ((SETQ TEM (SG-PLIST SG))
	 (FORMAT T "~%SG-PLIST ~S" TEM))))

(DEFUN PRINT-ERROR-MODE (&OPTIONAL (EM %MODE-FLAGS) (STREAM *STANDARD-OUTPUT*))
  "Prints the current error mode."
  (FORMAT STREAM "~&CAR of a number is ~A.
CDR of a number is ~A.
CAR of a symbol is ~A.
CDR of a symbol is a ~A.
Trapping is ~A.~%"
	  (CASE (LDB %%M-FLAGS-CAR-NUM-MODE EM)
	    (0 "an error")
	    (1 "NIL")
	    (OTHERWISE "in an unknown state"))
	  (CASE (LDB %%M-FLAGS-CDR-NUM-MODE EM)
	    (0 "an error")
	    (1 "NIL")
	    (OTHERWISE "in an unknown state"))
	  (CASE (LDB %%M-FLAGS-CAR-SYM-MODE EM)
	    (0 "an error")
	    (1 "NIL if the symbol is NIL, otherwise an error")
	    (2 "NIL")
	    (3 "its print-name"))
	  (CASE (LDB %%M-FLAGS-CDR-SYM-MODE EM)
	    (0 "an error")
	    (1 "NIL if the symbol is NIL, otherwise an error")
	    (2 "NIL")
	    (3 "its property list"))
	  (CASE (LDB %%M-FLAGS-TRAP-ENABLE EM)
	    (0 "disabled")
	    (1 "enabled"))
	  ))

(DEFUN DESCRIBE-FEF (FEF &AUX HEADER NAME FAST-ARG SV MISC LENGTH DBI)
  (TYPECASE FEF
    (SYMBOL (DESCRIBE-FEF (SYMBOL-FUNCTION FEF)))
    (COMPILED-FUNCTION
     (SETQ HEADER (%P-LDB-OFFSET %%HEADER-REST-FIELD FEF %FEFHI-IPC))
     (SETQ LENGTH (%P-CONTENTS-OFFSET FEF %FEFHI-STORAGE-LENGTH))
     (SETQ NAME (%P-CONTENTS-OFFSET FEF %FEFHI-FCTN-NAME))
     (SETQ FAST-ARG (%P-CONTENTS-OFFSET FEF %FEFHI-FAST-ARG-OPT))
     (SETQ SV (%P-CONTENTS-OFFSET FEF %FEFHI-SV-BITMAP))
     (SETQ MISC (%P-CONTENTS-OFFSET FEF %FEFHI-MISC))
     
     (FORMAT T "~%FEF for function ~S~%" NAME)
     (UNLESS (ZEROP (%P-LDB %%FEFH-GET-SELF-MAPPING-TABLE FEF))
       (FORMAT T "This is a method of flavor ~S.~%"
	       (%P-CONTENTS-OFFSET FEF (1- (%P-LDB-OFFSET %%FEFHI-MS-ARG-DESC-ORG
							  FEF %FEFHI-MISC)))))
     (FORMAT T "Initial relative PC: ~S halfwords.~%" (LDB %%FEFH-PC HEADER))
     ;; -- Print out the fast arg option
     (FORMAT T "The Fast Argument Option is ~A"
	     (IF (ZEROP (LDB %%FEFH-FAST-ARG HEADER))
		 "not active, but here it is anyway:"
	       "active:"))
     (DESCRIBE-NUMERIC-DESCRIPTOR-WORD FAST-ARG)
     ;; -- Randomness.
     (FORMAT T "~%The length of the local block is ~S~%"
	     (LDB %%FEFHI-MS-LOCAL-BLOCK-LENGTH MISC))
     (FORMAT T "The total storage length of the FEF is ~S~%"
	     LENGTH)
     ;; -- Special variables
     (IF (ZEROP (LDB %%FEFH-SV-BIND HEADER))
	 (PRINC "There are no special variables present.")
       (PRINC "There are special variables, ")
       (TERPRI)
       (IF (ZEROP (LDB %%FEFHI-SVM-ACTIVE SV))
	   (PRINC "but the S-V bit map is not active. ")
	 (FORMAT T "and the S-V bit map is active and contains: ~O"
		 (LDB %%FEFHI-SVM-BITS SV))))
     (TERPRI)
     ;; -- ADL.
     (COND ((ZEROP (LDB %%FEFH-NO-ADL HEADER))
	    (FORMAT T "There is an ADL:  It is ~S long, and starts at ~S"
		    (LDB %%FEFHI-MS-BIND-DESC-LENGTH MISC)
		    (LDB %%FEFHI-MS-ARG-DESC-ORG MISC))
	    (DESCRIBE-FEF-ADL FEF))
	   (T (PRINC "There is no ADL.")))
     (TERPRI)
     (WHEN (SETQ DBI (FUNCTION-DEBUGGING-INFO FEF))
       (FORMAT T "Debugging info:~%")
       (DOLIST (ITEM DBI)
	 (FORMAT T "  ~S~%" ITEM))))
    (T (FERROR NIL "~S is not a FEF (a compiled function)" FEF))))


(DEFUN DESCRIBE-NUMERIC-DESCRIPTOR-WORD (N &AUX (MIN (LDB %%ARG-DESC-MIN-ARGS N))
					 	(MAX (LDB %%ARG-DESC-MAX-ARGS N)))
  (FORMAT T "~&   ")
  (IF (BIT-TEST %ARG-DESC-QUOTED-REST N)
      (PRINC "Quoted rest arg, "))
  (IF (BIT-TEST %ARG-DESC-EVALED-REST N)
      (PRINC "Evaluated rest arg, "))
  (IF (BIT-TEST %ARG-DESC-FEF-QUOTE-HAIR N)
      (PRINC "Some args quoted, "))
  (IF (BIT-TEST %ARG-DESC-INTERPRETED N)
      (PRINC "Interpreted function, "))
  (IF (BIT-TEST %ARG-DESC-FEF-BIND-HAIR N)
      (PRINC "Linear enter must check ADL, "))
  (FORMAT T "Takes ~:[between ~D and ~D~;~D~] args.~%"
	  (= MAX MIN) MIN MAX))


(defun describe-array (array)
  (let ((rank (array-rank array))
	(long-length-flag (%p-ldb-offset %%array-long-length-flag array 0)))
    (format t "~%This is an ~S type array. (element-type ~S)~%"
	    (array-type array) (array-element-type array))
    (case rank
      (0
       (FORMAT T "It is of zero rank.")
       )
      (1
       (format t "It is a vector, with a total size of ~D elements" (array-total-size array))
       )
      (t
       (format T "It is ~D-dimensional, with dimensions " rank)
       (dotimes (d rank) (format t "~D " (array-dimension array d)))
       (format t ". Total size ~D elements" (array-total-size array))))
    (when (array-has-leader-p array)
      (let ((length (array-leader-length array)))
	(if (and (eq rank 1)
		 (eq length 1)
		 (fixnump (array-leader array 0)))
	    (format t "~%It has a fill-pointer: ~S" (fill-pointer array))
	  (format t "~%It has a leader, of length ~D. Contents:" length)
	  (format t "~%  Leader 0~:[~; (fill-pointer)~]: ~S"
		  (and (eq rank 1) (fixnump (array-leader array 0))) (array-leader array 0))
	  (dotimes (i (1- length))
	    (format t "~%  Leader ~D: ~S" (1+ i) (array-leader array (1+ i)))))))
    (when (array-displaced-p array)
      (cond ((array-indirect-p array)
	     (format t "~%The array is indirected to ~S"
		     (%p-contents-offset array (+ rank long-length-flag)))
	     (and (array-indexed-p array)
		  (format T ", with index-offset ~S"
			  (%p-contents-offset array (+ rank long-length-flag 2))))
	     (format t "~%Description of that array:")
	     (describe-1 (%p-contents-offset array (+ rank long-length-flag))))
	    (t (format t "~%The array is displaced to ~S"
		       (%p-contents-offset array (+ rank long-length-flag))))))))


(defun describe-symbol (sym)
  (format t "~%Symbol ~S is in ~:[no~;the ~:*~A~] package." sym (symbol-package sym))
  (let ((tem nil))
    (dolist (p *all-packages*)
      (multiple-value-bind (s flag) (intern-soft sym p)
	(when (and flag
		   (eq s sym)
		   (not (eq p (symbol-package sym)))
		   (symbol-package sym)
		   (not (memq p (package-used-by-list (symbol-package sym)))))
	  (push p tem))))
    (when tem (format t "~% It is also interned in package~P ~{~A~^, ~}" (length tem) tem)))
  (when (and (boundp sym) (not (keywordp sym)))
    (let ((*print-level* *describe-print-level*)
	  (*print-length* *describe-print-length*))
      (format t "~%The value of ~S is ~S" sym (symbol-value sym)))
    (describe-1 (symbol-value sym)))
  (when (fboundp sym)
    (let ((*print-level* *describe-print-level*)
	  (*print-length* *describe-print-length*))
      (ignore-errors
	(format t "~%The function definition of ~S is ~S: ~S"
		sym (symbol-function sym) (arglist sym))))
	 (describe-1 (symbol-function sym)))
  (do ((pl (symbol-plist sym) (cddr pl))
       (*print-level* *describe-print-level*)
       (*print-length* *describe-print-length*))
      ((null pl))
    (format t "~%~S has property ~S: ~S"
	    sym (car pl) (cadr pl))
    (describe-1 (cadr pl)))
  (if (not (or (boundp sym) (fboundp sym) (symbol-plist sym)))
      (format t "~%It has no value, definition or properties"))
  nil)

(defun describe-cons (l &aux (*print-circle* t))
  (format t "~%~S is a cons" l))

(DEFUN DESCRIBE-LOCATIVE (X)
  (LET ((AREA (%AREA-NUMBER X)))
    (COND (AREA
	   (FORMAT T "~%~S is a locative pointer into area ~S~%It points "
		     X (AREA-NAME AREA))
	   (LET* ((STRUC (%FIND-STRUCTURE-HEADER X))
		  (BASEP (%POINTER (%FIND-STRUCTURE-LEADER STRUC)))
		  (BOUND (+ (%STRUCTURE-TOTAL-SIZE STRUC) BASEP)))
	     (IF (AND ( BASEP (%POINTER X)) (< (%POINTER X) BOUND))
		 (FORMAT T "to word ~D. of ~S~%" (%POINTER-DIFFERENCE X STRUC) STRUC)
		 (FORMAT T "at some sort of forwarded version of ~S~%" STRUC))
	     (DESCRIBE-1 STRUC)))
	  (T (FORMAT T "~%~S is a locative pointer not into any area." X)))))

(DEFUN DESCRIBE-DEFSTRUCT (X &OPTIONAL DEFSTRUCT-TYPE &AUX DESCRIPTION)
  "Prints out a description of X, including the contents of each of its
slots.  DEFSTRUCT-TYPE should be the name of the structure so
DESCRIBE-DEFSTRUCT can figure out the names of the slots of X.  If X is
a named structure, you don't have to provide DEFSTRUCT-TYPE.  Normally
the DESCRIBE function will call DESCRIBE-DEFSTRUCT if asked to describe
a named structure; however, some named structures have their own way of
describing themselves."
  (SETQ DESCRIPTION (GET (OR DEFSTRUCT-TYPE
			     (IF (CONSP X) (CAR X) (NAMED-STRUCTURE-P X)))
			 'DEFSTRUCT-DESCRIPTION))
  (FORMAT T "~%~S is a ~S~%" X (DEFSTRUCT-DESCRIPTION-NAME))
  (DOLIST (L (DEFSTRUCT-DESCRIPTION-SLOT-ALIST))
    (FORMAT T "   ~S:~30T~S~%"
	    (CAR L)
	    (EVAL `(,(DEFSTRUCT-SLOT-DESCRIPTION-REF-MACRO-NAME (CDR L)) ',X))))
  X)
; also si::describe-defstruct-description in sys2;struct

(defun describe-closure (cl)
  (if (interpreter-environment-closure-p cl)
      (describe-interpreter-closure cl)		;defined in sys; eval
    (let ((bindings (closure-bindings cl))
	  (sym nil) (offset nil))
      (format t "~%~S is a closure of ~S~%" cl (closure-function cl))
      (case (length bindings)
	(0 (format t "(No bindings)"))
	(1 (format t "Lexical environment:~%")
	   (describe-lexical-closure-bindings bindings *standard-output*))
	(t
	 (do ((bindings bindings (cddr bindings)))
	     ((null bindings))
	   (setq sym (%find-structure-header (car bindings))
		 offset (%pointer-difference (car bindings) sym))
	   (if (not (symbolp sym))
	       (format t "    ~S" (car bindings))
	     (format t "    ~[Print name~;Value~;Function~;Property list~;Package~] cell of ~S"
		     offset sym))
	   (format t ":~40T~:[void~;~S~]~%"
		   (location-boundp (cadr bindings))
		   (and (location-boundp (cadr bindings))
			(contents (cadr bindings)))))))
      (unless (consp (closure-function cl))		;don't describe interpreted functions.
	(describe-1 (closure-function cl))))))

;;>> This should be much better.
;;>> When the compiler is hacked to record the names of closure-slots to which it refers,
;;>> this function should know how to print the name of those slots
;;>> Until Mly does that this is the best we can do.
(defun describe-lexical-closure-bindings (bindings stream)
  (loop for frame in (car bindings)
	for f from 0
	do (format stream "  Context ~D~%" f)
	   (loop for x in frame
		 for i from 0
		 do (format stream "    Slot ~D: ~S~%" i x))))
  
(DEFUN DESCRIBE-SELECT-METHOD (M)
  (FORMAT T "~%~S handles:" M)
  (DO ((ML (%MAKE-POINTER DTP-LIST M) (CDR ML)))
      ((ATOM ML)
       (UNLESS (NULL ML)
	 (FORMAT T "~%   anything else to ~S" ML)
	 (IF (AND (SYMBOLP ML) (BOUNDP ML))
	   (FORMAT T "  -> ~S" (SYMBOL-VALUE ML)))))
    (IF (ATOM (CAR ML))
	(FORMAT T "~%   subroutine ~S" (CAR ML))
      (FORMAT T "~%   ~S: ~34T" (CAAR ML))
      (OR (EQ (FUNCTION-NAME (CDAR ML)) (CDAR ML))
	  (PRINC "#'"))
      (PRIN1 (FUNCTION-NAME (CDAR ML))))))

(defun describe-small-flonum (x)
  (format t "~%~S is a small flonum.~%  " x)
  (format t "Excess-~O exponent #o~O, ~D-bit mantissa #o~O (~:[including sign bit~;with sign bit deleted~])"
	  short-float-exponent-offset
	  (%short-float-exponent x)
	  short-float-mantissa-length
	  (%short-float-mantissa x)
	  short-float-implicit-sign-bit-p))

(defun describe-flonum (x)
  (format t "~%~S is a flonum.~%  " x)
  (format t "Excess-~O exponent #o~O, ~D-bit mantissa #o~O (~:[including sign bit~;with sign bit deleted~])"
	  single-float-exponent-offset
	  (%single-float-exponent x)
	  single-float-mantissa-length
	  (%single-float-mantissa x)
	  single-float-implicit-sign-bit-p))

(defun describe-bignum (x)
  (let ((len (%p-ldb-offset #o0022 x 0))
	(barf nil))
    (format t "~&~S is a bignum.~&It is ~R word~:P long.  It is ~[positive~;negative~].  ~
                 It is stored starting at location: #o~O~&Its contents:~2%"
	    x len (%p-ldb-offset #o2201 x 0) (%pointer x))
    (do ((i 1 (1+ i)))
	((> i len))
      (unless (zerop (%p-ldb-offset #o3701 x i))
	(setq barf t))
      (format t "~&~3O: ~[ ~;*~]"
	      i (%p-ldb-offset #o3701 x i))
      (do ((ppss #o3601 (- ppss #o0100)))
	  ((< ppss #o0001))
	(tyo (digit-char (%p-ldb-offset ppss x i))))
      (format t "  ~O," (%p-ldb-offset #o3601 x i))
      (do ((ppss #o3303 (- ppss #o0300)))
	  ((< ppss #o0003))
	(tyo (digit-char (%p-ldb-offset ppss x i))))
      (princ "  ")
      (do ((ppss #o3403 (- ppss #o0300)))
	  ((< ppss #o0103))
	(tyo (digit-char (%p-ldb-offset ppss x i))))
      (format t ",~O  ~O," (%p-ldb-offset #o0001 x i) (%p-ldb-offset #o3502 x i))
      (do ((ppss #o3203 (- ppss #o0300)))
	  ((< ppss #o0203))
	(tyo (digit-char (%p-ldb-offset ppss x i))))
      (format t ",~O" (%p-ldb-offset #o0002 x i)))
    (if barf
	(format t "~2&* = high order bit illegally 1, bug in bignum microcode?"))
    (terpri))
  x)

(DEFUN DESCRIBE-AREA (AREA &AUX LENGTH USED N-REGIONS)
  "Tell all about the area AREA, including all its regions."
  (AND (NUMBERP AREA) (SETQ AREA (AREA-NAME AREA)))
  (DOTIMES (AREA-NUMBER SIZE-OF-AREA-ARRAYS)
    (COND ((EQ AREA (AREA-NAME AREA-NUMBER))
	   (MULTIPLE-VALUE (LENGTH USED N-REGIONS) (ROOM-GET-AREA-LENGTH-USED AREA-NUMBER))
	   (FORMAT T "~&Area #~D: ~S has " 
		   AREA-NUMBER AREA)
	   (OR (= (AREA-MAXIMUM-SIZE AREA-NUMBER)
		  (%LOGDPB 0 %%Q-BOXED-SIGN-BIT -1))
	       (FORMAT T "max size #o~O, " (AREA-MAXIMUM-SIZE AREA-NUMBER)))
	   (FORMAT T "region size #o~O." (AREA-REGION-SIZE AREA-NUMBER))
	   (OR (ZEROP (AREA-SWAP-RECOMMENDATIONS AREA-NUMBER))
	       (FORMAT T "  Swap ~D pages." (AREA-SWAP-RECOMMENDATIONS AREA-NUMBER)))
	   (TERPRI)
	   (IF (AREA-TEMPORARY-P AREA-NUMBER)
	       (FORMAT T "It is a temporary area.  "))
	   (FORMAT T "It has ~D region~P:~%" N-REGIONS N-REGIONS)
	   (DO ((REGION (AREA-REGION-LIST AREA-NUMBER) (REGION-LIST-THREAD REGION)))
	       ((MINUSP REGION))
	     (DESCRIBE-REGION REGION))
	   (RETURN T)))))

(DEFUN DESCRIBE-ALL-REGIONS NIL
  "Tell all about all regions."
  (DO ((REGION SIZE-OF-AREA-ARRAYS (1- REGION)))
      ((MINUSP REGION))
    (DESCRIBE-REGION REGION)))

(DEFUN DESCRIBE-REGION (REGION)
  "Tell all about the region number REGION."
  (LET ((BITS (REGION-BITS REGION)))
    (FORMAT T "  Region #~D: Origin #o~O, Length #o~O, Used #o~O, GC #o~O, Type ~A ~A, Map #o~O,~[NoScav~;Scav~]~%"
	    REGION (REGION-ORIGIN-TRUE-VALUE REGION) (REGION-LENGTH REGION)
	    (REGION-FREE-POINTER REGION) (REGION-GC-POINTER REGION)
	    (NTH (LDB %%REGION-REPRESENTATION-TYPE BITS)
		 '(LIST STRUC "REP=2" "REP=3"))
	    (NTH (LDB %%REGION-SPACE-TYPE BITS)
		 '(FREE OLD NEW NEW1 NEW2 NEW3 NEW4 NEW5 NEW6
			STATIC FIXED EXTRA-PDL COPY "TYPE=15" "TYPE=16" "TYPE=17"))
	    (LDB %%REGION-MAP-BITS BITS)
	    (LDB %%REGION-SCAVENGE-ENABLE BITS))))

(defun describe-rational-number (number)
  (format t "~&~S is a rational number with numerator ~S and denominator ~S"
	  number (numerator number) (denominator number)))

(defun describe-complex-number (number)
  (format t "~&~S is a complex number with real part ~S and imaginary part ~S."
	  number (realpart number) (imagpart number)))

(defun describe-character (character)
  (setq character (cli:character character))
  (format t "~&~S is a character with integer representation ~D, and code ~D
Its control-bits are ~D~:[~4*~; (~@[Control~*~]~@[Meta~*~]~@[Super~*~]~@[Hyper~*~])~]. Its font is ~D"
	  character (char-int character)
	  (char-code character) (char-bits character) ( 0 (char-bits character))
	  (char-bit character :control) (char-bit character :meta)
	  (char-bit character :super) (char-bit character :hyper)
	  (char-font character))
  character)

;;;; Room

(DEFVAR ROOM '(WORKING-STORAGE-AREA MACRO-COMPILED-PROGRAM)
  "Areas to mention when ROOM is called with no args.")

;;; (ROOM) tells about the default areas
;;; (ROOM area1 area2...) tells about those areas
;;; (ROOM T) tells about all areas
;;; (ROOM NIL) prints only the header, does not do any areas
(DEFUN ROOM (&REST ARGS)
  "Print size and free space of some areas.
ARGS can be areas, or T as arg means all areas.
No args means use the areas whose names are members of the value of ROOM.
NIL as arg means print a header but mention no areas."
  (LET ((FREE-SIZE (GET-FREE-SPACE-SIZE))
	(PHYS-SIZE (SYSTEM-COMMUNICATION-AREA %SYS-COM-MEMORY-SIZE)))
    (FORMAT T "~&Physical memory: #o~O (~DK), Free space: #o~O (~DK)"
	      PHYS-SIZE (TRUNCATE PHYS-SIZE 2000) FREE-SIZE (TRUNCATE FREE-SIZE 2000)))
  (MULTIPLE-VALUE-BIND (N-WIRED-PAGES N-FIXED-WIRED-PAGES)
      (COUNT-WIRED-PAGES)
    (FORMAT T ", Wired pages ~D+~D (~D~[~;.25~;.5~;.75~]K)~%"
	      N-FIXED-WIRED-PAGES (- N-WIRED-PAGES N-FIXED-WIRED-PAGES)
	      (TRUNCATE N-WIRED-PAGES (TRUNCATE #o2000 PAGE-SIZE))
	      (\ N-WIRED-PAGES (TRUNCATE #o2000 PAGE-SIZE))))
  (COND ((NULL ARGS)
	 (SETQ ARGS ROOM))
	((EQUAL ARGS '(T))
	 (FORMAT T "Unless otherwise noted, area names are in the SYSTEM package~%")
	 (SETQ ARGS AREA-LIST)))
  (UNLESS (EQUAL ARGS '(NIL))
    (DOLIST (AREA ARGS)
      (ROOM-PRINT-AREA (IF (SYMBOLP AREA) (SYMBOL-VALUE AREA) AREA)))))

(DEFUN ROOM-GET-AREA-LENGTH-USED (AREA)
  (DO ((REGION (AREA-REGION-LIST AREA) (REGION-LIST-THREAD REGION))
       (N-REGIONS 0 (1+ N-REGIONS))
       (LENGTH 0 (+ LENGTH (%POINTER-UNSIGNED (REGION-LENGTH REGION))))
       (USED 0 (+ USED (%POINTER-UNSIGNED (REGION-FREE-POINTER REGION)))))
      ((MINUSP REGION)
       (VALUES LENGTH USED N-REGIONS))))

;>> *print-package*
(DEFUN ROOM-PRINT-AREA (AREA &AUX (*PACKAGE* (PKG-FIND-PACKAGE 'SYSTEM)))
  (UNLESS (NULL (AREA-NAME AREA))
    (MULTIPLE-VALUE-BIND (LENGTH USED N-REGIONS)
	(ROOM-GET-AREA-LENGTH-USED AREA)
      (IF (= (LDB %%REGION-SPACE-TYPE (REGION-BITS (AREA-REGION-LIST AREA)))
	     %REGION-SPACE-FIXED)
	  (FORMAT T "~51,1,1,'.<~S~;(~D region~:P)~> ~O//~O used.  ~D% free.~%"
		  (AREA-NAME AREA) N-REGIONS USED LENGTH
		  (COND ((ZEROP LENGTH)
			 0)
			((< LENGTH #o40000)
			 (TRUNCATE (* 100. (- LENGTH USED)) LENGTH))
			(T
			 (TRUNCATE (- LENGTH USED) (TRUNCATE LENGTH 100.))) ))
	(FORMAT T "~51,1,1,'.<~S~;(~D region~:P)~> ~DK allocated, ~DK used.~%"
		(AREA-NAME AREA) N-REGIONS
		(CEILING LENGTH #o2000) (CEILING USED #o2000)))))
  T)

(DEFUN COUNT-WIRED-PAGES ()
  (DECLARE (VALUES NUMBER-OF-WIRED-PAGES NUMBER-OF-FIXED-WIRED-PAGES))
  (DO ((ADR (REGION-ORIGIN PAGE-TABLE-AREA) (+ ADR 2))
       (N (TRUNCATE (SYSTEM-COMMUNICATION-AREA %SYS-COM-PAGE-TABLE-SIZE) 2) (1- N))
       (N-WIRED 0))
      ((ZEROP N)
       (DO ((ADR (REGION-ORIGIN PHYSICAL-PAGE-DATA) (1+ ADR))
	    (N (TRUNCATE (SYSTEM-COMMUNICATION-AREA %SYS-COM-MEMORY-SIZE) PAGE-SIZE) (1- N))
	    (N-FIXED-WIRED 0))
	   ((ZEROP N)
	    (RETURN (VALUES (+ N-WIRED N-FIXED-WIRED)
			    N-FIXED-WIRED)))
	 (AND (= (%P-LDB #o0020 ADR) #o177777)
	      ( (%P-LDB #o2020 ADR) #o177777)
	      (SETQ N-FIXED-WIRED (1+ N-FIXED-WIRED)))))
    (AND (NOT (ZEROP (%P-LDB %%PHT1-VALID-BIT ADR)))
	 (= (%P-LDB %%PHT1-SWAP-STATUS-CODE ADR) %PHT-SWAP-STATUS-WIRED)
	 (INCF N-WIRED))))

(DEFUN PRINT-AREAS-OF-WIRED-PAGES ()
  (DO ((ADR (REGION-ORIGIN PAGE-TABLE-AREA) (+ ADR 2))
       (N (TRUNCATE (SYSTEM-COMMUNICATION-AREA %SYS-COM-PAGE-TABLE-SIZE) 2) (1- N)))
      ((ZEROP N))
    (WHEN (AND (NOT (ZEROP (%P-LDB %%PHT1-VALID-BIT ADR)))
	       (= (%P-LDB %%PHT1-SWAP-STATUS-CODE ADR) %PHT-SWAP-STATUS-WIRED))
      (FORMAT T "~S " (AREF (SYMBOL-FUNCTION 'SYS:AREA-NAME)
			    (%AREA-NUMBER
			      (ASH (%P-LDB %%PHT1-VIRTUAL-PAGE-NUMBER ADR) 8)))))))



;(DEFCONST NUMERIC-ARG-DESC-INFO '(
;;  %%ARG-DESC-QUOTED-REST 2501
;;  %%ARG-DESC-EVALED-REST 2401
;;  %%ARG-DESC-ANY-REST 2402			;NON-ZERO IF HAS EITHER KIND OF REST ARG
;;  %%ARG-DESC-FEF-QUOTE-HAIR 2301		; CALLER MUST CHECK A-D-L FOR FULL INFO
;;  %%ARG-DESC-INTERPRETED 2201			; NO INFORMATION AVAILABLE (VAL=1000077)
;;  %%ARG-DESC-FEF-BIND-HAIR 2101			; LINEAR ENTER MUST CHECK A-D-L
;  %%ARG-DESC-MIN-ARGS 0606			;MINIMUM NUMBER OF REQUIRED ARGS
;  %%ARG-DESC-MAX-ARGS 0006			;MAXIMUM NUMBER OF REQUIRED+OPTIONAL
;						; ARGS.  REST ARGS NOT COUNTED.
;  ))

(defun describe-args-info (args-info)
  (unless (fixnump args-info) (setq args-info (args-info args-info)))
  (dolist (x '((%%arg-desc-interpreted . "~%~:[Compiled//microcoded~;Interpreted~] function")
	       (%%arg-desc-any-rest . "~@[~%Has rest argument~]")
	       (%%arg-desc-quoted-rest . "~@[~% Has quoted rest arg~]")
	       (%%arg-desc-evaled-rest . "~@[~% Has evalled rest arg~]")
	       (%%arg-desc-fef-quote-hair
		 . "~@[~%Hairy fef arg quoting (caller must check FEF ADL)~]")
	       (%%arg-desc-fef-bind-hair . "~@[~%Hairy fef binding~]")
	       (%%arg-desc-min-args . "~*~%Minimum ~D. args.")
	       (%%arg-desc-max-args . "~*~%Maximum ~D. args.")))
    (let ((tem (ldb (symbol-value (car x)) args-info)))
      (format t (cdr x) (not (zerop tem)) tem)))
  (fresh-line))