;;; -*- Mode:LISP; Package:USER; Base:10; Lowercase:T -*-

;;; A stack group's saved accumulator holding a DTP-BODY-FORWARD
;;; (tools/microcode-check/README.md, cases/sg-saved-body-forward.cases).
;;; STRUCTURE-INFO leaves one in M-A after measuring a structure-forwarded
;;; object (SINFS-HFWD), and %P-LDB leaves the raw word it read in M-1; a
;;; process switch then saves it in the stack group's leader (SGLV).  A
;;; body-forward is relative to where it lies, so following it from a leader
;;; slot (TRANS-BFWD, from SG-LOAD-BLOCK-INTO-PDL-BUFFER's transport or the
;;; scavenger's) reads an unrelated address.
;;;
;;; SGF-POKE builds such a word by hand: a tenured ART-32B array's element 0
;;; holds a DTP-HEADER-FORWARD whose pointer is chosen so that following the
;;; body-forward from the slot lands on SGF-TARGET, an address in no region;
;;; the slot (SG-AC-A of a stack group that has run once) gets a body-forward
;;; to that element.  Microcode that follows it halts on the page fault in no
;;; region (PGF-NO-ENTRY's trap, taken where no trap can be: ILLOP), and the
;;; case gets no answer.

(defconst sgf-target (- (expt 2 31)))	;2^31 as a 32-bit address, in no region

(defvar *sgf-husk* nil)
(defvar *sgf-sg* nil)

(defun sgf-s32 (n)
  "N modulo 2^32 as a signed 32-bit fixnum, for %MAKE-POINTER."
  (let ((u (logand n (1- (expt 2 32)))))
    (if (>= u (expt 2 31)) (- u (expt 2 32)) u)))

(defun sgf-u32 (x) (logand (%pointer x) (1- (expt 2 32))))

(defun sgf-ephemeral-p (x) (= (ldb (byte 4 28) (%pointer x)) #b1101))

(defun sgf-slot (sg)
  (%make-pointer-offset dtp-locative sg
			(- (+ 2 (find-position-in-list 'si:sg-ac-a si:stack-group-head-leader-qs)))))

(defun sgf-make-sg ()
  (let ((sg (make-stack-group "SGF")))
    (stack-group-preset sg #'(lambda () (do () (nil) (stack-group-return 1))))
    (funcall sg)
    sg))

(defun sgf-setup ()
  "Preconditions: the target is in no region, the husk tenured, the stack group young."
  (setq *sgf-husk* (make-array 4 ':type 'art-32b ':area permanent-storage-area))
  (setq *sgf-sg* (sgf-make-sg))
  (list (null (%region-number (%make-pointer dtp-locative sgf-target)))
	(sgf-ephemeral-p *sgf-husk*)
	(sgf-ephemeral-p *sgf-sg*)))

(defun sgf-poke (sg)
  "Put the body-forward in SG's saved M-A; return the slot."
  (let* ((slot (sgf-slot sg))
	 (h (%make-pointer-offset dtp-locative *sgf-husk* 1)))
    ;; trans-bfwd: the address is the header-forward's pointer less (h - slot)
    (%p-store-tag-and-pointer h dtp-header-forward
			      (sgf-s32 (+ (logand sgf-target (1- (expt 2 32)))
					  (- (sgf-u32 h) (sgf-u32 slot)))))
    (%p-store-tag-and-pointer slot dtp-body-forward (%pointer h))
    slot))

(defun sgf-slot-word (sg)
  (let ((slot (sgf-slot sg)))
    (list (nth (%p-data-type slot) q-data-types)
	  (= (%p-pointer slot) (%pointer (%make-pointer-offset dtp-locative *sgf-husk* 1))))))

(defun sgf-clear (sg)
  (%p-store-tag-and-pointer (sgf-slot sg) dtp-fix 0)
  (%p-store-tag-and-pointer (%make-pointer-offset dtp-locative *sgf-husk* 1) dtp-fix 0)
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
  "A young collection while a young stack group's saved M-A is the body-forward:
whether the stack group was young and was copied, the slot's word after the
collection, and the value the stack group returns when resumed."
  (let ((sg (sgf-make-sg)) young old word v)
    (setq young (sgf-ephemeral-p sg) old (%pointer sg))
    (without-interrupts (sgf-poke sg))
    (si:gc-flip-now ':young)
    (si:gc-reclaim-oldspace)
    (setq word (sgf-slot-word sg))
    (without-interrupts (setq v (funcall sg)))
    (sgf-clear sg)
    (list young (not (= old (%pointer sg))) word v)))

