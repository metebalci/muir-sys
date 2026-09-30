;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:8; Lowercase:T; Readtable:ZL -*-

;;; Check 1's identity control (tools/cross-check/README.md): the builder
;;; band's own page, 256 words, loaded over the tree's QCOM, whose pages are
;;; 1024 words (contract G2, option (w)).  With it the cross build's parameters
;;; are this world's, as the control needs.  Only the page's constants change.

(setq page-size 400
      %%q-pointer-within-page 0010
      %%pht1-virtual-page-number 1020
      %pht-dummy-virtual-address 177777)
