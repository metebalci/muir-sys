;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:10; Readtable:ZL -*-
;;; Planted partial fixes for the check rev14-addresses (contract G3 revision
;;; 14, section 12's Y3 checks: "a partial fix fails").  Given after
;;; lisp/rev14-addresses.lisp in --files, each replaces a function of the tree
;;; with the fix half made, and the check's cases for it must fail:
;;; - SET-MAR with only %MAR-HIGH made by %POINTER-PLUS: its loop still steps
;;;   #o200 words and compares signed, so for an object across 2^31 it ends at
;;;   once and sets no page (the MAR cases fail);
;;; - WIRE-DISK-RQB with only LOW made by %POINTER-PLUS: HIGH and the page
;;;   loop still use + and >=, so the address 2^31 becomes a bignum, whose own
;;;   page WIRE-PAGE wires, or the loop wires none (the RQB cases fail).
;;; Not for any band in use.

(defun set-mar (location cycle-type &optional (n-words 1))
  (setq cycle-type (ecase cycle-type
		     (:read 1)
		     (:write 2)
		     ((t) 3)))
  (clear-mar)
  (setq %mar-high (%pointer-plus (setq %mar-low (%pointer location)) (1- n-words)))
  (do ((p %mar-low (+ p #o200)))
      ((> p %mar-high))
    (%change-page-status p nil (dpb 6 #o0604 (ldb %%region-map-bits
						  (region-bits (%region-number p))))))
  (setq %mode-flags (%logdpb cycle-type %%m-flags-mar-mode %mode-flags))
  t)

(defun wire-disk-rqb (rqb &optional (n-pages (array-leader rqb %disk-rq-leader-n-pages))
			  (wire-p t)
			  set-modified
		      &aux (long-array-flag (%p-ldb %%array-long-length-flag rqb))
			   (low (%pointer-plus rqb (- (+ (array-leader-length rqb) 2))))
			   (high (+ (%pointer rqb) 1 long-array-flag
				    (floor (array-length rqb) 2))))
  (do ((loc (logand low (- page-size)) (+ loc page-size)))
      ((>= loc high))
    (wire-page loc wire-p set-modified))
  (if (not wire-p)
      (setf (aref rqb %disk-rq-ccw-list-pointer-low) #o177777
	    (aref rqb %disk-rq-ccw-list-pointer-high) #o76)
    (do* ((n-blocks n-pages)
	  (block-words page-size)
	  (ccwx 0 (1+ ccwx))
	  (vadr (%pointer-plus low page-size) (%pointer-plus vadr block-words))
	  (padr))
	((>= ccwx n-blocks)
	 (setq padr (%physical-address (%pointer-plus rqb (+ 1 long-array-flag
							     (floor %disk-rq-ccw-list 2)))))
	 (setf (aref rqb %disk-rq-ccw-list-pointer-low) padr)
	 (setf (aref rqb %disk-rq-ccw-list-pointer-high) (lsh padr -16.)))
      (setq padr (%physical-address vadr))
      (setf (aref rqb (+ %disk-rq-ccw-list (* 2 ccwx)))
	    (+ (logand (- block-words) padr)
	       (if (= ccwx (1- n-blocks)) 0 1)))
      (setf (aref rqb (+ %disk-rq-ccw-list 1 (* 2 ccwx)))
	    (lsh padr -16.)))))
