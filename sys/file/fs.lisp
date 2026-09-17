;;; -*- Mode: Lisp; Package: User; Base: 8 -*-

(DEFSYSTEM FILE-SYSTEM-UTILITIES
  ;; MAGTAPE is no longer a component; its system went with SYS: TAPE;, which is not carried.
  (:COMPONENT-SYSTEMS LOCAL-FILE
		      FILE-SERVER
		      ))

(DEFSYSTEM LOCAL-FILE
  (:NAME "Local-File")
  (:SHORT-NAME "FS")
  (:PATHNAME-DEFAULT "SYS: FILE;")
  ;; not patchable.  This system makes releases, never patches; only System keeps a patch directory, for its release number.
  (:NOT-IN-DISK-LABEL)
  (:PACKAGE FILE-SYSTEM)
  (:MODULE DEFS "FSDEFS")
  (:MODULE MAIN ("FSSTR" "FSGUTS" "FSACC"))
  (:COMPILE-LOAD DEFS)
  (:COMPILE-LOAD MAIN
   ((:FASLOAD DEFS))))

(DEFSYSTEM FILE-SERVER
  (:NAME "FILE-Server")
  (:NICKNAMES "Server")
  (:PATHNAME-DEFAULT "SYS: FILE;")
  ;; not patchable.  This system makes releases, never patches; only System keeps a patch directory, for its release number.
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
