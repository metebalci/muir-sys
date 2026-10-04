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
;;;
;;; On the CADR, TRANSMIT-INT-PKT is too slow for that.  Measured on
;;; muir-sim's micro engine, a call takes about 500 us of the CADR's time
;;; (four to host 0, which only frees them, 1.9 ms), and a read of
;;; FIXNUM-MICROSECOND-TIME about 110 us; with both between the pushes, as
;;; QUUX's line has them, the gaps were 513, 502 and 1056 us and the list
;;; held 3 packets after the fourth push (of three pushes, 2).  The window,
;;; packet 0's frame on the cable after the interrupt that copies it in, is
;;; shorter: frames sent back to back start 1.79 ms apart on muir's
;;; --chaos-trace, the copy of the next one included.  So CTO-PUSH does just
;;; the part of TRANSMIT-INT-PKT that races with the microcode, for a host on
;;; this subnet: the word count and the host word, then the push onto the
;;; list's head by %STORE-CONDITIONAL and %CHAOS-WAKEUP
;;; (sys/network/chaos/chsncp.lisp:1941-1942, :1966-1975), and CTO-RUN times
;;; the pushes by the clock's low 16 bits, one Unibus read.  The pushes are
;;; then 251 us apart, and all four are on the list after the last one.

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

(defun cto-push (pkt)
  "Push PKT onto the transmit list as TRANSMIT-INT-PKT does for a host on this subnet."
  (setf (chaos:int-pkt-word-count pkt) (1+ (chaos:pkt-nwords pkt)))
  (setf (aref pkt (1- (chaos:int-pkt-word-count pkt))) (chaos:pkt-dest-address pkt))
  (without-interrupts
    (prog (old)
     loop (setq old (chaos:int-transmit-list))
	  (setf (chaos:int-pkt-thread pkt) old)
	  (or (%store-conditional chaos:int-transmit-list-pointer old pkt)
	      (go loop))
	  (system:%chaos-wakeup))))

(defun cto-clock ()
  "The microsecond clock's low 16 bits."
  (%unibus-read #o764120))

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
	    do (cto-push pkt)
	       (setf (car tail) (cto-clock)))
      ;; one walk of the list, taken at once: the first frame can end while
      ;; the list is walked, and on the CADR a count and four searches took
      ;; long enough that it did, and the window looked not entered with all
      ;; four pushed inside it (0, 2, 1, 0 on the cable)
      (let ((on (loop for pkt = (chaos:int-transmit-list) then (chaos:int-pkt-thread pkt)
		      while pkt collect pkt)))
	(setq length (length on)
	      window (loop for pkt in pkts always (memq pkt on))))
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
		      :gaps (loop for (a b) on times while b collect (logand #o177777 (- b a)))
		      :order (reverse order)))))

(defun cto (key)
  "KEY's value in what the last CTO-RUN saw."
  (getf *cto* key))

(compile 'cto-make-packet)
(compile 'cto-push)
(compile 'cto-clock)
(compile 'cto-on-transmit-list-p)
(compile 'cto-run)
