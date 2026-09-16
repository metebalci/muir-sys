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

Release **1000.0** is System 100 fixed and cleaned up: the same sources and
microcode 323, the faults that stopped it rebuilding itself repaired, the
material that is not MIT's left out. The number
steps from 100 to 1000 to say what it is --- the same lineage, a different
project.

## What 1000.0 changes from System 100

The sources are System 100's, with microcode 323. Two changes are cosmetic,
three are fixes the machine needed before it would rebuild itself, and one
removes a system whose files are not carried.

- **The name and the number.** `PRINT-HERALD` always says this system
  (`sys/io/disk.lisp`), and the system number is 1000 rather than 304
  (`sys/patch/system.patch-directory`). Nothing depends on the number, and it
  jumped rather than reset so that it could never be confused with MIT's.
- **`sys/sys2/prodef.lisp`:** `SCHEDULER-STACK-GROUP` is declared `NIL` instead
  of unbound. A cold load runs with traps disabled until `LISP-REINITIALIZE`
  turns them on, and `PROCESS-WAIT` reads that variable inside the window; read
  unbound there it trapped, the trap became `ILLOP`, and the machine halted
  with nothing printed at all. ([#6](https://github.com/metebalci/muir-sys/issues/6))
- **`sys/cold/mini.lisp`:** the "Unknown stream operation" error now names the
  operation. It passed the operation to `MINI-BARF` already, but the format
  string had no directive for it, so the one fact needed to diagnose the stop
  was the one fact missing. ([#7](https://github.com/metebalci/muir-sys/issues/7))
- **`sys/cold/mini.lisp`:** both MINI streams now answer `:SEND-IF-HANDLES`,
  which means "send this message only if you handle it". A flavor instance
  answers it through `VANILLA-FLAVOR`, but these streams are closures and have
  to answer for themselves; a cold load stopped on
  `(:SEND-IF-HANDLES :BYTE-SIZE)`, which the stream code asks of any stream.
  ([#7](https://github.com/metebalci/muir-sys/issues/7))

**What is not carried.** The tape system, which wants a drive neither muir nor
muir-fpga has; the Xerox Press printing binaries; `cold/minisr`, the PDP-10
MINI server, whose work ozd does now; and `doc/`, twenty-three megabytes of bug
mail and bboard archives that nothing loads. `lm3-304` in the project's own notes
says where a full copy of System 304 is kept, to copy from when something
turns out to be wanted.

Every change carries a comment in the source saying why. A fourth fault, the
cold load reading site files in the wrong readtable
([#9](https://github.com/metebalci/muir-sys/issues/9)), is worked around in this
site's own files rather than in the system.
[`docs/building.md`](docs/building.md) has the whole procedure.

## The other three projects

This is the system. Three projects around it carry the machine it runs on:

| | |
|---|---|
| **muir** | the software simulator |
| **muir-fpga** | the hardware simulator |
| **ozd** | the Chaosnet services daemon |

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
  System 304 rebuild.
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
recovered from MIT's backup tapes. One file, `sys/io/format-macro.lisp`, is
Lisp Machine Inc.'s, and its own header grants anyone use and modification.
