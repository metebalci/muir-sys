# The micro-assembler's checks for revision 14

Cases that check what the micro-assembler (`sys/sys/cadrlp.lisp`,
`sys/sys/cadsym.lisp`, `sys/sys/qwmcr.lisp`) does for QUUX's revision 14,
`ua:*hardware-revision*` 14 (`docs/building.md`, "Assembling the microcode").
Each check assembles UCADR from a copy of this tree, planted as the check says,
on a band through `tools/lispm-check`, and the runner then reads what the
assembler wrote.

```
tools/assembler-check/run --ref UBIN                    # every check, at once
tools/assembler-check/run --ref UBIN rev13 pinned       # some of them
tools/assembler-check/run --ref UBIN rev14 -- --engine rtl
```

`UBIN` holds the outputs the tree's microcode must assemble to at revision
13, `ucadr.mcr`, `.sym`, `.tbl` and `.locs`: for this tree, the release's
`sys/ubin/`. Arguments after `--` go to every lispm-check run. Each check takes
16 ports from `--ports N` on (47300 by default) and writes
`run/assembler-check/CHECK/` (git-ignored; `--out DIR` for another place):
`cases.cases`, `lispm-check.out`, the outputs it read, and `result.txt`,
ending `CHECK PASS` or `CHECK FAIL`. An assembly takes about six minutes on
the micro engine; run the checks detached (`setsid nohup ... &`). The exit
status is 0 when every check given passes.

lispm-check's band, `ubin/`, quux and ozd are this tree's defaults
(`run/check/band.img` beside `run/check/ubin/`, `../muir-sim` and `../ozd`),
since the copies are not where those defaults are found; `LISPM_CHECK_BAND`
and the others choose others. The band is System 2000's, whose builder loads
the micro-assembler from the copy with `make-system`.

| Check | Assembles | Passes when |
|---|---|---|
| `rev13` | the microcode at revision 13 | the four outputs equal `UBIN`'s byte for byte: nothing changes for a revision-13 build |
| `rev14` | the microcode at revision 14 | it assembles (the three checks below pass on it); the `.mcr`'s first section is section 6, start 0, one word, 14, and there is no other; every other section, and the symbol area, equals `UBIN`'s, the main-memory section's relative disk block aside; the `.sym`, `.tbl` and `.locs` equal `UBIN`'s |
| `bits` | `lisp/y1bits.lisp`, a few words in revision 14's names, with `ua:assemble` | at revision 13 the assembly is refused ("revision 14"); at revision 14 each word has appendix A14's bits as muir-sim's revision 14 decodes them: condition 12's jumps, calls and returns (`IR<5>` 1, `IR<4:0>` 12, `IR<6>` the inverse), the write-map operations' constants in `VMA<33:32>` (0 none, 1 direct write, 2 invalidate, 3 empty), the operation and entry fields, `pointer-type-register-0-31` and `-32-63` (register-page words 222 and 223) as the bits of A14.5's 19 types numbered by the tree's `Q-DATA-TYPES`, and section 6 |
| `pinned` | the microcode at revision 14 with a variable inserted before `A-PDL-BUFFER-VIRTUAL-ADDRESS` | the assembly is refused, naming `A-PDL-BUFFER-VIRTUAL-ADDRESS` (appendix A14.7) |
| `map-table` | the microcode at revision 14 with `D-TRANSPORT`'s entry for `FIX`, map bit 1, made unlike its map-bit-0 entry | the assembly is refused, naming `FIX`, a type outside the pointer-type register's set (A14.5) |
| `map-set` | the microcode at revision 14 with `ua:*pointer-types*` missing `DTP-NULL` | the assembly is refused, naming `NULL`, which `D-TRANSPORT` tells apart (A14.5) |
| `map-constant` | the microcode at revision 14 with `pointer-type-register-0-31` given another value than `ua:*pointer-types*`'s bits | the assembly is refused, naming `POINTER-TYPE-REGISTER-0-31` (A14.9) |
| `lc-shift` | the microcode at revision 14 with a word writing the location counter through the right shift | the assembly is refused (A14.11) |
| `lc-mm` | the microcode at revision 14 with a word writing the location counter by `M+M` | the assembly is refused (A14.11) |

`rev13` and `rev14` are the controls for the five planted checks: the same
assembly, unplanted, is not refused.
