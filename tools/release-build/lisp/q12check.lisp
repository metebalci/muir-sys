;-*- Mode:LISP; Package:USER; Base:10; Readtable:ZL -*-
;;; helpers for the date gates of a release build (tools/release-build/run,
;;; G3 and G5, docs/building.md); loaded by tools/lispm-check

;;; every file the cold load holds: the date its id recorded against the date
;;; the file server gives the file now.  the value is (files checked, files
;;; whose recorded date differs, the first three as (truename recorded
;;; served), recorded dates still strings).
(defun q12-cold-loaded-ids ()
  (let ((n 0) (bad nil) (strings 0))
    (maphash #'(lambda (ignore p)
		 (dolist (id (getf (fs:pathname-property-list p) :file-id-package-alist))
		   (let ((info (cadr id)))
		     (when (and (consp info) (equal (caddr id) "COLDLOADED"))
		       (incf n)
		       (if (stringp (cdr info))
			   (incf strings)
			 (let ((served (with-open-file (s (fs:parse-pathname (string (car info)))
							  :direction :probe)
					 (send s :creation-date))))
			   (unless (eql served (cdr info))
			     (push (list (string (car info)) (cdr info) served) bad))))))))
	     fs:*pathname-hash-table*)
    (list n (length bad) (firstn 3 bad) strings)))

;;; the date check (q12 1.11): the :creation-date a directory listing of
;;; OZ: /sys/q12d/ gives for the file named NAME.
(defun q12-listed-date (name &optional (dir "OZ: //sys//q12d//*.*"))
  (dolist (e (cdr (fs:directory-list dir)))
    (when (string-equal (send (car e) :name) name)
      (return (getf (cdr e) :creation-date)))))

;;; band to host: write OZ: /sys/q12o/NAME.text, set its creation date to UT,
;;; and give the date a listing reads back.  the host's mtime is read outside.
(defun q12-set-date (name ut)
  (let ((path (fs:parse-pathname (string-append "OZ: //sys//q12o//" name ".text"))))
    (with-open-file (s path :direction :output)
      (format s "q12 date check ~A ~D~%" name ut))
    (fs:change-file-properties path t :creation-date ut)
    (q12-listed-date name "OZ: //sys//q12o//*.*")))

;;; a date recorded as text before the time parser came in, as the cold load
;;; and QFILE record one: put TEXT on a scratch pathname's file ids, run
;;; FS:CANONICALIZE-COLD-LOADED-TIMES, and give the date it made.
(defun q12-canonicalized (name text)
  (let* ((p (send (fs:parse-pathname (string-append "OZ: //lispm//" name ".qfasl"))
		  :generic-pathname))
	 (id (list si:pkg-system-internals-package
		   (cons (fs:parse-pathname (string-append "OZ: //lispm//" name ".qfasl"))
			 (string-append text))
		   "COLDLOADED")))
    (send p :putprop (list id) :file-id-package-alist)
    (fs:canonicalize-cold-loaded-times)
    (cdr (cadr (car (send p :get :file-id-package-alist))))))

;;; every file the band has loaded, whatever loaded it: the date its id
;;; recorded against the date the file server gives the file now.  the value
;;; is (ids checked, ids whose date differs, the first three as (truename
;;; recorded served), ids whose date is not a number, files not found).
(defun q12-loaded-ids ()
  (let ((n 0) (bad nil) (odd nil) (gone 0))
    (maphash #'(lambda (ignore p)
		 (dolist (id (getf (fs:pathname-property-list p) :file-id-package-alist))
		   (let ((info (cadr id)))
		     (when (and (consp info) (car info))
		       (incf n)
		       (if (not (numberp (cdr info)))
			   (push (list (string (car info)) (cdr info)) odd)
			 (let ((served (condition-case ()
					   (with-open-file (s (car info) :direction :probe)
					     (send s :creation-date))
					 (error nil))))
			   (cond ((null served) (incf gone))
				 ((not (eql served (cdr info)))
				  (push (list (string (car info)) (cdr info) served) bad)))))))))
	     fs:*pathname-hash-table*)
    (list n (length bad) (firstn 3 bad) odd gone)))

;;; every loaded id of the band, one line each to OZ: /lispm/ids.text: the
;;; truename, a tab, and the recorded date (a number, or "text " and the text).
;;; the value is the number of lines.
(defun q12-dump-ids ()
  (let ((n 0))
    (with-open-file (out "OZ: //lispm//ids.text" :direction :output)
      (maphash #'(lambda (ignore p)
		   (dolist (id (getf (fs:pathname-property-list p) :file-id-package-alist))
		     (let ((info (cadr id)))
		       (when (and (consp info) (car info))
			 (incf n)
			 (format out "~A	~:[text ~A~;~D~]~%"
				 (if (stringp (car info)) (car info)
				   (send (car info) :string-for-printing))
				 (numberp (cdr info)) (cdr info))))))
	       fs:*pathname-hash-table*))
    n))
