;;; -*- Mode: Lisp; Package: User; Base: 8 -*-

(DEFSYSTEM FILE-SYSTEM-UTILITIES
  (:COMPONENT-SYSTEMS LOCAL-FILE
		      MAGTAPE
		      FILE-SERVER
		      ))

(DEFSYSTEM LOCAL-FILE
  (:NAME "Local-File")
  (:SHORT-NAME "FS")
  (:PATHNAME-DEFAULT "SYS: FILE;")
  (:PATCHABLE NIL "FS")
  (:NOT-IN-DISK-LABEL)
  (:PACKAGE FILE-SYSTEM)
  (:MODULE DEFS "FSDEFS")
  (:MODULE MAIN ("FSSTR" "FSGUTS" "FSACC"))
  (:COMPILE-LOAD DEFS)
  (:COMPILE-LOAD MAIN
   ((:FASLOAD DEFS))))

;;; the MagTape system is not carried.  Its files live in SYS: TAPE;,
;;; which wants a tape drive that neither muir nor muir-fpga has, so the
;;; definition below is commented out rather than left to fail on missing
;;; files.  SYS; SYSDCL has the matching change.
;(DEFSYSTEM MAGTAPE
;  (:NAME "MagTape")
;  (:SHORT-NAME "MT")
;  (:PATHNAME-DEFAULT "SYS: TAPE;")
;  (:PATCHABLE NIL "MagTape")
;  (:NOT-IN-DISK-LABEL)
;  (:PACKAGE FILE-SYSTEM)
;  (:MODULE DEFS ("MTDEFS"))
;  (:MODULE STREAM ("MTSTR"))
;  (:MODULE MAIN ("TAPE;FDUMP-DEF" "COPY" "MTAUX" "ODUMP")) ; ODUMP gone soon
;  (:COMPILE-LOAD DEFS)
;  (:COMPILE-LOAD STREAM (:FASLOAD DEFS))
;  (:COMPILE-LOAD MAIN (:FASLOAD DEFS STREAM)))

(DEFSYSTEM FILE-SERVER
  (:NAME "FILE-Server")
  (:NICKNAMES "Server")
  (:PATHNAME-DEFAULT "SYS: FILE;")
  (:PATCHABLE NIL "Server")
  (:NOT-IN-DISK-LABEL)
  (:PACKAGE FILE-SYSTEM)
  (:COMPILE-LOAD ("SERVER")))

FS:
(DEFUN LOAD-SYSTEMS (&REST SYSTEMS)
  (LOOP FOR SYSTEM IN SYSTEMS
	DO (SETQ SYSTEM (SI:FIND-SYSTEM-NAMED SYSTEM))
	   (MAKE-SYSTEM SYSTEM ':NOWARN)
	WHEN (SI:SYSTEM-PATCHABLE-P SYSTEM)
	COLLECT SYSTEM INTO PATCHABLE-SYSTEMS
	FINALLY (LOAD-PATCHES ':NOSELECTIVE ':SYSTEMS PATCHABLE-SYSTEMS)))

;;; The following are miscellaneous systems that are to be used with the Magtape and File
;;; systems.  They are not patchable.

;;; the Distribution system is not carried.  It copied the system's
;;; directories to another host or to tape for shipping to a site; this system ships
;;; a release as a pack and a sources tarball instead.
;(DEFSYSTEM DISTRIBUTION
;  (:NAME "Distribution")
;  (:NICKNAMES "Dis")
;  (:PATHNAME-DEFAULT "SYS: DISTRIBUTION;")
;  (:PACKAGE FILE-SYSTEM)
;  (:COMPILE-LOAD ("DIST")))

;;; the tape systems are not carried, SYS: TAPE; being absent; see the
;;; note on MagTape above.  Commented out rather than deleted so that what
;;; was removed stays visible.
;(DEFSYSTEM ITS-TAPE
;  (:NAME "ITS-Tape")
;  (:NICKNAMES "ITST" "PDP10T")
;  (:PATHNAME-DEFAULT "SYS: TAPE;")
;  (:PACKAGE FILE-SYSTEM)
;  (:COMPILE-LOAD ("PDP10")))

;(DEFSYSTEM VMS-TAPE
;  (:NAME "VMS-Tape")
;  (:NICKNAMES "VMST")
;  (:PATHNAME-DEFAULT "SYS: TAPE;")
;  (:PACKAGE FILE-SYSTEM)
;  (:COMPILE-LOAD ("VMS")))