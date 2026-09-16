;;; -*- Mode:LISP; Package:CADR; Base:8.-*-
;;; ** (C) Copyright 1981, Symbolics, Inc.
;;; The Massachusetts Institute of Technology has acquired the rights from Symbolics
;;; to include the Software covered by the foregoing notice of copyright with its
;;; licenses of the Lisp Machine System **

;;; Semi-automated crash analysis, for users' benefit

(DEFUN CC-MAIL ()
  (PKG-BIND "CADR"
    (LET ((BASE 8.) (IBASE 8.)			;Simulate the CC environment
	  CC-UPDATE-DISPLAY-FLAG CC-OPEN-REGISTER 
	  CC-LAST-OPEN-REGISTER CC-LAST-VALUE-TYPED)
      (CC-CONSOLE-INIT)
      (CC-MAIL-INTERNAL))))

;;; Assume user has gone into CC and typed control-S if necessary

(DEFUN (MAIL CC-COLON-CMD) (IGNORE)
  (TERPRI)
  (CC-MAIL-INTERNAL))

(DEFUN CC-MAIL-INTERNAL ()
  (BUG 'HARDWARE
       (WITH-OUTPUT-TO-STRING (STANDARD-OUTPUT)
	 (PRINC "Insert your description of the circumstances, and how often the problem occurs:

")
	 (TERPRI)
	 (TERPRI)
	 (LET ((ERROR-OUTPUT STANDARD-OUTPUT))
	   (CONDITION-CASE (.ERROR.)
	       (WHY-TEXT T)
	     (ERROR (FORMAT T "Error printing debugging information:~%  ~A" .ERROR.)))))
       (LENGTH "Insert your description of the circumstances, and how often the problem occurs:

")))

(DEFUN WHY-TEXT (MAIL-P)
  (PROG ()
    (QF-CLEAR-CACHE T)
    (QF-SETUP-PHT-ADDR)
    (UNLESS (CC-PRINT-DEBUGGEE-NAME)
      (RETURN NIL))
    (SELECTQ (CC-CHECK-SERIOUS-ERROR-STATUS)
      (MAIN-MEM-PAR (LET ((VMA (CC-REGISTER-EXAMINE RAVMA)))
		      (CC-ANALYZE-MEM-PAR (CC-VMA-TO-PMA VMA) VMA
					  (CC-REGISTER-EXAMINE RAMD))))
      (MAIN-MEM-PAR-DISK (CC-ANALYZE-MEM-PAR
			   (LOGLDB 0026 (PHYS-MEM-READ (+ CC-DISK-ADDRESS 1))) NIL NIL))
      (DISK-ERR (CC-ANALYZE-DISK-ERR))
      (PROC-PAR (CC-ANALYZE-OPCS) (CC-ANALYZE-PROC-PAR))
      (PROC (CC-ANALYZE-OPCS))
      (OTHERWISE (RETURN (CC-ANALYZE-PROM-OR-SOFTWARE))))
    (IF MAIL-P (CC-ANALYZE-PROM-OR-SOFTWARE)
	(FORMAT T "~%Type :WHYSOFT to attempt to analyze the current software state.~%"))))

;;; Assume user has gone into CC and typed control-S if necessary

(DEFUN (WHY CC-COLON-CMD) (IGNORE)
  (WHY-TEXT NIL))

(DEFUN (WHYSOFT CC-COLON-CMD) (IGNORE)
  (OR (NULL (CC-PRINT-DEBUGGEE-NAME))
      (CC-ANALYZE-PROM-OR-SOFTWARE)))

(DEFUN CC-ANALYZE-PROM-OR-SOFTWARE ()
  (IF (BIT-TEST 1_28. (CC-REGISTER-EXAMINE RASTS))	;Not in the PROM
      (CC-ANALYZE-SOFTWARE-CRASH)
      (CC-ANALYZE-PROM-HALT)))

;Print out any interesting processor, bus interface, or disk error status
;Returns a symbol for the error classification:
;  PROC-PAR	PROC	MAIN-MEM-PAR	MAIN-MEM-PAR-DISK	DISK-ERR
(DEFUN CC-CHECK-SERIOUS-ERROR-STATUS ()
  (LET ((PROC-STATUS (LOGXOR (LDB 2020 (CC-REGISTER-EXAMINE RASTS)) 164000))
	(BUS-STATUS (SELECTQ DBG-ACCESS-PATH
		      (SERIAL (FUNCALL SERIAL-STREAM ':TYO #/R)
			      (READ 'SERIAL-STREAM))
		      (BUSINT (%UNIBUS-READ 766104))
		      (CHAOS (LET ((PKT (DBG-CHAOS 'STATUS 0)))
			       (PROG1 (AREF PKT CHAOS:FIRST-DATA-WORD-IN-PKT)
				      (CHAOS:RETURN-PKT PKT))))
		      (OTHERWISE
		       (FERROR NIL "~A is illegal DBG-ACCESS-PATH" DBG-ACCESS-PATH))))
	(DISK-STATUS (PHYS-MEM-READ CC-DISK-ADDRESS))
	(ERR-CLASS NIL))
    (COND ((BIT-TEST 164377 PROC-STATUS)
	   (FORMAT T "Processor error:~%")
	   (LOOP FOR (BIT STR CLASS) IN '((1 "A-Memory parity error" PROC-PAR)
					  (2 "M-Memory parity error" PROC-PAR)
					  (4 "Pdl-buffer parity error" PROC-PAR)
					  (10 "Micro-Stack parity error" PROC-PAR)
					  (20 "Dispatch-memory parity error" PROC-PAR)
					  (40 "Control-memory parity error" PROC-PAR)
					  (100 "Main-memory parity error" MAIN-MEM-PAR)
					  (200 "Error in /"HI/" runs" PROC)
					  (4000 "Statistics-counter halt")
					  (20000 "First-level map parity error" PROC-PAR)
					  (40000 "Second-level map parity error" PROC-PAR)
					  (100000 "Clock waiting for memory" PROC))
		 WHEN (BIT-TEST BIT PROC-STATUS)
		   DO (FORMAT T "  ~A~%" STR)
		      (AND CLASS (SETQ ERR-CLASS CLASS)))))
    (SETQ BUS-STATUS (LOGAND 77 BUS-STATUS))
    (COND ((NOT (ZEROP BUS-STATUS))
	   (FORMAT T "Bus-interface errors since last reset:~%")
	   (LOOP FOR (BIT STR) IN '((1 "Xbus non-existent memory or device")
				    (2 "Xbus data parity error")
				    (4 "Parity error in address from processor")
				    (10 "Unibus non-existent device")
				    (20 "Parity error in data from processor")
				    (40 "UnibusXbus map error: invalid or write-protect"))
		 WHEN (BIT-TEST BIT BUS-STATUS)
		   DO (FORMAT T "  ~A~%" STR))))
    (COND ((BIT-TEST 07777560 DISK-STATUS)
	   (FORMAT T "Disk error: ~A~%"
		     (SI:DECODE-DISK-STATUS (LDB 0020 DISK-STATUS) (LDB 2020 DISK-STATUS)))
	   (FORMAT T "  disk address: ")
	   (CC-TYPE-OUT (PHYS-MEM-READ (+ CC-DISK-ADDRESS 2)) CC-DISK-DA-DESC T T)
	   (FORMAT T "~%  last memory address touched by disk = ~O~%"
		     (LOGLDB 0026 (PHYS-MEM-READ (+ CC-DISK-ADDRESS 1))))
	   (OR ERR-CLASS (SETQ ERR-CLASS (IF (LDB-TEST (+ 2000	;high half
							  SYS:%%DISK-STATUS-HIGH-MEM-PARITY)
						        DISK-STATUS)
					     'MAIN-MEM-PAR-DISK 'DISK-ERR)))))
    ERR-CLASS))

(DEFUN CC-ANALYZE-OPCS ()
  (CC-GET-PROPER-MICROCODE-SYMBOLS)
  (FORMAT T "~&Micro PC History (OPC's), oldest first:~%")
  (LET ((PROM-P (NOT (BIT-TEST 1_28. (CC-REGISTER-EXAMINE RASTS)))))
    (DOTIMES (I 8)
      (LET ((OPC (CC-REGISTER-EXAMINE (+ RAOPCO I))))
	(FORMAT T "   ~5,'0O   " OPC)
	(OR PROM-P (CC-PRINT-ADDRESS (+ OPC RACMO)))
	(TERPRI)))
    (IF PROM-P (FORMAT T "   ...in the PROM.~%"))))

;Analyze main-memory parity error at specified address, DATA is contents or NIL if unknown
;VADDR is virtual address if known
(DEFUN CC-ANALYZE-MEM-PAR (ADDR VADDR DATA)
  (LET ((MEM-DATA (PHYS-MEM-READ ADDR)))
    (FORMAT T "Memory parity error physical address = ~O, data = ~O~:[, MD data=~O~]~%"
	      ADDR MEM-DATA (AND DATA (NOT (EQUAL DATA MEM-DATA))) DATA)
    (FORMAT T "Address is memory board #~O, bank #~O~%"
	      (LOGLDB 2006 ADDR) (LOGLDB 1602 ADDR))
    (COND ((AND (BIT-TEST 1_28. (CC-REGISTER-EXAMINE RASTS))	;Not in the PROM
		(PROGN (CC-GET-PROPER-MICROCODE-SYMBOLS)	;Not still booting
		       (NOT (ZEROP (CC-SYMBOLIC-EXAMINE-REGISTER 'A-V-AREA-NAME))))
		(OR VADDR (SETQ VADDR (QF-VIRT-ADR-OF-PHYS-ADR ADDR))))
	   (FORMAT T "Checking disk copy of this virtual memory address")
	   (IF (LET ((PHTA (QF-PAGE-HASH-TABLE-LOOKUP VADDR)))
		 (AND (PLUSP PHTA)
		      (OR (LDB-TEST %%PHT1-MODIFIED-BIT (PHYS-MEM-READ PHTA))
			  (= (LDB %%PHT2-MAP-STATUS-CODE (PHYS-MEM-READ (1+ PHTA)))
			     %PHT-MAP-STATUS-READ-WRITE))))
	       (FORMAT T ", even though page is modified.~%")
	       (TERPRI))
	   (LET ((DISK-DATA (QF-MEM-READ-DISK-COPY VADDR)))
	     (IF (EQUAL DISK-DATA MEM-DATA)
		 (FORMAT T "Disk data identical, could be parity bit.")
	         (FORMAT T "Disk data = ~O, differs in bit " DISK-DATA)
		 (CC-PRINT-BITS (LOGXOR DISK-DATA MEM-DATA))))))
    (COND ((Y-OR-N-P "Do you want to try a parity sweep?")
	   (LET ((N-MEMORIES (CEILING (QF-POINTER (PHYS-MEM-READ (+ 400 %SYS-COM-MEMORY-SIZE)))
				      200000)))
	     (OR ( 1 N-MEMORIES 60.) (SETQ N-MEMORIES 2))
	     (FORMAT T "Assuming there are ~D memory boards~%" N-MEMORIES)
	     (IF (> N-MEMORIES 4)
		 (FORMAT T "[Warning: I don't think this works for more than 256K]~%"))
	     (CC-PARITY-SWEEP-INFO (CC-PARITY-SWEEP N-MEMORIES)))))))

;Analyze parity error in internal processor memories
(DEFUN CC-ANALYZE-PROC-PAR ()
  (LET ((PROC-STATUS (LOGXOR (LDB 2020 (CC-REGISTER-EXAMINE RASTS)) 164000)))
    (LOOP FOR (BIT FUNC) IN '((1 CC-SCAN-A-MEM-FOR-BAD-PARITY)
			      (2 CC-SCAN-M-MEM-FOR-BAD-PARITY)
			      (4 CC-SCAN-P-MEM-FOR-BAD-PARITY)
			      (20 CC-SCAN-D-MEM-FOR-BAD-PARITY)
			      (40 CC-SCAN-C-MEM-FOR-BAD-PARITY)
			      (20000 CC-SCAN-LEVEL-1-MAP-FOR-BAD-PARITY)
			      (40000 CC-SCAN-LEVEL-2-MAP-FOR-BAD-PARITY))
	  WHEN (AND (BIT-TEST BIT PROC-STATUS)
		    (FQUERY () "Run ~A? " FUNC))
	    DO (FUNCALL FUNC))))

;Error status has already been printed, but also offer to print the log
(DEFUN CC-ANALYZE-DISK-ERR ()
  (FORMAT T "Contents of disk error log in debugee's main memory 600-640:~%")
  (CC-PRINT-DISK-ERROR-LOG))

;These numbers are for version 9 of the microcode bootstrap prom.
;Unfortunately this doesn't seem to be the installed version on all machines.
;Obviously somebody screwed up.  These numbers are good enough, since the ones
;that are wrong are the 3-digit ones, which mainly apply to disk errors, which
;get analyzed elsewhere.
(DEFUN CC-ANALYZE-PROM-HALT ()
  (LET ((PC (CC-REGISTER-EXAMINE RAPC)))
    (FORMAT T "Halted at location ~O in the microcode bootstrap PROM.~%" PC)
    (LOOP FOR (VAL STR) IN '((10 "Failed to switch from PROM to RAM after loading microcode")
			     (12 "Bit failure in data path")
			     (14 "Failure testing addition or byte extraction")
			     (16 "Bit failure in A-memory")
			     (20 "Bit failure in M-memory")
			     (22 "Bit stuck at 1 in first-level map")
			     (24 "Unexpected page fault")
			     (26 "Disk label corrupted or not read from disk correctly")
			     (30 "Current microcode not found in disk partition map")
			     (32 "Microload file corrupted: bad section type")
			     (34 "Microload file corrupted: bad address to load into")
			     (36 "Microload file corrupted: premature end of partition")
			     (40 "Disk error")		;Shouldn't get here
			     (42 "Spurious division by zero")
			     (44 "Bit failure in pdl-buffer")
			     (552 "Waiting for disk to come on-line")
			     (566 "Waiting for disk error bits to clear")
			     (601 "Waiting for disk control to be idle")
			     (630 "Waiting for disk operation to complete"))
	  WHEN (IF (< VAL 100)
		   (= (LOGAND PC -2) VAL)
		   ( (- VAL 11.) PC VAL))		 
	    RETURN (FORMAT T "Reason=~A~%" STR))))

(DEFUN PRINT-SYMBOLIC-PC (ADDRESS)
  (DECLARE (VALUES SYMBOL OFFSET))
  (LET ((SYMBOLIC-PC (CC-FIND-CLOSEST-SYM ADDRESS)))
    (COND ((NULL SYMBOLIC-PC)
	   (PRINC (- ADDRESS RACMO))
	   (VALUES NIL (- ADDRESS RACMO)))
	  ((CONSP SYMBOLIC-PC)
	   (IF (ZEROP (CADR SYMBOLIC-PC))
	       (PRINC (CAR SYMBOLIC-PC))
	     (FORMAT T "~A+~O" (CAR SYMBOLIC-PC) (CADR SYMBOLIC-PC)))
	   (VALUES-LIST SYMBOLIC-PC))
	  (T (PRINC SYMBOLIC-PC)
	     (VALUES SYMBOLIC-PC 0)))))

;Try to say something about a software halt
;Wear your Kludge-Prufe (TM) goggles when looking at this code
(DEFUN CC-ANALYZE-SOFTWARE-CRASH ()
  (CC-GET-PROPER-MICROCODE-SYMBOLS)
  (LET ((USP (CC-REGISTER-EXAMINE RAUSP))
	(PC (+ RACMO (CC-REGISTER-EXAMINE RAPC)))
	(OPC3 (+ RACMO (CC-REGISTER-EXAMINE (+ RAOPCO 3))))
	(OPC4 (+ RACMO (CC-REGISTER-EXAMINE (+ RAOPCO 4))))
	(OPC6 (+ RACMO (CC-REGISTER-EXAMINE (+ RAOPCO 6))))
	SYMBOLIC-PC
	(PC-OFFSET 0)
	(ILLOP NIL))
    (TERPRI)
    (COND ((EQ (CC-FIND-CLOSEST-SYM OPC6) 'ILLOP)
	   (SETQ ILLOP T)
	   (FORMAT T "Microcode halted via ILLOP from ")
	   (SETF (VALUES SYMBOLIC-PC PC-OFFSET)
		 (PRINT-SYMBOLIC-PC OPC4)))
	  ((MEMQ OPC6 (APPEND CC-BREAKPOINT-LIST CC-TEMPORARY-BREAKPOINT-LIST))
	   (FORMAT T "Microcode halted via breakpoint at ")
	   (PRINT-SYMBOLIC-PC OPC6))
	  (T (FORMAT T
		 "This program doesn't understand why the machine stopped (not ILLOP).~%")))
    (CC-ANALYZE-OPCS)
    (FORMAT T "Backtrace of microcode subroutine stack:~%")
    (LOOP FOR I FROM USP DOWNTO 0
	  AS STK = (CC-REGISTER-EXAMINE (+ RAUSO I))
	  DO (FORMAT T "   ~2O  ~6,'0O   " I STK)
	     (CC-PRINT-ADDRESS (+ RACMO (LOGAND 37777 STK)))
	     (TERPRI))
    (LET* ((FLAGS (CC-SYMBOLIC-EXAMINE-REGISTER 'M-FLAGS))
	   (INT (LDB-TEST %%M-FLAGS-INTERRUPT FLAGS))
	   (SCAV (LDB-TEST %%M-FLAGS-SCAVENGE FLAGS))
	   (TRANSP (LDB-TEST %%M-FLAGS-TRANSPORT FLAGS))
	   (SG (LDB-TEST %%M-FLAGS-STACK-GROUP-SWITCH FLAGS)))
      (COND ((OR INT SCAV TRANSP SG)
	     (PRINC "Microcode state flags")
	     (IF INT (PRINC ": microcode interrupt"))
	     (IF SCAV (PRINC ": in scavenger"))
	     (IF TRANSP (PRINC ": in transporter"))
	     (IF SG (PRINC ": switching stack groups"))
	     (TERPRI))))
    ;; Say something about certain PC's, and about certain ILLOP-calling instructions
    (IF ILLOP
	(COND ((EQ SYMBOLIC-PC 'TRAP)
	       (PRINC "Halted trying to signal an error")
	       (SELECTQ PC-OFFSET
		 (0 (PRINC ", because trapping is disabled"))
		 (2 (PRINC " in scavenger, transporter, interrupt, or stack group switch"))
		 (4 (PRINC " while already trapping an error in this stack group"))
		 (12 (PRINC " in the first-level error-handler stack-group")))
	       (TERPRI)
	       (LET ((ERRPC (IF (< PC-OFFSET 12) (1- PC)
			       (+ (QF-POINTER (CC-SYMBOLIC-EXAMINE-REGISTER 'A-TRAP-MICRO-PC))
				 RACMO))))
		 (CC-DESCRIBE-ERROR-PC "Error was signalled from " ERRPC T)
		 (COND ((= PC-OFFSET 4)
			(CC-DESCRIBE-ERROR-PC "~%Previous error was from "
					      (+ (QF-POINTER (CC-SYMBOLIC-EXAMINE-REGISTER
							       'A-TRAP-MICRO-PC))
						 RACMO)))
		       ((= PC-OFFSET 12)
			(CATCH-ERROR
			  (LET ((SG (CC-SYMBOLIC-EXAMINE-REGISTER
							'A-SG-PREVIOUS-STACK-GROUP)))
			    (FORMAT T "~%Previous stack group was ")
			    (CC-Q-PRINT-TOPLEV SG)
			    (CC-DESCRIBE-ERROR-PC
			      "~%Last error in that stack group was from "
			      (+ (QF-POINTER (QF-MEM-READ (- SG SG-TRAP-MICRO-PC 2))) RACMO))
			    )))))
	       (TERPRI))
	      ((AND (EQ SYMBOLIC-PC 'INTR-0) (= PC-OFFSET 3))
	       (FORMAT T "Interrupt from unknown Unibus device, vector=~O~%"
		       (CC-SYMBOLIC-EXAMINE-REGISTER 'M-B)))
	      (T (LET* ((ILLINS (CC-REGISTER-EXAMINE OPC4))
			(MSRC (CC-INSTRUCTION-M-SOURCE-REG-ADR ILLINS))
			(CASE2 NIL))
		   (COND ((OR (AND (= (LDB CONS-IR-OP ILLINS) CONS-OP-DISPATCH)
				   (= (LDB CONS-IR-DISP-BYTL ILLINS) 5)	;data type dispatch
				   (= (LDB CONS-IR-MROT ILLINS) 10))
			      (AND (= (LDB CONS-IR-OP ILLINS) CONS-OP-JUMP)
				   (= (LDB CONS-IR-JUMP-COND ILLINS) CONS-JUMP-COND-M-NEQ-A)
				   ( RAMMO MSRC)
				   (< MSRC RAMME)
				   (LET ((PRED (CC-REGISTER-EXAMINE OPC3)))
				     (AND (= (LDB CONS-IR-OP PRED) CONS-OP-BYTE)
					  (= (+ (LDB CONS-IR-M-MEM-DEST PRED) RAMMO) MSRC)
					  (NOT (BIT-TEST CONS-A-MEM-DEST-INDICATOR
							 (LDB CONS-IR-A-MEM-DEST PRED)))
					  (= (LDB CONS-IR-BYTL-1 PRED) 4)
					  (= (LDB CONS-IR-MROT PRED) 10)
					  (SETQ MSRC (CC-INSTRUCTION-M-SOURCE-REG-ADR PRED)
						CASE2 T)))))
			  (PRINC "Halted due to bad data type: ")
			  (CC-PRINT-ADDRESS-AND-CONTENTS MSRC CC-Q-DESC)
			  (FORMAT T "  from microcode:~%") 
			  (IF CASE2 (CC-PRINT-ADDRESS-AND-CONTENTS OPC3))
			  (CC-PRINT-ADDRESS-AND-CONTENTS OPC4))
			 ((AND (= (LDB CONS-IR-OP ILLINS) CONS-OP-JUMP)
			       (= (LDB CONS-IR-JUMP-COND ILLINS) CONS-JUMP-COND-PAGE-FAULT))
			  (FORMAT T "Halted due to unexpected page fault, VMA=~O, maps="
				  (CC-REGISTER-EXAMINE RAVMA))
			  (CC-MAPS (CC-REGISTER-EXAMINE RAVMA))))))))
    ;; Now give a macrocode backtrace
    (MULTIPLE-VALUE-BIND (NIL ERROR-P)
	(CATCH-ERROR
	  (LET ((CURSG (CC-SYMBOLIC-EXAMINE-REGISTER 'A-QCSTKG))
		(CP (QF-SYMBOL 'CURRENT-PROCESS)))
	    (FORMAT T "~&Current stack group is: ")
	    (CC-Q-PRINT-TOPLEV CURSG)
	    (COND ((NOT (MINUSP CP))
		   (FORMAT T "~&Current process is: ")
		   (SETQ CP (QF-MEM-READ (1+ CP)))
		   (CC-Q-PRINT-TOPLEV CP)
		   (IF (= (QF-DATA-TYPE CP) DTP-INSTANCE)
		       ;PROCESS-NAME is first instance variable
		       (CC-Q-PRINT-TOPLEV (QF-MEM-READ (1+ CP))))))
	    (FORMAT T "~&Complete backtrace follows: (type Space to stop)~%")
	    (CC-PRINT-PDL-1 NIL T)
	    (TERPRI)
	    (COND ((= (QF-TYPED-POINTER CURSG)
		      (QF-TYPED-POINTER (CC-SYMBOLIC-EXAMINE-REGISTER 'A-QTRSTKG)))
		   (FORMAT T "Backtrace of erring stack group: (type Space to stop)~2%")
		   (CC-TRACE-THE-STACK (CC-SYMBOLIC-EXAMINE-REGISTER
							'A-SG-PREVIOUS-STACK-GROUP)
				       T 777777)
		   (TERPRI)))))
      (IF ERROR-P (FORMAT T "~&[Sorry, error while trying to print that.]~%")))))

(DEFUN CC-DESCRIBE-ERROR-PC (FORMAT ERRPC &OPTIONAL EMULATE-EH &AUX TEM)
  (FORMAT T FORMAT)
  (CC-PRINT-ADDRESS ERRPC)
  ;; Try looking up in EH error table
  (LET ((ETE (CC-MICROCODE-ERROR-LOOKUP (- ERRPC RACMO)
	       (CC-MICROCODE-ERROR-TABLE
		 (QF-POINTER (CC-SYMBOLIC-EXAMINE-REGISTER 'A-VERSION))))))
    (COND (ETE
	   (FORMAT T "~%  Error table says: ~A" ETE)
	   (AND EMULATE-EH (SETQ TEM (GET (CAR ETE) 'ETE-HANDLER))
		(FUNCALL TEM ETE))))))

(DEFUN (EH:TRANS-TRAP ETE-HANDLER) (IGNORE)
  (LET ((VMA (QF-POINTER (CC-REGISTER-EXAMINE RAVMA)))
	(MD-POINTER (QF-POINTER (CC-REGISTER-EXAMINE RAMD)))
	(MD-TYPE (QF-DATA-TYPE (CC-REGISTER-EXAMINE RAMD))))
    (COND ((= MD-TYPE DTP-NULL)
	   (FORMAT T "~&  ~A "
		   (SELECTQ (- VMA MD-POINTER)
		     (1 "Unbound variable")
		     (2 "Undefined function")
		     (OTHERWISE
		      "DTP-NULL of some sort, probably unbound closure//instance variable")))
	   (CC-Q-PRINT-TOPLEV (QF-MAKE-Q MD-POINTER DTP-SYMBOL))))))

(DEFUN (/? CC-COLON-CMD) (IGNORE)
  (FUNCALL STANDARD-OUTPUT ':FRESH-LINE)
  (FORMAT:PRINT-LIST STANDARD-OUTPUT
		     ":~20A"
		     (SORT (LOOP FOR SYM BEING THE INTERNED-SYMBOLS IN "CC"
				 WHEN (GET SYM 'CC-COLON-CMD) COLLECT SYM)
			   #'STRING-LESSP)
		     "  "
		     "")
  (FUNCALL STANDARD-OUTPUT ':FRESH-LINE))

;Print name of machine being debugged, return NIL if no machine
(DEFUN CC-PRINT-DEBUGGEE-NAME ()
  (LET ((CHAOS-ADDRESS (DBG-READ 764142)) HOST)
    (COND ((= CHAOS-ADDRESS 177777)
	   (FORMAT T "No machine on other end of debug cable, apparently.~%")
	   NIL)
	  ((= CHAOS-ADDRESS 0)
	   (FORMAT T "No response on debuggee Unibus, can't get machine name.~%")
	   T)
	  ((SETQ HOST (SI:GET-HOST-FROM-ADDRESS CHAOS-ADDRESS ':CHAOS))
	   (FORMAT T "Machine being debugged is ~A.~%" HOST)
	   T)
	  (T (FORMAT T "Machine being debugged is at chaos address ~O, name unknown.~%"
		       CHAOS-ADDRESS)
	     T)))
  (CC-GET-PROPER-MICROCODE-SYMBOLS))

(DEFUN CC-GET-PROPER-MICROCODE-SYMBOLS ()
  (AND (BIT-TEST 1_28. (CC-REGISTER-EXAMINE RASTS))	;Prom disabled
       (LET ((VERS (QF-POINTER (CC-REGISTER-EXAMINE (+ RAAMO 40)))))	;A-VERSION
	 (COND ((AND (> VERS 0) (< VERS 10000.)
		     (OR (NULL CC-FILE-SYMBOLS-LOADED-FROM)
			 (MULTIPLE-VALUE-BIND (NIL VERSION)
			     (FUNCALL CC-FILE-SYMBOLS-LOADED-FROM ':TYPE-AND-VERSION)
			   ( VERSION VERS))))
		(FORMAT T "~&[Loading CC symbols for Microcode ~D]~%" VERS)
		(CC-LOAD-UCODE-SYMBOLS-FOR-VERSION VERS)))))
  ;; Now that we know for sure where A-V-NIL is, look at it again.
  (QF-SETUP-Q-FIELDS))

;Assumes map is set up, since location was just referenced
(DEFUN CC-VMA-TO-PMA (VMA)
  (LET ((L1MAPADR (LDB 1513 VMA))
	(L2MAPADR (LDB 1005 VMA))
	(WITHIN-PAGE (LDB 0010 VMA))
	MAP)
    (SETQ L2MAPADR (+ (LSH (CC-REGISTER-EXAMINE (+ RAM1O L1MAPADR)) 5) L2MAPADR))
    (SETQ MAP (CC-REGISTER-EXAMINE (+ RAM2O L2MAPADR)))
    (OR (BIT-TEST 1_23. MAP)
	(FORMAT T "~&[Note: page map failure translating VMA to PMA]"))
    (DPB (LDB 0016 MAP) 1016 WITHIN-PAGE)))

(DEFVAR CC-MICROCODE-ERROR-TABLES NIL)

;Find the EH error table for the microcode version in the debugee
(DEFUN CC-MICROCODE-ERROR-TABLE (VERSION)
  (COND ((= VERSION %MICROCODE-VERSION-NUMBER) EH:MICROCODE-ERROR-TABLE)
	((CDR (ASSQ VERSION CC-MICROCODE-ERROR-TABLES)))
	(T (LET ((PACKAGE (PKG-FIND-PACKAGE "EH")) FOO)
	     (WITH-OPEN-FILE (S (FUNCALL (FS:PARSE-PATHNAME "SYS: UBIN; UCADR")
					 ':NEW-TYPE-AND-VERSION "TBL" VERSION))
	       (READ S)
	       (SETQ FOO (READ S)))
	     (AND (EQ (CAR FOO) 'SETQ)
		  (EQ (CADR FOO) 'EH:MICROCODE-ERROR-TABLE)
		  (EQ (CAR (CADDR FOO)) 'QUOTE)
		  (PROG1 (SETQ FOO (CADR (CADDR FOO)))
			 (PUSH (CONS VERSION FOO) CC-MICROCODE-ERROR-TABLES)))))))

(DEFUN CC-MICROCODE-ERROR-LOOKUP (PC TABLE)
  (LOOP FOR ENT IN TABLE
	WHEN (AND (EQ PC (CAR ENT))
		  (NOT (MEMQ (CADR ENT) '(EH:RESTART EH:CALLS-SUB EH:ARG-POPPED
					  EH:DEFAULT-ARG-LOCATIONS EH:STACK-WORDS-PUSHED))))
	  RETURN (CDR ENT)))

(DEFUN CC-INSTRUCTION-M-SOURCE-REG-ADR (INS)
  (LET ((MSRC (LDB CONS-IR-M-SRC INS)))
    (IF (BIT-TEST CONS-FUNC-SRC-INDICATOR MSRC)
	(SELECT MSRC
	  (CONS-M-SRC-MD RAMD)
	  (CONS-M-SRC-VMA RAVMA)
	  (CONS-M-SRC-Q RAQ)
	  (CONS-M-SRC-C-PDL-BUFFER-INDEX
	   (+ RAPBO (CC-REGISTER-EXAMINE RAPI)))
	  (CONS-M-SRC-C-PDL-BUFFER-POINTER
	   (+ RAPBO (CC-REGISTER-EXAMINE RAPP)))
	  (CONS-M-SRC-C-PDL-BUFFER-POINTER-POP
	   (+ RAPBO (CC-REGISTER-EXAMINE RAPP) 1))
	  (OTHERWISE (+ RAFSO MSRC (- CONS-FUNC-SRC-INDICATOR))))
	(+ RAMMO MSRC))))

(DEFUN CC-PRINT-ADDRESS-AND-CONTENTS (RA &OPTIONAL DESC-TABLE)
  (CC-PRINT-ADDRESS RA)
  (PRINC "// ")
  (IF (NULL DESC-TABLE)
      (PROGN
	(CC-PRINT-REG-ADR-CONTENTS RA)
	(WHEN (MEMQ (CC-FIND-REG-ADR-RANGE RA) '(P A M FS PHYSICAL VIRTUAL))
	  (PRINT "  ")
	  (IGNORE-ERRORS (CC-WHICH-AREA (CC-REGISTER-EXAMINE RA)))))
    (LET ((WD (CC-REGISTER-EXAMINE RA)))
      (PRIN1 WD)
      (PRINC "   ")
      (CC-TYPE-OUT WD DESC-TABLE T NIL)))
  (TERPRI)
  (WHEN (= RA RAMD)
    (PRINC "Note: ")
    (CC-PRINT-ADDRESS-AND-CONTENTS RAVMA)))
