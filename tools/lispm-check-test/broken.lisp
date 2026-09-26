;;; -*- Mode:Lisp; Package:User; Base:10 -*-
;;; A deliberately broken file for tools/lispm-check's self-test: the second
;;; form is never closed, so loading it must fail and the tool exit non-zero.

(defun check-selftest-square (n)
  (* n n))

(defun check-selftest-fail (x
  (ferror nil "Self-test error with ~S" x))
