# The cross build and the native rebuild

`tools/cross-build/run` makes the first band of a system whose layout the
previous system cannot build natively, and checks the route: the previous
system's band cross-builds it (contract G2, section 7; for revision 14,
contract G3 revision 14, 10.6), the band the cross build gives compiles its
own system, and that band compiles it once more. It is the route
`docs/building.md` describes under "Cross-building for the 40-bit QUUX",
"Loading the 40-bit cold load" and "The native rebuild", run as one tool from
one source tree, with G2 section 7's checks (a)-(d) and the guards of
appendix A14.13.

```
tools/cross-build/run --out run/<dir> --builder <disk> --builder-ubin <ubin> \
    --base-tree <tree.tar.gz> --quux <quux> --ozd <ozd> --ports <lo>-<hi> \
    [--commit <sha>] [--asm-band <disk> --asm-ubin <ubin> --asm-quux <quux> \
    --asm-revision 0] [--ubin-ref <ubin>] [--from STEP] [--to STEP]
tools/cross-build/run --list
```

Every option can also come from the environment as `CROSS_BUILD_` and the
option's name (`CROSS_BUILD_BUILDER`). No path is written in the tool.

| Option | What it is |
|---|---|
| `--out` | a git-ignored directory: `record.txt`, each step's logs and results, `bands/` |
| `--work` | scratch, a few GB: trees, disks, lispm-check's checkpoints (default `$XDG_CACHE_HOME/cross-build/<out's name>`) |
| `--commit` | the sources, by `git archive`; without it, this tree's tracked and untracked files as they are, the `git status` recorded |
| `--builder` | the previous system's disk, raw or VHD, its band current: for revision 14, System 2001's hand-over disk |
| `--builder-ubin` | that band's `sys/ubin/` (its `UCADR TBL`) |
| `--builder-prom`, `--builder-revision` | the builder's PROM (default quux's own) and revision (13) |
| `--base-tree` | the builder's own tree with its QFASLs, a tarball (`tools/cross-check`'s `--base-tree`) |
| `--asm-band`, `--asm-ubin`, `--asm-quux`, `--asm-revision` | the band that assembles the microcode and PROM, and its quux (default the builder) |
| `--ubin-ref` | a `sys/ubin/` the assembled `.mcr`, `.tbl` and `.locs` must equal |
| `--quux` | muir-sim's `quux` with the new revision (14) and the file device |
| `--ozd` | ozd, the TELNET gateway of every lispm-check run |
| `--ports` | at least 64 ports: lispm-check takes four a run from the range, the QLD and guard runs one each from its top 16 |

## The steps

| Step | What it does |
|---|---|
| `export` | the sources into the work directory, with `sys/ubin/` empty; `export/manifest.txt` has every file's sha256 |
| `assemble` | UCADR twice and PROMH once, at revision 14, version 2002, three lispm-check runs at once; the two UCADRs must be equal byte for byte (`.sym` too), and the result equal to `--ubin-ref` when given |
| `cross` | the export's own `tools/cross-check/run --fresh check3 check2` (check 3: the cold load's files compiled for the target, the readtables, MAKE-COLD; check 2: SYSTEM compiled for the target), and `cases/site.cases` and `cases/wormch.cases` (the site's QFASLs and `SYS: DEMO; WORMCH QFASL`, made in cross sessions), at once on the builder. Check 3 must pass; check 2's compile must pass and its logs show no host value (`check2.py`); its comparison with the builder's QFASLs (`compare.py`) is recorded |
| `target` | the target's tree: check 2's, with check 3's compiles laid over it, the site's and WORMCH's QFASLs, and the assembled `sys/ubin/` |
| `band4` | G2 section 7's step 4: a disk with the microcode in MCR1 and check 3's cold load in LOD3, current; quux at revision 14, 32 M words, the target's tree on the file device; `lisp/coldrun.lisp` runs QLD, reports register-page word 224 and the paging counters, and saves into LOD4; the save is waited for until LOD4 holds a band of format 2010 that stays the same for 60 s. `bands/band4.img` is that band on a fresh disk, current in LOD1, with the microcode in MCR1 |
| `native5` | step 5: band4 compiles the system from the export (`cases/native-compile.cases`: SYSDCL, the ALLDEFS files, the site, the readtables, WORMCH, `MAKE-SYSTEM` with `:RECOMPILE`), MAKE-COLD in a fresh boot (`cases/native-cold.cases`), and the cold load is booted, run through QLD and saved as in `band4`: `bands/native5.img` |
| `native6` | step 6: the same from native5's band: `bands/native6.img`, the band to hand over |
| `checks` | (a) `tools/cross-check/same40.py --floats --sources` on the target's QFASLs and step 5's; (b) the cold-load generator both ways, byte for byte: step 5's band on the target's QFASLs gives check 3's cold load (`cases/native-cold.cases`), and the builder's cross build on step 5's QFASLs gives step 5's (`cases/cross-cold.cases`); and step 6's cold load against step 5's with `tools/cold-compare` (G2 section 7 (b), as amended on 2 October 2026); (c) the comparisons' planted controls, `tools/cross-check/plant_a.py` and `tools/cold-compare-test`; (d) `same40.py` on step 5's QFASLs and step 6's |
| `high` | the high band (contract G3 revision 14, 10.11): native6's band booted read-write, the region floor set one quantum below 2^31, `SI:FULL-GC`, which copies every object of the dynamic areas into regions at or above the floor (`lisp/high.lisp` checks that one region lies across 2^31 and that no region of a dynamic area that holds an object lies below the floor), `DISK-SAVE` into LOD2; `bands/high.img`, booted again, must keep the floor and the region |
| `incremental` | an incremental save and restore with an ephemeral region, on native6's band and the high band: a young array of 100,000 words filled, another process consing in an area of its own all through the save, `DISK-SAVE` incremental into LOD2 (format 2011); LOD2 booted with its base and the array compared |
| `guards` | `guards.py`: each line of appendix A14.13 booted and shown to halt where it names, each with a control that does not |

A step that fails stops the run, and the record's last line says why.
`--from STEP` continues a run whose record shows every earlier step passed.

Measured for revision 14 (micro): the assembly 6 minutes, check 2 about two
and a half hours, QLD about 15 minutes, a native compile about two hours.
Run it detached (`setsid nohup ... &`).

## What it needs on the host

`git`, `qemu-img` (a VHD builder disk), `sgdisk` (the GPT's attribute bit 48
and names), `fallocate` and `dd`.
