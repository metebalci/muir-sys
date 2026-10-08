;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:10; Readtable:ZL -*-
;;; For the check extra-pdl-locative, given after its own file: the compare's
;;; old way, the page held as a locative across the stack-group switch.  The
;;; pdl buffer's dump traps it into EXTRA-PDL-TRAP, which copies the page's
;;; first word, a fixnum and no header, as an object: the machine halts at
;;; ILLOP, and the case gets no answer.

(defun epl-hold ()
  "The compare's old way: the page held as a locative across a stack-group
switch."
  (let* ((a (%make-pointer dtp-locative (epl-page)))
	 (s (epl-switch)))
    (list s (eq (%pointer a) (epl-page)))))
