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
   ;; the associated machine, the default host to log in to and the
   ;; who-line's, is HOST, the file device, where SYS: is: a login then needs
   ;; no Chaos peer, and the home directory is HOST: /home/<user>/.
   ("LISPM-1" "Lisp Machine One" "MUIR" (muir 1) "HOST")
   ("LISPM-2" "Lisp Machine Two" "MUIR" (muir 1) "HOST")
   ("LISPM-3" "Lisp Machine Three" "MUIR" (muir 1) "HOST")
   ("LISPM-4" "Lisp Machine Four" "MUIR" (muir 1) "HOST")
   ("LISPM-5" "Lisp Machine Five" "MUIR" (muir 1) "HOST")
   ("LISPM-6" "Lisp Machine Six" "MUIR" (muir 1) "HOST")
   ("LISPM-7" "Lisp Machine Seven" "MUIR" (muir 1) "HOST")
   ))
