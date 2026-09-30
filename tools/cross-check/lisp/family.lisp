;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:10; Lowercase:T; Readtable:ZL -*-

;;; The cross build's check 1 (tools/cross-check/README.md).  For each family
;;; of system constants measured when G2 was planned (word fields, data types,
;;; cdr codes, the page, the fixnum, arrays, characters, floats, the FEF,
;;; headers, the disk, virtual addresses), a function at each point where the
;;; compiler evaluates while it compiles: a fold, #., an interpreted macro, an
;;; eval-when (compile) and a compiler-let.  Each puts the constant's value, or
;;; the value shifted left 20 for a fold, into its FEF, where check1.py reads
;;; it.  Then the compiler's own encodings.

(eval-when (compile load eval) (defvar *xc-ct* nil) (defvar *xc-cl* nil))
(defmacro xc-clm () `',*xc-cl*)

(defun xc-fold-qfield () (ash %%q-pointer 20))
(defun xc-sharp-qfield () '(sharp qfield #.%%q-pointer))
(defmacro xc-mac-qfield () `'(mac qfield ,%%q-pointer))
(defun xc-use-mac-qfield () (xc-mac-qfield))
(eval-when (compile) (setq *xc-ct* (list 'ct 'qfield %%q-pointer)))
(defun xc-ct-qfield () '#.*xc-ct*)
(defun xc-cl-qfield () (compiler-let ((*xc-cl* (list 'cl 'qfield %%q-pointer))) (xc-clm)))

(defun xc-fold-dtp () (ash dtp-locative 20))
(defun xc-sharp-dtp () '(sharp dtp #.dtp-locative))
(defmacro xc-mac-dtp () `'(mac dtp ,dtp-locative))
(defun xc-use-mac-dtp () (xc-mac-dtp))
(eval-when (compile) (setq *xc-ct* (list 'ct 'dtp dtp-locative)))
(defun xc-ct-dtp () '#.*xc-ct*)
(defun xc-cl-dtp () (compiler-let ((*xc-cl* (list 'cl 'dtp dtp-locative))) (xc-clm)))

(defun xc-fold-cdr () (ash cdr-next 20))
(defun xc-sharp-cdr () '(sharp cdr #.cdr-next))
(defmacro xc-mac-cdr () `'(mac cdr ,cdr-next))
(defun xc-use-mac-cdr () (xc-mac-cdr))
(eval-when (compile) (setq *xc-ct* (list 'ct 'cdr cdr-next)))
(defun xc-ct-cdr () '#.*xc-ct*)
(defun xc-cl-cdr () (compiler-let ((*xc-cl* (list 'cl 'cdr cdr-next))) (xc-clm)))

(defun xc-fold-page () (ash page-size 20))
(defun xc-sharp-page () '(sharp page #.page-size))
(defmacro xc-mac-page () `'(mac page ,page-size))
(defun xc-use-mac-page () (xc-mac-page))
(eval-when (compile) (setq *xc-ct* (list 'ct 'page page-size)))
(defun xc-ct-page () '#.*xc-ct*)
(defun xc-cl-page () (compiler-let ((*xc-cl* (list 'cl 'page page-size))) (xc-clm)))

(defun xc-fold-fixnum () (ash most-positive-fixnum 20))
(defun xc-sharp-fixnum () '(sharp fixnum #.most-positive-fixnum))
(defmacro xc-mac-fixnum () `'(mac fixnum ,most-positive-fixnum))
(defun xc-use-mac-fixnum () (xc-mac-fixnum))
(eval-when (compile) (setq *xc-ct* (list 'ct 'fixnum most-positive-fixnum)))
(defun xc-ct-fixnum () '#.*xc-ct*)
(defun xc-cl-fixnum () (compiler-let ((*xc-cl* (list 'cl 'fixnum most-positive-fixnum))) (xc-clm)))

(defun xc-fold-array () (ash %%array-type-field 20))
(defun xc-sharp-array () '(sharp array #.%%array-type-field))
(defmacro xc-mac-array () `'(mac array ,%%array-type-field))
(defun xc-use-mac-array () (xc-mac-array))
(eval-when (compile) (setq *xc-ct* (list 'ct 'array %%array-type-field)))
(defun xc-ct-array () '#.*xc-ct*)
(defun xc-cl-array () (compiler-let ((*xc-cl* (list 'cl 'array %%array-type-field))) (xc-clm)))

(defun xc-fold-artq () (ash art-q 20))
(defun xc-sharp-artq () '(sharp artq #.art-q))
(defmacro xc-mac-artq () `'(mac artq ,art-q))
(defun xc-use-mac-artq () (xc-mac-artq))
(eval-when (compile) (setq *xc-ct* (list 'ct 'artq art-q)))
(defun xc-ct-artq () '#.*xc-ct*)
(defun xc-cl-artq () (compiler-let ((*xc-cl* (list 'cl 'artq art-q))) (xc-clm)))

(defun xc-fold-char () (ash %%ch-font 20))
(defun xc-sharp-char () '(sharp char #.%%ch-font))
(defmacro xc-mac-char () `'(mac char ,%%ch-font))
(defun xc-use-mac-char () (xc-mac-char))
(eval-when (compile) (setq *xc-ct* (list 'ct 'char %%ch-font)))
(defun xc-ct-char () '#.*xc-ct*)
(defun xc-cl-char () (compiler-let ((*xc-cl* (list 'cl 'char %%ch-font))) (xc-clm)))

(defun xc-fold-float () (ash single-float-exponent-offset 20))
(defun xc-sharp-float () '(sharp float #.single-float-exponent-offset))
(defmacro xc-mac-float () `'(mac float ,single-float-exponent-offset))
(defun xc-use-mac-float () (xc-mac-float))
(eval-when (compile) (setq *xc-ct* (list 'ct 'float single-float-exponent-offset)))
(defun xc-ct-float () '#.*xc-ct*)
(defun xc-cl-float () (compiler-let ((*xc-cl* (list 'cl 'float single-float-exponent-offset))) (xc-clm)))

(defun xc-fold-fef () (ash %fefhi-fctn-name 20))
(defun xc-sharp-fef () '(sharp fef #.%fefhi-fctn-name))
(defmacro xc-mac-fef () `'(mac fef ,%fefhi-fctn-name))
(defun xc-use-mac-fef () (xc-mac-fef))
(eval-when (compile) (setq *xc-ct* (list 'ct 'fef %fefhi-fctn-name)))
(defun xc-ct-fef () '#.*xc-ct*)
(defun xc-cl-fef () (compiler-let ((*xc-cl* (list 'cl 'fef %fefhi-fctn-name))) (xc-clm)))

(defun xc-fold-header () (ash %header-type-array-leader 20))
(defun xc-sharp-header () '(sharp header #.%header-type-array-leader))
(defmacro xc-mac-header () `'(mac header ,%header-type-array-leader))
(defun xc-use-mac-header () (xc-mac-header))
(eval-when (compile) (setq *xc-ct* (list 'ct 'header %header-type-array-leader)))
(defun xc-ct-header () '#.*xc-ct*)
(defun xc-cl-header () (compiler-let ((*xc-cl* (list 'cl 'header %header-type-array-leader))) (xc-clm)))

(defun xc-fold-disk () (ash %disk-rq-ccw-list 20))
(defun xc-sharp-disk () '(sharp disk #.%disk-rq-ccw-list))
(defmacro xc-mac-disk () `'(mac disk ,%disk-rq-ccw-list))
(defun xc-use-mac-disk () (xc-mac-disk))
(eval-when (compile) (setq *xc-ct* (list 'ct 'disk %disk-rq-ccw-list)))
(defun xc-ct-disk () '#.*xc-ct*)
(defun xc-cl-disk () (compiler-let ((*xc-cl* (list 'cl 'disk %disk-rq-ccw-list))) (xc-clm)))

(defun xc-fold-vaddr () (ash a-memory-virtual-address 20))
(defun xc-sharp-vaddr () '(sharp vaddr #.a-memory-virtual-address))
(defmacro xc-mac-vaddr () `'(mac vaddr ,a-memory-virtual-address))
(defun xc-use-mac-vaddr () (xc-mac-vaddr))
(eval-when (compile) (setq *xc-ct* (list 'ct 'vaddr a-memory-virtual-address)))
(defun xc-ct-vaddr () '#.*xc-ct*)
(defun xc-cl-vaddr () (compiler-let ((*xc-cl* (list 'cl 'vaddr a-memory-virtual-address))) (xc-clm)))

;;; the compiler's own encodings
;;; a local used in a lexical closure: its slot marked by the fixnum sign bit
(defun xc-closure (a) (let ((b (1+ a)) (c (* a 2))) #'(lambda () (list b c))))
;;; floats: ieee singles in a 40-bit file
(defun xc-floats () '(1.5 -2.5 0.1 3.14159265358979 1.5s0 0.1s0 1.0e20))
;;; integers that are fixnums in the target and not all here
(defun xc-big () '(2147483647 -2147483648 16777216 2147483648))
;;; lsh works on a fixnum's width: not folded in a cross build
(defun xc-lsh () (lsh 1 30))
;;; ash does not: folded
(defun xc-ash () (+ 1000000 (ash 1 20)))
;;; typep: this world's data type number (TYPE-OF-ALIST), guarded
(defun xc-typep (x) (typep x 'locative))
