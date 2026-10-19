;;; -*- Mode:LISP; Package:USER; Base:10; Readtable:ZL -*-
;;; For the check sg-deferred-entry (tools/microcode-check/README.md): sgent
;;; carries the deferred sequence break's flag, bit
;;; %%m-flags-deferred-sequence-break of m-flags, from the stack group left
;;; into the one entered, where sb-reinstate asks for the break again
;;; (sys/ucadr/uc-stack-groups.lisp; QUUX's Ethernet contract, section 2.6).
;;; Each case defers a clock break inside a without-interrupts (the bit set,
;;; scheduling inhibited), then enters a stack group in one of
;;; d-sg-enter's resume states with scheduling allowed there: resumable,
;;; awaiting return, awaiting call and awaiting initial call.  The group entered
;;; must break at once, before its first form, and then run on intact.  A
;;; process at priority 40 counts the scheduler's passes in its wait
;;; predicate, which every pass calls first; the group entered reads the
;;; count, and the case compares it with the count before the entry.  With
;;; mit's sgent, which restored the entered group's own flag, the count does
;;; not move.

(defvar sgd-passes 0)
(defvar sgd-counter nil)

(defun sgd-count-pass ()
  (setq sgd-passes (1+ sgd-passes))
  nil)

(defun sgd-start ()
  "The pass counter's process, at priority 40, above every other."
  (unless sgd-counter
    (setq sgd-counter (process-run-function '(:name "sgd passes" :priority 40)
					    #'(lambda () (process-wait "sgd" #'sgd-count-pass)))))
  (process-sleep 10.)
  (plusp sgd-passes))

(defun sgd-bit ()
  (ldb si:%%m-flags-deferred-sequence-break si:%mode-flags))

(defun sgd-defer ()
  "Inside a without-interrupts: clear the bit, then spin until a clock break sets it."
  (setq si:%mode-flags (%logdpb 0 si:%%m-flags-deferred-sequence-break si:%mode-flags))
  (do () ((= (sgd-bit) 1))))

;; awaiting initial call: a preset group's first call (sg-enter-call).
(defun sgd-initial ()
  "(BROKE VALUE)"
  (let ((sg (make-stack-group "sgd initial")))
    (stack-group-preset sg #'(lambda (a b) (list sgd-passes (+ a b))) 1 2)
    (without-interrupts
      (sgd-defer)
      (let* ((before sgd-passes) (r (funcall sg)))
	(list (> (first r) before) (second r))))))

;; awaiting call: a group that did stack-group-return, called again (r-bit).
(defun sgd-call ()
  "(BROKE VALUE)"
  (let ((sg (make-stack-group "sgd call")))
    (stack-group-preset sg #'(lambda () (do-forever (stack-group-return (list sgd-passes 'again)))))
    (funcall sg)
    (without-interrupts
      (sgd-defer)
      (let* ((before sgd-passes) (r (funcall sg)))
	(list (> (first r) before) (second r))))))

;; awaiting return: the caller, entered again when its callee returns from
;; inside a without-interrupts that deferred a break (qmddr0).  the caller
;; itself is outside any without-interrupts.
(defun sgd-return ()
  "(BROKE VALUE)"
  (let ((sg (make-stack-group "sgd return")))
    (stack-group-preset sg #'(lambda () (without-interrupts
					   (sgd-defer)
					   (stack-group-return (list sgd-passes 'returned)))))
    (let ((r (funcall sg)))
      (list (> sgd-passes (first r)) (second r)))))

;; resumable: a process the clock's break preempted, resumed by the scheduler
;; (r-bit).  the listener defers a break and waits inside its section; the
;; flag goes with it into the scheduler, which keeps it (scheduling is
;; inhibited there), and on into the compute process it resumes, which breaks
;; at once: a second pass before the compute process's first form.  the
;; compute process records the pass count when it first runs after the wait;
;; with mit's sgent it is one pass after the wait's, with the flag carried two
;; or more: a pass the network process takes first, for the session's own
;; frames over tcp, adds one (3, and 5 through the fault relay, on rtl).
(defvar sgd-seen 0)
(defvar sgd-stop-compute nil)

(defun sgd-resume ()
  "(RESUMABLE BROKE PASSES): T if the compute process's stack group was resumable at the
wait, T if two passes or more came from the wait to its first form, and how many."
  (setq sgd-stop-compute nil sgd-seen 0)
  (let ((x (process-run-function "sgd compute"
				 #'(lambda () (do () (sgd-stop-compute)
						(when (minusp sgd-seen) (setq sgd-seen sgd-passes)))))))
    ;; the count is exact only if nothing else brings a pass between the wait
    ;; and the compute process's first form: a clock break there (every 6
    ;; ticks with the collector on) gave 3 now and then on rtl.  so for the
    ;; case the clock runs at its default rate, 60 ticks, and the ethernet
    ;; device's interrupt, on a band with the network, is disarmed (240 <8>
    ;; clear, <0> kept; the network process arms it again before its next
    ;; wait), so that until the next pass only the carried break can bring one.
    (let ((rate (si:read-meter 'si:%tv-clock-rate))
	  (ip (find-package "INTERNET")))
      (unwind-protect
	  (let (before state)
	    (si:write-meter 'si:%tv-clock-rate 60.)
	    ;; x runs, and is preempted by a break when the listener wakes
	    (process-sleep 10.)
	    (without-interrupts
	      (setq state (si:sg-current-state (process-stack-group x)))
	      (when (and ip (boundp (intern "ETHER-ENABLED" ip)) (symbol-value (intern "ETHER-ENABLED" ip)))
		(funcall (intern "ETHER-SET-REGISTER" ip) (symbol-value (intern "%ETHER-CONTROL" ip)) 1))
	      (sgd-defer)
	      (setq sgd-seen -1 before sgd-passes)
	      (process-wait "sgd" #'(lambda () (not (minusp sgd-seen)))))
	    (list (= state si:sg-state-resumable) (>= (- sgd-seen before) 2) (- sgd-seen before)))
	(setq sgd-stop-compute t)
	(send x :kill)
	;; gone before the next case: a killed process still in the scheduler's
	;; list ran first in the next trial's pass and added one (2 with mit's sgent)
	(process-wait-with-timeout "sgd kill" 60. #'(lambda () (not (assq x si:active-processes))))
	(si:write-meter 'si:%tv-clock-rate rate)))))

(defun sgd-stop ()
  (when sgd-counter (send sgd-counter :kill) (setq sgd-counter nil))
  t)

;; compiled here when the file is loaded as source: the spin and the entries
;; are meant as compiled code runs them.
(dolist (f '(sgd-count-pass sgd-start sgd-bit sgd-defer sgd-initial sgd-call sgd-return sgd-resume sgd-stop))
  (unless (compiled-function-p (fdefinition f))
    (compile f)))
