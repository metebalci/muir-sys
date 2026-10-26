;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:8; Readtable:ZL -*-
;;; A planted fault for the check scheduler-arming (tools/system-check/README.md;
;;; QUUX's timer-driven scheduler, S2): a TIME due mapped to an instant of the
;;; network's 31-bit clock by its low 17 bits, as an earlier text of the
;;; contract had it (F2): beyond 2^16 units it compares as past.
;;; Given after lisp/scheduler-arming.lisp in --files, on a band with the change:
;;; (1)'s 2^16 + 1 case must fail.  Not for any band in use.

(defun scheduler-arm-period (this-time pass-us now-us process bound
			     net-due sleep-start sleep-interval)
  "The period for timer 1 written at NOW-US, in microseconds: the distance to the earliest
due time not reached when the pass began, 1 for one reached since, at most 16,777,215; 0 if
none remains.  The pass began at THIS-TIME, a TIME, and PASS-US, the network's 31-bit clock
read beside it.  The due times (TS-5), each a distance: PROCESS's remaining quantum and BOUND
(REQUEST-CLOCK-RATE's) from THIS-TIME, and SLEEP-INTERVAL from SLEEP-START, in TIME units;
NET-DUE, a microsecond of the network's clock; each may be NIL.  It conses nothing and
cannot signal, so the scheduler calls it with interrupts off."
  ;; GONE, the units since THIS-TIME, is taken from NOW-US itself (TIME's bits
  ;; 16:0 are the microsecond clock's bits 30:14, SYS: SYS; QRAND), so that the
  ;; units and the microseconds into the current unit agree: a second read of
  ;; TIME could fall in the next unit and arm a unit early.  a distance in
  ;; TIME units is never mapped to an instant, since TIME wraps modulo 2^23
  ;; and the network's clock modulo 2^31 (F2); it is clamped to 1,023 units,
  ;; whose microseconds stay below 2^24, and converted from the current
  ;; unit's boundary, so the rise is a few microseconds late, never early.
  ;; a due time reached before the pass began is not armed (F1): the pass's
  ;; scan has seen its waiter, and armed at once it would break every resume
  ;; for as long as it stays set, a storm of passes.
  (let ((gone (logand (- (ash now-us -14.) (logand this-time #o377777)) #o377777))
	(units nil)
	(us nil))
    (let ((left (and process (process-quantum-remaining process))))
      (when (and left (plusp left))
	(setq units (- left gone))))
    (when (and bound (plusp bound))
      (setq units (if units (min units (- bound gone)) (- bound gone))))
    ;; planted: the sleep's due as an instant, TIME's low 17 bits as the
    ;; clock's bits 30:14
    (when sleep-start
      (let* ((instant (ash (logand (+ sleep-start sleep-interval) #o377777) 14.))
	     (d (logand (- instant now-us) #o17777777777)))
	(setq us (if (or (zerop d) (not (< d #o10000000000))) 1 (min d 16777215.)))))
    (when net-due
      (let ((before (logand (- net-due pass-us) #o17777777777)))
	;; reached before the pass began: zero, or in the past modulo 2^31
	(unless (or (zerop before) (not (< before #o10000000000)))
	  (let ((d (logand (- net-due now-us) #o17777777777)))
	    (setq us (if (or (zerop d) (not (< d #o10000000000))) 1 (min d 16777215.)))))))
    (when units
      (setq units (if (plusp units)
		      (- (* (min units 1023.) 16384.) (logand now-us 16383.))
		    1)))
    (cond ((and units us) (min units us))
	  (units)
	  (us)
	  (t 0))))
