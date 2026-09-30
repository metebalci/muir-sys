;;; -*- Mode:LISP; Package:COLD; Base:10; Lowercase:T; Readtable:ZL -*-

;;; The cross build's native control (tools/cross-check/README.md), for a
;;; cold-load generator without SYS: COLD; CROSS: make a cold load, answering
;;; its question, and copy the first blocks of a partition to a file, as
;;; cold:cross-make-cold and cold:cross-copy-partition do.

(defun xc-make-cold (part-name)
  (let ((old (symbol-function 'fquery)))
    (unwind-protect
	(progn (fset 'fquery #'(lambda (&rest ignore) t))
	       (make-cold part-name))
      (fset 'fquery old)))
  (list :highest vmem-highest-address :nil qnil :t qtruth))

(defun xc-copy-partition (part-name file n)
  (multiple-value-bind (base size) (si:find-disk-partition part-name)
    (setq n (min n size))
    (let ((rqb (si:get-disk-rqb 1)))
      (unwind-protect
	  (with-open-file (out file :direction :output :characters nil :byte-size 8)
	    (dotimes (i n)
	      (si:disk-read rqb 0 (+ base i))
	      (send out :string-out (si:rqb-8-bit-buffer rqb))))
	(si:return-disk-rqb rqb))
      (list :blocks n :base base))))
