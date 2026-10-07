;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:10; Readtable:ZL -*-
;;; For the check float-print-least (tools/system-check/README.md): the
;;; smallest floats of both formats print, and the printed text reads back as
;;; the same float.  Definitions only; the cases call them.

(defun fpl-round-trip (x)
  "T if X prints and its printed text reads back as a float EQL to X; else
the printed text."
  (let ((s (prin1-to-string x)))
    (if (eql (read-from-string s) x) t s)))

(defun fpl-next-short (x)
  "The short float just above the positive short float X: its pointer field
plus one (one more in the mantissa's last place)."
  (%make-pointer dtp-small-flonum (1+ (%pointer x))))
