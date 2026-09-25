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

(DEFUN SET-CURRENT-BAND (BAND &OPTIONAL (UNIT 0) MICRO-P &AUX RQB LOC OLD DONT-DISPOSE)
  "Print the sgdisk command that makes BAND the LOD band loaded at boot time.
QUUX's GPT is written only on the host: the current band, and the current
microcode partition with MICRO-P, is the one of its type with attribute bit 48.
Do PRINT-DISK-LABEL to see what bands are available and what they contain.
UNIT can be a string containing a machine's name, or /"CC/".
UNIT can also be a disk drive number; however, it is the disk on
drive zero which is used for booting.
Returns NIL, as nothing is set on the disk."
  ;; quux (contract q8): the machine writes no gpt; mit's wrote the name of
  ;; the band (or microload) into the label's word 7 (or 6).
  (SETF (VALUES UNIT DONT-DISPOSE)
	(DECODE-UNIT-ARGUMENT UNIT
	         (FORMAT NIL "(SET-CURRENT-~:[BAND~;MICROLOAD~] ~D)" MICRO-P BAND)))
  (UNWIND-PROTECT
      (let ((type (if micro-p :microcode :band)))
	(setq rqb (get-disk-label-rqb))
	(setq band (cond ((or (symbolp band) (stringp band))
			  (string-upcase (string band)))
			 (t (format nil "~A~D" (if micro-p "MCR" "LOD") band))))
	(setq loc (nth-value 2 (find-disk-partition-for-read band rqb unit)))
	(unless (eq (gpt-entry-type rqb loc) type)
	  (ferror nil "~A is not a ~:[band~;microcode~] partition." band micro-p))
	(setq old (nth-value 2 (find-disk-partition-by-type type rqb unit t t)))
	(format t "~&QUUX writes no GPT; to make ~A the current ~:[band~;microcode~], on the host:~%  ~
		   sgdisk ~@[-A ~D:clear:48 ~]-A ~D:set:48 <disk image>~%"
		band micro-p (and old (not (= old loc)) (gpt-entry-number old))
		(gpt-entry-number loc))
	nil)
    (RETURN-DISK-RQB RQB)
    (UNLESS DONT-DISPOSE (DISPOSE-OF-UNIT UNIT))))

;; quux (contract q8): a microcode partition is one of the microcode type
;; whose comment is "UCADR <version>"; mit's looked for the name MCR in the
;; label's first page, which was all the prom read.
(DEFUN FIND-MICROCODE-PARTITION (RQB MICROCODE-VERSION &AUX DESIRED-COMMENT)
  ;; the CADR's names only; the Lambda's ULAMBDA and LMC are gone.
  (SETQ DESIRED-COMMENT (FORMAT NIL "~A ~D" "UCADR" MICROCODE-VERSION))
  (dotimes (i (gpt-n-entries rqb))
    (let ((loc (gpt-entry-loc i))
	  (len (string-length desired-comment)))
      (and (eq (gpt-entry-type rqb loc) :microcode)
	   (string-equal (gpt-entry-comment rqb loc) desired-comment 0 0 len len)
	   (return (gpt-entry-name rqb loc))))))

(DEFUN CURRENT-MICROLOAD (&OPTIONAL (UNIT 0))
  "Return the name of the current microload band.
UNIT can be a name of a machine, a number of a disk drive,
or a string containing CC."
  (CURRENT-BAND UNIT T))

(DEFUN CURRENT-BAND (&OPTIONAL (UNIT 0) MICRO-P &AUX RQB DONT-DISPOSE)
  "Return the name of the current Lisp system (LOD) band.
With MICRO-P, the current microcode partition's.  On QUUX's GPT, it is the
first partition of the type with attribute bit 48; NIL if there is none.
UNIT can be a name of a machine, a number of a disk drive,
or a string containing CC."
  ;; quux (contract q8): by type and bit 48; mit's read the label's word 7 (or 6).
  (UNWIND-PROTECT
      (PROGN (SETF (VALUES UNIT DONT-DISPOSE) (DECODE-UNIT-ARGUMENT UNIT "Reading Label"))
	     (SETQ RQB (GET-DISK-LABEL-RQB))
	     (READ-DISK-LABEL RQB UNIT)
	     (nth-value 3 (find-disk-partition-by-type (if micro-p :microcode :band)
						       rqb unit t t)))
    (RETURN-DISK-RQB RQB)			;Doesn't complain for NIL
    (UNLESS DONT-DISPOSE (DISPOSE-OF-UNIT UNIT))))

;;; quux (contract q8): retired: the gpt is written only on the host.
(DEFUN COPY-DISK-LABEL (&OPTIONAL (FROM-UNIT 0) (TO-UNIT "CC"))
  "Retired on QUUX: its GPT is written only on the host, with sgdisk."
  from-unit to-unit
  (ferror nil "COPY-DISK-LABEL is retired on QUUX; use sgdisk on the host."))

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

(DEFUN PRINT-DISK-LABEL-FROM-RQB (STREAM RQB CONS-UP-LE-STRUCTURE-P)
  ;; quux (contract q8): print the gpt: each used entry, its sgdisk number,
  ;; name, type, place, size and comment, * marking the current ones (bit 48).
  cons-up-le-structure-p
  (format stream "~%GPT, ~D entries from block ~D; * marks the current microcode and band:"
	  (get-disk-fixnum rqb #o224) (floor (get-disk-fixnum rqb #o222) 2))
  (dotimes (i (gpt-n-entries rqb))
    (let ((loc (gpt-entry-loc i)))
      (when (gpt-entry-type rqb loc)
	(format stream "~%~:[ ~;*~]~3D ~4A ~10A at block ~8D, ~8D blocks long, /"~A/""
		(gpt-entry-current-p rqb loc) (1+ i) (gpt-entry-name rqb loc)
		(string-downcase (gpt-entry-type rqb loc))
		(gpt-entry-start rqb loc) (gpt-entry-size rqb loc)
		(gpt-entry-comment rqb loc))))))

(DEFUN P-BIGNUM (ADR)
  (DPB (%P-LDB #o2020 ADR) #o2020 (%P-LDB #o0020 ADR)))

;;; This will get hairier later, e.g. check for wrap around
;; quux: it understands block-disk: the disk address is a block number, and
;; there are no data strobe or servo offset bits in the command.
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
							 (9 . "Write")))))
	     (TERPRI)
	     (FORMAT T "CCW-list pointer ~O (low 16 bits)~%" (LDB #o2020 CLP-CMD))
	     (format t "Disk address: block ~O (~:*~D decimal)~%" (ldb #o0034 da))
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

(DEFUN EDIT-DISK-LABEL (&OPTIONAL (LE-UNIT 0) (INIT-P NIL))
  "Retired on QUUX: its GPT is written only on the host, with sgdisk."
  ;; quux (contract q8): the label editor edited mit's LABL label; the gpt is
  ;; the host's to write.
  le-unit init-p
  (ferror nil "The disk label editor is retired on QUUX; use sgdisk on the host."))

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
