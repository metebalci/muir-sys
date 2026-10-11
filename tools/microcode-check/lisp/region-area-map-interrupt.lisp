;;; -*- Mode:LISP; Package:USER; Base:10; Lowercase:T -*-

;;; Region-to-area's table and the interrupts its walk can take
;;; (tools/microcode-check/README.md, cases/region-area-map-interrupt.cases).
;;; REGION-TO-AREA (sys/ucadr/uc-page-fault.lisp) keeps each region's area in
;;; a byte of A memory, A-REGION-AREA-MAP; a byte that says not yet known
;;; (377) makes it walk the region's list thread and keep what it finds.  The
;;; walk held the region number in A-TEM1 across its reads, where an
;;; interrupt can be taken, and the tick's TRACK-MOUSE sets A-TEM1 to 4 times
;;; the mouse's delta, 0 at rest: the area went into region 0's byte.  At the
;;; tick's 60 Hz that was rare (generational-tuning's gt-check found it now
;;; and then); RGM-STORM runs timer 0, the tick, at a period of tens of
;;; microseconds while it forgets every byte and looks every region up again,
;;; and then gives the tick back its 16,667.
;;;
;;; A memory and the register page are read and written through their
;;; windows.  A-REGION-AREA-MAP's place is found as the run of A memory words
;;; whose bytes, for every region in use, say not yet known or that region's
;;; area, at least 20 of them known.

(defvar *rgm-map* nil "A-REGION-AREA-MAP's place in A memory.")

(defun rgm-a-loc (k) (%make-pointer dtp-locative (si:%make-pointer-unsigned (+ #o35700000000 k))))
(defun rgm-reg-loc (k) (%make-pointer dtp-locative (si:%make-pointer-unsigned (+ #o35777777400 k))))
(defun rgm-byte-at (map r)
  (%p-ldb (byte 8 (* 8 (mod r 4))) (rgm-a-loc (+ map (floor r 4)))))
(defun rgm-byte (r) (rgm-byte-at *rgm-map* r))

(defun rgm-mouse-tracking ()
  "T if the tick tracks the mouse (MOUSE-CURSOR-STATE, A memory's, not 0), as it
must for TRACK-MOUSE to reach its A-TEM1."
  (not (zerop si::mouse-cursor-state)))

(defun rgm-walk (r)
  (do ((x (si:region-list-thread r) (si:region-list-thread x))) ((minusp x) (logand x 255))))

(defun rgm-in-use-p (r)
  (not (or (= (ldb si:%%region-space-type (si:region-bits r)) si:%region-space-free)
	   (zerop (si:region-length r)))))

(defun rgm-find-map ()
  "Find A-REGION-AREA-MAP, every region in use looked up first so that its
byte is known: (found)."
  (let ((areas nil))
    (dotimes (r si:size-of-area-arrays)
      (when (rgm-in-use-p r)
	(%area-number (%make-pointer dtp-locative (si:region-origin r)))
	(push (cons r (rgm-walk r)) areas)))
    (setq *rgm-map*
	  (dotimes (k (- #o2000 (ceiling si:size-of-area-arrays 4)))
	    (let ((known 0))
	      (when (dolist (e areas t)
		      (let ((b (rgm-byte-at k (car e))))
			(cond ((= b 255))
			      ((= b (cdr e)) (incf known))
			      (t (return nil)))))
		(when (>= known 20) (return k))))))
    (list (not (null *rgm-map*)))))

(defun rgm-bad ()
  "The regions in use whose byte holds another area's number: ((r byte area) ...)."
  (let ((bad nil))
    (dotimes (r si:size-of-area-arrays)
      (when (rgm-in-use-p r)
	(let ((b (rgm-byte r)) (a (rgm-walk r)))
	  (unless (or (= b 255) (= b a)) (push (list r b a) bad)))))
    bad))

(defun rgm-storm (period)
  "Timer 0 at PERIOD microseconds while every byte is forgotten (377) and every
region in use looked up again (%AREA-NUMBER, the walk), then the tick's 16,667
again: RGM-BAD after."
  (let ((loc (rgm-reg-loc #o111)))
    ;; without-interrupts: the clock's sequence breaks, every 6 ticks, would
    ;; keep the scheduler running at such a tick and starve the walk on micro
    (without-interrupts
     (unwind-protect
	(progn
	  (%p-dpb period (byte 24 0) loc)
	  (dotimes (w (ceiling si:size-of-area-arrays 4))
	    (%p-dpb -1 (byte 32 0) (rgm-a-loc (+ *rgm-map* w))))
	  (dotimes (r si:size-of-area-arrays)
	    (when (rgm-in-use-p r)
	      (%area-number (%make-pointer dtp-locative (si:region-origin r))))))
      (%p-dpb 16667 (byte 24 0) loc))))
  (rgm-bad))
