;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:8; Readtable:T -*-

;;; More winning Lisp Machine software patch facility.   DLW & BEE 10/24/80
;;; The functions in this file manage the patch files

;;; There are 3 kinds of files for each system. There is a patch description file.
;;; This file contains a version of the patch-system structure. This gives the
;;; format of the patch, and also contains the major version counter for the system
;;; In addition, it contains the format strings to generate the file names for the other
;;; files. The other files are: System directories which contain the list of patches
;;; and their descriptions for a given major version, and the patch files, which contain
;;; the actual patches

;;; Format of main patch directory
(DEFSTRUCT (PATCH-MAJOR :LIST (:CONC-NAME PATCH-) (:ALTERANT NIL))
  NAME				;system to be patched
  VERSION			;most recent version of the system
  )

;; note that the version-list of patch-systems is most recent first,
;; whereas patch-dirs are oldest first!!

;;; Internal format of each patch system
(DEFSTRUCT (PATCH-SYSTEM :LIST (:CONC-NAME PATCH-) (:INCLUDE PATCH-MAJOR) (:ALTERANT NIL))
  (STATUS NIL :DOCUMENTATION "A keyword: usually one of:
:RELEASED, :EXPERIMENTAL, :OBSOLETE, :INCONSISTENT, :BROKEN")
  (VERSION-LIST NIL :DOCUMENTATION
    "List of PATCH-VERSION structures corresponding to loaded patches. MOST RECENT FIRST.")
  (DIRECTORY-LOADED-ID NIL :DOCUMENTATION
    "Cons of truename and creation-date of the file to which we last read or wrote the
patch directory to a file, or NIL")
  (PATCH-DIR NIL :DOCUMENTATION "The patch-directory, as last read from file, or NIL.")
  )

;;; Format of patch directory
(DEFSTRUCT (PATCH-DIR :LIST (:CONC-NAME PATCH-DIR-) (:ALTERANT NIL))
  STATUS
  VERSION-LIST)			;List of patches and explanations, **OLDEST** first.

;;; Information for each patch.
;;; Elements of the PATCH-VERSION-LIST and the PATCH-DIR-VERSION-LIST look like this.
(DEFSTRUCT (PATCH-VERSION :LIST (:CONC-NAME VERSION-) (:ALTERANT NIL))
  (NUMBER NIL :DOCUMENTATION "Minor number of the patch")
  (EXPLANATION NIL :DOCUMENTATION "String explaining the contents of the patch")
  (AUTHOR USER-ID :DOCUMENTATION "Who dun it")
  (UNRELEASED NIL :DOCUMENTATION
    "T means that this patch is not released,
and will not normally be loaded by LOAD-PATCHES unless explicitly requested."))

;;; List of systems that are legal to patch, i.e. list of PATCH-SYSTEM's
(DEFVAR PATCH-SYSTEMS-LIST NIL)

;;; Given the name of a system, or the system itself, return the patch system
(DEFUN GET-PATCH-SYSTEM-NAMED (NAME &OPTIONAL NO-ERROR-P ONLY-IF-LOADED &AUX SYSTEM)
  "Return the object of type patch-system whose name is NAME.
NAME can be a string or symbol, or a system object.
NO-ERROR-P means return NIL rather than getting error if no such patchable system.
ONLY-IF-LOADED means return NIL if the system definition is not loaded;
 do not consider loading a file to get the definition."
  (COND ((AND (SETQ SYSTEM (FIND-SYSTEM-NAMED NAME NO-ERROR-P ONLY-IF-LOADED))
	      (ASS #'STRING-EQUAL (SYSTEM-NAME SYSTEM) PATCH-SYSTEMS-LIST)))
	(NO-ERROR-P NIL)
	(T (FERROR NIL "The system ~A is not patchable." SYSTEM))))

(DEFUN ADD-PATCH-SYSTEM (NAME &AUX PATCH-SYSTEM VERSION FIRST-VERS PATCH-DIR STATUS)
  "Add a new patchable system named NAME if there is none.
Done when the system is loaded.
Read in the patch directory files to find out the version.
Returns the major version and the system status."
  ;; Flush old patch system if there is one
  (AND (SETQ PATCH-SYSTEM (GET-PATCH-SYSTEM-NAMED NAME T))
       (SETQ PATCH-SYSTEMS-LIST (DELQ PATCH-SYSTEM PATCH-SYSTEMS-LIST)))
  (SETQ VERSION (GET-PATCH-SYSTEM-MAJOR-VERSION NAME)
	PATCH-SYSTEM (MAKE-PATCH-SYSTEM :NAME NAME :VERSION VERSION)
	PATCH-DIR (READ-PATCH-DIRECTORY PATCH-SYSTEM)
	FIRST-VERS (FIRST (PATCH-DIR-VERSION-LIST PATCH-DIR)))
  (OR (EQ (VERSION-NUMBER FIRST-VERS) 0)
      (FERROR NIL "Patch directory for ~A messed up: ~S" NAME FIRST-VERS))
  (SETF (PATCH-STATUS PATCH-SYSTEM) (SETQ STATUS (PATCH-DIR-STATUS PATCH-DIR)))
  (SETF (PATCH-VERSION-LIST PATCH-SYSTEM) (NCONS FIRST-VERS))
  (SETQ PATCH-SYSTEMS-LIST (NCONC PATCH-SYSTEMS-LIST (NCONS PATCH-SYSTEM)))
  (VALUES VERSION STATUS))

(DEFUN INCREMENT-PATCH-SYSTEM-MAJOR-VERSION (NAME STATUS &AUX VERSION PATCH-MAJOR)
  "Increment the major version of the patchable system NAME, and set status to STATUS.
This modifies the patch directory files of the system."
  (SETQ VERSION (GET-PATCH-SYSTEM-MAJOR-VERSION NAME T))
  (WHEN (NULL VERSION)
    (FORMAT T "~&No master directory for system ~A, creating one." NAME)
    (SETQ VERSION 0))
  (INCF VERSION)
  (SETQ PATCH-MAJOR (MAKE-PATCH-MAJOR :NAME NAME :VERSION VERSION))
  (WITH-OPEN-FILE (FILE (PATCH-SYSTEM-PATHNAME NAME :SYSTEM-DIRECTORY) :DIRECTION :OUTPUT)
    (FORMAT FILE
	    ";;; -*- Mode:LISP; Package:USER; Base:10; Readtable:T; Patch-File:T -*-~%")
    (WRITE-RESPONSIBILITY-COMMENT FILE)
    (LET ((*PRINT-BASE* 10.))
      (PRINT PATCH-MAJOR FILE)))
  (LET ((FIRST-VERS (MAKE-PATCH-VERSION :NUMBER 0
					:EXPLANATION (FORMAT NIL "~A Loaded" NAME))))
    (WRITE-PATCH-DIRECTORY PATCH-MAJOR (MAKE-PATCH-DIR :STATUS STATUS
						       :VERSION-LIST (NCONS FIRST-VERS))
			   T))
  VERSION)

(DEFUN GET-PATCH-SYSTEM-MAJOR-VERSION (NAME &OPTIONAL NO-ERROR-P)
  "Return the major version of patchable system NAME, as recorded in files.
NO-ERROR-P says no error if cannot read the files."
  (LET ((PATHNAME (PATCH-SYSTEM-PATHNAME NAME :SYSTEM-DIRECTORY)))
    (CONDITION-CASE-IF NO-ERROR-P ()
	(WITH-OPEN-FILE (FILE PATHNAME)
	  (LET ((PATCH-MAJOR (LET ((*READ-BASE* 10.)
				   (*READTABLE* INITIAL-READTABLE))
			       (CLI:READ FILE))))
	    (IF (NOT (STRING-EQUAL NAME (PATCH-NAME PATCH-MAJOR)))
		(FERROR NIL
			"~A name does not agree with ~A the name in the patch descriptor file"
			NAME (PATCH-NAME PATCH-MAJOR)))
	    (PATCH-VERSION PATCH-MAJOR)))
      (FS:FILE-ERROR NIL))))

(DEFVAR SYSTEM-STATUS-ALIST '((:EXPERIMENTAL "Experimental" "Exp" "experimental")
			      (:RELEASED "" "" "released")
			      (:OBSOLETE "Obsolete" "Obs" "obsolete")
			      (:INCONSISTENT "Inconsistent (unreleased patches loaded)"
					     "Bad" "inconsistent (unreleased patches loaded)")
			      (:BROKEN "Broken" "Broke" "broken")))

(DEFUN READ-PATCH-DIRECTORY (PATCH-SYSTEM &OPTIONAL NOERROR &AUX DIR)
  "Read in a patch directory file, returning the list-structure representation.
PATCH-SYSTEM is an object of type PATCH-SYSTEM.
The value is described by the defstruct PATCH-DIR.
NOERROR means return NIL rather than get error if patch directory file won't open."
  (CONDITION-CASE-IF NOERROR ()
      (WITH-OPEN-FILE (PATCH-DIR (PATCH-SYSTEM-PATHNAME (PATCH-NAME PATCH-SYSTEM)
							:VERSION-DIRECTORY
							(PATCH-VERSION PATCH-SYSTEM)))
	(LET ((*READ-BASE* 10.) (*PRINT-BASE* 10.) (*PACKAGE* PKG-USER-PACKAGE)
	      (*READTABLE* INITIAL-READTABLE)
	      (INFO (SEND PATCH-DIR :INFO)))
	  ;; don't waste time reading it in again
	  (IF (AND INFO (EQUAL INFO (PATCH-DIRECTORY-LOADED-ID PATCH-SYSTEM)))
	      (SETQ DIR (PATCH-PATCH-DIR PATCH-SYSTEM))
	    (SETQ DIR (CLI:READ PATCH-DIR))
	    (SETF (PATCH-PATCH-DIR PATCH-SYSTEM) DIR
		  (PATCH-DIRECTORY-LOADED-ID PATCH-SYSTEM) INFO)))
	(UNLESS (ASSQ (PATCH-DIR-STATUS DIR) SYSTEM-STATUS-ALIST)
	  (FERROR NIL "UNKNOWN PATCH SYSTEM STATUS ~S for ~A"
		  (PATCH-DIR-STATUS DIR) (PATCH-NAME PATCH-SYSTEM)))
	DIR)
    (FS:FILE-ERROR NIL)))

;;; Write out a patch directory file from the list-structure representation.
(DEFUN WRITE-PATCH-DIRECTORY (PATCH-SYSTEM PATCH-DIR &OPTIONAL MAJORP)
  "Write out a new patch directory file for PATCH-SYSTEM.
PATCH-DIR is a list described by the defstruct PATCH-DIR,
which is the data to write into the file."
  (LET ((*PRINT-BASE* 10.) (*READ-BASE* 10.) (*PACKAGE* PKG-USER-PACKAGE)
	(*NOPOINT T) (*PRINT-RADIX* NIL)
	(*READTABLE* INITIAL-READTABLE))
    (WITH-OPEN-FILE (STREAM (PATCH-SYSTEM-PATHNAME (PATCH-NAME PATCH-SYSTEM)
						   :VERSION-DIRECTORY
						   (PATCH-VERSION PATCH-SYSTEM))
			       :DIRECTION :OUTPUT)
       (FORMAT STREAM
	       ";;; -*- Mode:LISP; Package:USER; Base:10; Readtable:T; Patch-File:T -*-
;;; Patch directory for ~A version ~D
"
	       (PATCH-NAME PATCH-SYSTEM) (PATCH-VERSION PATCH-SYSTEM))
       (WRITE-RESPONSIBILITY-COMMENT STREAM)
       (WRITE-CHAR #/( STREAM)
       (PRIN1 (PATCH-DIR-STATUS PATCH-DIR) STREAM)
       (SEND STREAM :STRING-OUT "
 (")
       (DOLIST (PATCH (PATCH-DIR-VERSION-LIST PATCH-DIR))
	 (PRIN1 PATCH STREAM)
	 (SEND STREAM :STRING-OUT "
  "))
       (SEND STREAM :STRING-OUT "))")
       (UNLESS MAJORP
	 (SETF (PATCH-DIRECTORY-LOADED-ID PATCH-SYSTEM) (SEND STREAM :INFO))
	 (SETF (PATCH-PATCH-DIR PATCH-SYSTEM) PATCH-DIR)))))

(DEFUN PRINT-PATCHES (&OPTIONAL (SYSTEM "System") (AFTER 0))
  "Print the patches of the system SYSTEM after minor version AFTER."
  (LET* ((PATCH-SYSTEM (GET-PATCH-SYSTEM-NAMED SYSTEM T T))
	 (VERSION (PATCH-VERSION PATCH-SYSTEM))	;efficiency
	 (LATEST (VERSION-NUMBER (CAR (PATCH-VERSION-LIST PATCH-SYSTEM)))))
    (IF (NULL PATCH-SYSTEM)
	(FORMAT T "~%No ~A system loaded~%" SYSTEM)
      (FORMAT T "~%~A ~8TModification:~%" (PATCH-NAME PATCH-SYSTEM))
      (IF (> AFTER LATEST) (FORMAT T "Most recent patch loaded is ~D." LATEST)
	(DOLIST (V (REVERSE (PATCH-VERSION-LIST PATCH-SYSTEM)))
	  (WHEN ( AFTER (VERSION-NUMBER V)) (PRINT-PATCH VERSION V)))))))

(DEFUN PATCH-LOADED-P (MAJOR-VERSION MINOR-VERSION &OPTIONAL (SYSTEM "System"))
  "T if specified patch to patchable system SYSTEM is now loaded.
The patch specified is the one with numbers MAJOR-VERSION and MINOR-VERSION.
If the actual loaded major version is greater than MAJOR-VERSION
then the answer is T regardless of MINOR-VERSION, on the usually-true assumption
that the newer system contains everything patched into the older one.
NIL if SYSTEM is not loaded at all."
  (LET* ((PATCH-SYSTEM (GET-PATCH-SYSTEM-NAMED SYSTEM T T))
	 CURRENT-MAJOR-VERSION)
    (AND PATCH-SYSTEM
	 (SETQ CURRENT-MAJOR-VERSION (PATCH-VERSION PATCH-SYSTEM))
	 (OR (> CURRENT-MAJOR-VERSION MAJOR-VERSION)
	     (AND (= CURRENT-MAJOR-VERSION MAJOR-VERSION)
		  ( (OR (VERSION-NUMBER (CAR (PATCH-VERSION-LIST PATCH-SYSTEM))) 0)
		     MINOR-VERSION))))))

(DEFUN PRINT-PATCH (MAJOR-VERSION-NUMBER PATCH-VERSION-DESC)
  (FORMAT T "~&~D.~D ~8T~A:~:[~; (unreleased)~]~&~10T~~A~"
	  MAJOR-VERSION-NUMBER
	  (VERSION-NUMBER PATCH-VERSION-DESC)
	  (VERSION-AUTHOR PATCH-VERSION-DESC)
	  (VERSION-UNRELEASED PATCH-VERSION-DESC)
	  (VERSION-EXPLANATION PATCH-VERSION-DESC)))

;;; LOAD-PATCHES and LOAD-AND-SAVE-PATCHES, and RESERVE-PATCH and the rest
;;; of what the editor's patch commands used, are deleted.  This system makes releases,
;;; never patches; what is left here tracks the release number.

;;; Say who did it: which hardware, which firmware, which software, and which meatware.
(DEFUN WRITE-RESPONSIBILITY-COMMENT (STREAM &AUX (TIME:*DEFAULT-DATE-PRINT-MODE* :DD-MMM-YY))
  (FORMAT STREAM "~&;;; Written ~\DATIME\ by ~A,
;;; while running on ~A from band ~C
;;; with ~A.~2%"
	  USER-ID LOCAL-PRETTY-HOST-NAME
	  (LDB #o2010 CURRENT-LOADED-BAND) (SYSTEM-VERSION-INFO)))

;;;; Utilities for system versions

(DEFVAR SYSTEM-ADDITIONAL-INFO ""
  "Additional info is printed after the version when the system is booted.")

;;; This function updates the system version, asking the user.  If this is a fresh
;;; cold-load, the major-version stored on the file system is incremented.
;;; Returns string to go in the disk label.
;;; The user is allowed to add additional commentary.  If the whole string
;;; won't fit in the silly small disk-label comment field, the user
;;; is asked to retype it in an abbreviated form.
(DEFUN GET-NEW-SYSTEM-VERSION (&OPTIONAL (MAXIMUM-LENGTH 16.) &KEY INCREMENTAL)
  (FORMAT T "~&This is now:")
  (DESCRIBE-SYSTEM-VERSIONS)
  (FRESH-LINE)
  (SETQ SYSTEM-ADDITIONAL-INFO
	(READLINE-TRIM *QUERY-IO* ""
		       `((:PROMPT "Additional comment for herald: ")
			 (:INITIAL-INPUT ,system-additional-info)
			 (:INITIAL-INPUT-POINTER ,(LENGTH SYSTEM-ADDITIONAL-INFO)))))
  (LET ((VERS (SYSTEM-VERSION-INFO T)))
    (IF INCREMENTAL
	(SETQ VERS (STRING-APPEND "Inc " VERS)))
    ;; If short version doesn't fit, allow user to edit it (e.g. abbreviate system names)
    (DO (SHORT)
	(( (LENGTH VERS) MAXIMUM-LENGTH))
      (SETQ SHORT (SUBSTRING VERS 0 MAXIMUM-LENGTH))
      (SETQ VERS
	    (READLINE-TRIM *QUERY-IO* ""
			   `((:PROMPT ,(FORMAT NIL "~S will not fit in disk label.~@
						    Please abbreviate to ~D character~:P: "
					       VERS MAXIMUM-LENGTH))
			     (:INITIAL-INPUT ,VERS)
			     (:INITIAL-INPUT-POINTER ,MAXIMUM-LENGTH)))))
    VERS))

(DEFUN SYSTEM-VERSION-INFO (&OPTIONAL (BRIEF-P NIL) &AUX (FIRST T) TEM)
  "Return a one-line string giving the versions of all patchable systems.
Also gives the microcode version, and the loaded band's disk label comment.
With BRIEF-P, return stuff suitable for disk label comment."
  (WITH-OUTPUT-TO-STRING (S)
    (UNLESS (AND BRIEF-P (EQ (PATCH-STATUS (GET-PATCH-SYSTEM-NAMED "System")) :INCONSISTENT))
      ;; If some system is inconsistent but System is not,
      ;; make sure "Bad" appears at the front.
      (DOLIST (SYS PATCH-SYSTEMS-LIST)
	(WHEN (EQ (PATCH-STATUS SYS) :INCONSISTENT)
	  (FORMAT S (IF BRIEF-P "Bad " "Don't-dump-a-band! "))
	  (RETURN))))
    (DOLIST (SYS PATCH-SYSTEMS-LIST)
      (COND ((NOT (AND BRIEF-P (SYSTEM-SHOULD-NOT-APPEAR-IN-DISK-LABEL (PATCH-NAME SYS))))
	     (IF (NOT FIRST)
		 (SEND S :STRING-OUT (IF BRIEF-P " " ", ")))
	     (SETQ FIRST NIL)
	     (COND ((NULL (SETQ TEM (ASSQ (PATCH-STATUS SYS) SYSTEM-STATUS-ALIST)))
		    (SETQ TEM (STRING (PATCH-STATUS SYS))))
		   (BRIEF-P
		    (SETQ TEM (THIRD TEM)))
		   (T
		    (SETQ TEM (SECOND TEM))))
	     (UNLESS (EQUAL TEM "")
	       (SEND S :STRING-OUT TEM)
	       (SEND S :TYO #/SP))
	     (IF (NOT (AND BRIEF-P (EQUALP (PATCH-NAME SYS) "System")))
		 (FORMAT S "~A " (IF (NOT BRIEF-P) (PATCH-NAME SYS)
				     (SYSTEM-SHORT-NAME (PATCH-NAME SYS)))))
	     ;; the major version only.  This system makes no patches, so every
	     ;; release is N.0 and the minor number carries no information.
	     (FORMAT S "~D" (PATCH-VERSION SYS)))))
    (IF (NOT BRIEF-P)
	(FORMAT S ", microcode ~D" %MICROCODE-VERSION-NUMBER))
    (AND (PLUSP (STRING-LENGTH SYSTEM-ADDITIONAL-INFO))
	 (FORMAT S ", ~A" SYSTEM-ADDITIONAL-INFO))))

(DEFUN DESCRIBE-SYSTEM-VERSIONS (&OPTIONAL (S *STANDARD-OUTPUT*)
				 &AUX (MAX 9) NAME-LIST STATUS)
  "Print the version numbers of all patchable systems, one per line, on stream S.
The microcode version number and some other suitable information is also included."
  (SETQ NAME-LIST (MAKE-LIST (LENGTH PATCH-SYSTEMS-LIST)))
  (DO ((SYS PATCH-SYSTEMS-LIST (CDR SYS))
       (NAM NAME-LIST (CDR NAM)))
      ((NULL SYS))
    (SETQ STATUS (SECOND (ASSQ (PATCH-STATUS (CAR SYS)) SYSTEM-STATUS-ALIST)))
    (SETF (CAR NAM)
	  (WITH-OUTPUT-TO-STRING (STREAM)
	    (WHEN (PLUSP (LENGTH STATUS))
	      (SEND STREAM :STRING-OUT STATUS)
	      (SEND STREAM :TYO #/SP))
	    (SEND STREAM :STRING-OUT (PATCH-NAME (CAR SYS)))))
    (SETQ MAX (MAX (ARRAY-ACTIVE-LENGTH (CAR NAM)) MAX)))
  (DO ((SYS PATCH-SYSTEMS-LIST (CDR SYS))
       (NAM NAME-LIST (CDR NAM)))
      ((NULL SYS))
    (FORMAT S "~& ~A" (CAR NAM))
    (DOTIMES (I (- MAX (ARRAY-ACTIVE-LENGTH (CAR NAM))))
      (WRITE-CHAR #/SPACE S))
    ;; the major version only, as in SYSTEM-VERSION-INFO above.
    (FORMAT S " ~3D" (PATCH-VERSION (CAR SYS))))
  (FORMAT S "~& Microcode")
  (DOTIMES (I (- MAX 9))
    (WRITE-CHAR #/SPACE S))
  (FORMAT S " ~3D" %MICROCODE-VERSION-NUMBER)
  ;; the machine the microcode found at boot, the cadr or quux, under the
  ;; microcode it runs, aligned with it.
  (format s "~& Machine Type")
  (dotimes (i (- max 12.))		;decimal: this file reads in base 8
    (write-char #/space s))
  (format s " ~A" (machine-type)))

(DEFUN PRINT-SYSTEM-MODIFICATIONS (&REST SYSTEM-NAMES)
  "Print descriptions of all loaded patches of the systems in SYSTEM-NAMES, or all systems."
  (IF (NULL SYSTEM-NAMES)
      (DOLIST (PATCH PATCH-SYSTEMS-LIST)
	(PRINT-PATCHES (PATCH-NAME PATCH)))
    (DOLIST (PAT-NAME SYSTEM-NAMES)
      (PRINT-PATCHES PAT-NAME))))

(DEFUN GET-SYSTEM-VERSION (&OPTIONAL (SYSTEM "System"))
  "Returns the major and minor version numbers and status of the system named SYSTEM.
This describes what is currently loaded, not the most recent ones on disk.
Returns NIL if no such patchable system exists."
  (DECLARE (VALUES MAJOR MINOR STATUS))
  (LET ((PATCH (GET-PATCH-SYSTEM-NAMED SYSTEM T T)))
    (IF PATCH
	(VALUES (PATCH-VERSION PATCH)
		(VERSION-NUMBER (FIRST (PATCH-VERSION-LIST PATCH)))
		(PATCH-STATUS PATCH)))))

(DEFUN SET-SYSTEM-STATUS (SYSTEM NEW-STATUS &OPTIONAL MAJOR-VERSION &AUX PATCH PATCH-DIR)
  "Change the status of the system named SYSTEM to NEW-STATUS.
NEW-STATUS should be :EXPERIMENTAL, :BROKEN, :RELEASED or :OBSOLETE.
If MAJOR-VERSION is specified, the status of that major version is set.
Otherwise the status of the currently loaded major version is set.
This modifies the patch directory files."
  (UNLESS (ASSQ NEW-STATUS SYSTEM-STATUS-ALIST)
    (FERROR NIL "~S is not a defined system status." NEW-STATUS))
  (SETQ PATCH (GET-PATCH-SYSTEM-NAMED SYSTEM))
  (IF (AND MAJOR-VERSION ( MAJOR-VERSION (PATCH-VERSION PATCH)))
      (SETQ PATCH (MAKE-PATCH-SYSTEM :NAME SYSTEM :VERSION MAJOR-VERSION :STATUS NEW-STATUS))
    ;; Also change in core copy
    (SETF (PATCH-STATUS PATCH) NEW-STATUS))
  (SETQ PATCH-DIR (READ-PATCH-DIRECTORY PATCH))
  (SETF (PATCH-DIR-STATUS PATCH-DIR) NEW-STATUS)
  (WRITE-PATCH-DIRECTORY PATCH PATCH-DIR))

(ADD-INITIALIZATION 'RECORD-SYSTEM-VERSION
		    '(SETF (SYSTEM-COMMUNICATION-AREA %SYS-COM-MAJOR-VERSION)
			   (GET-SYSTEM-VERSION))
		    :BEFORE-COLD)

;; kansas:<l.sys2>patch
