;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:8; Lowercase:T; Readtable:ZL -*-

;;; The cross build's native control (tools/cross-check/README.md): the
;;; cold-load generator at 1024-word pages of 32-bit words, 4 disk blocks a
;;; page, loaded over QCOM (cold:cold-load-overlays).  Only the page changes.

(setq page-size 2000
      %%q-pointer-within-page 0012)
