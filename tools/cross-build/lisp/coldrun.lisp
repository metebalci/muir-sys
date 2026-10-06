;;; COLDRUN for tools/cross-build: the cold load runs QLD unattended, with
;;; SYS: on HOST (quux's file device) and no Chaosnet, reports through MINI,
;;; and saves the band into @SAVE@, since nothing types at it.  Register-page
;;; word 224 (contract g3 revision 14, a14.9) and the paging counters, read
;;; with si:read-meter, are reported before the save.  the counters were read at
;;; A 154, 155 and 157 through A memory's window, revision 14's places; the
;;; generational collector's three A-memory fixnums moved the counter block, and
;;; read-meter finds it wherever the microcode puts it.
(qld (quote (:noconfirm :no-reload-system-declaration)) nil)
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
(mini-report "saving")
(si:disk-save "@SAVE@" t)
