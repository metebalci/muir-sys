;;; -*- Mode:Lisp;Package:NETI;Base:8 -*-
;;; Stuff to define servers
;;;

(DEFMACRO DEFINE-SERVER (PROTOCOL-NAME OPTIONS &BODY BODY)
  "OPTIONS is an alternating list of keywords and values
BODY is the actual server code
Options include
:MEDIUM required
:ERROR-DISPOSITION : {nil or :NOTIFY}, :IGNORE, :DEBUGGER
:HOST var: user host
:NETWORK var: user network
:SECURE-P var
:REJECT-UNLESS-SECURE t or nil
:WHO-LINE t-or-nil
:PROCESS-NAME a string, defaulting to PROTOCOL server
 For :MEDIUM :BYTE-STREAM
:STREAM x: x is either a variable-name or a list of the variable and options:
 :ASCII-TRANSLATION (t, default nil)
 :ACCEPT-P (default t, nil) nil means send the stream either :ACCEPT or :REJECT
 :DIRECTION (:INPUT, :OUTPUT, default :BIDIRECTIONAL)
:NO-EOF t-or-nil: close in abort mode
 For :MEDIUM :DATAGRAM
:REQUEST-ARRAY list-of (array_var, start_idx_var, end_idx_var)
:RESPONSE-ARRAY as above.  Or, the body can return a second value as a string
 to use, and omit the :RESPONSE-ARRAY keyword

If :MEDIUM is :CHAOS
:CONN chaos-connection-variable (don't need chaos:listen)
 Still need to accept, reject, remove-conn"
  )

  )

(DEFUN CHAOS:ADD-CONTACT-NAME-FOR-PROTOCOL
       (PROTOCOL &OPTIONAL (CONTACT-NAME (GET-PNAME PROTOCOL)))
  )

