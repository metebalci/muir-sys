;-*- Mode:LISP; Package:SI; Readtable:ZL; Base:10 -*-

(defvar *analyzed-files* nil)

(defvar *unanalyzed-files* nil)

(defconst dont-record-function-specs
	  '(t nil lambda))

;>> icky kludgey magic list
(defparameter dont-record-symbol-values
	      '(;; contains all the random evaluations which the very cold-load was too
		;; stupid to perform itself. (such as defvar initializations, etc)
		original-lisp-crash-list
		;; list of symbols to be yanked out of the cold-load's si package
		;; and stuck into sys by package initialization
		initial-system-symbols
		;; ditto, but for global symbols
		initial-global-symbols
		;; compiled with different version of macro from one loaded.
		;; there may be some of these in the cold-load
		macro-mismatch-functions
		;; putting zwei:indent in debugging-info does away with need for this
		; zwei:*initial-lisp-indent-offset-alist*
		; zwei:*lisp-indent-offset-alist
		;;
		si::cold-load-function-property-lists
		;; what it sounds like
		*all-flavor-names*
		;; ditto
		*all-resources*
		;; all zmacs commands end up in this
		zwei::*command-alist*
		)
  "Don't analyze the values of these symbols.")

(defconst analyze-area (make-area :name 'debug-inf-area :representation :structure
				  :region-size #o100000))

(set-swap-recommendations-of-area analyze-area 6)

(defun analyze-system (system)
  (mapc #'analyze-file-and-record (system-source-files system)))

(defun analyze-all-files ()
  (setq *analyzed-files* nil)
  (maphash #'(lambda (ignore pathname)
	       (and (send pathname :get :definitions)
		    (not (memq pathname *analyzed-files*))
		    (analyze-file-and-record pathname)))
	   fs:*pathname-hash-table*)
  ;; Put them in the same order that LINEARIZE-PATHNAME-PLISTS copies their plists.
  (setq *analyzed-files* (nreverse *analyzed-files*)))

(defun sort-analyzed-files ()
  (setq *analyzed-files* (sort *analyzed-files*
			       #'(lambda (f1 f2)
				   (< (%pointer (get f1 ':foreign-objects-referenced))
				      (%pointer (get f2 ':foreign-objects-referenced)))))))

(add-initialization "Sort Analyzed Files" '(sort-analyzed-files) '(before-cold))

(defun analyze-changed-files ()
  "Reanalyze all files that have been changed."
  (mapc #'(lambda (pathname)
	    (or (send pathname :get :patch-file)
		(analyze-file-and-record pathname)))
	*unanalyzed-files*)
  (setq *unanalyzed-files* nil))

;Look through all the definitions in this file
;and record what objects not defined in the file are referenced by the file.
;The record made is the :FOREIGN-OBJECTS-REFERENCED property of the generic pathname,
;and its value is an ART-Q-LIST array whose contents are a list of the objects.
;The generic pathname is put on *ANALYZED-FILES* if not there already.
(defun analyze-file-and-record (pathname &optional (whole-file t))
  (let* ((generic-pathname (send pathname :generic-pathname))
	 (table (or (and (not whole-file)
			 (send generic-pathname :get :foreign-objects-referenced))
		    (make-array #o100 :type art-q-list
				:area analyze-area :fill-pointer 0))))
    (analyze-file generic-pathname #'analyze-record-used-object table nil)
    (if (zerop (fill-pointer table))
	(return-storage (prog1 table (setq table nil)))
      (pushnew generic-pathname *analyzed-files* :test #'eq)
      (send generic-pathname :putprop table :foreign-objects-referenced))))

;Return a list of all the files that contain references to any of the objects specified.
;Also add on any files that define those objects,
;since the analysis tables for those files will not contain those objects
;(since the tables only mention objects refered to but not defined).
(defun find-files-using-objects (objects &aux using-files)
  (dolist (obj objects)
    (setq objects (add-symbols-optimized-into obj objects)))
  (dolist (gp *analyzed-files*)
    (let ((table (send gp :get :foreign-objects-referenced)))
      (if (mem #'(lambda (objects obj) (memq obj objects))
	       objects
	       (g-l-p table))
	  (push gp using-files))))
  (dolist (obj objects)
    (dolist (def-type-files (get-all-source-file-names obj))
      (dolist (file (cdr def-type-files))
	(pushnew file using-files :test #'eq))))
  using-files)

(defvar *analyze-filename*)

(defun find-users-of-objects (objects &optional type)
  "Given a list of objects, return an alist of all the objects that use them
/(but only includes using objects that are in files that have been analyzed).
The format of the value is:
/((used-object-1 (how-used-1a using-object-1a defn-type-1a) ...)
/ (used-object-2 ...)
/ ...)
TYPE should be one of :FUNCTION, :VALUE, :CONSTANT or :FLAVOR to only find usages
of that particular type, or NIL, meaning to find usages of any type."
  (dolist (obj objects)
    (setq objects (add-symbols-optimized-into obj objects)))
  (let ((table (mapcar #'ncons objects)))
    ;; First we find which files might refer to these objects.
    (dolist (generic-pathname (find-files-using-objects objects))
      ;; Now analyze those files, but record callers of these objects.
      (let ((*analyze-filename* (send generic-pathname :new-pathname
						       :type :lisp :version :newest)))
	(analyze-file generic-pathname (if (eq type nil)
					   #'analyze-record-user-of-object
					   #'(lambda (x y)
					       (if (or (eq type y) (eq y nil))
						   (analyze-record-user-of-object x y))))
		      table nil)))
    table))

;Look at all the definitions in the specified file.
;For each time a definition references some object,
;call the RECORD-FUNCTION.  The arguments will be the object referenced
;and the type of reference (:FUNCTION, :VALUE, :CONSTANT, :FLAVOR, or NIL if unknown).  
(defun analyze-file (generic-pathname record-function analyze-table pkg)
  (declare (special analyze-table))
  (let* ((all-packages-definitions (send generic-pathname :get :definitions))
	 (analyze-definitions (or (cdr (assoc-equal pkg all-packages-definitions))
				  (cdar all-packages-definitions))))
    (declare (special analyze-definitions))
    ;; Record any random forms to be evaluated, present in this file.
    ;; List them as object nil, definition type nil.
    (analyze-definition nil nil (rem-if #'(lambda (elt)
					    (eq (car-safe elt)
						'fasl-record-file-macros-expanded))
					(send generic-pathname :get :random-forms))
			record-function)
    (dolist (def analyze-definitions)
      (analyze-object (car def) record-function))))

;These are two RECORD-FUNCTIONs:
;one to record all the objects that are used but not defined in this file,
;and one to record all the objects that use certain specified ones.
(defun analyze-record-used-object (used-object ignore)
  (declare (special analyze-table analyze-definitions))
  (if (symbolp used-object)
      (or (assq used-object analyze-definitions)
	  (memq used-object dont-record-function-specs)
	  (memq used-object (g-l-p analyze-table))
	  (vector-push-extend used-object analyze-table))
    (or (assoc-equal used-object analyze-definitions)
	(member-equal used-object dont-record-function-specs)
	(member-equal used-object (g-l-p analyze-table))
	(vector-push-extend used-object analyze-table))))

(defun analyze-record-user-of-object (used-object how-used)
  (declare (special analyze-table analyze-object-name analyze-object-type))
  (let ((slot (assoc-equal used-object analyze-table)))
    (if slot
	(let ((use (list how-used
			 (or analyze-object-name *analyze-filename*)
			 analyze-object-type)))
	  (pushnew use (cdr slot) :test #'equal)))))

(defun analyze-object (object-name record-function)
  (or (not (fdefinedp object-name))
      ;; Don't count symbols forwarded to others.
      (and (symbolp object-name)
	   (neq (locf (symbol-function object-name))
		(follow-cell-forwarding (locf (symbol-function object-name)) t)))
      (analyze-definition object-name :function
			  (fdefinition (unencapsulate-function-spec object-name))
			  record-function))
  (and (symbolp object-name)
       (boundp object-name)
       (not (memq object-name dont-record-symbol-values))
       ;; Don't count symbols forwarded to others.
       (eq (locf (symbol-value object-name))
	   (follow-cell-forwarding (locf (symbol-value object-name)) t))
       (analyze-definition object-name :value
			   (symbol-value object-name)
			   record-function))
  (and (symbolp object-name)
       (do ((plist (plist object-name) (cddr plist)))
	   ((null plist))
	 (analyze-definition object-name :property-name (car plist) record-function)
	 (or (typep (cadr plist) 'compiled-function)
	     (analyze-definition object-name `(:property ,(car plist))
				 (cadr plist)
				 record-function)))))

;Record about one definition of one object.
;The first arg is the name of the object.
;The second is the type of definition (:FUNCTION, :VALUE, :PROPERTY, etc.)
;The third is the value of that definition.
(defun analyze-definition (analyze-object-name analyze-object-type
			   definition record-function)
  (declare (special analyze-object-name analyze-object-type))
  (and (eq analyze-object-type :function)
       (eq (car-safe definition) 'macro)
       (pop definition))
  (typecase definition
    (compiled-function (analyze-compiled-function definition record-function))
    (si:flavor (analyze-flavor definition record-function))
    (symbol (analyze-list definition record-function))
    (list (funcall (if (eq analyze-object-type :function)
			#'analyze-lambda
		        #'analyze-list)
		    definition record-function))
    (select-method (analyze-list (%make-pointer dtp-list definition) record-function))
    (closure (analyze-definition (closure-function definition) :function
				 (closure-function definition) record-function))))

(defun analyze-flavor (definition record-function &aux (analyze-object-type :flavor))
  (declare (special analyze-object-name analyze-object-type))
  (analyze-list (flavor-local-instance-variables definition) record-function)
  (analyze-list (flavor-init-keywords definition) record-function)
  (analyze-list (flavor-inittable-instance-variables definition) record-function)
  (do ((plist (flavor-plist definition) (cddr plist))) ((null plist))
    (or (memq (car plist) '(additional-instance-variables
			    compile-flavor-methods
			    unmapped-instance-variables
			    mapped-component-flavors
			    all-instance-variables-special
			    instance-variable-initializations
			    all-inittable-instance-variables
			    remaining-default-plist
			    remaining-init-keywords))
	(analyze-definition analyze-object-name analyze-object-type
			    (cadr plist) record-function))
    (analyze-list (car plist) record-function)))

(defun analyze-compiled-function (definition record-function
				  &aux tem sym offset
				  (debug-info (debugging-info definition)))
  (do ((i %fef-header-length (1+ i))
       (lim (%structure-boxed-size definition)))
      (( i lim) nil)
    (cond ((= (%p-ldb-offset %%q-data-type definition i) dtp-external-value-cell-pointer)
	   (setq tem (%p-contents-as-locative-offset definition i)
		 sym (%find-structure-header tem)
		 offset (%pointer-difference tem sym))
	   (if (consp sym) (setq sym (car sym)))
	   (funcall record-function
		    sym
		    (case offset
		      (2 :function)
		      (1 :value))))
	  ((= (%p-ldb-offset %%q-data-type definition i) dtp-self-ref-pointer)
	   (let* ((fn (fef-flavor-name definition)))
	     (if fn
		 (multiple-value-bind (symbol use)
		     (flavor-decode-self-ref-pointer fn (%p-ldb-offset %%q-pointer definition i))
		   (funcall record-function symbol (if use :flavor :value))))))
	  ((eq (%p-contents-offset definition i) debug-info))
	  ((symbolp (%p-contents-offset definition i))
	   (funcall record-function (%p-contents-offset definition i) :constant))
	  ((consp (%p-contents-offset definition i))
	   (analyze-list (%p-contents-offset definition i) record-function))))
  ;; Now we should see if there is a reference compiled into a misc instruction,
  ;; except that we don't know which ones are worth checking for
  ;; and don't want to take the time to check them all.
  ;; So we just decide that misc functions are too widely used to be worth it.

  ;; Now record any macros that were expanded in compiling this function.
  (analyze-list (assq :macros-expanded debug-info) record-function)
  ;; Now analyze any internal functions that are part of this one.
  (and (setq tem (cdr (assq :internal-fef-offsets (debugging-info definition))))
       (loop for offset in tem
	     for i from 0
	     do (analyze-compiled-function (%p-contents-offset definition offset)
					   record-function))))

(defun analyze-lambda (definition record-function)
  (analyze-list (lambda-exp-args-and-body definition)
		record-function))

(defun analyze-list (list record-function)
  (do ((rest list (cdr rest)))
      ((atom rest)
       (if (symbolp rest)
	   (funcall record-function rest nil)))
    (let ((element (car rest)))
      (cond ((symbolp element)
	     (funcall record-function element nil))
	    ((list-match-p element `(function ,ignore))
	     (funcall record-function (cadr element) :function))
	    ((consp element)
	     (analyze-list element record-function))))))

