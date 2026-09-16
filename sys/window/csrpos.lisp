;-*- Mode:LISP; Package:TV; Base:8; Readtable:T -*-
;	** (c) Copyright 1980 Massachusetts Institute of Technology **

;For Maclisp compatibility
;No arguments returns (line . column)
;One argument does magic functions
;Two arguments sets cursorpos to there (args there of NIL mean don't change)
;Returns T if it succeeded, NIL if it didn't.
;Hmm, NEWIO seems to blow out rather than returning NIL now.  Change this?

;If the last argument is T (meaning *TERMINAL-IO*)
;or a stream, then it is applied to that stream.  Otherwise it is applied
;to *STANDARD-OUTPUT*.  Anything other than a number or a 1-character long
;symbol or NIL is assumed to be a stream.

(DEFUN CURSORPOS (&REST ARGS)
  (LET ((NARGS (LENGTH ARGS))
	(STREAM *STANDARD-OUTPUT*)
	ARG1 WO)
    (COND ((NULL ARGS))			;If any args, look for stream as 1st arg
	  ((EQ (SETQ ARG1 (CAR (LAST ARGS))) T) (SETQ STREAM *TERMINAL-IO* NARGS (1- NARGS)))
	  ((OR (NUMBERP ARG1) (NULL ARG1)))
	  ((OR (NOT (SYMBOLP ARG1)) (> (ARRAY-LENGTH (GET-PNAME ARG1)) 1))
	   (SETQ STREAM ARG1 NARGS (1- NARGS))))
    (SETQ ARG1 (CAR ARGS)
	  WO (SEND STREAM ':WHICH-OPERATIONS))
    (COND ((ZEROP NARGS)
	   (MULTIPLE-VALUE-BIND (X Y) (SEND STREAM :READ-CURSORPOS :CHARACTER)
	     (CONS Y X)))
	  ((> NARGS 2)
	   (FERROR NIL "Too many arguments"))	;Why bother signalling the correct condition?
	  ((OR (> NARGS 1) (NUMBERP ARG1))	;2 arguments or one numeric argument
	   (MULTIPLE-VALUE-BIND (X Y) (SEND STREAM :READ-CURSORPOS :CHARACTER)
	     (SEND STREAM :SET-CURSORPOS (OR (SECOND ARGS) X) (OR (FIRST ARGS) Y)
					 :CHARACTER)))
	  ((EQ (SETQ ARG1 (CHAR-UPCASE (CHAR (SYMBOL-NAME ARG1) 0))) #/F)
	   (CURSORPOS-INTERNAL STREAM +1 0 #/SPACE WO))	;F forward space
	  ((EQ ARG1 #/B)			;B backspace
	   (CURSORPOS-INTERNAL STREAM -1 0 #/OVERSTRIKE WO))
	  ((EQ ARG1 #/D)			;D down a line
	   (CURSORPOS-INTERNAL STREAM 0 +1 NIL WO))
	  ((EQ ARG1 #/U)			;U up a line
	   (CURSORPOS-INTERNAL STREAM 0 -1 NIL WO))
	  ((EQ ARG1 #/C)			;C clear screen
	   (IF (MEMQ ':CLEAR-WINDOW WO) (SEND STREAM :CLEAR-WINDOW)
	       (SEND STREAM :TYO #/PAGE))
	   T)
	  ((EQ ARG1 #/T)				;T top of screen
	   (IF (MEMQ ':HOME-CURSOR WO) (SEND STREAM :HOME-CURSOR)
	       (SEND STREAM ':TYO #/PAGE))
	   T)
	  ((EQ ARG1 #/E)				;E erase to end of screen
	   (WHEN (MEMQ ':CLEAR-REST-OF-WINDOW WO)
	     (SEND STREAM :CLEAR-REST-OF-WINDOW)
	     T))
	  ((EQ ARG1 #/L)				;L erase to end of line
	   (WHEN (MEMQ ':CLEAR-REST-OF-LINE WO)
	     (SEND STREAM ':CLEAR-REST-OF-LINE)
	     T))
	  ((EQ ARG1 #/K)				;K erase character
	   (WHEN (MEMQ ':CLEAR-CHAR WO)
	     (SEND STREAM :CLEAR-CHAR)
	     T))
	  ((EQ ARG1 #/X)				;X erase character backward
	   (CURSORPOS 'B STREAM)
	   (CURSORPOS 'K STREAM))
	  ((EQ ARG1 #/Z)				;Z home down
	   (IF (MEMQ ':HOME-DOWN WO)
	       (SEND STREAM :HOME-DOWN)
	     (SEND STREAM :FRESH-LINE))
	   T)
	  ((EQ ARG1 #/A)				;A fresh line
	   (SEND STREAM :FRESH-LINE)
	   T)
	  (T (FERROR NIL "~C not a recognized ~S option" ARG1 'CURSORPOS)))))

(DEFUN CURSORPOS-INTERNAL (STREAM DX DY ALTERNATE-CHARACTER WO)
  (COND ((MEMQ ':SET-CURSORPOS WO)
	 (MULTIPLE-VALUE-BIND (X Y) (SEND STREAM :READ-CURSORPOS :CHARACTER)
	   (SEND STREAM :SET-CURSORPOS (+ X DX) (+ Y DY) :CHARACTER)
	   T))
	((NOT (NULL ALTERNATE-CHARACTER))
	 (SEND STREAM :TYO ALTERNATE-CHARACTER)
	 T)
	(T NIL)))	;Or should it give an error?
