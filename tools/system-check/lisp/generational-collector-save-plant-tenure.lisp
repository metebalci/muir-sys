;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:10; Readtable:ZL -*-
;;; A planted partial fix for the save checks of the generational collector
;;; (tools/system-check/README.md, save/; contract G3 step 2 revision 1,
;;; section 12, C14): GC-PREPARE-FOR-DISK-SAVE still tenuring every young
;;; object, as revision 0 had it.  Given after lisp/generational-collector-
;;; save.lisp in the first session, before the save; save/after.cases must
;;; then fail C14 (a), the lists consed before the save not young (their
;;; generations 0, not 2) and C14 (b)'s marks.  Not for any band in use.

(defun gc-prepare-for-disk-save ()
  (with-lock (gc-flip-lock)
    (process-disable gc-process)
    (gc-reclaim-oldspace)
    (gc-flip-now :young t)
    (gc-reclaim-oldspace)))
