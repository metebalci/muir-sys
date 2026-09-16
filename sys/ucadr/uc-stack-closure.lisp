;-*-Mode:MIDAS-*-
;Written by RMS.  You are welcome to use this,
;though it is not likely to do you much good.

(setq uc-stack-closure '(

;;; Copy a DTP-STACK-CLOSURE when it is stored anywhere but
;;; into the same stack it points at, and farther down than where it points.
;;; There is no way to forward the stack closure to the copy,
;;; because only header-forward works to forward a list's car and cdr,
;;; and putting that inside a structure will confuse other things.
;;; So we stick an external-value-cell-pointer into the stack closure
;;; pointing at the copy.  This does not forward it as far as the
;;; low levels of the system is concerned!  But as long as the
;;; stack closure still exists, that's ok; the evcp forwards only the car
;;; of the stack closure, but forwards it to the car of the copy,
;;; which contains the correct value.

;Here from GC-WRITE-TEST if data type is DTP-STACK-CLOSURE.
;If VMA is NIL, it means always copy, and don't store the
;new value anywhere, just leave it in MD.
STACK-CLOSURE-TRAP
	((M-TEM) Q-POINTER MD)
	((M-PGF-TEM) Q-POINTER VMA)
;If storing into the same stack and inward from where it points, don't copy.
	(JUMP-LESS-THAN M-TEM A-QLPDLO STACK-CLOSURE-TRAP-REALLY)
	(JUMP-LESS-THAN M-PGF-TEM A-TEM STACK-CLOSURE-TRAP-REALLY)
	(JUMP-LESS-THAN M-PGF-TEM A-QLPDLH TRANS-DROP-THROUGH)

;Here if the stack-closure is being stored into a place it should not be.
STACK-CLOSURE-TRAP-REALLY
;; If coming from PDL buffer dumper, don't copy.
;; If it was ok to put the pointer there originally, it is still ok there.
;; (Note, additional hair would be needed to avoid lossage if it copied in this case.)
	(JUMP-IF-BIT-SET (BYTE-FIELD 1 0) READ-I-ARG TRANS-DROP-THROUGH)
	;; Save original cdr code of word containing the stack closure, and save its address.
	((PDL-PUSH) Q-CDR-CODE MD (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	((C-PDL-BUFFER-POINTER-PUSH) VMA)
	((VMA-START-READ) MD)			;Check for forwarding pointer already.
	(CHECK-PAGE-READ)
	((M-TEM) Q-DATA-TYPE READ-MEMORY-DATA)
	(CALL-NOT-EQUAL M-TEM (A-CONSTANT (EVAL DTP-EXTERNAL-VALUE-CELL-POINTER))
	    STACK-CLOSURE-COPY)
STACK-CLOSURE-STORE-COPY
	((MD M-TEM) Q-POINTER MD (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-CLOSURE)))
	((VMA) C-PDL-BUFFER-POINTER-POP)	;Get back original address referenced,
	(JUMP-EQUAL VMA A-V-NIL TRANS-DROP-THROUGH)	;Or NIL => just leave value in MD.
	((MD) DPB PDL-POP Q-CDR-CODE A-TEM)	;Merge in original CDR-code of memory word.
	((VMA-START-WRITE) VMA)			;Rewrite that location.
	(CHECK-PAGE-WRITE)
	(JUMP TRANS-DROP-THROUGH)

;This stack-closure has not yet had a copy made.
;The original stack-closure object is now in VMA.
;Returns with a pointer to the copy in MD.
STACK-CLOSURE-COPY
	((C-PDL-BUFFER-POINTER-PUSH) VMA)
;Make sure all the cells of the environment list are in newspace.
;Or rather, that their containing stacks are in newspace.
	((VMA-START-READ) ADD VMA (A-CONSTANT 3))
	(CHECK-PAGE-READ)		;MD has ptr to list, VMA as addr of that ptr.
	(CALL ENSURE-STACK-ENV-TRANSPORTED)
;Now no more transporting can happen,
;so save many ACs the same way the transporter does.
	(CALL TRANS-COPY-SAVE)
;Go through the environment-list of the closure,
;forwarding each cell of the list.
	((MD) ADD PDL-TOP (A-CONSTANT 2))
	(CALL ENSURE-STACK-ENV-COPIED)
;Get the address of the copy just made of the first cell of the environment-list.  Save it.
	((VMA-START-READ) ADD PDL-TOP (A-CONSTANT 2))
	(CHECK-PAGE-READ)
	((C-PDL-BUFFER-POINTER-PUSH) DPB MD Q-POINTER
				     (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-LIST)))
;Go through again, splicing the EVCPs out
;so that the new copies point directly one at the next.
	(CALL ENSURE-STACK-ENV-SNAPPED)
;Copy the closure itself.
	((M-B) (A-CONSTANT 2))
	(CALL-XCT-NEXT LCONS)
       ((M-S) DPB M-ZERO Q-ALL-BUT-TYPED-POINTER A-BACKGROUND-CONS-AREA)
;Store ptr to new value in last slot.
	((VMA) ADD M-T (A-CONSTANT 1))
	((MD-START-WRITE) DPB Q-TYPED-POINTER PDL-POP
		(A-CONSTANT (BYTE-VALUE Q-CDR-CODE CDR-NIL)))
	(CHECK-PAGE-WRITE)
;Get back ptr to original stack closure, and copy the first slot.
	((VMA-START-READ M-K) PDL-POP)
	(CHECK-PAGE-READ)
	((VMA-START-WRITE) M-T)
	(CHECK-PAGE-WRITE)
;Make the closure on the stack point at the copy with an EVCP.
	((MD) DPB M-T Q-POINTER
		  (A-CONSTANT (PLUS (BYTE-VALUE Q-CDR-CODE CDR-NEXT)
				    (BYTE-VALUE Q-DATA-TYPE DTP-EXTERNAL-VALUE-CELL-POINTER))))
	((VMA-START-WRITE) M-K)
	(CHECK-PAGE-WRITE)
	(JUMP TRANS-COPY-RESTORE)

;Make sure that all the cells of the list pointed to by MD
;have been copied into newspace if necessary.
;Actually, the entire stacks that contain them are copied.
;VMA should point at a storage word which points to the list;
;that pointer is updated to point to the copy in newspace,
;and the cdr pointers of the list all point at the copies too.
ENSURE-STACK-ENV-TRANSPORTED
	((MD) Q-TYPED-POINTER MD)
	(POPJ-EQUAL MD A-V-NIL)
	(DISPATCH TRANSPORT MD)
	((VMA-START-READ) M+1 MD)
	(CHECK-PAGE-READ)
	(JUMP ENSURE-STACK-ENV-TRANSPORTED)

;Make sure that all the elements of the list pointed to by MD
;are forwarded (with EVCPs).  Keep forwarding them
;until we reach one that is already forwarded
;or one that is actually in list space.
ENSURE-STACK-ENV-COPIED
;Is this cell in list space?  If so, don't bother with it.
	(DISPATCH L2-MAP-STATUS-CODE D-GET-MAP-BITS) ;Meta bits for cell.
	((M-A) L2-MAP-REPRESENTATION-TYPE)
	(POPJ-EQUAL M-A A-ZERO)
;Is this cell already copied?  If so, return.
	((VMA-START-READ M-A) MD)
	(CHECK-PAGE-READ)
#+cadr	((M-TEM) Q-DATA-TYPE READ-MEMORY-DATA)
#+cadr	(POPJ-EQUAL M-TEM (A-CONSTANT (EVAL DTP-EXTERNAL-VALUE-CELL-POINTER)))
#+lambda(popj-data-type-equal md
		 (a-constant (byte-value q-data-type dtp-external-value-cell-pointer)))
 ;** there isnt a check-data-type frob for this yet.
;Not already copied => push its car, then its cdr.
	((PDL-PUSH M-TEM) Q-TYPED-POINTER MD)
	((VMA-start-read) M+1 VMA)
	(CHECK-PAGE-READ)
	((PDL-PUSH) Q-TYPED-POINTER MD)
;The car points to the stack-closure-vector of a frame
; (or else it is T, which means an empty stack-closure-vector).
;The word before that contains a pointer to the frame itself.
;Get it and set that frame's copy-on-exit bit.
	(JUMP-EQUAL M-TEM A-V-TRUE ENSURE-STACK-ENV-COPIED-1)
	((VMA-START-READ) SUB M-TEM (A-CONSTANT 1))
	(CHECK-PAGE-READ)
	((VMA-START-READ) ADD MD (A-CONSTANT (EVAL %LP-ENTRY-STATE)))
	(CHECK-PAGE-READ)
	((MD-START-WRITE) IOR MD
	    (A-CONSTANT (BYTE-VALUE (LISP-BYTE %%LP-ENS-ENVIRONMENT-POINTER-POINTS-HERE) 1)))
	(CHECK-PAGE-WRITE)
ENSURE-STACK-ENV-COPIED-1
;Then cons a new cell with same car and cdr.
	(CALL-XCT-NEXT QCONS)
       ((M-S) DPB M-ZERO Q-ALL-BUT-TYPED-POINTER A-BACKGROUND-CONS-AREA)
;Make the old one point to the new one with an EVCP in the car.
	((VMA) M-A)
	((MD-START-WRITE) DPB M-T Q-POINTER
		(A-CONSTANT (PLUS (BYTE-VALUE Q-CDR-CODE CDR-NORMAL)
				  (BYTE-VALUE Q-DATA-TYPE DTP-EXTERNAL-VALUE-CELL-POINTER))))
	(CHECK-PAGE-WRITE)
;Get the cdr, which is either NIL or another full-cons.
;If not NIL, go copy it.
	((VMA-START-READ) M+1 VMA)
	(CHECK-PAGE-READ)
	((M-TEM) Q-TYPED-POINTER MD)
	(JUMP-NOT-EQUAL M-TEM A-V-NIL ENSURE-STACK-ENV-COPIED)
	(POPJ)

;Snap out any EVCPs in the cells of the list that MD points to.
;Replace each cdr-pointer to a cell that has an EVCP in its car
;with a pointer to where the EVCP points.
;ENSURE-STACK-ENV-TRANSPORTED, followed by ENSURE-STACK-ENV-COPIED and this,
;is a non-recursive way of copying and snapping an entire list of any length.
;Note that this must act on the start of the copy, not the start
;of the original list.
ENSURE-STACK-ENV-SNAPPED
;Get the first cell's cdr.
	((VMA-START-READ M-A) M+1 MD)
	(CHECK-PAGE-READ)
	((M-TEM) Q-TYPED-POINTER MD)
	(POPJ-EQUAL M-TEM A-V-NIL)
;Is this cell "forwarded" with an EVCP in its car?
	((VMA-START-READ) MD)
	(CHECK-PAGE-READ)
	((M-TEM) Q-DATA-TYPE READ-MEMORY-DATA)
	(POPJ-NOT-EQUAL M-TEM (A-CONSTANT (EVAL DTP-EXTERNAL-VALUE-CELL-POINTER)))
;Else compute the forwarded CDR, and store it back.
	((M-TEM) VMA)
	((MD) Q-POINTER MD A-TEM)
	((VMA-START-WRITE) M-A)
	(CHECK-PAGE-WRITE)
;Do the same thing to the next cell (the forwarded CDR).
	(JUMP ENSURE-STACK-ENV-SNAPPED)	

;; Copy a stack closure, but don't look for anything in M-T.
;; This instruction is used for the first stack closure to be copied
;; when several need to be done at once.
STACK-CLOSURE-DISCONNECT-FIRST
	((M-T) A-V-NIL)

;; Copy the stack closure at local block offset X (contents of low 9 bits of the instruction)
;; and unshare its pointer to this stack frame.
;; When first copied, the six slots of the closure itself are copied
;; but still contain a pointer to the stack closure vector of the frame the closure was in.
;; Normally this remains there until the frame is exited,
;; at which time it is replaced by a pointer to a copy of the stack frame, made in the heap.
;; This instruction copies the stack closure vector immediately.

;; So that more than one stack closure can be unshared at once,
;; this instruction expects either a stack closure vector copy or NIL in M-T.
;; If it is NIL, a new stack closure vector copy is made if necessary
;; and stored in M-T on exit.

;; Disconnection of stack closures is a no-op
;; in a frame whose stack closure vector is empty (that is, T).

STACK-CLOSURE-DISCONNECT
#+cadr	((M-A) M-INST-ADR)
#+lambda((M-A) MACRO-IR-ADR)
	(CALL STACK-CLOSURE-CLEAR)
	(POPJ-EQUAL M-E A-V-NIL)
;Now M-E has the copied stack closure just cleared.
;M-T has NIL if we need to make a copy of the stack closure vector,
;or else has a DTP-LIST pointer to the copy we can use.
	(JUMP-NOT-EQUAL M-T A-V-NIL STACK-CLOSURE-DISCONNECT-REPLACE)
	((PDL-PUSH) M-E)
	((M-A) A-V-NIL)
	(CALL STACK-CLOSURE-VECTOR-COPY)
	(JUMP-EQUAL M-C A-V-TRUE STACK-CLOSURE-DISCONNECT-EMPTY)
	((PDL-PUSH) M-C)
;Push this frame copy onto the list of all frame copies
;made for stack closures copied from this block.
	(CALL STACK-CLOSURE-FRAME-COPY-LIST)
	((PDL-PUSH) DPB PDL-INDEX Q-POINTER (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	((PDL-PUSH) M-C)	;Args to CONS: the new frame copy,
	((PDL-PUSH) M-T)	;and the list of older ones.
	(CALL XCONS)
	((PDL-INDEX) PDL-POP)
	((C-PDL-BUFFER-INDEX) M-T)
	((M-T) PDL-POP)
	((M-E) PDL-POP)
STACK-CLOSURE-DISCONNECT-REPLACE
	((VMA-START-READ) ADD M-E (A-CONSTANT 1))
	(CHECK-PAGE-READ)
	(DISPATCH TRANSPORT MD)
	((VMA-START-READ) MD)
	(CHECK-PAGE-READ)
	(DISPATCH TRANSPORT MD)
	;; MD has the word that points to the stack closure vector.
	;; Make it point to the copy instead, preserving the cdr code.
	((M-1) MD)
	((MD-START-WRITE) DPB M-T Q-TYPED-POINTER A-1)
	(CHECK-PAGE-WRITE)
	(POPJ)

STACK-CLOSURE-DISCONNECT-EMPTY
	((M-E) PDL-POP)
	(POPJ)

;Make a copy of the stack closure vector,
;with the same contents (a bunch of EVCPs) if M-A is NIL,
;with the values copied from the individual locals or args if M-A is not NIL.

;On return, M-C has the copy.  M-J has the pdl index of the word that holds the original.
;Except: if the vector in this frame is empty (that is, it is T) then M-J isn't set up.
STACK-CLOSURE-VECTOR-COPY
	(CALL STACK-CLOSURE-FRAME-COPY-LIST)
	((PDL-INDEX) SUB PDL-INDEX (A-CONSTANT 1))
	((PDL-PUSH) M-A)
	((PDL-PUSH M-K) DPB C-PDL-BUFFER-INDEX Q-POINTER
			(A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	(CALL GET-PDL-BUFFER-INDEX)	;Convert address in M-K to pdl index in M-K.
	((M-B) SUB PDL-INDEX A-K)
	((M-B) PDL-BUFFER-ADDRESS-MASK M-B)
;NOTE: 2 pushes have happened so far as of here.
	(JUMP-EQUAL M-B A-ZERO STACK-CLOSURE-VECTOR-COPY-EMPTY)
;M-B now has size of the stack closure vector.
	((PDL-PUSH) DPB M-B Q-POINTER (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	(CALL-XCT-NEXT LCONS)
       ((M-S) DPB M-ZERO Q-ALL-BUT-TYPED-POINTER A-BACKGROUND-CONS-AREA)
	((M-B) Q-POINTER PDL-POP)
	((M-K) PDL-POP)
	((M-A) PDL-POP)
;Put the copy in M-C.
	((M-C) DPB M-T Q-POINTER (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-LIST)))
	((VMA) SUB M-T (A-CONSTANT 1))
	(CALL LOAD-PDL-BUFFER-INDEX)
	((M-J) PDL-INDEX)
	(JUMP-NOT-EQUAL M-A A-V-NIL STACK-CLOSURE-VECTOR-COPY-2)
;Fill the copy with forwarding pointers to the stack frame.
;VMA advances thru the copy while M-J, a pdl index, advances thru the stack closure vector.
STACK-CLOSURE-VECTOR-COPY-1
	((PDL-INDEX) M-J)
	((MD) C-PDL-BUFFER-INDEX)
	((VMA-START-WRITE) ADD VMA (A-CONSTANT 1))
	(CHECK-PAGE-WRITE)
	((M-J) ADD M-J (A-CONSTANT 1))
	(JUMP-GREATER-THAN-XCT-NEXT M-B (A-CONSTANT 1) STACK-CLOSURE-VECTOR-COPY-1)
       ((M-B) SUB M-B (A-CONSTANT 1))
	(POPJ)

;Fill the copy with actual values of variables.
;VMA advances thru the copy while M-J, a pdl index, advances thru the stack closure vector.
STACK-CLOSURE-VECTOR-COPY-2
	((PDL-INDEX) M-J)
	((M-K) C-PDL-BUFFER-INDEX)
;M-K has a forwarding pointer to s stack frame slot.
;It also has the desired cdr-code.
	(CALL LOAD-PDL-BUFFER-INDEX)
	((MD) DPB C-PDL-BUFFER-INDEX Q-TYPED-POINTER A-K)
	((VMA-START-WRITE) ADD VMA (A-CONSTANT 1))
	(CHECK-PAGE-WRITE)
	((M-J) ADD M-J (A-CONSTANT 1))
	(JUMP-GREATER-THAN-XCT-NEXT M-B (A-CONSTANT 1) STACK-CLOSURE-VECTOR-COPY-2)
       ((M-B) SUB M-B (A-CONSTANT 1))
	(POPJ)

STACK-CLOSURE-VECTOR-COPY-EMPTY
	(POPJ-AFTER-NEXT (PDL-POINTER) SUB PDL-POINTER (A-CONSTANT 2))
       ((M-C) A-V-TRUE)

;; Make sure a particular stack closure in the active frame is copied,
;; if anything points to it.  Also invalidate the stack closure block
;; so that if another stack closure is wanted in the same block
;; it will be reinitialized from scratch.

;; M-A specifies the local block offset of the stack closure block to check.
;; The copy itself is returned in M-E, or NIL if no copy had to be made.
STACK-CLOSURE-CLEAR
	((M-E) A-V-NIL)
	((M-K PDL-INDEX) ADD M-A A-LOCALP)
	(POPJ-EQUAL C-PDL-BUFFER-INDEX A-V-NIL)  ;Nothing set up there now => don't copy.
	(CALL CONVERT-PDL-BUFFER-ADDRESS)
	((M-B) DPB M-K Q-POINTER (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-STACK-CLOSURE)))
;; Check as fast as possible whether there are any pointers within the frame.
;; Save PDL-POINTER in M-C so we can restore it later in all paths.
	((M-C) PDL-POINTER)
STACK-CLOSURE-CLEAR-1
	((M-1) Q-TYPED-POINTER PDL-POP)
	(JUMP-NOT-EQUAL-XCT-NEXT PDL-POINTER A-AP STACK-CLOSURE-CLEAR-1)
	(JUMP-EQUAL M-1 A-B STACK-CLOSURE-CLEAR-SLOW)
	((PDL-POINTER) M-C)
	((M-E) DPB C-PDL-BUFFER-INDEX Q-POINTER
		   (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-CLOSURE)))
	((M-1) Q-DATA-TYPE C-PDL-BUFFER-INDEX)
	((C-PDL-BUFFER-INDEX) A-V-NIL)
	(POPJ-AFTER-NEXT POPJ-EQUAL M-1 (A-CONSTANT (EVAL DTP-EXTERNAL-VALUE-CELL-POINTER)))
       ((M-E) A-V-NIL)

;; There is a pointer to this stack closure.
STACK-CLOSURE-CLEAR-SLOW
	((PDL-POINTER) M-C)
;; Forward it into heap if not already done.
	((MD) Q-TYPED-POINTER C-PDL-BUFFER-INDEX)
	((M-1) Q-DATA-TYPE MD)
	(JUMP-EQUAL M-1 (A-CONSTANT (EVAL DTP-EXTERNAL-VALUE-CELL-POINTER))
		    STACK-CLOSURE-CLEAR-2)
	((VMA) M-B)
	(CALL STACK-CLOSURE-COPY)
;; Now in either case the address of the copy is in MD.
STACK-CLOSURE-CLEAR-2
	((M-E) DPB MD Q-POINTER (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-CLOSURE)))
;; Save PDL-POINTER in M-C so we can restore it later in all paths.
	((M-C) PDL-POINTER)
;; Replace each pointer to the original stack closure (in M-B)
;; with an ordinary closure pointing to the copy (in M-E).
STACK-CLOSURE-CLEAR-3
	((M-1) Q-TYPED-POINTER PDL-POP)
	(JUMP-NOT-EQUAL-XCT-NEXT PDL-POINTER A-AP STACK-CLOSURE-CLEAR-3)
	(CALL-EQUAL M-1 A-B STACK-CLOSURE-CLEAR-FOUND)
	((PDL-POINTER) M-C)
	(POPJ-AFTER-NEXT
	 (PDL-INDEX) ADD M-A A-LOCALP)
       ((C-PDL-BUFFER-INDEX) A-V-NIL)

STACK-CLOSURE-CLEAR-FOUND
	((PDL-INDEX) ADD PDL-POINTER (A-CONSTANT 1))
	(POPJ-AFTER-NEXT (M-1) C-PDL-BUFFER-INDEX)
       ((C-PDL-BUFFER-INDEX) DPB M-E Q-TYPED-POINTER A-1)

;; Unshare a local variable
;; in all copies (made by STACK-CLOSURE-DISCONNECT) of this frame's stack closure vector.
;; The address field of the instruction is a 9-bit number
;; which is this variable's index in the stack closure vector.

;; This instruction is never used in a frame whose stack closure vector is T (empty).

STACK-CLOSURE-UNSHARE
	(CALL STACK-CLOSURE-FRAME-COPY-LIST)
	(POPJ-EQUAL M-T A-V-NIL)
;M-T has list of stack closure vector copies to unshare.
	((PDL-INDEX) SUB PDL-INDEX (A-CONSTANT 1))
;M-J has the stack closure vector of this frame.
#+cadr	((M-B) M-INST-ADR)
#+lambda((M-B) MACRO-IR-ADR)
	((M-K) ADD C-PDL-BUFFER-INDEX A-B)
;M-K has the memory address of this local's slot in the stack closure vector.
	(CALL LOAD-PDL-BUFFER-INDEX)
;M-K gets the EVCP that lives in the stack closure vector.
;It points to the stack frame slot for this local.
	((M-K) Q-TYPED-POINTER C-PDL-BUFFER-INDEX)
	(CALL LOAD-PDL-BUFFER-INDEX)
;M-C gets the current value of the local.
	((M-C) Q-TYPED-POINTER C-PDL-BUFFER-INDEX)
	((M-1) M-ZERO)
;M-K has an evcp -> the stack slot for the local we are unsharing.
;M-C has what to store in place of any evcps pointing to this local.
;M-1 is zero if we have not yet found an evcp pointing to this local.
;M-B has the index of this local's slot in the stack closure vector, and in copies of it.
;M-T has the list of all stack closure vector copies made in this frame.
;Examine each element of the list.
;Note that all the ones we need to unforward
;must be more recent than the ones we don't need to unforward,
;so we can exit the first time we find one already unforwarded.
STACK-CLOSURE-UNSHARE-1
	(POPJ-EQUAL M-T A-V-NIL)
	(CALL CARCDR-NO-SB)
	;; M-A has address of copy of stack closure vector.
	((VMA-START-READ) ADD M-A A-B)
	(CHECK-PAGE-READ)
	;; MD has the stack closure vector copy's data for this local.
	((M-2) Q-TYPED-POINTER MD)
	(POPJ-NOT-EQUAL M-2 A-K)
	;; It is forwarded to the stack.  Store M-C in it, preserving cdr-code.
	((M-2) MD)
	((MD-START-WRITE) DPB M-C Q-TYPED-POINTER A-2)
	(CHECK-PAGE-WRITE)
	(JUMP-NOT-EQUAL M-1 A-ZERO STACK-CLOSURE-UNSHARE-1)
	((M-1) M-MINUS-ONE)
	;; Forward the similar cells of any other stack frame copies
	;; to the cell in this stack frame copy.
	((M-C) DPB VMA Q-POINTER
	       (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-EXTERNAL-VALUE-CELL-POINTER)))
	(JUMP STACK-CLOSURE-UNSHARE-1)

;; Return in M-T the list of all copies of this stack frame
;; made by STACK-CLOSURE-DISCONNECT for copies of stack closures.
;; This list lives in the last cell of the frame's local block.
;; Also leaves the PDL-INDEX pointing to that slot.
STACK-CLOSURE-FRAME-COPY-LIST
	((PDL-INDEX) M-AP)
	((VMA-START-READ) ADD C-PDL-BUFFER-INDEX (A-CONSTANT (EVAL %FEFHI-MISC)))
	((M-T) ADD M-MINUS-ONE A-LOCALP)
	(CHECK-PAGE-READ)
	((PDL-INDEX) (LISP-BYTE %%FEFHI-MS-LOCAL-BLOCK-LENGTH) READ-MEMORY-DATA)
	(POPJ-AFTER-NEXT
	 (PDL-INDEX) ADD PDL-INDEX A-T)
       ((M-T) C-PDL-BUFFER-INDEX)

;; Make all stack closure vector copies belonging to stack closures originally in this frame
;; forward to a specified new stack closure vector copy (address in M-J)
;; rather than forwarding to the stack frame itself.
;; Called from QMEX1-COPY as part of exiting a frame in which stack closures have been made
;; (but not called if the frame's stack closure vector is empty).
;; Preserves M-C and M-D.
STACK-CLOSURE-UNSHARE-ALL
	(CALL STACK-CLOSURE-FRAME-COPY-LIST)
	(POPJ-EQUAL M-T A-V-NIL)
	((M-K) M-AP)
	(CALL CONVERT-PDL-BUFFER-ADDRESS)
	((M-K) DPB M-K Q-POINTER
	       (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-EXTERNAL-VALUE-CELL-POINTER)))
	((PDL-INDEX) SUB PDL-INDEX A-AP)
	((M-E) M+A+1 PDL-INDEX A-K)
;M-K has EVCP -> of start of stack frame,
;M-E has EVCP -> end of stack frame (first word after end of local block),
;M-J has address of the new copy.
;M-T has the list of all copies already made.
STACK-CLOSURE-UNSHARE-ALL-1
	(POPJ-EQUAL M-T A-V-NIL)
	(CALL CARCDR-NO-SB)
;M-A has address of the old stack closure vector copy.
;Now replace each forward that points to the real stack frame
;with a forward to the corresponding word of the new copy (M-J).
	((VMA) SUB M-A (A-CONSTANT 1))
STACK-CLOSURE-UNSHARE-ALL-3
	((VMA-START-READ) ADD VMA (A-CONSTANT 1))
	(CHECK-PAGE-READ)
	((M-2) Q-TYPED-POINTER MD)
	((M-1) Q-CDR-CODE MD)
	(JUMP-LESS-THAN M-2 A-K STACK-CLOSURE-UNSHARE-ALL-4)
	(JUMP-GREATER-OR-EQUAL M-2 A-E STACK-CLOSURE-UNSHARE-ALL-4)
	((M-2) SUB VMA M-A)
	((M-2) ADD M-2 A-J)
	((M-3) MD)
	((MD-START-WRITE) DPB M-2 Q-POINTER A-3)
	(CHECK-PAGE-WRITE)
STACK-CLOSURE-UNSHARE-ALL-4
	(JUMP-NOT-EQUAL M-1 (A-CONSTANT (EVAL CDR-NIL)) STACK-CLOSURE-UNSHARE-ALL-3)
;Now this one is done.  Look at the next closure in the list.
	(JUMP STACK-CLOSURE-UNSHARE-ALL-1)

;; Fill the last several local slots (except the last two)
;; with forwards to the stack slots for the args and locals of this frame
;; that lexical closures will want to refer to.

;; We get the list of what to forward to from the fef cell just before the debugging info.
;; We store a pointer to the first slot of the block we construct
;; into the next-to-the-last local slot, and return it in M-C.
;; Preserves M-I, M-J, M-2.
MAKE-STACK-CLOSURE-VECTOR
	((PDL-INDEX) M-AP)
	((VMA-START-READ) ADD C-PDL-BUFFER-INDEX (A-CONSTANT (EVAL %FEFHI-MISC)))
	(CHECK-PAGE-READ)
;Get number of locals of this function.
	((PDL-INDEX) (LISP-BYTE %%FEFHI-MS-LOCAL-BLOCK-LENGTH) READ-MEMORY-DATA)
	((PDL-INDEX) ADD PDL-INDEX A-LOCALP)
;Point to next-to-the-last local slot.
	((M-D PDL-INDEX) M-A-1 PDL-INDEX (A-CONSTANT 1))
;Already non-NIL => it points to the stack-closure-vector, already set up,
;so return that in M-C.
	((M-C) Q-TYPED-POINTER C-PDL-BUFFER-INDEX)
	(POPJ-NOT-EQUAL M-C A-V-NIL)
;Otherwise, M-C points same as M-D.  We will decrement M-C once to get first slot to store.
	((M-C) M-D)
;Mark this stack frame so that tail recursion will not flush it.
	((PDL-INDEX) ADD M-AP (A-CONSTANT (EVAL %LP-ENTRY-STATE)))
	((M-1) PDL-INDEX-INDIRECT)
	((PDL-INDEX-INDIRECT) DPB M-MINUS-ONE (LISP-BYTE %%LP-ENS-UNSAFE-REST-ARG) A-1)
;Get the fef cell preceding the debugging info.
	((VMA-START-READ) SUB VMA (A-CONSTANT (EVAL %FEFHI-MISC)))
	(CHECK-PAGE-READ)   ;No transport; the executing fef can't be in oldspace.
	((M-1) (LISP-BYTE %%FEFH-PC-IN-WORDS) MD)
	((M-1) M-A-1 M-1 (A-CONSTANT 1))
	((VMA-START-READ) ADD VMA A-1)
	(CHECK-PAGE-READ)
	(DISPATCH TRANSPORT MD)
	((VMA) Q-TYPED-POINTER MD)
;NIL there in the fef means the stack closure vector is supposed to be empty.
	(JUMP-EQUAL VMA A-V-NIL MAKE-STACK-CLOSURE-VECTOR-EMPTY)
;Otherwise it is a compact list, each element spec'ing one vector element.
;Make an EVCP pointing to the stack frame.
	((M-K) M-AP)
	(CALL CONVERT-PDL-BUFFER-ADDRESS)
	((M-K) DPB M-K Q-POINTER
	       (A-CONSTANT (PLUS (BYTE-VALUE Q-DATA-TYPE DTP-EXTERNAL-VALUE-CELL-POINTER)
				 (BYTE-VALUE Q-CDR-CODE CDR-NEXT))))
	((PDL-INDEX) A-LOCALP)
	((PDL-INDEX) SUB PDL-INDEX A-AP)
	((M-B) SUB PDL-INDEX (A-CONSTANT 1))
;; M-B has offset of local block with respect to argument 0.
;; M-K has an evcp pointing to start of stack frame, with CDR-NEXT.
;; VMA points into list that specifies locals and args to make forwards to.
;;  Each element of this list is a fixnum, either arg number, or local number + sign bit.
;; M-C has 1+ pdl slot to store in next.
;; M-D has pdl slot in which to store the pointer to the list we are making.
MAKE-STACK-CLOSURE-VECTOR-LOOP
	((VMA-START-READ) VMA)
	(CHECK-PAGE-READ)
	(DISPATCH TRANSPORT MD)
	(JUMP-IF-BIT-CLEAR-XCT-NEXT BOXED-SIGN-BIT MD MAKE-STACK-CLOSURE-VECTOR-ARG)
       ((M-1) (BYTE-FIELD 10. 0) MD)
	((M-1) ADD M-1 A-B)
MAKE-STACK-CLOSURE-VECTOR-ARG
	((M-C PDL-INDEX) SUB M-C (A-CONSTANT 1))
	((C-PDL-BUFFER-INDEX) M+A+1 M-K A-1)
	((M-1) Q-CDR-CODE MD)
	(JUMP-NOT-EQUAL-XCT-NEXT M-1 (A-CONSTANT (EVAL CDR-NIL))
				 MAKE-STACK-CLOSURE-VECTOR-LOOP)
       ((VMA) ADD VMA (A-CONSTANT 1))
	((PDL-INDEX) SUB M-D (A-CONSTANT 1))
	((C-PDL-BUFFER-INDEX) DPB C-PDL-BUFFER-INDEX Q-TYPED-POINTER
			      (A-CONSTANT (BYTE-VALUE Q-CDR-CODE CDR-NIL)))
	((PDL-INDEX) SUB M-C (A-CONSTANT 1))
	((C-PDL-BUFFER-INDEX) DPB M-K Q-POINTER
			      (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-LIST)))
;M-C is pdl index of start of stack closure vector.  Convert it to memory address.
	((PDL-INDEX) SUB M-C A-AP)
	((M-C) ADD PDL-INDEX A-K)
	(POPJ-AFTER-NEXT
	 (PDL-INDEX) M-D)
       ((C-PDL-BUFFER-INDEX M-C) DPB M-C Q-POINTER
				 (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-LIST)))

;; Here when this frame's stack closure vector can be empty.
;; This happens when this function makes lexical closures
;; that refer to outer lexical levels but never refer to any arg or local of this function.
;; T is used for an empty stack closure vector,
;; since NIL is used to mean that the vector has not been set up.
MAKE-STACK-CLOSURE-VECTOR-EMPTY
	(POPJ-AFTER-NEXT
	 (PDL-INDEX) M-D)
       ((C-PDL-BUFFER-INDEX M-C) A-V-TRUE)

;A lexical closure is a pointer with type DTP-CLOSURE or DTP-STACK-CLOSURE
;to a couple of lists on the stack which look like
;(function (stack-closure-vector . ,LEXICAL-ENVIRONMENT))

;This uses four words which live in the local block of the stack frame,
;after all the actual locals of the function.
;The local block index of the first of the words
;is specified in the low 9 bits of the MAKE-STACK-CLOSURE instruction.

;When lexical closures are in use in a frame,
;the last slot in the local block is used to hold a list of all
;copies of the stack frame made by STACK-CLOSURE-DISCONNECT.
;This list is accessed with STACK-CLOSURE-FRAME-COPY-LIST.

;The next to the last slot is a pointer to the stack-closure-vector of the frame.

;Several slots before that one contain the stack-closure-vector itself.
;The stack-closure-vector is a list which lives in the last part
;of the local block of this frame; it contains EVCPs pointing to various args and locals.
;All the stack closures made in this frame use the same stack-closure-vector.
;It is created by code on the previous page.

;The slot before the beginning of the stack-closure-vector
;contains a DTP-LIST pointer to the beginning of the stack frame.

;The function is popped off the stack.
;We push on, in its place, a pointer to the first slot, with DTP-STACK-CLOSURE,
;after storing the proper values in all six slots.

MAKE-STACK-CLOSURE
	((M-I) Q-TYPED-POINTER PDL-POP)
	((PDL-BUFFER-INDEX) ADD M-AP (A-CONSTANT (EVAL %LP-ENTRY-STATE)))
	((M-2) C-PDL-BUFFER-INDEX)
	((C-PDL-BUFFER-INDEX) DPB M-MINUS-ONE (LISP-BYTE %%LP-ENS-UNSAFE-REST-ARG) A-2)
;Put in M-T the memory address of the first slot.
#+cadr	((M-K) M-INST-ADR)
#+lambda((M-K) MACRO-IR-ADR)
	((PDL-INDEX M-K) ADD M-K A-LOCALP)
	(CALL CONVERT-PDL-BUFFER-ADDRESS)
	((PDL-PUSH M-J) DPB M-K Q-POINTER (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-STACK-CLOSURE)))
;Examine first slot; non-NIL means everything already set up.
	((M-1) Q-TYPED-POINTER C-PDL-BUFFER-INDEX)
	(POPJ-NOT-EQUAL M-1 A-V-NIL)
;M-C now gets frame's stack-closure-vector (either a cons, or the symbol T).
	((M-2) PDL-INDEX)
	(CALL MAKE-STACK-CLOSURE-VECTOR)
	((PDL-INDEX) M-2)
;Set up the first slot.
	((C-PDL-BUFFER-INDEX) DPB M-I Q-TYPED-POINTER
			      (A-CONSTANT (BYTE-VALUE Q-CDR-CODE CDR-NEXT)))
;Set up the second slot; points to third slot, and cdr-nil.
	((PDL-BUFFER-INDEX) M+1 PDL-BUFFER-INDEX)
	((M-K) ADD M-J (A-CONSTANT 2))
	((C-PDL-BUFFER-INDEX) DPB M-K Q-POINTER 
			      (A-CONSTANT (PLUS (BYTE-VALUE Q-DATA-TYPE DTP-LIST)
						(BYTE-VALUE Q-CDR-CODE CDR-NIL))))
;Set up the third slot, -> stack closure vector of frame.  Third and fourth are a cons cell
	((PDL-BUFFER-INDEX) M+1 PDL-BUFFER-INDEX)
	((C-PDL-BUFFER-INDEX) DPB M-C Q-TYPED-POINTER 
			      (A-CONSTANT (BYTE-VALUE Q-CDR-CODE CDR-NORMAL)))
;Set up the fourth slot; it's the lexical environment of entry to this frame.
	((PDL-BUFFER-INDEX) M+1 PDL-BUFFER-INDEX)
	(POPJ-AFTER-NEXT
	 (M-K) A-LEXICAL-ENVIRONMENT)
       ((C-PDL-BUFFER-INDEX) DPB M-K Q-TYPED-POINTER 
			     (A-CONSTANT (BYTE-VALUE Q-CDR-CODE CDR-ERROR)))

;Get and set lexical variables inherited from outer contexts.
XSTORE-IN-HIGHER-CONTEXT
	(MISC-INST-ENTRY %STORE-IN-HIGHER-CONTEXT)
	(CALL XLOAD-FROM-HIGHER-CONTEXT)
	((M-S) DPB VMA Q-POINTER
	       (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-LOCATIVE)))
	((M-T) PDL-POP)
	(JUMP-XCT-NEXT XSETCAR1)
       ((M-A) M-T)

XLOCATE-IN-HIGHER-CONTEXT
	(MISC-INST-ENTRY %LOCATE-IN-HIGHER-CONTEXT)
	(CALL XLOAD-FROM-HIGHER-CONTEXT)
	(POPJ-AFTER-NEXT NO-OP)
       ((M-T) DPB VMA Q-POINTER
	      (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-LOCATIVE)))

;Returns address of slot in VMA as well as value of variable in M-T.
XLOAD-FROM-HIGHER-CONTEXT
	(MISC-INST-ENTRY %LOAD-FROM-HIGHER-CONTEXT)
;Compute in M-T the address of a local or arg in a higher lexical context.
;Pops a word off the stack to specify where to find the local:
;  High 12. bits  Number of contexts to go up (0 => immediate higher context)
;  Low 12. bits	  Slot number in that context.
	((M-1) (BYTE-FIELD 12. 12.) PDL-TOP)
	(JUMP-EQUAL-XCT-NEXT M-1 A-ZERO XLOAD-FROM-HIGHER-CONTEXT-2)
       ((VMA) DPB M-ZERO Q-ALL-BUT-POINTER A-LEXICAL-ENVIRONMENT)
XLOAD-FROM-HIGHER-CONTEXT-1
;Take CDR of the next pair.  We know it is a two-Q cons cell.
	(CALL-XCT-NEXT PDL-FETCH)
       ((VMA) ADD VMA (A-CONSTANT 1))
	(DISPATCH TRANSPORT MD)
	((VMA) Q-POINTER MD)
	(JUMP-GREATER-THAN-XCT-NEXT M-1 (A-CONSTANT 1) XLOAD-FROM-HIGHER-CONTEXT-1)
       ((M-1) SUB M-1 (A-CONSTANT 1))

XLOAD-FROM-HIGHER-CONTEXT-2
;Take CAR of the cell we have reached, to get the stack closure vector or copy.
;M-C gets the index therein.
	(CALL-XCT-NEXT PDL-FETCH)
       ((M-C) (BYTE-FIELD 12. 0) PDL-POP)
	(DISPATCH TRANSPORT MD)
;Access that word in the vector (which is actually a cdr-coded list, not a vector).
	((VMA) ADD MD A-C)
	(CALL-XCT-NEXT PDL-FETCH)
       ((VMA) Q-POINTER VMA)
;Check explicitly for an EVCP there pointing to the pdl buffer.
;This is faster than transporting the usual way because we still avoid
;going through the page fault handler.
	((M-1) Q-DATA-TYPE MD)
	(JUMP-NOT-EQUAL M-1 (A-CONSTANT (EVAL DTP-EXTERNAL-VALUE-CELL-POINTER))
			    XLOAD-FROM-HIGHER-CONTEXT-3)
	((M-1) Q-POINTER MD)
	((PDL-INDEX M-2) SUB M-1 A-PDL-BUFFER-VIRTUAL-ADDRESS)
	(JUMP-NOT-EQUAL PDL-INDEX M-2 XLOAD-FROM-HIGHER-CONTEXT-3)
;It is an EVCP and does point into the pdl buffer.
	(POPJ-AFTER-NEXT
	 (M-T) DPB C-PDL-BUFFER-INDEX Q-POINTER
	       (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-LOCATIVE)))
       ((VMA) DPB MD Q-POINTER VMA)

;Not an EVCP or doesn't point to pdl buffer.  Do regular transport.
;Do this even if EVCP not pointing to pdl buffer, in case it points to oldspace.
XLOAD-FROM-HIGHER-CONTEXT-3
	(DISPATCH TRANSPORT MD)
	(POPJ-AFTER-NEXT NO-OP)
       ((M-T) Q-TYPED-POINTER MD)
	
;MD gets contents of untyped virtual address in VMA, when likely to be in pdl buffer.
;Does not assume that the address is actually in the current regpdl.

;this is a clever hack:

; If the VMA is less than A-PDL-BUFFER-VIRTUAL-ADDRESS, then the subtraction
; will produce a negative number, which will be stored in M-2, but will be
; masked to 10. or 11. bits in PDL-INDEX.  Therefore, the following instruction
; will jump.

; If the VMA is bigger than A-PDL-BUFFER-VIRTUAL-ADDRESS + size-of the PDL-BUFFER
; then again, M-2 will contain a number bigger than will fit in PDL-INDEX, so
; the jump will happen.

; The first jump makes sure the VMA is not just past the end of the PDL buffer array.
; This is necessary if the hardware pdl buffer is not very full, and we are
; storing into the beginning of the next PDL in memory.
PDL-FETCH
   ;****
	(jump-greater-or-equal vma a-qlpdlh pdl-fetch-1)
	((PDL-INDEX M-2) SUB VMA A-PDL-BUFFER-VIRTUAL-ADDRESS)
	(JUMP-NOT-EQUAL PDL-INDEX A-2 PDL-FETCH-1)
	(POPJ-AFTER-NEXT
	 (PDL-INDEX) ADD PDL-INDEX A-PDL-BUFFER-HEAD)
       ((MD) C-PDL-BUFFER-INDEX)

PDL-FETCH-1
	(POPJ-AFTER-NEXT (VMA-START-READ) VMA)
       (CHECK-PAGE-READ)

))