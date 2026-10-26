;;; -*- Mode:LISP; Package:USER; Base:10; Readtable:ZL -*-
;;; For the check scheduler-arming (tools/system-check/README.md): the scheduler
;;; arms timer 1, the scheduler's timer, before each resume, for the earliest due
;;; time (QUUX's timer-driven scheduler, TS-5 to TS-9; sys/sys2/proces.lisp,
;;; SCHEDULER-ARM-PERIOD and SCHEDULER-ARM).  Before it, a pass of the scheduler
;;; came only when the running process waited, at a received Ethernet frame, or
;;; at the clock's sequence break, every 6 ticks with the collector on and once
;;; a second with it off.
;;;
;;; SA-PERIOD drives the pure arming function with chosen clocks: the pass
;;; began at THIS-TIME, a TIME, whose bits 16:0 are the microsecond clock's
;;; bits 30:14, so the pass's microsecond is built from it and an offset into
;;; its unit, and now is DELTA microseconds later.  SA-TURNS, SA-PASSES and
;;; SA-GC-WAKE measure the scheduler itself; the band runs without its network
;;; (--network files), so that no Ethernet frame gives a pass.  A pass is
;;; counted by the wait predicate of a process at priority 10 that never runs:
;;; the scheduler calls it once in each pass, before and after the change.

(defconst sa-mask31 2147483647)

(defun sa-now () (%microsecond-clock-ldb #o0037))
(defun sa-diff (later earlier)
  (let ((d (logand (- later earlier) sa-mask31)))
    (if (< d 1073741824) d (- d 2147483648))))

;;; the pure function

(defvar *sa-process* nil "A process that never runs, whose quantum the cases set.")

(defun sa-process (quantum remaining)
  (unless *sa-process*
    (setq *sa-process* (make-process "SA Quantum")))
  (send *sa-process* :set-quantum quantum)
  (setf (si:process-quantum-remaining *sa-process*) remaining)
  *sa-process*)

(defun sa-pass-us (this-time offset)
  "The pass's microsecond on the network's clock for a pass at THIS-TIME, OFFSET into its unit."
  (logior (ash (logand this-time #o377777) 14) offset))

(defun sa-period (this-time offset delta &key quantum remaining bound net-due net-from-pass
		  sleep-start sleep-interval)
  "SI:SCHEDULER-ARM-PERIOD with the pass at THIS-TIME, OFFSET microseconds into its unit,
now DELTA microseconds later; NET-FROM-PASS gives the network's due as microseconds from the
pass's start (modulo 2^31)."
  (let* ((pass-us (sa-pass-us this-time offset))
	 (now-us (logand (+ pass-us delta) sa-mask31)))
    (si:scheduler-arm-period this-time pass-us now-us
			     (and quantum (sa-process quantum remaining))
			     bound
			     (if net-from-pass (logand (+ pass-us net-from-pass) sa-mask31) net-due)
			     sleep-start sleep-interval)))

(defun sa-net-period (pass-us delta net-from-pass)
  "The pure function with only the network's due, the pass at PASS-US (any value)."
  (si:scheduler-arm-period 0 pass-us (logand (+ pass-us delta) sa-mask31) nil nil
			   (logand (+ pass-us net-from-pass) sa-mask31) nil nil))

;;; the counting process

(defvar *sa-calls* 0 "Calls of SA-COUNT-P, one a pass.")
(defvar *sa-sink* nil)

(defun sa-count-p ()
  (setq *sa-calls* (1+ *sa-calls*))
  nil)

(defun sa-setup ()
  "The collector off, and the counting process at priority 10."
  (gc-off)
  (unless (dolist (p si:all-processes) (when (equal (send p :name) "SA Count") (return t)))
    (process-run-function '(:name "SA Count" :priority 10)
			  #'(lambda () (process-wait "SA Count" #'sa-count-p))))
  (process-sleep 30)
  (and (plusp *sa-calls*) t))

(defun sa-fix ()
  (let ((s 0)) (dotimes (i 64) (setq s (logand (+ s i) 65535))) s))

(defun sa-cons ()
  (setq *sa-sink* (make-list 20)))

;;; (2) turns: two loops at priority 0, each wait a gap over 10 ms in its progress

(defvar *sa-done* nil)
(defvar *sa-max* nil)
(defvar *sa-waits* nil)

(defun sa-turn-loop (k seconds)
  (let* ((t0 (sa-now)) (last t0) (mx 0) (n 0))
    (do () ((>= (sa-diff last t0) (* seconds 1000000)))
      (sa-fix)
      (let* ((now (sa-now)) (d (sa-diff now last)))
	(when (> d 10000) (setq n (1+ n) mx (max mx d)))
	(setq last now)))
    (setf (aref *sa-max* k) mx)
    (setf (aref *sa-waits* k) n)
    (setf (aref *sa-done* k) t)))

(defun sa-both-done-p () (and (aref *sa-done* 0) (aref *sa-done* 1)))

(defun sa-turns (seconds)
  "Two loops in two processes at priority 0, for SECONDS: each loop's longest wait in us,
and the number of its waits."
  (setq *sa-done* (make-array 2) *sa-max* (make-array 2) *sa-waits* (make-array 2))
  (process-run-function "SA Loop A" #'sa-turn-loop 0 seconds)
  (process-run-function "SA Loop B" #'sa-turn-loop 1 seconds)
  (process-wait "SA Turns" #'sa-both-done-p)
  (list (aref *sa-max* 0) (aref *sa-max* 1) (aref *sa-waits* 0) (aref *sa-waits* 1)))

;;; (3) passes a second

(defvar *sa-stop* nil)
(defun sa-loop-until-stop ()
  (do () (*sa-stop*) (sa-fix)))

(defun sa-per-second (n us)
  "N in US microseconds, a second, rounded."
  (floor (+ (* n 1000000) (floor us 2)) us))

(defun sa-passes (seconds &rest quanta)
  "Passes a second, counted by SA-COUNT-P, while a loop runs in a process of each quantum
of QUANTA at priority 0 and the listener waits SECONDS; and SI:SCHEDULER-PASSES' count
a second, or NIL where there is none."
  (setq *sa-stop* nil)
  (dolist (q quanta)
    (process-run-function (list :name "SA Pass Loop" :quantum q) #'sa-loop-until-stop))
  (process-sleep 30)
  (let* ((counted (variable-boundp si:scheduler-passes))
	 (c0 *sa-calls*) (t0 (sa-now)) (s0 (and counted (symbol-value 'si:scheduler-passes)))
	 c1 t1 s1)
    (process-sleep (* 60 seconds))
    (setq c1 *sa-calls* t1 (sa-now) s1 (and counted (symbol-value 'si:scheduler-passes)))
    (setq *sa-stop* t)
    (process-sleep 10)
    (list (sa-per-second (- c1 c0) (sa-diff t1 t0))
	  (and counted (sa-per-second (- s1 s0) (sa-diff t1 t0))))))

;;; (5) the GC process after eden fills.  For each young collection the
;;; consing loop notes when it first sees eden full, and a process at priority
;;; 6 that never runs notes, from its wait predicate, the first pass that sees
;;; it full: the pass that wakes the GC process, at priority 5, which then
;;; takes the processor.  Timing the flip itself would add the collector's own
;;; work before it (finishing the last collection), which is not the
;;; scheduler's.  Each cycle ends at its flip.

(defvar *sa-flips* 0)
(defvar *sa-full-at* nil "By cycle (the flip count), the loop's first sight of eden full.")
(defvar *sa-pass-at* nil "By cycle, the first pass that saw eden full.")

(defun sa-note-flip ()
  (setq *sa-flips* (1+ *sa-flips*)))

(defun sa-eden-full-p ()
  (not (< si:%gc-words-consed-since-flip si:gc-wait-eden-words)))

(defun sa-observe-p ()
  (let ((k *sa-flips*))
    (when (and *sa-pass-at* (< k (array-length *sa-pass-at*))
	       (null (aref *sa-pass-at* k)) (sa-eden-full-p))
      (setf (aref *sa-pass-at* k) (sa-now))))
  nil)

(defun sa-cons-loop (flips)
  (let ((f0 *sa-flips*))
    (do () ((>= (- *sa-flips* f0) flips))
      (sa-cons)
      (let ((k *sa-flips*))
	(when (and (< k (array-length *sa-full-at*)) (null (aref *sa-full-at* k)) (sa-eden-full-p))
	  (setf (aref *sa-full-at* k) (sa-now)))))
    (setq *sa-done* t)))

(defun sa-done-p () *sa-done*)

(defun sa-gc-wake (quantum flips)
  "The GC on, eden at 200,000 words, a consing loop in a process of QUANTUM: for each of
FLIPS young collections after the first, the microseconds from the loop's first sight of
eden full to the first pass that saw it (0 when the pass saw it first)."
  (setq si:gc-eden-size 200000)
  (gc-on t)
  (unless (member '(sa-note-flip) si:gc-every-flip-list)
    (push '(sa-note-flip) si:gc-every-flip-list))
  (let ((n (+ *sa-flips* flips 2)))
    (setq *sa-full-at* (make-array n) *sa-pass-at* (make-array n) *sa-done* nil))
  (unless (dolist (p si:all-processes) (when (equal (send p :name) "SA Observe") (return t)))
    (process-run-function '(:name "SA Observe" :priority 6)
			  #'(lambda () (process-wait "SA Observe" #'sa-observe-p))))
  ;; the first cycle sets eden's new size at its flip; the ones after it are measured
  (let ((k0 (1+ *sa-flips*)))
    (process-run-function (list :name "SA Cons" :quantum quantum) #'sa-cons-loop (1+ flips))
    (process-wait "SA GC" #'sa-done-p)
    (let ((w nil))
      (dotimes (i flips)
	(let ((full (aref *sa-full-at* (+ k0 i))) (pass (aref *sa-pass-at* (+ k0 i))))
	  (push (if (and full pass) (max 0 (sa-diff pass full)) (list full pass)) w)))
      (nreverse w))))
