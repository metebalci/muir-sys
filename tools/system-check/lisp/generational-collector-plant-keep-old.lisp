;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:8; Readtable:ZL -*-
;;; A planted partial fix for the check generational-reclaim (C30; contract G3
;;; step 2, clarification 16): MIT's GC-RECLAIM-OLDSPACE-AREA, which keeps an
;;; area's only region when it is old.  Given after
;;; lisp/generational-collector.lisp in --files: C30 (a), (b), (c) and the
;;; oldspace cases must fail (the region stays old).  Not for any band in use.

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
	   ;; free this region unless that would leave the area without any
	   ;; regions: MIT's rule, kept
	   (cond ((or prev-region (not (minusp (region-list-thread region))))
		  (setq region-to-free region
			region (region-list-thread region))
		  (if prev-region (store (region-list-thread prev-region) region)
				  (store (area-region-list area) region))
		  (%gc-free-region region-to-free)
		  (go nextloop))))
      (and (= (ldb %%region-space-type (region-bits region)) %region-space-copy)
	   (store (region-bits region) (%logdpb 0 %%region-scavenge-enable
						(%logdpb %region-space-new
							 %%region-space-type
							 (region-bits region))))))))
