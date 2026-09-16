;;; -*- Mode:LISP; Package:SI; Cold-load:T; Base:8; Lowercase:T; Readtable:T -*-
;;; LISP machine character level I/O stuff
;;; ** (c) Copyright 1980 Massachusetts Institute of Technology **

;(defconst stream-input-operations
;	  '(:tyi :listen :untyi :line-in :rubout-handler))

;(defconst stream-output-operations
;	  '(:tyo :force-output :finish :string-out :line-out :fresh-line :untyo-mark :untyo))

;;; Naming conventions:
;;;   Symbols whose names end in "-INPUT", "-OUTPUT", or "-IO" should
;;;      normally be BOUND to streams; which of the three you use depends on
;;;      what directions the stream normally supports.
;;;   Symbols whose names end in "-STREAM" are DEFINED as streams.


;;; Synonyms.
;;; MAKE-SYN-STREAM takes a symbol, and returns a stream which will forward all operations
;;;   to the binding of the symbol.  After (SETQ BAR (MAKE-SYN-STREAM 'FOO)), one says
;;;   that BAR is SYNned to FOO.


;;; The initial environment.
;;;   The initial binding of streams (set up by LISP-REINITIALIZE) is
;;;      as follows:
;;;   *TERMINAL-IO*	- This is how to get directly to the user's terminal.  It is set
;;;			up to go to the TV initially.  Other places it might go are to
;;;   *STANDARD-INPUT*	- This is initially bound to SYN to *TERMINAL-IO*.
;;;   *STANDARD-OUTPUT*	- This is initially bound to SYN to *TERMINAL-IO*. *STANDARD-INPUT*
;;;			and *STANDARD-OUTPUT* are the default streams for READ, PRINT and
;;;			other things.  *STANDARD-OUTPUT* gets hacked when the session is
;;;			being scripted, for example.
;;;   *ERROR-OUTPUT*	- This is where error messages should eventually get sent. Initially
;;;			SYNned to *TERMINAL-IO*.
;;;   *QUERY-IO*	- This is for unexpected user queries of the
;;;			"Do you really want to ..." variety. Initially SYNned to *TERMINAL-IO*
;;;   *TRACE-OUTPUT*	- Output produced by TRACE goes here.
;;;			 Initially SYNned to *ERROR-OUTPUT*.


(defvar *standard-input* :unbound
  "Default stream for input functions such as READ.")
(defvar *terminal-io* :unbound
  "Stream to use for /"terminal/" I//O.  Normally the selected window.
*STANDARD-INPUT* and other default streams are usually set up
as synonym streams which will use the value of *TERMINAL-IO*.")
;;; defvar for *standard-output* is in sys: sys; read
(defvar *error-output* :unbound
  "Stream to use for unanticipated noninteractive output, such as warnings.")
(defvar *query-io* :unbound
  "Stream to use for unanticipated questions, and related prompting, echoing, etc.")

(defvar standard-input :unbound
  "Default stream for input functions such as READ.")
(defvar terminal-io :unbound
  "Stream to use for /"terminal/" I//O.  Normally the selected window.
*STANDARD-INPUT* and other default streams are usually set up
as synonym streams which will use the value of *TERMINAL-IO*.")
(defvar error-output :unbound
  "Stream to use for unanticipated noninteractive output, such as warnings.")
(defvar query-io :unbound
  "Stream to use for unanticipated questions, and related prompting, echoing, etc.")

(forward-value-cell 'terminal-io '*terminal-io*)
(forward-value-cell 'standard-input '*standard-input*)
(forward-value-cell 'error-output '*error-output*)
(forward-value-cell 'query-io '*query-io*)

(defvar rubout-handler :unbound
  "Bound to stream which is inside rubout-handler, or NIL if none.")

;; BARF! BLETCH! Fuck me HARDER!!!!!
(defun streamp (object)
  "Returns non-NIL if OBJECT is a stream.
This predicate considers the following to be streams:
 Any instance incorporating SI:STREAM or TV:SHEET
 Any function handling either :TYI or :TYO.
 Any symbol with a non-NIL SI:IO-STREAM-P property."
  (or (and (instancep object) (or (typep-structure-or-flavor object 'stream)
				  (typep object 'tv:sheet)))
      ;; Explicit FUNCALLed things that accept messages
      (and (or (closurep object)
	       (entityp object)
	       (and (functionp object)
		    (or (nsymbolp object) (fboundp object))))
	   (arglist object t)
	   (ignore-errors
	     (let ((wo (funcall object :which-operations)))
	       (or (memq :tyo wo)
		   (memq :tyi wo)))))
      (and (symbolp object) (get object 'io-stream-p))))

(defun input-stream-p (stream) 
  "T if STREAM, assumed to be a stream, supports input."
  (memq (send stream :direction) '(:input :bidirectional)))

(defun output-stream-p (stream)
  "T if STREAM, assumed to be a stream, supports output."
  (memq (send stream :direction) '(:output :bidirectional)))

(defun io-stream-p (x)
  "T if X is a plausible I//O stream.
It must be an insance, entity, closure, compiled function
or a symbol which has a non-NIL SI:IO-STREAM-P property."
  (typecase x
    (instance t)
    (entity t)
    (closure t)
    (compiled-function t)
    (select t)
    (symbol (get x 'io-stream-p))
    (t nil)))

(defun stream-element-type (stream)
  "Return a Common Lisp type describing the objects input or output by STREAM.
This will be either CHARACTER or STRING-CHAR or a subtype of INTEGER."
  (or (send stream :send-if-handles :element-type)
      (if (send stream :characters)
	  'character
	(let ((value (send stream :send-if-handles :byte-size)))
	  (if value `(unsigned-byte ,value) 'fixnum)))))

;;;   eof-option  | eof-error-p | eof-value
;;; --------------+-------------+----------
;;;  (unsupplied) |      t      |     -
;;;     nil       |     nil     |    nil
;;;    other      |     nil     |   other

(defun decode-kludgey-mucklisp-read-args (arglist &optional (number-of-extra-args-allowed 0))
  (declare (values stream eof-error-p eof-value other-args))
  (cond
    ((null arglist)
     (values *standard-input* t))
    ((null (cdr arglist))
     (let ((arg1 (car arglist)))
       (if (or (eq arg1 nil) (eq arg1 t) (io-stream-p arg1))
	   ;; The arg is a plausible stream.
	   (values (decode-read-arg arg1) t)
	 ;; It is not a stream and must be an EOF option.
	 (values *standard-input* nil arg1))))
    ((null (cddr arglist))
     (let ((arg1 (car arglist)) (arg2 (cadr arglist)))
       (cond ((or (eq arg1 nil) (eq arg1 t) (io-stream-p arg1))
	      (values (decode-read-arg arg1) nil arg2))
	     ((or (eq arg2 nil) (eq arg2 t) (io-stream-p arg2))
	      (values (decode-read-arg arg2) nil arg1))
	     (t (values arg1 nil arg2)))))
    ((not (null (nthcdr (+ number-of-extra-args-allowed 2) arglist)))
     (ferror nil "Too many arguments were given to one of the READ-like functions: ~S"
	     arglist))
    ;; If giving hairy options, we assume she knows not to write stream args in wrong order.
    (t
     (values (decode-read-arg (car arglist)) nil (cadr arglist) (cddr arglist)))))

;;; Given the 2 arguments to READ (or TYI or READCH or TYIPEEK or READLINE)
;;; in the form of a REST argument this returns the input stream and the eof option.
;;; Note that the first arg would rather be the stream than the eof option.
;;; This is set up for Maclisp compatibility.
;;; HOWEVER, if the second argument is NIL or unsupplied, the first is
;;; assumed to be a stream if that is plausible,
;;; which is not compatible with Maclisp but more winning.
;;; If the user didn't supply an eof-option, the second value returned will
;;; be the symbol NO-EOF-OPTION.
(defun decode-read-args (arglist &optional (number-of-extra-args-allowed 0))
  (declare (values stream eof-option other-args))
  (multiple-value-bind (stream eof-error-p eof-value other-args)
      (decode-kludgey-mucklisp-read-args arglist number-of-extra-args-allowed)
    (if eof-error-p
	(values stream 'no-eof-option other-args)
      (values stream eof-value other-args))))
(compiler:make-obsolete decode-read-args "you probably want to be using DECODE-KLUDGEY-MUCKLISP-READ-ARGS instead")

(defun terpri (&optional stream)
  "Go to a new line on STREAM."
  (send (decode-print-arg stream) :tyo #/Return)
  t)

(defun cli:terpri (&optional stream)
  "Go to a new line on STREAM."
  (send (decode-print-arg stream) :tyo #/Return)
  nil)

(defun fresh-line (&optional stream)
  "Go to a new line on STREAM if not already at the beginning of one.
Returns T if a Return was output, NIL if nothing output."
  (send (decode-print-arg stream) :fresh-line))

(defun tyo (char &optional stream)
  "Output CHAR to STREAM."
  (send (decode-print-arg stream) :tyo (if (characterp char) (%pointer char) char))
  char)

(defun write-char (char &optional (stream *standard-output*))
  "Output CHAR to STREAM.  Returns CHAR."
  (send (decode-print-arg stream) :tyo (if (characterp char) (%pointer char) char))
  char)  

(defun write-byte (byte &optional (stream *standard-output*))
  "Output BYTE to STREAM.  Returns BYTE."
  (send (decode-print-arg stream) :tyo byte)
  byte)  

(defun write-string (string &optional (stream *standard-output*) &key (start 0) end)
  "Output all or part of STRING to STREAM.
START and END are indices specifying the part.
START defaults to 0 and END to NIL (which means the end of STRING.)"
  (send (decode-print-arg stream) :string-out string start end)
  string)

(defun write-line (string &optional (stream *standard-output*) &key (start 0) end)
  "Output all or part of STRING to STREAM, followed by a Return.
START and END are indices specifying the part.
START defaults to 0 and END to NIL (which means the end of STRING.)"
  (setq stream (decode-print-arg stream))
  (send stream :string-out string start end)
  (send stream :tyo #/Return)
  string)

(defun force-output (&optional stream)
  "Force output buffers on STREAM to begin being transmitted immediately.
Useful on asynchronous streams such as the chaosnet, which normally
wait until a buffer is full before even starting to transmit."
  (send (decode-print-arg stream) :force-output)
  nil)

(defun finish-output (&optional stream)
  "Wait until output buffers on STREAM are transmitted and processed completely.
For a file stream, this will not return until the data is recorded permanently
in the file system."
  (send (decode-print-arg stream) :finish)
  nil)

(defun clear-output (&optional stream)
  "Discard buffer output buffers on STREAM, if it is an interactive stream.
The discarded output will never appear where it was going.
For noninteractive streams, this usually does nothing."
  (send (decode-print-arg stream) :clear-output)
  nil)

;;; Common Lisp low level input functions

(defun read-char (&optional (stream *standard-input*) (eof-error-p t) eof-value recursive-p)
  "Read one character from STREAM, and return it as a character object.
If EOF-ERROR-P is T (the default), EOF is an error.
Otherwise, at EOF we return EOF-VALUE.
RECURSIVE-P is not used; it is a confusion in Common Lisp."
  recursive-p
  (let ((value (send (decode-read-arg stream) :tyi eof-error-p)))
    (if (null value) eof-value
      (int-char value))))

(defun unread-char (char &optional (stream *standard-input*))
  "Put CHAR back in STREAM to be read out again as the next input character.
CHAR must be the same character last read from STREAM,
or this may not work or might even signal an error."
  (send (decode-read-arg stream) :untyi (if (characterp char) (char-int char) char)))

(defun read-byte (&optional (stream *standard-input*) (eof-error-p t) eof-value)
  "Read one byte from STREAM, and return it.
If EOF-ERROR-P is T (the default), EOF is an error.
Otherwise, at EOF we return EOF-VALUE."
  (or (send (decode-read-arg stream) :tyi eof-error-p)
      eof-value))

(defun peek-char (&optional peek-type (stream *standard-input*) (eof-error-p t) eof-value
		  recursive-p)
  "Peek ahead at input from STREAM without discarding it.
The character peeked at is returned as a character object.
If PEEK-TYPE is NIL, peek at the next input character on STREAM,
 but leave it in the input stream so the next input will reread it.
If PEEK-TYPE is T, discard all whitespace chars and peek at first non-whitespace.
 The current readtable says what is whitespace.
Otherwise, discard all chars before the first one that is equal to PEEK-TYPE,
 which should be a number or a character.
EOF-ERROR-P and EOF-VALUE are as for READ-CHAR."
  recursive-p
  (setq stream (decode-read-arg stream))
  (cond ((null peek-type)
	 (let ((value (send stream :tyi)))
	   (if (null value)
	       (if eof-error-p
		   (ferror 'sys:end-of-file-1 "End of file encountered on stream ~S." stream)
		 eof-value)
	     (send stream :untyi value)
	     (int-char value))))
	(t
	 (do ((whitespace-code (cdr (getf (rdtbl-plist *readtable*) 'whitespace))))
	     (())
	   (let ((value (send stream :tyi)))
	     (if (null value)
		 (if eof-error-p
		     (ferror 'sys:end-of-file-1 "End of file encountered on stream ~S." stream)
		   (return eof-value))
	       (when (cond ((eq peek-type t)
			    (or ( (char-code value) value)
				( (rdtbl-code *readtable* value)
				   whitespace-code)))
			   (t
			    (eq peek-type (int-char value))))
		 (send stream :untyi value)
		 (return (int-char value)))))))))

(defun listen (&optional (stream *standard-input*))
  "T if input is available on STREAM.
On a noninteractive stream, this is T if not at EOF."
  (send (decode-read-arg stream) :listen))

(defun clear-input (&optional (stream *standard-input*))
  "Discard any buffered input on STREAM, if it is an interactive stream."
  (send (decode-read-arg stream) :clear-input)
  nil)

(defun read-char-no-hang (&optional (stream *standard-input*)
			  (eof-error-p t) eof-value recursive-p)
  "Read one character from STREAM, and return it as a character object, but don't wait.
On an interactive stream, if no input is currently buffered, NIL is returned.
If EOF-ERROR-P is T (the default), EOF is an error.
Otherwise, at EOF we return EOF-VALUE.
RECURSIVE-P is not used; it is a confusion in Common Lisp."
  recursive-p
  (condition-case-if (not eof-error-p) ()
      (let ((value (send (decode-read-arg stream) :tyi-no-hang t)))
	(if (null value) nil
	  (int-char value)))
    (end-of-file
     eof-value)))

;;;; Old-fashioned low level input functions.

;;; This function is compatible with the regular Maclisp TYI.  If you want speed,
;;; FUNCALL the stream directly.  We have to echo, but cannot use the rubout handler
;;; because the user wants to see rubout, form, etc. characters.  Inside the rubout
;;; handler, we do not echo since echoing will have occurred already.
(defun tyi (&rest read-args &aux ch)
  "Read one character from a stream.  Args are a stream and an eof-option.
The order is irrelevant; an arg which is not a reasonable stream
is taken to be the eof-option, which is returned if end of file is reached.
If there is no eof-option, end of file is an error.
If the stream supports rubout handling but we are not inside the rubout handler,
then the character read is echoed."
  (declare (arglist stream eof-option))
  (multiple-value-bind (stream eof-error-p eof-value)
      (decode-kludgey-mucklisp-read-args read-args)
    (cond ((null (setq ch (send stream :tyi)))	;Get a character, check for EOF
	   (if eof-error-p
	       (ferror 'sys:end-of-file-1 "End of file encountered on stream ~S." stream)
	     eof-value))
	  ((or rubout-handler			; If inside rubout handler, or
	       (not (memq :rubout-handler (send stream :which-operations))))
	   ch)					;  ordinary device, just return char
	  (t 
	   ;; Echo anything but blips and rubout, even control and meta charcters.
	   (if (and (fixnump ch)
		    ( ch #/Rubout))
	       (format stream "~C" ch))
	   ch))))

(defun readch (&rest read-args &aux ch (eof '(())))
  "Read one character from a stream, and return a symbol with that pname.
Otherwise the same as TYI.  This is an obsolete Maclisp function."
  (declare (arglist stream eof-option))
  (multiple-value-bind (stream eof-error-p eof-value)
      (decode-kludgey-mucklisp-read-args read-args)
    (if (eq (setq ch (tyi stream eof)) eof)
	(if eof-error-p
	    (ferror 'sys:end-of-file-1 "End of file encountered on stream ~S." stream)
	  eof-value)
	(intern (string ch)))))			;"Character objects" are in current package.

;;; This function is compatible, more or less, with the regular Maclisp TYIPEEK.
;;; It does not echo, since the echoing will occur when READ or TYI is called.
;;; It does echo characters which it discards.
(defun tyipeek (&optional peek-type &rest read-args)
  "If PEEK-TYPE is NIL, the default, returns the next character to be
read from STREAM, part of READ-ARGS, without removing the character from
the input stream.  If PEEK-TYPE is a fixnum less than 1000 octal, this
reads characters until it gets one equal to PEEK-TYPE.  That character
is not removed from the input stream.  If PEEK-TYPE is T, it skips over
all the input characters until the start of the printed representation
of a Lisp object is reached.  Characters passed over by TYIPEEK are echo
if STREAM is interactive.

This is an obsolete function.  Use the :TYIPEEK message for STREAMs
instead."
  (declare (arglist peek-type stream eof-option))
  (multiple-value-bind (stream eof-error-p eof-value)
      (decode-kludgey-mucklisp-read-args read-args)
    (if (characterp peek-type) (setq peek-type (char-int peek-type)))
    (and (numberp peek-type) ( peek-type #o1000)
	 (ferror nil "The ~S flavor of TYIPEEK is not implemented." peek-type))
    (do ((ch))	      ;Pass over characters until termination condition reached
	(())
      (or (setq ch (send stream :tyi))
	  (if eof-error-p
	      (ferror 'sys:end-of-file-1 "End of file encountered on stream ~S." stream)
	    (return eof-value)))
      (send stream :untyi ch)			;Put it back
      (and (cond ((null peek-type))		;Break on every
		 ((eq ch peek-type))		;Break on specified character
		 ((eq peek-type t)		;Break on start-of-object
		  (and (< ch rdtbl-array-size)
		       (zerop (logand (rdtbl-bits *readtable* ch) 1)))))
	   (return ch))				;Break here
      (tyi stream))))				;Echo and eat this character

(defun stream-copy-until-eof (from-stream to-stream &optional (leader-size nil))
  "Copy data from FROM-STREAM to TO-STREAM, until EOF on FROM-STREAM.
The default is to use the most efficient mode, but the third argument
may be used to force use of :LINE-IN//:LINE-OUT mode, especially useful
when the to-stream is an editor interval stream.  If you use this to
copy binary files, note that you had better open the streams with
appropriate host-dependent byte sizes, and that if the from-stream
supports :LINE-IN but not :READ-INPUT-BUFFER you will probably lose."
  (let ((fwo (send from-stream :which-operations))
	(two (send to-stream :which-operations)))
    (cond ((and (not leader-size)
		(memq :read-input-buffer fwo)
		(memq :string-out two))
	   ;; If it can go, this mode is the most efficient by far.
	   (do ((buf) (offset) (limit))
	       (())
	     (multiple-value (buf offset limit)
	       (send from-stream :read-input-buffer))
	     (cond ((null buf) (return nil)))
	     (send to-stream :string-out buf offset limit)
	     (send from-stream :advance-input-buffer)))
	  ((and (memq :line-in fwo)
                (memq :line-out two))
	   ;; Not as good, but better than :TYI/:TYO
           (do ((line) (eof))
	       (())
	     (multiple-value (line eof)
	       (send from-stream :line-in leader-size))
	     (cond ((not eof)
		    (send to-stream :line-out line))
		   (t (send to-stream :string-out line)
		      (return nil)))))
	  ;; This always wins, but is incredibly slow.
	  (t (do ((char))
		 ((null (setq char (send from-stream :tyi))))
	       (send to-stream :tyo char))))))


(deff make-syn-stream 'make-synonym-stream)
(defun make-synonym-stream (stream-symbol)
  "Return an I//O stream which passes all operations to the value of STREAM-SYMBOL.
This is most often used with STREAM-SYMBOL equal to '*TERMINAL-IO*.
STREAM-SYMBOL can be a locative instead of a symbol."
  (if (symbolp stream-symbol)
      ;; Changed 10/16/83 to make an uninterned symbol
      ;; but record it on STREAM-SYMBOL's plist so only one symbol needs to be made.
      (or (get stream-symbol 'syn-stream)
	  (let ((sym (make-symbol (string-append stream-symbol "-SYN-STREAM"))))
	    (%p-store-tag-and-pointer (locf (fsymeval sym))
				      dtp-external-value-cell-pointer
				      (locf (symeval stream-symbol)))
	    (putprop sym t 'io-stream-p)
	    (putprop stream-symbol sym 'syn-stream)
	    sym))
    (let ((sym (make-symbol "SYN-STREAM")))
      (%p-store-tag-and-pointer (locf (fsymeval sym))
				dtp-external-value-cell-pointer
				stream-symbol)
      (putprop sym t 'io-stream-p)
      sym)))

(defun follow-syn-stream (stream)
  "If STREAM is a synonym stream symbol, return the stream it is currently a synonym for.
Otherwise return STREAM."
  (cond ((not (symbolp stream)) stream)
	((neq (locf (fsymeval stream))
	      (follow-cell-forwarding (locf (fsymeval stream)) t))
	 (fsymeval stream))
	(t stream)))

(defun make-broadcast-stream (&rest streams)
  "Return an I//O stream which passes all operations to all of the STREAMS.
Thus, output directed to the broadcast stream will go to multiple places."
  (if (null streams) 'null-stream
    (let-closed ((broadcast-stream-streams (copylist streams))
		 (which-operations (loop with wo = (send (car streams) :which-operations)
					 with copyp = t
					 for stream in (cdr streams)
					 do (loop with wo2 = (send stream :which-operations)
						  for op in wo
						  unless (memq op wo2)
						    do (if copyp (setq wo (copylist wo)))
						       (setq copyp nil)
						       (setq wo (delq op wo)))
					 finally (return wo))))
      (function (lambda (&rest args)
		  (cond ((eq (car args) :which-operations) which-operations)
			((eq (car args) :operation-handled-p)
			 (memq (cadr args) which-operations))
			((eq (car args) :send-if-handles)
			 (do ((l broadcast-stream-streams (cdr l)))
			     ((null (cdr l))	;Last one gets to return multiple values
			      (lexpr-send (car l) :send-if-handles args))
			   (lexpr-send (car l) :send-if-handles args)))
			(t
			 (do ((l broadcast-stream-streams (cdr l)))
			     ((null (cdr l))	;Last one gets to return multiple values
			      (apply (car l) args))
			   (apply (car l) args)))))))))

(defun make-concatenated-stream (&rest streams)
  "Return a stream which will read from each of the STREAMS, one by one.
Reading from the concatenated stream will first read data from the first STREAM.
When that reaches eof, it will then read data from the second STREAM,
and so on until all the STREAMS are exhausted.  Then the concatenated stream gets eof."
  (let-closed ((concatenated-stream-streams (copylist streams))
	       (which-operations (loop with wo = (send (car streams) :which-operations)
				       with copyp = t
				       for stream in (cdr streams)
				       do (loop with wo2 = (send stream :which-operations)
						for op in wo
						unless (memq op wo2)
						do (if copyp (setq wo (copylist wo)))
						(setq copyp nil)
						(setq wo (delq op wo)))
				       finally (return wo)))
	       (concatenated-stream-function nil))
    (setq concatenated-stream-function
	  #'(lambda (op &rest args)
	      (prog ()
		loop
		(return
		  (case op
		    ((:tyi :tyi-no-hang :any-tyi-no-hang :any-tyi)
		     (if (null concatenated-stream-streams)
			 (and (car args)
			      (ferror 'sys:end-of-file-1 "End of file on ~S."
				      concatenated-stream-function))
		       (let ((value (send (car concatenated-stream-streams) :tyi)))
			 (if value
			     value
			   (pop concatenated-stream-streams)
			   (go loop)))))
		    (:which-operations which-operations)
		    (:send-if-handles
		     (and (memq (car args) which-operations)
			  (lexpr-send concatenated-stream-function args)))
		    (:operation-handled-p
		     (not (null (memq (car args) which-operations))))
		    (:untyi (send (car concatenated-stream-streams) :untyi (car args)))
		    (:direction :input)
		    (t (stream-default-handler concatenated-stream-function
					       op (car args) (cdr args))))))))))

(defconst two-way-input-operations
	  '(:tyi :tyi-no-hang :any-tyi-no-hang :any-tyi :untyi
	    :read-char :read-char-no-hang :any-read-char-no-hang :any-read-char :unread-char
	    :tyipeek :listen :line-in :string-in
	    :get-input-buffer :advance-input-buffer :read-input-buffer
	    :read-until-eof :clear-input))

(defun make-two-way-stream (input-stream output-stream)
  "Return a stream which does its input via INPUT-STREAM and its output via OUTPUT-STREAM.
This works by knowing about all the standard, ordinary input operations.
Use of unusual input operations, or operations that affect both input and output
/(such as random access) will not work."
  (let-closed ((two-way-input-stream input-stream)
	       (two-way-output-stream output-stream)
	       (which-operations
		 (union (intersection two-way-input-operations
				      (send input-stream :which-operations))
			(subset-not #'(lambda (elt) (memq elt two-way-input-operations))
				    (send output-stream :which-operations))
			'(:send-if-handles :operation-handled-p)))
	       (two-way-stream-function nil))
    (setq two-way-stream-function
	  #'(lambda (op &rest args)
		(cond ((memq op two-way-input-operations)
		       (lexpr-send two-way-input-stream op args))
		      ((eq op :which-operations) which-operations)
		      ((eq op :send-if-handles)
		       (and (memq (car args) which-operations)
			    (lexpr-send two-way-stream-function args)))
		      ((eq op :operation-handled-p)
		       (not (null (memq (car args) which-operations))))
		      (t
		       (lexpr-send two-way-output-stream op args)))))))

(defun make-echo-stream (input-stream output-stream)
  "Return a stream which does output via OUTPUT-STREAM, and input via INPUT-STREAM with echo.
All characters that this stream reads from INPUT-STREAM are also
echoed to OUTPUT-STREAM.
This works by knowing about all the standard, ordinary input operations.
Use of unusual input operations, or operations that affect both input and output
/(such as random access) will not work."
  (let-closed ((two-way-input-stream input-stream)
	       (two-way-output-stream output-stream)
	       (echo-stream-unread-char nil)
	       (which-operations
		 (union '(:tyi :untyi)
			(subset-not #'(lambda (elt) (memq elt two-way-input-operations))
				    (send output-stream :which-operations))
			'(:send-if-handles :operation-handled-p)))
	       (two-way-stream-function nil))
    (setq two-way-stream-function
	  #'(lambda (op &rest args)
		(cond ((eq op :tyi)
		       (or (prog1 echo-stream-unread-char
				  (setq echo-stream-unread-char nil))
			   (let ((value (send two-way-input-stream :tyi (car args))))
			     (if value (send two-way-output-stream :tyo value))
			     value)))
		      ((eq op :untyi)
		       (setq echo-stream-unread-char (car args)))
		      ((memq op two-way-input-operations)
		       (stream-default-handler two-way-stream-function op
					       (car args) (cdr args)))
		      ((eq op :which-operations) which-operations)
		      ((eq op :send-if-handles)
		       (and (memq (car args) which-operations)
			    (lexpr-send two-way-stream-function args)))
		      ((eq op :operation-handled-p)
		       (not (null (memq (car args) which-operations))))
		      (t
		       (lexpr-send two-way-output-stream op args)))))))

(defun stream-default-handler (fctn op arg1 args &aux tem)
  "Subroutine which provides default definition of certain stream operations.
If a stream does not recognize an operation, it may call this function
to have the operation handled.  The stream should return whatever
this function returns to it.  OP should be the operation, FCTN should
be the stream which received the operation, and ARG1 and ARGS should be
the arguments that came with the operation."
;character lossage in the extreme
  (tagbody
      (return-from stream-default-handler
	(case op
	  ((:tyipeek :listen)
	   (cond ((setq tem (send fctn :tyi nil))
		  (send fctn :untyi tem)
		  tem)))
	  ((:any-tyi :tyi-no-hang)
	   (send fctn :tyi arg1))
	  (:any-tyi-no-hang
	   (send fctn :any-tyi arg1))
	  (:read-char
	   (if (not (send fctn :characters)) (go lossage))
	   (setq tem (if arg1 (send fctn :tyi) (send fctn :tyi (car args))))
	   (if (fixnump tem) (int-char tem) tem))
	  ((:any-read-char :read-char-no-hang)
	   (send fctn :read-char arg1 (car args)))
	  (:any-read-char-no-hang
	   (send fctn :any-read-char arg1))
	  (:read-byte
	   (if arg1 (send fctn :tyi) (send fctn :tyi (car args))))
	  (:unread-char
	   (if (not (send fctn :characters)) (go lossage))
	   (send fctn :untyi (if (characterp arg1) (char-int arg1) arg1)))
	  (:write-char
	   (if (not (send fctn :characters)) (go lossage))
	   (send fctn :tyo (if (characterp arg1) (char-int arg1) arg1)))
	  (:write-byte
	   (send fctn :tyo))
	  ((:clear-output :clear-input :force-output :finish :close :eof)
	   nil)
	  (:fresh-line
	   (send fctn :tyo (char-int #/Newline))
	   t)
	  ((:string-out :line-out)
	   (setq tem (string arg1))
	   (do ((len (cond ((second args))
			   (t (string-length tem))))
		(i (cond ((first args)) (t 0))
		   (1+ i)))
	       (( i len) nil)
	     (send fctn :tyo (char-int (char tem i))))
	   (and (eq op :line-out)
		(send fctn :tyo (char-int #/Newline))))
	  (:line-in
	   (let ((buf (make-string #o100 :leader-length (if (numberp arg1) arg1 1))))
	     (setf (fill-pointer buf) 0)
	     (values buf
		     (do ((tem (send fctn :tyi) (send fctn :tyi)))
			 ((or (null tem)
			      (eq tem (char-int #/Newline))
			      (eq tem (char-int #/End)))
			  (adjust-array-size buf (array-active-length buf))
			  (null tem))
		       (vector-push-extend (int-char tem) buf)))))
	  (:string-in
	   ;; ARG1 = EOF, (CAR ARGS) = STRING
	   (loop with start = (or (cadr args) 0)
		 and end = (or (caddr args) (array-length (car args)))
		 while (< start end)
		 as ch = (send fctn :tyi)
		 while ch
		 do (aset ch (car args) (prog1 start (incf start)))
		 finally (and (array-has-leader-p (car args))
			      (store-array-leader start (car args) 0))
		 (and (null ch) arg1 (ferror 'end-of-file-1 "End of file on ~S." fctn))
		 (return (values start (null ch)))))
	  (:string-line-in
	   ;; ARG1 = EOF, (CAR ARGS) = STRING
	   (loop with start = (or (cadr args) 0)
		 and end = (or (caddr args) (array-length (car args)))
		 while (< start end)
		 as ch = (send fctn :tyi)
		 while (and ch (neq ch (char-int #/Newline)))
		       do (setf (char (car args) (prog1 start (incf start))) (int-char ch))
		 finally (and (array-has-leader-p (car args))
			      (setf (fill-pointer (car args)) start))
		 (and (null ch) arg1 (ferror 'end-of-file-1 "End of file on ~S." fctn))
		 (return (values start (null ch) (neq ch #/Return)))))
	  (:operation-handled-p (memq arg1 (send fctn :which-operations)))
	  (:characters t)
	  (:element-type
	   (if (send fctn :characters) 'character
	     (let ((value (send fctn :send-if-handles :byte-size)))
	       (if value `(unsigned-byte ,value) 'fixnum))))
	  (:direction
	   (let ((ops (send fctn :which-operations)))
	     (if (memq :tyi ops)
		 (if (memq :tyo ops) :bidirectional :input)
	       (if (memq :tyo ops) :output nil))))
	  (:send-if-handles
	   (if (memq arg1 (send fctn :which-operations))
	       (lexpr-send fctn arg1 args)))
	  (otherwise
	   (go lossage))))
   lossage
      (ferror :unclaimed-message "The stream operation ~S is not supported by ~S"
	      op fctn)))

(defmacro selectq-with-which-operations (thing &body clauses)
  "Like SELECTQ, but automatically recognizes :WHICH-OPERATIONS.
:WHICH-OPERATIONS is handled by returning a list of all the
keywords which are tested for in the clauses."
  (let (otherwise)
    (when (memq (caar (last clauses)) '(t otherwise :otherwise))
      (setq otherwise (last clauses)
	    clauses (butlast clauses)))
    `(selectq ,thing
       ,@clauses
       (:which-operations ',(loop for clause in clauses
				  appending (if (consp (car clause))
						(car clause)
					      (list (car clause)))))
       . ,otherwise)))

(defprop null-stream t io-stream-p)
(defun null-stream (op &rest args &aux tem)
  "An I//O stream which ignores output and gives instant end-of-file on input."
  (selectq-with-which-operations op
    ;; These operations signal EOF.
    ((:tyi :tyi-no-hang :tyipeek :get-input-buffer :read-input-buffer
	   :any-tyi :any-tyi-no-hang)
     (and (first args) (ferror 'read-end-of-file "End of file on SI:NULL-STREAM.")))
    ;; Signals EOF differently.
    (:string-in
     (and (first args) (ferror 'read-end-of-file "End of file on SI:NULL-STREAM."))
     (values (third args) t))
    ;; Signals EOF still differently.
    (:line-in
      (setq tem (make-array 0 :type 'art-string
			      :leader-length (and (numberp (first args)) (first args))))
      (and (numberp (first args))
	   (plusp (first args))
	   (setf (fill-pointer tem) 0))
      (values tem t))
    ;; These operations should all return their argument.
    ((:tyo :string-out :line-out :untyi)
     (first args))
    ((:increment-cursorpos :finish :force-output :clear-output :clear-input :listen)
     nil)
    ;; These operations should always return T.
    ((:characters :beep :fresh-line) t)
    ;; Supports nothing in both directions.
    (:direction :bidirectional)
    ;; Handle obscure operations.
    (otherwise (stream-default-handler 'null-stream op (first args) (rest1 args)))))

(defvar *iolst :unbound "String or list of data to read, in READLIST or READ-FROM-STRING.")

(defvar *ioch :unbound "Character position in *IOLST, in READ-FROM-STRING.")

(defvar *ioend :unbound "Character position to stop at, in READ-FROM-STRING.")

(defun readlist (charlist &aux (*ioch nil) (*iolst charlist))
  "Read an expression from the list of characters CHARLIST."
  (read 'readlist-stream))

(defprop readlist-stream t io-stream-p)

(defun readlist-stream (operation &optional arg1 &rest rest)
  (cond ((or (eq operation :any-tyi)
	     (memq operation '(:tyi :tyi-no-hang :any-tyi-no-hang)))
	 (cond ((eq *ioch t)
		(ferror nil "EOF in middle of READLIST"))
	       ((not (null *ioch))
		(prog2 nil *ioch (setq *ioch nil)))
	       ((null *iolst)
		(setq *ioch t)
		40)
	       (t (prog1 (character (car *iolst))
			 (setq *iolst (cdr *iolst))))))
	((eq operation :untyi)
	 (setq *ioch arg1))
	((eq operation :which-operations)
	 '(:tyi :untyi))
	(t (stream-default-handler 'readlist-stream operation arg1 rest))))

(defun cli:read-from-string (string &optional (eof-error-p t) eof-value
			     	    &key (start 0) end preserve-whitespace)
  "Read an expression out of the characters in STRING.
START and END are indices which specify a substring of STRING to be used.
 START defaults to 0 and END to NIL (which means the end of STRING).
Reaching the end of STRING or the specified substring constitutes EOF.
EOF-ERROR-P and EOF-VALUE are passed to the READ function,
 and PRESERVE-WHITESPACE non-NIL causes READ-PRESERVING-WHITESPACE to be used.
Only one object is read.  The first value is that object (or perhaps
 EOF-VALUE) and the second value is the index in STRING at which reading stopped."
  (declare (values contents end-char-position))
  (let ((*iolst string) (*ioch start) (*ioend (or end (string-length string))))
    (values (internal-read 'read-from-string-stream eof-error-p eof-value
			   nil preserve-whitespace)
	    *ioch)))

(defun read-from-string (string &optional (eof-option nil eof-option-p) (start 0)
			 end
			 &aux (*iolst string) (*ioch start)
			 (*ioend (or end (string-length string))))
  "Read an expression out of the characters in STRING.
If EOF-OPTION is supplied, it is returned on end of file;
otherwise, end of file is an error.  START (default 0)
is the position in STRING to start reading at; END is where to stop.

The second value is the index in the string at which reading stopped.
It stops after the first object, even if not all the input is used."
  (declare (values contents end-char-position))
  (values (internal-read 'read-from-string-stream (not eof-option-p) eof-option) *ioch))

(defprop read-from-string-stream t io-stream-p)

(defun make-string-input-stream (string &optional (start 0) end)
  "Return a stream from which one can read the characters of STRING, or some substring of it.
START and END are indices specifying a substring of STRING;
they default to 0 and NIL (NIL for END means the end of STRING)."
  (setq string (string string))
  (let-closed ((*ioch start)
	       (*ioend (or end (length string)))
	       (*iolst string))
    'read-from-string-stream))
    
(defun read-from-string-stream (operation &optional arg1 &rest rest)
  (cond ((or (eq operation :tyi) (eq operation :any-tyi))
	 (if (= *ioch *ioend)
	     nil
	   (prog1 (char-int (char *iolst *ioch))
		  (incf *ioch))))
	((eq operation :untyi)
	 (when arg1
	   (setq *ioch (1- *ioch))))
	((eq operation :get-string-index)
	 *ioch)
	((eq operation :which-operations)
	 '(:tyi :untyi :get-string-index))
	(t (stream-default-handler 'read-from-string-stream operation arg1 rest))))

(defun flatsize (x &aux (*ioch 0))
  "Return the number of characters it takes to print X with quoting."
  (prin1 x (function flatsize-stream))
  *ioch)

(defun flatc (x &aux (*ioch 0))
  "Return the number of characters it takes to print X with no quoting."
  (princ x (function flatsize-stream))
  *ioch)

(defprop flatsize-stream t io-stream-p)

(defun flatsize-stream (operation &optional arg1 &rest rest)
  (cond ((eq operation :tyo)
	 (incf *ioch))
	((eq operation :which-operations)
	 '(:tyo))
	(t (stream-default-handler 'flatsize-stream operation arg1 rest))))

(defun read-line (&optional (stream *standard-input*) (eof-error-p t) eof-value recursive-p
		  				      options)
  "Read a line from STREAM and return it as a string.
The string does not include the final Newline character, and is empty if nothing was read.
The second value is T if the line was terminated by EOF.
EOF-ERROR-P says whether an error should be signalled if eof occurs at the start of
 the line. If it is NIL and eof occurs at the start of the line, we return EOF-VALUE and T
RECURSIVE-P is ignored.
If the stream supports the :RUBOUT-HANDLER operation, we use it.
OPTIONS is a list of rubout handler options, passed to WITH-INPUT-EDITING if it is used."
  (declare (values line eof-flag))
  (declare (ignore recursive-p))
  (multiple-value-bind (string eof-flag)
      (read-delimited-string '(#/Newline #/End)
			     stream
			     eof-error-p
			     options)
    (if (and eof-flag (zerop (length string)))
	(values eof-value t)
      (values string eof-flag))))

(defun readline (&rest read-args)
  "Read a line from STREAM and return it as a string.
The string does not include a Return character, and is empty for a blank line.
If EOF-OPTION is non-NIL, it is returned on end of file at beginning of line;
 otherwise, end of file with no text first is an error.
End of file after reading some text is never an error.

If the stream supports the :RUBOUT-HANDLER operation, we use it.
OPTIONS is a list of rubout handler options, passed to WITH-INPUT-EDITING if it is used.

The second value is EOF-OPTION if we exit due to end of file.

The third value is the delimiter which ended the input, or NIL if
it ended due to EOF."
  (declare (arglist &optional stream eof-option options)
	   (values string-or-eof-option eof-flag delimiter))
  (multiple-value-bind (stream eof-error-p eof-value options)
      (decode-kludgey-mucklisp-read-args read-args 1)
    (multiple-value-bind (string eof terminator)
	(read-delimited-string '(#/Newline #/End) stream
			       eof-error-p (car options))
      (values (if (and eof (zerop (length string))) eof-value string)
	      (if eof eof-value)
	      terminator))))

(defun readline-trim (&rest read-args)
  "Read a line from STREAM and return it as a string, sans leading and trailing whitespace.
The string does not include a Return character, and is empty for a blank line.
If EOF-OPTION is non-NIL, it is returned on end of file at beginning of line;
 otherwise, end of file with no text first is an error.
End of file after reading some text is never an error.

If the stream supports the :RUBOUT-HANDLER operation, we use it.
OPTIONS is a list of rubout handler options, passed to WITH-INPUT-EDITING if it is used.

The second value is T if we exit due to end of file."
  (declare (arglist &optional stream eof-option options)
	   (values string eof))
  (multiple-value-bind (string eof)
      (apply #'readline read-args)
    (values
      (if eof string (string-trim '(#/Space #/Tab) string))
      eof)))

(defun readline-or-nil (&rest read-args)
  "Read a line from STREAM and return it as a string, or return NIL if line is empty.
The string does not include a Return character.
If EOF-OPTION is non-NIL, it is returned on end of file at beginning of line;
 otherwise, end of file with no text first is an error.
End of file after reading some text is never an error.

If the stream supports the :RUBOUT-HANDLER operation, we use it.
OPTIONS is a list of rubout handler options, passed to WITH-INPUT-EDITING if it is used.

The second value is T if we exit due to end of file."
  (declare (arglist &optional stream eof-option options)
	   (values string-or-nil eof))
  (multiple-value-bind (string eof)
      (apply #'readline read-args)
    (values
      (if eof string
	(setq string (string-trim '(#/Space #/Tab) string))
	(if (equal string "") nil string))
      eof)))

(defun read-delimited-string (&optional (delimiter #/End) (stream *standard-input*)
			      eof-error-p rh-options (buffer-size 100.))
  "Reads input from STREAM until DELIMITER is found; returns a string.
Uses the rubout handler if STREAM supports that.
DELIMITER is either a character or a list of characters.
 (Characters may be fixnums or character objects).
Values are:
 The string of characters read, not including the delimiter
 T if input ended due to end of file
 The delimiter character read (as a fixnum), or NIL if ended at EOF.
EOF-ERROR-P if non-NIL means get error on end of file before any input is got.
RH-OPTIONS are passed to WITH-INPUT-EDITING.
BUFFER-SIZE is the size to make the buffer string, initially."
  (declare (values string eof-flag delimiter))
  (setq stream (decode-read-arg stream))
  (typecase delimiter
    (character (setq delimiter (char-int delimiter)))
    (cons (loop for x in delimiter
		when (characterp delimiter)
		return (setq delimiter (mapcar #'(lambda (x)
						   (if (characterp x) (char-int x) x))
					       delimiter)))))
  (with-stack-list (activation :activation
			       (if (consp delimiter) 'memq 'eq)
			       delimiter)
    (with-stack-list* (options activation rh-options)
      (with-input-editing (stream options)
	(do ((buffer (make-array buffer-size :type art-string :fill-pointer 0)))
	    (())
	  (let ((ch (send stream (if rubout-handler :any-tyi :tyi)
			  (and (zerop (length buffer)) eof-error-p))))
	    (cond ((null ch)
		   (return buffer t))
		  ((consp ch)
		   (when (eq (car ch) :activation)
		     (send stream :tyo (cadr ch))
		     (return buffer nil (cadr ch))))
		  ((and (not rubout-handler)
			(if (consp delimiter) (memq ch delimiter) (eq ch delimiter)))
		   (return buffer nil ch))
		  (t
		   (vector-push-extend ch buffer)))))))))

(defvar prompt-and-read-format-string :unbound
  "Within PROMPT-AND-READ, holds the FORMAT-STRING argument.")

(defvar prompt-and-read-format-args :unbound
  "Within PROMPT-AND-READ, holds the FORMAT-ARGS arguments.")

(defun prompt-and-read (option format-string &rest format-args)
  "Read an object from *QUERY-IO* according to OPTION,
     prompting using FORMAT-STRING and -ARGS.
OPTION says how to read the object and what its syntax is.  It can be:
 :READ -- use READ to read the object.
 :EVAL-READ -- read an s-expression and evaluate it.  Return the value.
 :EVAL-READ-OR-END -- Like :EVAL-READ, but user can also type just End,
   in which case we return NIL as first value and :END as second.
 (:EVAL-READ :DEFAULT <DEFAULT>) -- Like :EVAL-READ, but user can
   also type just Space to use the default.  Second value is :DEFAULT then.
 (:EVAL-READ-OR-END :DEFAULT <DEFAULT>) -- Analogous.
 :NUMBER -- read a number, terminated by Return or End.
 (:NUMBER :INPUT-RADIX <RADIX> :OR-NIL <BOOLEAN>) -- read using <RADIX> for IBASE,
   and if <BOOLEAN> is non-NIL it allows you to type just Return and returns NIL.
 :CHARACTER -- read one character and return it as a fixnum.
 :DATE -- read a date and return in universal time format.
 (:DATE :PAST-P <PAST-P> :NEVER-P <NEVER-P>) -- read a date.
   The value is in universal time format.
   If <NEVER-P> is non-NIL, /"never/" is accepted, meaning return NIL.
   If <PAST-P> is non-NIL, the date is required to be before the present.
 :STRING -- read a string, terminated by Return.
 :STRING-TRIM -- read a string, terminated by Return.
   Discard leading and trailing whitespace.
 :STRING-OR-NIL -- read a string, terminated by Return.
   Discard leading and trailing whitespace.  If string is empty, return NIL.
 :PATHNAME -- read a pathname and default it.
 (:PATHNAME :DEFAULTS <DEFAULTS-LIST> :VERSION <VERSION-DEFAULT>) --
   read a pathname and default it using the defaults list specified.
   <VERSION-DEFAULT> is passed as the fourth arg to FS:MERGE-PATHNAME-DEFAULTS.
 :PATHNAME-OR-NIL -- like :PATHNAME but if user types just End then NIL is returned.
 (:DELIMITED-STRING :DELIMITER <DELIM> :BUFFER-SIZE <SIZE>) --
   read a string terminated by <DELIM>, which should be a character or a list of them.
   <SIZE> specifies the size of string to allocate initially.
 :DELIMITED-STRING-OR-NIL -- like :DELIMITED-STRING but if user types
   an empty string then NIL is returned.
 (:FQUERY . FQUERY-OPTIONS) -- calls FQUERY with the options."
  (or (lexpr-send *query-io* :send-if-handles :prompt-and-read
		  option format-string format-args)
      (let* ((option-type (if (consp option) (car option) option))
	     (function (get option-type 'prompt-and-read-function))
	     (prompt-and-read-format-string format-string)
	     (prompt-and-read-format-args format-args))
	(cond ((get option-type 'prompt-and-read-no-rubout-function)
	       (funcall (get option-type 'prompt-and-read-no-rubout-function)
			option *query-io*))
	      ((null function)
	       (ferror nil "~S is not a known PROMPT-AND-READ option keyword." option-type))
	      ((send *query-io* :operation-handled-p :rubout-handler)
	       (send *query-io* :rubout-handler
		     (get option-type 'prompt-and-read-rubout-options
			  '((:prompt prompt-and-read-prompt-function)
			    (:activation memq (#/End #/Return))))
		     function option *query-io*))
	      (t
	       (funcall function option *query-io*))))))

(defun prompt-and-read-prompt-function (stream ignore)
  (apply #'format stream prompt-and-read-format-string prompt-and-read-format-args))

;;; Warning!  May not use :PROPERTY function specs (or abbreviations therefore)
;;; in the following code, because that does not work in the cold load.
;;; THIS IS NOT TRUE! Something else was losing. Fucked if I know what, though. -- mly

(defconst eval-read-prinlevel 2)
(defconst eval-read-prinlength 4)

(defprop :eval-read eval-read-prompt-and-read prompt-and-read-no-rubout-function)
(defprop :eval-sexp eval-read-prompt-and-read prompt-and-read-no-rubout-function)
(defprop :eval-form eval-read-prompt-and-read prompt-and-read-no-rubout-function)
(defun eval-read-prompt-and-read (option stream)
  (do (value form flag)
      (())
    (error-restart (error "Try again to type this input.")
      (multiple-value (form flag)
	(with-input-editing (stream
			      '((:prompt prompt-and-read-prompt-function)
				(:activation = #/End)))
	  (let ((ch (send stream :tyi)))
	    (cond ((and (consp option) (get-location-or-nil option :default)
			(eq ch #/Space))
		   (values (get option :default) :default))
		  (t (send stream :untyi ch)
		     (values (read stream)))))))
      (if flag (return form flag)
	(setq value (eval-abort-trivial-errors form))))
    ;; If FORM was not trivial, ask for confirmation of the value it returned.
    (when (or (trivial-form-p form)
	      (let ((*print-level* eval-read-prinlevel)
		    (*print-length* eval-read-prinlength))
		(fquery '(:list-choices nil) "The object is ~S, ok? " value)))
      (return value))
    (terpri stream)))

(defun trivial-form-p (form)
  "T if what FORM evaluates to is inherent in its appearance."
  (cond ((symbolp form)
	 (or (eq form 't) (eq form 'nil) (keywordp form)))
	((eq (car-safe form) 'quote))
	((numberp form))
	((stringp form))))

(defprop :eval-read-or-end eval-read-or-end-prompt-and-read
	 prompt-and-read-no-rubout-function)
(defprop :eval-sexp-or-end eval-read-or-end-prompt-and-read
	 prompt-and-read-no-rubout-function)
(defprop :eval-form-or-end eval-read-or-end-prompt-and-read
	 prompt-and-read-no-rubout-function)
(defun eval-read-or-end-prompt-and-read (option stream)
  (do (value form flag)
      (())
    (error-restart (error "Try again to type this input.")
      (multiple-value (form flag)
	(with-input-editing (stream
			      '((:prompt prompt-and-read-prompt-function)
				(:activation = #/End)))
	  (let ((ch (send stream :any-tyi)))
	    (cond ((and (consp option) (get-location-or-nil option :default)
			(eq ch #/Space))
		   (values (get option :default) :default))
		  ((eq (car-safe ch) :activation)
		   (send stream :tyo (cadr ch))
		   (values nil :end))
		  ((eq ch #/End) (values nil :end))
		  (t (unless (consp ch) (send stream :untyi ch))
		     (values (read stream)))))))
      (if flag (return form flag)
	(setq value (eval-abort-trivial-errors form))))
    ;; If FORM was not trivial, ask for confirmation of the value it returned.
    (when (or (trivial-form-p form)
	      (let ((prinlevel eval-read-prinlevel)
		    (prinlength eval-read-prinlength))
		(fquery '(:list-choices nil) "The object is ~S, ok? " value)))
      (return value))
    (terpri stream)))

(defprop :read read-prompt-and-read prompt-and-read-function)
(defprop :expression read-prompt-and-read prompt-and-read-function)
(defun read-prompt-and-read (ignore stream)
  (values (read stream)))

(defprop :read ((:prompt prompt-and-read-prompt-function)
		(:activation = #/End))
	 prompt-and-read-rubout-options)

(defprop :expression ((:prompt prompt-and-read-prompt-function)
		      (:activation = #/End))
	 prompt-and-read-rubout-options)

(defprop :expression-or-end expression-or-end-prompt-and-read prompt-and-read-function)
(defprop :expression-or-end ((:prompt prompt-and-read-prompt-function)
			     (:activation = #/End))
	 prompt-and-read-rubout-options)
(defun expression-or-end-prompt-and-read (ignore stream)
  (let ((ch (send stream :any-tyi)))
    (if (or (and (consp ch) (eq (car ch) :activation))
	    (and (not rubout-handler) (eq ch #/End)))
	(progn
	  (if (consp ch)
	      (send stream :tyo (cadr ch)))
	  (values nil :end))
      (when (atom ch) (send stream :untyi ch))
      (values (read stream)))))

(defprop :character character-prompt-and-read prompt-and-read-no-rubout-function)
(defun character-prompt-and-read (option stream)
  (block char
    (prompt-and-read-prompt-function stream nil)
    (let ((char (send stream :tyi))
	  (*standard-output* stream))
      (when (and (consp option) (get option :or-nil))
	(cond ((memq char '(#/quote #/c-q))
	       (setq char (send stream :tyi)))
	      ((= char #/Clear-input)
	       (princ "none")
	       (return-from char nil))))
      (format:ochar char :editor)
      char)))

(defprop :character-list character-list-prompt-and-read prompt-and-read-function)
(defun character-list-prompt-and-read (ignore stream)
  (concatenate 'list (readline stream)))

(defprop :number number-prompt-and-read prompt-and-read-function)
(defun number-prompt-and-read (option stream)
  (let ((*read-base* (or (and (consp option) (get option :input-radix)) *read-base*))
	(string (readline-trim stream)))
    (if (and (consp option) (get option :or-nil)
	     (equal string ""))
	nil
      (condition-case ()
	  (let* ((number (read-from-string string)))
	    (if (numberp number) number
	      (ferror 'read-error-1 "That is not a number.")))
	(end-of-file (ferror 'read-error-1 "That is not a number."))))))

(defprop :integer integer-prompt-and-read prompt-and-read-function)
(defun integer-prompt-and-read (option stream)
  (let ((*read-base* (or (and (consp option) (get option :input-radix)) *read-base*))
	(string (readline-trim stream)))
    (if (and (consp option) (get option :or-nil)
	     (equal string ""))
	nil
      (condition-case ()
	  (let* ((number (read-from-string string)))
	    (if (integerp number) number
	      (ferror 'read-error-1 "That is not an integer.")))
	(end-of-file (ferror 'read-error-1 "That is not an integer."))))))

(defprop :small-fraction small-fraction-prompt-and-read prompt-and-read-function)
(defun small-fraction-prompt-and-read (option stream)
  (let ((string (readline-trim stream)))
    (if (and (consp option) (get option :or-nil)
	     (equal string ""))
	nil
      (condition-case ()
	  (let* ((number (read-from-string string)))
	    (if (and (numberp number) (realp number) ( 0.0 number 1.0))
		(float number)
	      (ferror 'read-error-1 "That is not a fraction between 0 and 1.")))
	(end-of-file (ferror 'read-error-1 "That is not a fraction between 0 and 1."))))))

(defprop :date date-prompt-and-read prompt-and-read-function)
(defun date-prompt-and-read (option stream)
  (let ((string (readline-trim stream)))
    (if (equalp string "never")
	(if (and (consp option)
		 (get option :never-p))
	    nil
	  (ferror 'read-error-1 "Never is not allowed here."))
      (let* ((past-p (and (consp option) (get option :past-p)))
	     (date (condition-case (error)
		       (time:parse-universal-time string 0 nil (not past-p))
		     (time:parse-error
		      (ferror 'read-error-1 "~A" (send error :report-string))))))
	(and past-p (> date (get-universal-time))
	     (ferror 'read-error-1 "~A is not in the past."
		     (time:print-universal-time date nil)))
	date))))

(defprop :string-or-nil string-or-nil-prompt-and-read prompt-and-read-function)
(defun string-or-nil-prompt-and-read (ignore stream)
  (readline-or-nil stream))

(defprop :string string-prompt-and-read prompt-and-read-function)
(defun string-prompt-and-read (ignore stream)
  (readline stream))

(defprop :string-trim string-trim-prompt-and-read prompt-and-read-function)
(defun string-trim-prompt-and-read (ignore stream)
  (readline-trim stream))

(defprop :string-list string-list-prompt-and-read prompt-and-read-function)
(defun string-list-prompt-and-read (ignore stream)
  (let ((str1 (readline stream))
	j accum)
    (do ((i 0))
	(())
      (setq j (string-search-char #/, str1 i))
      (let ((str2 (string-trim " " (substring str1 i j))))
	(unless (equal str2 "")
	  (push str2 accum)))
      (unless j (return (nreverse accum)))
      (setq i (1+ j)))))

(defprop :pathname pathname-prompt-and-read prompt-and-read-function)
(defun pathname-prompt-and-read (option stream)
  (let ((defaults (if (consp option) (get option :defaults) *default-pathname-defaults*))
	(string (readline stream)))
    (fs:merge-pathname-defaults string defaults
				fs:*name-specified-default-type*
				(or (and (consp option) (get option :default-version))
				    :newest))))

(defprop :pathname-or-end pathname-or-end-prompt-and-read prompt-and-read-function)
(defun pathname-or-end-prompt-and-read (option stream)
  (let ((defaults (if (consp option) (get option :defaults) *default-pathname-defaults*)))
    (multiple-value-bind (string nil terminator)
	(readline stream)
      (if (and (equal string "") (eq terminator #/End))
	  #/End
	(fs:merge-pathname-defaults string defaults
				    fs:*name-specified-default-type*
				    (or (and (consp option) (get option :default-version))
					:newest))))))

(defprop :pathname-or-nil pathname-or-nil-prompt-and-read prompt-and-read-function)
(defun pathname-or-nil-prompt-and-read (option stream)
  (let ((defaults (if (consp option) (get option :defaults) *default-pathname-defaults*)))
    (multiple-value-bind (string nil terminator)
	(readline stream)
      (unless (and (equal string "") (eq terminator #/End))
	(fs:merge-pathname-defaults string defaults
				    fs:*name-specified-default-type*
				    (or (and (consp option) (get option :default-version))
					:newest))))))

(defprop :fquery fquery-prompt-and-read prompt-and-read-no-rubout-function)
(defprop fquery fquery-prompt-and-read prompt-and-read-no-rubout-function)   ;Obsolete
(defun fquery-prompt-and-read (option *query-io*)
  (apply #'fquery (if (consp option) (cdr option))
		  prompt-and-read-format-string prompt-and-read-format-args))

(defprop :delimited-string delimited-string-prompt-and-read prompt-and-read-no-rubout-function)
(defun delimited-string-prompt-and-read (option stream)
  (read-delimited-string (or (and (consp option) (get option :delimiter)) #/End)
			 stream nil '((:prompt prompt-and-read-prompt-function))
			 (or (and (consp option) (get option :buffer-size))#o100)))

(defprop :delimited-string-or-nil delimited-string-or-nil-prompt-and-read prompt-and-read-no-rubout-function)
(defun delimited-string-or-nil-prompt-and-read (option stream)
  (let ((string
	  (read-delimited-string (or (and (consp option) (get option :delimiter)) #/End)
				 stream nil '((:prompt prompt-and-read-prompt-function))
				 (or (and (consp option) (get option :buffer-size)) #o100))))
    (if (equal string "") nil string)))

(defprop :choose choose-prompt-and-read prompt-and-read-no-rubout-function)
(defun choose-prompt-and-read (option *query-io*)
  (let ((choices (get option :choices)))
    (with-input-editing (*query-io*
			  `((:prompt ,#'(lambda (&rest args)
					  (apply #'prompt-and-read-prompt-function args)
					  (fresh-line query-io)
					  (do ((choices choices (cdr choices))
					       (i 0 (1+ i)))
					      ((null choices))
					    (format *query-io* "~& Type ~D for ~S"
						    i (car choices)))
					  (terpri *query-io*)))
			    (:activation memq (#/End #/Return))))
      (nth (read *query-io*)
	   choices))))

(defprop :assoc assoc-prompt-and-read prompt-and-read-no-rubout-function)
(defun assoc-prompt-and-read (option *query-io*)
  (let ((choices (get option :choices)))
    (with-input-editing (*query-io*
			  `((:prompt ,#'(lambda (&rest args)
					  (apply #'prompt-and-read-prompt-function args)
					  (fresh-line *query-io*)
					  (do ((choices choices (cdr choices))
					       (i 0 (1+ i)))
					      ((null choices))
					    (format *query-io* "~& Type ~D for ~S"
						    i (caar choices)))
					  (terpri *query-io*)))
			    (:activation memq (#/End #/Return))))
      (cdr (nth (read *query-io*)
		choices)))))

(defun (:boolean prompt-and-read-no-rubout-function) (ignore *query-io*)
  (apply #'y-or-n-p prompt-and-read-format-string prompt-and-read-format-args))


