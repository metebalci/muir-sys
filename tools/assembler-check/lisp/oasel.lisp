;-*- Mode:LISP; Package:MICRO-ASSEMBLER; Base:8 -*-

;; tools/assembler-check's oa select fixture (contract g3 revision 15,
;; appendix a15b.15; README.md, check oa-select): small programs in revision
;; 15's names, each assembled on its own with ua:assemble at revision 15.  the
;; runner makes one file of each variant below, oa-NAME.lisp, the common part
;; followed by the variant, in the shape the micro-assembler's fast reader
;; reads, (setq oa-NAME '(...)).  control uses every select correctly and must
;; pass the oa select check; each other variant holds one breach the check
;; must refuse.  never part of the microcode.

;;; common
(locality m-mem)
m-garbage	(0)
m-a		(0)
m-b		(0)
(locality a-mem)
a-garbage	(0)
a-hunoz		(0)
a-b		(0)
(loc 40)
(locality i-mem)
oa-start	((m-a) setz)

;;; variant control
(locality d-mem)
(start-dispatch 1 0)
oa-table	;both entries jump, neither with n
	(oa-dt-0)
	(oa-dt-1)
(end-dispatch)
(locality i-mem)
;; a write, and its select falling through
	((oa-reg-low) m-a)
	((m-b) m-a oa-low-select)
;; a write in a jump's slot (no n), its select at the jump's target
	(jump-xct-next oa-c1)
	((oa-reg-high) m-a)
oa-c0	(jump oa-c0)
oa-c1	((m-b) m-a oa-high-select)
;; after a conditional jump with n the write runs only when the jump is not
;; taken: its select is the next word, a jump through oa-reg-low
	(jump-equal m-a a-b oa-c0)
	((oa-reg-low) m-a)
oa-xl	(jump oa-c2 oa-low-select)
;; a call with n returns to the write; its select a dispatch-memory write
oa-c2	(call oa-sub)
	((oa-reg-low) m-a)
	(dispatch a-b write-dispatch-ram oa-low-select)
;; a write in a call's slot (no n), its select at the call's target
	(call-xct-next oa-sub-2)
	((oa-reg-low) m-a)
	((m-a) setz)
;; a conditional jump through oa-reg-high, where a hint may go
	((oa-reg-high) m-a)
oa-xh	(jump-equal m-a a-b oa-c0 oa-high-select)
;; a write in a dispatch's slot, each entry without n: each target selects
	(dispatch (byte-field 1 0) m-a oa-table)
	((oa-reg-low) m-a)
oa-dt-0	((m-b) m-a oa-low-select)
	(jump oa-c0)
oa-dt-1	((m-b) m-a oa-low-select)
	(jump oa-c0)
oa-sub	(popj)
oa-sub-2	((m-b) m-a oa-low-select)
	(popj)

;;; variant dropped
;; rule 1: a write whose next word has no select
	((oa-reg-low) m-a)
	((m-b) m-a)
oa-end	(jump oa-end)

;;; variant no-write
;; rule 2: a select entered from words that are no writes, a jump and a
;; word falling through
	(jump oa-s)
	((m-b) m-a)
oa-s	((m-b) m-a oa-low-select)
oa-end	(jump oa-end)

;;; variant return-point
;; rule 2: a select at a return point
	(call oa-sub)
	((m-b) m-a oa-low-select)
oa-end	(jump oa-end)
oa-sub	(popj)

;;; variant misc-entry
;; rule 2: a select at a misc entry
	(jump oa-start)
oa-m	(misc-inst-entry %halt)
	((m-b) m-a oa-low-select)
oa-end	(jump oa-end)

;;; variant n-jump
;; n: a write after a conditional jump that sets n, taken for the jump's
;; slot, with a select at the jump's target
	(jump-equal m-a a-b oa-t)
	((oa-reg-low) m-a)
	((m-b) m-a oa-low-select)
oa-end	(jump oa-end)
oa-t	((m-b) m-a oa-low-select)
	(jump oa-end)

;;; variant n-call
;; n: a write after a call that sets n, taken for the call's slot, with a
;; select at the call's target
	(call oa-sub)
	((oa-reg-low) m-a)
	((m-b) m-a oa-low-select)
oa-end	(jump oa-end)
oa-sub	((m-b) m-a oa-low-select)
	(popj)

;;; variant n-dispatch
;; n: a write in a dispatch's slot whose table mixes n: the entry with n goes
;; to its target with the write inhibited
(locality d-mem)
(start-dispatch 1 0)
oa-table-n	;the second entry with n, the first without
	(oa-dt-0)
	(inhibit-xct-next-bit oa-dt-1)
(end-dispatch)
(locality i-mem)
	(dispatch (byte-field 1 0) m-a oa-table-n)
	((oa-reg-low) m-a)
oa-dt-0	((m-b) m-a oa-low-select)
	(jump oa-end)
oa-dt-1	((m-b) m-a oa-low-select)
oa-end	(jump oa-end)

;;; variant return-slot
;; rule 1: a write in a return's slot
	(call oa-sub)
oa-end	(jump oa-end)
oa-sub	((m-a) setz popj-after-next)
	((oa-reg-low) m-a)

;;; variant two-selects
;; rule 3: both selects on one word
	((oa-reg-low) m-a)
	((m-b) m-a oa-low-select oa-high-select)
oa-end	(jump oa-end)

;;; variant dispatch-select
;; rule 3: oa-low-select on a dispatch that transfers
(locality d-mem)
(start-dispatch 1 0)
oa-table
	(oa-dt-0)
	(oa-dt-1)
(end-dispatch)
(locality i-mem)
	((oa-reg-low) m-a)
	(dispatch (byte-field 1 0) m-a oa-table oa-low-select)
	((m-a) setz)
oa-dt-0	(jump oa-dt-0)
oa-dt-1	(jump oa-dt-1)

;;; variant dispatch-write-popj
;; rule 3: oa-low-select on a dispatch-memory write with popj
	((oa-reg-low) m-a)
	(dispatch a-b write-dispatch-ram oa-low-select popj-after-next)
	((m-a) setz)
