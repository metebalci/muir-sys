;;; -*- Mode:LISP; Package:USER; Base:10; Lowercase:T; Readtable:ZL -*-

;;; The cross build's structure check (tools/cross-check/README.md, "The
;;; tree's structures"): a file compiled for the target that reads the tree's
;;; changed SRCCOM:FILE (SYS: CROSS-CHECK-TREE; SRCCOM) through its description
;;; alone, with no accessor of FILE's: XS-FILE2 includes FILE, so DEFSTRUCT
;;; takes FILE's slots from its description (getdecl), and XS-FILE2's own slot
;;; EXTRA follows them.  The tree's FILE has 7 slots, leader 0 to 6, so EXTRA
;;; is leader 7; with the builder's FILE, 6 slots, it would be leader 6.

(defstruct (xs-file2 :array-leader (:include srccom::file) (:conc-name xs-file2-)
		     (:alterant nil))
  (extra 0))

;;; the leader index XS-FILE2-EXTRA reads, in an array whose leader slot I
;;; holds I
(defun xs-file2-extra-index ()
  (let ((f (make-array 0 :leader-length 10.)))
    (dotimes (i 10.) (setf (array-leader f i) i))
    (xs-file2-extra f)))
