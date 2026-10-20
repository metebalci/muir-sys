;;; -*- Mode:LISP; Package:INTERNET; Base:10; Readtable:ZL -*-
;;; A planted control for tcp-check's lockerror parts (README.md): a partial
;;; fix of the TELNET server's lock error (sys/network/ip/servers.lisp,
;;; TELNET-SESSION-LOCK-ERROR), whose handler frees NETWORK-LOCK and declines,
;;; so that the session still enters the debugger on its own stream.  Given
;;; after the fixed servers.lisp in --files, lockerror must fail: the session
;;; is not closed.  Not for any band in use.

(defun telnet-session-lock-error (condition)
  condition
  (when (eq network-lock current-process)
    (setq network-lock nil))
  nil)
