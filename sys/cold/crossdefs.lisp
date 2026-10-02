;;; -*- Mode:LISP; Package:COLD; Base:10; Lowercase:T; Readtable:ZL -*-

;;; The tree's compile-time definitions that the cross build gives every
;;; compile for the target (cold:cross-begin, sys/cold/cross.lisp): each
;;; (file kind name status), status :new, :changed, :gone (System 2000
;;; has it and the tree does not), or :floats (a macro or defsubst of the
;;; same text that holds a float literal, which the builder read with its
;;; own floats).  Written by tools/cross-check/crossdefs.py
;;; from the sources; run it again after a change, since the cross build
;;; checks that this list is what the sources give.

(setq *cross-definitions* '(
  ("SYS: DEMO; COLORHACK" defmacro "CLIP-ON-PLANE" :floats)
  ("SYS: IO; DISK" defsubst "DISK-TRANSFER-BLOCKS-PER-PAGE" :new)
  ("SYS: IO; DISK" defsubst "DISK-BLOCK-WORDS" :new)
  ("SYS: IO; DISK" defsubst "RQB-NBLOCKS" :new)
  ("SYS: IO; DISK" defsubst "BAND-SYS-COM-BLOCK" :new)
  ("SYS: SYS; EVAL" defmacro "SERIAL-BINDING-LIST" :changed)
  ("SYS: SYS; EVAL" defmacro "APPLY-LAMBDA-BINDVAR" :changed)
  ("SYS: SYS; QMISC" defmacro "MAYBE-GROW-IO-STRING" :floats)
  ("SYS: SYS2; HASH" defsubst "HASH-TABLE-MAXIMAL-FULLNESS" :floats)
  ("SYS: SYS2; LMMAC" defsubst "%POINTER-TYPE-P" :changed)
  ("SYS: SYS2; NUMDEF" defsubst "%SHORT-FLOAT-EXPONENT" :changed)
  ("SYS: SYS2; NUMDEF" defsubst "%SHORT-FLOAT-MANTISSA" :changed)
  ("SYS: SYS2; NUMDEF" defsubst "ZERO-OF-TYPE" :floats)
  ("SYS: SYS2; PRODEF" defmacro "FIXNUM-READ-METER-FOR-SCHEDULER" :changed)
  ("SYS: WINDOW; SUPDUP" defmacro "ARDS-LOOP" :floats)
  ("SYS: WINDOW; SUPDUP" defmacro "ARDS-COORD" :floats)
  ))
