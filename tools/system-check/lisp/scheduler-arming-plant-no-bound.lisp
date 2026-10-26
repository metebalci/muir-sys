;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:8; Readtable:ZL -*-
;;; A planted fault for the check scheduler-arming (tools/system-check/README.md;
;;; QUUX's timer-driven scheduler, S2): the GC's bound ignored: the arming gives the
;;; pure function no bound.
;;; Given after lisp/scheduler-arming.lisp in --files, on a band with the change:
;;; (5), the GC process within 7 units of eden full, must fail.  Not for any band in use.

(defun scheduler-arm (this-time pass-us process)
  "Timer 1 armed for PROCESS, about to be resumed by the pass that began at THIS-TIME and
PASS-US (TS-6), and the pass counted.  The network's and the sleeps' due times are not yet
given (NIL)."
  (let* ((now (%microsecond-clock-ldb #o0037))
	 (period (scheduler-arm-period this-time pass-us now process nil	;planted: no bound
				       nil nil nil)))
    ;; a period write restarts timer 1, risen or not (contract q11, rule 4);
    ;; 0 leaves it on with nothing to count
    (%xbus-write (+ feature-page-xbus-address #o113) period)
    (setq scheduler-pass-due (and (plusp period) (logand (+ now period) #o17777777777))
	  scheduler-passes (logand (1+ scheduler-passes) #o17777777777))))
