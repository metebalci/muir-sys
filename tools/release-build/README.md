# The release builder

`tools/release-build/run` builds a release of this system from one commit
and checks it, as `docs/building.md` describes ("Building System 1003's
release" and "Publishing a release", step 1): everything up to the assets in
a directory, their sums and scan, and the checks; nothing is tagged,
uploaded or published.

```
tools/release-build/run --system 1003 --microcode 1001 --commit <sha> \
    --builder release-1002-pack.img --builder-sha256 <its SHA-256> \
    --builder-ubin <release-1002's sys/ubin/> \
    --muir-sim <muir-sim checkout>@<commit> --ozd <ozd checkout>@<commit> \
    --ports <lo>-<hi> --out run/<dir> [--body <body.md>] [--tag-msg <msg>]
tools/release-build/run --list                     # the steps
tools/release-build/run ... --from gates           # continue a run
tools/release-build/test                           # its parts' tests
```

Every option can also come from the environment, `RELEASE_BUILD_` and the
option's name (`RELEASE_BUILD_BUILDER_SHA256`); `run --help` and the head of
`run` say what each one is. No path is written in the tool: the builder band,
muir-sim, ozd, the output and the work directory are all given. The work
directory, by default `$XDG_CACHE_HOME/release-build/<system>-<commit>`,
holds the trees, the packs and lispm-check's caches (a few GB); `--out`, a
gitignored directory, holds the record, the logs and `dist/`.

## The steps

| Step | What it does |
|---|---|
| `inputs` | Resolves the commit; checks the builder pack's SHA-256, that every port of `--ports` is free and the disks' room; builds muir-sim's `cadr` and `diskpack` and ozd from a `git archive` of the commits given (or takes the executables given). |
| `export` | `git archive` of the commit, and the empty `sys/ubin/` an exported tree needs: the assembler makes no directory, and DCFU and MEMD stop without it. |
| `assemble` | UCADR twice, PROMH, DCFU and MEMD, each on the builder band freshly booted (lispm-check, five at once). Fails if the second UCADR differs from the first, if `ucadr.mcr`, `.tbl` or `.locs` is not what the last digests in `docs/release-N.md` give, or if `promh.mcr`, `.tbl` or `.locs` differs from the builder release's (`promh.sym`, `dcfu.uload` and `memd.uload` hold symbols in hash order and are recorded). |
| `tree` | The build tree: a fresh export, the ten assembled files in `sys/ubin/`, `site/coldrun.lisp`. |
| `machine` | The build pack: the builder pack with the new microcode in MCR1 ("UCADR M"); LOD3 and LOD4 must be empty. |
| `compile` | Stages 1-3 over TELNET (`forms/compile.forms`). |
| `cold` | The builder rebooted, stage 4: the COLD system and `MAKE-COLD` into LOD3 (`forms/cold.forms`). |
| `qld` | Stages 5-6: LOD3 booted, QLD run by the COLDRUN script to `qld-complete` and `script-ends` in ozd's log. |
| `save` | Stage 7: `DISK-SAVE` into LOD4, until the saved band answers; the pack copied before it is booted again. Runs with `qld`. |
| `verify` | LOD4 booted and checked (`forms/verify.forms`). |
| `package` | The release pack (`release-N-pack.img`): MCR1 and LOD1 from the build, every other block zero, checked; gzipped. |
| `sources` | `release-N-sys.tar.gz`: the export plus `sys/ubin/`, every member root's, no COLDRUN; gzipped with no name or date. |
| `sums` | `tools/release-sums`, written and checked. |
| `scan` | `tools/release-scan` on `dist/` (and the body and tag message when given), and the owner, top-directory and label lines of `docs/building.md`. |
| `unpack` | The published files unpacked: the sources tarball, and the pack decompressed and checked against `SHA256SUMS`. |
| `gates` | G1-G5 of `docs/building.md`: G1 and G2 from the build's ozd log, G3 and G4 on the release pack with the build tree served, G5 the date check (four runs) on fixtures this step writes with their mtimes. |
| `boot` | The published files booted as a user would, on micro and on rtl. |
| `checks` | lispm-check on the release pack with the published sources served, five lanes at once: A the arithmetic (division and multiply paths, checked exactly on the host) and the microcode's earlier checks; B `lispm-check-test`, `system-check` and `microcode-check` at 32 boards; C the same at 60; D `microcode-check` on rtl; H the herald at 32, 33, 59 and 60 boards, with its hint to use 60 boards below 60 and not at 60. |
| `hand` | What lispm-check cannot do: a save at 60 boards and its boot; a keyboard cold boot (Control Meta Rubout); a warm boot (Control Meta Return), which keeps a variable. A warm boot after which the machine never answers is the known fault of `docs/release-1003.md` and is recorded, not failed. |
| `final` | `SHA256SUMS` checked again after every check; the artifacts recorded. |

A step that fails stops the run, and the last line names it and why.
`--from STEP` continues a run with the same arguments, from a step whose
earlier steps the record shows as done; `qld` and `save` run together,
since the cold load stays running between them.

## The record

`OUT/record.txt` has a line for each step started, passed or failed, each
gate and check, and each artifact with its size and SHA-256. `OUT/record.json`
has the arguments, the tools' commits and digests, the builder's digest and
label, and each step's figures: its times, the microcode's digests and how
they compared, the gates' verdicts, every lispm-check run's summary. The logs
are in `OUT/logs`, `OUT/ubin.sha256` lists the assembled files, and
`OUT/dist` holds the assets exactly as they are uploaded.

## Lines

The system number names the line. The CADR's steps are written (`LINES` in
`run`). QUUX's release builds on `main`, with a VHD disk, its own PROM asset
and the `quux` machine; a 2NNN number is refused until its entry is written.

## Its files

`forms/` holds what is typed over TELNET, `cases/` lispm-check's cases and
`lisp/` the Lisp they load, with `@SYSTEM@`, `@MICROCODE@` and the like filled
in from the arguments. The date check's cases are written by `run` from its
table of fixtures, `DATE_FIXTURES`, the same table the fixtures are written
from.

## The tests

`tools/release-build/test` runs each part on a small input with one fault
planted, and fails if the part does not catch it: a tree with no
`sys/ubin/`, a stale `sys/ubin/`, fixtures copied without their mtimes, one
fixture touched or missing, a second assembly differing in one byte, notes
without a digest, a sources member owned by the user, a COLDRUN in the
sources, a short `sys/ubin/`, a pack with a byte in LOD2 or in MCR1 or LOD1
changed, a cold-load file or readtable read again after the cold boot, no
`script-ends`, a loaded id an hour off or as text, a wrong quotient, a
negative GCD, a busy port. It boots no machine and takes seconds; the
pack's tests need muir-sim's `diskpack` (`RELEASE_BUILD_DISKPACK`) and are
skipped without it.
