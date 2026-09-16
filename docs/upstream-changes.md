# What this system takes from upstream, and what it refuses

This system forks LM-3's **System 100**, which is the MIT tape content of release 99.32
brought up and typo-fixed. LM-3 went on to releases 300 through 304. Those are
not taken wholesale, and this file is the record of what is taken instead, one
change at a time, with the reason.

The rule is simple: a change is a candidate if it corrects wrong behaviour in
MIT's code. It is refused if it brings material from LMI or Gigamos's System
130, if it is a style sweep, or if it is release bookkeeping for a release this system
does not have.

## Why not just take 304

Between System 100 and the fork point there are 889 commits. Of the files in
the 304 tree, **252 take their content from imports of System 130, of a later
"DJ tape", or of LMI's own programs**; 247 of them say nothing about it in
their headers, and 67 carry an MIT notice over System 130 content. **141 files
carry patch headers written "at site LMI Cambridge" or "at site Gigamos
Cambridge" in 1987 and 1988**, on machines named in their own banners as
Lambdas with SDU ROMs. System 100 has none of this: one file,
`io/format-macro.lisp`, carries an LMI notice, and its own header grants anyone
use and modification.

That is the whole of the reason. The later fixes are worth having; the lineage
is worth more, and the fixes can be taken singly.

## What System 100 changed from 99.32

The base is not quite the tape content, and the difference is worth knowing,
since this system inherits it. 101 files differ between release 99.32 and System 100,
and they fall into four kinds.

**Typo fixes, the bulk of it.** 42 files differ by four lines or fewer and 35
more by twenty or fewer. They are what the release note says they are:
`:WHICH-OPERARATIONS` corrected to `:WHICH-OPERATIONS` in three places in
`io/print.lisp`, `ARGS` corrected to `FORMAT-ARGS` in three places in
`sys/ltop.lisp`, and so on through the tree.

**Duplicate definitions removed.** `sys/qmisc.lisp` loses 649 lines, the ROOM
functions, which `sys2/describe.lisp` defines as well.

**Things that are not code:** the bug-mail archives in `doc/`, `zmail/` and
`zwei/`, MIT's own site files, and the microcode tables in `ubin/`, which are
regenerated rather than edited.

**Bring-up workarounds, marked `;;;---!!!`.** Ten files carry them, and they
are the part this system should care about, because each is a question left open rather
than answered:

| File | What the note says |
|---|---|
| `sys/fspec.lisp` ([#11](https://github.com/metebalci/muir-sys/issues/11)) | **the whole file disabled** with `#\|`, because loading `SYS2; DEFSEL QFASL` during `SI:QLD` barfed in `INTERNAL-FUNCTION-SPEC-HANDLER` |
| `sys/qmisc.lisp` ([#11](https://github.com/metebalci/muir-sys/issues/11)) | the functions above "should be moved to `SYS: SYS; FSPEC`, but due to issues (see FSPEC) hasn't been done just yet" |
| `eh/eh.lisp`, `eh/ehc.lisp` ([#16](https://github.com/metebalci/muir-sys/issues/16)) | "No way known to do LOCF on SG-PLIST" |
| `sys2/macarr.lisp` ([#15](https://github.com/metebalci/muir-sys/issues/15)) | "This version of STORE from NIL is not MACLISP compatible", the code disabled |
| `sys/qrand.lisp` ([#13](https://github.com/metebalci/muir-sys/issues/13)) | "MAKE-COLD doesn't support complex types" |
| `cold/mini.lisp` | the file server's address hard-coded to OZ's, since restored to the tape's version (`bdf0d71`) |
| `network/host.lisp`, `sys/eval.lisp`, `io/file/logical.lisp` ([#12](https://github.com/metebalci/muir-sys/issues/12)) | "are these still used?" |
| `sys/sysdcl.lisp` ([#14](https://github.com/metebalci/muir-sys/issues/14)) | "How is PRESS-FONTS; FONTS WIDTHS generated?" |

Those are this system's inheritance and its first list of real work: a release that
calls itself fixed and cleaned up should answer them rather than carry the
notes forward, and each now has an issue. None is a reason to prefer System
304, which carries most of them too.

`FSPEC` is the one to read first. The file is 689 lines and all of them are
inside the `#|`, so it defines nothing --- yet the cold-load file list still
loads it (`sys/sysdcl.lisp:466`). The tape defines those 37 forms twice, in
`fspec.lisp` and again in `qrand.lisp` and `qmisc.lisp`, because MIT was moving
them into a file of their own and had not finished. Finishing that move is
release 1000's kind of work.

## The 889 commits, classified

| | Commits | Disposition |
|---|---|---|
| LMI / System 130 / DJ-tape material | 336 | refused |
| Genuine bug fixes | 75 | candidates, ruled on one at a time |
| New features | 45 | considered singly; most refused |
| Cleanups and modernisation | 323 | refused; no behaviour change |
| Release bookkeeping | 110 | not applicable |

Of the 75 fixes, **22 are on files that exist in 304 only because of an
import**. Most of those faults predate the import and can be re-applied by hand
to the MIT-lineage file; they are marked below.

The classification was made by reading the commits, and no entry is applied
before the change is read against this system's own source: a commit message is a claim,
not evidence.

## Changes made here where upstream made one too

These were made on their own merits. Neither is a cherry-pick.

| Change | Commit | Note |
|---|---|---|
| `network/chaos/chsncp.lisp`: routing table 96 → 256 subnets | `e4cc865` | A Chaos subnet is the high byte of a 16-bit address, so 256 is the whole range and 96 leaves two thirds unreachable. This site is on subnet 376, muir-fpga's boards likewise, so nothing here could run as it stood. LM-3 changed the same constant; the change is obvious enough that both arriving at it means nothing. |
| `cold/mini.lisp`: work out the file server's address instead of naming it | `bdf0d71` | **A restoration, not an import.** Release 99.32 --- the tape content --- computes the address from the host of the file being compiled. System 100 replaced that with OZ's own `#o3060` on subnet 6, with a `;;;---!!!` note admitting it. This system puts MIT's version back. LM-3 also reverted to it, later. |

## Candidates: the 75 fixes

Ruling: **+** to take, **-** to skip, blank while undecided. Nothing is applied
while its row is blank.

### cold/

| Commit | File | Fixes | Ruling |
|---|---|---|---|
| 57a47ae | qdefs.lisp | typo | |
| 48634b1 | qcom.lisp | `SIZE-OF-HARDWARE-M-MEMORY`, nested `#+/#-` returned multiple values | |
| abcb2a2 | global.lisp | `WITH-LIST` and `WITH-LIST*` never exported | |

### sys/

| Commit | File | Fixes | Ruling |
|---|---|---|---|
| ade79f7, 3175b7b | qmisc.lisp | `ARRAY-POP` typo | |
| f44580b | genric.lisp | `KEY-FETCH`, wrong LAMBDA optimisation | |
| ff43599 | qcfile.lisp | `COMPILE-FILE` keyword name not Common Lisp's | |
| 96d031e | ltop.lisp | `LISP-REINITIALIZE` typo | |
| d607c71 | eval.lisp | `LETF`/`LETF*`, stray parens round `WITH-STACK-LIST` | |
| 405f037 | qcopt.lisp | typo in a warning string | |

### sys2/

| Commit | File | Fixes | Ruling |
|---|---|---|---|
| 453f571 | advise.lisp | `ADVISE-FIND-SLOT` typo | |
| 4190c02 | resour.lisp | `DEFRESOURCE` deinitializer typo | |
| cd210c8 | defsel.lisp | `DEFSELECT-INTERNAL` `SETF` typo | |
| d1ca3e1 | cmany.lisp | missing `;` on the attribute line | |
| 94c738c | flavor.lisp | guard `ZWEI:SORT-COMPLETION-AARRAY` | |
| b30b74f | analyze.lisp | `MAKE-AREA` ran twice *[imported file]* | |
| c7aa8f0 | analyze.lisp | wrong data-type constant scanning FEFs *[imported file]* | |
| b6e3469 | login.lisp | hard error when the home directory is absent *[imported file]* | |
| ad3ced8 | maksys.lisp | `CANONICALIZE-PATHNAME` unspecified type *[imported file]* | |
| ef01571, c55eac6 | maksys.lisp | CWARNS file name collision *[imported file]* | |

### io/, io1/

| Commit | File | Fixes | Ruling |
|---|---|---|---|
| 5490cea, b6212bc | file/pathnm.lisp | `DEFAULT-PATHNAME` broken when not logged in | |
| 988bbb6 | file/pathnm.lisp | `merge-pathname-components` typo | |
| bec8aa9 | file/open.lisp | `pathname-completion-list` case bug | |
| 712df11 | file/pathst.lisp | missing `UNIX-PATHNAME-MIXIN :STRING-FOR-DIRECTORY` | |
| 54df5e4 | file/access.lisp | `:DELETE-MULTIPLE-FILES` | |
| bb1f448 | dledit.lisp | `EDIT-DISK-LABEL` never read the label | |
| fab8159 | dledit.lisp | END character encoding | |
| ddc80cc | io1/swar.lisp | `PROCESS-CREATE` → `MAKE-PROCESS` | |
| e71b341 | io1/time.lisp | run `INITIALIZE-TIMEBASE` on `:WARM` and `:NOW` *[imported file]* | |

### network/

| Commit | File | Fixes | Ruling |
|---|---|---|---|
| 9cc9b5d, 9c27c1a, 36af1e4 | chuse.lisp | `CHAOS-UNKNOWN-HOST-FUNCTION` typos, numeric host names | |
| 6b34da1 | chsaux.lisp | `POLL-HOSTS` hung HOSTAT on an unknown host | |
| 9f3c0e9 | peekch.lisp | host lookup for address 0 | |
| a59f26c | peekch.lisp | `HOSTAT-FORMAT-ANS` argument order | |
| 3a4a2f9, 7ca0409 | --- | HOSTS TEXT moved to `SYS: SITE;` | |
| fc0d7c4, 9de205d | chsncp.lisp | retransmission TIME variable scope *[imported file]* | |
| ffa42f2, 29726be | host.lisp | ZWEI host wrongly used as `ASSOCIATED-MACHINE` *[imported file]* | |
| c594ed8 | host.lisp | two fixes in one: `CLI:SOME` absent in the cold load, and a true-return bug. Split when applying *[imported file]* | |

### window/ --- every one on an imported file

| Commit | File | Fixes | Ruling |
|---|---|---|---|
| 812356a, 2eb4710 | menu.lisp | `:MOUSE-MOVES` crash | |
| 2fc7825 | tscrol.lisp | `:SETUP` typo | |
| 0300fb4 | shwarm.lisp | Control-N motion bug | |
| 66438e6 | shwarm.lisp | `SI::VIDEO-BOARD-TYPE` undefined | |
| a0a0ef2 | wholin.lisp | prints NIL state | |
| c2f1469, a8511d6 | --- | run-light initialisation on the CADR | |
| ef8bf89 | mouse.lisp | CADR mouse registers | |
| b3afdfd | tvdefs.lisp | `:VOLATILITY` to `MAKE-AREA` | |
| ca35ad6 | inspct.lisp | `EH:ABORT-OBJECT` | |
| 6f5c43f, 2b90b70, a027152 | --- | bogus `SYS:DOWNWARD-FUNCTION` declarations | |
| 19607ec | cold.lisp | restores the old CADR keyboard decoder and comments out the LMI Explorer path | |
| fc010ae | rh.lisp | Control-Shift-A | |

### zwei/ --- every one on an imported file

| Commit | File | Fixes | Ruling |
|---|---|---|---|
| 7b08eef, 2eab7b6, 69665b1 | comtab.lisp | `COMMAND-LOOKUP`/`COMMAND-STORE` character lossage | |
| 9b8d890 | comtab.lisp | command-name typos | |
| fde0942 | pated.lisp | `FINISH-PATCH` interleaved Reason lines | |
| ff2c2e7 | come.lisp | END character encoding | |

### file/, demo/, sysdcl

| Commit | File | Fixes | Ruling |
|---|---|---|---|
| 6eeb9cd | demo/doctor.lisp | no `QUIT` function | |
| 0086355 | demo/cafe.lisp | wrong `color:` entry point | |
| 10aa70b | sys/sysdcl.lisp | FED missing host | |
| d98d9bd | file/server.lisp | `ADD-INITIALIZATION` name must match the Chaos RFC *[imported file]* | |
| c1f37f7 | file2/server.lisp | `SI:PARSE-HOST` barfs during QC *[imported file]* | |

## Features, for the record

Refused by default, but these are the ones a maintainer might want: European
DST and CET/EEST timezones (7d3b5d7, 2069d1b, 509b574); global Chaosnet
broadcast packets (08f7ef5); `CHAOS-UNKNOWN-ADDRESS-FUNCTION` (19b917f,
9dba8d0, 088b0d2); a Chaos MINI server (5246061); the dpANS3 symbol list in
`cold/common-lisp.lisp` (4882cda, d7fda67); `MERGE-SORT` (c60e1ea); `LETF-IF`
(37a2876, a09eea4, 0590b79); `DEFVAR-RESETTABLE` (ac2fa70).

`5246061`, the MINI server, is worth a second look: ozd serves MINI here, so
a machine-side server is not needed, but it documents the protocol from the
serving end.

## What the refused buckets contain

**LMI and System 130 material (336).** The imports themselves --- Tape,
Local-File 77 and File-Server 26, ZMail 75, ZWEI 128, some 26 `window/` files,
LMI's Site Data Editor, the error-handler restructure --- the roughly 1,100
numbered files they arrived as, the commit that copied 345 of them onto the
live files, and the per-file adaptation commits that followed.

**Cleanups (323).** 163 "De-quote keywords", 18 `SELECTQ` to `CASE`, 18
`MULTIPLE-VALUE` to `MULTIPLE-VALUE-SETQ`, 14 `(FERROR NIL ...)` to `(FERROR
...)`, `MAKE-ARRAY` modernisation, and some sixty commits moving functions
between files to match System 130's layout. No behaviour changes, and the last
group is meaningless without the imports.

**Bookkeeping (110).** Patch files and directories for releases 100.1 through
304.x, version bumps, QFASL churn, and two mechanical commits that delete 1,117
files and restore 1,116 of them.
