;;; -*- Mode:LISP; Package:USER; Base:10; Readtable:ZL -*-
;;; For the check mar-range (tools/system-check/README.md): an array over
;;; several pages, the MAR set over part of it, and whether a write traps.

(defvar *mar-array* (make-array 3000. :type 'art-q))

(defun mar-page-after (index)
  "The address of the first page boundary after element INDEX of *MAR-ARRAY*."
  (logand (+ (%pointer (aloc *mar-array* index)) (1- si:page-size)) (- si:page-size)))

(defun mar-index (address)
  "The index of the element of *MAR-ARRAY* at ADDRESS."
  (%pointer-difference address (aloc *mar-array* 0)))

(defun mar-trap-p (index)
  "T if writing element INDEX of *MAR-ARRAY* signals the MAR's trap (eh:mar-break,
a condition, not an error)."
  (condition-case ()
      (progn (setf (aref *mar-array* index) 1) nil)
    (eh::mar-break t)))

;;; A break proceeded rather than left by a throw: the condition-bind handler
;;; returns the proceed type :no-action, and the error handler does the write.
(defun mar-proceed-p (index)
  "T if writing element INDEX of *MAR-ARRAY* signals the MAR's trap, proceeded
with :no-action by a condition-bind handler, so that the write is done."
  (let ((hit nil))
    (condition-bind ((eh::mar-break #'(lambda (condition) condition (setq hit t) :no-action)))
      (setf (aref *mar-array* index) 1))
    hit))

(defun mar-set (from n-words)
  "Set the MAR, for writes, over the N-WORDS elements of *MAR-ARRAY* from FROM, its pages in core."
  (fill *mar-array* 0)
  (si:set-mar (aloc *mar-array* from) :write n-words)
  t)
