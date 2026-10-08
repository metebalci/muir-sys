;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:10; Readtable:ZL -*-
;;; For the check extra-pdl-locative (tools/system-check/README.md): a
;;; pointer into EXTRA-PDL-AREA held on the stack across a stack-group switch.
;;; The switch dumps the pdl buffer, and the dump's write test takes a pointer
;;; whose page's map says extra pdl for a stored extended number:
;;; EXTRA-PDL-TRAP (sys/ucadr/uc-transporter.lisp) copies the word it names as
;;; an object's header.  A locative to a word that is no header halts the
;;; machine at ILLOP, from SINFSH's dispatch.  The incremental save's compare
;;; (sys/io1/inc.lisp, COMPARE-RANGE and PAGE-TAGS-EQUAL) walked every page of
;;; memory by locatives, the extra pdl's among them, and a sequence break in
;;; that window halted generational-rqb at SINF-FLO; it now walks by fixnum
;;; addresses.  Definitions only; the cases call them.

(defun epl-page ()
  "The address, a fixnum, of the last page of EXTRA-PDL-AREA's region, above
its free pointer: no object of the extra pdl lies there.  Its words are made
fixnum 0, read and written by fixnum addresses, so that a word copied as an
object's header is none."
  (let* ((r (area-region-list extra-pdl-area))
	 (a (%pointer-plus (region-origin r) (- (region-length r) page-size))))
    (dotimes (w page-size)
      (%p-dpb 0 %%q-pointer (%pointer-plus a w))
      (%p-dpb dtp-fix #o4010 (%pointer-plus a w)))
    a))

(defvar epl-stack-group nil "The stack group EPL-SWITCH runs.")

(defun epl-switch ()
  "A stack-group switch and back: the caller's pdl buffer is dumped on the way."
  (unless epl-stack-group
    (setq epl-stack-group (make-stack-group "EPL")))
  (stack-group-preset epl-stack-group #'(lambda () t))
  (funcall epl-stack-group))

(defun epl-p-ldb ()
  "%P-LDB through a fixnum address reads the word there and transports
nothing: a cell made a one-q-forward to its neighbour reads back the forward's
own data type, and the cell read as an object reads the neighbour.
(the data type read, the value)."
  (let* ((v (make-array 2 :initial-element 1))
	 (cell (%pointer (locf (aref v 0)))))
    (setf (aref v 1) 2)
    (%p-store-tag-and-pointer (locf (aref v 0)) dtp-one-q-forward (locf (aref v 1)))
    (list (ldb #o0005 (%p-ldb #o4010 cell)) (aref v 0))))

(defun epl-hold ()
  "The incremental save's compare's own way, two pages' addresses as fixnums
held across a stack-group switch, then compared: (switched, equal)."
  (let* ((a (epl-page))
	 (b a)
	 (s (epl-switch)))
    (list s (page-tags-equal a b))))
