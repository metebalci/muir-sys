;;; -*- Mode:LISP; Package:SI; Base:10; Lowercase:T -*-

;;; The generational collector's save and restore of the young-pointer marks
;;; (contract G3 step 2 revision 1, 8.3; 9.1 item 8; the microcode's part of
;;; C14, C25 and C26): loaded after lisp/generational.lisp, whose helpers it
;;; uses.  A session makes young lists held only from tenured pages, and the
;;; band is saved (the harness types the DISK-SAVE); the saved band, booted,
;;; must have those pages marked before any collection, every page whose bit is
;;; 1 in the band's mark bitmap marked in its entry, and the lists intact after
;;; young collections.  tools/microcode-check/generational-save runs it.

(defvar *gs-holder* nil "A static array: slot 1500, not on its first page, holds a young list.")
(defvar *gs-late* nil "A static array: slot 5 gets a young list in a BEFORE-COLD initialization.")

(defun gs-before-cold ()
  "Run by DISK-SAVE's BEFORE-COLD initializations, just before %DISK-SAVE: a young list
stored into a tenured page then is marked only just before the save (C14 (d))."
  (when *gs-late*
    (setf (aref *gs-late* 5) (gen-list 100 (gen-eph-area)))))

(defun gs-setup ()
  "The young lists and their tenured holders; the holders' pages' marks."
  (gen-setup)
  (setq *gs-holder* (make-array 2000 :area (gen-static-area)))
  (setf (aref *gs-holder* 1500) (gen-list 10000 (gen-eph-area)))
  ;; a wired page (C25 (a)): NIL's property list cell, in RESIDENT-SYMBOL-AREA,
  ;; given a young list at its head
  (setf (plist nil) (let ((default-cons-area (gen-eph-area)))
		      (list* 'gs-young (gen-list 1000 (gen-eph-area)) (plist nil))))
  (setq *gs-late* (make-array 10 :area (gen-static-area)))
  (add-initialization "gs before cold" '(gs-before-cold) '(:before-cold))
  ;; one young collection before the save: in the first collection after a
  ;; store the list is found without the walk (generational.lisp, gen-c17),
  ;; so without it the lists outlived the boot's collections even from a band
  ;; saved with no marks (measured).  the lists move to survivor space 1.
  (gen-collect)
  (list (gen-mark (aloc *gs-holder* 1500)) (gen-mark (locf (plist nil)))
	(gen-generation (aref *gs-holder* 1500)) (gen-generation (plist nil))))

;; the holders by their pages' addresses, not their places in the walk: what
;; the save conses before its walk (disk-save's own strings, an incremental
;; save's disk buffers) into a region below a holder's moves the holder's place
(defun gs-holder-pages ()
  "The addresses of the holders' pages: the static array's slot, NIL's plist cell, the
late store's slot."
  (mapcar #'(lambda (loc) (* page-size (floor (%pointer-unsigned (%pointer loc)) page-size)))
	  (list (aloc *gs-holder* 1500) (locf (plist nil)) (aloc *gs-late* 5))))

(defun gs-after ()
  "After the boot, before any collection: the holders' pages' marks and the lists'
generations (survivor space 2, 3, for the two stored before the save, which DISK-SAVE's own
young collection moved on from survivor space 1; eden, 1, for the BEFORE-COLD one)."
  (list (gen-mark (aloc *gs-holder* 1500)) (gen-mark (locf (plist nil)))
	(gen-mark (aloc *gs-late* 5))
	(gen-generation (aref *gs-holder* 1500)) (gen-generation (plist nil))
	(gen-generation (aref *gs-late* 5))))

(defun gs-bitmap-marked (file)
  "FILE holds the address of each page whose bit is 1 in the band's mark bitmap, one a
line (the harness wrote them from the partition, mapping the bitmap's places to pages
with the band's own region tables): the number of them, of those whose page's entry is
not marked now, and the first five of those."
  (with-open-file (s file)
    (do ((line (readline s nil) (readline s nil))
	 (n 0) (unmarked nil))
	;; firstn pads a short list with nils, so at most as many as there are
	((null line) (list n (length unmarked)
			   (firstn (min 5 (length unmarked)) (nreverse unmarked))))
      (let ((address (%make-pointer-unsigned (parse-number line))))
	(incf n)
	(unless (eql (gen-mark address) 1) (push (parse-number line) unmarked))))))

(defun gs-sums ()
  (list (gen-sum (aref *gs-holder* 1500)) (gen-sum (cadr (plist nil))) (gen-sum (aref *gs-late* 5))))

(defun gs-collect-sums ()
  "The sums after one, two and three young collections (C14 (c))."
  (loop repeat 3 do (gen-collect) collect (gs-sums)))
