# System 1001

What System 1001 changes from System 1000. Its theme is a deep cleanup:
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
  - With no use left, the macros that chose by processor go:
    `SELECT-PROCESSOR`, `IF-IN-CADR`, `IF-IN-LAMBDA`,
    `IF-IN-CADR-ELSE-LAMBDA` and `IF-IN-LAMBDA-ELSE-CADR`, with their
    processor properties (`sys2/lmmac.lisp`), their exports
    (`cold/global.lisp`, `cold/export.lisp`) and their `MAY-SURROUND-DEFUN`
    properties, which two never-defined `IF-FOR-` names also had
    (`io/read.lisp`). So do `LAMBDA-TYPE-CODE` and `EXPLORER-TYPE-CODE`
    (`window/cold.lisp`, `cold/system.lisp`). `CADR-TYPE-CODE` stays, to
    say what `SI:PROCESSOR-TYPE-CODE` holds.
  - The microcode (`ucadr/uc-arith.lisp`, `uc-array.lisp`,
    `uc-call-return.lisp`, `uc-parameters.lisp`, `uc-stack-closure.lisp`,
    `uc-storage-allocation.lisp`, `uc-transporter.lisp`, `uc-tv.lisp`): each
    `#+CADR` loses its conditional, each `#+LAMBDA` form goes, the
    `#-CADR (BEGIN-COMMENT)` and `(END-COMMENT)` pairs go and leave their
    contents, and the five `#-LAMBDA (BEGIN-COMMENT)` blocks go whole: the
    Lambda's micro-stack bits, `M-LAM` and `A-LAM` with the `MACRO-IR`
    fields, the two CXR dispatch tables, and four `ILLOP` entries in
    `D-ND2`. This is what the assembler read on a CADR, so no instruction,
    symbol or order changes, and `ucadr.mcr` should assemble byte for byte
    as before.
  - The 28 `DEFMIC`s of instructions the CADR's microcode never implemented
    go from `cold/defmic.lisp`: the Lambda's Multibus (732-737), NuBus,
    microsecond clock and I/O space (761-767) instructions, and 1100-1116
    (micro-paging, the multiplication tests, disk transfer, board slots).
    Their exports in `cold/global.lisp`, their commented documentation in
    `cold/docmic.lisp` and the `SETF` of `%IO-SPACE-READ` in `sys2/setf.lisp`
    go with them. Each opcode is written out, so no other instruction moves,
    and the opcodes are free for its own.
  - Kept: `MULTIBUS-VIRTUAL-ADDRESS` in `cold/qcom.lisp`, which nothing uses,
    and the A-memory and communication-area slots named above, whose
    positions the microcode shares.

- **`file/copy.lisp`**, bulk directory copying with tape-mounting hooks. It
  was a module only of the MagTape system, so nothing loaded it once that
  went; `COPY-FILE` itself is `io/file/open.lisp`'s.

- **Host operating systems this system will never talk to:** it talks to exactly
  two kinds of file host, UNIX (the `ozd` file server) and LISPM (the
  local file system), plus logical hosts. Multics, VMS, TOPS-20, Tenex and
  ITS support are gone, smallest first:
  - **Multics:** `MULTICS-PATHNAME-MIXIN` and the `MULTICS-PATHNAME` flavor
    (`io/file/pathst.lisp`), `HOST-MULTICS-MIXIN` (`network/host.lisp`),
    `FILE-HOST-MULTICS-MIXIN` and `MULTICS-HOST` (`io/file/access.lisp`),
    and the Multics finger parser (`network/chaos/chsaux.lisp`). The
    Multics-only password-guessing special case in `GUESS-PASSWORD-MAYBE`
    (`io/file/access.lisp`) goes too, now dead code for a host type that
    can no longer exist.
  - **VMS:** `VMS-PATHNAME-MIXIN` and the `VMS-PATHNAME` flavor
    (`io/file/pathst.lisp`), `HOST-VMS-MIXIN` (`network/host.lisp`),
    `FILE-HOST-VMS-MIXIN` and `VMS-HOST` (`io/file/access.lisp`), the VMS
    finger parser (`network/chaos/chsaux.lisp`), the dead `:VMS`
    surface-type clauses in the canonical-type tables
    (`io/file/pathnm.lisp`, ZMail's `zmail/comnds.lisp`), and ZMail's VMS
    mail-file format: `VMS-MAIL-FILE-MIXIN`, `VMS-MAIL-FILE-BUFFER`,
    `VMS-INBOX-BUFFER` and the `FS:VMS-PATHNAME-MIXIN` methods that offered
    and detected it (`zmail/mfhost.lisp`, `zmail/cometh.lisp`). Unlike
    ITS's, nothing else used the VMS mail format, so it goes whole.
  - **TOPS-20, Tenex and Twenex:** `TENEX-FAMILY-PATHNAME-MIXIN` (the
    shared base of TOPS-20, Tenex and VMS pathnames), `TOPS20-PATHNAME-MIXIN`
    and `TENEX-PATHNAME-MIXIN` (`io/file/pathst.lisp`); `HOST-TOPS20-MIXIN`
    and `HOST-TENEX-MIXIN` (`network/host.lisp`); `FILE-HOST-TOPS20-MIXIN`,
    `FILE-HOST-TENEX-MIXIN`, `TOPS20-HOST` and `TENEX-HOST`
    (`io/file/access.lisp`); the Twenex finger parser
    `PARSE-TWENEX-FINGER` (`network/chaos/chsaux.lisp`;
    `PARSE-TENEX-FINGER` is a different, still-used parser, for `:TOPS-10`,
    which this system keeps); the dead `(:TOPS-20 :TENEX)` surface-type clauses
    (`io/file/pathnm.lisp`); and ZMail's Tenex/TOPS-20 mail format
    (`TENEX-MAIL-FILE-MIXIN` and friends, and the
    `FS:TENEX-FAMILY-PATHNAME-MIXIN`/`FS:TOPS20-PATHNAME-MIXIN`/
    `FS:TENEX-PATHNAME-MIXIN`/`SI:HOST-TOPS20-MIXIN` methods that offered
    and detected it, in `zmail/mfhost.lisp` and `zmail/cometh.lisp`).
    `DEFAULT-DIRECTORY-PATHNAME-AS-FILE` stays in `pathst.lisp`: it is
    generic, and `UNIX-PATHNAME-MIXIN` uses it too. ZMail's `zmail/mail.lisp`
    loses a dead `MEMQ` against the same two host-type keywords.
  - **ITS,** the last: `ITS-PATHNAME-MIXIN` and the `ITS-PATHNAME` flavor
    (`io/file/pathst.lisp`), `HOST-ITS-MIXIN` (`network/host.lisp`),
    `FILE-HOST-ITS-MIXIN` and `ITS-HOST` (`io/file/access.lisp`), the ITS
    finger parser `PARSE-ITS-FINGER` (`network/chaos/chsaux.lisp`), the
    dead `:ITS` surface-type clauses (`io/file/pathnm.lisp`, ZMail's
    `zmail/comnds.lisp`), the dead `:ITS` device clause in the LPT hardcopy
    stream (`io1/hardcopy.lisp`), and the ITS-specific branches in
    `DETERMINE-USER-ID-AND-PASSWORD` (`io/file/access.lisp`) and
    `FILE-HOST-USER-ID`/`UNAME-ON-HOST` (`io/file/open.lisp`), which asked
    for or recorded one uname shared by all ITS hosts.
    `ITS-FN1-STRING`, `STRING-OR-WILD`, `QUOTE-COMPONENT-STRING`,
    `NUMERIC-P` and `*ITS-UNINTERESTING-TYPES*` stay in `pathst.lisp`
    despite their names: they are generic pathname-string helpers with
    callers outside the old ITS support, chiefly `io/file/logical.lisp`'s
    `LOGICAL-NAME-STRING` (literally `ITS-FN1-STRING`) and ZWEI's
    `FILE-LOADED-TRUENAME` (`zwei/zmacs.lisp`), which reads
    `*ITS-UNINTERESTING-TYPES*`. `ITS-DEVICE-STRING`, `ITS-FN2-STRING` and
    `SIX-SIXBIT-CHARACTERS` had no such callers and go.
  - **The ZMail mail-file trap:** `RMAIL-FILE-BUFFER` and
    `BABYL-MAIL-FILE-BUFFER` inherit `ITS-MAIL-FILE-MIXIN`
    (`zmail/mfhost.lisp`), which is a mail *format*, not host support, and
    has no required flavor on the pathname or host system. It stays
    unchanged, along with `PARSE-ITS-MSG-HEADERS`, `OUTPUT-ITS-HEADER` and
    the other ITS-format mail-header code in `zmail/mail.lisp`. Only the
    methods that offered and detected the format on the pathname and host
    flavors themselves (`FS:ITS-PATHNAME-MIXIN`'s
    `:MAIL-FILE-FORMAT-COMPUTER` and friends, `SI:HOST-ITS-MIXIN`'s
    `:GMSGS-PATHNAME`) go, since those flavors are gone. This is the
    smaller, safer of the two ways to resolve the trap, and keeps ZMail
    working unchanged for RMAIL and BABYL files on UNIX and LISPM hosts.
  - **Left as comments, not code, because a host-type keyword still names
    something else:** ZMail's mail-header-format code (`:ITS` as a header
    tag in `zmail/mail.lisp` and a `*LOCAL-MAIL-HEADER-FORCE*` menu choice
    in `zmail/defs.lisp`), a fallback uname lookup keyed on the bare symbol
    `ITS` in `FILE-HOST-LISPM-MIXIN` (`io/file/access.lisp:827`, kept
    because it is a harmless alist key, never populated once ITS support
    is gone), and doc-comment examples naming `:ITS`
    (`network/host.lisp:27,176`, `io/file/pathnm.lisp:62,632`).
  - **Not touched, reported instead:** `cold/export.lisp` still exports
    `SI::HOST-ITS-MIXIN`, `SI::HOST-MULTICS-MIXIN`, `SI::HOST-TENEX-MIXIN`,
    `SI::HOST-TOPS20-MIXIN`, `SI::HOST-VMS-MIXIN` and
    `FS::*ITS-UNINTERESTING-TYPES*` (the last is still a real export, since
    the variable stays); left for the cold-load cleanup, as with the
    similarly dangling patch-machinery exports above.
    `window/supdup.lisp:969` tests a host's `:SYSTEM-TYPE` against
    `(:MULTICS :WAITS)` to decide whether SUPDUP needs character
    identification; that is the SUPDUP terminal protocol talking to a
    remote host as a terminal, not the file-host system this cleanup
    covers, so it is left for its own decision. `io1/timpar.lisp`'s
    `PARSE-TWENEX-TIME` and `file/lmpars.lisp`'s
    `*LMFS-USE-TWENEX-SYNTAX*` are generic date-format and local-syntax
    helpers named for Twenex, not Twenex host support, and `file/` is
    this system's own local file system, out of scope for this cleanup; both are
    left. `sys/sys/clpack.lisp` defines no package for any of these five
    systems, so there was nothing to remove there.
- **`sys/fspec.lisp`**, 689 lines of which every one was inside a single `#|`
  block, so the file defined nothing (#11). It was a half-finished move of the
  function-spec machinery out of `sys/qrand.lisp` and `sys/qmisc.lisp`, which
  MIT abandoned and System 100 switched off; the note at its head records the
  barf it caused in `INTERNAL-FUNCTION-SPEC-HANDLER` while `QLD` loaded
  `sys2/defsel.lisp`. All 38 forms in the block have live twins in `qrand` or
  `qmisc`, save `FUNCTION-SPEC-REMPROP`, which no caller has. The cold load
  carried the empty file, so `sys/sysdcl.lisp` loses it from
  `COLD-LOAD-FILE-LIST` and from SYSTEM-INTERNALS' MAIN module, and the notes
  in `qrand`, `qmisc` and `io/file/open.lisp` that pointed at it say instead
  where the machinery lives.

- **The demos that need hardware this system does not have** (the user, 2026-09-18):
  `demo/ctest.lisp`, the wire-wrap board tester, with the driver it calls,
  `io1/cdrive.lisp`, and that driver's notes, `io1/wlr.doc`; and
  `demo/votrax.lisp` with its word list `demo/words.lisp`, which drive a
  Votrax speech synthesizer. No system loaded any of them: the HACKS system
  names neither, and nothing else in the tree calls them. The other demos
  stay.

- **Six names `cold/export.lisp` exported with nothing to define them:** the
  five host mixins for ITS, TOPS-20, Tenex, VMS and Multics, whose flavors
  went with those hosts, and `FUNCTION-SPEC-REMPROP`, which only ever existed
  inside the block comment that was `sys/fspec.lisp`.

## Faults fixed

- **Function-spec properties are read back again.** In
  `sys/qrand.lisp`'s `FUNCTION-SPEC-DEFAULT-HANDLER`, the `GET` clause had a
  second form after its `IF`, so the clause always returned the default and
  discarded the lookup: no property of a function spec that is not a symbol,
  such as which file a method came from, could be read. The default now sits
  inside the loop, as MIT wrote it in the unfinished `SYS; FSPEC` this release
  deletes.
- **A cold load can be driven without a console** (#18). `cold/mini.lisp`
  gains `MINI-RUN-SCRIPT`: before the cold load reaches its listener
  (`sys/ltop.lisp`), it asks the file server for `SYS: COLD; COLDRUN LISP` and
  evaluates the forms in it, so a build can type `(SI:QLD)` and the save
  without a screen. If the server has no such file the open is refused and the
  cold load goes to its listener exactly as before. Progress is reported by
  asking for names such as `SYS: COLD; COLDRUN-REPORT; form-2`, which the server logs,
  since MINI cannot send data; `MINI-OPEN-FILE` grew a `NO-BARF` argument for
  both. Anything that goes wrong still appears on the console, which a cold
  load has no error handler to catch.

- **The error handler's stack-group plist works again** (#16). Three places in
  `eh/eh.lisp` and `eh/ehc.lisp` were switched off by the bring-up with
  ">>ERROR; No way known to do LOCF on SG-PLIST": saving and restoring a stack
  group's property list around a resume, and re-entering single-instruction
  stepping when a foothold resumes. The cause was the package, not LOCF: EH
  inherits the other `SG-` accessors from SYSTEM, which `cold/system.lisp`
  lists, but not `SG-PLIST`, so the name read there as `EH:SG-PLIST`, which
  nothing defines. Named `SI:SG-PLIST` it expands through `ARRAY-LEADER`,
  compiles without a warning, and the error handler runs with it.

- **The error handler's backtrace prints the closure bit again.** The
  bring-up left one line of `eh/ehc.lisp`'s long backtrace off, asking
  whether `RP-ATTENTION` was a renaming of `RP-DOWNWARD-CLOSURE-PUSHED`.
  There is no `RP-ATTENTION` in this tree: `sys2/sgdefs.lisp` defines
  `RP-DOWNWARD-CLOSURE-PUSHED` over the bit the line wants, so it prints
  under that name. With this, no `;;;---!!!` note is left anywhere in the
  tree.
- **The last bring-up note outside the error handler is answered** (#13).
  `sys/qrand.lisp`'s table of null elements per array type had two entries
  commented out with "MAKE-COLD doesn't support complex types". The reason is
  narrower than the note: the entries' values would be complex literals, and
  QRAND is read while a cold load is built, before the reader can make a
  complex number. `ARRAY-TYPE-NULL-ELEMENT` has no caller in the tree and an
  absent entry gives NIL, so the note is replaced by a comment saying that,
  and the `ART-COMPLEX` entry, whose value is 0, stays.

- **`window/wholin.lisp`:** the who line showed NIL for a running process,
  whose wait whostate is NIL; it shows the run whostate then. The fix is
  LM-3's, marked for 1001 in `docs/upstream-changes.md`.
- **`io/stream.lisp`:** an ASCII-translating stream, such as a TELNET
  session's, sent a Return character object as octal 215 instead of CR LF,
  so FORMAT's `~%` broke no line. The translation compares the character's
  code now, so character objects and fixnums translate alike (#1).
- **`network/chaos/chsaux.lisp`:** a TELNET session whose first input was
  Return died in the error handler. The server skipped TELNET negotiation by
  reading a character and pushing it back, and the stream cannot push back
  the Return that CR LF becomes. The TELNET and EVAL servers peek at the
  next byte instead (#2).
- **`io/stream.lisp`:** after a CR not followed by LF, an ASCII-translating
  stream lost the next two bytes, because it sent `:UNTYI` to the
  continuation of its `:TYI` methods, which read again, rather than to the
  stream. It pushes the byte back onto the stream now, and a CR at end of
  file no longer signals (#2).
- **`io/stream.lisp`:** `:LINE-IN` trapped with too many arguments on the
  Chaos ASCII streams, because the default `:READ-CHAR` it sends took no
  arguments. That method takes EOF-ERROR-P and EOF-VALUE now, as the other
  `:READ-CHAR` methods do (#4).
- **`io/stream.lisp`:** an ASCII-translating stream did not claim `:BEEP`,
  so over TELNET a question asked with FQUERY signalled as soon as it had to
  ask again. These streams ring the terminal's bell with BEL now (#5).

- **The site is MIT, not Z54,** and its hosts are numbered from the subnet's
  first address: OZ is 177200 and LISPM-*n* is 177200+*n*, so LISPM-1 is
  177201. Release 1000 was re-released with the same change.

## Around the system
