;;; Disk pack editor.	-*- Mode: LISP; Package: CC; Base: 8  -*-
;	** (c) Copyright 1980 Massachusetts Institute of Technology **
;;; Reading and writing disk labels over the debugging interface.
;;; There used to also be a label editor, but (SI:EDIT-DISK-LABEL "CC") is better.

(DEFMACRO READ-MEMORY (ADDR)
    `(PHYS-MEM-READ ,ADDR))

(DEFMACRO WRITE-MEMORY (ADDR VALUE)
    `(PHYS-MEM-WRITE ,ADDR ,VALUE))

;;; Magic constants and global variables.

;;; LOWCORE and HIGHCORE are the range of physical memory to use, as page numbers.
;;; They are chosen to stay out of low core which contains, among other things,
;;; the command list for the disk controller, and to assume that there might
;;; be as little as 48k of memory.
(DECLARE (SPECIAL LOWCORE HIGHCORE))
(SETQ LOWCORE 10 HIGHCORE 300)

;;; Known pack types.  The first on this list is the default.
;;; Each element is a 4-list of
;;;   Pack brand name (32 or fewer chars) (as a symbol).
;;;   Number of cylinders.
;;;   Number of heads.
;;;   Number of blocks per track.
(DECLARE (SPECIAL PACK-TYPES))
(SETQ PACK-TYPES
      '((|Trident T-80| 815. 5. 17.)
	(|Trident T-300| 815. 19. 17.)
	))

;;; Global variables defining the label.
(DECLARE
 (SPECIAL
  LABEL-CHECK-WORD	   ; ASCII \LABL\
  LABEL-VERSION-NUMBER	   ; 1
  N-CYLINDERS		   ; The next four are parameters of the type of pack.
  N-HEADS
  N-BLOCKS-PER-TRACK
  INITIAL-MCR-NAME
  INITIAL-LOD-NAME
  PACK-BRAND-NAME	   ; 32 chars ascii
  PACK-NAME		   ; 32 chars ascii
  PACK-COMMENT		   ; 96 chars ascii
  N-PARTITIONS		   ; Number of partitions
  N-WORDS-PER-PARTITION-DESCRIPTOR
  PARTITION-NAMES	   ; The next four are arrays, indexed by partition number.
  PARTITION-START
  PARTITION-SIZE
  PARTITION-COMMENTS))

;;; Utility functions.

(DEFUN READ-STRING (NCHARS *ADDR)
   (DO ((WORDS (TRUNCATE (+ NCHARS 3) 4) (1- WORDS))
	(ADDR *ADDR (1+ ADDR))
	(L NIL))
       ((ZEROP WORDS)
	(PKG-BIND 'CADR
	  (IMPLODE (NREVERSE L))))
     (DECLARE (FIXNUM WORDS ADDR))
     (DO ((WORD (READ-MEMORY ADDR) (#Q ASH #M LSH WORD -10))
	  (CH)
	  (I (COND ((= WORDS 1) (1+ (\ (1- NCHARS) 4))) (T 4)) (1- I)))
	 ((ZEROP I))
       (DECLARE (FIXNUM WORD I CH))
       (SETQ CH (LOGAND 377 WORD))
       (OR (= CH 200) (= CH 0)
	   (SETQ L (CONS CH L))))))

(DEFUN WRITE-STRING (NCHARS *ADDR STRING)
   (DO ((ADDR *ADDR (1+ ADDR))
	(PNAME (GET-PNAME STRING))
	(N 0))
       ((NOT (< N NCHARS)))
     (DO ((WORD 0)
	  (SHIFT 0 (+ SHIFT 10)))
	 ((= SHIFT 40)
	  (WRITE-MEMORY ADDR WORD))
       (LET ((CHAR (COND ((< N NCHARS)
			  (AREF PNAME N))
			 (T 0)))) 
	 (SETQ WORD (+ WORD (ASH CHAR SHIFT)))
	 (SETQ N (1+ N))))))

(DEFUN GET-FIXNUM (PROMPT)
   (DO () (NIL)
     (AND PROMPT (PRINC PROMPT))
     (TYO 40)
     (LET ((X (READ)))
        (COND ((FIXP X)
	       (RETURN X))
	      (T (PRINC '| (Please type a fixnum.) |))))))

;;; Manipulating the label of the pack.

;This creates an in-core label that happens to be close to what we currently want.
(DEFUN INITIALIZE-LABEL (PACK-TYPE)
  (SETQ LABEL-CHECK-WORD '|LABL|
	 LABEL-VERSION-NUMBER 1
	 N-CYLINDERS (CADR PACK-TYPE)
	 N-HEADS (CADDR PACK-TYPE)
	 N-BLOCKS-PER-TRACK (CADDDR PACK-TYPE)
	 INITIAL-MCR-NAME '|MCR1|
	 INITIAL-LOD-NAME '|LOD1|
	 PACK-BRAND-NAME (CAR PACK-TYPE)
	 PACK-NAME '||
	 PACK-COMMENT '|(Initial dummy setup)|
	 N-PARTITIONS 10.
	 N-WORDS-PER-PARTITION-DESCRIPTOR 7
	 PARTITION-NAMES (*ARRAY NIL T 100)
	 PARTITION-START (*ARRAY NIL 'FIXNUM 100)
	 PARTITION-SIZE (*ARRAY NIL 'FIXNUM 100)
	 PARTITION-COMMENTS (*ARRAY NIL T 100))
   (FILLARRAY PARTITION-NAMES '(MCR1 MCR2 PAGE LOD1 LOD2 LOD3 LOD4 LOD5 LOD6 LOD7 NIL))
   (FILLARRAY PARTITION-START '(21 245 524 21210 41674 62360 103044 123530 144214 164700 0))
   (FILLARRAY PARTITION-SIZE '(224 224 20464 20464 20464 20464 20464 20464 20464 20464 0))
   (FILLARRAY PARTITION-COMMENTS '(NIL NIL NIL NIL NIL NIL NIL NIL NIL NIL NIL)))

(INITIALIZE-LABEL (CAR PACK-TYPES)) ;Make sure reasonable crud exists when first loaded

(DEFUN READ-LABEL ()
  "Load up our data structures to have what we read through the debugging cables."
  (CC-DISK-WRITE 1 LOWCORE 1) ;Save on block 1
  (CC-DISK-READ 0 LOWCORE 1)
  (READ-LABEL-1 LOWCORE)
  (CC-DISK-READ 1 LOWCORE 1) ;Restore saved core
  T)

(DEFUN READ-LABEL-1 (LOWCORE)
  "Initialize the label parameters from block LOWCORE in debugged machine's mem.
This is used when reading or writing that machine's label."
  (LET ((B (* LOWCORE 400)))
    (DECLARE (FIXNUM B))
    (SETQ LABEL-CHECK-WORD (READ-STRING 4 B)
	  LABEL-VERSION-NUMBER (READ-MEMORY (1+ B))
	  N-CYLINDERS (READ-MEMORY (+ B 2))
	  N-HEADS (READ-MEMORY (+ B 3))
	  N-BLOCKS-PER-TRACK (READ-MEMORY (+ B 4))
	  INITIAL-MCR-NAME (READ-STRING 4 (+ B 6))
	  INITIAL-LOD-NAME (READ-STRING 4 (+ B 7))
	  PACK-BRAND-NAME (READ-STRING 32. (+ B 10))
	  PACK-NAME (READ-STRING 32. (+ B 20))
	  PACK-COMMENT (READ-STRING 96. (+ B 30))
	  N-PARTITIONS (READ-MEMORY (+ B 200))
	  N-WORDS-PER-PARTITION-DESCRIPTOR (READ-MEMORY (+ B 201)))
    (PRINT-LABEL-WARNINGS)
    (DO ((I 0 (1+ I))
	 (ADDR (+ B 202) (+ ADDR N-WORDS-PER-PARTITION-DESCRIPTOR)))
	((= I N-PARTITIONS))
      (DECLARE (FIXNUM I ADDR))
      (AND (> N-WORDS-PER-PARTITION-DESCRIPTOR 0)
	   (STORE (ARRAYCALL T PARTITION-NAMES I) (READ-STRING 4 ADDR)))
      (AND (> N-WORDS-PER-PARTITION-DESCRIPTOR 1)
	   (STORE (ARRAYCALL FIXNUM PARTITION-START I) (READ-MEMORY (1+ ADDR))))
      (AND (> N-WORDS-PER-PARTITION-DESCRIPTOR 2)
	   (STORE (ARRAYCALL FIXNUM PARTITION-SIZE I) (READ-MEMORY (+ 2 ADDR))))
      (AND (> N-WORDS-PER-PARTITION-DESCRIPTOR 3)
	   (STORE (ARRAYCALL T PARTITION-COMMENTS I) (READ-STRING 16. (+ 3 ADDR)))))
  (SORT-PARTITIONS)))

(DEFUN PRINT-LABEL-WARNINGS ()
  "Warn the user if some aspects of the disk and label appear to be out of synch."
   (LET ((ERROR-P NIL))
     (COND ((NOT (STRING-EQUAL LABEL-CHECK-WORD "LABL"))
	    (FORMAT T "Warning: Label check word is /"~A/", not /"LABL/".~%"
		      LABEL-CHECK-WORD)
	    (SETQ ERROR-P T)))
     (COND ((NOT (= LABEL-VERSION-NUMBER 1))
	    (FORMAT T "Warning: Label version number is ~D., not 1.~%"
		      LABEL-VERSION-NUMBER)
	    (SETQ ERROR-P T)))
     (COND ((NOT (= N-WORDS-PER-PARTITION-DESCRIPTOR 7))
	    (FORMAT T "Warning: Number of words per partition descriptor is ~D., not 7.~%"
		      N-WORDS-PER-PARTITION-DESCRIPTOR)
	    (SETQ ERROR-P T)))
     ERROR-P))

(DEFUN WRITE-LABEL ()
  "Save the current state of what the disk label for the machine being debugged by writing it out"
    (COND ((NOT (Y-OR-N-P "Do you really want to write the label? "))
	   (ferror nil "I guess you don't.")))
    (COND ((NOT (EQ LABEL-CHECK-WORD '|LABL|))
	   (OR (Y-OR-N-P "Current label was clobbered, go ahead anyway? ")
	       (FERROR NIL "No, don't go ahead."))
	   (SETQ LABEL-CHECK-WORD '|LABL|)
	   ))
    (COND ((NOT (= LABEL-VERSION-NUMBER 1))
	   (FORMAT T "Current version number is ~D, not 1; " LABEL-VERSION-NUMBER)
	   (SETQ LABEL-VERSION-NUMBER (GET-FIXNUM "write what version number? "))))
    (COND ((NOT (= N-WORDS-PER-PARTITION-DESCRIPTOR 7))
	   (FORMAT T "Current n-words-per-partition-descriptor is ~D., not 7; "
		   N-WORDS-PER-PARTITION-DESCRIPTOR)
	   (SETQ N-WORDS-PER-PARTITION-DESCRIPTOR
		 (GET-FIXNUM "use what number: "))))
    (CC-DISK-WRITE 1 LOWCORE 1) ;Save on block 1
    (LET ((B (* LOWCORE 400)))
      (DECLARE (FIXNUM B))
      (WRITE-STRING 4 B LABEL-CHECK-WORD)
      (WRITE-MEMORY (1+ B) LABEL-VERSION-NUMBER)
      (WRITE-MEMORY (+ 2 B) N-CYLINDERS)
      (WRITE-MEMORY (+ 3 B) N-HEADS)
      (WRITE-MEMORY (+ 4 B) N-BLOCKS-PER-TRACK)
      (WRITE-MEMORY (+ 5 B) (* N-BLOCKS-PER-TRACK N-HEADS))
      (WRITE-STRING 4 (+ 6 B) INITIAL-MCR-NAME)
      (WRITE-STRING 4 (+ 7 B) INITIAL-LOD-NAME)
      (WRITE-STRING 32. (+ 10 B) PACK-BRAND-NAME)
      (WRITE-STRING 32. (+ 20 B) PACK-NAME)
      (WRITE-STRING 96. (+ 30 B) PACK-COMMENT)
      (WRITE-MEMORY (+ 200 B) N-PARTITIONS)
      (WRITE-MEMORY (+ 201 B) N-WORDS-PER-PARTITION-DESCRIPTOR)
      (DO ((I 0 (1+ I))
	   (ADDR (+ B 202) (+ ADDR N-WORDS-PER-PARTITION-DESCRIPTOR)))
	  ((= I N-PARTITIONS))
	(DECLARE (FIXNUM I ADDR))
	(AND (> N-WORDS-PER-PARTITION-DESCRIPTOR 0)
	     (WRITE-STRING 4 ADDR (ARRAYCALL T PARTITION-NAMES I)))
	(AND (> N-WORDS-PER-PARTITION-DESCRIPTOR 1)
	     (WRITE-MEMORY (1+ ADDR) (ARRAYCALL FIXNUM PARTITION-START I)))
	(AND (> N-WORDS-PER-PARTITION-DESCRIPTOR 2)
	     (WRITE-MEMORY (+ 2 ADDR) (ARRAYCALL FIXNUM PARTITION-SIZE I)))
	(AND (> N-WORDS-PER-PARTITION-DESCRIPTOR 3)
	     (WRITE-STRING 16. (+ 3 ADDR) (ARRAYCALL T PARTITION-COMMENTS I)))
	(DO ((J 7 (1+ J)))
	    ((NOT (< J N-WORDS-PER-PARTITION-DESCRIPTOR)))
	  (WRITE-MEMORY (+ J ADDR) 0))))
    (CC-DISK-WRITE 0 LOWCORE 1)
    (CC-DISK-READ 1 LOWCORE 1)
    NIL)

(DEFUN SORT-PARTITIONS ()
  "Arrange the disk partitions to be in canonical order."
    (DO I 0 (1+ I) (>= I N-PARTITIONS)
      (DO J (1+ I) (1+ J) (>= J N-PARTITIONS)
	(COND ((> (ARRAYCALL FIXNUM PARTITION-START I)
		  (ARRAYCALL FIXNUM PARTITION-START J))
	       (LET ((X (ARRAYCALL FIXNUM PARTITION-START I)))
		 (DECLARE (FIXNUM X))
		 (STORE (ARRAYCALL FIXNUM PARTITION-START I)
			(ARRAYCALL FIXNUM PARTITION-START J))
		 (STORE (ARRAYCALL FIXNUM PARTITION-START J) X))
	       (LET ((X (ARRAYCALL FIXNUM PARTITION-SIZE I)))
		 (DECLARE (FIXNUM X))
		 (STORE (ARRAYCALL FIXNUM PARTITION-SIZE I)
			(ARRAYCALL FIXNUM PARTITION-SIZE J))
		 (STORE (ARRAYCALL FIXNUM PARTITION-SIZE J) X))
	       (LET ((X (ARRAYCALL T PARTITION-NAMES I)))
		 (STORE (ARRAYCALL T PARTITION-NAMES I)
			(ARRAYCALL T PARTITION-NAMES J))
		 (STORE (ARRAYCALL T PARTITION-NAMES J) X))
	       (LET ((X (ARRAYCALL T PARTITION-COMMENTS I)))
		 (STORE (ARRAYCALL T PARTITION-COMMENTS I)
			(ARRAYCALL T PARTITION-COMMENTS J))
		 (STORE (ARRAYCALL T PARTITION-COMMENTS J) X)))))))

(DEFUN CC-SET-CURRENT-MICROLOAD (PART)
  "Change the current version of microcode on the machine being debugged to be PART."
  (COND ((NUMBERP PART) (SETQ PART (INTERN (STRING-APPEND "MCR" (+ PART #/0)) 'CADR))))
  (OR (STRING-EQUAL PART "MCR" 0 0 3)
      (ERROR '|Partition name should be MCRn| PART))
  (READ-LABEL)
  (SETQ INITIAL-MCR-NAME PART)
  (WRITE-LABEL))

(DEFUN CC-SET-CURRENT-BAND (PART)
  "Change the current LOD partion of the machine being debugged."
  (COND ((NUMBERP PART) (SETQ PART (INTERN (STRING-APPEND "LOD" (+ PART #/0)) 'CADR))))
  (OR (STRING-EQUAL PART "LOD" 0 0 3)
      (ERROR '|Partition name should be among LOD1...LOD7| PART))
  (READ-LABEL)
  (SETQ INITIAL-LOD-NAME PART)
  (WRITE-LABEL))

;;; Only works on the real machine.
(DEFUN CC-PRINT-DISK-LABEL ()  ;This is what I always think it is named. -- DLW
  "Show what the disk label is on the machine that is connected via debugging cables."
  (PRINT-DISK-LABEL "CC"))
