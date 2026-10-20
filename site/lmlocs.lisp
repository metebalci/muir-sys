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
   ;; who-line's, is FILES, the file device, where SYS: is: a login then needs
   ;; no Chaos peer, and the home directory is FILES: /home/<user>/.  it was
   ;; HOST, the file device's name before it became FILES.
   ("LISPM-1" "Lisp Machine One" "MUIR" (muir 1) "FILES")
   ("LISPM-2" "Lisp Machine Two" "MUIR" (muir 1) "FILES")
   ("LISPM-3" "Lisp Machine Three" "MUIR" (muir 1) "FILES")
   ("LISPM-4" "Lisp Machine Four" "MUIR" (muir 1) "FILES")
   ("LISPM-5" "Lisp Machine Five" "MUIR" (muir 1) "FILES")
   ("LISPM-6" "Lisp Machine Six" "MUIR" (muir 1) "FILES")
   ("LISPM-7" "Lisp Machine Seven" "MUIR" (muir 1) "FILES")
   ;; quux revision 16 (QUUX's Ethernet contract, section 5.6): LOCALHOST, the
   ;; name of a machine nothing else names, prints as "localhost", its
   ;; associated machine FILES like the others.
   ("LOCALHOST" "localhost" "(Unknown)" (unknown 0) "FILES")
   ))
