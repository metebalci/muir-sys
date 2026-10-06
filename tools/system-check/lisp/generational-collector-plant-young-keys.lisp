;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:10; Readtable:ZL -*-
;;; A planted partial fix for the check generational-collector (contract G3
;;; step 2, section 12, C16): young keys not flagged.  Given after
;;; lisp/generational-collector.lisp in --files, a table never learns that it
;;; holds a young key, so it does not rehash after a young flip: C16 (b) and
;;; (c) must fail (NIL and keys not found).  Not for any band in use.

(defun note-hash-key-young (hash-table generation)
  hash-table generation
  nil)
