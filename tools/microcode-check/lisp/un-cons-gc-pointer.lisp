;;; -*- Mode:LISP; Package:USER; Base:10; Lowercase:T -*-

;;; The check un-cons-gc-pointer (tools/microcode-check/README.md,
;;; cases/un-cons-gc-pointer.cases).  A bignum sum with no carry gives its
;;; last word back through UN-CONS, which lowers the region's free pointer
;;; and backs the scavenger's pointer, REGION-GC-POINTER, up to it when it
;;; lies above.  Both are relative to the region's origin.  The sums are
;;; consed in an area of their own, UN-CONS-AREA, through SI:NUMBER-CONS-AREA.

(defvar un-cons-area (make-area :name 'un-cons-area :representation :structure))

(defvar *un-cons-big* (expt 2 40.))

(defun un-cons-region ()
  "The region of UN-CONS-AREA that the sums are consed in."
  (let ((si:number-cons-area un-cons-area))
    (%region-number (+ *un-cons-big* 1))))

(defun un-cons-sum (&optional planted-gc-pointer)
  "Cons (+ *UN-CONS-BIG* 1) in UN-CONS-AREA, its last word given back.  With
PLANTED-GC-POINTER, the region's gc pointer is set that many words above its
free pointer first, as when the scavenger has passed words that UN-CONS then
gives back.  A list: the words the free pointer moved, the free pointer and
the gc pointer after, all relative to the region's origin, and the region's
length.  The gc pointer is set back to the free pointer after."
  (let* ((region (un-cons-region))
	 (free-before (si:region-free-pointer region)))
    (setf (si:region-gc-pointer region)
	  (+ free-before (or planted-gc-pointer 0)))
    (let ((si:number-cons-area un-cons-area))
      (+ *un-cons-big* 1))
    (let ((free (si:region-free-pointer region))
	  (gc (si:region-gc-pointer region)))
      (setf (si:region-gc-pointer region) free)
      (list (- free free-before) free gc (si:region-length region)))))

(defun un-cons-gc-pointer-ok (&optional planted-gc-pointer)
  "T if after UN-CONS-SUM the gc pointer is within the region's length and
not above the free pointer."
  (let ((r (un-cons-sum planted-gc-pointer)))
    (and (< (third r) (fourth r)) (<= (third r) (second r)))))
