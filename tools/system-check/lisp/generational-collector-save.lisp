;;; -*- Mode:LISP; Package:USER; Base:10; Readtable:ZL -*-
;;; For the save checks of the generational collector (tools/system-check/
;;; README.md, save/; contract G3 step 2 revision 1, section 12, C14 and
;;; C25-C29): a save keeps young objects young, the band carries each page's
;;; young-pointer mark in its mark bitmap, and the boot gives the marks back.
;;; Each check is two sessions on a persistent pack, as tools/cross-build's
;;; incremental step runs them: save/before.cases on a band of step 2, then
;;; DISK-SAVE into a partition, typed by the harness (the save closes the
;;; connection); then save/after.cases on the saved band, booted.  Loaded
;;; after lisp/generational-collector.lisp, whose helpers it uses; both are
;;; then in the saved band.  It needs step 2's microcode (E1) and a band built
;;; with step 2's Lisp (E3); written with E2 and not yet run.
;;;
;;; Automatic collection is off from the first session on (GC-ON-AT-BOOT NIL
;;; and GC-OFF), so that the saved band boots with collections off and the
;;; marks are read as the restore left them; DISK-SAVE still runs its one
;;; young collection.  No case returns a young object, so that the
;;; listener's history holds none: each young list is referenced only from
;;; the tenured slot the case names.

(defvar *gcsave-n* 10000 "The length of each young list: its sum is 49995000.")

(defun gcsave-off ()
  "Collections off now and at the saved band's boot."
  (setq si:gc-on-at-boot nil)
  (gencol-off))

(defun gcsave-young-address-p (x)
  "T if X's address is in ephemeral space, 1101 in its top four bits."
  (= (ldb (byte 4 28) (%pointer x)) #o15))

(defun gcsave-page-mark (address)
  "<19> of the page table's entry for ADDRESS's page, whether or not the page is in
core; NIL if no page-table page covers it."
  (let ((entry (si:page-entry address)))
    (and entry (ldb si:%%page-entry-ephemeral-reference entry))))

(defun gcsave-region-page (address)
  "The page of ADDRESS within its region: 0 for the region's first page."
  (floor (%pointer-difference address (si:region-origin (%region-number address)))
	 si:page-size))

;;; C14: a young list referenced only from a slot of a static array, on a page
;;; that is not its region's first; and (d) a second one, consed and stored by
;;; a BEFORE-COLD initialization, after the save's young collection, so that
;;; it is saved in eden and its mark set just before %DISK-SAVE.
(defvar *gcsave-holder* nil "A tenured array of 3000 slots in GENCOL-STATIC-AREA.")
(defconst gcsave-c14-slot 2500 "The slot holding C14's list, on the array's third page or later.")
(defconst gcsave-c14d-slot 1500 "The slot the BEFORE-COLD initialization stores C14 (d)'s list in.")

(defun gcsave-c14-setup ()
  "Returns (YOUNG-P REGION-PAGE): the list is young, and its slot is not on its region's
first page."
  (setq *gcsave-holder* (gencol-holder 3000))
  (setf (aref *gcsave-holder* gcsave-c14-slot) (gencol-list *gcsave-n*))
  (add-initialization "gcsave-c14d" '(gcsave-c14d-store) '(:before-cold))
  (list (gencol-young-p (aref *gcsave-holder* gcsave-c14-slot))
	(plusp (gcsave-region-page (aloc *gcsave-holder* gcsave-c14-slot)))))

(defun gcsave-c14d-store ()
  (setf (aref *gcsave-holder* gcsave-c14d-slot) (gencol-list *gcsave-n*)))

;;; C25: C14 (c) with the only reference in a page of each of the three kinds
;;; whose entry the restore makes on its own path:
;;; (a) a wired page, below the band's wired size: NIL's property list, in
;;;     RESIDENT-SYMBOL-AREA (BUILD-TABLES's entries);
;;; (b) a page wired for the restore beyond the band's wired size, below
;;;     1000000 (COLD-SWAP-IN's entries): a symbol there, its property list;
;;; (c) a paged page (BUILD-REGION-ENTRIES's): C14's static array, above
;;;     1000000.
;;; Each property list gains a young cons at its front, whose value is a young
;;; list; the symbol's own page holds the only reference to them.
;;; (b), made: the layout has no symbol between the wired size and 1000000
;;; (measured on E3's bands: the wired size is 400000, and only the fixed
;;; areas' regions lie up to 1000000, the region and area tables, the support
;;; vector, the constants, the extra pdl and the micro-code entry areas), so
;;; the search below found none and (b) went unchecked.  Of those regions
;;; AREA-NAME, at 404000, is scavenged and holds pointers, the areas' names;
;;; AREA-LIST is that array as a list.  The setup makes an area named by a
;;; young symbol, whose property list holds the young list, so that the
;;; area's word of AREA-NAME, on a page wired for the restore, holds the only
;;; reference.
;(defvar *gcsave-c25b-symbol* nil "The symbol of (b), or NIL when the layout has none.")
(defvar *gcsave-c25b-area* nil "The area of (b), named by a young symbol.")

(defun gcsave-c25b-symbol ()
  "The young symbol naming (b)'s area."
  (and *gcsave-c25b-area* (si:area-name *gcsave-c25b-area*)))

(defun gcsave-c25b-referrer ()
  "A locative to (b)'s referrer, the area's word of AREA-NAME."
  (and *gcsave-c25b-area* (aloc #'si:area-name *gcsave-c25b-area*)))

(defun gcsave-wired-words ()
  "The band's wired size in words."
  (si:system-communication-area si:%sys-com-wired-size))

(defun gcsave-symbol-between (low high)
  "A symbol, not NIL or T, whose address is at or above LOW and below HIGH, in a region
that is not free; NIL if there is none."
  (do-all-symbols (s)
    (let ((a (si:%pointer-unsigned (%pointer s))))
      (when (and (not (memq s '(nil t)))
		 (<= low a) (< a high)
		 (= (si:region-generation (%region-number s)) si:%region-generation-tenured))
	(return s)))))

(defun gcsave-c25-setup ()
  "Returns (A B C), each T when its kind is set up: the lists young, and each referrer's
page of its kind (for (b), the young symbol too)."
  (setplist nil (list* 'gcsave-c25 (gencol-list *gcsave-n*) (plist nil)))
;  (setq *gcsave-c25b-symbol* (gcsave-symbol-between (gcsave-wired-words) #o1000000))
;  (when *gcsave-c25b-symbol*
;    (setplist *gcsave-c25b-symbol*
;	      (list* 'gcsave-c25 (gencol-list *gcsave-n*) (plist *gcsave-c25b-symbol*))))
  (let ((name (make-symbol "GCSAVE-C25B")))
    (setplist name (list 'gcsave-c25 (gencol-list *gcsave-n*)))
    (setq *gcsave-c25b-area* (make-area :name name :gc :static)))
  (list (and (gencol-young-p (get nil 'gcsave-c25))
	     (< (si:%pointer-unsigned (%pointer nil)) (gcsave-wired-words)))
;	(and *gcsave-c25b-symbol*
;	     (gencol-young-p (get *gcsave-c25b-symbol* 'gcsave-c25))
;	     (si:%pointer-unsigned (%pointer *gcsave-c25b-symbol*)))
	(let ((a (si:%pointer-unsigned (%pointer (gcsave-c25b-referrer)))))
	  (and (gencol-young-p (gcsave-c25b-symbol))
	       (gencol-young-p (get (gcsave-c25b-symbol) 'gcsave-c25))
	       (<= (gcsave-wired-words) a) (< a #o1000000)))
	(>= (si:%pointer-unsigned (%pointer (aloc *gcsave-holder* gcsave-c14-slot))) #o1000000)))

(defun gcsave-lists ()
  "The young lists, by the case that holds them."
  (list (aref *gcsave-holder* gcsave-c14-slot)
	(aref *gcsave-holder* gcsave-c14d-slot)
	(get nil 'gcsave-c25)
;	(and *gcsave-c25b-symbol* (get *gcsave-c25b-symbol* 'gcsave-c25))))
	(and *gcsave-c25b-area* (get (gcsave-c25b-symbol) 'gcsave-c25))))

(defun gcsave-sums ()
  "The sums of the lists of C14, C14 (d), C25 (a) and C25 (b): 49995000 each, NIL for an
absent (b)."
  (mapcar #'(lambda (l) (and l (gencol-sum l))) (gcsave-lists)))

(defun gcsave-referrer-marks ()
  "<19> of the page of each list's referrer: C14's slot, C14 (d)'s, NIL's plist cell,
(b)'s word of AREA-NAME."
  (list (gcsave-page-mark (aloc *gcsave-holder* gcsave-c14-slot))
	(gcsave-page-mark (aloc *gcsave-holder* gcsave-c14d-slot))
	(gcsave-page-mark (%pointer nil))
;	(and *gcsave-c25b-symbol* (gcsave-page-mark (%pointer *gcsave-c25b-symbol*)))))
	(and *gcsave-c25b-area* (gcsave-page-mark (gcsave-c25b-referrer)))))

(defun gcsave-generations ()
  "The generation of each list's first cons: 2 (survivor space 1) for those consed before
the save's collection, 1 (eden) for C14 (d)'s."
  (mapcar #'(lambda (l) (and l (gencol-generation l))) (gcsave-lists)))

(defun gcsave-young-addresses ()
  (mapcar #'(lambda (l) (and l (gcsave-young-address-p l))) (gcsave-lists)))

;;; C26: after the cold boot of a saved band, with collections off and before
;;; any young collection, every page of the band's walk has <19> in its entry
;;; equal to its bit in the band's mark bitmap, read from the partition; and
;;; the band's valid pages are the bitmap's first page plus its pages.  The
;;; walk is the band's own: its region tables are read from the partition too,
;;; since the session's consing since the boot moved the free pointers.
;;; Lisp runs between the boot and the check (the boot's initializations, the
;;; login, the listener), and a young object it stores into a tenured page
;;; marks that page, so a page may be marked with its bit 0.  The check is
;;; therefore "no bit without its mark" (MISSING 0), which an off-by-one page
;;; order or bits ORed into the wrong entries fail; the marks without a bit
;;; (EXTRA) are recorded, a few pages.
(defun gcsave-booted-partition ()
  "The name of the band booted, as DISK-SAVE-INCREMENTAL finds it."
  (format nil "LOD~C" (ldb #o2010 (if (not (zerop si:%loaded-band))
				       si:%loaded-band
				     si:current-loaded-band))))

(defun gcsave-word (rqb index)
  "Word INDEX of RQB's data, read packed, as a fixnum whose 32-bit field is the word."
  (let ((buf (si:rqb-buffer rqb)))
    (si:%logdpb (aref buf (1+ (* 2 index))) #o2020 (aref buf (* 2 index)))))

(defun gcsave-read-band-pages (rqb part-base page)
  "Read the band at PART-BASE's pages from PAGE into RQB, packed."
  (let ((si:*disk-transfer-packed* t))
    (si:disk-read rqb 0 (si:band-page-block part-base page))))

(defun gcsave-band-table (part-base table n-regions)
  "The band at PART-BASE's copy of region table TABLE (an area number, a fixed area's
region being its area's), as an array of N-REGIONS words."
  (let* ((pages (ceiling n-regions si:page-size))
	 (rqb (si:get-disk-rqb pages))
	 (a (make-array n-regions)))
    (unwind-protect
	(progn
	  (gcsave-read-band-pages rqb part-base (si:band-page-index table))
	  (dotimes (r n-regions) (setf (aref a r) (gcsave-word rqb r))))
      (si:return-disk-rqb rqb))
    a))

(defun gcsave-c26 (&optional (part (gcsave-booted-partition)))
  "Returns (FORMAT BITMAP-PAGE-NOT-0 VALID-PAGES-AGREE WALK-PAGES BITS MISSING EXTRA FIRST):
the band's format, %SYS-COM-MARK-BITMAP not 0, the valid pages equal to the bitmap's first
page plus its pages, the walk's pages, the bits set, the pages whose bit is 1 and whose
entry's <19> is not, the pages marked whose bit is 0, and the first few of the missing as
(REGION PAGE MARK)."
  (let* ((part-base (si:find-disk-partition part))
	 (n-regions (array-length #'si:region-origin))
	 (rqb (si:get-disk-rqb))
	 format bitmap-page valid-pages)
    (unwind-protect
	(progn
	  (si:read-band-sys-com rqb 0 part-base)
	  (setq format (gcsave-word rqb si:%sys-com-band-format)
		bitmap-page (gcsave-word rqb si:%sys-com-mark-bitmap)
		valid-pages (ceiling (gcsave-word rqb si:%sys-com-valid-size) si:page-size)))
      (si:return-disk-rqb rqb))
    (let* ((origins (gcsave-band-table part-base si:region-origin n-regions))
	   (bits (gcsave-band-table part-base si:region-bits n-regions))
	   (fps (gcsave-band-table part-base si:region-free-pointer n-regions))
	   (n (loop for r below n-regions
		    sum (if (ldb-test si:%%region-space-type (aref bits r))
			    (ceiling (aref fps r) si:page-size)
			  0)))
	   (bitmap-pages (si:mark-bitmap-pages n))
	   (bitmap (si:get-disk-rqb (max 1 bitmap-pages)))
	   (k 0) (marked 0) (missing 0) (extra 0) (first nil))
      (unwind-protect
	  (progn
	    (unless (zerop bitmap-page)
	      (gcsave-read-band-pages bitmap part-base bitmap-page))
	    (dotimes (r n-regions)
	      (when (ldb-test si:%%region-space-type (aref bits r))
		(dotimes (j (ceiling (aref fps r) si:page-size))
		  (let ((bit (if (zerop bitmap-page)
				 0
			       (ldb (byte 1 (\ k 16))
				    (aref (si:rqb-buffer bitmap)
					  (+ (* 2 (floor k 32)) (if (>= (\ k 32) 16) 1 0))))))
			(mark (gcsave-page-mark (%pointer-plus (aref origins r) (* j si:page-size)))))
		    (cond ((and (= bit 1) (not (eql mark 1)))
			   (incf missing)
			   (when (< (length first) 5) (push (list r j mark) first)))
			  ((and (= bit 0) (eql mark 1))
			   (incf extra)))
		    (when (= bit 1) (incf marked))
		    (incf k))))))
	(si:return-disk-rqb bitmap))
      (list format (not (zerop bitmap-page)) (= valid-pages (+ bitmap-page bitmap-pages))
	    n marked missing extra (nreverse first)))))

(defun gcsave-marked-pages ()
  "The pages of the regions now, not free, whose entry has <19>: 0 at a cold load's boot
before any young object is stored (C26's second part, the restore applying no bitmap)."
  (let ((n 0))
    (dotimes (r (array-length #'si:region-origin))
      (when (ldb-test si:%%region-space-type (si:region-bits r))
	(dotimes (j (ceiling (si:region-free-pointer r) si:page-size))
	  (when (eql 1 (gcsave-page-mark (%pointer-plus (si:region-origin r) (* j si:page-size))))
	    (incf n)))))
    n))

;;; C27's Lisp-visible part: the band booted is format 2020 by the system's own
;;; constants, and its mark bitmap word is set.
(defun gcsave-c27 ()
  (list si:band-format-compressed si:band-format-incremental
	(= (si:system-communication-area si:%sys-com-band-format) si:band-format-compressed)
	(not (zerop (si:system-communication-area si:%sys-com-mark-bitmap)))))

;;; C29: the young words of the band booted, by generation, before any
;;; collection: (EDEN SURVIVOR-1 SURVIVOR-2), recorded, not checked.
(defun gcsave-young-words ()
  (cdr (multiple-value-list (si:gc-get-generation-sizes))))

;;; After the checks: the BEFORE-COLD initialization and the property lists
;;; are removed, so that a later save of this band does not repeat them.
(defun gcsave-clean-up ()
  (delete-initialization "gcsave-c14d" '(:before-cold))
  (remprop nil 'gcsave-c25)
;  (when *gcsave-c25b-symbol* (remprop *gcsave-c25b-symbol* 'gcsave-c25))
  ;; (b)'s area stays, an empty static area: an area is never deleted
  (when *gcsave-c25b-area* (remprop (gcsave-c25b-symbol) 'gcsave-c25))
  t)

(defun gcsave-reclaim-checker-off ()
  "Stop the reclaim checker GENCOL-INSTALL-RECLAIM-CHECKER installed (minutes a reclaim)."
  (setq si:gc-before-reclaim-list
	(remove '(gencol-check-no-oldspace-pointers) si:gc-before-reclaim-list))
  t)
