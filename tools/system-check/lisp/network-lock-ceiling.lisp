;;; -*- Mode:LISP; Package:USER; Base:10; Readtable:ZL -*-
;;; For the check network-lock-ceiling (tools/system-check/README.md): the
;;; network lock's priority ceiling, IP::WITH-NETWORK-LOCK (sys/network/ip/
;;; ether.lisp; QUUX's Ethernet contract, section 5.1, senders).  Each
;;; function holds the lock as a sender does, and is compiled as it is
;;; defined, since the stack's senders are compiled: interpreted, WITH-LOCK's
;;; LOCF of the lock reached another cell than the compiled code's, so a
;;; nested hold waited for ever (measured on band4, revision 16, micro).

(defun nlc-inside () (ip::with-network-lock (send current-process :priority)))
(defun nlc-holder () (ip::with-network-lock (eq ip::network-lock current-process)))
(defun nlc-nested () (ip::with-network-lock (ip::with-network-lock (send current-process :priority))))
(defun nlc-nested-around ()
  (ip::with-network-lock
    (list (send current-process :priority) (ip::with-network-lock 'inner) (send current-process :priority))))
(defun nlc-throw () (catch 'out (ip::with-network-lock (throw 'out nil))))
(defun nlc-error () (condition-case () (ip::with-network-lock (ferror nil "inside")) (error nil)))
(defun nlc-values () (multiple-value-list (ip::with-network-lock (values 1 2 3))))
(defun nlc-above (priority)
  "The section run at PRIORITY, above the ceiling: (BEFORE INSIDE AFTER)."
  (let ((own (send current-process :priority)))
    (unwind-protect
	(progn (send current-process :set-priority priority)
	       (list (send current-process :priority) (nlc-inside) (send current-process :priority)))
      (send current-process :set-priority own))))

;; the holder's place in si:active-processes: the ceiling moves the entry
;; itself (ip::network-raise-priority and ip::network-restore-priority), not
;; by :set-priority, so the cases check the list's order, that the entry is
;; where :set-priority to 25 puts it inside a section, and that it is back at
;; its own place after.
(defun nlc-order-ok ()
  "T if SI:ACTIVE-PROCESSES is in priority order, highest first, with the free entries
last and each entry's priority its process's; else the first entry out of place."
  (without-interrupts
    (do ((l si:active-processes (cdr l)) (last nil) (free nil))
	((null l) t)
      (let ((e (car l)))
	(cond ((null (first e)) (setq free t))
	      ((or free (and last (> (fourth e) last))
		   (not (= (fourth e) (si:process-priority (first e)))))
	       (return e))
	      (t (setq last (fourth e))))))))

(defun nlc-place ()
  (find-position-in-list (assq current-process si:active-processes) si:active-processes))

(defun nlc-order ()
  "The order checked before, inside and after a section."
  (let ((before (nlc-order-ok)))
    (list before (ip::with-network-lock (nlc-order-ok)) (nlc-order-ok))))

(defun nlc-places ()
  "(INSIDE AFTER): T if the entry's place inside a section is where :SET-PRIORITY to 25
puts it, and T if after the section it is back at its place before it."
  (let* ((own (send current-process :priority))
	 (before (nlc-place))
	 (here (ip::with-network-lock (nlc-place)))
	 (after (nlc-place))
	 inside)
    (send current-process :set-priority ip::%network-priority)
    (setq inside (= here (nlc-place)))
    (send current-process :set-priority own)
    (list inside (= after before))))

(defun nlc-fallback ()
  "A section that moves its own entry, by :SET-PRIORITY to 30: the restore finds the entry
off the place the raise left it and walks.  (PRIORITY-AFTER ORDER-OK)."
  (ip::with-network-lock (send current-process :set-priority 30))
  (list (send current-process :priority) (nlc-order-ok)))

;; compiled here when the file is loaded as source; a QFASL of it, under
;; lispm-check's --compile, has them compiled already.
(dolist (f '(nlc-inside nlc-holder nlc-nested nlc-nested-around nlc-throw nlc-error nlc-values nlc-above
	     nlc-order-ok nlc-place nlc-order nlc-places nlc-fallback))
  (unless (compiled-function-p (fdefinition f))
    (compile f)))
