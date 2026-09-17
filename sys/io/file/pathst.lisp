; -*- Mode:LISP; Package:FILE-SYSTEM; Base:8; Readtable:ZL -*-
;;;; host-pathname-type-specific pathname support

; logical pathnames moved to IO; FILE; LOGICAL

;;;; Support that stays: generic pathname-string helpers
;; ITS support (ITS-PATHNAME-MIXIN, ITS-DEVICE-STRING,
;; ITS-FN2-STRING, SIX-SIXBIT-CHARACTERS) removed; this system never talks to an
;; ITS host. ITS-FN1-STRING, STRING-OR-WILD, QUOTE-COMPONENT-STRING,
;; NUMERIC-P and *ITS-UNINTERESTING-TYPES* stay: despite their names, they
;; are generic and have callers outside the old ITS support, chiefly
;; IO; FILE; LOGICAL's LOGICAL-NAME-STRING (which is literally
;; ITS-FN1-STRING) and ZWEI's FILE-LOADED-TRUENAME (ZWEI; ZMACS), which
;; reads *ITS-UNINTERESTING-TYPES* to compare file types.

(DEFVAR *ITS-UNINTERESTING-TYPES* '("LISP" "TEXT" NIL :UNSPECIFIC))

(DEFUN ITS-FN1-STRING (&OPTIONAL NO-QUOTE-P NO-PLACEHOLDER)
  (DECLARE (:SELF-FLAVOR PATHNAME))
  (COND	((NULL NAME)
	 (IF NO-PLACEHOLDER
	     NIL ""))
	((EQ NAME ':UNSPECIFIC) NIL)		;Should this ever happen?
	((CONSP NAME) (IF NO-QUOTE-P (CAR NAME)
			  (QUOTE-COMPONENT-STRING (CAR NAME))))
	(T (STRING-OR-WILD NAME NO-QUOTE-P))))

(DEFUN STRING-OR-WILD (FIELD &OPTIONAL NO-QUOTE-P SPECIALS REPLACED-BY)
  "Convert FIELD, a pathname component, to a string to appear in a printed representation.
NO-QUOTE-P inhibits insertion of quoting characters;
otherwise, quote characters are inserted and some characters translated:
SPECIALS is a list of characters to be translated,
and REPLACED-BY is an equally-long list of characters to translate them to."
  (COND ((EQ FIELD ':WILD) "*")
	((MEMQ FIELD '(NIL :UNSPECIFIC)) NIL)
	(NO-QUOTE-P (STRING FIELD))
	((QUOTE-COMPONENT-STRING FIELD SPECIALS REPLACED-BY))))

(DEFUN QUOTE-COMPONENT-STRING (STRING &OPTIONAL SPECIALS REPLACED-BY &AUX LENGTH)
  "Put a quote character before each character of STRING that needs one.
Copies STRING if it has to be changed.  Any instance of a char in SPECIALS
is replaced by the corresponding char in REPLACED-BY, not quoted."
  (SETQ STRING (STRING STRING)
	LENGTH (STRING-LENGTH STRING))
  (DO ((NSTRING NIL)
       (QUOTE-IDX 0 NQUOTE-IDX)
       (NQUOTE-IDX -1))
      (NIL)
    (SETQ NQUOTE-IDX
	  (DO ((I (1+ NQUOTE-IDX) (1+ I)))
	      (( I LENGTH))
	    (AND (NOT (MEMQ (AREF STRING I) SPECIALS))
		 (SEND SELF :CHARACTER-NEEDS-QUOTING-P (AREF STRING I))
		 (RETURN I))))
    (AND (OR NQUOTE-IDX NSTRING)
	 (SETQ NSTRING (IF NSTRING
			   (STRING-APPEND NSTRING
					  (SEND SELF :QUOTE-CHARACTER)
					  (SUBSTRING STRING QUOTE-IDX NQUOTE-IDX))
			   (SUBSTRING STRING QUOTE-IDX NQUOTE-IDX))))
    (OR NQUOTE-IDX
	(PROGN
	  (DO-FOREVER
	    (LET ((I (STRING-SEARCH-SET SPECIALS (OR NSTRING STRING))))
	      (OR I (RETURN))
	      (OR NSTRING
		  (SETQ NSTRING (STRING-APPEND STRING)))
	      (SETF (AREF NSTRING I)
		    (NTH (FIND-POSITION-IN-LIST (AREF NSTRING I) SPECIALS) REPLACED-BY))))
	  (RETURN (OR NSTRING STRING))))))

(DEFUN NUMERIC-P (STRING &OPTIONAL PARTIAL-OK SIGN-OK)
  "If STRING is a printed representation of a number, return the number, else NIL.
PARTIAL-OK non-NIL says, if the number is not the whole of STRING,
 still return the number that there is (normally, NIL is returned)
 with a second value which is the index of the character after the number.
SIGN-OK non-NIL says a sign at the front is allowed."
  (AND (STRINGP STRING)
       (DO ((I 0 (1+ I))
	    (LEN (STRING-LENGTH STRING))
	    (NUM NIL)
	    (SIGN 1)
	    (CH))
	   (( I LEN)
	    (AND NUM (* NUM SIGN)))
	 (SETQ CH (CHAR STRING I))
	 (COND ((AND SIGN-OK
		     (ZEROP I)
		     (MEMQ CH '(#/+ #/-)))
		(IF (EQ CH #/+)
		    (SETQ SIGN 1)
		    (SETQ SIGN -1)))
	       ((LET ((TEM (DIGIT-CHAR-P CH)))
		  (AND TEM (SETQ NUM (+ TEM (IF NUM (* NUM 10.) 0))))))
	       (PARTIAL-OK
		(RETURN (AND NUM (* NUM SIGN)) I))
	       (T (RETURN NIL))))))

  
;; TENEX-family pathname support (TENEX-FAMILY-PATHNAME-MIXIN, the
;; shared base of TOPS-20, TENEX and VMS pathnames) and TOPS-20 support
;; (TOPS20-PATHNAME-MIXIN) removed; this system never talks to a TOPS-20 host.
;; DEFAULT-DIRECTORY-PATHNAME-AS-FILE, below, is generic and stays: it is
;; UNIX-PATHNAME-MIXIN's :DIRECTORY-PATHNAME-AS-FILE method too.

(DEFUN DEFAULT-DIRECTORY-PATHNAME-AS-FILE (IGNORE &AUX DIR NAM)
  (DECLARE (:SELF-FLAVOR PATHNAME))
  (COND ((EQ DIRECTORY :ROOT)
	 (FERROR 'PATHNAME-PARSE-ERROR "There is no pathname for the root as a file"))
	((OR (ATOM DIRECTORY) (NULL (CDR DIRECTORY)))
	 (SETQ DIR :ROOT
	       NAM (IF (CONSP DIRECTORY) (CAR DIRECTORY) DIRECTORY)))
	(T
	 (LET ((LAST (LAST DIRECTORY)))
	   (SETQ DIR (LDIFF DIRECTORY LAST)
		 NAM (CAR LAST)))))
  (SEND SELF :NEW-PATHNAME :RAW-DIRECTORY DIR
			   :RAW-NAME NAM
			   :TYPE (SEND SELF :DIRECTORY-FILE-TYPE)))

;; Tenex support (TENEX-PATHNAME-MIXIN) removed; this system never talks to
;; a Tenex host.

;; VMS support (VMS-PATHNAME-MIXIN) removed; this system never talks to a VMS
;; file server.

;;;; Unix support
;; Multics support (MULTICS-PATHNAME-MIXIN) removed; this system never talks to
;; a Multics file server.

(DEFFLAVOR UNIX-PATHNAME-MIXIN () (HIERARCHICAL-DIRECTORY-MIXIN MEANINGFUL-ROOT-MIXIN
				   PATHNAME-NORMALLY-LOWERCASE-MIXIN)
  (:REQUIRED-FLAVORS PATHNAME))

(DEFMETHOD (UNIX-PATHNAME-MIXIN :CHARACTER-NEEDS-QUOTING-P) (IGNORE)
  ())

(DEFMETHOD (UNIX-PATHNAME-MIXIN :UNSPECIFIC-TYPE-IS-DEFAULT) ()
  T)

(DEFMETHOD (UNIX-PATHNAME-MIXIN :DIRECTORY-PATHNAME-AS-FILE)
	   DEFAULT-DIRECTORY-PATHNAME-AS-FILE)

(DEFMETHOD (UNIX-PATHNAME-MIXIN :DIRECTORY-FILE-TYPE) ()
  ':UNSPECIFIC)

(DEFMETHOD (UNIX-PATHNAME-MIXIN :DIRECTORY-DELIMITER-CHARACTER) ()
  #//)

(DEFMETHOD (UNIX-PATHNAME-MIXIN :DIRECTORY-UP-DELIMITER) ()
  "..")

(DEFUN UNIX-FILENAME (NAME TYPE &AUX (NEW-TYPE (IF TYPE TYPE "'")))
  (IF (EQ NAME ':UNSPECIFIC) (SETQ NAME ""))
  (IF (EQ NAME ':WILD)
      (IF (MEMQ TYPE '(:WILD :UNSPECIFIC))
	  "*"	;Both wild, just *
	  (STRING-APPEND "*." NEW-TYPE))
    (IF (AND (NULL NAME) (MEMQ TYPE '(NIL :UNSPECIFIC)))
	""
      (OR NAME (SETQ NAME "'"))
      (COND ((EQ TYPE ':WILD)
	     (FORMAT NIL "~A.*" NAME))
	    ((EQ TYPE ':UNSPECIFIC)
	     NAME)
	    (T
	     (STRING-APPEND NAME "." NEW-TYPE))))))

(DEFMETHOD (UNIX-PATHNAME-MIXIN :STRING-FOR-HOST) ()
  (FORMAT NIL "~@[~A~]~A" (UNIX-DIRECTORY-STRING) (UNIX-FILENAME NAME TYPE)))

(DEFMETHOD (UNIX-PATHNAME-MIXIN :STRING-FOR-EDITOR) ()
  (FORMAT NIL "~A ~A ~A:"
	  (UNIX-FILENAME NAME TYPE) (UNIX-DIRECTORY-STRING)
	  (SEND HOST :NAME-AS-FILE-COMPUTER)))

(DEFMETHOD (UNIX-PATHNAME-MIXIN :STRING-FOR-DIRED) ()
  (UNIX-FILENAME NAME TYPE))

;;; the :STRING-FOR-DIRECTORY method was missing, so a Unix pathname
;;; could not print its own directory.
(DEFMETHOD (UNIX-PATHNAME-MIXIN :STRING-FOR-DIRECTORY) ()
  (UNIX-DIRECTORY-STRING))

(DEFUN UNIX-DIRECTORY-STRING ()
  (DECLARE (:SELF-FLAVOR UNIX-PATHNAME-MIXIN))
  (IF (MEMQ DIRECTORY '(NIL :UNSPECIFIC)) NIL
      (LET ((DIRECT DIRECTORY)
	    (SUPPRESS-DELIM NIL))
	(STRING-APPEND (COND ((EQ DIRECT :ROOT) "")
			     ((AND (EQ (CAR-SAFE DIRECT) :RELATIVE))
			      (POP DIRECT)
			      "")
			     (T
			      (SEND SELF :DIRECTORY-DELIMITER-CHARACTER)))
		       (COND ((EQ DIRECT ':ROOT) "")
			     ((ATOM DIRECT) (UNIX-DIRECTORY-COMPONENT DIRECT))
			     ((NULL (CDR DIRECT))
			      (LET (STRING)
				(MULTIPLE-VALUE (STRING SUPPRESS-DELIM)
				  (UNIX-DIRECTORY-COMPONENT (CAR DIRECT)))
				STRING))
			     (T (LOOP FOR SUBDIR IN DIRECT
				      WITH STRING = (MAKE-STRING #o20 :FILL-POINTER 0)
				      AS DELIM-P = NIL THEN T
				      DO (AND DELIM-P (NOT SUPPRESS-DELIM)
					      (ARRAY-PUSH-EXTEND
						STRING
						(SEND SELF
						  :DIRECTORY-DELIMITER-CHARACTER)))
					 (LET (SUBSTR)
					   (MULTIPLE-VALUE (SUBSTR SUPPRESS-DELIM)
					     (UNIX-DIRECTORY-COMPONENT SUBDIR))
					   (SETQ STRING (STRING-NCONC STRING SUBSTR)))
				      FINALLY (RETURN STRING))))
		     (COND (SUPPRESS-DELIM "")
			   (T (SEND SELF :DIRECTORY-DELIMITER-CHARACTER)))))))

(DEFUN UNIX-DIRECTORY-COMPONENT (STRING)
  (CASE STRING
    (:WILD "*")
    (:UP (LET ((DELIM (SEND SELF :DIRECTORY-UP-DELIMITER)))
	   (IF (STRINGP DELIM) DELIM (VALUES (STRING DELIM) T))))
    (OTHERWISE (STRING STRING))))

(DEFMETHOD (UNIX-PATHNAME-MIXIN :PARSE-NAMESTRING) (IGNORE NAMESTRING
						      &OPTIONAL (START 0) END
						      &AUX DIR NAM TYP (VER :UNSPECIFIC)
						      DELIM-CHAR DIRSTART DIREND)
  (OR END (SETQ END (STRING-LENGTH NAMESTRING)))
  (SETQ START (OR (STRING-SEARCH-NOT-CHAR #/SP NAMESTRING START END) END))
  (SETQ END (1+ (OR (STRING-REVERSE-SEARCH-NOT-CHAR #/SPACE NAMESTRING END START)
		    (1- START))))
  (SETQ DELIM-CHAR (SEND SELF :DIRECTORY-DELIMITER-CHARACTER))
  (LET (I)
    (IF (AND (SETQ I (STRING-SEARCH-CHAR #/SPACE NAMESTRING START END))
	     (CHAR-EQUAL DELIM-CHAR (CHAR NAMESTRING (1- END)))
	     (NOT (STRING-SEARCH-CHAR DELIM-CHAR NAMESTRING START I)))
	(SETQ DIRSTART (STRING-SEARCH-NOT-CHAR #/SPACE NAMESTRING I END)
	      DIREND END
	      END I)
      (SETQ DIRSTART START
	    DIREND (STRING-REVERSE-SEARCH-CHAR DELIM-CHAR NAMESTRING END START)
	    START (IF DIREND (1+ DIREND) START))))
  ;; Now START..END are the indices around the name and type,
  ;; and DIRSTART..DIREND are the indices around the directory.
  (WHEN DIREND
    (SETQ DIR (LET ((RELATIVE-P T)
		    (DIRIDX DIRSTART)
		    (UP (SEND SELF :DIRECTORY-UP-DELIMITER))
		    (NUP NIL)
		    (STRS NIL))
		(COND ((= (AREF NAMESTRING DIRIDX) DELIM-CHAR)
		       (SETQ RELATIVE-P NIL)
		       (SETQ DIRIDX (STRING-SEARCH-NOT-CHAR
				      DELIM-CHAR NAMESTRING DIRIDX))))
		(AND DIRIDX (> DIREND DIRIDX)
		     (SETQ STRS (LOOP FOR IDX = DIRIDX THEN JDX
				      AS JDX = (STRING-SEARCH-CHAR
						 DELIM-CHAR NAMESTRING IDX DIREND)
				      COLLECT (SUBSTRING NAMESTRING IDX (OR JDX DIREND))
				      WHILE
				      (AND JDX
					   (SETQ JDX
						 (STRING-SEARCH-NOT-CHAR
						   DELIM-CHAR NAMESTRING JDX DIREND))))))
		(AND (STRINGP UP)
		     (DO L STRS (CDR L) (NULL L)
			 (AND (STRING-EQUAL (CAR L) UP)
			      (SETF (CAR L) ':UP))))
		(AND NUP (SETQ STRS (NCONC NUP STRS)))
		(COND (RELATIVE-P (CONS ':RELATIVE STRS))
		      ((NULL STRS) ':ROOT)
		      ((NULL (CDR STRS)) (CAR STRS))
		      (T STRS)))))
  (SETQ TYP (STRING-REVERSE-SEARCH-CHAR #/. NAMESTRING END START))
  (IF (EQ TYP START) (SETQ TYP NIL))		;Initial . is part of NAM
  (IF TYP (PSETQ END TYP
		 TYP (SUBSTRING NAMESTRING (1+ TYP) END)))
  (SETQ NAM (AND ( START END) (SUBSTRING NAMESTRING START END)))
  (COND ((EQUAL NAM "'") (SETQ NAM NIL))
	((EQUAL NAM "*") (SETQ NAM ':WILD)))
  (COND ((NULL TYP) (SETQ TYP (AND NAM ':UNSPECIFIC)))
	((EQUAL TYP "'") (SETQ TYP NIL))
	((EQUAL TYP "*") (SETQ TYP ':WILD VER ':WILD)))
  ;; VER is :UNSPECIFIC unless TYP is :WILD, in which case VER is also :WILD.
  (VALUES :UNSPECIFIC DIR NAM TYP VER))

;; Differs from the default method in that if the type is :WILD
;; we clobber the version to :WILD; otherwise we clobber the version to :UNSPECIFIC.
(DEFMETHOD (UNIX-PATHNAME-MIXIN :NEW-PATHNAME)
	   (&REST OPTIONS
	    &KEY (STARTING-PATHNAME SELF)
		 ((:TYPE -TYPE-) (PATHNAME-TYPE STARTING-PATHNAME))
	    &ALLOW-OTHER-KEYS)
  (APPLY #'MAKE-PATHNAME-1
	 :VERSION (IF (EQ -TYPE- ':WILD) ':WILD ':UNSPECIFIC)
	 :STARTING-PATHNAME STARTING-PATHNAME
	 :PARSING-PATHNAME SELF
	 OPTIONS))

(DEFMETHOD (UNIX-PATHNAME-MIXIN :PARSE-DIRECTORY-SPEC) (SPEC)
  (COND ((STRINGP SPEC) (LIST (SEND SELF :PARSE-COMPONENT-SPEC SPEC)))
	((AND (CONSP SPEC)
	      (LOOP FOR ELT IN SPEC
		    ALWAYS (OR (MEMQ ELT '(:UP :WILD :RELATIVE))
			       (STRINGP ELT)))
	      (NOT (MEMQ :RELATIVE (CDR SPEC))))
	 (LOOP FOR ELT IN SPEC
	       COLLECT (IF (SYMBOLP ELT) ELT
			 (SEND SELF :PARSE-COMPONENT-SPEC ELT))))
	((MEMQ SPEC '(NIL :UNSPECIFIC :WILD)) SPEC)
	(T (PATHNAME-DIRECTORY (QUIET-USER-HOMEDIR HOST)))))

(DEFFLAVOR LMFS-PATHNAME-MIXIN () (UNIX-PATHNAME-MIXIN))

(DEFMETHOD (LMFS-PATHNAME-MIXIN :DIRECTORY-DELIMITER-CHARACTER) ()
  #/>)

(DEFMETHOD (LMFS-PATHNAME-MIXIN :DIRECTORY-UP-DELIMITER) ()
  #/<)

(DEFMETHOD (LMFS-PATHNAME-MIXIN :CONVERT-TYPE-FOR-HOST) (-TYPE-)
  (STRING-OR-WILD -TYPE-))

;;  (undefmethod (lmfs-pathname-mixin :directory))

;;; logical pathnames moved to io;file;logical

;;;; Kludges for bootstrapping from a world without flavors loaded.
(DEFUN CANONICALIZE-COLD-LOAD-PATHNAMES (&AUX SYS-PATHNAME PHYS-PATHNAME)
  (DECLARE (SPECIAL SYS-PATHNAME PHYS-PATHNAME))
  ;; Get someone who can do the translations
  (SETQ SYS-PATHNAME (SAMPLE-PATHNAME "SYS")
	PHYS-PATHNAME (SEND SYS-PATHNAME :TRANSLATED-PATHNAME))
  ;; Make pathnames for all files initially loaded, and setup their properties
  (DOLIST (ELEM SI::*COLD-LOADED-FILE-PROPERTY-LISTS*)
    (LET* ((RECORDED-PATHNAME (MERGE-PATHNAMES (CAR ELEM) PHYS-PATHNAME))
	   (PATHNAME (OR (SEND SYS-PATHNAME :BACK-TRANSLATED-PATHNAME RECORDED-PATHNAME)
			 RECORDED-PATHNAME))
	   (GENERIC-PATHNAME (SEND PATHNAME :GENERIC-PATHNAME)))
      (DO ((L (CDR ELEM) (CDDR L)))
	  ((NULL L))
	(LET ((PROP (INTERN (CAR L) SI:PKG-KEYWORD-PACKAGE))
	      (VAL (CADR L)))
	  ;;Cold load generator does not know how to put in instances, it makes
	  ;;strings instead.  Also, during MINI loading, calls to MAKE-PATHNAME-INTERNAL
	  ;;are saved just as lists.  Note: we do not back translate this pathname, so
	  ;;that we really remember the machine it was compiled on.
	  (COND ((EQ PROP :QFASL-SOURCE-FILE-UNIQUE-ID)
		 (COND ((STRINGP VAL)
			(SETQ VAL (PARSE-PATHNAME VAL)))
		       ((CONSP VAL)
			;; Don't bomb out if host isn't defined.
			(SETF (CAR VAL)
			      (OR (GET-PATHNAME-HOST (CAR VAL) T)
				  (SEND SYS-PATHNAME :PHYSICAL-HOST)))
			;; Symbols like UNSPECIFIC may be in the wrong package
			(DO ((L (CDR VAL) (CDR L)))
			    ((NULL L))
			    (AND (SYMBOLP (CAR L))
				 (SETF (CAR L) (INTERN (SYMBOL-NAME (CAR L)) ""))))
			(SETQ VAL (APPLY #'MAKE-PATHNAME-INTERNAL VAL)))))
		((EQ PROP :FILE-ID-PACKAGE-ALIST)
		 ;; Kludge, built before there are packages
		 (SETF (CAAR VAL) (PKG-FIND-PACKAGE
				    (OR (CAAR VAL)
					SI::PKG-SYSTEM-INTERNALS-PACKAGE)))
		 ;; And before there are truenames
		 (LET ((INFO (CADAR VAL)))
		   (AND (STRINGP (CAR INFO))
			(SETF (CAR INFO) (MERGE-PATHNAMES (CAR INFO) PHYS-PATHNAME)))))
		((EQ PROP :DEFINITIONS)
		 (COND ((OR (NULL VAL)
			    (SYMBOLP (CAR VAL)))
			;; The cold load maker doesn't put anything in saying what package,
			;; so just cons on SI.
			(SETQ VAL (LIST (CONS SI::PKG-SYSTEM-INTERNALS-PACKAGE (CADR L)))))
		       (T
			;; Kludge, built before there are packages
			(SETF (CAAR VAL)
			      (PKG-FIND-PACKAGE (OR (CAAR VAL)
						    SI::PKG-SYSTEM-INTERNALS-PACKAGE)))))))
	  (SEND GENERIC-PATHNAME :SET :GET PROP VAL)))))
  ;; Replace all strings saved on symbols with pathnames
  (LET (PATHNAME-MAP-ALIST)
    (DECLARE (SPECIAL PATHNAME-MAP-ALIST))
    (DOLIST (PKG *ALL-PACKAGES*)
      (MAPATOMS #'(LAMBDA (SYMBOL &AUX NAME)
		    (AND (SETQ NAME (GET SYMBOL ':SOURCE-FILE-NAME))
			 (NOT (TYPEP NAME 'PATHNAME))
			 (SETF (GET SYMBOL ':SOURCE-FILE-NAME)
			       (CANONICALIZE-SOURCE-FILE-NAME-PROPERTY NAME)))
		    (AND (SETQ NAME (GET SYMBOL 'SPECIAL))
			 (STRINGP NAME)
			 (SETF (GET SYMBOL 'SPECIAL)
			       (CANONICALIZE-SOURCE-FILE-NAME-PROPERTY-1 NAME)))
		    (AND (GET SYMBOL 'SI::INITIALIZATION-LIST)
			 (DOLIST (INIT (SYMEVAL SYMBOL))
			   (AND (SI::INIT-SOURCE-FILE INIT)
				(SETF (SI::INIT-SOURCE-FILE INIT)
				      (CANONICALIZE-SOURCE-FILE-NAME-PROPERTY-1
					(SI::INIT-SOURCE-FILE INIT)))))))
		PKG NIL))
    ;; Store source file names from the cold load
    (SETQ SI::FUNCTION-SPEC-HASH-TABLE (MAKE-EQUAL-HASH-TABLE))
    (DOLIST (ELEM SI::COLD-LOAD-FUNCTION-PROPERTY-LISTS)
      (SI:FUNCTION-SPEC-PUTPROP (FIRST ELEM)
				(IF (EQ (SECOND ELEM) ':SOURCE-FILE-NAME)
				    (CANONICALIZE-SOURCE-FILE-NAME-PROPERTY (THIRD ELEM))
				    (THIRD ELEM))
				(SECOND ELEM)))
    (DOLIST (FLAVOR SI::*ALL-FLAVOR-NAMES*)
      (LET ((FL (GET FLAVOR 'SI:FLAVOR)))
	(LET ((LOC (SI::FLAVOR-GET-LOCATION FL 'COMPILE-FLAVOR-METHODS)))
	  (AND LOC (STRINGP (CONTENTS LOC))
	       (SETF (CONTENTS LOC)
		     (CANONICALIZE-SOURCE-FILE-NAME-PROPERTY-1 (CONTENTS LOC))))))))
  )

(DEFUN PATHNAME-FROM-COLD-LOAD-PATHLIST (PATHLIST)
  ;; Don't bomb out if host isn't defined.
  (SETF (CAR PATHLIST)
	(OR (GET-PATHNAME-HOST (CAR PATHLIST) T)
	    (SEND (SAMPLE-PATHNAME "SYS") :PHYSICAL-HOST)))
  ;; Symbols like UNSPECIFIC may be in the wrong package
  (DO ((L (CDR PATHLIST) (CDR L))) ((NULL L))
    (AND (SYMBOLP (CAR L))
	 (SETF (CAR L) (INTERN (GET-PNAME (CAR L)) ""))))
  (APPLY #'MAKE-PATHNAME-INTERNAL PATHLIST))


(DEFUN CANONICALIZE-SOURCE-FILE-NAME-PROPERTY (PROPERTY)
  (IF (ATOM PROPERTY)
      (CANONICALIZE-SOURCE-FILE-NAME-PROPERTY-1 PROPERTY)
      (DOLIST (TYPE PROPERTY)
	(DO ((L (CDR TYPE) (CDR L))) ((NULL L))
	  (SETF (CAR L) (CANONICALIZE-SOURCE-FILE-NAME-PROPERTY-1 (CAR L)))))
      PROPERTY))

(DEFUN CANONICALIZE-SOURCE-FILE-NAME-PROPERTY-1 (NAME)
  (DECLARE (SPECIAL SYS-PATHNAME PHYS-PATHNAME PATHNAME-MAP-ALIST))
  (LET ((TEM (ASSOC NAME PATHNAME-MAP-ALIST)))
    (IF TEM (CDR TEM)
      (LET ((RECORDED-PATHNAME (MERGE-PATHNAMES NAME PHYS-PATHNAME)))
	(SETQ TEM
	      (SEND (OR (SEND SYS-PATHNAME :BACK-TRANSLATED-PATHNAME
			      RECORDED-PATHNAME)
			RECORDED-PATHNAME)
		    :GENERIC-PATHNAME))
	(PUSH (CONS NAME TEM) PATHNAME-MAP-ALIST)
	TEM))))

;;; Called when the time parser comes in, canonicalize times made before then
(DEFUN CANONICALIZE-COLD-LOADED-TIMES ()
  (MAPHASH #'(LAMBDA (IGNORE VAL &AUX ALIST)
	       (AND (SETQ ALIST (GETF (PATHNAME-PROPERTY-LIST VAL) :FILE-ID-PACKAGE-ALIST))
		    (DOLIST (ID ALIST)
		      (LET ((INFO (CADR ID)))
			(AND (STRINGP (CDR INFO))
			     (SETF (CDR INFO)
				   (PARSE-DIRECTORY-DATE-PROPERTY (CDR INFO) 0)))))))
	   *PATHNAME-HASH-TABLE*))


;;;; Initializations

;;; Here are the pathnames that we support

;; ITS-PATHNAME went with ITS support; TOPS20-PATHNAME and
;; TENEX-PATHNAME went with TOPS-20 and Tenex support.
(DEFFLAVOR UNIX-PATHNAME () (FS:UNIX-PATHNAME-MIXIN HOST-PATHNAME))

(DEFFLAVOR LMFS-PATHNAME () (FS:LMFS-PATHNAME-MIXIN HOST-PATHNAME))
(DEFPROP :LMFS LMFS-PATHNAME LISPM-PATHNAME-FLAVOR)

(COMPILE-FLAVOR-METHODS UNIX-PATHNAME
			LMFS-PATHNAME)


#|
;;; Partially special-case hack for converting all the :file-id-package-alist pathnames
;;; when the system directories are moved.

(defvar fix-loaded-pathnames-old-translations)

(defvar fix-loaded-pathnames-host)

(defun fix-loaded-pathnames (fix-loaded-pathnames-host old-translation-alist)
  (setq fix-loaded-pathnames-host (get-pathname-host fix-loaded-pathnames-host))
  (setq fix-loaded-pathnames-old-translations
	(mapcar #'(lambda (transl) (cons (car transl)
					 (substring (cadr transl) 1
						    (1- (string-length (cadr transl))))))
		old-translation-alist))
  (maphash 'fix-loaded-pathnames-1 *pathname-hash-table*))

(defun fix-loaded-pathnames-1 (ignore pathname)
  (let ((prop (send pathname :get :file-id-package-alist)))
    (dolist (elt prop)
      (if (eq (send (caadr elt) :host) fix-loaded-pathnames-host)
	  (let ((new-dir (rassoc (send (caadr elt) :directory)
				 fix-loaded-pathnames-old-translations)))
	    (if new-dir
		(setf (caadr elt)
		      (send (caadr elt) :new-pathname
			    :device "OZ"
			    :directory
			    (list "L" (car new-dir))))))))))

|#
