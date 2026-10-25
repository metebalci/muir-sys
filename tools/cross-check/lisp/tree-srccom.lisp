;;; -*- Mode:LISP; Package:SRCCOM; Base:10; Lowercase:T; Readtable:ZL -*-

;;; The cross build's structure check (tools/cross-check/README.md, "The
;;; tree's structures"): a structure of the builder's system that the tree
;;; changes.  SRCCOM:FILE is SYS: IO1; SRCCOM's, with one slot put first,
;;; FILE-GENERATION, so that every other slot's leader index is one higher
;;; than in the builder.  The check serves this file inside the tree's sys/,
;;; as SYS: CROSS-CHECK-TREE; SRCCOM, so that crossdefs.py lists FILE
;;; (:changed); a compile for the target must open-code FILE-NAME with the
;;; tree's index, and the builder's own FILE must stay as it is.

(defstruct (file :array-leader (:make-array (:length 100.)) (:alterant nil))
  (file-generation 0 :documentation "Planted by the cross build's check")
  (file-length 0 :documentation "Number of lines")
  (file-name nil :documentation "The file name")
  (file-type "File" :documentation "What kind of source it has")
  (file-stream nil :documentation "Input stream")
  (file-major-mode nil :documentation "Symbol")
  (file-compare ':text :documentation "Kind of comparison to use"))
