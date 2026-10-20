;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:8; Readtable:ZL -*-
;;; A planted control for the check generational-table-users (contract G3 step
;;; 2, 6.2; P5 as step R3 of QUUX's Ethernet contract, section 8, rewrote it):
;;; RESET-TEMPORARY-AREA as it was before the first-object table, every
;;; region's free pointer set to 0, so that the next object made overwrites
;;; the region's table.  Given after lisp/generational-table-users.lisp in
;;; --files, P5's resets must leave free pointers off their tables' ends, and
;;; the buffers made after them where the tables were.  Not for any band in
;;; use.

(defun reset-temporary-area (area)
  "Set all free pointers of an area to 0, deleting its entire contents."
  (unless (area-temporary-p area)
    (multiple-cerror () ()
		     ("The area ~S (~S) was not created as temporary." (area-name area) area)
      ("Don't reset this area" (return-from reset-temporary-area nil))
      ("Make area temporary, and the reset it" (make-area-temporary area))))
  (without-interrupts
    (do region (area-region-list area) (region-list-thread region) (minusp region)
      (gc-reset-free-pointer region 0))))
