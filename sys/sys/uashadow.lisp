;;; -*- Mode:LISP; Package:MICRO-ASSEMBLER; Base:8; Readtable:ZL -*-

;;; the micro-assembler reads SYS: COLD; QCOM into its own package (the
;;; CADR-MICRO-ASSEMBLER system, SYS: SYS; SYSDCL), for the word's fields, the
;;; data types and the rest that the microcode names.  many of those names are
;;; GLOBAL's, which UA uses, so QCOM's DEFCONSTs and ASSIGN-ALTERNATEs set the
;;; running world's own values: harmless while the tree's QCOM is the world's,
;;; but the 40-bit tree (contract g2) read on System 2000's 32-bit band set
;;; %%Q-POINTER and its kin to the 40-bit word's, and the band halted while it
;;; loaded the micro-assembler.  so, before QCOM is read, each constant QCOM
;;; changes that UA would inherit from GLOBAL is shadowed in UA: QCOM then sets
;;; UA's own symbol, and the microcode, read in UA, sees it.
;;; the names are found by reading QCOM's forms into a package of its own,
;;; which uses no other, without evaluating them: each DEFCONST whose value is
;;; a number, and each name and number of a list that ASSIGN-ALTERNATE assigns
;;; in pairs.  a name is shadowed only when its value in the running world is
;;; a number other than QCOM's, so that names used as symbols (the array
;;; types, as type specifiers) and the values QCOM leaves as they are stay
;;; GLOBAL's.

(defvar *qcom-values*)

(defun qcom-note (name value)
  (and (symbolp name) (numberp value)
       (push (cons (symbol-name name) value) *qcom-values*)))

(defun qcom-form-name-p (x name)
  (and (symbolp x) (string= (symbol-name x) name)))

(defun qcom-numeric-values (file)
  "(name . value) for FILE's DEFCONSTs of a number and its ASSIGN-ALTERNATE pairs."
  (let ((pkg (or (find-package "UA-QCOM-NAMES")
		 (make-package "UA-QCOM-NAMES" :use nil)))
	(*qcom-values* nil)
	(lists nil))
    (with-open-file (s file)
      (let ((package pkg) (*package* pkg) (*read-base* 8) (ibase 8))
	;; cli:read, whose eof value is its third argument: zetalisp's read,
	;; global's, takes its second as the eof value and returned nil for ever.
	(do ((form (cli:read s nil s) (cli:read s nil s)))
	    ((eq form s))
	  (when (consp form)
	    (cond ((qcom-form-name-p (car form) "DEFCONST")
		   (let ((value (caddr form)))
		     (qcom-note (cadr form) value)
		     (when (and (consp value) (qcom-form-name-p (car value) "QUOTE"))
		       (push (cons (symbol-name (cadr form)) (cadr value)) lists))))
		  ((qcom-form-name-p (car form) "ASSIGN-ALTERNATE")
		   (let ((l (cdr (assoc (symbol-name (cadr form)) lists))))
		     (do ((l l (cddr l))) ((null (cdr l)))
		       (qcom-note (car l) (cadr l))))))))))
    *qcom-values*))

(defun shadow-qcom-names ()
  "Shadow in UA each numeric constant of QCOM that UA inherits from GLOBAL with another value."
  (let ((ua (find-package "UA"))
	(global (find-package "GLOBAL"))
	(done nil))
    (dolist (nv (qcom-numeric-values "SYS: COLD; QCOM LISP >"))
      (multiple-value-bind (sym status) (find-symbol (car nv) ua)
	(when (and sym (eq status :inherited) (eq (symbol-package sym) global)
		   (boundp sym) (numberp (symbol-value sym))
		   (not (= (symbol-value sym) (cdr nv)))
		   (not (mem #'string= (car nv) done)))
	  (push (car nv) done)
	  (shadow (car nv) ua))))
    done))

(shadow-qcom-names)
