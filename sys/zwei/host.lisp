;;; ZWEI host -*-Mode: Lisp; Package: ZWEI; Base: 8.-*-
;;; Copyright (c) 1982 Devon S. McCullough, all rights reserved.
;;; I may give you permission to use this -- ask if you
;;; are interested -- but I will insist that you agree to
;;; return all improvements to me for redistribution.

; Make ZWEI a host so Lisp Machine programs can treat buffers like files.

; hosts:  ED:  accepts any name the completing reader would
;         ED-FILE:  accepts a pathname and does a find file (like Control-X Control-F)
;         ED-BUFFER:  must have the exact buffer name or will create new buffer

; known bugs:  ED-FILE won't allow :NEW-FILE nil (I'll fix later)

; --- ZWEI-HOST ---

(defmacro zwei-host-def (flavor name)
  
  `(progn 'compile
	  (defflavor ,flavor () (SI:BASIC-HOST))	; hmmmm, tasty...
	  
	  (defmethod (,flavor :NAME) ()		; what's your use name?
	    ,name)

	  (defmethod (,flavor :SYSTEM-TYPE) () ':zwei)
	  
	  (defmethod (,flavor :NAME-AS-FILE-COMPUTER) ()	; what can I call you?
	    ,name)

	  (defmethod (,flavor :PATHNAME-FLAVOR) ()	; how can I reach you?
	    ',(intern (string-append name "-PATHNAME")))
	  
	  (defmethod (,flavor :PATHNAME-HOST-NAMEP) (name)	; zwei, is that you?
	    (or (typep name ',flavor)
		(string-equal name ,name)))))
  
(zwei-host-def zwei-host "ED")
(zwei-host-def zwei-file-host "ED-FILE")
(zwei-host-def zwei-buffer-host "ED-BUFFER")
  
; -- ZWEI-PATHNAME --

(defflavor ed-basic-pathname () (fs:pathname))
(defflavor ed-pathname () (ed-basic-pathname))
(defflavor ed-file-pathname () (ed-basic-pathname))
(defflavor ed-buffer-pathname () (ed-basic-pathname))

(defmethod (ed-basic-pathname :STRING-FOR-PRINTING) ()	; print our name
  (string-append (send (funcall-self ':HOST) ':NAME) ": " (funcall-self ':NAME)))

(defmethod (ed-basic-pathname :STRING-FOR-EDITOR) ()
  (string-append (funcall-self ':NAME) " " (send (funcall-self ':HOST) ':NAME) ":"))

; PARSE-NAMESTRING accepts HOST-SPECIFIED (t or nil) which I ignore
;                          NAMESTRING (to be parsed)
;                          optional START and END indices into NAMESTRING
; returns multiple values DEVICE DIRECTORY NAME TYPE VERSION

(defmethod (ed-basic-pathname :PARSE-NAMESTRING) (ignored
					     namestring
					     &optional (start 0) end)
  (values ':UNSPECIFIC  ':UNSPECIFIC
	  (string-upcase (substring namestring start end)) ':UNSPECIFIC ':UNSPECIFIC))

(defmethod (ed-basic-pathname :HOMEDIR) (user)
  user
  (make-pathname ':host fs:host ':directory ':unspecific ':device ':unspecific))

; OPEN returns what?  it's called from SI:INSTANCE-HASH-FAILURE from OPEN
;      (LEXPR-FUNCALL FILENAME ':OPEN FILENAME KEYWORD-ARGS)
; So I need to understand KEYWORD-ARGS in order to implement this right.

;;; Possible keywords and values include the following:

; :DIRECTION is ignored if specified, ZWEI is always open for IO.
; :CHARACTERS (T and :DEFAULT for character mode, NIL for 16-bit :TYO mode)
; :BYTE-SIZE is ignored if specified, since :CHARACTERS does the job
; :ERROR if nil, return error string instead of bombing
; :NEW-FILE mustn't be T for ZWEI:
;           shouldn't (or should it?) be NIL for ZWEI-FILE:
;           if T, allows creation of new buffer for ZWEI-BUFFER:
; :OLD-FILE (T and :REWRITE = normal, :APPEND start at end)
; other keywords are totally ignored.

(defmethod (ed-pathname :OPEN)  ed-pathname-open)
(defmethod (ed-file-pathname :OPEN)  ed-pathname-open)
(defmethod (ed-buffer-pathname :OPEN)  ed-pathname-open)

(defmacro open-error (message &rest rest)	; expects value of :ERROR keyword in ERROR
  (check-arg-type message STRING)
  `(if error
       (ferror nil ,message ,@rest)
     ,(if rest
	  `(format nil ,message ,@rest)
	`,message)))

(defun ED-PATHNAME-OPEN (ignored pathname
			 &key &optional (characters t)
			 (direction ':input)
			 (error t)
			 (if-exists ':append)
			 (if-does-not-exist
			   (if (eq direction ':output) ':create
			     ':error))
			 &allow-other-keys)
  "parse OPEN keywords and then call the :REALLY-OPEN method"
  (let ((stream
	  (funcall-self ':REALLY-OPEN pathname characters error
			(eq if-does-not-exist ':create))))
    (if (and (eq direction ':output)
	     (eq if-exists ':append))
	(send stream ':read-until-eof))
    stream))

(defmethod (ED-PATHNAME :REALLY-OPEN) (pathname characters error new-file)
  pathname
  "Use completing reader to find buffer name.  Never make a new file."
  (and new-file
       (neq new-file ':DEFAULT)
       (open-error "can't handle :NEW-FILE keyword, use ED-BUFFER: instead"))
  (multiple-value-bind (ignore alist) (complete-string (send self ':name)
						       *ZMACS-BUFFER-NAME-ALIST*
						       '(#\SP #/- #/. #/\ #// #/#))
    (if alist
	(if (= (length alist) 1)
	    (interval-stream (cdar alist) nil nil (if characters nil ':TYO) t)
	    (open-error "ambiguous name"))
        (open-error "not found"))))

(defmethod (ED-FILE-PATHNAME :REALLY-OPEN) (pathname characters error new-file)
  pathname error new-file
  (let ((name (fs:parse-pathname (send self ':name)))
	(*interval* nil))
    (interval-stream
      (or (find-buffer-named pathname)		; don't bash existing buffer!
	  (find-file name nil t))
      nil
      nil
      (if characters nil ':TYO)
      t)))

(defmethod (ED-BUFFER-PATHNAME :REALLY-OPEN) (pathname characters error new-file)
  pathname
  (let ((buffer (find-buffer-named (send self ':name) (not (null new-file)))))
    (if buffer
	(interval-stream buffer nil nil (if characters nil ':TYO) t)
      (open-error "ED-BUFFER: not found"))))

(defvar zwei-host (make-instance 'zwei-host))
(defvar zwei-buffer-host (make-instance 'zwei-buffer-host))
(defvar zwei-file-host (make-instance 'zwei-file-host))

(defun add-zwei-hosts ()
  (or (memq zwei-host fs:*pathname-host-list*)
      (push zwei-host fs:*pathname-host-list*))
  (or (memq zwei-buffer-host fs:*pathname-host-list*)
      (push zwei-buffer-host fs:*pathname-host-list*))
  (or (memq zwei-file-host fs:*pathname-host-list*)
      (push zwei-file-host fs:*pathname-host-list*)))

(compile-flavor-methods zwei-host zwei-buffer-host zwei-file-host
			ed-pathname ed-buffer-pathname ed-file-pathname)

(add-initialization "Add ZWEI Hosts" '(add-zwei-hosts) '(site))
