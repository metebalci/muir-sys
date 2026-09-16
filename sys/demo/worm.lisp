;;; -*- Mode:Lisp; Package:Hacks; Base:8 -*-

(DECLARE (SPECIAL BITS ORDER WORM-TURNS WORM-X WORM-Y FITP X-WORM Y-WORM WORM-SG))

(DECLARE (SPECIAL WORM-ALU-FUNCTION ORDER WORM-X WORM-Y BITS DIR))

(DEFVAR WORM-WINDOW
	(TV:WINDOW-CREATE 'HOF-WINDOW ':BLINKER-P NIL)
  "The window where the worm is demoed.")

(DEFVAR *CHAR*)

;These are the "character codes" in the worm font
;for the various kinds of spots.
(DEFCONST WORM-BIG-CHAR 5)
(DEFCONST WORM-STRIPE-CHAR 4)
(DEFCONST WORM-GRAY-CHAR 3)
(DEFCONST WORM-BLACK-CHAR 2)

;This is a 6-long array of stack groups,
;each of which runs one worm.
(DEFVAR WORMS
	(LET ((ARRAY (MAKE-ARRAY 6 ':TYPE 'ART-Q-LIST)))
	  (DOTIMES (I 6)
	    (AS-1 (MAKE-STACK-GROUP (FORMAT NIL "WORM-~D" I)) ARRAY I))
	  ARRAY))

(DEFUN PRESET (SG CHAR ALU-FN N)
       (STACK-GROUP-PRESET SG
			   (FUNCTION FLOP)
			   (SYMEVAL CHAR)
			   (SYMEVAL ALU-FN)
			   ORDER
			   WORM-X
			   WORM-Y
			   BITS
			   (* N (^ 3 (1- ORDER)))
			   TERMINAL-IO
			   SYS:%CURRENT-STACK-GROUP))

(DEFUN WORM (&OPTIONAL (BITS 0) (ORDER 7) (WORM-X 222) (WORM-Y 777) 
	     &AUX LENGTH (TERMINAL-IO WORM-WINDOW))
  (TV:WINDOW-CALL (WORM-WINDOW :DEACTIVATE)
    (CATCH-ERROR-RESTART ((SYS:ABORT ERROR) "Exit WORM.")
      (FUNCALL WORM-WINDOW ':SET-LABEL "Worm")
      (OR (BOUNDP 'FONTS:WORM) (LOAD "SYS: LMDEMO;WORMCH" 'FONTS))
      (SETQ LENGTH (^ 3 (1+ ORDER)))
      (PRESET (AR-1 WORMS 0) 'WORM-BIG-CHAR 'TV:ALU-IOR 0)
      (SETQ FITP NIL)
      (DO I 0 (1+ I) (OR FITP ( I 2))		; Paint blackness over whole worm
	  (SETQ FITP T)
	  (FUNCALL TERMINAL-IO ':CLEAR-SCREEN)
	  (DOTIMES (I (1+ LENGTH))
	    (IF (FUNCALL (AR-1 WORMS 0))
		(signal eh:abort-object)))) ;;qit
      (SETQ WORM-X X-WORM WORM-Y Y-WORM)
      (MAPC (FUNCTION PRESET)			; Preset wormlets
	    (G-L-P WORMS)
	    '(WORM-GRAY-CHAR WORM-BLACK-CHAR WORM-STRIPE-CHAR WORM-BLACK-CHAR
			     WORM-BLACK-CHAR WORM-BLACK-CHAR)
	    '(TV:ALU-XOR TV:ALU-ANDCA TV:ALU-IOR TV:ALU-IOR TV:ALU-ANDCA TV:ALU-IOR)
	    '(0 1 2 3 5 6))			;4 is intentionally missing!
      (WORM-COMMAND-LOOP))))

(DEFUN WORM-COMMAND-LOOP (&AUX (YPOS (- (TV:SHEET-INSIDE-HEIGHT TERMINAL-IO)
					(* 3 (TV:SHEET-LINE-HEIGHT TERMINAL-IO)))))
  (DO ((I 0 (1+ I))
       RUN
       (STOP-VAL 0))
      (NIL)
    (COND ((OR RUN (< I STOP-VAL))
	   (AND (FUNCALL TERMINAL-IO ':TYI-NO-HANG)
		(SETQ RUN NIL STOP-VAL 0)))
	  (T (FUNCALL WORM-WINDOW ':SET-LABEL
		      (LET ((BASE 9))
			(FORMAT NIL "Worm    Generation ~S (base 9)" I)))
	     (FUNCALL TERMINAL-IO ':SET-CURSORPOS 0 YPOS)
	     (FUNCALL TERMINAL-IO ':CLEAR-EOL)
	     (FUNCALL TERMINAL-IO ':STRING-OUT
		      "    P: Run  nR: Run until n  nN: Run n steps  nS: Run till nth order  Abort: exit
    ")
	     (PROG (CH VAL)
		   (SETQ VAL 0)
		LOOP (SETQ CH (CHAR-UPCASE (TYI)))
		   (COND ((AND ( CH #/0)( CH #/9))
			  (SETQ VAL (+ (* VAL 9) (- CH #/0)))
			  (GO LOOP))
			 ((EQ CH #/N) (SETQ STOP-VAL (+ VAL I)))
			 ((EQ CH #/R) (SETQ STOP-VAL VAL))
			 ((EQ CH #/S) (SETQ VAL (^ 3 VAL)
					    STOP-VAL (* VAL (1+ (TRUNCATE I VAL)))))
			 ((EQ CH #/P) (SETQ RUN T))))
	     (IF (OR RUN (< I STOP-VAL))
		 (FUNCALL WORM-WINDOW ':SET-LABEL "Worm    Type any character to stop"))))
    (DOTIMES (I 6)
      (IF (FUNCALL (AR-1 WORMS I))
	  (SIGNAL EH:ABORT-OBJECT)))))

(OR (BOUNDP 'WORM-TURNS) (SETQ WORM-TURNS (MAKE-ARRAY 12. ':TYPE 'ART-Q-LIST)))

(FillArray WORM-TURNS '( 6  0
			 3  5
			-3  5
			-6  0
			-3 -5
			 3 -5))

;This is the coroutining function for each worm.
;Returns to the calling stack group with NIL normally,
;T if the user typed Abort.
(DEFUN FLOP (*CHAR* WORM-ALU-FUNCTION ORDER WORM-X WORM-Y BITS SNOOZE TERMINAL-IO WORM-SG)
  (CATCH-ERROR-RESTART ((SYS:ABORT ERROR) "Return to Worm command level.")
    (DO I 0 (1+ I) ( I SNOOZE)
	(STACK-GROUP-RETURN NIL))
    (DO ((I 0 (1+ I))
	 (DIR (BOOLE 4 (- ORDER) 1)))
	(NIL)
      (TERD ORDER BITS)
      (WORM-STEP)
      (SETQ X-WORM WORM-X Y-WORM WORM-Y)
      (SETQ DIR (+ DIR 4))))
  (DO () (()) (STACK-GROUP-RETURN T)))

(DEFUN TERD (N BITS)
   (IF (PLUSP N)
          (COND ((Bit-Test BITS 1)
                   (TERD (1- N) (LSH BITS -1))
                   (SETQ DIR (- DIR -2))
                   (WORM-STEP)
                   (SETQ DIR (- DIR 4))
                   (TERD (1- N) (LSH BITS -1))
                   (WORM-STEP)
                   (SETQ DIR (+ DIR 2))
                   (TERD (1- N) (LSH BITS -1)))
                (T (TERD (1- N) (LSH BITS -1))
                   (WORM-STEP)
                   (SETQ DIR (+ DIR 4))
                   (TERD (1- N) (LSH BITS -1))
                   (SETQ DIR (- DIR 2))
                   (WORM-STEP)
                   (SETQ DIR (- DIR 2))
                   (TERD (1- N) (LSH BITS -1))))))
	    
(DEFUN WORM-STEP ()
   (CLIP 'WORM-X (TV:SHEET-INSIDE-WIDTH TERMINAL-IO) (SETQ DIR (\ (+ 12. DIR) 12.)))
   (CLIP 'WORM-Y (- (TV:SHEET-INSIDE-HEIGHT TERMINAL-IO) 55) (1+ DIR))
   (TV:PREPARE-SHEET (TERMINAL-IO)
      (TV:%DRAW-CHAR FONTS:WORM *CHAR* WORM-X WORM-Y WORM-ALU-FUNCTION TERMINAL-IO))
   (STACK-GROUP-RETURN NIL))

(DEFUN CLIP (Z N D)
       (SELECTQ (TRUNCATE (+ N (SET Z (+ (SYMEVAL Z) (AR-1 WORM-TURNS D))))
			  N)
            (0 (SET Z 1) (SETQ FITP NIL))
            (1)
            (2 (SET Z (1- N)) (SETQ FITP NIL))))

(DEFDEMO "Worm" "Pretty fractal patters, by Gosper and Holloway." (WORM))
