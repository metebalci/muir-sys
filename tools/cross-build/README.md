# The cross build and the native rebuild

`tools/cross-build/run` makes the first band of a system whose layout the
previous system cannot build natively, and checks the route: the previous
system's band cross-builds it (contract G2, section 7; for revision 14,
contract G3 revision 14, 10.6), the band the cross build gives compiles its
own system, and that band compiles it once more. It is the route
`docs/building.md` describes under "Cross-building for the 40-bit QUUX",
"Loading the 40-bit cold load" and "The native rebuild", run as one tool from
one source tree, with G2 section 7's checks (a)-(d) and the guards of
appendix A15b.1 (A14.13's for a revision-14 assembly).

**The generational collector (contract G3 step 2 revision 1, 9.3, 9.4).**
Its microcode refuses revision 14's bands, so its first band comes the same
way: System 2002's revision-14 hand-over band is the builder
(`--builder-revision 14`, `--builder-prom` its PROM 2002, `--base-tree` its
tree), check 3 writes step 2's cold load (format 2022, with first-object
tables, `sys/cold/coldut.lisp`'s `TARGET-HAS-GENERATIONS-P`), and the bands
built are format 2020. COLDRUN tenures every young object before each save
it makes (band4, native5, native6), and the step `built` records the young
words and checks the RQBs. The guards add C27's lines and boot revision 13's
pieces from `--previous-band` and `--previous-ubin` (System 2001's). The
microcode may be assembled on the builder or, as for revision 14, on System
2000's band (`--asm-band`, `--asm-ubin`, `--asm-quux` and `--asm-revision
0`): since a 40-bit target's `.mcr` writes its microcode symbol area without
the assembling world's fixnum tag (`sys/sys/qwmcr.lisp`,
`WRITE-MICRO-CODE-SYMBOL-AREA-PART-2`), both give the same files; before, a
32-bit world's tag in `<29:25>` made those 1024 words differ.

```
tools/cross-build/run --out run/<dir> --builder <disk> --builder-ubin <ubin> \
    --base-tree <tree.tar.gz> --quux <quux> --ozd <ozd> --ports <lo>-<hi> \
    [--builder-revision 14 --builder-prom <promh.mcr> --asm-revision 14] \
    [--previous-band <disk> --previous-ubin <ubin>] \
    [--commit <sha>] [--asm-band <disk> --asm-ubin <ubin> --asm-quux <quux> \
    --asm-revision 0 --asm-prom <promh.mcr>] [--ubin-ref <ubin>] [--from STEP] [--to STEP]
tools/cross-build/run --list
```

Every option can also come from the environment as `CROSS_BUILD_` and the
option's name (`CROSS_BUILD_BUILDER`). No path is written in the tool.

**The revisions** (QUUX's Ethernet contract, section 8 R2): the route's
machine runs at revision 16 (`MACHINE_REVISION`), which has the Ethernet
device: band4's, native5's and native6's QLD, every lispm-check run on a band
the route made, and the sessions of `high` and `incremental`. The microcode
and PROM are assembled for revision 15 (`ASM_TARGET`, unless `--asm-target`
says another), since there is no assembly target for 16 and revision 16 runs
15's `.mcr` files. The builder runs at `--builder-revision`, its own band's,
and assembles at `--asm-revision`. Before, revision 14 was both the route's
machine and its target. `--quux` must therefore run revision 16, and a
pool of taps must be installed (muir-sim's `tools/quux-taps`).

The network follows the revision each run's machine runs: lispm-check's
default, and for the sessions its helper `harness_network`
(`docs/lispm-check.md`, "The network"). The route's runs, at revision 16,
each take a tap of `LISPM_CHECK_TAPS` and go over TCP, with no ozd, unless
`LISPM_CHECK_NETWORK` says `chaos`; the builder's, at its revision 13-15, go
over Chaos through `--ozd`. `tools/microcode-check/generational-save` and
the soak's harnesses take this tool's sessions too, at the revision their
`--quux` wrapper sets.

A save gives no answer over either network, a refused one neither: over
Chaos the connection closes, and over TCP the band's network stops as the
save begins, so the connection goes silent. The save is judged by its
partition alone, and a refused one fails as "no band saved", after 30
minutes; over TCP the silence is waited for 120 s before the partition is
watched, rather than 600.

| Option | What it is |
|---|---|
| `--out` | a git-ignored directory: `record.txt`, each step's logs and results, `bands/` |
| `--work` | scratch, a few GB: trees, disks, lispm-check's checkpoints (default `$XDG_CACHE_HOME/cross-build/<out's name>`) |
| `--commit` | the sources, by `git archive`; without it, this tree's tracked and untracked files as they are, the `git status` recorded |
| `--builder` | the previous system's disk, raw or VHD, its band current: System 2002's revision-14 hand-over disk (before the generational collector, System 2001's) |
| `--builder-ubin` | that band's `sys/ubin/` (its `UCADR TBL`) |
| `--builder-prom`, `--builder-revision` | the builder's PROM (default quux's own) and revision (13) |
| `--base-tree` | the builder's own tree with its QFASLs, a tarball (`tools/cross-check`'s `--base-tree`) |
| `--asm-band`, `--asm-ubin`, `--asm-quux`, `--asm-revision`, `--asm-prom` | the band that assembles the microcode and PROM, its quux and PROM (default the builder, with the builder's PROM) |
| `--asm-target` | the hardware revision the microcode and PROM are assembled for (`ua:*hardware-revision*`; default 15, `ASM_TARGET`; 14 before the route's machine moved to 16). At 15 the `.mcr` files are revision 15's self-describing format (contract G3 revision 15, 7) |
| `--oa-select-check` | `refuse` (the default) or `report`: with `report` a revision-15 assembly that the OA select check would refuse is written all the same, and each assembly's case output gives the breaches by rule and the words rule 1 refuses; for measuring microcode that has no selects yet, never for a build |
| `--previous-band`, `--previous-ubin` | revision 13's disk and `sys/ubin/` (System 2001's), for the guards' revision-13 lines |
| `--ubin-ref` | a `sys/ubin/` the assembled `.mcr`, `.tbl` and `.locs` must equal |
| `--quux` | muir-sim's `quux` with revision 16 (the route's machine) and the file device; it runs the builder at its revision too |
| `--ozd` | ozd, the TELNET gateway of the runs over Chaos |
| `--ports` | at least 64 ports: lispm-check takes four a run from the range, the QLD and guard runs one each from its top 16 |

## The steps

| Step | What it does |
|---|---|
| `export` | the sources into the work directory, with `sys/ubin/` empty; `export/manifest.txt` has every file's sha256 |
| `assemble` | UCADR twice and PROMH once, for revision 15 (`--asm-target`), version 2002, on the assembling band at `--asm-revision`, three lispm-check runs at once; the two UCADRs must be equal byte for byte (`.sym` too), and the result equal to `--ubin-ref` when given |
| `cross` | the export's own `tools/cross-check/run --fresh check3 check2` (check 3: the cold load's files compiled for the target, the readtables, MAKE-COLD; check 2: SYSTEM compiled for the target), and `cases/site.cases` and `cases/wormch.cases` (the site's QFASLs and `SYS: DEMO; WORMCH QFASL`, made in cross sessions), at once on the builder. Check 3 must pass; check 2's compile must pass and its logs show no host value (`check2.py`); its comparison with the builder's QFASLs (`compare.py`) is recorded |
| `target` | the target's tree: check 2's, with check 3's compiles laid over it, the site's and WORMCH's QFASLs, and the assembled `sys/ubin/` |
| `band4` | G2 section 7's step 4: a disk with the microcode in MCR1 and check 3's cold load in LOD3, current; quux at revision 16, 32 M words, the target's tree on the file device, no `--ethernet-socket`; `lisp/coldrun.lisp` counts `MAPATOMS-NR-SYM`'s visits in `NR-SYM` before QLD (the review of the first-object table, P6), runs QLD, reports register-page word 224 and the paging counters, tenures every young object (a young flip with the tenure-all table, reclaimed; the young words by generation reported before and after) and saves into LOD4; the save is waited for until LOD4 holds a band of format 2020 (2010 before the generational collector) that stays the same for 60 s. `bands/band4.img` is that band on a fresh disk, current in LOD1, with the microcode in MCR1 |
| `native5` | step 5: band4 compiles the system from the export (`cases/native-compile.cases`: SYSDCL, the ALLDEFS files, the site, the readtables, WORMCH, `MAKE-SYSTEM` with `:RECOMPILE`), MAKE-COLD in a fresh boot (`cases/native-cold.cases`), and the cold load is booted, run through QLD and saved as in `band4`: `bands/native5.img` |
| `native6` | step 6: the same from native5's band: `bands/native6.img`, the band to hand over |
| `checks` | (a) `tools/cross-check/same40.py --floats --sources` on the target's QFASLs and step 5's; (b) the cold-load generator both ways, byte for byte: step 5's band on the target's QFASLs gives check 3's cold load (`cases/native-cold.cases`), and the builder's cross build on step 5's QFASLs gives step 5's (`cases/cross-cold.cases`); and step 6's cold load against step 5's with `tools/cold-compare` (G2 section 7 (b), as amended on 2 October 2026); (c) the comparisons' planted controls, `tools/cross-check/plant_a.py` and `tools/cold-compare-test`; (d) `same40.py` on step 5's QFASLs and step 6's |
| `high` | the high band (contract G3 revision 14, 10.11): native6's band booted read-write, the region floor set one quantum below 2^31, `SI:FULL-GC`, which copies every object of the dynamic areas into regions at or above the floor (`lisp/high.lisp` checks that one region lies across 2^31 and that no region of a dynamic area that holds an object lies below the floor), `DISK-SAVE` into LOD2; `bands/high.img`, booted again, must keep the floor and the region |
| `incremental` | an incremental save and restore with an ephemeral region, on native6's band and the high band: a young array of 30,000 words (below the pretenuring threshold) filled in an ephemeral area, another process consing in an area of its own all through the save, `DISK-SAVE` incremental into LOD2 (format 2021); LOD2 booted with its base and the array compared, young; its address is recorded, since the save's young collection moves it |
| `guards` | `guards.py`, chosen by the assembled `ucadr.mcr`: for revision 15's, the default, appendix A15b.1's (contract G3 revision 15b): quux refuses PROM 2002 for revision 15 on revisions 14 and 13 and the old PROMs on 15, naming format and revision; a revision-14 disk on 15 halts at `ERROR-MCR-FORMAT`, the route's disk on 14 at `ERROR-MICROCODE-NOT-REVISION-14` and on 13 at `ERROR-BAD-SECTION-TYPE`, its microcode with section 6 saying 14 at `ERROR-MICROCODE-NOT-REVISION-15`; C27's band formats under the route's microcode on 15 and under revision 14's on 14; the route's disk runs on revision 16; a checkpoint of 14 refused on 15 and of 15 on 14. For revision 14's microcode, appendix A14.13's and C27's lines (below the route's machine's revision 16, which refuses revision 14's PROM, so a route at `--asm-target 14` no longer gets that far). Each booted and shown to halt where it names, each with a control that does not |
| `built` | C29 and P7 (contract G3 step 2 revision 1, 9.4; the review of the first-object table): check 3's cold load run through QLD and saved once more without the tenure-all (`bands/band4-untenured.img`); in it and in band4, native5, native6 and high (`cases/built.cases`, `lisp/built.lisp`) every RQB of the RQB resource and `PAGE-RQB` on page boundaries and `DISK-BUFFER-AREA`'s first-object tables passing the table checker; its filler words and the young words by generation recorded |

A step that fails stops the run, and the record's last line says why.
`--from STEP` continues a run whose record shows every earlier step passed.

Measured for revision 14 (micro): the assembly 6 minutes, check 2 about two
and a half hours, QLD about 15 minutes, a native compile about two hours;
the whole route at revision 16, target 15, took about 9 h 20 min on micro
(`docs/building.md`, "Building a band on QUUX"). Run it detached
(`setsid nohup ... &`).

`test` checks the revisions and the networks of the route's and the
builder's runs, dry, with a stand-in quux and ozd (its head gives the
usage).

## What it needs on the host

`git`, `qemu-img` (a VHD builder disk), `sgdisk` (the GPT's attribute bit 48
and names), `fallocate` and `dd`.
