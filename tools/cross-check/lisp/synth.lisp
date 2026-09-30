;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:8; Lowercase:T; Readtable:ZL -*-

;;; The cross build's check 1 (tools/cross-check/README.md): a synthetic target,
;;; loaded after SYS: COLD; TARGET40 into the cold-load generator's package
;;; (cold:cross-begin's overlays).  Every family gets a value that is neither
;;; this world's nor the 40-bit machine's, so that a file compiled for it shows
;;; which it was compiled with.  Octal.

(setq dtp-locative 35)				;data types (here 15)
(setq cdr-next 1)				;cdr codes (here 3)
(setq %%array-type-field 2405)			;arrays (here 2305)
(setq art-q 64000000)				;arrays (here 34000000)
(setq %%ch-font 1110)				;characters (here 1010)
(setq single-float-exponent-offset 177)		;floats (here 2000, SYS2; NUMDEF)
(setq %fefhi-fctn-name 12)			;the FEF (here 2)
(setq %header-type-array-leader 37)		;headers (here 2)
(setq %disk-rq-ccw-list 44)			;the disk (here 20)
(setq a-memory-virtual-address 1760000000)	;virtual addresses
;; a changed value that is not a number: the table gives it no target value
(setq %%q-high-half '(not a number))
