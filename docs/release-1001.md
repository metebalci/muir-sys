# Release 1001

What release 1001 changes from release 1000. Its theme is a deep cleanup:
what will never be used is removed, not commented out, and git keeps the
history. Every change to a source file that stays carries a comment in that
file saying why.

## Removed

- **The Ethernet code**, written for the Lambda's 3Com board:
  `network/simple-ether.lisp`, `network/addr-res.lisp`,
  `network/ether-mini.lisp` and `network/ip/` (`address.lisp`,
  `hostsnic.lisp`). Nothing loaded them on a CADR: QLD loads the Ethernet
  files only on a Lambda. The ETHERNET system, its package and the cold-load
  lists that name these files went later, with the Lambda support below.
- **The generic network layer nothing loads:** `network/service.lisp`,
  `network/server.lisp`, `network/regions.lisp`, `network/symbols.lisp` and
  `network/smtp.lisp`. No system names them and no other file calls what they
  define. `network/package.lisp` stays, because System loads it.
- **`ucadr/uc-pup.lisp`**, the CADR's Ethernet (PUP) microcode, which
  `ucadr/ucode.lisp` had already commented out of the microcode. The
  commented line goes too.
- **Firmware tools for hardware this system does not have:** the keyboard's 8748
  program (`io1/ukbd.lisp`), the 8748 and 8751 assemblers
  (`io1/as8748.lisp`, `io1/as8751.lisp`) and the PROM programmer driver
  (`io1/promp.lisp`). No system loads them, and they call only each other.
- **Files no system loads, superseded or never finished:**
  - `file/login.lisp`, the init file of the LMFILE file computer.
  - `file/clear.lisp` and `file/hogs.lisp`, which zeroed partitions and
    listed large directories of the local file system. Local-File does not
    load them.
  - `sys/compat.lisp`, MacLisp declarations for the micro assembler, whose
    two real functions `sys/cadrlp.lisp` and `sys/cdmp.lisp` define
    themselves.
  - `sys2/let.lisp`, an old destructuring `LET` that the system's own
    replaced.
  - `sys/recom.lisp`, recompilation hacks for building worlds at MIT.
  - `io/find-plausible-partitions.lisp`, an older copy of the function
    `io/disk.lisp` defines.
  - `zmail/parse.lisp`, a parser generator that `zmail/rfc733.lisp` no longer
    uses. `sys/sysdcl.lisp` loses the ZMail module and load steps that were
    already commented out.
  - `zmail/lm.lisp`, Local-File's mail file methods on a flavor that no longer
    carries them; `file/zmail.lisp` replaced it.
  - `eh/she.lisp`, a byte-identical copy of `eh/ehw.lisp`.
  - `io/strmdoc.lisp` and `window/winddoc.lisp`, operation documentation
    written with a `DEFOPERATION` that is defined nowhere.
- **The tape, Distribution and Press definitions left commented out** by
  release 1000 are deleted outright, with their notes: MagTape, ITS-Tape,
  VMS-Tape and Distribution in `file/fs.lisp`, and Press in
  `sys/sysdcl.lisp`. `FILE-SYSTEM-UTILITIES` no longer names MAGTAPE as a
  component, and the TAPE package is gone from `sys/clpack.lisp`. The PRESS
  and UNIX packages went later, with the Lambda support below.
- **The UNIX system** in `sys/sysdcl.lisp`, the Lambda's interface to its
  Unix processor, over a `SYS: UNIX;` directory that does not exist.
- **What still called the PRESS package outside the cold load** (#14):
  - `zmail/mfiles.lisp`: ZMail's XGP, Press and Dover hardcopy devices. TPL
    remains.
  - `zwei/comh.lisp`, `zwei/comtab.lisp`: the command View Dover Queue.
  - `sys2/maksys.lisp`: `LOAD-FONT-WIDTHS-1` and the `:LOAD-FONTS-WIDTHS`
    transformation, which only the PRESS system used.
  - `io1/fntcnv.lisp`, `window/fed.lisp`: reading and writing AC files, the
    Xerox printers' font format, and FED's AC choices. KST, AST, AL, KS and
    QFASL remain.

  The PRESS package went later, with the Lambda support below.
- **EFTP** (`network/chaos/eftp.lisp`), the PUP file transfer that sent
  Press files to the Dover and files to and from Xerox Altos, and its module
  in the CHAOS system (`sys/sysdcl.lisp`). Its symbols left
  `cold/export.lisp` later, with the Lambda support below.
- **`io1/xgp.lisp`**, screen hardcopy to MIT's XGP printer. Nothing loaded it,
  and its last user was ZMail's XGP device.
- **Code disabled with `#|...|#`**, outside the cold load:
  - `zwei/comf.lisp`: the Find Pattern command, which Lisp Match Search
    replaced.
  - `zwei/poss.lisp`: `RESECTIONIZE-BUFFER-POSSIBILITY`, and an old
    `FIND-WARNINGS-BUFFER` and `UPDATE-WARNINGS-SECTION`.
  - `io1/time.lisp`: the phase of the moon.
  - `window/basstr.lisp`: an old `KBD-STATUS`.
  - `sys2/maksys.lisp`: `GENERATE-INTERNAL-CONDITION`, marked "probably a bad
    idea".

  The `#|...|#` blocks that are documentation stay: `io1/infix.lisp`,
  `io1/output.lisp`, `sys/qclap.lisp`, `sys/qcp1.lisp`, `sys2/encaps.lisp`,
  `sys2/selev.lisp`, `window/baswin.lisp`, `window/choice.lisp` and
  `window/scroll.lisp`. So does the one inside `FULL-GC` in `sys2/gc.lisp`,
  whose note says why the code is off.
- **Notes nothing reads:**
  - `zmail/poop.text`, an early ZMail chapter that `zmail/manual/` superseded.
  - `zmail/info.mail` and `file/bugs.mail`, INFO-ZMAIL and Local-File mailing
    list traffic from 1982.
  - `zwei/bugs.status` and `zwei/emacs.comdif`, ZWEI's change notes and a
    list of its commands against EMACS.
  - `file/fs.improv` and `window/task.list`, to-do lists for Local-File and
    the window system.
  - `zwei/atsign.xfile`, a listing command for printing ZWEI's sources on the
    Dover, and `zwei/grind.definition`, an empty file.
  - `ucadr/chaos.test`, a few forms for poking the Chaos board over the
    Unibus.
  - `man/manual2.bolio` and `man/manual3.bolio`, byte-identical copies of
    `man/manual.bolio`.

- **The disabled NIL version of `STORE`** in `sys2/macarr.lisp`, with its
  bring-up note that it was not MacLisp compatible (#15). The live `STORE`
  stays, and so does the Burke and MIT notice above both.
- **Code for other Lisp dialects,** chosen by read-time conditionals such as
  `#+MACLISP`, `#+Multics`, `#+NIL` and `#-LISPM`. Each conditional is
  resolved as this machine's reader resolves it: a form the reader skips is
  deleted, and a form it reads loses its conditional. The reader therefore
  produces the same forms as before.
  - `sys2/struct.lisp`: DEFSTRUCT's MacLisp, Multics and NIL versions, and
    their commented-out option declarations.
  - `sys2/loop.lisp`: LOOP's code for PDP-10 and Multics MacLisp, NIL and
    Franz. LOOP set up features of its own while compiling, such as
    `Hairy-Collection` and `Common-Lisp-MACROs`, and read the rest of the file
    under them; the conditionals are resolved as those features stood on the
    Lisp Machine, and the setup is deleted with the Multics include macro. The
    warning that incremental compilation needed the setup evaluated first goes
    with it.
  - `cc/`, the CADR debugger: the MacLisp alternatives written with `#M` and
    `#Q` in `ccdisk.lisp`, `dmon.lisp`, `lcadrd.lisp` and `qf.lisp`, and the
    MacLisp code under `IF-FOR-MACLISP` in `cc.lisp`, among it the terminal
    handling that called `STATUS TTY` and `SSTATUS TTYINT`. `IF-FOR-LISPM`
    no longer wraps the code in `cc.lisp`, `ccdisk.lisp` and `diags.lisp`;
    it only bound `RUN-IN-MACLISP-SWITCH` to NIL, which is its value anyway.
  - `sys/qcp2.lisp`, `ucadr/praid.lisp` and `ucadr/packed.lisp`: the MacLisp
    alternatives written with `#M` and `#Q`.
  - `file/zmail.lisp`, `io/file/baldir.lisp` and `demo/what.lisp`: the
    Symbolics versions under `#+SYMBOLICS`.
  - `sys2/meth.lisp`: an old `DEFMETHOD` that `#+NIL` commented out, since
    FLAVOR defines the one in use.
- **The MacLisp conditional macros** `IF-IN-MACLISP`, `IF-IN-LISPM`,
  `IF-FOR-MACLISP`, `IF-FOR-LISPM` and `IF-FOR-MACLISP-ELSE-LISPM`
  (`sys2/lmmac.lisp`), obsolete since the MacLisp cross-compiler went, once
  the debugger no longer used them. `cold/global.lisp` still exports their
  names, which is harmless and left for the cold-load cleanup. Their
  `MAY-SURROUND-DEFUN` properties in `io/read.lisp` go with them.
- **MacLisp's `STATUS` and `SSTATUS`** (`sys/qmisc.lisp`), with the
  compiler's optimizer for `STATUS` (`sys/qcopt.lisp`). Their last users read
  or changed the feature list, and now use `*FEATURES*` directly:
  `sys2/loop.lisp`, which adds `:LOOP`, and the WHAT demo's "features"
  answer (`demo/what.lisp`). `cold/global.lisp` still exports both names,
  which is left for the cold-load cleanup.
- **Obsolete names that nothing calls,** with their `MAKE-OBSOLETE`
  declarations: `CHAOS-CLOSE` (`network/chaos/chuse.lisp`), `MACRO-DISPLACE`
  (`sys2/defmac.lisp`), `MAPHASH-EQUAL-RETURN` (`sys2/hashfl.lisp`),
  `SHEET-STRING-OUT-EXPLICIT` (`window/shwarm.lisp`), `CHAR-LOWERCASE-P`
  (`zwei/search.lisp`), `CLOSURE-COPY` and `PUT-ON-ALTERNATING-LIST`
  (`sys/qmisc.lisp`), and the declaration for `WITH-RESOURCE`, which is
  defined nowhere (`sys/qcopt.lisp`). An obsolete name stays while anything
  calls it, and while a file in `cold/` exports or names it.
- **Patches.** This system never makes or loads a patch, so the machinery for them
  goes, and the version tracking that the herald, the band comment and
  `:NO-INCREMENT-PATCH` rely on stays.
  - `zwei/pated.lisp`, the editor's patch commands (Start Patch, Add Patch,
    Finish Patch and the rest), with their entries in `zwei/zmacs.lisp` and
    their module in `sys/sysdcl.lisp`, and Set Patch File in
    `zwei/zmnew.lisp`.
  - `sys2/maksys.lisp`: the step that loaded a patchable system's patches
    after `MAKE-SYSTEM` loaded it, and the `:NO-LOAD-PATCHES` keyword that
    turned it off. `:NO-INCREMENT-PATCH` stays.
  - The Patch-File attribute: it no longer binds `FS:THIS-IS-A-PATCH-FILE`
    (`io/file/open.lisp`), and the editor no longer marks a buffer's file as a
    patch file from it (`zwei/comc.lisp`). The variable stays, always NIL,
    because `sys/qrand.lisp` and `sys/fspec.lisp` in the cold load read it.
  - `sys/qfasl.lisp`: when a reloaded file no longer defines a method, the
    offer to undefine it no longer looks past patch files.
  - `file/fs.lisp`: `LOAD-SYSTEMS` no longer loads patches after the systems,
    and the WHAT demo loses "me load patches" (`demo/what.lisp`).
  - `sys2/patch.lisp`: `LOAD-PATCHES`, `LOAD-AND-SAVE-PATCHES` and its
    incremental variant, and `RESERVE-PATCH`, `CONSUMMATE-PATCH`,
    `ABORT-PATCH` and `VIEW-UNFINISHED-PATCHES`. What stays reads and writes
    the patch directories for the release number, and prints the versions:
    `ADD-PATCH-SYSTEM`, `INCREMENT-PATCH-SYSTEM-MAJOR-VERSION`,
    `GET-SYSTEM-VERSION`, `SYSTEM-VERSION-INFO`, `DESCRIBE-SYSTEM-VERSIONS`,
    `GET-NEW-SYSTEM-VERSION`, `PRINT-PATCHES` and `SET-SYSTEM-STATUS`.
    `cold/global.lisp` still exports `LOAD-PATCHES` and
    `LOAD-AND-SAVE-PATCHES`, which is left for the cold-load cleanup.
- **LMFILE**, MIT's file computer, whose server release 1000 had already left
  out. Its pathnames go too, so no host of that kind can be defined.
  - `file2/pathnm.lisp`, the last file of `SYS: FILE2;`, with its place in
    FILE-SYSTEM's `HOST-PATHNAMES` module and in
    `REST-OF-PATHNAMES-FILE-ALIST`, the list MINI loads during `QLD`
    (`sys/sysdcl.lisp`). The note on FILE2's systems goes with it.
  - `zmail/lmfile.lisp`, ZMail's mail-file methods for LMFILE pathnames, and
    its place in ZMail's `MAIN` module.
  - `io/file/access.lisp`: the `LMFILE-HOST` flavor and its methods, the
    `:LMFILE-SERVER-HOSTS` site variable, `ADD-LMFILE-HOST` and
    `ADD-LMFILE-HOSTS`, and the call that added those hosts when the site
    was initialized.
  - `io/file/open.lisp`: `FILE-HOST-USER-ID` no longer tests for `:LMFILE`,
    which no host reported anyway.
  - `network/chaos/qfile.lisp`: opening a file tests only for
    `FS:LM-PARSING-MIXIN`, and `FILE-PRINT-PATHNAME` and
    `FILE-PRINT-DIRECTORY` no longer ask the host for `:REMOTE-HOST-NAME`,
    which only an LMFILE host answered.
  - `file/copy.lisp`: the two tests for `REMOTE-LMFILE-PATHNAME`, a flavor
    defined nowhere in the tree. No system loads this file.

  The manual's LMFILE sections (`man/pathnm.text`, `man/fd-hac.text`), a mail
  log (`man/bug-mail.txt`) and three comments in code stay as history.
- **Lambda and Explorer support** (#17). This system runs on a CADR, or on muir and
  muir-fpga, which model one; `SI:PROCESSOR-TYPE-CODE` is always 1 there. So
  every choice made on the processor type is resolved to its CADR branch, and
  code that only a Lambda ran is deleted. The variable itself stays, since
  the microcode sets it.
  - `sys/ltop.lisp`: `LISP-REINITIALIZE` no longer clears the Lambda's board
    slots or turns on its 60 Hz interrupts over the NuBus, and `QLD` no longer
    offers to load the Ethernet files; `TV::TV-QUAD-SLOT` goes.
  - `sys/qrand.lisp` (`TIME`), `sys/qmisc.lisp` (`PROB-FROCESSOR`, which puts
    `:CADR` on `*FEATURES*`), `sys/genric.lisp` (`MACHINE-TYPE`),
    `eh/eh.lisp` (`LOAD-ERROR-TABLE`), `io/dledit.lisp`, `io1/meter.lisp` and
    `network/chaos/chatst.lisp`: the CADR's branch only.
  - `sys2/proces.lisp`: `PROCESS-SCHEDULER-FOR-LAMBDA` and
    `LAMBDA-PDL-BUFFER-LENGTH`; `sys2/prodef.lisp`: `RUN-LIGHT-FOR-LAMBDA`
    and `FIXNUM-MICROSECOND-TIME-FOR-SCHEDULER-FOR-LAMBDA`;
    `sys2/setf.lisp`: the `SETF` of `%NUBUS-READ`.
  - `io/disk.lisp`: `LOAD-LMC-FILE` and `COMPARE-LMC-FILE`, which put the
    Lambda's microcode on a disk, and the Lambda's names and masks in
    `LOAD-MCR-FILE`, `SYS-COM-PAGE-NUMBER` and
    `GET-UCODE-VERSION-FROM-COMMENT`. A disk operation that did not finish
    at the address it should have is still reported: the test that the
    machine was not a Lambda, always true on a CADR, goes.
  - `window/cold.lisp`: the keyboard buffer's NuBus setup, and the Lambda's
    branches in `SET-MOUSE-MODE`, `VIRTUAL-UNIBUS-ADDRESS`, `SETUP-CPT` and
    the cold-load stream's size.
  - `window/shwarm.lisp`: the Lambda's branches in the black-on-white
    functions, the main screen's size and `SET-TV-SPEED`; and the Lambda's
    scan line table with everything that resized its screen through it:
    `SET-SCREEN-WIDTH`, `FIX-WINDOW-WIDTH`, `FIX-ARRAY`,
    `MAP-OVER-ALL-WINDOWS-OF-SHEET`, `LAMBDA-SET-HEIGHT`, `LANDSCAPE`,
    `PORTRAIT` and their who-line helpers. The "Load scan line table"
    initialization stays, and on a CADR it still only places the run lights.
  - `window/wholin.lisp`, `window/mouse.lisp`, `window/color.lisp` and
    `zwei/poss.lisp`: the CADR's branch only.
  - `io1/time.lisp`: the Lambda's battery clock, read and set through the
    SDU over the NuBus, with its CMOS layout, its configuration reader and
    its place in `INITIALIZE-TIMEBASE`; and the Lambda's branches of
    `MICROSECOND-TIME` and `FIXNUM-MICROSECOND-TIME`. `io1/timpar.lisp`
    loses the Lambda's override of that clock.
  - `network/chaos/chsncp.lisp`: the Lambda's `:ETHERNET` route in
    `TRANSMIT-INT-PKT`, which sent Chaos packets through the `ETHERNET`
    package's 3Com driver or to other processors sharing the NuBus through
    the `UNIX` package; the Lambda's way of finding its address from the
    disk label; and its branches in the routing table, the interface resets
    and `STATUS`. Nothing outside the cold-load lists names `ETHERNET` or
    `UNIX` any more.
  - The cold-load lists and packages: the ETHERNET system,
    `LAMBDA-COLD-LOAD-FILE-LIST`, `ETHERNET-FILE-ALIST` and its place in
    `MINI-FILE-ALIST-LIST`, and the commented-out `ETHER-MINI` in
    `sys/sysdcl.lisp`; the ETHERNET, UNIX and PRESS packages in
    `sys/clpack.lisp`; `MAKE-COLD`'s `LAMBDA-P` argument in
    `cold/coldut.lisp`; the Ethernet register offsets in `cold/qcom.lisp`,
    which no microcode or Lisp code used. `cold/export.lisp` no longer
    exports the PRESS package's symbols or the PUP and EFTP ones in CHAOS,
    and its notes for `DEFINE-SPECIAL-VARIABLE`, `PRINT-FILE`, `PRINT-STATUS`
    and `PRINT-STREAM` name the files that use them rather than
    `SYS: IO1; PRESS`. The A-memory and system communication area slots the
    Lambda and the Ethernet used stay, because their positions are shared
    with the microcode.

## Faults fixed

- **`window/wholin.lisp`:** the who line showed NIL for a running process,
  whose wait whostate is NIL; it shows the run whostate then. The fix is
  LM-3's, marked for 1001 in `docs/upstream-changes.md`.

## Around the system
