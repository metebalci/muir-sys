;;; -*- Mode: Lisp; Package: SYSTEM-INTERNALS; Base: 10.; Readtable:T -*-

;;; Where each Lisp Machine of the MIT site is.
;;;
;;; Format is
;;; (name machine-name finger-location (building floor) associated-machine
;;;   site-keyword-overriding-alist)

(DEFCONST MACHINE-LOCATION-ALIST
 '(
   ("LISPM-1" "Lisp Machine One" "MUIR" (MUIR 1) "OZ")
   ))
