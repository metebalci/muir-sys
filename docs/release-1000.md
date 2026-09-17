# Release 1000

What release 1000 changes from its base, LM-3's **System 100** --- the tape
content of release 99.32 as LM-3 brought it up --- with microcode 323. Every
change to a source file carries a comment in that file saying why.

## Left out of the tree

Nothing below was ever imported. A full copy of System 100 is kept outside the
repository for anything that turns out to be wanted.

- **The 3,066 numbered file versions.** The file server has no versions, and
  the machine reads the unnumbered file.
- **MIT's site files.** Every site supplies its own.
- **`tape/`**, and the MagTape code that lived in `file/`: `mtdefs`, `mtstr`,
  `mtaux`, `odump`. No machine this system targets has a tape drive.
- **`doc/`**, bug mail and bboard archives that nothing loads.
- **`ubin/`**, which the micro assembler writes from `ucadr/`, and the copy of
  its disk-formatting microcode, `dcfu.uload`, that had strayed into `cc/`.
- **The Xerox Press and Dover printing binaries.**
- **`cold/minisr`**, the PDP-10 MINI server, whose work ozd does.
- **Files nothing names and nothing needs:** the old evaluator and package
  system (`sys/qev.lisp`, `sys/pack4.lisp`), which `eval` and `clpack` replaced;
  an alternate network window front end and a TELNET scrap in `window/`; Dover
  and Versatec printing code (`io1/dplt`, `io1/rfontx`, `demo/versat`); MacLisp
  leftovers (`sys2/condit`, `sys2/cmany`, `ucadr/cadldb`); an unused access
  interface, mail server, reader comparer and error-handler stub
  (`file/fsname`, `zmail/lmcsrv`, `io/rcomp`, `eh/ehsys`); and two microcode
  fragments nothing assembles (`ucadr/mmtest`, `ucadr/uc-array-cache`).
- **`distribution/`**, LMI's tools for copying the system to another host or
  to tape for shipping to a site.
- **`ucadr/obsolete-cold-load-maker.lisp`**, the old loader that pushed a cold-load
  file into a CADR from a second machine; `MAKE-COLD` replaced it.
- **`file2/`**, the older LMFILE file computer, except `file2/pathnm.lisp`,
  which System loads for LMFILE pathnames.
- **Every patch file and every patch directory except System's own.** This system makes
  releases, never patches.
- **The `-read-.-this-` directory notes** and two scratch files in `cc/`.
- **`zwei/.comnd.text`**, a generated ZMacs command list whose name carried a
  Control-V byte, ITS's quote character for file names.
- **Renamed rather than left out:** four notes in `man/` had the same Control-V
  at the front of their names, which Unix tools mishandle. They are imported
  as `bug.lmman`, `dlw.wordab`, `forma.text` and `machn.compar`.
- **The BUG-ZWEI and BUG-ZMAIL mail archives** in `zwei/` and `zmail/`, 1982-84,
  about 2.7 MB of saved mailing-list traffic, and three files misnamed
  `.text`: the PDP-10 DOOR server's source (`io1/door.text`), old MacLisp
  code (`io1/mouse.text`), and a stray binary (`ucadr/ucadlr.text`).
- **Kept as reference:** `man/` and `wind/`, the Lisp Machine Manual and the
  Window System manual in Bolio source, which describe this system but which
  nothing here formats.
- **Generated output**: compiler warning databases, tag tables, mail indexes,
  and every QFASL except three that nothing here can make again: the fonts,
  `demo/tvbgar`, and `sys/ucinit.qfasl`, which records the functions
  microcompiled into the microcode and was written once, by hand, at MIT.

## The release's identity

- **The system number is 1000** (`patch/system.patch-directory`,
  `patch/system-1000.patch-directory`).
- **Versions print as whole numbers** (`sys2/patch.lisp`,
  `DESCRIBE-SYSTEM-VERSIONS` and `SYSTEM-VERSION-INFO`): with no patches, the
  minor number is always zero.
- **Only System is patchable.** Local-File and FILE-Server (`file/fs.lisp`),
  CADR and ZMail (`sys/sysdcl.lisp`) no longer are; CADR's `:INITIAL-STATUS`
  went with it, since that macro signals an error on a system that is not.

## Faults that stopped the system rebuilding itself

- **`sys2/prodef.lisp`:** `SCHEDULER-STACK-GROUP` is declared `NIL`. Read unbound
  while a cold load still had traps disabled, it halted the machine with
  nothing printed. (#6)
- **`cold/mini.lisp`:** "Unknown stream operation" names the operation. (#7)
- **`cold/mini.lisp`:** both MINI streams answer `:SEND-IF-HANDLES`, which a
  cold load's QLD sends to every stream. (#7)
- **`sys/cdmp.lisp`:** `CONS-DUMP-MEMORIES` dumps the microcode symbol image
  only after the `-3` that announces it. It wrote an empty image as a run of
  `NIL`s the loader cannot read, so `DCFU ULOAD` and `MEMD ULOAD` could not be
  made again as System 100 has them.

## The network and the cold load

- **`network/chaos/chsncp.lisp`:** the routing table holds 256 subnets, not 96.
  A machine on subnet 96 or above trapped as the network started.
- **`cold/mini.lisp`:** the file server's address is worked out at compile time
  from the host of the file being compiled, as release 99.32 did. System 100
  had hard-coded MIT's OZ, `#o3060`.
- **The host table is a site file:** `SYS: CHAOS; HOSTS` became
  `SYS: SITE; HOSTS` (`network/chaos/chsaux.lisp`, `sys/sysdcl.lisp`).
- **`sys/ltop.lisp`:** `LISP-REINITIALIZE` does its boot work at boot. Its test
  was inverted, so the TV sync setup, the run-light locations and the screen
  clear ran on a user's call instead.
- **`sys/ltop.lisp`, `window/shwarm.lisp`:** the run-light setup is a function
  of its own, `TV::INITIALIZE-RUN-LIGHT-LOCATIONS`, which the screen code calls
  on a CADR.

## Systems removed

- **MagTape, ITS-Tape and VMS-Tape** (`file/fs.lisp`, `sys/sysdcl.lisp`).
- **LFS, LMFILE-Server and LMFILE-Remote** (`sys/sysdcl.lisp`).
- **Distribution** (`file/fs.lisp`).
- **PRESS**, printing to a Xerox Dover (`io1/press.lisp` and `io1/rfontw.lisp`
  deleted; `sys/sysdcl.lisp`). Six files still name the PRESS package in their
  hardcopy paths (#14).

## Fixes

Chosen one at a time from LM-3's later work, as `docs/upstream-changes.md`
records, and checked against these files before they were applied.

- **`cold/`:** a `BARF` naming a misspelled symbol (`qdefs`); `WITH-LIST` and
  `WITH-LIST*` exported (`global`); `SIZE-OF-HARDWARE-M-MEMORY` is the CADR's
  alone (`qcom`).
- **`sys/`:** `ARRAY-POP`'s array types (`qmisc`); `COMPILE-FILE`'s keyword
  names (`qcfile`); `LETF`'s stack list (`eval`); a misspelled warning
  (`qcopt`); `KEY-FETCH` and `KEY-FETCH-INC` use a `LET`, not the PDL buffer
  (`genric`).
- **`sys2/`:** `ADVISE-FIND-SLOT`'s misspelled argument (`advise`); the
  `DEFRESOURCE` deinitializer test (`resour`); a paren inside a `SETF` place
  (`defsel`); a ZWEI call guarded for
  bands without ZWEI (`flavor`); `DEFVAR` so reloading makes no second area
  (`analyze`); warnings files named after their system (`maksys`); login
  without a home directory no longer enters the debugger (`login`).
- **`io/`:** `MERGE-PATHNAME-COMPONENTS` assigned the wrong variable, and
  `DEFAULT-HOST` and `DEFAULT-PATHNAME` failed before login (`file/pathnm`);
  Unix pathnames gained `:STRING-FOR-DIRECTORY` (`file/pathst`); completion
  kept a Unix host's case (`file/open`); `:DELETE-MULTIPLE-FILES` passed its
  argument wrongly (`file/access`); the disk label editor reads the label it
  edits (`dledit`); `MAKE-PROCESS` rather than a nonexistent `PROCESS-CREATE`
  (`io1/swar`).
- **`network/`:** an unkeyworded clause key (`chaos/chuse`); swapped
  arguments, and a host lookup for address 0 (`chaos/peekch`); HOSTAT no longer
  hangs on an unknown host (`chaos/chsaux`).
- **`window/`:** a menu crash on an atom item (`menu`); scroll items read from
  the right element (`tscrol`); the motion limit in both scanning loops
  (`shwarm`).
- **`zwei/comtab.lisp`:** six key bindings named commands that do not exist,
  and `COMMAND-STORE` stored keys lookup could not find.
- **`demo/doctor.lisp`, `file/server.lisp`:** a call to a nonexistent `QUIT`;
  the file server's initialization named for its Chaos contact.

## Bring-up notes answered

System 100's `;;;---!!!` questions, answered in place (#12):
`network/host.lisp` (`:DEFAULT-DEVICE`, which nothing sends, removed),
`sys/eval.lisp` and `io/file/logical.lisp`.

## Around the system

- **The MIT site** in `site/`. `sys.translations` doubles its slashes and names
  no readtable, because a cold load reads it in the traditional readtable (#9).
  `hsttbl.lisp` is not carried: the SITE system writes it from `hosts.text`.
- **The GNU Affero General Public License, version 3 or later**, in `LICENSE`,
  continuing LM-3's declaration for System 100.
