;;; -*- Mode:LISP; Package:FILE-SYSTEM; Base:8; Lowercase:T -*-

;;; This file contains all knowledge of pathnames for local files,
;;; pathstrings, and the format of pathstrings.

(defflavor lmfile-parsing-mixin (name-pathlist) ()
  (:required-flavors pathname))

;A PATHSTRING is a string form of description of a route through the hierarchy.
;The simplest kind is a sequence of node names separated by "\" or "/" characters.
;"/" is cleaner, but is a pain to use, so for now "\" is the usual choice.
;This pathstring refers to the node which is reached by the sequence of
;subnodes with those names, down from the root.
;"#" introduces a version spec, which can follow any node name or property.
;"^" in a pathstring refers to the supernode of the node reached by
;the path up to that point.
;"|" in a pathstring introduces a property name.  This refers to the node
;which is that property of the node specified by the path up to that point.
;The property name can be followed by "#" and a version spec.
;"~" in a pathstring refers to the root node, regardless of what comes before.

;Pathstrings can be divided arbitrarily into a directory and a name.
;This division is written as <directory>; <name> or as
;<name>  <directory>.  The division has no effect on which node is
;specified by the pathstring, because the directory and name are effectively
;concatenated.  However, certain pathname operations which modify the pathstring
;modify it in a way which depends on the division into directory and name.

;A PATHNAME is an instance which remembers pathlists for the directory and name.
;Pathnames can be sent messages to open files, etc.

;A PATHLIST is a partially parsed version of a pathstring.
;A pathlist is a list of pathsteps.  Each pathstep
;represents one step in a chain of nodes leading to the desired one.

;PATHSTEPs:  A pathstep is understood by a directory to identify
;a subnode, or a possible subnode, of the directory.
;This mapping need not be 1 to 1: many different pathsteps
;can identify the same subnode.  Also, which subnode is identified
;by a given pathstep can depend on what other subnodes exist
;(This happens for pathsteps with version ">" or "<", among others).
;There are some formats of pathstep which have a standard meaning.
;Other formats can be freely used in any way at all by any
;specific flavor of directory.

;Ordinarily a pathstep is a list
;whose car is a symbol saying what kind of pathstep it is.
;A couple of kinds of pathstep are standard,
;and others may be defined for a particular flavor of directory.
;A pathstep can also be an unparsed string, in which case the
;VALIDATE-PATHSTEP operation should parse it into an equivalent 
;(possibly flavor-specific) list.
;Unparsed strings still contain their quoting characters.
;A pathstep can also be symbol, but only certain symbols are allowed.
;The symbols allowed in a pathstep are:
; the symbol SUPERNODE, meaning the supernode of the preceding;
; the symbol ROOT, meaning the root node.
;These symbols can appear in pathlists of pathnames,
;but they are processed at a high level.
;Directories never receive them and do not understand them.
;They do not appear in pathnames that are truenames.

;These are the standard kinds of pathstep lists:
;(:VERSION pathstep version-spec) specifies a version of a file.
;This sort of pathstep is standard so that version numbers in pathnames
;can be manipulated without opening the directory.
;The cadr of this list is again a pathstep, 
;either a list or an unparsed string, never ROOT or SUPERNODE.
;(:MULTIPLE-NAMES name name ...) specifies several filenames.
;Each name is actually a pathstep, but most kinds of pathsteps,
;including :VERSION, :PROPERTY and :MULTIPLE-NAMES, do not make
;sense in this context and are not allowed.
;(:SUBNODE-PROPERTY pathstep propname version-spec)
;specifies a node identified as being a property of one of our subnodes.
;(:PROPERTY propname version-spec)
;specifies a property of the node specified so far.
;This is generated only for a property at the front of a name,
;or following "^".

;:SUBNODE-PROPERTY and :MULTIPLE-NAMES are pretty much
;different ways of doing similar things.  It is not clear yet
;which of them is the right thing for common constructs to use.
;Right now, dirs understand all three, so we can experiment
;with which one pathnames should use.

;A FULL-PATHSTEP is a pathstep that is completely parsed
;and which describes a particular subnode independent of what
;happens to other subnodes.  For example, it contains a version
;number which is actually a positive number, not > or <.
;Each subnode's dir-entry contains a full-pathstep for that subnode.

;A STANDARD-PATHSTEP is like a full-pathstep in that it clearly
;specifies a particular subnode, but instead of being fully parsed,
;it can use standard kinds of lists, and unparsed strings.
;The pathlist of a truename contains only standard pathsteps.
;The pathlist of any pathname contains only standard pathsteps,
;and the symbols ROOT and SUPERNODE.

(defun valid-subnode-property-pathstep-p (pathstep)
  (and (consp pathstep)
       (eq (car pathstep) :subnode-property)
       (consp (cdr pathstep))
       (consp (cddr pathstep))
       (stringp (caddr pathstep))
       (or (null (cdddr pathstep))
	   (consp (cdddr pathstep)))))

(defun valid-property-pathstep-p (pathstep)
  (and (consp pathstep)
       (eq (car pathstep) :property)
       (consp (cdr pathstep))
       (stringp (cadr pathstep))
       (or (null (cddr pathstep))
	   (consp (cddr pathstep)))))

;The Lisp machine pathname system was designed on the assumption
;that all file systems are Twenex.  A file system with different
;concepts needs crocks to interface to it.

;A lmfile-parsing-mixin remembers its information
;for the most part as a pathlist.
;However, this pathlist is divided (arbitrarily, by the user)
;into two parts, the "directory" and the "name" of the pathname.
;These are concatenated to get the pathlist of the file to be
;opened.

;Further exception: the last pathstep never has a version number.
;Instead, the "version" of the pathname is what ought to be
;its version number.  When it the actual pathlist is needed,
;this version number must be merged into the "name".

;Similarly, the "name" never ends with a subnode-property pathstep.
;When it would be expected to do so, instead the "type" of the
;pathname holds the property which is the last pathstep.
;When we want the actual pathlist to use, this must be merged in.

;Here we merge the "name", "type" and "version" into a pathlist
;which could be appended to the "directory" and then opened.
(declare-flavor-instance-variables (lmfile-parsing-mixin)
(defun merge-name-type-and-version ()
    (if (variable-boundp name-pathlist)
	name-pathlist
	(setq name-pathlist
	      (merge-name-type-and-version-1 name type version)))))

(defun merge-name-type-and-version-1 (name type version)
  (let (tem real-name
	(default-cons-area pathname-area))
    (setq real-name
	  (copylist
	    (cond ((eq name :wild)
		   '("*"))
		  ((eq name :unspecific)
		   nil)
		  (t name))))
    (cond ((and type
		(neq type :unspecific))
	   (setq tem type)
	   (and (or (eq tem :wild) (equal tem '("WILD")))
		(setq tem "*"))
	   (let ((last (car (last real-name))))
	     (if (or (symbolp last) (null last))
		 (setq real-name (append real-name `((:property ,tem))))
	       (if (and (equal last "*") (equal tem "*"))
		   nil
		 (rplaca (last real-name)
			 `(:subnode-property ,last ,tem)))))))
    (and version
	 (neq version :unspecific)
	 (not (atom real-name))
	 (let ((tem1 (last real-name))
	       real-version)
	   (setq real-version
		 (selectq version
		   (:oldest :<)
		   (:newest :>)
		   (:wild :*)
		   (:installed :!)
		   (:unspecific nil)
		   (t version)))
	   (cond ((symbolp (car tem1)))
		 ((and (consp (car tem1))
		       (eq (caar tem1) :property))
		  (rplaca tem1 (list :property (cadar tem1) real-version)))
		 ((and (consp (car tem1))
		       (eq (caar tem1) :subnode-property))
		  (rplaca tem1
			  `(:subnode-property ,(cadar tem1) ,(caddar tem1) ,real-version)))
		 (t (rplaca tem1 `(:version ,(car tem1) ,real-version))))))
    real-name))

(defmethod (lmfile-parsing-mixin :name-type-and-version) ()
  (merge-name-type-and-version))

(defun decompose-name-type-and-version (pathlist)
  (cond ((eq pathlist :wild)
	 (values :wild :wild :wild))
	(t
	 (let ((name pathlist)
	       type version)
	   ;; Now correct for the fact that we have to store the type and version
	   ;; in separate places.
	   (let ((tem (last name)))
	     (cond ((atom (car tem)))
		   ((eq (caar tem) :version)
		    (setq version (caddar tem)
			  name (nconc (butlast name) (list (cadar tem)))))
		   ((eq (caar tem) :subnode-property)
		    (setq version (car (cdddar tem))
			  type (caddar tem)
			  name (nconc (butlast name) (list (cadar tem)))))
		   ((eq (caar tem) :property)
		    (setq version (caddar tem)
			  type (cadar tem)
			  name (butlast name)))))
	   (cond ((equal name '("*")) (setq name :wild)))
	   (cond ((string-equal type "*")
		  (setq type :wild)))
	   (setq version (selectq version
			   (:> :newest)
			   (:< :oldest)
			   (:! :installed)
			   (:* :wild)
			   (t version)))
	   (values name type version)))))

(defmethod (lmfile-parsing-mixin :pathname-as-directory) ()
  (funcall-self :new-pathname :directory (append directory (merge-name-type-and-version))
		:name :unspecific :type :unspecific :version :unspecific))

(defmethod (lmfile-parsing-mixin :directory-pathname-as-file) (&aux dir nam)
  (cond ((or (atom directory) (null (cdr directory)))
	 (setq dir '(root)
	       nam (if (eq directory :unspecific) nil directory)))
	(t
	 (let ((last (last directory)))
	   (setq dir (ldiff directory last)
		 nam last))))
  (funcall (funcall-self :new-directory dir)
	   :new-name-type-and-version nam))

;To make a standard pathlist into a truename.
(defun pathlist-into-pathname (pathlist)
  (declare (special lfs-host))
  (let (nam typ vers)
    (setf (values nam typ vers)
	  (decompose-name-type-and-version
	    (break-out-pathlist-spaces (last pathlist))))
    (make-pathname-internal lfs-host
			    :unspecific (or (butlast pathlist) '(root))
			    nam typ vers)))

(defun break-out-pathlist-spaces (pathlist)
  (let ((l (last pathlist))
	str i vers)
    (cond ((stringp (car l)) (setq str (car l) vers nil))
	  ((and (consp (car l)) (eq (caar l) :version))
	   (setq str (cadar l) vers (caddar l))))
    (and str (setq i (last-unquoted-space str)))
    (if i
	(subst (list `(:subnode-property ,(substring str 0 i) ,(substring str (1+ i)) ,vers))
	       l pathlist)
      pathlist)))

(defun last-unquoted-space (string &aux quoted answer)
  (dotimes (i (string-length string))
    (or quoted (and (= (aref string i) #\space) (setq answer i)))
    (setq quoted (and (not quoted) (= (aref string i) #/))))
  answer)

;Turn pathnames into pathstrings.

(defmethod (lmfile-parsing-mixin :string-for-host) ()
  (let ((filename (pathlist-to-string (merge-name-type-and-version) name))
	(devstring
	  (if (eq device :unspecific)
	      ""
	    (string-append device ": ")))
	(dirstring
	  (and (neq directory :unspecific)
	       (if (and directory
			(not (equal directory '(root))))
		   (pathlist-to-string directory)
		   "~")))
	(default-cons-area pathname-area))
    (if (eq directory :unspecific)
	(string-append devstring filename)
      (string-append devstring
		     dirstring
		     (if name "; " ";")
		     filename))))

(defmethod (lmfile-parsing-mixin :string-for-printing) ()
  (let ((default-cons-area pathname-area)
	(hostname (funcall host :name-as-file-computer))
	(filename (funcall-self :string-for-host)))
    (string-append hostname ": " filename)))

(defmethod (lmfile-parsing-mixin :string-for-editor) ()
  (let ((default-cons-area pathname-area)
	(name-and-vers (pathlist-to-string (merge-name-type-and-version)))
	(hostname (funcall host :name-as-file-computer))
	(dir (and (neq directory :unspecific)
		  (pathlist-to-string directory))))
    (if (eq directory :unspecific)
	(string-append name-and-vers " " hostname ":")
      (string-append name-and-vers
		     "  "
		     hostname
		     ": "
		     dir))))

(defmethod (lmfile-parsing-mixin :string-for-dired) ()
  (let ((default-cons-area pathname-area)
	(string (pathlist-to-string (merge-name-type-and-version))))
    (string-append string)))

(defmethod (lmfile-parsing-mixin :string-for-directory) ()
  (if (eq directory :unspecific)
      "~;"
    (let ((default-cons-area pathname-area)
	  (s (pathlist-to-string directory)))
      (string-append s ";"))))

;This function takes a standard pathlist, one made up
;entirely of standard-pathsteps, and converts it to a pathstring.
;Use the :STANDARD-PATHLIST operation on a node to get
;is truename as a standard pathlist.
;We require a standard pathlist because each flavor of directory
;defines its own nonstandard pathsteps, and we can't possibly
;expect to know how to print them; and we don't want to have to
;open the directory nodes to ask them to do it.
;NON-NULL-ROOT means represent the root node by "~", not an empty string.
(defun pathlist-to-string (pathlist &optional non-null-root)
  (cond ((and non-null-root
	      (or (null pathlist)
		  (equal pathlist '(root))))
	 "~")
	(t
	 (format:output nil
	   (do ((pathrest pathlist (cdr pathrest))
		(base 10.)
		(ibase 10.)
		(*nopoint t)
		(need-\ nil t))
	       ((null pathrest))
	     (let ((pathelt (car pathrest)))
	       (print-pathstep pathelt need-\ pathrest)))))))

(defun print-pathstep (pathstep need-\ pathrest)
  (cond ((stringp pathstep)
	 (and need-\ (tyo #/\))
	 (princ pathstep)
	 (and (zerop (string-length pathstep))
	      (null (cdr pathrest))
	      (princ "\")))
	((eq pathstep 'supernode) (tyo #/^))
	((eq pathstep 'root) (tyo #/~))
	((eq (car pathstep) :version)
	 (and need-\ (tyo #/\))
	 (princ (cadr pathstep))
	 (tyo #/#)
	 (princ (caddr pathstep)))
	((eq (car pathstep) :subnode-property)
	 (print-pathstep (cadr pathstep) need-\ t)
	 (tyo #/|)
	 (princ (caddr pathstep))
	 (and (cadddr pathstep)
	      (progn (tyo #/#)
		     (princ (cadddr pathstep)))))
	((eq (car pathstep) :property)
	 (tyo #/|)
	 (princ (cadr pathstep))
	 (and (caddr pathstep)
	      (progn (tyo #/#)
		     (princ (caddr pathstep)))))))

;Alter the property name at the end of the path,
;to be appropriate for the specified string.
;If string is "LISP" we want no property at the end.
;If it is "QFASL" we want a "QFASL" property at the end, etc.
(defvar ignored-types '("LISP" "TEXT"))

(defmethod (lmfile-parsing-mixin :new-pathname)
	   (&rest options &key &allow-other-keys
	    &optional (starting-pathname self)
	    (original-type nil original-type-p)
	    &aux host-p device-p directory-p name-p type-p version-p
	    new-host new-device new-directory new-name new-type canonical-type new-version
	    new-name-really
	    new-directory-really
	    new-type-really
	    new-version-really)
  (loop for (keyword value) on options by 'cddr
	do
	(selectq keyword
	  (:host (unless host-p (setq new-host value host-p t)))
	  (:name (unless name-p (setq new-name value name-p t)))
	  (:raw-name (unless name-p (setq new-name value name-p :raw)))
	  (:directory (unless directory-p (setq new-directory value directory-p t)))
	  (:raw-directory (unless directory-p (setq new-directory value directory-p :raw)))
	  (:device (unless device-p (setq new-device value device-p t)))
	  (:raw-device (unless device-p (setq new-device value device-p :raw)))
	  (:type (unless type-p
		   (if (and (symbolp value) (not (memq value '(nil :unspecific))))
		       (setq canonical-type value type-p :canonical)
		     (setq new-type value type-p t))))
	  (:raw-type (unless type-p (setq new-type value type-p :raw)))
	  (:canonical-type
	   (unless type-p (setq canonical-type value type-p :canonical)))
	  (:version (unless version-p (setq new-version value version-p t)))
;; All keywords that do NOT require special decoding must go here.
	  ((:starting-pathname
	    :original-type :defaults nil)
	   nil)
	  (t (ferror nil "Unknown keyword ~s to MAKE-PATHNAME or :NEW-PATHNAME." keyword))))
  (or host-p (setq new-host (pathname-host starting-pathname)))
  (setq new-host (get-pathname-host new-host))
  ;; Turn a specified canonical type into a string (in standard case).
  (if (eq type-p :canonical)
      (multiple-value-bind (preferred all)
	  (decode-canonical-type canonical-type (send new-host :system-type))
	(setq new-type
	      (let ((alphabetic-case-affects-string-comparison t))
		(unless original-type-p
		  (setq original-type (pathname-type starting-pathname)))
		(if (member original-type all)
		    original-type
		  preferred)))))
  (if (eq (pathname-host starting-pathname) new-host)
      (progn
	(or device-p (setq new-device (pathname-raw-device starting-pathname) device-p :raw))
	(or directory-p (setq new-directory (pathname-raw-directory starting-pathname) directory-p :raw))
	(or name-p (setq new-name (pathname-raw-name starting-pathname) name-p :raw))
	(or type-p (setq new-type (pathname-raw-type starting-pathname) type-p :raw)))
    ;; Hosts don't match; must convert to standard syntax and reparse.
    (or device-p (setq new-device (pathname-device starting-pathname)))
    (or directory-p (setq new-directory (pathname-directory starting-pathname)))
    (or name-p (setq new-name (pathname-name starting-pathname)))
    (or type-p (setq new-type (pathname-type starting-pathname))))
  (or version-p (setq new-version (pathname-raw-version starting-pathname)))
  ;; Now compute the actual new components from what was specified.
  (setq new-device (or new-device :unspecific))
  (and (stringp new-device)
       (string-equal new-device "DSK")
       (setq new-device :unspecific))
  (setq new-directory-really
	(cond ((eq directory-p :raw) new-directory)
	      ((stringp new-directory) (expand-pathstring new-directory))
	      ((eq new-directory :root) '(root))
	      ((memq new-directory '(nil :unspecific :wild))
	       new-directory)
	      ((consp new-directory) new-directory)
	      (t (ferror 'pathname-parse-error
			 "~S is not a valid directory component for ~A."
			 new-directory host))))
  (cond ((eq name-p :raw)
	 (setq new-name-really new-name))
	((eq new-name :wild)
	 (setq new-name-really :wild))
	((stringp new-name)
	 (setf (values nil nil new-name-really new-type-really new-version-really)
	       (funcall-self :parse-namestring nil new-name)))
	(t
	 (setq new-name-really new-name)))
  (setq new-type-really
	(cond ((eq type-p :raw) new-type)
	      ((and (null type-p) new-type-really)
	       new-type-really)
	      ((memq new-type '(nil :unspecific :wild))
	       new-type)
	      ((string-equal new-type '*) :wild)
	      ((mem 'string-equal new-type ignored-types)
	       :unspecific)
	      (t (string new-type))))
  (when (or (stringp new-version) (symbolp new-version))
    (unless (null new-version)
      (setq new-version (intern new-version si:pkg-keyword-package))))
  (setq new-version-really
	(selectq new-version
	  (:> :newest)
	  (:< :oldest)
	  (:* :wild)
	  (:! :installed)
	  (t new-version)))
  (make-pathname-internal new-host
			  new-device new-directory-really new-name-really
			  new-type-really new-version-really))

(defmethod (lmfile-parsing-mixin :parse-truename) (string)
  (let ((pn (parse-pathname string host)))
    (if (null (pathname-type pn))
	(send pn :new-type :unspecific)
      pn)))

(defmethod (lmfile-parsing-mixin :init-file) (program-name)
  (funcall-self :new-pathname
		:name (list "INIT" (string program-name))
		:directory (list (string user-id))))

(defmethod (lmfile-parsing-mixin :source-pathname) ()
  (let ((gp (funcall-self :generic-pathname)))
    (if (typep gp 'lmfile-parsing-mixin)
	(send gp :new-version :newest)
      (send gp :source-pathname))))

(defmethod (lmfile-parsing-mixin :undeletable-p) () t)

(defmethod (lmfile-parsing-mixin :wild-p) ()
  (or (eq directory :wild)
      (eq name :wild)
      (eq type :wild)
      (eq version :wild)
      (and (consp directory)
	   (dolist (dircomp directory)
	     (if (member dircomp '("*" "**")) (return t))))
      (dolist (namecomp (merge-name-type-and-version))
	(if (member namecomp '("*" "**")) (return t)))))

(defmethod (lmfile-parsing-mixin :directory-wild-p) ()
  (or (eq directory :wild)
      (and (consp directory)
	   (dolist (dircomp directory)
	     (if (member dircomp '("*" "**")) (return t))))))

(defmethod (lmfile-parsing-mixin :name-wild-p) ()
  (or (eq name :wild)
      (dolist (namecomp (merge-name-type-and-version))
	(if (member namecomp '("*" "**")) (return t)))))

(defmethod (lmfile-parsing-mixin :equal) (other-pathname)
  (and other-pathname
       (eq (typep self) (typep other-pathname))
       (eq host (pathname-raw-host other-pathname))
       (equalp device (pathname-raw-device other-pathname))
       (equalp directory (pathname-raw-directory other-pathname))
       (equalp name (pathname-raw-name other-pathname))
       (equalp type (pathname-raw-type other-pathname))
       (eq version (pathname-raw-version other-pathname))))

(defmethod (lmfile-parsing-mixin :new-name-type-and-version) (new-pathlist)
  (multiple-value-bind (nam typ vers)
      (decompose-name-type-and-version (break-out-pathlist-spaces new-pathlist))
    (make-pathname-internal host device directory nam typ vers)))

;These are the properties which the user cannot set arbitrarily.
(defconst lmfile-unsettable-properties
  '(:length-in-blocks
    :flavor :directory
    :pack-number :volume-name))

(defmethod (lmfile-parsing-mixin :property-settable-p) (propname)
  (not (memq propname lmfile-unsettable-properties)))

(defmethod (lmfile-parsing-mixin :default-settable-properties) ()
  '(:deleted :dont-delete :dont-supersede :not-backed-up
    :creation-date :byte-size :reference-date :characters
    :author :dont-reap :date-last-expunge))

(comment 
;;; Test arguments for whether they would be valid if used in the
;;; :NEW-PATHNAME operation.

(defmethod (lmfile-parsing-mixin :valid-name-p) (putative-name)
  (or (stringp putative-name)
      (memq putative-name '(nil :wild :unspecific))
      (consp putative-name)))

(defmethod (lmfile-parsing-mixin :valid-directory-p) (putative-directory)
  (or (stringp putative-directory)
      (memq putative-directory '(nil :wild :unspecific :root))
      (consp putative-directory)))

(defmethod (lmfile-parsing-mixin :valid-type-p) (putative-type)
  (or (and (stringp putative-type)
	   (not (mem 'string-equal putative-type ignored-types)))
      (memq putative-type '(nil :wild :unspecific))))

(defmethod (lmfile-parsing-mixin :valid-type) (typ)
  (if (funcall-self :valid-type-p typ)
      typ
    :unspecific))

(defmethod (lmfile-parsing-mixin :valid-version-p) (vrs)
  (or (fixnump vrs)
      (memq vrs '(nil :unspecific :wild :newest :oldest :installed :> :< :! :*))))

);end comment

(comment
(defmethod (lmfile-parsing-mixin :generic-pathname) ()
  (funcall #'(:method pathname :generic-pathname) :generic-pathname
	   (component-upcase device) (component-upcase directory)
	   (component-upcase name) (component-upcase type))))

;;; Must upcase all these to get interchange case.
(defmethod (lmfile-parsing-mixin :name) ()
  (component-upcase name))

(defmethod (lmfile-parsing-mixin :directory) ()
  (component-upcase directory))

(defmethod (lmfile-parsing-mixin :device) ()
  (component-upcase device))

(defmethod (lmfile-parsing-mixin :type) ()
  (component-upcase type))

(defun component-upcase (object)
  (cond ((stringp object) (string-upcase object))
	((consp object) (mapcar 'component-upcase object))
	(t object)))

;Turn pathstrings into pathlists for use as pathname components.

;Parse something that may contain a name, a directory or both.
;start and end specify the range of pathstring to be looked at.
(defmethod (lmfile-parsing-mixin :parse-namestring) (host-specified-flag pathstring
						    &optional start end)
  host-specified-flag
  (let (nam dir (dev :unspecific) typ ver
	(pathstring pathstring))
    (and end (setq pathstring (substring pathstring 0 end)))
    (or start (setq start 0))
    (do (pathlist (end-index (1- start)) next-is-dir)
	(())
      (multiple-value (pathlist end-index) (expand-pathstring pathstring (1+ end-index)))
      (cond ((null end-index)
	     (cond (next-is-dir (setq dir pathlist))
		   (t (setq nam pathlist)))
	     (return nil)))
      (cond ((= (aref pathstring end-index) #/)
	     (setq next-is-dir t)
	     (setq nam pathlist))
	    ((= (aref pathstring end-index) #/:)
	     (setq dev (car pathlist)
		   next-is-dir nil))
	    (t (setq next-is-dir nil)
	       (setq dir pathlist))))
    (and (eq (car nam) 'root)
	 (setq dir :unspecific))
    ;; Now correct for the fact that we have to store the type and version
    ;; in separate places.
    (setf (values nam typ ver) (decompose-name-type-and-version nam))
    (values dev dir nam typ ver)))

;Decompose a pathstring into a pathlist.
;":", ";", "" and "" are not processed; instead, this function returns
;the expansion of the pathstring up to the first "" or "" or ";" or ":".
;and a second value which is the index of that "" or "" or ";" or ":"

(defconst pathstring-special-chars '(#/^ #/~ #/\ #// #/| #/ #/ #/; #/:))

(defun expand-pathstring (pathstring &optional (name-start-index 0))
  (cond ((or (consp pathstring) (null pathstring)) pathstring)
	(t
	 (setq pathstring (string pathstring))
	 (do (pathlist
	       previous-step
	       (len (string-length pathstring))
	       nextname nextversion propflag
	       after-root-or-supernode
	       name-end-index last-nonspace)
	     (( name-start-index len)
	      pathlist)
	   (setq nextname nil nextversion nil)
	   (cond ((= (aref pathstring name-start-index) #/^)
		  (setq previous-step 'supernode)
		  (setq pathlist (nconc pathlist (list previous-step)))
		  (setq after-root-or-supernode "^")
		  (setq name-start-index (1+ name-start-index)))
		 ((= (aref pathstring name-start-index) #/~)
		  (setq previous-step 'root)
		  (setq pathlist (nconc pathlist (list previous-step)))
		  (setq after-root-or-supernode "~")
		  (setq name-start-index (1+ name-start-index)))
		 ((and (memq (aref pathstring name-start-index) '(#// #/\))
		       after-root-or-supernode)
		  (setq name-start-index (1+ name-start-index))
		  (setq after-root-or-supernode nil))
		 ((and (= (aref pathstring name-start-index) #/|)
		       after-root-or-supernode)
		  (setq after-root-or-supernode nil))
		 ((= (aref pathstring name-start-index) #/ )
		  (setq name-start-index (1+ name-start-index)))
		 ((memq (aref pathstring name-start-index) '(#/ #/ #/; #/:))
		  (return pathlist name-start-index))
		 (t
		   (and after-root-or-supernode
			(ferror 'pathname-parse-error
				"garbage following ~A in pathstring"
				after-root-or-supernode))
		   ;; Read a name of subnode or property.
		   (setq propflag nil)
		   (cond ((= (aref pathstring name-start-index) #/|)
			  (setq name-start-index (1+ name-start-index))
			  (setq propflag t)))
		   (setq last-nonspace (1- name-start-index))
		   ;; Find end of name.  Skip over quoted characters.
		   (do ((i name-start-index (1+ i)))
		       (( i len)
			(setq name-end-index len))
		     (let ((ch (aref pathstring i)))
		       (cond ((= ch #/)
			      (setq i (1+ i))
			      (setq last-nonspace i)
			      (cond ((= i len)
				     (pathname-error (1- i) pathstring
					     "Pathstring ends with quote character ~C"
					     #/))))
			     ((memq ch pathstring-special-chars)
			      (return (setq name-end-index i)))
			     ((= ch #/ ))
			     (t (setq last-nonspace i)))))
		   ;; Extract the name.
		   (setq nextname
			 (string-left-trim " "
					   (substring pathstring
						      name-start-index (1+ last-nonspace))))
		   (setq name-start-index name-end-index)
		   (setq nextname (parse-name-and-version nextname
							  (cond (propflag :property)
								(t :version))))
		   ;; Don't keep a list starting with :version
		   ;; if there isn't really a version number.
		   (and (not propflag) (null (caddr nextname))
			(setq nextname (cadr nextname)))
		   ;; Skip over any "/" or "\" separating it from the following name.
		   (and (< name-start-index len)
			(or (= (aref pathstring name-start-index) #//)
			    (= (aref pathstring name-start-index) #/\))
			(setq name-start-index (1+ name-start-index)))
		   ;; Add the new step onto the pathlist.
		   (if (and propflag
			    (not (symbolp previous-step))
			    (not (and (consp previous-step)
				      (eq (car previous-step) :property))))
		       (rplaca (last pathlist)
			       (setq previous-step
				     `(:subnode-property ,(car (last pathlist))
							 . ,(cdr nextname))))
		       (setq pathlist
			     (nconc pathlist (list (setq previous-step nextname)))))))))))

;Turn a string pathstep into a list pathstep by parsing it into a name and a version.
;Make a list whose cadr is the name, caddr is the version,
;and whose car is the specified symbol list-car.
;NOTE: this is not necessarily right for any particular flavor
;of directory.  It happens to be right for ORDINARY-DIR-NODE.
;It also is right for property pathsteps.
(defun parse-name-and-version (pathstep list-car)
  (let (name version (len (string-length pathstep))
        (last-nonspace -1) name-end-index)
    ;; Find the version-number delimiter "#" if there is one.
    (do ((i 0 (1+ i)))
	(( i len)
	 (setq name-end-index len))
      (let ((ch (aref pathstep i)))
	(cond ((= ch #/)
	       (setq i (1+ i))
	       (setq last-nonspace i))
	      ((= ch #/#)
	       (return (setq name-end-index i)))
	      ((= ch #/ ))
	      (t (setq last-nonspace i)))))
    ;; Extract the name, proper.
    (setq name (substring pathstep 0 (1+ last-nonspace)))
    ;; If there is a version number, extract it.
    (cond ((< name-end-index len)
	   (setq version
		 (let ((base 10.) (ibase 10.) (*nopoint t) (package si:pkg-keyword-package))
		   (read-from-string
		     (substring pathstep (1+ name-end-index) len))))))
    (if (eq version :nil) (setq version nil))
    (list list-car name version)))

;Remove all the quoting characters from a string.
(defun remove-quote-chars (name)
  (let ((name (string-append name)))
    ;; Flush any quote characters by copying contents of name downward.
    (do ((from 0 (1+ from))
	 (to 0 (1+ to))
	 (len (string-length name)))
	((= from len)
	 (adjust-array-size name to))
      (let ((ch (aref name from)))
	(and (= ch #/)
	     (setq ch (aref name (setq from (1+ from)))))
	(setf (aref name to) ch)))
    name))

(defun princ-with-quoting (string &optional additional-special-chars dont-quote-characters)
  (dotimes (i (string-length string))
    (cond ((memq (aref string i) dont-quote-characters))
	  ((or (memq (aref string i) pathstring-special-chars)
	       (memq (aref string i) additional-special-chars)
	       (and (= (aref string i) #\space)
		    (or (zerop i) (= i (1- (string-length string)))))
	       (= (aref string i) #/#)
	       (= (aref string i) #/))
	   (tyo #/)))
    (tyo (aref string i))))

;;; Here's THE flavor of pathname for us.

(DEFFLAVOR LMFILE-PATHNAME () (FS:LMFILE-PARSING-MIXIN HOST-PATHNAME))

(COMPILE-FLAVOR-METHODS LMFILE-PATHNAME)

;; These must be defined for remote users as well.

(defprop ptl property-list-too-long file-error)
(defprop property-list-too-long ptl file-error)
(defsignal property-list-too-long change-property-failure (pathname property)
  "Property list total size exceeds what can be represented on disk.")

(defprop rus rename-underneath-self file-error)
(defprop rename-underneath-self rus file-error)
(defsignal rename-underneath-self rename-failure
	   (pathname new-pathname)
  "Renaming a node to be its own subnode.")
