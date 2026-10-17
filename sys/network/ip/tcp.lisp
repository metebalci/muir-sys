;;; -*- Mode:LISP; Package:INTERNET; Base:10; Readtable:ZL -*-
;;;
;;; This is SYS: NETWORK; IP; TCP
;;;
;;; quux revision 16: TCP over IPv4 (RFC 9293; QUUX's Ethernet contract,
;;; sections 5.5 and 6): passive open only, MSS 1460, an 8,192-byte buffer each
;;; way for each connection, in-order delivery only, RFC 6298's retransmission,
;;; RFC 5681's congestion control, sender and receiver silly window avoidance,
;;; a persist timer, TIME-WAIT records apart from the connections, and RFC
;;; 6528's ISN.  the streams, the servers and the control session's functions
;;; are in SYS: NETWORK; IP; SERVERS.
;;;
;;; everything here runs under the network lock: received segments in the
;;; network process's pass, the timers after them, and a server's reads and
;;; writes when it takes the lock.  each segment received is acknowledged once
;;; for its batch (section 5.1), unless a segment sent in the batch carried the
;;; acknowledgment.  the device fills in the checksum (section 2.4).
;;;
;;; sequence numbers are fixnums, the 32 bits with the sign bit included, and
;;; their arithmetic is modulo 2^32 through %pointer-plus and
;;; %pointer-difference, which keep 32 bits and cons nothing (section 5.5).
;;; times are the network clock's microseconds (SYS: NETWORK; IP; ETHER).

;;;; Sequence arithmetic, modulo 2^32

(defsubst seq+ (a n) (%pointer-plus a n))
(defsubst seq- (a b) "A - B modulo 2^32, as a signed difference." (%pointer-difference a b))
(defsubst seq< (a b) (minusp (%pointer-difference a b)))
(defsubst seq<= (a b) (not (minusp (%pointer-difference b a))))

(defun seq-from-unsigned (n)
  "A sequence number as these functions hold it, from 0 to 2^32 - 1 as on the wire."
  (if (> n #o17777777777) (- n #o40000000000) n))

(defun seq-to-unsigned (n)
  (if (minusp n) (+ n #o40000000000) n))

;;;; Constants (section 5.5)

(defconst %tcp-mss 1460 "MMS_R: the MSS the band offers, on its SYN-ACK only.")
(defconst %tcp-default-mss 536 "The send MSS when the peer offers none (MUST-15).")
(defconst %tcp-buffer 8192 "Bytes in each connection's receive buffer and send buffer.")
(defconst %tcp-connections 8 "Connections from SYN-RECEIVED to LAST-ACK, at most.")
(defconst %tcp-backlog 4 "Half-open connections on one listener, at most.")
(defconst %tcp-time-wait-records 64)
(defconst %tcp-time-wait (* 60. 1000000.) "TIME-WAIT: 60 s, an MSL of 30 s, as Linux's.")
(defconst %tcp-fin-wait-2 (* 60. 1000000.) "FIN-WAIT-2's end after the band's FIN.")
(defconst %tcp-first-rto 1000000. "RFC 6298's first RTO, 1 s.")
(defconst %tcp-min-rto 200000. "The RTO's floor, 200 ms, Linux's (RFC 6298's 1 s is a SHOULD).")
(defconst %tcp-max-rto (* 60. 1000000.) "The RTO's ceiling, and the persist timer's.")
(defconst %tcp-r1 3 "Retransmissions after which the next hop's ARP entry goes (MUST-20).")
(defconst %tcp-r2 (* 100. 1000000.) "R2 for data: 100 s (MUST-20).")
(defconst %tcp-synack-r2 (* 180. 1000000.) "R2 for a SYN-ACK: 180 s (MUST-23).")
(defconst %tcp-override (* 200. 1000.) "MUST-38's override timer, 200 ms.")
(defconst %tcp-first-tx-slots 32 "Segments in flight a connection keeps the first sending of.")

(defconst %tcp-fin #o1)
(defconst %tcp-syn #o2)
(defconst %tcp-rst #o4)
(defconst %tcp-psh #o10)
(defconst %tcp-ack #o20)
(defconst %tcp-urg #o40)

;;;; Connections

;; a connection is an array of 54 words, read and set through these substs.
;; no defstruct: the cross build cannot give a new structure to the compile
;; for the target without changing the builder's world (sys/cold/cross.lisp,
;; cross-declare-definitions), and a subst it gives.
;; the four-tuple: the band's address is MY-ADDRESS
(defsubst tcb-remote (c) (aref c 0))
(defsubst tcb-rport (c) (aref c 1))
(defsubst tcb-lport (c) (aref c 2))
;; :syn-received :established :fin-wait-1 :fin-wait-2 :close-wait :closing
;; :last-ack, or :closed when gone
(defsubst tcb-state (c) (aref c 3))
(defsubst tcb-irs (c) (aref c 4))
(defsubst tcb-iss (c) (aref c 5))
(defsubst tcb-rcv-nxt (c) (aref c 6))
(defsubst tcb-snd-una (c) (aref c 7))
(defsubst tcb-snd-nxt (c) (aref c 8))
(defsubst tcb-max-sent (c) (aref c 9))		;the end of the furthest byte sent
(defsubst tcb-mss (c) (aref c 10))		;the effective send MSS
(defsubst tcb-peer-window (c) (aref c 11))
(defsubst tcb-max-window (c) (aref c 12))
(defsubst tcb-cwnd (c) (aref c 13))
(defsubst tcb-ssthresh (c) (aref c 14))
(defsubst tcb-send-buffer (c) (aref c 15))
(defsubst tcb-send-head (c) (aref c 16))
(defsubst tcb-send-count (c) (aref c 17))
(defsubst tcb-pushed (c) (aref c 18))		;T while queued data has been pushed
(defsubst tcb-receive-buffer (c) (aref c 19))
(defsubst tcb-receive-head (c) (aref c 20))
(defsubst tcb-receive-count (c) (aref c 21))
(defsubst tcb-adv-edge (c) (aref c 22))		;the right edge last advertised, or NIL
(defsubst tcb-rcv-up (c) (aref c 23))		;the urgent pointer received, or NIL
(defsubst tcb-srtt (c) (aref c 24))
(defsubst tcb-rttvar (c) (aref c 25))
(defsubst tcb-rto-base (c) (aref c 26))
(defsubst tcb-backoff (c) (aref c 27))
(defsubst tcb-retries (c) (aref c 28))
(defsubst tcb-timed-end (c) (aref c 29))		;the one segment being timed, or NIL
(defsubst tcb-timed-sent (c) (aref c 30))		;the one segment being timed, or NIL
(defsubst tcb-first-tx-end (c) (aref c 31))
(defsubst tcb-first-tx-time (c) (aref c 32))
(defsubst tcb-first-tx-head (c) (aref c 33))
(defsubst tcb-first-tx-count (c) (aref c 34))
(defsubst tcb-synack-tx (c) (aref c 35))		;the first SYN-ACK's sending
(defsubst tcb-r2 (c) (aref c 36))		;this connection's R2 (MUST-21's keyword)
(defsubst tcb-rexmt-due (c) (aref c 37))
(defsubst tcb-persist-due (c) (aref c 38))
(defsubst tcb-override-due (c) (aref c 39))
(defsubst tcb-r2-due (c) (aref c 40))
(defsubst tcb-synack-r2-due (c) (aref c 41))
(defsubst tcb-fin-wait-2-due (c) (aref c 42))
(defsubst tcb-persist-backoff (c) (aref c 43))
(defsubst tcb-forced (c) (aref c 44))		;the next segment goes whatever MUST-38 says
(defsubst tcb-close-requested (c) (aref c 45))		;the application closed: a FIN after the data
(defsubst tcb-fin-seq (c) (aref c 46))		;our FIN's sequence number and sending, once sent
(defsubst tcb-fin-tx (c) (aref c 47))		;our FIN's sequence number and sending, once sent
(defsubst tcb-ack-pending (c) (aref c 48))		;an ACK is owed for this batch
(defsubst tcb-peer-fin (c) (aref c 49))		;the peer's FIN has come: the stream reads EOF
(defsubst tcb-error (c) (aref c 50))		;the signal name of what ended the connection, or NIL
(defsubst tcb-application-closed (c) (aref c 51))		;the application's own close has been made
(defsubst tcb-stream (c) (aref c 52))
(defsubst tcb-server-process (c) (aref c 53))

(defconst %tcb-words 54)

(defun make-tcb-internal (&key remote rport lport (state :syn-received) irs iss rcv-nxt snd-una snd-nxt max-sent mss peer-window max-window cwnd ssthresh)
  "A connection, its other words at their initial values."
  (let ((c (make-array %tcb-words)))
    (setf (aref c 0) remote)
    (setf (aref c 1) rport)
    (setf (aref c 2) lport)
    (setf (aref c 3) state)
    (setf (aref c 4) irs)
    (setf (aref c 5) iss)
    (setf (aref c 6) rcv-nxt)
    (setf (aref c 7) snd-una)
    (setf (aref c 8) snd-nxt)
    (setf (aref c 9) max-sent)
    (setf (aref c 10) mss)
    (setf (aref c 11) peer-window)
    (setf (aref c 12) max-window)
    (setf (aref c 13) cwnd)
    (setf (aref c 14) ssthresh)
    (setf (aref c 15) (make-array %tcp-buffer :type 'art-8b))
    (setf (aref c 16) 0)
    (setf (aref c 17) 0)
    (setf (aref c 18) nil)
    (setf (aref c 19) (make-array %tcp-buffer :type 'art-8b))
    (setf (aref c 20) 0)
    (setf (aref c 21) 0)
    (setf (aref c 22) nil)
    (setf (aref c 23) nil)
    (setf (aref c 24) nil)
    (setf (aref c 25) nil)
    (setf (aref c 26) %tcp-first-rto)
    (setf (aref c 27) 0)
    (setf (aref c 28) 0)
    (setf (aref c 29) nil)
    (setf (aref c 30) nil)
    (setf (aref c 31) (make-array %tcp-first-tx-slots))
    (setf (aref c 32) (make-array %tcp-first-tx-slots))
    (setf (aref c 33) 0)
    (setf (aref c 34) 0)
    (setf (aref c 35) nil)
    (setf (aref c 36) %tcp-r2)
    (setf (aref c 37) nil)
    (setf (aref c 38) nil)
    (setf (aref c 39) nil)
    (setf (aref c 40) nil)
    (setf (aref c 41) nil)
    (setf (aref c 42) nil)
    (setf (aref c 43) 0)
    (setf (aref c 44) nil)
    (setf (aref c 45) nil)
    (setf (aref c 46) nil)
    (setf (aref c 47) nil)
    (setf (aref c 48) nil)
    (setf (aref c 49) nil)
    (setf (aref c 50) nil)
    (setf (aref c 51) nil)
    (setf (aref c 52) nil)
    (setf (aref c 53) nil)
    c))

(defvar tcp-connections nil "Every connection from SYN-RECEIVED to LAST-ACK.")
(defvar tcp-listeners nil
  "Elements (PORT NAME FUNCTION SWITCH): a SYN to PORT opens a connection while SWITCH,
a variable, is not NIL (or always, if SWITCH is NIL), and once the connection is
ESTABLISHED FUNCTION runs on it in a process of its own (SYS: NETWORK; IP; SERVERS).")

(defun tcp-listener (port)
  "The listener on PORT, if one is open: a closed port gets RST."
  (let ((l (assoc port tcp-listeners)))
    (and l (or (null (fourth l)) (symbol-value (fourth l))) l)))

;; TIME-WAIT records (section 5.5): the four-tuple, the final RCV.NXT and SND.NXT,
;; and the end.  a free record has REMOTE NIL.
(defvar tcp-tw-remote (make-array %tcp-time-wait-records))
(defvar tcp-tw-rport (make-array %tcp-time-wait-records))
(defvar tcp-tw-lport (make-array %tcp-time-wait-records))
(defvar tcp-tw-rcv-nxt (make-array %tcp-time-wait-records))
(defvar tcp-tw-snd-nxt (make-array %tcp-time-wait-records))
(defvar tcp-tw-end (make-array %tcp-time-wait-records))
(defvar tcp-tw-started (make-array %tcp-time-wait-records) "For the oldest's early end.")

;; the test hooks of the control session (section 9, T1, the way in)
(defvar *isn-of-next-connection* nil
  "NIL, or an ISN as on the wire, 0 to 2^32 - 1: the next SYN answered with a SYN-ACK
takes it, and it is then NIL (a test hook; section 9, T1).")
(defvar *r2-of-next-connection* nil
  "NIL, or a number of seconds: the next connection the test echo service accepts gets it
as its R2 (MUST-21's keyword, :R2), and it is then NIL (a test hook; section 9, T1).")

(defvar tcp-segments-received 0)
(defvar tcp-segments-sent 0)
(defvar tcp-segments-dropped 0 "Segments dropped for an illegal option length or a bad offset.")
(defvar tcp-refused-silently 0 "SYNs refused silently: MUST-63's sources, a full backlog.")

(defun tcp-find (remote rport lport)
  (dolist (c tcp-connections)
    (when (and (= (tcb-remote c) remote) (= (tcb-rport c) rport) (= (tcb-lport c) lport))
      (return c))))

(defun tcp-remove (c error)
  "Take C out of the table: its server's reads and writes then end, with the signal
ERROR, or with EOF if it is NIL."
  (setq tcp-connections (delq c tcp-connections))
  (setf (tcb-state c) :closed
	(tcb-error c) (or (tcb-error c) error)))

;;;; The ISN (RFC 6528; MUST-8)

(defvar tcp-isn-key 0 "The ISN's key, drawn at the network's start from the RTC and the clock.")
(defvar tcp-clock-high 0 "Wraps of the network clock's 31 bits, for the ISN's 32-bit clock.")
(defvar tcp-clock-last 0)

(defun tcp-clock-track ()
  "Count the network clock's wraps: called in every pass and at every ISN, and the
timers wake the process at least every 15 minutes."
  (let ((now (network-now)))
    (when (< now tcp-clock-last) (incf tcp-clock-high))
    (setq tcp-clock-last now)
    now))

(defsubst shl32 (x k)
  "X shifted left K bits, modulo 2^32, as a fixnum."
  (%logdpb (%logldb (- 32. k) x) (+ (ash k 6) (- 32. k)) 0))

(defsubst shr32 (x k)
  "X shifted right K bits, logically."
  (%logldb (+ (ash k 6) (- 32. k)) x))

(defun tcp-mix (h x)
  "Mix the fixnum X into the hash H: a xorshift round, not cryptographic."
  (setq h (logxor h x))
  (setq h (logxor h (shl32 h 13.)))
  (setq h (logxor h (shr32 h 17.)))
  (logxor h (shl32 h 5)))

(defun tcp-isn (remote rport lport)
  "RFC 6528: the clock in 4 us units plus a keyed hash of the four-tuple; or the test
hook's ISN, once."
  (if *isn-of-next-connection*
      (prog1 (seq-from-unsigned *isn-of-next-connection*)
	     (setq *isn-of-next-connection* nil))
    (let* ((now (tcp-clock-track))
	   ;; the 4 us clock: the 34-bit microseconds from the wraps and the
	   ;; 31 bits, over 4, modulo 2^32
	   (clock (%logdpb (logand tcp-clock-high 7) #o3503 (ash now -2)))
	   (h tcp-isn-key))
      (setq h (tcp-mix h remote))
      (setq h (tcp-mix h (%logdpb rport #o2020 lport)))
      (setq h (tcp-mix h tcp-isn-key))
      (seq+ clock h))))

;;;; Sending segments

(defun tcp-raw-send (remote sport dport seq ack flags window &optional (data-from nil)
		     (data-offset 0) (data-length 0) (mss-option nil))
  "Send one TCP segment.  Its data, DATA-LENGTH bytes, come from connection
DATA-FROM's send buffer, DATA-OFFSET bytes past SND.UNA's first byte.  The checksum
is the device's."
  (multiple-value-bind (slot b o) (ipv4-datagram-slot)
    (let ((header (if mss-option 24 20)))
      (put-16 b o sport)
      (put-16 b (+ o 2) dport)
      (put-32 b (+ o 4) seq)
      (put-32 b (+ o 8) (if (zerop (logand flags %tcp-ack)) 0 ack))
      (put-16 b (+ o 12) (dpb (floor header 4) #o1404 flags))
      (put-16 b (+ o 14) window)
      (put-16 b (+ o 16) 0)
      (put-16 b (+ o 18) 0)
      (when mss-option
	(put-8 b (+ o 20) 2)
	(put-8 b (+ o 21) 4)
	(put-16 b (+ o 22) mss-option))
      (when (plusp data-length)
	;; the send buffer is a ring: the data may wrap at its end.
	(let* ((buffer (tcb-send-buffer data-from))
	       (start (logand (+ (tcb-send-head data-from) data-offset) (1- %tcp-buffer)))
	       (first (min data-length (- %tcp-buffer start))))
	  (copy-array-portion buffer start (+ start first) b (+ o header) (+ o header first))
	  (when (< first data-length)
	    (copy-array-portion buffer 0 (- data-length first)
				b (+ o header first) (+ o header data-length)))))
      (incf tcp-segments-sent)
      (ipv4-send slot remote %ipv4-protocol-tcp (+ header data-length)))))

(defun tcp-window (c)
  "The receive window to advertise: the free space of the 8,192-byte buffer, its right
edge moved only by at least the connection's effective send MSS (receiver silly window
avoidance, MUST-39; section 5.5)."
  (let* ((free (- %tcp-buffer (tcb-receive-count c)))
	 (edge (seq+ (tcb-rcv-nxt c) free))
	 (adv (tcb-adv-edge c)))
    (when (or (null adv) (>= (seq- edge adv) (tcb-mss c)))
      (setf (tcb-adv-edge c) edge))
    (let ((w (seq- (tcb-adv-edge c) (tcb-rcv-nxt c))))
      (if (minusp w) 0 (min w %tcp-buffer)))))

(defun tcp-send (c flags seq &optional (data-offset 0) (data-length 0))
  "A segment of connection C, acknowledging RCV.NXT."
  (setf (tcb-ack-pending c) nil)
  (tcp-raw-send (tcb-remote c) (tcb-lport c) (tcb-rport c) seq (tcb-rcv-nxt c)
		flags (if (zerop (logand flags %tcp-syn)) (tcp-window c) %tcp-buffer)
		c data-offset data-length
		(and (not (zerop (logand flags %tcp-syn))) %tcp-mss)))

(defun tcp-send-ack (c)
  (tcp-send c %tcp-ack (tcb-snd-nxt c)))

(defun tcp-send-synack (c)
  (tcp-send c (logior %tcp-syn %tcp-ack) (tcb-iss c))
  (unless (tcb-synack-tx c)
    (let ((now (network-now)))
      (setf (tcb-synack-tx c) now
	    ;; R2 for a SYN-ACK, 180 s from its first sending: back to LISTEN.
	    (tcb-synack-r2-due c) (network-time-plus now %tcp-synack-r2))
      (network-note-timer (tcb-synack-r2-due c))))
  (unless (tcb-rexmt-due c) (tcp-arm c)))

;;;; RFC 6298

(defun tcp-rto (c)
  (let ((rto (tcb-rto-base c)))
    (dotimes (i (tcb-backoff c))
      (setq rto (min (* 2 rto) %tcp-max-rto)))
    (min rto %tcp-max-rto)))

(defun tcp-arm (c)
  "Start the retransmission timer from now."
  (setf (tcb-rexmt-due c) (network-time-plus (network-now) (tcp-rto c)))
  (network-note-timer (tcb-rexmt-due c)))

(defun tcp-sample (c r)
  "An RTT sample of R us (RFC 6298 section 2)."
  (cond ((null (tcb-srtt c))
	 (setf (tcb-srtt c) r (tcb-rttvar c) (floor r 2)))
	(t
	 (setf (tcb-rttvar c) (floor (+ (* 3 (tcb-rttvar c)) (abs (- (tcb-srtt c) r))) 4))
	 (setf (tcb-srtt c) (floor (+ (* 7 (tcb-srtt c)) r) 8))))
  (setf (tcb-rto-base c) (min (max %tcp-min-rto (+ (tcb-srtt c) (max 1 (* 4 (tcb-rttvar c)))))
			      %tcp-max-rto)))

(defun tcp-r2-arm (c)
  "R2: from the first sending of the oldest unacknowledged segment."
  (cond ((zerop (tcb-first-tx-count c))
	 (setf (tcb-r2-due c) nil))
	(t
	 (setf (tcb-r2-due c)
	       (network-time-plus (aref (tcb-first-tx-time c) (tcb-first-tx-head c)) (tcb-r2 c)))
	 (network-note-timer (tcb-r2-due c)))))

(defun tcp-sent-new (c start end)
  "A segment [START, END) sent: timed if it is new data (Karn: a resent segment is
never timed), and its first sending noted."
  (when (seq< (tcb-max-sent c) end)
    (let ((now (network-now)))
      (when (and (not (seq< start (tcb-max-sent c))) (null (tcb-timed-end c)))
	(setf (tcb-timed-end c) end (tcb-timed-sent c) now))
      (when (< (tcb-first-tx-count c) %tcp-first-tx-slots)
	(let ((i (logand (+ (tcb-first-tx-head c) (tcb-first-tx-count c)) (1- %tcp-first-tx-slots))))
	  (setf (aref (tcb-first-tx-end c) i) end
		(aref (tcb-first-tx-time c) i) now)
	  (incf (tcb-first-tx-count c))))
      (setf (tcb-max-sent c) end)
      (when (= (tcb-first-tx-count c) 1)
	(tcp-r2-arm c)))))

;;;; Output: MUST-38, the windows, the persist and override timers

(defun tcp-flight (c)
  (let ((flight (seq- (tcb-snd-nxt c) (tcb-snd-una c))))
    (if (eq (tcb-state c) :syn-received) (1- flight) flight)))

(defun tcp-output (c)
  "Send what sender silly window avoidance allows (RFC 9293 3.8.6.2.1, MUST-38): (1) a
full MSS; (2) all that is queued, pushed, if it fits now; (3) at least half the largest
window the peer has offered; (4) the rest when the override timer expires.  Always
within the peer's window and the congestion window; the FIN after the data once the
application has closed.  Returns T if anything was sent."
  (let ((sent nil))
    (loop
      (when (or (eq (tcb-state c) :syn-received) (eq (tcb-state c) :closed) (tcb-fin-seq c))
	(return sent))
      (let* ((flight (tcp-flight c))
	     (unsent (- (tcb-send-count c) flight)))
	(when (<= unsent 0)
	  (when (and (tcb-close-requested c) (memq (tcb-state c) '(:established :close-wait)))
	    ;; the close: a FIN after the data, which takes a sequence number.
	    (setf (tcb-fin-seq c) (tcb-snd-nxt c)
		  (tcb-fin-tx c) (network-now))
	    (tcp-send c (logior %tcp-fin %tcp-ack) (tcb-snd-nxt c))
	    (setf (tcb-snd-nxt c) (seq+ (tcb-snd-nxt c) 1))
	    (tcp-sent-new c (tcb-fin-seq c) (tcb-snd-nxt c))
	    (setf (tcb-state c) (if (eq (tcb-state c) :established) :fin-wait-1 :last-ack))
	    (unless (tcb-rexmt-due c) (tcp-arm c))
	    (return t))
	  (return sent))
	(let ((usable (- (min (tcb-peer-window c) (tcb-cwnd c)) flight)))
	  (when (<= usable 0)
	    (when (and (zerop (tcb-peer-window c)) (zerop flight))
	      (tcp-persist-start c))
	    (return sent))
	  (let* ((n (min (tcb-mss c) usable unsent))
		 (rule-1 (>= (min unsent usable) (tcb-mss c)))
		 (rule-2 (and (tcb-pushed c) (<= unsent usable)))
		 (rule-3 (>= (* 2 (min unsent usable)) (tcb-max-window c))))
	    (unless (or rule-1 rule-2 rule-3 (tcb-forced c))
	      (when (tcb-pushed c) (tcp-override-start c))
	      (return sent))
	    (setf (tcb-forced c) nil)
	    (let ((start (tcb-snd-nxt c)))
	      (tcp-send c (logior %tcp-ack (if (and (= n unsent) (tcb-pushed c)) %tcp-psh 0))
			start flight n)
	      (setf (tcb-snd-nxt c) (seq+ start n))
	      (tcp-sent-new c start (tcb-snd-nxt c)))
	    (setq sent t)
	    (unless (tcb-rexmt-due c) (tcp-arm c))))))))

(defun tcp-persist-start (c)
  "The persist timer: probes of a zero window from one RTO, doubling to 60 s, never
aborting while they are answered (MUST-35 to -37)."
  (unless (tcb-persist-due c)
    (tcp-persist-arm c)))

(defun tcp-persist-arm (c)
  (let ((delay (tcb-rto-base c)))
    (dotimes (i (tcb-persist-backoff c))
      (setq delay (min (* 2 delay) %tcp-max-rto)))
    (setf (tcb-persist-due c) (network-time-plus (network-now) (min delay %tcp-max-rto)))
    (network-note-timer (tcb-persist-due c))))

(defun tcp-persist-fire (c)
  ;; a probe of one octet of new data at the right edge (RFC 9293 3.8.6.1).
  (let ((flight (tcp-flight c)))
    (if (> (tcb-send-count c) flight)
	(tcp-send c %tcp-ack (tcb-snd-nxt c) flight 1)
      (tcp-send c %tcp-ack (seq+ (tcb-snd-una c) -1)))
    (incf (tcb-persist-backoff c))
    (tcp-persist-arm c)))

(defun tcp-override-start (c)
  "MUST-38's override timer: started when pushed data is first held back while the
peer's window is open; an ACK that leaves the data held does not restart it."
  (unless (tcb-override-due c)
    (setf (tcb-override-due c) (network-time-plus (network-now) %tcp-override))
    (network-note-timer (tcb-override-due c))))

;;;; ACKs and windows

(defun tcp-acked (c ack)
  "An ACK of new data: the send buffer, the RTT sample, the timer restarted (RFC 6298
5.3), slow start or congestion avoidance (RFC 5681)."
  (let ((n (seq- ack (tcb-snd-una c)))
	(now (network-now)))
    ;; the SYN and the FIN take a number but no byte of the buffer.
    (let ((bytes (min n (tcb-send-count c))))
      (setf (tcb-send-head c) (logand (+ (tcb-send-head c) bytes) (1- %tcp-buffer))
	    (tcb-send-count c) (- (tcb-send-count c) bytes)))
    (setf (tcb-snd-una c) ack)
    (when (seq< (tcb-snd-nxt c) ack) (setf (tcb-snd-nxt c) ack))
    (when (and (tcb-timed-end c) (not (seq< ack (tcb-timed-end c))))
      (tcp-sample c (network-time-difference now (tcb-timed-sent c)))
      (setf (tcb-timed-end c) nil))
    (do () ((or (zerop (tcb-first-tx-count c))
		(seq< ack (aref (tcb-first-tx-end c) (tcb-first-tx-head c)))))
      (setf (tcb-first-tx-head c) (logand (1+ (tcb-first-tx-head c)) (1- %tcp-first-tx-slots)))
      (decf (tcb-first-tx-count c))
      (tcp-r2-arm c))
    (setf (tcb-retries c) 0 (tcb-backoff c) 0)
    (if (< (tcb-cwnd c) (tcb-ssthresh c))
	(incf (tcb-cwnd c) (tcb-mss c))
      (incf (tcb-cwnd c) (max 1 (floor (* (tcb-mss c) (tcb-mss c)) (tcb-cwnd c)))))
    (if (or (not (= (tcb-snd-una c) (tcb-snd-nxt c)))
	    (and (tcb-fin-seq c) (not (= (tcb-snd-una c) (tcb-max-sent c)))))
	(tcp-arm c)
      (setf (tcb-rexmt-due c) nil))))

(defun tcp-window-update (c window)
  (setf (tcb-peer-window c) window
	(tcb-max-window c) (max (tcb-max-window c) window))
  (when (and (plusp window) (tcb-persist-due c))
    (setf (tcb-persist-due c) nil (tcb-persist-backoff c) 0)
    (when (and (not (= (tcb-snd-una c) (tcb-snd-nxt c))) (null (tcb-rexmt-due c)))
      (tcp-arm c))))

;;;; Receive (RFC 9293 3.10.7)

(defun tcp-refused-source-p (source)
  "MUST-63's sources: a broadcast, multicast or class E, 0.0.0.0, loopback, the band."
  (or (broadcast-address-p source)
      (zerop source)
      (= source my-address)
      (let ((a (%logldb #o3010 source)))
	(or (>= a 224) (= a 127)))))

(defun tcp-option-mss (b p header)
  "The MSS option of the segment at P, or NIL; :ILLEGAL for an illegal option length
\(MUST-7).  Options are parsed anywhere, unaligned, and unknown ones skipped."
  (do ((i (+ p 20)) (end (+ p header)) (mss nil))
      ((>= i end) mss)
    (let ((kind (get-8 b i)))
      (cond ((= kind 0) (return mss))
	    ((= kind 1) (incf i))
	    ((or (>= (1+ i) end)
		 (< (get-8 b (1+ i)) 2)
		 (> (+ i (get-8 b (1+ i))) end))
	     (return :illegal))
	    (t (when (and (= kind 2) (= (get-8 b (1+ i)) 4))
		 (setq mss (get-16 b (+ i 2))))
	       (incf i (get-8 b (1+ i))))))))

(defun tcp-in-window-p (c seq)
  "SEQ in the receive window; at a zero window only RCV.NXT."
  (let ((w (if (eq (tcb-state c) :syn-received) %tcp-buffer (tcp-window c))))
    (if (zerop w)
	(= seq (tcb-rcv-nxt c))
      (and (not (seq< seq (tcb-rcv-nxt c))) (seq< seq (seq+ (tcb-rcv-nxt c) w))))))

(defun tcp-deliver (c b p n)
  "N bytes at P in B, in order, into C's receive buffer, which has room for them."
  (let* ((buffer (tcb-receive-buffer c))
	 (start (logand (+ (tcb-receive-head c) (tcb-receive-count c)) (1- %tcp-buffer)))
	 (first (min n (- %tcp-buffer start))))
    (copy-array-portion b p (+ p first) buffer start (+ start first))
    (when (< first n)
      (copy-array-portion b (+ p first) (+ p n) buffer 0 (- n first)))
    (incf (tcb-receive-count c) n)))

(defun tcp-refuse (remote sport dport seq ack flags length)
  "RFC 9293 3.10.7.1's RST to a segment that has no connection, which its sender
accepts: <SEQ=SEG.ACK><CTL=RST> if it carries ACK, else
<SEQ=0><ACK=SEG.SEQ+SEG.LEN><CTL=RST,ACK>."
  (if (zerop (logand flags %tcp-ack))
      (tcp-raw-send remote dport sport 0 (seq+ seq (+ length (if (zerop (logand flags %tcp-syn)) 0 1)))
		    (logior %tcp-rst %tcp-ack) 0)
    (tcp-raw-send remote dport sport ack 0 %tcp-rst 0)))

(defun tcp-receive (b source p length)
  "A TCP segment of LENGTH bytes at P in B, from SOURCE."
  (incf tcp-segments-received)
  (let* ((sport (get-16 b p))
	 (dport (get-16 b (+ p 2)))
	 (seq (get-32 b (+ p 4)))
	 (ack (get-32 b (+ p 8)))
	 (offset-flags (get-16 b (+ p 12)))
	 (header (* 4 (ldb #o1404 offset-flags)))
	 (flags (logand offset-flags #o77))
	 (window (get-16 b (+ p 14)))
	 (urgent (get-16 b (+ p 18)))
	 (mss nil))
    (when (or (< header 20) (> header length))
      (incf tcp-segments-dropped)
      (return-from tcp-receive nil))
    (setq mss (tcp-option-mss b p header))
    (when (eq mss :illegal)
      ;; an illegal option length drops the segment: nothing in it is used.
      (incf tcp-segments-dropped)
      (return-from tcp-receive nil))
    (let ((data (+ p header))
	  (n (- length header)))
      (when (tcp-time-wait-segment source sport dport seq flags n)
	(return-from tcp-receive nil))
      (let ((c (tcp-find source sport dport)))
	(if c
	    (tcp-receive-on c b seq ack flags window urgent data n)
	  (tcp-receive-closed b source sport dport seq ack flags window mss n))))))

(defun tcp-receive-closed (b source sport dport seq ack flags window mss n)
  (ignore b)
  (cond ((not (zerop (logand flags %tcp-rst))) nil)
	((and (not (zerop (logand flags %tcp-syn))) (zerop (logand flags %tcp-ack))
	      (tcp-listener dport))
	 (cond ((tcp-refused-source-p source)
		(incf tcp-refused-silently))	;MUST-63
	       ;; the backlog first, then the table, where every connection
	       ;; from SYN-RECEIVED to LAST-ACK counts.
	       ((>= (loop for c in tcp-connections
			  count (and (eq (tcb-state c) :syn-received) (= (tcb-lport c) dport)))
		    %tcp-backlog)
		(incf tcp-refused-silently))
	       ((>= (length tcp-connections) %tcp-connections)
		(tcp-refuse source sport dport seq ack flags n))
	       (t
		(let ((iss (tcp-isn source sport dport))
		      (send-mss (min (or mss %tcp-default-mss) %tcp-mss)))
		  (let ((c (make-tcb-internal
			     :remote source :rport sport :lport dport
			     :irs seq :iss iss :rcv-nxt (seq+ seq 1)
			     :snd-una iss :snd-nxt (seq+ iss 1) :max-sent (seq+ iss 1)
			     :mss send-mss :peer-window window :max-window window
			     :cwnd (* 3 send-mss) :ssthresh 65535.)))
		    (push c tcp-connections)
		    (tcp-send-synack c))))))
	(t (tcp-refuse source sport dport seq ack flags n))))

(defun tcp-receive-on (c b seq ack flags window urgent data n)
  (block nil
    (when (not (zerop (logand flags %tcp-rst)))
      ;; an RST in the window is taken: in SYN-RECEIVED back to LISTEN, else the
      ;; connection is aborted and its stream signals it (MUST-11, -12).
      (when (tcp-in-window-p c seq)
	(tcp-remove c (if (eq (tcb-state c) :syn-received) nil 'sys:connection-lost)))
      (return nil))
    (when (not (zerop (logand flags %tcp-syn)))
      (if (and (eq (tcb-state c) :syn-received) (= seq (tcb-irs c)))
	  (tcp-send-synack c)			;the SYN again
	(tcp-send-ack c))			;a challenge ACK (RFC 5961 4)
      (return nil))
    (when (zerop (logand flags %tcp-ack))
      (return nil))
    (when (not (zerop (logand flags %tcp-urg)))
      ;; the urgent pointer is kept even when the data is not taken (MUST-66):
      ;; RCV.UP, the octet after the urgent data (MUST-62).
      (let ((up (seq+ seq urgent)))
	(when (or (null (tcb-rcv-up c)) (seq< (tcb-rcv-up c) up))
	  (setf (tcb-rcv-up c) up))))
    (cond ((eq (tcb-state c) :syn-received)
	   ;; the ACK of the SYN-ACK.
	   (unless (and (seq< (tcb-iss c) ack) (not (seq< (tcb-snd-nxt c) ack)))
	     (return nil))
	   (setf (tcb-state c) :established
		 (tcb-snd-una c) ack
		 (tcb-peer-window c) window
		 (tcb-max-window c) (max (tcb-max-window c) window)
		 (tcb-rexmt-due c) nil
		 (tcb-synack-r2-due c) nil)
	   (cond ((and (tcb-synack-tx c) (zerop (tcb-retries c)))
		  (tcp-sample c (network-time-difference (network-now) (tcb-synack-tx c))))
		 ((and (plusp (tcb-retries c)) (null (tcb-srtt c)))
		  ;; RFC 6298 (5.7): the SYN-ACK was resent, so data starts at 3 s.
		  (setf (tcb-rto-base c) (* 3 1000000.))))
	   (when (plusp (tcb-retries c))
	     ;; RFC 5681 3.1: after a lost SYN-ACK the initial window is one segment.
	     (setf (tcb-cwnd c) (tcb-mss c)))
	   (setf (tcb-retries c) 0 (tcb-backoff c) 0)
	   (tcp-server-start c))
	  (t
	   ;; an ACK of what was never sent is dropped.
	   (when (seq< (tcb-max-sent c) ack)
	     (return nil))
	   (when (seq< (tcb-snd-una c) ack)
	     (tcp-acked c ack)
	     (when (and (tcb-fin-seq c) (= ack (seq+ (tcb-fin-seq c) 1)))
	       ;; our FIN is acknowledged.
	       (case (tcb-state c)
		 (:fin-wait-1
		  (setf (tcb-state c) :fin-wait-2
			(tcb-fin-wait-2-due c) (network-time-plus (tcb-fin-tx c) %tcp-fin-wait-2))
		  (network-note-timer (tcb-fin-wait-2-due c)))
		 (:closing (tcp-enter-time-wait c) (return nil))
		 (:last-ack (tcp-remove c nil) (return nil)))))
	   (unless (seq< ack (tcb-snd-una c))
	     (tcp-window-update c window))))
    (let ((need-ack nil))
      (when (and (zerop n) (zerop (logand flags %tcp-fin)))
	;; a segment without data that is not acceptable, a probe below
	;; RCV.NXT for one, gets an ACK (RFC 9293 3.10.7.4).
	(let ((w (tcp-window c)))
	  (unless (if (zerop w)
		      (= seq (tcb-rcv-nxt c))
		    (and (not (seq< seq (tcb-rcv-nxt c))) (seq< seq (seq+ (tcb-rcv-nxt c) w))))
	    (setq need-ack t))))
      (cond ((zerop n))
	    ((memq (tcb-state c) '(:established :fin-wait-1 :fin-wait-2))
	     (cond ((= seq (tcb-rcv-nxt c))
		    (let ((take (min n (tcp-window c))))
		      (when (plusp take)
			(tcp-deliver c b data take)
			(setf (tcb-rcv-nxt c) (seq+ (tcb-rcv-nxt c) take)))
		      (setq need-ack t)))
		   ((and (seq< seq (tcb-rcv-nxt c)) (seq< (tcb-rcv-nxt c) (seq+ seq n)))
		    ;; an overlap: only its new part is taken.
		    (let* ((old (seq- (tcb-rcv-nxt c) seq))
			   (take (min (- n old) (tcp-window c))))
		      (when (plusp take)
			(tcp-deliver c b (+ data old) take)
			(setf (tcb-rcv-nxt c) (seq+ (tcb-rcv-nxt c) take))))
		    (setq need-ack t))
		   ;; beyond RCV.NXT: dropped and answered (in-order delivery only);
		   ;; an old duplicate: acknowledged, not delivered.
		   (t (setq need-ack t))))
	    (t (setq need-ack t)))		;after the peer's FIN: acknowledged, not taken
      (when (not (zerop (logand flags %tcp-fin)))
	(cond ((= (seq+ seq n) (tcb-rcv-nxt c))
	       (case (tcb-state c)
		 (:established
		  (setf (tcb-rcv-nxt c) (seq+ (tcb-rcv-nxt c) 1)
			(tcb-state c) :close-wait
			(tcb-peer-fin c) t)
		  (setq need-ack t))
		 (:fin-wait-2
		  (setf (tcb-rcv-nxt c) (seq+ (tcb-rcv-nxt c) 1)
			(tcb-peer-fin c) t)
		  (tcp-send-ack c)
		  (tcp-enter-time-wait c)
		  (return nil))
		 (:fin-wait-1
		  ;; both FINs crossed: CLOSING, ours unacknowledged.
		  (setf (tcb-rcv-nxt c) (seq+ (tcb-rcv-nxt c) 1)
			(tcb-state c) :closing
			(tcb-peer-fin c) t)
		  (setq need-ack t))))
	      ((and (memq (tcb-state c) '(:close-wait :last-ack :closing))
		    (= (seq+ seq (1+ n)) (tcb-rcv-nxt c)))
	       (setq need-ack t))))		;the peer's FIN again
      (when (and (not (tcp-output c)) need-ack)
	(setf (tcb-ack-pending c) t)))))

(defun tcp-batch-end ()
  "The one ACK of each connection for the batch (section 5.1)."
  (dolist (c tcp-connections)
    (when (tcb-ack-pending c)
      (tcp-send-ack c))))

;;;; TIME-WAIT (section 5.5)

(defun tcp-enter-time-wait (c)
  "TIME-WAIT for 60 s, as a record apart from the connections; the oldest ends early
when all 64 are taken."
  (tcp-remove c nil)
  (let ((slot nil) (now (network-now)))
    (dotimes (i %tcp-time-wait-records)
      (cond ((null (aref tcp-tw-remote i)) (return (setq slot i)))
	    ((or (null slot)
		 (minusp (network-time-difference (aref tcp-tw-started i) (aref tcp-tw-started slot))))
	     (setq slot i))))
    (setf (aref tcp-tw-remote slot) (tcb-remote c)
	  (aref tcp-tw-rport slot) (tcb-rport c)
	  (aref tcp-tw-lport slot) (tcb-lport c)
	  (aref tcp-tw-rcv-nxt slot) (tcb-rcv-nxt c)
	  (aref tcp-tw-snd-nxt slot) (tcb-snd-nxt c)
	  (aref tcp-tw-started slot) now)
    (tcp-time-wait-arm slot)))

(defun tcp-time-wait-arm (slot)
  (setf (aref tcp-tw-end slot) (network-time-plus (network-now) %tcp-time-wait))
  (network-note-timer (aref tcp-tw-end slot)))

(defun tcp-time-wait-segment (remote rport lport seq flags n)
  "A segment to a TIME-WAIT record, answered as RFC 9293 3.10.7.4 has TIME-WAIT
answer; NIL if there is no record, or if it is a SYN above the final RCV.NXT, which
ends the record and opens a new connection (MAY-2)."
  (let ((slot (dotimes (i %tcp-time-wait-records)
		(when (and (eql (aref tcp-tw-remote i) remote)
			   (= (aref tcp-tw-rport i) rport) (= (aref tcp-tw-lport i) lport))
		  (return i)))))
    (when slot
      (flet ((answer ()
	       (tcp-raw-send remote lport rport (aref tcp-tw-snd-nxt slot) (aref tcp-tw-rcv-nxt slot)
			     %tcp-ack %tcp-buffer)))
	(cond ((not (zerop (logand flags %tcp-rst))) t)
	      ((and (not (zerop (logand flags %tcp-syn))) (zerop (logand flags %tcp-ack)))
	       (cond ((seq< (aref tcp-tw-rcv-nxt slot) seq)
		      (setf (aref tcp-tw-remote slot) nil)
		      nil)
		     (t (answer) t)))		;the challenge ACK; the record stays
	      ((not (zerop (logand flags %tcp-fin)))
	       ;; the peer's FIN again: acknowledged, and TIME-WAIT restarts.
	       (answer)
	       (tcp-time-wait-arm slot)
	       t)
	      (t
	       ;; any other segment that is not acceptable gets an ACK of the final
	       ;; RCV.NXT; a bare ACK at RCV.NXT gets nothing.
	       (when (or (plusp n) (not (= seq (aref tcp-tw-rcv-nxt slot))))
		 (answer))
	       t))))))

;;;; Timers

(defun tcp-expire (c)
  "The retransmission timer (RFC 6298 5.5; RFC 5681 3.1): the RTO doubles; after R1 = 3
retransmissions the next hop's ARP entry goes (MUST-20); the congestion window drops
to one segment and the sender goes back to SND.UNA."
  (setf (tcb-rexmt-due c) nil)
  (incf (tcb-retries c))
  (incf (tcb-backoff c))
  (setf (tcb-timed-end c) nil)
  (when (= (tcb-retries c) (1+ %tcp-r1))
    (arp-forget (next-hop (tcb-remote c))))
  (cond ((eq (tcb-state c) :syn-received)
	 (tcp-send-synack c))
	((tcb-fin-seq c)
	 (let ((flight (seq- (tcb-snd-nxt c) (tcb-snd-una c))))
	   (cond ((and (plusp (tcb-send-count c)) (plusp flight))
		  (tcp-send c %tcp-ack (tcb-snd-una c) 0 (min (tcb-mss c) (tcb-send-count c))))
		 ((plusp flight)
		  (tcp-send c (logior %tcp-fin %tcp-ack) (tcb-fin-seq c))))
	   (tcp-arm c)))
	(t
	 (let ((flight (tcp-flight c)))
	   (setf (tcb-ssthresh c) (max (floor flight 2) (* 2 (tcb-mss c)))
		 (tcb-cwnd c) (tcb-mss c)
		 (tcb-snd-nxt c) (tcb-snd-una c)
		 (tcb-forced c) t)		;the resent segment goes whatever MUST-38 says
	   (tcp-output c)
	   (when (and (null (tcb-rexmt-due c)) (not (= (tcb-snd-una c) (tcb-max-sent c))))
	     (tcp-arm c))))))

(defsubst tcp-due-p (due now)
  (and due (not (minusp (network-time-difference now due)))))

(defun tcp-earlier (due next)
  (if (and due (minusp (network-time-difference due next))) due next))

(defun tcp-timers (now)
  "TCP's timers, run in every pass: returns the time of the next.  The pass comes at
least every 15 minutes, so that the ISN's clock counts the network clock's wraps."
  (tcp-clock-track)
  ;; the list is walked as it shrinks: TCP-REMOVE's DELQ leaves the cell walked.
  (dolist (c tcp-connections)
    (when (and (eq (tcb-state c) :syn-received) (tcp-due-p (tcb-synack-r2-due c) now))
      ;; R2 for a SYN-ACK: back to LISTEN, at that time.
      (tcp-remove c nil))
    (when (and (not (eq (tcb-state c) :closed)) (tcp-due-p (tcb-r2-due c) now))
      ;; R2 for data: the connection closes at that time, and its stream
      ;; signals it.
      (tcp-remove c 'sys:host-stopped-responding))
    (when (and (not (eq (tcb-state c) :closed)) (tcp-due-p (tcb-fin-wait-2-due c) now))
      (setf (tcb-fin-wait-2-due c) nil)
      (when (eq (tcb-state c) :fin-wait-2) (tcp-remove c nil)))
    (when (and (not (eq (tcb-state c) :closed)) (tcp-due-p (tcb-rexmt-due c) now))
      (tcp-expire c))
    (when (and (not (eq (tcb-state c) :closed)) (tcp-due-p (tcb-persist-due c) now))
      (setf (tcb-persist-due c) nil)
      (tcp-persist-fire c))
    (when (and (not (eq (tcb-state c) :closed)) (tcp-due-p (tcb-override-due c) now))
      (setf (tcb-override-due c) nil (tcb-forced c) t)
      (tcp-output c)))
  (dotimes (i %tcp-time-wait-records)
    (when (and (aref tcp-tw-remote i) (tcp-due-p (aref tcp-tw-end i) now))
      (setf (aref tcp-tw-remote i) nil)))
  (let ((next (network-time-plus now (* 15. 60. 1000000.))))
    (dolist (c tcp-connections)
      (setq next (tcp-earlier (tcb-rexmt-due c) next)
	    next (tcp-earlier (tcb-persist-due c) next)
	    next (tcp-earlier (tcb-override-due c) next)
	    next (tcp-earlier (tcb-r2-due c) next)
	    next (tcp-earlier (tcb-synack-r2-due c) next)
	    next (tcp-earlier (tcb-fin-wait-2-due c) next)))
    (dotimes (i %tcp-time-wait-records)
      (when (aref tcp-tw-remote i)
	(setq next (tcp-earlier (aref tcp-tw-end i) next))))
    next))

;;;; The servers' side: reading, writing, closing (under the network lock)

(defun tcp-readable-p (c)
  (or (plusp (tcb-receive-count c)) (tcb-peer-fin c) (eq (tcb-state c) :closed)))

(defun tcp-signal-if-ended (c)
  "Signal the error that ended C, if one did."
  (when (and (eq (tcb-state c) :closed) (tcb-error c))
    (tcp-signal c (tcb-error c))))

(defun tcp-consume (c n)
  "Take N bytes off the front of C's receive buffer.  A window that opens from zero is
said at once."
  (with-network-lock
    (let ((was (if (eq (tcb-state c) :closed) 1 (tcp-window c))))
      (setf (tcb-receive-head c) (logand (+ (tcb-receive-head c) n) (1- %tcp-buffer))
	    (tcb-receive-count c) (- (tcb-receive-count c) n))
      (when (and (zerop was) (not (eq (tcb-state c) :closed)) (plusp (tcp-window c)))
	(tcp-send-ack c)))))

(defun tcp-peek-into (c array start end)
  "Copy up to END - START bytes from the front of C's receive buffer into ARRAY at
START, consuming none; returns the count."
  (let* ((n (min (- end start) (tcb-receive-count c)))
	 (buffer (tcb-receive-buffer c))
	 (head (tcb-receive-head c))
	 (first (min n (- %tcp-buffer head))))
    (copy-array-portion buffer head (+ head first) array start (+ start first))
    (when (< first n)
      (copy-array-portion buffer 0 (- n first) array (+ start first) (+ start n)))
    n))

(defun tcp-writable-p (c)
  (or (< (tcb-send-count c) %tcp-buffer) (eq (tcb-state c) :closed)))

(defun tcp-write (c array start end)
  "Queue the bytes of ARRAY from START to END on C, waiting while the send buffer is
full; nothing is sent after the application's own close."
  (do () ((>= start end))
    (unless (tcp-writable-p c)
      (process-wait "TCP Output" #'tcp-writable-p c))
    (tcp-signal-if-ended c)
    (with-network-lock
      (when (or (tcb-application-closed c) (tcb-close-requested c) (eq (tcb-state c) :closed))
	(return nil))
      (let* ((n (min (- end start) (- %tcp-buffer (tcb-send-count c))))
	     (buffer (tcb-send-buffer c))
	     (tail (logand (+ (tcb-send-head c) (tcb-send-count c)) (1- %tcp-buffer)))
	     (first (min n (- %tcp-buffer tail))))
	(copy-array-portion array start (+ start first) buffer tail (+ tail first))
	(when (< first n)
	  (copy-array-portion array (+ start first) (+ start n) buffer 0 (- n first)))
	(incf (tcb-send-count c) n)
	(incf start n)
	(setf (tcb-pushed c) nil)
	(tcp-output c)))))

(defun tcp-push (c)
  "Push what is queued (:FORCE-OUTPUT): MUST-38's rules 2 and 4 then apply."
  (with-network-lock
    (unless (eq (tcb-state c) :closed)
      (setf (tcb-pushed c) t)
      (tcp-output c))))

(defun tcp-acknowledged-p (c)
  (or (eq (tcb-state c) :closed) (= (tcb-snd-una c) (tcb-max-sent c))))

(defun tcp-finish (c)
  "Wait until everything sent on C is acknowledged."
  (process-wait "TCP Finish" #'tcp-acknowledged-p c))

(defun tcp-close (c &optional abort)
  "The application's close: a FIN after the data, or with ABORT an RST.  After the
application's first close, a later one sends nothing (section 9, T1, the way in)."
  (with-network-lock
    (unless (tcb-application-closed c)
      (setf (tcb-application-closed c) t)
      (cond ((eq (tcb-state c) :closed))
	    (abort
	     (tcp-send c (logior %tcp-rst %tcp-ack) (tcb-snd-nxt c))
	     (tcp-remove c nil))
	    (t
	     (setf (tcb-close-requested c) t (tcb-pushed c) t)
	     (tcp-output c))))))

(defun tcp-signal (c name)
  "Signal NAME, SYS:CONNECTION-LOST or SYS:HOST-STOPPED-RESPONDING, for C, the condition
carrying C's foreign host itself (section 7)."
  (error (make-instance 'eh::bad-connection-state
			:property-list (list :connection c :foreign-host (tcp-foreign-host c)
					     :reason (if (eq name 'sys:connection-lost) "reset" nil))
			:format-string (if (eq name 'sys:connection-lost)
					   "The TCP connection ~S was reset by its foreign host."
					 "The foreign host of the TCP connection ~S stopped responding.")
			:format-args (list c)
			:condition-names (if (eq name 'sys:connection-lost)
					     '(sys:connection-lost)
					   '(sys:host-stopped-responding eh::host-not-responding)))))

(defun tcp-foreign-host (c)
  "The host of C's foreign address, from the host table, or NIL."
  (address-host (tcb-remote c)))

(defun address-host (address)
  "The site table's host whose INTERNET address is ADDRESS, or NIL."
  (dolist (elem si:host-alist)
    (dolist (a (getf (si:host-addresses elem) :internet))
      (when (and (stringp a) (eql (condition-case () (parse-address a) (error nil)) address))
	(return-from address-host (si:get-alist-elem-host elem))))))

;;;; Starting

(defun tcp-start ()
  "As the network starts: no connection, no record, a new ISN key."
  (dolist (c tcp-connections) (setf (tcb-state c) :closed (tcb-error c) 'sys:connection-lost))
  (setq tcp-connections nil)
  (dotimes (i %tcp-time-wait-records) (setf (aref tcp-tw-remote i) nil))
  (setq tcp-clock-last (network-now) tcp-clock-high 0)
  ;; the key from the RTC and the microsecond clock (section 5.5).
  (setq tcp-isn-key (tcp-mix (tcp-mix #x5A17 (ether-register #o103)) (network-now))))

(setq ipv4-tcp-function 'tcp-receive)
(or (memq 'tcp-timers network-timer-functions) (push 'tcp-timers network-timer-functions))
(or (memq 'tcp-batch-end network-batch-functions) (push 'tcp-batch-end network-batch-functions))
(or (memq 'tcp-start network-start-functions)
    (setq network-start-functions (append network-start-functions '(tcp-start))))
