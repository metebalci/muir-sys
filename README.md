# muir-sys

**The Lisp Machine system for QUUX,** the machine that muir and muir-fpga
evolve from the MIT CADR, continuing where System 100 left off and evolved
step by step.

The starting point is the MIT CADR and its system as MIT last left it. **System
release 99.32** is the content of a backup of OZ recovered by the
[Tapes of Tech Square](https://archivesspace.mit.edu/repositories/2/resources/1265)
project, "possibly the last backup and version of the Lisp Machine for the
CADR". This system is forked from **System 100**, [LM-3](https://tumbleweed.nu/lm-3/)'s
release of that content, brought up and fixed, under the AGPL.

The aim is to evolve the system, not to change it radically. It moves on in
steps, each a release built from this repository. **Backward compatibility is
not an aim, but System 1001 will always be supported by muir and muir-fpga.**

**System 1001 is the last release for the CADR,** which stays on it with MIT's
microcode 323. From System 1002 the system runs only on QUUX.

## QUUX

QUUX is the CADR evolved, the machine muir runs with `--machine quux` and
muir-fpga builds. It keeps the CADR's architecture and improves on it in two
directions: performance and capacity, and modern computing, such as the
display's resolution, block storage and the network. Each improvement is a
hardware revision, and the machine says which it has: `MACHINE-ID`, a
functional source, gives the revision, and its **feature page**, one read-only
page of I/O space, gives its sizes. The system reads both at boot rather than
assuming them.

What System 1002 uses so far:

| | QUUX | the CADR |
|---|---|---|
| level-1 map entry (revision 1) | 6 bits: 63 level-2 blocks, 504K words mapped at once | 5 bits: 31 blocks, 248K words |
| PDL buffer (revision 2) | 16K words | 1K words |
| multiply and divide (revision 3) | one instruction each | 32 steps |
| the 60-cycle clock (revision 4) | the processor's own tick | the display's vertical interrupt |
| display | MONO TV, a 1-bit frame buffer, 1920 by 1080 by default, sized from the feature page | 768 by 963, with a sync program |

The microcode is **microcode 1000**, the first change to the microcode itself,
which stayed 323 while it was MIT's, and the machine boots it with **boot
PROM 1000**. Both are for QUUX alone and stop on anything else, as a System
1002 band does. [`docs/release-1002.md`](docs/release-1002.md) records each
change as it is made; [`docs/booting.md`](docs/booting.md) follows a machine
from power-on to Lisp.

## System 1002

System 1002 is in progress on `main` and not yet released: the first system for
QUUX, as above, with the herald naming the site and the machine, and fixes
taken from the System 2000 line.

## System 1001

System 1001 removes unused machine and host support, dead interfaces and
obsolete compatibility code. It fixes the error handler and TELNET input,
and adds unattended cold loading through a generated
`SYS: SITE; COLDRUN LISP` script. The system is built by a clean recompile,
a new cold load, `QLD` and a saved band.
[`docs/release-1001.md`](docs/release-1001.md) records the changes.

## System 1000

**System 1000** is System 100 fixed and cleaned up: the same sources and
microcode 323, the faults that stopped it rebuilding itself repaired, the
material that is not MIT's left out. It continues where System 100 left off,
and the number steps from 100 to 1000.

In short, the fault that stopped a cold load in silence and MINI's two stream
faults are fixed; the routing table covers every subnet, and MINI finds its
file server by itself; about forty faults are fixed across the tree, and 36 of
LM-3's later fixes are taken, one at a time; the tape,
LMFILE and Xerox printing systems are gone; only System is patchable; and what
is not MIT's, or not wanted, was never imported. The band is compiled by the
system itself, and the microcode is assembled from its sources.
[`docs/release-1000.md`](docs/release-1000.md) records every change.

## Releases

**There are no patches, only releases.** Every change reaches a band through a
full rebuild of the system from its sources, so a release is a whole number ---
1000, 1001, 1002 --- and never 1000.1. A running band is not updated in place;
it is replaced by the next release's band. The Lisp Machine's patch system
remains in the tree, because it keeps track of the release number, but no patch
files are written or loaded.

Each release is published on this repository's Releases page with two files: a
disk pack ready to boot, and the system's sources with their assembled
microcode and an example site. Its README gives their checksums and how to run
them.

## The machine it runs on

This is the system. Three projects provide the machine:

| | |
|---|---|
| **muir** | the software simulator, of the CADR and of QUUX |
| **muir-fpga** | the hardware simulator |
| **ozd** | the Chaosnet services daemon: files, time, host table, TELNET |

## Layout

| | |
|---|---|
| `sys/` | the Lisp Machine sources, as the machine sees them: `SYS: SYS2;` is `sys/sys2/` |
| `site/` | the site files a machine loads, for the example site `MIT` |
| `docs/` | how the system is built, and what has been found out about it |
| `pages/` | the project's web page and its release notes, written by hand, published at <https://muir-sys.metebalci.com/> |

## Documents

- [`docs/building.md`](docs/building.md) --- building the system from source:
  compiling, the cold load, `QLD`, saving a band, assembling the microcode, and
  writing a release pack.
- [`docs/release-1002.md`](docs/release-1002.md) --- every change System 1002
  makes to System 1001, recorded as it is made.
- [`docs/booting.md`](docs/booting.md) --- how a machine boots, from power-on
  through the boot PROM and the microcode to the first macroinstruction.
- [`docs/release-1001.md`](docs/release-1001.md) --- every change System 1001
  makes to System 1000.
- [`docs/release-1000.md`](docs/release-1000.md) --- every change System 1000
  makes to System 100.
- [`docs/upstream-changes.md`](docs/upstream-changes.md) --- the fixes LM-3 made
  after System 100, and which of them were taken.
- [`docs/fonts.md`](docs/fonts.md) --- the fonts are the last binaries with no
  source here: what became of their sources, and where copies of some survive.

Faults found along the way are logged as issues in this repository.

## How it is developed

The system sources are MIT's, by way of LM-3. The changes here, the builds and
the documents here are made by [Claude Code](https://claude.com/claude-code),
on Anthropic's Opus and Fable models.

## Copying

muir-sys is licensed under the **GNU Affero General Public License, version 3 or
later**; see [`LICENSE`](LICENSE). LM-3 released System 100 under those terms,
and it continues under them.

The files carry MIT's copyright notices, the code having been recovered from
MIT's backup tapes, and a few carry other notices. [`NOTICE`](NOTICE) sets out
where the sources come from, the terms they are distributed under, and every
notice that is not MIT's.
