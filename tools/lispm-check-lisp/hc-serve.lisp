;;; -*- Mode:LISP; Package:USER; Base:10 -*-
;;; HC-SERVE: tools/lispm-check's session through files on the file device's
;;; host (--network files), for a band checked without its network: revision
;;; 15, whose band has no Chaos and no Ethernet device, or any band on 16 that
;;; is to be checked without its tap.
;;;
;;; The tool's setup writes this file, after its own LISPM-CHECK-CASE (the
;;; tool's HELPER, the same function a TELNET session calls), as the login's
;;; init file, /home/lispm/lispm.init, and types two short forms at the
;;; console through muir's glass TTY: (login "LISPM"), which loads the init
;;; file, and (hc-serve).  Two forms of 27 characters in all, since the band
;;; keeps only the first 40-odd characters typed before its listener runs
;;; (measured; tools/lispm-check, HC_START), and since (hc-serve) must run at the
;;; listener and not inside a LOAD: a load's stream stays open, and the file
;;; device refuses a checkpoint while a handle is open.
;;;
;;; The loop: request K is /home/lispm/hc-K.req on the host the login is on;
;;; its answer, what LISPM-CHECK-CASE printed, goes to hc-K.ans, and then
;;; hc-K.done holds K: the tool reads the answer only once .done is there.
;;; Between two polls the loop sleeps in PROCESS-SLEEP with no stream open,
;;; so that a checkpoint taken while it waits meets no handle open and, but
;;; for the poll's one PROBEF, no command queued.  A request runs with no
;;; stream open either: what it prints is kept in a string and written after
;;; it.  The forms are read by READ in the listener's package and base, USER
;;; and 10, as the TELNET listener reads them.
;;;
;;; A bare (Y or N), asked without FQUERY, or an error LISPM-CHECK-CASE does
;;; not catch, waits at the console listener: the request gets no answer and
;;; the tool's run fails at --timeout.  Output to TERMINAL-IO is not seen.

(defvar *hc-k* 0 "The number of the last request taken.")
(defvar *hc-sleep* 6 "The ticks of the 60 Hz clock between two polls.")

(defun hc-path (k type)
  "The file of request K, of TYPE (req, ans or done), in the login's home."
  (format nil "~A: //home//lispm//hc-~D.~A" (send fs:user-login-machine :name) k type))

(defun hc-write (path thing princ-p)
  "THING to the file PATH, by PRINC or PRIN1, and the file closed.  A file
of that name left by an earlier run is superseded, not an error."
  (with-open-file (o path ':direction ':output ':if-exists ':supersede)
    (if princ-p (princ thing o) (prin1 thing o))))

(defun hc-serve ()
  "Serve the tool's requests until a request :HC-STOP.  hc-ready.txt says
the loop runs."
  (hc-write (format nil "~A: //home//lispm//hc-ready.txt" (send fs:user-login-machine :name))
            *hc-k* nil)
  (do () (nil)
    (let ((req (hc-path (1+ *hc-k*) "req")))
      (do () ((probef req)) (process-sleep *hc-sleep*))
      (let ((form (with-open-file (s req) (read s))))
        (setq *hc-k* (1+ *hc-k*))
        (when (eq form ':hc-stop)
          (return *hc-k*))
        (let ((text (with-output-to-string (standard-output)
                      (lispm-check-case *hc-k* form))))
          (hc-write (hc-path *hc-k* "ans") text t))
        (hc-write (hc-path *hc-k* "done") *hc-k* nil)))))

(compile 'hc-path)
(compile 'hc-write)
(compile 'hc-serve)
