;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:10; Readtable:ZL -*-
;;; A plant for the check machine-name (tools/system-check/machine-name --plant,
;;; README.md): FIND-LOCAL-HOST with SET-HOST-NAME's name before the name file,
;;; the order of QUUX's Ethernet contract, section 5.6, broken.  Loaded before
;;; the command and kept by the save, it must fail the case "both" (the saved
;;; band boots as LISPM-3 although the name file says LISPM-2).

(let ((inhibit-fdefine-warnings t))
  (defun find-local-host (&optional (read-file t))
    (when read-file
      (setq *host-name-since-boot* nil)
      (setq local-host-file-name (read-local-host-name-file)))
    ;; the plant: the command's name first
    (cond (*host-name* (host-of-name *host-name*))
	  (local-host-file-name (host-of-name local-host-file-name))
	  ((loop for f in local-host-functions thereis (funcall f)))
	  (t (host-of-name "LOCALHOST")))))
