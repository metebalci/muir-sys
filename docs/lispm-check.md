# Checking a Lisp change: `tools/lispm-check`

`tools/lispm-check` checks a change to the Lisp sources on a saved band in
seconds rather than minutes. It resumes a checkpoint of the band already booted
to its TELNET prompt, loads or compiles the changed files, and runs a file of
cases in one listener session, printing one line per case.

```
tools/lispm-check [--band PACK] [--quux PATH | --cadr PATH] [--ozd PATH]
                  [--ubin DIR] [--tree DIR] [--files a.lisp,b.lisp]
                  [--compile] [--file-server auto|device|ozd]
                  [--engine micro|rtl] [--timeout S] [--setup-limit S] [--keep]
                  [--ozd-file-dates mit|utc] [--ozd-timezone N]
                  [--network chaos|tcp] CASES
```

## The machine

The band runs on muir-sim's executable for the line's system, named by
`MACHINE` at the top of the tool, the one line in which the two lines' copies
of the tool differ:

| Line | System | `MACHINE` | Flag | Variable | Default |
|---|---|---|---|---|---|
| `main` | QUUX's, System 2000 | `quux` | `--quux` | `LISPM_CHECK_QUUX` | `../muir-sim/target/release/quux` |
| `cadr` | the CADR's, System 1002 | `cadr` | `--cadr`, and `--quux` as the same flag | `LISPM_CHECK_CADR` | `../muir-sim/target/release/cadr` |

On the `cadr` line `--quux` is kept as another name of `--cadr`, so that a
command line written for `main` still runs; `LISPM_CHECK_QUUX` is not read
there, since it names a quux. The flags differ by machine: quux is given the
video controller's size, `--video-size 1280x1024`; cadr has no video
controller and refuses that flag, and is given `--no-debug-cable-listen`,
since on rtl it otherwise listens for a debugger's cable on a TCP port. Below,
"the machine" is that executable.

## What it does

1. **Setup, once per band, build of the machine, file server and engine.** A
   checkpoint resumes only on the build and the engine that wrote it, so
   the tool keys it by the sha256 of the band and of the machine, by the
   [file server](#the-file-server) and by the [engine](#the-engine). When
   there is none, it boots the band cold with the tree served, asks the band
   which host its `SYS:` is on and stops unless that is the server's, logs in
   to that host, compiles a small helper that runs each case, and has the
   machine write the checkpoint at the prompt. This takes about 15 s, most of it the
   cold boot, unloaded; on a loaded host much longer (twelve setups of System
   2000's band at once under 24 busy processes took 680 to 914 s each, single
   forms up to 311 s). So the setup has no limit on each step: it waits as long as the
   machine runs, gives up as a hang (exit status 3) when the machine gets no
   CPU time at all for 60 s (stopped), and has one hard limit on its wall
   clock, `--setup-limit` (1800 s), which ends a machine that runs but never
   answers, also as a hang. The probe of [the file server](#the-file-server)
   waits the same way.
2. **Each check** takes four free ports of its own, serves a copy of the
   tree's `sys/` and `site/` with the changed files laid over it, starts a
   private ozd, resumes the checkpoint, and loads each file (`load` of the
   source, or with `--compile`, `qc-file` and `load` of the QFASL). It then
   runs every case, stops the machine and ozd, and exits. With either file server a
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
A compiler file patched alone into a band built before the cross build (System
2000's) needs `sys/sys/qcdefs.lisp` given before it in `--files`, since
`qcopt`, `qcp1` and `qcfasd` read what it defines (`tools/cross-check/README.md`).

## The file server

The copy is served the way the band reads its `SYS:` files, since a band
boots to its prompt only with its `SYS:` host served: a band whose `SYS:` is
on OZ served by the file device alone, or one whose `SYS:` is on HOST served
by ozd alone, waits at boot with no TELNET server, and ozd logs "No server
for this contact name" until the setup gives up at `--setup-limit` and
reports a hang (exit status 3). So does a band
the machine cannot run: a System 1002 band for QUUX (microcode 1000) on quux
revision 11 or later (see [Defaults](#defaults)).

| `--file-server` | For a band whose `SYS:` is on | The copy is served by | The setup logs in to |
|---|---|---|---|
| `ozd` | OZ | ozd: its roots `sys`, `site` and `lispm` | `OZ` |
| `device` | HOST | quux's file device: the copy is HOST's `/` (`--file-root`), holding `sys/`, `site/` and `home/lispm/` | `HOST` |

In both, ozd carries the band's TELNET listener; with `device` that is all it
does: its one root is an empty read-only folder (ozd wants one), so it serves
no file. A checkpoint carries none of the device's folders (quux takes the
mounts from its flags on every resume), so each check mounts its own copy.

The file device is QUUX's: cadr has none, so on the `cadr` line the files are
always served by ozd, and `--file-server device` is refused.

`auto`, the default, chooses by the host the band's `SYS:` is on: `device`
for HOST, `ozd` for OZ. It takes that from a checkpoint of this band and
machine already made, whose setup asked the band; else from the answers remembered in
`sys-hosts.json` under the cache; else from a probe, a cold boot with the copy
served both ways that only asks the band (about 15 s, once for each band and
machine). A machine without a file device (no `--file-root` in its `--help`,
as cadr) means `ozd`. Every run says which server it chose and why:

```
lispm-check: files served by device: the band's SYS: is on HOST (auto, from its checkpoint)
```

## The engine

`--engine micro|rtl` (or `LISPM_CHECK_ENGINE`) is the engine the machine runs,
passed to it as `--micro` or `--rtl`; any other value is refused before
anything starts. `micro`, the default, is the microinstruction engine; `rtl` is
the register transfer engine, which quux and cadr pace at the machine's own
speed, so its setup and checks take longer. A checkpoint is made on one engine
and resumes only on it, so each engine has its own. The command the machine
ran with heads its log, `quux.log` or `cadr.log` in the run directory (kept
with `--keep`):

```
tools/lispm-check --engine rtl --keep ... CASES
```

## The network

QUUX's revision 16 has the Ethernet device (QUUX's Ethernet contract,
sections 3, 7 and 8 R1). On it every run takes a tap of the pool that
muir-sim's `tools/quux-taps` installs, through the fault relay
(`tools/fault-relay/`), so that the band always has its link, and gives the
machine the tap's addresses at the setup and at every resume:
`--ethernet-socket` (the relay's socket), `--ip-address` and `--ip-gateway`,
as the relay's line names them. Revision 15 and the CADR take no tap. The
tool asks the machine which revision it runs once for each build and value of
`MUIR_QUUX_REVISION` (a wrapper may set it), and remembers the answer in
`revisions.json` under the cache.

`--network chaos|tcp` (or `LISPM_CHECK_NETWORK`) says what carries the TELNET
session:

| `--network` | The session | The machine's Chaos | ozd |
|---|---|---|---|
| `chaos` (the default) | ozd's TCP gateway to the band's Chaos TELNET server | `--chaos-address 177201` and its cable, `--chaos-udp` to ozd | started |
| `tcp` | the build host's own TCP, from a socket bound to the tap (`SO_BINDTODEVICE`), to the band's TELNET server on port 23 at QUUX's address | `--chaos-address 177201` only: no cable and no peer | not started |

`tcp` needs revision 16 and a band whose `SYS:` is on HOST, its files on the
file device: ozd would serve OZ's files over Chaos. So `--file-server auto`
means `device` under `tcp`, and the setup's check refuses a band whose `SYS:`
is on OZ. `--chaos-address` is given in both until the NCP leaves the band
(the contract's R3), since the checkpoint holds the Chaosnet interface's
switches and muir refuses a resume under others; so one checkpoint serves
both networks. At the end of a setup over TCP the tool closes cleanly
(section 7): it half-closes the session, reads to the band's EOF, which the
band's server sends at the client's EOF, and waits 0.5 s for the last ACK, so
that the checkpoint holds no connection; a band that sends no EOF within 60
s, or resets the session, fails the setup. A check closes the same way, but
does not fail on it.

**The taps, and a checkpoint for each tap index.** The range is
`LISPM_CHECK_TAPS`, tap indexes as `N`, `LO-HI` or a comma-separated list of
them, by default the whole pool; of them the host-only taps alone, those with
a /30 of their own, since a LAN tap's address is a real one (the contract,
amendment 3). A checkpoint is made for each tap index on its first use, by
the run that holds that tap, and its key names QUUX's address behind the tap,
since muir refuses a resume under other addresses; on revision 16 the key's
setup version is 3:

```
<band sha256>-<quux sha256>-3-micro-device-169.254.101.2.chk   (each sha256 its first 16 digits)
```

The JSON beside it records the tap, both addresses, and the network that made
it. The taps tried are those of the range whose index already has a
checkpoint for this key, lowest first, then the rest, lowest first, so that a
key's runs keep to as few indexes as run at once. A tap another run holds is
passed for the next; when every one is held the run waits for one, up to
`--setup-limit`. The tap is the lock: the kernel lets one program hold it, so
a band uses index N's address only while its run holds tap N. The relay
serves the setup's machine and then the check's, and stops after the last
machine; with `--keep` its report, `relay.json`, and its log join the run's
files. Every run says which tap it took:

```
lispm-check: tap quux1, QUUX at 169.254.101.2, TELNET over tcp
```

The relay's socket is under the cache (`sockets/`), or under the system's
temporary directory when the cache's path is too long for a UNIX socket.

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

A form that asks a question anyway fails at once, whatever the case
expected. Every question asked through `FQUERY` (`Y-OR-N-P`, `YES-OR-NO-P` and
`FQUERY` itself) first signals the condition `FQUERY`; the case's
`condition-case` has a clause for it, which ends the form there and reports
the question's text. GC-ON's question shows it:

```
FAIL  (progn (gc-on) ...)  -> asked Try garbage collecting after all?, the form ended there
```

This is the only way to see `YES-OR-NO-P` over TELNET, where it prints no
prompt at all, only a beep. A second line of defence catches a question asked
some other way: when what the case printed ends with a bare `(Y or N)` or
`(Yes or No)`, with no error before it and no output for 0.5 s after it, the
case fails with `-> asked QUESTION, answered No`, the question is answered No,
and the next case is sent once that form has ended. The words inside a value
or followed by more output ask nothing: a value is printed between the case's
markers, read before any question. An error that escapes the case's handlers,
followed by the listener's "Enter the debugger (No means abort instead)? (Y or
N)", is answered No as before and reported as an `ERROR` with the error's
message.

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
within `--timeout` seconds (120 by default). It is 3 when the machine hung in
the setup's cold boot or the probe's: it got no CPU time for 60 s (a stopped
machine), or ran without answering until `--setup-limit` (above). A failed
run keeps its TELNET,
machine and ozd logs in its run directory under the cache and prints where;
`--keep` keeps them always.

## Defaults

Each is overridden by its flag or an environment variable.

| Flag | Variable | Default |
|---|---|---|
| `--band` | `LISPM_CHECK_BAND` | `run/check/band.img` in the tree: a band of the line's system, below |
| `--ubin` | `LISPM_CHECK_UBIN` | `ubin/` beside the band: the `sys/ubin/` the band's microcode was assembled into, whose `ucadr.tbl` the cold boot reads |
| `--quux` (main) | `LISPM_CHECK_QUUX` | `../muir-sim/target/release/quux` beside the tree |
| `--cadr` (cadr) | `LISPM_CHECK_CADR` | `../muir-sim/target/release/cadr` beside the tree |
| `--ozd` | `LISPM_CHECK_OZD` | `../ozd/target/release/ozd` beside the tree |
| `--tree` | `LISPM_CHECK_TREE` | the tree the tool is in |
| `--file-server` | `LISPM_CHECK_FILE_SERVER` | `auto`: [the file server](#the-file-server) the band's `SYS:` host needs |
| `--engine` | `LISPM_CHECK_ENGINE` | `micro` ([the engine](#the-engine)) |
| `--setup-limit` | `LISPM_CHECK_SETUP_LIMIT` | 1800: the hard limit in seconds on the setup's and the probe's wall clock |
| `--ozd-file-dates` | `LISPM_CHECK_OZD_FILE_DATES` | none: ozd's own, `utc` ([ozd's dates](#ozds-dates)) |
| `--ozd-timezone` | `LISPM_CHECK_OZD_TIMEZONE` | none: ozd's own |
| `--network` | `LISPM_CHECK_NETWORK` | `chaos` ([the network](#the-network)) |
| | `LISPM_CHECK_PORTS` | the range the ports are taken from, `44000-44999` |
| | `LISPM_CHECK_TAPS` | the tap indexes taken from on revision 16: the pool's host-only taps |
| | `LISPM_CHECK_RELAY_FLAGS` | none: the fault relay's fault flags (`tools/fault-relay/README.md`), for T4 |

`run/` is git-ignored, so `run/check/band.img` (a link to the band to check
against, or a copy) and `run/check/ubin/` are set up once per clone:

- **`main`:** QUUX's current System 2000 band, the one muir-sim's tests boot:
  `run/check/band.img` a link to muir-sim's `ref/band-2000/pack-2000.vhd`, and
  `run/check/ubin/` links to the `ucadr.*` and `promh.*` beside it, so both
  follow when muir-sim takes a new hand-over. Its `SYS:` is on HOST, so its
  files are served by the file device. From the tree:

  ```
  ln -s ../../../muir-sim/ref/band-2000/pack-2000.vhd run/check/band.img
  mkdir run/check/ubin
  for f in ucadr.mcr ucadr.sym ucadr.tbl ucadr.locs promh.mcr promh.sym promh.tbl promh.locs
  do ln -s ../../../../muir-sim/ref/band-2000/$f run/check/ubin/$f; done
  ```

  The default was a System 1002 band for QUUX (microcode 1000, `SYS:` on OZ)
  until quux revision 11. That microcode reads block-disk's registers at
  17377774, where revision 11 moved them to the register page at 17777400:
  on quux revision 12 such a band stays in the microcode's
  `DISK-AWAIT-READY` loop (PC 25040) for as long as it runs, with no TELNET
  server, where quux revision 10 boots it to the prompt in about 16 s.
- **`cadr`:** a band of the CADR's system, run on cadr, with its `SYS:` on
  OZ. No System 1002 band for the CADR has been built yet, so until one is,
  `run/check/band.img` is System 1001's release band
  (`release-1001-pack.img`, microcode 323) and `run/check/ubin/` its
  `ubin/`; the line's fixes are checked on it (`docs/release-1002.md`). It
  reads FILE dates at its site's zone, so a check of dates on it wants
  `--ozd-file-dates mit --ozd-timezone -1` ([ozd's dates](#ozds-dates)). The cache is `$XDG_CACHE_HOME/muir-sys-check`, or
`~/.cache/muir-sys-check`: the checkpoints, the probes' answers, the run
directories and the locks, never inside the tree.

Each run takes a block of four ports (ozd's UDP, the machine's UDP, TELNET
and the machine's RFB display) under a lock, checks that each is free, and connects only
to a TELNET listener owned by its own ozd, so parallel runs do not meet. It
stops the machine and ozd on every exit, also on a timeout or a signal.

Everything that knows how the tree is served (ozd's flags, the copy of the
tree and its layout, the pathnames of served files, the TELNET listener ozd
carries and the machine's flags that plug the band into them) is in the classes
`OzdFileServer` and `DeviceFileServer` in the tool; a third way of serving the
tree is a class with the same methods, named in `FILE_SERVERS`. The network
that carries the session is a key of `NETWORKS`, which the same classes
branch on (`machine_flags`, `_open`, `close_session`); the third, `host`, a
session through quux's file device for a band without its network, is to
come there. `options` and `prepare` are the command line and everything
before the check (the revision, the file server, the tap, the checkpoint),
which `tools/tcp-check/run` takes from the tool.

## Self-test

`tools/lispm-check-test/run.sh` runs the tool eight times on the files beside
it, for each file server, and checks each exit status and verdict: the case
file loaded as source and compiled (status 1, with a wrong value, a wrong
error message and an unexpected error on purpose, and a case that the tree's
`sys/` is served), a wrong expected value (1), only passing cases (0), and a
file with an unclosed form, loaded and compiled (2, with the tool's message
naming the file and the step that failed), the question cases
(`question.cases`: status 1, each verdict and its text as
`expected-question.txt`, the cases' time under 20 s with `--timeout 30`); and then the passing cases once
more with no `--file-server`, where `auto` must choose that mode's server for
that band. `LISPM_CHECK_TEST_MODES` picks the modes, each run with the
`ubin/` beside its band:

| Line | Modes by default | `device` band | `ozd` band |
|---|---|---|---|
| `main` | `device` | `LISPM_CHECK_DEVICE_BAND`, else `LISPM_CHECK_BAND`, else `run/check/band.img` (System 2000, `SYS:` on HOST) | `LISPM_CHECK_BAND`, else `run/check/band.img`: a band whose `SYS:` is on OZ, of which quux since revision 11 runs none |
| `cadr` | `ozd` | none: cadr has no file device | `LISPM_CHECK_BAND`, else `run/check/band.img` |

It passes its arguments on to every run (`--quux`, `--cadr`, `--engine` and
so on), so `tools/lispm-check-test/run.sh --engine rtl` is the self-test on
rtl.

`tools/lispm-check-test/network.sh` is the self-test of [the
network](#the-network), on a revision 16 machine and a band with the network,
with `LISPM_CHECK_TAPS` naming two host-only taps at least, A and B, and a
cache of its own, so that its first run sets up over TCP: `tcp` (A held by
another program, the run takes B, sets up over TCP and resumes; the machine
has B's addresses and no Chaos peer, ozd is not started, the relay found no
bad frame, the key names B's address, and the resumed band holds only the
session's connection), `order` (both free, B alone with a checkpoint: the run
takes B over Chaos with no setup, one checkpoint serving both networks),
`index` (B held: A, with a setup of its own), `order-both` (both free: A, no
setup), `wait` (A alone and held for 5 s: the run waits, then takes it),
`no-tap` (a range with no tap: status 2), and with
`LISPM_CHECK_TEST_QUUX15` naming a revision 15 machine, `rev15-tcp` (refused)
and `rev15-chaos` (no tap, the key as before). `LISPM_CHECK_TEST_TOOL` names
another copy of the tool to test, a planted one say. About 5 minutes on
micro.
