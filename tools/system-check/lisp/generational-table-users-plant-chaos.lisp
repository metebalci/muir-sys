;;; -*- Mode:LISP; Package:CHAOS; Base:8; Readtable:ZL -*-
;;; A planted control for the check generational-table-users (contract G3 step
;;; 2, clarification 12; the review of the first-object table, section 5, P5):
;;; PRINT-INT-PKT-STATUS as it was before clarification 12, walking
;;; CHAOS-BUFFER-AREA's region from its origin, through its first-object
;;; table.  Given after lisp/generational-table-users.lisp in --files, P5's
;;; walk must signal or visit other words than the buffers.  Not for any band
;;; in use.

(defun print-int-pkt-status (&optional print-all)
  (format t "~%Free list ~d, transmit-list ~d, receive-list ~d"
	  (int-pkt-list-length (system-communication-area %sys-com-chaos-free-list))
	  (int-pkt-list-length (system-communication-area %sys-com-chaos-transmit-list))
	  (int-pkt-list-length (system-communication-area %sys-com-chaos-receive-list)))
  (when print-all
    (let* ((region (sys:area-region-list chaos-buffer-area))
	   (ro (sys:region-origin region))
	   (rfp (sys:region-free-pointer region)))
      (do ((q-offset 0 (+ q-offset (+ 3 128. (length chaos-buffer-leader-qs)))))
	  ((>= q-offset rfp))
	(let ((pkt (%make-pointer dtp-array-pointer
				  (+ ro q-offset (+ 2 (length chaos-buffer-leader-qs))))))
	  (if (int-pkt-list-memq pkt (system-communication-area %sys-com-chaos-free-list))
	      (format t "~%Following pkt on free list!"))
	  (print-pkt pkt nil t)
	  (cond ((memq (pkt-opcode pkt)
		       '(#,rfc-op #,opn-op #,cls-op #,ans-op))
		 (dotimes (c (min 100. (ceiling (pkt-nbytes pkt) 2)))
		   (let ((b (aref pkt (+ c first-data-word-in-pkt))))
		     (tyo (logand b 377))
		     (tyo (lsh b -8))))))
	  ))))
  )
