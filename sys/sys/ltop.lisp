;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:8; Readtable:ZL; Cold-load:T -*-
;;; Initialization & top-level READ-EVAL-PRINT loop

(DEFVAR SYN-TERMINAL-IO (MAKE-SYN-STREAM '*TERMINAL-IO*)
  "A synonym stream that points to the value of *TERMINAL-IO*.")

(DEFVAR LISP-TOP-LEVEL-INSIDE-EVAL :UNBOUND
  "Bound to T while within EVAL inside the top-level loop.")

(DEFVAR * NIL "Value of last expression evaluated by read-eval-print loop.")
(DEFVAR ** NIL "Value of next-to-last expression evaluated by read-eval-print loop.")
(DEFVAR *** NIL "Value of third-to-last expression evaluated by read-eval-print loop.")

(DEFVAR + NIL "Last expression evaluated by read-eval-print loop.")
(DEFVAR ++ NIL "Next-to-last expression evaluated by read-eval-print loop.")
(DEFVAR +++ NIL "Third-to-last expression evaluated by read-eval-print loop.")

(DEFVAR // NIL "All values of last expression evaluated by read-eval-print loop.")
(DEFVAR CLI:// NIL "All values of last expression evaluated by read-eval-print loop.")
(DEFVAR //// NIL "All values of next-to-last expression evaluated by read-eval-print loop.")
(DEFVAR ////// NIL "All values of third-to-last expression evaluated by read-eval-print loop.")
(FORWARD-VALUE-CELL 'CLI:// '//)

(DEFVAR - NIL "Expression currently being evaluated by read-eval-print loop.")

(DEFVAR *VALUES* NIL
  "List of all lists-of-values produced by the expressions evaluated in this listen loop.
Most recent evaluations come first on the list.")

(DEFVAR LISP-CRASH-LIST :UNBOUND
  "List of forms to be evaluated at next warm or cold boot.")

(DEFVAR ORIGINAL-LISP-CRASH-LIST :UNBOUND
  "List of forms that was evaluated when the cold load was first booted.")

(DEFVAR ERROR-STACK-GROUP :UNBOUND
  "The first level error handler stack group that handles traps from the microcode.")

(DEFVAR %ERROR-HANDLER-STACK-GROUP :UNBOUND
  "Microcode variable that is initialized by warm boot to be ERROR-STACK-GROUP.")

(DEFVAR COLD-BOOT-HISTORY NIL
  "List of elements (HOST UNIVERSAL-TIME), one for each time this band was cold-booted.")

(DEFVAR COLD-BOOTING T
  "T while booting if this is a cold boot.  Always NIL except when booting or disk-saving.")

(DEFVAR *IN-COLD-LOAD-P* T
  "T if we are executing in a cold-load environment. 
Will be NIL by the time YOU get to look at it")

;;; Initial values of the following three come out of the cold load builder,
;;; since it gets them from QCOM anyway.
(DEFVAR A-MEMORY-VIRTUAL-ADDRESS :UNBOUND
  "Virtual address that is mapped by software to location 0 of A memory.")

(DEFVAR IO-SPACE-VIRTUAL-ADDRESS :UNBOUND
  "Virtual address mapped into start of XBUS I//O space.")

(DEFVAR UNIBUS-VIRTUAL-ADDRESS :UNBOUND
  "Virtual address mapped into Unibus location 0.")

(DEFCONST TV::TV-QUAD-SLOT #xF8 "Slot number for LAMBDA tv board.")


(ADD-INITIALIZATION "Next boot is a cold boot" '(SETQ COLD-BOOTING T)
		    '(:BEFORE-COLD))

;;; Come here when machine starts.  Provides a base frame.
(DEFUN LISP-TOP-LEVEL ()
  (LISP-REINITIALIZE NIL)			;(Re)Initialize critical variables and things
  (TERPRI (OR TV::INITIAL-LISP-LISTENER *TERMINAL-IO*))
  ;; LISP-TOP-LEVEL1 supposedly never returns, but loop anyway in case
  ;; someone forces it to return with the error-handler.
  (DO-FOREVER
    (IF (FBOUNDP 'PROCESS-TOP-LEVEL)
	(PROCESS-TOP-LEVEL)
      (LISP-TOP-LEVEL1 (OR TV::INITIAL-LISP-LISTENER *TERMINAL-IO*)))))

;;; Called when the main process is reset.
(DEFUN LISP-TOP-LEVEL2 ()
  (LISP-TOP-LEVEL1 (OR TV::INITIAL-LISP-LISTENER *TERMINAL-IO*)))

;;; Function to reset various things, do initialization that's inconvenient in cold load, etc.
;;; COLD-BOOT is T if this is for a cold boot.
(DEFUN LISP-REINITIALIZE (&OPTIONAL (CALLED-BY-USER T)
			  &AUX (COLD-BOOT COLD-BOOTING)
			  MUST-ENABLE-TRAPPING)
  "Resets various global constants and initializes the error system.
COLD-BOOT is T if this is for a cold boot."
  (SETQ INHIBIT-SCHEDULING-FLAG T)		;In case called by the user
  ;; make sure we don't use these until set up below
  (select-processor
    (:cadr
      (setq tv::tv-quad-slot nil)
      (setq rg-quad-slot nil)
      (setq sdu-quad-slot nil))
    (:lambda
      (setq tv::tv-quad-slot (compiler::%lambda-tv-quad-slot)
	    rg-quad-slot (compiler::%lambda-rg-quad-slot)
	    sdu-quad-slot (compiler::%lambda-sdu-quad-slot))))

  (SETQ ALPHABETIC-CASE-AFFECTS-STRING-COMPARISON NIL)
  ;; If these are set wrong, all sorts of things don't work.

  (SETQ LOCAL-DECLARATIONS NIL FILE-LOCAL-DECLARATIONS NIL
	UNDO-DECLARATIONS-FLAG NIL COMPILER::QC-FILE-IN-PROGRESS NIL)

  (SETQ *INTERPRETER-VARIABLE-ENVIRONMENT* NIL
	*INTERPRETER-FUNCTION-ENVIRONMENT* NIL
	*INTERPRETER-FRAME-ENVIRONMENT* NIL)

  ;; Provide ucode with space to keep EVCPs stuck into a-memory locations
  ;; by closure-binding the variables that forward there.
  (OR (AND (BOUNDP 'AMEM-EVCP-VECTOR) AMEM-EVCP-VECTOR)
      (SETQ AMEM-EVCP-VECTOR
	    (MAKE-ARRAY (+ (LENGTH SYS:A-MEMORY-LOCATION-NAMES) #o40 #o20)
			;;					     in case ucode grows.
			:AREA PERMANENT-STORAGE-AREA)))

  (UNLESS (NOT CALLED-BY-USER)
     (IF (FBOUNDP 'COMPILER::MA-RESET)	;Unload microcompiled defs, because they are gone!
	 (COMPILER::MA-RESET))		; Hopefully manage to do this before any gets called.
     ;; Set up the TV sync program as soon as possible; until it is set up
     ;; read references to the TV buffer can get NXM errors which cause a
     ;; main-memory parity error halt.  Who-line updating can do this.
     (WHEN (BOUNDP 'TV:DEFAULT-SCREEN)
       (IF (BOUNDP 'TV::SYNC-RAM-CONTENTS)
	   ;; if TV:SET-TV-SPEED has been done in this image,
	   ;; use the results from that.
	   (SETUP-CPT TV::SYNC-RAM-CONTENTS NIL T)
	   (SETUP-CPT))
       (IF (VARIABLE-BOUNDP TV:MAIN-SCREEN)
	   (SETQ %DISK-RUN-LIGHT
		 (+ (- (* TV:MAIN-SCREEN-HEIGHT
			  (TV:SHEET-LOCATIONS-PER-LINE TV:MAIN-SCREEN))
		       #o15)
		    (TV:SCREEN-BUFFER TV:MAIN-SCREEN))))
       (SETQ TV::WHO-LINE-RUN-LIGHT-LOC (+ 2 (LOGAND %DISK-RUN-LIGHT #o777777))))
     ;; Clear all the bits of the main screen after a cold boot.
     (AND COLD-BOOT (CLEAR-SCREEN-BUFFER IO-SPACE-VIRTUAL-ADDRESS)))

  ;; Do something at least if errors occur during loading
  (OR (FBOUNDP 'FERROR) (FSET 'FERROR #'FERROR-COLD-LOAD))
  (OR (FBOUNDP 'CERROR) (FSET 'CERROR #'CERROR-COLD-LOAD))
  (OR (FBOUNDP 'UNENCAPSULATE-FUNCTION-SPEC)
      (FSET 'UNENCAPSULATE-FUNCTION-SPEC #'(LAMBDA (X) X)))
  (OR (FBOUNDP 'FS:MAKE-PATHNAME-INTERNAL) (FSET 'FS:MAKE-PATHNAME-INTERNAL #'LIST))
  (OR (FBOUNDP 'FS:MAKE-FASLOAD-PATHNAME) (FSET 'FS:MAKE-FASLOAD-PATHNAME #'LIST))

  ;; Allow streams to work before WHOLIN loaded
  (OR (BOUNDP 'TV::WHO-LINE-FILE-STATE-SHEET)
      (SETQ TV::WHO-LINE-FILE-STATE-SHEET 'IGNORE))   ;NOT #'IGNORE since IGNORE not in coldld
  (UNCLOSUREBIND '(* ** *** + ++ +++ // //// ////// *VALUES*))

  (SETQ DEFAULT-CONS-AREA WORKING-STORAGE-AREA)	;Reset default areas.

  (UNCLOSUREBIND '(READ-AREA))
  (SETQ READ-AREA NIL)

  (NUMBER-GC-ON)				;This seems to work now, make it the default

  (UNLESS (GET 'CDR-NIL 'SYSTEM-CONSTANT)
    (MAPC #'(LAMBDA (Y) 
	      (MAPC #'(LAMBDA (X) 
			(PUTPROP X T 'SYSTEM-CONSTANT))
		    (SYMBOL-VALUE Y)))
	  SYSTEM-CONSTANT-LISTS)
    (MAPC #'(LAMBDA (Y) 
	      (MAPC #'(LAMBDA (X) 
			(PUTPROP X T 'SPECIAL))
		    (SYMBOL-VALUE Y)))
	  SYSTEM-VARIABLE-LISTS)
    (PUTPROP T T 'SYSTEM-CONSTANT)
    (PUTPROP T T 'SPECIAL)
    (PUTPROP NIL T 'SYSTEM-CONSTANT)
    (PUTPROP NIL T 'SPECIAL))

  (UNLESS (VARIABLE-BOUNDP *PACKAGE*)
    (PKG-INITIALIZE))

  (WHEN (NOT (BOUNDP 'CURRENT-PROCESS))		;Very first time around
    (SETQ SCHEDULER-EXISTS NIL
	  CURRENT-PROCESS NIL
	  TV::WHO-LINE-PROCESS NIL
	  TV::LAST-WHO-LINE-PROCESS NIL)
    (UNLESS (FBOUNDP 'TV::WHO-LINE-RUN-STATE-UPDATE)
      (FSET 'TV::WHO-LINE-RUN-STATE-UPDATE #'(LAMBDA (&REST IGNORE) NIL)))
    (KBD-INITIALIZE))
  (SETQ TV::KBD-LAST-ACTIVITY-TIME (TIME))	; Booting is keyboard activity.

  (INITIALIZE-WIRED-KBD-BUFFER)

  (select-processor
    (:lambda;; now that the "unibus" channel is set up, turn on 60Hz interrupts
      ;; first the vector
      (compiler::%nubus-write tv::tv-quad-slot 8
			      (dpb rg-quad-slot (byte 8 24.) (* 4 (+ #o400 #o260))))
      (compiler::%nubus-write tv::tv-quad-slot 4
			      (logior #o40 (compiler::%nubus-read tv::tv-quad-slot 4)))))

  ;; Flush any closure binding forwarding pointers
  ;; left around from a closure we were in when we warm booted.
  (UNCLOSUREBIND '(PRIN1 *PRINT-BASE* *READ-BASE*
		   FDEFINE-FILE-PATHNAME INHIBIT-FDEFINE-WARNINGS
		   SELF SI:PRINT-READABLY *PACKAGE* *READTABLE*
		   EH::ERROR-MESSAGE-HOOK EH::ERROR-DEPTH EH::ERRSET-STATUS))
  (when (variable-boundp zwei:*local-bound-variables*)
    (unclosurebind zwei:*local-bound-variables*))
  (when (variable-boundp *default-process-closure-variables*)
    (unclosurebind *default-process-closure-variables*))
  (unclosurebind '(zwei:*local-variables* zwei:*local-bound-variables*))

  ;; Initialize the rubout handler.
  (SETQ	RUBOUT-HANDLER NIL)			;We're not in it now

  ;; Initialize the error handler.
  (SETQ EH::CONDITION-HANDLERS NIL
	EH::CONDITION-DEFAULT-HANDLERS NIL
	EH::CONDITION-RESUME-HANDLERS NIL)
  (OR (BOUNDP 'ERROR-STACK-GROUP)
      (SETQ ERROR-STACK-GROUP (MAKE-STACK-GROUP 'ERROR-STACK-GROUP :SAFE 0)))
  (SETQ %ERROR-HANDLER-STACK-GROUP ERROR-STACK-GROUP)
  (STACK-GROUP-PRESET ERROR-STACK-GROUP 'LISP-ERROR-HANDLER)	;May not be defined yet 
  (SETF (SG-FOOTHOLD-DATA %INITIAL-STACK-GROUP) NIL)	;EH depends on this
  (WHEN (AND (FBOUNDP 'LISP-ERROR-HANDLER)
	     (FBOUNDP 'EH::ENABLE-TRAPPING))
    (SEND ERROR-STACK-GROUP '(INITIALIZE))
    (IF (NOT (BOUNDP 'EH::ERROR-TABLE))
	(SETQ MUST-ENABLE-TRAPPING T)
      ;; Note: if error-table not loaded,
      ;; we enable trapping after loading it.
      (EH::ENABLE-TRAPPING)))
  (SETQ EH::ERRSET-STATUS NIL EH::ERROR-MESSAGE-HOOK NIL);Turn off possible spurious errset
  (SETQ EH::ERROR-DEPTH 0)

  ;; Get the right readtable.
  (unless (variable-boundp initial-readtable)
    (setq initial-readtable *readtable*
	  *readtable* (copy-readtable *readtable*)
	  standard-readtable *readtable*)
    (setf (rdtbl-names *readtable*) (rdtbl-names initial-readtable))
    (pushnew *readtable* *all-readtables* :test #'eq))	;since not frobbed by cold-load
  (when (variable-boundp common-lisp-readtable)
    (unless (variable-boundp initial-common-lisp-readtable)
      (setq initial-common-lisp-readtable common-lisp-readtable
	    common-lisp-readtable (copy-readtable common-lisp-readtable))
      (setf (rdtbl-names common-lisp-readtable) (rdtbl-names initial-common-lisp-readtable)))
    (pushnew common-lisp-readtable *all-readtables* :test #'eq))

  ;; And all kinds of randomness...
  (SETQ TRACE-LEVEL 0)
  (SETQ INSIDE-TRACE NIL)
  (SETQ + NIL * NIL - NIL	;In case of error during first read/eval/print cycle
	// NIL ++ NIL +++ NIL 	;or if their values were unprintable or obscene
	** NIL *** NIL)  	;and to get global values if break in non-lisp-listener
  (SETQ //// NIL ////// NIL)
  (SETQ LISP-TOP-LEVEL-INSIDE-EVAL NIL)
  (SETQ %INHIBIT-READ-ONLY NIL)
  (UNLESS (BOUNDP 'PRIN1) (SETQ PRIN1 NIL))
  (SETQ *EVALHOOK* NIL *APPLYHOOK* NIL)
  (SETQ *READ-BASE* 10. *PRINT-BASE* 10.)
  (SETQ XR-CORRESPONDENCE-FLAG NIL		;Prevent the reader from doing random things
	XR-CORRESPONDENCE NIL)
; (SETQ *RSET T)				;In case any MACLISP programs look at it
  (SETQ FDEFINE-FILE-PATHNAME NIL)
  (SETQ INHIBIT-FDEFINE-WARNINGS NIL)		;Don't get screwed by warm boot

  (SETQ SELF-FLAVOR-DECLARATION NIL)
  (SETQ SELF NIL SELF-MAPPING-TABLE NIL)

  (SETQ SI:PRINT-READABLY NIL)

  (SETQ CHAOS:CHAOS-SERVERS-ENABLED NIL)	;Don't allow botherage from networks
  (IF COLD-BOOT (SETQ FS:USER-LOGIN-MACHINE NIL))
  (SETQ *PACKAGE* PKG-USER-PACKAGE)

  ;; The first time, this does top-level SETQ's from the cold-load files
  (OR (BOUNDP 'ORIGINAL-LISP-CRASH-LIST)	;Save it for possible later inspection
      (SETQ ORIGINAL-LISP-CRASH-LIST LISP-CRASH-LIST))

  (MAPC #'EVAL LISP-CRASH-LIST)
  (SETQ LISP-CRASH-LIST NIL)

  ;; Reattach IO streams.  Note that *TERMINAL-IO* will be fixed later to go to a window.
  (UNLESS CALLED-BY-USER
    (UNCLOSUREBIND '(*TERMINAL-IO* *STANDARD-OUTPUT* *STANDARD-INPUT*
				   *QUERY-IO* *TRACE-OUTPUT* *ERROR-OUTPUT* *DEBUG-IO*))
    (SETQ *TERMINAL-IO*	COLD-LOAD-STREAM
	  *STANDARD-OUTPUT* SYN-TERMINAL-IO
	  *STANDARD-INPUT*	SYN-TERMINAL-IO
	  *QUERY-IO*	SYN-TERMINAL-IO
	  *DEBUG-IO*	SYN-TERMINAL-IO
	  *TRACE-OUTPUT*	SYN-TERMINAL-IO
	  *ERROR-OUTPUT*	SYN-TERMINAL-IO)
    (SEND *TERMINAL-IO* :HOME-CURSOR))

  (SETQ TV::MOUSE-WINDOW NIL)	;This gets looked at before the mouse process is turned on
  (KBD-CONVERT-NEW 1_15.)	;Reset state of shift keys

  (SELECT-PROCESSOR
    (:CADR (AND (FBOUNDP 'CADR:CLEAR-UNIBUS-MAP);clear valid bits on unibus map.
		(CADR:CLEAR-UNIBUS-MAP))))	; and necessary if sharing Unibus with PDP11.
						; Do this before SYSTEM-INITIALIZATION-LIST to
						; avoid screwwing ETHERNET code.
  ;; These are initializations that have to be done before other initializations
  (INITIALIZATIONS 'SYSTEM-INITIALIZATION-LIST T)
  ;; At this point if the window system is loaded, it is all ready to go
  ;; and the initial Lisp listener has been exposed and selected.  So do
  ;; any future typeout on it.  But if any typeout happened on the cold-load
  ;; stream, leave it there (clobbering the Lisp listener's bits).  This does not
  ;; normally happen, but just in case we do the set-cursorpos below so that
  ;; if anything strange gets typed out it won't get erased.  Note that normally
  ;; we do not do any typeout nor erasing on the cold-load-stream, to avoid bashing
  ;; the bits of whatever window was exposed before a warm boot.
  (COND (CALLED-BY-USER)
	((FBOUNDP 'TV::WINDOW-INITIALIZE)
	 (MULTIPLE-VALUE-BIND (X Y) (SEND *TERMINAL-IO* :READ-CURSORPOS)
	   (SEND TV::INITIAL-LISP-LISTENER :SET-CURSORPOS X Y))
	 (SETQ *TERMINAL-IO* TV::INITIAL-LISP-LISTENER)
	 (SEND *TERMINAL-IO* :SEND-IF-HANDLES :SET-PACKAGE *PACKAGE*)
	 (SEND *TERMINAL-IO* :FRESH-LINE))
	(T (SETQ TV::INITIAL-LISP-LISTENER NIL)	;Not created yet
	   (SEND *TERMINAL-IO* :CLEAR-EOL)))

  (WHEN CURRENT-PROCESS
    (SEND CURRENT-PROCESS :RUN-REASON 'LISP-INITIALIZE))

  ;; prevent screw from things being traced during initialization
  (if (fboundp 'untrace) (untrace))
  (if (fboundp 'breakon) (unbreakon))

  ;; Have to check explicitly for col-booting since can't just rely on initializations
  ;; to see that everything in this list has already run (ie at last cold boot)
  ;; since luser may have added own new inits
  (IF COLD-BOOTING (INITIALIZATIONS 'COLD-INITIALIZATION-LIST))
  (INITIALIZATIONS 'WARM-INITIALIZATION-LIST T)

  (WHEN (AND MUST-ENABLE-TRAPPING
	     (BOUNDP 'EH::ERROR-TABLE))
    (EH::ENABLE-TRAPPING))

  (SETQ COLD-BOOTING NIL)

  (IF (FBOUNDP 'PRINT-HERALD)
      (PRINT-HERALD)
    (SEND *STANDARD-OUTPUT* :FRESH-LINE)
    (PRINC "Lisp Machine cold load environment, beware!
; *READ//PRINT-BASE* = ")
    (LET ((*PRINT-BASE* 10.))
      (PRINC *READ-BASE*))
    (PRINC ", *PACKAGE* = ")
    (PRINC (PACKAGE-NAME *PACKAGE*))
    (PRINC ".]"))

  (AND (BOUNDP 'TIME:*LAST-TIME-UPDATE-TIME*)
       (NULL (CAR COLD-BOOT-HISTORY))
       (SETF (CAR COLD-BOOT-HISTORY) (CATCH-ERROR (LIST SI:LOCAL-HOST
							(GET-UNIVERSAL-TIME)))))

  ;; This process no longer needs to be able to run except for the usual reasons.
  ;; The delayed-restart processes may now be allowed to run
  (WHEN CURRENT-PROCESS
    (SEND CURRENT-PROCESS :REVOKE-RUN-REASON 'LISP-INITIALIZE)
    (WHEN WARM-BOOTED-PROCESS
      (FORMAT T "Warm boot while running ~S.
Its variable bindings remain in effect;
its unwind-protects have been lost.~%" WARM-BOOTED-PROCESS)
      (WHEN (NOT (OR (EQ (PROCESS-WARM-BOOT-ACTION WARM-BOOTED-PROCESS)
			 'PROCESS-WARM-BOOT-RESTART)
		     (EQ WARM-BOOTED-PROCESS INITIAL-PROCESS)
		     (TYPEP WARM-BOOTED-PROCESS 'SI:SIMPLE-PROCESS)))
	(IF (YES-OR-NO-P "Reset it?  Answer No if you want to debug it.  ")
	    (RESET-WARM-BOOTED-PROCESS)
	  (FORMAT T "~&Do ~S to examine it, or do
~S to reset it and let it run again.~%
If you examine it, you will see a state that is not quite the latest one."
		  '(SI:DEBUG-WARM-BOOTED-PROCESS) '(SI:RESET-WARM-BOOTED-PROCESS)))))
    (LOOP FOR (P . RR) IN DELAYED-RESTART-PROCESSES
	  DO (WITHOUT-INTERRUPTS
	       (SETF (PROCESS-RUN-REASONS P) RR)
	       (PROCESS-CONSIDER-RUNNABILITY P)))
    (SETQ DELAYED-RESTART-PROCESSES NIL))

  ;; The global value of *TERMINAL-IO* is a stream which goes to an auto-exposing
  ;; window.  Some processes, such as Lisp listeners, rebind it to something else.
  ;; CALLED-BY-USER is T if called from inside one of those.
  (WHEN (AND (NOT CALLED-BY-USER)
	     (FBOUNDP 'TV::DEFAULT-BACKGROUND-STREAM)
	     (NEQ (SYMBOL-FUNCTION 'TV::DEFAULT-BACKGROUND-STREAM) COLD-LOAD-STREAM))
    (SETQ *TERMINAL-IO* TV::DEFAULT-BACKGROUND-STREAM))

  ;; Now that -all- initialization has been completed, allow network servers
  (SETQ CHAOS:CHAOS-SERVERS-ENABLED T))

(DEFUN UNCLOSUREBIND (SYMBOLS)
  "If any of SYMBOLS has a closure binding evcp pointer in its value cell, remove it.
Does not change the value of the symbol, but unshares it with the closure.
This does not need to be done on A-memory variables."
  (DOLIST (SYMBOL SYMBOLS)
    (LET ((LOC (FOLLOW-CELL-FORWARDING (VALUE-CELL-LOCATION SYMBOL) NIL)))
      (IF (= (%P-DATA-TYPE LOC) DTP-EXTERNAL-VALUE-CELL-POINTER)
	  (%BLT-TYPED (FOLLOW-CELL-FORWARDING LOC T) LOC 1 1)))))

(DEFUN CLEAR-SCREEN-BUFFER (BUFFER-ADDRESS)
  (%P-DPB 0 %%Q-LOW-HALF BUFFER-ADDRESS)
  (%P-DPB 0 %%Q-HIGH-HALF BUFFER-ADDRESS)
  (%BLT BUFFER-ADDRESS (1+ BUFFER-ADDRESS)
	#o77777 1))

;;; This is a temporary function, which turns on the "extra-pdl" feature
(DEFUN NUMBER-GC-ON (&OPTIONAL (ON-P T))
  (SETQ NUMBER-CONS-AREA
        (COND (ON-P EXTRA-PDL-AREA)
              (T WORKING-STORAGE-AREA))))

(DEFUN LISP-TOP-LEVEL1 (*TERMINAL-IO* &OPTIONAL (TOP-LEVEL-P T) &AUX OLD-PACKAGE W-PKG)
  "Read-eval-print loop used by lisp listeners.  *TERMINAL-IO*
is the stream to read and print with."
  (IF (VARIABLE-BOUNDP *PACKAGE*)
      (%BIND (LOCF *PACKAGE*) *PACKAGE*))
  (WHEN (FBOUNDP 'FORMAT)
    (FORMAT T "~&;Reading~@[ at top level~]" TOP-LEVEL-P)
    (IF (SEND *TERMINAL-IO* :OPERATION-HANDLED-P :NAME)
	(FORMAT T " in ~A." (SEND *TERMINAL-IO* :NAME))
      (FORMAT T ".")))
  (PUSH NIL *VALUES*)
  (DO ((*READTABLE* *READTABLE*)
       (*PRINT-BASE* *PRINT-BASE*) (*READ-BASE* *READ-BASE*)
       (LAST-TIME-READTABLE NIL)
       THROW-FLAG)	;Gets non-NIL if throw to COMMAND-LEVEL (e.g. quitting from an error)
      (NIL)		;Do forever
    ;; If *PACKAGE* has changed, set OLD-PACKAGE and tell our window.
    ;; Conversely, if the window's package has changed, change ours.
    ;; The first iteration, we always copy from the window.
    (COND ((NOT (VARIABLE-BOUNDP *PACKAGE*)))
	  ((EQ *TERMINAL-IO* COLD-LOAD-STREAM))
	  ;; User set the package during previous iteration of DO
	  ;; => tell the window about it.
	  ((AND OLD-PACKAGE (NEQ PACKAGE OLD-PACKAGE))
	   (SEND *TERMINAL-IO* :SEND-IF-HANDLES :SET-PACKAGE *PACKAGE*)
	   (SETQ OLD-PACKAGE *PACKAGE*))
	  ;; Window's package has been changed, or first iteration through DO,
	  ;; => set our package to the window's -- if the window has one.
	  ((SETQ W-PKG (SEND *TERMINAL-IO* :SEND-IF-HANDLES :PACKAGE))
	   (AND (NEQ W-PKG *PACKAGE*)
		(SETQ *PACKAGE* W-PKG))
	   (SETQ OLD-PACKAGE *PACKAGE*))
	  ;; First time ever for this window => set window's package
	  ;; to the global value of *PACKAGE*.
	  ((NULL OLD-PACKAGE)
	   (SETQ OLD-PACKAGE *PACKAGE*)
	   (SEND *TERMINAL-IO* :SEND-IF-HANDLES :SET-PACKAGE *PACKAGE*)))
    (CHECK-FOR-READTABLE-CHANGE LAST-TIME-READTABLE)
    (SETQ LAST-TIME-READTABLE *READTABLE*)
    (SETQ THROW-FLAG T)
    (CATCH-ERROR-RESTART ((SYS:ABORT ERROR) "Return to top level in ~A."
			  (OR (SEND *TERMINAL-IO* :SEND-IF-HANDLES :NAME)
			      "current process."))
      (TERPRI)
      (SETQ +++ ++ ++ + + -)			;Save last three input forms
      (SETQ - (READ-FOR-TOP-LEVEL))
      (LET ((LISP-TOP-LEVEL-INSIDE-EVAL T)
	    VALUES)
	(UNWIND-PROTECT
	    (SETQ VALUES (MULTIPLE-VALUE-LIST (EVAL-ABORT-TRIVIAL-ERRORS -)))
	  ;; Always push SOMETHING -- NIL if evaluation is aborted.
	  (PUSH VALUES *VALUES*))
	(SETQ ////// ////
	      //// //
	      // VALUES)
	(SETQ *** **				;Save first value, propagate old saved values
	      ** *
	      * (CAR //)))
      (DOLIST (VALUE //)
	(TERPRI)
	(FUNCALL (OR PRIN1 #'PRIN1) VALUE))
      (SETQ THROW-FLAG NIL))
    (WHEN THROW-FLAG
      ;; Inform user of return to top level.
      (FORMAT T "~&;Back to top level")
      (IF (SEND *TERMINAL-IO* :OPERATION-HANDLED-P :NAME)
	  (FORMAT T " in ~A." (SEND *TERMINAL-IO* :NAME))
	  (WRITE-CHAR #/.)))))

(defun check-for-readtable-change (last-time-readtable)
  "Says something about the readtable if (neq *readtable* last-time-readtable)"
  (unless (eq *readtable* last-time-readtable)
    (when (fboundp 'format)
      (format t "~&;Reading in base ~D in package ~A with ~A.~&"
	      *read-base* *package* *readtable*))
    t))

(defun common-lisp (flag &optional globally-p &aux (old-rdtbl *readtable*))
  "Makes the default syntax be either Common Lisp (if FLAG is non-NIL)
or Traditional Zetalisp (if FLAG is NIL)"
  (setq *readtable* (if flag common-lisp-readtable standard-readtable))
  (if globally-p (setq-globally *readtable* *readtable*))
  (if (eq *readtable* old-rdtbl) flag (values)))


(DEFVAR *BREAK-BINDINGS*
	'((RUBOUT-HANDLER NIL)			;Start new level of rubout catch
	  (READ-PRESERVE-DELIMITERS NIL)	;For normal Lisp syntax
	  (READ-CHECK-INDENTATION NIL)
	  (DEFAULT-CONS-AREA BACKGROUND-CONS-AREA)	;as opposed to compiler temp area
	  ;Next line commented out since it causes more trouble in than out
	  ;(IBASE 8) (BASE 8)
	  (OLD-STANDARD-INPUT *STANDARD-INPUT*)	;So user can find old stream.  BREAK, too!
	  (OLD-QUERY-IO *QUERY-IO*)		;...
	  (*STANDARD-INPUT* SYN-TERMINAL-IO)	;Rebind streams to terminal
	  (*STANDARD-OUTPUT* SYN-TERMINAL-IO)
	  (*QUERY-IO* SYN-TERMINAL-IO)
	  (EH::ERRSET-STATUS NIL)		;"Condition Wall" for errsets
	  (EH::CONDITION-HANDLERS NIL)		; and for conditions
	  (EH::CONDITION-DEFAULT-HANDLERS NIL)
	  (LOCAL-DECLARATIONS NIL)
	  (SELF-FLAVOR-DECLARATION NIL)
	  ;; must use FUNCALL in the line below as the cold-load cannot hack the macro "SEND"
	  (*READTABLE* (IF (EQ (FUNCALL *READTABLE* :GET :SYNTAX) ':COMMON-LISP)
			   COMMON-LISP-READTABLE
			   STANDARD-READTABLE))
	  ;Changed 3/3/80 by Moon not to bind *, +, and -.
	  )
  "Bindings to be made by the function BREAK.
Each element is a list (VARNAME VALUE-FORM) describing one binding.
Bindings are made sequentially.")

(DEFVAR OLD-STANDARD-INPUT)
(DEFVAR OLD-QUERY-IO)

;;; Note that BREAK binds RUBOUT-HANDLER to NIL so that a new level of catch
;;; will be established.  Before returning it restores the old rubout handler's buffer.
(DEFUN BREAK (&OPTIONAL FORMAT-STRING &REST FORMAT-ARGS
	      &AUX SAVED-BUFFER SAVED-BUFFER-POSITION)
  "Read-eval-print loop for use as subroutine.  Args are passed to FORMAT.
Many variables are rebound, as specified in SI::*BREAK-BINDINGS*."
  (SETQ FORMAT-STRING (STRING FORMAT-STRING))
;  (SETQ FORMAT-STRING
;	;; temporary kludge for compatability with past, when break took &quoted first arg
;	(IF (OR (SYMBOLP FORMAT-STRING) (AND (CONSP FORMAT-STRING)
;					     (EQ (CAR FORMAT-STRING) 'QUOTE)
;					     (SYMBOLP (CADR FORMAT-STRING))
;					     (NULL (CDDR FORMAT-STRING))
;					     (SETQ FORMAT-STRING (CADR FORMAT-STRING))))
;	    (STRING FORMAT-STRING)
;	  (EVAL FORMAT-STRING)))
  (UNLESS (OR (EQUAL FORMAT-STRING "")
	      (MEMQ (CHAR FORMAT-STRING (1- (LENGTH FORMAT-STRING))) '(#/. #/? #/!)))
    (SETQ FORMAT-STRING (STRING-APPEND FORMAT-STRING #/.)))
  (PROGW *BREAK-BINDINGS*
    ;; Deal with keyboard multiplexing in a way similar to the error-handler.
    ;; If we break in the scheduler, set CURRENT-PROCESS to NIL.
    ;; If this is not the scheduler process, make sure it has a run reason
    ;; in case we broke in the middle of code manipulating process data.
    ;; If INHIBIT-SCHEDULING-FLAG is set, turn it off and print a warning.
    (COND ((EQ %CURRENT-STACK-GROUP SCHEDULER-STACK-GROUP)
	   (SETQ CURRENT-PROCESS NIL)))
    (AND (NOT (NULL CURRENT-PROCESS))
	 (NULL (SEND CURRENT-PROCESS :RUN-REASONS))
	 (SEND CURRENT-PROCESS :RUN-REASON 'BREAK))
    (COND (INHIBIT-SCHEDULING-FLAG
	   (FORMAT T "~%---> Turning off INHIBIT-SCHEDULING-FLAG, you may lose. <---~%")
	   (SETQ INHIBIT-SCHEDULING-FLAG NIL)))
    (MULTIPLE-VALUE-SETQ (SAVED-BUFFER SAVED-BUFFER-POSITION)
      (SEND OLD-STANDARD-INPUT :SEND-IF-HANDLES :SAVE-RUBOUT-HANDLER-BUFFER))
    (FORMAT T "~&;Breakpoint ~?  ~:@C to continue, ~:@C to quit.~%"
	    FORMAT-STRING FORMAT-ARGS #/RESUME #/ABORT)
    (LET* ((LAST-TIME-READTABLE NIL)
	   (VALUE
	     (DO-FOREVER
	       (CHECK-FOR-READTABLE-CHANGE LAST-TIME-READTABLE)
	       (SETQ LAST-TIME-READTABLE *READTABLE*)
	       (TERPRI)
	      LOOK-FOR-SPECIAL-KEYS
	       (LET ((CHAR (SEND *STANDARD-INPUT* :TYI)))
		 ;; Intercept characters even if otherwise disabled in program
		 ;; broken out of.  Also treat c-Z like ABORT for convenience
		 ;; and for compatibility with the error handler.
		 (IF (= CHAR (CHAR-INT #/C-Z)) (SETQ CHAR (CHAR-INT #/ABORT)))
		 (COND ((AND (BOUNDP 'TV:KBD-STANDARD-INTERCEPTED-CHARACTERS)
			     (ASSQ CHAR TV:KBD-STANDARD-INTERCEPTED-CHARACTERS))
			(FUNCALL (CADR (ASSQ CHAR TV:KBD-STANDARD-INTERCEPTED-CHARACTERS))
				 CHAR))
		       ((= CHAR (CHAR-INT #/RESUME))
			(SEND *STANDARD-OUTPUT* :STRING-OUT "[Resume]
")
			(RETURN NIL))
		       (T (SEND *STANDARD-INPUT* :UNTYI CHAR))))
	       (LET ((EH::CONDITION-RESUME-HANDLERS (CONS T EH::CONDITION-RESUME-HANDLERS))
		     (THROW-FLAG T))
		 (CATCH-ERROR-RESTART ((SYS:ABORT ERROR)
				       "Return to BREAK ~?"
				       FORMAT-STRING FORMAT-ARGS)
		   (MULTIPLE-VALUE-BIND (TEM1 TEM)
		       (WITH-INPUT-EDITING (*STANDARD-INPUT* '((:FULL-RUBOUT :FULL-RUBOUT)
							       (:ACTIVATION CHAR= #/END)))
			 (READ-FOR-TOP-LEVEL))
		     (IF (EQ TEM ':FULL-RUBOUT)
			 (GO LOOK-FOR-SPECIAL-KEYS))
		     (SHIFTF +++ ++ + - TEM1))
		   (COND ((AND (CONSP -) (EQ (CAR -) 'RETURN))
			  (RETURN (EVAL-ABORT-TRIVIAL-ERRORS (CADR -)))))	;(RETURN form) proceeds
		   (LET (VALUES)
		     (UNWIND-PROTECT
			 (SETQ VALUES
			       (MULTIPLE-VALUE-LIST (EVAL-ABORT-TRIVIAL-ERRORS -)))
		       ;; Always push SOMETHING for each form evaluated.
		       (PUSH VALUES *VALUES*))
		     (SETQ ////// ////
			   //// //
			   // VALUES)
		     (SETQ *** **
			   ** *
			   * (CAR //)))
		   (DOLIST (VALUE //)
		     (TERPRI)
		     (FUNCALL (OR PRIN1 #'PRIN1) VALUE))
		   (SETQ THROW-FLAG NIL))
		 (WHEN THROW-FLAG
		   (FORMAT T "~&;Back to Breakpoint ~?  ~:@C to continue, ~:@C to quit.~%"
			   FORMAT-STRING FORMAT-ARGS #/RESUME #/ABORT))))))
      ;; Before returning, restore and redisplay rubout handler's buffer so user
      ;; gets what he sees, if we broke out of reading through the rubout handler.
      ;; If we weren't inside there, the rubout handler buffer is now empty because
      ;; we read from it, so leave it alone.  (Used to :CLEAR-INPUT).
      (WHEN SAVED-BUFFER
	(SEND OLD-STANDARD-INPUT :RESTORE-RUBOUT-HANDLER-BUFFER
	      SAVED-BUFFER SAVED-BUFFER-POSITION))
      VALUE)))

;;;; Initialization stuff

(DEFVAR BEFORE-COLD-INITIALIZATION-LIST NIL
  "Initializations to be run before doing a DISK-SAVE.")
(DEFVAR COLD-INITIALIZATION-LIST NIL
  "Initializations to be run on cold boot.")
(DEFVAR WARM-INITIALIZATION-LIST NIL
  "Initializations to be run on warm or cold boot.")
(DEFVAR ONCE-ONLY-INITIALIZATION-LIST NIL
  "Initializations to be run only once.  They have indeed been run if they are here.")
(DEFVAR SYSTEM-INITIALIZATION-LIST NIL
  "Initializations to be run on warm boot, before the COLD and WARM ones.")
(DEFVAR LOGIN-INITIALIZATION-LIST NIL
  "Initializations to be run on logging in.")
(DEFVAR LOGOUT-INITIALIZATION-LIST NIL
  "Initializations to be run on logging out.")

;;; Some code relies on INIT-NAME being the CAR of the init entry.  **DO NOT CHANGE THIS**
(DEFSTRUCT (INIT-LIST-ENTRY :LIST
			    (:CONSTRUCTOR MAKE-INIT-LIST-ENTRY (NAME FORM FLAG SOURCE-FILE))
			    (:CONC-NAME "INIT-")
			    (:ALTERANT NIL))
  (NAME NIL :DOCUMENTATION "Pretty name for this initialization (a string)")
  (FORM NIL :DOCUMENTATION "The actual code to eval when the initialization is run")
  (FLAG NIL :DOCUMENTATION "NIL means that this initialization has not yet been run")
  (SOURCE-FILE NIL :DOCUMENTATION "The source file for this initialization"))

(DEFMACRO INIT-LIST-CHECK (NAME)
  `(PROGN (OR (BOUNDP ,NAME)
	      (SET ,NAME NIL))
	  (OR (GET ,NAME 'INITIALIZATION-LIST)
	      (PUTPROP ,NAME T 'INITIALIZATION-LIST))))

(DEFUN INITIALIZATIONS (LIST-NAME &OPTIONAL (REDO-FLAG NIL) (FLAG T))
  "Run the inits in the initialization list whose name is LIST-NAME.
REDO-FLAG if non-NIL says rerun inits that are marked as already run.
If FLAG is T, inits are marked as run; if NIL, they are marked as not already run."
  (INIT-LIST-CHECK LIST-NAME)
  (DO ((INIT (SYMBOL-VALUE LIST-NAME) (CDR INIT)))
      ((NULL INIT))
    (WHEN (OR (NULL (INIT-FLAG (CAR INIT))) REDO-FLAG)
      (CATCH-ERROR-RESTART ((ERROR) "Abort the ~A initialization."
			    (INIT-NAME (CAR INIT)))
	(EVAL (INIT-FORM (CAR INIT))))
      (SETF (INIT-FLAG (CAR INIT)) FLAG))))

;;; Adds a new init to the list.
;;; Keywords are:
;;; NOW		Run the init now
;;; FIRST	Run the init now if this is the first entry for the specified name
;;; NORMAL	Do the "normal" thing (init when initializations normally run)
;;; REDO	Do nothing now, but set up things so init gets redone
;;; COLD	Use the cold boot list
;;; WARM	Use the warm boot list
;;; ONCE	Use the once-only list
;;; SYSTEM	Use the system list
;;; BEFORE-COLD	The list that gets done before disk-save'ing out
;;; LOGIN       Use the login list
;;; LOGOUT      Use the logout list
;;; SITE	Use the site list (also run once)
;;; SITE-OPTION Use the site-option list (also run once)
;;; HEAD-OF-LIST If entry not presently on list, add it to front instead of the end of list.
;;; If neither WARM nor COLD are specified, warm is assumed.  If a fourth argument
;;; is given, then it is the list to use.  WARM and COLD will override the fourth argument.
(DEFCONST INITIALIZATION-KEYWORDS
	  '((:SITE SITE-INITIALIZATION-LIST NOW)
	    (:SITE-OPTION SITE-OPTION-INITIALIZATION-LIST NOW)
	    (:SYSTEM SYSTEM-INITIALIZATION-LIST FIRST)
	    (:FULL-GC FULL-GC-INITIALIZATION-LIST)
	    (:AFTER-FULL-GC AFTER-FULL-GC-INITIALIZATION-LIST)
	    (:AFTER-FLIP AFTER-FLIP-INITIALIZATION-LIST)
	    (:ONCE ONCE-ONLY-INITIALIZATION-LIST FIRST)
	    (:LOGIN LOGIN-INITIALIZATION-LIST)
	    (:LOGOUT LOGOUT-INITIALIZATION-LIST)
	    (:WARM WARM-INITIALIZATION-LIST)
	    (:COLD COLD-INITIALIZATION-LIST)
	    (:BEFORE-COLD BEFORE-COLD-INITIALIZATION-LIST))
  "Alist defining keywords accepted by ADD-INITIALIZATION.
Each element looks like (KEYWORD LIST-VARIABLE-NAME [TIME-TO-RUN])
TIME-TO-RUN should be NOW, FIRST, NORMAL or REDO, or omitted.
It is a default in case the ADD-INITIALIZATION doesn't specify any of them.")

(DEFUN ADD-INITIALIZATION (NAME FORM &OPTIONAL KEYWORDS (LIST-NAME 'WARM-INITIALIZATION-LIST)
                                     &AUX WHEN DEFAULT-WHEN INIT HEAD-OF-LIST)
  "Add an initialization with name NAME and definition FORM to an initialization list.
NAME should be a string and FORM an expression to be evaluated later.
KEYWORDS can be one keyword or a list of them.  These keywords can be in any package.
Keywords can either be HEAD-OF-LIST, meaning add to front of list rather than the end,
COLD, WARM, ONCE, SYSTEM, BEFORE-COLD, LOGIN, LOGOUT, SITE, SITE-OPTION,
 FULL-GC, AFTER-FULL-GC or AFTER-FLIP, specifying a list,
or NOW, FIRST, NORMAL or REDO, saying when to run the init.
NOW means run the init as well as adding to the list;
FIRST means run the init now if it isn't on the list;
NORMAL means don't run the init now;
REDO means don't run it now, but mark it as never having been run
 even if it is already on the list and has been run.
If the keywords do not specify the list, LIST-NAME is used.
The default for it is SYS:WARM-INITIALIZATION-LIST."
  (DOLIST (S (IF (CLI:LISTP KEYWORDS) KEYWORDS (LIST KEYWORDS)))
    (LET* ((V (GET-PNAME S))
	   (KEYDEF (ASS #'STRING= V INITIALIZATION-KEYWORDS)))
      (IF KEYDEF (SETQ LIST-NAME (CADR KEYDEF)
		       DEFAULT-WHEN (CADDR KEYDEF))
	(COND ((MEM #'STRING= V '("NOW" "FIRST" "NORMAL" "REDO"))
	       (SETQ WHEN V))
	      ((STRING= "HEAD-OF-LIST" V)
	       (SETQ HEAD-OF-LIST T))
	      (T (FERROR NIL "Illegal keyword ~S" S))))))
  (SELECTOR (OR WHEN DEFAULT-WHEN) STRING=
    ((:NIL) (SETQ WHEN NIL))
    ((:NORMAL) (SETQ WHEN NIL))
    ((:NOW) (SETQ WHEN ':NOW))
    ((:REDO) (SETQ WHEN ':REDO))
    ((:FIRST) (SETQ WHEN ':FIRST)))
  (INIT-LIST-CHECK LIST-NAME)
  (SETQ INIT
        (DOLIST (L (SYMBOL-VALUE LIST-NAME)
		   (IF (OR HEAD-OF-LIST (NULL (SYMBOL-VALUE LIST-NAME)))
		       (CAR (PUSH (MAKE-INIT-LIST-ENTRY NAME FORM NIL FDEFINE-FILE-PATHNAME)
				  (SYMBOL-VALUE LIST-NAME)))
		     (CADR (RPLACD (LAST (SYMBOL-VALUE LIST-NAME))
				   (NCONS (MAKE-INIT-LIST-ENTRY
					    NAME FORM NIL FDEFINE-FILE-PATHNAME))))))
	  (WHEN (STRING= (INIT-NAME L) NAME)
	    (SETF (INIT-FORM L) FORM)
	    (SETF (INIT-SOURCE-FILE L) FDEFINE-FILE-PATHNAME)
	    (RETURN L))))
  (COND ((EQ WHEN ':REDO) (SETF (INIT-FLAG INIT) NIL))
        ((OR (EQ WHEN ':NOW)
             (AND (EQ WHEN ':FIRST) (NULL (INIT-FLAG INIT))))
         (EVAL (INIT-FORM INIT))
         (SETF (INIT-FLAG INIT) T))))

;;; Deletes an init from the list.
;;; All list-name keywords (see INITIALIZATION-KEYWORDS) are allowed.
;;; If there is one, it overrides the third argument.
(DEFUN DELETE-INITIALIZATION (NAME &OPTIONAL KEYWORDS (LIST-NAME 'WARM-INITIALIZATION-LIST))
  "Remove any initialization named NAME from an initialization list.
NAME should be a string.  KEYWORDS can be a keyword or a list of them;
packages do not matter.  The only thing you can specify with one
is what list to remove from.  Or let KEYWORDS be NIL and supply the
list name symbol as LIST-NAME."
  (DO ((L KEYWORDS (CDR L))
       KEYDEF V)
      ((NULL L))
    (SETQ V (SYMBOL-NAME (CAR L)))
    (IF (SETQ KEYDEF (ASS #'STRING= V INITIALIZATION-KEYWORDS))
	(SETQ LIST-NAME (CADR KEYDEF))
      (FERROR NIL "Illegal keyword ~S" (CAR L))))
  (INIT-LIST-CHECK LIST-NAME)
  (DO ((L (SYMBOL-VALUE LIST-NAME) (CDR L))
       (FLAG NIL))
      ((NULL L) FLAG)
      (WHEN (STRING= (INIT-NAME (CAR L)) NAME)
	(SET LIST-NAME (DELQ (CAR L) (SYMBOL-VALUE LIST-NAME)))
	(SETQ FLAG T))))

(DEFUN RESET-INITIALIZATIONS (LIST-NAME)
  "Mark all the inits in the initialization list named LIST-NAME as not yet run."
  (INIT-LIST-CHECK LIST-NAME)
  (DO ((L (SYMBOL-VALUE LIST-NAME) (CDR L)))
      ((NULL L))
    (SETF (INIT-FLAG (CAR L)) NIL)))

;;; This is an old name for FDEFINE which everyone uses.
(DEFUN FSET-CAREFULLY (FUNCTION-SPEC DEFINITION &OPTIONAL NO-QUERY-FLAG)
  "This is obsolete.  It is equivalent to (FDEFINE FUNCTION-SPEC
DEFINITION T FORCE-FLAG)."
  (FDEFINE FUNCTION-SPEC DEFINITION T NO-QUERY-FLAG))

;;; Simple version of FERROR to be used in the cold load environment.
(DEFUN FERROR-COLD-LOAD (&REST ARGS)
  (PRINT (SETQ * ARGS))
  (BREAK 'FERROR))

;;; Simple version of CERROR to be used in the cold load environment.
(DEFUN CERROR-COLD-LOAD (&REST ARGS)
  (PRINT (SETQ * ARGS))
  (BREAK 'CERROR))

(ADD-INITIALIZATION "Reset cold boot history" '(PUSH-NIL-ON-COLD-BOOT-HISTORY) '(:COLD))

;;; This is a function, since PUSH isn't loaded early enough
(DEFUN PUSH-NIL-ON-COLD-BOOT-HISTORY ()
  (PUSH 'NIL COLD-BOOT-HISTORY))

;;; Stuff which has to go somewhere, to be around in the cold-load,
;;; and doesn't have any logical place where it belongs

(DEFVAR USER-ID ""
  "String for the name you are logged in as, or an empty string if not logged in.")

;;; This is here rather than with the scheduler because it has to be
;;; in the cold-load.  It checks for the non-existence of a scheduler
;;; and does it itself in that case.

;;; Takes a predicate and arguments to it.  The process becomes blocked
;;; until the application of the predicate to those arguments returns T.
;;; Note that the function is run in the SCHEDULER stack group, not the
;;; process's stack group!  This means that bindings in effect at the
;;; time PROCESS-WAIT is called will not be in effect; don't refer to
;;; variables "freely" if you are binding them.
;;;    Kludge:  if the scheduler seems broken, or we ARE the scheduler
;;; (i.e. a clock function tries to block), then loop-wait (no blinkers...)

;;; In case of a process-level interrupt while waiting, this function can get
;;; restarted from its beginning.  Therefore, it must not modify its arguments,
;;; and the way it does its WITHOUT-INTERRUPTS must not be changed.
;;; See (:METHOD SI:PROCESS :INTERRUPT)
(DEFUN PROCESS-WAIT (WHOSTATE FUNCTION &REST ARGUMENTS)
  "Wait until FUNCTION applied to ARGUMENTS returns T.
WHOSTATE is a string to appear in Peek and the who-line until then.
Note that FUNCTION will be called in the scheduler stack group,
so your special variable bindings will not be available.
Pass whatever data or pointers you need in the ARGUMENTS."
  (COND ((APPLY FUNCTION ARGUMENTS)	;Test condition before doing slow stack-group switch
	 NIL)				;Hmm, no need to wait after all
	((AND SCHEDULER-EXISTS
	      (EQ SCHEDULER-STACK-GROUP %CURRENT-STACK-GROUP)
	      CURRENT-PROCESS)
	 ;; Called PROCESS-WAIT from a process's wait-function!
	 ;; Rather than hang the system, just say the process is not runnable now.
	 (THROW 'PROCESS-WAIT-IN-SCHEDULER NIL))
	((OR (NOT SCHEDULER-EXISTS)
	     (EQ SCHEDULER-STACK-GROUP %CURRENT-STACK-GROUP)
	     (NULL CURRENT-PROCESS)
	     (LET ((STATE (SG-CURRENT-STATE SCHEDULER-STACK-GROUP)))
	       (NOT (OR (= STATE SG-STATE-AWAITING-INITIAL-CALL)
			(= STATE SG-STATE-AWAITING-CALL)
			(= STATE SG-STATE-AWAITING-RETURN)))))
	 (DO-FOREVER
	   (AND (APPLY FUNCTION ARGUMENTS)
		(RETURN NIL))))
	(T
	 (WITHOUT-INTERRUPTS		;A sequence break would reset my state to "running"
	   (SETF (PROCESS-WAIT-WHOSTATE CURRENT-PROCESS) WHOSTATE)
	   (TV::WHO-LINE-PROCESS-CHANGE CURRENT-PROCESS)
	   (SET-PROCESS-WAIT CURRENT-PROCESS FUNCTION ARGUMENTS)
	   ;; DON'T change this FUNCALL to a STACK-GROUP-RESUME!  The scheduler
	   ;; needs to know what the process's current stack group is.
	   (FUNCALL SCHEDULER-STACK-GROUP))
	 (TV::WHO-LINE-PROCESS-CHANGE CURRENT-PROCESS))))

;;;; System initialization
(DEFVAR QLD-MINI-DONE NIL)

;;; Procedure for booting up a world load:
;;; 1. Use MINI to load CLPACK.  Create packages.
;;; 2. Use MINI to load kernel system, viz. FORMAT, flavors, processes, error handler,
;;;    chaos, QFILE.
;;; 3. Do a quasi cold boot.  This turns on the real file system.
;;; 4. Load MAKSYS and SYSDCL to build the initial systems.
;;; 5. Use MAKE-SYSTEM to load the rest of the top level system.
(DEFUN QLD (&OPTIONAL (LOAD-KEYWORDS '(:NOCONFIRM :NO-RELOAD-SYSTEM-DECLARATION))) ; :SILENT
  "Load the rest of the Lisp machine system into the cold load.
Used only if you are not generating a new Lisp machine system version."
; (SETQ AREA-FOR-PROPERTY-LISTS WORKING-STORAGE-AREA)	;Because will be recopied at end
  (COND ((NULL QLD-MINI-DONE)
	 (TERPRI)
	 (PRINC "Loading inner system")
	 (MINI-LOAD-FILE-ALIST INNER-SYSTEM-FILE-ALIST)
	 ;; Even though PATHNM is now loaded, it doesn't work yet.  So must disable
	 ;; FS:MAKE-FASLOAD-PATHNAME until it does.
	 (LETF (((SYMBOL-FUNCTION 'FS:MAKE-FASLOAD-PATHNAME) #'LIST))
	   (MINI-LOAD-FILE-ALIST REST-OF-PATHNAMES-FILE-ALIST)
	   (SELECT-PROCESSOR
	     (:LAMBDA (MINI-LOAD-FILE-ALIST ETHERNET-FILE-ALIST)))
	   ;; Read the site files.
	   ;; Now that QFILE is loaded, this will work properly.
	   (UPDATE-SITE-CONFIGURATION-INFO)	;Setup site dependent stuff
	   )
	 (LISP-REINITIALIZE)			;Turn on network, load error table, etc.
	 (LOGIN "LISPM" (SEND (FS:GET-PATHNAME-HOST "SYS") :PHYSICAL-HOST) T)
	 (FS:CANONICALIZE-COLD-LOAD-PATHNAMES)	;Update properties for real pathnames
	 ;; Load MAKE-SYSTEM so we can use it for the rest.
	 (DOLIST (F SYSTEM-SYSTEM-FILE-ALIST)
	   (LOAD (CAR F) (CADR F)))
	 (SETQ QLD-MINI-DONE T))
	(T (LOGIN "LISPM" T)))			;So that we can do file I/O
  (PRINC "Loading rest of world")
  ;; Make sure symbols that MAKSYS binds are set correctly
  (DOLIST (X '((COMPILER::COMPILER-WARNINGS-CONTEXT . NIL)
	       (TV:MORE-PROCESSING-GLOBAL-ENABLE . T)))
    (OR (BOUNDP (CAR X))
	(SET (CAR X) (CDR X))))
  (LET (TV:MORE-PROCESSING-GLOBAL-ENABLE)
    (APPLY #'MAKE-SYSTEM "System" LOAD-KEYWORDS)
    (DOLIST (SYSTEM (PROMPT-AND-READ :READ "List of names of additional systems to load:~%"))
      (APPLY #'MAKE-SYSTEM SYSTEM LOAD-KEYWORDS)))
; ;; Compactify property lists in the hopes of speeding up compilation
; (SETQ AREA-FOR-PROPERTY-LISTS PROPERTY-LIST-AREA)
  (MAPATOMS-ALL #'(LAMBDA (X) (SETF (PLIST X) (COPYLIST (PLIST X) PROPERTY-LIST-AREA))))

  (ANALYZE-ALL-FILES)

  (SETQ *IN-COLD-LOAD-P* NIL)
  (FORMAT T "~%Partition size ~D.~%" (ESTIMATE-DUMP-SIZE))
  (PRINT-DISK-LABEL)
  (FORMAT T "~%OK, now do a DISK-SAVE~%"))

;;; This is used for things like host tables which can get loaded again when the world
;;; is already built.
(DEFUN MAYBE-MINI-LOAD-FILE-ALIST (ALIST)
  (IF (NOT QLD-MINI-DONE)
      (MINI-LOAD-FILE-ALIST ALIST)
    (DOLIST (F ALIST)
      (LOAD (CAR F) (CADR F) NIL T))))

(DEFCONST SYSTEM-SYSTEM-FILE-ALIST
	  '(("SYS: SYS2; MAKSYS QFASL >" "SI")
	    ("SYS: SYS2; PATCH QFASL >" "SI")
	    ("SYS: SYS; SYSDCL QFASL >" "SI")))
