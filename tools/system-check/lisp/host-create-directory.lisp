;;; -*- Mode:LISP; Package:USER; Base:10; Readtable:ZL -*-
;;; For the check host-create-directory (tools/system-check/README.md): a
;;; HOST: file opened for output in a directory that does not exist is
;;; written once the error is proceeded with :CREATE-DIRECTORY-AND-RETRY, the
;;; debugger's "Creates the directory and tries again" (sys/io/file/open.lisp,
;;; DIRECTORY-NOT-FOUND-ERROR).  That proceed type creates the directory and
;;; proceeds with :RETRY-FILE-OPERATION, which the file device's operations
;;; did not offer (sys/io/file/hostfs.lisp), so the directory was made and the
;;; open then stopped at "Invalid proceed-type :RETRY-FILE-OPERATION returned
;;; by handler".

(defvar *hcd-proceeded* 0 "How often HCD-WRITE's handler proceeded.")

(defun hcd-write (file text)
  "Open FILE for output and write TEXT, with a handler that proceeds a
DIRECTORY-NOT-FOUND once with :CREATE-DIRECTORY-AND-RETRY, as the debugger's
command for it does.  Return how often the handler proceeded."
  (let ((*hcd-proceeded* 0))
    (condition-bind ((fs:directory-not-found
		       #'(lambda (condition)
			   (when (zerop *hcd-proceeded*)
			     (incf *hcd-proceeded*)
			     (send condition :proceed :create-directory-and-retry)))))
      (with-open-file (stream file :direction :output)
	(princ text stream)))
    *hcd-proceeded*))

(defun hcd-read (file)
  "The first line of FILE."
  (with-open-file (stream file) (readline stream)))

(defun hcd-proceed-types (function)
  "Call FUNCTION, which signals a file error; return the proceed types the
debugger would offer for that error that the file system's operation gives,
or :NO-ERROR.  Those that the callers give are left out: :NEW-PATHNAME, and
the processes' restarts of the listener running the case."
  (catch 'hcd-proceed-types
    (condition-bind ((fs:file-error
		       #'(lambda (condition)
			   (throw 'hcd-proceed-types
				  (rem-if-not #'(lambda (type)
						  (memq type '(:no-action :retry-file-operation
							       :create-directory-and-retry)))
					      (send condition :user-proceed-types
						    (send condition :proceed-types)))))))
      (funcall function))
    :no-error))

(defun hcd-retry-open (file)
  "Open FILE for input, which does not exist, with a handler that writes it and
proceeds with :RETRY-FILE-OPERATION once; return its first line."
  (let ((*hcd-proceeded* 0))
    (condition-bind ((fs:file-not-found
		       #'(lambda (ignore)
			   (when (zerop *hcd-proceeded*)
			     (incf *hcd-proceeded*)
			     (with-open-file (stream file :direction :output)
			       (princ "made by the handler" stream))
			     :retry-file-operation))))
      (hcd-read file))))

(defun hcd-new-pathname (file new-file)
  "Open FILE for output, in a directory that does not exist, with a handler that
proceeds with :NEW-PATHNAME and NEW-FILE, which OPEN offers whatever the host;
write to the stream it gives; return NEW-FILE's first line."
  (condition-bind ((fs:directory-not-found
		     #'(lambda (ignore) (values :new-pathname (pathname new-file)))))
    (with-open-file (stream file :direction :output)
      (princ "elsewhere" stream)))
  (hcd-read new-file))
