;-*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:8; Readtable:ZL -*-

;;; The word of g2's 40-bit machine (contract g1, the word; appendix a1), for
;;; the cross build (sys: cold; cross), which loads this file into the cold-load
;;; generator's package after QCOM, QDEFS and DEFMIC (cold:load-parameters, its
;;; cold-load-overlays), so these values replace theirs in the target's table
;;; and in the cold load.  It holds only what g1 and a1 fix: the fields of a word
;;; and the page.  Everything else is QCOM's as the tree has it, and moves there;
;;; when QCOM itself carries the 40-bit word, this file goes.

;;; Loading this with a base of other than 8 can really cause bizarre effects
GLOBAL:(UNLESS (= *READ-BASE* 8) (BREAK "*READ-BASE* not 8."))

;;; a word is the cdr code <39:38>, the data type <37:32> and the field <31:0>
;;; (g1 2.1); a fixnum's sign is the field's top bit (g1 2.4).  the halves of
;;; the field still hold two macroinstructions (g1 2.6), and characters keep
;;; today's fields (g2 7.1), so %%q-high-half, %%q-low-half, %%ch- and %%kbd- stay.
(setq %%q-cdr-code 4602
      %%q-boxed-sign-bit 3701
      %%q-data-type 4006
      %%q-pointer 0040
      %%q-typed-pointer 0046
      %%q-all-but-typed-pointer 4602
      %%q-all-but-pointer 4010
      %%q-all-but-cdr-code 0046)

;;; pages of 1024 words (g1 3.3), whose word offset is ten bits
(setq page-size 2000
      %%q-pointer-within-page 0012)
