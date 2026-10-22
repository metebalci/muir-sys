;;; -*- Mode:LISP; Package:USER; Base:10; Readtable:ZL -*-
;;; For the checks process-debugger-abort and process-debugger-proceed and the
;;; harness warm-boot-debugger (tools/system-check/README.md): a process in the
;;; debugger whose terminal is a stream of the check's own, so that the check
;;; can type at the debugger.
;;; The debugger of a microcode error, and of a Lisp error too (INVOKE-DEBUGGER
;;; calls %ERROR-HANDLER-STACK-GROUP), runs in the error handler's stack group,
;;; and the process waits for input there.  The debugger's Resume sends the
;;; process back into its initial stack group without passing through the
;;; scheduler, which alone sets the process's STACK-GROUP slot
;;; (sys/sys2/proces.lisp, the scheduler's switch), so the slot still names the
;;; error handler's group when the process, its function done, kills itself
;;; (PROCESS-RUN-FUNCTION-INTERNAL-FLUSH-PROCESS): a kill that judges by that
;;; slot alone unwinds the stack group it runs in, and the machine halts
;;; (measured on micro).  The debugger's Abort, the restart "Terminate and free
;;; process", ends in the same self-kill.

(defvar *pdb-input* nil "Characters the debugger reads next, in order.")
(defvar *pdb-untyi* nil)
(defvar *pdb-reading* nil "T while the victim waits in the stream for input.")
(defvar *pdb-text* (make-array 4000 :type 'art-string :fill-pointer 0)
  "What the debugger printed, its first 4000 characters, for a failure's record.")
(defvar *pdb-log* nil "What the victim did, newest first.")
(defvar *pdb-proc* nil "The victim's process.")

(defun pdb-stream (op &optional arg1 &rest args)
  "The victim's terminal: :TYI waits for *PDB-INPUT*; output goes to *PDB-TEXT*."
  (case op
    (:which-operations '(:tyi :untyi :tyo :read-cursorpos))
    (:tyi (or (prog1 *pdb-untyi* (setq *pdb-untyi* nil))
	      (progn (setq *pdb-reading* t)
		     (process-wait "PDB input" #'(lambda () *pdb-input*))
		     (setq *pdb-reading* nil)
		     (pop *pdb-input*))))
    (:untyi (setq *pdb-untyi* arg1) nil)
    (:tyo (when (< (fill-pointer *pdb-text*) (array-length *pdb-text*))
	    (vector-push (int-char (logand arg1 #o177)) *pdb-text*))
	  nil)
    (:read-cursorpos (values 0 0))
    (otherwise (stream-default-handler 'pdb-stream op arg1 args))))

(defun pdb-start (function)
  "Run FUNCTION in a fresh PROCESS-RUN-FUNCTION process, not restartable, whose terminal
is PDB-STREAM; wait until it reads input (at most 5 s).  Returns (READING IN-INITIAL-SG):
READING T once the victim waits in the stream, IN-INITIAL-SG whether its STACK-GROUP slot
is then its initial stack group."
  (setq *pdb-input* nil *pdb-untyi* nil *pdb-reading* nil *pdb-log* nil)
  (setf (fill-pointer *pdb-text*) 0)
  (setq *pdb-proc* (process-run-function "pdb victim"
					 #'(lambda (f)
					     (let ((*terminal-io* 'pdb-stream)
						   (*debug-io* 'pdb-stream))
					       (funcall f)))
					 function))
  (process-wait-with-timeout "PDB victim" 300. #'(lambda () *pdb-reading*))
  (list *pdb-reading*
	(eq (send *pdb-proc* :stack-group) (send *pdb-proc* :initial-stack-group))))

(defun pdb-victim-alive ()
  "T while a process named pdb victim is in SI:ALL-PROCESSES.  The victim's process,
once killed, is a spare that the next PROCESS-RUN-FUNCTION takes and renames (the
TELNET server's for a new session among them), so the process object alone does not
tell whether the victim still runs."
  (loop for p in si:all-processes
	thereis (equal (send p :name) "pdb victim")))

(defun pdb-type (char)
  "CHAR typed at the victim's debugger; wait until the victim has left the process list
or 5 s.  Returns (ALIVE WHOSTATE LOG): ALIVE whether it is still in SI:ALL-PROCESSES,
WHOSTATE its process's wait whostate, LOG what it did, newest first."
  (setq *pdb-input* (list char))
  (process-wait-with-timeout "PDB typed" 300. #'(lambda () (not (pdb-victim-alive))))
  (process-sleep 30.)
  (list (pdb-victim-alive)
	(si:process-wait-whostate *pdb-proc*)
	*pdb-log*))

(defun pdb-fresh-processes ()
  "Two fresh PROCESS-RUN-FUNCTION processes, one after the other, each run: (:RAN :RAN2)."
  (let ((ran nil))
    (process-run-function "pdb next" #'(lambda () (push :ran ran)))
    (process-wait-with-timeout "PDB next" 300. #'(lambda () ran))
    (process-run-function "pdb next2" #'(lambda () (push :ran2 ran)))
    (process-wait-with-timeout "PDB next2" 300. #'(lambda () (cdr ran)))
    (reverse ran)))

(defun pdb-left ()
  "The names of this check's processes still in SI:ALL-PROCESSES."
  (loop for p in si:all-processes
	when (string-search "pdb " (send p :name))
	  collect (send p :name)))
