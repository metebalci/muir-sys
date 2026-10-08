# System 1004

What the CADR's next release changes from System 1003. It is in progress on
the `cadr` branch: each change is recorded here as it is made. `main` is
QUUX's system, numbered from 2000; what this branch takes from it is a bug fix,
a change that needs no QUUX hardware, or a feature Mete chose for the CADR.
Every change to a source file carries a comment in that file saying why.

- **The system number is 1004** (`sys/patch/system.patch-directory`,
  `sys/patch/system-1004.patch-directory`), now that System 1003 is released,
  so that no band built from this branch calls itself 1003. The microcode
  changes (below), and keeps the number 1001 until it is released (it
  becomes 1002 then).
- **`SET-MAR` and `CLEAR-MAR` reach the page holding the range's last word**
  (`map-mar-pages`, `sys/sys/qmisc.lisp:812-830`; `clear-mar`, `:842-852`;
  `set-mar`, `:864-879`). Both stepped `#o200` words from the range's first
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
- **After `SET-MAR`, every write into the range traps, not only the first**
  (`restore-mar-mode-from-foothold`, `sys/eh/eh.lisp:300-316`, called by
  `fh-applier`, `fh-applier-no-restart`, `fh-evaler` and
  `fh-stream-binding-evaler` when a throw leaves them, `:867`, `:880`,
  `:910`, `:956`). The error handler signals the MAR's break in the erring
  stack group through `run-sg`, which turns that stack group's MAR off while
  the handlers run (`:387`, MIT's line, marked "why??"); only
  `sg-restore-state`, on the return to the error handler, turned it back on.
  A break proceeded (the debugger's Resume, a handler returning
  `:no-action`) kept the MAR on, but one left by a throw (`condition-case`,
  an abort) left it off for good: the next write into the range did not
  trap, `mar-mode` said `NIL`, and `%MAR-LOW`, `%MAR-HIGH` and the pages'
  trap status stayed set. Neither the microcode nor `set-mar` re-arms
  anything: `PGF-MAR` (`sys/ucadr/uc-page-fault.lisp:456-470`) leaves the
  page's status as it is and takes the break by the stack group's MAR mode
  alone. The FH- functions now put back the MAR mode saved in their foothold
  as they are thrown through. `tools/system-check`'s check `mar-range` has
  three new cases: System 1003 gives `(T NIL NIL)` for two writes left by
  throws and `mar-mode`, where `(T T :WRITE)` is expected, and `(T T NIL)`
  for a proceeded break then two left by throws; the control, two proceeded
  breaks, passes on both. Its second case, a write outside the range, passed
  on System 1003 only because the MAR was off by then. `main` has the same
  code (`run-sg` and the FH- functions in `sys/eh/eh.lisp`).
- **`%POINTER-UNSIGNED` gives N + 2^25 for a negative N**
  (`sys/sys/qmisc.lisp:6-14`). MIT's added the sign bit shifted left once,
  whose value is negative (-2^25), and so gave N - 2^25: -1 gave -33554433,
  and `a-memory-virtual-address`, -263168, gave -33817600. It now subtracts
  it, as `main` does (`sys/sys/qrand.lisp` there). Its callers on this
  branch take region origins, lengths and free pointers
  (`region-origin-true-value`, `region-true-length` and
  `region-true-free-pointer`, `sys/sys/qmisc.lisp`, with `find-max-addr`,
  `estimate-dump-size`, `describe-region`, `room`, `lowest-address-in-area`,
  `peek-areas-region-display`, `gc-get-space-sizes` and
  `gc-reclaim-oldspace`), and none is affected in practice: on System 1003's
  band no region has a negative origin, and none of its 101 regions in use a
  negative length or free pointer. `tools/system-check`'s new check
  `pointer-unsigned`: System 1003 fails four cases (negative arguments) and
  passes the three controls; with the change all seven pass.
- **`%FINDCORE` returns a fixnum on the CADR, as it did**, and needs no change.
  QUUX's line found its `%FINDCORE` returning FINDCORE's bare `M-B` (data type
  0), which `PAGE-IN-WORDS` multiplied and so halted in `ILLOP`. The CADR's
  `XFINDCORE` returns `M-B` as `PHTDELX` popped it, pushed with `DTP-FIX` by
  `COREFOUND2` (`sys/ucadr/uc-page-fault.lisp`); measured on System 1003, the
  data type is `DTP-FIX` before and after the scan pointer wrapped (frame
  2493, then 487 after a 2.5 M-word array was made on 2 M words), and
  `PAGE-IN-WORDS` of four pages not in core pages them in equal to their
  blocks in the PAGE partition. `tools/microcode-check`'s new check
  `findcore-fixnum` keeps that so: on microcode whose `%FINDCORE` returns
  the number with data type 0, System 1003's band runs macrocode but never
  reaches its TELNET prompt, and the check fails.
- **`UN-CONS` backs the scavenger's pointer up to the free pointer**
  (`UN-CONS-0`, `sys/ucadr/uc-storage-allocation.lisp:1653-1659`).
  `REGION-GC-POINTER` is relative to the region's origin, as the free pointer
  is, but MIT's `UN-CONS-1` compared it with `M-E`, the given-back object's
  end as an address, larger than any offset, so it never backed the pointer
  up: when the scavenger had passed words that `UN-CONS` then gave back, its
  pointer stayed above the free pointer, past words the next object consed
  there would hold. `M-E` is now the free pointer just written, relative.
  Fixed on `main` in the same way, where from 2^31 up it also wrote an
  address into the gc pointer. On the CADR it is latent: the scavenger has
  to pass the words between a bignum's cons and its `UN-CONS`, inside one
  instruction. `tools/microcode-check`'s new check `un-cons-gc-pointer`
  plants that state, the gc pointer set above the free pointer before a
  bignum sum with no carry gives its last word back: on microcode 1001 the
  gc pointer stays 7 words above the free pointer; with the change it is
  the free pointer. Its three controls pass on both.
  - The microcode changes (still numbered 1001 until it is released): microcode
    1001 with this change, one control-store word more, so every word from
    `UN-CONS-0`'s on moves by one (`ucadr.locs`: I-memory 30436 to 30437;
    A-memory and the dispatch memory keep their size), and `ucadr.tbl`
    changes. Assembled twice, each on a freshly booted copy of System 1003's
    band, the four files were the same both times; the outputs, numbered
    1001 (sha256):
    - `ucadr.mcr` `050b095bded5fc78a52f37a27e4f04662a9077af35620e9f0af6aeea8ea168da`
    - `ucadr.tbl` `2b9b4b083d67e0b65ae1443fd9bb4db8c22f3a7c71f577a4d51257ad5dd21b88`
    - `ucadr.locs` `7ec7cb2c3d2fac11b5a1909a6b4f5ff7e59ff28afd9ad5d5e6afc9dba24db8ac`
    - `ucadr.sym` `05a829ca53eccf5779e7f5529ec6c3f79ec176823efe1ac8d944f098e34cc956`

    System 1003's band boots on it, and `tools/microcode-check` (five checks,
    22 cases) passes on micro and on rtl; `tools/lispm-check-test`,
    `tools/system-check`'s `interpreter-closure` and
    `interpreter-closure-scope`, and `mar-range` and `wire-range` with this
    change's Lisp compiled, pass on micro.
- **FORMAT forgets the clause strings it gives back**
  (`format-reclaim-clauses`, `sys/io/format.lisp:1276-1292`). The clause
  buffer, `format-clauses-array`, kept for the next call, still held each
  `~[`, `~<` or `~:[` clause's string after `return-array` gave its storage
  back, and the collector scans the buffer whole, past its fill pointer. Once
  that storage's page was brought back fresh by CONSF (`M-DONT-SWAP-IN`),
  `%FIND-STRUCTURE-HEADER`'s scan back from the pointer could meet the
  GC-FORWARD words of an object copied before it, and the machine halted in
  ILLOP (HALT-CONS, called from `XFSHS1+2`'s dispatch,
  `sys/ucadr/uc-storage-allocation.lisp:1140-1143`). The string's and the
  parameters' slots are now cleared as they are given back. Fixed on `main`
  in the same way, where it was found. `tools/system-check` gains
  `format-clauses` and `format-clauses-gc` (in the new `cases-2mw/`, for a
  machine of 2 M words, the CADR's 32 boards; `tools/system-check/run` now
  looks there for a check named and takes a case file's `; lisp: NAME.lisp`
  first line, as `main`'s does). On System 1003's band without the change,
  `format-clauses` fails three of its five cases (the buffer holds three
  returned strings, `(3 3)` where `(0 0)` is expected) and passes the two
  controls; `format-clauses-gc` passes its planting cases and halts in the
  collection case, muir reporting the stop at PC 5317, `XFSHS1+3`, on
  microcode 1001. With the change both pass, five cases each.
- **COLLAPSE-DUPLICATE-PNAMES leaves no symbol in the package it gives back**
  (`sys/sys2/gc.lisp:802-810`, run by `FULL-GC` with `:DUPLICATE-PNAMES`).
  It interns every pname in the package "GC Temporary", which makes a new
  symbol there for each first pname, moves the ones with no value,
  definition or properties into `WORTHLESS-SYMBOL-AREA`, a static area the
  collector scans, then kills the package and gives its storage back with
  `RETURN-STORAGE`. Those symbols kept the package in their package cell: on
  System 1003's band 25,116 symbols, 2 of them in `WORTHLESS-SYMBOL-AREA`.
  Once that storage was consed again, reading such a symbol's package halted
  the machine (an array consed where the package was, then `TYPEP` and
  `ARRAY-LENGTH` of the package: HALT-CONS at PC 11004, `GAHD1+6`, on
  microcode 1001). The package's symbols are now left with no package
  before it is killed. `tools/system-check` gains `collapse-pnames`; without
  the change its first case gives `(T 25116 2)` where `(T 0 0)` is
  expected, with it all four cases pass. Fixed on `main` in the same way.
- **The demo's PAINT-COM-TEXT-LEAVE forgets the string it gives back**
  (`sys/demo/npaint.lisp:947-952`). It returned the special
  `PAINT-TEXT-HOLDING-STRING`'s string with `RETURN-ARRAY` and left the
  special naming it, a pointer the collector scans to storage given back.
  The file does not load on this system (`DEFCLASS` is gone), so this is
  for the record. `tools/system-check` gains `npaint-text-leave`, which reads
  that one definition from the file: without the change the special names
  the string consed next, `(T T T)` where `(NIL NIL NIL)` is expected; with
  it both cases pass. Fixed on `main` in the same way.
- **A simple process that would wait no longer stops the scheduler**
  (`sys/sys2/proces.lisp:787-799`, `PROCESS-SCHEDULER-FOR-CADR`; MIT's).
  A simple process's function runs in the scheduler, which cannot wait, and
  `PROCESS-WAIT` there throws to `PROCESS-WAIT-IN-SCHEDULER`, whose catch was
  only around the wait functions: the throw found none, the scheduler stopped
  in the cold load stream's debugger ("Error in the scheduler"), and every
  process and the network with it. The dormant file connection GC, a simple
  process run every minute, did so on `main` when it sent a host
  `:SEND-IF-HANDLES` while the TELNET server held that flavor's method
  table, rehashing it after a flip. The scheduler now catches the throw
  around a simple process's function, and the process runs it again from its
  start a tick later (`SIMPLE-PROCESS-RETRY-P`, `:699-700`). Fixed on `main`
  in the same way, where it was found. `tools/system-check` gains
  `scheduler-simple-wait`: on System 1003's band without the change the
  scheduler stops at its second case, a simple process's `PROCESS-LOCK`
  (TRAP 1203, `THROW-TRAP`: no pending catch for
  `SI::PROCESS-WAIT-IN-SCHEDULER`), and the TELNET connection closes; with
  it all six cases pass.
- **The least positive floats print, and read back** (`print-flonum`,
  `sys/io/print.lisp:649-656`, `:692`; `scale-flonum`, `:712-730`;
  `scale-flonum-up`, `:737-741`; `xr-small-float`, `sys/io/read.lisp:1214-1228`,
  now unused; `xr-flonum-cons`, `:1263-1265`; MIT's). The printer made a
  positive float negative before scaling it, but a negative mantissa is
  normalized to [-1, -1/2), so the least positive float of each format, a
  mantissa of 1/2 at the smallest exponent (2^-128 short, 2^-1024 single),
  has no negative: printing `LEAST-POSITIVE-SHORT-FLOAT` or
  `LEAST-POSITIVE-SINGLE-FLOAT` signalled "MINUS produced a result too
  small". That float now stays positive, and `scale-flonum` takes either
  sign. Every single float below about 10^-307, `LEAST-NEGATIVE-SINGLE-FLOAT`
  among them, needed a power of ten past the table's 10^307 and signalled
  "The subscript 308 ... was out of range"; it is now scaled by 10^307 and
  then by the rest, and the reader divides the same way where it refused
  ("318 is larger than the maximum allowed exponent" for
  `5.562684648e-309`). The least positive short float printed as
  `2.93872s-39`, below it by less than half its last place, and the reader
  gave it for such a text, the short float nearest, where `SMALL-FLOAT`
  signalled. (With the exact printer and reader of the next item, the two
  least positive floats print as `2.93874s-39` and `5.562684646e-309`, and
  `float-print-least` expects those texts.) FORMAT's `~E`, which passes
  `scale-flonum` a positive float, signalled "The subscript 308" for every
  float and now prints (`(format nil "~,3E" 1.5)` is `"1.500e+0"`).
  `tools/system-check` gains `float-print-least`: without the change the
  cadr line's band and System 1001's fail eight of its 14 cases; with it all
  pass.
- **Every float prints as the fewest digits that read back as it, and
  every float's text reads back as it** (`print-flonum`,
  `sys/io/print.lisp:649-656`, `:663-678`; `flonum-digits`, `:743-828`;
  `xr-read-flonum`, `sys/io/read.lisp:1153-1163`; `xr-flonum-nearest`,
  `:1165-1212`; MIT's). The printer scaled a float outside [1e-3, 1e7) to
  [1, 10) by floating multiplication or division, which loses bits, and
  printed the scaled float's digits: 6.02e23 printed as `6.019999996e23`,
  2^-20 short as `9.5367s-7` and 1e-307 as `9.99999999e-308`, none of which
  read back as the float printed; they print as `6.02e23`, `9.5368s-7` and
  `1.0e-307`. `flonum-digits` gives the
  E format's digits exactly, in integers (Steele and White's free-format
  method, as Burger and Dybvig give it), from the float's bits, so the most
  negative float, whose magnitude is no float, needs no negation. The
  reader multiplied or divided the digits by a float power of ten, rounding
  twice, read a short float as a single one and rounded that again, and
  negated the magnitude it read: `5.56268465e-309`, the float just above
  2^-1024 printed, read back as 2^-1024, and `-8.988465674e307`, the most
  negative single float, overflowed ("* produced a result too large"), as
  did the most negative short float. `xr-flonum-nearest` rounds the text's exact
  value to the nearest float of its format, ties to an even mantissa, with
  its sign; zero and a text out of range are read as before. Floats in
  [1e-3, 1e7) print as before; FORMAT's `~E` and `~G` still take their
  digits from `scale-flonum`. `tools/system-check` gains
  `float-round-trip`, both signs, the extremes, powers of two and ten across
  the exponent range and pseudo-random floats of each format, 1853 short
  and 1201 single floats in about a minute on micro, and
  `float-round-trip-full` (`cases-full/`, run only when named), 3853 short
  and 9409 single floats in about 8. The cadr line's band with the previous
  item's printer and reader fails 7 of the first's 8 cases (346 short and
  491 single floats not coming back) and 24 of the second's 25 (738 and
  3708); with the change all pass.
- **`LEAST-NEGATIVE-SINGLE-FLOAT` and `SINGLE-FLOAT-EPSILON` have the values
  their definitions state** (`sys/sys2/numer.lisp:521-526`, `:545-552`;
  MIT's). `LEAST-NEGATIVE-SINGLE-FLOAT`, the negative float nearest zero,
  was -(3/2 * 2^-1024 + 2^-1054): `(xbyte 5 0)` set five bits of the
  mantissa's top byte where six make the mantissa -(1/2 + 2^-31); it is
  -(2^-1024 + 2^-1054). `SINGLE-FLOAT-EPSILON`, the smallest float that
  makes a difference when added to 1.0, was 2^-37 + 2^-75, which is 2^-37
  as a float, and 1.0 + 2^-37 is 1.0; a sum rounds to the nearest float,
  ties to even, so 1.0 + 2^-31 is 1.0 too, and the epsilon is 2^-31 +
  2^-61. The long and double float constants are the single float's.
  `tools/system-check` gains `float-constants`: the cadr line's band fails
  three of its 15 cases; with the change all pass.
