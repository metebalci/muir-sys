;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:10; Lowercase:T -*-
;;; A planted partial fix for the check generational-reclaim (the pages a
;;; tenured flip cuts off its old regions' ends): DEALLOCATE-PAGES doing
;;; nothing, so the tail DEALLOCATE-END-OF-REGION cuts off keeps its pages'
;;; frames, slots and page-table entries, though the address space map no
;;; longer gives its quanta to the region.  Given after
;;; lisp/generational-collector.lisp in --files: GENCOL-TAILS-RUN must fail
;;; (cut-off pages keeping an entry that no region reused).  Every other case
;;; of generational-collector, generational-reclaim, generational-tuning and
;;; region-area-map-interrupt passes with it.  Not for any band in use.

(defun deallocate-pages (base-addr n-pages) base-addr n-pages nil)
