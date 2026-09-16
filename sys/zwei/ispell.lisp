;;; -*- Mode:LISP; Package:ZWEI; Base:8; Fonts:CPTFONT; Readtable:T -*-

;;; This code implements the ISPELL interface that can be
;;; used both from ZWEI and the Lisp Listener

;; Bug: check spelling of does't or isn't is confused by the '
;; bug for spaces in certain spots.  optimizations could be done.
;; There are places where the code could be NES'd
;; don't forget to use site info to determine spell hosts.
;; keep local list of correct words, hash table, etc.

;;query replace stuff is hopelessly broken.

;(DEFVAR *ISPELL-INIT-LOADED* NIL "T iff we have loaded the user's ispell init file")

;the above should be done at the oz level, but lets consider it anyway.
						
(DEFUN CORRECT-SPELLING (WORD-OR-WORDLIST &OPTIONAL (STREAM QUERY-IO) IN-EDITOR-P
			   &AUX WORD RESULT)
  "Given a word or string of words, return a list of words which 
corresponds to those word or words spelled correctly.  In the case
where the user has to supply information, ask the questions on stream STREAM.
If IN-EDITOR-P is T, we will modify the buffer to reflect the user's wishes."
  (LET ((RESULTS (CHECK-SPELLING-WORDLIST WORD-OR-WORDLIST))
	(WORDLIST (PARSE-ISPELL-OUTPUT (STRING-APPEND WORD-OR-WORDLIST #/SPACE))))
    (LOOP FOR N FROM 0 TO (1- (LENGTH RESULTS)) ;zero based.
	  DOING
	  (SETQ WORD (NTH N WORDLIST))
	  (SETQ RESULT (NTH N RESULTS))
	  COLLECT
	  (CORRECT-SPELLING-1 WORD RESULT STREAM IN-EDITOR-P))))

(DEFUN CORRECT-SPELLING-1 (WORD RESULT STREAM IN-EDITOR-P)
  "Auxilary function used by CORRECT-SPELLING.  Given a word and the
result given by the spell server, return the correct spelling of a 
given word.   Ask questions of the user on stream STREAM.  If 
IN-EDITOR-P is T,  we will change the buffer to have the correct word in it."
  (COND ((CONSP RESULT)  ;word isn't spelled correctly
	 (IF IN-EDITOR-P (TYPEIN-LINE "Couldn't find it.   Choices listed above."))
	 (LET ((REPLACEMENT
		 (USER-CHOOSE-WORD WORD RESULT STREAM IN-EDITOR-P)))
	   (IF IN-EDITOR-P  ;fix up the screen
	       (SEND STANDARD-OUTPUT ':MAKE-COMPLETE))
	   (AND (NOT (EQUALP REPLACEMENT WORD))
		IN-EDITOR-P
		(REPLACE-WORD-WITH WORD REPLACEMENT
		  (LET ((*QUERY-IO* STREAM))
		    (Y-OR-N-P "Should I query replace your change as well? "))))))
	((STRING-EQUAL "t" RESULT)		;word exists.
	 (IF IN-EDITOR-P (TYPEIN-LINE "Found it."))
	 WORD)
	((STRING-EQUAL "nil" RESULT)		;word is spelled incorrectly
	 (IF IN-EDITOR-P (TYPEIN-LINE "Couldn't find it."))
	 WORD)					;leave it alone.
;;(QQUERY NIL  "Type R to replace the word with a word of your choice,
;;or type A to accept the word as it is." (LIST #/r #/R #/a #/A))
;;(IF (< 3 RESULT) (GET-CORRECT-SPELLING-FROM-USER WORD) WORD))
	(T
	 (FERROR "An unparsable result ~A was obtained.
Please send a bug report to BUG-ISPELL." RESULT))))

(DEFUN CHECK-SPELLING-WORDLIST (WORDLIST)
  "Given a string of words, such as #/"this si a test#/" return a list
of with one element for each word in the wordlist which represents
information about the correct spelling of the wordlist."
  (IF (LISTP WORDLIST) (SETQ WORDLIST (PARSE-LIST-INTO-STRING WORDLIST)))
  (PARSE-ISPELL-OUTPUT (CHAOS:CHECK-SPELLING-WORDLIST WORDLIST)))
   

;Don't bother checking for spelling demons or user options yet (ie. words in the
;lispm's local spelling dictionary.

;;user interface
(DEFUN USER-CHOOSE-WORD (WORD CHOICES &OPTIONAL (STREAM QUERY-IO) IN-EDITOR-P &AUX NEW-WORD)
  "Provide the user with a list of words which may be the word he wants.
We must return a real word, according to what the user said."
  (LET ((RESULT (QQUERY CHOICES
			(FORMAT NIL
				(IF IN-EDITOR-P
				    "Choose the letter corresponding to the correct spelling of the word ~A.
Type ~:@c to leave the word alone,
or type ~C to enter the new spelling from the keyboard.

If you change the word, you will be asked whether to
query-replace all occurrences of it."
				  "Choose the letter corresponding to the correct spelling of the word ~A.
Type ~:@c to leave the word alone,
or type ~C to enter the new spelling from the keyboard.")
				WORD #/SPACE #/R)
			(LIST #/SPACE #/R #/r)
			STREAM)))
    (COND ((STRINGP RESULT)  ;;its the word itself. 
	   (SETQ NEW-WORD RESULT))
	  ((= RESULT 0.)  ;they typed a space.
	   (SETQ NEW-WORD WORD))
	  ((OR (= RESULT 1.) (= RESULT 2.))  ;;they typed in an R.
	   (SETQ NEW-WORD (GET-CORRECT-SPELLING-FROM-USER WORD STREAM))))
    NEW-WORD))

(DEFUN GET-CORRECT-SPELLING-FROM-USER (WORD &OPTIONAL (STREAM QUERY-IO))
  "Ask the user how to spell WORD, and return his reponse as an answer."
  (FORMAT STREAM "~%Please type in the correct spelling of the word ~A.  (End with Return)~&"
	  WORD)
  (READLINE-TRIM STREAM))

;;make this a keyword coded function like fquery.  But this will do for now. 
;;but if char in char-set is also a generatable character (ie a thru s, and r)
(DEFUN QQUERY (LIST-OF-CHOICES &OPTIONAL (STRING-TO-SHOW "") CHAR-SET (STREAM QUERY-IO))
  "Provide another user-choice facility that should be very quick.
Provide a list of choices, for which we want one and only one of those choices
as a value to return.  STRING-TO-SHOW is a string used for documentation.
CHAR-SET is magic list of characters that we will allow the user to type.
If a CHAR in CHAR-SET is typed, return the number corresponding to
which character was typed.  Note that the case is preserved in the CHAR-SET, if you
want to find both a upper and lower case letter, you must include both.
How this function works will be drastically changed in the future,  for
now it just claims to work most of the time."
  ;;this function should be improved, and use keywords for arguments.
  (LET ((L (LENGTH LIST-OF-CHOICES)))
    (COND ((< L 27) ;we can use a one character response.
	   (SEND STREAM ':FRESH-LINE)
	   (SEND STREAM ':LINE-OUT STRING-TO-SHOW)
	   (LOOP FOR N FROM 1 TO L
		 DOING
		 ;;test for lossage cases
		 (SEND STREAM ':LINE-OUT  
		       (FORMAT NIL "~C) ~A" (+ #/A N -1) (NTH (1- N) LIST-OF-CHOICES))))
	   (LET ((N (QQUERY-VALID-CHAR L (MAPCAR #'CHARACTER CHAR-SET))))
	     (IF (> (1+ N) L) (- N L) (NTH N LIST-OF-CHOICES))))
	  (T        ;we can't use a one character response.
	   (LET ((CHOICES-ALIST
		   (LOOP FOR CHOICES IN LIST-OF-CHOICES
			 COLLECT CHOICES)))
		 (TV:MENU-CHOOSE CHOICES-ALIST STRING-TO-SHOW))))))

(DEFUN QQUERY-VALID-CHAR (N &OPTIONAL CHAR-SET &AUX CHAR POS)
  "Return a number in the range of 0 to n-1 which represents a letter of the alphabet
that the user typed.  If the user types a character in CHAR-SET return
N plus the char's position in the CHAR-SET"
  (IF (AND (= N 0) (NULL CHAR-SET))
      (FERROR NIL "There must be at least one valid character to type."))
  (*CATCH 'CHAR
    (LOOP UNTIL NIL ;forever 
	  (SETQ CHAR (SEND QUERY-IO ':TYI))
	  (COND ((SETQ POS (FIND-POSITION-IN-LIST CHAR CHAR-SET))
		 (*THROW 'CHAR (+ N POS)))
		((AND (SETQ CHAR (- (CHAR-UPCASE CHAR) #/A)) (< CHAR N) (> CHAR -1))
		 (*THROW 'CHAR CHAR))
		(T
		 (SEND QUERY-IO ':STRING-OUT
		       (FORMAT NIL "~%Please type ~@[a letter between A and ~C~]~{ or ~:@c~}."
			       (AND (> N 0) (+ #/A N -1)) CHAR-SET))))))) ;;win for 0?

;;ZWEI side of the picture.  We want to implement meta-$ and meta-x correct spelling

(DEFUN CURRENT-WORD-BP () 
  "Return the BP that represents the BP that begins the current word."
  (FORWARD-WORD (FORWARD-WORD (FORWARD-CHAR (POINT) -1 T) 1 T) -1 T))

(DEFCOM COM-CORRECT-WORD-SPELLING
  "Correct the spelling of the word at point.
Uses a SPELL server on some file server host.
If word is incorrect, a list of possible corrections is printed.
You can choose one of them to replace just this occurrence
or all occurrences of the word you checked."
  ()
  ;Figure out what the current word is.  Make it work for end/beginning of buffer.
  (LET* ((BP1 (CURRENT-WORD-BP))
	 (BP2 (FORWARD-WORD BP1 1 T))
	 (WORD (STRING-INTERVAL BP1 BP2)))
;	 (ALPHABETIC-CASE-AFFECTS-STRING-COMPARISON NIL)  ;This should never be T for long.
    (TYPEIN-LINE (STRING-APPEND "Checking the spelling of " WORD #/.)) ;format,
    (CONDITION-CASE ()
	(CORRECT-SPELLING WORD STANDARD-OUTPUT T)  ;are we sure about the stream?
      (:NO-ERROR
       DIS-TEXT) ;;success
      (SYS:NO-SERVER-UP
       (TYPEIN-LINE "No spell server host is up now.")
       DIS-NONE)))
  DIS-TEXT) ;;temp crock

;; lossage in terms of next word!!

;;;fox boo too foo zoo for  fi fo fum mooo moooo bar fdoo moo

(DEFUN REPLACE-WORD-WITH (WORD REPLACEMENT &OPTIONAL QUERY-REPLACE-P BP1 BP2)
  "Replace WORD located between BP1 and BP2 with REPLACEMENT.
If QUERY-REPLACE-P, than query replace whole buffer as well."
  (PREPARE-WINDOW-FOR-REDISPLAY *WINDOW*)
;;foe bar baz for boo too foo fox foo fi fo
  (IF (NULL BP1)
      (SETQ BP1 (CURRENT-WORD-BP)))
  (IF (NULL BP2)
      (SETQ BP2 (FORWARD-WORD BP1 1 T)))
  (LET ((*CASE-REPLACE* T)
	(REPLACEMENT (STRING-DOWNCASE REPLACEMENT))
	(WORD (STRING-DOWNCASE WORD)))  ;for case-replace
    (WITH-UNDO-SAVE ("Spelling correction" BP1 BP2 T)
      (SETQ BP2 (CASE-REPLACE BP1 BP2 REPLACEMENT))
      (MOVE-BP (POINT) BP2))
    (WHEN QUERY-REPLACE-P
      (POINT-PDL-PUSH (COPY-BP (POINT)) *WINDOW*)
      (MOVE-BP (POINT) (INTERVAL-FIRST-BP *INTERVAL*))
      (QUERY-REPLACE (POINT) (INTERVAL-LAST-BP *INTERVAL*)
		     (STRING-DOWNCASE WORD) (STRING-DOWNCASE REPLACEMENT)))))

;for implementing meta-x  Correct spelling
;; must get a bunch of words with theory of com-meta-$ and stuff into
;; chaos packets quickly (we're limited by the size of the packet.

;auxiliary functions for parsing words and spaces into lists and vice versa.


(DEFMACRO EMPTY-STRING? (STRING)
  `(= 0 (LENGTH ,STRING)))

(DEFUN PARSE-LIST-INTO-STRING (LIST &AUX (STRING ""))
  "Given a list such as (a b c) return the string a b c"
  (LOOP FOR ELEMENT IN LIST
	DOING (SETQ STRING (STRING-APPEND STRING (STRING ELEMENT) #/SPACE)))
  (STRING-RIGHT-TRIM #/SPACE STRING))

(DEFUN PARSE-ISPELL-OUTPUT (STRING &AUX (SP-POS 0.) OLD-SP-POS PAREN-POS LIST L)
  "Given what the spell server returns, return a list of real Lisp forms.
Ie. Given  /" nil t (a b c)/" return (/"nil/" /"t/" (/"a/" /"b/" /"c/"))"
  (SETQ L (1- (LENGTH STRING)))
  (LOOP UNTIL NIL ;forever
	DOING
	(SETQ OLD-SP-POS SP-POS)
	(SETQ SP-POS (STRING-SEARCH-CHAR #/SP STRING (1+ OLD-SP-POS)))
	(IF (NOT (= OLD-SP-POS 0)) (INCF OLD-SP-POS))
	(COND ((STRING-EQUAL #/( (SUBSTRING STRING OLD-SP-POS (1+ OLD-SP-POS)))
	       (SETQ PAREN-POS (STRING-SEARCH-CHAR #/) STRING OLD-SP-POS))
	       (SETQ LIST (APPEND LIST (LIST (PARSE-ISPELL-OUTPUT
					       (STRING-APPEND
						 (SUBSTRING
						   STRING
						   (+ 1 OLD-SP-POS)
						   PAREN-POS)
						 #/SPACE)))))
	       (SETQ SP-POS (1+ PAREN-POS)))
	      (T
	       (SETQ LIST (APPEND LIST
				  (LIST
				    (STRING-TRIM #/"  ;strip off those silly quotes
						 (SUBSTRING STRING OLD-SP-POS SP-POS)))))))
	(IF (= SP-POS L) ;there should be a space at the end of the string
	    (LOOP-FINISH)))
  LIST)




