;;; -*- Mode:LISP; Package:USER; Base:10; Readtable:ZL -*-
;;; For the check fef-tags (tools/system-check/README.md): a function compiled
;;; to a QFASL and fasloaded, and a helper that reads the tags of an FEF's
;;; instruction words.

(defun fef-tags-sample (x y)
  (if (> x y) (list x y (* x y)) (cons y (+ x 1))))

(defun fef-tags-unboxed (fef)
  "The tags, <39:32>, of FEF's unboxed words, its instructions, as a list."
  (loop for i from (%structure-boxed-size fef) below (%structure-total-size fef)
	collect (%p-ldb-offset %%q-all-but-pointer fef i)))
