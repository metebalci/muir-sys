;;; -*- Mode:LISP; Package:USER; Base:10; Readtable:ZL -*-
;;; c15, the warm boot (contract g3 step 2, section 12), for
;;; tools/system-check/warm-boot, with lisp/generational-collector.lisp's
;;; helpers loaded first.  (b): a young collection stopped mid-walk, the
;;; scavenger inhibited globally, before the warm boot; after it the
;;; collection finishes with c1's list intact and the reclaim checker
;;; passing.  (a): after the warm boot word 221 reads 1, and a young pointer
;;; stored then into a tenured page survives the next collection.
(defvar *c15-holder* nil)

(defun c15-off ()
  (setq si:gc-on-at-boot nil)
  (gencol-off))

(defun c15-b-setup ()
  "C1's list in a tenured holder; a young flip; the scavenger then stopped
after 320 units of work, mid-walk.  Returns (FLIP-READY OLDSPACE ARMED)."
  (gencol-c1-setup)
  (setq inhibit-scavenging-flag t si:inhibit-idle-scavenging-flag t)
  (si:gc-flip-now :young)
  (dotimes (i 20) (si:%gc-scavenge 16))
  (list si:%gc-flip-ready si:gc-oldspace-exists))

(defun c15-b-finish ()
  "After the warm boot: the scavenger let go, the reclaim checker installed, the
collection finished.  Returns (OLDSPACE-BEFORE SUM CHECKS VIOLATIONS FIRST)."
  (let ((before si:gc-oldspace-exists))
    (setq inhibit-scavenging-flag nil si:inhibit-idle-scavenging-flag nil)
    (gencol-install-reclaim-checker)
    (si:gc-reclaim-oldspace)
    (list before (gencol-c1-sum) (plusp *gencol-reclaim-checks*)
	  *gencol-reclaim-violations* *gencol-reclaim-first*)))

(defun c15-a ()
  "After the warm boot: word 221, and a young list stored into a tenured holder
surviving a young collection.  Returns (WORD-221 SUM)."
  (setq *c15-holder* (gencol-holder 10))
  (setf (aref *c15-holder* 3) (gencol-list 10000))
  (gencol-young-collection)
  (list (si:feature-page-field #o221 #o0001) (gencol-sum (aref *c15-holder* 3))))
