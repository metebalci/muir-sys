# Checking a Lisp change: `tools/lispm-check`

`tools/lispm-check` checks a change to the Lisp sources on a saved band in
seconds rather than minutes. It resumes a checkpoint of the band already booted
to its TELNET prompt, loads or compiles the changed files, and runs a file of
cases in one listener session, printing one line per case.

```
tools/lispm-check [--band PACK] [--quux PATH] [--ozd PATH] [--ubin DIR]
                  [--tree DIR] [--files a.lisp,b.lisp] [--compile]
                  [--file-server auto|device|ozd] [--timeout S] [--keep]
                  [--ozd-file-dates mit|utc] [--ozd-timezone N] CASES
```

## What it does

1. **Setup, once per band, quux build and file server.** A checkpoint resumes
   only on the quux build that wrote it, so the tool keys it by the sha256 of
   the band and of quux, and by the [file server](#the-file-server). When
   there is none, it boots the band cold with the tree served, asks the band
   which host its `SYS:` is on and stops unless that is the server's, logs in
   to that host, compiles a small helper that runs each case, and has quux
   write the checkpoint at the prompt. This takes about 15 s, most of it the
   cold boot.
2. **Each check** takes four free ports of its own, serves a copy of the
   tree's `sys/` and `site/` with the changed files laid over it, starts a
   private ozd, resumes the checkpoint, and loads each file (`load` of the
   source, or with `--compile`, `qc-file` and `load` of the QFASL). It then
   runs every case, stops quux and ozd, and exits. With either file server a
   check takes about 0.6 s with no files, and a small file adds about 0.8 s
   to load it or 1.6 s to compile and load it.

The band is always opened read-only (`--disk-pack PACK,ro`): the writes of the
boot live in the checkpoint, so the band file never changes, and any number
of checks, at the same time too, resume one checkpoint on one band. The tree
is never written either; QFASLs land in the copy.

A file inside the tree's `sys/` is served in its own place and loaded by its
logical name, `sys/io1/time.lisp` as `SYS: IO1; TIME LISP`, so the world sees
the source file it already knows. Any other file is served in the login's home
directory, `OZ: /lispm/` or `HOST: /home/lispm/`. Some `sys/` files do not
load as source because they use functions only the compiler open-codes
(`sys/io1/time.lisp` stops at "The function %PUSH is undefined"): check those
with `--compile`.

## The file server

The copy is served the way the band reads its `SYS:` files, since a band
boots to its prompt only with its `SYS:` host served: a band whose `SYS:` is
on OZ served by the file device alone, or one whose `SYS:` is on HOST served
by ozd alone, waits at boot with no TELNET server, and ozd logs "No server
for this contact name" until the tool gives up after 300 s.

| `--file-server` | For a band whose `SYS:` is on | The copy is served by | The setup logs in to |
|---|---|---|---|
| `ozd` | OZ | ozd: its roots `sys`, `site` and `lispm` | `OZ` |
| `device` | HOST | quux's file device: the copy is HOST's `/` (`--file-root`), holding `sys/`, `site/` and `home/lispm/` | `HOST` |

In both, ozd carries the band's TELNET listener; with `device` that is all it
does: its one root is an empty read-only folder (ozd wants one), so it serves
no file. A checkpoint carries none of the device's folders (quux takes the
mounts from its flags on every resume), so each check mounts its own copy.

`auto`, the default, chooses by the host the band's `SYS:` is on: `device`
for HOST, `ozd` for OZ. It takes that from a checkpoint of this band and quux
already made, whose setup asked the band; else from the answers remembered in
`sys-hosts.json` under the cache; else from a probe, a cold boot with the copy
served both ways that only asks the band (about 15 s, once for each band and
quux). A quux without a file device (no `--file-root` in its `--help`) means
`ozd`. Every run says which server it chose and why:

```
lispm-check: files served by device: the band's SYS: is on HOST (auto, from its checkpoint)
```

## ozd's dates

`--ozd-file-dates mit|utc` and `--ozd-timezone N` are passed to ozd as its
`--file-dates` and `--timezone`: how FILE writes and reads a file's date.
Given neither, ozd takes its own defaults, `utc`: plain UTC, as Systems 1002
and 2000 read FILE dates. A band of Systems 100 to 1001 reads them at its
site's zone, with MIT's daylight savings time on top, so it wants
`--ozd-file-dates mit --ozd-timezone` and that zone: `-1` for System 1001's
release band, `5` for System 100's site. Without them every file date such a
band reads is off by the zone's offset: on the 1001 band, a file of 12:00 GMT
on 15 January read as 3600 s early and one on 15 July as 7200 s early, and
exact with the two flags. ozd refuses a zone under `utc`, and the tool refuses
`--ozd-timezone` without `--ozd-file-dates mit` before it starts anything.
They change only what ozd serves, not the checkpoint, whose setup reads no
file.

```
tools/lispm-check --band release-1001-pack.img --file-server ozd \
                  --ozd-file-dates mit --ozd-timezone -1 ... CASES
```

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
| `--quux` | `LISPM_CHECK_QUUX` | `../muir-sim/target/release/quux` beside the tree |
| `--ozd` | `LISPM_CHECK_OZD` | `../ozd/target/release/ozd` beside the tree |
| `--tree` | `LISPM_CHECK_TREE` | the tree the tool is in |
| `--file-server` | `LISPM_CHECK_FILE_SERVER` | `auto`: [the file server](#the-file-server) the band's `SYS:` host needs |
| `--ozd-file-dates` | `LISPM_CHECK_OZD_FILE_DATES` | none: ozd's own, `utc` ([ozd's dates](#ozds-dates)) |
| `--ozd-timezone` | `LISPM_CHECK_OZD_TIMEZONE` | none: ozd's own |
| | `LISPM_CHECK_PORTS` | the range the ports are taken from, `44000-44999` |

`run/` is git-ignored, so `run/check/band.img` (a link to the band to check
against, or a copy) and `run/check/ubin/` are set up once per clone, and for
the self-test's device mode `run/check/device/band.img` and
`run/check/device/ubin/`. The cache is `$XDG_CACHE_HOME/muir-sys-check`, or
`~/.cache/muir-sys-check`: the checkpoints, the probes' answers, the run
directories and the locks, never inside the tree.

Each run takes a block of four ports (ozd's UDP, quux's UDP, TELNET and
quux's RFB display) under a lock, checks that each is free, and connects only
to a TELNET listener owned by its own ozd, so parallel runs do not meet. It
stops quux and ozd on every exit, also on a timeout or a signal.

Everything that knows how the tree is served (ozd's flags, the copy of the
tree and its layout, the pathnames of served files, the TELNET listener ozd
carries and the quux flags that plug the band into them) is in the classes
`OzdFileServer` and `DeviceFileServer` in the tool; a third way of serving the
tree is a class with the same methods, named in `FILE_SERVERS`.

## Self-test

`tools/lispm-check-test/run.sh` runs the tool seven times on the files beside
it, for each file server, and checks each exit status and verdict: the case
file loaded as source and compiled (status 1, with a wrong value, a wrong
error message and an unexpected error on purpose, and a case that the tree's
`sys/` is served), a wrong expected value (1), only passing cases (0), and a
file with an unclosed form, loaded and compiled (2, with the tool's message
naming the file and the step that failed); and then the passing cases once
more with no `--file-server`, where `auto` must choose that mode's server for
that band. The `ozd` runs use `run/check/band.img` (or `LISPM_CHECK_BAND`), a
band whose `SYS:` is on OZ; the `device` runs use `run/check/device/band.img`
(or `LISPM_CHECK_DEVICE_BAND`), a band whose `SYS:` is on HOST; each with the
`ubin/` beside it. `LISPM_CHECK_TEST_MODES` picks the modes, `ozd device` by
default. It passes its arguments on to every run (`--quux` and so on).
