;;; -*- Mode:LISP; Package:USER; Base:10; Readtable:ZL -*-
;;; For the check wire-range (tools/system-check/README.md): an array over
;;; several pages, which pages of it WIRE-WORDS and WIRE-STRUCTURE wire, and
;;; which PAGE-OUT-WORDS offers for swapping out, read from each page's swap
;;; status.

(defvar *wire-array* (make-array 3000. :type 'art-q))

(defun wire-base ()
  "The address of the first page boundary after element 300 of *WIRE-ARRAY*,
so that the pages from 256 words below it to 1024 words above it are the array's."
  (logand (+ (%pointer (aloc *wire-array* 300.)) (1- si:page-size)) (- si:page-size)))

(defun wire-swap-status (address)
  "The swap status of the page holding ADDRESS, or NIL when it is not in core."
  (let ((sts (si:%page-status address)))
    (and sts (ldb si:%%pht1-swap-status-code sts))))

;; %page-status is open-coded by the compiler and is no function: compiled
;; here when the file is loaded as source
(unless (typep (fdefinition 'wire-swap-status) 'compiled-function)
  (compile 'wire-swap-status))

(defun wire-pages-with (status)
  "The pages of *WIRE-ARRAY* around WIRE-BASE whose swap status is STATUS, each
given as its offset from WIRE-BASE, -256 to 1024."
  (let ((base (wire-base)))
    (loop for offset from -256. to 1024. by si:page-size
	  when (eql (wire-swap-status (%pointer-plus base offset)) status)
	    collect offset)))

(defun wire-touch ()
  "Bring every page of *WIRE-ARRAY* in and make it normal: unwired, not flushable."
  (let ((base (wire-base)))
    (loop for offset from -256. to 1024. by si:page-size
	  do (si:unwire-page (%pointer-plus base offset))))
  (fill *wire-array* 0)
  t)

(defun wire-words-pages (offset size)
  "The pages that (WIRE-WORDS (+ WIRE-BASE OFFSET) SIZE) wires, as offsets from
WIRE-BASE; every page is unwired again after."
  (wire-touch)
  (si:wire-words (%pointer-plus (wire-base) offset) size)
  (prog1 (wire-pages-with si:%pht-swap-status-wired) (wire-touch)))

(defun wire-structure-pages ()
  "T if WIRE-STRUCTURE of *WIRE-ARRAY* wires every page of it, from its header's
to its last element's; every page is unwired again after."
  (wire-touch)
  (si:wire-structure *wire-array*)
  (prog1 (loop for p = (logand (%pointer *wire-array*) (- si:page-size))
		     then (%pointer-plus p si:page-size)
	       until (si:%pointer-lessp (aloc *wire-array* 2999.) p)
	       always (eql (wire-swap-status p) si:%pht-swap-status-wired))
	 (wire-touch)))

(defun page-out-words-pages (offset size)
  "The pages that (PAGE-OUT-WORDS (+ WIRE-BASE OFFSET) SIZE) makes flushable,
as offsets from WIRE-BASE; every page is made normal again after."
  (wire-touch)
  (si:page-out-words (%pointer-plus (wire-base) offset) size)
  (prog1 (wire-pages-with si:%pht-swap-status-flushable) (wire-touch)))
