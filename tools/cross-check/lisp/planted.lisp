;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:10; Lowercase:T; Readtable:ZL -*-

;;; The cross build's checks 1 and 2 (tools/cross-check/README.md): a planted
;;; fold of a constant that changes, and a read of one at #.  Compiled for the
;;; 40-bit machine they hold 1048576 (1024 shifted left 10) and 32.

(defun xc-planted-fold () (ash page-size 10))
(defun xc-planted-sharp () '(planted #.%%q-pointer))
