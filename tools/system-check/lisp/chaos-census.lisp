;;; -*- Mode:LISP; Package:USER; Base:10; Readtable:ZL -*-
;;; For the check chaos-census (tools/system-check/README.md): QUUX's band
;;; carries no Chaos after step R3 (QUUX's Ethernet contract, section 8).  Its
;;; check is a census of the files loaded and of the CHAOS: symbols in
;;; compiled code, which must find 0 of each.
;;; - The files loaded: every pathname in FS:*PATHNAME-HASH-TABLE* that has a
;;;   :FILE-ID-PACKAGE-ALIST, which LOAD, FASLOAD and the cold load record.
;;;   A file counts as Chaos's when its directory is NETWORK; CHAOS;, when it
;;;   is one of Chaos's own files kept elsewhere (*CENSUS-CHAOS-FILES*), or
;;;   when it was loaded into the package CHAOS (as SYS: SITE; HSTTBL was).
;;; - The compiled code: every FEF of the world, found by walking every
;;;   structure region by %STRUCTURE-TOTAL-SIZE from its origin, and the
;;;   symbols its constants name, read as FIND-CALLERS-OF-SYMBOLS-AUX-FEF
;;;   reads them (an external value cell pointer's symbol, or a symbol), and
;;;   the symbols in the list structure of its constants.  A symbol counts as
;;;   Chaos's when its package is named CHAOS.  Interpreted forms on the
;;;   initialization lists are read the same way, since an initialization
;;;   the band runs at boot is code too.
;;; Nothing here names a CHAOS: symbol, so that the file loads on a band
;;; without the package's contents.

(defvar *census-chaos-files* '(("WINDOW" "SUPDUP") ("IO1" "CONVER") ("FILE" "SERVER")
			       ("SYS2" "BAND") ("WINDOW" "PEEKFS"))
  "Chaos's own files outside SYS: NETWORK; CHAOS;, as (directory name): the SUPDUP and
TELNET clients, CONVERSE, the FILE server, band transfer, and PEEK's QFILE pane.")

(defun census-chaos-package-p (package)
  (and package (string-equal (si:pkg-name package) "CHAOS")))

(defun census-chaos-symbol-p (x)
  (and (symbolp x) (census-chaos-package-p (symbol-package x))))

(defun census-directory-string (pathname)
  (let ((d (send pathname :directory)))
    (format nil "~{~A ~}" (if (listp d) d (list d)))))

(defun census-chaos-file-p (pathname alist)
  (let ((directory (census-directory-string pathname))
	(name (send pathname :name)))
    (or (string-search "CHAOS" directory)
	(and (stringp name)
	     (loop for (d n) in *census-chaos-files*
		   thereis (and (string-equal n name) (string-search d directory))))
	(loop for entry in alist thereis (census-chaos-package-p (car entry))))))

(defun census-files ()
  "Chaos's files loaded: a list of (the generic pathname's string, the packages
it was loaded into)."
  (let ((found nil))
    (maphash #'(lambda (ignore p)
		 (let ((alist (send p :get :file-id-package-alist)))
		   (when (and alist (census-chaos-file-p p alist))
		     (pushnew (list (send p :string-for-printing)
				    (loop for entry in alist
					  collect (and (car entry) (si:pkg-name (car entry)))))
			      found :test #'equal))))
	     fs:*pathname-hash-table*)
    (sort found #'string-lessp :key #'car)))

(defun census-loaded-files ()
  "The number of all files loaded, for the record: a census that finds no file
at all has not looked."
  (let ((n 0))
    (maphash #'(lambda (ignore p)
		 (and (send p :get :file-id-package-alist) (incf n)))
	     fs:*pathname-hash-table*)
    n))

(defvar *census-walk-failures* nil
  "Regions whose walk met a word that is no object start: (region, offset).")

(defun census-walkable-region-p (region)
  (let* ((bits (si:region-bits region))
	 (space (%logldb si:%%region-space-type bits)))
    (and (= (%logldb si:%%region-representation-type bits)
	    si:%region-representation-type-structure)
	 (not (memq space (list si:%region-space-free si:%region-space-old
				si:%region-space-fixed si:%region-space-extra-pdl))))))

(defun census-map-fefs (function)
  "Call FUNCTION on every FEF in every structure region of the world.  The
number of FEFs."
  (setq *census-walk-failures* nil)
  (let ((n 0))
    (dotimes (region si:size-of-area-arrays)
      (when (census-walkable-region-p region)
	(let ((org (%make-pointer dtp-locative (si:region-origin region)))
	      (fp (si:region-free-pointer region)))
	  (do ((i 0)) ((>= i fp))
	    (let ((loc (%make-pointer-offset dtp-locative org i)))
	      (when (and (= (%p-data-type loc) dtp-header)
			 (= (%p-ldb si:%%header-type-field loc) si:%header-type-fef))
		(incf n)
		(funcall function (%make-pointer dtp-fef-pointer loc)))
	      (let ((total (%structure-total-size loc)))
		(unless (plusp total)
		  (push (list region i) *census-walk-failures*)
		  (return nil))
		(incf i total)))))))
    n))

(defun census-tree (x function &optional (limit 2000))
  "Call FUNCTION on each Chaos symbol in the list structure X, at most LIMIT
conses deep and long."
  (do ((l x (cdr l)) (k 0 (1+ k)))
      ((or (atom l) (>= k limit))
       (and (census-chaos-symbol-p l) (funcall function l)))
    (let ((a (car l)))
      (cond ((census-chaos-symbol-p a) (funcall function a))
	    ((and (consp a) (plusp limit)) (census-tree a function (truncate limit 2)))))))

(defun census-fef-constants (fef function)
  "Call FUNCTION on each Chaos symbol FEF's constants name."
  (do ((i si:%fef-header-length (1+ i))
       (lim (truncate (si:fef-initial-pc fef) 2)))
      ((>= i lim))
    (let ((dt (%p-ldb-offset si:%%q-data-type fef i)))
      (cond ((= dt dtp-external-value-cell-pointer)
	     (let ((sym (%find-structure-header (%p-contents-as-locative-offset fef i))))
	       (and (census-chaos-symbol-p sym) (funcall function sym))))
	    ((= dt dtp-self-ref-pointer))
	    (t (let ((c (%p-contents-offset fef i)))
		 (cond ((census-chaos-symbol-p c) (funcall function c))
		       ((consp c) (census-tree c function)))))))))

(defun census-function-name (fef)
  (condition-case () (si:fef-name fef) (error :unnamed)))

(defvar *census-fef-hits* nil
  "The last census: (the FEF's name, the Chaos symbol it names), each pair once.")

(defun census-symbols ()
  "The number of (FEF, Chaos symbol) pairs in compiled code; the pairs are in
*CENSUS-FEF-HITS*."
  (let ((hits nil))
    (census-map-fefs
      #'(lambda (fef)
	  (census-fef-constants fef
	    #'(lambda (sym)
		(pushnew (list (census-function-name fef) sym) hits :test #'equal)))))
    (setq *census-fef-hits* hits)
    (length hits)))

(defun census-fefs ()
  "(the FEFs walked, the regions whose walk failed)"
  (list (census-map-fefs #'ignore) (length *census-walk-failures*)))

(defun census-initializations ()
  "(initialization list, initialization name, Chaos symbol) for each Chaos symbol
in an interpreted initialization form."
  (let ((hits nil))
    (dolist (p si:*all-packages*)
      (mapatoms #'(lambda (s)
		    (when (and (get s 'si:initialization-list) (boundp s)
			       (listp (symbol-value s)))
		      (dolist (init (symbol-value s))
			(when (consp init)
			  (census-tree (si:init-form init)
				       #'(lambda (sym)
					   (pushnew (list s (si:init-name init) sym)
						    hits :test #'equal)))))))
		p nil))
    hits))

(defun census-hits-by-file ()
  "The FEFs of the last census grouped by the file that defined them: a list of
(file, the number of pairs), the most first."
  (let ((counts nil))
    (dolist (h *census-fef-hits*)
      (let* ((name (car h))
	     (inner (if (and (consp name) (memq (car name) '(:internal :property)))
			(cadr name) name))
	     (spec (if (and (consp inner) (eq (car inner) :method)) (cadr inner) inner))
	     (file (condition-case ()
		       (let ((f (si:get-source-file-name spec)))
			 (if f (send f :string-for-printing) "unknown"))
		     (error "unknown")))
	     (e (assoc file counts)))
	(if e (incf (cdr e)) (push (cons file 1) counts))))
    (sort counts #'> :key #'cdr)))

(defun census-hits-unattributed ()
  "The pairs of the last census whose FEF's defining file is not known."
  (loop for h in *census-fef-hits*
	when (let* ((name (car h))
		    (inner (if (and (consp name) (memq (car name) '(:internal :property)))
			       (cadr name) name))
		    (spec (if (and (consp inner) (eq (car inner) :method)) (cadr inner) inner)))
	       (null (condition-case () (si:get-source-file-name spec) (error nil))))
	  collect h))
