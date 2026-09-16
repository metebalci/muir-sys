; -*- Mode:LISP; Package:FILE-SYSTEM; Base:8; Readtable:ZL -*-

;;;; Logical pathnames and hosts

(DEFUN TRANSLATED-PATHNAME (PATHNAME)
  "Return translated pathname made from PATHNAME.
If PATHNAME refers to a logical host, the result will refer to the
corresponding physical host."
  (SEND (PATHNAME PATHNAME) :TRANSLATED-PATHNAME))

(DEFUN BACK-TRANSLATED-PATHNAME (LOGICAL-PATHNAME ACTUAL-PATHNAME)
  "Try to untranslate ACTUAL-PATHNAME for the host of LOGICAL-PATHNAME.
If LOGICAL-PATHNAME indeed refers to a logical host, and ACTUAL-PATHNAME
is a pathname that could be produced by translation of some logical pathname
on that host, then said logical pathname is returned.
Otherwise, ACTUAL-PATHNAME is returned."
  (SEND (PATHNAME LOGICAL-PATHNAME) :BACK-TRANSLATED-PATHNAME (PATHNAME ACTUAL-PATHNAME)))

(DEFFLAVOR LOGICAL-PATHNAME () (PATHNAME))
 
(DEFMETHOD (LOGICAL-PATHNAME :STRING-FOR-PRINTING) ()
  (LET* ((DEFAULT-CONS-AREA PATHNAME-AREA)
	 (DIR (IF (ATOM DIRECTORY)		;lose!
		  (LIST (STRING-OR-WILD DIRECTORY))
		  (MAPCAR #'STRING-OR-WILD DIRECTORY)))
	 (DEV (LOGICAL-DEVICE-STRING))
	 (NAM (LOGICAL-NAME-STRING))
	 (TYP (LOGICAL-TYPE-STRING))
	 (VER (LOGICAL-VERSION-STRING)))	; can actually be a number
	(FORMAT NIL "~A: ~@[~A: ~]~:[~{~A; ~}~;~*~]~@[~A~]~@[ ~A~]~@[ ~A~]"
	    (SEND HOST :NAME-AS-FILE-COMPUTER)
	    DEV
	    (SI:MEMBER-EQUAL DIRECTORY '(NIL (:UNSPECIFIC)))
	    DIR NAM TYP (IF (NUMBERP VER) (FORMAT NIL "~D" VER) VER))))

(DEFMETHOD (LOGICAL-PATHNAME :STRING-FOR-DIRECTORY) ()
  (LET ((DIR (IF (ATOM DIRECTORY) (LIST (STRING-OR-WILD DIRECTORY))
	       (MAPCAR 'STRING-OR-WILD DIRECTORY)))
	(DEV (LOGICAL-DEVICE-STRING)))
    (FORMAT NIL "~@[~A: ~]~:[~{~A;~^ ~}~;~]"
	    DEV
	    (SI:MEMBER-EQUAL DIRECTORY '(NIL (:UNSPECIFIC)))
	    DIR)))

(DEFF LOGICAL-NAME-STRING 'ITS-FN1-STRING)

(DEFUN LOGICAL-DEVICE-STRING ()
  (DECLARE (:SELF-FLAVOR LOGICAL-PATHNAME))
  (IF (MEMQ DEVICE '(NIL :UNSPECIFIC))
      NIL
    (STRING-OR-WILD DEVICE)))

(DEFUN LOGICAL-TYPE-STRING (&OPTIONAL NO-PLACEHOLDER)
  (DECLARE (:SELF-FLAVOR LOGICAL-PATHNAME))
  (COND ((EQ TYPE :UNSPECIFIC) "")
	((NULL TYPE)
	 (AND (NOT NO-PLACEHOLDER)
	      VERSION
	      ""))
	(T
	 (STRING-OR-WILD TYPE))))

;;; Contrary to its name, this can also return NIL or numbers as well as strings
(DEFUN LOGICAL-VERSION-STRING ()
  (DECLARE (:SELF-FLAVOR LOGICAL-PATHNAME))
  (CASE VERSION
    (:UNSPECIFIC "")
    (NIL NIL)
    (:NEWEST ">")
    (:OLDEST "<")
    (:WILD "*")
    (OTHERWISE VERSION)))

(DEFMETHOD (LOGICAL-PATHNAME :PARSE-NAMESTRING) (IGNORE NAMESTRING &OPTIONAL (START 0) END)
  (OR END (SETQ END (STRING-LENGTH NAMESTRING)))
  (DO ((I START)
       (J START (1+ J))
       CH TEM Q
       DIR NAM NAMP TYP TYPP VERS)
      ((> J END)
       (SETQ DIR (NREVERSE DIR))
       (VALUES :UNSPECIFIC DIR NAM TYP VERS))
    (SETQ CH (IF (= J END) #/SPACE (CHAR NAMESTRING J)))
    (COND ((CHAR= CH #/)
	   (INCF J))
	  ((MEMQ CH '(#/; #/: #/ #/ #/SPACE #/TAB #/.))
	   (COND ((OR ( I J) (CHAR= CH #/) (CHAR= CH #/))
		  (AND (MEMQ CH '(#/ #/))
		       (OR ( I J)
			   (AND ( (1+ J) END)
				(CHAR (CHAR NAMESTRING (1+ J)) #/SPACE)))
		       (PATHNAME-ERROR (1+ J) NAMESTRING
				       "An unquoted ~C must be a component unto itself." CH))
		  (MULTIPLE-VALUE-SETQ (TEM Q)
		    (CASE CH
		      (#/ (VALUES :UNSPECIFIC NIL))
		      (#/ (VALUES NIL NIL))
		      (T (UNQUOTE-LOGICAL-STRING NAMESTRING I J))))
		  (IF (AND (NOT Q) (STRING= TEM "*"))
		      (SETQ TEM ':WILD))
		  (CASE CH
		    (#/: NIL)			;Ignore "devices"
		    (#/; (PUSH TEM DIR))
		    (OTHERWISE
		     (COND (VERS)
			   (TYPP (SETQ VERS (COND ((MEMQ TEM '(:UNSPECIFIC :WILD)) TEM)
						  ((AND (NOT Q)
							(COND ((STRING= TEM ">") :NEWEST)
							      ((STRING= TEM "<") :OLDEST)
							      ((NUMERIC-P TEM)))))
						  (T (PATHNAME-ERROR J NAMESTRING
						       "Version not numeric")))))
			   (NAMP (SETQ TYP TEM TYPP T))
			   (T (SETQ NAM TEM NAMP T)))))))
	   (SETQ I (1+ J))))))

(DEFMETHOD (LOGICAL-PATHNAME :QUOTE-CHARACTER) ()
  #/)

(DEFMETHOD (LOGICAL-PATHNAME :CHARACTER-NEEDS-QUOTING-P) (CH)
  (OR ( #/a CH #/z)
      (MEM #'= CH '(#/: #/; #/ #/ #/. #/SP #/TAB))))

(DEFUN UNQUOTE-LOGICAL-STRING (STRING &OPTIONAL (START 0) (END (STRING-LENGTH STRING)))
  (DO ((I START (1+ I))
       (NCH 0) (CH)
       (NEED-COPY NIL))
      (( I END)
       (COND ((AND (= START 0) (= I (STRING-LENGTH STRING)) (NOT NEED-COPY))
	      STRING)				;To avoid consing
	     ((NOT NEED-COPY)
	      (SUBSTRING STRING START I))
	     (T
	      (DO ((NSTRING (MAKE-STRING NCH))
		   (J 0)
		   (K START (1+ K))
		   CHAR-QUOTED
		   (CH))
		  (( K I) (VALUES NSTRING T))
		(SETQ CH (AREF STRING K))
		(COND (( CH #/)
		       (SETF (AREF NSTRING J) (IF CHAR-QUOTED CH (CHAR-UPCASE CH)))
		       (SETQ CHAR-QUOTED NIL)
		       (INCF J))
		      (T (SETQ CHAR-QUOTED T)))))))
    (SETQ CH (AREF STRING I))
    (IF (= CH #/)
	(SETQ NEED-COPY T)
      (IF ( #/a CH #/z) (SETQ NEED-COPY T))
      (INCF NCH))))

(DEFMETHOD (LOGICAL-PATHNAME :PARSE-DIRECTORY-SPEC) (SPEC)
  (COND ((STRINGP SPEC) (SEND SELF :PARSE-COMPONENT-SPEC SPEC))
	((CONSP SPEC)
	 (MAPCAR SELF (CIRCULAR-LIST :PARSE-COMPONENT-SPEC) SPEC))
	((MEMQ SPEC '(NIL :UNSPECIFIC :WILD)) SPEC)
	(T (PATHNAME-DIRECTORY (QUIET-USER-HOMEDIR HOST)))))

(DEFMETHOD (LOGICAL-PATHNAME :COMPLETE-STRING) (STRING OPTIONS &AUX STRING1 FOO SUCCESS)
  (LET ((TRANSLATED (SEND (PARSE-PATHNAME STRING HOST) :TRANSLATED-PATHNAME)))
    (SETQ STRING1 (SEND TRANSLATED :STRING-FOR-HOST))
;    ;; This used to be just :STRING-FOR-PRINTING,
;    ;; but we want to get rid of the 's that NIL components would make.
;    (SETQ STRING1
;	  (IF (NOT (MEMQ (SEND TRANSLATED :VERSION) '(NIL :UNSPECIFIC)))
;	      (SEND TRANSLATED :STRING-FOR-PRINTING)
;	    (IF (SEND TRANSLATED :TYPE)
;		(SEND (SEND TRANSLATED :NEW-VERSION :NEWEST) :STRING-FOR-PRINTING)
;	      (STRING-APPEND (SEND (SEND TRANSLATED :NEW-PATHNAME
;					 :NAME NIL :TYPE NIL)
;				   :STRING-FOR-PRINTING)
;			     (SEND TRANSLATED :NAME)))))
;    (SETQ STRING1 (SUBSTRING STRING1 (1+ (STRING-SEARCH-CHAR #/: STRING1))))
    )
  ;; What STRING1 is will match the :STRING-FOR-HOST for many kinds of pathname,
  ;; but not for all.
  (LET (BASE-PATHNAME)
    (CONDITION-CASE ()
	(SETQ BASE-PATHNAME (SEND SELF :TRANSLATED-PATHNAME))
      (UNKNOWN-LOGICAL-PATHNAME-TRANSLATION
       (SETQ BASE-PATHNAME
	     (SEND (SEND (SEND SELF :NEW-DIRECTORY NIL) :TRANSLATED-PATHNAME)
		   :NEW-DIRECTORY (SEND SELF :DIRECTORY)))))
    (VALUES
      (SEND
	(SEND SELF :BACK-TRANSLATED-PATHNAME (PARSE-PATHNAME (MULTIPLE-VALUE (FOO SUCCESS)
							       (SEND BASE-PATHNAME
								     :COMPLETE-STRING
								     STRING1
								     OPTIONS))))
	:STRING-FOR-PRINTING)
      SUCCESS)))

(DEFUN LOGICAL-PATHNAME-PASS-ON (&REST REST)
  (DECLARE (:SELF-FLAVOR LOGICAL-PATHNAME))
  (LEXPR-SEND (SEND SELF :TRANSLATED-PATHNAME) REST))

(DEFMETHOD (LOGICAL-PATHNAME :STRING-FOR-HOST) LOGICAL-PATHNAME-PASS-ON)
(DEFMETHOD (LOGICAL-PATHNAME :STRING-FOR-WHOLINE) LOGICAL-PATHNAME-PASS-ON)
(DEFMETHOD (LOGICAL-PATHNAME :STRING-FOR-EDITOR) LOGICAL-PATHNAME-PASS-ON)
(DEFMETHOD (LOGICAL-PATHNAME :CHANGE-PROPERTIES) LOGICAL-PATHNAME-PASS-ON)
(DEFMETHOD (LOGICAL-PATHNAME :EXPUNGE) LOGICAL-PATHNAME-PASS-ON)
(DEFMETHOD (LOGICAL-PATHNAME :OPEN) LOGICAL-PATHNAME-PASS-ON)
(DEFMETHOD (LOGICAL-PATHNAME :OPEN-CANONICAL-TYPE) LOGICAL-PATHNAME-PASS-ON)
(DEFMETHOD (LOGICAL-PATHNAME :DELETE) LOGICAL-PATHNAME-PASS-ON)
(DEFMETHOD (LOGICAL-PATHNAME :UNDELETE) LOGICAL-PATHNAME-PASS-ON)
(DEFMETHOD (LOGICAL-PATHNAME :RENAME) LOGICAL-PATHNAME-PASS-ON)
(DEFMETHOD (LOGICAL-PATHNAME :UNDELETABLE-P) LOGICAL-PATHNAME-PASS-ON)
(DEFMETHOD (LOGICAL-PATHNAME :HOMEDIR) LOGICAL-PATHNAME-PASS-ON)
(DEFMETHOD (LOGICAL-PATHNAME :MULTIPLE-FILE-PLISTS) LOGICAL-PATHNAME-PASS-ON)
(DEFMETHOD (LOGICAL-PATHNAME :PARSE-TRUENAME) LOGICAL-PATHNAME-PASS-ON)
(DEFMETHOD (LOGICAL-PATHNAME :DIRECTORY-LIST) LOGICAL-PATHNAME-PASS-ON)
(DEFMETHOD (LOGICAL-PATHNAME :DIRECTORY-LIST-STREAM) LOGICAL-PATHNAME-PASS-ON)
(DEFMETHOD (LOGICAL-PATHNAME :ALL-DIRECTORIES) LOGICAL-PATHNAME-PASS-ON)
(DEFMETHOD (LOGICAL-PATHNAME :STRING-FOR-DIRED) LOGICAL-PATHNAME-PASS-ON)

(DEFMETHOD (LOGICAL-PATHNAME :MAIL-FILE-FORMAT-COMPUTER) LOGICAL-PATHNAME-PASS-ON)
(DEFMETHOD (LOGICAL-PATHNAME :INBOX-BUFFER-FLAVOR) LOGICAL-PATHNAME-PASS-ON)

;;; These need to be passed on since otherwise the information on how they were created
;;; will be lost.
(DEFMETHOD (LOGICAL-PATHNAME :PATCH-FILE-PATHNAME) LOGICAL-PATHNAME-PASS-ON)
(DEFMETHOD (LOGICAL-PATHNAME :NEW-TYPE-AND-VERSION) LOGICAL-PATHNAME-PASS-ON)


(DEFFLAVOR LOGICAL-HOST
	(NAME					;Logical device name
	 PHYSICAL-HOST				;Host that turns into
	 TRANSLATIONS)				;The actual translations
	;; NON-DEFAULT-DEVICE-LIST  would record devices other than default-device for
	;; which GENERIC-PATHNAMES have been created for this host.  See discussion
	;; in PATHNM. Not implemented.  For now, if it would need this it just bombs
	;; in (method pathname :generic-pathname).
	(SI:BASIC-HOST)
  (:SETTABLE-INSTANCE-VARIABLES))

(DEFUN LOGICAL-HOST-PASS-ON (&REST REST)
  (DECLARE (:SELF-FLAVOR LOGICAL-HOST))
  (LEXPR-SEND PHYSICAL-HOST REST))

(DEFMETHOD (LOGICAL-HOST :PATHNAME-FLAVOR) () 'LOGICAL-PATHNAME)

(DEFMETHOD (LOGICAL-HOST :SYSTEM-TYPE) ()
  :LOGICAL)

;;;---!!! Is (LOGICAL-HOST :HOST) still used anywhere?
;;; old name
(defmethod (logical-host :host) () physical-host)

;;; These characteristics of a logical host are the same as those of the physical host
(DEFMETHOD (LOGICAL-HOST :NETWORK-TYPE) LOGICAL-HOST-PASS-ON)
(DEFMETHOD (LOGICAL-HOST :NETWORK-TYPEP) LOGICAL-HOST-PASS-ON)
(DEFMETHOD (LOGICAL-HOST :ENABLE-CAPABILITIES) LOGICAL-HOST-PASS-ON)
(DEFMETHOD (LOGICAL-HOST :DISABLE-CAPABILITIES) LOGICAL-HOST-PASS-ON)

(DEFMETHOD (LOGICAL-HOST :GMSGS-PATHNAME) LOGICAL-HOST-PASS-ON)

;;;; Actual installation and use of translations.
(defstruct (logical-pathname-translation :list (:conc-name translation-) (:alterant nil))
  logical-pattern
  physical-pattern)

(defmethod (logical-pathname :translated-pathname) ()
  (block done
    (do-forever
      (dolist (trans (send host :translations))
	(when (send (translation-logical-pattern trans) :pathname-match self t)
	  (return-from done
	    (send (translation-logical-pattern trans) :translate-wild-pathname
		  (translation-physical-pattern trans) self t))))
      (unless (or directory name type version)
	(return (send self :new-pathname :host (send host :physical-host) :device nil)))
      (signal-proceed-case ((newdir)
			    'unknown-logical-pathname-translation
			    "No translation for ~A." self)
	(:define-directory
	 (add-logical-host-translation
	   host (send self :new-pathname :name :wild :type :wild :version :wild)
	   newdir))))))

(defmethod (logical-pathname :back-translated-pathname) (pathname)
  (dolist (trans (send host :translations))
    (when (send (translation-physical-pattern trans) :pathname-match pathname t)
      (return
	(send (translation-physical-pattern trans) :translate-wild-pathname
	      (translation-logical-pattern trans) pathname t)))))

(deff change-logical-pathname-directory 'add-logical-host-translation)

(defun add-logical-host-translation (logical-host from-pattern to-pattern)
  "Add or modify translation of FROM-PATTERN in existing logical host LOGICAL-HOST.
It will translate to TO-PATTERN.
LOGICAL-HOST may be a host or host name.
FROM-PATTERN and TO-PATTERN may be pathnames or namestrings."
  (if (stringp logical-host)
      (setq logical-host (get-pathname-host logical-host)))
  (send logical-host :set-translations
	(delete-duplicates
	  (append (send logical-host :translations)
		  (ncons (decode-translation logical-host from-pattern to-pattern)))
	  :key #'car)))

(defun decode-translation (logical-host from-pattern to-pattern)
  (let ((parsed-from-pattern (parse-pathname from-pattern logical-host)))
    ;; Detect missing semicolon after directory name.
    (if (and (null (send parsed-from-pattern :directory))
	     (null (send parsed-from-pattern :type))
	     (null (send parsed-from-pattern :version))
	     (send parsed-from-pattern :name))
	(setq parsed-from-pattern
	      (send parsed-from-pattern :new-pathname
		    :directory (send parsed-from-pattern :name)
		    :name nil)))
    (make-logical-pathname-translation
      :logical-pattern (wildify parsed-from-pattern)
      :physical-pattern (wildify (parse-pathname to-pattern
						 (send logical-host :physical-host))))))

;;; Default the dir, name, type and version to wild.
;;; Default the device to the host's primary device.
(defun wildify (pathname)
  (make-pathname :host (pathname-host pathname)
		 :device (or (pathname-device pathname)
			     (send (pathname-host pathname) :primary-device))
		 :directory (or (pathname-directory pathname) :wild)
		 :name (or (pathname-name pathname) :wild)
		 :type (or (pathname-type pathname) :wild)
		 :version (or (pathname-version pathname) :wild)))

(defun set-logical-pathname-host (logical-host &key physical-host translations)
  "Define a logical host named LOGICAL-HOST, which translates to PHYSICAL-HOST.
TRANSLATIONS is a list of translations to use: each element looks like
 (logical-pattern physical-pattern),
 where each pattern is a file namestring with wildcards.
 Omitted components default to * (:WILD)."
  (let (log phys)
    (tagbody
	retry
	   (setq log (get-pathname-host logical-host t nil))
	   (unless (typep log '(or null logical-host))
	     (multiple-cerror () () ("~Creating the logical host with name /"~A/"
will override that name for the physical host ~S,
making /"~:2*~A/" unacceptable as a name for the physical host~" logical-host log)
	       ("Create the logical host anyway"
		(setq log nil))
	       ("Don't create the logical host"
		(return-from set-logical-pathname-host nil))
	       ("Supply a new name for the logical host"
		(let ((*query-io* *debug-io*))
		  (setq logical-host
			(string-upcase (prompt-and-read :string-trim
							"New name for logical host: "))))
		(go retry))))
	   (unless log
	     (setq log (make-instance 'logical-host :name logical-host))
	     (push log *logical-pathname-host-list*)))
    (setq phys (or (get-pathname-host physical-host t)
		   (si:parse-host physical-host)))
    ;; Here is a bit of a kludge for SI:SET-SITE.  If the physical host is not defined yet,
    ;; add it now.
    (unless (typep phys 'logical-host)
      (pushnew phys *pathname-host-list* :test 'eq))
    (send log :set-physical-host phys)
    (if translations
	(send log :set-translations
	      (loop for trans in translations
		    collect (decode-translation log (car trans) (cadr trans)))))
    (pushnew log *logical-pathname-host-list* :test 'eq)
    log))

(defun add-logical-pathname-host (logical-host physical-host translations)
  "Define a logical host named LOGICAL-HOST, which translates to PHYSICAL-HOST.
TRANSLATIONS is a list of translations to use: each element looks like
 (logical-pattern physical-pattern),
 where each pattern is a file namestring with wildcards.
 Omitted components default to * (:WILD)."
  (set-logical-pathname-host logical-host
			     :physical-host physical-host
			     :translations translations))

(defun make-logical-pathname-host (host-name &key (warn-about-redefinition t))
  "Defines HOST-NAME to be the name of a logical host.
If this conflicts the name or nickname of any physical host,
then and error is signalled, and the new logical host may be allowed to
override that name of the physical host.
This function loads the file SYS: SITE; host-name TRANSLATIONS, which should contain
a call to FS:SET-LOGICAL-PATHNAME-HOST to set up the translations for the host."
  (setq host-name (string-upcase (string host-name)))
  (let ((old (get-pathname-host host-name t))
	new file-id loaded-id)
    (catch-error-restart ((fs:remote-network-error fs:file-not-found)
			  "Give up loading logical pathname translations for ~A" host-name)
      (when (typep old 'logical-host)
	(setq loaded-id (send old :get 'make-logical-pathname-host))
	;; if previously defined by hand, don't load translations and clobber it
	(cond ((not loaded-id)
	       (return-from make-logical-pathname-host old))
	      (warn-about-redefinition
	       (format *error-output* "~&Warning: The logical host ~A is being redefined"
		       old))))
      ;; no need to give error if redefining physical host, as set-logical-pathname-host errs
      (let ((pathname (make-pathname :host "SYS"
				     :device :unspecific
				     :directory '("SITE")
				     :name host-name
				     :canonical-type :logical-pathname-translations
				     :version :newest)))
	(setq file-id (with-open-file (stream pathname :direction :probe
					      	       :if-does-not-exist :error)
			(send stream :info)))
	(unless (equal loaded-id file-id)
	  (load pathname :verbose nil :package (symbol-package 'foo)))))
    (cond ((typep (setq new (get-pathname-host host-name nil)) 'logical-host)
	   (send new :set :get 'make-logical-pathname-host file-id)
	   new)
	  (t (format *error-output*
		     "~&Warning: The logical host ~S was not defined by ~S."
		     host-name 'make-logical-pathname-host)
	     nil))))

;;;; Errors from untranslatable pathnames.

(DEFFLAVOR UNKNOWN-LOGICAL-PATHNAME-TRANSLATION () (PATHNAME-ERROR))

(DEFSIGNAL UNKNOWN-LOGICAL-PATHNAME-TRANSLATION UNKNOWN-LOGICAL-PATHNAME-TRANSLATION
	   (LOGICAL-PATHNAME)
  "Used when a logical pathname's directory is not recognized for that host.")

(DEFMETHOD (UNKNOWN-LOGICAL-PATHNAME-TRANSLATION :CASE :PROCEED-ASKING-USER
						 :DEFINE-DIRECTORY)
	   (PROCEED-FUN READ-OBJECT-FUN)
  "Proceed, reading a physical pathname translate this directory to, permanently."
  (FUNCALL PROCEED-FUN :DEFINE-DIRECTORY
	   (FUNCALL READ-OBJECT-FUN :STRING
		    "Filename to translate ~A to, permanently: "
		    (SEND (SEND SELF :LOGICAL-PATHNAME)
			  :NEW-PATHNAME :NAME :WILD :TYPE :WILD :VERSION :WILD))))

(COMPILE-FLAVOR-METHODS UNKNOWN-LOGICAL-PATHNAME-TRANSLATION)


(COMPILE-FLAVOR-METHODS LOGICAL-PATHNAME LOGICAL-HOST)

;;; This would be an initialization, except that this file is loaded too early.
;;; It is called from RESET-NON-SITE-HOSTS, which is an initialization.
(DEFUN DEFINE-SYS-LOGICAL-DEVICE (&OPTIONAL IGNORE)
  (MAKE-LOGICAL-PATHNAME-HOST "SYS" :WARN-ABOUT-REDEFINITION NIL))

