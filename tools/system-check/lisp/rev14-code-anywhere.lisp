;;; -*- Mode:LISP; Package:USER; Base:10; Lowercase:T -*-

;;; Revision 14's code anywhere (tools/system-check/README.md,
;;; cases/rev14-code-anywhere.cases; contract G3 revision 14, 10.4, LC's checks
;;; L1-L7 at the system level, with planted FEFs): MACRO-COMPILED-PROGRAM's
;;; next region is placed with the region floor across 2^30 words (LC<32>, a
;;; carry out of LC<31:0>), at 30000000000 (LC<33:32> = 11) or above 2^31
;;; (LC<33> = 1), filled to a few words below the boundary, and functions
;;; compiled there, their FEFs across it, are run.  LC is a byte address, so
;;; 2^30 words is LC's 2^32.

(defun rev14c-address (n) (si:%make-pointer-unsigned n))

(defun rev14c-place (origin words-below)
  "MACRO-COMPILED-PROGRAM's next region made at ORIGIN (the floor there while it
is made, then put back), and filled so that the next FEF starts WORDS-BELOW
words below ORIGIN + one quantum.  Returns that boundary's address, unsigned."
  (let ((area macro-compiled-program) (boundary (%pointer-plus (rev14c-address origin)
							       si:%address-space-quantum-size))
	x)
    (when (<= (si:area-region-size area) si:%address-space-quantum-size)
      (setf (si:area-region-size area) (* 4 si:%address-space-quantum-size)))
    (unwind-protect
	(progn (si:set-region-floor (rev14c-address origin))
	       (do ((r (si:area-region-list area) (si:region-list-thread r)))
		   ((minusp r))
		 (si:%use-up-region r))
	       ;; its pages are read-only, which the compiler's stores inhibit too
	       (setq x (let ((si:%inhibit-read-only t)) (make-array 1 :type 'art-32b :area area))))
      (si:set-region-floor))
    (let ((region (%region-number x)))
      (unless (= (si:%pointer-unsigned (si:region-origin region)) origin)
	(ferror nil "The region is at ~O, not ~O" (si:%pointer-unsigned (si:region-origin region)) origin))
      (do () (nil)
	(let ((gap (- (%pointer-difference boundary (%pointer-plus (si:region-origin region)
								  (si:region-free-pointer region)))
		      words-below)))
	  (when (<= gap 0) (return))
	  (let ((si:%inhibit-read-only t))
	    (make-array (max 0 (min (- gap 2) 4000)) :type 'art-32b :area area))))
      (si:%pointer-unsigned boundary))))

(defun rev14c-across (f boundary)
  "Where F's FEF lies against BOUNDARY: (:header-below T/NIL :code-start-above
T/NIL :end-above T/NIL), the code's start by its initial PC (a halfword index)."
  (let* ((fef (if (symbolp f) (fsymeval f) f))
	 (b (rev14c-address boundary))
	 (start (%pointer fef))
	 (code (%pointer-plus start (floor (si:fef-initial-pc fef) 2)))
	 (end (%pointer-plus start (si:%structure-total-size fef))))
    (list :header-below (si:%pointer-lessp start b)
	  :code-start-above (not (si:%pointer-lessp code b))
	  :end-above (si:%pointer-lessp b end))))

;;; L1, L2: a loop whose body spans the boundary: its backward branch from above
;;; to below borrows, the exit test's forward branch from below to above carries;
;;; a branch both short and long (the body's own COND)
(defun rev14c-id (x) x)
(defmacro rev14c-steps (n)
  ;; N steps adding 0 to N-1, each with a short forward branch never taken
  `(progn ,@(loop for i below n collect `(progn (setq s (+ s (rev14c-id ,i)))
						 (if (minusp s) (setq s 0))))))
(defun rev14c-loop-def ()
  (eval '(defun rev14c-loop (n)
	   (let ((s 0))
	     (dotimes (i n)
	       (rev14c-steps 100))
	     s)))
  (compile 'rev14c-loop))
(defun rev14c-loop-want (n) (* n 4950))

;;; L4: a call from above the boundary in an FEF that straddles it, and the
;;; return to it
(defun rev14c-callee (x) (* x 3))
(defun rev14c-caller-def ()
  (eval '(defun rev14c-caller (x)
	   (let ((s 0))
	     (rev14c-steps 100)
	     (+ s (rev14c-callee x)))))
  (compile 'rev14c-caller))

;;; L5: an FEF whose start PC lies past the boundary: many constants first
(defun rev14c-constants-def ()
  (eval `(defun rev14c-constants ()
	   (list ,@(loop for i below 120 collect `',(intern (format nil "REV14C-K~D" i))))))
  (compile 'rev14c-constants))

;;; L6: an unwind-protect continued (its cleanup run as the form returns) and
;;; one entered by a throw through it
(defvar *rev14c-cleanups* 0)
(defun rev14c-unwind-def ()
  (eval '(defun rev14c-unwind (throw)
	   (catch 'rev14c
	     (unwind-protect
		 (progn (when throw (throw 'rev14c :thrown)) :returned)
	       (incf *rev14c-cleanups*)))))
  (compile 'rev14c-unwind))

;;; L7: a sequence break deferred while interrupts are off, and taken when they
;;; come on, in code above 2^31: the scheduler's clock runs meanwhile
(defun rev14c-deferred-def ()
  (eval '(defun rev14c-deferred (n)
	   (let ((s 0))
	     (dotimes (k 20)
	       (without-interrupts
		 (dotimes (i n) (setq s (+ s 1))))
	       (process-allow-schedule))
	     s)))
  (compile 'rev14c-deferred))

(mapc #'compile '(rev14c-address rev14c-place rev14c-across rev14c-id rev14c-callee))
