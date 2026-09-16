;;; -*- Mode:LISP; Package:CHAOS; Base:8; Readtable:ZL -*-
;;; This is SYS: NETWORK; CHAOS; CHSNCP
;;;
;;;	** (c) Copyright 1980, 1984 Massachusetts Institute of Technology **
;;;
;;; Lisp Machine package for using the ChaosNet.  Does not contain Ethernet II interface.
;;; New Protocol of May, 1978
;;;
;;; Software details for general use and the Lisp Machine are documented in the
;;; chapter ``The Chaosnet'' in the Lisp Machine manual.

;;; cleaned up routing table stuff.  7/30/83 naha

;;; TO BE FIXED!!!!!!!!!!!!!!!!!!!!!!!!!!!!
;;; **** Fix the packet recording stuff****
;;; **** Per-connection retransmission timeouts/intervals  (Yow !  Do we have land lines
;;;      yet ?)

;;; This file contains the CHAOS net software from the packet level down

;;;Some standard abbreviations and mnemonic indicators:
;;;Items in this list with no "-" at either end signify abbreviations
;;;	which may occur in any context, those with one or more "-"'s
;;;	only occur in a context in which there are "-"'s in exactly
;;;	those places.
;;; PKT		Abbreviation for PACKET.  see the DEFSTRUCT
;;; CONN		Abbreviation for CONNECTION.  see the DEFSTRUCT
;;; SEND-		Cause a packet to be "sent" with retry etc. if applicable.
;;; TRANSMIT-	Cause a packet to be "transmitted" (i.e. placed on the net).
;;;			This is done by all the SEND- routines by calling
;;;			an appropriate TRANSMIT- routine to put the packet
;;;			on a list of packets to be put on the net.
;;; -STATE	A symbol representing a state that a connection might be in.
;;; -OP		A system constant whose value represents that of a packet op code.

;;; The file is divided into more-or-less localized units.  These units
;;;	and which of the contained functions are intended for outside
;;;	use are listed here in the order in which they appear in the file.

;;; Definitions for high-level structures (with functions to print them textually)
;;;	and various macros for the specialized formulas of the protocol
;;;   (Everything here is used everywhere)

;;; Low-level PKT management.
;;; functions referenced elsewhere:
;;;   ALLOCATE-PKT, FREE-PKT, SET-PKT-STRING

;;; Low-level CONN management.
;;; functions referenced elsewhere:
;;;   MAKE-CONNECTION, REMOVE-CONN

;;; High level Transmission routines
;;; functions referenced elsewhere:
;;;   TRANSMIT-LOS-INT-PKT, TRANSMIT-STS, TRANSMIT-NORMAL-PKT

;;;; Opcodes of packets
(DEFCONSTANT RFC-OP #o1 "Opcode value for RFC packets.")
(DEFCONSTANT OPN-OP #o2 "Opcode value for OPN packets.")
(DEFCONSTANT CLS-OP #o3 "Opcode value for CLS packets.")
(DEFCONSTANT FWD-OP #o4 "Opcode value for FWD packets.")
(DEFCONSTANT ANS-OP #o5 "Opcode value for ANS packets.")
(DEFCONSTANT SNS-OP #o6 "Opcode value for SNS packets.")
(DEFCONSTANT STS-OP #o7 "Opcode value for STS packets.")
(DEFCONSTANT RUT-OP #o10 "Opcode value for RUT packets.")
(DEFCONSTANT LOS-OP #o11 "Opcode value for LOS packets.")
(DEFCONSTANT LSN-OP #o12 "Opcode value for LSN packets.")
(DEFCONSTANT MNT-OP #o13 "Opcode value for MNT packets.")
(DEFCONSTANT EOF-OP #o14 "Opcode value for EOF packets.")
(DEFCONSTANT UNC-OP #o15 "Opcode value for UNC packets.")
(DEFCONSTANT BRD-OP #o16 "Opcode value for BRD packets.") 
(DEFCONSTANT DAT-OP #o200 "Default data opcode for 8-bit byte data.")

;;; This is for printing out packets nicely.
(DEFCONST OPCODE-LIST '(ZERO? RFC OPN CLS FWD ANS SNS STS RUT LOS LSN MNT EOF UNC BRD)
  "List of system packet opcode names, indexed by opcode value.")

;;; Size-of-packet symbols.  These symbols define the protocol specified sizes.
(DEFCONSTANT MAX-WORDS-PER-PKT 252.
  "Largest packet possible in 16-bit words, including header.")
(DEFCONSTANT MAX-DATA-WORDS-PER-PKT 244. "Number of 16-bit data words in largest packet.")
(DEFCONSTANT MAX-DATA-BYTES-PER-PKT 488. "Number of 8-bit data bytes in largest packet.")
(DEFCONSTANT FIRST-DATA-WORD-IN-PKT 8. 
  "Offset to first data word in packet (or, number of bytes in header).
Note that the contents of the packet, as an array, includes its header.")

(DEFVAR PKT-LEADER-SIZE :UNBOUND "Number of elements in array leader of a PKT.")

;;; Clock constants
(DEFCONST RETRANSMISSION-INTERVAL 30.)		;  1/2 second
(DEFCONST PROBE-INTERVAL (* 60. 10.))		; 10 seconds
(DEFCONST LONG-PROBE-INTERVAL (* 60. 60.))	;  1 minute
(DEFCONST HOST-DOWN-INTERVAL (* 60. 90. 2))	;  3 minutes

(DEFVAR BACKGROUND-REQUESTS NIL "List of requests to the background ChaosNet process.")
(DEFVAR RETRANSMISSION-NEEDED T
  "T if retransmission of packets may be needed.
Enables background process to wake up on clock.
Set this whenever you put something on SEND-PKTS of a CONN.")

(DEFVAR MORE-RETRANSMISSION-NEEDED)

(DEFCONST DEFAULT-WINDOW-SIZE #o15 "This is the default size of the window for a CONN.")
(DEFCONST MAXIMUM-WINDOW-SIZE #o200 "This is the maximum size of the window for a CONN.")

(DEFCONST MAXIMUM-INDEX #o200
  "Length of INDEX-CONN; number of distinct connection-indices.")
(DEFCONST MAXIMUM-INDEX-LOG-2-MINUS-1 (1- (HAULONG MAXIMUM-INDEX))
  "Number of bits in a connection index.")

;;; This array holds the CONN for the given index number.
;;; It is big enough that no uniquizing is needed, since it is
;;; used in circular fashion.
(DEFVAR INDEX-CONN (MAKE-ARRAY MAXIMUM-INDEX :AREA PERMANENT-STORAGE-AREA)
  "Array holding the connection for each index number.
No two connections at any one time can have the same index number.
Index numbers go in packets to identify which connection they are for.")
(DEFVAR INDEX-CONN-FREE-POINTER 1
  "Next connection index to consider using for a new connection.")

;;; This array holds the uniquizer for the current (or last) connection for a given index
(DEFVAR UNIQUIZER-TABLE (MAKE-ARRAY MAXIMUM-INDEX :TYPE 'ART-16B
				    		  :AREA PERMANENT-STORAGE-AREA)
  "For each connection index, holds last uniquizer value.
The uniquizer is incremented each time a new connection is made
for the given index, and it is used together with the index
in identifying the connection a packet is intended for.")

(DEFCONST BACKGROUND (MAKE-PROCESS "Chaos Background" :WARM-BOOT-ACTION NIL :PRIORITY 25.)
  "This process runs all chaosnet time response actions such as PROBEs and Retransmission,
and some other things for the net.")

(DEFCONST RECEIVER (MAKE-PROCESS "Chaos Receiver" :SIMPLE-P T :WARM-BOOT-ACTION NIL
				 		  :PRIORITY 35.)
  "SIMPLE-PROCESS that reads packets out of the wired buffers.")

(DEFVAR ENABLE NIL
  "T if chaosnet is enabled (turned on for use).")

;;; The following are used for negotiating the initial connection between a host and a server.
(DEFVAR PENDING-RFC-PKTS NIL
  "Incoming RFC packets not yet LISTENed for, linked through the PKT-LINK.")
(DEFVAR PENDING-LISTENS NIL
  "List of (CONTACT-NAME . CONN) for pending listens.")

;;; BRD in direction meters
(DEFVAR *BRD-HISTORY* ()
  "A list describing hosts which answered our BRDs (contact-name host-address)")
(DEFVAR *BRD-PKTS-IN* 0 "Number of answered BRD packets")

;;; This is NIL at first to leave the machine in piece during the cold load
(DEFVAR *RECEIVE-BROADCAST-PACKETS-P* () "BRD packets are responded to if this is T.")

;;; BRD out direction meters
(DEFVAR *BRD-REPLIES-IN* 0 "Number of replies from opening a broadcast connection")
(DEFVAR *BRD-PKTS-OUT* 0 "Number of BRDs we have transmitted")

(DEFVAR SERVER-ALIST NIL
  "Alist of (CONTACT-NAME FORM-TO-EVALUATE) for creating chaos servers.
Entries are put on with ADD-INITIALIZATION.
The form is evaluated in the background task when an incoming RFC
matches the contact name and there is no pending listen for it.")

;;; Packet lists and other pointers
(DEFVAR FREE-PKTS NIL
  "Chain of free packets, linked through the PKT-LINK field.")
(DEFVAR MADE-PKTS NIL
  "Chain of all packets constructed, linked through the PKT-MADE-LINK field.")

;;; Connection list
(DEFVAR CONN-LIST NIL
  "List of existing CONNs.")
(DEFVAR FREE-CONN-LIST NIL "List of free CONN structures (save consing).")
(DEFVAR PROTOTYPE-CONN :UNBOUND
  "A CONN object used for initializing other CONNs when they are made.
The prototype is simply copied into the new CONN.")
(DEFVAR DISTINGUISHED-PORT-CONN-TABLE)	;Assq list of special port numbers and conns
					;This is because of EFTP


;;;; Meters
(DEFVAR PKTS-FORWARDED :UNBOUND
  "Incremented when we forward a PKT to someone.")
(DEFVAR PKTS-OVER-FORWARDED :UNBOUND
  "Incremented when we forward a PKT for the nth time and discard it as a consequence.")
(DEFVAR PKTS-BAD-BIT-COUNT :UNBOUND
  "Incremented when a packet is discarded because of a bad bit count:
Bit count less than Dest, Source, and CRC words,
or not mod 16., or doesn't agree with software packet length.")
(DEFVAR PKTS-BAD-DEST :UNBOUND
  "Incremented when we discard a packet because hardware dest wasn't MY-ADDRESS.")
(DEFVAR PKTS-BAD-CRC-1 :UNBOUND
  "Incremented when a packet's CRC was bad on receive.")
(DEFVAR PKTS-BAD-CRC-2 :UNBOUND
  "Incremented when a packet's CRC was bad after readout.")
(DEFVAR PKTS-LOST :UNBOUND
  "Incremented when hardware says it lost a packet.")
(DEFVAR PKTS-MADE :UNBOUND
  "Number of PKTs ever created.")
(DEFVAR PKTS-RECEIVED :UNBOUND
  "Number of packets received from the chaosnet.")
(DEFVAR PKTS-TRANSMITTED :UNBOUND
  "Number of packets transmitted to the chaosnet.")
(DEFVAR PKTS-OTHER-DISCARDED :UNBOUND
  "Incremented when we discard a packet for misc other reasons.
Such as, too small to contain a protocol packet.")
(DEFVAR LOS-PKT-COUNT :UNBOUND
  "Number of all LOS packets ever received.")
(DEFVAR CURRENT-LOS-PKT-COUNT :UNBOUND
  "Number of packets currently on LOS-PKTS.")
(DEFVAR PKTS-RETRANSMITTED :UNBOUND
  "Number of packets retransmitted.")
(DEFVAR PKTS-DUPLICATED :UNBOUND
  "Number of duplicate packets received.")
(DEFVAR DATA-PKTS-IN :UNBOUND
  "Number of data packets received.")
(DEFVAR DATA-PKTS-OUT :UNBOUND
  "Number of data packets transmitted.")
  ;also SI:%COUNT-CHAOS-TRANSMIT-ABORTS which is maintained by the microcode
  ;Reference this with READ-METER, WRITE-METER

;;;; Debugging aids which keep records into the past (a short way).
(DEFVAR BAD-PKT-LIST NIL
  "List of strings describing packets received in error.")
(DEFVAR PKTS-BAD-CRC-SAVE-P NIL
  "Non-NIL means save all packets with bad crc.")
(DEFVAR LOS-PKTS NIL
  "Chain of recent LOS PKTs received from the network, linked by PKT-LINK.")
(DEFVAR MAX-LOS-PKTS-TO-KEEP 16.
  "Maximum number of LOS packets to keep on LOS-PKTS.
There may actually be more but they will be used by allocator.")
(DEFVAR RECENT-HEADERS :UNBOUND
  "Array of #o200 most recent packet transactions' headers.
Each row of the array contains the eight header words of the packet
and the time at which the record was made.")
(DEFVAR RECENT-HEADERS-POINTER :UNBOUND
  "Next index to use in storing in RECENT-HEADERS.")

(DEFVAR MY-ADDRESS :UNBOUND "This machine's chaosnet address.")
(DEFVAR MY-SUBNET :UNBOUND "This machine's chaosnet subnet number.")

;;; Will be used in the future by bridging machines
(DEFVAR MY-OTHER-ADDRESSES :UNBOUND "Secondary chaos addresses.")
(DEFVAR MY-OTHER-SUBNETS NIL "Secondary chaos subnet numbers.")

;;; This array is the routing table:  if we want to send a message to a given
;;; subnet, where should I forward it?  If the subnet # is greater than the
;;; length of the array, use the contents of array element zero.
;;; The contents of the array are the host number on our subnet who knows
;;; how to handle this packet.  NOTE that for now we can only be on one subnet.
;;; Don't use this table unless you are sure that the packet is not going to
;;; a host on THIS subnet!
;;; These tables are filled in by code in INITIALIZE-NCP-ONCE.
(DEFCONST ROUTING-TABLE-SIZE 96. "the number of subnets in the routing table")
(DEFVAR ROUTING-TABLE (MAKE-ARRAY ROUTING-TABLE-SIZE
				  :TYPE 'ART-16B :AREA PERMANENT-STORAGE-AREA))
(DEFVAR ROUTING-TABLE-COST (MAKE-ARRAY ROUTING-TABLE-SIZE
				       :TYPE 'ART-16B :AREA PERMANENT-STORAGE-AREA))
(DEFVAR ROUTING-TABLE-TYPE (MAKE-ARRAY routing-table-size
				       :TYPE ART-Q :AREA PERMANENT-STORAGE-AREA)
  "the type of the subnet")
(DEFVAR	MAXIMUM-ROUTING-COST 1024. "The maximum value in the routing table that is real.")

;;; hardware related specials
(DEFVAR BASE-ADDRESS)				;the base address of the hardware register
(DEFVAR CONTROL-STATUS-REGISTER)		;the control-status register
(DEFVAR MY-NUMBER-REGISTER)			;the cable address register
(DEFVAR WRITE-BUFFER-REGISTER)			;the write-data register
(DEFVAR READ-BUFFER-REGISTER)			;the read-data register
(DEFVAR BIT-COUNT-REGISTER)			;the bit count register
(DEFVAR INITIATE-TRANSFER-REGISTER)		;the start transfer register

;;; Interrupt (microcode) related specials
(DEFVAR INT-FREE-LIST-POINTER)			;Freelist used by microcode
(DEFVAR INT-RECEIVE-LIST-POINTER)		;Packets received at interrrupt level
(DEFVAR INT-TRANSMIT-LIST-POINTER)		;Packets to be transmitted at interrupt level

(DEFVAR FAKE-RECEIVE-LIST NIL
  "Chain of int pkts being /"transmitted/" from this machine to this machine.")

(DEFVAR CHAOS-BUFFER-AREA :UNBOUND
  "Area in which chaosnet INT-PKT's reside.")

(DEFVAR RESERVED-INT-PKT NIL)	;If non-NIL, the INT-PKT to use.  This permits the
				; receiver level stuff to reserve a packet and thus
				; avoid the possibility of blocking.

;;; These are interesting meters
(DEFCONST PEEK-A-BOO-LIST
	  '(PKTS-FORWARDED PKTS-OVER-FORWARDED PKTS-BAD-BIT-COUNT PKTS-BAD-DEST
	    PKTS-BAD-CRC-1 PKTS-BAD-CRC-2 PKTS-LOST PKTS-MADE PKTS-RECEIVED
	    PKTS-TRANSMITTED PKTS-OTHER-DISCARDED LOS-PKT-COUNT
	    CURRENT-LOS-PKT-COUNT PKTS-RETRANSMITTED PKTS-DUPLICATED DATA-PKTS-IN
	    DATA-PKTS-OUT))

(DEFUN RESET-METERS ()
  (DOLIST (METER PEEK-A-BOO-LIST)
    (SET METER 0))
  (WRITE-METER 'SYS:%COUNT-CHAOS-TRANSMIT-ABORTS 0))

;;; avoid unbound-symbol errors if new things have been added to peek-a-boo-list.
;;; These can be very embarrassing.
(RESET-METERS)	

(DEFUN RESET-ROUTING-TABLE ()
  "Flush out old routing data."
  (SETQ MY-OTHER-SUBNETS NIL)
  (DOTIMES (I (ARRAY-LENGTH ROUTING-TABLE))	;Clear out the routing table
    (SETF (AREF ROUTING-TABLE I) 0)
    (SETF (AREF ROUTING-TABLE-COST I) MAXIMUM-ROUTING-COST)
    (SETF (AREF ROUTING-TABLE-TYPE I) NIL))
  (SETF (AREF ROUTING-TABLE MY-SUBNET) MY-ADDRESS)
  (SETF (AREF ROUTING-TABLE-COST MY-SUBNET) 10.)
  (SI:SELECT-PROCESSOR
    (:CADR
      (SETF (AREF ROUTING-TABLE-TYPE MY-SUBNET) :CHAOS))
    (:LAMBDA
      (SETF (AREF ROUTING-TABLE-TYPE MY-SUBNET) :ETHERNET))))

;;;; High Level Structures

;;; Definitions for high level structures and various macros for the
;;;     specialized formulas of the protocol

;;; STRUCTURE DEFINITIONS: Connections (CONNs) and Packets (PKTs)

(DEFSUBST CONN-STATE (CONN)
  "The current state of CONN.
Possible states are CHAOS:INACTIVE-STATE, CHAOS:ANSWERED-STATE,
CHAOS:CLS-RECEIVED-STATE, CHAOS:LISTENING-STATE, CHAOS:RFC-RECEIVED-STATE,
CHAOS:RFC-SENT-STATE, CHAOS:OPEN-STATE, CHAOS:LOS-RECEIVED-STATE,
CHAOS:HOST-DOWN-STATE, CHAOS:FOREIGN-STATE, CHAOS:BROADCAST-SENT-STATE"
  (STATE CONN))

(DEFSTRUCT (CONN :ARRAY :NAMED (:ALTERANT NIL))
  "This structure is a connection, abbreviated CONN."
  (LOCAL-WINDOW-SIZE NIL :DOCUMENTATION "Window size for receiving")
  (FOREIGN-WINDOW-SIZE NIL :DOCUMENTATION "Window size for transmitting")
  (STATE 'INACTIVE-STATE :DOCUMENTATION "State of this connection.
States in which a connection may be.
INACTIVE-STATE
 This state indicates the CONN is not currently associated with any CHAOS channel.
ANSWERED-STATE
 This state indicates the CONN has received an ANS from the other end of the channel;
 it is waiting to be read.
 No I/O is allowed except reading the ANS packet already on the READ-PKTS chain.
CLS-RECEIVED-STATE
 This state indicates the CONN has received a CLS from the other end of the channel;
 any data packets that were received in order before the CLS are waiting
 to be read, followed by the CLS packet.
 No I/O is allowed except reading the packets already on th READ-PKTS chain.
LISTENING-STATE
 This state is given to a CONN on which a LSN has been sent while it is awaiting the RFC.
RFC-RECEIVED-STATE
 This state indicates that an RFC has been received on this CONN but that no response
 has yet been given (such as done by ACCEPT and REJECT).
RFC-SENT-STATE
 This state indicates that there has been an RFC sent on this CONN but that no response
 has yet been received from the foreign host.
OPEN-STATE
 This state is the normal state for an open connection
LOS-RECEIVED-STATE
 This state indicates the CONN has received a LOS from the other end of the channel;
 the LOS packet will be the data packet waiting to be read; any READ-PKTS
 or SEND-PKTS are discarded
 No I/O is allowed except reading the packets already on th READ-PKTS chain.
HOST-DOWN-STATE
 This state is entered when it is determined that the foreign
 host is down (or something). This is done in PROBE-CONN.
 No I/O is allowed except reading the packets already on th READ-PKTS chain.
FOREIGN-STATE
 Allows UNC packets to go in and out, for implementing non-Chaosnet protocols
BROADCAST-SENT-STATE
 We have transmitted a broadcast packet.  The following actions are possible:
 1. The user can send more BRD packets.
 2. The user can read all packets except OPNs (until buffering is exceeded)
 3. OPNs, when there are no queued input packets, will cause the connection
    to enter the OPEN state.  Any other packets received from other hosts after
    this OPEN state is reached will evoke a LOS packet.")
  (FOREIGN-ADDRESS 0 :DOCUMENTATION "Address <his> for the other end of this CONN")
  (FOREIGN-INDEX-NUM 0 :DOCUMENTATION "Index number <his> for the other end of this CONN")
  ;; LOCAL-ADDRESS is a constant and therefore not needed or included
  (LOCAL-INDEX-NUM 0 :DOCUMENTATION "Index number <mine> for this end of the CONN")
  (READ-PKTS NIL :DOCUMENTATION "Packets which have been read from the net and are in order")
  (READ-PKTS-LAST NIL :DOCUMENTATION "Last packet in READ-PKTS of the CONN")
  (RECEIVED-PKTS NIL :DOCUMENTATION "Packets which have been received but are not in order")

  (PKT-NUM-READ -1 :DOCUMENTATION "The <his> highest packet number given to user.")
  (PKT-NUM-RECEIVED -1 :DOCUMENTATION
		    "The <his> highest packet number in ordered list (READ-PKTS)")
  (PKT-NUM-ACKED -1 :DOCUMENTATION "The level of acknowledgement we have sent out to date")
  (TIME-LAST-RECEIVED NIL :DOCUMENTATION "Time of last input from net.")

  (SEND-PKTS NIL :DOCUMENTATION "List of packets which we must send.")
  (SEND-PKTS-LAST NIL :DOCUMENTATION "Last PT on SEND-PKTS")
  (SEND-PKTS-LENGTH 0 :DOCUMENTATION "Length of SEND-PKTS chain")
  (PKT-NUM-SENT 0 :DOCUMENTATION "Highest <our> packet number assigned.")
  (SEND-PKT-ACKED 0 :DOCUMENTATION
		  "The last packet number for which we received acknowledgement")
  (WINDOW-AVAILABLE 0 :DOCUMENTATION "Space in window not occupied by unacknowledged packets")
  (RETRANSMISSION-INTERVAL 30.
    :DOCUMENTATION "Retransmission interval for this CONN in 60ths.")

  (INTERRUPT-FUNCTION NIL :DOCUMENTATION
    "Function to be called in when a new packet arrives at the head of READ-PKTS")
  (CONN-PLIST NIL :DOCUMENTATION
    "Properties include RFC-CONTACT-NAME and LISTEN-CONTACT-NAME,
which record the contact names used in the two directions."))


(DEFSUBST CONN-LOCAL-WINDOW-SIZE (CONN) (LOCAL-WINDOW-SIZE CONN))
(DEFSUBST CONN-FOREIGN-WINDOW-SIZE (CONN) (FOREIGN-WINDOW-SIZE CONN))

(DEFSUBST CONN-FOREIGN-ADDRESS (CONN)
  "Address of host at other end of CONN."
  (FOREIGN-ADDRESS CONN))

(DEFSUBST CONN-FOREIGN-INDEX-NUM (CONN) (FOREIGN-INDEX-NUM CONN))
(DEFSUBST CONN-LOCAL-INDEX-NUM (CONN) (LOCAL-INDEX-NUM CONN))
(DEFSUBST CONN-READ-PKTS (CONN)
  "Chain of sequential packets available for reading from CONN by user."
  (READ-PKTS CONN))
(DEFSUBST CONN-READ-PKTS-LAST (CONN) (READ-PKTS-LAST CONN))
(DEFSUBST CONN-RECEIVED-PKTS (CONN) (RECEIVED-PKTS CONN))
(DEFSUBST CONN-PKT-NUM-READ (CONN) (PKT-NUM-READ CONN))
(DEFSUBST CONN-PKT-NUM-RECEIVED (CONN) (PKT-NUM-RECEIVED CONN))
(DEFSUBST CONN-PKT-NUM-ACKED (CONN) (PKT-NUM-ACKED CONN))
(DEFSUBST CONN-TIME-LAST-RECEIVED (CONN) (TIME-LAST-RECEIVED CONN))
(DEFSUBST CONN-SEND-PKTS (CONN) (SEND-PKTS CONN))
(DEFSUBST CONN-SEND-PKTS-LAST (CONN) (SEND-PKTS-LAST CONN))
(DEFSUBST CONN-SEND-PKTS-LENGTH (CONN) (SEND-PKTS-LENGTH CONN))
(DEFSUBST CONN-PKT-NUM-SENT (CONN) (PKT-NUM-SENT CONN))
(DEFSUBST CONN-SEND-PKT-ACKED (CONN) (SEND-PKT-ACKED CONN))
(DEFSUBST CONN-RETRANSMISSION-INTERVAL (CONN) (RETRANSMISSION-INTERVAL CONN))

(DEFSUBST CONN-WINDOW-AVAILABLE (CONN)
  "Number of packets that may be sent on CONN before outgoing window is full."
  (WINDOW-AVAILABLE CONN))

(DEFSUBST CONN-INTERRUPT-FUNCTION (CONN)
  "Function to be called when a new packet arrives for CONN."
  (INTERRUPT-FUNCTION CONN))

(DEFUN CONTACT-NAME (CONN)
  "Return the contact name with which connection CONN was created, or NIL if none.
Can be NIL if the connection is in a weird state."
  (OR (GETF (CONN-PLIST CONN) 'RFC-CONTACT-NAME)
      (GETF (CONN-PLIST CONN) 'LISTEN-CONTACT-NAME)))

(DEFSELECT ((:PROPERTY CONN NAMED-STRUCTURE-INVOKE))
  (:DESCRIBE (CONN)
    (PRINT-CONN CONN)
    (SI:DESCRIBE-DEFSTRUCT CONN 'CONN))
  (:PRINT-SELF (CONN STREAM IGNORE &OPTIONAL IGNORE)
    (SYS:PRINTING-RANDOM-OBJECT (CONN STREAM)
      (SEND STREAM :STRING-OUT "CHAOS Connection")
      (LET ((FHOST (SI:GET-HOST-FROM-ADDRESS (FOREIGN-ADDRESS CONN) :CHAOS))
	    CONTACT)
	(COND ((SETQ CONTACT (GETF (CONN-PLIST CONN) 'RFC-CONTACT-NAME))
	       (FORMAT STREAM " to ~A ~A" FHOST CONTACT))
	      ((SETQ CONTACT (GETF (CONN-PLIST CONN) 'SERVER-CONTACT-NAME))
	       (FORMAT STREAM " from ~A to ~A server" FHOST CONTACT)))))))

;;;; Packets.
;;; ***THESE DEFSTRUCTS USED BY QFILE!  RECOMPILE IT IF THEY CHANGE!***
(DEFSTRUCT (PKT-LEADER :ARRAY-LEADER (:CONSTRUCTOR NIL) (:ALTERANT NIL)
		       (:SIZE-SYMBOL PKT-LEADER-SIZE))
  "This structure is a packet, abbreviated PKT.
The elements of the array are the actual bits of the packet, whereas
the elements of the leader are internal information not transmitted."
  PKT-ACTIVE-LENGTH				;Not used
  (PKT-NAMED-STRUCTURE-SYMBOL PKT)		;Note PKT not PKT-LEADER;
  						; 2 defstructs for 1 object!
  (PKT-TIME-TRANSMITTED	nil :documentation
    "Time this PKT last transmitted")
  (PKT-TIMES-TRANSMITTED nil :documentation
    "Number of times this PKT has been transmitted")
  (PKT-STRING nil :documentation
    "A string which is the bytes of the PKT")
  (PKT-LINK nil :documentation
    "Links PKTs in the chain that describes them")
  (PKT-MADE-LINK nil :documentation
    "Links all packets ever made")
  ;; for all three -LINKs NIL = Last in chain, T = Not on chain at all.
  ;; PKT-LINK is T only if the PKT was freed but was on transmit list
  ;; and so is temporarily kept.
  (PKT-BEING-RETRANSMITTED nil :documentation
    "T if the packet is being retransmitted and so cannot be really freed.
If this is the case, it is bashed to be FREE so that the retransmitter
will know to free it up")
  (PKT-STATUS nil :documentation
    "Status of the packet
The status slot is used by the NCP to remember a small amount of info about the packet:
  NIL      Normal packet, in use by the NCP
  RELEASED Packet has been given to the user"))


(DEFSTRUCT (PKT :ARRAY (:CONSTRUCTOR NIL) (:ALTERANT NIL))
  "For a description of the fields in a PKT see the documentation on the CHAOS Net"
  ((PKT-OPCODE-LEFT-JUSTIFIED NIL)
   (PKT-OPCODE #o1010))
  ((PKT-NBYTES #o0014)
   (PKT-FWD-COUNT #o1404))
  ((PKT-DEST-ADDRESS NIL)
   (PKT-DEST-HOST-NUM #o0010)
   (PKT-DEST-SUBNET #o1010))
  PKT-DEST-INDEX-NUM
  ((PKT-SOURCE-ADDRESS NIL)
   (PKT-SOURCE-HOST-NUM #o0010)
   (PKT-SOURCE-SUBNET #o1010))
  PKT-SOURCE-INDEX-NUM
  PKT-NUM
  PKT-ACK-NUM
  PKT-FIRST-DATA-WORD
  PKT-SECOND-DATA-WORD)

(DEFMACRO PKT-NWORDS (PKT)
  `(+ FIRST-DATA-WORD-IN-PKT (LSH (1+ (PKT-NBYTES ,PKT)) -1)))

(DEFMACRO PKT-DEST-CONN (PKT)
  `(AREF INDEX-CONN (LDB MAXIMUM-INDEX-LOG-2-MINUS-1 (PKT-DEST-INDEX-NUM ,PKT))))

(DEFMACRO PKT-SOURCE-CONN (PKT)
  `(AREF INDEX-CONN (LDB MAXIMUM-INDEX-LOG-2-MINUS-1 (PKT-SOURCE-INDEX-NUM ,PKT))))

(DEFSELECT ((:PROPERTY PKT NAMED-STRUCTURE-INVOKE) IGNORE)
  (:PRINT-SELF (PKT STREAM IGNORE &OPTIONAL IGNORE)
    (SI:PRINTING-RANDOM-OBJECT (PKT STREAM)
      (FORMAT STREAM "CHAOS packet :STRING ~S :STATUS ~S"
	      (PKT-STRING PKT) (PKT-STATUS PKT))))
  (:DESCRIBE (PKT)
    (DESCRIBE-DEFSTRUCT PKT 'PKT)
    (DESCRIBE-DEFSTRUCT PKT 'PKT-LEADER)
    (PRINT-PKT PKT)))

;;;; The following macros are for accessing the elements of RECENT-HEADERS
(DEFMACRO RCNT-OPCODE (INDEX)
  `(LDB #o1010 (AREF RECENT-HEADERS ,INDEX 0)))
(DEFMACRO RCNT-NBYTES (INDEX)
  `(LDB #o0014 (AREF RECENT-HEADERS ,INDEX 1)))
(DEFMACRO RCNT-FWD-COUNT (INDEX)
  `(LDB #o1404 (AREF RECENT-HEADERS ,INDEX 1)))
(DEFMACRO RCNT-DEST-ADDRESS (INDEX)
  `(AREF RECENT-HEADERS ,INDEX 2))
(DEFMACRO RCNT-DEST-INDEX (INDEX)
  `(AREF RECENT-HEADERS ,INDEX 3))
(DEFMACRO RCNT-SOURCE-ADDRESS (INDEX)
  `(AREF RECENT-HEADERS ,INDEX 4))
(DEFMACRO RCNT-SOURCE-INDEX (INDEX)
  `(AREF RECENT-HEADERS ,INDEX 5))
(DEFMACRO RCNT-PKT-NUM (INDEX)
  `(AREF RECENT-HEADERS ,INDEX 6))
(DEFMACRO RCNT-ACK-NUM (INDEX)
  `(AREF RECENT-HEADERS ,INDEX 7))
(DEFMACRO RCNT-TIME-RECORDED (INDEX)
  `(AREF RECENT-HEADERS ,INDEX 8))

;;;; These are routines to print out the preceding structures in a readable form

(DEFUN PRINT-CONN (CONN &OPTIONAL (SHORT-PKT-DISPLAY T) &AUX (LAST NIL))
  (FORMAT T
	  "~%Chn: ~O (~O): Contact: ~S State: ~S From: ~O-~O to ~O-~O .~%"
	  (LOCAL-INDEX-NUM CONN) (%POINTER CONN)
	  (OR (GETF (CONN-PLIST CONN) 'RFC-CONTACT-NAME)
	      (GETF (CONN-PLIST CONN) 'LISTEN-CONTACT-NAME))
	  (STATE CONN)
	  MY-ADDRESS (LOCAL-INDEX-NUM CONN)
	  (FOREIGN-ADDRESS CONN) (FOREIGN-INDEX-NUM CONN))
  (FORMAT T
	  " Rcvd #~O, Read #~O, Acked #~O; Sent #~O, Acked #~O.  Windows: ~O, ~O (~O available).~%"
	  (PKT-NUM-RECEIVED CONN) (PKT-NUM-READ CONN) (PKT-NUM-ACKED CONN)
	  (PKT-NUM-SENT CONN) (SEND-PKT-ACKED CONN)
	  (LOCAL-WINDOW-SIZE CONN) (FOREIGN-WINDOW-SIZE CONN) (WINDOW-AVAILABLE CONN))
  
  (WHEN (SEND-PKTS CONN)
    (FORMAT T " Send pkts:")
    (DO ((PKT (SEND-PKTS CONN) (PKT-LINK PKT))
	 (LAST NIL PKT)
	 (LEN 0 (1+ LEN)))
	((NULL PKT)
	 (OR (EQ LAST (SEND-PKTS-LAST CONN))
	     (FORMAT T
		     "==> SEND-PKTS-LAST IS SCREWED! <==~%"))
	 (OR (= LEN (SEND-PKTS-LENGTH CONN))
	     (FORMAT T "==> SEND-PKTS-LENGTH IS SCREWED! <==~%")))
      (UNLESS (EQ CONN (PKT-SOURCE-CONN PKT))
	(FORMAT T "~Following PKT has bad PKT-SOURCE-CONN PKT = ~S"
		(PKT-SOURCE-CONN PKT)))
      (PRINT-PKT PKT SHORT-PKT-DISPLAY)))
  (SETQ LAST NIL)
  (WHEN (READ-PKTS CONN)
    (FORMAT T " Read pkts:")
    (DO ((PKT (READ-PKTS CONN) (PKT-LINK PKT))
	 (LAST NIL PKT)
	 (LEN 0 (1+ LEN)))
	((NULL PKT)
	 (OR (EQ LAST (READ-PKTS-LAST CONN))
	     (FORMAT T
		     "==> READ-PKTS-LAST IS SCREWED! <==~%")))
      (PRINT-PKT PKT SHORT-PKT-DISPLAY)))
  
  (WHEN (RECEIVED-PKTS CONN)
    (FORMAT T " Received pkts:")
    (DO ((PKT (RECEIVED-PKTS CONN) (PKT-LINK PKT)))
	((NULL PKT))
      (SETQ LAST PKT)
      (PRINT-PKT PKT SHORT-PKT-DISPLAY))))

;;; Print out a packet, if SHORT-DISPLAY is T only 1 line is printed.
(DEFUN PRINT-PKT (PKT &OPTIONAL (SHORT-DISPLAY NIL) INT-PKT-P)
  (TERPRI)
  (AND SHORT-DISPLAY (FORMAT T "   "))
  (FORMAT T "Number: #o~O (#o~O)  Opcode: #o~O (~A).  Number of bytes = #o~O ."
	  (PKT-NUM PKT)
	  (%POINTER PKT)
	  (PKT-OPCODE PKT)
	  (COND ((< (PKT-OPCODE PKT) (LENGTH OPCODE-LIST))
		 (NTH (PKT-OPCODE PKT) OPCODE-LIST))
		(( (PKT-OPCODE PKT) DAT-OP) 'DAT)
		(T (FORMAT NIL "==> #o~O <==" (PKT-OPCODE PKT))))
	  (PKT-NBYTES PKT))
  (UNLESS SHORT-DISPLAY
    (FORMAT T "~%From #o~O-~O to #o~O-~O .~%"
	    (PKT-SOURCE-ADDRESS PKT) (PKT-SOURCE-INDEX-NUM PKT)
	    (PKT-DEST-ADDRESS PKT) (PKT-DEST-INDEX-NUM PKT))
    ;        (FORMAT T "Contents:~S~%   " (PKT-STRING PKT))
    (LET ((MIN-WORDS (MIN 8. (PKT-NWORDS PKT))))
      (DO ((I 0 (1+ I))) (( I min-words))
	(FORMAT T "#o~6,48O~:[,~;~%~]" (AREF PKT I) (= (1+ I) MIN-WORDS))))
    (FORMAT T "Pkt number = #o~O, Ack number = #o~O, Forwarded #o~O times.~%"
	    (PKT-NUM PKT) (PKT-ACK-NUM PKT) (PKT-FWD-COUNT PKT))
    (UNLESS INT-PKT-P
      (FORMAT T "Retransmitted ~O times, last at ~S.~%Link = ~S~%"
	      (PKT-TIMES-TRANSMITTED PKT) (PKT-TIME-TRANSMITTED PKT)
	      (PKT-LINK PKT))))
  NIL)

(DEFUN PRINT-ALL-PKTS (CHAIN &OPTIONAL (SHORT-DISPLAY T))
  (DO ((PKT CHAIN (PKT-LINK PKT)))
      ((NULL PKT))
    (PRINT-PKT PKT SHORT-DISPLAY)))

;;;; Definitions for interrupt hacking

;;; To access the data base
(DEFMACRO INT-FREE-LIST ()
 `(%P-CONTENTS-OFFSET INT-FREE-LIST-POINTER 0))
(DEFMACRO INT-RECEIVE-LIST ()
  `(%P-CONTENTS-OFFSET INT-RECEIVE-LIST-POINTER 0))
(DEFMACRO INT-TRANSMIT-LIST ()
 `(%P-CONTENTS-OFFSET INT-TRANSMIT-LIST-POINTER 0))
;;; The array leader offsets are defined in the SYSTEM package
(DEFMACRO INT-PKT-WORD-COUNT (INT-PKT)
 `(ARRAY-LEADER ,INT-PKT %CHAOS-LEADER-WORD-COUNT))
(DEFMACRO INT-PKT-THREAD (INT-PKT)
 `(ARRAY-LEADER ,INT-PKT %CHAOS-LEADER-THREAD))
(DEFMACRO INT-PKT-CSR-1 (INT-PKT)
  `(ARRAY-LEADER ,INT-PKT %CHAOS-LEADER-CSR-1))
(DEFMACRO INT-PKT-CSR-2 (INT-PKT)
 `(ARRAY-LEADER ,INT-PKT %CHAOS-LEADER-CSR-2))
(DEFMACRO INT-PKT-BIT-COUNT (INT-PKT)
 `(ARRAY-LEADER ,INT-PKT %CHAOS-LEADER-BIT-COUNT))

;This DEFSTRUCT applies to INT-PKT's also
;(DEFSTRUCT (PKT :ARRAY (:CONSTRUCTOR NIL) (:alterant nil))
;      ((PKT-OPCODE-LEFT-JUSTIFIED NIL) (PKT-OPCODE 1010))
;      ((PKT-NBYTES 0014) (PKT-FWD-COUNT 1404))
;      ((PKT-DEST-ADDRESS NIL) (PKT-DEST-HOST-NUM 0010) (PKT-DEST-SUBNET 1010))
;	PKT-DEST-INDEX-NUM
;      ((PKT-SOURCE-ADDRESS NIL) (PKT-SOURCE-HOST-NUM 0010) (PKT-SOURCE-SUBNET 1010))
;	PKT-SOURCE-INDEX-NUM
;	PKT-NUM
;	PKT-ACK-NUM
;	PKT-FIRST-DATA-WORD
;	PKT-SECOND-DATA-WORD
;	)

;;; Also, at the end of an INT-PKT are the source address, destination address, and CRC
(DEFMACRO INT-PKT-HARDWARE-DEST (INT-PKT)
  `(AREF ,INT-PKT (- (INT-PKT-WORD-COUNT ,INT-PKT) 3)))

(DEFMACRO INT-PKT-HARDWARE-SOURCE (INT-PKT)
  `(AREF ,INT-PKT (- (INT-PKT-WORD-COUNT ,INT-PKT) 2)))

(DEFMACRO INT-PKT-CRC (INT-PKT)
  `(AREF ,INT-PKT (1- (INT-PKT-WORD-COUNT INT-PKT))))

;;;; MACROS: for various random things

(DEFMACRO PKTNUM-< (A B)
  "Compare two packet numbers, taking wrap-around into account."
   `(BIT-TEST #o100000 (- ,A ,B)))

(DEFMACRO PKTNUM-1+ (A)
  "Increment a packet number, with wrap-around."
   `(LOGAND #o177777 (1+ ,A)))

(DEFUN PKTNUM-- (A B &AUX TEM)
  "Subtract one packet number from another, with wrap-around."
    (SETQ TEM (- A B))
    (IF (< TEM 0)
	(+ TEM #o200000)
        TEM))

;;; Adds a new background task to the queue:  these tasks are ORDERED on a fifo bases
(DEFMACRO BACKGROUND-TASK (TASK)
  `(WITHOUT-INTERRUPTS
     (PUSH ,TASK BACKGROUND-REQUESTS)))

;;;; Initialize all of the data of the NCP routines

;;; Once-only initialization stuff
(DEFUN INITIALIZE-NCP-ONCE ()
  ;; hardware register address definitions
  (SETQ BASE-ADDRESS #o764140
	CONTROL-STATUS-REGISTER BASE-ADDRESS
	MY-NUMBER-REGISTER (+ BASE-ADDRESS (LSH %CHAOS-MY-NUMBER-OFFSET 1))
	WRITE-BUFFER-REGISTER (+ BASE-ADDRESS (LSH %CHAOS-WRITE-BUFFER-OFFSET 1))
	READ-BUFFER-REGISTER (+ BASE-ADDRESS (LSH %CHAOS-READ-BUFFER-OFFSET 1))
	BIT-COUNT-REGISTER (+ BASE-ADDRESS (LSH %CHAOS-BIT-COUNT-OFFSET 1))
	INITIATE-TRANSFER-REGISTER (+ BASE-ADDRESS (LSH %CHAOS-START-TRANSMIT-OFFSET 1))
	*RECEIVE-BROADCAST-PACKETS-P* NIL)
  (SETQ
    ;; Connection list
    PROTOTYPE-CONN (MAKE-CONN)

    ;; Recent headers
    ;;  Array of #o200 most recent packet transactions each row
    ;;  containing the eight header words of the packet and the
    ;;  time at which the record was made.
    RECENT-HEADERS (MAKE-ARRAY '(#o200 9.) :TYPE 'ART-16B :AREA PERMANENT-STORAGE-AREA)

    ;; Microcode and interrupt stuff
    INT-FREE-LIST-POINTER (ALOC (FUNCTION SYSTEM-COMMUNICATION-AREA)
				%SYS-COM-CHAOS-FREE-LIST)
    INT-RECEIVE-LIST-POINTER (ALOC (FUNCTION SYSTEM-COMMUNICATION-AREA)
				   %SYS-COM-CHAOS-RECEIVE-LIST)
    INT-TRANSMIT-LIST-POINTER (ALOC (FUNCTION SYSTEM-COMMUNICATION-AREA)
				    %SYS-COM-CHAOS-TRANSMIT-LIST))

  ;; Make 8 connections now so they're all on the same page.
  (DOTIMES (I 8.)
    (PUSH (MAKE-CONN) FREE-CONN-LIST))

;  ;; Initialize the routing table
;  (RESET-ROUTING-TABLE)
  )

(DEFUN SETUP-MY-ADDRESS ()
  (SI:SELECT-PROCESSOR
    (:CADR
     (SETQ MY-ADDRESS (%UNIBUS-READ MY-NUMBER-REGISTER))) ;Full address of this host.
    (:LAMBDA
     (WHEN (FBOUNDP 'SI:FIND-PROCESSOR-CONFIGURATION-STRUCTURE)
       (SI:FIND-PROCESSOR-CONFIGURATION-STRUCTURE))
     (LET ((NAMES-FOR-THIS-MACHINE (MULTIPLE-VALUE-LIST (SI:GET-PACK-NAME)))
	   MY-NAME)
       (COND ((VARIABLE-BOUNDP SI:*MY-PROC-NUMBER*)
	      (SETQ MY-NAME (NTH SI:*MY-PROC-NUMBER* NAMES-FOR-THIS-MACHINE)))
	     (T
	      (SETQ MY-NAME (CAR NAMES-FOR-THIS-MACHINE))))
       (SETQ MY-ADDRESS NIL)
       (IF (STRINGP MY-NAME)
	   (SETQ MY-ADDRESS (ADDRESS-PARSE MY-NAME)))
       (IF (NULL MY-ADDRESS)
	   (SETQ MY-ADDRESS #o3412))		; FLAG THAT ADDRESS IS BAD
       )
     ;; This won't compile on the CADR in the 99 that I have.
     ;; I don't know where to find the definition of SI:%PROCESSOR-CONF-CHAOS-ADDRESS
  #||
     (WHEN (FBOUNDP 'SI:FIND-PROCESSOR-CONFIGURATION-STRUCTURE)
       (SETF (SI:%PROCESSOR-CONF-CHAOS-ADDRESS-LO SI:*LAMBDA-PROC-CONF*) MY-ADDRESS))
   ||#
     ))
  (SETQ MY-SUBNET (LDB #o1010 MY-ADDRESS))	;Subnet of this host.
  (LET ((EXISTING-HOST (SI:GET-HOST-FROM-ADDRESS MY-ADDRESS :CHAOS)))
    (SETQ SI:LOCAL-HOST
	  (IF (AND EXISTING-HOST (EQ (SEND EXISTING-HOST :SYSTEM-TYPE) :LISPM))
	      EXISTING-HOST
	    (SI:MAKE-UNNAMED-HOST :LISPM `(:CHAOS (,MY-ADDRESS)))))))

;;; Cold-boot initialization stuff
(DEFUN INITIALIZE-NCP-COLD ()
  ;; Debugging aids which keep records into the past (a short way).
  (SETQ BAD-PKT-LIST NIL	;List of strings describing packets received in error
        PKTS-BAD-CRC-SAVE-P NIL ;Don't defaultly save packets with bad CRC
	LOS-PKTS NIL		;LOS PKTs received from the network linked through PKT-LINK.
	MAX-LOS-PKTS-TO-KEEP 20	;Maximum number of LOS packets to keep on LOS-PKTS
				;There may actually be more but they will be used by allocator
	RECENT-HEADERS-POINTER 0
	*RECEIVE-BROADCAST-PACKETS-P* NIL
	*BRD-PKTS-IN* 0
	*BRD-PKTS-OUT* 0
	*BRD-HISTORY* NIL
	*BRD-REPLIES-IN* 0)
  (RESET-METERS)
  (SETUP-MY-ADDRESS)
  (RESET-ROUTING-TABLE))

;;; Initializations needed on every warm boot
(DEFUN INITIALIZE-NCP-SYSTEM ()
  (RESET)
  ;; This will cause the initialization to happen if it hasn't already
  (ADD-INITIALIZATION "CHAOS-NCP" '(INITIALIZE-NCP-COLD) '(:COLD :FIRST))
  (SETUP-MY-ADDRESS)
  (SI:SELECT-PROCESSOR
    (:LAMBDA (FUNCALL (INTERN "LAMBDA-ETHER-INIT" 'ETHER))))
  (ENABLE))

;;;; Low Level PKT Management

;;; PKT MANAGEMENT.

;;; Creates a new pkt.  Only allocates the storage, doesn't initialize anything.
;;; This should only be called by allocate and with interrupts inhibited
;;; Make sure it doesnt happen in a temporary area.
(DEFUN MAKE-PKT (&AUX PKT (DEFAULT-CONS-AREA BACKGROUND-CONS-AREA))
  (SETQ PKT (MAKE-ARRAY MAX-WORDS-PER-PKT
			:TYPE ART-16B
			:LEADER-LENGTH PKT-LEADER-SIZE
			:NAMED-STRUCTURE-SYMBOL 'PKT))
  (SETF (PKT-STRING PKT)	     ;Create indirect array to reference as a string
	(MAKE-ARRAY MAX-DATA-BYTES-PER-PKT
		    :TYPE ART-STRING
		    :FILL-POINTER 0
		    :DISPLACED-TO PKT
		    :DISPLACED-INDEX-OFFSET 16.))
  (SETF (PKT-MADE-LINK PKT) MADE-PKTS)
  (SETQ MADE-PKTS PKT)
  PKT)

(DEFUN ALLOCATE-PKT (&AUX PKT)
  "Allocate, initialize and return a packet, reusing one if possible."
  (WITHOUT-INTERRUPTS
    (SETQ PKT (COND (FREE-PKTS
		      (PROG1 FREE-PKTS
			     (SETQ FREE-PKTS (PKT-LINK FREE-PKTS))))
		    ((> CURRENT-LOS-PKT-COUNT MAX-LOS-PKTS-TO-KEEP)
		     (PROG1 LOS-PKTS
			    (SETQ LOS-PKTS (PKT-LINK LOS-PKTS))
			    (SETQ CURRENT-LOS-PKT-COUNT (1- CURRENT-LOS-PKT-COUNT))))
		    (T (SETQ PKTS-MADE (1+ PKTS-MADE))
		       (MAKE-PKT))))
    (SETF (PKT-TIME-TRANSMITTED PKT) 0)
    (SETF (PKT-TIMES-TRANSMITTED PKT) 0)
    (SETF (FILL-POINTER (PKT-STRING PKT)) 0)
    (SETF (PKT-LINK PKT) T)
    (SETF (PKT-OPCODE PKT) 0)
    (SETF (PKT-NBYTES PKT) 0)
    (SETF (PKT-FWD-COUNT PKT) 0)
    PKT))

(DEFUN FREE-PKT (PKT)
  "Release the packet PKT so that ALLOCATE-PKT can reuse it.
It is ok to call this while PKT is still awaiting transmission
at interrupt level; it will not really be reused until it has been sent.
NOTE: This is for internal use by the chaosnet ncp ONLY.
User programs should use RETURN-PKT to free packets obtained with
GET-PKT or GET-NEXT-PKT."
  (WITHOUT-INTERRUPTS
   (COND ((NULL (PKT-BEING-RETRANSMITTED PKT))
          (SETF (PKT-LINK PKT) FREE-PKTS)
          (SETQ FREE-PKTS PKT))
         (T (SETF (PKT-BEING-RETRANSMITTED PKT) 'FREE)))))

(DEFUN SET-PKT-STRING (PKT STRING &REST OTHER-STRINGS)
  "Store data into packet PKT from STRING and OTHER-STRINGS concatenated.
The PKT-NBYTES field is updated."
  (SETQ STRING (STRING STRING))
  (LET ((LEN (ARRAY-ACTIVE-LENGTH STRING))
	(PKT-STRING (PKT-STRING PKT)))
    (COPY-ARRAY-PORTION STRING 0 LEN PKT-STRING 0 LEN)
    (WHEN OTHER-STRINGS
      (DO ((STRINGS OTHER-STRINGS (CDR STRINGS)))
	  ((OR (NULL STRINGS) ( LEN MAX-DATA-BYTES-PER-PKT)))
	;;>> should use copy-array-portion
	(DO ((IDX 0 (1+ IDX))
	     (STR (STRING (CAR STRINGS)))
	     (STR-LEN (STRING-LENGTH (STRING (CAR STRINGS)))))
	    ((OR ( IDX STR-LEN) ( LEN MAX-DATA-BYTES-PER-PKT)))
	  (SETF (CHAR PKT-STRING LEN) (CHAR STR IDX))
	  (INCF LEN))))
    (SETQ LEN (MIN MAX-DATA-BYTES-PER-PKT LEN))
    (SETF (PKT-NBYTES PKT) LEN)
    (SETF (FILL-POINTER (PKT-STRING PKT)) LEN)))

;;;; INT-PKT management routines

(DEFUN FREE-INT-PKT (INT-PKT)
  "Returns an INT-PKT to the free list"
  (UNLESS (= (%AREA-NUMBER INT-PKT) CHAOS-BUFFER-AREA)
    (FERROR NIL "Attempt to free non-interrupt packet ~A" INT-PKT))
  (PROG (OLD-FREE-LIST)
     LOOP
	(SETQ OLD-FREE-LIST (INT-FREE-LIST))
	(SETF (INT-PKT-THREAD INT-PKT) OLD-FREE-LIST)
	(OR (%STORE-CONDITIONAL INT-FREE-LIST-POINTER OLD-FREE-LIST INT-PKT)
	    (GO LOOP))
	(%CHAOS-WAKEUP)))

(DEFUN COUNT-INT-PKTS ()
  (WITHOUT-INTERRUPTS
    (DO ((N 0 (1+ N))
	 (PKT (INT-FREE-LIST) (INT-PKT-THREAD PKT)))
	((OR (NULL PKT) (> N #o100)) N))))

(DEFMACRO CONVERT-TO-PKT (INT-PKT &OPTIONAL (FREE-PKT-FLAG T))
  "Allocates a new packet, copies the INT-PKT to it, and then deallocates the INT-PKT"
  (LET ((PKT (GENTEMP "PKT"))
	(INT-PKT-I (GENTEMP "INT-PKT"))
	(NW (GENTEMP "NW")))
    `(LET ((,PKT (ALLOCATE-PKT))
	   (,INT-PKT-I ,INT-PKT) ,NW)
       (SETQ ,NW (PKT-NWORDS ,INT-PKT-I))
       (WITHOUT-INTERRUPTS
	 (%BLT (%MAKE-POINTER-OFFSET DTP-FIX ,INT-PKT-I
				     (SI::ARRAY-DATA-OFFSET ,INT-PKT-I))
	       (%MAKE-POINTER-OFFSET DTP-FIX ,PKT (SI::ARRAY-DATA-OFFSET ,PKT))
	       (CEILING ,NW 2)
	       1))
       (STORE-ARRAY-LEADER (PKT-NBYTES ,INT-PKT-I) (PKT-STRING ,PKT) 0)
       (AND ,FREE-PKT-FLAG (FREE-INT-PKT ,INT-PKT-I))
       ,PKT)))

(DEFUN ALLOCATE-INT-PKT (&OPTIONAL (WAIT-IF-NECESSARY T) &AUX INT-PKT FREE-LIST)
  "Allocates a new INT-PKT may have to wait for one, so be careful
that it is ok that the process this gets called from can be safely suspended
or that a packet is reserved  (in other words, freeing up INT-PKTS better
not rely on the caller!)."
  (COND ((NULL RESERVED-INT-PKT)
	 (DO-FOREVER
	   (SETQ FREE-LIST (INT-FREE-LIST))
	   (COND ((NULL FREE-LIST)
		  (IF WAIT-IF-NECESSARY
		      (PROCESS-WAIT "Chaos buffer" #'(LAMBDA () (INT-FREE-LIST)))
		    (RETURN NIL)))
		 ((%STORE-CONDITIONAL INT-FREE-LIST-POINTER
				      FREE-LIST (INT-PKT-THREAD FREE-LIST))
		  (RETURN (SETQ INT-PKT FREE-LIST))))))
	;; No WITHOUT-INTERRUPTS needed here since RESERVED-INT-PKT never non-null
	;; in a process, only inside the scheduler
	(T (SETQ INT-PKT RESERVED-INT-PKT
		 RESERVED-INT-PKT NIL)))
  (AND INT-PKT (SETF (INT-PKT-THREAD INT-PKT) NIL))
  INT-PKT)

(DEFUN CONVERT-TO-INT-PKT (PKT &AUX INT-PKT NW)
  (SETQ INT-PKT (ALLOCATE-INT-PKT))
  (SETQ NW (PKT-NWORDS PKT))
  (WITHOUT-INTERRUPTS
    (%BLT (%MAKE-POINTER-OFFSET DTP-FIX PKT (SI:ARRAY-DATA-OFFSET PKT))
	  (%MAKE-POINTER-OFFSET DTP-FIX INT-PKT (SI:ARRAY-DATA-OFFSET INT-PKT))
	  (CEILING NW 2)
	  1))
  (SETF (INT-PKT-WORD-COUNT INT-PKT) NW)		;This is probably superfluous
  INT-PKT)

;;;; Low Level CONN Management

;;; CONN MANAGEMENT.

;;; Create a connection.  Returns the connection.
(DEFUN MAKE-CONNECTION ( &OPTIONAL CONN &AUX CONS)
  (WITHOUT-INTERRUPTS
    (COND (CONN)			;Caller supplying CONN to be recycled
	  ((SETQ CONS FREE-CONN-LIST)	;Recycle one
	   (SETQ FREE-CONN-LIST (CDR CONS)
		 CONN (CAR CONS))
	   (COPY-ARRAY-CONTENTS PROTOTYPE-CONN CONN))
	  ((SETQ CONN (MAKE-CONN)))))
  (OR (EQ (STATE CONN) 'INACTIVE-STATE)
      (FERROR NIL "Attempt to reuse ~S, which is in the ~A, not INACTIVE-STATE"
	      CONN (STATE CONN)))
  (AND (MEMQ CONN FREE-CONN-LIST)
       (FERROR NIL "Attempt to reuse ~S, which was on FREE-CONN-LIST twice (now only once)."
	       CONN))
  (AND (MEMQ CONN CONN-LIST)
       (FERROR NIL "Attempt to reuse ~S, which is already in use." CONN))
  (DO ((FP (\ (1+ INDEX-CONN-FREE-POINTER) MAXIMUM-INDEX) (\ (1+ FP) MAXIMUM-INDEX))
       (COUNTER MAXIMUM-INDEX (1- COUNTER)))
      ((%STORE-CONDITIONAL (LOCF (AREF INDEX-CONN (IF (= FP 0) (SETQ FP 1) FP)))
			   NIL
			   CONN)
       (SETQ INDEX-CONN-FREE-POINTER FP)
       (SETF (LOCAL-INDEX-NUM CONN) (DPB (INCF (AREF UNIQUIZER-TABLE FP))
					 (DPB MAXIMUM-INDEX-LOG-2-MINUS-1
					      #o0606
					      (- #o20 MAXIMUM-INDEX-LOG-2-MINUS-1))
					 FP))
       (SETF (CONN-RETRANSMISSION-INTERVAL CONN) RETRANSMISSION-INTERVAL)
       (WITHOUT-INTERRUPTS
	 (SETQ CONN-LIST (RPLACD (OR CONS (NCONS CONN)) CONN-LIST)))
	 CONN)
    (AND (MINUSP COUNTER)
	 (FERROR 'SYS:NETWORK-RESOURCES-EXHAUSTED "Connection table full"))))

(DEFUN REMOVE-CONN (CONN)
  "Remove connection-object CONN from the connection tables and free its packets."
  (WITHOUT-INTERRUPTS
    (FREE-ALL-READ-PKTS CONN)
    (FREE-ALL-RECEIVED-PKTS CONN)
    (FREE-ALL-SEND-PKTS CONN)
    (SETF (STATE CONN) 'INACTIVE-STATE)
    (SETF (AREF INDEX-CONN (LDB MAXIMUM-INDEX-LOG-2-MINUS-1 (LOCAL-INDEX-NUM CONN))) NIL)
    (SETQ DISTINGUISHED-PORT-CONN-TABLE
	  (DELQ (RASSQ CONN DISTINGUISHED-PORT-CONN-TABLE) DISTINGUISHED-PORT-CONN-TABLE))
    (LET ((CONS (MEMQ CONN CONN-LIST)))
      (SETQ CONN-LIST (DELQ CONN CONN-LIST))
      (OR (MEMQ CONN FREE-CONN-LIST)
	  (SETQ FREE-CONN-LIST (RPLACD (OR CONS (NCONS CONN)) FREE-CONN-LIST))))
    (DOLIST (X PENDING-LISTENS)
      (AND (EQ (CDR X) CONN) (SETQ PENDING-LISTENS (DELQ X PENDING-LISTENS))))
    NIL))

;;; Must be called with interrupts off.
(DEFUN FREE-ALL-READ-PKTS (CONN)
  (DO ((PKT (READ-PKTS CONN) (PKT-LINK PKT))
       (PREV NIL PKT))
      (NIL)
    (AND PREV (FREE-PKT PREV))
    (OR PKT (RETURN NIL)))
  (SETF (READ-PKTS CONN) NIL)
  (SETF (READ-PKTS-LAST CONN) NIL))

;;; Must be called with interrupts off.
(DEFUN FREE-ALL-RECEIVED-PKTS (CONN)
  (DO ((PKT (RECEIVED-PKTS CONN) (PKT-LINK PKT))
       (PREV NIL PKT))
      (NIL)
    (AND PREV (FREE-PKT PREV))
    (OR PKT (RETURN NIL)))
  (SETF (RECEIVED-PKTS CONN) NIL))

;;; Must be called with interrupts off.
(DEFUN FREE-ALL-SEND-PKTS (CONN)
  (DO ((PKT (SEND-PKTS CONN) (PKT-LINK PKT))
       (PREV NIL PKT))
      (NIL)
    (AND PREV (FREE-PKT PREV))			;This offseting so doesn't rely on PKT-LINK of
    (OR PKT (RETURN NIL)))			; a PKT it has freed.
  (SETF (SEND-PKTS CONN) NIL)
  (SETF (SEND-PKTS-LAST CONN) NIL)
  (SETF (SEND-PKTS-LENGTH CONN) 0))

(DEFUN INTERRUPT-CONN (REASON CONN &REST ARGS &AUX (IFUN (INTERRUPT-FUNCTION CONN)))
  "Causes the CONN's INTERRUPT-FUNCTION to be run in the background process with the
specified reason and arguments
 Reasons are:
  :INPUT		input has arrived
  :OUTPUT		the window, which was full, now has room in it
  :CHANGE-OF-STATE	the state of the connection has just changed"
  (AND IFUN
       (BACKGROUND-TASK `(INTERRUPT-CONN-INTERNAL ',IFUN ',REASON ',CONN
						  ',(APPEND ARGS NIL)))))

;;; If while the request was on the queue, the connection was flushed, get rid
;;; of the interrupt.  Because of connection reusing, this is somewhat heuristic.
(DEFUN INTERRUPT-CONN-INTERNAL (IFUN REASON CONN ARGS)
  (OR (EQ (STATE CONN) 'INACTIVE-STATE)
      (NEQ (INTERRUPT-FUNCTION CONN) IFUN)
      (APPLY IFUN REASON CONN ARGS)))

;;;; High Level Transmission Routines

;;; These are the routines which cause a packet to be queued for transmission.

(DEFUN TRANSMIT-PKT (PKT &OPTIONAL ACK-P)
  "Put the pkt on the transmit list, and create a phony transmitter interrupt
  if needed so that the interrupt level will start sending.
If the second arg is T, put an ACK aboard this PKT.
This is a very low level function, called mainly by the following 2 functions.
/(Also called by the retransmitter and forwarder.)"
  (AND (> (PKT-NBYTES PKT) MAX-DATA-BYTES-PER-PKT)
       (FERROR NIL "Attempt to transmit an invalid packet (~S).
The length ~O is greater than the maximum packet size (~O)."
	       PKT (PKT-NBYTES PKT) MAX-DATA-BYTES-PER-PKT))
  (WHEN ACK-P
    (WITHOUT-INTERRUPTS
      (LET ((CONN (PKT-SOURCE-CONN PKT)))
	(OR CONN (FERROR NIL "~S has null connection." PKT))
	(LET ((ACKN (PKT-NUM-READ CONN)))
	  (SETF (PKT-ACK-NUM PKT) ACKN)
	  (SETF (PKT-NUM-ACKED CONN) ACKN)))))
  (SETF (PKT-TIME-TRANSMITTED PKT) (TIME))
  (SETF (PKT-TIMES-TRANSMITTED PKT) (1+ (PKT-TIMES-TRANSMITTED PKT)))
  (TRANSMIT-INT-PKT (CONVERT-TO-INT-PKT PKT)) )

(DEFUN TRANSMIT-INT-PKT-FOR-CONN (CONN PKT)
  (SETF (PKT-SOURCE-ADDRESS PKT) MY-ADDRESS)
  (SETF (PKT-SOURCE-INDEX-NUM PKT) (LOCAL-INDEX-NUM CONN))
  (SETF (PKT-DEST-ADDRESS PKT) (FOREIGN-ADDRESS CONN))
  (SETF (PKT-DEST-INDEX-NUM PKT) (LDB 0020 (FOREIGN-INDEX-NUM CONN)))
  (WITHOUT-INTERRUPTS
    (LET ((ACKN (PKT-NUM-READ CONN)))
      (SETF (PKT-ACK-NUM PKT) ACKN)
      (SETF (PKT-NUM-ACKED CONN) ACKN)))
  (TRANSMIT-INT-PKT PKT))

(DEFUN TRANSMIT-LOS-INT-PKT (INT-PKT OP &OPTIONAL REASON &AUX DH DI LEN)
  "Given a losing pkt or an RFC we want to reject, shuffle the
pkt and return it.  Caller must specify opcode, either LOS or CLS.
If the OP is CLS, include a string which is the reason the RFC was
rejected.  Note that the very same pkt is used, so when this is called
the pkt had better not be on any lists or anything."
  (SETF (PKT-OPCODE INT-PKT) OP)
  (WHEN REASON
    (SETF (PKT-NBYTES INT-PKT) (SETQ LEN (ARRAY-ACTIVE-LENGTH REASON)))
    (DO ((SIDX 0 (+ SIDX 2))
	 (WIDX FIRST-DATA-WORD-IN-PKT (1+ WIDX)))
	(( SIDX LEN))
      (SETF (AREF INT-PKT WIDX) (IF (= (1+ SIDX) LEN)
				    (AREF REASON SIDX)
				    (DPB (AREF REASON (1+ SIDX))
					 #o1010
					 (AREF REASON SIDX))))))
  (SETQ DH (PKT-DEST-ADDRESS INT-PKT)
	DI (PKT-DEST-INDEX-NUM INT-PKT))
  (SETF (PKT-DEST-ADDRESS INT-PKT) (PKT-SOURCE-ADDRESS INT-PKT))
  (SETF (PKT-DEST-INDEX-NUM INT-PKT) (PKT-SOURCE-INDEX-NUM INT-PKT))
  (SETF (PKT-SOURCE-ADDRESS INT-PKT) DH)
  (SETF (PKT-SOURCE-INDEX-NUM INT-PKT) DI)
  (TRANSMIT-INT-PKT INT-PKT))

(DEFUN TRANSMIT-NORMAL-PKT (CONN PKT &OPTIONAL (PKTN 0) (ACK-PKTN 0) &AUX ACK-P)
  "Send a normal pkt (i.e., not LOS nor DATA)
Caller must allocate the pkt, and fill in the opcode, nbytes, and data parts.
The PKT and ACK-PKT numbers to place in the packet are optional arguments,
they default to 0.  If T is provided for either, the usual thing happens."
  (WHEN (EQ PKTN T)
    (SETQ PKTN (PKTNUM-1+ (PKT-NUM-SENT CONN)))
    (SETF (PKT-NUM-SENT CONN) PKTN))
  (SETF (PKT-NUM PKT) PKTN)
  (IF (EQ ACK-PKTN T)
      (SETQ ACK-P T)
    (SETF (PKT-ACK-NUM PKT) ACK-PKTN))
  (SETF (PKT-SOURCE-ADDRESS PKT) MY-ADDRESS)
  (SETF (PKT-SOURCE-INDEX-NUM PKT) (LOCAL-INDEX-NUM CONN))
  (SETF (PKT-DEST-ADDRESS PKT) (FOREIGN-ADDRESS CONN))
  (SETF (PKT-DEST-INDEX-NUM PKT) (LDB 0020 (FOREIGN-INDEX-NUM CONN)))
  (TRANSMIT-PKT PKT ACK-P))

(DEFVAR STS-WHY-ARRAY (MAKE-ARRAY #o100 :LEADER-LIST '(100 0)))

(DEFUN PRINT-STS-WHY ()
  (LET ((N (ARRAY-LEADER STS-WHY-ARRAY 1)))
    (DO I (\ (1+ N) #o100) (\ (1+ I) #o100) NIL
      (PRINT (AREF STS-WHY-ARRAY I))
      (AND (= I N) (RETURN NIL)))))

;;; Internal routine to send a status packet to a connection.
(DEFUN TRANSMIT-STS (CONN WHY &AUX PKT)
  (SETF (AREF STS-WHY-ARRAY (ARRAY-LEADER STS-WHY-ARRAY 1)) WHY)
  (SETF (ARRAY-LEADER STS-WHY-ARRAY 1) (\ (1+ (ARRAY-LEADER STS-WHY-ARRAY 1)) #o100))
  (SETQ PKT (ALLOCATE-INT-PKT))
  (SETF (PKT-OPCODE PKT) STS-OP)
  (SETF (PKT-NBYTES PKT) 4)
  (SETF (PKT-FIRST-DATA-WORD PKT) (PKT-NUM-RECEIVED CONN))
  (SETF (PKT-SECOND-DATA-WORD PKT) (LOCAL-WINDOW-SIZE CONN))
  (TRANSMIT-INT-PKT-FOR-CONN CONN PKT))

;;;; Output-Main Program level

(DEFUN RELEASE-PKT (PKT)
  "Release a packet to a routine outside the NCP.
This routine should be called whenever returning a packet as a value
to a caller which is outside the NCP"
  (COND ((NULL (PKT-STATUS PKT))
         (SETF (PKT-STATUS PKT) 'RELEASED)
         (SETF (PKT-LINK PKT) NIL))
        (T (FERROR NIL "Attempt to release ~S, which is already released." PKT))))

;;; To send a PKT, first call GET-PKT to give you a pkt, fill it full of
;;; cruft and set its NBYTES, and then call SEND-PKT on it.

(DEFUN GET-PKT ( &AUX PKT)
  "Allocate and return a /"released/" packet.
A released packet is one which can be in use outside the chaosnet ncp itself.
This is the proper way for a progam which uses the chaosnet to get a packet.
When you are finished with it, call RETURN-PKT to allow it to be reused."
  (SETQ PKT (ALLOCATE-PKT))
  (RELEASE-PKT PKT)
  PKT)

;;; CONN must be in OPEN-STATE, and the OPCODE must be a DAT opcode.
(DEFUN SEND-PKT (CONN PKT &OPTIONAL (OPCODE DAT-OP))
  "Send the data packet PKT to connection CONN.  OPCODE specifies the type of packet;
The default is DAT (opcode #o200)  PKT is returned to the chaosnet NCP
and should not be used further by the caller.
The value is the packet number assigned to the packet."
  (CASE (STATE CONN)
    (OPEN-STATE
      (OR (BIT-TEST DAT-OP OPCODE) (= EOF-OP OPCODE)
	  (FERROR NIL "~O is not a legal opcode." OPCODE))
      (PROCESS-WAIT "Chaosnet Output"
		    (FUNCTION (LAMBDA (X) (OR (MAY-TRANSMIT X)
					      (NEQ (STATE X) 'OPEN-STATE))))
		    CONN)
      (COND ((EQ (STATE CONN) 'OPEN-STATE)
	     (OR (EQ (PKT-STATUS PKT) 'RELEASED)
		 (FERROR NIL "Attempt to transmit ~S, which is not released." PKT))
	     (SETF (PKT-STATUS PKT) NIL)
	     (SETF (PKT-OPCODE PKT) OPCODE)
	     (SETF (WINDOW-AVAILABLE CONN) (1- (WINDOW-AVAILABLE CONN)))
	     (TRANSMIT-NORMAL-PKT CONN PKT T T)   ;And send it for the first time.
	     (WITHOUT-INTERRUPTS		  ;Must do the transmit before putting it
	       (LET ((LAST (SEND-PKTS-LAST CONN)))  ;in SEND-PKTS because TRANSMIT-NORMAL-PKT
		 (COND (LAST (SETF (PKT-LINK LAST) PKT)) ;fills in lots of fields.
		       (T (SETF (SEND-PKTS CONN) PKT)))
		 (SETF (SEND-PKTS-LAST CONN) PKT)
		 (SETF (PKT-LINK PKT) NIL)
		 (SETF (SEND-PKTS-LENGTH CONN) (1+ (SEND-PKTS-LENGTH CONN)))
		 (SETQ RETRANSMISSION-NEEDED T))
	       (PKT-NUM PKT)))
	    (T (REPORT-BAD-CONNECTION-STATE CONN "transmit on"))))
    (T (REPORT-BAD-CONNECTION-STATE CONN "transmit on"))))

(DEFUN SEND-STRING (CONN &REST STRINGS &AUX PKT)
  "Send data made by concatenating STRINGS down connection CONN."
  (SETQ PKT (GET-PKT))
  (APPLY #'SET-PKT-STRING PKT STRINGS)
  (SEND-PKT CONN PKT))

;;; User level routine to transmit an uncontrolled packet.
(DEFUN SEND-UNC-PKT (CONN PKT
                     &OPTIONAL (PKTN-FIELD (PKT-NUM PKT)) (ACK-FIELD (PKT-ACK-NUM PKT)))
  "Send a user-handled uncontrolled packet PKT down connection CONN.
The opcode field of PKT should be set up by the caller."
  (SETF (PKT-OPCODE PKT) UNC-OP)
  (TRANSMIT-NORMAL-PKT CONN PKT PKTN-FIELD ACK-FIELD))

(DEFUN MAY-TRANSMIT (CONN)
  "T if more packets can be sent down CONN without filling up the transmit window.
Packets awaiting transmission count against the limits."
  (> (WINDOW-AVAILABLE CONN) 0))

(DEFUN DATA-AVAILABLE (CONN)
  "T if input data is available on connection CONN."
  (NOT (NULL (READ-PKTS CONN))))

(DEFUN FINISH-CONN (CONN &OPTIONAL (WHOSTATE "Net Finish"))
  "Wait until all packets awaiting transmission on CONN have been sent and acknowledged.
Also returns if the connection is closed.
Returns T if the connection is still open."
  (PROCESS-WAIT WHOSTATE #'CONN-FINISHED-P CONN)
  (EQ (STATE CONN) 'OPEN-STATE))
(DEFF FINISH 'FINISH-CONN)
(MAKE-OBSOLETE FINISH "use CHAOS:FINISH-CONN")

(DEFUN CONN-FINISHED-P (CONN)
  "T unless connection is open but not all our transmissions have been acknowledged."
  (OR ( (WINDOW-AVAILABLE CONN) (FOREIGN-WINDOW-SIZE CONN))
      (NEQ (STATE CONN) 'OPEN-STATE)))
(DEFF FINISHED-P 'CONN-FINISHED-P)
(MAKE-OBSOLETE FINISHED-P "use CHAOS:CONN-FINISHED-P")

;;;; Input-Main Program level

(DEFUN GET-NEXT-PKT (CONN &OPTIONAL (NO-HANG-P NIL) (WHOSTATE "Chaosnet Input")
		     (CHECK-CONN-STATE (NOT NO-HANG-P))
		     &AUX PKT)
  "Return the next input packet from connection CONN.
The packet may contain data, or it may be a CLS, ANS or UNC.
If the next input packet is not are available,
 either wait or return NIL according to NO-HANG-P.
WHOSTATE is what to put in the who-line while we wait, if we wait.
CHECK-CONN-STATE non-NIL says get an error now if connection is in
 an invalid state.  Default is T unless NO-HANG-P.
When you are finished with the data in the packet, use RETURN-PKT
to allow the chaosnet ncp to reuse the packet."
  ;; Loop until we get a packet, decide not to hang, or error out
  (DO-FOREVER
    ;; Check for connection in an erroneous state
    (AND CHECK-CONN-STATE
	 (OR (MEMQ (STATE CONN) '(OPEN-STATE RFC-RECEIVED-STATE ANSWERED-STATE FOREIGN-STATE))
	     (IF (EQ (STATE CONN) 'CLS-RECEIVED-STATE)
		 (UNLESS (READ-PKTS CONN)
		   (FERROR 'SYS:CONNECTION-NO-MORE-DATA
			   "Attempt to receive from ~S,
a connection which has been closed by foreign host."
			   CONN))
	       (REPORT-BAD-CONNECTION-STATE CONN "receive from"))))
    ;; Now see if there are any packets we can have
    (WITHOUT-INTERRUPTS
      (SETQ PKT (READ-PKTS CONN))
      (COND (PKT				;Got packet, take off of read list
	     (AND ( UNC-OP (PKT-OPCODE PKT))
		  (SETF (PKT-NUM-READ CONN) (PKT-NUM PKT)))
	     (SETF (READ-PKTS CONN) (PKT-LINK PKT))
	     (COND ((NULL (READ-PKTS CONN))
		    (SETF (READ-PKTS-LAST CONN) NIL))))))
    (AND (NOT (NULL PKT))			;Got packet, acknowledge if necessary
	 (EQ (STATE CONN) 'OPEN-STATE)
	 ( (* 3 (PKTNUM-- (PKT-NUM PKT) (PKT-NUM-ACKED CONN))) (LOCAL-WINDOW-SIZE CONN))
	 (TRANSMIT-STS CONN 'WINDOW-FULL))
    (AND PKT					;Got packet, release from NCP
	 (RELEASE-PKT PKT))
    (AND (OR PKT NO-HANG-P) (RETURN PKT))	;If satisfied, return
    ;; Not satisfied, wait for something interesting to happen
    (PROCESS-WAIT WHOSTATE
		  #'(LAMBDA (X) (OR (READ-PKTS X)
				    (NOT (MEMQ (STATE X) '(OPEN-STATE FOREIGN-STATE)))))
		  CONN)))

(DEFPROP REPORT-BAD-CONNECTION-STATE T :ERROR-REPORTER)
(DEFUN REPORT-BAD-CONNECTION-STATE (CONN OPERATION-STRING)
  (COND ((EQ (STATE CONN) 'HOST-DOWN-STATE)
	 (FERROR 'SYS:HOST-STOPPED-RESPONDING
		 "Attempt to ~1@*~A ~0@*~S,
a connection whose foreign host died."
		 CONN OPERATION-STRING))
	((EQ (STATE CONN) 'LOS-RECEIVED-STATE)
	 (FERROR 'SYS:CONNECTION-LOST
		 "Attempt to ~2@*~A ~0@*~S,
which got a LOS: ~A"
		 CONN
		 (IF (READ-PKTS-LAST CONN)
		     (PKT-STRING (READ-PKTS-LAST CONN))
		   "??")
		 OPERATION-STRING))
	((EQ (STATE CONN) 'CLS-RECEIVED-STATE)
	 (FERROR 'SYS:CONNECTION-CLOSED
		 "Attempt to ~1@*~A ~0@*~S,
a connection which has been closed by foreign host."
		 CONN OPERATION-STRING))
	(T
	 (FERROR 'SYS:BAD-CONNECTION-STATE-1
		 "Attempt to ~2@*~A ~0@*~S,
which is in ~S, not a valid state"
		 CONN (STATE CONN) OPERATION-STRING))))

(DEFUN RETURN-PKT (PKT)
  "Tell the chaosnet ncp you are finished with packet PKT.
PKT should be a /"released/" packet, obtained with GET-PKT or GET-NEXT-PKT."
  (CASE (PKT-STATUS PKT)
    (RELEASED
     (SETF (PKT-STATUS PKT) NIL)
     (FREE-PKT PKT))
    (OTHERWISE
     (FERROR NIL "Attempt to return unreleased packet (~S) to the NCP." PKT))))

;;;; Receiver Interrupt level

;;; RECEIVER FUNCTIONS:  These run at receiver interrupt level.

;;; This function is the called on an INT-PKT which has just come in from the net.
;;; It is mostly a transfer vector to more specialized functions, but it also
;;; does error checking.
;;; Note: Functions reached from here must not, in any case, go blocked, particularily
;;;  now that the RECEIVER process is flushed.  A common case is to call functions 
;;;  which ordinarily could go blocked waiting for a INT-PKT, but this is prevented from
;;;  happening by setting up RESERVED-INT-PKT to the INT-PKT just received.
(DEFUN RECEIVE-INT-PKT (INT-PKT &AUX (OP (PKT-OPCODE INT-PKT)) CONN ACKN)
  (COND ((NOT (ZEROP (LDB #o0010 (AREF INT-PKT 0))))	;Header version must be zero
	 (FREE-INT-PKT INT-PKT))
	((= OP RUT-OP)
	 (DO ((I FIRST-DATA-WORD-IN-PKT (+ I 2))
	      (N (// (PKT-NBYTES INT-PKT) 4) (1- N))
	      (GATEWAY (PKT-SOURCE-ADDRESS INT-PKT))
	      (N-SUBNETS (ARRAY-LENGTH ROUTING-TABLE))
	      (SUBNET) (COST))
	     ((ZEROP N) (FREE-INT-PKT INT-PKT))
	   (SETQ SUBNET (AREF INT-PKT I) COST (AREF INT-PKT (1+ I)))
	   (WHEN (AND (< SUBNET N-SUBNETS)
		      ( COST (AREF ROUTING-TABLE-COST SUBNET))
		      (NULL (AREF ROUTING-TABLE-TYPE SUBNET)))
	     (SETF (AREF ROUTING-TABLE SUBNET) GATEWAY)
	     (SETF (AREF ROUTING-TABLE-COST SUBNET) COST))))
;;; RPK please check this
;;; Should this say PKT-DEST-ADDRESS instead of INT-PKT-HARDWARE-DEST?
	((AND (= OP BRD-OP) (ZEROP (INT-PKT-HARDWARE-DEST INT-PKT)))
	 (RECEIVE-BRD INT-PKT))
	(( (PKT-DEST-ADDRESS INT-PKT) MY-ADDRESS)	;Packet to be forwarded
	 (COND ((OR (= (PKT-FWD-COUNT INT-PKT) 17)
		    (> (PKT-NBYTES INT-PKT) MAX-DATA-BYTES-PER-PKT))
		(FREE-INT-PKT INT-PKT)
		(INCF PKTS-OVER-FORWARDED))
	       (T (INCF (PKT-FWD-COUNT INT-PKT))
		  (INCF PKTS-FORWARDED)
		  (TRANSMIT-INT-PKT INT-PKT))))
	(T (RECORD-INT-PKT-HEADER INT-PKT)
	   (AND (BIT-TEST #o200 OP) (INCF DATA-PKTS-IN))
	   (COND
	     ((= OP RFC-OP) (RECEIVE-RFC INT-PKT))
	     ((= OP LOS-OP) (RECEIVE-LOS INT-PKT))
	     ((= OP CLS-OP) (RECEIVE-CLS INT-PKT))
	     ((= OP MNT-OP) (FREE-INT-PKT INT-PKT))
	     ((AND (OR (NULL (SETQ CONN (PKT-DEST-CONN INT-PKT)))
		       ( (PKT-DEST-INDEX-NUM INT-PKT) (LOCAL-INDEX-NUM CONN))
		       ( (PKT-SOURCE-ADDRESS INT-PKT) (FOREIGN-ADDRESS CONN)))
		   (NOT (SETQ CONN (CDR (ASSQ (PKT-DEST-INDEX-NUM INT-PKT)
					      DISTINGUISHED-PORT-CONN-TABLE)))))
	      (TRANSMIT-LOS-INT-PKT INT-PKT LOS-OP
				    (IF CONN "You are not connected to this index"
				      "No such index exists")))
	     ((PROG2 (SETF (TIME-LAST-RECEIVED CONN) (TIME))
		     (= OP OPN-OP))
	      (RECEIVE-OPN CONN INT-PKT))
	     ((= OP FWD-OP) (RECEIVE-FWD CONN INT-PKT))
	     ((= OP ANS-OP) (RECEIVE-ANS CONN INT-PKT))
	     ((= OP UNC-OP) (RECEIVE-UNC CONN INT-PKT))
	     ((NOT (OR (= OP SNS-OP) (= OP STS-OP)
		       (= OP EOF-OP) ( OP DAT-OP)))
	      (TRANSMIT-LOS-INT-PKT INT-PKT LOS-OP "Illegal opcode"))
	     ((NOT (= (PKT-SOURCE-INDEX-NUM INT-PKT) (FOREIGN-INDEX-NUM CONN)))
	      (IF (= OP SNS-OP) (FREE-INT-PKT INT-PKT)	;Ignore SNS if not open
		(TRANSMIT-LOS-INT-PKT INT-PKT LOS-OP
				      "That is not your index number for this connection")))
	     ;; Below here can be SNS, STS, EOF, or DAT, all packets having ack fields.
	     ((NOT (EQ (STATE CONN) 'OPEN-STATE))
	      (IF (= OP SNS-OP) (FREE-INT-PKT INT-PKT)	;Ignore SNS if not open
		(TRANSMIT-LOS-INT-PKT INT-PKT LOS-OP "Connection not open")))
	     (T
	      ;; Below here, this INT-PKT contains a normal acknowledgement field.
	      (SETQ ACKN (PKT-ACK-NUM INT-PKT))	;Acknowledgement field
	      (RECEIPT CONN ACKN)		;Clear receipted packets from send list
	      (AND (PKTNUM-< (SEND-PKT-ACKED CONN) ACKN)
		   (SETF (SEND-PKT-ACKED CONN) ACKN))
	      (UPDATE-WINDOW-AVAILABLE CONN)
	      (COND ((OR (>= OP DAT-OP) (= OP EOF-OP))
		     (RECEIVE-EOF-OR-DAT CONN INT-PKT))
		    ((= OP SNS-OP) (RECEIVE-SNS CONN INT-PKT))
		    ((= OP STS-OP) (RECEIVE-STS CONN INT-PKT))))))))

(DEFUN RECORD-INT-PKT-HEADER (INT-PKT)
  (DO ((I 0 (1+ I))) ((= I 8.))
    (SETF (AREF RECENT-HEADERS RECENT-HEADERS-POINTER I) (AREF INT-PKT I)))
  (SETF (AREF RECENT-HEADERS RECENT-HEADERS-POINTER 8.) (TIME))
  (SETQ RECENT-HEADERS-POINTER (\ (1+ RECENT-HEADERS-POINTER) #o200)))

;;; Discard packets from send-list which have been receipted by other end
(DEFUN RECEIPT (CONN ACK-LEV)
 (WITHOUT-INTERRUPTS
   (LET ((SENDS (SEND-PKTS CONN))	;(Save array references...)
	 (NEXT NIL)			;Prevent weird screw.
	 (LENGTH (SEND-PKTS-LENGTH CONN)))
     (DO ((PKT SENDS NEXT))		;For each PKT not yet ACKed which this ACKs,
	 ((OR (NULL PKT) (PKTNUM-< ACK-LEV (PKT-NUM PKT))))
;      (SETQ NEXT (PKT-LINK PKT))
       (SETQ NEXT (SETQ SENDS (PKT-LINK PKT)))  ;Two variables only for "clairity"
       (FREE-PKT PKT)
       (SETQ LENGTH (1- LENGTH)))
     (SETF (SEND-PKTS CONN) SENDS)
     (SETF (SEND-PKTS-LENGTH CONN) LENGTH)
     (IF (NULL SENDS)
	 (SETF (SEND-PKTS-LAST CONN) NIL)))))

;;; A new ack has come in, so adjust the amount left in the window.  If the window was
;;; full, and has now become "un-full", cause an output interrupt
(DEFUN UPDATE-WINDOW-AVAILABLE (CONN &AUX (AVAILABLE (WINDOW-AVAILABLE CONN)))
  (SETF (WINDOW-AVAILABLE CONN)
	(MAX AVAILABLE			;in case rcvd out of order
	     (- (FOREIGN-WINDOW-SIZE CONN)
		(PKTNUM-- (PKT-NUM-SENT CONN) (SEND-PKT-ACKED CONN)))))
  (AND (ZEROP AVAILABLE) (NOT (ZEROP (WINDOW-AVAILABLE CONN)))
       (INTERRUPT-CONN :OUTPUT CONN)))

;;; The following functions are called to process the receipt of a particular kind of packet.

(DEFUN RECEIVE-STS (CONN INT-PKT)
  (RECEIPT CONN (PKT-FIRST-DATA-WORD INT-PKT))
  (SETF (FOREIGN-WINDOW-SIZE CONN) (PKT-SECOND-DATA-WORD INT-PKT))
  (UPDATE-WINDOW-AVAILABLE CONN)
  (FREE-INT-PKT INT-PKT))

;;; When this is called, CONN is known to be in OPEN-STATE.
(DEFUN RECEIVE-SNS (CONN INT-PKT)
  (SETQ RESERVED-INT-PKT INT-PKT)
  (TRANSMIT-STS CONN 'SNS))

;;; This uses the PKT-NUM to correctly order the PKTs.
;;;	If the PKT-NUM is less than or equal to the highest we received
;;;	     ignore it and send a receipt
;;;	If one higher then this one is added to the end of the successfully recieved PKTs.
;;;	     Then the out of sequence list is appended to the insequence list and the
;;;		point of break in sequence is found whereupon the list is broken
;;;		and all the appropriate pointers are set up.
;;;	If more than one larger try locating it's position in the out of order list
;;; When this is called, CONN is known to be in OPEN-STATE.
(DEFUN RECEIVE-EOF-OR-DAT (CONN INT-PKT &AUX PKT PKT-NUM PKTL-NUM PREV)
  (SETQ PKT-NUM (PKT-NUM INT-PKT))
  (COND ((NOT (PKTNUM-< (PKT-NUM-RECEIVED CONN) PKT-NUM))
	 (SETQ RESERVED-INT-PKT INT-PKT)
	 (SETQ PKTS-DUPLICATED (1+ PKTS-DUPLICATED))
	 (TRANSMIT-STS CONN '<-NUM-RCVD))	;This is a duplicate, receipt and ignore
	((= PKT-NUM (PKTNUM-1+ (PKT-NUM-RECEIVED CONN)))
	 ;; This is the one we were waiting for add it to READ-PKTS
	 (SETQ PKT (CONVERT-TO-PKT INT-PKT))
	 (AND (NULL (READ-PKTS CONN))
	      (INTERRUPT-CONN :INPUT CONN))
	 (WITHOUT-INTERRUPTS
	   (SETF (PKT-LINK PKT) (RECEIVED-PKTS CONN))	;Link the two lists together
	   (SETF (RECEIVED-PKTS CONN) NIL)
	   (COND ((NULL (READ-PKTS-LAST CONN))
		  (SETF (READ-PKTS CONN) PKT))
		 (T (SETF (PKT-LINK (READ-PKTS-LAST CONN)) PKT)))
	   (DO ((PKTL-NUM (PKT-NUM PKT)
			  (PKTNUM-1+ PKTL-NUM)))
	       ((OR (NULL PKT)
		    ( PKTL-NUM (PKT-NUM PKT)))
		(SETF (PKT-NUM-RECEIVED CONN) (PKTNUM-- PKTL-NUM 1))
		(SETF (RECEIVED-PKTS CONN) PKT)
		(AND PREV (SETF (PKT-LINK PREV) NIL))
		(SETF (READ-PKTS-LAST CONN) PREV))
	     (SETQ PREV PKT)
	     (SETQ PKT (PKT-LINK PKT)))))
	(T (WITHOUT-INTERRUPTS 
	     (DO ((PKTL (RECEIVED-PKTS CONN) (PKT-LINK PKTL))
		  (PREV NIL PKTL))
		 ((NULL PKTL)
		  (SETQ PKT (CONVERT-TO-PKT INT-PKT))
		  (COND ((NULL PREV) (SETF (RECEIVED-PKTS CONN) PKT))
			(T (SETF (PKT-LINK PREV) PKT)))
		  (SETF (PKT-LINK PKT) NIL))
	       (SETQ PKTL-NUM (PKT-NUM PKTL))
	       (COND ((= PKT-NUM PKTL-NUM)	;Same as existing one, forget about it.
		      (SETQ RESERVED-INT-PKT INT-PKT)
		      (TRANSMIT-STS CONN 'ALREADY-ON-RCVD-PKTS)	;Send a receipt
		      (RETURN NIL))
		     ((PKTNUM-< PKT-NUM PKTL-NUM)	;This is the place!
		      (SETQ PKT (CONVERT-TO-PKT INT-PKT))
		      (COND ((NULL PREV)
			     (SETF (PKT-LINK PKT) (RECEIVED-PKTS CONN))
			     (SETF (RECEIVED-PKTS CONN) PKT))
			    (T
			     (SETF (PKT-LINK PKT) (PKT-LINK PREV))
			     (SETF (PKT-LINK PREV) PKT)))
		      (RETURN NIL))))))))

(DEFUN RECEIVE-UNC (CONN INT-PKT &AUX PKT)
  (BLOCK NIL
    (COND ((EQ (STATE CONN) 'FOREIGN-STATE))	;Foreign-protocol state--no checks
	  ((NEQ (STATE CONN) 'OPEN-STATE)
	   (RETURN (TRANSMIT-LOS-INT-PKT INT-PKT LOS-OP "Connection not open")))
	  ((NOT (= (PKT-SOURCE-INDEX-NUM INT-PKT) (FOREIGN-INDEX-NUM CONN)))
	   (RETURN (TRANSMIT-LOS-INT-PKT INT-PKT LOS-OP
		     "That is not your index number for this connection"))))
    (COND (( (LOOP FOR X = (READ-PKTS CONN) THEN (PKT-LINK X)
		    WHILE X
		    COUNT T)
	      (LOCAL-WINDOW-SIZE CONN))
	   ;; There are more packets on the list than the window size.  Discard
	   ;; this packet.  This is so that we do not allocate infinite packet
	   ;; buffers if someone throws lots of UNC packets at us.
	   (FREE-INT-PKT INT-PKT))
	  (T
	   ;; Convert to regular packet, do INTERRUPT-CONN, and thread it on.
	   (SETQ PKT (CONVERT-TO-PKT INT-PKT))
	   (AND (NULL (READ-PKTS CONN))
		(INTERRUPT-CONN :INPUT CONN))
	   (WITHOUT-INTERRUPTS
	     (SETF (PKT-LINK PKT) (READ-PKTS CONN))
	     (SETF (READ-PKTS CONN) PKT)
	     (AND (NULL (READ-PKTS-LAST CONN))
		  (SETF (READ-PKTS-LAST CONN) PKT)))))))

;;; Random servers are not likely to work during the cold load, leave them turned off until
;;; the first disk save.
(DEFVAR CHAOS-SERVERS-ENABLED NIL "T enables RFCs to create server processes.")

(ADD-INITIALIZATION "Allow CHAOS servers" '(SETQ CHAOS-SERVERS-ENABLED T) '(:BEFORE-COLD))
(ADD-INITIALIZATION "Allow CHAOS BRD Reception"
		    '(SETQ *RECEIVE-BROADCAST-PACKETS-P* T) '(:BEFORE-COLD))

(DEFUN DUPLICATE-RFC-INT-PKT-P (INT-PKT &AUX CONN)
  (OR (DO ((TST-PKT PENDING-RFC-PKTS (PKT-LINK TST-PKT)))
	  ((NULL TST-PKT) NIL)
	(AND (= (PKT-SOURCE-ADDRESS INT-PKT) (PKT-SOURCE-ADDRESS TST-PKT))
	     (= (PKT-SOURCE-INDEX-NUM INT-PKT) (PKT-SOURCE-INDEX-NUM TST-PKT))
	     (RETURN T)))
      (DO ((I 1 (1+ I)))
	  (( I MAXIMUM-INDEX) NIL)
	(AND (SETQ CONN (AREF INDEX-CONN I))
	     (= (FOREIGN-ADDRESS CONN) (PKT-SOURCE-ADDRESS INT-PKT))
	     (= (FOREIGN-INDEX-NUM CONN) (PKT-SOURCE-INDEX-NUM INT-PKT))
	     (RETURN T)))))

;;; If RFC matches a pending LSN, call RFC-MEETS-LSN, else if there is a server,
;;; add to pending list and start up a server.
;;; (So far all we have done is verified PKT-DEST-ADDRESS.)
;;; Note that because of RFC-ANS stuff, the contact "name" is not the
;;; whole string, so we must do a simple parse.
(DEFUN RECEIVE-RFC (INT-PKT &AUX PKT)
  (IF (DUPLICATE-RFC-INT-PKT-P INT-PKT)
      (FREE-INT-PKT INT-PKT)
    (SETQ PKT (CONVERT-TO-PKT INT-PKT))
    (HANDLE-RFC-PKT PKT T)))

(DEFUN HANDLE-RFC-PKT (PKT CLS-ON-ERROR-P &AUX LSN SERVER CONTACT-NAME)
  "Handle an RFC packet.  If CLS-ON-ERROR-P is T, send a CLS if there's no server"
  (SETQ CONTACT-NAME (CONTACT-NAME-FROM-RFC PKT))
  (COND ((SETQ LSN (ASS #'EQUALP CONTACT-NAME PENDING-LISTENS))
	 (SETQ PENDING-LISTENS (DELQ LSN PENDING-LISTENS))
	 (RFC-MEETS-LSN (CDR LSN) PKT))
	((AND (OR (EQUALP CONTACT-NAME "STATUS") CHAOS-SERVERS-ENABLED)
	      (SETQ SERVER (ASS #'EQUALP CONTACT-NAME SERVER-ALIST)))
	 (WITHOUT-INTERRUPTS	;seems like a good idea, altho probably not necessary
	   (SETF (PKT-LINK PKT) PENDING-RFC-PKTS)
	   (SETQ PENDING-RFC-PKTS PKT))
	 ;; This assumes that the name is in the CAR of an init list entry
	 ;; was just EVAL
	 (BACKGROUND-TASK (SI:INIT-FORM SERVER)))
	(T (WHEN CLS-ON-ERROR-P
	     (TRANSMIT-LOS-INT-PKT (CONVERT-TO-INT-PKT PKT) CLS-OP
				   "No server for this contact name [LISPM]"))
	   (FREE-PKT PKT))))

(DEFUN CONTACT-NAME-FROM-RFC (PKT &AUX CONTACT-STRING TEM)
  (SETQ CONTACT-STRING (PKT-STRING PKT))
  (COND ((SETQ TEM (STRING-SEARCH-CHAR #o40 CONTACT-STRING))
	 (NSUBSTRING CONTACT-STRING 0 TEM))
	(T CONTACT-STRING)))

;;; Receving a BRD is like receiving an RFC
(DEFUN RECEIVE-BRD (INT-PKT &AUX BIT-MAP-LENGTH BYTE-IN-MAP PKT)
  (COND ((AND *RECEIVE-BROADCAST-PACKETS-P*
	      ;; Check the subnet bit map : length in bytes multiple of 4 ?
	      (ZEROP (MOD (SETQ BIT-MAP-LENGTH (PKT-ACK-NUM INT-PKT)) 4))
	      (> BIT-MAP-LENGTH (SETQ BYTE-IN-MAP (TRUNCATE MY-SUBNET 8)))) ; big enuf ?
	 ;; Massage so it looks like an RFC: Delete bit map, decrease byte count
	 (SETF (PKT-ACK-NUM INT-PKT) 0)
	 (INCF *BRD-PKTS-IN*)
	 (SETQ PKT (CONVERT-TO-PKT INT-PKT))
	 (SET-PKT-STRING PKT (SUBSTRING (PKT-STRING PKT) BIT-MAP-LENGTH))
	 (HANDLE-RFC-PKT PKT NIL))
	(T
	 (FREE-INT-PKT INT-PKT))))

;;; This is called when we have a LSN matching an RFC.  It can be called when we do
;;; a LSN (m.p. level) or when an RFC gets here (p.i. level).
;;; Here LISTEN has filled in some of the fields of the CONN, we must
;;; fill in the rest.
(DEFUN RFC-MEETS-LSN (CONN PKT)
  (SETF (FOREIGN-ADDRESS CONN) (PKT-SOURCE-ADDRESS PKT))
  (SETF (FOREIGN-INDEX-NUM CONN) (PKT-SOURCE-INDEX-NUM PKT))
  (SETF (FOREIGN-WINDOW-SIZE CONN) (PKT-ACK-NUM PKT))
  (SETF (PKT-NUM-READ CONN) (PKT-NUM PKT))
  (SETF (PKT-NUM-RECEIVED CONN) (PKT-NUM PKT))
  (SETF (PKT-NUM-ACKED CONN) (PKT-NUM PKT))
  (SETF (STATE CONN) 'RFC-RECEIVED-STATE)
  (SETF (READ-PKTS CONN) PKT)
  (SETF (READ-PKTS-LAST CONN) PKT)
  (SETF (PKT-LINK PKT) NIL)
  (INTERRUPT-CONN :CHANGE-OF-STATE CONN 'RFC-RECEIVED-STATE)
  (INTERRUPT-CONN :INPUT CONN))

;;; So far both host and both index numbers have been verified.
(DEFUN RECEIVE-OPN (CONN INT-PKT)
  (CASE (STATE CONN)
    (RFC-SENT-STATE (SETF (FOREIGN-INDEX-NUM CONN) (PKT-SOURCE-INDEX-NUM INT-PKT))
		    (SETF (FOREIGN-WINDOW-SIZE CONN) (PKT-SECOND-DATA-WORD INT-PKT))
		    (SETF (PKT-NUM-READ CONN) (PKT-NUM INT-PKT))
		    (SETF (PKT-NUM-RECEIVED CONN) (PKT-NUM INT-PKT))
		    (SETF (PKT-NUM-ACKED CONN) (PKT-NUM INT-PKT))
		    (SETF (TIME-LAST-RECEIVED CONN) (TIME))
		    (RECEIPT CONN (PKT-ACK-NUM INT-PKT))
		    (UPDATE-WINDOW-AVAILABLE CONN)
		    (SETF (STATE CONN) 'OPEN-STATE)
		    (SETQ RESERVED-INT-PKT INT-PKT)
		    (TRANSMIT-STS CONN 'OPN)
		    (INTERRUPT-CONN :CHANGE-OF-STATE CONN 'OPEN-STATE))
    (OPEN-STATE (COND ((AND (= (FOREIGN-ADDRESS CONN) (PKT-SOURCE-ADDRESS INT-PKT))
			    (= (FOREIGN-INDEX-NUM CONN)
			       (PKT-SOURCE-INDEX-NUM INT-PKT))
			    (= MY-ADDRESS (PKT-DEST-ADDRESS INT-PKT))
			    (= (LOCAL-INDEX-NUM CONN) (PKT-DEST-INDEX-NUM INT-PKT)))
		       (SETQ RESERVED-INT-PKT INT-PKT)
		       (TRANSMIT-STS CONN 'OPN))
		      (T (TRANSMIT-LOS-INT-PKT INT-PKT
					       LOS-OP
					       "You didn't open this connection"))))
    (OTHERWISE (TRANSMIT-LOS-INT-PKT INT-PKT LOS-OP "Bad state for OPN"))))

;;; We have received a CLS.  If the connection which he is closing is still open,
;;; put it in closed state, free up all pending SEND-PKTs, and put the CLS packet
;;; on the READ-PKTS list so that MP level can see it.
;;;      If the connection does not exist, this is NOT an error, because two
;;; CLSs might have passed each other.  So just free the PKT.
(DEFUN RECEIVE-CLS (INT-PKT &AUX PKT (INT-FLAG NIL))
  (LET ((CONN (PKT-DEST-CONN INT-PKT)))
    (COND ((NULL CONN)
	   (FREE-INT-PKT INT-PKT))
	  ((MEMQ (STATE CONN) '(OPEN-STATE RFC-SENT-STATE))
	   (SETQ PKT (CONVERT-TO-PKT INT-PKT))
	   (WITHOUT-INTERRUPTS
	     (FREE-ALL-SEND-PKTS CONN)
	     (FREE-ALL-RECEIVED-PKTS CONN)
	     (SETF (STATE CONN) 'CLS-RECEIVED-STATE)
	     (COND ((NULL (READ-PKTS-LAST CONN))
		    (SETF (READ-PKTS CONN) PKT)
		    (SETQ INT-FLAG T))
		   (T (SETF (PKT-LINK (READ-PKTS-LAST CONN)) PKT)))
	     (SETF (READ-PKTS-LAST CONN) PKT)
	     (SETF (PKT-LINK PKT) NIL))
	   (INTERRUPT-CONN :CHANGE-OF-STATE CONN 'CLS-RECEIVED-STATE)
	   (AND INT-FLAG (INTERRUPT-CONN :INPUT CONN)))
	  (T (TRANSMIT-LOS-INT-PKT INT-PKT
				   LOS-OP
				   "You sent a CLS to the wrong kind of connection.")))))

(DEFUN RECEIVE-LOS (INT-PKT &AUX (PKT (CONVERT-TO-PKT INT-PKT)) MY-INDEX CONN (INT-FLAG NIL))
  (SETQ MY-INDEX (LDB MAXIMUM-INDEX-LOG-2-MINUS-1 (PKT-DEST-INDEX-NUM PKT)))
  (COND ((AND (< MY-INDEX MAXIMUM-INDEX)
	      (SETQ CONN (AREF INDEX-CONN MY-INDEX))
	      (EQ (STATE CONN) 'OPEN-STATE)
	      (= (PKT-SOURCE-ADDRESS INT-PKT) (FOREIGN-ADDRESS CONN))
	      (= (PKT-SOURCE-INDEX-NUM INT-PKT) (FOREIGN-INDEX-NUM CONN)))
	 (WITHOUT-INTERRUPTS
	   (FREE-ALL-SEND-PKTS CONN)
	   (FREE-ALL-RECEIVED-PKTS CONN)
	   (SETF (STATE CONN) 'LOS-RECEIVED-STATE)
	   (COND ((NULL (READ-PKTS-LAST CONN))
		  (SETF (READ-PKTS CONN) PKT)
		  (SETQ INT-FLAG T))
		 (T (SETF (PKT-LINK (READ-PKTS-LAST CONN)) PKT)))
	   (SETF (READ-PKTS-LAST CONN) PKT)
	   (SETF (PKT-LINK PKT) NIL))
	 (INTERRUPT-CONN :CHANGE-OF-STATE CONN 'LOS-RECEIVED-STATE)
	 (AND INT-FLAG (INTERRUPT-CONN :INPUT CONN)))
	(T (SETF (PKT-LINK PKT) LOS-PKTS)
	   (SETQ LOS-PKTS PKT)
	   (SETQ CURRENT-LOS-PKT-COUNT (1+ CURRENT-LOS-PKT-COUNT)))))

(DEFUN RECEIVE-FWD (CONN INT-PKT &AUX PKT)
  (COND ((NEQ (STATE CONN) 'RFC-SENT-STATE)
	 (TRANSMIT-LOS-INT-PKT INT-PKT LOS-OP "An FWD was sent to a non-RFC-SENT index."))
	(T (SETQ PKT (CONVERT-TO-PKT INT-PKT))
	   (SETF (FOREIGN-ADDRESS CONN) (PKT-ACK-NUM PKT))
	   (SETF (PKT-OPCODE PKT) RFC-OP)
	   (TRANSMIT-NORMAL-PKT CONN PKT (PKT-NUM-SENT CONN) (LOCAL-WINDOW-SIZE CONN)))))

(DEFUN RECEIVE-ANS (CONN INT-PKT &AUX PKT)
  (COND ((NOT (MEMQ (STATE CONN) '(RFC-SENT-STATE BROADCAST-SENT-STATE)))
	 (FREE-INT-PKT INT-PKT))
	(T (SETQ PKT (CONVERT-TO-PKT INT-PKT))
	   (SETF (STATE CONN) 'ANSWERED-STATE)
	   (SETF (READ-PKTS CONN) PKT)
	   (SETF (PKT-LINK PKT) NIL)
	   (INTERRUPT-CONN :CHANGE-OF-STATE CONN 'ANSWERED-STATE)
	   (INTERRUPT-CONN :INPUT CONN))))

;;;; Timed Responses and background tasks

(DEFUN BACKGROUND (&AUX LAST-WAKEUP-TIME (LAST-PROBE-TIME (TIME)) TASKS TIME)
  (RESET-ROUTING-TABLE)
  (DO-FOREVER
    (SETQ TIME (TIME))
    (SETQ LAST-WAKEUP-TIME TIME)
    (DO () ((OR ( (TIME-DIFFERENCE TIME LAST-WAKEUP-TIME) RETRANSMISSION-INTERVAL)
		( (TIME-DIFFERENCE TIME LAST-PROBE-TIME) PROBE-INTERVAL)))
      (PROCESS-WAIT "Background Task"
		    #'(LAMBDA (LAST-WAKEUP-TIME LAST-PROBE-TIME &AUX (TIME (TIME)))
			(OR ( (TIME-DIFFERENCE TIME LAST-PROBE-TIME) PROBE-INTERVAL)
			    (AND RETRANSMISSION-NEEDED
				 ( (TIME-DIFFERENCE TIME LAST-WAKEUP-TIME)
				    RETRANSMISSION-INTERVAL))
			    BACKGROUND-REQUESTS))
		    LAST-WAKEUP-TIME LAST-PROBE-TIME)
      (WITHOUT-INTERRUPTS
	(SETQ TASKS (NREVERSE BACKGROUND-REQUESTS))
	(SETQ BACKGROUND-REQUESTS NIL))
      (DO () ((NULL TASKS))
	(EVAL (CAR TASKS))
	(SETQ TASKS (CDR TASKS)))
      (SETQ TIME (TIME)))
    (COND (RETRANSMISSION-NEEDED
	   (SETQ RETRANSMISSION-NEEDED NIL
		 MORE-RETRANSMISSION-NEEDED NIL)
	   (MAPC #'RETRANSMISSION CONN-LIST)	;Retransmit on all connections
	   (WITHOUT-INTERRUPTS
	     (SETQ RETRANSMISSION-NEEDED
		   (OR RETRANSMISSION-NEEDED MORE-RETRANSMISSION-NEEDED)))))
    (WHEN ( (TIME-DIFFERENCE TIME LAST-PROBE-TIME) PROBE-INTERVAL)
      (SETQ LAST-PROBE-TIME TIME)
      (DOTIMES (I (ARRAY-LENGTH ROUTING-TABLE-COST))
	(UNLESS (AREF ROUTING-TABLE-TYPE I)
	  ;; If we have a direct connection of known type,
	  ;; don't do the processing for indirect links.
	  (SETF (AREF ROUTING-TABLE-COST I) (MIN (+ (AREF ROUTING-TABLE-COST I) 2) #o1000))))
      (MAPC #'PROBE-CONN CONN-LIST))))		;Do probes and timeouts

;;; Retransmit all unreceipted packets not recently sent
(DEFUN RETRANSMISSION (CONN &AUX TIME (INHIBIT-SCHEDULING-FLAG T))
  (WHEN (MEMQ (STATE CONN) '(OPEN-STATE RFC-SENT-STATE))
    ;; Only if it is open or awaiting a response from RFC
    (BLOCK CONN-DONE
      (DO-FOREVER
	;; Doing this outside the loop can lose
	;; because then TIME can be less than (PKT-TIME-TRANSMITTED PKT).
	(SETQ TIME (TIME))
	(LET ((INHIBIT-SCHEDULING-FLAG T))
	  (DO ((PKT (SEND-PKTS CONN) (PKT-LINK PKT)))
	      ((NULL PKT) (RETURN-FROM CONN-DONE NIL))
	    (COND ((NOT (EQ CONN (PKT-SOURCE-CONN PKT)))
		   (FERROR NIL "~S in SEND-PKTS list for incorrect CONN:
CONN ~S, (PKT-SOURCE-CONN PKT) ~S." PKT CONN (PKT-SOURCE-CONN PKT))))
	    (SETQ MORE-RETRANSMISSION-NEEDED T)
	    (WHEN ( (TIME-DIFFERENCE TIME (PKT-TIME-TRANSMITTED PKT))
		     (LSH (CONN-RETRANSMISSION-INTERVAL CONN)
			  ;; Retransmit the lowest numbered packet most often
			  (MAX 0 (MIN 5 (1- (%POINTER-DIFFERENCE (PKT-NUM PKT)
								 (SEND-PKT-ACKED CONN)))))))
	      (SETF (PKT-BEING-RETRANSMITTED PKT) T)
	      (SETQ INHIBIT-SCHEDULING-FLAG NIL)
	      (TRANSMIT-PKT PKT T)
	      (INCF PKTS-RETRANSMITTED)
	      (SETQ INHIBIT-SCHEDULING-FLAG T)
	      (COND ((EQ (PKT-BEING-RETRANSMITTED PKT) 'FREE)
		     (SETF (PKT-BEING-RETRANSMITTED PKT) NIL)
		     (FREE-PKT PKT))
		    (T (SETF (PKT-BEING-RETRANSMITTED PKT) NIL)))
	      (RETURN NIL)))))		;Must always start from beginning of chain if
					; turned on scheduling, since chain could be invalid
      (PROCESS-ALLOW-SCHEDULE))))

;;; Send a SNS on this conn if necessary.  Decide whether foreign host is down.
;;; This gets called every PROBE-INTERVAL.
(DEFUN PROBE-CONN (CONN &AUX DELTA-TIME)
  (WHEN (MEMQ (STATE CONN) '(OPEN-STATE RFC-SENT-STATE))
    ;Only if it is open or awaiting a response from RFC
    (SETQ DELTA-TIME (TIME-DIFFERENCE (TIME) (TIME-LAST-RECEIVED CONN)))
    (COND ((> DELTA-TIME HOST-DOWN-INTERVAL)
	   (WITHOUT-INTERRUPTS
	     (FREE-ALL-SEND-PKTS CONN)
	     (FREE-ALL-RECEIVED-PKTS CONN)
	     (SETF (STATE CONN) 'HOST-DOWN-STATE))
	   (INTERRUPT-CONN :CHANGE-OF-STATE CONN 'HOST-DOWN-STATE))
	  ((AND (EQ (STATE CONN) 'OPEN-STATE)	;Send SNS only on open connections
		(OR (< (WINDOW-AVAILABLE CONN) (FOREIGN-WINDOW-SIZE CONN))
		    (> DELTA-TIME LONG-PROBE-INTERVAL)))
	   (LET ((PKT (ALLOCATE-INT-PKT)))
	     (SETF (PKT-OPCODE PKT) SNS-OP)
	     (SETF (PKT-NBYTES PKT) 0)
	     (TRANSMIT-INT-PKT-FOR-CONN CONN PKT))))))

;;;; Hardware Interface

(DEFUN INTERFACE-RESET-AND-ENABLE ()
  (SI:SELECT-PROCESSOR
    (:CADR
     (%UNIBUS-WRITE CONTROL-STATUS-REGISTER
		    (DPB -1 %%CHAOS-CSR-RESET 0))
     (%UNIBUS-WRITE CONTROL-STATUS-REGISTER
		    (DPB -1 %%CHAOS-CSR-INTERRUPT-ENABLES 0)))
    (:LAMBDA
      NIL)))

(DEFUN INTERFACE-RESET ()
  (SI:SELECT-PROCESSOR
    (:CADR
     (%UNIBUS-WRITE CONTROL-STATUS-REGISTER
		    (DPB -1 %%CHAOS-CSR-RESET 0)))
    (:LAMBDA
      NIL)))

(DEFUN RECEIVER-RESET ()
  (SI:SELECT-PROCESSOR
    (:CADR
     (%UNIBUS-WRITE CONTROL-STATUS-REGISTER
		    (DPB 1 %%CHAOS-CSR-RECEIVER-CLEAR
			 (%UNIBUS-READ CONTROL-STATUS-REGISTER))))
    (:LAMBDA
      NIL)))

;;; Top level function for receiver to be called directly from scheduler. (Instead of the
;;; old thing where something like this was the top level of the RECEIVER process.)
(DEFUN RECEIVE-ANY-FUNCTION (&AUX INT-PKT)
  (DO ((RESERVED-INT-PKT NIL))
      ((NOT (AND ENABLE (OR FAKE-RECEIVE-LIST (INT-RECEIVE-LIST)))))
    (WHEN (SETQ INT-PKT (RECEIVE-PROCESS-NEXT-INT-PKT))
      ;; WITHOUT-INTERRUPTS not necc since from scheduler.
      (RECEIVE-INT-PKT INT-PKT))
    (WHEN RESERVED-INT-PKT
      (FERROR NIL "Int PKT about to be lost!")))	;Hopefully this will get printed
  (SI:SET-PROCESS-WAIT CURRENT-PROCESS
		       #'(LAMBDA () (AND ENABLE (OR FAKE-RECEIVE-LIST (INT-RECEIVE-LIST))))
		       NIL)
  (SETF (SI:PROCESS-WAIT-WHOSTATE CURRENT-PROCESS) "Chaos Packet"))

;;; Returns NIL if there was a CRC error, INT-PKT if win.
(DEFUN RECEIVE-PROCESS-NEXT-INT-PKT ()
  (PROG (INT-PKT BITS DEST)
	(IF FAKE-RECEIVE-LIST
	    (WITHOUT-INTERRUPTS
	      (SETQ INT-PKT FAKE-RECEIVE-LIST
		    FAKE-RECEIVE-LIST (INT-PKT-THREAD FAKE-RECEIVE-LIST))
	      (SETF (INT-PKT-BIT-COUNT INT-PKT)
		    (* #o20 (+ (PKT-NWORDS INT-PKT) 3)))
	      (SETF (INT-PKT-THREAD INT-PKT) NIL)
	      (RETURN INT-PKT))
	  (DO-FOREVER
	    (LET ((OLD-RECEIVE-LIST (INT-RECEIVE-LIST)))
	      (WHEN (%STORE-CONDITIONAL INT-RECEIVE-LIST-POINTER OLD-RECEIVE-LIST
					(INT-PKT-THREAD OLD-RECEIVE-LIST))
		(RETURN (SETQ INT-PKT OLD-RECEIVE-LIST))))))
	(SETF (INT-PKT-THREAD INT-PKT) NIL)
	(WHEN (< (INT-PKT-WORD-COUNT INT-PKT) (+ FIRST-DATA-WORD-IN-PKT 3))
	  ;; Less than the minimum size that can exist in the current protocol?
	  (SETQ PKTS-OTHER-DISCARDED (1+ PKTS-OTHER-DISCARDED))
	  (FREE-INT-PKT INT-PKT)
	  (RETURN NIL))
	(SETQ PKTS-RECEIVED (1+ PKTS-RECEIVED))
	(SETQ DEST (INT-PKT-HARDWARE-DEST INT-PKT)
	      BITS (INT-PKT-BIT-COUNT INT-PKT)
	      PKTS-LOST (+ (LDB %%CHAOS-CSR-LOST-COUNT (INT-PKT-CSR-2 INT-PKT))
			   PKTS-LOST))
	(COND ((OR (< BITS 48.)
		   (BIT-TEST 17 BITS)
		   (AND (ZEROP (LOGAND #o377 (AREF INT-PKT 0)))	;Header version 0
			( (TRUNCATE BITS #o20) (+ (PKT-NWORDS INT-PKT) 3))))
	       (SETQ PKTS-BAD-BIT-COUNT (1+ PKTS-BAD-BIT-COUNT))
	       (FREE-INT-PKT INT-PKT))
	      ((LDB-TEST %%CHAOS-CSR-CRC-ERROR (INT-PKT-CSR-1 INT-PKT))
	       (SETQ PKTS-BAD-CRC-1 (1+ PKTS-BAD-CRC-1))
	       (FREE-INT-PKT INT-PKT))
	      ((LDB-TEST %%CHAOS-CSR-CRC-ERROR (INT-PKT-CSR-2 INT-PKT))
	       (SETQ PKTS-BAD-CRC-2 (1+ PKTS-BAD-CRC-2))
	       (FREE-INT-PKT INT-PKT))
	      ((AND ( DEST 0) ( DEST MY-ADDRESS))
	       (SETQ PKTS-BAD-DEST (1+ PKTS-BAD-DEST))
	       (FREE-INT-PKT INT-PKT))
	      (T (RETURN INT-PKT))) ))

;;; This is called by anyone with an INT-PKT.  It looks at the
;;; destination field in the INT-PKT and sends it somewhere.
;;; This does not mess with links in any way.
;;; The host and subnet can be passed as optional arguments, so that
;;; this function can be used for debugging purposes.

(DEFUN TRANSMIT-INT-PKT (INT-PKT &OPTIONAL (HOST (PKT-DEST-ADDRESS INT-PKT))
                                           (SUBNET (PKT-DEST-SUBNET INT-PKT))
				 &AUX HARDWARE-P LOCAL-PROC OTHER-LOCAL-PROCS)
  ;;; Simple routing if he is not on my subnet.
  (COND ((AND (NOT (= SUBNET MY-SUBNET))
	      (NOT (MEMQ SUBNET MY-OTHER-SUBNETS)))
	 (AND ( SUBNET (LENGTH ROUTING-TABLE))
	      (SETQ SUBNET 0))
	 (SETQ HOST (AREF ROUTING-TABLE SUBNET))))
  (IF ( (LDB #o1010 HOST) (LENGTH ROUTING-TABLE))
      (FERROR NIL "bad routing table"))
  (SETF (INT-PKT-WORD-COUNT INT-PKT) (1+ (PKT-NWORDS INT-PKT)))
  (SETF (AREF INT-PKT (1- (INT-PKT-WORD-COUNT INT-PKT))) HOST)
  (OR (= (%AREA-NUMBER INT-PKT) CHAOS-BUFFER-AREA)
      (FERROR NIL "Attempt to transmit non-interrupt packet ~A." INT-PKT))
  (AND (BIT-TEST #o200 (PKT-OPCODE INT-PKT)) (SETQ DATA-PKTS-OUT (1+ DATA-PKTS-OUT)))
  (COND ((ZEROP HOST)
	 ;; This means we know no path to the destination.
	 ;; Just give up.
	 (FREE-INT-PKT INT-PKT))
	((= HOST MY-ADDRESS)
	 ;; loop back to myself ... system 98+ handles this a different way
	 (LET ((N-16-BIT-WORDS (+ (CEILING (+ (CHAOS:PKT-NBYTES INT-PKT) 16.) 2) 3)))
	   (SETF (INT-PKT-WORD-COUNT INT-PKT) (1+ N-16-BIT-WORDS))
	   (SETF (INT-PKT-CSR-1 INT-PKT) 0)	; say no CRC-1 error
	   (SETF (INT-PKT-CSR-2 INT-PKT) 0)	; say no CRC-2 error
	   (SETF (INT-PKT-BIT-COUNT INT-PKT)
		 (* (- N-16-BIT-WORDS 3) #o20))	; fill in bit count
	   ;; set the hardware destination
	   (SETF (AREF INT-PKT (- (INT-PKT-WORD-COUNT INT-PKT) 3)) MY-ADDRESS)
	   (WITHOUT-INTERRUPTS
	     (RECEIVE-INT-PKT INT-PKT))))
	(T
	 (ECASE (AREF ROUTING-TABLE-TYPE (LDB #o1010 HOST))
	   (:ETHERNET
	    (COND ((AND (FBOUNDP 'SI:SHARE-MODE-ACTIVE-P)
			(SI:SHARE-MODE-ACTIVE-P))
		   (COND
		     ;; broadcast -- send to everyone
		     ((ZEROP HOST)
		      (SETQ OTHER-LOCAL-PROCS SI:*OTHER-PROCESSORS*)
		      (SETQ HARDWARE-P (EQ SI:*ETHERNET-HARDWARE-CONTROLLER* SI:*MY-OP*)))

		     ;; if he's local, just send to him
		     ((SETQ LOCAL-PROC (UNIX:PROCESSOR-FOR-HOST-IF-ON-MY-NUBUS HOST)))

		     ;; it's definitely going out of this machine - give it to
		     ;; the hardware controller
		     ((EQ SI:*ETHERNET-HARDWARE-CONTROLLER* SI:*MY-OP*)
		      (SETQ HARDWARE-P T))
		     (T
		      (SETQ LOCAL-PROC SI:*ETHERNET-HARDWARE-CONTROLLER*))))
		  (T
		   (SETQ HARDWARE-P T)))

	    (COND ((NOT (NULL HARDWARE-P))
		   (LET ((ETHER-ADDRESS (ETHERNET:GET-ETHERNET-ADDRESS HOST)))
		     (COND ((NOT (NULL ETHER-ADDRESS))
			    (FUNCALL (SI:SELECT-PROCESSOR
				       (:CADR
					 'ETHERNET:SEND-INT-PKT-VIA-UNIBUS-ETHERNET)
				       (:LAMBDA
					 'ETHERNET:SEND-INT-PKT-VIA-MULTIBUS-ETHERNET))
				     INT-PKT
				     ETHERNET:MY-ETHERNET-ADDRESS	;source
				     ETHER-ADDRESS			;destination
				     ETHERNET:CHAOS-ETHERNET-TYPE)
			    (INCF ETHERNET:*ETHERNET-CHAOS-PKTS-TRANSMITTED*)
			    (INCF PKTS-TRANSMITTED))
			   (T
			    (INCF ETHERNET:*ETHERNET-CHAOS-PKTS-NOT-TRANSMITTED-LACKING-ETHERNET-ADDRESS*))))))

	    (DOLIST (OP OTHER-LOCAL-PROCS)
	      (UNIX:TRANSMIT-INT-PKT-TO-SHARING-HOST INT-PKT OP))

	    (IF LOCAL-PROC
		(UNIX:TRANSMIT-INT-PKT-TO-SHARING-HOST INT-PKT LOCAL-PROC))

	    (FREE-INT-PKT INT-PKT))
	   (:CHAOS
	    (SI:SELECT-PROCESSOR
	      (:LAMBDA (FERROR NIL "Trying to use chaosnet hardware")))
	    (WITHOUT-INTERRUPTS
	      (PROG (OLD-TRANSMIT-LIST)
		    (SETQ PKTS-TRANSMITTED (1+ PKTS-TRANSMITTED))
		 LOOP
		    (SETQ OLD-TRANSMIT-LIST (INT-TRANSMIT-LIST))
		    (SETF (INT-PKT-THREAD INT-PKT) OLD-TRANSMIT-LIST)
		    (OR (%STORE-CONDITIONAL INT-TRANSMIT-LIST-POINTER
					    OLD-TRANSMIT-LIST
					    INT-PKT)
			(GO LOOP))
		    (%CHAOS-WAKEUP))))))))


;(DEFUN TRANSMIT-INT-PKT (INT-PKT &OPTIONAL (HOST (PKT-DEST-ADDRESS INT-PKT))
;                                           (SUBNET (PKT-DEST-SUBNET INT-PKT))
;				 &AUX HARDWARE-P LOCAL-PROC OTHER-LOCAL-PROCS)
;    ;;; Simple routing if he is not on my subnet.
;    (UNLESS (= SUBNET MY-SUBNET)
;      (IF ( SUBNET (ARRAY-LENGTH ROUTING-TABLE))
;	  (SETQ SUBNET 0))
;      (SETQ HOST (AREF ROUTING-TABLE SUBNET)))
;    (SETF (INT-PKT-WORD-COUNT INT-PKT) (1+ (PKT-NWORDS INT-PKT)))
;    (ASET HOST INT-PKT (1- (INT-PKT-WORD-COUNT INT-PKT)))
;    (OR (= (%AREA-NUMBER INT-PKT) CHAOS-BUFFER-AREA)
;        (FERROR NIL "Attempt to transmit non-interrupt packet ~A." INT-PKT))
;    (if (BIT-TEST #o200 (PKT-OPCODE INT-PKT)) (incf DATA-PKTS-OUT))
;    (WITHOUT-INTERRUPTS
;     (PROG (OLD-TRANSMIT-LIST)
;	   (INCF PKTS-TRANSMITTED)
;	   (WHEN (= HOST MY-ADDRESS)
;	     ;; Handle "transmission" to this very machine -- just pretend pkt was received.
;	     (SETF (INT-PKT-THREAD INT-PKT) FAKE-RECEIVE-LIST)
;	     (INCF (INT-PKT-WORD-COUNT INT-PKT) 2)
;	     (SETF (INT-PKT-HARDWARE-DEST INT-PKT) MY-ADDRESS)
;	     (SETQ FAKE-RECEIVE-LIST INT-PKT)
;	     (RETURN))
;	LOOP
;	   (SETQ OLD-TRANSMIT-LIST (INT-TRANSMIT-LIST))
;           (SETF (INT-PKT-THREAD INT-PKT) OLD-TRANSMIT-LIST)
;           (OR (%STORE-CONDITIONAL INT-TRANSMIT-LIST-POINTER OLD-TRANSMIT-LIST INT-PKT)
;               (GO LOOP))
;           (%CHAOS-WAKEUP))))
;)

;;; DEBUGGING: The following are functions for printing out information, 
;;; principally for debugging.

(DEFUN STATUS ( &AUX CSR LC)
  "Print out contents of hardware registers (CADR Only)"
  (SI:SELECT-PROCESSOR
    (:LAMBDA (FERROR NIL "LAMBDAs don't have chaosnet boards")))
  (SETQ CSR (%UNIBUS-READ CONTROL-STATUS-REGISTER))
  (TERPRI) (TERPRI)
  (AND (LDB-TEST %%CHAOS-CSR-TIMER-INTERRUPT-ENABLE CSR)
       (FORMAT T "Timer interrupt enable or maybe transmit busy.~%"))
  (AND (LDB-TEST %%CHAOS-CSR-LOOP-BACK CSR)
       (FORMAT T "Loopback.~%"))
  (AND (LDB-TEST %%CHAOS-CSR-RECEIVE-ALL CSR)
       (FORMAT T "Receive all messages mode is on.~%"))
  (AND (LDB-TEST %%CHAOS-CSR-RECEIVE-ENABLE CSR)
       (FORMAT T "Receiver interrupt enabled.~%"))
  (AND (LDB-TEST %%CHAOS-CSR-TRANSMIT-ENABLE CSR)
       (FORMAT T "Transmit interrupt enabled.~%"))
  (AND (LDB-TEST %%CHAOS-CSR-TRANSMIT-ABORT CSR)
       (FORMAT T "Transmit aborted by collision.~%"))
  (AND (LDB-TEST %%CHAOS-CSR-TRANSMIT-DONE CSR)
       (FORMAT T "Transmit done.~%"))
  (OR  (ZEROP (SETQ LC (LDB %%CHAOS-CSR-LOST-COUNT CSR)))
       (FORMAT T "Lost count = ~O~%" LC))
  (AND (LDB-TEST %%CHAOS-CSR-RESET CSR)
       (FORMAT T "I//O reset.~%"))
  (AND (LDB-TEST %%CHAOS-CSR-CRC-ERROR CSR)
       (FORMAT T "-- CRC ERROR!!! --~%"))
  (AND (LDB-TEST %%CHAOS-CSR-RECEIVE-DONE CSR)
       (FORMAT T "Receive done.~%"))
  (FORMAT T "Bit count: ~O~%" (%UNIBUS-READ BIT-COUNT-REGISTER))
  NIL)

;;;; KLUDGES and assorted random functions

(DEFUN ASSURE-ENABLED ()
  "Make sure the chaosnet NCP is operating.
User programs may call this before attempting to use the chaosnet."
  (OR ENABLE (ENABLE)))

(DEFUN ENABLE ()
  (SEND BACKGROUND :REVOKE-RUN-REASON)
  (SEND RECEIVER :REVOKE-RUN-REASON)
  (INTERFACE-RESET-AND-ENABLE)
  (SEND BACKGROUND :PRESET 'BACKGROUND)
  (SEND BACKGROUND :RUN-REASON)
  (SEND RECEIVER :PRESET 'RECEIVE-ANY-FUNCTION)
  (SEND RECEIVER :RUN-REASON)
  (SETQ ENABLE T))

(DEFUN DISABLE ()
  (SETQ ENABLE NIL)
  (SEND RECEIVER :REVOKE-RUN-REASON)
  (SEND BACKGROUND :REVOKE-RUN-REASON)
  (INTERFACE-RESET))

(DEFUN RESET (&OPTIONAL ENABLE-P)
  "Turn off and reinitialize the chaosnet software.
This may unwedge it if it is not working properly.
This will cause all of your currently open connections to lose.
You must call CHAOS:ENABLE to turn the chaosnet ncp on again
before you can use the chaosnet; but many user-level functions
that use the net will do that for you.  
Calling this function with ENABLE-P of T will have the same effect."
  (DISABLE)
  (WITHOUT-INTERRUPTS
    (SETQ BACKGROUND-REQUESTS NIL)		;Get rid of requests for connections flushing
    (SETQ RETRANSMISSION-NEEDED T)
    (DO ((CL CONN-LIST (CDR CL)))
	((NULL CL))
      (FREE-ALL-READ-PKTS (CAR CL))
      (FREE-ALL-RECEIVED-PKTS (CAR CL))
      (FREE-ALL-SEND-PKTS (CAR CL))
      (SETF (STATE (CAR CL)) 'INACTIVE-STATE))
    (DO ((I 1 (1+ I)))
	((= I MAXIMUM-INDEX))
      (SETF (AREF INDEX-CONN I) NIL))
    (SETQ DISTINGUISHED-PORT-CONN-TABLE NIL)
    (SETQ CONN-LIST NIL)
    (OR (AND (INTEGERP INDEX-CONN-FREE-POINTER)
	     (> MAXIMUM-INDEX INDEX-CONN-FREE-POINTER -1))
	(SETQ INDEX-CONN-FREE-POINTER 1))

    ;; The initialization is needed because if the LISP Machine has an open connection,
    ;; it gets reloaded, and the connection is established on the same index before the
    ;; other end has gone into INCXMT state, then the RFC will look like a duplicate.
    ;; Though this may sound like a rare event, it is exactly what happens with the
    ;; file job connection!!
    (DO ((INDEX 0 (1+ INDEX)))
	(( INDEX MAXIMUM-INDEX))
      (SETF (AREF UNIQUIZER-TABLE INDEX) (+ (TIME) INDEX)))

    ;; Should actually try and free up these
    (SETQ PENDING-LISTENS NIL)
    (SETQ PENDING-RFC-PKTS NIL)
    (SETQ FAKE-RECEIVE-LIST NIL)
    (SETQ *BRD-PKTS-IN* 0
	  *BRD-PKTS-OUT* 0
	  *BRD-HISTORY* NIL
	  *BRD-REPLIES-IN* 0
	  *RECEIVE-BROADCAST-PACKETS-P* NIL)
    ;; This is a pretty arbitrary number, but it used to be MAXIMUM-INDEX which
    ;; grew like mad causing an absurd number of pages to get wired.  This is undoubtedly
    ;; enough for average use.
    (CREATE-CHAOSNET-BUFFERS 40.) )
  (IF ENABLE-P
      (PROGN (ENABLE)
	     "Reset and enabled")
    "Reset and disabled"))

(ADD-INITIALIZATION "Turn off chaosnet" '(RESET) '(BEFORE-COLD))

(DEFUN PKT-ADD-32 (PKT COUNT)
  (LET ((IDX (+ FIRST-DATA-WORD-IN-PKT (TRUNCATE (PKT-NBYTES PKT) 2))))
    (SETF (AREF PKT IDX) (LDB #o0020 COUNT))
    (SETF (AREF PKT (1+ IDX)) (LDB #o2020 COUNT))
    (SETF (PKT-NBYTES PKT) (+ (PKT-NBYTES PKT) 4))))

(DEFUN SEND-STATUS (&AUX CONN PKT STRING)
  (SETQ CONN (LISTEN "STATUS"))
  (SETQ PKT (GET-PKT))
  (SET-PKT-STRING PKT (HOST-DATA MY-ADDRESS))
  (DO I (ARRAY-ACTIVE-LENGTH (SETQ STRING (PKT-STRING PKT))) (1+ I) ( I 32.)
    (ARRAY-PUSH STRING 0))
  (SETF (PKT-NBYTES PKT) 32.)
  (PKT-ADD-32 PKT (DPB 16. #o2020 (+ (LDB 1010 MY-ADDRESS) 400)))
  (PKT-ADD-32 PKT PKTS-RECEIVED)
  (PKT-ADD-32 PKT PKTS-TRANSMITTED)
  (PKT-ADD-32 PKT (READ-METER '%COUNT-CHAOS-TRANSMIT-ABORTS))
  (PKT-ADD-32 PKT PKTS-LOST)
  (PKT-ADD-32 PKT PKTS-BAD-CRC-1)
  (PKT-ADD-32 PKT PKTS-BAD-CRC-2)
  (PKT-ADD-32 PKT PKTS-BAD-BIT-COUNT)
  (PKT-ADD-32 PKT PKTS-OTHER-DISCARDED)
  (ANSWER CONN PKT))

(ADD-INITIALIZATION "STATUS" '(SEND-STATUS) NIL 'SERVER-ALIST)

;;; For now, doesn't worry about changing number of buffers.  If called
;;; more than once, will discard all old buffers.  You better not try to
;;; increase the number of buffers, though.
(DEFUN CREATE-CHAOSNET-BUFFERS (N-BUFFERS)
  (COND ((NOT (BOUNDP 'CHAOS-BUFFER-AREA))
	 (MAKE-AREA :NAME 'CHAOS-BUFFER-AREA
		    :SIZE (* (CEILING (* N-BUFFERS
					 (+ 3 ;Leader header, leader length, array header
					    128.     ;Max 32-bit wds in pkt incl hardware wds
					    (LENGTH CHAOS-BUFFER-LEADER-QS)))
				      PAGE-SIZE)
			     PAGE-SIZE)
		    :GC :TEMPORARY))
	(T (RESET-TEMPORARY-AREA CHAOS-BUFFER-AREA)))
  (SETQ RESERVED-INT-PKT NIL)
  (DO ((PREV NIL BUF)
       (BUF)
       (COUNT N-BUFFERS (1- COUNT)))
      ((ZEROP COUNT)
       (SI:WIRE-AREA CHAOS-BUFFER-AREA T)
       (STORE (SYSTEM-COMMUNICATION-AREA %SYS-COM-CHAOS-FREE-LIST) BUF)
       (STORE (SYSTEM-COMMUNICATION-AREA %SYS-COM-CHAOS-TRANSMIT-LIST) NIL)
       (STORE (SYSTEM-COMMUNICATION-AREA %SYS-COM-CHAOS-RECEIVE-LIST) NIL))
    (SETQ BUF (MAKE-ARRAY 256. :TYPE 'ART-16B :AREA CHAOS-BUFFER-AREA
			       :LEADER-LENGTH (LENGTH CHAOS-BUFFER-LEADER-QS)))
    (STORE-ARRAY-LEADER 0 BUF %CHAOS-LEADER-WORD-COUNT)
    (STORE-ARRAY-LEADER PREV BUF %CHAOS-LEADER-THREAD)))

(DEFUN PRINT-INT-PKT (INT-PKT)
  (DO ((I 0 (1+ I)))
      (( I  (INT-PKT-WORD-COUNT INT-PKT)))
    (FORMAT T "~%Word ~O, data ~O" I (AREF INT-PKT I))))

(DEFUN PRINT-INT-PKT-STATUS (&OPTIONAL PRINT-ALL)
  (FORMAT T "~%Free list ~d, transmit-list ~d, receive-list ~d"
	  (INT-PKT-LIST-LENGTH (SYSTEM-COMMUNICATION-AREA %SYS-COM-CHAOS-FREE-LIST))
	  (INT-PKT-LIST-LENGTH (SYSTEM-COMMUNICATION-AREA %SYS-COM-CHAOS-TRANSMIT-LIST))
	  (INT-PKT-LIST-LENGTH (SYSTEM-COMMUNICATION-AREA %SYS-COM-CHAOS-RECEIVE-LIST)))
  (WHEN PRINT-ALL
    (LET* ((REGION (SYS:AREA-REGION-LIST CHAOS-BUFFER-AREA))
	   (RO (SYS:REGION-ORIGIN REGION))
	   (RFP (SYS:REGION-FREE-POINTER REGION)))
      (DO ((Q-OFFSET 0 (+ Q-OFFSET (+ 3 128. (LENGTH CHAOS-BUFFER-LEADER-QS)))))
	  ((>= Q-OFFSET RFP))
	(LET ((PKT (%MAKE-POINTER DTP-ARRAY-POINTER
				  (+ RO Q-OFFSET (+ 2 (LENGTH CHAOS-BUFFER-LEADER-QS))))))
	  (IF (INT-PKT-LIST-MEMQ PKT (SYSTEM-COMMUNICATION-AREA %SYS-COM-CHAOS-FREE-LIST))
	      (FORMAT T "~%Following pkt on free list!"))
	  (PRINT-PKT PKT NIL T)
	  (COND ((MEMQ (PKT-OPCODE PKT)
		       '(#,RFC-OP #,OPN-OP #,CLS-OP #,ANS-OP))
		 (DOTIMES (C (MIN 100. (CEILING (PKT-NBYTES PKT) 2)))
		   (LET ((B (AREF PKT (+ C FIRST-DATA-WORD-IN-PKT))))
		     (TYO (LOGAND B 377))
		     (TYO (LSH B -8))))))
	  ))))
  )

(DEFUN INT-PKT-LIST-LENGTH (HEAD)
  (WITHOUT-INTERRUPTS
    (DO ((C 0 (1+ C))
	 (PKT HEAD (INT-PKT-THREAD PKT)))
	((NULL PKT) C))))

(DEFUN INT-PKT-LIST-MEMQ (ITEM INT-PKT-LIST)
  (WITHOUT-INTERRUPTS
    (DO ((PKT INT-PKT-LIST (INT-PKT-THREAD PKT)))
	((NULL PKT))
      (IF (EQ PKT ITEM) (RETURN T)))))

;;; routing packet transmitter

(DEFVAR RUT-TRANSMITTER-PROCESS NIL)

(DEFUN START-RUT-TRANSMITTER-PROCESS ()
  (IF (NULL RUT-TRANSMITTER-PROCESS)
      (SETQ RUT-TRANSMITTER-PROCESS
	    (MAKE-PROCESS "Chaos RUT transmitter" :WARM-BOOT-ACTION NIL :PRIORITY 25.)))
  (COND ((NULL MY-OTHER-SUBNETS)
	 (PROCESS-DISABLE RUT-TRANSMITTER-PROCESS))
	(T
	 (GLOBAL:SEND RUT-TRANSMITTER-PROCESS :PRESET 'RUT-TRANSMITTER-TOP-LEVEL)
	 (PROCESS-RESET-AND-ENABLE RUT-TRANSMITTER-PROCESS))))

(DEFVAR *NUMBER-OF-ROUTING-PACKETS* 0)

(DEFUN RUT-TRANSMITTER-TOP-LEVEL ()
  (LET ((SUBNET-LIST (CONS MY-SUBNET MY-OTHER-SUBNETS))
	(ADDRESS-LIST (CONS MY-ADDRESS MY-OTHER-ADDRESSES)))
    (DO-FOREVER
      (DO ((SUB SUBNET-LIST (CDR SUB))
	   (ADDR ADDRESS-LIST (CDR ADDR))
	   (INT-PKT (ALLOCATE-INT-PKT) (ALLOCATE-INT-PKT)))
	  ((NULL SUB) (FREE-INT-PKT INT-PKT))
	(DO ((SUBNET 1 (1+ SUBNET))
	     (I FIRST-DATA-WORD-IN-PKT)
	     (N 0))
	    ((= SUBNET (ARRAY-LENGTH ROUTING-TABLE))
	     (SETF (PKT-NBYTES INT-PKT) (* N 4)))
	  (WHEN (< (AREF ROUTING-TABLE-COST SUBNET) MAXIMUM-ROUTING-COST)
	    (SETF (AREF INT-PKT I) SUBNET)
	    (SETF (AREF INT-PKT (1+ I)) (AREF ROUTING-TABLE-COST SUBNET))
	    (INCF I 2)
	    (INCF N 1)))
	(SETF (PKT-OPCODE INT-PKT) RUT-OP)
	(SETF (PKT-SOURCE-ADDRESS INT-PKT) (CAR ADDR))
	(SETF (PKT-SOURCE-INDEX-NUM INT-PKT) 0)
	(SETF (PKT-DEST-ADDRESS INT-PKT) 0)
	(SETF (PKT-DEST-INDEX-NUM INT-PKT) 0)
	(TRANSMIT-INT-PKT INT-PKT 0 (CAR SUB))	; frees int-pkt
	(INCF *NUMBER-OF-ROUTING-PACKETS*))
      (PROCESS-SLEEP (* 60. 10.)))))

(ADD-INITIALIZATION "CHAOS-NCP" '(INITIALIZE-NCP-ONCE) '(ONCE))
(ADD-INITIALIZATION "CHAOS-NCP" '(INITIALIZE-NCP-COLD) '(COLD))
(ADD-INITIALIZATION "CHAOS-NCP"
                    '(INITIALIZE-NCP-SYSTEM)
                    '(SYSTEM NORMAL))   ;NORMAL keyword to override FIRST default
