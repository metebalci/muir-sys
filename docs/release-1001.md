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
  lists that name these files are left for the cold-load cleanup.
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
  and UNIX packages stay for now: `cold/export.lisp` names PRESS symbols, and
  `network/chaos/chsncp.lisp` names UNIX ones.
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

  `cold/export.lisp` still names PRESS symbols, so the PRESS package stays
  until the cold-load cleanup.
- **EFTP** (`network/chaos/eftp.lisp`), the PUP file transfer that sent
  Press files to the Dover and files to and from Xerox Altos, and its module
  in the CHAOS system (`sys/sysdcl.lisp`). `cold/export.lisp` still names its
  symbols, which is harmless and left for the cold-load cleanup.
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

## Faults fixed

- **`window/wholin.lisp`:** the who line showed NIL for a running process,
  whose wait whostate is NIL; it shows the run whostate then. The fix is
  LM-3's, marked for 1001 in `docs/upstream-changes.md`.

## Around the system
