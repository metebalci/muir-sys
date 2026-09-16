;;; -*- Mode:LISP; Package:TV; Base:8; Readtable:ZL -*-
;;;	** (c) Copyright 1980, 1981 Massachusetts Institute of Technology **

(DEFMACRO COERCE-FONT (FONT-VARIABLE SHEET)
  `(UNLESS (TYPEP ,FONT-VARIABLE 'FONT)
     (SETQ ,FONT-VARIABLE (SEND (SHEET-GET-SCREEN ,SHEET) :PARSE-FONT-SPECIFIER
				,FONT-VARIABLE))))

(DEFUN SCREEN-REDISPLAY (&OPTIONAL (TYPE :COMPLETE-REDISPLAY) (SCREEN DEFAULT-SCREEN))
  "Redisplay the entire contents of SCREEN"
  (SEND SCREEN :REFRESH TYPE)
  (WHO-LINE-CLOBBERED))

(DEFMETHOD (SCREEN :BEEP) (&OPTIONAL BEEP-TYPE)
  "Beep the beeper."
  BEEP-TYPE  ;We wanted to make this soo hairy, that we punted until we could do it right
  (AND BEEP
       (WITHOUT-INTERRUPTS  ;otherwise might quit out and leave screen complemented
	 (OR (EQ BEEP :BEEP) (COMPLEMENT-BOW-MODE SELF))
	 (IF (EQ BEEP :FLASH)
	     (%BEEP 0 BEEP-DURATION)	;Delay same time without making any noise
	   (BEEP BEEP-TYPE 'IGNORE))
	 (OR (EQ BEEP :BEEP) (COMPLEMENT-BOW-MODE SELF)))))

(DEFMETHOD (SHEET :BEEP) (&OPTIONAL BEEP-TYPE)
  (AND SUPERIOR (SEND SUPERIOR :BEEP BEEP-TYPE)))

(DEFUN BEEP (&OPTIONAL BEEP-TYPE (STREAM *TERMINAL-IO*))
  "Ring the bell and flash the screen.
Works via the :BEEP operation on STREAM if STREAM supports it.
The value of BEEP controls what this function does:
 T means flash the screen and make noise,
 :BEEP means just make noise, :FLASH means just flash.
 NIL means do nothing.
BEEP-TYPE says why the beep is being done.  Standard values are:
 ZWEI::CONVERSE-PROBLEM -- Converse was unable to send a message.
 ZWEI::CONVERSE-MESSAGE-RECEIVED -- A Converse message has come in.
 ZWEI::NO-COMPLETION -- Completion in a minibuffer failed.
 TV:NOTIFY -- A notification cannot be printed on the selected window.
 SUPDUP::TERMINAL-BELL -- ``Bell'' received for terminal
 FQUERY -- When a question needs to be answered
 NIL -- anything else.
BEEP-TYPE does not have any effect, currently,
but you can redefine BEEP to to different things for different beep types."
  (WHEN BEEP
    (IF (OPERATION-HANDLED-P STREAM :BEEP)
	(SEND STREAM :BEEP BEEP-TYPE)
      (%BEEP BEEP-WAVELENGTH BEEP-DURATION))))


(DEFUN BLACK-ON-WHITE (&OPTIONAL (SCREEN DEFAULT-SCREEN))
  "Set SCREEN to display one bits as black and zeros as white."
  (SELECT-PROCESSOR
    (:CADR
     (%XBUS-WRITE (SCREEN-CONTROL-ADDRESS SCREEN)
		    (LOGIOR 4 (%XBUS-READ (SCREEN-CONTROL-ADDRESS SCREEN)))))
    (:LAMBDA
     (%NUBUS-WRITE TV:TV-QUAD-SLOT 4
		   (LOGIOR #o20 (%NUBUS-READ TV:TV-QUAD-SLOT 4))))))

(DEFUN WHITE-ON-BLACK (&OPTIONAL (SCREEN DEFAULT-SCREEN))
  "Set SCREEN to display one bits as white and zeros as black."
  (SELECT-PROCESSOR
    (:CADR
     (%XBUS-WRITE (SCREEN-CONTROL-ADDRESS SCREEN)
		  (LOGAND -5 (%XBUS-READ (SCREEN-CONTROL-ADDRESS SCREEN))))) ;1's comp of 4
    (:LAMBDA
     (%NUBUS-WRITE TV:TV-QUAD-SLOT 4
		   (LOGAND (LOGNOT #o20) (%NUBUS-READ TV:TV-QUAD-SLOT 4))))))

(DEFUN COMPLEMENT-BOW-MODE (&OPTIONAL (SCREEN DEFAULT-SCREEN))
  "Complement whether SCREEN displays one bits as white or as black."
  (SELECT-PROCESSOR
    (:CADR
     (%XBUS-WRITE (SCREEN-CONTROL-ADDRESS SCREEN)
		    (LOGXOR 4 (%XBUS-READ (SCREEN-CONTROL-ADDRESS SCREEN)))))
    (:LAMBDA
     (%NUBUS-WRITE TV:TV-QUAD-SLOT 4
		   (LOGXOR #o20 (%NUBUS-READ TV:TV-QUAD-SLOT 4))))))

(DEFMETHOD (SHEET :DRAW-RECTANGLE) (RECTANGLE-WIDTH RECTANGLE-HEIGHT X Y
				    &OPTIONAL (ALU CHAR-ALUF))
  (PREPARE-SHEET (SELF)
    (DRAW-RECTANGLE-INSIDE-CLIPPED RECTANGLE-WIDTH RECTANGLE-HEIGHT X Y ALU SELF)))


;;; Didn't handle top-overrun and left-overrun correctly
;;; For consistency, the two \'s below should be done by BITBLT itself  --TIM 10/84

(DEFMETHOD (SHEET :BITBLT) (ALU WID HEI FROM-ARRAY FROM-X FROM-Y TO-X TO-Y
				   &AUX (IL (SHEET-INSIDE-LEFT))
				        (IT (SHEET-INSIDE-TOP))
					(IW (SHEET-INSIDE-WIDTH))
					(IH (SHEET-INSIDE-HEIGHT)))
  (LET* ((ABS-WID (ABS WID))
	 (ABS-HEI (ABS HEI))
	 (LEFT-OVERRUN   (MAX 0 (- TO-X)))
	 (RIGHT-OVERRUN  (MAX 0 (- (+ TO-X ABS-WID) IW)))
	 (TOP-OVERRUN    (MAX 0 (- TO-Y)))
	 (BOTTOM-OVERRUN (MAX 0 (- (+ TO-Y ABS-HEI) IH)))
	 (CLIPPED-WID (* (IF (MINUSP WID) -1 1)
			 (MAX 0 (- ABS-WID LEFT-OVERRUN RIGHT-OVERRUN))))
	 (CLIPPED-HEI (* (IF (MINUSP HEI) -1 1)
			 (MAX 0 (- ABS-HEI TOP-OVERRUN BOTTOM-OVERRUN)))))
    (AND (NOT (ZEROP CLIPPED-WID))				;bitblt errs when w=h=0
	 (NOT (ZEROP CLIPPED-HEI))				;and dims are out of bounds
	 (PREPARE-SHEET (SELF)
	   (BITBLT ALU
		   CLIPPED-WID CLIPPED-HEI
		   FROM-ARRAY
		   (\ (+ FROM-X LEFT-OVERRUN) (PIXEL-ARRAY-WIDTH FROM-ARRAY))  
		   (\ (+ FROM-Y TOP-OVERRUN) (PIXEL-ARRAY-HEIGHT FROM-ARRAY))
		   SCREEN-ARRAY
		   (+ IL (MIN (MAX 0 TO-X) IW)) (+ IT (MIN (MAX 0 TO-Y) IH)))))))

(DEFMETHOD (SHEET :BITBLT-FROM-SHEET) (ALU WID HEI FROM-X FROM-Y TO-ARRAY TO-X TO-Y
					      &AUX (IL (SHEET-INSIDE-LEFT))
					           (IR (SHEET-INSIDE-RIGHT))
						   (IT (SHEET-INSIDE-TOP))
						   (IB (SHEET-INSIDE-BOTTOM)))
  (SETQ FROM-X (+ IL FROM-X) FROM-Y (+ IT FROM-Y))
  (LET* ((CLIPPED-FROM-X				
	   (MIN (MAX IL FROM-X) IR))
	 (CLIPPED-FROM-Y
	   (MIN (MAX IT FROM-Y) IB))
	 (WID-SIGN (IF (MINUSP WID) -1 1))
	 (HEI-SIGN (IF (MINUSP HEI) -1 1))
	 (LEFT-OVERRUN
	   (- CLIPPED-FROM-X FROM-X))
	 (RIGHT-OVERRUN
	   (MAX 0 (- (+ CLIPPED-FROM-X (ABS WID)) IR)))
	 (TOP-OVERRUN
	   (- CLIPPED-FROM-Y FROM-Y))
	 (BOTTOM-OVERRUN
	   (MAX 0 (- (+ CLIPPED-FROM-Y (ABS HEI)) IB)))
	 (CLIPPED-WID
	   (* WID-SIGN (MAX 0 (- (ABS WID) LEFT-OVERRUN RIGHT-OVERRUN))))
	 (CLIPPED-HEI
	   (* HEI-SIGN (MAX 0 (- (ABS HEI) TOP-OVERRUN BOTTOM-OVERRUN)))))

    (AND (NOT (ZEROP CLIPPED-WID))		;bitblt has this weird bug where it
	 (NOT (ZEROP CLIPPED-HEI))		;doesn't check to see if wid and hei are = 0
	 (PREPARE-SHEET (SELF)
	   (BITBLT ALU
		   CLIPPED-WID CLIPPED-HEI
		   SCREEN-ARRAY CLIPPED-FROM-X CLIPPED-FROM-Y
		   TO-ARRAY (+ TO-X LEFT-OVERRUN) (+ TO-Y TOP-OVERRUN))))))

(DEFMETHOD (SHEET :BITBLT-WITHIN-SHEET) (ALU WID HEI FROM-X FROM-Y TO-X TO-Y
						&AUX (IL (SHEET-INSIDE-LEFT))
					             (IR (SHEET-INSIDE-RIGHT))
						     (IT (SHEET-INSIDE-TOP))
						     (IB (SHEET-INSIDE-BOTTOM)))
  (SETQ FROM-X (+ IL FROM-X) FROM-Y (+ IT FROM-Y)
	TO-X (+ IL TO-X) TO-Y (+ IT TO-Y))
  (LET* ((CLIPPED-FROM-X
	   (MIN (MAX IL FROM-X) IR))		
	 (CLIPPED-FROM-Y
	   (MIN (MAX IT FROM-Y)	IB))		
	 (CLIPPED-TO-X
	   (MIN (MAX IL TO-X) IR))		
	 (CLIPPED-TO-Y
	   (MIN (MAX IT TO-Y) IB))         
	 (WID-SIGN (IF (MINUSP WID) -1 1))
	 (HEI-SIGN (IF (MINUSP HEI) -1 1))
	 (LEFT-OVERRUN
	   (MAX 0 (- CLIPPED-FROM-X FROM-X) (- CLIPPED-TO-X TO-X)))
	 (RIGHT-OVERRUN
	   (MAX 0 (- (+ CLIPPED-FROM-X (ABS WID)) IR) (- (+ CLIPPED-TO-X (ABS WID)) IR)))
	 (TOP-OVERRUN
	   (MAX 0 (- CLIPPED-FROM-Y FROM-Y) (- CLIPPED-TO-Y TO-Y)))
	 (BOTTOM-OVERRUN
	   (MAX 0 (- (+ CLIPPED-FROM-Y (ABS HEI)) IB) (- (+ CLIPPED-TO-Y (ABS HEI)) IB)))
	 (CLIPPED-WID
	   (* WID-SIGN (MAX 0 (- (ABS WID) LEFT-OVERRUN RIGHT-OVERRUN))))
	 (CLIPPED-HEI
	   (* HEI-SIGN (MAX 0 (- (ABS HEI) TOP-OVERRUN BOTTOM-OVERRUN)))))

    (AND (NOT (ZEROP CLIPPED-WID))
	 (NOT (ZEROP CLIPPED-HEI))
	 (PREPARE-SHEET (SELF)
	   (BITBLT ALU
		   CLIPPED-WID CLIPPED-HEI
		   SCREEN-ARRAY (+ FROM-X LEFT-OVERRUN) (+ FROM-Y TOP-OVERRUN)
		   SCREEN-ARRAY (+ TO-X LEFT-OVERRUN) (+ TO-Y TOP-OVERRUN))))))

(DEFMETHOD (SHEET :DRAW-CHAR) (FONT CHAR X-BITPOS Y-BITPOS &OPTIONAL (ALU CHAR-ALUF))
  (PREPARE-SHEET (SELF)
    (DRAW-CHAR FONT CHAR
	       (+ X-BITPOS LEFT-MARGIN-SIZE)
	       (+ Y-BITPOS TOP-MARGIN-SIZE)
	       ALU SELF)))

(DEFMETHOD (SHEET :INCREMENT-BITPOS) (DX DY)
  (SHEET-INCREMENT-BITPOS SELF DX DY))

(DEFUN SHEET-INCREMENT-BITPOS (SHEET DX DY &AUX X Y MORE-VPOS)
  "Increment cursor X and cursor Y, keeping within sheet.
Sets exception flags according to new positions"
  (SETF (SHEET-CURSOR-X SHEET)
	(SETQ X (MAX (+ DX (SHEET-CURSOR-X SHEET)) (SHEET-INSIDE-LEFT SHEET))))
  (SETF (SHEET-CURSOR-Y SHEET)
	(SETQ Y (MAX (+ DY (SHEET-CURSOR-Y SHEET)) (SHEET-INSIDE-TOP SHEET))))
  (AND (> (+ Y (SHEET-LINE-HEIGHT SHEET)) (SHEET-INSIDE-BOTTOM SHEET))
       (SETF (SHEET-END-PAGE-FLAG SHEET) 1))
  (AND (SETQ MORE-VPOS (SHEET-MORE-VPOS SHEET))
       ( Y MORE-VPOS)
       (SETF (SHEET-MORE-FLAG SHEET) 1))
  NIL)

(DEFUN SHEET-SET-FONT (SHEET FONT)
  "Set the current font of SHEET to FONT.
The current font is what ordinary output is printed in.
FONT may be a font object, a name of one, a name of a name, etc."
  (SEND SHEET :SET-CURRENT-FONT FONT T))

(DEFMETHOD (SHEET :SIZE-IN-CHARACTERS) ()
  (VALUES (TRUNCATE (SHEET-INSIDE-WIDTH) CHAR-WIDTH) (SHEET-NUMBER-OF-INSIDE-LINES)))

(DEFMETHOD (SHEET :SET-SIZE-IN-CHARACTERS) (WIDTH-IN-CHARS HEIGHT-IN-CHARS
							   &OPTIONAL OPTION)
   (SEND SELF :SET-SIZE
	      (DECODE-CHARACTER-WIDTH-SPEC WIDTH-IN-CHARS)
	      (DECODE-CHARACTER-HEIGHT-SPEC HEIGHT-IN-CHARS)
	      OPTION))

(DEFMETHOD (SHEET :SET-CURSORPOS) (X Y &OPTIONAL (UNIT :PIXEL))
  (CASE UNIT
    (:PIXEL)
    (:CHARACTER
      (AND X (SETQ X (* X CHAR-WIDTH)))
      (AND Y (SETQ Y (* Y LINE-HEIGHT))))
    (OTHERWISE
      (FERROR NIL "~S is not a known unit." UNIT)))
  (SHEET-SET-CURSORPOS SELF X Y))

(DEFUN SHEET-SET-CURSORPOS (SHEET X Y)
  "Set 'cursor' position of SHEET in terms of raster units.
The cursor is where ordinary output will appear
/(the top left corner of the next character).
Cursorposes are relative to the left and top margins.
The arguments are `clipped' to stay inside the sheet's margins."
  (DO ((INHIBIT-SCHEDULING-FLAG T T)  ;Keep trying until we get the lock
       (LOCK) (BL))
      ((AND (SETQ LOCK (SHEET-CAN-GET-LOCK SHEET))
	    (NOT (SHEET-OUTPUT-HELD-P SHEET)))
       (SETQ X (IF X (MIN (+ (MAX (FIX X) 0) (SHEET-INSIDE-LEFT SHEET))
			  (SHEET-INSIDE-RIGHT SHEET))
		   (SHEET-CURSOR-X SHEET)))
       (SETQ Y (IF Y (MIN (+ (MAX (FIX Y) 0) (SHEET-INSIDE-TOP SHEET))
			  (SHEET-INSIDE-BOTTOM SHEET))
		   (SHEET-CURSOR-Y SHEET)))
       (AND (= (SHEET-CURSOR-X SHEET) X) (= (SHEET-CURSOR-Y SHEET) Y)
	    (RETURN NIL))			;Not moving, don't open the blinker
       (AND (SETQ BL (SHEET-FOLLOWING-BLINKER SHEET))
	    (OPEN-BLINKER BL))
       (AND (SHEET-MORE-VPOS SHEET)		;If more processing enabled, delay until
						; bottom of sheet
	    (SETF (SHEET-MORE-VPOS SHEET) (SHEET-DEDUCE-MORE-VPOS SHEET)))
       (SETF (SHEET-CURSOR-X SHEET) X)
       (SETF (SHEET-CURSOR-Y SHEET) Y)
       (SETF (SHEET-EXCEPTIONS SHEET) 0)
       (AND (> (+ Y (SHEET-LINE-HEIGHT SHEET)) (SHEET-INSIDE-BOTTOM SHEET))
	    (SETF (SHEET-END-PAGE-FLAG SHEET) 1))
       T)
    (SETQ INHIBIT-SCHEDULING-FLAG NIL)
    (IF LOCK
	(SEND SHEET :OUTPUT-HOLD-EXCEPTION)
	(PROCESS-WAIT "Window Lock" #'SHEET-CAN-GET-LOCK SHEET))))

(DEFMETHOD (SHEET :INCREMENT-CURSORPOS) (DX DY &OPTIONAL (UNIT :PIXEL))
  (SELECTQ UNIT
    (:PIXEL)
    (:CHARACTER
     (AND DX (SETQ DX (- (* CHAR-WIDTH DX)
			 (NTH-VALUE 1 (CEILING (- CURSOR-X LEFT-MARGIN-SIZE) CHAR-WIDTH)))))
     (AND DY (SETQ DY (- (* LINE-HEIGHT DY)
			 (NTH-VALUE 1 (CEILING (- CURSOR-Y TOP-MARGIN-SIZE) LINE-HEIGHT))))))
    (OTHERWISE
      (FERROR NIL "~S is not a known unit." UNIT)))
  (PREPARE-SHEET (SELF)
    (OR (ZEROP (SHEET-EXCEPTIONS)) (SHEET-HANDLE-EXCEPTIONS SELF))
    (SHEET-INCREMENT-BITPOS SELF DX DY)))

(DEFMETHOD (SHEET :READ-CURSORPOS) (&OPTIONAL (UNIT :PIXEL))
  (SELECTQ UNIT
    (:PIXEL
     (VALUES (- CURSOR-X LEFT-MARGIN-SIZE)
	     (- CURSOR-Y TOP-MARGIN-SIZE)))
    (:CHARACTER
     (VALUES (CEILING (- CURSOR-X LEFT-MARGIN-SIZE) CHAR-WIDTH)
	     (CEILING (- CURSOR-Y TOP-MARGIN-SIZE) LINE-HEIGHT)))
    (OTHERWISE
     (FERROR NIL "~S is not a known unit." UNIT))))

(DEFUN SHEET-READ-CURSORPOS (SHEET)
  "Return the cursor position in raster units relative to margins"
  (DECLARE (VALUES CURSOR-X CURSOR-Y))
  (VALUES (- (SHEET-CURSOR-X SHEET) (SHEET-INSIDE-LEFT SHEET))
	  (- (SHEET-CURSOR-Y SHEET) (SHEET-INSIDE-TOP SHEET))))

(DEFMETHOD (SHEET :HOME-CURSOR) ()
  (SHEET-HOME SELF))

(DEFUN SHEET-HOME (SHEET)
  "Position SHEET's cursor to upper left corner (inside the margins)."
  (PREPARE-SHEET (SHEET)
    (AND (SHEET-MORE-VPOS SHEET)		;If MORE processing, put it off 'til last line
	 (SETF (SHEET-MORE-VPOS SHEET) (SHEET-DEDUCE-MORE-VPOS SHEET)))
    (SETF (SHEET-CURSOR-X SHEET) (SHEET-INSIDE-LEFT SHEET))
    (SETF (SHEET-CURSOR-Y SHEET) (SHEET-INSIDE-TOP SHEET))
    (SETF (SHEET-EXCEPTIONS SHEET) 0)))

(DEFMETHOD (SHEET :HOME-DOWN) ()
  (SHEET-SET-CURSORPOS SELF 0
		       (* (TRUNCATE (- (SHEET-INSIDE-HEIGHT) LINE-HEIGHT)
				     LINE-HEIGHT)
				 LINE-HEIGHT))
  (AND MORE-VPOS (SETQ MORE-VPOS (LOGIOR 100000 MORE-VPOS)))) ;Delay until next time

(DEFMETHOD (SHEET :TERPRI) ()
  (SHEET-CRLF SELF))

(DEFUN SHEET-CRLF (SHEET)
  "Move SHEET's cursor to beginning of next line, and clear the line."
  (PREPARE-SHEET (SHEET)
    (OR (ZEROP (SHEET-EXCEPTIONS SHEET))	;Handle exceptions first
	(SHEET-HANDLE-EXCEPTIONS SHEET))
    (SETF (SHEET-CURSOR-X SHEET) (SHEET-INSIDE-LEFT SHEET))
    (SHEET-INCREMENT-BITPOS SHEET 0 (SHEET-LINE-HEIGHT SHEET))
    (SHEET-CLEAR-EOL SHEET)))

(DEFMETHOD (SHEET :LINE-OUT) (STRING &OPTIONAL (START 0) END)
  (SEND SELF :STRING-OUT STRING START END)
  (SEND SELF :TERPRI))

(DEFMETHOD (SHEET :FRESH-LINE) ()
  (COND ((= CURSOR-X (SHEET-INSIDE-LEFT))
	 (SHEET-CLEAR-EOL SELF)
	 NIL)
	(T
	 (SHEET-CRLF SELF)
	 T)))

(DEFMETHOD (SHEET :CLEAR-CHAR) (&OPTIONAL CHAR)
  (SHEET-CLEAR-CHAR SELF CHAR))

(DEFUN SHEET-CLEAR-CHAR (SHEET &OPTIONAL CHAR)
  "Clear the character position SHEET's cursor points at.
CHAR may be a character whose width controls how wide an area to clear."
  (PREPARE-SHEET (SHEET)
    (OR (ZEROP (SHEET-EXCEPTIONS SHEET))
	(SHEET-HANDLE-EXCEPTIONS SHEET))
    (%DRAW-RECTANGLE (IF CHAR (SHEET-CHARACTER-WIDTH SHEET CHAR
						     (SHEET-CURRENT-FONT SHEET))
			      (SHEET-CHAR-WIDTH SHEET))
		     (SHEET-LINE-HEIGHT SHEET)
		     (SHEET-CURSOR-X SHEET) (SHEET-CURSOR-Y SHEET)
		     (SHEET-ERASE-ALUF SHEET) SHEET)))

(DEFMETHOD (SHEET :CLEAR-EOL) ()
  (SHEET-CLEAR-EOL SELF))
(compiler:make-obsolete :clear-eol
			":CLEAR-EOL is an obsolete window operation; use the :CLEAR-REST-OF-LINE")

(DEFMETHOD (SHEET :CLEAR-REST-OF-LINE) ()
  (SHEET-CLEAR-EOL SELF))

(DEFUN SHEET-CLEAR-EOL (SHEET)
  "Clear from SHEET's cursor to the right margin."
  (PREPARE-SHEET (SHEET)
    ;; Note that this need not handle **MORE** exception, because the **more**
    ;; would bash the line this is clearing anyway.  We don't want to **more**
    ;; if the next operation is going to be tyi.
    (OR (ZEROP (SHEET-END-PAGE-FLAG SHEET))
	(SHEET-HANDLE-EXCEPTIONS SHEET))
    (%DRAW-RECTANGLE (MAX (- (SHEET-INSIDE-RIGHT SHEET) (SHEET-CURSOR-X SHEET))
			  0)
		     (MIN (- (SHEET-INSIDE-BOTTOM SHEET) (SHEET-CURSOR-Y SHEET))
			  (SHEET-LINE-HEIGHT SHEET))
		     (SHEET-CURSOR-X SHEET) (SHEET-CURSOR-Y SHEET)
		     (SHEET-ERASE-ALUF SHEET) SHEET)))

(DEFMETHOD (SHEET :CLEAR-STRING) (STRING &OPTIONAL START END)
  (SHEET-CLEAR-STRING SELF STRING START END))

(DEFUN SHEET-CLEAR-STRING (SHEET STRING &OPTIONAL START END)
  "Clear enough space after SHEET's cursor to hold STRING, or part of it.
If STRING contains Return characters, we clear space on each line
to hold the characters of STRING on that line."
  (PREPARE-SHEET (SHEET)
    (OR (ZEROP (SHEET-EXCEPTIONS SHEET))
	(SHEET-HANDLE-EXCEPTIONS SHEET))
    (DO ((LINE-START (OR START 0))
	 (WHOLE-END (OR END (LENGTH STRING)))
	 (PSEUDO-CURSOR-X (SHEET-CURSOR-X SHEET)
			  (SHEET-INSIDE-LEFT SHEET))
	 (PSEUDO-CURSOR-Y (SHEET-CURSOR-Y SHEET)
			  (+ PSEUDO-CURSOR-Y LINE-HEIGHT))
	 MAXIMUM-X FINAL-INDEX
	 (LINE-HEIGHT (SHEET-LINE-HEIGHT SHEET))
	 (LINE-END))
	(())
      ;; Do vertical wrap around at bottom of sheet.
      (IF (>= (+ PSEUDO-CURSOR-Y LINE-HEIGHT) (SHEET-INSIDE-BOTTOM SHEET))
	  (SETQ PSEUDO-CURSOR-Y (SHEET-INSIDE-TOP SHEET)))
      ;; Find end of this line of the string.
      (SETQ LINE-END (OR (STRING-SEARCH-CHAR #/RETURN STRING LINE-START WHOLE-END)
			 WHOLE-END))
      ;; Does it fit in one screen-line?  If not, how much does?
      (MULTIPLE-VALUE-SETQ (NIL FINAL-INDEX MAXIMUM-X)
	(SHEET-STRING-LENGTH SHEET STRING LINE-START LINE-END
			     (SHEET-INSIDE-RIGHT SHEET)
			     (SHEET-CURRENT-FONT SHEET)
			     PSEUDO-CURSOR-X))
      ;; We only handle what fits in this screen-line.
      (IF (= FINAL-INDEX LINE-END)
	  (SETQ LINE-START (1+ LINE-END))
	(SETQ LINE-START FINAL-INDEX
	      MAXIMUM-X (SHEET-INSIDE-RIGHT SHEET)))
      ;; Clear that much.
      (%DRAW-RECTANGLE (- MAXIMUM-X PSEUDO-CURSOR-X)
		       LINE-HEIGHT
		       PSEUDO-CURSOR-X PSEUDO-CURSOR-Y
		       (SHEET-ERASE-ALUF SHEET) SHEET)
      ;; If entire specified portion of string is done, exit.
      (IF (>= LINE-START WHOLE-END) (RETURN NIL)))))

(DEFMETHOD (SHEET :CLEAR-BETWEEN-CURSORPOSES) (START-X START-Y END-X END-Y)
  (SHEET-CLEAR-BETWEEN-CURSORPOSES SELF START-X START-Y END-X END-Y))

(DEFUN SHEET-CLEAR-BETWEEN-CURSORPOSES (SHEET START-X START-Y END-X END-Y
					&AUX (ALUF (SHEET-ERASE-ALUF SHEET)) MID-Y)
  "Erase on SHEET from START-X, START-Y to END-X, END-Y.
All positions are relative to SHEET's margins.
Does nothing if start is after end on the same line,
but if on different lines, assumes screen wrap-around"
  (SETQ START-X (MIN (+ START-X (SHEET-INSIDE-LEFT SHEET)) (SHEET-INSIDE-RIGHT SHEET))
	START-Y (MIN (+ START-Y (SHEET-INSIDE-TOP SHEET)) (SHEET-INSIDE-BOTTOM SHEET))
	END-X (MIN (+ END-X (SHEET-INSIDE-LEFT SHEET)) (SHEET-INSIDE-RIGHT SHEET))
	END-Y (MIN (+ END-Y (SHEET-INSIDE-TOP SHEET)) (SHEET-INSIDE-BOTTOM SHEET)))
  (PREPARE-SHEET (SHEET)
    (COND ((= START-Y END-Y)
	   (COND ((< START-X END-X)
		  (%DRAW-RECTANGLE (- END-X START-X)
				   (MIN (- (SHEET-INSIDE-BOTTOM SHEET) START-Y)
					(SHEET-LINE-HEIGHT SHEET))
				   START-X START-Y ALUF SHEET))))
	  (T (%DRAW-RECTANGLE (- (SHEET-INSIDE-RIGHT SHEET) START-X) 
			      (MIN (- (SHEET-INSIDE-BOTTOM SHEET) START-Y)
				   (SHEET-LINE-HEIGHT SHEET))
			      START-X START-Y ALUF SHEET)
	     (SETQ MID-Y (+ START-Y (SHEET-LINE-HEIGHT SHEET)))
	     (%DRAW-RECTANGLE END-X (MIN (- (SHEET-INSIDE-BOTTOM SHEET) END-Y)
					 (SHEET-LINE-HEIGHT SHEET))
			      (SHEET-INSIDE-LEFT SHEET) END-Y ALUF SHEET)
	     (IF (< START-Y END-Y)
		 (AND (< MID-Y END-Y)
		      (%DRAW-RECTANGLE (SHEET-INSIDE-WIDTH SHEET) (- END-Y MID-Y)
				       (SHEET-INSIDE-LEFT SHEET) MID-Y ALUF SHEET))
		 (%DRAW-RECTANGLE (SHEET-INSIDE-WIDTH SHEET)
				  (- (SHEET-INSIDE-BOTTOM SHEET) MID-Y)
				  (SHEET-INSIDE-LEFT SHEET) MID-Y ALUF SHEET)
		 (%DRAW-RECTANGLE (SHEET-INSIDE-WIDTH SHEET)
				  (- END-Y (SHEET-INSIDE-TOP SHEET))
				  (SHEET-INSIDE-LEFT SHEET) (SHEET-INSIDE-TOP SHEET)
				  ALUF SHEET))))))

(DEFMETHOD (SHEET :CLEAR-SCREEN) ()
  (SHEET-CLEAR SELF))
(compiler:make-obsolete :clear-screen
			":CLEAR-SCREEN is an obsolete window operation, use the :CLEAR-WINDOW message")

(DEFMETHOD (SHEET :CLEAR-WINDOW) ()
  (SHEET-CLEAR SELF))

(DEFUN SHEET-CLEAR (SHEET &OPTIONAL (MARGINS-P NIL))
  "Erase all of SHEET.  If MARGINS-P, erase its margins too."
  (PREPARE-SHEET (SHEET)
    (SHEET-HOME SHEET)				;Handles any exceptions
    (IF MARGINS-P
	(%DRAW-RECTANGLE (SHEET-WIDTH SHEET) (SHEET-HEIGHT SHEET)
			 0 0
			 (SHEET-ERASE-ALUF SHEET) SHEET)
	(%DRAW-RECTANGLE (SHEET-INSIDE-WIDTH SHEET) (SHEET-INSIDE-HEIGHT SHEET)
			 (SHEET-INSIDE-LEFT SHEET) (SHEET-INSIDE-TOP SHEET)
			 (SHEET-ERASE-ALUF SHEET) SHEET))
    (SCREEN-MANAGE-FLUSH-KNOWLEDGE SHEET)))

(DEFMETHOD (SHEET :CLEAR-REST-OF-WINDOW) ()
  (SHEET-CLEAR-EOF SELF))

(DEFMETHOD (SHEET :CLEAR-EOF) ()
  (SHEET-CLEAR-EOF SELF))

(compiler:make-obsolete :clear-eof
			":CLEAR-REST-OF-WINDOW is an obsolete window operation, use the :CLEAR-EOF message")

(DEFUN SHEET-CLEAR-EOF (SHEET &AUX HT TEM)
  "Clear from SHEET's cursor to right margin, and all area below."
  (PREPARE-SHEET (SHEET)
    (OR (ZEROP (SHEET-EXCEPTIONS SHEET))
	(SHEET-HANDLE-EXCEPTIONS SHEET))
    (SHEET-CLEAR-EOL SHEET)
    (AND (PLUSP (SETQ HT (- (SHEET-INSIDE-BOTTOM SHEET)
			    (SETQ TEM (+ (SHEET-CURSOR-Y SHEET) (SHEET-LINE-HEIGHT SHEET))))))
	 (%DRAW-RECTANGLE (SHEET-INSIDE-WIDTH SHEET) HT
			  (SHEET-INSIDE-LEFT SHEET) TEM
			  (SHEET-ERASE-ALUF SHEET) SHEET))))

(DEFMETHOD (SHEET :INSERT-LINE) (&OPTIONAL (LINE-COUNT 1) (UNIT :CHARACTER))
  (SHEET-INSERT-LINE SELF LINE-COUNT UNIT))

(DEFUN SHEET-INSERT-LINE (SHEET &OPTIONAL (LINE-COUNT 1) (UNIT :CHARACTER))
  "Make room for some line before the line the cursor is currently on.
The data on this line and below is moved downward on the screen,
and that near the bottom of SHEET is discarded.
LINE-COUNT is how many lines to insert; default 1.
UNIT is :CHARACTER (the default) or :PIXEL, and says what unit
LINE-COUNT is expressed in.  :CHARACTER means it is multiplied
by the window's line-height."
  (PREPARE-SHEET (SHEET)
    (LET ((ARRAY (SHEET-SCREEN-ARRAY SHEET))
	  (WIDTH (SHEET-INSIDE-WIDTH SHEET))
	  (LINE-HEIGHT (SHEET-LINE-HEIGHT SHEET))
	  HEIGHT
	  DELTA-HEIGHT)
      (SETQ HEIGHT (IF (EQ UNIT :CHARACTER) (* LINE-COUNT LINE-HEIGHT) LINE-COUNT))
      ;; Compute minus height of block to BLT
      (SETQ DELTA-HEIGHT
	    (- HEIGHT (- (* LINE-HEIGHT (SHEET-NUMBER-OF-INSIDE-LINES SHEET))
			 (- (SHEET-CURSOR-Y SHEET) (SHEET-INSIDE-TOP SHEET)))))
      (OR ( DELTA-HEIGHT 0)			;If some bits to move, move them
	  (BITBLT ALU-SETA
		  WIDTH DELTA-HEIGHT
		  ARRAY (SHEET-INSIDE-LEFT SHEET) (SHEET-CURSOR-Y SHEET)
		  ARRAY (SHEET-INSIDE-LEFT SHEET) (+ (SHEET-CURSOR-Y SHEET) HEIGHT)))
      (%DRAW-RECTANGLE WIDTH HEIGHT
		       (SHEET-INSIDE-LEFT SHEET) (SHEET-CURSOR-Y SHEET)
		       (SHEET-ERASE-ALUF SHEET) SHEET))))

(DEFMETHOD (SHEET :DELETE-LINE) (&OPTIONAL (LINE-COUNT 1) (UNIT :CHARACTER))
  (SHEET-DELETE-LINE SELF LINE-COUNT UNIT))

(DEFUN SHEET-DELETE-LINE (SHEET &OPTIONAL (LINE-COUNT 1) (UNIT :CHARACTER))
  "Discard one or more lines starting at the cursor vpos, moving data below up.
Blank lines appear at the bottom of SHEET.
LINE-COUNT is how many lines to delete; default 1.
UNIT is :CHARACTER (the default) or :PIXEL, and says what unit
LINE-COUNT is expressed in.  :CHARACTER means it is multiplied
by the window's line-height."
  (PREPARE-SHEET (SHEET)
    (LET ((ARRAY (SHEET-SCREEN-ARRAY SHEET))
	  (WIDTH (SHEET-INSIDE-WIDTH SHEET))
	  (LINE-HEIGHT (SHEET-LINE-HEIGHT SHEET))
	  HEIGHT
	  DELTA-HEIGHT)
      (SETQ HEIGHT (IF (EQ UNIT :CHARACTER) (* LINE-COUNT LINE-HEIGHT) LINE-COUNT))
      (AND (PLUSP (SETQ DELTA-HEIGHT
			(- (+ (- (SHEET-CURSOR-Y SHEET) (SHEET-INSIDE-TOP SHEET)) HEIGHT)
			   (* LINE-HEIGHT (SHEET-NUMBER-OF-INSIDE-LINES SHEET)))))
	   (FERROR NIL "Illegal line-count ~S for ~S" LINE-COUNT SHEET))
      (BITBLT ALU-SETA WIDTH (- DELTA-HEIGHT)
	      ARRAY (SHEET-INSIDE-LEFT SHEET) (+ (SHEET-CURSOR-Y SHEET) HEIGHT)
	      ARRAY (SHEET-INSIDE-LEFT SHEET) (SHEET-CURSOR-Y SHEET))
      (%DRAW-RECTANGLE WIDTH HEIGHT
		       (SHEET-INSIDE-LEFT SHEET) (- (SHEET-CURSOR-Y SHEET) DELTA-HEIGHT)
		       (SHEET-ERASE-ALUF SHEET) SHEET))))

(DEFMETHOD (SHEET :INSERT-CHAR) (&OPTIONAL (-WIDTH- 1) (UNIT :CHARACTER))
  (SHEET-INSERT-CHAR SELF -WIDTH- UNIT))

(DEFUN SHEET-INSERT-CHAR (SHEET &OPTIONAL (WIDTH 1) (UNIT :CHARACTER))
  "Make room for characters at SHEET's cursor, moving rest of line right.
The last part of the line is discarded.  The cursorpos does not change.
If UNIT is :CHARACTER, WIDTH is a number of characters.
This is accurate only for fixed-width fonts.
Alternatively, WIDTH may be a number of pixels
if UNIT is :PIXEL."
  (PREPARE-SHEET (SHEET)
    (LET ((ARRAY (SHEET-SCREEN-ARRAY SHEET))
	  (LINE-HEIGHT (SHEET-LINE-HEIGHT SHEET))
	  (WIDTH (IF (EQ UNIT :PIXEL) WIDTH
		     (* WIDTH (SHEET-CHAR-WIDTH SHEET)))))
      (BITBLT ALU-SETA
	      (- WIDTH (- (SHEET-INSIDE-RIGHT SHEET) (SHEET-CURSOR-X SHEET)))
	      LINE-HEIGHT
	      ARRAY (SHEET-CURSOR-X SHEET) (SHEET-CURSOR-Y SHEET)
	      ARRAY (+ (SHEET-CURSOR-X SHEET) WIDTH) (SHEET-CURSOR-Y SHEET))
      (%DRAW-RECTANGLE WIDTH LINE-HEIGHT
		       (SHEET-CURSOR-X SHEET) (SHEET-CURSOR-Y SHEET)
		       (SHEET-ERASE-ALUF SHEET) SHEET))))

(DEFMETHOD (SHEET :DELETE-CHAR) (&OPTIONAL (-WIDTH- 1) (UNIT :CHARACTER))
  (SHEET-DELETE-CHAR SELF -WIDTH- UNIT))

(DEFUN SHEET-DELETE-CHAR (SHEET &OPTIONAL (WIDTH 1) (UNIT :CHARACTER))
  "Discard characters after SHEET's cursor, moving rest of line left.
Blank space is created near the right margin.
The cursor position does not change.
If UNIT is :CHARACTER, WIDTH is a number of characters.
This is accurate only for fixed-width fonts.
Alternatively, WIDTH may be a number of pixels
if UNIT is :PIXEL."
  (PREPARE-SHEET (SHEET)
    (LET ((ARRAY (SHEET-SCREEN-ARRAY SHEET))
	  (LINE-HEIGHT (SHEET-LINE-HEIGHT SHEET))
	  (WIDTH (IF (EQ UNIT :PIXEL) WIDTH
		     (* WIDTH (SHEET-CHAR-WIDTH SHEET)))))
      (BITBLT ALU-SETA
	      (- (SHEET-INSIDE-RIGHT SHEET) (SHEET-CURSOR-X SHEET) WIDTH)
	      LINE-HEIGHT
	      ARRAY (+ (SHEET-CURSOR-X SHEET) WIDTH) (SHEET-CURSOR-Y SHEET)
	      ARRAY (SHEET-CURSOR-X SHEET) (SHEET-CURSOR-Y SHEET))
      (%DRAW-RECTANGLE WIDTH LINE-HEIGHT
		       (- (SHEET-INSIDE-RIGHT SHEET) WIDTH)
		       (SHEET-CURSOR-Y SHEET)
		       (SHEET-ERASE-ALUF SHEET) SHEET))))

(DEFMETHOD (SHEET :INSERT-STRING) (STRING &OPTIONAL (START 0) END (TYPE-TOO T))
  (SHEET-INSERT-STRING SELF STRING START END TYPE-TOO))

(DEFUN SHEET-INSERT-STRING (SHEET STRING &OPTIONAL (START 0) END (TYPE-TOO T) &AUX LEN)
  "Make room for STRING after SHEET's cursor, moving rest of line right.
The last part of the line is discarded.  The cursorpos does not change.
If TYPE-TOO is non-NIL, STRING is output into the space
and the cursor is left after it."
  (SETQ LEN (IF (NUMBERP STRING)
		(SHEET-CHARACTER-WIDTH SHEET STRING (SHEET-CURRENT-FONT SHEET))
		(SHEET-STRING-LENGTH SHEET STRING START END)))
  (SHEET-INSERT-CHAR SHEET LEN :PIXEL)
  (AND TYPE-TOO (SHEET-STRING-OUT SHEET STRING START END)))

(DEFMETHOD (SHEET :DELETE-STRING) (STRING &OPTIONAL (START 0) END)
  (SHEET-DELETE-STRING SELF STRING START END))

(DEFUN SHEET-DELETE-STRING (SHEET STRING &OPTIONAL (START 0) END &AUX LEN)
  "Delete enough space for STRING, after SHEET's cursor.
The following part of the line moves left, creating blank space at the end.
The cursor position does not change."
  (SETQ LEN (IF (NUMBERP STRING)
		(SHEET-CHARACTER-WIDTH SHEET STRING (SHEET-CURRENT-FONT SHEET))
		(SHEET-STRING-LENGTH SHEET STRING START END)))
  (SHEET-DELETE-CHAR SHEET LEN :PIXEL))

(DEFMETHOD (SHEET :DISPLAY-LOZENGED-STRING) (STRING)
  (SHEET-DISPLAY-LOZENGED-STRING SELF STRING))

(DEFUN SHEET-DISPLAY-LOZENGED-STRING (SHEET STRING)
  "Display STRING on SHEET inside a lozenge.
This is how special characters with no graphic or formatting meaning are output."
  (SETQ STRING (STRING STRING))
  (LET ((WIDTH (LOZENGED-STRING-WIDTH STRING)))
    ;; Make sure there is enough room on the line, if not CRLF and
    ;; hope the sheet isn't too narrow.  Relies on the fact that handling
    ;; of all exceptions leaves you no further to the right than you were
    ;; (usually at the left margin).
    (PREPARE-SHEET (SHEET)
      (OR (ZEROP (SHEET-EXCEPTIONS SHEET))
	  (SHEET-HANDLE-EXCEPTIONS SHEET))
      (COND ((> (+ (SHEET-CURSOR-X SHEET) WIDTH)
		(IF (ZEROP (SHEET-RIGHT-MARGIN-CHARACTER-FLAG SHEET))
		    (SHEET-INSIDE-RIGHT SHEET)
		    (- (SHEET-INSIDE-RIGHT SHEET) (SHEET-CHAR-WIDTH SHEET))))
	     (SEND SHEET :END-OF-LINE-EXCEPTION)))
      (SETF (SHEET-CURSOR-X SHEET)
	    (SHEET-DISPLAY-LOZENGED-STRING-INTERNAL SHEET STRING
			(SHEET-CURSOR-X SHEET) (1+ (SHEET-CURSOR-Y SHEET))
			(SHEET-INSIDE-RIGHT SHEET) (SHEET-CHAR-ALUF SHEET))))))

(DEFUN LOZENGED-STRING-WIDTH (STRING)
  (+ 9. (* 6 (STRING-LENGTH STRING))))

(DEFUN SHEET-DISPLAY-LOZENGED-STRING-INTERNAL (SHEET STRING X0 Y0 XLIM ALUF)
  (LET* ((WIDTH (LOZENGED-STRING-WIDTH STRING))
	 TEM (TRUNCATED 8))
    (WHEN (MINUSP (SETQ TEM (- XLIM (+ WIDTH X0))))
      (SETQ TRUNCATED 4)
      (SETQ WIDTH (+ WIDTH TEM)))
    (IF (> WIDTH 4)
	;; Put the string then the box around it
	(LET ((X1 (+ X0 WIDTH -1))
	      (Y1 (+ Y0 8)))
	  (SHEET-STRING-OUT-EXPLICIT-1 SHEET STRING (+ X0 4) (+ Y0 2) X1 NIL
				       (SEND (SHEET-GET-SCREEN SHEET)
					     :PARSE-FONT-DESCRIPTOR FONTS:5X5)
				       ALUF)
	  (%DRAW-LINE X0 (+ Y0 4) (+ X0 3) (1+ Y0) ALUF T SHEET)
	  (%DRAW-LINE (1+ X0) (+ Y0 5) (+ X0 3) (1- Y1) ALUF T SHEET)
	  (WHEN (PLUSP (SETQ TEM (- WIDTH TRUNCATED)))
	    (%DRAW-RECTANGLE TEM 1 (+ X0 4) Y0 ALUF SHEET)
	    (%DRAW-RECTANGLE TEM 1 (+ X0 4) Y1 ALUF SHEET))
	  (WHEN (EQ TRUNCATED 8)
	    (%DRAW-LINE X1 (+ Y0 4) (- X1 3) (1+ Y0) ALUF T SHEET)
	    (%DRAW-LINE (1- X1) (+ Y0 5) (- X1 3) (1- Y1) ALUF T SHEET))
	  (1+ X1))
      XLIM)))

(DEFMETHOD (SHEET :TYO) (CH &OPTIONAL FONT)
  (SHEET-TYO SELF CH FONT)
  CH)

(DEFUN SHEET-TYO (SHEET CHAR &OPTIONAL FONT &AUX BASE-ADJ)
  "Output printing or formatting character CHAR on SHEET in FONT.
FONT defaults to the current font of SHEET.
Weird characters are printed in lozenges."
;character lossage
  (IF (CHARACTERP CHAR) (SETQ CHAR (CHAR-INT CHAR)))
  (CHECK-TYPE CHAR (INTEGER 0 (#o400)) "a character")
  (IF ( CHAR #o200)
      (COND ((AND (= CHAR #/NEWLINE) (ZEROP (SHEET-CR-NOT-NEWLINE-FLAG SHEET)))
             (SHEET-CRLF SHEET))
            ((= CHAR #/TAB)
             (SHEET-TAB-1 SHEET))
            ((AND (= CHAR #/BACKSPACE) (ZEROP (SHEET-BACKSPACE-NOT-OVERPRINTING-FLAG SHEET)))
             (SHEET-BACKSPACE-1 SHEET))
            (T
	     (SHEET-DISPLAY-LOZENGED-STRING SHEET
		(STRING (OR (CAR (RASSQ CHAR SI::XR-SPECIAL-CHARACTER-NAMES))
			    (FORMAT NIL "~3O" CHAR))))))
      (PREPARE-SHEET (SHEET)
        (OR (ZEROP (SHEET-EXCEPTIONS SHEET))
	    (SHEET-HANDLE-EXCEPTIONS SHEET))
	(COND (FONT
	       (COERCE-FONT FONT SHEET)
	       (SETQ BASE-ADJ (- (SHEET-BASELINE SHEET) (FONT-BASELINE FONT))))
	      (T
	       (SETQ FONT (SHEET-CURRENT-FONT SHEET)
		     BASE-ADJ (SHEET-BASELINE-ADJ SHEET))))
        (LET* ((CHAR-WIDTHS (FONT-CHAR-WIDTH-TABLE FONT))
	       (FIT (FONT-INDEXING-TABLE FONT))
	       (WIDTH)
	       (KERN 0)
	       (KERN-TABLE)
	       (XPOS (SHEET-CURSOR-X SHEET))
	       (RIGHT-LIM (SHEET-INSIDE-RIGHT SHEET)))
	  (OR (ZEROP (SHEET-RIGHT-MARGIN-CHARACTER-FLAG SHEET))
	      (SETQ RIGHT-LIM (- RIGHT-LIM (SHEET-CHAR-WIDTH SHEET))))
	  (SETQ WIDTH (IF CHAR-WIDTHS
			  (AREF CHAR-WIDTHS CHAR)
			  (FONT-CHAR-WIDTH FONT)))
	  (COND ((> (+ XPOS WIDTH) RIGHT-LIM)
		 (SEND SHEET :END-OF-LINE-EXCEPTION)
		 (SHEET-TYO SHEET CHAR FONT))
		(T
		 (AND (SETQ KERN-TABLE (FONT-LEFT-KERN-TABLE FONT))
		      (SETQ KERN (AREF KERN-TABLE CHAR)))
		 (COND ((NULL FIT)
			(%DRAW-CHAR FONT CHAR (- XPOS KERN)
				    (+ (SHEET-CURSOR-Y SHEET) BASE-ADJ)
				    (SHEET-CHAR-ALUF SHEET)
				    SHEET))
		       ;; Wide character, draw several columns
		       (T
			(DRAW-CHAR FONT CHAR (- XPOS KERN)
				   (+ (SHEET-CURSOR-Y SHEET) BASE-ADJ)
				   (SHEET-CHAR-ALUF SHEET)
				   SHEET)))
		 (SETF (SHEET-CURSOR-X SHEET) (+ XPOS WIDTH)))))))
  CHAR)

(DEFMETHOD (SHEET :BACKWARD-CHAR) (&OPTIONAL CHAR)
  (SHEET-BACKSPACE-1 SELF CHAR))

(DEFUN SHEET-BACKSPACE-1 (SHEET &OPTIONAL CHAR)
  (PREPARE-SHEET (SHEET)
    (OR (ZEROP (SHEET-EXCEPTIONS SHEET))
	(SHEET-HANDLE-EXCEPTIONS SHEET))
    (SHEET-INCREMENT-BITPOS SHEET
			    (- (IF CHAR (SHEET-CHARACTER-WIDTH SHEET CHAR
							       (SHEET-CURRENT-FONT SHEET))
					(SHEET-CHAR-WIDTH SHEET)))
			    0)))

(DEFUN SHEET-TAB-1 (SHEET)
  (PREPARE-SHEET (SHEET)
     (OR (ZEROP (SHEET-EXCEPTIONS SHEET)) (SHEET-HANDLE-EXCEPTIONS SHEET))
     (LET ((TAB-WIDTH (SHEET-TAB-WIDTH SHEET)))
       (SHEET-INCREMENT-BITPOS SHEET (- TAB-WIDTH (\ (- (SHEET-CURSOR-X SHEET)
							(SHEET-INSIDE-LEFT SHEET))
						     TAB-WIDTH))
			       0))))

(DEFMETHOD (SHEET :FORWARD-CHAR) (&OPTIONAL CHAR)
  (SHEET-SPACE SELF CHAR))

(DEFUN SHEET-SPACE (SHEET &OPTIONAL CHAR)
  "Move SHEET's cursor forward one character position.
Will move to a new line if necessary.
If CHAR is specified, that character's width is the distance to move."
  (PREPARE-SHEET (SHEET)
    (OR (ZEROP (SHEET-EXCEPTIONS SHEET))
	(SHEET-HANDLE-EXCEPTIONS SHEET))
    (SHEET-INCREMENT-BITPOS SHEET
			    (IF CHAR (SHEET-CHARACTER-WIDTH SHEET CHAR
							    (SHEET-CURRENT-FONT SHEET))
				     (SHEET-CHAR-WIDTH SHEET))
			    0)))

(DEFMETHOD (SHEET :STRING-OUT) (STRING &OPTIONAL (START 0) END)
  (SHEET-STRING-OUT SELF STRING START END))

(DEFUN SHEET-STRING-OUT (SHEET STRING &OPTIONAL (START 0) (END NIL))
  "Output STRING or portion on SHEET."
  (PREPARE-SHEET (SHEET)
    (AND (SYMBOLP STRING)		;Convert symbols to strings for output
	 (SETQ STRING (GET-PNAME STRING)))
    (PROG ((I START)
	   (N (OR END (ARRAY-ACTIVE-LENGTH STRING)))
	   (FONT (SHEET-CURRENT-FONT SHEET))
	   XPOS YPOS XLIM ALUF WIDTH CH FWT LKT)
       TOP
	  (AND ( I N) (RETURN NIL))		        ;No exception if done anyway
	  (AND (NULL (FONT-INDEXING-TABLE FONT))
	       (GO EZ))					;Handle easy case fast
       HD
	  (SHEET-TYO SHEET (CHAR-CODE (CHAR STRING I)))
	  (AND (< (SETQ I (1+ I)) N)
	       (GO TOP))
	  (RETURN NIL)

       EZ
	  (OR (ZEROP (SHEET-EXCEPTIONS SHEET))		;End of page, MORE
	      (SHEET-HANDLE-EXCEPTIONS SHEET))
	  (SETQ XPOS (SHEET-CURSOR-X SHEET)
		YPOS (+ (SHEET-CURSOR-Y SHEET) (SHEET-BASELINE-ADJ SHEET))
	        ALUF (SHEET-CHAR-ALUF SHEET)
		WIDTH (FONT-CHAR-WIDTH FONT)
		XLIM (SHEET-INSIDE-RIGHT SHEET))
	  (OR (ZEROP (SHEET-RIGHT-MARGIN-CHARACTER-FLAG SHEET))
	      (SETQ XLIM (- XLIM (SHEET-CHAR-WIDTH SHEET))))
	  (AND (OR (FONT-CHAR-WIDTH-TABLE FONT) (FONT-LEFT-KERN-TABLE FONT))
	       (GO VW))					;Variable-width is a little slower
       EZ1						;This is the fast loop
	  (SETQ CH (CHAR-CODE (CHAR STRING I)))
	  (COND ((< CH #o200)				;Printing char
		 (COND ((> (+ XPOS WIDTH) XLIM)		;Room for it before right margin?
			(SETF (SHEET-CURSOR-X SHEET) XPOS)
			(SEND SHEET :END-OF-LINE-EXCEPTION)
			(GO TOP)))
		 (%DRAW-CHAR FONT CH XPOS YPOS ALUF SHEET)
		 (SETQ XPOS (+ XPOS WIDTH))
		 (AND (< (SETQ I (1+ I)) N)
		      (GO EZ1))
		 (SETF (SHEET-CURSOR-X SHEET) XPOS)
		 (RETURN NIL))
		(T					;Format effector
		 (SETF (SHEET-CURSOR-X SHEET) XPOS)
		 (GO HD)))

       VW
	  (SETQ FWT (FONT-CHAR-WIDTH-TABLE FONT)	;This is the medium speed loop 
		 LKT (FONT-LEFT-KERN-TABLE FONT))
       VW1
	  (SETQ CH (CHAR-CODE (CHAR STRING I)))
	   (COND ((< CH #o200)				;Printing char
		  (AND FWT (SETQ WIDTH (AREF FWT CH)))
		  (COND ((> (+ WIDTH XPOS) XLIM)	;Room before margin?
			 (SETF (SHEET-CURSOR-X SHEET) XPOS)
			 (SEND SHEET :END-OF-LINE-EXCEPTION)
			 (GO TOP)))
		  (%DRAW-CHAR FONT CH (IF LKT (- XPOS (AREF LKT CH)) XPOS) YPOS ALUF SHEET)
		  (SETQ XPOS (+ XPOS WIDTH))
		  (AND (< (SETQ I (1+ I)) N)
		       (GO VW1))
		  (SETF (SHEET-CURSOR-X SHEET) XPOS)
		  (RETURN NIL))
		 (T					;Format effector
		  (SETF (SHEET-CURSOR-X SHEET) XPOS)
		  (GO HD))))))

(DEFMETHOD (SHEET :FAT-STRING-OUT) (STRING &OPTIONAL (START 0) END)
  (SHEET-FAT-STRING-OUT SELF STRING START END))

(DEFUN SHEET-FAT-STRING-OUT (SHEET STRING &OPTIONAL (START 0) END)
  (DO ((INDEX START)
       (STOP (OR END (STRING-LENGTH STRING)))
       (XPOS))
      (( INDEX STOP))
    (SETF (VALUES INDEX XPOS)
	  (SHEET-LINE-OUT SHEET STRING INDEX END))
    (SETF (SHEET-CURSOR-X SHEET) XPOS)
    (WHEN (> INDEX STOP)
      (SHEET-INCREMENT-BITPOS SELF 0 0)
      (RETURN NIL))
    (SHEET-CRLF SHEET)))

;;; Editor's line redisplay primitive, output STRING from START to END,
;;; first setting position to (SET-XPOS,SET-YPOS) and doing a clear-eol
;;; DWIDTH is a special hack for DIS-LINE redisplay of italic fonts, it means
;;; draw an extra character starting one character back, since the clear-eol
;;; will have erased part of the last character where it sticks out past its width.
;;; (If this can really happen, it's going to mean trouble with the margins, too!)
;;; This function never does more than one line; it stops rather than wrapping around.
;;; If you put a carriage return in the string, above may not be true.
;;; Where this leaves the sheet's actual cursorpos is undefined (somewhere on the line)

;;; This is NOT related to the :LINE-OUT operation!
(defun sheet-line-out (sheet string &optional (start 0) (stop nil)
					      set-xpos set-ypos dwidth (clear t))
  ;; Returns index of next character to do and where cursor got to except the first value can
  ;; be incremented, to show that the line was completed (as though it counted an implicit
  ;; carriage return).
  (declare (values index xpos))
  (let* ((inside-right (sheet-inside-right sheet))
	 (inside-left (sheet-inside-left sheet))
	 (margin-flag (not (zerop (sheet-right-margin-character-flag sheet))))
	 (xpos (if set-xpos (+ set-xpos inside-left) (sheet-cursor-x sheet)))
	 (ypos (if set-ypos (+ set-ypos (sheet-inside-top sheet))
		 (sheet-cursor-y sheet)))
	 (stop-index)
	 (stop-xpos))
  (prepare-sheet (sheet)
    (setq stop (or stop (array-active-length string)))
    (setf (sheet-cursor-y sheet) ypos)		;%DRAW-STRING depends on this in some cases.
;    (%draw-rectangle
;      (- inside-right xpos)
;      (sheet-line-height sheet)
;      xpos
;      ypos
;      (sheet-erase-aluf sheet)
;      sheet)
    (cond ((fixnump clear)
	   (if ( (+ inside-left clear) (- inside-right #o20))
	       (%draw-rectangle (- inside-right xpos) (sheet-line-height sheet)
				xpos ypos
				(sheet-erase-aluf sheet) sheet)
	       (%draw-rectangle (- (+ inside-left clear) xpos) (sheet-line-height sheet)
				xpos ypos
				(sheet-erase-aluf sheet) sheet)))
	  ((null clear))
	  (t
	   (%draw-rectangle (- inside-right xpos) (sheet-line-height sheet)
			    xpos ypos
			    (sheet-erase-aluf sheet) sheet)))
    (when dwidth				;Italic correction, back up one character.
      (setq xpos (- xpos dwidth))
      (decf start))
    (multiple-value-setq (stop-index stop-xpos)
      (%draw-string sheet (sheet-char-aluf sheet) xpos ypos string 0 start stop
		    (if margin-flag (- inside-right (sheet-char-width sheet)) inside-right)))
    (when (< stop-index stop)
      (when margin-flag (send sheet :tyo-right-margin-character stop-xpos ypos #/!)))
    (values stop-index (- stop-xpos inside-left)))))

(defun %draw-string (sheet alu xpos ypos string font start stop xlim)
  "Draw STRING on SHEET starting with the character at index START and stopping after
drawing the character at index STOP, presuming it all fits.  Output starts at XPOS,
YPOS on the sheet and continues until all appropriate characters are drawn, or until
the next character to be drawn would extend past XLIM.  The index of the next character
to be drawn, and the xpos where it would go are returned.  If a NEWLINE is encountered,
returns its index and xpos immediately.  The sheet's cursor position is ignored and
left unchanged."
  ;; Who says you can't write assembly code on the Lisp Machine?
  (declare (values index xpos))
  (prog (c (i start) width (tab-width (sheet-tab-width sheet)) (base-ypos ypos) (npos xpos)
	 font-index font-next (font-map (sheet-font-map sheet))
	 font-index-table font-width-table font-kern-table lozenge-string
	 (inside-left (sheet-inside-left sheet)))

	(cond (( i stop)
	       (return (values (1+ stop) xpos)))
	      ((neq (%p-mask-field-offset #.%%array-type-field string 0) art-string)
	       (go multiple-font)))

   single-font
	(when (fixnump font) (setq font (aref font-map font)))
	(setq ypos (+ ypos (- (sheet-baseline sheet) (font-baseline font))))
	(cond ((setq font-index-table (font-indexing-table font))
	       (setf (sheet-cursor-x sheet) xpos)
	       (go single-hairy-font-loop))
	      ((or (setq font-width-table (font-char-width-table font))
		   (setq font-kern-table (font-left-kern-table font)))
	       (setq width (font-char-width font))
	       (go single-variable-width-font-loop))
	      (t
	       (setq width (font-char-width font))
	       (go single-fixed-width-font-loop)))

   single-fixed-width-font-loop
	(when ( (setq c (char-int (char string i))) #o200)
	  (case c
	    (#.(char-int #/tab)     (go single-fixed-width-font-tab))
	    (#.(char-int #/newline) (return (values i npos)))
	    (otherwise (go single-fixed-width-font-hard))))
   single-fixed-width-font-char
	(when (> (setq npos (+ (setq xpos npos) width)) xlim)
	  (return (values i xpos)))
	(%draw-char font c xpos ypos alu sheet)
	(when (eq (incf i) stop)
	  (return (values (1+ stop) npos)))
	(if (< (setq c (char-int (char string i))) #o200)
	    (go single-fixed-width-font-char)
	  (case c
	    (#.(char-int #/tab)     (go single-fixed-width-font-tab))
	    (#.(char-int #/newline) (return (values i npos)))
	    (otherwise (go single-fixed-width-font-hard))))
   single-fixed-width-font-tab
	(setq npos (+ (* (truncate (+ (setq xpos npos) tab-width) tab-width)
			 tab-width)
		      inside-left))
	(cond ((> npos xlim)
	       (return (values i xpos)))
	      ((eq (incf i) stop)
	       (return (values (1+ stop) npos)))
	      (t (go single-fixed-width-font-loop)))
   single-fixed-width-font-hard
	(setq lozenge-string (or (car (rassq c si::xr-special-character-names))
				 (format nil "~O" c)))
	(setq npos (+ (setq xpos npos) (lozenged-string-width lozenge-string)))
	(when (> npos xlim)
	  (return (values i xpos)))
	(setf (sheet-cursor-x sheet) xpos)
	(sheet-display-lozenged-string sheet lozenge-string)
	(if (eq (incf i) stop)
	    (return (values (1+ stop) npos))
	  (go single-fixed-width-font-loop))

   single-variable-width-font-loop
	(when ( (setq c (char-int (char string i))) #o200)
	  (case c
	    (#.(char-int #/tab)     (go single-variable-width-font-tab))
	    (#.(char-int #/newline) (return (values i npos)))
	    (otherwise (go single-variable-width-font-hard))))
   single-variable-width-font-char
        (when (> (setq npos (+ (setq xpos npos)
			       (if font-width-table (aref font-width-table c) width))) xlim)
	  (return (values i xpos)))
	(if font-kern-table
	    (%draw-char font c (- xpos (aref font-kern-table c)) ypos alu sheet)
	  (%draw-char font c xpos ypos alu sheet))
	(if (eq (incf i) stop)
	    (return (values (1+ stop) npos))
	  (go single-variable-width-font-loop))
   single-variable-width-font-tab
	(setq npos (+ (* (truncate (+ (setq xpos npos) tab-width) tab-width)
			 tab-width)
		      inside-left))
	(cond ((> npos xlim)
	       (return (values i xpos)))
	      ((eq (incf i) stop)
	       (return (values (1+ stop) npos)))
	      (t (go single-variable-width-font-loop)))
   single-variable-width-font-hard
	(setq lozenge-string (or (car (rassq c si:xr-special-character-names))
				 (format nil "~O" c)))
	(setq npos (+ (setq xpos npos) (lozenged-string-width lozenge-string)))
	(when (> npos xlim)
	  (return (values i xpos)))
	(setf (sheet-cursor-x sheet) xpos)
	(sheet-display-lozenged-string sheet lozenge-string)
	(if (eq (incf i) stop)
	    (return (values (1+ stop) npos))
	  (go single-variable-width-font-loop))

   single-hairy-font-loop
	(setq width (sheet-character-width sheet (setq c (char-int (char string i))) font))
	(when (> (+ (sheet-cursor-x sheet) width) xlim)
	  (return (values i (sheet-cursor-x sheet))))
	(sheet-tyo sheet c font)
	(if (eq (incf i) stop)
	    (return (values (1+ stop) (sheet-cursor-x sheet)))
	  (go single-hairy-font-loop))

   multiple-font
	(setq font-next (char-font (setq c (char string i))))
   multiple-font-main-loop-font-changed
	(setq font (aref font-map (setq font-index font-next)))
	(setq font-index-table (font-indexing-table font))
	(setq font-width-table (font-char-width-table font))
	(setq font-kern-table (font-left-kern-table font))
	(setq width (font-char-width font))
	(setq ypos (+ base-ypos (- (sheet-baseline sheet) (font-baseline font))))
   multiple-font-main-loop-font-unchanged
	(when ( (setq c (char-code c)) #o200)
	  (go multiple-font-special-character))

   multiple-font-graphic-character
	(when (> (setq npos (+ (setq xpos npos)
			       (if font-width-table (aref font-width-table c) width)))
		 xlim)
	  (return (values i xpos)))
	(when (null font-index-table)
	  (if font-width-table
	      (if font-kern-table
		  (go multiple-font-variable-width-with-kerning-loop-short-cut)
		(go multiple-font-variable-width-loop-short-cut))
	    (go multiple-font-fixed-width-loop-short-cut)))
	(setf (sheet-cursor-x sheet) xpos)	;Must transmit latest position.
	(sheet-tyo sheet c font)		;Indexed character (wider than 32 bits).
	(go multiple-font-loop-tail)

   multiple-font-special-character
	(case c
	  (#.(char-int #/tab)
	   (when (> (setq npos (+ (setq xpos npos)
				  (- tab-width
				     (\ (- xpos inside-left)
					tab-width))))
		    xlim)
	     (return (values i xpos))))
	  (#.(char-int #/newline)
	   (return (values i (setq xpos npos))))
	  (otherwise
	   (setq lozenge-string (or (car (rassq c si::xr-special-character-names))
				    (format nil "~O" c)))
	   (when (> (setq npos (+ (setq xpos npos)
				  (lozenged-string-width lozenge-string)))
		    xlim)
	     (return (values i xpos)))
	   (setf (sheet-cursor-x sheet) xpos)
	   (sheet-display-lozenged-string sheet lozenge-string)))

   multiple-font-loop-tail
	(cond ((eq (incf i) stop)
	       (return (values (1+ stop) npos)))
	      ((eq (setq font-next (char-font (setq c (char string i)))) font-index)
	       (go multiple-font-main-loop-font-unchanged))
	      (t
	       (go multiple-font-main-loop-font-changed)))
	
   multiple-font-fixed-width-loop
	(cond (( (setq c (char-code c)) #o200)
	       (go multiple-font-special-character))
	      ((> (setq npos (+ (setq xpos npos) width))
		  xlim)
	       (return (values i xpos))))
   multiple-font-fixed-width-loop-short-cut
	(%draw-char font c xpos ypos alu sheet)
	(cond ((eq (incf i) stop)
	       (return (values (1+ stop) npos)))
	      ((eq (setq font-next (char-font (setq c (char string i)))) font-index)
	       (go multiple-font-fixed-width-loop))
	      (t
	       (go multiple-font-main-loop-font-changed)))

   multiple-font-variable-width-loop
	(cond (( (setq c (char-code c)) #o200)
	       (go multiple-font-special-character))
	      ((> (setq npos (+ (setq xpos npos)
				(if font-width-table (aref font-width-table c) width)))
		  xlim)
	       (return (values i xpos))))
   multiple-font-variable-width-loop-short-cut
	(%draw-char font c xpos ypos alu sheet)
	(cond ((eq (incf i) stop)
	       (return (values (1+ stop) npos)))
	      ((eq (setq font-next (char-font (setq c (char string i)))) font-index)
	       (go multiple-font-variable-width-loop))
	      (t
	       (go multiple-font-main-loop-font-changed)))

   multiple-font-variable-width-with-kerning-loop
	(cond (( (setq c (char-code c)) #o200)
	       (go multiple-font-special-character))
	      ((> (setq npos (+ (setq xpos npos)
				(if font-width-table (aref font-width-table c) width)))
		  xlim)
	       (return (values i xpos))))
   multiple-font-variable-width-with-kerning-loop-short-cut
	(%draw-char font c (- xpos (aref font-kern-table c)) ypos alu sheet)
	(cond ((eq (incf i) stop)
	       (return (values (1+ stop) npos)))
	      ((eq (setq font-next (char-font (setq c (char string i)))) font-index)
	       (go multiple-font-variable-width-with-kerning-loop))
	      (t
	       (go multiple-font-main-loop-font-changed)))))


(DEFMETHOD (SHEET :COMPUTE-MOTION) (STRING &OPTIONAL (START 0) END X Y &REST ARGS)
  (APPLY #'SHEET-COMPUTE-MOTION SELF X Y STRING START END ARGS))

(DEFCONST PRINTING-CHARACTER-TRANSLATE-TABLE
	  (MAKE-ARRAY #o200 :INITIAL-ELEMENT 1))
  
;; Change to T to fix the bug
;; that we stop after a character that goes across STOP-X
;; though we ought to stop before it.
;; Should not turn on the fix until the callers are changed to match.
;; If indeed the change really should be made.
(DEFCONST COMPUTE-MOTION-ROUND-DOWN NIL)

(DEFUN SHEET-COMPUTE-MOTION (SHEET X Y STRING
			     &OPTIONAL (START 0) (END NIL) (CR-AT-END-P NIL)
				       (STOP-X 0) (STOP-Y NIL) BOTTOM-LIMIT RIGHT-LIMIT
				       FONT
				       (LINE-HT (IF FONT (FONT-CHAR-HEIGHT FONT)
						  (SHEET-LINE-HEIGHT SHEET)))
				       (TAB-WIDTH
					 (IF FONT (* (FONT-CHAR-WIDTH FONT)
						     (SHEET-TAB-NCHARS SHEET))
					   (SHEET-TAB-WIDTH SHEET))))
  "Compute the motion that would be caused by outputing a string.
This is used by the editor and by TV:STREAM-MIXIN.
In computing the motion, it will chose the font in one of two ways:
 If given an ART-FAT-STRING array (16 bit string) like the editor uses,
  it will take the font from the character's CHAR-FONT and look in
  SHEET's font-map.
 If given an ART-STRING array (8 bit string), it will take the font from
  FONT, or the SHEET-CURRENT-FONT of the sheet.
SHEET is used to supply information such as the font map,
 and for defaulting such things as BOTTOM-LIMIT, RIGHT-LIMIT
 and LINE-HT.
STRING, with START and END, specifies what characters to process.
CR-AT-END-P if non-NIL says /"output/" a Newline after
 STRING or the portion of STRING, and count that
 in the cursor motion.
STOP-X and STOP-Y specify a cursor position at which to stop.
 Processing stops when both coordinates are  the stop points.
 The stop points default to the bottom left corner of SHEET.
 Specify a very large value for STOP-Y if you do not
 want processing to stop before the end of STRING.
BOTTOM-LIMIT and RIGHT-LIMIT are a cursor position
 at which to wrap around; these default to
 the inside-size of SHEET.
FONT specifies the font to use, if STRING is not a fat string.
LINE-HT is the line height to use for Newline characters,
 defaulting to SHEET's line height.
TAB-WIDTH is the width to use for Tab characters,
 defaulting to SHEET's SHEET-TAB-WIDTH.

Processing stops either because the string or portion has
been processed or because the stopping-point has been reached.

Returns 4 values:
FINAL-X, FINAL-Y are the cursor position
 at which processing stopped.
FINAL-STRING-INDEX is the index
 in the string at which processing stopped (could be the length
 of the string, if the stop point was passed then), T if stopped
 due to reaching the stop point after the additional Newline,
 or NIL if stopped due to finishing.
MAXIMUM-X was the largest X-position ever encountered during processing."

; *** The interface to this crock should be redesigned.  Also note that the
; *** exact treatment of STOP-X and STOP-Y does not agree with SHEET-STRING-LENGTH.
; *** This is what turning on COMPUTE-MOTION-ROUND-DOWN is going to fix.
  (DECLARE (VALUES FINAL-X FINAL-Y FINAL-STRING-INDEX MAXIMUM-X))
  (IF FONT
      (COERCE-FONT FONT SHEET)
      (SETQ FONT (SHEET-CURRENT-FONT SHEET)))
  (PROG (CWA CW CH FONTX TEM I N NN II MARGIN-FLAG MAXIMUM-X OLD-X)
	(OR (ZEROP (SHEET-RIGHT-MARGIN-CHARACTER-FLAG SHEET)) (SETQ MARGIN-FLAG T))
	(AND (NULL X) (SETQ X (- (SHEET-CURSOR-X SHEET) (SHEET-INSIDE-LEFT SHEET))))
	(AND (NULL Y) (SETQ Y (- (SHEET-CURSOR-Y SHEET) (SHEET-INSIDE-TOP SHEET))))
	(AND (NULL STOP-Y)
	     (SETQ STOP-Y (1+ (SHEET-INSIDE-HEIGHT SHEET))))
	;;		   ^-- THIS 1+ IS SO CAN USE  RATHER THAN >
	(OR RIGHT-LIMIT (SETQ RIGHT-LIMIT (SHEET-INSIDE-WIDTH SHEET)))
	(AND MARGIN-FLAG (SETQ RIGHT-LIMIT (- RIGHT-LIMIT (SHEET-CHAR-WIDTH SHEET))))
	(AND (NULL BOTTOM-LIMIT)
	     (SETQ BOTTOM-LIMIT (- (SHEET-INSIDE-HEIGHT SHEET) LINE-HT)))
	(SETQ MAXIMUM-X X
	      I START
	      N (OR END (ARRAY-ACTIVE-LENGTH STRING))
	      CW (FONT-CHAR-WIDTH FONT))
	;; At this point, decide whether we can use the fast version.
	(COND
	  ;; If FONTX is non-NIL, then we have a string with font changes.
	  ((NEQ 8 (CDR (ASSQ (ARRAY-TYPE STRING) ARRAY-BITS-PER-ELEMENT)))
	   (SETQ FONTX T))
	  ;; The current font is variable width.
	  ((SETQ CWA (FONT-CHAR-WIDTH-TABLE FONT)))
	  ;; No font changes and the current font is fixed width.
	  ;;  We can use the fast version.
	  (T (GO FAST)))
	;;This is the slow version.
     SLOW
	(SETQ MAXIMUM-X (MAX X MAXIMUM-X))
	(COND ((AND ( Y STOP-Y) ( X STOP-X))	;Reached sticking-point
	       (RETURN (VALUES X Y
			       I MAXIMUM-X)))
	      ((NOT (< I N))			;If string exhausted
	       (WHEN CR-AT-END-P
		 (SETQ X 0 Y (+ Y LINE-HT))	;CRLF if told to
		 (AND (> Y BOTTOM-LIMIT) (SETQ Y 0)))
	       (RETURN (VALUES X Y
			       (AND ( X STOP-X) ( Y STOP-Y)) MAXIMUM-X))))
	;; Move quickly over the remaining characters until we reach
	;; an x-position at which something must be done.
	(UNLESS (EQ FONTX T)
	  (LET ((WIDTH-INCR)
		(LIMIT (MIN RIGHT-LIMIT (IF ( Y STOP-Y) STOP-X RIGHT-LIMIT))))
	    (SETQ WIDTH-INCR
		  (%STRING-WIDTH (OR CWA
				     PRINTING-CHARACTER-TRANSLATE-TABLE)
				 (IF FONTX (DPB FONTX %%CH-FONT 0) 0)
				 STRING I N
				 (IF CWA (- LIMIT X) (FLOOR (- LIMIT X) CW))))
	    (UNLESS CWA
	      (SETQ WIDTH-INCR (* WIDTH-INCR CW)))
	    (SETQ I (%POP))
	    ;; increment positions.
	    (INCF X WIDTH-INCR)
	    ;; At end of string, loop back, to exit.
	    (IF (= I N) (GO SLOW))
	    ;; Otherwise we stopped due to funny char or font change or reaching the X limit.
	    ))
	(SETQ MAXIMUM-X (MAX X MAXIMUM-X))
	(WHEN (AND ( Y STOP-Y) ( X STOP-X))	;If reached sticking-point, done.
	  (RETURN (VALUES X Y
			  I MAXIMUM-X)))
	(SETQ CH (CHAR-CODE (SETQ TEM (CHAR STRING I))))
	(WHEN (AND FONTX (NEQ (SETQ TEM (CHAR-FONT TEM)) FONTX))	;Changing fonts
	  (SETQ FONTX TEM
		FONT (LET ((FONT-MAP (SHEET-FONT-MAP SHEET)))
		       (AREF FONT-MAP (IF ( FONTX (ARRAY-ACTIVE-LENGTH FONT-MAP))
					  0 FONTX)))
		CWA (FONT-CHAR-WIDTH-TABLE FONT)
		CW (FONT-CHAR-WIDTH FONT)))
	(SETQ OLD-X X)
	;; Try to do this one char.
	(COND ((= CH #/NEWLINE)
	       (SETQ X 0 Y (+ Y LINE-HT))
	       (AND (> Y BOTTOM-LIMIT) (SETQ Y 0)))
	      ((< CH #o200)			;Printing character
	       (SETQ X (+ (COND (CWA (AREF CWA CH)) (T CW)) X)))	;do char width
	      ((= CH #/TAB)			;Tab (have to do here since x-dependent)
	       (SETQ TEM TAB-WIDTH)
	       (SETQ X (* (TRUNCATE (+ X TEM) TEM) TEM)))
	      (T				;Format effector
	       (SETQ X (MAX (+ X (SHEET-CHARACTER-WIDTH SHEET CH FONT)) 0))))
	;; If this char went past the stop-point, pretend we stopped before it.
	(WHEN (AND COMPUTE-MOTION-ROUND-DOWN
		   (> X STOP-X) ( Y STOP-Y))
	  (RETURN (VALUES OLD-X Y
			  I MAXIMUM-X)))
	;; If this char went past the right margin, do a CR, then redo this char
	(COND ((> X RIGHT-LIMIT)
	       (SETQ X 0 Y (+ Y LINE-HT))
	       (AND (> Y BOTTOM-LIMIT) (SETQ Y 0)))
	      (T (INCF I)))
	(GO SLOW)

	;;Here is the fast loop.  The basic idea is to scan as fast as possible
	;;over printing characters, with all checking outside the loop.
     FAST 
	(SETQ MAXIMUM-X (MAX X MAXIMUM-X))
	;;First, decide the most characters we want to scan over in a whack
	(SETQ NN
	      (MIN (1+ (TRUNCATE (- (IF ( Y STOP-Y)	;Stop-point is in this line
				        STOP-X
				        RIGHT-LIMIT)	;Stop for this line is margin
				    X)
				 CW))
		   N))				;NN is limiting value of I
	;; Now, scan over printing characters.
	(WHEN ( (SETQ II I) NN)		;Save initial I, and check for null loop
	  (GO SCX))
     SCN
	(%STRING-WIDTH PRINTING-CHARACTER-TRANSLATE-TABLE
		       0 STRING II NN NIL)
	(SETQ I (%POP))
;       (SETQ TEM #o200)			;This is really a ridiculous bum
;    SCN
;	(AND (< (AREF STRING I) TEM)		;If this is a printing character
;	     (< (SETQ I (1+ I)) NN)		; and we haven't reached stop point
;	     (GO SCN))				; then continue to loop (9 instructions)
	(SETQ X (+ (* (- I II) CW) X))		;Account for the motion of those chars

     SCX
	(SETQ NN X)
	(SETQ MAXIMUM-X (MAX X MAXIMUM-X))
	(COND ((AND ( Y STOP-Y) ( X STOP-X))	;If reached sticking-point, done.
	       (RETURN (VALUES X Y
			       I MAXIMUM-X)))
	      ((NOT (< I N))			;If string exhausted
	       (WHEN CR-AT-END-P		;Do Newline X off end of line
		 (SETQ X 0 Y (+ Y LINE-HT))	;crlf if told to
		 (AND (> Y BOTTOM-LIMIT) (SETQ Y 0)))
	       (RETURN (VALUES X Y
			       (AND ( X STOP-X) ( Y STOP-Y)) MAXIMUM-X))))
	(SETQ OLD-X X)
	;; Try to do this one char.
	(COND ((= (SETQ CH (CHAR STRING I)) #/CR)
	       (SETQ X 0 Y (+ Y LINE-HT))
	       (AND (> Y BOTTOM-LIMIT) (SETQ Y 0)))
	      ((< CH #o200)			;Printing character
	       (INCF X CW))
	      ((= CH #/TAB)			;Tab (have to do here since x-dependent)
	       (SETQ TEM TAB-WIDTH)
	       (SETQ X (* (TRUNCATE (+ X TEM) TEM) TEM)))
	      (T				;Format effector
	       (SETQ X (MAX (+ X (SHEET-CHARACTER-WIDTH SHEET CH FONT)) 0))))
	;; If this char went past the stop-point, pretend we stopped before it.
	(WHEN (AND COMPUTE-MOTION-ROUND-DOWN
		   (> X STOP-X) ( Y STOP-Y))
	  (RETURN (VALUES OLD-X Y
			  I MAXIMUM-X)))
	;; If this char went past the right margin, do a Newline and then redo this char.
	(COND ((> X RIGHT-LIMIT)
	       (SETQ X 0 Y (+ Y LINE-HT))
	       (AND (> Y BOTTOM-LIMIT) (SETQ Y 0)))
	      (T (INCF I)))
	(GO FAST)))

(DEFMETHOD (SHEET :CHARACTER-WIDTH) (CHAR &OPTIONAL (FONT CURRENT-FONT))
  (SHEET-CHARACTER-WIDTH SELF CHAR
			 (IF (TYPEP FONT 'FONT)
			     FONT
			   (SEND (SHEET-GET-SCREEN SELF) :PARSE-FONT-DESCRIPTOR FONT))))

(DEFUN SHEET-CHARACTER-WIDTH (SHEET CH FONT &AUX TEM)
  "Returns the width of a character, in raster units.
For Backspace, it can return a negative number.
For Tab, the number returned depends on the current cursor position.
For Newline, the result is zero.
CH may be NIL; then you get the font's character-width."
  (COERCE-FONT FONT SHEET)
  (COND ((NULL CH) (FONT-CHAR-WIDTH FONT))
	((< CH #o200)				;Ordinary printing character
	 (COND ((SETQ TEM (FONT-CHAR-WIDTH-TABLE FONT)) (AREF TEM CH))
	       (T (FONT-CHAR-WIDTH FONT))))
	((= CH #/NEWLINE) 0)			;Return
	((= CH #/TAB)				;Tab
	 (SETQ TEM (SHEET-TAB-WIDTH SHEET))
	 (- (* (TRUNCATE (+ (SHEET-CURSOR-X SHEET) TEM) TEM) TEM)
	    (SHEET-CURSOR-X SHEET)))
	((AND (= CH #/BACKSPACE) (ZEROP (SHEET-BACKSPACE-NOT-OVERPRINTING-FLAG SHEET)))
	 (MINUS (SHEET-CHAR-WIDTH SHEET)))		;Backspace
	(T						;Misc lozenge character
	 (LET ((TEM (CAR (RASSQ CH SI::XR-SPECIAL-CHARACTER-NAMES))))
	   (LOZENGED-STRING-WIDTH (OR TEM "777"))))))

(DEFMETHOD (SHEET :STRING-LENGTH) (&REST ARGS)
  (APPLY #'SHEET-STRING-LENGTH SELF ARGS))

(DEFUN SHEET-STRING-LENGTH (SHEET STRING &OPTIONAL (START 0) (END NIL) (STOP-X NIL)
						   FONT (START-X 0)
						   (TAB-WIDTH
						     (IF FONT (* (FONT-CHAR-WIDTH FONT)
								 (SHEET-TAB-NCHARS SHEET))
						       (SHEET-TAB-WIDTH SHEET)))
						   &AUX (MAX-X START-X))
  "Return the length in X-position of STRING or a portion.
START and END specify the portion (default is all).
START-X is an X-position to begin computation at.
STOP-X is an X-position at which to stop processing and return.
 FINAL-INDEX will indicate where in the string this was reached.
FONT is the font to use (default is SHEET's current font);
 but if STRING is an ART-FAT-STRING, each character's font
 is looked up in SHEET's font-map.
TAB-WIDTH is the width to use for tab characters,
 defaulting to SHEET's SHEET-TAB-WIDTH.

The cursor position does not wrap around during processing;
arbitrarily large values can be returned.
Use TV:SHEET-COMPUTE-MOTION if you want wrap-around.

Three values are returned:
FINAL-X is the X-position when processing stopped
 (due to end of string or portion, or reaching STOP-X).
FINAL-INDEX is the index in the string at which processing stopped.
MAXIMUM-X is the largest X-position reached during processing.
 This can be larger than FINAL-X if the string contains
 Backspaces or Newlines."
  (DECLARE (VALUES FINAL-X FINAL-INDEX MAXIMUM-X))
  (IF FONT
      (COERCE-FONT FONT SHEET)
    (SETQ FONT (SHEET-CURRENT-FONT SHEET)))
  (PROG (CWA CW CH FONTX TEM I N NN II STRINGP (X START-X))
	(SETQ I START
	      N (OR END (ARRAY-ACTIVE-LENGTH STRING))
	      CW (FONT-CHAR-WIDTH FONT))
	;; At this point, decide whether we can use the fast version
     SLOW
	(AND (SETQ STRINGP (= (%P-MASK-FIELD-OFFSET %%ARRAY-TYPE-FIELD STRING 0)
			      ART-STRING))	;i.e. no font changes
	     (NULL (SETQ CWA (FONT-CHAR-WIDTH-TABLE FONT)))	;and fixed width
	     (GO FAST))
     SLOW0
	(UNLESS (< I N)				;If string exhausted
	  (RETURN (VALUES X I MAX-X)))
	;; Move quickly over 20 characters, or all the remaining characters,
	;; if that does not go past STOP-X.
	(WHEN (OR STRINGP FONTX)
	  (LET ((WIDTH-INCR
		  (%STRING-WIDTH (OR CWA
				     PRINTING-CHARACTER-TRANSLATE-TABLE)
				 (IF FONTX (DPB FONTX %%CH-FONT 0) 0)
				 STRING I N
				 (AND STOP-X
				      (IF CWA
					  (- STOP-X X)
					(FLOOR (- STOP-X X) CW))))))
	    (UNLESS CWA
	      (SETQ WIDTH-INCR (* WIDTH-INCR CW)))
	    (SETQ I (%POP))
	    (INCF X WIDTH-INCR)
	    (SETQ MAX-X (MAX X MAX-X))
	    ;; Loop back if reached end of string.
	    (IF (= I N) (GO SLOW0))
	    ;; Otherwise we stopped due to funny char or font change or reaching STOP-X.
	    ))
	(SETQ CH (CHAR-CODE (SETQ TEM (AREF STRING I))))
	(COND ((AND (NOT STRINGP)		;Changing fonts
		    (NEQ (SETQ TEM (CHAR-FONT TEM)) FONTX))
	       (SETQ FONTX TEM
		     FONT (AREF (SHEET-FONT-MAP SHEET) FONTX)
		     CWA (FONT-CHAR-WIDTH-TABLE FONT)
		     CW (FONT-CHAR-WIDTH FONT))))
	(COND ((< CH #o200)			;Printing character
	       (SETQ NN (IF CWA (AREF CWA CH) CW)))
	      ((= CH #/TAB)
	       (SETQ TEM TAB-WIDTH)
	       (SETQ NN (- (* (TRUNCATE (+ X TEM) TEM) TEM) X)))
	      ((AND (= CH #/BACKSPACE) (ZEROP (SHEET-BACKSPACE-NOT-OVERPRINTING-FLAG SHEET)))
	       (SETQ NN (- (MAX 0 (- X (SHEET-CHAR-WIDTH SHEET))) X)))
	      ((= CH #/NEWLINE)
	       (SETQ NN 0 X 0))
	      (T				;Lozenged character
	       (SETQ NN (SHEET-CHARACTER-WIDTH SHEET CH FONT))))
	(INCF X NN)
	(IF (> X MAX-X) (SETQ MAX-X X))
	(WHEN (AND STOP-X (> X STOP-X))		;If char doesn't fit, stop before it
	  (RETURN (VALUES (- X NN) I MAX-X)))
	(INCF I)
	(GO SLOW)

	;; Here is the fast loop.  The basic idea is to scan as fast as possible
	;; over printing characters, with all checking outside the loop.
     FAST
	;; First, decide the most characters we want to scan over in a whack
	(SETQ NN (COND ((NULL STOP-X) N)	;NN is limiting value of I
		       ((MIN (1+ (TRUNCATE (- STOP-X X) CW))
			     N))))
	;; Now, scan over printing characters.
	(WHEN ( (SETQ II I) NN)		;Save initial I, and check for null loop
	  (GO SLOW0))
     SCN
	(%STRING-WIDTH PRINTING-CHARACTER-TRANSLATE-TABLE
		       0 STRING II NN NIL)
	(SETQ I (%POP))
;	(SETQ TEM #o200)			;This is really a ridiculous bum
;    SCN
;	(AND (< (AREF STRING I) TEM)		;If this is a printing character
;	     (< (SETQ I (1+ I)) NN)		; and we haven't reached stop point
;	     (GO SCN))				; then continue to loop (9 instructions)
	(SETQ X (+ (* (- I II) CW) X))		;Account for the motion of those chars
	(IF (> X MAX-X) (SETQ MAX-X X))
	(GO SLOW0)))				;Either string exhausted, non-printing,
						; or reached stop-x

(DEFMETHOD (SHEET :STRING-OUT-EXPLICIT)
	   (STRING START-X START-Y X-LIMIT Y-LIMIT FONT ALU
	    &OPTIONAL (START 0) END MULTI-LINE-LINE-HEIGHT)
  (SHEET-STRING-OUT-EXPLICIT-1 SELF STRING START-X START-Y X-LIMIT Y-LIMIT FONT ALU
			       START END MULTI-LINE-LINE-HEIGHT))

(COMPILER:MAKE-OBSOLETE SHEET-STRING-OUT-EXPLICIT
			"use the :STRING-OUT-EXPLICIT operation with rearranged args")
(DEFUN SHEET-STRING-OUT-EXPLICIT (SHEET STRING START-X Y XLIM FONT ALU
				  &OPTIONAL (START 0) (END NIL)
				  MULTI-LINE-LINE-HEIGHT YLIM)
  (SHEET-STRING-OUT-EXPLICIT-1 SHEET STRING START-X Y XLIM YLIM
			       FONT ALU START END MULTI-LINE-LINE-HEIGHT))

(DEFUN SHEET-STRING-OUT-EXPLICIT-1 (SHEET STRING START-X Y XLIM YLIM FONT ALU
				    &OPTIONAL (START 0) (END NIL)
				    MULTI-LINE-LINE-HEIGHT
				    &AUX FIT FWT LKT
				    (X START-X))
  "Output STRING on SHEET without using SHEET's cursor, font, etc.
Output starts at cursor position START-X, Y but SHEET's cursor is not moved.
Output stops if x-position XLIM or y-position YLIM is reached.
Font FONT is used, and alu-function ALU.
START and END specify a portion of STRING to be used.
MULTI-LINE-LINE-HEIGHT is how far to move down for Newline characters;
 Newline also moves back to x-position START-X.
 NIL means output <Return> with a lozenge.
All position arguments are relative to SHEET's outside edges."
  (DECLARE (VALUES FINAL-X FINAL-INDEX FINAL-Y))
  (COERCE-FONT FONT SHEET)
  (SETQ FIT (FONT-INDEXING-TABLE FONT)
	FWT (FONT-CHAR-WIDTH-TABLE FONT)
	LKT (FONT-LEFT-KERN-TABLE FONT))
  (OR XLIM (SETQ XLIM (SHEET-WIDTH SHEET)))
  (PREPARE-SHEET (SHEET)
    (DO ((I START (1+ I))
	 (N (OR END (ARRAY-ACTIVE-LENGTH STRING)))
	 (WIDTH (FONT-CHAR-WIDTH FONT))
	 (CH))
	(( I N) (VALUES X Y I))
      (SETQ CH (AREF STRING I))
      (COND ((AND MULTI-LINE-LINE-HEIGHT (= CH #/NEWLINE))
	     (SETQ X START-X Y (+ Y MULTI-LINE-LINE-HEIGHT))
	     (IF (AND YLIM (> (+ Y MULTI-LINE-LINE-HEIGHT) YLIM))
		 (RETURN (VALUES X Y I))))
	    (( CH #o200)
	     (LET* ((STRING (STRING (OR (CAR (RASSQ CH SI::XR-SPECIAL-CHARACTER-NAMES))
					(FORMAT NIL "~3O" CH))))
		    (NX (+ X (LOZENGED-STRING-WIDTH STRING))))
	       (IF (> NX XLIM) (RETURN (VALUES X Y I)))
	       (SHEET-DISPLAY-LOZENGED-STRING-INTERNAL SHEET STRING
						       X (1+ Y) XLIM ALU)
	       (SETQ X NX)))
	    (T (IF FWT (SETQ WIDTH (AREF FWT CH)))
	       (IF (> (+ X WIDTH) XLIM) (RETURN (VALUES X Y I)))
	       (DRAW-CHAR FONT CH
			  (IF LKT (- X (AREF LKT CH)) X)
			  Y ALU SHEET)
	       (INCF X WIDTH))))))

;;; like %DRAW-CHAR but works on wide characters just as on narrow ones.
(DEFUN DRAW-CHAR (FONT CH X Y ALU SHEET)
  "Draw character CH in FONT at X, Y in SHEET using alu-function ALU.
X and Y are relative to SHEET's outside edges."
  (COERCE-FONT FONT SHEET)
  (LET ((FIT (FONT-INDEXING-TABLE FONT)))
    (IF FIT
	(DO ((CH (AREF FIT CH) (1+ CH))
	     (LIM (AREF FIT (1+ CH)))
	     (BPP (IF (ARRAYP SHEET) (ARRAY-BITS-PER-PIXEL SHEET)
		    (SHEET-BITS-PER-PIXEL SHEET)))
	     (X X (+ X (TRUNCATE (FONT-RASTER-WIDTH FONT) BPP))))
	    (( CH LIM))
	  (%DRAW-CHAR FONT CH X Y ALU SHEET))
      (%DRAW-CHAR FONT CH X Y ALU SHEET))))

(DEFMETHOD (SHEET :DISPLAY-CENTERED-STRING-EXPLICIT) (&REST ARGS)
  (APPLY #'SHEET-DISPLAY-CENTERED-STRING-EXPLICIT SELF ARGS))

(COMPILER:MAKE-OBSOLETE SHEET-DISPLAY-CENTERED-STRING-EXPLICIT
  "use the :STRING-OUT-CENTERED-EXPLICIT operation with rearranged args")

(DEFUN SHEET-DISPLAY-CENTERED-STRING-EXPLICIT
       (SHEET STRING &OPTIONAL
	(LEFT (TV:SHEET-INSIDE-LEFT SHEET)) Y-POS
	(RIGHT (SHEET-INSIDE-RIGHT SHEET))
	(FONT (SHEET-CURRENT-FONT SHEET)) 
	(ALU (SHEET-CHAR-ALUF SHEET))
	(START 0) END
	(MULTI-LINE-LINE-HEIGHT (SHEET-LINE-HEIGHT SHEET))
	Y-LIMIT)
  (SHEET-STRING-OUT-CENTERED-EXPLICIT SELF STRING LEFT Y-POS RIGHT Y-LIMIT
				      FONT ALU START END MULTI-LINE-LINE-HEIGHT))

(DEFMETHOD (SHEET :STRING-OUT-CENTERED-EXPLICIT)
	   (STRING &OPTIONAL (LEFT (SHEET-INSIDE-LEFT)) Y-POS
	    (RIGHT (SHEET-INSIDE-RIGHT)) Y-LIMIT
	    (FONT CURRENT-FONT) 
	    (ALU CHAR-ALUF)
	    (START 0) END
	    (MULTI-LINE-LINE-HEIGHT LINE-HEIGHT))
  (SHEET-STRING-OUT-CENTERED-EXPLICIT SELF STRING LEFT Y-POS RIGHT Y-LIMIT
				      FONT ALU START END MULTI-LINE-LINE-HEIGHT))

(DEFUN SHEET-STRING-OUT-CENTERED-EXPLICIT
       (SHEET STRING
	&OPTIONAL (LEFT (TV:SHEET-INSIDE-LEFT SHEET)) Y-POS
	(RIGHT (SHEET-INSIDE-RIGHT SHEET)) YLIM
	(FONT (SHEET-CURRENT-FONT SHEET))
	(ALU (SHEET-CHAR-ALUF SHEET))
	(START 0) END
	(MULTI-LINE-LINE-HEIGHT (SHEET-LINE-HEIGHT SHEET))
	&AUX WID SWID)
  "Output STRING or portion on SHEET centered between LEFT and RIGHT.
LEFT and RIGHT are relative to SHEET's outside edge.
The string is truncated on the right if it is too wide.
Y-POS specifies the vertical position of the top of the output,
relative to SHEET's top margin.
FONT and ALU function are used, defaulting to SHEET's font and char-aluf.
START and END specify a portion of STRING to output; default is all.
MULTI-LINE-LINE-HEIGHT is the distance for Newline to move down;
 then each line is centered individually.
 It can be NIL meaning output Newline as <Return>.
 Default is sheet's line-height.

SHEET's cursor is not used or moved."
  (IF FONT
      (COERCE-FONT FONT SHEET)
      (SETQ FONT (SHEET-CURRENT-FONT SHEET)))
  (OR ALU (SETQ ALU ALU-IOR))
  (SETQ WID (- RIGHT LEFT)
	STRING (STRING STRING))
  (OR END (SETQ END (STRING-LENGTH STRING)))
  (DO ((BEG START)) ((>= BEG END))
    (LET ((STOP (OR (STRING-SEARCH-CHAR #/RETURN STRING BEG END) END)))
      (SETQ SWID		;Compute how wide the string is, and whether to truncate
	    (NTH-VALUE 3 (SHEET-COMPUTE-MOTION SHEET 0 0 STRING BEG STOP NIL
					       1.0s10 1.0s10 1.0s10 1.0s10 FONT)))
      (SHEET-STRING-OUT-EXPLICIT-1 SHEET STRING
				   (+ LEFT (MAX (TRUNCATE (- WID SWID) 2) 0))
				   Y-POS
				   RIGHT NIL FONT ALU BEG STOP)
      (IF (OR (NULL MULTI-LINE-LINE-HEIGHT)
	      ( (+ Y-POS MULTI-LINE-LINE-HEIGHT) YLIM))
	  (RETURN))
      (INCF Y-POS MULTI-LINE-LINE-HEIGHT)
      (SETQ BEG (1+ STOP)))))

(DEFMETHOD (SHEET :STRING-OUT-CENTERED) (&REST ARGS)
  (DECLARE (ARGLIST STRING &OPTIONAL LEFT RIGHT Y-POS))
  (APPLY #'SHEET-DISPLAY-CENTERED-STRING SELF ARGS))

(DEFMETHOD (SHEET :DISPLAY-CENTERED-STRING) (&REST ARGS)
  (DECLARE (ARGLIST STRING &OPTIONAL LEFT RIGHT Y-POS))
  (APPLY #'SHEET-DISPLAY-CENTERED-STRING SELF ARGS))

;;; This function displays a string centered between two X coordinates, truncated if necessary
;;; The arguments are relative to the margins, as usual.
(DEFUN SHEET-DISPLAY-CENTERED-STRING (SHEET STRING
				      &OPTIONAL (LEFT 0) (RIGHT (SHEET-INSIDE-WIDTH SHEET))
				                (Y-POS (- (SHEET-CURSOR-Y SHEET)
							  (SHEET-INSIDE-TOP SHEET)))
				      &AUX WID SWID SLEN)
  "Output STRING on SHEET centered between LEFT and RIGHT.
LEFT and RIGHT are relative to SHEET's margin.
Y-POS specifies the vertical position of the top of the output,
relative to SHEET's top margin.  The output may be multiple lines.
SHEET's current font, alu function and line height are used.
SHEET's cursor is left at the end of the string."
  (SETQ WID (- RIGHT LEFT)
	STRING (STRING STRING))
  ;; Compute how wide the string is, and whether to truncate
  (MULTIPLE-VALUE-SETQ (SWID SLEN)
     (SHEET-STRING-LENGTH SHEET STRING 0 NIL WID))
  ;; SHEET-SET-CURSORPOS takes arguments in a different coordinate system
  (SHEET-SET-CURSORPOS SHEET (+ LEFT (MAX (TRUNCATE (- WID SWID) 2) 0)) Y-POS)
  (SHEET-STRING-OUT SHEET STRING 0 SLEN))

(DEFMETHOD (SHEET :STRING-OUT-X-Y-CENTERED-EXPLICIT) (&REST ARGS)
  (DECLARE (ARGLIST STRING &OPTIONAL LEFT TOP RIGHT BOTTOM FONT ALU START END LINE-HEIGHT))
  (APPLY #'SHEET-DISPLAY-X-Y-CENTERED-STRING SELF ARGS))

(DEFMETHOD (SHEET :DISPLAY-X-Y-CENTERED-STRING) (&REST ARGS)
  (DECLARE (ARGLIST STRING &OPTIONAL LEFT TOP RIGHT BOTTOM FONT ALU START END LINE-HEIGHT))
  (APPLY #'SHEET-DISPLAY-X-Y-CENTERED-STRING SELF ARGS))

(DEFUN SHEET-DISPLAY-X-Y-CENTERED-STRING (SHEET STRING
					  &OPTIONAL
					  (LEFT (SHEET-INSIDE-LEFT SHEET))
					  (TOP (SHEET-INSIDE-TOP SHEET))
					  (RIGHT (SHEET-INSIDE-RIGHT SHEET))
					  (BOTTOM (SHEET-INSIDE-BOTTOM SHEET))
					  (FNT (SHEET-CURRENT-FONT SHEET))
					  (ALU (SHEET-CHAR-ALUF SHEET))
					  (START 0) END
					  (MULTI-LINE-LINE-HEIGHT (SHEET-LINE-HEIGHT SHEET)))
  "Display STRING on SHEET centered in both X and Y, in font FNT.
It is centered horizontally between LEFT and RIGHT,
vertically between TOP and BOTTOM.
All four coordinates are relative to SHEET's outside edges.
SHEET's cursor is not used or moved."
  (LET ((WID (- RIGHT LEFT)))
    (MULTIPLE-VALUE-BIND (NIL SHEI SLEN SWID)
	(SHEET-COMPUTE-MOTION SHEET LEFT TOP STRING START END T
			      0 (+ TOP (SHEET-INSIDE-HEIGHT SHEET))
			      #o30000000 NIL FNT MULTI-LINE-LINE-HEIGHT)
;	(SHEET-STRING-LENGTH SHEET STRING START END WID FNT)
      (UNLESS (NUMBERP SLEN) (SETQ SLEN NIL))
      (SHEET-STRING-OUT-EXPLICIT-1 SHEET STRING
				   (+ LEFT (MAX (TRUNCATE (- WID SWID) 2) 0))
				   (MAX (- (TRUNCATE (+ TOP BOTTOM) 2)
					   (TRUNCATE SHEI 2))
					TOP)
				   RIGHT BOTTOM
				   FNT ALU START SLEN MULTI-LINE-LINE-HEIGHT))))

;;; Most screens can be seen by the "user"
(DEFMETHOD (SCREEN :USER-VISIBLE) () T)

;;; A mixin that causes inferiors to be scaled when the size of the window changes
;;; and propagates changes in the default font.
;;; TIME-STAMP is (as for any sheet), the time-stamp for comparison with this sheet's superior
;;; CURRENT-TIME-STAMP is the stamp which propagates down into our inferiors.  If
;;; an inferior's TIME-STAMP is EQ to our CURRENT-TIME-STAMP, then the inferior is
;;; up to date.  Otherwise we compare the two stamps and resolve the differences.
;;; This comparison happens to the active inferiors when our stamp changes and
;;; to any newly-activated inferior.
;;; This mixin is the only thing which knows the format of time stamps (other than
;;; that they are compared with EQ).  A time stamp is a list which represents
;;; the state of a window that has this mixin:
;;;	(serial-number our-inside-width our-inside-height default-font)
;;; serial-number is incremented every time a new time stamp is generated, and is
;;; only there for human beings looking at the stamps.
;;; Other elements may be added as needed.
(DEFFLAVOR SCALE-INFERIORS-MIXIN (CURRENT-TIME-STAMP) ()
  (:REQUIRED-FLAVORS SHEET)
  (:GETTABLE-INSTANCE-VARIABLES CURRENT-TIME-STAMP))

(DEFMETHOD (SCALE-INFERIORS-MIXIN :AFTER :INIT) (IGNORE)
  (SETQ CURRENT-TIME-STAMP
	(LIST 0 (SHEET-INSIDE-WIDTH) (SHEET-INSIDE-HEIGHT)
	      (LOOP FOR ELT IN (SCREEN-FONT-ALIST (SHEET-GET-SCREEN SELF))
		    APPEND (LIST (CAR ELT) (FONT-EVALUATE (CDR ELT)))))))

(DEFMETHOD (SCALE-INFERIORS-MIXIN :INFERIOR-TIME-STAMP) (INF)
  INF						;Inferiors all have same time stamp
  CURRENT-TIME-STAMP)

(DEFUN SCALE-INFERIORS-MIXIN-UPDATE-INFERIOR (INFERIOR)
  (DECLARE (:SELF-FLAVOR SCALE-INFERIORS-MIXIN))
  (LET ((INF-TIME-STAMP (SHEET-TIME-STAMP INFERIOR)))
    (COND ((NEQ INF-TIME-STAMP CURRENT-TIME-STAMP)
	   (LET ((OLD-FONT (FOURTH (SHEET-TIME-STAMP INFERIOR)))
		 (NEW-FONT (FOURTH CURRENT-TIME-STAMP)))
	     (OR (EQUAL OLD-FONT NEW-FONT)
		 (SEND INFERIOR :CHANGE-OF-DEFAULT-FONT NIL NIL)))
	   (SCALE-INFERIORS-MIXIN-SCALE-INFERIOR INFERIOR NIL INF-TIME-STAMP)))))

(DEFUN SCALE-INFERIORS-MIXIN-SCALE-INFERIOR (INFERIOR EXPOSE
					     &OPTIONAL (INF-TIME-STAMP
							 (SHEET-TIME-STAMP INFERIOR)))
  (DECLARE (:SELF-FLAVOR SCALE-INFERIORS-MIXIN))
  (OR (EQ CURRENT-TIME-STAMP INF-TIME-STAMP)
      ;; Hasn't had edges set in the current time slice, so set them
      (LET* ((SIZE-LAST-TIME (CDR INF-TIME-STAMP))
	     (NEW-LEFT (TRUNCATE (* (SHEET-X-OFFSET INFERIOR)
				    (SHEET-INSIDE-WIDTH))
				 (FIRST SIZE-LAST-TIME)))
	     (NEW-TOP (TRUNCATE (* (SHEET-Y-OFFSET INFERIOR)
				   (SHEET-INSIDE-HEIGHT))
				(SECOND SIZE-LAST-TIME)))
	     (NEW-WIDTH (TRUNCATE (* (SHEET-WIDTH INFERIOR)
				     (SHEET-INSIDE-WIDTH))
				  (FIRST SIZE-LAST-TIME)))
	     (NEW-HEIGHT (TRUNCATE (* (SHEET-HEIGHT INFERIOR)
				      (SHEET-INSIDE-HEIGHT))
				   (SECOND SIZE-LAST-TIME))))
	(COND ((AND (= (SHEET-X-OFFSET INFERIOR) NEW-LEFT)
		    (= (SHEET-Y-OFFSET INFERIOR) NEW-TOP)
		    (= (SHEET-WIDTH INFERIOR) NEW-WIDTH)
		    (= (SHEET-HEIGHT INFERIOR) NEW-HEIGHT))
	       (SETQ NEW-LEFT NIL))
	      ((NOT (SEND INFERIOR :SET-EDGES NEW-LEFT NEW-TOP
					      (+ NEW-LEFT NEW-WIDTH) (+ NEW-TOP NEW-HEIGHT)
					      :VERIFY))
	       ;; Won't go, try not to change size
	       (SETQ NEW-WIDTH (SHEET-WIDTH INFERIOR)
		     NEW-HEIGHT (SHEET-HEIGHT INFERIOR))
	       (AND (> (+ NEW-WIDTH NEW-LEFT) (SHEET-INSIDE-RIGHT))
		    (SETQ NEW-LEFT (- (SHEET-INSIDE-RIGHT) NEW-WIDTH)))
	       (AND (> (+ NEW-HEIGHT NEW-TOP) (SHEET-INSIDE-BOTTOM))
		    (SETQ NEW-TOP (- (SHEET-INSIDE-BOTTOM) NEW-HEIGHT)))
	       (OR (SEND INFERIOR :SET-EDGES NEW-LEFT NEW-TOP
					     (+ NEW-LEFT NEW-WIDTH) (+ NEW-TOP NEW-HEIGHT)
					     :VERIFY)
		   ;; Won't go, don't change size at all
		   (SETQ NEW-LEFT NIL))))
	(COND (NEW-LEFT
	       (SEND INFERIOR :SET-EDGES NEW-LEFT NEW-TOP
		     			 (+ NEW-LEFT NEW-WIDTH) (+ NEW-TOP NEW-HEIGHT))
	       (AND EXPOSE (SEND INFERIOR :EXPOSE)))
	      (T (SEND INFERIOR :UPDATE-TIME-STAMP))))))

(DEFMETHOD (SCALE-INFERIORS-MIXIN :BEFORE :INFERIOR-ACTIVATE) (INFERIOR)
  ;; Catch up with any changes that happened while we were inactive
  (SCALE-INFERIORS-MIXIN-UPDATE-INFERIOR INFERIOR)
  INFERIOR)

(DEFWRAPPER (SCALE-INFERIORS-MIXIN :CHANGE-OF-SIZE-OR-MARGINS) (IGNORE . BODY)
  `(DELAYING-SCREEN-MANAGEMENT
     (LET ((OLD-EXP-INFS (REVERSE EXPOSED-INFERIORS)))
       (DOLIST (I EXPOSED-INFERIORS)
	 (SEND I :DEEXPOSE))
       ,@BODY
       (SETQ CURRENT-TIME-STAMP
	     (LIST (1+ (CAR CURRENT-TIME-STAMP))
		   (SHEET-INSIDE-WIDTH) (SHEET-INSIDE-HEIGHT)
		   (FOURTH CURRENT-TIME-STAMP)))
       (DOLIST (I OLD-EXP-INFS)
	 (SCALE-INFERIORS-MIXIN-SCALE-INFERIOR I T))
       (DOLIST (I INFERIORS)
	 (OR (MEMQ I EXPOSED-INFERIORS)
	     (SCALE-INFERIORS-MIXIN-SCALE-INFERIOR I NIL))))))

(DEFMETHOD (SCALE-INFERIORS-MIXIN :BEFORE :CHANGE-OF-DEFAULT-FONT) (IGNORE IGNORE)
  (SETQ CURRENT-TIME-STAMP
	(LIST (1+ (CAR CURRENT-TIME-STAMP))
	      (SHEET-INSIDE-WIDTH) (SHEET-INSIDE-HEIGHT)
	      (LOOP FOR ELT IN (SCREEN-FONT-ALIST (SHEET-GET-SCREEN SELF))
		    APPEND (LIST (CAR ELT) (FONT-EVALUATE (CDR ELT)))))))

(DEFVAR KILL-RECURSION NIL
  "Non-NIL if killing the inferiors of another window being killed.")

;; Kill the processes only after any :after :kill daemons have run.
(DEFWRAPPER (SHEET :KILL) (IGNORE . BODY)
  `(LET ((PROCESSES (UNLESS KILL-RECURSION (SEND SELF :PROCESSES)))
	 (KILL-RECURSION T))
     ,@BODY
     (KILL-PROCESSES PROCESSES)))

(DEFMETHOD (SHEET :KILL) ()
  (SEND SELF :DEACTIVATE)
  (MAPC #'(LAMBDA (X) (SEND X :KILL)) (COPY-LIST INFERIORS)))

(DEFUN KILL-PROCESSES (PROCESSES)
  (DOLIST (P PROCESSES)
    (UNLESS (EQ P CURRENT-PROCESS)
      (SEND P :KILL)))
  (IF (MEMQ CURRENT-PROCESS PROCESSES)
      (SEND CURRENT-PROCESS :KILL)))

;; Uses :APPEND method combination and returns a list of processes to be killed.
(DEFMETHOD (SHEET :PROCESSES) ()
  (MAPCAN #'(LAMBDA (X) (SEND X :PROCESSES)) (COPY-LIST INFERIORS)))


(DEFFLAVOR STANDARD-SCREEN () (SCALE-INFERIORS-MIXIN SCREEN))

;;; Before making our first screen, compile any methods it requires
;;; Also do Sheet now, since it actually does get instantiated, e.g. for the who-line
(COMPILE-FLAVOR-METHODS SHEET SCREEN STANDARD-SCREEN)

;;; This height may get hacked by the who-line making code if the wholine ends up
;;; at the bottom of the main screen (which it usually does!)
(DEFVAR MAIN-SCREEN-WIDTH
  (SELECT-PROCESSOR
    (:CADR 768.)
    (:LAMBDA #o1440)))				;LAMBDA TV IS 32. BITS WIDER.

(DEFVAR MAIN-SCREEN-HEIGHT
  (SELECT-PROCESSOR
    (:CADR 963.)				;was 896. for CPT
    (:LAMBDA (- #o2000 8))))

(DEFVAR MAIN-SCREEN-LOCATIONS-PER-LINE
  (SELECT-PROCESSOR
    (:CADR 24.)
    (:LAMBDA 32.)))

(DEFCONST MAIN-SCREEN-BUFFER-ADDRESS IO-SPACE-VIRTUAL-ADDRESS)
(DEFCONST MAIN-SCREEN-CONTROL-ADDRESS #o377760)
(DEFCONST MAIN-SCREEN-BUFFER-LENGTH #o100000)

;;;Set things up
(DEFUN INITIALIZE ()
  (SHEET-CLEAR-LOCKS)
  (WHO-LINE-SETUP)
  ;; Set up screen and sheet for the main monitor (CPT typically)
  (OR MAIN-SCREEN
      (SETQ MAIN-SCREEN
	    (DEFINE-SCREEN 'STANDARD-SCREEN "Main Screen"
	      :BUFFER MAIN-SCREEN-BUFFER-ADDRESS
	      :CONTROL-ADDRESS MAIN-SCREEN-CONTROL-ADDRESS
	      :PROPERTY-LIST '(:VIDEO :BLACK-AND-WHITE :CONTROLLER :SIMPLE)
	      :HEIGHT (- MAIN-SCREEN-HEIGHT (SHEET-HEIGHT WHO-LINE-SCREEN))
	      :WIDTH MAIN-SCREEN-WIDTH
	      :LOCATIONS-PER-LINE MAIN-SCREEN-LOCATIONS-PER-LINE)))
  (SETQ MOUSE-SHEET MAIN-SCREEN)
  (SETQ DEFAULT-SCREEN MAIN-SCREEN
	INHIBIT-SCREEN-MANAGEMENT NIL
	SCREEN-MANAGER-TOP-LEVEL T
	SCREEN-MANAGER-QUEUE NIL))

(DEFUN DEFINE-SCREEN (FLAVOR NAME &REST ARGS)
  (LET ((SCREEN (APPLY #'MAKE-INSTANCE FLAVOR :NAME NAME ARGS)))
    (PUSH SCREEN ALL-THE-SCREENS)
    (SEND SCREEN :EXPOSE)
    SCREEN))

(DEFVAR MAIN-SCREEN-AND-WHO-LINE NIL)
(DEFUN MAIN-SCREEN-AND-WHO-LINE ()
  (IF MAIN-SCREEN-AND-WHO-LINE
      (SI:CHANGE-INDIRECT-ARRAY MAIN-SCREEN-AND-WHO-LINE (SHEET-ARRAY-TYPE MAIN-SCREEN)
				(IF ARRAY-INDEX-ORDER
				    (LIST MAIN-SCREEN-HEIGHT MAIN-SCREEN-WIDTH)
				  (LIST MAIN-SCREEN-WIDTH MAIN-SCREEN-HEIGHT))
				(SCREEN-BUFFER MAIN-SCREEN) NIL)
    (SETQ MAIN-SCREEN-AND-WHO-LINE
	  (MAKE-PIXEL-ARRAY MAIN-SCREEN-WIDTH MAIN-SCREEN-HEIGHT
			    :TYPE (SHEET-ARRAY-TYPE MAIN-SCREEN)
			    :DISPLACED-TO (SCREEN-BUFFER MAIN-SCREEN))))
  MAIN-SCREEN-AND-WHO-LINE)

(DEFVAR INITIAL-LISP-LISTENER)

;;; This function is called from an initialization in COMETH
(DEFUN WINDOW-INITIALIZE (&AUX FIRST-TIME)
  (INITIALIZE)
  (DOLIST (S ALL-THE-SCREENS)
    (SEND S :EXPOSE))
  (SETQ KBD-TYI-HOOK NIL PROCESS-IS-IN-ERROR NIL)
  (OR (EQ WHO-LINE-PROCESS SI:INITIAL-PROCESS)	;So it stays latched here during loading
      (SETQ WHO-LINE-PROCESS NIL))
  (OR INITIAL-LISP-LISTENER			;Set to NIL in LTOP
      (SETQ INITIAL-LISP-LISTENER (MAKE-INSTANCE 'LISP-LISTENER :PROCESS SI:INITIAL-PROCESS)
	    FIRST-TIME T))
  (SEND INITIAL-LISP-LISTENER :SELECT)
  (WHEN FIRST-TIME (SETQ *TERMINAL-IO* INITIAL-LISP-LISTENER))
  (PUSHNEW 'TV:BLINKER-CLOCK SI:CLOCK-FUNCTION-LIST :TEST #'EQ))


(DEFVAR SYNC-RAM-CONTENTS :UNBOUND
  "Data to load into the TV board's sync memory.")

(DEFUN SET-TV-SPEED (&OPTIONAL ARG (WASTED-LINES 0) &AUX VALUE N-LINES)
  "Set the TV refresh rate.  ARG is the number of scan lines to display.
On the CADR, it can also be the refresh frequency (default is 60.5).
WASTED-LINES is a number of lines at the bottom of the screen that should not be used
for output, and should be left zero, though they will be displayed on the monitor.
This is useful if your monitor is adjusted so that some of it cannot be seen."
  (IF ARG
      ;; Try not to burn up the monitor
      (SELECT-PROCESSOR
	(:CADR (CHECK-TYPE ARG (OR (INTEGER 54. 76.) (INTEGER 7644. 1086.))))
	(:LAMBDA (CHECK-TYPE ARG (INTEGER 101. 1024.))))
    (SETQ ARG (SELECT-PROCESSOR (:CADR 60.5) (:LAMBDA 1024.))))
  ;; If arg is frequency, compute number of lines from it.
  (IF (< 100. ARG)
      (SETQ N-LINES ARG)
    (SETQ N-LINES (- (FIX (// 1E6 (* 16. ARG))) 70.)))
  ;; Here each horizontal line is 32. sync clocks, or 16.0 microseconds with a 64 MHz clock.
  ;; The number of lines per frame is 70. overhead lines plus enough display lines
  ;; to give the desired rate.
  (DELAYING-SCREEN-MANAGEMENT
    (WITH-MOUSE-USURPED
      (LOCK-SHEET (MAIN-SCREEN)
	(LOCK-SHEET (WHO-LINE-SCREEN)
	  (WITHOUT-INTERRUPTS
	    (LET ((MS MOUSE-SHEET) (SW SELECTED-WINDOW))
	      (AND (SHEET-ME-OR-MY-KID-P MS MAIN-SCREEN)
		   (SETQ MOUSE-SHEET NIL))
	      (SEND WHO-LINE-SCREEN :DEEXPOSE)
	      (SEND MAIN-SCREEN :DEEXPOSE)
	      (IF-IN-CADR
		(SI:SETUP-CPT
		  (SETQ SYNC-RAM-CONTENTS	;save for possible use at LISP-REINITIALIZE.
			(APPEND '(1.  (1 33) (5 13) 12 12 (11. 12 12) 212 113)	;VERT SYNC, CLEAR TVMA
				'(53. (1 33) (5 13) 12 12 (11. 12 12) 212 13)	;VERT RETRACE
				'(8.  (1 31)  (5 11) 11 10 (11. 0 0) 200 21)	;8 LINES OF MARGIN
				(DO ((L NIL (APPEND L `(,DN (1 31) (5 11) 11 50 (11. 0 40) 200 21)))
				     (N N-LINES (- N DN))
				     (DN))
				    ((ZEROP N) L)
				  (SETQ DN (MIN 255. N)))
				'(7. (1 31) (5 11) #o11 #o10 (11. 0 0) #o200 #o21)
				'(1. (1 31) (5 11) #o11 #o10 (11. 0 0) #o300 #o23)))
		  (SCREEN-CONTROL-ADDRESS MAIN-SCREEN)
		  T))
	      ;; Move the who-line, and change the dimensions of main screen
	      (SETQ MAIN-SCREEN-HEIGHT (- N-LINES WASTED-LINES))
	      (SEND WHO-LINE-SCREEN
		    :CHANGE-OF-SIZE-OR-MARGINS
		    :TOP (- MAIN-SCREEN-HEIGHT (SHEET-HEIGHT WHO-LINE-SCREEN)))
	      (SEND MAIN-SCREEN
		    :CHANGE-OF-SIZE-OR-MARGINS
		    :HEIGHT (- MAIN-SCREEN-HEIGHT (SHEET-HEIGHT WHO-LINE-SCREEN)))
	      (SETQ %DISK-RUN-LIGHT
		    (+ (- (* MAIN-SCREEN-HEIGHT (SHEET-LOCATIONS-PER-LINE MAIN-SCREEN)) 15)
		       MAIN-SCREEN-BUFFER-ADDRESS))
	      (SETQ WHO-LINE-RUN-LIGHT-LOC (+ 2 (LOGAND %DISK-RUN-LIGHT #o777777)))
	      (SEND WHO-LINE-SCREEN :EXPOSE)
	      (SEND MAIN-SCREEN :EXPOSE)
	      (AND SW (SEND SW :SELECT))
	      (SETQ MOUSE-SHEET MS)
	      ;; Zero out the words at screen bottom that we are not using.
	      (IF-IN-LAMBDA
		(INCF WASTED-LINES (- 1024. N-LINES)))
	      (LET ((WASTED-WORDS (* WASTED-LINES (SHEET-LOCATIONS-PER-LINE MAIN-SCREEN)))
		    (PTR1 (%POINTER-PLUS (SCREEN-BUFFER MAIN-SCREEN)
					 (* (- N-LINES WASTED-LINES)
					    (SHEET-LOCATIONS-PER-LINE MAIN-SCREEN)))))
		(DOTIMES (I WASTED-WORDS)
		  (%P-DPB 0 %%Q-LOW-HALF (%MAKE-POINTER-OFFSET DTP-FIX PTR1 I))
		  (%P-DPB 0 %%Q-HIGH-HALF (%MAKE-POINTER-OFFSET DTP-FIX PTR1 I))))
	      (SETQ VALUE (- N-LINES WASTED-LINES))))))))
  (DOLIST (RESOURCE-NAME WINDOW-RESOURCE-NAMES)
    (SI:MAP-RESOURCE 
      #'(LAMBDA (WINDOW &REST IGNORE)
	  (UNLESS (TYPEP WINDOW 'INSTANCE) (FERROR NIL "LOSSAGE"))
	  (IF (TYPEP WINDOW 'TV:BASIC-MENU)
	      (LET ((GEO (SEND WINDOW :GEOMETRY)))
		(DO ((L GEO (CDR L))) ((NULL L))
		  (SETF (CAR L) NIL)))
	    (LET* ((SUPERIOR (SEND WINDOW :SUPERIOR))
		   (BOTTOM (SEND WINDOW :HEIGHT))
		   (SUPHEIGHT (OR (SEND SUPERIOR :SEND-IF-HANDLES :INSIDE-HEIGHT)
				  (SEND SUPERIOR :HEIGHT))))
	      (IF (> BOTTOM SUPHEIGHT)
		  (SEND WINDOW :SET-SIZE (SEND WINDOW :WIDTH) SUPHEIGHT)))))
      RESOURCE-NAME))
  VALUE)

;(DEFF SET-TV-HEIGHT 'SET-TV-SPEED)

(DEFUN SET-WHO-LINE-LINES (N-LINES)
  "Reconfigure the screen so that the who line has N-LINES lines."
  (WITH-MOUSE-USURPED
    (LOCK-SHEET (MAIN-SCREEN)
      (LOCK-SHEET (WHO-LINE-SCREEN)
	(WITHOUT-INTERRUPTS
	  (LET ((MS MOUSE-SHEET) (SW SELECTED-WINDOW))
	    (AND (SHEET-ME-OR-MY-KID-P MS MAIN-SCREEN)
		 (SETQ MOUSE-SHEET NIL))
	    (SEND WHO-LINE-SCREEN :DEEXPOSE)
	    (SEND MAIN-SCREEN :DEEXPOSE)
	    (SEND WHO-LINE-SCREEN :SET-VSP (IF (= N-LINES 1) 0 2))
	    (SEND WHO-LINE-SCREEN :CHANGE-OF-SIZE-OR-MARGINS
		  		  :BOTTOM MAIN-SCREEN-HEIGHT
				  :TOP (- MAIN-SCREEN-HEIGHT
					  (* N-LINES (SHEET-LINE-HEIGHT WHO-LINE-SCREEN))))
	    (SEND MAIN-SCREEN :CHANGE-OF-SIZE-OR-MARGINS
			      :HEIGHT (- MAIN-SCREEN-HEIGHT (SHEET-HEIGHT WHO-LINE-SCREEN)))
	    (SEND WHO-LINE-SCREEN :EXPOSE)
	    (SEND MAIN-SCREEN :EXPOSE)
	    (AND SW (SEND SW :SELECT))
	    (SETQ MOUSE-SHEET MS)))))))


;;;; Scan line table hacking

(defconst scan-line-table-begin #16r6000)
(defconst scan-line-table-length (// #16r1000 4))

(defun read-scan-line-table (adr)
  (%nubus-read #xf8 (+ (* adr 4) scan-line-table-begin)))

(defun write-scan-line-table (adr data)
  (%nubus-write #xf8 (+ (* adr 4) scan-line-table-begin) data))

(defun load-scan-line-table (words-per-line)
  (do ((line-number 0 (1+ line-number))
       (bit-map-pointer 0 (+ bit-map-pointer (* 2 words-per-line))))
      ((>= line-number scan-line-table-length) ())
    (write-scan-line-table line-number bit-map-pointer)))

(defun set-up-scan-line-table ()
  (if-in-lambda
    (load-scan-line-table (sheet-locations-per-line main-screen))
    (setq %disk-run-light
	  (+ (* (1- main-screen-height) (sheet-locations-per-line main-screen))
	     14
	     (lsh #o77 18.)))
    (setq who-line-run-light-loc (+ 2 (logand %disk-run-light #o777777)))))

(add-initialization "Load scan line table" '(set-up-scan-line-table))

;;;

(defvar *words-per-line*)

(defun set-screen-width (new-width-in-words)
  (setq *words-per-line* new-width-in-words)
  (delaying-screen-management
    (with-mouse-usurped
      (lock-sheet (main-screen)
	(lock-sheet (who-line-screen)
	  (without-interrupts
	    (let ((ms mouse-sheet) (sw selected-window))
	      (and (sheet-me-or-my-kid-p ms main-screen)
		   (setq mouse-sheet nil))
	      (send who-line-screen :deexpose)
	      (send main-screen :deexpose)

	      (setf (sheet-locations-per-line main-screen) *words-per-line*)
	      (setf (sheet-locations-per-line who-line-screen) *words-per-line*)

	      ;fix cold-load-stream
	      (let ((new-array
		      (make-array (list (* 32. *words-per-line*) #o1777) :type 'art-1b
				  ; 10. is BUFFER instance variable
				  :displaced-to (%p-contents-offset si:cold-load-stream 10.))))
		(%p-store-contents-offset
		  new-array si:cold-load-stream 1)			;ARRAY
		(%p-store-contents-offset
		  *words-per-line* si:cold-load-stream 2)		;LOCATIONS-PER-LINE
		(%p-store-contents-offset #o1777 si:cold-load-stream 3)	;HEIGHT
		)

	      (load-scan-line-table *words-per-line*)

	      (map-over-all-windows-of-sheet
		#'(lambda (window) 
		    (send window :eval-inside-yourself
			  '(fix-window-width *words-per-line*)))
		main-screen)

	      (let ((array (send who-line-screen :old-screen-array)))
		(redirect-array array
				(array-type array)
				(* *words-per-line* 32.)
				(pixel-array-height array)
				(%p-contents-offset array
					     (+ (array-rank array)
						(%p-ldb-offset %%array-long-length-flag array
							       0)))
				nil))

	      (map-over-all-windows-of-sheet
		#'(lambda (window)
		    (cond ((neq window who-line-screen)
			   (send window :eval-inside-yourself
				 '(fix-window-width *words-per-line*)))))
		who-line-screen)
	      
	      (send who-line-screen :change-of-size-or-margins
				    :top (- main-screen-height
					    (sheet-height who-line-screen)))
	      (setq %disk-run-light
		    (+ (* (1- main-screen-height) (sheet-locations-per-line main-screen))
		       11.
		       (lsh #o77 18.)))
	      (setq who-line-run-light-loc (+ 2 (logand %disk-run-light #o777777)))
	      (send who-line-screen :expose)
	      (send main-screen :expose)
	      (and sw (send sw :select))
	      (mouse-set-sheet ms)
	      )))))))

(defun fix-window-width (words-per-line)
  (declare (:self-flavor sheet))
  (setq locations-per-line words-per-line)
  (if (and (variable-boundp screen-array) screen-array)
      (fix-array self screen-array words-per-line))
  (if (and (variable-boundp old-screen-array) old-screen-array)
      (fix-array self old-screen-array words-per-line))
  (if (and (variable-boundp bit-array) bit-array)
      (fix-array self bit-array words-per-line)))

(defun fix-array (window array words-per-line)
  (cond ((array-displaced-p array)
	 (redirect-array array
			 (array-type array)
			 (* words-per-line 32.)
			 (pixel-array-height array)
			 ;used to be just array
			 (%p-contents-offset array
					     (+ (array-rank array)
						(%p-ldb-offset %%array-long-length-flag array
							       0)))
			 (let ((offset (+ (send window :x-offset)
					  (* (send window :y-offset)
					     (* words-per-line 32.)))))
			   (if (zerop offset) 
			       (if (= (%p-ldb-offset si:%%array-index-length-if-short array 0)
				      2)
				   nil 0)
			     offset))))
	(t
	 (grow-bit-array array (* words-per-line 32.) (pixel-array-height array)))))

;;; Mapping over windows, allowing for devious concealment of Zmacs subwindows.

(defvar *mapped-windows*)

(defun map-over-all-windows-of-sheet (func sheet)
  (setq *mapped-windows* nil)
  (map-over-all-windows-of-sheet-1 func sheet)
  (dolist (resource-name window-resource-names)
    (si:map-resource #'(lambda (window ignore ignore)
			 (cond ((and (eq (send window :status) ':deactivated)
				     (eq sheet (sheet-get-screen window)))
				(map-over-all-windows-of-sheet-1 func window))))
		     resource-name)))

(defun map-over-all-windows-of-sheet-1 (func sheet)
  (cond ((null (memq sheet *mapped-windows*))
	 (push sheet *mapped-windows*)
	 (funcall func sheet)
	 (cond ((and (not (typep sheet 'zwei:zwei-mini-buffer))
		     (send sheet :send-if-handles :typeout-window))
		(map-over-all-windows-of-sheet-1 func (send sheet :typeout-window))))
	 (cond ((and (typep sheet 'zwei:mode-line-window)
		     (send sheet :mini-buffer-window))
		(map-over-all-windows-of-sheet-1 func (send sheet :mini-buffer-window))))
	 (dolist (x (send sheet :inferiors))
	   (map-over-all-windows-of-sheet-1 func x)))))

;;;

(DEFUN LAMBDA-SET-HEIGHT (&OPTIONAL (N-LINES 1024.) &AUX VALUE)
  "Set the TV refresh rate.  The default is 60.5.  Returns the number of display lines.
WASTED-LINES is a number of lines at the bottom of the screen that should not be used.
This is useful if your monitor is adjusted so that some of it cannot be seen."
  ;; Try not to burn up the monitor
  (CHECK-TYPE N-LINES (INTEGER 100. 1024.))
  (DELAYING-SCREEN-MANAGEMENT
    (WITH-MOUSE-USURPED
      (LOCK-SHEET (MAIN-SCREEN)
	(LOCK-SHEET (WHO-LINE-SCREEN)
	  (WITHOUT-INTERRUPTS
	    (LET ((MS MOUSE-SHEET) (SW SELECTED-WINDOW))
	      (AND (SHEET-ME-OR-MY-KID-P MS MAIN-SCREEN)
		   (SETQ MOUSE-SHEET NIL))
	      (SEND WHO-LINE-SCREEN :DEEXPOSE)
	      (SEND MAIN-SCREEN :DEEXPOSE)
	      ;; Move the who-line, and change the dimensions of main screen
	      (SETQ MAIN-SCREEN-HEIGHT N-LINES)
	      (SEND WHO-LINE-SCREEN :CHANGE-OF-SIZE-OR-MARGINS
				    :TOP (- MAIN-SCREEN-HEIGHT
					    (SHEET-HEIGHT WHO-LINE-SCREEN)))
	      (SEND MAIN-SCREEN :CHANGE-OF-SIZE-OR-MARGINS
				:HEIGHT (- MAIN-SCREEN-HEIGHT (SHEET-HEIGHT WHO-LINE-SCREEN)))
	      (let ((line-address (* (1- main-screen-height)
				     (sheet-locations-per-line main-screen))))
		(setq %disk-run-light (+ (+ line-address 11.) (lsh #o77 18.)))
		(setq who-line-run-light-loc (+ 2 (logand %disk-run-light #o777777))))
	      (SEND WHO-LINE-SCREEN :EXPOSE)
	      (SEND MAIN-SCREEN :EXPOSE)
	      (AND SW (SEND SW :SELECT))
	      (SETQ MOUSE-SHEET MS)
	      (LET ((WASTED-WORDS (* (- 1024. n-lines)
				     (SHEET-LOCATIONS-PER-LINE MAIN-SCREEN)))
		    (LAST-USED-WORD (* (+ (SHEET-HEIGHT WHO-LINE-SCREEN)
					  (SHEET-HEIGHT MAIN-SCREEN))
				       (SHEET-LOCATIONS-PER-LINE MAIN-SCREEN))))
		(DOTIMES (I WASTED-WORDS)
		  (%P-STORE-TAG-AND-POINTER
		    (%MAKE-POINTER-OFFSET DTP-FIX
					  (SCREEN-BUFFER MAIN-SCREEN) (+ LAST-USED-WORD I))
		    0 0)))
	      (SETQ VALUE N-LINES)))))))
  (DOLIST (RESOURCE-NAME WINDOW-RESOURCE-NAMES)
    (SI:MAP-RESOURCE 
      #'(LAMBDA (WINDOW &REST IGNORE)
	  (OR (TYPEP WINDOW 'INSTANCE) (FERROR NIL "LOSSAGE"))
	  (IF (typep window 'tv:basic-menu)
	      (LET ((GEO (SEND WINDOW :GEOMETRY)))
		(DO ((L GEO (CDR L))) ((NULL L))
		  (SETF (CAR L) NIL)))
	    (LET* ((SUPERIOR (SEND WINDOW :SUPERIOR))
		   (BOTTOM (SEND WINDOW :HEIGHT))
		   (SUPHEIGHT (OR (SEND SUPERIOR :SEND-IF-HANDLES :INSIDE-HEIGHT)
				  (SEND SUPERIOR :HEIGHT))))
	      (IF (> BOTTOM SUPHEIGHT)
		  (SEND WINDOW :SET-SIZE (SEND WINDOW :WIDTH) SUPHEIGHT)))))
      RESOURCE-NAME))
  VALUE)

;;; The high-level changes for the landscape.

(defun landscape ()
  "Configure all existing (primary) screens and windows for landscape monitor."
  (lambda-set-height 798.)
  (with-mouse-usurped
   (lock-sheet (main-screen)
    (lock-sheet (who-line-screen)
      (without-interrupts
	(let ((ms mouse-sheet) (sw selected-window))
	  (when (sheet-me-or-my-kid-p ms main-screen) (setq mouse-sheet nil))
	  (send who-line-screen :deexpose)
	  (send main-screen :deexpose)
	  (setq mouse-sheet ms)

	  (send who-line-screen :change-of-size-or-margins :width 1024.)
	  (send main-screen :change-of-size-or-margins :width 1024.)

	  (configure-who-line-for-landscape)

	  (mouse-set-sheet main-screen)
	  (send main-screen :expose)
	  (send who-line-screen :expose)
	  (when sw (send sw :select))))))))

(defun portrait ()
  "Configure all existing (primary) screens and windows for portrait monitor."
  (lambda-set-height 1016.)
  (with-mouse-usurped
   (lock-sheet (main-screen)
    (lock-sheet (who-line-screen)
      (without-interrupts
	(let ((ms mouse-sheet) (sw selected-window))
	  (when (sheet-me-or-my-kid-p ms main-screen) (setq mouse-sheet nil))
	  (send who-line-screen :deexpose)
	  (send main-screen :deexpose)
	  (setq mouse-sheet ms)

	  (send who-line-screen :change-of-size-or-margins :width 800.)
	  (send main-screen :change-of-size-or-margins :width 800.)

	  (configure-who-line-for-portrait)

	  (mouse-set-sheet main-screen)
	  (send main-screen :expose)
	  (send who-line-screen :expose)
	  (when sw (send sw :select))))))))

(defun configure-who-line-for-landscape ()
  (send who-line-run-state-sheet :change-of-size-or-margins
	:left 328. :right 520.)
  (send who-line-file-state-sheet :change-of-size-or-margins
	:left 520. :right 1024.)
  (send who-line-documentation-window :change-of-size-or-margins
	:width 1024.))

(defun configure-who-line-for-portrait ()
  (send who-line-run-state-sheet :change-of-size-or-margins
	:left 328. :right 480.)
  (send who-line-file-state-sheet :change-of-size-or-margins
	:left 480. :right 800.)
  (send who-line-documentation-window :change-of-size-or-margins
	:width 800.))

;;;

(DEFUN SET-DEFAULT-FONT (FONT-DESCRIPTOR)
  "Make FONT-DESCRIPTOR be the default font.
All windows that were set up to /"use the default font/"
will presently be using FONT-DESCRIPTOR.
FONT-DESCRIPTOR should be a font descriptor, such as the name of a font."
  (SET-STANDARD-FONT :DEFAULT FONT-DESCRIPTOR))

(DEFUN SET-STANDARD-FONT (PURPOSE FONT-DESCRIPTOR)
  "Make FONT-DESCRIPTOR be the standard font for purpose PURPOSE.
All windows that were set up to /"use the font for PURPOSE/"
will presently be using FONT-DESCRIPTOR.
FONT-DESCRIPTOR should be a font descriptor, such as the name of a font."
  (DOLIST (SCREEN ALL-THE-SCREENS)
    (SET-SCREEN-STANDARD-FONT SCREEN PURPOSE FONT-DESCRIPTOR)))

(DEFUN SET-SCREEN-STANDARD-FONT (SCREEN PURPOSE FONT-DESCRIPTOR)
  "Make FONT-DESCRIPTOR be the standard font for purpose PURPOSE on SCREEN.
All windows on SCREEN that were set up to /"use the font for PURPOSE/"
will presently be using FONT-DESCRIPTOR."
  ;; Make absolutely sure we really have a font,
  ;; since if we don't this will wedge everything.
  (LET ((FONT (SEND SCREEN :PARSE-FONT-DESCRIPTOR FONT-DESCRIPTOR))
	FONT-NAME)
    (DO () ((TYPEP FONT 'FONT))
      (SETQ FONT (FONT-EVALUATE
		   (CERROR T NIL :WRONG-TYPE-ARG "~S is not a font name" FONT-DESCRIPTOR))))
    (SETQ FONT-NAME (FONT-NAME FONT))
    (LET* ((STANDARD-NAME (SEND SCREEN :FONT-NAME-FOR PURPOSE T))
	   (OLD-FONT (SYMBOL-VALUE STANDARD-NAME)))
      ;; If the screen has no entry for PURPOSE on its font alist,
      ;; :FONT-NAME-FOR returns T because we supplied that as the default.
      ;; We do that so we can avoid clobbering the font names on the
      ;; DEFAULT-FONT-ALIST.
      (UNLESS (EQ STANDARD-NAME T)
	(SET STANDARD-NAME FONT-NAME)
	(IF (EQ PURPOSE ':DEFAULT)
	    (SEND SCREEN :CHANGE-OF-DEFAULT-FONT
			 (FONT-EVALUATE OLD-FONT) (FONT-EVALUATE FONT-NAME))
	  (SEND SCREEN :CHANGE-OF-DEFAULT-FONT NIL NIL))))))

