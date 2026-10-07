;;; -*- Mode:LISP; Package:USER; Base:10; Lowercase:T -*-

;;; Revision 14's ephemeral run (tools/system-check/README.md,
;;; cases/rev14-ephemeral.cases; contract G3 revision 14, section 12's Y4
;;; checks, and the GC study's 5.3 A): the workloads with the
;;; default cons area an ephemeral area, so that every object they make lies in
;;; ephemeral space, past 2^31 words, and with the ephemeral-reference setter's
;;; enable on (register-page word 221), so that real stores set it.  After
;;; them, the pages whose entry has <19> are read from the page table, to be
;;; compared with a replay of the run's stores (the setter's rule, A14.8).

(defun rev14e-loc (a) (%make-pointer dtp-locative a))
(defun rev14e-word-loc (k) (rev14e-loc (si:%make-pointer-unsigned (+ #o35777777400 k))))
(defun rev14e-word (k) (%p-ldb (byte 32 0) (rev14e-word-loc k)))
(defun rev14e-enable (on)
  "The setter's enable, register-page word 221 <0>."
  (%p-dpb (if on 1 0) (byte 1 0) (rev14e-word-loc #o221))
  (rev14e-word #o221))

(defvar *rev14e-area* nil)
(defvar *rev14e-nca* nil "NUMBER-CONS-AREA before the run.")
(defun rev14e-ephemeral-area ()
  "A new dynamic area flagged ephemeral (%%REGION-EPHEMERAL, contract G3
revision 14, 10.2) whose first region, made before the flag, is used up, so
that every region it takes from then on lies in ephemeral space."
  (let ((area (make-area :name 'rev14e-young :gc :dynamic :region-size #o200000)))
    (setf (si:area-region-bits area) (%logdpb 1 si:%%region-ephemeral (si:area-region-bits area)))
    (si:%use-up-region (si:area-region-list area))
    (setq *rev14e-area* area)))

(defun rev14e-young-p (x)
  "T if X lies in ephemeral space: its address's <31:28> 1101."
  (= (ldb (byte 4 28) (%pointer x)) #o15))

;;; muir-sim's profile workloads (examples/profile.rs), as S4 runs them
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

;;; the stores the setter is for: old objects made to point to young ones
;(defvar *rev14e-old* (make-array 2000 :area working-storage-area))
;; the old array is made in a dynamic area of its own: under the generational
;; collector working-storage-area is ephemeral, and an array made there is
;; young, which the control case finds (contract g3 step 2, 3.3)
(defvar *rev14e-old* (make-array 2000 :area (make-area :name 'rev14e-old :gc :dynamic)))
(defun rev14e-old-to-young (n)
  "N stores of young objects into an old array, and into an old symbol's value."
  (dotimes (i n)
    (aset (list i) *rev14e-old* (remainder i 2000))
    (setq *rev14e-last* (make-array 3)))
  (count-if #'rev14e-young-p *rev14e-old*))
(defvar *rev14e-last* nil)

(defun rev14e-marked-pages ()
  "Every page of every region whose entry has the ephemeral-reference bit <19>,
as octal page numbers (the address's <31:10>), in order, and the pages with an
entry looked at."
  (let ((marked nil) (seen 0))
    (dotimes (region si:size-of-area-arrays)
      (let ((origin (si:region-origin region))
	    (length (si:region-length region)))
	(when (and (plusp length)
		   (not (= (ldb si:%%region-space-type (si:region-bits region)) si:%region-space-free)))
	  (do ((k 0 (1+ k))) ((>= (* k si:page-size) length))
	    (let ((e (si:page-entry (%pointer-plus origin (* k si:page-size)))))
	      (when e
		(incf seen)
		(when (ldb-test si:%%page-entry-ephemeral-reference e)
		  (push (ldb (byte 22. 10.) (%pointer-plus origin (* k si:page-size))) marked))))))))
    (values (sort marked #'<) seen)))

(defun rev14e-marked-report ()
  "The marked pages, as one string of octal page numbers, and their count."
  (multiple-value-bind (pages seen) (rev14e-marked-pages)
    (list (length pages) seen (format nil "~{~O~^ ~}" pages))))

(defun rev14e-mar-trap-p (thunk)
  "T if calling THUNK signals the MAR's trap (eh:mar-break, a condition)."
  (condition-case ()
      (progn (funcall thunk) nil)
    (eh::mar-break t)))

(defun rev14e-bad-regions ()
  "The regions in use whose scavenger pointer (REGION-GC-POINTER) or free pointer
is not an offset within them: a free pointer past the length, or a gc pointer
past the free pointer, both unsigned.  UN-CONS once wrote an object's address
into the gc pointer of a region from 2^31 up."
  (loop for r below si:size-of-area-arrays
	unless (= (ldb si:%%region-space-type (si:region-bits r)) si:%region-space-free)
	  when (or (si:%pointer-lessp (si:region-length r) (si:region-free-pointer r))
		   (si:%pointer-lessp (si:region-free-pointer r) (si:region-gc-pointer r)))
	    collect (list r (si:%pointer-unsigned (si:region-origin r)) (si:region-length r)
			  (si:region-free-pointer r) (si:region-gc-pointer r))))

(defun rev14e-lc-names (file)
  """For each word address in FILE, one a line in decimal (the M4c monitor's
macroinstruction words), the octal address and what holds it: an FEF's
function name, else the data type of the structure there."""
  (with-open-file (s file)
    (loop for line = (readline s nil) while line
	  when (plusp (string-length line))
	    collect (let* ((w (parse-number line 0 nil 10.))
			   (h (%find-structure-header
				(%make-pointer dtp-locative (si:%make-pointer-unsigned w)))))
		      (list (format nil "~O" w)
			    (if (= (%data-type h) dtp-fef-pointer)
				(function-name h)
			      (nth (%data-type h) q-data-types)))))))

(mapc #'compile '(rev14e-bad-regions rev14e-mar-trap-p rev14e-lc-names rev14e-loc rev14e-word-loc rev14e-word rev14e-enable rev14e-young-p
		  rev14e-old-to-young rev14e-marked-pages rev14e-marked-report))
