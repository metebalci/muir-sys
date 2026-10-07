;;; -*- Mode:LISP; Package:USER; Base:10; Lowercase:T -*-

;;; The built bands' check, for tools/cross-build's step built (contract G3
;;; step 2 revision 1, 9.4 and 12's C29; the review of the first-object table,
;;; section 5, P7): in a band the route built, every RQB the RQB resource
;;; holds and PAGE-RQB lie on page boundaries, DISK-BUFFER-AREA's first-object
;;; tables hold (the table checker of contract 6.3), and the words its
;;; fillers take (DISK-BUFFER-REGION-PAD-TO-PAGE) and the band's young words by
;;; generation are recorded.

(defun built-aligned-p (address)
  (zerop (logand (1- si:page-size) address)))

(defun built-rqbs ()
  "(the RQBs the RQB resource holds, those whose RQB-BUFFER and data both start on a
page boundary)"
  (let* ((resource (get 'si:rqb 'si:defresource))
	 (n (si:resource-n-objects resource))
	 (good 0))
    (dotimes (i n)
      (let* ((rqb (si:resource-object resource i))
	     (buffer (array-leader rqb si:%disk-rq-leader-buffer))
	     (data (%pointer-plus rqb (- (+ 1 (%p-ldb si:%%array-long-length-flag rqb)
					    (floor (array-length rqb) 2))
					 (* si:page-size (array-leader rqb si:%disk-rq-leader-n-pages))))))
	(when (and (built-aligned-p (%pointer buffer)) (built-aligned-p data))
	  (incf good))))
    (list n good)))

;;; the table checker (contract 6.3), as tools/system-check's
;;; GTU-CHECK-REGION-TABLE: each page's entry below the free pointer is an
;;; object start at or below the page's first word
(defun built-check-region-table (region)
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

(defun built-disk-buffer-area ()
  "(DISK-BUFFER-AREA's regions, those with a table, the table checker's failures, the
words of its ART-32B arrays other than the tables: the fillers')"
  (let ((regions 0) (tabled 0) (failures nil) (filler-words 0))
    (do ((r (si:area-region-list si:disk-buffer-area) (si:region-list-thread r)))
	((minusp r))
      (incf regions)
      (when (si:region-has-first-object-table-p r)
	(incf tabled)
	(setq failures (nconc failures (built-check-region-table r)))
	(let ((org (%make-pointer dtp-locative (si:region-origin r)))
	      (fp (si:region-free-pointer r)))
	  (do ((i (si:region-first-object-table-end r)
		  (+ i (%structure-total-size (%make-pointer-offset dtp-locative org i)))))
	      ((>= i fp))
	    (let ((h (%make-pointer-offset dtp-locative org i)))
	      (when (and (= (%p-data-type h) dtp-array-header)
			 (= (%p-ldb si:%%array-type-field h) (ldb si:%%array-type-field art-32b)))
		(incf filler-words (%structure-total-size h))))))))
    (list regions tabled failures filler-words)))

(defun built-young-words ()
  "The band's words in eden and survivor spaces 1 and 2 (C29)."
  (cdr (multiple-value-list (si:gc-get-generation-sizes))))
