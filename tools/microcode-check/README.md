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
| `gcd-setz` | `GCD` of -2^31, the most negative 32-bit fixnum (`GCD-FIX-FIX`, `sys/ucadr/uc-arith.lisp`): with 0 or itself it is the bignum 2^31, and with anything else the gcd of 2^30 and it. `(gcd 12 18)` is the control. |
| `typed-a` | A memory that Lisp reads as a fixnum stays one (microcode 2001; contract G2 section 2.2, an arithmetic result takes M's tag): `ARRAY-PUSH`'s fill pointer (`XFARY-1`, `sys/ucadr/uc-array.lisp`) and `%REGION-CONS-ALARM` and `%PAGE-CONS-ALARM` (`MAKE-REGION`, `uc-storage-allocation.lisp`) after a new region. A fill pointer read before any push is the control. The metering counters (`uc-meter.lisp`) are fixed the same way but not checked, since metering is off. |
| `setz` | +2^31 as a bignum is two 31-bit digits (microcode 2001): negating it, multiplying it by -1, and -2^31's remainder and quotient by it give fixnums (`BIGNUM-MINUS`, `FXBMPY`, `REMAINDER-FIX-BIG`, `FXBIDIV`, `sys/ucadr/uc-arith.lisp`), so the literal -2147483648 reads as the fixnum. -2^31 made by subtraction is the control. |
| `floats` | Floats are IEEE singles (microcode 2001; contract G1 sections 2.3, 2.4): the contract's `(+ 1.0 2.0)`, the rounding of 0.1 and `(float 16777217)`, ties to even, an infinity past the largest single, subnormal operands, 32-bit fixnums and bignums to and from floats, `ART-FLOAT` one word an element, and the Lisp float accessors, limits and `SQRT`. Bits are compared through `%POINTER`. |
| `instance-get` | `GET`, `GETL` and `GET-LOCATION-OR-NIL` of an instance send it the message: `PLGET` marks an instance in the cdr code, `<39:38>` at 40 bits (`uc-fctns.lisp`). A symbol's property is the control. |
| `numbers` | The 40-bit word's numbers (contract G1 section 2.4): 32-bit fixnums near +-2^31 and their overflow into bignums, `ART-32B`, string and 8-bit array words (tag 005), characters, negative subscripts, and a cold-load bignum against a computed one (digits tag 000). Cases marked "fails on 2000" fail on System 2000's band. |
| `pdl-refill` | The PDL buffer refill brings a one-q-forward back into the buffer as it was written (`sys/ucadr/uc-page-fault.lisp`, `PB-TRANS`). An interpreted special binding's slot is still the forward, ending its frame, after a process switch, and a `SETQ` after the switch reaches the variable. The first case, with no switch, is the control. Microcode that follows the forward fails the other three. |
