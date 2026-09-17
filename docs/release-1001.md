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

## Faults fixed

## Around the system
