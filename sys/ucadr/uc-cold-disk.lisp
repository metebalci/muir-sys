;-*-MIDAS-*-

(SETQ UC-COLD-DISK '(

RESET-MACHINE
	((A-DISK-BUSY) M-ZERO)			;Forget pending disk operation
	((INTERRUPT-CONTROL) DPB (M-CONSTANT -1)	;Reset the bus interface and I/O devs
		(BYTE-FIELD 1 28.) A-ZERO)
	((M-1) (A-CONSTANT 40))				;Generate RESET for 10 microseconds
RST	(JUMP-NOT-EQUAL-XCT-NEXT M-1 A-ZERO RST)
       ((M-1) SUB M-1 (A-CONSTANT 1))
	((INTERRUPT-CONTROL) DPB (M-CONSTANT -1)	;Clear RESET, set halfword-mode,
		(BYTE-FIELD 1 27.) A-ZERO)		;and enable interrupts
	((MD) SETZ)
	(CALL-XCT-NEXT PHYS-MEM-WRITE)			;Reset bus interface status.
       ((VMA) (A-CONSTANT 17773022))			;Unibus loc 766044
	;Drop into INITIAL-MAP

;LOADING THE INITIAL MAP.
; THE FIRST STEP IS TO ADDRESS THE SYSTEM COMMUNICATION AREA AND FIND
; OUT MUCH VIRTUAL MEMORY SHOULD BE WIRED AND STRAIGHT-MAPPED (%SYS-COM-WIRED-SIZE).
; THE MAP IS THEN SET UP FOR THOSE PAGES.  THE REMAINDER OF VIRTUAL
; SPACE IS MADE "MAP NOT SET UP."  STUFF WILL THEN BE PICKED
; UP OUT OF THE PAGE HASH TABLE.  IT IS ALSO NECESSARY TO SET UP THE
; LAST BLOCK OF LEVEL 2 MAP TO "MAP NOT SET UP (ZERO)".

INITIAL-MAP
	(CALL-XCT-NEXT PHYS-MEM-READ)		;ADDRESS SYSTEM COMMUNICATION AREA
       ((VMA) (A-CONSTANT (PLUS 400 (EVAL %SYS-COM-WIRED-SIZE))))
	((M-A) Q-POINTER MD)			;SAVE NUMBER OF WIRED WORDS
INITIAL-MAP-A	;Enter here with number of words to map in M-A
	;FIRST SET ALL LEVEL 1 MAP TO 37
	((VMA) DPB (M-CONSTANT -1) MAP-WRITE-FIRST-LEVEL-MAP 
		   (A-CONSTANT (BYTE-VALUE MAP-WRITE-ENABLE-FIRST-LEVEL-WRITE 1)))
	((MD) DPB (M-CONSTANT -1) (BYTE-FIELD 1 24.) A-ZERO)
INIMAP1	((MD-WRITE-MAP) SUB MD (A-CONSTANT 20000))
	(JUMP-NOT-EQUAL MD A-ZERO INIMAP1)
	;THEN ZERO LAST BLOCK OF LEVEL 2 MAP
	((MD) A-ZERO)
INIMAP2	((VMA-WRITE-MAP) DPB (M-CONSTANT -1) MAP-WRITE-ENABLE-SECOND-LEVEL-WRITE A-ZERO)
	((MD) ADD MD (A-CONSTANT (EVAL PAGE-SIZE)))
	(JUMP-IF-BIT-CLEAR (BYTE-FIELD 1 13.) MD INIMAP2)
	;NOW SET UP WIRED LEVEL 1 MAP
	((MD) A-ZERO)
	((M-C) DPB (M-CONSTANT -1) MAP-WRITE-ENABLE-FIRST-LEVEL-WRITE A-ZERO)
INIMAP7	((VMA-WRITE-MAP) M-C) 
	((MD) ADD MD (A-CONSTANT 20000))
	(JUMP-LESS-THAN-XCT-NEXT MD A-A INIMAP7)
       ((M-C) ADD M-C (A-CONSTANT (BYTE-VALUE MAP-WRITE-FIRST-LEVEL-MAP 1)))
	((A-SECOND-LEVEL-MAP-REUSE-POINTER-INIT) 
		MAP-WRITE-FIRST-LEVEL-MAP M-C)	;FIRST NON-WIRED
	;THEN SET UP WIRED LEVEL 2 MAP
	((MD) SETZ)
INIMAP3	((VMA-WRITE-MAP) VMA-PHYS-PAGE-ADDR-PART MD	;SELF-ADDRESS
		(A-CONSTANT (PLUS (BYTE-VALUE MAP-ACCESS-CODE 3)   ;RW
				  ;(BYTE-VALUE MAP-STATUS-CODE 0)  ;4 READ/WRITE
				  (BYTE-VALUE MAP-META-BITS 64) ;NOT OLD, NOT EXTRA-PDL, STRUC
				  (BYTE-VALUE MAP-WRITE-ENABLE-SECOND-LEVEL-WRITE 1))))
	((MD) ADD MD (A-CONSTANT (EVAL PAGE-SIZE)))			;NEXT PAGE
	(JUMP-LESS-THAN MD A-A INIMAP3)		;LOOP UNTIL DONE ALL WIRED ADDRESSES
INIM3A	((M-1) (BYTE-FIELD 5 8) MD)		;IF NOT AT EVEN 1ST LVL MAP BOUNDARY...
	(JUMP-EQUAL M-1 A-ZERO INIM3B)		; INITIALIZE REST OF 2ND LVL BLOCK TO
	((VMA-WRITE-MAP)			; MAP NOT SET UP.
	   (A-CONSTANT (BYTE-VALUE MAP-WRITE-ENABLE-SECOND-LEVEL-WRITE 1)))
	(JUMP-XCT-NEXT INIM3A)
       ((MD) ADD MD (A-CONSTANT (EVAL PAGE-SIZE)))

INIM3B						;INITIALIZE REVERSE 1ST LVL MAP
	((A-SECOND-LEVEL-MAP-REUSE-POINTER) A-SECOND-LEVEL-MAP-REUSE-POINTER-INIT)
					;REVERSE 1ST LVL MAP LOCS 40-77
	((WRITE-MEMORY-DATA) M-ZERO)	;VALUE TO GO IN WIRED ENTRIES
	((VMA) (A-CONSTANT 437))	;A-V-SYSTEM-COMMUNICATION-AREA IS 400
INIMAP5	((VMA-START-WRITE) ADD VMA (A-CONSTANT 1))
	(ILLOP-IF-PAGE-FAULT)
	((WRITE-MEMORY-DATA) ADD WRITE-MEMORY-DATA (A-CONSTANT 20000))
	(JUMP-LESS-THAN WRITE-MEMORY-DATA A-A INIMAP6)	;JUMP IF STILL WIRED
	((M-A WRITE-MEMORY-DATA) (M-CONSTANT -1))	;REST OF ENTRYS ARE -1.
INIMAP6	(JUMP-LESS-THAN VMA (A-CONSTANT 477) INIMAP5)
	(POPJ)

;PHYSICAL MEMORY REFERENCING.
;THIS WORKS BY TEMPORARILY CLOBBERING LOCATION 0 OF THE SECOND-LEVEL MAP.
;A-TEM1, A-TEM2, AND A-TEM3 ARE USED AS TEMPORARIES.  ARGS ARE IN VMA AND MD.
PHYS-MEM-READ 
	((A-TEM1) VMA)				;SAVE ADDRESS
	((MD) A-ZERO)				;ADDRESS MAP LOCATION 0@2
	((A-TEM3) MAP-WRITE-SECOND-LEVEL-MAP	;SAVE IT (READ & WRITE THE SAME)
		  MEMORY-MAP-DATA
		  (A-CONSTANT (BYTE-VALUE MAP-WRITE-ENABLE-SECOND-LEVEL-WRITE 1)))
	((VMA-WRITE-MAP) VMA-PHYS-PAGE-ADDR-PART VMA
		(A-CONSTANT (PLUS (BYTE-VALUE MAP-WRITE-ENABLE-SECOND-LEVEL-WRITE 1)
				  (BYTE-VALUE MAP-ACCESS-CODE 3))))
	((VMA-START-READ) DPB M-ZERO		;READ, USING LOC WITHIN PAGE ZERO
		ALL-BUT-VMA-LOW-BITS A-TEM1)
	(ILLOP-IF-PAGE-FAULT)			;FOO, I JUST SET UP THE MAP
	((A-TEM2) READ-MEMORY-DATA)		;GET RESULT TO BE RETURNED
	((MD) A-ZERO)				;RESTORE THE MAP
	((VMA-WRITE-MAP) A-TEM3)
	(POPJ-AFTER-NEXT (VMA) A-TEM1)		;RETURN CORRECT VALUES IN VMA AND MD
       ((MD) A-TEM2)

PHYS-MEM-WRITE 
	((A-TEM1) VMA)				;SAVE ADDRESS
	((A-TEM2) MD)				;AND DATA
	((MD) A-ZERO)				;ADDRESS MAP LOCATION 0@2
	((A-TEM3) MAP-WRITE-SECOND-LEVEL-MAP	;SAVE IT (READ & WRITE THE SAME)
		  MEMORY-MAP-DATA
		  (A-CONSTANT (BYTE-VALUE MAP-WRITE-ENABLE-SECOND-LEVEL-WRITE 1)))
	((VMA-WRITE-MAP) VMA-PHYS-PAGE-ADDR-PART VMA
		(A-CONSTANT (PLUS (BYTE-VALUE MAP-WRITE-ENABLE-SECOND-LEVEL-WRITE 1)
				  (BYTE-VALUE MAP-ACCESS-CODE 3))))
	((MD) A-TEM2)				;RESTORE THE DATA TO BE WRITTEN
	((VMA-START-WRITE) DPB M-ZERO		;WRITE, USING LOC WITHIN PAGE ZERO
		ALL-BUT-VMA-LOW-BITS A-TEM1)
	(ILLOP-IF-PAGE-FAULT)			;FOO, I JUST SET UP THE MAP
	((MD) A-ZERO)				;RESTORE THE MAP
	((VMA-WRITE-MAP) A-TEM3)
	(POPJ-AFTER-NEXT (VMA) A-TEM1)		;RETURN CORRECT VALUES IN VMA AND MD
       ((MD) A-TEM2)

;;; COLD BOOT, %DISK-RESTORE and %DISK-SAVE code

;(%DISK-SAVE main-memory-size high-16-bits-of-partition-name low-16-bits)
;The second and third arguments may be zero to specify the current partition.
;The first arg may also be minus the main-memory-size, to dump an incremental band.
DISK-SAVE (MISC-INST-ENTRY %DISK-SAVE)
	((M-4) PDL-POP)
	((M-4) DPB PDL-POP (BYTE-FIELD 20 20) A-4)
	((M-S) Q-POINTER PDL-TOP)
	((MD) (A-CONSTANT 1000))    ;store code so this band known to be in compressed format
	(JUMP-IF-BIT-CLEAR BOXED-SIGN-BIT M-S DISK-SAVE-1)
	((MD) ADD MD (A-CONSTANT 1))	;or incremental format, whichever it is
	((M-S) SUB M-ZERO A-S)
	((M-S) Q-POINTER M-S)
DISK-SAVE-1
	((VMA-START-WRITE) (A-CONSTANT (EVAL (+ 400 %SYS-COM-BAND-FORMAT))))  ;before swapout
	(ILLOP-IF-PAGE-FAULT)			; so it gets to saved image on disk
	(CALL SWAP-OUT-ALL-PAGES)		;Make sure disk has valid data for all pages.
	(CALL COLD-READ-LABEL-PRESERVING-MEMORY) ;Find the specified partition, and PAGE.
;Set up args for DISK-SAVE-REGIONWISE in case we go straight there.,
	((M-K) A-ZERO)
	((M-AP) M-ZERO)			;region to hack.
	((M-Q) M-I)
	(JUMP-IF-BIT-CLEAR BOXED-SIGN-BIT PDL-POP DISK-SAVE-REGIONWISE)

DISK-SAVE-INCREMENTAL
	((M-B) (A-CONSTANT INC-BAND-BITMAP-BUFFER-PAGE-ORIGIN))
	((M-1) ADD M-I (A-CONSTANT INC-BAND-BASE-DATA-PAGE))
	(CALL COLD-DISK-READ-1)
;Read length in bits of page bit table of this incremental band.
	(CALL-XCT-NEXT PHYS-MEM-READ)
       ((VMA) (A-CONSTANT (PLUS INC-BAND-BITMAP-BUFFER-ORIGIN INC-BAND-BITMAP-SIZE-INDEX)))
	((M-K) MD)
;Get number of pages the bit map occupies.
	((M-2) ADD M-K (A-CONSTANT (EVAL (PLUS (TIMES PAGE-SIZE 32.) -1))))
	((M-2) LDB (BYTE-FIELD 13 15) M-2)
	((M-R) M-2)
;Read in the bit map.
	((M-1) ADD M-I (A-CONSTANT INC-BAND-BITMAP-PAGE))
	((M-B) (A-CONSTANT INC-BAND-BITMAP-BUFFER-PAGE-ORIGIN))
	((M-C) (A-CONSTANT COPY-BUFFER-CCW-ORIGIN))
	(CALL COLD-DISK-READ)
;Save the first three pages into the band.
	((M-1) M-I)
	((M-2) (A-CONSTANT 3))
	((M-B) A-ZERO)
	((M-C) (A-CONSTANT COPY-BUFFER-CCW-ORIGIN))
	(CALL COLD-DISK-WRITE)
;Now save the remaining regions regionwise
;starting after the bitmap pages.
	((M-Q) ADD M-I (A-CONSTANT INC-BAND-BITMAP-PAGE))
	((M-Q) ADD M-Q A-R)
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
DISK-SAVE-REGIONWISE-SUBR
	((A-COPY-BAND-TEM) ADD M-I A-J) ;better not try to write above here.
	((A-COPY-BAND-TEM1) M-I)	;Starting track for dest. band. 
DISK-SR-1
	((VMA-START-READ) ADD M-AP A-V-REGION-BITS)
	(ILLOP-IF-PAGE-FAULT)
	((M-TEM) LDB (LISP-BYTE %%REGION-SPACE-TYPE) MD)
	(JUMP-EQUAL M-TEM A-ZERO DISK-SR-2)	;free region, forget it.
	((VMA-START-READ) ADD M-AP A-V-REGION-ORIGIN)
	(ILLOP-IF-PAGE-FAULT)
	((M-I) LDB VMA-PAGE-ADDR-PART MD)
	((M-I) ADD M-I A-DISK-OFFSET)
	((VMA-START-READ) ADD M-AP A-V-REGION-FREE-POINTER)
	(ILLOP-IF-PAGE-FAULT)
	((MD) ADD MD (A-CONSTANT 377))
	((M-J) LDB VMA-PAGE-ADDR-PART MD)
	((M-TEM) ADD M-Q A-J)
	(CALL-GREATER-OR-EQUAL M-TEM A-COPY-BAND-TEM BAND-NOT-BIG-ENOUGH)
	((M-TEM) ADD M-I A-J)
	((M-TEM) SUB M-TEM A-DISK-OFFSET)
	(CALL-GREATER-OR-EQUAL M-TEM A-DISK-MAXIMUM ILLOP)  ;Band not within paging partition
	(CALL DISK-SAVE-REGION)
DISK-SR-2
	((M-TEM) A-V-REGION-LENGTH)		;depend on REGION-ORIGIN and REGION-LENGTH
	((M-TEM) SUB M-TEM A-V-REGION-ORIGIN)	; being consecutive to determine how
	((M-AP) ADD M-AP (A-CONSTANT 1))	; many regions there are.
	(JUMP-LESS-THAN M-AP A-TEM DISK-SR-1)
	((M-Q) SUB M-Q A-COPY-BAND-TEM1)
	((MD) DPB M-Q (BYTE-FIELD 30 10) A-ZERO) ;Record active size of band.
	((VMA-START-WRITE) (A-CONSTANT (EVAL (PLUS 400 %SYS-COM-VALID-SIZE))))
	(ILLOP-IF-PAGE-FAULT)
	((M-B) (A-CONSTANT 1))			;Core page frame number
	((M-1) M+A+1 M-ZERO A-COPY-BAND-TEM1)	;Disk address, second page of band.
	((M-2) (A-CONSTANT 1))			;one page.
	((M-C) (A-CONSTANT 777))
	(JUMP COLD-DISK-WRITE)		;write it on the band.

;M-I and M-J have origin and size, on disk in the PAGE partition, of a region.
;M-Q has disk address to copy to in band being dumped.
DISK-SAVE-REGION
	(JUMP-EQUAL M-K A-ZERO DISK-SAVE-SECTION)
;Otherwise copy only pages which have 0 in the bitmap.
;Each page copied comes from the PAGE partition according to its page number.
;Thus, the pages not copied do take up space in PAGE.
;But only the copied pages are present in the dumped band.
	((M-1) SUB M-I A-DISK-OFFSET)
	((M-R) ADD M-J A-1)
DISK-SAVE-REGION-LOOP
;M-1 gets virt mem page number of first page to think about.
	((M-1) SUB M-I A-DISK-OFFSET)
	((M-2) (A-CONSTANT 0))
;Search for next page with a 0 in the bit map.  Increment M-1 up to that page number.
	(CALL DISK-RESTORE-BITMAP-SEARCH)
	((M-I) ADD M-1 A-DISK-OFFSET)
;Return now if no page found within this region.
	(POPJ-EQUAL M-1 A-R)
;Find next following page we should not copy.
	((M-2) (A-CONSTANT 1))
	(CALL DISK-RESTORE-BITMAP-SEARCH)
;M-J gets number of consec pages to be copied.
	((M-J) ADD M-1 A-DISK-OFFSET)
	((M-J) SUB M-J A-I)
;Copy them.  Updates M-Q to point at place to copy next page to,
;and M-I to next page to think about.
	(CALL DISK-SAVE-SECTION)
	(JUMP DISK-SAVE-REGION-LOOP)

DISK-SAVE-SECTION
	((M-TEM) ADD M-Q A-J)
	(CALL-GREATER-OR-EQUAL M-TEM A-COPY-BAND-TEM BAND-NOT-BIG-ENOUGH)
	(JUMP DISK-COPY-SECTION)	

BAND-NOT-BIG-ENOUGH	;Destination band not big enuf.  This should have been detected
	(CALL ILLOP)	; before now.  If you proceed this, it should swap your band
	(POPJ)		; back in.

;Make sure all pages are correct on disk.
;Requires that M-S contain the number of words of physical main memory.
;Has the side-effect of destroying the page hash table.
;For %DISK-SAVE, that doesn't matter since we just re-boot anyway.
SWAP-OUT-ALL-PAGES
	((C-PDL-BUFFER-POINTER-PUSH) M-S)
	((M-S) LDB (BYTE-FIELD 16. 8) M-S A-ZERO)	;Number of physical pages.
	((VMA-START-READ) (A-CONSTANT (PLUS 400 (EVAL %SYS-COM-WIRED-SIZE))))
	(ILLOP-IF-PAGE-FAULT)
	((M-T) (BYTE-FIELD 16. 8) READ-MEMORY-DATA)	;Number of wired pages.
	((C-PDL-BUFFER-POINTER-PUSH) M-T)
	((M-T) SUB M-S (A-CONSTANT 1))		;First page to do is highest in core
;Swap out all unwired pages first, using %DELETE-PHYSICAL-PAGE and updating the PHT normally.
SWAP-OUT-ALL-PAGES-1
	((C-PDL-BUFFER-POINTER-PUSH) M-T)	;Save current page
	((C-PDL-BUFFER-POINTER-PUSH) DPB M-T VMA-PAGE-ADDR-PART A-ZERO)  ;arg
	(CALL XDPPG)
	((M-T) SUB C-PDL-BUFFER-POINTER-POP (A-CONSTANT 1))
	(JUMP-GREATER-OR-EQUAL M-T A-ZERO SWAP-OUT-ALL-PAGES-1)
;Now swap out all the wired pages
	((M-A) (A-CONSTANT 200000))		;Direct-map the first 64K
	(CALL INITIAL-MAP-A)
	((M-1) A-DISK-OFFSET)			;Disk address of virtual location 0
	((M-2) C-PDL-BUFFER-POINTER-POP)	;Number of wired pages
	((M-B) M-ZERO)				;Physical memory location 0
	((M-C) DPB M-2 VMA-PAGE-ADDR-PART A-ZERO)	;Put CCW list in high memory
	((M-S) C-PDL-BUFFER-POINTER-POP)
	(JUMP COLD-DISK-WRITE)

COLD-BOOT
	((M-4) A-ZERO)				;0 => use current band.
	(JUMP DISK-RESTORE-1)			;Load world from there

;(%DISK-RESTORE high-16-bits-of-partition-name low-16-bits)
;The first and second arguments may be zero to specify the current partition.
DISK-RESTORE (MISC-INST-ENTRY %DISK-RESTORE)
	((M-4) C-PDL-BUFFER-POINTER-POP)
	((M-4) DPB C-PDL-BUFFER-POINTER-POP (BYTE-FIELD 20 20) A-4)
DISK-RESTORE-1
	((WRITE-MEMORY-DATA) (A-CONSTANT 200000))	;64K to be direct-mapped
	(CALL-XCT-NEXT PHYS-MEM-WRITE)
       ((VMA) (A-CONSTANT (EVAL (PLUS 400 %SYS-COM-WIRED-SIZE))))
	(CALL RESET-MACHINE)
	(CALL-XCT-NEXT COLD-FAKE-L2-MAP)	;set up L2 map to avoid getting to
       ((MD) A-DISK-REGS-BASE)			; page fault handler from AWAIT-DISK,etc
	(CALL-XCT-NEXT COLD-FAKE-L2-MAP)	; before things set up.  Another RESET-MACHINE
       ((MD) A-DISK-RUN-LIGHT)			; will be done at beg0000 eventually anyway.
	(CALL DISK-RECALIBRATE)			;For marksman

;;; Determine size of main memory
	((MD) (A-CONSTANT 40))			;Turn off ERROR-STOP-ENABLE
	(CALL-XCT-NEXT PHYS-MEM-WRITE)		;40 is PROM-DISABLE
       ((VMA) (A-CONSTANT 17773005))		;Unibus 766012
	((M-S) SETZ)
MEM-SIZE-LOOP
	((VMA M-S) ADD M-S (A-CONSTANT 40000))	;Memory comes in 16K increments
	(CALL-XCT-NEXT PHYS-MEM-WRITE)
       ((MD) (A-CONSTANT 37))			;Some 1's, some 0's
	(CALL PHYS-MEM-READ)
	(JUMP-EQUAL MD (A-CONSTANT 37) MEM-SIZE-LOOP)
	;M-S now has the first non-existent location
	((MD) (A-CONSTANT 46))			;Turn ERROR-STOP-ENABLE back on
	(CALL-XCT-NEXT PHYS-MEM-WRITE)		;40 is PROM-DISABLE, 2 is NORMAL speed.
       ((VMA) (A-CONSTANT 17773005))		;Unibus 766012
	(CALL-XCT-NEXT PHYS-MEM-WRITE)		;Clear bus error indicators
       ((VMA) (A-CONSTANT 17773022))		;Unibus 766044
	(CALL COLD-READ-LABEL)			;Find PAGE partition and specified partition.
	((M-1) M-I)				;From start of source band.
	((M-2) (A-CONSTANT 3))			;Core pages 0, 1, and 2
	((M-B) (A-CONSTANT 0))			;..
	((M-C) (A-CONSTANT COPY-BUFFER-CCW-ORIGIN)) ;CCW list after MICRO-CODE-SYMBOL-AREA
	(CALL COLD-DISK-READ)
	(CALL-XCT-NEXT PHYS-MEM-READ)
       ((VMA) (A-CONSTANT (PLUS 400 (EVAL %SYS-COM-BAND-FORMAT))))
	(JUMP-EQUAL MD (A-CONSTANT 1000) DISK-RESTORE-REGIONWISE)  ;compressed partition.
	(JUMP-EQUAL MD (A-CONSTANT 1001) DISK-RESTORE-INCREMENTAL) ;incremental partition.
;Non-compressed band (must be a cold-load band, I think).
	(CALL-XCT-NEXT PHYS-MEM-READ)		;Get useful size of partition, in words
       ((VMA) (A-CONSTANT (PLUS 400 (EVAL %SYS-COM-VALID-SIZE))))
	((M-D) VMA-PAGE-ADDR-PART MD)		;Number of valid pages
	(JUMP-LESS-OR-EQUAL M-J A-D DISK-COPY-PART-1)
	((M-J) M-D)				;M-J is number of pages to copy (min sizes)
DISK-COPY-PART-1
	(CALL-GREATER-THAN M-J A-R ILLOP)	;Not enough room in destination partition
	(CALL DISK-COPY-SECTION)
	(JUMP COLD-SWAP-IN)

DISK-RESTORE-REGIONWISE
	((M-K) A-ZERO)
	((M-I) ADD M-I (A-CONSTANT 3))
	((M-J) SUB M-J (A-CONSTANT 3))
  ;Micro-code-symbol-area has a free pointer
  ;of zero, so is not copied into band.  Therefore, REGION-ORIGIN, etc. start at 3rd page
  ;of band
DISK-RESTORE-REGIONWISE-INC
	(CALL DISK-RESTORE-REGIONWISE-SUBR)
	(JUMP COLD-SWAP-IN)

;M-I and M-J have origin and size of data to restore,
;omitting the first three pages, and the bitmap and base band pages for an inc band.
;M-K has length of bit map saying which pages to omit;
;this bit map is in core starting at INC-BAND-BITMAP-BUFFER-ORIGIN.
;If M-K is 0, restore all the pages from the band.
;Note: for restoring an incremental band, M-I is not really the start of the band;
;it is adjusted upward for the number of special inc band pages we should skip.
;It is adjusted so that it plus 3 is the first block after the bitmap!
;M-J is adjusted down to match.
DISK-RESTORE-REGIONWISE-SUBR
;low 3 pages already in.
;Read in stuff below CCW buffer.  This had better include REGION-ORIGIN, -LENGTH, -BITS,
; -FREE-POINTER.
	((M-B) (A-CONSTANT END-OF-MICRO-CODE-SYMBOL-AREA))
	((M-2) (A-CONSTANT INC-BAND-BITMAP-BUFFER-PAGE-ORIGIN))
	((M-2) SUB M-2 A-B)
	((M-1) M-I)
	((M-C) (A-CONSTANT COPY-BUFFER-CCW-ORIGIN))
	(CALL COLD-DISK-READ)
	((PDL-PUSH) M-K)
	(CALL GET-AREA-ORIGINS)		;set up A-V-REGION-ORIGIN, -LENGTH, -BITS for below
	((M-K) PDL-POP)
;At this point, M-S has words physical memory.   M-I, M-J point to band.
; A-V-REGION-ORGIN, -FREE-POINTER, and -BITS are valid,
; and those arrays are still in main memory and wont get clobbered by calling
; DISK-COPY-SECTION.  A-DISK-OFFSET and A-DISK-MAXIMUM are set.
	((M-AP) (A-CONSTANT 3))			;region to hack.
	((A-COPY-BAND-TEM) ADD M-I A-J) ;better not try to read above here.
DISK-RR-1
	((VMA-START-READ) ADD M-AP A-V-REGION-BITS)
	(ILLOP-IF-PAGE-FAULT)
	((M-TEM) LDB (LISP-BYTE %%REGION-SPACE-TYPE) MD)
	(JUMP-EQUAL M-TEM A-ZERO DISK-RR-2)	;free region, forget it.
	((VMA-START-READ) ADD M-AP A-V-REGION-ORIGIN)
	(ILLOP-IF-PAGE-FAULT)
	((M-Q) LDB VMA-PAGE-ADDR-PART MD)
	((M-Q) ADD M-Q A-DISK-OFFSET)
	((VMA-START-READ) ADD M-AP A-V-REGION-FREE-POINTER)
	(ILLOP-IF-PAGE-FAULT)
	((MD) ADD MD (A-CONSTANT 377))
	((M-J) LDB VMA-PAGE-ADDR-PART MD)
	(CALL-GREATER-OR-EQUAL M-I A-COPY-BAND-TEM ILLOP) ;bandwise EOF.
	((M-TEM) ADD M-Q A-J)
	((M-TEM) SUB M-TEM A-DISK-OFFSET)
	(CALL-GREATER-OR-EQUAL M-TEM A-DISK-MAXIMUM ILLOP)   ;page partition not big enuf
							     ; for this band.
	(CALL DISK-RESTORE-REGION)
	(CALL-GREATER-OR-EQUAL M-I A-COPY-BAND-TEM ILLOP) ;bandwise EOF.
DISK-RR-2
	((M-TEM) A-V-REGION-LENGTH)		;depend on REGION-ORIGIN and REGION-LENGTH
	((M-TEM) SUB M-TEM A-V-REGION-ORIGIN)	; being consecutive to determine how
	((M-AP) ADD M-AP (A-CONSTANT 1))	; many regions there are.
	(JUMP-LESS-THAN M-AP A-TEM DISK-RR-1)
	(POPJ)

;Copy one region from compressed LOD band to PAGE band.
;M-I and M-J have origin and size (on disk) of the region, where it lives in the LOD band.
;M-Q has disk address in PAGE band to copy to.
;M-K has bitmap length or 0 if no bitmap.
;M-S assumed to have phys memory size.
;Clobbers M-1, M-2, M-B, M-C, M-D, M-J, M-T and M-R
;On exit, M-I and M-Q are updated past this region.

DISK-RESTORE-REGION
;If no bitmap, copy entire region,
	(JUMP-EQUAL M-K A-ZERO DISK-COPY-SECTION)
;Otherwise copy only pages which have 0 in the bitmap.
;Each page copied goes into the PAGE partition according to its page number.
;Thus, the pages not copied do take up space in PAGE.
;But only the copied pages are present in the source partition.
	((M-1) SUB M-Q A-DISK-OFFSET)
	((M-R) ADD M-J A-1)
DISK-RESTORE-REGION-LOOP
;M-1 gets virt mem page number of start of this region.
	((M-1) SUB M-Q A-DISK-OFFSET)
	((M-2) (A-CONSTANT 0))
;Search for next page with a 0 in the bit map.  Increment M-1 up to that page number.
	(CALL DISK-RESTORE-BITMAP-SEARCH)
	((M-Q) ADD M-1 A-DISK-OFFSET)
;Return now if no page found within this region.
	(POPJ-EQUAL M-1 A-R)
;Find next following page we should not copy.
	((M-2) (A-CONSTANT 1))
	(CALL DISK-RESTORE-BITMAP-SEARCH)
;M-J gets number of consec pages to be copied.
	((M-J) ADD M-1 A-DISK-OFFSET)
	((M-J) SUB M-J A-Q)
;Copy them.  Updates M-I to point at place to copy next page from.
	(CALL DISK-COPY-SECTION)
	(JUMP DISK-RESTORE-REGION-LOOP)

;Search for a page whose entry in the inc band bitmap in core matches M-2 (zero or one).
;M-1 contains first page to consider.  Page found is returned in M-1.
;M-R contains last page to consider, plus one.
;If nothing is found, returned value in M-1 matches M-R.
DISK-RESTORE-BITMAP-SEARCH
	(POPJ-EQUAL M-1 A-R)
	((VMA) (BYTE-FIELD 23 5) M-1)
	(CALL-XCT-NEXT PHYS-MEM-READ)
       ((VMA) ADD VMA (A-CONSTANT INC-BAND-BITMAP-BUFFER-ORIGIN))
	((VMA) (BYTE-FIELD 5 0) M-1)
	(JUMP-EQUAL VMA A-ZERO DISK-RESTORE-BITMAP-SEARCH-2)
DISK-RESTORE-BITMAP-SEARCH-1
	((MD) (BYTE-FIELD 37 1) MD)
	((VMA) SUB VMA (A-CONSTANT 1))
	(JUMP-NOT-EQUAL VMA A-ZERO DISK-RESTORE-BITMAP-SEARCH-1)
DISK-RESTORE-BITMAP-SEARCH-2
	((MD) (BYTE-FIELD 1 0) MD)
	(POPJ-EQUAL MD A-2)
	((M-1) M+1 M-1)
	(JUMP DISK-RESTORE-BITMAP-SEARCH)

;;; Incremental dumping and loading.

;Index of page in incremental band that identifies the band's base band,
;and also the bitmap size.
(ASSIGN INC-BAND-BASE-DATA-PAGE 3)
;Index in that page of the bitmap size.
(ASSIGN INC-BAND-BITMAP-SIZE-INDEX 10)
;Index of page in incremental band that has a copy of the base band's REGION-FREE-POINTER
(ASSIGN INC-BAND-BASE-FREE-POINTERS-PAGE 4)
;Index of page in incremental band that has start of the band's bitmap.
(ASSIGN INC-BAND-BITMAP-PAGE 5)

;Address and page number of buffer in core used to hold the bitmap.
(ASSIGN INC-BAND-BITMAP-BUFFER-PAGE-ORIGIN 20)
(ASSIGN INC-BAND-BITMAP-BUFFER-ORIGIN 10000)

DISK-RESTORE-INCREMENTAL
	((M-B) (A-CONSTANT INC-BAND-BITMAP-BUFFER-PAGE-ORIGIN))
	((M-1) ADD M-I (A-CONSTANT INC-BAND-BASE-DATA-PAGE))
	(CALL COLD-DISK-READ-1)
;Read length in bits of page bit table of this incremental band.
	(CALL-XCT-NEXT PHYS-MEM-READ)
       ((VMA) (A-CONSTANT (PLUS INC-BAND-BITMAP-BUFFER-ORIGIN INC-BAND-BITMAP-SIZE-INDEX)))
	((PDL-PUSH) MD)
;Read the name of the base partition.
	(CALL-XCT-NEXT PHYS-MEM-READ)
       ((VMA) (A-CONSTANT INC-BAND-BITMAP-BUFFER-ORIGIN))
	((M-4) MD)
	((PDL-PUSH) M-I)
	((PDL-PUSH) M-J)
;Restore the base partition of this partition.
	(CALL COLD-READ-LABEL)			;Find PAGE partition and specified partition.
	((M-1) M-I)				;From start of source band.
	((M-2) (A-CONSTANT 3))			;Core pages 0, 1, and 2
	((M-B) (A-CONSTANT 0))			;..
	((M-C) (A-CONSTANT COPY-BUFFER-CCW-ORIGIN)) ;CCW list after MICRO-CODE-SYMBOL-AREA
	(CALL COLD-DISK-READ)
	(CALL-XCT-NEXT PHYS-MEM-READ)
       ((VMA) (A-CONSTANT (PLUS 400 (EVAL %SYS-COM-BAND-FORMAT))))
	(CALL-NOT-EQUAL MD (A-CONSTANT 1000) ILLOP)  ;Must be a compressed partition.
	((M-I) ADD M-I (A-CONSTANT 3))    ;See DISK-RESTORE-REGIONWISE for this insn.
	((M-J) SUB M-J (A-CONSTANT 3))
	((M-K) A-ZERO)		;Make sure restore as a non-compressed band!
	(CALL DISK-RESTORE-REGIONWISE-SUBR)
;Now check that page 4 of incremental load
;matches the REGION-FREE-POINTER area of the base load.
	((M-B) (A-CONSTANT INC-BAND-BITMAP-BUFFER-PAGE-ORIGIN))
	((M-J) PDL-POP)
	((M-I) PDL-POP)
	((M-1) ADD (A-CONSTANT INC-BAND-BASE-FREE-POINTERS-PAGE) M-I)
	(CALL COLD-DISK-READ-1)
	((M-1) ADD M-MINUS-ONE (A-CONSTANT INC-BAND-BITMAP-BUFFER-ORIGIN))
	((M-2) ADD M-MINUS-ONE A-V-REGION-FREE-POINTER)
	((M-4) (A-CONSTANT (EVAL PAGE-SIZE)))
DISK-RESTORE-INCREMENTAL-CHECK
	(CALL-XCT-NEXT PHYS-MEM-READ)
       ((M-1 VMA) M+1 M-1)
	((M-3) MD)
	(CALL-XCT-NEXT PHYS-MEM-READ)
       ((M-2 VMA) M+1 M-2)
	(CALL-NOT-EQUAL MD A-3 ILLOP)
	((M-4) SUB M-4 (A-CONSTANT 1))
	(JUMP-NOT-EQUAL M-4 A-ZERO DISK-RESTORE-INCREMENTAL-CHECK)
;It matches; go ahead and load the incremental load.
	((M-K) PDL-POP)
;Get number of pages the bit map occupies.
	((M-2) ADD M-K (A-CONSTANT (EVAL (PLUS (TIMES PAGE-SIZE 32.) -1))))
	((M-2) LDB (BYTE-FIELD 13 15) M-2)
	((M-R) M-2)
;Read in the bit map.
	((M-1) ADD M-I (A-CONSTANT INC-BAND-BITMAP-PAGE))
	((M-B) (A-CONSTANT INC-BAND-BITMAP-BUFFER-PAGE-ORIGIN))
	((M-C) (A-CONSTANT COPY-BUFFER-CCW-ORIGIN))
	(CALL COLD-DISK-READ)
;Reread low 3 pages of inc band (they were clobbered by those pages of base band)
	((M-1) M-I)
	((M-B) A-ZERO)
	((M-2) (A-CONSTANT 3))
	((M-C) (A-CONSTANT COPY-BUFFER-CCW-ORIGIN))
	(CALL COLD-DISK-READ)
;Adjust M-I and M-J so that DISK-RESTORE-REGIONWISE will skip the bitmap & base band pages.
	((M-I) ADD M-I (A-CONSTANT INC-BAND-BITMAP-PAGE))
	((M-I) ADD M-I A-R)
	((M-J) SUB M-J (A-CONSTANT INC-BAND-BITMAP-PAGE))
	((M-J) SUB M-J A-R)
;Go restore the inc band.  M-K still has length in bits of bit map.
	(JUMP DISK-RESTORE-REGIONWISE-INC)

;;; Initialize physical memory from its swapped-out image on disk.
;;; Low 3 pages, page zero, the system communication area, and
;;; the scratchpad-init-area, already in.  MICRO-CODE-SYMBOL-AREA also in since it
;;; was loaded by microcode loader.
COLD-SWAP-IN
;;; Read in the rest of wired memory (the sys comm area has its size).
;;; Don't clobber the MICRO-CODE-SYMBOL-AREA
	(CALL-XCT-NEXT PHYS-MEM-READ)
       ((VMA) (A-CONSTANT (PLUS 400 (EVAL %SYS-COM-WIRED-SIZE))))
	((M-2) VMA-PAGE-ADDR-PART READ-MEMORY-DATA)	;Number of wired pages
	((M-C) Q-POINTER READ-MEMORY-DATA)	;Save for later, also put CCW list there
	((M-B) (A-CONSTANT END-OF-MICRO-CODE-SYMBOL-AREA))
	((M-1) ADD M-B A-DISK-OFFSET)
	((M-2) SUB M-2 (A-CONSTANT END-OF-MICRO-CODE-SYMBOL-AREA))
	(CALL COLD-DISK-READ)
;;; Set things up according to actual main memory size
	((WRITE-MEMORY-DATA) Q-POINTER M-S (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	((VMA-START-WRITE) (A-CONSTANT (PLUS 400 (EVAL %SYS-COM-MEMORY-SIZE))))
	(ILLOP-IF-PAGE-FAULT)
;;; Now set up the table of area addresses
	(CALL GET-AREA-ORIGINS)
;;; Reinitialize the page hash table to be completely empty;
;;; permanently wired pages have no entries.
;;; Decide the size of the PHT from the size of main memory; it should
;;; have 4 words in it for each page of main memory (thus will be 1/2 full).
	((M-1) VMA-PAGE-ADDR-PART M-S)		;Number of pages of main memory
	((M-1) ADD M-1 A-1 OUTPUT-SELECTOR-LEFTSHIFT-1)	;Times 4
	((M-1) ADD M-1 (A-CONSTANT (EVAL (1- PAGE-SIZE))))	;Round up to multiple of page
	((M-1) AND M-1 (A-CONSTANT (EVAL (MINUS PAGE-SIZE))))
	((M-TEM) A-V-PHYSICAL-PAGE-DATA)	;But not bigger than available space
	((M-TEM) SUB M-TEM A-V-PAGE-TABLE-AREA)
	(JUMP-LESS-OR-EQUAL M-1 A-TEM COLD-REINIT-PHT-0)
	((M-1) A-TEM)
COLD-REINIT-PHT-0
	((A-PHT-INDEX-LIMIT) M-1)		;Size of page hash table
	((WRITE-MEMORY-DATA) Q-POINTER M-1 (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	((VMA-START-WRITE) (A-CONSTANT (EVAL (PLUS 400 %SYS-COM-PAGE-TABLE-SIZE))))
	(ILLOP-IF-PAGE-FAULT)
	((M-J VMA) ADD M-1 A-V-PAGE-TABLE-AREA)	;Address above PHT
	(CALL SET-PHT-INDEX-MASK)
	((WRITE-MEMORY-DATA) (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))  ;Fill PHT with 0
COLD-REINIT-PHT-2
	((VMA-START-WRITE) SUB VMA (A-CONSTANT 1))
	(ILLOP-IF-PAGE-FAULT)
	(JUMP-GREATER-THAN VMA A-V-PAGE-TABLE-AREA COLD-REINIT-PHT-2)
;;; Initialize physical-page-data.  First make it all completely null.
	((WRITE-MEMORY-DATA) (M-CONSTANT -1))
	((VMA) A-V-REGION-ORIGIN)
COLD-REINIT-PPD-0
	((VMA-START-WRITE) SUB VMA (A-CONSTANT 1))
	(ILLOP-IF-PAGE-FAULT)
	(JUMP-GREATER-THAN VMA A-V-PHYSICAL-PAGE-DATA COLD-REINIT-PPD-0)
;;; Make magic PHYSICAL-PAGE-DATA entries for the wired pages and
;;; free entries in PPD and PHT for the available main memory.
;;; M-J has the upper-bound address of the PHT.  M-I gets same for PPD.
	((M-1) VMA-PAGE-ADDR-PART M-S)			;Number of pages of main memory
	((M-I) ADD M-1 A-V-PHYSICAL-PAGE-DATA)
	((M-R) A-V-RESIDENT-SYMBOL-AREA)		;Address doing
	((M-K) ADD M-S A-R)				;Size of memory
	((M-C) M-J)					;Address for filling in PHT
COLD-REINIT-PPD-1
	(JUMP-GREATER-OR-EQUAL M-R A-V-REGION-GC-POINTER COLD-REINIT-PPD-3)	;free
	(JUMP-GREATER-OR-EQUAL M-R A-V-ADDRESS-SPACE-MAP COLD-REINIT-PPD-2)	;wired
	(JUMP-GREATER-OR-EQUAL M-R A-I COLD-REINIT-PPD-3)	;free part of PPD
	(JUMP-GREATER-OR-EQUAL M-R A-V-PHYSICAL-PAGE-DATA COLD-REINIT-PPD-2)	;wired
	(JUMP-GREATER-OR-EQUAL M-R A-J COLD-REINIT-PPD-3)	;free part of PHT
COLD-REINIT-PPD-2
	((WRITE-MEMORY-DATA) (A-CONSTANT 177777))	;Wired page, no PHT entry
	((VMA-START-WRITE) (BYTE-FIELD 8 8) M-R A-V-PHYSICAL-PAGE-DATA)
	(ILLOP-IF-PAGE-FAULT)
	(JUMP COLD-REINIT-PPD-4)

COLD-REINIT-PPD-3
	((VMA M-C) SUB M-C (A-CONSTANT 4))		;Put in a PHT entry for free page
	(CALL-XCT-NEXT XCPPG1)				;Create physical page
       ((C-PDL-BUFFER-POINTER-PUSH) M-R)		;At this address
COLD-REINIT-PPD-4
	((M-R) ADD M-R (A-CONSTANT (EVAL PAGE-SIZE)))
	(JUMP-LESS-THAN M-R A-K COLD-REINIT-PPD-1)

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
	((VMA-START-READ) (A-CONSTANT 1031))	;FETCH MISCELLANEOUS SCRATCHPAD LOCS
	(ILLOP-IF-PAGE-FAULT)
	((A-AMCENT) Q-TYPED-POINTER READ-MEMORY-DATA)
	((VMA-START-READ) (A-CONSTANT 1021))
	(ILLOP-IF-PAGE-FAULT)
	((A-CNSADF) Q-TYPED-POINTER READ-MEMORY-DATA)
	((A-BACKGROUND-CONS-AREA) A-CNSADF)
	;; Initially don't hack the extra-pdl area.
	;; The setup of A-FLOATING-ZERO depends on this,
	;; as well as possibly other things.
	((A-NUM-CNSADF) Q-TYPED-POINTER READ-MEMORY-DATA)
	(CALL GET-AREA-ORIGINS)
	((M-K) SUB M-ZERO (A-CONSTANT 200))	;FIRST 200 MICRO ENTRIES ARE NOT IN TABLE
	((A-V-MISC-BASE) ADD M-K A-V-MICRO-CODE-SYMBOL-AREA)
	;; If using Marksman disk, must recalibrate after I/O reset
	(CALL DISK-RECALIBRATE)
	;; Find out where to page off of if we don't know already 
	(CALL-EQUAL A-DISK-OFFSET M-ZERO WARM-READ-LABEL)
	;; Clear the unused pages of the PHT and PPD out of the map
	((MD) DPB (M-CONSTANT -1) (BYTE-FIELD 8 0) A-V-PHYSICAL-PAGE-DATA-END)
	((MD) ADD MD (A-CONSTANT 1))		;First page above PPD
	(JUMP-GREATER-OR-EQUAL MD A-V-REGION-ORIGIN BEGCM2)
BEGCM1	((VMA-WRITE-MAP) (A-CONSTANT (BYTE-MASK MAP-WRITE-ENABLE-SECOND-LEVEL-WRITE)))
	((MD) ADD MD (A-CONSTANT (EVAL PAGE-SIZE)))
	(JUMP-LESS-THAN MD A-V-REGION-ORIGIN BEGCM1)
BEGCM2	((MD) A-V-PAGE-TABLE-AREA)
	((MD) ADD MD A-PHT-INDEX-LIMIT)
	(JUMP-GREATER-OR-EQUAL MD A-V-PHYSICAL-PAGE-DATA BEGCM4)
BEGCM3	((VMA-WRITE-MAP) (A-CONSTANT (BYTE-MASK MAP-WRITE-ENABLE-SECOND-LEVEL-WRITE)))
	((MD) ADD MD (A-CONSTANT (EVAL PAGE-SIZE)))
	(JUMP-LESS-THAN MD A-V-PHYSICAL-PAGE-DATA BEGCM3)
BEGCM4	;; Get A-INITIAL-FEF, A-QTRSTKG, A-QCSTKG, A-QISTKG
	((VMA) (BYTE-FIELD 9 0) (M-CONSTANT -1)) ;777 ;SCRATCH-PAD-INIT-AREA MINUS ONE
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
	((MD) (A-CONSTANT 6000))		;Enable Unibus interrupts
	((VMA-START-WRITE) (A-CONSTANT 77773020))  ;Unibus address 766040
	(CHECK-PAGE-WRITE)
	(JUMP-XCT-NEXT QLENX)			;CALL INITIAL FUNCTION, NEVER RETURNS
       ((M-ERROR-SUBSTATUS) M-ZERO)


SET-PHT-INDEX-MASK				;Given A-PHT-INDEX-SIZE in M-1
	((M-2) A-ZERO)				;Build mask with same haulong
SET-PHT-INDEX-MASK-1
	((M-2) M+A+1 M-2 A-2)			;Shift left bringing in 1
	((M-1) (BYTE-FIELD 37 1) M-1)		;Shift right bringing in 0
	(POPJ-AFTER-NEXT (A-PHT-INDEX-MASK) DPB M-ZERO (BYTE-FIELD 1 0) A-2) ;clear low bit
       (CALL-NOT-EQUAL M-1 (A-CONSTANT 0) SET-PHT-INDEX-MASK-1)

;set things up so ref to locn in MD will straight map.  This just zonks whatever 2nd level
; block the current first level map entry points to (in practice, this means it will
; gronk entries in block 37, the always all fault block).  This is ok for current purposes, 
; since the 5 bits within block are unique between the disk-regs and the run light, which is
; all we use this for and since another RESET-MACHINE will be done at BEG0000.

COLD-FAKE-L2-MAP
	((M-T) VMA-PHYS-PAGE-ADDR-PART MD
		(A-CONSTANT (BYTE-MASK MAP-WRITE-ENABLE-SECOND-LEVEL-WRITE)))
	((M-A) (A-CONSTANT 1460))	;RW ACCESS, STATUS=4, NO AREA TRAPS, REP TYPE 0
	((VMA-WRITE-MAP) DPB M-A MAP-ACCESS-STATUS-AND-META-BITS A-T)
	(POPJ)


;;; Decoding the label to find a partition.

;;; Read the disk label and find the main load partition to be used,
;;; and the PAGE partition.  The main load to be used is either the
;;; one whose name is in M-4, or the current one if M-4 is zero.
;;; Also set A-LOADED-BAND for later macrocode use.
COLD-READ-LABEL 
	((M-B) A-ZERO)				;Core page 0
	((M-1) A-ZERO)				;Disk page 0
	(CALL COLD-DISK-READ-1)
	((M-B) (A-CONSTANT 2))			;Core page 2
	((M-1) ADD M-B A-B)			;Disk page 4
	(CALL COLD-DISK-READ-1)
;Cannot use COLD-DISK-READ-1 next since that puts the CCW in 777
	((M-B) (A-CONSTANT 1))			;Core page 1
	((M-1) ADD M-B A-B)			;Disk page 2
	((M-2) (A-CONSTANT 1))
	((M-C) (A-CONSTANT 170))	;Words 170-177 in disk label not used!
	(CALL COLD-DISK-READ-1)
	;Location 7 contains the name of the main load partition.
	;Location 200 contains the partition table.
	;We must also find the PAGE partition and set up A-DISK-OFFSET and A-DISK-MAXIMUM
	(CALL-XCT-NEXT PHYS-MEM-READ)		; Read the number of blocks per track
       ((VMA) (A-CONSTANT 4))
	((A-DISK-BLOCKS-PER-TRACK) Q-POINTER READ-MEMORY-DATA
			(A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	(CALL-XCT-NEXT PHYS-MEM-READ)		; Read the number of heads
       ((VMA) (A-CONSTANT 3))
	((Q-R) READ-MEMORY-DATA)		; Get number of blocks per cylinder
	(CALL-XCT-NEXT MPY)			; Blocks/track * tracks/cylinder
       ((M-1) DPB M-ZERO Q-ALL-BUT-POINTER A-DISK-BLOCKS-PER-TRACK)
	((A-DISK-BLOCKS-PER-CYLINDER) Q-POINTER Q-R
			(A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	(CALL-XCT-NEXT COLD-FIND-PARTITION)
       ((M-3) (A-CONSTANT 10521640520))		; PAGE = 105 107 101 120 = 10521640520
	((A-DISK-OFFSET) M-I)
	((A-DISK-MAXIMUM) M-J)
	((M-Q) M-I)				;M-Q, M-R point to PAGE partition
	((M-R) M-J)
	(CALL-XCT-NEXT PHYS-MEM-READ)
       ((VMA) (A-CONSTANT 7))
	((M-3) READ-MEMORY-DATA)		;Current Band
	(JUMP-EQUAL M-4 A-ZERO COLD-READ-LABEL-1)
	((M-3) M-4)
COLD-READ-LABEL-1
	((A-LOADED-BAND) (BYTE-FIELD 30 10) M-3 (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	(CALL COLD-FIND-PARTITION)		;Set up M-I, M-J for partition to load.
	(POPJ)

;Does not preserve memory location 777, which is used for CCWs.
COLD-READ-LABEL-PRESERVING-MEMORY
	((M-B) A-ZERO)				;Core address
	((M-1) M+A+1 M-B A-B)			;Disk address
	((M-2) (A-CONSTANT 1))			;1 block
	((M-C) (A-CONSTANT 777))
	(CALL COLD-DISK-WRITE)			;Save page 0
	((M-B) (A-CONSTANT 1))			;Core address
	((M-1) M+A+1 M-B A-B)			;Disk address
	((M-2) (A-CONSTANT 1))			;1 block
	((M-C) (A-CONSTANT 777))
	(CALL COLD-DISK-WRITE)			;Save page 1
	((M-B) (A-CONSTANT 2))			;Core address
	((M-1) M+A+1 M-B A-B)			;Disk address
	((M-2) (A-CONSTANT 1))			;1 block
	((M-C) (A-CONSTANT 777))
	(CALL COLD-DISK-WRITE)			;Save page 2
	(CALL COLD-READ-LABEL)
	((M-B) A-ZERO)		;Restore page 0 from disk block 1
	((M-1) M+A+1 M-B A-B)
	(CALL COLD-DISK-READ-1)
	((M-B) (A-CONSTANT 1))	;Restore page 1 from disk block 3
	((M-1) M+A+1 M-B A-B)
	(CALL COLD-DISK-READ-1)
	((M-B) (A-CONSTANT 2))	;Restore page 2 from disk block 5
	((M-1) M+A+1 M-B A-B)
	(JUMP COLD-DISK-READ-1)

;;; Here on a warm boot, we have to read the label in order to find where the
;;; PAGE partition is.  But we mustn't bash core page 0.
;;; Also have to set up A-V-PHYSICAL-PAGE-DATA-END based on main memory size
;;; and set up PHT size parameters
WARM-READ-LABEL
	((VMA-START-READ) (A-CONSTANT (EVAL (PLUS 400 %SYS-COM-MEMORY-SIZE))))
	(ILLOP-IF-PAGE-FAULT)
	((M-TEM) VMA-PAGE-ADDR-PART READ-MEMORY-DATA)
	((A-V-PHYSICAL-PAGE-DATA-END) ADD M-TEM A-V-PHYSICAL-PAGE-DATA)
	((VMA-START-READ) (A-CONSTANT (EVAL (PLUS 400 %SYS-COM-PAGE-TABLE-SIZE))))
	(ILLOP-IF-PAGE-FAULT)
	((M-1) Q-POINTER READ-MEMORY-DATA)
	((A-PHT-INDEX-LIMIT) M-1)
	(CALL SET-PHT-INDEX-MASK)
	(CALL-XCT-NEXT COLD-READ-LABEL-PRESERVING-MEMORY)	;Go get the label
       ((M-4) SETZ)				;not worrying about load partition
	((A-LOADED-BAND)			;We don't know which band this is
		(A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	(POPJ)

;;; With the label in location 0, this routine finds a partition whose name is in M-3
;;; and returns its start and size (in blocks) in M-I and M-J.
COLD-FIND-PARTITION
	(CALL-XCT-NEXT PHYS-MEM-READ)		;Get number of partitions
       ((VMA) (A-CONSTANT 200))
	((M-I) READ-MEMORY-DATA)
	(CALL-XCT-NEXT PHYS-MEM-READ)		;Get words per partition
       ((VMA) ADD VMA (A-CONSTANT 1))
	((M-J) READ-MEMORY-DATA)
	((VMA) ADD VMA (A-CONSTANT 1))
COLD-FIND-PART-LOOP
	(CALL-EQUAL M-I A-ZERO ILLOP)		;Out of partitions, not found, die
	(CALL PHYS-MEM-READ)			;Get name of a partition
	((M-I) SUB M-I (A-CONSTANT 1))
	(JUMP-NOT-EQUAL-XCT-NEXT READ-MEMORY-DATA A-3 COLD-FIND-PART-LOOP)
       ((VMA) ADD VMA A-J)
	((VMA) SUB VMA A-J)
	(CALL-XCT-NEXT PHYS-MEM-READ)		;Found it, get start and size
       ((VMA) ADD VMA (A-CONSTANT 1))
	((M-I) READ-MEMORY-DATA)
	(CALL-XCT-NEXT PHYS-MEM-READ)
       ((VMA) ADD VMA (A-CONSTANT 1))
	(POPJ-AFTER-NEXT (M-J) READ-MEMORY-DATA)
       (NO-OP)

;;; Lowest level disk routines.
;;; Read or write sequence of blocks from core,
;;; copy contiguous range of blocks from disk to disk.

;The copy buffer must be far enough above INC-BAND-BITMAP-BUFFER-ORIGIN
;to leave room for as large a bitmap as we want to deal with.
(ASSIGN COPY-BUFFER-CCW-PAGE-ORIGIN 100)
(ASSIGN COPY-BUFFER-CCW-ORIGIN 40000)	;above * page-size
(ASSIGN COPY-BUFFER-CCW-BLOCK-LENGTH 1000)
(ASSIGN COPY-BUFFER-PAGE-ORIGIN 102)

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
	(POPJ-EQUAL M-J A-ZERO)			;If done.
;M-D gets max # blocks we can transfer at once.
	((M-D) VMA-PHYS-PAGE-ADDR-PART M-S)		;Number of pages in main memory
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
	((M-I) ADD M-I A-D)			;Advance pointers
	((M-Q) ADD M-Q A-D)
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
	(CALL DISK-RECALIBRATE-WAIT)		;Wait for hardware completion
	(CALL DISK-COMPLETION)
	(JUMP-NOT-EQUAL A-DISK-BUSY M-ZERO COLD-AWAIT-DISK)  ;Not done, must have been error
	(POPJ-AFTER-NEXT (M-B) A-DISK-SAVE-PGF-B)
       ((M-A) A-DISK-SAVE-PGF-A)

COLD-DISK-READ-1				;1 page read
	((M-2) (A-CONSTANT 1))
	((M-C) (A-CONSTANT 777))
COLD-DISK-READ
	((VMA) A-DISK-RUN-LIGHT)
	((WRITE-MEMORY-DATA) (M-CONSTANT -1))
	((VMA-START-WRITE) ADD VMA (A-CONSTANT 2))	;Turn on run bar
	((M-T) (A-CONSTANT DISK-READ-COMMAND))
	(JUMP COLD-RUN-DISK)

))