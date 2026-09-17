# muir-sys

**This system makes the Lisp Machine usable today:** on current hardware,
with current displays and networks, and developed the way software is developed
now.

The starting point is the MIT CADR and its system as MIT last left it. **System
release 99.32** is the content of a backup of OZ recovered by the
[Tapes of Tech Square](https://archivesspace.mit.edu/repositories/2/resources/1265)
project, "possibly the last backup and version of the Lisp Machine for the
CADR". This system is forked from **System 100**, [LM-3](https://tumbleweed.nu/lm-3/)'s
release of that content, brought up and fixed, under the AGPL.

The aim is not preservation. The machine is meant to run on an FPGA and in a
simulator rather than on 1980s boards, to use memory, screens and networks of
today's sizes and kinds, and to be built, versioned and released reproducibly
from a git repository. **Compatibility is not kept:** the CADR architecture,
the PROM, the microcode and the system are all open to change.

## Release 1000

Release **1000** is System 100 fixed and cleaned up: the same sources and
microcode 323, the faults that stopped it rebuilding itself repaired, the
material that is not MIT's left out. The number
steps from 100 to 1000: the same lineage, a different project.

In short, the fault that stopped a cold load in silence and MINI's two stream
faults are fixed; the routing table covers every subnet, and MINI finds its
file server by itself; about forty faults are fixed across the tree; the tape,
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
| **muir** | the software simulator |
| **muir-fpga** | the hardware simulator |
| **ozd** | the Chaosnet services daemon: files, time, host table, TELNET |

## Where it is going

1. Hardware multiply and divide, in one ALU step instead of 32.
2. No disk paging, with 16MW of physical memory.
3. 720p, then 1080p.
4. TCP/IP, once the sources can be loaded over it.

## Layout

| | |
|---|---|
| `sys/` | the Lisp Machine sources, as the machine sees them: `SYS: SYS2;` is `sys/sys2/` |
| `site/` | the site files a machine loads, for the example site `Z54` |
| `docs/` | how the system is built, and what has been found out about it |

## Documents

- [`docs/building.md`](docs/building.md) --- building the system from source:
  compiling, the cold load, `QLD`, saving a band, assembling the microcode, and
  writing a release pack.
- [`docs/release-1000.md`](docs/release-1000.md) --- every change release 1000
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
