;;; -*- Mode:Lisp; Package:System-Internals; Base:8 -*-

;;; Disk label editor

;;; Simple routines for manipulating own label
;;; These are to be called by the user

(DEFUN SET-CURRENT-MICROLOAD (BAND &OPTIONAL (UNIT 0))
  "Specify the MCR band to be used for loading microload at boot time.
Do PRINT-DISK-LABEL to see what bands are available and what they contain.
UNIT can be a string containing a machine's name, or /"CC/";
then the specified or debugged machine's current microload is set.
The last works even if the debugged machine is down.
UNIT can also be a disk drive number; however, it is the disk on
drive zero which is used for booting."
  (SET-CURRENT-BAND BAND UNIT T))

(DEFUN SET-CURRENT-BAND (BAND &OPTIONAL (UNIT 0) MICRO-P &AUX RQB LABEL-INDEX DONT-DISPOSE)
  "Specify the LOD band to be used for loading the Lisp system at boot time.
If the LOD band you specify goes with a different microcode,
you will be given the option of selecting that microcode as well.  Usually, do so.

Do PRINT-DISK-LABEL to see what bands are available and what they contain.
UNIT can be a string containing a machine's name, or /"CC/";
then the specified or debugged machine's current band is set.
The last works even if the debugged machine is down.
UNIT can also be a disk drive number; however, it is the disk on
drive zero which is used for booting.

Returns T if the band was set as specified, NIL if not
 (probably because user said no to a query)."
  (SETF (VALUES UNIT DONT-DISPOSE)
	(DECODE-UNIT-ARGUMENT UNIT
	         (FORMAT NIL "(SET-CURRENT-~:[BAND~;MICROLOAD~] ~D)" MICRO-P BAND)))
  (UNWIND-PROTECT
   (PROG ((UCODE-NAME (SELECT-PROCESSOR
			(:CADR "MCR")
			(:LAMBDA "LMC"))))
    (SETQ RQB (GET-DISK-LABEL-RQB))
    (SETQ BAND (COND ((OR (SYMBOLP BAND) (STRINGP BAND))
		      (STRING-UPCASE (STRING BAND)))
		     (T (FORMAT NIL "~A~D"
				(COND (MICRO-P UCODE-NAME)
				      (T "LOD"))
				BAND))))
    (MULTIPLE-VALUE (NIL NIL LABEL-INDEX)
      (FIND-DISK-PARTITION-FOR-READ BAND RQB UNIT))	;Does a READ-DISK-LABEL
    (OR (STRING-EQUAL (SUBSTRING BAND 0 3)
		      (IF MICRO-P UCODE-NAME "LOD"))
	(FQUERY NIL "The specified band is not a ~A band.  Select it anyway? "
		(IF MICRO-P UCODE-NAME "LOD"))
	(RETURN NIL))
    (PUT-DISK-STRING RQB BAND (COND (MICRO-P 6) (T 7)) 4)
    (IF (NOT MICRO-P)
	(MULTIPLE-VALUE-BIND (NIL MEMORY-SIZE-OF-BAND UCODE-VERSION-OF-BAND)
	    (MEASURED-SIZE-OF-PARTITION BAND UNIT)
	  (LET ((CURRENT-UCODE-VERSION
		  (GET-UCODE-VERSION-FROM-COMMENT (GET-DISK-STRING RQB 6 4) UNIT RQB T))
		(MACHINE-MEMORY-SIZE
		  (MEASURED-SIZE-OF-PARTITION "PAGE" UNIT)))
	    (AND (> MEMORY-SIZE-OF-BAND MACHINE-MEMORY-SIZE)
		 (NOT (FQUERY NIL "~A requires a ~D block PAGE partition, but there is only ~D.  Select ~A anyway? "
			      BAND MEMORY-SIZE-OF-BAND MACHINE-MEMORY-SIZE BAND))
		 (RETURN))
	    (MULTIPLE-VALUE-BIND (BASE-BAND-NAME BASE-BAND-VALID)
		(INC-BAND-BASE-BAND BAND UNIT)
	      (WHEN BASE-BAND-NAME
		(FORMAT T "~%Band ~A is an incremental save with base band ~A."
			BAND BASE-BAND-NAME)
		(UNLESS BASE-BAND-VALID
		  (FORMAT T "~2%It appears that ~A's contents have been changed
 since ~A was dumped.  Therefore, booting ~A may fail to work!"
			  BASE-BAND-NAME BAND BAND)
		  (UNLESS (FQUERY FORMAT:YES-OR-NO-P-OPTIONS "~%Select ~A anyway? "
				  BAND)
		    (RETURN NIL)))))
	    (IF UCODE-VERSION-OF-BAND
		(IF (EQ CURRENT-UCODE-VERSION UCODE-VERSION-OF-BAND)
		    (FORMAT T "~%The new current band ~A should work properly
with the ucode version that is already current." BAND)
		  (LET ((BAND-UCODE-PARTITION
			  (FIND-MICROCODE-PARTITION RQB UCODE-VERSION-OF-BAND)))
		    (IF BAND-UCODE-PARTITION
			(IF (FQUERY NIL "~A goes with ucode ~D, which is not selected.
Partition ~A claims to contain ucode ~D.  Select it? "
				    BAND UCODE-VERSION-OF-BAND
				    BAND-UCODE-PARTITION UCODE-VERSION-OF-BAND)
			    (PUT-DISK-STRING RQB BAND-UCODE-PARTITION 6 4)
			  (UNLESS (FQUERY FORMAT:YES-OR-NO-P-OPTIONS
					  "~2%The machine may fail to boot if ~A is selected
 with the wrong microcode version.  It wants ucode ~D.
Currently ucode version ~D is selected.
Do you know that ~A will run with this ucode? "
					  BAND UCODE-VERSION-OF-BAND
					  CURRENT-UCODE-VERSION BAND)
			    (RETURN NIL)))
		      ;; Band's desired microcode doesn't seem present.
		      (FORMAT T "~%~A claims to go with ucode ~D,
which does not appear to be present on this machine.
It may or may not run with other ucode versions.
Currently ucode ~D is selected."
			      BAND UCODE-VERSION-OF-BAND CURRENT-UCODE-VERSION)
		      (UNLESS (FQUERY FORMAT:YES-OR-NO-P-OPTIONS
				      "~%Should I really select ~A? " BAND)
			(RETURN NIL))))))))
      ;; Here to validate a MCR partition.
      (WHEN (> LABEL-INDEX (- #o400 3))
	(FORMAT T "~%Band ~A may not be selected since it is past the first page of the label.
The bootstrap prom only looks at the first page.  Sorry.")
	(RETURN NIL)))
    (WRITE-DISK-LABEL RQB UNIT)
    (RETURN T))
   (RETURN-DISK-RQB RQB)
   (UNLESS DONT-DISPOSE (DISPOSE-OF-UNIT UNIT))))

(DEFUN FIND-MICROCODE-PARTITION (RQB MICROCODE-VERSION
				 &AUX N-PARTITIONS WORDS-PER-PART DESIRED-COMMENT)
  (SETQ DESIRED-COMMENT (FORMAT NIL "~A ~D"
				(select-processor
				  (:cadr "UCADR")
				  (:lambda "ULAMBDA"))
				MICROCODE-VERSION))
  (SETQ N-PARTITIONS (GET-DISK-FIXNUM RQB 200))
  (SETQ WORDS-PER-PART (GET-DISK-FIXNUM RQB 201))
  (IF ( WORDS-PER-PART 3)			;Partition comment
      NIL
    (DO ((I 0 (1+ I))
	 (PARTITION-NAME)
	 (COMMENT)
	 (LEN (STRING-LENGTH DESIRED-COMMENT))
	 (LOC #o202 (+ LOC WORDS-PER-PART)))
	((OR (= I N-PARTITIONS)
	     ;; Bootstrap prom only searches first label page,
	     ;; so don't consider any MCR partitions outside that!
	     (> (+ LOC WORDS-PER-PART) #o400)))
      (SETQ PARTITION-NAME (GET-DISK-STRING RQB LOC 4))
      (SETQ COMMENT (GET-DISK-STRING RQB (+ LOC 3) 16.))
      (AND (STRING-EQUAL PARTITION-NAME (select-processor
					  (:cadr "MCR")
					  (:lambda "LMC"))
			 0 0 3 3)
	   (STRING-EQUAL COMMENT DESIRED-COMMENT 0 0 LEN LEN)
	   (RETURN PARTITION-NAME)))))

(DEFUN CURRENT-MICROLOAD (&OPTIONAL (UNIT 0))
  "Return the name of the current microload band.
UNIT can be a name of a machine, a number of a disk drive,
or a string containing CC."
  (CURRENT-BAND UNIT T))

(DEFUN CURRENT-BAND (&OPTIONAL (UNIT 0) MICRO-P &AUX RQB DONT-DISPOSE)
  "Return the name of the current Lisp system (LOD) band.
UNIT can be a name of a machine, a number of a disk drive,
or a string containing CC."
  (UNWIND-PROTECT
      (PROGN (SETF (VALUES UNIT DONT-DISPOSE) (DECODE-UNIT-ARGUMENT UNIT "Reading Label"))
	     (SETQ RQB (GET-DISK-LABEL-RQB))
	     (READ-DISK-LABEL RQB UNIT)
	     (GET-DISK-STRING RQB (IF MICRO-P 6 7) 4))
    (RETURN-DISK-RQB RQB)			;Doesn't complain for NIL
    (UNLESS DONT-DISPOSE (DISPOSE-OF-UNIT UNIT))))

;;; Copy the label from unit 0 on this machine to unit 0 of the debuggee machine.
;;; You may want to use this right after formatting the debuggee's disk pack.
(DEFUN COPY-DISK-LABEL (&OPTIONAL (FROM-UNIT 0) (TO-UNIT "CC"))
  "Copy the disk label from one unit to another.
A unit can be a disk drive number, the name of a machine (the chaosnet is used)
or /"CC/" meaning the machine being debugged by this one.
The last can be used even if that machine is down."
  (AND (FQUERY FORMAT:YES-OR-NO-P-OPTIONS
	       "Should I really smash the label on unit ~D with a copy of the label from unit ~D?"
	       TO-UNIT FROM-UNIT)
       (LET ((RQB (GET-DISK-LABEL-RQB)))
	 (UNWIND-PROTECT
	   (PROGN (SETQ FROM-UNIT (DECODE-UNIT-ARGUMENT FROM-UNIT "reading label" T NIL)
			TO-UNIT (DECODE-UNIT-ARGUMENT TO-UNIT "writing label" T T))
		  (READ-DISK-LABEL RQB FROM-UNIT)
		  (WRITE-DISK-LABEL RQB TO-UNIT))
	   (DISPOSE-OF-UNIT FROM-UNIT)
	   (DISPOSE-OF-UNIT TO-UNIT)
	   (RETURN-DISK-RQB RQB)))))

(DEFUN PRINT-DISK-LABEL (&OPTIONAL (UNIT 0) (STREAM STANDARD-OUTPUT)
                         &AUX RQB)
  "Print the contents of a disk label.
A unit can be a disk drive number, the name of a machine (the chaosnet is used)
or /"CC/" meaning the machine being debugged by this one.
The last can be used even if that machine is down."
  (SETQ UNIT (DECODE-UNIT-ARGUMENT UNIT "reading label"))
  (UNWIND-PROTECT
   (PROGN (SETQ RQB (GET-DISK-LABEL-RQB))
	  (READ-DISK-LABEL RQB UNIT)
	  (PRINT-DISK-LABEL-FROM-RQB STREAM RQB NIL))
   (RETURN-DISK-RQB RQB))
  (DISPOSE-OF-UNIT UNIT))

(DEFVAR LE-STRUCTURE NIL
  "LE-STRUCTURE is a list of items for the disk-label editor.
Each item looks like: (name value start-x start-y width)")

;;; This is a subroutine for PRINT-DISK-LABEL-FROM-RQB which implements this.
;;; Note that if not consing up a structure, this must work on a non-display stream
(DEFUN LE-OUT (NAME VALUE STREAM CONS-UP-LE-STRUCTURE-P
	       &AUX X Y WIDTH)
  (AND CONS-UP-LE-STRUCTURE-P
       (MULTIPLE-VALUE (X Y) (SEND *TERMINAL-IO* ':READ-CURSORPOS)))
  (FORMAT STREAM "~D" VALUE)
  (WHEN CONS-UP-LE-STRUCTURE-P
    (SETQ WIDTH (- (SEND *TERMINAL-IO* ':READ-CURSORPOS) X))
    (IF (MINUSP WIDTH) (SETQ WIDTH (- (TV:SHEET-INSIDE-RIGHT *TERMINAL-IO*) X))
      (IF (ZEROP WIDTH) (SETQ WIDTH 4)))
    (PUSH (LIST NAME VALUE X Y WIDTH) LE-STRUCTURE))
  NIL)

(DEFUN PRINT-DISK-LABEL-FROM-RQB (STREAM RQB CONS-UP-LE-STRUCTURE-P
				  &AUX N-PARTITIONS WORDS-PER-PART THIS-END NEXT-BASE
				  CURRENT-MICROLOAD CURRENT-BAND)
  (TERPRI STREAM)
  (LE-OUT 'PACK-NAME (GET-DISK-STRING RQB #o20 32.) STREAM CONS-UP-LE-STRUCTURE-P)
  (PRINC ": " STREAM)
  (LE-OUT 'DRIVE-NAME (GET-DISK-STRING RQB #o10 32.) STREAM CONS-UP-LE-STRUCTURE-P)
  (PRINC ", " STREAM)
  (LE-OUT 'COMMENT (GET-DISK-STRING RQB #o30 96.) STREAM CONS-UP-LE-STRUCTURE-P)
  (FORMAT STREAM "~%~A version ~D, "		;You can't edit these
	  (GET-DISK-STRING RQB 0 4) (GET-DISK-FIXNUM RQB 1))
  (LE-OUT 'N-CYLINDERS (GET-DISK-FIXNUM RQB 2) STREAM CONS-UP-LE-STRUCTURE-P)
  (PRINC " cylinders, " STREAM)
  (LE-OUT 'N-HEADS (GET-DISK-FIXNUM RQB 3) STREAM CONS-UP-LE-STRUCTURE-P)
  (PRINC " heads, " STREAM)
  (LE-OUT 'N-BLOCKS-PER-TRACK (GET-DISK-FIXNUM RQB 4) STREAM CONS-UP-LE-STRUCTURE-P)
  (PRINC " blocks//track, " STREAM)
  (FORMAT STREAM "~D" (GET-DISK-FIXNUM RQB 5))
  (PRINC " blocks//cylinder" STREAM)
  (TERPRI STREAM)
  (PRINC "Current microload = " STREAM)
  (LE-OUT 'CURRENT-MICROLOAD (SETQ CURRENT-MICROLOAD (GET-DISK-STRING RQB 6 4))
	  STREAM CONS-UP-LE-STRUCTURE-P)
  (PRINC ", current virtual memory load (band) = " STREAM)
  (LE-OUT 'CURRENT-BAND (SETQ CURRENT-BAND (GET-DISK-STRING RQB 7 4))
	  STREAM CONS-UP-LE-STRUCTURE-P)
  (TERPRI STREAM)
  (LE-OUT 'N-PARTITIONS (SETQ N-PARTITIONS (GET-DISK-FIXNUM RQB #o200))
	  STREAM CONS-UP-LE-STRUCTURE-P)
  (PRINC " partitions, " STREAM)
  (LE-OUT 'WORDS-PER-PART (SETQ WORDS-PER-PART (GET-DISK-FIXNUM RQB #o201))
	  STREAM CONS-UP-LE-STRUCTURE-P)
  (PRINC "-word descriptors:" STREAM)
  (DO ((I 0 (1+ I))
       (PARTITION-NAME)
       (LOC #o202 (+ LOC WORDS-PER-PART)))
      ((= I N-PARTITIONS))
    (SETQ PARTITION-NAME (GET-DISK-STRING RQB LOC 4))
    (IF (OR (STRING-EQUAL PARTITION-NAME CURRENT-MICROLOAD)
	    (STRING-EQUAL PARTITION-NAME CURRENT-BAND))
	(FORMAT STREAM "~%* ")
	(FORMAT STREAM "~%  "))
    (LE-OUT 'PARTITION-NAME (GET-DISK-STRING RQB LOC 4) STREAM CONS-UP-LE-STRUCTURE-P)
    (PRINC " at block " STREAM)
    (LE-OUT 'PARTITION-START (GET-DISK-FIXNUM RQB (1+ LOC)) STREAM CONS-UP-LE-STRUCTURE-P)
    (PRINC ", " STREAM)
    (LE-OUT 'PARTITION-SIZE (GET-DISK-FIXNUM RQB (+ LOC 2)) STREAM CONS-UP-LE-STRUCTURE-P)
    (PRINC " blocks long" STREAM)
    (WHEN (> WORDS-PER-PART 3)			;Partition comment
      (PRINC ", /"" STREAM)
      (LE-OUT 'PARTITION-COMMENT (GET-DISK-STRING RQB (+ LOC 3)
						  (* 4 (- WORDS-PER-PART 3)))
	      STREAM CONS-UP-LE-STRUCTURE-P)
      (TYO #/" STREAM))
    (SETQ THIS-END (+ (GET-DISK-FIXNUM RQB (1+ LOC)) (GET-DISK-FIXNUM RQB (+ LOC 2)))
	  NEXT-BASE (COND ((= (1+ I) N-PARTITIONS)
			   (* (GET-DISK-FIXNUM RQB 2) (GET-DISK-FIXNUM RQB 5)))
			  ((GET-DISK-FIXNUM RQB (+ LOC 1 WORDS-PER-PART)))))
    (COND ((> (- NEXT-BASE THIS-END) 0)
	   (FORMAT STREAM ", ~D blocks free at ~D" (- NEXT-BASE THIS-END) THIS-END))
	  ((< (- NEXT-BASE THIS-END) 0)
	   (FORMAT STREAM ", ~D blocks overlap" (- THIS-END NEXT-BASE))))))

(DEFUN P-BIGNUM (ADR)
  (DPB (%P-LDB #o2020 ADR) #o2020 (%P-LDB #o0020 ADR)))

;;; This will get hairier later, e.g. check for wrap around
;;; Also this only understands the Trident controller I guess
(DEFUN PRINT-DISK-ERROR-LOG ()
  "Print a description of remembered disk errors."
  (FORMAT T "~&Disk error count ~D.~%" (READ-METER 'SYS:%COUNT-DISK-ERRORS))
  (DO ((I #o600 (+ I 4))) ((= I #o640))
    (LET ((CLP-CMD (P-BIGNUM I))
	  (DA (P-BIGNUM (1+ I)))
	  (STS (P-BIGNUM (+ I 2)))
	  (MA (P-BIGNUM (+ I 3))))
      (COND ((NOT (ZEROP CLP-CMD))
	     (FORMAT T "~%Command ~O ~@[(~A) ~]"
		       (LDB #o0020 CLP-CMD)
		       (CDR (ASSQ (LDB #o0004 CLP-CMD) '((0 . "Read")
							 (8 . "Read-Compare")
							 (9 . "Write")))))
	     (AND (BIT-TEST %DISK-COMMAND-DATA-STROBE-EARLY CLP-CMD)
		  (PRINC "Data-Strobe-Early "))
	     (AND (BIT-TEST %DISK-COMMAND-DATA-STROBE-LATE CLP-CMD)
		  (PRINC "Data-Strobe-Late "))
	     (AND (BIT-TEST %DISK-COMMAND-SERVO-OFFSET CLP-CMD)
		  (PRINC "Servo-offset "))
	     (AND (BIT-TEST %DISK-COMMAND-SERVO-OFFSET-FORWARD CLP-CMD)
		  (PRINC "S-O-Forward "))
	     (TERPRI)
	     (FORMAT T "CCW-list pointer ~O (low 16 bits)~%" (LDB #o2020 CLP-CMD))
	     (FORMAT T "Disk address: unit ~O, cylinder ~O, head ~O, block ~O (~4:*~D ~D ~D ~D decimal)~%"
		       (LDB #o3404 DA) (LDB #o2014 DA) (LDB #o1010 DA) (LDB #o0010 DA))
	     (FORMAT T "Memory address: ~O (type bits ~O)~%"
		       (LDB #o0026 MA) (LDB #o2602 MA))
	     (FORMAT T "Status: ~O  ~A~%"
		       STS (DECODE-DISK-STATUS (LDB #o0020 STS) (LDB #o2020 STS))))))))

;;;; Label editor

(DEFVAR LE-ITEM-NUMBER)
(DEFVAR LE-UNIT)
(DEFVAR LE-RQB)

;;; Change n-words-per-partition of a label sitting in an RQB
(DEFUN CHANGE-PARTITION-MAP (RQB NEW-N-WORDS)
  (LET ((OLD-N-WORDS (GET-DISK-FIXNUM RQB 201))
	(N-PARTITIONS (GET-DISK-FIXNUM RQB 200)))
    (LET ((SAVE (MAKE-ARRAY (LIST N-PARTITIONS (MAX OLD-N-WORDS NEW-N-WORDS)))))
      ;; Fill with zeros
      (DOTIMES (I N-PARTITIONS)
	(DOTIMES (J (MAX OLD-N-WORDS NEW-N-WORDS))
	  (ASET 0 SAVE I J)))
      ;; Copy out
      (DOTIMES (I N-PARTITIONS)
	(DOTIMES (J OLD-N-WORDS)
	  (ASET (GET-DISK-FIXNUM RQB (+ #o202 (* I OLD-N-WORDS) J)) SAVE I J)))
      ;; Copy back in
      (PUT-DISK-FIXNUM RQB NEW-N-WORDS #o201)
      (DOTIMES (I N-PARTITIONS)
	(DOTIMES (J NEW-N-WORDS)
	  (PUT-DISK-FIXNUM RQB (AREF SAVE I J) (+ #o202 (* I NEW-N-WORDS) J)))))))

;;; Known pack types.  The first on this list is the default.
;;; Each element is a 4-list of
;;;   Pack brand name (32 or fewer chars) (as a symbol).
;;;   Number of cylinders.
;;;   Number of heads.
;;;   Number of blocks per track.
;;;   Partition list: name, size (- blocks, + cylinders at cyl bndry)
;;;   First partition starts at block 17. (first track reserved)
(DEFVAR PACK-TYPES
	'#o((|Trident T-80| 815. 5. 17.
			    ((MCR1 -224) (MCR2 -224)
			     (PAGE 340.)
			     (LOD1 200.) (LOD2 200.)
			     (FILE 29.)))
	    (|Trident T-300| 815. 19. 17.
			     ((MCR1 -224) (MCR2 -224) (MCR3 -224) (MCR4 -224)
			      (MCR5 -224) (MCR6 -224) (MCR7 -224) (MCR8 -224)
			      (PAGE 202.)	;Full address space
			      (LOD1 75.) (LOD2 75.) (LOD3 75.) (LOD4 75.)
			      (LOD5 75.) (LOD6 75.) (LOD7 75.) (LOD8 75.)
			      (FILE 9.)))
	    (|Fujitsu Eagle| 842. 20. 25.
			     ((LMC1 -224) (LMC2 -224) (LMC3 -224) (LMC4 -224)
			      (LMC5 -224) (LMC6 -224) (LMC7 -224) (LMC8 -224)
			      (PAGE 141.)	;Full address space
			      (FILE 200.)
			      (LOD1 75.) (LOD2 75.) (LOD3 75.) (LOD4 75.)
			      (LOD5 75.) (LOD6 75.) 
			      (METR 9.)))
	    ))

(DEFUN LE-INITIALIZE-LABEL (RQB PACK-TYPE)
  (PUT-DISK-STRING RQB "LABL" 0 4)		;Checkword
  (PUT-DISK-FIXNUM RQB 1 1)			;Version number
  (PUT-DISK-FIXNUM RQB (CADR PACK-TYPE) 2)	;Number of cylinders
  (PUT-DISK-FIXNUM RQB (CADDR PACK-TYPE) 3)	;Number of heads
  (PUT-DISK-FIXNUM RQB (CADDDR PACK-TYPE) 4)	;Blocks per track
  (PUT-DISK-FIXNUM RQB (* (CADDR PACK-TYPE) (CADDDR PACK-TYPE)) 5)
  (PUT-DISK-STRING RQB "MCR1" 6 4)		;Current microload
  (PUT-DISK-STRING RQB "LOD1" 7 4)		;Current band
  (PUT-DISK-STRING RQB (STRING (CAR PACK-TYPE)) 10 40)	;Brand name of drive
  (PUT-DISK-STRING RQB "(name)" #o20 #o40)	;Name of pack
  (PUT-DISK-STRING RQB "(comment)" #o30 #o140)	;Comment
  (PUT-DISK-FIXNUM RQB (LENGTH (FIFTH PACK-TYPE)) #o200) ;Number of partitions
  (PUT-DISK-FIXNUM RQB 7 #o201)			;Words per partition descriptor
  (DO ((LOC #o202 (+ LOC 7))
       (BLOCK (CADDDR PACK-TYPE) (+ BLOCK SZ))
       (SZ)
       (BPC (* (CADDR PACK-TYPE) (CADDDR PACK-TYPE)))
       (PARTS (FIFTH PACK-TYPE) (CDR PARTS)))
      ((NULL PARTS))
    (SETQ SZ (IF (MINUSP (CADAR PARTS))
		 (- (CADAR PARTS))
	       (SETQ BLOCK (* BPC (CEILING BLOCK BPC)))
	       (* (CADAR PARTS) BPC)))
    (PUT-DISK-STRING RQB (STRING (CAAR PARTS)) LOC 4)
    (PUT-DISK-FIXNUM RQB BLOCK (1+ LOC))
    (PUT-DISK-FIXNUM RQB SZ (+ LOC 2))
    (PUT-DISK-STRING RQB "" (+ LOC 3) 16.)))

;;; Display the label which is sitting in an RQB 
(DEFUN LE-DISPLAY-LABEL (RQB UNIT &OPTIONAL NO-PROMPT)
  (SEND *TERMINAL-IO* ':CLEAR-SCREEN)
  (IF (NUMBERP UNIT)
      (FORMAT T "Editing label for unit ~D~%" UNIT)
    (FORMAT T "Editing label for unit ~D on ~A~%"
	    (SEND UNIT ':UNIT-NUMBER)
	    (SEND UNIT ':MACHINE-NAME)))
  (SETQ LE-STRUCTURE NIL)
  (PRINT-DISK-LABEL-FROM-RQB STANDARD-OUTPUT RQB T)
  (SETQ LE-STRUCTURE (NREVERSE LE-STRUCTURE))
  (FORMAT T "~%~%~%")
  (UNLESS NO-PROMPT (PRINC "Label Edit Command: "))
  (SETQ LE-ITEM-NUMBER (MIN LE-ITEM-NUMBER (LENGTH LE-STRUCTURE)))
  (LE-UNDERSCORE))

;;; Underscore the selected item
(DEFUN LE-UNDERSCORE ()
  (LET ((ITEM (NTH LE-ITEM-NUMBER LE-STRUCTURE)))
    (IF ITEM
	(SEND *TERMINAL-IO* ':DRAW-RECTANGLE
	      (FIFTH ITEM) 1
	      (THIRD ITEM) (+ (FOURTH ITEM)
			      (- (TV:SHEET-LINE-HEIGHT *TERMINAL-IO*) 2))
	      TV:ALU-XOR)
      ;; Pointing at the line after the last existing partition.
      (SEND *TERMINAL-IO* ':DRAW-RECTANGLE
	    1 (SEND TERMINAL-IO ':LINE-HEIGHT)
	    0
	    (+ (FOURTH (CAR (LAST LE-STRUCTURE)))
	       (TV:SHEET-LINE-HEIGHT *TERMINAL-IO*))
	    TV:ALU-XOR))))

(DEFVAR LE-SOMETHING-CHANGED NIL "Used to figure out if we've made any editing changes.")

(DEFUN EDIT-DISK-LABEL (&OPTIONAL (LE-UNIT 0) (INIT-P NIL)
					      ;If t, dont try to save page 1 since current
					      ; label is garbage.  It can bomb setting
					      ; blocks-per-track to 0, etc.
			&AUX LE-RQB LE-STRUCTURE (LE-ITEM-NUMBER 0) CH COM ABORT)
  "Edit the label of a disk pack.
LE-UNIT is the disk drive number, or a name of a machine (the chaosnet is used),
or /"CC/" which refers to the machine being debugged by this one."
  (SETQ LE-SOMETHING-CHANGED NIL)		;restart
  (SETQ LE-UNIT (DECODE-UNIT-ARGUMENT LE-UNIT "editing label" INIT-P))
  (UNWIND-PROTECT
     (PROGN (WITHOUT-INTERRUPTS
	     (SETQ LE-RQB (GET-DISK-LABEL-RQB)))
	    (LE-INITIALIZE-LABEL LE-RQB (CAR PACK-TYPES))
	    (LE-DISPLAY-LABEL LE-RQB LE-UNIT T)
	    (FORMAT T "Use Control-R to read and edit existing label; hit HELP for help.~%")
	    (PRINC "Label Edit Command: ")
	    (*CATCH 'LE-EXIT
		    (DO-FOREVER
		      (SETQ CH (SEND *TERMINAL-IO* ':TYI))
		      (SETQ COM (INTERN-SOFT (STRING-UPCASE (FORMAT NIL "LE-COM-~:C" CH))
					     "SI"))
		      (COND ((OR (NULL COM)	;nothing typed
				 (NOT (FBOUNDP COM)))	;command not defined
			     (BEEP)
			     (FORMAT T "~%~:C is not a known edit-disk-label command.  Type ~:C for help, or ~:C to exit." CH #/HELP #/END))
			    (T (MULTIPLE-VALUE (NIL ABORT)
				 (CATCH-ERROR-RESTART ((ERROR SYS:ABORT)
						       "Return to EDIT-DISK-LABEL.")
				   (FUNCALL COM)))
			       (AND ABORT (LE-DISPLAY-LABEL LE-RQB LE-UNIT)))))))
     (RETURN-DISK-RQB LE-RQB)
     (DISPOSE-OF-UNIT LE-UNIT)))

;;; Redisplay
(DEFUN LE-COM-FORM ()
  (LE-DISPLAY-LABEL LE-RQB LE-UNIT))

(DEFUN LE-COM-ABORT ()
  (FORMAT T "~%Type ~:C to exit, or ~:C for help." #/END #/HELP))

;;; Exit
(DEFUN LE-COM-END ()
  (WHEN (OR (NULL LE-SOMETHING-CHANGED)
	    (FQUERY NIL "~&It appears to me that you have not written out your changes.
You must type ~:C to write out your changes before typing ~:C.
Do you still want to exit? " #/CONTROL-W #/END))
    (FORMAT T "~%Exiting the disk label editor.")
    (*THROW 'LE-EXIT NIL)))

(DEFUN LE-COM-META-~ ()
  (FORMAT T "~%No longer modified.")
  (SETQ LE-SOMETHING-CHANGED NIL))

;;; Previous item
(DEFUN LE-COM-CONTROL-B ()
  (LE-UNDERSCORE)
  (SETQ LE-ITEM-NUMBER (MAX 0 (1- LE-ITEM-NUMBER)))
  (LE-UNDERSCORE))

(DEFUN LE-COM-CONTROL-D ()
  (LET ((PLOC (LE-CURRENT-PARTITION)))
    (IF (= LE-ITEM-NUMBER (LENGTH LE-STRUCTURE))
	(BEEP)
      (SI:DESCRIBE-PARTITION (GET-DISK-STRING LE-RQB PLOC 4)))))
	

;;; Next item
(DEFUN LE-COM-CONTROL-F ()
  (LE-UNDERSCORE)
  (SETQ LE-ITEM-NUMBER (MIN (LENGTH LE-STRUCTURE)
			    (1+ LE-ITEM-NUMBER)))
  (LE-UNDERSCORE))

;;; First item on next line
(DEFUN LE-COM-CONTROL-N ()
  (LE-UNDERSCORE)
  (DO ((L (NTHCDR LE-ITEM-NUMBER LE-STRUCTURE) (CDR L))
       (N LE-ITEM-NUMBER (1+ N))
       (Y0 (OR (FOURTH (NTH LE-ITEM-NUMBER LE-STRUCTURE)) 0)))
      ((OR (NULL L) (> (FOURTH (CAR L)) Y0))
       (SETQ LE-ITEM-NUMBER (MIN (LENGTH LE-STRUCTURE) N))
       (LE-UNDERSCORE))))

;;; First item on previous line
(DEFUN LE-COM-CONTROL-P ()
  (LE-UNDERSCORE)
  (DO ((Y0 (OR (FOURTH (NTH LE-ITEM-NUMBER LE-STRUCTURE)) 0))
       (L LE-STRUCTURE (CDR L))
       (N 0 (1+ N))
       (Y) (CAND-Y -1) (CAND-N 0))
      (())
    (SETQ Y (FOURTH (CAR L)))
    (COND ((OR (NULL L) (= Y Y0))
	   (SETQ LE-ITEM-NUMBER CAND-N)
	   (LE-UNDERSCORE)
	   (RETURN NIL))
	  ((= Y CAND-Y) )			;Next thing on same line
	  (T (SETQ CAND-Y Y CAND-N N)))))	;First thing on a line

;;; Read in the label
(DEFUN LE-COM-CONTROL-R ()
  (READ-DISK-LABEL LE-RQB LE-UNIT)
  (LE-DISPLAY-LABEL LE-RQB LE-UNIT))

;;; Write out the label
(DEFUN LE-COM-CONTROL-W ()
  (COND ((Y-OR-N-P "Do you want to write out this label? ")
	 (WRITE-DISK-LABEL LE-RQB LE-UNIT)
	 (SETQ LE-SOMETHING-CHANGED NIL)
	 (FORMAT T "~&Written.~%Type  to exit the disk-label editor."))
	(T
	 (FORMAT T "~&Not written.~%"))))

;;; Initialize
(DEFUN LE-COM-CONTROL-I ()
  (FORMAT T "Pack types are:~%")
  (DO ((L PACK-TYPES (CDR L))
       (N 0 (1+ N)))
      ((NULL L))
    (FORMAT T " ~S  ~A~%" N (CAAR L)))
  (SETQ LE-SOMETHING-CHANGED T)
  (FORMAT T "Enter desired number: ")
  (LET ((TEM (NTH (READ) PACK-TYPES)))
    (AND TEM (LE-INITIALIZE-LABEL LE-RQB TEM)))
  (LE-DISPLAY-LABEL LE-RQB LE-UNIT))

;;; Delete this partition
(DEFUN LE-COM-CONTROL-K ()
  (LET ((PLOC (LE-CURRENT-PARTITION)))
    (COND ((= LE-ITEM-NUMBER (LENGTH LE-STRUCTURE))
	   (FORMAT T "~&There is no currently selected partition.")
	   (BEEP))
	  ((FQUERY NIL "Delete the ~S partition? " (GET-DISK-STRING LE-RQB PLOC 4))
	   (SETQ LE-SOMETHING-CHANGED T)
	   (LET ((NPARTS (GET-DISK-FIXNUM LE-RQB #o200))
		 (NWORDS (GET-DISK-FIXNUM LE-RQB #o201))
		 (BUF (RQB-BUFFER LE-RQB)))
	     (PUT-DISK-FIXNUM LE-RQB (MAX (1- NPARTS) 0) #o200)
	     (COPY-ARRAY-PORTION BUF (* (+ PLOC NWORDS) 2) (ARRAY-LENGTH BUF)
				 BUF (* PLOC 2) (ARRAY-LENGTH BUF)))
	   (LE-DISPLAY-LABEL LE-RQB LE-UNIT)))))

;;; Redisplay
(DEFUN LE-COM-CONTROL-L ()
  (LE-DISPLAY-LABEL LE-RQB LE-UNIT))

;;; Add a partition
(DEFUN LE-COM-CONTROL-O ()
  (SETQ LE-SOMETHING-CHANGED T)
  (LET ((PLOC (LE-CURRENT-PARTITION)))
    (LET ((NPARTS (1+ (GET-DISK-FIXNUM LE-RQB 200)))
	  (NWORDS (GET-DISK-FIXNUM LE-RQB 201))
	  (BUF (RQB-BUFFER LE-RQB)))
      (COND ((> (+ (* NPARTS NWORDS) #o202)
		(FLOOR (ARRAY-LENGTH (RQB-BUFFER LE-RQB)) 2))
	     (FORMAT T "~&Partition table full"))
	    (T (PUT-DISK-FIXNUM LE-RQB NPARTS 200)
	       (LET ((FOO (MAKE-ARRAY #o1000 ':TYPE 'ART-16B)))
		 (COPY-ARRAY-PORTION BUF (* PLOC 2) (ARRAY-LENGTH BUF) FOO (* NWORDS 2) #o1000)
		 (COPY-ARRAY-PORTION FOO 0 #o1000 BUF (* PLOC 2) (ARRAY-LENGTH BUF))
		 (PUT-DISK-STRING LE-RQB "????" PLOC 4)
		 (PUT-DISK-FIXNUM LE-RQB 0 (+ 2 PLOC))
		 (PUT-DISK-FIXNUM LE-RQB
				  (IF (= LE-ITEM-NUMBER (LENGTH LE-STRUCTURE))
				      (+ (GET-DISK-FIXNUM LE-RQB (+ 1 (- PLOC NWORDS)))
					 (GET-DISK-FIXNUM LE-RQB (+ 2 (- PLOC NWORDS))))
				    (GET-DISK-FIXNUM LE-RQB (+ PLOC NWORDS 1)))
				  (1+ PLOC))
		 (RETURN-ARRAY FOO))
	       (LE-DISPLAY-LABEL LE-RQB LE-UNIT))))))

;;; Sort partitions by address (2nd word) and redisplay
(DEFUN LE-COM-CONTROL-S ()			
  (SETQ LE-SOMETHING-CHANGED T)			;something probably changed
  (DO ((NPARTS (GET-DISK-FIXNUM LE-RQB #o200) (1- NPARTS))
       (NWORDS (GET-DISK-FIXNUM LE-RQB #o201))
       (FROB NIL NIL)
       (PART-LIST NIL (CONS (CONS (GET-DISK-FIXNUM LE-RQB (1+ LOC)) FROB) PART-LIST))
       (LOC #o202 (+ LOC NWORDS))
       (BUF (RQB-BUFFER LE-RQB)))
      ((ZEROP NPARTS)
       (SETQ PART-LIST (SORTCAR PART-LIST #'<))
       (DO ((L PART-LIST (CDR L))
	    (LOC #o202 (+ LOC NWORDS)))
	   ((NULL L))
	 (DO ((K (CDAR L) (CDR K))
	      (I (1- (* 2 NWORDS)) (1- I)))
	     ((MINUSP I))
	   (ASET (CAR K) BUF (+ LOC LOC I)))))
    (DOTIMES (I (* 2 NWORDS))
      (PUSH (AREF BUF (+ LOC LOC I)) FROB)))
  (LE-DISPLAY-LABEL LE-RQB LE-UNIT))

;;; This, my friends, is the hairy part
;;; Edit the selected item
(DEFUN LE-COM-CONTROL-E ()
  (SETQ LE-SOMETHING-CHANGED T)			;something probably will...
  (IF (< LE-ITEM-NUMBER (LENGTH LE-STRUCTURE))
      (LET ((ITEM (NTH LE-ITEM-NUMBER LE-STRUCTURE)))
	(LET ((NAME (FIRST ITEM))
	      (VALUE (SECOND ITEM))
	      (*READ-BASE* 10.))
	  (WITH-INPUT-EDITING (T `((:INITIAL-INPUT ,(FORMAT NIL "~D" VALUE))))
	    (SETQ VALUE (PROMPT-AND-READ (IF (NUMBERP VALUE) ':INTEGER ':STRING)
					 "Change the ~A from to:" NAME)))
	  ;; Avoid lossage in lowercase partition names.
	  (COND ((MEMQ NAME '(PARTITION-NAME CURRENT-BAND CURRENT-MICROLOAD))
		 (SETQ VALUE (STRING-UPCASE VALUE))))
	  (SELECTQ NAME
	    (PACK-NAME (PUT-DISK-STRING LE-RQB VALUE #o20 32.))
	    (DRIVE-NAME (PUT-DISK-STRING LE-RQB VALUE #o10 32.))
	    (COMMENT (PUT-DISK-STRING LE-RQB VALUE #o30 96.))
	    (N-CYLINDERS (PUT-DISK-FIXNUM LE-RQB VALUE 2))
	    (N-HEADS (PUT-DISK-FIXNUM LE-RQB VALUE 3)
		     (PUT-DISK-FIXNUM LE-RQB (* VALUE (GET-DISK-FIXNUM LE-RQB 4)) 5))
	    (N-BLOCKS-PER-TRACK (PUT-DISK-FIXNUM LE-RQB VALUE 4)
				(PUT-DISK-FIXNUM LE-RQB (* VALUE (GET-DISK-FIXNUM LE-RQB 3)) 5))
	    (CURRENT-MICROLOAD (PUT-DISK-STRING LE-RQB VALUE 6 4))
	    (CURRENT-BAND (PUT-DISK-STRING LE-RQB VALUE 7 4))
	    (N-PARTITIONS (PUT-DISK-FIXNUM LE-RQB VALUE #o200))
	    (WORDS-PER-PART (CHANGE-PARTITION-MAP LE-RQB VALUE))
	    ;; These occur in multiple instances; hair is required
	    ((PARTITION-NAME PARTITION-START PARTITION-SIZE PARTITION-COMMENT)
	     (LET ((PLOC (LE-CURRENT-PARTITION)))
	       (SELECTQ NAME
		 (PARTITION-NAME (PUT-DISK-STRING LE-RQB VALUE PLOC 4))
		 (PARTITION-START (PUT-DISK-FIXNUM LE-RQB VALUE (1+ PLOC)))
		 (PARTITION-SIZE (PUT-DISK-FIXNUM LE-RQB VALUE (+ PLOC 2)))
		 (PARTITION-COMMENT
		  (PUT-DISK-STRING LE-RQB VALUE (+ PLOC 3)
				   (* 4 (- (GET-DISK-FIXNUM LE-RQB #o201) 3)))))))
	    (OTHERWISE (FERROR NIL "No editor for ~S" NAME)))))
    (BEEP))
  (LE-DISPLAY-LABEL LE-RQB LE-UNIT))

;;; Returns the word number of the start of the descriptor for the partition
;;; containing the current item.
(DEFUN LE-CURRENT-PARTITION ()
  (DO ((WORDS-PER-PARTITION (GET-DISK-FIXNUM LE-RQB 201))
       (PNO 0)
       (L LE-STRUCTURE (CDR L))
       (N LE-ITEM-NUMBER (1- N)))
      ((ZEROP N)
       (+ #o202 (* PNO WORDS-PER-PARTITION)))
    (AND (EQ (CAAR L) 'PARTITION-COMMENT) (INCF PNO))))

;;; Give help
(DEFF LE-COM-HELP 'LE-COM-?)
(DEFUN LE-COM-? ()
  (FORMAT T "~2%Commands are as follows:
C-B back, C-F forward, C-P up, C-N down
C-R read label from disk, C-W write label to disk, C-I initialize the label
C-L clear the screen, and redisplay the label
C-E edit selected item
C-D describe the current partition
M-~~ mark buffer unmodified
C-O add partition, C-K delete partition, C-S sort partitions
 exit"))
