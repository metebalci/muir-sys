;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:8; Readtable:ZL -*-
;;; A planted partial fix for the check generational-reclaim (C30; contract G3
;;; step 2, clarification 16): GC-RECLAIM-OLDSPACE-AREA frees an area's only
;;; region when it is old and makes no new one, leaving the area's region
;;; list empty.  Given after lisp/generational-collector.lisp in --files: C30
;;; (a), (b), (c) and (d) must fail (no region in the area).  An area left so
;;; is never consed in by the check (RCONS reads an empty region list as a
;;; region), but other areas emptied by the same collection may be, so the
;;; machine may stop after the first failures.  Not for any band in use.

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
		 ;; the plant: the only region freed, no new one made
		 (t
		  (store (area-region-list area) (region-list-thread region))
		  (%gc-free-region region)
		  (return nil))))
      (and (= (ldb %%region-space-type (region-bits region)) %region-space-copy)
	   (store (region-bits region) (%logdpb 0 %%region-scavenge-enable
						(%logdpb %region-space-new
							 %%region-space-type
							 (region-bits region))))))))
