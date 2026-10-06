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
