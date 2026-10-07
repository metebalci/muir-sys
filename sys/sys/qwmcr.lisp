;-*- Mode:LISP; Package:MICRO-ASSEMBLER; Base:8; Readtable:T -*-

;Write out the output of CONSLP.
;This is the Lisp machine version of WMCR.  It's a different file
;because so much had to be changed.

;For now, the reading side is flushed.  It exists elsewhere anyway, doesn't it?

;An MCR file looks a lot like a microcode partition.  Each 36-bit word
;contains one 32-bit word, left-justified.  (Being left justified makes
;it a whole lot easier to gobble the file with the real machine).
;From the Lisp machine, we write this as 2 16-bit pieces

;;; quux: the microcode and the boot prom this tree assembles are quux's,
;;; whose .mcr is written in partition order (muir's contract q8): each
;;; 32-bit word's low half first, then its high half, exactly as the word
;;; lies in a microcode partition, and the file padded with zeros to a whole
;;; block, so that dd copies it into a partition with no conversion.  mit's
;;; order, high half first, which every copy into a partition swapped (see
;;; load-mcr-file in io/disk.lisp), is had by binding this to nil; the
;;; cadr's microcode, mit's 323, stays in mit's order.  every section writes
;;; its words as pairs of halves, high then low, so out16 holds the high
;;; half until the low one comes and writes the two swapped.
(defvar *mcr-partition-order* t
  "T writes a .mcr file in partition order (quux's), NIL in mit's order.")
(defvar mcr-held-high-half nil
  "The high half of the word being written in partition order, until its low half comes.")

(DEFVAR CONSLP-OUTPUT-SYMBOL-PREDICTED-FILEPOS)
(DEFVAR CONSLP-OUTPUT-CURRENT-FILEPOS)
(PROCLAIM '(SPECIAL CONSLP-OUTPUT VERSION-NUMBER CONSLP-OUTPUT-PATHNAME))
;; quux: the word width, cadrlp's: 32. or 40. (contract g2).
(proclaim '(special *word-width*))
;; quux: the hardware revision, cadrlp's: 13. or 14. (contract g3's revision 14).
(proclaim '(special *hardware-revision*))

(DEFUN OUT16 (FILE HALFWORD)
  (INCF CONSLP-OUTPUT-CURRENT-FILEPOS)
  (cond ((not *mcr-partition-order*)
	 (SEND FILE :TYO HALFWORD))
	((null mcr-held-high-half)
	 (setq mcr-held-high-half halfword))
	(t (send file :tyo halfword)
	   (send file :tyo mcr-held-high-half)
	   (setq mcr-held-high-half nil))))

(DEFUN OUT32 (FILE WORD)
  (OUT16 FILE (LDB #o2020 WORD))		;Note non-standard order of 16-bit bytes
  (OUT16 FILE (LDB #o0020 WORD)))

;obsolete entry function
(DEFUN WRITE-MCR (BASE-VERSION-NUMBER)
  (WRITE-MCR-FILE (SEND CONSLP-OUTPUT-PATHNAME :NEW-PATHNAME
					       :CANONICAL-TYPE :CADR-MICROCODE
					       :VERSION VERSION-NUMBER)
		  BASE-VERSION-NUMBER))

(DEFUN WRITE-MCR-FILE (PATHNAME BASE-VERSION-NUMBER)
  (PKG-BIND 'MICRO-ASSEMBLER
    (LET ((*READ-BASE* 8) (*PRINT-BASE* 8)
	  (*NOPOINT T) (*PRINT-RADIX* NIL) (*READTABLE* SI:INITIAL-READTABLE))
      (WITH-OPEN-FILE (FILE PATHNAME :DIRECTION :OUTPUT :CHARACTERS NIL :IF-EXISTS :SUPERSEDE)
	(LET ((CONSLP-OUTPUT-CURRENT-FILEPOS 0)
	      (mcr-held-high-half nil))
	  ;; quux revision 15: the target description names the format (sys: sys;
	  ;; uatarget).  revision 15's is self-describing (appendix a15b.7,
	  ;; write-mcr-sections); the cadr's and revisions 13 and 14 keep mit's
	  ;; sections below, byte for byte, with the target's parameters in place of
	  ;; the word-width and revision tests they replace.
	  (when (eq (target-parameter :mcr-format) :self-describing)
	    (write-mcr-sections file base-version-number))
	  (unless (eq (target-parameter :mcr-format) :self-describing)
	  ;; quux revision 14 (appendix a14.13): the partition's first section is
	  ;; section 6, start 0, one word, the hardware revision, so that prom
	  ;; 2002 refuses a revision-13 microcode and prom 2001 a revision-14 one
	  ;; (it halts at error-bad-section-type).  a revision-13 assembly has none.
;	  (when (and (= *word-width* 40.) (eql *hardware-revision* 14.))
	  (when (target-parameter :mcr-revision-section)
	    (out32 file 6)			;section code
	    (out32 file 0)			;start
	    (out32 file 1)			;one word
;	    (out32 file 14.))			;the hardware revision
	    (out32 file (target-parameter :hardware-revision)))	;the hardware revision
	  (WHEN BASE-VERSION-NUMBER
	    (OUT32 FILE 3)			;a fake main memory block
	    (OUT32 FILE 0)			;blocks to xfer
	    (OUT32 FILE 0)			;normally relative disk block,
						; 0 says base version follows
	    (OUT32 FILE BASE-VERSION-NUMBER))
	  (WRITE-I-MEM I-MEM 1 FILE)
	  (WRITE-D-MEM D-MEM 2 FILE)
	  (WRITE-MICRO-CODE-SYMBOL-AREA-PART-1 FILE)
;	  (WRITE-A-MEM A-MEM 4 FILE)
	  ;; quux: at 40. bits a memory is section 5, two words a location
	  ;; (contract g2's appendix a1.12, q-a1g); section 4 is 32 bits a
	  ;; location, and prom 2001 halts on it.
;	  (write-a-mem a-mem (if (= *word-width* 40.) 5 4) file)
	  (write-a-mem a-mem (target-parameter :mcr-a-memory-section) file)
	  (WRITE-MICRO-CODE-SYMBOL-AREA-PART-2 FILE))
	  ;; quux: partition order ends on a whole block, 1000 halves, and
	  ;; with no half of a word left held.
	  (when *mcr-partition-order*
	    (do () ((zerop (\ conslp-output-current-filepos 1000)))
	      (out16 file 0))
	    (when mcr-held-high-half
	      (ferror nil "Half a word left over in partition order")))))
      (WRITE-SYMBOL-TABLE-FILE (SEND PATHNAME :NEW-CANONICAL-TYPE :CADR-MICROCODE-SYMBOLS)))))

(DEFUN WRITE-D-MEM (ARRAY CODE FILE)
  (OUT32 FILE CODE)				;Code for this kind of section.
  (OUT32 FILE 0)				;Start address.
  (LET ((SIZE (ARRAY-LENGTH ARRAY)))
    (OUT32 FILE SIZE)
    (DO ((I 0 (1+ I))) ((= I SIZE))
      (LET ((VAL (OR (AREF ARRAY I) 0)))
	(OUT16 FILE				;High bit and parity bit
	       (DPB (DO ((COUNT 17. (1- COUNT))
			 (X VAL (LOGXOR VAL (LSH X -1))))
			((= COUNT 0)
			 (LOGXOR 1 X)))		;ODD PARITY
		    0101
		    (LDB 2001 VAL)))
	(OUT16 FILE VAL)			;Low 16 bits
	))))

(DEFUN WRITE-A-MEM (A-ARRAY CODE FILE)
  (OUT32 FILE CODE)				;Code for this kind of section.
  (OUT32 FILE 0)				;Start address.
  (LET ((SIZE (ARRAY-LENGTH A-ARRAY)))
    (OUT32 FILE SIZE)
    (DO ((I 0 (1+ I))) ((= I SIZE))
;      (OUT32 FILE (OR (AREF A-ARRAY I) 0)))))
      ;; quux: section 5 (40. bits) puts out each location as <31:0> and
      ;; then <39:32> in the low byte of a second word, its <31:8> zero
      ;; (a1.12); section 4 as the one word it was.
      (let ((word (or (aref a-array i) 0)))
	(cond ((= code 5)
	       (out32 file word)		;out32 puts out <31:0> alone
	       (out32 file (ldb 4010 word)))
	      (t (out32 file word)))))))

(DEFUN WRITE-I-MEM (ARRAY CODE FILE)
  (OUT32 FILE CODE)				;Code for this kind of section.
  (OUT32 FILE 0)				;Start address.
  (LET ((SIZE (ARRAY-LENGTH ARRAY)) (TEM))
    (DO () ((NOT (NULL (AREF ARRAY (1- SIZE)))))
      (SETQ SIZE (1- SIZE)))
    (OUT32 FILE SIZE)
    (DO I 0 (1+ I) (= I SIZE)
	(SETQ TEM (OR (AREF ARRAY I) 0))
	(OUT16 FILE (LDB 6020 TEM))		;A high
	(OUT16 FILE (LDB 4020 TEM))		;A low
	(OUT16 FILE (LDB 2020 TEM))		;M high
	(OUT16 FILE (LDB 0020 TEM))		;M low
	)))

(DEFUN WRITE-MICRO-CODE-SYMBOL-AREA-PART-1 (FILE)
  (OUT32 FILE 3)				;Code for main mem section.
  ;; 400 words are one 1 kbyte block of the .mcr file, not a page (with
  ;; 1024-word pages, contract g2 option (w), a page is four such blocks)
  (OUT32 FILE (TRUNCATE (ARRAY-LENGTH MICRO-CODE-SYMBOL-IMAGE) 400))	;# of blocks
  (SETQ CONSLP-OUTPUT-SYMBOL-PREDICTED-FILEPOS
	(+ CONSLP-OUTPUT-CURRENT-FILEPOS
	   4					;rest of this block
	   6					;A/M header
;	   4000					;A/M data
	   ;; quux: A/M data, 2000 locations of two halves, or at 40. bits of
	   ;; four (section 5, two words a location).
;	   (if (= *word-width* 40.) 10000 4000)
	   ;; quux revision 15: by the target's a memory section and size.
	   (* (target-parameter :a-memory-words)
	      (if (eql (target-parameter :mcr-a-memory-section) 5) 4 2))
	   ))
  ;; Rel disk block #
  (OUT32 FILE (TRUNCATE (+ CONSLP-OUTPUT-SYMBOL-PREDICTED-FILEPOS 777) 1000))
  ;; Phys mem address
  (OUT32 FILE (CONS-DUMP-FIND-AREA-ORIGIN 'MICRO-CODE-SYMBOL-AREA)))

;Call this after everything else, to put the micro code symbol area at the end
(DEFUN WRITE-MICRO-CODE-SYMBOL-AREA-PART-2 (FILE)
  (UNLESS (= CONSLP-OUTPUT-CURRENT-FILEPOS CONSLP-OUTPUT-SYMBOL-PREDICTED-FILEPOS)
    (FERROR NIL "Lossage"))
  (DO ((N (\ CONSLP-OUTPUT-CURRENT-FILEPOS 1000) (1+ N)))
      ((OR (ZEROP N) (= N 1000)))		;Pad to page boundary
    (OUT16 FILE 0))
  (LET ((ARRAY MICRO-CODE-SYMBOL-IMAGE))
    (DO ((I 0 (1+ I))
	 (N (ARRAY-LENGTH ARRAY))
;	 (FIXNUM-DATA-TYPE (DPB DTP-FIX %%Q-DATA-TYPE 0)))
	 ;; quux (40-bit words): each entry is written as its value alone.  the
	 ;; tag added here was the assembling world's: a 32-bit world puts
	 ;; dtp-fix in <29:25>, which on the 40-bit machine are the pointer's
	 ;; bits, so every entry read as its address plus 1200000000 (ma-info
	 ;; printed "ucode adr 1200006130" for 6130), and a 40-bit world puts it
	 ;; above the file's 32 bits; the same sources so gave two files.  the
	 ;; disk read puts tag 005 above <31:0> itself.  a 32-bit target keeps
	 ;; the tag in its word, as before.
;	 (fixnum-data-type (if (= *word-width* 40.) 0 (dpb dtp-fix %%q-data-type 0))))
	 ;; quux revision 15: the tag is the target description's own, dtp-fix in
	 ;; the target's data-type field, not the assembling world's dtp-fix and
	 ;; %%q-data-type, which the compiler took from the world it ran in: a
	 ;; 32-bit target's tag is the same from any world.
	 (fixnum-data-type (if (target-parameter :mcr-symbol-area-tag)
			       (dpb (target-parameter :fixnum-tag) (target-parameter :data-type-field) 0)
			     0)))
	((NOT (< I N)))
      (OUT32 FILE (+ FIXNUM-DATA-TYPE (OR (AREF ARRAY I) 0))))))

;; quux revision 15 (contract g3 revision 15, 7; appendix a15b.7): the
;; self-describing .mcr, so that a loader reads every section's shape from the
;; file and refuses one that is not its machine's.  little-endian 32-bit words,
;; partition order: a file header of two words, the format word and the number
;; of sections; then each section an 8-word header (0 the type, 1 the number
;; of items, 2 the actual width in bits, 3 the storage width in bits, a
;; multiple of 32, 4 the start address, 5-7 zero) and exactly items times the
;; storage width in bits, each item least significant word first with zeros
;; from its actual width up; then zeros to the block's end (write-mcr-file).
;; every number is the target description's (sys: sys; uatarget), and an item
;; wider than its actual width, or a control store section where the loaders
;; refuse it, is refused here rather than written.
(defun write-mcr-sections (file base-version-number)
  (unless *mcr-partition-order*
    (ferror nil "The self-describing .mcr is written in partition order only (appendix a15b.7)."))
  (when base-version-number
    (ferror nil "A base version ~D, an incremental assembly's, has no place in the self-describing .mcr (appendix a15b.7)."
	    base-version-number))
  (let ((sections (target-parameter :mcr-sections)))
    (out32 file (target-parameter :mcr-format-word))
    (out32 file (length sections))
    (dolist (section sections)
      (write-mcr-section file (first section) (second section) (third section)))))

(defun write-mcr-section (file type actual storage)
  "Writes the section TYPE of the self-describing .mcr: its 8-word header and its items, each
ACTUAL bits wide in STORAGE bits."
  (unless (and (zerop (\ storage 32.)) (>= storage actual))
    (ferror nil "Section ~D's storage width ~D is not a multiple of 32 at least its actual width ~D."
	    type storage actual))
  (multiple-value-bind (start count) (mcr-section-extent type)
    (out32 file type)
    (out32 file count)
    (out32 file actual)
    (out32 file storage)
    (out32 file start)
    (out32 file 0)
    (out32 file 0)
    (out32 file 0)
    (let ((limit (expt 2 actual)))
      (dotimes (i count)
	(let ((item (mcr-section-item type start i)))
	  (unless (and (>= item 0) (< item limit))
	    (ferror nil "Section ~D's item ~O, ~O, does not fit its actual width, ~D bits."
		    type (+ start i) item actual))
	  ;; out32 puts out <31:0> alone, by 16-bit bytes: an ldb of 32 bits
	  ;; would not fit a fixnum
	  (dotimes (k (truncate storage 32.))
	    (out32 file (ash item (- (* 32. k))))))))))

(defun mcr-section-extent (type)
  "The start address and the number of items of the section TYPE, as two values."
  (selectq type
    (6 (values 0 1))
    (1 (let ((first nil) (end 0))
	 (dotimes (i (array-length i-mem))
	   (when (aref i-mem i)
	     (or first (setq first i))
	     (setq end (1+ i))))
	 (check-control-store-section (or first 0) end)
	 (values (or first 0) (- end (or first 0)))))
    (2 (values 0 (array-length d-mem)))
    (3 (values (cons-dump-find-area-origin 'micro-code-symbol-area)
	       (array-length micro-code-symbol-image)))
    (4 (values 0 (array-length a-mem)))
    (otherwise (ferror nil "~D is no section type of the self-describing .mcr." type))))

(defun mcr-section-item (type start i)
  "The item at index I of the section TYPE, which starts at START."
  (selectq type
    ;; the hardware revision
    (6 (target-parameter :hardware-revision))
    ;; the control store word, its extension in <63:48>
    (1 (or (aref i-mem (+ start i)) 0))
    ;; the dispatch memory entry, <16:0>, with odd parity in <17>
    (2 (let ((entry (ldb 0021 (or (aref d-mem i) 0))))
	 (dpb (d-mem-odd-parity entry) 2101 entry)))
    ;; the symbol area's word: a fixnum, the target's tag over the value
    (3 (let ((v (or (aref micro-code-symbol-image i) 0)))
	 (unless (and (>= v 0) (< v (expt 2 32.)))
	   (ferror nil "The symbol area's word ~O, ~O, is no fixnum's 32-bit value." i v))
	 (dpb (target-parameter :fixnum-tag) (target-parameter :data-type-field) v)))
    ;; the a or m memory word
    (4 (or (aref a-mem i) 0))))

(defun d-mem-odd-parity (entry)
  "The bit that gives the 17-bit dispatch memory ENTRY odd parity, as write-d-mem computes it."
  (do ((bits entry (lsh bits -1))
       (parity 1 (logxor parity (logand bits 1)))
       (count 17. (1- count)))
      ((zerop count) parity)))

(defun check-control-store-section (start end)
  "Refuses a control store section the loaders refuse (appendix a15b.7): the microcode's past
the PROM, or the PROM's own file other than from the PROM's base for at most its words."
  (let ((base (target-parameter :prom-base)) (words (target-parameter :prom-words)))
    (cond ((>= start end)
	   (ferror nil "The control store section is empty."))
	  ((null base))
	  ((< start base)
	   (when (> end base)
	     (ferror nil "The microcode's control store runs from ~O to ~O, into the PROM at ~O."
		     start end base)))
	  ((or (not (= start base)) (> end (+ base words)))
	   (ferror nil "The PROM's control store runs from ~O to ~O, not within ~O to ~O."
		   start end base (+ base words))))))

(PROCLAIM '(SPECIAL I-MEM-LOC D-MEM-LOC A-MEM-LOC M-MEM-LOC 
		    A-CONSTANT-LOC A-CONSTANT-BASE M-CONSTANT-LOC M-CONSTANT-BASE 
		    D-MEM-FREE-BLOCKS M-CONSTANT-LIST A-CONSTANT-LIST))

;This writes an ascii file containing the symbol table
(DEFUN WRITE-SYMBOL-TABLE-FILE (PATHNAME)
  (LET ((*READ-BASE* 8) (*PRINT-BASE* 8)
	(*NOPOINT T) (*PRINT-RADIX* NIL) (*READTABLE* SI:INITIAL-READTABLE))
    (WITH-OPEN-FILE (OUT-FILE PATHNAME :DIRECTION :OUTPUT :CHARACTERS T :IF-EXISTS :SUPERSEDE)
      (PRINT -4 OUT-FILE)			;ASSEMBLER STATE INFO
      (PRINT (MAKE-ASSEMBLER-STATE-LIST) OUT-FILE)
      (PRINT -2 OUT-FILE)
      (CONS-DUMP-SYMBOLS OUT-FILE)
      (PRINT -1 OUT-FILE)			;EOF
      )))

(DEFUN MAKE-CONSTANT-LIST (LST)			;FLUSH USAGE COUNT, LAST LOCN REF'ED AT.
  (MAPCAR #'(LAMBDA (X) (LIST (CAR X) (CADR X)))
	  LST))

;CONS-DUMP-SYMBOLS IN CDMP
