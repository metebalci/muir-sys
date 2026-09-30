;;; -*- Mode:LISP; Package:USER; Base:10; Lowercase:T -*-

;;; The PDL buffer refill's check (tools/microcode-check/README.md,
;;; cases/pdl-refill.cases).  PDL-REFILL-SLOT reads the value slot of the
;;; innermost interpreter binding frame as its word stands, without following
;;; it: the data type's name and the cdr code.  For a special variable bound by
;;; an interpreted LET that slot is a DTP-ONE-Q-FORWARD to the value cell, with
;;; cdr-nil (2) ending the frame; a refill that followed the forward left a copy
;;; of the cell there, with the cell's cdr code, cdr-next (3).

(defun pdl-refill-slot ()
  (let* ((frame (car si:*interpreter-variable-environment*))
	 (slot (%make-pointer dtp-locative (1+ (%pointer frame)))))
    (list (nth (%p-data-type slot) q-data-types) (%p-cdr-code slot))))

(compile 'pdl-refill-slot)
