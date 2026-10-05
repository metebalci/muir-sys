;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:10; Readtable:ZL -*-
;;;
;;; This is SYS: IO; FDEV
;;;
;;; quux: the driver of quux's file device (contract q9, revision 9).  the
;;; device is muir's as built at ab87378, described in its docs/quux.md,
;;; "the file device": folders of the host served to the machine under the
;;; pathname host HOST, commands and responses in two rings in main memory,
;;; the bytes moved by dma, and only control and the rings' indexes in the
;;; registers, words 160-171 of the register page.  the pathname host, its
;;; access and its streams are in SYS: IO; FILE; HOSTFS; this file is only
;;; the rings.  it is loaded by mini before qld's lisp-reinitialize, so that
;;; the reset below runs there, and nothing here touches the device when the
;;; file is loaded: mini may be reading this very file through it.
;;;
;;; the driver polls.  the device's interrupt enable, register 160 <8>,
;;; stays off: the device's interrupt is word 100 <7> from revision 11
;;; (contract q13; <6> before), and microcode 2000 takes it as a stray,
;;; turning <8> off and dismissing it, so the driver never sets it.  a
;;; waiting process is woken by its wait predicate, which the scheduler runs
;;; on every pass, and which reads one register and conses nothing.
;;;
;;; the rings, 16 entries of 8 words each, share one wired page; each of the
;;; 16 command slots owns two wired pages of the name area, one for buffer a
;;; (a name, a log line) and one for buffer b (a second name, a directory
;;; listing, a completion).  a stream's data pages are its own rqb's.
;;; responses come in command order, one each, so command n's response is
;;; response n and its slot is n mod 16 in both rings and in the tables
;;; here; the tag the device echoes is only a check.

;;;; The layout (docs/quux.md, "the file device"; one place, as the design asks)

(defconst %file-device-control-register (+ feature-page-xbus-address #o160)
  "Register 160: <0> enable, <8> interrupt enable.  Written 0, the device is reset.")
(defconst %file-device-status-register (+ feature-page-xbus-address #o161)
  "Register 161: <0> enabled, <1> quiet, <2> configuration refused, <3> index fault,
<8> a response waiting, <23:16> handles open.")
(defconst %file-device-command-base-register (+ feature-page-xbus-address #o162))
(defconst %file-device-command-size-register (+ feature-page-xbus-address #o163))
(defconst %file-device-command-producer-register (+ feature-page-xbus-address #o164))
(defconst %file-device-command-consumer-register (+ feature-page-xbus-address #o165))
(defconst %file-device-response-base-register (+ feature-page-xbus-address #o166))
(defconst %file-device-response-size-register (+ feature-page-xbus-address #o167))
(defconst %file-device-response-producer-register (+ feature-page-xbus-address #o170))
(defconst %file-device-response-consumer-register (+ feature-page-xbus-address #o171))

(defconst %%file-device-control-enable #o0001)
(defconst %%file-device-control-interrupt-enable #o1001)
(defconst %%file-device-status-enabled #o0001)
(defconst %%file-device-status-quiet #o0101)
(defconst %%file-device-status-refused #o0201)
(defconst %%file-device-status-index-fault #o0301)
(defconst %%file-device-status-response-waiting #o1001)
(defconst %%file-device-status-handles-open #o2010)

;; feature word 15 <1> says the device is there; the word reads 0 below
;; revision 9.
(defconst %%file-device-feature #o0101)

(defconst %file-device-entry-words 8 "Words in a command entry and in a response entry.")
(defconst %file-device-ring-log2 4 "The log2 of the entries in each ring.")
(defconst %file-device-ring-entries 16)

;; command entry words
(defconst %file-device-command-header 0)	;<15:0> tag, <23:16> opcode, <31:24> flags
(defconst %file-device-command-handle 1)
(defconst %file-device-command-a-address 2)
(defconst %file-device-command-a-length 3)
(defconst %file-device-command-b-address 4)
(defconst %file-device-command-b-length 5)
(defconst %file-device-command-offset 6)	;read, write: the offset; directory: the cookie
(defconst %file-device-command-date 7)		;close: the date to set
;; response entry words
(defconst %file-device-response-header 0)	;<15:0> tag, <23:16> status, <31:24> opcode
(defconst %file-device-response-count 1)
(defconst %file-device-response-handle 2)
(defconst %file-device-response-length 3)
(defconst %file-device-response-mtime 4)
(defconst %file-device-response-flags 5)
(defconst %file-device-response-cookie 6)	;directory: the next cookie; complete: the matches

(defconst %file-device-op-open 1)
(defconst %file-device-op-read 2)
(defconst %file-device-op-write 3)
(defconst %file-device-op-close 4)
(defconst %file-device-op-directory 5)
(defconst %file-device-op-complete 6)
(defconst %file-device-op-delete 7)
(defconst %file-device-op-rename 8)
(defconst %file-device-op-create-directory 9)
(defconst %file-device-op-log 10)

(defconst %file-device-open-read 0)
(defconst %file-device-open-write 1)
(defconst %file-device-open-probe 2)
(defconst %%file-device-open-mode #o0002)
(defconst %%file-device-open-if-exists #o0202)	;0 supersede, 1 error, 2 append
(defconst %%file-device-open-if-does-not-exist #o0401)	;0 create, 1 error
(defconst %%file-device-close-abort #o0001)
(defconst %%file-device-close-set-date #o0101)

;; response flags word
(defconst %%file-device-flag-directory #o0001)
(defconst %%file-device-flag-read-only #o0101)
(defconst %%file-device-flag-complete-exact #o0201)
(defconst %%file-device-flag-complete-directory #o0301)

;; statuses: 0 done; 1-17 the file conditions, mapped in SYS: IO; FILE;
;; HOSTFS; 64-66 faults of this driver, never file conditions.
(defconst %file-device-status-done 0)
(defconst %file-device-fault-names
	  '((64. . "bad handle") (65. . "bad buffer") (66. . "bad argument"))
  "The device's statuses 64 to 66, faults of this driver.")

(defconst %file-device-name-page-bytes (* page-size 4)
  "A slot's buffer a and buffer b are one page each.")
(defconst %file-device-quiet-timeout 120.
  "Sixtieths of a second to wait for the device to become quiet at a reset.")
(defconst file-device-spin-polls 100.
  "Register polls before a waiting process gives the processor up.")

;;;; State

(defvar file-device-lock nil "Held while the rings and the tables below change.")
(defvar file-device-generation 0 "Counts resets; a command of an older generation is gone.")
(defvar file-device-enabled nil "T once a reset has enabled the device.")
(defvar file-device-ring-rqb nil "One page: the command ring, then the response ring.")
(defvar file-device-name-rqb nil "Two pages a slot: buffer a, then buffer b.")
(defvar file-device-ring-address nil "The ring page's physical address.")
(defvar file-device-name-addresses (make-array (* 2 %file-device-ring-entries))
  "The physical address of each page of the name area.")
(defvar file-device-command-count 0 "Commands submitted, mod 2^16: register 164.")
(defvar file-device-response-count 0 "Responses taken from the ring, mod 2^16: register 171.")
(defvar file-device-slot-state (make-array %file-device-ring-entries)
  "NIL free, :SUBMITTED, :ANSWERED, or :ORPHAN when its waiter has gone.")
(defvar file-device-slot-index (make-array %file-device-ring-entries)
  "The command index each slot holds.")
(defvar file-device-slot-response
	(make-array (list %file-device-ring-entries %file-device-entry-words))
  "Each slot's response, copied out of the response ring.")
(defvar file-device-deferred-rqbs nil
  "Elements (rqb . index): the rqb goes back to its resource once command index is answered.
A stream that closes with a command still naming its pages defers its rqb here,
so that no page is reused while the device may write it.")
(defvar file-device-commands-submitted 0 "Every command submitted since the band was built.")

;;;; Registers and memory

(defsubst file-device-register (register)
  (%xbus-read register))

(defsubst file-device-set-register (register value)
  (%xbus-write register value))

(defun file-device-present-p ()
  "T if the machine has a file device (feature word 15 <1>)."
  (not (zerop (feature-page-field #o15 %%file-device-feature))))

(defun file-device-rqb-page-address (rqb page)
  "The physical word address of data page PAGE of a wired RQB, from its CCW list."
  ;; wire-disk-rqb writes each data page's physical address into the ccw
  ;; list: the low 16 bits (bit 0 the chain bit, the page's low bits 0) and
  ;; the high bits.
;  (+ (logand (aref rqb (+ %disk-rq-ccw-list (* 2 page))) (- page-size))
;     (ash (aref rqb (+ %disk-rq-ccw-list 1 (* 2 page))) 16.)))
  ;; 1024-word pages (contract g2, option (w)): a page has
  ;; disk-blocks-per-page ccws, a block each, and its first is the page's
  ;; address, the page's frame being whole.
;  (let ((ccw (+ %disk-rq-ccw-list (* 2 page disk-blocks-per-page))))
  ;; quux revision 13 (appendix a1.11): a ccw a page, the page's address
  (let ((ccw (+ %disk-rq-ccw-list (* 2 page))))
    (+ (logand (aref rqb ccw) (- page-size))
       (ash (aref rqb (1+ ccw)) 16.))))

(defun file-device-8-bit-view (rqb)
  "An ART-8B array over RQB's data pages, made as MAKE-DISK-RQB makes its views."
  (let* ((n-pages (rqb-npages rqb))
	 (view (make-array (* page-size 4 n-pages)
			   :type art-8b
			   :displaced-to ""
			   :displaced-index-offset
			   (* 2 (- (array-length rqb) (* page-size 2 n-pages))))))
    (%p-store-contents-offset rqb view 1)
    view))

;; a ring word is two halves of the rqb's art-16b view.  a word may be a
;; bignum (an mtime, a header with its flags), so it is split and joined
;; with ash and logand, which take one.
(defsubst file-device-store-word (buffer word value)
  (setf (aref buffer (* 2 word)) (logand value #o177777))
  (setf (aref buffer (1+ (* 2 word))) (logand (ash value -16.) #o177777)))

(defsubst file-device-fetch-word (buffer word)
  (+ (aref buffer (* 2 word)) (ash (aref buffer (1+ (* 2 word))) 16.)))

(defsubst file-device-index-answered-p (index)
  "T if response INDEX has been taken off the ring."
  ;; indexes count mod 2^16; at most 16 are outstanding.
  (< 0 (logand (- file-device-response-count index) #o177777) #o100000))

;;;; Reset

(defun file-device-disable ()
  "Disable the file device: its commands not yet run are dropped and every handle is closed.
A command it had run stands, host effect and all, though its response is lost."
  (when (file-device-present-p)
    (file-device-set-register %file-device-control-register 0)
    (setq file-device-enabled nil)
    (incf file-device-generation))
  nil)

;; no dma while disk-save writes memory out, and muir refuses a checkpoint
;; while a handle is open.  the next command re-enables the device.
(add-initialization "File device off" '(file-device-disable) '(:before-cold))

(defun file-device-reset (&optional (error-p t))
  "Reset the file device and point it at this driver's rings.
The sequence of docs//quux.md: disable, wait for quiet, write the ring bases and
sizes, enable, check the status.  Everything in flight is forgotten; its
waiters get an error.  Returns T, or NIL and a message if ERROR-P is NIL."
  (block reset
    (flet ((fail (format-string &rest args)
	     (setq file-device-enabled nil)
	     (if error-p
		 (apply #'ferror nil format-string args)
	       (return-from reset
		 (values nil (apply #'format nil format-string args))))))
      (unless (file-device-present-p)
	(fail "This machine has no file device (feature word 15 <1> is clear)."))
      (file-device-disable)
      ;; muir is quiet at once; the boards finish a copy first.
      (let ((start (time)))
	(do () ((ldb-test %%file-device-status-quiet
			  (file-device-register %file-device-status-register)))
	  (when (> (time-difference (time) start) %file-device-quiet-timeout)
	    (fail "The file device did not become quiet within ~D//60 s of a disable (status ~O)."
		  %file-device-quiet-timeout
		  (file-device-register %file-device-status-register)))))
      ;; nothing is in flight now: forget every slot, and give back the
      ;; pages that waited for an answer that will not come.
      (dotimes (slot %file-device-ring-entries)
	(setf (aref file-device-slot-state slot) nil))
      (dolist (deferred (prog1 file-device-deferred-rqbs (setq file-device-deferred-rqbs nil)))
	(return-disk-rqb (car deferred)))
      (setq file-device-command-count 0 file-device-response-count 0)
      ;; the rings and names, wired again: wiring does not survive a boot, and
      ;; a page's physical address may differ after one.
      (or file-device-ring-rqb (setq file-device-ring-rqb (get-disk-rqb 1)))
      (or file-device-name-rqb
	  (setq file-device-name-rqb (get-disk-rqb (* 2 %file-device-ring-entries))))
      (wire-disk-rqb file-device-ring-rqb 1 t t)
      (wire-disk-rqb file-device-name-rqb (* 2 %file-device-ring-entries) t t)
      (setq file-device-ring-address (file-device-rqb-page-address file-device-ring-rqb 0))
      (dotimes (page (* 2 %file-device-ring-entries))
	(setf (aref file-device-name-addresses page)
	      (file-device-rqb-page-address file-device-name-rqb page)))
      (file-device-set-register %file-device-command-base-register file-device-ring-address)
      (file-device-set-register %file-device-command-size-register %file-device-ring-log2)
      (file-device-set-register %file-device-response-base-register
				(+ file-device-ring-address
				   (* %file-device-ring-entries %file-device-entry-words)))
      (file-device-set-register %file-device-response-size-register %file-device-ring-log2)
      ;; enabled, interrupt enable off: we poll.
      (file-device-set-register %file-device-control-register 1)
      (let ((status (file-device-register %file-device-status-register)))
	(unless (and (ldb-test %%file-device-status-enabled status)
		     (not (ldb-test %%file-device-status-refused status)))
	  (fail "The file device refused its configuration (status ~O; rings at ~O)."
		status file-device-ring-address)))
      (setq file-device-enabled t)
      t)))

(defun file-device-boot-reset ()
  "LISP-REINITIALIZE's reset, before the error table is loaded; never an error."
  (when (file-device-present-p)
    ;; a process that held the lock when the machine stopped is gone.  only
    ;; here: FILE-DEVICE-RESET also runs inside the lock, from a command.
    (setq file-device-lock nil)
    (multiple-value-bind (ok message) (file-device-reset nil)
      (unless ok
	(format t "~&~A~%" message)))))

;;;; Commands

;; named functions, defined above their callers: qld reloads this file
;; through itself, and an internal lambda is invalid in the gap fasload
;; leaves (the lesson of 8942300, chsncp.lisp).
(defun file-device-response-waiting-p ()
  "T if a response is on the ring that this driver has not taken."
  (not (= (file-device-register %file-device-response-producer-register)
      file-device-response-count)))

(defun file-device-slot-answered-p (slot index generation)
  (or (not (= generation file-device-generation))
      (and (eq (aref file-device-slot-state slot) :answered)
	   (eql (aref file-device-slot-index slot) index))
      (not (= (file-device-register %file-device-response-producer-register)
	  file-device-response-count))))

(defun file-device-slot-free-p (slot generation)
  (or (not (= generation file-device-generation))
      (null (aref file-device-slot-state slot))
      (not (= (file-device-register %file-device-response-producer-register)
	  file-device-response-count))))

(defun file-device-drain ()
  "Take every response the device has written off the ring.  Call with the lock held."
  (let ((ring (rqb-buffer file-device-ring-rqb))
	(producer (file-device-register %file-device-response-producer-register))
	(taken nil))
    (do () ((= producer file-device-response-count))
      (let* ((index file-device-response-count)
	     (slot (logand index (1- %file-device-ring-entries)))
	     (base (* (+ %file-device-ring-entries slot) %file-device-entry-words))
	     (header (file-device-fetch-word ring base)))
	(unless (= (logand header #o177777) index)
	  (ferror nil "File device: response ~D carries tag ~D." index (logand header #o177777)))
	(without-interrupts
	  (cond ((eq (aref file-device-slot-state slot) :orphan)
		 (setf (aref file-device-slot-state slot) nil))
		(t
		 (dotimes (word %file-device-entry-words)
		   (setf (aref file-device-slot-response slot word)
			 (file-device-fetch-word ring (+ base word))))
		 (setf (aref file-device-slot-state slot) :answered))))
	(setq file-device-response-count (logand (1+ index) #o177777)
	      taken t)))
    (when taken
      (file-device-set-register %file-device-response-consumer-register
				file-device-response-count)
      (when file-device-deferred-rqbs
	(dolist (deferred file-device-deferred-rqbs)
	  (when (file-device-index-answered-p (cdr deferred))
	    (setq file-device-deferred-rqbs (delq deferred file-device-deferred-rqbs))
	    (return-disk-rqb (car deferred))))))))

(defun file-device-put-string (string page)
  "Copy STRING's bytes into page PAGE of the name area; return its address and length."
  (let ((length (string-length string)))
    (when (> length %file-device-name-page-bytes)
      (ferror nil "File device: a name or line of ~D bytes is over ~D."
	      length %file-device-name-page-bytes))
    (copy-array-portion string 0 length
			(rqb-8-bit-buffer file-device-name-rqb)
			(* page %file-device-name-page-bytes)
			(+ (* page %file-device-name-page-bytes) length))
    (values (aref file-device-name-addresses page) length)))

(defun file-device-buffer-spec (spec page)
  "Buffer A or B of a command: NIL, a string (copied into name page PAGE), :PAGE
\(name page PAGE, whole), or a list (physical-address length)."
  (cond ((null spec) (values 0 0))
	((stringp spec) (file-device-put-string spec page))
	((eq spec :page)
	 (values (aref file-device-name-addresses page) %file-device-name-page-bytes))
	(t (values (first spec) (second spec)))))

;; the device may have been taken from the driver since its reset: a boot
;; disables it (reset devices, register page word 104, which the prom and
;; the microcode's reset-machine write from quux revision 10, contract q11;
;; the unibus reset below it), and MINI (cold/mini.lisp) gives it its
;; own rings whenever it is used and finds them not there.  so the driver
;; checks, before each command, that the device is enabled on its rings, and
;; resets it if not; whichever of the two is used next takes the device.
(defun file-device-ensure-enabled ()
  (unless (and file-device-enabled
	       (eql (file-device-register %file-device-command-base-register)
		    file-device-ring-address)
	       (ldb-test %%file-device-status-enabled
			 (file-device-register %file-device-status-register)))
    (file-device-reset t)))

(defun file-device-submit (opcode &optional (flags 0) (handle 0) a b (offset 0) (date 0))
  "Put one command on the ring and return its index, to give to FILE-DEVICE-WAIT.
A and B are as FILE-DEVICE-BUFFER-SPEC takes them."
  (let ((generation file-device-generation) (index nil))
    (do () (index)
      (setq index
	    (with-lock (file-device-lock)
	      (file-device-ensure-enabled)
	      ;; the generation this command belongs to, after any reset above.
	      (setq generation file-device-generation)
	      (file-device-drain)
	      (let ((slot (logand file-device-command-count (1- %file-device-ring-entries))))
		(when (null (aref file-device-slot-state slot))
		  (let ((ring (rqb-buffer file-device-ring-rqb))
			(base (* slot %file-device-entry-words))
			(index file-device-command-count))
		    (multiple-value-bind (a-address a-length)
			(file-device-buffer-spec a (* 2 slot))
		      (multiple-value-bind (b-address b-length)
			  (file-device-buffer-spec b (1+ (* 2 slot)))
			(file-device-store-word ring base
						(+ index (ash opcode 16.) (ash flags 24.)))
			(file-device-store-word ring (+ base 1) handle)
			(file-device-store-word ring (+ base 2) a-address)
			(file-device-store-word ring (+ base 3) a-length)
			(file-device-store-word ring (+ base 4) b-address)
			(file-device-store-word ring (+ base 5) b-length)
			(file-device-store-word ring (+ base 6) offset)
			(file-device-store-word ring (+ base 7) date)))
		    (setf (aref file-device-slot-index slot) index
			  (aref file-device-slot-state slot) :submitted)
		    (setq file-device-command-count (logand (1+ index) #o177777))
		    (incf file-device-commands-submitted)
		    ;; the register write drains the processor's write buffer
		    ;; first, so the entry and the name are in memory when the
		    ;; device reads them (contract, section 2).
		    (file-device-set-register %file-device-command-producer-register
					      file-device-command-count)
		    index)))))
      ;; every slot is busy: wait for one, or for a response to take.
      (unless index
	(process-wait "File device" #'file-device-slot-free-p
		      (logand file-device-command-count (1- %file-device-ring-entries))
		      generation)))
    (values index generation)))

(defun file-device-abandon (index)
  "The waiter of command INDEX will not take its response: free its slot when it comes."
  (let ((slot (logand index (1- %file-device-ring-entries))))
    (without-interrupts
      (when (eql (aref file-device-slot-index slot) index)
	(case (aref file-device-slot-state slot)
	  (:submitted (setf (aref file-device-slot-state slot) :orphan))
	  (:answered (setf (aref file-device-slot-state slot) nil)))))))

(defun file-device-wait (index generation &optional want-b)
  "Wait for command INDEX's response and return its words:
status, count, handle, length, mtime, flags, word 6, and, if WANT-B, a string of
the COUNT bytes the device wrote into buffer B of the name area."
  (declare (values status count handle length mtime flags word-6 b-string))
  (let ((slot (logand index (1- %file-device-ring-entries)))
	(taken nil) (status nil) (count nil) (handle nil) (length nil) (mtime nil)
	(flags nil) (word-6 nil) (b-string nil))
    ;; the words are copied into locals here and returned below, outside the
    ;; unwind-protect.  returned from inside it, from a multiple-value-prog1
    ;; in a do, a caller that took one value got 0 for the status while
    ;; multiple-value-list got every value right (measured: the delete of a
    ;; file on a read-only folder "succeeded").
    (unwind-protect
	(do () (taken)
	  (when (not (= generation file-device-generation))
	    (ferror nil "The file device was reset with command ~D in flight; ~
the command may have taken effect on the host without an answer." index))
	  (cond ((and (eq (aref file-device-slot-state slot) :answered)
		      (eql (aref file-device-slot-index slot) index))
		 (setq status (logand (ash (aref file-device-slot-response slot 0) -16.) #o377)
		       count (aref file-device-slot-response slot 1)
		       handle (aref file-device-slot-response slot 2)
		       length (aref file-device-slot-response slot 3)
		       mtime (aref file-device-slot-response slot 4)
		       flags (aref file-device-slot-response slot 5)
		       word-6 (aref file-device-slot-response slot 6))
		 (when want-b
		   (let ((start (* (1+ (* 2 slot)) %file-device-name-page-bytes)))
		     (setq b-string (substring (rqb-8-bit-buffer file-device-name-rqb)
					       start
					       (+ start (min count %file-device-name-page-bytes))))))
		 (without-interrupts
		   (setf (aref file-device-slot-state slot) nil)
		   (setq taken t)))
		((file-device-response-waiting-p)
		 (with-lock (file-device-lock) (file-device-drain)))
		(t
		 ;; muir answers in tens of microseconds of machine time: spin a
		 ;; little before giving the processor up.
		 (do ((polls 0 (1+ polls)))
		     ((or (>= polls file-device-spin-polls)
			  (file-device-response-waiting-p)))
		   nil)
		 (unless (file-device-response-waiting-p)
		   (process-wait "File device" #'file-device-slot-answered-p
				 slot index generation)))))
      (unless taken
	(when (= generation file-device-generation)
	  (file-device-abandon index))))
    (values status count handle length mtime flags word-6 b-string)))

(defun file-device-call (opcode &optional (flags 0) (handle 0) a b (offset 0) (date 0) want-b)
  "Submit one command and wait for its response; the values are FILE-DEVICE-WAIT's."
  (multiple-value-bind (index generation)
      (file-device-submit opcode flags handle a b offset date)
    (file-device-wait index generation want-b)))

(defun file-device-return-rqb (rqb last-index &optional (generation file-device-generation))
  "Give RQB back to its resource once command LAST-INDEX (or NIL) of GENERATION has
been answered.  After a reset nothing more is written to it."
  (without-interrupts
    (if (or (null last-index)
	    (not (= generation file-device-generation))
	    (null file-device-ring-rqb)
	    (file-device-index-answered-p last-index))
	(return-disk-rqb rqb)
      (push (cons rqb last-index) file-device-deferred-rqbs))))

(defun file-device-log (line)
  "Write LINE on muir's standard error (the boards: Linux's log), after log: ."
  (file-device-call %file-device-op-log 0 0 (string line)))

(defun file-device-state ()
  "A plist describing the driver and the device, for tests and PEEK."
  (list :control (file-device-register %file-device-control-register)
	:status (file-device-register %file-device-status-register)
	:command-base (file-device-register %file-device-command-base-register)
	:command-size (file-device-register %file-device-command-size-register)
	:response-base (file-device-register %file-device-response-base-register)
	:response-size (file-device-register %file-device-response-size-register)
	:command-producer (file-device-register %file-device-command-producer-register)
	:command-consumer (file-device-register %file-device-command-consumer-register)
	:response-producer (file-device-register %file-device-response-producer-register)
	:response-consumer (file-device-register %file-device-response-consumer-register)
	:ring-address file-device-ring-address
;	:ring-address-now (and file-device-ring-rqb
;			       (%physical-address
;				 (+ (%pointer file-device-ring-rqb) 1
;				    (%p-ldb %%array-long-length-flag file-device-ring-rqb)
;				    (floor (- (array-length file-device-ring-rqb)
;					      (* page-size 2)) 2))))
	;; quux revision 14 (contract g3 revision 14, 10.10): the ring's address
	;; by %pointer-plus of the rqb and the offset, so that an rqb at or
	;; across 2^31 names its own word, not a bignum's
	:ring-address-now (and file-device-ring-rqb
			       (%physical-address
				 (%pointer-plus file-device-ring-rqb
						(+ 1
						   (%p-ldb %%array-long-length-flag file-device-ring-rqb)
						   (floor (- (array-length file-device-ring-rqb)
							     (* page-size 2)) 2)))))
	:enabled file-device-enabled
	:generation file-device-generation
	:commands file-device-command-count
	:responses file-device-response-count
	:busy-slots (loop for slot below %file-device-ring-entries
			  count (aref file-device-slot-state slot))
	:deferred-rqbs (length file-device-deferred-rqbs)
	:submitted file-device-commands-submitted))
