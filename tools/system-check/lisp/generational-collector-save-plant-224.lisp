;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:10; Readtable:ZL -*-
;;; Planted for the save checks of the generational collector
;;; (tools/system-check/README.md, save/refuse.cases; contract G3 step 2
;;; revision 1, section 12, C28): register-page word 224's reader returns 1,
;;; as after a write-back of a page's young-pointer mark that the guard
;;; refused.  DISK-SAVE must then refuse the save and leave the partition's
;;; band as it was; a DISK-SAVE that does not check overwrites it.  Not for
;;; any band in use.

(defun disk-save-refused-write-backs ()
  1)
