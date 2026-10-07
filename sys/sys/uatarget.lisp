;;; -*- Mode:LISP; Package:MICRO-ASSEMBLER; Base:8; Readtable:ZL -*-

;;; the target description (contract g3 revision 15, 7; appendix a15b.7): every
;;; parameter of the machine an assembly is for, in one place.  the
;;; micro-assembler is a cross tool: what it assembles and writes depends on
;;; the target named here and on nothing of the world it runs in, so that the
;;; same sources assembled on a 32-bit band and on a 40-bit one give the same
;;; files.  before this file the .mcr writer took the fixnum tag of its
;;; symbol area from the assembling world's own %%q-data-type and dtp-fix
;;; (compiled in), and the control store's and the symbol area's sizes from
;;; the world's si: constants.
;;;
;;; ua:*word-width* and ua:*hardware-revision* name the target
;;; (assembly-target); the micro-assembler (cadrlp), the .mcr writer (qwmcr)
;;; and the microcode loader (usymld) read its parameters (target-parameter).
;;; the cadr's line keeps mit's .mcr and quux's revisions 13 and 14 theirs,
;;; byte for byte; revision 15 writes the self-describing .mcr (a15b.7).
;;;
;;; the parameters, each target giving every one:
;;;  :word-width              the machine's word, bits (ua:*word-width*)
;;;  :revision                the revision the assembly's names are checked
;;;                           against (ua:*hardware-revision*): a name marked
;;;                           with a later one (cons-lap-revision) is refused
;;;  :hardware-revision       the revision the .mcr names in its section 6,
;;;                           or nil where it has none
;;;  :data-type-field         the data type's byte in a word
;;;  :cdr-code-field          the cdr code's byte in a word
;;;  :fixnum-tag              the fixnum's data type
;;;  :microinstruction-width  the control store's word, bits
;;;  :control-store-words     the control store's size
;;;  :prom-base, :prom-words  the boot prom's place in the control store, or
;;;                           nil where it has none there (the cadr's)
;;;  :dispatch-memory-words   the dispatch memory's size
;;;  :dispatch-address-field  a dispatch word's dispatch memory address
;;;  :a-memory-words          a memory's size, m memory its first 40
;;;  :symbol-area-words       the microcode symbol area's size
;;;  :mcr-format              :mit, mit's sections, or :self-describing (a15b.7)
;;;  :mcr-revision-section    mit's format: t if section 6 comes first
;;;  :mcr-a-memory-section    mit's format: a memory's section, 4 (a word a
;;;                           location) or 5 (two words, revision 13's a1.12)
;;;  :mcr-symbol-area-tag     mit's format: t if each symbol area word
;;;                           carries the fixnum tag in the target's own word
;;;  :mcr-format-word         the self-describing format's first word
;;;  :mcr-sections            the self-describing format's sections, in order:
;;;                           (type actual-width storage-width) each
;;;  :control-store-halves    the two bytes of a control store word that
;;;                           %write-internal-processor-memories takes as
;;;                           d-hi and d-low
;;;  :extension               the extension's fields (a15b.2): (name byte)
;;;  :oa-registers            (destination byte): oa-reg-low's and
;;;                           oa-reg-high's destinations and the ir bits each
;;;                           register covers (a15b.15)
;;;  :oa-select-fields        (select class byte ...): the fields a select ors
;;;                           its register into, by class (a15b.15)
;;;  :revision-14-checks      t if assemble-system holds the microcode to
;;;                           revision 14's hardware (cadrlp)
;;;  :oa-select-check         t if the oa select check runs (a15b.15)
;; cadrlp's two switches, which name the target.
(proclaim '(special *word-width* *hardware-revision*))

(defconst *assembly-targets*
	  '((:cadr (32. 13.)			;the cadr, and quux to microcode 2000
	     :word-width 32. :revision 13. :hardware-revision nil
	     :data-type-field 3105 :cdr-code-field 3602 :fixnum-tag 5
	     :microinstruction-width 48. :control-store-words 40000
	     :prom-base nil :prom-words nil
	     :dispatch-memory-words 4000 :dispatch-address-field 1413
	     :a-memory-words 2000 :symbol-area-words 2000
	     :mcr-format :mit :mcr-revision-section nil :mcr-a-memory-section 4
	     :mcr-symbol-area-tag t :mcr-format-word nil :mcr-sections nil
	     :control-store-halves (3030 0030)
	     :extension nil :oa-registers nil :oa-select-fields nil
	     :revision-14-checks nil :oa-select-check nil)
	    (:quux-13 (40. 13.)			;contract g2: microcode 2001
	     :word-width 40. :revision 13. :hardware-revision nil
	     :data-type-field 4006 :cdr-code-field 4602 :fixnum-tag 5
	     :microinstruction-width 48. :control-store-words 40000
	     :prom-base 36000 :prom-words 2000
	     :dispatch-memory-words 10000 :dispatch-address-field 1414
	     :a-memory-words 2000 :symbol-area-words 2000
	     :mcr-format :mit :mcr-revision-section nil :mcr-a-memory-section 5
	     :mcr-symbol-area-tag nil :mcr-format-word nil :mcr-sections nil
	     :control-store-halves (3030 0030)
	     :extension nil :oa-registers nil :oa-select-fields nil
	     :revision-14-checks nil :oa-select-check nil)
	    (:quux-14 (40. 14.)			;contract g3 revision 14, appendix a14
	     :word-width 40. :revision 14. :hardware-revision 14.
	     :data-type-field 4006 :cdr-code-field 4602 :fixnum-tag 5
	     :microinstruction-width 48. :control-store-words 40000
	     :prom-base 36000 :prom-words 2000
	     :dispatch-memory-words 10000 :dispatch-address-field 1414
	     :a-memory-words 2000 :symbol-area-words 2000
	     :mcr-format :mit :mcr-revision-section t :mcr-a-memory-section 5
	     :mcr-symbol-area-tag nil :mcr-format-word nil :mcr-sections nil
	     :control-store-halves (3030 0030)
	     :extension nil :oa-registers nil :oa-select-fields nil
	     :revision-14-checks t :oa-select-check nil)
	    (:quux-15 (40. 15.)			;contract g3 revision 15, appendix a15b
	     :word-width 40. :revision 15. :hardware-revision 15.
	     :data-type-field 4006 :cdr-code-field 4602 :fixnum-tag 5
	     :microinstruction-width 64. :control-store-words 40000
	     :prom-base 36000 :prom-words 2000
	     :dispatch-memory-words 10000 :dispatch-address-field 1414
	     :a-memory-words 2000 :symbol-area-words 2000
	     :mcr-format :self-describing :mcr-revision-section nil
	     :mcr-a-memory-section nil :mcr-symbol-area-tag nil
	     ;; 0x51550001: machine-id's signature over the format number 1
	     :mcr-format-word 12125200001
	     ;; 6 the hardware revision, 1 the control store, 2 the dispatch
	     ;; memory (<16:0> the entry, <17> odd parity), 3 the symbol area (a
	     ;; fixnum), 4 a memory, last, since the prom stages it in the pdl
	     ;; buffer and ends there
	     :mcr-sections ((6 32. 32.) (1 64. 64.) (2 18. 32.) (3 40. 64.) (4 40. 64.))
	     :control-store-halves (4040 0040)
	     ;; a15b.2, read by the class ir<44:43>: jump's hint <48>, alu's and
	     ;; byte's pdl address field (e <48>, the base <50:49>, the
	     ;; displacement <58:51>), dispatch's predicted target (<61:48>, p and
	     ;; r inverted in <62> and <63>), and the oa selects
	     :extension ((:hint 6001) (:pdl-field-present 6001) (:pdl-base 6102)
			 (:pdl-displacement 6310) (:predicted-address 6016)
			 (:predicted-p-inverted 7601) (:predicted-r-inverted 7701)
			 (:oa-low-select 7401) (:oa-high-select 7501))
	     ;; oa-reg-low, destination 16, covers ir<25:0>; oa-reg-high,
	     ;; destination 17, ir<47:26>
	     :oa-registers ((16 0032) (17 3226))
	     ;; sl: alu and byte, the a destination <23:14> (ir<25> 1) or the m
	     ;; destination <18:14> (ir<25> 0); alu's function <6:3>; byte's
	     ;; rotate <5:0> and length - 1 <11:6>; jump's address <25:12>; a
	     ;; dispatch-memory write's address <23:12>.  sh: the a source
	     ;; <41:32>, and the m source <30:26> when ir<31> is 0
	     :oa-select-fields ((:oa-low-select :alu 1612 1605 0304)
				(:oa-low-select :byte 1612 1605 0006 0606)
				(:oa-low-select :jump 1416)
				(:oa-low-select :dispatch-memory-write 1414)
				(:oa-high-select :alu 4012 3205)
				(:oa-high-select :byte 4012 3205)
				(:oa-high-select :jump 4012 3205))
	     :revision-14-checks t :oa-select-check t))
  "The machines the micro-assembler assembles for: (name (word-width hardware-revision) . parameters).")

(defconst *assembly-target-parameters*
	  '(:word-width :revision :hardware-revision :data-type-field :cdr-code-field
	    :fixnum-tag :microinstruction-width :control-store-words :prom-base :prom-words
	    :dispatch-memory-words :dispatch-address-field :a-memory-words
	    :symbol-area-words :mcr-format :mcr-revision-section :mcr-a-memory-section
	    :mcr-symbol-area-tag :mcr-format-word :mcr-sections :control-store-halves
	    :extension :oa-registers :oa-select-fields :revision-14-checks :oa-select-check)
  "Every parameter a target description gives.")

(defun assembly-target ()
  "The target description ua:*word-width* and ua:*hardware-revision* name, or an error."
  (or (dolist (target *assembly-targets*)
	(when (and (eql (car (cadr target)) *word-width*)
		   (eql (cadr (cadr target)) *hardware-revision*))
	  (return target)))
      (ferror nil "No target is ~D bits at revision ~D: the micro-assembler knows ~{~A~^, ~} (ua:*assembly-targets*)."
	      *word-width* *hardware-revision*
	      (mapcar #'(lambda (target)
			  (format nil "~D bits at revision ~D" (car (cadr target)) (cadr (cadr target))))
		      *assembly-targets*))))

(defun target-parameter (name)
  "The parameter NAME of the target being assembled for (assembly-target)."
  (let ((parameters (cddr (assembly-target))))
    (unless (memq name *assembly-target-parameters*)
      (ferror nil "~S is not a parameter of a target description." name))
    (do ((p parameters (cddr p)))
	((null p)
	 (ferror nil "The target ~S gives no ~S." (car (assembly-target)) name))
      (when (eq (car p) name) (return (cadr p))))))

(defun target-extension-field (name)
  "The byte of the extension's field NAME (appendix a15b.2) in the target's microinstruction."
  (or (cadr (assq name (target-parameter :extension)))
      (ferror nil "The target ~S has no extension field ~S." (car (assembly-target)) name)))

(defun target-extension-bit (name)
  "The value of the one-bit extension field NAME set alone, as a word to add in the source."
  (dpb 1 (target-extension-field name) 0))

(defun control-store-word-halves (word)
  "WORD, a control store word, as the two fixnums %write-internal-processor-memories takes:
d-hi and d-low, the target's :control-store-halves.  Each half's top bit is put in with
%logdpb, so that a 32-bit half makes a fixnum on a 40-bit machine rather than a bignum.
Returns them as two values."
  (values-list
    (mapcar #'(lambda (field)
		(let ((size (ldb 0006 field)) (position (ldb 0606 field)))
		  ;; the halves are for the machine being loaded, which is the
		  ;; target: a world whose fixnum is narrower than a half (a
		  ;; 32-bit world, a revision-15 half) cannot pass it to
		  ;; %write-internal-processor-memories
		  (when (> (1- size) (haulong most-positive-fixnum))
		    (ferror nil "A ~D-bit half of the control store word is no fixnum in this world: load the target's control store on the target."
			    size))
		  ;; by ash and logand: an ldb's field must fit a fixnum
		  (%logdpb (logand (ash word (- 1 position size)) 1)
			   (+ (lsh (1- size) 6) 1)
			   (logand (ash word (- position)) (1- (expt 2 (1- size)))))))
	    (target-parameter :control-store-halves))))
