;;; -*- Mode:LISP; Package:USER; Base:10; Lowercase:T -*-

;;; The high band's check (contract G3 revision 14, 10.11, "The high band"),
;;; for tools/cross-build's step high, after the region floor was set one
;;; quantum below 2^31 and a full collection copied every dynamic object into
;;; regions at or above it: one region lies across 2^31, and no region of a
;;; dynamic area that holds an object lies below the floor.

(defun high-region-report ()
  "(regions across 2^31, regions of dynamic areas below the floor that hold objects,
regions in use, empty regions of dynamic areas below the floor), each region as
(number area-name origin length free-pointer space-type), origins octal."
  (let ((two31 (si:%make-pointer-unsigned #o20000000000))
	(floor si:%region-floor)
	(first-unfixed (si:region-floor-default))
	(across nil) (low nil) (empty nil) (n 0))
    (dotimes (area si:size-of-area-arrays)
      (when (aref #'si:area-name area)
	(let ((dynamic (= (ldb si:%%region-space-type (si:area-region-bits area)) si:%region-space-new)))
	  (do ((r (si:area-region-list area) (si:region-list-thread r)))
	      ((minusp r))
	    (let* ((o (si:region-origin r))
		   (l (si:region-length r))
		   (end (%pointer-plus o l))
		   (row (list r (aref #'si:area-name area) (format nil "~O" (si:%pointer-unsigned o)) l
			      (si:region-free-pointer r)
			      (ldb si:%%region-space-type (si:region-bits r)))))
	      (when (plusp l)
		(incf n)
		(when (and (si:%pointer-lessp o two31) (si:%pointer-lessp two31 end))
		  (push row across))
		(when (and dynamic
			   (not (si:%pointer-lessp o first-unfixed))
			   (si:%pointer-lessp o floor))
		  ;; an empty one holds no object: the oldspace region an
		  ;; area keeps when the collection leaves it no other
		  (if (plusp (si:region-free-pointer r))
		      (push row low)
		    (push row empty)))))))))
    (list across low n empty)))

(compile 'high-region-report)
