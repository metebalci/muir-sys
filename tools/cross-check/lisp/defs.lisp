;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:10; Lowercase:T; Readtable:ZL -*-

;;; The cross build's check 1 (tools/cross-check/README.md): the tree's
;;; compile-time definitions, which cold:cross-begin gives every compile for the
;;; target (SYS: COLD; CROSSDEFS).  Compiled for the 40-bit machine; check1.py
;;; reads the code.
;;;
;;; - XC-SHORT-EXPONENT open-codes the defsubst %short-float-exponent of
;;;   SYS2; NUMDEF, as QFASL's FASL-OP-NEW-FLOAT does: its byte must be the
;;;   tree's (byte 8 23.), #o2710, and not System 2000's (byte 8 17.), #o2110.
;;; - XC-METER expands PRODEF's macro fixnum-read-meter-for-scheduler, as the
;;;   scheduler does: its byte must be the target's (1- %%q-pointer), #o37,
;;;   and not the builder's, #o30.

(defun xc-short-exponent (x) (%short-float-exponent x))

(defun xc-meter () (fixnum-read-meter-for-scheduler %disk-wait-time))

;;; What the compiler itself decides by this world's values (qcdefs, qcopt):
;;; - XC-TABLE-CONSTANT folds DISK-BLOCKS-PER-PAGE, a system constant of the
;;;   target that System 2000 does not have: (ash 4 2), 16, not a variable's
;;;   value;
;;; - XC-ROT folds a ROT with the target's 32-bit fixnum: -2147483648;
;;; - XC-FLOAT-PROTO is (float x 0f0): the target has one float, the short
;;;   float, so it compiles to SMALL-FLOAT, not INTERNAL-FLOAT;
;;; - XC-SMALL-FLOAT folds SMALL-FLOAT to the target's single, #x3EAAAAAB,
;;;   not System 2000's short float of 17 bits.
(defun xc-table-constant () (ash disk-blocks-per-page 2))

(defun xc-rot () (rot 1 31))

(defun xc-float-proto (x) (float x 0f0))

(defun xc-small-float () (small-float 0.333333333333))

;;; What the builder's own reading and evaluating give:
;;; - XC-SHORT-LITERAL holds short-float literals, which must keep the target's
;;;   24 bits (#x3FA66666, #x3F333333), not System 2000's 17;
;;; - XC-SQRT folds (sqrt 2), which must be #x3FB504F3 also once make-system
;;;   has met SYS2; NUMDEF, which the cross build does not load into the builder.
(defun xc-short-literal () '(1.3s0 0.7s0))

(defun xc-sqrt () (sqrt 2))

;;; Floats the builder holds as the target does not:
;;; - XC-FULLNESS open-codes HASH-TABLE-MAXIMAL-FULLNESS, whose text is System
;;;   2000's but whose 0.7s0 the builder read as its short float: listed in
;;;   CROSSDEFS (:floats), it must hold #x3F333333, not #x3F333300;
;;; - XC-DEDUP returns one of two literals that are one float in the target:
;;;   rounded to the target's single as they are read, they must be one constant.
(defun xc-fullness (h) (hash-table-maximal-fullness h))

(defun xc-dedup (x) (if x 1.442695s0 1.44269504))

;;; Floats read as the target reads them, exactly (si:xr-float-bits):
;;; - XC-LONG-LITERAL holds 1.00000005960464477539062500001, just past the
;;;   halfway point between 1.0 and the next single: #x3F800001, where this
;;;   world's reader, 12 digits, gives 1.0;
;;; - XC-PI2 returns one of 1.570796326 and 1.5707963185, which are one single,
;;;   #x3FC90FDB, as in numer's SIN-AUX: one constant.
(defun xc-long-literal () '(1.00000005960464477539062500001))

(defun xc-pi2 (x) (if x 1.570796326 1.5707963185))
