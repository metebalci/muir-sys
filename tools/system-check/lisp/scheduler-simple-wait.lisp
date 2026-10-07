;;; -*- Mode:LISP; Package:USER; Base:10; Readtable:ZL -*-
;;; For the check scheduler-simple-wait (tools/system-check/README.md): a
;;; simple process whose function would wait does not stop the scheduler
;;; (sys/sys2/proces.lisp, PROCESS-SCHEDULER-FOR-CADR).  A simple process's
;;; function runs in the scheduler, which cannot wait; PROCESS-WAIT there
;;; throws to PROCESS-WAIT-IN-SCHEDULER, which had a catch only around the wait
;;; functions, so the scheduler stopped in the cold load stream's debugger,
;;; and every process and the network with it.  The dormant file connection
;;; GC, a simple process, did so after a flip, waiting for a flavor's method
;;; table that the TELNET server held while it rehashed it (FULL-GC typed
;;; right after GC-IMMEDIATELY: no answer, the TELNET connection given up).

(defvar *ssw-lock* nil "A lock: NIL, or the process holding it.")
(defvar *ssw-runs* 0 "How often the simple process's function got the lock.")
(defvar *ssw-simple* nil "The simple process.")

(defun ssw-restart-scheduler ()
  "Start the scheduler afresh, as every boot does (SI:PROCESS-INITIALIZE), so that a
PROCESS-SCHEDULER-FOR-CADR loaded since this band's boot runs.  Only a band built
before the change needs it.  As at the boot, INHIBIT-SCHEDULING-FLAG is T, its global
value, until the scheduler has run: a sequence break taken in the fresh scheduler
before its WITHOUT-INTERRUPTS binds the flag halts the machine (SBSER), which a
binding of this process's does not prevent, since the scheduler's stack group does
not see it."
  (setq inhibit-scheduling-flag t)
  (stack-group-preset si:scheduler-stack-group (si:appropriate-process-scheduler))
  (funcall si:scheduler-stack-group)
  (setq inhibit-scheduling-flag nil)
  t)

(defun ssw-hold (locative seconds)
  "Hold the lock LOCATIVE points to for SECONDS."
  (process-lock locative)
  (process-sleep (* 60 seconds))
  (process-unlock locative))

(defun ssw-simple-top ()
  "The simple process's function: count a run with the lock, then wait for ever."
  (with-lock (*ssw-lock*)
    (incf *ssw-runs*))
  (si:set-process-wait current-process #'false nil))

(defun ssw-start (seconds)
  "A process holds *SSW-LOCK* for SECONDS; then a simple process starts whose function
takes the lock.  Returns (HELD RUNS): the lock held, and no run yet."
  (setq *ssw-runs* 0)
  (process-run-function "SSW holder" #'ssw-hold (locf *ssw-lock*) seconds)
  (process-sleep 30)
  (setq *ssw-simple* (make-process "SSW simple" :simple-p t))
  (send *ssw-simple* :preset 'ssw-simple-top)
  (send *ssw-simple* :run-reason 'ssw)
  (process-sleep 30)
  (list (not (null *ssw-lock*)) *ssw-runs*))

(defun ssw-end ()
  (send *ssw-simple* :revoke-run-reason 'ssw)
  t)

(defun ssw-hold-host-method-table (seconds)
  "Hold the method table of the first pathname host's flavor for SECONDS, as the
TELNET server held one while it rehashed it: the dormant file connection GC, every
minute, sends that host :SEND-IF-HANDLES, which looks the operation up in that table."
  (let ((table (si:flavor-method-hash-table
		 (si:instance-flavor (car fs:*pathname-host-list*)))))
    (process-run-function "SSW method table" #'ssw-hold
			  (locf (si:hash-table-lock table)) seconds)
    (process-sleep 30)
    (not (null (si:hash-table-lock table)))))
