# Fonts

The 81 files in `sys/fonts` are the only binaries left in the tree that nothing
here can rebuild. The microcode and the boot PROM are generated from
`sys/ucadr/uc-*.lisp` and `sys/ucadr/promh.text`, so `sys/ubin/` is build
output, but the fonts have no source at all. This document records what
happened to the sources, where copies of some of them turn out to survive, and
the two ways to give the tree a font source format again.

## The formats and the tools

`sys/io1/fntcnv.lisp` converts between three forms, and its header names them:
KST is "used for communication with the PDP-10", AST is a text form of stars
and spaces, and FD, the font descriptor, is "a machine resident format". A
fourth pair, AL and AC, appears as well. The system reads and writes all of
them:

| Direction | Function | Where |
|---|---|---|
| read | `READ-KST-INTO-FONT-DESCRIPTOR` | `sys/io1/fntcnv.lisp:575` |
| write | `WRITE-FONT-INTO-KST` | `sys/io1/fntcnv.lisp:824` |
| write | `WRITE-FONT-DESCRIPTOR-INTO-KST` | `sys/io1/fntcnv.lisp:913` |
| write | `WRITE-FONT-INTO-AST` | `sys/io1/fntcnv.lisp:1753` |
| write | `WRITE-FONT-DESCRIPTOR-INTO-AST` | `sys/io1/fntcnv.lisp:1759` |

The font editor FED drives them from its save path
(`sys/window/fed.lisp:2095-2098`), so reading and writing a font file is an
ordinary operation of the system.

What the tree has not got is a build rule. Nothing defines a system that
compiles `sys/fonts/*.qfasl` from anything; the QFASLs are simply committed
binaries. `sys/fonts/times.9rom` is not an exception but an 82nd such binary,
carrying the same QFASL magic as `sys/fonts/cptfont.qfasl` under the ITS file
type `9ROM`. The only real font source in the tree is `sys/demo/wormch.ast`,
the WORM demo font, which serves as a worked example of the AST format. Three
KST fonts in `sys/man` are manual examples, listed as such in the release's own
tape documentation, `doc/lmtape.text`, which this tree does not carry.

## What happened to the sources: `gfr.archiv`

`sys/fonts/gfr.archiv` is not an archive despite its name. It is a plain-text
manifest left behind by ITS's Grim File Reaper, the utility that reclaimed disk
space by copying files to backup tape and deleting them:

> This file is a list of all the stuff which has been Grim File Reaped from
> this directory. The reason for doing this is that Lisp Machines insist on
> believing that these fonts exist (and on trying to load them) as long as
> directory entries exist for them.
>
> Written 5/20/82 by Dulcey.

Its 40 entries each name a file, its type, the tape it went to, the file's own
date, the date it was reaped in parentheses, and who did it:

```
      CPTFON KST    => BACKUP; TAPE GFR5     09/13/79 00:03:12 (01/04/82) MTM
      MEDFNT KST    => BACKUP; TAPE GFR3     05/03/77 01:41:54 (11/19/81) SJOBRG
      TINY   AST    => BACKUP; TAPE GFR5     12/05/80 13:45:56 (08/16/81) MMCM
```

By type they are 13 AST, 7 KST, 15 QFASL, 2 OQFASL, 2 XFILE and 1 CLDFNT, and
they went to seven tapes: GFR1, GFR3, GFR5, GFR6, GFR8, GFR9 and GFR23.
Fifteen are sources for fonts this tree still carries compiled, among them
`CPTFON KST` (tape GFR5), `MEDFNT KST` (GFR3), `TOG KST` (GFR8), `TINY AST`
(GFR5), `43VXMS AST` (GFR23) and `TVFONT CLDFNT` (GFR8). The rest name fonts
that are not in the tree at all any more.

So the sources existed and were deliberately removed in 1981 and 1982, and this
file is the index saying which tape holds which one.

## Where copies survive

The ITS reconstruction project keeps recovered files from the MIT AI Lab's
machines in <https://github.com/PDP-10/its-vault>, laid out one directory per
ITS directory. Among them is `files/lmfont/`, which is `AI: LMFONT;`, described
in its own `-read-.-this-` as the Lisp Machine project's "Fonts (ast, kst, and
qfasl files)". It holds 86 files, 29 of them sources, alongside `files/fonts/`,
`files/fonts1/` and `files/fonts2/`, which are the PDP-10's own font
directories and hold about 200 more KST files.

A working copy of all five directories, 333 files, sits in `lmfont/` at the root
of this repository. It is not committed: `.gitignore` excludes it, because the
material is recovered by others, its copyright is not uniformly MIT's, and it
can be fetched again from the vault at any time. `lmfont/README.md` says what
each subdirectory is.

The sources in `LMFONT;` are:

```
13fg.ast 13fgb.ast 14fr3.kst 16fg.ast 25fr3.ast 40vshd.ast 43vxms.ast
5x5.kst apl14.ast arr10.ast arrow.kst bigfnt.kst bug.kst cm10.ast cm12.ast
cptfon.ast gls7x9.ast hafont.kst mouse.kst sail10.ast swfont.ast tog.kst
tonto.ast tr10.al tr10b.al tr12.al tr12i.al tr14.al tr18.al
```

`cptfon.ast` is a genuine AST source for the system font, 16,819 bytes, and it
opens as the format requires:

```
0 KSTID DSK:LMFONT;CPTFON KST
12 HEIGHT
10 BASE LINE
0 COLUMN POSITION ADJUSTMENT
^L0 CHARACTER CODE DSK:LMFONT;CPTFON KST
3 RASTER WIDTH
8 CHARACTER WIDTH
-2 LEFT KERN
```

Matching those directories against the 81 fonts by name gives **26 exact
matches**: `13fgb`, `16fg`, `18fg`, `20vr`, `25fr3`, `31vr`, `40vr`, `40vshd`,
`43vxms`, `5x5`, `apl14`, `arr10`, `bigfnt`, `cptfon`, `ent`, `mets`, `metsi`,
`mit`, `mouse`, `s35ger`, `tog`, `tr10`, `tr10b`, `tr12`, `tr12i` and `tr18`.

**55 have no candidate anywhere**, including much of what the system actually
uses: `cptfont`, `cptfontb`, `medfnt`, `medfnb`, `tiny`, `search`, `tvfont`,
`narrow`, `abacus`, the whole `hl` family (`hl6`, `hl7`, `hl10`, `hl12`,
`hl12b`, `hl12i` and the rest), and most of the `tr` family (`tr8`, `tr8b`,
`tr8i`, `tr12b`, `tr10i`, `tr18b`). That is consistent with `gfr.archiv`: `MEDFNT KST` went to tape in
November 1981, and the surviving snapshot of the directory was taken after the
reaping, so what the Reaper took is missing there too.

The two archives are independent routes to the same material, so the 81 divide
into three tiers with different confidence:

| Tier | Count | Fonts |
|---|---|---|
| In both archives, so diffable | 12 | `13fgb`, `16fg`, `25fr3`, `40vshd`, `43vxms`, `5x5`, `apl14`, `arr10`, `bigfnt`, `cptfon`, `mouse`, `tog` |
| In the vault only, one witness | 14 | `18fg`, `20vr`, `31vr`, `40vr`, `ent`, `mets`, `metsi`, `mit`, `s35ger`, `tr10`, `tr10b`, `tr12`, `tr12i`, `tr18` |
| In neither, so the round trip | 55 | `cptfont`, `cptfontb`, `medfnt`, `medfnb`, `tiny`, `search`, `tvfont`, `narrow`, `abacus`, the `hl` family, most of the `tr` family, and the rest |

The recoverable total is the union of the two archives, and it is **26**: every
name `sys46/lmfont` matches is also in the vault, so the second archive adds no
font to the set and adds a second witness to twelve of them. Where two witnesses
exist they can be diffed, and a difference between them would itself be a
finding; the 53 have no such check, and anything produced for them by the round
trip is a machine-made reconstruction and should be labelled as one.

The traffic runs the other way as well: **12 sources in `LMFONT;` compile to
nothing this tree ships** --- `13fg`, `14fr3`, `arrow`, `bug`, `cm10`, `cm12`,
`gls7x9`, `hafont`, `sail10`, `swfont`, `tonto` and `tr14`. Fonts whose sources
outlived their binaries, the opposite case to the 53.

The same directory survives by a second route, in an older MIT source tree held
by the muir project as `sys46/lmfont`: 85 files, whose `cptfon.ast` opens with
the same four lines as the vault's. It matches only 12 of the 81, so it does not
displace the vault, but it is an independent witness for those twelve rather
than another copy of the same distribution.

### `CPTFON` is not `CPTFONT`

The tree ships `cptfon.qfasl`, `cptfont.qfasl` and `cptfontb.qfasl` as three
different files of three different sizes, and the recovered `cptfon.ast` is the
source of the first only. The first is the cold load's font, listed as
`SYS: FONTS; CPTFON QFASL` in `COLD-LOAD-FILE-LIST`
(`sys/sys/sysdcl.lisp:500`), and the tree says of it in as many words:

> These are the source files from which the cold load band is constructed. The
> only COLD-LOAD-FILE-LIST file not present is CPTFON, which as a font file
> doesn't have a source. --- `sys/sys/sysdcl.lisp:621-623`

So the one font the sources single out as having no source is the one now
recoverable. `CPTFONT`, which 33 files in the tree name and which the window
system actually runs on, is in the leftover tier and has no source in either
archive. A name-based analysis hides that difference quietly, which is why the
two are separated here.

Two cautions before treating a recovered file as the source of a font here.
The ITS name is six characters, so `CPTFON` is this tree's `CPTFONT` and the
match is by truncation, not identity; and these files are snapshots from around
1978 to 1982, while the compiled fonts in `sys/fonts` come from System 100, so
a recovered source may be an earlier version of the font rather than the one
that was compiled. Both are settled the same way, by converting the file and
comparing the result with the loaded font bitmap for bitmap.

## Searching further

- **PDP-10/its-vault** is the first place to look, and a file is fetched
  straight from it at
  `https://raw.githubusercontent.com/PDP-10/its-vault/master/files/lmfont/<name>`.
- **Tapes of Tech Square (ToTS)** is MIT's collection of backup tape images and
  extracted files from the AI Lab and LCS, 1973 to the early 1990s, held by MIT
  Distinctive Collections and catalogued in MIT ArchivesSpace. The LM-3 sources
  this fork descends from came from it, so it is the right place to ask for a
  tape that the vault does not have. Access goes through the department, and
  copyright is not uniformly held by MIT.
- **Tools:** `itstar` (<https://github.com/PDP-10/itstar>) reads ITS DUMP tape
  images, and `larsbrinkhoff/pdp10-its-disassembler` includes `ast.c`, which
  converts fonts to AST format outside the machine.

Whether the GFR tapes themselves survive is unknown. They are ITS backup tapes,
not the release tapes that carried the system, and nothing found so far names
them.

## The two ways forward

1. **Recover.** Take the 26 sources from `LMFONT;` and the PDP-10 font
   directories, convert each and check it against the compiled font. Every one
   that matches is a real source, with its original provenance.
2. **Round trip.** For the 53 with no surviving source, load the compiled font
   and write it back out with `WRITE-FONT-INTO-AST`. AST is text, so the result
   can be read, diffed and regenerated, which the QFASL cannot. What is lost is
   provenance rather than content: a dump records what the compiled font holds,
   not what the original said, and whatever the format cannot carry is already
   gone.

Either way the first step is the same and is falsifiable: write one font out,
read it back, and compare it with the original. If the round trip is not exact,
the whole plan stops and the binaries stay. metebalci/muir-sys#10 tracks this.
