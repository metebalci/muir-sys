;;; -*- Mode:LISP; Package:USER; Base:10 -*-
;;; APPLY of an interpreted &rest function: UAPLY spreads the list onto the
;;; stack (sys/ucadr/uc-call-return.lisp UAPLY5) and INTP1 opens APPLY-LAMBDA's
;;; call block above that frame (INTP-ARGLIST-MADE, P3ZERO), whose 8-bit
;;; deltas to the active and open blocks (%%LP-CLS-DELTA-TO-ACTIVE-BLOCK 0010,
;;; %%LP-CLS-DELTA-TO-OPEN-BLOCK 1010, sys/cold/qcom.lisp) hold N + 4 words.
;;; Loaded as source, so the functions stay interpreted.
(defun alf-plain (&rest args) (length args))
(defun alf-plain-n (n) (apply #'alf-plain (make-list n)))
(defun alf-switch () (let ((sg (make-stack-group "alf"))) (stack-group-preset sg #'(lambda () 7)) (funcall sg)))
(defun alf-hold (&rest args) (alf-switch) (length args))
(defun alf-n (n) (apply #'alf-hold (make-list n)))
