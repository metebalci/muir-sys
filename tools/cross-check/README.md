# The cross build's checks

The cross build (`sys/cold/cross.lisp`; `docs/building.md`, "Cross-building
for the 40-bit QUUX") compiles SYSTEM on System 2000's band for the 40-bit
machine and writes that machine's cold load. These are its checks, and the
controls that show each check can fail. They run on a builder band through
`tools/lispm-check`, and read what the builder wrote on the host.

```
tools/cross-check/run all                 # checks 1 and 3 and the native control, at once
tools/cross-check/run check1              # one of them
tools/cross-check/run check2              # SYSTEM compiled for the target: about two hours
tools/cross-check/run check1 -- --quux PATH   # arguments after -- go to lispm-check
```

Run it detached (`setsid nohup ... &`), since `all` takes about half an hour
and `check2` about two hours and twenty minutes. The exit status is 0 when
every check given passes. Each check writes `run/cross-check/CHECK/` (git-ignored):

| File | What it is |
|---|---|
| `result.txt` | the analysis, ending `CHECK PASS` or `CHECK FAIL` |
| `lispm-check.out` | lispm-check's output: one line per case |
| `cases.cases` | the cases the builder ran: `cases/prime.cases` and the check's own |
| `manifest.txt` | the sha256 of the cross build's sources the run used |
| `home/` | what the run left in HOST's home: QFASLs, logs, tables, images |
| `served/` | the run's served `sys/`, with the QFASLs it made (checks 3 and 2) |
| `*.log` | the machine's, ozd's and the TELNET session's logs |

## What it needs

- The builder band: lispm-check's default, `run/check/band.img` (System
  2000's, `docs/lispm-check.md`, Defaults), with its `ubin/`, quux and ozd.
  Since each check serves a copy of the tree, the driver passes these defaults
  of this tree to lispm-check (`LISPM_CHECK_BAND` and the others, set unless
  already set); `LISPM_CHECK_PORTS` gives the port range.
- For check 3, the native control and check 2: System 2000's tree with its
  QFASLs, muir-sim's `ref/band-2000/tree-2000.tar.gz` beside this tree
  (`--tree-2000` or `CROSS_CHECK_TREE_2000` for another). It is unpacked once
  into `run/cross-check/tree-2000/`.
- The builder is primed as `docs/building.md` says: `cases/prime.cases`
  compiles and loads the compiler files the cross build changes, `SYSDCL`, the
  cold-load generator and `SYS: COLD; CROSS`, with their QFASLs in HOST's
  home. Every check but the native control starts with it.

The files of `lisp/` are served to the builder as `SYS: CROSS-CHECK;`
(`sys/cross-check/` of the check's copy of the tree), never in the tree itself.

## Check 1: every family at every point

`cases/check1.cases`, `check1.py`. The compiler meets this world's values only
where it evaluates while it compiles: a fold, `#.`, an interpreted macro, an
`EVAL-WHEN (COMPILE)` and a `COMPILER-LET`. `lisp/family.lisp` has, for each
family of system constants (word fields, data types, cdr codes, the page, the
fixnum, arrays, characters, floats, the FEF, headers, the disk, virtual
addresses), a function at each of the five points. It is compiled:

- **for a synthetic target** (`lisp/synth.lisp` over `SYS: COLD; TARGET40`),
  which gives every family a value that is neither this world's nor the 40-bit
  machine's: each of the 13 constants at each point must show the synthetic
  value in the decoded QFASL, and not this world's;
- **for the 40-bit machine**: the constants that change (the word's fields,
  the page, the fixnum's limits) must show the target's value;
- **with this world's own parameters** (the identity control): the tree's
  `QCOM`, which describes the 40-bit machine, with every parameter this world
  also has given this world's value, and so every system constant the tree's
  other files define, such as `SINGLE-FLOAT-EXPONENT-OFFSET`
  (`lisp/world.lisp`). The QFASL must equal
  the native compile's function for function, but for `XC-LSH`, since a
  cross build folds no `LSH`;
- **for a 32-bit target of 1024-word pages** (contract G2, option (w)):
  this world's parameters with that page (`lisp/world.lisp`, then
  `lisp/pages32.lisp`). Its files name no word width, so
  `cold:cross-foreign-file-p` tells them by the page. `FAMILY` is compiled for it beside its source and
  loaded, and the load must be replaced by this world's compile of the
  source (one replaced load); `SYS: FONTS; CPTFON`, which has no source, is
  not foreign.

And the controls and encodings:

- **The guards**: `cross-begin` refuses a target whose data types
  or FEF, FASL and character formats are not this world's.
- **Fail-closed**: an uncovered `#.` (`lisp/uncovered-sharp.lisp`) and an
  uncovered fold (`lisp/uncovered-fold.lisp`) each stop their file, and no
  QFASL is written.
- **The compiler's encodings** in the 40-bit file:
  - a closure's slots are marked with bit 31, not bit 24;
  - floats are IEEE singles, and the cases check IEEE 754's rounding at its
    edges and back;
  - integers up to 2^31 are kept;
  - floats keep their encodings after the builder loads the tree's
    `SYS2; NUMDEF`, as `cross-begin` does (the encoder reads the
    builder's floats from their bits, not through `INTEGER-DECODE-FLOAT`,
    which that file redefines for IEEE singles);
  - a character is its field's bits, unsigned: a mouse character, bit 24 set,
    is 16777248 in the 40-bit file, not this world's negative field;
  - `LSH` is left unfolded and `ASH` folded;
  - the file carries the mark `:WORD-WIDTH 40`, and a 32-bit file none.
- **The planted fold** (`lisp/planted.lisp`) holds 1048576 and 32.
- **The tree's definitions** (`lisp/defs.lisp`), compiled for the 40-bit
  machine: `%SHORT-FLOAT-EXPONENT`, a defsubst of `SYS2; NUMDEF`, is
  open-coded with the tree's byte, `#o2710`, not System 2000's, `#o2110`; and
  the macro `FIXNUM-READ-METER-FOR-SCHEDULER` pushes the target's byte,
  `#o37`, not the builder's, `#o30`; and what the compiler decides by the
  target's values (a table constant folded, `LSH` and `ROT` folded on the
  target's fixnum, `SMALL-FLOAT` folded and a float prototype taken as the
  target's single), its floats (short literals, a listed defsubst's float,
  two literals of one target float as one constant, a long literal read
  exactly, as the tree's reader reads it, and `1.570796326` and
  `1.5707963185` as one constant, `(sqrt 2)` after
  `NUMDEF` was met), and `lisp/shortfloat.lisp`, whose short float of the
  builder stops it. A copy of the tree with these fixes undone fails each.
- **The fail-closed check of the definitions**: with `NUMDEF`'s definitions
  left out (`:definitions '(:omit "SYS: SYS2; NUMDEF")`) but still checked,
  the compile of `SYS: SYS; QFASL` stops, and no QFASL is written.

## The tree's definitions

A file compiled for the target expands a macro, or open-codes a defsubst, with
the definition in force where it is compiled, which in the builder is System
2000's unless the compile is given the tree's. `crossdefs.py TREE BASE --lisp
sys/cold/crossdefs.lisp` lists every compile-time definition of the tree
(`DEFMACRO`, `DEFSUBST`, `DEFSETF`, `DEFINE-SETF-METHOD`, `DEFSTRUCT`,
`DEFF-MACRO` and the like, at top level or inside `EVAL-WHEN` and `PROGN`) whose
text is not System 2000's (BASE: muir-sim's `ref/band-2000/tree-2000.tar.gz`
unpacked): new, changed, or gone; and every macro or defsubst of System 2000's
text that holds a float literal (`:floats`), which the builder read with its
own floats. The text is compared as tokens, comments
dropped, case folded outside strings, and a file that does not parse into whole
forms stops the script. `cold:cross-begin` reads each listed definition from
its file and evaluates it as the compiler does inside a file it compiles, which
declares it and defines nothing; every compile for the target starts with
those declarations, and the builder's own definitions do not change. A listed
name that expands without such a declaration stops the file.

Before a check that cross-builds, `run` checks with `--check` that
`sys/cold/crossdefs.lisp` is what the sources give, and runs `--census`: no
`#,` may sit inside a compile-time definition, since `#,` puts in the value of
the world that reads it, the builder's; it also lists the new or changed
constants (`--table` the cross table: those whose form reads a constant the
target changes). A copy of the tree with `PRODEF`'s old macro, which used
`#,(1- %%Q-POINTER)`, is listed and fails.

## Check 3: the 40-bit cold load

`cases/check3.cases`, `check3.py`, `plant3.py`. The files of
`SI:COLD-LOAD-FILE-LIST` are compiled for the target, and so are the
readtables. The cold load's font is written again for the target
(`cold:cross-redump-value-file`; the tree's is a 32-bit file). `MAKE-COLD`
writes partition `LOD3`, and the band is opened read-only, so the writes stay
in the run. The partition's pages are then copied to `home/cold40.img`.
`check3.py` reads the image on the host as the target would (5-byte words,
1024-word pages):

- the system communication area is on page 1;
- `REGION-ORIGIN` is where it points;
- NIL and T sit where `RESIDENT-SYMBOL-AREA`'s origin says, with their
  headers, print names, value, function, property and package cells, and at
  the words `MAKE-COLD` reported;
- the band format is 2002, and the pointer width 32.

Also run on this check:

- `plant3.py`: two planted faults, each of which `check3.py` must fail on;
- `check2.py`: the fold log of this compile;
- `compare.py`: these QFASLs against System 2000's.

## The native control

`cases/native.cases`. On System 2000's own tree and QFASLs, the cold load made
by this tree's cold-load generator must be byte for byte the one System 2000's
generator makes. This tree's generator is served as `SYS: CROSS-CHECK;
COLDUT-NEW` and `COLDLD-NEW`. `check3.py` must pass on that image (256-word
pages), and on the generator's cold load at 1024-word pages of 32-bit words,
4 blocks a page (`lisp/pages32.lisp`), whose band format is 1102.

## Check 2: SYSTEM compiled for the target

`cases/check2.cases`, `check2.py`, `compare.py`; `tools/cross-check/run check2`.
It takes about two hours and twenty minutes on the micro engine.

- `SYSDCL` and SYSTEM's definition files are compiled for the target, then
  `MAKE-SYSTEM` through `cold:cross-compile-system`. Then the controls: the
  planted fold, and an uncovered `#.`, which must stop its file.
- Each file compiled leaves a log in HOST's home, `x1-cross-NNNN.txt` (`cold:cross-write-log`).
  The log holds every read of a watched symbol at an interpreted point, with
  its target and builder values, every fold, every `#.`, every miss and every
  `LSH` or `ROT` left to the target. The table is `x1-cross-table.txt`, and the
  compiler's output is `x1-cross-compile.txt`.
- `check2.py` checks the logs:
  - no miss;
  - every read gives the table's value;
  - every fold and `#.` that names a constant that changes is evaluated again
    on the host, with the target's values and with this world's, and the
    logged value must be the target's.
- `compare.py` compares the target QFASLs with System 2000's native ones,
  function by function: every function that differs must be explained (a
  constant that changes, a float, an `LSH` left to the target, closure
  slots, generated names, a `#.` value). This previews contract G2 section
  7's check (a).
- The check keeps its copy of the tree (`run/cross-check/check2/tree/`), with
  the QFASLs each part made. So if the machine stops, `run check2` again goes
  on where it stopped, in `part2/`, and the analysis reads every part; use
  `--fresh` to start again.
- `--system NAME` compiles another system (`file-system`, say) by the same
  steps, for a shorter run.

## A compiler file alone

`sys/sys/qcopt.lisp`, `qcp1.lisp` and `qcfasd.lisp` read `*cross-target*`,
`target-value` and `target-word-width`, which `sys/sys/qcdefs.lisp` defines. A
band built from this tree has `qcdefs` loaded before them, but to patch one of
them alone into a band built before the cross build (System 2000's), give
`qcdefs` first: `tools/lispm-check --files
sys/sys/qcdefs.lisp,sys/sys/qcopt.lisp ...`. Without it, a constant fold in
the patched band signals that `*CROSS-TARGET*` is unbound, and with `qcfasd`
alone every `QC-FILE` fails.

## Comparing two builds of the 40-bit machine: `same40.py`

`same40.py [--floats] [--sources] TREE-A TREE-B` decodes each QFASL of one
tree's `sys/` and `site/` with its counterpart in the other (`qfasl.py`) and
compares them word by word, with the attribute list's compile data (time,
version, user, machine, site) dropped and its order ignored, and generated
symbols' numbers, `EXPR-SXHASH` values, in a FEF's local map the numbers
that end `GENTEMP`'s names (a counter of the session), and in the file's
record of the macros it expanded the hashes of their definitions normalised; every FEF's words and
instructions, every array and every evaluation must be equal, floats by their
binary32 bits. With `--floats` a float may differ from its counterpart by one
unit in the last place, as the cross build's literals, rounded through the
builder's floats, may; each such float is listed (`FLOAT` lines), and every
other word of its item must still be equal. With `--sources` a file whose
source differs between the trees is listed apart (`SOURCE`). Contract G2
section 7 uses it for check (a), the cross build's QFASLs against the native
rebuild's, and check (d), two native rebuilds'.

`plant_a.py TREE` is its control (G2 section 7, check (c)): on a copy of one
QFASL of TREE at a time it plants, for each rule, a change the rule must
report and one it must not: an instruction of a function that holds a float
(also `HASH-TABLE-MAXIMAL-FULLNESS`'s), a float one and two units in the last
place apart, the compile time, a generated symbol's number and the same symbol
made a plain one, an `EXPR-SXHASH` value and a fixnum beside it, a
`GENTEMP` name's number in a local map and the same name's stem, and a
definition's hash in the macros-expanded record.