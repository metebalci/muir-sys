;;; -*- Mode:LISP; Package:USER; Base:10; Readtable:ZL -*-
;;; division by the most negative fixnum.  Every quotient and
;;; remainder is written out, one line per case, for exact checking on the
;;; host.
(defvar *div-values*
  (list 0 1 -1 2 -2 3 -3 7 -7 16777215 -16777215 16777216 -16777216 8388607
	-8388608 4294967295 -4294967295 4294967296 2147483648 -2147483648
	(expt 2 48) (- (expt 2 48)) 12345678901234567890 -12345678901234567890))

(defun div-line (s op a b)
  (format s "~A ~D ~D " op a b)
  (condition-case (e)
      (multiple-value-bind (q r)
	  (cond ((eq op 'div) (let ((x (%div a b))) (values (numerator x) (denominator x))))
		(t (funcall op a b)))
	(format s "~D ~D~%" q r))
    (error (format s "ERR~%"))))

(defun div-check (file)
  (with-open-file (s file ':direction ':output)
    (dolist (a *div-values*)
      (dolist (b *div-values*)
	(div-line s 'truncate a b)
	(div-line s 'floor a b)
	(div-line s 'ceiling a b)
	(div-line s 'div a b)))
    (format s "done~%")))
(compile 'div-line)
(compile 'div-check)
