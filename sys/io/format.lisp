; -*- Mode:LISP; Package:FORMAT; Readtable:ZL; Base:10 -*-
;; Function for printing or creating nicely formatted strings.
;	** (c) Copyright 1980 Massachusetts Institute of Technology **

;*** When there is a garbage collector that works well, all the crappy manual
;*** storage allocation in this program should be removed.  It will probably
;*** get a lot faster.

;;; FORMAT prints several arguments according to a control argument.
;;; The control argument is either a string or a list of strings and lists.
;;; The strings and lists are interpreted consecutively.
;;; Strings are for the most part just printed, except that the character ~
;;; starts an escape sequence which directs other actions.
;;; A ~ escape sequence has an (optional) numeric parameter followed by a mode character.
;;; These escape actions can use up one or more of the non-control arguments.
;;; A list in the control-argument list is also interpreted as an escape.
;;; Its first element is the mode, a symbol which may be any length,
;;; and its remaining elements are parameters.  The list (D 5) is equivalent
;;; to the ~ escape "~5D";  similarly, each ~ escape has an equivalent list.
;;; However, there are list escapes which have no ~ equivalent.

;;; Any undefined list escape is simply evaluated.

;;;Further documentation is at the head of the function FORMAT.

;;; (FORMAT <stream> <control arg> &REST <args>)
;;; If <stream> is NIL, cons up and return a string.
;;; If <stream> is T, use *STANDARD-OUTPUT* (saves typing).

(DEFVAR FORMAT-STRING)		;The string used for output by (FORMAT NIL ...)
(DEFVAR FORMAT-PACKAGE (SYMBOL-PACKAGE 'FOO));Where format commands are interned.
(DEFVAR FORMAT-CLAUSES-ARRAY NIL)	;Internal "pseudo-resource"s
(DEFVAR FORMAT-STACK-ARRAY NIL)
(DEFVAR FORMAT-STRING-BUFFER-ARRAY NIL)

(DEFVAR CTL-STRING)		;The control string.
(DEFVAR CTL-LENGTH)		;STRING-LENGTH of CTL-STRING.
(DEFVAR CTL-INDEX)		;Our current index into the control string.  This
				;  is used by the conditional command.
(DEFVAR ATSIGN-FLAG)		;Modifier
(DEFVAR COLON-FLAG)		;Modifier
(DEFVAR FORMAT-PARAMS)		;Array for pushing parameters
(DEFVAR FORMAT-TEMPORARY-AREA COMPILER::FASL-TEMP-AREA)	 ;For temporary consing
(DEFVAR FORMAT-ARGLIST)		;The original arg list, for ~@*.
(DEFVAR LOOP-ARGLIST)		;Loop arglist, for ~:^.
(DEFVAR FORMAT-CHAR-TABLE)	;Table of single-char symbols, for fast interning.
(DEFVAR ROMAN-OLD)

(DEFMACRO DEFFORMAT (DIRECTIVE (ARG-TYPE) LAMBDA-LIST &BODY BODY)
  "Define a format directive named DIRECTIVE (a symbol).
If DIRECTIVE is in the FORMAT package and its name is one character long,
you can use this directive by writing that character after a ~ in a format string.
Otherwise, then you must use the ~\...\ syntax to use this directive.
ARG-TYPE is a keyword saying how many format arguments this directive uses up.
It can be :NO-ARG, :ONE-ARG or :MULTI-ARG.
:NO-ARG means this directive doesn't use any of the format args (like ~T or ~%).
 LAMBDA-LIST should receive one argument,
 which will be a list of the parameters given (such as 3 and 5 in ~3,5T).
:ONE-ARG means this directive uses one format arg (like ~D).
 LAMBDA-LIST should receive two args,
 the first being one format arg and the second being the list of parameters given.
:MULTI-ARG means this directive decides how many format args to use up (like ~n*).
 LAMBDA-LIST should receive two args,
 the first being the list of format args and the second being the list of parameters given.
 Then the BODY should return as a value the list of format args left over."
  `(DEFUN (:PROPERTY ,DIRECTIVE ,(ECASE ARG-TYPE
				   (:NO-ARG 'FORMAT-CTL-NO-ARG)
				   (:ONE-ARG 'FORMAT-CTL-ONE-ARG)
				   (:MULTI-ARG 'FORMAT-CTL-MULTI-ARG)))
	  (,@LAMBDA-LIST &AUX (*FORMAT-OUTPUT* *STANDARD-OUTPUT*))
     *FORMAT-OUTPUT*				;Prevent unused variable warning.
     . ,BODY))

(defmacro get-format-buffer (variable make-array)
  `(or (do ((val)) (())
	 (setq val ,variable)
	 (when (%store-conditional (locf ,variable) val nil)
	   (if val (setf (fill-pointer val) 0))
	   (return val)))
       ,make-array))
(defmacro return-format-buffer (array variable)
  `(unless (%store-conditional (locf ,variable) nil ,array)
     (return-storage (prog1 ,array (setq ,array nil)))))

;;; Make FORMAT-CHAR-TABLE into an array whose i'th element is the
;;; symbol, in FORMAT-PACKAGE, whose pname is the character whose code is i.
;;; This provides a fast alternative to INTERN-SOFT, for single-character symbols.
;;; CHARS is the list of symbols to put in the table.
;;; All single-character FORMAT operations must be included.
(DEFUN FORMAT-INIT-CHAR-TABLE (CHARS)
  (SETQ FORMAT-CHAR-TABLE (MAKE-ARRAY #o200))
  (DO ((CHARS CHARS (CDR CHARS))) ((NULL CHARS))
    (SETF (AREF FORMAT-CHAR-TABLE
		(CHAR-CODE (CHAR (SYMBOL-NAME (CAR CHARS)) 0)))
	  (CAR CHARS))))

(LET ((CHARS '(A B C D E F G O P R Q S T V X [ ] /; % /| < > * &   ^  { } ~ $ ? /( /))))
  (FORMAT-INIT-CHAR-TABLE CHARS))


;;; Little arrays in which to cons up lists of parameters
(DEFRESOURCE FORMAT-PARAMS ()
  :CONSTRUCTOR (MAKE-ARRAY 10. :TYPE 'ART-Q-LIST :FILL-POINTER 0)
  :INITIAL-COPIES 6)


(DEFUN MAKE-STRING-OUTPUT-STREAM (&OPTIONAL STRING START-INDEX EXTRA-ARG)
  "Return a stream that accumulates output in a string.
If STRING is specified, output is STRING-NCONC'd onto it.
Otherwise a new string is created and used;
GET-OUTPUT-STREAM-STRING can be used on the stream to get the accumulated string."
  ;; We need hair here to detect calls that use the old calling sequence
  ;; where the first argument was a Common Lisp thing not really used
  ;; and STRING was the second argument.
  (IF (STRINGP START-INDEX)
      (LET ((STRING START-INDEX)
	    (START-INDEX EXTRA-ARG))
	(LET-CLOSED ((FORMAT-STRING
		       (OR STRING (MAKE-STRING 128. :FILL-POINTER 0))))
	  (IF START-INDEX
	      (SETF (FILL-POINTER FORMAT-STRING) START-INDEX))
	  'FORMAT-STRING-STREAM))
    (LET-CLOSED ((FORMAT-STRING
		   (OR STRING (MAKE-STRING 128. :FILL-POINTER 0))))
      (IF START-INDEX
	  (SETF (FILL-POINTER FORMAT-STRING) START-INDEX))
      'FORMAT-STRING-STREAM)))

(DEFUN GET-OUTPUT-STREAM-STRING (STREAM)
  "Return the string of characters accumulated so far by STREAM.
STREAM must be a stream made by MAKE-OUTPUT-STRING-STREAM.
This clears the stream's data, so that if GET-OUTPUT-STREAM-STRING is called
a second time it will only get the data output after the first time it was called."
  (SEND STREAM 'EXTRACT-STRING))


(DEFPROP FORMAT-STRING-STREAM T SI:IO-STREAM-P)
;;; (FORMAT NIL ...) outputs to this stream, which just puts the characters
;;; into the string FORMAT-STRING.
(DEFSELECT (FORMAT-STRING-STREAM FORMAT-STRING-STREAM-DEFAULT-HANDLER)
  (:TYO (CH)
   (OR FORMAT-STRING (SETQ FORMAT-STRING (MAKE-STRING 128. :FILL-POINTER 0)))
   (VECTOR-PUSH-EXTEND CH FORMAT-STRING))

  (:STRING-OUT (STRING &OPTIONAL (FIRST 0) LAST &AUX NEW-LENGTH)
   (OR FORMAT-STRING (SETQ FORMAT-STRING (MAKE-STRING 128. :FILL-POINTER 0)))
   (SETQ LAST (OR LAST (ARRAY-ACTIVE-LENGTH STRING)))
   (SETQ NEW-LENGTH (+ (FILL-POINTER FORMAT-STRING) (- LAST FIRST)))
   (AND (< (ARRAY-LENGTH FORMAT-STRING) NEW-LENGTH)
	(ADJUST-ARRAY-SIZE FORMAT-STRING NEW-LENGTH))
   (COPY-ARRAY-PORTION STRING FIRST LAST
		       FORMAT-STRING (FILL-POINTER FORMAT-STRING) NEW-LENGTH)
   (SETF (FILL-POINTER FORMAT-STRING) NEW-LENGTH))

  (:READ-CURSORPOS (&OPTIONAL (MODE :CHARACTER) &AUX POS)
   (OR FORMAT-STRING (SETQ FORMAT-STRING (MAKE-STRING 128. :FILL-POINTER 0)))
   (OR (EQ MODE :CHARACTER)
       (FERROR NIL "Strings only have a width in ~S, not ~S" :CHARACTER MODE))
   (SETQ POS (STRING-REVERSE-SEARCH-CHAR #/NEWLINE FORMAT-STRING))
   (VALUES (- (STRING-LENGTH FORMAT-STRING) (IF POS (+ POS 1) 0))
	   0))

  (:INCREMENT-CURSORPOS (DX DY &OPTIONAL (MODE :CHARACTER) &AUX NEWLEN)
   (OR FORMAT-STRING (SETQ FORMAT-STRING (MAKE-STRING 128. :FILL-POINTER 0)))
   (UNLESS (EQ MODE :CHARACTER)
     (FERROR NIL "Strings can only have a width in ~S, not ~S" :CHARACTER MODE))
   (OR (AND (ZEROP DY) (NOT (MINUSP DX)))
       (FERROR NIL "Cannot do this ~S" :INCREMENT-CURSORPOS))
   (SETQ NEWLEN (+ (STRING-LENGTH FORMAT-STRING) DX))
   (AND (< (ARRAY-LENGTH FORMAT-STRING) NEWLEN)
	(ADJUST-ARRAY-SIZE FORMAT-STRING NEWLEN))
   (DO ((I (STRING-LENGTH FORMAT-STRING) (1+ I)))
       (( I NEWLEN))
     (SETF (CHAR FORMAT-STRING I) #/SPACE))
   (SETF (FILL-POINTER FORMAT-STRING) NEWLEN))

  (:SET-CURSORPOS (X Y &OPTIONAL (MODE :CHARACTER) &AUX POS DELTA NEWLEN)
   (OR FORMAT-STRING (SETQ FORMAT-STRING (MAKE-STRING 128. :FILL-POINTER 0)))
   (UNLESS (EQ MODE :CHARACTER)
     (FERROR NIL "Strings can only have a width in ~S, not ~S" :CHARACTER MODE))
   (SETQ POS (STRING-REVERSE-SEARCH-SET '(#/NEWLINE #/LINE #/FORM) FORMAT-STRING)
	 DELTA (- X (- (STRING-LENGTH FORMAT-STRING) (IF POS (+ POS 1) 0))))
   (OR (AND (ZEROP Y) (PLUSP DELTA))
       (FERROR NIL "Cannot do this ~S" :SET-CURSORPOSE))
   (SETQ NEWLEN (+ (STRING-LENGTH FORMAT-STRING) DELTA))
   (AND (< (ARRAY-LENGTH FORMAT-STRING) NEWLEN)
	(ADJUST-ARRAY-SIZE FORMAT-STRING NEWLEN))
   (DO ((I (STRING-LENGTH FORMAT-STRING) (1+ I)))
       (( I NEWLEN))
     (SETF (CHAR FORMAT-STRING I) #/SPACE))
   (SETF (FILL-POINTER FORMAT-STRING) NEWLEN))
  (:UNTYO-MARK () (FILL-POINTER FORMAT-STRING))
  (:UNTYO (MARK) (SETF (FILL-POINTER FORMAT-STRING) MARK))
  (EXTRACT-STRING ()
   (PROG1 FORMAT-STRING
	  (SETQ FORMAT-STRING NIL)))
  (:FRESH-LINE ()
   (WHEN (NOT (OR (NULL FORMAT-STRING)
		  (ZEROP (STRING-LENGTH FORMAT-STRING))
		  (CHAR= (CHAR FORMAT-STRING (1- (STRING-LENGTH FORMAT-STRING))) #/NEWLINE)))
     (VECTOR-PUSH-EXTEND #/NEWLINE FORMAT-STRING)
     T)))

(DEFUN FORMAT-STRING-STREAM-DEFAULT-HANDLER (OP &OPTIONAL ARG1 &REST REST)
  (STREAM-DEFAULT-HANDLER 'FORMAT-STRING-STREAM OP ARG1 REST))


(DEFUN FORMAT (STREAM CTL-STRING &REST ARGS)
  "Format arguments according to a control string and print to a stream.
/(If the stream is T, *STANDARD-OUTPUT* is used;
 if NIL, a string is returned containing the formatted text.)
The control string is copied to the stream, but ~ indicates special formatting commands.
~D  ~mincol,padchar,commacharD   Print number as a decimal integer.
    ~:D  Print the comma character every three digits.
    ~@D  Always print the sign.   ~:@D  Both.
~O  Analogous to ~D, but prints in octal.
~X  Analogous to ~D, but prints in hex.
~B  Analogous to ~X, but prints in binary.
~F  ~w,d,s,overflowchar,padcharF  Print float in nonexponential notation.
    Multiplies by 10^s before printing if s is specified.
    Prints in w positions, with d digits after the decimal point.
    Pads on left with padchar if nec.  If number doesn't fit in w positions,
    and overflowchar is specified, just fills the w positions with that character.
~E  ~w,d,e,s,overflowchar,padchar,exptcharE   Print float in exponential notation.
    Prints in w positions, with e digits of exponent.
    If s (default is 1) is positive, prints s digits before point, d-s+1 after.
    If s is zero, prints d digits after the point, and a zero before if there's room.
    If s is negative, prints d digits after the point, of which the first -s are zeros.
    If exptchar is specified, it is used to delimit the exponent
    (instead of /"e/" or whatever.)
    If overflowchar is specified, then if number doesn't fit in specified width,
    or if exponent doesn't fit in e positions, field is filled with overflowchar instead.
~G  Like ~E, but if number fits without exponent, prints without one.
~$  ~w,x,y,z$ prints a floating-point number with exactly w (default 2) digits to right of
     decimal, at least x (default 1) to left of decimal, right-justified in field y wide
     padded with z.  @ print + sign.  : sign to left of padding.
~R  ~R  Print number as an English cardinal number.
    ~:R  English ordinal number.   ~@R  Roman numeral.   ~:@R  Old Roman numeral.
    ~nR  Print number in radix n.  Thus ~8R = ~O, and ~10R = ~D.
    Extra parameters are as for ~D (~n,mincol,padchar,commacharR).
~A  Ascii output (PRINC).  Good for printing strings.  ~mincol,colinc,minpad,padcharA.
    ~@A  Right-justify the string.   ~:A  Make NIL print as ().  ~:@A  Both.
~S  Analogous to ~A, but uses PRIN1, not PRINC.
~C  Print a character.  Mouse characters print in standard format.
    ~C  Actual character, preceded by /"c-/", /"m-/", /"s-/" or /"h-/" if necessary.
    ~:C  Format effectors print as names.  Names of control bits (/"Control-/") precede.
    ~@C  Prints the character in READ format, using #\.
    ~:@C  Like ~:C, but top/front/greek characters are followed by remark, e.g. /" (Top-S)/".
~*  Ignore an argument.   ~n*  Ignore n arguments.   ~:n*  Back up n arguments (default 1).
    ~n@* Go to argument n.
~%  Insert a newline.     ~n%  Insert n newlines.
~~  Insert a tilde.       ~n~  Insert n tildes.
~|  Insert a form.        ~n|  Insert n forms.
    ~:|  Do :CLEAR-SCREEN if the stream supports it, otherwise insert a form.   ~:n|  Similar.
~<cr>  Ignore a CR and following whitespace in the control string.
    ~:<cr> Ignore the CR, retain the whitespace.  ~@<cr> Retain the CR, ignore the whitespace.
~&  Do a :FRESH-LINE.     ~n&  Do a FRESH-LINE, then insert n-1 newlines.
~^  Terminate processing if no more arguments.  Within ~{...~}, just terminate the loop.
    ~n;  Terminate if n is zero.  ~n,m;  Terminate if n=m.  ~n,m,p;  Terminate if nmp.
    ~:^  When within ~:{...~}, ~^ terminates this iteration.  Use ~:^ to exit the loop.
~T  ~mincol,colincT  Tab to column mincol+p*colinc, for the smallest integer p possible.
    ~mincol,colinc:T  Same, but tabs in TV pixels rather than characters.
    ~n@T  Insert n spaces.
    ~n,colinc@T   Insert n spaces, then move 0 or more up to multiple of colinc.
~Q  Apply next argument to no arguments.  ~a,b,c,...,zQ  Apply next argument to parameters
    a,b,c,...z.  In (Q ...) form, apply argument to unevaled parameters.
~P  Pluralize.  Insert /"s/", unless argument is 1.
    ~:P  Use previous argument, not next one (i.e. do ~:* first).
    ~@P  Insert /"y/" if argument is 1, otherwise insert /"ies/".   ~:@P  Both.
~(  ~(...~)  Force lower case for the output generated within.
    ~:(...~)  Similar but capitalize each word.
    ~@(...~)  Similar but capitalize the first word.
    ~:@(...~)  Similar but force all upper case.
    ~1(...~)  Force first letter of first word to upper case, leave all else alone.
~?  Indirect.  Uses up two args; first is a format string, second is args for it.
    ~@? uses up one arg directly, as a format string, but it operates on
    the remaining format args and can use them up.
~<  ~mincol,colinc,minpad,padchar<str0~;str1~;...~;strn~>  Do formatting for all formatting
    strings strj; then output all strings with padding between them at the ~; points.
    Each padding point must have at least minpad padding characters.  Subject to that,
    the total width must be at least mincol, and must be mincol+p*colinc for some p.
    If str0 is followed by ~:; instead of ~;, then str0 is not normally output, and the
    ~:; is not a padding point.  Instead, after the total width has been determined,
    if the text will not fit into the current line of output, then str0 is output before
    outputting the rest.  (Doesn't work when producing a string.)  An argument n (~:n;)
    means that the text plus n more columns must fit to avoid outputting str0.  A second
    argument m (~n,m:;) provides the line width to use instead of the stream's width.
    ~:<  Also have a padding point at the left.  Hence ~n:<x~> right-justifies x in n columns.
    ~@<  Also have a padding point at the right.   ~:@<  Both.   Hence ~n:@<x~> centers x.
~[  ~[str0~;str1~;...~;strn~]  Select.  Argument selects one clause to do.  If argument is not
    between 0 and n inclusive, then no alternative is performed.  If a parameter is given,
    then use the parameter instead of an argument.  (The only useful one is /"#/".)
    If the last string is preceded by ~:;, it is an /"else/" clause, and is processed if
    no other string is selected.
    One can also tag the clauses explicitly by giving arguments to ~;.  In this case the
    first string must be null, and arguments to ~; tag the following string.  The
    argument is matched against the list of parameters for each ~;.  One can get ranges
    of tags by using ~:;.  Pairs of parameters serve as inclusive range limits.
    A ~:; with no parameters is still an /"else/" clause.
    Example:  ~[~'+,'-,'*,'////;operator~:'A,'Z,'a,'z;letter~:'0,'9;digit~:;other~]
    will produce /"operator/", /"letter/", /"digit/", or /"other/" as appropriate.
    ~:[iffalse~;iftrue~]  The argument selects the first clause if nil, the second if non-nil.
    ~@[str~]  If the argument is non-nil, then it is not swallowed, and str is processed.
    Otherwise, the nil is swallowed and str is ignored.  Thus ~@[~S~] will PRIN1 a
    non-null thing.
~{  ~{str~}  Use str as a format string for each element in the argument.  More generally,
    the argument is a list of things to be used as successive arguments, and str is used
    repeatedly as a format string until the arguments are exhausted (or ~^ is used).
    Within the iteration the commands ~* and ~@* move among the iteration arguments,
    not among all the arguments given to FORMAT.
    ~n{str~} repeats the string at most n times.
    Terminating with ~:} forces str to be processed at least once.
    ~:{str}  The argument is a list of lists, and each repetition sees one sublist.
    ~@{str}  All remaining arguments are used as the list.
    ~:@{str}  Each remaining argument is a list.
    If the str within a ~{ is empty, then an argument (which must be a string) is used.
    This argument precedes any that are iterated over as loop arguments.
~  ~str~ Successive lines within str are indented to align themselves with the column
    at which str began. ie all text within str will lie to the right of the beginning of str
In place of a numeric parameter, one may use V, which uses an argument to supply the number;
or one may use #, which represents the number of arguments remaining to be processed;
or one may use 'x, which uses the ascii value of x (good for pad characters).
The control string may actually be a list of intermixed strings and sublists.
In that case, the strings are printed literally.  The first atom in a sublist should be
the name of a command, and remaining elements are parameters."
  (LET-IF (NULL STREAM)
	  ;; Only bind FORMAT-STRING if STREAM is NIL.  This avoids lossage if
	  ;; FORMAT with a first arg of NIL calls FORMAT recursively (e.g. if
	  ;; printing a named structure).
	  ((FORMAT-STRING (get-format-buffer format-string-buffer-array
					     (make-string 128. :fill-pointer 0
							       :area format-temporary-area))))
    (LET-IF (STRINGP STREAM)
	    ((FORMAT-STRING STREAM))
      (LET ((*STANDARD-OUTPUT* (COND ((OR (NULL STREAM)
					  (STRINGP STREAM)) 'FORMAT-STRING-STREAM)
				     ((EQ STREAM T) *STANDARD-OUTPUT*)
				     (T STREAM)))
	    (FORMAT-ARGLIST ARGS)
	    (LOOP-ARGLIST NIL))
	(CATCH 'FORMAT-/:^-POINT
	  (CATCH 'FORMAT-^-POINT
            (COND ((STRINGP CTL-STRING)
		   (FORMAT-CTL-STRING ARGS CTL-STRING))
		  ((ERRORP CTL-STRING)
		   (PRINC CTL-STRING))
		  ((SYMBOLP CTL-STRING)
		   (FORMAT-CTL-STRING ARGS (GET-PNAME CTL-STRING)))
		  (T (DO ((CTL-STRING CTL-STRING (CDR CTL-STRING))) ((NULL CTL-STRING))
		       (IF (STRINGP (CAR CTL-STRING))
			   (SEND *STANDARD-OUTPUT* :STRING-OUT (CAR CTL-STRING))
			 (SETQ ARGS (FORMAT-CTL-LIST ARGS (CAR CTL-STRING)))))))))))
      ;; Copy returned string out of temporary area and reclaim
      (WHEN (NULL STREAM)			;return string or nil
	(PROG1 (SUBSTRING FORMAT-STRING 0)
	       (return-format-buffer format-string format-string-buffer-array)))))


;;; Call this to signal an error in FORMAT processing.  If CTL-STRING is a string, then
;;; CTL-INDEX should point one beyond the place to be indicated in the error message.

(DEFUN FORMAT-ERROR (STRING &REST ARGS)
  (IF (STRINGP CTL-STRING)
      (FERROR NIL "~1{~:}~%~VT~%   /"~A/"~%" STRING ARGS
	      (- CTL-INDEX
		 1
		 (OR (STRING-REVERSE-SEARCH-CHAR #/NEWLINE CTL-STRING CTL-INDEX)
		     -4))
	      CTL-STRING)
    (FERROR NIL "~1{~:}" STRING ARGS)))
(DEFPROP FORMAT-ERROR T :ERROR-REPORTER)

(DEFUN FORMAT-CTL-LIST (ARGS CTL-LIST &AUX (ATSIGN-FLAG NIL) (COLON-FLAG NIL))
  (FORMAT-CTL-OP (COND ((GETL (CAR CTL-LIST)
			      '(FORMAT-CTL-ONE-ARG FORMAT-CTL-NO-ARG
				FORMAT-CTL-MULTI-ARG FORMAT-CTL-REPEAT-CHAR))
			(CAR CTL-LIST))
		       (T (INTERN-LOCAL-SOFT (CAR CTL-LIST) FORMAT-PACKAGE)))
		 ARGS (CDR CTL-LIST)))

(DEFUN FORMAT-CTL-STRING (ARGS CTL-STRING &AUX (FORMAT-PARAMS NIL))
  (UNWIND-PROTECT
      (DO ((CTL-INDEX 0)
	   (CTL-LENGTH (ARRAY-ACTIVE-LENGTH CTL-STRING))
	   (TEM))
	  (( CTL-INDEX CTL-LENGTH))
	(SETQ TEM (%STRING-SEARCH-CHAR #/~ CTL-STRING CTL-INDEX CTL-LENGTH))
	(COND ((NEQ TEM CTL-INDEX)			;Put out some literal string
	       (SEND *STANDARD-OUTPUT* :STRING-OUT CTL-STRING CTL-INDEX TEM)
	       (IF (NULL TEM) (RETURN))
	       (SETQ CTL-INDEX TEM)))
	;; (CHAR CTL-STRING CTL-INDEX) is a tilde.
	(LET ((ATSIGN-FLAG NIL)
	      (COLON-FLAG NIL))
	  (IF (NULL FORMAT-PARAMS) 
	      (SETQ FORMAT-PARAMS (ALLOCATE-RESOURCE 'FORMAT-PARAMS)))
	  (SETF (FILL-POINTER FORMAT-PARAMS) 0)
	  (MULTIPLE-VALUE (TEM ARGS) (FORMAT-PARSE-COMMAND ARGS T))
	  (SETQ ARGS (FORMAT-CTL-OP TEM ARGS (G-L-P FORMAT-PARAMS)))))
    (AND FORMAT-PARAMS (DEALLOCATE-RESOURCE 'FORMAT-PARAMS FORMAT-PARAMS)))
  ARGS)

;;; Expects ATSIGN-FLAG, COLON-FLAG, and FORMAT-PARAMS to be bound.
;;; CTL-INDEX points to a tilde.  Returns command name and new ARGS,
;;; leaving CTL-INDEX after the command.  NIL for the command name
;;; means no command there
;;; If SWALLOW-ARGS is NIL, we are not executing commands, just parsing,
;;; e.g. to find a matching ~}, ~], or ~>.  So don't swallow any args (e.g. for ~V).
(DEFUN FORMAT-PARSE-COMMAND (ARGS SWALLOW-ARGS)
  (DO ((PARAM-FLAG NIL)		;If T, a parameter has been started in PARAM
       (START CTL-INDEX)	;for error message
       (CH)
       (TEM)
       (SYM)
       (SIGN NIL)		;Sign of parameter currently being constructed.
       (PARAM NIL))		;PARAM is the parameter currently being constructed
      (( (SETQ CTL-INDEX (1+ CTL-INDEX)) CTL-LENGTH)
       (SETQ CTL-INDEX (1+ START))
       (FORMAT-ERROR "Command fell off end of control string"))
    (SETQ CH (CHAR-UPCASE (CHAR CTL-STRING CTL-INDEX)))
    (COND ((CHAR #/0 CH #/9)	;DIGIT-CHAR-P not loaded yet
	   (SETQ TEM (- CH #/0))
	   (SETQ PARAM (+ (* (OR PARAM 0) 10.) TEM)
		 PARAM-FLAG T))
	  ((CHAR= CH #/-)
	   (SETQ SIGN (NOT SIGN)))
	  ((CHAR= CH #/+) NIL)
	  ((CHAR= CH #/@)
	   (SETQ ATSIGN-FLAG T))
	  ((CHAR= CH #/:)
	   (SETQ COLON-FLAG T))
	  ((CHAR= CH #/V)
	   (WHEN (AND (NULL ARGS) SWALLOW-ARGS)
	     (INCF CTL-INDEX)
	     (FORMAT-ERROR "No argument for V parameter to use"))
	   (SETQ PARAM (POP ARGS) PARAM-FLAG T))
	  ((CHAR= CH #/#)
	   (SETQ PARAM (LENGTH ARGS) PARAM-FLAG T))
	  ((CHAR= CH #/')
	   (SETQ PARAM (CHAR-CODE (CHAR CTL-STRING (INCF CTL-INDEX))) PARAM-FLAG T))
	  ((CHAR= CH #/,)		;comma, begin another parameter
	   (AND SIGN PARAM (SETQ PARAM (- PARAM)))
	   (VECTOR-PUSH PARAM FORMAT-PARAMS)
	   (SETQ PARAM NIL PARAM-FLAG T SIGN NIL))	;omitted arguments made manifest by
							; presence of comma are NIL
	  ((CHAR= CH #/NEWLINE)		;No command, just ignoring a CR
	   (INCF CTL-INDEX)			;Skip the newline
	   (OR COLON-FLAG			;Unless colon, skip whitespace on next line
	       (DO () ((OR ( CTL-INDEX CTL-LENGTH)
			   (NOT (MEMQ (CHAR CTL-STRING CTL-INDEX) '(#/SPACE #/TAB)))))
		 (INCF CTL-INDEX)))
	   (RETURN 'CRLF ARGS))
	  (T					;Must be a command character
	   (INCF CTL-INDEX)			;Advance past command character
	   (AND SIGN PARAM (SETQ PARAM (- PARAM)))
	   (AND PARAM-FLAG (VECTOR-PUSH PARAM FORMAT-PARAMS))
	   (SETQ PARAM-FLAG NIL PARAM NIL TEM NIL)
	   ;; SYM gets the symbol for the operation to be performed.
	   (IF (CHAR= CH #/\)
	       (LET ((I (STRING-SEARCH-CHAR #/\ CTL-STRING CTL-INDEX))
		     (*PACKAGE* FORMAT-PACKAGE))
		 (AND (NULL I)
		      (FORMAT-ERROR "Unmatched \ in control string."))
		 (SETQ SYM (READ-FROM-STRING CTL-STRING NIL CTL-INDEX I))
		 (SETQ CTL-INDEX (1+ I)))
#| This cannot work properly due to variablity of readtable.
   So, we have to use slow read every time to win.
   Of course, this format op is not commonlisp, but still...
		         (LET ((L (LENGTH TEM)))
			   (IF (OR (%STRING-SEARCH-CHAR #/: TEM 0 L)
				   (%STRING-SEARCH-CHAR #/| TEM 0 L)
				   (%STRING-SEARCH-CHAR #// TEM 0 L))
			     (SETQ SYM (READ-FROM-STRING TEM))
			   (SETQ SYM (INTERN-SOFT (STRING-UPCASE TEM)
						  FORMAT-PACKAGE))))
|#
	       (SETQ SYM (OR (AREF FORMAT-CHAR-TABLE CH)
			     (INTERN-SOFT CH FORMAT-PACKAGE))))
	   (RETURN (VALUES SYM ARGS))))))

;;; Perform a single formatted output operation on specified args.
;;; Return the remaining args not used up by the operation.
(DEFUN FORMAT-CTL-OP (OP ARGS PARAMS &AUX TEM)
  (COND ((NULL OP) (FORMAT-ERROR "Undefined ~S command." 'FORMAT)	;eg not interned
		   ARGS)
	((SETQ TEM (GET OP 'FORMAT-CTL-ONE-ARG))
	 (FUNCALL TEM (CAR ARGS) PARAMS)
	 (CDR ARGS))
	((SETQ TEM (GET OP 'FORMAT-CTL-NO-ARG))
	 (FUNCALL TEM PARAMS)
	 ARGS)
	((SETQ TEM (GET OP 'FORMAT-CTL-MULTI-ARG))
	 (FUNCALL TEM ARGS PARAMS))
	((SETQ TEM (GET OP 'FORMAT-CTL-REPEAT-CHAR))
	 (FORMAT-CTL-REPEAT-CHAR (OR (CAR PARAMS) 1) TEM)
	 ARGS)
	(T (FORMAT-ERROR "/"~S/" is not defined as a ~S command." OP 'FORMAT)
	   ARGS)))

(DEFUN (:PROPERTY CRLF FORMAT-CTL-NO-ARG) (IGNORE)
  (AND ATSIGN-FLAG (SEND *STANDARD-OUTPUT* :TYO #/NEWLINE)))

;; Several commands have a SIZE long object which they must print
;; in a WIDTH wide field.  If WIDTH is specified and is greater than
;; the SIZE of the thing to be printed, this put out the right
;; number of  CHARs to fill the field.  You can call this before
;; or after printing the thing, to get leading or trailing padding.
(DEFUN FORMAT-CTL-JUSTIFY (WIDTH SIZE &OPTIONAL (CHAR #/SPACE))
  (AND WIDTH (> WIDTH SIZE) (FORMAT-CTL-REPEAT-CHAR (- WIDTH SIZE) CHAR)))

;;; Fixed point output.

(DEFPROP D FORMAT-CTL-DECIMAL FORMAT-CTL-ONE-ARG)

(DEFUN FORMAT-CTL-DECIMAL (ARG PARAMS &OPTIONAL (*PRINT-BASE* 10.)	;Also called for octal
			   	      &AUX	(*NOPOINT T)
				      		(*PRINT-RADIX* NIL)
						(WIDTH (FIRST PARAMS))
						(PADCHAR (SECOND PARAMS))
						(COMMACHAR (THIRD PARAMS))
						(PLUS-P (AND ATSIGN-FLAG
							     (NUMBERP ARG)
							     (NOT (MINUSP ARG)))))
  (SETQ PADCHAR (COND ((NULL PADCHAR) #/SPACE)
		      ((NUMBERP PADCHAR) (INT-CHAR PADCHAR))
		      ((CHARACTERP PADCHAR) PADCHAR)
		      (T (CHAR (STRING PADCHAR) 0))))
  (SETQ COMMACHAR (COND ((NULL COMMACHAR) #/,)
			((NUMBERP COMMACHAR) (INT-CHAR COMMACHAR))
			((CHARACTERP COMMACHAR) COMMACHAR)
			(T (CHAR (STRING COMMACHAR) 0))))
  (AND WIDTH (FORMAT-CTL-JUSTIFY WIDTH
				 (+ (IF (FIXNUMP ARG)
					(+ (LOOP FOR X = (ABS ARG) THEN (FLOOR X *PRINT-BASE*)
						 COUNT T
						 UNTIL (< X *PRINT-BASE*))
					   (IF (MINUSP ARG) 1 0))
				      (FLATC ARG))
				    (IF PLUS-P 1 0)
				    (IF (AND COLON-FLAG (INTEGERP ARG))
					(FLOOR (1- (FLATC (ABS ARG))) 3)   ;Number of commas
				      0))
				 PADCHAR))
  (AND PLUS-P (SEND *STANDARD-OUTPUT* :TYO #/+))
  (COND ((AND COLON-FLAG (INTEGERP ARG))
	 ;; Random hair with commas.  I'm not going to bother not consing.
	 (COND ((MINUSP ARG) (SEND *STANDARD-OUTPUT* :TYO #/-) (SETQ ARG (- ARG))))
	   (SETQ ARG (NREVERSE (INHIBIT-STYLE-WARNINGS	;Give up!
				 (EXPLODEN ARG))))
	   (DO ((L ARG (CDR L))
		(I 2 (1- I)))
	       ((NULL (CDR L)))
	     (COND ((ZEROP I)
		    (RPLACD L (CONS COMMACHAR (CDR L)))
		    (SETQ I 3 L (CDR L)))))
	   (DOLIST (CH (NREVERSE ARG))
	     (SEND *STANDARD-OUTPUT* :TYO CH)))
	((FIXNUMP ARG) (SI::PRINT-FIXNUM ARG *STANDARD-OUTPUT*))
	;; This is PRINC rather than PRIN1 so you can have a string instead of a number
	(T (PRINC ARG))))

(DEFPROP O FORMAT-CTL-OCTAL FORMAT-CTL-ONE-ARG)
(DEFUN FORMAT-CTL-OCTAL (ARG PARAMS)
  (FORMAT-CTL-DECIMAL ARG PARAMS 8))

(DEFPROP B FORMAT-CTL-BINARY FORMAT-CTL-ONE-ARG)
(DEFUN FORMAT-CTL-BINARY (ARG PARAMS)
  (FORMAT-CTL-DECIMAL ARG PARAMS 2))

(DEFPROP X FORMAT-CTL-HEX FORMAT-CTL-ONE-ARG)
;(DEFPROP X FORMAT-CTL-HEX FORMAT-CTL-COMMON-LISP-ONE-ARG)
(DEFUN FORMAT-CTL-HEX (ARG PARAMS)
  (FORMAT-CTL-DECIMAL ARG PARAMS 16.))

(DEFPROP R FORMAT-CTL-ROMAN FORMAT-CTL-ONE-ARG)
(DEFUN FORMAT-CTL-ROMAN (ARG PARAMS)
  (COND ((CAR PARAMS) (FORMAT-CTL-DECIMAL ARG (CDR PARAMS) (CAR PARAMS)))
	((AND ATSIGN-FLAG
	      (INTEGERP ARG)
	      (< ARG 4000.)
	      (> ARG 0))
	 (LET ((ROMAN-OLD COLON-FLAG))
	   (ROMAN-STEP ARG 0)))
	((OR ATSIGN-FLAG
	     (NOT (INTEGERP ARG)))
	 (LET ((*PRINT-BASE* 10.) (*NOPOINT T) (*PRINT-RADIX* NIL))
	   (PRIN1 ARG)))
	((NOT COLON-FLAG)
	 (ENGLISH-PRINT ARG))
	(T (ENGLISH-ORDINAL-PRINT ARG))))

(DEFCONST ENGLISH-SMALL
	  #("one" "two" "three" "four" "five" "six"
	    "seven" "eight" "nine" "ten" "eleven" "twelve"
	    "thirteen" "fourteen" "fifteen" "sixteen"
	    "seventeen" "eighteen" "nineteen"))

(DEFCONST ENGLISH-ORDINAL-SMALL
	  #("first" "second" "third" "fourth" "fifth"
	    "sixth" "seventh" "eighth" "ninth"
	    "tenth" "eleventh" "twelfth" "thirteenth"
	    "fourteenth" "fifteenth" "sixteenth"
	    "seventeenth" "eighteenth" "nineteenth"))

(DEFCONST ENGLISH-MEDIUM
	  #("twenty" "thirty" "forty" "fifty" "sixty" "seventy" "eighty" "ninety"))

(DEFCONST ENGLISH-ORDINAL-MEDIUM
	  #("twentieth" "thirtieth" "fortieth" "fiftieth"
	    "sixtieth" "seventieth" "eightieth" "ninetieth"))

(DEFCONST ENGLISH-LARGE
	  #("" "thousand" "million" "billion" "trillion"
	       "quadrillion" "quintillion" "sextillion"
	       "septillion" "octillion" "nonillion" "decillion"
	       "undecillion" "duodecillion"))

(DEFCONST ENGLISH-ORDINAL-LARGE
	  #("" "thousandth" "millionth" "billionth"
	       "trillionth" "quadrillionth" "quintillionth"
	       "sextillionth" "septillionth" "octillionth" "nonillionth"
	       "decillionth" "undecillionth" "duodecillionth"))

(DEFCONST ENGLISH-100 "hundred")

(DEFCONST ENGLISH-ORDINAL-100 "hundredth")

;;; Returns T if it printed anything, else NIL.
(DEFUN ENGLISH-PRINT-THOUSAND (N STREAM)
  (LET ((FLAG NIL)
	(N (\ N 100.))
	(H (FLOOR N 100.)))
    (WHEN (> H 0)
      (SETQ FLAG T)
      (SEND STREAM :STRING-OUT (AREF ENGLISH-SMALL (1- H)))
      (SEND STREAM :TYO #/SPACE)
      (SEND STREAM :STRING-OUT ENGLISH-100)
      (AND (> N 0) (SEND STREAM :TYO #/SPACE)))
    (COND ((= N 0))
	  ((< N 20.)
	   (SETQ FLAG T)
	   (SEND STREAM :STRING-OUT (AREF ENGLISH-SMALL (1- N))))
	  (T
	   (SETQ FLAG T)
	   (SEND STREAM :STRING-OUT (AREF ENGLISH-MEDIUM (- (FLOOR N 10.) 2)))
	   (COND ((ZEROP (SETQ H (\ N 10.))))
		 (T
		  (WRITE-CHAR #/- STREAM)
		  (SEND STREAM :STRING-OUT (AREF ENGLISH-SMALL (1- H)))))))
    FLAG))

;;; Returns T if it printed anything, else NIL.
(DEFUN ENGLISH-PRINT (N &OPTIONAL (STREAM *STANDARD-OUTPUT*) (TRIAD 0))
  (COND ((ZEROP N)
	 (COND ((ZEROP TRIAD)
		(SEND STREAM :STRING-OUT "zero")
		T)
	       (T NIL)))
	((< N 0)
	 (SEND STREAM :STRING-OUT "minus")
	 (SEND STREAM :TYO #/SPACE)
	 (ENGLISH-PRINT (MINUS N) STREAM)
	 T)
	(T
	 (LET ((FLAG (ENGLISH-PRINT (FLOOR N 1000.) STREAM (1+ TRIAD))))
	   (LET ((THIS-TRIPLET (\ N 1000.)))
	     (COND ((NOT (ZEROP THIS-TRIPLET))
		    (IF FLAG (SEND STREAM :TYO #/SPACE))
		    (IF (EQ FLAG 'EXPT) (SEND STREAM :STRING-OUT "plus "))
		    (ENGLISH-PRINT-THOUSAND THIS-TRIPLET STREAM)
		    (COND ((ZEROP TRIAD) T)
			  ((> TRIAD 13.)
			   (SEND STREAM :STRING-OUT " times ten to the ")
			   (ENGLISH-ORDINAL-PRINT (* 3 TRIAD))
			   (SEND STREAM :STRING-OUT " power")
			   'EXPT)
			  (T
			   (WRITE-CHAR #/SPACE STREAM)
			   (SEND STREAM :STRING-OUT (AREF ENGLISH-LARGE TRIAD))
			   T)))
		   (T FLAG)))))))

(DEFUN ENGLISH-ORDINAL-PRINT (N &OPTIONAL (STREAM *STANDARD-OUTPUT*))
  (IF (ZEROP N)
      (SEND STREAM :STRING-OUT "zeroth")
    (DO ((I (IF (= (\ (FLOOR N 10.) 10.) 0)
		10. 100.)
	    (* I 10.))
	 (TEM) (TEM1))
	(( (SETQ TEM (\ N I)) 0)
	 (COND (( (SETQ TEM1 (- N TEM)) 0)
		(ENGLISH-PRINT (- N TEM) STREAM)
		(SEND STREAM :TYO #/SPACE)))
	 (LET ((ENGLISH-SMALL (IF (AND (= (\ TEM 10.) 0) ( TEM 10.))
				  ENGLISH-SMALL
				  ENGLISH-ORDINAL-SMALL))
	       (ENGLISH-MEDIUM (IF (= (\ TEM 10.) 0)
				   ENGLISH-ORDINAL-MEDIUM
				   ENGLISH-MEDIUM))
	       (ENGLISH-100 ENGLISH-ORDINAL-100)
	       (ENGLISH-LARGE ENGLISH-ORDINAL-LARGE))
	   (ENGLISH-PRINT TEM STREAM))))))

(DEFUN ROMAN-STEP (X N)
  (WHEN (> X 9.)
    (ROMAN-STEP (FLOOR X 10.) (1+ N))
    (SETQ X (\ X 10.)))
  (COND ((AND (= X 9) (NOT ROMAN-OLD))
	 (ROMAN-CHAR 0 N)
	 (ROMAN-CHAR 0 (1+ N)))
	((= X 5)
	 (ROMAN-CHAR 1 N))
	((AND (= X 4) (NOT ROMAN-OLD))
	 (ROMAN-CHAR 0 N)
	 (ROMAN-CHAR 1 N))
	(T (WHEN (> X 5)
	     (ROMAN-CHAR 1 N)
	     (SETQ X (- X 5)))
	   (DOTIMES (I X)
	     (ROMAN-CHAR 0 N)))))

(DEFUN ROMAN-CHAR (I X)
  (SEND *STANDARD-OUTPUT* :TYO (NTH (+ I X X) '(#/I #/V #/X #/L #/C #/D #/M))))

;;; Funny bases
(DEFUN (:ENGLISH SI:PRINC-FUNCTION) (X STREAM)
  (FORMAT STREAM "~R" (- X)))

(DEFUN (:ROMAN SI:PRINC-FUNCTION) (X STREAM)
  (FORMAT STREAM "~@R" (- X)))

(DEFUN (:ROMAN-OLD SI:PRINC-FUNCTION) (X STREAM)
  (FORMAT STREAM "~:@R" (- X)))

;(DEFPROP F FORMAT-CTL-HAIRY-F-FORMAT FORMAT-CTL-COMMON-LISP-ONE-ARG)
(DEFPROP F FORMAT-CTL-HAIRY-F-FORMAT FORMAT-CTL-ONE-ARG)
(DEFUN FORMAT-CTL-HAIRY-F-FORMAT (ARG PARAMS)
  (AND (RATIONALP ARG) (SETQ ARG (FLOAT ARG)))
  (IF (NOT (FLOATP ARG))
      (FORMAT-CTL-DECIMAL ARG (LIST (CAR PARAMS)))
    (PROG* ((WIDTH (CAR PARAMS))
	    (AFTER-DECIMAL (CADR PARAMS))
	    (SCALE (CADDR PARAMS))
	    (OVERFLOWCHAR (FOURTH PARAMS))
	    (PADCHAR (FIFTH PARAMS))
	    (WIDTH-AFTER-SIGN
	      (AND WIDTH
		   (IF (OR (MINUSP ARG) ATSIGN-FLAG) (- WIDTH 1) WIDTH))))
	  (WHEN SCALE
	    (SETQ ARG (* ARG (SI::XR-GET-POWER-10 SCALE))))
	  (MULTIPLE-VALUE-BIND (BUFFER)
	      (SI::FLONUM-TO-STRING (ABS ARG) (TYPEP ARG 'SHORT-FLOAT)
				    (AND WIDTH (1- WIDTH-AFTER-SIGN))
				    AFTER-DECIMAL T)
	    (WHEN WIDTH
	      (WHEN (AND OVERFLOWCHAR
			 (> (LENGTH BUFFER) WIDTH-AFTER-SIGN))
		;; Does not fit in specified width => print overflow chars.
		(RETURN
		  (DOTIMES (I WIDTH)
		    (SEND *STANDARD-OUTPUT* :TYO OVERFLOWCHAR))))
	      ;; Space left over => print padding.
	      (DOTIMES (I (- WIDTH-AFTER-SIGN (LENGTH BUFFER)))
		(SEND *STANDARD-OUTPUT* :TYO (OR PADCHAR #/SPACE))))
	    (COND ((MINUSP ARG) (SEND *STANDARD-OUTPUT* :TYO #/-))
		  (ATSIGN-FLAG (SEND *STANDARD-OUTPUT* :TYO #/+)))
	    (SEND *STANDARD-OUTPUT* :STRING-OUT BUFFER)
	    (RETURN-ARRAY (PROG1 BUFFER (SETQ BUFFER NIL)))))))

;(DEFPROP F FORMAT-CTL-F-FORMAT FORMAT-CTL-ONE-ARG)
;(DEFUN FORMAT-CTL-F-FORMAT (ARG PARAMS)
;  (AND (NUMBERP ARG) (NOT (FLOATP ARG)) (SETQ ARG (FLOAT ARG)))
;  (IF (NOT (FLOATP ARG))
;      (FORMAT-CTL-DECIMAL ARG NIL)
;    (SI::PRINT-FLONUM ARG STANDARD-OUTPUT NIL (TYPEP ARG 'SHORT-FLOAT)
;		      (CAR PARAMS) NIL)))

;(DEFPROP E FORMAT-CTL-HAIRY-E-FORMAT FORMAT-CTL-COMMON-LISP-ONE-ARG)
(DEFPROP E FORMAT-CTL-HAIRY-E-FORMAT FORMAT-CTL-ONE-ARG)
(DEFUN FORMAT-CTL-HAIRY-E-FORMAT (ORIGINAL-ARG PARAMS)
  (AND (RATIONALP ORIGINAL-ARG) (SETQ ORIGINAL-ARG (FLOAT ORIGINAL-ARG)))
  (IF (NOT (FLOATP ORIGINAL-ARG))
      (FORMAT-CTL-DECIMAL ORIGINAL-ARG (LIST (CAR PARAMS)))
    (PROG* ((WIDTH (CAR PARAMS))
	    (AFTER-DECIMAL (CADR PARAMS))
	    (EXPONENT-DIGITS (THIRD PARAMS))
	    (SCALE (OR (FOURTH PARAMS) 1))
	    (OVERFLOWCHAR (FIFTH PARAMS))
	    (PADCHAR (SIXTH PARAMS))
	    (EXPONENTCHAR (SEVENTH PARAMS))
	    (NEGATIVE (MINUSP ORIGINAL-ARG))
	    WIDTH-AFTER-SIGN-AND-EXPONENT
	    EXPONENT
	    EXTRA-ZERO
	    ARG)
	RETRY
	   (SETF (VALUES ARG EXPONENT) (SI::SCALE-FLONUM (ABS ORIGINAL-ARG)))
	   ;; If user does not specify number of exponent digits, guess.
	   (UNLESS EXPONENT-DIGITS
	     (SETQ EXPONENT-DIGITS
		   (COND ((> (ABS EXPONENT) 99.) 3)
			 ((> (ABS EXPONENT) 9) 2)
			 (T 1))))
	   (SETQ WIDTH-AFTER-SIGN-AND-EXPONENT
		 (AND WIDTH
		      (- (IF (OR NEGATIVE ATSIGN-FLAG) (- WIDTH 1) WIDTH)
			 EXPONENT-DIGITS 2)))
	   (MULTIPLE-VALUE-BIND (BUFFER DECIMAL-PLACE)
	       (SI::FLONUM-TO-STRING ARG (TYPEP ARG 'SHORT-FLOAT)
				     (AND WIDTH (1- WIDTH-AFTER-SIGN-AND-EXPONENT))
				     (AND AFTER-DECIMAL
					  (IF (PLUSP SCALE)
					      AFTER-DECIMAL
					      (1- AFTER-DECIMAL))))
	     ;; Correct "10.0", caused by carry, into "1.0"
	     (WHEN (= DECIMAL-PLACE 2)
	       (SETF (CHAR BUFFER 2) (CHAR BUFFER 1))
	       (SETF (CHAR BUFFER 1) #/.)
	       (IF (CHAR= (CHAR BUFFER (1- (LENGTH BUFFER))) #/0)
		   (DECF (FILL-POINTER BUFFER)))
	       (DECF DECIMAL-PLACE)
	       (INCF EXPONENT))
	     (DECF EXPONENT (- SCALE 1))
	     (SETQ EXTRA-ZERO (AND ( SCALE 0)
				   (> WIDTH-AFTER-SIGN-AND-EXPONENT (LENGTH BUFFER))))
	     (WHEN WIDTH
	       (WHEN (AND OVERFLOWCHAR
			  (OR (> (LENGTH BUFFER) WIDTH-AFTER-SIGN-AND-EXPONENT)
			      (AND (THIRD PARAMS)
				   ( (ABS EXPONENT)
				      (EXPT 10. EXPONENT-DIGITS)))))
		 ;; Does not fit in specified width => print overflow chars.
		 ;; Do not bomb out on an exponent that doesn't fit
		 ;; unless the number of exponent digits was explicitly specified.
		 (RETURN
		   (DOTIMES (I WIDTH)
		     (SEND *STANDARD-OUTPUT* :TYO OVERFLOWCHAR))))
	       ;; If exponent needs extra digits but we aren't bombing out,
	       ;; allocate more space to exponent and try again.
	       ;; This way we try to stay within the specified field width
	       ;; by taking away from other things.
	       (DO ((I 1 (1+ I))
		    (X 10. (* X 10.)))
		   ((> X (ABS EXPONENT))
		    (WHEN (> I EXPONENT-DIGITS)
		      (SETQ EXPONENT-DIGITS I)
		      (GO RETRY))))
	       ;; Space left over => print padding.
	       (DOTIMES (I (- WIDTH-AFTER-SIGN-AND-EXPONENT (LENGTH BUFFER)
			      (IF EXTRA-ZERO 1 0)))
		 (SEND *STANDARD-OUTPUT* :TYO (OR PADCHAR #/SPACE))))
	     (COND (NEGATIVE (SEND *STANDARD-OUTPUT* :TYO #/-))
		   (ATSIGN-FLAG (SEND *STANDARD-OUTPUT* :TYO #/+)))
	     (WHEN EXTRA-ZERO
	       (SEND *STANDARD-OUTPUT* :TYO #/0))
	     (WHEN (MINUSP SCALE)
	       (SEND *STANDARD-OUTPUT* :TYO (SI::PTTBL-DECIMAL-POINT *READTABLE*))
	       (DOTIMES (I (- SCALE))
		 (SEND *STANDARD-OUTPUT* :TYO #/0))
	       (DECF (FILL-POINTER BUFFER) (- SCALE)))
	     (DOTIMES (I (1- (LENGTH BUFFER)))
	       (WHEN (= I SCALE)
		 (SEND *STANDARD-OUTPUT* :TYO (SI::PTTBL-DECIMAL-POINT *READTABLE*)))
	       (SEND *STANDARD-OUTPUT* :TYO
		     (CHAR BUFFER (IF ( I DECIMAL-PLACE) (1+ I) I))))
	     (SEND *STANDARD-OUTPUT* :TYO
		   (OR EXPONENTCHAR
		       (COND ((EQ (NOT (TYPEP ARG 'SHORT-FLOAT))
				  (NEQ *READ-DEFAULT-FLOAT-FORMAT* 'SHORT-FLOAT))
			      #/e)
			     ((TYPEP ARG 'SHORT-FLOAT) #/s)
			     (T #/f))))
	     (SEND *STANDARD-OUTPUT* :TYO
		   (IF (MINUSP EXPONENT) #/- #/+))
	     (LET (ATSIGN-FLAG COLON-FLAG)
	       (FORMAT-CTL-DECIMAL (ABS EXPONENT) (LIST EXPONENT-DIGITS #/0)))
	     (RETURN-ARRAY (PROG1 BUFFER (SETQ BUFFER NIL)))))))

;(DEFPROP E FORMAT-CTL-E-FORMAT FORMAT-CTL-ONE-ARG)
;(DEFUN FORMAT-CTL-E-FORMAT (ARG PARAMS)
;  (AND (NUMBERP ARG) (NOT (FLOATP ARG)) (SETQ ARG (FLOAT ARG)))
;  (IF (NOT (FLOATP ARG))
;      (FORMAT-CTL-DECIMAL ARG NIL)
;    (SI::PRINT-FLONUM ARG STANDARD-OUTPUT NIL (TYPEP ARG 'SHORT-FLOAT)
;		       (CAR PARAMS) T)))

(DEFPROP G FORMAT-CTL-HAIRY-G-FORMAT FORMAT-CTL-MULTI-ARG)
;(DEFUN FORMAT-CTL-GOTO (IGNORE PARAMS &AUX (COUNT (OR (CAR PARAMS) 1)))
;    (NTHCDR COUNT FORMAT-ARGLIST))

;(DEFPROP G FORMAT-CTL-HAIRY-G-FORMAT FORMAT-CTL-COMMON-LISP-ONE-ARG)
(DEFUN FORMAT-CTL-HAIRY-G-FORMAT (ARGS PARAMS &AUX (ARG (CAR ARGS)))
  (IF (AND (NUMBERP (CAR PARAMS)) ( 0 (CAR PARAMS) 3))
      (NTHCDR (CAR PARAMS) FORMAT-ARGLIST)
    (AND (RATIONALP ARG) (SETQ ARG (FLOAT ARG)))
    (IF (NOT (FLOATP ARG))
	(FORMAT-CTL-DECIMAL ARG (LIST (CAR PARAMS)))
      (PROG* ((WIDTH (CAR PARAMS))
	      (AFTER-DECIMAL (CADR PARAMS))
	      (EXPONENT-DIGITS (OR (THIRD PARAMS) 2))
	      (OVERFLOWCHAR (FIFTH PARAMS))
	      (PADCHAR (SIXTH PARAMS))
	      (EXPONENT-WIDTH (+ EXPONENT-DIGITS 2))
	      (WIDTH-AFTER-EXPONENT
		(AND WIDTH
		     (- WIDTH EXPONENT-WIDTH)))
	      EXPONENT
	      DECIMALS-NEEDED-IF-FIXED
	      (NEGATIVE (MINUSP ARG))
	      )
	     (MULTIPLE-VALUE (NIL EXPONENT) (SI::SCALE-FLONUM (ABS ARG)))
	     (UNLESS AFTER-DECIMAL
	       ;; If number of sig figs not specified, compute # digits needed for fixed format.
	       (IF (> (ABS EXPONENT) WIDTH)
		   ;; If it's going to be gross, don't bother.
		   ;; We know that E format will be used, so go use it.
		   (RETURN (FORMAT-CTL-HAIRY-E-FORMAT ARG PARAMS)))
	       (MULTIPLE-VALUE-BIND (BUFFER)
		   (SI::FLONUM-TO-STRING (ABS ARG) (TYPEP ARG 'SHORT-FLOAT)
					 (AND WIDTH (- WIDTH-AFTER-EXPONENT
						       (IF (OR NEGATIVE ATSIGN-FLAG) 2 1)))
					 NIL T)
		 (SETQ AFTER-DECIMAL
		       (MAX (1- (LENGTH BUFFER)) (MIN (1+ EXPONENT) 7)))))
	     (SETQ DECIMALS-NEEDED-IF-FIXED
		   (- AFTER-DECIMAL EXPONENT 1))
	     (IF ( 0 DECIMALS-NEEDED-IF-FIXED AFTER-DECIMAL)
		 (PROGN
		   (FORMAT-CTL-HAIRY-F-FORMAT
		     ARG
		     (LIST WIDTH-AFTER-EXPONENT
			   DECIMALS-NEEDED-IF-FIXED
			   NIL OVERFLOWCHAR PADCHAR))
		   (DOTIMES (I EXPONENT-WIDTH)
		     (SEND *STANDARD-OUTPUT* :TYO #/SPACE)))
	       (FORMAT-CTL-HAIRY-E-FORMAT ARG PARAMS))))
    (CDR ARGS)))

;;; This doesn't support RDIG being 0.  That would be nice, but is complicated.
(DEFPROP $ FORMAT-CTL-MONEY FORMAT-CTL-ONE-ARG)
(DEFUN FORMAT-CTL-MONEY (ARG PARAMS)
  (LET ((RDIG (OR (FIRST PARAMS) 2))		;This many digits after decimal point
	(LDIG (OR (SECOND PARAMS) 1))		;At least this many to left of decimal
	(FIELD (THIRD PARAMS))			;Right-justify in field this wide
	(PADCHAR (OR (FOURTH PARAMS) #/SPACE)))	;Padding with this
    (COND ((OR (NOT (NUMBERP ARG)) (> (ABS ARG) 1e50))
	   (FORMAT-CTL-JUSTIFY FIELD (FLATC ARG) PADCHAR)
	   (PRINC ARG))
	  (T (OR (FLOATP ARG) (SETQ ARG (FLOAT ARG)))
	     (MULTIPLE-VALUE-BIND (STR IDIG)
		 (SI::FLONUM-TO-STRING (ABS ARG) (TYPEP ARG 'SHORT-FLOAT) NIL RDIG)
	       (LET ((WIDTH (+ (IF (OR ATSIGN-FLAG (MINUSP ARG)) 1 0)
			       (MAX (- LDIG IDIG) 0)
			       (ARRAY-ACTIVE-LENGTH STR))))
		 (IF (NOT COLON-FLAG) (FORMAT-CTL-JUSTIFY FIELD WIDTH PADCHAR))
		 (COND ((MINUSP ARG)
			(SEND *STANDARD-OUTPUT* :TYO (SI::PTTBL-MINUS-SIGN *READTABLE*)))
		       (ATSIGN-FLAG (SEND *STANDARD-OUTPUT* :TYO #/+)))
		 (IF COLON-FLAG (FORMAT-CTL-JUSTIFY FIELD WIDTH PADCHAR))
		 (DOTIMES (I (- LDIG IDIG)) (SEND *STANDARD-OUTPUT* :TYO #/0))
		 (SEND *STANDARD-OUTPUT* :STRING-OUT STR)
		 (RETURN-ARRAY (PROG1 STR (SETQ STR NIL)))))))))

;(DEFPROP G FORMAT-CTL-GOTO FORMAT-CTL-MULTI-ARG)
;(DEFUN FORMAT-CTL-GOTO (IGNORE PARAMS &AUX (COUNT (OR (CAR PARAMS) 1)))
;    (NTHCDR COUNT FORMAT-ARGLIST))

(DEFPROP A FORMAT-CTL-ASCII FORMAT-CTL-ONE-ARG)
(DEFUN FORMAT-CTL-ASCII (ARG PARAMS &OPTIONAL PRIN1P)
  (LET ((EDGE (CAR PARAMS))
	(PERIOD (CADR PARAMS))
	(MIN (CADDR PARAMS))
	(PADCHAR (CADDDR PARAMS)))
    (COND ((NULL PADCHAR)
	   (SETQ PADCHAR #/SPACE))
	  ((NOT (NUMBERP PADCHAR))
	   (SETQ PADCHAR (CHARACTER PADCHAR))))
    (COND (ATSIGN-FLAG)				;~@5nA right justifies
	  ((AND COLON-FLAG (NULL ARG)) (SEND *STANDARD-OUTPUT* :STRING-OUT "()"))
	  (PRIN1P (PRIN1 ARG))
	  ((STRINGP ARG) (SEND *STANDARD-OUTPUT* :STRING-OUT ARG))
	  (T (PRINC ARG)))
    (WHEN EDGE
      (LET ((WIDTH (SEND (COND (PRIN1P #'FLATSIZE)
			       ((STRINGP ARG) #'ARRAY-ACTIVE-LENGTH)
			       (T #'FLATC))
			 ARG)))
	(WHEN MIN
	  (FORMAT-CTL-REPEAT-CHAR MIN PADCHAR)
	  (INCF WIDTH MIN))
	(COND (PERIOD
	       (FORMAT-CTL-REPEAT-CHAR
		 (- (+ EDGE (* (FLOOR (+ (- (MAX EDGE WIDTH) EDGE 1)
					 PERIOD)
				      PERIOD)
			       PERIOD))
		    WIDTH)
		 PADCHAR))
	      (T (FORMAT-CTL-JUSTIFY EDGE WIDTH PADCHAR)))))
    (COND ((NOT ATSIGN-FLAG))
	  ((AND COLON-FLAG (NULL ARG)) (SEND *STANDARD-OUTPUT* :STRING-OUT "()"))
	  (PRIN1P (PRIN1 ARG))
	  ((STRINGP ARG) (SEND *STANDARD-OUTPUT* :STRING-OUT ARG))
	  (T (PRINC ARG)))))

(DEFPROP S FORMAT-CTL-SEXP FORMAT-CTL-ONE-ARG)
(DEFUN FORMAT-CTL-SEXP (ARG PARAMS)
  (FORMAT-CTL-ASCII ARG PARAMS T))

;;;; Character output modes

(DEFPROP LOZENGED-CHAR FORMAT-CTL-LOZENGED-CHAR FORMAT-CTL-ONE-ARG)
(DEFPROP LOZENGED-CHARACTER FORMAT-CTL-LOZENGED-CHAR FORMAT-CTL-ONE-ARG)
(DEFUN FORMAT-CTL-LOZENGED-CHAR (CHAR IGNORE)
  (IF (AND (OR (GRAPHIC-CHAR-P CHAR)
	       (FORMAT-GET-CHARACTER-NAME CHAR))
	   (SEND *STANDARD-OUTPUT* :OPERATION-HANDLED-P :DISPLAY-LOZENGED-STRING))
      (SEND *STANDARD-OUTPUT* :DISPLAY-LOZENGED-STRING (FORMAT NIL "~:C" CHAR))
    (FORMAT-CTL-CHARACTER CHAR NIL)))

(DEFFORMAT LOZENGED-STRING (:ONE-ARG) (STRING PARAMS)
  (SETQ STRING (STRING STRING))
  (IF (AND (SEND *STANDARD-OUTPUT* :OPERATION-HANDLED-P :DISPLAY-LOZENGED-STRING)
	   (DOTIMES (I (LENGTH STRING) T)
	     (UNLESS (GRAPHIC-CHAR-P (CHAR STRING I)) (RETURN NIL))))
      (SEND *STANDARD-OUTPUT* :DISPLAY-LOZENGED-STRING STRING)
    (FORMAT-CTL-ASCII STRING PARAMS)))

;;; Prevent error calling TV:CHAR-MOUSE-P before window system loaded.
(UNLESS (FBOUNDP 'TV:CHAR-MOUSE-P)
  (FSET 'TV:CHAR-MOUSE-P 'IGNORE))

(DEFPROP C FORMAT-CTL-CHARACTER FORMAT-CTL-ONE-ARG)
(DEFUN FORMAT-CTL-CHARACTER (ARG IGNORE &AUX CHNAME BITS LOWER-CASE)
  (WHEN (EQ (CAR-SAFE ARG) ':MOUSE-BUTTON) (SETQ ARG (CADR ARG)))
  (SETQ ARG (CLI:CHARACTER ARG)
	BITS (CHAR-BITS ARG))
  (FLET ((PRINT-BITS (BITS)
	   (AND (BIT-TEST CHAR-HYPER-BIT BITS)
		(SEND *STANDARD-OUTPUT* :STRING-OUT "Hyper-"))
	   (AND (BIT-TEST CHAR-SUPER-BIT BITS)
		(SEND *STANDARD-OUTPUT* :STRING-OUT "Super-"))
	   (AND (BIT-TEST CHAR-CONTROL-BIT BITS)
		(SEND *STANDARD-OUTPUT* :STRING-OUT "Control-"))
	   (AND (BIT-TEST CHAR-META-BIT BITS)
		(SEND *STANDARD-OUTPUT* :STRING-OUT "Meta-"))))
    (COND ((TV:CHAR-MOUSE-P ARG)
	   (IF (AND (NOT COLON-FLAG) ATSIGN-FLAG)
	       (PRINC "#\"))
	   (PRINT-BITS BITS)
	   (SETF (CHAR-BITS ARG) 0)
	   (IF (AND (NOT COLON-FLAG) ATSIGN-FLAG)
	       (IF (SETQ CHNAME (FORMAT-GET-CHARACTER-NAME ARG))
		   (PRINC CHNAME)
		 (FORMAT-ERROR "~O unknown mouse character given to ~~@C" ARG))
	     (SEND *STANDARD-OUTPUT* :STRING-OUT "Mouse-")
	     (SEND *STANDARD-OUTPUT* :STRING-OUT (NTH (LDB %%KBD-MOUSE-BUTTON ARG)
						      '("Left" "Middle" "Right")))
	     (IF (SETQ CHNAME (NTH (SETQ BITS (LDB %%KBD-MOUSE-N-CLICKS ARG))
				   '("" "-Twice" "-Thrice")))
		 (SEND *STANDARD-OUTPUT* :STRING-OUT CHNAME)
	       (SEND *STANDARD-OUTPUT* :TYO #/-)
	       (ENGLISH-PRINT (1+ BITS))
	       (SEND *STANDARD-OUTPUT* :STRING-OUT "-times"))))
	  ((NOT COLON-FLAG)
	   ;; If @ flag or if control bits, we want to use characters' names.
	   (IF (OR ATSIGN-FLAG (NOT (ZEROP BITS)))
	       (SETQ CHNAME (FORMAT-GET-CHARACTER-NAME (CHAR-CODE ARG))))
	   ;; Print an appropriate reader macro if @C.
	   (IF ATSIGN-FLAG (PRINC "#\"))
	   (UNLESS (ZEROP BITS)
	     (SEND *STANDARD-OUTPUT*
		   :STRING-OUT (NTH BITS '("" "c-" "m-" "c-m-"
					   "s-" "c-s-" "m-s-" "c-m-s-"
					   "h-" "c-h-" "m-h-" "c-m-h-"
					   "s-h-" "c-s-h-" "m-s-h-" "c-m-s-h-")))
	     (IF ( (CHAR-CODE #/a) (SETQ LOWER-CASE (CHAR-CODE ARG)) (CHAR-CODE #/z))
		 (SEND *STANDARD-OUTPUT* :STRING-OUT "sh-")
	       (SETQ LOWER-CASE NIL)))
	   (COND (CHNAME
		  (SETQ CHNAME (SYMBOL-NAME CHNAME))
		  ;; are we CONSING yet?
		  (SEND *STANDARD-OUTPUT* :TYO (CHAR-UPCASE (CHAR CHNAME 0)))
		  (DO ((LEN (LENGTH CHNAME))
		       (I 1 (1+ I)))
		      ((= I LEN))
		    (SEND *STANDARD-OUTPUT* :TYO (CHAR-DOWNCASE (CHAR CHNAME I)))))
		 (T (IF ATSIGN-FLAG
			(IF (SI::CHARACTER-NEEDS-QUOTING-P (CHAR-CODE ARG))
			    (SEND *STANDARD-OUTPUT* :TYO (SI::PTTBL-SLASH *READTABLE*)))
		        (IF LOWER-CASE (SETQ ARG (CHAR-UPCASE (INT-CHAR LOWER-CASE)))))
		    (SEND *STANDARD-OUTPUT* :TYO (CHAR-CODE ARG)))))
	  (T
	   (PRINT-BITS BITS)
	   (SETQ ARG (INT-CHAR (CHAR-CODE ARG)))
	   (COND ((SETQ CHNAME (FORMAT-GET-CHARACTER-NAME ARG))
		  (SETQ CHNAME (SYMBOL-NAME CHNAME))
		  (SEND *STANDARD-OUTPUT* :TYO (CHAR-UPCASE (CHAR CHNAME 0)))
		  (DO ((LEN (LENGTH CHNAME))
		       (I 1 (1+ I)))
		      ((= I LEN))
		    (SEND *STANDARD-OUTPUT* :TYO (CHAR-DOWNCASE (CHAR CHNAME I))))
		  (AND ATSIGN-FLAG (FORMAT-PRINT-TOP-CHARACTER ARG)))
                 ((AND ATSIGN-FLAG (CHAR< ARG (INT-CHAR #o40)) (CHAR ARG #/))
		  (SEND *STANDARD-OUTPUT* :TYO ARG)
		  (FORMAT-PRINT-TOP-CHARACTER ARG))
		 ((AND (LOWER-CASE-P ARG)
		       (NOT (ZEROP BITS)))
		  (SEND *STANDARD-OUTPUT* :STRING-OUT "Shift-")
		  (SEND *STANDARD-OUTPUT* :TYO (CHAR-UPCASE ARG)))
                 (T (SEND *STANDARD-OUTPUT* :TYO ARG)))))))

(DEFUN FORMAT-GET-CHARACTER-NAME (CHAR)
  (IF (FIXNUMP CHAR) (SETQ CHAR (INT-CHAR CHAR)))
  (UNLESS (AND (GRAPHIC-CHAR-P CHAR)
	       (CHAR CHAR #/SPACE)
	       (CHAR CHAR #/ALTMODE))
    (DO ((L SI::XR-SPECIAL-CHARACTER-NAMES (CDR L)))
	((NULL L) NIL)
;character lossage
      (WHEN (CHAR= (INT-CHAR (CDAR L)) CHAR)
	(RETURN (CAAR L))))))

(DEFUN FORMAT-PRINT-TOP-CHARACTER (CHAR &AUX NAME CHNAME)
  (IF (CHARACTERP CHAR) (SETQ CHAR (CHAR-INT CHAR)))
  (COND ((SETQ CHNAME (DOTIMES (I #o200)
			(WHEN (= CHAR (AREF SI::KBD-NEW-TABLE 2 I))
			  (RETURN (INT-CHAR (AREF SI::KBD-NEW-TABLE 1 I))))))
	 (SETQ NAME " (Top-"))
	((SETQ CHNAME (DOTIMES (I #o200)
			(AND (= CHAR (AREF SI::KBD-NEW-TABLE 3 I))
			     (RETURN (INT-CHAR (AREF SI::KBD-NEW-TABLE 0 I))))
			(AND (= CHAR (AREF SI::KBD-NEW-TABLE 4 I))
			     (RETURN (INT-CHAR (AREF SI::KBD-NEW-TABLE 1 I))))))
	 (SETQ NAME (IF (ALPHA-CHAR-P CHNAME) " (Greek-" " (Front-"))))
  (WHEN (AND CHNAME (NEQ CHNAME (INT-CHAR CHAR)))
    (SEND *STANDARD-OUTPUT* :STRING-OUT NAME)
    ;; I'm not sure what to pass for the second arg, since it is not used.
    ;; It currently doesn't matter.
    (LET ((ATSIGN-FLAG NIL))
      (FORMAT-CTL-CHARACTER CHNAME NIL))
    (SEND *STANDARD-OUTPUT* :TYO #/))))

(DEFPROP T FORMAT-CTL-TAB FORMAT-CTL-NO-ARG)
(DEFUN FORMAT-CTL-TAB (PARAMS &AUX (DEST (OR (FIRST PARAMS) 1)) (EXTRA (OR (SECOND PARAMS) 1))
				   (OPS (SEND *STANDARD-OUTPUT* :WHICH-OPERATIONS))
				   INCR-OK)
  (COND ((OR (SETQ INCR-OK (MEMQ :INCREMENT-CURSORPOS OPS))
	     (MEMQ :SET-CURSORPOS OPS))
	 (LET ((FLAVOR (IF COLON-FLAG :PIXEL :CHARACTER)))
	   (MULTIPLE-VALUE-BIND (X Y) (SEND *STANDARD-OUTPUT* :READ-CURSORPOS FLAVOR)
	     (LET ((NEW-X (IF ATSIGN-FLAG
			      (IF ( EXTRA 1)
				  (+ DEST X)
				  (* (CEILING (+ DEST X) EXTRA) EXTRA))
			    (COND ((< X DEST)
				   DEST)
				  ((ZEROP EXTRA)
				   X)
				  (T
				   (+ X EXTRA (- (\ (- X DEST) EXTRA))))))))
	       (COND ((= NEW-X X))
		     (INCR-OK
		      ;; Use :INCREMENT-CURSORPOS preferentially
		      ;; because it will do a **MORE** if we need one.
		      (SEND *STANDARD-OUTPUT* :INCREMENT-CURSORPOS (- NEW-X X) 0 FLAVOR))
		     (T
		      (SEND *STANDARD-OUTPUT* :SET-CURSORPOS NEW-X Y FLAVOR)))))))
	(ATSIGN-FLAG
	 (DOTIMES (I DEST)
	   (SEND *STANDARD-OUTPUT* :TYO #/SPACE)))
	(T (SEND *STANDARD-OUTPUT* :STRING-OUT "  "))))

(DEFPROP P FORMAT-CTL-PLURAL FORMAT-CTL-MULTI-ARG)
(DEFUN FORMAT-CTL-PLURAL (ARGS IGNORE)
  (AND COLON-FLAG (SETQ ARGS (FORMAT-CTL-IGNORE ARGS NIL)))	;crock: COLON-FLAG is set
  (IF ATSIGN-FLAG (IF (EQUAL (CAR ARGS) 1)
		      (SEND *STANDARD-OUTPUT* :TYO #/y)
		    (SEND *STANDARD-OUTPUT* :STRING-OUT "ies"))
    (OR (EQUAL (CAR ARGS) 1) (SEND *STANDARD-OUTPUT* :TYO #/s)))
  (CDR ARGS))

(DEFPROP * FORMAT-CTL-IGNORE FORMAT-CTL-MULTI-ARG)
(DEFUN FORMAT-CTL-IGNORE (ARGS PARAMS &AUX (COUNT (OR (CAR PARAMS) 1)))
  (COND (ATSIGN-FLAG
	 (NTHCDR COUNT FORMAT-ARGLIST))
	(COLON-FLAG
	 (DO ((A FORMAT-ARGLIST (CDR A))
	      (B (NTHCDR COUNT FORMAT-ARGLIST) (CDR B)))
	     ((NULL A) (FORMAT-ERROR "Can't back up properly for a ~:*"))
	   (AND (EQ B ARGS) (RETURN A))))
	(T (NTHCDR COUNT ARGS))))

(DEFPROP % FORMAT-CTL-NEWLINES FORMAT-CTL-NO-ARG)
(DEFUN FORMAT-CTL-NEWLINES (PARAMS &AUX (COUNT (OR (CAR PARAMS) 1)))
  (DOTIMES (I COUNT) (SEND *STANDARD-OUTPUT* :TYO #/NEWLINE)))

(DEFPROP & FORMAT-CTL-FRESH-LINE FORMAT-CTL-NO-ARG)
(DEFUN FORMAT-CTL-FRESH-LINE (PARAMS &AUX (COUNT (OR (CAR PARAMS) 1)))
  (SEND *STANDARD-OUTPUT* :FRESH-LINE)
  (DOTIMES (I (1- COUNT))
    (SEND *STANDARD-OUTPUT* :TYO #/NEWLINE)))

;(DEFPROP X #/SPACE FORMAT-CTL-REPEAT-CHAR)
(DEFPROP ~ #/~ FORMAT-CTL-REPEAT-CHAR)

(DEFUN FORMAT-CTL-REPEAT-CHAR (COUNT CHAR)
  (DOTIMES (I COUNT)
    (SEND *STANDARD-OUTPUT* :TYO CHAR)))

(DEFPROP /| FORMAT-CTL-FORMS FORMAT-CTL-NO-ARG)
(DEFUN FORMAT-CTL-FORMS (PARAMS)
  (IF (AND COLON-FLAG (MEMQ :CLEAR-SCREEN (SEND *STANDARD-OUTPUT* :WHICH-OPERATIONS)))
      (SEND *STANDARD-OUTPUT* :CLEAR-SCREEN)
    (FORMAT-CTL-REPEAT-CHAR (OR (CAR PARAMS) 1) #/FORM)))

(DEFPROP Q FORMAT-CTL-APPLY FORMAT-CTL-ONE-ARG)
(DEFUN FORMAT-CTL-APPLY (ARG PARAMS)
  (APPLY ARG PARAMS))

;;; Parse a set of clauses separated by ~; and terminated by ~closechar.
;;; (If SEMIP is nil, however, then ~; is ignored.)
;;; Returns an array; G-L-P of this array is a list whose length is a multiple of 3.
;;; Every three elements are <string> <bits> <paramarray>, where <string> is a control
;;; string separated by ~;, <bits> encodes the : and @ flags for the ~; or ~closechar
;;; that followed this string (: = 1, @ = 2), and <paramarray> is () or the parameter array
;;; for that ~; or ~closechar.  The arrays and strings are consed in the temporary area.
;;; FORMAT-RECLAIM-CLAUSES should be used to return the arrays and strings.

(defun format-parse-clauses (closechar semip &aux (start (+ 3 ctl-index)))
  (let ((clauses (get-format-buffer format-clauses-array
				    (make-array 30. :area format-temporary-area
						    :type art-q-list :fill-pointer 0)))
	(stack (get-format-buffer format-stack-array
				  (make-array 10. :area format-temporary-area
						  :type art-q-list :fill-pointer 0)))
	i j tem atsign-flag colon-flag command)
    (setf (fill-pointer clauses) 0 (fill-pointer stack) 0)
    (setq i ctl-index)
    (do-forever
      (unless (setq ctl-index (%string-search-char #/~ ctl-string ctl-index ctl-length))
	(ferror nil
		;; Yow!
		"Missing ~{~*~~~A and ~} ~~~A in format string:~%~{~VT~*~}~VT~%~3@T/"~A/"~%"
		(g-l-p stack) closechar (g-l-p stack) start ctl-string))
      (setq j ctl-index)
      (setq atsign-flag nil colon-flag nil)
      (let ((format-params (allocate-resource 'format-params)))
	(setf (fill-pointer format-params) 0)
	(setq command (format-parse-command nil nil))
	;; Now I points to beginning of clause, J to ~, and CTL-INDEX after command.
	(cond ((setq tem (get command 'format-matching-delimiter))
	       (vector-push-extend start stack)
	       (vector-push-extend closechar stack)
	       (setq closechar tem start (+ 3 ctl-index)))
	      ((< (fill-pointer stack) 2)			;at top level
	       (when (or (eq command closechar) (and (eq command '/;) semip))
		 (vector-push-extend (nsubstring ctl-string i j format-temporary-area)
				     clauses)
		 (vector-push-extend (+ (if colon-flag 1 0) (if atsign-flag 2 0))
				     clauses)
		 (vector-push-extend (when (g-l-p format-params)
				       (prog1 format-params (setq format-params nil)))
				     clauses)
		 (setq i ctl-index)
		 (when (eq command closechar)
		   (return-format-buffer stack format-stack-array)
		   (when format-params (deallocate-resource 'format-params format-params))
		   (return clauses))))
	      ((eq command closechar)				;pop off a level
	       (setq closechar (vector-pop stack))
	       (setq start (vector-pop stack))))
	;; Unless the parameters were saved away in the clauses table, free them
	(if format-params (deallocate-resource 'format-params format-params))))))

(defun format-reclaim-clauses (clauses)
  (do ((i (fill-pointer clauses) (- i 3)))
      ((= i 0)
       (return-format-buffer clauses format-clauses-array))
    (return-array (aref clauses (- i 3)))
    (and (aref clauses (1- i))
	 (deallocate-resource 'format-params (aref clauses (1- i))))))

(DEFPROP /; FORMAT-CTL-DELIMIT-CLAUSE FORMAT-CTL-NO-ARG)
(DEFUN FORMAT-CTL-DELIMIT-CLAUSE (IGNORE)
       (FORMAT-ERROR "Stray ~~; in FORMAT control string"))


(defvar case-convert nil)
(defvar prev-char nil)
(defvar case-converted-stream nil)

(defprop case-convert-stream t si:io-stream-p)
(defun case-convert-stream (op &rest args)
  (case op
    (:tyo
     (selectq case-convert
       (uppercase (send case-converted-stream :tyo (char-upcase (car args))))
       (lowercase (send case-converted-stream :tyo (char-downcase (car args))))
       (cap-all-words
	(send case-converted-stream :tyo
	      (setq prev-char
		    (if (alphanumericp prev-char)
			(char-downcase (car args))
		      (char-upcase (car args))))))
       (cap-first-word
	(send case-converted-stream :tyo
	      (if (alphanumericp prev-char)
		  (char-downcase (car args))
		(setq prev-char
		      (char-upcase (car args))))))
       (just-first-word
	(send case-converted-stream :tyo
	      (if (alphanumericp prev-char)
		  (car args)
		(setq prev-char
		      (char-upcase (car args))))))))
    ((:string-out :line-out)
     (stream-default-handler 'case-convert-stream op (car args) (cdr args)))
    (:which-operations (remove :print (send case-converted-stream :which-operations)))
    (t (lexpr-send case-converted-stream op args))))

(defprop /( format-ctl-start-case-convert format-ctl-multi-arg)
(defprop /( /) format-matching-delimiter)
(defun format-ctl-start-case-convert (args params)
  (let ((clauses (format-parse-clauses '/) nil))
	(case-convert
	  (if (eq (car params) 1)
	      'just-first-word
	    (if colon-flag
		(if atsign-flag
		    'uppercase 'cap-all-words)
	      (if atsign-flag
		  'cap-first-word 'lowercase))))
	(prev-char 0)
	(case-converted-stream
	  (if case-convert case-converted-stream *standard-output*))
	(*standard-output* 'case-convert-stream))
    (unwind-protect
	(format-ctl-string args (aref clauses 0))
      (format-reclaim-clauses clauses))))

(defprop /) format-ctl-end-case-convert format-ctl-no-arg)
(defun format-ctl-end-case-convert (ignore)
       (format-error "Stray ~~) in FORMAT control string"))

(defprop format: format-ctl-upcase format:format-ctl-one-arg)

(defun format-ctl-upcase (thing ignore)
  (let ((*downcase-flag* format:atsign-flag)
	(*once-only-flag* format:colon-flag)
	(*old-stream* *standard-output*))
    (declare (special *downcase-flag* *once-only-flag* *old-stream*))
    (princ thing 'upcase-stream)))

(defprop upcase-stream t si:io-stream-p)
(defun upcase-stream (op &optional arg1 &rest rest)
  (declare (special *downcase-flag* *once-only-flag* *old-stream*))
  (case op
    (:which-operations
     '(:tyo))
    (:tyo
     (if *downcase-flag*
	 (if (upper-case-p arg1) (setq arg1 (char-downcase arg1)))
	 (if (lower-case-p arg1) (setq arg1 (char-upcase arg1))))
     (if *once-only-flag*
	 (setq *once-only-flag* nil *downcase-flag* (not *downcase-flag*)))
     (send *old-stream* :tyo arg1))
    (otherwise
     (stream-default-handler 'upcase-stream op arg1 rest))))

(defvar indent-convert nil)
(defvar indent-converted-stream nil)

(defun indent-convert-stream (op &rest args)
  (case op
    (:tyo
     (send indent-converted-stream :tyo (car args))
;character lossage
     (when (char= (car args) #/newline)
       (dotimes (i indent-convert)
	 (write-char #/space indent-converted-stream))))
    (:fresh-line
     (send indent-converted-stream :tyo #/newline)
     (dotimes (i indent-convert)
       (write-char #/space indent-converted-stream)))
    ((:string-out :line-out)
     (stream-default-handler 'indent-convert-stream op (car args) (cdr args)))
    (:which-operations (remove :print (send indent-converted-stream :which-operations)))
    (t (lexpr-send indent-converted-stream op args))))

(defprop  format-ctl-start-indent-convert format-ctl-multi-arg)
(defprop   format-matching-delimiter)
(defun format-ctl-start-indent-convert (args params)
  (let ((clauses (format-parse-clauses ' nil))
	(indent-convert (or (car params)
			    (send *standard-output* :send-if-handles
						    :read-cursorpos :character)
			    0))
	(indent-converted-stream
	  (if indent-convert indent-converted-stream *standard-output*))
	(*standard-output* 'indent-convert-stream))
    (unwind-protect
	(format-ctl-string args (aref clauses 0))
      (format-reclaim-clauses clauses))))

(defprop  format-ctl-end-indent-convert format-ctl-no-arg)
(defun format-ctl-end-indent-convert (ignore)
       (format-error "Stray ~~ in FORMAT control string"))

(DEFPROP [ FORMAT-CTL-START-SELECT FORMAT-CTL-MULTI-ARG)
(defprop [ ] format-matching-delimiter)
(DEFUN FORMAT-CTL-START-SELECT (ARGS PARAMS &AUX (ARG (CAR ARGS)))
  (COND (COLON-FLAG
	 (COND (ATSIGN-FLAG (FORMAT-ERROR "~~:@[ is not a defined FORMAT command"))
	       (T (SETQ ARG (COND (ARG 1) (T 0))) (POP ARGS))))
	(ATSIGN-FLAG (SETQ ARG (COND (ARG 0) (T (POP ARGS) -1))))
	((CAR PARAMS) (SETQ ARG (CAR PARAMS)))
	(T (POP ARGS)))
  (OR (NUMBERP ARG)
      (FORMAT-ERROR "The argument to the FORMAT /"~~[/" command must be a number"))
  (LET ((START CTL-INDEX)			;for error message only
	(CLAUSES (FORMAT-PARSE-CLAUSES '] T)))
    (DO ((L (G-L-P CLAUSES) (CDDDR L))
	 (STATE (AND (NOT (ZEROP (STRING-LENGTH (CAR (G-L-P CLAUSES))))) 'SIMPLE)))
	((NULL (CDDDR L))
	 (LET ((STRING (COND ((EQ STATE 'HAIRY)
			      (DO ((Z (G-L-P CLAUSES) (CDDDR Z)))
				  ((NULL (CDDDR Z)) NIL)
				(AND (COND ((NULL (CADDR Z)) T)
					   ((ODDP (CADR Z))
					    (DO ((Q (G-L-P (CADDR Z)) (CDDR Q)))
						((NULL Q) NIL)
					      (AND (OR (NULL (CAR Q)) (NOT (< ARG (CAR Q))))
						   (OR (NULL (CADR Q)) (NOT (> ARG (CADR Q))))
						   (RETURN T))))
					   (T (MEMQ ARG (G-L-P (CADDR Z)))))
				     (RETURN (CADDDR Z)))))
			     (T (DO ((Z (G-L-P CLAUSES) (CDDDR Z))
				     (A ARG (1- A)))
				    ((NULL Z) NIL)
				  (AND (ZEROP A) (RETURN (CAR Z)))
				  (AND (ODDP (CADR Z))
				       (NOT (NULL (CDDDR Z)))
				       (RETURN (CADDDR Z))))))))
	   (LET ((NEWARGS (COND (STRING (FORMAT-CTL-STRING ARGS STRING))
				(T ARGS))))
	     (FORMAT-RECLAIM-CLAUSES CLAUSES)
	     NEWARGS)))
      (COND ((NOT (NULL (CADDR L)))
	     (COND ((EQ STATE 'SIMPLE)
		    (SETQ CTL-INDEX START)
		    (FORMAT-ERROR "Mixture of simple and tagged clauses in ~~[")))
	     (SETQ STATE 'HAIRY))
	    ((NOT (ODDP (CADR L)))
	     (COND ((EQ STATE 'HAIRY)
		    (SETQ CTL-INDEX START)
		    (FORMAT-ERROR "Mixture of simple and tagged clauses in ~~[")))
	     (SETQ STATE 'SIMPLE))))))

(DEFPROP ] FORMAT-CTL-END-SELECT FORMAT-CTL-NO-ARG)
(DEFUN FORMAT-CTL-END-SELECT (IGNORE)
       (FORMAT-ERROR "Stray ~~] in FORMAT control string"))

(DEFPROP ^ FORMAT-CTL-TERMINATE FORMAT-CTL-MULTI-ARG)
(DEFUN FORMAT-CTL-TERMINATE (ARGS PARAMS)
  (AND (IF (CAR PARAMS)
	   (IF (CADR PARAMS)
	       (IF (CADDR PARAMS)
		   (AND (NOT (> (CAR PARAMS) (CADR PARAMS)))
			(NOT (> (CADDR PARAMS) (CADR PARAMS))))
		 (= (CAR PARAMS) (CADR PARAMS)))
	     (ZEROP (CAR PARAMS)))
	 (NULL (IF COLON-FLAG LOOP-ARGLIST ARGS)))
       (THROW (IF COLON-FLAG 'FORMAT-/:^-POINT 'FORMAT-^-POINT) NIL))
  ARGS)

(DEFPROP { FORMAT-ITERATE-OVER-LIST FORMAT-CTL-MULTI-ARG)
(defprop { } format-matching-delimiter)
(DEFUN FORMAT-ITERATE-OVER-LIST (ARGS PARAMS)
  (LET ((LIMIT (OR (FIRST PARAMS) -1))
	(CLAUSES (FORMAT-PARSE-CLAUSES '} NIL)))
    (OR (NULL (CDDDR (G-L-P CLAUSES))) (FORMAT-ERROR "Bug in FORMAT's ~{ processor"))
    (LET ((STR (CAR (G-L-P CLAUSES))))
      (AND (ZEROP (STRING-LENGTH STR))
	   (OR (STRINGP (SETQ STR (POP ARGS)))
	       (FORMAT-ERROR "~~{~~} argument not a string")))
      (LET ((LOOP-ARGLIST (IF ATSIGN-FLAG ARGS (CAR ARGS))))
	(CATCH 'FORMAT-/:^-POINT
	  (CATCH 'FORMAT-^-POINT
	    (DO ((OKAY-TO-EXIT (NOT (ODDP (CADR (G-L-P CLAUSES)))) T))
		((OR (AND OKAY-TO-EXIT (NULL LOOP-ARGLIST)) (= LIMIT 0)))
	      (COND ((NOT COLON-FLAG)
		     (LET ((FORMAT-ARGLIST LOOP-ARGLIST))
		       (SETQ LOOP-ARGLIST
			     (FORMAT-CTL-STRING LOOP-ARGLIST STR))))
		    (T (LET ((FORMAT-ARGLIST (POP LOOP-ARGLIST)))
			 (CATCH 'FORMAT-^-POINT
			   (FORMAT-CTL-STRING FORMAT-ARGLIST
					      STR)))))
	      (SETQ LIMIT (1- LIMIT)))))
	(FORMAT-RECLAIM-CLAUSES CLAUSES)
	(IF ATSIGN-FLAG LOOP-ARGLIST (CDR ARGS))))))

(DEFPROP } FORMAT-CTL-END-ITERATE-OVER-LIST FORMAT-CTL-NO-ARG)
(DEFUN FORMAT-CTL-END-ITERATE-OVER-LIST (IGNORE)
       (FORMAT-ERROR "Stray ~~} in FORMAT control string"))

(DEFPROP ? FORMAT-INDIRECT FORMAT-CTL-MULTI-ARG)
(DEFUN FORMAT-INDIRECT (ARGS IGNORE)
  (LET ((STR (POP ARGS)))
    (LET ((LOOP-ARGLIST (IF ATSIGN-FLAG ARGS (CAR ARGS))))
      (CATCH 'FORMAT-/:^-POINT
	(CATCH 'FORMAT-^-POINT
	  (LET ((FORMAT-ARGLIST LOOP-ARGLIST))
	    (SETQ LOOP-ARGLIST
		  (FORMAT-CTL-STRING LOOP-ARGLIST STR)))))
      (IF ATSIGN-FLAG LOOP-ARGLIST (CDR ARGS)))))

;;; This function is like FORMAT-CTL-STRING except that instead of sending to
;;; *STANDARD-OUTPUT* it sends to a string and returns that as its second value.
;;; The returned string is in the temporary area.
(DEFUN FORMAT-CTL-STRING-TO-STRING (ARGS STR)
  (LET ((FORMAT-STRING (MAKE-STRING 128. :AREA FORMAT-TEMPORARY-AREA :FILL-POINTER 0))
	(*STANDARD-OUTPUT* 'FORMAT-STRING-STREAM))
    (VALUES (FORMAT-CTL-STRING ARGS STR)
	    (ADJUST-ARRAY-SIZE FORMAT-STRING (ARRAY-ACTIVE-LENGTH FORMAT-STRING)))))

;;; This is not so hairy as to work with ~T, tabs, crs.  I really don't see how to do that.
;;; It makes a list of strings, then decides how much spacing to put in,
;;; then goes back and outputs.
(DEFPROP < FORMAT-HAIRY-JUSTIFICATION FORMAT-CTL-MULTI-ARG)
(defprop < > format-matching-delimiter)
(DEFUN FORMAT-HAIRY-JUSTIFICATION (ARGS PARAMS)
  (LET ((MINCOL (OR (FIRST PARAMS) 0))
	(COLINC (OR (SECOND PARAMS) 1))
	(MINPAD (OR (THIRD PARAMS) 0))
	(PADCHAR (OR (FOURTH PARAMS) #/SPACE))
	(W-O (SEND *STANDARD-OUTPUT* :WHICH-OPERATIONS))
	(NEWLINE NIL)
	(EXTRA 0)
	(LINEWIDTH NIL)
	(STRINGS NIL)
	(STRING-NCOL 0)
	(CLAUSES)
	(N-PADDING-POINTS -1)
	(TOTAL-PADDING)
	(N-PADS)
	(N-EXTRA-PADS))
    (AND COLON-FLAG (SETQ N-PADDING-POINTS (1+ N-PADDING-POINTS)))
    (AND ATSIGN-FLAG (SETQ N-PADDING-POINTS (1+ N-PADDING-POINTS)))
    (CATCH 'FORMAT-^-POINT
      (PROGN (SETQ CLAUSES (FORMAT-PARSE-CLAUSES '> T))
	     (DO ((SPECS (G-L-P CLAUSES) (CDDDR SPECS)) (STR))
		 ((NULL SPECS))
	       (MULTIPLE-VALUE (ARGS STR) (FORMAT-CTL-STRING-TO-STRING ARGS (CAR SPECS)))
	       (SETQ STRING-NCOL (+ (STRING-LENGTH STR) STRING-NCOL))
	       (SETQ N-PADDING-POINTS (1+ N-PADDING-POINTS))
	       (SETQ STRINGS (CONS-IN-AREA STR STRINGS FORMAT-TEMPORARY-AREA)))))
    (SETQ STRINGS (NREVERSE STRINGS))
    (WHEN (AND (G-L-P CLAUSES) (ODDP (CADR (G-L-P CLAUSES))))
      (SETQ NEWLINE (POP STRINGS))
      (AND (CADDR (G-L-P CLAUSES))
	   (SETQ EXTRA (OR (CAR (G-L-P (CADDR (G-L-P CLAUSES)))) 0)
		 LINEWIDTH (CADR (G-L-P (CADDR (G-L-P CLAUSES))))))
      (SETQ STRING-NCOL (- STRING-NCOL (STRING-LENGTH NEWLINE)))
      (SETQ N-PADDING-POINTS (1- N-PADDING-POINTS)))
    (WHEN (ZEROP N-PADDING-POINTS)	;With no options and no ~; right-justify
      (SETQ COLON-FLAG T N-PADDING-POINTS 1))
    ;; Get the amount of space needed to print the strings and MINPAD padding
    (SETQ TOTAL-PADDING (+ (* N-PADDING-POINTS MINPAD) STRING-NCOL))
    ;; Now bring in the MINCOL and COLINC constraint, i.e. the total width is
    ;; at least MINCOL and exceeds MINCOL by a multiple of COLINC, and
    ;; get the total amount of padding to be divided among the padding points
    (SETQ TOTAL-PADDING (- (+ MINCOL (* COLINC (CEILING (MAX (- TOTAL-PADDING MINCOL) 0)
							COLINC)))
			   STRING-NCOL))
    ;; Figure out whether a newline is called for or not.
    (WHEN (AND NEWLINE
	       (MEMQ :READ-CURSORPOS W-O)
	       (> (+ (SEND *STANDARD-OUTPUT* :READ-CURSORPOS :CHARACTER)
		     STRING-NCOL TOTAL-PADDING EXTRA)
		  (OR LINEWIDTH
		      (AND (MEMQ :SIZE-IN-CHARACTERS W-O)
			   (SEND *STANDARD-OUTPUT* :SIZE-IN-CHARACTERS))
		      72.)))
      (SEND *STANDARD-OUTPUT* :STRING-OUT NEWLINE))
    ;; Decide how many pads at each padding point + how many of the leftmost
    ;; padding points need one extra pad.
    (SETF (VALUES N-PADS N-EXTRA-PADS) (FLOOR TOTAL-PADDING N-PADDING-POINTS))
    (OR (ZEROP N-EXTRA-PADS) (SETQ N-PADS (1+ N-PADS)))
    ;; Output the stuff
    (DO ((STRINGS STRINGS (CDR STRINGS))
	 (PAD-BEFORE-P COLON-FLAG T))
	((NULL STRINGS))
      (WHEN PAD-BEFORE-P
	(FORMAT-CTL-REPEAT-CHAR N-PADS PADCHAR)
	(AND (ZEROP (SETQ N-EXTRA-PADS (1- N-EXTRA-PADS))) (SETQ N-PADS (1- N-PADS))))
      (SEND *STANDARD-OUTPUT* :STRING-OUT (CAR STRINGS)))
    ;; Finally spacing at the right
    (AND ATSIGN-FLAG (FORMAT-CTL-REPEAT-CHAR N-PADS PADCHAR))
    ;; Reclamation
    (DOLIST (STR (NREVERSE STRINGS))
      (RETURN-ARRAY STR))
    (AND NEWLINE (RETURN-ARRAY NEWLINE))
    (FORMAT-RECLAIM-CLAUSES CLAUSES)
    ARGS))

(DEFPROP > FORMAT-CTL-END-HAIRY-JUSTIFICATION FORMAT-CTL-NO-ARG)
(DEFUN FORMAT-CTL-END-HAIRY-JUSTIFICATION (IGNORE)
  (FORMAT-ERROR "Stray ~~> in FORMAT control string"))

;;; Less messy interface to list-printing stuff -- but it conses
(DEFUN PRINT-LIST (DESTINATION ELEMENT-FORMAT-STRING LIST
		   &OPTIONAL (SEPARATOR-FORMAT-STRING ", ")
			     (START-LINE-FORMAT-STRING "   ")
			     (TILDE-BRACE-OPTIONS ""))
  "Print the elements of list without lapping across line boundaries"
  (LET ((FSTRING (FORMAT NIL "~~~A{~~<~~%~A~~~D:;~A~~>~~^~A~~}"
			 TILDE-BRACE-OPTIONS
			 START-LINE-FORMAT-STRING
			 (STRING-LENGTH SEPARATOR-FORMAT-STRING)
			 ELEMENT-FORMAT-STRING
			 SEPARATOR-FORMAT-STRING)))
    (PROG1 (FORMAT DESTINATION FSTRING LIST)
	   (RETURN-ARRAY FSTRING))))

(DEFPROP TIME-INTERVAL FORMAT-CTL-TIME-INTERVAL FORMAT-CTL-ONE-ARG)
(DEFUN FORMAT-CTL-TIME-INTERVAL (INTERVAL IGNORE)
  (TIME:PRINT-INTERVAL-OR-NEVER INTERVAL))

(DEFPROP DATIME FORMAT-CTL-DATIME FORMAT-CTL-NO-ARG)
(DEFUN FORMAT-CTL-DATIME (IGNORE)
  (TIME:PRINT-CURRENT-TIME))

(DEFPROP TIME FORMAT-CTL-TIME FORMAT-CTL-ONE-ARG)
(DEFUN FORMAT-CTL-TIME (UT IGNORE)
  (TIME:PRINT-UNIVERSAL-TIME UT))

(DEFPROP DATE FORMAT-CTL-DATE FORMAT-CTL-ONE-ARG)
(DEFUN FORMAT-CTL-DATE (UT IGNORE)
  (TIME:PRINT-UNIVERSAL-DATE UT))

