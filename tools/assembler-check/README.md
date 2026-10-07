# The micro-assembler's checks for revisions 14 and 15

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

`UBIN` holds the outputs microcode 2001 assembles to at revision 13,
`ucadr.mcr`, `.sym`, `.tbl` and `.locs`: the release's `sys/ubin/`. The
checks `rev13` and `rev14` assemble that microcode, whose sources
`--ucadr-ref SRC` names: a directory laid out as the tree, with release-2001's
`sys/ucadr/` and the two files the micro-assembler reads for the microcode's
constants, `sys/cold/qcom.lisp` and `sys/cold/defmic.lisp`
(`git archive release-2001 sys/ucadr sys/cold | tar -x -C SRC`), so that the
release's microcode is assembled with the release's constants. Revision 14's
`qcom.lisp` no longer defines the page hash table's names, and its area
numbers are two lower from `ADDRESS-SPACE-MAP` on. Without `--ucadr-ref` they
assemble the tree's own microcode, which held microcode 2001 until revision
14's microcode replaced it. The check
`tree` assembles the tree's own microcode, whatever `--ucadr-ref` says. Arguments after `--` go to every lispm-check run. Each check takes
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
| `rev13` | the microcode at revision 13 | the four outputs equal `UBIN`'s byte for byte, but for the `.mcr`'s symbol area, which equals `UBIN`'s by value (below): nothing else changes for a revision-13 build |
| `tree` | the tree's own microcode at revision 14 | it assembles (the planted checks' controls for revision 14's microcode); the `.mcr`'s first section is section 6, start 0, one word, 14, and there is no other |
| `rev14` | the microcode at revision 14 | it assembles (the three checks below pass on it); the `.mcr`'s first section is section 6, start 0, one word, 14, and there is no other; every other section equals `UBIN`'s, the main-memory section's relative disk block aside, and the symbol area equals `UBIN`'s by value (below); the `.sym`, `.tbl` and `.locs` equal `UBIN`'s |
| `bits` | `lisp/y1bits.lisp`, a few words in revision 14's names, with `ua:assemble` | at revision 13 the assembly is refused ("revision 14"); at revision 14 each word has appendix A14's bits as muir-sim's revision 14 decodes them: condition 12's jumps, calls and returns (`IR<5>` 1, `IR<4:0>` 12, `IR<6>` the inverse), the write-map operations' constants in `VMA<33:32>` (0 none, 1 direct write, 2 invalidate, 3 empty), the operation and entry fields, `pointer-type-register-0-31` and `-32-63` (register-page words 222 and 223) as the bits of A14.5's 19 types numbered by the tree's `Q-DATA-TYPES`, and section 6 |
| `pinned` | the microcode at revision 14 with a variable inserted before `A-PDL-BUFFER-VIRTUAL-ADDRESS` | the assembly is refused, naming `A-PDL-BUFFER-VIRTUAL-ADDRESS` (appendix A14.7) |
| `map-table` | the microcode at revision 14 with `D-TRANSPORT`'s entry for `FIX`, map bit 1, made unlike its map-bit-0 entry | the assembly is refused, naming `FIX`, a type outside the pointer-type register's set (A14.5) |
| `map-set` | the microcode at revision 14 with `ua:*pointer-types*` missing `DTP-NULL` | the assembly is refused, naming `NULL`, which `D-TRANSPORT` tells apart (A14.5) |
| `map-constant` | the microcode at revision 14 with `pointer-type-register-0-31` given another value than `ua:*pointer-types*`'s bits | the assembly is refused, naming `POINTER-TYPE-REGISTER-0-31` (A14.9) |
| `lc-shift` | the microcode at revision 14 with a word writing the location counter through the right shift | the assembly is refused (A14.11) |
| `fiddle` | the tree's microcode with a map-bit dispatch planted between `FORCE-WR-RDONLY`'s TLB direct write and its store | the assembly is refused, naming the fiddle (the fiddle rule: no lookup between a direct write and the reference it is for, the PDL buffer loops allowed by name; contract G3 revision 14, 9.1, and the review of the fiddles against TLB eviction) |
| `lc-mm` | the microcode at revision 14 with a word writing the location counter by `M+M` | the assembly is refused (A14.11) |
| `rev15` | the tree's microcode and `PROMH` at revision 15, with `ua:*oa-select-check-refuses*` nil (contract G3 revision 15, 7) | both assemble; each `.mcr` parses as appendix A15b.7 reads it (`parse_15`), and each of `malformed_15`'s planted files, one for every refusal A15b.7 lists, is refused; no word has an extension yet; the words the OA select check's rule 1 reports are exactly the words the file holds that write `OA-REG-LOW` or `OA-REG-HIGH` (functional destinations 16 and 17), decoded here, and rules 2 and 3 report none |
| `oa-refused` | the tree's microcode at revision 15 | the assembly is refused by the OA select check (A15b.15): the microcode has no selects yet |
| `oa-select` | `lisp/oasel.lisp`'s variants with `ua:assemble` | the OA select check's rules (A15b.15): the selects refused at revision 14; at 15 the control passes and each variant is refused by its rule (a dropped select; a select entered from words that write nothing, at a return point and at a misc entry; a write after a conditional jump, a call and a dispatch whose table mixes N, each with the select where the slot would lead; a write in a return's slot; two selects; a select on a transferring dispatch; one on a dispatch-memory write with POPJ); the hint and the PDL address field planted in the control's image (no source names them): a hint with `oa-high-select` passes, one with `oa-low-select` and the PDL field with a select are refused; the control's `.mcr` read back by the loader's reader (`read-mcr-sections`, `sys/sys2/usymld.lisp`) equals the assembled memories word for word; the control store's halves (`control-store-word-halves`) are revision 14's `<47:24>` and `<23:0>` and revision 15's `<63:32>` and `<31:0>`, refused in a world whose fixnum is narrower than a half |

**The symbol area by value.** `UBIN`, release 2001's, was assembled on
System 2000's 32-bit band, whose `.mcr` writer added that world's fixnum tag,
`DTP-FIX` in `<29:25>`, to each word of the microcode symbol area. The writer
now puts out each word's value alone for a 40-bit target, on purpose (the fix
recorded in `docs/release-2002.md`, "The microcode symbol area holds plain
addresses"). So `rev13` and `rev14` compare the symbol area word by word with
that tag stripped (`symbol_area_values`), and every other part of the `.mcr`,
and the `.tbl` and `.locs`, byte for byte as before. Each run also plants a
change in one symbol area value of the assembled file, not in its tag, and
fails unless the comparison then finds the areas differ
(`symbol_area_control`).

`oa-select`'s `control` is the control for its variants, and `rev15` for `oa-refused`: the same assembly with the check reporting.

`tree` is the control for `fiddle`; `rev13` and `rev14` are the controls for the five planted checks: the same
assembly, unplanted, is not refused.
