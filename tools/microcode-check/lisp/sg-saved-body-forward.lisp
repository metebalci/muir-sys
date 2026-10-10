;;; -*- Mode:LISP; Package:USER; Base:10; Lowercase:T -*-

;;; A stack group's saved accumulator holding a DTP-BODY-FORWARD
;;; (tools/microcode-check/README.md, cases/sg-saved-body-forward.cases).
;;; STRUCTURE-INFO leaves one in M-A after measuring a structure-forwarded
;;; object (SINFS-HFWD): %STRUCTURE-TOTAL-SIZE of a stale pointer to an array
;;; that ADJUST-ARRAY-SIZE grew by copying, as ARRAY-PUSH-EXTEND does with the
;;; array it is given.  A process switch saves M-A in the stack group's leader
;;; (SGLV).  A body-forward is relative to where it lies, so following it from
;;; a leader slot (TRANS-BFWD, from SG-LOAD-BLOCK-INTO-PDL-BUFFER's transport
;;; or the scavenger's) reads an unrelated word and goes on with it.
;;;
;;; SGF-POKE builds such a word by hand, so that the unrelated word is one
;;; this file chose: a static ART-32B array's element 0 holds a
;;; DTP-HEADER-FORWARD whose pointer is chosen so that following the
;;; body-forward from the slot lands on its element 2, which holds a
;;; DTP-GC-FORWARD; the slot (SG-AC-A of a stack group that has run once)
;;; gets a body-forward to element 0.  Microcode that follows it meets the
;;; GC-FORWARD in the transporter's dispatch, which halts in ILLOP, and the
;;; case gets no answer.  SGF-NATURAL is no check: it lets a process measure
;;; a stale pointer in a loop and reads the type of the M-A it saved.

(defvar *sgf-husk* nil)
(defvar *sgf-sg* nil)

(defun sgf-s24 (n)
  "N modulo 2^24 as a signed 24-bit fixnum, for %MAKE-POINTER."
  (let ((u (logand n (1- (expt 2 24)))))
    (if (>= u (expt 2 23)) (- u (expt 2 24)) u)))

(defun sgf-u24 (x) (logand (%pointer x) (1- (expt 2 24))))

(defun sgf-slot (sg)
  (%make-pointer-offset dtp-locative sg
			(- (+ 2 (find-position-in-list 'si:sg-ac-a si:stack-group-head-leader-qs)))))

(defun sgf-make-sg ()
  (let ((sg (make-stack-group "SGF")))
    (stack-group-preset sg #'(lambda () (do () (nil) (stack-group-return 1))))
    (funcall sg)
    sg))

(defun sgf-static-p (x)
  (= (ldb si:%%region-space-type (si:region-bits (%region-number x))) si:%region-space-static))

(defun sgf-setup ()
  "Preconditions: the husk static, the stack group dynamic."
  (setq *sgf-husk* (make-array 4 ':type 'art-32b ':area permanent-storage-area))
  (setq *sgf-sg* (sgf-make-sg))
  (list (sgf-static-p *sgf-husk*) (sgf-static-p *sgf-sg*)))

(defun sgf-poke (sg)
  "Put the body-forward in SG's saved M-A; return the slot."
  (let* ((slot (sgf-slot sg))
	 (h (%make-pointer-offset dtp-locative *sgf-husk* 1))
	 (x (%make-pointer-offset dtp-locative *sgf-husk* 3)))
    (%p-store-tag-and-pointer x dtp-gc-forward (%pointer x))
    ;; trans-bfwd: the address is the header-forward's pointer less (h - slot)
    (%p-store-tag-and-pointer h dtp-header-forward
			      (sgf-s24 (+ (sgf-u24 x) (- (sgf-u24 h) (sgf-u24 slot)))))
    (%p-store-tag-and-pointer slot dtp-body-forward (%pointer h))
    slot))

(defun sgf-slot-word (sg)
  (let ((slot (sgf-slot sg)))
    (list (nth (%p-data-type slot) q-data-types)
	  (= (%p-pointer slot) (%pointer (%make-pointer-offset dtp-locative *sgf-husk* 1))))))

(defun sgf-clear (sg)
  (%p-store-tag-and-pointer (sgf-slot sg) dtp-fix 0)
  (dotimes (i 4) (%p-store-tag-and-pointer (%make-pointer-offset dtp-locative *sgf-husk* (1+ i)) dtp-fix 0))
  t)

(defun sgf-resume ()
  "Resume a stack group whose saved M-A is the body-forward: the value it returns."
  (let ((sg *sgf-sg*) v)
    (without-interrupts
      (sgf-poke sg)
      (setq v (funcall sg)))
    (sgf-clear sg)
    v))

(defun sgf-collect ()
  "A flip with a stack group in dynamic space: the flip's transport copies it,
its copy gets the body-forward in its saved M-A, and the reclaim scavenges the
copy (SCAVL3).  Whether it was copied, the slot's word after the reclaim, and
the value the stack group returns when resumed."
  (let ((sg (sgf-make-sg)) old word v)
    (setq old (%pointer sg))
    (si:gc-flip-now)
    (without-interrupts (sgf-poke sg))
    (si:gc-reclaim-oldspace)
    (setq word (sgf-slot-word sg))
    (without-interrupts (setq v (funcall sg)))
    (sgf-clear sg)
    (list (not (= old (%pointer sg))) word v)))

(defun sgf-natural (n)
  "A stale pointer to an array grown by copying, measured in a loop by a
process: whether it is the husk, and the data type of the process's saved M-A
at N samples, 2 ticks apart."
  (let* ((a (make-array 10))
	 (b (make-array 10)))
    (adjust-array-size a 2000)
    (let ((p (process-run-function "SGF natural"
				   #'(lambda (h) (do () (nil) (%structure-total-size h)))
				   a))
	  (types nil))
      (dotimes (i n)
	(process-sleep 2)
	(push (nth (%p-data-type (sgf-slot (process-stack-group p))) q-data-types) types))
      (send p ':kill)
      (list (= (%p-data-type a) dtp-header-forward) (length b) (nreverse types)))))
