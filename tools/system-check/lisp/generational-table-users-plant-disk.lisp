;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:8; Readtable:T -*-
;;; A planted control for the check generational-table-users (contract G3 step
;;; 2, clarification 11; the review of the first-object table, section 5, P2,
;;; P3): MAKE-DISK-RQB, WIRE-DISK-RQB and WIRE-PAGE-RQB as they were before
;;; clarification 11, which neither pad to a page boundary nor refuse an RQB
;;; off one.  Given after lisp/generational-table-users.lisp in --files, P2
;;; must fail with "... not on a page boundary", P2 (b)'s refusal and P3's
;;; refusal must be NIL.  Not for any band in use.

(defun make-disk-rqb (ignore n-pages leader-length)
  (let* ((overhead (+ 4 4 3 leader-length))
	 (array-length (* (- (* (1+ n-pages) page-size) overhead) 2))
	 rqb-buffer
	 rqb-8-bit-buffer
	 rqb)
    ;; compute how much overhead there is in the rqb-buffer,
    ;; rqb-8-bit-buffer, and in the rqb's leader and header.  4 for the
    ;; rqb-buffer indirect-offset array, 4 for the rqb-8-bit-buffer
    ;; indirect-offset array, 3 for the rqb's header, plus the rqb's leader.
    ;; then set the length (in halfwords) of the array to be sufficient so
    ;; that it plus the overhead is a multiple of the page size, making it
    ;; possible to wire down rqb's.
    (when (> array-length %array-max-short-index-length)
      (incf overhead 1)
      (decf array-length 2)
      (unless (> array-length %array-max-short-index-length)
	(ferror nil "Impossible to make this RQB array fit")))
    ;; see if the ccw list will run off the end of the first page, and hence
    ;; not be stored in consecutive physical addresses.
;    (if (> (+ overhead (floor %disk-rq-ccw-list 2) n-pages) page-size)
    ;; 1024-word pages (contract g2, option (w)): a ccw a block
;    (if (> (+ overhead (floor %disk-rq-ccw-list 2) (* n-pages disk-blocks-per-page)) page-size)
    ;; quux revision 13 (appendix a1.11): a ccw a page
    (if (> (+ overhead (floor %disk-rq-ccw-list 2) n-pages) page-size)
	(ferror 'rqb-too-large "CCW list doesn't fit on first RQB page, ~S pages is too many"
		n-pages))
    (tagbody
     l	(setq rqb-buffer (make-array (* page-size 2 n-pages)
				     :type art-16b
				     :area disk-buffer-area
				     :displaced-to ""
				     :displaced-index-offset	;to second page of rqb
				     	(- array-length (* page-size 2 n-pages)))
	      rqb-8-bit-buffer (make-array (* page-size 4 n-pages)
					   :type art-string
					   :area disk-buffer-area
					   :displaced-to ""
					   :displaced-index-offset
					   	(* 2 (- array-length (* page-size 2 n-pages))))
	      rqb (make-array array-length
			      :area disk-buffer-area
			      :type art-16b
			      :leader-length leader-length))
	(when ( (%region-number rqb-buffer)	;make sure a new region
		 (%region-number rqb))		;didn't screw us completely
	  ;; screwed! try again.  make sure don't lose same way again by
	  ;;  using up region that didnt hold it.
	  (return-array rqb)
	  (let ((rn (%region-number rqb-buffer)))
	    (return-array rqb-buffer)
	    (%use-up-region rn))
	  (go l)))
    (make-sure-free-pointer-of-region-is-at-page-boundary
      'disk-buffer-area (%region-number rqb))
    (%p-store-contents-offset rqb rqb-buffer 1)	;displace rqb-buffer to rqb
    (%p-store-contents-offset rqb rqb-8-bit-buffer 1)
;    (store-array-leader (+ %disk-rq-ccw-list (* 2 n-pages))
;			rqb
;			%disk-rq-leader-n-hwds)
    ;; 1024-word pages (contract g2, option (w)): a ccw a block
;    (store-array-leader (+ %disk-rq-ccw-list (* 2 n-pages disk-blocks-per-page))
;			rqb
;			%disk-rq-leader-n-hwds)
    ;; quux revision 13 (appendix a1.11): a ccw a page
    (store-array-leader (+ %disk-rq-ccw-list (* 2 n-pages))
			rqb
			%disk-rq-leader-n-hwds)
    (setf (array-leader rqb %disk-rq-leader-n-pages) n-pages)
    (setf (array-leader rqb %disk-rq-leader-buffer) rqb-buffer)
    (setf (array-leader rqb %disk-rq-leader-8-bit-buffer) rqb-8-bit-buffer)
    rqb))

(defun wire-disk-rqb (rqb &optional (n-pages (array-leader rqb %disk-rq-leader-n-pages))
		      		    (wire-p t)
				    set-modified
			  &aux (long-array-flag (%p-ldb %%array-long-length-flag rqb))
;			       (low (- (%pointer rqb) (array-leader-length rqb) 2))
;			       (high (+ (%pointer rqb) 1 long-array-flag
;					(floor (array-length rqb) 2))))
;  (do ((loc (logand low (- page-size)) (+ loc page-size)))
;      (( loc high))
;    (wire-page loc wire-p set-modified))
			       ;; quux revision 14 (contract g3 revision 14, 10.10):
			       ;; the rqb's first and one-past-last words by
			       ;; %pointer-plus, modulo 2^32: by - and + an rqb at or
			       ;; across 2^31 gave bignums, and wire-page wired the
			       ;; bignums' pages, not the rqb's.
			       (low (%pointer-plus rqb (- (+ (array-leader-length rqb) 2))))
			       (high (%pointer-plus rqb (+ 1 long-array-flag
							   (floor (array-length rqb) 2)))))
  ;; each page from low's up to high, counted, the address stepped by
  ;; %pointer-plus (the loop ended by a signed compare, at once past 2^31)
  (do ((loc (logand low (- page-size)) (%pointer-plus loc page-size))
       (n (ceiling (%pointer-difference high (logand low (- page-size))) page-size) (1- n)))
      (( n 0))
    (wire-page loc wire-p set-modified))
  ;; having wired the rqb, if really wiring set up ccw-list n-pages long
  ;; and clp to it, but if really unwiring make clp point to nxm as err check
  (if (not wire-p)
      (setf (aref rqb %disk-rq-ccw-list-pointer-low)  #o177777	;just below tv buffer
            (aref rqb %disk-rq-ccw-list-pointer-high) #o76)
;    (do ((ccwx 0 (1+ ccwx))
;	 (vadr (+ low page-size) (+ vadr page-size))	;start with 2nd page of rqb array
;	 (padr))
;	(( ccwx n-pages)	;done, set end in last ccw
    ;; 1024-word pages (contract g2, option (w)): a ccw for each block of each
    ;; page, disk-blocks-per-page a page, each the physical address of its
    ;; block (a block is one map entry, 256 words, whose physical page
    ;; %physical-address gives)
;    (do* ((n-blocks (* n-pages disk-blocks-per-page))
;	  (block-words (disk-block-words))
;	  (ccwx 0 (1+ ccwx))
;	  (vadr (+ low page-size) (+ vadr block-words))	;start with 2nd page of rqb array
;	  (padr))
;	((>= ccwx n-blocks)	;done, set end in last ccw
    ;; quux revision 13 (appendix a1.11): a ccw names a page: its physical
    ;; address, <27:10>, and <0> the chain bit, a page's frame being whole.
;    (do* ((n-blocks n-pages)			;the ccws
;	  (block-words page-size)		;a ccw's words
;	  (ccwx 0 (1+ ccwx))
;	  (vadr (+ low page-size) (+ vadr block-words))	;start with 2nd page of rqb array
;	  (padr))
;	((>= ccwx n-blocks)	;done, set end in last ccw
;	 (setq padr (%physical-address (+ (%pointer rqb)
;					  1
;					  long-array-flag
;					  (floor %disk-rq-ccw-list 2))))
    ;; quux revision 14 (contract g3 revision 14, 10.10): each data page's
    ;; address, and the ccw list's, by %pointer-plus, so that an rqb at or
    ;; across 2^31 names its own pages' frames, not a bignum's
    (do* ((n-blocks n-pages)			;the ccws
	  (block-words page-size)		;a ccw's words
	  (ccwx 0 (1+ ccwx))
	  (vadr (%pointer-plus low page-size) (%pointer-plus vadr block-words))	;start with 2nd page of rqb array
	  (padr))
	((>= ccwx n-blocks)	;done, set end in last ccw
	 (setq padr (%physical-address (%pointer-plus rqb (+ 1
							     long-array-flag
							     (floor %disk-rq-ccw-list 2)))))
	 (setf (aref rqb %disk-rq-ccw-list-pointer-low) padr)
	 (setf (aref rqb %disk-rq-ccw-list-pointer-high) (lsh padr -16.)))
      (setq padr (%physical-address vadr))
;      (setf (aref rqb (+ %disk-rq-ccw-list (* 2 ccwx)))
;	    (+ (logand (- page-size) padr)		;low 16 bits
;	       (if (= ccwx (1- n-pages)) 0 1)))		;chain bit
      (setf (aref rqb (+ %disk-rq-ccw-list (* 2 ccwx)))
	    (+ (logand (- block-words) padr)		;low 16 bits
	       (if (= ccwx (1- n-blocks)) 0 1)))	;chain bit
      (setf (aref rqb (+ %disk-rq-ccw-list 1 (* 2 ccwx)))
	    (lsh padr -16.)))))				;high 6 bits

(defun wire-page-rqb () 
  (wire-page (%pointer page-rqb))
  (let ((padr (+ (%physical-address page-rqb)
;		 1
		 page-rqb-header-words		;1024-word pages: 2, the array being long
		 (floor %disk-rq-ccw-list 2))))
    (setf (aref page-rqb %disk-rq-ccw-list-pointer-low) padr)
    (setf (aref page-rqb %disk-rq-ccw-list-pointer-high) (lsh padr -16.))))
