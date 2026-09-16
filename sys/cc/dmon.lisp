;;; -*- MODE: LISP; PACKAGE: CADR;Base:8.-*-
;;; Diagnostic "monitor"  (will be anyway. pretty simpleminded for now).

(DEFVAR CC-MAIN-MEMORY-SIZE NIL)
(ADD-INITIALIZATION "clear target machine core size"
		    '(SETQ CC-MAIN-MEMORY-SIZE NIL)
		    '(:BEFORE-COLD))

(DEFUN CC-RUN-MTEST-AUTO (&OPTIONAL ALREADY-LOADED RANGE (MAP-OFFSET 0))
  (CC-RUN-MTEST ALREADY-LOADED RANGE MAP-OFFSET T))

;if AUTO-P is non-nil, errors will be proceeded from.  ADRIOR, ADRAND, DATAIOR, DATAAND
; will be updated if prgm can figure out how to do it.

;;; Hacks to permit CC-RUN-MTEST only to load the microcode once.

(DEFVAR MTEST-UCODE (MAKE-ARRAY 1000. ':LEADER-LIST '(0)))
(DEFVAR UCODE-COUNTER 0)
(DEFVAR UCODE-TRUENAME)

(DEFUN MTEST-UCODE-STREAM (OP &OPTIONAL ARG1 &REST REST)
  (SELECTQ OP
    (:RESET
     (WITH-OPEN-FILE (STREAM "sys:ubin;memd uload >" ':direction ':input)
       (setq ucode-truename (funcall stream ':truename))
       (setq ucode-counter 0)
       (store-array-leader 0 mtest-ucode 0)
       (do
	 ((value (funcall stream ':tyi) (funcall stream ':tyi)))
	 ((not value))
	 (array-push-extend mtest-ucode value))))
    (:tyi
     (if (< ucode-counter (array-active-length mtest-ucode))
       (aref mtest-ucode (1- (setq ucode-counter (1+ ucode-counter))))
      nil))
    (:truename ucode-truename)
    (:close
     t)
    (:WHICH-OPERATIONS '(:reset :tyi :close :truename))
    (OTHERWISE
     (STREAM-DEFAULT-HANDLER (FUNCTION mtest-ucode-stream)
			     OP ARG1 REST))))

(putprop 'mtest-ucode-stream t 'si:io-stream-p)

(defvar ucode-dummy (funcall 'mtest-ucode-stream ':reset))

(DEFUN CC-RUN-MTEST (&OPTIONAL ALREADY-LOADED RANGE (MAP-OFFSET 0) AUTO-P (RESET-P T)
		     &AUX PC SYMBOLIC-PC CHAR 
		     ERRORS OTHER-ERRORS ADRAND ADRIOR DATAAND DATAIOR)
  (CC-DISCOVER-MAIN-MEMORY-SIZE)
  (dotimes (i (TRUNCATE cc-main-memory-size 200000))
    (format t "~% Memory board ~D" i)
    (cc-fast-address-test-mem i))
  (COND ((NULL ALREADY-LOADED)
	 (CC-ZERO-ENTIRE-MACHINE RESET-P)
	 ;; Read in MEMD ULOAD if have not already done so.
	 (IF (ZEROP (LENGTH MTEST-UCODE))
	     (MTEST-UCODE-STREAM :RESET))
	 (SETQ UCODE-COUNTER 0)
	 (CC-UCODE-LOADER NIL "SYS: UBIN; MEMD ULOAD >" NIL 'mtest-ucode-stream)))
  (COND ((ZEROP MAP-OFFSET) (CC-FAST-LOAD-STRAIGHT-MAP))
	(T (CC-LOAD-STRAIGHT-MAP MAP-OFFSET)))
  (COND ((NULL RANGE)
	 (CC-SYMBOLIC-DEPOSIT-REGISTER 'A-MAIN-MEMORY-START 0)
	 (CC-SYMBOLIC-DEPOSIT-REGISTER 'A-MAIN-MEMORY-SIZE CC-MAIN-MEMORY-SIZE))
	(T (CC-SYMBOLIC-DEPOSIT-REGISTER 'A-MAIN-MEMORY-START (CAR RANGE))
	   (CC-SYMBOLIC-DEPOSIT-REGISTER 'A-MAIN-MEMORY-SIZE (CADR RANGE))))
  (LET ((CC-MODE-REG (+ 44 (LOGAND CC-MODE-REG 3))))  ;SAME SPEED, DISABLE PROM, ENABLE
    (IF RESET-P (CC-RESET-MACH))				   ; ERROR STOPS.
    (DO TEST 0 (1+ TEST) (= TEST 10)
	(SETQ ERRORS 0 OTHER-ERRORS 0
	      ADRAND 77777777 ADRIOR 0 DATAAND 37777777777 DATAIOR 0)
	(SETQ CC-UPDATE-DISPLAY-FLAG T)
	(CC-SYMBOLIC-DEPOSIT-REGISTER 'M-TEST TEST)
	(CC-REGISTER-DEPOSIT RASA (CC-SYMBOLIC-CMEM-ADR  'MEMORY-DATA-TEST))
			 CONT (CC-REGISTER-DEPOSIT RAGO 0)
			 L  (COND ((SETQ CHAR (KBD-TYI-NO-HANG))
				   (GO X1))
				  ((ZEROP (CC-REGISTER-EXAMINE RAGO)) (GO X)))
			 (PROCESS-SLEEP 30. "MTest Wait")         ;WHY WAIT AS LONG?
			 (GO L)      
			 X1 (COND ((= CHAR #/ )
				   (FORMAT T "~%Aborting test ~D" TEST)
				   (CC-REGISTER-DEPOSIT RASTOP 0)
				   (GO E)))
			 X  (CC-REGISTER-DEPOSIT RASTOP 0)
			 (COND ((NOT (OR (= (SETQ PC (CC-REGISTER-EXAMINE RAPC))
					    (CC-SYMBOLIC-CMEM-ADR 'MEMORY-TEST-OK))
					 (> ERRORS 100.)))   ;give up after 100. errors.
				(SETQ SYMBOLIC-PC (CC-FIND-CLOSEST-SYM (+ RACMO PC)))
				(IF (NULL AUTO-P)
				    (FORMAT T "~%Test ~D halted at ~S (= ~O)
 " TEST SYMBOLIC-PC PC)
				    (SETQ ERRORS (1+ ERRORS))
				    (LET* ((CORRECT-DATA
					     (CC-SYMBOLIC-EXAMINE-REGISTER
					       'A-CURRENT-MEMORY-DATA))
					   (WRONG-BITS (LOGXOR CC-SAVED-MD CORRECT-DATA)))
				      (IF (NOT (MEMBER SYMBOLIC-PC '( ERROR-WRONG-DATA
								     (ERROR-WRONG-DATA 2)
								     (MEMORY-CHECK 2))))
					  (PROGN (SETQ OTHER-ERRORS (1+ OTHER-ERRORS))
					   (FORMAT T "~%unexpected stop!!")
					   (CC))
					  (SETQ ADRAND (LOGAND ADRAND CC-SAVED-VMA)
						ADRIOR (LOGIOR ADRIOR CC-SAVED-VMA)
						DATAAND (LOGAND WRONG-BITS DATAAND)
						DATAIOR (LOGIOR WRONG-BITS DATAIOR))))
				    (GO CONT)))
			       ((NOT (ZEROP ERRORS))
				(FORMAT T "~%Test ~D, ~D errors, ADRAND ~S,
 ADRIOR ~S, DATAAND ~S, DATAIOR ~S, other errors ~D"
					TEST ERRORS ADRAND ADRIOR DATAAND DATAIOR
					OTHER-ERRORS)
				(FORMAT T "~%DATAIOR bits ")
				(CC-PRINT-BITS DATAIOR))
			       (T (FORMAT T "~%Test ~D OK" TEST)))
			 E  )))

(DEFUN CC-MTEST-DING-LOOP NIL
  (DO () (())
    (CC-REGISTER-DEPOSIT RASA 0)
    (CC-REGISTER-DEPOSIT RAGO 0)
    (DO ((PC))
	(())
      (COND ((ZEROP (CC-REGISTER-EXAMINE RAGO))
	     (CC-REGISTER-DEPOSIT RASTOP 0)
	     (COND ((= (SETQ PC (CC-REGISTER-EXAMINE RAPC))
		       (CC-SYMBOLIC-CMEM-ADR 'MEMORY-TEST-OK))
		    (RETURN NIL))
		   (T
		    (FORMAT T "~%VMA:~S, MD:~S, AMD:~S"
			    CC-SAVED-VMA
			    CC-SAVED-MD
			    (CC-SYMBOLIC-EXAMINE-REGISTER 'A-CURRENT-MEMORY-DATA))
		    ;(CC-DIAGNOSE-FLOATING-ONE-RIGHT)
		    (TV:BEEP)
		    (CC-REGISTER-DEPOSIT RAGO 0))))))))

;USE THIS WITH MEMORY TEST PART 5 TO FIND STORES INTO WRONG ADDRESSES.
(DEFUN CC-DIAGNOSE-FLOATING-ONE-RIGHT (&OPTIONAL (ADR 0))
  (PROG (EXPECTED-DATA ACTUAL-DATA NEXT-ADR NEXT-DATA NEXT-EXPECTED-DATA)
    L	(SETQ EXPECTED-DATA (DBG-READ-XBUS ADR))
    L2  (SETQ ADR (1+ ADR))
    L1  (COND ((NOT (< ADR 200000)) (RETURN T)))
	(COND ((ZEROP (SETQ EXPECTED-DATA (ASH EXPECTED-DATA -1)))
	       (SETQ EXPECTED-DATA 1_31.)))
	(COND ((NOT (= (SETQ ACTUAL-DATA (DBG-READ-XBUS ADR))
		       EXPECTED-DATA))
	       (FORMAT T "~%ADR:~S, EXPECTED: ~S, ACTUAL: ~S"
		       ADR
		       EXPECTED-DATA
		       ACTUAL-DATA)
	       (SETQ NEXT-ADR (1+ ADR)
		     NEXT-DATA (DBG-READ-XBUS NEXT-ADR))
	       (COND ((ZEROP (SETQ NEXT-EXPECTED-DATA (ASH EXPECTED-DATA -1)))
		      (SETQ NEXT-EXPECTED-DATA 1_31.)))
	       (COND ((= NEXT-DATA NEXT-EXPECTED-DATA)
		      (FORMAT T " RANDOM STORE IN SEQUENCE")
		      (GO L2))
		     (T (GO L))))
	      (T (GO L2)))))

(DEFUN CC-SYMBOLIC-CMEM-ADR (SYM)
   (LET ((VAL (CC-LOOKUP-NAME SYM)))
      (COND ((OR (< VAL RACMO)
		 (NOT (< VAL RACME)))
	     (FERROR NIL "The symbol ~s is not a C-MEM symbol" SYM)))
      (- VAL RACMO)))

;DISCOVER THE AMOUNT OF MAIN MEMORY, SETQ THE VARIABLE CC-MAIN-MEMORY-SIZE
(defun CC-DISCOVER-MAIN-MEMORY-SIZE ()
  (SETQ CC-MAIN-MEMORY-SIZE (CC-RETURN-MAIN-MEMORY-SIZE))
  (FORMAT T "~%Main memory ~DK" (TRUNCATE CC-MAIN-MEMORY-SIZE 2000))
)

(defun CC-RETURN-MAIN-MEMORY-SIZE ()
  (do ((ADR 0 (+ ADR 40000))		;memory comes in 16k chunks
       (ZEROS 0)
       (ONES 37777777777)
       (EXIT-FLAG) (WRONG-BITS 0) (TEM))
      (())
    (PHYS-MEM-WRITE ADR ZEROS)
    (IF ( ZEROS (SETQ TEM (PHYS-MEM-READ ADR)))
	(SETQ EXIT-FLAG T WRONG-BITS TEM))
    (PHYS-MEM-WRITE ADR ONES)
    (IF ( ONES (SETQ TEM (PHYS-MEM-READ ADR)))
	(SETQ EXIT-FLAG T WRONG-BITS (LOGIOR WRONG-BITS (LOGXOR ONES TEM))))
    (IF EXIT-FLAG
	(PROGN (IF ( WRONG-BITS ONES)
		   (PROGN (FORMAT T "~%bits that crapped out at memory limit:")
			  (CC-PRINT-BITS WRONG-BITS)))
	       (RETURN ADR)))
    ))

;;; Read and write the sync program
(DEFUN CC-TV-READ-SYNC (ADR &OPTIONAL (TV-ADR 17377760))
	(PHYS-MEM-WRITE (+ TV-ADR 2) ADR)	;Set pointer
	(LOGAND 377 (PHYS-MEM-READ (+ TV-ADR 1))))

(DEFUN CC-TV-READ-SYNC-ENB-RAM (ADR &OPTIONAL (TV-ADR 17377760))
	(PHYS-MEM-WRITE (+ TV-ADR 3) 200)	;Enable SYNC RAM
	(PHYS-MEM-WRITE (+ TV-ADR 2) ADR)	;Set pointer
	(LOGAND 377 (PHYS-MEM-READ (+ TV-ADR 1))))

;;; This clobbers vertical spacing in order to guarantee access to RAM not PROM.
(DEFUN CC-TV-WRITE-SYNC (ADR DATA &OPTIONAL (TV-ADR 17377760))
	(PHYS-MEM-WRITE (+ TV-ADR 3) 200)	;Enable SYNC RAM
	(PHYS-MEM-WRITE (+ TV-ADR 2) ADR)	;Set pointer
	(PHYS-MEM-WRITE (+ TV-ADR 1) DATA))

;;; Start and stop the sync program
(DEFUN CC-TV-START-SYNC (CLOCK BOW VSP &OPTIONAL (TV-ADR 17377760))
	(PHYS-MEM-WRITE TV-ADR (+ (LSH BOW 2) CLOCK))
	(PHYS-MEM-WRITE (+ TV-ADR 3) (+ 200 VSP)))

(DEFUN CC-TV-STOP-SYNC (&OPTIONAL (TV-ADR 17377760))
	(PHYS-MEM-WRITE (+ TV-ADR 3) 200))		;Disable output of sync

;;; Write into the sync program from a list with repeat-counts
;;; Sub-lists are repeated <car> times.
(DEFUN CC-TV-FILL-SYNC (L &OPTIONAL (ADR 0) (TV-ADR 17377760) &AUX X)
  (DO ((L L (CDR L))) ((NULL L) ADR)
    (SETQ X (CAR L))
    (COND ((ATOM X) (CC-TV-WRITE-SYNC ADR X TV-ADR) (SETQ ADR (1+ ADR)))
	  (T (DO N (CAR X) (1- N) (ZEROP N)
	       (SETQ ADR (CC-TV-FILL-SYNC (CDR X) ADR TV-ADR)))))))

(DEFUN CC-TV-CHECK-SYNC (L &OPTIONAL (ADR 0) (TV-ADR 17377760) &AUX X)
  (DO ((L L (CDR L))) ((NULL L) ADR)
    (SETQ X (CAR L))
    (COND ((ATOM X)
	   (CC-TV-CHECK-SYNC-WD ADR X TV-ADR)
	   (SETQ ADR (1+ ADR)))
	  (T (DO N (CAR X) (1- N) (ZEROP N)
	       (SETQ ADR (CC-TV-CHECK-SYNC (CDR X) ADR TV-ADR)))))))

(DEFUN CC-TV-CHECK-SYNC-WD (ADR DATA TV-ADR &AUX MACH)
  (COND ((NOT (= DATA (SETQ MACH (CC-TV-READ-SYNC ADR TV-ADR))))
	 (FORMAT T "~%ADR:~S MACH: ~S should be ~S" ADR MACH DATA))))

(DECLARE (SPECIAL SI:CPT-SYNC SI:CPT-SYNC1 SI:CPT-SYNC2 SI:COLOR-SYNC))

;;; Set up sync for CPT monitor 768. x 896.
(DEFUN CC-TV-SETUP-CPT (&OPTIONAL (SYNC-PROG SI:CPT-SYNC2) (TV-ADR 17377760))
  (CC-TV-STOP-SYNC TV-ADR)
  (CC-TV-FILL-SYNC SYNC-PROG 0 TV-ADR)
  (CC-TV-START-SYNC 0 1 0 TV-ADR))

(DEFUN CC-SET-TV-SPEED (FREQUENCY)
  ;;"Set the TV refresh rate.  The default is 64.69.  Returns the number of display lines."
  ;; Try not to burn up the monitor
  (CHECK-ARG FREQUENCY (AND (> FREQUENCY 54.) (< FREQUENCY 76.))
	     "a number between 55. and 75.")
  ;; Here each horizontal line is 32. sync clocks, or 16.0 microseconds with a 64 MHz clock.
  ;; The number of lines per frame is 70. overhead lines plus enough display lines
  ;; to give the desired rate.
  (LET ((TV-ADR 17377760)
	(N-LINES (- (FIX (// 1e6 (* 16. FREQUENCY))) 70.)))
    (CC-TV-SETUP-CPT
      (APPEND '(1.  (1 33) (5 13) 12 12 (11. 12 12) 212 113)	;VERT SYNC, CLEAR TVMA
	      '(53. (1 33) (5 13) 12 12 (11. 12 12) 212 13)	;VERT RETRACE
	      '(8.  (1 31)  (5 11) 11 10 (11. 0 0) 200 21)	;8 LINES OF MARGIN
	      (DO ((L NIL (APPEND L `(,DN (1 31) (5 11) 11 50 (11. 0 40) 200 21)))
		   (N N-LINES (- N DN))
		   (DN))
		  ((ZEROP N) L)
		(SETQ DN (MIN 255. N)))
	      '(7. (1 31) (5 11) 11 10 (11. 0 0) 200 21)
	      '(1. (1 31) (5 11) 11 10 (11. 0 0) 300 23))
      TV-ADR)
    T))

(defun cc-tv-setup-loop ()
  (do () (()) (cc-tv-setup-cpt)))

(DEFUN CC-TV-CPT-CHECK-SYNC (&OPTIONAL (SYNC-PROG SI:CPT-SYNC2) (TV-ADR 17377760))
  (CC-TV-STOP-SYNC TV-ADR)
  (CC-TV-CHECK-SYNC SYNC-PROG 0 TV-ADR)
  (CC-TV-START-SYNC 0 1 0 TV-ADR))

(SETQ TV-SYNC-ZEROS '( (4096. 0)) )
(SETQ TV-SYNC-ONES  '( (4096. 377)) )

;FAST ADDRESS TEST WRITES ZEROS AND ONES INTO 2 LOCATIONS 
;WHOSE ADDRESSES DIFFER IN 1 BIT, CHECKS FOR INTERFERENCE.
;THIS DETECTS ADDRESS BITS STUCK AT ZERO OR ONE FOR SOME DATA
;BITS, BUT DOES NOT DETECT ADJACENT ADDRESS BITS SHORTED TOGETHER.
(DEFUN CC-FAST-ADDRESS-TEST-SYNC ()
  (CC-TV-STOP-SYNC)
  (DO ((N 2 (1- N))
       (PHASE T NIL)
       (ONES (SUB1 #Q (DPB 1 (+ (LSH 8 6) 1) 0)  #M(EXPT 2 8)))
       (ZEROS 0))
      ((= N 0))
    (DO ((BITNO 0 (1+ BITNO))
	 (GOOD1 (COND (PHASE ZEROS) (T ONES)))
	 (GOOD2 (COND (PHASE ONES) (T ZEROS)))
	 (BAD1)
	 (BAD2)
	 (BAD3)
	 (K)
         (CC-SUSPECT-BIT-LIST))
	((= BITNO 12.))
      (SETQ K (LSH 1 BITNO))
      (CC-TV-WRITE-SYNC K GOOD2)
      (COND ((NOT (EQUAL (SETQ BAD2 (CC-TV-READ-SYNC K)) GOOD2))
	     (PRINC " loc ") (PRIN1 K)
	     (CC-PRINT-BIT-LIST " fails in data bits "
				(CC-WRONG-BITS-LIST GOOD2 BAD2 8))))
      (CC-TV-WRITE-SYNC 0 GOOD1)		;Deposit in loc 0 second for A & M's sake
      (COND ((NOT (EQUAL (SETQ BAD1 (CC-TV-READ-SYNC 0)) GOOD1))
	     (PRINC " loc 0")
	     (CC-PRINT-BIT-LIST " fails in data bits "
				(CC-WRONG-BITS-LIST GOOD1 BAD1 8))))
      (COND ((NOT (EQUAL (SETQ BAD3 (CC-TV-READ-SYNC K)) GOOD2))
	     (FORMAT T " address bit ~D" BITNO)
	     (CC-PRINT-BIT-LIST (COND (PHASE " fails storing 1's then 0 in data bits ")
				      (T " fails storing 0 then 1's in data bits "))
				(CC-WRONG-BITS-LIST GOOD2 BAD3 8)))))))

(DEFUN CC-TV-SYNC-WRITE-LOOP (&OPTIONAL (ADR 0) (DATA -1))
  (DO () ((KBD-TYI-NO-HANG))
    (CC-TV-WRITE-SYNC ADR DATA)))

(DEFUN CC-TV-SYNC-READ-LOOP (&OPTIONAL (ADR 0))
  (DO () ((KBD-TYI-NO-HANG))
    (CC-TV-READ-SYNC ADR)))

(DEFUN CC-TV-SYNC-READ-LOOP-ENB-RAM (&OPTIONAL (ADR 0))
  (DO () ((KBD-TYI-NO-HANG))
    (CC-TV-READ-SYNC-ENB-RAM ADR)))


(DEFUN CC-TEST-TV-MEMORY (&OPTIONAL ALREADY-LOADED)
  (CC-TV-SETUP-CPT)
  (CC-RUN-MTEST ALREADY-LOADED '(0 100000) (ASH 17000000 -8)))

(defun cc-test-color-tv-memory (&optional already-loaded)
  (cc-tv-setup-cpt color:sync 17377750)
  (cc-run-mtest already-loaded '(0 100000) (ash 17200000 -8)))

(defun cc-tv-read (adr &optional (base-adr 17000000))
  (phys-mem-read (+ adr base-adr)))

(defun cc-tv-write (adr data &optional (base-adr 17000000))
  (phys-mem-write (+ adr base-adr) data))

(defun cc-fill-tv-memory (data)
  (cc-fast-mem-fill 0 100000 data 'load-map-slowly (ash 17000000 -8)))

(defun cc-tv-write-loop (&optional (adr 0) (data -1))
  (do () (())
    (cc-tv-write adr data)))

(defun cc-tv-read-loop (&optional (adr 0))
  (do () (())
    (cc-tv-read adr)))

(DEFUN CC-FAST-ADDRESS-TEST-MEM (&OPTIONAL (MEM-NUMBER 0))
 (DOTIMES (BANK 4)
  (FORMAT T "~%  Bank ~s" BANK)
  (CC-FAST-ADDRESS-TEST-MAIN-MEM (+ (* MEM-NUMBER 200000)
				    (* BANK 40000))
				 32.
				 14.)))

;FAST-ADDRESS-TEST FOR THE TV ONLY DOES TWO 16K BANKS.  ONE BANK IS ODD ADDRESSES, THE
;OTHER EVEN.  A COUPLE OF THE VARIABLES HAVE DIFFERENT NAMES AND SOME HAVE BEEN 
;REPLACED BY CONSTANTS BUT OTHERWISE THIS IS COPIED FROM THE FAST ADDRESS TEST BELOW.
(DEFUN CC-FAST-ADDRESS-TEST-TV-MEM ()
 (DOTIMES (BANK 2)
  (FORMAT T "~%~[Even ~;Odd ~]bank " BANK)
    (DO ((N 4 (1- N))
         (PHASE 0 (1+ PHASE))
         (ONES 37777777777)
         (ADR-MASK 37776)
         (ZEROS 0)
         (BASE-ADDRESS (+ 17000000 BANK)))
        ((= N 0)) 					
     (DO ((BITNO 0 (1+ BITNO))
	 (GOOD1 (COND ((EVENP PHASE) ZEROS) (T ONES)))
	 (GOOD2 (COND ((EVENP PHASE) ONES) (T ZEROS)))
	 (BAD1)
	 (BAD2)
	 (BAD3)
	 (LOCATION-ONE)
	 (LOCATION-TWO)
         (CC-SUSPECT-BIT-LIST))
	((= BITNO 13.))
      (SETQ LOCATION-ONE (+ BASE-ADDRESS (COND ((< PHASE 2)
			                        (LSH 2 BITNO))
                  			       (T (LOGXOR ADR-MASK (LSH 2 BITNO))))))
      (SETQ LOCATION-TWO (COND ((< PHASE 2) BASE-ADDRESS)
			    (T (+ BASE-ADDRESS ADR-MASK))))
      (PHYS-MEM-WRITE LOCATION-ONE GOOD2)
      (COND ((NOT (EQUAL (SETQ BAD2 (PHYS-MEM-READ LOCATION-ONE)) GOOD2))
	     (PRINC " loc ") (PRIN1 LOCATION-ONE)
	     (CC-PRINT-BIT-LIST " fails in data bits "
				(CC-WRONG-BITS-LIST GOOD2 BAD2 32.))))
      (PHYS-MEM-WRITE LOCATION-TWO GOOD1)
      (COND ((NOT (EQUAL (SETQ BAD1 (PHYS-MEM-READ LOCATION-TWO)) GOOD1))
	     (PRINC " loc ") (PRIN1 LOCATION-TWO)
	     (CC-PRINT-BIT-LIST " fails in data bits "
				(CC-WRONG-BITS-LIST GOOD1 BAD1 32.))))
      (COND ((NOT (EQUAL (SETQ BAD3 (PHYS-MEM-READ LOCATION-ONE)) GOOD2))
	     (FORMAT T " address bit ~D" (1+ BITNO))
	     (CC-PRINT-BIT-LIST (COND ((EVENP PHASE)
				       " fails storing 1's then 0 in data bits ")
				      (T " fails storing 0 then 1's in data bits "))
				(CC-WRONG-BITS-LIST GOOD2 BAD3 32.))))))))



;FAST ADDRESS TEST WRITES ZEROS AND ONES INTO 2 LOCATIONS 
;WHOSE ADDRESSES DIFFER IN 1 BIT, CHECKS FOR INTERFERENCE.
;THIS DETECTS ADDRESS BITS STUCK AT ZERO OR ONE FOR SOME DATA
;BITS, BUT DOES NOT DETECT ADJACENT ADDRESS BITS SHORTED TOGETHER.
(DEFUN CC-FAST-ADDRESS-TEST-MAIN-MEM (OFFSET N-DATA-BITS N-ADDRESS-BITS)
  (DO ((N 4 (1- N))
       (PHASE 0 (1+ PHASE))
       (ONES (SUB1 (EXPT 2 N-DATA-BITS)))
       (ADR-MASK (1- (EXPT 2 N-ADDRESS-BITS)))
       (ZEROS 0))
      ((= N 0))
    (DO ((BITNO 0 (1+ BITNO))
	 (GOOD1 (COND ((EVENP PHASE) ZEROS) (T ONES)))
	 (GOOD2 (COND ((EVENP PHASE) ONES) (T ZEROS)))
	 (BAD1)
	 (BAD2)
	 (BAD3)
	 (OTHER-LOC)
	 (K)
         (CC-SUSPECT-BIT-LIST))
	((= BITNO N-ADDRESS-BITS))
      (SETQ K (+ OFFSET (COND ((< PHASE 2)
			       (LSH 1 BITNO))
			      (T (LOGXOR ADR-MASK (LSH 1 BITNO))))))
      (SETQ OTHER-LOC (COND ((< PHASE 2) OFFSET)
			    (T (+ OFFSET ADR-MASK))))
      (PHYS-MEM-WRITE K GOOD2)
      (COND ((NOT (EQUAL (SETQ BAD2 (PHYS-MEM-READ K)) GOOD2))
	     (PRINC " loc ") (PRIN1 K)
	     (CC-PRINT-BIT-LIST " fails in data bits "
				(CC-WRONG-BITS-LIST GOOD2 BAD2 N-DATA-BITS))))
      (PHYS-MEM-WRITE OTHER-LOC GOOD1)
      (COND ((NOT (EQUAL (SETQ BAD1 (PHYS-MEM-READ OTHER-LOC)) GOOD1))
	     (PRINC " loc ") (PRIN1 OTHER-LOC)
	     (CC-PRINT-BIT-LIST " fails in data bits "
				(CC-WRONG-BITS-LIST GOOD1 BAD1 N-DATA-BITS))))
      (COND ((NOT (EQUAL (SETQ BAD3 (PHYS-MEM-READ K)) GOOD2))
	     (FORMAT T " address bit ~D" BITNO)
	     (CC-PRINT-BIT-LIST (COND ((EVENP PHASE)
				       " fails storing 1's then 0 in data bits ")
				      (T " fails storing 0 then 1's in data bits "))
				(CC-WRONG-BITS-LIST GOOD2 BAD3 N-DATA-BITS)))))))


;; Fillmain memory. Stop via statistics counter.
;; VMA gets loaded with starting address minus one.
;; MD has data.

;; CC-FAST-MEM-FILL should be adjusted in coordination with CC-FAST-LOAD-STRAIGHT-MAP
;; to do the right thing with memory size > 256K

(declare (special CC-MAIN-MEMORY-SIZE))

(defun CC-FAST-MEM-FILL (&OPTIONAL (FROM 0) (TO 1000000)	; FROM will be auto-adjusted
				   (FILL-DATA 0) 
				   LOAD-STRAIGHT-MAP-SLOWLY-P
				   (MAP-OFFSET 0))
  (cond ((or (not (boundp 'CC-MAIN-MEMORY-SIZE))
	     (null CC-MAIN-MEMORY-SIZE))
	 (setq CC-MAIN-MEMORY-SIZE (cc-return-main-memory-size))))
  (cond ((or (< FROM 0) (< TO FROM)) (ferror nil "Totally unreasonable bounds provided."))
	((and (not LOAD-STRAIGHT-MAP-SLOWLY-P)
	      (>= FROM CC-MAIN-MEMORY-SIZE))
	 (ferror nil "The machine has only ~DK (~O) words of memory. Fill not performed."
		 (TRUNCATE CC-MAIN-MEMORY-SIZE 2000) CC-MAIN-MEMORY-SIZE))
	((and (not LOAD-STRAIGHT-MAP-SLOWLY-P)
	      (>= TO CC-MAIN-MEMORY-SIZE))
	 (setq TO (sub1 CC-MAIN-MEMORY-SIZE))
	 (format T "~%The upper bound has been adjusted to ~O to reflect the main memory size of ~DK."
		 TO (TRUNCATE CC-MAIN-MEMORY-SIZE 2000))))
  (cond (LOAD-STRAIGHT-MAP-SLOWLY-P (cc-load-straight-map MAP-OFFSET))
	(t (cc-fast-load-straight-map)))	;Fast, so we always do it.
  (let ((SAVED-C-MEMORY (cc-multiple-read-c-mem 0 3)))
    (cc-stuff-memory-fill-loop)
    (cc-write-func-dest CONS-FUNC-DEST-VMA (sub1 FROM))
    (cc-write-stat-counter (- FROM TO 1))
    (cc-write-md FILL-DATA)
    (cc-run-test-loop 0)
    (let ((PC-STOP-ADDRESS (cc-read-pc)))
      (cc-multiple-write-c-mem 0 SAVED-C-MEMORY)
      (select PC-STOP-ADDRESS
	(2 (format t "~%Memory fill operation completed.") T)
	(4 (format t "~%Page fault encountered during memory fill operation.  VMA: ~O"
		   (cc-read-m-mem CONS-M-SRC-VMA)))
	(t (format t "~%Unanticipated error during memory fill operation. PC: ~O  VMA: ~O"
		   PC-STOP-ADDRESS (cc-read-m-mem CONS-M-SRC-MD)))))))

;;Microcode loop:

;FILL    ((VMA-START-WRITE) M+1 VMA STAT-BIT)
;        (JUMP-IF-NO-PAGE-FAULT FILL)
;ERROR-BAD-PAGE-FAULT-IN-FILL
;        (JUMP HALT-CONS ERROR-BAD-PAGE-FAULT)

;; MD has value to be stored.
;; VMA has starting address minus 1
;; Depends on loading of statistics counter to number of words
;;	      Saving of C-mem if so desired. [not currently done ?]
;; 	      Preloaded straight map

(defun CC-STUFF-MEMORY-FILL-LOOP ()
     (cc-execute (W-C-MEM 0)
	    cons-ir-stat-bit 1
	    cons-ir-m-src CONS-M-SRC-VMA
	    cons-ir-ob CONS-OB-ALU
	    cons-ir-aluf CONS-ALU-M+1
	    cons-ir-func-dest CONS-FUNC-DEST-VMA-START-WRITE)
     (cc-execute (W-C-MEM 1)
	    cons-ir-op CONS-OP-JUMP
	    cons-ir-jump-cond CONS-JUMP-COND-NO-PAGE-FAULT
	    cons-ir-jump-addr 0
	    cons-ir-n 1)
     (cc-execute (W-C-MEM 2)
	    cons-ir-mf CONS-MF-HALT))

;;; Have the debuggee machine load its own straight map.

;; Stat-counter causes stop, VMA has the data, MD the address.
;; A-A and A-B are used for data increment and address increment respectively
;; They are saved and restored

;; Note that the following are used and defined elsewhere (LCADRD ?)
;;  CONS-VMA-WRITE-LEVEL-1-MAP-BIT
;;  CONS-VMA-LEVEL-1-BYTE
;;  The level 2 map is written from bits 0-23 (0030) of the MD. (Too big for fixnum ops)

(defun CC-FAST-LOAD-STRAIGHT-MAP (&aux SAVED-A-A SAVED-A-B)	;This should take an offset
  (let ((A-A 5) (A-B 6) (PC-STOP-ADDRESS)
	(SAVED-C-MEM (cc-multiple-read-c-mem 0 3)))
    (setq SAVED-A-A (cc-read-a-mem A-A)		;Using A because A + Functional Source op.
	  SAVED-A-B (cc-read-a-mem A-B))
    (cc-stuff-load-straight-map-loop)		;For now just sets up for low 256K
;; FIRST WRITE THE LEVEL 1 MAP
    (cc-write-a-mem A-A (ASH 1 27.))		;map data increment
    (cc-write-a-mem A-B	(ASH 1 13.))		;map address increment
    (cc-write-func-dest CONS-FUNC-DEST-VMA 
			CONS-VMA-WRITE-LEVEL-1-MAP-BIT)
    (cc-write-stat-counter -40)
    (cc-write-md (dpb -1 CONS-VMA-LEVEL-1-BYTE 0))	; in correct field.
    (cc-run-test-loop 0)
    (setq PC-STOP-ADDRESS (cc-read-pc))
    (select PC-STOP-ADDRESS
      (1 (format t "~%Level 1 map loaded for the low 256K addresses.") T)
      (t (cc-multiple-write-c-mem 0 SAVED-C-MEM)
	 (cc-write-a-mem A-A SAVED-A-A) (cc-write-a-mem A-B SAVED-A-B)
	 (ferror nil "~%Level 1 load unsuccessful.   PC: ~O   MD: ~O   VMA: ~O"
		 PC-STOP-ADDRESS (cc-read-m-mem CONS-M-SRC-MD) (cc-read-m-mem CONS-M-SRC-VMA))))
 ;; NOW WRITE THE LEVEL 2 MAP
    (cc-write-a-mem A-A 1)			;map data increment
    (cc-write-a-mem A-B 400)			;map address increment
    (cc-write-func-dest CONS-FUNC-DEST-VMA
			(ash 13 22.))		;Appropriate access bits & loc 0 data.[meta ?]
    (cc-write-stat-counter -1024.)
    (cc-write-md (dpb -1 1020 0))		;Map Loc (0 minus 1)
    (cc-run-test-loop 0)
    (setq PC-STOP-ADDRESS (cc-read-pc))
    (cc-multiple-write-c-mem 0 SAVED-C-MEM)
    (select PC-STOP-ADDRESS
      (1 (format t "~%Level 2 map loaded.") T)
      (t (format t "~%Level 2 load unsuccessful.   PC: ~O   MD: ~O   VMA: ~O"
	      PC-STOP-ADDRESS (cc-read-m-mem CONS-M-SRC-MD) (cc-read-m-mem CONS-M-SRC-VMA))))
    (cc-write-a-mem A-A SAVED-A-A)
    (cc-write-a-mem A-B SAVED-A-B)
    T))

;; Microcode loop for loading maps. (address in MD, data in VMA, stop via STAT. COUNTER)
;; There may be timing problems here, the write might not get finished in time ?
;; The STAT-BIT must go at the end of the loop to insure that the final write gets done.

;LOOP	 ((MD-WRITE-MAP) ADD MD A-B)
;        (JUMP-XCT-NEXT LOOP)
;      ((VMA) ADD VMA A-A STAT-BIT)

(defun CC-STUFF-LOAD-STRAIGHT-MAP-LOOP ()	;For now just sets up for low 256K
     (cc-execute (W-C-MEM 0)
	    cons-ir-aluf CONS-ALU-ADD
	    cons-ir-m-src CONS-M-SRC-MD
	    cons-ir-a-src 6				;A-B has address increment
	    cons-ir-ob CONS-OB-ALU
	    cons-ir-func-dest CONS-FUNC-DEST-MD-WRITE-MAP)
     (cc-execute (W-C-MEM 1)
	    cons-ir-op CONS-OP-JUMP
	    cons-ir-jump-cond CONS-JUMP-COND-UNC
	    cons-ir-jump-addr 0			
	    CONS-IR-n 0)
     (cc-execute (W-C-MEM 2)
	    cons-ir-stat-bit 1
	    cons-ir-aluf CONS-ALU-ADD
	    cons-ir-m-src CONS-M-SRC-VMA
	    cons-ir-a-src 5			 	;A-A has data increment
	    cons-ir-ob CONS-OB-ALU
	    cons-ir-func-dest CONS-FUNC-DEST-VMA))
