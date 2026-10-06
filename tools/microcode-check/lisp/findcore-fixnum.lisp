;;; -*- Mode:LISP; Package:USER; Base:10; Lowercase:T -*-

;;; The check findcore-fixnum (tools/microcode-check/README.md,
;;; cases/findcore-fixnum.cases).  %FINDCORE takes a frame for a page and
;;; returns its number, which PAGE-IN-WORDS and WIRE-PAGE give to LSH and
;;; %PAGE-IN.  FINDCORE-OUT-RUN finds pages of P-N-STRING that are not in
;;; core, as most of them are after a boot; FINDCORE-PAGE-IN pages a run of
;;; them in with PAGE-IN-WORDS and compares each with its blocks in the PAGE
;;; partition, read by DISK-READ.  The functions are compiled when the file
;;; is loaded as source, since %FINDCORE and %PAGE-STATUS are open-coded by the
;;; compiler and are no functions.

(defun findcore-out-run (n)
  "The address of the first of N pages of P-N-STRING's regions none of which is
in core, or NIL."
  (do ((region (si:area-region-list si:p-n-string) (si:region-list-thread region)))
      ((minusp region) nil)
    (do ((p (si:region-origin region) (%pointer-plus p si:page-size))
	 (k 0 (1+ k)))
	((> (* (+ k n) si:page-size) (si:region-free-pointer region)))
      (when (loop for i below n
		  never (si:%page-status (%pointer-plus p (* i si:page-size))))
	(return-from findcore-out-run p)))))

(defun findcore-type ()
  "T if %FINDCORE returns a fixnum.  The frame goes back to the free pool."
  (let ((pfn (si:%findcore)))
    (prog1 (= (%data-type pfn) dtp-fix)
	   (si:%create-physical-page (lsh (%pointer pfn) 8)))))

(defun findcore-page-matches-disk (address rqb)
  "T if the page at ADDRESS has the same 32-bit words as its blocks in the
PAGE partition."
  (si:disk-read rqb 0 (+ (lsh (%pointer address) -8) si:page-offset))
  (let ((buf (si:rqb-buffer rqb)))
    (loop for i below si:page-size
	  always (and (= (aref buf (* 2 i)) (%p-ldb-offset #o0020 address i))
		      (= (aref buf (1+ (* 2 i))) (%p-ldb-offset #o2020 address i))))))

(defun findcore-page-in (n)
  "Page N pages of P-N-STRING not in core in by PAGE-IN-WORDS.  A list: T if
each is in core after, and T if each equals its blocks in the PAGE partition."
  (let ((p (findcore-out-run n))
	(rqb nil))
    (si:page-in-words p (* n si:page-size))
    (list (loop for i below n
		always (si:%page-status (%pointer-plus p (* i si:page-size))))
	  (unwind-protect
	      (progn (setq rqb (si:get-disk-rqb 1))
		     (loop for i below n
			   always (findcore-page-matches-disk
				    (%pointer-plus p (* i si:page-size)) rqb)))
	    (and rqb (si:return-disk-rqb rqb))))))

(dolist (f '(findcore-out-run findcore-type findcore-page-matches-disk findcore-page-in))
  (unless (typep (fdefinition f) 'compiled-function)
    (compile f)))
