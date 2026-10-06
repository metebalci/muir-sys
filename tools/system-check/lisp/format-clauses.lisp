;;; -*- Mode:LISP; Package:FORMAT; Base:10; Readtable:ZL -*-
;;; For the checks format-clauses and format-clauses-gc
;;; (tools/system-check/README.md): FORMAT's cached clause buffer,
;;; FORMAT-CLAUSES-ARRAY, and the strings of returned clauses it may still
;;; point to.  FORMAT-PARSE-CLAUSES conses each clause's string with
;;; NSUBSTRING in FORMAT-TEMPORARY-AREA and FORMAT-RECLAIM-CLAUSES gives it
;;; back with RETURN-ARRAY (sys/io/format.lisp); the buffer is kept for the
;;; next call.  A buffer that still holds such a string after the call holds
;;; a pointer to storage given back, which the scavenger transports when it
;;; scans the buffer, its whole length and not only below the fill pointer.
;;; Definitions only; the cases call them.

(defun fc-returned-p (x)
  "T if X is an array lying at or above its region's free pointer: storage
given back by RETURN-ARRAY and not consed again."
  (and (arrayp x)
       (let ((r (si:%region-number x)))
	 (and r (>= (- (%pointer x) (si:region-origin r)) (si:region-free-pointer r))))))

(defun fc-held ()
  "What FORMAT-CLAUSES-ARRAY holds over its whole length, past its fill
pointer too: (the arrays, the arrays given back)."
  (let ((a format-clauses-array) (arrays 0) (returned 0))
    (when a
      (dotimes (i (array-length a))
	(let ((x (aref a i)))
	  (when (arrayp x) (incf arrays))
	  (when (fc-returned-p x) (incf returned)))))
    (list arrays returned)))

;;; The planted state of the collector's halt, for format-clauses-gc, at 2 M
;;; words of main memory.  FORMAT's temporary consing goes to an area of the
;;; check's own, a dynamic one, so that a flip copies it:
;;;  1. a first call makes the buffers there, and a pad brings the area's free
;;;     pointer to a page boundary B;
;;;  2. a call with three clauses conses their strings from B and gives them
;;;     back, so the free pointer is B again;
;;;  3. B's page is forced out (rev14-paging's way: large arrays filled);
;;;  4. a call with one clause conses its string at B, a fresh page boundary,
;;;     so CONSF creates the page without reading it (M-DONT-SWAP-IN): the
;;;     words past that string are the fresh fill, DTP-TRAP, and the second
;;;     clause's string, which the buffer may still point to, is gone;
;;;  5. a collection: the buffer is scavenged, the first clause's string is
;;;     copied, and a pointer still held to the second makes
;;;     %FIND-STRUCTURE-HEADER's backward scan meet the first's GC-FORWARD
;;;     words: ILLOP (HALT-CONS from XFSHS1+2), the machine stops.

(defvar *fc-area* nil)
(defvar *fc-b* nil)
(defvar *fc-push* nil)

(defun fc-free (area)
  "The address of AREA's first region's free pointer."
  (let ((r (si:area-region-list area)))
    (+ (si:region-origin r) (si:region-free-pointer r))))

(defun fc-format (control)
  (let ((format-temporary-area *fc-area*))
    (format nil control 0)))

(defun fc-plant-1 ()
  "Steps 1 and 2.  T when the free pointer is back at the page boundary B
after the three-clause call."
  (setq *fc-area* (si:make-area :name (gensym) :gc :dynamic))
  (setq format-clauses-array nil format-stack-array nil format-string-buffer-array nil)
  (fc-format "~[a~;b~;c~]")
  (let* ((fp (fc-free *fc-area*))
	 (b (* si:page-size (ceiling (+ fp 2) si:page-size))))
    ;; an art-32b array of n elements is 1 + n words while n is short
    (make-array (- b fp 1) :type 'art-32b :area *fc-area*)
    (setq *fc-b* (fc-free *fc-area*)))
  (fc-format "~[aaaaa~;bbbbb~;ccccc~]")
  (and (zerop (remainder *fc-b* si:page-size)) (= (fc-free *fc-area*) *fc-b*)))

(defun fc-out-p ()
  "T if the page at B is out of core."
  (null (si:%page-status *fc-b*)))

(defun fc-push (n)
  "Fill an array of N words, forcing pages out."
  (setq *fc-push* (make-array n))
  (dotimes (i n) (aset i *fc-push* i))
  (setq *fc-push* nil)
  n)

(defun fc-plant-2 ()
  "Steps 3 and 4: B's page out, then the one-clause call.  The data type of the
word just past the first string, at B + 4: DTP-TRAP (0) when the page came
back fresh."
  (si:page-out-words *fc-b* si:page-size)
  (fc-push 1500000)
  (fc-push 1500000)
  (let ((out (fc-out-p)))
    (fc-format "~[x~]")
    (list out (= (fc-free *fc-area*) *fc-b*)
	  (%p-data-type (%make-pointer dtp-locative (+ *fc-b* 4))))))

(defun fc-collect ()
  "Step 5: a collection of every dynamic area; T when it returns."
  (si:gc-immediately)
  t)
