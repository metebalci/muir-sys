;;; -*- Mode:LISP; Package:USER; Base:10; Lowercase:T; Readtable:ZL -*-

;;; The cross build's structure check (tools/cross-check/README.md, "The
;;; tree's structures"): a file compiled for the target that uses the tree's
;;; structures, XS-POINT (new, SYS: CROSS-CHECK-TREE; STRUCTS) and SRCCOM:FILE
;;; (changed, SYS: CROSS-CHECK-TREE; SRCCOM).  The builder's word is the
;;; target's, so the check loads the QFASL into the builder and runs it.

;;; What this compile sees, recorded while it compiles: the size of XS-POINT's
;;; description, its slot ID's setf method (read only), and the expansions of an
;;; accessor of each structure.
(eval-when (compile)
  (setq xs-compile-record
	(list (let ((d (getdecl 'xs-point 'si:defstruct-description)))
		(and d (si:defstruct-description-size d)))
	      (getdecl 'xs-point-id 'si:setf-method)
	      (macroexpand '(xs-point-y p))
	      (macroexpand '(srccom::file-name f)))))

;;; the constructor: the named array as the tree lays it out
(defun xs-layout ()
  (let ((p (make-xs-point x 3 y 4)))
    (list (array-length p) (aref p 0) (aref p 1) (aref p 2) (aref p 3))))

;;; the accessors, and their setf, incf and the alterant
(defun xs-setf ()
  (let ((p (make-xs-point)))
    (setf (xs-point-x p) 11)
    (incf (xs-point-y p) 5)
    (alter-xs-point p x 12)
    (list (xs-point-x p) (xs-point-y p) (xs-point-id p) (aref p 1) (aref p 2))))

;;; the description: a structure that includes XS-POINT
(defstruct (xs-point3 (:type :named-array) (:include xs-point) (:conc-name xs-point3-))
  (z 9))

(defun xs-include ()
  (let ((q (make-xs-point3 x 1 z 2)))
    (list (array-length q) (xs-point-x q) (xs-point3-y q) (xs-point3-z q))))

;;; the changed structure: the leader index FILE-NAME reads, in an array whose
;;; leader slot I holds I
(defun xs-file-name-index ()
  (let ((f (make-array 0 :leader-length 10.)))
    (dotimes (i 10.) (setf (array-leader f i) i))
    (srccom::file-name f)))
