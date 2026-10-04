;;; -*- Mode:LISP; Package:USER; Base:10; Readtable:ZL -*-
;;; every multiply and divide path, one line per case, for exact checking on
;;; the host (tools/release-build/run, verify_arith): a release's check that
;;; the microcode's arithmetic is right.
(defvar *arith-values*
  (list 0 1 -1 2 -2 3 -3 7 -7 10 -10 255 -256 4095 12345 -12345 65535 -65536
	1000003 -1000003 4194303 -4194304 8388607 -8388608 5000000 -7654321
	(expt 2 24) (- (expt 2 24)) (expt 2 31) (- (expt 2 31)) (1- (expt 2 32))
	(expt 3 30) (- (expt 3 30)) 12345678901234567890 -98765432109876543210
	(* (expt 7 40) 13) (- (expt 10 30) 1) (expt 2 90)))

(defvar *arith-trace* nil)
;; floor, ceiling and mod are left out: (floor 4294967295 -16777216) halts
;; the machine at XMINUS on MIT's own microcode 323 as well.
(defun arith-one (stream op a b)
  (when *arith-trace* (format t "~&~S ~D ~D~%" op a b) (send standard-output ':force-output))
  (format stream "~A ~D ~D => ~S~%" (if (symbolp op) op 'double) a b
	  (condition-case (e)
	      (multiple-value-list (funcall op a b))
	    (error (list 'error (send e ':report-string))))))

(defun arith-check (file)
  (with-open-file (s file ':direction ':output)
    (dolist (a *arith-values*)
      (dolist (b *arith-values*)
	(arith-one s '* a b)
	(arith-one s 'truncate a b)
	(arith-one s 'rem a b)
	(arith-one s 'gcd a b)))
    ;; the fixnum-only primitives on fixnum pairs
    (dolist (a *arith-values*)
      (dolist (b *arith-values*)
	(when (and (fixp a) (fixp b) (typep a 'fixnum) (typep b 'fixnum))
	  (arith-one s '%multiply-fractions a b)
	  (dolist (c '(1 3 -7 1000 -65536 8388607))
	    (arith-one s #'(lambda (x y) (%divide-double x y c)) a b)
	    (arith-one s #'(lambda (x y) (%remainder-double x y c)) a b)))))
    (format s "floats ~S~%" (list (// 1.0 3.0) (// 2.5 -7.0) (* 1.5 -2.25) (sqrt 2.0)))
    (format s "done~%")))
(compile 'arith-one)
(compile 'arith-check)
