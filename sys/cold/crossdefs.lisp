;;; -*- Mode:LISP; Package:COLD; Base:10; Lowercase:T; Readtable:ZL -*-

;;; The tree's compile-time definitions that the cross build gives every
;;; compile for the target (cold:cross-begin, sys/cold/cross.lisp): each
;;; (file kind name status), status :new, :changed, :gone (the builder's
;;; system has it and the tree does not), or :floats (a macro or defsubst of the
;;; same text that holds a float literal, which the builder read with its
;;; own floats).  Written by tools/cross-check/crossdefs.py
;;; from the sources; run it again after a change, since the cross build
;;; checks that this list is what the sources give.

(setq *cross-definitions* '(
  ("SYS: DEMO; COLORHACK" defmacro "CLIP-ON-PLANE" :floats)
  ("SYS: SYS; QMISC" defmacro "MAYBE-GROW-IO-STRING" :floats)
  ("SYS: SYS2; HASH" defsubst "HASH-TABLE-MAXIMAL-FULLNESS" :floats)
  ("SYS: SYS2; NUMDEF" defsubst "ZERO-OF-TYPE" :floats)
  ("SYS: WINDOW; SUPDUP" defmacro "ARDS-LOOP" :floats)
  ("SYS: WINDOW; SUPDUP" defmacro "ARDS-COORD" :floats)
  ))

;;; The tree's special variables that the builder's system has not, which
;;; the cross build proclaims special in the builder while it compiles for
;;; the target (cold:cross-begin): each (file kind name status), status
;;; :special, or :gone (the builder's system has it and the tree does not),
;;; which the cross build refuses.

(setq *cross-specials* '(
  ("SYS: COLD; COLDUT" defvar "AREA-FIRST-OBJECT-TABLE-HEADERS" :special)
  ("SYS: COLD; COLDUT" defvar "AREA-OBJECT-STARTS" :special)
  ("SYS: COLD; CROSS" defvar "*CROSS-MADE-SPECIAL*" :special)
  ("SYS: COLD; CROSS" defvar "*CROSS-SPECIALS*" :special)
  ("SYS: SYS; QMISC" defconst "MARK-BITMAP-BITS-PER-PAGE" :special)
  ("SYS: SYS; QRAND" defvar "SXHASH-HASHED-YOUNG-ADDRESS" :special)
  ("SYS: SYS2; GC" defvar "GC-COLLECTION-KIND" :special)
  ("SYS: SYS2; GC" defvar "GC-COLLECTION-PROMOTION" :special)
  ("SYS: SYS2; GC" defvar "GC-EDEN-SIZE" :special)
  ("SYS: SYS2; GC" defvar "GC-ON-AT-BOOT" :special)
  ("SYS: SYS2; GC" defvar "GC-PRETENURE-THRESHOLD" :special)
  ("SYS: SYS2; GC" defvar "GC-REPORT-ALLOWANCE" :special)
  ("SYS: SYS2; GC" defvar "GC-SURVIVOR-CAP" :special)
  ("SYS: SYS2; GC" defvar "GC-TENURED-AUTOMATIC" :special)
  ("SYS: SYS2; GC" defvar "GC-TENURED-COLLECTION-COUNT" :special)
  ("SYS: SYS2; GC" defvar "GC-TENURED-GROWTH-LIMIT" :special)
  ("SYS: SYS2; GC" defvar "GC-TENURED-WORDS-AT-LAST-TENURED-COLLECTION" :special)
  ("SYS: SYS2; GC" defvar "GC-WAIT-EDEN-WORDS" :special)
  ("SYS: SYS2; GC" defvar "GC-YOUNG-COLLECTION-COUNT" :special)
  ("SYS: SYS2; HASH" defvar "%GC-TENURED-FLIP-GENERATION" :special)
  ))
