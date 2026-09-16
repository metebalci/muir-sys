(SETQ UC-DISK '(
;;; Here to perform a disk swapping operation.
;;; M-A has the virtual memory address, M-T has the command.
;;; M-B is no longer an argument at this level.
;;; The CCW is already set up starting at location in M-C.  M-C, M-T bashed.
;;; Returns with operation successfully completed.

DISK-SWAP-HANDLER
	(CALL-XCT-NEXT DISK-PGF-SAVE)
       ((A-DISK-IDLE-TIME) M-ZERO)		;I use the disk
	((M-1) VMA-PAGE-ADDR-PART M-A)		;Convert virtual address to disk address
	(CALL-GREATER-OR-EQUAL M-1 A-DISK-MAXIMUM ILLOP)	;Address out of bounds
	((M-1) ADD M-1 A-DISK-OFFSET)		;Relocate to appropriate part of disk
	(CALL START-DISK-SWAP)			;Start the disk operation
	((MD) SETZ)		;Turn off CPU run light
	((VMA-START-WRITE M-T) ADD VMA (A-CONSTANT 2))
	(CHECK-PAGE-WRITE)
	(CALL READ-MICROSECOND-CLOCK)		;Read microsecond clock into M-2
	((M-1) A-AGING-SCAN-POINTER)		;Run Ager while in disk wait
	(CALL-NOT-EQUAL M-1 A-FINDCORE-SCAN-POINTER AGER)
	(CALL AWAIT-DISK)			;Now wait for operation to complete
	(CALL-XCT-NEXT READ-MICROSECOND-CLOCK)	;Get current time
       ((M-1) M-2)				;but save old time
	((M-2) SUB M-2 A-1)			;Get delta time
	((A-DISK-WAIT-TIME) ADD M-2 A-DISK-WAIT-TIME)	;Increment wait time counter
	((MD) (M-CONSTANT -1))	;Turn on CPU run light
	((VMA-START-WRITE) M-T)
	(CHECK-PAGE-WRITE)
	(JUMP DISK-PGF-RESTORE)

;Given a typeless virtual memory address in M-A, set A-DISK-CYL-BEG and A-DISK-CYL-END
;to the typeless virtual memory addresses which enclose the cylinder containing that block
;Smashes M-1, M-2, A-TEM1
GET-DISK-CYLINDER-BOUNDARY
	((M-1) VMA-PAGE-ADDR-PART M-A)
	((M-1) ADD M-1 A-DISK-OFFSET)
	(CALL-XCT-NEXT DIV)			;M-1 gets n blocks into cylinder
       ((M-2) DPB M-ZERO Q-ALL-BUT-POINTER A-DISK-BLOCKS-PER-CYLINDER)
	((M-1) DPB M-1 VMA-PAGE-ADDR-PART A-ZERO)	;Convert pages to words
	((M-2) DPB M-2 VMA-PAGE-ADDR-PART A-ZERO)
	(POPJ-AFTER-NEXT (A-DISK-CYL-BEG) SUB M-A A-1)
       ((A-DISK-CYL-END) ADD M-2 A-DISK-CYL-BEG)


;;; Here to start a disk operation, first waiting for the disk to become idle.
;;; M-1 has the disk address, M-T has the command.
;;; The CLP is already built and is in M-C.  M-T, M-C, M-1, M-2 bashed.
;;; Multiple pages can be transfered to consecutive pages on the disk, as
;;; per the CCW list.  Returns with A-DISK-RUN-LIGHT in VMA.
START-DISK-SWAP
	(CALL AWAIT-DISK)			;Wait until disk is idle
	((A-DISK-READ-WRITE) M-T)		;Then store parameters into A-memory
	((A-DISK-CLP) M-C)
	((A-DISK-RETRY-STATE) M-ZERO)
	(CALL-XCT-NEXT DIV)			;Convert disk address to physical
       ((M-2) DPB M-ZERO Q-ALL-BUT-POINTER A-DISK-BLOCKS-PER-CYLINDER)
	((A-DISK-ADDRESS) DPB Q-R (BYTE-FIELD 12. 16.) A-ZERO)	;Save cylinder
	(CALL-XCT-NEXT DIV)
       ((M-2) DPB M-ZERO Q-ALL-BUT-POINTER A-DISK-BLOCKS-PER-TRACK)
	((A-DISK-ADDRESS) DPB Q-R (BYTE-FIELD 8 8) A-DISK-ADDRESS)	;Save head
	((A-DISK-ADDRESS) DPB M-1 (BYTE-FIELD 8 0) A-DISK-ADDRESS)	;Save block
	(JUMP-XCT-NEXT START-DISK-OP)
       ((A-DISK-RESERVED-FOR-USER) (A-CONSTANT 0))	;Not any more, it isn't!

;;; Here to start a disk operation, first waiting for the disk to become idle.
;;; M-1 has the disk address, M-B has the page frame number of the first main
;;; memory page to transfer, M-T has the command.
;;; The CLP is always 777 .  M-T, M-C, M-1, M-2 bashed.
;;; Returns with A-DISK-RUN-LIGHT in VMA.
START-DISK-1-PAGE
	((M-2) (A-CONSTANT 1))			;Transfer just one page
	((M-C) (A-CONSTANT 777))		;CLP is always 777
;;; M-1 starting disk address, M-B starting main memory page frame number.
;;; M-2 number of pages to transfer, M-T command, M-C address of CCW list.
;;; Bashes M-T, M-1, M-2.  Returns with A-DISK-RUN-LIGHT in VMA.
START-DISK-N-PAGES
	(CALL AWAIT-DISK)			;Wait until disk is idle
	((A-DISK-READ-WRITE) M-T)		;Then store parameters into A-memory
	((A-DISK-CLP) M-C)
	((A-DISK-RETRY-STATE) M-ZERO)
	((M-T) M-2)
	(CALL-XCT-NEXT DIV)			;Convert disk address to physical
       ((M-2) DPB M-ZERO Q-ALL-BUT-POINTER A-DISK-BLOCKS-PER-CYLINDER)
	((A-DISK-ADDRESS) DPB Q-R (BYTE-FIELD 12. 16.) A-ZERO)	;Save cylinder
	(CALL-XCT-NEXT DIV)
       ((M-2) DPB M-ZERO Q-ALL-BUT-POINTER A-DISK-BLOCKS-PER-TRACK)
	((A-DISK-ADDRESS) DPB Q-R (BYTE-FIELD 8 8) A-DISK-ADDRESS)	;Save head
	((A-DISK-ADDRESS) DPB M-1 (BYTE-FIELD 8 0) A-DISK-ADDRESS)	;Save block
	;; Now build the CCW list
	((VMA) ADD (M-CONSTANT -1) A-DISK-CLP)
	((MD) DPB M-B VMA-PHYS-PAGE-ADDR-PART (A-CONSTANT 1))
BUILD-CCW-LIST-1
	(JUMP-GREATER-THAN M-T (A-CONSTANT 1) BUILD-CCW-LIST-2)
	((MD) SUB MD (A-CONSTANT 1))	;last
BUILD-CCW-LIST-2
	((VMA-START-WRITE) ADD VMA (A-CONSTANT 1))
	(CHECK-PAGE-WRITE-NO-INTERRUPT)
	((M-T) SUB M-T (A-CONSTANT 1))
	(JUMP-GREATER-THAN-XCT-NEXT M-T (A-CONSTANT 0) BUILD-CCW-LIST-1)
       ((MD) ADD MD (A-CONSTANT (EVAL PAGE-SIZE)))
	((A-DISK-RESERVED-FOR-USER) (A-CONSTANT 0))	;Not any more, it isn't!
;;; Here to start a disk operation that has been set up in the A-memory variables.
;;; Also called from interrupt level for retries
;;; Returns immediately; call AWAIT-DISK if you want to wait for completion.
;;; Returns with address of disk-run-light in VMA
START-DISK-OP
	((A-DISK-COMMAND) A-DISK-READ-WRITE)
	((A-DISK-DOING-READ-COMPARE) M-ZERO)
;;; Here to start some command other than the one we are really supposed to be doing
START-DISK-OP-1
	((MD) DPB (M-CONSTANT -1)	;Turn on interrupt enable
		(BYTE-FIELD 1 11.) A-DISK-COMMAND)
;;; Enter here from %DISK-OP
START-DISK-OP-2
	((VMA-START-WRITE) A-DISK-REGS-BASE)
	(CHECK-PAGE-WRITE-NO-INTERRUPT)
	((MD) A-DISK-CLP)
	((VMA-START-WRITE) ADD VMA (A-CONSTANT 1))
	(CHECK-PAGE-WRITE-NO-INTERRUPT)
	((MD) A-DISK-ADDRESS)
	((VMA-START-WRITE) ADD VMA (A-CONSTANT 1))
	(CHECK-PAGE-WRITE-NO-INTERRUPT)
	((A-DISK-BUSY) (M-CONSTANT -1))
	((VMA-START-WRITE) ADD VMA (A-CONSTANT 1))	;Start it up
	(CHECK-PAGE-WRITE-NO-INTERRUPT)
	((MD) (M-CONSTANT -1))	;Turn on disk run light
	(POPJ-AFTER-NEXT (VMA-START-WRITE) A-DISK-RUN-LIGHT)
       (CHECK-PAGE-WRITE-NO-INTERRUPT)

;;; Subroutine to wait for a disk operation to complete.  Checks for interrupts,
;;; but doesn't check for interrupts between discovering that it is idle and
;;; returning; hence it is guaranteed still to be idle.
AWAIT-DISK
	(POPJ-EQUAL A-DISK-BUSY M-ZERO)
	(CHECK-PAGE-READ)		;Check for interrupt (can't do directly)
	(JUMP AWAIT-DISK)

;;; Disk completion handler - called from XBUS interrupt handler, status in MD
;;; The following registers may be clobbered
;;; M-A, M-B, M-T
;;; M-TEM, A-TEM1, A-TEM2, A-TEM3
;;; DISPATCH-CONSTANT, Q-R, VMA, MD

DISK-COMPLETION
	(CALL DISK-COMPLETION-GET-STATUS)
	(JUMP-NOT-EQUAL M-ZERO A-DISK-DOING-READ-COMPARE DISK-COMPLETION-READ-COMPARE-OVER)
	(JUMP-NOT-EQUAL M-A A-ZERO DISK-COMPLETION-ERROR)
	;; Operation completed without error, but may still need to do a read-compare.
	((OA-REG-LOW) DPB M-ZERO (BYTE-FIELD 31. 1) A-DISK-READ-WRITE)
	((M-TEM) DPB (M-CONSTANT -1) (BYTE-FIELD 1 0))	;1 if read, 2 if write
	((M-TEM) AND M-TEM A-DISK-SWITCHES)
	((M-B) (A-CONSTANT DISK-READ-COMPARE-COMMAND))
	((A-DISK-DOING-READ-COMPARE) SETO)
	(JUMP-NOT-EQUAL-XCT-NEXT M-TEM A-ZERO START-DISK-OP-1) ;Must check this transfer
       ((A-DISK-COMMAND) DPB M-B (BYTE-FIELD 4 0) A-DISK-COMMAND) ;using same recovery features
DISK-COMPLETION-OK	;; Here when a disk operation has successfully completed
	((MD) M-ZERO)	;Turn off disk run light
	((VMA-START-WRITE) A-DISK-RUN-LIGHT)
	(CHECK-PAGE-WRITE-NO-INTERRUPT)
	((A-DISK-BUSY) M-ZERO)
	(POPJ-AFTER-NEXT (VMA-START-WRITE) A-DISK-REGS-BASE) ;Clear interrupt enable
       (CHECK-PAGE-WRITE-NO-INTERRUPT)

DISK-COMPLETION-GET-STATUS
	(CALL-IF-BIT-CLEAR (BYTE-FIELD 1 0) MD ILLOP)	;Control busy?
	((A-DISK-STATUS) MD)	;Store away results of operation
	((M-A) AND MD		;Get just error status bits
		(A-CONSTANT (PLUS 1_4 1_5 1_6 1_8 1_9 1_10. 1_11. 1_12. 1_13.
				  1_14. 1_15. 1_16. 1_17. 1_18. 1_19. 1_20. 1_23.)))
	((VMA-START-READ) ADD VMA (A-CONSTANT 1))
	(CHECK-PAGE-READ-NO-INTERRUPT)
	((A-DISK-MA) MD)
	((VMA-START-READ) ADD VMA (A-CONSTANT 1))
	(CHECK-PAGE-READ-NO-INTERRUPT)
	((A-DISK-FINAL-ADDRESS) MD)
	((VMA-START-READ) ADD VMA (A-CONSTANT 1))
	(CHECK-PAGE-READ-NO-INTERRUPT)
	(POPJ-AFTER-NEXT NO-OP)
       ((A-DISK-ECC) MD)

DISK-COMPLETION-READ-COMPARE-OVER
	((A-DISK-DOING-READ-COMPARE) M-ZERO)
	(JUMP-NOT-EQUAL M-A A-ZERO DISK-COMPLETION-READ-COMPARE-ERROR)
	((M-TEM) A-DISK-STATUS)
	(JUMP-IF-BIT-CLEAR (BYTE-FIELD 1 22.) M-TEM DISK-COMPLETION-OK)	;No rd/comp error
	((A-DISK-READ-COMPARE-DIFFERENCES) M+A+1 M-ZERO A-DISK-READ-COMPARE-DIFFERENCES)
DISK-COMPLETION-READ-COMPARE-ERROR
	(JUMP-EQUAL A-DISK-READ-WRITE M-ZERO DISK-COMPLETION-READ-COMPARE-READ-ERROR)
	(CALL LOG-DISK-ERROR)
	(JUMP-XCT-NEXT START-DISK-OP)		;Do write over
       ((A-DISK-READ-COMPARE-REWRITES) M+A+1 M-ZERO A-DISK-READ-COMPARE-REWRITES)

DISK-COMPLETION-READ-COMPARE-READ-ERROR
	((A-DISK-READ-COMPARE-REREADS) M+A+1 M-ZERO A-DISK-READ-COMPARE-REREADS)
DISK-COMPLETION-ERROR
	((A-DISK-ERROR-COUNT) M+A+1 M-ZERO A-DISK-ERROR-COUNT)
	(CALL LOG-DISK-ERROR)
	((M-TEM) AND M-A (A-CONSTANT (PLUS 1_4   ;Multiple select
					   1_5   ;No select
					   1_6   ;Fault
					   1_9   ;Off line
					   1_19. ;Mem parity error
					   1_20. ;NXM
					   )))
	(JUMP-NOT-EQUAL M-TEM A-ZERO FATAL-DISK-ERROR)	;Fatal error, die
	((M-TEM) AND M-A (A-CONSTANT (PLUS 1_8   ;Off cylinder
					   1_10. ;Seek error
					   1_11. ;Timeout error
					   1_12. ;Start-block error
					   1_13. ;Any termination
					   1_14. ;Overrun
					   1_23. ;Internal parity error
					   )))
	(JUMP-NOT-EQUAL M-TEM A-ZERO DISK-COMPLETION-RETRY)
	;(JUMP-IF-BIT-SET (BYTE-FIELD 1 15.) M-A DISK-COMPLETION-ECC)
	;; ECC Hard, ECC Soft, Header ECC, or Header Compare
	;; Operation may succeed if error-recovery features invoked (command <7:4>)
	;; However, we use only the data strobe features, not the servo offset
	;; features.  See the bugs mentioned in LMDOC;DISK
DISK-COMPLETION-RECOVER
	(JUMP-EQUAL M-B (A-CONSTANT DISK-WRITE-COMMAND) DISK-COMPLETION-RETRY)
	((M-TEM) A-DISK-MA)		;Get controller type
	(DISPATCH (BYTE-FIELD 2 22.) M-TEM D-DISK-COMPLETION-RECOVER)
(LOCALITY D-MEM)
(START-DISPATCH 2 0)
D-DISK-COMPLETION-RECOVER
	(P-BIT R-BIT)			;Trident, drop through
	(INHIBIT-XCT-NEXT-BIT DISK-COMPLETION-RETRY)	;Marksman, no recovery features
	(INHIBIT-XCT-NEXT-BIT ILLOP)	;Type 2 not defined
	(P-BIT R-BIT)			;Type 3 treat as Trident in case old disk control
(END-DISPATCH)
(LOCALITY I-MEM)
	((M-TEM) A-DISK-COMMAND)
	(JUMP-IF-BIT-SET (BYTE-FIELD 1 6) M-TEM DISK-COMPLETION-RETRY) ;Features exhausted
	(JUMP-IF-BIT-CLEAR-XCT-NEXT (BYTE-FIELD 1 7) M-TEM START-DISK-OP-1)
       ((A-DISK-COMMAND) DPB (M-CONSTANT -1) (BYTE-FIELD 1 7) A-DISK-COMMAND)
	(JUMP-XCT-NEXT START-DISK-OP-1)
       ((A-DISK-COMMAND) SUB M-TEM (A-CONSTANT 1_6))	;Bit 7 off, bit 6 on

DISK-COMPLETION-RETRY	;Operation may succeed if tried again
	(JUMP-IF-BIT-CLEAR (BYTE-FIELD 1 14.) M-A DISK-COMPLETION-RETRY-1)
	((VMA-START-READ) A-CHAOS-CSR-ADDRESS)	;Overrun: try turning off Chaosnet
	(CHECK-PAGE-READ-NO-INTERRUPT)
	((M-TEM) MD)
	((MD-START-WRITE) SELECTIVE-DEPOSIT M-ZERO
		(LISP-BYTE %%CHAOS-CSR-INTERRUPT-ENABLES) A-TEM)
	(CHECK-PAGE-WRITE-NO-INTERRUPT)
DISK-COMPLETION-RETRY-1
	((A-DISK-RETRY-STATE Q-R) M+A+1 M-ZERO A-DISK-RETRY-STATE)
	(JUMP-GREATER-THAN Q-R (A-CONSTANT 5) FATAL-DISK-ERROR)	;Give up after 5 tries
	(CALL-IF-BIT-CLEAR (BYTE-FIELD 1 0) Q-R DISK-RECALIBRATE)	;Recal 2nd, 4th time
	(JUMP START-DISK-OP)

;;; This is called with the disk not busy, and possibly at interrupt level.
DISK-RECALIBRATE	;Recalibrate the disk.  Callable as a subroutine.
	((MD) (A-CONSTANT DISK-RECALIBRATE-COMMAND))
	((VMA-START-WRITE) A-DISK-REGS-BASE)
	(CHECK-PAGE-WRITE-NO-INTERRUPT)
	((A-DISK-RECALIBRATE-COUNT) M+A+1 M-ZERO A-DISK-RECALIBRATE-COUNT)
	((VMA-START-WRITE) ADD VMA (A-CONSTANT 3))
	(CHECK-PAGE-WRITE-NO-INTERRUPT)
DISK-RECALIBRATE-WAIT	;Now wait for on-cylinder.  Must NOT check for interrupts
			;since may be called from interrupt level.  Hopefully this
			;doesn't happen often enough to lose many keyboard characters.
			;This is also called from COLD-RUN-DISK
	((VMA-START-READ) A-DISK-REGS-BASE)
	(CHECK-PAGE-READ-NO-INTERRUPT)
	(JUMP-IF-BIT-CLEAR (BYTE-FIELD 1 0) MD DISK-RECALIBRATE-WAIT) ;Wait for startup
	(JUMP-IF-BIT-SET (BYTE-FIELD 1 8) MD DISK-RECALIBRATE-WAIT) ;Wait for not off cyl
	(POPJ)

;;; Here if a fatal disk error has occurred.  Pass back to user if this is from user.
FATAL-DISK-ERROR
	(CALL-EQUAL M-ZERO A-DISK-RESERVED-FOR-USER ILLOP)
	(JUMP DISK-COMPLETION-OK)	;Well, sort of

;;; Log a disk error for later analysis by macrocode or console program
LOG-DISK-ERROR
	((M-TEM) A-DISK-CLP)
	((MD) DPB M-TEM (BYTE-FIELD 20 20) A-DISK-COMMAND)
	((VMA-START-WRITE) A-DISK-ERROR-LOG-POINTER)
	(ILLOP-IF-PAGE-FAULT)
	((MD) A-DISK-FINAL-ADDRESS)
	((VMA-START-WRITE) ADD VMA (A-CONSTANT 1))
	(ILLOP-IF-PAGE-FAULT)
	((MD) A-DISK-STATUS)
	((VMA-START-WRITE) ADD VMA (A-CONSTANT 1))
	(ILLOP-IF-PAGE-FAULT)
	((MD) A-DISK-MA)	
	((VMA-START-WRITE) ADD VMA (A-CONSTANT 1))
	(ILLOP-IF-PAGE-FAULT)
	(POPJ-LESS-THAN-XCT-NEXT VMA (A-CONSTANT 637))
       ((A-DISK-ERROR-LOG-POINTER) ADD VMA (A-CONSTANT 1))
	(POPJ-AFTER-NEXT (A-DISK-ERROR-LOG-POINTER) (A-CONSTANT 600))
       (NO-OP)

;I don't want to try out this error-correction stuff right now
;Also this knows the disk geometry (e.g. number of heads per disk)
;Something will have to change for multiple units
;
;DISK-COMPLETION-ECC	;ECC Soft - fix bad bits in memory and continue
;			;The disk address has not been incremented past the sector in error
;			;The MA has the address of the last word in the bad page
;			;The right half of the ECC register is the bit number in error
;			;The left half of the ECC register is a mask of which bits are wrong
;	((A-DISK-ECC-COUNT) M+A+1 M-ZERO A-DISK-ECC-COUNT)
;	((M-A) A-DISK-ECC)
;	(CALL-XCT-NEXT PHYS-MEM-READ)
;       ((VMA) (BYTE-FIELD 8 5) M-A A-DISK-MA)	;VMA<21:0> gets physical addr of 1st bad word
;	((M-B) (BYTE-FIELD 5 0) M-A)	;Get bit number of first erroneous bit
;	((M-A) (BYTE-FIELD 20 20) M-A)	;Get erroneous bits mask
;	((M-TEM) M-A-1 (M-CONSTANT 32.) A-B)	;Byte length-1 for bits in first word
;	((OA-REG-LOW) DPB M-TEM OAL-BYTL-1 A-B)
;	((A-TEM1) DPB M-A (BYTE-FIELD 0 0) A-ZERO)	;Erroneous bits in first word
;	(CALL-XCT-NEXT PHYS-MEM-WRITE)	;Correct first word
;       ((MD) XOR MD A-TEM1)
;	(JUMP-LESS-OR-EQUAL M-B (A-CONSTANT 16.) DISK-COMPLETION-ECC-2) ;If all bits in 1st wd
;	((OA-REG-LOW) SUB (M-CONSTANT 32.) A-B)	;Rotate remainder of bit mask to low bits
;	((M-A) (BYTE-FIELD 16. 0) M-A)
;	(JUMP-EQUAL M-A A-ZERO DISK-COMPLETION-ECC-2)	;Jump if no bits in second word
;	(CALL-XCT-NEXT PHYS-MEM-READ)
;       ((VMA) ADD VMA (A-CONSTANT 1))
;	(CALL-XCT-NEXT PHYS-MEM-WRITE)
;       ((MD) XOR MD A-A)
;DISK-COMPLETION-ECC-2
;	(CALL-XCT-NEXT PHYS-MEM-READ)	;Fetch a CCW
;       ((VMA) A-DISK-CLP)
;	((M-TEM) XOR MD A-DISK-MA)
;	((M-TEM) (BYTE-FIELD 14. 8) M-TEM)
;	(JUMP-IF-BIT-CLEAR (BYTE-FIELD 1 0) MD DISK-COMPLETION-ECC-4)	;End CCW list
;	(JUMP-NOT-EQUAL-XCT-NEXT M-TEM A-ZERO DISK-COMPLETION-ECC-2)
;       ((A-DISK-CLP) ADD VMA (A-CONSTANT 1))
;	;Advance the disk address manually
;	((M-A) M+A+1 M-ZERO A-DISK-FINAL-ADDRESS)
;	((M-TEM) (BYTE-FIELD 8 0) M-A)	;Block number
;	(JUMP-LESS-THAN M-TEM A-DISK-CURRENT-BLOCKS-PER-TRACK DISK-COMPLETION-ECC-3)
;	((M-A) DPB M-ZERO (BYTE-FIELD 8 0) A-A)	;Recycle to block 0
;	((M-A) ADD M-A (A-CONSTANT 400))	; on next head
;	((M-TEM) (BYTE-FIELD 8 8) M-A)	;Head number
;	(JUMP-LESS-THAN M-TEM A-DISK-CURRENT-NUMBER-OF-HEADS DISK-COMPLETION-ECC-3)
;	((M-A) DPB M-ZERO (BYTE-FIELD 8 8) A-A)	;Recycle to head 0
;	((M-A) ADD M-A (A-CONSTANT 200000))	; on next cylinder
;DISK-COMPLETION-ECC-3
;	((A-DISK-ADDRESS) M-A)
;	(JUMP START-DISK-OP-1)
;
;DISK-COMPLETION-ECC-4		;Here for ECC error corrected on last page of transfer
;	(CALL-NOT-EQUAL M-TEM A-ZERO ILLOP)	;CCW not found in CCW list?
;	(JUMP DISK-COMPLETION-OK)

;;; Support for "user" disk I/O
;;; Note that the interrupt-enable bit in the command word controls
;;; whether or not system error recovery features are invoked.

XDSKOP (MISC-INST-ENTRY %DISK-OP)
	(CALL GAHDRA)		;Get disk-rq array, which must be temp-wired
	;; For now, no queueing, just perform request immediately
	((A-DISK-IDLE-TIME) M-ZERO)		;I use the disk
	((A-DISK-RESERVED-FOR-USER) SETO)	;I want the disk
	(CALL AWAIT-DISK)			;Wait for disk control to become available
	((VMA-START-READ) ADD M-E (A-CONSTANT (EVAL (// %DISK-RQ-COMMAND 2))))
	(CHECK-PAGE-READ)			;Copy user's commands into A-memory
	((A-DISK-COMMAND) MD)
	((A-DISK-READ-WRITE) (BYTE-FIELD 4 0) MD)	;For error recovery
	((VMA-START-READ) ADD VMA (A-CONSTANT 1))	;CLP
	(CHECK-PAGE-READ)
	((A-DISK-CLP) MD)
	((VMA-START-READ) ADD VMA (A-CONSTANT 1))	;Address
	(CHECK-PAGE-READ)
	((A-DISK-ADDRESS) MD)
	((A-DISK-RETRY-STATE) M-ZERO)
	((A-DISK-DOING-READ-COMPARE) M-ZERO)
	(CALL-XCT-NEXT START-DISK-OP-2)		;Fire it up
       ((MD M-1) A-DISK-COMMAND)
XDSKOP2	((VMA-START-READ) A-DISK-REGS-BASE)	;Await controller ready
	(CHECK-PAGE-READ)
	(JUMP-IF-BIT-CLEAR (LISP-BYTE %%DISK-STATUS-LOW-READY) MD XDSKOP2)
	(CALL-IF-BIT-SET (BYTE-FIELD 1 11.) M-1 AWAIT-DISK)	;Await retry if enabled
	(CALL-IF-BIT-CLEAR (BYTE-FIELD 1 11.) M-1 DISK-COMPLETION-GET-STATUS) ;Get status
					;into A-MEM if havent already. 
	(CALL-IF-BIT-CLEAR (BYTE-FIELD 1 11.) M-1 DISK-COMPLETION-OK)	;and finish up if nec.
	;Return status from A-memory.  Unfortunately not quite the same as at LOG-DISK-ERROR.
	((VMA) ADD M-E (A-CONSTANT (EVAL (// %DISK-RQ-STATUS-LOW 2))))
	((MD-START-WRITE) A-DISK-STATUS)
	(CHECK-PAGE-WRITE)
	((VMA) ADD VMA (A-CONSTANT 1))
	((MD-START-WRITE) A-DISK-MA)
	(CHECK-PAGE-WRITE)
	((VMA) ADD VMA (A-CONSTANT 1))
	((MD-START-WRITE) A-DISK-FINAL-ADDRESS)
	(CHECK-PAGE-WRITE)
	((VMA) ADD VMA (A-CONSTANT 1))
	((MD-START-WRITE) A-DISK-ECC)
	(CHECK-PAGE-WRITE)

	((MD) DPB (M-CONSTANT -1) (BYTE-FIELD 17. 15.) A-DISK-RETRY-STATE)
	((VMA-START-WRITE) ADD M-E (A-CONSTANT (EVAL (// %DISK-RQ-DONE-FLAG 2))))
	(CHECK-PAGE-WRITE)			;Set completion flag, return retry state
	(CALL-EQUAL M-ZERO A-DISK-RESERVED-FOR-USER ILLOP)	;Took a page fault??
	(POPJ-AFTER-NEXT (M-T) A-V-NIL)
       ((A-DISK-RESERVED-FOR-USER) M-ZERO)	;I'm done with it
))