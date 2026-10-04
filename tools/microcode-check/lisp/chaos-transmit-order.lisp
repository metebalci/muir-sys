;;; -*- Mode:LISP; Package:USER; Base:10; Lowercase:T -*-

;;; The Chaosnet transmit list's check (tools/microcode-check/README.md,
;;; cases/chaos-transmit-order.cases).  TRANSMIT-INT-PKT pushes a packet onto
;;; the head of the transmit list; the microcode's transmit interrupt
;;; (CHAOS-XMT-0, CHAOS-XMT-DONE, sys/ucadr/uc-chaos.lisp) sends a packet,
;;; leaves it on the list while it is on the cable, and takes it off when its
;;; Transmit Done comes.  CTO-RUN pushes four full-length UNC packets back to
;;; back, each to its own host that is not there (177270 to 177273, so that
;;; muir's --chaos-trace tells them apart on the cable), and then watches the
;;; list until all four have left it, noting the order in which they left.
;;; Sent oldest first, they leave in the order they were pushed, (0 1 2 3).
;;; A microcode that sends and pops the head sends 0, then frees 3 unsent at
;;; 0's Transmit Done, sends 2, 1 and 0 again: they leave as (3 2 1 0).
;;;
;;; The race needs the pushes to land while packet 0 is on the cable: the
;;; check holds only when all four are on the list after the last push (the
;;; window entered), which CTO-RUN measures, with the microseconds between
;;; the pushes.

(defvar *cto* nil "What the last CTO-RUN saw, a property list.")

(defun cto-make-packet (host)
  "A full-length UNC int-pkt to HOST, from this machine, index 0."
  (let ((pkt (chaos:allocate-int-pkt)))
    (setf (chaos:pkt-opcode pkt) chaos:unc-op)
    (setf (chaos:pkt-fwd-count pkt) 0)
    (setf (chaos:pkt-nbytes pkt) chaos:max-data-bytes-per-pkt)
    (setf (chaos:pkt-dest-address pkt) host)
    (setf (chaos:pkt-dest-index-num pkt) 0)
    (setf (chaos:pkt-source-address pkt) chaos:my-address)
    (setf (chaos:pkt-source-index-num pkt) 0)
    (setf (chaos:pkt-num pkt) 0)
    (setf (chaos:pkt-ack-num pkt) 0)
    pkt))

(defun cto-on-transmit-list-p (pkt)
  (chaos:int-pkt-list-memq pkt (chaos:int-transmit-list)))

(defun cto-run (&optional (n 4) (timeout-us 2000000))
  "Push N packets back to back and note the order in which they leave the transmit list."
  (let ((pkts (loop for i below n collect (cto-make-packet (+ #o177270 i))))
	(times (make-list n))
	(order nil) length window)
    ;; start from an empty transmit list, so that the first push is sent at once
    (process-wait-with-timeout "Transmit list empty" 600
			       #'(lambda () (null (chaos:int-transmit-list))))
    (without-interrupts
      (loop for pkt in pkts
	    for tail on times
	    do (chaos:transmit-int-pkt pkt)
	       (setf (car tail) (time:fixnum-microsecond-time)))
      (setq length (chaos:int-pkt-list-length (chaos:int-transmit-list))
	    window (loop for pkt in pkts always (cto-on-transmit-list-p pkt)))
      (loop with start = (time:fixnum-microsecond-time)
	    with left = pkts
	    ;; stop at the timeout, and at a wrap of the microsecond clock
	    while (and left (< -1 (- (time:fixnum-microsecond-time) start) timeout-us))
	    do (dolist (pkt left)
		 (unless (cto-on-transmit-list-p pkt)
		   (push (position pkt pkts) order)
		   (setq left (remove pkt left))))))
    (setq *cto* (list :window (if window "window entered" "window not entered")
		      :length length
		      :gaps (loop for (a b) on times while b collect (- b a))
		      :order (reverse order)))))

(defun cto (key)
  "KEY's value in what the last CTO-RUN saw."
  (getf *cto* key))

(compile 'cto-make-packet)
(compile 'cto-on-transmit-list-p)
(compile 'cto-run)
