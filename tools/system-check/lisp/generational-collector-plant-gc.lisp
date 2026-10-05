;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:10; Readtable:ZL -*-
;;; Planted partial fixes for the check generational-collector (contract G3
;;; step 2, section 12: "a partial fix fails"), the collector's own.  Given
;;; after lisp/generational-collector.lisp in --files, each replaces a
;;; function of the tree with the fix left out, and the cases named must fail:
;;; - the promotion table without the soft cap: the second promotion-table
;;;   case (56, not 8) and C11 (survivor space 2, 3, not tenured, 0);
;;; - GC-RESET-FREE-POINTER as before step 2, writing no first-object table
;;;   entry when it moves up: C6 (b);
;;; - FILL-UP-REGION as before step 2, the same: C6 (c);
;;; - the incremental save refused after any flip: C20.
;;; Not for any band in use.

(defun gc-promotion-table (tenure-all)
  (if tenure-all
      0
    (logior (lsh %region-generation-survivor-1 (* 2 %region-generation-eden))
	    (lsh %region-generation-survivor-2 (* 2 %region-generation-survivor-1)))))

(defun gc-reset-free-pointer (region newfp &optional ignore-if-downward-flag object-start)
  object-start
  (or inhibit-scheduling-flag
      (ferror nil "This function must be called with scheduling inhibited"))
  (let ((oldfp (region-free-pointer region)))
    (cond ((or (< oldfp newfp)
	       (not ignore-if-downward-flag))
	   (store (region-free-pointer region) newfp)
	   (cond ((> (region-gc-pointer region) oldfp)
		  (ferror nil "The free pointer of region ~S is screwed" region))
		 ((or (= (region-gc-pointer region) oldfp)
		      (not (< (region-gc-pointer region) newfp)))
		  (store (region-gc-pointer region) newfp)))
	   (%gc-scav-reset region)
	   (%gc-cons-work (- newfp oldfp))))))

(defun fill-up-region (region)
  (without-interrupts
    (let ((free-pointer (region-free-pointer region))
	  (origin (region-origin region))
	  (size (region-length region))
	  (bits (region-bits region)))
      (unless (= size free-pointer)
	(cond ((= (%logldb %%region-representation-type bits)
		  %region-representation-type-list)
	       (%p-store-contents-offset nil origin free-pointer)
	       (%p-dpb-offset cdr-nil %%q-cdr-code origin free-pointer)
	       (unless (= size (1+ free-pointer))
		 (%blt (%pointer-plus origin free-pointer)
		       (%pointer-plus origin (1+ free-pointer))
		       (- size free-pointer 1) 1)))
	      (t
	       (do ((i free-pointer (1+ i)))
		   ((= (\ i page-size) 0))
		 (%blt fill-up-region-array (%pointer-plus origin i) 1 1))
	       (do ((i (* (ceiling free-pointer page-size) page-size)
		       (+ i page-size)))
		   ((= i size))
		 (%blt fill-up-region-array (%pointer-plus origin i) 1 1)
		 (%p-dpb-offset (1- page-size) %%array-index-length-if-short origin i))))
	(setf (region-free-pointer region) size)))))

(defun gc-tenured-flip-since-p (generation)
  (not (= generation %gc-generation-number)))
