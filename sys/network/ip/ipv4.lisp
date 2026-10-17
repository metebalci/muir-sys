;;; -*- Mode:LISP; Package:INTERNET; Base:10; Readtable:ZL -*-
;;;
;;; This is SYS: NETWORK; IP; IPV4
;;;
;;; quux revision 16: ARP, IPv4 and ICMP echo over quux's ethernet device
;;; (QUUX's Ethernet contract, sections 5.2-5.4), and PING.  they run in the
;;; network process's pass (SYS: NETWORK; IP; ETHER), and a sender, a user
;;; process, builds and posts its datagram under the network lock.  the device
;;; fills in and checks every checksum (section 2.4), so no checksum is
;;; computed or checked here: a field is left 0.
;;;
;;; the band's address, netmask and gateway are the host's, registers 255-257,
;;; read when the network starts (section 5.6).  there is always a gateway: a
;;; destination on the subnet is sent to directly, any other through the
;;; gateway (section 5.3).  no fragments are sent, and none is taken.

;;;; Addresses

;; an IPv4 address is a fixnum, a.b.c.d as a<<24|b<<16|c<<8|d with the sign bit
;; included (from 128.0.0.0 up negative), as register 255 reads it.
(defvar my-address 0 "The band's IPv4 address, register 255.")
(defvar my-netmask 0 "The band's netmask, register 256.")
(defvar my-gateway 0 "The band's gateway, register 257: always one, on the subnet.")
(defvar my-mac-high 0 "The band's MAC address, bytes 0-1: register 253.")
(defvar my-mac-low 0 "The band's MAC address, bytes 2-5: register 254.")

(defun parse-address (address)
  "An IPv4 address as a fixnum, from a dotted string such as 192.0.2.1, or a fixnum."
  (if (integerp address)
      address
    (let ((start 0) (value 0))
      (dotimes (k 4)
	(let ((end (if (= k 3) (string-length address) (string-search-char #/. address start))))
	  (unless end
	    (ferror nil "~S is not a dotted IPv4 address." address))
	  (let ((byte (parse-integer address :start start :end end)))
	    (unless (<= 0 byte 255)
	      (ferror nil "~S is not a dotted IPv4 address." address))
	    (setq value (%logdpb byte (- #o3010 (* k #o1000)) value)))
	  (setq start (1+ end))))
      value)))

(defun address-string (address)
  "The dotted form of the IPv4 address ADDRESS, a fixnum."
  (format nil "~D.~D.~D.~D" (%logldb #o3010 address) (%logldb #o2010 address)
	  (%logldb #o1010 address) (%logldb #o0010 address)))

(defsubst on-subnet-p (address)
  (= (logand address my-netmask) (logand my-address my-netmask)))

(defun broadcast-address-p (address)
  "T for the limited broadcast, 255.255.255.255, and the band's subnet's broadcast."
  (or (= address -1)
      (= address (logior (logand my-address my-netmask) (lognot my-netmask)))))

(defun next-hop (address)
  "The address a datagram to ADDRESS is sent to on the link (section 5.3)."
  (if (on-subnet-p address) address my-gateway))

;;;; Counts: what the stack drops, outside 241 (sections 5.3 and 5.4)

(defvar ipv4-not-for-us 0 "Received datagrams for another address, or malformed.")
(defvar ipv4-fragments-dropped 0 "Received fragments, dropped (section 5.3).")
(defvar ipv4-source-routes-dropped 0 "Received datagrams with a source route, dropped.")
(defvar ipv4-protocols-dropped 0 "Received datagrams of a protocol not taken.")
(defvar icmp-types-dropped 0 "Received ICMP messages of a type not taken.")
(defvar arp-dropped 0 "Received ARP packets not for Ethernet and IPv4, or malformed.")
(defvar arp-held-dropped 0 "Datagrams dropped after three ARP requests went unanswered.")

(defun network-counts ()
  "A plist of the stack's counts and the driver's totals, for tests and PEEK."
  (ether-update-totals)
  (list :passes network-passes :sent ether-frames-sent :received ether-frames-received
	:type-filter ether-type-filter-total :ipv4-checks ether-ipv4-checks-total
	:no-buffer ether-dropped-total :refused ether-refused-total
	:not-for-us ipv4-not-for-us :fragments ipv4-fragments-dropped
	:source-routes ipv4-source-routes-dropped :protocols ipv4-protocols-dropped
	:icmp-types icmp-types-dropped :arp-dropped arp-dropped :arp-held-dropped arp-held-dropped
	:handler-errors ether-handler-errors))

;;;; ARP (RFC 826; RFC 1122 2.3.2; QUUX's Ethernet contract, 5.2)

(defconst %arp-cache-size 16)
(defconst %arp-lifetime (* 600. 1000000.)
  "Microseconds an entry is kept from the last ARP packet whose sender is its address.")
(defconst %arp-interval 1000000. "Microseconds between two requests for one address, at least.")
(defconst %arp-requests 3 "Requests for one resolution before its datagram is dropped.")

;; the cache: a slot is free when its address is NIL.  entries are kept 10
;; minutes from the last ARP packet whose sender is their address, a request
;; or a reply, whatever its target, even while used; neither sending to the
;; address nor receiving from it keeps an entry (RFC 1122 2.3.2.1, its first
;; mechanism).  the least recently used is replaced.
(defvar arp-cache-address (make-array %arp-cache-size))
(defvar arp-cache-mac-high (make-array %arp-cache-size))
(defvar arp-cache-mac-low (make-array %arp-cache-size))
(defvar arp-cache-refreshed (make-array %arp-cache-size) "The network clock's time of the entry's last ARP packet.")
(defvar arp-cache-used (make-array %arp-cache-size) "ARP-USE-COUNT at the entry's last use.")
(defvar arp-use-count 0)

;; resolutions in progress: the newest datagram held for an address with no
;; entry, the requests sent for it and when the next is due.  one that comes
;; while another is held replaces it, and the count goes on; once the third
;; request has gone unanswered for ARP's interval, the held datagram is
;; dropped and no fourth request is sent, and a datagram after that starts
;; anew.  the record stays, with nothing held, for the time of its last
;; request, so that a new resolution still sends at most one a second.
;; a resolution is an array of 6 words, read and set through these substs.
;; no defstruct: the cross build cannot give a new structure to the compile
;; for the target without changing the builder's world (sys/cold/cross.lisp,
;; cross-declare-definitions), and a subst it gives.
(defsubst arp-resolution-address (r) (aref r 0))
(defsubst arp-resolution-held (r) (aref r 1))		;an ART-8B array holding the frame, or NIL
(defsubst arp-resolution-held-length (r) (aref r 2))
(defsubst arp-resolution-requests (r) (aref r 3))	;requests sent for the datagram held
(defsubst arp-resolution-last-request (r) (aref r 4))	;the network clock's time of the last request, or NIL
(defsubst arp-resolution-due (r) (aref r 5))		;the next request's or the drop's time, or NIL

(defun make-arp-resolution (address)
  (let ((r (make-array 6)))
    (setf (aref r 0) address (aref r 1) nil (aref r 2) 0 (aref r 3) 0 (aref r 4) nil (aref r 5) nil)
    r))

(defun arp-resolution-for (address)
  "The resolution of ADDRESS in ARP-RESOLUTIONS, or NIL."
  (dolist (r arp-resolutions)
    (when (eql (arp-resolution-address r) address) (return r))))

(defvar arp-resolutions nil "Every ARP-RESOLUTION, one an address.")

(defun arp-reset ()
  "Forget every entry and every resolution."
  (dotimes (i %arp-cache-size)
    (setf (aref arp-cache-address i) nil))
  (setq arp-resolutions nil arp-use-count 0))

(defun arp-entry (address)
  "The cache slot holding ADDRESS, if it is there and not expired."
  (dotimes (i %arp-cache-size)
    (when (and (eql (aref arp-cache-address i) address)
	       (< (network-time-difference (network-now) (aref arp-cache-refreshed i)) %arp-lifetime))
      (return i))))

(defun arp-learn (address mac-high mac-low &optional (slot (arp-entry address)))
  "Enter or update ADDRESS's entry, its 10 minutes restarted."
  (unless slot
    ;; a free slot, or the least recently used.
    (setq slot 0)
    (dotimes (i %arp-cache-size)
      (cond ((null (aref arp-cache-address i)) (return (setq slot i)))
	    ((< (aref arp-cache-used i) (aref arp-cache-used slot)) (setq slot i))))
    (setf (aref arp-cache-used slot) (incf arp-use-count)))
  (setf (aref arp-cache-address slot) address
	(aref arp-cache-mac-high slot) mac-high
	(aref arp-cache-mac-low slot) mac-low
	(aref arp-cache-refreshed slot) (network-now))
  slot)

(defun arp-forget (address)
  "Remove ADDRESS's entry: TCP's negative advice (MUST-20, section 5.2)."
  (let ((slot (arp-entry address)))
    (when slot (setf (aref arp-cache-address slot) nil))))

(defun arp-send (op target-mac-high target-mac-low target-address &optional
		 (dest-high %broadcast-mac-high) (dest-low %broadcast-mac-low))
  "Send an ARP packet for Ethernet and IPv4 of operation OP, the band the sender."
  (multiple-value-bind (slot o) (ether-transmit-slot)
    (let ((b ether-transmit-bytes))
      (put-mac b o dest-high dest-low)
      (put-mac b (+ o 6) my-mac-high my-mac-low)
      (put-16 b (+ o 12) %ether-type-arp)
      (put-16 b (+ o 14) 1)			;Ethernet
      (put-16 b (+ o 16) %ether-type-ipv4)
      (put-8 b (+ o 18) 6)
      (put-8 b (+ o 19) 4)
      (put-16 b (+ o 20) op)
      (put-mac b (+ o 22) my-mac-high my-mac-low)
      (put-32 b (+ o 28) my-address)
      (put-mac b (+ o 32) target-mac-high target-mac-low)
      (put-32 b (+ o 38) target-address)
      ;; 42 bytes: padding to 60 is the host side's (section 2.3).
      (ether-post slot 42))))

(defun arp-send-gratuitous ()
  "One gratuitous ARP as the network starts: a broadcast request whose sender and
target addresses are both the band's (RFC 5944 4.6; RFC 5227 3)."
  (arp-send 1 0 0 my-address))

(defun arp-request (r)
  "Send a request for resolution R's address now, and set its next time."
  (let ((now (network-now)))
    (arp-send 1 0 0 (arp-resolution-address r))
    (incf (arp-resolution-requests r))
    (setf (arp-resolution-last-request r) now
	  (arp-resolution-due r) (network-time-plus now %arp-interval))
    (network-note-timer (arp-resolution-due r))))

(defun arp-hold (address bytes offset length)
  "Hold the frame of LENGTH bytes at OFFSET in BYTES, an IPv4 datagram to ADDRESS
with no ARP entry, in place of any held before; start its resolution if none runs."
  (let ((r (arp-resolution-for address)))
    (unless r
      (push (setq r (make-arp-resolution address)) arp-resolutions))
    (unless (arp-resolution-held r)
      (setf (arp-resolution-held r) (make-array %ether-frame-max :type 'art-8b)))
    (copy-array-portion bytes offset (+ offset length) (arp-resolution-held r) 0 length)
    (setf (arp-resolution-held-length r) length)
    (when (zerop (arp-resolution-requests r))
      ;; a new resolution: its first request now, or a second after the last
      ;; request for the address, whichever is later.
      (let ((last (arp-resolution-last-request r)))
	(if (and last (< (network-time-difference (network-now) last) %arp-interval))
	    (progn (setf (arp-resolution-due r) (network-time-plus last %arp-interval))
		   (network-note-timer (arp-resolution-due r)))
	  (arp-request r))))))

(defun arp-send-held (r slot)
  "Send resolution R's held datagram, now that cache SLOT has its address."
  (let ((held (arp-resolution-held r)) (length (arp-resolution-held-length r)))
    (setf (arp-resolution-held r) nil
	  (arp-resolution-requests r) 0
	  (arp-resolution-due r) nil)
    (when (and held (plusp length))
      (multiple-value-bind (tslot o) (ether-transmit-slot)
	(copy-array-portion held 0 length ether-transmit-bytes o (+ o length))
	(put-mac ether-transmit-bytes o (aref arp-cache-mac-high slot) (aref arp-cache-mac-low slot))
	(setf (aref arp-cache-used slot) (incf arp-use-count))
	(ether-post tslot length)))))

(defun arp-timers (now)
  "ARP's timers: requests due, held datagrams dropped, entries expired.  Returns the
time of the next."
  (let ((next nil))
    (flet ((note (time)
	     (when (or (null next) (minusp (network-time-difference time next)))
	       (setq next time))))
      (dolist (r arp-resolutions)
	(let ((due (arp-resolution-due r)))
	  (when due
	    (cond ((minusp (network-time-difference now due))
		   (note due))
		  ((null (arp-resolution-held r))
		   (setf (arp-resolution-due r) nil))
		  ((< (arp-resolution-requests r) %arp-requests)
		   (arp-request r)
		   (note (arp-resolution-due r)))
		  (t
		   ;; the third request unanswered for the interval: the datagram
		   ;; is dropped and no fourth request goes.
		   (setf (arp-resolution-held r) nil
			 (arp-resolution-requests r) 0
			 (arp-resolution-due r) nil)
		   (incf arp-held-dropped))))))
      ;; drop the records with nothing held whose last request is more than a
      ;; second old: they no longer bound the rate.
      (setq arp-resolutions
	    (del-if #'(lambda (r)
			(and (null (arp-resolution-held r))
			     (or (null (arp-resolution-last-request r))
				 (>= (network-time-difference now (arp-resolution-last-request r))
				     %arp-interval))))
		    arp-resolutions))
      (dolist (r arp-resolutions)
	(when (and (null (arp-resolution-held r)) (arp-resolution-last-request r))
	  (note (network-time-plus (arp-resolution-last-request r) %arp-interval))))
      ;; entries: each expires 10 minutes after its refresh.
      (dotimes (i %arp-cache-size)
	(when (aref arp-cache-address i)
	  (let ((end (network-time-plus (aref arp-cache-refreshed i) %arp-lifetime)))
	    (if (minusp (network-time-difference now end))
		(note end)
	      (setf (aref arp-cache-address i) nil))))))
    next))

(defun arp-receive (b o n)
  "An ARP packet, at O in B, N bytes in its frame: RFC 826's packet reception."
  (if (or (< n 42)
	  (not (= (get-16 b (+ o 14)) 1))
	  (not (= (get-16 b (+ o 16)) %ether-type-ipv4))
	  (not (= (get-8 b (+ o 18)) 6))
	  (not (= (get-8 b (+ o 19)) 4)))
      (incf arp-dropped)
    (let* ((op (get-16 b (+ o 20)))
	   (sender-high (get-16 b (+ o 22)))
	   (sender-low (get-32 b (+ o 24)))
	   (sender (get-32 b (+ o 28)))
	   (target (get-32 b (+ o 38)))
	   (slot (arp-entry sender))
	   (merge nil))
      ;; the merge: an entry for the sender is updated, and its 10 minutes
      ;; restart, whatever the target.  none is made for 0.0.0.0, a probe's
      ;; sender, or for the band's own address.
      (when (and slot (not (= sender my-address)))
	(arp-learn sender sender-high sender-low slot)
	(setq merge t))
      (when (= target my-address)
	(unless (or merge (zerop sender) (= sender my-address))
	  (setq slot (arp-learn sender sender-high sender-low)))
	(when (= op 1)
	  (arp-send 2 sender-high sender-low sender sender-high sender-low)))
      ;; a datagram held for the sender goes, now that it has an entry.
      (let ((r (arp-resolution-for sender)))
	(when (and r (arp-resolution-held r))
	  (let ((slot (arp-entry sender)))
	    (when slot (arp-send-held r slot))))))))

;;;; IPv4 (RFC 791; RFC 1122 3; QUUX's Ethernet contract, 5.3)

(defvar *ipv4-ttl* 64 "The time to live of every datagram the band sends.")
(defvar ipv4-identification 0
  "The identification of the next datagram sent: a counter, so that none repeats within
65,536 datagrams (DF is clear, section 5.3).")

(defvar ipv4-tcp-function nil
  "Called on each TCP segment for the band, with the byte array, the source, the
segment's first byte and its length (SYS: NETWORK; IP; TCP).")

(defconst %ipv4-header 20 "Bytes of the header the band sends: IHL 5, no options.")
(defconst %ipv4-protocol-icmp 1)
(defconst %ipv4-protocol-tcp 6)

(defun ipv4-datagram-slot ()
  "A transmit slot for a datagram: returns the slot, the byte array and the offset of
the datagram's payload in it, after the Ethernet and IPv4 headers."
  (declare (values slot bytes payload-offset))
  (multiple-value-bind (slot o) (ether-transmit-slot)
    (values slot ether-transmit-bytes (+ o 14 %ipv4-header))))

(defun ipv4-send (slot destination protocol payload-length)
  "Send the datagram whose payload, PAYLOAD-LENGTH bytes, is in transmit SLOT's buffer:
the IPv4 header filled in, the next hop resolved, and the frame posted, or held for
ARP.  The header checksum is the device's.  Call with the network lock held."
  (let* ((b ether-transmit-bytes)
	 (o (ether-transmit-offset slot))
	 (total (+ %ipv4-header payload-length))
	 (length (+ 14 total))
	 (hop (next-hop destination)))
    (put-8 b (+ o 14) #x45)			;version 4, IHL 5
    (put-8 b (+ o 15) 0)			;TOS 0
    (put-16 b (+ o 16) total)
    (put-16 b (+ o 18) ipv4-identification)
    (setq ipv4-identification (logand (1+ ipv4-identification) #o177777))
    (put-16 b (+ o 20) 0)			;DF clear, not a fragment
    (put-8 b (+ o 22) *ipv4-ttl*)
    (put-8 b (+ o 23) protocol)
    (put-16 b (+ o 24) 0)			;the device fills in the checksum
    (put-32 b (+ o 26) my-address)
    (put-32 b (+ o 30) destination)
    (put-mac b (+ o 6) my-mac-high my-mac-low)
    (put-16 b (+ o 12) %ether-type-ipv4)
    (let ((entry (and (not (broadcast-address-p destination)) (arp-entry hop))))
      (cond ((broadcast-address-p destination)
	     ;; the subnet's broadcast, or the limited one, goes to the
	     ;; Ethernet broadcast address, with no ARP (RFC 1122 3.3.6).
	     (put-mac b o %broadcast-mac-high %broadcast-mac-low)
	     (ether-post slot length))
	    (entry
	     (put-mac b o (aref arp-cache-mac-high entry) (aref arp-cache-mac-low entry))
	     (setf (aref arp-cache-used entry) (incf arp-use-count))
	     (ether-post slot length))
	    (t
	     ;; not posted: the slot is used again by the next frame, and the
	     ;; datagram goes from the held copy once the hop is resolved.
	     (arp-hold hop b o length))))))

(defun ipv4-source-route-p (b o header)
  "T if the options of the IPv4 header at O, HEADER bytes long, hold a loose or strict
source route (section 5.3: such a datagram is dropped, as RFC 7126 advises)."
  (do ((i (+ o 20)) (end (+ o header)))
      ((>= i end) nil)
    (let ((type (get-8 b i)))
      (cond ((= type 0) (return nil))		;end of options
	    ((= type 1) (incf i))		;no operation
	    ((or (= type 131) (= type 137)) (return t))
	    ((>= (1+ i) end) (return nil))
	    (t (let ((n (get-8 b (1+ i))))
		 (when (< n 2) (return nil))	;a bad length ends the scan; IHL skips them
		 (incf i n)))))))

(defun ipv4-receive (b o n)
  "An IPv4 datagram at O in B, its frame N bytes.  The device has checked its header
checksum, its well-formedness and, for ICMP, TCP and UDP, their checksums (2.4)."
  (let* ((ip (+ o 14))
	 (version-ihl (get-8 b ip))
	 (header (* 4 (logand version-ihl 15)))
	 (total (get-16 b (+ ip 2))))
    (cond ((or (not (= (ash version-ihl -4) 4))
	       (< header 20)
	       (< total header)
	       (> (+ 14 total) n)
	       (not (= (get-32 b (+ ip 16)) my-address)))
	   (incf ipv4-not-for-us))
	  ((not (zerop (logand (get-16 b (+ ip 6)) #o37777)))
	   ;; MF set or a fragment offset, DF aside: no reassembly in step one.
	   (incf ipv4-fragments-dropped))
	  ((and (> header 20) (ipv4-source-route-p b ip header))
	   (incf ipv4-source-routes-dropped))
	  (t
	   (let ((protocol (get-8 b (+ ip 9))))
	     (cond ((= protocol %ipv4-protocol-icmp)
		    (icmp-receive b (get-32 b (+ ip 12)) (+ ip header) (- total header)))
		   ((and (= protocol %ipv4-protocol-tcp) ipv4-tcp-function)
		    (funcall ipv4-tcp-function b (get-32 b (+ ip 12)) (+ ip header) (- total header)))
		   ;; any other protocol is dropped and counted.
		   (t (incf ipv4-protocols-dropped))))))))

(defun network-receive (b o n)
  "The network process's handler of every received Ethernet frame."
  (let ((type (get-16 b (+ o 12))))
    (cond ((= type %ether-type-ipv4) (ipv4-receive b o n))
	  ((= type %ether-type-arp) (arp-receive b o n))
	  ;; the type filter passes nothing else (section 2.4).
	  (t nil))))

;;;; ICMP (RFC 792; RFC 1122 3.2.2; QUUX's Ethernet contract, 5.4)

(defconst %icmp-echo-reply 0)
(defconst %icmp-echo-request 8)

(defun icmp-echo-reply (b source p length)
  "Answer the echo request of LENGTH bytes at P in B from SOURCE: the same
identifier, sequence and data, type 0.  Its checksum is the device's."
  (multiple-value-bind (slot tb to) (ipv4-datagram-slot)
    (copy-array-portion b (+ p 4) (+ p length) tb (+ to 4) (+ to length))
    (put-8 tb to %icmp-echo-reply)
    (put-8 tb (+ to 1) 0)
    (put-16 tb (+ to 2) 0)
    (ipv4-send slot source %ipv4-protocol-icmp length)))

;; pings waiting for their replies: elements (identifier sequence . reply),
;; the reply's network clock time once it came.
(defvar ping-waiters nil)

(defun icmp-receive (b source p length)
  "An ICMP message of LENGTH bytes at P in B, from SOURCE."
  ;; the device dropped an ICMP message under 8 bytes (2.4.2).
  (let ((type (get-8 b p)) (code (get-8 b (1+ p))))
    (cond ((and (= type %icmp-echo-request) (= code 0))
	   (icmp-echo-reply b source p length))
	  ((and (= type %icmp-echo-reply) (= code 0))
	   ;; a ping's reply, matched by identifier and sequence; any other is
	   ;; ignored.
	   (let ((w (assoc-ping (get-16 b (+ p 4)) (get-16 b (+ p 6)))))
	     (when (and w (null (cddr w)))
	       (setf (cddr w) (network-now)))))
	  (t (incf icmp-types-dropped)))))

(defun assoc-ping (identifier sequence)
  (dolist (w ping-waiters)
    (when (and (= (car w) identifier) (= (cadr w) sequence))
      (return w))))

;;;; PING (QUUX's Ethernet contract, 5.4)

(defvar ping-identifier #x4C4D "The identifier of the band's echo requests.")
(defvar ping-sequence 0 "The sequence of the band's last echo request.")
(defconst %ping-data-length 56)

(defun ping-replied-p (waiter deadline)
  (or (cddr waiter) (network-time-reached-p deadline)))

(defun ping (address &key (timeout 1) (stream *standard-output*))
  "Send one ICMP echo request to ADDRESS, a dotted string, and wait TIMEOUT seconds
(at least 1) for the reply that matches it by identifier and sequence, ignoring any
other.  Prints the round trip.  Returns the reply's identifier and sequence, or NIL."
  (declare (values identifier sequence microseconds))
  ;; the network's start is its process's first act: give it two seconds.
  (unless network-up
    (process-wait-with-timeout "Network start" 120. #'symbol-value 'network-up))
  (unless network-up
    (ferror nil "The network is not up."))
  (let* ((destination (parse-address address))
	 (sequence (setq ping-sequence (logand (1+ ping-sequence) #o177777)))
	 (waiter (list* ping-identifier sequence nil))
	 (start nil) (deadline nil))
    (unwind-protect
	(progn
	  (with-network-lock
	    (push waiter ping-waiters)
	    (multiple-value-bind (slot b o) (ipv4-datagram-slot)
	      (put-8 b o %icmp-echo-request)
	      (put-8 b (+ o 1) 0)
	      (put-16 b (+ o 2) 0)
	      (put-16 b (+ o 4) ping-identifier)
	      (put-16 b (+ o 6) sequence)
	      (dotimes (i %ping-data-length)
		(put-8 b (+ o 8 i) (logand i #o377)))
	      (setq start (network-now)
		    deadline (network-time-plus start (* (max timeout 1) 1000000.)))
	      (ipv4-send slot destination %ipv4-protocol-icmp (+ 8 %ping-data-length))))
	  (process-wait "Ping" #'ping-replied-p waiter deadline)
	  (cond ((cddr waiter)
		 (let ((round-trip (network-time-difference (cddr waiter) start)))
		   (format stream "~&~A: id ~D seq ~D, ~D.~3,'0D ms~%" (address-string destination)
			   ping-identifier sequence (floor round-trip 1000) (mod round-trip 1000))
		   (values ping-identifier sequence round-trip)))
		(t
		 (format stream "~&~A: no reply in ~D s~%" (address-string destination) (max timeout 1))
		 nil)))
      (without-interrupts
	(setq ping-waiters (delq waiter ping-waiters))))))

;;;; Starting

(defun ipv4-start ()
  "As the network starts: the addresses from the device, ARP afresh, one gratuitous ARP."
  (setq my-address (ether-register %ether-ip-address)
	my-netmask (ether-register %ether-ip-netmask)
	my-gateway (ether-register %ether-ip-gateway)
	my-mac-high (ether-field %ether-mac-high #o0020)
	my-mac-low (ether-register %ether-mac-low))
  (arp-reset)
  (setq ping-waiters nil)
  (arp-send-gratuitous))

(setq network-receive-function 'network-receive)
(or (memq 'arp-timers network-timer-functions) (push 'arp-timers network-timer-functions))
(or (memq 'ipv4-start network-start-functions) (push 'ipv4-start network-start-functions))
