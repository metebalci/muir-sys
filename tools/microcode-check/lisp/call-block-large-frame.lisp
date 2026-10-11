;;; -*- Mode:LISP; Package:USER; Base:10 -*-
;;; Call blocks opened above a large frame.  A call block holds its deltas to
;;; the active and open blocks in 8 bits (%%LP-CLS-DELTA-TO-ACTIVE-BLOCK 0010,
;;; %%LP-CLS-DELTA-TO-OPEN-BLOCK 1010, sys/cold/qcom.lisp), and past 255 they
;;; wrapped.  The microcode's two openers, CBM0 for macrocode calls and P3ZERO
;;; for its own calls out to Lisp, now signal STACK-FRAME-TOO-LARGE at
;;; %SPREAD's limit: the frame with the new block at most 370 octal (248)
;;; words, counted as %ASSURE-PDL-ROOM counts it, so the block's delta to the
;;; active block at most 249.
;;;
;;; CBLF-DEEP-N nests N calls in one compiled expression: each open call
;;; block is 4 words of temporaries in the frame, and the Kth is opened 4K
;;; words above it, 248 at the 62nd, 252 at the 63rd.  CBLF-REST4, compiled,
;;; nests 4 calls above an &rest frame of N arguments passed by a compiled
;;; caller (CBLF-CN): the fourth is N + 17 words above it, 249 at N = 232.
;;; CBLF-PLAIN stays interpreted: a compiled caller (CBLF-IN) gives it N
;;; arguments, and its entry (INTP1) opens APPLY-LAMBDA's call block with
;;; P3ZERO, N + 4 words above the frame, 249 at N = 245.  At 252 arguments and
;;; more that block is refused too, but the error handler's own frame, pushed
;;; where the block would have gone, wraps in the same way and the listener is
;;; lost: the limit that remains.  CBLF-IN-SG and CBLF-IN-PROCESS run a
;;; function in a stack group of its own and in a process, and return
;;; :TOO-LARGE if it signalled the error there.
;;;
;;; Load it as source, not with --compile: it compiles all but CBLF-PLAIN.
(defun cblf-1+ (x) (1+ x))
(defmacro cblf-nest (n) (if (zerop n) 0 `(cblf-1+ (cblf-nest ,(1- n)))))
(defmacro cblf-def-deep (name n) `(defun ,name () (cblf-nest ,n)))
(cblf-def-deep cblf-deep-62 62)
(cblf-def-deep cblf-deep-63 63)
(cblf-def-deep cblf-deep-64 64)
(cblf-def-deep cblf-deep-100 100)
(defun cblf-rest4 (&rest r) (cblf-1+ (cblf-1+ (cblf-1+ (cblf-1+ (length r))))))
(defmacro cblf-def-caller (name callee n)
  `(defun ,name () (,callee ,@(make-list n :initial-element 0))))
(cblf-def-caller cblf-c232 cblf-rest4 232)
(cblf-def-caller cblf-c233 cblf-rest4 233)
(cblf-def-caller cblf-c240 cblf-rest4 240)
(defun cblf-plain (&rest args) (length args))
(cblf-def-caller cblf-i245 cblf-plain 245)
(cblf-def-caller cblf-i246 cblf-plain 246)
(cblf-def-caller cblf-i251 cblf-plain 251)
(defun cblf-catch (f)
  (condition-case (e) (funcall f)
    (error (if (string-search "larger than 256" (send e :report-string))
	       :too-large
	       (send e :report-string)))))
(defun cblf-in-sg (f)
  (let ((sg (make-stack-group "cblf")))
    (stack-group-preset sg #'cblf-catch f)
    (funcall sg)))
(defvar *cblf-result* nil)
(defun cblf-in-process (f)
  (setq *cblf-result* nil)
  (process-run-function "cblf" #'(lambda (f) (setq *cblf-result* (cblf-catch f))) f)
  (process-wait-with-timeout "cblf" 3600. #'(lambda () *cblf-result*))
  *cblf-result*)
(mapc 'compile '(cblf-1+ cblf-deep-62 cblf-deep-63 cblf-deep-64 cblf-deep-100 cblf-rest4
		 cblf-c232 cblf-c233 cblf-c240 cblf-i245 cblf-i246 cblf-i251
		 cblf-catch cblf-in-sg cblf-in-process))
