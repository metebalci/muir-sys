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
way: System 2002's revision-14 hand-over band was the builder until step 1
of the removal of revisions 13-15 (`--builder-revision 14`, `--builder-prom` its PROM 2002, `--base-tree` its
tree), check 3 writes step 2's cold load (format 2022, with first-object
tables, `sys/cold/coldut.lisp`'s `TARGET-HAS-GENERATIONS-P`), and the bands
built are format 2020. COLDRUN tenures every young object before each save
it makes (band4, native5, native6), and the step `built` records the young
words and checks the RQBs. The guards add C27's lines and boot revision 13's
pieces from `--previous-band` and `--previous-ubin` (System 2001's). The
microcode may be assembled on the builder or, as for revision 14 before step
1, on System 2000's band (`--asm-band`, `--asm-ubin`, `--asm-quux` and `--asm-revision
0`): since a 40-bit target's `.mcr` writes its microcode symbol area without
the assembling world's fixnum tag (`sys/sys/qwmcr.lisp`,
`WRITE-MICRO-CODE-SYMBOL-AREA-PART-2`), both give the same files; before, a
32-bit world's tag in `<29:25>` made those 1024 words differ.

```
tools/cross-build/run --out run/<dir> --builder <disk> --builder-ubin <ubin> \
    --base-tree <tree.tar.gz> --quux <quux> --ports <lo>-<hi> \
    --previous-band <disk> --previous-ubin <ubin> --rev14-band <disk> --rev14-ubin <ubin> \
    [--builder-prom <promh.mcr>] [--commit <sha>] \
    [--asm-band <disk> --asm-ubin <ubin> --asm-prom <promh.mcr>] \
    [--ubin-ref <ubin>] [--from STEP] [--to STEP]
tools/cross-build/run --list
```

**The builder on revision 16** (the removal of revisions 13-15, step 1):
the builder and the band that assembles run at the route's revision, 16,
over TCP, as the route's own bands do. The builder is a band of an earlier
route, its native6, with that route's `sys/ubin/` as `--builder-ubin`; its
PROM is that ubin's `promh.mcr` unless `--builder-prom` names one, since
revision 16 has no built-in boot PROM. `--builder-revision`,
`--asm-revision` and `--asm-quux` went, and `--ozd` is no longer needed
(it is passed to lispm-check when given). The guards' old pieces, which the
builder supplied while it was the hand-over, are `--rev14-band` and
`--rev14-ubin` (System 2002's revision-14 hand-over's disk and
`sys/ubin/`) beside `--previous-band` and `--previous-ubin` (System 2001's);
the four are asked for before a run that includes the step `guards`.

Every option can also come from the environment as `CROSS_BUILD_` and the
option's name (`CROSS_BUILD_BUILDER`). No path is written in the tool.

**The revisions** (QUUX's Ethernet contract, section 8 R2): the route's
machine runs at revision 16 (`MACHINE_REVISION`), which has the Ethernet
device: band4's, native5's and native6's QLD, every lispm-check run on a band
the route made, and the sessions of `high` and `incremental`. The microcode
and PROM are assembled for revision 15 (`ASM_TARGET`, unless `--asm-target`
says another), since there is no assembly target for 16 and revision 16 runs
15's `.mcr` files. The builder and the assembling band run at 16 too since
step 1; they ran at `--builder-revision` and `--asm-revision`, their own
bands'. Before, revision 14 was both the route's machine and its target. `--quux` must therefore run revision 16, and a
pool of taps must be installed (muir-sim's `tools/quux-taps`).

The network follows the revision each run's machine runs: lispm-check's
default, and for the sessions its helper `harness_network`
(`docs/lispm-check.md`, "The network"). Every run, at revision 16, takes a
tap of `LISPM_CHECK_TAPS` and goes over TCP, with no ozd, unless
`LISPM_CHECK_NETWORK` says another; the builder's, at its revision 13-15,
went over Chaos through `--ozd` until step 1. `tools/microcode-check/generational-save` and
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
| `--builder` | the previous system's disk, raw or VHD, its band current: a native6 of an earlier route, which revision 16 runs (until step 1, System 2002's revision-14 hand-over, renamed; before the generational collector, System 2001's) |
| `--builder-ubin` | that band's `sys/ubin/` (its `UCADR TBL`) |
| `--builder-prom` | the builder's PROM (default `--builder-ubin`'s `promh.mcr`); `--builder-revision`, its revision, went with step 1 |
| `--base-tree` | the builder's own tree with its QFASLs, a tarball (`tools/cross-check`'s `--base-tree`) |
| `--asm-band`, `--asm-ubin`, `--asm-prom` | the band that assembles the microcode and PROM, and its PROM (default the builder, with the builder's PROM; another band's PROM defaults to its ubin's `promh.mcr`), at revision 16; `--asm-revision` and `--asm-quux` went with step 1 |
| `--asm-target` | the hardware revision the microcode and PROM are assembled for (`ua:*hardware-revision*`; default 15, `ASM_TARGET`; 14 before the route's machine moved to 16). At 15 the `.mcr` files are revision 15's self-describing format (contract G3 revision 15, 7) |
| `--oa-select-check` | `refuse` (the default) or `report`: with `report` a revision-15 assembly that the OA select check would refuse is written all the same, and each assembly's case output gives the breaches by rule and the words rule 1 refuses; for measuring microcode that has no selects yet, never for a build |
| `--previous-band`, `--previous-ubin` | revision 13's disk and `sys/ubin/` (System 2001's), for the guards: its band and PROM 2001, each given to revision 16 |
| `--rev14-band`, `--rev14-ubin` | revision 14's disk and `sys/ubin/` (System 2002's revision-14 hand-over's), for the guards: its microcode, band and PROM 2002 for revision 14, each given to revision 16 |
| `--ubin-ref` | a `sys/ubin/` the assembled `.mcr`, `.tbl` and `.locs` must equal |
| `--quux` | muir-sim's `quux` with revision 16 (the route's machine) and the file device; it runs the builder and the assembly too |
| `--ozd` | not needed: passed to lispm-check when given (it was the TELNET gateway of the builder's runs over Chaos) |
| `--ports` | at least 64 ports: lispm-check takes four a run from the range, the QLD and guard runs one each from its top 16 |

## The steps

| Step | What it does |
|---|---|
| `export` | the sources into the work directory, with `sys/ubin/` empty; `export/manifest.txt` has every file's sha256 |
| `assemble` | UCADR twice and PROMH once, for revision 15 (`--asm-target`), version 2002, on the assembling band at revision 16, three lispm-check runs at once; the two UCADRs must be equal byte for byte (`.sym` too), and the result equal to `--ubin-ref` when given |
| `cross` | the export's own `tools/cross-check/run --fresh check3 check2` (check 3: the cold load's files compiled for the target, the readtables, MAKE-COLD; check 2: SYSTEM compiled for the target), and `cases/site.cases` and `cases/wormch.cases` (the site's QFASLs and `SYS: DEMO; WORMCH QFASL`, made in cross sessions), at once on the builder. Check 3 must pass; check 2's compile must pass and its logs show no host value (`check2.py`); its comparison with the builder's QFASLs (`compare.py`) is recorded |
| `target` | the target's tree: check 2's, with check 3's compiles laid over it, the site's and WORMCH's QFASLs, and the assembled `sys/ubin/` |
| `band4` | G2 section 7's step 4: a disk with the microcode in MCR1 and check 3's cold load in LOD3, current; quux at revision 16, 32 M words, the target's tree on the file device, no `--ethernet-socket`; `lisp/coldrun.lisp` counts `MAPATOMS-NR-SYM`'s visits in `NR-SYM` before QLD (the review of the first-object table, P6), runs QLD, reports register-page word 224 and the paging counters, tenures every young object (a young flip with the tenure-all table, reclaimed; the young words by generation reported before and after) and saves into LOD4; the save is waited for until LOD4 holds a band of format 2020 (2010 before the generational collector) that stays the same for 60 s. `bands/band4.img` is that band on a fresh disk, current in LOD1, with the microcode in MCR1 |
| `native5` | step 5: band4 compiles the system from the export (`cases/native-compile.cases`: SYSDCL, the ALLDEFS files, the site, the readtables, WORMCH, `MAKE-SYSTEM` with `:RECOMPILE`), MAKE-COLD in a fresh boot (`cases/native-cold.cases`), and the cold load is booted, run through QLD and saved as in `band4`: `bands/native5.img` |
| `native6` | step 6: the same from native5's band: `bands/native6.img`, the band to hand over |
| `checks` | (a) `tools/cross-check/same40.py --floats --sources` on the target's QFASLs and step 5's; (b) the cold-load generator both ways, byte for byte: step 5's band on the target's QFASLs gives check 3's cold load (`cases/native-cold.cases`), and the builder's cross build on step 5's QFASLs gives step 5's (`cases/cross-cold.cases`); and step 6's cold load against step 5's with `tools/cold-compare` (G2 section 7 (b), as amended on 2 October 2026); (c) the comparisons' planted controls, `tools/cross-check/plant_a.py` and `tools/cold-compare-test`; (d) `same40.py` on step 5's QFASLs and step 6's |
| `high` | the high band (contract G3 revision 14, 10.11): native6's band booted read-write, the region floor set one quantum below 2^31, `SI:FULL-GC`, which copies every object of the dynamic areas into regions at or above the floor (`lisp/high.lisp` checks that one region lies across 2^31 and that no region of a dynamic area that holds an object lies below the floor), `DISK-SAVE` into LOD2; `bands/high.img`, booted again, must keep the floor and the region |
| `incremental` | an incremental save and restore with an ephemeral region, on native6's band and the high band: a young array of 30,000 words (below the pretenuring threshold) filled in an ephemeral area, another process consing in an area of its own all through the save, `DISK-SAVE` incremental into LOD2 (format 2021); LOD2 booted with its base and the array compared, young; its address is recorded, since the save's young collection moves it |
| `guards` | `guards.py`, on revision 16 (the removal of revisions 13-15, step 1): appendix A15b.1's lines that ran on revision 15, each given to revision 16, the route's machine, which must refuse it or halt where the guard says: quux refuses the old PROMs, revision 14's and 2001 (`--rev14-ubin`, `--previous-ubin`), naming the file's revision; the hand-over's revision-14 disk halts at `ERROR-MCR-FORMAT`, the route's microcode with section 6 saying 14 at `ERROR-MICROCODE-NOT-REVISION-15`; C27's band formats (the hand-over's 2010 band, it made 2011 and 2012, System 2001's band, band4 without its mark bitmap and with it a page off) under the route's microcode; the route's disk runs on revision 16. Each booted and shown to halt where it names, each with a control, the route's disk, that does not. A ucadr.mcr that is not revision 15's is refused. Before step 1 it was chosen by the assembled `ucadr.mcr` and booted revisions 13, 14 and 15 too: for revision 15's, appendix A15b.1's (contract G3 revision 15b), with quux on 14 and 13 refusing PROM 2002 for 15, the route's disk on 14 halting at `ERROR-MICROCODE-NOT-REVISION-14` and on 13 at `ERROR-BAD-SECTION-TYPE`, C27's lines under revision 14's microcode on 14, and a checkpoint of 14 refused on 15 and of 15 on 14; for revision 14's microcode, appendix A14.13's and C27's lines |
| `built` | C29 and P7 (contract G3 step 2 revision 1, 9.4; the review of the first-object table): check 3's cold load run through QLD and saved once more without the tenure-all (`bands/band4-untenured.img`); in it and in band4, native5, native6 and high (`cases/built.cases`, `lisp/built.lisp`) every RQB of the RQB resource and `PAGE-RQB` on page boundaries and `DISK-BUFFER-AREA`'s first-object tables passing the table checker; its filler words and the young words by generation recorded |

A step that fails stops the run, and the record's last line says why.
`--from STEP` continues a run whose record shows every earlier step passed.

Measured for revision 14 (micro): the assembly 6 minutes, check 2 about two
and a half hours, QLD about 15 minutes, a native compile about two hours;
the whole route at revision 16, target 15, took about 9 h 20 min on micro
(`docs/building.md`, "Building a band on QUUX"). Run it detached
(`setsid nohup ... &`).

`test` checks the revisions and the networks of the route's, the
builder's, the assembly's and the guards' runs, dry, with a stand-in quux and
ozd: every start at revision 16, and no ozd started (its head gives the
usage).

## What it needs on the host

`git`, `qemu-img` (a VHD builder disk), `sgdisk` (the GPT's attribute bit 48
and names), `fallocate` and `dd`.
