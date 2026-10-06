# System 1004

What the CADR's next release changes from System 1003. It is in progress on
the `cadr` branch: each change is recorded here as it is made. `main` is
QUUX's system, numbered from 2000; what this branch takes from it is a bug fix,
a change that needs no QUUX hardware, or a feature Mete chose for the CADR.
Every change to a source file carries a comment in that file saying why.

- **The system number is 1004** (`sys/patch/system.patch-directory`,
  `sys/patch/system-1004.patch-directory`), now that System 1003 is released,
  so that no band built from this branch calls itself 1003.
- **`SET-MAR` and `CLEAR-MAR` reach the page holding the range's last word**
  (`map-mar-pages`, `sys/sys/qmisc.lisp:808-826`; `clear-mar`, `:838-848`;
  `set-mar`, `:860-875`). Both stepped `#o200` words from the range's first
  word and stopped past its last: on the CADR's 256-word pages, when the last
  word lay in the first 127 words of a later page, the last step could fall
  in the page before, depending on the first word modulo 128, so that page
  never got the MAR's status and a write there was not trapped. Both now
  visit each page from the first word's to the last word's once, the pages
  counted from the difference of the two pages' addresses and the address
  stepped by `%pointer-plus`; `set-mar` takes the last word's address by
  `%pointer-plus` too, a fixnum also from 2^24 up. Fixed on `main` in the
  same way. `tools/system-check`'s new check `mar-range` sets the MAR over a
  range from 28 words below a page boundary to 50 past it: System 1003 fails
  its third case (a write of the last word does not trap) and passes the
  other three, the controls; with the change all four pass.
- **`WIRE-WORDS` wires every page of its range, `WIRE-STRUCTURE` works, and
  `PAGE-OUT-WORDS` offers every page** (`wire-words`,
  `sys/io/disk.lisp:1335-1353`; `page-out-words`, `:1835-1842`). MIT's
  `wire-words` tested its end before each page, so it never wired the
  range's last page, nor any page of a range within one page; it took the
  address with `logand` and `-`, which do not take the structure itself that
  `wire-structure` (and `unwire-structure`) pass it, so `wire-structure`
  signalled "The first argument to LOGAND ... was of the wrong type" on every
  call. It now counts the pages from the first word's to the last word's and
  takes the address from the pointer field. `page-out-words` changed the
  status of the range's first page once for each page, not each page's. Fixed
  on `main` in the same way. `tools/system-check`'s new check `wire-range`
  reads each page's swap status: on System 1003 `(wire-words base+200 100)`
  wires the page at `base` only, not `base+256`; `(wire-words base 10)` and
  `(wire-words base 256)` wire nothing; `(wire-words base 750)` wires `base`
  and `base+256`, not `base+512`; `wire-structure` errs; and `(page-out-words
  base+300 600)` makes only `base+256` flushable, not `base+512` and
  `base+768`. It fails those six cases and passes the two controls; with the
  change all eight pass. Two faults fixed on `main` beside these do not arise
  on the CADR: `sys-com-page-number` and the band size reader broke from
  2^31, and every CADR address is below 2^24, the top of the 24-bit mask the
  CADR's `sys-com-page-number` applies (`sys/io/disk.lisp:1089-1095`): the
  regions stay below `virtual-memory-size`, which is capped at the page of
  `a-memory-virtual-address` (`:1246-1247`), measured 16514048 words, under
  2^24 = 16777216, on System 1003's band.
