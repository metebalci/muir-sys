;;; -*- Mode:LISP; Package:USER; Base:10; Lowercase:T; Readtable:ZL -*-

;;; The cross build's structure check (tools/cross-check/README.md, "The
;;; tree's structures"): a structure the builder's system does not have, as
;;; a file of the tree being built would define it.  The check serves this
;;; file inside the tree's sys/, as SYS: CROSS-CHECK-TREE; STRUCTS, so that
;;; crossdefs.py lists XS-POINT (:new) and cold:cross-begin is asked to give
;;; it to every compile for the target; SYS: CROSS-CHECK; STRUCT-USE uses it.
;;;
;;; XS-POINT is a named array: element 0 holds its name, X at 1, Y at 2 and
;;; the read-only ID at 3.  Its accessors are defsubsts, its constructor
;;; MAKE-XS-POINT and its alterant ALTER-XS-POINT macros, and ID has no setf.

(defstruct (xs-point (:type :named-array) (:conc-name xs-point-))
  (x 0)
  (y 0)
  (id 7 :read-only t))
