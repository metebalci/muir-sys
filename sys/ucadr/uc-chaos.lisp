(SETQ UC-CHAOS '(
;;; Come here for Unibus interrupt from Chaos network

(ASSIGN CHAOS-NUMBER-TRANSMIT-RETRIES 3)	;Send once and retry twice if aborted

CHAOS-INTR
	((MICRO-STACK-DATA-PUSH) (A-CONSTANT (I-MEM-LOC UB-INTR-RET)))
	((VMA-START-READ M-B) A-CHAOS-CSR-ADDRESS) ;M-B has base address of hardware
	(CHECK-PAGE-READ-NO-INTERRUPT)
	(JUMP-IF-BIT-CLEAR (LISP-BYTE %%CHAOS-CSR-RECEIVE-DONE) READ-MEMORY-DATA
		CHAOS-XMT-INTR)			;See if received a packet
	((A-INTR-TEM2) Q-POINTER READ-MEMORY-DATA	;Save CSR for later
			(A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	(CALL-XCT-NEXT CHAOS-LIST-GET)		;M-A gets next packet from free list
       ((VMA-START-READ) (A-CONSTANT (EVAL (+ 400 %SYS-COM-CHAOS-FREE-LIST))))
	(JUMP-EQUAL M-A A-V-NIL CHAOS-XMT-INTR)	;Can't receive now, hold up
	;; Read out the packet into this buffer, along with CSR1, CSR2, Bit-count
	;; M-A points at the buffer and M-B points at the hardware
	;; Buffer is assumed to be big enough for max possible word count (255)
	((WRITE-MEMORY-DATA) A-INTR-TEM2)	;Save CSR1
	((VMA-START-WRITE) SUB M-A (A-CONSTANT (EVAL (+ 2 %CHAOS-LEADER-CSR-1))))
	(CHECK-PAGE-WRITE-NO-INTERRUPT)
	((VMA-START-READ) ADD M-B (A-CONSTANT (EVAL %CHAOS-BIT-COUNT-OFFSET)))
	(CHECK-PAGE-READ-NO-INTERRUPT)
	((WRITE-MEMORY-DATA M-TEM) M+A+1 READ-MEMORY-DATA	;Type bits are 0, bit count is
		(A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))	;off by 1
	((A-INTR-TEM1) (BYTE-FIELD 8 4) M-TEM)	;Get word count, then save bit count
	((VMA-START-WRITE) SUB M-A (A-CONSTANT (EVAL (+ 2 %CHAOS-LEADER-BIT-COUNT))))
	(CHECK-PAGE-WRITE-NO-INTERRUPT)
	((WRITE-MEMORY-DATA) SELECTIVE-DEPOSIT WRITE-MEMORY-DATA
		Q-ALL-BUT-POINTER A-INTR-TEM1)	;Save word count
	((VMA-START-WRITE) SUB M-A (A-CONSTANT (EVAL (+ 2 %CHAOS-LEADER-WORD-COUNT))))
	(CHECK-PAGE-WRITE-NO-INTERRUPT)
	((A-INTR-TEM2) (A-CONSTANT 1))		;Offset in buffer array
CHAOS-RCV-INTR-LOOP	;Read two words out of the hardware, then store them
	((VMA-START-READ) ADD M-B (A-CONSTANT (EVAL %CHAOS-READ-BUFFER-OFFSET)))
	(CHECK-PAGE-READ-NO-INTERRUPT)
	((A-INTR-TEM1) ADD (M-CONSTANT -1) A-INTR-TEM1)	;Count down word count
	((M-TEM) READ-MEMORY-DATA)		;Save low word
	(JUMP-EQUAL M-ZERO A-INTR-TEM1 CHAOS-RCV-INTR-2)	;If word count was odd
	((VMA-START-READ) VMA)			;Get high word
	(ILLOP-IF-PAGE-FAULT)			;Mustn't bash M-TEM
	((A-INTR-TEM1) ADD (M-CONSTANT -1) A-INTR-TEM1)	;Count down word count
	;If the disk is busy, give it time to get three Xbus cycles after our two
	;Unibus cycles.  Combined with the one Xbus cycle it gets between the
	;two Unibus cycles, this should be enough to keep it from overrunning,
	;although just barely.
	(JUMP-NOT-EQUAL-XCT-NEXT A-DISK-BUSY M-ZERO CHAOS-RCV-INTR-1)
       ((M-T) (A-CONSTANT 16.))			;6.0 microseconds
	;If pdp11 is arbitrating Unibus, also delay, supposedly to make pdp11
	;run faster and prevent other devices such as Arm servo from getting
	;overrun.  Since the code for this that used to be here was a complete
	;no-op, this probably is not important, but do it anyway.
	(JUMP-EQUAL A-INTR-LOCAL-UNIBUS-MODE M-ZERO CHAOS-RCV-INTR-1)
	((M-T) M-ZERO)				;Default delay count (no delay)
CHAOS-RCV-INTR-1
	((WRITE-MEMORY-DATA) DPB READ-MEMORY-DATA (BYTE-FIELD 20 20) A-TEM)
CHAOS-RCV-DELAY
	(JUMP-NOT-EQUAL-XCT-NEXT M-T A-ZERO CHAOS-RCV-DELAY)
       ((M-T) SUB M-T (A-CONSTANT 1))
CHAOS-RCV-INTR-2
	((VMA-START-WRITE) ADD M-A A-INTR-TEM2)	;Write two halfwords into buffer
	(CHECK-PAGE-WRITE-NO-INTERRUPT)
	(JUMP-LESS-THAN-XCT-NEXT M-ZERO A-INTR-TEM1 CHAOS-RCV-INTR-LOOP)
       ((A-INTR-TEM2) M+A+1 M-ZERO A-INTR-TEM2)
	;; Now save CSR2, enable next receive, and cons onto receive list
	((VMA-START-READ) M-B)			;Get CSR
	(CHECK-PAGE-READ-NO-INTERRUPT)
	((WRITE-MEMORY-DATA) Q-POINTER READ-MEMORY-DATA
		(A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	((VMA-START-WRITE) SUB M-A (A-CONSTANT (EVAL (+ 2 %CHAOS-LEADER-CSR-2))))
	(CHECK-PAGE-WRITE-NO-INTERRUPT)
	((WRITE-MEMORY-DATA) IOR WRITE-MEMORY-DATA
		(A-CONSTANT (BYTE-MASK %%CHAOS-CSR-RECEIVER-CLEAR)))
	((VMA-START-WRITE) M-B)			;Write CSR to clear receiver
	(CHECK-PAGE-WRITE-NO-INTERRUPT)
	(CALL-XCT-NEXT CHAOS-LIST-PUT)		;Add packet in M-A to receive list
       ((VMA-START-READ) (A-CONSTANT (EVAL (+ 400 %SYS-COM-CHAOS-RECEIVE-LIST))))
	(JUMP-IF-BIT-CLEAR M-SBS-CHAOS CHAOS-INTR-EXIT)	;Request SB if enabled
	((INTERRUPT-CONTROL) IOR LOCATION-COUNTER (A-CONSTANT 1_26.))
;drops through
;drops in
CHAOS-WAKEUP (MISC-INST-ENTRY %CHAOS-WAKEUP)
	;drops in
;; Here to dismiss the interrupt.  We must decide on the interrupt enables.
;; If there are any free buffers, we can enable receive interrupts.
;; If there are any buffers wanting to be transmitted, we can enable transmit interrupts.
CHAOS-INTR-EXIT
	((M-A) SETZ)				;20 = receive-enable, 40 = transmit-enable
	((VMA-START-READ) (A-CONSTANT (EVAL (+ 400 %SYS-COM-CHAOS-FREE-LIST))))
	(CHECK-PAGE-READ-NO-INTERRUPT)
	((M-TEM) Q-TYPED-POINTER READ-MEMORY-DATA)
	(JUMP-EQUAL M-TEM A-V-NIL CHAOS-INTR-EXIT-1)
	((M-A) DPB (M-CONSTANT -1) (LISP-BYTE %%CHAOS-CSR-RECEIVE-ENABLE) A-A)
						;Free list not empty, enable receive done
CHAOS-INTR-EXIT-1
	(JUMP-GREATER-THAN M-ZERO A-CHAOS-TRANSMIT-ABORTED
		CHAOS-INTR-EXIT-2)		;Disable transmit-done if in abort-timeout
	((VMA-START-READ) (A-CONSTANT (EVAL (+ 400 %SYS-COM-CHAOS-TRANSMIT-LIST))))
	(CHECK-PAGE-READ-NO-INTERRUPT)
	((M-TEM) Q-TYPED-POINTER READ-MEMORY-DATA)
	(JUMP-EQUAL M-TEM A-V-NIL CHAOS-INTR-EXIT-2)
	((M-A) DPB (M-CONSTANT -1) (LISP-BYTE %%CHAOS-CSR-TRANSMIT-ENABLE) A-A)
						;Xmt list not empty, enable transmit done
CHAOS-INTR-EXIT-2
	((VMA-START-READ) A-CHAOS-CSR-ADDRESS)	;M-B not valid if called as misc inst
	(CHECK-PAGE-READ-NO-INTERRUPT)
	((M-TEM) READ-MEMORY-DATA)
	((WRITE-MEMORY-DATA-START-WRITE) SELECTIVE-DEPOSIT M-A
		(LISP-BYTE %%CHAOS-CSR-INTERRUPT-ENABLES) A-TEM)
	(CHECK-PAGE-WRITE-NO-INTERRUPT)
	(JUMP XFALSE)				;Could be called as misc inst, mustn't popj

;;; Transmit interrupt handler
;;; A-CHAOS-TRANSMIT-RETRY-COUNT is 0 if nothing going on, otherwise number of retries
;;; before we should give up.  Note buffer not removed from list until done.
CHAOS-XMT-INTR
	((VMA-START-READ) M-B)			;Fetch CSR again
	(CHECK-PAGE-READ-NO-INTERRUPT)
	(JUMP-IF-BIT-CLEAR (LISP-BYTE %%CHAOS-CSR-TRANSMIT-DONE) READ-MEMORY-DATA
		CHAOS-INTR-EXIT)		;Transmit in progress
	(JUMP-EQUAL A-CHAOS-TRANSMIT-RETRY-COUNT M-ZERO CHAOS-XMT-0) ;Jump if transmit idle
	;; Next instruction starts a retransmission if either we have finished delaying
	;; after a transmit abort, or if we get woken up or receive a packet during
	;; a transmit abort delay (this prevents infinite hang if the clock is off and doesn't
	;; sound too unreasonable).
	(JUMP-NOT-EQUAL A-CHAOS-TRANSMIT-ABORTED M-ZERO CHAOS-XMT-0)
	;; Here if a transmission really just completed
	(JUMP-IF-BIT-CLEAR (LISP-BYTE %%CHAOS-CSR-TRANSMIT-ABORT) READ-MEMORY-DATA
		CHAOS-XMT-DONE)			;Jump if transmit done and not aborted
	((A-COUNT-CHAOS-TRANSMIT-ABORTS) M+A+1 M-ZERO A-COUNT-CHAOS-TRANSMIT-ABORTS)
	;; If transmit aborted, keep trying until count runs out, then give up
	((A-CHAOS-TRANSMIT-RETRY-COUNT) ADD (M-CONSTANT -1) A-CHAOS-TRANSMIT-RETRY-COUNT)
	(JUMP-EQUAL M-ZERO A-CHAOS-TRANSMIT-RETRY-COUNT CHAOS-XMT-DONE)	;Give up
	(JUMP-XCT-NEXT CHAOS-INTR-EXIT)		;Wait a while, then retransmit
       ((A-CHAOS-TRANSMIT-ABORTED) SETO)

CHAOS-XMT-0
	;; Get current or next transmit packet
	((VMA-START-READ) (A-CONSTANT (EVAL (+ 400 %SYS-COM-CHAOS-TRANSMIT-LIST))))
	(CHECK-PAGE-READ-NO-INTERRUPT)
	((A-CHAOS-TRANSMIT-ABORTED) SETZ)	;Forget this state left from previous packet
	((M-A) Q-TYPED-POINTER READ-MEMORY-DATA) ;Note, don't call CHAOS-LIST-GET
						;since we are leaving it on the list for now
	(JUMP-EQUAL M-A A-V-NIL CHAOS-INTR-EXIT)	;Nothing to transmit, give up
	;; If this is not a retransmission, initialize retry count
	(JUMP-NOT-EQUAL M-ZERO A-CHAOS-TRANSMIT-RETRY-COUNT CHAOS-XMT-1)
	((A-CHAOS-TRANSMIT-RETRY-COUNT) (A-CONSTANT CHAOS-NUMBER-TRANSMIT-RETRIES))
CHAOS-XMT-1
	((VMA-START-READ) SUB M-A (A-CONSTANT (EVAL (+ 2 %CHAOS-LEADER-WORD-COUNT))))
	(CHECK-PAGE-READ-NO-INTERRUPT)
	((A-INTR-TEM2) (A-CONSTANT 1))		;Offset in buffer
	((A-INTR-TEM1) Q-POINTER READ-MEMORY-DATA)	;Halfword count
CHAOS-XMT-2
	((VMA-START-READ) ADD M-A A-INTR-TEM2)	;Get a pair of halfwords
	(CHECK-PAGE-READ-NO-INTERRUPT)
	((A-INTR-TEM1) ADD (M-CONSTANT -1) A-INTR-TEM1)	;Count down word count
	;See comments in receive loop above
	(JUMP-NOT-EQUAL-XCT-NEXT A-DISK-BUSY M-ZERO CHAOS-XMT-4)
       ((M-T) (A-CONSTANT 16.))			;6.0 microseconds
	(JUMP-EQUAL A-INTR-LOCAL-UNIBUS-MODE M-ZERO CHAOS-XMT-4)
	((M-T) M-ZERO)				;Default delay count (no delay)
CHAOS-XMT-4
	((WRITE-MEMORY-DATA) READ-MEMORY-DATA)	;Write first halfword into hardware
CHAOS-XMT-DELAY
	(JUMP-NOT-EQUAL-XCT-NEXT M-T A-ZERO CHAOS-XMT-DELAY)
       ((M-T) SUB M-T (A-CONSTANT 1))
	((VMA-START-WRITE) ADD M-B (A-CONSTANT (EVAL %CHAOS-WRITE-BUFFER-OFFSET)))
	(CHECK-PAGE-WRITE-NO-INTERRUPT)
	(JUMP-EQUAL M-ZERO A-INTR-TEM1 CHAOS-XMT-3)	;Done if was odd number of words
	((WRITE-MEMORY-DATA-START-WRITE) (BYTE-FIELD 20 20) WRITE-MEMORY-DATA)
	(CHECK-PAGE-WRITE-NO-INTERRUPT)		;Write second halfword into hardware
	((A-INTR-TEM1) ADD (M-CONSTANT -1) A-INTR-TEM1)	;Count down word count
	(JUMP-LESS-THAN-XCT-NEXT M-ZERO A-INTR-TEM1 CHAOS-XMT-2)
       ((A-INTR-TEM2) M+A+1 M-ZERO A-INTR-TEM2)
CHAOS-XMT-3
	((VMA-START-READ) ADD M-B (A-CONSTANT (EVAL %CHAOS-START-TRANSMIT-OFFSET)))
	(CHECK-PAGE-READ-NO-INTERRUPT)		;Initiate transmission
	(JUMP CHAOS-INTR-EXIT)

;; Here when we are through with a transmit packet.
CHAOS-XMT-DONE
	(CALL-XCT-NEXT CHAOS-LIST-GET)		;Pull this guy off xmt list, we're done with it
       ((VMA-START-READ) (A-CONSTANT (EVAL (+ 400 %SYS-COM-CHAOS-TRANSMIT-LIST))))
	(CALL-NOT-EQUAL-XCT-NEXT M-A A-V-NIL CHAOS-LIST-PUT)	;Add to free list
       ((VMA-START-READ) (A-CONSTANT (EVAL (+ 400 %SYS-COM-CHAOS-FREE-LIST))))
	(JUMP-XCT-NEXT CHAOS-XMT-0)		;Now transmit more if possible
       ((A-CHAOS-TRANSMIT-RETRY-COUNT) SETZ)	;Transmit not in progress now

;;; Take packet off list which has been VMA-START-READ, return it in M-A
;;; M-A can return with NIL in it.  Uses A-INTR-TEM1
CHAOS-LIST-GET
	(CHECK-PAGE-READ-NO-INTERRUPT)		;MD gets first buffer on list
	((A-INTR-TEM1) VMA)			;Save address of list header
	((M-A) Q-TYPED-POINTER READ-MEMORY-DATA)
	(POPJ-EQUAL M-A A-V-NIL)		;Return if list empty
	((VMA-START-READ) SUB M-A (A-CONSTANT (EVAL (+ 2 %CHAOS-LEADER-THREAD))))
	(CHECK-PAGE-READ-NO-INTERRUPT)		;MD gets next buffer on list
	((WRITE-MEMORY-DATA) Q-TYPED-POINTER READ-MEMORY-DATA)
	(POPJ-AFTER-NEXT (VMA-START-WRITE) A-INTR-TEM1)
       (CHECK-PAGE-WRITE-NO-INTERRUPT)

;;; Put packet in M-A onto list which has been VMA-START-READ
;;; Uses A-INTR-TEM1
CHAOS-LIST-PUT
	(CHECK-PAGE-READ-NO-INTERRUPT)		;MD gets present first buffer on list
	((A-INTR-TEM1) VMA)			;Save address of list header
	((WRITE-MEMORY-DATA) Q-TYPED-POINTER READ-MEMORY-DATA)	;Thread onto new first buffer
	((VMA-START-WRITE) SUB M-A (A-CONSTANT (EVAL (+ 2 %CHAOS-LEADER-THREAD))))
	(CHECK-PAGE-WRITE-NO-INTERRUPT)
	((WRITE-MEMORY-DATA) Q-TYPED-POINTER M-A)	;Change list header
	(POPJ-AFTER-NEXT (VMA-START-WRITE) A-INTR-TEM1)
       (CHECK-PAGE-WRITE-NO-INTERRUPT)


))