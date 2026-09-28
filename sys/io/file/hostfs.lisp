;;; -*- Mode:LISP; Package:FILE-SYSTEM; Base:10; Readtable:ZL -*-
;;;
;;; This is SYS: IO; FILE; HOSTFS
;;;
;;; quux: the pathname host HOST, the folders its host computer serves to it
;;; through quux's file device (contract q9, revision 9; muir's docs/quux.md,
;;; "the file device", as built at muir e11026a).  the driver, the rings and
;;; the registers are SYS: IO; FDEV; this file is the host, its access and its
;;; streams, on the model of SYS: FILE; FSACC and FSSTR.
;;;
;;; HOST speaks unix pathname syntax, so its pathnames print and parse as
;;; OZ's do, "HOST: /sys/io/disk.lisp".  it is on no network: QFILE's access
;;; never takes it.  the device moves bytes and never interprets them
;;; (decision 3 of the contract), so the streams here translate characters,
;;; with ozd's tables, and decide :characters :default by the qfasl magic, as
;;; ozd does.  dates are the device's binary unix seconds, converted by the
;;; epoch alone; the site's time zone applies when a date is decoded, as for
;;; every universal time.  no date is parsed or printed here.
;;;
;;; how muir's device differs from what one might assume, as built: a
;;; DIRECTORY of a missing directory is DNF; a LOG line over 1 KiB, a
;;; COMPLETE longer than buffer b, or flags on the wrong opcode are fault 66;
;;; names the host's file system refuses are not listed; a length over 64 KiB
;;; is charged as 64 KiB; the temporary files of writes in progress,
;;; .quux-write-*, are never listed.  names are exact in case; a name the
;;; host refuses with EINVAL is IPS.  a command in flight when the device is
;;; disabled (a boot, a disk-save) may have taken effect without an answer.

;; the same constant as time:unix-epoch-universal-time (io1/time.lisp); this
;; file is loaded by mini, before io1; time, and dates are needed at once.
(defconst unix-epoch-universal-time 2208988800.
  "The universal time of 1970-01-01 00:00 GMT, where the device's unix seconds count from.")

;;;; Characters

;; ozd's character translation, one byte for one character, so that a file
;; reads here as it reads over QFILE from ozd.  measured through ozd (all 256
;; bytes each way, run/q9-fdev): a host byte BS, TAB, FF or DEL is the lisp
;; machine's Backspace, Tab, Page or Rubout and the reverse; LF is Return
;; and CR is Line, but Return (215) is CR and Line (212) is LF, so reading
;; is not its own inverse.  writing is its inverse; every other byte is
;; itself both ways.
(defun make-file-device-translation (inverse)
  (let ((table (make-array 256. :type 'art-8b)))
    (dotimes (i 256.) (setf (aref table i) i))
    (dolist (pair '((#o010 #o210) (#o210 #o010) (#o011 #o211) (#o211 #o011)
		    (#o014 #o214) (#o214 #o014) (#o177 #o377) (#o377 #o177)
		    (#o012 #o215) (#o215 #o015) (#o015 #o212) (#o212 #o012)))
      (if inverse
	  (setf (aref table (second pair)) (first pair))
	(setf (aref table (first pair)) (second pair))))
    table))

(defconst file-device-read-translation (make-file-device-translation nil)
  "Host byte to lisp machine character.")
(defconst file-device-write-translation (make-file-device-translation t)
  "Lisp machine character to host byte: the read translation's inverse.")

(defun file-device-translate (table bytes start end)
  "Translate the ART-8B BYTES from START to END in place by TABLE."
  (do ((i start (1+ i))) ((>= i end))
    (setf (aref bytes i) (aref table (aref bytes i)))))

;; the qfasl magic, ozd's rule for :characters :default: bytes 150 306 260
;; 163, the check words #o143150 #o071660 stored little-endian.
(defun file-device-qfasl-bytes-p (bytes count)
  (and (>= count 4)
       (= (aref bytes 0) #o150) (= (aref bytes 1) #o306)
       (= (aref bytes 2) #o260) (= (aref bytes 3) #o163)))

;;;; Statuses

(defconst file-device-status-codes
	  '(nil fnf dnf fae ref acc atf dae dne nmr iod wkf ips ner uop dat for rad)
  "The device's statuses 1 to 17 as the three-letter codes of SYS: IO; FILE; OPEN.")

(defconst file-device-status-messages
	  '(nil "File not found" "Directory not found" "File already exists"
	    "Rename to existing file" "Access refused by the host"
	    "Incorrect access to file (a read-only folder)" "Directory already exists"
	    "Directory not empty" "No more room on the host"
	    "Invalid operation for a directory" "Wrong kind of file"
	    "Invalid pathname syntax" "Not enough resources: all 64 file device handles are open"
	    "Unknown operation" "Data error on the host" "File position out of range"
	    "Rename across folders served separately"))

(defun file-device-error (status operation pathname-or-stream &optional noerror new-pathname)
  "Signal the file condition for device status STATUS, or return it if NOERROR."
  (let ((code (nth status file-device-status-codes)))
    (if (and code (< 0 status (length file-device-status-codes)))
	(apply #'file-process-error (get code 'file-error) (nth status file-device-status-messages)
	       pathname-or-stream nil noerror
	       (case code
		 ((ref rad) (list new-pathname))
		 (dne nil)
		 (t (list operation))))
      (ferror nil "File device ~:[status ~D~;fault ~:*~A (~D)~] in ~S for ~A."
	      (cdr (assq status si:%file-device-fault-names)) status operation
	      pathname-or-stream))))

;;;; Names

;; a name for the device: an absolute path of at most 1,024 bytes, each
;; component 1 to 255 bytes of 040-176, not . or ..; a single trailing /
;; for a directory.  the device refuses .. , so each :up goes here with the
;; component before it, and the truename is the normalized name, so that
;; make-system sees one name for one file.
(defun file-device-normalize (string operation pathname)
  "Return STRING as the device's name for it, or signal IPS."
  (flet ((bad () (file-device-error 12. operation pathname)))
    (let ((length (string-length string))
	  (components nil))
      (unless (and (plusp length) (= (aref string 0) #//)) (bad))
      (do ((start 1 (1+ end)) (end))
	  ((> start length))
	(setq end (or (string-search-char #// string start) length))
	(let ((component (substring string start end)))
	  (cond ((or (zerop (string-length component)) (string-equal component ".")))
		((string-equal component "..")
		 (if components (pop components) (bad)))
		((> (string-length component) 255.) (bad))
		(t (dotimes (i (string-length component))
		     (unless (<= #o040 (aref component i) #o176) (bad)))
		   (push component components)))))
      (let ((name (format nil "//~{~A~^//~}~:[~;//~]" (reverse components)
			  (and components (= (aref string (1- length)) #//)))))
	(when (> (string-length name) 1024.) (bad))
	name))))

(defun file-device-name (pathname operation &optional directory-only)
  "The device's name for PATHNAME, or for its directory if DIRECTORY-ONLY."
  (let ((string (if directory-only
		    (send pathname :string-for-directory)
		  (send pathname :string-for-host))))
    (unless (stringp string) (file-device-error 12. operation pathname))
    (file-device-normalize string operation pathname)))

(defun file-device-truename (pathname name)
  "The truename of PATHNAME, whose device name is NAME: PATHNAME's physical
pathname itself unless normalizing changed its name."
  ;; a logical pathname's truename is its translation.  MAKE-SYSTEM asks for
  ;; the properties of SYS: pathnames, which LOGICAL-PATHNAME passes on to this
  ;; host untranslated, and the :TRUENAME was then the logical pathname: never
  ;; EQUAL to a loaded file's id, whose truename is HOST's, so with SYS: on
  ;; HOST, MAKE-SYSTEM loaded every file of a system again, and QLD reloaded
  ;; the cold load's files and stopped at a redefinition query.  a physical
  ;; pathname translates to itself.
  (let ((pathname (send pathname :translated-pathname)))
    (if (string-equal name (send pathname :string-for-host))
        pathname
      (parse-pathname name (pathname-host pathname)))))

(defun file-device-universal-time (seconds)
  (+ seconds unix-epoch-universal-time))

;;;; The host

(defflavor file-device-host () (file-host-unix-mixin si:basic-host)
  (:documentation "HOST, the folders served by quux's file device."))

(defmethod (file-device-host :name) () "HOST")
(defmethod (file-device-host :system-type) () :unix)
(defmethod (file-device-host :file-system-type) () :file-device)
;; file-host-mixin requires it; it is qfile's login reply, which HOST has not.
(defmethod (file-device-host :hsname-information) (&rest ignore)
  (values (send self :sample-pathname) "" #/- ""))

(compile-flavor-methods file-device-host)

(defvar *file-device-host* nil "The one pathname host HOST; the SYS logical host may hold it.")

(defun file-device-host-initialize ()
  "Put HOST on the pathname host list, always the same instance.
Called when this file is loaded, before any translation can name HOST, and
again by RESET-NON-SITE-HOSTS after SITE-PATHNAME-INITIALIZE, which drops
every file host (access.lisp), as LM-HOST-INITIALIZE is."
  (or *file-device-host* (setq *file-device-host* (make-instance 'file-device-host)))
  (unless (memq *file-device-host* *pathname-host-list*)
    ;; at the end: an associated machine defaults to the list's first host.
    (setq *pathname-host-list* (append *pathname-host-list* (list *file-device-host*))))
  *file-device-host*)

(file-device-host-initialize)

;;;; The access

(defflavor file-device-access ((streams nil)) (directory-list-mixin basic-access)
  (:gettable-instance-variables streams))

(define-file-access file-device-access 1.0s0 (:file-system-type :file-device))

(defmethod (file-device-access :access-description) () "File device")

(defmethod (file-device-access :open-streams) () (copylist streams))

(defmethod (file-device-access :add-stream) (stream)
  (without-interrupts (push stream streams)))

(defmethod (file-device-access :remove-stream) (stream)
  (without-interrupts (setq streams (delq stream streams))))

(defmethod (file-device-access :close-all-files) (&optional (mode :abort))
  (loop for stream in (copylist streams)
	do (format *error-output* "~%Closing ~S" stream)
	   (send stream :close mode)
	collect stream))

(defmethod (file-device-access :reset) ()
  (send self :close-all-files :abort))

(defmethod (file-device-access :homedir) (&optional (user user-id))
  (file-device-homedir host user))

;; the home is HOST:/home/<user>/ (the user, 2026-09-25), the user id in
;; lower case, as unix names normally are: LISPM's is /home/lispm/.
(defun file-device-homedir (host user)
  (parse-pathname (if (and user (plusp (string-length user)))
		      (string-append "//home//" (string-downcase user) "//")
		    "//home//")
		  host))

(defmethod (file-device-access :change-properties) (pathname error-p &rest ignore)
  (file-process-error 'unknown-operation "Properties cannot be changed" pathname
		      nil (not error-p) :change-properties))

(defmethod (file-device-access :create-link) (pathname ignore &optional (error t))
  (file-process-error 'unknown-operation "Links are not supported" pathname
		      nil (not error) :create-link))

(defmethod (file-device-access :expunge) (pathname &optional (error t))
  (file-process-error 'unknown-operation "There is nothing to expunge" pathname
		      nil (not error) :expunge))

(defmethod (file-device-access :remote-connect) (pathname &optional (error t) &rest ignore)
  (file-process-error 'unknown-operation "Remote connect is not supported" pathname
		      nil (not error) :remote-connect))

(defmethod (file-device-access :delete) (pathname &optional (error-p t))
  (let ((name (file-device-name pathname :delete)))
    (let ((status (si:file-device-call si:%file-device-op-delete 0 0 name)))
      (if (zerop status) t
	(file-device-error status :delete pathname (not error-p))))))

(defmethod (file-device-access :rename) (pathname new-pathname &optional (error-p t))
  (declare (values new-truename old-truename))
  (setq new-pathname (send new-pathname :translated-pathname))
  (if (neq (pathname-host new-pathname) host)
      (file-device-error 17. :rename pathname (not error-p) new-pathname)
    (let* ((old (file-device-name pathname :rename))
	   (new (file-device-name new-pathname :rename))
	   (status (si:file-device-call si:%file-device-op-rename 0 0 old new)))
      (if (zerop status)
	  (values (file-device-truename new-pathname new) (file-device-truename pathname old))
	(file-device-error status :rename pathname (not error-p) new-pathname)))))

(defmethod (file-device-access :create-directory) (pathname &optional (error t))
  (let* ((name (file-device-name pathname :create-directory t))
	 (status (si:file-device-call si:%file-device-op-create-directory 0 0 name)))
    (if (zerop status) t
      (file-device-error status :create-directory
			 (send pathname :new-pathname :name nil :type nil) (not error)))))

;;;; Properties and directories

(defun file-device-plist (truename bytes mtime flags &optional characters byte-size qfaslp)
  "The property list of a file the device described.  BYTE-SIZE is :CHARACTERS,
8 or 16 for an open stream's; CHARACTERS T or :BINARY adds :CHARACTERS and :QFASLP."
  (let ((plist (list :truename truename
		     :creation-date (file-device-universal-time mtime)
		     ;; 16-bit bytes: ozd gives the length rounded up, though a
		     ;; last odd byte is not read (measured); the same here.
		     :length (if (eql byte-size 16.) (ceiling bytes 2) bytes)
		     :length-in-bytes bytes
		     :length-in-blocks (ceiling bytes 1024.)
		     :byte-size (if (eql byte-size 16.) 16. 8))))
    (when (ldb-test si:%%file-device-flag-directory flags)
      (setq plist (list* :directory t plist)))
    (when characters
      (setq plist (list* :characters (eq characters t) :qfaslp qfaslp plist)))
    plist))

(defun file-device-probe (pathname operation)
  "OPEN probe PATHNAME; return its truename and property list, or the status."
  (declare (values truename plist status))
  (let ((name (file-device-name pathname operation)))
    (multiple-value-bind (status nil nil bytes mtime flags)
	(si:file-device-call si:%file-device-op-open si:%file-device-open-probe 0 name)
      (if (zerop status)
	  (let ((truename (file-device-truename pathname name)))
	    (values truename (file-device-plist truename bytes mtime flags) 0))
	(values nil nil status)))))

(defmethod (file-device-access :multiple-file-plists) (pathnames options)
  options					;:characters changes nothing here
  ;; the probes go out eight at a time, all in flight at once.  a batch cut
  ;; short by an abort leaves its unanswered probes to be freed by the driver.
  (let ((result nil) (batch nil))
    (unwind-protect
	(do ((rest pathnames)) ((null rest))
	  (dotimes (i 8.)
	    (when rest
	      (let* ((pathname (pop rest))
		     (name (condition-case () (file-device-name pathname :properties)
			     (file-error nil))))
		(setq batch
		      (nconc batch
			     (list (list pathname name
					 (and name
					      (multiple-value-list
						(si:file-device-submit
						  si:%file-device-op-open
						  si:%file-device-open-probe 0 name))))))))))
	  (do () ((null batch))
	    (destructuring-bind (pathname name submitted) (car batch)
	      (push (if (null submitted) (list pathname)
		      (multiple-value-bind (status nil nil bytes mtime flags)
			  (si:file-device-wait (first submitted) (second submitted))
			(if (zerop status)
			    (let ((truename (file-device-truename pathname name)))
			      (cons pathname (file-device-plist truename bytes mtime flags)))
			  (list pathname))))
		    result))
	    (pop batch)))
      (dolist (item batch)
	(when (third item) (si:file-device-abandon (first (third item))))))
    (nreverse result)))

(defun file-device-word (string start)
  "The little-endian 32-bit word of STRING's bytes from START."
  (+ (aref string start) (ash (aref string (+ start 1)) 8.)
     (ash (aref string (+ start 2)) 16.) (ash (aref string (+ start 3)) 24.)))

(defun file-device-directory-entries (pathname directory operation noerror)
  "Every entry of DIRECTORY, a device name: a list of (name length mtime flags), or a condition."
  (do ((cookie 0) (entries nil)) (())
    (multiple-value-bind (status count nil nil nil nil next b)
	(si:file-device-call si:%file-device-op-directory 0 0 directory :page cookie 0 t)
      (unless (zerop status)
	(return (file-device-error status operation pathname noerror)))
      (do ((i 0)) ((>= i count))
	(let* ((word0 (file-device-word b i))
	       (name-length (ldb #o0010 word0))
	       (record-words (ldb #o1010 word0)))
	  (push (list (substring b (+ i 12.) (+ i 12. name-length))
		      (if (ldb-test #o2201 word0) nil (file-device-word b (+ i 4)))
		      (file-device-word b (+ i 8.))
		      (ldb #o2003 word0))
		entries)
	  (setq i (+ i (* 4 (max record-words 3))))))
      (setq cookie next)
      (when (zerop cookie) (return (nreverse entries))))))

;; the wildcards of the last component, * and ?, matched here against the
;; names exactly, case and all, as ozd's DIRECTORY did: the device has no
;; wildcards, and its names are exact in case, while :pathname-match
;; compares in interchange case (pathnm's convert-solid-case), where a
;; partial wildcard such as "foo*" and a mixed-case name need not compare
;; as the names themselves do.  (the reason given here before, that
;; :pathname-match compared a unix pathname's raw components with another's
;; case-converted ones, no longer holds: it now converts both.)
(defun file-device-wild-match (pattern name &optional (p 0) (n 0))
  (let ((plength (string-length pattern)) (nlength (string-length name)))
    (cond ((= p plength) (= n nlength))
	  ((= (aref pattern p) #/*)
	   (do ((k n (1+ k))) ((> k nlength) nil)
	     (when (file-device-wild-match pattern name (1+ p) k) (return t))))
	  ((= n nlength) nil)
	  ((or (= (aref pattern p) #/?) (= (aref pattern p) (aref name n)))
	   (file-device-wild-match pattern name (1+ p) (1+ n))))))

(defmethod (file-device-access :directory-list) (pathname options)
  (let ((noerror (memq :noerror options))
	(directories-only (memq :directories-only options))
	(name (pathname-name pathname))
	(type (pathname-type pathname)))
    (if (and name (not (memq name '(:wild :unspecific)))
	     (not (eq type :wild))
	     (not (send pathname :wild-p)))
	;; one file: PATHNAME :PROPERTIES asks this way.  one probe.
	(condition-case-if noerror (condition)
	    (multiple-value-bind (truename plist status)
		(file-device-probe pathname :directory-list)
	      (if (zerop status)
		  (list (list nil) (cons truename plist))
		(file-device-error status :directory-list pathname)))
	  (file-error condition))
      (condition-case-if noerror (condition)
	  (let* ((directory (file-device-name pathname :directory-list t))
		 (pattern (unix-filename (pathname-raw-name pathname) (pathname-raw-type pathname)))
		 (entries (file-device-directory-entries pathname directory
							 :directory-list nil))
		 (list nil))
	    (dolist (entry entries)
	      (destructuring-bind (entry-name bytes mtime flags) entry
		(when (and (or (not directories-only) (ldb-test #o0001 flags))
			   (file-device-wild-match pattern entry-name))
		  (let ((entry-pathname (parse-pathname (string-append directory entry-name) host)))
		    (push (cons entry-pathname
				(let ((plist (list :creation-date (file-device-universal-time mtime)
						   :byte-size 8)))
				  (when bytes
				    (setq plist (list* :length-in-bytes bytes
						       :length-in-blocks (ceiling bytes 1024.)
						       plist)))
				  (if (ldb-test #o0001 flags) (list* :directory t plist) plist)))
			  list)))))
	    (setq list (nreverse list))
	    (when (memq :sorted options)
	      (setq list (sortcar list #'pathname-lessp)))
	    (cons (list nil :settable-properties nil) list))
	(file-error condition)))))

(defmethod (file-device-access :complete-string) (pathname string options)
  options
  (let* ((slash (string-reverse-search-char #// string))
	 (directory (cond ((null slash) (send pathname :string-for-directory))
			  ((and (plusp (string-length string)) (= (aref string 0) #//))
			   (substring string 0 (1+ slash)))
			  (t (string-append (send pathname :string-for-directory)
					    (substring string 0 (1+ slash))))))
	 (prefix (if slash (substring string (1+ slash)) string))
	 (name (file-device-name (parse-pathname directory host) :complete-string t)))
    (multiple-value-bind (status nil nil nil nil flags matches completion)
	(si:file-device-call si:%file-device-op-complete 0 0
			     (string-append name prefix) :page 0 0 t)
      (let ((success (cond ((not (zerop status)) nil)
			   ((ldb-test si:%%file-device-flag-complete-exact flags) :old)
			   ((plusp matches) :new))))
	(values (string-append (send host :name-as-file-computer) ": " name
			       (if success completion prefix))
		success)))))

;;;; Streams

(defflavor file-device-stream-mixin
	(access truename (handle nil) (status :open))
	(si:property-list-mixin si:file-stream-mixin)
  (:initable-instance-variables access truename handle status)
  (:gettable-instance-variables access truename handle status))

(defmethod (file-device-stream-mixin :qfaslp) () (getf si:property-list :qfaslp))
(defmethod (file-device-stream-mixin :length) () (getf si:property-list :length))
(defmethod (file-device-stream-mixin :properties) (&optional ignore)
  (values (cons truename si:property-list) nil))

(defflavor file-device-probe-stream () (file-device-stream-mixin si:stream)
  (:default-init-plist :status :closed))

(defmethod (file-device-probe-stream :direction) () nil)
(defmethod (file-device-probe-stream :close) (&optional ignore) nil)
(defmethod (file-device-probe-stream :byte-size) () (getf si:property-list :byte-size))

;; a data stream owns a wired rqb of four pages, one command a page.  the
;; rqb is its buffer: characters see it as a string, 16-bit bytes as an
;; art-16b array, 8-bit bytes as an art-8b one.  while a command names its
;; pages the device owns them: an aborted stream leaves the rqb to be given
;; back when the last such command is answered.
(defconst file-device-stream-pages 4)

(defun file-device-transfer (opcode rqb handle offset byte-count &optional who)
  "READ or WRITE BYTE-COUNT bytes between RQB's pages and the file at OFFSET,
one command a page, all in flight at once.  Returns the bytes moved and the
index of the last command, or signals the file condition of a failed one,
for WHO, a stream or a pathname."
  (declare (values count last-index))
  (let ((submitted nil) (total 0) (short nil) (last-index nil)
	(page-bytes (* si:page-size 4)))
    (unwind-protect
	(progn
	  (do ((page 0 (1+ page))) ((>= (* page page-bytes) byte-count))
	    (let* ((length (min page-bytes (- byte-count (* page page-bytes))))
		   (buffer (list (si:file-device-rqb-page-address rqb page) length)))
	      (multiple-value-bind (index generation)
		  (if (= opcode si:%file-device-op-read)
		      (si:file-device-submit opcode 0 handle nil buffer
					     (+ offset (* page page-bytes)))
		    (si:file-device-submit opcode 0 handle buffer nil
					   (+ offset (* page page-bytes))))
		(setq last-index index)
		(setq submitted (nconc submitted (list (list index generation length)))))))
	  (do () ((null submitted))
	    (destructuring-bind (index generation length) (car submitted)
	      (multiple-value-bind (status count) (si:file-device-wait index generation)
		(pop submitted)
		(unless (zerop status)
		  (file-device-error status (if (= opcode si:%file-device-op-read) :read :write)
				     who))
		(unless short (incf total count))
		(when (< count length) (setq short t)))))
	  (values total last-index))
      (dolist (item submitted)
	(si:file-device-abandon (first item))))))

(defflavor file-device-data-stream-mixin
	(rqb
	 bytes					;art-8b view of the rqb
	 byte-size				;:characters, 8 or 16
	 generation				;the driver's, at open
	 (file-offset 0)			;bytes, the next transfer's
	 (last-index nil))			;the last command naming the rqb
	(file-device-stream-mixin)
  (:included-flavors si:file-data-stream-mixin)
  (:initable-instance-variables rqb bytes byte-size generation file-offset last-index)
  (:gettable-instance-variables byte-size))

(defmethod (file-device-data-stream-mixin :element-type) ()
  (if (eq byte-size :characters) 'string-char `(unsigned-byte ,byte-size)))

(defun file-device-element-bytes ()
  (declare (:self-flavor file-device-data-stream-mixin))
  (if (eql byte-size 16.) 2 1))

(defun file-device-buffer ()
  "The rqb as the stream's buffer array."
  (declare (:self-flavor file-device-data-stream-mixin))
  (case byte-size
    (:characters (si:rqb-8-bit-buffer rqb))
    (16. (si:rqb-buffer rqb))
    (t bytes)))

(defun file-device-stream-transfer (opcode byte-count)
  (declare (:self-flavor file-device-data-stream-mixin))
  (when (not (= generation si:file-device-generation))
    (ferror nil "The file device was reset while ~A was open." truename))
  (multiple-value-bind (count index)
      (file-device-transfer opcode rqb handle file-offset byte-count self)
    (and index (setq last-index index))
    count))

(defmethod (file-device-data-stream-mixin :close) (&optional abortp)
  (unless (eq status :closed)
    (unwind-protect
	(send self :close-handle abortp)
      (setq status :closed)
      (si:file-device-return-rqb rqb last-index generation)
      (send access :remove-stream self))))

(defflavor file-device-input-stream-mixin ((prefill nil)) (file-device-data-stream-mixin)
  (:settable-instance-variables prefill)
  (:included-flavors si:input-file-stream-mixin))

(defun file-device-fill ()
  "Read the next buffer into the rqb; return the bytes read, 0 at the end of the file."
  (declare (:self-flavor file-device-input-stream-mixin))
  (let* ((remaining (- (getf si:property-list :length-in-bytes) file-offset))
	 (total (if (plusp remaining)
		    (file-device-stream-transfer si:%file-device-op-read
						 (min remaining (* file-device-stream-pages
								   si:page-size 4)))
		  0)))
    (incf file-offset total)
    total))

(defmethod (file-device-input-stream-mixin :next-input-buffer) (&optional ignore)
  (when (eq status :closed)
    (ferror nil "Attempt to get input from ~S, which is closed." self))
  (let ((total (if prefill (prog1 prefill (setq prefill nil)) (file-device-fill))))
    (cond ((zerop total) nil)
	  (t (when (eq byte-size :characters)
	       (file-device-translate file-device-read-translation bytes 0 total))
	     (values (file-device-buffer) 0 (floor total (file-device-element-bytes)))))))

(defmethod (file-device-input-stream-mixin :discard-input-buffer) (ignore) nil)

(defmethod (file-device-input-stream-mixin :set-buffer-pointer) (new-pointer)
  (let ((offset (* new-pointer (file-device-element-bytes))))
    (when (or (minusp offset) (> offset (getf si:property-list :length-in-bytes)))
      (file-device-error 16. :set-pointer self))
    (setq prefill nil file-offset offset)
    new-pointer))

(defmethod (file-device-input-stream-mixin :close-handle) (ignore)
  (when (and handle (= generation si:file-device-generation))
    (let ((reply (si:file-device-call si:%file-device-op-close 0 handle)))
      (unless (zerop reply)
	(file-device-error reply :close self)))))

(defflavor file-device-output-stream-mixin ((date nil)) (file-device-data-stream-mixin)
  (:included-flavors si:output-file-stream-mixin))

(defmethod (file-device-output-stream-mixin :new-output-buffer) ()
  (when (eq status :closed)
    (ferror nil "Attempt to do output on ~S, which is closed." self))
  (values (file-device-buffer) 0
	  (floor (* file-device-stream-pages si:page-size 4) (file-device-element-bytes))))

(defmethod (file-device-output-stream-mixin :send-output-buffer) (ignore end)
  (let ((count (* end (file-device-element-bytes))))
    (when (plusp count)
      (when (eq byte-size :characters)
	(file-device-translate file-device-write-translation bytes 0 count))
      (let ((moved (file-device-stream-transfer si:%file-device-op-write count)))
	(unless (= moved count)
	  (file-device-error 15. :write self))
	(incf file-offset moved)))))

(defmethod (file-device-output-stream-mixin :discard-output-buffer) (ignore) nil)

(defmethod (file-device-output-stream-mixin :set-buffer-pointer) (new-pointer)
  (setq file-offset (* new-pointer (file-device-element-bytes)))
  new-pointer)

;; COPY-FILE sends :creation-date and :author together (open.lisp): the date
;; is set at CLOSE, and the author, which the host does not keep, is taken
;; and dropped.
(defmethod (file-device-output-stream-mixin :change-properties) (error-p &rest properties)
  (loop for (property value) on properties by 'cddr
	do (case property
	     (:creation-date (setq date value))
	     (:author)
	     (t (return (file-process-error 'unknown-property "Property cannot be set" self
					    nil (not error-p) property))))
	finally (return t)))

(defmethod (file-device-output-stream-mixin :close-handle) (abortp)
  (cond ((not (= generation si:file-device-generation))
	 (unless abortp
	   (ferror nil "The file device was reset while ~A was open for output; ~
the file was not written." truename)))
	(handle
	 (multiple-value-bind (reply nil nil length mtime)
	     (si:file-device-call si:%file-device-op-close
				  (+ (if abortp 1 0) (if (and date (not abortp)) 2 0))
				  handle nil nil 0
				  (if date (- date unix-epoch-universal-time) 0))
	   (cond ((not (zerop reply))
		  (unless abortp (file-device-error reply :close self)))
		 ((not abortp)
		  ;; the creation date comes only from here: the host may
		  ;; keep times to 2 s.
		  (setf (getf si:property-list :creation-date)
			(file-device-universal-time mtime)
			(getf si:property-list :length-in-bytes) length
			(getf si:property-list :length-in-blocks) (ceiling length 1024.)
			(getf si:property-list :length)
			(ceiling length (file-device-element-bytes)))))))))

(defflavor file-device-character-input-stream ()
	   (file-device-input-stream-mixin si:input-file-stream-mixin
	    si:buffered-input-character-stream))

(defflavor file-device-binary-input-stream ()
	   (file-device-input-stream-mixin si:input-file-stream-mixin
	    si:buffered-input-stream))

(defflavor file-device-character-output-stream ()
	   (file-device-output-stream-mixin si:output-file-stream-mixin
	    si:buffered-output-character-stream))

(defflavor file-device-binary-output-stream ()
	   (file-device-output-stream-mixin si:output-file-stream-mixin
	    si:buffered-output-stream))

(compile-flavor-methods file-device-probe-stream
			file-device-character-input-stream file-device-binary-input-stream
			file-device-character-output-stream file-device-binary-output-stream)

;;;; Open

(defun file-device-element-type (element-type byte-size)
  "Decode OPEN's element type: CHARACTERS (T, NIL or :DEFAULT) and the byte size."
  (declare (values characters byte-size))
  (cond ((memq element-type '(:default)) (values :default byte-size))
	((memq element-type '(string-char standard-char character)) (values t :default))
	((eq element-type 'unsigned-byte) (values nil :default))
	((and (consp element-type) (memq (car element-type) '(unsigned-byte mod)))
	 (values nil (if (eq (car element-type) 'mod)
			 (haulong (1- (cadr element-type)))
		       (cadr element-type))))
	(t (ferror 'unimplemented-option "~S is not implemented as an ELEMENT-TYPE on HOST."
		   element-type))))

(defmethod (file-device-access :open) (file pathname &rest options)
  (apply #'file-device-open self file pathname options))

(defun file-device-open (access file pathname
			 &key (direction :input) (characters t) (error t)
			      (element-type 'string-char element-type-p)
			      (if-exists :new-version)
			      (if-does-not-exist
				;; direction nil, the old probe, errs by default
				;; (probe-file counts on it), as qfile's open does.
				(cond ((memq direction '(:probe :probe-link :probe-directory))
				       nil)
				      ((and (eq direction :output)
					    (not (memq if-exists '(:overwrite :truncate :append))))
				       :create)
				      (t :error)))
			      (byte-size :default)
			 &allow-other-keys)
  (ccase direction
    ((:input :output :probe-directory))
    ((nil :probe :probe-link) (setq direction nil)))
  (check-type if-exists (member :error :new-version :rename :rename-and-delete
				:overwrite :append :truncate :supersede nil))
  (check-type if-does-not-exist (member :error :create nil))
  (when element-type-p
    (multiple-value-setq (characters byte-size) (file-device-element-type element-type byte-size)))
  (condition-case-if (not error) (condition)
      (condition-case-if (null if-does-not-exist) ()
	  (condition-case-if (null if-exists) ()
	      (file-device-open-1 access file pathname direction characters byte-size
				  if-exists if-does-not-exist)
	    (file-already-exists nil))
	(file-not-found nil))
    (file-error condition)))

(defun file-device-open-1 (access file pathname direction characters byte-size
			   if-exists if-does-not-exist)
  ;; :probe-directory asks about the directory whatever name and type the
  ;; pathname was given by merging.
  (let ((name (file-device-name file :open (eq direction :probe-directory)))
	(probe (memq direction '(nil :probe-directory))))
    (when (and (null characters) (not (memq byte-size '(:default 8. 16.))))
      (file-process-error 'invalid-byte-size
			  (format nil "Byte size ~D is not 8 or 16" byte-size) file nil nil :open))
    (when (memq if-exists '(:rename :rename-and-delete))
      (file-process-error 'unimplemented-option
			  (format nil "IF-EXISTS ~S is not implemented" if-exists)
			  file nil nil :open))
    (let ((flags (case direction
		   (:input si:%file-device-open-read)
		   (:output (+ si:%file-device-open-write
			       (ash (case if-exists
				      ((:error nil) 1)
				      (:append 2)
				      (t 0))
				    2)
			       (if (eq if-does-not-exist :create) 0 (ash 1 4))))
		   (t si:%file-device-open-probe))))
      (multiple-value-bind (status nil handle bytes mtime reply-flags)
	  (si:file-device-call si:%file-device-op-open flags 0 name)
	(unless (zerop status)
	  (file-device-error status :open file))
	(let ((truename (file-device-truename file name))
	      (directory-p (ldb-test si:%%file-device-flag-directory reply-flags)))
	  (cond ((not probe)
		 (file-device-data-stream access pathname truename direction handle
					  bytes mtime characters byte-size if-exists))
		;; one probe mode in the device; the kinds are told apart here.
		((if (eq direction :probe-directory) (not directory-p)
		   (and directory-p (send file :name)))
		 (file-device-error 11. :open file))
		(t (make-instance 'file-device-probe-stream
				  :access access :pathname pathname :truename truename
				  :property-list (file-device-plist truename bytes mtime
								    reply-flags)))))))))

(defun file-device-data-stream (access pathname truename direction handle bytes mtime
				characters byte-size if-exists)
  "Make the stream for an open HANDLE; close the handle if that fails."
  (let ((rqb (si:get-disk-rqb file-device-stream-pages))
	(generation si:file-device-generation)
	(stream nil) (prefill nil) (last-index nil) (qfaslp nil))
    (unwind-protect
	(let ((view (si:file-device-8-bit-view rqb)))
	  (si:wire-disk-rqb rqb file-device-stream-pages t t)
	  (when (and (eq direction :input) (eq characters :default))
	    ;; read the first buffer now, to decide by the qfasl magic as ozd does.
	    (multiple-value-setq (prefill last-index)
	      (file-device-transfer si:%file-device-op-read rqb handle 0
				    (min bytes (* file-device-stream-pages si:page-size 4))
				    truename))
	    (setq qfaslp (file-device-qfasl-bytes-p view prefill)
		  characters (not qfaslp)))
	  (let ((size (cond (characters :characters)
			    ((eq byte-size :default) 16.)
			    (t byte-size))))
	    (setq stream
		  (make-instance
		    (if (eq direction :output)
			(if characters 'file-device-character-output-stream
			  'file-device-binary-output-stream)
		      (if characters 'file-device-character-input-stream
			'file-device-binary-input-stream))
		    :access access :pathname pathname :truename truename
		    :handle handle :rqb rqb :bytes view :byte-size size
		    :generation generation :last-index last-index
		    :file-offset (cond (prefill prefill)
				       ((eq if-exists :append) bytes)
				       (t 0))
		    :property-list
		    (if (eq direction :output)
			(list :truename truename)
		      (file-device-plist truename bytes mtime 0 (if characters t :binary)
					 size qfaslp)))))
	  (when prefill (send stream :set-prefill prefill))
	  (send access :add-stream stream)
	  stream)
      (unless stream
	(si:file-device-return-rqb rqb last-index generation)
	(when (= generation si:file-device-generation)
	  (si:file-device-call si:%file-device-op-close
			       (if (eq direction :output) 1 0) handle))))))

(compile-flavor-methods file-device-access)
