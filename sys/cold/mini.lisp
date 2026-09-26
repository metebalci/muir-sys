;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Cold-Load:T; Base:8; Readtable:ZL -*-

;;; Miniature file reader.  Only good for reading ascii and binary files.
;;; quux (contract q9): it reads through quux's file device, where it read
;;; over the chaosnet before, so a cold load needs no file server on a
;;; network and no server's address is compiled into it.  It knows the
;;; device's registers and entries non-symbolically, since SYS: IO; FDEV,
;;; which names them, is loaded after it.  The magic numbers are the words
;;; #o1100-#o1377 (see MINI-COMMAND-RING below).

(DEFVAR MINI-FILE-ID)
(DEFVAR MINI-CH-IDX)
(DEFVAR MINI-UNRCHF)
(DEFVAR MINI-EOF-SEEN)
(DEFVAR MINI-PLIST-RECEIVER-POINTER)
(defvar mini-ring)			;art-16b over both rings, 16. halfwords an entry
(defvar mini-buffer-string)		;the buffer as characters
(defvar mini-buffer-8)			;the buffer as bytes, for the translation
(defvar mini-buffer-16)			;the buffer as 16-bit words, as a qfasl is read
(defvar mini-device-ready nil)		;t once mini-init has given the device its rings
(defvar mini-index 0)			;commands sent since mini-init, mod 2^16
(defvar mini-slot)			;the last response's first halfword in mini-ring
(defvar mini-handle nil)		;the open file's handle, or nil
(defvar mini-file-name)			;its name
(defvar mini-binary-p)			;t if it is read as 16-bit words
(defvar mini-length)			;its length in bytes, from its open
(defvar mini-offset)			;where in it the next read starts
(defvar mini-count 0)			;bytes of it in the buffer

;This is the filename (a string) on which MINI-FASLOAD was called.
(DEFVAR MINI-FASLOAD-FILENAME)

;;; the file device (muir's docs/quux.md, "The file device").  MINI keeps its
;;; rings and its one buffer in the unused words of scratch-pad-init-area past
;;; its free pointer (#o1032), which is wired and straight-mapped, so their
;;; virtual addresses are the physical ones the device takes:
;;;   #o1100-#o1117  the command ring, 2 entries of 8 words
;;;   #o1120-#o1137  the response ring, 2 entries of 8 words
;;;   #o1200-#o1377  the buffer, 512. bytes: a file's name, a log line, or data
;;; one command is out at a time, so the one buffer serves as both A and B.
;;; the registers are words of the register page, feature-page-xbus-address
;;; (#o377000) plus the word; each constant names the constant of SYS: IO;
;;; FDEV that must agree with it.
(defconst mini-feature-devices #o377015)	;feature word 15: <1>, si:%%file-device-feature
(defconst mini-device-control #o377160)		;si:%file-device-control-register
(defconst mini-device-status #o377161)		;si:%file-device-status-register
(defconst mini-command-base #o377162)		;si:%file-device-command-base-register
(defconst mini-command-size #o377163)		;si:%file-device-command-size-register
(defconst mini-command-producer #o377164)	;si:%file-device-command-producer-register
(defconst mini-response-base #o377166)		;si:%file-device-response-base-register
(defconst mini-response-size #o377167)		;si:%file-device-response-size-register
(defconst mini-response-producer #o377170)	;si:%file-device-response-producer-register
(defconst mini-response-consumer #o377171)	;si:%file-device-response-consumer-register
(defconst mini-command-ring #o1100)
(defconst mini-response-ring #o1120)
(defconst mini-buffer #o1200)
(defconst mini-buffer-bytes 512.)
;;; opcodes, as si:%file-device-op-open, -read, -close and -log; an entry's
;;; words as si:%file-device-command-... and -response-...
(defconst mini-op-open 1)
(defconst mini-op-read 2)
(defconst mini-op-close 4)
(defconst mini-op-log 10.)
;;; polls of a register before MINI gives up on the device; muir answers a
;;; command within some hundreds.
(defconst mini-polls 1000000.)

;;; give the device MINI's rings.  disable is the device's reset: it drops
;;; what is queued and closes every handle; the full driver's reset (SYS: IO;
;;; FDEV) starts the same way, so it can take the device over from here.
(defun mini-init ()
  (or (logtest 2 (%xbus-read mini-feature-devices))
      (mini-barf "This machine has no file device"))
  (setq mini-ring (make-array 64. ':type 'art-16b ':displaced-to mini-command-ring)
	mini-buffer-string (make-string mini-buffer-bytes ':displaced-to mini-buffer)
	mini-buffer-8 (make-array mini-buffer-bytes ':type 'art-8b ':displaced-to mini-buffer)
	mini-buffer-16 (make-array (floor mini-buffer-bytes 2) ':type 'art-16b
				   ':displaced-to mini-buffer))
  (setq mini-device-ready nil mini-handle nil)
  (%xbus-write mini-device-control 0)			;disable
  (do ((n mini-polls (1- n)))				;quiet: at once on muir
      ((logtest 2 (%xbus-read mini-device-status)))
    (and (zerop n) (mini-barf "The file device is not quiet")))
  (%xbus-write mini-command-base mini-command-ring)
  (%xbus-write mini-command-size 1)			;log2 of 2 entries
  (%xbus-write mini-response-base mini-response-ring)
  (%xbus-write mini-response-size 1)
  (%xbus-write mini-device-control 1)			;enable, its interrupt off
  (let ((status (%xbus-read mini-device-status)))	;<0> enabled, <2> refused
    (or (and (logtest 1 status) (not (logtest 4 status)))
	(mini-barf "The file device refused MINI's rings, status" status)))
  (setq mini-index 0 mini-count 0 mini-device-ready t))

;;; set the device up for MINI unless it is already: a boot disables it,
;;; and the full driver's reset gives it other rings.
(defun mini-device ()
  (or (and mini-device-ready
	   (logtest 1 (%xbus-read mini-device-status))
	   (= (%xbus-read mini-command-base) mini-command-ring)
	   (= (%xbus-read mini-response-base) mini-response-ring))
      (mini-init)))

;;; one command, and wait for its response.  A-LENGTH is the length of
;;; buffer A (a name, a log line) and B-LENGTH of buffer B (data read), both
;;; the one buffer.  returns the response's status, 0 when done; the response
;;; stays in its slot for mini-response-word until the command after next.
(defun mini-command (op a-length b-length &optional (handle 0) (offset 0)
		     &aux (c (* 16. (logand mini-index 1)))
			  (next (logand (1+ mini-index) #o177777)))
  (aset mini-index mini-ring c)				;word 0: <15:0> the tag,
  (aset op mini-ring (1+ c))				; <23:16> op, <31:24> flags 0
  (mini-store-word c 1 handle)
  (mini-store-word c 2 mini-buffer)			;A
  (mini-store-word c 3 a-length)
  (mini-store-word c 4 mini-buffer)			;B
  (mini-store-word c 5 b-length)
  (mini-store-word c 6 offset)				;read: where in the file
  (mini-store-word c 7 0)
  (%xbus-write mini-command-producer next)
  (do ((n mini-polls (1- n)))
      ((= (%xbus-read mini-response-producer) next))
    (and (zerop n) (mini-barf "The file device does not answer")))
  (setq mini-slot (+ 32. c))				;responses come in command order
  (or (= (aref mini-ring mini-slot) mini-index)
      (mini-barf "The file device answered another tag" (aref mini-ring mini-slot)))
  (%xbus-write mini-response-consumer next)
  (setq mini-index next)
  (ldb #o0010 (aref mini-ring (1+ mini-slot))))		;<23:16> the status

(defun mini-store-word (c k value)
  (aset (ldb #o0020 value) mini-ring (+ c k k))
  (aset (ldb #o2020 value) mini-ring (+ c k k 1)))

;;; word K of the last response, for values under 2^24.
(defun mini-response-word (k)
  (dpb (aref mini-ring (+ mini-slot k k 1)) #o2020 (aref mini-ring (+ mini-slot k k))))

;;; the file's date as the chaosnet server gave it, "MM/DD/YY HH:MM:SS" in
;;; UTC, from the open's mtime: Unix seconds, in two 16-bit halves.  the days
;;; become a date by the proleptic Gregorian calendar (the days-to-civil
;;; algorithm of H. Hinnant, "chrono-Compatible Low-Level Date Algorithms").
;;; everything stays a fixnum for any mtime before 2038.
(defun mini-date-string (high low &aux days rest (s (make-string 17.)))
  ;; mtime/128 = high*512 + low/128; 86400 = 675*128
  (multiple-value-setq (days rest) (floor (+ (* high 512.) (lsh low -7)) 675.))
  (let* ((seconds (+ (* rest 128.) (logand low 127.)))
	 (z (+ days 719468.))				;days from 0000-03-01
	 (era (floor z 146097.))
	 (doe (- z (* era 146097.)))
	 (yoe (floor (- (+ doe (floor doe 36524.)) (floor doe 1460.) (floor doe 146096.))
		     365.))
	 (doy (- doe (- (+ (* 365. yoe) (floor yoe 4)) (floor yoe 100.))))
	 (mp (floor (+ (* 5 doy) 2) 153.))
	 (month (if (< mp 10.) (+ mp 3) (- mp 9.)))
	 (year (+ yoe (* era 400.) (if (<= month 2) 1 0))))
    (mini-two-digits s 0 month)
    (mini-two-digits s 3 (1+ (- doy (floor (+ (* 153. mp) 2) 5))))
    (mini-two-digits s 6 (mod year 100.))
    (mini-two-digits s 9. (floor seconds 3600.))
    (mini-two-digits s 12. (mod (floor seconds 60.) 60.))
    (mini-two-digits s 15. (mod seconds 60.))
    (aset (int-char #o57) s 2)				;/
    (aset (int-char #o57) s 5)
    (aset (int-char #o40) s 8.)				;space
    (aset (int-char #o72) s 11.)			;:
    (aset (int-char #o72) s 14.)
    s))

(defun mini-two-digits (s i n)
  (aset (int-char (+ (char-int #/0) (floor n 10.))) s i)
  (aset (int-char (+ (char-int #/0) (mod n 10.))) s (1+ i)))

;;; the next buffer's worth of the open file; nil at its end, where the file
;;; is closed.  a read names only the bytes left, since the device charges
;;; the length named.
(defun mini-next-buffer (&aux (n (min mini-buffer-bytes (- mini-length mini-offset))) status)
  (setq mini-ch-idx 0 mini-count 0)
  (when (and mini-handle (plusp n))
    (setq status (mini-command mini-op-read 0 n mini-handle mini-offset))
    (or (zerop status) (mini-barf "File device read failed, status" status))
    (setq mini-count (mini-response-word 1))
    (incf mini-offset mini-count)
    (or mini-binary-p (mini-translate)))
  (cond ((plusp mini-count) t)
	(t (mini-close-file) nil)))

;;; the device moves bytes and never interprets them.  the chaosnet server
;;; (ozd) sent a character file through its character mapping, one byte for
;;; one character, so MINI does the same here, as measured on all 256 bytes
;;; over the chaosnet: ascii backspace, tab, line feed, page, return and
;;; rubout (10, 11, 12, 14, 15, 177) become the machine's #o210, #o211,
;;; newline #o215, #o214, #o212 and #o377, and #o210, #o211, #o212, #o214,
;;; #o215 and #o377 become 10, 11, 12, 14, 15 and 177 (so line feed and
;;; return do not simply swap back).  every other byte is itself.
(defun mini-translate ()
  (dotimes (i mini-count)
    (let ((b (aref mini-buffer-8 i)))
      (aset (case b
	      (#o10 #o210) (#o11 #o211) (#o12 #o215) (#o14 #o214) (#o15 #o212) (#o177 #o377)
	      (#o210 #o10) (#o211 #o11) (#o212 #o12) (#o214 #o14) (#o215 #o15) (#o377 #o177)
	      (t b))
	    mini-buffer-8 i))))

(defun mini-close-file (&aux (handle mini-handle))
  (setq mini-eof-seen t mini-count 0)			;nothing more to read
  (when handle
    (setq mini-handle nil)
    (or (zerop (mini-command mini-op-close 0 0 handle))
	(mini-barf "File device close failed, handle" handle))
    ;; one line a file in muir's log, as the chaosnet server logged MINI's
    ;; reads: the name and the bytes that came through the device.
    (mini-log (string-append "mini: read " mini-file-name " " (mini-decimal mini-offset)))))

;;; a line to muir's log, with the device's LOG command.
(defun mini-log (line)
  (copy-array-contents line mini-buffer-string)		;A, the line
  (mini-command mini-op-log (min (array-active-length line) mini-buffer-bytes) 0))

;;; N in decimal; FORMAT is not loaded this early.
(defun mini-decimal (n &aux (s ""))
  (do () (nil)
    (setq s (string-append (string (int-char (+ (char-int #/0) (mod n 10.)))) s)
	  n (floor n 10.))
    (and (zerop n) (return s))))

;;; Open a file for read
;;; NO-BARF makes a refused open return NIL instead of breaking, so that
;;; the cold load can ask for a file that need not be there (MINI-RUN-SCRIPT).
(defun mini-open-file (filename binary-p &optional no-barf &aux status)
  (mini-device)
  (mini-close-file)					;one file at a time
  (setq mini-ch-idx 0 mini-count 0 mini-offset 0 mini-unrchf nil mini-eof-seen nil
	mini-binary-p binary-p mini-file-name filename)
  (copy-array-contents filename mini-buffer-string)	;A, the name
  (setq status (mini-command mini-op-open (array-active-length filename) 0))
  (cond ((zerop status)					;flags 0: read
	 (setq mini-handle (mini-response-word 2)
	       mini-length (mini-response-word 3))
	 ;; Before pathnames and time parsing is loaded, things are stored as strings.
	 ;; the device's truename is the name asked, as the server's was.
	 (setq mini-file-id (cons (string-append filename)
				  ;Discard zero at front of month, so the format
				  ;matches that produced by PRINT-UNIVERSAL-TIME
				  ;and by QFILE before TIMPAR is loaded.
				  (string-left-trim #/0 (mini-date-string
							  (aref mini-ring (+ mini-slot 9.))
							  (aref mini-ring (+ mini-slot 8.))))))
	 (if binary-p #'mini-binary-stream #'mini-ascii-stream))
	(t (mini-log (string-append "mini: refused " filename " status " (mini-decimal status)))
	   (if no-barf nil
	     (mini-barf "Cannot open" filename "file device status" status)))))

;;; the two OTHERWISE clauses below print the operation with ~S.  They
;;; passed OP to MINI-BARF already, but its format string had no directive for
;;; it, so a cold load stopped at "Unknown stream operation" without naming the
;;; operation, which is the one fact needed to fix such a stop.
;;; Stream which does only 16-bit binary input
(DEFUN MINI-BINARY-STREAM (OP &OPTIONAL ARG1 ARG2)
  (CASE OP
    (:WHICH-OPERATIONS '(:TYI :READ-BYTE))
    ((:TYI :READ-BYTE)
     (COND (MINI-UNRCHF
	    (PROG1 MINI-UNRCHF (SETQ MINI-UNRCHF NIL)))
	   ((< mini-ch-idx (floor mini-count 2))
	    (prog1 (aref mini-buffer-16 mini-ch-idx)
		   (SETQ MINI-CH-IDX (1+ MINI-CH-IDX))))
	   ((mini-next-buffer)				;the next buffer's worth
	    (mini-binary-stream :tyi))
	   ;; EOF, and the file closed.  OP is no longer overwritten with a
	   ;; packet's opcode here, so the :TYI arm below now runs (it never did).
	   (t
	    (cond ((eq op ':tyi)			;And tell caller
		   (and arg1 (error arg1))
		   nil)
		  (arg1 (error "EOF"))
		  (t arg2)))))
    (:UNTYI (SETQ MINI-UNRCHF ARG1))
    (:PATHNAME MINI-FASLOAD-FILENAME)
    (:GENERIC-PATHNAME 'MINI-PLIST-RECEIVER)
    (:INFO MINI-FILE-ID)
    (:close (mini-close-file))
    ;; answer :SEND-IF-HANDLES instead of barfing.  It means "send this
    ;; message only if you handle it", so a stream that signals on it turns a
    ;; caller's optional message into a fatal error.  A flavor instance answers
    ;; it through VANILLA-FLAVOR; these streams are closures and must answer for
    ;; themselves.  A cold load stopped here on (:SEND-IF-HANDLES :BYTE-SIZE),
    ;; which IO; STREAM:64 asks of any stream.
    (:SEND-IF-HANDLES
     (AND (MEMQ ARG1 '(:TYI :READ-BYTE :UNTYI :PATHNAME :GENERIC-PATHNAME
		       :INFO :CLOSE :WHICH-OPERATIONS))
	  (MINI-BINARY-STREAM ARG1 ARG2)))
    (OTHERWISE (MINI-BARF "Unknown stream operation ~S" OP))))

;;; stream which does only character input
(DEFUN MINI-ASCII-STREAM (OP &OPTIONAL ARG1 ARG2)
  (CASE OP
    (:WHICH-OPERATIONS '(:TYI :UNTYI :READ-CHAR :UNREAD-CHAR))
    ((:TYI :READ-CHAR)
     (LET ((TEM (COND (MINI-UNRCHF
		       (PROG1 MINI-UNRCHF (SETQ MINI-UNRCHF NIL)))
		      ((< mini-ch-idx mini-count)
		       (prog1 (aref mini-buffer-string mini-ch-idx)
			      (INCF MINI-CH-IDX)))
		      ((mini-next-buffer)		;the next buffer's worth
		       (mini-ascii-stream :tyi))
		      (t				;EOF: see the binary stream
		       (cond ((eq op ':tyi)		;and tell caller
			      (and arg1 (error arg1))
			      nil)
			     (arg1 (error "EOF"))
			     (t (return-from mini-ascii-stream arg2)))))))
       (IF (AND (EQ OP ':READ-CHAR) (FIXNUMP TEM))
	   (INT-CHAR TEM)
	   TEM)))
    ((:UNTYI :UNREAD-CHAR) (SETQ MINI-UNRCHF ARG1))
    (:PATHNAME MINI-FASLOAD-FILENAME)
    (:GENERIC-PATHNAME 'MINI-PLIST-RECEIVER)
    (:INFO MINI-FILE-ID)
    (:close (mini-close-file))
    ;; see the note on the binary stream above.
    (:SEND-IF-HANDLES
     (AND (MEMQ ARG1 '(:TYI :READ-CHAR :UNTYI :UNREAD-CHAR :PATHNAME
		       :GENERIC-PATHNAME :INFO :CLOSE :WHICH-OPERATIONS))
	  (MINI-ASCII-STREAM ARG1 ARG2)))
    (OTHERWISE (MINI-BARF "Unknown stream operation ~S" OP))))

;;; a failure leaves the device to be set up afresh on the next use, and the
;;; disable that does so closes any file still open.
(defun mini-barf (&rest args)
  (setq mini-device-ready nil mini-handle nil)
  ;; If inside the cold load, this will be FERROR-COLD-LOAD, else make debugging easier
  (APPLY #'FERROR 'MINI-BARF ARGS))

;;;; Higher-level stuff

;;; Load a file alist as setup by the cold load generator
(DEFUN MINI-LOAD-FILE-ALIST (ALIST)
  (LOOP FOR (FILE PACK QFASLP) IN ALIST
	DO (PRINT FILE)
	DO (FUNCALL (IF QFASLP #'MINI-FASLOAD #'MINI-READFILE) FILE PACK)))

;; initialized by the cold-load builder
(DEFVAR *COLD-LOADED-FILE-PROPERTY-LISTS*)

(DEFUN MINI-FASLOAD (MINI-FASLOAD-FILENAME PKG
		     &AUX FASL-STREAM TEM)
  ;; Set it up so that file properties get remembered for when there are pathnames
  (OR (SETQ TEM (ASSOC-EQUAL MINI-FASLOAD-FILENAME *COLD-LOADED-FILE-PROPERTY-LISTS*))
      (PUSH (SETQ TEM (NCONS MINI-FASLOAD-FILENAME)) *COLD-LOADED-FILE-PROPERTY-LISTS*))
  (SETQ MINI-PLIST-RECEIVER-POINTER TEM)
  ;;Open the input stream in binary mode, and load from it.
  (SETQ FASL-STREAM (MINI-OPEN-FILE MINI-FASLOAD-FILENAME T))
  (FASLOAD-INTERNAL FASL-STREAM PKG T)
  ;; FASLOAD Doesn't really read to EOF, must read rest to avoid getting out of phase
  (MINI-CLOSE FASL-STREAM)
  MINI-FASLOAD-FILENAME)

;;; FASLOAD does not read to EOF; closing the file is enough now, as the
;;; device reads by offset and nothing is in flight.
(defun mini-close (stream)
  (funcall stream :close))

;; This kludge simulates the behavior of PROPERTY-LIST-MIXIN.
;; It is used instead of the generic-pathname in fasloading and readfiling;
;; it handles the same messages that generic-pathnames are typically sent.
(DEFUN MINI-PLIST-RECEIVER (OP &REST ARGS)
  (CASE OP
    (:GET (GET MINI-PLIST-RECEIVER-POINTER (CAR ARGS)))
    (:GETL (GETL MINI-PLIST-RECEIVER-POINTER (CAR ARGS)))
    (:PUTPROP (PUTPROP MINI-PLIST-RECEIVER-POINTER (CAR ARGS) (CADR ARGS)))
    (:REMPROP (REMPROP MINI-PLIST-RECEIVER-POINTER (CAR ARGS)))
    (:PROPERTY-LIST (CONTENTS MINI-PLIST-RECEIVER-POINTER))
    (:SET (CASE (CAR ARGS)
	    (:PROPERTY-LIST (SETF (CONTENTS MINI-PLIST-RECEIVER-POINTER) (CAR (LAST ARGS))))
	    (:GET (SETF (GET MINI-PLIST-RECEIVER-POINTER (CADR ARGS)) (CAR (LAST ARGS))))
	    (T (PRINT "Bad :SET to MINI-PLIST-RECEIVED") (PRINT (CAR ARGS)) (%HALT))))
    (:PUSH-PROPERTY (PUSH (CAR ARGS) (GET MINI-PLIST-RECEIVER-POINTER (CADR ARGS))))
    (T (PRINT "Bad op to MINI-PLIST-RECEIVER ") (PRINT OP) (%HALT))))

(DEFUN MINI-READFILE (FILE-NAME PKG &AUX (FDEFINE-FILE-PATHNAME FILE-NAME) TEM)
  (LET ((EOF '(()))
	(*STANDARD-INPUT* (MINI-OPEN-FILE FILE-NAME NIL))
	(*PACKAGE* (PKG-FIND-PACKAGE PKG)))
    (DO ((FORM (CLI:READ *STANDARD-INPUT* NIL EOF) (CLI:READ *STANDARD-INPUT* NIL EOF)))
	((EQ FORM EOF))
      (EVAL FORM))
    (OR (SETQ TEM (ASSOC-EQUAL FILE-NAME *COLD-LOADED-FILE-PROPERTY-LISTS*))
	(PUSH (SETQ TEM (NCONS FILE-NAME)) *COLD-LOADED-FILE-PROPERTY-LISTS*))
    (LET ((MINI-PLIST-RECEIVER-POINTER TEM))
      (SET-FILE-LOADED-ID 'MINI-PLIST-RECEIVER MINI-FILE-ID PACKAGE))))

;;; a cold load runs unattended.  It asks the file device for
;;; SYS: SITE; COLDRUN LISP; if there is no such file the open is refused
;;; and the cold load goes to its console listener exactly as before.  If it
;;; has one, its forms are read and evaluated here, which is how a build types
;;; (SI:QLD) and (SI:DISK-SAVE ...) without a screen.
;;;
;;; Progress is reported with MINI-REPORT, the device's LOG command, which
;;; muir writes to its log.  So the log says how far the script got, and the
;;; console still shows anything that goes wrong, since the cold load has no
;;; error handler to catch it.


;;; COLDRUN is generated site policy, not system source.  MINI has no
;;; logical pathname translator, so resolve its site pathname while
;;; compiling, so the cold load sends the device a physical pathname rather
;;; than SYS: SITE; ... .
(DEFMACRO DEFINE-MINI-SCRIPT-FILE-NAME ()
  ;; DEFVAR quotes its initializer in this system.  Expand the whole
  ;; definition here so the cold load receives a string, not a macro call.
  `(DEFVAR MINI-SCRIPT-FILE-NAME
     ,(SEND (SEND (FS:PARSE-PATHNAME "SYS: SITE; COLDRUN LISP")
                  :TRANSLATED-PATHNAME)
            :STRING-FOR-MINI)))

(DEFINE-MINI-SCRIPT-FILE-NAME)
(DEFVAR MINI-SCRIPT-RUNNING-P NIL)

;;; send one line to muir's log with the device's LOG command, which muir
;;; writes to its standard error as "log: " and the line.  the line is
;;; "report: " and the message, so a build watching muir's log matches
;;; "report: script-ends" and "report: qld-complete" as it matched them in
;;; the chaosnet server's log before.  once QLD is done and SYS: IO; FDEV is
;;; loaded, the device is the driver's, and its FILE-DEVICE-LOG sends the
;;; line; until then the device keeps MINI's rings.
(defun mini-report (message &aux (line (string-append "report: " message)))
  (cond ((and (boundp 'qld-mini-done) qld-mini-done (fboundp 'file-device-log))
	 (funcall 'file-device-log line))		;not defined when this is compiled
	(t (mini-device)
	   (mini-log line)))
  t)

;;; MINI has one stream and one packet buffer.  Read through EOF before
;;; reporting or evaluating: either operation may reuse that buffer, and QLD
;;; opens other files and eventually replaces the network and input streams.
;;; QLD also calls LISP-REINITIALIZE; the binding prevents a recursive script.
(DEFUN MINI-RUN-SCRIPT (&AUX STREAM (N 0) FORMS)
  (UNLESS MINI-SCRIPT-RUNNING-P
    (LET ((MINI-SCRIPT-RUNNING-P T)
          (*PACKAGE* (PKG-FIND-PACKAGE "SYSTEM-INTERNALS")))
      (WHEN (SETQ STREAM (MINI-OPEN-FILE MINI-SCRIPT-FILE-NAME NIL T))
        (LET ((EOF '(())))
          (DO ((FORM (CLI:READ STREAM NIL EOF) (CLI:READ STREAM NIL EOF)))
              ((EQ FORM EOF))
            (PUSH FORM FORMS)))
        (MINI-REPORT "script-begins")
        (DOLIST (FORM (NREVERSE FORMS))
          (SETQ N (1+ N))
          ;; FORMAT is not loaded this early, so the number is a digit.
          (MINI-REPORT (STRING-APPEND "form-"
                           (IF (< N 10.)
                               (STRING (INT-CHAR (+ (CHAR-INT #/0) N)))
                             "more")))
          (EVAL FORM))
        (MINI-REPORT "script-ends")
        T))))

(defun mini-boot ()
  (setq mini-device-ready nil mini-handle nil))		;a boot disables the device

(ADD-INITIALIZATION "MINI" '(MINI-BOOT) '(WARM FIRST))
