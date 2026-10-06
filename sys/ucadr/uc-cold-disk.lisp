;-*-MIDAS-*-

(SETQ UC-COLD-DISK '(

;; quux revision 14 (contract g3 revision 14, 3.2; the settled readings for
;; lisp, r1): the system communication area's words for the tables.  revision
;; 14's qcom renames %sys-com-page-table-pntr and -size in place to
;; %sys-com-physical-page-data (a physical address) and
;; %sys-com-physical-page-data-size (frames, the memory found), and adds
;; %sys-com-slot-bitmap (a physical address) and %sys-com-commit-limit (pages)
;; after %sys-com-pointer-width; the next word keeps the region floor across a
;; save (%sys-com-region-floor).  the band this assembles on may have either
;; qcom, so each is taken by its new name if it has one, else by its place.
(assign-eval sys-com-physical-page-data
	(eval (if (boundp '%sys-com-physical-page-data) %sys-com-physical-page-data
		%sys-com-page-table-pntr)))
(assign-eval sys-com-physical-page-data-size
	(eval (if (boundp '%sys-com-physical-page-data-size) %sys-com-physical-page-data-size
		%sys-com-page-table-size)))
(assign-eval sys-com-slot-bitmap
	(eval (if (boundp '%sys-com-slot-bitmap) %sys-com-slot-bitmap
		(+ %sys-com-pointer-width 1))))
(assign-eval sys-com-commit-limit
	(eval (if (boundp '%sys-com-commit-limit) %sys-com-commit-limit
		(+ %sys-com-pointer-width 2))))
(assign-eval sys-com-region-floor
	(eval (if (boundp '%sys-com-region-floor) %sys-com-region-floor
		(+ %sys-com-pointer-width 3))))

;; quux revision 14: reset-machine (below) resets the devices and then sets the
;; memory system's words; the cold boot resets the devices alone, before the
;; tables exist.
;RESET-MACHINE
RESET-DEVICES
	((A-DISK-BUSY) M-ZERO)			;Forget pending disk operation
	;; quux revision 10 (contract q11): this microcode resets the devices and
	;; starts the tick on the register page, whose words 104 and 110-115 are
	;; reserved below revision 10: there it would reset no device and its tick
	;; would never start.  so check machine-id first, before any of the writes
	;; below, as initial-map-a does for revision 6 (which comes after them):
	;; the signature 50525 (0x5155) in <31:16> and a revision of 10 or more in
	;; <15:4>.  a cadr reads all ones.  otherwise halt at machine-not-quux-10.
	;; quux revision 11 (contract q13): the register page is at 17777400 from
	;; revision 11, and word 100's bits are in a new order, so this microcode
	;; asks for 11 or more and halts at machine-not-quux-11 below it: on
	;; revision 10 every register it writes would be nothing there.
	;; quux revision 13 (contract g2 2.8): microcode 2001 is for the 40-bit
	;; word, revision 13, which contains no earlier revision: below it, halt
	;; at machine-not-quux-13 (a 32-bit machine would not even assemble this
	;; microcode's words as they were meant).
	((m-tem) (byte-field 20 20) machine-id)
;	(jump-not-equal m-tem (a-constant 50525) machine-not-quux-10)
;	(jump-not-equal m-tem (a-constant 50525) machine-not-quux-11)
;	(jump-not-equal m-tem (a-constant 50525) machine-not-quux-13)
	;; quux revision 14 (appendix a14.13): microcode 2002 is for revision 14,
	;; which contains no earlier revision: below it, halt at
	;; machine-not-quux-14.
	(jump-not-equal m-tem (a-constant 50525) machine-not-quux-14)
	((m-tem) (byte-field 14 4) machine-id)
;	(jump-less-than m-tem (a-constant 10.) machine-not-quux-10)
;	(jump-less-than m-tem (a-constant 11.) machine-not-quux-11)
;	(jump-less-than m-tem (a-constant 13.) machine-not-quux-13)
	(jump-less-than m-tem (a-constant 14.) machine-not-quux-14)
	;; quux revision 10: interrupt-control <28>, the unibus reset, drives nothing
	;; on quux, so its 10-microsecond pulse is gone; the register page's reset
	;; devices takes its place (contract q11, and the q9 amendment for the file
	;; device).  it is written at every microcode start, so that a
	;; %disk-restore, which does not pass through the prom, also leaves no file
	;; device enabled to complete queued commands into memory the new band
	;; holds, and resets block-disk and the network as the pulse did.
;	((INTERRUPT-CONTROL) DPB (M-CONSTANT -1)	;Reset the bus interface and I/O devs
;		(BYTE-FIELD 1 28.) A-ZERO)
;	((M-1) (A-CONSTANT 40))				;Generate RESET for 10 microseconds
;RST	(JUMP-NOT-EQUAL-XCT-NEXT M-1 A-ZERO RST)
;       ((M-1) SUB M-1 (A-CONSTANT 1))
	((md) (a-constant 1))
	(call-xct-next phys-mem-write)		;word 104 <0>: reset devices
       ((vma) (a-constant quux-reset-devices-physical-address))
	;; then wait for the file device to be quiet (word 161 <1>) before anything
	;; loads memory: on the boards a copy the reset overtook may still write
	;; memory until the program drops its claim.  on muir it is quiet at once,
	;; one read.  the bound is 2 seconds, the driver's own (sys: io; fdev), until
	;; muir-fpga measures the longest a disable keeps quiet low; past it, halt at
	;; file-device-not-quiet rather than load a band under a copy in flight.
	((m-1) microsecond-clock)
reset-machine-quiet
	(call-xct-next phys-mem-read)
       ((vma) (a-constant quux-file-device-status-physical-address))
	(jump-if-bit-set (byte-field 1 1) md reset-machine-quiet-done)
	((m-tem) microsecond-clock)
	((m-tem) sub m-tem a-1)
	(jump-less-than m-tem (a-constant 2000000.) reset-machine-quiet)
	(jump file-device-not-quiet)
reset-machine-quiet-done
	((INTERRUPT-CONTROL) DPB (M-CONSTANT -1)	;Clear RESET, set halfword-mode,
;; quux revision 13 (appendix a1.6): lc's and interrupt-control's flags moved
;; up by 8: sequence.break is bit 34, int.enable bit 35.
;		(BYTE-FIELD 1 27.) A-ZERO)		;and enable interrupts
		(byte-field 1 35.) A-ZERO)		;and enable interrupts
	;; timer 0's period, 16,667 microseconds, 60 hz: reset devices set it to 0,
	;; and the prom's write does not reach a %disk-restore.  beg06 turns it on.
	((md) (a-constant 16667.))
	(call-xct-next phys-mem-write)		;word 111: timer 0's period
       ((vma) (a-constant quux-timer-0-period-physical-address))
	((MD) SETZ)
	(CALL-XCT-NEXT PHYS-MEM-WRITE)			;Reset bus interface status.
       ((VMA) (A-CONSTANT QUUX-ERROR-STATUS-PHYSICAL-ADDRESS)) ;quux: word 101, not 766044
	;; quux revision 12 (contract h8a), the fused return: fill the macro
	;; dispatch memory with the generic handlers and enable the
	;; macro-dispatch register, at every start of this microcode, before its
	;; first main-loop return (beg06).  the enable is off after -reset and is
	;; cleared by every control-store write, so a microcode the prom loaded, or
	;; the one a %disk-restore runs, never returns through entries another
	;; microcode left; the entries themselves are kept, so they are written
	;; again here.  every index (the halfword's <15:6>) gets opdtb's entry for
	;; its opcode, <13:9>, which is the index's <7:3>, from
	;; a-macro-dispatch-generic, with the operand bit clear: then a fused
	;; return runs the handler the main loop's dispatch would, and the machine
	;; does what it does without the fused return, two microcycles sooner.
	;; the feature page's word 17 reads 0 below revision 12, where
	;; destinations 5 to 7 write only m: skip it all there.
	(call-xct-next phys-mem-read)
       ((vma) (a-constant quux-macro-dispatch-entries-physical-address))
	(jump-equal md a-zero reset-machine-macro-dispatch-done)
	((m-c) a-zero)				;the index
reset-machine-macro-dispatch-fill
	((m-tem) (byte-field 5 3) m-c)		;the opcode
	((m-tem) add m-tem (a-constant (a-mem-loc a-macro-dispatch-generic)))
	((oa-reg-high) dpb m-tem oah-a-src a-zero)	;a source of the next
	((m-1) a-garbage)				;opdtb's entry
	((macro-dispatch-index) m-c)
	((m-c) add m-c (a-constant 1))
	(jump-less-than-xct-next m-c (a-constant 2000) reset-machine-macro-dispatch-fill)
       ((macro-dispatch-entry) m-1)
	;; the main loop, qmlp, whose word a return pops (a-main-dispatch); and
	;; a-localp's and m-ap's addresses, for the operand address (contract h8a
	;; section 3.4); with the enable, <31>.
	((macro-dispatch-register) dpb (m-constant -1) (byte-field 1 31.)
		(a-constant (plus (i-mem-loc qmlp)
				  (byte-value (byte-field 10. 14.) (a-mem-loc a-localp))
				  (byte-value (byte-field 5 24.) (m-mem-loc m-ap)))))
	;; the hardware keeps copies of a-localp and m-ap for the operand
	;; address, taken from every write of the addresses the register names
	;; and never read back from a and m memory (contract h8a section 3.4).
	;; write both once, with their own values, now that the register names
	;; them, so that the copies start equal to the memories instead of
	;; holding whatever they held before this start.
	((a-localp) a-localp)
	((m-ap) m-ap)
	;; the specialised handlers (contract h8a section 4) over the generic
	;; entries of the halfwords they serve.  no main-loop return comes before
	;; beg06, so writing them after the enable is the same as before it.  an
	;; entry's <17> is the operand bit, 400000: a fused return into it with
	;; register local (5) or arg (6) loads pdl-index with the operand's
	;; address.  it is set only on those two registers' indexes.  the index is
	;; the halfword's <15:6>: the destination <15:14>, the opcode <13:9>, the
	;; register <8:6>.
	;; move d-pdl (1) of a local or an argument: opcode 2, indexes 425 and 426.
	((macro-dispatch-index) (a-constant 425))
	((macro-dispatch-entry) (a-constant (plus (i-mem-loc qimove-pdl-operand) 400000)))
	((macro-dispatch-index) (a-constant 426))
	((macro-dispatch-entry) (a-constant (plus (i-mem-loc qimove-pdl-operand) 400000)))
	;; pop and movem into a local or an argument: destination 3, opcode 33 (pop,
	;; nd3's sub-opcode 7) and 13 (movem, sub-opcode 6); indexes 1735, 1736,
	;; 1535 and 1536.
	((macro-dispatch-index) (a-constant 1735))
	((macro-dispatch-entry) (a-constant (plus (i-mem-loc qipop-operand) 400000)))
	((macro-dispatch-index) (a-constant 1736))
	((macro-dispatch-entry) (a-constant (plus (i-mem-loc qipop-operand) 400000)))
	((macro-dispatch-index) (a-constant 1535))
	((macro-dispatch-entry) (a-constant (plus (i-mem-loc qimvm-operand) 400000)))
	((macro-dispatch-index) (a-constant 1536))
	((macro-dispatch-entry) (a-constant (plus (i-mem-loc qimvm-operand) 400000)))
	;; br, br-nil and br-not-nil: opcode 14 (br, destination 0; br-not-nil,
	;; destination 1) and 34 (br-nil, destination 0), sub-opcodes 0, 2 and 1;
	;; indexes 140, 540 and 340 plus the register field, which for a branch is
	;; the top of its offset: 0-3 forward, the -pos handlers, and 4-7 backward,
	;; the -neg ones.  the operand bit clear: a branch has no operand.
	((m-c) a-zero)				;the register field
reset-machine-macro-dispatch-branch-pos
	((macro-dispatch-index) add m-c (a-constant 140))
	((macro-dispatch-entry) (a-constant (i-mem-loc qibrn-br-pos)))
	((macro-dispatch-index) add m-c (a-constant 340))
	((macro-dispatch-entry) (a-constant (i-mem-loc qibrn-br-nil-pos)))
	((macro-dispatch-index) add m-c (a-constant 540))
	((macro-dispatch-entry) (a-constant (i-mem-loc qibrn-br-not-nil-pos)))
	((m-c) add m-c (a-constant 1))
	(jump-less-than m-c (a-constant 4) reset-machine-macro-dispatch-branch-pos)
reset-machine-macro-dispatch-branch-neg
	((macro-dispatch-index) add m-c (a-constant 140))
	((macro-dispatch-entry) (a-constant (i-mem-loc qibrn-br-neg)))
	((macro-dispatch-index) add m-c (a-constant 340))
	((macro-dispatch-entry) (a-constant (i-mem-loc qibrn-br-nil-neg)))
	((macro-dispatch-index) add m-c (a-constant 540))
	((macro-dispatch-entry) (a-constant (i-mem-loc qibrn-br-not-nil-neg)))
	((m-c) add m-c (a-constant 1))
	(jump-less-than m-c (a-constant 10) reset-machine-macro-dispatch-branch-neg)
	;; sete-1+, + and < of a local or an argument: sete-1+ is opcode 12 (nd2),
	;; sub-opcode 6, destination 3, indexes 1525 and 1526; + is opcode 31 (nd1),
	;; sub-opcode 1, destination 0, indexes 315 and 316; < is opcode 12,
	;; sub-opcode 2, destination 1, indexes 525 and 526.
	((macro-dispatch-index) (a-constant 1525))
	((macro-dispatch-entry) (a-constant (plus (i-mem-loc qisp1-operand) 400000)))
	((macro-dispatch-index) (a-constant 1526))
	((macro-dispatch-entry) (a-constant (plus (i-mem-loc qisp1-operand) 400000)))
	((macro-dispatch-index) (a-constant 315))
	((macro-dispatch-entry) (a-constant (plus (i-mem-loc qiadd-operand) 400000)))
	((macro-dispatch-index) (a-constant 316))
	((macro-dispatch-entry) (a-constant (plus (i-mem-loc qiadd-operand) 400000)))
	((macro-dispatch-index) (a-constant 525))
	((macro-dispatch-entry) (a-constant (plus (i-mem-loc qilsp-operand) 400000)))
	((macro-dispatch-index) (a-constant 526))
	((macro-dispatch-entry) (a-constant (plus (i-mem-loc qilsp-operand) 400000)))
reset-machine-macro-dispatch-done
;	;Drop into INITIAL-MAP
	(popj)					;quux revision 14: reset-devices returns

;LOADING THE INITIAL MAP.
; THE FIRST STEP IS TO ADDRESS THE SYSTEM COMMUNICATION AREA AND FIND
; OUT MUCH VIRTUAL MEMORY SHOULD BE WIRED AND STRAIGHT-MAPPED (%SYS-COM-WIRED-SIZE).
; THE MAP IS THEN SET UP FOR THOSE PAGES.  THE REMAINDER OF VIRTUAL
; SPACE IS MADE "MAP NOT SET UP."  STUFF WILL THEN BE PICKED
; UP OUT OF THE PAGE HASH TABLE.  IT IS ALSO NECESSARY TO SET UP THE
; LAST BLOCK OF LEVEL 2 MAP TO "MAP NOT SET UP (ZERO)".

;INITIAL-MAP
;	(CALL-XCT-NEXT PHYS-MEM-READ)		;ADDRESS SYSTEM COMMUNICATION AREA
;       ((VMA) (A-CONSTANT (PLUS 400 (EVAL %SYS-COM-WIRED-SIZE))))
	;; 1024-word pages (contract g2, option (w)): the system communication
	;; area is at 2000, a page of its own (appendix a1.9), not 400
;       ((vma) (a-constant (plus 2000 (eval %sys-com-wired-size))))
;	((M-A) Q-POINTER MD)			;SAVE NUMBER OF WIRED WORDS
;INITIAL-MAP-A	;Enter here with number of words to map in M-A
	;; this microcode is for quux from hardware revision 6: the 6-bit level-1
	;; entry (revision 1), the 16k-word pdl buffer (revision 2), multiply
	;; and divide in one instruction each (revision 3), the tick, its own
	;; 60-cycle clock (revision 4), and the microsecond clock and interval
	;; timer in the processor (revision 5, contract q1), and the register
	;; page and the prom at 36000 (revision 6, contract q2).  the cadr
	;; keeps mit's microcode 323.  machine-id carries the signature 50525
	;; (0x5155) in bits 31:16 on a quux, and reads all ones on a cadr; the
	;; revision is in bits 15:4, cumulative, and the processor type in 3:0.
	;; on anything else, halt at machine-not-quux-6 rather than run with a map
	;; and a pdl buffer the hardware does not have.
	;; from revision 10 (contract q11) reset-machine, which drops in here,
	;; checks for revision 10 first; this check stays at 6, as its other caller,
	;; disk-save, runs only in a machine that booted through reset-machine.
;	((m-tem) (byte-field 20 20) machine-id)
;	(jump-not-equal m-tem (a-constant 50525) machine-not-quux-6)
;	((m-tem) (byte-field 14 4) machine-id)
;	(jump-less-than m-tem (a-constant 6) machine-not-quux-6)	;revision 6: the register page
;	((a-processor-type-code) (byte-field 4 0) machine-id
;		(a-constant (byte-value q-data-type dtp-fix)))
;	((a-level-1-map-invalid) (a-constant 77))
;inimap0	;first set all level 1 map to the invalid entry, all 6 bits ones, bit 5
	;written from vma<24>
;	((vma) dpb (m-constant -1) map-write-first-level-map
;		   (a-constant (plus (byte-value map-write-enable-first-level-write 1)
;				     (byte-mask map-write-first-level-map-high))))
;	((MD) DPB (M-CONSTANT -1) (BYTE-FIELD 1 24.) A-ZERO)
;INIMAP1	((MD-WRITE-MAP) SUB MD (A-CONSTANT 20000))
;	(JUMP-NOT-EQUAL MD A-ZERO INIMAP1)
	;; the entry just written for block 0 must read back as the invalid entry
	;; machine-id promised: if the level-1 map is narrower than it says, blocks
	;; would silently alias, so halt at map-width-mismatch.  md is 0 here,
	;; addressing block 0.
;	((m-tem) map-first-level-map memory-map-data)
;	(jump-not-equal m-tem a-level-1-map-invalid map-width-mismatch)
	;THEN ZERO LAST BLOCK OF LEVEL 2 MAP (the invalid block, 37 or 77, which
	;md's level-1 entry, just set to it, points at)
;	((MD) A-ZERO)
;INIMAP2	((VMA-WRITE-MAP) DPB (M-CONSTANT -1) MAP-WRITE-ENABLE-SECOND-LEVEL-WRITE A-ZERO)
;	((MD) ADD MD (A-CONSTANT (EVAL PAGE-SIZE)))
	;; 1024-word pages (contract g2, option (w)): every map entry of the
	;; block, 256 words each, not every 1024-word page
;	((md) add md (a-constant map-entry-size))
;	(JUMP-IF-BIT-CLEAR (BYTE-FIELD 1 13.) MD INIMAP2)
	;NOW SET UP WIRED LEVEL 1 MAP
;	((MD) A-ZERO)
;	((M-C) DPB (M-CONSTANT -1) MAP-WRITE-ENABLE-FIRST-LEVEL-WRITE A-ZERO)
;INIMAP7	((VMA-WRITE-MAP) M-C) 
;	((MD) ADD MD (A-CONSTANT 20000))
;	(JUMP-LESS-THAN-XCT-NEXT MD A-A INIMAP7)
;       ((M-C) ADD M-C (A-CONSTANT (BYTE-VALUE MAP-WRITE-FIRST-LEVEL-MAP 1)))
	;; only the low 5 bits of the entry are counted here, which holds while
	;; fewer than 37 blocks (248k words) are wired.
;	((A-SECOND-LEVEL-MAP-REUSE-POINTER-INIT) 
;		MAP-WRITE-FIRST-LEVEL-MAP M-C)	;FIRST NON-WIRED
	;THEN SET UP WIRED LEVEL 2 MAP
;	((MD) SETZ)
;INIMAP3	((VMA-WRITE-MAP) VMA-PHYS-PAGE-ADDR-PART MD	;SELF-ADDRESS
;		(A-CONSTANT (PLUS (BYTE-VALUE MAP-ACCESS-CODE 3)   ;RW
;				  ;(BYTE-VALUE MAP-STATUS-CODE 0)  ;4 READ/WRITE
;				  (BYTE-VALUE MAP-META-BITS 64) ;NOT OLD, NOT EXTRA-PDL, STRUC
;				  (BYTE-VALUE MAP-WRITE-ENABLE-SECOND-LEVEL-WRITE 1))))
;	((MD) ADD MD (A-CONSTANT (EVAL PAGE-SIZE)))			;NEXT PAGE
	;; 1024-word pages (contract g2, option (w)): wire every map entry of the
	;; wired words, 256 words each, to itself; a step of a 1024-word page
	;; would map one entry in four and leave holes
;inimap3	((vma-write-map) vma-phys-map-entry-part md	;self-address
;		(a-constant (plus (byte-value map-access-code 3)   ;rw
				  ;(byte-value map-status-code 0)  ;4 read/write
;				  (byte-value map-meta-bits 64) ;not old, not extra-pdl, struc
;				  (byte-value map-write-enable-second-level-write 1))))
;	((md) add md (a-constant map-entry-size))		;next map entry
;	(JUMP-LESS-THAN MD A-A INIMAP3)		;LOOP UNTIL DONE ALL WIRED ADDRESSES
;INIM3A	((M-1) (BYTE-FIELD 5 8) MD)		;IF NOT AT EVEN 1ST LVL MAP BOUNDARY...
;	(JUMP-EQUAL M-1 A-ZERO INIM3B)		; INITIALIZE REST OF 2ND LVL BLOCK TO
;	((VMA-WRITE-MAP)			; MAP NOT SET UP.
;	   (A-CONSTANT (BYTE-VALUE MAP-WRITE-ENABLE-SECOND-LEVEL-WRITE 1)))
;	(JUMP-XCT-NEXT INIM3A)
;       ((MD) ADD MD (A-CONSTANT (EVAL PAGE-SIZE)))
;       ((md) add md (a-constant map-entry-size))	;the next map entry, not page

;INIM3B						;INITIALIZE REVERSE 1ST LVL MAP
;	((A-SECOND-LEVEL-MAP-REUSE-POINTER) A-SECOND-LEVEL-MAP-REUSE-POINTER-INIT)
					;reverse 1st lvl map locs 240-337:
					;quux's 64 entries do not fit in 40-77
;	((WRITE-MEMORY-DATA) M-ZERO)	;VALUE TO GO IN WIRED ENTRIES
;	((vma) (a-constant 637))	;a-v-system-communication-area is 400
	;; 1024-word pages (contract g2, option (w)): the system communication
	;; area is at 2000 (appendix a1.9), its offsets kept: 2240-2337
;	((vma) (a-constant 2237))	;a-v-system-communication-area is 2000
;INIMAP5	((VMA-START-WRITE) ADD VMA (A-CONSTANT 1))
;	(ILLOP-IF-PAGE-FAULT)
;	((WRITE-MEMORY-DATA) ADD WRITE-MEMORY-DATA (A-CONSTANT 20000))
;	(JUMP-LESS-THAN WRITE-MEMORY-DATA A-A INIMAP6)	;JUMP IF STILL WIRED
;	((M-A WRITE-MEMORY-DATA) (M-CONSTANT -1))	;REST OF ENTRYS ARE -1.
;INIMAP6	(jump-less-than vma (a-constant 737) inimap5)	;64 entries, to 737
;inimap6	(jump-less-than vma (a-constant 2337) inimap5)	;64 entries, to 2337
;; quux revision 13 (appendix a1.7): the level-1 map has 8,192 entries of 7
;; bits, indexed by vma<27:15>, each a block of 32 level-2 entries of a
;; 1024-word page; the invalid block is 177.  the level-1 entry is written
;; whole from vma<38:32>, which arithmetic does not reach (the alu's
;; arithmetic acts on <31:0>, g2 2.2), so the wired blocks' entries are made by
;; dpb of a count kept apart.  the reverse level-1 map has 128 entries, at the
;; system communication area's offsets 400-577 (a1.8).
;	((a-level-1-map-invalid) (a-constant 177))
;inimap0	;first set all level 1 map to the invalid entry, all 7 bits ones
;	((vma) dpb (m-constant -1) map-write-first-level-map
;		   (a-constant (byte-value map-write-enable-first-level-write 1)))
;	((md) dpb (m-constant -1) (byte-field 1 28.) a-zero)	;the top of the 28-bit space
;inimap1	((md-write-map) sub md (a-constant 100000))	;a level-1 entry is 32k words
;	(jump-not-equal md a-zero inimap1)
	;; the entry just written for block 0 must read back as the invalid entry
	;; machine-id promised: if the level-1 map is narrower than it says, blocks
	;; would silently alias, so halt at map-width-mismatch.  md is 0 here,
	;; addressing block 0.
;	((m-tem) map-first-level-map memory-map-data)
;	(jump-not-equal m-tem a-level-1-map-invalid map-width-mismatch)
	;then zero last block of level 2 map (the invalid block, 177, which
	;md's level-1 entry, just set to it, points at): its 32 pages
;	((md) a-zero)
;inimap2	((vma-write-map) dpb (m-constant -1) map-write-enable-second-level-write a-zero)
;	((md) add md (a-constant (eval page-size)))
;	(jump-if-bit-clear (byte-field 1 15.) md inimap2)
	;now set up wired level 1 map: block k for the k-th 32k words
;	((md) a-zero)
;	((m-1) a-zero)					;the block
;inimap7	((vma-write-map) dpb m-1 map-write-first-level-map
;		(a-constant (byte-value map-write-enable-first-level-write 1)))
;	((md) add md (a-constant 100000))
;	(jump-less-than-xct-next md a-a inimap7)
;       ((m-1) add m-1 (a-constant 1))
;	((a-second-level-map-reuse-pointer-init) m-1)	;first non-wired
	;then set up wired level 2 map, a page an entry
;	((md) setz)
;inimap3	((vma-write-map) vma-phys-map-entry-part md	;self-address
;		(a-constant (plus (byte-value map-access-code 3)   ;rw
				  ;(byte-value map-status-code 0)  ;4 read/write
;				  (byte-value map-meta-bits 64) ;not old, not extra-pdl, struc
;				  (byte-value map-write-enable-second-level-write 1))))
;	((md) add md (a-constant (eval page-size)))		;next page
;	(jump-less-than md a-a inimap3)		;loop until done all wired addresses
;inim3a	((m-1) (byte-field 5 10.) md)		;if not at even 1st lvl map boundary...
;	(jump-equal m-1 a-zero inim3b)		; initialize rest of 2nd lvl block to
;	((vma-write-map)			; map not set up.
;	   (a-constant (byte-value map-write-enable-second-level-write 1)))
;	(jump-xct-next inim3a)
;       ((md) add md (a-constant (eval page-size)))

;inim3b						;initialize reverse 1st lvl map
;	((a-second-level-map-reuse-pointer) a-second-level-map-reuse-pointer-init)
;	((write-memory-data) m-zero)	;value to go in wired entries
;	((vma) (a-constant 2377))	;a-v-system-communication-area is 2000: 2400-2577
;inimap5	((vma-start-write) add vma (a-constant 1))
;	(illop-if-page-fault)
;	((write-memory-data) add write-memory-data (a-constant 100000))
;	(jump-less-than write-memory-data a-a inimap6)	;jump if still wired
;	((m-a write-memory-data) (m-constant -1))	;rest of entrys are -1.
;inimap6	(jump-less-than vma (a-constant 2577) inimap5)	;128 entries, to 2577
;	(POPJ)

;; quux revision 14 (contract g3 revision 14, 9.5; appendix a14.9): no map to
;; load.  every start of this microcode resets the devices (reset-devices,
;; above) and then sets the memory system's words, which -reset clears:
;; register-page word 220, the directory's first frame, before any paged
;; reference, and words 222 and 223, the pointer-type register, before any
;; dispatch can meet oldspace (a band saved mid-collection holds some); and
;; empties the tlb, which -reset swept but a %disk-restore or a reboot without
;; -reset did not.  the cold boot makes the tables (build-tables) before it
;; comes here; a warm boot, whose a memory the prom loaded afresh, finds the
;; ones the cold boot left (warm-tables).
RESET-MACHINE
	(CALL RESET-DEVICES)
INITIAL-MAP
	((a-processor-type-code) (byte-field 4 0) machine-id
		(a-constant (byte-value q-data-type dtp-fix)))
	((m-tem) a-directory-window)
	(call-equal m-tem a-zero warm-tables)
	((m-tem) a-directory-window)
	((md) vma-phys-page-addr-part m-tem)	;the directory's first frame
	(call-xct-next phys-mem-write)
       ((vma) (a-constant quux-directory-base-physical-address))	;word 220
	((md) (a-constant pointer-type-register-0-31))	;a14.5's types (the assembler's set)
	(call-xct-next phys-mem-write)
       ((vma) (a-constant quux-pointer-types-0-31-physical-address))	;word 222
	((md) (a-constant pointer-type-register-32-63))
	(call-xct-next phys-mem-write)
       ((vma) (a-constant quux-pointer-types-32-63-physical-address))	;word 223
	((md) a-zero)				;not a window's address
	((vma-write-map) (a-constant write-map-empty))
	((vma) a-v-nil)
	(popj)

;; warm-tables: a warm boot (the prom, then beg0000 with no restore) keeps main
;; memory, so the tables the cold boot took are there: physical-page-data and
;; the slot bitmap at the physical addresses the system communication area
;; holds, the directory in the last four frames of the memory it covers, the
;; page-table pages below the bitmap, wired, page 0.  their a-memory
;; variables are set again from those.
WARM-TABLES
	(call-xct-next phys-mem-read)
       ((vma) (a-constant (plus 2000 sys-com-physical-page-data-size)))
	((m-tem) q-pointer md)
	((a-memory-frames) m-tem)
	((m-tem) sub m-tem (a-constant 4))	;the directory
	((m-tem) dpb m-tem vma-phys-page-addr-part a-zero)
	((a-directory-window) dpb (m-constant -1) physical-memory-window-bits a-tem)
	(call-xct-next phys-mem-read)
       ((vma) (a-constant (plus 2000 sys-com-physical-page-data)))
	((m-tem) q-pointer md)
	((a-ppd-window) dpb (m-constant -1) physical-memory-window-bits a-tem)
	(call-xct-next phys-mem-read)
       ((vma) (a-constant (plus 2000 sys-com-slot-bitmap)))
	((m-tem) q-pointer md)
	((a-slot-bitmap-window) dpb (m-constant -1) physical-memory-window-bits a-tem)
	((m-tem) vma-phys-page-addr-part m-tem)
	((a-tables-frame) m-tem)
	(call-xct-next phys-mem-read)
       ((vma) (a-constant (plus 2000 sys-com-commit-limit)))
	((m-tem) q-pointer md)
	((a-commit-limit) m-tem)
	(call-xct-next phys-mem-read)
       ((vma) (a-constant (eval (+ 2000 %sys-com-wired-size))))
	((m-tem) vma-page-addr-part md)
	((a-wired-frames) m-tem)
	((a-findcore-scan-pointer) m-tem)
	((a-aging-scan-pointer) m-tem)
	((a-slot-hint) a-zero)
	;; the page-table pages: the wired page-0 frames below the tables
	((m-1) a-tables-frame)
warm-tables-1
	((m-tem) sub m-1 (a-constant 1))
	((m-tem) dpb m-tem (byte-field 31. 1) a-zero)
	((vma-start-read) add m-tem a-ppd-window)
	(illop-if-page-fault)
	((m-tem) q-pointer md)
	(jump-not-equal m-tem (a-constant (byte-value ppd-wired-bit 1)) warm-tables-2)
	(jump-xct-next warm-tables-1)
       ((m-1) sub m-1 (a-constant 1))
warm-tables-2
	(popj-after-next (a-table-page-frame) m-1)
       ((vma) a-v-nil)

;; machine-not-quux-14: reset-devices comes here when machine-id is not quux's
;; revision 14 or later (contract g3 revision 14, appendix a14.13): microcode
;; 2002 needs the page table, the tlb and the windows, and below revision 14
;; every reference would go through a map it never loads.  the halt shows this
;; location.
machine-not-quux-14
	(call illop)

;; prom-entry-read: the prom's entry (prom, uc-cadr) calls this for its first
;; read, of the keyboard's status through the device window, with the address
;; in vma: machine-id is checked first, as reset-devices checks it, and below
;; revision 14 the machine halts at machine-not-quux-14 (appendix a14.13)
;; rather than fault on a window the machine does not have.  then the read,
;; phys-mem-read's.  clobbers m-tem.
prom-entry-read
	((m-tem) (byte-field 20 20) machine-id)
	(jump-not-equal m-tem (a-constant 50525) machine-not-quux-14)
	((m-tem) (byte-field 14 4) machine-id)
	(jump-less-than m-tem (a-constant 14.) machine-not-quux-14)
	(jump phys-mem-read)

;; band-not-revision-14: disk-restore-1 comes here when the band is revision
;; 13's, format 2000, 2001 or 2002 (appendix a14.13): its fixed areas are
;; where revision 13's cold load put them, the page table and
;; physical-page-data areas among them, which this microcode does not have.
;; the halt shows this location.
band-not-revision-14
	(call illop)

;; initial-map-a comes here when the level-1 map is narrower than machine-id
;; says.  the halt shows this location.
map-width-mismatch
	(call illop)

;; initial-map-a comes here when machine-id is not quux's from revision 6 on,
;; a cadr's all ones included.  the halt shows this location.
machine-not-quux-6
	(call illop)

;; reset-machine comes here when machine-id is not quux's from revision 10 on
;; (contract q11), a cadr's all ones included, before it writes the register
;; page.  the halt shows this location.
;; quux (contract q13): from revision 11 on, and so named machine-not-quux-11.
;machine-not-quux-10
;machine-not-quux-11
;; quux revision 13 (contract g2 2.8): from revision 13 on, and so named
;; machine-not-quux-13.
machine-not-quux-13
	(call illop)

;; reset-machine comes here when the file device is not quiet 2 seconds after
;; reset devices: a copy still in flight would write memory the band is about
;; to hold.  on a board, the file device's program holding its claim (busy)
;; does this; its restart lets the claim go.  the halt shows this location.
file-device-not-quiet
	(call illop)

;; disk-restore-1 comes here when the band is not one of 1024-word pages
;; (contract g2, option (w)): its format is not 1100, 1101 or 1102, as a band
;; of 256-word pages's is not.  the halt shows this location.
;band-not-1024-word-pages
;	(call illop)
;; quux revision 13 (contract g2 2.8; appendix a1.12): disk-restore-1 comes
;; here when the band's format is not a 40-bit band's, the fixnum 2000 or 2002:
;; a band of revision 12 among others.  the halt shows this location.
band-not-40-bit
	(call illop)

;PHYSICAL MEMORY REFERENCING.
;THIS WORKS BY TEMPORARILY CLOBBERING LOCATION 0 OF THE SECOND-LEVEL MAP.
;A-TEM1, A-TEM2, AND A-TEM3 ARE USED AS TEMPORARIES.  ARGS ARE IN VMA AND MD.
;PHYS-MEM-READ 
;	((A-TEM1) VMA)				;SAVE ADDRESS
;	((MD) A-ZERO)				;ADDRESS MAP LOCATION 0@2
;	((A-TEM3) MAP-WRITE-SECOND-LEVEL-MAP	;SAVE IT (READ & WRITE THE SAME)
;		  MEMORY-MAP-DATA
;		  (A-CONSTANT (BYTE-VALUE MAP-WRITE-ENABLE-SECOND-LEVEL-WRITE 1)))
;	((VMA-WRITE-MAP) VMA-PHYS-PAGE-ADDR-PART VMA
;		(A-CONSTANT (PLUS (BYTE-VALUE MAP-WRITE-ENABLE-SECOND-LEVEL-WRITE 1)
;				  (BYTE-VALUE MAP-ACCESS-CODE 3))))
	;; 1024-word pages (contract g2, option (w)): map entry 0 to the 256
	;; words holding the address, a map entry's physical page
;	((vma-write-map) vma-phys-map-entry-part vma
;		(a-constant (plus (byte-value map-write-enable-second-level-write 1)
;				  (byte-value map-access-code 3))))
;	((VMA-START-READ) DPB M-ZERO		;READ, USING LOC WITHIN PAGE ZERO
;		ALL-BUT-VMA-LOW-BITS A-TEM1)
;	(ILLOP-IF-PAGE-FAULT)			;FOO, I JUST SET UP THE MAP
;	((A-TEM2) READ-MEMORY-DATA)		;GET RESULT TO BE RETURNED
;	((MD) A-ZERO)				;RESTORE THE MAP
;	((VMA-WRITE-MAP) A-TEM3)
;	(POPJ-AFTER-NEXT (VMA) A-TEM1)		;RETURN CORRECT VALUES IN VMA AND MD
;       ((MD) A-TEM2)

;PHYS-MEM-WRITE 
;	((A-TEM1) VMA)				;SAVE ADDRESS
;	((A-TEM2) MD)				;AND DATA
;	((MD) A-ZERO)				;ADDRESS MAP LOCATION 0@2
;	((A-TEM3) MAP-WRITE-SECOND-LEVEL-MAP	;SAVE IT (READ & WRITE THE SAME)
;		  MEMORY-MAP-DATA
;		  (A-CONSTANT (BYTE-VALUE MAP-WRITE-ENABLE-SECOND-LEVEL-WRITE 1)))
;	((VMA-WRITE-MAP) VMA-PHYS-PAGE-ADDR-PART VMA
;		(A-CONSTANT (PLUS (BYTE-VALUE MAP-WRITE-ENABLE-SECOND-LEVEL-WRITE 1)
;				  (BYTE-VALUE MAP-ACCESS-CODE 3))))
	;; 1024-word pages (contract g2, option (w)): map entry 0 to the 256
	;; words holding the address, a map entry's physical page
;	((vma-write-map) vma-phys-map-entry-part vma
;		(a-constant (plus (byte-value map-write-enable-second-level-write 1)
;				  (byte-value map-access-code 3))))
;	((MD) A-TEM2)				;RESTORE THE DATA TO BE WRITTEN
;	((VMA-START-WRITE) DPB M-ZERO		;WRITE, USING LOC WITHIN PAGE ZERO
;		ALL-BUT-VMA-LOW-BITS A-TEM1)
;	(ILLOP-IF-PAGE-FAULT)			;FOO, I JUST SET UP THE MAP
;	((MD) A-ZERO)				;RESTORE THE MAP
;	((VMA-WRITE-MAP) A-TEM3)
;	(POPJ-AFTER-NEXT (VMA) A-TEM1)		;RETURN CORRECT VALUES IN VMA AND MD
;       ((MD) A-TEM2)

;; quux revision 14 (contract g3 revision 14, 2; appendix a14.1): physical
;; memory is reached through the physical memory window, 36000000000 plus the
;; physical address, untranslated, and the register page is in the device
;; window, untranslated too, so no map entry is borrowed.  vma is a physical
;; address of main memory, or a window's address (vma<31:29> 111), taken as it
;; is: the register page's words, which have no physical address in main
;; memory's space.  vma and md are returned as they came; a-tem1 and a-tem2
;; and m-tem are clobbered.
PHYS-MEM-READ
	((a-tem1) vma)				;save address
	((m-tem) vma-window-bits vma)
	(jump-equal m-tem (a-constant 7) phys-mem-read-1)
	((vma-start-read) dpb (m-constant -1) physical-memory-window-bits a-tem1)
	(jump phys-mem-read-2)
phys-mem-read-1
	((vma-start-read) a-tem1)
phys-mem-read-2
	(illop-if-page-fault)			;a window never faults (but a memory's)
	((a-tem2) read-memory-data)		;get result to be returned
	(popj-after-next (vma) a-tem1)		;return correct values in vma and md
       ((md) a-tem2)

PHYS-MEM-WRITE
	((a-tem1) vma)				;save address
	((a-tem2) md)				;and data
	((m-tem) vma-window-bits vma)
	(jump-equal m-tem (a-constant 7) phys-mem-write-1)
	((vma) dpb (m-constant -1) physical-memory-window-bits a-tem1)
phys-mem-write-1
	((md) a-tem2)				;the data, the microcycle before the start
	((vma-start-write) vma)
	(illop-if-page-fault)
	(popj-after-next (vma) a-tem1)		;return correct values in vma and md
       ((md) a-tem2)

;;; COLD BOOT, %DISK-RESTORE and %DISK-SAVE code

;(%DISK-SAVE main-memory-size high-16-bits-of-partition-name low-16-bits)
;The second and third arguments may be zero to specify the current partition.
;The first arg may also be minus the main-memory-size, to dump an incremental band.
DISK-SAVE (MISC-INST-ENTRY %DISK-SAVE)
;	((M-4) PDL-POP)
	;; quux revision 13 (appendix a1.11, rule 5): the band's name is compared
	;; with m-3, which is built by ldb from the gpt and so untagged: take the
	;; argument's field, not its tag and cdr code.
	((m-4) q-pointer pdl-pop)
	((M-4) DPB PDL-POP (BYTE-FIELD 20 20) A-4)
	((M-S) Q-POINTER PDL-TOP)
;	((MD) (A-CONSTANT 1000))    ;store code so this band known to be in compressed format
	;; 1024-word pages (contract g2, option (w); appendix a1.12): a band of
	;; 1024-word pages on revision 12 is 1100 compressed, 1101 incremental and
	;; 1102 a cold load, so that no microcode takes it for a band of 256-word
	;; pages (1000, 1001), or the other way round
;	((md) (a-constant 1100))    ;store code so this band known to be in compressed format
	;; quux revision 13 (appendix a1.12): a saved 40-bit band is 2000, stored
	;; as a fixnum, and an incremental one 2001 (disk-save-incremental, 5-block
	;; pages); the sum keeps md's fixnum tag.
;	((md) (a-constant (plus (byte-value q-data-type dtp-fix) 2000)))
	;; quux revision 14 (appendix a14.13): 2010 saved, 2011 incremental
	((md) (a-constant band-format-saved))
	(JUMP-IF-BIT-CLEAR BOXED-SIGN-BIT M-S DISK-SAVE-1)
;	(jump incremental-band-not-supported)
	((MD) ADD MD (A-CONSTANT 1))	;or incremental format, whichever it is
	((M-S) SUB M-ZERO A-S)
	((M-S) Q-POINTER M-S)
DISK-SAVE-1
;	((VMA-START-WRITE) (A-CONSTANT (EVAL (+ 400 %SYS-COM-BAND-FORMAT))))  ;before swapout
	((vma-start-write) (a-constant (eval (+ 2000 %sys-com-band-format))))  ;before swapout
	(ILLOP-IF-PAGE-FAULT)			; so it gets to saved image on disk
	;; quux revision 14 (contract g3 revision 14, 10.11): the region floor goes
	;; with the band, so that a band saved with it set keeps placing regions
	;; there after its boot (beg0000 takes it back).
	((md) a-region-floor)
	((vma-start-write) (a-constant (plus 2000 sys-com-region-floor)))
	(illop-if-page-fault)
	(CALL SWAP-OUT-ALL-PAGES)		;Make sure disk has valid data for all pages.
	;; quux (contract q8): read the gpt into the copy buffer, which the copy
	;; overwrites anyway, so no page of memory is saved around it (mit saved
	;; pages 0-2 on blocks 1, 3 and 5, which now hold gpt entries).
	((a-gpt-buffer-page) (a-constant copy-buffer-page-origin))
	((a-gpt-ccw) (a-constant copy-buffer-ccw-origin))
	(call cold-read-gpt)			;Find the specified partition, and PAGE.
;Set up args for DISK-SAVE-REGIONWISE in case we go straight there.,
	((M-K) A-ZERO)
	((M-AP) M-ZERO)			;region to hack.
	((M-Q) M-I)
	(JUMP-IF-BIT-CLEAR BOXED-SIGN-BIT PDL-POP DISK-SAVE-REGIONWISE)

;; quux revision 13: incremental bands were not converted to 5-block pages;
;; %disk-save of an incremental band and %disk-restore of one (format 2001)
;; halted at incremental-band-not-supported.  they are now: the band's pages
;; are 5 blocks, packed, as a whole band's, and the bitmap has a bit a page
;; (the inc-band- constants, io1; inc).
;incremental-band-not-supported
;	(call illop)

DISK-SAVE-INCREMENTAL
	((M-B) (A-CONSTANT INC-BAND-BITMAP-BUFFER-PAGE-ORIGIN))
	((M-1) ADD M-I (A-CONSTANT INC-BAND-BASE-DATA-PAGE))
	(CALL COLD-DISK-READ-1)
;Read length in bits of page bit table of this incremental band.
	(CALL-XCT-NEXT PHYS-MEM-READ)
       ((VMA) (A-CONSTANT (PLUS INC-BAND-BITMAP-BUFFER-ORIGIN INC-BAND-BITMAP-SIZE-INDEX)))
;	((M-K) MD)
	((m-k) q-pointer md)		;quux revision 13: the count, without lisp's tag
;Get number of pages the bit map occupies.
;	((M-2) ADD M-K (A-CONSTANT (EVAL (PLUS (TIMES PAGE-SIZE 32.) -1))))
	;; 1024-word pages (contract g2, option (w)): blocks of 256 words, not
	;; pages: the bitmap has a bit a block, and is read and skipped by blocks
;	((m-2) add m-k (a-constant (eval (plus (times 400 32.) -1))))
;	((M-2) LDB (BYTE-FIELD 13 15) M-2)
	;; quux revision 13: a bit a page again, 32 bits a word, 32768 a page
	((m-2) add m-k (a-constant (eval (plus (times page-size 32.) -1))))
	((m-2) ldb (byte-field 13 17) m-2)
	((M-R) M-2)
;Read in the bit map.
	((M-1) ADD M-I (A-CONSTANT INC-BAND-BITMAP-PAGE))
	((M-B) (A-CONSTANT INC-BAND-BITMAP-BUFFER-PAGE-ORIGIN))
	((M-C) (A-CONSTANT COPY-BUFFER-CCW-ORIGIN))
	(CALL COLD-DISK-READ)
;Save the first three pages into the band.
	((M-1) M-I)
;	((M-2) (A-CONSTANT 3))
;	((m-2) (a-constant low-pages-blocks))	;1024-word pages: 3 pages, 14 blocks
	((m-2) (a-constant low-pages))		;quux revision 13: 3 pages
	((M-B) A-ZERO)
	((M-C) (A-CONSTANT COPY-BUFFER-CCW-ORIGIN))
	(CALL COLD-DISK-WRITE)
;Now save the remaining regions regionwise
;starting after the bitmap pages.
;	((M-Q) ADD M-I (A-CONSTANT INC-BAND-BITMAP-PAGE))
;	((M-Q) ADD M-Q A-R)
	;; quux revision 13: m-q a block, the bitmap's m-r pages 5 blocks each
	((m-tem) dpb m-r (byte-field 30. 2) a-zero)
	((m-tem) add m-tem a-r)
	((m-q) add m-i a-tem)
	((m-q) add m-q (a-constant inc-band-bitmap-page))
	((M-AP) (A-CONSTANT 3))			;region to hack.
DISK-SAVE-REGIONWISE
	(CALL DISK-SAVE-REGIONWISE-SUBR)
	(JUMP COLD-SWAP-IN)			;Physical core now clobbered, so re-swap-in.

;M-I and M-J have origin and size of band to dump into.
;M-Q has disk address, within band, to start writing at,
; and M-AP has region number of first region to dump.
;M-S has size of phys memory in words.
;M-K has size of page bitmap in bits.
;This bitmap starts at INC-BAND-BITMAP-BUFFER-ORIGIN
;and a 1 in the bitmap means omit the page.
;If M-K contains 0, save all pages.
;A-V-REGION-ORGIN, -FREE-POINTER, and -BITS
;re valid, and those arrays are still in main memory and wont get clobbered by calling
;DISK-COPY-SECTION.
;DISK-SAVE-REGIONWISE-SUBR
;	((A-COPY-BAND-TEM) ADD M-I A-J) ;better not try to write above here.
;	((A-COPY-BAND-TEM1) M-I)	;Starting track for dest. band. 
;DISK-SR-1
;	((VMA-START-READ) ADD M-AP A-V-REGION-BITS)
;	(ILLOP-IF-PAGE-FAULT)
;	((M-TEM) LDB (LISP-BYTE %%REGION-SPACE-TYPE) MD)
;	(JUMP-EQUAL M-TEM A-ZERO DISK-SR-2)	;free region, forget it.
;	((VMA-START-READ) ADD M-AP A-V-REGION-ORIGIN)
;	(ILLOP-IF-PAGE-FAULT)
;	((M-I) LDB VMA-PAGE-ADDR-PART MD)
	;; 1024-word pages (contract g2, option (w)): the disk counts 256-word
	;; blocks; a region starts on a page, and is saved to the end of the page
	;; its free pointer is in, as with 256-word pages, four blocks a page
;	((m-i) ldb vma-block-part md)
;	((M-I) ADD M-I A-DISK-OFFSET)
;	((VMA-START-READ) ADD M-AP A-V-REGION-FREE-POINTER)
;	(ILLOP-IF-PAGE-FAULT)
;	((MD) ADD MD (A-CONSTANT 377))
;	((M-J) LDB VMA-PAGE-ADDR-PART MD)
;	((md) add md (a-constant 1777))
;	((m-j) ldb vma-page-addr-part md)
;	((m-j) dpb m-j (byte-field 16. 2) a-zero)	;its pages' blocks
;	((M-TEM) ADD M-Q A-J)
;	(CALL-GREATER-OR-EQUAL M-TEM A-COPY-BAND-TEM BAND-NOT-BIG-ENOUGH)
;	((M-TEM) ADD M-I A-J)
;	((M-TEM) SUB M-TEM A-DISK-OFFSET)
;	(CALL-GREATER-OR-EQUAL M-TEM A-DISK-MAXIMUM ILLOP)  ;Band not within paging partition
	;; quux revision 13 (appendix a1.11): the region's first block in the
	;; paging partition is 5 times its first page; m-j counts its pages, to the
	;; end of the page its free pointer is in; disk-copy-section copies pages
	;; and advances the disk addresses 5 blocks a page.
;	((m-i) ldb vma-page-addr-part md)
;	((m-1) m-i)				;its first page, for disk-save-region
;	((m-tem) dpb m-i (byte-field 30. 2) a-zero)
;	((m-i) add m-i a-tem)			;times 5
;	((M-I) ADD M-I A-DISK-OFFSET)
;	((VMA-START-READ) ADD M-AP A-V-REGION-FREE-POINTER)
;	(ILLOP-IF-PAGE-FAULT)
;	((md) add md (a-constant 1777))
;	((m-j) ldb vma-page-addr-part md)	;its pages
;	((m-tem) dpb m-j (byte-field 30. 2) a-zero)
;	((m-tem) add m-tem a-j)			;its blocks
;	((m-tem) add m-q a-tem)
;	(call-greater-or-equal m-tem a-copy-band-tem band-not-big-enough)
;	((m-tem) dpb m-j (byte-field 30. 2) a-zero)
;	((m-tem) add m-tem a-j)
;	((m-tem) add m-i a-tem)
;	((m-tem) sub m-tem a-disk-offset)
;	(call-greater-or-equal m-tem a-disk-maximum illop)  ;band not within paging partition
;	(CALL DISK-SAVE-REGION)
;DISK-SR-2
;	((M-TEM) A-V-REGION-LENGTH)		;depend on REGION-ORIGIN and REGION-LENGTH
;	((M-TEM) SUB M-TEM A-V-REGION-ORIGIN)	; being consecutive to determine how
;	((M-AP) ADD M-AP (A-CONSTANT 1))	; many regions there are.
;	(JUMP-LESS-THAN M-AP A-TEM DISK-SR-1)
;	((M-Q) SUB M-Q A-COPY-BAND-TEM1)
;	((MD) DPB M-Q (BYTE-FIELD 30 10) A-ZERO) ;Record active size of band.
;	((VMA-START-WRITE) (A-CONSTANT (EVAL (PLUS 400 %SYS-COM-VALID-SIZE))))
;	(ILLOP-IF-PAGE-FAULT)
;	((M-B) (A-CONSTANT 1))			;Core page frame number
;	((M-1) M+A+1 M-ZERO A-COPY-BAND-TEM1)	;Disk address, second page of band.
;	((M-2) (A-CONSTANT 1))			;one page.
;	((M-C) (A-CONSTANT 777))
	;; 1024-word pages (contract g2, option (w); appendix a1.9): the system
	;; communication area is page 1, at 2000, which is block 4 of the band;
	;; its first block, which holds the valid size, is written again, with
	;; the ccw at 2377, its reserved last word
;	((vma-start-write) (a-constant (eval (plus 2000 %sys-com-valid-size))))
;	(ILLOP-IF-PAGE-FAULT)
;	((m-b) (a-constant 4))			;core block of the area, 2000
;	((m-1) a-copy-band-tem1)		;the band's first block
;	((m-1) add m-1 (a-constant 4))		;and the area's
;	((m-2) (a-constant 1))			;one block
;	((m-c) (a-constant 2377))
	;; quux revision 13: m-q is blocks, 5 a page; the valid size is words, a
	;; fixnum, of the pages written.  the system communication area is page 1,
	;; written again, whole, to the band's second page, blocks 5-9, with the
	;; ccw at 2377, its reserved word.
;	((m-1) m-q)
;	(call divide-by-blocks-per-page)	;the band's pages
;	((md) dpb m-1 vma-page-addr-part (a-constant (byte-value q-data-type dtp-fix)))
;	((vma-start-write) (a-constant (eval (plus 2000 %sys-com-valid-size))))
;	(ILLOP-IF-PAGE-FAULT)
;	((m-b) (a-constant 1))			;core page frame number
;	((m-1) a-copy-band-tem1)		;the band's first block
;	((m-1) add m-1 (a-constant blocks-per-page))	;its second page
;	((m-2) (a-constant 1))			;one page
;	((m-c) (a-constant 2377))
;	(JUMP COLD-DISK-WRITE)		;write it on the band.

;; quux revision 14 (contract g3 revision 14, 10.6; appendix a14.12): the band's
;; layout does not change, but a page is no longer at its virtual page's place
;; in the paging partition.  every page leaves memory first: the pageable
;; ones are evicted (%delete-physical-page writes each modified one to its
;; slot), and the wired ones are written to their slots, a wired page with
;; none getting one (swap-out-all-pages).  then the regions are walked, region
;; by region from region 0, each to the end of the page its free pointer is in,
;; as before, and each page is copied from its slot to the band; a page with no
;; slot (never written) is written as it would be filled fresh (czrr).  a run
;; of pages whose slots follow one another is copied in one transfer.  an
;; incremental band (m-k, the mask's length, not 0) omits each page whose mask
;; bit is 1, the mask indexed by the page's place in the walk (lisp's io1;
;; inc).  the copy's buffer stays below the tables.
DISK-SAVE-REGIONWISE-SUBR
	((A-COPY-BAND-TEM) ADD M-I A-J) ;better not try to write above here.
	((A-COPY-BAND-TEM1) M-I)	;Starting track for dest. band.
	((m-s) a-table-page-frame)	;the copy's buffer stays below the tables
	((m-s) dpb m-s vma-phys-page-addr-part a-zero)
	((a-walk-region) a-zero)
	((a-walk-index) a-zero)		;the page's place in the walk, the mask's index
	((a-run-count) a-zero)		;no run of slots yet
dsr-region
	((m-a) a-walk-region)
	((m-tem) a-v-region-length)
	((m-tem) sub m-tem a-v-region-origin)
	(jump-greater-or-equal m-a a-tem dsr-done)
	((vma-start-read) add m-a a-v-region-bits)
	(illop-if-page-fault)
	((m-tem) (lisp-byte %%region-space-type) md)
	(jump-equal m-tem a-zero dsr-next-region)	;free region, forget it.
	((vma-start-read) add m-a a-v-region-origin)
	(illop-if-page-fault)
	((m-tem) q-pointer md)
	((a-walk-va) m-tem)
	((vma-start-read) add m-a a-v-region-free-pointer)
	(illop-if-page-fault)
	((m-tem) add md (a-constant (eval (1- page-size))))
	((m-tem) vma-page-addr-part m-tem)
	((a-walk-n) m-tem)			;its pages in the band
	((a-walk-i) a-zero)
	(jump-greater-or-equal m-a a-ap dsr-page)	;from the first region to save (m-ap)
	((m-tem) a-walk-index)			;before it: only counted
	(jump-xct-next dsr-next-region)
       ((a-walk-index) add m-tem a-walk-n)
dsr-page
	((m-tem) a-walk-i)
	(jump-greater-or-equal m-tem a-walk-n dsr-next-region)
	(jump-equal m-k a-zero dsr-page-1)	;no mask
	(call-xct-next dsr-mask-bit)
       ((a-mask-k) a-walk-index)
	(jump-not-equal m-tem a-zero dsr-next-page)	;omitted
dsr-page-1
	(call-xct-next find-page-entry)		;its slot
       ((a-tem1) a-walk-va)
	((m-tem) map-status-code md)
	(jump-less-than m-tem (a-constant 2) dsr-page-out)
	((m-b) map-physical-page-number md)	;in core: a wired page, its frame's slot
	(call ppd-slot)
	(jump dsr-page-slot)
dsr-page-out
	(call entry-slot)
dsr-page-slot
	(jump-equal m-tem (a-constant page-entry-no-slot) dsr-page-fresh)
	;; a slot: add it to the run, or copy the run and start one
	((m-a) a-run-count)
	(jump-equal m-a a-zero dsr-run-start)
	((m-a) a-run-slot)
	((m-a) add m-a a-run-count)
	(jump-not-equal m-tem a-a dsr-run-new)
	((m-tem) a-run-count)
	(jump-xct-next dsr-next-page)
       ((a-run-count) add m-tem (a-constant 1))
dsr-run-new
	((c-pdl-buffer-pointer-push) m-tem)
	(call dsr-copy-run)
	((m-tem) c-pdl-buffer-pointer-pop)
dsr-run-start
	((a-run-slot) m-tem)
	(jump-xct-next dsr-next-page)
       ((a-run-count) (a-constant 1))
dsr-page-fresh					;no slot: the page as czrr fills it
	(call dsr-copy-run)
	((a-disk-swapin-page-frame) (a-constant copy-buffer-page-origin))
	(call-xct-next czrr)
       ((a-disk-swapin-virtual-address) a-walk-va)
	((m-tem) (a-constant blocks-per-page))
	((m-tem) add m-q a-tem)
	(call-greater-or-equal m-tem a-copy-band-tem band-not-big-enough)
	((m-1) m-q)
	((m-2) (a-constant 1))
	((m-b) (a-constant copy-buffer-page-origin))
	((m-c) (a-constant copy-buffer-ccw-origin))
	(call cold-disk-write)
	((m-q) add m-q (a-constant blocks-per-page))
dsr-next-page
	((m-tem) a-walk-va)
	((a-walk-va) add m-tem (a-constant (eval page-size)))
	((m-tem) a-walk-index)
	((a-walk-index) add m-tem (a-constant 1))
	((m-tem) a-walk-i)
	(jump-xct-next dsr-page)
       ((a-walk-i) add m-tem (a-constant 1))
dsr-next-region
	((m-tem) a-walk-region)
	(jump-xct-next dsr-region)
       ((a-walk-region) add m-tem (a-constant 1))
dsr-done
	(call dsr-copy-run)
	((M-Q) SUB M-Q A-COPY-BAND-TEM1)
	;; quux revision 13: m-q is blocks, 5 a page; the valid size is words, a
	;; fixnum, of the pages written.  the system communication area is page 1,
	;; written again, whole, to the band's second page, blocks 5-9, with the
	;; ccw at 2377, its reserved word.
	((m-1) m-q)
	(call divide-by-blocks-per-page)	;the band's pages
	((md) dpb m-1 vma-page-addr-part (a-constant (byte-value q-data-type dtp-fix)))
	((vma-start-write) (a-constant (eval (plus 2000 %sys-com-valid-size))))
	(ILLOP-IF-PAGE-FAULT)
	((m-b) (a-constant 1))			;core page frame number
	((m-1) a-copy-band-tem1)		;the band's first block
	((m-1) add m-1 (a-constant blocks-per-page))	;its second page
	((m-2) (a-constant 1))			;one page
	((m-c) (a-constant 2377))
	(JUMP COLD-DISK-WRITE)		;write it on the band.

;; dsr-copy-run: the run of a-run-count pages from slot a-run-slot is copied
;; to the band at m-q, which moves past it; then there is no run.
DSR-COPY-RUN
	((m-j) a-run-count)
	(popj-equal m-j a-zero)
	((m-i) a-run-slot)			;the slots' first block
	((m-tem) dpb m-i (byte-field 30. 2) a-zero)
	((m-i) add m-i a-tem)			;times 5
	((m-i) add m-i a-disk-offset)
	(call disk-save-section)		;m-q moves on
	(popj-after-next (a-run-count) a-zero)
       (no-op)

;; dsr-mask-bit: the incremental band's mask bit for the page a-mask-k, in
;; m-tem: the mask is in memory at inc-band-bitmap-buffer-origin, physical, a
;; bit a page, 32 a word, the first in a word's bit 0.
DSR-MASK-BIT
	((m-tem) a-mask-k)
	((vma) (byte-field 27. 5) m-tem)
	(call-xct-next phys-mem-read)
       ((vma) add vma (a-constant inc-band-bitmap-buffer-origin))
;	((m-tem) a-walk-index)
	;; the bit's place in its word from a-mask-k, as the word's is.  it was
	;; taken from a-walk-index, which is the page's index while
	;; disk-save-regionwise-subr saves, but its region's first page's while
	;; build-region-entries restores an incremental band (a-mask-k being that
	;; plus the page's place in its region): every page but a region's
	;; first got another page's bit, and the restored band took pages from
	;; the wrong slots.
	((m-tem) a-mask-k)
	((m-tem) (byte-field 5 0) m-tem)
	(popj-after-next (oa-reg-low) sub (m-constant 50) a-tem)
       ((m-tem) (byte-field 1 0) md)

;; quux revision 13: m-1, a count of blocks, divided by blocks-per-page, 5: a
;; page's blocks in the packed transfer.  by subtraction; only save and restore
;; call it.  clobbers m-tem.
divide-by-blocks-per-page
	((m-tem) a-zero)
divide-by-blocks-per-page-1
	(jump-less-than m-1 (a-constant blocks-per-page) divide-by-blocks-per-page-2)
	((m-1) sub m-1 (a-constant blocks-per-page))
	(jump-xct-next divide-by-blocks-per-page-1)
       ((m-tem) add m-tem (a-constant 1))
divide-by-blocks-per-page-2
	(popj-after-next (m-1) m-tem)
       (no-op)

;M-I and M-J have origin and size, on disk in the PAGE partition, of a region.
;M-Q has disk address to copy to in band being dumped.
;DISK-SAVE-REGION
;	(JUMP-EQUAL M-K A-ZERO DISK-SAVE-SECTION)
;Otherwise copy only pages which have 0 in the bitmap.
;Each page copied comes from the PAGE partition according to its page number.
;Thus, the pages not copied do take up space in PAGE.
;But only the copied pages are present in the dumped band.
;	((M-1) SUB M-I A-DISK-OFFSET)
;	((M-R) ADD M-J A-1)
;DISK-SAVE-REGION-LOOP
;;M-1 gets virt mem page number of first page to think about.
;	((M-1) SUB M-I A-DISK-OFFSET)
;	((M-2) (A-CONSTANT 0))
;;Search for next page with a 0 in the bit map.  Increment M-1 up to that page number.
;	(CALL DISK-RESTORE-BITMAP-SEARCH)
;	((M-I) ADD M-1 A-DISK-OFFSET)
;;Return now if no page found within this region.
;	(POPJ-EQUAL M-1 A-R)
;;Find next following page we should not copy.
;	((M-2) (A-CONSTANT 1))
;	(CALL DISK-RESTORE-BITMAP-SEARCH)
;;M-J gets number of consec pages to be copied.
;	((M-J) ADD M-1 A-DISK-OFFSET)
;	((M-J) SUB M-J A-I)
;;Copy them.  Updates M-Q to point at place to copy next page to,
;;and M-I to next page to think about.
;	(CALL DISK-SAVE-SECTION)
;	(JUMP DISK-SAVE-REGION-LOOP)
	;; quux revision 13: m-i is a block of the paging partition, 5 a page, and
	;; no longer the page number plus the offset, so the page numbers are kept
	;; apart: m-1 the region's first page (disk-sr-1), m-r past its last, and
	;; the next page to think about on the pdl across disk-save-section, which
	;; clobbers m-1.
;	((M-R) ADD M-J A-1)
;DISK-SAVE-REGION-LOOP
;	((M-2) (A-CONSTANT 0))
;Search for next page with a 0 in the bit map.  Increment M-1 up to that page number.
;	(CALL DISK-RESTORE-BITMAP-SEARCH)
;	((m-tem) dpb m-1 (byte-field 30. 2) a-zero)	;m-i its block
;	((m-i) add m-1 a-tem)
;	((m-i) add m-i a-disk-offset)
;Return now if no page found within this region.
;	(POPJ-EQUAL M-1 A-R)
;	((pdl-push) m-1)
;Find next following page we should not copy.
;	((M-2) (A-CONSTANT 1))
;	(CALL DISK-RESTORE-BITMAP-SEARCH)
;M-J gets number of consec pages to be copied.
;	((m-2) pdl-pop)
;	((m-j) sub m-1 a-2)
;Copy them.  Updates M-Q to point at place to copy next page to.
;	((pdl-push) m-1)
;	(CALL DISK-SAVE-SECTION)
;	((m-1) pdl-pop)
;	(JUMP DISK-SAVE-REGION-LOOP)

;; quux revision 14: disk-save-region (above) is part of
;; disk-save-regionwise-subr's walk now.

DISK-SAVE-SECTION
;	((M-TEM) ADD M-Q A-J)
	;; quux revision 13: m-j counts pages, 5 blocks each
	((m-tem) dpb m-j (byte-field 30. 2) a-zero)
	((m-tem) add m-tem a-j)
	((m-tem) add m-q a-tem)
	(CALL-GREATER-OR-EQUAL M-TEM A-COPY-BAND-TEM BAND-NOT-BIG-ENOUGH)
	(JUMP DISK-COPY-SECTION)	

BAND-NOT-BIG-ENOUGH	;Destination band not big enuf.  This should have been detected
	(CALL ILLOP)	; before now.  If you proceed this, it should swap your band
	(POPJ)		; back in.

;Make sure all pages are correct on disk.
;Requires that M-S contain the number of words of physical main memory.
;Has the side-effect of destroying the page hash table.
;For %DISK-SAVE, that doesn't matter since we just re-boot anyway.
;SWAP-OUT-ALL-PAGES
;	((C-PDL-BUFFER-POINTER-PUSH) M-S)
;	((M-S) LDB (BYTE-FIELD 16. 8) M-S A-ZERO)	;Number of physical pages.
;	((VMA-START-READ) (A-CONSTANT (PLUS 400 (EVAL %SYS-COM-WIRED-SIZE))))
;	(ILLOP-IF-PAGE-FAULT)
;	((M-T) (BYTE-FIELD 16. 8) READ-MEMORY-DATA)	;Number of wired pages.
	;; 1024-word pages (contract g2, option (w)): the physical pages are
	;; 1024-word frames, which %delete-physical-page takes; the wired words
	;; are written in 256-word blocks, the disk's unit; the system
	;; communication area is at 2000
;	((m-s) ldb vma-phys-page-addr-part m-s a-zero)	;number of physical pages.
;	((vma-start-read) (a-constant (plus 2000 (eval %sys-com-wired-size))))
;	(ILLOP-IF-PAGE-FAULT)
;	((m-t) vma-block-part read-memory-data)	;number of wired blocks.
	;; quux revision 13: the wired words are written in pages, a ccw each
;	((m-t) vma-page-addr-part read-memory-data)	;number of wired pages.
;	((C-PDL-BUFFER-POINTER-PUSH) M-T)
;	((M-T) SUB M-S (A-CONSTANT 1))		;First page to do is highest in core
;Swap out all unwired pages first, using %DELETE-PHYSICAL-PAGE and updating the PHT normally.
;SWAP-OUT-ALL-PAGES-1
;	((C-PDL-BUFFER-POINTER-PUSH) M-T)	;Save current page
;	((C-PDL-BUFFER-POINTER-PUSH) DPB M-T VMA-PAGE-ADDR-PART A-ZERO)  ;arg
;	(CALL XDPPG)
;	((M-T) SUB C-PDL-BUFFER-POINTER-POP (A-CONSTANT 1))
;	(JUMP-GREATER-OR-EQUAL M-T A-ZERO SWAP-OUT-ALL-PAGES-1)
;Now swap out all the wired pages
;	((M-A) (A-CONSTANT 200000))		;Direct-map the first 64K
	;; quux revision 13: the wired words and the ccw list above them, as at
	;; disk-restore-1
;	((m-a) (a-constant 1000000))		;direct-map the first 256k
;	(CALL INITIAL-MAP-A)
;	((M-1) A-DISK-OFFSET)			;Disk address of virtual location 0
;	((M-2) C-PDL-BUFFER-POINTER-POP)	;Number of wired pages
;	((M-B) M-ZERO)				;Physical memory location 0
;	((M-C) DPB M-2 VMA-PAGE-ADDR-PART A-ZERO)	;Put CCW list in high memory
;	((m-c) dpb m-2 vma-block-part a-zero)	;put ccw list in high memory, above the blocks
;	((m-c) dpb m-2 vma-page-addr-part a-zero)	;quux revision 13: above the pages
;	((M-S) C-PDL-BUFFER-POINTER-POP)
;	(JUMP COLD-DISK-WRITE)

;; quux revision 14 (contract g3 revision 14, 10.6): every pageable frame's page
;; is evicted with %delete-physical-page (written to its slot if modified),
;; from the highest frame down; then every wired frame below a-wired-frames
;; that has no slot gets one, and the wired pages are written to their slots.
;; the copy that follows reads every page from its slot.  requires m-s, the
;; memory's words.  the frames are out of service afterwards; cold-swap-in puts
;; them back.
SWAP-OUT-ALL-PAGES
	((C-PDL-BUFFER-POINTER-PUSH) M-S)
	((m-t) a-memory-frames)
	((m-t) sub m-t (a-constant 1))		;First page to do is highest in core
swap-out-all-pages-1
	((C-PDL-BUFFER-POINTER-PUSH) M-T)	;Save current page
	((C-PDL-BUFFER-POINTER-PUSH) DPB M-T VMA-PHYS-PAGE-ADDR-PART A-ZERO)  ;arg
	(CALL XDPPG)
	((M-T) SUB C-PDL-BUFFER-POINTER-POP (A-CONSTANT 1))
	(JUMP-GREATER-OR-EQUAL M-T A-ZERO SWAP-OUT-ALL-PAGES-1)
	((m-b) a-zero)				;the wired frames' slots
swap-out-all-pages-2
	(call ppd-slot)
	(jump-not-equal m-tem (a-constant page-entry-no-slot) swap-out-all-pages-3)
	((a-paging-tem) vma)			;its word 1
	(call allocate-slot)			;none yet: take one
	((md) q-pointer m-tem (a-constant (byte-value q-data-type dtp-fix)))
	((vma-start-write) a-paging-tem)
	(illop-if-page-fault)
swap-out-all-pages-3
	((m-b) add m-b (a-constant 1))
	(jump-less-than m-b a-wired-frames swap-out-all-pages-2)
	((a-run-end) a-wired-frames)		;write them
	((a-wired-op) (a-constant 1))
	(call-xct-next run-wired-pages)
       ((m-b) a-zero)
	(POPJ-AFTER-NEXT (M-S) C-PDL-BUFFER-POINTER-POP)
       (NO-OP)

COLD-BOOT
	((M-4) A-ZERO)				;0 => use current band.
	(JUMP DISK-RESTORE-1)			;Load world from there

;(%DISK-RESTORE high-16-bits-of-partition-name low-16-bits)
;The first and second arguments may be zero to specify the current partition.
DISK-RESTORE (MISC-INST-ENTRY %DISK-RESTORE)
;	((M-4) C-PDL-BUFFER-POINTER-POP)
	;; quux revision 13 (appendix a1.11, rule 5): the argument's field, as at
	;; disk-save
	((m-4) q-pointer c-pdl-buffer-pointer-pop)
	((M-4) DPB C-PDL-BUFFER-POINTER-POP (BYTE-FIELD 20 20) A-4)
	(jump disk-restore-1)		;quux revision 14: it is written further on
;DISK-RESTORE-1
;	((WRITE-MEMORY-DATA) (A-CONSTANT 200000))	;64K to be direct-mapped
	;; quux revision 13: the wired words end at 530000 (the page table and
	;; physical-page-data sized for 32 m words), and cold-swap-in puts its ccw
	;; list above them; both must be direct-mapped, as the first 64k was, or
	;; the level-1 miss uses the reverse map that the band's page 1 has just
	;; overwritten.  8 level-1 blocks, 256k words.
;	((write-memory-data) (a-constant 1000000))	;256k to be direct-mapped
;	(CALL-XCT-NEXT PHYS-MEM-WRITE)
;       ((VMA) (A-CONSTANT (EVAL (PLUS 400 %SYS-COM-WIRED-SIZE))))
;       ((vma) (a-constant (eval (plus 2000 %sys-com-wired-size))))	;1024-word pages: at 2000
;	(CALL RESET-MACHINE)
	;; quux: the run light back at its boot address, as a cold boot has it,
	;; before the two fake level-2 entries below, which must fall in different
	;; slots (vma<12:8>) of the invalid block.  lisp moves the run light to
	;; the video controller's last line (tv::initialize-run-light-locations,
	;; sys; ltop), and when the buffer is a multiple of 8k words long,
	;; 1280x1024 and 1024x768 among them, that is slot 37, the disk
	;; registers' own: the
	;; second entry overwrote the first, %disk-restore's disk commands went to
	;; the frame buffer, and disk-await-ready waited for ever.  lisp sets it
	;; again after the restore.  (from revision 11, contract q13, the disk
	;; registers are the register page's words 200-203, virtual 77777600,
	;; still slot 37.)
;	((a-disk-run-light) (a-constant (plus (byte-value q-data-type dtp-fix)
;					      disk-run-light-virtual-address)))
;	(CALL-XCT-NEXT COLD-FAKE-L2-MAP)	;set up L2 map to avoid getting to
;       ((MD) A-DISK-REGS-BASE)			; page fault handler from AWAIT-DISK,etc
	;; quux: and halt at run-light-shares-disk-slot, rather than hang, if the
	;; run light's entry would overwrite the disk registers'.
;	((m-1) a-disk-run-light)
;	((m-1) (byte-field 5 8) m-1)
;	((m-1) (byte-field 5 10.) m-1)		;quux revision 13: vma<14:10>, a page's slot
;	((m-2) a-disk-regs-base)
;	((m-2) (byte-field 5 8) m-2)
;	((m-2) (byte-field 5 10.) m-2)
;	(jump-equal m-1 a-2 run-light-shares-disk-slot)
;	(CALL-XCT-NEXT COLD-FAKE-L2-MAP)	; before things set up.  Another RESET-MACHINE
;       ((MD) A-DISK-RUN-LIGHT)			; will be done at beg0000 eventually anyway.
	;; quux: block-disk has no drive to recalibrate (mit's did, for the
	;; marksman, after the i/o reset).

;;; Determine size of main memory
	;; quux: error stop is the register page's word 102, bit 0, not unibus
	;; 766012 (where mit wrote 40, prom-disable alone).
;	((MD) SETZ)				;Turn off ERROR-STOP-ENABLE
;	(CALL-XCT-NEXT PHYS-MEM-WRITE)
;       ((VMA) (A-CONSTANT QUUX-MODE-PHYSICAL-ADDRESS))
;	((M-S) SETZ)
;MEM-SIZE-LOOP
;	((VMA M-S) ADD M-S (A-CONSTANT 40000))	;Memory comes in 16K increments
	;; stop at physical 1760000000, where the frame buffer's window begins
	;; (revision 13's address map): main memory is below it, and the window
	;; reads back the field written, so a probe with no stop would count it
	;; as memory after a memory that reached it.
;	(jump-greater-or-equal m-s (a-constant 1760000000) mem-size-done)
;	(CALL-XCT-NEXT PHYS-MEM-WRITE)
;       ((MD) (A-CONSTANT 37))			;Some 1's, some 0's
;	(CALL PHYS-MEM-READ)
;	(JUMP-EQUAL MD (A-CONSTANT 37) MEM-SIZE-LOOP)
;mem-size-done
	;M-S now has the first non-existent location
;	((md) (a-constant 1))			;Turn ERROR-STOP-ENABLE back on
;	(CALL-XCT-NEXT PHYS-MEM-WRITE)		;quux: word 102, not 766012
;       ((VMA) (A-CONSTANT QUUX-MODE-PHYSICAL-ADDRESS))
;	(CALL-XCT-NEXT PHYS-MEM-WRITE)		;Clear bus error indicators
;       ((VMA) (A-CONSTANT QUUX-ERROR-STATUS-PHYSICAL-ADDRESS)) ;quux: word 101, not 766044
;	(call cold-read-gpt-page-0)		;Find PAGE partition and specified partition.
;	((M-1) M-I)				;From start of source band.
;	((M-2) (A-CONSTANT 3))			;Core pages 0, 1, and 2
;	((m-2) (a-constant low-pages-blocks))	;core pages 0, 1, and 2: 14 blocks
;	((m-2) (a-constant low-pages))		;quux revision 13: core pages 0, 1, and 2
;	((M-B) (A-CONSTANT 0))			;..
;	((M-C) (A-CONSTANT COPY-BUFFER-CCW-ORIGIN)) ;CCW list after MICRO-CODE-SYMBOL-AREA
;	(CALL COLD-DISK-READ)
;	(CALL-XCT-NEXT PHYS-MEM-READ)
;       ((VMA) (A-CONSTANT (PLUS 400 (EVAL %SYS-COM-BAND-FORMAT))))
;	(JUMP-EQUAL MD (A-CONSTANT 1000) DISK-RESTORE-REGIONWISE)  ;compressed partition.
;	(JUMP-EQUAL MD (A-CONSTANT 1001) DISK-RESTORE-INCREMENTAL) ;incremental partition.
	;; 1024-word pages (contract g2, option (w); appendix a1.12): 1100
	;; compressed, 1101 incremental, 1102 a cold load.  a band of 256-word
	;; pages (1000, 1001, or a cold load with anything else) halts at
	;; band-not-1024-word-pages rather than load, as it was taken for a
	;; cold load before.  the save stores a bare number and the cold load a
	;; fixnum, so the pointer field is compared.
;       ((vma) (a-constant (plus 2000 (eval %sys-com-band-format))))
;	((m-tem) q-pointer md)
;	(jump-equal m-tem (a-constant 1100) disk-restore-regionwise)  ;compressed partition.
;	(jump-equal m-tem (a-constant 1101) disk-restore-incremental) ;incremental partition.
;	(jump-not-equal m-tem (a-constant 1102) band-not-1024-word-pages)
	;; quux revision 13 (contract g2 2.8; appendix a1.12): a 40-bit band's
	;; format is a fixnum, compared whole with fixnum constants: 2000 saved,
	;; 2002 a cold load, 2001 incremental (it halted at
	;; incremental-band-not-supported until incremental bands were converted
	;; to 5-block pages), and anything else, a 32-bit band's 1000-1102 among
	;; them, halts at band-not-40-bit, rather than be taken for a cold load.
;	(jump-equal md (a-constant (plus (byte-value q-data-type dtp-fix) 2000))
;		disk-restore-regionwise)  ;compressed partition.
;	(jump-equal md (a-constant (plus (byte-value q-data-type dtp-fix) 2001))
;		disk-restore-incremental) ;incremental partition.
;	(jump-not-equal md (a-constant (plus (byte-value q-data-type dtp-fix) 2002))
;		band-not-40-bit)
;Non-compressed band (must be a cold-load band, I think).
;	(CALL-XCT-NEXT PHYS-MEM-READ)		;Get useful size of partition, in words
;       ((VMA) (A-CONSTANT (PLUS 400 (EVAL %SYS-COM-VALID-SIZE))))
;	((M-D) VMA-PAGE-ADDR-PART MD)		;Number of valid pages
;       ((vma) (a-constant (plus 2000 (eval %sys-com-valid-size))))
;	((m-d) vma-block-part md)		;number of valid blocks
;	(JUMP-LESS-OR-EQUAL M-J A-D DISK-COPY-PART-1)
;	((M-J) M-D)				;M-J is number of pages to copy (min sizes)
;DISK-COPY-PART-1
;	(CALL-GREATER-THAN M-J A-R ILLOP)	;Not enough room in destination partition
	;; quux revision 13: m-j and m-r are the band's and the paging
	;; partition's blocks, 5 a page; disk-copy-section copies pages.  the valid
	;; pages, if the band holds them.
;	((m-d) vma-page-addr-part md)		;number of valid pages
;	((m-tem) dpb m-d (byte-field 30. 2) a-zero)
;	((m-tem) add m-tem a-d)			;their blocks
;	(jump-less-or-equal m-tem a-j disk-copy-part-1)
;	((m-1) m-j)				;or as many as the band holds
;	(call divide-by-blocks-per-page)
;	((m-d) m-1)
;	((m-tem) dpb m-d (byte-field 30. 2) a-zero)
;	((m-tem) add m-tem a-d)
;disk-copy-part-1
;	(call-greater-than m-tem a-r illop)	;not enough room in destination partition
;	((m-j) m-d)				;m-j is number of pages to copy (min sizes)
;	(CALL DISK-COPY-SECTION)
;	(JUMP COLD-SWAP-IN)

;DISK-RESTORE-REGIONWISE
;	((M-K) A-ZERO)
;	((M-I) ADD M-I (A-CONSTANT 3))
;	((M-J) SUB M-J (A-CONSTANT 3))
;	((m-i) add m-i (a-constant low-pages-blocks))	;1024-word pages: 3 pages, 14 blocks
;	((m-j) sub m-j (a-constant low-pages-blocks))
	;; quux revision 13: 3 pages of 5 blocks
;	((m-i) add m-i (a-constant (eval (* 3 5))))
;	((m-j) sub m-j (a-constant (eval (* 3 5))))
  ;Micro-code-symbol-area has a free pointer
  ;of zero, so is not copied into band.  Therefore, REGION-ORIGIN, etc. start at 3rd page
  ;of band
;DISK-RESTORE-REGIONWISE-INC
;	(CALL DISK-RESTORE-REGIONWISE-SUBR)
;	(JUMP COLD-SWAP-IN)

;M-I and M-J have origin and size of data to restore,
;omitting the first three pages, and the bitmap and base band pages for an inc band.
;M-K has length of bit map saying which pages to omit;
;this bit map is in core starting at INC-BAND-BITMAP-BUFFER-ORIGIN.
;If M-K is 0, restore all the pages from the band.
;Note: for restoring an incremental band, M-I is not really the start of the band;
;it is adjusted upward for the number of special inc band pages we should skip.
;It is adjusted so that it plus 3 is the first block after the bitmap!
;M-J is adjusted down to match.
;DISK-RESTORE-REGIONWISE-SUBR
;low 3 pages already in.
;Read in stuff below CCW buffer.  This had better include REGION-ORIGIN, -LENGTH, -BITS,
; -FREE-POINTER.
;	((M-B) (A-CONSTANT END-OF-MICRO-CODE-SYMBOL-AREA))
;	((M-2) (A-CONSTANT INC-BAND-BITMAP-BUFFER-PAGE-ORIGIN))
;	((M-2) SUB M-2 A-B)
;	((M-1) M-I)
;	((M-C) (A-CONSTANT COPY-BUFFER-CCW-ORIGIN))
;	(CALL COLD-DISK-READ)
;	((PDL-PUSH) M-K)
;	(CALL GET-AREA-ORIGINS)		;set up A-V-REGION-ORIGIN, -LENGTH, -BITS for below
;	((M-K) PDL-POP)
;At this point, M-S has words physical memory.   M-I, M-J point to band.
; A-V-REGION-ORGIN, -FREE-POINTER, and -BITS are valid,
; and those arrays are still in main memory and wont get clobbered by calling
; DISK-COPY-SECTION.  A-DISK-OFFSET and A-DISK-MAXIMUM are set.
;	((M-AP) (A-CONSTANT 3))			;region to hack.
;	((A-COPY-BAND-TEM) ADD M-I A-J) ;better not try to read above here.
;DISK-RR-1
;	((VMA-START-READ) ADD M-AP A-V-REGION-BITS)
;	(ILLOP-IF-PAGE-FAULT)
;	((M-TEM) LDB (LISP-BYTE %%REGION-SPACE-TYPE) MD)
;	(JUMP-EQUAL M-TEM A-ZERO DISK-RR-2)	;free region, forget it.
;	((VMA-START-READ) ADD M-AP A-V-REGION-ORIGIN)
;	(ILLOP-IF-PAGE-FAULT)
;	((M-Q) LDB VMA-PAGE-ADDR-PART MD)
	;; 1024-word pages (contract g2, option (w)): blocks, as disk-sr-1 saves
	;; them: the region to the end of its free pointer's page
;	((m-q) ldb vma-block-part md)
;	((M-Q) ADD M-Q A-DISK-OFFSET)
;	((VMA-START-READ) ADD M-AP A-V-REGION-FREE-POINTER)
;	(ILLOP-IF-PAGE-FAULT)
;	((MD) ADD MD (A-CONSTANT 377))
;	((M-J) LDB VMA-PAGE-ADDR-PART MD)
;	((md) add md (a-constant 1777))
;	((m-j) ldb vma-page-addr-part md)
;	((m-j) dpb m-j (byte-field 16. 2) a-zero)	;its pages' blocks
;	(CALL-GREATER-OR-EQUAL M-I A-COPY-BAND-TEM ILLOP) ;bandwise EOF.
;	((M-TEM) ADD M-Q A-J)
;	((M-TEM) SUB M-TEM A-DISK-OFFSET)
	;; quux revision 13, as disk-sr-1: the region's first block in the paging
	;; partition, 5 a page, and its pages
;	((m-q) ldb vma-page-addr-part md)
;	((m-1) m-q)				;its first page, for disk-restore-region
;	((m-tem) dpb m-q (byte-field 30. 2) a-zero)
;	((m-q) add m-q a-tem)			;times 5
;	((M-Q) ADD M-Q A-DISK-OFFSET)
;	((VMA-START-READ) ADD M-AP A-V-REGION-FREE-POINTER)
;	(ILLOP-IF-PAGE-FAULT)
;	((md) add md (a-constant 1777))
;	((m-j) ldb vma-page-addr-part md)	;its pages
;	(CALL-GREATER-OR-EQUAL M-I A-COPY-BAND-TEM ILLOP) ;bandwise EOF.
;	((m-tem) dpb m-j (byte-field 30. 2) a-zero)
;	((m-tem) add m-tem a-j)			;its blocks
;	((m-tem) add m-q a-tem)
;	((M-TEM) SUB M-TEM A-DISK-OFFSET)
;	(CALL-GREATER-OR-EQUAL M-TEM A-DISK-MAXIMUM ILLOP)   ;page partition not big enuf
							     ; for this band.
;	(CALL DISK-RESTORE-REGION)
;	(CALL-GREATER-OR-EQUAL M-I A-COPY-BAND-TEM ILLOP) ;bandwise EOF.
;DISK-RR-2
;	((M-TEM) A-V-REGION-LENGTH)		;depend on REGION-ORIGIN and REGION-LENGTH
;	((M-TEM) SUB M-TEM A-V-REGION-ORIGIN)	; being consecutive to determine how
;	((M-AP) ADD M-AP (A-CONSTANT 1))	; many regions there are.
;	(JUMP-LESS-THAN M-AP A-TEM DISK-RR-1)
;	(POPJ)

;Copy one region from compressed LOD band to PAGE band.
;M-I and M-J have origin and size (on disk) of the region, where it lives in the LOD band.
;M-Q has disk address in PAGE band to copy to.
;M-K has bitmap length or 0 if no bitmap.
;M-S assumed to have phys memory size.
;Clobbers M-1, M-2, M-B, M-C, M-D, M-J, M-T and M-R
;On exit, M-I and M-Q are updated past this region.

;DISK-RESTORE-REGION
;If no bitmap, copy entire region,
;	(JUMP-EQUAL M-K A-ZERO DISK-COPY-SECTION)
;Otherwise copy only pages which have 0 in the bitmap.
;Each page copied goes into the PAGE partition according to its page number.
;Thus, the pages not copied do take up space in PAGE.
;But only the copied pages are present in the source partition.
;	((M-1) SUB M-Q A-DISK-OFFSET)
;	((M-R) ADD M-J A-1)
;DISK-RESTORE-REGION-LOOP
;;M-1 gets virt mem page number of start of this region.
;	((M-1) SUB M-Q A-DISK-OFFSET)
;	((M-2) (A-CONSTANT 0))
;;Search for next page with a 0 in the bit map.  Increment M-1 up to that page number.
;	(CALL DISK-RESTORE-BITMAP-SEARCH)
;	((M-Q) ADD M-1 A-DISK-OFFSET)
;;Return now if no page found within this region.
;	(POPJ-EQUAL M-1 A-R)
;;Find next following page we should not copy.
;	((M-2) (A-CONSTANT 1))
;	(CALL DISK-RESTORE-BITMAP-SEARCH)
;;M-J gets number of consec pages to be copied.
;	((M-J) ADD M-1 A-DISK-OFFSET)
;	((M-J) SUB M-J A-Q)
;;Copy them.  Updates M-I to point at place to copy next page from.
;	(CALL DISK-COPY-SECTION)
;	(JUMP DISK-RESTORE-REGION-LOOP)
	;; quux revision 13: as disk-save-region, with m-q the paging partition's
	;; block; m-1 the region's first page (disk-rr-1).
;	((M-R) ADD M-J A-1)
;DISK-RESTORE-REGION-LOOP
;	((M-2) (A-CONSTANT 0))
;Search for next page with a 0 in the bit map.  Increment M-1 up to that page number.
;	(CALL DISK-RESTORE-BITMAP-SEARCH)
;	((m-tem) dpb m-1 (byte-field 30. 2) a-zero)	;m-q its block
;	((m-q) add m-1 a-tem)
;	((m-q) add m-q a-disk-offset)
;Return now if no page found within this region.
;	(POPJ-EQUAL M-1 A-R)
;	((pdl-push) m-1)
;Find next following page we should not copy.
;	((M-2) (A-CONSTANT 1))
;	(CALL DISK-RESTORE-BITMAP-SEARCH)
;M-J gets number of consec pages to be copied.
;	((m-2) pdl-pop)
;	((m-j) sub m-1 a-2)
;Copy them.  Updates M-I to point at place to copy next page from.
;	((pdl-push) m-1)
;	(CALL DISK-COPY-SECTION)
;	((m-1) pdl-pop)
;	(JUMP DISK-RESTORE-REGION-LOOP)

;Search for a page whose entry in the inc band bitmap in core matches M-2 (zero or one).
;M-1 contains first page to consider.  Page found is returned in M-1.
;M-R contains last page to consider, plus one.
;If nothing is found, returned value in M-1 matches M-R.
;DISK-RESTORE-BITMAP-SEARCH
;	(POPJ-EQUAL M-1 A-R)
;	((VMA) (BYTE-FIELD 23 5) M-1)
;	(CALL-XCT-NEXT PHYS-MEM-READ)
;       ((VMA) ADD VMA (A-CONSTANT INC-BAND-BITMAP-BUFFER-ORIGIN))
;	((VMA) (BYTE-FIELD 5 0) M-1)
;	(JUMP-EQUAL VMA A-ZERO DISK-RESTORE-BITMAP-SEARCH-2)
;DISK-RESTORE-BITMAP-SEARCH-1
;	((MD) (BYTE-FIELD 37 1) MD)
;	((VMA) SUB VMA (A-CONSTANT 1))
;	(JUMP-NOT-EQUAL VMA A-ZERO DISK-RESTORE-BITMAP-SEARCH-1)
;DISK-RESTORE-BITMAP-SEARCH-2
;	((MD) (BYTE-FIELD 1 0) MD)
;	(POPJ-EQUAL MD A-2)
;	((M-1) M+1 M-1)
;	(JUMP DISK-RESTORE-BITMAP-SEARCH)

;;; Incremental dumping and loading.

;Index of page in incremental band that identifies the band's base band,
;and also the bitmap size.
;; 1024-word pages (contract g2, option (w)): these are blocks of the band,
;; after its first three pages, fourteen blocks, as io1; inc writes them.
;(ASSIGN INC-BAND-BASE-DATA-PAGE 3)
;(assign inc-band-base-data-page 14)
;; quux revision 13: pages of 5 blocks, mit's pages 3, 4 and 5 again: the
;; constants are their first blocks, 15, 20 and 25 (io1; inc writes them)
(assign inc-band-base-data-page 17)
;Index in that page of the bitmap size.
(ASSIGN INC-BAND-BITMAP-SIZE-INDEX 10)
;Index of page in incremental band that has a copy of the base band's REGION-FREE-POINTER
;(ASSIGN INC-BAND-BASE-FREE-POINTERS-PAGE 4)
;(assign inc-band-base-free-pointers-page 15)
(assign inc-band-base-free-pointers-page 24)
;Index of page in incremental band that has start of the band's bitmap.
;(ASSIGN INC-BAND-BITMAP-PAGE 5)
;(assign inc-band-bitmap-page 16)
(assign inc-band-bitmap-page 31)

;Address and page number of buffer in core used to hold the bitmap.
;(ASSIGN INC-BAND-BITMAP-BUFFER-PAGE-ORIGIN 20)
;(ASSIGN INC-BAND-BITMAP-BUFFER-ORIGIN 10000)
;; 1024-word pages (contract g2, option (w)): above the region tables, which
;; are at 10000-17777 (disk-restore-regionwise-subr reads them to below the
;; buffer); block 40, 20000
;(assign inc-band-bitmap-buffer-page-origin 40)
;; quux revision 13: pages again; page 10, 20000
(assign inc-band-bitmap-buffer-page-origin 10)
(assign inc-band-bitmap-buffer-origin 20000)

;DISK-RESTORE-INCREMENTAL
;	((M-B) (A-CONSTANT INC-BAND-BITMAP-BUFFER-PAGE-ORIGIN))
;	((M-1) ADD M-I (A-CONSTANT INC-BAND-BASE-DATA-PAGE))
;	(CALL COLD-DISK-READ-1)
;Read length in bits of page bit table of this incremental band.
;	(CALL-XCT-NEXT PHYS-MEM-READ)
;       ((VMA) (A-CONSTANT (PLUS INC-BAND-BITMAP-BUFFER-ORIGIN INC-BAND-BITMAP-SIZE-INDEX)))
;	((PDL-PUSH) MD)
;	((pdl-push) q-pointer md)	;quux revision 13: the count, without lisp's tag
;Read the name of the base partition.
;	(CALL-XCT-NEXT PHYS-MEM-READ)
;       ((VMA) (A-CONSTANT INC-BAND-BITMAP-BUFFER-ORIGIN))
;	((M-4) MD)
	;; quux revision 13: its four characters, without the tag lisp's array
	;; gave the word, as disk-restore takes its argument (cold-read-gpt
	;; compares the gpt's untagged names)
;	((m-4) q-pointer md)
;	((PDL-PUSH) M-I)
;	((PDL-PUSH) M-J)
;Restore the base partition of this partition.
;	(call cold-read-gpt-page-0)		;Find PAGE partition and specified partition.
;	((M-1) M-I)				;From start of source band.
;	((M-2) (A-CONSTANT 3))			;Core pages 0, 1, and 2
;	((m-2) (a-constant low-pages-blocks))	;core pages 0, 1, and 2: 14 blocks
;	((m-2) (a-constant low-pages))		;quux revision 13: core pages 0, 1, and 2
;	((M-B) (A-CONSTANT 0))			;..
;	((M-C) (A-CONSTANT COPY-BUFFER-CCW-ORIGIN)) ;CCW list after MICRO-CODE-SYMBOL-AREA
;	(CALL COLD-DISK-READ)
;	(CALL-XCT-NEXT PHYS-MEM-READ)
;       ((VMA) (A-CONSTANT (PLUS 400 (EVAL %SYS-COM-BAND-FORMAT))))
;	(CALL-NOT-EQUAL MD (A-CONSTANT 1000) ILLOP)  ;Must be a compressed partition.
;	((M-I) ADD M-I (A-CONSTANT 3))    ;See DISK-RESTORE-REGIONWISE for this insn.
;	((M-J) SUB M-J (A-CONSTANT 3))
	;; 1024-word pages (contract g2, option (w)): the area at 2000, 1100 for
	;; compressed, and three pages of fourteen blocks
;       ((vma) (a-constant (plus 2000 (eval %sys-com-band-format))))
;	(call-not-equal md (a-constant 1100) illop)  ;must be a compressed partition.
;	((m-i) add m-i (a-constant low-pages-blocks))    ;see disk-restore-regionwise for this insn.
;	((m-j) sub m-j (a-constant low-pages-blocks))
	;; quux revision 13: the base band's format the fixnum 2000, and three
	;; pages of 5 blocks, as disk-restore-regionwise
;	(call-not-equal md (a-constant (plus (byte-value q-data-type dtp-fix) 2000)) illop)
;	((m-i) add m-i (a-constant (eval (* 3 5))))
;	((m-j) sub m-j (a-constant (eval (* 3 5))))
;	((M-K) A-ZERO)		;Make sure restore as a non-compressed band!
;	(CALL DISK-RESTORE-REGIONWISE-SUBR)
;Now check that page 4 of incremental load
;matches the REGION-FREE-POINTER area of the base load.
;	((M-B) (A-CONSTANT INC-BAND-BITMAP-BUFFER-PAGE-ORIGIN))
;	((M-J) PDL-POP)
;	((M-I) PDL-POP)
;	((M-1) ADD (A-CONSTANT INC-BAND-BASE-FREE-POINTERS-PAGE) M-I)
;	(CALL COLD-DISK-READ-1)
;	((M-1) ADD M-MINUS-ONE (A-CONSTANT INC-BAND-BITMAP-BUFFER-ORIGIN))
;	((M-2) ADD M-MINUS-ONE A-V-REGION-FREE-POINTER)
;	((M-4) (A-CONSTANT (EVAL PAGE-SIZE)))
	;; 1024-word pages (contract g2, option (w)): the free pointers of the
	;; 256 regions, the one block read, not a whole page
;	((m-4) (a-constant 400))
;DISK-RESTORE-INCREMENTAL-CHECK
;	(CALL-XCT-NEXT PHYS-MEM-READ)
;       ((M-1 VMA) M+1 M-1)
;	((M-3) MD)
;	(CALL-XCT-NEXT PHYS-MEM-READ)
;       ((M-2 VMA) M+1 M-2)
;	(CALL-NOT-EQUAL MD A-3 ILLOP)
;	((M-4) SUB M-4 (A-CONSTANT 1))
;	(JUMP-NOT-EQUAL M-4 A-ZERO DISK-RESTORE-INCREMENTAL-CHECK)
;It matches; go ahead and load the incremental load.
;	((M-K) PDL-POP)
;Get number of pages the bit map occupies.
;	((M-2) ADD M-K (A-CONSTANT (EVAL (PLUS (TIMES PAGE-SIZE 32.) -1))))
	;; 1024-word pages (contract g2, option (w)): blocks of 256 words, not
	;; pages: the bitmap has a bit a block, and is read and skipped by blocks
;	((m-2) add m-k (a-constant (eval (plus (times 400 32.) -1))))
;	((M-2) LDB (BYTE-FIELD 13 15) M-2)
	;; quux revision 13: a bit a page again, as disk-save-incremental
;	((m-2) add m-k (a-constant (eval (plus (times page-size 32.) -1))))
;	((m-2) ldb (byte-field 13 17) m-2)
;	((M-R) M-2)
;Read in the bit map.
;	((M-1) ADD M-I (A-CONSTANT INC-BAND-BITMAP-PAGE))
;	((M-B) (A-CONSTANT INC-BAND-BITMAP-BUFFER-PAGE-ORIGIN))
;	((M-C) (A-CONSTANT COPY-BUFFER-CCW-ORIGIN))
;	(CALL COLD-DISK-READ)
;Reread low 3 pages of inc band (they were clobbered by those pages of base band)
;	((M-1) M-I)
;	((M-B) A-ZERO)
;	((M-2) (A-CONSTANT 3))
;	((m-2) (a-constant low-pages-blocks))	;1024-word pages: 3 pages, 14 blocks
;	((m-2) (a-constant low-pages))		;quux revision 13: 3 pages
;	((M-C) (A-CONSTANT COPY-BUFFER-CCW-ORIGIN))
;	(CALL COLD-DISK-READ)
;Adjust M-I and M-J so that DISK-RESTORE-REGIONWISE will skip the bitmap & base band pages.
;	((M-I) ADD M-I (A-CONSTANT INC-BAND-BITMAP-PAGE))
;	((M-I) ADD M-I A-R)
;	((M-J) SUB M-J (A-CONSTANT INC-BAND-BITMAP-PAGE))
;	((M-J) SUB M-J A-R)
	;; quux revision 13: in blocks, the bitmap's m-r pages 5 blocks each
;	((m-tem) dpb m-r (byte-field 30. 2) a-zero)
;	((m-tem) add m-tem a-r)
;	((m-tem) add m-tem (a-constant inc-band-bitmap-page))
;	((m-i) add m-i a-tem)
;	((m-j) sub m-j a-tem)
;Go restore the inc band.  M-K still has length in bits of bit map.
;	(JUMP DISK-RESTORE-REGIONWISE-INC)

;; quux revision 14: the incremental restore (above, commented out) is
;; rewritten over slots below.

;;; quux revision 14 (contract g3 revision 14, 10.7 item 2; appendix a14.13):
;;; the incremental restore over slots.  an incremental band holds its low
;;; three pages, its base band's name and the mask's length, a copy of the
;;; base band's region-free-pointer table, the mask, and then the pages whose
;;; mask bit is 0, in the order of the region-by-region walk from region 0 (the
;;; mask's index, lisp's io1; inc); a page whose bit is 1 is the same as the
;;; base band's page of the same region and place.  so the base band is copied
;;; into slots 0 on, page k to slot k, and its walk gives each of its regions'
;;; first slot (kept at base-band-index-origin, a word a region); the
;;; incremental band's pages are copied after it, into the next slots, in their
;;; order; and the incremental band's regions get entries holding either kind
;;; of slot (build-region-entries, a-restore-cold 2).  the low three pages are
;;; the incremental band's, read into memory directly, and keep their base
;;; slots, which the next save overwrites.
;;; the base band's region index table: a word a region, in the upper half of
;;; the copy's command-list page, which a copy of up to 1000 pages leaves alone.
(assign base-band-index-origin 41400)

DISK-RESTORE-INCREMENTAL
	((M-B) (A-CONSTANT INC-BAND-BITMAP-BUFFER-PAGE-ORIGIN))
	((M-1) ADD M-I (A-CONSTANT INC-BAND-BASE-DATA-PAGE))
	(CALL COLD-DISK-READ-1)
;Read length in bits of page bit table of this incremental band.
	(CALL-XCT-NEXT PHYS-MEM-READ)
       ((VMA) (A-CONSTANT (PLUS INC-BAND-BITMAP-BUFFER-ORIGIN INC-BAND-BITMAP-SIZE-INDEX)))
	((pdl-push) q-pointer md)	;the count, without lisp's tag
;Read the name of the base partition.
	(CALL-XCT-NEXT PHYS-MEM-READ)
       ((VMA) (A-CONSTANT INC-BAND-BITMAP-BUFFER-ORIGIN))
	((m-4) q-pointer md)
	((PDL-PUSH) M-I)
	((PDL-PUSH) M-J)
;Restore the base partition of this partition into slots 0 on.
	(call cold-read-gpt-page-0)		;Find PAGE partition and specified partition.
	((M-1) M-I)				;From start of source band.
	((m-2) (a-constant low-pages))		;core pages 0, 1, and 2
	((M-B) (A-CONSTANT 0))			;..
	((M-C) (A-CONSTANT COPY-BUFFER-CCW-ORIGIN)) ;CCW list after MICRO-CODE-SYMBOL-AREA
	(CALL COLD-DISK-READ)
	(CALL-XCT-NEXT PHYS-MEM-READ)
       ((vma) (a-constant (plus 2000 (eval %sys-com-band-format))))
	(call-not-equal md (a-constant band-format-saved) illop)	;must be a saved band
	((a-restore-cold) a-zero)
	(call restore-copy-base)		;the tables, the copy, its region tables
	;; each base region's first slot, its place in the base band's walk
	((m-a) a-zero)
	((m-d) a-zero)
dri-base-index
	((m-tem) a-v-region-length)
	((m-tem) sub m-tem a-v-region-origin)
	(jump-greater-or-equal m-a a-tem dri-check)
	((m-tem) (a-constant base-band-index-origin))
	((vma) add m-tem a-a)
	(call-xct-next phys-mem-write)
       ((md) m-d)
	((vma-start-read) add m-a a-v-region-bits)
	(illop-if-page-fault)
	((m-tem) (lisp-byte %%region-space-type) md)
	(jump-equal m-tem a-zero dri-base-index-1)	;free: no pages
	((vma-start-read) add m-a a-v-region-free-pointer)
	(illop-if-page-fault)
	((m-tem) add md (a-constant (eval (1- page-size))))
	((m-tem) vma-page-addr-part m-tem)
	((m-d) add m-d a-tem)
dri-base-index-1
	(jump-xct-next dri-base-index)
       ((m-a) add m-a (a-constant 1))
;Now check that page 4 of incremental load
;matches the REGION-FREE-POINTER area of the base load.
dri-check
	((M-B) (A-CONSTANT INC-BAND-BITMAP-BUFFER-PAGE-ORIGIN))
	((M-J) PDL-POP)
	((M-I) PDL-POP)
	((M-1) ADD (A-CONSTANT INC-BAND-BASE-FREE-POINTERS-PAGE) M-I)
	(CALL COLD-DISK-READ-1)
	((M-1) ADD M-MINUS-ONE (A-CONSTANT INC-BAND-BITMAP-BUFFER-ORIGIN))
	((M-2) ADD M-MINUS-ONE A-V-REGION-FREE-POINTER)
	((m-4) (a-constant 400))
DISK-RESTORE-INCREMENTAL-CHECK
	(CALL-XCT-NEXT PHYS-MEM-READ)
       ((M-1 VMA) M+1 M-1)
	((M-3) MD)
	(CALL-XCT-NEXT PHYS-MEM-READ)
       ((M-2 VMA) M+1 M-2)
	(CALL-NOT-EQUAL MD A-3 ILLOP)
	((M-4) SUB M-4 (A-CONSTANT 1))
	(JUMP-NOT-EQUAL M-4 A-ZERO DISK-RESTORE-INCREMENTAL-CHECK)
;It matches; read the incremental band's mask.
	((M-K) PDL-POP)
	((m-2) add m-k (a-constant (eval (plus (times page-size 32.) -1))))
	((m-2) ldb (byte-field 13 17) m-2)	;its pages
	((M-R) M-2)
	((M-1) ADD M-I (A-CONSTANT INC-BAND-BITMAP-PAGE))
	((M-B) (A-CONSTANT INC-BAND-BITMAP-BUFFER-PAGE-ORIGIN))
	((M-C) (A-CONSTANT COPY-BUFFER-CCW-ORIGIN))
	(CALL COLD-DISK-READ)
;Reread low 3 pages of inc band (they were clobbered by those pages of base band)
	((M-1) M-I)
	((M-B) A-ZERO)
	((m-2) (a-constant low-pages))
	((M-C) (A-CONSTANT COPY-BUFFER-CCW-ORIGIN))
	(CALL COLD-DISK-READ)
	;; its pages after the mask are copied into the slots after the base band's
	((m-tem) dpb m-r (byte-field 30. 2) a-zero)
	((m-tem) add m-tem a-r)
	((m-tem) add m-tem (a-constant inc-band-bitmap-page))
	((m-i) add m-i a-tem)			;the first page after the mask
	((m-j) sub m-j a-tem)			;the blocks left
	(call-xct-next phys-mem-read)		;the pages the band holds, from its valid size
       ((vma) (a-constant (plus 2000 (eval %sys-com-valid-size))))
	((m-d) vma-page-addr-part md)
	((m-tem) (a-constant 5))		;the low three pages, the two of base data; and the mask
	((m-tem) add m-tem a-r)
	((m-d) sub m-d a-tem)
	((m-tem) dpb m-d (byte-field 30. 2) a-zero)
	((m-tem) add m-tem a-d)
	(call-greater-than m-tem a-j illop)	;more than the band holds
	((m-q) a-restore-valid-pages)		;its first slot, past the base band's
	((m-tem) add m-q a-d)
	(call-greater-than m-tem a-disk-maximum-pages illop)	;more than the slots
	((m-tem) dpb m-q (byte-field 30. 2) a-zero)
	((m-q) add m-q a-tem)
	((m-q) add m-q a-disk-offset)
	((m-j) m-d)
	(call disk-copy-section)
	;; its region tables, its first saved pages (region 3 has none)
	((m-1) a-restore-valid-pages)
	((m-tem) dpb m-1 (byte-field 30. 2) a-zero)
	((m-1) add m-1 a-tem)
	((m-1) add m-1 a-disk-offset)
	((m-2) (a-constant (difference inc-band-bitmap-buffer-page-origin end-of-micro-code-symbol-area)))
	((m-b) (a-constant end-of-micro-code-symbol-area))
	((m-c) (a-constant copy-buffer-ccw-origin))
	(call cold-disk-read)
	(call get-area-origins)
	((a-restore-cold) (a-constant 2))	;incremental: the mask m-k, base indexes
	((a-inc-next-slot) a-restore-valid-pages)	;its own pages' first slot
	(call build-region-entries)
	(jump cold-swap-in)

;; restore-copy-base: as restore-copy, for the base band of an incremental one,
;; returning: the tables, the base band copied into slots 0 on, its region
;; tables read back.
RESTORE-COPY-BASE
	(call build-tables)			;the tables; word 220
	(CALL-XCT-NEXT PHYS-MEM-READ)		;Get useful size of partition, in words
       ((vma) (a-constant (plus 2000 (eval %sys-com-valid-size))))
	((m-d) vma-page-addr-part md)		;number of valid pages
	((m-tem) dpb m-d (byte-field 30. 2) a-zero)
	((m-tem) add m-tem a-d)
	(jump-less-or-equal m-tem a-j restore-copy-base-1)
	((m-1) m-j)
	(call divide-by-blocks-per-page)
	((m-d) m-1)
	((m-tem) dpb m-d (byte-field 30. 2) a-zero)
	((m-tem) add m-tem a-d)
restore-copy-base-1
	(call-greater-than m-tem a-r illop)	;not enough room in destination partition
	((a-restore-valid-pages) m-d)
	((m-j) m-d)
	((m-s) a-table-page-frame)		;the copy's buffer stays below the tables
	((m-s) dpb m-s vma-phys-page-addr-part a-zero)
	(CALL DISK-COPY-SECTION)
	((m-1) a-disk-offset)			;its region tables, its fourth page on
	((m-1) add m-1 (a-constant (eval (* 3 5))))
	((m-2) (a-constant (difference inc-band-bitmap-buffer-page-origin end-of-micro-code-symbol-area)))
	((m-b) (a-constant end-of-micro-code-symbol-area))
	((m-c) (a-constant copy-buffer-ccw-origin))
	(call cold-disk-read)
	(jump get-area-origins)

;;; Initialize physical memory from its swapped-out image on disk.
;;; Low 3 pages, page zero, the system communication area, and
;;; the scratchpad-init-area, already in.  MICRO-CODE-SYMBOL-AREA also in since it
;;; was loaded by microcode loader.
;COLD-SWAP-IN
;;; Read in the rest of wired memory (the sys comm area has its size).
;;; Don't clobber the MICRO-CODE-SYMBOL-AREA
;	(CALL-XCT-NEXT PHYS-MEM-READ)
;       ((VMA) (A-CONSTANT (PLUS 400 (EVAL %SYS-COM-WIRED-SIZE))))
;	((M-2) VMA-PAGE-ADDR-PART READ-MEMORY-DATA)	;Number of wired pages
	;; 1024-word pages (contract g2, option (w)): the area at 2000, and the
	;; wired words read in 256-word blocks, the disk's unit
;       ((vma) (a-constant (plus 2000 (eval %sys-com-wired-size))))
;	((m-2) vma-block-part read-memory-data)	;number of wired blocks
;	((M-C) Q-POINTER READ-MEMORY-DATA)	;Save for later, also put CCW list there
;	((M-B) (A-CONSTANT END-OF-MICRO-CODE-SYMBOL-AREA))
;	((M-1) ADD M-B A-DISK-OFFSET)
;	((M-2) SUB M-2 (A-CONSTANT END-OF-MICRO-CODE-SYMBOL-AREA))
	;; quux revision 13: pages, 5 blocks each on the disk
;	((m-2) vma-page-addr-part read-memory-data)	;number of wired pages
;	((M-C) Q-POINTER READ-MEMORY-DATA)	;Save for later, also put CCW list there
;	((M-B) (A-CONSTANT END-OF-MICRO-CODE-SYMBOL-AREA))
;	((m-1) (a-constant (eval (* 4 5))))	;page 4's first block
;	((M-1) ADD M-1 A-DISK-OFFSET)
;	((M-2) SUB M-2 (A-CONSTANT END-OF-MICRO-CODE-SYMBOL-AREA))
;	(CALL COLD-DISK-READ)
	;; use no more main memory than the band's page tables serve: one
	;; physical-page-data word and 4 page-table-area words a page, the sizes
	;; cold-reinit-pht and cold-reinit-ppd fill below.  the page table's size
	;; was capped there, after the memory size was stored, so with more
	;; memory than the tables serve (600 or 1024 boards against 32 megawords'
	;; tables) lisp saw the whole memory: the herald said 65536k,
	;; count-wired-pages read 32768 entries past the table, and
	;; set-scavenger-ws and warm-read-gpt's physical-page-data end take
	;; their extent from the same size.  the sizes are the band's
	;; own (cold/qcom.lisp), so a band with smaller tables uses that much of a
	;; bigger machine.
;	(call get-area-origins)			;moved up from below, for the sizes
;	((m-1) a-v-address-space-map)
;	((m-1) sub m-1 a-v-physical-page-data)	;pages the ppd serves
;	((m-2) a-v-physical-page-data)
;	((m-2) sub m-2 a-v-page-table-area)
;	((m-2) ldb (byte-field 30. 2) m-2 a-zero)	;pages the pht serves
;	(jump-less-or-equal m-1 a-2 cold-swap-in-cap-1)
;	((m-1) m-2)
;cold-swap-in-cap-1
;	((m-1) dpb m-1 vma-page-addr-part a-zero)	;in words
;	(jump-less-or-equal m-s a-1 cold-swap-in-cap-2)
;	((m-s) m-1)
;cold-swap-in-cap-2
;;; Set things up according to actual main memory size
;	((WRITE-MEMORY-DATA) Q-POINTER M-S (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
;	((VMA-START-WRITE) (A-CONSTANT (PLUS 400 (EVAL %SYS-COM-MEMORY-SIZE))))
;	((vma-start-write) (a-constant (plus 2000 (eval %sys-com-memory-size))))	;1024-word pages
;	(ILLOP-IF-PAGE-FAULT)
;;; Now set up the table of area addresses
;	(CALL GET-AREA-ORIGINS)
	;; done above, before the memory size is capped
;;; Reinitialize the page hash table to be completely empty;
;;; permanently wired pages have no entries.
;;; Decide the size of the PHT from the size of main memory; it should
;;; have 4 words in it for each page of main memory (thus will be 1/2 full).
;	((M-1) VMA-PAGE-ADDR-PART M-S)		;Number of pages of main memory
;	((M-1) ADD M-1 A-1 OUTPUT-SELECTOR-LEFTSHIFT-1)	;Times 4
	;; times 4 by a byte: the left shift brings in q<31>, which is 1 here
	;; on revision 13, so the size was 4 times the pages plus one, a page
	;; more once rounded (66560 words at 256 boards).
;	((m-1) dpb m-1 (byte-field 30. 2) a-zero)	;times 4
	;; rounded up to a power of two: compute-page-hash masks the hash to the
	;; size's power of two (set-pht-index-mask) and wraps what is past the
	;; size once, so a size between two powers got twice the hashes on its
	;; first words: at 256 boards (66560 words) the first 64512, at 300
	;; (77824) the first 53248.  the mask of the size less one, plus one, as
	;; set-pht-index-mask-1 builds it; the table's area is a power of two
	;; (cold/qcom.lisp), and the memory is capped to it above, so the size
	;; stays within it.
;	((m-tem) sub m-1 (a-constant 1))
;	((m-2) a-zero)
;cold-reinit-pht-power-of-two
;	((m-2) m+a+1 m-2 a-2)			;shift left bringing in 1
;	((m-tem) (byte-field 37 1) m-tem)	;shift right bringing in 0
;	(jump-not-equal m-tem a-zero cold-reinit-pht-power-of-two)
;	((m-1) add m-2 (a-constant 1))
;	((M-1) ADD M-1 (A-CONSTANT (EVAL (1- PAGE-SIZE))))	;Round up to multiple of page
;	((M-1) AND M-1 (A-CONSTANT (EVAL (MINUS PAGE-SIZE))))
;	((M-TEM) A-V-PHYSICAL-PAGE-DATA)	;But not bigger than available space
;	((M-TEM) SUB M-TEM A-V-PAGE-TABLE-AREA)
;	(JUMP-LESS-OR-EQUAL M-1 A-TEM COLD-REINIT-PHT-0)
;	((M-1) A-TEM)
	;; quux revision 13 (appendix a1.9): the table holds 4 words a page, so
	;; main memory past its pages gets no entry: m-s, the memory entered below,
	;; is cut to the table's pages, a quarter of its words, 1024 words each,
	;; rather than filling entries below the table's origin.
;	((m-s) dpb m-1 (byte-field 24. 8.) a-zero)
	;; the memory is capped to the tables before its size is stored (above),
	;; so the table's size is never cut here, and with the size a power of
	;; two this would raise m-s past the memory if it were.
;COLD-REINIT-PHT-0
;	((A-PHT-INDEX-LIMIT) M-1)		;Size of page hash table
;	((WRITE-MEMORY-DATA) Q-POINTER M-1 (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
;	((VMA-START-WRITE) (A-CONSTANT (EVAL (PLUS 400 %SYS-COM-PAGE-TABLE-SIZE))))
;	((vma-start-write) (a-constant (eval (plus 2000 %sys-com-page-table-size))))	;1024-word pages
;	(ILLOP-IF-PAGE-FAULT)
;	((M-J VMA) ADD M-1 A-V-PAGE-TABLE-AREA)	;Address above PHT
;	(CALL SET-PHT-INDEX-MASK)
;	((WRITE-MEMORY-DATA) (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))  ;Fill PHT with 0
;COLD-REINIT-PHT-2
;	((VMA-START-WRITE) SUB VMA (A-CONSTANT 1))
;	(ILLOP-IF-PAGE-FAULT)
;	(JUMP-GREATER-THAN VMA A-V-PAGE-TABLE-AREA COLD-REINIT-PHT-2)
;;; Initialize physical-page-data.  First make it all completely null.
;	((WRITE-MEMORY-DATA) (M-CONSTANT -1))
;	((VMA) A-V-REGION-ORIGIN)
	;; fill from the end of the table, address-space-map's origin.
	;; region-origin lies below page-table-area (cold/qcom.lisp, area-list),
	;; so the loop wrote -1 into the word below region-origin, the last of
	;; micro-code-symbol-area, and stopped, and the table was never filled:
	;; at 256 boards its 16384 entries past the memory's pages kept the
	;; band's words.
;	((vma) a-v-address-space-map)
;COLD-REINIT-PPD-0
;	((VMA-START-WRITE) SUB VMA (A-CONSTANT 1))
;	(ILLOP-IF-PAGE-FAULT)
;	(JUMP-GREATER-THAN VMA A-V-PHYSICAL-PAGE-DATA COLD-REINIT-PPD-0)
	;; the end of the valid entries starts at the table's origin, and xcppg1
	;; below raises it as it adds entries.  it was set only when the
	;; microcode was loaded and on a warm boot, so after %disk-restore it
	;; kept the previous world's end, past this band's table when that
	;; world's table was elsewhere or larger (the cadr line's halt in
	;; fatal-disk-error).  findcore's and the ager's scan pointers start at
	;; page 0.
;	((a-v-physical-page-data-end) a-v-physical-page-data)
;	((a-findcore-scan-pointer) a-zero)
;	((a-aging-scan-pointer) a-zero)
;;; Make magic PHYSICAL-PAGE-DATA entries for the wired pages and
;;; free entries in PPD and PHT for the available main memory.
;;; M-J has the upper-bound address of the PHT.  M-I gets same for PPD.
;	((M-1) VMA-PAGE-ADDR-PART M-S)			;Number of pages of main memory
;	((M-I) ADD M-1 A-V-PHYSICAL-PAGE-DATA)
;	((M-R) A-V-RESIDENT-SYMBOL-AREA)		;Address doing
;	((M-K) ADD M-S A-R)				;Size of memory
;	((M-C) M-J)					;Address for filling in PHT
;COLD-REINIT-PPD-1
;	(JUMP-GREATER-OR-EQUAL M-R A-V-REGION-GC-POINTER COLD-REINIT-PPD-3)	;free
;	(JUMP-GREATER-OR-EQUAL M-R A-V-ADDRESS-SPACE-MAP COLD-REINIT-PPD-2)	;wired
;	(JUMP-GREATER-OR-EQUAL M-R A-I COLD-REINIT-PPD-3)	;free part of PPD
;	(JUMP-GREATER-OR-EQUAL M-R A-V-PHYSICAL-PAGE-DATA COLD-REINIT-PPD-2)	;wired
;	(JUMP-GREATER-OR-EQUAL M-R A-J COLD-REINIT-PPD-3)	;free part of PHT
;COLD-REINIT-PPD-2
;	((WRITE-MEMORY-DATA) (A-CONSTANT 177777))	;Wired page, no PHT entry
;; quux revision 13 (appendix a1.9): the pht index is physical-page-data's <19:0>, 32 m words' 131072-word table
;	((write-memory-data) (a-constant 3777777))	;Wired page, no PHT entry
;	((VMA-START-WRITE) (BYTE-FIELD 8 8) M-R A-V-PHYSICAL-PAGE-DATA)
	;; 1024-word pages (contract g2, option (w)): the frame's number is
	;; m-r<21:10>, added to the table's origin (which need not be a multiple
	;; of the index's range, as the merge of the ldb assumed)
;	((m-tem) vma-phys-page-addr-part m-r)
;	((vma-start-write) add m-tem a-v-physical-page-data)
;	(ILLOP-IF-PAGE-FAULT)
;	(JUMP COLD-REINIT-PPD-4)

;COLD-REINIT-PPD-3
;	((VMA M-C) SUB M-C (A-CONSTANT 4))		;Put in a PHT entry for free page
	;; a free page's entry goes at the first hole from its frame's hash xor
	;; 4 entries, where free-region puts a freed page's (uc-page-fault.lisp,
	;; xcpgs0).  laid every other entry down from the table's top, the free
	;; pages sat in frame order, and findcore, which takes them in frame
	;; order, emptied the table section by section while the pages it filled
	;; hashed elsewhere: at 32 m words the sections not yet reached went to
	;; 90-100% full after four flips.  hashed by frame, consecutive frames
	;; spread over the table.  the hash of a frame and of a virtual page from
	;; the same 128-page block start at the same offset in their 8-entry
	;; group, so at the hash itself every real page's slot held a free page
	;; (4.6 probes a hit, against 1.5); xor 4 takes the group's other half.
;	((m-t) m-r)					;the frame's address
;	(call compute-page-hash)
;	((m-t) xor m-t (a-constant 8.))			;xor 4 entries (8 words)
;cold-reinit-ppd-5
;	((vma-start-read) add m-t a-v-page-table-area)	;the first hole from it
;	(illop-if-page-fault)
;	(jump-if-bit-clear pht1-valid-bit read-memory-data cold-reinit-ppd-6)
;	((m-t) add m-t (a-constant 2))
;	(jump-less-than m-t a-pht-index-limit cold-reinit-ppd-5)
;	(jump-xct-next cold-reinit-ppd-5)
;       ((m-t) sub m-t a-pht-index-limit)		;wrap around
;cold-reinit-ppd-6
;	(CALL-XCT-NEXT XCPPG1)				;Create physical page
;       ((C-PDL-BUFFER-POINTER-PUSH) M-R)		;At this address
;COLD-REINIT-PPD-4
;	((M-R) ADD M-R (A-CONSTANT (EVAL PAGE-SIZE)))
;	(JUMP-LESS-THAN M-R A-K COLD-REINIT-PPD-1)

;; quux revision 14 (contract g3 revision 14, 9.5; appendix a14.13): the
;; devices are reset, but no map is set up: the cold boot reaches memory, the
;; disk's command lists and the registers through the windows until the
;; tables are made.  the memory is sized through the physical memory window up
;; to 2^28 words; the band's first pages are read; a band of revision 13's
;; formats is refused; then the tables (build-tables), the copy of the band
;; into the paging partition's slots, the region tables read back from them,
;; and the entries (build-region-entries).
DISK-RESTORE-1
	((a-wired-frames) (a-constant 400))	;wired for the restore: the first 256k words
	(call reset-devices)
	((a-disk-run-light) (a-constant (plus (byte-value q-data-type dtp-fix)
					      disk-run-light-virtual-address)))
;;; Determine size of main memory
	((MD) SETZ)				;Turn off ERROR-STOP-ENABLE
	(CALL-XCT-NEXT PHYS-MEM-WRITE)
       ((VMA) (A-CONSTANT QUUX-MODE-PHYSICAL-ADDRESS))
	((M-S) SETZ)
restore-mem-size-loop
	((VMA M-S) ADD M-S (A-CONSTANT 40000))	;Memory comes in 16K increments
	;; up to 2^28 words, physical space's end (appendix a14.1); past main
	;; memory's end the window is nothing there, reading 0.
	(jump-greater-or-equal-unsigned m-s (a-constant 2000000000) restore-mem-size-done)
	(CALL-XCT-NEXT PHYS-MEM-WRITE)
       ((MD) (A-CONSTANT 37))			;Some 1's, some 0's
	(CALL PHYS-MEM-READ)
	(JUMP-EQUAL MD (A-CONSTANT 37) restore-mem-size-loop)
restore-mem-size-done
	;M-S now has the first non-existent location
	((md) (a-constant 1))			;Turn ERROR-STOP-ENABLE back on
	(CALL-XCT-NEXT PHYS-MEM-WRITE)		;quux: word 102, not 766012
       ((VMA) (A-CONSTANT QUUX-MODE-PHYSICAL-ADDRESS))
	(CALL-XCT-NEXT PHYS-MEM-WRITE)		;Clear bus error indicators
       ((VMA) (A-CONSTANT QUUX-ERROR-STATUS-PHYSICAL-ADDRESS)) ;quux: word 101, not 766044
	(call cold-read-gpt-page-0)		;Find PAGE partition and specified partition.
	((M-1) M-I)				;From start of source band.
	((m-2) (a-constant low-pages))		;core pages 0, 1, and 2
	((M-B) (A-CONSTANT 0))			;..
	((M-C) (A-CONSTANT COPY-BUFFER-CCW-ORIGIN)) ;CCW list after MICRO-CODE-SYMBOL-AREA
	(CALL COLD-DISK-READ)
	(CALL-XCT-NEXT PHYS-MEM-READ)
       ((vma) (a-constant (plus 2000 (eval %sys-com-band-format))))
	((a-restore-cold) a-zero)
	(jump-equal md (a-constant band-format-saved) restore-copy)
	(jump-equal md (a-constant band-format-incremental) disk-restore-incremental)
	((a-restore-cold) (a-constant 1))
	(jump-equal md (a-constant band-format-cold-load) restore-copy)
	;; revision 13's bands: 2000 saved, 2001 incremental, 2002 a cold load
	(jump-equal md (a-constant (plus (byte-value q-data-type dtp-fix) 2000)) band-not-revision-14)
	(jump-equal md (a-constant (plus (byte-value q-data-type dtp-fix) 2001)) band-not-revision-14)
	(jump-equal md (a-constant (plus (byte-value q-data-type dtp-fix) 2002)) band-not-revision-14)
	(jump band-not-40-bit)

;; the band's pages, all it holds, are copied into the paging partition's
;; slots from 0, page k to slot k: the valid pages the system communication
;; area records, or as many as the band holds.  then the region tables are read
;; back from their slots (a saved band holds them from its fourth page, as
;; region 3, the micro-code symbol area, has none; a cold load has them at
;; their own pages), and the entries are made.
restore-copy
	(call build-tables)			;the tables; word 220
	(CALL-XCT-NEXT PHYS-MEM-READ)		;Get useful size of partition, in words
       ((vma) (a-constant (plus 2000 (eval %sys-com-valid-size))))
	((m-d) vma-page-addr-part md)		;number of valid pages
	((m-tem) dpb m-d (byte-field 30. 2) a-zero)
	((m-tem) add m-tem a-d)			;their blocks
	(jump-less-or-equal m-tem a-j restore-copy-1)
	((m-1) m-j)				;or as many as the band holds
	(call divide-by-blocks-per-page)
	((m-d) m-1)
	((m-tem) dpb m-d (byte-field 30. 2) a-zero)
	((m-tem) add m-tem a-d)
restore-copy-1
	(call-greater-than m-tem a-r illop)	;not enough room in destination partition
	((a-restore-valid-pages) m-d)
	((m-j) m-d)				;m-j is number of pages to copy (min sizes)
	((m-s) a-table-page-frame)		;the copy's buffer stays below the tables
	((m-s) dpb m-s vma-phys-page-addr-part a-zero)
	(CALL DISK-COPY-SECTION)		;band page k to slot k
	((m-1) a-disk-offset)			;the region tables, physical pages 4-9
	((m-tem) a-restore-cold)
	(jump-equal-xct-next m-tem a-zero restore-copy-2)
       ((m-1) add m-1 (a-constant (eval (* 3 5))))	;a saved band: its fourth page on
	((m-1) add m-1 (a-constant 5))			;a cold load: its fifth
restore-copy-2
	((m-2) (a-constant (difference inc-band-bitmap-buffer-page-origin end-of-micro-code-symbol-area)))
	((m-b) (a-constant end-of-micro-code-symbol-area))
	((m-c) (a-constant copy-buffer-ccw-origin))
	(call cold-disk-read)
	(call get-area-origins)
	(call build-region-entries)
	(jump cold-swap-in)

;; quux revision 14 (contract g3 revision 14, 9.5, 10.6; appendix a14.12,
;; a14.13): the cold boot, before its first paged reference, sizes memory
;; through the physical memory window, takes the tables' frames at its top
;; (build-tables), writes word 220 and the pointer-type register
;; (initial-map), maps the wired areas virtual equal to physical, and restores
;; the band.  a band's pages are copied, in the band's own order, into the
;; paging partition's slots 0 on (the band's page k into slot k), and every
;; page of every region gets an entry holding its slot (build-region-entries):
;; for a saved band, k is the page's place in the region-by-region walk the
;; save made; for a cold load, its virtual page, as the cold load lays pages
;; out.  then cold-swap-in reads the wired pages from their slots.

;; the band formats (appendix a14.13): 2010 saved, 2011 incremental, 2012 a
;; cold load, fixnums; revision 13's 2000-2002 are refused.
(assign band-format-saved (plus (byte-value q-data-type dtp-fix) 2010))
(assign band-format-incremental (plus (byte-value q-data-type dtp-fix) 2011))
(assign band-format-cold-load (plus (byte-value q-data-type dtp-fix) 2012))

;;; build-tables: the tables' frames at the top of the memory m-s found
;;; (appendix a14.3, a14.12): the directory, four frames, the last ones (memory
;;; comes in 16k words, so they start at a multiple of 4); physical-page-data
;;; below it, two words a frame; the slot bitmap below that, a bit a slot of
;;; the paging partition.  they are zeroed; physical-page-data has the frames
;;; below a-wired-frames wired with their own page, the frames up to the tables
;;; free, and the tables' frames wired with page 0.  then initial-map writes
;;; word 220 and the pointer-type register, and the wired frames are mapped
;;; virtual equal to physical, read/write, taking page-table pages below the
;;; tables.  clobbers m-a, m-b, m-t, m-tem, a-tem1..3, a-paging-tem, vma, md.
BUILD-TABLES
	((m-tem) (byte-field 19. 10.) m-s)	;the frames (2^28 words is 2^18 frames)
	((a-memory-frames) m-tem)
	((m-tem) sub m-tem (a-constant 4))	;the directory's first frame
	((a-paging-tem) m-tem)
	((m-tem) dpb m-tem vma-phys-page-addr-part a-zero)
	((a-directory-window) dpb (m-constant -1) physical-memory-window-bits a-tem)
	((m-tem) a-memory-frames)		;physical-page-data's frames
	((m-tem) dpb m-tem (byte-field 30. 1) a-zero)
	((m-tem) add m-tem (a-constant 1777))
	((m-tem) (byte-field 22. 10.) m-tem)
	((a-tem2) m-tem)
	((m-tem) a-paging-tem)
	((m-tem) sub m-tem a-tem2)
	((a-paging-tem) m-tem)			;its first frame
	((m-tem) dpb m-tem vma-phys-page-addr-part a-zero)
	((a-ppd-window) dpb (m-constant -1) physical-memory-window-bits a-tem)
	((m-tem) a-disk-maximum-pages)		;the bitmap's frames, 32k slots each
	((m-tem) add m-tem (a-constant 77777))
	((m-tem) (byte-field 17. 15.) m-tem)
	((a-tem2) m-tem)
	((m-tem) a-paging-tem)
	((m-tem) sub m-tem a-tem2)
	((a-tables-frame) m-tem)		;its first frame, the tables' first
	((a-table-page-frame) m-tem)
	((m-tem) dpb m-tem vma-phys-page-addr-part a-zero)
	((a-slot-bitmap-window) dpb (m-constant -1) physical-memory-window-bits a-tem)
	((m-b) a-tables-frame)			;zero the tables: fixnum 0
	((a-tem2) (a-constant (byte-value q-data-type dtp-fix)))
build-tables-1
	(call fill-frame)
	((m-b) add m-b (a-constant 1))
	(jump-less-than m-b a-memory-frames build-tables-1)
	((m-b) a-zero)				;physical-page-data
build-tables-2
	((m-tem) dpb m-b (byte-field 31. 1) a-zero)
	((vma) add m-tem a-ppd-window)
	(jump-less-than m-b a-wired-frames build-tables-wired)
	(jump-less-than m-b a-tables-frame build-tables-free)
	(jump-xct-next build-tables-3)
       ((md) (a-constant ppd-wired-table))
build-tables-wired
	(jump-xct-next build-tables-3)
       ((md) dpb m-b ppd-virtual-page-number
		(a-constant (plus (byte-value q-data-type dtp-fix) (byte-value ppd-wired-bit 1))))
build-tables-free
	((md) (a-constant ppd-free))
build-tables-3
	((vma-start-write) vma)
	(illop-if-page-fault)
	((md) (a-constant (plus (byte-value q-data-type dtp-fix) page-entry-no-slot)))
	((vma-start-write) add vma (a-constant 1))
	(illop-if-page-fault)
	((m-b) add m-b (a-constant 1))
	(jump-less-than m-b a-memory-frames build-tables-2)
	(call initial-map)			;word 220, the pointer-type register, the tlb
	((m-a) a-zero)				;the wired frames, virtual equal to physical
build-tables-4
	(call-xct-next find-page-entry-or-make)
       ((a-tem1) dpb m-a vma-phys-page-addr-part a-zero)
	((md) dpb m-a map-physical-page-number (a-constant page-entry-wired))
	((vma-start-write) vma)
	(illop-if-page-fault)
	((m-a) add m-a (a-constant 1))
	(jump-less-than m-a a-wired-frames build-tables-4)
	((a-findcore-scan-pointer) a-wired-frames)
	((a-aging-scan-pointer) a-wired-frames)
	(popj-after-next (a-slot-hint) a-zero)
       ((vma) a-v-nil)

;;; build-region-entries: after a restore, every page of every region gets an
;;; entry holding its slot (a-restore-cold says how slots were laid out; for a
;;; cold load, a-restore-valid-pages is the pages copied), or no slot past
;;; what the band holds: not in core, the region's meta bits.  a page wired
;;; for the restore keeps its slot in its frame's physical-page-data word 1
;;; instead, for cold-swap-in.  each slot taken is marked in the bitmap.  the
;;; walk is disk-save-regionwise-subr's: regions from 0, each to the end of the
;;; page its free pointer is in.  clobbers m-a, m-b, m-t, m-tem, a-tem1..3,
;;; the a-walk- variables, vma, md.
BUILD-REGION-ENTRIES
	((a-walk-region) a-zero)
	((a-walk-index) a-zero)			;the band's pages before this region
bre-region
	((m-a) a-walk-region)
	((m-tem) a-v-region-length)		;the number of regions (the tables are
	((m-tem) sub m-tem a-v-region-origin)	; consecutive)
	(popj-greater-or-equal m-a a-tem)
	((vma-start-read) add m-a a-v-region-bits)
	(illop-if-page-fault)
	((m-tem) (lisp-byte %%region-space-type) md)
	(jump-equal m-tem a-zero bre-next-region)	;free region
	((a-walk-template) selective-deposit md map-meta-bits-high
		(a-constant (plus (byte-value q-data-type dtp-fix) (byte-value map-status-code 1))))
	((vma-start-read) add m-a a-v-region-origin)
	(illop-if-page-fault)
	((m-tem) q-pointer md)
	((a-walk-va) m-tem)
	((vma-start-read) add m-a a-v-region-length)
	(illop-if-page-fault)
	((m-tem) add md (a-constant (eval (1- page-size))))
	((m-tem) vma-page-addr-part m-tem)
	((a-walk-pages) m-tem)			;its pages
	((vma-start-read) add m-a a-v-region-free-pointer)
	(illop-if-page-fault)
	((m-tem) add md (a-constant (eval (1- page-size))))
	((m-tem) vma-page-addr-part m-tem)
	((a-walk-n) m-tem)			;its pages in a saved band
	((a-walk-i) a-zero)
bre-page
	((m-tem) a-walk-i)
	(jump-greater-or-equal m-tem a-walk-pages bre-region-done)
	((a-walk-slot) (a-constant page-entry-no-slot))
	((m-t) a-restore-cold)
	(jump-equal m-t (a-constant 2) bre-inc)
	(jump-not-equal m-t a-zero bre-cold)
	(jump-greater-or-equal m-tem a-walk-n bre-slot)	;past the band's pages: none
	(jump-xct-next bre-slot)
       ((a-walk-slot) add m-tem a-walk-index)	;a saved band: its place in the walk
bre-inc						;an incremental band (disk-restore-incremental):
	(jump-greater-or-equal m-tem a-walk-n bre-slot)	;past the band's pages: none
	((m-t) a-walk-region)
	(jump-less-than m-t (a-constant 3) bre-inc-base)	;the low pages: their base slots
	((m-tem) a-walk-i)			;the mask's bit, at the page's place in the walk
	((m-tem) add m-tem a-walk-index)
	(call-xct-next dsr-mask-bit)
       ((a-mask-k) m-tem)
	(jump-not-equal m-tem a-zero bre-inc-base)	;omitted: the base band's page
	((m-tem) a-inc-next-slot)		;saved: the next of the band's own pages
	((a-walk-slot) m-tem)
	(jump-xct-next bre-slot)
       ((a-inc-next-slot) add m-tem (a-constant 1))
bre-inc-base					;the base band's page of this region and place
	((m-tem) a-walk-region)
	(call-xct-next phys-mem-read)
       ((vma) add m-tem (a-constant base-band-index-origin))
	((m-tem) add md a-walk-i)
	(jump-xct-next bre-slot)
       ((a-walk-slot) m-tem)
bre-cold
	((m-tem) a-walk-va)			;a cold load: its virtual page, if copied
	((m-tem) vma-page-addr-part m-tem)
	(jump-greater-or-equal m-tem a-restore-valid-pages bre-slot)
	((a-walk-slot) m-tem)
bre-slot
	((m-tem) a-walk-slot)
	(jump-equal m-tem (a-constant page-entry-no-slot) bre-entry)
	((a-slot-tem) m-tem)			;taken
	(call slot-bit)
	(call slot-set)
bre-entry
	((m-tem) a-walk-va)
	((m-tem) vma-page-addr-part m-tem)
	(jump-greater-or-equal-unsigned m-tem a-wired-frames bre-paged)
	((m-tem) dpb m-tem (byte-field 31. 1) a-zero)	;wired for the restore: its frame's word 1
	((vma) add m-tem a-ppd-window)
	((m-tem) a-walk-slot)
	((md) q-pointer m-tem (a-constant (byte-value q-data-type dtp-fix)))
	((vma-start-write) add vma (a-constant 1))
	(illop-if-page-fault)
	(jump bre-next-page)
bre-paged
	(call-xct-next find-page-entry-or-make)
       ((a-tem1) a-walk-va)
	((m-tem) a-walk-slot)
	((m-t) dpb m-tem page-entry-slot-low a-walk-template)
	((m-tem) slot-number-high m-tem)
	((md) dpb m-tem page-entry-slot-high a-t)
	((vma-start-write) vma)
	(illop-if-page-fault)
bre-next-page
	((m-tem) a-walk-va)
	((a-walk-va) add m-tem (a-constant (eval page-size)))
	((m-tem) a-walk-i)
	(jump-xct-next bre-page)
       ((a-walk-i) add m-tem (a-constant 1))
bre-region-done
	((m-tem) a-walk-index)
	((a-walk-index) add m-tem a-walk-n)
bre-next-region
	((m-tem) a-walk-region)
	(jump-xct-next bre-region)
       ((a-walk-region) add m-tem (a-constant 1))

;;; ppd-slot: the slot in frame m-b's physical-page-data word 1, in m-tem.
PPD-SLOT
	((m-tem) dpb m-b (byte-field 31. 1) a-zero)
	((vma-start-read) add m-tem a-ppd-window)
	(illop-if-page-fault)
	((vma-start-read) add vma (a-constant 1))
	(illop-if-page-fault)
	(popj-after-next (m-tem) q-pointer md)
       (no-op)

;;; run-wired-pages: the wired frames from m-b up to a-run-end, each run of
;;; frames whose slots follow one another read (a-wired-op 0) or written in
;;; one transfer from or to its slots; a frame with no slot is passed over.
;;; the command list is put in frame a-run-end, which is no wired page then.
;;; clobbers m-a, m-b, m-c, m-t, m-1, m-2, m-tem, vma, md, the a-run- variables.
RUN-WIRED-PAGES
	(popj-greater-or-equal m-b a-run-end)
	(call ppd-slot)
	(jump-not-equal m-tem (a-constant page-entry-no-slot) run-wired-pages-1)
	(jump-xct-next run-wired-pages)
       ((m-b) add m-b (a-constant 1))
run-wired-pages-1
	((a-run-frame) m-b)
	((a-run-slot) m-tem)
	((a-run-count) (a-constant 1))
run-wired-pages-2
	((m-b) add m-b (a-constant 1))
	(jump-greater-or-equal m-b a-run-end run-wired-pages-3)
	(call ppd-slot)
	((m-a) a-run-slot)
	((m-a) add m-a a-run-count)
	(jump-not-equal m-tem a-a run-wired-pages-3)	;its slot does not follow
	((m-tem) a-run-count)
	(jump-xct-next run-wired-pages-2)
       ((a-run-count) add m-tem (a-constant 1))
run-wired-pages-3
	((m-1) a-run-slot)			;the slots' first block
	((m-tem) dpb m-1 (byte-field 30. 2) a-zero)
	((m-1) add m-1 a-tem)			;times 5
	((m-1) add m-1 a-disk-offset)
	((m-2) a-run-count)
	((c-pdl-buffer-pointer-push) m-b)	;the next frame to look at
	((m-b) a-run-frame)
	((m-c) a-run-end)			;the command list
	((m-c) dpb m-c vma-phys-page-addr-part a-zero)
	((m-tem) a-wired-op)
	(call-equal m-tem a-zero cold-disk-read)
	((m-tem) a-wired-op)
	(call-not-equal m-tem a-zero cold-disk-write)
	(jump-xct-next run-wired-pages)
       ((m-b) c-pdl-buffer-pointer-pop)

;;; Initialize physical memory from its swapped-out image on disk.
;;; Low 3 pages, page zero, the system communication area, and
;;; the scratchpad-init-area, already in.  MICRO-CODE-SYMBOL-AREA also in since it
;;; was loaded by microcode loader.
;;; quux revision 14: the entries are made (build-region-entries, or a save
;;; that left every pageable page in its slot).  the band's wired pages, from 4
;;; up to its wired size, are read from their slots into their frames; the
;;; frames wired for the restore past that size become pageable, their pages'
;;; entries not in core with their slots (or status 0 for a page in no region,
;;; its slot freed); the pageable frames are put in service, free; the tlb is
;;; emptied; the system communication area gets the memory size, the tables'
;;; physical addresses and sizes and the commit limit.
COLD-SWAP-IN
	(call get-area-origins)
	((vma-start-read) (a-constant (eval (plus 2000 %sys-com-wired-size))))
	(illop-if-page-fault)
	((m-tem) vma-page-addr-part read-memory-data)
	(call-greater-than m-tem a-wired-frames illop)	;more than were wired for the restore
	((a-paging-tem2) m-tem)			;the band's wired frames
	((a-run-end) m-tem)
	((a-wired-op) a-zero)			;read
	(call-xct-next run-wired-pages)
       ((m-b) (a-constant end-of-micro-code-symbol-area))	;from page 4
	((m-b) a-paging-tem2)
cold-swap-in-unwire
	(jump-greater-or-equal m-b a-wired-frames cold-swap-in-pageable)
	(call ppd-slot)
	((a-walk-slot) m-tem)
	((a-walk-va) dpb m-b vma-phys-page-addr-part a-zero)
	((c-pdl-buffer-pointer-push) m-b)
	(call-xct-next xrgn1)			;its region, or nil
       ((m-a) dpb m-b vma-phys-page-addr-part (a-constant (byte-value q-data-type dtp-fix)))
	(jump-equal m-t a-v-nil cold-swap-in-unwire-none)
	((vma-start-read) add m-t a-v-region-bits)
	(illop-if-page-fault)
	((a-walk-template) selective-deposit md map-meta-bits-high
		(a-constant (plus (byte-value q-data-type dtp-fix) (byte-value map-status-code 1))))
	((m-tem) a-walk-slot)
	((m-t) dpb m-tem page-entry-slot-low a-walk-template)
	((m-tem) slot-number-high m-tem)
	(jump-xct-next cold-swap-in-unwire-write)
       ((a-walk-template) dpb m-tem page-entry-slot-high a-t)
cold-swap-in-unwire-none
	((a-slot-tem) a-walk-slot)		;in no region: no entry, and no slot
	(call free-slot)
	((a-walk-template) (a-constant (byte-value q-data-type dtp-fix)))
cold-swap-in-unwire-write
	(call-xct-next find-page-entry)
       ((a-tem1) a-walk-va)
	((md) a-walk-template)
	((vma-start-write) vma)
	(illop-if-page-fault)
	((m-b) c-pdl-buffer-pointer-pop)
	(jump-xct-next cold-swap-in-unwire)
       ((m-b) add m-b (a-constant 1))
cold-swap-in-pageable
	((m-b) a-paging-tem2)
	((a-wired-frames) m-b)
cold-swap-in-free
	((m-tem) dpb m-b (byte-field 31. 1) a-zero)
	((vma) add m-tem a-ppd-window)
	((md) (a-constant ppd-free))
	((vma-start-write) vma)
	(illop-if-page-fault)
	((md) (a-constant (plus (byte-value q-data-type dtp-fix) page-entry-no-slot)))
	((vma-start-write) add vma (a-constant 1))
	(illop-if-page-fault)
	((m-b) add m-b (a-constant 1))
	(jump-less-than m-b a-table-page-frame cold-swap-in-free)
	((md) a-zero)				;not a window's address
	((vma-write-map) (a-constant write-map-empty))
	;; the system communication area
	((m-tem) a-memory-frames)
	((md) dpb m-tem (byte-field 19. 10.) (a-constant (byte-value q-data-type dtp-fix)))
	((vma-start-write) (a-constant (eval (plus 2000 %sys-com-memory-size))))
	(illop-if-page-fault)
	((md) q-pointer m-tem (a-constant (byte-value q-data-type dtp-fix)))
	((vma-start-write) (a-constant (plus 2000 sys-com-physical-page-data-size)))
	(illop-if-page-fault)
	((m-tem) a-ppd-window)
	((md) (byte-field 28. 0) m-tem (a-constant (byte-value q-data-type dtp-fix)))
	((vma-start-write) (a-constant (plus 2000 sys-com-physical-page-data)))
	(illop-if-page-fault)
	((m-tem) a-slot-bitmap-window)
	((md) (byte-field 28. 0) m-tem (a-constant (byte-value q-data-type dtp-fix)))
	((vma-start-write) (a-constant (plus 2000 sys-com-slot-bitmap)))
	(illop-if-page-fault)
	((m-tem) a-table-page-frame)		;commit: the slots and the pageable frames
	((m-tem) sub m-tem a-wired-frames)
	((m-tem) add m-tem a-disk-maximum-pages)
	((a-commit-limit) m-tem)
	((md) q-pointer m-tem (a-constant (byte-value q-data-type dtp-fix)))
	((vma-start-write) (a-constant (plus 2000 sys-com-commit-limit)))
	(illop-if-page-fault)
	((a-findcore-scan-pointer) a-wired-frames)
	((a-aging-scan-pointer) a-wired-frames)
	((a-slot-hint) a-zero)
	;DROPS IN. INITIALIZE AND START WORLD.
  ;DROPS IN. INITIALIZE AND START WORLD.
BEG0000	((M-FLAGS) (A-CONSTANT (PLUS		;RE-INITIALIZE ALL FLAGS
		(BYTE-VALUE Q-DATA-TYPE DTP-FIX)
		(BYTE-VALUE M-CAR-SYM-MODE 1)
		(BYTE-VALUE M-CAR-NUM-MODE 0)
		(BYTE-VALUE M-CDR-SYM-MODE 1)
		(BYTE-VALUE M-CDR-NUM-MODE 0)
		(BYTE-VALUE M-DONT-SWAP-IN 0)
		(BYTE-VALUE M-TRAP-ENABLE 0)	;MACROCODE WILL TURN ON TRAPS WHEN READY
		(BYTE-VALUE M-MAR-MODE 0)
		(BYTE-VALUE M-PGF-WRITE 0)
		(BYTE-VALUE M-INTERRUPT-FLAG 0)
		(BYTE-VALUE M-SCAVENGE-FLAG 0)
		(BYTE-VALUE M-TRANSPORT-FLAG 0)
		(BYTE-VALUE M-STACK-GROUP-SWITCH-FLAG 0)
		(BYTE-VALUE M-DEFERRED-SEQUENCE-BREAK-FLAG 0)
		(BYTE-VALUE M-METER-STACK-GROUP-ENABLE 0))))
	((M-SB-SOURCE-ENABLE) (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	((A-TV-CURRENT-SHEET) A-V-NIL)		;Forget this cache
	((A-LEXICAL-ENVIRONMENT) A-V-NIL)	;At top level wrt lexical bindings.
	((A-AMEM-EVCP-VECTOR) A-V-NIL)		;Don't write all over memory
	((A-MOUSE-CURSOR-STATE) (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))	;Mouse off
	((A-SCAV-COUNT) SETZ)			;Forget scavenger state
;This seems like an unnecessary waste of time:
;	((A-DISK-SWITCHES) DPB (M-CONSTANT -1)	;Read-compare writes, not reads
;		(BYTE-FIELD 1 1) (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	((A-GC-SWITCHES) (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	((A-INHIBIT-SCHEDULING-FLAG) A-V-TRUE)	;DISABLE SEQUENCE BREAKS
	((A-INHIBIT-SCAVENGING-FLAG) A-V-TRUE)	;GARBAGE COLLECTOR NOT TURNED ON UNTIL LATER
	((A-LCONS-CACHE-AREA) SETZ)		;Forget these caches (disk-restore...)
	((A-SCONS-CACHE-AREA) SETZ)
	((A-PAGE-TRACE-PTR) SETZ)		;SHUT OFF PAGE-TRACE
	((A-METER-GLOBAL-ENABLE) A-V-NIL)	;Turn off metering
	((A-METER-DISK-COUNT) (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	(CALL RESET-MACHINE)			;Reset and turn on interrupts, set up map
;	((VMA-START-READ) (A-CONSTANT 1031))	;FETCH MISCELLANEOUS SCRATCHPAD LOCS
	;; 1024-word pages (contract g2, option (w); appendix a1.9): the scratch
	;; pad init area is page 2, at 4000, not 1000
	((vma-start-read) (a-constant 4031))	;fetch miscellaneous scratchpad locs
	(ILLOP-IF-PAGE-FAULT)
	((A-AMCENT) Q-TYPED-POINTER READ-MEMORY-DATA)
;	((VMA-START-READ) (A-CONSTANT 1021))
	((vma-start-read) (a-constant 4021))
	(ILLOP-IF-PAGE-FAULT)
	((A-CNSADF) Q-TYPED-POINTER READ-MEMORY-DATA)
	((A-BACKGROUND-CONS-AREA) A-CNSADF)
	;; Initially don't hack the extra-pdl area.
	;; The setup of A-FLOATING-ZERO depends on this,
	;; as well as possibly other things.
	((A-NUM-CNSADF) Q-TYPED-POINTER READ-MEMORY-DATA)
	(CALL GET-AREA-ORIGINS)
	;; quux revision 14 (contract g3 revision 14, 10.11): the region floor, as
	;; the band was saved with it (disk-save), or the first unfixed area's
	;; address, the default, if it holds none or one out of range.
	((vma-start-read) (a-constant (plus 2000 sys-com-region-floor)))
	(illop-if-page-fault)
	((m-tem) q-pointer read-memory-data)
	((a-region-floor) a-v-first-unfixed-area)
	(jump-less-than-unsigned m-tem a-v-first-unfixed-area beg-region-floor)
	(jump-greater-or-equal-unsigned m-tem (a-constant 32000000000) beg-region-floor)
	((a-region-floor) q-pointer read-memory-data (a-constant (byte-value q-data-type dtp-fix)))
beg-region-floor
	((M-K) SUB M-ZERO (A-CONSTANT 200))	;FIRST 200 MICRO ENTRIES ARE NOT IN TABLE
	((A-V-MISC-BASE) ADD M-K A-V-MICRO-CODE-SYMBOL-AREA)
	;; quux: block-disk needs no recalibrate after the i/o reset (mit's
	;; did, for the marksman).
	;; Find out where to page off of if we don't know already 
	(CALL-EQUAL A-DISK-OFFSET M-ZERO WARM-READ-GPT)
	;; Clear the unused pages of the PHT and PPD out of the map
;	((MD) DPB (M-CONSTANT -1) (BYTE-FIELD 8 0) A-V-PHYSICAL-PAGE-DATA-END)
	;; quux revision 13: to the end of the 1024-word page, where the map's
	;; entry now ends (y3 rounded to a 256-word map entry)
;	((md) dpb (m-constant -1) (byte-field 10. 0) a-v-physical-page-data-end)
;	((MD) ADD MD (A-CONSTANT 1))		;First page above PPD
	;; the first page above the table's valid entries: their end rounded up
	;; to a page.  the end's page plus one skipped the end's own page when the
	;; end fell on a page boundary, as it does with whole memory boards
	;; (16 of them fill a page of entries), and left it mapped to its frame,
	;; which cold-reinit-ppd gives to paging.
;	((md) a-v-physical-page-data-end)
;	((md) add md (a-constant (eval (1- page-size))))
;	((md) and md (a-constant (eval (minus page-size))))
;	(JUMP-GREATER-OR-EQUAL MD A-V-REGION-ORIGIN BEGCM2)
	;; the table ends at address-space-map's origin; region-origin lies
	;; below page-table-area (cold/qcom.lisp, area-list), so the loop never
	;; ran, and the pages of the table past the memory's entries stayed mapped
	;; to their own frames while cold-reinit-ppd gave those frames to paging,
	;; so at 256 boards 16 frames were reachable both as table pages and as
	;; the pages paged into them.
;	(jump-greater-or-equal md a-v-address-space-map begcm2)
;BEGCM1	((VMA-WRITE-MAP) (A-CONSTANT (BYTE-MASK MAP-WRITE-ENABLE-SECOND-LEVEL-WRITE)))
;	((MD) ADD MD (A-CONSTANT (EVAL PAGE-SIZE)))
;	((md) add md (a-constant map-entry-size))	;every map entry, not every 1024-word page
;	(JUMP-LESS-THAN MD A-V-REGION-ORIGIN BEGCM1)
;	(jump-less-than md a-v-address-space-map begcm1)
;BEGCM2	((MD) A-V-PAGE-TABLE-AREA)
;	((MD) ADD MD A-PHT-INDEX-LIMIT)
;	(JUMP-GREATER-OR-EQUAL MD A-V-PHYSICAL-PAGE-DATA BEGCM4)
;BEGCM3	((VMA-WRITE-MAP) (A-CONSTANT (BYTE-MASK MAP-WRITE-ENABLE-SECOND-LEVEL-WRITE)))
;	((MD) ADD MD (A-CONSTANT (EVAL PAGE-SIZE)))
;	((md) add md (a-constant map-entry-size))	;every map entry, not every 1024-word page
;	(JUMP-LESS-THAN MD A-V-PHYSICAL-PAGE-DATA BEGCM3)
;; quux revision 14: no map to clear; the tables are not areas.
BEGCM4	;; Get A-INITIAL-FEF, A-QTRSTKG, A-QCSTKG, A-QISTKG
;	((VMA) (BYTE-FIELD 9 0) (M-CONSTANT -1)) ;777 ;SCRATCH-PAD-INIT-AREA MINUS ONE
	((vma) (byte-field 11. 0) (m-constant -1)) ;3777 ;scratch-pad-init-area (4000) minus one
	((M-K) (A-CONSTANT (A-MEM-LOC A-SCRATCH-PAD-BEG))) ;FIRST A MEM LOC TO BLT INTO
BEG03	((VMA-START-READ) ADD VMA (A-CONSTANT 1))
	(ILLOP-IF-PAGE-FAULT)
	(DISPATCH TRANSPORT READ-MEMORY-DATA)
	((OA-REG-LOW) DPB M-K OAL-A-DEST A-ZERO)	;DESTINATION
	((A-GARBAGE) READ-MEMORY-DATA)
	(JUMP-NOT-EQUAL-XCT-NEXT M-K (A-CONSTANT (A-MEM-LOC A-SCRATCH-PAD-END)) BEG03)
       ((M-K) ADD M-K (A-CONSTANT 1))
	((VMA-START-READ) A-INITIAL-FEF)	;INDIRECT
	(CHECK-PAGE-READ)
	;; Don't let garbage pointer leak through DISK-RESTORE
	;; There are a lot of these, we only get the ones that are known to cause trouble
	;; There are also the "method subroutine" and "sg calling args" guys
	((A-SELF) DPB Q-ALL-BUT-TYPED-POINTER M-ZERO A-V-NIL)
	((A-SG-PREVIOUS-STACK-GROUP) A-V-NIL)
	(DISPATCH TRANSPORT READ-MEMORY-DATA)
	((A-INITIAL-FEF) READ-MEMORY-DATA)

	(CALL-XCT-NEXT SG-LOAD-STATIC-STATE)	;INITIALIZE PDL LIMITS ETC
       ((A-QCSTKG) A-QISTKG)			;FROM INITIAL STACK-GROUP
	((A-QLBNDP) ADD (M-CONSTANT -1) A-QLBNDO) ;INITIALIZE BINDING PDL POINTER
			; POINTS AT VALID LOCATION, OF WHICH THERE ARENT ANY YET.
	((A-PDL-BUFFER-HEAD) A-ZERO)
	((A-PDL-BUFFER-VIRTUAL-ADDRESS) A-QLPDLO)
	((PDL-BUFFER-POINTER) A-PDL-BUFFER-HEAD)
	((A-PDL-BUFFER-HIGH-WARNING) (A-CONSTANT PDL-BUFFER-HIGH-LIMIT))  ;INITAL STACK
					;HAD BETTER AT LEAST BIG ENUF FOR P.B.
	((C-PDL-BUFFER-POINTER-PUSH) (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	(CALL XFLOAT)
	((A-FLOATING-ZERO) M-T)
	((C-PDL-BUFFER-POINTER) (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX))) ;THIS GOES
					;INTO 0@P
	((C-PDL-BUFFER-POINTER-PUSH) (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	((C-PDL-BUFFER-POINTER-PUSH) (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	((M-A C-PDL-BUFFER-POINTER-PUSH) A-INITIAL-FEF)
	((M-K) Q-DATA-TYPE M-A)
	(CALL-NOT-EQUAL M-K (A-CONSTANT (EVAL DTP-FEF-POINTER)) ILLOP)
	((M-AP) PDL-BUFFER-POINTER)
	((M-PDL-BUFFER-ACTIVE-QS) (A-CONSTANT 4))
	((VMA-START-READ) M-A)
	(CHECK-PAGE-READ)
	(DISPATCH TRANSPORT-HEADER READ-MEMORY-DATA)
	((M-J) (LISP-BYTE %%FEFH-PC) READ-MEMORY-DATA)
BEG06	(CALL-NOT-EQUAL MICRO-STACK-PNTR-AND-DATA 	;CLEAR THE MICRO STACK PNTR (TO -1)
			(A-CONSTANT (PLUS 37_24. 1 (I-MEM-LOC BEG06))) BEG06)
	((MICRO-STACK-DATA-PUSH) A-MAIN-DISPATCH)	;PUSH MAGIC RETURN
	;; quux (contract q5): no unibus; each device's interrupt is enabled on the
	;; register page (the keyboard's 120 <8>, the chaosnet's csr), and mit's
	;; write of 6000 to unibus 766040, which enabled unibus interrupts, is gone.
	;; quux: start the tick, the 60-cycle clock, as the unibus interrupts are
	;; enabled: the clock handler runs only once the machine is set up, as it
	;; did when the band enabled the display's interrupt.
	;; quux revision 10 (contract q11): the tick is timer 0 on the register
	;; page, which has no reset period: reset-machine wrote its 16,667
	;; microseconds to word 111 after reset devices.  word 110 gets 401: on,
	;; periodic (<2> clear, taken at the turn-on), and its interrupt enable
	;; <8>.  destination 3, which q1's tick control was, writes only m at
	;; revision 10 and drives no timer, so it is no longer written.
;	((tick-control) (a-constant 1))
	((md) (a-constant 401))
	((vma-start-write) (a-constant quux-timer-0-control-virtual-address))
	(check-page-write-no-interrupt)
	(JUMP-XCT-NEXT QLENX)			;CALL INITIAL FUNCTION, NEVER RETURNS
       ((M-ERROR-SUBSTATUS) M-ZERO)


;SET-PHT-INDEX-MASK				;Given A-PHT-INDEX-SIZE in M-1
;	((M-2) A-ZERO)				;Build mask with same haulong
;SET-PHT-INDEX-MASK-1
;	((M-2) M+A+1 M-2 A-2)			;Shift left bringing in 1
;	((M-1) (BYTE-FIELD 37 1) M-1)		;Shift right bringing in 0
;	(POPJ-AFTER-NEXT (A-PHT-INDEX-MASK) DPB M-ZERO (BYTE-FIELD 1 0) A-2) ;clear low bit
;       (CALL-NOT-EQUAL M-1 (A-CONSTANT 0) SET-PHT-INDEX-MASK-1)

;set things up so ref to locn in MD will straight map.  This just zonks whatever 2nd level
; block the current first level map entry points to (in practice, this means it will
; gronk entries in block 37, the always all fault block).  This is ok for current purposes, 
; since the 5 bits within block are unique between the disk-regs and the run light, which is
; all we use this for and since another RESET-MACHINE will be done at BEG0000.

;; disk-restore-1 comes here when the run light's fake level-2 entry would
;; overwrite the disk registers' (the same vma<12:8>).  the halt shows this
;; location.
;run-light-shares-disk-slot
;	(call illop)

;COLD-FAKE-L2-MAP
;	((M-T) VMA-PHYS-PAGE-ADDR-PART MD
;		(A-CONSTANT (BYTE-MASK MAP-WRITE-ENABLE-SECOND-LEVEL-WRITE)))
	;; 1024-word pages (contract g2, option (w)): the map entry's physical
	;; page, 256 words
;	((m-t) vma-phys-map-entry-part md
;		(a-constant (byte-mask map-write-enable-second-level-write)))
;	((M-A) (A-CONSTANT 1460))	;RW ACCESS, STATUS=4, NO AREA TRAPS, REP TYPE 0
;	((VMA-WRITE-MAP) DPB M-A MAP-ACCESS-STATUS-AND-META-BITS A-T)
;	(POPJ)


;; quux revision 14: no map to fake (above): the registers and the run
;; light are in the device window.

;;; Decoding the GPT to find a partition.

;;; quux (contract q8): quux's disk carries a gpt, and the machine only reads
;;; it; mit's label (LABL at block 0, its partition table from word 200) is
;;; gone, with its writes to blocks 1, 3 and 5, which now hold gpt entries.
;;; A block is two lbas, so an lba is halved to a block number.  The type
;;; guids' words, as the disk holds them (the guid's mixed-endian bytes as
;;; little-endian words), are muir's docs/quux.md's, checked with sgdisk:
;;;   band (LODn)  24354602160 10160342724 14564524207 27023041220
;;;   PAGE         10624537245 11366203257 10115335662 31024200467
;;; Every entry is scanned.  The first PAGE entry gives A-DISK-OFFSET and
;;; A-DISK-MAXIMUM, and M-Q and M-R as well.  The band is the first band
;;; entry whose name's first four characters are M-4's (packed as the lisp
;;; packs them, first character lowest), or with M-4 zero the first one
;;; with attribute bit 48, the current band; M-4 = -1 finds PAGE only.
;;; The band's start and size go to M-I and M-J, its packed name to M-3,
;;; and A-LOADED-BAND is set as before.  The gpt is read one block at a
;;; time into the page in A-GPT-BUFFER-PAGE, with the ccw at A-GPT-CCW.
;;; A disk is at most 8 GiB, so an lba's high word is not read.
;;; Clobbers M-1, M-2, M-3, M-B, M-C, M-T, M-TEM, M-I, M-J, M-Q, M-R.
cold-read-gpt-page-0			;the cold boot and %disk-restore: page 0,
	((a-gpt-buffer-page) a-zero)	; which the band's first pages overwrite
;	((a-gpt-ccw) (a-constant 777))
	;; 1024-word pages (contract g2, option (w); appendix a1.9): the ccw is
	;; the system communication area's word 377, 2377; the buffer is still
	;; block 0, words 0-377
	((a-gpt-ccw) (a-constant 2377))
cold-read-gpt
	(call-xct-next cold-read-gpt-block)
       ((m-1) a-zero)			;block 0: the protective mbr, and lba 1
	(call-xct-next phys-mem-read)	; the gpt header, from word 200
;       ((vma) dpb m-b vma-phys-page-addr-part (a-constant 200))
;       ((vma) dpb m-b vma-block-part (a-constant 200))	;m-b is a block, 256 words
;	(jump-not-equal md (a-constant 4022243105) gpt-missing)	;"EFI "
;	(call-xct-next phys-mem-read)
;       ((vma) add vma (a-constant 1))
;	(jump-not-equal md (a-constant 12424440520) gpt-missing)	;"PART"
	;; quux revision 13 (appendix a1.11): the gpt is read by the 4-byte
	;; transfer, a page of 4 blocks, block m-1 in its first 400 words, and
	;; every word read carries tag 005: a constant compared with one is a
	;; fixnum (rule 1), a count read from it is tested against zero by an
	;; ordering condition (rule 2), and a byte taken by ldb is untagged (rule
	;; 3).  m-b is the buffer's page frame.
       ((vma) dpb m-b vma-phys-page-addr-part (a-constant 200))
	(jump-not-equal md (a-constant (plus (byte-value q-data-type dtp-fix) 4022243105)) gpt-missing)	;"EFI "
	(call-xct-next phys-mem-read)
       ((vma) add vma (a-constant 1))
	(jump-not-equal md (a-constant (plus (byte-value q-data-type dtp-fix) 12424440520)) gpt-missing)	;"PART"
	(call-xct-next phys-mem-read)
       ((vma) add vma (a-constant 21))	;word 222: the entries' first lba
	(jump-if-bit-set (byte-field 1 0) md gpt-missing)	;not on a block
	((a-gpt-block) (byte-field 37 1) md)
	(call-xct-next phys-mem-read)
       ((vma) add vma (a-constant 2))	;word 224: the number of entries
	((a-gpt-count) md)
	(call-xct-next phys-mem-read)
       ((vma) add vma (a-constant 1))	;word 225: the size of an entry
;	(jump-not-equal md (a-constant 200) gpt-missing)	;must be 128 bytes
	(jump-not-equal md (a-constant (plus (byte-value q-data-type dtp-fix) 200)) gpt-missing)	;must be 128 bytes
	((m-q) setz)			;no PAGE yet
	((m-i) setz)			;no band yet (none starts at block 0)
gpt-next-block				;read the next block of 8 entries
;	(jump-equal m-zero a-gpt-count gpt-done)
	(jump-greater-or-equal m-zero a-gpt-count gpt-done)	;quux revision 13: rule 2
	(call-xct-next cold-read-gpt-block)
       ((m-1) a-gpt-block)
	((a-gpt-block) m+a+1 m-zero a-gpt-block)
;	((m-c) dpb m-b vma-phys-page-addr-part a-zero)	;m-c: the entry
;	((m-c) dpb m-b vma-block-part a-zero)	;m-c: the entry (m-b is a block)
	((m-c) dpb m-b vma-phys-page-addr-part a-zero)	;quux revision 13: m-b is a page
gpt-next-entry				;dispatch on the type's first word
	(call-xct-next phys-mem-read)
       ((vma) m-c)
;	(jump-equal md (a-constant 10624537245) gpt-page-entry)
;	(jump-equal md (a-constant 24354602160) gpt-band-entry)
	(jump-equal md (a-constant (plus (byte-value q-data-type dtp-fix) 10624537245)) gpt-page-entry)
	(jump-equal md (a-constant (plus (byte-value q-data-type dtp-fix) 24354602160)) gpt-band-entry)
gpt-entry-done
	((a-gpt-count) add (m-constant -1) a-gpt-count)
;	(jump-equal m-zero a-gpt-count gpt-done)
	(jump-greater-or-equal m-zero a-gpt-count gpt-done)	;quux revision 13: rule 2
	((m-c) add m-c (a-constant 40))	;32 words an entry
	((m-tem) (byte-field 8. 0) m-c)
	(jump-not-equal m-tem a-zero gpt-next-entry)
	(jump gpt-next-block)

gpt-page-entry				;the type's other three words
	(call-xct-next phys-mem-read)
       ((vma) add m-c (a-constant 1))
	;; quux revision 13: fixnum constants (appendix a1.11, rule 1)
	(jump-not-equal md (a-constant (plus (byte-value q-data-type dtp-fix) 11366203257)) gpt-entry-done)
	(call-xct-next phys-mem-read)
       ((vma) add m-c (a-constant 2))
	(jump-not-equal md (a-constant (plus (byte-value q-data-type dtp-fix) 10115335662)) gpt-entry-done)
	(call-xct-next phys-mem-read)
       ((vma) add m-c (a-constant 3))
	(jump-not-equal md (a-constant (plus (byte-value q-data-type dtp-fix) 31024200467)) gpt-entry-done)
	(jump-not-equal m-q a-zero gpt-entry-done)	;the first PAGE wins
	(call gpt-entry-extent)
	((m-q) m-1)
	(jump-xct-next gpt-entry-done)
       ((m-r) m-2)

gpt-band-entry				;the type's other three words
	(call-xct-next phys-mem-read)
       ((vma) add m-c (a-constant 1))
	;; quux revision 13: fixnum constants (appendix a1.11, rule 1)
	(jump-not-equal md (a-constant (plus (byte-value q-data-type dtp-fix) 10160342724)) gpt-entry-done)
	(call-xct-next phys-mem-read)
       ((vma) add m-c (a-constant 2))
	(jump-not-equal md (a-constant (plus (byte-value q-data-type dtp-fix) 14564524207)) gpt-entry-done)
	(call-xct-next phys-mem-read)
       ((vma) add m-c (a-constant 3))
	(jump-not-equal md (a-constant (plus (byte-value q-data-type dtp-fix) 27023041220)) gpt-entry-done)
	(jump-equal m-4 a-minus-one gpt-entry-done)	;PAGE only
	(jump-not-equal m-i a-zero gpt-entry-done)	;the first match wins
	(jump-not-equal m-4 a-zero gpt-band-named)
	(call-xct-next phys-mem-read)
       ((vma) add m-c (a-constant 15))	;word 13: attributes 63-32
	(jump-if-bit-clear (byte-field 1 16.) md gpt-entry-done)	;bit 48: current
	(call gpt-entry-name)
	(jump gpt-band-found)
gpt-band-named
	(call gpt-entry-name)
	(jump-not-equal m-3 a-4 gpt-entry-done)
gpt-band-found
	(call gpt-entry-extent)
	((m-i) m-1)
	(jump-xct-next gpt-entry-done)
       ((m-j) m-2)

gpt-done
	(jump-equal m-q a-zero gpt-no-page)
	((a-disk-offset) m-q)
	((a-disk-maximum) m-r)
	;; quux revision 13: and its pages, 5 blocks each (make-region's bound)
	((m-1) m-r)
	(call divide-by-blocks-per-page)
	((a-disk-maximum-pages) m-1)
	(popj-equal m-4 a-minus-one)
	(jump-equal m-i a-zero gpt-no-band)
	((a-loaded-band) (byte-field 30 10) m-3 (a-constant (byte-value q-data-type dtp-fix)))
	(popj)

;; read block m-1 of the gpt into the page in a-gpt-buffer-page, left in m-b.
;; quux revision 13 (appendix a1.11): by the 4-byte transfer, a page of 4
;; blocks from block m-1, which is the page's words 0-377.
cold-read-gpt-block
	((m-b) a-gpt-buffer-page)
	((m-2) (a-constant 1))
;	(jump-xct-next cold-disk-read)
	(jump-xct-next cold-disk-read-4-byte)
       ((m-c) a-gpt-ccw)

;; the entry at m-c: its first block in m-1, its size in blocks in m-2.  a
;; partition is whole blocks, so its first lba must be even (its last odd).
gpt-entry-extent
	(call-xct-next phys-mem-read)
       ((vma) add m-c (a-constant 10))	;word 8: the first lba
	(jump-if-bit-set (byte-field 1 0) md gpt-odd-start)
	((m-1) (byte-field 37 1) md)
	(call-xct-next phys-mem-read)
       ((vma) add m-c (a-constant 12))	;word 10: the last lba
	((m-2) (byte-field 37 1) md)	;the last block
	((m-2) sub m-2 a-1)
	((m-2) m+1 m-2)
	(popj)

;; the entry at m-c: the first four characters of its name, utf-16 in words
;; 14 and 15, packed into m-3 as the lisp packs a partition's name.
gpt-entry-name
	(call-xct-next phys-mem-read)
       ((vma) add m-c (a-constant 16))	;word 14: characters 0 and 1
	((m-3) (byte-field 8. 0) md)
	((m-tem) (byte-field 8. 16.) md)
	((m-3) dpb m-tem (byte-field 8. 8.) a-3)
	(call-xct-next phys-mem-read)
       ((vma) add m-c (a-constant 17))	;word 15: characters 2 and 3
	((m-tem) (byte-field 8. 0) md)
	((m-3) dpb m-tem (byte-field 8. 16.) a-3)
	((m-tem) (byte-field 8. 16.) md)
	((m-3) dpb m-tem (byte-field 8. 24.) a-3)
	(popj)

;; the gpt's halts; each shows its own location.
gpt-missing				;no "EFI PART" in lba 1, or entries not
	(call illop)			; 128 bytes or not on a block
gpt-no-page				;no PAGE partition
	(call illop)
gpt-no-band				;no current band (no entry with bit 48),
	(call illop)			; or none of the name asked for
gpt-odd-start				;the partition starts on an odd lba
	(call illop)

;;; Here on a warm boot, we have to read the gpt in order to find where the
;;; PAGE partition is.  But we mustn't bash core page 0.
;;; Also have to set up A-V-PHYSICAL-PAGE-DATA-END based on main memory size
;;; and set up PHT size parameters
;;; quux (contract q8): page 0 is parked in the pdl buffer, which is free
;;; before BEG0000 sets it up, while the gpt is read into it; mit saved
;;; pages 0-2 on blocks 1, 3 and 5, which now hold gpt entries.
WARM-READ-GPT
;	((VMA-START-READ) (A-CONSTANT (EVAL (PLUS 400 %SYS-COM-MEMORY-SIZE))))
	;; 1024-word pages (contract g2, option (w)): the area at 2000; the
	;; table has an entry a 1024-word page (vma-page-addr-part's)
;	((vma-start-read) (a-constant (eval (plus 2000 %sys-com-memory-size))))
;	(ILLOP-IF-PAGE-FAULT)
;	((M-TEM) VMA-PAGE-ADDR-PART READ-MEMORY-DATA)
;	((A-V-PHYSICAL-PAGE-DATA-END) ADD M-TEM A-V-PHYSICAL-PAGE-DATA)
;;	((VMA-START-READ) (A-CONSTANT (EVAL (PLUS 400 %SYS-COM-PAGE-TABLE-SIZE))))
;	((vma-start-read) (a-constant (eval (plus 2000 %sys-com-page-table-size))))
;	(ILLOP-IF-PAGE-FAULT)
;	((M-1) Q-POINTER READ-MEMORY-DATA)
;	((A-PHT-INDEX-LIMIT) M-1)
;	(CALL SET-PHT-INDEX-MASK)
	;; quux revision 14: no hash table to size; the tables' variables are set
	;; at initial-map (warm-tables).
	(call gpt-park-page-0)
	(call-xct-next cold-read-gpt-page-0)	;Go get the gpt
       ((m-4) (m-constant -1))		;PAGE only, not the load partition
	(call gpt-unpark-page-0)
	((A-LOADED-BAND)			;We don't know which band this is
		(A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	(POPJ)

;; physical page 0 to pdl buffer locations 0-377 and back, around the warm
;; boot's reading of the gpt into page 0.
;; quux revision 13 (appendix a1.9): a read of the gpt fills the whole page,
;; 1024 words, so the whole page is parked, pdl buffer locations 0-1777.
gpt-park-page-0
	((pdl-buffer-index) setz)
gpt-park-page-0-1
	(call-xct-next phys-mem-read)
       ((vma) pdl-buffer-index)
	((c-pdl-buffer-index) md)
	((pdl-buffer-index) m+1 pdl-buffer-index)
;	(jump-if-bit-clear (byte-field 1 8.) pdl-buffer-index gpt-park-page-0-1)
	(jump-if-bit-clear (byte-field 1 10.) pdl-buffer-index gpt-park-page-0-1)
	(popj)

gpt-unpark-page-0
	((pdl-buffer-index) setz)
gpt-unpark-page-0-1
	((md) c-pdl-buffer-index)
	(call-xct-next phys-mem-write)
       ((vma) pdl-buffer-index)
	((pdl-buffer-index) m+1 pdl-buffer-index)
;	(jump-if-bit-clear (byte-field 1 8.) pdl-buffer-index gpt-unpark-page-0-1)
	(jump-if-bit-clear (byte-field 1 10.) pdl-buffer-index gpt-unpark-page-0-1)
	(popj)

;;; Lowest level disk routines.
;;; Read or write sequence of blocks from core,
;;; copy contiguous range of blocks from disk to disk.

;The copy buffer must be far enough above INC-BAND-BITMAP-BUFFER-ORIGIN
;to leave room for as large a bitmap as we want to deal with.
;(ASSIGN COPY-BUFFER-CCW-PAGE-ORIGIN 100)
;(ASSIGN COPY-BUFFER-CCW-ORIGIN 40000)	;above * page-size
;(ASSIGN COPY-BUFFER-CCW-BLOCK-LENGTH 1000)
;(ASSIGN COPY-BUFFER-PAGE-ORIGIN 102)
;; quux revision 13: in 1024-word pages, the same words: the ccw list at 40000,
;; page 20, up to 1000 pages at a time, and the buffer from page 21, 42000.
(assign copy-buffer-ccw-page-origin 20)
(assign copy-buffer-ccw-origin 40000)	;above * page-size
(assign copy-buffer-ccw-block-length 1000)
(assign copy-buffer-page-origin 21)

;Copy one sequence of disk blocks into another.
;M-I and M-J now have the start and size of the sequence to be copied from.
;M-Q has the start of the sequence to be copied into.
;M-S has the size of main memory (in words)
;On exit, M-I and M-Q are incremented past the block transfered, and M-J is zero.
;Clobbers M-B, M-C, M-D, M-T, M-1, M-2.

;Uses all of memory starting at COPY-BUFFER-PAGE-ORIGIN.
;The two pages starting at COPY-BUFFER-CCW-PAGE-ORIGIN
;are used for disk CCWs, allowing transfer of up to 512. pages (128k words) at a time.

DISK-COPY-SECTION
;Here M-I, M-Q and M-J are as updated for blocks already transfered.
	;; quux revision 13 (appendix a1.11): m-j counts pages, m-i and m-q are
	;; blocks, 5 a page in the packed transfer; a transfer moves pages.
	(POPJ-EQUAL M-J A-ZERO)			;If done.
;M-D gets max # blocks we can transfer at once.
;	((M-D) VMA-PHYS-PAGE-ADDR-PART M-S)		;Number of pages in main memory
;	((m-d) vma-block-part m-s)		;number of blocks in main memory (1024-word pages)
	((m-d) vma-phys-page-addr-part m-s)	;number of pages in main memory
	((M-D) SUB M-D (A-CONSTANT COPY-BUFFER-PAGE-ORIGIN))	;memory not used for buffer
;Copy at most 1000 pages at a time since that is size of 2-page command list
	(JUMP-LESS-THAN M-D (A-CONSTANT COPY-BUFFER-CCW-BLOCK-LENGTH) DISK-COPY-PART-2)
	((M-D) (A-CONSTANT COPY-BUFFER-CCW-BLOCK-LENGTH))
DISK-COPY-PART-2
	(JUMP-GREATER-OR-EQUAL-XCT-NEXT M-J A-D DISK-COPY-PART-3)
       ((M-2) M-D)				;Number to do this time
	((M-2) M-J)
DISK-COPY-PART-3
	((M-D) M-2)
	((M-B) (A-CONSTANT COPY-BUFFER-PAGE-ORIGIN)) ;First page to use as buffer
	((M-1) M-I)				;Read some in
	((M-C) (A-CONSTANT COPY-BUFFER-CCW-ORIGIN))	;CCW list address
	(CALL COLD-DISK-READ)
	((M-2) M-D)
	((M-1) M-Q)				;Write some out
	(CALL COLD-DISK-WRITE)
;	((M-I) ADD M-I A-D)			;Advance pointers
;	((M-Q) ADD M-Q A-D)
	((m-tem) dpb m-d (byte-field 30. 2) a-zero)	;quux revision 13: the pages' blocks
	((m-tem) add m-tem a-d)
	((m-i) add m-i a-tem)			;advance pointers
	((m-q) add m-q a-tem)
	((M-J) SUB M-J A-D)
	(JUMP DISK-COPY-SECTION)

COLD-DISK-WRITE
	((VMA) A-DISK-RUN-LIGHT)
	((WRITE-MEMORY-DATA) Q-POINTER (M-CONSTANT 0))
	((VMA-START-WRITE) ADD VMA (A-CONSTANT 2))	;Turn off run bar
	((M-T) (A-CONSTANT DISK-WRITE-COMMAND))
;;; Start the disk and wait for completion.
COLD-RUN-DISK
	(CALL START-DISK-N-PAGES)
	((A-DISK-SAVE-PGF-A) M-A)
	((A-DISK-SAVE-PGF-B) M-B)
COLD-AWAIT-DISK
	(CALL DISK-AWAIT-READY)			;Wait for hardware completion
	(CALL DISK-COMPLETION)
	(JUMP-NOT-EQUAL A-DISK-BUSY M-ZERO COLD-AWAIT-DISK)  ;Not done, must have been error
	(POPJ-AFTER-NEXT (M-B) A-DISK-SAVE-PGF-B)
       ((M-A) A-DISK-SAVE-PGF-A)

COLD-DISK-READ-1				;1 page read
	((M-2) (A-CONSTANT 1))
;	((M-C) (A-CONSTANT 777))
	((m-c) (a-constant 2377))	;1024-word pages: sys com area's 377, at 2000 (one block)
COLD-DISK-READ
	;; quux revision 13 (appendix a1.11): pages by the packed transfer
	((VMA) A-DISK-RUN-LIGHT)
	((WRITE-MEMORY-DATA) (M-CONSTANT -1))
	((VMA-START-WRITE) ADD VMA (A-CONSTANT 2))	;Turn on run bar
	((M-T) (A-CONSTANT DISK-READ-COMMAND))
	(JUMP COLD-RUN-DISK)

;; quux revision 13 (appendix a1.11): read m-2 pages by the 4-byte transfer,
;; 4 blocks a page, each word's <31:0> from 4 bytes, tagged 005: the gpt, whose
;; bytes the machine reads as 32-bit words.  arguments as cold-disk-read's.
cold-disk-read-4-byte
	((VMA) A-DISK-RUN-LIGHT)
	((WRITE-MEMORY-DATA) (M-CONSTANT -1))
	((VMA-START-WRITE) ADD VMA (A-CONSTANT 2))	;turn on run bar
	((m-t) (a-constant (plus disk-read-command 1_12.)))
	(JUMP COLD-RUN-DISK)

))