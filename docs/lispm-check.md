# Checking a Lisp change: `tools/lispm-check`

`tools/lispm-check` checks a change to the Lisp sources on a saved band in
seconds rather than minutes. It resumes a checkpoint of the band already booted
to its TELNET prompt, loads or compiles the changed files, and runs a file of
cases in one listener session, printing one line per case.

```
tools/lispm-check [--band PACK] [--quux PATH]
                  [--ubin DIR] [--tree DIR] [--files a.lisp,b.lisp]
                  [--compile] [--file-server auto|device]
                  [--engine micro|rtl] [--timeout S] [--setup-limit S] [--keep]
                  [--network tcp|files] CASES
```

## The machine

The band runs on muir-sim's `quux` (`--quux`, `LISPM_CHECK_QUUX`, by default
`../muir-sim/target/release/quux` beside the tree), named by `MACHINE` at the
top of the tool and given the video controller's size, `--video-size
1280x1024`. Below, "the machine" is that executable. This is `main`'s copy of
the tool, for QUUX alone; the `cadr` line keeps its own copy and its own
page, for the CADR (`--cadr`), with ozd and Chaos.

QUUX has no Chaosnet interface, and this copy starts no ozd. `--network
chaos`, `--file-server ozd`, `--ozd`, `--ozd-file-dates` and `--ozd-timezone`,
and `LISPM_CHECK_NETWORK=chaos` and `LISPM_CHECK_FILE_SERVER=ozd`, are each
refused by name before anything starts (status 2):

```
lispm-check: error: --network chaos: QUUX has no Chaosnet interface, and these tools start no ozd: the session goes over tcp, the default, or through files, and quux's file device serves the files
```

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
   answers, also as a hang.
2. **Each check** takes four free ports of its own, serves a copy of the
   tree's `sys/` and `site/` with the changed files laid over it, resumes
   the checkpoint, and loads each file (`load` of the source, or with
   `--compile`, `qc-file` and `load` of the QFASL). It then runs every case,
   stops the machine, and exits. A check takes about 0.6 s with no files,
   and a small file adds about 0.8 s to load it or 1.6 s to compile and load
   it.

The band is always opened read-only (`--disk-pack PACK,ro`): the writes of the
boot live in the checkpoint, so the band file never changes, and any number
of checks, at the same time too, resume one checkpoint on one band. The tree
is never written either; QFASLs land in the copy.

A file inside the tree's `sys/` is served in its own place and loaded by its
logical name, `sys/io1/time.lisp` as `SYS: IO1; TIME LISP`, so the world sees
the source file it already knows. Any other file is served in the login's home
directory, `/home/lispm/` on the file device's host:
`FILES: /home/lispm/`, `HOST: /home/lispm/` in a band that names it HOST
(Systems 2000 and 2001, and the bands before the rename). Some `sys/` files do not
load as source because they use functions only the compiler open-codes
(`sys/io1/time.lisp` stops at "The function %PUSH is undefined"): check those
with `--compile`.
A compiler file patched alone into a band built before the cross build (System
2000's) needs `sys/sys/qcdefs.lisp` given before it in `--files`, since
`qcopt`, `qcp1` and `qcfasd` read what it defines (`tools/cross-check/README.md`).

## The file server

The copy is served by quux's file device, for a band whose `SYS:` is on the
file device's host, FILES (or HOST in the bands before the rename): the copy
is that host's `/` (`--file-root`), holding `sys/`, `site/` and
`home/lispm/`, and the setup logs in to the band's name for it, `FILES` or
`HOST`. A checkpoint carries none of the device's folders (quux takes the
mounts from its flags on every resume), so each check mounts its own copy.

`--file-server device` and `auto`, the default, mean the same: the device is
the one file server, and a machine without it (no `--file-root` in its
`--help`) is refused. Every run says so:

```
lispm-check: files served by device: quux's file device, the one server (auto)
```

A band boots to its prompt only with its `SYS:` host served, so a band whose
`SYS:` is on OZ waits at boot with no TELNET server until the setup gives up
at `--setup-limit` and reports a hang (exit status 3). So does a band the
machine cannot run: a System 1002 band for QUUX (microcode 1000) on quux
revision 11 or later (see [Defaults](#defaults)). Until ozd left these tools,
`--file-server ozd` served an OZ band by ozd, and `auto` chose between the two
by the host the band's `SYS:` was on, asked by a probe, a cold boot with the
copy served both ways.

## The engine

`--engine micro|rtl` (or `LISPM_CHECK_ENGINE`) is the engine the machine runs,
passed to it as `--micro` or `--rtl`; any other value is refused before
anything starts. `micro`, the default, is the microinstruction engine; `rtl` is
the register transfer engine, which quux paces at the machine's own
speed, so its setup and checks take longer. A checkpoint is made on one engine
and resumes only on it, so each engine has its own. The command the machine
ran with heads its log, `quux.log` in the run directory (kept
with `--keep`):

```
tools/lispm-check --engine rtl --keep ... CASES
```

## The network

QUUX has the Ethernet device (QUUX's Ethernet contract, sections 3, 7 and
8 R1). Every run takes a tap of the pool that
muir-sim's `tools/quux-taps` installs, through the fault relay
(`tools/fault-relay/`), so that the band always has its link, and gives the
machine the tap's addresses at the setup and at every resume:
`--ethernet-socket` (the relay's socket), `--ip-address` and `--ip-gateway`,
as the relay's line names them (all but `--network files`'s).

**One QUUX.** The tools run the QUUX that `quux` runs, revision 16; an
earlier revision runs from an earlier commit of this tree (revisions 13-15
left these tools, and with them the choice of network by revision). Until
muir-sim's `quux` runs revision 16 by default, the tool gives every machine
it starts `MUIR_QUUX_REVISION=16`, and refuses a `MUIR_QUUX_REVISION` set to
another value. It asks the machine what it runs once for each build and
value of `MUIR_QUUX_REVISION`, and remembers the answer in `revisions.json`
under the cache: a machine whose start names a revision other than 16 (an
older quux, or a wrapper that sets another) is refused, naming it; a start
that names none, as `quux`'s will once it runs one QUUX alone, is taken. It
asks with no engine named, so that a wrapper's flags for rtl alone
(`--memory-timing`, `--cache`) are taken; quux's own engine is rtl.

`--network tcp|files` (or `LISPM_CHECK_NETWORK`) says what carries the
session: TELNET over TCP, or no network at all, the session going through
files on the file device's host ([`files`](#--network-files)):

| `--network` | The session | The machine's Chaos |
|---|---|---|
| `tcp` | the build host's own TCP, from a socket bound to the tap (`SO_BINDTODEVICE`), to the band's TELNET server on port 23 at QUUX's address | none: no address, no cable and no peer (until R3, `--chaos-address 177201` alone) |
| `files` | request and answer files in `/home/lispm/` on the file device's host, which HC-SERVE, a loop at the band's listener, reads and writes | none, and no tap |

`chaos`, ozd's TCP gateway to the band's Chaos TELNET server, the machine
given `--chaos-address 177201` and its cable, `--chaos-udp` to ozd, left with
main's Chaos and ozd path, and is refused by name (above).

**The default** (the contract, section 8 R2): a run that names no network,
by the flag or the variable, takes `tcp`, the band having the network.
Until R2 every run's default was `chaos`, and revisions 13-15 took `chaos`
until they left these tools. A band without the network (a band from before Ethernet, or a check that wants
the device to itself, as microcode-check's `ethernet-stray`) wants
`files`: over TCP its setup waits for a TELNET server that never
answers, until `--setup-limit`, and then ends as a hang (status 3) whose
message asks whether the band starts its network. The tap line of a run that took the default says so:

```
lispm-check: tap quux1, QUUX at 169.254.101.2, TELNET over tcp (the default)
```

The tools that build their own sessions from this tool's classes,
`tools/system-check/warm-boot` and `tools/cross-build/run`'s sessions (and
with them `tools/microcode-check/generational-save`), take the tap and the
network through its helper, `harness_network`: the machine asked and refused
as above, `LISPM_CHECK_NETWORK` or the default (`chaos` refused as above), and
a tap of `LISPM_CHECK_TAPS`. The tools that run this one, as microcode-check,
system-check, assembler-check and cross-check do, get its default.

`tcp` needs a band whose `SYS:` is on the file device's host (FILES, or HOST
before the rename), its files on the file device; the setup's check refuses a
band whose `SYS:` is on OZ. Since the NCP left the band (the contract's
section 8, R3), `tcp` gives the machine no `--chaos-address`; `chaos` had a
checkpoint of its own, its key ending `-chaos` before the address, until it
left these tools. Until R3 `--chaos-address` was given in both, so that one
checkpoint served both networks and the band behind the pool was LISPM-1;
now a band is the unnamed host of its INTERNET address. At the end of a setup over TCP the tool closes cleanly
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
since muir refuses a resume under other addresses; the key's setup version
is 4 (3 until R3; a run over Chaos added `-chaos` before the address):

```
<band sha256>-<quux sha256>-4-micro-device-169.254.101.2.chk   (each sha256 its first 16 digits; 3 until R3)
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

### `--network files`

`files` checks a band without its network (QUUX's Ethernet contract, section
18, Q-N13 (a)), when the check is to run without a tap (and, until it left
these tools, on revision 15, whose band had no Chaos and no Ethernet device
since R3).
It is never the default; a run names it. No tap is taken and
`LISPM_CHECK_TAPS` is not used (the run says so). The tools that drive TELNET
sessions of their own
through `harness_network` (`tools/system-check/warm-boot`,
`tools/cross-build/run`'s sessions) refuse `LISPM_CHECK_NETWORK=files`.

**The session.** Request K is the form, written whole to `hc-K.req` in the
login's home of the served copy. HC-SERVE (`tools/lispm-check-lisp/hc-serve.lisp`)
reads it by `READ` in the listener's package and base, `USER` and 10, runs
it through the same helper a TELNET session calls, `LISPM-CHECK-CASE`, keeps
what it printed in a string, writes that to `hc-K.ans`, and then writes
`hc-K.done`. The tool reads the answer only once `hc-K.done` is there: a
form may write files of its own meanwhile, and the self-test's
`early-answer` case writes a false `hc-K.ans` while it runs. The answer
carries the same markers a TELNET answer does, so the verdicts are made by
the same code.

**The setup.** The band is booted cold with no network and a glass TTY
(muir-sim's `--glass-tty`, on the free TCP port TELNET would take). The
helper and HC-SERVE are laid out as the login's init file,
`/home/lispm/lispm.init`, and two short forms are typed at the console,
`(login "LISPM")`, which logs in on the associated machine and loads the
init file, and `(hc-serve)`, which must run at the listener rather than
inside a `LOAD`, whose stream would stay open. They are typed blind, since
the glass TTY reads this band's screen as `?`, once the machine has run 20
million microcycles (`HC_TYPE_AFTER`, asked at its prompt with `pc`), past
the boot's first microcode: one setup that typed as soon as the glass TTY
took a connection stopped itself there (`HALT-CONS` at PC 32063, at 0.75
million), though four more that typed as early did not. The band keeps only
the first 40-odd characters typed before its listener runs, so the start is
kept short (three longer forms typed early left half a form at the
listener); these two were kept in all 38 boots that typed them blind, from
2.5 to 300 million microcycles in, so they are typed once, with no retype
that could leave a second `(hc-serve)` queued.
The setup then waits for `hc-ready.txt`, asks the band's `SYS:` host as the
first request, and takes the checkpoint at the machine's prompt
(`checkpoint FILE`) while HC-SERVE waits; the JSON beside it records the
network and `hc_next`, the number of the first request a check sends, since
HC-SERVE's count is in the checkpoint. A check resumes it with its own copy
served and types nothing.

**The checkpoint while HC-SERVE waits.** The file device refuses a
checkpoint while it has a handle open or a command queued (muir-sim
`src/file_device.rs`, `checkpoint_refusal`); the refusal is not a wait: the
machine says `not written` and runs on. Between two polls HC-SERVE holds no
file open and sits in `PROCESS-SLEEP` for 6 ticks of the band's 60 Hz clock,
100 ms of the machine's own time; its one command is the poll's `PROBEF`,
20 us of the machine's time. A poll measured 1.92 million microcycles on
micro at revision 15, not the 11.8 million that 100 ms makes at 8.5 ns a
microcycle, because the machine's clock runs ahead of its microcycles: it
counts memory waits too, about 60 ns a microcycle on average over a wait
(5.56 s of the machine's clock in 92.1 million microcycles; 48 polls in it,
116 ms each). So a checkpoint meets a command in flight about once in a
thousand tries or fewer (0 of 848 in the measurement). A refusal for a
command queued with no handle open is taken again after 0.1-0.5 s, up to
20 times (`CHECKPOINT_TRIES`); a refusal for a handle open is HC-SERVE's
fault and fails the setup at once (status 2). The checkpoint's key ends
`-files-` and the first 8 digits of HC-SERVE's sha256, so a changed HC-SERVE
makes its checkpoint again:

```
<band sha256>-<quux sha256>-1-micro-device-files-<HC-SERVE sha256>.chk   (each sha256 its first 16 digits, HC-SERVE's 8)
```

**What differs from TELNET.** A bare `(Y or N)` asked without `FQUERY`, and an
error the helper does not catch, wait at the console listener, where nothing
answers them: the request gets no answer and the run fails at `--timeout`
(status 2), where TELNET answers No. Output to `TERMINAL-IO` is not in the
answer. A form is read from a file by `READ`, not typed at a listener, in the
same package, base and readtable.

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
the setup's cold boot: it got no CPU time for 60 s (a stopped
machine), or ran without answering until `--setup-limit` (above). A failed
run keeps its TELNET, machine and fault relay logs in its run directory under
the cache and prints where; `--keep` keeps them always.

## Defaults

Each is overridden by its flag or an environment variable.

| Flag | Variable | Default |
|---|---|---|
| `--band` | `LISPM_CHECK_BAND` | `run/check/band.img` in the tree: a band of the line's system, below |
| `--ubin` | `LISPM_CHECK_UBIN` | `ubin/` beside the band: the `sys/ubin/` the band's microcode was assembled into, whose `ucadr.tbl` the cold boot reads |
| `--quux` | `LISPM_CHECK_QUUX` | `../muir-sim/target/release/quux` beside the tree |
| `--tree` | `LISPM_CHECK_TREE` | the tree the tool is in |
| `--file-server` | `LISPM_CHECK_FILE_SERVER` | `auto`: quux's file device, as `device` ([the file server](#the-file-server)) |
| `--engine` | `LISPM_CHECK_ENGINE` | `micro` ([the engine](#the-engine)) |
| `--setup-limit` | `LISPM_CHECK_SETUP_LIMIT` | 1800: the hard limit in seconds on the setup's wall clock |
| `--network` | `LISPM_CHECK_NETWORK` | `tcp` ([the network](#the-network)) |
| | `LISPM_CHECK_PORTS` | the range the ports are taken from, `44000-44999` |
| | `LISPM_CHECK_TAPS` | the tap indexes taken from: the pool's host-only taps |
| | `LISPM_CHECK_RELAY_FLAGS` | none: the fault relay's fault flags (`tools/fault-relay/README.md`), for T4 |

`--ozd` (`LISPM_CHECK_OZD`), `--ozd-file-dates` and `--ozd-timezone`, ozd's
path and its FILE dates, which a band of Systems 100 to 1001 wanted at its
site's zone, left with ozd; the `cadr` line's copy keeps them.

`run/` is git-ignored, so `run/check/band.img` (a link to the band to check
against, or a copy) and `run/check/ubin/` are set up once per clone:

- A band of System 2002 for revision 16, the one QUUX these
  tools run: a read-only copy of the native band of a route of
  `tools/cross-build/run` (`native6`) as `run/check/band.img`, and that
  route's `ubin/` (its assembly's `ucadr.*` and `promh.*`) copied to
  `run/check/ubin/`. Its `SYS:` is on FILES, so its files are served by the
  file device. muir-sim's `quux` has no boot PROM for revision 16 built in,
  so until it has one `--quux` names a wrapper that gives
  `run/check/ubin/promh.mcr` as `--prom` (but not on a `--resume`); the tool
  sets `MUIR_QUUX_REVISION=16`. From the tree, with ROUTE a route's output:

  ```
  cp --sparse=always ROUTE/bands/native6.img run/check/band.img && chmod 444 run/check/band.img
  mkdir run/check/ubin && cp ROUTE-UBIN/ucadr.* ROUTE-UBIN/promh.* run/check/ubin/
  ```

  The default was System 2001's band, the one muir-sim's tests boot
  (`tests/system_2001.rs`, release-2001's disk, a link to muir-sim's
  `ref/band-2001-81b3973/handover-2001-81b3973-disk.vhd`, with
  `run/check/ubin/` linking to the `ucadr.*` and `promh.*` beside it), on
  quux at revision 13 with its PROM 2001, `SYS:` on HOST, until revisions
  13-15 left these tools.

  The default was System 2000's band (muir-sim's `ref/band-2000/`), which
  runs on revision 12 alone (at 13 it stays at a black screen), and the
  current quux refuses revision 12 ("revision 13, 14, 15 or 16").

  The default was a System 1002 band for QUUX (microcode 1000, `SYS:` on OZ)
  until quux revision 11. That microcode reads block-disk's registers at
  17377774, where revision 11 moved them to the register page at 17777400:
  on quux revision 12 such a band stays in the microcode's
  `DISK-AWAIT-READY` loop (PC 25040) for as long as it runs, with no TELNET
  server, where quux revision 10 boots it to the prompt in about 16 s.

  The `cadr` line's band is the CADR's, its `SYS:` on OZ; its copy of the
  tool and of this page say which.

The cache is `$XDG_CACHE_HOME/muir-sys-check`, or
`~/.cache/muir-sys-check`: the checkpoints, the machines' answers, the run
directories and the locks, never inside the tree.

Each run takes a block of four ports under a lock and checks that each is
free: the third is the glass TTY's under `--network files`, the fourth the
machine's RFB display (the first two were ozd's and the machine's Chaos
UDP, and the third ozd's TELNET gateway, until ozd left these tools). A
session over TCP reaches only the band behind the run's own tap, so
parallel runs do not meet. It stops the machine and the fault relay on
every exit, also on a timeout or a signal.

Everything that knows how the tree is served (the copy of the tree and its
layout, the pathnames of served files, the TELNET listener and the
machine's flags that plug the band into them) is in the classes
`FileServer` and `DeviceFileServer` in the tool (`FileServer` was
`OzdFileServer`, ozd's, until ozd left these tools); a second way of serving
the tree is a class with the same methods, named in `FILE_SERVERS`. The
network that carries the session is one of `NETWORKS`, which the same
classes branch on (`machine_flags`, `_open`, `connect_listener`,
`close_session`); `files` is the session through quux's file device for a
band without its network: `FileSession` beside `Session`, and `setup_files`,
`take_checkpoint` and `type_at_console` for its setup, with HC-SERVE in
`tools/lispm-check-lisp/hc-serve.lisp`. `options` and `prepare` are the command line and everything
before the check (the revision, the file server, the tap, the checkpoint),
which `tools/tcp-check/run` takes from the tool.

## Self-test

`tools/lispm-check-test/run.sh` runs the tool eight times on the files beside
it, with the file device, and checks each exit status and verdict: the case
file loaded as source and compiled (status 1, with a wrong value, a wrong
error message and an unexpected error on purpose, and a case that the tree's
`sys/` is served), a wrong expected value (1), only passing cases (0), and a
file with an unclosed form, loaded and compiled (2, with the tool's message
naming the file and the step that failed), the question cases
(`question.cases`: status 1, each verdict and its text as
`expected-question.txt`, the cases' time under 40 s with `--timeout 60`); and then the passing cases once
more with no `--file-server`, where `auto` must choose the device. Its band
is `LISPM_CHECK_DEVICE_BAND`, else `LISPM_CHECK_BAND`, else
`run/check/band.img` (System 2002 for revision 16, `SYS:` on FILES), with the
`ubin/` beside it; `LISPM_CHECK_TEST_MODES` names `device`, the one mode left
(`ozd`, a band whose `SYS:` is on OZ served by ozd, left with ozd). A
stand-in ozd that notes each start is given to every run, as
`LISPM_CHECK_OZD` and as the first `ozd` on `PATH`, and the last line,
`no-ozd`, wants it never started.

It passes its arguments on to every run (`--quux` and so on).

`tools/lispm-check-test/network.sh` is the self-test of [the
network](#the-network), on QUUX's machine and a band with the network,
with `LISPM_CHECK_TAPS` naming two host-only taps at least, A and B, and a
cache of its own, so that its first run sets up over TCP: `tcp` (A held by
another program, the run takes B, sets up over TCP and resumes; the machine
has B's addresses and no Chaos peer, ozd is not started, the relay found no
bad frame, the key names B's address, and the resumed band holds only the
session's connection; and the machine has no `--chaos-address`),
`index` (B held: A, with a setup of its own), `order-both` (both free: A, no
setup), `wait` (A alone and held for 5 s: the run waits, then takes it),
`no-tap` (a range with no tap: status 2); then the machine asked what it
runs: `other-revision` (a stand-in whose start names revision 15: status 2,
refused, naming it, before any setup), `variable-set`
(`MUIR_QUUX_REVISION=15` set: status 2, refused) and `no-revision` (a
wrapper over `--quux`'s machine whose start names no revision, as `quux`'s
will: taken, over TCP). `rev15-tcp` and `rev15-chaos`, on a revision 15
machine named by `LISPM_CHECK_TEST_QUUX15`, left with revision 15. Then
Chaos and ozd refused by name, each before the machine is asked anything or
a tap taken (status 2, "QUUX has no Chaosnet interface"): `chaos-refused`
(`--network chaos`), `chaos-variable` (`LISPM_CHECK_NETWORK=chaos`),
`harness-chaos` (the same through `harness_network`), `ozd-refused`
(`--file-server ozd`), `ozd-variable` (`LISPM_CHECK_FILE_SERVER=ozd`) and
`ozd-flags` (`--ozd`, `--ozd-file-dates` and `--ozd-timezone`). Then the
default (section 8 R2), with neither `--network` nor `LISPM_CHECK_NETWORK`:
`default` (over TCP on a tap, no Chaos cable, and the stand-in ozd never
started). Last, `rtl-flags`: rtl through a wrapper that adds the soak's rtl-only flags,
`--memory-timing kria --cache 65536`, to `--quux`'s machine, still asked
what it runs (16) and so over TCP, with the stand-in ozd never started; its
setup is on rtl, about 5 minutes more. A stand-in ozd that notes each start
and exits is given to every run, `files.sh`'s too, as `LISPM_CHECK_OZD` and
as the first `ozd` on `PATH`, and the last case, `no-ozd`, wants it never
started. The Chaos cases `chaos-own` and `variable` (on a band from before
R3, `LISPM_CHECK_TEST_CHAOS_BAND`) and the CADR's `cadr-default` left with
main's Chaos and ozd path, `rev15-default` with revision 15.
`LISPM_CHECK_TEST_TOOL` names another copy of the tool to test, a planted
one say. About 5 minutes on micro. Last it runs `files.sh` with the same
arguments.

`tools/lispm-check-test/files.sh` is the self-test of
[`--network files`](#--network-files), which needs no tap and runs alone too:
`files-16` (with `LISPM_CHECK_TAPS` naming no tap: status 1 with every verdict of `expected-files.txt` for
`files.cases`; the setup typed at the glass TTY and took its checkpoint at
the prompt, neither machine had a network flag, the check's no glass TTY, no
ozd, the tap pool not used, the key ending `-files-`), `files-16-again` (the
checkpoint resumed, no setup), `files-16-rtl` (on rtl), and the plants (the
lanes ran on revision 15, `LISPM_CHECK_TEST_QUUX15`, as `files-15`,
`files-15-again` and `files-15-rtl`, until it left these tools): `held`, an HC-SERVE that
holds a file open around its loop (`hc-serve-held.lisp` appended), whose
setup must fail on the checkpoint refused for a handle open; `early`, a tool
whose `FileSession` takes `hc-K.ans` without waiting for `hc-K.done`, which
`files.cases`'s `early-answer` case must catch; then `ozd-server`
(`--file-server ozd` refused by name) and `harness` (`LISPM_CHECK_NETWORK=files` refused by
`harness_network`); `cadr`, `--network files` refused on the CADR's copy of
the tool, left when main's tools stopped offering the CADR. About 4 minutes
on micro, and 10 more for the rtl lane.

`tools/lispm-check-test/harnesses.sh W16 DISK UBIN [ENGINE]` checks
the default of the tools that take the network through `harness_network`:
`tools/system-check/warm-boot` and `tools/microcode-check/generational-save`
(whose session and boot are `tools/cross-build/run`'s), each run over TCP
with a stand-in ozd, given as `LISPM_CHECK_OZD` and as the first `ozd` on
`PATH` (as `--ozd` until ozd left these tools), never started (and, until
revision 15 left these tools, once on 15 over Chaos with ozd, `W15` and
`OZD`). `DISK` holds a band with the network
current in LOD1, LOD2 free for the save; `LISPM_CHECK_TAPS` and
`LISPM_CHECK_PORTS` must be set; `LISPM_CHECK_TEST_TREE` names another
tree's tools to test. About 15 minutes on micro.
