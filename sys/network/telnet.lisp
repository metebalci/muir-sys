;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:8; Readtable:T -*-
;;;
;;; This is SYS: NETWORK; TELNET
;;;
;;; quux revision 16 (QUUX's Ethernet contract, sections 7 and 8, step R3): the
;;; TELNET server's body, independent of the protocol, moved here from the
;;; NCP's services (SYS: NETWORK; CHAOS; CHSAUX: TELNET-SERVER-FUNCTION's body,
;;; ECHOING-STREAM, TELNET-SERVER-EOF and their variables), which left the band.
;;; A protocol's server accepts the connection and gives the body a character
;;; stream on it with ASCII translation (TCP's: SYS: NETWORK; IP; SERVERS,
;;; TELNET-SERVER-FUNCTION).  The code is MIT's but for the package, SI here,
;;; CHAOS there, and the body's own function.

(defun telnet-server-body (telnet-stream)
  "The TELNET server's session on TELNET-STREAM: the herald, /"Telnet server here/", the
client's TELNET negotiations flushed, then the listener over ECHOING-STREAM.  It ends at
the client's end of file (TELNET-SERVER-EOF) or a network error (ECHOING-STREAM), each
of which kills the process."
  ;; the stream is bound to STREAM, the special ECHOING-STREAM reads, as
  ;; chsaux's WITH-OPEN-STREAM bound it; STREAM is GLOBAL's symbol.
  (let ((untyi-char nil) (stream telnet-stream))
    (declare (special untyi-char stream))
    (print-herald stream)
    (format stream "~&Telnet server here~2%")
    (send stream :force-output)
    ;; Flush any number of telnet negotiations.  (We only understand the simplest kind).
    ;; peek at the next byte instead of reading it and sending :UNTYI.  The
    ;; stream reads CR LF as one Return, which :UNTYI cannot push back, so a session
    ;; whose first input was Return died in the error handler.  :TYIPEEK consumes
    ;; nothing, and IAC (#o377) is the same byte translated or not.
    (do-forever
      (if (eq (send stream :tyipeek) #o377)
	  (progn (send stream :tyi) (send stream :tyi) (send stream :tyi))
	(return)))
    (si:lisp-top-level1 (closure '(stream untyi-char) 'echoing-stream))))

(defvar record-stream nil)

(defvar *telnet-output-translation-table* ; for 32 random LM-characters
	#("." "v" "a" "b" "^" "~" "e" "p"
	  "l" "g" "d" "^" "+-" "+" "infty" "d"
	  "<" ">" "^" "v" "A" "E" "x" "<->"
	  "<-" "->" "//=" "$" "<=" "=>" "=" "v"))

(defvar *enable-telnet-output-translation* t)

(defun echoing-stream (op &rest args)
  (declare (special stream untyi-char))
  (condition-case ()
      (case op
	(:tyi
	 (or (prog1 untyi-char (setq untyi-char nil))
	     (let (ch)
	       (send stream :force-output)
	       (setq ch (send stream :tyi))
	       ;; nil is the client's end of file: close and end the session
	       ;; (telnet-server-eof, below), instead of taking nil for a code.
	       (when (null ch) (telnet-server-eof))
	       (if record-stream (send record-stream :tyo ch))
	       (if (> ch #o37) (send stream :tyo ch)
		 (setq ch (set-char-bit (logior #o100 ch) :control 1))
		 (send stream :string-out "c-")
		 (send stream :tyo (char-code ch)))
	       ch)))
	(:untyi (setq untyi-char (car args)))
	(:read-cursorpos (values 0 0))
	(:tyo
	 (let ((c (car args)))
	   (cond ((not *enable-telnet-output-translation*) (send stream :tyo c))
		 ((> c #o37) (send stream :tyo c))
		 (t (send stream :string-out (aref *telnet-output-translation-table* c))))))
	(otherwise (lexpr-send stream op args)))
    (sys:remote-network-error
     (process-run-function "Kill"
			   current-process :kill)
     (process-wait "Die" 'false))))

;; The client's end of file ends the TELNET session cleanly: the server closes
;; its side and its process ends.  ECHOING-STREAM's :TYI reads nil at end of
;; file; it used to compare that nil with #o37 and err, and the debugger,
;; reading from the same stream, erred again one level deeper each time, until
;; the band ran out of regions and halted (an EOF alone, as a TCP half-close
;; gives).  After EOF and CLS the process ended with no close of its own and
;; its connection was left behind.  :CLOSE without abort is the stream's normal
;; close (on Chaos: force out what is buffered, send EOF, wait until the other
;; side has acknowledged everything, then CLS; chuse.lisp, BASIC-OUTPUT-STREAM
;; :BEFORE :CLOSE), so the output of the last form arrives first; an abnormal
;; exit from WITH-OPEN-STREAM would close with abort instead.  The read may be
;; the debugger's, which for a microcode error runs in a stack group of its own
;; (eh/eh.lisp, SECOND-LEVEL-ERROR-HANDLER), so the session is not left by a
;; throw: the process is killed as on a network error in ECHOING-STREAM, and
;; WITH-OPEN-STREAM's abort then finds the stream closed.  This belongs to the
;; server's body, not to Chaos: it uses only the stream and the process.
(defun telnet-server-eof ()
  (declare (special stream))
  (send stream :close)
  (process-run-function "Kill" current-process :kill)
  (process-wait "Die" 'false))
