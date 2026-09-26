# Checking a Lisp change: `tools/lispm-check`

`tools/lispm-check` checks a change to the Lisp sources on a saved band in
seconds rather than minutes. It resumes a checkpoint of the band already booted
to its TELNET prompt, loads or compiles the changed files, and runs a file of
cases in one listener session, printing one line per case.

```
tools/lispm-check [--band PACK] [--quux PATH] [--ozd PATH] [--ubin DIR]
                  [--tree DIR] [--files a.lisp,b.lisp] [--compile]
                  [--timeout S] [--keep] CASES
```

## What it does

1. **Setup, once per band and quux build.** A checkpoint resumes only on the
   quux build that wrote it, so the tool keys it by the sha256 of the band and
   of quux. When there is none, it boots the band cold, logs in, compiles a
   small helper that runs each case, and has quux write the checkpoint at the
   prompt. This takes about 15 s, most of it the cold boot.
2. **Each check** takes four free ports of its own, starts a private ozd
   serving a copy of the tree's `sys/` and `site/` with the changed files laid
   over it, resumes the checkpoint, and loads each file (`load` of the source,
   or with `--compile`, `qc-file` and `load` of the QFASL). It then runs every
   case, stops quux and ozd, and exits.

The band is always opened read-only (`--disk-pack PACK,ro`): the writes of the
boot live in the checkpoint, so the band file never changes, and any number
of checks, at the same time too, resume one checkpoint on one band. The tree
is never written either; QFASLs land in the copy.

A file inside the tree's `sys/` is served in its own place and loaded by its
logical name, `sys/io1/time.lisp` as `SYS: IO1; TIME LISP`, so the world sees
the source file it already knows. Any other file is served in the login's
home directory. Some `sys/` files do not load as source because they use
functions only the compiler open-codes (`sys/io1/time.lisp` stops at "The
function %PUSH is undefined"): check those with `--compile`.

## Cases

One case per form; a form may run over several lines. Blank lines and lines
starting with `;` are skipped. What follows the form on its last line says
what is expected:

| Case | Passes when |
|---|---|
| `FORM` | it returns without an error |
| `FORM => TEXT` | its value, printed with `prin1`, is `TEXT` |
| `FORM =>!` | it signals an error |
| `FORM =>! TEXT` | it signals an error whose message contains `TEXT` |

The listener reads the forms: base 10 and traditional syntax, where `/`
escapes, so a slash inside a string is written twice. Values are compared
with runs of whitespace collapsed to one space. Each form runs inside a
`condition-case`, so an error is reported by its message and the next case
goes on in the same session. A form must not read from the terminal.

```
(check-selftest-square 7) => 49
(list 'a
      (check-selftest-square 3)) => (A 9)
(car 1) =>!
(check-selftest-fail 3) =>! Self-test error with 3
```

## Output and exit status

```
FILE  sys/io1/time.lisp  compiled and loaded in 29.09 s
PASS  (check-selftest-square 7)  -> 49
FAIL  (check-selftest-square 4)  -> 16, expected 17
ERROR  (check-selftest-undefined 1)  -> The function CHECK-SELFTEST-UNDEFINED is undefined.
lispm-check: 7 passed, 1 failed, 1 errors, of 9 (banner 0.31 s, all 2.81 s)
```

A `WARN` line shows each line the compiler printed about a file. The status
is 0 when every case passes, 1 when a case fails or errors, and 2 when the run
itself failed: bad arguments, a boot that did not reach the prompt, a file
that did not load or compile (a compiler heading `<< Error ...` counts, since
`qc-file` still writes a QFASL after a reader error), or a case with no answer
within `--timeout` seconds (120 by default). A failed run keeps its TELNET,
quux and ozd logs in its run directory under the cache and prints where;
`--keep` keeps them always.

## Defaults

Each is overridden by its flag or an environment variable.

| Flag | Variable | Default |
|---|---|---|
| `--band` | `LISPM_CHECK_BAND` | `run/check/band.img` in the tree |
| `--ubin` | `LISPM_CHECK_UBIN` | `ubin/` beside the band: the `sys/ubin/` the band's microcode was assembled into, whose `ucadr.tbl` the cold boot reads |
| `--quux` | `LISPM_CHECK_QUUX` | `../muir/target/release/quux` beside the tree |
| `--ozd` | `LISPM_CHECK_OZD` | `../ozd/target/release/ozd` beside the tree |
| `--tree` | `LISPM_CHECK_TREE` | the tree the tool is in |
| | `LISPM_CHECK_PORTS` | the range the ports are taken from, `44000-44999` |

`run/` is git-ignored, so `run/check/band.img` (a link to the band to check
against, or a copy) and `run/check/ubin/` are set up once per clone. The cache
is `$XDG_CACHE_HOME/muir-sys-check`, or `~/.cache/muir-sys-check`: the
checkpoints, the run directories and the locks, never inside the tree.

Each run takes a block of four ports (ozd's UDP, quux's UDP, TELNET and
quux's RFB display) under a lock, checks that each is free, and connects only
to a TELNET listener owned by its own ozd, so parallel runs do not meet. It
stops quux and ozd on every exit, also on a timeout or a signal.

The file server is ozd. Everything that knows about it (its flags, the copy
of the tree it serves, the pathnames of served files, the TELNET listener it
carries and the quux flags that plug the band into it) is the class
`OzdFileServer` in the tool, so it can be replaced by another way of serving
the tree without touching the rest.

## Self-test

`tools/lispm-check-test/run.sh` runs the tool six times on the files beside
it and checks each exit status and verdict: the case file loaded as source and
compiled (status 1, with a wrong value, a wrong error message and an unexpected error on purpose), a
wrong expected value (1), only passing cases (0), and a file with an unclosed
form, loaded and compiled (2). It takes the tool's flags.
