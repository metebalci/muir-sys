;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:10; Lowercase:T; Readtable:ZL -*-

;;; The cross build's controls (tools/cross-check/README.md): #. of a watched
;;; symbol with no target value must stop the file, and no QFASL be written.

(defun xc-uncovered-sharp () '#.%file-device-name-page-bytes)
