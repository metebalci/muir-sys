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
  ("SYS: IO; RDDEFS" defmacro "PRINTING-RANDOM-OBJECT" :changed)
  ("SYS: SYS; QMISC" defmacro "MAYBE-GROW-IO-STRING" :floats)
  ("SYS: SYS2; HASH" defsubst "HASH-TABLE-MAXIMAL-FULLNESS" :floats)
  ("SYS: SYS2; LMMAC" defsubst "%POINTER-LESSP" :changed)
  ("SYS: SYS2; NUMDEF" defsubst "ZERO-OF-TYPE" :floats)
  ("SYS: SYS2; PRODEF" defmacro "FIXNUM-READ-METER-FOR-SCHEDULER" :changed)
  ("SYS: SYS2; PRODEF" defsubst "RUN-LIGHT-FOR-CADR" :changed)
  ("SYS: SYS2; PRODEF" defsubst "SET-RUN-LIGHT-FOR-CADR" :new)
  ("SYS: WINDOW; SUPDUP" defmacro "ARDS-LOOP" :floats)
  ("SYS: WINDOW; SUPDUP" defmacro "ARDS-COORD" :floats)
  ("SYS: SYS2; PRODEF" defsetf "RUN-LIGHT-FOR-CADR" :gone)
  ))
