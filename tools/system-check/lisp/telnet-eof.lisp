;;; -*- Mode:LISP; Package:USER; Base:10; Readtable:ZL -*-
;;; For the check telnet-eof (tools/system-check/README.md): the TELNET server
;;; closes its side when its client sends EOF (sys/network/chaos/chsaux.lisp,
;;; ECHOING-STREAM and TELNET-SERVER-EOF).  The client is this band itself: a
;;; Chaos connection to its own address, which the NCP loops back
;;; (sys/network/chaos/chsncp.lisp, TRANSMIT-INT-PKT), so the check needs no
;;; gateway that can send an EOF alone.  The client receipts every packet at
;;; once with an STS, as a gateway such as ozd does.  Before the change an EOF
;;; alone made the server's listener take NIL for a character and err, and the
;;; debugger, reading the same stream, err again one level deeper each time,
;;; until the band ran out of regions and halted; after EOF and CLS the server
;;; ended without a close of its own and its connection could be left behind.
;;; TE-CLEANUP kills a server left running, so that a failing case does not
;;; take the band down.

(defvar *te-conn* nil "This check's client connection to the band's own TELNET server.")
(defvar *te-index* nil "The client connection's local index, the server connection's foreign one.")
(defvar *te-before* nil "The TELNET Server processes that ran before the connection.")
(defvar *te-server* nil "The TELNET Server process serving the connection.")
(defvar *te-text* "" "The text the server sent, as received.")
(defvar *te-ops* nil "The opcodes, as keywords, of the packets other than data received, in order.")
(defvar *te-eof-time* nil "(TIME) when the client sent its EOF.")
(defvar *te-mark* 0 "The length of *TE-TEXT* when the client sent its EOF.")
(defvar *te-done-time* nil "(TIME) when the text named by TE-POLL's DONE-TEXT arrived.")
(defvar *te-close-time* nil "(TIME) when the server's CLS (or a LOS) arrived.")

(defun te-telnet-servers ()
  (subset #'(lambda (p) (string-equal (send p :name) "TELNET Server")) si:all-processes))

(defun te-new-servers ()
  "The TELNET Server processes that did not run before the connection."
  (subset #'(lambda (p) (not (memq p *te-before*))) (te-telnet-servers)))

(defun te-servers-gone-p ()
  (null (te-new-servers)))

(defun te-all-gone-p ()
  (and (null (te-new-servers)) (null (te-server-connection))))

(defun te-op-name (op)
  (cond ((= op chaos:eof-op) :eof)
	((= op chaos:cls-op) :cls)
	((= op chaos:los-op) :los)
	(t op)))

(defun te-closed-p ()
  (or (memq :cls *te-ops*) (memq :los *te-ops*)))

(defun te-poll (ticks &optional done-text)
  "Read what the server sends for up to TICKS 60ths, ending at its CLS or a LOS.
Every packet is receipted at once.  Notes when DONE-TEXT first shows in the text.
Returns T when the connection was closed."
  (let ((start (time)))
    (do-forever
      (let ((pkt (chaos:get-next-pkt *te-conn* t "TE Poll" nil)))
	(cond (pkt
	       (let ((op (chaos:pkt-opcode pkt)))
		 (if (>= op chaos:dat-op)
		     (setq *te-text* (string-append *te-text* (chaos:pkt-string pkt)))
		   (setq *te-ops* (append *te-ops* (list (te-op-name op))))))
	       (chaos:return-pkt pkt)
	       (when (eq (chaos:state *te-conn*) 'chaos:open-state)
		 (chaos:transmit-sts *te-conn* 'te-receipt)))
	      ((te-closed-p) (setq *te-close-time* (or *te-close-time* (time))) (return t))
	      ((>= (time-difference (time) start) ticks) (return nil))
	      (t (process-sleep 1 "TE Poll"))))
      (when (and done-text (null *te-done-time*)
		 (string-search done-text *te-text* *te-mark*))
	(setq *te-done-time* (time))))))

(defun te-open ()
  "Connect to this band's own TELNET server and read its banner.  T when the banner
came and one new TELNET Server process serves the connection."
  (setq *te-text* "" *te-ops* nil *te-eof-time* nil *te-mark* 0
	*te-done-time* nil *te-close-time* nil)
  (setq *te-before* (te-telnet-servers))
  (setq *te-conn* (chaos:connect chaos:my-address "TELNET"))
  (setq *te-index* (chaos:local-index-num *te-conn*))
  (let ((start (time)))
    (do () ((or (string-search "Telnet server here" *te-text*)
		(te-closed-p)
		(> (time-difference (time) start) (* 60 60))))
      (te-poll 10)))
  (te-poll 60)					;the banner's blank lines
  (let ((new (te-new-servers)))
    (setq *te-server* (car new))
    (and (not (null (string-search "Telnet server here" *te-text*)))
	 (= (length new) 1))))

(defun te-send (text)
  "Send TEXT and a CR LF, as a TELNET client sends a line."
  (let ((pkt (chaos:get-pkt)))
    (chaos:set-pkt-string pkt text (string (code-char 13)) (string (code-char 10)))
    (chaos:send-pkt *te-conn* pkt))
  t)

(defun te-send-eof ()
  (setq *te-mark* (length *te-text*) *te-eof-time* (time))
  (chaos:send-pkt *te-conn* (chaos:get-pkt) chaos:eof-op)
  t)

(defun te-server-connection ()
  "The server's side of the connection, while it is in the connection list."
  (dolist (c chaos:conn-list)
    (when (and (= (chaos:foreign-address c) chaos:my-address)
	       (eql (chaos:foreign-index-num c) *te-index*))
      (return c))))

(defun te-result ()
  "(CLOSED OPCODES ERROR SERVER CONNECTION): :CLOSED when the server's CLS came, else
:OPEN; the opcodes other than data received since the connection opened; :ERROR when
the text since the EOF holds a trap or error message, which start with two greater-than
signs, else :NO-ERROR;
:SERVER-GONE when no new TELNET Server process runs, else :SERVER-RUNS; and the
state of the server's side of the connection if it is still in the connection list,
else NIL."
  (let ((c (te-server-connection)))
    (list (if (memq :cls *te-ops*) :closed :open)
	  *te-ops*
	  (if (string-search ">>" *te-text* *te-mark*) :error :no-error)
	  (if (te-new-servers) :server-runs :server-gone)
	  (and c (chaos:state c)))))

(defun te-eof-and-wait (seconds &optional done-text)
  "Send EOF alone, then read for up to SECONDS or until the server's close; let the
server's process end (up to 5 s more); the result as TE-RESULT gives it."
  (te-send-eof)
  (te-poll (* 60 seconds) done-text)
  (process-wait-with-timeout "TE Server End" (* 60 5) #'te-servers-gone-p)
  (te-result))

(defun te-close-ticks ()
  "The 60ths from the EOF, or from DONE-TEXT's arrival when a form ran, to the
server's close; NIL when it did not close."
  (and *te-close-time* (memq :cls *te-ops*)
       (time-difference *te-close-time* (or *te-done-time* *te-eof-time*))))

(defun te-closed-within (ticks)
  "T when the server closed within TICKS 60ths (TE-CLOSE-TICKS); NIL when later or not."
  (let ((n (te-close-ticks)))
    (and (numberp n) (< n ticks))))

(defun te-text-since-eof ()
  (substring *te-text* *te-mark*))

(defun te-report ()
  "For the record: the opcodes received, the 60ths from the EOF (or from a form's value)
to the close, and the number of characters the server sent after the EOF."
  (list *te-ops* (te-close-ticks) (length (te-text-since-eof))))

(defun te-form-then-eof (form seconds done-text)
  "Send FORM, and EOF right after it while it runs; then as TE-EOF-AND-WAIT, noting
when DONE-TEXT arrives."
  (te-send form)
  (te-poll 30)
  (te-eof-and-wait seconds done-text))

(defun te-eof-then-cls (seconds)
  "Send EOF, wait (up to 5 s) until it is receipted, then CLS, as ozd closes a TELNET
connection whose TCP client has closed; then wait up to SECONDS for the server's
process to end and give (SERVER CONNECTION) as TE-RESULT does."
  (te-send-eof)
  (process-wait-with-timeout "TE EOF Receipt" (* 60 5) #'chaos:conn-finished-p *te-conn*)
  (chaos:close-conn *te-conn* "")
  (process-wait-with-timeout "TE Server End" (* 60 seconds) #'te-all-gone-p)
  (process-sleep 60)
  (cdddr (te-result)))

(defun te-cleanup ()
  "Kill a TELNET Server process this check's connection left running, close the
client's side and remove the server's side if left.  T."
  (dolist (p (te-new-servers)) (send p :kill))
  (when *te-conn*
    (unless (eq (chaos:state *te-conn*) 'chaos:inactive-state)
      (chaos:close-conn *te-conn* "")))
  (let ((c (te-server-connection)))
    (when c (chaos:remove-conn c)))
  (setq *te-conn* nil)
  t)
