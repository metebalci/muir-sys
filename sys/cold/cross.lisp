;;; -*- Mode:LISP; Package:COLD; Base:10; Lowercase:T; Readtable:ZL -*-

;;; The cross build: System 2000's band, on the machine it runs on, compiles
;;; SYSTEM for g2's 40-bit machine and writes that machine's cold load
;;; (contract g2, section 7, option (iii)).
;;;
;;; A plain reference to a system constant compiles to a read of its value
;;; cell, which the target's cold load fills with the target's value, so such
;;; code is right for the target as it stands.  This world's values reach the
;;; output only where this world evaluates while it compiles (measured while
;;; g2 was planned): folding constant expressions, #., the interpreter running
;;; a macro, an eval-when (compile) or a compiler-let, and the compiler's own
;;; encodings.
;;; Here one evaluator hook gives every interpreted evaluation of a system
;;; constant the target's value, from a table built from the cold-load
;;; generator's own parameters (load-parameters: QCOM, QDEFS, DEFMIC and the
;;; target's overlay, SYS: COLD; TARGET40), and a constant the table lacks
;;; stops the file's compile, so no value of this world is used unseen
;;; (fail-closed).  The compiler's encodings ask compiler:target-value
;;; (compiler:*cross-target*, sys: sys; qcdefs).
;;;
;;; What the hook cannot see is checked when the build begins: the tables
;;; compiled code reads (TYPEP's and EQ's optimizers put this world's data type
;;; numbers into code, from TYPE-OF-ALIST and TYPEP-ONE-ARG-ALIST), the misc
;;; instructions the compiler knows, and the fef, fasl and character formats
;;; the compiler and fasd write, all of which must be the target's.
;;;
;;; In a builder band, after SYSDCL, with this system's changed compiler files
;;; primed as docs/building.md says, and SYS: served from the tree to build:
;;;   (cold:cross-begin)		;the target's table, the checks, the hook
;;;   ... qc-file, make-system	;compile for the target
;;;   (cold:cross-make-cold "LOD3")	;the target's cold load
;;;   (cold:cross-end)
;;; Every compiled file's evaluations are logged, one file each, as
;;; cross-NNNN.txt in the log directory.

(defvar *cross-active* nil "T between CROSS-BEGIN and CROSS-END.")

(defvar *cross-table* nil
  "Hash table: a watched symbol of this world -> its value in the target.")

(defvar *cross-watch* nil
  "Hash table: every symbol whose interpreted evaluation takes the target's value or stops.")

(defvar *cross-changed* nil
  "The watched symbols whose target value differs from this world's.")

(defvar *cross-unset* nil
  "The watched symbols with no target value: evaluating one stops the compile.")

(defvar *cross-saved* nil
  "(name . original definition) of each function the cross build wraps.")

(defvar *cross-log-directory* "HOST: //home//lispm//")

(defvar *cross-fileno* 0 "The number of the last file logged.")

(defvar *cross-replaced-loads* nil
  "(40-bit QFASL . this world's QFASL of its source) for each load the build replaced.")

(defvar *cross-native* nil
  "True while the cross build compiles a file for this world (cross-host-fasl).")

(defvar *cross-host-fasls* nil
  "Hash table: a source file -> this world's QFASL of it, compiled in this session.")

;;; the tree's compile-time definitions.  a file compiled for the target expands
;;; a macro, or open-codes a defsubst, with the definition in force where it is
;;; compiled, and here that is this world's, system 2000's, unless the compile
;;; is given the tree's: so did qfasl's FASL-OP-NEW-FLOAT open-code system
;;; 2000's %short-float-exponent, (byte 8 17.), where the tree's is (byte 8
;;; 23.), since make-system loads the tree's NUMDEF only after the cold load's
;;; files are compiled.  SYS: COLD; CROSSDEFS, which
;;; tools/cross-check/crossdefs.py writes from the sources, lists every
;;; compile-time definition of the tree whose text is not system 2000's.
;;; cross-begin reads each from its file and evaluates it as the compiler does
;;; while it compiles a file, which declares it and defines nothing
;;; (undo-declarations-flag: a DEF entry of file-local-declarations); every file
;;; compiled for the target starts with those declarations, which the compiler
;;; consults before this world's definitions (si:declared-definition), and this
;;; world's function cells do not change.  an expansion of a listed name that
;;; finds no such declaration stops the file (cross-declared-definition).
(defvar *cross-definitions* nil
  "(file kind name status) for each compile-time definition of the tree that is not system 2000's.")

(defvar *cross-definition-names* nil
  "Hash table: each name in *cross-definitions* -> its status (:new, :changed, :gone).")

(defvar *cross-declarations* nil
  "The DEF declarations of the tree's definitions given to every compile for the target.")

(defvar *cross-compiling* nil
  "True while a file compiles for the target (cross-compile-stream).")

(defvar *cross-reading* nil
  "True while cross-begin reads the tree's definitions, which are read as for the target.")

(defvar *cross-made-constant* nil
  "The symbols cross-begin made system constants, which cross-end makes plain again.")

;;; Per compiled file.
(defvar *cross-file* nil)
(defvar *cross-lines* nil "This file's log lines, newest first.")
(defvar *cross-misses* nil "This file's watched symbols evaluated without a target value.")
(defvar *cross-context* nil "Where an evaluation happens: :fold, :sharp-dot or nil.")

;;;; The target's table

(defun cross-same (a b)
  "True if A, this world's value, and B, the target's, are the same; symbols by name,
since the target's are the cold-load generator's own."
  (cond ((and (numberp a) (numberp b)) (and (eq (type-of a) (type-of b)) (= a b)))
	((and (symbolp a) (symbolp b)) (string= (symbol-name a) (symbol-name b)))
	((and (stringp a) (stringp b)) (string= a b))
	((and (consp a) (consp b))
	 (and (cross-same (car a) (car b)) (cross-same (cdr a) (cdr b))))
	(t (eq a b))))

;;; symbol's target value is value: the same as this world's, or a number.  a
;;; changed value of another kind, a list of the target's symbols say, is left
;;; out, so that evaluating it stops the compile.
(defun cross-set (symbol value)
  (puthash symbol t *cross-watch*)
  (let ((here (and (boundp symbol) (symeval symbol))))
    (cond ((cross-same here value)
	   (puthash symbol here *cross-table*))
	  ((numberp value)
	   (puthash symbol value *cross-table*)
	   (push symbol *cross-changed*))
	  (t (push symbol *cross-unset*)))))

(defun cross-watch-only (symbol)
  (puthash symbol t *cross-watch*)
  (push symbol *cross-unset*))

;;; the cold-load generator's symbol for this world's symbol, if it has a value
(defun cross-cold-symbol (symbol)
  (let ((cold (intern-soft (symbol-name symbol) sym-package)))
    (and cold
	 (eq (symbol-package cold) sym-package)
	 (boundp cold)
	 cold)))

;;; the variables a scan of the sources found defined from system constants,
;;; which code run at compile time could read: the two tables (sys: sys; types)
;;; hold data type numbers, the same in the target while cross-check-data-types
;;; passes; the others are watched with no value.
(defconst cross-derived-tables '(si:type-of-alist si:typep-one-arg-alist))

(defconst cross-derived-variables
	  '("SHIFT-ARRAY-PORTION-BUFFER" "GRID-BITBLT-KLUDGE" "GRID-BITBLT-ONES"
	    "*ALL-SUBNET-BIT-MAP*" "ROUTING-TABLE-TYPE" "FILL-UP-REGION-ARRAY"
	    "%%FSM-CHAR" "PAGE-RQB-SIZE" "PAGE-RQB" "QREVERSE-DUMMY-ARRAY-HEADER"
	    "%FILE-DEVICE-NAME-PAGE-BYTES")
  "Their names: the symbols are in several packages.")

;;; every package's own symbol of this name
(defun cross-symbols-named (name)
  (let ((out nil))
    (dolist (pkg *all-packages*)
      (let ((s (intern-soft name pkg)))
	(when (and s (eq (symbol-package s) pkg))
	  (pushnew s out))))
    out))

(defun cross-build-table ()
  (setq *cross-table* (make-hash-table :test 'eq :size 3000)
	*cross-watch* (make-hash-table :test 'eq :size 3000)
	*cross-changed* nil
	*cross-unset* nil)
  ;; the area names' values are their numbers, which make-cold-1 assigns first
  ;; in the same way
  (assign-values sym:area-list 0)
  (let ((pending nil))
    ;; this world's system constants, from the target's parameters where they
    ;; define them
    (dolist (pkg *all-packages*)
      (mapatoms #'(lambda (s)
		    (when (and (eq (symbol-package s) pkg)
			       (get s 'si:system-constant)
			       (not (memq s '(t nil))))
		      (let ((cold (cross-cold-symbol s)))
			(if cold
			    (cross-set s (symeval cold))
			  (push s pending)))))
		pkg nil))
    ;; the parameters' other variables that this world also has (the lists
    ;; QCOM and QDEFS define, such as Q-DATA-TYPES and AREA-LIST)
    (mapatoms #'(lambda (cold)
		  (when (and (eq (symbol-package cold) sym-package) (boundp cold))
		    (let ((s (intern-soft (symbol-name cold) (pkg-find-package "SI"))))
		      (when (and s (boundp s) (not (gethash s *cross-watch*))
				 (not (memq s '(t nil))))
			(cross-set s (symeval cold))))))
	      sym-package nil)
    ;; the fixnum's range, from the target's pointer field (load-parameters)
    (cross-set 'most-positive-fixnum big-fixnum)
    (cross-set 'most-negative-fixnum little-fixnum)
    (dolist (s cross-derived-tables) (cross-set s (symeval s)))
    (dolist (name cross-derived-variables)
      (dolist (s (cross-symbols-named name))
	(unless (gethash s *cross-watch*) (cross-watch-only s))))
    ;; the constants the parameters do not define, from their defining files in
    ;; the tree being built
    (cross-read-defining-files pending)
    ;; the target's system constants that are not this world's
    (cross-declare-target-constants)))

;;; every symbol of the target's system-constant lists (qdefs) is a system
;;; constant in the target, which a native compile folds; one that is not
;;; this world's (disk-blocks-per-page, which this tree adds) was compiled as a
;;; variable.  each is given its target value and made a system constant here
;;; until cross-end (*cross-made-constant*).
(defun cross-declare-target-constants ()
  (dolist (l sym:system-constant-lists)
    (dolist (cold (symeval l))
      (when (and (symbolp cold) (boundp cold) (not (memq cold '(t nil))))
	(let ((s (intern (symbol-name cold) (pkg-find-package "SI"))))
	  (unless (gethash s *cross-watch*)
	    (cross-set s (symeval cold)))
	  (unless (get s 'si:system-constant)
	    (putprop s t 'si:system-constant)
	    (push s *cross-made-constant*)))))))

;;; for each constant, the DEFCONSTANT of it in the file this world recorded it
;;; from, read from the tree being built and evaluated under the hook, so that
;;; a form that uses another constant uses the target's.  a constant whose
;;; DEFCONSTANT is not found has no target value.
(defun cross-read-defining-files (symbols)
  (let ((files nil))
    (dolist (s symbols)
      (let* ((file (si:get-source-file-name s 'defvar))
	     (entry (and file (assq file files))))
	(cond ((null file) (cross-watch-only s))
	      (entry (push s (cdr entry)))
	      (t (push (list file s) files)))))
    (let ((forms nil))
      (dolist (entry files)
	(setq forms (nconc forms (cross-defconstants (car entry) (cdr entry)))))
      ;; a form may use a constant defined in a later file: go round until
      ;; nothing more can be evaluated
      (do ((left forms) (progress t)) ((or (null left) (not progress))
				      (dolist (f left) (cross-watch-only (car f))))
	(setq progress nil)
	(dolist (f (prog1 left (setq left nil)))
	  (let ((*cross-misses* nil))
	    (multiple-value-bind (value error)
		(catch-error (let ((*evalhook* 'cross-evalhook))
			       (eval (cadr f)))
			     nil)
	      (if (or error *cross-misses*)
		  (push f left)
		(setq progress t)
		(cross-set (car f) value)))))))))

;;; the (symbol form) of each DEFCONSTANT of SYMBOLS in FILE, read with the
;;; file's own attributes (package, base, readtable)
(defun cross-defconstants (file symbols)
  (let ((found nil))
    (with-open-file (stream (send file :new-pathname :type :lisp :version :newest))
      (let ((generic (send (send stream :pathname) :generic-pathname)))
	(fs:read-attribute-list generic stream)
	(multiple-value-bind (vars vals) (fs:file-attribute-bindings generic)
	  (progv vars vals
	    (do ((eof (ncons nil))
		 (form))
		((eq (setq form (read stream eof)) eof))
	      (cross-find-defconstants form symbols #'(lambda (s f) (push (list s f) found))))))))
    (dolist (s symbols)
      (unless (assq s found) (cross-watch-only s)))
    (nreverse found)))

(defun cross-find-defconstants (form symbols fn)
  (when (consp form)
    (cond ((and (memq (car form) '(defconstant defconst defparameter))
		(memq (cadr form) symbols))
	   (funcall fn (cadr form) (caddr form)))
	  ((memq (car form) '(progn eval-when))
	   (dolist (f (if (eq (car form) 'eval-when) (cddr form) (cdr form)))
	     (cross-find-defconstants f symbols fn))))))

;;;; What the hook cannot see, checked once

;;; TYPEP's and EQ's optimizers compile this world's data type numbers into
;;; code (TYPE-OF-ALIST, TYPEP-ONE-ARG-ALIST, sys: sys; types): right for the
;;; target only if every data type keeps its number (appendix a1.14).
(defun cross-check-data-types ()
  (let ((bad nil))
    (dolist (cold sym:q-data-types)
      (let ((s (intern-soft (symbol-name cold) (pkg-find-package "SI"))))
	(unless (and s (boundp s) (eql (symeval s) (symeval cold)))
	  (push (list cold (symeval cold) (and s (boundp s) (symeval s))) bad))))
    (dolist (s si:q-data-types)
      (unless (memq (intern-soft (symbol-name s) sym-package) sym:q-data-types)
	(push (list s nil (symeval s)) bad)))
    (when bad
      (ferror nil "The target's data types are not this world's (type, target, here): ~S" bad))
    t))

;;; the compiler compiles a call to a misc instruction by the opcode this world
;;; knows; each of the target's (DEFMIC) must be known with the same opcode, or
;;; primed first (docs/building.md, Priming the builder).
(defun cross-check-misc-instructions ()
  (let ((bad nil))
    (dolist (cold misc-instruction-list)
      (let* ((op (get cold 'sym:qlval))
	     (s (or (intern-soft (symbol-name cold) (pkg-find-package "SI"))
		    (intern-soft (symbol-name cold) (pkg-find-package "COMPILER"))))
	     (here (and s (get s 'compiler:qlval))))
	(unless (eql op here)
	  (push (list cold op here) bad))))
    (when bad
      (ferror nil "The compiler's misc instructions are not the target's (name, target, here): ~S"
	      bad))
    t))

;;; the compiler writes fefs, fasl groups and characters in this world's
;;; formats; the target's must be the same (g2 keeps the fef and fasl formats,
;;; and today's characters, g2 7.1).
(defconst cross-same-lists
	  '(si:fasl-group-fields si:fasl-ops si:fasl-table-parameters si:fasl-constants
	    si:fefhi-indexes si:fefhi-fields si:fefh-constants si:fef-arg-syntax si:fef-des-dt
	    si:fef-functional si:fef-init-option si:fef-name-present si:fef-quote-status
	    si:fef-specialness si:arg-desc-fields si:numeric-arg-desc-fields si:adi-kinds
	    si:adi-storing-options si:adi-fields si:header-fields si:q-header-types
	    si:array-types si:array-fields si:array-leader-fields si:array-miscs))

(defconst cross-same-symbols
	  '(si:%%q-high-half si:%%q-low-half si:%%ch-font si:%%ch-char si:%%kbd-char
	    si:%%kbd-control-meta si:%%kbd-control si:%%kbd-meta si:%%kbd-super si:%%kbd-hyper
	    si:%%kbd-mouse si:%%kbd-mouse-button si:%%kbd-mouse-n-clicks
	    si:%%byte-specifier-position si:%%byte-specifier-size))

;; the flag an adi word's cdr code holds (contract g1 2.2: the cdr code keeps
;; its other uses, the adi flags), which moves with the cdr code to bit 38 of
;; a 40-bit word.  the microcode sets and tests it, and the error handler
;; reads it by name; neither the compiler nor the fasl format holds it.
(defconst cross-format-exceptions '(si:%%adi-previous-adi-flag))

(defun cross-check-formats ()
  (let ((bad nil))
    ;; a constant this world has no value for (QCOM's FEF-DES-DT, for one) is
    ;; in none of its code, so only the others are compared
    (flet ((check (s)
	     (let ((cold (cross-cold-symbol s)))
	       (when (and (boundp s)
			  (not (memq s cross-format-exceptions))
			  (not (and cold (cross-same (symeval s) (symeval cold)))))
		 (push (list s (and cold (symeval cold)) (symeval s)) bad)))))
      (dolist (list cross-same-lists)
	(check list)
	(dolist (s (symeval list)) (check s)))
      (dolist (s cross-same-symbols) (check s)))
    (when bad
      (ferror nil "The target's fef, fasl or character formats are not this world's (name, target, here): ~S"
	      bad))
    t))

;;;; The hook and the log

(defun cross-evalhook (form env)
  (if (and (symbolp form) (gethash form *cross-watch*))
      (cross-read form)
    (evalhook form #'cross-evalhook nil env)))

(defun cross-read (symbol)
  (multiple-value-bind (value found) (gethash symbol *cross-table*)
    (cond (found
	   (cross-note "R" (or *cross-context* :eval) symbol value
		       (if (boundp symbol) (symeval symbol) :unbound) (cross-function))
	   value)
	  (t
	   (push (cons symbol (or *cross-context* :eval)) *cross-misses*)
	   (cross-note "M" (or *cross-context* :eval) symbol (cross-function))
	   (ferror nil "The cross build has no target value for ~S" symbol)))))

;;; compiler:*cross-target*'s function
(defun cross-target-value (symbol)
  (multiple-value-bind (value found) (gethash symbol *cross-table*)
    (if found
	value
      (ferror nil "The cross build has no target value for ~S" symbol))))

(defun cross-function ()
  (if (boundp 'compiler:function-to-be-defined) compiler:function-to-be-defined :none))

(defun cross-clean (string)
  (dotimes (i (string-length string))
    (when (memq (aref string i) '(#\return #\tab #\line #\page))
      (aset #\space string i)))
  string)

(defun cross-string (x)
  (let ((*print-base* 10.) (*read-base* 10.) (*nopoint t) (*print-radix* nil)
	(*print-level* 12.) (*print-length* 60.)
	(*package* (pkg-find-package "KEYWORD")))
    (cross-clean (format nil "~S" x))))

(defun cross-note (kind &rest fields)
  (push (format nil "~A~{	~A~}" kind (mapcar #'cross-string fields)) *cross-lines*))

(defun cross-write-log (status)
  (incf *cross-fileno*)
  (with-open-file (s (format nil "~Across-~4,'0D.txt" *cross-log-directory* *cross-fileno*)
		     :direction :output)
    (format s "F	~A~%" (cross-string *cross-file*))
    (dolist (l (reverse *cross-lines*)) (format s "~A~%" l))
    (format s "E	~A	~A~%" (cross-string *cross-file*) status)))

;;;; The wrappers

(defun cross-wrap (name new)
  (unless (assq name *cross-saved*)
    (push (cons name (fdefinition name)) *cross-saved*))
  (fset name new))

(defun cross-original (name)
  (cdr (assq name *cross-saved*)))

;;; one file's compile: the hook on, a compiler error an error, and the file
;;; refused (its qfasl aborted) if a watched symbol had no target value
(defun cross-compile-stream (input-stream generic-pathname &rest more)
  (if *cross-native*
;      (apply (cross-original 'compiler:compile-stream) input-stream generic-pathname more)
      ;; a compile for this world, also one inside a compile for the target, is
      ;; not checked against the tree's definitions
      (let ((*cross-compiling* nil))
	(apply (cross-original 'compiler:compile-stream) input-stream generic-pathname more))
  (let ((*cross-file* (or (send input-stream :send-if-handles :truename) generic-pathname))
	(*cross-lines* nil)
	(*cross-misses* nil)
	(status :aborted))
    (unwind-protect
;	(prog1 (let ((compiler:warn-on-errors nil)
;		     (*evalhook* 'cross-evalhook))
;		 (apply (cross-original 'compiler:compile-stream)
;			input-stream generic-pathname more))
	;; the file starts with the tree's definitions declared
	;; (*cross-declarations*): compile-stream's sixth optional argument,
	;; after fasd-flag, process-fn, qc-file-load-flag, qc-file-in-core-flag
	;; and package-spec, is file-local-declarations' initial value
	(prog1 (let ((compiler:warn-on-errors nil)
		     (*evalhook* 'cross-evalhook)
		     (*cross-compiling* t)
		     (args (copy-list more)))
		 (when *cross-declarations*
		   (loop while (< (length args) 6) do (setq args (nconc args (list nil))))
		   (rplaca (nthcdr 5 args) (append (nth 5 args) *cross-declarations*)))
		 (apply (cross-original 'compiler:compile-stream)
			input-stream generic-pathname args))
	       (when *cross-misses*
		 (setq status :no-target-value)
		 (ferror nil "~A: no target value for ~S" *cross-file*
			 (mapcar #'car *cross-misses*)))
	       (setq status :ok))
      (cross-write-log status)))))

(defun cross-fold-constants (form)
  (if *cross-native*
      (funcall (cross-original 'compiler:fold-constants) form)
    (let ((value (let ((*cross-context* :fold))
		   (funcall (cross-original 'compiler:fold-constants) form))))
      ;; its floats as the target holds them (cross-target-float)
      (when (compiler:target-one-float-p)
	(setq value (cross-target-float value)))
      (cross-note "X" (cross-function) form value)
      value)))

;;; an lsh or rot of constants that the cross build leaves to the target
;;; (compiler:arith-opt-non-associative), logged: its code differs from a
;;; native compile's
(defun cross-arith-opt-non-associative (form)
  (let ((new (funcall (cross-original 'compiler:arith-opt-non-associative) form)))
    (when (and (not *cross-native*)
	       (eq new form)
	       (memq (car-safe form) '(lsh rot))
	       (loop for arg in (cdr form) always (constantp arg)))
      (cross-note "L" (cross-function) form))
    new))

;;; a float literal read for the target is this world's full single, which is
;;; dumped rounded to the target's ieee single (compiler:float-to-binary32).
;;; read as this world's short float, system 2000's small flonum, a literal such
;;; as 1.3s0 kept 17 bits of significand: hash's was dumped as #x3FA66680, where
;;; a native compile has #x3FA66666.
;;; a target whose floats are this world's (check 1's identity control) reads
;;; them as this world does (compiler:target-one-float-p)
;;; the literal is read as the target reads it: the tree's own exact reading,
;;; si:xr-float-bits (sys: io; read), which cross-begin defines here
;;; (cross-define-reader), gives the single's bits.  through this world's reader,
;;; 12 digits and its own rounding, then rounded again to the target's single,
;;; 1.00000005960464477539062500001 was #x3F800000, not #x3F800001.
(defun cross-read-flonum (string sfl-p)
  (if (and (not *cross-native*) (or *cross-compiling* *cross-reading*)
	   (compiler:target-one-float-p))
;      (cross-target-float (funcall (cross-original 'si:xr-read-flonum) string nil))
      (multiple-value-bind (bits negative) (si:xr-float-bits string)
	(when (eq bits :underflow)
	  (ferror nil "~A is below the smallest normal single: it underflows in the target" string))
	(let ((x (binary32-to-float bits)))
	  (if negative (- x) x)))
    (funcall (cross-original 'si:xr-read-flonum) string sfl-p)))

;;; the tree's exact float reading, si:xr-float-bits and the function it calls,
;;; read from SYS: IO; READ and compiled here (new names in this world, which
;;; change nothing of its own reader)
(defvar *cross-reader-functions* '(si:xr-float-bits si:xr-decimal-to-single-bits))

(defun cross-define-reader ()
  (with-open-file (s "SYS: IO; READ LISP")
    (multiple-value-bind (vars vals) (fs:extract-attribute-bindings s)
      (progv vars vals
	(loop with eof = s
	      ;; zetalisp's read: the second argument is what end of file returns
	      for form = (read s eof)
	      until (eq form eof)
	      when (and (consp form) (eq (car form) 'defun)
			(memq (cadr form) *cross-reader-functions*))
		do (let ((si:inhibit-fdefine-warnings :just-warn)
			 ;; compiled for this world, as cross-host-fasl compiles
			 (*cross-native* t)
			 (compiler:*cross-target* nil))
		     (eval form)
		     (compile (cadr form)))))))
  (dolist (f *cross-reader-functions*)
    (unless (fboundp f)
      (ferror nil "SYS: IO; READ defines no ~S" f)))
  t)

;;; X with each float rounded to the target's ieee single, kept as this world's
;;; full single: two literals that are one float in the target (1.442695s0 and
;;; 1.44269504) are then one constant here too, as the compiler shares them in a
;;; native compile, and a fold or a #. gives the value the target holds.
(defun cross-target-float (x)
  (cond ((and (floatp x) (not (small-floatp x)))
	 (binary32-to-float (compiler:float-to-binary32 x)))
	((consp x)
	 (let ((a (cross-target-float (car x))) (d (cross-target-float (cdr x))))
	   (if (and (eq a (car x)) (eq d (cdr x))) x (cons a d))))
	(t x)))

;;; #., as si:xr-#.-macro reads it, with the form and its value logged
(defun cross-sharp-dot (stream ignore &optional ignore)
  (values (if *read-suppress*
	      (progn (si:internal-read stream t nil t) nil)
	    (let* ((form (si:internal-read stream t nil t))
		   (value (let ((*cross-context* :sharp-dot))
			    (si:eval1 form))))
	      ;; its floats as the target holds them (cross-target-float)
	      (when (and *cross-compiling* (compiler:target-one-float-p))
		(setq value (cross-target-float value)))
	      (unless *cross-native*
		(cross-note "S" form value))
	      value))))

;;; a file compiled for the target is never loaded into this world.  where
;;; make-system loads one (the definition files of what it compiles, such as
;;; SYSTEM's ALLDEFS and ZWEI's modules), this world loads its own compile of the
;;; same source instead, so that what the rest of the compile sees is what a
;;; native build's would: the definitions of the tree being built, with this
;;; world's values, and not this world's own, which would keep a macro or a
;;; structure the tree has changed.
;;;
;;; but a file of *cross-unloaded-files* is not loaded at all: SYS2; NUMDEF
;;; redefines this world's float functions for the target's floats, and the
;;; compile's own evaluations then went wrong (colorhack's (sqrt 2), folded
;;; after it was loaded, became an infinity).  its defsubsts reach the compile
;;; as declarations (cross-declare-definitions) and its constants through the
;;; table, as the target's.
(defvar *cross-unloaded-files* '("SYS: SYS2; NUMDEF")
  "The tree's files make-system would load that the cross build does not load into this world.")

(defun cross-unloaded-file-p (pathname)
  (dolist (f *cross-unloaded-files*)
    (let ((u (fs:parse-pathname f)))
      (when (and (string-equal (send u :name) (send pathname :name))
		 (equal (send u :directory) (send pathname :directory))
		 (eq (send u :host) (send pathname :host)))
	(return t)))))

(defun cross-fasload-internal (fasl-stream pkg no-msg-p)
  (let ((file (send fasl-stream :truename)))
;    (cond ((not (cross-marked-file-p file))
    (cond ((not (cross-foreign-file-p file))
	   (funcall (cross-original 'si:fasload-internal) fasl-stream pkg no-msg-p))
	  ((cross-unloaded-file-p (send fasl-stream :pathname))
	   (push (cons file :not-loaded) *cross-replaced-loads*)
	   (send fasl-stream :pathname))
	  (t (let ((host (cross-host-fasl (send fasl-stream :pathname))))
	       (push (cons file host) *cross-replaced-loads*)
	       (let ((si:inhibit-fdefine-warnings :just-warn))
		 (load host pkg)))
	     (send fasl-stream :pathname)))))

;;; true if FILE's attribute list names a word width, which only a file compiled
;;; for a word other than this world's 32 bits does (compiler:fasd-attributes-
;;; list): the name WORD-WIDTH is among its first bytes.  read as bytes because
;;; reading the attribute list as the fasloader does (si:qfasl-file-plist)
;;; before a load was measured to change what the load does: after it, a
;;; compile of SYS: FILE; LMPARS no longer wrote LM-PATHNAME's combined :SET
;;; method, as a native one does.
(defun cross-marked-file-p (file)
  (with-open-file (stream file :direction :input :characters nil :byte-size 8.)
    (let ((head (make-array 64. :type 'art-string :fill-pointer 0)))
      (dotimes (i 64.)
	(let ((byte (send stream :tyi)))
	  (if byte (vector-push byte head) (return))))
      (string-search "WORD-WIDTH" head))))

;;; true if FILE was compiled for a target that this world cannot run: a file
;;; that names a word width, or, when the target's page is not this world's,
;;; any file with a source beside it.  a 32-bit target of 1024-word pages
;;; (contract g2, option (w)) marks nothing, but folds its page into its code
;;; and reads its disk-blocks-per-page: loaded here for SYSTEM's host-file-io,
;;; its SYS: IO; FDEV stopped this world at an illop in %find-structure-header,
;;; while this world's own compile of the same source loads and runs.  a file
;;; with no source, such as a font, is data and is loaded as it is.
(defun cross-foreign-file-p (file)
  (or (cross-marked-file-p file)
      (and (not (= sym:page-size si:page-size))
	   (probe-file (send file :new-pathname :type :lisp :version :newest))
	   t)))

;;; this world's QFASL of the source of FASL, compiled once in a session, with
;;; the cross build off (no hook, this world's values, no log)
(defun cross-host-fasl (fasl)
  (let* ((source (send fasl :new-pathname :type :lisp :version :newest))
	 (key (send source :string-for-printing)))
    (or (gethash key *cross-host-fasls*)
	(let ((out (cross-host-fasl-name source)))
	  (let ((*cross-native* t)
		(*evalhook* nil)
		(compiler:*cross-target* nil))
	    (qc-file source out))
	  (puthash key out *cross-host-fasls*)
	  out))))

;;; HOST: //home//lispm//hq-zwei-defs.qfasl for SYS: ZWEI; DEFS LISP, apart
;;; from the tree, whose QFASLs are the target's
(defun cross-host-fasl-name (source)
  (let ((dir (send source :directory)))
    (string-downcase
      (format nil "~Ahq-~{~A-~}~A.qfasl" *cross-log-directory*
	      (if (listp dir) dir (list dir)) (send source :name)))))

;;;; Beginning and end

;(defun cross-begin (&key (overlays '("SYS: COLD; TARGET40 LISP"))
;		    (check-data-types t) (check-misc-instructions t) (check-formats t)
;		    (log-directory *cross-log-directory*))
;  "Load the target's parameters, check what the hook cannot see, and turn the cross build on.
;OVERLAYS are loaded over QCOM, QDEFS and DEFMIC; NIL gives this tree's own parameters."
;;; definitions: the tree's compile-time definitions (cross-declare-definitions)
(defun cross-begin (&key (overlays '("SYS: COLD; TARGET40 LISP"))
		    (check-data-types t) (check-misc-instructions t) (check-formats t)
		    (log-directory *cross-log-directory*)
		    (definitions t))
  "Load the target's parameters, check what the hook cannot see, and turn the cross build on.
OVERLAYS are loaded over QCOM, QDEFS and DEFMIC; NIL gives this tree's own parameters.
DEFINITIONS: T gives every compile for the target the tree's compile-time definitions
that SYS: COLD; CROSSDEFS lists, NIL none (this world's own target), (:OMIT FILE...)
all but FILEs'."
  (when *cross-active* (cross-end))
  (setq *cross-log-directory* log-directory)
  ;; the parameters afresh: a value an earlier overlay or cold load left in the
  ;; cold-load package would otherwise stay in the table
  (mapatoms #'(lambda (s) (when (eq (symbol-package s) sym-package) (makunbound s)))
	    sym-package nil)
  (setq cold-load-overlays overlays)
  (load-parameters)
  (cross-build-table)
  (when check-data-types (cross-check-data-types))
  (when check-misc-instructions (cross-check-misc-instructions))
  (when check-formats (cross-check-formats))
  (setq *cross-replaced-loads* nil
	*cross-host-fasls* (make-hash-table :test 'equal))
  (setq *cross-saved* nil)
  (cross-wrap 'compiler:compile-stream #'cross-compile-stream)
  (cross-wrap 'compiler:fold-constants #'cross-fold-constants)
  (cross-wrap 'compiler:arith-opt-non-associative #'cross-arith-opt-non-associative)
  (cross-wrap 'si:xr-#.-macro #'cross-sharp-dot)
  (cross-wrap 'si:fasload-internal #'cross-fasload-internal)
  (cross-wrap 'si:declared-definition #'cross-declared-definition)
  (cross-wrap 'si:xr-read-flonum #'cross-read-flonum)
  (setq compiler:*cross-target* 'cross-target-value
	*cross-active* t)
  ;; the tree's exact float reading, for a target whose float is the single
  (when (compiler:target-one-float-p)
    (cross-define-reader))
  ;; the tree's compile-time definitions, as declarations (*cross-definitions*)
  (cross-declare-definitions definitions)
;  (list :word-bits word-bits :page-size sym:page-size
;	:watched (cross-count *cross-watch*) :changed (length *cross-changed*)
;	:without-value (length *cross-unset*)))
  (list :word-bits word-bits :page-size sym:page-size
	:watched (cross-count *cross-watch*) :changed (length *cross-changed*)
	:without-value (length *cross-unset*)
	:definitions (length *cross-declarations*)
	:checked (if *cross-definition-names* (cross-count *cross-definition-names*) 0)))

;;; DEFINITIONS: t, every definition SYS: COLD; CROSSDEFS lists; nil, none and
;;; no check (this world's own target, the identity control); or (:omit FILE...),
;;; every one but those of FILEs, all still checked (the check's control)
(defun cross-declare-definitions (definitions)
  (setq *cross-declarations* nil
	*cross-definition-names* nil)
  (when definitions
    (let ((si:inhibit-fdefine-warnings :just-warn))
      (load "SYS: COLD; CROSSDEFS LISP" "COLD"))
    (setq *cross-definition-names* (make-hash-table :test 'eq))
    (let ((omit (and (consp definitions) (eq (car definitions) :omit) (cdr definitions)))
	  (files nil))
      ;; a structure or a setf method evaluated so still changes this world
      ;; (DEFSTRUCT redefines the structure here): such a changed definition
      ;; stops the cross build until it is given another way
      (dolist (d *cross-definitions*)
	(unless (or (eq (fourth d) :gone) (cross-checked-kind-p (second d)))
	  (ferror nil "The cross build cannot give the tree's ~A ~A (~A) without changing this world"
		  (second d) (third d) (first d))))
      (dolist (d *cross-definitions*)
	(let* ((file (first d)) (name (third d)) (status (fourth d))
	       (wanted (and (neq status :gone)
			    (not (mem #'string-equal file omit))))
	       (entry (ass #'string-equal file files)))
	  (unless entry
	    (push (setq entry (list file)) files))
	  (push (list name wanted (second d)) (cdr entry))))
      (dolist (entry files)
	(cross-declare-file (car entry) (cdr entry)))))
  (length *cross-declarations*))

;;; FILE's definitions named in NAMES ((name-string wanted kind) ...): each read with
;;; the file's attributes; a wanted one evaluated as the compiler evaluates it,
;;; into a declaration; every one's symbol put in *cross-definition-names*
(defun cross-declare-file (file names)
  (with-open-file (s file)
    (multiple-value-bind (vars vals) (fs:extract-attribute-bindings s)
      (progv vars vals
	(loop with eof = s
	      ;; zetalisp's read: the second argument is what end of file returns
	      for form = (let ((*cross-reading* t)) (read s eof))
	      until (eq form eof)
	      do (dolist (def (cross-definition-forms form))
		   (let* ((name (cross-definition-name def))
			  (entry (and name (ass #'string= (symbol-name name) names))))
		     (when entry
		       (when (cross-checked-kind-p (third entry))
			 (puthash name t *cross-definition-names*))
		       (when (second entry)
			 ;; as inside a compile: functions-referenced is what macro and
			 ;; defsubst-1 look at when undo-declarations-flag is set
			 (let ((sys:undo-declarations-flag t)
			       (sys:file-local-declarations nil)
			       (compiler:functions-referenced nil)
			       (si:inhibit-fdefine-warnings :just-warn))
			   (eval def)
			   (setq *cross-declarations*
				 (append sys:file-local-declarations *cross-declarations*))))))))))
    ;; a listed name the file no longer defines, or that is gone, is checked too
    (dolist (entry names)
      (let ((sym (and (cross-checked-kind-p (third entry))
		      (cross-definition-symbol file (car entry)))))
	(when sym (puthash sym t *cross-definition-names*))))))

;;; the kinds of definition that define a symbol's own function, which the
;;; compiler finds through si:declared-definition: a defsetf or a setf method
;;; defines the setf of its name, and a structure's accessors are its own
;;; definitions, so neither is checked by its name
(defun cross-checked-kind-p (kind)
  (memq kind '(defmacro defsubst macro deff-macro deflambda-macro defmacro-displace)))

;;; the definitions in a top-level FORM, through the forms that hold others
(defun cross-definition-forms (form)
  (cond ((atom form) nil)
	((memq (car form) '(defmacro defsubst defsetf define-setf-method defstruct deff-macro
			    deflambda-macro macro define-modify-macro defmacro-displace))
	 (list form))
	((memq (car form) '(eval-when local-declare compiler-let))
	 (mapcan #'cross-definition-forms (cddr form)))
	((memq (car form) '(progn si:loop-macro-progn))
	 (mapcan #'cross-definition-forms (cdr form)))))

;;; a symbol, or a structure's name; a function spec such as (and
;;; alternate-macro-definition) names no symbol's own definition: nil
(defun cross-definition-name (form)
  (let ((x (cadr form)))
    (cond ((symbolp x) x)
	  ((eq (car form) 'defstruct) (car x)))))

;;; the symbol NAME names in FILE's package, if it exists
(defun cross-definition-symbol (file name)
  (let ((pkg (with-open-file (s file)
	       (let ((attrs (fs:extract-attribute-list s)))
		 (getf attrs :package)))))
    (and pkg (pkg-find-package pkg :find)
	 (intern-soft name (pkg-find-package pkg)))))

;;; si:declared-definition, checked: while a file compiles for the target, a name
;;; the tree defines (*cross-definition-names*) must be declared, by the tree's
;;; definition given at cross-begin or by the file's own; else it would expand,
;;; or be compiled as a call, by this world's definition, and the file stops
(defun cross-declared-definition (function-spec)
  (when (and *cross-compiling* *cross-definition-names*
	     (symbolp function-spec)
	     (gethash function-spec *cross-definition-names*)
	     (not (cross-declared-p function-spec)))
    (cross-note "D" (cross-function) function-spec)
    ;; also refused after the compile (cross-compile-stream), should a handler
    ;; of the compiler's take this error
    (push (cons function-spec :definition) *cross-misses*)
    (ferror nil "~S would expand with this world's definition, not the tree's" function-spec))
  (funcall (cross-original 'si:declared-definition) function-spec))

(defun cross-declared-p (function-spec)
  (flet ((has (list) (dolist (l list) (and (eq (car-safe l) 'def) (equal (cadr l) function-spec)
					     (return t)))))
    (or (has local-declarations) (has sys:file-local-declarations))))

(defun cross-end ()
  "Turn the cross build off: this world's own values again."
  (dolist (s *cross-saved*) (fset (car s) (cdr s)))
  ;; the target's system constants that are not this world's
  (dolist (s *cross-made-constant*) (remprop s 'si:system-constant))
  (setq *cross-made-constant* nil)
  (setq *cross-saved* nil
	compiler:*cross-target* nil
	*cross-active* nil)
  t)

(defun cross-count (table)
  (let ((n 0))
    (maphash #'(lambda (ignore ignore) (incf n)) table)
    n))

;;; the table, for the log: symbol, target value, this world's value
(defun cross-write-table (&optional (file (string-append *cross-log-directory* "cross-table.txt")))
  (with-open-file (s file :direction :output)
    (maphash #'(lambda (sym value)
		 (format s "T	~A	~A	~A~%" (cross-string sym) (cross-string value)
			 (cross-string (if (boundp sym) (symeval sym) :unbound))))
	     *cross-table*)
    (dolist (sym *cross-unset*)
      (format s "U	~A	~A~%" (cross-string sym)
	      (cross-string (if (boundp sym) (symeval sym) :unbound)))))
  (list :table (cross-count *cross-table*) :unset (length *cross-unset*)))

;;;; Compiling SYSTEM, and the cold load

(defun cross-compile-system (&optional (output (string-append *cross-log-directory*
							      "cross-compile.txt")))
  "Compile SYSTEM for the target, into the tree's QFASLs; the compiler's output to OUTPUT."
  (with-open-file (out output :direction :output)
    (let ((standard-output out) (error-output out))
      (let ((si:inhibit-fdefine-warnings :just-warn))
	(make-system 'system :compile :noload :noconfirm :nowarn :no-increment-patch))))
  (list :files *cross-fileno* :loads-replaced (length *cross-replaced-loads*)))

(defun cross-make-cold (part-name)
  "Write the target's cold load into the partition PART-NAME, answering its question."
  (let ((old (symbol-function 'fquery)))
    (unwind-protect
	(progn (fset 'fquery #'(lambda (&rest ignore) t))
	       (make-cold part-name))
      (fset 'fquery old)))
  (list :word-bits word-bits :page-size sym:page-size :blocks-per-page blocks-per-page
	:highest-address vmem-highest-address
	:nil qnil :t qtruth))

;;; a file that sets SYMBOL to a value, for the target: the cold load's font,
;;; SYS: FONTS; CPTFON, which COLD-LOAD-FILE-LIST names and which the tree holds
;;; only as a 32-bit file.  the value is the one that file sets, loaded here with
;;; SYMBOL bound so that this world's own font does not change (the world's
;;; CPTFONT is a larger font than the cold load's), and it is written as that
;;; file writes it, stored into the symbol's value cell, which the cold-load
;;; generator reads (compiler:fasd-symbol-value writes an evaluation, which it
;;; does not).
(defun cross-redump-value-file (file symbol)
  (progv (list symbol) (list nil)
    ;; in USER: such a file has no attribute list, and its NIL must be global's
    (let ((si:inhibit-fdefine-warnings :just-warn))
      (load file (pkg-find-package "USER")))
    ;; a file already written for the target is not loaded (cross-fasload-internal)
    (or (symbol-value symbol)
	(ferror nil "~A set no value of ~S here" file symbol))
    (cross-dump-symbol-value file symbol)))

(defun cross-dump-symbol-value (file symbol)
  (with-open-file (compiler:fasd-stream file :direction :output :characters nil
					     :byte-size 16.)
    (let ((compiler:fasd-package nil))
      (compiler:locking-resources
	(compiler:fasd-initialize)
	(compiler:fasd-start-file)
	(compiler:fasd-attributes-list
	  (list :package (package-name (symbol-package symbol))))
	;; fasd-attributes-list made the symbol's package fasd-package, so the
	;; symbol would be dumped with no prefix, and the cold load, whose
	;; fasloader takes no package from the attribute list, made a second
	;; symbol of the name: fonts:cptfont stayed unbound, and the cold-load
	;; stream's init method stopped on it.  with no fasd-package the symbol
	;; is dumped with its package's prefix.
	(setq compiler:fasd-package nil)
	(compiler:fasd-store-value-cell symbol (compiler:fasd-constant (symbol-value symbol)))
	(compiler:fasd-end-whack)
	(compiler:fasd-end-file))))
  file)

(defun cross-copy-partition (part-name file &optional n-blocks)
  "Copy the first N-BLOCKS blocks of PART-NAME (default: the cold load's pages) to FILE,
as bytes, for a program on the host to read."
  (multiple-value-bind (base size) (si:find-disk-partition part-name)
    (or base (ferror nil "No partition ~A" part-name))
    (let ((n (min size (or n-blocks
			   (* blocks-per-page (ceiling vmem-highest-address sym:page-size)))))
	  (rqb (si:get-disk-rqb 1))
	  ;; the blocks a page of this world's rqb takes: 1 in a world of 256-word
	  ;; pages, as the cross build's builder; 4 in a 40-bit world (a native
	  ;; build, contract g2 section 7, step 5), whose 4-byte transfer of a
	  ;; page reads 4 blocks, and of whose last transfer only the blocks asked
	  ;; for are written.  a block a transfer there would read 4 and write
	  ;; each block four times over.
	  (step (if (boundp 'si:disk-blocks-per-packed-page)
		    (symeval 'si:disk-blocks-per-page)
		  1)))
      (unwind-protect
	  (with-open-file (out file :direction :output :characters nil :byte-size 8)
;	    (dotimes (i n)
;	      (si:disk-read rqb 0 (+ base i))
;	      (send out :string-out (si:rqb-8-bit-buffer rqb))))
	    (do ((i 0 (+ i step))) ((>= i n))
	      (si:disk-read rqb 0 (+ base i))
	      (send out :string-out (si:rqb-8-bit-buffer rqb) 0 (* 1024. (min step (- n i))))))
	(si:return-disk-rqb rqb))
      (list :blocks n :base base))))
