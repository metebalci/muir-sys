;;; -*- Mode:LISP; Package:USER; Base:10; Lowercase:T -*-

;;; The network's interrupt, word 100 <6>, taken as a stray
;;; (tools/microcode-check/README.md, cases-15/network-stray.cases; QUUX's
;;; Ethernet contract, section 8, step R3).  Word 100 <6> is the Chaosnet
;;; interface's request, up while its CSR, word 140, has Receive Done and the
;;; receive interrupt enable (<4>), or Transmit Done (<7>, up while the
;;; transmitter is idle) and the transmit interrupt enable (<5>): a level.
;;; With the NCP gone from the band nothing sets those enables, but the
;;; microcode still runs on revision 15, which has the interface (step R4 took
;;; it from revision 16, where the check is skipped: cases-15/); its
;;; stray (INTR-NETWORK-STRAY, sys/ucadr/uc-interrupt.lisp) writes the CSR 0,
;;; which turns both enables off and drops the level, and dismisses the
;;; interrupt.  Microcode without it dismisses the interrupt untouched, and the
;;; level interrupts again at once, for ever.  It wants a band without the
;;; NCP, whose own handler took the interrupt.  The registers are read and
;;; written through the register page's window, as ethernet-stray.lisp does.

(defun nts-loc (w) (%make-pointer dtp-locative (si:%make-pointer-unsigned (+ #o35777777400 w))))
(defun nts-reg (w) (%p-ldb (byte 16 0) (nts-loc w)))
(defun nts-set (w v) (%p-dpb v (byte 16 0) (nts-loc w)))

(defun nts-state ()
  "(the CSR's interrupt enables <5:4>, its Transmit Done <7>, word 100 <6>)"
  (let ((csr (nts-reg #o140)))
    (list (ldb (byte 2 4) csr) (ldb (byte 1 7) csr) (ldb (byte 1 6) (nts-reg #o100)))))

(defun nts-enable (enables)
  "Write the CSR with ENABLES (<5:4>, as a CSR value) and nothing else, wait a tick,
and return NTS-STATE."
  (nts-set #o140 enables)
  (process-sleep 1)
  (nts-state))
