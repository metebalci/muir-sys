;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:8; Readtable:ZL -*-
;;; This is file of definitions of the format of stack groups.   dlw 10/15/77
;;; It will be used by error handlers.
;	** (c) Copyright 1980 Massachusetts Institute of Technology **

;If this file is changed, it goes without saying that you need to make a new cold load.
;(Comments below may not be correct!)
;  Also COLD; QCOM and COLD;GLOBAL must be changed to agree.
;  SYS:COLD;SYSTEM has a list of the symbols defined here which belong in the SYSTEM package

;The microcode must be reassembled, and at least the following must be recompiled:
;    SYS2;EH >, SYS2;EHF >, SYS; QMISC > (for DESCRIBE)
;    SYS2;PROCES >, SYS;LTOP > (for PROCESS-WAIT), SYS2;QTRACE (for FUNCTION-ACTIVE-P)
;
;also CC;CC > Also zillions of other things. si:find-users-of-objects...

(DEFSTRUCT (STACK-GROUP :ARRAY-LEADER (:CONC-NAME SG-) (:CONSTRUCTOR NIL) (:ALTERANT NIL))
  (NAME NIL :DOCUMENTATION "String with the name of the stack group")
  (REGULAR-PDL nil :DOCUMENTATION "Regular PDL array, 0=base of stack")
  (REGULAR-PDL-LIMIT nil :documentation "Max reg pdl depth before trap")
  (SPECIAL-PDL nil :documentation "Special PDL array, 0=base of stack")
  (SPECIAL-PDL-LIMIT nil :documentation "Max spec pdl depth before trap")
  (INITIAL-FUNCTION-INDEX nil :documentation
    "Index into PDL of initial M-AP. (3 unless initial call has adi)")
  (PLIST nil :documentation "Not clear yet. Debugger uses this for communication")
  (TRAP-TAG nil :documentation
    "Symbolic tag corresponding to SG-TRAP-MICRO-PC.
Gotten via MICROCODE-ERROR-TABLE, etc.  Properties off this symbol drive error recovery.")
  (RECOVERY-HISTORY nil :documentation
    "Available for hairy SG munging routines to attempt to leave tracks.
This is not used presently.")
  (FOOTHOLD-DATA nil :DOCUMENTATION
    "During error recovery, contains pointer to a stack frame which contains saved status
of the main stack group. (Preventing it from being lost when the foothold is running.)")
  ((STATE)
   (CURRENT-STATE (byte 6 0) 0 :documentation "State of this stack group")
   (FOOTHOLD-EXECUTING-FLAG (byte 1 6) 0 :documentation "Not used")
   (PROCESSING-ERROR-FLAG (byte 1 7) 0 :documentation
     "Taking error trap (detect recursive errors)")
   (PROCESSING-INTERRUPT-FLAG (byte 1 8.) 0 :documentation "Not used")
   (SAFE (byte 1 9.))
   (INST-DISP (byte 2 10.) 0 :documentation "The instruction dispatch we are using")
   (IN-SWAPPED-STATE (byte 1 22.) 0 :documentation
     "We are in the swapped state")
   (SWAP-SV-ON-CALL-OUT (byte 1 21.) 0 :documentation 
     "If this is on in the caller,then swap")
   (SWAP-SV-OF-SG-THAT-CALLS-ME (byte 1 20.) 0 :documentation
     "If this is on in the callee, then swap"))
  (PREVIOUS-STACK-GROUP nil :documentation "Stack group which just ran")
  (CALLING-ARGS-POINTER nil :documentation
    "Pointer into previous stack group's REGPDL to the args passed to us.")
  CALLING-ARGS-NUMBER
  (TRAP-AP-LEVEL nil :documentation
    "Locative to a location in PDL Buffer, below which traps occur")
  (REGULAR-PDL-POINTER nil :documentation
    "Saved pdl pointer (as index into regular-pdl array)")
  (SPECIAL-PDL-POINTER nil :documentation
     "Saved A-QLBNDP (as index into special-pdl array)")
  AP						;Saved M-AP
  IPMARK					;Saved A-IPMARK
  (TRAP-MICRO-PC nil :documentation "Address of last call to TRAP")
; ERROR-HANDLING-SG				;Having these part of the SG would be nice,
; INTERRUPT-HANDLING-SG				; however, it doesnt buy anything for the time
						; being, and costs a couple microinstructions.
  SAVED-QLARYH					;Saved A-QLARYH
  SAVED-QLARYL					;Saved A-QLARYL
  ((SAVED-M-FLAGS)				;Saved M-FLAGS
   (FLAGS-QBBFL %%M-FLAGS-QBBFL)		; Binding-block-pushed flag
   (FLAGS-CAR-SYM-MODE %%M-FLAGS-CAR-SYM-MODE)	;UPDATE PRINT-ERROR-MODE IN QMISC
   (FLAGS-CAR-NUM-MODE %%M-FLAGS-CAR-NUM-MODE)	;  IF ADD ANY..
   (FLAGS-CDR-SYM-MODE %%M-FLAGS-CDR-SYM-MODE) 
   (FLAGS-CDR-NUM-MODE %%M-FLAGS-CDR-NUM-MODE) 
   (FLAGS-DONT-SWAP-IN %%M-FLAGS-DONT-SWAP-IN)
   (FLAGS-TRAP-ENABLE %%M-FLAGS-TRAP-ENABLE)
   (FLAGS-MAR-MODE %%M-FLAGS-MAR-MODE)
   (FLAGS-PGF-WRITE %%M-FLAGS-PGF-WRITE)
   (FLAGS-METER-ENABLE %%M-FLAGS-METER-ENABLE)
   (FLAGS-TRAP-ON-CALL %%M-FLAGS-TRAP-ON-CALL)
   )
  AC-K
  AC-S
  AC-J 
  AC-I
  AC-Q
  AC-R
  AC-T
  AC-E
  AC-D
  AC-C 
  AC-B
  AC-A
  AC-ZR
  (AC-2 0 :documentation "Pointer field of M-2 as fixnum")
  (AC-1 0 :documentation "Pointer field of M-1 as fixnum")
  (VMA-M1-M2-TAGS 0 :documentation "Tag fields of VMA, M-1, M-2 packed into a fixnum")
  (SAVED-VMA nil :documentation "Pointer field of VMA as a locative")
  (PDL-PHASE nil :documentation
    "This is the actual value of PDL-BUFFER-POINTER reg.
If you mung the sg's stack pointer, do same to this"))


;; this is here so the debuggger knows that these potentially contain dangerous garbage
;; ac-1 and ac-2 aren't here as they always contain a fixnum, and hence are safe to read.
(defconst sg-accumulators '(
  SG-AC-K
  SG-AC-S
  SG-AC-J 
  SG-AC-I
  SG-AC-Q
  SG-AC-R
  SG-AC-T
  SG-AC-E
  SG-AC-D
  SG-AC-C 
  SG-AC-B
  SG-AC-A
  SG-AC-ZR
  ))

(DEFSTRUCT (REGULAR-PDL :ARRAY-LEADER (:CONSTRUCTOR NIL) (:ALTERANT NIL))
  REGULAR-PDL-SG)

(DEFSTRUCT (SPECIAL-PDL :ARRAY-LEADER (:CONSTRUCTOR NIL) (:ALTERANT NIL))
  SPECIAL-PDL-SG)

;; Defsubsts for accessing the Regular Pdl.

(DEFSUBST RP-CALL-WORD     (RP AP) (AREF RP (+ AP %LP-CALL-STATE)))
(DEFSUBST RP-EXIT-WORD     (RP AP) (AREF RP (+ AP %LP-EXIT-STATE)))
(DEFSUBST RP-ENTRY-WORD    (RP AP) (AREF RP (+ AP %LP-ENTRY-STATE)))
(DEFSUBST RP-FUNCTION-WORD (RP AP) (AREF RP (+ AP %LP-FEF)))

; (DEFINE-RP-MACROS ((RP-FOO %%FOO) (RP-BAR %%BAR)) RP-CALL-WORD)
;
; produces
;
; (PROGN
;   (DEFSUBST RP-FOO (RP AP)
;     (LDB %%FOO (RP-CALL-WORD RP AP)))
;   (DEFSUBST RP-BAR (RP AP)
;     (LDB %%BAR (RP-CALL-WORD RP AP))))

(DEFMACRO DEFINE-RP-MACROS (SPEC-LIST WORD-MACRO)
  (DO ((L SPEC-LIST (CDR L))
       (BYTE)
       (NAME)
       (ACCUM))
      ((NULL L) `(PROGN . ,ACCUM))
    (SETQ NAME (CAAR L) BYTE (CADAR L))
    (PUSH `(DEFSUBST ,NAME (RP AP)
	     (LDB ,BYTE (,WORD-MACRO RP AP)))
	  ACCUM)))

(DEFINE-RP-MACROS ((RP-DOWNWARD-CLOSURE-PUSHED %%LP-CLS-DOWNWARD-CLOSURE-PUSHED)
		   (RP-ADI-PRESENT %%LP-CLS-ADI-PRESENT)
		   (RP-DESTINATION %%LP-CLS-DESTINATION)
		   (RP-DELTA-TO-OPEN-BLOCK %%LP-CLS-DELTA-TO-OPEN-BLOCK)
		   (RP-DELTA-TO-ACTIVE-BLOCK %%LP-CLS-DELTA-TO-ACTIVE-BLOCK)
		   (RP-TRAP-ON-EXIT %%LP-CLS-TRAP-ON-EXIT))
		  RP-CALL-WORD)

(DEFINE-RP-MACROS ((RP-MICRO-STACK-SAVED %%LP-EXS-MICRO-STACK-SAVED)
		   (RP-PC-STATUS %%LP-EXS-PC-STATUS)
		   (RP-BINDING-BLOCK-PUSHED %%LP-EXS-BINDING-BLOCK-PUSHED)	;Same as above
		   (RP-EXIT-PC %%LP-EXS-EXIT-PC))
		  RP-EXIT-WORD)

(DEFINE-RP-MACROS ((RP-NUMBER-ARGS-SUPPLIED %%LP-ENS-NUM-ARGS-SUPPLIED) ;Only for macro frames
		   (RP-LOCAL-BLOCK-ORIGIN				;can this be extended?
		    %%LP-ENS-MACRO-LOCAL-BLOCK-ORIGIN))	;Only for macro frames
		  RP-ENTRY-WORD)

;; Defsubsts for accessing fields of the headers of Function Entry Frames.

(DEFMACRO DEFINE-OFFSET-BYTE-MACROS (PTR . WORDS)
   (DO ((LL WORDS (CDR LL))
	(ACCUM)
        (INDEX 0 (1+ INDEX)))
       ((NULL LL) `(PROGN . ,ACCUM))
      (DO ((L (CAR LL) (CDR L))
           (NAME)
           (BYTE))
          ((NULL L))
         (SETQ NAME (CAAR L) BYTE (CADAR L))
         (PUSH `(DEFSUBST ,NAME (,PTR)
                  (%P-LDB-OFFSET ,BYTE ,PTR ,INDEX))
               ACCUM))))

(DEFINE-OFFSET-BYTE-MACROS FEF
 ((FEF-INITIAL-PC %%FEFH-PC)
  (FEF-NO-ADL-P %%FEFH-NO-ADL)
  (FEF-FAST-ARGUMENT-OPTION-P %%FEFH-FAST-ARG)
  (FEF-SPECIALS-BOUND-P %%FEFH-SV-BIND))
 ((FEF-LENGTH %%Q-POINTER))
 ()
 ((FEF-FAST-ARGUMENT-OPTION-WORD %%Q-POINTER))
 ((FEF-BIT-MAP-P %%FEFHI-SVM-ACTIVE)
  (FEF-BIT-MAP %%FEFHI-SVM-BITS))
 ((FEF-NUMBER-OF-REAL-LOCALS %%FEFHI-MS-LOCAL-BLOCK-LENGTH)
  (FEF-ADL-ORIGIN %%FEFHI-ARG-DESC-ORG)
  (FEF-ADL-LENGTH %%FEFHI-BIND-DESC-LENGTH)))

;;; kind of random that these are here...
(DEFSUBST FEF-NAME (FEF) (%P-CONTENTS-OFFSET FEF %FEFHI-FCTN-NAME))

(DEFSUBST FEF-DEBUGGING-INFO-PRESENT-P (FEF)
  (LDB-TEST %%FEFHI-MS-DEBUG-INFO-PRESENT (%P-CONTENTS-OFFSET FEF %FEFHI-MISC)))

(DEFUN FEF-DEBUGGING-INFO (FEF) 
  (AND (FEF-DEBUGGING-INFO-PRESENT-P FEF)
       (%P-CONTENTS-OFFSET FEF (1- (%P-LDB %%FEFH-PC-IN-WORDS FEF)))))

(DEFSETF FEF-DEBUGGING-INFO SET-FEF-DEBUGGING-INFO)
(DEFLOCF FEF-DEBUGGING-INFO LOCATE-FEF-DEBUGGING-INFO)

(DEFUN SET-FEF-DEBUGGING-INFO (FEF VALUE)
  (IF (FEF-DEBUGGING-INFO-PRESENT-P FEF)
      (LET ((%INHIBIT-READ-ONLY T))
	(SETF (%P-CONTENTS-OFFSET FEF (1- (%P-LDB %%FEFH-PC-IN-WORDS FEF))) VALUE))
    (FERROR NIL "The FEF ~S has nowhere to put debugging-info" FEF)))
(DEFUN LOCATE-FEF-DEBUGGING-INFO (FEF)
  (IF (FEF-DEBUGGING-INFO-PRESENT-P FEF)
      (%MAKE-POINTER-OFFSET DTP-LOCATIVE (FOLLOW-STRUCTURE-FORWARDING FEF)
					 (1- (%P-LDB %%FEFH-PC-IN-WORDS FEF)))
    (FERROR NIL "The FEF ~S has no debugging-info" FEF)))


;; Randomness.
;   %%US-RPC						;RETURN PC
;   %%US-PPBMIA						;ADI ON MICRO-TO-MICRO-CALL
;   %%US-PPBMAA						;ADI ON MACRO-TO-MICRO-CALL
;   %%US-PPBSPC						;BINDING BLOCK PUSHED

;%%ADI-TYPE						;ADI-KINDS
;    ADI-RETURN-INFO
;       %%ADI-RET-STORING-OPTION			;ADI-STORING-OPTIONS
;          ADI-ST-BLOCK ADI-ST-LIST 
;	  ADI-ST-MAKE-LIST
;	  ADI-ST-INDIRECT
;       %%ADI-RET-SWAP-SV
;       %%ADI-RET-NUM-VALS-EXPECTING 
;    ADI-RESTART-PC
;       %%ADI-RPC-MICRO-STACK-LEVEL
;    ADI-FEXPR-CALL 
;    ADI-LEXPR-CALL
;    ADI-BIND-STACK-LEVEL
;    ADI-USED-UP-RETURN-INFO
