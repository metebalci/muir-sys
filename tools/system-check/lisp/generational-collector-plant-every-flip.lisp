;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:10; Readtable:ZL -*-
;;; A planted partial fix for the check generational-collector (contract G3
;;; step 2, section 12, C16): every table still rehashes after every flip, as
;;; before step 2.  Given after lisp/generational-collector.lisp in --files:
;;; C16 (a) and the FS:*PATHNAME-HASH-TABLE* case must fail (stale after a
;;; young flip).  Not for any band in use.

(defun hash-generation-stale-p (code)
  (not (= (if (< code -1) (- -2 code) code) %gc-generation-number)))
