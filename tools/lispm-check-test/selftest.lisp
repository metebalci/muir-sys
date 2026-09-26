;;; -*- Mode:Lisp; Package:User; Base:10 -*-
;;; The self-test's file for tools/lispm-check: two small functions its cases
;;; call, one that answers and one that signals an error, so that the self-test
;;; sees a file compiled or loaded and then used.

(defun check-selftest-square (n)
  (* n n))

(defun check-selftest-fail (x)
  (ferror nil "Self-test error with ~S" x))
