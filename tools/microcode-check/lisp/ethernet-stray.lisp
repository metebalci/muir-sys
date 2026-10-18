;;; -*- Mode:LISP; Package:USER; Base:10; Lowercase:T -*-

;;; Revision 16's Ethernet device interrupt taken as a stray
;;; (tools/microcode-check/README.md, cases-16/ethernet-stray.cases; QUUX's
;;; Ethernet contract, sections 2.6 and 10).  Word 100 <8> is up while word
;;; 240's <8>, the interrupt enable, is on and an Ethernet frame waits (251
;;; not equal to 252): a level.  The microcode (INTR-ETHERNET-DEVICE,
;;; sys/ucadr/uc-interrupt.lisp) writes 240 back with <8> clear and <0> as it
;;; was, asks for a sequence break, and dismisses the interrupt; the network
;;; process sets <8> again before each wait (section 2.6's fallback; until it,
;;; the bit was a stray, the same write without the break).  Microcode without
;;; the write dismisses it untouched, and the level interrupts again at once,
;;; for ever.  It wants a band without the network, whose process would take
;;; the device's frames itself.
;;;
;;; ETS-SETUP points the device at one wired page: the receive ring's one
;;; entry at its word 0, the transmit ring's at word 8, and a buffer of 1,536
;;; bytes at word 64.  The peer, tools/microcode-check/ethernet-peer, sends a
;;; broadcast ARP request every 20 ms; the device discards them until it has a
;;; buffer.  The registers are read and written through the register page's
;;; window, as region-area-map-interrupt.lisp does.

(defvar *ets-rqb* nil "The wired page: the two rings' entries and the buffer.")
(defvar *ets-page* nil "Its physical word address.")
(defconst ets-buffer-word 64 "The buffer's place in the page, on a line.")
(defconst ets-buffer-bytes 1536)

(defun ets-loc (w) (%make-pointer dtp-locative (si:%make-pointer-unsigned (+ #o35777777400 w))))
(defun ets-reg (w) (%p-ldb (byte 24 0) (ets-loc w)))
(defun ets-bit (w b) (ldb (byte 1 b) (ets-reg w)))
(defun ets-set (w v) (%p-dpb v (byte 32 0) (ets-loc w)))

;; a word of the page, as two halves of the rqb's art-16b view, as
;; sys: io; fdev writes its rings
(defun ets-store (word value)
  (let ((b (si:rqb-buffer *ets-rqb*)))
    (setf (aref b (* 2 word)) (logand value #o177777))
    (setf (aref b (1+ (* 2 word))) (logand (ash value -16) #o177777))))
(defun ets-fetch (word)
  (let ((b (si:rqb-buffer *ets-rqb*)))
    (+ (aref b (* 2 word)) (ash (aref b (1+ (* 2 word))) 16))))

(defun ets-present ()
  "Feature word 15: 7 on revision 16, its <2> the Ethernet device."
  (ets-reg #o15))

(defun ets-setup ()
  "Disable, wire the page, write the rings and enable, interrupt enable off.
Returns 240, then 241's <0> enabled, <1> quiet and <2> refused."
  (ets-set #o240 0)
  (or *ets-rqb* (setq *ets-rqb* (si:get-disk-rqb 1)))
  (si:wire-disk-rqb *ets-rqb* 1 t t)
  (setq *ets-page* (si:file-device-rqb-page-address *ets-rqb* 0))
  (dotimes (w 16) (ets-store w 0))
  (ets-store 0 (+ *ets-page* ets-buffer-word))
  (ets-store 1 ets-buffer-bytes)
  (ets-set #o246 *ets-page*)
  (ets-set #o247 0)
  (ets-set #o242 (+ *ets-page* 8))
  (ets-set #o243 0)
  (ets-set #o240 1)
  (list (ets-reg #o240) (ets-bit #o241 0) (ets-bit #o241 1) (ets-bit #o241 2)))

(defun ets-state ()
  "240, 241 <8> (an Ethernet frame waiting), word 100 <8>, 251 and 252."
  (list (ets-reg #o240) (ets-bit #o241 8) (ets-bit #o100 8)
	(ldb (byte 16 0) (ets-reg #o251)) (ldb (byte 16 0) (ets-reg #o252))))

(defun ets-wait-frame (consumer)
  "Wait up to 60 s of the machine's time for 251 to reach CONSUMER; then ETS-STATE."
  (let ((start (time)))
    (do () ((or (= (ldb (byte 16 0) (ets-reg #o251)) consumer)
		(> (time-difference (time) start) 3600)))
      (process-sleep 1)))
  (ets-state))

(defun ets-give (producer)
  "Buffers given up to PRODUCER (250); then wait for the Ethernet frame."
  (ets-set #o250 producer)
  (ets-wait-frame producer))

(defun ets-frame-length ()
  "The receive entry's word 2, the Ethernet frame's length, and the buffer's
first word: the destination's bytes 0-3, broadcast."
  (list (ets-fetch 2) (ets-fetch ets-buffer-word)))

(defun ets-interrupt-enable ()
  "Set 240 <8> with the device enabled, wait a tick, and return ETS-STATE."
  (ets-set #o240 #o401)
  (process-sleep 1)
  (ets-state))

(defun ets-take (taken)
  "Take the filled entries back up to TAKEN (252); then ETS-STATE."
  (ets-set #o252 taken)
  (ets-state))

(defun ets-cleanup ()
  "Disable, and give the page back.  Returns 240 and 241 <1>, quiet."
  (ets-set #o240 0)
  (when *ets-rqb*
    (si:unwire-disk-rqb *ets-rqb*)
    (si:return-disk-rqb *ets-rqb*)
    (setq *ets-rqb* nil))
  (list (ets-reg #o240) (ets-bit #o241 1)))
