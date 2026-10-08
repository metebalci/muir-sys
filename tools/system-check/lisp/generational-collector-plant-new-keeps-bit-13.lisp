;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:8; Readtable:ZL -*-
;;; A planted partial fix for the check generational-reclaim (C30; contract G3
;;; step 2, clarification 16): GC-RECLAIM-OLDSPACE-AREA frees an area's only
;;; region when it is old and makes a new one from the area's bits with bit
;;; 13 (%%REGION-EPHEMERAL) left set, so an ephemeral area's new region lies
;;; in ephemeral space.  Given after lisp/generational-collector.lisp in
;;; --files: C30 (b) and (c) must fail (bit 13 set, not below ephemeral
;;; space).  Not for any band in use.

(defun gc-reclaim-oldspace-area (area)
  (check-arg area (and (numberp area) (<= 0 area) (< area size-of-area-arrays)) "an area number")
  (without-interrupts
    (or %gc-flip-ready
	(ferror nil "You cannot reclaim oldspace now, there may be pointers to it"))
    (do ((region (area-region-list area) (region-list-thread region))
	 (region-to-free)
	 (prev-region nil region))
	(())
     nextloop
      (and (minusp region) (return nil))
      (and (= (ldb %%region-space-type (region-bits region)) %region-space-old)
	   (cond ((or prev-region (not (minusp (region-list-thread region))))
		  (setq region-to-free region
			region (region-list-thread region))
		  (if prev-region (store (region-list-thread prev-region) region)
				  (store (area-region-list area) region))
		  (%gc-free-region region-to-free)
		  (go nextloop))
		 ;; the plant: the new region keeps the area's bit 13
		 (t
		  (let ((end (region-list-thread region)))
		    (store (area-region-list area) end)
		    (%gc-free-region region)
		    (let ((new (%make-region (%logdpb %region-generation-tenured %%region-generation
						      (area-region-bits area))
					     (area-region-size area))))
		      (store (region-list-thread new) end)
		      (store (area-region-list area) new)))
		  (return nil))))
      (and (= (ldb %%region-space-type (region-bits region)) %region-space-copy)
	   (store (region-bits region) (%logdpb 0 %%region-scavenge-enable
						(%logdpb %region-space-new
							 %%region-space-type
							 (region-bits region))))))))
