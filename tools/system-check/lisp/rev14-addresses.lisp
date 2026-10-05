;;; -*- Mode:LISP; Package:USER; Base:10; Readtable:ZL -*-
;;; For the check rev14-addresses (tools/system-check/README.md): objects
;;; placed at, above and across 2^31 words with the region floor (contract G3
;;; revision 14, 10.11), and readers of the page table for the cases.  It
;;; needs revision 14 and a band of System 2002: the region floor, the page
;;; table and the windows.
;;;
;;; One region can hold the address 2^31, so the check has one area whose
;;; region lies across it, a temporary area: each case that needs an object
;;; across 2^31 starts it afresh (rev14-fresh), so that its objects are placed
;;; from the region's origin again, and drops the objects of the case before.

(defvar *rev14-area* nil "A temporary area of structures whose one region lies across 2^31.")
(defvar *rev14-mar* nil)
(defvar *rev14-wire* nil)
(defvar *rev14-rqb* nil)

(defun rev14-address (n)
  "The fixnum whose 32-bit field is the address N (si:%make-pointer-unsigned)."
  (si:%make-pointer-unsigned n))

(defun rev14-unsigned (x)
  "X's pointer field as an unsigned number."
  (si:%pointer-unsigned (%pointer x)))

(defun rev14-area ()
  "The area whose first region, two quanta long, starts one quantum below 2^31: the
region floor is raised to there while the area is made, then put back."
  (or *rev14-area*
      (unwind-protect
	  (progn (si:set-region-floor (rev14-address #o17777740000))
		 (setq *rev14-area* (make-area :name 'rev14-area :gc :temporary
					       :representation :structure
					       :region-size #o100000)))
	(si:set-region-floor))))

(defun rev14-fresh ()
  "Start the area afresh: the objects of the case before are dropped, and the next object
is placed at the region's origin again."
  (setq *rev14-mar* nil *rev14-wire* nil *rev14-rqb* nil)
  (si:reset-temporary-area (rev14-area))
  t)

(defun rev14-region-across-p (area)
  "T if AREA's first region holds the address 2^31 - 1 and the address 2^31."
  (let* ((region (si:area-region-list area))
	 (origin (si:region-origin region))
	 (last (%pointer-plus origin (1- (si:region-length region)))))
    (and (not (si:%pointer-lessp (rev14-address #o17777777777) origin))
	 (not (si:%pointer-lessp last (rev14-address #o20000000000))))))

(defun rev14-free-address (area)
  "The address of the next word AREA's first region will allocate."
  (let ((region (si:area-region-list area)))
    (%pointer-plus (si:region-origin region) (si:region-free-pointer region))))

(defun rev14-fill-to (address)
  "Cons fillers in the area so that its next object starts at ADDRESS."
  (let ((gap (%pointer-difference address (rev14-free-address (rev14-area)))))
    (cond ((minusp gap) (ferror nil "The area's next word, ~O, is past ~O"
				(rev14-unsigned (rev14-free-address (rev14-area)))
				(rev14-unsigned address)))
	  ((zerop gap))
	  ((<= (1- gap) si:%array-max-short-index-length)
	   (make-array (1- gap) :type 'art-32b :area (rev14-area)))	;a header and GAP - 1 words
	  (t (make-array (- gap 2) :type 'art-32b :area (rev14-area))))	;a long array's two header words
    (= (rev14-free-address (rev14-area)) address)))

(defun rev14-array-at (header-address length &optional (type 'art-q))
  "A short array of LENGTH elements whose header is at HEADER-ADDRESS, in the area
(ART-Q by default, whose elements ALOC takes)."
  (rev14-fill-to header-address)
  (make-array length :type type :area (rev14-area)))

(defun rev14-page (address)
  "The address of the first word of ADDRESS's page."
  (logand (%pointer address) (- si:page-size)))

(defun rev14-page-wired-p (address)
  "T if ADDRESS's page is in core and its frame wired (physical-page-data)."
  (let ((entry (si:page-entry address)))
    (and entry
	 (member (ldb si:%%page-entry-status entry) '(2 4 5 6))
	 (si:frame-wired-p (ldb si:%%page-entry-frame entry)))))

(defun rev14-page-status (address)
  "The status, <26:24>, of ADDRESS's page entry, or NIL if it has none."
  (let ((entry (si:page-entry address)))
    (and entry (ldb si:%%page-entry-status entry))))

(defun rev14-pages (from n)
  "The addresses of the N pages from FROM's page on."
  (loop for k below n collect (%pointer-plus (rev14-page from) (* k si:page-size))))

(defun rev14-ephemeral-area ()
  "A new ephemeral area whose first region is used up, so that its next object takes a
new region with the area's bits, in ephemeral space."
  (let ((area (make-area :name (gensym) :gc :dynamic :region-size #o40000)))
    (setf (si:area-region-bits area) (%logdpb 1 si:%%region-ephemeral (si:area-region-bits area)))
    (si:%use-up-region (si:area-region-list area))
    area))

(defun rev14-mar-trap-p (thunk)
  "T if calling THUNK signals the MAR's trap (eh:mar-break, a condition, not an error)."
  (condition-case ()
      (progn (funcall thunk) nil)
    (eh::mar-break t)))

(defun rev14-same-p (a b)
  "T if the arrays A and B hold the same elements."
  (and (= (array-length a) (array-length b))
       (loop for i below (array-length a) always (= (aref a i) (aref b i)))))
