;;; -*- Mode:LISP; Package:SI; Base:10; Lowercase:T -*-

;;; The generational collector's microcode (contract G3 step 2, 9.1 items 1-7;
;;; tools/microcode-check/README.md, cases/generational.cases).  Definitions
;;; only; the cases call them.
;;;
;;; The cases drive the microcode itself, so that they run on any band of
;;; System 2002 under the collector's microcode: on E3's band, whose Lisp is
;;; the collector's, and on revision 14's band under a test variant of the
;;; microcode that boots it.  They reach the three new A-memory fixnums through
;;; A memory's window at their places, 143 (the words consed since the last
;;; flip), 144 (the promotion table) and 145 (the pretenuring threshold),
;;; after checking that those hold fixnums: under revision 14's microcode they
;;; are A-V-NIL, A-V-TRUE and A-FLOATING-ZERO, and nothing is written there.
;;; A young collection here is the microcode's: the promotion table written,
;;; (%gc-flip -1), then gc-reclaim-oldspace, which scavenges to the end (the
;;; marked-page walk included) and frees oldspace; automatic collection is off
;;; throughout.  An ephemeral area is one whose area bits carry
;;; %%region-ephemeral, its first region a tenured one, as make-area's :gc
;;; :ephemeral makes it.

(defun gen-loc (a) (%make-pointer dtp-locative a))
(defun gen-amem-loc (k) (gen-loc (%make-pointer-unsigned (+ #o35700000000 k))))
(defun gen-register (k) (%p-ldb (byte 32 0) (gen-loc (%make-pointer-unsigned (+ #o35777777400 k)))))

(defun gen-e1-p ()
  "T if A memory 143-145 hold fixnums: the generational collector's microcode."
  (and (= (%p-data-type (gen-amem-loc #o143)) dtp-fix)
       (= (%p-data-type (gen-amem-loc #o144)) dtp-fix)
       (= (%p-data-type (gen-amem-loc #o145)) dtp-fix)))

(defun gen-check-e1 ()
  (or (gen-e1-p) (ferror nil "This microcode has no generational collector (A memory 143-145).")))

(defun gen-words () (gen-check-e1) (%p-contents-offset (gen-amem-loc #o143) 0))
(defun gen-promotion () (gen-check-e1) (%p-contents-offset (gen-amem-loc #o144) 0))
(defun gen-threshold () (gen-check-e1) (%p-contents-offset (gen-amem-loc #o145) 0))
(defun gen-set-promotion (table)
  (gen-check-e1)
  (%p-store-contents (gen-amem-loc #o144) table))
(defun gen-set-threshold (n)
  (gen-check-e1)
  (%p-store-contents (gen-amem-loc #o145) n))

;;; promotion tables: bits <2g+1:2g> the destination of generation g (0
;;; tenured, 1 eden, 2 survivor space 1, 3 survivor space 2)
(defconst gen-normal-table (logior (lsh 2 2) (lsh 3 4)))	;eden to 1, 1 to 2, 2 to tenured
(defconst gen-cap-table (lsh 2 2))				;1 over the cap: to tenured
(defconst gen-tenure-all-table 0)

(defun gen-generation (x) (ldb (byte 2 5) (region-bits (%region-number x))))
(defun gen-region-generation (region) (ldb (byte 2 5) (region-bits region)))
(defun gen-space (region) (ldb %%region-space-type (region-bits region)))
(defun gen-in-ephemeral-space-p (x) (= (ldb (byte 4 28) (%pointer x)) #b1101))
(defun gen-mark (address)
  "<19> of the page table's entry for ADDRESS's page (appendix A14.2), or NIL if none."
  (let ((e (page-entry address))) (and e (ldb (byte 1 19) e))))

(defun gen-gc-off ()
  (when gc-on (gc-off))
  t)

(defvar *gen-eph* nil "An ephemeral area of 128 K-word regions.")
(defvar *gen-tab* nil "A dynamic area that is not ephemeral: tenured regions.")
(defvar *gen-static* nil "A static area: tenured holders of young objects.")

(defun gen-make-ephemeral-area (name)
  (let ((a (make-area :name name :region-size #o400000)))
    (setf (area-region-bits a) (%logdpb 1 %%region-ephemeral (area-region-bits a)))
    a))
(defun gen-eph-area () (or *gen-eph* (setq *gen-eph* (gen-make-ephemeral-area 'gen-eph))))
(defun gen-tab-area ()
  (or *gen-tab* (setq *gen-tab* (make-area :name 'gen-tab :region-size #o400000))))
(defun gen-static-area ()
  (or *gen-static* (setq *gen-static* (make-area :name 'gen-static :gc :static
						 :region-size #o400000))))

(defun gen-setup ()
  "Collection off; the test areas made.  T on the generational collector's microcode."
  (gen-gc-off)
  (gen-eph-area) (gen-tab-area) (gen-static-area)
  (gen-e1-p))

(defun gen-list (n area)
  "A fresh list of the fixnums below N in AREA."
  (let ((default-cons-area area) (l nil))
    (dotimes (i n) (push i l))
    l))
(defun gen-sum (l)
  (let ((s 0)) (dolist (x l) (incf s x)) s))

;;; the young collection
(defun gen-flip (&optional (table gen-normal-table))
  "A young flip with promotion table TABLE, not reclaimed."
  (gen-check-e1)
  (gen-gc-off)
  (without-interrupts
    (gen-set-promotion table)
    (setq ar-1-array-pointer-1 nil ar-1-array-pointer-2 nil)
    (%gc-flip -1)
    (setq gc-oldspace-exists t)
    ;; the symbol through a variable: a quoted one made the compiler warn of
    ;; a free variable on a band whose lisp has no gc-collection-kind
    (let ((kind 'gc-collection-kind))
      (when (boundp kind) (set kind :young))))
  t)
(defun gen-collect (&optional (table gen-normal-table))
  "A young collection with promotion table TABLE, flipped and reclaimed now."
  (gen-flip table)
  (gc-reclaim-oldspace)
  t)

;;; item 5: a structure-forwarded husk in a tenured region.  an array with a
;;; leader, tenured, grown by copying (adjust-array-size): its new copy is made
;;; in eden, and the husk's leader words, body-forwards, come before its
;;; header's header-forward to the copy.  the copy, held only by a local, is
;;; transported by the flip (the pdl buffer is a root), so its old words are
;;; gc-forwards when the walk scans the husk's page: following a leader
;;; word's body-forward through the header without transporting it halted the
;;; machine in illop (scav-walk-words; a compile of the system on step 2's
;;; first band), and the case gets no answer.
(defvar *gen-husk* nil)
(defun gen-husk-leader ()
  "(the array's generation once tenured, its copy's after growing, the leader's sum after
two young collections)"
  (let ((a (make-array 3000 :type 'art-16b :leader-length 8 :area (gen-eph-area)))
	(pad (make-array 10 :type 'art-16b :area (gen-eph-area))))
    (dotimes (i 8) (setf (array-leader a i) (gen-list (1+ i) (gen-eph-area))))
    ;; one list holds the array and a pad, so that each collection transports
    ;; the pad right after the array: tenured, the array is then not at the
    ;; end of its region, and adjust-array-size copies it (at the end it
    ;; grows in place and makes no husk)
    (setq *gen-husk* (list a pad))
    (setq a nil pad nil)
    (dotimes (k 4) (gen-collect))
    (let* ((gen (gen-generation (car *gen-husk*)))
	   (c (adjust-array-size (car *gen-husk*) 4000))
	   (copy-gen (gen-generation c)))
      (setq *gen-husk* nil)
      (gen-collect)
      (gen-collect)
      (list gen copy-gen (loop for i below 8 sum (gen-sum (array-leader c i)))))))

;;; item 7: the A-memory fixnums
(defun gen-a-memory ()
  "Whether A 143 and 144 hold fixnums, and A 145's fixnum, the pretenuring threshold."
  (list (= (%p-data-type (gen-amem-loc #o143)) dtp-fix)
	(= (%p-data-type (gen-amem-loc #o144)) dtp-fix)
	(and (= (%p-data-type (gen-amem-loc #o145)) dtp-fix)
	     (%p-contents-offset (gen-amem-loc #o145) 0))))

(defun gen-qcom-names ()
  "With qcom's names for them (a band of the collector's Lisp), their places: each
symbol's value forwarded to its A location; else T."
  (let ((names (loop for (name k) in '(("%GC-WORDS-CONSED-SINCE-FLIP" #o143)
				       ("%GC-PROMOTION" #o144) ("%GC-PRETENURE-THRESHOLD" #o145))
		     for s = (find-symbol name "SYSTEM")
		     when s collect (list s k))))
    (or (null names)
	(loop for (s k) in names
	      always (= (%p-pointer (value-cell-location s)) (%pointer (gen-amem-loc k)))))))

;;; item 1: the words consed since the last flip
(defun gen-words-delta ()
  "T if a list of 2000 words adds at least 2000 to the words consed, and at most 3000."
  (let* ((before (gen-words))
	 (l (make-list 2000))
	 (after (gen-words)))
    l
    (<= 2000 (- after before) 3000)))

;;; item 1: allocation by generation
(defun gen-young-cons ()
  "An array and a cons made in an ephemeral area: generation and place."
  (let ((x (make-array 10 :area (gen-eph-area)))
	(c (cons-in-area 1 2 (gen-eph-area))))
    (list (gen-generation x) (gen-in-ephemeral-space-p x)
	  (gen-generation c) (gen-in-ephemeral-space-p c))))

(defun gen-tenured-cons ()
  "An array and a cons made in an area that is not ephemeral."
  (let ((x (make-array 10 :area (gen-tab-area)))
	(c (cons-in-area 1 2 (gen-tab-area))))
    (list (gen-generation x) (gen-in-ephemeral-space-p x)
	  (gen-generation c) (gen-in-ephemeral-space-p c))))

(defun gen-area-first-region (area)
  (do ((r (area-region-list area) (region-list-thread r))
       (last nil r))
      ((minusp r) last)))

(defun gen-first-region-untouched ()
  "T if 100 arrays made in a new ephemeral area leave its first, tenured region as made."
  (let* ((a (gen-make-ephemeral-area (gensym)))
	 (r (gen-area-first-region a))
	 (fp (region-free-pointer r)))
    (dotimes (i 100) (make-array 100 :area a))
    (list (gen-region-generation r) (= fp (region-free-pointer r)))))

(defun gen-pretenure ()
  "A 64 K-word array in an ephemeral area, then a 10-word one and a 1 K-word one:
each one's generation and whether it lies in ephemeral space (C12)."
  (let* ((a (gen-make-ephemeral-area (gensym)))
	 (big (make-array 65536 :area a))
	 (small (make-array 10 :area a))
	 (one-k (make-array 1024 :area a)))
    (list (gen-generation big) (gen-in-ephemeral-space-p big)
	  (gen-generation small) (gen-in-ephemeral-space-p small)
	  (gen-generation one-k) (gen-in-ephemeral-space-p one-k))))

(defun gen-pretenure-edge ()
  "Arrays of 32768 and 32769 words (a long header and 32766 or 32767 elements): the
first is young, the second over the threshold."
  (let ((a (gen-make-ephemeral-area (gensym))))
    (list (gen-generation (make-array 32766 :area a))
	  (gen-generation (make-array 32767 :area a)))))

;;; item 2: the first-object table
(defun gen-table (region) (%make-pointer dtp-array-pointer (region-origin region)))
(defun gen-region-pages (region) (ceiling (%pointer-unsigned (region-length region)) page-size))

(defun gen-table-header-ok (region)
  (let ((h (gen-loc (region-origin region))))
    (and (= (%p-data-type h) dtp-array-header)
	 (= (ldb %%array-type-field (%p-pointer h)) (ldb %%array-type-field art-32b))
	 (= (ldb %%array-number-dimensions (%p-pointer h)) 1))))

(defun gen-new-region-table (area)
  "AREA's first region: its table's header is an art-32b array of one dimension, an
entry a page, entry 0 is 0, and the free pointer starts after it."
  (let ((r (gen-area-first-region area)))
    (if (not (gen-table-header-ok r))
	:no-table
      (let ((tab (gen-table r)))
	(list (= (array-length tab) (gen-region-pages r))
	      (aref tab 0)
	      (= (region-free-pointer r) (%structure-total-size tab)))))))

(defun gen-object-starts (region)
  "The offsets of REGION's objects below its free pointer, walked from its origin."
  (do ((origin (region-origin region))
       (fp (region-free-pointer region))
       (off 0 (+ off (%structure-total-size (gen-loc (%pointer-plus origin off)))))
       (starts nil (cons off starts)))
      ((>= off fp) (nreverse starts))))

(defun gen-table-exact (region)
  "T if every page of REGION below its free pointer has as its table entry the start of
the object holding the page's first word."
  ;; one pass over the starts, which are in order: the holder of page k's first
  ;; word is the last start at or below it (a search per page took minutes,
  ;; interpreted, on a region of thousands of objects)
  (let* ((tab (gen-table region))
	 (starts (gen-object-starts region))
	 (fp (region-free-pointer region)))
    (do ((k 0 (1+ k)))
	((>= k (ceiling fp page-size)) t)
      (let ((first (* k page-size)))
	(do () ((not (and (cdr starts) (<= (cadr starts) first))))
	  (pop starts))
	(or (eql (aref tab k) (and starts (<= (car starts) first) (car starts)))
	    (return nil))))))

(defun gen-table-entries ()
  "Arrays of mixed sizes across page boundaries in a new area's first region, then
whether its table's entries are exact."
  (let* ((a (make-area :name (gensym) :region-size #o400000))
	 (r (gen-area-first-region a)))
    (dolist (n '(1 500 1023 1024 1500 3 2047 2048 5000 100 4000 1 7000 2 3333))
      (make-array n :area a))
    (make-array 1000 :leader-length 5 :area a)
    (dotimes (i 50) (make-array (* 37 i) :area a))
    (list (= (gen-area-first-region a) r) (gen-table-exact r))))

(defun gen-big-region-table ()
  "A region of more than 1777 pages: a long header, and the table's own pages' entries 0."
  (let* ((a (make-area :name (gensym) :region-size (* 1100 page-size)))
	 (r (gen-area-first-region a))
	 (tab (gen-table r))
	 (pages (gen-region-pages r)))
    (list (gen-table-header-ok r)
	  (ldb-test %%array-long-length-flag (%p-pointer (gen-loc (region-origin r))))
	  (= (array-length tab) pages)
	  (aref tab 0) (aref tab 1)
	  (= (region-free-pointer r) (+ 2 pages)))))

(defun gen-young-no-table ()
  "A new ephemeral area's first young object lies at its eden region's origin: no table."
  (let ((x (make-array 10 :area (gen-make-ephemeral-area (gensym)))))
    (= (%pointer x) (region-origin (%region-number x)))))

(defun gen-big-object ()
  "An object as big as its area's regions (64 K words) fits a new region, its table
included, and the region's table is exact."
  (let* ((a (make-area :name (gensym) :region-size #o200000))
	 (x (make-array (- #o200000 2) :area a)))
    (list (= (%structure-total-size x) #o200000) (gen-table-exact (%region-number x)))))

;;; item 4: the young flip
(defun gen-flip-test ()
  "A young flip: an eden region becomes oldspace, a tenured new region does not, and the
words consed are cleared; then reclaimed."
  (let* ((yr (%region-number (make-array 10 :area (gen-eph-area))))
	 (tr (%region-number (make-array 10 :area (gen-tab-area))))
	 (result (progn (make-list 3000)
			(gen-flip)
			(list (gen-space yr) (gen-space tr) (< (gen-words) 1000)))))
    (gc-reclaim-oldspace)
    result))

;;; items 3-5: collections
(defun gen-ages ()
  "An eden object held only by a static array: its generation after 0, 1, 2 and 3 young
collections with the normal table (C10)."
  (let ((holder (make-array 1 :area (gen-static-area))))
    (setf (aref holder 0) (make-array 10 :area (gen-eph-area)))
    (let ((gens (list (gen-generation (aref holder 0)))))
      (dotimes (i 3)
	(gen-collect)
	(push (gen-generation (aref holder 0)) gens))
      (nreverse gens))))

(defun gen-tables ()
  "An eden object after one collection with the tenure-all table, and a survivor space 1
object after one with survivor space 1 over the cap."
  (let ((holder (make-array 2 :area (gen-static-area))))
    (setf (aref holder 0) (make-array 10 :area (gen-eph-area)))
    (gen-collect gen-tenure-all-table)
    (setf (aref holder 1) (make-array 10 :area (gen-eph-area)))
    (gen-collect)
    (let ((s1 (gen-generation (aref holder 1))))
      (gen-collect gen-cap-table)
      (list (gen-generation (aref holder 0)) s1 (gen-generation (aref holder 1))))))

(defun gen-c1 ()
  "A young list of 10,000 fixnums held only by a slot of a static array, not on its first
page: its sum after each of four young collections (C1)."
  (let ((holder (make-array 2000 :area (gen-static-area))))
    (setf (aref holder 1500) (gen-list 10000 (gen-eph-area)))
    (loop repeat 4
	  do (gen-collect)
	  collect (gen-sum (aref holder 1500)))))

(defun gen-c2 ()
  "The holder's page's mark: before a collection, after one (the list young in survivor
space 1), and after the list is tenured and one more walk (C2)."
  (let ((holder (make-array 2000 :area (gen-static-area))))
    (setf (aref holder 1500) (gen-list 100 (gen-eph-area)))
    (let ((loc (aloc holder 1500))
	  (marks nil))
      (push (gen-mark loc) marks)
      (gen-collect)
      (push (gen-mark loc) marks)
      (gen-collect) (gen-collect)
      (gen-collect)
      (push (gen-mark loc) marks)
      (list (nreverse marks) (gen-sum (aref holder 1500))))))

(defun gen-c3 ()
  "A store after the walk passed a page: the page marked and holding no young pointer is
scanned and cleared, the scavenger stepped until then; a new young list is stored into
it; the collection finishes, and one more: the list is intact (C3)."
  (let ((holder (make-array 2000 :area (gen-static-area))))
    (setf (aref holder 1500) (gen-list 10 (gen-eph-area)))
    (setf (aref holder 1500) nil)
    (let ((loc (aloc holder 1500))
	  (passed nil))
      (let ((inhibit-scavenging-flag t)
	    (inhibit-idle-scavenging-flag t))
	(gen-flip)
	(do ((i 0 (1+ i)))
	    ((or (eql (gen-mark loc) 0) %gc-flip-ready (> i 1000000)))
	  (%gc-scavenge 16))
	(setq passed (eql (gen-mark loc) 0))
	(setf (aref holder 1500) (gen-list 1000 (gen-eph-area)))
	(gc-reclaim-oldspace))
      (gen-collect)
      (list passed (gen-mark loc) (gen-sum (aref holder 1500))))))

(defun gen-c4 ()
  "A static art-32b array whose data words carry the list tag and an eden address, and
whose leader holds a young list: after three collections the data are unchanged and the
list intact (C4)."
  (let* ((a (make-array 100 :type 'art-32b :leader-length 1 :area (gen-static-area)))
	 (young (gen-list 100 (gen-eph-area)))
	 (fake (%pointer young))
	 (data (%make-pointer-offset dtp-locative a 1)))
    (setf (array-leader a 0) young)
    (setq young nil)
    (dotimes (i 100)
      (%p-store-tag-and-pointer (%make-pointer-offset dtp-locative data i) dtp-list fake))
    (gen-collect) (gen-collect) (gen-collect)
    (list (loop for i below 100
		for w = (%make-pointer-offset dtp-locative data i)
		always (and (= (%p-data-type w) dtp-list) (= (%p-pointer w) fake)))
	  (gen-sum (array-leader a 0)))))

(defun gen-c5 ()
  "A young list stored into the fourth page of a static 5000-element array: its sum after
two collections (C5)."
  (let ((holder (make-array 5000 :area (gen-static-area))))
    (setf (aref holder 3500) (gen-list 1000 (gen-eph-area)))
    (gen-collect) (gen-collect)
    (gen-sum (aref holder 3500))))

(defvar *gen-c7-go* nil)
(defvar *gen-c7-result* nil)
(defun gen-c7a ()
  "A waiting process holds the only reference to a young list in a local; two young
collections; it then sums it (C7 (a))."
  (setq *gen-c7-go* nil *gen-c7-result* nil)
  (let ((ready nil))
    (process-run-function "gen-c7a"
			  #'(lambda ()
			      (let ((l (gen-list 10000 (gen-eph-area))))
				(setq ready t)
				(process-wait "gen-c7a" #'(lambda () *gen-c7-go*))
				(setq *gen-c7-result* (gen-sum l)))))
    (process-wait "gen-c7a ready" #'(lambda () ready))
    (gen-collect) (gen-collect)
    (setq *gen-c7-go* t)
    (process-wait "gen-c7a done" #'(lambda () *gen-c7-result*))
    *gen-c7-result*))

(defun gen-c7b-deep (depth)
  (if (zerop depth)
      (progn (gen-collect) (gen-collect) 0)
    (1+ (gen-c7b-deep (1- depth)))))
(defun gen-c7b (depth)
  "The current process holds the only reference in a local of a frame DEPTH frames below
the one that collects (C7 (b))."
  (let ((l (gen-list 10000 (gen-eph-area))))
    (gen-c7b-deep depth)
    (gen-sum l)))

(defvar *gen-special* nil)
(defun gen-c8 ()
  "A young list held only as a binding's saved old value, across two collections, is
restored at unbinding (C8)."
  (setq *gen-special* (gen-list 10000 (gen-eph-area)))
  (let ((*gen-special* nil))
    (gen-collect) (gen-collect))
  (gen-sum *gen-special*))

;; a special, so that the product is made when the test runs, on the extra pdl:
;; compiled, (* 98765432109876543 3) is folded into a constant of the function,
;; which lies in a tenured area
(defvar *gen-c18-factor* 98765432109876543)

(defun gen-c18 ()
  "A bignum made on the extra PDL and stored into a static array during a young
collection is copied to its area's allocation generation, here eden; it survives two more
collections (C18)."
  (let ((holder (make-array 1 :area (gen-static-area)))
	(background-cons-area (gen-eph-area)))
    (gen-flip)
    (setf (aref holder 0) (* *gen-c18-factor* 3))
    (let ((g (gen-generation (aref holder 0))))
      (gc-reclaim-oldspace)
      (gen-collect) (gen-collect)
      (list g (= (aref holder 0) (* *gen-c18-factor* 3))))))

;;; item 5 at 2 M words of main memory (cases-2mw/generational-2mw.cases)
(defvar *gen-c17-push* nil)
(defun gen-c17 ()
  "A marked tenured page forced out of core before the flip (C17): after one collection,
its holder's page is marked and out (status 1), and the young list it alone holds is
intact after two more, so the walk scanned the page out of core."
  (let ((holder (make-array 2000 :area (gen-static-area))))
    (setf (aref holder 1500) (gen-list 10000 (gen-eph-area)))
    ;; one collection first, with the page in core: in the first collection
    ;; after the store the list is found without the walk (measured: with the
    ;; walk skipping pages out of core, two collections right after the store
    ;; kept the list; the region loop's pass over what was consed into the
    ;; static region since its last pass is the likely path), so the page is
    ;; forced out only after it
    (gen-collect)
    (let ((loc (aloc holder 1500)))
      ;; arrays of 1.5 M words, filled, force the holder's page out
      (dotimes (k 2)
	(setq *gen-c17-push* (make-array 1500000 :area (gen-tab-area)))
	(dotimes (i 1500000) (aset i *gen-c17-push* i)))
      (setq *gen-c17-push* nil)
      (let ((before (list (gen-mark loc) (ldb %%page-entry-status (page-entry loc)))))
	(gen-collect) (gen-collect)
	(list before (gen-sum (aref holder 1500)))))))

;;; item 2: un-cons and the cons cache
(defun gen-uncons-search ()
  "Bignum arithmetic in an area with a first-object table, which UN-CONS shrinks or gives
back (its results, its temporaries), with the free pointer placed at each of 64 offsets
below a page boundary, then small arrays made, which the cons cache serves: whether the
region's table stays exact after each."
  (let* ((a (make-area :name (gensym) :region-size #o400000))
	 (r (gen-area-first-region a))
	 (x (expt 3 300))
	 (y (* (expt 3 200) (expt 7 50))))
    (loop for off from 2 to 65
	  always (let* ((fp (region-free-pointer r))
			(gap (- (* page-size (ceiling (+ fp off 2) page-size)) fp off)))
		   (make-array (- gap 1) :area a)	;the free pointer OFF words below a boundary
		   (let ((number-cons-area a))
		     (gcd x y) (- x (1- x)) (* x y) (truncate x y) (gcd y x))
		   (dotimes (i 5) (make-array (+ 3 (* 7 i)) :area a))
		   (gen-table-exact r)))))

;;; P1 (clarification 11; the review of the first-object table, section 5): an
;;; RQB in a fresh table region.  DISK-BUFFER-AREA is static, so a region made
;;; for it begins with a first-object table, and MAKE-DISK-RQB, which needs its
;;; first array on a page boundary for the device's CCWs, pads the region up to
;;; one.  It needs the Lisp side's MAKE-DISK-RQB; with main's (no padding)
;;; the incremental compare and GET-DISK-RQB signal "... not on a page boundary".
(defun gen-rqb-ccw (rqb i)
  "The physical address CCW I of RQB names, its chain bit cleared."
  (logand (- page-size)
	  (+ (aref rqb (+ %disk-rq-ccw-list (* 2 i)))
	     (lsh (aref rqb (+ %disk-rq-ccw-list 1 (* 2 i))) 16.))))

(defun gen-p1 ()
  "Every DISK-BUFFER-AREA region used up, then the incremental save's compare and
(get-disk-rqb 16): (the compare returns, the RQB is made, the new region begins with a
table header, RQB-BUFFER and the data on page boundaries, the data where WIRE-DISK-RQB
puts the CCWs, each CCW the frame of its data page, the region's table exact)."
  (do ((r (area-region-list disk-buffer-area) (region-list-thread r)))
      ((minusp r))
    (%use-up-region r))
  (let ((inc (condition-case (e)
		 (progn (disk-save-incremental (find-disk-partition "LOD2")) t)
	       (error (send e :report-string))))
	(rqb (condition-case (e) (get-disk-rqb 16.) (error (send e :report-string)))))
    (if (stringp rqb)
	(list inc rqb)
      (unwind-protect
	  (let* ((buffer (array-leader rqb %disk-rq-leader-buffer))
		 (region (%region-number buffer))
		 (origin (region-origin region))
		 ;; the data: the RQB array's last 16 pages
		 (data (%pointer-plus rqb (- (+ 1 (%p-ldb %%array-long-length-flag rqb)
						(floor (array-length rqb) 2))
					     (* 16. page-size)))))
	    (wire-disk-rqb rqb)
	    (list inc t
		  (and (= (%p-data-type origin) dtp-array-header)
		       (= (%p-ldb %%array-type-field origin) (ldb %%array-type-field art-32b)))
		  (zerop (logand (1- page-size) (%pointer buffer)))
		  (zerop (logand (1- page-size) data))
		  (= data (%pointer (rqb-data-pointer rqb)))
		  (loop for i below 16.
			always (= (gen-rqb-ccw rqb i)
				  (logand (- page-size)
					  (%physical-address (%pointer-plus data (* i page-size))))))
		  (gen-table-exact region)))
	(return-disk-rqb rqb)))))
