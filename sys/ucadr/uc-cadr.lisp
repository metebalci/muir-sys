;-*-Mode:Midas-*-
;NOTE: THIS FILE FOLLOWS UC-PARAMETERS AND HAS FIRST I-MEM CODE.

(SETQ UC-CADR '(
;also note: A-LOWEST-DIRECT-VIRTUAL-ADDRESS  holds the lowest direct mapped
; virtual address, normally LOWEST-A-MEM-VIRTUAL-ADDRESS.  But it can be set lower
; ie if you are using the new color TV board you need 128K of direct mapped space
; below that to reference the video buffer.
;(ASSIGN LOWEST-A-MEM-VIRTUAL-ADDRESS 176776000)	;MUST BE 0 MODULO SIZE OF A-MEM
;(ASSIGN LOWEST-IO-SPACE-VIRTUAL-ADDRESS 177000000)  ;BEGINING OF X-BUS IO SPACE
;(ASSIGN LOWEST-UNIBUS-VIRTUAL-ADDRESS 177400000)    ;END OF X-BUS, BEGINNING OF UNIBUS
;; quux revision 13 (contract g2 2.6; appendix a1.7): virtual addresses are 28
;; bits.  the i/o virtual region is the top of the mapped space,
;; 1760000000-1777777777, virtual equal to physical, and a memory's window is
;; just below it, 1757776000-1757777777, in the order the page fault handler
;; tests them.  there is no unibus: its window is put past the frame buffer in
;; the i/o region, where nothing answers.
(assign lowest-a-mem-virtual-address 1757776000)	;must be 0 modulo size of a-mem
(assign lowest-io-space-virtual-address 1760000000)	;the i/o virtual region
(assign lowest-unibus-virtual-address 1770000000)	;no unibus on quux

;Compare with these after clearing the sign bit of the address
;(which is done since that bit is meaningless in the map on a CADR).
;(ASSIGN INTERNAL-LOWEST-A-MEM-VIRTUAL-ADDRESS 76776000)    ;MUST BE 0 MODULO SIZE OF A-MEM
;(ASSIGN INTERNAL-LOWEST-IO-SPACE-VIRTUAL-ADDRESS 77000000) ;BEGINING OF X-BUS IO SPACE
;(ASSIGN INTERNAL-LOWEST-UNIBUS-VIRTUAL-ADDRESS 77400000)   ;END OF X-BUS, BEGINNING OF UNIBUS
;; quux revision 13: no sign bit is cleared from a 28-bit address, so the
;; internal addresses are the addresses themselves.
(assign internal-lowest-a-mem-virtual-address 1757776000)
(assign internal-lowest-io-space-virtual-address 1760000000)
(assign internal-lowest-unibus-virtual-address 1770000000)

;; quux (contract q13, revision 11): the register page is the last page of
;; the physical space, 17777400-17777777, fixed, where it was 17377000-
;; 17377377 before; its word w is physical 17777400+w and virtual 77777400+w
;; (the i/o region's direct map, pgf-mm0).  every register-page address below
;; is made from these two, so that the page moves in one place; the old
;; addresses are nothing there on revision 11.
;(assign quux-register-page-virtual-address 77777400)
;(assign quux-register-page-physical-address 17777400)
;; quux revision 13 (contract g2 4.1): the register page is the last page of
;; the 28-bit physical space, 1777777400, and virtual equal to physical in the
;; i/o virtual region.
(assign quux-register-page-virtual-address 1777777400)
(assign quux-register-page-physical-address 1777777400)

;; quux (contract q4): the chaosnet interface is the register page's words
;; 140-147, word 140+k for unibus 764140+2k, the same registers in the same
;; order, so every access made relative to a-chaos-csr-address moves with it.
;(ASSIGN CHAOS-CSR-ADDRESS 77377140)		;register page word 140, not UNIBUS 764140
(assign chaos-csr-address (plus quux-register-page-virtual-address 140))	;word 140
;; quux (contract q13): block-disk's registers are the register page's words
;; 200-203 from revision 11, where they were 17377774-17377777 beside it.
;(ASSIGN DISK-REGS-ADDRESS-BASE 77377774)	;XBUS ADDRESS 17377774
(assign disk-regs-address-base (plus quux-register-page-virtual-address 200))	;word 200

(ASSIGN DISK-READ-COMMAND 0)
(ASSIGN DISK-WRITE-COMMAND 11)
;; quux: block-disk does read, 0, and write, 11, only; mit's read-compare, 10,
;; and recalibrate, 10001005, are gone.

;; quux: tv-regs-address-base and a-tv-regs-base are gone: the tv's vertical
;; interrupt was the only thing the microcode read there, and the video
;; controller (mono tv until contract q13) has none.
;; quux: on the video controller's first line, words 34-40, which every size has (the
;; narrowest, 1024 wide, is 32 words); it serves only until lisp sets
;; %disk-run-light from the screen's real size (tv::initialize-run-light-
;; locations, sys; ltop).  it was the bottom right of a 1920x1080 buffer,
;; which on a smaller one is past the end: every disk operation before lisp
;; ran was an xbus nxm (muir traced them at 17176423 on a 1280x1024 screen).
;(assign disk-run-light-virtual-address 77000036)	;XBUS ADDRESS
;; quux revision 13: the frame buffer window is at 1760000000 (g1 3.2).
(assign disk-run-light-virtual-address 1760000036)

;; quux: the microsecond clock is the processor's source 15 (revision 5), not
;; the i/o board's at unibus 764120.

;; quux (contract q3): the mouse is the register page's word 122, x in <11:0>,
;; y in <27:16> and the buttons in <14:12>; mit's were unibus 764104 (y and
;; buttons) and 764106 (x).
;(ASSIGN MOUSE-HARDWARE-VIRTUAL-ADDRESS 77377122)
(assign mouse-hardware-virtual-address (plus quux-register-page-virtual-address 122))
;; quux (contract q13): word 123, the mouse's status, <0> moved and <8> its
;; interrupt enable; intr-mouse-stray writes it 0.
(assign quux-mouse-status-virtual-address (plus quux-register-page-virtual-address 123))
;; quux (contract q3): the keyboard is the register page's words 120, its
;; status (<0> a key word waiting), and 121, whose read takes the oldest key
;; word, the 32-bit word unibus 764100 and 764102 gave together.
;(ASSIGN QUUX-KBD-DATA-VIRTUAL-ADDRESS 77377121)
;(ASSIGN QUUX-KBD-STATUS-PHYSICAL-ADDRESS 17377120)
;(ASSIGN QUUX-KBD-DATA-PHYSICAL-ADDRESS 17377121)
(assign quux-kbd-data-virtual-address (plus quux-register-page-virtual-address 121))
(assign quux-kbd-status-physical-address (plus quux-register-page-physical-address 120))
(assign quux-kbd-data-physical-address (plus quux-register-page-physical-address 121))

;; quux (contract q3): no beeper; %beep no longer writes unibus 764110.
(ASSIGN BEEP-HARDWARE-VIRTUAL-ADDRESS 77772044)	   ;Unibus 764110

;; quux's register page (contract q2), the feature page's page: word 100
;; says who interrupted, a
;; write to word 101, the error status, clears it, and bit 0 of word 102, the
;; mode, is error stop.  they replace unibus 766040, 766044 and 766012.
;; quux revision 11 (contract q13): word 100's bits are <0>-<2> timers 0-2,
;; <3> block-disk, <4> the keyboard, <5> the mouse, <6> the network and <7>
;; the file device; before, <0> was the tick, <1> timer 1, <2> block-disk,
;; <3> the keyboard, <5> the network and <7> timer 2 (intr, sys: ucadr;
;; uc-interrupt).
;(ASSIGN QUUX-INTERRUPT-STATUS-VIRTUAL-ADDRESS 77377100)
;(ASSIGN QUUX-ERROR-STATUS-PHYSICAL-ADDRESS 17377101)
;(ASSIGN QUUX-MODE-PHYSICAL-ADDRESS 17377102)
(assign quux-interrupt-status-virtual-address (plus quux-register-page-virtual-address 100))
(assign quux-error-status-physical-address (plus quux-register-page-physical-address 101))
(assign quux-mode-physical-address (plus quux-register-page-physical-address 102))
;; quux revision 10 (contract q11): word 100's <0> is timer 0, the tick, and
;; <1> and <7> (<2> from revision 11) are timers 1 and 2, each under its interrupt enable; q1's
;; interval timer is gone.  word 104 <0>, reset devices: a write of 1 resets
;; every device (the timers, the file device, block-disk and the network) in
;; place of the unibus reset, interrupt-control <28>, which drives nothing on
;; quux from revision 10.  timer k's control and status is word 110+2k (<0>
;; on, a write with <1> set clears its flag, <2> one-shot, taken at turn-on,
;; <8> its interrupt enable) and its period in microseconds word 111+2k.
;; word 161 is the file device's status, <1> quiet.  reset-machine reaches
;; them physically, intr and beg06 through the map.
;(ASSIGN QUUX-RESET-DEVICES-PHYSICAL-ADDRESS 17377104)
;(ASSIGN QUUX-TIMER-0-CONTROL-VIRTUAL-ADDRESS 77377110)
;(ASSIGN QUUX-TIMER-0-PERIOD-PHYSICAL-ADDRESS 17377111)
;(ASSIGN QUUX-TIMER-1-CONTROL-VIRTUAL-ADDRESS 77377112)
;(ASSIGN QUUX-TIMER-1-PERIOD-PHYSICAL-ADDRESS 17377113)
;(ASSIGN QUUX-TIMER-2-CONTROL-VIRTUAL-ADDRESS 77377114)
;(ASSIGN QUUX-TIMER-2-PERIOD-PHYSICAL-ADDRESS 17377115)
;(ASSIGN QUUX-FILE-DEVICE-STATUS-PHYSICAL-ADDRESS 17377161)
(assign quux-reset-devices-physical-address (plus quux-register-page-physical-address 104))
(assign quux-timer-0-control-virtual-address (plus quux-register-page-virtual-address 110))
(assign quux-timer-0-period-physical-address (plus quux-register-page-physical-address 111))
(assign quux-timer-1-control-virtual-address (plus quux-register-page-virtual-address 112))
(assign quux-timer-1-period-physical-address (plus quux-register-page-physical-address 113))
(assign quux-timer-2-control-virtual-address (plus quux-register-page-virtual-address 114))
(assign quux-timer-2-period-physical-address (plus quux-register-page-physical-address 115))
(assign quux-file-device-status-physical-address (plus quux-register-page-physical-address 161))
;; quux revision 12 (contract h8a): the feature page's word 17 is the number of
;; the macro dispatch memory's entries, 1,024, and reads 0 below revision 12;
;; reset-machine fills the memory only when it is there.
(assign quux-macro-dispatch-entries-physical-address
	(plus quux-register-page-physical-address 17))
;; quux (contract q13): word 160, the file device's control, <0> enable and
;; <8> interrupt enable; intr-file-device-stray clears <8>.
(assign quux-file-device-control-virtual-address (plus quux-register-page-virtual-address 160))
(ASSIGN INTERRUPT-STATUS-HARDWARE-VIRTUAL-ADDRESS 77773020)
		;Unibus address 766040 (interrupt status)
(ASSIGN CLEAR-INTERRUPT-HARDWARE-VIRTUAL-ADDRESS  77773021) ;Unibus address 766042
(ASSIGN INTERRUPT-CONTROL-HARDWARE-VIRTUAL-ADDRESS 77773020) ;Unibus address 766040

(ASSIGN UNIBUS-MAP-VIRTUAL-BASE-ADDRESS 77773060)	;Base of the unibus map

;(DISPATCH ADVANCE-INSTRUCTION-STREAM) TO GET NEXT HALFWORD
(ASSIGN ADVANCE-INSTRUCTION-STREAM
	(PLUS (PLUS (PLUS DISPATCH-ADVANCE-INSTRUCTION-STREAM 
;			  (BYTE-FIELD 1 31.)) ;NEEDFETCH BIT
			  ;; quux revision 13 (appendix a1.6): lc's flags moved up
			  ;; by 8, need-fetch to bit 39.
			  (byte-field 1 39.)) ;needfetch bit
		    LOCATION-COUNTER)
	      D-ADVANCE-INSTRUCTION-STREAM))


;;; INITIALIZATION

(LOCALITY I-MEM)

ZERO	(JUMP ZERO HALT-CONS)		;WILD TRANSFER TO ZERO

;This is location 1.  Enter here if virtual memory is valid.
BEG	((M-ZERO) SETZ)				;DON'T GET SCREWED BY CLOBBERED LOC 2@A
	(JUMP BEG0000)

;Enter here from the PROM.  Virtual memory is not valid yet.
(LOC 6)
PROM	(JUMP-NOT-EQUAL-XCT-NEXT Q-R A-ZERO PROM)    ;These 2 instructions duplicate the prom
       ((Q-R) ADD Q-R A-MINUS-ONE)
;;; Decide whether to restore virtual memory from saved band on disk, i.e.
;;; whether this is a cold boot or a warm boot.  If the keyboard has input
;;; available, and the character was RETURN (rather than RUBOUT), it's a warm boot.
	(CALL-XCT-NEXT PHYS-MEM-READ)
       ((VMA) (A-CONSTANT QUUX-KBD-STATUS-PHYSICAL-ADDRESS)) ;quux: word 120, not 764112
	(JUMP-IF-BIT-CLEAR (BYTE-FIELD 1 0) MD	;If keyboard is not ready,
		COLD-BOOT)			; assume we are supposed to cold-boot
	(CALL-XCT-NEXT PHYS-MEM-READ)
       ((VMA) (A-CONSTANT QUUX-KBD-DATA-PHYSICAL-ADDRESS)) ;quux: word 121, not 764100
	((MD) (BYTE-FIELD 6 0) MD)		;Get keycode
	(JUMP-EQUAL MD (A-CONSTANT 46) COLD-BOOT)	;This is cold-boot if key is RUBOUT
	;; quux: standardize the mode: error stop, bit 0 of the register page's
	;; word 102.  mit wrote 44, error stop and prom-disable, to unibus
	;; 766012; quux's prom is never disabled.
	((md) (a-constant 1))
	(CALL-XCT-NEXT PHYS-MEM-WRITE)
       ((VMA) (A-CONSTANT QUUX-MODE-PHYSICAL-ADDRESS))
	(JUMP BEG0000)


;PUSHJ HERE FOR FATAL ERRORS, E.G. THINGS THAT CAN'T HAPPEN.
;ALSO FOR THINGS WHICH DON'T HAVE ERROR-TABLE ENTRIES YET.
  (MICRO-CODE-ILLEGAL-ENTRY-HERE)	;FILL IN UNUSED ENTRIES IN 
					; MICRO-CODE-SYMBOL-AREA
ILLOP	(POPJ HALT-CONS)		;Halt with place called from in lights


;; (%WRITE-INTERNAL-PROCESSOR-MEMORIES CODE ADR D-HI D-LOW)
;;   CODE SELECTS WHICH MEMORY GETS WRITTEN. 1 -> I, 2 -> D, 4 -> A/M . 
;;    (THIS IS A SUBSET OF THE CODE USED IN MCR FILES).
XWIPM (MISC-INST-ENTRY %WRITE-INTERNAL-PROCESSOR-MEMORIES)
	((M-1) Q-POINTER C-PDL-BUFFER-POINTER-POP)
	((M-1) DPB C-PDL-BUFFER-POINTER (BYTE-FIELD 10 30) A-1)  ;M-1 GETS 32 BITS DATA
	((M-2) (BYTE-FIELD 20 10) C-PDL-BUFFER-POINTER-POP)      ;M-2 GETS REST BEYOND THAT
	((M-A) Q-POINTER C-PDL-BUFFER-POINTER-POP)		;ADDRESS
	((M-B) Q-POINTER C-PDL-BUFFER-POINTER-POP)		;CODE
	(JUMP-EQUAL M-B (A-CONSTANT 1) XWIPM-I)
	(JUMP-EQUAL M-B (A-CONSTANT 2) XWIPM-D)
	(CALL-NOT-EQUAL M-B (A-CONSTANT 4) TRAP)
   (ERROR-TABLE BAD-INTERNAL-MEMORY-SELECTOR-ARG M-B)
	;; quux revision 13: an a or m location is 40 bits.  d-hi's bits 15:8, which
	;; the callers (ma-load-a-mem, sys; mlap; the ucode loader, sys2; usymld)
	;; fill from the word's bits 39:32, are its tag, <39:32>; m-1 held only the
	;; 32 bits below, so every location written got tag 000.
	((m-1) dpb m-2 q-all-but-pointer a-1)
	(JUMP-LESS-THAN M-A (A-CONSTANT 40) XWIPM-M)
	((OA-REG-LOW) DPB M-A OAL-A-DEST A-ZERO)
	((A-GARBAGE) M-1)
	(JUMP XFALSE)

XWIPM-M ((OA-REG-LOW) DPB M-A OAL-M-DEST A-ZERO)
	((M-GARBAGE) M-1)
	(JUMP XFALSE)

XWIPM-D ((OA-REG-LOW) DPB M-A OAL-DISP A-ZERO)
	(DISPATCH A-1 WRITE-DISPATCH-RAM)
	(JUMP XFALSE)

XWIPM-I ((OA-REG-LOW) DPB M-A OAL-JUMP A-ZERO)
	(WRITE-I-MEM A-2 M-1)
	(JUMP XFALSE)

;; Give this an offset into the IO part of the XBUS, not an XBUS address.
XXBR (MISC-INST-ENTRY %XBUS-READ)
	(DISPATCH Q-DATA-TYPE C-PDL-BUFFER-POINTER TRAP-UNLESS-FIXNUM)
    (ERROR-TABLE ARGTYP FIXNUM PP 0)
    (ERROR-TABLE ARG-POPPED 0 PP)
	((VMA-START-READ) ADD C-PDL-BUFFER-POINTER-POP	;XBUS word addr
		(A-CONSTANT LOWEST-IO-SPACE-VIRTUAL-ADDRESS))
XUBR0	(CHECK-PAGE-READ)		;Mustn't check for sequence breaks since
	(JUMP-XCT-NEXT RETURN-M-1)	;on some devices reading has side effects and if
       ((M-1) READ-MEMORY-DATA)		;a sequence break occurred we would read it twice

XUBR (MISC-INST-ENTRY %UNIBUS-READ)
	(DISPATCH Q-DATA-TYPE C-PDL-BUFFER-POINTER TRAP-UNLESS-FIXNUM)
    (ERROR-TABLE ARGTYP FIXNUM PP 0)
    (ERROR-TABLE ARG-POPPED 0 PP)
	((VMA-START-READ) (BYTE-FIELD 17. 1) C-PDL-BUFFER-POINTER-POP	;UBUS word addr
		(A-CONSTANT LOWEST-UNIBUS-VIRTUAL-ADDRESS))
	(JUMP XUBR0)

;; quux: %xbus-write-sync is gone.  it waited on a status bit of the cadr tv's
;; control register before writing, for writing the color map in the retrace;
;; quux's tv registers report no retrace, and the color map is written
;; directly.  its misc opcode, 471, is free.

;; See comments on %XBUS-READ above.
XXBW (MISC-INST-ENTRY %XBUS-WRITE)
	(CALL GET-32-BITS)		;M-1 gets value to write
	(DISPATCH Q-DATA-TYPE C-PDL-BUFFER-POINTER TRAP-UNLESS-FIXNUM)
		(ERROR-TABLE ARGTYP FIXNUM PP 0)
	((WRITE-MEMORY-DATA) M-1)
	((VMA-START-WRITE M-T) ADD C-PDL-BUFFER-POINTER-POP	;Return random fixnum in M-T
		(A-CONSTANT LOWEST-IO-SPACE-VIRTUAL-ADDRESS))
	(CHECK-PAGE-WRITE)
	(POPJ)

XUBW (MISC-INST-ENTRY %UNIBUS-WRITE)
	(DISPATCH Q-DATA-TYPE C-PDL-BUFFER-POINTER TRAP-UNLESS-FIXNUM)
		(ERROR-TABLE ARGTYP FIXNUM PP 1)
	((M-T WRITE-MEMORY-DATA) Q-TYPED-POINTER C-PDL-BUFFER-POINTER-POP) ;WORD TO WRITE
;;; IF THIS IS MADE CONTINUABLE, THIS WILL HAVE TO BE FIXED
	(DISPATCH Q-DATA-TYPE C-PDL-BUFFER-POINTER TRAP-UNLESS-FIXNUM)
		(ERROR-TABLE ARGTYP FIXNUM PP 0)
	((M-A) (BYTE-FIELD 17. 1) C-PDL-BUFFER-POINTER-POP)	;UBUS WORD ADDR
	((VMA-START-WRITE) ADD M-A (A-CONSTANT LOWEST-UNIBUS-VIRTUAL-ADDRESS))
	(CHECK-PAGE-WRITE)
	(POPJ)


;;; %STORE-CONDITIONAL pointer, old-val, new-val
;;; This is protected against interrupts, provided that the value you
;;; are storing does not point at the EXTRA-PDL, and that the location
;;; is guaranteed never to contain a pointer to old-space (i.e. it
;;; only points to static areas.)  This is always protected against
;;; sequence breaks (other macrocode processes).
XSTACQ (MISC-INST-ENTRY %STORE-CONDITIONAL) ;args are pointer, old-val, new-val
	((M-A) Q-TYPED-POINTER C-PDL-BUFFER-POINTER-POP) ;new
	((M-B) Q-TYPED-POINTER C-PDL-BUFFER-POINTER-POP) ;old
	((M-1) Q-DATA-TYPE PDL-TOP)
	(CALL-NOT-EQUAL M-1 (A-CONSTANT (EVAL DTP-LOCATIVE)) TRAP)
    (ERROR-TABLE ARGTYP LOCATIVE PP 0)
;Won't interrupt between reading out the data here
	((VMA-START-READ) C-PDL-BUFFER-POINTER-POP) ;pntr
	(CHECK-PAGE-READ-NO-INTERRUPT)
	(DISPATCH TRANSPORT-READ-WRITE READ-MEMORY-DATA)
	((M-1) Q-TYPED-POINTER READ-MEMORY-DATA)
	(JUMP-NOT-EQUAL M-B A-1 XFALSE)		;Return NIL if old-val was wrong
	((WRITE-MEMORY-DATA-START-WRITE)	;Otherwise, store new-val
		SELECTIVE-DEPOSIT
		READ-MEMORY-DATA Q-ALL-BUT-TYPED-POINTER A-A)
;and writing the replacement data here
	(CHECK-PAGE-WRITE)
	(POPJ-AFTER-NEXT GC-WRITE-TEST)
       ((M-T) A-V-TRUE)


;;; Read microsecond clock into M-2  (preserve A-TEM1)
;; quux: one read of source 15 gives the whole word; the unibus clock took two,
;; the low half first to latch the high.
READ-MICROSECOND-CLOCK
	(POPJ-AFTER-NEXT (M-2) MICROSECOND-CLOCK)
       (NO-OP)

;the following two routines should be combined into the above one.  But be careful,
; registers are very touchy.

read-microsecond-clock-into-md
	;; quux: source 15, one read (see read-microsecond-clock).
	(popj-after-next (write-memory-data) microsecond-clock)
       (no-op)

;Read the time in microseconds, and put it in A-LAST-USEC-TIME.
;; quux: from source 15; MD is no longer touched, as it was by the unibus reads.
READ-USEC-TIME
	(POPJ-AFTER-NEXT (A-LAST-USEC-TIME) MICROSECOND-CLOCK)
       (NO-OP)

;;; quux: (%microsecond-clock-ldb ppss) returns the ppss field of one read of
;;; the microsecond clock, source 15, as a fixnum, the way %p-ldb returns a
;;; field of a word in memory.  lisp read the clock at unibus 764120 and
;;; 764122; one read of a field lets TIME take its bits without consing.
XUSLDB (MISC-INST-ENTRY %MICROSECOND-CLOCK-LDB)
	(JUMP-XCT-NEXT XLLDB1)
       ((M-1) MICROSECOND-CLOCK)

XHALT (MISC-INST-ENTRY %HALT)
	(JUMP HALT-CONS XFALSE)		;CONTINUING RETURNS NIL

))
