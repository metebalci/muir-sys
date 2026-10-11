;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:10; Readtable:ZL -*-
;;; For the check extra-pdl-locative, given after its own file: the compare's
;;; old way, the page held as a locative across the stack-group switch.  The
;;; pdl buffer's dump traps it into EXTRA-PDL-TRAP; the page lies past every
;;; object of the extra pdl, so the trap copies the object below it and gives
;;; the locative that copy's address plus the page's offset, and the case
;;; fails, (T NIL).

(defun epl-hold ()
  "The compare's old way: the page held as a locative across a stack-group
switch."
  (let* ((a (%make-pointer dtp-locative (epl-page)))
	 (s (epl-switch)))
    (list s (eq (%pointer a) (epl-page)))))
