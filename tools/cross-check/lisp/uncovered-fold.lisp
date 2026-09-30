;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:10; Lowercase:T; Readtable:ZL -*-

;;; The cross build's controls (tools/cross-check/README.md): a fold of a
;;; system constant with no target value (%%q-high-half in the synthetic
;;; target, synth.lisp) must stop the file, though the fold's own error is
;;; caught by the compiler and only warned about.

(defun xc-uncovered-fold () (ash %%q-high-half 20))
