;;; -*- Mode:LISP; Package:USER; Base:10 -*-
;;; network.sh's held plant, appended to a copy of tools/lispm-check-lisp/
;;; hc-serve.lisp: HC-SERVE run with a file of the login's home held open
;;; around its loop, so that the file device has a handle open while it
;;; waits.  The setup must then fail: the checkpoint is refused for a handle
;;; open, which no retry can cure.
(fset 'hc-serve-unheld (fsymeval 'hc-serve))
(defun hc-serve ()
  (with-open-file (held (hc-path 0 "held") ':direction ':output ':if-exists ':supersede)
    (prin1 'held held)
    (hc-serve-unheld)))
(compile 'hc-serve)
