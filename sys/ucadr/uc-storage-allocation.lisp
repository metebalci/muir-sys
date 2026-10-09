;-*-Mode:Midas-*-
;the #+CADR, #+LAMBDA, #-CADR and #-LAMBDA choices between the CADR and
;the Lambda are resolved as the CADR's reader resolves them, and Lambda-only
;BEGIN-COMMENT blocks are deleted.  No instruction or symbol is changed.

(SETQ UC-STORAGE-ALLOCATION '(

;;; These are not callable with MISC instructions, only as functions.
;;; They are documented as taking an &REST argument but actually take 63 optional args.
;;; When entered, the arguments are on the stack and M-R contains the number of them.
;;; (M-AP)+1 is the first argument, (PP) is the last.
	(MISC-INST-ENTRY LIST)
XLIST	(JUMP-EQUAL M-R A-ZERO XFALSE)
	(CALL-XCT-NEXT LCONS-D)
       ((M-B) Q-POINTER M-R)
XLIST0	((WRITE-MEMORY-DATA) LDB C-PDL-BUFFER-POINTER-POP
		Q-ALL-BUT-CDR-CODE (A-CONSTANT (BYTE-VALUE Q-CDR-CODE CDR-NIL)))
	((VMA) ADD M-T A-B)
	((M-T) DPB Q-POINTER M-T (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-LIST)))
XLIST1	((VMA-START-WRITE) SUB VMA (A-CONSTANT 1))
	(CHECK-PAGE-WRITE)
	(GC-WRITE-TEST)
	((M-B) SUB M-B (A-CONSTANT 1))
XLIST2	(POPJ-LESS-OR-EQUAL M-B A-ZERO)
	(JUMP-XCT-NEXT XLIST1)
       ((WRITE-MEMORY-DATA) LDB C-PDL-BUFFER-POINTER-POP
		Q-ALL-BUT-CDR-CODE (A-CONSTANT (BYTE-VALUE Q-CDR-CODE CDR-NEXT)))

	(MISC-INST-ENTRY LIST*)
XLISTR	(JUMP-EQUAL M-R (A-CONSTANT 1) POPTJ)
	(CALL-XCT-NEXT LCONS-D)
       ((M-B) Q-POINTER M-R)
XLISTR0	((VMA) ADD M-T A-B)
	((M-T) DPB Q-POINTER M-T (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-LIST)))
	((WRITE-MEMORY-DATA) LDB C-PDL-BUFFER-POINTER-POP
		Q-ALL-BUT-CDR-CODE (A-CONSTANT (BYTE-VALUE Q-CDR-CODE CDR-ERROR)))
	((VMA-START-WRITE) SUB VMA (A-CONSTANT 1))
	(CHECK-PAGE-WRITE)
	(GC-WRITE-TEST)
	((WRITE-MEMORY-DATA) LDB C-PDL-BUFFER-POINTER-POP
		Q-ALL-BUT-CDR-CODE (A-CONSTANT (BYTE-VALUE Q-CDR-CODE CDR-NORMAL)))
	((VMA-START-WRITE) SUB VMA (A-CONSTANT 1))
	(CHECK-PAGE-WRITE)
	(GC-WRITE-TEST)
	(JUMP-XCT-NEXT XLIST2)
       ((M-B) SUB M-B (A-CONSTANT 2))

;;; Note that these two never pop their first argument.  This doesn't matter when
;;; calling them as functions, but if you try to make a MISC-instruction interface
;;; to these you will need to be aware of that.
	(MISC-INST-ENTRY LIST-IN-AREA)
XLISTA	(JUMP-EQUAL M-R (A-CONSTANT 1) XFALSE)
	((PDL-BUFFER-INDEX) ADD M-AP (A-CONSTANT 1))
	((M-S) Q-TYPED-POINTER C-PDL-BUFFER-INDEX)
	((M-B) SUB M-R (A-CONSTANT 1))
	(JUMP-XCT-NEXT XLIST0)
       (CALL LCONS)
	
	(MISC-INST-ENTRY LIST*-IN-AREA)
XLISTRA	(JUMP-EQUAL M-R (A-CONSTANT 2) POPTJ)
	((PDL-BUFFER-INDEX) ADD M-AP (A-CONSTANT 1))
	((M-S) Q-TYPED-POINTER C-PDL-BUFFER-INDEX)
	((M-B) SUB M-R (A-CONSTANT 1))
	(JUMP-XCT-NEXT XLISTR0)
       (CALL LCONS)

;THIS IS THE NEW PRIMITIVE CALLED BY MAKE-LIST.  ARGUMENTS ARE
;INITIAL-VALUE, AREA, LENGTH.

(ERROR-TABLE DEFAULT-ARG-LOCATIONS %MAKE-LIST PP M-S M-B)

XNMKLS (MISC-INST-ENTRY %MAKE-LIST)
		(ERROR-TABLE RESTART XNMKLS)
	(DISPATCH (I-ARG DATA-TYPE-INVOKE-OP)
		Q-DATA-TYPE C-PDL-BUFFER-POINTER TRAP-UNLESS-FIXNUM)
    (ERROR-TABLE ARGTYP FIXNUM PP 2 XNMKLS)
	(CALL-IF-BIT-SET BOXED-SIGN-BIT C-PDL-BUFFER-POINTER TRAP)
    (ERROR-TABLE ARGTYP NONNEGATIVE-FIXNUM PP 2 XNMKLS)
    (ERROR-TABLE ARG-POPPED 0 PP PP PP)
	((M-B) Q-POINTER C-PDL-BUFFER-POINTER-POP)	;THIRD ARG NUMBER OF QS
	((M-S) Q-TYPED-POINTER C-PDL-BUFFER-POINTER-POP) ;SECOND ARG AREA
	(JUMP-EQUAL M-B A-ZERO POP-THEN-XFALSE)		;ZERO LENGTH LIST IS NIL
	(CALL LIST-OF-THINGS)				;TAKES INITIAL-VALUE ON STACK
	(POPJ-AFTER-NEXT
	 (M-T) Q-POINTER M-T (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-LIST)))
       (NO-OP)


;THESE VARIOUS CONSING ROUTINES HAD BETTER NOT CLOBBER M-C.  OTHER REGS PROBABLY OK.

(ERROR-TABLE DEFAULT-ARG-LOCATIONS XCONS (PP 1) (PP 0))

XXCONS (MISC-INST-ENTRY XCONS)			;XCONS
	(JUMP-XCT-NEXT XXCON1)
       ((M-S) DPB M-ZERO Q-ALL-BUT-TYPED-POINTER A-CNSADF)	;USE DEFAULT AREA

(ERROR-TABLE DEFAULT-ARG-LOCATIONS XCONS-IN-AREA (PP 1) (PP 0) M-S)

XXCONA (MISC-INST-ENTRY XCONS-IN-AREA)		;XCONS, WITH AREA AS THIRD ARG
	((M-S) Q-TYPED-POINTER C-PDL-BUFFER-POINTER-POP)
XXCON1	((M-B) C-PDL-BUFFER-POINTER-POP)	;EXCH ARGS
	((M-A) C-PDL-BUFFER-POINTER-POP)
	((C-PDL-BUFFER-POINTER-PUSH) M-B)
	(JUMP-XCT-NEXT QCONS)
       ((C-PDL-BUFFER-POINTER-PUSH) M-A)

(ERROR-TABLE DEFAULT-ARG-LOCATIONS NCONS (PP 1))

XNCONS (MISC-INST-ENTRY NCONS)			;NCONS
	(JUMP-XCT-NEXT XNCON1)
       ((M-S) DPB M-ZERO Q-ALL-BUT-TYPED-POINTER A-CNSADF)

(ERROR-TABLE DEFAULT-ARG-LOCATIONS NCONS-IN-AREA (PP 1) M-S)

XNCONA (MISC-INST-ENTRY NCONS-IN-AREA)		;NCONS, WITH AREA AS SECOND ARG
	((M-S) Q-TYPED-POINTER C-PDL-BUFFER-POINTER-POP)
XNCON1	(JUMP-XCT-NEXT QCONS)
       ((C-PDL-BUFFER-POINTER-PUSH) A-V-NIL)

(ERROR-TABLE DEFAULT-ARG-LOCATIONS CONS PP PP)

XCONS (MISC-INST-ENTRY CONS)			;CONS
	((M-S) DPB M-ZERO Q-ALL-BUT-TYPED-POINTER A-CNSADF)	;USE DEFAULT AREA
QCONS	(CALL-XCT-NEXT LCONS)			;ALLOCATE 2 Q'S, RETURN POINTER IN M-T,
       ((M-B) (A-CONSTANT 2))			;ALLOCATE FROM LIST SPACE
	((WRITE-MEMORY-DATA) DPB Q-TYPED-POINTER
		C-PDL-BUFFER-POINTER-POP 
		(A-CONSTANT (BYTE-VALUE Q-CDR-CODE CDR-ERROR)))
	((VMA-START-WRITE) ADD M-T (A-CONSTANT 1))
	(CHECK-PAGE-WRITE)
	(GC-WRITE-TEST)
	((WRITE-MEMORY-DATA) DPB Q-TYPED-POINTER 
		C-PDL-BUFFER-POINTER-POP 
		(A-CONSTANT (BYTE-VALUE Q-CDR-CODE CDR-NORMAL)))
	((VMA-START-WRITE M-T) DPB M-T Q-POINTER
		(A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-LIST)))
	(CHECK-PAGE-WRITE)
;	(POPJ-AFTER-NEXT GC-WRITE-TEST)
	(gc-write-test-return)
       (NO-OP)
	(popj)				;trans-drop-through's return (rev 15)

(ERROR-TABLE DEFAULT-ARG-LOCATIONS CONS-IN-AREA PP PP M-S)

XCONSA (MISC-INST-ENTRY CONS-IN-AREA)		;CONS, WITH AREA AS THIRD ARG
	(JUMP-XCT-NEXT QCONS)
       ((M-S) Q-TYPED-POINTER C-PDL-BUFFER-POINTER-POP)

;Assuming M-S set up with area,
;cons a single-word cell with cdr-nil,
;with contents taken from the stack.
XNCONQ	(CALL-XCT-NEXT LCONS)			;ALLOCATE 1 Q, RETURN POINTER IN M-T,
       ((M-B) (A-CONSTANT 1))			;ALLOCATE FROM LIST SPACE
	((WRITE-MEMORY-DATA) DPB Q-TYPED-POINTER 
		C-PDL-BUFFER-POINTER-POP 
		(A-CONSTANT (BYTE-VALUE Q-CDR-CODE CDR-NIL)))
	((VMA-START-WRITE M-T) DPB M-T Q-POINTER
		(A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-LIST)))
	(CHECK-PAGE-WRITE)
;	(POPJ-AFTER-NEXT GC-WRITE-TEST)
	(gc-write-test-return)
       (NO-OP)
	(popj)				;trans-drop-through's return (rev 15)

;;; STORAGE ALLOCATION STUFF

; CALL WITH AREA IN M-S, NUMBER OF QS DESIRED IN M-B
; NIL AND T AS AREAS WILL MEAN DEFAULT AND EXTRA-PDL, RESPECTIVELY
; OTHERWISE, M-S MUST BE A NUMBER OR A SYMBOL WHOSE VALUE IS A NUMBER.
; CALL LCONS TO ALLOCATE IN LIST SPACE, OR SCONS TO ALLOCATE IN STRUCTURE SPACE
; RETURNS RESULT IN M-T, WITH GARBAGE IN THE DATA-TYPE, YOU BETTER FIX THIS QUICK!
; THE ALLOCATED MEMORY WILL NOT BE INITIALIZED (IT WILL NORMALLY BE FILLED WITH DTP-FREE'S)
; YOU BETTER STORE HEADERS OR WHATEVER QUICK!
; SEE LIST-OF-NILS, WHICH IS LIKE LCONS BUT INITIALIZES THE STORAGE TO NIL, WITH CDR-CODES
;
; VARIOUS CALLERS REQUIRE THAT THE FOLLOWING REGISTERS BE PRESERVED:
;	M-A, M-B, M-C, M-D, M-I, M-J, M-Q, M-R, M-ZR, M-1, M-2
; THIS CAN POTENTIALLY CAUSE A STACK-GROUP SWITCH, ALSO MAY CLOBBER M-K, M-E
; WILL NOT STACK-GROUP SWITCH IF CALLED FROM THE TRANSPORTER, UNLESS TRAPPING
; FOR ILLEGAL ARGUMENT IN M-S OR M-B, WHICH WON'T HAPPEN, OR
; FOR OUT-OF-VIRTUAL-MEMORY WHICH SHOULDN'T HAPPEN AND MAY NOT WORK.

;DECODE AREA SPEC IN M-S.  RETURN FIXNUM, WITH DATA-TYPE, IN M-S.
;THIS CAN CALL TRAP OR JUMP TO IT, THUS CALLER MUST HAVE (ERROR-TABLE ARGTYP AREA M-S NIL)
;M-S MUST HAVE DATA-TYPE AND NO CDR-CODE/FLAG.
CONS-GET-AREA		(ERROR-TABLE RESTART CONS-GET-AREA)
	((M-TEM) Q-DATA-TYPE M-S)
	(CALL-EQUAL M-TEM (A-CONSTANT (EVAL DTP-SYMBOL)) CONS-GET-AREA-1)
	(POPJ-AFTER-NEXT DISPATCH Q-DATA-TYPE M-S TRAP-UNLESS-FIXNUM)
    (ERROR-TABLE ARGTYP AREA M-S NIL CONS-GET-AREA)
;       (CALL-GREATER-THAN M-S (A-CONSTANT (PLUS (BYTE-VALUE Q-DATA-TYPE DTP-FIX)
;						(EVAL SIZE-OF-AREA-ARRAYS)))
;		TRAP)
	;; quux revision 13 (decisions of 29 sep, g2 review 2): the comparison
	;; orders the fields alone, where the typed word once put a negative
	;; fixnum above the range; unsigned, a negative area number still traps.
       (call-greater-or-equal-unsigned m-s (a-constant (plus (byte-value q-data-type dtp-fix)
						(eval (1+ size-of-area-arrays))))
		trap)

CONS-GET-AREA-1
	((VMA-START-READ) ADD M-S (A-CONSTANT 1))	;Fetch value
	(CHECK-PAGE-READ)
	(DISPATCH TRANSPORT READ-MEMORY-DATA)
	(POPJ-XCT-NEXT)
       ((M-S) Q-TYPED-POINTER READ-MEMORY-DATA)

;This entry used by number functions to cons a structure in extra-pdl 
SCONS-T	((M-S) DPB M-ZERO Q-ALL-BUT-TYPED-POINTER A-NUM-CNSADF)
;This is the normal entry, area in M-S with no cdr code or flag bit
SCONS	(JUMP-NOT-EQUAL M-S A-V-NIL SCONS-N)
;This is the entry to cons in the default area
SCONS-D	((M-S) DPB M-ZERO Q-ALL-BUT-TYPED-POINTER A-CNSADF)
;At this point M-S is a fixnum, unless there is a bug or use of an obsolete feature 
SCONS-N	(CALL-LESS-OR-EQUAL M-B A-ZERO TRAP)
		(ERROR-TABLE CONS-ZERO-SIZE M-B)
	(JUMP-IF-BIT-SET M-TRANSPORT-FLAG SCONSR)	;Transporter must avoid cache
	(JUMP-NOT-EQUAL M-S A-SCONS-CACHE-AREA SCONSR)	;Jump if need full SCONS
	((M-3) ADD M-B A-SCONS-CACHE-FREE-POINTER)	;Proposed new free pointer
;	(JUMP-GREATER-THAN M-3 A-SCONS-CACHE-FREE-LIMIT SCONSR)	;Jump if won't fit
	(jump-greater-than-unsigned m-3 a-scons-cache-free-limit sconsr)	;Jump if won't fit	;quux revision 14: unsigned (contract g3 revision 14, 10.1)
	((M-T) A-SCONS-CACHE-FREE-POINTER)		;Allocate it here
	((A-SCONS-CACHE-FREE-POINTER) M-3)		;Advance free pointer
	((M-3) SUB M-3 A-SCONS-CACHE-REGION-ORIGIN)	;Exit via scavenger
	;; quux revision 13 (contract g2 2.2): an arithmetic result takes m's tag,
	;; and m-b, the count, has none: the free pointer scav0 stores is made a
	;; fixnum again, as the region's table holds it.
	((m-3) dpb m-3 q-pointer (a-constant (byte-value q-data-type dtp-fix)))
	(JUMP-XCT-NEXT SCAV0)				; which will store back free pntr
       ((M-K) A-SCONS-CACHE-REGION)

SCONSR		(ERROR-TABLE RESTART SCONSR)
	(CALL CONS-GET-AREA)				;Set up M-S
    (ERROR-TABLE ARGTYP AREA M-S NIL SCONSR)
	;; the generational collector (contract g3 step 2, 3.2): the generation this
	;; cons goes into, which the region it takes must hold (cons-check-new,
	;; cons-check-copy, rcons).
	(call cons-generation)
	((VMA-START-READ) ADD M-S A-V-AREA-REGION-LIST)	;Find appropriate region of the area
SCONS0	(CHECK-PAGE-READ)
	(JUMP-IF-BIT-SET BOXED-SIGN-BIT READ-MEMORY-DATA SCONS5)	;No region found
	((M-K) Q-POINTER READ-MEMORY-DATA)		;Get region number
SCONS2	((VMA-START-READ) ADD M-K A-V-REGION-BITS)	;Get attributes of that region
	(CHECK-PAGE-READ)
	((M-E) (A-CONSTANT (EVAL %REGION-REPRESENTATION-TYPE-STRUCTURE)))
	(DISPATCH (LISP-BYTE %%REGION-SPACE-TYPE) READ-MEMORY-DATA D-CONS-1)
	(DISPATCH (LISP-BYTE %%REGION-REPRESENTATION-TYPE) READ-MEMORY-DATA D-SCONS-2)
	;; Returns with M-K region, M-T allocated guy, M-3 new free pointer, M-E origin
	;; Cache this information then return via scavenger
	(JUMP-IF-BIT-SET M-TRANSPORT-FLAG SCAVT)	;Transporter must avoid cache
	;; the generational collector (contract g3 step 2, 3.2): a pretenured cons
	;; does not fill the cache, which would send the area's next small conses
	;; to its tenured region.
	((m-tem) a-cons-pretenured)
	(jump-not-equal m-tem a-zero scav0)
	((A-SCONS-CACHE-AREA) M-S)
	((A-SCONS-CACHE-REGION) M-K)
	((A-SCONS-CACHE-REGION-ORIGIN) M-E)
	((A-SCONS-CACHE-FREE-POINTER Q-R) ADD M-3 A-E)
	((M-TEM) SUB Q-R (A-CONSTANT 1))		;Location on last good page
;	((M-TEM) DPB (M-CONSTANT -1) (BYTE-FIELD 8 0) A-TEM)	;Last loc on that page
	((m-tem) dpb (m-constant -1) vma-page-offset a-tem)	;last loc on that 1024-word page
	(JUMP-XCT-NEXT SCAV0)
       ((A-SCONS-CACHE-FREE-LIMIT) ADD M-TEM (A-CONSTANT 1))	;Page to stop before

;A copy of the above code except for List representation-type, slightly different dispatch
;This is the normal entry, area in M-S with no cdr code or flag bit
LCONS	(JUMP-NOT-EQUAL M-S A-V-NIL LCONS-N)
;This is the entry to cons in the default area
LCONS-D	((M-S) DPB M-ZERO Q-ALL-BUT-TYPED-POINTER A-CNSADF)
;At this point M-S is a fixnum, unless there is a bug or use of an obsolete feature 
LCONS-N	(CALL-LESS-OR-EQUAL M-B A-ZERO TRAP)
		(ERROR-TABLE CONS-ZERO-SIZE M-B)
	(JUMP-IF-BIT-SET M-TRANSPORT-FLAG LCONSR)	;Transporter must avoid cache
	(JUMP-NOT-EQUAL M-S A-LCONS-CACHE-AREA LCONSR)	;Jump if need full LCONS
	((M-3) ADD M-B A-LCONS-CACHE-FREE-POINTER)	;Proposed new free pointer
;	(JUMP-GREATER-THAN M-3 A-LCONS-CACHE-FREE-LIMIT LCONSR)	;Jump if won't fit
	(jump-greater-than-unsigned m-3 a-lcons-cache-free-limit lconsr)	;Jump if won't fit	;quux revision 14: unsigned (contract g3 revision 14, 10.1)
	((M-T) A-LCONS-CACHE-FREE-POINTER)		;Allocate it here
	((A-LCONS-CACHE-FREE-POINTER) M-3)		;Advance free pointer
	((M-3) SUB M-3 A-LCONS-CACHE-REGION-ORIGIN)	;Exit via scavenger
	;; quux revision 13 (contract g2 2.2): an arithmetic result takes m's tag,
	;; and m-b, the count, has none: the free pointer scav0 stores is made a
	;; fixnum again, as the region's table holds it.
	((m-3) dpb m-3 q-pointer (a-constant (byte-value q-data-type dtp-fix)))
	(JUMP-XCT-NEXT SCAV0)				; which will store back free pntr
       ((M-K) A-LCONS-CACHE-REGION)

LCONSR		(ERROR-TABLE RESTART LCONSR)
	(CALL CONS-GET-AREA)			;Set up M-S
    (ERROR-TABLE ARGTYP AREA M-S NIL LCONSR)
	;; the generational collector (contract g3 step 2, 3.2): as sconsr
	(call cons-generation)
	((VMA-START-READ) ADD M-S A-V-AREA-REGION-LIST)	;Find appropriate region of the area
LCONS0	(CHECK-PAGE-READ)
	(JUMP-IF-BIT-SET BOXED-SIGN-BIT READ-MEMORY-DATA LCONS5)	;No region found
	((M-K) Q-POINTER READ-MEMORY-DATA)		;Get region number
LCONS2	((VMA-START-READ) ADD M-K A-V-REGION-BITS)	;Get attributes of that region
	(CHECK-PAGE-READ)
	((M-E) (A-CONSTANT (EVAL %REGION-REPRESENTATION-TYPE-LIST)))
	(DISPATCH (LISP-BYTE %%REGION-SPACE-TYPE) READ-MEMORY-DATA D-CONS-1)
	(DISPATCH (LISP-BYTE %%REGION-REPRESENTATION-TYPE) READ-MEMORY-DATA D-LCONS-2)
	;; Returns with M-K region, M-T allocated guy, M-3 new free pointer, M-E origin
	;; Cache this information then return via scavenger
	(JUMP-IF-BIT-SET M-TRANSPORT-FLAG SCAVT)	;Transporter must avoid cache
	;; the generational collector (contract g3 step 2, 3.2): as scons2, a
	;; pretenured cons does not fill the cache
	((m-tem) a-cons-pretenured)
	(jump-not-equal m-tem a-zero scav0)
	((A-LCONS-CACHE-AREA) M-S)
	((A-LCONS-CACHE-REGION) M-K)
	((A-LCONS-CACHE-REGION-ORIGIN) M-E)
	((A-LCONS-CACHE-FREE-POINTER Q-R) ADD M-3 A-E)
	((M-TEM) SUB Q-R (A-CONSTANT 1))		;Location on last good page
;	((M-TEM) DPB (M-CONSTANT -1) (BYTE-FIELD 8 0) A-TEM)	;Last loc on that page
	((m-tem) dpb (m-constant -1) vma-page-offset a-tem)	;last loc on that 1024-word page
	(JUMP-XCT-NEXT SCAV0)
       ((A-LCONS-CACHE-FREE-LIMIT) ADD M-TEM (A-CONSTANT 1))	;Page to stop before

SCONS1	(JUMP-XCT-NEXT SCONS0)			;TRY NEXT REGION
       ((VMA-START-READ) ADD M-K A-V-REGION-LIST-THREAD)

LCONS1	(JUMP-XCT-NEXT LCONS0)			;TRY NEXT REGION
       ((VMA-START-READ) ADD M-K A-V-REGION-LIST-THREAD)


	;This region is the right type, see if adequate free space, if so do it.
	;Called as subroutine from both SCONS and LCONS.
	;; the generational collector (contract g3 step 2, 6.2): md is the region's
	;; bits, kept for consf-table below.
consf	((a-cons-region-bits) md)
	((vma-start-read) add m-k a-v-region-length)
	(CHECK-PAGE-READ)
	((M-3) Q-POINTER READ-MEMORY-DATA)	;Length of region
	((VMA-START-READ) ADD M-K A-V-REGION-FREE-POINTER)
	(CHECK-PAGE-READ)
	((M-T) Q-POINTER READ-MEMORY-DATA)	;Current free pointer
	((M-4) ADD M-T A-B)			;Proposed new free pointer
	(JUMP-GREATER-THAN M-4 A-3 CONSF4)	;Jump if doesn't fit, try next region
	((M-3) SELECTIVE-DEPOSIT READ-MEMORY-DATA Q-ALL-BUT-POINTER A-4) ;New free pointer
	((VMA-START-READ) ADD M-K A-V-REGION-ORIGIN)	;Relocate M-T
	(CHECK-PAGE-READ)
	((A-CONS-TEM) M-FLAGS)
	((M-E) Q-POINTER READ-MEMORY-DATA)	;Save region origin
	((M-T VMA-START-READ) ADD M-E A-T)	;Address of allocated stuff, garbage datatype
	((M-4) Q-POINTER-WITHIN-PAGE M-T)	;Then touch each page of allocated stuff
	(JUMP-NOT-EQUAL-XCT-NEXT M-4 A-ZERO CONSF2) ;Jump if first page not a fresh page
       ((M-4) ADD M-4 A-B)			;M-4 gives page count in hairy way
CONSF1	((M-DONT-SWAP-IN) DPB (M-CONSTANT -1) A-FLAGS)	;Create pages without disk read
CONSF2	(CHECK-PAGE-READ)			;Now take fault for previous VMA-START-READ
	((M-4) SUB M-4 (A-CONSTANT (EVAL PAGE-SIZE)))
;	(POPJ-LESS-OR-EQUAL-XCT-NEXT M-4 A-ZERO)
	;; the generational collector (contract g3 step 2, 6.2): the first-object
	;; table's entries, then the return (consf-table)
	(jump-less-or-equal-xct-next m-4 a-zero consf-table)
       ((M-FLAGS) SETA A-CONS-TEM READ-MEMORY-DATA);Restore flags, complete memory cycle
	(JUMP-XCT-NEXT CONSF1)
       ((VMA-START-READ) ADD VMA (A-CONSTANT (EVAL PAGE-SIZE)))

;; the generational collector (contract g3 step 2, 6.1, 6.2): a tenured
;; structure region that is not fixed or extra-pdl begins with its first-object
;; table, an art-32b array at its origin (make-region writes it), entry k the
;; offset from the origin of an object start at or below the first word of the
;; region's page k.  every object that holds a page's first word comes here,
;; since the cons caches stop at a page boundary and the transporter does not
;; use them, so here each page whose first word lies in the new object gets
;; the object's start: m-t the object's address, m-b its words, m-e the
;; region's origin, m-k the region, a-cons-region-bits its bits.  the entries
;; are fixnums; the flags are restored, so a table page out of core is read in.
;; keeps m-3, m-t, m-e, m-k, m-b; clobbers m-4, vma, md, tems.
consf-table
	((md) a-cons-region-bits)
	(call first-object-table-p)
	(popj-equal m-tem a-zero)
	;; s, the object's start in the region; the first page whose first word
	;; it holds, (s + 1777) / 2000, and the last, (s + m-b - 1) / 2000
	((m-4) sub m-t a-e)
	((m-4) q-pointer m-4)
	((a-cons-table-start) dpb m-4 q-pointer (a-constant (byte-value q-data-type dtp-fix)))
	((m-tem) add m-4 a-b)
	((m-tem) sub m-tem (a-constant 1))
	((m-tem) vma-page-addr-part m-tem)	;the last page
	((m-4) add m-4 (a-constant (eval (1- page-size))))
	((m-4) vma-page-addr-part m-4)		;the first page
	(popj-greater-than m-4 a-tem)		;no page's first word in it
	((m-tem) sub m-tem a-4)
	((a-cons-table-count) add m-tem (a-constant 1))	;the entries to write
	;; the table's header, at the origin: its entries follow it, or the long
	;; length word after it
	((vma-start-read) m-e)
	(check-page-read)
	(call consf-table-check)
	(jump-if-bit-clear (lisp-byte %%array-long-length-flag) md consf-table-1)
	((m-4) add m-4 (a-constant 1))
consf-table-1
	((m-4) add m-4 (a-constant 1))		;the entry's offset from the origin
	((vma) add m-4 a-e)
consf-table-2
	((write-memory-data) a-cons-table-start)
	((vma-start-write) vma)
	(check-page-write)
	((m-tem) a-cons-table-count)
	((a-cons-table-count) sub m-tem (a-constant 1))
	(popj-less-or-equal m-tem (a-constant 1))
	(jump-xct-next consf-table-2)
       ((vma) add vma (a-constant 1))

;; consf-table-check: md, a region's first word, must be a first-object
;; table's header, an art-32b array of one dimension; else the band or the
;; tables are wrong, and the machine halts here rather than misparse the
;; region.  the walk (scav-walk-page) checks it the same way.  clobbers m-tem.
consf-table-check
	((m-tem) q-data-type md)
	(call-not-equal m-tem (a-constant (eval dtp-array-header)) first-object-table-missing)
	((m-tem) (lisp-byte %%array-type-field) md)
	(call-not-equal m-tem (a-constant (eval (ldb %%array-type-field art-32b)))
		first-object-table-missing)
	((m-tem) (lisp-byte %%array-number-dimensions) md)
	(call-not-equal m-tem (a-constant 1) first-object-table-missing)
	(popj)

;; consf-table-check and the walk come here when a region that should begin
;; with a first-object table does not.  the halt shows this location.
first-object-table-missing
	(call illop)

CONSF4	((M-GARBAGE) MICRO-STACK-DATA-POP)
CONSF5	(DISPATCH (BYTE-FIELD 2 0) M-E D-CONS-NEXT-REGION)

;Trying to cons in newspace
;CONS-CHECK-NEW
;	(POPJ-AFTER-NEXT POPJ-IF-BIT-CLEAR M-TRANSPORT-FLAG)
;       (DISPATCH (BYTE-FIELD 2 0) M-E D-CONS-NEXT-REGION)
;; the generational collector (contract g3 step 2, 3.2): the mutator conses
;; only into regions of the cons's generation, a-cons-generation (eden in an
;; ephemeral area, tenured in any other or past the pretenuring threshold);
;; the transporter never into newspace.  md is the region's bits.  a region
;; refused: the next one (consf4 drops the return address).
CONS-CHECK-NEW
	(jump-if-bit-set m-transport-flag consf4)
cons-check-generation
	((m-tem) region-generation md)
	(popj-equal m-tem a-cons-generation)
	(jump consf4)

;Trying to cons in copyspace
;CONS-CHECK-COPY
;	(POPJ-AFTER-NEXT POPJ-IF-BIT-SET M-TRANSPORT-FLAG)
;       (DISPATCH (BYTE-FIELD 2 0) M-E D-CONS-NEXT-REGION)
;; the generational collector (contract g3 step 2, 3.2): the transporter
;; conses only into copy regions of its destination's generation
;; (a-cons-generation, from a-trans-generation); the mutator never.
CONS-CHECK-COPY
	(jump-if-bit-clear m-transport-flag consf4)
	(jump cons-check-generation)

;; the generational collector (contract g3 step 2, 3.2, 5): cons-generation
;; sets a-cons-generation, the generation the cons being made goes into, and
;; a-cons-pretenured.  m-s the area (a fixnum, cons-get-area's), m-b the
;; words.  the transporter's copy goes to its destination, a-trans-generation;
;; extra-pdl-trap's (a-trans-generation 4) and the mutator's to the area's
;; allocation generation: eden if the area is ephemeral (%%region-ephemeral in
;; its area bits), unless the cons has more words than the pretenuring
;; threshold, which makes it tenured; tenured in any other area.  clobbers
;; m-tem, vma, md.
cons-generation
	((a-cons-pretenured) a-zero)
	(jump-if-bit-clear m-transport-flag cons-generation-area)
	((m-tem) a-trans-generation)
	(jump-equal m-tem (a-constant 4) cons-generation-area)
	(popj-after-next (a-cons-generation) m-tem)
       (no-op)
cons-generation-area
	((vma-start-read) add m-s a-v-area-region-bits)
	(check-page-read)
	(jump-if-bit-clear (lisp-byte %%region-ephemeral) md cons-generation-tenured)
	((m-tem) a-gc-pretenure-threshold)
	((m-tem) q-pointer m-tem)
	(jump-greater-than-unsigned m-b a-tem cons-generation-pretenured)
	(popj-after-next (a-cons-generation) (a-constant region-generation-eden))
       (no-op)
cons-generation-pretenured
	((a-cons-pretenured) (a-constant 1))
cons-generation-tenured
	(popj-after-next (a-cons-generation) (a-constant region-generation-tenured))
       (no-op)

(LOCALITY D-MEM)
(START-DISPATCH 4 0)
D-CONS-1	;DISPATCH ON SPACE TYPE
	(P-BIT INHIBIT-XCT-NEXT-BIT ILLOP)	;0 FREE (erroneous)
	(INHIBIT-XCT-NEXT-BIT CONSF5)		;1 OLD (try next region)
	(P-BIT INHIBIT-XCT-NEXT-BIT CONS-CHECK-NEW) ;2 NEW (only if not in transporter)
	(P-BIT INHIBIT-XCT-NEXT-BIT CONS-CHECK-NEW) ;3 NEW1 (only if not in transporter)
	(P-BIT INHIBIT-XCT-NEXT-BIT CONS-CHECK-NEW) ;4 NEW2 (only if not in transporter)
	(P-BIT INHIBIT-XCT-NEXT-BIT CONS-CHECK-NEW) ;5 NEW3 (only if not in transporter)
	(P-BIT INHIBIT-XCT-NEXT-BIT CONS-CHECK-NEW) ;6 NEW4 (only if not in transporter)
	(P-BIT INHIBIT-XCT-NEXT-BIT CONS-CHECK-NEW) ;7 NEW5 (only if not in transporter)
	(P-BIT INHIBIT-XCT-NEXT-BIT CONS-CHECK-NEW) ;10 NEW6 (only if not in transporter)
;	(P-BIT R-BIT)				;11 STATIC
	;; the generational collector (contract g3 step 2, 3.2): a static region is
	;; tenured, so a cons of another generation (eden's) does not take it
	(p-bit inhibit-xct-next-bit cons-check-generation)	;11 static
	(INHIBIT-XCT-NEXT-BIT CONSF5)		;12 FIXED (try next region; will get error)
	(P-BIT R-BIT)				;13 EXTRA-PDL
	(P-BIT INHIBIT-XCT-NEXT-BIT CONS-CHECK-COPY) ;14 COPY (only if in transporter)
(REPEAT 3 (P-BIT INHIBIT-XCT-NEXT-BIT ILLOP))	;Unused code (erroneous)
(END-DISPATCH)

(START-DISPATCH 2 INHIBIT-XCT-NEXT-BIT)
D-SCONS-2	;DISPATCH ON REPRESENTATION TYPE
	(SCONS1)		;0 LIST (TRY NEXT REGION)
	(P-BIT CONSF)		;1 STRUCTURE
	(P-BIT ILLOP)		;2 ILLEGAL
	(P-BIT ILLOP)		;3 ILLEGAL
(END-DISPATCH)

(START-DISPATCH 2 INHIBIT-XCT-NEXT-BIT)
D-LCONS-2	;DISPATCH ON REPRESENTATION TYPE
	(P-BIT CONSF)		;0 LIST
	(LCONS1)		;1 STRUCTURE (TRY NEXT REGION)
	(P-BIT ILLOP)		;2 ILLEGAL
	(P-BIT ILLOP)		;3 ILLEGAL
(END-DISPATCH)

(START-DISPATCH 2 INHIBIT-XCT-NEXT-BIT)
D-CONS-NEXT-REGION	;DISPATCH ON REPRESENTATION TYPE
	(LCONS1)		;0 LIST
	(SCONS1)		;1 STRUCTURE
	(P-BIT ILLOP)		;2 ILLEGAL
	(P-BIT ILLOP)		;3 ILLEGAL
(END-DISPATCH)

(LOCALITY I-MEM)

;;; Scavenger

;Here after consing something, to do scavenging and so forth.  M-E, M-K smashable.
;M-B has the number of Q'S consed, M-K has the region number.
;M-3 has the new free pointer, the free-pointer has not been updated yet, to 
;avoid attempting to scavenge the newly-allocated object, which is not yet initialized.
SCAV0	;(JUMP-IF-BIT-SET M-TRANSPORT-FLAG SCAVT) ;If in transporter, don't invoke scavenger
	((M-E) DPB M-B (BYTE-FIELD Q-POINTER-WIDTH 2) A-ZERO) ;4 times number of Q's consed (K=4)
	;; the generational collector (contract g3 step 2, 4.1): the words the
	;; mutator conses, a fixnum, which every flip clears (lisp's
	;; %gc-words-consed-since-flip); the transporter's copies go to scavt.
	((m-tem) add m-b a-gc-words-consed-since-flip)
	((a-gc-words-consed-since-flip) dpb m-tem q-pointer (a-constant (byte-value q-data-type dtp-fix)))
	((A-CONS-WORK-DONE Q-R) ADD M-E A-CONS-WORK-DONE)
	(JUMP-LESS-THAN-XCT-NEXT Q-R A-SCAV-WORK-DONE SCAV0X)	;Return if not yet
       ((A-CONS-NEW-FREE-POINTER) M-3)				; time to scavenge
	;; the generational collector (contract g3 step 2, 4.5, amendment 8):
	;; one cons scavenges at most a page's units, 1,024, while the backlog,
	;; a-cons-work-done less a-scav-work-done with this cons's 4n counted, is
	;; at most the backlog limit, 4000000 (1,048,576)
	;; units, k times a working-storage region; above it the cons scavenges
	;; its whole 4n, as mit's did.  the 4n stays counted above; later conses,
	;; each scavenging its own share while the scavenger is behind, and idle
	;; time do the rest.  one cons scavenged up to all of a collection's
	;; remaining work at once: the error handler's assure-free-space, 4,098
	;; words, 188.9 ms at 2 mw (t1).  the limit keeps mit's free-space rule
	;; to within the limit over k, 262,144 words, which
	;; gc-get-committed-free-space (gc.lisp) commits besides.
	((m-tem) sub q-r a-scav-work-done)	;the backlog, this cons's 4n in it
	(jump-greater-than m-tem (a-constant 4000000) scav0-bounded)	;over the limit: all 4n
	(jump-less-or-equal m-e (a-constant (eval page-size)) scav0-bounded)
	((m-e) (a-constant (eval page-size)))
scav0-bounded
	((M-TEM) DPB M-ZERO Q-ALL-BUT-TYPED-POINTER A-INHIBIT-SCAVENGING-FLAG)
	(CALL-EQUAL-XCT-NEXT M-TEM A-V-NIL SCAV2)	;Check if scavenger inhibited by user
SCAV0X ((A-CONS-NEW-FP-REGION) ADD M-K A-V-REGION-FREE-POINTER)
	((WRITE-MEMORY-DATA) A-CONS-NEW-FREE-POINTER)		;Now update free pointer
	(POPJ-AFTER-NEXT (VMA-START-WRITE) A-CONS-NEW-FP-REGION)
       (CHECK-PAGE-WRITE)

;Scavenge M-E Q's worth of stuff.  Clobber only M-E,M-K,M-3,M-4, tems
SCAV2	((MD) (A-CONSTANT -2))			;Turn on scavenger run-light
	((VMA-START-WRITE) ADD MD A-DISK-RUN-LIGHT)
	(CHECK-PAGE-WRITE)
	(JUMP-EQUAL-XCT-NEXT A-SCAV-COUNT M-ZERO SCAV3)	;Jump if no remembered scavenger state
       ((M-SCAVENGE-FLAG) DPB (M-CONSTANT -1) A-FLAGS)
;;;Continue previous scavenge.  Kludgiferous hair required for pdls since they
;;;change in size in real time, and we really have to obey the pad since various
;;;microcode routines like to push garbage off the end of the pdl.
SCAVL0	(JUMP-EQUAL M-ZERO A-SCAV-PDL-BASE SCAVL1)
	(CALL-XCT-NEXT SCAV-STRUCTURE-INFO)	;Recompute size of pdl
       ((MD) A-SCAV-PDL-BASE)
	((M-TEM) DPB M-ZERO Q-ALL-BUT-POINTER A-SCAV-PTR)
	((M-TEM) SUB M-TEM A-SCAV-PDL-BASE)	;Number of Q's already done
	((M-TEM) SUB M-ZERO A-TEM)
	((A-SCAV-COUNT) ADD M-TEM A-SCAV-COUNT)	;Subtract that from total #Q's
	(JUMP-LESS-THAN M-ZERO A-SCAV-COUNT SCAVL1)
	((M-TEM) A-SCAV-COUNT)		 ;Shrunk beyond where we were
	(JUMP-XCT-NEXT SCAVL4)		 ;Move back A-SCAV-PTR so next structure will
       ((A-SCAV-PTR) ADD M-TEM A-SCAV-PTR)  ;be found. This can result in bit of double
					    ;counting on A-SCAV-WORK-DONE, but thats too
					    ;bad.
SCAVL1	(JUMP-GREATER-OR-EQUAL-XCT-NEXT M-E A-SCAV-COUNT SCAVL2)
       ((M-K) A-SCAV-COUNT)			;Get number of Q's to do this time
	((M-K) M-E)
SCAVL2	((A-SCAV-WORK-DONE) ADD M-K A-SCAV-WORK-DONE)
	((M-E) SUB M-E A-K)
SCAVL3	((VMA-START-READ) A-SCAV-PTR)		;Scavenge some Q's
	(CHECK-PAGE-READ)
	((A-SCAV-PTR) M+A+1 M-ZERO A-SCAV-PTR)
	((A-SCAV-COUNT) ADD (M-CONSTANT -1) A-SCAV-COUNT)
	(DISPATCH TRANSPORT-SCAV READ-MEMORY-DATA)
	(JUMP-GREATER-THAN-XCT-NEXT M-K (A-CONSTANT 1) SCAVL3)
       ((M-K) SUB M-K (A-CONSTANT 1))
	(JUMP-NOT-EQUAL A-SCAV-COUNT M-ZERO SCAVX) ;M-E too small to finish this object
	;;Finished this object, update region's GC-POINTER
SCAVL4	((M-TEM) A-SCAV-SKIP)
	((A-SCAV-WORK-DONE) ADD M-TEM A-SCAV-WORK-DONE) ;Unboxed Q's come for free
	((M-3) ADD M-TEM A-SCAV-PTR)
	((M-3) SUB M-3 A-SCAV-REGION-ORIGIN) ;relative
	((WRITE-MEMORY-DATA) Q-POINTER M-3 (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	((M-K) A-SCAV-REGION)
	((VMA-START-WRITE) ADD M-K A-V-REGION-GC-POINTER)
	(CHECK-PAGE-WRITE)
	;;Try to find next object to scavenge in this region
	((VMA-START-READ) ADD M-K A-V-REGION-FREE-POINTER)
	(CHECK-PAGE-READ)
	((M-4) Q-POINTER READ-MEMORY-DATA)	;Save free pointer
	(JUMP-EQUAL M-3 A-4 SCAV3)		;This region now clean, try some others
;Here M-K has region, M-3 has gc pointer, M-4 has free pointer, as pure numbers
SCAV6	((VMA-START-READ) ADD M-K A-V-REGION-BITS)
	(CHECK-PAGE-READ)
	((A-SCAV-PTR) ADD M-3 A-SCAV-REGION-ORIGIN)
	(DISPATCH (LISP-BYTE %%REGION-REPRESENTATION-TYPE) READ-MEMORY-DATA D-SCAV6)
	(CALL-XCT-NEXT SCAV-STRUCTURE-INFO)	;Structure region
       ((MD) A-SCAV-PTR)			;Set A-SCAV-COUNT, A-SCAV-SKIP
	((A-SCAV-PDL-BASE) A-SINF-PDL-BASE)	;0 or base address of this pdl
SCAV8	(JUMP-EQUAL A-SCAV-COUNT M-ZERO SCAVL4)	;Object or region can have no boxed Q's!
	(JUMP-NOT-EQUAL-XCT-NEXT M-E A-ZERO SCAVL0)	;Go scavenge this object
       ((A-SCAV-PTR) DPB M-ZERO Q-ALL-BUT-POINTER A-SCAV-PTR) ;This must have a zero tag
	(JUMP SCAVX)				;Done for now

SCAV7	((A-SCAV-SKIP) A-ZERO)			;List region, don't worry about
	((A-SCAV-PDL-BASE) A-ZERO)		; object boundaries
	(JUMP-GREATER-THAN-XCT-NEXT M-4 A-3 SCAV9)
       ((Q-R A-SCAV-COUNT) SUB M-4 A-3)
	((A-SCAV-PTR) ADD M-4 A-SCAV-REGION-ORIGIN)
	((Q-R A-SCAV-COUNT) SUB M-3 A-4)	;Downward-consing
SCAV9	(JUMP-LESS-OR-EQUAL Q-R (A-CONSTANT 400) SCAV8)
	(JUMP-XCT-NEXT SCAV8)
       ((A-SCAV-COUNT) (A-CONSTANT 400))	;Do at most this many before updating GC-pntr

(LOCALITY D-MEM)
(START-DISPATCH 2 0) ;Dispatch on representation-type
D-SCAV6	(INHIBIT-XCT-NEXT-BIT SCAV7)		;0 list
	(P-BIT R-BIT)				;1 structure
	(INHIBIT-XCT-NEXT-BIT P-BIT ILLOP)	;2 unused
	(INHIBIT-XCT-NEXT-BIT P-BIT ILLOP)	;3 unused
(END-DISPATCH)
(LOCALITY I-MEM)

;SCAV3	((M-K) A-ZERO)				;Check every region
	;; the generational collector (contract g3 step 2, 4.4): while the
	;; marked-page walk is armed and no copy region has been consed into since
	;; the region loop last found every region clean, the walk goes on without
	;; another pass of the region loop.
scav3	((m-tem) a-scav-walk-armed)
	(jump-equal m-tem a-zero scav3-regions)
	((m-tem) a-scav-region-dirty)
	(jump-equal m-tem a-zero scav-walk)
scav3-regions
	((m-k) a-zero)				;check every region
SCAV4	((VMA-START-READ) ADD M-K A-V-REGION-BITS)
	(CHECK-PAGE-READ)
	(JUMP-IF-BIT-CLEAR (LISP-BYTE %%REGION-SCAVENGE-ENABLE) READ-MEMORY-DATA SCAV5)
	((VMA-START-READ) ADD M-K A-V-REGION-GC-POINTER)
	(CHECK-PAGE-READ)
	((M-3) Q-POINTER READ-MEMORY-DATA)
	((VMA-START-READ) ADD M-K A-V-REGION-FREE-POINTER)
	(CHECK-PAGE-READ)
	((M-4) Q-POINTER READ-MEMORY-DATA)	;Save free pointer
	(JUMP-EQUAL M-4 A-3 SCAV5)		;This region is clean
	((VMA-START-READ) ADD M-K A-V-REGION-ORIGIN)
	(CHECK-PAGE-READ)
	((A-SCAV-REGION) M-K)			;Do this one
	(JUMP-XCT-NEXT SCAV6)
       ((A-SCAV-REGION-ORIGIN) Q-POINTER READ-MEMORY-DATA)

SCAV5	(JUMP-LESS-THAN-XCT-NEXT M-K (A-CONSTANT (EVAL SIZE-OF-AREA-ARRAYS)) SCAV4)
       ((M-K) ADD M-K (A-CONSTANT 1))
	;; the generational collector (contract g3 step 2, 4.4): every region is
	;; clean.  copyspace first, then the walk, until both are clean: while the
	;; walk is armed it goes on; the flip is ready only when it is done.
	((a-scav-region-dirty) a-zero)
	((m-tem) a-scav-walk-armed)
	(jump-not-equal m-tem a-zero scav-walk)
	;;No scavenging needed anywhere, shut off the scavenger and enable flipping
	((A-GC-FLIP-READY) A-V-TRUE)
	((A-SCAV-WORK-DONE) (BYTE-FIELD 31. 0) (M-CONSTANT -1))  ;Maximum possible
SCAVX	((M-SCAVENGE-FLAG) DPB (M-CONSTANT 0) A-FLAGS)
	((MD) SETZ)
	((M-TEM) (A-CONSTANT -2))		;Turn off run light
	(POPJ-AFTER-NEXT (VMA-START-WRITE) ADD M-TEM A-DISK-RUN-LIGHT)
       (CHECK-PAGE-WRITE)			;This also makes sure VMA not pointing at gbg

;;; the generational collector (contract g3 step 2, 4.4, 4.5): the marked-page
;;; walk.  a young collection's roots beyond the machine's state are the
;;; tenured pages whose entry's <19> the setter marked (appendix a14.8): the
;;; walk visits every page, from its origin to its free pointer's page, of
;;; every region of the tenured generation whose space is new, copy, static or
;;; fixed (a fixed one only if scavenged: the cold load leaves raw ones out),
;;; reading its entry through the physical memory window, so it fills no tlb
;;; entry; a marked page is scanned and perhaps cleared as one step
;;; (scav-walk-page).  it is part of the scavenger, per cons and in idle
;;; time: an entry is a unit of work, a scanned word another.  after a marked
;;; page the region loop runs first if the transporter consed meanwhile
;;; (copyspace first); when every page is walked, the walk is disarmed and the
;;; region loop runs once more before the flip is ready (scav5).  xflip arms it
;;; at a young flip, and beg0000 when a boot finds oldspace.  m-e is the work
;;; to do; clobbers m-e, m-k, m-3, m-4, tems, as the scavenger may.
scav-walk
	((a-scav-walk-budget) m-e)
scav-walk-1
	(jump-less-or-equal m-e a-zero scav-walk-out)	;this call's work is done
	((m-k) a-scav-walk-region)
	(jump-greater-or-equal m-k (a-constant (eval size-of-area-arrays)) scav-walk-done)
	((vma-start-read) add m-k a-v-region-bits)
	(check-page-read)
	((m-tem) region-generation md)
	(jump-not-equal m-tem (a-constant region-generation-tenured) scav-walk-next-region)
	((m-tem) (lisp-byte %%region-space-type) md)
	(jump-equal m-tem (a-constant (eval %region-space-new)) scav-walk-2)
	(jump-equal m-tem (a-constant (eval %region-space-copy)) scav-walk-2)
	(jump-equal m-tem (a-constant (eval %region-space-static)) scav-walk-2)
	(jump-not-equal m-tem (a-constant (eval %region-space-fixed)) scav-walk-next-region)
	(jump-if-bit-clear (lisp-byte %%region-scavenge-enable) md scav-walk-next-region)
scav-walk-2
	((a-scav-walk-bits) md)
	((vma-start-read) add m-k a-v-region-free-pointer)
	(check-page-read)
	((m-tem) q-pointer md)
	((a-scav-walk-limit) m-tem)		;the free pointer, relative
	((m-tem) add m-tem (a-constant (eval (1- page-size))))
	((m-tem) vma-page-addr-part m-tem)	;the pages to the free pointer's
	((m-3) a-scav-walk-page)
	(jump-greater-or-equal m-3 a-tem scav-walk-next-region)
	((vma-start-read) add m-k a-v-region-origin)
	(check-page-read)
	((m-4) q-pointer md)
	((a-scav-walk-origin) m-4)
	((m-tem) dpb m-3 vma-page-addr-part a-zero)
	((m-4) add m-4 a-tem)			;the page's address
	((a-scav-walk-va) m-4)
	(call-xct-next find-page-entry)		;its entry, through the window
       ((a-tem1) m-4)
	((m-e) sub m-e (a-constant 1))		;an entry is a unit of work
	((m-tem) map-status-code md)
	(jump-equal m-tem a-zero scav-walk-next-page)	;no entry
	(jump-if-bit-clear map-ephemeral-reference-bit md scav-walk-next-page)	;not marked
	(call scav-walk-page)			;marked: scanned, perhaps cleared
	((m-tem) a-scav-walk-page)
	((a-scav-walk-page) add m-tem (a-constant 1))
	(call scav-walk-account)
	(jump-less-or-equal m-e a-zero scavx)
	(jump scav3)				;copyspace first, if the scan transported
scav-walk-next-page
	((m-tem) a-scav-walk-page)
	(jump-xct-next scav-walk-1)
       ((a-scav-walk-page) add m-tem (a-constant 1))
scav-walk-next-region
	((a-scav-walk-page) a-zero)
	((m-tem) a-scav-walk-region)
	(jump-xct-next scav-walk-1)
       ((a-scav-walk-region) add m-tem (a-constant 1))
scav-walk-out
	(call scav-walk-account)
	(jump scavx)
scav-walk-done					;every page walked: disarmed, and the
	((a-scav-walk-armed) a-zero)		; region loop once more (scav5)
	((a-scav-region-dirty) (a-constant 1))
	(call scav-walk-account)
	(jump scav3)

;; scav-walk-account: the walk's work since a-scav-walk-budget was set goes to
;; a-scav-work-done, as the region loop's does (scavl2).
scav-walk-account
	((m-tem) a-scav-walk-budget)
	((m-tem) sub m-tem a-e)
	(popj-after-next (a-scav-work-done) add m-tem a-scav-work-done)
       ((a-scav-walk-budget) m-e)

;; scav-walk-page: the marked page at a-scav-walk-va of the region whose origin,
;; bits and free pointer (relative) are a-scav-walk-origin, -bits and -limit,
;; its page a-scav-walk-page.  its boxed words below the free pointer are read
;; and transported through transport-scav, as the region loop scans them: a
;; list page word by word; a structure page object by object from the first
;; object at or before its first word (the region's first-object table's entry
;; for the page, or a fixed region's origin, which has no table), only the
;; words in this page; a pdl only to its active top.  if no word left there is
;; a young pointer, <19> is cleared in the page's entry and its tlb entry
;; invalidated, with no reference to the page in between: one step, which runs
;; no lisp (the transporter cannot sequence-break, and check-page-read and
;; -write take page faults and interrupts in microcode), so a young pointer
;; stored after the clear finds <19> 0 in the reloaded entry and marks the page
;; again.  the interrupt handlers store no pointer into ephemeral space.
;; m-e is reduced by the words read.  clobbers m-k, m-3, m-4, tems, vma, md.
scav-walk-page
	((a-scav-walk-young) a-zero)
	((m-4) a-scav-walk-limit)		;the scan's end: the free pointer,
	((m-4) add m-4 a-scav-walk-origin)	; or the page's end if lower
	((m-3) a-scav-walk-va)
	((m-3) add m-3 (a-constant (eval page-size)))
	(jump-less-or-equal-unsigned m-4 a-3 scav-walk-page-1)
	((m-4) m-3)
scav-walk-page-1
	((a-scav-walk-limit) m-4)		;now the scan's end, an address
	((m-tem) a-scav-walk-bits)
	((m-tem) (lisp-byte %%region-representation-type) m-tem)
	(jump-not-equal m-tem (a-constant (eval %region-representation-type-list))
		scav-walk-page-structure)
	((a-scav-walk-ptr) a-scav-walk-va)	;a list page: every word
	(call-xct-next scav-walk-words)
       ((a-scav-walk-to) m-4)
	(jump scav-walk-page-clear)
scav-walk-page-structure
	((m-4) a-scav-walk-origin)
	((m-tem) a-scav-walk-bits)
	((m-tem) (lisp-byte %%region-space-type) m-tem)
	(jump-equal m-tem (a-constant (eval %region-space-fixed)) scav-walk-page-2)
	((vma-start-read) m-4)			;the table's header, at the origin
	(check-page-read)
	(call consf-table-check)
	((m-tem) a-scav-walk-page)		;entry k: after the header, and the
	((m-tem) add m-tem (a-constant 1))	; long length word if there is one
	(jump-if-bit-clear (lisp-byte %%array-long-length-flag) md scav-walk-page-3)
	((m-tem) add m-tem (a-constant 1))
scav-walk-page-3
	((vma-start-read) add m-4 a-tem)
	(check-page-read)
	((m-tem) q-pointer md)
	((m-4) add m-4 a-tem)			;an object start at or before the page
	(call-greater-than-unsigned m-4 a-scav-walk-va first-object-table-missing)
scav-walk-page-2
	((a-scav-walk-obj) m-4)
scav-walk-page-4				;each object, while it starts before the end
	((m-4) a-scav-walk-obj)
	(jump-greater-or-equal-unsigned m-4 a-scav-walk-limit scav-walk-page-clear)
	(call-xct-next scav-walk-sinf)		;m-3 its boxed words, m-4 all its words
       ((md) m-4)
	((m-tem) a-scav-walk-obj)
	((m-3) add m-3 a-tem)			;its boxed words' end
	((m-4) add m-4 a-tem)			;the next object
	(call-equal m-4 a-tem illop)		;an object of no words: a broken region
	((a-scav-walk-obj) m-4)
	((m-4) a-scav-walk-va)			;the boxed words in the page: from the
	(jump-greater-or-equal-unsigned m-4 a-tem scav-walk-page-5)	; later of the
	((m-4) m-tem)				; page's start and the object's
scav-walk-page-5
	((a-scav-walk-ptr) m-4)
	((m-4) a-scav-walk-limit)		;to the earlier of the scan's end and
	(jump-less-or-equal-unsigned m-4 a-3 scav-walk-page-6)	; the boxed words'
	((m-4) m-3)
scav-walk-page-6
	(call-xct-next scav-walk-words)
       ((a-scav-walk-to) m-4)
	(jump scav-walk-page-4)
scav-walk-page-clear				;no young pointer left: <19> 0
	((m-tem) a-scav-walk-young)
	(popj-not-equal m-tem a-zero)
	(call-xct-next find-page-entry)
       ((a-tem1) a-scav-walk-va)
	((md) andca md (a-constant (byte-mask map-ephemeral-reference-bit)))
	((vma-start-write) vma)
	(illop-if-page-fault)
	((md) a-scav-walk-va)			;and the tlb's copy
	((vma-write-map) (a-constant write-map-invalidate))
	(popj-after-next (vma) a-v-nil)
       (no-op)

;; scav-walk-words: the words from a-scav-walk-ptr to below a-scav-walk-to,
;; each read and dispatched through transport-scav, as scavl3 does, which
;; transports a pointer to oldspace and writes the new one back; then the word
;; left in the page (md, or read again if the transporter followed a
;; forwarding pointer, vma moved) is tested, and a young pointer sets
;; a-scav-walk-young.  m-e is reduced by the words.  clobbers tems, vma, md.
;; a body-forward is not dispatched: it is a word of a structure-forwarded
;; husk (adjust-array-size growing a tenured array by copying it), and
;; trans-bfwd would follow it through the husk's header-forward to the word
;; in the new copy without transporting the header-forward first.  in a young
;; collection the new copy is young, in oldspace, and an array's leader words
;; come before its header: so the walk met a leader word's body-forward before
;; the header-forward, the new copy, transported by the flip, held
;; gc-forwards, and the machine halted here in illop (a compile of the system
;; on step 2's first band).  the husk's header-forward is dispatched as any
;; word, which copies or snaps the new copy; a body-forward points into its
;; own tenured husk, so it is never a young pointer.
scav-walk-words
	((m-tem) a-scav-walk-ptr)
	(popj-greater-or-equal-unsigned m-tem a-scav-walk-to)
	((vma-start-read) a-scav-walk-ptr)
	(check-page-read)
	((m-e) sub m-e (a-constant 1))
	((m-tem) q-data-type read-memory-data)
	(jump-equal m-tem (a-constant (eval dtp-body-forward)) scav-walk-words-2)
	(dispatch transport-scav read-memory-data)
	((m-tem) q-pointer vma)
	(jump-equal m-tem a-scav-walk-ptr scav-walk-words-1)
	((vma-start-read) a-scav-walk-ptr)
	(check-page-read)
scav-walk-words-1
	((m-tem) address-space-nibble md)
	(call-equal m-tem (a-constant ephemeral-space-nibble) scav-walk-young-type)
scav-walk-words-2
	((m-tem) a-scav-walk-ptr)
	(jump-xct-next scav-walk-words)
       ((a-scav-walk-ptr) add m-tem (a-constant 1))

;; scav-walk-young-type: md's address is in ephemeral space; if its type is
;; one the pointer-type register holds (the assembler's constants for
;; register-page words 222 and 223, appendix a14.5, a14.9), md is a young
;; pointer and a-scav-walk-young is set.  clobbers m-tem.
scav-walk-young-type
	((m-tem) q-data-type md)
	(jump-greater-or-equal m-tem (a-constant 40) scav-walk-young-type-1)
	((a-scav-walk-type) m-tem)
	(jump-xct-next scav-walk-young-type-2)
       ((m-tem) (a-constant pointer-type-register-0-31))
scav-walk-young-type-1
	((m-tem) sub m-tem (a-constant 40))
	((a-scav-walk-type) m-tem)
	((m-tem) (a-constant pointer-type-register-32-63))
scav-walk-young-type-2
	;; an ldb of the type's bit: its rotate is 50 less the position, ored into
	;; the next instruction (see slot-bit, uc-page-fault)
	((oa-reg-low) sub (m-constant 50) a-scav-walk-type)
	((m-tem) (byte-field 1 0) m-tem oa-low-select)	;reads oa-reg-low (rev 15)
	(popj-equal m-tem a-zero)
	(popj-after-next (a-scav-walk-young) (a-constant 1))
       (no-op)

;; scav-walk-sinf: structure-info of the object at md, as scav-structure-info
;; calls it, so that a pdl's words past its active top are skipped (a-sinf-pad):
;; m-3 its boxed words to scan, m-4 all its words.  keeps m-a, m-b, m-t;
;; clobbers m-k and the a-scav-save- locations, and leaves a-scav-pdl-base 0,
;; as the region loop has no object while the walk runs.
scav-walk-sinf
	((a-scav-save-a) m-a)
	((a-scav-save-b) m-b)
	((a-scav-save-t) m-t)
	((a-scav-pdl-base) q-pointer md)
	(call-xct-next structure-info)
       ((a-sinf-pdl-base) (a-constant 0))
	((m-4) add m-3 a-4)
	((m-3) sub m-3 a-sinf-pad)
	((a-scav-pdl-base) a-zero)
	((m-t) a-scav-save-t)
	(popj-after-next (m-b) a-scav-save-b)
       ((m-a) a-scav-save-a)

;; scav-walk-arm: the walk from its start (xflip at a young flip; beg0000).
scav-walk-arm
	((a-scav-walk-region) a-zero)
	((a-scav-walk-page) a-zero)
	((a-scav-region-dirty) (a-constant 1))
	(popj-after-next (a-scav-walk-armed) (a-constant 1))
       (no-op)

;; scav-walk-arm-if-oldspace (contract g3 step 2 revision 1, 8.3.5): beg0000
;; forgets the scavenger's state, and a warm boot loads a memory afresh,
;; which holds the walk's place; so with any region oldspace, a collection is
;; running, and the walk starts again, so that every page still marked is
;; scanned before the reclaim.  clobbers m-k, m-tem, vma, md.
scav-walk-arm-if-oldspace
	((a-scav-walk-armed) a-zero)
	((a-scav-region-dirty) (a-constant 1))
	((m-k) (a-constant (eval size-of-area-arrays)))
scav-walk-arm-if-oldspace-1
	((vma-start-read) add m-k a-v-region-bits)
	(illop-if-page-fault)
	((m-tem) (lisp-byte %%region-space-type) md)
	(jump-equal m-tem (a-constant (eval %region-space-old)) scav-walk-arm)
	(jump-greater-than-xct-next m-k a-zero scav-walk-arm-if-oldspace-1)
       ((m-k) sub m-k (a-constant 1))
	(popj)

;CONSing inside transporter.  If also inside scavenger, count as scavenger
;work done.  In either case, don't count as cons work done since this is not
;fresh consing but just copying, and don't invoke the scavenger.
SCAVT	((WRITE-MEMORY-DATA) M-3)	;Write back the free pointer
	((VMA-START-WRITE) ADD M-K A-V-REGION-FREE-POINTER)
	(CHECK-PAGE-WRITE)
	;; the generational collector (contract g3 step 2, 4.4): a copy is made,
	;; so the region loop runs again before the marked-page walk goes on
	((a-scav-region-dirty) (a-constant 1))
	(JUMP-NOT-EQUAL M-K A-SCONS-CACHE-REGION SCAVT1)	;Cache interference
	((A-SCONS-CACHE-AREA) SETZ)
SCAVT1	(JUMP-NOT-EQUAL M-K A-LCONS-CACHE-REGION SCAVT2)
	((A-LCONS-CACHE-AREA) SETZ)
SCAVT2	(POPJ-AFTER-NEXT POPJ-IF-BIT-CLEAR M-SCAVENGE-FLAG)
       ((A-SCAV-WORK-DONE) ADD M-B A-SCAV-WORK-DONE)

;Scavenge the specified amount or until a page fault.
XSCAV (MISC-INST-ENTRY %GC-SCAVENGE)
	((M-R) Q-POINTER C-PDL-BUFFER-POINTER-POP)	;Amount of scav work to do
XSCAV1	((M-T) DPB M-ZERO Q-ALL-BUT-TYPED-POINTER A-GC-FLIP-READY)
	(POPJ-NOT-EQUAL M-T A-V-NIL)			;Return if scavenger all done
	((M-S) A-DISK-PAGE-READ-COUNT)
	(CALL-XCT-NEXT SCAV2)				;Just do 1 single scavenge step
       ((M-E) (A-CONSTANT 1))
	(POPJ-NOT-EQUAL M-S A-DISK-PAGE-READ-COUNT)	;Return if took page fault
	(JUMP-GREATER-THAN-XCT-NEXT M-R (A-CONSTANT 1) XSCAV1)
       ((M-R) SUB M-R (A-CONSTANT 1))
	(JUMP XFALSE)					;Return if did specified # steps

;Make the scavenger forget about a particular region
;This also removes the region from the cons cache
SCVRST (MISC-INST-ENTRY %GC-SCAV-RESET)
	((M-K) Q-POINTER C-PDL-BUFFER-POINTER-POP)	;arg 1 - region number
	((A-SCONS-CACHE-AREA) SETZ)			;Clear cons cache
	((A-LCONS-CACHE-AREA) SETZ)
	;; the generational collector (contract g3 step 2, 4.4): a region reset
	;; may need scanning, so the region loop runs before the walk goes on
	((a-scav-region-dirty) (a-constant 1))
	(JUMP-NOT-EQUAL M-K A-SCAV-REGION XFALSE)	;nothing if scavenger not looking here
	(JUMP-XCT-NEXT XTRUE)
       ((A-SCAV-COUNT) M-ZERO)			;Else make scavenger forget its state

;Adjust A-CONS-WORK-DONE
XGCCW (MISC-INST-ENTRY %GC-CONS-WORK)
	(CALL FXUNPK-P-1)				;M-1 gets adjustment
	;; the generational collector (contract g3 step 2, 4.1): the words consed
	;; since the flip move by the adjustment too
	((m-tem) add m-1 a-gc-words-consed-since-flip)
	((a-gc-words-consed-since-flip) dpb m-tem q-pointer (a-constant (byte-value q-data-type dtp-fix)))
	((M-1) DPB M-1 (BYTE-FIELD 30. 2) A-ZERO)	;Multiply by 4
	(JUMP-XCT-NEXT XFALSE)
       ((A-CONS-WORK-DONE) ADD M-1 A-CONS-WORK-DONE)

;HERE WHEN AREA REQUIRES NEW REGION

SCONS5	(JUMP-EQUAL M-S
		(A-CONSTANT (PLUS (BYTE-VALUE Q-DATA-TYPE DTP-FIX)
				  (EVAL (FIND-POSITION-IN-LIST 'EXTRA-PDL-AREA AREA-LIST))))
		EXTRA-PDL-OV)			;EXTRA-PDL FULL
	((M-E) (A-CONSTANT (EVAL %REGION-REPRESENTATION-TYPE-STRUCTURE)))
	(JUMP-XCT-NEXT SCONS2)
       (CALL RCONS)

;LIST-TYPE EXTRA-PDLS NOT CODED.
LCONS5	((M-E) (A-CONSTANT (EVAL %REGION-REPRESENTATION-TYPE-LIST)))
	(JUMP-XCT-NEXT LCONS2)
       (CALL RCONS)

;HERE WHEN SCONS'ING IN EXTRA-PDL AND REGION FULL.  WE CAN GIVE UP AND
;CONS IN WORKING-STORAGE INSTEAD, OR WE CAN DECIDE TO RESET THE EXTRA-PDL
;BY COPYING OUT ANYTHING POINTED TO BY REGISTERS AND PDL-BUFFER.
EXTRA-PDL-OV
	(JUMP-LESS-OR-EQUAL M-B A-3 EXTRA-PDL-OV-0)
	(JUMP SCONS-D)			;won't fit, cons in working storage instead

;FLUSH POINTERS TO EXTRA-PDL OUT OF "MACHINE", I.E. M-ZR - M-K, A-VERSION - A-END-Q-POINTERS,
;PDL BUF, M-B, M-E, M-K, M-S, M-T HAVE INTERNAL DATA OUT OF CONS, WILL PURGE ANYWAY,
;SHOULDN'T HURT
EXTRA-PDL-OV-0
	((M-E) (A-CONSTANT (M-MEM-LOC M-ZR)))
EXTRA-PDL-OV-1
	((OA-REG-HIGH) DPB M-E OAH-M-SRC A-ZERO)
	((M-T) M-GARBAGE oa-high-select)  ;M-GARBAGE IS LOCATION 0@M
	;the oa-high-select above reads oa-reg-high (rev 15)
	(CALL EXTRA-PDL-PURGE)
	((OA-REG-LOW) DPB M-E OAL-M-DEST A-ZERO)
	((M-GARBAGE) M-T oa-low-select)	;reads oa-reg-low (rev 15)
	(JUMP-NOT-EQUAL-XCT-NEXT M-E (A-CONSTANT (M-MEM-LOC M-J)) ;DON'T DO M-S, M-K
		EXTRA-PDL-OV-1)
       ((M-E) ADD M-E (A-CONSTANT 1))
	((M-E) (A-CONSTANT (A-MEM-LOC A-VERSION)))
EXTRA-PDL-OV-2
	((OA-REG-HIGH) DPB M-E OAH-A-SRC A-ZERO)
	((M-T) A-GARBAGE oa-high-select) ;A-GARBAGE IS LOCATION 0@A
	;the oa-high-select above reads oa-reg-high (rev 15)
	(CALL EXTRA-PDL-PURGE)
	((OA-REG-LOW) DPB M-E OAL-A-DEST A-ZERO)
	((A-GARBAGE) M-T oa-low-select)	;reads oa-reg-low (rev 15)
	(JUMP-NOT-EQUAL-XCT-NEXT M-E (A-CONSTANT (A-MEM-LOC A-END-Q-POINTERS)) EXTRA-PDL-OV-2)
       ((M-E) ADD M-E (A-CONSTANT 1))
	((PDL-BUFFER-INDEX) A-PDL-BUFFER-HEAD)
EXTRA-PDL-OV-3
	((M-E) PDL-BUFFER-INDEX)	;Save PI
	(CALL-XCT-NEXT EXTRA-PDL-PURGE)
       ((M-T) C-PDL-BUFFER-INDEX)
	((PDL-BUFFER-INDEX) M-E)	;Restore possibly-clobbered PI
	((C-PDL-BUFFER-INDEX) M-T)
	(JUMP-NOT-EQUAL-XCT-NEXT A-E PDL-BUFFER-POINTER EXTRA-PDL-OV-3)
       ((PDL-BUFFER-INDEX) ADD M-E (A-CONSTANT 1))
	;; Now reset the extra-pdl free-pointer and try again
	((WRITE-MEMORY-DATA) (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	((VMA-START-WRITE) ADD M-K A-V-REGION-FREE-POINTER)
	(CHECK-PAGE-WRITE)
	(JUMP SCONS2)				;Should win this time

;;; If M-T points to extra-pdl, copy out what it points to and change it.
;;; Must protect all lettered registers, M-1, M-2.
EXTRA-PDL-PURGE
	((MD) Q-POINTER M-T	;Start with a cheap test (avoid loading map)
		(A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
;	(POPJ-LESS-THAN MD A-V-EXTRA-PDL-AREA)
	(popj-less-than-unsigned md a-v-extra-pdl-area)	;quux revision 14: unsigned (contract g3 revision 14, 10.1)
;	(POPJ-GREATER-OR-EQUAL MD A-V-MICRO-CODE-ENTRY-AREA)
	(popj-greater-or-equal-unsigned md a-v-micro-code-entry-area)	;quux revision 14: unsigned (contract g3 revision 14, 10.1)
	((MD) M-T)		;Get full ptr including data type
;	((VMA) (A-CONSTANT (EVAL (+ 400 %SYS-COM-TEMPORARY))))
	;; 1024-word pages (contract g2, option (w); appendix a1.9): the system
	;; communication area is at 2000, a page of its own, not 400
	((vma) (a-constant (eval (+ 2000 %sys-com-temporary))))
;	(POPJ-AFTER-NEXT GC-WRITE-TEST)		;Use regular GC-WRITE-TEST mechanism
	(gc-write-test-return)		;Use regular GC-WRITE-TEST mechanism
       ((M-T) MD)
	(popj)				;trans-drop-through's return (rev 15)

;Allocate a new region for area in M-S
;Must be at least M-B words, desired representation type in M-E, other attributes from
; the area's AREA-REGION-BITS, and as follows:
;REGION-SPACE-TYPE is determined as follows:
; If called from scavenger, %REGION-SPACE-COPY
; Otherwise from AREA-REGION-BITS.
;REGION-SCAVENGE-ENABLE is determined as follows:
; For static area, it should be on and will be copied from AREA-REGION-BITS.
; For dynamic area, it should be on for COPY and off otherwise.
;Return region number in M-K
;May bash M-E, M-T only (among lettered registers).
;Protects M-1, M-2.

RCONS	((VMA-START-READ) ADD M-S A-V-AREA-REGION-LIST)	;COMPUTE CURRENT SIZE OF AREA
	(CHECK-PAGE-READ)				;BY ADDING UP SIZES OF ALL REGIONS
	((M-4) SETZ)					;INTO M-4
	((M-K) Q-POINTER READ-MEMORY-DATA)
RCONS0	((VMA-START-READ) ADD M-K A-V-REGION-LENGTH)	;USE TOTAL SIZE NOT ALLOCATED SIZE
	(CHECK-PAGE-READ)
	((M-4) ADD READ-MEMORY-DATA A-4)
	((VMA-START-READ) ADD M-K A-V-REGION-LIST-THREAD)
	(CHECK-PAGE-READ)
	(JUMP-IF-BIT-CLEAR-XCT-NEXT BOXED-SIGN-BIT READ-MEMORY-DATA RCONS0)
       ((M-K) Q-POINTER READ-MEMORY-DATA)
	;; the generational collector (contract g3 step 2, 6.1): the words the new
	;; region must hold, a-cons-region-need: m-b, and room for the first-object
	;; table a tenured structure region begins with, more than its 1 or 2
	;; header words and an entry a page (two words for each page of m-b, and 24
	;; for the quantum's rounding).  without it, an object that fills a region
	;; of the area's size would find no room in a new region either, and the
	;; cons would make regions for ever.
	((a-cons-region-need) m-b)
	(jump-not-equal m-e (a-constant (eval %region-representation-type-structure)) rcons-need)
	((m-tem) a-cons-generation)
	(jump-not-equal m-tem (a-constant region-generation-tenured) rcons-need)
	((m-tem) vma-page-addr-part m-b)
	((m-tem) dpb m-tem (byte-field 31. 1) a-zero)
	((m-tem) add m-tem (a-constant 30))
	((a-cons-region-need) add m-tem a-b)
rcons-need
	((VMA-START-READ) ADD M-S A-V-AREA-REGION-SIZE)
	(CHECK-PAGE-READ)
	((M-3) Q-POINTER READ-MEMORY-DATA)	;NORMAL AMOUNT TO ALLOCATE
;	(JUMP-GREATER-THAN M-3 A-B RCONS1)
;	((M-3) M-B)				;M-3 AMOUNT WE WANT TO ALLOCATE
	(jump-greater-than m-3 a-cons-region-need rcons1)
	((m-3) a-cons-region-need)		;m-3 amount we want to allocate
RCONS1	((VMA-START-READ) ADD M-S A-V-AREA-MAXIMUM-SIZE)
	(CHECK-PAGE-READ)
	((MD) Q-POINTER READ-MEMORY-DATA)
;	(JUMP-EQUAL MD (A-CONSTANT 37777777) RCONS2) ;MAX AREA ALLOCATED, NO OVERFLOW.
	;; quux revision 13: an area of no maximum has most-positive-fixnum, 2^31-1
	;; (make-area's and the cold load's, describe-area's test), not 2^23-1
	(jump-equal md (a-constant 17777777777) rcons2) ;max area allocated, no overflow.
	((M-4) Q-POINTER M-4)
	((M-4) SUB MD A-4)			;M-4 AMOUNT LEFT BEFORE OVERFLOW
	(JUMP-GREATER-OR-EQUAL M-4 A-3 RCONS2)	;JUMP IF NO OVERFLOW PROBLEM
	(JUMP-IF-BIT-SET M-TRANSPORT-FLAG RCONS2A) ;INHIBIT EMBARRASSING TRAP OUT OF TRANSP
;	(CALL-GREATER-THAN M-B A-4 TRAP)
	;; the generational collector (contract g3 step 2, 6.1): m-b and the
	;; first-object table's room (a-cons-region-need, above)
	((m-tem) a-cons-region-need)
	(call-greater-than m-tem a-4 trap)
    (ERROR-TABLE AREA-OVERFLOW M-S)
	(JUMP-XCT-NEXT RCONS2)			;CONS MAXIMAL SIZE REGION
       ((M-3) M-4)
;RCONS2A	((M-3) M-B)				;ALMOST OVERFLOWING, ALLOCATE LESS (WIN?)
rcons2a	((m-3) a-cons-region-need)		;almost overflowing, allocate less (win?)
RCONS2	((VMA-START-READ) ADD M-S A-V-AREA-REGION-BITS)	;GET BITS FOR THIS REGION 
	(CHECK-PAGE-READ)
	(JUMP-IF-BIT-SET-XCT-NEXT M-TRANSPORT-FLAG RCONS4)
       ((M-4) READ-MEMORY-DATA)
	(DISPATCH-XCT-NEXT (LISP-BYTE %%REGION-SPACE-TYPE) M-4 D-RCONS)	;Check region type
	     (ERROR-TABLE RCONS-FIXED)
RCONS3 ((M-4) IOR M-4 (A-CONSTANT (BYTE-MASK %%REGION-OLDSPACE-META-BIT))) ;Not oldspace
	;; the generational collector (contract g3 step 2, 3.1, 3.2): the new region
	;; holds the cons's generation (a-cons-generation: the mutator's allocation
	;; generation, or the transporter's destination), and its bit 13 says it
	;; lies in ephemeral space exactly when that is not tenured, whatever the
	;; area's bit 13 says: an ephemeral area's tenured regions lie below it.
	((m-tem) a-cons-generation)
	((m-4) dpb m-tem region-generation a-4)
	(jump-equal m-tem (a-constant region-generation-tenured) rcons-tenured)
	(jump-xct-next rcons-make)
       ((m-4) dpb (m-constant -1) (lisp-byte %%region-ephemeral) a-4)
rcons-tenured
	((m-4) dpb m-zero (lisp-byte %%region-ephemeral) a-4)
rcons-make
	(CALL-XCT-NEXT MAKE-REGION)		;ALLOCATE A REGION OF THAT SIZE (TO M-K)
       ((M-4) DPB M-E (LISP-BYTE %%REGION-REPRESENTATION-TYPE) A-4)
	;Cons into area region list - for now we just put it at the front
	;In the case where there is more than one representation type this could be unoptimal
	((VMA-START-READ) ADD M-S A-V-AREA-REGION-LIST)
	(CHECK-PAGE-READ)
	((M-3) READ-MEMORY-DATA)		;2ND REGION
	((WRITE-MEMORY-DATA-START-WRITE) DPB M-K Q-POINTER A-3)
	(CHECK-PAGE-WRITE)
	((WRITE-MEMORY-DATA) M-3)
	(POPJ-AFTER-NEXT
	 (VMA-START-WRITE) ADD M-K A-V-REGION-LIST-THREAD)
       (CHECK-PAGE-WRITE)

RCONS4	((MD) (A-CONSTANT (EVAL %REGION-SPACE-COPY)))
	((M-4) DPB MD (LISP-BYTE %%REGION-SPACE-TYPE) A-4)
	(JUMP-XCT-NEXT RCONS3)	;COPY space should always have scavenge enable
       ((M-4) DPB (M-CONSTANT -1) (LISP-BYTE %%REGION-SCAVENGE-ENABLE) A-4)

RCONS-DYNAM	;Newspace doesn't need to be scavenged
	(POPJ-AFTER-NEXT (M-TEM) (A-CONSTANT (EVAL %REGION-SPACE-NEW)))
       ((M-4) DPB M-ZERO (LISP-BYTE %%REGION-SCAVENGE-ENABLE) A-4)

(LOCALITY D-MEM)
(START-DISPATCH 4 0)
D-RCONS	(P-BIT ILLOP)		;0 FREE
	(P-BIT ILLOP)		;1 OLD (should not create old space regions)
	(P-BIT R-BIT)		;2 NEW (copy it)
	(P-BIT R-BIT)		;3 NEW1 (copy it)
	(P-BIT R-BIT)		;4 NEW2 (copy it)
	(P-BIT R-BIT)		;5 NEW3 (copy it)
	(P-BIT R-BIT)		;6 NEW4 (copy it)
	(P-BIT R-BIT)		;7 NEW5 (copy it)
	(P-BIT R-BIT)		;10 NEW6 (copy it)
	(P-BIT R-BIT)		;11 STATIC (copy it)
	(P-BIT INHIBIT-XCT-NEXT-BIT TRAP) ;12 FIXED (not supposed to cons new regions)
	(P-BIT R-BIT)		;13 EXTRA-PDL (copy it)
	(P-BIT ILLOP)		;14 COPY (should not create copy regions except transporter)
(REPEAT 3 (P-BIT ILLOP))
(END-DISPATCH)
(LOCALITY I-MEM)

;;; MAKE A REGION.
;;; M-3 HAS SIZE IN WORDS, M-4 HAS REGION-BITS
;;; SETS UP EVERYTHING ELSE EXCEPT REGION-LIST-THREAD, RETURNS REGION IN M-K, BASHES M-E, M-T
;;; PRESERVES M-3 AND M-4, EXCEPT M-3 IS ROUNDED UP TO THE NEXT QUANTUM BOUNDARY
MAKE-REGION
	((M-3) ADD M-3 (A-CONSTANT (EVAL (1- %ADDRESS-SPACE-QUANTUM-SIZE)))) ;Round up to
	((M-3) SELECTIVE-DEPOSIT M-3 VMA-QUANTUM-BYTE A-ZERO)		     ; quantum bound
;	((A-REGION-CONS-ALARM) M+A+1 M-ZERO A-REGION-CONS-ALARM)
;; quux revision 13 (contract g2 2.2): an arithmetic result takes m's tag,
;; and m-zero, m-minus-one and m-tem have none: the sum, then the fixnum's
;; tag by dpb, since lisp reads these (%region-cons-alarm,
;; %page-cons-alarm; the gc process waits on them) as fixnums.
	((m-tem) m+a+1 m-zero a-region-cons-alarm)
	((a-region-cons-alarm) dpb m-tem q-pointer (a-constant (byte-value q-data-type dtp-fix)))
	((M-TEM) VMA-PAGE-ADDR-PART M-3)	;Length of region in pages
;	((A-PAGE-CONS-ALARM) ADD M-TEM A-PAGE-CONS-ALARM)
	((m-tem) add m-tem a-page-cons-alarm)
	((a-page-cons-alarm) dpb m-tem q-pointer (a-constant (byte-value q-data-type dtp-fix)))
	;; Search address-space-map for suitable number of consecutive zeros
;	((M-T) A-V-FIRST-UNFIXED-AREA)		;Starting address
;	((M-TEM) A-LOWEST-DIRECT-VIRTUAL-ADDRESS)  ;Avoid losing if additional direct
;	((M-TEM) VMA-PAGE-ADDR-PART M-TEM)	   ; space created or band allocated too big.
	;; 1024-word pages (contract g2, option (w)): a-disk-maximum, the paging
	;; partition's size, is in 256-word blocks, not pages
;	((m-tem) vma-block-part m-tem)	   ; space created or band allocated too big.
;	(JUMP-LESS-THAN M-TEM A-DISK-MAXIMUM MAKE-REGION-0)
;	((M-TEM) A-DISK-MAXIMUM)		;Ending address
;MAKE-REGION-0
;	((M-K) DPB M-TEM VMA-PAGE-ADDR-PART
;	 (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
;	((m-k) dpb m-tem vma-block-part
;	 (a-constant (byte-value q-data-type dtp-fix)))
	;; quux revision 13 (appendix a1.11): pages again; the paging partition's
	;; pages are a-disk-maximum-pages (its blocks are 5 a page)
;	((m-tem) vma-page-addr-part m-tem)	   ; space created or band allocated too big.
;	(jump-less-than m-tem a-disk-maximum-pages make-region-0)
;	((m-tem) a-disk-maximum-pages)		;ending address
;make-region-0
;	((m-k) dpb m-tem vma-page-addr-part
;	 (a-constant (byte-value q-data-type dtp-fix)))
;MAKE-REGION-1
;	((M-E) ADD M-T A-3)			;End of large enough region starting here
;MAKE-REGION-2	
;	(CALL-GREATER-OR-EQUAL M-T A-K TRAP)	;Reached end of map, with no luck
;	    (ERROR-TABLE VIRTUAL-MEMORY-OVERFLOW)
;	(CALL ADDRESS-SPACE-MAP-LOOKUP)		;This could be optimized to save some mem rds?
;	(JUMP-NOT-EQUAL-XCT-NEXT M-TEM A-ZERO MAKE-REGION-1)
;       ((M-T) ADD M-T (A-CONSTANT (EVAL %ADDRESS-SPACE-QUANTUM-SIZE)))
;	(JUMP-LESS-THAN M-T A-E MAKE-REGION-2)	;Found free space, but not big enough yet
;	((M-T) SUB M-T A-3)			;Base address of free space found
;; quux revision 14 (contract g3 revision 14, 9.3, 10.2, 10.11): commit, and
;; the bounds by space, compared unsigned.
;; commit: the regions' pages, this one's included, may not exceed the paging
;; partition's slots plus the pageable frames (a-commit-limit, set at boot);
;; otherwise virtual-memory-overflow, as the bound by the partition's pages
;; (above, commented out) gave.
	((m-e) vma-page-addr-part m-3)		;this region's pages
	((m-t) (a-constant (eval size-of-area-arrays)))	;every region, from the last
make-region-commit
	((vma-start-read) add m-t a-v-region-bits)
	(check-page-read)
	((m-tem) (lisp-byte %%region-space-type) read-memory-data)
	(jump-equal m-tem a-zero make-region-commit-1)	;free
	((vma-start-read) add m-t a-v-region-length)
	(check-page-read)
	((m-tem) add read-memory-data (a-constant (eval (1- page-size))))
	((m-tem) vma-page-addr-part m-tem)	;its pages
	((m-e) add m-e a-tem)
make-region-commit-1
	(jump-greater-than-xct-next m-t a-zero make-region-commit)
       ((m-t) sub m-t (a-constant 1))
	(call-greater-than-unsigned m-e a-commit-limit trap)
	    (error-table virtual-memory-overflow)
;; the bounds (10.2): a region of an ephemeral area (region bit 13, the former
;; compact-cons flag, lisp's %%region-ephemeral) lies in ephemeral space,
;; 32000000000-33777777777; any other from the region floor up to below
;; 32000000000.  the floor (10.11), a-region-floor, is the first unfixed
;; area's address by default; it is never taken below that.  m-k is the bound.
	(jump-if-bit-set (byte-field 1 13.) m-4 make-region-ephemeral)
	((m-t) dpb m-zero q-all-but-pointer a-region-floor)
	((m-tem) dpb m-zero q-all-but-pointer a-v-first-unfixed-area)
	(jump-greater-or-equal-unsigned m-t a-tem make-region-floor)
	((m-t) m-tem)				;never below the fixed areas
make-region-floor
	(jump-xct-next make-region-1)
       ((m-k) (a-constant 32000000000))
make-region-ephemeral
	((m-t) (a-constant 32000000000))
	((m-k) (a-constant 34000000000))
	;; Search address-space-map for suitable number of consecutive zeros:
	;; m-t the quantum looked at, m-e the end of a region starting where the
	;; free quanta began.
MAKE-REGION-1
	((M-E) ADD M-T A-3)			;End of large enough region starting here
	(call-greater-than-unsigned m-e a-k trap)	;reached the bound, with no luck
	    (error-table virtual-memory-overflow)
MAKE-REGION-2
	(CALL ADDRESS-SPACE-MAP-LOOKUP)		;This could be optimized to save some mem rds?
	(JUMP-NOT-EQUAL-XCT-NEXT M-TEM A-ZERO MAKE-REGION-1)
       ((M-T) ADD M-T (A-CONSTANT (EVAL %ADDRESS-SPACE-QUANTUM-SIZE)))
	(jump-less-than-unsigned m-t a-e make-region-2)	;found free space, but not big enough yet
	((M-T) SUB M-T A-3)			;Base address of free space found
	;; M-T has origin, M-3 has length, M-4 has bits.  Put region in tables.
;	((VMA-START-READ) (A-CONSTANT (EVAL (PLUS 400 %SYS-COM-FREE-REGION/#-LIST))))
	;; 1024-word pages (contract g2, option (w); appendix a1.9): the system
	;; communication area is at 2000, a page of its own, not 400
	((vma-start-read) (a-constant (eval (plus 2000 %sys-com-free-region/#-list))))
	(CHECK-PAGE-READ)
	((M-K) Q-POINTER READ-MEMORY-DATA)	;Number of new region
	(CALL-EQUAL M-K A-ZERO TRAP)		;Out of region numbers
	    (ERROR-TABLE REGION-TABLE-OVERFLOW)
	((VMA-START-READ) ADD M-K A-V-REGION-LIST-THREAD)	;CDR OFF OF LIST
	(CHECK-PAGE-READ)
	((WRITE-MEMORY-DATA) READ-MEMORY-DATA)	;THIS ENSURES READ CYCLE FINISHES
;	((VMA-START-WRITE) (A-CONSTANT (EVAL (PLUS 400 %SYS-COM-FREE-REGION/#-LIST))))
	;; 1024-word pages (contract g2, option (w); appendix a1.9): the system
	;; communication area is at 2000, a page of its own, not 400
	((vma-start-write) (a-constant (eval (plus 2000 %sys-com-free-region/#-list))))
	(CHECK-PAGE-WRITE)
	;; Proceed to initialize the various tables, except list-thread which caller does.
	((WRITE-MEMORY-DATA) Q-POINTER M-T (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	((VMA-START-WRITE) ADD M-K A-V-REGION-ORIGIN)
	(ILLOP-IF-PAGE-FAULT)
	((WRITE-MEMORY-DATA) Q-POINTER M-3 (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	((VMA-START-WRITE) ADD M-K A-V-REGION-LENGTH)
	(ILLOP-IF-PAGE-FAULT)
	((WRITE-MEMORY-DATA) Q-POINTER M-4 (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	((VMA-START-WRITE) ADD M-K A-V-REGION-BITS)
	(CHECK-PAGE-WRITE)
	;; Set up address-space-map
	((M-E) ADD M-T A-3)			;End of region
MAKE-REGION-3
	(CALL ADDRESS-SPACE-MAP-STORE)
	((M-T) ADD M-T (A-CONSTANT (EVAL %ADDRESS-SPACE-QUANTUM-SIZE)))
;	(JUMP-LESS-THAN M-T A-E MAKE-REGION-3)
	(jump-less-than-unsigned m-t a-e make-region-3)	;quux revision 14: unsigned (contract g3 revision 14, 10.1)
;; quux revision 14 (contract g3 revision 14, 9.4): every page of the region
;; gets an entry: not in core, no slot, the region's meta bits, <19> 0.  a
;; megaword met for the first time gets a page-table page.  the entries were
;; status 0, which the walk never loads, so no invalidation is needed.
;; find-page-entry-or-make can evict a page for a page-table page, so the
;; lettered registers this keeps are saved around it.
	((c-pdl-buffer-pointer-push) m-a)
	((c-pdl-buffer-pointer-push) m-b)
	((c-pdl-buffer-pointer-push) m-d)
	((c-pdl-buffer-pointer-push) m-k)
	((c-pdl-buffer-pointer-push) m-3)
	((c-pdl-buffer-pointer-push) m-4)
	((m-t) sub m-e a-3)			;the origin
	((a-paging-tem) m-t)
	((a-paging-tem2) selective-deposit m-4 map-meta-bits-high (a-constant page-entry-fresh))
make-region-entries
	(call-xct-next find-page-entry-or-make)
       ((a-tem1) a-paging-tem)
	((md) a-paging-tem2)
	((vma-start-write) vma)
	(illop-if-page-fault)
	((m-t) a-paging-tem)
	((m-t) add m-t (a-constant (eval page-size)))
	(jump-not-equal-xct-next m-t a-e make-region-entries)
       ((a-paging-tem) m-t)
	((m-4) c-pdl-buffer-pointer-pop)
	((m-3) c-pdl-buffer-pointer-pop)
	((m-k) c-pdl-buffer-pointer-pop)
	((m-d) c-pdl-buffer-pointer-pop)
	((m-b) c-pdl-buffer-pointer-pop)
	((m-a) c-pdl-buffer-pointer-pop)
	;; the generational collector (contract g3 step 2, 6.1, 6.2): a region with
	;; a first-object table (first-object-table-p) gets it now, its pages'
	;; entries made: m-t its words, where the free pointer and the gc pointer
	;; start; 0 for any other region, as before.
	((m-t) a-zero)
	((md) m-4)
	(call first-object-table-p)
	(call-not-equal m-tem a-zero make-region-table)
	;; Finish setting up tables
;	((WRITE-MEMORY-DATA) (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX))) ;FREE PTR = 0
	((write-memory-data) dpb m-t q-pointer (a-constant (byte-value q-data-type dtp-fix)))
	((VMA-START-WRITE) ADD M-K A-V-REGION-FREE-POINTER)
	(CHECK-PAGE-WRITE)
	(POPJ-AFTER-NEXT (VMA-START-WRITE) ADD M-K A-V-REGION-GC-POINTER)
       (CHECK-PAGE-WRITE)

;; make-region-table (contract g3 step 2, 6.1, 6.2): the first-object table of
;; the region made, whose end is m-e and whose words are m-3: an art-32b array
;; at its origin with an entry for each page, a short header if 1777 entries
;; or fewer, else a long one and its length word; entry 0, and the entry of
;; every other page the table itself covers, is 0, the table's own start.  the
;; other entries are written as objects come to hold their pages' first words
;; (consf).  returns its words in m-t.  clobbers m-e, m-tem, vma, md.
make-region-table
	((m-e) sub m-e a-3)			;the origin
	((m-t) vma-page-addr-part m-3)		;its pages, an entry each
	(jump-greater-than m-t (a-constant (eval %array-max-short-index-length)) make-region-table-long)
	((md) ior m-t (a-constant (plus (byte-value q-data-type dtp-array-header)
					(byte-value %%array-number-dimensions 1)
					(eval art-32b))))
	((vma-start-write) m-e)
	(check-page-write)
	(jump-xct-next make-region-table-1)
       ((m-t) add m-t (a-constant 1))		;its words: the header, the entries
make-region-table-long
	((md) (a-constant (plus (byte-value q-data-type dtp-array-header)
				(byte-value %%array-number-dimensions 1)
				(byte-value %%array-long-length-flag 1)
				(eval art-32b))))
	((vma-start-write) m-e)
	(check-page-write)
	((md) dpb m-t q-pointer (a-constant (byte-value q-data-type dtp-fix)))	;the length
	((vma-start-write) add m-e (a-constant 1))
	(check-page-write)
	((m-t) add m-t (a-constant 2))		;its words: the header, the length, the entries
make-region-table-1				;vma is the word before entry 0
	((m-tem) sub m-t (a-constant 1))
	((m-tem) vma-page-addr-part m-tem)	;the last page the table covers
	((a-cons-table-count) add m-tem (a-constant 1))
	((md) (a-constant (byte-value q-data-type dtp-fix)))	;entries of 0
make-region-table-2
	((vma-start-write) add vma (a-constant 1))
	(check-page-write)
	((m-tem) a-cons-table-count)
	((a-cons-table-count) sub m-tem (a-constant 1))
	(jump-greater-than m-tem (a-constant 1) make-region-table-2)
	(popj)

;; first-object-table-p (contract g3 step 2, 6.1; clarification 4): m-tem 1 if
;; the region whose bits are md begins with a first-object table, a tenured
;; structure region that is not free, fixed or extra-pdl (static and temporary
;; areas' included), else 0.  clobbers m-tem.
first-object-table-p
	((m-tem) (lisp-byte %%region-representation-type) md)
	(jump-not-equal m-tem (a-constant (eval %region-representation-type-structure))
		first-object-table-p-1)
	((m-tem) region-generation md)
	(jump-not-equal m-tem (a-constant region-generation-tenured) first-object-table-p-1)
	((m-tem) (lisp-byte %%region-space-type) md)
	(jump-equal m-tem (a-constant (eval %region-space-free)) first-object-table-p-1)
	(jump-equal m-tem (a-constant (eval %region-space-fixed)) first-object-table-p-1)
	(jump-equal m-tem (a-constant (eval %region-space-extra-pdl)) first-object-table-p-1)
	(popj-after-next (m-tem) (a-constant 1))
       (no-op)
first-object-table-p-1
	(popj-after-next (m-tem) a-zero)
       (no-op)

;;; SUBROUTINE TO CREATE A REGION, CALLED ONLY BY AREA-CREATOR
;;; EXISTS MAINLY BECAUSE THE MICROCODE HAS TO KNOW HOW TO DO THIS ANYWAY
;-- no longer necessary. will be flushed soon.
XMKRG (MISC-INST-ENTRY %MAKE-REGION)
	((M-3) Q-POINTER C-PDL-BUFFER-POINTER-POP)	;SIZE
	(CALL-XCT-NEXT MAKE-REGION)
       ((M-4) Q-POINTER C-PDL-BUFFER-POINTER-POP)	;BITS
	(POPJ-AFTER-NEXT
	 (M-T) Q-POINTER M-K (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
       (NO-OP)

;Given an address in M-T, look up in the address space map, return result in M-TEM
ADDRESS-SPACE-MAP-LOOKUP
	;; Get word from ADDRESS-SPACE-MAP (assuming it starts on proper boundary!)
	((VMA-START-READ) ADDRESS-SPACE-MAP-WORD-INDEX-BYTE M-T A-V-ADDRESS-SPACE-MAP)
	(ILLOP-IF-PAGE-FAULT)
	((M-TEM) ADDRESS-SPACE-MAP-BYTE-NUMBER-BYTE M-T)	;Byte number in that word
	((M-TEM) DPB M-TEM ADDRESS-SPACE-MAP-BYTE-MROT A-ZERO)
;	(POPJ-AFTER-NEXT (OA-REG-LOW) SUB (M-CONSTANT 40) A-TEM) ;40 doesn't hurt here, IORed
;; quux revision 13: a right rotate by e is a rotate of 40. - e, 50 octal, in
;; the ring of 40 (a1.2)
	(popj-after-next (oa-reg-low) sub (m-constant 50) a-tem) ;50 doesn't hurt here, iored
       ((M-TEM) (BYTE-FIELD (EVAL %ADDRESS-SPACE-MAP-BYTE-SIZE) 0) READ-MEMORY-DATA oa-low-select)	;reads oa-reg-low (rev 15)

;Given an address in M-T, store M-K into the address space map.
ADDRESS-SPACE-MAP-STORE
	;; Get word from ADDRESS-SPACE-MAP (assuming it starts on proper boundary!)
	((VMA-START-READ) ADDRESS-SPACE-MAP-WORD-INDEX-BYTE M-T A-V-ADDRESS-SPACE-MAP)
	(ILLOP-IF-PAGE-FAULT)
	((M-TEM) ADDRESS-SPACE-MAP-BYTE-NUMBER-BYTE M-T)	;Byte number in that word
	((A-TEM1) READ-MEMORY-DATA)
;	(POPJ-AFTER-NEXT (OA-REG-LOW) DPB M-TEM ADDRESS-SPACE-MAP-BYTE-MROT A-ZERO)
;       ((WRITE-MEMORY-DATA-START-WRITE) DPB M-K
;		(BYTE-FIELD (EVAL %ADDRESS-SPACE-MAP-BYTE-SIZE) 0) A-TEM1)
	;; quux revision 15 (the map-after-start check; cadrlp): a memory
	;; start is not followed by a word that reads the map, and a start in a
	;; return's slot is refused, since what runs next is not known.  so the
	;; start carries the popj, and a no-op is its slot: one word more.
	((OA-REG-LOW) DPB M-TEM ADDRESS-SPACE-MAP-BYTE-MROT A-ZERO)
	(POPJ-AFTER-NEXT (WRITE-MEMORY-DATA-START-WRITE) DPB M-K
		(BYTE-FIELD (EVAL %ADDRESS-SPACE-MAP-BYTE-SIZE) 0) A-TEM1 oa-low-select)	;reads oa-reg-low (rev 15)
       (no-op)

;;; CALL THIS ROUTINE TO FREE UP A REGION, NUMBER IN M-K (MUST BE PURE NUMBER).
;;; BASHES M-A,M-B,M-D,M-E,M-K,M-T, M-1...M-2, A-TEM1...A-TEM3

XFREE-REGION (MISC-INST-ENTRY %GC-FREE-REGION)
	((M-K) Q-POINTER C-PDL-BUFFER-POINTER-POP)
FREE-REGION
	;; region-to-area's table (uc-page-fault): the number freed may be made
	;; next for another area, so its byte says not known
	(call region-area-map-forget)
	((WRITE-MEMORY-DATA) (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	((VMA-START-WRITE) ADD M-K A-V-REGION-BITS)	;Clear the REGION-BITS, = free status
	(CHECK-PAGE-WRITE)
	((M-D) DPB (M-CONSTANT -1) (BYTE-FIELD 1 31.)	;Change swap-status to Flushable
		(A-CONSTANT 2))				; and disconnect the virtual page
	(CALL-XCT-NEXT UPDATE-REGION-PHT);Note that this sets M-1 and M-2 to the region bounds
       ((MD) (A-CONSTANT (BYTE-VALUE MAP-STATUS-CODE 2))) ;Make read-only, no access, in PHT2
	;; Put region in M-K onto free region-table-entry list
;	((VMA-START-READ) (A-CONSTANT (EVAL (PLUS 400 %SYS-COM-FREE-REGION/#-LIST))))
	;; 1024-word pages (contract g2, option (w); appendix a1.9): the system
	;; communication area is at 2000, a page of its own, not 400
	((vma-start-read) (a-constant (eval (plus 2000 %sys-com-free-region/#-list))))
	(ILLOP-IF-PAGE-FAULT)
	((A-TEM2) READ-MEMORY-DATA)
	((WRITE-MEMORY-DATA-START-WRITE) Q-POINTER M-K
		(A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	(ILLOP-IF-PAGE-FAULT)
	((WRITE-MEMORY-DATA) A-TEM2)
	((VMA-START-WRITE) ADD M-K A-V-REGION-LIST-THREAD)
	(CHECK-PAGE-WRITE)
	;; Remove from ADDRESS-SPACE-MAP
	;; Referencing these addresses will halt in PAGE-IN-GET-MAP-BITS
	((M-T) M-1)
	;; a region of no length owns no quantum.  the loop below tests at its end, so
	;; it stored 0 for the quantum at such a region's origin, which is another
	;; region's: the cold load gives its last area, fasl-temp-area, a region of no
	;; length at the end of its areas, where the next region made begins, and a
	;; full gc that freed it after that quantum had passed to a new region left
	;; the new region out of the map ("the argument area was nil" from
	;; gc-get-space-sizes, or "region not found" in get-map-bits).
;	(jump-greater-or-equal m-t a-2 free-region-2)
	(jump-greater-or-equal-unsigned m-t a-2 free-region-2)	;quux revision 14: unsigned (contract g3 revision 14, 10.1)
FREE-REGION-1
	(CALL-XCT-NEXT ADDRESS-SPACE-MAP-STORE)
       ((M-K) A-ZERO)
	((M-T) ADD M-T (A-CONSTANT (EVAL %ADDRESS-SPACE-QUANTUM-SIZE)))
;	(JUMP-LESS-THAN M-T A-2 FREE-REGION-1)
	(jump-less-than-unsigned m-t a-2 free-region-1)	;quux revision 14: unsigned (contract g3 revision 14, 10.1)
free-region-2
	(POPJ-AFTER-NEXT (M-T) A-V-NIL)
       (NO-OP)

;Remove all information about the region in M-K from the page map,
;and fix the PHT entries of any swapped-in pages.
;Call with MD containing the new REGION-BITS entry for the region,
; and M-D containing A-V-NIL or the new swap-status.
;Sets M-1 and M-2 to the bounds of the region.
;Bashes M-A, M-B, M-E, M-T, tems.
;UPDATE-REGION-PHT
;	((M-E) (LISP-BYTE %%REGION-MAP-BITS) MD)	;Arg for XCPGS0
;	((VMA-START-READ) ADD M-K A-V-REGION-ORIGIN)	;Find virtual address range of region
;	(CHECK-PAGE-READ)
;	((M-1) Q-POINTER READ-MEMORY-DATA)
;	((VMA-START-READ) ADD M-K A-V-REGION-LENGTH)
;	(CHECK-PAGE-READ)
;	((M-2) Q-POINTER READ-MEMORY-DATA)
;	((MD M-2) ADD M-1 A-2)
	;; M-1 has lowest address in region, M-2 has highest address in region +1
	;; Both are necessarily a multiple of the page size.
	;; Call XCPGS0 on each page, to fix the PHT entry (if any) and the map.
	;; a region of no length has no page.  the loop below tests at its end, so it
	;; called xcpgs0 on the page below such a region's origin, another region's
	;; page: a flip gave it this region's map bits, and free-region made it
	;; flushable and forgot it.
;	(popj-less-or-equal m-2 a-1)
;UPDATE-REGION-PHT-0
;	(CALL-XCT-NEXT XCPGS0)
;       ((C-PDL-BUFFER-POINTER-PUSH) SUB MD (A-CONSTANT (EVAL PAGE-SIZE)))
;	(JUMP-GREATER-THAN MD A-1 UPDATE-REGION-PHT-0)
;	(POPJ)

;Remove all information about the region in M-K from the page map,
;and fix the page table entries of its pages.
;Call with MD containing the new REGION-BITS entry for the region,
; and M-D containing A-V-NIL or, negative, freeing (free-region).
;Sets M-1 and M-2 to the bounds of the region.
;Bashes M-A, M-B, M-E, M-T, tems.
;; quux revision 14 (contract g3 revision 14, 9.3, 9.4): every page of the
;; region has an entry, which is rewritten in place, a page at a time, with no
;; hash table to search.  a flip (m-d nil) rewrites <27:20> of an entry in core
;; from the region's bits, and the meta bits <23:20> of one not in core, and
;; keeps <29:28> (accessed and modified, or the slot) and <19:18>
;; (ephemeral-reference and software's).  freeing (m-d negative) frees each
;; page's frame and slot and writes status 0, no entry.  then the tlb is
;; emptied once, as every entry of the region may have changed (about 41
;; microseconds at 4,096 entries).
UPDATE-REGION-PHT
	((M-E) (LISP-BYTE %%REGION-MAP-BITS) MD)	;the region's access, status, meta
	((VMA-START-READ) ADD M-K A-V-REGION-ORIGIN)	;Find virtual address range of region
	(CHECK-PAGE-READ)
	((M-1) Q-POINTER READ-MEMORY-DATA)
	((VMA-START-READ) ADD M-K A-V-REGION-LENGTH)
	(CHECK-PAGE-READ)
	((M-2) Q-POINTER READ-MEMORY-DATA)
	((M-2) ADD M-1 A-2)
	;; M-1 has lowest address in region, M-2 has highest address in region +1
	;; Both are necessarily a multiple of the page size.
	;; a region of no length has no page.
	(popj-equal m-2 a-1)
	((m-b) m-1)				;the page
update-region-pht-0
	(call-xct-next find-page-entry)
       ((a-tem1) m-b)
	((m-a) md)
	((m-tem) map-status-code m-a)
	(jump-equal m-tem a-zero update-region-pht-next)	;no entry
	(jump-if-bit-set boxed-sign-bit m-d update-region-pht-free)
	(jump-less-than m-tem (a-constant 2) update-region-pht-meta)
	((m-tem) (byte-field 8 2) m-e)		;in core: <27:20>
	(jump-xct-next update-region-pht-write)
       ((m-a) dpb m-tem map-access-status-and-high-meta a-a)
update-region-pht-meta
	((m-tem) (byte-field 4 2) m-e)		;not in core: the meta bits, <23:20>
	((m-a) dpb m-tem map-meta-bits-high a-a)
update-region-pht-write
	((md) m-a)
	((vma-start-write) vma)
	(illop-if-page-fault)
update-region-pht-next
	((m-b) add m-b (a-constant (eval page-size)))
	(jump-not-equal m-b a-2 update-region-pht-0)
	((md) a-zero)				;not a window's address
	((vma-write-map) (a-constant write-map-empty))
	(popj-xct-next)
       ((vma) a-v-nil)
update-region-pht-free
	((a-paging-tem) vma)			;the entry's address
	(call free-page-resources)
	((vma) a-paging-tem)
	(jump-xct-next update-region-pht-write)
       ((m-a) (a-constant (byte-value q-data-type dtp-fix)))	;status 0, no entry

GET-AREA-ORIGINS
;	((VMA-START-READ) (A-CONSTANT (EVAL (PLUS 400 %SYS-COM-AREA-ORIGIN-PNTR))))
	;; 1024-word pages (contract g2, option (w); appendix a1.9): the system
	;; communication area is at 2000, a page of its own, not 400
	((vma-start-read) (a-constant (eval (plus 2000 %sys-com-area-origin-pntr))))
	(ILLOP-IF-PAGE-FAULT)
	((VMA) SUB READ-MEMORY-DATA (A-CONSTANT 1)) ;1- ADDR OF REGION-ORIGIN TABLE
	((M-K) (A-CONSTANT (A-MEM-LOC A-V-RESIDENT-SYMBOL-AREA)))
BEG02	((VMA-START-READ) ADD VMA (A-CONSTANT 1))
	(ILLOP-IF-PAGE-FAULT)
	((OA-REG-LOW) DPB M-K OAL-A-DEST A-ZERO)	;DESTINATION
	((A-GARBAGE) Q-POINTER READ-MEMORY-DATA (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)) oa-low-select)	;reads oa-reg-low (rev 15)
	((M-K) ADD M-K (A-CONSTANT 1))
	(JUMP-NOT-EQUAL M-K (A-CONSTANT (A-MEM-LOC A-V-FIRST-UNFIXED-AREA)) BEG02)
	;; Now find the end of the last fixed area, which is where we can start making regions
	;; Too bad the cold-load generator didn't store this anywhere for us
	((M-K) M-A-1 M-K (A-CONSTANT (A-MEM-LOC A-V-RESIDENT-SYMBOL-AREA)))
	((VMA-START-READ) ADD M-K A-V-REGION-LENGTH)
	(ILLOP-IF-PAGE-FAULT)
	((M-K) ADD READ-MEMORY-DATA A-V-INIT-LIST-AREA)	;...the last fixed area
	;; Round up to next multiple of a quantum
	(POPJ-AFTER-NEXT (M-K) ADD M-K (A-CONSTANT (EVAL (1- %ADDRESS-SPACE-QUANTUM-SIZE))))
       ((A-V-FIRST-UNFIXED-AREA) SELECTIVE-DEPOSIT M-K
		VMA-QUANTUM-BYTE (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))

;;; SAFE ALLOCATION AND INITIALIZATION OF STRUCTURES

;(%ALLOCATE-AND-INITIALIZE <data type for return> <data type for header> <header> 
;				<value for second word> <area> <nqs>)
(ERROR-TABLE DEFAULT-ARG-LOCATIONS %ALLOCATE-AND-INITIALIZE PP PP PP PP PP PP)

XAAI (MISC-INST-ENTRY %ALLOCATE-AND-INITIALIZE)
	(DISPATCH (I-ARG DATA-TYPE-INVOKE-OP)
		Q-DATA-TYPE C-PDL-BUFFER-POINTER TRAP-UNLESS-FIXNUM)
    (ERROR-TABLE ARGTYP FIXNUM-GREATER-THAN-1 PP 5)
	((M-1) Q-POINTER C-PDL-BUFFER-POINTER)	;CHECK FOR ALLOC AT LEAST 2 WORDS
	(CALL-LESS-THAN M-1 (A-CONSTANT 2) TRAP)
    (ERROR-TABLE ARGTYP FIXNUM-GREATER-THAN-1 PP 5)
	(CALL XALLB)			;ALLOCATE BLOCK, RETURN IN M-T, NO SEQUENCE BREAK
					; WHILE CRUFT IS PARTIALLY INITIALIZED.  POPS LAST ARG.
	((VMA) ADD M-T (A-CONSTANT 1))	;-> SECOND WORD
	((WRITE-MEMORY-DATA-START-WRITE) C-PDL-BUFFER-POINTER-POP)
	(CHECK-PAGE-WRITE)
	((A-TEM1) C-PDL-BUFFER-POINTER-POP)	;HEADER Q (POINTER PART)
	((WRITE-MEMORY-DATA) DPB C-PDL-BUFFER-POINTER-POP	;SET DATA TYPE, ETC.
		Q-ALL-BUT-POINTER A-TEM1)
;	(POPJ-AFTER-NEXT			;WRITE THE HEADER, AND
;	 (VMA-START-WRITE M-T) DPB C-PDL-BUFFER-POINTER-POP	; RETURN POINTER TO BLOCK,
;		Q-ALL-BUT-POINTER A-T)		; WITH CORRECT TYPE
;       (CHECK-PAGE-WRITE)
	;; quux revision 12 (contract h8a section 3.3): no call in the
	;; microinstruction after a return, where a fused return has chosen the
	;; next handler (see xfxflp in uc-fctns): check-page-write, a call on a
	;; page fault or an interrupt, now follows the write before the return.
	;; two microcycles more.
	((vma-start-write m-t) dpb c-pdl-buffer-pointer-pop	;write the header, and
		q-all-but-pointer a-t)		; return pointer to block, with correct type
	(check-page-write)
	(popj)

;(%ALLOCATE-AND-INITIALIZE-ARRAY <header as fixnum> <index length> <leader length> 
;					<area> <nqs>)
(ERROR-TABLE DEFAULT-ARG-LOCATIONS %ALLOCATE-AND-INITIALIZE-ARRAY PP PP PP PP PP)

XAAIA (MISC-INST-ENTRY %ALLOCATE-AND-INITIALIZE-ARRAY)
	(CALL XALLB)			;ALLOCATE BLOCK, RETURN IN M-T, NO SEQUENCE BREAK
					; WHILE CRUFT IS PARTIALLY INITIALIZED
		;XALLB ALSO FILLS IT WITH NILS, WHICH IS RIGHT EXCEPT FOR THE DATA
		;PORTION OF A NUMERIC ARRAY.  NOTE THAT THE LEADER OF ANY KIND
		;OF ARRAY WANTS TO BE FILLED WITH NILS.
	((VMA M-T) Q-POINTER M-T	;VMA -> START OF BLOCK, M-T RIGHT MAYBE
		(A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-ARRAY-POINTER)))
	((M-E) ADD M-T A-B)		;UPPER BOUND OF STORAGE, SAME DATA-TYPE AS M-T
	((M-E) SUB M-E (A-CONSTANT 1))		;LAST LOCATION TO BE FILLED
	((M-C) Q-POINTER C-PDL-BUFFER-POINTER-POP)	;LEADER LENGTH
	((M-B) Q-POINTER C-PDL-BUFFER-POINTER-POP)	;INDEX LENGTH
	(JUMP-IF-BIT-CLEAR-XCT-NEXT (LISP-BYTE %%ARRAY-LEADER-BIT)
		C-PDL-BUFFER-POINTER XAAIA1)
       ((M-2) DPB C-PDL-BUFFER-POINTER-POP	;HEADER
	    Q-POINTER (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-ARRAY-HEADER)))
;	((WRITE-MEMORY-DATA-START-WRITE) ADD M-C	;STORE LEADER HEADER
;		(A-CONSTANT (PLUS (PLUS (BYTE-VALUE Q-DATA-TYPE DTP-HEADER)
;					(BYTE-VALUE %%HEADER-TYPE-FIELD
;						    %HEADER-TYPE-ARRAY-LEADER))
;				  2)))
;; quux revision 13 (contract g2 2.2): an arithmetic result takes m's tag,
;; and m-c, the leader's length, has none: the length plus 2, then the
;; header's tag and type by ior, a logical function (the bits do not overlap).
	((write-memory-data) add m-c (a-constant 2))
	((write-memory-data-start-write) ior md	;store leader header
		(a-constant (plus (byte-value q-data-type dtp-header)
				  (byte-value %%header-type-field %header-type-array-leader))))
	(CHECK-PAGE-WRITE)
	((VMA M-T) ADD M-T A-C ALU-CARRY-IN-ONE)	;POINTS ONE BEFORE HEADER
	((WRITE-MEMORY-DATA-START-WRITE) DPB M-C
		Q-POINTER (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	(CHECK-PAGE-WRITE)
	((VMA M-T) ADD M-T (A-CONSTANT 1))	;POINTS TO HEADER
XAAIA1	((WRITE-MEMORY-DATA-START-WRITE) M-2)	;STORE HEADER
	(CHECK-PAGE-WRITE)
	(DISPATCH (LISP-BYTE %%ARRAY-TYPE-FIELD) M-2 SKIP-IF-NUMERIC-ARRAY)
	 (JUMP XAAIA3)				;ALREADY INITED TO NIL
;	(JUMP-GREATER-OR-EQUAL VMA A-E XAAIA3)	;JUMP IF ZERO-LENGTH ARRAY
	(jump-greater-or-equal-unsigned vma a-e xaaia3)	;JUMP IF ZERO-LENGTH ARRAY	;quux revision 14: unsigned (contract g3 revision 14, 10.1)
	((M-3) SELECTIVE-DEPOSIT (LISP-BYTE %%ARRAY-TYPE-FIELD) M-2)
	(JUMP-NOT-EQUAL-XCT-NEXT
	      M-3 (A-CONSTANT (BYTE-VALUE %%ARRAY-TYPE-FIELD
					  (EVAL (LDB %%ARRAY-TYPE-FIELD ART-COMPLEX))))
	      XAAIA2)
	;; This is a numeric or string array, fill with zeros.
;       ((WRITE-MEMORY-DATA) M-ZERO)
	;; quux revision 13 (contract g1 2.6): a word of data carries tag 005, so
	;; the zeros are fixnum zeros (an art-float element reads as 0.0, qfary)
       ((write-memory-data) (a-constant (byte-value q-data-type dtp-fix)))
	;; This is a complex array; init all words to boxed zeros.
	((MD) (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
XAAIA2	((VMA-START-WRITE) ADD VMA (A-CONSTANT 1))
	(CHECK-PAGE-WRITE)
;	(JUMP-LESS-THAN VMA A-E XAAIA2)
	(jump-less-than-unsigned vma a-e xaaia2)	;quux revision 14: unsigned (contract g3 revision 14, 10.1)
XAAIA3	(POPJ-IF-BIT-CLEAR (LISP-BYTE %%ARRAY-LONG-LENGTH-FLAG) M-2)
	((VMA) ADD M-T (A-CONSTANT 1))
;	(POPJ-AFTER-NEXT
;	 (WRITE-MEMORY-DATA-START-WRITE) DPB M-B Q-POINTER 
;		(A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
;       (CHECK-PAGE-WRITE)
	;; quux revision 12 (contract h8a section 3.3): no call in the
	;; microinstruction after a return, where a fused return has chosen the
	;; next handler (see xfxflp in uc-fctns): check-page-write, a call on a
	;; page fault or an interrupt, now follows the write before the return.
	;; two microcycles more.
	((write-memory-data-start-write) dpb m-b q-pointer
		(a-constant (byte-value q-data-type dtp-fix)))
	(check-page-write)
	(popj)
	
;SUBROUTINE TO THE ABOVE.  TAKES AREA AND #QS ON PDL, CALLS SCONS.
;FILLS THE THING WITH NILS
XALLB	(DISPATCH (I-ARG DATA-TYPE-INVOKE-OP)
		Q-DATA-TYPE C-PDL-BUFFER-POINTER TRAP-UNLESS-FIXNUM)
  (ERROR-TABLE ARGTYP POSITIVE-FIXNUM PP NIL)
	(CALL-IF-BIT-SET-XCT-NEXT BOXED-SIGN-BIT C-PDL-BUFFER-POINTER TRAP)
       ((M-B) Q-POINTER C-PDL-BUFFER-POINTER-POP)	;ARG 2 NUMBER OF QS
  (ERROR-TABLE ARGTYP POSITIVE-FIXNUM M-B NIL)
	(CALL-XCT-NEXT SCONS)
       ((M-S) Q-TYPED-POINTER C-PDL-BUFFER-POINTER-POP)	;ARG 1 AREA
	(JUMP-XCT-NEXT FILL-WITH-THINGS)
       ((C-PDL-BUFFER-POINTER-PUSH) A-V-NIL)

;SUBROUTINE TO CONS UP A LIST OF NILS.  ARGS LIKE LCONS.
;NOTE THAT DATA-TYPE RETURNED IN M-T IS GARBAGE.
LIST-OF-NILS
	((C-PDL-BUFFER-POINTER-PUSH) A-V-NIL)

;SUBROUTINE TO CONS UP A LIST OF THINGS.  THE THING TO BE CONSED IS ON THE
;STACK.  OTHERWISE, ARGS LIKE NCONS.  NOTE THAT DATA-TYPE RETURNED IN M-T
;IS GARBAGE.
LIST-OF-THINGS
	(CALL LCONS)
FILL-WITH-THINGS
	((M-3) M-B)				;NUMBER OF CELLS TO INITIALIZE
;	((WRITE-MEMORY-DATA) LDB C-PDL-BUFFER-POINTER-POP	;CDR-NEXT
;		Q-ALL-BUT-CDR-CODE (A-CONSTANT -1))
;; quux revision 13 (appendix a1.5): a constant is zero-extended from 32 bits,
;; so -1 has no bits in the cdr code, <39:38>, and gave cdr-normal; cdr-next
;; is written as its value.
	((write-memory-data) ldb c-pdl-buffer-pointer-pop	;cdr-next
		q-all-but-cdr-code (a-constant (byte-value q-cdr-code cdr-next)))
	((VMA) SUB M-T (A-CONSTANT 1))
	(JUMP-LESS-OR-EQUAL M-3 (A-CONSTANT 1) FILL-WITH-THINGS-1)
FILL-WITH-THINGS-0
	((VMA-START-WRITE) ADD VMA (A-CONSTANT 1))
	(CHECK-PAGE-WRITE)
	(JUMP-GREATER-THAN-XCT-NEXT M-3 (A-CONSTANT 2) FILL-WITH-THINGS-0)
       ((M-3) SUB M-3 (A-CONSTANT 1))
FILL-WITH-THINGS-1
	((WRITE-MEMORY-DATA) Q-ALL-BUT-CDR-CODE WRITE-MEMORY-DATA
			(A-CONSTANT (BYTE-VALUE Q-CDR-CODE CDR-NIL)))
	(POPJ-AFTER-NEXT (VMA-START-WRITE) ADD VMA (A-CONSTANT 1))
       (CHECK-PAGE-WRITE)
;OK TO POPJ AND START MEM CYCLE.  USED AS MISC INSTRUCTION, BUT NOT AS REGULAR INSTRUCTION.
;AND NOT USED AS MISC INSTRUCTION TO D-IGNORE.

;;; Sub-Primitives for dissecting an object in storage.
;;; These are called by the garbage collector and also available as misc functions.

;;; Given a pointer, return the object (base pointer and data type) which contains
;;; the cell to which the pointer points.  This may not be the actual beginning
;;; of the object's storage, in the case of an array with a leader.
;;; Arg on pdl, answer in M-T.  Clobbers M-A, M-B, M-E, and page-fault-clobberable.
;;;This function could maybe be improved with some pipelining, but hair is required!

;;; Inside this routine, it is important to note that M-A and VMA usually
;;; but not always contain the same thing.  The difference has to do with
;;; forwarded structures.  Study the code.

;;; %FIND-STRUCTURE-LEADER is the same except if given an array with a leader,
;;; it returns a locative to the leader-header rather than the usual array-pointer.
;;; This gives you the actual lowest address in the structure, which is what
;;; the transporter needs.

XFSH (MISC-INST-ENTRY %FIND-STRUCTURE-HEADER)
	(JUMP-XCT-NEXT XFSH0)
       ((M-E) SETZ)

XFSL (MISC-INST-ENTRY %FIND-STRUCTURE-LEADER)
	((M-E) SETO)	
XFSH0	(CALL XRGN)				;M-A gets pointer, M-T gets region
	((VMA-START-READ) ADD M-T A-V-REGION-ORIGIN)
	(CHECK-PAGE-READ)
	(POPJ-EQUAL M-T A-V-NIL)		;Return NIL if garbage pointer input
	((M-B) Q-TYPED-POINTER READ-MEMORY-DATA)	;Origin address of region
	((VMA-START-READ) ADD M-T A-V-REGION-BITS)	;Get representation type
	(CHECK-PAGE-READ)
	(DISPATCH (LISP-BYTE %%REGION-REPRESENTATION-TYPE)
		READ-MEMORY-DATA D-FSH)

(LOCALITY D-MEM)
(START-DISPATCH 2 INHIBIT-XCT-NEXT-BIT)
D-FSH	(XFSHL)		;0 LIST
	(XFSHS)		;1 STRUCTURE
	(P-BIT ILLOP)	;2 NOT USED
	(P-BIT ILLOP)	;3 NOT USED
(END-DISPATCH)

(START-DISPATCH 2 0)
D-FSHL	(XFSHL)		;0 CDR-NORMAL
	(P-BIT R-BIT)	;1 CDR-ERROR
	(P-BIT R-BIT)	;2 CDR-NIL
	(XFSHL)		;3 CDR-NEXT
(END-DISPATCH)

(LOCALITY I-MEM)

;%FIND-STRUCTURE-HEADER in list space
XFSHL	(JUMP-EQUAL M-A A-B XFSHL1)		;This is start of list if start of region
	((VMA-START-READ) SUB M-A (A-CONSTANT 1))	;Check preceding word
	(CHECK-PAGE-READ)
	((M-TEM) Q-DATA-TYPE READ-MEMORY-DATA)	;If it is forwarded, not same list
	(JUMP-EQUAL M-TEM (A-CONSTANT (EVAL DTP-HEADER-FORWARD)) XFSHL1)
	(DISPATCH Q-CDR-CODE READ-MEMORY-DATA D-FSHL) ;CDR-NEXT or CDR-NORMAL -> search more,
       ((M-A) SUB M-A (A-CONSTANT 1))
	((M-A) ADD M-A (A-CONSTANT 1))		      ; CDR-ERROR or CDR-NIL -> gone too far.
XFSHL1	(POPJ-XCT-NEXT)
       ((M-T) DPB M-A Q-POINTER (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-LIST)))

;%FIND-STRUCTURE-HEADER in structure space

;This dispatch ignores data-types 0 and -1, rather than going to ILLOP,
;because they are legal in stack-group array-leaders.
;(ASSIGN-EVAL NQZUSD-1 (EVAL (- 31. (LENGTH Q-DATA-TYPES))))
;; quux revision 13: 6-bit types, so the all-ones type (-1) is 63, not 31.
(assign-eval nqzusd-1 (eval (- 63. (length q-data-types))))
(LOCALITY D-MEM)
;(START-DISPATCH 5 0)
;; quux revision 13 (contract g2 2.4): the data type is one bit wider, 6-bit types
(start-dispatch 6 0)
D-FSHS	(XFSHS1)				;TRAP
	(XFSHS1)				;NULL
	(P-BIT INHIBIT-XCT-NEXT-BIT ILLOP)	;FREE
	(XFSHS1)				;SYMBOL
	(INHIBIT-XCT-NEXT-BIT XFSHSS)		;SYMBOL-HEADER
	(XFSHS1)				;FIX
	(XFSHS1)				;EXTENDED-NUMBER
	(INHIBIT-XCT-NEXT-BIT XFSHSH)		;HEADER
	(P-BIT INHIBIT-XCT-NEXT-BIT ILLOP)	;GC-FORWARD
	(XFSHS1)				;EXTERNAL-VALUE-CELL-POINTER
	(XFSHS1)				;ONE-Q-FORWARD
	(INHIBIT-XCT-NEXT-BIT XFSHS-HFWD)	;HEADER-FORWARD
	(INHIBIT-XCT-NEXT-BIT XFSHS-BFWD)	;BODY-FORWARD
	(XFSHS1)				;LOCATIVE
	(XFSHS1)				;LIST
	(XFSHS1)				;U CODE ENTRY
	(XFSHS1)				;FEF
	(XFSHS1)				;ARRAY-POINTER
	(INHIBIT-XCT-NEXT-BIT XFSHSA)		;ARRAY-HEADER
	(XFSHS1)				;STACK-GROUP
	(XFSHS1)				;CLOSURE
	(XFSHS1)				;SMALL-FLONUM 
	(XFSHS1)				;SELECT-METHOD
	(XFSHS1)				;INSTANCE
	(INHIBIT-XCT-NEXT-BIT XFSHSI)		;INSTANCE-HEADER
	(XFSHS1)				;ENTITY
	(XFSHS1)				;STACK-CLOSURE
	(XFSHS1)				;SELF-REF-POINTER
	(XFSHS1)				;CHARACTER
 (REPEAT NQZUSD-1 (P-BIT INHIBIT-XCT-NEXT-BIT ILLOP))
	(XFSHS1)				;DATA-TYPE 37
(END-DISPATCH)

(START-DISPATCH 5 INHIBIT-XCT-NEXT-BIT)	;DISPATCH ON HEADER SUBTYPE
D-FSHSH	(P-BIT ILLOP)	;%HEADER-TYPE-ERROR
	(XFSHSHF)	;%HEADER-TYPE-FEF
	(XFSHSHAL)	;%HEADER-TYPE-ARRAY-LEADER
	(P-BIT ILLOP)	;unused
	(XFSHSHN)	;%HEADER-TYPE-FLONUM
	(XFSHSHN)	;%HEADER-TYPE-COMPLEX
	(XFSHSHN)	;%HEADER-TYPE-BIGNUM
	(XFSHSHN)	;%HEADER-TYPE-RATIONAL
	(P-BIT ILLOP)	;unused
	(P-BIT ILLOP)	;unused
	(P-BIT ILLOP)	;unused
	(P-BIT ILLOP)	;unused
(REPEAT NHDUSD (P-BIT ILLOP))
(END-DISPATCH)
(LOCALITY I-MEM)

;%FIND-STRUCTURE-HEADER in structure space
XFSHS	((VMA-START-READ) M-A)
XFSHS1	(CHECK-PAGE-READ)
;	(CALL-LESS-THAN M-A A-B ILLOP)		;Dropped off top of region
	(call-less-than-unsigned m-a a-b illop)		;Dropped off top of region	;quux revision 14: unsigned (contract g3 revision 14, 10.1)
	(DISPATCH Q-DATA-TYPE READ-MEMORY-DATA D-FSHS)	;Leave loop if header,
       ((M-A VMA-START-READ) SUB M-A (A-CONSTANT 1))	; or read preceding word and loop

XFSHSS	(POPJ-AFTER-NEXT (M-TEM) (A-CONSTANT (EVAL DTP-SYMBOL)))
       ((M-T) DPB M-TEM Q-DATA-TYPE A-A)

;This is an array.  We may want to return a locative pointer to the leader,
;an array-pointer to the header, or a stack-group pointer to the header.
XFSHSA	(JUMP-EQUAL M-E A-ZERO XFSHA2)			;Jump if %FIND-STRUCTURE-HEADER
	(JUMP-IF-BIT-CLEAR (LISP-BYTE %%ARRAY-LEADER-BIT) READ-MEMORY-DATA XFSHA3)
	((VMA-START-READ) SUB VMA (A-CONSTANT 1))	;Pick up leader length
	(CHECK-PAGE-READ)
	((M-TEM) (LISP-BYTE %%ARRAY-LEADER-LENGTH) MD)
	((M-TEM) ADD M-TEM (A-CONSTANT 2))	;and end up returning ptr to leader hdr
	((M-A) SUB M-A A-TEM)
	((M-A) Q-POINTER M-A)		;Prevent garbage data-type in M-A upon return
XFSHA1	(POPJ-AFTER-NEXT (M-TEM) (A-CONSTANT (EVAL DTP-LOCATIVE)))
       ((M-T) DPB M-TEM Q-DATA-TYPE A-A)

;Return a pointer to the header, with data-type DTP-ARRAY-POINTER or DTP-STACK-GROUP
XFSHA2	((M-TEM) (LISP-BYTE %%ARRAY-TYPE-FIELD) READ-MEMORY-DATA)
	(JUMP-EQUAL M-TEM (A-CONSTANT (EVAL (LSH ART-STACK-GROUP-HEAD ARRAY-TYPE-SHIFT)))
			XFSHSG)
XFSHA3	(POPJ-AFTER-NEXT (M-TEM) (A-CONSTANT (EVAL DTP-ARRAY-POINTER)))
       ((M-T) DPB M-TEM Q-DATA-TYPE A-A)

XFSHSG	(POPJ-AFTER-NEXT (M-TEM) (A-CONSTANT (EVAL DTP-STACK-GROUP)))
       ((M-T) DPB M-TEM Q-DATA-TYPE A-A)

XFSHSI	(POPJ-AFTER-NEXT (M-TEM) (A-CONSTANT (EVAL DTP-INSTANCE)))
       ((M-T) DPB M-TEM Q-DATA-TYPE A-A)

XFSHS-BFWD
	((M-A VMA-START-READ) Q-POINTER READ-MEMORY-DATA)	;BODY-FORWARD -> HEADER-FORWARD
	(CHECK-PAGE-READ)
XFSHS-HFWD
	(DISPATCH TRANSPORT-HEADER READ-MEMORY-DATA)	;HEADER-FORWARD -> new header
	(DISPATCH Q-DATA-TYPE READ-MEMORY-DATA D-FSHS)	;DISPATCH ON TYPE OF THAT HEADER,
							; M-A STILL POINTS AT OLD ONE
       (CALL ILLOP)					;SHOULDN'T XCT-NEXT, SHOULD BE HEADER!

XFSHSH	(DISPATCH (LISP-BYTE %%HEADER-TYPE-FIELD) READ-MEMORY-DATA D-FSHSH)

XFSHSHN	(POPJ-AFTER-NEXT (M-TEM) (A-CONSTANT (EVAL DTP-EXTENDED-NUMBER)))
       ((M-T) DPB M-TEM Q-DATA-TYPE A-A)

XFSHSHF	(POPJ-AFTER-NEXT (M-TEM) (A-CONSTANT (EVAL DTP-FEF-POINTER)))
       ((M-T) DPB M-TEM Q-DATA-TYPE A-A)

XFSHSHAL
	(JUMP-NOT-EQUAL M-E A-ZERO XFSHA1)	;Jump if %FIND-STRUCTURE-LEADER
	((M-TEM) (LISP-BYTE %%ARRAY-LEADER-LENGTH) READ-MEMORY-DATA)
	(POPJ-AFTER-NEXT (M-A) ADD M-A A-TEM)	;OFFSET FROM LEADER TO HEADER
       ((M-T) Q-POINTER M-A (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-ARRAY-POINTER)))

;;; Given the address of the base of a structure, return information on its size.
;;; Note that if given the address of an array header, the leader (if any) is
;;; not counted, but if given the address of the leader, the leader is
;;; counted.  I.e. nothing before the given address is counted.
;;; In the case of an RPLACD-forwarded list, the 2 words pointed to by the
;;; forwarding-pointer are counted, and the forwarding-pointer itself isn't.
;;; Inputs:  address in MD
;;; Outputs: M-3 number of boxed Q's, M-4 number of unboxed Q's following those,
;;;	     A-SINF-PAD number of those Q's which need not be copied (pdl's only).
;;;	     A-SINF-PDL-BASE usually 0, else pointer to base of structure.
;;;		The scavenger, in its finite wisdom, uses this.
;;;		The value of this is garbage if not called from the scavenger.
;;;	     M-K map data, mainly for representation type
;;;	     M-K<31> = 1 if this is a list which ends in an rplacd-forwarding
;;; Clobbers: M-A, M-B, M-T, usual page-fault things.
;;; The type field of VMA is zero throughout this section.
;;; This routine MAY NOT call the transporter, since it is invoked by the
;;; transporter.  Otherwise the transporter's variables and flag could be
;;; clobbered, and the possibility of micro-stack overflow would arise.
;;; Note that an illegal pointer to oldspace can be left in the VMA.

;;; This entry saves M-A, M-B, M-T for the scavenger and sets A-SCAV-COUNT, A-SCAV-SKIP
SCAV-STRUCTURE-INFO
	((A-SCAV-SAVE-A) M-A)	;Shouldn't use pdl buffer since may be computing pdl size
	((A-SCAV-SAVE-B) M-B)
	((A-SCAV-SAVE-T) M-T)
	((A-SCAV-PDL-BASE) Q-POINTER MD)	;Could get moved into A-SINF-PDL-BASE
	(CALL-XCT-NEXT STRUCTURE-INFO)
       ((A-SINF-PDL-BASE) (A-CONSTANT 0))
	((A-SCAV-COUNT) SUB M-3 A-SINF-PAD)
	((A-SCAV-SKIP) ADD M-4 A-SINF-PAD)
	((M-T) A-SCAV-SAVE-T)
	(POPJ-AFTER-NEXT (M-B) A-SCAV-SAVE-B)
       ((M-A) A-SCAV-SAVE-A)

STRUCTURE-INFO
	(DISPATCH L2-MAP-STATUS-CODE D-GET-MAP-BITS) ;Ensure validity of meta bits
;	((M-K) MAP-SECOND-LEVEL-MAP MEMORY-MAP-DATA)	;FOR DISPATCH BELOW, AND
	;; quux revision 14 (appendix a14.5): map(md)'s <29:0>, the page entry
	((m-k) map-entry memory-map-data)	;for dispatch below, and
						; RETURNED TO CALLER.  NOTE 0 IN SIGN BIT.
	((VMA-START-READ) Q-POINTER MD)		;FETCH FIRST WORD
	(CHECK-PAGE-READ)
	((M-3) (A-CONSTANT 0))			;INITIALIZE RETURN VALUES
	((A-SINF-PAD) (A-CONSTANT 0))
	(DISPATCH-XCT-NEXT (LISP-BYTE %%REGION-REPRESENTATION-TYPE) M-K D-SINF)
       ((M-4) (A-CONSTANT 0))

(LOCALITY D-MEM)
(START-DISPATCH 2 0)
D-SINF	(SINFL)					;0 LIST
	(SINFS)					;1 STRUCTURE
	(P-BIT INHIBIT-XCT-NEXT-BIT ILLOP)	;2 NOT USED
	(P-BIT INHIBIT-XCT-NEXT-BIT ILLOP)	;3 NOT USED
(END-DISPATCH)

(START-DISPATCH 2 0)
D-SINFL	(SINFL0)				;0 CDR-NORMAL
	(INHIBIT-XCT-NEXT-BIT R-BIT)		;1 CDR-ERROR
	(INHIBIT-XCT-NEXT-BIT R-BIT)		;2 CDR-NIL
	(SINFL0)				;3 CDR-NEXT
(END-DISPATCH)

(LOCALITY I-MEM)

;STRUCTURE-INFO in list space.  First word has been read, zero in M-3, M-4, A-SINF-PAD.
;There are no unboxed or pad Q's.  Scan forward through memory counting boxed Q's
;May clobber only M-3 and usual page-fault things, due to other callers.
SINFL0	(CHECK-PAGE-READ)
SINFL	((M-3) ADD M-3 (A-CONSTANT 1))		;Count this Q as part of structure
	((M-TEM) Q-DATA-TYPE READ-MEMORY-DATA)	;Forward ends list, but counts as 2 Q's!
	(JUMP-EQUAL M-TEM (A-CONSTANT (EVAL DTP-HEADER-FORWARD)) SINFL2)
	(DISPATCH Q-CDR-CODE READ-MEMORY-DATA D-SINFL) ;Check cdr code, loop if NEXT or NORMAL
       ((VMA-START-READ) ADD VMA (A-CONSTANT 1))

SINFL2	((M-K) DPB (M-CONSTANT -1) (BYTE-FIELD 1 31.) A-K) ;Set sign of M-K
SINFL1	(POPJ-AFTER-NEXT (M-3) ADD M-3 (A-CONSTANT 1))
       (NO-OP)

;STRUCTURE-INFO in structure space.  First word has been read, zero in M-3, M-4, A-SINF-PAD.
SINFS	(DISPATCH Q-DATA-TYPE READ-MEMORY-DATA D-SINFS)
       ((M-3) (A-CONSTANT 5))			;Symbol is easy, make it fast case

(LOCALITY D-MEM)
;(START-DISPATCH 5 0)
;; quux revision 13 (contract g2 2.4): the data type is one bit wider, 6-bit types
(start-dispatch 6 0)
D-SINFS	(P-BIT INHIBIT-XCT-NEXT-BIT ILLOP)	;TRAP
	(P-BIT INHIBIT-XCT-NEXT-BIT ILLOP)	;NULL
	(P-BIT INHIBIT-XCT-NEXT-BIT ILLOP)	;FREE
	(P-BIT INHIBIT-XCT-NEXT-BIT ILLOP)	;SYMBOL
	(R-BIT)					;SYMBOL-HEADER
	(P-BIT INHIBIT-XCT-NEXT-BIT ILLOP)	;FIX
	(P-BIT INHIBIT-XCT-NEXT-BIT ILLOP)	;EXTENDED-NUMBER
	(INHIBIT-XCT-NEXT-BIT SINFSH)		;HEADER
	(P-BIT INHIBIT-XCT-NEXT-BIT ILLOP)	;GC-FORWARD
	(P-BIT INHIBIT-XCT-NEXT-BIT ILLOP)	;EXTERNAL-VALUE-CELL-POINTER
	(P-BIT INHIBIT-XCT-NEXT-BIT ILLOP)	;ONE-Q-FORWARD
	(INHIBIT-XCT-NEXT-BIT SINFS-HFWD)	;HEADER-FORWARD
	(INHIBIT-XCT-NEXT-BIT SINFS-BFWD)	;BODY-FORWARD
	(P-BIT INHIBIT-XCT-NEXT-BIT ILLOP)	;LOCATIVE
	(P-BIT INHIBIT-XCT-NEXT-BIT ILLOP)	;LIST
	(P-BIT INHIBIT-XCT-NEXT-BIT ILLOP)	;U CODE ENTRY
	(P-BIT INHIBIT-XCT-NEXT-BIT ILLOP)	;FEF
	(P-BIT INHIBIT-XCT-NEXT-BIT ILLOP)	;ARRAY-POINTER
	(INHIBIT-XCT-NEXT-BIT SINFSA)		;ARRAY-HEADER
	(P-BIT INHIBIT-XCT-NEXT-BIT ILLOP)	;STACK-GROUP
	(P-BIT INHIBIT-XCT-NEXT-BIT ILLOP)	;CLOSURE
	(P-BIT INHIBIT-XCT-NEXT-BIT ILLOP)	;SMALL-FLONUM 
	(P-BIT INHIBIT-XCT-NEXT-BIT ILLOP)	;SELECT-METHOD
	(P-BIT INHIBIT-XCT-NEXT-BIT ILLOP)	;INSTANCE
	(INHIBIT-XCT-NEXT-BIT SINFSI)		;INSTANCE-HEADER
	(P-BIT INHIBIT-XCT-NEXT-BIT ILLOP)	;ENTITY
	(P-BIT INHIBIT-XCT-NEXT-BIT ILLOP)	;STACK-CLOSURE
	(P-BIT INHIBIT-XCT-NEXT-BIT ILLOP)	;SELF-REF-POINTER
	(P-BIT INHIBIT-XCT-NEXT-BIT ILLOP)	;CHARACTER
 (REPEAT NQZUSD (P-BIT INHIBIT-XCT-NEXT-BIT ILLOP))
(END-DISPATCH)
(LOCALITY I-MEM)

;DTP-BODY-FORWARD - find DTP-HEADER-FORWARD, count boxed Q's between
SINFS-BFWD
	((M-TEM) Q-POINTER READ-MEMORY-DATA)	;Address of header
	((M-TEM) SUB VMA A-TEM)			;- # Q's between here and there
	(CALL-GREATER-OR-EQUAL M-TEM A-ZERO ILLOP)
	((M-3) SUB M-3 A-TEM)			;Account for them, drop into header case
	((VMA) Q-POINTER READ-MEMORY-DATA)
;DTP-HEADER-FORWARD - include all DTP-BODY-FORWARD's that point here as unboxed Q's
SINFS-HFWD
	(CALL-XCT-NEXT XRGN1)			;M-T gets region number
       ((M-A) Q-POINTER VMA (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	((VMA-START-READ) ADD M-T A-V-REGION-ORIGIN)
	(CHECK-PAGE-READ)
	((M-3) ADD M-3 (A-CONSTANT 1))		;1 boxed Q for the header
	((M-B) SUB READ-MEMORY-DATA (A-CONSTANT 1))
	((VMA-START-READ) ADD M-T A-V-REGION-FREE-POINTER)
	(CHECK-PAGE-READ)
	((M-A) Q-POINTER M-A (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-BODY-FORWARD)))
	((M-B) ADD READ-MEMORY-DATA A-B)
	((M-B) Q-POINTER M-B)			;Last valid address in region
	((VMA) Q-POINTER M-A)			;Address of header
SINFS-HFWD-0
;	(POPJ-GREATER-OR-EQUAL VMA A-B)		;Ran off top of region
	(popj-greater-or-equal-unsigned vma a-b)		;Ran off top of region	;quux revision 14: unsigned (contract g3 revision 14, 10.1)
	((VMA-START-READ) ADD VMA (A-CONSTANT 1))
	(CHECK-PAGE-READ)
	((M-TEM) Q-TYPED-POINTER READ-MEMORY-DATA)
	(JUMP-EQUAL-XCT-NEXT M-TEM A-A SINFS-HFWD-0) ;This word part of this forwarded struc
       ((M-4) ADD M-4 (A-CONSTANT 1))		;So count it and keep looping
	(POPJ-AFTER-NEXT (M-4) SUB M-4 (A-CONSTANT 1))	;Counted an extra time
       (NO-OP)

;Given a read cycle on a location which could be in oldspace,
;this subroutine substitutes for the transporter by checking for a GC-forward.
;Bashes M-TEM
SINF-TRANS
	(CHECK-PAGE-READ)
	((M-TEM) Q-DATA-TYPE READ-MEMORY-DATA)
	(POPJ-NOT-EQUAL M-TEM (A-CONSTANT (EVAL DTP-GC-FORWARD)))
	(JUMP-XCT-NEXT SINF-TRANS)
       ((VMA-START-READ) MD)

;DTP-INSTANCE-HEADER - get size from instance-descriptor
SINFSI	(CALL-XCT-NEXT SINF-TRANS)
       ((VMA-START-READ) ADD READ-MEMORY-DATA
		(A-CONSTANT (EVAL %INSTANCE-DESCRIPTOR-SIZE)))
	(POPJ-XCT-NEXT)
       ((M-3) Q-POINTER READ-MEMORY-DATA)

;DTP-HEADER - dispatch on subtype.  MD contains the header word.
;M-3 and M-4 should be zero when we get here;
;on return, they are set to the number of boxed and unboxed Qs.
;Note: EXTRA-PDL-TRAP calls here.
SINFSH	(DISPATCH (LISP-BYTE %%HEADER-TYPE-FIELD) READ-MEMORY-DATA D-SINFSH)

(LOCALITY D-MEM)
(START-DISPATCH 5 INHIBIT-XCT-NEXT-BIT)	;DISPATCH ON HEADER SUBTYPE
D-SINFSH(P-BIT ILLOP)	;%HEADER-TYPE-ERROR
	(SINF-FEF)	;%HEADER-TYPE-FEF
	(SINF-AL)	;%HEADER-TYPE-ARRAY-LEADER
	(P-BIT ILLOP)	;unused
	(SINF-FLO)	;%HEADER-TYPE-FLONUM
	(SINF-BRAT)	;%HEADER-TYPE-COMPLEX
	(SINF-BIG)	;%HEADER-TYPE-BIGNUM
	(SINF-BRAT)	;%HEADER-TYPE-RATIONAL
	(P-BIT ILLOP)	;unused
	(P-BIT ILLOP)	;unused
	(P-BIT ILLOP)	;unused
	(P-BIT ILLOP)	;unused
(REPEAT NHDUSD (P-BIT ILLOP))
(END-DISPATCH)
(LOCALITY I-MEM)

SINF-FLO
	(POPJ-AFTER-NEXT (M-4) (A-CONSTANT 2))	;2 unboxed Q's
       (NO-OP)	

SINF-BRAT
	(POPJ-AFTER-NEXT (M-3) (A-CONSTANT 3))	;Headers and two number pointers.
       (NO-OP)
		
SINF-BIG
	(POPJ-AFTER-NEXT
	 (M-4) BIGNUM-HEADER-LENGTH READ-MEMORY-DATA)
       ((M-4) ADD M-4 (A-CONSTANT 1))

SINF-FEF
	((M-3) (LISP-BYTE %%FEFH-PC-IN-WORDS) READ-MEMORY-DATA)	;Number of boxed words
	((VMA-START-READ) ADD VMA (A-CONSTANT (EVAL %FEFHI-STORAGE-LENGTH)))
	(CHECK-PAGE-READ)
	(POPJ-AFTER-NEXT (M-4) Q-POINTER READ-MEMORY-DATA)	;Total number of words
       ((M-4) SUB M-4 A-3)			;Number of unboxed words

SINF-AL	((M-3) (LISP-BYTE %%ARRAY-LEADER-LENGTH) READ-MEMORY-DATA)  ;Add in size of leader
	((VMA-START-READ) ADD VMA A-3)		;Reference header
	(CHECK-PAGE-READ)			;And drop into SINFSA

;DTP-ARRAY-HEADER - get info on array, depending on array-type
SINFSA	((M-A) Q-POINTER READ-MEMORY-DATA)	;Copy the array header
	((M-T) (LISP-BYTE %%ARRAY-NUMBER-DIMENSIONS) M-A)
	((M-B) (LISP-BYTE %%ARRAY-INDEX-LENGTH-IF-SHORT) M-A)
	(JUMP-IF-BIT-CLEAR (LISP-BYTE %%ARRAY-LONG-LENGTH-FLAG) M-A SINFSA1)
	((VMA-START-READ) ADD VMA (A-CONSTANT 1))
	(CHECK-PAGE-READ)	
	((M-T) ADD M-T (A-CONSTANT 1))
	((M-B) Q-POINTER READ-MEMORY-DATA)	;Long index length
	((VMA) SUB VMA (A-CONSTANT 1))
SINFSA1	;; M-T # header words, M-B index length, VMA address of header, M-A header
	(JUMP-IF-BIT-SET-XCT-NEXT (LISP-BYTE %%ARRAY-DISPLACED-BIT) M-A SINFSA-DISPLACED)
       ((M-3) ADD M-3 A-T)			;Count array header, dimension words as boxed
	(DISPATCH (LISP-BYTE %%ARRAY-TYPE-FIELD) M-A D-SINFSA)
       ((M-3) ADD M-3 A-B)			;POPJ-XCT-NEXT if Q-type array

SINFSA-DISPLACED
	(POPJ-AFTER-NEXT (M-3) ADD M-3 A-B)	;Displaced array, pretend type is Q
       (NO-OP)

SINFSA-1B
	(POPJ-AFTER-NEXT (M-B) ADD M-B (A-CONSTANT 37))
       ((M-4) (BYTE-FIELD (DIFFERENCE Q-POINTER-WIDTH 5) 5) M-B)

SINFSA-2B
	(POPJ-AFTER-NEXT (M-B) ADD M-B (A-CONSTANT 17))
       ((M-4) (BYTE-FIELD (DIFFERENCE Q-POINTER-WIDTH 4) 4) M-B)

SINFSA-4B
	(POPJ-AFTER-NEXT (M-B) ADD M-B (A-CONSTANT 7))
       ((M-4) (BYTE-FIELD (DIFFERENCE Q-POINTER-WIDTH 3) 3) M-B)

SINFSA-8B
	(POPJ-AFTER-NEXT (M-B) ADD M-B (A-CONSTANT 3))
       ((M-4) (BYTE-FIELD (DIFFERENCE Q-POINTER-WIDTH 2) 2) M-B)

SINFSA-16B
	(POPJ-AFTER-NEXT (M-B) ADD M-B (A-CONSTANT 1))
       ((M-4) (BYTE-FIELD (DIFFERENCE Q-POINTER-WIDTH 1) 1) M-B)

SINFSA-32B
	(POPJ-AFTER-NEXT NO-OP)
       ((M-4) M-B)

SINFSA-CPLXFL ;art-complex-float is four words per element.
	(POPJ-AFTER-NEXT
	 (M-4) ADD M-B A-B)
       ((M-4) ADD M-4 A-4)

SINFSA-CPLX  ;art-complex is two BOXED words per element.
	(POPJ-AFTER-NEXT	;Add to the number of boxed words
	 (M-3) ADD M-3 A-B)	;twice the number of elements.
       ((M-3) ADD M-3 A-B)

SINFSA-CPLX-FPSFL ;ART-COMPLEX-FPS-FLOAT is two unboxed words per element.
SINFSA-FLOAT
	(POPJ-AFTER-NEXT	;Add to the number of unboxed words
	 (M-4) ADD M-4 A-B)	;twice the number of elements.
       ((M-4) ADD M-4 A-B)

;;; PDL's have the magic feature that stuff after the pdl pointer is not looked at
;;; Element 0 of a pdl's array leader is its stack group
;;; We have already counted whole size of pdl into M-3, still have to get A-SINF-PAD.
SINF-REGPDL
	(JUMP-XCT-NEXT SINF-PDL)
       ((M-A) (A-CONSTANT (EVAL (+ 2 SG-REGULAR-PDL-POINTER))))

SINF-BNDPDL
	((M-A) (A-CONSTANT (EVAL (+ 2 SG-SPECIAL-PDL-POINTER))))
SINF-PDL
	((VMA-START-READ) SUB VMA (A-CONSTANT 2))	;Get stack-group which owns pdl
	(CHECK-PAGE-READ)
	((A-SINF-PDL-BASE) A-SCAV-PDL-BASE)	;Remember that this is a pdl
	(CALL-XCT-NEXT SINF-TRANS)		;That might have been an oldspace ptr, so
       ((VMA-START-READ) MD)			; check header of stack-group for gc-fwd
	((M-TEM) Q-TYPED-POINTER VMA)		;Owning stack group
	(JUMP-EQUAL M-TEM A-QCSTKG SINF-OWN-PDL) ;Currently running, ptr in different place
SINF-NOT-OWN-PDL
	((VMA-START-READ) SUB VMA A-A)		;Get appropriate pdl pointer out of sg
	(CHECK-PAGE-READ)
	;; This looks like it could be bummed, but note that pdl-ptrs can be -1
	((M-TEM) ADD READ-MEMORY-DATA (A-CONSTANT 1))	;Index of lowest invalid location
	(POPJ-AFTER-NEXT 
	 (M-TEM) Q-POINTER M-TEM)		;Clear carry
       ((A-SINF-PAD) SUB M-B A-TEM)		;Rest of array is to be skipped

SINF-OWN-PDL
	;; If in middle of switching stack groups, pdl pointers in machine are not valid.
	;; We must have been called from the transporter, and this must be the sg we're
	;; switching to, since the one we're switching from cannot be in oldspace.
	(JUMP-IF-BIT-SET M-STACK-GROUP-SWITCH-FLAG SINF-NOT-OWN-PDL)
	;; If not switching stack groups, and this is the current stack group,
	;; use the pdl pointers in the machine rather than those in memory.
	(JUMP-EQUAL M-A (A-CONSTANT (EVAL (+ 2 SG-SPECIAL-PDL-POINTER))) SINF-OWN-BND-PDL)
	((PDL-BUFFER-INDEX) SUB PDL-BUFFER-POINTER A-PDL-BUFFER-HEAD) ;mod-2000 arithmetic
	((M-TEM) ADD PDL-BUFFER-INDEX A-PDL-BUFFER-VIRTUAL-ADDRESS)
	(POPJ-AFTER-NEXT (M-TEM) SUB M-TEM A-QLPDLO)	;relative pdl ptr
       ((A-SINF-PAD) M-A-1 M-B A-TEM)		;Rest of array is to be skipped

SINF-OWN-BND-PDL
	((M-TEM) A-QLBNDP)
	(POPJ-AFTER-NEXT (M-TEM) SUB M-TEM A-QLBNDO)	;relative pdl ptr
       ((A-SINF-PAD) M-A-1 M-B A-TEM)		;Rest of array is to be skipped

(LOCALITY D-MEM)
(START-DISPATCH 5 0)
D-SINFSA
	(P-BIT INHIBIT-XCT-NEXT-BIT ILLOP)	;ARRAY TYPE 0 NOT USED
	(INHIBIT-XCT-NEXT-BIT SINFSA-1B)	;BIT ARRAY
	(INHIBIT-XCT-NEXT-BIT SINFSA-2B)	;2 BIT ARRAY
	(INHIBIT-XCT-NEXT-BIT SINFSA-4B)	;4 BIT ARRAY
	(INHIBIT-XCT-NEXT-BIT SINFSA-8B)	;8 BIT ARRAY
	(INHIBIT-XCT-NEXT-BIT SINFSA-16B)	;16 BIT ARRAY
	(INHIBIT-XCT-NEXT-BIT SINFSA-32B)	;32 BIT ARRAY
	(R-BIT)					;Q ARRAY
	(R-BIT)					;LIST Q ARRAY
	(INHIBIT-XCT-NEXT-BIT SINFSA-8B)	;STRING ARRAY
	(R-BIT)					;STACK-GROUP HEAD
	(SINF-BNDPDL)				;BINDING-PDL
	(INHIBIT-XCT-NEXT-BIT SINFSA-16B)	;HALF-FIX
	(SINF-REGPDL)				;REG-PDL
;	(INHIBIT-XCT-NEXT-BIT SINFSA-FLOAT)	;FLOAT
	(inhibit-xct-next-bit sinfsa-32b)	;float: quux revision 13, a single a word
	(INHIBIT-XCT-NEXT-BIT SINFSA-32B)	;FPS-FLOAT
	(INHIBIT-XCT-NEXT-BIT SINFSA-16B)	;FAT-STRING
;	(INHIBIT-XCT-NEXT-BIT SINFSA-CPLXFL)	;COMPLEX-FLOAT
	(inhibit-xct-next-bit sinfsa-float)	;complex-float: quux revision 13, two singles
	(INHIBIT-XCT-NEXT-BIT SINFSA-CPLX)	;COMPLEX
	(INHIBIT-XCT-NEXT-BIT SINFSA-CPLX-FPSFL)	;COMPLEX-FPS-FLOAT
 (REPEAT NATUSD (P-BIT INHIBIT-XCT-NEXT-BIT ILLOP))
(END-DISPATCH)
(LOCALITY I-MEM)

;;; These are macrocode interfaces to STRUCTURE-INFO
XSBOXSZ (MISC-INST-ENTRY %STRUCTURE-BOXED-SIZE)
	(CALL XFSL)				;Fix bug if given an array with a leader
	(CALL-XCT-NEXT STRUCTURE-INFO)
       ((MD) Q-POINTER M-T)
	((VMA) SETZ)				;Clear possible garbage in VMA
	(POPJ-AFTER-NEXT (M-3) SUB M-3 A-SINF-PAD) ;Don't count garbage off end of pdl as boxed
       ((M-T) Q-POINTER M-3 (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))

XSTOTSZ (MISC-INST-ENTRY %STRUCTURE-TOTAL-SIZE)
	(CALL XFSL)				;Fix bug if given an array with a leader
	(CALL-XCT-NEXT STRUCTURE-INFO)
       ((MD) Q-POINTER M-T)
	((VMA) SETZ)				;Clear possible garbage in VMA
	(POPJ-AFTER-NEXT (M-3) ADD M-3 A-4)
       ((M-T) Q-POINTER M-3 (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))

;;; FLIPPER

;%GC-FLIP region.  Flips specified region, converting newspace to oldspace.
; Then goes over everything in the machine and makes sure it
; doesn't point to old-space.  If the region is T, all newspace and copyspace regions
; are done.
; Usually reclaim oldspace at some point before calling this function.
; To do a list of areas, just apply this to their regions one at a time, paying
; the penalty of extra checking of stuff in the machine for old-space-ptr;
; this is necessary due to problems with transporting of a list argument
; to this function, and anyway makes the microcode simpler.
XFLIP (MISC-INST-ENTRY %GC-FLIP)
	((A-GC-FLIP-READY) A-V-NIL)		;Due to creation of new old-space regions
	((A-CONS-WORK-DONE) SETZ)		;Reset work counters and make them equal
	((A-SCAV-WORK-DONE) SETZ)
	((A-TV-CURRENT-SHEET) A-V-NIL)		;Must recompute sheet data
	((A-SCONS-CACHE-AREA) SETZ)		;Clear cache
	((A-LCONS-CACHE-AREA) SETZ)		;Clear cache
	;; the generational collector (contract g3 step 2, 4.1, 4.2, 7): every flip
	;; clears the words consed since the last; the marked-page walk is for a
	;; young collection only, so it is disarmed here and a young flip arms it.
	((a-gc-words-consed-since-flip) (a-constant (byte-value q-data-type dtp-fix)))
	((a-scav-walk-armed) a-zero)
	((a-scav-region-dirty) (a-constant 1))
	((M-K) Q-TYPED-POINTER C-PDL-BUFFER-POINTER-POP) ;Region spec
	;; (%gc-flip -1) is a young flip (contract g3 step 2, 4.2; clarification 3):
	;; each region whose generation is not tenured (eden, survivor space 1 and
	;; 2) and whose space is new or copy becomes oldspace; (%gc-flip t), a
	;; tenured one, flips every new and copy region, as before.
	(jump-equal m-k (a-constant (plus (byte-value q-data-type dtp-fix) 37777777777)) xflip-young)
	((M-TEM) Q-DATA-TYPE M-K)
	(JUMP-EQUAL M-TEM (A-CONSTANT (EVAL DTP-FIX)) XFLIP4) ;Single region
	;Do all areas.  We do this by looking through the region-tables
	;for new-space and copy-space, since all REGION-BITS slots are guaranteed filled-in,
	;while the area tables are less structured.
	((M-K) (A-CONSTANT (EVAL SIZE-OF-AREA-ARRAYS)))
XFLIP1	((VMA-START-READ) ADD M-K A-V-REGION-BITS)
	(CHECK-PAGE-READ)
	((M-TEM) (LISP-BYTE %%REGION-SPACE-TYPE) READ-MEMORY-DATA)
	(JUMP-EQUAL M-TEM (A-CONSTANT (EVAL %REGION-SPACE-NEW)) XFLIP3)
	(JUMP-EQUAL M-TEM (A-CONSTANT (EVAL %REGION-SPACE-COPY)) XFLIP3)
XFLIP2	(JUMP-GREATER-THAN-XCT-NEXT M-K A-ZERO XFLIP1)
       ((M-K) SUB M-K (A-CONSTANT 1))
;Having done the flipping, now get rid of all pointers to old-space in the machine.
;"The machine" is M-ZR through M-K, A-VERSION through A-END-Q-POINTERS, pdl buffer,
;A-PDL-BUFFER-VIRTUAL-ADDRESS, A-QLBNDO, etc.
;In order to avoid bugs with storing GC-FORWARDING pointers into the pdl buffer
;and the like, we use the stack-group-switch mechanism to save the state of the machine
;then load it back with transporting.
XFLIPW	(CALL-XCT-NEXT SGLV)		;Save state, don't swap variables
       ((M-TEM) DPB (M-CONSTANT -1) (BYTE-FIELD 1 6) A-SG-STATE)
;Now transport the magic A-memory variables, which constitute the root of the world.
;	((VMA) (A-CONSTANT (EVAL (+ 400 %SYS-COM-TEMPORARY)))) ;Pretend was read from here
	;; 1024-word pages (contract g2, option (w); appendix a1.9): the system
	;; communication area is at 2000, a page of its own, not 400
	((vma) (a-constant (eval (+ 2000 %sys-com-temporary)))) ;pretend was read from here
	((M-E) (A-CONSTANT (A-MEM-LOC A-VERSION)))
XFLIPW2	((OA-REG-HIGH) DPB M-E OAH-A-SRC A-ZERO)
	((MD) A-GARBAGE oa-high-select)		;A-GARBAGE IS LOCATION 0@A
	;the oa-high-select above reads oa-reg-high (rev 15)
	(DISPATCH TRANSPORT-AC MD)
	((OA-REG-LOW) DPB M-E OAL-A-DEST A-ZERO)
	((A-GARBAGE) MD oa-low-select)	;reads oa-reg-low (rev 15)
	(JUMP-NOT-EQUAL-XCT-NEXT M-E (A-CONSTANT (A-MEM-LOC A-END-Q-POINTERS)) XFLIPW2)
       ((M-E) ADD M-E (A-CONSTANT 1))
;Now restore the stack-group, which got copied back there someplace.
	(CALL SGENT)			;Restore state
	(POPJ-AFTER-NEXT (A-SG-STATE)	;Leave A-SG-STATE unchanged
		DPB M-TEM (LISP-BYTE %%SG-ST-CURRENT-STATE) A-SG-STATE)
       ((M-T) A-V-NIL)

XFLIP3	(JUMP-XCT-NEXT XFLIP2)
       (CALL XFLIP5)

;; the young flip (contract g3 step 2, 4.2): the regions of eden and both
;; survivor spaces, new or copy, become oldspace (xflip5; update-region-pht
;; keeps each entry's <19:18>); the marked-page walk is armed, its roots
;; beyond the machine's state; then xflipw transports the machine's state as
;; for any flip.
xflip-young
	((m-k) (a-constant (eval size-of-area-arrays)))
xflip-young-1
	((vma-start-read) add m-k a-v-region-bits)
	(check-page-read)
	((m-tem) region-generation read-memory-data)
	(jump-equal m-tem (a-constant region-generation-tenured) xflip-young-2)
	((m-tem) (lisp-byte %%region-space-type) read-memory-data)
	(jump-equal m-tem (a-constant (eval %region-space-new)) xflip-young-3)
	(jump-equal m-tem (a-constant (eval %region-space-copy)) xflip-young-3)
xflip-young-2
	(jump-greater-than-xct-next m-k a-zero xflip-young-1)
       ((m-k) sub m-k (a-constant 1))
	(call scav-walk-arm)
	(jump xflipw)
xflip-young-3
	(jump-xct-next xflip-young-2)
       (call xflip5)

XFLIP4	((MICRO-STACK-DATA-PUSH) (A-CONSTANT (I-MEM-LOC XFLIPW)))
	((VMA-START-READ) ADD M-K A-V-REGION-BITS)
	(CHECK-PAGE-READ)
XFLIP5	((M-TEM) (A-CONSTANT (EVAL %REGION-SPACE-OLD)))	;Change to oldspace, clear meta bit,
	((A-TEM1) ANDCA MD				; and clear scavenge-enable
		(A-CONSTANT (PLUS (BYTE-MASK %%REGION-OLDSPACE-META-BIT)
				  (BYTE-MASK %%REGION-SCAVENGE-ENABLE))))
	((WRITE-MEMORY-DATA-START-WRITE) DPB M-TEM (LISP-BYTE %%REGION-SPACE-TYPE) A-TEM1)
	(CHECK-PAGE-WRITE)
	(JUMP-XCT-NEXT UPDATE-REGION-PHT)	;Fix map, page table
       ((M-D) A-V-NIL)				;Don't change swap-status


;; Takes a pointer to a block of words to free up in M-1, the number of words in M-2.
;; This only works for structure space.
;; Smashes M-A,M-B,M-E,M-TEM,M-2. M-1 preserved. NO SEQUENCE BREAKS TAKEN.

UN-CONS	(POPJ-EQUAL M-2 A-ZERO)
	((C-PDL-BUFFER-POINTER-PUSH) M-T)	;Protect M-T through this routine
	(CALL-XCT-NEXT XRGN1)			;Get region number from M-1 in M-T
       ((M-A) Q-POINTER M-1 (A-CONSTANT (BYTE-VALUE Q-DATA-TYPE DTP-FIX)))
	((M-T) Q-POINTER M-T)
	(JUMP-NOT-EQUAL M-T A-SCAV-REGION UN-CONS-0)
	((A-SCAV-COUNT) (A-CONSTANT 0))		;Make scavenger forget this region
UN-CONS-0
	((VMA-START-READ) ADD M-T A-V-REGION-ORIGIN)
	(CHECK-PAGE-READ)
	((M-E) ADD M-A A-2)			;M-E gets where free pointer should be
	((M-A) MD)				;M-A gets region origin
	((VMA-START-READ) ADD M-T A-V-REGION-FREE-POINTER)
	(CHECK-PAGE-READ)
	((M-E) Q-POINTER M-E)
	((M-TEM) ADD MD A-A)			;M-TEM gets actual free pointer
	((M-TEM) Q-POINTER M-TEM)
	(JUMP-NOT-EQUAL M-TEM A-E UN-CONS-FILL)	;Something else got allocated, don't mess
	((MD-START-WRITE) SUB MD A-2)		;Decrement free pointer.
	(CHECK-PAGE-WRITE)
	;; quux revision 14 (contract g3 revision 14, 10.1): the
	;; scavenger's pointer, read below, is relative to the region's origin, as
	;; the free pointer is, but m-e is the object's end as an address.  the
	;; signed compare of the two never backed the pointer up below 2^31 (an
	;; address is larger than any offset), and from 2^31 up (an ephemeral
	;; region) it always did, writing the address into region-gc-pointer.
	;; m-e is now the free pointer just written, relative, which the pointer
	;; is backed up to when it lies above it.
	((m-e) q-pointer md)
	(JUMP-NOT-EQUAL M-T A-SCONS-CACHE-REGION UN-CONS-1)	;Fix free ptr in cache, too
	((A-SCONS-CACHE-FREE-POINTER) ADD MD A-SCONS-CACHE-REGION-ORIGIN)
	;; the generational collector (contract g3 step 2, 6.2): the cache's limit
	;; stays at the end of the page the old free pointer was in, so with the
	;; free pointer moved back across a page boundary the fast path could cons
	;; across it without consf, which writes the first-object table's entries:
	;; in a region with a table the cache is cleared.  a region without one
	;; (the extra pdl's, where bignums are given back) keeps its cache.
	((vma-start-read) add m-t a-v-region-bits)
	(check-page-read)
	(call first-object-table-p)
	(jump-equal m-tem a-zero un-cons-1)
	((a-scons-cache-area) setz)
UN-CONS-1
	((VMA-START-READ) ADD M-T A-V-REGION-GC-POINTER)	;back up scav pointer if necc
	(CHECK-PAGE-READ)
	((M-TEM) SUB M-ZERO A-2)		;Undo cons-work-done
	((A-CONS-WORK-DONE) ADD M-TEM A-CONS-WORK-DONE)
	((M-TEM) Q-POINTER READ-MEMORY-DATA)
	(POPJ-LESS-OR-EQUAL-XCT-NEXT M-TEM A-E)
       ((M-T) C-PDL-BUFFER-POINTER-POP)		;Restore M-T
	((MD-START-WRITE) SELECTIVE-DEPOSIT MD Q-ALL-BUT-POINTER A-E)
	(CHECK-PAGE-WRITE)
	(POPJ)	;NO POPJ-AFTER-NEXT, BADD4 CAN JUMP HERE, THEN WE RETURN TO MAIN LOOP

UN-CONS-FILL
	((M-2) SUB M-2 (A-CONSTANT 1))		;M-2 gets length of array to fill with
	(CALL-GREATER-THAN M-2 (A-CONSTANT (EVAL %ARRAY-MAX-SHORT-INDEX-LENGTH)) ILLOP)
;	((MD) ADD M-2 (A-CONSTANT (PLUS (BYTE-VALUE Q-DATA-TYPE DTP-ARRAY-HEADER)
;					(BYTE-VALUE %%ARRAY-NUMBER-DIMENSIONS 1)
;					(EVAL ART-32B))))
;; quux revision 13 (contract g2 2.2): an arithmetic result takes m's tag,
;; and m-2, the length, has none: ior, a logical function, takes the tag from
;; the constant; the length is below the header's other fields, so ior is the add.
	((md) ior m-2 (a-constant (plus (byte-value q-data-type dtp-array-header)
					(byte-value %%array-number-dimensions 1)
					(eval art-32b))))
	((VMA-START-WRITE) M-1)		;NO POPJ-AFTER-NEXT, SEE ABOVE
	(CHECK-PAGE-WRITE)
	(POPJ-AFTER-NEXT (M-T) C-PDL-BUFFER-POINTER-POP)	;RESTORE IT.
       (NO-OP)
))
