;-*- Mode:LISP; Package:CC; Base:8 -*-
;	** (c) Copyright 1980 Massachusetts Institute of Technology **

(DEFVAR CC-GETSYL-UNRCH NIL)
(DEFVAR CC-GETSYL-UNRCH-TOKEN NIL)
(DEFVAR CC-LOW-LEVEL-FLAG)

(DEFUN CC-GETSYL-RCH NIL 
 (PROG (CH)
	(COND (CC-GETSYL-UNRCH 
		(SETQ CH CC-GETSYL-UNRCH)
		(SETQ CC-GETSYL-UNRCH NIL))
	      (T (COND (CC-LOW-LEVEL-FLAG (CC-REPLACE-STATE)))
		 (SETQ CH (TYI STANDARD-INPUT '3))))
     X	(RETURN CH)))

;Returns: for digits, a number.
;for other alphanumerics, a symbol.
;Otherwise, a symbol whose name starts with "#".
(DEFUN CC-GETSYL-READ-TOKEN NIL 
  (PROG (TOK CH TERM-TOKEN)
	(COND (CC-GETSYL-UNRCH-TOKEN
		(SETQ TOK CC-GETSYL-UNRCH-TOKEN)
		(SETQ CC-GETSYL-UNRCH-TOKEN NIL)
		(RETURN TOK)))
   L	(SETQ CH (CC-GETSYL-RCH))
	(COND ((= CH #\RUBOUT)
	       (OR TOK (RETURN '*RUB*))		;OVER-RUBOUT
	       (SETQ TOK (CDR TOK))
	       (CURSORPOS 'X)
	       (GO L))
	      ((OR ( #/A CH #/Z)
		   ( #/0 CH #/9)
		   (= CH #/.)
		   (= CH #/?))
	       (GO ALPHA-NUM))
	      (( #/a CH #/z)
	       (SETQ CH (CHAR-UPCASE CH))
	       (GO ALPHA-NUM))
	      ((= CH #/-)
	       (GO ALPHA-NUM)))
;DROP THRU ON "SCO"
	(SETQ TERM-TOKEN
	      (INTERN (STRING-APPEND "#"
				     (STRING-UPCASE (FORMAT:OUTPUT NIL
						      (FORMAT:OCHAR CH ':EDITOR))))
		      (SYMBOL-PACKAGE 'FOO)))
  SEP 
  X	(COND (TOK 
	       (SETQ TOK (NREVERSE TOK))
	       (SETQ TOK
		     (COND ((DO L TOK (CDR L) (NULL L)
			      (OR (AND (< 57 (CAR L)) (< (CAR L) 72))
				  (= (CAR L) 55)
				  (= (CAR L) 53)
				  (RETURN T)))
			    (IMPLODE TOK))	;HAS LETTERS OR DOTS IN IT
			   (T (READLIST TOK))))	;A NUMBER (DIGITS, PLUS, MINUS)
		(SETQ CC-GETSYL-UNRCH-TOKEN TERM-TOKEN)
		(RETURN TOK))
	      (TERM-TOKEN
		(RETURN TERM-TOKEN))
	      (T (GO L)))

  ALPHA-NUM
	(SETQ TOK (CONS CH TOK))
	(GO L)))
