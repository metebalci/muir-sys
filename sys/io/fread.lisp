;;-*- Mode:LISP; Package:MICRO-ASSEMBLER; Lowercase:T; Base:8 -*-

(defun read-ucode (file)
  (with-open-file (stream file :direction :input :characters t)
    ;; since these files have a way of saying (setq random-symbol ...)
    (si:eval-special-ok (fread stream))))

;; Fast, simple reader for reading in ucode

(defvar *stream* :unbound
  "Stream that was passed to FREAD, for reference from within FREAD.")

(defvar *line-in* :unbound
  "Within FREAD, buffers one line read from the stream passed to FREAD.")

(defvar *line-in-index* :unbound
  "Within FREAD, index for scanning within *LINE-IN*")

(defvar *line-in-length* :unbound
  "Within FREAD, length of valid data in *LINE-IN*")

(defvar *unrchf* :unbound
  "Used within FREAD for backing up one character.")

(defvar *char-type-table* :unbound
  "Syntax table used by FREAD.  Indexed by an input character.
Each element is:
 NIL  -> break char
 T -> whitespace
 negative number, -n  -> number, ascii code n
 positive number, +n  -> non-number. n is code to store
  (n is identical to the character used to index, except for upcasing).")

(defvar *fread-string* :unbound)

(defmacro fread-eat-whitespace nil
  `(prog ()
      l	 (when (eq (setq char-type (aref *char-type-table* (setq char (fread-tyi))))
		   t)
	   (go l))
	 (return char)))

(defmacro fread-tyi (&optional preserve-crs)
  `(prog ()
	 (cond (*unrchf*
		(return (prog1 *unrchf* (setq *unrchf* nil)))))
      l  (cond ,@(if preserve-crs '(((= *line-in-index* *line-in-length*)
				     (setq *line-in-index* (1+ *line-in-index*))
				     (return #/return))))
	       ((>= *line-in-index* *line-in-length*)
		(return-array (prog1 *line-in* (setq *line-in* nil)))
		(multiple-value-setq (*line-in* eof-flag)
		  (send *stream* :line-in))
		(and eof-flag
		     (equal *line-in* "")
		     (ferror nil "Premature EOF in fast reader"))
		(setq *line-in-length* (length *line-in*))
		(setq *line-in-index* 0)
		(go l)))
	 (return (prog1 (char-int (char *line-in* *line-in-index*))
			(incf *line-in-index*)))))
			 
; eof-error-p and eof-value aren't actually used...
(defun fread (*stream* &optional eof-error-p eof-value)
  "Like READ, but faster and accepting only a very limited syntax.
Called just like READ.
EOF-ERROR-P and EOF-VALUE aren't actually used -- we always get an error.
 This -is- meant to be a simple reader, after all."
  (declare (ignore eof-error-p eof-value))
  (cond ((not (variable-boundp *char-type-table*))
	 (setq *char-type-table* (make-array #o216))
	 (do ((ch 0 (1+ ch)))					;initialize to self
	     ((= ch #o216))
	   (setf (aref *char-type-table* ch) ch))
	 (do ((ch #/0 (1+ ch)))					;numbers
	     ((> ch #/9))
	   (setf (aref *char-type-table* ch) (minus ch)))
	 (dolist (ch '(#/( #/) #/. #// #/; #/' #/_ #/#))	;breaks
	   (setf (aref *char-type-table* ch) nil))
	 (dolist (ch '(#/sp #/tab #/lf #/vt #/ff #/return))	;white-space
	   (setf (aref *char-type-table* ch) t))
	 (do ((ch #/a (1+ ch)))
	     ((> ch #/z))
	   (setf (aref *char-type-table* ch) (- ch #o40)))
	 (setq *fread-string* (make-string #o200 :fill-pointer 0))))
  (setq *line-in-length* (length (setq *line-in* (send *stream* :line-in))))
  (setq *line-in-index* 0)
  (setq *unrchf* nil)
  (unwind-protect
      (fread-1)
    (return-array (prog1 *line-in* (setq *line-in* nil)))))


(defun fread-1 ()
  (prog (idx ob char char-type number-possible dec oct acc number-finished sign
	 digit-seen eof-flag)
	(setq idx -1 number-possible t dec 0 oct 0 sign 1)
     l00
	(setq char (fread-eat-whitespace))
     l0
	(cond ((not (numberp char-type))		;predicate true if not symbol constit.
	       (cond ((= char #/.)			;dot
		      (cond ((and number-possible (not (= idx -1)))
			     (setq oct dec)
			     (setq char-type #/.)	;can be symbol const
			     (setq number-finished t))	;error check
			    ;; legit dots read at read-list
			    (t (ferror nil "dot-context-error"))))
		     ((= char #/_)			;underline (old leftarrow)
		      (setq oct (ash oct (fread-1)))
		      (go x))
		     ((= char #// )			;slash
		      (setq number-possible nil)
		      (setq char-type (fread-tyi))
		      (go s))
		     ((> idx -1)
		      (setq *unrchf* char)		;in middle of something,
		      (go x))
		     ((= char #/()
		      (go read-list-start))
		     ((= char #/')
		      (return (list 'quote (fread-1))))
		     ((= char #/;)
		      (return-array (prog1 *line-in* (setq *line-in* nil)))
		      (setq *line-in-length*
			    (length (setq *line-in* (send *stream* :line-in))))
		      (setq *line-in-index* 0)
		      (go l00))
		     ((= char #/))
		      (ferror nil "unexpected close"))	;()
		     ((= char #/#)
		      (let ((values (si:invoke-reader-macro
				      (cdr (assq char (dont-optimize
							(si:rdtbl-macro-alist *readtable*))))
				'fread-stream)))
			(if values (return (car values))
			  (throw 'top-level-splicing t))))
		     (t (go l00))))			;flush it.
	     (number-possible 
	      (cond ((> char-type 0)			;true if not digit
		     (cond ((and (= char #/+) (null digit-seen)))
			   ((and (= char #/-) (null digit-seen))
			    (setq sign (minus sign)))
			   (t (setq number-possible nil))))
		    (t 
		     (cond (number-finished (ferror nil "no-floating-point")))
		     (setq digit-seen t)
		     (setq dec (+ (* 10. dec) (setq ob (- char #/0)))
			   oct (+ (* #o10 oct) ob))))))
     s  (setf (aref *fread-string* (incf idx)) (abs char-type))
	(setq char-type (aref *char-type-table* (setq char (fread-tyi t))))
	(go l0)
     read-list-start 
	(setq char (fread-eat-whitespace))
	(cond ((= char #/))				;close
	       (return nil))
	      ((= char #/;)				;Semi-colon
	       (return-array (prog1 *line-in* (setq *line-in* nil)))
	       (setq *line-in-length* (length (setq *line-in* (send *stream* :line-in))))
	       (setq *line-in-index* 0)
	       (go read-list-start)))
	(setq *unrchf* char)
     read-list
	(catch 'top-level-splicing
	  (push (fread-1) acc))
     read-list0
	(setq char (fread-eat-whitespace))
	(cond ((= char #/))				;close
	       (return (nreverse acc)))
	      ((= char #/;)				;Semi-colon
	       (return-array (prog1 *line-in* (setq *line-in* nil)))
	       (setq *line-in-length* (length (setq *line-in* (send *stream* :line-in))))
	       (setq *line-in-index* 0)
	       (go read-list0))
	      ((eq char #/.)
	       (setq ob (cons (car acc) (fread-1)))
	       (unless (= (setq char (fread-eat-whitespace)) #/) )
		 (ferror nil "dot-closing-error"))
	       (return ob)))
	(setq *unrchf* char)
	(go read-list)
     x  (cond ((and number-possible digit-seen)		; return it.
	       (return (* sign oct)))			; digit seen so it wins on +, -
	      (t (cond ((not (= idx -1))
			(setf (fill-pointer *fread-string*)  (1+ idx))
			(multiple-value-setq (ob oct)
			  (intern-soft *fread-string*))
			(unless oct
			  (setq ob (intern (let ((s (make-string (1+ idx))))
					     (copy-array-contents *fread-string* s)
					     s))))))
		 (return ob)))))


(defprop fread-stream t si:io-stream-p)
(defun fread-stream (operation &optional arg1 &rest rest &aux eof-flag)
  (case operation
    ((:tyi :read-char)
     (let ((ch (fread-tyi t)))			;preserve cr's so comments terminate!
       (if (eq operation :tyi) ch (int-char ch))))
    ((:untyi :unread-char)
     (setq *unrchf* (if (characterp arg1) (char-int arg1) arg1)))
    (:which-operations
     '(:tyi :read-char :untyi :unread-char))
    (t (stream-default-handler 'fread-stream operation arg1 rest))))
