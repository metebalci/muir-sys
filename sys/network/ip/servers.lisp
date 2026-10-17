;;; -*- Mode:LISP; Package:INTERNET; Base:10; Readtable:ZL -*-
;;;
;;; This is SYS: NETWORK; IP; SERVERS
;;;
;;; quux revision 16: TCP's streams, the server dispatch, the TELNET server and
;;; the test echo service over TCP (QUUX's Ethernet contract, section 7), the
;;; band's own host (section 5.6), and the functions the segment scripts'
;;; control session calls (section 9, T1, the way in).  TCP itself is in SYS:
;;; NETWORK; IP; TCP.
;;;
;;; the streams are composed as chaos's are (chuse.lisp): a basic stream on the
;;; connection, an input mixin whose :next-input-buffer copies what has arrived
;;; and whose :discard-input-buffer takes it off the receive buffer, opening the
;;; window, and an output mixin whose buffers go into the send buffer, with
;;; :force-output pushing; the system's ascii translation mixins over
;;; si:buffered-tyi-tyo-stream make CR LF a Return, as chaos's
;;; ascii-translating-character-stream does.

;;;; Streams

(defflavor tcp-basic-stream ((connection nil)) ()
  (:included-flavors si:stream)
  (:initable-instance-variables connection)
  (:gettable-instance-variables connection))

(defmethod (tcp-basic-stream :foreign-host) ()
  (and connection (tcp-foreign-host connection)))

(defmethod (tcp-basic-stream :foreign-address) ()
  (and connection (address-string (tcb-remote connection))))

(defmethod (tcp-basic-stream :close) (&optional abort-p)
  ;; :close sends FIN, or RST with abort; after the application's first
  ;; close, a later one sends nothing (tcp-close).
  (when connection
    (tcp-close connection abort-p)))

(defmethod (tcp-basic-stream :eof) ()
  (send self :force-output)
  (tcp-close connection))

(defmethod (tcp-basic-stream :finish) ()
  (tcp-finish connection))

(defflavor tcp-input-mixin ((input-buffer nil) (input-taken 0)) ()
  (:included-flavors tcp-basic-stream si:basic-buffered-input-stream))

(defmethod (tcp-input-mixin :next-input-buffer) (&optional no-hang-p)
  (let ((c connection))
    (unless (or no-hang-p (tcp-readable-p c))
      (process-wait "TCP Input" #'tcp-readable-p c))
    (cond ((plusp (tcb-receive-count c))
	   (or input-buffer
	       (setq input-buffer (make-array %tcp-buffer :type (send self :input-buffer-type))))
	   (setq input-taken (tcp-peek-into c input-buffer 0 %tcp-buffer))
	   (values input-buffer 0 input-taken))
	  (t
	   ;; nothing waiting: EOF after the peer's FIN or the band's own end,
	   ;; else the error that ended the connection.
	   (tcp-signal-if-ended c)
	   nil))))

(defmethod (tcp-input-mixin :discard-input-buffer) (ignore)
  (when (plusp input-taken)
    (tcp-consume connection (prog1 input-taken (setq input-taken 0)))))

(defflavor tcp-output-mixin ((output-buffer nil)) ()
  (:included-flavors tcp-basic-stream si:basic-buffered-output-stream))

(defmethod (tcp-output-mixin :new-output-buffer) ()
  (or output-buffer
      (setq output-buffer (make-array %tcp-mss :type (send self :output-buffer-type))))
  (values output-buffer 0 %tcp-mss))

(defmethod (tcp-output-mixin :send-output-buffer) (buffer end)
  (tcp-signal-if-ended connection)
  (tcp-write connection buffer 0 end))

(defmethod (tcp-output-mixin :discard-output-buffer) (ignore) nil)

(defmethod (tcp-output-mixin :after :force-output) ()
  (tcp-push connection))

(defflavor tcp-character-mixin () ()
  (:included-flavors tcp-input-mixin tcp-output-mixin))
(defmethod (tcp-character-mixin :input-buffer-type) () 'art-string)
(defmethod (tcp-character-mixin :output-buffer-type) () 'art-string)
(defmethod (tcp-character-mixin :element-type) () 'string-char)
;; the EVAL server's need on chaos, and the listener's: a beep goes nowhere.
(defmethod (tcp-character-mixin :beep) (&optional ignore) nil)

(defflavor tcp-binary-mixin () ()
  (:included-flavors tcp-input-mixin tcp-output-mixin))
(defmethod (tcp-binary-mixin :input-buffer-type) () 'art-8b)
(defmethod (tcp-binary-mixin :output-buffer-type) () 'art-8b)
(defmethod (tcp-binary-mixin :element-type) () '(unsigned-byte 8))

(defflavor tcp-ascii-character-stream ()
	   (si:ascii-translating-input-stream-mixin si:ascii-translating-output-stream-mixin
	    tcp-character-mixin tcp-input-mixin tcp-output-mixin tcp-basic-stream
	    si:buffered-tyi-tyo-stream))

(defflavor tcp-character-stream ()
	   (tcp-character-mixin tcp-input-mixin tcp-output-mixin tcp-basic-stream
	    si:buffered-character-stream))

(defflavor tcp-binary-stream ()
	   (tcp-binary-mixin tcp-input-mixin tcp-output-mixin tcp-basic-stream si:buffered-stream))

(compile-flavor-methods tcp-ascii-character-stream tcp-character-stream tcp-binary-stream)

(defun make-tcp-stream (connection &key (characters t) (ascii-translation nil) (r2 nil))
  "A bidirectional stream on an established TCP connection, as chaos:make-stream makes
one on a chaos connection.  R2, in seconds, is the connection's R2 for data in place of
100 s (MUST-21)."
  (when r2
    (setf (tcb-r2 connection) (* r2 1000000.)))
  (setf (tcb-stream connection)
	(make-instance (cond (ascii-translation 'tcp-ascii-character-stream)
			     (characters 'tcp-character-stream)
			     (t 'tcp-binary-stream))
		       :connection connection)))

;;;; Server dispatch (section 7)

(defun tcp-listen (port name function &optional switch)
  "Open PORT for NAME: each connection to it, once ESTABLISHED, runs FUNCTION on the
connection in a process of its own; while SWITCH, a variable, is NIL the port is closed."
  (setq tcp-listeners (cons (list port name function switch)
			    (del #'(lambda (p l) (= p (car l))) port tcp-listeners))))

(defun tcp-server-start (c)
  "C is ESTABLISHED on a listening port: run its server."
  (let ((l (assoc (tcb-lport c) tcp-listeners)))
    (when l
      (setf (tcb-server-process c)
	    (process-run-function (string-append (second l) " Server") (third l) c)))))

;;;; The TELNET server (section 7)

(defvar telnet-server-last-error nil "The network error that last ended a TELNET session.")

(defun telnet-server-function (c)
  "The TELNET server on connection C: MIT's body (chsaux.lisp, TELNET-SERVER-FUNCTION)
over a TCP stream, the herald, the IAC flush by peeking and the listener over
CHAOS:ECHOING-STREAM, which ends the session cleanly at the client's EOF."
  ;; the stream is bound to STREAM, the special that ECHOING-STREAM reads, only
  ;; through TCP-STREAM: STREAM is GLOBAL's symbol, and an init form STREAM
  ;; under its own special declaration read the special's outer value, a
  ;; chaos stream, so the herald went to chaos.
  (let ((tcp-stream (make-tcp-stream c :ascii-translation t)))
    (let ((chaos::untyi-char nil) (chaos::stream tcp-stream))
      (declare (special chaos::untyi-char chaos::stream))
      (condition-case (err)
	  (progn
	    (print-herald tcp-stream)
	    (format tcp-stream "~&Telnet server here~2%")
	    (send tcp-stream :force-output)
	    (do-forever
	      (if (eq (send tcp-stream :tyipeek) #o377)
		  (progn (send tcp-stream :tyi) (send tcp-stream :tyi) (send tcp-stream :tyi))
		(return)))
	    (si:lisp-top-level1 (closure '(chaos::stream chaos::untyi-char) 'chaos::echoing-stream)))
	(sys:remote-network-error (setq telnet-server-last-error err))))
    ;; an abnormal exit closes with abort, as WITH-OPEN-STREAM does; after a
    ;; close of its own the session's stream sends nothing.
    (send tcp-stream :close :abort)))

;;;; The test echo service (RFC 862; section 7)

(defvar *test-echo-service* nil
  "T opens port 7, the test echo service, for the segment scripts (a test switch, set at
the listener; section 7).  While it is NIL port 7 is a closed port.")

(defvar test-echo-service-condition nil
  "The signal name of the last condition the test echo service's stream signalled.")

(defun test-echo-service-condition ()
  "The name of the condition the test echo service's stream last signalled, or NIL."
  test-echo-service-condition)

(defun test-echo-ready-p (c)
  (or (and (plusp (tcb-receive-count c)) (< (tcb-send-count c) %tcp-buffer))
      (and (zerop (tcb-receive-count c)) (or (tcb-peer-fin c) (eq (tcb-state c) :closed)))))

(defun test-echo-server (c)
  "The test echo service: it reads what has arrived while its writes fit the send
buffer, writes it back, and pushes once it has written all it has read; at EOF it
closes its side, with FIN.  It keeps the last condition its stream signalled."
  (let ((echo-stream (make-tcp-stream c :characters nil
				 :r2 (prog1 *r2-of-next-connection*
					    (setq *r2-of-next-connection* nil))))
	(buffer (make-array %tcp-buffer :type 'art-8b)))
    (condition-case (err)
	(do-forever
	  (unless (test-echo-ready-p c)
	    (process-wait "TCP Echo" #'test-echo-ready-p c))
	  (cond ((plusp (tcb-receive-count c))
		 (let ((n (tcp-peek-into c buffer 0 (- %tcp-buffer (tcb-send-count c)))))
		   (tcp-consume c n)
		   (tcp-write c buffer 0 n)
		   (when (zerop (tcb-receive-count c))
		     (tcp-push c))))
		(t
		 (tcp-signal-if-ended c)
		 (send echo-stream :close)
		 (return nil))))
      (sys:remote-network-error
       ;; the signal's name: the condition's first names are its flavor's.
       (setq test-echo-service-condition
	     (let ((names (send err :condition-names)))
	       (or (car (memq 'sys:connection-lost names))
		   (car (memq 'sys:host-stopped-responding names))
		   (car names))))
       (send echo-stream :close :abort)))))

;;;; The control session's functions (section 9, T1, the way in)

(defun tcp-connection-from-port (port)
  "The connection whose foreign port is PORT, or NIL."
  (dolist (c tcp-connections)
    (when (= (tcb-rport c) port) (return c))))

(defun close-connection-from-port (port)
  "A close by the band of the connection whose foreign port is PORT: the application's
own close, its stream's :CLOSE without abort."
  (let ((c (tcp-connection-from-port port)))
    (when c
      (if (tcb-stream c)
	  (send (tcb-stream c) :close)
	(tcp-close c)))
    port))

(defun urgent-state-of-port (port)
  "Whether urgent data is waiting on the connection whose foreign port is PORT, and how
much: the octets from the next one its server reads up to the urgent pointer, those not
yet received included (section 5.5)."
  (declare (values waiting-p octets))
  (let ((c (tcp-connection-from-port port)))
    (if (or (null c) (null (tcb-rcv-up c)))
	(values nil 0)
      (let ((read (seq+ (tcb-rcv-nxt c) (- (tcb-receive-count c)))))
	(if (seq< read (tcb-rcv-up c))
	    (values t (seq- (tcb-rcv-up c) read))
	  (values nil 0))))))

;;;; The band's own host (section 5.6)

(defun internet-set-local-host ()
  "SI:LOCAL-HOST: the site table's host whose INTERNET address is the band's; failing
that the host of the Chaos address, as the chaos initialization set it; failing both an
unnamed host."
  (let ((host (address-host my-address)))
    (cond (host (setq si:local-host host))
	  ((and (boundp 'si:local-host) si:local-host))
	  (t (setq si:local-host
		   (si:make-unnamed-host :lispm `(:internet (,(address-string my-address)))))))))

(tcp-listen 23. "TELNET" 'telnet-server-function)
(tcp-listen 7 "Test Echo" 'test-echo-server '*test-echo-service*)
(or (memq 'internet-set-local-host network-start-functions)
    (setq network-start-functions (append network-start-functions '(internet-set-local-host))))
