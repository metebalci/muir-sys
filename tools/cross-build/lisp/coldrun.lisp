;;; COLDRUN for tools/cross-build: the cold load runs QLD unattended, with
;;; SYS: on HOST (quux's file device) and no Chaosnet, reports through MINI,
;;; and saves the band into @SAVE@, since nothing types at it.  Register-page
;;; word 224 (contract g3 revision 14, a14.9) and the paging counters, read
;;; with si:read-meter, are reported before the save.  the counters were read at
;;; A 154, 155 and 157 through A memory's window, revision 14's places; the
;;; generational collector's three A-memory fixnums moved the counter block, and
;;; read-meter finds it wherever the microcode puts it.
;;; the generational collector (clarification 12; the review of the
;;; first-object table, 5, p6): before qld, the cold load's first boot has run
;;; pkg-initialize, which interns every symbol mapatoms-nr-sym visits.  the
;;; visits in nr-sym and those that are no symbol are counted here, with the
;;; cold load's own functions only, and reported after qld, for comparing with
;;; the generator's count of the symbols in nr-sym (tools/cross-check/check3.py).
;;; the counts are kept on a property list: before qld, a setq of a variable
;;; that is not special, or the value of an unbound one, stops the cold load
;;; in the transporter's trap (trans-really-trap), with nothing printed.
(putprop 'coldrun-nr-sym 0 'visits)
(putprop 'coldrun-nr-sym 0 'not-symbols)
(si:mapatoms-nr-sym
  (function (lambda (s)
	      (cond ((= (%area-number s) si:nr-sym)
		     (putprop 'coldrun-nr-sym (1+ (get 'coldrun-nr-sym 'visits)) 'visits)
		     (cond ((not (= (%p-data-type s) dtp-symbol-header))
			    (putprop 'coldrun-nr-sym (1+ (get 'coldrun-nr-sym 'not-symbols))
				     'not-symbols))))))))
(qld (quote (:noconfirm :no-reload-system-declaration)) nil)
(mini-report (format nil "nr-sym-before-qld visits ~D not-symbols ~D"
		     (get 'coldrun-nr-sym 'visits) (get 'coldrun-nr-sym 'not-symbols)))
(mini-report "qld-complete")
(condition-case ()
    (mini-report
      (format nil "word224 ~O paging-reads-writes-fresh ~O ~O ~O"
	      (%p-ldb (byte 32 0) (%make-pointer dtp-locative (%make-pointer-unsigned (+ #o35777777400 #o224))))
;	      (%p-ldb (byte 32 0) (%make-pointer dtp-locative (%make-pointer-unsigned (+ #o35700000000 #o154))))
;	      (%p-ldb (byte 32 0) (%make-pointer dtp-locative (%make-pointer-unsigned (+ #o35700000000 #o155))))
;	      (%p-ldb (byte 32 0) (%make-pointer dtp-locative (%make-pointer-unsigned (+ #o35700000000 #o157))))))
	      (si:read-meter 'sys:%count-disk-page-reads)
	      (si:read-meter 'sys:%count-disk-page-writes)
	      (si:read-meter 'sys:%count-fresh-pages)))
  (error (mini-report "word224-read-failed")))
;;; the generational collector (contract g3 step 2 revision 1, 9.4): qld runs
;;; with no collection, so what it consed in working storage is young, in eden,
;;; and disk-save's young collection would keep its live part young in the
;;; band, to be copied into the tenured generation again by the first young
;;; collection after every boot.  a band the build makes is tenured before its
;;; save: a young flip with the tenure-all table, reclaimed.  the young words by
;;; generation (eden, survivor spaces 1 and 2) are reported before and after.
;;; @TENURE@ is t, or nil for a band saved without it (c29's record).
(defun coldrun-young-words ()
  (condition-case ()
      (cdr (multiple-value-list (si:gc-get-generation-sizes)))
    (error :unknown)))
(mini-report (format nil "young-words-before ~S" (coldrun-young-words)))
(when @TENURE@
  (condition-case (e)
      (progn (si:gc-flip-now :young t)
	     (si:gc-reclaim-oldspace)
	     (mini-report (format nil "tenured young-words-after ~S" (coldrun-young-words))))
    (error (mini-report (format nil "tenure-all-failed ~A" (send e :report-string))))))
(mini-report "saving")
(si:disk-save "@SAVE@" t)
