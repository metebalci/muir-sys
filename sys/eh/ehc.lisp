;;; Error handler commands -*- Mode:LISP; Package:EH; Readtable:ZL; Base:8; Lowercase:T -*-

;;; Copyright (C) Hyperbolic Systems Inc., 1982.  All wrongs reversed.

;; Commands in the dispatch table are given the SG and the ERROR-OBJECT,
;; and a third arg which is the numeric argument may or may not be passed.

;;>> this seems to be no longer true! -------------------------------
;; Any command which wants to return out of the error handler should
;; do a throw to FINISHED after restarting the erring stack group.
;;>> ----------------------------------------------------------------

;; See elso EHBPT for breakpointing and single-stepping commands

(defvar window-error-handler-old-window nil
  "If inside window error handler, this is either the old selected window or T if none.")

(defvar *command-char* :unbound
  "While calling a debugger command, this is the command character.")

(defparameter *proceed-type-special-keys*
;character lossage
	      '((:store-new-value . #/m-C))
  "Alist of proceed types vs. standard commands that proceed with those proceed types.")

(defparameter *special-command-special-keys* nil
  "Alist of special-command keywords vs. standard characters that run them.")

(defvar *special-commands* :unbound
  "List of special command keywords provided by this error.")

(defconst *inhibit-debugger-proceed-prompt* nil
  "Non-NIL means do not list available Super-commands on entry to debugger.")

(defun command-loop (error-sg error-object
		     &aux function sexp 
		     (*evalhook* nil)
		     (*special-commands* nil)
		     (window-error-handler-old-window nil)
		     io-buffer
		     reading-command)
  (when error-object
    (setq *special-commands* (send error-object :special-command :which-operations))
    (send error-object :initialize-special-commands))
  (when (setq io-buffer (send *standard-input* :send-if-handles :io-buffer))
    (%bind (locf (tv:io-buffer-output-function io-buffer)) 'io-buffer-output-function)
    (%bind (locf (tv:io-buffer-input-function io-buffer)) nil))
  (inheriting-variables-from (error-sg)  ;Do this every time around the loop in case of setq
    (catch-error-restart ((sys:abort error) "Return to debugger command loop.")
      (catch 'quit
	(show-function-and-args error-sg)
	(warn-about-special-variables error-sg)
	(unless *inhibit-debugger-proceed-prompt*
	  (describe-proceed-types error-sg error-object)))))
  (error-restart (abort "Return to debugger command loop")
    (do ((numeric-arg nil nil)
	 (-)
	 (+ (symeval-in-stack-group '- error-sg))
	 (++ (symeval-in-stack-group '+ error-sg))
	 (+++ (symeval-in-stack-group '++ error-sg))
	 (* (symeval-in-stack-group '* error-sg))
	 (** (symeval-in-stack-group '** error-sg))
	 (*** (symeval-in-stack-group '*** error-sg))
	 (// (symeval-in-stack-group '// error-sg))
	 (//// (symeval-in-stack-group '//// error-sg))
	 (////// (symeval-in-stack-group '////// error-sg))
	 (*values* (symeval-in-stack-group '*values* error-sg)))
	(())
      (inheriting-variables-from (error-sg)  ;Do this every time around the loop in case of setq
	(unless error-handler-running
	  (setq error-depth 1))
	(catch-error-restart ((sys:abort error) "Return to debugger command loop.")
	  (catch 'quit
	    (fresh-line *standard-output*)
	    (dotimes (i error-depth)
	      (send *standard-output* :tyo #/))
	    (do-forever				;This loop processes numeric args
	      ;; Read the next command or sexp, with combined rubout processing.
	      (multiple-value-setq (function sexp)
		(command-loop-read))
	      ;; If it's a character, execute the definition or complain.
	      (cond ((numberp function)
		     (setq numeric-arg
			   (cond ((null numeric-arg)
				  (format t " Argument: ~C"
					  (if (eq function -1) #/- (digit-char function)))
				  function)
				 ((eq function -1)
				  (beep)
				  numeric-arg)
				 (t
				  (princ (digit-char function))
				  (+ function (* 10. numeric-arg))))))
		    (function
		     (if numeric-arg (tyo #/space))
		     (format t "~C " sexp)
		     (if (not (fdefinedp function))
			 (return (format t "~S undefined debugger function!!" function))
		       (let ((*command-char* (int-char sexp)))
			 (return (if (not numeric-arg)
				     (funcall function error-sg error-object)
				     (funcall function error-sg error-object numeric-arg))))))
		    ;; If there was no command, there was a sexp, so eval it.
		    (t
		     (catch 'quit
		       (setq +++ ++ ++ + + -)
		       (let (values)
			 (unwind-protect
			     (setq values (sg-eval-in-frame error-sg
							    (setq - sexp) current-frame t))
			   (push (unless (eq values error-flag) values) *values*))
			 (unless (eq values error-flag)
			   (setq ////// //// //// //)
			   (setq *** ** ** *)
			   (setq // values * (car //))
			   (dolist (value //)
			     (terpri)
			     (print-carefully () (funcall (or prin1 #'prin1) value))))))
		     (return))))))))))

;Errors in error handler commands can be reported this way.
(defun barf (format-string &rest args)
  (apply #'format t format-string args)
  (throw 'quit nil))

(defvar reading-command nil
  "Used in the debugger. Bound to T while reading a command char, for the io-buffer function.")

;; Read from *STANDARD-INPUT* either a control-character (or ? or Help)
;; or a s-expression.  Return FUNCTION and CHAR or return NIL and the s-expression.
(defun command-loop-read ()
  (prog (char sexp flag function)
     retry
	;; Read a character.
	(let ((reading-command t))
	  (setq char (send *standard-input* :tyi)))
	;; Now, if the char is special, echo and return it.
;character lossage
	(cond ((rassq char *proceed-type-special-keys*)
	       (return (values 'com-proceed-specified-type char)))
	      ((rassq char *special-command-special-keys*)
	       (return (values 'com-special-command char)))
	      ((or ( 0 (char-bits char))
		   (command-lookup char))
	       (when (setq function (command-lookup char))
		 (cond ((eq function 'com-rubout)
			(go retry))
		       ((eq function 'com-number)
			(setq function (or (digit-char-p (make-char char))
					   -1))))	;else it's a "-"
		 (return (values function char)))))
       ;; Otherwise, unread it and read an s-exp instead.
       (send *standard-input* :untyi char)
       (multiple-value (sexp flag)
	 (with-input-editing (*standard-input*  '((:full-rubout :full-rubout)
						  (:activation = #/end)
						  (:prompt " Eval: ")))
	   (si:read-for-top-level nil nil nil)))
       (when (eq flag ':full-rubout)
	 (go retry))
       (return (values nil sexp))))

;; Rubout.  Flush numeric arg.
(defun com-rubout (ignore ignore &optional ignore)
  "Flushes the numeric arg, if any."
  (throw 'quit nil))

;; Control-0 though Control-Meta-9, Control-- through Control-Meta--
(setf (documentation 'com-number 'function)
      "Used to give a numeric argument to debugger commands.")

(defun io-buffer-output-function (ignore char &aux tem)
  (cond ;; Blips shouldn't get here, but don't die
	((not (numberp char)) char)
	;; Don't intercept commands
	((and reading-command (command-lookup char)) char)
	((setq tem (assq char tv:kbd-intercepted-characters))
	 (multiple-value-prog1
	   (funcall (cadr tem) char)
	   (format t "~&Back to debugger.~%")))
	;; Compatibility with ancient history
;character lossage
	((eq char (char-int #/c-G))
	 (tv:kbd-intercept-abort (char-int #/c-G)))
	(t char)))

(defun command-lookup (char)
  "Return the debugger command function for CHAR, or NIL."
  (aref command-dispatch-table (char-bits char)
			       (char-code (char-upcase char))))


(defun describe-proceed-types (sg error-object)
  "Print documentation of the available proceed-types and characters to get them.
ERROR-OBJECT is the object to document.  Output goes to *STANDARD-OUTPUT*."
  (when error-handler-running
    (let* ((proceed-types  (send error-object :user-proceed-types
				 (sg-condition-proceed-types sg error-object)))
	   (resume-handlers (symeval-in-stack-group 'condition-resume-handlers sg))
	   (abort-handler (find-resume-handler abort-object nil resume-handlers)))
      (do ((keywords (append proceed-types *special-commands*)
		     (cdr keywords))
	   (proceed-types proceed-types
			  (cdr proceed-types))
	   tem
	   this-one-for-abort
	   (i 0 (1+ i)))
	  ((null keywords))
	(if (zerop i)
	    (format t "~&~%Commands available for this particular error:~2%"))
	(format t "~C" (+ (char-int #/S-A) i))
	(when proceed-types
	  (setq this-one-for-abort
		(eq (find-resume-handler error-object (car keywords) resume-handlers)
		    abort-handler))
	  (if this-one-for-abort (setq abort-handler nil)))
	(cond ((and (zerop i) (atom (car proceed-types)))
	       ;; Resume only works for proceed-types that are atomic.
	       (format t ", ~C" #/Resume))
	      ((setq tem (assq (car keywords)
			       (if proceed-types *proceed-type-special-keys*
				 *special-command-special-keys*)))
	       (format t ", ~C" (cdr tem)))
	      ;; If Abort is synonymous with this one, mention that.
	      (this-one-for-abort
	       (format t ", ~C" #/Abort)))
	(format t ":~13T")
	(send error-object
	      (if proceed-types
		  :document-proceed-type
		  :document-special-command)
	      (car keywords) *standard-output* resume-handlers)
	(send *standard-output* :fresh-line))
      (when abort-handler
	;; Abort is not currently synonymous with any of the proceed types.
	;; So document it specially.
	(format t "~C:~13T" #/Abort)
	(send abort-object :document-proceed-type (second abort-handler)
	      *standard-output* resume-handlers)
	(send *standard-output* :fresh-line)))))

;;;; Utility functions used by the top level, and various commands.

(defun print-brief-error-backtrace (sg error-object)
  (declare (ignore error-object))
  (format t "~&While in the function ")
  (short-backtrace sg nil error-message-backtrace-length error-locus-frame)
  (terpri)
  (let ((hook (symeval-in-stack-group 'error-message-hook sg)))
    (if hook (funcall hook))))

(defun read-object (&rest prompt-and-read-args)
  "Like PROMPT-AND-READ but executes in the erring stack group."
  (declare (arglist option format-string &rest format-args))
  (cond (window-error-handler-old-window
	 (apply #'window-read-object prompt-and-read-args))
	(t
	 (let ((otoc (sg-flags-trap-on-call error-sg)))
	   (setf (sg-flags-trap-on-call error-sg) 0)
	   (unwind-protect
	     (values-list
	       (sg-eval-in-frame error-sg `(apply #'prompt-and-read ',prompt-and-read-args)
				 current-frame t))
	     (setf (sg-flags-trap-on-call error-sg) otoc))))))

(defun leaving-error-handler ()
  "Called when resuming erring program and not coming back to the debugger.
Special hacks cause this function to be called, in the debugger SG,
if the debugger's foothold is thrown through.
Deactivates the debugger window if one was in use."
  (setq tv:cold-load-stream-owns-keyboard
	saved-cold-load-stream-owns-keyboard)
  (and window-error-handler-old-window
       (tv:delaying-screen-management
	 (if (eq window-error-handler-old-window t)
	     (send error-handler-window :deselect t)
	     (send window-error-handler-old-window :select))
	 ;;If this doesn't leave the window still on the screen, it is useless, so free it.
	 (or (tv:sheet-exposed-p error-handler-window)
	     (send error-handler-window :deactivate)))))

(defun proceed-error-sg (&rest args)
  (leaving-error-handler)
  (without-interrupts
    (free-second-level-error-handler-sg %current-stack-group)
    (stack-group-resume error-sg (copylist args))))

;; Continue the stack group, returning VAL if specified
(defun proceed-sg (sg &optional val)
  (leaving-error-handler)
  (without-interrupts
    (free-second-level-error-handler-sg %current-stack-group)
;;;---!!! >>ERROR; No way known to do LOCF on SG-PLIST.
;;;---!!!    (cond ((getf (sg-plist sg) 'single-macro-dispatch)
;;;---!!!	   (setf (getf (sg-plist sg) 'single-macro-dispatch) nil)
;;;---!!!	   (setf (sg-inst-disp sg) 2)))
    (stack-group-resume sg val)))

;;;; Backtrace commands.

;; Short backtraces contain only function names.  Full ones contain arg names and values.
;; Both versions take arguments the same way.  The first is the SG, and the
;; second is ignored so that the functions may be used as commands.
;; They will print no more than N frames if N is present.
;; If SKIP is nonzero, the first that many frames are skipped before the
;; N frames are printed.  Used to put them in curly brackets, but that was
;; fairly useless.

;; This prints out like the Maclisp BAKTRACE, and does not TERPRI at beginning
;; nor end.

;; Conrtol-B
(defun com-short-backtrace (sg ignore &optional (n most-positive-fixnum))
  "Prints a brief (function names only) backtrace of the stack.
Optional numeric arg determines how far back to go."
  (short-backtrace sg nil n))

(defun short-backtrace (sg ignore &optional (n most-positive-fixnum) start-frame uninteresting-flag)
  (print-backtrace sg n start-frame uninteresting-flag
		   #'(lambda (sg frame count)
		       (let ((width (or (send *standard-output* :send-if-handles
								:size-in-characters)
					40.)))
			 (format:breakline width nil
			   (or (zerop count) (princ "  "))
			   (prin1 (function-name
				    (rp-function-word (sg-regular-pdl sg) frame))))))))

(defun full-backtrace (sg ignore &optional (n most-positive-fixnum) start-frame uninteresting-flag)
  "Gives a full (includes args) backtrace. Optional numeric arg determines how far back to go."
  (print-backtrace sg n start-frame uninteresting-flag
		   #'(lambda (sg frame ignore)
		       (print-function-and-args sg frame))))

(defun print-backtrace (sg n start-frame uninteresting-flag
			frame-printer-function)
  (do ((frame (or start-frame current-frame)
	      (funcall (if uninteresting-flag
			   #'sg-next-active
			   #'sg-next-interesting-active)
		       sg frame))
       (i 0 (1+ i)))
      ((or ( i n) (null frame)) nil)
    (funcall frame-printer-function sg frame i)))

(defun full-backtrace-uninteresting (sg ignore &optional (n most-positive-fixnum) start-frame)
  "Gives an exhaustive (includes args and /"uninteresting/" frames) backtrace.
Optional numeric arg determines how far back to go."
  (full-backtrace sg nil n start-frame t))

(defun print-function-and-args (sg frame &optional describe-function-source-file
				&aux function function-name (rp (sg-regular-pdl sg))
				(*print-level* function-prinlevel)
				(*print-length* function-prinlength))
  "Print the function called in FRAME, and the arguments it has."
  (setq function (rp-function-word rp frame))
  (setq function-name (function-name function))
  (catch-error (format t "~%~S:" function-name) nil)
  (when (typep function 'compiled-function)
    (format t " (P.C. = ~D)"			;Note that this displays the return-pc,
	    (rp-exit-pc rp frame)))		; which is one greater than the D-LAST.  
  (if describe-function-source-file (describe-function-source-file function))
  (terpri)
  (when (eq (car-safe function-name) :method)
    (print-carefully "self"
      (format t "   (~S is ~S)~%" 'self (symeval-in-stack-group 'self sg frame))))
  (print-frame-args sg frame 3))

(defun print-frame-args (sg frame indent
			 &aux (*print-level* error-message-prinlevel)
			      (*print-length* error-message-prinlength)
			      function nargs-supplied nargs-to-print
			      (rp (sg-regular-pdl sg))
			      nargs-expected nargs-required active-flag
			      lexpr-call rest-arg-p rest-arg-value)
  "Print the arguments in FRAME, indenting lines by INDENT chars.
If the function called in FRAME wants a rest arg, we return T
/(so our caller can refrain from mentioning local 0,
if he is going to print the locals)."
  (setq function (rp-function-word rp frame)
	nargs-supplied (rp-number-args-supplied rp frame))
  (setq active-flag (sg-frame-active-p sg frame))
  (cond (active-flag
	 (when (legitimate-function-p function)
	   (setq nargs-required
		 (ldb %%arg-desc-min-args (args-info function)))
	   (setq nargs-expected
		 (ldb %%arg-desc-max-args (args-info function))))
	 (multiple-value (rest-arg-value rest-arg-p lexpr-call)
	   (sg-rest-arg-value sg frame))
	 (setq nargs-to-print (sg-number-of-spread-args sg frame)))
	(t
	 (princ "  Frame still accumulating args;
  possible args or stack temps follow:
")
	 (let ((tem (sg-previous-open sg frame)))
	   (setq nargs-to-print (- (if tem (- tem 4)
				       (sg-regular-pdl-pointer sg))
				   frame)
		 nargs-supplied nargs-to-print))))
  ;; Print the individual args.
  (dotimes (i nargs-to-print)
    (and (= i nargs-supplied)
	 (if (and nargs-required (< i nargs-required)) (format t "   --Missing args:--~%")
	     (format t "   --Defaulted args:--~%"))) ;These "args" weren't supplied
    (and nargs-required (< nargs-supplied nargs-required) (= i nargs-required)
	 (format t "   --Optional args:--~%"))	;End of truly missing args
    (and nargs-expected (= i nargs-expected)    ;Called with too many args
	 (format t "   --Extraneous args:--~%"))
    (format t "~VTArg ~D" indent i)
    (and active-flag (display-arg-name " (~A)" function i))
    ;; Print the arg value unless the arg is missing (val is garbage).
    (cond ((not (and nargs-required
		     (> nargs-required nargs-supplied)
		     ( i nargs-supplied)))
	   (princ ": ")
	   (catch-error (prin1 (sg-frame-arg-value sg frame i))) nil))
    (terpri))
  ;; Print the rest arg if any.
  (cond (rest-arg-p
	 (format t "~VTRest arg" indent)
	 (display-local-name " (~A)" function 0)
	 (princ ": "))
	(lexpr-call
	 (format t "~VTExtraneous Rest Arg: " indent)))
  (when (or rest-arg-p lexpr-call)
    (catch-error (prin1 rest-arg-value) nil)
    (terpri))
  rest-arg-p)

(defun display-value-name (format-string function valuenum &aux name)
  "Print the name of value number VALUENUM of FUNCTION, using FORMAT-STRING.
If there is no name known for such a value, prints nothing."
  (setq name (value-name function valuenum))
  (and name (format t format-string name)))

(defun display-local-name (format-string function localno &aux name)
  "Print the name of local number LOCALNO of FUNCTION, using FORMAT-STRING.
If there is no such local or no name known, prints nothing."
  (setq name (local-name function localno))
  (and name (format t format-string name)))

(defun display-arg-name (format-string function argno &aux name)
  "Print the name of arg number ARGNO of FUNCTION, using FORMAT-STRING.
If there is no such arg or no name known, prints nothing."
  (setq name (arg-name function argno))
  (and name (format t format-string name)))

;;;; Basic commands for moving between stack frames.

;; UP means closer to the top of the stack, DOWN means the base of the stack.

;; Control-P, <^>
(defun com-up-stack (sg ignore &optional count show-all-flag reverse-flag uninteresting-flag
			       &aux frame count1)
  "Goes up to the previous stack frame (inward; later function calls)"
  (setq count1 (or count 1))
  (and reverse-flag (setq count1 (- count1)))
  (if uninteresting-flag
      (setq frame (sg-previous-nth-open sg current-frame count1))
    (setq frame (sg-previous-nth-interesting-active sg current-frame count1
						    innermost-visible-frame)))
  (cond ((= frame current-frame)
	 (format t (cond (reverse-flag
			  "You are already at the bottom of the stack.~%")
			 (t "You are already at the top of the stack.~%"))))
	(t (setq current-frame frame)
	   (cond ((not show-all-flag) (show-function-and-args sg))
		 (t (show-all sg)))))
  nil)

;; Control-N, <line>
(defun com-down-stack (sg error-object &optional count)
  "Goes down to the next stack frame (outward; earlier function call)"
  (com-up-stack sg error-object count nil t))

;; Meta-P.
(defun com-up-stack-all (sg error-object &optional count)
  "Goes up to the previous stack frame (inward; later function call)
and shows the args, locals and compiled code."
  (com-up-stack sg error-object count t))

;; Meta-N.
(defun com-down-stack-all (sg error-object &optional count)
  "Goes down to the next stack frame (outward; earlier function call)
and shows the args, locals and compiled code."
  (com-up-stack sg error-object count t t))

;; Meta-<.
(defun com-top-stack (sg &rest ignore)
  "Goes to the top of the stack (innermost; most recent call)"
  (setq current-frame (sg-out-to-interesting-active sg error-locus-frame))
  (show-function-and-args sg)
  nil)

;; Meta->.
(defun com-bottom-stack (sg &rest ignore)
  "Goes to the bottom of the stack (outermost; oldest function call)"
  (setq current-frame
	(do ((frame innermost-visible-frame (sg-next-active sg frame))
	     (prev-frame nil frame))
	    ((null frame) prev-frame)))
  (show-function-and-args sg)
  nil)

;; Control-Meta-P.
(defun com-up-stack-uninteresting (sg error-object &optional count)
  "Goes up to the previous stack frame (inwards; later function call)
Includes internal /"uninteresting/" frames, such as EVAL and PROG, etc."
  (com-up-stack sg error-object count nil nil t))

;; Control-Meta-N.
(defun com-down-stack-uninteresting (sg error-object &optional count)
  "Goes down to the next stack frame (inwards; later function call)
Includes internal /"uninteresting/" frames, such as EVAL and PROG, etc."
  (com-up-stack sg error-object count nil t t))

;; Control-Meta-U.
(defun com-up-to-interesting (sg ignore &optional ignore)
  "Goes down to the previous /"interesting/" stack frame (outwards; earlier function call)"
  (setq current-frame (sg-out-to-interesting-active sg current-frame))
  (show-function-and-args sg)
  nil)

;; Control-L, form.
(defun com-clear-and-show (sg error-object &rest ignore)
  "Clears the screen and redisplays the error message."
  (send *standard-output* :clear-screen)
  (print-carefully "error message"
    (send error-object :print-error-message sg nil *standard-output*))
  (show-function-and-args sg)
  (warn-about-special-variables sg)
  (describe-proceed-types sg error-object)
  (unless error-handler-running
    (format t "~2&Examine-only mode; you cannot resume or alter execution.
Type ~C to exit the debugger.~%" #/resume))
  nil)

;; Control-Meta-Q
(defun com-describe-proceed-types (sg error-object &rest ignore)
  "Describes the possible proceed types."
  (describe-proceed-types sg error-object)
  nil)

;; Meta-L.
(defun com-clear-and-show-all (sg &rest ignore)
  "Clears the screen and redisplays the error message, args, locals and compiled code."
  (show-all sg)
  nil)

;; Control-S.
(defun com-search (sg ignore &optional ignore flag &aux key frame)
  "Prompts for a string and searches down the stack for a frame containing a call to a
function whose name contains that string."
  (format t "~%String to search for (end with RETURN):~%")
  (setq key (readline))
  (setq frame 
	(do ((frame current-frame (sg-next-active sg frame))
	     (rp (sg-regular-pdl sg))
	     (name))
	    ((null frame) nil)
	  (setq name (function-name (rp-function-word rp frame)))
	  (setq name (cond ((stringp name) name)
			   ((symbolp name) (string name))
			   (t (format nil "~S" name))))
	  (when (string-search key name)
	    (return frame))))
  (if (null frame)
      (format t "Search failed.~%")
    (setq current-frame frame)
    (if flag
	(show-all sg)
        (show-function-and-args sg))))

;; Not bound to any key
(defun com-search-and-show-all (sg error-object &optional (count 1))
  "Prompts for a string and searches down the stack for a frame containing a call to a
function whose name contains that string, and then displays args, locals and compiled code."
  (com-search sg error-object count t))

;; Control-M
(defun com-bug-report (ignore error-object &optional arg)
  "Mails a bug report containing a backtrace of the stack.
You are prompted for a message. The depth of stack backtrace included is determined
by the optional numeric argument."
  (if (eq *terminal-io* tv:cold-load-stream)
      ;; If windows are losing, don't try switching windows.
      (progn
	(format t "Please type a precise, detailed description
of what you did that led up to the bug.
")
	(bug (send error-object :bug-report-recipient-system)
	     (string-append (zwei:qsend-get-message)
			    #/newline
			    (format:output nil
			      (send error-object :bug-report-description
				    *standard-output* arg)))))
    (format t " Mail a bug report.   Entering the editor...")
    (bug (send error-object :bug-report-recipient-system)
	 (format:output nil
	   "Insert your description of the circumstances here:


"
	   (send error-object :bug-report-description *standard-output* arg))
	 52.)))		;This is the length of the constant, above, minus one.

;;;; The guts of the commands on the previous page.

;; SHOW-FUNCTION-AND-ARGS is regular printing tty stuff.
;; SHOW-ALL clears the screen and then fills it up.
(defun show-function-and-args (sg &optional show-ucode)
  (print-function-and-args sg current-frame)
  (let* ((rp (sg-regular-pdl sg))
	 (function (rp-function-word rp current-frame)))
    (when (and show-ucode
	       (typep function 'microcode-function)
	       (or (get (function-name function) 'compiler::mclap)
		   (get (function-name function) 'compiler::mclap-loaded-info))
	       (fboundp 'compiler:ma-print))
      (compiler::ma-print (function-name function)
			  (cons (sg-trap-micro-pc sg)
				(cdddr (symeval-in-stack-group 'ucode-error-status sg)))))))

(defun show-function-and-args (sg)
  (print-function-and-args sg current-frame))

(defun show-all (sg &aux rp function)
  "Print everything about the current frame, including locals and disassembly."
  (setq rp (sg-regular-pdl sg)
	function (rp-function-word rp current-frame))
  (send *standard-output* :clear-window)
  ;; Print the header, including the function name
  (format t "Frame address ~D" current-frame)
  (unless (zerop (rp-adi-present rp current-frame))
    (terpri)
    (show-adi rp (- current-frame 4)))
  (terpri)
  (if (typep function 'compiled-function)
      (show-all-macro sg current-frame)
    (show-function-and-args sg)))

(defun describe-function-source-file (function)
  (when (or (validate-function-spec function)
	    (functionp function t))
    (let* ((name (function-name function))
	   (file (cadr (assq 'defun (si:get-all-source-file-names name)))))
      (when (and file (neq (send file :host) (fs:get-pathname-host "SYS")))
	(format t " (from file ~A)" file)))))

(defun show-frame-briefly-for-bug-message (sg frame &aux rp function)
  (setq rp (sg-regular-pdl sg)
	function (rp-function-word rp frame))
  (send *standard-output* :fresh-line)
  (if (typep function 'compiled-function)
      (format t "~S (P.C. = ~D)" (fef-name function) (rp-exit-pc rp frame))
    (prin1 (function-name function)))
  (describe-function-source-file function)
  (terpri))

(defun show-frame-for-bug-message (sg frame &aux rp function)
  (setq rp (sg-regular-pdl sg)
	function (rp-function-word rp frame))
  (unless (zerop (rp-adi-present rp frame))
    (terpri)
    (show-adi rp (- frame 4)))
  (terpri)
  (if (typep function 'compiled-function)
      (show-all-macro sg frame t)
    (print-function-and-args sg frame t)))

(defun warn-about-special-variables (sg)
  "Print warnings about vital special variables whose values in SG are peculiar."
  (condition-case ()
      (let ((*print-base* (symeval-in-stack-group '*print-base* sg))
	    (*read-base* (symeval-in-stack-group '*read-base* sg)))
	(if (eq *print-base* *read-base*)
	    (unless (numberp *print-base*)
	      (format t "~&Warning: ~S and ~S are ~D."
		      '*print-base* '*read-base* *print-base*))
	  (format t "~&Warning: ~S is ~D but ~S is ~D (both decimal).~%"
		  '*print-base* *print-base* '*read-base* *read-base*)))
    (error
      (format t "~&Warning: error while trying to find ~S and ~S in ~S."
	      '*print-base* '*read-base* sg)))
  (condition-case ()
      (let ((areaname (area-name (symeval-in-stack-group 'default-cons-area sg))))
	(or (eq areaname 'working-storage-area)
	    (format t "~&Warning: the default cons area is ~S~%" areaname)))
    (error
      (format t "~&Warning: error while trying to find ~S in ~S." 'default-cons-area sg)))
  (condition-case ()
      (if (symeval-in-stack-group 'tail-recursion-flag sg)
	  (format t "~&Note: ~S is set, so some frames may no longer be on the stack.~%"
		  'tail-recursion-flag))
    (error
      (format t "~&Warning: error while trying to find ~S in ~S." 'tail-recursion-flag sg)))
  (format t "~&;Reading in base ~D in package ~A with ~A.~&"
	  *read-base* *package* *readtable*))

(defun show-all-macro (sg frame &optional no-disassembled-code
		       &aux n-locals pc-now name rest-arg-printed nlines where lim-pc
		       (rp (sg-regular-pdl sg))
		       (function (rp-function-word rp frame)))
  (setq n-locals (fef-number-of-locals function)
	name (fef-name function)
	pc-now (rp-exit-pc rp frame)
	lim-pc (compiler::disassemble-lim-pc function))
  (format t "~%~S (P.C. = ~D)" name pc-now)
  (when no-disassembled-code (describe-function-source-file name))
  (terpri)
  (when (eq (car-safe name) :method)
    (format t "  (~S is " 'self)
    (print-carefully "SELF"
      (prin1 (symeval-in-stack-group 'self sg frame)))
    (format t ")~%"))
  (terpri)
  ;; Print the arguments, including the rest-arg which is the first local
  (setq rest-arg-printed (print-frame-args sg frame 0))
  (cond ((sg-frame-active-p sg frame)
	 ;; Print the rest of the locals -- if the frame is active.
	 (dotimes (i n-locals)
	   (cond ((not (and rest-arg-printed (zerop i)))	;Don't show rest arg twice
		  (format t "Local ~D" i)
		  (display-local-name " (~A)" function i)
		  (let ((*print-level* error-message-prinlevel)
			(*print-length* error-message-prinlength))
		    (format t ": ")
		    (print-carefully "local"
		      (prin1 (sg-frame-local-value sg frame i)))
		    (terpri)))))
	 (unless no-disassembled-code
	   (format t "~%Disassembled code:")
	   ;; Figure out how many instructions will fit in the stream we are using.
	   (setq nlines
		 (max disassemble-instruction-count	;don't show absurdly few
		      (cond ((send *standard-output* :operation-handled-p
				   		     :size-in-characters)
			     (setq nlines (nth-value 1
				            (send *standard-output* :size-in-characters))
				   where (nth-value 1
					    (send *standard-output* :read-cursorpos
								    :character)))
			     ;; Leave 1 line for prompt, 1 for extra terpri
			     (- nlines where 2))
			    (t 0))))		;Don't know size of window, use default count
	   (do ((i 0 (1+ i))
		(pc (max (fef-initial-pc function) (- pc-now (truncate nlines 2)))
		    (+ pc (compiler::disassemble-instruction-length function pc))))
	       ((or ( i nlines) ( pc lim-pc))
		(cond ((= pc pc-now)		;If arrow should point after all code,
		       (terpri) (princ "=> "))))
	     (terpri)
	     (princ (if (= pc pc-now) "=> " "   "))
	     (compiler::disassemble-instruction function pc))
	   ;; This kludge is to prevent prompt from triggering a **MORE** when it comes out
	   ;; on the bottom line of the window
	   (send *standard-output* :send-if-handles :notice :input-wait)))))

(defun show-adi (rp idx)
  "Print the ADI at index IDX in the regular pdl RP"
  (format t "~%Additional information supplied with call:")
  (do ((idx idx (- idx 2)))
      (())
    (let ((type (ldb %%adi-type (aref rp idx)))
	  (more-p (%p-ldb %%adi-previous-adi-flag (aloc rp (1- idx)))))
      (select type
	((adi-return-info adi-used-up-return-info)
	 (show-mv-specs rp idx))
	(adi-bind-stack-level
	 (format t "~% Binding stack level: ~S" (aref rp (1- idx))))
	(adi-restart-pc
	 (format t "~% Restart PC on ~S: ~D" 'throw (aref rp (1- idx))))
	(otherwise
	 (format t "~% ~S" (nth type adi-kinds))))
      (if (zerop more-p) (return)))))

(defun show-mv-specs (rp idx)
  (let ((storing-option (nth (ldb %%adi-ret-storing-option (ar-1 rp idx))
			     adi-storing-options)))
    (cond ((eq storing-option 'adi-st-block)
	   (format t "~% Expecting ~D values"
		   (ldb %%adi-ret-num-vals-total (ar-1 rp idx)))
	   (let ((num-already
		   (- (ldb %%adi-ret-num-vals-total (ar-1 rp idx))
		      (ldb %%adi-ret-num-vals-expecting (ar-1 rp idx)))))
	     (or (zerop num-already)
		 (format t "; ~D already returned." num-already))))
	  ((eq storing-option 'adi-st-make-list)
	   (format t "~% Values to be collected for MULTIPLE-VALUE-LIST"))
	  ((eq storing-option 'adi-st-list)
	   (format t "~% Values being collected for MULTIPLE-VALUE-LIST")
	   (format t "; ~D values already returned."
		   (length (aref rp (1- idx)))))
	  ((eq storing-option 'adi-st-indirect)
	   (if (aref rp (1- idx))
	       (format t "~% Multiple values being passed to frame at ~D"
		       (+ 4 (%pointer-difference (aref rp (1- idx))
						 (aloc rp 0))))
	     (format t "~% Multiple values passed to frame, but frame pointer is NIL.
 This means that we were going to pass multiple values
 to a frame that did not want them."))))))

;;;; Commands for looking at special bindings.

;; Control-Meta-S: Print names and values of specials bound by this frame.
;; If SELF is bound in this frame, its instance variables are also included.
(defun com-print-frame-bindings (sg ignore &optional count
				 &aux start end (sp (sg-special-pdl sg)))
				 ;; self-included special-vars
  "Lists the names and values of all special variables bound by this frame."
  ;; Find range of special pdl for this frame together with
  ;; all uninteresting frames called by it.
  (do ((previous-int (sg-previous-interesting-active sg current-frame
						     innermost-visible-frame))
       (previous current-frame (sg-previous-active sg previous innermost-visible-frame)))
      ((equal previous previous-int))
    (multiple-value-bind (maybe-start maybe-end)
	(sg-frame-special-pdl-range sg previous)
      (setq start maybe-start)
      (and maybe-end (setq end (1+ maybe-end)))))
  (cond (start
	 (if (null count) (format t "~&Names and values of specials bound in this frame:~%"))
	 ;; Now look through the specials bound in this frame.
	 (do ((i start (+ i 2)))
	     (( i end))
	   (let ((sym (symbol-from-value-cell-location (aref sp (1+ i)))))
	     ;;(push tem special-vars)
	     ;;(if (eq sym 'self)
	     ;;  (setq self-included i))
	     (when (or (null count) (= count (lsh (- i start) -1)))
	       (format t "~:[~% ~S: ~;~&Value of ~S in this frame:~&   ~]" count sym)
	       (multiple-value-bind (val error)
		   (catch-error (funcall (or prin1 #'prin1) (aref sp i)) nil)
		 (cond (error (princ "void"))
		       (count (got-values val (aref sp (1+ i)) nil))))))))
;; instance variables are NOT special!! Use m-I
;	 ;; List the instance variable of SELF also if SELF is bound in this frame.
;	 (if (and self-included
;		  (typep (aref sp self-included) 'instance)
;		  ;; But not if want only one variable and already got it.
;		  (or (null count)
;		      ( count (lsh (- end start) -1))))
;	     (let* ((self-value (aref sp self-included))
;		    (self-flavor 
;		     (si::instance-flavor self-value))
;		    (self-vars (si::flavor-all-instance-variables-slow self-flavor)))
;	       (unless count
;		 (format t "~2&Non-special instance variables of ~S~&" self-value))
;	       (do ((sv self-vars (cdr sv))
;		    (count-unspecial (lsh (- end start) -1))
;		    (i 1 (1+ i)))
;		   ((null sv))
;		 (when (and (not (memq (car sv) special-vars))
;			    (or (null count)
;				(= (1+ count) (incf count-unspecial))))
;		   (format t "~:[~% ~S: ~;~&Value of instance variable ~S within ~S:~&   ~]"
;			   count (car sv) 'self)
;		   (multiple-value-bind (val error)
;		       (catch-error (funcall (or prin1 #'prin1)
;					     (%instance-ref self-value i)) nil)
;		     (cond (error (princ "void"))
;			   (count (got-values val (%instance-loc self-value i) nil)))))))))
	(t (format t "~&No specials bound in this frame"))))

;; Meta-S: Print the value as seen in the current frame (at the point at which
;; it called out or erred) of a specified variable.
(defun com-print-variable-frame-value (sg ignore &optional ignore &aux var)
  "Print the value of a special variable within the context of the current stack frame.
Prompts for the variable name."
  ;;(terpri)
  (with-input-editing (*standard-input*
			'(;(:full-rubout :full-rubout) -- too obnoxious
			  (:activation char= #/end)
			  (:prompt "Value in this frame of special variable: ")))
    (setq var (si:read-for-top-level nil nil nil))
    (multiple-value-bind (value boundflag loc)
	(symeval-in-stack-group var sg current-frame)
      (if boundflag
	  (got-values value loc nil)
	(princ "Void")))))
;; look goddam it! Instance variables are NOT special!!!
;	(let* ((self-value (symeval-in-stack-group 'self sg current-frame))
;	       (self-pos (and (instancep self-value)
;			      (find-position-in-list var
;						     (si::flavor-all-instance-variables-slow
;						       (si::instance-flavor self-value))))))
;	  (if self-pos
;	      (got-values (%instance-ref self-value (1+ self-pos))
;			  (%make-pointer-offset dtp-locative self-value (1+ self-pos))
;			  nil)
;	    (princ "Void")
;	    nil))))))

;; Meta-I: Print value of instance variable of SELF
(defun com-print-instance-variable (sg ignore &optional ignore)
  "Print the value of an instance VARIABLE of SELF within the context of the current frame.
Prompts for the instance variable name.
With a numeric argument, displays all instance variables of SELF."
  (let ((self-value (symeval-in-stack-group 'self sg current-frame))
	ivars var val)
    (unless (instancep self-value)
      (format t "~&~S is not an instance" 'self)
      (return-from com-print-instance-variable nil))
    (setq ivars (si::flavor-all-instance-variables-slow (si::instance-flavor self-value)))
    (do-forever
      (with-input-editing (*standard-input*
			    '((:prompt "Value in this frame of instance variable: ")
			      (:activation char= #/end)
			      ;(:full-rubout :full-rubout) -- too obnoxious
			      (:command char= #/hand-right)
			      ))
	(setq val (si:read-for-top-level nil nil nil))
	(if (setq var (or (memq val ivars) (mem #'string-equal val ivars)))
	    (let* ((pos (find-position-in-list (setq var (car var)) ivars))
		   (loc (locf (%instance-ref self-value (1+ pos)))))
	      (return-from com-print-instance-variable
		(if (location-boundp loc)
		    (got-values (contents loc) loc nil)
		  (princ "void")
		  (got-values nil loc nil))))
	  (parse-ferror "~S is not an instance variable of ~S" val self-value)))
      ;; If doesn't return, then luser typed Help
      (format t "~&Instance variables of ~S are:~%~4@T ~S" 'self (car ivars))
      (format:breakline nil (princ "    ") (dolist (v (cdr ivars)) (prin1 v))))))

;; Control-Meta-H
(defun com-print-frame-handlers (sg ignore &optional arg)
  "Lists the condition handlers set up in this frame. (includes resume and default handlers)
With an argument, shows all condition handlers active in this frame."
  (let ((handlers-outside (symeval-in-stack-group 'condition-handlers sg
						  (sg-next-active sg current-frame)))
	(default-handlers-outside (symeval-in-stack-group 'condition-default-handlers sg
							  (sg-next-active sg current-frame)))
	(resume-handlers-outside (symeval-in-stack-group 'condition-resume-handlers sg
							 (sg-next-active sg current-frame)))
	(handlers (symeval-in-stack-group 'condition-handlers sg current-frame))
	(default-handlers (symeval-in-stack-group 'condition-default-handlers sg
						  current-frame))
	(resume-handlers (symeval-in-stack-group 'condition-resume-handlers sg
						 current-frame)))
    (unless (and (null arg) (eq handlers handlers-outside))
      (if (and (null arg) (null handlers))
	  (format t "~&Condition handlers bound off, hidden from lower levels.")
	(format t "~&~:[No ~]Condition handlers:~%" handlers)
	(dolist (h (if arg handlers (ldiff handlers handlers-outside)))
	  (format t "~& Handler for ~S" (car h)))))
    (unless (and (null arg) (eq default-handlers default-handlers-outside))
      (if (and (null arg) (null default-handlers))
	  (format t "~&Default handlers bound off, hidden from lower levels.")
	(format t "~&~:[No ~]Default handlers:~%" default-handlers)
	(dolist (h (if arg default-handlers (ldiff default-handlers default-handlers-outside)))
	  (format t "~& Default handler for ~S" (car h)))))
    (unless (and (null arg) (eq resume-handlers resume-handlers-outside))
      (format t "~&Resume handlers:~%")
      (dolist (h (if arg resume-handlers (ldiff resume-handlers resume-handlers-outside)))
	(cond ((eq h t)
	       (format t "~& Barrier hiding all resume handlers farther out.")
	       (return nil))
	      (t
	       (format t "~& Resume handler for ~S,~%  " (car h))
	       (unless (consp (cadr h))
		 (format t "proceed type ~S,~%  " (cadr h)))
	       (apply #'format t (cadddr h))))))
    (if (and (eq resume-handlers resume-handlers-outside)
	     (eq default-handlers default-handlers-outside)
	     (eq handlers handlers-outside)
	     (null arg))
	(format t "~&No handlers set up in this frame."))))


;; Meta-T
(defun com-show-stack-temporaries (sg ignore &optional arg
				   &aux (*print-level* error-message-prinlevel)
				        (*print-length* error-message-prinlength)
				   (rp (sg-regular-pdl sg)))
  "With no argument, show temporary values pushed onto stack by this stack frame.
With an argument of 0, also displays pending open frames, and arguments pushed
 for them (presumably as arguments)
With an argument of -1, displays each word of the regular pdl from the current frame
 to the pdl-pointer. You don't -really- want to do this, do you?"
  (cond ((eq arg -1)
	 (let ((end (sg-regular-pdl-pointer sg))
	       (rp (sg-regular-pdl sg)))
	   (loop for i from (1+ current-frame) below end do
		 (format t "~%~4D: " i)
		 (p-prin1-careful-1 (locf (aref rp i))))))
	(t
	 (loop for this-frame = current-frame then (sg-previous-open sg this-frame)
	       for firstp = t then nil
	       while (and this-frame ( this-frame (sg-regular-pdl-pointer sg)))
	       as function = (rp-function-word rp this-frame)
	       as n-locals = 0 and nargs = 0 and nargs-expected = 0
	       as rest-arg-value = nil and rest-arg-p = nil and lexpr-call = nil
	       until (and (not firstp) (or (eq arg 0)
					   (sg-frame-active-p sg this-frame)
					   (eq function #'foothold)))
	    do (if (eq function #'foothold)
		   (show-foothold sg this-frame)
		 (when (sg-frame-active-p sg this-frame)
		   (when (legitimate-function-p function)
		     (setq nargs-expected
			   (ldb %%arg-desc-max-args (args-info function)))
		     (setq nargs (sg-number-of-spread-args sg this-frame))
		     (multiple-value-setq (rest-arg-value rest-arg-p lexpr-call)
		       (sg-rest-arg-value sg this-frame))
		     (setq n-locals (fef-number-of-locals function))))
		 (let* ((prev-open (sg-previous-open sg this-frame))
			(total (- (if prev-open (- prev-open 4) (sg-regular-pdl-pointer sg))
				  this-frame)))
		   (catch-error (format t "~2&~S" (function-name function)) nil)
		   (when (typep function 'compiled-function)
		     (format t " (P.C. = ~D)" (rp-exit-pc rp this-frame)))
		   (format t "~%Frame index ~D" this-frame)
		   (format t "~%~D arg~:P, ~D local~:P, ~D total in frame"
			   nargs n-locals total)
		   (if (not (zerop (rp-adi-present rp this-frame)))
		       (show-adi rp (- this-frame 4)))
		   (do ((i 0 (1+ i))
			(index (1+ this-frame) (1+ index)))
		       (( i total))
		     (block printed
		       (cond ((< i nargs)
			      (and nargs-expected
				   (= i nargs-expected)
				   (format t "~%  --Extraneous args:--"))
			      (format t "~%  Arg ~D: " i))
			     ((and (= i nargs) rest-arg-p)
			      (format t "~%Rest arg: "))
			     ((and (= i nargs) lexpr-call)
			      (format t "~%Extraneous rest arg: ")
			      (p-prin1-careful-1 (locf rest-arg-value))
			      (return-from printed))
			     ((< i (+ n-locals nargs))
			      (format t "~%Local ~D: " (- i nargs)))
			     (t (format t "~% ~s Temp ~D: "
					(%pointer-plus rp (+ (si:array-data-offset rp)
							     index))
					(- i nargs n-locals))))
		       (p-prin1-careful-1 (locf (aref rp index)))))))
	       (terpri)))))

(defun show-foothold (sg frame)
  (format t "~%Foothold data:")
  (let ((end-of-foothold-data (- (sg-previous-open sg frame) 4))
	(rp (sg-regular-pdl sg)))
    (do ((i (1+ frame) (+ i 2))
	 (sg-q si::stack-group-head-leader-qs (cdr sg-q)))
	((> i end-of-foothold-data))
      (format t "~&~30S: " (car sg-q))
      (let ((dtp (ldb (byte (byte-size %%q-data-type) 0) (aref rp (1+ i)))))
	(if (memq (car sg-q) si::sg-accumulators)
	    (format t "#<~:[Data type ~O~;~:*~A~*~] ~O>"
		    (q-data-types dtp) dtp (%pointer (aref rp i)))
	  (setq dtp (%make-pointer dtp (aref rp i)))
	  (p-prin1-careful (locf dtp)))))))


;>>

;; Control-Meta-C
(defun com-print-open-catch-frames (sg ignore &optional ignore)
  "Print information about all CATCH and UNWIND-PROTECT frames
open around the current function"
  
  )


(defun com-print-lexical-environment (sg ignore &optional arg)
  (declare (ignore arg))




  )

;;;; Other informational commands.

;; Control-A.
(defun com-arglist (sg &rest ignore)
  "Returns the arglist for the current stack frame function."
  (let ((function (rp-function-word (sg-regular-pdl sg) current-frame)))
    (multiple-value-bind (arglist values)
	(arglist function nil)
      (format t "~&Argument list for ~S is ~S~@[  ~S~].~%"
	      (function-name function) arglist values)))
  nil)

(defun got-values (star minus barf)
  (terpri)
  (if barf (princ barf)
    (setq ////// //// //// // // (list star))
    (setq *** ** ** * * star)
    (setq +++ ++ ++ + + - - minus)
    (print-carefully nil (funcall (or prin1 #'prin1) star))))

;; Control-Meta-A
(defun com-get-arg (sg ignore &optional (arg 0))
  "Sets * to the nth arg to the current function, where n is a numeric argument (default 0)
Also sets + to a locative to the arg."
  (multiple-value-bind (a b barf)
     (sg-frame-arg-value sg current-frame arg nil)
    (got-values a b barf)))

;; Control-Meta-L
(defun com-get-local (sg ignore &optional (arg 0))
  "Sets * to the nth local of he current function, where n is a numeric argument
/(default 0) Also sets + to a locative to the local."
  (multiple-value-bind (a b barf)
      (sg-frame-local-value sg current-frame arg nil)
    (got-values a b barf)))

;; Control-Meta-V
(defun com-get-value (sg ignore &optional (arg 0))
  "Sets * to the nth value being returned by the current function, where n is a numeric
argument (default 0) Also sets + to a locative to the value."
  (multiple-value-bind (a b barf)
      (sg-frame-value-value sg current-frame arg nil)
    (got-values a b barf)))


;; Control-Meta-F
(defun com-get-function (sg ignore &optional ignore)
  "Sets * to the current function, and + to a locative to the it."
  (let ((loc (locf (rp-function-word (sg-regular-pdl sg) current-frame))))
    (got-values (contents loc) loc nil)))

;; Control-Meta-T
(defun com-get-stack-temporary (sg ignore &optional (arg 0))
  "Sets * to the nth temporary pushed onto the stack, where is a numeric argument
/(default 0) Also sets + to a locative to the local."
  (multiple-value-bind (a b barf)
      (sg-frame-stack-temporary-value sg current-frame arg nil)
    (got-values a b barf)))

;; Control-Meta-D
(defun com-describe-* (ignore ignore &optional ignore)
  "Describes the value of *"
  (got-values (describe *) + nil))

;; Control-E
(defun com-edit-frame-function (sg &rest ignore)
  "Edit the source code for the current function in Zmacs."
  (if (eq *terminal-io* si:cold-load-stream)
      (format t "~&The editor cannot be invoked since we are using the cold load stream.")
    (let* ((rp (sg-regular-pdl sg))
	   (fn (function-name (rp-function-word rp current-frame))))
      (if fn (ed fn)
	(format t "~&This frame's function's name cannot be determined.")))))


;;;; HELP!

(defconst *com-help-alist* '(((com-help-general "General"
			      "General information about using the debugger") #/G #/g)
			    ((com-help-information "Information"
			      "Various ways of obtaining information about the current stack frame")
			     #/I #/i #/E #/e)
			    ((com-help-frames "Stack Frames"
			      "Selecting Stack Frames to examine") #/F #/f)
			    ((com-help-stepping "Stepping"
			      "Stepping though through the program") #/S #/s)
			    ((com-help-proceeding "Proceeding"
			      "Proceeding from this error and resuming execution")
			      #/P #/p #/X #/x)
			    ((com-help-transferring "Transferring"
			      "Transferring to other systems: Edit, Bug report, Window-based Debugger")
			     #/T #/t)
			    ((com-help-describe-command "Describe"
			      "Give the documentation of the function associated with a command key")
			     #/D #/d #/C #/c)
			    ((ignore "Abort" t) #/abort #/c-Z #/c-G)
			    ((#/help "Help" t) #/help #/?))
  "FQUERY options for used in giving help for debugger commands.")

;; ?, <help>
(defun com-help (sg error-object &optional ignore)
  "Help for using the debugger"
  (prog (command)
   loop
      (with-stack-list (options :choices *com-help-alist* :help-function nil)
	(case (setq command (fquery options "Help for debugger commands. Choose a topic: "))
	  (#/help
	   (terpri)
	   (princ "For additional help in using the debugger, type one of the following:")
	   (terpri)
	   (dolist (x *com-help-alist*)
	     (unless (eq (third (car x)) t)
	       (format t "~&  ~:C~6T~A" (cadr x) (or (third (car x)) (second (car x))))))
	   (go loop))
	  (t (funcall command sg error-object))))))

(defun com-help-general (ignore ignore)	       
  (format t "~2%You are in the debugger.  If you don't want to debug this error, type ~C.
Otherwise you can evaluate expressions in the context of the error, examine
the stack, and proceed//throw//return to recover.
  If you type in a Lisp form, it will be evaluated, and the results printed,
using ~a and base ~d in package ~a. This
evaluation uses the variable environment of the stack frame you are examining.
  Type ~c or ~c to get back to top level, or the previous debugger level.
While in the debugger, ~c quits back to the debugger top level.
  If you think this error indicates a bug in the Lisp machine system, use the
~:c command."
		     #/Abort *readtable* *read-base* *package*
		     #/Abort #/c-Z #/c-G #/c-M))

(defun com-help-information (ignore ignore)
  (format t "~2%~c or ~\lozenged-string\ clears screen and retypes error message.
~c clears screen and types args, locals and compiled code.
~c gives a backtrace of function names.
~c gives a backtrace of function names and argument names and values.
~c is like ~c but shows ~Ss, ~Ss, ~Ss, etc.
~c prints an argument to the current function, and sets * to be that
   argument to let you do more complicated things with it.
   + is set to a locative to that argument, should you want to modify it.
   To specify which argument, type the argument number with Control
   or Meta held down before the ~c.
~c is like ~c but works on the function's locals rather than the args.
~c is like ~c but works on the values this frame is returning.
   (This is useful when you get a trap on exit from function).
~c does likewise for the function itself.
~c prints the arglist of the function in the current frame.
~c prints the value in this frame of a special variable you specify.
~c lists all special variable bindings in this frame.

Use the functions (~S n), (~S n), (~S n) and (~S) to get the
value of an arg, local, value or function-object respectively from an
expression being evaluated. For args and locals, n can be a name or a number.
~S allows numbers only. ~S and ~S on those expressions are also allowed.
" #/c-L "Clear Screen" #/m-L #/c-B #/c-m-B #/m-B #/c-B 'eval 'prog 'cond
  #/c-m-A #/c-m-A #/c-m-L #/c-m-A #/c-m-V #/c-m-A #/c-m-F #/c-A #/m-S #/c-m-S
  'eh:arg 'eh:loc 'eh:val 'eh:fun 'eh:val 'locf 'setf))

(defun com-help-frames (ignore ignore)
  (format t "~%
~c or ~\lozenged-character\ goes down a frame, ~c or ~\lozenged-character\ goes up.
~c and ~c are similar but show args, locals and compiled code.
~c and ~c are similar to ~c and ~c, but they show
   all the internal EVALs, PROGs, CONDs, etc. of interpreted code,
   and function calls whose args are still being computed.
~c and ~c go to the top and bottom of the stack, respectively.
~c reads a string and searches down the stack for a frame
   calling a function whose name contains that substring.
" #/c-N #/line #/c-P #/return #/m-N #/m-P #/c-m-N #/c-m-P #/c-N #/c-P
  #/m-< #/m-> #/c-S))

(defun com-help-stepping (ignore ignore)
  (if error-handler-running
      (format t "~2%~c toggles the trap-on-exit flag for the current frame.
~c sets the trap-on-exit flag for the current frame and all outer frames.
~c clears this flag for the current frame and all outer frames.
Trap on exit also occurs if the frame is thrown through.
~c proceeds like ~C, but first sets the trap-on-next-function-call flag.
~c toggles the trap-on-next-function-call flag.
Functions which get a trap on entry are automatically flagged for
trap on exit as well.  You can un-flag them with ~c.
" #/c-X #/m-X #/c-m-X #/c-D #/resume #/m-D #/c-X)
    (format t "~2%You cannot use the stepping commands, since you are in examine-only mode.
~C exits the debugger." #/resume)))

(defun com-help-proceeding (sg error-object)
  (cond (error-handler-running
	 (format t "~2%~c aborts to previous debugger or other command loop, or to top level.
~c returns a value or values from the current frame.
~c offers to reinvoke the current frame with the same arguments
   originally supplied (as best as they can be determined).
~c offers to reinvoke the current frame, letting you alter
   some of the arguments, or use more or fewer arguments.
~c throws to a specific tag." #/c-Z #/c-R #/c-m-R #/m-R #/c-T)
	 (describe-proceed-types sg error-object))
	(t
	 (format t "~2%You cannot continue execution, since you are in examine-only mode.
~C exits the debugger." #/resume))))

(defun com-help-transferring (ignore ignore)
  (format t "~2%~c calls the editor to edit the current function.
~c enters the editor to send a bug message, and puts the error
  message and a backtrace into the message automatically.
  A numeric argument says how many stack frames to put in the backtrace.
~c switches to the window-based debugger.
" #/c-E #/c-M #/c-m-W))

(defun com-help-describe-command (sg error-object &aux char)
  "Prompts for a character and describes what the current meaning of that keystoke
is as a command to the error-handler."
  (format t "~&Describe Command. Type command character: ")
  (let ((reading-command t))			;let abort, etc through
    (setq char (send *standard-input* :tyi)))
  (let* ((command (command-lookup char))
	 (resume-handlers (symeval-in-stack-group 'condition-resume-handlers sg))
	 (proceed-types (send error-object :user-proceed-types
			      (sg-condition-proceed-types sg error-object)))
	 (keywords (append proceed-types *special-commands*))
	 tem)
    (format t "~:C~&~C: " char char)
    (cond ((setq tem (rassq char *proceed-type-special-keys*))
	   (send error-object :document-proceed-type (car tem)
		 *standard-output* resume-handlers))
	  ((setq tem (rassq char *special-command-special-keys*))
	   (send error-object :document-special-command (car tem)
		 *standard-output* resume-handlers))
	  ((null command)
	   (if (zerop (char-bits char))
	       (format t "is not a special debugger command.
  Typing this will enter a read-eval-print loop,
using ~A in base ~D, package ~A, with which
you can examine information in the environment of the stack frame you are examining."
		       *readtable* *read-base* *package*)
	     (format t "is not currently a defined debugger command.")))
	  ((eq command 'com-proceed-specified-type)
	   (if (not (< -1 (- char (char-int #/s-A)) (length keywords)))
	       (format t "is not currently a defined debugger command.")
	     (send error-object (if (< (- char (char-int #/s-A)) (length proceed-types))
				    :document-proceed-type
				    :document-special-command)
		   (nth (- char (char-int #/s-A)) keywords)
		   *standard-output* resume-handlers)))
	  (t (if (documentation command)
		 (format t "~A" (documentation command))
	         (format t "~S is not documented" command))
	     (send *standard-output* :fresh-line)
	     (case command
	       (com-abort
		(let ((abort-handler (find-resume-handler abort-object nil resume-handlers)))
		  (cond ((dolist (x proceed-types)
			   (when (eq (find-resume-handler error-object x resume-handlers)
				     abort-handler)
			     (format t "~&This command is currently synonymous with ~C: "
				     (+ (char-int #/s-A) (position x proceed-types)))
			     (send error-object :document-proceed-type x
				   *standard-output* resume-handlers)
			     (return t))))
			(abort-handler
			 (send abort-object :document-proceed-type (second abort-handler)
			       *standard-output* resume-handlers))
			(t (format t "There is no way to abort from this error.")))))
	       (com-proceed
		(if proceed-types
		    (progn (format t "~&This command is currently synonymous with ~C: "
				   #/s-A)
			   (send error-object :document-proceed-type (car proceed-types)
				 *standard-output* resume-handlers))
		  (format t "There is no way to proceed from this error."))))))))

;;;; Commands for resuming execution.

;; Abort.  If there is a numeric arg, just flush the arg.
(defun com-abort (sg error-object &optional arg)
  "Aborts out of this error if possible."
  (if arg (throw 'quit nil)
    (com-top-level-throw sg error-object)))

;; Control-Z.
(defun com-top-level-throw (sg ignore &optional ignore)
  "Throws to the top level in the current process."
  (leaving-error-handler)
  (error-handler-must-be-running) 
  (cond ((eq sg si::scheduler-stack-group)
	 (format t "~&Restarting the scheduler.")
	 (let ((proc (symeval-in-stack-group 'current-process sg)))
	   (when proc
	     (si::process-blast proc)
	     (format t "~%Blasting ~S so this won't happen again" proc)))
	 (stack-group-preset sg (si::appropriate-process-scheduler))
	 (sg-run-goodbye sg))
	(t
	 (let ((sg-to-abort sg)
	       (sg-innermost-frame innermost-visible-frame))
	   (when (and (neq sg (process-initial-stack-group current-process))
		      (not (memq sg (send current-process :coroutine-stack-groups)))
		      (null (symeval-in-stack-group
			      'condition-resume-handlers sg)))
	     ;; Running in a random stack group, get rid of it then throw in the
	     ;; initial stack group.
	     (unwind-sg sg %current-stack-group nil nil)
	     (setq sg-to-abort (process-initial-stack-group current-process))
	     (setq sg-innermost-frame (sg-ap sg)) )
	   ;; Prevent any trap-on-exits from this throw.
	   (do ((frame sg-innermost-frame (sg-next-active sg-to-abort frame)))
	       ((null frame))
	     (setf (rp-trap-on-exit (sg-regular-pdl sg-to-abort) frame) 0))
	   (sg-abort sg-to-abort))))
  nil)

(defun sg-abort (sg)
  (sg-apply-no-trap sg 'signal-condition (list eh:abort-object) t
		    (not error-handler-running)))

;; Control-T.
(defun com-throw (sg ignore &rest ignore &aux tag val)
  "Throw to a tag which is prompted for."
  (error-handler-must-be-running)
  (format t "Throw a value to a tag.~%")
  (setq tag (read-object :eval-read "Form to evaluate to get the tag: ")
	val (read-object :eval-read "~&Form to evaluate to get the value to throw: "))
  (leaving-error-handler)
  (setf (rp-trap-on-exit (sg-regular-pdl sg) innermost-visible-frame) 0)
  (sg-throw sg tag val)
  nil)

;; Meta-R
(defun com-reinvoke-new-args (sg ignore &rest ignore)
  "Reinvoke the current function with possibly altered arguments."
  (cond ((null error-handler-running)
	 (format t "You can only examine this stack group, not modify it."))
	((not (sg-frame-active-p sg current-frame))
	 (format t "This frame's args are still being computed;
it cannot be reinvoked since it was never invoked."))
	(t
	 (let* ((form (get-frame-function-and-args sg current-frame))
		(function-name (car form))
		(function (rp-function-word (sg-regular-pdl sg) current-frame))
		(argument-list (cdr form))
		(nargs (length argument-list))
		(args-info (args-info function))
		(args-wanted (ldb %%arg-desc-min-args args-info))
		(rest-flag (ldb-test %%arg-desc-any-rest args-info))
		(max-args (ldb %%arg-desc-max-args args-info))
		new-args
		(*print-level* error-message-prinlevel)
		(*print-length* error-message-prinlength))
	   (format t "~&Reinvoke ~S with possibly altered arguments." function-name)
	   (do ((i 0 (1+ i)))
	       ((unless rest-flag (eq i max-args)))
	     (multiple-value-bind (value flag)
		 (prompt-and-read
		   (let ((keyword (if ( i args-wanted) :eval-read-or-end :eval-read)))
		     (if (< i nargs)
			 (list keyword :default (nth i argument-list))
		         keyword))
		   (if (< i nargs)
		       (if ( i args-wanted)
			   "~&Arg ~D~A, or ~\lozenged-character\ not to change it, or ~C: "
			   "~&Arg ~D~A, or ~\lozenged-character\ not to change it: ")
		     (if ( i args-wanted)
			 "~&Arg ~D~A, or ~*~C: "
		         "~&Arg ~D~A: "))
		   i
		   (format:output nil (display-arg-name " (~A)" function i))
		   #/space #/end)
	       (if (eq flag ':end) (return))
	       (if (eq flag ':default)
		   (prin1 value))
	       (setq new-args
		     (nconc new-args
			    (ncons value)))))
	   (setq form (cons function-name new-args))
	   (when (fquery nil "Reinvoking ~S, OK? " form)
	     (setf (rp-trap-on-exit (sg-regular-pdl sg) innermost-visible-frame) 0)
	     (sg-unwind-to-frame-and-reinvoke sg current-frame form)
	     (leaving-error-handler)
	     (without-interrupts
	       (and error-handler-running
		    (free-second-level-error-handler-sg %current-stack-group))
	       (stack-group-resume sg nil)))))))

;; Control-R.
(defun com-return-a-value (sg ignore &rest ignore &aux value
			   (fn (function-name (rp-function-word (sg-regular-pdl sg)
								current-frame))))
  "Specify values to return from the current frame (does not reinvoke the function)"
  (cond ((null error-handler-running)
	 (format t "You can only examine this stack group, not modify it."))
	((not (sg-frame-active-p sg current-frame))
	 (format t "This frame has not yet been activated; you cannot return from it."))
	((null (sg-next-active sg current-frame))
	 (format t "This is the bottom frame; you cannot return from it."))
	(t (multiple-value-bind (nil number-loc-or-nil) (sg-frame-value-list sg current-frame)
	     (cond ((null number-loc-or-nil)
		    (format t "Return a value from the function ~S.~%" fn)
		    (setq value (read-object :eval-read "Form to evaluate and return: "))
		    (leaving-error-handler)
		    (setf (rp-trap-on-exit (sg-regular-pdl sg) innermost-visible-frame) 0)
		    (sg-unwind-to-frame sg current-frame t value))
		   (t
		    (format t "Return values from the function ~S " fn)
		    (if (numberp number-loc-or-nil)
			(format t "(up to ~D of them)." number-loc-or-nil)
		      (format t "(any number of them)."))
		    (let (accum)
		      (do ((i 0 (1+ i)))
			  ((eq i number-loc-or-nil))
			(multiple-value-bind (value flag)
			    (read-object :eval-read-or-end "~&Value ~D~A, or ~C: "
					 i (format:output nil
					     (display-value-name " (~A)" fn i))
					 #/end)
			  (if flag (return))
			  (push value accum)))
		      (sg-unwind-to-frame-and-reinvoke sg current-frame
						       `(values . ,(nreverse accum)))
		      (leaving-error-handler)
		      (without-interrupts
			(and error-handler-running
			     (free-second-level-error-handler-sg %current-stack-group))
			(stack-group-resume sg nil))))))))
  nil)

;; Control-Meta-R
(defun com-return-reinvocation (sg ignore &rest ignore
				&aux form (*print-level* error-message-prinlevel)
					  (*print-length* error-message-prinlength))
  "Retries invoking the current function."
  (cond ((null error-handler-running)
	 (format t "You can only examine this stack group, not modify it."))
	((not (sg-frame-active-p sg current-frame))
	 (format t "This frame's args are still being computed;
their values are not known, to re-evaluate with."))
	((fquery '(:list-choices nil :fresh-line nil)
		 " Re-evaluating ~S, OK? "
		 (setq form (get-frame-function-and-args sg current-frame)))
	 (setf (rp-trap-on-exit (sg-regular-pdl sg) innermost-visible-frame) 0)
	 (sg-unwind-to-frame-and-reinvoke sg current-frame form)
	 (leaving-error-handler)
	 (without-interrupts
	   (and error-handler-running
		(free-second-level-error-handler-sg %current-stack-group))
	   (stack-group-resume sg nil)))))

;; Resume.
(defun com-proceed (error-sg error-object &rest ignore &aux proceed)
  "Proceeds from this error if possible."
  (declare (special error-object))
  (if (not error-handler-running)
      (throw 'exit t))
  (setq proceed (car (or (send error-object :user-proceed-types
			       (sg-condition-proceed-types error-sg error-object))
			 *special-commands*)))
  (if (null proceed)
      (format t "There is no way to proceed from this error.~%")
    (if (consp proceed)
	(format t "You cannot proceed; you can only restart various command loops.~%")
      (send error-object :proceed-asking-user proceed 'proceed-error-sg 'read-object)))
  nil)

;; Handles things like Super-A, and also things like Meta-C.
(defun com-proceed-specified-type (error-sg error-object &rest ignore
				   &aux proceed-types proceed-type)
  "Use a user-specified proceed option for this error."
  (declare (special error-object))
  (error-handler-must-be-running)
  (setq proceed-types (append (send error-object :user-proceed-types
				    (sg-condition-proceed-types error-sg error-object))
			      *special-commands*))
;character lossage
  (cond ((rassq (char-int *command-char*) *proceed-type-special-keys*)
	 (setq proceed-type (car (rassq (char-int *command-char*)
					*proceed-type-special-keys*)))
	 (unless (memq proceed-type proceed-types)
	   (format t "Proceed type ~S is not available." proceed-type)
	   (setq proceed-type nil)))
	((> (length proceed-types) (- (char-int *command-char*) (char-int #/s-A)) -1)
	 (setq proceed-type (nth (- (char-int *command-char*) (char-int #/s-A))
				 proceed-types)))
	(t
	 (format t "There are not ~D different ways to proceed."
		 (- (char-int *command-char*) (char-int #/s-A)))))
  (if proceed-type
      (send error-object :proceed-asking-user proceed-type
	    'proceed-error-sg
	    'read-object))
  nil)

(defun com-special-command (error-sg error-object &rest ignore)
;character lossage
  (let ((special-command-type (car (rassq (char-int *command-char*)
					  *special-command-special-keys*))))
    (send error-object :special-command special-command-type)))

(defun error-handler-must-be-running ()
  (unless error-handler-running
    (format t "The process didn't get an error; this command may not be used.~%")
    (throw 'quit nil)))

;;;; Initialization
(defvar command-dispatch-table :unbound
  "16. x 256. array that holds debugger command definitions.
First index is the bucky bits of the character, second index is the character code.")

(defun assure-dispatch-set-up ()
  (when (not (boundp 'command-dispatch-table))
    (setq command-dispatch-table (make-array (list char-bits-limit char-code-limit)))
    (dolist (x command-dispatch-list)
      (let ((char (car x))
	    (com (cadr x))
	    (repeat (caddr x)))
	(let ((i (char-bits char)) (j (char-code char)))
	  (dotimes (n (or repeat 1))
	    (setf (aref command-dispatch-table i j) com)
	    (incf j)))))))

;; Make sure COMMAND-DISPATCH-TABLE is recomputed
;; from the new value of COMMAND-DISPATCH-LIST if this file is reloaded.
(makunbound 'command-dispatch-table)

;; The initial dispatch table.
(defconst command-dispatch-list
	  '((#/? com-help)
	    (#/help com-help)
	    (#/line com-down-stack)
	    (#/form com-clear-and-show)
	    (#/return com-up-stack)
	    (#/resume com-proceed)
	    (#/abort com-abort)
	    (#/rubout com-rubout)
	    
	    (#/c-- com-number)
	    (#/c-0 com-number 10.)		;control-digits
	    (#/c-A com-arglist)
	    (#/c-B com-short-backtrace)
	    (#/c-C com-proceed)
	    (#/c-D com-proceed-trap-on-call)
	    (#/c-E com-edit-frame-function)
	    (#/c-I com-set-macro-single-step)
	    (#/c-L com-clear-and-show)
	    (#/c-M com-bug-report)
	    (#/c-N com-down-stack)
	    (#/c-P com-up-stack)
	    (#/c-R com-return-a-value)
	    (#/c-S com-search)
	    (#/c-T com-throw)
	    (#/c-X com-toggle-frame-trap-on-exit)
	    (#/c-Z com-top-level-throw)
	    
	    (#/m-- com-number)
	    (#/m-0 com-number 10.)		;meta-digits
	    (#/m-< com-top-stack)
	    (#/m-> com-bottom-stack)
	    (#/m-B full-backtrace)
	    (#/m-D com-toggle-trap-on-call)
;>>
	    (#/m-I com-print-instance-variable)
	    (#/m-L com-clear-and-show-all)
	    (#/m-N com-down-stack-all)
	    (#/m-P com-up-stack-all)
	    (#/m-R com-reinvoke-new-args)
	    (#/m-S com-print-variable-frame-value)
	    (#/m-T com-show-stack-temporaries)
	    (#/m-X com-set-all-frames-trap-on-exit)
	    
	    (#/c-m-- com-number)
	    (#/c-m-0 com-number 10.)		;control-meta-digits
	    (#/c-m-A com-get-arg)
	    (#/c-m-B full-backtrace-uninteresting)
;>>
	    (#/c-m-C com-print-open-catch-frames)
;>>
	    (#/c-m-D com-describe-*)
;>>
	    (#/c-m-E com-describe-lexical-environment)
	    (#/c-m-F com-get-function)
	    (#/c-m-H com-print-frame-handlers)
	    (#/c-m-L com-get-local)
	    (#/c-m-N com-down-stack-uninteresting)
	    (#/c-m-P com-up-stack-uninteresting)
	    (#/c-m-Q com-describe-proceed-types)
	    (#/c-m-R com-return-reinvocation)
	    (#/c-m-S com-print-frame-bindings)
	    (#/c-m-T com-get-stack-temporary)
	    (#/c-m-U com-up-to-interesting)
	    (#/c-m-V com-get-value)
	    (#/c-m-W com-window-error-handler)
	    (#/c-m-X com-clear-all-frames-trap-on-exit)
	    
;>>
	    (#/c-sh-s com-set-breakpoint)
;>>
	    (#/c-sh-c com-clear-breakpoint)
;>>
	    (#/m-sh-c com-clear-all-breakpoints)
;>>
	    (#/c-sh-l com-list-breakpoints)
;>>
	    (#/m-sh-s com-macro-single-step)

	    (#/s-A com-proceed-specified-type 26.)

	    (#/c-quote com-eval-in-error-handler)
	    (#/c-m-delta com-describe-alot)

	    )
  "List of elements (character command-symbol) from which COMMAND-DISPATCH-TABLE is initialized.")

;;; BREAKON moved to EHBPT
;;; setting/clearing/toggling trap on thisframe/allframes exit/call commands moved to EHBPT

;;;; for debugging the debugger
;; by pace.

(defun com-eval-in-error-handler (&rest ignore)
  "Perform an evaluation in the context of the error handler, rather than withing the
erring stack-group's context.
You don't need to use this unless you're debugging the debugger."
  (multiple-value-bind (sexp flag)
      (with-input-editing (*standard-input*  '((:full-rubout :full-rubout)
					       (:activation = #/end)
					       (:prompt " Eval in EH stack group: ")))
	(si:read-for-top-level))
    (unless (eq flag ':full-rubout)
      (setq +++ ++ ++ + + -)
      (let ((values (multiple-value-list (si:eval-special-ok (setq - sexp)))))
	(push values *values*)
	(setq ////// //// //// // // values)
	(setq *** ** ** * * (car values))
	(setq // values * (car //))
	(dolist (value //)
	  (terpri)
	  (print-carefully () (funcall (or prin1 #'prin1) value)))))))

(defun com-describe-alot (sg ignore &optional ignore)
  "Print masses of crud only of interest to people who are breaking
/(ooops! /"maintaining/", that is) the system"
  (let ((rp (sg-regular-pdl sg))
	(ap current-frame))
    (cond ((not (typep (rp-function-word rp ap) 'compiled-function))
	   (format t "current frame is not for a compiled function")
	   (return-from com-describe-alot nil)))

    (format t "~&")

;;;---!!! SYS:SYS;SGDEFS introduced RP-ATTENTION at some point (renamed from
;;;---!!!   RP-DOWNWARD-CLOSURE-PUSHED?).
;;;---!!!    (format t "~[~;ATTENTION ~]" (rp-attention rp ap))
    (format t "~[~;SELF-MAP ~]" (ldb %%lp-cls-self-map-provided (rp-call-word rp ap)))
    (format t "~[~;TRAP-ON-EXIT ~]" (rp-trap-on-exit rp ap))
    (format t "~[~;ADI-PRESENT ~]" (rp-adi-present rp ap))
    (format t "~[D-IGNORE~;D-PDL~;D-RETURN~;D-LAST~:;D-MICRO-RETURN~:*~s~] "
	    (rp-destination rp ap))
    (format t "Delta to open ~s Delta to active ~s "
	    (rp-delta-to-open-block rp ap)
	    (rp-delta-to-active-block rp ap))
    (fresh-line)
    (format t "~[~;MICRO-STACK-SAVED ~]" (rp-micro-stack-saved rp ap))
    (format t "~[~;BINDING-BLOCK-PUSHED ~]" (rp-binding-block-pushed rp ap))
    (format t "EXIT-PC ~s " (rp-exit-pc rp ap))
    (fresh-line)
    (format t "~[~;EXPLICIT-REST-ARG ~]" (ldb %%lp-ens-lctyp (rp-entry-word rp ap)))
    (format t "~[~;UNSAFE-REST-ARG ~]" (ldb %%lp-ens-unsafe-rest-arg (rp-entry-word rp ap)))
    (format t "~[~;ENVIRONMENT-POINTER-POINTS-HERE ~]"
	    (ldb %%lp-ens-environment-pointer-points-here (rp-entry-word rp ap)))
    (format t "~[~;UNSAFE-REST-ARG-1 ~]"
	    (ldb %%lp-ens-unsafe-rest-arg-1 (rp-entry-word rp ap)))
    (format t "~&args supplied ~o " (rp-number-args-supplied rp ap))
    (format t "~&local block origin ~o " (rp-local-block-origin rp ap))
    (format t "~&Function: ~o" (rp-function-word rp current-frame))

    (let ((lex-env (car (sg-eval-in-frame sg 'si:lexical-environment ap t))))
      (if (null lex-env)
	  (format t "~&Null lexical environment")
	(format t "~&Lexical environment: ~s" lex-env)
	(when lex-env
	  (do ((env-list lex-env (cdr env-list)))
	      ((null env-list))
	    (format t "~&Next step:  ")
	    (do ((env env-list (%p-pointer env)))
		(( (%p-data-type env) dtp-external-value-cell-pointer)
		 (format t "~&    #<~S ~S ~O ~S>"
			 (nth (%p-cdr-code env) q-cdr-codes)
			 (nth (%p-data-type env) q-data-types)
			 (%p-pointer env)
			 (%p-contents-offset env 0))
		 (cond ((= (%area-number (%p-pointer env)) linear-pdl-area)
			(let ((index (virtual-address-to-pdl-index sg (%p-pointer env)))
			      frame)
			  (if (not (null index))
			      (setq frame (sg-frame-for-pdl-index sg index)))
			  (cond ((null frame)
				 (format t " Can't find frame"))
				(t
				 (format t "~& Closure in frame with function ~s"
					 (rp-function-word rp frame))))))))
	      (format t "#<EVCP ~O> -> " (%p-pointer env)))))))))

