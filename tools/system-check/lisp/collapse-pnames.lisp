;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:10; Readtable:ZL -*-
;;; For the check collapse-pnames (tools/system-check/README.md): the
;;; temporary package COLLAPSE-DUPLICATE-PNAMES gives back
;;; (sys/sys2/gc.lisp).  It interns each symbol's pname in the package "GC
;;; Temporary" with INTERN-LOCAL, which makes a new symbol there for each
;;; first pname, and the loop moves some of those into WORTHLESS-SYMBOL-AREA,
;;; a static area the collector scans.  The package is then killed and its
;;; storage given back with RETURN-STORAGE: a symbol whose package cell still
;;; holds it points to storage given back, which becomes another object once
;;; consed again, and which the scavenger transports at the next flip.
;;; Definitions only; the cases call them.

(defvar *cp-tem* nil "The temporary package's address, a fixnum.")

(defun cp-returned-p (x)
  "T if X lies at or above its region's free pointer: storage given back."
  (let ((r (%region-number x)))
    (and r (>= (- (%pointer x) (region-origin r)) (region-free-pointer r)))))

(defun cp-holders ()
  "The symbols of NR-SYM and WORTHLESS-SYMBOL-AREA whose package is the
temporary package: (all of them, those in WORTHLESS-SYMBOL-AREA)."
  (let ((n 0) (w 0))
    (mapatoms-nr-sym
      #'(lambda (s)
	  (when (and s (= (%pointer (symbol-package s)) *cp-tem*))
	    (incf n)
	    (when (= (%area-number s) worthless-symbol-area) (incf w)))))
    (list n w)))

(defun cp-run ()
  "Make the package /"GC Temporary/", which COLLAPSE-DUPLICATE-PNAMES finds
and uses, run it, and return (the package's storage was given back, the
symbols whose package it still is: all, in WORTHLESS-SYMBOL-AREA)."
  (let ((tem (make-package "GC Temporary" :use () :size 50000.)))
    (setq *cp-tem* (%pointer tem))
    (collapse-duplicate-pnames)
    (cons (cp-returned-p tem) (cp-holders))))
