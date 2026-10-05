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
    ;; a block a read in a world of 256-word pages; in a 40-bit world, System
    ;; 2001's, the builder of revision 14's cross build, a page of the rqb is 4
    ;; blocks, which one read fills, so the copy steps 4 blocks and writes only
    ;; the blocks asked for (as cold:cross-copy-partition does); a block a read
    ;; there wrote each block four times over.
    (let ((rqb (si:get-disk-rqb 1))
	  (step (if (boundp 'si:disk-blocks-per-packed-page)
		    (symeval 'si:disk-blocks-per-page)
		  1)))
      (unwind-protect
	  (with-open-file (out file :direction :output :characters nil :byte-size 8)
	    (do ((i 0 (+ i step))) ((>= i n))
	      (si:disk-read rqb 0 (+ base i))
	      (send out :string-out (si:rqb-8-bit-buffer rqb) 0 (* 1024. (min step (- n i))))))
	(si:return-disk-rqb rqb))
      (list :blocks n :base base))))
