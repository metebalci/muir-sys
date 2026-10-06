;;; -*- Mode:LISP; Package:SI; Base:10; Lowercase:T -*-

;;; Revision 14's paging over slots (tools/microcode-check/README.md,
;;; cases/rev14-paging.cases; contract G3 revision 14, 9.3 and section 12's Y2
;;; checks), at 2 M words of main memory, where arrays of a few M words force
;;; pages out.  Definitions only; the cases call them.
;;;
;;; The round trip: element i of a 2.5 M-word array is i; arrays of 1.5 M words
;;; force it out; every element is read back.  Its pages' entries are read
;;; (SI:PAGE-ENTRY): a page out has a slot.
;;;
;;; Fresh pages: pages of a new region read but never written are fresh, each
;;; word the self-pointing DTP-TRAP word CZRR fills it with (its 32-bit field
;;; its own address); forced out unwritten, such a page takes no slot (its
;;; entry's slot is %PAGE-ENTRY-NO-SLOT, which SI:PAGE-ENTRY-SLOT reads as NIL)
;;; and comes back as a fresh page, the same fill.

(defun rev14p-loc (a) (%make-pointer dtp-locative a))
(defun rev14p-amem (k) (%p-ldb (byte 32 0) (rev14p-loc (%make-pointer-unsigned (+ #o35700000000 k)))))
(defun rev14p-word (k) (%p-ldb (byte 32 0) (rev14p-loc (%make-pointer-unsigned (+ #o35777777400 k)))))
(defun rev14p-counters ()
  "The paging counters, A 154, 155 and 157: page reads, page writes, fresh pages."
  (list (rev14p-amem #o154) (rev14p-amem #o155) (rev14p-amem #o157)))
(defun rev14p-memory-words ()
  (system-communication-area %sys-com-memory-size))

(defvar *rev14p-rt* nil)
(defvar *rev14p-other* nil)
(defun rev14p-fill (n)
  (setq *rev14p-rt* (make-array n))
  (dotimes (i n) (aset i *rev14p-rt* i))
  n)
(defun rev14p-push (n)
  (setq *rev14p-other* (make-array n))
  (dotimes (i n) (aset i *rev14p-other* i))
  n)
(defun rev14p-verify (&aux (bad 0))
  (dotimes (i (array-length *rev14p-rt*) bad)
    (or (eq (aref *rev14p-rt* i) i) (incf bad))))
(defun rev14p-status (address)
  (let ((e (page-entry address))) (and e (ldb %%page-entry-status e))))
(defun rev14p-pages (array)
  "ARRAY's pages: (out with a slot, out with none, in core)."
  (let ((out 0) (no-slot 0) (in 0)
	(first (%pointer (aloc array 0))))
    (do ((a (* page-size (ceiling first page-size)) (+ a page-size)))
	((>= a (+ first (array-length array))) (list out no-slot in))
      (let ((e (page-entry a)))
	(cond ((>= (ldb %%page-entry-status e) 2) (incf in))
	      ((page-entry-slot e) (incf out))
	      (t (incf no-slot)))))))

(defvar *rev14p-fresh-origin* nil)
(defun rev14p-fresh-region ()
  (let* ((area (make-area :name (gensym) :region-size 1048576))
	 (x (make-array 10 :area area)))
    (setq *rev14p-fresh-origin* (region-origin (%region-number x)))))
(defun rev14p-fresh-read (from to &aux (bad 0))
  "Read the first word of pages FROM below TO of the fresh region: bad unless
each is its own address, the fresh fill."
  (do ((k from (1+ k))) ((= k to) bad)
    (let ((a (+ *rev14p-fresh-origin* (* k page-size))))
      (or (= (%p-ldb (byte 32 0) (rev14p-loc a)) a) (incf bad)))))
(defun rev14p-fresh-out (from to)
  "Of pages FROM below TO of the fresh region: (out with no slot, out with a slot)."
  (let ((none 0) (slot 0))
    (do ((k from (1+ k))) ((= k to) (list none slot))
      (let ((e (page-entry (+ *rev14p-fresh-origin* (* k page-size)))))
	(when (< (ldb %%page-entry-status e) 2)
	  (if (page-entry-slot e) (incf slot) (incf none)))))))

;;; PAGE-IN-WORDS after eviction, of an array in an ephemeral area (contract
;;; G3 revision 14, section 12's Y4 planted tests): its pages' slots are read
;;; from their entries (base-slot, page-in-words, sys/io/disk.lisp).
(defvar *rev14p-young* nil)
(defun rev14p-young-fill (n)
  (let ((area (make-area :name (gensym) :gc :dynamic :region-size #o200000)))
    (setf (area-region-bits area) (%logdpb 1 %%region-ephemeral (area-region-bits area)))
    (%use-up-region (area-region-list area))
    (setq *rev14p-young* (make-array n :area area))
    (dotimes (i n) (aset (- i) *rev14p-young* i))
    (list (= (ldb (byte 4 28) (%pointer *rev14p-young*)) #o15) n)))
(defun rev14p-young-in-core ()
  "Of the young array's whole pages: (in core, out)."
  (let ((in 0) (out 0) (first (%pointer (aloc *rev14p-young* 0))))
    (do ((a (%pointer-plus first (- page-size (logand first (1- page-size)))) (%pointer-plus a page-size)))
	((not (%pointer-lessp (%pointer-plus a page-size)
			      (%pointer-plus first (array-length *rev14p-young*))))
	 (list in out))
      (if (>= (ldb %%page-entry-status (page-entry a)) 2) (incf in) (incf out)))))
(defun rev14p-young-verify (&aux (bad 0))
  (dotimes (i (array-length *rev14p-young*) bad)
    (or (eq (aref *rev14p-young* i) (- i)) (incf bad))))

(mapc #'compile '(rev14p-young-fill rev14p-young-in-core rev14p-young-verify))

(mapc #'compile '(rev14p-loc rev14p-amem rev14p-word rev14p-counters rev14p-memory-words
		  rev14p-fill rev14p-push rev14p-verify rev14p-status rev14p-pages
		  rev14p-fresh-region rev14p-fresh-read rev14p-fresh-out))
