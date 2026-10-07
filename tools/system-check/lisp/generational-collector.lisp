;;; -*- Mode:LISP; Package:USER; Base:10; Readtable:ZL -*-
;;; For the check generational-collector (tools/system-check/README.md): the
;;; generational collector's Lisp-visible checks (contract G3 step 2, section
;;; 12, C1-C22), their helpers, and two checkers the contract asks for, which
;;; other runs may also call:
;;; - the table checker (C6, 6.3), GENCOL-CHECK-TABLES: for every region with
;;;   a first-object table, each page's entry below the free pointer is an
;;;   object start at or below the page's first word, so that a walk by
;;;   %STRUCTURE-TOTAL-SIZE from it reaches the page;
;;; - the reclaim checker (C21), GENCOL-INSTALL-RECLAIM-CHECKER: before each
;;;   reclaim, a scan of every region that is not free or old finds no
;;;   pointer into oldspace (GENCOL-RECLAIM-VIOLATIONS).
;;; It needs step 2's microcode (E1) and a band built with step 2's Lisp (E3);
;;; written with E2 and not yet run, since neither exists.
;;;
;;; The cases make their collections themselves, with the GC process off:
;;; GENCOL-YOUNG-COLLECTION flips young and reclaims at once (batch), so the
;;; ages of objects are known.  A "tenured holder" is an array in a static
;;; area of this check's own (tenured, with a first-object table), whose
;;; slots hold the only reference to young objects.

(defvar *gencol-static-area* nil "A static structure area: tenured holders.")

(defun gencol-static-area ()
  (or *gencol-static-area*
      (setq *gencol-static-area*
	    (make-area :name 'gencol-static-area :gc :static :representation :structure))))

(defun gencol-holder (n)
  "A tenured array of N slots."
  (make-array n :area (gencol-static-area)))

(defun gencol-off ()
  "Turn off automatic garbage collection, so that the cases alone flip."
  (when si:gc-on (si:gc-off))
  t)

(defun gencol-young-collection ()
  "A young collection, flipped and reclaimed now."
  (si:gc-flip-now :young)
  (si:gc-reclaim-oldspace)
  t)

(defun gencol-young-collections (n)
  (dotimes (i n) (gencol-young-collection))
  t)

(defun gencol-tenured-collection ()
  "A tenured collection, flipped and reclaimed now."
  (si:gc-flip-now :tenured)
  (si:gc-reclaim-oldspace)
  t)

(defun gencol-generation (x)
  "The generation of the region X lies in: 0 tenured, 1 eden, 2 and 3 the survivor spaces."
  (si:region-generation (%region-number x)))

(defun gencol-young-p (x)
  (si:young-pointer-p x))

(defun gencol-below-ephemeral-space-p (x)
  (si:%pointer-lessp (%pointer x) si:ephemeral-space-virtual-address))

(defun gencol-list (n)
  "A fresh list of the fixnums below N, in the default cons area."
  (let ((l nil))
    (dotimes (i n) (push i l))
    l))

(defun gencol-sum (l)
  (let ((s 0))
    (dolist (x l) (incf s x))
    s))

(defun gencol-mark (address)
  "The ephemeral-reference bit, <19>, of the page table's entry for ADDRESS's page, or
NIL if the page is not in core."
  (let ((entry (si:%page-status address)))
    (and entry (ldb si:%%page-entry-ephemeral-reference entry))))

(defun gencol-table-code (table)
  "The HASH-TABLE-GC-GENERATION-NUMBER of hash table TABLE's array."
  (si:hash-table-gc-generation-number (symeval-in-instance table 'si:hash-array)))

;;; C1, C2: a tenured page as the only root
(defvar *gencol-holder* nil)

(defun gencol-c1-setup ()
  (setq *gencol-holder* (gencol-holder 10))
  (setf (aref *gencol-holder* 0) (gencol-list 10000))
  (gencol-young-p (aref *gencol-holder* 0)))

(defun gencol-c1-sum ()
  (gencol-sum (aref *gencol-holder* 0)))

;;; C3: a store after the walk passed the page.  The page is marked and holds
;;; no young pointer (one stored, then overwritten); the scavenger is
;;; stepped until the walk has cleared its mark; then a new young object is
;;; stored into it.
(defun gencol-c3 ()
  (let ((holder (gencol-holder 1000))
	(passed nil))
    (setf (aref holder 0) (gencol-list 10))
    (setf (aref holder 0) nil)
    (let ((inhibit-scavenging-flag t)
	  (si:inhibit-idle-scavenging-flag t))
      (si:gc-flip-now :young)
      (do ((i 0 (1+ i)))
	  ((or (eql (gencol-mark (aloc holder 0)) 0)
	       si:%gc-flip-ready
	       (> i 1000000.)))
	(si:%gc-scavenge 16.))
      (setq passed (eql (gencol-mark (aloc holder 0)) 0))
      (setf (aref holder 0) (gencol-list 1000))
      (si:gc-reclaim-oldspace))
    (gencol-young-collection)
    (list passed (gencol-sum (aref holder 0)))))

;;; C4: unboxed words that look like pointers.  A tenured ART-32B array whose
;;; data words carry the LIST tag and an eden address, and whose leader holds
;;; a young object.
(defun gencol-c4 ()
  (let* ((a (make-array 100 :type 'art-32b :leader-length 1 :area (gencol-static-area)))
	 (young (gencol-list 100))
	 (fake (%pointer young))
	 (data (%make-pointer-offset dtp-locative a 1)))
    (setf (array-leader a 0) young)
    (setq young nil)
    (dotimes (i 100)
      (%p-store-tag-and-pointer (%make-pointer-offset dtp-locative data i) dtp-list fake))
    (gencol-young-collections 3)
    (list (let ((same t))
	    (dotimes (i 100)
	      (let ((w (%make-pointer-offset dtp-locative data i)))
		(unless (and (= (%p-data-type w) dtp-list) (= (%p-pointer w) fake))
		  (setq same nil))))
	    same)
	  (gencol-sum (array-leader a 0)))))

;;; C5: an object across pages.  A young pointer in the fourth page of a
;;; 5,000-element tenured ART-Q array.
(defun gencol-c5 ()
  (let* ((a (gencol-holder 5000))
	 (page (+ 3 (ldb (byte 22. 10.) (%pointer a))))
	 (index (do ((i 0 (1+ i)))
		    ((= (ldb (byte 22. 10.) (%pointer (aloc a i))) page) i))))
    (setf (aref a index) (gencol-list 100))
    (gencol-young-collection)
    (list (< index 5000) (gencol-sum (aref a index)))))

;;; The table checker (C6; contract 6.3).
(defvar *gencol-table-failures* nil
  "The last check's failures: (REGION :WALK OFFSET) or (REGION PAGE ENTRY).")

(defun gencol-check-region-table (region)
  "The failures of REGION's first-object table, NIL if none."
  (let* ((fp (si:region-free-pointer region))
	 (org (%make-pointer dtp-locative (si:region-origin region)))
	 (table (si:region-first-object-table region))
	 (starts (make-array (1+ fp) :type 'art-1b))
	 (failures nil))
    ;; the object starts, walked from the origin
    (do ((i 0)) ((>= i fp))
      (let ((total (%structure-total-size (%make-pointer-offset dtp-locative org i))))
	(when (or (not (plusp total)) (> (+ i total) fp))
	  (push (list region :walk i) failures)
	  (return nil))
	(setf (aref starts i) 1)
	(incf i total)))
    ;; each page whose first word is below the free pointer
    (unless failures
      (do ((page 0 (1+ page)))
	  ((not (< (* page si:page-size) fp)))
	(let ((entry (aref table page)))
	  (unless (and (not (> entry (* page si:page-size)))
		       (= (aref starts entry) 1))
	    (push (list region page entry) failures)))))
    (return-array (prog1 starts (setq starts nil)))
    (nreverse failures)))

(defun gencol-check-tables (&optional area)
  "Check the first-object table of every region that has one, or of AREA's.  Returns the
failures, NIL if none."
  (let ((failures nil))
    (dotimes (region si:size-of-area-arrays)
      ;; an old region is left out: its objects are forwarded, and
      ;; %structure-total-size on a gc-forward word halts the machine
      ;; (xfshs1, ILLOP).  GC-RECLAIM-OLDSPACE-AREA keeps an area's only
      ;; region when it is old (sys/sys2/gc.lisp), so after a tenured
      ;; collection a few are left, gencol-c6b's area's among them; the walk
      ;; reads tables in new, copy and static regions only (scav-walk-1)
      (when (and (si:region-has-first-object-table-p region)
		 (not (= (ldb si:%%region-space-type (si:region-bits region)) si:%region-space-old))
		 (or (null area) (= (%area-number (si:region-origin region)) area)))
	(setq failures (nconc failures (gencol-check-region-table region)))))
    (setq *gencol-table-failures* failures)
    (length failures)))

;;; C6 (a): UN-CONS across a page boundary, then a cons on the fast path
;;; across it: bignum products, which the microcode conses at their largest
;;; and gives back with UN-CONS, among small arrays, in an area of their own
(defun gencol-c6a ()
  (let ((area (make-area :name 'gencol-c6a-area :gc :dynamic :representation :structure)))
    (let ((si:number-cons-area area)
	  (default-cons-area area))
      (dotimes (i 3000.)
	(* (expt 7 (+ 30 (random 60))) (expt 3 (+ 20 (random 60))))
	(make-array (random 30))))
    (gencol-check-tables area)))

;;; C6 (a), two give-backs in a row (clarification 13: UN-CONS clears the
;;; structure cons cache of a region with a table, since two give-backs could
;;; otherwise leave an entry inside a later object).  A bignum division whose
;;; quotient is a fixnum gives back storage twice, its temporary and then the
;;; quotient (BIDIV, BCLEANUP; uc-arith.lisp), with the region's free pointer
;;; placed at each of 64 offsets below a page boundary, and small arrays are
;;; made after each: a cache left after the give-backs serves them across the
;;; boundary on the fast path, without CONSF, and leaves the page's entry
;;; inside one of them.  The value is the checker's failures in the region
;;; after all 64: 0, and under E1's uncons-keeps-cache microcode not 0
;;; (measured), under which gencol-c6a above, products and small arrays,
;;; passes (measured: 0).
(defun gencol-c6a2 ()
  (let* ((area (make-area :name 'gencol-c6a2-area :gc :dynamic :representation :structure
			  :region-size #o400000))
	 (region (si:area-region-list area))
	 (x (expt 3 300))
	 (y (* (expt 3 200) (expt 7 50))))
    (loop for off from 2 to 65
	  do (let* ((fp (si:region-free-pointer region))
		    (gap (- (* si:page-size (ceiling (+ fp off 2) si:page-size)) fp off)))
	       (make-array (- gap 1) :area area)	;the free pointer OFF words below a boundary
	       (let ((si:number-cons-area area))
		 (truncate x y))
	       (dotimes (i 5) (make-array (+ 3 (* 7 i)) :area area))))
    (length (gencol-check-region-table region))))

;;; C6 (b): ADJUST-ARRAY-SIZE growing in place across three pages
;(defun gencol-c6b ()
;  (let* ((area (make-area :name 'gencol-c6b-area :gc :dynamic :representation :structure))
;	 (a (make-array 10 :area area))
;	 (b (adjust-array-size a 3500)))
;    (list (eq a b) (gencol-check-tables area))))
;;; the array is of the long format from the start: one of 10 elements is
;;; short, and growing it past %array-max-short-index-length (1023) changes
;;; the format, which ADJUST-ARRAY-SIZE does by a copy, never in place
;;; (sys/sys/qrand.lisp), so (eq a b) was NIL whatever the table.  1,100
;;; elements after the region's table hold page 1's first word; grown to
;;; 4,600 they hold pages 2, 3 and 4's, whose entries GC-RESET-FREE-POINTER
;;; writes.  A fresh table's entries are 0, the table's own start, which the
;;; checker takes (a walk from there reaches any page), so those entries are
;;; first made stale: three arrays after A hold pages 2, 3 and 4's first
;;; words, and are given back (RETURN-STORAGE moves the free pointer down and
;;; leaves their entries); without the write the entries are their starts,
;;; inside the grown array, and the checker fails 3.
(defun gencol-c6b ()
  (let* ((area (make-area :name 'gencol-c6b-area :gc :dynamic :representation :structure))
	 (a (make-array 1100 :area area)))
    (let* ((x1 (make-array 1000 :area area))
	   (x2 (make-array 1000 :area area))
	   (x3 (make-array 1000 :area area)))
      (return-storage (prog1 x3 (setq x3 nil)))
      (return-storage (prog1 x2 (setq x2 nil)))
      (return-storage (prog1 x1 (setq x1 nil))))
    (let ((b (adjust-array-size a 4600)))
      (list (eq a b) (gencol-check-tables area)))))

;;; C6 (c): MAKE-AREA-REGIONS-STATIC on a part-filled region
;(defun gencol-c6c ()
;  (let ((area (make-area :name 'gencol-c6c-area :gc :dynamic :representation :structure
;			 :region-size #o400000)))
;    (dotimes (i 300) (make-array 100 :area area))
;    (si:make-area-regions-static area)
;    (gencol-check-tables area)))
;;; as C6 (b), the entries of the pages above the free pointer are first made
;;; stale, by three arrays given back: FILL-UP-REGION must write each filler
;;; page's start; without it two of them are the given-back arrays' starts,
;;; inside a filler (the first array's start is the first filler's too)
(defun gencol-c6c ()
  (let ((area (make-area :name 'gencol-c6c-area :gc :dynamic :representation :structure
			 :region-size #o400000)))
    (dotimes (i 300) (make-array 100 :area area))
    (let* ((x1 (make-array 1000 :area area))
	   (x2 (make-array 1000 :area area))
	   (x3 (make-array 1000 :area area)))
      (return-storage (prog1 x3 (setq x3 nil)))
      (return-storage (prog1 x2 (setq x2 nil)))
      (return-storage (prog1 x1 (setq x1 nil))))
    (si:make-area-regions-static area)
    (gencol-check-tables area)))

;;; C7: stacks
(defvar *gencol-go* nil)
(defvar *gencol-result* nil)

(defun gencol-waiter ()
  (let ((l (gencol-list 1000)))
    (process-wait "Gencol wait" #'(lambda () *gencol-go*))
    (setq *gencol-result* (gencol-sum l))))

(defun gencol-c7a ()
  "A waiting process holds the only reference in a local."
  (setq *gencol-go* nil *gencol-result* nil)
  (process-run-function "Gencol waiter" #'gencol-waiter)
  (process-sleep 30)
  (gencol-young-collections 4)
  (setq *gencol-go* t)
  (process-wait-with-timeout "Gencol result" 600 #'(lambda () *gencol-result*))
  *gencol-result*)

(defun gencol-recurse (n)
  (if (zerop n)
      (gencol-young-collections 4)
    (progn (gencol-recurse (1- n)) n)))

(defun gencol-c7b ()
  "The current process holds the only reference deep in its stack."
  (let ((l (gencol-list 1000)))
    (gencol-recurse 300)
    (gencol-sum l)))

(defun gencol-plant (n)
  (let* ((a (gencol-list 10)) (b a) (c a) (d a))
    (if (zerop n)
	(length (list a b c d))
      (+ 0 (gencol-plant (1- n))))))

(defun gencol-c7c ()
  "Pointers to eden left above the stack's top, freed and then reused, are not followed."
  (let ((keep (gencol-list 1000)))
    (gencol-plant 300)
    (gencol-young-collections 3)
    (gencol-list 100000.)
    (gencol-young-collections 2)
    (gencol-sum keep)))

;;; C8: the special PDL
(defvar *gencol-special* nil)

(defun gencol-c8 ()
  (let ((*gencol-special* (gencol-list 1000)))
    (let ((*gencol-special* nil))
      (gencol-young-collections 4))
    (gencol-sum *gencol-special*)))

;;; C9: A memory.  SELF, bound here, holds the only reference; the collections
;;; run without interrupts, so no stack group switch saves it in a binding
;;; (the contract leaves the variable to E4).
(defun gencol-c9 ()
  (let ((self nil))
    (setq self (gencol-list 1000))
    (without-interrupts
      (gencol-young-collections 4))
    (gencol-sum self)))

;;; C10: ages
(defun gencol-c10 ()
  (let ((h (gencol-holder 1))
	(ages nil))
    (setf (aref h 0) (gencol-list 100))
    (dotimes (i 3)
      (gencol-young-collection)
      (push (gencol-generation (aref h 0)) ages))
    (append (nreverse ages)
	    (list (gencol-below-ephemeral-space-p (aref h 0)) (gencol-sum (aref h 0))))))

;;; C11: the soft cap, 100 K words, with 200 K live young words
(defun gencol-c11 ()
  (let ((si:gc-survivor-cap 102400.)
	(h (gencol-holder 20)))
    (dotimes (i 20) (setf (aref h i) (make-array 10000.)))
    (gencol-young-collection)
    (let ((first (gencol-generation (aref h 0))))
      (gencol-young-collection)
      (list first (gencol-generation (aref h 0)) (gencol-generation (aref h 19))))))

;;; C12: pretenuring
(defun gencol-c12 ()
  (let* ((big (make-array (* 1024 1024)))
	 (small (make-array 1024)))
    (list (gencol-below-ephemeral-space-p big) (gencol-young-p small)
	  (gencol-generation big))))

;;; C13: code
(defun gencol-c13 ()
  (let ((constant (gencol-list 100)))
    (compile 'gencol-c13-fn `(lambda () ',constant))
    (setq constant nil)
    (gencol-young-collections 4)
    (let ((f (fdefinition 'gencol-c13-fn)))
      (list (= (%area-number f) macro-compiled-program)
	    (gencol-below-ephemeral-space-p f)
	    (gencol-sum (funcall f))))))

;;; C16: hash tables
(defvar *gencol-symbols* '(car cdr cons list append nconc member assoc))

(defun gencol-c16a ()
  "An EQ table keyed by symbols: no young key; not stale after a young flip, stale after a
tenured one, and every key found."
  (let ((h (make-hash-table)))
    (dolist (s *gencol-symbols*) (puthash s t h))
    (let ((code (gencol-table-code h)))
      (gencol-young-collection)
      (let ((after-young (si:hash-generation-stale-p (gencol-table-code h))))
	(gencol-tenured-collection)
	(list (si:hash-generation-young-p code)
	      after-young
	      (si:hash-generation-stale-p (gencol-table-code h))
	      (let ((found t))
		(dolist (s *gencol-symbols*) (unless (gethash s h) (setq found nil)))
		found))))))

(defun gencol-keys-found (h keys)
  (let ((found t))
    (dolist (k keys) (unless (eq (gethash k h) k) (setq found nil)))
    found))

(defun gencol-c16b ()
  "An EQ table keyed by young conses finds every key after a young flip."
  (let ((h (make-hash-table))
	(keys nil))
    (dotimes (i 1000) (push (list i) keys))
    (dolist (k keys) (puthash k k h))
    (let ((young (si:hash-generation-young-p (gencol-table-code h))))
      (gencol-young-collection)
      (list young (gencol-keys-found h keys)))))

(defun gencol-c16c ()
  "An EQUAL table whose keys hold a young closure, hashed by its address."
  (let ((h (make-equal-hash-table))
	(keys nil))
    (dotimes (i 200) (push (list i (closure nil #'car)) keys))
    (dolist (k keys) (puthash k k h))
    (let ((young (si:hash-generation-young-p (gencol-table-code h))))
      (gencol-young-collection)
      (list young (gencol-keys-found h keys)))))

(defun gencol-pathname-table ()
  "E0's MG2: FS:*PATHNAME-HASH-TABLE*, the band's pathnames, holds no young key; a young
flip leaves it current."
  (gencol-young-collection)
  (let ((code (gencol-table-code fs:*pathname-hash-table*)))
    (list (si:hash-generation-young-p code) (si:hash-generation-stale-p code))))

;;; C17: a marked page swapped out before the flip
(defun gencol-c17 ()
  (let ((h (gencol-holder 2000)))
    (setf (aref h 1000) (gencol-list 1000))
    (si:page-out-words (aloc h 1000) 1)
    (let ((out (null (si:%page-status (aloc h 1000)))))
      (gencol-young-collection)
      (list out (gencol-sum (aref h 1000))))))

;;; C18: a bignum from the extra PDL stored into a tenured object during a
;;; young collection
(defun gencol-c18 ()
  (let ((h (gencol-holder 2)))
    (let ((inhibit-scavenging-flag t)
	  (si:inhibit-idle-scavenging-flag t))
      (si:gc-flip-now :young)
      (setf (aref h 0) (* most-positive-fixnum 12345.))
      (si:gc-reclaim-oldspace))
    (gencol-young-collections 2)
    (= (aref h 0) (* most-positive-fixnum 12345.))))

;;; C19: a tenured collection with young objects alive
(defun gencol-c19 ()
  (let ((h (gencol-holder 1)))
    (setf (aref h 0) (gencol-list 1000))
    (gencol-young-collection)
    (let ((first (gencol-generation (aref h 0))))
      (gencol-tenured-collection)
      (list first (gencol-generation (aref h 0)) (gencol-sum (aref h 0))))))

;;; C20: the incremental save, refused after a tenured flip only
(defun gencol-c20 ()
  (let ((generation si:%gc-generation-number))
    (gencol-young-collections 2)
    (let ((after-young (si:gc-tenured-flip-since-p generation)))
      (gencol-tenured-collection)
      (list after-young (si:gc-tenured-flip-since-p generation)))))

;;; The reclaim checker (C21).  Before each reclaim (SI:GC-BEFORE-RECLAIM-LIST)
;;; every word of every region that is not free, old or extra-pdl, nor a fixed
;;; region the scavenger leaves alone, is read without transport (%P-LDB,
;;; %P-POINTER, never %P-CONTENTS), structures object by object and only
;;; their boxed words, lists word by word; a word of a pointer type whose
;;; address lies in an old region is a violation.  The current stack group's
;;; regular and special PDLs are left out: their arrays' fill pointers are
;;; stale while it runs (A memory and the PDL buffer, transported at the
;;; flip and read through the transporter since, are not read either).
(defvar *gencol-reclaim-checks* 0)
(defvar *gencol-reclaim-violations* 0)
(defvar *gencol-reclaim-first* nil "The first violations: (REGION OFFSET ADDRESS).")
(defvar *gencol-peak-regions* 0)

(defun gencol-region-count ()
  (let ((n 0))
    (dotimes (region si:size-of-area-arrays)
      (unless (= (ldb si:%%region-space-type (si:region-bits region)) si:%region-space-free)
	(incf n)))
    n))

(defun gencol-check-word (address region offset)
  (when (si:%pointer-type-p (%p-ldb si:%%q-data-type address))
    (let ((r (%region-number (%p-pointer address))))
      (when (and r (= (ldb si:%%region-space-type (si:region-bits r)) si:%region-space-old))
	(incf *gencol-reclaim-violations*)
	(when (< (length *gencol-reclaim-first*) 10)
	  (push (list region offset (%p-pointer address)) *gencol-reclaim-first*))))))

(defun gencol-scan-for-oldspace-pointers ()
  (let ((skip (list (%pointer (%find-structure-leader (si:sg-regular-pdl si:%current-stack-group)))
		    (%pointer (%find-structure-leader (si:sg-special-pdl si:%current-stack-group))))))
    (dotimes (region si:size-of-area-arrays)
      (let* ((bits (si:region-bits region))
	     (space (ldb si:%%region-space-type bits)))
	(unless (or (= space si:%region-space-free)
		    (= space si:%region-space-old)
		    (= space si:%region-space-extra-pdl)
		    (and (= space si:%region-space-fixed)
			 (zerop (ldb si:%%region-scavenge-enable bits))))
	  (let ((org (%make-pointer dtp-locative (si:region-origin region)))
		(fp (si:region-free-pointer region)))
	    (if (= (ldb si:%%region-representation-type bits)
		   si:%region-representation-type-list)
		(dotimes (i fp)
		  (gencol-check-word (%make-pointer-offset dtp-locative org i) region i))
	      (do ((i 0)) ((>= i fp))
		(let* ((object (%make-pointer-offset dtp-locative org i))
		       (total (%structure-total-size object)))
		  (unless (plusp total)
		    (push (list region i :walk) *gencol-reclaim-first*)
		    (incf *gencol-reclaim-violations*)
		    (return nil))
		  (unless (memq (%pointer object) skip)
		    (dotimes (j (%structure-boxed-size object))
		      (gencol-check-word (%make-pointer-offset dtp-locative object j)
					 region (+ i j))))
		  (incf i total))))))))))

(defun gencol-check-no-oldspace-pointers ()
  (incf *gencol-reclaim-checks*)
  (setq *gencol-peak-regions* (max *gencol-peak-regions* (gencol-region-count)))
  (gencol-scan-for-oldspace-pointers))

(defun gencol-install-reclaim-checker ()
  (setq *gencol-reclaim-checks* 0 *gencol-reclaim-violations* 0 *gencol-reclaim-first* nil)
  (unless (member '(gencol-check-no-oldspace-pointers) si:gc-before-reclaim-list)
    (push '(gencol-check-no-oldspace-pointers) si:gc-before-reclaim-list))
  t)

(defun gencol-workload ()
  "Some consing of every kind, part of it kept by tenured holders."
  (let ((h (gencol-holder 100))
	(table (make-equal-hash-table)))
    (dotimes (i 100)
      (setf (aref h i) (list (make-array (random 200)) (gencol-list (random 300))
			     (format nil "string ~D" i) (* most-positive-fixnum i)))
      (puthash (list i (format nil "~D" i)) (aref h i) table)
      (gencol-list 2000))
    (setf (aref h 0) table)
    t))

;;; C22: no fixed region the scavenger leaves alone has a marked page
(defun gencol-raw-fixed-marked-pages ()
  (let ((marked nil))
    (dotimes (region si:size-of-area-arrays)
      (let ((bits (si:region-bits region)))
	(when (and (= (ldb si:%%region-space-type bits) si:%region-space-fixed)
		   (zerop (ldb si:%%region-scavenge-enable bits)))
	  (do ((offset 0 (+ offset si:page-size)))
	      ((not (< offset (si:region-free-pointer region))))
	    (let ((entry (si:page-entry (%pointer-plus (si:region-origin region) offset))))
	      (when (and entry (= 1 (ldb si:%%page-entry-ephemeral-reference entry)))
		(push (list region offset) marked)))))))
    marked))
