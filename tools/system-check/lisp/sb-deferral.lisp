;;; -*- Mode:LISP; Package:USER; Base:10; Readtable:ZL -*-
;;; For the check sb-deferral (tools/system-check/README.md): a sequence break
;;; deferred while the scheduler runs is the machine's, not the scheduler
;;; stack group's (sys/ucadr/uc-stack-groups.lisp, sgent; QUUX's Ethernet
;;; contract, section 2.6).  MIT's sgent restored the deferred flag, bit
;;; %%m-flags-deferred-sequence-break of m-flags (%mode-flags), from the stack
;;; group entered, so a break that came during the scheduler's pass was
;;; dropped when it resumed a process, and the next pass waited for the clock's
;;; next break, a second at the clock's default rate.
;;;
;;; A trial: a compute process X at priority 0, which never waits, and a
;;; process W at priority 1 whose wait predicate, run by the scheduler, does the work.  Armed,
;;; the predicate clears the bit (MIT's scheduler keeps a stale 1 once any
;;; break was deferred in it), spins until a clock break sets it, deferred
;;; since the scheduler inhibits scheduling, records the microsecond clock and
;;; returns NIL; the scheduler resumes X.  On its next call the predicate
;;; records the clock again and returns T.  With the flag the machine's, X
;;; breaks at its first instruction and the next pass comes within a few
;;; milliseconds; with MIT's sgent, at the clock's next break, about a second
;;; later.  The clock runs at its default, every 60 ticks, for the trial.

(defvar sbd-phase 0)
(defvar sbd-t0 0)
(defvar sbd-t1 0)
(defvar sbd-stop nil)
(defvar sbd-count 0)

(defun sbd-bit ()
  "The deferred sequence break's bit of %MODE-FLAGS, 0 or 1."
  (ldb si:%%m-flags-deferred-sequence-break si:%mode-flags))

(defun sbd-now ()
  "The microsecond clock's low 23 bits, as the scheduler reads it."
  (si:fixnum-microsecond-time-for-scheduler-for-cadr))

(defun sbd-predicate ()
  ;; only in the scheduler's pass: process-wait calls the predicate once in
  ;; the process itself first, where scheduling is allowed, a break is taken
  ;; rather than deferred, and the spin below would never end.
  (case (and (eq si:%current-stack-group si:scheduler-stack-group) sbd-phase)
    (1 ;; the ethernet device's interrupt disarmed (240 <8> clear, <0> kept),
       ;; so that until the next pass only the clock can break x: a frame from
       ;; the tap would otherwise bring the pass early with mit's sgent too.
       ;; the network process arms it again before its next wait.
       (when (and (boundp 'ip::ether-enabled) ip::ether-enabled)
	 (ip::ether-set-register ip::%ether-control 1))
       (setq si:%mode-flags (%logdpb 0 si:%%m-flags-deferred-sequence-break si:%mode-flags))
       (do () ((= (sbd-bit) 1)))
       (setq sbd-t0 (sbd-now) sbd-phase 2)
       nil)
    (2 (setq sbd-t1 (sbd-now) sbd-phase 3)
       t)
    (3 t)
    (t nil)))

(defun sbd-trial ()
  "One trial: the gap, in microseconds, from the break deferred in the scheduler's pass
to the next pass."
  (setq sbd-phase 0 sbd-stop nil sbd-count 0)
  (let ((x (process-run-function "sbd compute" #'(lambda () (do () (sbd-stop) (incf sbd-count)))))
	;; w above x: the scheduler stops its scan at the first runnable process,
	;; so w's predicate must come before x, which is always runnable.
	(w (process-run-function '(:name "sbd wait" :priority 1)
				 #'(lambda () (process-wait "sbd" #'sbd-predicate)))))
    (unwind-protect
	(progn
	  ;; the clock's default rate for the trial: a rate asked for by the
	  ;; collector or the network (every tick while a timer is due) would
	  ;; bring the next pass within a tick even with MIT's sgent.
	  (si:write-meter 'si:%tv-clock-rate 60.)
	  ;; a sixth of a second for the processes to settle: the last trial's,
	  ;; killed, and this one's, started; one that ran and then waited in the
	  ;; gap would bring the next pass early.
	  (process-sleep 10.)
	  (setq sbd-phase 1)
	  (process-wait "sbd trial" #'(lambda () (= sbd-phase 3)))
	  (logand (- sbd-t1 sbd-t0) (1- (expt 2 23))))
      (setq sbd-stop t)
      (send w :kill)
      (send x :kill)
      (process-wait-with-timeout "sbd kill" 60.
	#'(lambda () (not (or (assq x si:active-processes) (assq w si:active-processes)))))
      ;; the rate back to the smallest asked for
      (si:request-clock-rate :sb-deferral nil))))

(defvar sbd-gaps nil)

(defun sbd-trials (n)
  "N trials, T for each gap under 100 ms; the gaps in SBD-GAPS."
  (setq sbd-gaps (loop repeat n collect (sbd-trial)))
  (loop for gap in sbd-gaps collect (< gap 100000.)))

;; a coroutine called inside a without-interrupts: the caller's own deferred
;; break (a clock break that came inside its section) goes with the flag into
;; the callee, which swaps its bindings and so runs with scheduling allowed:
;; it takes the break there.  the caller's bit after the return is then the
;; machine's, 0; with mit's sgent it is the caller's saved 1, taken at its
;; section's end.
(defun sbd-coroutine ()
  "(CALLEE-BIT CALLER-BIT-AFTER-RETURN)"
  (let ((sg (make-stack-group "sbd coroutine")))
    (stack-group-preset sg #'(lambda () (sbd-bit)))
    (without-interrupts
      (setq si:%mode-flags (%logdpb 0 si:%%m-flags-deferred-sequence-break si:%mode-flags))
      (do () ((= (sbd-bit) 1)))
      (let ((callee (funcall sg)))
	(list callee (sbd-bit))))))

;; compiled here when the file is loaded as source, as the scheduler runs the
;; predicate compiled.
(dolist (f '(sbd-bit sbd-now sbd-predicate sbd-trial sbd-trials sbd-coroutine))
  (unless (compiled-function-p (fdefinition f))
    (compile f)))
