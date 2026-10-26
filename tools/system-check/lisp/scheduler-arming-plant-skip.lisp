;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:8; Readtable:ZL -*-
;;; A planted fault for the check scheduler-arming (tools/system-check/README.md;
;;; QUUX's timer-driven scheduler, S2): the arming skipped: timer 1 is never written,
;;; so a pass comes only at a wait, a frame or the clock's break.
;;; Given after lisp/scheduler-arming.lisp in --files, on a band with the change:
;;; (2), two loops' turns, about a second, must fail.  Not for any band in use.

(defun scheduler-arm (this-time pass-us process)
  "Timer 1 armed for PROCESS, about to be resumed by the pass that began at THIS-TIME and
PASS-US (TS-6), and the pass counted.  The network's and the sleeps' due times are not yet
given (NIL)."
  (let* ((now (%microsecond-clock-ldb #o0037))
	 (period (scheduler-arm-period this-time pass-us now process clock-rate-bound
				       nil nil nil)))
    ;; a period write restarts timer 1, risen or not (contract q11, rule 4);
    ;; 0 leaves it on with nothing to count
    ;; planted: no write
    period
    (setq scheduler-pass-due (and (plusp period) (logand (+ now period) #o17777777777))
	  scheduler-passes (logand (1+ scheduler-passes) #o17777777777))))
