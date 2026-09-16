;;; -*- Mode:LISP; Package:ETHERNET; Base:8 -*-

; Advertised functions:
;
; receive-addr-pkt         - given a art-16b array; update address resolution tables
; get-ethernet-address     - given a chaos address return the ethernet address,
;                            or nil, if it is not available, or not available now.
;
; functions that need to be called:
;
; allocate-some-kind-of-packet
; send-the-packet-somehow-with-ether-type-x608

; internal function
;
; send-addr-pkt           - given a chaos address, ether send a request packet, or
;                           with optional arguments, reply to a request

; plus several helpers ...



; address resolution packet looks like:

; from SECONDS by Gill Pratt - for PDP11's

#|

#define CHAOS_TYPE 0x0408 /* chaos */
#define ADDR_TYPE 0x0608 /* address resolution */

/* address resolution data format */

struct ar {
    short ar_hardware;  /* hardware type */
    short ar_protocol;  /* protocol-id - same as packet type */
    u_char ar_hlength;  /*hardware address length = 6 for ethernet  */
    u_char ar_plength /* protocol address length = 2 for chaosnet */
    short ar_opcode;  /* address resolution op-code */
    u_char ar_esender[6]; /* ethernet sender address */
    int ar_csender; /* chaos sender address */
    u_char ar_etarget[6];
    int ar_ctarget; /* target chaos address */
};

#define AR_ETHERNET (1<<8) /* only legit value for ar_hardware */

#define AR_REQUEST (1<<8) /* possible values for ar_opcode */
#define AR_REPLY (2<<8)

|#

;** temp
(if (not (boundp 'chaos:my-other-addresses))
    (setq chaos:my-other-addresses nil))

; resolved address cache
; elements are (chaos-address ether-address age)


(defvar ether-address-translations nil)

(add-initialization "forget address translations" '(setq ether-address-translations nil)
		    '(system))

(defun get-ethernet-address (chaos-address)

  (declare (special chaos:my-other-addresses)) ; ** temp
  (cond ((zerop chaos-address)
	 -1)
	((or (= chaos-address chaos:my-address)
	     (member chaos-address chaos:my-other-addresses))
	 my-ethernet-address)
	(t
	 (let ((address-info (assoc chaos-address ether-address-translations)))
	   (cond ((null address-info)
		  (send-addr-pkt chaos-address chaos:my-address)
		  nil)
		 (t
		  (cadr address-info)))))))

(defun send-addr-pkt (dest-chaos-address source-chaos-address &optional his-ether)

  ;don't send addr res packets to subnet 6, except for cadr2
  ;this will be fixed correctly when the new routing stuff is done
  (COND ((AND (NOT (= DEST-CHAOS-ADDRESS 3140)) (= (LDB 1010 DEST-CHAOS-ADDRESS) 6))
	 NIL)
	(T
	 (let ((pkt (chaos:allocate-int-pkt nil)))
	   (cond ((not (null pkt))
		  (make-addr-pkt pkt
				 dest-chaos-address
				 source-chaos-address
				 (if his-ether 2_8. 1_8.)
				 (or his-ether 0))
		  (select si:processor-type-code
		    (si:lambda-type-code
		     (send-int-pkt-via-multibus-ethernet
		       pkt my-ethernet-address (or his-ether -1) #x608 12.))
		    (si:cadr-type-code
		     (send-int-pkt-via-unibus-ethernet
		       pkt my-ethernet-address (or his-ether -1) #x608 12.)))
		  (chaos:free-int-pkt pkt)))))))

(defun receive-addr-pkt (array)			;art-16b
  (let ((target-chaos-address (aref array 13)))
    (cond ((or (= target-chaos-address chaos:my-address)
	       (and (= chaos:my-address 3140) (= target-chaos-address 3540)) ; cadr2's hack
	       (and (fboundp 'unix:processor-for-host-if-on-my-nubus)
		    (unix:processor-for-host-if-on-my-nubus target-chaos-address)))
	   (without-interrupts
	     (let ((address-info (assoc (aref array 7) ether-address-translations)))
	       (cond ((null address-info)
		      (push (list (aref array 7)
				  (get-address-from-array array 4)
				  1000)
			    ether-address-translations))
		     (t
		      (rplaca (cdr address-info) (get-address-from-array array 4))
		      (rplaca (cddr address-info) 1000)))))
	   (cond ((= (aref array 3) 1_8.)
		  (send-addr-pkt (aref array 7)
				 (aref array 13)
				 (get-address-from-array array 4))))))))

(defun make-addr-pkt (array dest-chaos-address source-chaos-address
		      &optional (opcode 1_8.) (his-ether 0))
		;array is art-16b
  (aset 1_8. array 0)				;ar_hardware
  (aset #x408 array 1)				;ar_protocol = CHAOS
  (aset (logior 6 2_8.) array 2)		;ar_hlength & ar_plength
  (aset opcode array 3)				;ar_opcode
  (put-address-to-array my-ethernet-address array 4)	;ar_esender in slots 4, 5, and 6
  (aset source-chaos-address array 7)		;ar_csender
  (put-address-to-array his-ether array 10)	;ar-etarget
  (aset dest-chaos-address array 13))

(defun print-addr-pkt (array)
  (format t "~&ar_hardware (should be 400 or 1000) ~O" (aref array 0))
  (format t "~&ar_protocol (should be 2010) ~O" (aref array 1))
  (format t "~&ar_hlength & ar_plength (should be 1006) ~O" (aref array 2))
  (format t "~&ar_opcode (should be 400-request or 1000-reply) ~O" (aref array 3))
  (format t "~&ar_esender ")
  (print-address-from-array-in-hex array 4)
  (format t "~&ar_csender ~O" (aref array 7))
  (format t "~&ar_etarget ")
  (print-address-from-array-in-hex array 10)
  (format t "~&ar_ctarget ~O" (aref array 13)))

(defun print-address-from-array-in-hex (array place)
  (format t "~16r " (ldb 0010 (aref array place)))
  (format t "~16r " (ldb 1010 (aref array place)))
  (format t "~16r " (ldb 0010 (aref array (+ place 1))))
  (format t "~16r " (ldb 1010 (aref array (+ place 1))))
  (format t "~16r " (ldb 0010 (aref array (+ place 2))))
  (format t "~16r " (ldb 1010 (aref array (+ place 2)))))

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

