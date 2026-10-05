;-*- Mode:LISP; Package:MICRO-ASSEMBLER; Base:8 -*-

;; tools/assembler-check's bits fixture: a few words in revision 14's names,
;; assembled on their own with ua:assemble, so that their bits can be read
;; out of y1bits.mcr and held to appendix a14's encoding (README.md, check
;; bits).  never part of the microcode.

(setq y1bits '(

(locality m-mem)
m-garbage	(0)
m-a		(0)

(locality a-mem)
a-garbage	(0)
a-hunoz		(0)
a-b		(0)
(loc 40)

(locality i-mem)
;; condition 12, m <= a on the fields, unsigned (a14.10), and its inverse
y1-le		(jump-less-or-equal-unsigned m-a a-b y1-le)
y1-le-x		(jump-less-or-equal-unsigned-xct-next m-a a-b y1-le)
y1-le-call	(call-less-or-equal-unsigned m-a a-b y1-le)
y1-le-popj	(popj-less-or-equal-unsigned m-a a-b)
y1-gt		(jump-greater-than-unsigned m-a a-b y1-le)
y1-gt-x		(jump-greater-than-unsigned-xct-next m-a a-b y1-le)
y1-gt-call	(call-greater-than-unsigned m-a a-b y1-le)
y1-gt-popj	(popj-greater-than-unsigned m-a a-b)
;; the write-map operation word (a14.4): vma<33:32> the operation, <29:0>
;; a direct write's page entry
y1-none		((m-a) (a-constant write-map-none))
y1-write	((m-a) (a-constant write-map-direct-write))
y1-inval	((m-a) (a-constant write-map-invalidate))
y1-empty	((m-a) (a-constant write-map-empty))
y1-bv		((m-a) (a-constant (byte-value write-map-operation 2)))
y1-op-dpb	((vma-write-map) dpb m-a write-map-operation a-b)
y1-ent-dpb	((vma) dpb m-a write-map-entry a-b)
;; the pointer-type register's words 222 and 223 (a14.9), from ua:*pointer-types*
y1-ptr-lo	((m-a) (a-constant pointer-type-register-0-31))
y1-ptr-hi	((m-a) (a-constant pointer-type-register-32-63))
y1-end		(jump y1-end)
))
