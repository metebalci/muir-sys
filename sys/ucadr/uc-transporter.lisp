;-*-Mode:Midas-*-

(SETQ UC-TRANSPORTER '(
;;; THE TRANSPORTER

;		"Energize!"
;		     -- J. T. Kirk
;
;THIS CAN CALL CONS BUT CANNOT SEQUENCE-BREAK.  IT WILL NOT CLOBBER ANY REGISTERS
;EXCEPT WHAT PAGE-FAULTS CLOBBER.  IF IT NEEDS TO SEQUENCE BREAK, THE BREAK WILL
;ACTUALLY BE DEFERRED SO THAT EVERYONE WHO TRANSPORTS DOESN'T HAVE TO WORRY ABOUT
;SEQUENCE BREAKS.

;GET HERE BY SPECIAL DISPATCH, THE RETURN ADDRESS ON THE MICROSTACK
;IS THE ADDRESS OF THE DISPATCH INSTRUCTION ITSELF.
;PRESENTLY, WE HAVE ONE DISPATCH TABLE AND USE I-ARG'S TO DISTINGUISH THE
;CASES.  IF IT TURNS OUT WE OUGHT TO HAVE DROPPED THROUGH, WE RETURN TO
;THE DISPATCH INSTRUCTION, OA-MODIFYING IT TO DISPATCH THROUGH LOC 3777
;WHICH FORCES IT TO DROP THROUGH.  NORMALLY, WE EITHER ERR OUT OR ALTER
;VMA AND MD AND RETURN TO RE-EXECUTE THE DISPATCH.

;Enter here if either the MD is a pointer to old-space or we have a map miss
TRANS-OLD
	(JUMP-IF-BIT-SET (BYTE-FIELD 1 1) READ-I-ARG TRANS-DROP-THROUGH);Ignore if no-transport
TRANS-OLD0	;Enter here if forwarding-pointer, mustn't ever drop-through
	((A-TRANS-VMA) VMA)			;Save where MD came from
	(DISPATCH L2-MAP-STATUS-CODE D-GET-MAP-BITS) ;Ensure validity of meta bits
	(POPJ-IF-BIT-SET-XCT-NEXT 
		l2-map-oldspace-meta-bit)	;Re-transport if was just map not set up
       ((VMA) A-TRANS-VMA)			;Restoring VMA which could have been bashed
	((VMA-START-READ) MD)			;Get word out of old space
	(CHECK-PAGE-READ)	;** Should blow out here if was really free space
	((A-TRANS-MD) VMA)			;Save pointer to old space
	(DISPATCH Q-DATA-TYPE READ-MEMORY-DATA D-TRANS-OLD)

(LOCALITY D-MEM)
;Dispatch on datatype of word fetched from old space when transporting a pointer to old-space
;Usually go to TRANS-OLD-COPY to copy the containing structure.  Check specially for
;GC-FORWARD (already copied), invisibles (snap out).
(START-DISPATCH 5 INHIBIT-XCT-NEXT-BIT)
D-TRANS-OLD
	(TRANS-OLD-COPY)	;TRAP
	(TRANS-OLD-COPY)	;NULL
	(TRANS-OLD-COPY)	;FREE
	(TRANS-OLD-COPY)	;SYMBOL
	(TRANS-OLD-COPY)	;SYMBOL-HEADER
	(TRANS-OLD-COPY)	;FIX
	(TRANS-OLD-COPY)	;EXTENDED NUMBER
	(TRANS-OLD-COPY)	;HEADER
	(TRANS-OLD-GC-FWD)	;GC-FORWARD
	(TRANS-OLD-COPY)	;EXTERNAL-VALUE-CELL-POINTER
	(TRANS-OLD-COPY)	;ONE-Q-FORWARD
	(TRANS-OLD-HDR-FWD)	;HEADER-FORWARD
	(TRANS-OLD-BODY-FWD)	;BODY-FORWARD
	(TRANS-OLD-COPY)	;LOCATIVE
	(TRANS-OLD-COPY)	;LIST
	(TRANS-OLD-COPY)	;U CODE ENTRY
	(TRANS-OLD-COPY)	;FEF
	(TRANS-OLD-COPY)	;ARRAY-POINTER
	(TRANS-OLD-COPY)	;ARRAY-HEADER
	(TRANS-OLD-COPY)	;STACK-GROUP
	(TRANS-OLD-COPY)	;CLOSURE
	(TRANS-OLD-COPY)	;SMALL-FLONUM 
	(TRANS-OLD-COPY)	;SELECT-METHOD
	(TRANS-OLD-COPY)	;INSTANCE
	(TRANS-OLD-COPY)	;INSTANCE-HEADER
	(TRANS-OLD-COPY)	;ENTITY
	(TRANS-OLD-COPY)	;STACK-CLOSURE
	(TRANS-OLD-COPY)	;SELF-REF-POINTER
	(TRANS-OLD-COPY)	;CHARACTER
 (REPEAT NQZUSD (TRANS-OLD-COPY))
(END-DISPATCH)
(LOCALITY I-MEM)

;;; Copy object found in oldspace
TRANS-OLD-COPY
	((C-PDL-BUFFER-POINTER-PUSH) M-A)	;Protect regs used by XARN
	((C-PDL-BUFFER-POINTER-PUSH) M-B)
	((C-PDL-BUFFER-POINTER-PUSH) M-T)
	(CALL-XCT-NEXT XARN)			;M-T gets area# object is in
       ((C-PDL-BUFFER-POINTER-PUSH) A-TRANS-MD)
	((M-TEM) M-T)				;Allocate new copy in same area
	((M-T) C-PDL-BUFFER-POINTER-POP)	;Restore registers
	((M-B) C-PDL-BUFFER-POINTER-POP)
	((M-A) C-PDL-BUFFER-POINTER-POP)
	(CALL-XCT-NEXT TRANS-COPY)		;Make new copy
       ((A-TRANS-COPY-FWD-DTP)
		(A-CONSTANT (PLUS (BYTE-VALUE Q-DATA-TYPE DTP-GC-FORWARD)
				  (BYTE-VALUE Q-CDR-CODE CDR-ERROR))))
	(POPJ-AFTER-NEXT (VMA-START-WRITE) A-TRANS-VMA)	;Replace oldspace ptr with newspace ptr
       (CHECK-PAGE-WRITE-FORCE)			;and transport again

;DTP-BODY-FORWARD in old space.  Must find header, find new copy, and snap out.
TRANS-OLD-BODY-FWD
	((VMA-START-READ) MD)			;Pick up the DTP-HEADER-FORWARD
	(CHECK-PAGE-READ)
	((A-TRANS-TEM) SUB VMA A-TRANS-MD)	;Offset from particular Q to header
	((M-TEM) Q-DATA-TYPE READ-MEMORY-DATA)	;Consistency check
	(CALL-NOT-EQUAL M-TEM (A-CONSTANT (EVAL DTP-HEADER-FORWARD)) ILLOP)
	((MD) SUB READ-MEMORY-DATA A-TRANS-TEM)	;MD gets address of new copy of Q
						;Drops through
;DTP-GC-FORWARD in old space.  Take what it points to.
TRANS-OLD-GC-FWD
	((MD) Q-POINTER MD A-TRANS-MD)		;Combine new pointer with old tag
	(POPJ-AFTER-NEXT (VMA-START-WRITE) A-TRANS-VMA)	;Snap it out
       (CHECK-PAGE-WRITE-FORCE)			;and transport again

;DTP-HEADER-FORWARD in old space.  In structure space, just snap it out.
;Then transport again in case it pointed to oldspace.
;In list space, header-forward is something else entirely, namely
;rplacd-forwarding pointer.  We ignore the header-forward and do
;the usual copying operation, which will handle the header-forward suitably.
TRANS-OLD-HDR-FWD
	(DISPATCH L2-MAP-STATUS-CODE D-GET-MAP-BITS) ;Meta bits for new copy
	(DISPATCH L2-MAP-REPRESENTATION-TYPE D-TRANS-OLD-HDR-FWD)

(LOCALITY D-MEM)
(START-DISPATCH 2 INHIBIT-XCT-NEXT-BIT)
D-TRANS-OLD-HDR-FWD
	(TRANS-OLD-COPY)	;0 list
	(TRANS-OLD-GC-FWD)	;1 structure
(REPEAT 2 (P-BIT ILLOP))	;2, 3 not used
(END-DISPATCH)
(LOCALITY I-MEM)

;Enter here for trapping data type.  If it points to old-space, and
;this is not an inum-type (DTP-NULL), will have already been
;transported.  If going to write, we ignore it, otherwise we trap anyway.
TRANS-TRAP
	(CALL-IF-BIT-CLEAR (BYTE-FIELD 1 4) READ-I-ARG
		TRANS-REALLY-TRAP)	;BARF IF READING RANDOM DATA
;Return to caller, causing dispatch to drop through by OA-modifying it.
;Assume that VMA and MD haven't been modified, or have been saved and restored.
TRANS-DROP-THROUGH	
	(POPJ-AFTER-NEXT NO-OP)
#+cadr ((OA-REG-LOW) DPB (M-CONSTANT -1) OAL-DISP A-ZERO)	;FORCE DISP TO LOC 3777
#+lambda  ((OA-REG-HIGH) DPB (M-CONSTANT -1) OAH-DISP A-ZERO)	;FORCE DISP TO LOC 7777


;Since MD is not saved in the stack group state, save it elsewhere (on the stack)
;and then call trap.  It is sort of important to be able to tell what data in MD
;actually caused the trap, in case the contents of the addressed location change.
TRANS-REALLY-TRAP
	((PDL-PUSH) DPB MD Q-POINTER (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	((PDL-PUSH) LDB Q-DATA-TYPE MD (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	(CALL TRAP)
    (ERROR-TABLE TRANS-TRAP) ;This is a special entry, which the EH knows all about.
    (ERROR-TABLE RESTART TRANS-TRAP-RESTART)	;Retart here
	((MD) C-PDL-BUFFER-POINTER-POP)		;with replacement data on the stack
	(POPJ-AFTER-NEXT PDL-POP)
       (PDL-POP)		;Discard the MD value we provided for the error handler.

;Enter here if self-ref-pointer.  Need not transport from old space since Q-POINTER field
;is not really a pointer.
TRANS-SRP
	(JUMP-IF-BIT-SET (LISP-BYTE %%SELF-REF-MONITOR-FLAG) MD TRANS-MONITOR)
	(JUMP-IF-BIT-CLEAR (BYTE-FIELD 1 0) READ-I-ARG TRANS-EVCP-1)	;JUMP IF SHOULDN'T INVZ
	((M-TEM) DPB M-ZERO Q-POINTER A-SELF)
	(CALL-NOT-EQUAL M-TEM
	 (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-INSTANCE))
	 TRAP)
    (ERROR-TABLE SELF-NOT-INSTANCE)
;Jump if this pointer wants no mapping table.
	(JUMP-IF-BIT-CLEAR (LISP-BYTE %%SELF-REF-RELOCATE-FLAG) MD TRANS-SRP-NO-MAP)
;Jump if combined method getting another mapping table.
	(JUMP-IF-BIT-SET-XCT-NEXT (LISP-BYTE %%SELF-REF-MAP-LEADER-FLAG) MD
	 TRANS-SRP-MAP-LEADER)
       ((A-TRANS-VMA) VMA)
;Jump if no mapping table now.
	((M-TEM) A-SELF-MAPPING-TABLE)
	((M-TEM) Q-DATA-TYPE M-TEM)
	(JUMP-NOT-EQUAL M-TEM (A-CONSTANT (EVAL DTP-ARRAY-POINTER)) TRANS-SRP-NO-MAP)
;Map the SELF-REF-INDEX thru the mapping table, an ART-16B array.
	((M-TEM) (LISP-BYTE %%SELF-REF-WORD-INDEX) MD)
	((A-TRANS-MD) LDB (BYTE-FIELD 1 0) MD A-ZERO)
	((VMA-START-READ) M+A+1 A-SELF-MAPPING-TABLE M-TEM)
	(CHECK-PAGE-READ)
	((VMA) A-TRANS-VMA)
	(JUMP-EQUAL A-TRANS-MD M-ZERO TRANS-SRP-NO-MAP)
	((MD) (BYTE-FIELD 20 20) MD)
;Make a pointer to the desired slot in SELF and then INVZ to there.
;MD contains the slot number.
;Note: no need to check for oldspace since A-SELF can't point to oldspace.
TRANS-SRP-NO-MAP
	((M-TEM) (LISP-BYTE %%SELF-REF-INDEX) MD)
	(CALL-GREATER-THAN M-TEM (A-CONSTANT 7770) TRAP)
    (ERROR-TABLE NONEXISTENT-INSTANCE-VARIABLE VMA)
	((MD) M+A+1 A-SELF M-TEM)
	(JUMP-XCT-NEXT TRANS-INVZ)
       ((MD) DPB MD Q-POINTER		;avoid garbage data type
		(A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-EXTERNAL-VALUE-CELL-POINTER)))

;Here to get the contents of what an array leader slot points to.
;In this case, we get the mapping table from local slot 1 on the stack.
TRANS-SRP-MAP-LEADER
	((PDL-BUFFER-INDEX) M+A+1 M-ZERO A-LOCALP)
	((A-TRANS-MD) (LISP-BYTE %%SELF-REF-INDEX) MD)
	((M-TEM) Q-TYPED-POINTER C-PDL-BUFFER-INDEX)
	(CALL-EQUAL M-TEM A-V-NIL TRAP)
    (ERROR-TABLE NO-MAPPING-TABLE-1)
	((VMA) SUB C-PDL-BUFFER-INDEX A-TRANS-MD)
	((VMA-START-READ) SUB VMA (A-CONSTANT 2))
	(CHECK-PAGE-READ)	;Get the contents of the arrayleader slot.
	((VMA) DPB VMA Q-POINTER A-TRANS-VMA)	;Go thru gyrations to preserve data type field
	(DISPATCH TRANSPORT MD)			;of the original VMA that pointed to the SRP.
	;; A-TRANS-VMA has just been clobbered!
	;; The array-leader slot contains a locative to a cell.
	;; Put the cell's address in VMA and read the cell's contents.
	((A-TRANS-VMA) VMA)
	(POPJ-AFTER-NEXT
	 (VMA-START-READ) DPB MD Q-POINTER A-TRANS-VMA)
       (CHECK-PAGE-READ)  ;Return, and transport the new contents of VMA/MD.

TRANS-MONITOR
;Here if we encounter a DTP-SELF-REF-POINTER whose %%SELF-REF-MONITOR-FLAG bit is set.
;Forward to the following word.  But first, get an error if about to write.
	(CALL-IF-BIT-SET READ-I-ARG (A-CONSTANT 40) TRANS-REALLY-TRAP)
	(POPJ-AFTER-NEXT (VMA-START-READ) ADD VMA (A-CONSTANT 1))
       (CHECK-PAGE-READ)
		
;Enter here if external-value-cell-pointer to old-space.
;If supposed to invz, transport first.  Otherwise, transport
;unless don't-transport bit is set.
TRANS-OLDP-EVCP
	(JUMP-IF-BIT-CLEAR (BYTE-FIELD 1 1) READ-I-ARG TRANS-OLD0) ;Transport if supposed to.
	(JUMP-IF-BIT-SET (BYTE-FIELD 1 0) READ-I-ARG TRANS-OLD0) ;Transport first, if must invz
	(JUMP TRANS-EVCP-1)
	;Drop into TRANS-EVCP-1 if either going to drop-through and no transp desired,
	;or if going to ILLOP

;Enter here for external-value-cell-pointer to newspace.
TRANS-EVCP
	(JUMP-IF-BIT-CLEAR (BYTE-FIELD 1 0) READ-I-ARG TRANS-EVCP-1) ;JUMP IF SHOULDN'T INVZ
	;Else drop into TRANS-INVZ, faster than jumping

;Enter here for DTP-HEADER-FORWARD pointer, always forwards.
;Already transported if was old-space.
TRANS-HFWD	
;Chase forwarding pointer, restart cycle
TRANS-INVZ	
	((A-TEM1) READ-MEMORY-DATA)
	(POPJ-AFTER-NEXT
	 (VMA-START-READ) SELECTIVE-DEPOSIT VMA		;RETAIN DATA TYPE,
			 Q-ALL-BUT-POINTER A-TEM1)	;ALTER POINTER
       (CHECK-PAGE-READ)

TRANS-EVCP-1
	(JUMP-XCT-NEXT TRANS-DROP-THROUGH)	;SHOULDN'T INVZ, GO SIMULATE DROP THROUGH
       (CALL-IF-BIT-SET (BYTE-FIELD 1 2) READ-I-ARG ILLOP)	;BARF IF TRANSPORT-HEADER

;Enter here for one-q-forward.  Already transported if was old-space.
TRANS-OQF
	(JUMP-IF-BIT-SET (BYTE-FIELD 1 3) READ-I-ARG TRANS-DROP-THROUGH) ;IGNORE OQF IF JUST
	(JUMP-XCT-NEXT TRANS-INVZ)					 ;CHECKING CDR CODE
       (CALL-IF-BIT-SET (BYTE-FIELD 1 2) READ-I-ARG ILLOP)	;BARF IF TRANSPORT-HEADER

;Enter here for DTP-BODY-FORWARD, always forwards, but must "go around" through header
TRANS-BFWD	
	((A-TRANS-VMA) VMA)			;REMEMBER WHERE ORIGINAL REFERENCE WAS
	((VMA-START-READ) DPB READ-MEMORY-DATA	;PICK UP DTP-HEADER-FORWARD FROM OLD HEADER
		Q-POINTER A-TRANS-VMA)		;DON'T CHANGE DATA TYPE OF VMA
	(CHECK-PAGE-READ)
	((A-TEM1) SUB VMA A-TRANS-VMA)		;MINUS OFFSET FROM HEADER TO DATA
	((M-TEM) Q-DATA-TYPE READ-MEMORY-DATA)	;THESE 2 INSTRUCTIONS ARE JUST A RANDOMNESS
	(CALL-NOT-EQUAL M-TEM (A-CONSTANT (EVAL DTP-HEADER-FORWARD)) ILLOP)	; CHECK
	((M-TEM) SUB READ-MEMORY-DATA A-TEM1)	;GET ADDRESS RELOCATED TO
	(POPJ-AFTER-NEXT			;REFERENCE THAT ADDRESS, VMA DATATYPE UNCHANGED
	 (VMA-START-READ) SELECTIVE-DEPOSIT VMA Q-ALL-BUT-POINTER A-TEM)
       (CHECK-PAGE-READ)

;;; Routine to copy what A-TRANS-MD points to into area in M-TEM.
;;; Returns with MD pointing to copy.  Leaves forwarding pointers behind,
;;; whose data-type and cdr code come from A-TRANS-COPY-FWD-DTP
;;; Note that cdr-code of the GC-forwarding pointer must be cdr-error,
;;; to avoid faking out XFSHL.
;;; Used by the transporter and the extra-pdl copier.
;;; In list space, we have to worry about complicated dealings with rplacd-forwards
;;; Can't save registers in the pdl buffer since might be called from XFLIPW
;;; and might decide to clobber the registers with GC-forwarding pointers.
TRANS-COPY
	((M-TRANSPORT-FLAG) DPB (M-CONSTANT -1) A-FLAGS) ;No sequence break out of CONS!
	(CALL TRANS-COPY-SAVE)
	((M-S) M-TEM)				;Area in which to allocate
	(CALL-XCT-NEXT XFSL)			;Find start of structure (to M-T)
       ((C-PDL-BUFFER-POINTER-PUSH) A-TRANS-MD)	;arg
	((C-PDL-BUFFER-POINTER-PUSH) M-T)	;Save old object
	(CALL-XCT-NEXT STRUCTURE-INFO)		;Find size of structure
       ((MD) M-T)
	;; Cons up new copy.  If list representation, branch off to special code first.
	(DISPATCH-XCT-NEXT (LISP-BYTE %%REGION-REPRESENTATION-TYPE) M-K D-TRANS-COPY)
       ((M-B) ADD M-3 A-4)			;Total size of it
TRANS-COPY-1
	((M-K) SETO)				;Extinguish flag
TRANS-COPY-1K
	;; Copy it, boxed and unboxed Q's alike, since shouldn't transport here.
	;; Length is in M-B, last A-SINF-PAD Q's not to be copied.
	((M-E) SUB C-PDL-BUFFER-POINTER-POP (A-CONSTANT 1)) ;Old object minus 1
TRANS-COPY-2  ;Copy loop
	((VMA-START-READ M-E) ADD M-E (A-CONSTANT 1))
	(CHECK-PAGE-READ)
	((M-B) SUB M-B (A-CONSTANT 1))
TRANS-COPY-5
	((M-A) READ-MEMORY-DATA)
	((WRITE-MEMORY-DATA-START-WRITE)	;Replace with GC-forwarding pointer
		Q-POINTER M-T A-TRANS-COPY-FWD-DTP)
	(CHECK-PAGE-WRITE-FORCE)
	((M-TEM) Q-DATA-TYPE M-A)		;Check data type of Q being copied
	(JUMP-EQUAL M-TEM A-K TRANS-COPY-4)	;Oops, special hair for rplacd-forwarding
	((WRITE-MEMORY-DATA) M-A)		;Store old contents in new place
	((VMA-START-WRITE) M-T)
	(CHECK-PAGE-WRITE-FORCE)
	(JUMP-GREATER-THAN-XCT-NEXT M-B A-SINF-PAD TRANS-COPY-2)
       ((M-T) ADD M-T (A-CONSTANT 1))
	(JUMP-EQUAL M-B A-ZERO TRANS-COPY-9)
TRANS-COPY-7	;"Copy" the padding.  Must store forwarding pointers but clobber contents.
	((VMA M-E) ADD M-E (A-CONSTANT 1))
	((WRITE-MEMORY-DATA-START-WRITE)	;Replace with forwarding pointer
		Q-POINTER M-T A-TRANS-COPY-FWD-DTP)
	(CHECK-PAGE-WRITE-FORCE)
	((M-B) SUB M-B (A-CONSTANT 1))
	((VMA) M-T)
	((WRITE-MEMORY-DATA-START-WRITE)	;"Copy" gets a fixnum zero
		(A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	(CHECK-PAGE-WRITE-FORCE)
	(JUMP-GREATER-THAN-XCT-NEXT M-B A-ZERO TRANS-COPY-7)
       ((M-T) ADD M-T (A-CONSTANT 1))
TRANS-COPY-9
	((M-TEM) M-A-1 M-T A-E)			;Offset from old to new
	((MD) ADD M-TEM A-TRANS-MD)		;Change value being stored
TRANS-COPY-3
	((MD) Q-POINTER MD A-TRANS-MD)		;But only the address part
	(JUMP-XCT-NEXT TRANS-COPY-RESTORE)
       ((M-TRANSPORT-FLAG) DPB (M-CONSTANT 0) A-FLAGS)

TRANS-COPY-4 ;Copy last 2 words, rplacd-forwarded list, that have been snapped in
	(CALL-NOT-EQUAL M-B (A-CONSTANT 1) ILLOP)	;Fuckup somewhere
	((VMA-START-READ) M-A)			;Get first of 2 words via forwarding ptr
	(CHECK-PAGE-READ)
	((M-E) ADD M-E (A-CONSTANT 1))
	((M-B) READ-MEMORY-DATA)		;Cdr-code will always be CDR-NORMAL
	((WRITE-MEMORY-DATA-START-WRITE)	;Replace with GC-forwarding pointer
		Q-POINTER M-T A-TRANS-COPY-FWD-DTP)
	(CHECK-PAGE-WRITE-FORCE)
	((WRITE-MEMORY-DATA) M-B)		;Store old contents in new place
	((VMA-START-WRITE) M-T)
	(CHECK-PAGE-WRITE-FORCE)
	((M-B) (A-CONSTANT 0))
	((VMA-START-READ) ADD M-A (A-CONSTANT 1))	;Get second of 2 words
	(CHECK-PAGE-READ)
	(JUMP-XCT-NEXT TRANS-COPY-5)		;Rejoin main code to do last word
       ((M-T) ADD M-T (A-CONSTANT 1))

TRANS-COPY-SAVE
	((A-TRANS-SAVE-A) M-A)			;Save regs bashed by CONS, FSH
	((A-TRANS-SAVE-B) M-B)
	((A-TRANS-SAVE-E) M-E)
	((A-TRANS-SAVE-K) M-K)
	((A-TRANS-SAVE-S) M-S)
	((A-TRANS-SAVE-T) M-T)
	(POPJ-AFTER-NEXT
	 (A-TRANS-SAVE-3) M-3)
	((A-TRANS-SAVE-4) M-4)

TRANS-COPY-RESTORE
	((M-4) A-TRANS-SAVE-4)			;Restore registers
	((M-3) A-TRANS-SAVE-3)
	((M-T) A-TRANS-SAVE-T)
	((M-S) A-TRANS-SAVE-S)
	((M-K) A-TRANS-SAVE-K)
	((M-E) A-TRANS-SAVE-E)
	(POPJ-AFTER-NEXT
	 (M-B) A-TRANS-SAVE-B)
	((M-A) A-TRANS-SAVE-A)

(LOCALITY D-MEM)
(START-DISPATCH 2 0)
;Dispatch on representation type for CONS inside of TRANS-COPY
D-TRANS-COPY
	(TRANS-COPY-LIST)	;0 List
	(P-BIT SCONS)		;1 Structure
	(P-BIT ILLOP)		;2 unused
 	(P-BIT ILLOP)		;3 unused
(END-DISPATCH)
(LOCALITY I-MEM)

;;; TRANS-COPY on a list
TRANS-COPY-LIST
	(JUMP-IF-BIT-SET (BYTE-FIELD 1 31.) M-K TRANS-COPY-LIST-0) ;Test for RPLACD-forwarding
	(JUMP-XCT-NEXT TRANS-COPY-1)	;No RPLACD-forwarding, copy just like structure
       (CALL LCONS)

TRANS-COPY-LIST-0
	(JUMP-GREATER-THAN M-B (A-CONSTANT 2) TRANS-COPY-LIST-1) ;Test for hairy case
	;; The entire list-structure (1 Q) was forwarded, so simply snap out
	((VMA-START-READ) C-PDL-BUFFER-POINTER-POP)	;Fetch forwarding pointer
	(CHECK-PAGE-READ)
	(JUMP TRANS-COPY-3)			;Use what it points at

;;; Here if the list-structure is partially in one place and partially in another.
;;; If the new node created by rplacd is in oldspace and not yet copied, we should
;;; snap-out by copying it into the same place as the old part of the list-structure.
;;; And if we didn't snap out we could be storing a pointer to oldspace which is a no-no.
;;; On the other hand, if the new node is in newspace or has already been copied,
;;; we can't snap out.  Instead we create a full-node out of the cdr-next
;;; node just before the forwarded one.
TRANS-COPY-LIST-1
	((M-T) SUB M-B (A-CONSTANT 2))		;Offset to dtp-header-forward Q
	((VMA-START-READ M-T) ADD C-PDL-BUFFER-POINTER A-T)	;Fetch him
	(CHECK-PAGE-READ)
	((M-TEM) READ-MEMORY-DATA)		;Complete read cycle
	(DISPATCH L2-MAP-STATUS-CODE D-GET-MAP-BITS) ;Validate meta bits
	(JUMP-IF-BIT-SET L2-MAP-OLDSPACE-META-BIT
		TRANS-COPY-LIST-3)		;Jump if new node is in newspace
	((VMA-START-READ) MD)			;Pick up first word of new node
	(CHECK-PAGE-READ)
	((M-TEM) Q-DATA-TYPE READ-MEMORY-DATA)	;Look for GC-forward
	(JUMP-EQUAL M-TEM (A-CONSTANT (EVAL DTP-GC-FORWARD)) TRANS-COPY-LIST-3)
	;; New node can be merged with old node, full snapping-out
	(CALL LCONS)				;Cons new list, big enough for both
	(JUMP-XCT-NEXT TRANS-COPY-1K)		;Go join normal copy
       ((M-K) (A-CONSTANT (EVAL DTP-HEADER-FORWARD))) ;but watch out for this data type

TRANS-COPY-LIST-3 ;Can't snap out.  MD -> new node in newspace.
	((VMA) M-T)				;Clobber hdr-fwd with cdr pointer
	((MD-START-WRITE) Q-POINTER MD (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-LIST)))
	(CHECK-PAGE-WRITE-FORCE)
	((VMA-START-READ) SUB VMA (A-CONSTANT 1))	;Fix cdr code of preceding word
	(CHECK-PAGE-READ)
	((M-B) SUB M-B (A-CONSTANT 1))		;Copy will be 1 Q shorter since no snapout
	((MD-START-WRITE) Q-ALL-BUT-CDR-CODE READ-MEMORY-DATA
		(A-CONSTANT (BYTE-VALUE Q-CDR-CODE CDR-NORMAL)))
	(CHECK-PAGE-WRITE-FORCE)
	(JUMP-XCT-NEXT TRANS-COPY-1)		;Copy fudged list
       (CALL LCONS)

;;; EXTRA-PDL-TRAP
;;; We get here if we just wrote a possible pointer to the extra-pdl
;;; into main memory.  If so, we must copy the object out into a normal
;;; area and do the write again.  Mustn't sequence-break while the
;;; bad thing is in memory, and mustn't clobber anything other than
;;; what page faults clobber.  SMASHES PDL-BUFFER-INDEX.
;;; (I-ARG 1) indicates coming from pdl-buffer dumper, special return
;;; indicated since map has been munged.
;;; Note that we cannot get here from inside the transporter, which
;;; is fortunate since some variables are shared.

EXTRA-PDL-TRAP
	((A-TRANS-MD) MD)			;SAVE DUBIOUS OBJECT
	(JUMP-IF-BIT-SET-XCT-NEXT		;CHECK FOR CALL FROM PDL-BUFFER DUMPER
		(BYTE-FIELD 1 0) READ-I-ARG EXTRA-PDL-TRAP-0)
       ((A-TRANS-VMA) VMA)			;SAVE ADDRESS WRITTEN INTO
EXTRA-PDL-TRAP-1
;Only if MD points at the extra pdl area do we need to copy it.
	(DISPATCH L2-MAP-STATUS-CODE D-GET-MAP-BITS) ;ENSURE VALIDITY OF META BITS
	(POPJ-IF-BIT-SET-XCT-NEXT		;RETURN IF FALSE ALARM
		L2-MAP-EXTRA-PDL-META-BIT)
       ((VMA) A-TRANS-VMA)			;RESTORE VMA
;Don't copy if the pointer is being stored in the extra pdl area.
	((MD) VMA)
	(DISPATCH L2-MAP-STATUS-CODE D-GET-MAP-BITS) ;ENSURE VALIDITY OF META BITS
	(JUMP-IF-BIT-CLEAR-XCT-NEXT		;Return if false alarm.
	  	L2-MAP-EXTRA-PDL-META-BIT
		TRANS-DROP-THROUGH)
       ((MD) A-TRANS-MD)			;RESTORE MD

;Don't copy if storing into virtual address which will map to PDL buffer.
	((m-tem) dpb m-zero q-all-but-pointer a-trans-vma)
	(jump-less-than m-tem a-pdl-buffer-virtual-address extra-pdl-trap-2)
	((m-tem) sub m-tem a-pdl-buffer-active-qs)
	((pdl-buffer-index) sub pdl-buffer-pointer a-ap)
	((m-3) pdl-buffer-index)	;do modulo arithmetic
	((m-tem) sub m-tem a-3)		;account for Qs in current frame 
					;(in case clobbering REST arg).
	(jump-less-than m-tem a-pdl-buffer-virtual-address trans-drop-through)

EXTRA-PDL-TRAP-2
;Real extra-pdl trap, copy object out into working storage
	((VMA-START-READ) MD)			;Check for forwarding pointer
	(CHECK-PAGE-READ)
	((M-TEM) Q-DATA-TYPE READ-MEMORY-DATA)
	(JUMP-EQUAL-XCT-NEXT M-TEM (A-CONSTANT (EVAL DTP-HEADER-FORWARD)) EXTRA-PDL-TRAP-3)
       ((MD) Q-POINTER MD A-TRANS-MD)		;Change address to follow forwarding ptr
	((A-TRANS-COPY-FWD-DTP)			;Forward with header forwards
		(A-CONSTANT (PLUS (BYTE-VALUE Q-DATA-TYPE DTP-HEADER-FORWARD)
				  (BYTE-VALUE Q-CDR-CODE CDR-ERROR))))
	(CALL-XCT-NEXT TRANS-COPY)		;Copy the frob in A-TRANS-MD
       ((M-TEM) DPB M-ZERO Q-ALL-BUT-TYPED-POINTER A-BACKGROUND-CONS-AREA) ;into default area
	((PDL-PUSH) MD)
;Now look at the header of the object we copied
;and find out how many boxed Qs the object contains (in M-3).
	((VMA-START-READ) MD)
	(CHECK-PAGE-READ)
	(CALL-XCT-NEXT SINFSH)
       ((M-3) A-ZERO)
	(JUMP-LESS-THAN M-3 (A-CONSTANT 2) EXTRA-PDL-TRAP-4)
	((PDL-PUSH) A-TRANS-VMA)
	((PDL-PUSH) M-3)
;These pointers may point into the extra pdl area.
;If so, they too need to be copied.
;Here, VMA points at word before next pointer to be tested
;and PDL-TOP contains 1+number of pointers to test.
EXTRA-PDL-TRAP-5
	((VMA-START-READ) ADD VMA (A-CONSTANT 1))
	(CHECK-PAGE-READ)
	(GC-WRITE-TEST)
	((PDL-TOP M-3) SUB PDL-TOP (A-CONSTANT 1))
	(JUMP-NOT-EQUAL M-3 (A-CONSTANT 1) EXTRA-PDL-TRAP-5)
	(PDL-POP)
	((A-TRANS-VMA) PDL-POP)
EXTRA-PDL-TRAP-4
	((MD) PDL-POP)
EXTRA-PDL-TRAP-3	;New copy is now in MD, with suitable tag
	(POPJ-AFTER-NEXT (VMA-START-WRITE) A-TRANS-VMA) ;Correct store that trapped
       (CHECK-PAGE-WRITE)			; and return

;Here for EXTRA-PDL-TRAP while storing pdl-buffer.  Must clean up
;before processing the trap, and must eventually return to P-B-MR0.
;M-1 has the original map word contents.
;Cleanup is different in that VMA and PI haven't been advanced yet.
EXTRA-PDL-TRAP-0
	((M-TEM) SUB VMA A-PDL-BUFFER-VIRTUAL-ADDRESS)	;Number of locations dumped -1
	((M-PDL-BUFFER-ACTIVE-QS) M-A-1 M-PDL-BUFFER-ACTIVE-QS A-TEM)
	((A-PDL-BUFFER-VIRTUAL-ADDRESS) ADD VMA (A-CONSTANT 1))
	((PDL-BUFFER-INDEX) ADD PDL-BUFFER-INDEX (A-CONSTANT 1))
	((A-PDL-BUFFER-HEAD) PDL-BUFFER-INDEX)
	((MD) Q-R)				;Address the map
#+cadr	((VMA-WRITE-MAP) DPB M-1		;Restore the map for this page
		MAP-WRITE-SECOND-LEVEL-MAP
		(A-CONSTANT (BYTE-MASK MAP-WRITE-ENABLE-SECOND-LEVEL-WRITE)))
#+lambda((L2-MAP-CONTROL) M-1)
	;; EXTRA-PDL-TRAP-1 will clean up garbage in VMA.
	((MD) SETA A-TRANS-MD			;Restore dubious MD
		MICRO-STACK-PNTR-AND-DATA-POP)	;and flush useless return address
	(JUMP-XCT-NEXT EXTRA-PDL-TRAP-1)	;Return to mainline
       ((MICRO-STACK-DATA-PUSH) (A-CONSTANT (I-MEM-LOC P-B-MR0-HACK))) ;with return address buggered

;; We want to return to P-B-MR0, but we can get there though TRANS-DROP-THROUGH,
;; and it expects the return address to be a DISPATCH and modifies it through the OA reg.
;; So give it a no-op dispatch so that that does not do anything unpredictable.
P-B-MR0-HACK
	(DISPATCH (BYTE-FIELD 0 0) LAST-DMEM-LOCATION)
	(JUMP P-B-MR0)
))
