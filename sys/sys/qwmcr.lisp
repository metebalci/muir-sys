;-*- Mode:LISP; Package:MICRO-ASSEMBLER; Base:8; Readtable:T -*-

;Write out the output of CONSLP.
;This is the Lisp machine version of WMCR.  It's a different file
;because so much had to be changed.

;For now, the reading side is flushed.  It exists elsewhere anyway, doesn't it?

;An MCR file looks a lot like a microcode partition.  Each 36-bit word
;contains one 32-bit word, left-justified.  (Being left justified makes
;it a whole lot easier to gobble the file with the real machine).
;From the Lisp machine, we write this as 2 16-bit pieces

(DEFVAR CONSLP-OUTPUT-SYMBOL-PREDICTED-FILEPOS)
(DEFVAR CONSLP-OUTPUT-CURRENT-FILEPOS)
(PROCLAIM '(SPECIAL CONSLP-OUTPUT VERSION-NUMBER CONSLP-OUTPUT-PATHNAME))

(DEFUN OUT16 (FILE HALFWORD)
  (INCF CONSLP-OUTPUT-CURRENT-FILEPOS)
  (SEND FILE :TYO HALFWORD))

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
	(LET ((CONSLP-OUTPUT-CURRENT-FILEPOS 0))
	  (WHEN BASE-VERSION-NUMBER
	    (OUT32 FILE 3)			;a fake main memory block
	    (OUT32 FILE 0)			;blocks to xfer
	    (OUT32 FILE 0)			;normally relative disk block,
						; 0 says base version follows
	    (OUT32 FILE BASE-VERSION-NUMBER))
	  (WRITE-I-MEM I-MEM 1 FILE)
	  (WRITE-D-MEM D-MEM 2 FILE)
	  (WRITE-MICRO-CODE-SYMBOL-AREA-PART-1 FILE)
	  (WRITE-A-MEM A-MEM 4 FILE)
	  (WRITE-MICRO-CODE-SYMBOL-AREA-PART-2 FILE)))
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
      (OUT32 FILE (OR (AREF A-ARRAY I) 0)))))

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
  (OUT32 FILE (TRUNCATE (ARRAY-LENGTH MICRO-CODE-SYMBOL-IMAGE) 400))	;# of blocks
  (SETQ CONSLP-OUTPUT-SYMBOL-PREDICTED-FILEPOS
	(+ CONSLP-OUTPUT-CURRENT-FILEPOS
	   4					;rest of this block
	   6					;A/M header
	   4000					;A/M data
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
	 (FIXNUM-DATA-TYPE (DPB DTP-FIX %%Q-DATA-TYPE 0)))
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
