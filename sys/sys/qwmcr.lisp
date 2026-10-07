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
	  ;; quux revision 14 (appendix a14.13): the partition's first section is
	  ;; section 6, start 0, one word, the hardware revision, so that prom
	  ;; 2002 refuses a revision-13 microcode and prom 2001 a revision-14 one
	  ;; (it halts at error-bad-section-type).  a revision-13 assembly has none.
	  (when (and (= *word-width* 40.) (eql *hardware-revision* 14.))
	    (out32 file 6)			;section code
	    (out32 file 0)			;start
	    (out32 file 1)			;one word
	    (out32 file 14.))			;the hardware revision
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
	  (write-a-mem a-mem (if (= *word-width* 40.) 5 4) file)
	  (WRITE-MICRO-CODE-SYMBOL-AREA-PART-2 FILE)
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
	   (if (= *word-width* 40.) 10000 4000)
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
	 (fixnum-data-type (if (= *word-width* 40.) 0 (dpb dtp-fix %%q-data-type 0))))
	((NOT (< I N)))
      (OUT32 FILE (+ FIXNUM-DATA-TYPE (OR (AREF ARRAY I) 0))))))

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
