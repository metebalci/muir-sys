(SETQ UC-PUP '(

;;; Ethernet microcode

;;; Additions to DEFMIC
;  (defmic %ether-wakeup 711 (reset-p) t)
;  (defmic %checksum-pup 712 (art-16b-pup start length) t)
;  (defmic %decode-pup 713 (art-byte-pup start length state super-image-p) t)
	

(ASSIGN ETHER-MAX-RETRANSMITS 16.)		;Max times the u-code tries to retransmit
(ASSIGN ETHER-OUTPUT-CSR-ENABLES 101)		;These are not changeable
(ASSIGN UNIBUS-MAP-VIRTUAL-BASE-ADDRESS 77773060)	;Base of the unibus map
(DEF-DATA-FIELD UNIBUS-MAP-BLOCK 4. 10.)	;Map block address in unibus address

(LOCALITY A-MEM)
A-CURRENT-ETHER-RCV-PACKET			;Current packet being received (no data-type)
	((BYTE-VALUE Q-DATA-TYPE DTP-SYMBOL) 0)	;ie NIL
A-ETHER-REGISTER-BASE		(77772100)	;Virtual address of ether net base
A-ETHER-INPUT-CSR-ENABLES	(101)		;Input csr enables initially non-promiscuous
(LOCALITY I-MEM)

;;; Ether net driver
;;; Note that we use M-SBS-CHAOS to enable Ether sequence breaks
;;; Questions: What about lack of room in SYS-COM area?  What about transmission completion?

ETHER-RCV-DONE
	((M-B) A-ETHER-REGISTER-BASE)
	((M-A) A-CURRENT-ETHER-RCV-PACKET)
	((VMA-START-READ) ADD M-B (A-CONSTANT (EVAL %ETHER-INPUT-CSR-OFFSET)))
	(CHECK-PAGE-READ-NO-INTERRUPT)
	;; Save CSR into packet
	((WRITE-MEMORY-DATA) Q-POINTER READ-MEMORY-DATA
			(A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	((VMA-START-WRITE) SUB M-A (A-CONSTANT (EVAL (+ 2 %ETHER-LEADER-CSR))))
	(CHECK-PAGE-WRITE-NO-INTERRUPT)
	(JUMP-IF-BIT-SET (BYTE-FIELD 1 15.) READ-MEMORY-DATA
		ETHER-RCV-RET)		;Error on the receive, just return packet
	;; Save active length
	((VMA-START-READ) ADD M-B (A-CONSTANT (EVAL %ETHER-INPUT-WORD-COUNT-OFFSET)))
	(CHECK-PAGE-READ-NO-INTERRUPT)
	((MD) SUB READ-MEMORY-DATA
		(A-CONSTANT (EVAL (LOGAND 1777 (- ETHER-MAXIMUM-PACKET-LENGTH)))))
	((WRITE-MEMORY-DATA) Q-POINTER MD (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	((VMA-START-WRITE) SUB M-A (A-CONSTANT (EVAL (+ 2 %ETHER-LEADER-ACTIVE-LENGTH))))
	(CHECK-PAGE-WRITE-NO-INTERRUPT)
	;; Install on Receive list
ETHER-RCV-RET
	(CALL-XCT-NEXT ETHER-LIST-PUT)
       ((VMA-START-READ) (A-CONSTANT (EVAL (+ 400 %SYS-COM-ETHER-RECEIVE-LIST))))
	(JUMP-IF-BIT-CLEAR-XCT-NEXT M-SBS-CHAOS ETHER-RCV-NEW-PACKET)	;SB enabled?
       ((MICRO-STACK-DATA-PUSH) (A-CONSTANT (I-MEM-LOC UB-INTR-RET)))
	((INTERRUPT-CONTROL) IOR LOCATION-COUNTER (A-CONSTANT 1_26.))	;request SB
	;; Drops through to reenable the interface

ETHER-RCV-NEW-PACKET
	(CALL-XCT-NEXT ETHER-LIST-GET)
       ((VMA-START-READ) (A-CONSTANT (EVAL (+ 400 %SYS-COM-ETHER-FREE-LIST))))
	((A-CURRENT-ETHER-RCV-PACKET) M-A)
	(JUMP-EQUAL M-A A-V-NIL ETHER-NO-FREE-PACKETS)
	((M-A) ADD M-A (A-CONSTANT 1))
	(CALL-XCT-NEXT ETHER-MAP-PACKET)	;Map in this packet
       ((M-B) (A-CONSTANT (EVAL ETHER-UNIBUS-BLOCK)))
	((VMA-START-WRITE) ADD M-B (A-CONSTANT (EVAL %ETHER-INPUT-BUFFER-POINTER-OFFSET)))
	(CHECK-PAGE-WRITE-NO-INTERRUPT)
	((WRITE-MEMORY-DATA) (A-CONSTANT (EVAL (- ETHER-MAXIMUM-PACKET-LENGTH))))
	((VMA-START-WRITE) ADD M-B (A-CONSTANT (EVAL %ETHER-INPUT-WORD-COUNT-OFFSET)))	
	(CHECK-PAGE-WRITE-NO-INTERRUPT)
	((WRITE-MEMORY-DATA) A-ETHER-INPUT-CSR-ENABLES)
	(POPJ-AFTER-NEXT
		(VMA-START-WRITE) ADD M-B (A-CONSTANT (EVAL %ETHER-INPUT-CSR-OFFSET)))
       (CHECK-PAGE-WRITE-NO-INTERRUPT)

ETHER-NO-FREE-PACKETS
	((WRITE-MEMORY-DATA) SETZ)
	((M-B) A-ETHER-REGISTER-BASE)
	(POPJ-AFTER-NEXT
		(VMA-START-WRITE) ADD M-B (A-CONSTANT (EVAL %ETHER-INPUT-CSR-OFFSET)))
       (CHECK-PAGE-WRITE-NO-INTERRUPT)

;;; Currently transmitting packet got a collision
ETHER-COLLISION
	((VMA-START-READ) (A-CONSTANT (EVAL (+ 400 %SYS-COM-ETHER-TRANSMIT-LIST))))
	(CHECK-PAGE-READ-NO-INTERRUPT)
	((M-A) READ-MEMORY-DATA)		;Current packet
	((VMA-START-READ) SUB M-A (A-CONSTANT (EVAL (+ 2 %ETHER-LEADER-TRANSMIT-COUNT))))
	(CHECK-PAGE-READ-NO-INTERRUPT)		;Get the number of retransmit times
	(JUMP-GREATER-THAN READ-MEMORY-DATA (A-CONSTANT ETHER-MAX-RETRANSMITS)
			ETHER-XMIT-DONE)	;Punt
	((MICRO-STACK-DATA-PUSH) (A-CONSTANT (I-MEM-LOC UB-INTR-RET)))
	((M-B) READ-MEMORY-DATA)
	((WRITE-MEMORY-DATA-START-WRITE) ADD READ-MEMORY-DATA (A-CONSTANT 1))
	(CHECK-PAGE-WRITE-NO-INTERRUPT)
	;; here number of retries is in M-B
	((VMA-START-READ) (A-CONSTANT 77772050))	;Pick up u-sec clock
	(CHECK-PAGE-READ-NO-INTERRUPT)
	((OA-REG-LOW) DPB M-B OAL-BYTL-1 A-ZERO)	;Pick up n bottom bits of it
	((WRITE-MEMORY-DATA) BYTE-INST READ-MEMORY-DATA A-ZERO)
	((VMA) A-ETHER-REGISTER-BASE)
	((VMA-START-WRITE) ADD VMA (A-CONSTANT (EVAL %ETHER-OUTPUT-DELAY-OFFSET)))
	(CHECK-PAGE-WRITE-NO-INTERRUPT)		;Set the delay to that
	((M-A) ADD M-A (A-CONSTANT 1))
	((M-B) (A-CONSTANT (EVAL ETHER-UNIBUS-BLOCK)))	;Use receive map
	(JUMP-XCT-NEXT ETHER-XMIT-PACKET)	;Retransmit packet
       (CALL ETHER-ADDRESS-PACKET)		;But first calculate the address

ETHER-XMIT-DONE
	((MICRO-STACK-DATA-PUSH) (A-CONSTANT (I-MEM-LOC UB-INTR-RET)))
	(CALL-XCT-NEXT ETHER-LIST-GET)		;Read output packet
       ((VMA-START-READ) (A-CONSTANT (EVAL (+ 400 %SYS-COM-ETHER-TRANSMIT-LIST))))
	((M-B) Q-TYPED-POINTER M-A)
	(JUMP-EQUAL M-B A-V-NIL ETHER-NO-XMIT)
	(CALL-XCT-NEXT ETHER-LIST-PUT)
       ((VMA-START-READ) (A-CONSTANT (EVAL (+ 400 %SYS-COM-ETHER-FREE-LIST))))	;Free packet
	(JUMP-IF-BIT-CLEAR M-SBS-CHAOS ETHER-XMIT-NEW-PACKET)		;SB enabled?
	((INTERRUPT-CONTROL) IOR LOCATION-COUNTER (A-CONSTANT 1_26.))	;request SB

;;; Sets up the next packet transfer
ETHER-XMIT-NEW-PACKET
	((VMA-START-READ) (A-CONSTANT (EVAL (+ 400 %SYS-COM-ETHER-TRANSMIT-LIST))))
	(CHECK-PAGE-READ-NO-INTERRUPT)		;Read output packet
	((M-A) Q-TYPED-POINTER READ-MEMORY-DATA)
	(JUMP-EQUAL M-A A-V-NIL ETHER-NO-XMIT)	;No packet available
	((M-A) ADD M-A (A-CONSTANT 1))		;Get pointer to data word
	(CALL-XCT-NEXT ETHER-MAP-PACKET)
       ((M-B) (A-CONSTANT (EVAL (+ ETHER-UNIBUS-BLOCK 2))))	;Transmit is next blocks
;;; Here packet is setup and addressed by map. MD is the unibus address of it
ETHER-XMIT-PACKET
	((VMA-START-WRITE) ADD M-B (A-CONSTANT (EVAL %ETHER-OUTPUT-BUFFER-POINTER-OFFSET)))
	(CHECK-PAGE-WRITE-NO-INTERRUPT)
	((VMA-START-READ) SUB M-A (A-CONSTANT (EVAL (+ 3 %ETHER-LEADER-ACTIVE-LENGTH))))
	(CHECK-PAGE-READ-NO-INTERRUPT)
	((M-A) Q-POINTER READ-MEMORY-DATA A-ZERO)
	((WRITE-MEMORY-DATA) SUB M-ZERO A-A)
	((VMA-START-WRITE) ADD M-B (A-CONSTANT (EVAL %ETHER-OUTPUT-WORD-COUNT-OFFSET)))
	(CHECK-PAGE-WRITE-NO-INTERRUPT)
	((WRITE-MEMORY-DATA) (A-CONSTANT ETHER-OUTPUT-CSR-ENABLES))
	(POPJ-AFTER-NEXT
		(VMA-START-WRITE) ADD M-B (A-CONSTANT (EVAL %ETHER-OUTPUT-CSR-OFFSET)))
       (CHECK-PAGE-WRITE-NO-INTERRUPT)

ETHER-NO-XMIT
	((WRITE-MEMORY-DATA) SETZ)
	((M-B) A-ETHER-REGISTER-BASE)
	(POPJ-AFTER-NEXT
		(VMA-START-WRITE) ADD M-B (A-CONSTANT (EVAL %ETHER-OUTPUT-CSR-OFFSET)))
       (CHECK-PAGE-WRITE-NO-INTERRUPT)

;;; M-A is the page to address, M-B is the unibus block to use
;;; Returns with MD full with the appropriate unibus address to
;;; address the buffer, and M-B points to the ether register base
ETHER-MAP-PACKET
	((VMA-START-READ) M-A)				;Look up physical address
	(CHECK-PAGE-READ-NO-INTERRUPT)
	((MD) VMA)
	((WRITE-MEMORY-DATA) MAP-PHYSICAL-PAGE-NUMBER	;UNIBUS map enable word
		MEMORY-MAP-DATA (A-CONSTANT 140000))
	((VMA-START-WRITE) ADD M-B (A-CONSTANT UNIBUS-MAP-VIRTUAL-BASE-ADDRESS))
	(CHECK-PAGE-WRITE-NO-INTERRUPT)
	;((WRITE-MEMORY-DATA) ADD MD (A-CONSTANT 1))	;--- this has to be wrong ---
	((WRITE-MEMORY-DATA) A-ZERO)			;disable next map, see what happens
	((VMA-START-WRITE) ADD VMA (A-CONSTANT 1))	;Next page
	(CHECK-PAGE-WRITE-NO-INTERRUPT)
ETHER-ADDRESS-PACKET
	((M-B) DPB M-B UNIBUS-MAP-BLOCK (A-CONSTANT 140000))	;Set the page number
	(POPJ-AFTER-NEXT			;Fill in page offset
		(WRITE-MEMORY-DATA) DPB M-A (BYTE-FIELD 8. 2) A-B)
       ((M-B) A-ETHER-REGISTER-BASE)	;Restore this for fun

ETHER-WAKEUP (MISC-INST-ENTRY %ETHER-WAKEUP)
;This version that takes an argument works due to the following convoluted reasons:
;Usual (easy) case: arg=NIL, so first call doesn't happen, second call is comparing
;to M-A=NIL (instead of A-V-NIL) so it works as before.  Reset-P case: arg is non-NIL
;so first call happens.  Usually this finds a packet, sets A-CURRENT-ETHER-RCV-PACKET
;and increments M-A.  Thus they are not equal and the second call does not happen.
;If it doesn't find a packet both are NIL.  This causes the second call to happen,
;but since the first call didn't do much it is unlikely to have any effect anyway.
	((M-A) Q-TYPED-POINTER C-PDL-BUFFER-POINTER-POP)	;get reset-p arg
	(CALL-NOT-EQUAL M-A A-V-NIL ETHER-RCV-NEW-PACKET)	;enable reception if resetting
	(CALL-EQUAL M-A A-CURRENT-ETHER-RCV-PACKET ETHER-RCV-NEW-PACKET) ;or need packet
	((M-B) A-ETHER-REGISTER-BASE)		; Now enable output side
	((VMA-START-READ) ADD M-B (A-CONSTANT (EVAL %ETHER-OUTPUT-CSR-OFFSET)))
	(CHECK-PAGE-READ-NO-INTERRUPT)		;Cant allow interrupts
	(CALL-IF-BIT-CLEAR (BYTE-FIELD 1 6) READ-MEMORY-DATA
		ETHER-XMIT-NEW-PACKET)		;Interrupts off, so try to send new packet
	(JUMP XFALSE)

;;; Take packet off list which has been VMA-START-READ, return it in M-A
;;; M-A can return with NIL in it.  Uses A-INTR-TEM1
ETHER-LIST-GET
	(CHECK-PAGE-READ-NO-INTERRUPT)		;MD gets first buffer on list
	((A-INTR-TEM1) VMA)			;Save address of list header
	((M-A) Q-TYPED-POINTER READ-MEMORY-DATA)
	(POPJ-EQUAL M-A A-V-NIL)		;Return if list empty
	((VMA-START-READ) SUB M-A (A-CONSTANT (EVAL (+ 2 %ETHER-LEADER-THREAD))))
	(CHECK-PAGE-READ-NO-INTERRUPT)		;MD gets next buffer on list
	((WRITE-MEMORY-DATA) Q-TYPED-POINTER READ-MEMORY-DATA)
	(POPJ-AFTER-NEXT (VMA-START-WRITE) A-INTR-TEM1)
       (CHECK-PAGE-WRITE-NO-INTERRUPT)

;;; Put packet in M-A onto list which has been VMA-START-READ
;;; Uses A-INTR-TEM1
ETHER-LIST-PUT
	(CHECK-PAGE-READ-NO-INTERRUPT)		;MD gets present first buffer on list
	((A-INTR-TEM1) VMA)			;Save address of list header
	((WRITE-MEMORY-DATA) Q-TYPED-POINTER READ-MEMORY-DATA)	;Thread onto new first buffer
	((VMA-START-WRITE) SUB M-A (A-CONSTANT (EVAL (+ 2 %ETHER-LEADER-THREAD))))
	(CHECK-PAGE-WRITE-NO-INTERRUPT)
	((WRITE-MEMORY-DATA) Q-TYPED-POINTER M-A)	;Change list header
	(POPJ-AFTER-NEXT (VMA-START-WRITE) A-INTR-TEM1)
       (CHECK-PAGE-WRITE-NO-INTERRUPT)

;ETH-CHECKSUM-PUP checksums a segment of an ART-16B.  The first argument gives the array,
;the second the starting element and the third argument gives the number of elements.
;Example:  (defun fast-checksum-pup (epkt &aux (n (lsh (1- (pup-length epkt)) -1)))
;	     (values (%checksum-pup epkt 2 n) (+ 2 n)))
;
;This is the original Lisp (attributed to MOON).
;Note ucode takes args to specify position in ART-16B.
; (DEFUN CHECKSUM-PUP (EPKT)
;      (DO ((I 2. (1+ I))
;	   (CK 0)
;	   (N (LSH (1- (PUP-LENGTH EPKT)) -1) (1- N)))
;	  ((ZEROP N)
;	   (AND (= CK 177777) (SETQ CK 0))	;Gronk minus zero
;	   (RETURN CK I))			;Return checksum and index in PUP of cksm
;	(SETQ CK (+ CK (AREF EPKT I)))		;1's complement add
;	(AND (BIT-TEST 200000 CK) (SETQ CK (LDB 0020 (1+ CK))))
;	(SETQ CK (DPB CK 0117 (LDB 1701 CK)))))	;16-bit left rotate
;
ETH-CHECKSUM-PUP	(MISC-INST-ENTRY %CHECKSUM-PUP)
   (ERROR-TABLE RESTART ETH-CHECKSUM-PUP)
	(CALL UCODE-AR-1-SETUP)					;set up for array access
   (ERROR-TABLE CALLS-SUB ETH-CHECKSUM-PUP)
	((M-TEM) (LISP-BYTE %%ARRAY-TYPE-FIELD) M-B)		;trap if not 16B
	(CALL-NOT-EQUAL M-TEM (A-CONSTANT (EVAL (LSH ART-16B ARRAY-TYPE-SHIFT))) TRAP)
   (ERROR-TABLE ARGTYP ART-16B M-A 0 ETH-CHECKSUM-PUP %CHECKSUM-PUP)
	((M-1) DPB M-T (BYTE-FIELD 20 20) A-ZERO)		;init M-1 as tho for odd index
	(JUMP-IF-BIT-CLEAR-XCT-NEXT
	  M-Q (BYTE-FIELD 1 0) ETH-CHECKSUM-PUP-EVEN)		;jump if starting even index
       ((M-T) SETZ) 					        ;zero running checksum
;We now ping-pong between the even and odd indices.
;M-1 = 32B memory data, M-T = running checksum
;M-Q = current array index, M-K = final array index
;M-Q is right shifted one place when used to index off of M-E, the array base memory address.
ETH-CHECKSUM-PUP-ODD		;data has been read from the array, use hi order 16 bits
	(JUMP-GREATER-THAN-XCT-NEXT M-Q A-K ETH-CHECKSUM-PUP-EXIT)	;end test
       ((A-TEM1) (BYTE-FIELD 20 20) M-1)    			;checksum left half  
	((M-T) ADD M-T A-TEM1)					;16B two's complement sum
	((A-TEM1) (BYTE-FIELD 1 20) M-T)			;A-TEM1 gets 16B "overflow"
	((M-T) OUTPUT-SELECTOR-LEFTSHIFT-1 ADD M-T A-TEM1)	;end-around carry, M-T gets
								;1's comp sum left shifted
								;lsb gets "don't care" from Q
	((A-TEM1) (BYTE-FIELD 1 20) M-T)			;A-TEM1 gets msb of 1's comp
        ((M-T) SELECTIVE-DEPOSIT M-T (BYTE-FIELD 17 1) A-TEM1)	;M-T gets rotated 16B 1's comp
	((M-Q) ADD M-Q (A-CONSTANT 1))				;increment index
ETH-CHECKSUM-PUP-EVEN		;read data from array, use lo order 16 bits
	(JUMP-GREATER-THAN-XCT-NEXT M-Q A-K ETH-CHECKSUM-PUP-EXIT)	;end test
       ((A-TEM1) (BYTE-FIELD 27 1) M-Q)				;A-TEM1 gets word-wise index
	((VMA-START-READ) ADD M-E A-TEM1)			;M-1 gets entire data word
	(CHECK-PAGE-READ)
	((M-1) READ-MEMORY-DATA)
        ((A-TEM1) (BYTE-FIELD 20 0) M-1)  			;checksum right half
	((M-T) ADD M-T A-TEM1)					;16B two's complement sum
	((A-TEM1) (BYTE-FIELD 1 20) M-T)			;A-TEM1 gets 16B "overflow"
	((M-T) OUTPUT-SELECTOR-LEFTSHIFT-1 ADD M-T A-TEM1)	;end-around carry, M-T gets
								;1's comp sum left shifted
								;lsb gets "don't care" from Q
	((A-TEM1) (BYTE-FIELD 1 20) M-T)			;A-TEM1 gets msb of 1's comp
        ((M-T) SELECTIVE-DEPOSIT M-T (BYTE-FIELD 17 1) A-TEM1)	;M-T gets rotated 16B 1's comp
	(JUMP-XCT-NEXT ETH-CHECKSUM-PUP-ODD)			;loop
       ((M-Q) ADD M-Q (A-CONSTANT 1))				;increment index
ETH-CHECKSUM-PUP-EXIT						;return  M-T = PUP checksum
	(POPJ-NOT-EQUAL-XCT-NEXT M-T (A-CONSTANT 177777))	;test for 16B minus zero
       ((M-T) DPB M-T Q-POINTER					;return fixnum
		(A-CONSTANT (BYTE-VALUE %%Q-DATA-TYPE DTP-FIX)))
	(POPJ-AFTER-NEXT (M-T) DPB M-ZERO Q-POINTER		;return plus zero crock
		(A-CONSTANT (BYTE-VALUE %%Q-DATA-TYPE DTP-FIX)))
       (NO-OP)

;ETH-DECODE-PUP decodes a segment of an array of bytes.  The first argument gives the
;array, the second the starting byte and the third argument gives the number of bytes.
;The fourth argument is an initial state and the fifth if non-nil indicates super-image
;style decoding.  The routine returns a fixnum: the lowest two bits give the final state
;and the remaining bits give the number of decoded bytes.  This is never greater than
;the third argument.  The bytes are decoded in-place, munging the original pup.  The
;initial state should be 0 on the first call, and subsequently should be the final state
;returned from the previous call.  The possible states are:
;	0 - normal decoding
;	1 - return seen (gobbles subsequent line feeds)
;	2 - rubout prefix seen (controls 200 bit of subsequent character)
;[It is expected that this misc instruction will be nicely packaged in macrocode to do
;such things as make a displaced ART-8B into the actual PUP (which is 16B), set its
;length to the number of decoded bytes and return only the final state.  Also sanitize
;input (eg ignore null strings) before this routine sees it.]  Example:
;(defun decode-pup-string (pup-string &optional (state 0) super-image-p)
;  (if (< (string-length pup-string) 1) state	;null strings are no-ops
;      (setq state
;	     (%decode-pup pup-string 0 (array-active-length pup-string) state super-image-p))
;      (store-array-leader (%logldb 0226 state) pup-string 0)	;set new length
;      (%logldb 0002 state)))					;return new state

;The ordering of bytes in a PUP has different "sex" than in a string.  Hence:
(DEF-DATA-FIELD PUP-BYTE-0 10 10)		;first byte in incoming word
(DEF-DATA-FIELD PUP-BYTE-1 10 0)		;second byte in incoming word
(DEF-DATA-FIELD PUP-BYTE-2 10 30)		;third byte in incoming word
(DEF-DATA-FIELD PUP-BYTE-3 10 20)		;last byte in incoming word
;Don't you think these are decorative?
(DEF-DATA-FIELD STRING-BYTE-0 10 0)		;first byte in outgoing word
(DEF-DATA-FIELD STRING-BYTE-1 10 10)		;second byte in outgoing word
(DEF-DATA-FIELD STRING-BYTE-2 10 20)		;third byte in outgoing word
(DEF-DATA-FIELD STRING-BYTE-3 10 30)		;last byte in outgoing word

(DEF-DATA-FIELD 200BIT 1 7)			;msb of byte, & object of unseemly fascination

;Dispatch tables
(LOCALITY D-MEM)	

(START-DISPATCH 2 P-BIT)			;CALL-XCT-NEXT
D-ETH-DECODE-PUP-WRITE				;write appropriate byte in output
	(ETH-DECODE-PUP-WRITE-BYTE-0)
	(ETH-DECODE-PUP-WRITE-BYTE-1)
	(ETH-DECODE-PUP-WRITE-BYTE-2)
	(ETH-DECODE-PUP-WRITE-BYTE-3)
(END-DISPATCH)	

(START-DISPATCH 3)				;JUMP-XCT-NEXT
D-ETH-DECODE-PUP-BYTE				;handle characters 10 to 17
	(ETH-DECODE-PUP-TOGGLE)			;10
	(ETH-DECODE-PUP-TOGGLE)			;11
	(ETH-DECODE-PUP-12 INHIBIT-XCT-NEXT-BIT);12 - inhibits clearing gobble bit
	(P-BIT R-BIT)				;13 - vanilla fall-through
	(ETH-DECODE-PUP-TOGGLE)			;14
	(ETH-DECODE-PUP-15)			;15
	(P-BIT R-BIT)				;16 - vanilla fall-through
	(P-BIT R-BIT)				;17 - vanilla fall-through
(END-DISPATCH)

(LOCALITY I-MEM)
	
;Register usage:
;	M-R	super-image-p argument
;	M-C	internal state: 0=normal, 1=gobble, 200=prefix seen
;		(the 200 bit is frobbed internally while handling the byte)
;	M-I	initial byte index (for length calculation)
;	M-Q	input byte index
;	M-T	output byte index
;	M-1	input word data
;	M-2	output word data
;	M-3	current byte
;M-4, A-TEM1 are temps, other registers are as UCODE-AR-1-SETUP deigns
;
ETH-DECODE-PUP	(MISC-INST-ENTRY %DECODE-PUP)
   (ERROR-TABLE RESTART ETH-DECODE-PUP)
	((M-R) Q-TYPED-POINTER C-PDL-BUFFER-POINTER-POP)	;get super-image-p arg
 	(DISPATCH Q-DATA-TYPE C-PDL-BUFFER-POINTER TRAP-UNLESS-FIXNUM)
   (ERROR-TABLE ARGTYP FIXNUM PP 3 ETH-DECODE-PUP %DECODE-PUP)	;bless initial state
        ((M-C) Q-POINTER C-PDL-BUFFER-POINTER-POP)	;get external format initial state
	(CALL-GREATER-THAN M-C (A-CONSTANT 2) TRAP)	;impossible state
	(JUMP-IF-BIT-CLEAR (BYTE-FIELD 1 1) M-C ETH-DECODE-PUP-SETUP)
	((M-C) (A-CONSTANT 200))		;create internal format for prefix case
ETH-DECODE-PUP-SETUP
	(CALL UCODE-AR-1-SETUP)
   (ERROR-TABLE CALLS-SUB ETH-DECODE-PUP)
	((M-T) M-Q)				;initialize output index at input index
	((M-I) M-Q)				;M-I gets inital index
	((A-TEM1) (BYTE-FIELD 26 2) M-I)	;read in initial word
	((VMA-START-READ) ADD M-E A-TEM1)
	(CHECK-PAGE-READ)
	;punt if there isn't anything to do -- we CALL because exit code pops microstack
	(CALL-GREATER-THAN-XCT-NEXT M-Q A-K ETH-DECODE-PUP-EXIT)
       ((M-2) READ-MEMORY-DATA)			;if M-Q mod 4  0 must restore initial word
	((M-4) (BYTE-FIELD 2 0) M-Q)		;M-4 gets initial read phase to "dispatch" on
	(JUMP-EQUAL-XCT-NEXT M-4 (A-CONSTANT 0) ETH-DECODE-PUP-INITIAL-BYTE-0)	;phase=0
       ((M-1) M-2)				;also setup input register with initial word
	(JUMP-EQUAL M-4 (A-CONSTANT 2) ETH-DECODE-PUP-READ-BYTE-2)	;phase=2 (most likely)
	(JUMP-EQUAL M-4 (A-CONSTANT 1) ETH-DECODE-PUP-READ-BYTE-1)	;phase=1
	(JUMP-EQUAL M-4 (A-CONSTANT 3) ETH-DECODE-PUP-READ-BYTE-3)	;phase=3
;here we're all ready to go -- we loop, sucessively decoding each of the 4 bytes in the word
ETH-DECODE-PUP-READ-BYTE-0
	((A-TEM1) (BYTE-FIELD 26 2) M-Q)	;read in word
	((VMA-START-READ) ADD M-E A-TEM1)
	(CHECK-PAGE-READ)
	((M-1) READ-MEMORY-DATA)
ETH-DECODE-PUP-INITIAL-BYTE-0			;label for first-word-already-read-in bum
	(CALL-XCT-NEXT ETH-DECODE-PUP-BYTE)
       ((M-3) PUP-BYTE-0 M-1)
ETH-DECODE-PUP-READ-BYTE-1
	(CALL-XCT-NEXT ETH-DECODE-PUP-BYTE)
       ((M-3) PUP-BYTE-1 M-1)
ETH-DECODE-PUP-READ-BYTE-2
	(CALL-XCT-NEXT ETH-DECODE-PUP-BYTE)
       ((M-3) PUP-BYTE-2 M-1)
ETH-DECODE-PUP-READ-BYTE-3
	((MICRO-STACK-DATA-PUSH)
		(A-CONSTANT (I-MEM-LOC ETH-DECODE-PUP-READ-BYTE-0)))	;hack return address
	((M-3) PUP-BYTE-3 M-1)						;and just fall thru...
;This gets called to handle each byte and then increment the read pointer M-Q.  If we're
;done, instead of returning, we enter the exit sequence (hence we must pop ustack then).
ETH-DECODE-PUP-BYTE
	(JUMP-EQUAL M-3 (A-CONSTANT 177) ETH-DECODE-PUP-177)		;prefix char
	(JUMP-GREATER-THAN M-3 (A-CONSTANT 17) ETH-DECODE-PUP-VANILLA)	;vanilla char
	(JUMP-LESS-THAN M-3 (A-CONSTANT 10) ETH-DECODE-PUP-VANILLA)	;french vanilla char
	(DISPATCH-XCT-NEXT (BYTE-FIELD 3 0) M-3 D-ETH-DECODE-PUP-BYTE)
;this is the main sequence for most chars, special cases join in at various points	
ETH-DECODE-PUP-VANILLA				;usual thing to do
       ((M-C) DPB M-ZERO (BYTE-FIELD 1 0) A-C)	;clear gobble bit (on LFs this get inhibited)
ETH-DECODE-PUP-BUILD-CHAR			;the Charles Atlas way
	((M-3) SELECTIVE-DEPOSIT M-C 200BIT A-3)	;deposit 200 bit into char
ETH-DECODE-PUP-WRITE-CHAR			;output the thing
	(DISPATCH-CALL-XCT-NEXT (BYTE-FIELD 2 0) M-T D-ETH-DECODE-PUP-WRITE)
       ((M-C) DPB M-ZERO 200BIT A-C)		;clear the 200 bit in state
;paths for all characters rejoin main sequence here	
ETH-DECODE-PUP-BYTE-TAIL			;*ouch*
	(POPJ-NOT-EQUAL-XCT-NEXT M-Q A-K)	;return to main loop if haven't read last byte
       ((M-Q) ADD M-Q (A-CONSTANT 1))		;increment input index
ETH-DECODE-PUP-EXIT				;all done...
	((M-4) (BYTE-FIELD 2 0) M-T)		;set M-4 to phase of write
	(JUMP-EQUAL-XCT-NEXT M-4 (A-CONSTANT 0) ETH-DECODE-PUP-RETURN-COUNT)	;phase=0: noop
       ((M-GARBAGE) MICRO-STACK-POINTER-POP)	;also clean up pending call on ustack
;this is to flush out bytes in M-2 that haven't been written into memory yet -- we try
;to minimally trash the word (up to 16B boundry anyway, odd bytes CAN'T work correctly)
	(JUMP-EQUAL-XCT-NEXT M-4 (A-CONSTANT 3)
		ETH-DECODE-PUP-WRITE-LAST-WORD)	;if phase=3 we just dump M-2
       ((A-TEM1) (BYTE-FIELD 26 2) M-T)		;for phase=1 or 2: read word at current index
	((VMA-START-READ) ADD M-E A-TEM1)
	(CHECK-PAGE-READ)
	((M-2) SELECTIVE-DEPOSIT READ-MEMORY-DATA (BYTE-FIELD 20 20) A-2)	;fix left half
ETH-DECODE-PUP-WRITE-LAST-WORD
	((WRITE-MEMORY-DATA) M-2)		;write out last few bytes in M-2
	((A-TEM1) (BYTE-FIELD 26 2) M-T)
	((VMA-START-WRITE) ADD M-E A-TEM1)
	(CHECK-PAGE-WRITE)
ETH-DECODE-PUP-RETURN-COUNT
;return number of bytes lsh 2, with state (in external format) in least significant bits
	((M-T) SUB M-T A-I)			;length (M-T= final, M-I= initial index)
	((M-T) DPB M-T (BYTE-FIELD 26 2)	;lsh 2, and make fixnum
		(A-CONSTANT (BYTE-VALUE %%Q-DATA-TYPE DTP-FIX)))
	(POPJ-IF-BIT-CLEAR-XCT-NEXT M-C 200BIT)	;non-prefix cases exit
       ((M-T) DPB M-C (BYTE-FIELD 2 0) A-T)	;set state field for normal/gobble cases
	(POPJ-AFTER-NEXT (M-T) DPB M-MINUS-ONE (BYTE-FIELD 1 1) A-T)	;prefix case
       (NO-OP)
;this is the code dispatched into for the really special-case characters
ETH-DECODE-PUP-12				;line feed (falls thru to TOGGLE usually)
	(JUMP-IF-BIT-SET M-C (BYTE-FIELD 1 0) ETH-DECODE-PUP-BYTE-TAIL)	;ignore if gobbling
ETH-DECODE-PUP-TOGGLE				;toggle 200 bit first
	(JUMP-XCT-NEXT ETH-DECODE-PUP-BUILD-CHAR)
       ((M-C) XOR M-C (A-CONSTANT 200))		;toggle 200 bit
ETH-DECODE-PUP-15				;carriage return
	(JUMP-XCT-NEXT ETH-DECODE-PUP-TOGGLE)
       ((M-C) DPB M-MINUS-ONE (BYTE-FIELD 1 0) A-C)	;set gobble bit
ETH-DECODE-PUP-177				;prefix
	(JUMP-IF-BIT-SET-XCT-NEXT M-C 200BIT ETH-DECODE-PUP-WRITE-CHAR)	;prefixxed prefix
       ((M-C) DPB M-ZERO (BYTE-FIELD 1 0) A-C)	;clear gobble bit
	(JUMP-NOT-EQUAL M-R A-V-NIL ETH-DECODE-PUP-WRITE-CHAR)	;super-image mode
	(JUMP-XCT-NEXT ETH-DECODE-PUP-BYTE-TAIL)
       ((M-C) DPB M-MINUS-ONE 200BIT A-C)		;set 200 bit
;dispatch here to handle the various output phases
ETH-DECODE-PUP-WRITE-BYTE-0
	(POPJ-AFTER-NEXT (M-2) DPB M-3 STRING-BYTE-0 A-2)
       ((M-T) ADD M-T (A-CONSTANT 1))
ETH-DECODE-PUP-WRITE-BYTE-1
	(POPJ-AFTER-NEXT (M-2) DPB M-3 STRING-BYTE-1 A-2)
       ((M-T) ADD M-T (A-CONSTANT 1))
ETH-DECODE-PUP-WRITE-BYTE-2
	(POPJ-AFTER-NEXT (M-2) DPB M-3 STRING-BYTE-2 A-2)
       ((M-T) ADD M-T (A-CONSTANT 1))
ETH-DECODE-PUP-WRITE-BYTE-3			;this is the last byte, so write the word
	((WRITE-MEMORY-DATA) DPB M-3 STRING-BYTE-3 A-2)
	((A-TEM1) (BYTE-FIELD 26 2) M-T)
	((VMA-START-WRITE) ADD M-E A-TEM1)
	(CHECK-PAGE-WRITE)
	(POPJ-AFTER-NEXT (M-T) ADD M-T (A-CONSTANT 1))
       (NO-OP)
))