;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:10; Readtable:ZL -*-
;;; For the check npaint-text-leave (tools/system-check/README.md): the demo's
;;; PAINT-COM-TEXT-LEAVE (sys/demo/npaint.lisp) gives the special
;;; PAINT-TEXT-HOLDING-STRING's string back with RETURN-ARRAY.  The file does
;;; not load on this system (DEFCLASS is gone), so the check reads that one
;;; definition from it and evaluates it.  A special still naming the string
;;; after the call is a pointer the collector scans to storage given back,
;;; and once that storage is consed again it names the new object.
;;; Definitions only; the cases call them.

(defun ntl-read-def (file pkg name)
  "The first top-level form of FILE, read in PKG and base 8, whose second
element is NAME."
  (with-open-file (s file)
    (let ((*package* (find-package pkg)) (ibase 8) (base 8))
      (loop for f = (read s nil :eof)
	    until (eq f :eof)
	    when (and (consp f) (eq (cadr f) name)) return f))))

(defun ntl-run ()
  "Define PAINT-COM-TEXT-LEAVE from the file, give it a holding string, and
call it.  Returns (the special still names a string, that string lies in
storage given back, it is the string consed there after the call)."
  (eval '(defvar user::paint-text-holding-string nil))
  (eval (ntl-read-def "SYS: DEMO; NPAINT LISP" "USER" 'user::paint-com-text-leave))
  (set 'user::paint-text-holding-string
       (make-array 50 :type 'art-string :leader-list '(0)))
  (user::paint-com-text-leave)
  (let* ((v (symeval 'user::paint-text-holding-string))
	 (r (and v (%region-number v)))
	 (returned (and r (>= (- (%pointer v) (region-origin r)) (region-free-pointer r))))
	 (new (make-array 50 :type 'art-string :leader-list '(0))))
    (list (stringp v) (not (null returned)) (eq v new))))
