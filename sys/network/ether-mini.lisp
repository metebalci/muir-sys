;;; -*- Mode: Lisp; Package: System-Internals; BASE: 8; Cold-load: T -*-

;;; Miniature Chaosnet program.  Only good for reading ascii and binary files.
;;; The following magic number is in this program:  1200
;;; It also knows the format of a packet and the Chaosnet opcodes non-symbolically

(DECLARE (SPECIAL MINI-PKT MINI-PKT-STRING MINI-FILE-ID MINI-OPEN-P MINI-CH-IDX MINI-UNRCHF
		  MINI-LOCAL-INDEX MINI-LOCAL-HOST MINI-REMOTE-INDEX MINI-REMOTE-HOST
		  MINI-IN-PKT-NUMBER MINI-OUT-PKT-NUMBER MINI-EOF-SEEN
		  MINI-DESTINATION-ADDRESS MINI-ROUTING-ADDRESS
		  MINI-PLIST-RECEIVER-POINTER))

;This is the filename (a string) on which MINI-FASLOAD was called.
(DEFVAR MINI-FASLOAD-FILENAME)

(SETQ MINI-DESTINATION-ADDRESS 3420)	;LAM2
(SETQ MINI-ROUTING-ADDRESS 3420) ; bridge to get there
(defvar mini-his-ethernet-address nil) ;gets ether address of bridge
(defvar mini-my-ethernet-address :unbound)

;;; Contact name<space>user<space>password
(DEFVAR MINI-CONTACT-NAME "MINI LISPM ")

;;; Initialization, usually only called once.
(DEFUN MINI-INIT ()
  ;; Init lists microcode looks at
;  (STORE (SYSTEM-COMMUNICATION-AREA %SYS-COM-CHAOS-FREE-LIST) NIL)
;  (STORE (SYSTEM-COMMUNICATION-AREA %SYS-COM-CHAOS-RECEIVE-LIST) NIL)
;  (STORE (SYSTEM-COMMUNICATION-AREA %SYS-COM-CHAOS-TRANSMIT-LIST) NIL)
  ;; Fake up a packet buffer for the microcode, locations 1200-x through 1377
  ;; I.e. in the unused portions of SCRATCH-PAD-INIT-AREA
  (%P-STORE-TAG-AND-POINTER 1177 DTP-ARRAY-HEADER
			    (DPB 1 %%ARRAY-NUMBER-DIMENSIONS
				 (DPB 400 %%ARRAY-INDEX-LENGTH-IF-SHORT
				      (DPB 1 %%ARRAY-LEADER-BIT
					   ART-16B))))
  (%P-STORE-TAG-AND-POINTER 1176 DTP-FIX (LENGTH CHAOS-BUFFER-LEADER-QS))
  (%P-STORE-TAG-AND-POINTER (- 1176 1 (LENGTH CHAOS-BUFFER-LEADER-QS))
			    DTP-HEADER
			    (DPB %HEADER-TYPE-ARRAY-LEADER %%HEADER-TYPE-FIELD
				 (+ 2 (LENGTH CHAOS-BUFFER-LEADER-QS))))
  (SETQ MINI-PKT (%MAKE-POINTER DTP-ARRAY-POINTER 1177))
  (SETQ MINI-PKT-STRING (MAKE-ARRAY 760
				    ':TYPE 'ART-STRING
				    ':DISPLACED-TO 1204)) ;Just the data part of the packet
  (OR (BOUNDP 'MINI-LOCAL-INDEX)
      (SETQ MINI-LOCAL-INDEX 0))
  (SETQ MINI-OPEN-P NIL)
  (3COM-RESET))

;;; Get a connection to a file server
(DEFUN MINI-OPEN-CONNECTION (HOST CONTACT-NAME)
  (OR (BOUNDP 'MINI-PKT) (MINI-INIT))
  (SETQ MINI-LOCAL-HOST 3410		;LAM1
	MINI-REMOTE-HOST HOST
	MINI-OUT-PKT-NUMBER 1)
;  (AND (= (LDB 1010 MINI-LOCAL-HOST) (LDB 1010 MINI-REMOTE-HOST))
;       (SETQ MINI-ROUTING-ADDRESS MINI-REMOTE-HOST))
  (SETQ MINI-LOCAL-INDEX (1+ MINI-LOCAL-INDEX))
  (AND (= MINI-LOCAL-INDEX 200000) (SETQ MINI-LOCAL-INDEX 1))
  (SETQ MINI-REMOTE-INDEX 0
	MINI-IN-PKT-NUMBER 0)
  (arm-3com-receive-buffer-a)
  (arm-3com-receive-buffer-b)
  (get-his-ethernet-address)
  (DO ((RETRY-COUNT 10. (1- RETRY-COUNT)))
      ((ZEROP RETRY-COUNT) (MINI-BARF "RFC fail"))
    ;; Store contact name into packet
    (COPY-ARRAY-CONTENTS CONTACT-NAME MINI-PKT-STRING)
    (MINI-SEND-PKT 1 (ARRAY-LENGTH CONTACT-NAME))  ;Send RFC
    (COND ((EQ (MINI-NEXT-PKT NIL) 2)	;Look for a response of OPN
	   (SETQ MINI-REMOTE-INDEX (AREF MINI-PKT 5)
		 MINI-IN-PKT-NUMBER (AREF MINI-PKT 6))
	   (SETQ MINI-OUT-PKT-NUMBER (1+ MINI-OUT-PKT-NUMBER))
	   (MINI-SEND-STS)
	   (SETQ MINI-OPEN-P T)
	   (RETURN T)))))	;and exit.  Otherwise, try RFC again.

;;; Send a STS
(DEFUN MINI-SEND-STS ()
  (ASET MINI-IN-PKT-NUMBER MINI-PKT 10) ;Receipt
  (ASET 1 MINI-PKT 11) ;Window size
  (MINI-SEND-PKT 7 4)) ;STS

;;; Open a file for read
(DEFUN MINI-OPEN-FILE (FILENAME BINARY-P)
  (SETQ MINI-CH-IDX 1000 MINI-UNRCHF NIL MINI-EOF-SEEN NIL)
  (OR MINI-OPEN-P
      (MINI-OPEN-CONNECTION MINI-DESTINATION-ADDRESS MINI-CONTACT-NAME))
  (DO ((OP)) ;Retransmission loop
      (NIL)
    ;; Send opcode 200 (ascii open) or 201 (binary open) with file name
    (COPY-ARRAY-CONTENTS FILENAME MINI-PKT-STRING)
    (MINI-SEND-PKT (IF BINARY-P 201 200) (ARRAY-ACTIVE-LENGTH FILENAME))
    ;; Get back opcode 202 (win) or 203 (lose) or OPN if old STS lost
    (SETQ OP (MINI-NEXT-PKT NIL))
    (COND ((NULL OP))		;no response, retransmit
	  ((= OP 2)		;OPN
	   (MINI-SEND-STS))	;send STS and then retransmit
	  ((OR (= OP 202) (= OP 203)) ;Win or Lose
	   (SETQ MINI-IN-PKT-NUMBER (LOGAND 177777 (1+ MINI-IN-PKT-NUMBER))
		 MINI-OUT-PKT-NUMBER (LOGAND 177777 (1+ MINI-OUT-PKT-NUMBER)))
	   (LET* ((LENGTH (LOGAND 7777 (AREF MINI-PKT 1)))
		  (CR (STRING-SEARCH-CHAR #\CR MINI-PKT-STRING 0 LENGTH)))
	     ;; Before pathnames and time parsing is loaded, things are stored as strings.
	     (SETQ MINI-FILE-ID (CONS (SUBSTRING MINI-PKT-STRING 0 CR)
				      ;;Discard zero at front of month, so the format
				      ;;matches that produced by PRINT-UNIVERSAL-TIME,
				      ;;and by QFILE before TIMPAR is loaded.
				      (STRING-LEFT-TRIM
					#/0 (SUBSTRING MINI-PKT-STRING (1+ CR) LENGTH)))))
	   (MINI-SEND-STS)	;Acknowledge packet just received
	   (COND ((= OP 202)
		  (RETURN T))
		 (T ;Lose
		  (MINI-BARF MINI-FILE-ID FILENAME))))))
  (IF BINARY-P #'MINI-BINARY-STREAM #'MINI-ASCII-STREAM))

;; Doesn't use symbols for packet fields since not loaded yet
;; This sends a packet and doesn't return until it has cleared microcode.
;; You fill in the data part before calling, this fills in the header.
(DEFUN MINI-SEND-PKT (OPCODE N-BYTES)
  (ASET (LSH OPCODE 8) MINI-PKT 0)
  (ASET N-BYTES MINI-PKT 1)
  (ASET MINI-REMOTE-HOST MINI-PKT 2)
  (ASET MINI-REMOTE-INDEX MINI-PKT 3)
  (ASET MINI-LOCAL-HOST MINI-PKT 4)
  (ASET MINI-LOCAL-INDEX MINI-PKT 5)
  (ASET MINI-OUT-PKT-NUMBER MINI-PKT 6) ;PKT#
  (ASET MINI-IN-PKT-NUMBER MINI-PKT 7)  ;ACK#
  (LET ((WC (+ 8 (CEILING N-BYTES 2) 1))) ;Word count including header and hardware dest word
    (STORE-ARRAY-LEADER WC MINI-PKT %CHAOS-LEADER-WORD-COUNT)
    (ASET MINI-ROUTING-ADDRESS MINI-PKT (1- WC))) ;Store hardware destination

  (transmit-ethernet-16b-array
    mini-my-ethernet-address
    mini-his-ethernet-address
    MINI-PKT
    (+ 8 (ceiling n-bytes 2))
    #x408)
  
;  (STORE-ARRAY-LEADER NIL MINI-PKT %CHAOS-LEADER-THREAD)
;  (STORE (SYSTEM-COMMUNICATION-AREA %SYS-COM-CHAOS-TRANSMIT-LIST) MINI-PKT)
;  (%CHAOS-WAKEUP)
;  (DO ()	;Await completion of transmission
;      ((NULL (SYSTEM-COMMUNICATION-AREA %SYS-COM-CHAOS-TRANSMIT-LIST))))
  ;; Disallow use of the packet by the receive side, flush any received packet that snuck in
;  (STORE (SYSTEM-COMMUNICATION-AREA %SYS-COM-CHAOS-FREE-LIST) NIL)
;  (STORE (SYSTEM-COMMUNICATION-AREA %SYS-COM-CHAOS-RECEIVE-LIST) NIL)
  (COPY-ARRAY-CONTENTS "" MINI-PKT))		;Fill with zero

;; Return opcode of next packet other than those that are no good.
;; If the arg is NIL, can return NIL if no packet arrives after a while.
;; If T, waits forever.  Return value is the opcode of the packet in MINI-PKT.
(DEFUN MINI-NEXT-PKT (MUST-RETURN-A-PACKET &AUX OP)
  (DO ((TIMEOUT 20. (1- TIMEOUT)))	;A couple seconds
      ((AND (ZEROP TIMEOUT) (NOT MUST-RETURN-A-PACKET)) NIL)
    ;; Enable microcode to receive a packet
;    (STORE (SYSTEM-COMMUNICATION-AREA %SYS-COM-CHAOS-FREE-LIST) NIL)
;    (STORE (SYSTEM-COMMUNICATION-AREA %SYS-COM-CHAOS-RECEIVE-LIST) NIL)
;    (STORE-ARRAY-LEADER NIL MINI-PKT %CHAOS-LEADER-THREAD)
;    (COPY-ARRAY-CONTENTS "" MINI-PKT)		;Fill with zero
;    (STORE (SYSTEM-COMMUNICATION-AREA %SYS-COM-CHAOS-FREE-LIST) MINI-PKT)
;    (%CHAOS-WAKEUP)
;    (DO ((N 2000. (1- N)))	;Give it time
;	((OR (ZEROP N) (SYSTEM-COMMUNICATION-AREA %SYS-COM-CHAOS-RECEIVE-LIST))))
    (receive-ethernet-16b-array mini-pkt)
    (COND (t ;(SYSTEM-COMMUNICATION-AREA %SYS-COM-CHAOS-RECEIVE-LIST)
	   (SETQ OP (LSH (AREF MINI-PKT 0) -8))
	   (COND ((AND
		       (= (AREF MINI-PKT 2) MINI-LOCAL-HOST)
		       (= (AREF MINI-PKT 3) MINI-LOCAL-INDEX)
		       (OR (AND (MEMQ OP '(14 202 203 200 300))  ;EOF, win, lose, data
				(= (AREF MINI-PKT 6) (LOGAND 177777 (1+ MINI-IN-PKT-NUMBER))))
			   (MEMQ OP '(2 3 11))))  ;OPN, CLS, LOS
		  ;; This packet not to be ignored, return to caller
		  (COND ((MEMQ OP '(3 11))  ;CLS, LOS
			 (LET ((MSG (MAKE-ARRAY (LOGAND 7777 (AREF MINI-PKT 1))
						':TYPE 'ART-STRING)))
			   (COPY-ARRAY-CONTENTS MINI-PKT-STRING MSG)
			   (MINI-BARF "Connection broken" MSG))))
		  (RETURN OP)))
	   ;; This packet to be ignored, get another
	   (AND MINI-OPEN-P		;Could be getting a retransmission of
		(MINI-SEND-STS))	; an old pkt due to lost STS
	   ))))

;Stream which does only 16-bit TYI
(DEFUN MINI-BINARY-STREAM (OP &OPTIONAL ARG1)
  (SELECTQ OP
    (:WHICH-OPERATIONS '(:TYI))
    (:TYI (COND (MINI-UNRCHF
		 (PROG1 MINI-UNRCHF (SETQ MINI-UNRCHF NIL)))
		((< MINI-CH-IDX (FLOOR (LOGAND 7777 (AREF MINI-PKT 1)) 2))
		 (PROG1 (AREF MINI-PKT (+ 10 MINI-CH-IDX))
			(SETQ MINI-CH-IDX (1+ MINI-CH-IDX))))
		(T ;Get another packet
		 (MINI-SEND-STS)  ;Acknowledge packet just processed
		 (SETQ OP (MINI-NEXT-PKT T))
		 (SETQ MINI-IN-PKT-NUMBER (LOGAND 177777 (1+ MINI-IN-PKT-NUMBER)))
		 (COND ((= OP 14) ;EOF
			(MINI-SEND-STS) ;Acknowledge the EOF
			(SETQ MINI-EOF-SEEN T)
			NIL)		;and tell caller
		       ((= OP 300) ;Data
			(SETQ MINI-CH-IDX 0)
			(MINI-BINARY-STREAM ':TYI))
		       (T (MINI-BARF "Bad opcode received" OP))))))
    (:UNTYI (SETQ MINI-UNRCHF ARG1))
    (:PATHNAME MINI-FASLOAD-FILENAME)
    (:GENERIC-PATHNAME 'MINI-PLIST-RECEIVER)
    (:INFO MINI-FILE-ID)
    (:CLOSE (DO () (MINI-EOF-SEEN) (MINI-BINARY-STREAM ':TYI)))
    (OTHERWISE (MINI-BARF "Unknown stream operation" OP))))

(DEFUN MINI-ASCII-STREAM (OP &OPTIONAL ARG1)
  (SELECTQ OP
    (:WHICH-OPERATIONS '(:TYI :UNTYI))
    (:TYI (COND (MINI-UNRCHF
		 (PROG1 MINI-UNRCHF (SETQ MINI-UNRCHF NIL)))
		((< MINI-CH-IDX (LOGAND 7777 (AREF MINI-PKT 1)))
		 (PROG1 (AREF MINI-PKT-STRING MINI-CH-IDX)
			(SETQ MINI-CH-IDX (1+ MINI-CH-IDX))))
		(T ;Get another packet
		 (MINI-SEND-STS)  ;Acknowledge packet just processed
		 (SETQ OP (MINI-NEXT-PKT T))
		 (SETQ MINI-IN-PKT-NUMBER (LOGAND 177777 (1+ MINI-IN-PKT-NUMBER)))
		 (COND ((= OP 14) ;EOF
			(MINI-SEND-STS) ;Acknowledge the EOF
			(SETQ MINI-EOF-SEEN T)
			(AND ARG1 (ERROR ARG1))
			NIL)		;and tell caller
		       ((= OP 200) ;Data
			(SETQ MINI-CH-IDX 0)
			(MINI-ASCII-STREAM ':TYI))
		       (T (MINI-BARF "Bad opcode received" OP))))))
    (:UNTYI (SETQ MINI-UNRCHF ARG1))
    (:PATHNAME MINI-FASLOAD-FILENAME)
    (:GENERIC-PATHNAME 'MINI-PLIST-RECEIVER)
    (:INFO MINI-FILE-ID)
    (:CLOSE (DO () (MINI-EOF-SEEN) (MINI-ASCII-STREAM ':TYI)))
    (OTHERWISE (MINI-BARF "Unknown stream operation" OP))))

(DEFUN MINI-BARF (&REST ARGS)
  (SETQ MINI-OPEN-P NIL) ;Force re-open of connection
  ;; If inside the cold load, this will be FERROR-COLD-LOAD, else make debugging easier
  (LEXPR-FUNCALL #'FERROR 'MINI-BARF ARGS))

;;; Higher-level stuff

;;; Load a file alist as setup by the cold load generator
(DEFUN MINI-LOAD-FILE-ALIST (ALIST)
  (LOOP FOR (FILE PACK QFASLP) IN ALIST
	DO (PRINT FILE)
	DO (FUNCALL (IF QFASLP #'MINI-FASLOAD #'MINI-READFILE) FILE PACK)))

(DECLARE (SPECIAL *COLD-LOADED-FILE-PROPERTY-LISTS*))

(DEFUN MINI-FASLOAD (MINI-FASLOAD-FILENAME PKG
		     &AUX FASL-STREAM TEM)
  
  ;; Set it up so that file properties get remembered for when there are pathnames
  (OR (SETQ TEM (ASSOC MINI-FASLOAD-FILENAME *COLD-LOADED-FILE-PROPERTY-LISTS*))
      (PUSH (SETQ TEM (NCONS MINI-FASLOAD-FILENAME)) *COLD-LOADED-FILE-PROPERTY-LISTS*))
  (SETQ MINI-PLIST-RECEIVER-POINTER TEM)
  ;;Open the input stream in binary mode, and load from it.
  (SETQ FASL-STREAM (MINI-OPEN-FILE MINI-FASLOAD-FILENAME T))
  (FASLOAD-INTERNAL FASL-STREAM PKG T)
  ;; FASLOAD Doesn't really read to EOF, must read rest to avoid getting out of phase
  (MINI-CLOSE FASL-STREAM)
  MINI-FASLOAD-FILENAME)

(DEFUN MINI-CLOSE (STREAM)
  (DO () (MINI-EOF-SEEN)
    (FUNCALL STREAM ':TYI)))

;This kludge simulates the behavior of PROPERTY-LIST-MIXIN.
;It is used instead of the generic-pathname in fasloading and readfiling;
;it handles the same messages that generic-pathnames are typically sent.
(DEFUN MINI-PLIST-RECEIVER (OP &REST ARGS)
  (SELECTQ OP
    (:GET (GET MINI-PLIST-RECEIVER-POINTER (CAR ARGS)))
    (:GETL (GETL MINI-PLIST-RECEIVER-POINTER (CAR ARGS)))
    (:PUTPROP (PUTPROP MINI-PLIST-RECEIVER-POINTER (CAR ARGS) (CADR ARGS)))
    (:REMPROP (REMPROP MINI-PLIST-RECEIVER-POINTER (CAR ARGS)))
    (:PLIST (CAR MINI-PLIST-RECEIVER-POINTER))
    (:PUSH-PROPERTY (PUSH (CAR ARGS) (GET MINI-PLIST-RECEIVER-POINTER (CADR ARGS))))
    (OTHERWISE
     (PRINT "Bad op to MINI-PLIST-RECEIVER ")
     (PRINT OP)
     (%HALT))))

(DEFUN MINI-READFILE (FILE-NAME PKG &AUX (FDEFINE-FILE-PATHNAME FILE-NAME) TEM)
  (LET ((EOF '(()))
	(STANDARD-INPUT (MINI-OPEN-FILE FILE-NAME NIL))
	(PACKAGE (PKG-FIND-PACKAGE PKG)))
    (DO FORM (READ STANDARD-INPUT EOF) (READ STANDARD-INPUT EOF) (EQ FORM EOF)
	(EVAL FORM))
    (OR (SETQ TEM (ASSOC FILE-NAME *COLD-LOADED-FILE-PROPERTY-LISTS*))
	(PUSH (SETQ TEM (NCONS FILE-NAME)) *COLD-LOADED-FILE-PROPERTY-LISTS*))
    (LET ((MINI-PLIST-RECEIVER-POINTER TEM))
      (SET-FILE-LOADED-ID 'MINI-PLIST-RECEIVER MINI-FILE-ID PACKAGE))))

(DEFUN MINI-BOOT ()
  (SETQ MINI-OPEN-P NIL)
  (VARIABLE-MAKUNBOUND MINI-PKT)
  (VARIABLE-MAKUNBOUND MINI-PKT-STRING))

(ADD-INITIALIZATION "MINI" '(MINI-BOOT) '(WARM FIRST))

;these use plus because + may be funbound in the cold load!!.  Problem is it's
; set up by the crash list, and the order of evaluation is not assured.
(defconst 3com-mebase #x30000 "address of 3com ethernet controller")
(defconst 3com-mecsr 3com-mebase "control/status register for 3com interface")
(defconst 3com-meback (plus 2 3com-mecsr) "jam backoff counter for 3com interface")
(defconst 3com-address-rom (plus 3com-mebase #x400) "3com ethernet address ROM")
(defconst 3com-address-ram (plus 3com-mebase #x600) "3com ethernet address RAM")
(defconst 3com-transmit-buffer (plus 3com-mebase #x800) "3com transmit buffer")
(defconst 3com-buffer-a (plus 3com-mebase #x1000) "3com receive buffer A")
(defconst 3com-buffer-b (plus 3com-mebase #x1800) "3com receive buffer B")
(defconst 3com-meahdr 3com-buffer-a "header word of 3com buffer A")
(defconst 3com-mebhdr 3com-buffer-b "header word of 3com buffer B")

;Note: this code operates with the byte-ordering switch ON on the 3-COM board.
;  This sets "low byte first" mode, like the 8086 and unlike the 68000.
;  Setting it this way means data CAN be read from packet buffers with 32 bit transfers.
;  This is NOT the way the board was shipped by 3-COM.
;  This means the pictures in the manual are byte reversed!
;  In particular, the byte offset words in the buffer headers are byte reversed!!!

  ;the #. s below avoid bombout because byte is a defsubst and not in the cold load.
(defconst bbsw #.(byte 1 7))		;set if buffer B belongs to ether.
(defconst absw #.(byte 1 6))		;set if buffer A belongs to ether.
(defconst tbsw #.(byte 1 5))		;set if transmit buffer belongs to ether.
(defconst jam #.(byte 1 4))			;writing 1 clears jam.
(defconst amsw #.(byte 1 3))		;address in RAM is valid
(defconst rbba #.(byte 1 2))		;A/B receive buffer ordering.
   ; bit 1 not used
(defconst reset #.(byte 1 0))		;reset the controller.
(defconst binten #.(byte 1 15.))		;enable interrupts on buffer B.
(defconst ainten #.(byte 1 14.))		;enable interrupts on buffer A.
(defconst tinten #.(byte 1 13.))		;enable interrupts on transmit buffer.
(defconst jinten #.(byte 1 12.))		;enable interrupts on jam.
(defconst pa #.(byte 4 8.))		;which frame addresses to accept

(defconst 3com-csr-background-bits (logior (dpb 7 pa 0)
					   (dpb 1 amsw 0)))


(defun write-3com-csr (new-csr)
   (%multibus-write-8 3com-mecsr new-csr))

(defun read-3com-csr ()
  (%multibus-read-8 3com-mecsr))

(defun 3com-reset ()
  (write-3com-csr 1)		;reset
  (setq mini-my-ethernet-address 0)
  (dotimes (i 6)
    (let ((next-byte (%multibus-read-8 (+ 3com-address-rom i))))
      (%multibus-write-8 (+ 3com-address-ram i) next-byte)
      (setq mini-my-ethernet-address (dpb next-byte 0010 (ash mini-my-ethernet-address 8.)))))
  ;set up normal csr - address RAM valid, receive MINE + Broadcast packets
  (write-3com-csr 3com-csr-background-bits))

(defun arm-3com-receive-buffer-a ()
  (write-3com-csr (dpb 1 absw 3com-csr-background-bits)))

(defun arm-3com-receive-buffer-b ()
  (write-3com-csr (dpb 1 bbsw 3com-csr-background-bits)))

(defun wait-for-3com-buffer ()
  (do ()
      ((mini-pkt-available))))

;;; multibus 3com receive buffer contains
;;; buffer-base:    meahdr (note byte reversed!!)
;;;          +2:    destination
;;;          +8:    source
;;;         +14:    type
;;;         +16:    data


(defun write-lambda-3com-frame-header (buffer-base offset source destination type)
  (setq offset (- offset 14.))
  (%multibus-write-8 (1+ buffer-base) (ldb 0010 offset)) ;offset reg is reversed!!!
  (%multibus-write-8  buffer-base (ldb 1010 offset))
  (%multibus-write-8 (+ buffer-base offset ) (ldb 5010 destination))
  (%multibus-write-8 (+ buffer-base offset 1) (ldb 4010 destination))
  (%multibus-write-8 (+ buffer-base offset 2) (ldb 3010 destination))
  (%multibus-write-8 (+ buffer-base offset 3) (ldb 2010 destination))
  (%multibus-write-8 (+ buffer-base offset 4) (ldb 1010 destination))
  (%multibus-write-8 (+ buffer-base offset 5) (ldb 0010 destination))

  (%multibus-write-8 (+ buffer-base offset 6) (ldb 5010 source))
  (%multibus-write-8 (+ buffer-base offset 7) (ldb 4010 source))
  (%multibus-write-8 (+ buffer-base offset 10) (ldb 3010 source))
  (%multibus-write-8 (+ buffer-base offset 11) (ldb 2010 source))
  (%multibus-write-8 (+ buffer-base offset 12) (ldb 1010 source))
  (%multibus-write-8 (+ buffer-base offset 13) (ldb 0010 source))
  
  (%multibus-write-8 (+ buffer-base offset 14) (ldb 0010 type))
  (%multibus-write-8 (+ buffer-base offset 15) (ldb 1010 type)))

(defun transmit-ethernet-16b-array (from-ether-host to-ether-host array nwords e-type)
  (let* ((physical-size (max (* nwords 2) 60.))
	 (offset (- 2048. physical-size))
	 (beginning-address (+ 3com-transmit-buffer offset)))
    (prog (csr start-time)
	  (setq start-time (%fixnum-microsecond-time))
       l  (setq csr (read-3com-csr))
	  (cond ((not (zerop (ldb jam csr)))
		 (write-3com-csr (dpb 1 jam 3com-csr-background-bits))	;reset jam
		 (go l))
		((not (zerop (ldb tbsw csr)))
		 (cond ((> (time-difference (%fixnum-microsecond-time)
					    start-time)
			   100000.)
			(return nil))		;give up.
		       (t (go l)))))
	  (do ((adr beginning-address (+ adr 2))
	       (from-index 0 (1+ from-index))
	       (n (* nwords 2) (1- n)))
	      ((zerop n))
	    (let ((data (aref array from-index)))
	      (%multibus-write-8 adr (ldb 0010 data))
	      (%multibus-write-8 (1+ adr) (ldb 1010 data))))
	  (write-lambda-3com-frame-header 3com-transmit-buffer
					  offset
					  from-ether-host
					  to-ether-host
					  e-type)
	  (write-3com-csr (dpb 1 tbsw 3com-csr-background-bits))
	  (do ()
	      ((zerop (ldb 0501 (read-3com-csr))))))))	;tbsw

(defun mini-pkt-available ()
  (or (zerop (ldb absw (read-3com-csr)))
      (zerop (ldb bbsw (read-3com-csr)))))

(defun receive-ethernet-16b-array (array)
  (wait-for-3com-buffer)
  (do ((got-one nil))
      ((not (null got-one)) array)
    (setq got-one (receive-ethernet-with-buffer-ready array))))

(defun receive-ethernet-with-buffer-ready (array &aux got-one)
  (cond ((zerop (ldb absw (read-3com-csr)))
	 (setq got-one (receive-ethernet-pkt-into-array 3com-buffer-a array))
	 (arm-3com-receive-buffer-a))
	((zerop (ldb bbsw (read-3com-csr)))
	 (setq got-one (receive-ethernet-pkt-into-array 3com-buffer-b array))
	 (arm-3com-receive-buffer-b)))
  got-one)

(defun get-ethernet-packet-type (buffer-base)
  (dpb (%multibus-read-8 (+ buffer-base 17))
       1010
       (%multibus-read-8 (+ buffer-base 16))))

;returns nil if the packet is not an interesting chaos packet
(defun receive-ethernet-pkt-into-array (buffer-base array)
  (cond ((not (zerop (logand 250 (%multibus-read-8 buffer-base)))) ;fcs error, etc
	 nil)
	(t
	 (let ((type (get-ethernet-packet-type buffer-base)))
	   (select type
	     (#x408 ;chaos-ethernet-type
	      (do ((adr (+ buffer-base 16.) (+ adr 2))
		   (wd-count 0 (1+ wd-count)))
		  ((>= wd-count 374)) ;chaos:max-words-per-pkt
		(aset (dpb (%multibus-read-8 (+ adr 1))
			   1010
			   (%multibus-read-8 adr))
		      array
		      wd-count))
	      t)
	     (#x608 ;address-resolution-type
	      ;;copy received data into pkt
	      (do ((adr (+ buffer-base 16.) (+ adr 2))
		   (wd-count 0 (1+ wd-count)))
		  ((>= wd-count 374))
		(aset (dpb (%multibus-read-8 (+ adr 1))
			   1010
			   (%multibus-read-8 adr))
		      array
		      wd-count))
	      (receive-addr-pkt array)		;record address; maybe send reply
	      nil))))))

; --------- addr res stuff

(defvar mini-addr-pkt (make-array 512. ':type 'art-16b))

(defun get-his-ethernet-address ()
  (princ "Trying to get remote ether address ")
  (setq mini-his-ethernet-address nil)
  (do ()
      ((not (null mini-his-ethernet-address)))
    (princ ".")
    (mini-send-addr-pkt mini-destination-address mini-local-host)
    (dotimes (i 10000)
      (cond ((mini-pkt-available)
	     (cond ((receive-ethernet-with-buffer-ready mini-addr-pkt)
		    (return t))))
	    ((not (null mini-his-ethernet-address))
	     (return t)))))
  (princ " remote ether address is ")
  (print mini-his-ethernet-address))

(defun mini-send-addr-pkt (dest-chaos-address source-chaos-address)
  (make-addr-pkt mini-addr-pkt
		 dest-chaos-address
		 source-chaos-address
		 1_8. ; request
		 0)
  (transmit-ethernet-16b-array 
    mini-my-ethernet-address -1 mini-addr-pkt 12. #x608))


(defun receive-addr-pkt (array)			;art-16b
  (princ " got addr pkt for host ")
  (princ (aref array 13))
  (cond ((= (aref array 13) mini-local-host)
	 (setq mini-his-ethernet-address (get-address-from-array array 4)))))

(defun make-addr-pkt (array dest-chaos-address source-chaos-address
		      &optional (opcode 1_8.) (his-ether 0))
		;array is art-16b
  (aset 1_8. array 0)				;ar_hardware
  (aset #x408 array 1)				;ar_protocol = CHAOS
  (aset (logior 6 2_8.) array 2)		;ar_hlength & ar_plength
  (aset opcode array 3)				;ar_opcode
  (put-address-to-array mini-my-ethernet-address array 4) ;ar_esender in slots 4, 5, and 6
  (aset source-chaos-address array 7)		;ar_csender
  (put-address-to-array his-ether array 10)	;ar-etarget
  (aset dest-chaos-address array 13))


(defun put-address-to-array (addr array place)
  (aset (dpb (ldb 4010 addr) 1010 (ldb 5010 addr)) array place)
  (aset (dpb (ldb 2010 addr) 1010 (ldb 3010 addr)) array (1+ place))
  (aset (dpb (ldb 0010 addr) 1010 (ldb 1010 addr)) array (+ place 2)))

(defun get-address-from-array (array place)
  (let ((word1 (aref array place))
	(word2 (aref array (1+ place)))
	(word3 (aref array (+ place 2))))
    (logior (ash (dpb (ldb 0010 word1) 1010 (ldb 1010 word1)) 32.)
	    (ash (dpb (ldb 0010 word2) 1010 (ldb 1010 word2)) 16.)
	    (dpb (ldb 0010 word3) 1010 (ldb 1010 word3)))))

; --------- end of address res stuff

(defun test-send-rfc ()
  (let ((pkt (chaos:get-pkt))
	(from-chaos-host 3410)
	(to-chaos-host 3034)
	(contact-name "FOO"))
    (setf (chaos:pkt-opcode pkt) 1)
    (setf (chaos:pkt-nbytes pkt) (string-length contact-name))
    (setf (chaos:pkt-source-address pkt) from-chaos-host)
    (setf (chaos:pkt-source-index-num pkt) 1)
    (setf (chaos:pkt-dest-address pkt) to-chaos-host)
    (setf (chaos:pkt-dest-index-num pkt) 0)
    (setf (chaos:pkt-num pkt) 1)
    (setf (chaos:pkt-ack-num pkt) 0)
    (copy-array-contents contact-name (chaos:pkt-string pkt))
    (store-array-leader (string-length contact-name) (chaos:pkt-string pkt) 0)
    (transmit-ethernet-16b-array
      mini-my-ethernet-address
      mini-his-ethernet-address
      pkt
      (// (+ 16. (string-length contact-name)) 2))
    (chaos:return-pkt pkt)))

(DEFUN MINI-DISK-SAVE (PARTITION &AUX (NO-QUERY T))
  "Save the current Lisp world in partition PARTITION.
PARTITION can be either a string naming a partition, or a number
which signifies a partition whose name starts with LOD.
NO-QUERY says do not ask for confirmation (or any keyboard input at all)."
  (PROG* DISK-SAVE
	 ((L (DISK-RESTORE-DECODE PARTITION))
	  (PART-NAME (STRING-APPEND (LDB 0010 (CADR L)) (LDB 1010 (CADR L))
				    (LDB 0010 (CAR L)) (LDB 1010 (CAR L))))
	  PART-BASE PART-SIZE SYSTEM-VERSION MAX-ADDR
	  (INC-PAGES-SAVED 0))
      (or inc-pages-saved system-version) ;reference to avoid compiler warning 
    (OR (MULTIPLE-VALUE (PART-BASE PART-SIZE)
	  (IF NO-QUERY
	      (FIND-DISK-PARTITION-FOR-READ PART-NAME)
	    (FIND-DISK-PARTITION-FOR-WRITE PART-NAME)))
	(RETURN NIL))

    ;; Cause cold boot initializations to happen when rebooted
    ;; and do the BEFORE-COLD initializations now
;    (INITIALIZATIONS 'BEFORE-COLD-INITIALIZATION-LIST T)
;    (RESET-INITIALIZATIONS 'COLD-INITIALIZATION-LIST)
    (SETQ COLD-BOOTING T) ; usually on before-cold-initialization-list
    (SETQ WHO-LINE-JUST-COLD-BOOTED-P T)
;    (LOGOUT)

    (CHAOS:RESET)  ;Otherwise, UCODE could lose hacking packets as world dumped.

    ;; Check again before updating the partition comment.
 ;  (CHECK-PARTITION-SIZE (+ INC-PAGES-SAVED PART-SIZE))
    (UPDATE-PARTITION-COMMENT PART-NAME "mini-dump" 0)

    (WITHOUT-INTERRUPTS
	;; The process we are now executing in will look like it was warm-booted when
	;; this saved band is restored.  Suppress the warm-boot message, but disable
	;; and flush the process so it doesn't start running with its state destroyed.
	;; We'd like to :RESET it, but can't because we are still running in it.
	;; If the process is the initial process, it will get a new state and get enabled
	;; during the boot process.
      (COND ((NOT (NULL CURRENT-PROCESS))
	     (PROCESS-DISABLE CURRENT-PROCESS)
	     (SET-PROCESS-WAIT CURRENT-PROCESS #'FALSE NIL)
	     (SETQ CURRENT-PROCESS NIL)))
	;; Once more with feeling, and bomb out badly if losing.
 	(SETQ MAX-ADDR (FIND-MAX-ADDR))
 ;	(CHECK-PARTITION-SIZE (+ INC-PAGES-SAVED PART-SIZE) T)
	;; Store the size in words rather than pages.  But don't get a bignum!
	(SETF (SYSTEM-COMMUNICATION-AREA %SYS-COM-HIGHEST-VIRTUAL-ADDRESS)
	      (LSH MAX-ADDR 8))
	(DO I 600 (1+ I) (= I 640)	;Clear the disk error log
	    (%P-STORE-TAG-AND-POINTER I 0 0))
	(%DISK-SAVE (SYSTEM-COMMUNICATION-AREA %SYS-COM-MEMORY-SIZE)
		    (CAR L) (CADR L)))))