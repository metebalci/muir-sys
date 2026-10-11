;;; -*- Mode:LISP; Package:USER; Base:10; Lowercase:T -*-

;;; A locative into the middle of an extra-pdl object, stored or saved
;;; (tools/microcode-check/README.md, cases/extra-pdl-interior.cases).  A
;;; bignum made by arithmetic lies in EXTRA-PDL-AREA until it is stored; a
;;; locative to one of its digits, stored into memory or dumped from the pdl
;;; buffer at a stack-group switch, trips the write test, and EXTRA-PDL-TRAP
;;; (sys/ucadr/uc-transporter.lisp) copies the bignum out.  It then read the
;;; header of the copy at the locative's own address, a digit, and SINFSH
;;; dispatched on that digit's header-type bits: a digit whose bits name no
;;; header type halted the machine in ILLOP (SINF-FLO), and any other gave a
;;; wrong size.  The cases take 2^21 cubed, 2^63, whose third word, its second
;;; digit, is 0, so the unchanged microcode halts and the case gets no answer.
;;; The functions must run compiled, so that the bignum and the locative stay
;;; on the pdl: loaded as source, the file compiles them.

(defvar *epi-array* (make-array 4))
(defvar *epi-stack-group* nil)

(defun epi-switch ()
  "A stack-group switch and back: the caller's pdl buffer is dumped on the way."
  (unless *epi-stack-group*
    (setq *epi-stack-group* (make-stack-group "EPI")))
  (stack-group-preset *epi-stack-group* #'(lambda () t))
  (funcall *epi-stack-group*))

(defun epi-digit (loc) (%p-ldb (byte 16 0) loc))

(defun epi-control (a)
  "The bignum A^3 is in the extra pdl, and its third word, a digit, reads the
same through a locative as through the bignum's own offset: (in the extra
pdl, the same, that word all 0, no header type)."
  (let* ((n (* (* a a) a))
	 (loc (%make-pointer-offset dtp-locative n 2)))
    (list (= (%area-number n) si:extra-pdl-area)
	  (= (epi-digit loc) (%p-ldb-offset (byte 16 0) n 2))
	  (and (zerop (%p-ldb (byte 16 0) loc)) (zerop (%p-ldb (byte 16 16) loc))))))

(defun epi-loc (a)
  "A locative to the third word of the bignum A^3, made in the extra pdl, and
that word's low 16 bits: the bignum itself is not kept."
  (let* ((n (* (* a a) a))
	 (loc (%make-pointer-offset dtp-locative n 2)))
    (values loc (epi-digit loc))))

(defun epi-out (loc digit)
  "LOC after its trap: (the digit as before, out of the extra pdl, still the
third word of its object)."
  (list (= digit (epi-digit loc))
	(not (= (%area-number loc) si:extra-pdl-area))
	(= (%pointer-difference loc (%find-structure-header loc)) 2)))

(defun epi-store (a)
  "The locative stored into an array, then read back: EPI-OUT of it."
  (multiple-value-bind (loc digit) (epi-loc a)
    (setf (aref *epi-array* 0) loc)
    (let ((s (aref *epi-array* 0)))
      (setf (aref *epi-array* 0) nil)
      (epi-out s digit))))

(defun epi-hold (a)
  "The locative held on the stack across a stack-group switch, whose dump of
the pdl buffer stores it: (switched, EPI-OUT of it)."
  (multiple-value-bind (loc digit) (epi-loc a)
    (let ((s (epi-switch)))
      (list s (epi-out loc digit)))))

(dolist (f '(epi-switch epi-digit epi-control epi-loc epi-out epi-store epi-hold))
  (unless (typep (fdefinition f) 'compiled-function)
    (compile f)))
