;;; COLDRUN for tools/cross-build: the cold load runs QLD unattended, with
;;; SYS: on HOST (quux's file device) and no Chaosnet, reports through MINI,
;;; and saves the band into @SAVE@, since nothing types at it.  Register-page
;;; word 224 (contract g3 revision 14, a14.9) and the paging counters, A 154,
;;; 155 and 157 read through A memory's window, are reported before the save.
(qld (quote (:noconfirm :no-reload-system-declaration)) nil)
(mini-report "qld-complete")
(condition-case ()
    (mini-report
      (format nil "word224 ~O paging-reads-writes-fresh ~O ~O ~O"
	      (%p-ldb (byte 32 0) (%make-pointer dtp-locative (%make-pointer-unsigned (+ #o35777777400 #o224))))
	      (%p-ldb (byte 32 0) (%make-pointer dtp-locative (%make-pointer-unsigned (+ #o35700000000 #o154))))
	      (%p-ldb (byte 32 0) (%make-pointer dtp-locative (%make-pointer-unsigned (+ #o35700000000 #o155))))
	      (%p-ldb (byte 32 0) (%make-pointer dtp-locative (%make-pointer-unsigned (+ #o35700000000 #o157))))))
  (error (mini-report "word224-read-failed")))
(mini-report "saving")
(si:disk-save "@SAVE@" t)
