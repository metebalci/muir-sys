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

## Faults fixed

## Around the system
