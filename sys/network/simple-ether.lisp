;;;-*- Mode:LISP; Package:ETHERNET; Base:8. -*-


;simple ethernet hacker.  This file is self contained except for change to
; CHAOS:TRANSMIT-INT-PKT!!!

(defvar *lambda-has-ethernet* t)

(defvar *use-ethernet* t)


(defvar *ethernet-packets-received* 0)
(defvar *ethernet-packets-transmitted* 0)
(defvar *ethernet-packets-not-transmitted-xmit-buffer-not-available* 0)
(defvar *ethernet-chaos-pkts-transmitted* 0)	;incremented by TRANSMIT-INT-PKT
(defvar *ethernet-chaos-pkts-not-transmitted-lacking-ethernet-address* 0)  ;ditto
(defvar *ethernet-chaos-pkts-received* 0)
(defvar *ethernet-chaos-pkts-too-big-to-unwrap* 0)
(defvar *ethernet-address-resolution-pkts-received* 0)
(defvar *ethernet-echo-server-requests* 0)
(defvar *ethernet-unknown-protocol-pkts-received* 0)
(defvar *ethernet-last-unknown-protocol-type* 0)
(defvar *ethernet-transmit-time-outs* 0)
(defvar *ethernet-jam-count* 0 "Number of ether collisions since we came up")
(defvar *ethernet-fcs-errors* 0)

(defconst chaos-ethernet-type #x408 "ethernet type code for chaos protocol") ; =2010
(defconst address-resolution-type #x608 "ethernet type for address resolution") ; 3010

;These counts record errors detected while examining the unwrapped ether packet.
; the have the same meanings as the chaos counters without the "ETHER-CHAOS".
(DEFVAR ETHER-CHAOS-PKTS-OTHER-DISCARDED 0)
(DEFVAR ETHER-CHAOS-PKTS-BAD-BIT-COUNT 0)
(DEFVAR ETHER-CHAOS-PKTS-BAD-DEST 0)

(DEFVAR ETHERNET-RECENT-HEADERS NIL
  "Array of 200 most recent packet transactions' headers.
Each row of the array contains the eight header words of the packet
and the time at which the record was made.")
(DEFVAR ETHERNET-RECENT-HEADERS-POINTER NIL
  "Next index to use in storing in ETHERNET-RECENT-HEADERS.")


; for the time being, these symbols are also in the si package associated with MINI.
(defconst 3com-mebase #x30000 "address of 3com ethernet controller")
(defconst 3com-mecsr 3com-mebase "control/status register for 3com interface")
(defconst 3com-meback (+ 2 3com-mecsr) "jam backoff counter for 3com interface")
(defconst 3com-address-rom (+ 3com-mebase #x400) "3com ethernet address ROM")
(defconst 3com-address-ram (+ 3com-mebase #x600) "3com ethernet address RAM")
(defconst 3com-transmit-buffer (+ 3com-mebase #x800) "3com transmit buffer")
(defconst 3com-buffer-a (+ 3com-mebase #x1000) "3com receive buffer A")
(defconst 3com-buffer-b (+ 3com-mebase #x1800) "3com receive buffer B")
(defconst 3com-me-buffer-size 2048. "number of bytes in a buffer")

(DEFUN TEMP-BYTE (OVER NBITS) ;this definition compatible common lisp -NO IT ISNT, change it back
  "Creates a byte pointer from its arguments.
The first argument specifies the size of byte; the second is the number of bits from the
right of the number that the byte starts."
  (DPB OVER 0609 NBITS))	;"Make a byte pointer" 

;Note: this code operates with the byte-ordering switch ON on the 3-COM board.
;  This sets "low byte first" mode, like the 8086 and unlike the 68000.
;  Setting it this way means data CAN be read from packet buffers with 32 bit transfers.
;  This is NOT the way the board was shipped by 3-COM.
;  This means the pictures in the manual are byte reversed!
;  In particular, the byte offset words in the buffer headers are byte reversed!!!

(defconst bbsw (temp-byte 7. 1))		;set if buffer B belongs to ether.
(defconst absw (temp-byte 6. 1))		;set if buffer A belongs to ether.
 (defconst a+b-bsw (temp-byte 6. 2))		; both of the above.
(defconst tbsw (temp-byte 5. 1))		;set if transmit buffer belongs to ether.
(defconst jam (temp-byte 4. 1))			;writing 1 clears jam.
 (defconst tbsw+jam (temp-byte 4 2))
(defconst amsw (temp-byte 3. 1))		;address in RAM is valid
(defconst rbba (temp-byte 2. 1))		;A/B receive buffer ordering.
   ; bit 1 not used
(defconst reset (temp-byte 0. 1))		;reset the controller.
(defconst binten (temp-byte 15. 1))		;enable interrupts on buffer B.
(defconst ainten (temp-byte 14. 1))		;enable interrupts on buffer A.
(defconst tinten (temp-byte 13. 1))		;enable interrupts on transmit buffer.
(defconst jinten (temp-byte 12. 1))		;enable interrupts on jam.
(defconst pa (temp-byte 8. 4))		;which frame addresses to accept


(defconst 3com-csr-background-bits (logior (dpb 7 pa 0)
					   (dpb 1 amsw 0)))

(defvar my-ethernet-address :unbound)


(defun write-3com-csr (new-csr)
  (if *lambda-has-ethernet*
      (%nubus-write si:sdu-quad-slot 3com-mecsr new-csr)
                ;this also writes the jam-backoff counter, which
		;I guess doesnt hurt.  Writing it in two pieces also has potential lossage.
    (ferror nil "no ethernet is present")))


(defun read-3com-csr ()
  (if *lambda-has-ethernet*
      (ldb 0020 (%nubus-read si:sdu-quad-slot 3com-mecsr))
    (ferror nil "no ethernet is present")))

(defun print-3com-csr ()
  (let ((csr (read-3com-csr)))
    (format t "~%Buf B belongs to ether: ~40t~d" (ldb bbsw csr))
    (format t "~%Buf A belongs to ether: ~40t~d" (ldb absw csr))
    (format t "~%Transmit buf belongs to ether: ~40t~d" (ldb tbsw csr))
    (format t "~%Jam: ~40t~d" (ldb jam csr))
    (format t "~%RAM valid: ~40t~d" (ldb amsw csr))
    (format t "~%A/B buffer ordering: ~40t~d" (ldb rbba csr))
    (format t "~%reset: ~40t~d" (ldb reset csr))	;probably write only
    (format t "~%Enable interrupts on B buffer: ~40t~d" (ldb binten csr))
    (format t "~%Enable interrupts on A buffer: ~40t~d" (ldb ainten csr))
    (format t "~%Enable interrupts on transmit buffer: ~40t~d" (ldb tinten csr))
    (format t "~%Enable interrupts on JAM: ~40t~d" (ldb jinten csr))
    (format t "~%pa: ~40t~d" (ldb pa csr))))

(defvar multibus-ethernet-process nil)

;this is called by chaos:initialize-ncp-system, which is early on the system initialization list
(defun lambda-ether-init ()
  (lambda-3com-reset)
  (cond (*lambda-has-ethernet*
	 (COND ((NULL ETHERNET-RECENT-HEADERS)
		(SETQ ETHERNET-RECENT-HEADERS (MAKE-ARRAY '(200 22) ':TYPE 'ART-8B
							  ':AREA PERMANENT-STORAGE-AREA))))
				;Array of 200 most recent packet transactions each row
				;containing the eight header words of the packet and the
				;time at which the record was made.
	 (SETQ ETHERNET-RECENT-HEADERS-POINTER 0)
	 (if (null multibus-ethernet-process)
	     (setq multibus-ethernet-process
		   (make-process "Multibus Ethernet Receiver"
				 ':warm-boot-action nil ':priority 25.)))
	 (send multibus-ethernet-process ':preset 'multibus-ethernet-receiver)
	 (process-reset-and-enable multibus-ethernet-process)))
  )

(defun lambda-3com-reset ()
  (if multibus-ethernet-process
      (process-disable multibus-ethernet-process))
  (cond (*lambda-has-ethernet*
	 (write-3com-csr (dpb 1 reset 0)) ;don't used background bits here
	 (setq my-ethernet-address 0)
	 (dotimes (i 6)
	   (let ((next-byte (compiler:%multibus-read-8 (+ 3com-address-rom i))))
	     (compiler:%multibus-write-8 (+ 3com-address-ram i) next-byte)
	     (setq my-ethernet-address (dpb next-byte 0010 (ash my-ethernet-address 8.)))))
	 ;set up normal csr - address RAM valid, receive MINE + Broadcast packets
	 (write-3com-csr 3com-csr-background-bits)))
  )


(defun print-3com-address-ram ()
  (if (null *lambda-has-ethernet*) (ferror nil "no ethernet present"))
  (dotimes (i 6)
    (format t "~16r " (%multibus-read-8 (+ 3com-address-ram i)))))

(defun print-3com-address-rom ()
  (if (null *lambda-has-ethernet*) (ferror nil "no ethernet present"))
  (dotimes (i 6)
    (format t "~16r " (%multibus-read-8 (+ 3com-address-rom i)))))

(defun arm-3com-receive-buffer-a ()
  (write-3com-csr (dpb 1 absw 3com-csr-background-bits)))

(defun arm-3com-receive-buffer-b ()
  (write-3com-csr (dpb 1 bbsw 3com-csr-background-bits)))

(DEFUN ARM-3COM-RECEIVE-BUFFER (BYTE-PTR)
  (PROG ()
    L   (COND ((NOT (ZEROP (LDB TBSW (READ-3COM-CSR))))

	       (cond ((not (zerop (ldb jam (read-3com-csr))))
		      (write-3com-csr (dpb 1 jam 3com-csr-background-bits))))
	       (GO L)))
        (WITHOUT-INTERRUPTS
	  (COND ((NOT (ZEROP (LDB TBSW (READ-3COM-CSR))))
	       (GO L)))
	  (write-3com-csr (dpb 1 BYTE-PTR 3com-csr-background-bits)))))

;;; LAMBDA's 3com receive buffer contains
;;; buffer-base:    meahdr (note byte reversed!!)
;;;          +2:    destination
;;;          +8:    source
;;;         +14:    type
;;;         +16:    data

(defun read-lambda-3com-buffer-header (buffer-base)
  "returns the header word of a 3com receive buffer decoded as follows:
  first value:   the number of bytes, computed from the offset field;
  second value:  T if there was a framing error, otherwise nil;
  third value:   T if address matches our own;
  fourth value:  T if frame length is out of bounds;
  fifth value:   T if it was a broadcast frame;
  sixth value:   T if the frame has a checksum error"
  (if (null *lambda-has-ethernet*) (ferror nil "no ethernet present"))
  (let* ((header (dpb (compiler:%multibus-read-8 buffer-base)	;note byte-reversed.
		      1010
		      (compiler:%multibus-read-8 (1+ buffer-base))))
	 (n-bytes (ldb 0013 header))
	 (framing-error (= 1 (ldb 1301 header)))
	 (address-match (= 1 (ldb 1401 header)))
	 (range-error (= 1 (ldb 1501 header)))
	 (broadcast (= 1 (ldb 1601 header)))
	 (fcs-error (= 1 (ldb 1701 header))))
    (values n-bytes framing-error address-match range-error broadcast fcs-error)))



(defun write-lambda-3com-frame-header (buffer-base offset source destination type)
  (if (null *lambda-has-ethernet*) (ferror nil "no ethernet present"))
  (setq offset (- offset 14.))
  (compiler:%multibus-write-8 (1+ buffer-base) (ldb 0010 offset)) ;offset reg is reversed!!!
  (compiler:%multibus-write-8  buffer-base (ldb 1010 offset))
  (compiler:%multibus-write-8 (+ buffer-base offset ) (ldb 5010 destination))
  (compiler:%multibus-write-8 (+ buffer-base offset 1) (ldb 4010 destination))
  (compiler:%multibus-write-8 (+ buffer-base offset 2) (ldb 3010 destination))
  (compiler:%multibus-write-8 (+ buffer-base offset 3) (ldb 2010 destination))
  (compiler:%multibus-write-8 (+ buffer-base offset 4) (ldb 1010 destination))
  (compiler:%multibus-write-8 (+ buffer-base offset 5) (ldb 0010 destination))

  (compiler:%multibus-write-8 (+ buffer-base offset 6) (ldb 5010 source))
  (compiler:%multibus-write-8 (+ buffer-base offset 7) (ldb 4010 source))
  (compiler:%multibus-write-8 (+ buffer-base offset 10) (ldb 3010 source))
  (compiler:%multibus-write-8 (+ buffer-base offset 11) (ldb 2010 source))
  (compiler:%multibus-write-8 (+ buffer-base offset 12) (ldb 1010 source))
  (compiler:%multibus-write-8 (+ buffer-base offset 13) (ldb 0010 source))
  
  (compiler:%multibus-write-8 (+ buffer-base offset 14) (ldb 0010 type))
  (compiler:%multibus-write-8 (+ buffer-base offset 15) (ldb 1010 type)))


(defun read-lambda-3com-frame-header (buffer-base)
  "returns the type of the packet in the hardware buffer"
  (if (null *lambda-has-ethernet*) (ferror nil "no ethernet present"))
  (dpb (%multibus-read-8 (+ buffer-base 17))
       1010
       (%multibus-read-8 (+ buffer-base 16))))


(defun print-rcv-buffer (buf)
  (let ((buf-base (selectq buf
		    ((a 0) 3com-buffer-a)
		    ((b 1) 3com-buffer-b))))
    (dotimes (i 30)
      (format t "~16r " (%multibus-read-8 (+ buf-base i))))))

(defun print-xmit-buffer ()
  (let ((offset (dpb (%multibus-read-8  3com-transmit-buffer)
		     1010
		     (%multibus-read-8 (1+ 3com-transmit-buffer)))))
    (dotimes (i 30)
      (format t "~16r " (%multibus-read-8 (+ 3com-transmit-buffer offset i))))))

;**this seems to have a timing error!  It can get here with interrupts enabled.
; Could happen in more than one process at once!!
(defun send-int-pkt-via-multibus-ethernet (int-pkt e-source e-destination e-type
					   &optional (n-16-bit-words
						       (ceiling (+ (chaos:pkt-nbytes int-pkt)
								   16.)
								2)))
  (cond (*lambda-has-ethernet*
	 (let* ((physical-size (max (* n-16-bit-words 2) 60.))	;don't send runts
		(offset (- 3com-me-buffer-size physical-size))
		(beginning-address (+ 3com-transmit-buffer offset)))
	   (prog (csr start-time)
		 (setq start-time (compiler:%fixnum-microsecond-time))
		 l  (setq csr (read-3com-csr))
		 (cond ((not (zerop (ldb jam csr)))

  ;			(write-3com-csr (dpb 1 jam 3com-csr-background-bits))	;reset jam
			(write-3com-csr (dpb 1 reset 0))
			(write-3com-csr 3com-csr-background-bits)
			(incf *ethernet-jam-count*)
			(go l))
		       ((not (zerop (ldb tbsw csr)))
			(cond ((> (time-difference (compiler:%fixnum-microsecond-time)
						   start-time)
				  100000.)
			       (setq *ethernet-transmit-time-outs*
				     (1+ *ethernet-transmit-time-outs*))
			       (return nil))	;give up.
			      (t (go l)))))
		 (incf *ethernet-packets-transmitted*)
		 (WITHOUT-INTERRUPTS
		   (COND ((not (zerop (ldb tbsw csr)))

			  (incf *ethernet-packets-not-transmitted-xmit-buffer-not-available*))
			 (T
			  (do ((adr beginning-address (+ adr 2))
			       (from-index 0 (1+ from-index))
			       (n n-16-bit-words (1- n)))
			      ((zerop n))
			    (let ((data (aref int-pkt from-index)))
			      (compiler:%multibus-write-8 adr (ldb 0010 data))
			      (compiler:%multibus-write-8 (1+ adr) (ldb 1010 data))))
			  (write-lambda-3com-frame-header 3com-transmit-buffer
							  offset
							  e-source
							  e-destination
							  e-type)
			  (write-3com-csr (dpb 1 tbsw 3com-csr-background-bits)))))
		;  (do ()
		;      ((zerop (ldb tbsw (read-3com-csr)))))
		 )))))

(defun multibus-3com-process-wait-function ()

  (and *lambda-has-ethernet* chaos:enable
       (or (not (boundp 'si:*ethernet-hardware-controller*))
	   (eq si:*ethernet-hardware-controller* si:*my-op*))
       (not (= 3 (ldb a+b-bsw (read-3com-csr))))))	;either buffer available

(defun multibus-ethernet-receiver ()
  (cond (*lambda-has-ethernet*
	 (arm-3com-receive-buffer ABSW)
	 (arm-3com-receive-buffer BBSW)
	 (error-restart-loop ((error sys:abort) "Wait for another ethernet packet")
	   (process-wait "Await ether pkt or enable" 'multibus-3com-process-wait-function)
	   (let ((csr (read-3com-csr)))
	     (cond ((zerop (ldb absw csr))
		    (multibus-ethernet-receive-buffer 3com-buffer-a)
		    (arm-3com-receive-buffer ABSW))
		   ((zerop (ldb bbsw csr))
		    (multibus-ethernet-receive-buffer 3com-buffer-b)
		    (arm-3com-receive-buffer BBSW))))))))


(defvar *ethernet-random-packet-alist* '((6 handle-xns-packet)))

(defun multibus-ethernet-receive-buffer (buffer-base)
  (if (null *lambda-has-ethernet*) (ferror nil "no ethernet present"))
  (incf *ethernet-packets-received*)
  (ethernet-record-pkt-header buffer-base)
  (cond ((not (zerop (logand 250 (compiler:%multibus-read-8 buffer-base)))) ;note byte swap
	 (incf *ethernet-fcs-errors*))
	(t
	 (let ((type (read-lambda-3com-frame-header buffer-base)))
	   (select type
	     (chaos-ethernet-type
	      (setq *ethernet-chaos-pkts-received*
		    (1+ *ethernet-chaos-pkts-received*))
	      (let ((int-pkt (chaos:allocate-int-pkt)))	;OK to go blocked if necessary
		(do ((adr (+ buffer-base 16.) (+ adr 2))
		     (wd-count 0 (1+ wd-count)))
		    ((>= wd-count chaos:max-words-per-pkt))
		  (aset (dpb (compiler:%multibus-read-8 (+ adr 1))
			     1010
			     (compiler:%multibus-read-8 adr))
			int-pkt
			wd-count))
		(let ((n-16-bit-words (+ (ceiling (+ (chaos:pkt-nbytes int-pkt) 16.) 2)
					 3))) ; 3 for the chaos hardware source, dest, and crc
		  (cond ((<= n-16-bit-words (+ 3 chaos:max-words-per-pkt))
			 (setf (chaos:int-pkt-word-count int-pkt) (1+ n-16-bit-words))
			 (setf (chaos:int-pkt-csr-1 int-pkt) 0)	; say no CRC-1 error
			 (setf (chaos:int-pkt-csr-2 int-pkt) 0)	; say no CRC-2 error
			 (setf (chaos:int-pkt-bit-count int-pkt)
			       (* (- n-16-bit-words 3) 20))	; fill in bit count
			 (aset chaos:my-address		; set the hardware destination
			       int-pkt
			       (- (chaos:int-pkt-word-count int-pkt) 3))
			 (check-and-receive-chaos-int-pkt int-pkt))
			(t

			 (incf chaos:pkts-other-discarded)
			 (incf *ethernet-chaos-pkts-too-big-to-unwrap*)
			 (chaos:free-int-pkt int-pkt))))))
	     (address-resolution-type
	      (setq *ethernet-address-resolution-pkts-received*
		    (1+ *ethernet-address-resolution-pkts-received*))
	      (let ((pkt (chaos:get-pkt)))	;OK to go blocked
		;;copy received data into pkt
		(do ((adr (+ buffer-base 16.) (+ adr 2))
		     (wd-count 0 (1+ wd-count)))
		    ((>= wd-count chaos:max-words-per-pkt))
		  (aset (dpb (compiler:%multibus-read-8 (+ adr 1))
			     1010
			     (compiler:%multibus-read-8 adr))
			pkt
			wd-count))
		(receive-addr-pkt pkt)		;record address; maybe send reply
		(chaos:return-pkt pkt)))
	     (otherwise

	      (if (assoc type *ethernet-random-packet-alist*)
		  (funcall (cadr (assoc type *ethernet-random-packet-alist*)) buffer-base)
		(setq *ethernet-unknown-protocol-pkts-received*
		      (1+ *ethernet-unknown-protocol-pkts-received*)
		      *ethernet-last-unknown-protocol-type* type))))))))

(defun handle-xns-packet (buffer-base)
  (let ((pkt (chaos:get-pkt)) e-dest)	;OK to go blocked
    ;;copy received data into pkt
    (setq e-dest 0)
    (setf (ldb 5010 e-dest) (compiler:%multibus-read-8 (+ buffer-base 10)))
    (setf (ldb 4010 e-dest) (compiler:%multibus-read-8 (+ buffer-base 11)))
    (setf (ldb 3010 e-dest) (compiler:%multibus-read-8 (+ buffer-base 12)))
    (setf (ldb 2010 e-dest) (compiler:%multibus-read-8 (+ buffer-base 13)))
    (setf (ldb 1010 e-dest) (compiler:%multibus-read-8 (+ buffer-base 14)))
    (setf (ldb 0010 e-dest) (compiler:%multibus-read-8 (+ buffer-base 15)))
    (do ((adr (+ buffer-base 20) (+ adr 2))
	 (wd-count 0 (1+ wd-count)))
	((>= wd-count chaos:max-words-per-pkt))
      (aset (dpb (compiler:%multibus-read-8 (+ adr 1))
		 1010
		 (compiler:%multibus-read-8 adr))
	    pkt
	    wd-count))
    (setf (aref pkt 5.) (aref pkt 11.))
    (setf (aref pkt 6.) (aref pkt 12.))	 
    (setf (aref pkt 7.) (aref pkt 13.))
    (if (= (aref pkt 15.) 400)
	(progn (setf (aref pkt 15.) 1000)
	       (setq *ethernet-echo-server-requests* (1+ *ethernet-echo-server-requests*))
	       (send-int-pkt-via-multibus-ethernet pkt my-ethernet-address e-dest 6
						   chaos:max-words-per-pkt)))
    (chaos:return-pkt pkt)))

(defun check-and-receive-chaos-int-pkt (int-pkt)
  (cond ((check-over-chaos-int-pkt int-pkt)
	 (without-interrupts
	   (let ((chaos:reserved-int-pkt nil))

	     (incf chaos:PKTS-RECEIVED)
	     (chaos:receive-int-pkt int-pkt)
	     (cond (chaos:reserved-int-pkt
		    (FERROR NIL "Int PKT about to be lost in ethernet stuff!"))))))))

;This checking is normally done in RECEIVE-PROCESS-NEXT-INT-PKT, which unfortunately
; is not accessible for current purposes.
(DEFUN CHECK-OVER-CHAOS-INT-PKT (INT-PKT)
  (PROG (BITS DEST)
      (SETF (CHAOS:INT-PKT-THREAD INT-PKT) NIL)
      (COND ((< (CHAOS:INT-PKT-WORD-COUNT INT-PKT)
		(+ CHAOS:FIRST-DATA-WORD-IN-PKT 3))
             ;; Less than the minimum size that can exist in the current protocol?
	     (SETQ ETHER-CHAOS-PKTS-OTHER-DISCARDED
		   (1+ ETHER-CHAOS-PKTS-OTHER-DISCARDED))
             (CHAOS:FREE-INT-PKT INT-PKT)
             (RETURN NIL)))
      (SETQ DEST (CHAOS:INT-PKT-HARDWARE-DEST INT-PKT)
            BITS (CHAOS:INT-PKT-BIT-COUNT INT-PKT))
      (COND 
 	;the following is a useless test for now.. also it seems to have a bug.
  ;	    ((OR (< BITS 48.)
  ;		 (BIT-TEST 17 BITS)
  ;		 (AND (ZEROP (LOGAND 377 (AREF INT-PKT 0)))	;Header version 0
  ;		      ( (TRUNCATE BITS 20) (+ (CHAOS:PKT-NWORDS INT-PKT) 3))))
  ;             (SETQ ETHER-CHAOS-PKTS-BAD-BIT-COUNT (1+ ETHER-CHAOS-PKTS-BAD-BIT-COUNT))
  ;             (CHAOS:FREE-INT-PKT INT-PKT))
            ((AND ( DEST 0) ( DEST CHAOS:MY-ADDRESS))
             (SETQ ETHER-CHAOS-PKTS-BAD-DEST (1+ ETHER-CHAOS-PKTS-BAD-DEST))
             (CHAOS:FREE-INT-PKT INT-PKT)
	     (RETURN NIL))
            (T (RETURN INT-PKT)))
      ))
  
(defun reset-stats ()
  (setq *ethernet-packets-received* 0
	*ethernet-packets-transmitted* 0

	*ethernet-packets-not-transmitted-xmit-buffer-not-available* 0
	*ethernet-chaos-pkts-transmitted* 0
	*ethernet-chaos-pkts-not-transmitted-lacking-ethernet-address* 0
	*ethernet-chaos-pkts-received* 0
	*ethernet-chaos-pkts-too-big-to-unwrap* 0
	*ethernet-unknown-protocol-pkts-received* 0
	*ethernet-last-unknown-protocol-type* nil
	*ethernet-transmit-time-outs* 0

	ether-chaos-pkts-other-discarded 0
	ether-chaos-pkts-bad-bit-count 0
	ether-chaos-pkts-bad-dest 0
	*ethernet-address-resolution-pkts-received* 0

	*ethernet-echo-server-requests* 0
	*ethernet-jam-count* 0
	*ethernet-fcs-errors* 0
))

(defun print-stats ()
  (format t "~%ethernet-packets-received: ~40t~d" *ethernet-packets-received*)
  (format t "~%ethernet-packets-transmitted: ~40t~d" *ethernet-packets-transmitted*)

  (format t "~%ethernet-packets-not-transmitted-xmit-buffer-not-available: ~40t~d"
	  *ethernet-packets-not-transmitted-xmit-buffer-not-available*)
  (format t "~%ethernet-chaos-pkts-transmitted:~40t~d" *ethernet-chaos-pkts-transmitted*)
  (format t "~%ethernet-chaos-pkts-not-transmitted-lacking-ethernet-address:~40t~d"
	  *ethernet-chaos-pkts-not-transmitted-lacking-ethernet-address*)
  (format t "~%ethernet-chaos-pkts-received: ~40t~d" *ethernet-chaos-pkts-received*)
  (format t "~%ethernet-chaos-pkts-too-big-to-unwrap: ~40t~d"
	  *ethernet-chaos-pkts-too-big-to-unwrap*)
  (format t "~%ethernet-unknown-protocol-pkts-received: ~40t~d"
	  *ethernet-unknown-protocol-pkts-received*)
  (format t "~%ethernet-last-unknown-protocol-type: ~40t~s"
	  *ethernet-last-unknown-protocol-type*)
  (format t "~%ethernet-transmit-time-outs: ~40t~d" *ethernet-transmit-time-outs*)

  (FORMAT T "~%ether-chaos-pkts-other-discarded: ~40t~d" ETHER-CHAOS-PKTS-OTHER-DISCARDED)
  (FORMAT T "~%ether-chaos-pkts-bad-bit-count: ~40t~d" ETHER-CHAOS-PKTS-BAD-BIT-COUNT)
  (FORMAT T "~%ether-chaos-pkts-bad-dest: ~40t~d" ETHER-CHAOS-PKTS-BAD-DEST)
  (format t "~%*ethernet-address-resolution-pkts-received*: ~40t~d"
	  *ethernet-address-resolution-pkts-received*)

  (format t "~%*ethernet-echo-server-requests*: ~40t~d"
	  *ethernet-echo-server-requests*)
  (format t "~%jam count: ~30T~d" *ethernet-jam-count*)
  (format t "~%ethernet-fcs-errors: ~40t~d" *ethernet-fcs-errors*)
)

(defun remove-ethernet-board ()
  (chaos:reset)
  (setq *lambda-has-ethernet* nil)
  (format t "~&Now do a disk-save, and the next cold boot will not need an ethernet board"))

(defun install-ethernet-board ()
  (chaos:reset)
  (setq *lambda-has-ethernet* t)
  (lambda-ether-init)
  (chaos:enable)
  (format t "~&The network is enabled now.  Do a disk-save to make the change permanent"))

(DEFUN ETHERNET-RECORD-PKT-HEADER (BUFFER-BASE)
  ;THIS SAVES BUFFER HEADER (WITH ERROR CODE), DESTINATION, SOURCE, AND PACKET TYPE.
  ;NOTE IT IS NOT BYTE REVERSED, SO THAT HAS TO BE DONE ON READOUT.
  (COND ((AND ETHERNET-RECENT-HEADERS ETHERNET-RECENT-HEADERS-POINTER)
	  ;FIRST 20 BYTES HAS DESTINATION (5), SOURCE (5), AND PACKET TYPE (2).
	  ;NOTE NO BYTE REVERSING IS DONE.
	 (DO I 0 (1+ I) (= I 20)
	     (AS-2 (COMPILER:%MULTIBUS-READ-8 (+ BUFFER-BASE I))  
		   ETHERNET-RECENT-HEADERS
		   ETHERNET-RECENT-HEADERS-POINTER
		   I))
	 (LET ((TIME (TIME)))
	   (AS-2 (LDB 0010 TIME) ETHERNET-RECENT-HEADERS ETHERNET-RECENT-HEADERS-POINTER 20)
	   (AS-2 (LDB 1010 TIME) ETHERNET-RECENT-HEADERS ETHERNET-RECENT-HEADERS-POINTER 21))
	 (SETQ ETHERNET-RECENT-HEADERS-POINTER (\ (1+ ETHERNET-RECENT-HEADERS-POINTER) 200)))))


(DEFUN WIPE-RECENT-HEADERS (&OPTIONAL (NBR 200))
  (DO ((I (\ (+ 177 ETHERNET-RECENT-HEADERS-POINTER) 200) (COND ((ZEROP I) 177) (T (1- I))))
	(COUNT NBR (1- COUNT)))
       ((ZEROP COUNT))
    (DOTIMES (C 22)
      (AS-2 0 ETHERNET-RECENT-HEADERS I C))))      
    
(DEFUN ETHERNET-PRINT-RECENT-HEADERS ( &OPTIONAL (NBR 200))
   (DO ((I (\ (+ 177 ETHERNET-RECENT-HEADERS-POINTER) 200) (COND ((ZEROP I) 177) (T (1- I))))
	(COUNT NBR (1- COUNT)))
       ((ZEROP COUNT))
     (let* ((header (dpb (erp-ref i 0) 1010 (erp-ref i 1)))
	    (n-bytes (ldb 0013 header))
	    (framing-error (= 1 (ldb 1301 header)))
	    (address-match (= 1 (ldb 1401 header)))
	    (range-error (= 1 (ldb 1501 header)))
	    (broadcast (= 1 (ldb 1601 header)))
	    (fcs-error (= 1 (ldb 1701 header)))
	    (TO (DPB (ERP-REF I 2) 5010
		  (DPB (ERP-REF I 3) 4010
		       (DPB (ERP-REF I 4) 3010
			    (DPB (ERP-REF I 5) 2010 (DPB (ERP-REF I 6) 1010 (ERP-REF I 7)))))))
	    (FROM
	      (DPB (ERP-REF I 10) 5010
		  (DPB (ERP-REF I 11) 4010
		       (DPB (ERP-REF I 12) 3010
			    (DPB (ERP-REF I 13) 2010 (DPB (ERP-REF I 14) 1010 (ERP-REF I 15))))))))
       (FORMAT T "~%fcs-errror ~s, broadcast ~s, range-error ~s, adr match ~s, frame-error ~s, nbytes ~s, "
	     fcs-error broadcast range-error address-match framing-error n-bytes)
       (format t "~%     TO: ~S(~16r), FROM: ~S(~16r), TYPE ~S"
	       to to
	       from from
	     (DPB (ERP-REF I 17) 1010 (ERP-REF I 16))))))

(DEFUN ERP-REF (I N)
  (AREF ETHERNET-RECENT-HEADERS I N))
