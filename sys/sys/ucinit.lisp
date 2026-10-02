;-*- Mode:LISP; Package:COMPILER; Base:8 -*-

;;; The microcompiler's record of the functions microcompiled into the
;;; microcode: *initially-microcompiled-functions*, and each one's MCLAP
;;; property.  System 100's SYS: SYS; UCINIT QFASL, which has no source and
;;; whose writer, write-initially-microcompiled-file (sys; mlap), has no caller,
;;; held one: EQUAL's MCLAP, microinstructions of the CADR's 32-bit word, and
;;; (setq *initially-microcompiled-functions* '(equal)).  Microcode 2001, for
;;; quux revision 13's 40-bit word, has no microcompiled function (EQUAL is
;;; hand-written, XEQUAL in uc-fctns), and those 32-bit microinstructions
;;; would be wrong for it, so this file, compiled as any other, records none.
;;; Nothing else reads the variable; MCLAP-LOAD reads a function's MCLAP
;;; property only when asked to load that function.
(setq *initially-microcompiled-functions* nil)
