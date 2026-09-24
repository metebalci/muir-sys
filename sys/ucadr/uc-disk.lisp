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

;; quux: GET-DISK-CYLINDER-BOUNDARY, which nothing called, is gone with the
;; disk's cylinders: block-disk has none.

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
	;; quux: block-disk's disk address is the block number; mit's divided it
	;; into cylinder, head and block by the label's geometry.
	((A-DISK-ADDRESS) M-1)
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
	;; quux: block-disk's disk address is the block number; mit's divided it
	;; into cylinder, head and block by the label's geometry.
	((A-DISK-ADDRESS) M-1)
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
	;; quux: block-disk has no read-compare (command 10 stops by error), so
	;; A-DISK-SWITCHES' read-compare bits, 0 and 1, do nothing now.
	(JUMP-NOT-EQUAL M-A A-ZERO DISK-COMPLETION-ERROR)
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
	;; quux: block-disk's error bits: <9> no pack, <13> stopped by error,
	;; <17> past the end of the pack, <20> nxm.
	((M-A) AND MD		;Get just error status bits
		(A-CONSTANT (PLUS 1_9 1_13. 1_17. 1_20.)))
	((VMA-START-READ) ADD VMA (A-CONSTANT 1))
	(CHECK-PAGE-READ-NO-INTERRUPT)
	((A-DISK-MA) MD)
	((VMA-START-READ) ADD VMA (A-CONSTANT 1))
	(CHECK-PAGE-READ-NO-INTERRUPT)
	((A-DISK-FINAL-ADDRESS) MD)
	;; quux: block-disk has no ecc register; the cadr's was read from the
	;; start register's address.
	(POPJ-AFTER-NEXT NO-OP)
       ((A-DISK-ECC) M-ZERO)

;; quux: every error of block-disk's is final: no pack, a transfer stopped
;; by error, past the end of the pack, or nxm.  so there is nothing to retry,
;; recover with the data strobe, or recalibrate for, and the read-compare,
;; retry, recovery and recalibrate code is gone.
DISK-COMPLETION-ERROR
	((A-DISK-ERROR-COUNT) M+A+1 M-ZERO A-DISK-ERROR-COUNT)
	(CALL LOG-DISK-ERROR)
	(JUMP FATAL-DISK-ERROR)

;;; Wait for the controller to be not active.  Must NOT check for interrupts,
;;; since it may be called from interrupt level.  Called from COLD-RUN-DISK.
;;; quux: mit's disk-recalibrate-wait also waited for the drive to be on
;;; cylinder; block-disk has no cylinders.
DISK-AWAIT-READY
	((VMA-START-READ) A-DISK-REGS-BASE)
	(CHECK-PAGE-READ-NO-INTERRUPT)
	(JUMP-IF-BIT-CLEAR (BYTE-FIELD 1 0) MD DISK-AWAIT-READY) ;Wait for not active
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

;; quux: mit's soft-ecc correction, commented out, is gone: block-disk has no
;; ecc, and it knew the cadr disk's geometry.

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