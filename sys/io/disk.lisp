;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:8; Readtable:T -*-
;	** (c) Copyright 1980 Massachusetts Institute of Technology **

;;; "User" Disk I/O routines for Lisp machine -- macrocode portion
;;; See QCOM for documentation on disk rqb's and symbol definitions.
;;; The label-editor and related routines have been moved out of here into DLEDIT

;;;*** Errors should be metered, do this after the microcode is revised ***

;;; The following routines are likely to be of general interest:
;;; DESCRIBE-PARTITION - prints various info about a partition.
;;; FIND-PLAUSIBLE-PARTITIONS - searches the disk for blocks that appear to start Lisp bands
;;; POWER-UP-DISK - makes sure a drive is powered up
;;; CLEAR-DISK-FAULT - attempts to reset select-lock (fault, unsafe, device-check)
;;; SET-CURRENT-MICROLOAD - choose microload to be booted from  [this is in the DLEDIT file]
;;; SET-CURRENT-BAND - choose world load to be booted from  [this is in the DLEDIT file]
;;; PRINT-DISK-LABEL - print the pack label of a drive  [this is in the DLEDIT file]
;;; PRINT-LOADED-BAND - print information about what system is running
;;; PAGE-{IN,OUT}-{STRUCTURE,WORDS,REGION,AREA,ARRAY} - fast paging: multiple pages at a time
;;; EDIT-DISK-LABEL - edit the pack label of a drive  [this is in the DLEDIT file]
;;; LOAD-MCR-FILE - load microcode from the file-computer onto the disk
;;; COPY-DISK-PARTITION - copy a partition from disk to disk
;;; COPY-DISK-PARTITION-BACKGROUND - same but in separate process and artificially slowed down
;;; COMPARE-DISK-PARTITION - similar to copy, but compares and prints differences.
;;; MEASURED-SIZE-OF-PARTITION - Returns how much of LOD is actually used.

;;; These are interesting if you really want to do I/O
;;; GET-DISK-RQB
;;; RETURN-DISK-RQB
;;; PRINT-RQB
;;; DISK-READ
;;; DISK-WRITE

(DEFVAR *UNIT-CYLINDER-OFFSETS* NIL
  "Alist for dealing with disks with offset origins.
use care! Unit 0 not offset!")

;;; Area containing wirable buffers and RQBs
(DEFVAR DISK-BUFFER-AREA (MAKE-AREA :NAME 'DISK-BUFFER-AREA :GC :STATIC)
  "Area containing disk RQBs.")

(DEFVAR PAGE-OFFSET :UNBOUND
  "Disk address of start of PAGE partition")
(DEFVAR VIRTUAL-MEMORY-SIZE :UNBOUND
  "Size of paging partition in words")

(DEFVAR CURRENT-LOADED-BAND :UNBOUND
  "Remembers %LOADED-BAND through warm-booting")
(DEFVAR DISK-PACK-NAME :UNBOUND
  "Remembers name of pack for PRINT-LOADED-BAND")

(DEFVAR CC-REMOTE-DISK-WRITE-CHECK NIL
  "T => CC remote disk handler does read after write")
(DEFVAR DISK-SHOULD-READ-COMPARE NIL
  "T => read-compare after reads and write done by Lisp programs.")
				      ;Unfortunately there is a hardware bug with
				      ;read compares on transfers longer than 1 block.
				      ;This didn't find any problems while it was on anyway.
				      ;(Fixed by DC ECO#1)
(DEFVAR DISK-ERROR-RETRY-COUNT 5 "Retry this many times before CERRORing, on disk errors.")
(DEFVAR LET-MICROCODE-HANDLE-DISK-ERRORS T "Use the disk error retry code in the microcode.")

(DEFSUBST RQB-BUFFER (RQB)
  "Returns a 16-bit array whose contents are the data in RQB.
This is an indirect array which overlaps the appropriate portion of RQB."
  (ARRAY-LEADER RQB %DISK-RQ-LEADER-BUFFER))
(DEFSUBST RQB-8-BIT-BUFFER (RQB)
  "Returns an 8-bit array whose contents are the data in RQB.
This is an indirect array which overlaps the appropriate portion of RQB."
  (ARRAY-LEADER RQB %DISK-RQ-LEADER-8-BIT-BUFFER))
(DEFSUBST RQB-NPAGES (RQB)
  "Returns the data length of RQB, in pages."
  (ARRAY-LEADER RQB %DISK-RQ-LEADER-N-PAGES))

;;; The next three routines are the simple versions intended to be called
;;; by moderately naive people (i.e. clowns).
;;; Note that if UNIT is not a number, it is a function called to
;;; perform the operation.  This allows the console program to
;;; access other machines' disks in a compatible fashion.

(DEFUN DISK-READ (RQB UNIT ADDRESS
		  &OPTIONAL (MICROCODE-ERROR-RECOVERY LET-MICROCODE-HANDLE-DISK-ERRORS)
			    DO-NOT-OFFSET)
  "Read data from disk UNIT at block ADDRESS into RQB.
The length of data read is simply the number of pages of data in RQB.
UNIT can be either a disk unit number or a function to perform
the transfer.  That is how transfers to other machines' disks are done.
The function receives arguments :READ, the RQB, and the ADDRESS."
  (COND ((NUMBERP UNIT)
	 (WIRE-DISK-RQB RQB (ARRAY-LEADER RQB %DISK-RQ-LEADER-N-PAGES) T T) ;set modified bits
	 (DISK-READ-WIRED RQB UNIT ADDRESS MICROCODE-ERROR-RECOVERY do-not-offset)
	 (UNWIRE-DISK-RQB RQB)
	 RQB)
	((SEND UNIT :READ RQB ADDRESS))))

(DEFUN DISK-WRITE (RQB UNIT ADDRESS
		  &OPTIONAL (MICROCODE-ERROR-RECOVERY LET-MICROCODE-HANDLE-DISK-ERRORS))
  "Write data to disk UNIT at block ADDRESS from RQB.
The length of data written is simply the number of pages of data in RQB.
UNIT can be either a disk unit number or a function to perform
the transfer.  That is how transfers to other machines' disks are done.
The function receives arguments :WRITE, the RQB, and the ADDRESS."
  (COND ((NUMBERP UNIT)
	 (WIRE-DISK-RQB RQB)
	 (DISK-WRITE-WIRED RQB UNIT ADDRESS MICROCODE-ERROR-RECOVERY)
	 (UNWIRE-DISK-RQB RQB)
	 RQB)
	((SEND UNIT :WRITE RQB ADDRESS))))

;A hardware bug causes this to lose if xfer > 1 page  (Fixed by DC ECO#1)
;Returns T if they match and NIL if they don't
(DEFUN DISK-READ-COMPARE (RQB UNIT ADDRESS
		  &OPTIONAL (MICROCODE-ERROR-RECOVERY LET-MICROCODE-HANDLE-DISK-ERRORS))
  "Compare data from disk UNIT at block ADDRESS with the data in RQB.
The length of data compared is simply the number of pages of data in RQB.
UNIT can be either a disk unit number or a function to perform
the transfer.  That is how transfers to other machines' disks are done.
The function receives arguments :READ-COMPARE, the RQB, and the ADDRESS."
  (COND ((NUMBERP UNIT)
	 (WIRE-DISK-RQB RQB)
	 (DISK-READ-COMPARE-WIRED RQB UNIT ADDRESS MICROCODE-ERROR-RECOVERY)
	 (UNWIRE-DISK-RQB RQB)
	 (ZEROP (LDB %%DISK-STATUS-HIGH-READ-COMPARE-DIFFERENCE
		     (AREF RQB %DISK-RQ-STATUS-HIGH))))
	((SEND UNIT :READ-COMPARE RQB ADDRESS))))

;;; Get STATUS of a unit by doing OFFSET-CLEAR (nebbish command) to it
;;; Leaves the status in the rqb
(DEFUN GET-DISK-STATUS (RQB UNIT)
  (DISK-RUN RQB UNIT 0 1 1 %DISK-COMMAND-OFFSET-CLEAR "Offset Clear" T))

;(DEFUN LOCAL-DISK-APPARENTLY-EXISTS-P (UNIT)
;  "Returns T if there is reason to believe that UNIT exists as a running disk drive."	
;  UNIT)					   

;;; Power up a drive, return T if successful, NIL if timed out
(DEFUN POWER-UP-DISK (UNIT &OPTIONAL (TIME-TO-WAIT (* 30. 60.)) &AUX RQB)
  "Attempt to turn on disk unit UNIT, returning T if successful.  Timeout after TIME-TO-WAIT."
  (UNWIND-PROTECT
     (PROGN (SETQ RQB (GET-DISK-RQB))
	    (DO ((START-TIME (TIME)))
		((OR (> (TIME-DIFFERENCE (TIME) START-TIME) TIME-TO-WAIT))	
		     (NOT (LDB-TEST %%DISK-STATUS-LOW-OFF-CYLINDER
				    (PROGN (GET-DISK-STATUS RQB UNIT)
					   (AREF RQB %DISK-RQ-STATUS-LOW)))))
		 (NOT (LDB-TEST %%DISK-STATUS-LOW-OFF-CYLINDER
				(AREF RQB %DISK-RQ-STATUS-LOW))))
	      (PROCESS-SLEEP 60. "Wait for disk (power up)"))
     (RETURN-DISK-RQB RQB)))

(DEFUN CLEAR-DISK-FAULT (UNIT &AUX RQB)
  "Clear any error indicators on disk drive UNIT."
  (UNWIND-PROTECT
     (PROGN (SETQ RQB (GET-DISK-RQB))
	    (DISK-RUN RQB UNIT 0 1 1 %DISK-COMMAND-FAULT-CLEAR "Fault Clear" T))
     (RETURN-DISK-RQB RQB)))

;;; A debugging function
(DEFUN PRINT-RQB (RQB)
  (DO ((I 0 (1+ I))
       (L DISK-RQ-HWDS (CDR L)))
      ((NULL (CDR L))
       (PRINT (CAR L))				;CCW list
       (DO ((I I (+ I 2))) (())
	 (FORMAT T "	~O" (DPB (AREF RQB (1+ I)) #o2020 (AREF RQB I)))
	 (OR (BIT-TEST 1 (AREF RQB I)) (RETURN NIL)))
       (TERPRI))
    (FORMAT T "~%~S  ~O" (CAR L) (AREF RQB I))))

;;; Internally, RQBs are resources.
(DEFRESOURCE RQB (N-PAGES LEADER-LENGTH)
  :CONSTRUCTOR MAKE-DISK-RQB
  :FREE-LIST-SIZE 50.)

(DEFUN GET-DISK-RQB (&OPTIONAL (N-PAGES 1) (LEADER-LENGTH (LENGTH DISK-RQ-LEADER-QS)))
  "Return an RQB of data length N-PAGES and leader length LEADER-LENGTH.
The leader length is specified only for weird hacks.
Use RETURN-DISK-RQB to release the RQB for re-use."
  (LET ((DEFAULT-CONS-AREA WORKING-STORAGE-AREA)) ;avoid lossage on consing in 
						  ; resource stuff. (specifically parametizer)
    (ALLOCATE-RESOURCE 'RQB N-PAGES LEADER-LENGTH)))

(DEFUN MAKE-DISK-RQB (IGNORE N-PAGES LEADER-LENGTH)
  (LET* ((OVERHEAD (+ 4 4 3 LEADER-LENGTH))
	 (ARRAY-LENGTH (* (- (* (1+ N-PAGES) PAGE-SIZE) OVERHEAD) 2))
	 RQB-BUFFER
	 RQB-8-BIT-BUFFER
	 RQB)
    ;; Compute how much overhead there is in the RQB-BUFFER,
    ;; RQB-8-BIT-BUFFER, and in the RQB's leader and header.  4 for the
    ;; RQB-BUFFER indirect-offset array, 4 for the RQB-8-BIT-BUFFER
    ;; indirect-offset array, 3 for the RQB's header, plus the RQB's leader.
    ;; Then set the length (in halfwords) of the array to be sufficient so
    ;; that it plus the overhead is a multiple of the page size, making it
    ;; possible to wire down RQB's.
    (WHEN (> ARRAY-LENGTH %ARRAY-MAX-SHORT-INDEX-LENGTH)
      (INCF OVERHEAD 1)
      (DECF ARRAY-LENGTH 2)
      (UNLESS (> ARRAY-LENGTH %ARRAY-MAX-SHORT-INDEX-LENGTH)
	(FERROR NIL "Impossible to make this RQB array fit")))
    ;; See if the CCW list will run off the end of the first page, and hence
    ;; not be stored in consecutive physical addresses.
    (IF (> (+ OVERHEAD (FLOOR %DISK-RQ-CCW-LIST 2) N-PAGES) PAGE-SIZE)
	(FERROR 'RQB-TOO-LARGE "CCW list doesn't fit on first RQB page, ~S pages is too many"
		N-PAGES))
    (TAGBODY
     L	(SETQ RQB-BUFFER (MAKE-ARRAY (* PAGE-SIZE 2 N-PAGES)
				     :TYPE ART-16B
				     :AREA DISK-BUFFER-AREA
				     :DISPLACED-TO ""
				     :DISPLACED-INDEX-OFFSET	;To second page of RQB
				     	(- ARRAY-LENGTH (* PAGE-SIZE 2 N-PAGES)))
	      RQB-8-BIT-BUFFER (MAKE-ARRAY (* PAGE-SIZE 4 N-PAGES)
					   :TYPE ART-STRING
					   :AREA DISK-BUFFER-AREA
					   :DISPLACED-TO ""
					   :DISPLACED-INDEX-OFFSET
					   	(* 2 (- ARRAY-LENGTH (* PAGE-SIZE 2 N-PAGES))))
	      RQB (MAKE-ARRAY ARRAY-LENGTH
			      :AREA DISK-BUFFER-AREA
			      :TYPE ART-16B
			      :LEADER-LENGTH LEADER-LENGTH))
	(WHEN ( (%REGION-NUMBER RQB-BUFFER)	;make sure a new region
		 (%REGION-NUMBER RQB))		;didn't screw us completely
	  ;; Screwed! Try again.  Make sure don't lose same way again by
	  ;;  using up region that didnt hold it.
	  (RETURN-ARRAY RQB)
	  (LET ((RN (%REGION-NUMBER RQB-BUFFER)))
	    (RETURN-ARRAY RQB-BUFFER)
	    (%USE-UP-REGION RN))
	  (GO L)))
    (MAKE-SURE-FREE-POINTER-OF-REGION-IS-AT-PAGE-BOUNDARY
      'DISK-BUFFER-AREA (%REGION-NUMBER RQB))
    (%P-STORE-CONTENTS-OFFSET RQB RQB-BUFFER 1)	;Displace RQB-BUFFER to RQB
    (%P-STORE-CONTENTS-OFFSET RQB RQB-8-BIT-BUFFER 1)
    (STORE-ARRAY-LEADER (+ %DISK-RQ-CCW-LIST (* 2 N-PAGES))
			RQB
			%DISK-RQ-LEADER-N-HWDS)
    (SETF (ARRAY-LEADER RQB %DISK-RQ-LEADER-N-PAGES) N-PAGES)
    (SETF (ARRAY-LEADER RQB %DISK-RQ-LEADER-BUFFER) RQB-BUFFER)
    (SETF (ARRAY-LEADER RQB %DISK-RQ-LEADER-8-BIT-BUFFER) RQB-8-BIT-BUFFER)
    RQB))

;;; Use this to recover if the free pointer is off a page boundary.
(DEFUN %USE-UP-REGION (REGION-NUMBER)
  (SETF (AREF #'SYSTEM:REGION-LENGTH REGION-NUMBER)
	(AREF #'SYSTEM:REGION-FREE-POINTER REGION-NUMBER)))

;;; This used to check all the regions of the area, but that loses,
;;; because exhausted regions always have free pointers 10 past the page boundary
;;; (because the rqb-buffer and rqb-8-bit-buffer had been consed before exhausting it).
(DEFUN MAKE-SURE-FREE-POINTER-OF-REGION-IS-AT-PAGE-BOUNDARY (AREA REGION-NUMBER)
  (OR (ZEROP (LOGAND (1- PAGE-SIZE) (REGION-FREE-POINTER REGION-NUMBER)))
      (FERROR NIL
	      "~%Area ~A(#~O), region ~O has free pointer ~O, which is not on a page boundary"
	      AREA (SYMEVAL AREA) REGION-NUMBER (REGION-FREE-POINTER REGION-NUMBER))))

;;; Return a buffer to the free list
(DEFUN RETURN-DISK-RQB (RQB)
  "Release RQB for reuse."
  (COND ((NOT (NULL RQB))	;Allow NIL's to be handed to the function just in case
	 (UNWIRE-DISK-RQB RQB)
	 (DEALLOCATE-RESOURCE 'RQB RQB)))
  NIL)

(DEFCONST DISK-LABEL-RQB-PAGES 3)
(DEFUN GET-DISK-LABEL-RQB ()
  "Get a disk RQB for reading the label into."
  (GET-DISK-RQB DISK-LABEL-RQB-PAGES))

(DEFUN COUNT-FREE-RQBS (N-PAGES)
  "Return the number of free RQBs there are whose data length is N-PAGES."
  (WITHOUT-INTERRUPTS
    (LOOP WITH RESOURCE = (GET 'RQB 'DEFRESOURCE)
	  WITH N-OBJECTS = (RESOURCE-N-OBJECTS RESOURCE)
	  FOR I FROM 0 BELOW N-OBJECTS
	  COUNT (= (CAR (RESOURCE-PARAMETERS RESOURCE I)) N-PAGES))))

;;; Set up ccw list, wire down pages
(DEFUN WIRE-DISK-RQB (RQB &OPTIONAL (N-PAGES (ARRAY-LEADER RQB %DISK-RQ-LEADER-N-PAGES))
		      		    (WIRE-P T)
				    SET-MODIFIED
			  &AUX (LONG-ARRAY-FLAG (%P-LDB %%ARRAY-LONG-LENGTH-FLAG RQB))
			       (LOW (- (%POINTER RQB) (ARRAY-LEADER-LENGTH RQB) 2))
			       (HIGH (+ (%POINTER RQB) 1 LONG-ARRAY-FLAG
					(FLOOR (ARRAY-LENGTH RQB) 2))))
  (DO ((LOC (LOGAND LOW (- PAGE-SIZE)) (+ LOC PAGE-SIZE)))
      (( LOC HIGH))
    (WIRE-PAGE LOC WIRE-P SET-MODIFIED))
  ;; Having wired the rqb, if really wiring set up CCW-list N-PAGES long
  ;; and CLP to it, but if really unwiring make CLP point to NXM as err check
  (IF (NOT WIRE-P)
      (SETF (AREF RQB %DISK-RQ-CCW-LIST-POINTER-LOW)  #o177777	;Just below TV buffer
            (aref RQB %DISK-RQ-CCW-LIST-POINTER-HIGH) #o76)
    (DO ((CCWX 0 (1+ CCWX))
	 (VADR (+ LOW PAGE-SIZE) (+ VADR PAGE-SIZE))	;Start with 2nd page of rqb array
	 (PADR))
	(( CCWX N-PAGES)	;Done, set END in last CCW
	 (SETQ PADR (%PHYSICAL-ADDRESS (+ (%POINTER RQB)
					  1
					  LONG-ARRAY-FLAG
					  (FLOOR %DISK-RQ-CCW-LIST 2))))
	 (SETF (aref RQB %DISK-RQ-CCW-LIST-POINTER-LOW) PADR)
	 (SETF (aref RQB %DISK-RQ-CCW-LIST-POINTER-HIGH) (LSH PADR -16.)))
      (SETQ PADR (%PHYSICAL-ADDRESS VADR))
      (SETF (AREF RQB (+ %DISK-RQ-CCW-LIST (* 2 CCWX)))
	    (+ (LOGAND (- PAGE-SIZE) PADR)		;Low 16 bits
	       (IF (= CCWX (1- N-PAGES)) 0 1)))		;Chain bit
      (SETF (AREF RQB (+ %DISK-RQ-CCW-LIST 1 (* 2 CCWX)))
	    (LSH PADR -16.)))))				;High 6 bits

(DEFUN UNWIRE-DISK-RQB (RQB)
  (WIRE-DISK-RQB RQB NIL NIL))

;;; Disk geometry is remembered in the following arrays.
;;; The DISK-READ-WIRED function contains a kludge that it notices if you
;;; are reading the label, and automatically adjusts the geometry
;;; for that unit from the label.  You can also store explicitly
;;; in the arrays if you like.

(DEFVAR DISK-SECTORS-PER-TRACK-ARRAY)
(DEFVAR DISK-HEADS-PER-CYLINDER-ARRAY)

(UNLESS (BOUNDP 'DISK-SECTORS-PER-TRACK-ARRAY)
  (SETQ DISK-SECTORS-PER-TRACK-ARRAY (MAKE-ARRAY #o20 :TYPE 'ART-8B :INITIAL-ELEMENT 17.)
	DISK-HEADS-PER-CYLINDER-ARRAY (MAKE-ARRAY #o20 :TYPE 'ART-8B :INITIAL-ELEMENT 5)))

;;; These must be called with the buffer already wired, which specifies the
;;; number of pages implicitly (usually 1 of course)
;;; For now, error-handling is rudimentary, fix later
;;; Note!! If you call this directly, you better make sure the modified bits for the
;;; pages transferred get set!!!
(DEFUN DISK-READ-WIRED (RQB UNIT ADDRESS
			&OPTIONAL (MICROCODE-ERROR-RECOVERY LET-MICROCODE-HANDLE-DISK-ERRORS)
				  DO-NOT-OFFSET
			&AUX (SECTORS-PER-TRACK (AREF DISK-SECTORS-PER-TRACK-ARRAY UNIT))
			     (HEADS-PER-CYLINDER (AREF DISK-HEADS-PER-CYLINDER-ARRAY UNIT)))
  
  (DISK-RUN RQB UNIT ADDRESS SECTORS-PER-TRACK HEADS-PER-CYLINDER
	    (LOGIOR %DISK-COMMAND-READ
		    (IF MICROCODE-ERROR-RECOVERY %DISK-COMMAND-DONE-INTERRUPT-ENABLE 0))
	    "read"
	    nil
	    (if do-not-offset -100. 0)))

(DEFUN DISK-WRITE-WIRED (RQB UNIT ADDRESS
		   &OPTIONAL (MICROCODE-ERROR-RECOVERY LET-MICROCODE-HANDLE-DISK-ERRORS)
		   &AUX (SECTORS-PER-TRACK (AREF DISK-SECTORS-PER-TRACK-ARRAY UNIT))
			(HEADS-PER-CYLINDER (AREF DISK-HEADS-PER-CYLINDER-ARRAY UNIT)))
  (DISK-RUN RQB UNIT ADDRESS SECTORS-PER-TRACK HEADS-PER-CYLINDER
	    (LOGIOR %DISK-COMMAND-WRITE
		    (IF MICROCODE-ERROR-RECOVERY %DISK-COMMAND-DONE-INTERRUPT-ENABLE 0))
	    "write"))


; A hardware bug causes this to lose if xfer > 1 page  (Fixed by DC ECO#1)
;;; Returns T if read-compare difference detected
(DEFUN DISK-READ-COMPARE-WIRED (RQB UNIT ADDRESS
		   &OPTIONAL (MICROCODE-ERROR-RECOVERY LET-MICROCODE-HANDLE-DISK-ERRORS)
		   &AUX (SECTORS-PER-TRACK (AREF DISK-SECTORS-PER-TRACK-ARRAY UNIT))
			(HEADS-PER-CYLINDER (AREF DISK-HEADS-PER-CYLINDER-ARRAY UNIT)))
  (DISK-RUN RQB UNIT ADDRESS SECTORS-PER-TRACK HEADS-PER-CYLINDER
	    (LOGIOR %DISK-COMMAND-READ-COMPARE
		    (IF MICROCODE-ERROR-RECOVERY %DISK-COMMAND-DONE-INTERRUPT-ENABLE 0))
	    "read-compare")
  (LDB-TEST %%DISK-STATUS-HIGH-READ-COMPARE-DIFFERENCE
	    (AREF RQB %DISK-RQ-STATUS-HIGH)))

(DEFUN DISK-RUN (RQB UNIT ADDRESS SECTORS-PER-TRACK HEADS-PER-CYLINDER CMD CMD-NAME
		 &OPTIONAL NO-ERROR-CHECKING (offset-of-another-kind 0)
		 &AUX ADR CYLINDER SURFACE SECTOR ERROR-COUNT ER-H ER-L TEM)
  (PROG (FINAL-ADDRESS FINAL-CYLINDER FINAL-SURFACE FINAL-SECTOR MICROCODE-ERROR-RECOVERY)
	(SETQ FINAL-ADDRESS (+ ADDRESS (1- (DISK-TRANSFER-SIZE RQB)))   ;count length of CCW.
	      FINAL-SECTOR (\ FINAL-ADDRESS SECTORS-PER-TRACK)
	      ADR (FLOOR FINAL-ADDRESS SECTORS-PER-TRACK)
	      FINAL-SURFACE (\ ADR HEADS-PER-CYLINDER)
	      FINAL-CYLINDER (FLOOR ADR  HEADS-PER-CYLINDER)
	      MICROCODE-ERROR-RECOVERY (BIT-TEST %DISK-COMMAND-DONE-INTERRUPT-ENABLE CMD))
     FULL-RETRY
	(SETQ ERROR-COUNT DISK-ERROR-RETRY-COUNT)
     PARTIAL-RETRY
	(SETQ SECTOR (\ ADDRESS SECTORS-PER-TRACK)
	      ADR (FLOOR ADDRESS SECTORS-PER-TRACK)
	      SURFACE (\ ADR HEADS-PER-CYLINDER)
	      CYLINDER (+ (FLOOR ADR HEADS-PER-CYLINDER)
			  (COND ((ZEROP UNIT) 0)	;dont lose completely!!
				((SETQ TEM (ASSQ UNIT *UNIT-CYLINDER-OFFSETS*))
				 (CDR TEM))
				(T 0))))
	(SETF (AREF RQB %DISK-RQ-COMMAND) CMD
	      (AREF RQB %DISK-RQ-SURFACE-SECTOR) (+ (LSH SURFACE 8) SECTOR)
	      (AREF RQB %DISK-RQ-UNIT-CYLINDER) (+ (LSH UNIT 12.)
						   (LDB #o0014
							(+ CYLINDER OFFSET-OF-ANOTHER-KIND)))
	      (AREF RQB %DISK-RQ-FINAL-UNIT-CYLINDER) 0
	      (AREF RQB %DISK-RQ-FINAL-SURFACE-SECTOR) 0)
	(DISK-RUN-1 RQB UNIT)
	(WHEN NO-ERROR-CHECKING
	  (RETURN NIL))
	(SETQ ER-H (AREF RQB %DISK-RQ-STATUS-HIGH)
	      ER-L (AREF RQB %DISK-RQ-STATUS-LOW))
	(AND (= CMD %DISK-COMMAND-READ-COMPARE)
	     (LDB-TEST %%DISK-STATUS-HIGH-READ-COMPARE-DIFFERENCE ER-H)
	     (SETQ ER-H (DPB 0 %%DISK-STATUS-HIGH-INTERNAL-PARITY ER-H)))
	(COND ((OR (BIT-TEST %DISK-STATUS-HIGH-ERROR ER-H)
		   (BIT-TEST %DISK-STATUS-LOW-ERROR ER-L))
	       (OR (ZEROP (SETQ ERROR-COUNT (1- ERROR-COUNT)))
		   MICROCODE-ERROR-RECOVERY
		   (GO PARTIAL-RETRY))
	       (CERROR :RETRY-DISK-OPERATION NIL 'SYS:DISK-ERROR
		       "Disk ~A error unit ~D, cyl ~D., surf ~D., sec ~D.,~%  status ~A
 Type ~:C to retry."
		       CMD-NAME UNIT
		       (LDB #o0014 (AREF RQB %DISK-RQ-FINAL-UNIT-CYLINDER))
		       (LDB #o1010 (AREF RQB %DISK-RQ-FINAL-SURFACE-SECTOR))
		       (LDB #o0010 (AREF RQB %DISK-RQ-FINAL-SURFACE-SECTOR))
		       (DECODE-DISK-STATUS (AREF RQB %DISK-RQ-STATUS-LOW)
					   (AREF RQB %DISK-RQ-STATUS-HIGH))
		       #/RESUME)
	       (GO FULL-RETRY))
	      ((AND ( PROCESSOR-TYPE-CODE LAMBDA-TYPE-CODE)
		    (OR ( FINAL-CYLINDER
			   (LDB #o0014 (AREF RQB %DISK-RQ-FINAL-UNIT-CYLINDER)))
			( FINAL-SURFACE
			   (LDB #o1010 (AREF RQB %DISK-RQ-FINAL-SURFACE-SECTOR)))
			( FINAL-SECTOR
			   (LDB #o0010 (AREF RQB %DISK-RQ-FINAL-SURFACE-SECTOR)))))
	       (CERROR :RETRY-DISK-OPERATION NIL 'SYS:DISK-ERROR
		       "Disk ~A error unit ~D, cyl ~D., surf ~D., sec ~D.,~%  status ~A
 Failed to complete operation, final disk address should be ~D, ~D, ~D.
 Type ~:C to retry."
		       CMD-NAME UNIT
		       (LDB #o0014 (AREF RQB %DISK-RQ-FINAL-UNIT-CYLINDER))
		       (LDB #o1010 (AREF RQB %DISK-RQ-FINAL-SURFACE-SECTOR))
		       (LDB #o0010 (AREF RQB %DISK-RQ-FINAL-SURFACE-SECTOR))
		       (DECODE-DISK-STATUS (AREF RQB %DISK-RQ-STATUS-LOW)
					   (AREF RQB %DISK-RQ-STATUS-HIGH))
		       FINAL-CYLINDER FINAL-SURFACE FINAL-SECTOR
		       #/RESUME)
	       (GO FULL-RETRY))
	      ((AND DISK-SHOULD-READ-COMPARE
		    (OR (= CMD %DISK-COMMAND-READ) (= CMD %DISK-COMMAND-WRITE)))
	       (SETF (AREF RQB %DISK-RQ-COMMAND) %DISK-COMMAND-READ-COMPARE)
	       (DISK-RUN-1 RQB UNIT)
	       (COND ((OR (BIT-TEST %DISK-STATUS-HIGH-ERROR (AREF RQB %DISK-RQ-STATUS-HIGH))
			  (BIT-TEST %DISK-STATUS-LOW-ERROR (AREF RQB %DISK-RQ-STATUS-LOW)))
		      (OR (ZEROP (SETQ ERROR-COUNT (1- ERROR-COUNT)))
			  (GO PARTIAL-RETRY))
		      (CERROR :RETRY-DISK-OPERATION NIL 'SYS:DISK-ERROR
			      "Disk error during read//compare after ~A unit ~D, cyl ~D., surf ~D., sec ~D.,~%  status ~A
 Type ~:C to retry."
			      CMD-NAME UNIT
			      (LDB #o0014 (AREF RQB %DISK-RQ-FINAL-UNIT-CYLINDER))
			      (LDB #o1010 (AREF RQB %DISK-RQ-FINAL-SURFACE-SECTOR))
			      (LDB #o0010 (AREF RQB %DISK-RQ-FINAL-SURFACE-SECTOR))
			      (DECODE-DISK-STATUS (AREF RQB %DISK-RQ-STATUS-LOW)
						  (AREF RQB %DISK-RQ-STATUS-HIGH))
			      #/RESUME)
		      (GO FULL-RETRY))
		     ((LDB-TEST %%DISK-STATUS-HIGH-READ-COMPARE-DIFFERENCE
				(AREF RQB %DISK-RQ-STATUS-HIGH))
		      ;; A true read/compare difference really shouldn't happen, complain
		      (CERROR :RETRY-DISK-OPERATION NIL 'SYS:DISK-ERROR
			      "Disk read//compare error unit ~D, cyl ~D., surf ~D., sec ~D.
 Type ~:C to retry."
			      UNIT
			      (LDB #o0014 (AREF RQB %DISK-RQ-FINAL-UNIT-CYLINDER))
			      (LDB #o1010 (AREF RQB %DISK-RQ-FINAL-SURFACE-SECTOR))
			      (LDB #o0010 (AREF RQB %DISK-RQ-FINAL-SURFACE-SECTOR))
			      #/RESUME)
		      (GO FULL-RETRY)))))))

;;; This knows about a second disk controller, containing units 10-17,
;;; which is at an XBUS address 4 less than the address of the first controller.
(DEFUN DISK-RUN-1 (RQB UNIT)
  (COND ((< UNIT 8)
	 (%DISK-OP RQB)
	 (DO () ((NOT (ZEROP (AREF RQB %DISK-RQ-DONE-FLAG))))))	;Loop until disk op complete
	(T ;; Await disk control ready
	   (DO () ((BIT-TEST 1 (%XBUS-READ #o377770))))
	   ;; Write 4 words into disk control
	   (%BLT (%MAKE-POINTER-OFFSET DTP-FIX RQB
				       (+ (LSH %DISK-RQ-COMMAND -1) (ARRAY-DATA-OFFSET RQB)))
		 (+ IO-SPACE-VIRTUAL-ADDRESS #o377770)
		 4 1)
	   ;; Await disk control done
	   (DO () ((BIT-TEST 1 (%XBUS-READ #o377770))))
	   ;; Read 4 words from disk control
	   (%BLT (+ IO-SPACE-VIRTUAL-ADDRESS #o377770)
		 (%MAKE-POINTER-OFFSET DTP-FIX RQB
				       (+ (LSH %DISK-RQ-STATUS-LOW -1)
					  (ARRAY-DATA-OFFSET RQB)))
		 4 1))))

(DEFUN DISK-TRANSFER-SIZE (RQB)
  (DO ((CCWP %DISK-RQ-CCW-LIST (+ CCWP 2))
       (COUNT 1 (1+ COUNT)))
      ((ZEROP (LOGAND (AREF RQB CCWP) 1)) COUNT)))

;;; Return a string representation of the disk status register (pair of halfwords)
;;; Put the most relevant error condition bit first, followed by all other 1 bits
;;; Except for Idle, Interrupt, Read Compare Difference (and block-counter) which
;;; are not interesting as errors.
;;; Also if the transfer is aborted, leave out Internal Parity which is always on.
(DEFUN DECODE-DISK-STATUS (LOW HIGH)
  (WITH-OUTPUT-TO-STRING (S)
    (LOOP FOR (NAME PPSS HALF) IN '(("Nonexistent-Memory" %%DISK-STATUS-HIGH-NXM T)
				    ("Memory-Parity" %%DISK-STATUS-HIGH-MEM-PARITY T)
				    ("Multiple-Select" %%DISK-STATUS-LOW-MULTIPLE-SELECT)
				    ("No-Select" %%DISK-STATUS-LOW-NO-SELECT)
				    ("Fault" %%DISK-STATUS-LOW-FAULT)
				    ("Off-line"  %%DISK-STATUS-LOW-OFF-LINE)
				    ("Off-Cylinder" %%DISK-STATUS-LOW-OFF-CYLINDER)
				    ("Seek-Error" %%DISK-STATUS-LOW-SEEK-ERROR)
				    ("Start-Block-Error" %%DISK-STATUS-LOW-START-BLOCK-ERROR)
				    ("Overrun" %%DISK-STATUS-LOW-OVERRUN)
				    ("Header-Compare" %%DISK-STATUS-HIGH-HEADER-COMPARE T)
				    ("Header-ECC" %%DISK-STATUS-HIGH-HEADER-ECC T)
				    ("ECC-Hard" %%DISK-STATUS-HIGH-ECC-HARD T)
				    ("ECC-Soft" %%DISK-STATUS-LOW-ECC-SOFT)
				    ("Timeout" %%DISK-STATUS-LOW-TIMEOUT)
				    ("Internal-Parity" %%DISK-STATUS-HIGH-INTERNAL-PARITY T)
				    ("Transfer-Aborted" %%DISK-STATUS-LOW-TRANSFER-ABORTED)
				    ("CCW-Cycle" %%DISK-STATUS-HIGH-CCW-CYCLE T)
				    ("Read-Only" %%DISK-STATUS-LOW-READ-ONLY)
				    ("Sel-Unit-Attention"
				        %%DISK-STATUS-LOW-SEL-UNIT-ATTENTION)
				    ("Any-Unit-Attention" %%DISK-STATUS-LOW-ATTENTION))
	  WITH FLAG = NIL
	  WHEN (AND (LDB-TEST (SYMEVAL PPSS) (IF (NULL HALF) LOW HIGH))
		    (OR (NEQ PPSS '%%DISK-STATUS-HIGH-INTERNAL-PARITY)
			(NOT (LDB-TEST %%DISK-STATUS-LOW-TRANSFER-ABORTED LOW))))
	    DO (IF FLAG (SEND S :STRING-OUT "  "))
	       (SEND S :STRING-OUT NAME)
	       (SETQ FLAG T))))

;;; Unit is unit number on local disk controller or a string.
;;; If a string, CC means hack over debug interface
;;;    		 TEST is a source of test data
;;;		 MT is magtape
;;;	  otherwise it is assumed to be the chaosnet name of a remote machine.
(DECLARE (*EXPR FS:MAKE-BAND-MAGTAPE-HANDLER))

(DEFUN DECODE-UNIT-ARGUMENT (UNIT USE &OPTIONAL (CC-DISK-INIT-P NIL) (WRITE-P NIL)
			     &AUX TEM)
  "First value is decoded unit.  Second if T if arg was not already a decoded unit.
If second value is NIL, the caller should call DISPOSE-OF-UNIT eventually."
  (DECLARE (SPECIAL CC-DISK-INIT-P CADR:CC-DISK-LOWCORE CADR:CC-DISK-TYPE))
  (COND ((NUMBERP UNIT) UNIT)			;Local disk
	((AND (STRINGP UNIT) 
	      (STRING-EQUAL UNIT "CC" :END1 2))
	 (SETQ TEM (STRING-SEARCH-CHAR #/SPACE UNIT))
	 (LET ((CC-DISK-UNIT (IF (NULL TEM) 0 (READ-FROM-STRING UNIT NIL (1+ TEM)))))
	   (DECLARE (SPECIAL CC-DISK-UNIT))
	   (COND ((NOT (ZEROP CC-DISK-UNIT))
		  (FERROR NIL "CC can only talk to unit zero")))
	   (COND ((NULL CC-DISK-INIT-P)
		  (CADR:CC-DISK-INIT)
		  ;; Block 2 is part of the disk label!
		  (CADR:CC-DISK-WRITE 1 CADR:CC-DISK-LOWCORE 1)	;Save on blocks 1, 3.
		  (CADR:CC-DISK-WRITE 3 (1+ CADR:CC-DISK-LOWCORE) 1))
		 (T (SETQ CADR:CC-DISK-TYPE T)))   ;Dont try to read garbage label, etc.
	   (CLOSURE '(CC-DISK-UNIT CC-DISK-INIT-P)
		    'CC-DISK-HANDLER)))
	((AND (STRINGP UNIT)			;This makes test data.
	      (STRING-EQUAL UNIT "TEST" :END1 4))   
	 (SETQ TEM (STRING-SEARCH-CHAR #/SPACE UNIT))
	 (LET ((CC-DISK-UNIT (IF (NULL TEM) 0 (READ-FROM-STRING UNIT NIL (1+ TEM)))))
	   (DECLARE (SPECIAL CC-DISK-UNIT))
	   (CLOSURE '(CC-DISK-UNIT)
		    'CC-TEST-HANDLER)))
	((AND (STRINGP UNIT)			;Magtape interface.
	      (STRING-EQUAL UNIT "MT" :END1 2))
	 (SETQ TEM (STRING-SEARCH-CHAR #/SPACE UNIT))
	 (LET ((CC-DISK-UNIT (IF (NULL TEM) 0 (READ-FROM-STRING UNIT NIL (1+ TEM)))))
	   (COND ((NOT (ZEROP CC-DISK-UNIT))
		  (FERROR NIL "MT can only talk to unit zero")))
	   (FS:MAKE-BAND-MAGTAPE-HANDLER WRITE-P)))	;Temporarily, this fctn in RG;MT.
	((STRINGP UNIT)				;Open connection to foreign disk
	 ;; make @lm1 work as well as lm1
	 ;; if a host is stupid enough to have a name like @Losing  then use "@@Losing"
	 (IF (CHAR= #/@ (CHAR UNIT 0))
	     (SETQ UNIT (SUBSTRING UNIT 1)))
	 (LET ((REMOTE-DISK-CONN
		 (CHAOS:CONNECT (SUBSTRING UNIT 0 (SETQ TEM (STRING-SEARCH-CHAR #/SP UNIT)))
				"REMOTE-DISK" 25.))
	       (REMOTE-DISK-STREAM)
	       (REMOTE-DISK-UNIT (IF (NULL TEM) 0 (READ-FROM-STRING UNIT NIL (1+ TEM)))))
	   (DECLARE (SPECIAL REMOTE-DISK-CONN REMOTE-DISK-STREAM REMOTE-DISK-UNIT))
	   (AND (STRINGP REMOTE-DISK-CONN)
		(FERROR NIL "Cannot connect to ~S: ~A" UNIT REMOTE-DISK-CONN))
	   (SETQ REMOTE-DISK-STREAM (CHAOS:MAKE-STREAM REMOTE-DISK-CONN))
	   (FORMAT REMOTE-DISK-STREAM "SAY Disk being hacked remotely by ~A@~O -- ~A~%"
		   		      USER-ID
				      (GET-HOST-FROM-ADDRESS CHAOS:MY-ADDRESS :CHAOS)
				      USE)
	   (SEND REMOTE-DISK-STREAM :FORCE-OUTPUT)
	   (CLOSURE '(REMOTE-DISK-CONN REMOTE-DISK-STREAM REMOTE-DISK-UNIT)
		    'REMOTE-DISK-HANDLER)))
	(T (VALUES UNIT T))))				;Probably remote disk at higher level

(DEFUN DISPOSE-OF-UNIT (UNIT)
  (OR (NUMBERP UNIT) (SEND UNIT :DISPOSE)))

;;; :READ-COMPARE not supported, nothing uses it.
(DEFUN REMOTE-DISK-HANDLER (OP &REST ARGS)
  (DECLARE (SPECIAL REMOTE-DISK-CONN REMOTE-DISK-STREAM REMOTE-DISK-UNIT))
  (SELECTQ OP
    (:READ (LET ((RQB (CAR ARGS)))
	     (LET ((BLOCK (CADR ARGS))
		   (N-BLOCKS (ARRAY-LEADER RQB %DISK-RQ-LEADER-N-PAGES)))
	       (FORMAT REMOTE-DISK-STREAM "READ ~D ~D ~D~%" REMOTE-DISK-UNIT BLOCK N-BLOCKS)
	       (SEND REMOTE-DISK-STREAM :FORCE-OUTPUT)
	       (DO ((BLOCK BLOCK (1+ BLOCK))
		    (N-BLOCKS N-BLOCKS (1- N-BLOCKS))
		    (BLOCK-PKT-1 (GET-DISK-STRING RQB 0 484. T))
		    (BLOCK-PKT-2 (GET-DISK-STRING RQB 121. 484. T))
		    (BLOCK-PKT-3 (GET-DISK-STRING RQB 242. 56. T)))
		   ((ZEROP N-BLOCKS)
		    (RETURN-ARRAY BLOCK-PKT-3)
		    (RETURN-ARRAY BLOCK-PKT-2)
		    (RETURN-ARRAY BLOCK-PKT-1))
		 ;; Get 3 packets and form a block in the buffer
		 ;; RECEIVE-PARTITION-PACKET will throw if it gets to eof.
		 (RECEIVE-PARTITION-PACKET REMOTE-DISK-CONN BLOCK-PKT-1)
		 (RECEIVE-PARTITION-PACKET REMOTE-DISK-CONN BLOCK-PKT-2)
		 (RECEIVE-PARTITION-PACKET REMOTE-DISK-CONN BLOCK-PKT-3)
		 ;; Advance magic strings to next block
		 (%P-STORE-CONTENTS-OFFSET (+ (%P-CONTENTS-OFFSET BLOCK-PKT-1 3)
					      (* 4 PAGE-SIZE))
					   BLOCK-PKT-1 3)
		 (%P-STORE-CONTENTS-OFFSET (+ (%P-CONTENTS-OFFSET BLOCK-PKT-2 3)
					      (* 4 PAGE-SIZE))
					   BLOCK-PKT-2 3)
		 (%P-STORE-CONTENTS-OFFSET (+ (%P-CONTENTS-OFFSET BLOCK-PKT-3 3)
					      (* 4 PAGE-SIZE))
					   BLOCK-PKT-3 3)))))
    (:WRITE (LET ((RQB (CAR ARGS)))
	      (LET ((BLOCK (CADR ARGS))
		    (N-BLOCKS (ARRAY-LEADER RQB %DISK-RQ-LEADER-N-PAGES)))
		(FORMAT REMOTE-DISK-STREAM "WRITE ~D ~D ~D~%" REMOTE-DISK-UNIT BLOCK N-BLOCKS)
		(SEND REMOTE-DISK-STREAM :FORCE-OUTPUT)
		(DO ((BLOCK BLOCK (1+ BLOCK))
		     (N-BLOCKS N-BLOCKS (1- N-BLOCKS))
		     (BLOCK-PKT-1 (GET-DISK-STRING RQB 0 484. T))
		     (BLOCK-PKT-2 (GET-DISK-STRING RQB 121. 484. T))
		     (BLOCK-PKT-3 (GET-DISK-STRING RQB 242. 56. T)))
		    ((ZEROP N-BLOCKS)
		     (RETURN-ARRAY BLOCK-PKT-3)
		     (RETURN-ARRAY BLOCK-PKT-2)
		     (RETURN-ARRAY BLOCK-PKT-1))
		  ;; Transmit three packets from block in buffer
		  (TRANSMIT-PARTITION-PACKET REMOTE-DISK-CONN BLOCK-PKT-1)
		  (TRANSMIT-PARTITION-PACKET REMOTE-DISK-CONN BLOCK-PKT-2)
		  (TRANSMIT-PARTITION-PACKET REMOTE-DISK-CONN BLOCK-PKT-3)
		  ;; Advance magic strings to next block
		  (%P-STORE-CONTENTS-OFFSET (+ (%P-CONTENTS-OFFSET BLOCK-PKT-1 3)
					       (* 4 PAGE-SIZE))
					    BLOCK-PKT-1 3)
		  (%P-STORE-CONTENTS-OFFSET (+ (%P-CONTENTS-OFFSET BLOCK-PKT-2 3)
					       (* 4 PAGE-SIZE))
					    BLOCK-PKT-2 3)
		  (%P-STORE-CONTENTS-OFFSET (+ (%P-CONTENTS-OFFSET BLOCK-PKT-3 3)
					       (* 4 PAGE-SIZE))
					    BLOCK-PKT-3 3)))))
    (:DISPOSE (CHAOS:CLOSE-CONN REMOTE-DISK-CONN))
    (:UNIT-NUMBER REMOTE-DISK-UNIT)
    (:MACHINE-NAME
     (GET-HOST-FROM-ADDRESS (CHAOS:FOREIGN-ADDRESS REMOTE-DISK-CONN) :CHAOS))
    (:SAY
      (FORMAT REMOTE-DISK-STREAM "SAY ~A~%" (CAR ARGS))
      (SEND REMOTE-DISK-STREAM :FORCE-OUTPUT))
    (:HANDLES-LABEL NIL)
    ))

(DEFUN RECEIVE-PARTITION-PACKET (CONN INTO)
  (LET ((PKT (CHAOS:GET-NEXT-PKT CONN)))
    (AND (NULL PKT) (FERROR NIL "Connection ~S broken" CONN))
    (SELECT (CHAOS:PKT-OPCODE PKT)
      (CHAOS:DAT-OP
       (COPY-ARRAY-CONTENTS (CHAOS:PKT-STRING PKT) INTO)
       (LET ((CORRECT (AREF PKT (+ (FLOOR (ARRAY-LENGTH INTO) 2) #o10)))
	     (ACTUAL (CHECKSUM-STRING INTO)))
	 (OR (= CORRECT ACTUAL)
	     (FORMAT T "~&Checksum error, correct=~O, actual=~O~%" CORRECT ACTUAL)))
       (CHAOS:RETURN-PKT PKT))
      (CHAOS:EOF-OP
       (CHAOS:RETURN-PKT PKT)
       (*THROW 'EOF NIL))
      (OTHERWISE
        (FERROR NIL "~S is illegal packet opcode, pkt ~S, received for connection ~S"
                    (CHAOS:PKT-OPCODE PKT) PKT CONN)))))

(DEFUN TRANSMIT-PARTITION-PACKET (CONN OUTOF)
  (LET ((PKT (CHAOS:GET-PKT)))
    (COPY-ARRAY-CONTENTS OUTOF (CHAOS:PKT-STRING PKT))
    (SETF (AREF PKT (+ (FLOOR (ARRAY-LENGTH OUTOF) 2) #o10)) (CHECKSUM-STRING OUTOF))
    (SETF (CHAOS:PKT-NBYTES PKT) (+ (ARRAY-LENGTH OUTOF) 2))
    (CHAOS:SEND-PKT CONN PKT)))

(DEFUN CHECKSUM-STRING (STR)
  (DO ((CKSM 0 (+ (AREF STR I) CKSM))
       (I 0 (1+ I))
       (N (ARRAY-LENGTH STR)))
      (( I N) (LOGAND #o177777 CKSM))))

(DEFUN CC-DISK-HANDLER (OP &REST ARGS)
  (DECLARE (SPECIAL CC-DISK-UNIT CC-DISK-INIT-P CADR:CC-DISK-LOWCORE CADR:CC-DISK-TYPE))
  (SELECTQ OP
    (:READ (LET ((RQB (CAR ARGS)))
	     (LET ((BLOCK (CADR ARGS))
		   (N-BLOCKS (ARRAY-LEADER RQB %DISK-RQ-LEADER-N-PAGES)))
	       (DO ((BLOCK BLOCK (1+ BLOCK))
		    (N-BLOCKS N-BLOCKS (1- N-BLOCKS))
		    (BUF (RQB-BUFFER RQB))
		    (BUF-IDX -1))
		   ((ZEROP N-BLOCKS))
		 (CADR:CC-DISK-READ BLOCK CADR:CC-DISK-LOWCORE 1)  ;Was 2 - doesn't that clobber the block above LOWCORE?
		 ;; Following code transmogrified from DBG-READ-XBUS and DBG-READ.
		 ;; You don't really think this would be reasonable via DL11 or debug kludge,
		 ;; do you?
		 ;;  Yes it is reasonable, you total fool!  Hacking the disk label is one of 
		 ;;  the most useful things to do.  You really made me do alot of work, and
		 ;;  it was not appreciated one bit.  --HIC
		 (IF (EQ CADR:DBG-ACCESS-PATH 'CADR:BUSINT)
		     (LET ((UBUS-WD-LOC
			     (LSH (CADR:DBG-SETUP-UNIBUS-MAP 17
						   (ASH CADR:CC-DISK-LOWCORE 8)) -1)))
		       (%UNIBUS-WRITE #o766110 0)  ;high unibus adr bit and DBG-NXM-INHIBIT
		       (DOTIMES (W #o400)
			 (%UNIBUS-WRITE #o766114 UBUS-WD-LOC)
			 (SETF (AREF BUF (INCF BUF-IDX)) (%UNIBUS-READ #o766100))
			 (%UNIBUS-WRITE #o766114 (INCF UBUS-WD-LOC))
			 (SETF (AREF BUF (INCF BUF-IDX)) (%UNIBUS-READ #o766100))
			 (INCF UBUS-WD-LOC)))
		     (DO ((ADR (ASH CADR:CC-DISK-LOWCORE 8) (1+ ADR))
			  (WORD)
			  (W 0 (1+ W)))
			 (( W #o400))
		       (SETQ WORD (CADR:PHYS-MEM-READ ADR))
		       (SETF (AREF BUF (INCF BUF-IDX)) (LOGAND #o177777 WORD))
		       (SETF (AREF BUF (INCF BUF-IDX)) (LDB #o2020 WORD))))))))
    (:WRITE (LET ((RQB (CAR ARGS)))
	      (LET ((BLOCK (CADR ARGS))
		    (N-BLOCKS (ARRAY-LEADER RQB %DISK-RQ-LEADER-N-PAGES)))
		(DO ((BLOCK BLOCK (1+ BLOCK))
		     (N-BLOCKS N-BLOCKS (1- N-BLOCKS))
		     (BUF (RQB-BUFFER RQB))
		     (BUF-IDX -1))
		    ((ZEROP N-BLOCKS))
		  (IF (EQ CADR:DBG-ACCESS-PATH 'CADR:BUSINT)
		      (LET ((UBUS-WD-LOC
			      (LSH (CADR:DBG-SETUP-UNIBUS-MAP 17
						    (ASH CADR:CC-DISK-LOWCORE 8)) -1)))
			(%UNIBUS-WRITE #o766110 0)  ;high unibus adr bit and DBG-NXM-INHIBIT
			(DOTIMES (W #o400)
			  (%UNIBUS-WRITE #o766114 UBUS-WD-LOC)
			  (%UNIBUS-WRITE #o766100 (AREF BUF (INCF BUF-IDX)))
			  (%UNIBUS-WRITE #o766114 (INCF UBUS-WD-LOC))
			  (%UNIBUS-WRITE #o766100 (AREF BUF (INCF BUF-IDX)))
			  (INCF UBUS-WD-LOC)))
		      (DO ((ADR (ASH CADR:CC-DISK-LOWCORE 8) (1+ ADR))
			   (WORD)
			   (W 0 (1+ W)))
			  (( W #o400))
			(SETQ WORD (DPB (AREF BUF (SETQ BUF-IDX (+ 2 BUF-IDX)))
					#o2020
					(AREF BUF (1- BUF-IDX))))
			(CADR:PHYS-MEM-WRITE ADR WORD)))
		  ;; If writing label, init some params such as CC:BLOCKS-PER-CYLINDER.
		  (IF (ZEROP BLOCK)
		      (CC:READ-LABEL-1 CADR:CC-DISK-LOWCORE))
	RETRY	  (CADR:CC-DISK-WRITE BLOCK CADR:CC-DISK-LOWCORE 1)
		  (COND ((AND CC-REMOTE-DISK-WRITE-CHECK 
			      (NULL (CADR:CC-DISK-READ BLOCK
						       (1+ CADR:CC-DISK-LOWCORE)
						       1)))
			 (GO RETRY)))		;read it back to let hardware check ECC, etc.
		  ))))

    (:DISPOSE (COND ((NULL CC-DISK-INIT-P)
		     (CADR:CC-DISK-READ 1 CADR:CC-DISK-LOWCORE 1)
		     (CADR:CC-DISK-READ 3 (1+ CADR:CC-DISK-LOWCORE) 1)) ;Restore saved core
		    (T (SETQ CADR:CC-DISK-TYPE NIL))))	;Otherwise read label now that it
							; maybe isnt garbage
    (:UNIT-NUMBER 0)
    (:MACHINE-NAME "via CC")
    (:SAY (FORMAT T "CC-SAY ~A~%" (CAR ARGS)))
    (:HANDLES-LABEL NIL)))

(DEFUN CC-TEST-HANDLER (OP &REST ARGS)
  (DECLARE (SPECIAL CC-DISK-UNIT))
  (SELECTQ OP
    (:READ (LET ((RQB (CAR ARGS)))
	     (LET ((BLOCK (CADR ARGS))
		   (N-BLOCKS (ARRAY-LEADER RQB %DISK-RQ-LEADER-N-PAGES)))
	       (DO ((BLOCK BLOCK (1+ BLOCK))
		    (N-BLOCKS N-BLOCKS (1- N-BLOCKS))
		    (BUF (RQB-BUFFER RQB))
		    (BUF-IDX -1))
		   ((ZEROP N-BLOCKS))
		 (SELECTQ CC-DISK-UNIT
		   (0 (DOTIMES (W #o400)	;Unit 0 makes block,,word
			(SETF (AREF BUF (INCF BUF-IDX)) BLOCK)
			(SETF (AREF BUF (INCF BUF-IDX)) W)))
		   (1 (DOTIMES (W #o400)	;Unit 1 makes block#7777,,word
			(SETF (AREF BUF (INCF BUF-IDX)) (LOGXOR #o7777 BLOCK))
			(SETF (AREF BUF (INCF BUF-IDX)) W))))))))
    (:WRITE (LET ((RQB (CAR ARGS)))
	      (LET ((BLOCK (CADR ARGS))
		    (N-BLOCKS (ARRAY-LEADER RQB %DISK-RQ-LEADER-N-PAGES)))
		(DO ((BLOCK BLOCK (1+ BLOCK))
		     (N-BLOCKS N-BLOCKS (1- N-BLOCKS))
		    (BUF (RQB-BUFFER RQB))
		    ;; Following code is transmogrified from DBG-WRITE-XBUS
		    (BUF-IDX -1)
		    (W1) (W2) (ERRS 0) (MAX-ERRS 3))
		    ((ZEROP N-BLOCKS))
		 (SELECTQ CC-DISK-UNIT
		   (0 (DOTIMES (W #o400)	;Unit 0 should be block,,word
			(SETQ W1 (AREF BUF (INCF BUF-IDX))
			      W2 (AREF BUF (INCF BUF-IDX)))
			(COND ((OR (NOT (= BLOCK W1))
				   (NOT (= W2 W)))
			       (FORMAT T "~%Block ~O WD ~O should be ~O,,~O is ~O,,~O"
				       BLOCK W BLOCK W W1 W2)
			       (IF (> (INCF ERRS) MAX-ERRS)
				   (RETURN NIL))))))
		   (1 (DOTIMES (W #o400)  ;Unit 1 should be block#7777,,word
			(SETQ W1 (AREF BUF (INCF BUF-IDX))
			      W2 (AREF BUF (INCF BUF-IDX)))
			(COND ((OR (NOT (= (LOGXOR #o7777 BLOCK) W1))
				   (NOT (= W2 W)))
			       (FORMAT T "~%Block ~O WD ~O should be ~O,,~O is ~O,,~O"
				       BLOCK W (LOGXOR BLOCK #o7777) W W1 W2)
			       (IF (> (INCF ERRS) MAX-ERRS)
				   (RETURN NIL)))))))))))
    (:DISPOSE NIL)
    (:UNIT-NUMBER CC-DISK-UNIT)
    (:MACHINE-NAME "TEST")
    (:SAY (FORMAT T "CC-TEST-SAY ~A~%" (CAR ARGS)))
    (:HANDLES-LABEL T)
    (:FIND-DISK-PARTITION (VALUES  0 #o100000 NIL))
    (:PARTITION-COMMENT (FORMAT NIL "TEST ~D" CC-DISK-UNIT))
    (:UPDATE-PARTITION-COMMENT NIL)
    ))


;;;; Internals

;;; Read the label from specified unit into an RQB, and set up the
;;; disk configuration table if it is a local unit.
;;; The label uses even-numbered pages, with the odd-numbered pages ignored.
;;; That is because booting uses them as scratch pages.
;;; CC-DISK-HANDLER also uses block 1 and 3 as scratch.
(DEFUN READ-DISK-LABEL (RQB UNIT)
  (LET (RQB1)
    (UNWIND-PROTECT
	(PROGN
	  (SETQ RQB1 (GET-DISK-RQB))
	  (DISK-READ RQB1 UNIT 0)
	  (COPY-ARRAY-PORTION (RQB-BUFFER RQB1) 0 (* 2 PAGE-SIZE)
			      (RQB-BUFFER RQB) 0 (* 2 PAGE-SIZE))
	  (DISK-READ RQB1 UNIT 2)
	  (COPY-ARRAY-PORTION (RQB-BUFFER RQB1) 0 (* 2 PAGE-SIZE)
			      (RQB-BUFFER RQB) (* 2 PAGE-SIZE) (* 4 PAGE-SIZE))
	  (DISK-READ RQB1 UNIT 4)
	  (COPY-ARRAY-PORTION (RQB-BUFFER RQB1) 0 (* 2 PAGE-SIZE)
			      (RQB-BUFFER RQB) (* 4 PAGE-SIZE) (* 6 PAGE-SIZE)))
      (AND RQB1 (RETURN-DISK-RQB RQB1))))
  (IF (NUMBERP UNIT)
      (LET ((BFR (RQB-BUFFER RQB)))
	(COND ((AND (= (AREF BFR 0) (+ (LSH #/A 8) #/L))
		    (= (AREF BFR 1) (+ (LSH #/L 8) #/B))
		    (= (AREF BFR 2) 1))
	       (ASET (AREF BFR 6) DISK-HEADS-PER-CYLINDER-ARRAY UNIT)
	       (ASET (AREF BFR 10) DISK-SECTORS-PER-TRACK-ARRAY UNIT))))))

(DEFUN WRITE-DISK-LABEL (RQB UNIT)
  (OR (STRING-EQUAL (GET-DISK-STRING RQB 0 4) "LABL")
      (FERROR NIL "Attempt to write garbage label"))
  (LET (RQB1)
    (UNWIND-PROTECT
	(PROGN
	  (SETQ RQB1 (GET-DISK-RQB))
	  (COPY-ARRAY-PORTION (RQB-BUFFER RQB) 0 (* 2 PAGE-SIZE)
			      (RQB-BUFFER RQB1) 0 (* 2 PAGE-SIZE))
	  (DISK-WRITE RQB1 UNIT 0)
	  (COPY-ARRAY-PORTION (RQB-BUFFER RQB) (* 2 PAGE-SIZE) (* 4 PAGE-SIZE)
			      (RQB-BUFFER RQB1) 0 (* 2 PAGE-SIZE))
	  (DISK-WRITE RQB1 UNIT 2)
	  (COPY-ARRAY-PORTION (RQB-BUFFER RQB) (* 4 PAGE-SIZE) (* 6 PAGE-SIZE)
			      (RQB-BUFFER RQB1) 0 (* 2 PAGE-SIZE))
	  (DISK-WRITE RQB1 UNIT 4))
      (AND RQB1 (RETURN-DISK-RQB RQB1)))))

(DEFUN GET-DISK-STRING (RQB WORD-ADDRESS N-CHARACTERS &OPTIONAL (SHARE-P NIL))
  "Return a string containing the contents of a part of RQB's data.
The data consists of N-CHARACTERS characters starting at data word WORD-ADDRESS.
/(The first word of data is WORD-ADDRESS = 0).
SHARE-P non-NIL means return an indirect array that overlaps the RQB,
Otherwise return a string containing the data, except for trailing 0's
 (in which case the string returned may in fact be shorted than N-CHARACTERS.)"
  (IF SHARE-P
      (NSUBSTRING (RQB-8-BIT-BUFFER RQB) (* 4 WORD-ADDRESS)
					 (+ (* 4 WORD-ADDRESS) N-CHARACTERS))
    (LET* ((STR (SUBSTRING (RQB-8-BIT-BUFFER RQB) (* 4 WORD-ADDRESS)
						  (+ (* 4 WORD-ADDRESS) N-CHARACTERS)))
	   (IDX (STRING-REVERSE-SEARCH-NOT-CHAR 0 STR)))
      (ADJUST-ARRAY-SIZE STR (IF IDX (1+ IDX) 0))
      STR)))

(DEFUN PUT-DISK-STRING (RQB STR WORD-ADDRESS N-CHARACTERS)
  "Store the contents of string STR into RQB's data at WORD-ADDRESS.
N-CHARACTERS characters are stored, padding STR with zeros if it is not that long."
  (LET ((START (* 4 WORD-ADDRESS))
	(END (+ (* 4 WORD-ADDRESS) N-CHARACTERS)))
    (ARRAY-INITIALIZE (RQB-8-BIT-BUFFER RQB) 0 START END)
    (COPY-ARRAY-PORTION
      STR 0 (STRING-LENGTH STR)
      (RQB-8-BIT-BUFFER RQB) START (MIN END (+ START (STRING-LENGTH STR))))))

(DEFUN GET-DISK-FIXNUM (RQB WORD-ADDRESS)
  "Return the contents of data word WORD-ADDRESS in RQB, as a number."
  (DPB (AREF (RQB-BUFFER RQB) (1+ (* 2 WORD-ADDRESS)))
       #o2020
       (AREF (RQB-BUFFER RQB) (* 2 WORD-ADDRESS))))

(DEFUN PUT-DISK-FIXNUM (RQB VAL WORD-ADDRESS)
  "Store VAL into data word WORD-ADDRESS of RQB."
  (SETF (AREF (RQB-BUFFER RQB) (* 2 WORD-ADDRESS)) (LDB #o0020 VAL))
  (SETF (AREF (RQB-BUFFER RQB) (1+ (* 2 WORD-ADDRESS))) (LDB #o2020 VAL)))

(DEFUN FIND-DISK-PARTITION (NAME &OPTIONAL RQB (UNIT 0) (ALREADY-READ-P NIL) CONFIRM-WRITE
			    &AUX (RETURN-RQB NIL))
  "Search the label of disk unit UNIT for a partition named NAME.
Returns three values describing what was found, or NIL if none found.
The values are the first block number of the partition,
the length in disk blocks of the partition,
and the location in the label (in words) of the data for this partition."
  (DECLARE (VALUES FIRST-BLOCK N-BLOCKS LABEL-LOC NAME))
  (IF (AND (CLOSUREP UNIT)
	   (FUNCALL UNIT :HANDLES-LABEL))
      (FUNCALL UNIT :FIND-DISK-PARTITION NAME)
    (UNWIND-PROTECT
	(PROGN
	  (IF (NULL RQB)
	      (SETQ RETURN-RQB T
		    RQB (GET-DISK-LABEL-RQB)))
	  (OR ALREADY-READ-P (READ-DISK-LABEL RQB UNIT))
	  (DO ((N-PARTITIONS (GET-DISK-FIXNUM RQB #o200))
	       (WORDS-PER-PART (GET-DISK-FIXNUM RQB #o201))
	       (I 0 (1+ I))
	       (LOC #o202 (+ LOC WORDS-PER-PART)))
	      ((= I N-PARTITIONS) NIL)
	    (WHEN (STRING-EQUAL (GET-DISK-STRING RQB LOC 4) NAME)
	      (AND CONFIRM-WRITE
		   (NOT (FQUERY FORMAT:YES-OR-NO-QUIETLY-P-OPTIONS
				"Do you really want to clobber partition ~A ~
				 ~:[~*~;on unit ~D ~](~A)? "
				NAME (NUMBERP UNIT) UNIT
				(GET-DISK-STRING RQB
						 (+ LOC 3)
						 (* 4 (- (GET-DISK-FIXNUM RQB #o201) 3)))))
		   (RETURN-FROM FIND-DISK-PARTITION (VALUES NIL T)))
	      (RETURN-FROM FIND-DISK-PARTITION (VALUES (GET-DISK-FIXNUM RQB (+ LOC 1))
						       (GET-DISK-FIXNUM RQB (+ LOC 2))
						       LOC
						       NAME)))))
      (WHEN RETURN-RQB (RETURN-DISK-RQB RQB)))))

(DEFUN FIND-DISK-PARTITION-FOR-READ (NAME &OPTIONAL RQB (UNIT 0) (ALREADY-READ-P NIL)
				     		        (NUMBER-PREFIX "LOD"))
  "Like FIND-DISK-PARTITION except there is error checking and coercion.
If NAME is a number, its printed representation is appended to NUMBER-PREFIX
to get the partition name to use."
  (DECLARE (VALUES FIRST-BLOCK N-BLOCKS LABEL-LOC NAME))
  (TYPECASE NAME
    (NUMBER
     (SETQ NAME (FORMAT NIL "~A~D" NUMBER-PREFIX NAME)))
    (SYMBOL
     (SETQ NAME (SYMBOL-NAME NAME)))
    (STRING)
    (T
     (FERROR NIL "~S is not a valid partition name" NAME)))
  (MULTIPLE-VALUE-BIND (FIRST-BLOCK N-BLOCKS LABEL-LOC)
      (FIND-DISK-PARTITION NAME RQB UNIT ALREADY-READ-P)
    (IF (NOT (NULL FIRST-BLOCK))
	(VALUES FIRST-BLOCK N-BLOCKS LABEL-LOC NAME)
      (FERROR NIL "No partition named /"~A/" exists on disk unit ~D." NAME UNIT))))

(DEFUN FIND-DISK-PARTITION-FOR-WRITE (NAME &OPTIONAL RQB (UNIT 0) (ALREADY-READ-P NIL)
						    (NUMBER-PREFIX "LOD"))
  "Like FIND-DISK-PARTITION except there is error checking, coercion, and confirmation.
If NAME is a number, its printed representation is appended to NUMBER-PREFIX
to get the partition name to use.
Returns NIL if the partition specified is valid but the user refuses to confirm."
  (DECLARE (VALUES FIRST-BLOCK N-BLOCKS LABEL-LOC NAME))
  (COND ((NUMBERP NAME) (SETQ NAME (FORMAT NIL "~A~D" NUMBER-PREFIX NAME)))
	((SYMBOLP NAME) (SETQ NAME (GET-PNAME NAME)))
	((NOT (STRINGP NAME)) (FERROR NIL "~S is not a valid partition name" NAME)))
  (LET* ((CURRENT-BAND (CURRENT-BAND))
	 (CURRENT-BAND-BASE-BAND (INC-BAND-BASE-BAND CURRENT-BAND 0))
	 (CURRENT-RUNNING-BAND (STRING-APPEND "LOD"
					      (LDB #o2010 CURRENT-LOADED-BAND))))
    (COND ((NOT (EQ UNIT 0)))
	  ((STRING-EQUAL NAME CURRENT-BAND)
	   (FORMAT T "~&It is dangerous to write into the current band.
If there is a disk error saving,
the machine's current band will be invalid
and cold-booting will not work."))
	  ((AND CURRENT-BAND-BASE-BAND
		(STRING-EQUAL NAME CURRENT-BAND-BASE-BAND))
	   (FORMAT T "~&It is dangerous to write into the current band's base band.
The current band ~A is an incremental band
and requires ~A, its base band, in order to cold-boot.
Overwriting that band makes the current band invalid
and the machine will be unbootable until a valid band is selected."
		   CURRENT-BAND CURRENT-BAND-BASE-BAND))
	  ((STRING-EQUAL NAME CURRENT-RUNNING-BAND)
	   (FORMAT T "~&It may be unwise to overwrite the currently running band.
Do it only if you are sure the current band for booting (~A)
will work properly."
		   CURRENT-BAND))))
  (MULTIPLE-VALUE-BIND (FIRST-BLOCK N-BLOCKS LABEL-LOC)
      (FIND-DISK-PARTITION NAME RQB UNIT ALREADY-READ-P T)
    (IF (NOT (NULL FIRST-BLOCK))
	(VALUES FIRST-BLOCK N-BLOCKS LABEL-LOC NAME)
      (IF (NULL N-BLOCKS)
	  (FERROR NIL "No partition named /"~A/" exists on disk unit ~D." NAME UNIT)
	NIL))))

(DEFUN PARTITION-LIST (&OPTIONAL RQB (UNIT 0) ALREADY-READ-P &AUX RETURN-RQB)
  "Returns the data of the disk label on unit UNIT.
The value is a list with one element per partition,
with the format (<name> <base> <size> <comment> <desc-loc>).
RQB is an rqb to use, or NIL meaning allocate one temporarily."
  (UNWIND-PROTECT
      (PROGN (IF (NULL RQB)
		 (WITHOUT-INTERRUPTS
		   (SETQ RETURN-RQB T
			 RQB (GET-DISK-LABEL-RQB))))
	     (UNLESS ALREADY-READ-P
	       (READ-DISK-LABEL RQB UNIT))
	     (LET ((RESULT (MAKE-LIST (GET-DISK-FIXNUM RQB #o200)))
		   (WORDS-PER-PART (GET-DISK-FIXNUM RQB #o201)))
	       (DO ((LOC #o202 (+ LOC WORDS-PER-PART))
		    (R RESULT (CDR R)))
		   ((NULL R) RESULT)
		 (SETF (CAR R)
		       (LIST (GET-DISK-STRING RQB LOC 4)
			     (GET-DISK-FIXNUM RQB (+ LOC 1))
			     (GET-DISK-FIXNUM RQB (+ LOC 2))
			     (GET-DISK-STRING RQB (+ LOC 3)
					          (* 4 (- (GET-DISK-FIXNUM RQB #o201) 3)))
			     LOC)))))
    (IF RETURN-RQB (RETURN-DISK-RQB RQB))))

;;; This is a hack to allow one to easily find if a partition he wants is available.
(DEFUN PRINT-AVAILABLE-BANDS (&OPTIONAL (WHICH "LOD")
					(MACHINES (CHAOS:FINGER-ALL-LMS 'IGNORE NIL T))
			      &AUX (WL (AND (STRINGP WHICH)
					    (MIN (ARRAY-ACTIVE-LENGTH WHICH) 4)))
			      DONT-DISPOSE
			      RQB UNIT TEM PARTITION-LIST PARTITION-LIST-ALIST)
  "Print a summary of the contents of partitions existing on MACHINES.
MACHINES defaults to all free Lisp machines.
Only partitions whose names start with WHICH are mentioned.
WHICH defaults to /"LOD/"."
  (CHECK-TYPE WHICH (OR STRING (MEMBER T)) "a string or T")
  (UNWIND-PROTECT
      (PROGN
	(SETQ RQB (GET-DISK-RQB))
	(DOLIST (M MACHINES)
	  (UNWIND-PROTECT
	      (SETF (VALUES UNIT DONT-DISPOSE)
		    (DECODE-UNIT-ARGUMENT M "Examining Label"))
	    (SETQ PARTITION-LIST (PARTITION-LIST NIL UNIT))
	    (UNLESS DONT-DISPOSE (DISPOSE-OF-UNIT UNIT)))
	  (DOLIST (PARTITION PARTITION-LIST)
	    (AND (OR (EQ WHICH T)
		     (STRING-EQUAL (CAR PARTITION) WHICH 0 0 WL WL))
		 (PLUSP (STRING-LENGTH (FOURTH PARTITION)))
		 (IF (SETQ TEM (SYS:ASSOC-EQUAL (FOURTH PARTITION) PARTITION-LIST-ALIST))
		     (RPLACD (LAST TEM) (NCONS (LIST M (FIRST PARTITION))))
		     (PUSH (LIST* (FOURTH PARTITION)
				  (LIST M (FIRST PARTITION))
				  NIL)
			   PARTITION-LIST-ALIST))))))
    (RETURN-DISK-RQB RQB))
  (SETQ PARTITION-LIST-ALIST (SORTCAR PARTITION-LIST-ALIST #'STRING-LESSP))
  (DOLIST (P PARTITION-LIST-ALIST)
    (FORMAT T "~%~A:~20T~:{~<~%~20T~2:;~A ~A~>~:^, ~}" (CAR P) (CDR P))))

(DEFUN SYS-COM-PAGE-NUMBER (16B-BUFFER INDEX)
  (LSH
    (LOGAND
      (SELECT-PROCESSOR
	(:CADR (1- 1_24.))
	(:LAMBDA -1))
      (LOGIOR (LSH (AREF 16B-BUFFER (1+ (* 2 INDEX))) #o20)
	      (AREF 16B-BUFFER (* 2 INDEX))))
    (- %%Q-POINTER-WITHIN-PAGE)))

(DEFUN DESCRIBE-PARTITION (PART &OPTIONAL (UNIT 0)
			   &AUX PART-BASE PART-SIZE RQB
			   COMPRESSED-FORMAT-P INCREMENTAL-BAND-P
			   VALID-SIZE HIGHEST-VIRTUAL-ADDRESS
			   DESIRED-UCODE-VERSION DONT-DISPOSE)
  "Print information about partition PART on unit UNIT.
UNIT can be a disk unit number, the name of a machine on the chaos net,
or /"CC/" which refers to the machine being debugged by this one."
  (SETF (VALUES UNIT DONT-DISPOSE)
	(DECODE-UNIT-ARGUMENT UNIT (FORMAT NIL "describing ~A partition" PART)))
  (UNWIND-PROTECT
    (PROGN
      (MULTIPLE-VALUE (PART-BASE PART-SIZE)
	(FIND-DISK-PARTITION-FOR-READ PART NIL UNIT))
      (SETQ RQB (GET-DISK-RQB))
      (SETQ VALID-SIZE
	    (COND ((OR (NUMBERP PART) (STRING-EQUAL PART "LOD" :END1 3))
		   (DISK-READ RQB UNIT (1+ PART-BASE))
		   (LET ((BUF (RQB-BUFFER RQB)))
		     (SETQ COMPRESSED-FORMAT-P
			   (= #o1000 (AREF BUF (* 2 %SYS-COM-BAND-FORMAT))))
		     (SETQ INCREMENTAL-BAND-P
			   (= #o1001 (AREF BUF (* 2 %SYS-COM-BAND-FORMAT))))
		     (SETQ VALID-SIZE (SYS-COM-PAGE-NUMBER BUF %SYS-COM-VALID-SIZE))
		     (SETQ VALID-SIZE (IF (AND (> VALID-SIZE #o10)
					       ( VALID-SIZE PART-SIZE))
					  VALID-SIZE
					PART-SIZE))
		     (SETQ HIGHEST-VIRTUAL-ADDRESS
			   (SYS-COM-PAGE-NUMBER BUF %SYS-COM-HIGHEST-VIRTUAL-ADDRESS))
		     (SETQ DESIRED-UCODE-VERSION
			   (AREF BUF (* 2 %SYS-COM-DESIRED-MICROCODE-VERSION)))
		     VALID-SIZE))
		  (T PART-SIZE)))
      (FORMAT T "~%Partition ~A starts at ~D and is ~D pages long."
	      (STRING-UPCASE PART) PART-BASE PART-SIZE)
      (IF (OR COMPRESSED-FORMAT-P INCREMENTAL-BAND-P)
	  (PROGN
	    (IF COMPRESSED-FORMAT-P
		(FORMAT T "~%It is a compressed world-load.")
	      (FORMAT T "~%It is an incremental band with base band ~A."
		      (INC-BAND-BASE-BAND PART UNIT)))
	    (FORMAT T "~%Data length is ~D pages, highest virtual page number is ~D."
		    VALID-SIZE HIGHEST-VIRTUAL-ADDRESS))
	(FORMAT T "~%It is in non-compressed format, data length ~D pages." VALID-SIZE))
      (IF DESIRED-UCODE-VERSION
	  (FORMAT T "~%Goes with microcode version ~D." DESIRED-UCODE-VERSION)))
    (UNLESS DONT-DISPOSE (DISPOSE-OF-UNIT UNIT))
    (RETURN-DISK-RQB RQB)))

(DEFUN DESCRIBE-PARTITIONS (&OPTIONAL (UNIT 0) &AUX DONT-DISPOSE)
  "Describes all of the partitions of UNIT, or the standard disk if unit is not supplied."
  (SETF (VALUES UNIT DONT-DISPOSE)
	(DECODE-UNIT-ARGUMENT UNIT "describing partitions"))
  (UNWIND-PROTECT
      (LOOP FOR (BAND . REST) IN (PARTITION-LIST NIL UNIT)
	    DOING
	    (FORMAT T "~%")
	    (DESCRIBE-PARTITION BAND UNIT))
    (UNLESS DONT-DISPOSE (DISPOSE-OF-UNIT UNIT))))

(DEFUN FIND-PLAUSIBLE-PARTITIONS (UNIT START END &AUX RQB DONT-DISPOSE)
  "Search disk unit UNIT from block START to just before block END for valid-looking Lisp worlds.
Use this if a disk label is clobbered.
Each time a block is found that looks like it could be
where the beginning of a partition ought to be,
an entry is printed.  Ignore those whose printed Ucode versions are unreasonable.
If there are two valid-looking entries close together on the disk,
the one with the higher disk address is more likely to be followed
by an actual good Lisp world."
  (SETF (VALUES UNIT DONT-DISPOSE)
	(DECODE-UNIT-ARGUMENT UNIT (FORMAT NIL "searching for partitions")))
  (UNWIND-PROTECT
      (PROGN
	(SETQ RQB (GET-DISK-RQB 20))
	(DO ((RQB-BASE START (+ RQB-BASE 20)))
	    ((>= RQB-BASE END))
	  (DISK-READ RQB UNIT RQB-BASE)
	  (DO ((IDX 0 (1+ IDX)))
	      ((= IDX 20))
	    (WHEN (= #O1000
		     (AREF (RQB-BUFFER RQB)
			   (+ (* PAGE-SIZE 2 IDX) (* 2 %SYS-COM-BAND-FORMAT))))
	      (FORMAT T "~%Possible at block ~d:~%" (+ RQB-BASE IDX -1))
	      (FORMAT T "Ucode version ~d~%"
		      (AREF (RQB-BUFFER RQB)
			    (+ (* PAGE-SIZE 2 IDX)
			       (* 2 %SYS-COM-DESIRED-MICROCODE-VERSION))))))))
    (WHEN RQB (RETURN-DISK-RQB RQB))
    (UNLESS DONT-DISPOSE (DISPOSE-OF-UNIT UNIT))))

(DEFUN GET-UCODE-VERSION-OF-BAND (PART &OPTIONAL (UNIT 0)
				  &AUX PART-BASE PART-SIZE RQB DONT-DISPOSE)
  "Return the microcode version number that partition PART on unit UNIT should be run with.
This is only meaningful when used on a LOD partition.
UNIT can be a disk unit number, the name of a machine on the chaos net,
or /"CC/" which refers to the machine being debugged by this one."
  (SETF (VALUES UNIT DONT-DISPOSE)
	(DECODE-UNIT-ARGUMENT UNIT (FORMAT NIL "Finding microcode for ~A partition" PART)))
  (UNWIND-PROTECT
      (PROGN
	(MULTIPLE-VALUE (PART-BASE PART-SIZE)
	  (FIND-DISK-PARTITION-FOR-READ PART NIL UNIT))
	(SETQ RQB (GET-DISK-RQB))
	(COND ((OR (NUMBERP PART) (STRING-EQUAL PART "LOD" :END1 3))
	       (DISK-READ RQB UNIT (1+ PART-BASE))
	       (LET ((BUF (RQB-BUFFER RQB)))
		 (AREF BUF (* 2 %SYS-COM-DESIRED-MICROCODE-VERSION))))))
    (UNLESS DONT-DISPOSE (DISPOSE-OF-UNIT UNIT))
    (RETURN-DISK-RQB RQB)))

(DEFUN MEASURED-SIZE-OF-PARTITION (PART &OPTIONAL (UNIT 0)
				   &AUX PART-BASE PART-SIZE RQB DONT-DISPOSE)
  "Return the number of blocks of partition PART on unit UNIT actually containing data.
Except for LOD partitions, this is the total size.
The second value, for LOD partitions, is the required PAGE partition size.
The third value, for LOD partitions, is the desired microcode version.
UNIT can be a disk unit number, the name of a machine on the chaos net,
or /"CC/" which refers to the machine being debugged by this one."
  (DECLARE (:VALUES PARTITION-DATA-SIZE VIRTUAL-MEMORY-SIZE MICROCODE-VERSION))
  (SETF (VALUES UNIT DONT-DISPOSE)
	(DECODE-UNIT-ARGUMENT UNIT (FORMAT NIL "sizing ~A partition" PART)))
  (UNWIND-PROTECT
    (PROGN
      (SETQ RQB (GET-DISK-RQB))
      (MULTIPLE-VALUE (PART-BASE PART-SIZE)
	(FIND-DISK-PARTITION-FOR-READ PART NIL UNIT))
      (COND ((OR (NUMBERP PART) (STRING-EQUAL PART "LOD" :END1 3))
	     (DISK-READ RQB UNIT (1+ PART-BASE))
	     (LET* ((BUF (RQB-BUFFER RQB))
		    (SIZE (SYS-COM-PAGE-NUMBER BUF %SYS-COM-VALID-SIZE))
		    (FINAL-SIZE (IF (AND (> SIZE #o10) ( SIZE PART-SIZE)) SIZE PART-SIZE))
		    (MEMORY-SIZE
		      (SYS-COM-PAGE-NUMBER BUF %SYS-COM-HIGHEST-VIRTUAL-ADDRESS)))
	       (VALUES FINAL-SIZE
		       (IF (= (AREF BUF (* 2 %SYS-COM-BAND-FORMAT)) #o1000)
			   MEMORY-SIZE FINAL-SIZE)
		       (AREF BUF (* 2 %SYS-COM-DESIRED-MICROCODE-VERSION)))))
	    (T PART-SIZE)))
    (UNLESS DONT-DISPOSE (DISPOSE-OF-UNIT UNIT))
    (RETURN-DISK-RQB RQB)))

(DEFUN DISK-INIT (&AUX RQB SIZE)
  (UNWIND-PROTECT
      (PROGN (SETQ RQB (GET-DISK-LABEL-RQB))
	     (READ-DISK-LABEL RQB 0)
	     ;; Update things which depend on the location and size of the paging area
	     (MULTIPLE-VALUE (PAGE-OFFSET SIZE)
	       (FIND-DISK-PARTITION "PAGE" RQB 0 T))
	     (SETQ VIRTUAL-MEMORY-SIZE (* (MIN (LDB #o1020 A-MEMORY-VIRTUAL-ADDRESS) SIZE)
					  PAGE-SIZE))
	     (SETQ DISK-PACK-NAME (GET-DISK-STRING RQB #o20 32.)))
    (RETURN-DISK-RQB RQB)))

(DEFUN PRINT-LOADED-BAND (&OPTIONAL (STREAM T))	;Can be NIL to return a string
  "Prints on STREAM a description of the loaded band.
This is obsolete -- You probably want PRINT-HERALD"
  (UNLESS (ZEROP %LOADED-BAND)
    (SETQ CURRENT-LOADED-BAND %LOADED-BAND))
  (UNLESS (BOUNDP 'CURRENT-LOADED-BAND)
    (SETQ CURRENT-LOADED-BAND 0))
  (PROG2	;If STREAM is NIL, want to return a string with no carriage returns in it
    (FRESH-LINE STREAM)
    (FORMAT STREAM "This is band ~C of ~A, with ~A"
	    (LDB #o2010 CURRENT-LOADED-BAND)	;4th char in string (only high 3 stored)
	    DISK-PACK-NAME
	    (IF (FBOUNDP 'SYSTEM-VERSION-INFO)	;For the cold load
		(SYSTEM-VERSION-INFO)
              "[fresh cold load]"))
    (FRESH-LINE STREAM)))

;;; This is called explicitly by LISP-REINITIALIZE.
(DEFUN PRINT-HERALD (&OPTIONAL (STREAM STANDARD-OUTPUT))
  "Print on STREAM a description of the versions of all software running."
  (UNLESS (ZEROP %LOADED-BAND)
    (SETQ CURRENT-LOADED-BAND %LOADED-BAND))
  (UNLESS (BOUNDP 'CURRENT-LOADED-BAND)
    (SETQ CURRENT-LOADED-BAND 0))
  (FORMAT STREAM "~&~A System, band ~C of ~A."
	  (IF (OR (NOT (VARIABLE-BOUNDP SITE-NAME)) (EQ SITE-NAME ':MIT))
	      "MIT" "LMI")			;>> commercial lossage. fmh.
	  (LDB #o2010 CURRENT-LOADED-BAND)
	  DISK-PACK-NAME)
  (AND (BOUNDP 'SYSTEM-ADDITIONAL-INFO)
       (PLUSP (ARRAY-ACTIVE-LENGTH SYSTEM-ADDITIONAL-INFO))
       (FORMAT STREAM " (~A)" SYSTEM-ADDITIONAL-INFO))
  (IF (NOT (FBOUNDP 'DESCRIBE-SYSTEM-VERSIONS))
      (FORMAT STREAM "~%Fresh Cold Load~%")
    (FORMAT STREAM "~&~DK physical memory, ~DK virtual memory."
	    (TRUNCATE (SYSTEM-COMMUNICATION-AREA %SYS-COM-MEMORY-SIZE) #o2000)
	    (TRUNCATE VIRTUAL-MEMORY-SIZE #o2000))
    (DESCRIBE-SYSTEM-VERSIONS STREAM)
    (FORMAT STREAM "~%~A ~A, with associated machine ~A.~%"
	    (OR (GET-SITE-OPTION :SITE-PRETTY-NAME) SITE-NAME)
	    LOCAL-PRETTY-HOST-NAME
	    (SEND ASSOCIATED-MACHINE :NAME-AS-FILE-COMPUTER))))

;;; Must be defined before initialization below
(DEFUN WIRE-PAGE (ADDRESS &OPTIONAL (WIRE-P T) SET-MODIFIED DONT-BOTHER-PAGING-IN)
  (IF WIRE-P
      (DO ()
	  ((%CHANGE-PAGE-STATUS ADDRESS %PHT-SWAP-STATUS-WIRED NIL)
	   (IF SET-MODIFIED			;Set modified bit without changing anything
	       (IF DONT-BOTHER-PAGING-IN	;and without touching uninitialized memory
		   (%P-STORE-TAG-AND-POINTER ADDRESS DTP-TRAP ADDRESS)
		 (%P-DPB (%P-LDB %%Q-DATA-TYPE ADDRESS) %%Q-DATA-TYPE ADDRESS))))
	(COND ((NOT DONT-BOTHER-PAGING-IN)
	       (%P-LDB 1 (%POINTER ADDRESS)))	;Haul it in
	      ((NULL (%PAGE-STATUS ADDRESS))
	       (WITHOUT-INTERRUPTS		;Try not to get aborted
		 (LET ((PFN (%FINDCORE)))
		   (OR (%PAGE-IN PFN (LSH ADDRESS -8))
		       ;; Page already got in somehow, free up the PFN
		       (%CREATE-PHYSICAL-PAGE (LSH PFN 8))))))))
      (UNWIRE-PAGE ADDRESS)))

(DEFUN UNWIRE-PAGE (ADDRESS)
  (%CHANGE-PAGE-STATUS ADDRESS %PHT-SWAP-STATUS-NORMAL NIL))

(DEFUN WIRE-WORDS (FROM SIZE &OPTIONAL (WIRE-P T) SET-MODIFIED DONT-BOTHER-PAGING-IN)
  (DO ((ADR (- FROM (LOGAND FROM (1- PAGE-SIZE))) (+ ADR PAGE-SIZE))
       (N   (- PAGE-SIZE (LOGAND FROM (1- PAGE-SIZE))) (+ N PAGE-SIZE)))
      (( N SIZE))
    (WIRE-PAGE ADR WIRE-P SET-MODIFIED DONT-BOTHER-PAGING-IN)))

(DEFUN UNWIRE-WORDS (FROM SIZE)
  (WIRE-WORDS FROM SIZE NIL))
      
(DEFUN WIRE-ARRAY  (ARRAY &OPTIONAL FROM TO SET-MODIFIED DONT-BOTHER-PAGING-IN &AUX SIZE)
  (WITHOUT-INTERRUPTS
    (MULTIPLE-VALUE (ARRAY FROM SIZE)
      (PAGE-ARRAY-CALCULATE-BOUNDS ARRAY FROM TO))
    (AND ARRAY
	 ;; Have starting word and number of words. 
	 (WIRE-WORDS FROM SIZE T SET-MODIFIED DONT-BOTHER-PAGING-IN))))

(DEFUN UNWIRE-ARRAY (ARRAY &OPTIONAL FROM TO &AUX SIZE)
  (WITHOUT-INTERRUPTS
    (MULTIPLE-VALUE (ARRAY FROM SIZE)
      (PAGE-ARRAY-CALCULATE-BOUNDS ARRAY FROM TO))
    (AND ARRAY
	 ;; Have starting word and number of words. 
	 (UNWIRE-WORDS FROM SIZE))))

(DEFUN WIRE-STRUCTURE (OBJ &OPTIONAL SET-MODIFIED DONT-BOTHER-PAGING-IN)
  (SETQ OBJ (FOLLOW-STRUCTURE-FORWARDING OBJ))
  (WITHOUT-INTERRUPTS
    (WIRE-WORDS (%FIND-STRUCTURE-LEADER OBJ)
		(%STRUCTURE-TOTAL-SIZE OBJ)
		T SET-MODIFIED DONT-BOTHER-PAGING-IN)))

(DEFUN UNWIRE-STRUCTURE (OBJ)
  (SETQ OBJ (FOLLOW-STRUCTURE-FORWARDING OBJ))
  (WITHOUT-INTERRUPTS
    (UNWIRE-WORDS (%FIND-STRUCTURE-LEADER OBJ)
		  (%STRUCTURE-TOTAL-SIZE OBJ))))

;;; Takes the number of an area and wires down all the allocated
;;; pages of it, or un-wires, depending on the second argument.
;;; The area had better have only one region.
;;; Also doesn't work on downwards-consed list regions (which no longer exist).
(DEFUN WIRE-AREA (AREA WIRE-P)
  (LET ((REGION (AREA-REGION-LIST AREA)))
    (OR (MINUSP (REGION-LIST-THREAD REGION)) ;last region in area
	(FERROR NIL "Area ~A has more than one region" (AREA-NAME AREA)))
    (DO ((LOC (REGION-ORIGIN REGION) (%MAKE-POINTER-OFFSET DTP-FIX LOC PAGE-SIZE))
	 (COUNT (CEILING (REGION-FREE-POINTER REGION) PAGE-SIZE) (1- COUNT)))
	((ZEROP COUNT))
      (WIRE-PAGE LOC WIRE-P))))

;This must be after main definitions above, but before initialization below!
(ADD-INITIALIZATION "DISK-INIT" '(DISK-INIT) '(SYSTEM))

;;; Put a microcode file onto my own disk.
;;; Note that the cretinous halfwords are out of order
(DEFUN LOAD-MCR-FILE (FILENAME PART &OPTIONAL (UNIT 0)
                                    &AUX PART-BASE PART-SIZE RQB)
  "Load microcode from file FILENAME into partition PART on unit UNIT.
UNIT can be a disk unit number, the name of a machine on the chaosnet,
or /"CC/" which refers to the machine being debugged by this one."
  (SETQ FILENAME (IF (NUMBERP FILENAME)
		     (SEND (SELECT-PROCESSOR
			     (:CADR
			       (FS:PARSE-PATHNAME "SYS: UBIN; UCADR"))
			     (:LAMBDA
			       (FS:PARSE-PATHNAME "SYS: UBIN; ULAMBDA")))
			   :NEW-TYPE-AND-VERSION "MCR" FILENAME)
		   (FS:MERGE-PATHNAME-DEFAULTS FILENAME)))
  (UNLESS (EQUAL (SEND FILENAME :TYPE-AND-VERSION) "MCR")
    (FERROR NIL "~A is not a MCR file." FILENAME))
  (SETQ UNIT (DECODE-UNIT-ARGUMENT UNIT
				   (FORMAT NIL "Loading ~A into ~A partition" FILENAME PART)
				   NIL
				   T))
  (UNWIND-PROTECT
      (PROGN
	(SETQ RQB (GET-DISK-RQB))
	(MULTIPLE-VALUE (PART-BASE PART-SIZE NIL PART)
	  (FIND-DISK-PARTITION-FOR-WRITE PART NIL UNIT NIL "MCR"))
	(WITH-OPEN-FILE (FILE FILENAME :DIRECTION :INPUT :CHARACTERS NIL :BYTE-SIZE 16.)
	  (BLOCK DONE
	    (DO ((BUF16 (ARRAY-LEADER RQB %DISK-RQ-LEADER-BUFFER))
		 (BLOCK PART-BASE (1+ BLOCK))
		 (N PART-SIZE (1- N)))
		((ZEROP N) (FERROR NIL "Failed to fit in partition"))
	      (DO ((LH) (RH)
		   (I 0 (+ I 2)))
		  ((= I #o1000)
		   (DISK-WRITE RQB UNIT BLOCK))
		(SETQ LH (SEND FILE :TYI)
		      RH (SEND FILE :TYI))
		(WHEN (OR (NULL LH) (NULL RH))
		  (UPDATE-PARTITION-COMMENT
		    PART
		    (LET ((PATHNAME (SEND FILE :TRUENAME)))
		      (FORMAT NIL "~A ~D" (SEND PATHNAME :NAME) (SEND PATHNAME :VERSION)))
		    UNIT)
		  (RETURN-FROM DONE NIL))
		(SETF (AREF BUF16 I) RH)
		(SETF (AREF BUF16 (1+ I)) LH))))))
    (DISPOSE-OF-UNIT UNIT)
    (RETURN-DISK-RQB RQB)))

;;; Put a microcode file onto my own disk, LAMBDA style.
;;; Note that the halfwords are IN order in a LMC file (as opposed to a MCR file).
(DEFUN LOAD-LMC-FILE (FILENAME PART &OPTIONAL (UNIT 0)
                                    &AUX PART-BASE PART-SIZE RQB RQB-FOR-LABEL)
  "Load microcode from file FILENAME into partition PART on unit UNIT.
UNIT can be a disk unit number, the name of a machine on the chaosnet,
or /"CC/" or /"LAM/" which refers to the machine being debugged by this one."
  (SETQ FILENAME (IF (NUMBERP FILENAME)
		     (SEND (FS:PARSE-PATHNAME "SYS: LAMBDA-UCODE; ULAMBDA")
			   :NEW-TYPE-AND-VERSION "LMC" FILENAME)
		     (FS:MERGE-PATHNAME-DEFAULTS FILENAME)))
  (UNLESS (EQUAL (SEND FILENAME :TYPE-AND-VERSION) "LMC")
    (FERROR NIL "~A is not a LMC file." FILENAME))
  (SETQ UNIT (DECODE-UNIT-ARGUMENT UNIT
		(FORMAT NIL "Loading ~A into ~A partition" FILENAME PART)
		NIL
		T))
  (UNWIND-PROTECT
      (PROGN
	(SETQ RQB (GET-DISK-RQB))
	(SETQ RQB-FOR-LABEL (GET-DISK-RQB 3))
	(MULTIPLE-VALUE (PART-BASE PART-SIZE NIL PART)
	  (FIND-DISK-PARTITION-FOR-WRITE PART RQB-FOR-LABEL UNIT NIL "LMC"))
	(WITH-OPEN-FILE (FILE FILENAME :DIRECTION :INPUT :CHARACTERS NIL :BYTE-SIZE 16.)
	  (BLOCK DONE
	    (DO ((BUF16 (ARRAY-LEADER RQB %DISK-RQ-LEADER-BUFFER))
		 (BLOCK PART-BASE (1+ BLOCK))
		 (N PART-SIZE (1- N)))
		((ZEROP N) (FERROR NIL "Failed to fit in partition"))
	      (DO ((LH) (RH)
		   (I 0 (+ I 2)))
		  ((= I #o1000)
		   (DISK-WRITE RQB UNIT BLOCK))
		(SETQ RH (SEND FILE :TYI)	;note halfwords in "right" order in LMC file
		      LH (SEND FILE :TYI))
		(WHEN (OR (NULL LH) (NULL RH))
		  (UPDATE-PARTITION-COMMENT
		    PART
		    (LET ((PATHNAME (SEND FILE :TRUENAME)))
		      (FORMAT NIL "~A ~D" (SEND PATHNAME :NAME) (SEND PATHNAME :VERSION)))
		    UNIT)
		  (RETURN-FROM DONE NIL))
	      (SETF (AREF BUF16 I) RH)
	      (SETF (AREF BUF16 (1+ I)) LH))))))
    (RETURN-DISK-RQB RQB)
    (RETURN-DISK-RQB RQB-FOR-LABEL)))

;;; Compare a microcode file with a partiion on me, LAMBDA style.
;;; Note that the halfwords are IN order in a LMC file (as opposed to a MCR file).
(DEFUN COMPARE-LMC-FILE (FILENAME PART &OPTIONAL (UNIT 0)
			 &AUX PART-BASE PART-SIZE RQB RQB-FOR-LABEL)
  "Compare microcode from file FILENAME with partition PART on unit UNIT.
UNIT can be a disk unit number, the name of a machine on the chaosnet,
or /"CC/" or /"LAM/" which refers to the machine being debugged by this one."
  (SETQ FILENAME (IF (NUMBERP FILENAME)
		     (SEND (FS:PARSE-PATHNAME "SYS: LAMBDA-UCODE; ULAMBDA")
			   :NEW-TYPE-AND-VERSION "LMC" FILENAME)
		   (FS:MERGE-PATHNAME-DEFAULTS FILENAME)))
  (UNLESS (EQUAL (SEND FILENAME :TYPE-AND-VERSION) "LMC")
    (FERROR NIL "~A is not a LMC file." FILENAME))
  (SETQ UNIT (DECODE-UNIT-ARGUMENT UNIT
				   (FORMAT NIL "Comparing ~A with ~A partition" FILENAME PART)
				   NIL
				   NIL))
  (UNWIND-PROTECT
      (PROGN
	(SETQ RQB (GET-DISK-RQB))
	(SETQ RQB-FOR-LABEL (GET-DISK-RQB 3))
	(MULTIPLE-VALUE (PART-BASE PART-SIZE NIL PART)
	  (FIND-DISK-PARTITION-FOR-READ PART RQB-FOR-LABEL UNIT NIL "LMC"))
	(WITH-OPEN-FILE (FILE FILENAME :DIRECTION :INPUT :CHARACTERS NIL :BYTE-SIZE 16.)
	  (BLOCK DONE
	    (DO ((BUF16 (ARRAY-LEADER RQB %DISK-RQ-LEADER-BUFFER))
		 (BLOCK PART-BASE (1+ BLOCK))
		 (N PART-SIZE (1- N)))
		((ZEROP N) (FORMAT T "~&File is longer than partition"))
	      (DISK-READ RQB UNIT BLOCK)
	      (DO ((LH) (RH)
		   (I 0 (+ I 2)))
		  ((= I #o1000))
		(SETQ RH (SEND FILE :TYI)	;note halfwords in "right" order in LMC file
		      LH (SEND FILE :TYI))
		(COND ((OR (NULL LH) (NULL RH))
		       (RETURN-FROM DONE NIL)))
		(COND ((OR (NOT (= RH (AREF BUF16 I)))
			   (NOT (= LH (AREF BUF16 (1+ I)))))
		       (FORMAT T "~&Compare error:  adr ~O; file ~O-~O; partition ~O-~O"
			       I LH RH (AREF BUF16 (1+ I)) (AREF BUF16 I)))))))))
    (RETURN-DISK-RQB RQB)
    (RETURN-DISK-RQB RQB-FOR-LABEL)))

(DEFUN PARTITION-COMMENT (PART UNIT &AUX RQB DESC-LOC)
  "Return the comment in the disk label for partition PART, unit UNIT.
UNIT can be a disk unit number, the name of a machine on the chaos net,
or /"CC/" which refers to the machine being debugged by this one."
  (IF (AND (CLOSUREP UNIT)
	   (FUNCALL UNIT :HANDLES-LABEL))
      (FUNCALL UNIT :PARTITION-COMMENT PART)
    (UNWIND-PROTECT
	(PROGN (SETQ RQB (GET-DISK-LABEL-RQB))
	       (SETQ DESC-LOC (NTH-VALUE 2 (FIND-DISK-PARTITION PART RQB UNIT)))
	       (COND ((NULL DESC-LOC) NIL)
		     (( (GET-DISK-FIXNUM RQB #o201) 7)
		      (GET-DISK-STRING RQB
				       (+ DESC-LOC 3)
				       (* 4 (- (GET-DISK-FIXNUM RQB #o201) 3))))
		     (T "")))
      (RETURN-DISK-RQB RQB))))

(DEFUN MAXIMUM-PARTITION-COMMENT-LENGTH (PART UNIT &AUX RQB DESC-LOC)
  "Returns the maximum length in characters of the descriptive partition comments on UNIT"
  (UNWIND-PROTECT
      (PROGN (SETQ RQB (GET-DISK-LABEL-RQB))
	     (SETQ DESC-LOC (NTH-VALUE 2 (FIND-DISK-PARTITION PART RQB UNIT)))
	     (COND ((NULL DESC-LOC) NIL)
		   (( (GET-DISK-FIXNUM RQB #o201) 7)
		    (* 4 (- (GET-DISK-FIXNUM RQB #o201) 3)))
		   (T 0)))
    (RETURN-DISK-RQB RQB)))

(DEFUN GET-UCODE-VERSION-FROM-COMMENT (PART UNIT &OPTIONAL RQB ALREADY-READ-P
				       &AUX RETURN-RQB DESC-LOC)
  "Return the microcode version stored in partition PART on unit UNIT.
This works by parsing the comment in the disk label.
UNIT can be a disk unit number, the name of a machine on the chaos net,
or /"CC/" which refers to the machine being debugged by this one."
  (UNWIND-PROTECT
    (PROGN
      (IF (NULL RQB)
	  (SETQ RETURN-RQB T
		RQB (GET-DISK-LABEL-RQB)))
      (SETQ DESC-LOC (NTH-VALUE 2 (FIND-DISK-PARTITION PART RQB UNIT ALREADY-READ-P)))
      (LET ((COMMENT (AND DESC-LOC
			  ( (GET-DISK-FIXNUM RQB #o201) 7)
			  (GET-DISK-STRING RQB
					   (+ DESC-LOC 3)
					   (* 4 (- (GET-DISK-FIXNUM RQB #o201) 3))))))
	(AND COMMENT
	     (SELECT-PROCESSOR
	       (:CADR (STRING-EQUAL COMMENT "UCADR " :END1 6))
	       (:LAMBDA (STRING-EQUAL COMMENT "ULAMBDA " :END1 8.)))
	     (LET ((*READ-BASE* 10.))
	       (CLI:READ-FROM-STRING COMMENT T NIL :START (SELECT-PROCESSOR
							    (:CADR 6)
							    (:LAMBDA 8.)))))))
    (AND RETURN-RQB (RETURN-DISK-RQB RQB))))
	    
;;; Change the comment on a partition
(DEFUN UPDATE-PARTITION-COMMENT (PART STRING UNIT &AUX RQB DESC-LOC) 
  "Set the comment in the disk label for partition PART, unit UNIT to STRING.
UNIT can be a disk unit number, the name of a machine on the chaos net,
or /"CC/" which refers to the machine being debugged by this one."
  (IF (AND (CLOSUREP UNIT)
	   (FUNCALL UNIT :HANDLES-LABEL))
      (FUNCALL UNIT :UPDATE-PARTITION-COMMENT PART STRING)
    (UNWIND-PROTECT
	(PROGN (SETQ RQB (GET-DISK-LABEL-RQB))
	       (SETQ DESC-LOC (NTH-VALUE 2
				(FIND-DISK-PARTITION-FOR-READ PART RQB UNIT NIL NIL)))
	       (AND ( (GET-DISK-FIXNUM RQB #o201) 7)
		    (PUT-DISK-STRING RQB
				     STRING
				     (+ DESC-LOC 3)
				     (* 4 (- (GET-DISK-FIXNUM RQB #o201) 3))))
	       (WRITE-DISK-LABEL RQB UNIT))
      (RETURN-DISK-RQB RQB))))

(DEFUN COPY-DISK-PARTITION-BACKGROUND (FROM-UNIT FROM-PART TO-UNIT TO-PART STREAM
				       STARTING-HUNDRED)
  (PROCESS-RUN-FUNCTION "copy partition"
	#'(LAMBDA (FU FP TU TP *TERMINAL-IO* SH)
	    (COPY-DISK-PARTITION FU FP TU TP 10. 300. SH))
	FROM-UNIT FROM-PART TO-UNIT TO-PART STREAM STARTING-HUNDRED))

;;; Copying a partition from one unit to another
(DEFUN COPY-DISK-PARTITION (FROM-UNIT FROM-PART TO-UNIT TO-PART
			    &OPTIONAL (N-PAGES-AT-A-TIME 85.) (DELAY NIL)
				      (STARTING-HUNDRED 0) (WHOLE-THING-P NIL)
			    &AUX FROM-PART-BASE FROM-PART-SIZE TO-PART-BASE TO-PART-SIZE RQB
			         PART-COMMENT)
  "Copy partition FROM-PART on FROM-UNIT to partition TO-PART on TO-UNIT.
While names of other machines can be specified as units, this
is not very fast for copying between machines.
Use SI:RECEIVE-BAND or SI:TRANSMIT-BAND for that."
  (SETQ FROM-UNIT (DECODE-UNIT-ARGUMENT FROM-UNIT
					(FORMAT NIL "reading ~A partition" FROM-PART))
	TO-UNIT (DECODE-UNIT-ARGUMENT TO-UNIT
				      (FORMAT NIL "writing ~A partition" TO-PART)
				      NIL
				      T))
  (UNWIND-PROTECT
      (PROGN
	(SETQ RQB (GET-DISK-RQB N-PAGES-AT-A-TIME))
	(MULTIPLE-VALUE (FROM-PART-BASE FROM-PART-SIZE NIL FROM-PART)
	  (FIND-DISK-PARTITION-FOR-READ FROM-PART NIL FROM-UNIT))
	(MULTIPLE-VALUE (TO-PART-BASE TO-PART-SIZE NIL TO-PART)
	  (FIND-DISK-PARTITION-FOR-WRITE TO-PART NIL TO-UNIT))
	(SETQ PART-COMMENT (PARTITION-COMMENT FROM-PART FROM-UNIT))
	(FORMAT T "~&Copying ~S" PART-COMMENT)
	(AND (OR (NUMBERP FROM-PART) (STRING-EQUAL FROM-PART "LOD" :END1 3))
	     (NOT WHOLE-THING-P)
	     (NOT (AND (CLOSUREP FROM-UNIT)
		       (EQ (CLOSURE-FUNCTION FROM-UNIT) 'FS:BAND-MAGTAPE-HANDLER)))
	     (LET ((RQB NIL) (BUF NIL))
	       (UNWIND-PROTECT
		   (PROGN (SETQ RQB (GET-DISK-RQB 1))
			  (SETQ BUF (RQB-BUFFER RQB))
			  (DISK-READ RQB FROM-UNIT (1+ FROM-PART-BASE))
			  (LET ((SIZE (SYS-COM-PAGE-NUMBER BUF %SYS-COM-VALID-SIZE)))
			    (COND ((AND (> SIZE #o10) ( SIZE FROM-PART-SIZE))
				   (SETQ FROM-PART-SIZE SIZE)
				   (FORMAT T "... using measured size of ~D blocks." SIZE)))))
		 (RETURN-DISK-RQB RQB))))
	(UNLESS ( TO-PART-SIZE FROM-PART-SIZE)
	  (FERROR NIL "Target partition is only ~D blocks long; ~D needed."
		  TO-PART-SIZE FROM-PART-SIZE))
	(FORMAT T "~%")
	(UPDATE-PARTITION-COMMENT TO-PART "Incomplete Copy" TO-UNIT)
	(WHEN (AND (CLOSUREP TO-UNIT)		;magtape needs to know this stuff before
		   (FUNCALL TO-UNIT :HANDLES-LABEL))	;writing file.
	  (FUNCALL TO-UNIT :PUT PART-COMMENT :COMMENT)
	  (FUNCALL TO-UNIT :PUT FROM-PART-SIZE :SIZE))
	;; Old hack which used to move WIRE-DISK-RQB outside loop flushed because
	;; DISK-READ sets modified bits during WIRE-DISK-RQB, which we may need to do.
	(DO ((FROM-ADR (+ FROM-PART-BASE (* 100. STARTING-HUNDRED)) (+ FROM-ADR AMT))
	     (TO-ADR (+ TO-PART-BASE (* 100. STARTING-HUNDRED)) (+ TO-ADR AMT))
	     (FROM-HIGH (+ FROM-PART-BASE FROM-PART-SIZE))
	     (TO-HIGH (+ TO-PART-BASE TO-PART-SIZE))
	     (N-BLOCKS (* 100. STARTING-HUNDRED) (+ N-BLOCKS AMT))
	     (N-HUNDRED STARTING-HUNDRED)
	     (AMT))
	    ((OR ( FROM-ADR FROM-HIGH) (>= TO-ADR TO-HIGH)))
	  (SETQ AMT (MIN (- FROM-HIGH FROM-ADR) (- TO-HIGH TO-ADR) N-PAGES-AT-A-TIME))
	  (COND ((NOT (= AMT N-PAGES-AT-A-TIME))
		 (RETURN-DISK-RQB RQB)
		 (SETQ RQB (GET-DISK-RQB AMT))))
	  (DISK-READ RQB FROM-UNIT FROM-ADR)
	  (DISK-WRITE RQB TO-UNIT TO-ADR)
	  (WHEN ( (FLOOR (+ N-BLOCKS AMT) 100.) N-HUNDRED)
	    (INCF N-HUNDRED)
	    (FORMAT T "~D " N-HUNDRED))
	  (IF DELAY
	      (PROCESS-SLEEP DELAY)
	      (PROCESS-ALLOW-SCHEDULE)))	;kludge
	(UPDATE-PARTITION-COMMENT TO-PART PART-COMMENT TO-UNIT))
    ;; Unwind-protect forms
    (RETURN-DISK-RQB RQB))
  (DISPOSE-OF-UNIT FROM-UNIT)
  (DISPOSE-OF-UNIT TO-UNIT))

;;; Prints differences
(DEFUN COMPARE-DISK-PARTITION (FROM-UNIT FROM-PART TO-UNIT TO-PART
			    &OPTIONAL (N-PAGES-AT-A-TIME 85.) (DELAY NIL)
				      (STARTING-HUNDRED 0) (WHOLE-THING-P NIL)
			    &AUX FROM-PART-BASE FROM-PART-SIZE TO-PART-BASE TO-PART-SIZE
			         RQB RQB2)
  "Compare partition FROM-PART on FROM-UNIT to partition TO-PART on TO-UNIT.
While names of other machines can be specified as units, this
is not very fast for copying between machines.
Use SI:RECEIVE-BAND or SI:TRANSMIT-BAND for that."
  (SETQ FROM-UNIT (DECODE-UNIT-ARGUMENT FROM-UNIT
					(FORMAT NIL "reading ~A partition" FROM-PART))
	TO-UNIT (DECODE-UNIT-ARGUMENT TO-UNIT (FORMAT NIL "reading ~A partition" TO-PART)))
  (UNWIND-PROTECT
      (PROGN
	(SETQ RQB (GET-DISK-RQB N-PAGES-AT-A-TIME))
	(SETQ RQB2 (GET-DISK-RQB N-PAGES-AT-A-TIME))
	(MULTIPLE-VALUE (FROM-PART-BASE FROM-PART-SIZE)
	  (FIND-DISK-PARTITION-FOR-READ FROM-PART NIL FROM-UNIT))
	(MULTIPLE-VALUE (TO-PART-BASE TO-PART-SIZE)
	  (FIND-DISK-PARTITION-FOR-READ TO-PART NIL TO-UNIT))
	(FORMAT T "~&Comparing ~S and ~S"
		(PARTITION-COMMENT FROM-PART FROM-UNIT)
		(PARTITION-COMMENT TO-PART TO-UNIT))
	(WHEN (STRING-EQUAL FROM-PART "LOD" :END1 3)
	  (NOT WHOLE-THING-P)
	  (LET (RQB BUF)
	    (UNWIND-PROTECT
		(PROGN
		  (SETQ RQB (GET-DISK-RQB 1))
		  (SETQ BUF (RQB-BUFFER RQB))
		  (DISK-READ RQB FROM-UNIT (1+ FROM-PART-BASE))
		  (LET ((SIZE (SYS-COM-PAGE-NUMBER BUF %SYS-COM-VALID-SIZE)))
		    (COND ((AND (> SIZE #o10) ( SIZE FROM-PART-SIZE))
			   (SETQ FROM-PART-SIZE SIZE)
			   (FORMAT T "... using measured size of ~D. blocks." SIZE)))))
	      (RETURN-DISK-RQB RQB))))
	(DO ((FROM-ADR (+ FROM-PART-BASE (* 100. STARTING-HUNDRED)) (+ FROM-ADR AMT))
	     (TO-ADR (+ TO-PART-BASE (* 100. STARTING-HUNDRED)) (+ TO-ADR AMT))
	     (FROM-HIGH (+ FROM-PART-BASE FROM-PART-SIZE))
	     (TO-HIGH (+ TO-PART-BASE TO-PART-SIZE))
	     (N-BLOCKS (* 100. STARTING-HUNDRED) (+ N-BLOCKS AMT))
	     (N-HUNDRED STARTING-HUNDRED)
	     (AMT)
	     (BUF (RQB-BUFFER RQB))
	     (BUF2 (RQB-BUFFER RQB2)))
	    ((OR ( FROM-ADR FROM-HIGH)
		 ( TO-ADR TO-HIGH)))
	  (SETQ AMT (MIN (- FROM-HIGH FROM-ADR) (- TO-HIGH TO-ADR) N-PAGES-AT-A-TIME))
	  (COND ((NOT (= AMT N-PAGES-AT-A-TIME))
		 (RETURN-DISK-RQB RQB)
		 (RETURN-DISK-RQB RQB2)
		 (SETQ RQB (GET-DISK-RQB AMT))
		 (SETQ RQB2 (GET-DISK-RQB AMT))
		 (SETQ BUF (RQB-BUFFER RQB))
		 (SETQ BUF2 (RQB-BUFFER RQB2))))
	  (DISK-READ RQB FROM-UNIT FROM-ADR)
	  (DISK-READ RQB2 TO-UNIT TO-ADR)
	  (UNLESS (LET ((ALPHABETIC-CASE-AFFECTS-STRING-COMPARISON T))
		    (%STRING-EQUAL (RQB-8-BIT-BUFFER RQB) 0
				   (RQB-8-BIT-BUFFER RQB2) 0
				   (* #o2000 AMT)))
	    (DO ((C 0 (1+ C))
		 (ERRS 0)
		 (LIM (* #o1000 AMT)))
		((OR (= C LIM) (= ERRS 3)))
	      (COND ((NOT (= (AREF BUF C) (AREF BUF2 C)))
		     (FORMAT T "~%ERR Block ~O Halfword ~O, S1: ~O S2: ~O "
			     (+ (- FROM-ADR (+ FROM-PART-BASE (* STARTING-HUNDRED 100.)))
				(FLOOR C #o1000))
			     (\ C #o1000)
			     (AREF BUF C)
			     (AREF BUF2 C))
		     (INCF ERRS)))))
	  (UNLESS (= (FLOOR N-BLOCKS 100.) N-HUNDRED)
	    (SETQ N-HUNDRED (FLOOR N-BLOCKS 100.))
	    (FORMAT T "~D " N-HUNDRED))
	  (IF DELAY (PROCESS-SLEEP DELAY)
	    (PROCESS-ALLOW-SCHEDULE)))		;kludge
	)
    ;; Unwind-protect forms
    (RETURN-DISK-RQB RQB)
    (RETURN-DISK-RQB RQB2)
    (DISPOSE-OF-UNIT FROM-UNIT)
    (DISPOSE-OF-UNIT TO-UNIT)))

;;;; User-controlled paging code

;;; We have a special RQB which is not like a normal disk RQB in that
;;; it doesn't contain any buffer.  It is exactly one page long since
;;; everything in DISK-BUFFER-AREA has to be a multiple of a page.
;;; This defines the number of CCWs.

(DEFVAR PAGE-RQB-SIZE (- PAGE-SIZE 1 (FLOOR %DISK-RQ-CCW-LIST 2))) ;NUMBER OF CCWS
(DEFVAR PAGE-RQB
	(MAKE-ARRAY (* 2 (1- PAGE-SIZE)) :TYPE 'ART-16B :AREA DISK-BUFFER-AREA))

(DEFUN WIRE-PAGE-RQB () 
  (WIRE-PAGE (%POINTER PAGE-RQB))
  (LET ((PADR (+ (%PHYSICAL-ADDRESS PAGE-RQB)
		 1
		 (FLOOR %DISK-RQ-CCW-LIST 2))))
    (SETF (AREF PAGE-RQB %DISK-RQ-CCW-LIST-POINTER-LOW) PADR)
    (SETF (AREF PAGE-RQB %DISK-RQ-CCW-LIST-POINTER-HIGH) (LSH PADR -16.))))

(DEFUN UNWIRE-PAGE-RQB ()
  (UNWIRE-PAGE (%POINTER PAGE-RQB)))

(DEFUN PAGE-IN-AREA (AREA)
  "Swap in the contents of AREA in one disk operation."
  (DO REGION (AREA-REGION-LIST AREA) (REGION-LIST-THREAD REGION) (MINUSP REGION)
    (PAGE-IN-REGION REGION)))

(DEFUN PAGE-OUT-AREA (AREA)
  "Put the contents of AREA high on the list for being swapped out."
  (DO REGION (AREA-REGION-LIST AREA) (REGION-LIST-THREAD REGION) (MINUSP REGION)
    (PAGE-OUT-REGION REGION)))

(DEFUN PAGE-IN-REGION (REGION)
  "Swap in the contents of region REGION in one disk operation."
  (PAGE-IN-WORDS (REGION-ORIGIN REGION) (REGION-FREE-POINTER REGION)))

(DEFUN PAGE-OUT-REGION (REGION)
  "Put the contents of region REGION high on the list for being swapped out."
  (PAGE-OUT-WORDS (REGION-ORIGIN REGION) (REGION-FREE-POINTER REGION)))

(DEFUN PAGE-IN-STRUCTURE (OBJ)
  "Swap in the structure STRUCTURE in one disk operation."
  (SETQ OBJ (FOLLOW-STRUCTURE-FORWARDING OBJ))
  (PAGE-IN-WORDS (%FIND-STRUCTURE-LEADER OBJ)
		 (%STRUCTURE-TOTAL-SIZE OBJ)))

(DEFUN PAGE-OUT-STRUCTURE (OBJ)
  "Put the data of structure STRUCTURE high on the list for being swapped out."
  (SETQ OBJ (FOLLOW-STRUCTURE-FORWARDING OBJ))
  (PAGE-OUT-WORDS (%FIND-STRUCTURE-LEADER OBJ)
		  (%STRUCTURE-TOTAL-SIZE OBJ)))

(DEFUN PAGE-ARRAY-CALCULATE-BOUNDS (ARRAY FROM TO)
  "FROM and TO are lists of subscripts.  If too short, zeros are appended.
Returns array, starting address of data, number of Q's of data.
First value is NIL if displaced to an absolute address (probably TV buffer)."
  (DECLARE (VALUES ARRAY DATA-START-ADDRESS ESS DATA-LENGTH))
  (SETQ ARRAY (FOLLOW-STRUCTURE-FORWARDING ARRAY))
  (LET (NDIMS TYPE START END SIZE ELTS-PER-Q)
    (BLOCK DONE
      (SETQ NDIMS (ARRAY-RANK ARRAY)
	    TYPE (ARRAY-TYPE ARRAY))
      (UNLESS ( (LENGTH FROM) NDIMS)
	(FERROR NIL "Too many dimensions in starting index ~S" FROM))
      (UNLESS ( (LENGTH TO) NDIMS)
	(FERROR NIL "Too many dimensions in ending index ~S" TO))
      (SETQ START (OR (CAR FROM) 0)
	    END (1- (OR (CAR TO) (ARRAY-DIMENSION ARRAY 0))))
      (DO ((I 1 (1+ I))
	   DIM)
	  ((= I NDIMS))
	(SETQ START (+ (* START (SETQ DIM (ARRAY-DIMENSION ARRAY I)))
		       (OR (NTH I FROM) 0))
	      END (+ (* END DIM)
		     (1- (OR (NTH I TO) DIM)))))
      (INCF END)			;Convert from inclusive upper bound to exclusive
      (SETQ SIZE (- END START))
      (DO ((P))
	  ((ZEROP (%P-LDB-OFFSET %%ARRAY-DISPLACED-BIT ARRAY 0)))
	(SETQ NDIMS (%P-LDB-OFFSET %%ARRAY-NUMBER-DIMENSIONS ARRAY 0))
	(SETQ P (%MAKE-POINTER-OFFSET DTP-LOCATIVE
				      ARRAY
				      (+ NDIMS (%P-LDB-OFFSET %%ARRAY-LONG-LENGTH-FLAG
							      ARRAY 0))))
	(IF (ARRAY-INDEXED-P ARRAY)		;Index offset
	    (INCF START (%P-CONTENTS-OFFSET P 2)))
	(SETQ ARRAY (%P-CONTENTS-OFFSET P 0))
	(UNLESS (ARRAYP ARRAY)
	  (RETURN-FROM DONE NIL)))
      (SETQ ELTS-PER-Q (CDR (ASSOC TYPE ARRAY-ELEMENTS-PER-Q)))
      (SETQ START (+ (IF (PLUSP ELTS-PER-Q)
			 (FLOOR START ELTS-PER-Q)
		         (* START (MINUS ELTS-PER-Q)))
		     (%POINTER-PLUS ARRAY
				    (+ NDIMS
				       (%P-LDB-OFFSET %%ARRAY-LONG-LENGTH-FLAG ARRAY 0))))
	    SIZE (IF (PLUSP ELTS-PER-Q)
		     (CEILING SIZE ELTS-PER-Q)
		     (* SIZE (MINUS ELTS-PER-Q))))
      (VALUES ARRAY START SIZE))))

(DEFUN PAGE-IN-ARRAY  (ARRAY &OPTIONAL FROM TO &AUX SIZE)
  "Swap in all or part of ARRAY in one disk operation.
FROM and TO are lists of subscripts, or NIL."
  (WITHOUT-INTERRUPTS
    (MULTIPLE-VALUE (ARRAY FROM SIZE)
      (PAGE-ARRAY-CALCULATE-BOUNDS ARRAY FROM TO))
    (AND ARRAY
	 ;; Have starting word and number of words.  Page dem words in.
	 (PAGE-IN-WORDS FROM SIZE))))

(DEFUN PAGE-OUT-ARRAY (ARRAY &OPTIONAL FROM TO &AUX SIZE)
  "Put all or part of ARRAY high on the list for being swapped out.
FROM and TO are lists of subscripts, or NIL."
  (WITHOUT-INTERRUPTS
    (MULTIPLE-VALUE (ARRAY FROM SIZE)
      (PAGE-ARRAY-CALCULATE-BOUNDS ARRAY FROM TO))
    (AND ARRAY
	 ;; Have starting word and number of words.  Page dem words out.
	 (PAGE-OUT-WORDS FROM SIZE))))

;;; Just mark pages as good to swap out; don't actually write them.
(DEFUN PAGE-OUT-WORDS (ADDRESS NWDS &OPTIONAL ONLY-IF-UNMODIFIED &AUX STS)
  ONLY-IF-UNMODIFIED
  (WITHOUT-INTERRUPTS
    (SETQ ADDRESS (%POINTER ADDRESS))
    ;; This DO is over the whole frob
    (DO ((ADDR (LOGAND (- PAGE-SIZE) ADDRESS) (%MAKE-POINTER-OFFSET DTP-FIX ADDR PAGE-SIZE))
	 (N (+ NWDS (LOGAND (1- PAGE-SIZE) ADDRESS)) (- N PAGE-SIZE)))
	((NOT (PLUSP N)))
      (OR (NULL (SETQ STS (%PAGE-STATUS ADDR)))	;Swapped out
	  ( (LDB %%PHT1-SWAP-STATUS-CODE STS)
	     %PHT-SWAP-STATUS-WIRED)	;Wired
	  (%CHANGE-PAGE-STATUS ADDRESS %PHT-SWAP-STATUS-FLUSHABLE
			       (LDB %%REGION-MAP-BITS
				    (REGION-BITS (%REGION-NUMBER ADDRESS))))))))

(DEFUN PAGE-IN-WORDS (ADDRESS NWDS &AUX (CCWX 0) CCWP BASE-ADDR)
  (WITHOUT-INTERRUPTS
    (SETQ ADDRESS (%POINTER ADDRESS))
    (UNWIND-PROTECT
      (PROGN (WIRE-PAGE-RQB)
	     ;; This DO is over the whole frob
	     (DO ((ADDR (LOGAND (- PAGE-SIZE) ADDRESS)
			(%MAKE-POINTER-OFFSET DTP-FIX ADDR PAGE-SIZE))
		  (N (+ NWDS (LOGAND (1- PAGE-SIZE) ADDRESS)) (- N PAGE-SIZE)))
		 ((NOT (PLUSP N)))
	       (SETQ CCWX 0
		     CCWP %DISK-RQ-CCW-LIST
		     BASE-ADDR ADDR)
	       ;; This DO is over pages to go in a single I/O operation.
	       ;; We collect some page frames to put them in, remembering the
	       ;; PFNs as CCWs.
	       (DO-FOREVER
		 (OR (EQ (%PAGE-STATUS ADDR) NIL) (RETURN NIL))
		 (LET ((PFN (%FINDCORE)))
		   (SETF (AREF PAGE-RQB CCWP) (1+ (LSH PFN 8)))
		   (SETF (AREF PAGE-RQB (1+ CCWP)) (LSH PFN -8)))
		 (INCF CCWX 1)
		 (INCF CCWP 2)
		 (UNLESS (< CCWX PAGE-RQB-SIZE)
		   (RETURN NIL))
		 (SETQ ADDR (%POINTER-PLUS ADDR PAGE-SIZE))
		 (DECF N PAGE-SIZE)
		 (UNLESS (PLUSP N)
		   (RETURN NIL)))
	       (WHEN (PLUSP CCWX)	;We have something to do, run the I/O op
		 ;; Turn off chain bit
		 (SETF (AREF PAGE-RQB (- CCWP 2)) (LOGAND (AREF PAGE-RQB (- CCWP 2)) -2))
		 (DISK-READ-WIRED PAGE-RQB 0 (+ (LSH BASE-ADDR -8) PAGE-OFFSET))
		 ;; Make these pages in
		 (DO ((I 0 (1+ I))
		      (CCWP %DISK-RQ-CCW-LIST (+ 2 CCWP))
		      (VPN (LSH BASE-ADDR -8) (1+ VPN))
		      (PFN))
		     ((= I CCWX))
		   (SETQ PFN (DPB (AREF PAGE-RQB (1+ CCWP))
				  #o1010
				  (LDB #o1010 (AREF PAGE-RQB CCWP))))
		   (UNLESS (%PAGE-IN PFN VPN)
		     ;; Page already got in somehow, free up the PFN
		     (%CREATE-PHYSICAL-PAGE (LSH PFN 8))))
		 (SETQ CCWX 0))))
      ;; UNWIND-PROTECT forms
      (UNWIRE-PAGE-RQB)
;I guess it's better to lose some physical memory than to get two pages
;swapped into the same address, in the event that we bomb out.
;     (DO ((CCWP %DISK-RQ-CCW-LIST (+ CCWP 2))
;	   (N CCWX (1- N)))
;	  ((ZEROP N))
;	(%CREATE-PHYSICAL-PAGE (DPB (AREF PAGE-RQB (1+ CCWP))
;				    #o2006
;				    (AREF PAGE-RQB CCWP))))
      )))

;;;used by the lambda to find the machine name (since there is nothing like the
;;; chaos address set on the IO board)  Must be in this file since is needed when
;;; real chaos routines are initialized after MINI has done its thing.
(defun get-pack-name (&optional (unit 0) &aux rqb pack-name)
  (setq unit (decode-unit-argument unit "reading label"))
  (unwind-protect
      (progn (setq rqb (get-disk-label-rqb))
	     (read-disk-label rqb unit)
	     (setq pack-name (get-disk-string rqb #o20 32.)))
    (return-disk-rqb rqb))
  (dispose-of-unit unit)
  pack-name)

(defun set-pack-name (pack-name &optional (unit 0) &aux rqb)
  (setq unit (decode-unit-argument unit "writing label"))
  (unwind-protect
      (progn (setq rqb (get-disk-label-rqb))
	     (read-disk-label rqb unit)
	     (put-disk-string rqb pack-name #o20 32.)
	     (write-disk-label rqb unit))
    (return-disk-rqb rqb))
  (dispose-of-unit unit)
  pack-name)

;This is a test function.
(DEFUN READ-ALL-BLOCKS (&OPTIONAL (UNIT 0) &AUX RQB BUF BLOCKS-PER-TRACK N-CYLS N-HEADS)
  (SETQ UNIT (DECODE-UNIT-ARGUMENT UNIT "reading all"))
  (UNWIND-PROTECT
      (PROGN (UNWIND-PROTECT
		 (PROGN (SETQ RQB (GET-DISK-RQB 1))
			(DISK-READ RQB UNIT 0)	;Get label
			(SETQ BUF (RQB-BUFFER RQB))
			(SETQ N-CYLS (AREF BUF 4)
			      N-HEADS (AREF BUF 6)
			      BLOCKS-PER-TRACK (AREF BUF 8)))
	       (RETURN-DISK-RQB RQB))
	     (SETQ RQB NIL)
	     (UNWIND-PROTECT
		 (PROGN (SETQ RQB (GET-DISK-RQB BLOCKS-PER-TRACK))
			(DOTIMES (CYL N-CYLS)
			  (DOTIMES (HEAD N-HEADS)
			    (DISK-READ RQB UNIT (* (+ (* CYL N-HEADS) HEAD)
						   BLOCKS-PER-TRACK)))
			  (FORMAT T "~D " CYL)))
	       (RETURN-DISK-RQB RQB)))
    (DISPOSE-OF-UNIT UNIT)))

(DEFUN INSPECT-BLOCK (BLOCK-NO &OPTIONAL (UNIT 0) &AUX RQB BUF)
  (SETQ UNIT (DECODE-UNIT-ARGUMENT UNIT "reading block"))
  (UNWIND-PROTECT
      (UNWIND-PROTECT
	  (PROGN (SETQ RQB (GET-DISK-RQB 1))
		 (DISK-READ RQB UNIT BLOCK-NO)
		 (SETQ BUF (RQB-8-BIT-BUFFER RQB))
		 (LET ((FROBS-PER-LINE #o20))
		   (DOTIMES (LINE (TRUNCATE #o2000 FROBS-PER-LINE))
		     (TERPRI)
		     (DOTIMES (CHAR FROBS-PER-LINE)
		       (PRIN1-THEN-SPACE (AREF BUF (+ (* LINE FROBS-PER-LINE)
						      CHAR))))
		     (MULTIPLE-VALUE-BIND (X Y)
			 (SEND *TERMINAL-IO* :READ-CURSORPOS)
		       (SEND *TERMINAL-IO* :SET-CURSORPOS (MAX X 500.) Y))
		     (DOTIMES (CHAR FROBS-PER-LINE)
		       (SEND *TERMINAL-IO*
			     :TYO (AREF BUF (+ (* LINE FROBS-PER-LINE) CHAR)))))))
	(RETURN-DISK-RQB RQB))
    (DISPOSE-OF-UNIT UNIT)))
  
