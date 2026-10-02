# The microcode's checks

Cases that check the microcode assembled from `sys/ucadr/`, run on a band
through `tools/lispm-check`. Each check is a case file, `cases/NAME.cases`,
with the Lisp it needs first, if any, in `lisp/NAME.lisp`.

```
tools/microcode-check/run -- --band PACK --ubin UBIN              # every check
tools/microcode-check/run pdl-refill -- --band PACK --ubin UBIN   # one of them
tools/microcode-check/run pdl-refill -- --band PACK --ubin UBIN --engine rtl
```

`fixpack-flag.py` is a static check of the sources, with no band: every jump to
`FIXPACK-T` or `FIXPACK-P`, which test the fixnum overflow flag that every ALU
word loads, must have as its flag word (the jump's next word when it is
`-XCT-NEXT`, else the word before it) the arithmetic word that made `M-1`, or a
logical word, whose flag is 0; a call, a page-fault check, a dispatch, a byte
word or another register's sum between them breaks the rule. Exit status 0
when no site breaks it.

Arguments after `--` go to every lispm-check run. The machine runs the
microcode in the disk's MCR1, not the one in `ubin/`, so the disk must carry
the microcode under test: write `sys/ubin/ucadr.mcr` over MCR1, which starts
at block 17 (`dd if=ucadr.mcr of=DISK bs=1024 seek=17 conv=notrunc`), serve
the same `ubin/`, whose `ucadr.tbl` the cold boot reads, and give `quux` the
matching boot PROM (`--prom`, through a `--quux` wrapper; `docs/building.md`,
"A band of 1024-word pages for revision 12"). lispm-check's default band,
`run/check/band.img`, runs microcode 2000. The exit status is 0 when every
check passes.

| Check | What it checks |
|---|---|
| `range-checks` | The array bounds checks are unsigned (microcode 2001; contract G2 appendix A1.3): `(aref a -1)` and `(aset x a -1)` signal `SUBSCRIPT-OUT-OF-BOUNDS` on general, string, 8-bit and 2-dimensional arrays and write nothing, `array-in-bounds-p` says NIL at -1, `array-push` with a negative fill pointer stores nothing, and `copy-array-portion` with a negative start stores nothing below the array. An index one past the end is the control. |
| `address-past-28-bits` | A reference to an address with `<31:28>` set signals `ADDRESS-PAST-28-BITS` with the address (microcode 2001, `ADDRESS-PAST-28-BITS` in `sys/ucadr/uc-page-fault.lisp`; `sys/eh/ehf.lisp`), by `%P-CONTENTS-OFFSET`, `%P-STORE-CONTENTS`, `%P-LDB` and `%P-CONTENTS-AS-LOCATIVE` of a word of all ones, and the machine goes on. A band built before `ehf.lisp` gained the error needs `--compile --files sys/eh/ehf.lisp`. A reference inside the space is the control; microcode that halts answers none after it. |
| `write-a-memory` | `%WRITE-INTERNAL-PROCESSOR-MEMORIES` and `COMPILER:MA-LOAD-A-MEM` write an A memory location's 40 bits, its tag from `D-HI`'s bits 15:8 (`XWIPM`, `sys/ucadr/uc-cadr.lisp`), read back through A memory's window; location 1777 is restored after. The first case, the location's `<31:0>`, is the control; microcode that writes 32 bits fails the other two. |
| `fixnum-boundaries` | Fixnum arithmetic at the 32-bit boundaries with no sign extension (microcode 2001; contract G2 sections 2.2 and 6.1): `+`, `-`, `*`, `1+`, `1-` and `ASH` at 2147483647 and -2147483648 and their overflow into bignums, the comparisons, `=` and `EQL` on negative fixnums, the one-argument functions, the logical functions, `LDB`, `DPB`, the divisions, a bignum with a negative fixnum operand and characters, interpreted and compiled. Each goes through the type dispatches `D-NUMARG`, `D-NUMARG1` or `D-FIXNUM-NUMARG2`, which fall through for a fixnum, or `ARITH-ANY-FIX` (`sys/ucadr/uc-arith.lisp`). It passes on microcode 2001 before the sign extension went and after. |
| `bignum-fixnum-extremes` | A bignum with -2147483648 and 2147483647 (microcode 2001): `+`, `-`, `*`, `QUOTIENT`, `REMAINDER`, `MOD`, `<`, `>`, `=`, `EQL` and `EQUAL`, then `FLOOR`, `CEILING`, `TRUNCATE`, `ROUND`, `GCD`, `LOGAND`, `LOGIOR`, `LOGXOR`, `MAX`, `MIN` and `CLI://`, the bignum first and the fixnum first, interpreted and compiled, against values computed outside the machine. -2^31's magnitude, 2^31, is not a 32-bit fixnum, so `BFXSUB` and `BFXMPY-OK` (`sys/ucadr/uc-arith.lisp`), which negate the fixnum, take it apart. Microcode without that fails the first three cases, `(- (expt 2 40) most-negative-fixnum)`, `(- (expt 2 31) most-negative-fixnum)` and `(* (expt 2 40) most-negative-fixnum)`, and `(- b f)`, `(* b f)` and `(* f b)` with -2^31 and the remainders made from them. |
| `full-gc` | `SI:GC-IMMEDIATELY` and `SI:FULL-GC` complete (microcode 2001: the page hash table's first words keep their fixnum tag through the selective deposits of `PGF-AG`, `AGER2`, `AGER4` and `XCPGS3`), and a sample of the other checks passes after them. |
| `gcd-setz` | `GCD` of -2^31, the most negative 32-bit fixnum (`GCD-FIX-FIX`, `sys/ucadr/uc-arith.lisp`): with 0 or itself it is the bignum 2^31, and with anything else the gcd of 2^30 and it. `(gcd 12 18)` is the control. |
| `typed-a` | A memory that Lisp reads as a fixnum stays one (microcode 2001; contract G2 section 2.2, an arithmetic result takes M's tag): `ARRAY-PUSH`'s fill pointer (`XFARY-1`, `sys/ucadr/uc-array.lisp`) and `%REGION-CONS-ALARM` and `%PAGE-CONS-ALARM` (`MAKE-REGION`, `uc-storage-allocation.lisp`) after a new region. A fill pointer read before any push is the control. The metering counters (`uc-meter.lisp`) are fixed the same way but not checked, since metering is off. |
| `setz` | +2^31 as a bignum is two 31-bit digits (microcode 2001): negating it, multiplying it by -1, and -2^31's remainder and quotient by it give fixnums (`BIGNUM-MINUS`, `FXBMPY`, `REMAINDER-FIX-BIG`, `FXBIDIV`, `sys/ucadr/uc-arith.lisp`), so the literal -2147483648 reads as the fixnum. -2^31 made by subtraction is the control. |
| `floats` | Floats are IEEE singles (microcode 2001; contract G1 sections 2.3, 2.4): the contract's `(+ 1.0 2.0)`, the rounding of 0.1 and `(float 16777217)`, ties to even, an infinity past the largest single, subnormal operands, 32-bit fixnums and bignums to and from floats, `ART-FLOAT` one word an element, and the Lisp float accessors, limits and `SQRT`. Bits are compared through `%POINTER`. |
| `instance-get` | `GET`, `GETL` and `GET-LOCATION-OR-NIL` of an instance send it the message: `PLGET` marks an instance in the cdr code, `<39:38>` at 40 bits (`uc-fctns.lisp`). A symbol's property is the control. |
| `numbers` | The 40-bit word's numbers (contract G1 section 2.4): 32-bit fixnums near +-2^31 and their overflow into bignums, `ART-32B`, string and 8-bit array words (tag 005), characters, negative subscripts, and a cold-load bignum against a computed one (digits tag 000). Cases marked "fails on 2000" fail on System 2000's band. |
| `pdl-refill` | The PDL buffer refill brings a one-q-forward back into the buffer as it was written (`sys/ucadr/uc-page-fault.lisp`, `PB-TRANS`). An interpreted special binding's slot is still the forward, ending its frame, after a process switch, and a `SETQ` after the switch reaches the variable. The first case, with no switch, is the control. Microcode that follows the forward fails the other three. |
| `zero-length-region` | Freeing a region of no length leaves the regions around it alone (`sys/ucadr/uc-storage-allocation.lisp`, `FREE-REGION` and `UPDATE-REGION-PHT`). It frees the region of no length the cold load gives `FASL-TEMP-AREA`, as a full GC does, and checks that the region whose first quantum holds its origin still has that quantum in the address space map, that the page below the origin is still in the page hash table, and that `ROOM` still finds every region's area. The first two cases check that the band has such a region. Microcode without the fix answers `(NIL T NIL)` in the third case and fails `ROOM` with "The argument AREA was NIL", or halts at `GET-MAP-BITS`'s "Region not found". |
