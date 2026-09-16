;;; -*- Mode: LISP;  Package: FS;  Base: 8 -*-
;;;	** (c) Copyright 1981 Massachusetts Institute of Technology **
;;; Chaosnet FILE JOB peek functions

(DEFUN DC-ACCESS-PEEK-FILE-SYSTEM ()
  (TV:SCROLL-MAINTAIN-LIST
    `(LAMBDA () ',(SEND SELF :HOST-UNITS))
    #'PEEK-FILE-SYSTEM-HOST-UNIT))

(DEFUN PEEK-FILE-SYSTEM-HOST-UNIT (UNIT &OPTIONAL (INDENT 2))
  "Generate a scroll item describing a host unit"
  (LIST ()
    (TV:SCROLL-PARSE-ITEM ':MOUSE
			  `(NIL :MENU-CHOOSE
				("Host-unit operations"
				 ("Reset" :EVAL (FUNCALL THISUNIT ':RESET)
				  :DOCUMENTATION
				  "Click left to close this connection")
				 ("Inspect" :EVAL
				  (LET ((TERMINAL-IO TYPWIN))
				    (INSPECT THISUNIT))
				  :DOCUMENTATION
				  "Click left to INSPECT this host-unit.")
				 ("Describe" :EVAL
				  (LET ((TERMINAL-IO TYPWIN))
				    (DESCRIBE THISUNIT))
				  :DOCUMENTATION
				  "Click left to DESCRIBE this host-unit."))
				:DOCUMENTATION
				"Menu of things to do to this host-unit."
				:BINDINGS
				((THISUNIT ',UNIT)
				 (TYPWIN ',(FUNCALL SELF ':TYPEOUT-WINDOW))))
			  (FORMAT NIL "~V@THost unit for ~A, control connection in "
				  INDENT (SEND UNIT :HOST))
			  `(:FUNCTION ,#'(LAMBDA (UNIT)
					   (LET ((CONN (SEND UNIT :CONTROL-CONNECTION)))
					     (IF CONN (GET-PNAME (CHAOS:STATE CONN))
						 "NONEXISTANT-STATE")))
				      (,UNIT)))
    (TV:SCROLL-MAINTAIN-LIST `(LAMBDA () (PEEK-FILE-SYSTEM-HOST-UNIT-NEXT-STREAM
					   (NCONS (SEND ',UNIT :DATA-CONNECTIONS)) T))
			     `(LAMBDA (STREAM)
				(FUNCALL STREAM ':PEEK-FILE-SYSTEM (+ 2 ,INDENT)))
			     NIL
			     #'(LAMBDA (STATE &AUX NS STREAM)
				 (MULTIPLE-VALUE (NS STREAM)
				   (PEEK-FILE-SYSTEM-HOST-UNIT-NEXT-STREAM STATE))
				 (VALUES STREAM NS
					 (NULL (PEEK-FILE-SYSTEM-HOST-UNIT-NEXT-STREAM
						 NS T)))))))

(DEFUN PEEK-FILE-SYSTEM-HOST-UNIT-NEXT-STREAM (STATE &OPTIONAL DONT-STEP &AUX STREAM FLAG NS)
  "Returns new state and next stream.  If DONT-STEP is specified, returns the current
state if there is a stream available, else NIL"
  (SETQ FLAG (CDR STATE))
  (DO ((S (CAR STATE) (CDR S)))
      ((NULL S) (SETQ NS NIL))
    (SETQ NS S)
    (AND (NULL FLAG) (SETQ STREAM (DATA-STREAM (CAR S) ':INPUT))
	 (NEQ STREAM T) (RETURN (SETQ FLAG T)))
    (SETQ FLAG NIL)
    (AND (SETQ STREAM (DATA-STREAM (CAR S) ':OUTPUT))
	 (NEQ STREAM T) (RETURN (SETQ NS (CDR NS)))))
  (AND (NOT (SYMBOLP STREAM))
       (VALUES (IF DONT-STEP
		   STATE
		   (RPLACA STATE NS)
		   (RPLACD STATE FLAG))
	       STREAM)))

