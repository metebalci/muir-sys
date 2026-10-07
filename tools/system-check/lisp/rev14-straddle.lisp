;;; -*- Mode:LISP; Package:USER; Base:10; Lowercase:T -*-

;;; Revision 14's straddle runs (tools/system-check/README.md,
;;; cases/rev14-straddle-*.cases; contract G3 revision 14, 10.11, "Four
;;; straddle runs"): the workloads again, with one area's region placed across
;;; 2^31 words just before the workloads need it, so that their objects,
;;; stacks, RQBs or FEFs lie across 2^31.  The region floor is raised to one
;;; quantum below 2^31 while that region is made, and put back after.  One
;;; region can hold 2^31 at a time, so each run is its own session.

(defun rev14s-address (n) (si:%make-pointer-unsigned n))
(defvar *rev14s-two31* (rev14s-address #o20000000000))
(defvar *rev14s-floor* (rev14s-address #o17777740000))
;; what the cases keep between their forms: the region, the stack group, the RQB
(defvar *r* nil)
(defvar *s* nil)
(defvar *q* nil)

(defun rev14s-word (k)
  "Register-page word K (appendix a14.9)."
  (%p-ldb (byte 32 0) (%make-pointer dtp-locative (rev14s-address (+ #o35777777400 k)))))

(defun rev14s-across-p (region)
  "T if REGION holds the words 2^31 - 1 and 2^31."
  (let ((o (si:region-origin region)))
    (and (si:%pointer-lessp o *rev14s-two31*)
	 (si:%pointer-lessp *rev14s-two31* (%pointer-plus o (si:region-length region))))))

(defun rev14s-region-of (x) (%region-number x))

;; an area of its own, whose list and structure regions are made now, below the
;; floor, so that consing there later makes no region
(defvar *rev14s-other-area*
	(let ((a (make-area :name 'rev14s-other)))
	  (let ((default-cons-area a)) (cons nil nil))
	  (make-array 1 :area a)
	  a))
(defun rev14s-straddle (area kind)
  "Make AREA's next region of KIND (:list or :structure) lie across 2^31: its
regions used up, the floor one quantum below 2^31 while one object makes the
new region, the floor put back.  The region's size is raised to four quanta
when it is less.  Returns (the region, its origin unsigned, across-p)."
  (when (<= (si:area-region-size area) si:%address-space-quantum-size)
    (setf (si:area-region-size area) (* 4 si:%address-space-quantum-size)))
  (let (x)
    (unwind-protect
	(progn
	  (si:set-region-floor *rev14s-floor*)
	  (do ((r (si:area-region-list area) (si:region-list-thread r)))
	      ((minusp r))
	    (si:%use-up-region r))
	  ;; the microcode's cons caches (a-lcons-cache-*, a-scons-cache-*,
	  ;; uc-storage-allocation) keep the last area's region and its old
	  ;; limit: a list or a structure consed in another area first, so that
	  ;; the next one in AREA looks at its regions again
	  (let ((default-cons-area *rev14s-other-area*)) (cons nil nil))
	  (make-array 1 :area *rev14s-other-area*)
	  (setq x (if (eq kind :list)
		      (let ((default-cons-area area)) (cons nil nil))
		    (let ((si:%inhibit-read-only t))	;macro-compiled-program's pages
		      (make-array 1 :area area)))))
      (si:set-region-floor))
    (let ((r (rev14s-region-of x)))
      (list r (si:%pointer-unsigned (si:region-origin r)) (rev14s-across-p r)))))

;; the generational collector (contract g3 step 2, 3.3): working-storage-area
;; is ephemeral, so its conses go to eden, in ephemeral space above 2^31, and
;; never to a region the floor places: its next list region cannot be made to
;; lie across 2^31.  the list straddle run uses a dynamic list area of its own
;; instead, tenured, as working storage was before step 2, and conses the
;; workloads' lists there, with young collections on for the rest.
(defvar *rev14s-list-area* nil)
(defun rev14s-list-area ()
  (or *rev14s-list-area*
      (setq *rev14s-list-area*
	    (make-area :name 'rev14s-list :gc :dynamic :representation :list))))

(defun rev14s-free-address (region)
  (%pointer-plus (si:region-origin region) (si:region-free-pointer region)))

(defun rev14s-fill-below (region area kind words)
  "Fill REGION up to WORDS words below 2^31 with garbage of KIND, so that the
next objects of AREA lie across 2^31.  Returns the free address, unsigned."
  (let ((si:%inhibit-read-only t))		;macro-compiled-program's pages
    (do ()
	((not (si:%pointer-lessp (rev14s-free-address region)
				 (%pointer-plus *rev14s-two31* (- words)))))
      (let ((gap (- (%pointer-difference *rev14s-two31* (rev14s-free-address region)) words)))
	(if (eq kind :list)
	    (let ((default-cons-area area)) (make-list (max 1 (min gap 4000))))
	  (make-array (max 0 (min (- gap 2) 4000)) :type 'art-32b :area area)))))
  (si:%pointer-unsigned (rev14s-free-address region)))

;;; the workloads, muir-sim's profile workloads (examples/profile.rs)
(defun w-ack (m n) (cond ((zerop m) (1+ n)) ((zerop n) (w-ack (1- m) 1)) (t (w-ack (1- m) (w-ack m (1- n))))))
(defun w-fib (n) (if (< n 2) n (+ (w-fib (1- n)) (w-fib (- n 2)))))
(defun w-cons () (dotimes (i 10000) (make-list 200)))
(defun w-muldiv () (let ((s 0)) (dotimes (i 150000) (setq s (remainder (+ s (* i 7)) 1000003))) s))
(defun w-float () (let ((x 1.0)) (dotimes (i 50000) (setq x (+ (* x 1.0001) 0.5))) x))
(defun w-array () (let ((a (make-array 1000))) (dotimes (i 186) (dotimes (j 1000) (aset j a j) (aref a j)))))
(defun w-sort () (let ((l nil)) (dotimes (i 3000) (push (random 100000) l)) (sort l #'<)))
(defun w-bignum () (dotimes (i 21) (print (expt 3 300))))
(defun w-intern () (dotimes (i 1500) (intern (format nil "W-SYM-~D" i))))
(defun w-print () (dotimes (i 1000) (print i)))
(defun w-bitblt ()
  (let ((a (make-pixel-array 512 256 ':type 'art-1b)) (b (make-pixel-array 512 256 ':type 'art-1b)))
    (dotimes (i 40)
      (bitblt tv:alu-seta 480 200 a 0 0 b 0 0) (bitblt tv:alu-xor 480 200 a 3 5 b 17 1)
      (bitblt tv:alu-ior 100 50 a 1 0 b 40 9) (bitblt tv:alu-seta 32 32 a 0 0 b 33 2)
      (bitblt tv:alu-seta 480 200 b 0 8 b 0 0) (bitblt tv:alu-xor 480 200 b 0 0 b 5 8))))

(defun rev14s-workloads ()
  "Every workload, each checked; the list of those that failed."
  (let ((bad nil))
    (unless (= (w-ack 2 100) 203) (push 'ack bad))
    (unless (= (w-fib 20) 6765) (push 'fib bad))
    (w-cons)
    (unless (= (w-muldiv) (let ((s 0)) (dotimes (i 150000) (setq s (remainder (+ s (* i 7)) 1000003))) s))
      (push 'muldiv bad))
    (w-float)
    (w-array)
    (let ((l (w-sort))) (unless (and (= (length l) 3000) (loop for (a b) on l while b always (<= a b)))
			  (push 'sort bad)))
    (unless (= (expt 3 300) (* (expt 3 150) (expt 3 150))) (push 'bignum bad))
    (w-intern)
    (w-bitblt)
    (nreverse bad)))

(defun rev14s-compile-workloads ()
  (mapc #'compile '(w-ack w-fib w-cons w-muldiv w-float w-array w-sort w-bignum w-intern w-bitblt
		    rev14s-workloads))
  t)

;;; the PDL straddle: a stack group whose regular PDL lies across 2^31, and the
;;; workloads run in it
(defun rev14s-stack-group (size)
  (let ((sg (make-stack-group "rev14s" ':regular-pdl-size size ':special-pdl-size 4000)))
    (list sg (si:%pointer-unsigned (%pointer (si:sg-regular-pdl sg)))
	  (rev14s-across-p (%region-number (si:sg-regular-pdl sg))))))
(defun rev14s-in-stack-group (sg form)
  (stack-group-preset sg #'(lambda (f) (eval f)) form)
  (funcall sg))
(defun rev14s-array-across-p (array)
  "T if ARRAY's words hold 2^31 - 1 and 2^31."
  (let ((o (%pointer array)))
    (and (si:%pointer-lessp o *rev14s-two31*)
	 (si:%pointer-lessp *rev14s-two31* (%pointer-plus o (array-length array))))))

;;; the RQB straddle: RQBs taken until one lies across 2^31; reads into it
;;; compared with reads into an RQB below it
(defvar *rev14s-rqbs* nil)
(defun rev14s-align (region area)
  "Pad REGION's free pointer to a page boundary, as GET-DISK-RQB wants it."
  (let ((gap (remainder (- si:page-size (remainder (si:region-free-pointer region) si:page-size))
			 si:page-size)))
    (cond ((zerop gap))
	  ((<= (1- gap) si:%array-max-short-index-length)	;a header and GAP - 1 words
	   (make-array (1- gap) :type 'art-32b :area area))
	  (t (make-array (- gap 2) :type 'art-32b :area area))))
  (si:region-free-pointer region))
(defun rev14s-rqb-across-p (rqb pages)
  "T if RQB's data pages (si::rqb-data-pointer) hold the words 2^31 - 1 and 2^31."
  (let ((d (%pointer (si::rqb-data-pointer rqb))))
    (and (si:%pointer-lessp d *rev14s-two31*)
	 (si:%pointer-lessp *rev14s-two31* (%pointer-plus d (* pages si:page-size))))))
(defun rev14s-rqb-across (pages)
  "RQBs of PAGES pages taken (kept, so that the next is new) until one's data
lie across 2^31.  Returns it, or NIL after 64."
  (loop repeat 64
	for rqb = (si:get-disk-rqb pages)
	do (push rqb *rev14s-rqbs*)
	when (rev14s-rqb-across-p rqb pages) return rqb))
(defun rev14s-read-compare (rqb pages n)
  "N reads of PAGES pages of the current band into RQB and into a fresh RQB,
from block 0 on, compared: the reads that differ."
  (let ((other (si:get-disk-rqb pages)) (bad 0)
	(base (si:find-disk-partition (format nil "LOD~C" (ldb #o2010 si:current-loaded-band)))))
    (unwind-protect
	(dotimes (k n bad)
	  (let ((block (+ base (* k pages si:disk-blocks-per-page))))
	    (si:disk-read rqb 0 block)
	    (si:disk-read other 0 block)
	    (unless (loop for i below (array-length (si:rqb-buffer rqb))
			  always (= (aref (si:rqb-buffer rqb) i) (aref (si:rqb-buffer other) i)))
	      (incf bad))))
      (si:return-disk-rqb other))))

(mapc #'compile '(rev14s-address rev14s-word rev14s-across-p rev14s-region-of rev14s-straddle
		  rev14s-free-address rev14s-fill-below rev14s-stack-group rev14s-in-stack-group
		  rev14s-array-across-p rev14s-align rev14s-rqb-across-p rev14s-rqb-across rev14s-read-compare))
