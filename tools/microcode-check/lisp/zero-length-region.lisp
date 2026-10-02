;;; -*- Mode:LISP; Package:USER; Base:10; Lowercase:T -*-

;;; The check of freeing a region of no length (tools/microcode-check/README.md,
;;; cases/zero-length-region.cases).  The cold load gives the last area,
;;; FASL-TEMP-AREA, a region of no length at the end of its areas, where the
;;; next region made begins (sys/cold/coldut.lisp, CREATE-AREAS).  FREE-REGION
;;; (sys/ucadr/uc-storage-allocation.lisp) must leave that other region's quantum
;;; in the address space map, and UPDATE-REGION-PHT, which it calls, the page
;;; below the origin in the page hash table.

(defun zlr-region ()
  "The first region in use whose length is 0, or NIL."
  (dotimes (r si:size-of-area-arrays)
    (and (not (= (ldb si:%%region-space-type (si:region-bits r)) si:%region-space-free))
	 (zerop (si:region-length r))
	 (return r))))

(defun zlr-area (region)
  "The area whose region list holds REGION."
  (dotimes (a (array-active-length #'si:area-name))
    (when (si:area-name a)
      (do ((r (si:area-region-list a) (si:region-list-thread r)))
	  ((minusp r))
	(if (= r region) (return-from zlr-area a))))))

(defun zlr-free (region)
  "Free REGION as GC-RECLAIM-OLDSPACE-AREA frees an old region, after giving its
area a region in front of it.  Returns a list: whether the region holding
REGION's origin still holds it in the address space map, and whether the page
below the origin, read just before, was in the page hash table before the free
and is after it."
  (let* ((area (zlr-area region))
	 (origin (si:region-origin region))
	 (owner (%region-number origin))
	 (below (%make-pointer dtp-locative (%pointer-plus origin (- si:page-size)))))
    ;; A new region is put at the front of the area's list.
    (let ((default-cons-area area)) (make-array 100))
    (without-interrupts
      (do ((r (si:area-region-list area) (si:region-list-thread r))
	   (prev nil r))
	  ((minusp r))
	(when (= r region)
	  (if prev
	      (setf (si:region-list-thread prev) (si:region-list-thread r))
	    (setf (si:area-region-list area) (si:region-list-thread r)))
	  (return)))
      (%p-pointer below)
      (let ((in-core (not (null (si:%page-status below)))))
	(si:%gc-free-region region)
	(list (eq (%region-number origin) owner)
	      in-core
	      (not (null (si:%page-status below))))))))

(compile 'zlr-region)
(compile 'zlr-area)
(compile 'zlr-free)
