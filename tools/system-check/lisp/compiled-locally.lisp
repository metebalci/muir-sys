;;; -*- Mode:LISP; Package:USER; Base:10; Readtable:ZL -*-
;;; For the check compiled-locally (tools/system-check/README.md): LOCALLY in
;;; the body of a compiled function.  The compiler had no LOCALLY of its own
;;; there and compiled one as a call of the interpreter's LOCALLY with the body
;;; quoted, so the body ran interpreted and did not see the function's lexical
;;; variables: "X is referenced as a free variable but not declared special."
;;; Run with --compile, so that these functions are compiled.

;; the symbols the SPECIAL declarations name; neither is declared special
;; anywhere, so only the LOCALLY's declaration makes a reference special
(set 'compiled-locally-sym 'global)
(set 'compiled-locally-set nil)

;; a control: the same declaration in a LET, which the compiler has
(defun compiled-locally-control (x)
  (let () (declare (special compiled-locally-nothing)) (list x)))

;; a lexical variable read inside the LOCALLY
(defun compiled-locally-read (x)
  (locally (declare (special compiled-locally-nothing)) (list x)))

;; a lexical variable written inside it, and read after it
(defun compiled-locally-write (x)
  (locally (setq x (1+ x)))
  x)

;; a closure made inside it
(defun compiled-locally-closure (x)
  (locally (function (lambda () x))))

;; its SPECIAL declaration: inside, the reference is the symbol's value; after
;; it, the lexical binding again
(defun compiled-locally-special ()
  (let ((compiled-locally-sym 'lexical))
    (list (locally (declare (special compiled-locally-sym)) compiled-locally-sym)
	  compiled-locally-sym)))

;; a special write inside it
(defun compiled-locally-special-set (x)
  (locally (declare (special compiled-locally-set)) (setq compiled-locally-set x))
  (symbol-value 'compiled-locally-set))

;; its value and multiple values, with and without a lexical variable
(defun compiled-locally-values (x)
  (locally (values x (1+ x) (+ x 2))))

(defun compiled-locally-constant-values ()
  (locally (values 1 2 3)))

(defun compiled-locally-empty ()
  (locally))

;; inside a LET, and inside a loop that pushes onto a lexical variable
(defun compiled-locally-let (x)
  (let ((y (* x 2)))
    (locally (declare (special compiled-locally-nothing)) (+ x y))))

(defun compiled-locally-loop (n)
  (let ((acc nil))
    (dotimes (i n)
      (locally (push i acc)))
    acc))

;; under DONT-OPTIMIZE, whose argument forms the compiler does not optimize
(defun compiled-locally-dont-optimize (x)
  (dont-optimize (locally (list x))))

;; a closure whose body holds the LOCALLY: the compiler finds the variables a
;; closure needs with its code walker (sys/sys/qcluke.lisp), which must look
;; inside the LOCALLY
(defun compiled-locally-in-closure (x)
  (function (lambda () (locally (list x)))))

;; a LOCALLY at the top level of the file, holding a DEFUN, which is then
;; compiled as a top-level form like the forms of a PROGN
(locally (declare (special compiled-locally-nothing))
  (defun compiled-locally-top (x) (list x)))

;; whether F's compiled code calls the interpreter's LOCALLY, from its disassembly
(defun compiled-locally-calls-locally (f)
  (not (null (string-search "#'LOCALLY"
			    (with-output-to-string (s)
			      (let ((*standard-output* s)) (disassemble f)))))))
