;;; -*- Mode:LISP; Package:INTERNET; Base:10; Readtable:ZL -*-
;;;
;;; This is SYS: NETWORK; IP; ETHER
;;;
;;; quux revision 16: the driver of quux's ethernet device and the network
;;; process (QUUX's Ethernet contract, sections 2, 2.6 and 5.1).  the device
;;; is muir's as its docs/quux.md describes it, "revision 16: the ethernet
;;; device": ethernet frames moved by dma through two rings in main memory,
;;; one for each direction, with only control, the rings' bases, sizes and
;;; indexes, four counters and the host's addresses in the registers, words
;;; 240-257 of the register page.  arp, ipv4, icmp and ping, which run on
;;; this, are in SYS: NETWORK; IP; IPV4.
;;;
;;; the device fills in and checks every checksum (the contract's section
;;; 2.4), so nothing here or in ipv4 computes one: a field the stack leaves 0
;;; goes out filled in, and a frame with a wrong one never arrives.
;;;
;;; the network process waits on a predicate that reads register 251, the
;;; receive consumer, and the earliest timer, and conses nothing.  a received
;;; frame wakes it through the device's interrupt (section 2.6's fallback,
;;; built since m-ack's idle bound failed with the clock's break every tick):
;;; before it waits the process sets register 240 <8>, the interrupt enable,
;;; and the microcode, taking word 100 <8>, clears <8> again and asks for a
;;; sequence break, as mit's microcode can take a chaos packet as one (:chaos;
;;; the band enables only :clock), so the scheduler runs the
;;; process, at priority 25 as chaos background, at once even when another
;;; process computes.  the clock's sequence break comes every tick only while
;;; a timer of the network's own is due within 2 s (network-clock-rule), so
;;; that an idle band pays only the collector's rate or the clock's default.
;;; a sender runs at the network process's priority while it holds the
;;; network lock (with-network-lock), so that a sender preempted in its
;;; section resumes before any process at a user's priority (m-ack).
;;;
;;; the rings share one wired page: 16 transmit entries of 8 words, then 32
;;; receive entries.  every buffer is 384 words, 1,536 bytes, two to a wired
;;; page, so that no buffer crosses a page: the device cannot see pages, and
;;; a wired rqb's pages are not contiguous in physical memory (section 2.3).
;;; transmit entry k always uses transmit buffer k, receive entry k receive
;;; buffer k.

;;;; The layout (QUUX's Ethernet contract, sections 2.2 and 2.3; one place)

(defconst %ether-control #o240 "Register 240: <0> enable, <8> interrupt enable.")
(defconst %ether-status #o241
  "Register 241: <0> enabled, <1> quiet, <2> configuration refused, <3> index fault,
<7:4> received frames dropped by the type filter mod 16, <8> a frame waiting,
<15:9> received frames dropped by the IPv4 checks mod 128, <23:16> received frames
dropped mod 256, <31:24> transmit entries refused mod 256.")
(defconst %ether-transmit-base #o242)
(defconst %ether-transmit-size #o243)
(defconst %ether-transmit-producer #o244)
(defconst %ether-transmit-consumer #o245)
(defconst %ether-receive-base #o246)
(defconst %ether-receive-size #o247)
(defconst %ether-receive-producer #o250 "Buffers given to the device.")
(defconst %ether-receive-consumer #o251 "Buffers the device filled.")
(defconst %ether-receive-taken #o252 "Filled entries the driver took back.")
(defconst %ether-mac-high #o253 "<15:0>: the MAC address's bytes 0-1, byte 0 in <15:8>.")
(defconst %ether-mac-low #o254 "<31:0>: the MAC address's bytes 2-5, byte 2 in <31:24>.")
(defconst %ether-ip-address #o255 "The host's IPv4 address for the band, a.b.c.d as a<<24|b<<16|c<<8|d.")
(defconst %ether-ip-netmask #o256)
(defconst %ether-ip-gateway #o257)

(defconst %%ether-status-enabled #o0001)
(defconst %%ether-status-quiet #o0101)
(defconst %%ether-status-refused #o0201)
(defconst %%ether-status-index-fault #o0301)
(defconst %%ether-status-type-filter #o0404)
(defconst %%ether-status-ipv4-checks #o1107)
(defconst %%ether-status-dropped #o2010)
(defconst %%ether-status-refused-entries #o3010)

;; feature word 15 <2> says the device is there; it reads 3 on revision 15.
(defconst %%ether-feature #o0201)
(defconst %ether-control-armed #o401 "Register 240: enabled, <0>, with the interrupt enable, <8>.")

(defconst %ether-entry-words 8)
(defconst %ether-transmit-log2 4)
(defconst %ether-transmit-entries 16)
(defconst %ether-receive-log2 5)
(defconst %ether-receive-entries 32)
(defconst %ether-receive-ring-offset (* %ether-transmit-entries %ether-entry-words)
  "Words from the ring page's start to the receive ring's.")
(defconst %ether-buffer-words 384)
(defconst %ether-buffer-bytes (* 4 %ether-buffer-words))
(defconst %ether-frame-max 1514 "The longest Ethernet frame, header included, in bytes.")
(defconst %ether-quiet-timeout 120.
  "Sixtieths of a second to wait for the device to become quiet after a disable.")

;;;; State

(defvar ether-generation 0
  "Counts disables.  A disable is the device's reset (section 2.7): what was given
to it before is forgotten, so a waiter of an older generation gives up.")
(defvar ether-enabled nil "T once a reset has enabled the device on this driver's rings.")
(defvar ether-ring-rqb nil "One wired page: the transmit ring, then the receive ring.")
(defvar ether-transmit-rqb nil "8 wired pages: transmit buffers 0-15, two to a page.")
(defvar ether-receive-rqb nil "16 wired pages: receive buffers 0-31, two to a page.")
(defvar ether-ring nil "The ring page's 16-bit view.")
(defvar ether-transmit-bytes nil "An ART-8B view of the transmit buffers' pages.")
(defvar ether-receive-bytes nil "An ART-8B view of the receive buffers' pages.")
(defvar ether-ring-address nil "The ring page's physical address.")
(defvar ether-transmit-addresses (make-array %ether-transmit-entries)
  "The physical word address of each transmit buffer.")
(defvar ether-receive-addresses (make-array %ether-receive-entries)
  "The physical word address of each receive buffer.")
(defvar ether-transmit-count 0 "Transmit entries posted, mod 2^16: register 244.")
(defvar ether-receive-given 0 "Receive buffers given, mod 2^16: register 250.")
(defvar ether-receive-count 0 "Filled receive entries taken back, mod 2^16: register 252.")
(defvar ether-frames-sent 0 "Transmit entries posted since the band was built.")
(defvar ether-frames-received 0 "Receive entries taken since the band was built.")

;; the driver's totals of status 241's four counters (section 5.1): each pass
;; adds the change in each counter since the pass before, modulo its width.
;; the counters run free from power-on and no disable changes them (section
;; 2.7), so the totals count from the first reading after the network starts.
(defvar ether-type-filter-total 0 "Received frames the type filter dropped, 241 <7:4>.")
(defvar ether-ipv4-checks-total 0 "Received frames the IPv4 checks dropped, 241 <15:9>.")
(defvar ether-dropped-total 0 "Received frames dropped for want of a buffer, 241 <23:16>.")
(defvar ether-refused-total 0 "Transmit entries refused, 241 <31:24>.")
(defvar ether-last-status nil "Register 241 when the totals were last brought up to date.")

;;;; Registers and memory

;; a register's field straight out of its word, as feature-page-field reads
;; the feature page, so that the wait predicate conses nothing.
(defsubst ether-field (word ppss)
  (si:feature-page-field word ppss))

;; a register as a fixnum: muir's 32-bit words read as signed fixnums.
(defsubst ether-register (word)
  (%xbus-read (+ si:feature-page-xbus-address word)))

(defsubst ether-set-register (word value)
  (%xbus-write (+ si:feature-page-xbus-address word) value))

(defun ether-present-p ()
  "T if the machine has an Ethernet device (feature word 15 <2>)."
  (not (zerop (si:feature-page-field #o15 %%ether-feature))))

(defsubst ether-transmit-offset (slot)
  "The byte offset of transmit buffer SLOT in ETHER-TRANSMIT-BYTES: two buffers to a page."
  (+ (* (floor slot 2) si:page-size 4) (* (logand slot 1) %ether-buffer-bytes)))

(defsubst ether-receive-offset (slot)
  "The byte offset of receive buffer SLOT in ETHER-RECEIVE-BYTES: two buffers to a page."
  (+ (* (floor slot 2) si:page-size 4) (* (logand slot 1) %ether-buffer-bytes)))

(defsubst ether-store-entry-word (entry word value)
  (si:file-device-store-word ether-ring (+ (* entry %ether-entry-words) word) value))

(defsubst ether-fetch-entry-word (entry word)
  (si:file-device-fetch-word ether-ring (+ (* entry %ether-entry-words) word)))

;;;; The totals of 241's counters

(defsubst ether-counter-change (status last ppss width)
  "The change in 241's counter PPSS, WIDTH bits wide, from LAST to STATUS."
  (logand (- (%logldb ppss status) (%logldb ppss last)) (1- (ash 1 width))))

(defun ether-update-totals ()
  "Add the change in each of status 241's four counters to the driver's totals."
  (without-interrupts
    (let ((status (ether-register %ether-status))
	  (last ether-last-status))
      (when last
	(incf ether-type-filter-total
	      (ether-counter-change status last %%ether-status-type-filter 4))
	(incf ether-ipv4-checks-total
	      (ether-counter-change status last %%ether-status-ipv4-checks 7))
	(incf ether-dropped-total (ether-counter-change status last %%ether-status-dropped 8))
	(incf ether-refused-total
	      (ether-counter-change status last %%ether-status-refused-entries 8)))
      (setq ether-last-status status))))

(defun type-filter-total ()
  "The driver's total of received Ethernet frames the device's type filter dropped
(status 241 <7:4>), brought up to date now."
  (ether-update-totals)
  ether-type-filter-total)

(defun ipv4-checks-total ()
  "The driver's total of received Ethernet frames the device's IPv4 checks dropped
(status 241 <15:9>), brought up to date now."
  (ether-update-totals)
  ether-ipv4-checks-total)

;;;; Reset

(defun ether-disable ()
  "Disable the Ethernet device: what it was given is forgotten (section 2.7)."
  (when (ether-present-p)
    (ether-set-register %ether-control 0)
    (setq ether-enabled nil)
    (incf ether-generation))
  nil)

(defun ether-wait-quiet ()
  "Wait until the device is quiet: not enabled and not busy.  On a board busy is
its program's claim, which it gives up once it sees the disable (section 2.7).
Returns NIL, or a message if it does not become quiet in time."
  (let ((start (time)))
    (do () ((ldb-test %%ether-status-quiet (ether-register %ether-status)) nil)
      (when (> (time-difference (time) start) %ether-quiet-timeout)
	(return (format nil "The Ethernet device did not become quiet within ~D//60 s of a disable (status ~O)."
			%ether-quiet-timeout (ether-register %ether-status))))
      (process-allow-schedule))))

(defun ether-reset ()
  "Reset the Ethernet device and point it at this driver's rings, every receive
buffer given.  The sequence of docs//quux.md: disable, wait for quiet, write the
bases and sizes, enable, check the status.  Returns NIL, or a message."
  (block reset
    (unless (ether-present-p)
      (return-from reset "This machine has no Ethernet device (feature word 15 <2> is clear)."))
    (ether-disable)
    ;; the buffers may be reused only once the device is quiet: until then a
    ;; board's program may still be writing one under its claim.
    (let ((message (ether-wait-quiet)))
      (when message (return-from reset message)))
    ;; the rings and buffers, wired again: wiring does not survive a boot, and
    ;; a page's physical address may differ after one.
    (or ether-ring-rqb (setq ether-ring-rqb (si:get-disk-rqb 1)))
    (or ether-transmit-rqb
	(setq ether-transmit-rqb (si:get-disk-rqb (floor %ether-transmit-entries 2))))
    (or ether-receive-rqb
	(setq ether-receive-rqb (si:get-disk-rqb (floor %ether-receive-entries 2))))
    (si:wire-disk-rqb ether-ring-rqb 1 t t)
    (si:wire-disk-rqb ether-transmit-rqb (floor %ether-transmit-entries 2) t t)
    (si:wire-disk-rqb ether-receive-rqb (floor %ether-receive-entries 2) t t)
    (setq ether-ring (si:rqb-buffer ether-ring-rqb))
    (or ether-transmit-bytes (setq ether-transmit-bytes (si:file-device-8-bit-view ether-transmit-rqb)))
    (or ether-receive-bytes (setq ether-receive-bytes (si:file-device-8-bit-view ether-receive-rqb)))
    (setq ether-ring-address (si:file-device-rqb-page-address ether-ring-rqb 0))
    (dotimes (slot %ether-transmit-entries)
      (setf (aref ether-transmit-addresses slot)
	    (+ (si:file-device-rqb-page-address ether-transmit-rqb (floor slot 2))
	       (* (logand slot 1) %ether-buffer-words))))
    (dotimes (slot %ether-receive-entries)
      (setf (aref ether-receive-addresses slot)
	    (+ (si:file-device-rqb-page-address ether-receive-rqb (floor slot 2))
	       (* (logand slot 1) %ether-buffer-words))))
    ;; the entries: a transmit entry is written when it is posted; a receive
    ;; entry names its buffer and the buffer's length, and the device writes
    ;; its word 2, the frame's length (section 2.3).
    (dotimes (entry (+ %ether-transmit-entries %ether-receive-entries))
      (dotimes (word %ether-entry-words)
	(ether-store-entry-word entry word 0)))
    (dotimes (slot %ether-receive-entries)
      (let ((entry (+ %ether-transmit-entries slot)))
	(ether-store-entry-word entry 0 (aref ether-receive-addresses slot))
	(ether-store-entry-word entry 1 %ether-buffer-bytes)))
    (ether-set-register %ether-transmit-base ether-ring-address)
    (ether-set-register %ether-transmit-size %ether-transmit-log2)
    (ether-set-register %ether-receive-base (+ ether-ring-address %ether-receive-ring-offset))
    (ether-set-register %ether-receive-size %ether-receive-log2)
    ;; enabled, interrupt enable off: the network process sets it before it
    ;; waits (ether-arm-interrupt).
    (ether-set-register %ether-control 1)
    (let ((status (ether-register %ether-status)))
      (unless (and (ldb-test %%ether-status-enabled status)
		   (not (ldb-test %%ether-status-refused status)))
	(return-from reset
	  (format nil "The Ethernet device refused its configuration (status ~O; rings at ~O)."
		  status ether-ring-address))))
    ;; the indexes read 0 after an enable.  every buffer is given at once.
    (setq ether-transmit-count 0 ether-receive-count 0
	  ether-receive-given %ether-receive-entries)
    (ether-set-register %ether-receive-producer ether-receive-given)
    (setq ether-last-status nil)
    (ether-update-totals)
    (setq ether-enabled t)
    nil))

;;;; Receive

(defsubst ether-frame-waiting-p ()
  "T if the device has filled a receive buffer that the driver has not taken."
  (not (= (ether-field %ether-receive-consumer #o0020) ether-receive-count)))

(defvar ether-handler-errors 0 "Errors a frame's handler signalled, each frame then dropped.")
(defvar ether-last-handler-error nil "The last error a frame's handler signalled, for debugging.")

(defun ether-take-frames (handler)
  "Call HANDLER on every received Ethernet frame waiting, in order, with the byte
array, the frame's first byte in it and its length; then write 252 and give the
buffers back through 250 (section 5.1).  Returns the number of frames taken.
An error in HANDLER drops its frame and is counted, so that the pass goes on."
  (let ((taken 0))
    (do ((consumer (ether-field %ether-receive-consumer #o0020)
		   (ether-field %ether-receive-consumer #o0020)))
	((= consumer ether-receive-count))
      (do () ((= consumer ether-receive-count))
	(let* ((slot (logand ether-receive-count (1- %ether-receive-entries)))
	       (length (ether-fetch-entry-word (+ %ether-transmit-entries slot) 2)))
	  (when (<= 14 length %ether-frame-max)
	    (condition-case (err)
		(funcall handler ether-receive-bytes (ether-receive-offset slot) length)
	      (error (incf ether-handler-errors)
		     (setq ether-last-handler-error err))))
	  (setq ether-receive-count (logand (1+ ether-receive-count) #o177777))
	  (incf ether-frames-received)
	  (incf taken))))
    (when (plusp taken)
      ;; 252 first, then 250: 250 - 252 may never exceed the ring's size.
      (ether-set-register %ether-receive-taken ether-receive-count)
      (setq ether-receive-given (logand (+ ether-receive-count %ether-receive-entries) #o177777))
      (ether-set-register %ether-receive-producer ether-receive-given))
    taken))

;;;; Transmit

(defun ether-transmit-slot-free-p (generation)
  (or (not (= generation ether-generation))
      (< (logand (- ether-transmit-count (ether-field %ether-transmit-consumer #o0020)) #o177777)
	 %ether-transmit-entries)))

(defun ether-transmit-slot ()
  "The transmit slot the next frame goes in, waiting for the device to pass one if
every slot is posted; returns the slot and the byte offset of its buffer in
ETHER-TRANSMIT-BYTES.  Call with the network lock held, and post the slot with
ETHER-POST before taking another."
  (declare (values slot offset))
  (let ((generation ether-generation))
    (unless (ether-transmit-slot-free-p generation)
      (process-wait "Ethernet transmit" #'ether-transmit-slot-free-p generation))
    (let ((slot (logand ether-transmit-count (1- %ether-transmit-entries))))
      (values slot (ether-transmit-offset slot)))))

(defun ether-post (slot length)
  "Post transmit SLOT, whose buffer holds an Ethernet frame of LENGTH bytes."
  (when ether-enabled
    (ether-store-entry-word slot 0 (aref ether-transmit-addresses slot))
    (ether-store-entry-word slot 1 length)
    (setq ether-transmit-count (logand (1+ ether-transmit-count) #o177777))
    (incf ether-frames-sent)
    ;; the register write drains the processor's write buffer first, so the
    ;; entry and the frame are in memory when the device reads them (section
    ;; 2.5).
    (ether-set-register %ether-transmit-producer ether-transmit-count)))

;;;; Bytes, big-endian, in an ART-8B array

(defsubst get-8 (bytes i) (aref bytes i))
(defsubst put-8 (bytes i value) (aset value bytes i))

(defsubst get-16 (bytes i)
  (dpb (aref bytes i) #o1010 (aref bytes (1+ i))))

(defsubst put-16 (bytes i value)
  (aset (ldb #o1010 value) bytes i)
  (aset (ldb #o0010 value) bytes (1+ i)))

;; 32 bits as a fixnum, the sign bit included, as register 255 reads, so that an
;; IPv4 address from 128.0.0.0 up is a negative fixnum and never a bignum.
(defsubst get-32 (bytes i)
  (%logdpb (aref bytes i) #o3010
	   (dpb (aref bytes (+ i 1)) #o2010
		(dpb (aref bytes (+ i 2)) #o1010 (aref bytes (+ i 3))))))

(defsubst put-32 (bytes i value)
  (aset (%logldb #o3010 value) bytes i)
  (aset (%logldb #o2010 value) bytes (+ i 1))
  (aset (%logldb #o1010 value) bytes (+ i 2))
  (aset (%logldb #o0010 value) bytes (+ i 3)))

;; a MAC address is two fixnums: its bytes 0-1 (HIGH) and 2-5 (LOW), as
;; registers 253 and 254 hold it.
(defsubst put-mac (bytes i high low)
  (put-16 bytes i high)
  (put-32 bytes (+ i 2) low))

(defconst %ether-type-ipv4 #x0800)
(defconst %ether-type-arp #x0806)
(defconst %broadcast-mac-high #xFFFF)
(defconst %broadcast-mac-low -1)

;;;; Time

;; the network's clock: the processor's microsecond clock, source 15, its low
;; 31 bits, a positive fixnum that wraps every 35.8 minutes.  (TIME) counts
;; 16,384 us, not a 60th, and a request one second after another by it would be
;; 0.983 s apart, under the contract's 1 s less a tick.  a time is compared with
;; another modulo 2^31, so a timer may lie at most 2^30 us, 17.9 minutes,
;; ahead; ARP's 10 minutes are the longest.
(defsubst network-now ()
  (%microsecond-clock-ldb #o0037))

(defsubst network-time-plus (time microseconds)
  (logand (+ time microseconds) #o17777777777))

(defsubst network-time-difference (later earlier)
  "Microseconds from EARLIER to LATER, modulo 2^31: negative if LATER is earlier."
  (let ((d (logand (- later earlier) #o17777777777)))
    (if (< d #o10000000000) d (- d #o20000000000))))

(defsubst network-time-reached-p (time)
  (< (logand (- (network-now) time) #o17777777777) #o10000000000))

;;;; The network process (sections 2.6 and 5.1)

(defvar network-process (make-process "Network" :warm-boot-action nil :priority 25.)
  "The network process: it takes every received Ethernet frame and runs the timers.")
(defvar network-lock nil "Held while the stack's state changes: the network process's pass, and senders.")
(defvar network-up nil "T while the network is started.")
(defconst %network-priority 25. "The network process's priority, and a sender's while it holds the lock.")
(defconst %network-fast-lead 2000000.
  "Microseconds: the clock's break comes every tick while a timer of the network's is due
within this (section 2.6).  2 s covers the slowest break, once a second, between the wait
predicate's look and the timer's due time.")
(defvar network-fast-clock nil "T while the network asks for the clock's break every tick.")
(defvar network-next-timer nil "The network clock's time the earliest timer is due, or NIL.")
(defvar network-passes 0 "The network process's passes since the band was built.")
(defvar network-receive-function nil "Called on each received Ethernet frame (SYS: NETWORK; IP; IPV4).")
(defvar network-timer-functions nil
  "Functions each called in every pass with the network clock's time, after the received
frames; each runs its due timers and returns the time of its next, or NIL.")
(defvar network-batch-functions nil
  "Functions called in every pass once the received frames are taken, before the timers:
TCP sends there the one ACK of each connection for the batch (section 5.1).")
(defvar network-start-functions nil
  "Functions called, with the network lock held, as the network starts, after the device's
reset.")

(defun network-yield ()
  "After a sender's work under the network lock: if the network process has frames or
a timer waiting, let it run now.  A sender at a lower priority that took the lock again
and again held it at most clock ticks, and the network process, finding it held at each,
waited: a TELNET session echoing a typed form one character at a time kept it off the
receive ring for 120 ms, and the ring overflowed."
  (when (and (not (eq current-process network-process)) (network-wakeup-p))
    (process-allow-schedule)))

;; the ceiling's raise and restore by :set-priority cost 0.78 ms a pair at
;; 19 ns on every lock section, half of it in process-reinsert-aentry and the
;; rest in the message, its check-type, process-active-entry's assq, the
;; pushnew on all-processes and set-process-wait (each measured apart, 10,000
;; times at the listener).  only the entry's place in si:active-processes
;; matters to the scheduler, so the raise moves the entry itself: the
;; microcoded assq and find-position-in-list find it, a walk over the
;; entries at 25 and above (a few) finds its new place, and %blt shifts the
;; ones between, as process-reinsert-aentry does.  the restore puts it back
;; where it was, which keeps the order if the entries around that place
;; still bracket its priority, and otherwise walks (network-move-entry).
;; before:
;(defun network-raise-priority ()
;  "Raise the current process to the network process's priority, if it is lower, and
;return the priority it had then, or NIL if it was not raised."
;  (let ((priority (send current-process :priority)))
;    (when (< priority %network-priority)
;      (send current-process :set-priority %network-priority)
;      priority)))
;
;(defun network-restore-priority (priority)
;  (send current-process :set-priority priority))

(defun network-shift-entry (entry from to)
  "Move ENTRY, at index FROM of SI:ACTIVE-PROCESSES, to index TO, the ones between moving
a place, as SI:PROCESS-REINSERT-AENTRY moves them: the list is cdr-coded and contiguous.
Called with interrupts off."
  (let ((ap si:active-processes))
    (cond ((= from to))
	  ((< from to)
	   (si:%blt (si:%make-pointer-offset si:dtp-list ap (1+ from))
		    (si:%make-pointer-offset si:dtp-list ap from)
		    (- to from) 1)
	   (si:%p-dpb-offset si:cdr-next si:%%q-cdr-code ap (1- to))
	   (setf (car (si:%make-pointer-offset si:dtp-list ap to)) entry))
	  (t
	   (let ((cdr-code (si:%p-ldb-offset si:%%q-cdr-code ap from)))
	     (si:%blt (si:%make-pointer-offset si:dtp-list ap (1- from))
		      (si:%make-pointer-offset si:dtp-list ap from)
		      (- from to) -1)
	     (si:%p-dpb-offset cdr-code si:%%q-cdr-code ap from))
	   (setf (car (si:%make-pointer-offset si:dtp-list ap to)) entry)))))

(defun network-move-entry (priority)
  "The restore's fallback: set the current process's priority to PRIORITY, other than its
own, and put its entry in SI:ACTIVE-PROCESSES where :SET-PRIORITY puts it: after every
entry of PRIORITY or above, before those below.  The list is in priority order, highest
first, free entries last; a process not on it only has its priority set, as :SET-PRIORITY
does."
  (without-interrupts
    (let ((old (si:process-priority current-process)))
      (setf (si:process-priority current-process) priority)
      (if (> priority old)
	  ;; raised, it moves forward: find the first entry below PRIORITY and the
	  ;; process's own, then shift those from the first up to its own back a place.
	  (do ((tail si:active-processes (cdr tail)) (start nil))
	      ((null tail))
	    (let ((e (car tail)))
	      (when (and (null start) (first e) (< (fourth e) priority)
			 (not (eq (first e) current-process)))
		(setq start tail))
	      (when (eq (first e) current-process)
		(setf (fourth e) priority)
		(when start
		  (do ((l start (cdr l)) (carry e))
		      ((eq l tail) (setf (car l) carry))
		    (psetf (car l) carry carry (car l))))
		(return))))
	;; lowered, it moves back: each entry after it of PRIORITY or above moves forward
	;; a place, into the hole, and the process's goes into the last hole.
	(do ((tail si:active-processes (cdr tail)) (hole nil) (entry nil))
	    ((null tail) (when entry (setf (car hole) entry)))
	  (let ((e (car tail)))
	    (cond (entry
		   (cond ((and (first e) (>= (fourth e) priority))
			  (setf (car hole) e)
			  (setq hole tail))
			 (t (setf (car hole) entry)
			    (return))))
		  ((eq (first e) current-process)
		   (setf (fourth e) priority)
		   (setq entry e hole tail)))))))))

(defun network-raise-priority ()
  "Raise the current process to the network process's priority, if it is lower.  Return
the priority it had then and its entry's index in SI:ACTIVE-PROCESSES before and after
the raise (NIL if it has none), or NIL if it was not raised."
  (without-interrupts
    (let ((priority (si:process-priority current-process)))
      (when (< priority %network-priority)
	(setf (si:process-priority current-process) %network-priority)
	(let* ((ap si:active-processes) (entry (assq current-process ap)))
	  (if (null entry)
	      (values priority nil nil)
	    ;; its new place: after every entry at 25 or above, all ahead of it,
	    ;; since it is below 25 and the list is in order; the walk stops at
	    ;; the first entry below 25, its own at the latest.  each step of a
	    ;; compiled walk costs about what the microcoded assq costs for the
	    ;; whole list, so the walk is over those few only.
	    (let ((from (find-position-in-list entry ap))
		  (to (do ((l ap (cdr l)) (i 0 (1+ i)))
			  ((< (fourth (car l)) %network-priority) i))))
	      (setf (fourth entry) %network-priority)
	      (network-shift-entry entry from to)
	      (values priority from to))))))))

(defun network-restore-priority (priority from to)
  "Undo NETWORK-RAISE-PRIORITY: back to PRIORITY and the entry from index TO back to index
FROM, if it is still at TO and the entries around FROM then bracket PRIORITY; else
NETWORK-MOVE-ENTRY puts it where :SET-PRIORITY would."
  (without-interrupts
    (let* ((tail (and to (nthcdr to si:active-processes))) (entry (car tail)))
      (if (not (and entry (eq (first entry) current-process)))
	  (network-move-entry priority)
	;; after the move the entry at FROM - 1 is the one now at FROM, and the
	;; one at FROM + 1 stays: the first must be a process's at PRIORITY or
	;; above, the second at PRIORITY or below, or free, or none.  with no
	;; move (FROM = TO) the one above is at 25 or above.  the rest of the list
	;; is in order, as every move keeps it.
	(let* ((ftail (nthcdr (- from to) tail))
	       (above (and (/= from to) (car ftail)))
	       (below (cadr ftail)))
	  (if (and ftail
		   (or (null above) (and (first above) (>= (fourth above) priority)))
		   (or (null below) (null (first below)) (<= (fourth below) priority)))
	      (progn (setf (si:process-priority current-process) priority)
		     (setf (fourth entry) priority)
		     (network-shift-entry entry to from))
	    (network-move-entry priority)))))))

;; the priority ceiling (m-ack; the contract's section 5.1, senders): a sender
;; at a user's priority, preempted by the clock's break while it held the lock,
;; waited behind a compute-bound process of its own priority for that
;; process's whole quantum, a second, and the network process, at 25, waited
;; on the lock with it: no ack went out for a second.  so a sender is raised
;; to the network process's priority before it takes the lock and restored
;; after it releases it, at the outermost hold only (with-lock recurses), in
;; an unwind-protect; a holder that waits inside the lock waits at 25 too.
;; the yield comes after the restore, at the outermost hold.  before:
;(defmacro with-network-lock (&body body)
;  "BODY with the network lock held, for a sender, then NETWORK-YIELD."
;  `(multiple-value-prog1 (with-lock (network-lock) . ,body)
;			 (network-yield)))
(defmacro with-network-lock (&body body)
  "BODY with the network lock held, for a sender, at the network process's priority;
then, at the outermost hold, the priority restored and NETWORK-YIELD."
  ;; the raise's three values (the priority, the entry's index before and
  ;; after) go back to the restore, which undoes the move.  before:
  ;(let ((outer (gensym)) (priority (gensym)))
  ;  `(let ((,outer (not (eq network-lock current-process))) (,priority nil))
  ;     (multiple-value-prog1
  ;	 (unwind-protect
  ;	     (progn (when ,outer (setq ,priority (network-raise-priority)))
  ;		    (with-lock (network-lock) . ,body))
  ;	   (when ,priority (network-restore-priority ,priority)))
  ;	 (when ,outer (network-yield))))))
  (let ((outer (gensym)) (priority (gensym)) (from (gensym)) (to (gensym)))
    `(let ((,outer (not (eq network-lock current-process))) (,priority nil) (,from nil) (,to nil))
       (multiple-value-prog1
	 (unwind-protect
	     (progn (when ,outer (multiple-value-setq (,priority ,from ,to) (network-raise-priority)))
		    (with-lock (network-lock) . ,body))
	   (when ,priority (network-restore-priority ,priority ,from ,to)))
	 (when ,outer (network-yield))))))

(defun network-note-timer (time)
  "A timer is due at TIME: wake the network process then, if not earlier."
  (without-interrupts
    (when (or (null network-next-timer)
	      (minusp (network-time-difference time network-next-timer)))
      (setq network-next-timer time))))

;; before the fallback (section 2.6) the predicate was a frame waiting or a
;; timer due:
;(defun network-wakeup-p ()
;  "The network process's wait predicate: a frame waiting or a timer due."
;  (or (ether-frame-waiting-p)
;      (let ((due network-next-timer))
;	(and due (network-time-reached-p due)))))
(defun network-wakeup-p ()
  "The network process's wait predicate: a frame waiting, a timer due, or a timer due
within %NETWORK-FAST-LEAD while the clock's break is not every tick."
  (or (ether-frame-waiting-p)
      (let ((due network-next-timer))
	(and due (or (network-time-reached-p due)
		     (and (not network-fast-clock)
			  (< (network-time-difference due (network-now)) %network-fast-lead)))))))

(defun network-clock-rule ()
  "Ask for the clock's break every tick while a timer of the network's is due within
%NETWORK-FAST-LEAD, and withdraw the request otherwise; only when that changes, since a
request conses (section 2.6)."
  (let ((fast (let ((due network-next-timer))
		(and due (< (network-time-difference due (network-now)) %network-fast-lead)))))
    (unless (eq (not fast) (not network-fast-clock))
      (setq network-fast-clock (not (null fast)))
      (si:request-clock-rate :network (and fast 1)))))

(defun ether-arm-interrupt ()
  "Set register 240 <8>, the interrupt enable, with the device enabled: the next frame
waiting, or one waiting now, interrupts, and the microcode clears <8> and asks for a
sequence break (section 2.6).  Writing 240 also clears 241 <2> and <3>, which only the
reset reads."
  (when ether-enabled
    (ether-set-register %ether-control %ether-control-armed)))

(defun network-pass ()
  "One pass of the network process: every frame waiting, then the timers (section 5.1)."
  (with-lock (network-lock)
    (incf network-passes)
    (ether-update-totals)
    (when network-receive-function
      (ether-take-frames network-receive-function))
    (dolist (f network-batch-functions) (funcall f))
    (setq network-next-timer nil)
    (let ((now (network-now)))
      (dolist (f network-timer-functions)
	(let ((next (funcall f now)))
	  (when next (network-note-timer next)))))))

(defun network-top-level (&optional starting)
  ;; the start's work (the addresses, the gratuitous ARP) is the process's own
  ;; first act, so that at boot it comes once the boot's initializations have
  ;; ended and the scheduler runs: done from the warm initialization itself,
  ;; the frames that followed the gratuitous ARP waited some 80 ms for the
  ;; boot to finish, outside the bounds of the timers that start on them.
  (when starting
    (with-lock (network-lock)
      (setq network-next-timer nil)
      (dolist (f network-start-functions) (funcall f)))
    (setq network-up t))
  ;; before each wait: the clock's rate by its rule, then the interrupt armed,
  ;; so that a frame arriving at any time after the pass wakes the process.
  (do-forever
;   (process-wait "Network" #'network-wakeup-p)	;before the fallback (2.6)
    (network-clock-rule)
    (ether-arm-interrupt)
    (process-wait "Network" #'network-wakeup-p)
    (network-pass)))

(defun network-stop ()
  "Stop the network: the process, the device, and the clock's rate it asked for."
  (setq network-up nil)
  (process-disable network-process)
  (ether-disable)
  (si:request-clock-rate :network nil)
  (setq network-fast-clock nil)
  nil)

(defun network-start ()
  "Start the network: reset the Ethernet device, take the band's addresses from it,
and start the network process (section 5.1).  Returns T, or NIL and a message."
  (block start
    (network-stop)
    ;; a process that held the lock when the machine stopped is gone.
    (setq network-lock nil)
    (let ((message (ether-reset)))
      (when message (return-from start (values nil message))))
    (send network-process :preset 'network-top-level t)
    (process-enable network-process)
    ;; the clock's sequence break every tick only while a timer of the
    ;; network's is due within 2 s: the process asks, by network-clock-rule,
    ;; before each wait (2.6).  until the fallback it came every tick while
    ;; the network was up, which cost an idle band 12-13% (m-ack):
;   (si:request-clock-rate :network 1)
    t))

(defun network-boot-start ()
  "At boot and at warm boot: start the network if the machine has the device and
the host gave the band an address (section 5.1)."
  (when (and (ether-present-p) (not (zerop (ether-register %ether-ip-address))))
    (multiple-value-bind (ok message) (network-start)
      (unless ok
	(format t "~&~A~%" message)))))

;; no dma while disk-save writes memory out.
(add-initialization "Network off" '(network-stop) '(:before-cold))
(add-initialization "Network" '(network-boot-start) '(:warm))
