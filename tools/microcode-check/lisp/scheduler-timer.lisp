;;; -*- Mode:LISP; Package:USER; Base:10; Lowercase:T -*-

;;; The scheduler's timer, timer 1 (tools/microcode-check/README.md,
;;; cases-16/scheduler-timer.cases; QUUX's timer-driven scheduler, TS-3 and
;;; TS-4).  BEG06 (sys/ucadr/uc-cold-disk.lisp) turns timer 1 on at period 0,
;;; one-shot, with its interrupt enable: word 112 reads 405.  A period written
;;; to word 113 makes it rise that many microseconds later; INTR-TIMER-1
;;; (sys/ucadr/uc-interrupt.lisp) writes 112 with 403, which clears the flag
;;; and leaves it on and one-shot, and asks for a sequence break while :clock
;;; is enabled.  So a pass of the scheduler follows the rise.  Before it, timer
;;; 1 had no user: a reset left it off, and its stray turned it off with a
;;; write of 0.
;;;
;;; ST-COUNT, a process at priority 10 that never runs, has a wait predicate
;;; that the scheduler calls at every pass; it notes the time of its first
;;; call after the write.  The listener computes meanwhile, so nothing else
;;; gives a pass: the band runs without its network (--network files), and
;;; with the collector off the clock's own break comes once a second.  Each
;;; measurement first waits for a pass, so that the clock's next break is
;;; about a second away, computes 100 ms, then writes the period.

(defun st-now () (%microsecond-clock-ldb #o0037))
(defun st-diff (later earlier)
  "Microseconds from EARLIER to LATER on the 31-bit clock."
  (let ((d (logand (- later earlier) #o17777777777)))
    (if (< d #o10000000000) d (- d #o20000000000))))
(defun st-word (w) (%xbus-read (+ si:feature-page-xbus-address w)))
(defun st-set-word (w v) (%xbus-write (+ si:feature-page-xbus-address w) v))
(defun st-control ()
  "Word 112, timer 1's control and status, in octal."
  (format nil "~O" (st-word #o112)))

(defvar *st-calls* 0 "Calls of ST-COUNT-P, one a pass.")
(defvar *st-armed* nil "Set at the write of the period.")
(defvar *st-first* nil "The time of ST-COUNT-P's first call after the write.")
(defvar *st-sink* 0)
(defvar *st-last* nil "The last measurement: the latency in us (or NIL) and the loop's counts.")

(defun st-count-p ()
  (setq *st-calls* (1+ *st-calls*))
  (when (and *st-armed* (null *st-first*))
    (setq *st-first* (st-now)))
  nil)

(defun st-work ()
  (let ((s 0)) (dotimes (i 32) (setq s (logand (+ s i) 65535))) (setq *st-sink* s)))

(defun st-compute (us)
  "Compute for US microseconds; the number of rounds."
  (let ((t0 (st-now)) (n 0))
    (do () ((>= (st-diff (st-now) t0) us) n)
      (st-work)
      (setq n (1+ n)))))

(defun st-setup ()
  "The collector off, and the counting process at priority 10."
  (gc-off)
  (unless (dolist (p si:all-processes) (when (equal (send p :name) "ST Count") (return t)))
    (process-run-function '(:name "ST Count" :priority 10)
			  #'(lambda () (process-wait "ST Count" #'st-count-p))))
  (process-sleep 30)
  (and (plusp *st-calls*) t))

(defun st-measure (period window)
  "Wait for a pass, compute 100 ms, write PERIOD to word 113, and compute for WINDOW us.
The value: the us from the write to the first pass after it, or NIL; and *ST-LAST*
also gets the rounds computed in the 50 ms before the write and in the 50 ms after
the period, which an interrupt that is never cleared would cut to nearly none."
  (let ((c0 *st-calls*) (t0 (st-now)) tw before after)
    (setq *st-armed* nil *st-first* nil)
    (do () ((or (/= *st-calls* c0) (> (st-diff (st-now) t0) 3000000))) (st-work))
    (st-compute 50000)
    (setq before (st-compute 50000))
    (setq tw (st-now) *st-armed* t)
    (st-set-word #o113 period)
    (st-compute period)
    (setq after (st-compute 50000))
    (st-compute (max 0 (- window (st-diff (st-now) tw))))
    (setq *st-armed* nil)
    (setq *st-last* (list (and *st-first* (st-diff *st-first* tw)) before after))
    (car *st-last*)))

(defun st-pass-check (period bound)
  "A pass within BOUND us of the write of PERIOD, with :clock on; the loop not starved
after the rise; word 112 after it."
  (let ((latency (st-measure period 1500000)))
    (list (and latency (<= latency bound) t)
	  (> (third *st-last*) (floor (second *st-last*) 2))
	  (st-control))))

(defun st-sb-off-check (period)
  "With sequence breaks off, no pass in the 300 ms after the write of PERIOD; the loop
not starved after the rise; word 112 after it."
  (let ((old (si:sb-on)) latency)
    (unwind-protect
	(progn (si:sb-on nil)
	       ;; the pass that ST-MEASURE waits for comes by the scheduler's own
	       ;; call from PROCESS-ALLOW-SCHEDULE
	       (process-allow-schedule)
	       (let ((c0 *st-calls*))
		 (setq *st-armed* nil *st-first* nil)
		 (st-compute 100000)
		 (let ((before (st-compute 50000)) (tw (st-now)) after)
		   (setq *st-armed* t)
		   (st-set-word #o113 period)
		   (st-compute period)
		   (setq after (st-compute 50000))
		   (st-compute (max 0 (- 300000 (st-diff (st-now) tw))))
		   (setq *st-armed* nil)
		   (setq latency (and *st-first* (st-diff *st-first* tw)))
		   (setq *st-last* (list latency before after (- *st-calls* c0))))))
      (si:sb-on old))
    (list (and latency t)
	  (> (third *st-last*) (floor (second *st-last*) 2))
	  (st-control))))
