;;; -*- Mode:LISP; Package:SI; Base:10; Lowercase:T -*-

;;; Revision 14's checks of the PDL buffer's fiddles against TLB eviction, the
;;; flip and the guard's count (tools/microcode-check/README.md,
;;; cases/rev14-fiddles.cases; contract G3 revision 14, section 12's Y2
;;; checks).  Definitions only; the cases call them.
;;;
;;; The PDL buffer dump and refill write a TLB entry directly (a fiddle) for
;;; the stack page they move.  A map-bit dispatch on a pointer whose page
;;; shares that entry's TLB index evicts the fiddle by its port-B fill; the
;;; next dump write then walks, loads the page's status-5 entry and is taken
;;; into the buffer, so memory never gets the word (the microcode's early A
;;; 430 and 431 copies keep the dumped words outside the buffer), and at
;;; status 6, under SET-MAR, the reload faults (the dump's and the refill's
;;; recovery, P-B-FIDDLE-AGAIN and P-R-FIDDLE-AGAIN).  A frame of pointers
;;; each aliasing its own stack word's TLB index makes every dump and refill
;;; write meet that eviction.

(defun rev14-loc (a) (%make-pointer dtp-locative a))
;; A memory and the register page through their windows (appendix a14.9)
(defun rev14-amem (k) (%p-ldb (byte 32 0) (rev14-loc (%make-pointer-unsigned (+ #o35700000000 k)))))
(defun rev14-word (k) (%p-ldb (byte 32 0) (rev14-loc (%make-pointer-unsigned (+ #o35777777400 k)))))
;; the TLB index of an address: its page number's low 12 bits (4,096 entries)
(defun rev14-idx (va) (ldb (byte 12 10) va))

;; a region of 4,096 pages, one for each TLB index
(defvar *rev14-alias-area* (make-area :name 'rev14-alias :region-size (* 4 1024 1024)))
(defvar *rev14-alias-origin*
	(region-origin (%region-number (make-array 10 :area *rev14-alias-area*))))

(defun rev14-alias-loc (va)
  "A locative into the alias region, on a page whose TLB index is VA's page's."
  (rev14-loc (+ *rev14-alias-origin* 5
		(* 1024 (ldb (byte 12 0) (- (rev14-idx va) (rev14-idx *rev14-alias-origin*)))))))

(defun rev14-switch ()
  "A stack-group switch, which dumps the whole PDL buffer; the return refills it."
  (let ((sg (make-stack-group "rev14")))
    (stack-group-preset sg #'(lambda () 7))
    (funcall sg)))

(defun rev14-where (expected &rest args) expected (%pointer args))
(defun rev14-hold (expected &rest args)
  (let ((at (%pointer args)))
    (rev14-switch)
    (list at (loop for a in args for e in expected count (not (eq a e))))))
;; x1: a bignum made by the multiply, held in the frame above the rest args,
;; in the extra PDL when made
(defun rev14-hold-x (expected &rest args)
  (let ((b (* 98765432109876543 (length args))))
    (let ((area-before (%area-number b)))
      (rev14-switch)
      (list (loop for a in args for e in expected count (not (eq a e)))
	    (= b (* 98765432109876543 (length args)))
	    area-before
	    (%area-number b)))))

(defun rev14-d1 (n &optional mar &aux p0 expected result)
  "D1 (D2 and R1 with MAR): N rest args, each pointing to a page that shares its
own stack word's TLB index, dumped by a switch and refilled; with MAR, SET-MAR
on a word of their stack page first (status 6).  Returns (stack address, the
address the hold saw, args that came back changed)."
  (setq p0 (apply #'rev14-where nil (make-list n)))
  (setq expected (loop for j below n collect (rev14-alias-loc (+ p0 j))))
  (when mar (set-mar (rev14-loc (+ p0 (floor n 2))) :write))
  (setq result (apply #'rev14-hold expected expected))
  (when mar (clear-mar))
  (list p0 (first result) (second result)))

(defun rev14-d0 (n &aux p0 expected result)
  "D1's control: the same frame with no alias."
  (setq p0 (apply #'rev14-where nil (make-list n)))
  (setq expected (loop for j below n collect (rev14-loc (+ *rev14-alias-origin* 5 j))))
  (setq result (apply #'rev14-hold expected expected))
  (list p0 (first result) (second result)))

(defun rev14-x1 (n &optional (alias t) &aux p0 expected)
  "X1: an extra-PDL bignum in the frame above N args, aliased or not.  Returns
(changed args, the bignum still equal, its area before, its area after)."
  (setq p0 (apply #'rev14-where nil (make-list n)))
  (setq expected (loop for j below n collect (if alias (rev14-alias-loc (+ p0 j)) (+ j 1))))
  (apply #'rev14-hold-x expected expected))

;;; the flip keeps the ephemeral-reference bit <19>: a region of its own, an
;;; array in it referenced from nowhere, its page's entry given <19> through
;;; the physical memory window, then %gc-flip of the region.  Returns the
;;; entry before and after and the two bits.
(defun rev14-phys-loc (pa) (rev14-loc (%make-pointer-unsigned (+ #o36000000000 pa))))
(defun rev14-entry-pa (va)
  (let ((d (%p-ldb (byte 32 0) (rev14-phys-loc (+ (* 1024 (rev14-word #o220)) (ldb (byte 12 20) va))))))
    (+ (* 1024 (ldb (byte 18 0) d)) (ldb (byte 10 10) va))))
(defun rev14-flip-test (&aux area va pa before after)
  (setq area (make-area :name (gensym) :region-size 16384))
  (setq va (%pointer (make-array 100 :area area)))
  (%p-ldb (byte 32 0) (rev14-loc va))		;in core
  (setq pa (rev14-entry-pa va))
  (%p-dpb 1 (byte 1 19) (rev14-phys-loc pa))
  (setq before (%p-ldb (byte 32 0) (rev14-phys-loc pa)))
  (%gc-flip (%region-number (rev14-loc va)))
  (setq after (%p-ldb (byte 32 0) (rev14-phys-loc pa)))
  (list before after (ldb (byte 1 19) before) (ldb (byte 1 19) after)))

;;; D1, D2/R1 and X1 by depth, compiled (a frame holds at most 256 words): each
;;; frame's eight locals point to pages whose TLB index is that of the local's
;;; own stack word (alias), or to one fixed word (the control).  At the bottom
;;; a stack-group switch dumps the whole PDL buffer; the returns refill it.
;;; With MAR, SET-MAR over the stack from the top frame to the bottom before the
;;; switch (status 6 on those pages), cleared at the top.  Every 50th frame
;;; holds a bignum made by the multiply (the extra PDL).
(defvar *rev14-alias* t)
(defvar *rev14-mar* nil)
(defvar *rev14-top* 0)
(defvar *rev14-depth* 0)
(defvar *rev14-bignums* 0)
(defvar *rev14-bignums-before* 0)
(defun rev14-val (loc)
  (if *rev14-alias* (rev14-alias-loc (%pointer loc)) (rev14-loc (+ *rev14-alias-origin* 5))))
(defun rev14-chk (v loc) (if (eq v (rev14-val loc)) 0 1))
(defun rev14-deep (depth &aux a b c d e f g h x)
  ;; the MAR's range starts at the first frame's locals (rev14-run's own frame
  ;; holds UNWIND-PROTECT's catch block, which Lisp writes in memory)
  (when (= depth *rev14-depth*) (setq *rev14-top* (%pointer (variable-location a))))
  (setq a (rev14-val (variable-location a)) b (rev14-val (variable-location b))
	c (rev14-val (variable-location c)) d (rev14-val (variable-location d))
	e (rev14-val (variable-location e)) f (rev14-val (variable-location f))
	g (rev14-val (variable-location g)) h (rev14-val (variable-location h)))
  (when (zerop (remainder depth 50)) (setq x (* 98765432109876543 (+ depth 1)))
    (when (= (%area-number x) extra-pdl-area) (incf *rev14-bignums-before*)))
  (let ((bad (cond ((plusp depth) (rev14-deep (1- depth)))
		   (t (when *rev14-mar*
			(set-mar (rev14-loc *rev14-top*) :write
				 (- (%pointer (variable-location a)) *rev14-top*)))
		      (rev14-switch)
		      0))))
    (when (and x (not (= x (* 98765432109876543 (+ depth 1)))))
      (setq bad (+ bad 100000)))
    (when (and x (= (%area-number x) extra-pdl-area))
      (incf *rev14-bignums*))
    (+ bad (rev14-chk a (variable-location a)) (rev14-chk b (variable-location b))
       (rev14-chk c (variable-location c)) (rev14-chk d (variable-location d))
       (rev14-chk e (variable-location e)) (rev14-chk f (variable-location f))
       (rev14-chk g (variable-location g)) (rev14-chk h (variable-location h)))))

(defun rev14-run (depth &optional (alias t) mar)
  "DEPTH frames as above.  Returns (bad words, the top's address, bignums in the
extra PDL before the switch, those still there after it)."
  (setq *rev14-alias* alias *rev14-mar* mar *rev14-bignums* 0 *rev14-bignums-before* 0)
  (setq *rev14-depth* depth)
  (list (unwind-protect (rev14-deep depth) (when mar (clear-mar)))
	*rev14-top* *rev14-bignums-before* *rev14-bignums*))

;; the depth runs compiled, as their frames must be; the functions that take
;; N args by APPLY stay interpreted, since a compiled frame holds at most 256
;; words ("Attempt to make a stack frame larger than 256. words")
(mapc #'compile '(rev14-loc rev14-amem rev14-word rev14-idx rev14-alias-loc rev14-switch
		  rev14-phys-loc rev14-entry-pa rev14-flip-test rev14-val rev14-chk
		  rev14-deep rev14-run))
