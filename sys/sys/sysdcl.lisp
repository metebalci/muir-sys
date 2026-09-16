;;;-*- Mode:LISP; Package:SYSTEM-INTERNALS; Readtable:ZL; Base:10 -*-

;;; Declarations for SYSTEM's initally loaded
;;; ** (c) Copyright 1980 Massachusetts Institute of Technology **

(DEFSYSTEM SYSTEM
  (:NAME "System")
  (:SHORT-NAME "SYS")
  (:PATCHABLE "SYS: PATCH;")
  (:MODULE ALLDEFS ("SYS: SYS2; DEFMAC"		;These are defs files for whole system
		    "SYS: SYS2; LMMAC"
		    "SYS: EH; ERRMAC"
		    "SYS: SYS2; STRUCT"
		    "SYS: SYS2; SETF"
		    "SYS: SYS; TYPES")
	   :PACKAGE SI)
  (:COMPONENT-SYSTEMS FONTS		;Before SYSTEM-INTERNALS because things use fonts
		      SYSTEM-INTERNALS
		      FORMAT		;a NO-OP if loading for first time
		      CHAOS		;likewise
		      COMPILER
		      FILE-SYSTEM
		      QFASL-REL
		      TIME		;must be before TV
		      TV
		      PEEK
		      SUPDUP
		      ZWEI
		      FED
		      COLOR
		      EH
		      PRESS
		      MATH
		      HACKS
		      METER
		      SRCCOM
		      CONVERSE
		      )
  (:COMPILE-LOAD ALLDEFS)
  (:DO-COMPONENTS (:FASLOAD ALLDEFS)))

(DEFSYSTEM SYSTEM-INTERNALS
  (:PACKAGE SYSTEM-INTERNALS)
  (:NICKNAMES "SI")
  (:MODULE DEFS ("SYS: SYS2; PRODEF"
		 "SYS: IO; RDDEFS"
		 "SYS: SYS2; SGDEFS"
		 "SYS: SYS2; NUMDEF"))
  (:MODULE METH "SYS: SYS2; METH")
  (:MODULE CLASS "SYS: SYS2; CLASS") 
  (:MODULE MAIN ("SYS: SYS2; ADVISE"
		 "SYS: SYS2; BAND"
		 "SYS: SYS2; CHARACTER"
		 "SYS: SYS; CLPACK"	;packages
		 "SYS: COLD; GLOBAL"	;for package initialization
		 "SYS: COLD; SYSTEM"
		 "SYS: COLD; LISP"
		 "SYS: WINDOW; COLD"
		 "SYS: SYS2; DEFSEL"	;defselect
		 "SYS: SYS2; DESCRIBE"
		 "SYS: IO; DISK"
		 "SYS: IO; DLEDIT"	;disk-label editor
		 "SYS: IO; DRIBBL"	;dribble
		 "SYS: SYS2; ENCAPS"	;encapsulations
		 "SYS: SYS; EVAL"
		 "SYS: SYS2; FLAVOR"
		 "SYS: SYS; FSPEC"
		 "SYS: SYS2; GC"
		 "SYS: SYS; GENRIC"	;new commonlisp functions
		 "SYS: IO; GRIND"
		 "SYS: SYS2; HASH"
		 "SYS: SYS2; HASHFL"	;flavorized hash table stuff
		 "SYS: NETWORK; HOST"	; Still in SYSTEM-INTERNALS (for now)
		 "SYS: NETWORK; PACKAGE" ; network package definitions
		 "SYS: IO1; INC"
		 "SYS: IO1; INFIX"
		 "SYS: SYS2; LOGIN"
		 "SYS: SYS2; LOOP"
		 "SYS: SYS; LTOP"
		 "SYS: SYS2; MACARR"	;mucklisp array functions. bletch
		 "SYS: SYS2; MAKSYS"
		 "SYS: COLD; MINI"
;		 "SYS: IO; ETHER-MINI"	;New ethernet.  putting both flavors of mini in
					; won't hurt too much since its work is already
					; done by the time the wrong one would get loaded.
		 "SYS: SYS2; NUMER"
		 "SYS: SYS2; PATCH"
		 "SYS: SYS2; PLANE"
		 "SYS: IO; PRINT"
		 "SYS: SYS2; PROCES"
		 "SYS: IO; QIO"
		 "SYS: SYS; QFASL"
		 "SYS: SYS; QFCTNS"
		 "SYS: SYS; QMISC"
		 "SYS: IO1; HARDCOPY"
		 "SYS: SYS; QNEW"
		 "SYS: SYS; QRAND"
		 "SYS: SYS2; QTRACE"	;trace
		 "SYS: SYS2; RAT"
		 "SYS: IO; READ"
		 "SYS: SYS2; RESOUR"	;resources
		 "SYS: SYS2; SELEV"
		 "SYS: IO1; SERIAL"
		 "SYS: SYS; SGFCTN"
		 "SYS: SYS; SORT"
		 "SYS: SYS2; STEP"
		 "SYS: IO; STREAM"
		 "SYS: SYS2; STRING"
		 "SYS: SYS; SYSDCL"
		 "SYS: SYS2; UNFASL"
		 "SYS: IO; UNIBUS"
		 "SYS: SYS2; CLMAC"	;alternate macro definitions for some zl special forms
		 "SYS: SYS2; ANALYZE"
		 ))
  (:MODULE RDTBL ("SYS: IO; RDTBL" "SYS: IO; CRDTBL"))
  (:MODULE EXPORT ("SYS: COLD; EXPORT"))
  (:COMPILE-LOAD DEFS)
  (:COMPILE-LOAD MAIN (:FASLOAD DEFS))
  (:FASLOAD RDTBL)
  (:READFILE EXPORT)
  (:COMPILE-LOAD METH (:FASLOAD DEFS))
  (:COMPILE-LOAD CLASS (:FASLOAD DEFS) (:FASLOAD METH)))

(DEFSYSTEM FONTS
  (:PACKAGE FONTS)
  (:PATHNAME-DEFAULT "SYS: FONTS;")
  (:FASLOAD ("TVFONT" "CPTFONTB" "CPTFONT" "BIGFNT" "TINY" "5X5"
	     "MEDFNT" "MEDFNB" "METS" "METSI" "43VXMS"
	     "HL6" "HL7" "HL10" "HL10B" "HL12" "HL12I" "HL12B" "HL12BI"
	     "TR8" "TR8I" "TR8B" "TR10" "TR10I" "TR10B" "TR10BI"
	     "TR12" "TR12B" "TR12I" "TR12BI"
	     "MOUSE" "SEARCH" "TOG" "ABACUS" "NARROW"))
  (:READFILE ("EQUIVALENCE")))

(DEFSYSTEM CHAOS
  (:PACKAGE CHAOS)
  (:PATHNAME-DEFAULT "SYS: NETWORK; CHAOS;")
  (:MODULE NCP ("CHSNCP" "CHUSE"))
  (:MODULE AUX "CHSAUX")
  (:MODULE TEST "CHATST")
  (:MODULE EFTP "EFTP")
  (:COMPILE-LOAD (NCP AUX TEST EFTP))
  (:COMPILE-LOAD (:GENERATE-HOST-TABLE (("SYS: CHAOS; HOSTS" "SYS: SITE; HSTTBL")))))

;;; New ethernet
(DEFSYSTEM ETHERNET
  (:NAME "Ethernet")
  (:SHORT-NAME "Ether")
  (:PACKAGE ETHERNET)
  (:PATHNAME-DEFAULT "SYS: IO;")
  (:MODULE MAIN ("SIMPLE-ETHER" "ADDR-RES"))
  (:COMPILE-LOAD (MAIN)))

(DEFSYSTEM SITE
  (:PACKAGE SYSTEM-INTERNALS)
  (:MODULE SITE ("SYS: SITE; SITE" "SYS: SITE; LMLOCS"))
  (LOAD-SITE-FILE (:COMPILE SITE))
  (:MODULE HOST-TABLE (("SYS: CHAOS; HOSTS" "SYS: SITE; HSTTBL"))
		      :PACKAGE CHAOS)
  (LOAD-SITE-FILE (:COMPILE (:GENERATE-HOST-TABLE HOST-TABLE))))

(DEFSYSTEM TIME
  (:PACKAGE TIME)
  (:PATHNAME-DEFAULT "SYS: IO1;")
  (:COMPILE-LOAD ("TIME" "TIMPAR")))

(DEFSYSTEM SUPDUP
  (:PACKAGE SUPDUP)
  (:COMPILE-LOAD ("SYS: WINDOW; SUPDUP")))

(DEFSYSTEM PRESS
  (:PACKAGE PRESS)
  (:PATHNAME-DEFAULT "SYS: IO1;")
  (:MODULE RFONTW "RFONTW")
  (:MODULE PRESS "PRESS")
  (:MODULE FONTW "PRESS-FONTS; FONTS WIDTHS >")
  (:COMPILE-LOAD RFONTW)
  (:COMPILE-LOAD PRESS)
;;;---!!! How is PRESS-FONTS; FONTS WIDTHS generated?
;;;---!!!  (:LOAD-FONTS-WIDTHS FONTW (:FASLOAD RFONTW))
  )

(DEFSYSTEM FORMAT
  (:PACKAGE FORMAT)
  (:COMPILE-LOAD ("SYS: IO; FORMAT"
;pos		  "SYS: IO; FORMAT-MACRO" 
		  "SYS: IO1; FQUERY"
		  "SYS: IO1; OUTPUT")))

(DEFSYSTEM QFASL-REL
  (:PACKAGE QFASL-REL)
  (:PATHNAME-DEFAULT "SYS: IO1;")
  (:COMPILE-LOAD ("RELLD" "RELDMP")))

(DEFSYSTEM COMPILER
  (:PACKAGE COMPILER)
  (:MODULE DEFS ("SYS: SYS; MADEFS"
		 "SYS: SYS; QCDEFS"))
  (:MODULE MAIN ("SYS: SYS2; DISASS"
		 "SYS: SYS; MA"
		 "SYS: SYS; MAOPT"
		 "SYS: SYS; MC"
		 "SYS: SYS; MLAP"
		 "SYS: SYS; QCFASD"
		 "SYS: SYS; QCFILE"
		 "SYS: SYS; QCP1"
		 "SYS: SYS; QCP2"
		 "SYS: SYS; QCOPT"
		 "SYS: SYS; QCLUKE"
		 "SYS: SYS; QCPEEP"
		 "SYS: SYS; QCLAP"))
  (:COMPILE-LOAD DEFS)
  (:COMPILE-LOAD MAIN (:FASLOAD DEFS))
  (:READFILE ("SYS: COLD; DEFMIC"
	      "SYS: COLD; DOCMIC"))
  (:FASLOAD ("SYS: SYS; UCINIT")))

(DEFSYSTEM COLOR
  (:PACKAGE COLOR)
  (:COMPILE-LOAD ("SYS: WINDOW; COLOR")))

(DEFSYSTEM ZWEI
  (:PACKAGE ZWEI)
  (:PATHNAME-DEFAULT "SYS: ZWEI;")
  (:MODULE DEFS ("DEFS"				;Structure definitions and declarations.
		 "MACROS"))			;Lisp macros used in the ZWEIs source.
  (:MODULE SCREEN ("SCREEN"))			;Interface to screen system
  (:MODULE MAIN ("COMTAB"			;Functions regarding comtabs and command loop.
		 "DISPLA"			;Redisplay, and screen-related functions.
		 "FOR"				;Forward-this, forward-that functions.
		 "INDENT"			;Indention functions
		 "INSERT"			;Insertion and deletion, and related functions
		 "METH"				;Important methods for windows and buffers.
		 "PRIMIT"			;Random primitives and utilities.
		 "NPRIM"			;More recently written primitves
		 "HISTORY"			;Kill history, mini buffer history, etc.
		 "FONT"				;Font hacking stuff
		 "KBDMAC"			;Keyboard macro stream
		 "SEARCH"			;Searching functions

		 "COMA"				;Vanilla commands.
		 "COMB"				;More vanilla commands.
		 "COMC"				;Yet more vanilla commands.
		 "COMD"				;Still more vanilla commands.
		 "COME"				;Even more vanilla commands.
		 "COMF"				;More and more vanilla commands
		 "COMG"				;And more vanilla commands
		 "COMH"
		 "COMS"				;Searching and replacing commands.
		 "DIRED"			;Directory editor.
		 "BDIRED"			;Directory Differences editor.
		 "DOC"				;Self-documentation commands and functions.
		 "FASUPD"			;Update fasl file from core.
		 "FILES"			;File commands and utilities.
		 "HOST"				;Define ED:, ED-BUFFER:, ED-FILE: hosts.
		 "ISPELL"                       ;spelling corrector
		 "LPARSE"			;Parsing lisp code.
		 "MODES"			;Major and minor mode functions and commands
		 "MOUSE"			;Mouse commands less screen interface
		 "PATED"			;Patch commands.
		 "PL1MOD"			;PL/I mode commands.
		 "POSS"				;Visiting lists of things
		 "STREAM"			;Editor stream

		 "SECTIO"			;Some section specific command for ZMACS
		 "ZMNEW"
		 "ZMACS"))			;Multiple-buffer and file commands.

  (:MODULE ZYMURG ("ZYMURG"))			;Combined methods.

  (:COMPILE-LOAD DEFS)
  (:COMPILE-LOAD SCREEN (:FASLOAD DEFS))
  (:COMPILE-LOAD MAIN (:FASLOAD DEFS SCREEN))
  (:COMPILE-LOAD ZYMURG (:FASLOAD DEFS SCREEN MAIN)))


;;; Font editor
(DEFSYSTEM FED
  (:PACKAGE FED)
  (:MODULE DEFS "SYS: IO1; FNTDEF")
  (:MODULE MAIN ("SYS: IO1; FNTCNV"
		 "SYS: WINDOW; FED"
		 ))
  (:READFILE DEFS)
  (:COMPILE-LOAD MAIN (:READFILE DEFS)))

;;; error handler, debugger
(DEFSYSTEM EH
  (:PACKAGE EH)
  (:PATHNAME-DEFAULT "SYS: EH;")
  (:COMPILE-LOAD ("EH" "EHF" "EHC" "EHW" "EHBPT")))

(DEFSYSTEM TV
  (:PACKAGE TV)
  (:PATHNAME-DEFAULT "SYS: WINDOW;")
  (:MODULE DEFS "TVDEFS")
  (:MODULE MAIN ("SCRMAN" "SHEET" "SHWARM" "BASWIN" "WHOLIN"
		 "MOUSE" "BASSTR" "STREAM" "GRAPHICS" "MENU" "COMETH"
		 ;; The above must be loaded before any windows get created
		 "SYSMEN" "SCRED" "TYPWIN" "SCROLL" "TSCROL"
		 "FRAME" "CHOICE" "CSRPOS" "INSPCT" "RH"))
  (:COMPILE-LOAD DEFS)
  (:COMPILE-LOAD MAIN (:FASLOAD DEFS)))

(DEFSYSTEM PEEK
  (:PACKAGE TV)
  (:PATHNAME-DEFAULT "SYS: WINDOW;")
  (:MODULE MAIN "PEEK")
  (:MODULE CHAOS "SYS: NETWORK; CHAOS; PEEKCH" :PACKAGE CHAOS)
  (:MODULE FILE "PEEKFS" :PACKAGE FS)
  (:COMPILE-LOAD MAIN)
  (:COMPILE-LOAD CHAOS)
  (:COMPILE-LOAD FILE))

(DEFSYSTEM FILE-SYSTEM
  (:PACKAGE FILE-SYSTEM)
  (:NICKNAMES "FS")
  (:PATHNAME-DEFAULT "SYS: IO; FILE;")
  (:MODULE BASIC-PATHNAMES ("ACCESS" "PATHNM"))
  (:MODULE HOST-PATHNAMES ("PATHST" "LOGICAL" "SYS:FILE2;PATHNM" "SYS:FILE;LMPARS"))
  (:MODULE FILE-IO ("OPEN" "BALDIR"))
  (:MODULE CHAOS-FILE-IO ("SYS: NETWORK; CHAOS; QFILE"))
  (:COMPILE-LOAD BASIC-PATHNAMES)
  (:COMPILE-LOAD HOST-PATHNAMES (:FASLOAD BASIC-PATHNAMES))
  (:COMPILE-LOAD FILE-IO (:FASLOAD BASIC-PATHNAMES))
  (:COMPILE-LOAD CHAOS-FILE-IO (:FASLOAD HOST-PATHNAMES)))

(DEFSYSTEM MATH
  (:PACKAGE MATH)
  (:COMPILE-LOAD ("SYS: SYS2; MATRIX")))

;;; Random use programs and demos
(DEFSYSTEM HACKS
  (:PACKAGE HACKS)
  (:PATHNAME-DEFAULT "SYS: DEMO;")
  (:MODULE DEFS "HAKDEF")
  (:MODULE MAIN ("ABACUS" "ALARM" "BEEPS" "CAFE" "COLXOR" "COLORHACK" "CROCK"
		 "DC" "DEUTSC" "DLWHAK" "DOCTOR" "DOCSCR"
		 "GEB" "HCEDIT" "MUNCH" "OHACKS" "ORGAN" "QIX"
		 "ROTATE" "ROTCIR" "WORM" "WORM-TRAILS"))
  (:COMPILE-LOAD DEFS)
  (:COMPILE-LOAD MAIN (:FASLOAD DEFS))
  (:FASLOAD ("TVBGAR" "WORMCH")))

;;; Source compare
(DEFSYSTEM SRCCOM
  (:PACKAGE SRCCOM)
  (:COMPILE-LOAD ("SYS: IO1; SRCCOM")))

(DEFSYSTEM METER
  (:PACKAGE METER)
  (:COMPILE-LOAD ("SYS: IO1; METER")))

;;; Interactive message program
(DEFSYSTEM CONVERSE
  (:PACKAGE ZWEI)
  (:COMPILE-LOAD ("SYS: IO1; CONVER")))

;;; Systems not initially loaded, but done right afterwards
;;; MIT-Specific definition moved to SYS: SITE; MIT-SPECIFIC SYSTEM

(DEFSYSTEM CADR
  (:NAME "CADR")
  (:PATHNAME-DEFAULT "SYS:CC;")
  (:PATCHABLE "SYS: PATCH;")
  (:INITIAL-STATUS :RELEASED)
  (:NOT-IN-DISK-LABEL)
  (:PACKAGE CADR)
  (:COMPONENT-SYSTEMS CADR-MICRO-ASSEMBLER CADR-DEBUGGER))

(DEFSYSTEM CADR-DEBUGGER
  (:PACKAGE CADR)
  (:NICKNAMES "CC")
  (:PATHNAME-DEFAULT "SYS: CC;")
  (:MODULE DEFS ("SYS: CC; LQFMAC"
		 "SYS: CC; LCADMC"))
  (:MODULE MAIN ("SYS: CC; CC"
		 "SYS: CC; CCGSYL"
		 "SYS: CC; LCADRD"
		 "SYS: CC; DIAGS"
		 "SYS: CC; DMON"
		 "SYS: CC; LDBG"
		 "SYS: CC; ZERO"
		 "SYS: CC; CADLD"
		 "SYS: CC; QF"
		 "SYS: CC; CCWHY"
		 "SYS: CC; CCDISK"
		 "SYS: CC; DCHECK"
		 "SYS: CC; CHPLOC"
		 "SYS: CC; SALVAG"))
  (:COMPILE-LOAD DEFS)
  (:READFILE ("SYS: CC; CADREG"))
  (:COMPILE-LOAD MAIN (:FASLOAD DEFS)))

(DEFSYSTEM CADR-MICRO-ASSEMBLER
  (:PACKAGE MICRO-ASSEMBLER)
  (:NICKNAMES "UA" "MICRO-ASSEMBLER")
  (:MODULE ASS "SYS: SYS; CADRLP")
  (:MODULE MAIN ("SYS: SYS; CDMP"
		 "SYS: SYS; QWMCR"
		 "SYS: IO; FREAD"
		 "SYS: SYS2; USYMLD"))
  (:COMPILE-LOAD ASS)
  (:READFILE ("SYS: COLD; QCOM"
	      "SYS: COLD; DEFMIC"
	      "SYS: SYS; CADSYM")
	     (:FASLOAD ASS))
  (:COMPILE-LOAD MAIN))

(SET-SYSTEM-SOURCE-FILE "UCODE" "SYS: UCADR; UCODE")

(DEFSYSTEM ZMAIL
  (:NAME "ZMail")
  (:PATHNAME-DEFAULT "SYS: ZMAIL;")
  (:SHORT-NAME "ZM")
  (:PATCHABLE "SYS: PATCH;")
  (:NOT-IN-DISK-LABEL)
  (:PACKAGE ZWEI)
  (:MODULE DEFS "DEFS")
  (:MODULE TV ("MULT" "BUTTON") :PACKAGE TV)
  (:MODULE MAIN ("TOP" "MFILES" "MFHOST" "REFER" "LMFILE" "SYS:FILE;ZMAIL"
		 "SYS:ZMAIL;COMNDS" "MAIL" "WINDOW" "FILTER" "PROFIL" TV))
  (:MODULE COMETH "COMETH")
; (:MODULE PARSE "PARSE")
  (:MODULE RFC733 "RFC733")
  (:MODULE LEX733 "LEX733")
; (:MODULE FONTS "NARROW")	;now in fonts system
  (:COMPILE-LOAD DEFS)
  (:COMPILE-LOAD MAIN (:FASLOAD DEFS))
; (:COMPILE-LOAD PARSE)
  (:COMPILE-LOAD RFC733
;		 (:FASLOAD PARSE)
		 )
; (:RTC-LOAD LEX733)		;Someday
  (:FASLOAD LEX733)
; (:FASLOAD FONTS)
  (:COMPILE-LOAD COMETH (:FASLOAD DEFS MAIN)))

(defsystem unix
  (:name "Unix-Interface")
  (:short-name "unix")
  (:package unix)
  (:pathname-default "sys:unix;")
  (:patchable nil "unix99-patch")
  (:module config ("sys;lam-config") :package si)
  (:module main ("lamtty" "share-chaos" "iomsg"))
  (:compile-load config)
  (:compile-load main (:fasload config)))

;;; Systems defined elsewhere

(LOOP FOR SYSTEM IN '(:FILE-SYSTEM-UTILITIES :LOCAL-FILE :MAGTAPE :FILE-SERVER)
      DO (SET-SYSTEM-SOURCE-FILE SYSTEM "SYS: FILE; FS"))

(LOOP FOR SYSTEM IN '(:LFS :LMFILE-SERVER :LMFILE-REMOTE)
      DO (SET-SYSTEM-SOURCE-FILE SYSTEM "SYS: FILE2; SYSTEM"))

(SET-SYSTEM-SOURCE-FILE 'COLD "SYS: COLD; COLDPK")

;;;; These are the files in the cold load
(DEFCONST COLD-LOAD-FILE-LIST
	  '("SYS: FONTS; CPTFON QFASL >"
	    "SYS: SYS; QRAND QFASL >"
	    "SYS: SYS; FSPEC QFASL >"
	    "SYS: IO; QIO QFASL >"
;	    "SYS: IO; RDTBL QFASL >"	;done specially
;	    "SYS: IO; CRDTBL QFASL >"	;done specially
	    "SYS: IO; READ QFASL >"
	    "SYS: IO; PRINT QFASL >"
	    "SYS: WINDOW; COLD QFASL >"
	    "SYS: SYS; SGFCTN QFASL >"
	    "SYS: SYS; EVAL QFASL >"
	    "SYS: SYS; TYPES QFASL >"
	    "SYS: SYS; LTOP QFASL >"
	    "SYS: SYS; QFASL QFASL >"
	    "SYS: COLD; MINI QFASL >"
	    "SYS: SYS; QFCTNS QFASL >"
	    "SYS: SYS2; STRING QFASL >"
	    "SYS: SYS2; CHARACTER QFASL >"
	    "SYS: SYS; CLPACK QFASL >"
	    "SYS: COLD; GLOBAL QFASL >"
	    "SYS: COLD; SYSTEM QFASL >"
	    "SYS: COLD; LISP QFASL >"))

(DEFCONST LAMBDA-COLD-LOAD-FILE-LIST
	  '("SYS: FONTS; CPTFON QFASL"
	    "SYS: SYS; QRAND QFASL >"
	    "SYS: SYS; FSPEC QFASL >"
	    "SYS: IO; QIO QFASL >"
;	    "SYS: IO; RDTBL QFASL >"	;done specially
;	    "SYS: IO; CRDTBL QFASL >"	;done specially
	    "SYS: IO; READ QFASL >"
	    "SYS: IO; PRINT QFASL >"
	    "SYS: WINDOW; COLD QFASL >"
	    "SYS: SYS; SGFCTN QFASL >"
	    "SYS: SYS; EVAL QFASL >"
	    "SYS: SYS; TYPES QFASL >"
	    "SYS: SYS; LTOP QFASL >"
	    "SYS: SYS; QFASL QFASL >"
	    "SYS: NETWORK; CHAOS; ETHER-MINI QFASL >"
	    "SYS: SYS; QFCTNS QFASL >"
	    "SYS: SYS2; STRING QFASL >"
	    "SYS: SYS; CLPACK QFASL >"
	    "SYS: COLD; GLOBAL QFASL >"
	    "SYS: COLD; SYSTEM QFASL >"
	    "SYS: COLD; LISP QFASL >"))

;;; These variables are looked at by the cold load generator, which takes
;;; the translated pathnames and dumps out prototype values into the new
;;; world with those strings suitable for use with MINI.
;;; They are then used before this file gets loaded.
(DEFCONST MINI-FILE-ALIST-LIST
	  '(INNER-SYSTEM-FILE-ALIST REST-OF-PATHNAMES-FILE-ALIST
	    ETHERNET-FILE-ALIST SITE-FILE-ALIST HOST-TABLE-FILE-ALIST))

(DEFCONST INNER-SYSTEM-FILE-ALIST
	  '(("SYS: SYS2; DEFSEL QFASL >" "SI")	;By (resource named-structure-invoke)
	    ("SYS: SYS2; RESOUR QFASL >" "SI")	;By FILLARRAY
	    ("SYS: SYS; QMISC QFASL >" "SI")
	    ("SYS: SYS; SORT QFASL >" "SI")	;Needed by FLAVOR
	    ("SYS: IO; FORMAT QFASL >" "FORMAT")	;ditto
	    ("SYS: IO1; FQUERY QFASL >" "FORMAT")	;Needed by everything in sight
	    ("SYS: SYS2; HASH QFASL >" "SI")	;Needed by FLAVOR,PATHNM
	    ("SYS: SYS2; FLAVOR QFASL >" "SI")	;Needed by PROCES
	    ("SYS: SYS2; HASHFL QFASL >" "SI")	;Make flavors really work.
	    ("SYS: SYS2; PRODEF QFASL >" "SI")	;Definitions for PROCES
	    ("SYS: SYS2; PROCES QFASL >" "SI")
	    ("SYS: SYS2; NUMER QFASL >" "SI")	;SI:EXPT-HARD needed by PROCES
	    ("SYS: EH; EH QFASL >" "EH")
	    ("SYS: EH; EHF QFASL >" "EH")
	    ("SYS: EH; EHC QFASL >" "EH")
	    ("SYS: EH; EHBPT QFASL >" "EH")
	    ("SYS: SYS2; DISASS QFASL >" "COMPILER")	;EH calls subroutines in DISASS
	    ("SYS: SYS2; DESCRIBE QFASL >" "SI")	;For hack value
	    ("SYS: IO; DISK QFASL >" "SI")
	    ("SYS: SYS2; LOGIN QFASL >" "SI")	;ditto
	    ("SYS: IO; RDDEFS QFASL >" "SI")	;Load this before trying to read any #\'s
	    ("SYS: NETWORK; HOST QFASL >" "SI")
	    ("SYS: NETWORK; PACKAGE QFASL >" "SI")
	    ("SYS: IO; FILE; ACCESS QFASL >" "FS")
	    ("SYS: IO; STREAM QFASL >" "SI")	;Probably needed by any file system
	    ;; PATHNM must be the last file in this list.  It breaks things while cold loading
	    ;; that QLD knows how to fix after this alist is loaded.
	    ("SYS: IO; FILE; PATHNM QFASL >" "FS")))

(DEFCONST REST-OF-PATHNAMES-FILE-ALIST
	  '(("SYS: IO; FILE; PATHST QFASL >" "FS")
	    ("SYS: IO; FILE; LOGICAL QFASL >" "FS")
	    ("SYS: FILE2; PATHNM QFASL >" "FS")
	    ("SYS: FILE; LMPARS QFASL >" "FS")
	    ("SYS: IO; FILE; OPEN QFASL >" "FS")
	    ("SYS: NETWORK; CHAOS; CHSNCP QFASL >" "CHAOS")
	    ("SYS: NETWORK; CHAOS; CHUSE QFASL >" "CHAOS")
	    ("SYS: NETWORK; CHAOS; QFILE QFASL >" "FS")))

(DEFCONST ETHERNET-FILE-ALIST
	  '(("SYS: NETWORK; SIMPLE-ETHER QFASL >" "ETHERNET")
	    ("SYS: NETWORK; ADDR-RES QFASL >" "ETHERNET")))

(DEFCONST SITE-FILE-ALIST
	  '(("SYS: SITE; SITE QFASL >" "SI")))

(DEFCONST HOST-TABLE-FILE-ALIST
	  '(("SYS: SITE; HSTTBL QFASL >" "CHAOS")
	    ("SYS: SITE; LMLOCS QFASL >" "SI")
	    ("SYS: SITE; SYS TRANSLATIONS >" "FS")))
