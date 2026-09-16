;;; FEF Disassembler -*- Mode:LISP; Package:COMPILER; Base:8; Readtable:T -*-
;	** (c) Copyright 1980 Massachusetts Institute of Technology **
;;; This stuff is used by SYS: SYS2; EH >.  If you change things around,
;;; make sure not to break that program.

;; Aesthetic note:
;;  do not change (princ 'foo) or (format t "~A" 'foo) into (format t "FOO")
;;  as that loses when *print-case* neq :upcase
(DEFVAR DISASSEMBLE-OBJECT-OUTPUT-FUN NIL)
(DEFUN DISASSEMBLE (FUNCTION &AUX FEF LIM-PC ILEN (DISASSEMBLE-OBJECT-OUTPUT-FUN NIL))
  "Print a disassembly of FUNCTION on *STANDARD-OUTPUT*.
FUNCTION can be a compiled function, an LAMBDA-expression (which will be compiled),
or a function spec (whose definition will be used)."
  (DO ((FUNCTION FUNCTION)) (())
    (COND ((TYPEP FUNCTION 'COMPILED-FUNCTION)
	   (SETQ FEF FUNCTION)
	   (RETURN))
	  ((MEMQ (CAR-SAFE FUNCTION) '(LAMBDA NAMED-LAMBDA SUBST CLI:SUBST NAMED-SUBST))
	   (SETQ FEF (COMPILE-LAMBDA FUNCTION (GENSYM)))
	   (RETURN))
	  ((EQ (CAR-SAFE FUNCTION) 'MACRO)
	   (FORMAT T "~%Definition as macro")
	   (SETQ FUNCTION (CDR FUNCTION)))
	  ((TYPEP FUNCTION 'CLOSURE)
	   (FORMAT T "~%Definition of closed-over function")
	   (SETQ FUNCTION (CLOSURE-FUNCTION FUNCTION)))
	  (T
	   (SETQ FUNCTION (SI:DWIMIFY-PACKAGE FUNCTION))
	   (SETQ FUNCTION (FDEFINITION (SI:UNENCAPSULATE-FUNCTION-SPEC FUNCTION))))))
  (WHEN (GET-MACRO-ARG-DESC-POINTER FEF)
    (SI:DESCRIBE-FEF-ADL FEF)
    (TERPRI))
  (SETQ LIM-PC (DISASSEMBLE-LIM-PC FEF))
  (DO ((PC (FEF-INITIAL-PC FEF) (+ PC ILEN))) (( PC LIM-PC))
    (TERPRI)
    (SETQ ILEN (DISASSEMBLE-INSTRUCTION FEF PC)))
  (TERPRI)
  FUNCTION)

(DEFF DISASSEMBLE-INSTRUCTION-LENGTH 'FEF-INSTRUCTION-LENGTH)
(DEFF DISASSEMBLE-FETCH 'FEF-INSTRUCTION)
(DEFF DISASSEMBLE-LIM-PC 'FEF-LIMIT-PC)

(DEFUN DISASSEMBLE-INSTRUCTION (FEF PC &AUX WD OP SUBOP DEST REG DISP ILEN SECOND-WORD)
  "Print on *STANDARD-OUTPUT* the disassembly of the instruction at PC in FEF.
Returns the length of that instruction."
  (SETQ ILEN (DISASSEMBLE-INSTRUCTION-LENGTH FEF PC))
  (BLOCK NIL
    (SETQ WD (DISASSEMBLE-FETCH FEF PC))
    (FORMAT T "~3D " pc)
    (SETQ OP (LDB #o1104 WD)
	  SUBOP (LDB #o1503 WD)
	  DEST (LDB #o1602 WD)
	  DISP (LDB #o0011 WD)
	  REG (LDB #o0603 WD))
    (COND ((= ILEN 2)
	   (INCF PC)
	   (SETQ SECOND-WORD (DISASSEMBLE-FETCH FEF PC))
	   ;; If a two-word insn has a source address, it must be an extended address,
	   ;; so set up REG and DISP to be right for that.
	   (UNLESS (= OP #o14)
	     (SETQ REG (LDB #o0603 SECOND-WORD)
		   DISP (DPB (LDB #o1104 SECOND-WORD)
			     #o0604 (LDB #o0006 SECOND-WORD))))))
    (IF (< OP #o11) (SETQ OP (LDB #o1105 WD)))
    (COND ((ZEROP WD)
	   (PRINC 0))
	  ((< OP #o11)				;DEST/ADDR 
	   (FORMAT T "~A ~A" (NTH OP '(CALL CALL0 MOVE CAR CDR CADR CDDR CDAR CAAR))
		   	     (NTH DEST '(D-IGNORE D-PDL D-RETURN D-LAST)))
	   (DISASSEMBLE-ADDRESS FEF REG DISP SECOND-WORD))
	  ((= OP #o11)				;ND1
	   (PRINC (NTH SUBOP '(ND1-UNUSED + - * // LOGAND LOGXOR LOGIOR)))
	   (DISASSEMBLE-ADDRESS FEF REG DISP SECOND-WORD))
	  ((= OP #o12)				;ND2
	   (PRINC (NTH SUBOP '(= > < EQ SETE-CDR SETE-CDDR SETE-1+ SETE-1-)))
	   (DISASSEMBLE-ADDRESS FEF REG DISP SECOND-WORD))
	  ((= OP #o13)				;ND3
	   (PRINC (NTH SUBOP '(BIND-OBSOLETE? BIND-NIL BIND-POP
			       SET-NIL SET-ZERO PUSH-E MOVEM POP)))
	   (DISASSEMBLE-ADDRESS FEF REG DISP SECOND-WORD))
	  ((= OP #o14)				;BRANCH
	   (PRINC (NTH SUBOP '(BR BR-NIL BR-NOT-NIL BR-NIL-POP
			       BR-NOT-NIL-POP BR-ATOM BR-NOT-ATOM BR-ILL-7)))
	   (IF (> DISP #o400) (SETQ DISP (LOGIOR #o-400 DISP)))	;Sign-extend
	   (IF (NEQ DISP -1)
	       ;; One word
	       (FORMAT T " ~D" (+ PC DISP 1))
	     ;; Long branch
	     (SETQ DISP SECOND-WORD)
	     (IF ( DISP #o100000) (SETQ DISP (LOGIOR #o-100000 DISP)))
	     (FORMAT T " ~A ~D" 'LONG (+ PC DISP 1))
	     (RETURN)))
	  ((= OP #o15)				;MISC
	   (FORMAT T "(~A) " 'MISC)		;Moon likes to see this
	   (IF (BIT-TEST 1 SUBOP)
	       (SETQ DISP (+ DISP #o1000)))
	   (COND ((< DISP #o200)
		  (FORMAT T "~A (~D) "
			  (NTH (LDB #o0403 DISP)
			       '(AR-1 ARRAY-LEADER %INSTANCE-REF UNUSED-AREFI-3
				 AS-1 STORE-ARRAY-LEADER %INSTANCE-SET UNUSED-AREFI-7))
			  (+ (LDB #o0004 DISP)
			     (IF (= (LDB #o0402 DISP) 2) 1 0))))
		 ((< DISP #o220)
		  (FORMAT T "~A ~D binding~:P " 'UNBIND (- DISP #o177))	;200 does 1 unbind.
		  (AND (ZEROP DEST) (RETURN)))
		 ((< DISP #o240)
		  (FORMAT T "~A ~D time~:P " 'PDL-POP (- DISP #o220))	;220 does 0 pops.
		  (AND (ZEROP DEST) (RETURN)))
		 ((= DISP #o460)		;(GET 'INTERNAL-FLOOR-1 'QLVAL)
		  (PRINC (NTH DEST '(FLOOR CEILING TRUNCATE ROUND)))
		  (PRINC " one value to stack")
		  (SETQ DEST NIL))
		 ((= DISP #o510)		;(GET 'INTERNAL-FLOOR-2 'QLVAL)
		  (PRINC (NTH DEST '(FLOOR CEILING TRUNCATE ROUND)))
		  (PRINC " two values to stack")
		  (SETQ DEST NIL))
		 (T
                  (LET ((OP (MICRO-CODE-SYMBOL-NAME-AREA (- DISP #o200))))
                    (IF (NULL OP) (FORMAT T "#~O " DISP) (FORMAT T "~A " OP)))))
	   (WHEN DEST (PRINC (NTH DEST '(D-IGNORE D-PDL D-RETURN D-LAST)))))
	  ((= OP #o16)				;ND4
	   (CASE SUBOP
	     (0 (FORMAT T "STACK-CLOSURE-DISCONNECT  local slot ~D" DISP))
	     (1 (LET ((LOCALNUM
			(LDB #o0012 (NTH DISP
					 (%P-CONTENTS-OFFSET
					   FEF (- (%P-LDB %%FEFH-PC-IN-WORDS FEF) 2))))))
		  (PRINC 'STACK-CLOSURE-UNSHARE)
		  (FORMAT T " ~A|~D" 'LOCAL LOCALNUM)
		  (LET ((TEM (DISASSEMBLE-LOCAL-NAME FEF LOCALNUM)))
		    (AND TEM (FORMAT T " ~30,8T;~A" TEM)))))
	     (2 (FORMAT T "~A  local slot ~D" 'MAKE-STACK-CLOSURE DISP))
	     (3 (FORMAT T "~A ~S" 'push-number DISP))
	     (4 (FORMAT T "~A  local slot ~D" 'STACK-CLOSURE-DISCONNECT-FIRST DISP))
	     (5 (PRINC 'PUSH-CDR-IF-CAR-EQUAL)
		(TYO #/SPACE)
		(DISASSEMBLE-ADDRESS FEF REG DISP SECOND-WORD PC))
	     (6 (PRINC 'PUSH-CDR-STORE-CAR-IF-CONS)
		(TYO #/SPACE)
		(DISASSEMBLE-ADDRESS FEF REG DISP SECOND-WORD PC))
	     (T (FORMAT T "UNDEF-ND4-~D ~D" SUBOP DISP))))
	  ((= OP #o20)
	   (FORMAT T "~A (~D) "
		   (NTH REG
			'(AR-1 ARRAY-LEADER %INSTANCE-REF COMMON-LISP-AR-1
			  SET-AR-1 SET-ARRAY-LEADER SET-%INSTANCE-REF UNUSED-AREFI))
		   (+ (LDB #o0006 DISP)
		      (IF (MEMQ REG '(2 6)) 1 0)))
	   (PRINC (NTH DEST '(D-IGNORE D-PDL D-RETURN D-LAST))))
	  (T					;UNDEF
	   (FORMAT T "UNDEF-~O" op))))
  ILEN)

;;; This ought to figure out which flavor's mapping table is going to be current
;;; at a certain PC, assuming that the compiled code explicitly sets it up.
(DEFUN DISASSEMBLE-CURRENT-FLAVOR (FEF PC)
  FEF PC
  NIL)

(DEFUN DISASSEMBLE-ADDRESS (FEF REG DISP &OPTIONAL SECOND-WORD PC &AUX TEM)
  "Print out the disassembly of an instruction source address.
REG is the register number of the address, and DISP is the displacement.
SECOND-WORD should be the instruction's second word if it has two.
PC should be where the instruction was found in the FEF."
  (TYO #/SPACE)
  ;; In a one-word instruction, the displacement for types 4 thru 7 is only 6 bits,
  ;; so ignore the rest.  In a two word insn, we have been fed the full disp from word 2.
  (IF (AND ( REG 4) (NOT SECOND-WORD))
      (SETQ DISP (LOGAND #o77 DISP)))
  (COND ((< REG 4)
	  (FORMAT T "~A|~D ~30,8T;" 'FEF DISP)
	  (DISASSEMBLE-POINTER FEF DISP PC))
	((= REG 4)
	 (FORMAT T "'~S" (CONSTANTS-AREA DISP)))
        ((= REG 5)
         (FORMAT T "~A|~D" 'LOCAL DISP)
         (SETQ TEM (DISASSEMBLE-LOCAL-NAME FEF DISP))
         (AND TEM (FORMAT T " ~30,8T;~A" TEM)))
        ((= REG 6)
         (FORMAT T "~A|~D" 'ARG DISP)
         (SETQ TEM (DISASSEMBLE-ARG-NAME FEF DISP))
         (AND TEM (FORMAT T " ~30,8T;~A" TEM)))
	((AND (NOT SECOND-WORD) (= DISP #o77))
	 (PRINC 'PDL-POP))
	((< DISP #o40)
         (FORMAT T "~A|~D" SELF DISP)
         (SETQ TEM (DISASSEMBLE-INSTANCE-VAR-NAME FEF DISP))
         (AND TEM (FORMAT T " ~30,8T;~A" TEM)))
	((< DISP #o70)
         (FORMAT T "~A|~D" 'SELF-MAP (- DISP #o40))
         (SETQ TEM (DISASSEMBLE-MAPPED-INSTANCE-VAR-NAME FEF (- DISP #o40)))
         (AND TEM (FORMAT T " ~30,8T;~A" TEM)))
	(T (FORMAT T "PDL|~D (undefined)" DISP))))

(DEFUN DISASSEMBLE-POINTER (FEF DISP PC &AUX CELL LOC PTR OFFSET TEM)
  (SETQ LOC (%MAKE-POINTER-OFFSET DTP-LOCATIVE FEF DISP))
  (COND ((= (%P-LDB-OFFSET %%Q-DATA-TYPE FEF DISP) DTP-SELF-REF-POINTER)
	 (MULTIPLE-VALUE-BIND (PTR COMPONENT-FLAVOR-FLAG)
	     (SI:FLAVOR-DECODE-SELF-REF-POINTER 
	       (OR (DISASSEMBLE-CURRENT-FLAVOR FEF PC)
		   (SI:FEF-FLAVOR-NAME FEF))
	       (%P-LDB-OFFSET %%Q-POINTER FEF DISP))
	   (IF (NULL PTR)
	       (SETQ CELL "self-ref-pointer " PTR (%P-LDB-OFFSET %%Q-POINTER FEF DISP))
	     (SETQ CELL (IF COMPONENT-FLAVOR-FLAG "mapping table for " ""))
	     (IF DISASSEMBLE-OBJECT-OUTPUT-FUN
		 (FUNCALL DISASSEMBLE-OBJECT-OUTPUT-FUN PTR CELL LOC T)
	       (FORMAT T "~A~S" CELL PTR)
	       (IF (EQUAL CELL "")
		   (PRINC " in SELF"))))))
	((= (%P-LDB-OFFSET %%Q-DATA-TYPE FEF DISP) DTP-EXTERNAL-VALUE-CELL-POINTER)
	 (SETQ PTR (%FIND-STRUCTURE-HEADER
		     (SETQ TEM (%P-CONTENTS-AS-LOCATIVE-OFFSET FEF DISP)))
	       OFFSET (%POINTER-DIFFERENCE TEM PTR))
	 (COND ((SYMBOLP PTR)
		(SETQ CELL (NTH OFFSET '("@+0?? "
					 ""
					 "#'"
					 "@PLIST-HEAD-CELL "
					 "@PACKAGE-CELL "))))
	       ((CONSP PTR)
		(SETQ PTR (CAR PTR) CELL "#'"))
	       (T (SETQ CELL "")))
	 (IF DISASSEMBLE-OBJECT-OUTPUT-FUN
	     (FUNCALL DISASSEMBLE-OBJECT-OUTPUT-FUN PTR CELL LOC T)
	   (FORMAT T "~A~S" CELL PTR)))
	(T
	 (IF DISASSEMBLE-OBJECT-OUTPUT-FUN
	     (FUNCALL DISASSEMBLE-OBJECT-OUTPUT-FUN (CAR LOC) "'" LOC NIL)
	   (FORMAT T "'~S" (%P-CONTENTS-OFFSET FEF DISP))))))

;;; Given a fef and an instance variable slot number,
;;; find the name of the instance variable,
;;; if the fef knows which flavor is involved.
(DEFUN DISASSEMBLE-INSTANCE-VAR-NAME (FEF SLOTNUM)
  (LET ((FLAVOR (GET (CADR (ASSQ :FLAVOR (SI:FUNCTION-DEBUGGING-INFO FEF))) 'SI:FLAVOR)))
    (AND FLAVOR (NTH SLOTNUM (SI:FLAVOR-ALL-INSTANCE-VARIABLES FLAVOR)))))

(DEFUN DISASSEMBLE-MAPPED-INSTANCE-VAR-NAME (FEF MAPSLOTNUM)
  (LET ((FLAVOR (GET (CADR (ASSQ ':FLAVOR (SI:FUNCTION-DEBUGGING-INFO FEF))) 'SI:FLAVOR)))
    (AND FLAVOR (NTH MAPSLOTNUM (SI:FLAVOR-MAPPED-INSTANCE-VARIABLES FLAVOR)))))

;;; Given a fef and the number of a slot in the local block,
;;; return the name of that local (or NIL if unknown).
;;; If it has more than one name due to slot-sharing, we return a list of
;;; the names, but if there is only one name we return it.
(DEFUN DISASSEMBLE-LOCAL-NAME (FEF LOCALNUM)
  (LET ((FDI (SI:FUNCTION-DEBUGGING-INFO FEF)))
    (LET ((NAMES (NTH LOCALNUM (CADR (ASSQ 'COMPILER:LOCAL-MAP FDI)))))
      (COND ((NULL NAMES) NIL)
	    ((NULL (CDR NAMES)) (CAR NAMES))
	    (T NAMES)))))

;; Given a fef and the number of a slot in the argument block,
;; return the name of that argument (or NIL if unknown).
;; First we look for an arg map, then we look for a name in the ADL.
(DEFUN DISASSEMBLE-ARG-NAME (FEF ARGNUM
			     &AUX (FDI (SI:FUNCTION-DEBUGGING-INFO FEF))
			          (ARGMAP (CADR (ASSQ 'COMPILER:ARG-MAP FDI))))
  (IF ARGMAP
      (CAR (NTH ARGNUM ARGMAP))
    (DO ((ADL (GET-MACRO-ARG-DESC-POINTER FEF) (CDR ADL))
	 (IDX 0 (1+ IDX))
	 (ADLWORD))
	((NULL ADL))
      (SETQ ADLWORD (CAR ADL))
      (SELECT (MASK-FIELD %%FEF-ARG-SYNTAX ADLWORD)
	((FEF-ARG-REQ FEF-ARG-OPT))
	(OTHERWISE (RETURN)))
      (IF (= 1 (LDB %%FEF-NAME-PRESENT ADLWORD))
	  (SETQ ADL (CDR ADL)))
      (WHEN (= IDX ARGNUM)
	(RETURN (AND (= 1 (LDB %%FEF-NAME-PRESENT ADLWORD)) (CAR ADL))))
      (SELECT (MASK-FIELD %%FEF-INIT-OPTION ADLWORD)
	((FEF-INI-PNTR FEF-INI-C-PNTR FEF-INI-OPT-SA FEF-INI-EFF-ADR)
	 (SETQ ADL (CDR ADL)))))))
