;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:8; Readtable:T -*-
;;; A planted control for the check generational-table-users (contract G3 step
;;; 2, clarification 12; the review of the first-object table, section 5, P4):
;;; MAPATOMS-NR-SYM as it was before clarification 12, walking each region of
;;; NR-SYM and WORTHLESS-SYMBOL-AREA from its origin, through its first-object
;;; table.  Given after lisp/generational-table-users.lisp in --files, P4 must
;;; find visits that are not symbols.  Not for any band in use.

(defun mapatoms-nr-sym (function)
  "Call FUNCTION on every symbol in the world, regardless of packages."
  (funcall function nil)			;these two are stored elsewhere
  (funcall function t)
  (do ((region (area-region-list nr-sym) (region-list-thread region)))
      ((minusp region))
    (do ((sym (%make-pointer dtp-symbol (region-origin region))
	      (%make-pointer-offset dtp-symbol sym length-of-atom-head))
         (ct (truncate (region-free-pointer region) length-of-atom-head) (1- ct)))
        ((zerop ct))
      (funcall function sym)))
  (when (boundp 'worthless-symbol-area)
    (do ((region (area-region-list worthless-symbol-area) (region-list-thread region)))
	((minusp region))
      (do ((sym (%make-pointer dtp-symbol (region-origin region))
		(%make-pointer-offset dtp-symbol sym length-of-atom-head))
	   (ct (truncate (region-free-pointer region) length-of-atom-head) (1- ct)))
	  ((zerop ct))
	(funcall function sym)))))
