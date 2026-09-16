;;;-*- Mode:LISP; Package:SYSTEM-INTERNALS; Readtable:T; Base:10 -*-
;;; ** (c) Copyright 1982 Massachusetts Institute of Technology **

;;; New version of resource package, subsumes system-window facility
;;; Note that WITH-RESOURCE is obsolete because it takes its "arguments"
;;; in the wrong order.  It has been replaced by USING-RESOURCE.

;;; Old form of DEFRESOURCE:
;;;	(DEFRESOURCE [name | (name dont-make-initial-copy)] . creator-body)
;;; New form of DEFRESOURCE:
;;;	(DEFRESOURCE name parameters [docstring] keyword value keyword value ...)
;;;  Keywords are:
;;;	:CONSTRUCTOR form   (this is required)
;;;		Sees parameters as arguments.
;;;	:FINDER form
;;;		Sees parameters as arguments.
;;;	:MATCHER form
;;;		Sees OBJECT (in current package) and parameters as arguments.
;;;	:CHECKER form
;;;		Sees OBJECT and IN-USE-P (in current package) and parameters as arguments.
;;;	:INITIALIZER form
;;;		Sees OBJECT and parameters as arguments.
;;;	:DEINITIALIZER form
;;;		Sees OBJECT as arguments
;;;	  In the above five options, form may also be a symbol which is a function to call.
;;;	  It gets the resource data structure as its first argument then the specified args.
;;;	:INITIAL-COPIES number  (default 0)
;;;		If this is specified, all parameters must be &optional and
;;;		have suitable defaults.  This is generally a good idea anyway.
;;;		Specifying NIL here is the same as zero.
;;;     :FREE-LIST-SIZE number  (default 20.)
;;;		If this is specified, the size of the free-list for this resource
;;;		will initially be that number.
;;;  If :FINDER is specified, we keep no list of free objects and use :FINDER
;;;  to find a free one by looking through the general environment.
;;;  Otherwise we keep a table of objects and whether they are free.
;;;  If :MATCHER is specified, we use it to check them against the parameters.
;;;  Otherwise the a-list also includes the parameter values, which are checked
;;;  with EQUAL (not EQ).
;;;  If :CHECKER is specified, then it gets to pass on each object to decide whether
;;;  or not to reuse it, whether or not it is already marked as in-use.
;;;
;;;  The finder, matcher, and checker are called without-interrupts.
;;;
;;;  Possible features that might be added: ability to keep a free list threaded
;;;  through the objects.  Code to be run when something is deallocated, e.g.
;;;  to deactivate a window.
;;;
;;;  Note: for windows, you typically want to use DEFWINDOW-RESOURCE,
;;;  which supplies the right options to DEFRESOURCE.
;;;
;;; DEFRESOURCE no longer uses the value and function cells of the resource's name.
;;; It puts on a DEFRESOURCE property of the following defstruct.  Note: only the
;;; functions right here are "allowed" to know what is in this structure.

(DEFSTRUCT (RESOURCE (:TYPE :NAMED-ARRAY-LEADER) (:ALTERANT NIL)
		     (:CONC-NAME RESOURCE-))
  NAME				;Symbol which names it
  (N-OBJECTS 0)			;Number of objects on the free list.
  PARAMETIZER			;Function which defaults the parameters and returns list
  CONSTRUCTOR			;Constructor function
  FINDER			;Optional finder function
  MATCHER			;Optional matcher function
  CHECKER			;Optional checker function
  INITIALIZER			;Optional initializer function
  DEINITIALIZER			;Optional deinitializer function
  )

;;; kludge for system 99.
;(defun resource-deinitializer (resource)
;  (and (> (array-leader-length resource) 9) (array-leader resource 10.)))

;;; The free list is the (n x 3) array itself, with the following fields:
(DEFSUBST RESOURCE-OBJECT (RESOURCE I) (AREF RESOURCE I 0))
(DEFSUBST RESOURCE-IN-USE-P (RESOURCE I) (AREF RESOURCE I 1))
(DEFSUBST RESOURCE-PARAMETERS (RESOURCE I) (AREF RESOURCE I 2))

(DEFSELECT ((:PROPERTY RESOURCE NAMED-STRUCTURE-INVOKE))
  (:DESCRIBE (RESOURCE &AUX (N-OBJECTS (RESOURCE-N-OBJECTS RESOURCE)))
    (DESCRIBE-DEFSTRUCT RESOURCE)
    (COND ((ZEROP N-OBJECTS)
	   (FORMAT T "~&There are currently no objects.~%"))
	  (T (FORMAT T "~&There ~[~;is~:;are~] currently ~:*~D object~:P:~@
			Object~40TParameters~60TIn Use"
		     N-OBJECTS)
	     (LOOP FOR I FROM 0 BELOW N-OBJECTS DOING
		   (FORMAT T "~%~S~40T~S~60T~:[No~;Yes~]"
			   (RESOURCE-OBJECT RESOURCE I)
			   (RESOURCE-PARAMETERS RESOURCE I)
			   (RESOURCE-IN-USE-P RESOURCE I)))
	     (FORMAT T "~%"))))
  (:PRINT-SELF (RESOURCE STREAM &REST IGNORE &AUX (N-OBJECTS (RESOURCE-N-OBJECTS RESOURCE)))
    (PRINTING-RANDOM-OBJECT (RESOURCE STREAM :TYPE)
      (FORMAT STREAM "~S (~D object~:P, ~D in use)"
	      (RESOURCE-NAME RESOURCE) N-OBJECTS
	      (LOOP FOR I FROM 0 BELOW N-OBJECTS COUNT (RESOURCE-IN-USE-P RESOURCE I))))))

(DEFMACRO DEFRESOURCE (NAME PARAMETERS &REST OPTIONS)
  "Define a resource named NAME, with parameters PARAMETERS for constructing objects.
OPTIONS can specify how to create objects and how to tell when old objects can be reused.
Options are :CONSTRUCTOR (required) :FINDER :MATCHER :CHECKER :INITIALIZER :DEINITIALIZER
 :INITIAL-COPIES :FREE-LIST-SIZE See the manual for details."
  (LET ((CONSTRUCTOR-FORM NIL) (FINDER-FORM NIL) (MATCHER-FORM NIL) (CHECKER-FORM NIL)
	(CONSTRUCTOR-FUNCTION NIL) (FINDER-FUNCTION NIL) (MATCHER-FUNCTION NIL)
	(PARAMETIZER-FUNCTION NIL) (CHECKER-FUNCTION NIL) (INITIAL-COPIES 0)
	(INITIALIZER-FORM NIL) (INITIALIZER-FUNCTION NIL)
	(DEINITIALIZER-FORM NIL) (DEINITIALIZER-FUNCTION NIL)
	(FREE-LIST-SIZE 20.) (PARAMS NIL)
	(DOCUMENTATION NIL))
    (UNLESS (CLI:LISTP PARAMETERS)
      (FERROR NIL "~S invalid parameter list" PARAMETERS))
    (SETQ PARAMS (LOOP FOR P IN PARAMETERS
		       UNLESS (MEMQ P LAMBDA-LIST-KEYWORDS)
		       COLLECT (IF (SYMBOLP P) P (CAR P))))
    ;; if first option is a string, use it as documentation instead
    (WHEN (STRINGP (CAR OPTIONS))
      (SETQ DOCUMENTATION (POP OPTIONS)))
    (LOOP FOR (KEYWORD VALUE) ON OPTIONS BY 'CDDR
	  DO (CASE KEYWORD
	       (:CONSTRUCTOR (SETQ CONSTRUCTOR-FORM VALUE))
	       (:FINDER (SETQ FINDER-FORM VALUE))
	       (:MATCHER (SETQ MATCHER-FORM VALUE))
	       (:CHECKER (SETQ CHECKER-FORM VALUE))
	       (:INITIALIZER (SETQ INITIALIZER-FORM VALUE))
	       (:DEINITIALIZER (SETQ DEINITIALIZER-FORM VALUE))
	       (:INITIAL-COPIES
		(SETQ INITIAL-COPIES
		      (COND ((NULL VALUE) 0)
			    ((NUMBERP VALUE) VALUE)
			    (T (FERROR NIL "~S ~S - number required"
				       :INITIAL-COPIES VALUE)))))
	       (:FREE-LIST-SIZE
		(SETQ FREE-LIST-SIZE
		      (COND ((NULL VALUE) 20.)
			    ((NUMBERP VALUE) VALUE)
			    (T (FERROR NIL "~S ~S - number required"
				       :FREE-LIST-SIZE VALUE)))))
	       (OTHERWISE (FERROR NIL "~S unknown option in ~S" 'DEFRESOURCE KEYWORD))))
    (OR CONSTRUCTOR-FORM (FERROR NIL "~S requires the ~S option" 'DEFRESOURCE :CONSTRUCTOR))
    ;; Pick function names.  Note that NIL is SYMBOLP.
    (SETQ CONSTRUCTOR-FUNCTION (IF (SYMBOLP CONSTRUCTOR-FORM) CONSTRUCTOR-FORM
				 `(:PROPERTY ,NAME RESOURCE-CONSTRUCTOR)))
    (SETQ FINDER-FUNCTION (IF (SYMBOLP FINDER-FORM) FINDER-FORM
			    `(:PROPERTY ,NAME RESOURCE-FINDER)))
    (SETQ MATCHER-FUNCTION (IF (SYMBOLP MATCHER-FORM) MATCHER-FORM
			     `(:PROPERTY ,NAME RESOURCE-MATCHER)))
    (SETQ CHECKER-FUNCTION (IF (SYMBOLP CHECKER-FORM) CHECKER-FORM
			     `(:PROPERTY ,NAME RESOURCE-CHECKER)))
    (SETQ INITIALIZER-FUNCTION (IF (SYMBOLP INITIALIZER-FORM) INITIALIZER-FORM
				 `(:PROPERTY ,NAME RESOURCE-INITIALIZER)))
    (SETQ DEINITIALIZER-FUNCTION (IF (SYMBOLP DEINITIALIZER-FORM) DEINITIALIZER-FORM
				 `(:PROPERTY ,NAME RESOURCE-DEINITIALIZER)))
    (SETQ PARAMETIZER-FUNCTION (IF (AND PARAMETERS (NOT MATCHER-FORM) (NOT FINDER-FORM))
				   `(:PROPERTY ,NAME RESOURCE-PARAMETIZER)))
    `(LOCAL-DECLARE ((SYS:FUNCTION-PARENT ,NAME DEFRESOURCE))
       ,(IF (NOT (SYMBOLP CONSTRUCTOR-FORM))
	    `(DEFUN ,CONSTRUCTOR-FUNCTION (IGNORE ,@PARAMETERS)
	       ,@PARAMS
	       ,CONSTRUCTOR-FORM))
       ,(IF (NOT (SYMBOLP FINDER-FORM))
	    `(DEFUN ,FINDER-FUNCTION (IGNORE ,@PARAMETERS)
	       ,@PARAMS
	       ,FINDER-FORM))
       ,(IF (NOT (SYMBOLP MATCHER-FORM))
	    `(DEFUN ,MATCHER-FUNCTION (IGNORE ,(INTERN "OBJECT") ,@PARAMETERS)
	       ,@PARAMS
	       ,MATCHER-FORM))
       ,(IF (NOT (SYMBOLP CHECKER-FORM))
	    `(DEFUN ,CHECKER-FUNCTION (IGNORE ,(INTERN "OBJECT") ,(INTERN "IN-USE-P")
				       ,@PARAMETERS)
	       ,@PARAMS ,(INTERN "OBJECT") ,(INTERN "IN-USE-P")
	       ,CHECKER-FORM))
       ,(IF (NOT (SYMBOLP INITIALIZER-FORM))
	    `(DEFUN ,INITIALIZER-FUNCTION (IGNORE ,(INTERN "OBJECT") ,@PARAMETERS)
	       ,@PARAMS ,(INTERN "OBJECT")
	       ,INITIALIZER-FORM))
       ,(IF (NOT (SYMBOLP INITIALIZER-FORM))
	    `(DEFUN ,DEINITIALIZER-FUNCTION (IGNORE ,(INTERN "OBJECT") ,@PARAMETERS)
	       ,@PARAMS ,(INTERN "OBJECT")
	       ,DEINITIALIZER-FORM))
       ,(IF PARAMETIZER-FUNCTION
	    `(DEFUN ,PARAMETIZER-FUNCTION ,PARAMETERS
	       (LIST ,@PARAMS)))
       (INITIALIZE-RESOURCE ',NAME ',CONSTRUCTOR-FUNCTION ',FINDER-FUNCTION
			    ',MATCHER-FUNCTION ',CHECKER-FUNCTION
			    ',PARAMETIZER-FUNCTION ',INITIAL-COPIES ',FREE-LIST-SIZE
			    ',INITIALIZER-FUNCTION ',DEINITIALIZER-FUNCTION)
       ,(IF DOCUMENTATION
	  `(SET-DOCUMENTATION ',NAME 'RESOURCE ,DOCUMENTATION)))))

(DEFPROP DEFRESOURCE "Resource" DEFINITION-TYPE-NAME)

(DEFVAR *ALL-RESOURCES* ()
  "List of all symbols that are names of DEFRESOURCEs.")

(DEFUN INITIALIZE-RESOURCE (NAME CONSTRUCTOR-FUNCTION FINDER-FUNCTION MATCHER-FUNCTION
			    CHECKER-FUNCTION PARAMETIZER-FUNCTION INITIAL-COPIES
			    FREE-LIST-SIZE INITIALIZER-FUNCTION
			    ;; Keep this &OPTIONAL for the time being so old QFASLs work.
			    &OPTIONAL DEINITIALIZER-FUNCTION)
  (OR (SYMBOLP CONSTRUCTOR-FUNCTION)
      (SETQ CONSTRUCTOR-FUNCTION (GET (SECOND CONSTRUCTOR-FUNCTION)
				      (THIRD CONSTRUCTOR-FUNCTION))))
  (OR (SYMBOLP FINDER-FUNCTION)
      (SETQ FINDER-FUNCTION (GET (SECOND FINDER-FUNCTION) (THIRD FINDER-FUNCTION))))
  (OR (SYMBOLP MATCHER-FUNCTION)
      (SETQ MATCHER-FUNCTION (GET (SECOND MATCHER-FUNCTION) (THIRD MATCHER-FUNCTION))))
  (OR (SYMBOLP CHECKER-FUNCTION)
      (SETQ CHECKER-FUNCTION (GET (SECOND CHECKER-FUNCTION) (THIRD CHECKER-FUNCTION))))
  (OR (SYMBOLP INITIALIZER-FUNCTION)
      (SETQ INITIALIZER-FUNCTION (GET (SECOND INITIALIZER-FUNCTION)
					(THIRD INITIALIZER-FUNCTION))))
  (OR (SYMBOLP DEINITIALIZER-FUNCTION)
      (SETQ DEINITIALIZER-FUNCTION (GET (SECOND DEINITIALIZER-FUNCTION)
					(THIRD DEINITIALIZER-FUNCTION))))
  (OR (SYMBOLP PARAMETIZER-FUNCTION)
      (SETQ PARAMETIZER-FUNCTION (GET (SECOND PARAMETIZER-FUNCTION)
				      (THIRD PARAMETIZER-FUNCTION))))
  (AND (RECORD-SOURCE-FILE-NAME NAME 'DEFRESOURCE)
       (LET ((OLD-RESOURCE (GET NAME 'DEFRESOURCE)) RESOURCE)
	 ;; Be careful that there's enough room for all objects in the old resource
	 ;; when replacing it.
	 (AND OLD-RESOURCE (NOT FINDER-FUNCTION)
	      (SETQ FREE-LIST-SIZE (MAX (RESOURCE-N-OBJECTS OLD-RESOURCE)
					FREE-LIST-SIZE)))
	 (AND FINDER-FUNCTION (SETQ FREE-LIST-SIZE 0))
	 (SETQ RESOURCE (MAKE-RESOURCE :NAME NAME
				       :MAKE-ARRAY (:LENGTH (LIST FREE-LIST-SIZE 3)
						    :AREA PERMANENT-STORAGE-AREA)
				       :PARAMETIZER PARAMETIZER-FUNCTION
				       :CONSTRUCTOR CONSTRUCTOR-FUNCTION
				       :FINDER FINDER-FUNCTION
				       :MATCHER MATCHER-FUNCTION
				       :CHECKER CHECKER-FUNCTION
				       :INITIALIZER INITIALIZER-FUNCTION
				       :DEINITIALIZER DEINITIALIZER-FUNCTION))
	 ;; Save any old objects when reloading a DEFRESOURCE
	 (WHEN (AND OLD-RESOURCE (NOT FINDER-FUNCTION))
	   (COPY-ARRAY-CONTENTS OLD-RESOURCE RESOURCE)
	   (SETF (RESOURCE-N-OBJECTS RESOURCE)
		 (RESOURCE-N-OBJECTS OLD-RESOURCE)))
	 (PUTPROP NAME RESOURCE 'DEFRESOURCE)
	 (LOOP FOR OBJECT IN (LOOP REPEAT INITIAL-COPIES COLLECT (ALLOCATE-RESOURCE NAME))
	       DO (DEALLOCATE-RESOURCE NAME OBJECT))))
  (PUSHNEW NAME *ALL-RESOURCES* :TEST #'EQ)
  NAME)

;Don't record this in qfasl files because it always does a RECORD-SOURCE-FILE-NAME.
(DEFPROP INITIALIZE-RESOURCE T QFASL-DONT-RECORD)

;>> should the deinitializer get run here? I don't think so...
(DEFUN CLEAR-RESOURCE (RESOURCE-NAME &AUX RESOURCE)
  "Throw away all objects allocated from the resource RESOURCE-NAME.
This is useful if you discover they were all constructed wrong,
and you fix the constructor, to make sure newly constructed objects will be used."
  (CHECK-ARG RESOURCE-NAME (SETQ RESOURCE (GET RESOURCE-NAME 'DEFRESOURCE))
	     "the name of a resource")
  (WITHOUT-INTERRUPTS
    ;; Clear the actual cells so the old objects can be garbage collected immediately.
    (LOOP FOR I FROM 0 BELOW (RESOURCE-N-OBJECTS RESOURCE)
	  WHEN (RESOURCE-IN-USE-P RESOURCE I)
	    DO (FORMAT *ERROR-OUTPUT* "~%[Warning: ~S still in use]"
		       (RESOURCE-OBJECT RESOURCE I))
	  DO (SETF (RESOURCE-OBJECT RESOURCE I) NIL)
      FINALLY (SETF (RESOURCE-N-OBJECTS RESOURCE) 0))))

(DEFUN MAP-RESOURCE (FUNCTION RESOURCE-NAME &REST EXTRA-ARGS &AUX RESOURCE)
  "Call FUNCTION on each object created in resource RESOURCE-NAME.
FUNCTION gets three args at each call: the object, whether the resource
believes it is in use, and RESOURCE-NAME."
  (CHECK-ARG RESOURCE-NAME (SETQ RESOURCE (GET RESOURCE-NAME 'DEFRESOURCE))
	     "the name of a resource")
  ;; Windows are the user's problem....
  (LOOP FOR I FROM 0 BELOW (RESOURCE-N-OBJECTS RESOURCE)
	FOR OBJECT = (RESOURCE-OBJECT RESOURCE I)
	WHEN OBJECT
	  DO (APPLY FUNCTION OBJECT (RESOURCE-IN-USE-P RESOURCE I) RESOURCE-NAME
		    EXTRA-ARGS)))
  
(DEFUN ALLOCATE-RESOURCE (RESOURCE-NAME &REST PARAMETERS
			  &AUX RESOURCE (PARAMS PARAMETERS)  ;Note PARAMS is UNSAFE!
			  TEM INDEX (OLD INHIBIT-SCHEDULING-FLAG) INITIALIZER)
  "Allocate an object from resource RESOURCE-NAME according to PARAMETERS.
An old object is reused if possible; otherwise a new one is created.
The significance of the PARAMETERS is determined by the individual resource."
  (CHECK-ARG RESOURCE-NAME (SETQ RESOURCE (GET RESOURCE-NAME 'DEFRESOURCE))
	     "the name of a resource")
  (AND (SETQ TEM (RESOURCE-PARAMETIZER RESOURCE))
       (< (LENGTH PARAMS) (LDB %%ARG-DESC-MAX-ARGS (%ARGS-INFO TEM)))
       (SETQ PARAMS (APPLY TEM PARAMS)))
  (WITHOUT-INTERRUPTS
    (COND ((SETQ TEM (RESOURCE-FINDER RESOURCE))
	   (SETQ TEM (APPLY TEM RESOURCE PARAMS)))
	  ((LOOP WITH CHECKER = (RESOURCE-CHECKER RESOURCE)
		 WITH MATCHER = (RESOURCE-MATCHER RESOURCE)
		 WITH N-OBJECTS = (RESOURCE-N-OBJECTS RESOURCE)
		 FOR N FROM (1- N-OBJECTS) DOWNTO 0
		 AS IN-USE-P = (RESOURCE-IN-USE-P RESOURCE N)
		 AS OBJ = (RESOURCE-OBJECT RESOURCE N)
		 WHEN (AND (IF CHECKER
			       (APPLY CHECKER RESOURCE OBJ IN-USE-P PARAMS)
			       (NOT IN-USE-P))
			   (IF MATCHER (APPLY MATCHER RESOURCE OBJ PARAMS)
			       (OR (NULL PARAMS)
				   (EQUAL (RESOURCE-PARAMETERS RESOURCE N) PARAMS))))
		   DO (SETF (RESOURCE-IN-USE-P RESOURCE N) T)
		      (RETURN (SETQ TEM OBJ))))
	  (T (SETQ INHIBIT-SCHEDULING-FLAG OLD)
	     (SETQ PARAMS (COPYLIST PARAMS))
	     (SETQ TEM (APPLY (RESOURCE-CONSTRUCTOR RESOURCE) RESOURCE PARAMS))
	     (SETQ INHIBIT-SCHEDULING-FLAG T)
	     (SETF (RESOURCE-N-OBJECTS RESOURCE)
		   (1+ (SETQ INDEX (RESOURCE-N-OBJECTS RESOURCE))))
	     (WHEN ( INDEX (ARRAY-DIMENSION RESOURCE 0))
	       (PUTPROP (RESOURCE-NAME RESOURCE)
			(SETQ RESOURCE (ARRAY-GROW RESOURCE
						   (+ INDEX (MAX 20. (TRUNCATE INDEX 2)))
						   3))
			'DEFRESOURCE))
	     (SETF (RESOURCE-OBJECT RESOURCE INDEX) TEM)
	     (SETF (RESOURCE-IN-USE-P RESOURCE INDEX) T)
	     (SETF (RESOURCE-PARAMETERS RESOURCE INDEX)			;Avoid lossage with
		   (IF (EQ PARAMS PARAMETERS) (COPY-LIST PARAMS)	;as little consing
		     PARAMS)))))					;as possible.
  ;; TEM now is the object
  (AND (SETQ INITIALIZER (RESOURCE-INITIALIZER RESOURCE))
       (APPLY INITIALIZER RESOURCE TEM PARAMS))
  TEM)

(DEFUN DEALLOCATE-RESOURCE (RESOURCE-NAME OBJECT &AUX RESOURCE DEINITIALIZER)
  "Return OBJECT to the free pool of resource RESOURCE-NAME.
OBJECT should have been returned by a previous call to ALLOCATE-RESOURCE."
  (CHECK-ARG RESOURCE-NAME (SETQ RESOURCE (GET RESOURCE-NAME 'DEFRESOURCE))
	     "the name of a resource")
  (UNLESS (RESOURCE-FINDER RESOURCE)
    (LOOP WITH N-OBJECTS = (RESOURCE-N-OBJECTS RESOURCE)
	  FOR N FROM (1- N-OBJECTS) DOWNTO 0
	  WITH DEINITIALIZER = (RESOURCE-DEINITIALIZER RESOURCE)
	  WHEN (EQ (RESOURCE-OBJECT RESOURCE N) OBJECT)
	    ;; Note that this doesn't need any locking.
	    DO (IF DEINITIALIZER (APPLY DEINITIALIZER RESOURCE OBJECT))
	       (RETURN (SETF (RESOURCE-IN-USE-P RESOURCE N) NIL))
	  FINALLY (FERROR NIL "~S is not an object from the ~S resource"
			  OBJECT RESOURCE-NAME))))


(DEFUN DEALLOCATE-WHOLE-RESOURCE (RESOURCE-NAME &AUX RESOURCE)
  "Return all objects allocated from resource RESOURCE-NAME to the free pool."
  (CHECK-ARG RESOURCE-NAME (SETQ RESOURCE (GET RESOURCE-NAME 'DEFRESOURCE))
	     "the name of a resource")
  (UNLESS (RESOURCE-FINDER RESOURCE)
    (LOOP WITH N-OBJECTS = (RESOURCE-N-OBJECTS RESOURCE)
	  FOR N FROM 0 BELOW N-OBJECTS
	  WITH DEINITIALIZER = (RESOURCE-DEINITIALIZER RESOURCE)
	  WHEN (RESOURCE-IN-USE-P RESOURCE N)
	    DO (IF DEINITIALIZER
		   (FUNCALL DEINITIALIZER RESOURCE (RESOURCE-OBJECT RESOURCE N)))
	       (SETF (RESOURCE-IN-USE-P RESOURCE N) NIL))))

(DEFMACRO USING-RESOURCE (&ENVIRONMENT ENV (VAR RESOURCE-NAME . PARAMETERS) &BODY BODY)
  "Execute BODY with VAR bound to an object allocated from resource RESOURCE-NAME.
PARAMETERS are used in selecting or creating the object,
according to the definition of the resource."
  (MULTIPLE-VALUE-BIND (BODY DECLARATIONS)
      (EXTRACT-DECLARATIONS BODY NIL NIL ENV)
    `(LET ((,VAR NIL))
       ,(IF DECLARATIONS `(DECLARE . ,DECLARATIONS))
       (UNWIND-PROTECT
	   (PROGN
	     (SETQ ,VAR (ALLOCATE-RESOURCE ',RESOURCE-NAME . ,PARAMETERS))
	     . ,BODY)
	 (AND ,VAR (DEALLOCATE-RESOURCE ',RESOURCE-NAME ,VAR))))))
