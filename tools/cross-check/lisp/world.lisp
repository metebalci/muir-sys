;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:8; Lowercase:T; Readtable:ZL -*-

;;; Check 1's identity control, and with PAGES32 its 32-bit target of 1024-word
;;; pages (tools/cross-check/README.md): this world's parameters, loaded over
;;; the tree's QCOM, which describes the 40-bit machine (contract G2).  Every
;;; parameter QCOM, QDEFS and DEFMIC defined that this world also has takes
;;; this world's value, so the cross build's parameters are this world's.  A
;;; value that holds symbols (Q-DATA-TYPES, an alist of array types) holds the
;;; cold-load package's symbols of the same names, as QCOM's own lists do.
;;; Loaded into the cold-load generator's package, which uses no other: hence
;;; the prefixes.

(global:defvar *world-conses* 0)

(defun world-translate (x)
  ;; along a list's cdrs by iteration: a long list would overflow the pdl.  a
  ;; circular value would never end: it stops the load instead.
  (global:cond ((global:and (global:symbolp x)
			    (global:not (global:memq x '(t nil)))
			    (global:not (global:keywordp x)))
		(global:intern (global:symbol-name x) (global:pkg-find-package "COLD-SYMBOLS")))
	       ((global:consp x)
		(global:when (global:> (global:setq *world-conses* (global:1+ *world-conses*)) 200000.)
		  (global:ferror nil "WORLD: a value of more than 200000 conses, or circular"))
		(global:do ((tail x (global:cdr tail))
			    (out nil (global:cons (world-translate (global:car tail)) out))
			    (n 0 (global:1+ n)))
			   ((global:or (global:not (global:consp tail))
				       (global:and (global:> n 200000.)
						   (global:ferror nil "WORLD: a circular list")))
			    (global:nreconc out (world-translate tail)))))
	       (t x)))

(global:mapatoms
  (global:function
    (global:lambda (cold)
      (global:let ((here (global:intern-soft (global:symbol-name cold)
					       (global:pkg-find-package "SI"))))
	(global:when (global:and here
				 (global:not (global:eq here cold))
				 (global:not (global:memq here '(t nil)))
				 (global:boundp cold)
				 (global:boundp here)
				 (global:not (global:fboundp cold)))
	  (global:set cold (world-translate (global:symbol-value here)))))))
  (global:pkg-find-package "COLD-SYMBOLS")
  nil)

;;; The system constants that QCOM, QDEFS and DEFMIC do not define, such as
;;; SINGLE-FLOAT-EXPONENT-OFFSET in SYS: SYS2; NUMDEF, would otherwise be read
;;; from their defining files in the tree, whose values may not be this
;;; world's: each gets a cold symbol with this world's value, which the cross
;;; build then takes (cross-cold-symbol) instead of reading the file.
(global:dolist (pkg global:*all-packages*)
  (global:mapatoms
    (global:function
      (global:lambda (here)
	(global:when (global:and (global:eq (global:symbol-package here) pkg)
				 (global:get here 'si:system-constant)
				 (global:boundp here)
				 (global:not (global:memq here '(t nil))))
	  (global:let ((cold (global:intern (global:symbol-name here)
					    (global:pkg-find-package "COLD-SYMBOLS"))))
	    (global:unless (global:boundp cold)
	      (global:set cold (world-translate (global:symbol-value here))))))))
    pkg nil))
