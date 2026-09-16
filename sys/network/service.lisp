;;; -*- Mode:Lisp;Package:NETI;Base:8 -*-
;;; Stuff to define and invoke services.
;;;

(DEFVAR *INVOKE-SERVICE-AUTOMATIC-RETRY* ()
  "If T, try all paths to a service if needed")

(DEFUN INVOKE-SERVICE-ON-HOST (SERVICE HOST &REST SERVICE-ARGS)
  "Invoke SERVICE on HOST, returning service-dependent values."
  )

(DEFUN FIND-PATHS-TO-SERVICE (SERVICE)
  "Returns a list of service access paths for the particular service
and only one for a given host, sorted by decreasing desirability"
  )

(DEFUN FIND-PATHS-TO-SERVICE-ON-HOST (SERVICE HOST)
  "Signals an error if none can be found."
  )

(DEFUN FIND-PATH-TO-SERVICE-HOST (SERVICE HOST)
  "Find a path for SERVICE to HOST, or signal an error")

(DEFUN FIND-PATHS-TO-PROTOCOL-ON-HOST (PROTOCOL HOST)
  )

(DEFUN FIND-PATH-TO-PROTOCOL-ON-HOST (PROTOCOL HOST)
  )

(DEFUN INVOKE-SERVICE-ACCESS-PATH (SERVICE-ACCESS-PATH SERVICE-ARGS)
  "Returns service-depedent values"
  )

;;; In NETI:
(DEFUN MOST-DESIRABLE-SERVICE-ACCESS-PATH (SERVICE-ACCESS-PATH-LIST)
  "Chooses randomly from the best subset, where the list is already sorted."
  )

(DEFUN START-SERVICE-ACCESS-PATH-FUTURE (SERVICE-ACCESS-PATH &REST SERVICE-ARGS)
  "Initiates a request for the service.  Returns T if successfull.
Returns () if the service is not implemented or the connection medium
does not support asynchronous connections, and the values normally returned
by the service."
  )

(DEFUN SERVICE-ACCESS-PATH-FUTURE-CONNECTED-P (SERVICE-ACCESS-PATH)
  )

(DEFUN CONTINUE-SERVICE-ACCESS-PATH-FUTURE (SERVICE-ACCESS-PATH)
  "Returns the value for the service, if connected, or signals an error.
SYS:NETWORK-ERROR will include such an error."
  )

(DEFUN ABORT-SERVICE-ACCESS-PATH-FUTURE (SERVICE-ACCESS-PATH)
  )

(DEFMACRO INVOKE-MULTIPLE-SERVICES ((SERVICES TIMEOUT &OPTIONAL WHOSTATE SERVICE-VARIABLE)
				    (HOST &REST SERVICE-RESULTS)
				    &BODY BODY)
  "Useful for contacting all hosts for a service.
SERVICES: A form that returns a list of service-access-paths
TIMEOUT: In 60ths
WHOSTATE: Defaults to /"Service Wait/"
SERVICE-VARIABLE: Bound to the service-access-path describing the service
CLAUSES: As for CONDITION-CASE.  The SERVICE-RESULTS variables are actually the
variables in a CONDITION-CASE, so the first result an error, if it occurs."
  )

;;; Steps -- to define implementations of media
;;; (:NETWORK network-type) Function opens connection over the network
;;;    Succeeds when the local host and the target are on the same network.
;;; (:MEDIUM medium) Function creates the encapsulated connect
;;;    Succeeds if a connection can be formed over that medium.
;;; (:SERVICE service) No functions.
;;;    Succeeds if a connection can be formed to a service providing the service.
;;; (:LOCAL T) Only used by the local medium.

(DEFMACRO DEFINE-MEDIUM (MEDIUM (BUILT-ON-MEDIUM) &BODY BODY)
  "BUILT-ON-MEDIUM is optional.
Each element of body can be either an implementation or a list of the form:
  (IMPLEMENTATION LAMBDA-LIST . BODY),
which provides a function for the step."
  )

(DEFINE-MEDIUM :PUP-DATAGRAM (:DATAGRAM)
  ((:NETWORK :PUP))
  ((:SERVICE :PACKET-GATEWAY) (:NETWORK :PUP)))

(DEFINE-MEDIUM :PUP-BSP (:DATAGRAM)
  ((:NETWORK :PUP))
  ((:SERVICE :PACKET-GATEWAY) (:NETWORK :PUP)))

(DEFINE-MEDIUM :TCP (:BYTE-STREAM)
  ((:NETWORK :INTERNET))
  ((:SERVICE :TCP-GATEWAY) (:MEDIUM :TCP)))

(DEFINE-MEDIUM :CHAOS (:BYTE-STREAM)
  (((:NETWORK :CHAOS)) (SERVICE-ACCESS-PATH &REST CONNECTION-ARGS)
   (DO-THE-RIGHT-CHAOS-THING SERVICE-ACCESS-PATH CONNECTION-ARGS)))

(DEFINE-MEDIUM :CHAOS-SIMPLE (:DATAGRAM)
  (((:NETWORK :CHAOS)) (SERVICE-ACCESS-PATH &REST CONNECTION-ARGS)
   (DO-THE-RIGHT-CHAOS-SIMPLE-THING SERVICE-ACCESS-PATH CONNECTION-ARGS)))

(DEFINE-MEDIUM :DIAL (:BYTE-STREAM)
  (((:NETWORK :DIAL)) (SERVICE-ACCESS-PATH &REST CONNECTION-ARGS)
   (DO-THE-RIGHT-DIAL-THING SERVICE-ACCESS-PATH CONNECTION-ARGS)))

(DEFINE-MEDIUM :X25 (:BYTE-STREAM)
  ((:NETWORK :X25))
  ((:SERVICE :X25-GATEWAY) (:MEDIUM :X25)))

;;; Building a reliable stream on top of an
(DEFINE-MEDIUM :MMDF (:BYTE-STREAM)
  (((:MEDIUM :BYTE-STREAM)) (SERVICE-ACCESS-PATH STREAM &REST CONNECTION-ARGS)
   (DO-THE-RIGHT-MMDF-THING SERVICE-ACCESS-PATH STREAM CONNECTION-ARGS)))

(DEFINE-MEDIUM :PSEUDONET (:BYTE-STREAM)
  ((:SERVICE :PSEUODNET-GATEWAY) (:NETWORK :GATEWAY-PSEUDONET)))

(DEFINE-MEDIUM :BYTE-STREAM ())
(DEFINE-MEDIUM :DATAGRAM ())
(DEFINE-MEDIUM :LOCAL () ((:LOCAL T)))
 
;;; Whenever medium X uses the built-on medium, it is as if the built-on medium
;;; is given the new implementation (:MEDIUM :X)

(DEFMACRO DEFINE-PROTOCOL (NAME (SERVICE BASE-MEDIUM) &BODY OPTIONS)
  "Options are (:OPTION . values) are:
DESIRABILITY: A number between 0 and 1, default 1
PROPERTY: (indicator property) Used for higher-level protocol-defining macros
 that save their own information.
INVOKE function: When the service is invoked, the function is called with the
 access path as an argument.
INVOKE-WITH-STREAM function: As above, but the arguments are a stream gotten with
 NET:GET-CONNECTION-FOR-SERVICE, and the service args.
INVOKE-WITH-STREAM-AND-CLOSE function: As above, but the stream is closed when the
 function returns.

Function can be a symbol or a lambda-list and the body.
The lambda should be either (STREAM . SERVICE-ARGS)
 or ((STREAM CONNECTION-ARGS) . SERVICE-ARGS)"
  )

(DEFINE-PROTOCOL :LOCAL-TIME (:TIME :LOCAL)
  (:INVOKE (IGNORE)
   (AND TIME:*TIME-IS-KNOWN-P* (TIME:GET-UNIVERSAL-TIME))))

;;; Chaos simple time, just returns 32b time from STREAM
(DEFINE-PROTOCOL :TIME-SIMPLE (:TIME DATAGRAM)
  (:DESIRABILITY .75)
  (:INVOKE-WITH-STREAM-AND-CLOSE (STREAM)
   (TIME-SIMPLE STREAM ())))

(DEFUN GET-CONNECTION-FOR-SERVICE (SERVICE-ACCESS-PATH &REST CONNECTION-ARGS)
  "Can be used inside :INVOKE to get a network stream.
CONNECTION-ARGS are passed onto the stream creator."
  )

;;; Services and protocols
;;; BAND-TRANSFER (BAND-TRANSFER)
;;; FILE (LOCAL-FILE, PUP-FTP, QFILE, TCP-FTP)
;;; HARDCOPY (DOVER, EFTP, LGP, LOCAL-HARDCOPY)
;;; (printer options)  (hardcopy-stream)
;;; LGP (chaos)
;;;   Contact name is LGP <file>NL<printer-name>NL<user-name>NL<date>
;;;   Date is decimal universal time
;;;  DOVER (chaos) AI-CHAOS-11
;;;  EFTP (pup)
;;; HARDCOPY-DEVICE-STATUS (DOVER-STATUS, LGP-STATUS)
;;; (printer)  printed info
;;;  LGP-STATUS (chaos)
;;;   Contact @ LGP-STATUS <printer>, ANS is status info
;;;  EARS-STATUS(datagram), DOVER-STATUS(datagram/chaos)
;;; HARDCOPY-STATUS (EARS-STATUS, LGP-QUEUE)
;;; (printer)  printed info
;;;  LGP-QUEUE (byte-stream)
;;;   Contact @ LGP-QUEUE printer
;;; LISPM-FINGER (LISPM-FINGER)
;;; (machine)  (list-of (uname machine-location idle-time personal-name affiliation))
;;; LOGIN (CHAT, EVAL, SUPDUP, TELNET, TELSUP, TTY-LOGIN)
;;; (machine)  (rnvt-stream, input-side-filters, output-side-filters, string-for-path)
;;; MAIL-TO-USER (CHAOS-MAIL, SMTP)
;;; (recipients template-expansion)
;;; NAMESPACE (IEN-811, NAMESPACE)
;;; ()  namespace-stream
;;; NAMESPACE-TIMESTAMP (NAMESPACE-TIMESTAMP)
;;; (namespace)  (timestamp)
;;; NOTIFY (NOTIFY)
;;; PACKET-GATEWAY (PUP-GATEWAY)
;;; PRINT-DISK-LABEL (LOCAL-PRINT-DISK-LABEL, NETWORK-PRINT-DISK-LABEL)
;;; PSEUDONET-GATEWAY (PSEUDONET-GATEWAY)
;;; SCREEN-SPY (CHAOS-SCREEN-SPY)
;;; SEND (SEND, SMTP)
;;; (&key date from to text)  (result)
;;; SHOW-USERS (ASCII-NAME, NAME)
;;; (&key user whois)
;;; STATUS (CHAOS-STATUS)
;;; STORE-AND-FORWARD-MAIL (CHAOS-MAIL, DUMMY-MAILER, SMTP)
;;; (recipients template-expansion)
;;; TAPE (RTAPE)
;;; TCP-GATEWAY (TCP-GATEWAY)
;;; TIME (LOCAL-TIME, PUP-MISC-SERVICES, TIME-MSB, TIME-SIMPLE, TIME-SIMPLE-MSB)
;;; UPTIME (UPTIME-SIMPLE)
;;; WHO-AM-I (WHO-AM-I)
;;; ()  (namespace-name-keyword {host-name, :UNKNOWN} answering-host)
;;;  WHO-AM-I (datagram)
;;;  ANS with NAMESPACE|HOST-NAME, or *UNKNOWN*
;;; YOW (YOW)
;;; Prints out a Zippyism
;;;  YOW (byte-stream) Chaos contact is YOW