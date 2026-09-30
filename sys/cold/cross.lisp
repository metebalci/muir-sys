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
    (cross-read-defining-files pending)))

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

(defun cross-check-formats ()
  (let ((bad nil))
    ;; a constant this world has no value for (QCOM's FEF-DES-DT, for one) is
    ;; in none of its code, so only the others are compared
    (flet ((check (s)
	     (let ((cold (cross-cold-symbol s)))
	       (when (and (boundp s)
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
      (apply (cross-original 'compiler:compile-stream) input-stream generic-pathname more)
  (let ((*cross-file* (or (send input-stream :send-if-handles :truename) generic-pathname))
	(*cross-lines* nil)
	(*cross-misses* nil)
	(status :aborted))
    (unwind-protect
	(prog1 (let ((compiler:warn-on-errors nil)
		     (*evalhook* 'cross-evalhook))
		 (apply (cross-original 'compiler:compile-stream)
			input-stream generic-pathname more))
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

;;; #., as si:xr-#.-macro reads it, with the form and its value logged
(defun cross-sharp-dot (stream ignore &optional ignore)
  (values (if *read-suppress*
	      (progn (si:internal-read stream t nil t) nil)
	    (let* ((form (si:internal-read stream t nil t))
		   (value (let ((*cross-context* :sharp-dot))
			    (si:eval1 form))))
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
(defun cross-fasload-internal (fasl-stream pkg no-msg-p)
  (let ((file (send fasl-stream :truename)))
    (cond ((not (cross-marked-file-p file))
	   (funcall (cross-original 'si:fasload-internal) fasl-stream pkg no-msg-p))
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

(defun cross-begin (&key (overlays '("SYS: COLD; TARGET40 LISP"))
		    (check-data-types t) (check-misc-instructions t) (check-formats t)
		    (log-directory *cross-log-directory*))
  "Load the target's parameters, check what the hook cannot see, and turn the cross build on.
OVERLAYS are loaded over QCOM, QDEFS and DEFMIC; NIL gives this tree's own parameters."
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
  (setq compiler:*cross-target* 'cross-target-value
	*cross-active* t)
  (list :word-bits word-bits :page-size sym:page-size
	:watched (cross-count *cross-watch*) :changed (length *cross-changed*)
	:without-value (length *cross-unset*)))

(defun cross-end ()
  "Turn the cross build off: this world's own values again."
  (dolist (s *cross-saved*) (fset (car s) (cdr s)))
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
	  (rqb (si:get-disk-rqb 1)))
      (unwind-protect
	  (with-open-file (out file :direction :output :characters nil :byte-size 8)
	    (dotimes (i n)
	      (si:disk-read rqb 0 (+ base i))
	      (send out :string-out (si:rqb-8-bit-buffer rqb))))
	(si:return-disk-rqb rqb))
      (list :blocks n :base base))))
