# muir-sys

**This is a continuation of the Lisp Machine project.**

I take the CADR where it was left in the early 1980s, and the software where
MIT left it: **System release 99.32**, the content of a backup of OZ recovered
by the [Tapes of Tech Square](https://archivesspace.mit.edu/repositories/2/resources/1265)
project --- "possibly the last backup and version of the Lisp Machine for the
CADR". [LM-3](https://tumbleweed.nu/lm-3/) brought that content up as **System
100**, fixing typos and a few critical errors, and released it under the AGPL.
It forks there and continues.

This system deliberately does **not** take LM-3's later releases. Between System 100
and System 304, a great deal of LMI and Gigamos's System 130 was merged in:
252 files of that tree take their content from those imports, 247 of them
saying nothing about it, and 141 carry patch headers written at LMI or Gigamos
Cambridge in 1987 and 1988. System 100 has none of it. Keeping the lineage one
thing --- MIT's, from the tapes --- is worth more here than the later fixes,
which can be taken one at a time on their merits.

**I do not aim to keep compatibility.** The CADR architecture may change, the
PROM may change, the microcode may change, and the system will change.

Release **1000** is System 100 fixed and cleaned up: the same sources and
microcode 323, the faults that stopped it rebuilding itself repaired, the
material that is not MIT's left out. The number
steps from 100 to 1000 to say what it is --- the same lineage, a different
project.

## What 1000 changes from System 100

In short: the fault that stopped a cold load in silence and MINI's two stream
faults are fixed; the routing table covers every subnet and MINI finds its
file server by itself; about forty faults are fixed across the tree; the
tape, LMFILE and Xerox printing systems are gone; every system but System is
unpatchable; and what is not MIT's, or not wanted, was never imported.
[`docs/release-1000.md`](docs/release-1000.md) records every change.

## The other three projects

This is the system. Three projects around it carry the machine it runs on:

| | |
|---|---|
| **muir** | the software simulator |
| **muir-fpga** | the hardware simulator |
| **ozd** | the Chaosnet services daemon |

## Releases

**There are no patches, only releases.** Every change reaches a band through a
full rebuild of the system from its sources, so a release is a whole number ---
1000, 1001, 1002 --- and never 1000.1. A running band is never updated in place;
it is replaced by the next release's band.

The Lisp Machine's patch system remains in the tree, because it is what keeps
track of the release number, but this system writes no patch files and loads none.

A release is published on this repository's Releases page as a disk pack ready
to boot, the sources with the microcode, and the example site, with a README
giving their checksums and how to run them.

## Layout

| | |
|---|---|
| `sys/` | the Lisp Machine sources, as the machine sees them: `SYS: SYS2;` is `sys/sys2/` |
| `site/` | the site files a machine loads, for the site `Z54` |
| `docs/` | how the system is built, and what has been found out about it |

## Where it is going

1. Hardware multiply and divide, in one ALU step instead of 32.
2. No disk paging, with 16MW of physical memory.
3. 720p, then 1080p.
4. TCP/IP, after the sources and patches can load over it.

## Documents

- [`docs/building.md`](docs/building.md) --- building the system from source:
  the cold load, `QLD`, and saving a band, with what had to be changed to make
  System 100 rebuild itself.
- [`docs/release-1000.md`](docs/release-1000.md) --- every change release 1000
  makes to System 100.
- [`docs/upstream-changes.md`](docs/upstream-changes.md) --- the fixes LM-3 made
  after System 100, and which of them were taken.
- [`docs/fonts.md`](docs/fonts.md) --- the fonts are the last binaries with no
  source here, what became of their sources, and where copies of some survive.

Faults found along the way are logged as issues in this repository.

## How it is developed

The system sources are MIT's, by way of LM-3. The changes here, the builds and
the documents here are made by [Claude Code](https://claude.com/claude-code),
on Anthropic's Opus and Fable models.

## Copying

muir-sys is licensed under the **GNU Affero General Public License, version 3 or
later**; see [`LICENSE`](LICENSE). LM-3 released System 100 under those terms,
and it continues under them.

The tree's own files carry MIT's copyright notices, the code having been
recovered from MIT's backup tapes, and a few carry other notices.
[`NOTICE`](NOTICE) sets out where the sources come from, the terms they are
distributed under, and every notice that is not MIT's.
