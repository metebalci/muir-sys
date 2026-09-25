;;; -*- Mode: Lisp; Package: SYSTEM-INTERNALS; Base: 10.; Readtable:T -*-

;;; Where each Lisp Machine of the MIT site is.
;;;
;;; Format is
;;; (name machine-name finger-location (building floor) associated-machine
;;;   site-keyword-overriding-alist)

(DEFCONST MACHINE-LOCATION-ALIST
 '(
   ;; one entry for each lisp machine in SYS: SITE; HOSTS TEXT, LISPM-1 to
   ;; LISPM-7, so that each prints its own name and location when it boots.
   ("LISPM-1" "Lisp Machine One" "MUIR" (MUIR 1) "OZ")
   ("LISPM-2" "Lisp Machine Two" "MUIR" (muir 1) "OZ")
   ("LISPM-3" "Lisp Machine Three" "MUIR" (muir 1) "OZ")
   ("LISPM-4" "Lisp Machine Four" "MUIR" (muir 1) "OZ")
   ("LISPM-5" "Lisp Machine Five" "MUIR" (muir 1) "OZ")
   ("LISPM-6" "Lisp Machine Six" "MUIR" (muir 1) "OZ")
   ("LISPM-7" "Lisp Machine Seven" "MUIR" (muir 1) "OZ")
   ))
