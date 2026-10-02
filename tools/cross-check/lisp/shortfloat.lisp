;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:10; Lowercase:T; Readtable:ZL -*-

;;; The cross build's check 1 (tools/cross-check/README.md): a short float of
;;; the builder, made by #., holds 17 bits where the target's holds 24, so the
;;; file must stop and its QFASL not be written (compiler:fasd-short-float).
(defun xc-builder-short-float () '#.(small-float 1.3))
