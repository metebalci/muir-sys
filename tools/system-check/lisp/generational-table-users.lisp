;;; -*- Mode:LISP; Package:USER; Base:10; Readtable:ZL -*-
;;; For the check generational-table-users (tools/system-check/README.md): the
;;; code that found a region's first object at its origin, where the
;;; first-object table now is (contract G3 step 2, 6.1; clarifications 11 and
;;; 12; the review of the first-object table, section 5, tests P2-P5).
;;; - P2, the split retry: MAKE-DISK-RQB with its first two arrays in a region
;;;   filled to within 8 words of its end, its RQB in a fresh region, which
;;;   begins with its table: the RQB is padded to a page boundary.  (b):
;;;   WIRE-DISK-RQB refuses an RQB made off a page boundary.
;;; - P3, PAGE-RQB on a page boundary; MIT's form, in a fresh table region,
;;;   off one by the table's words, and WIRE-PAGE-RQB refusing it.
;;; - P4, MAPATOMS-NR-SYM: every object it visits is a symbol, as many as a
;;;   walk by %STRUCTURE-TOTAL-SIZE from each region's table end finds, in
;;;   NR-SYM, in a region of it made since, and in WORTHLESS-SYMBOL-AREA.
;;; - P5, CHAOS-BUFFER-AREA: PRINT-INT-PKT-STATUS visits the buffers, from the
;;;   table's end, and nothing else; the area keeps one region.
;;; The planted controls are the functions as they were, in
;;; generational-table-users-plant-disk.lisp, -plant-mapatoms.lisp and
;;; -plant-chaos.lisp, each given after this file.  Each test uses up regions
;;; of a system area, so the check runs on a copy of the band (lispm-check's).

;;; The table checker of contract 6.3, as the check generational-collector
;;; has it (GENCOL-CHECK-REGION-TABLE), here so that this check needs no other
;;; file: each page's entry below the free pointer is an object start at or
;;; below the page's first word.  NIL if the table holds.
(defun gtu-check-region-table (region)
  (let* ((fp (si:region-free-pointer region))
	 (org (%make-pointer dtp-locative (si:region-origin region)))
	 (table (si:region-first-object-table region))
	 (starts (make-array (1+ fp) :type 'art-1b))
	 (failures nil))
    (do ((i 0)) ((>= i fp))
      (let ((total (%structure-total-size (%make-pointer-offset dtp-locative org i))))
	(when (or (not (plusp total)) (> (+ i total) fp))
	  (push (list region :walk i) failures)
	  (return nil))
	(setf (aref starts i) 1)
	(incf i total)))
    (unless failures
      (do ((page 0 (1+ page)))
	  ((not (< (* page si:page-size) fp)))
	(let ((entry (aref table page)))
	  (unless (and (not (> entry (* page si:page-size)))
		       (= (aref starts entry) 1))
	    (push (list region page entry) failures)))))
    (nreverse failures)))

(defun gtu-table-header-p (region)
  "T if REGION's first word is an ART-32B array's header, a first-object table's."
  (let ((h (%make-pointer dtp-locative (si:region-origin region))))
    (and (= (%p-data-type h) dtp-array-header)
	 (= (%p-ldb si:%%array-type-field h) (ldb si:%%array-type-field art-32b)))))

(defun gtu-use-up-area (area)
  "Use up every region of AREA, so that its next cons makes a fresh region."
  (do ((r (si:area-region-list area) (si:region-list-thread r)))
      ((minusp r))
    (si:%use-up-region r)))

(defun gtu-filler (area words)
  "An ART-32B array of WORDS words in all, in AREA; NIL for 0 words."
  (cond ((zerop words) nil)
	((<= (1- words) si:%array-max-short-index-length)
	 (make-array (1- words) :type 'art-32b :area area))
	(t (make-array (- words 2) :type 'art-32b :area area))))

(defun gtu-on-page-boundary (address)
  (zerop (logand (1- si:page-size) address)))

(defun gtu-rqb-data (rqb)
  "The address of RQB's data, its last pages."
  (%pointer-plus rqb (- (+ 1 (%p-ldb si:%%array-long-length-flag rqb) (floor (array-length rqb) 2))
			(* si:page-size (array-leader rqb si:%disk-rq-leader-n-pages)))))

;;; P2
(defun gtu-p2 ()
  "DISK-BUFFER-AREA's regions used up, a fresh one filled to within 8 words of its end,
then (MAKE-DISK-RQB NIL 4 ...): RQB-BUFFER and RQB-8-BIT-BUFFER fit the filled region,
the RQB does not, so the split retry uses that region up and makes the RQB in a fresh
one, which begins with its table.  (RQB-BUFFER in the RQB's region, that region not
the filled one, the filled one used up, RQB-BUFFER on a page boundary, the data on one,
the table checker's failures in the filled region and in the RQB's), or the error's
message."
  (gtu-use-up-area si:disk-buffer-area)
  (let* ((front (%region-number (make-array 0 :type 'art-32b :area si:disk-buffer-area)))
	 (filler (gtu-filler si:disk-buffer-area
			     (- (si:region-length front) (si:region-free-pointer front) 8))))
    (if (not (and filler (= (%region-number filler) front)))
	:setup-failed
      (let ((rqb (condition-case (e)
		     (si:make-disk-rqb nil 4 (length si:disk-rq-leader-qs))
		   (error (send e :report-string)))))
	(if (stringp rqb)
	    rqb
	  (let* ((buffer (array-leader rqb si:%disk-rq-leader-buffer))
		 (region (%region-number rqb)))
	    (list (= (%region-number buffer) region)
		  (not (= region front))
		  (= (si:region-length front) (si:region-free-pointer front))
		  (gtu-on-page-boundary (%pointer buffer))
		  (gtu-on-page-boundary (gtu-rqb-data rqb))
		  (gtu-check-region-table front)
		  (gtu-check-region-table region))))))))

;;; P2 (b): an RQB off a page boundary, made as MAKE-DISK-RQB made one before
;;; clarification 11 (its arrays at a fresh table region's free pointer), but
;;; without MAKE-DISK-RQB's check, which stopped it
(defun gtu-misaligned-rqb (n-pages)
  (let* ((leader-length (length si:disk-rq-leader-qs))
	 (overhead (+ 4 4 3 leader-length))
	 (array-length (* (- (* (1+ n-pages) si:page-size) overhead) 2))
	 buffer buffer-8 rqb)
    (when (> array-length si:%array-max-short-index-length)
      (incf overhead 1)
      (decf array-length 2))
    (gtu-use-up-area si:disk-buffer-area)
    (setq buffer (make-array (* si:page-size 2 n-pages) :type 'art-16b :area si:disk-buffer-area
			     :displaced-to "" :displaced-index-offset
			     (- array-length (* si:page-size 2 n-pages)))
	  buffer-8 (make-array (* si:page-size 4 n-pages) :type 'art-string
			       :area si:disk-buffer-area :displaced-to ""
			       :displaced-index-offset (* 2 (- array-length (* si:page-size 2 n-pages))))
	  rqb (make-array array-length :area si:disk-buffer-area :type 'art-16b
			  :leader-length leader-length))
    (%p-store-contents-offset rqb buffer 1)
    (%p-store-contents-offset rqb buffer-8 1)
    (store-array-leader (+ si:%disk-rq-ccw-list (* 2 n-pages)) rqb si:%disk-rq-leader-n-hwds)
    (setf (array-leader rqb si:%disk-rq-leader-n-pages) n-pages)
    (setf (array-leader rqb si:%disk-rq-leader-buffer) buffer)
    (setf (array-leader rqb si:%disk-rq-leader-8-bit-buffer) buffer-8)
    rqb))

(defun gtu-p2b ()
  "(the misaligned RQB's data off a page boundary, WIRE-DISK-RQB refusing it, an RQB of
MAKE-DISK-RQB wired and unwired)"
  (let* ((bad (gtu-misaligned-rqb 2))
	 (refused (condition-case ()
		      (progn (si:wire-disk-rqb bad) (si:unwire-disk-rqb bad) nil)
		    (error t)))
	 (good (si:make-disk-rqb nil 2 (length si:disk-rq-leader-qs)))
	 (taken (condition-case (e)
		    (progn (si:wire-disk-rqb good) (si:unwire-disk-rqb good) t)
		  (error (send e :report-string)))))
    (list (not (gtu-on-page-boundary (gtu-rqb-data bad))) refused taken)))

;;; P3
(defun gtu-p3-page-rqb ()
  "PAGE-RQB's offset from a page boundary: 0."
  (logand (1- si:page-size) (%pointer si:page-rqb)))

(defvar *gtu-p3-old-offset* nil
  "MIT's form for PAGE-RQB in a fresh table region: its offset from a page boundary.")

(defun gtu-p3 ()
  "(MIT's form for PAGE-RQB, evaluated in a fresh table region: off a page boundary, by
the region's table's words (*GTU-P3-OLD-OFFSET*), WIRE-PAGE-RQB refusing it;
MAKE-PAGE-RQB in a fresh table region: its offset, WIRE-PAGE-RQB taking it, the table
checker's failures)"
  (gtu-use-up-area si:disk-buffer-area)
  (let* ((old (make-array (* 2 (- si:page-size si:page-rqb-header-words)) :type 'art-16b
			  :area si:disk-buffer-area))
	 (old-offset (logand (1- si:page-size) (%pointer old)))
	 (old-table-end (si:region-first-object-table-end (%region-number old)))
	 (refused (condition-case ()
		      (progv '(si:page-rqb) (list old)
			(si:wire-page-rqb)
			(si:unwire-page-rqb)
			nil)
		    (error t))))
    (gtu-use-up-area si:disk-buffer-area)
    (let* ((new (si:make-page-rqb))
	   (taken (condition-case (e)
		      (progv '(si:page-rqb) (list new)
			(si:wire-page-rqb)
			(si:unwire-page-rqb)
			t)
		    (error (send e :report-string)))))
      (setq *gtu-p3-old-offset* old-offset)
      (list (plusp old-offset) (= old-offset old-table-end) refused
	    (logand (1- si:page-size) (%pointer new)) taken
	    (gtu-check-region-table (%region-number new))))))

;;; P4
(defun gtu-symbol-walk (area)
  "AREA's objects, walked by %STRUCTURE-TOTAL-SIZE from each region's table end: their
number if every one is a symbol, else :NOT-A-SYMBOL."
  (let ((n 0))
    (do ((r (si:area-region-list area) (si:region-list-thread r)))
	((minusp r) n)
      (let ((org (%make-pointer dtp-locative (si:region-origin r)))
	    (fp (si:region-free-pointer r)))
	(do ((i (si:region-first-object-table-end r)
		(+ i (%structure-total-size (%make-pointer-offset dtp-locative org i)))))
	    ((>= i fp))
	  (unless (= (%p-data-type (%make-pointer-offset dtp-locative org i)) dtp-symbol-header)
	    (return-from gtu-symbol-walk :not-a-symbol))
	  (incf n))))))

(defvar *gtu-fresh-symbol* nil)

(defun gtu-p4-fresh-region ()
  "NR-SYM's regions used up and a symbol made in it, in a fresh region: (NR-SYM's regions
more than one, the symbol's region beginning with a table, the symbol after the table)."
  (gtu-use-up-area si:nr-sym)
  (setq *gtu-fresh-symbol* (make-symbol "GTU-FRESH" t))
  (let ((r (%region-number *gtu-fresh-symbol*)))
    (list (> (loop for x = (si:area-region-list si:nr-sym) then (si:region-list-thread x)
		   until (minusp x) count t)
	     1)
	  (gtu-table-header-p r)
	  (= (%pointer-difference *gtu-fresh-symbol* (si:region-origin r))
	     (si:region-first-object-table-end r)))))

(defun gtu-p4 ()
  "MAPATOMS-NR-SYM's visits: (in NR-SYM, those not symbols; in WORTHLESS-SYMBOL-AREA,
those not symbols; NR-SYM's count against its walk's; WORTHLESS-SYMBOL-AREA's count
against its walk's; elsewhere (NIL and T); the fresh symbol visited)."
  (let ((nr 0) (nr-bad 0) (ws 0) (ws-bad 0) (other 0) (fresh nil))
    (si:mapatoms-nr-sym
      #'(lambda (s)
	  (let ((a (%area-number s))
		(symbol-p (= (%p-data-type s) dtp-symbol-header)))
	    (cond ((eql a si:nr-sym)
		   (incf nr)
		   (or symbol-p (incf nr-bad))
		   (and *gtu-fresh-symbol* (eq s *gtu-fresh-symbol*) (setq fresh t)))
		  ((eql a si:worthless-symbol-area)
		   (incf ws)
		   (or symbol-p (incf ws-bad)))
		  (t (incf other))))))
    (list nr-bad ws-bad
	  (eql nr (gtu-symbol-walk si:nr-sym))
	  (eql ws (gtu-symbol-walk si:worthless-symbol-area))
	  other fresh)))

;;; P5
(defun gtu-chaos-walk (area)
  "PRINT-INT-PKT-STATUS's walk of AREA, as CHAOS-BUFFER-AREA, with CHAOS:PRINT-PKT
replaced by a recorder and the output dropped: (the packets it visits, NIL if it
signalled)."
  (let ((visited nil)
	(old (fsymeval 'chaos:print-pkt)))
    (unwind-protect
	(progn
	  (fset 'chaos:print-pkt #'(lambda (pkt &rest ignore) (push pkt visited)))
	  (condition-case ()
	      (progv '(chaos:chaos-buffer-area) (list area)
		(let ((standard-output 'si:null-stream))
		  (chaos:print-int-pkt-status t))
		(nreverse visited))
	    (error nil)))
      (fset 'chaos:print-pkt old))))

(defun gtu-buffer-walk (area)
  "AREA's region walked by %STRUCTURE-TOTAL-SIZE from its table's end: the array header of
each ART-16B array with a leader, as PRINT-INT-PKT-STATUS names a buffer, or :OTHER for
another object."
  (let* ((r (si:area-region-list area))
	 (org (%make-pointer dtp-locative (si:region-origin r)))
	 (fp (si:region-free-pointer r))
	 (found nil))
    (do ((i (si:region-first-object-table-end r)
	    (+ i (%structure-total-size (%make-pointer-offset dtp-locative org i)))))
	((>= i fp) (nreverse found))
      (let ((leader (%make-pointer-offset dtp-locative org i)))
	(push (if (= (%p-data-type leader) dtp-header)
		  (%make-pointer-offset dtp-array-pointer org
					(+ i 2 (length chaos:chaos-buffer-leader-qs)))
		:other)
	      found)))))

(defun gtu-p5-sizes (area)
  "(AREA's first region's free pointer, its length, its table's end)"
  (let ((r (si:area-region-list area)))
    (list (si:region-free-pointer r) (si:region-length r) (si:region-first-object-table-end r))))

(defun gtu-p5-check (area)
  "(AREA's regions, its buffers walked, PRINT-INT-PKT-STATUS's visits the same buffers,
each of them an ART-16B array's header, the free pointer below the region's length)"
  (let ((visited (gtu-chaos-walk area))
	(walked (gtu-buffer-walk area))
	(r (si:area-region-list area)))
    (list (loop for x = r then (si:region-list-thread x) until (minusp x) count t)
	  (length walked)
	  (and visited (= (length visited) (length walked))
	       (loop for v in visited for w in walked always (= (%pointer v) (%pointer w))))
	  (and visited
	       (loop for v in visited
		     always (and (= (%p-data-type v) dtp-array-header)
				 (= (%p-ldb si:%%array-type-field v) (ldb si:%%array-type-field art-16b)))))
	  (< (si:region-free-pointer r) (si:region-length r)))))

(defvar *gtu-p5-scratch-area* nil)

(defun gtu-p5-scratch ()
  "A temporary area made as CREATE-CHAOSNET-BUFFERS makes CHAOS-BUFFER-AREA, its 40
buffers made, the area reset (RESET-TEMPORARY-AREA) and the 40 made again: GTU-P5-CHECK.
The area is kept in *GTU-P5-SCRATCH-AREA*."
  (let* ((n (length chaos:chaos-buffer-leader-qs))
	 (area (make-area :name (gensym "GTU-CHAOS-")
			  :size (* (ceiling (* 40 (+ 3 128 n)) si:page-size) si:page-size)
			  :gc :temporary)))
    (setq *gtu-p5-scratch-area* area)
    (dotimes (pass 2)
      (when (= pass 1) (si:reset-temporary-area area))
      (dotimes (i 40)
	(make-array 256 :type 'art-16b :area area :leader-length n)))
    (gtu-p5-check area)))
