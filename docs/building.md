# Building the system from source

This is how a new world is built from the tree: compile the sources, make a cold load, boot it, load the rest of the system and save a band. It follows the tree's own code, and each claim cites a file and line.

**System 1001 verification (2026-09-18):** clean compilation, fresh cold
loading, unattended QLD and saved-band boot checks passed. The main SYSTEM
compile took 2h17m36s; MAKE-COLD took 5m16s; the successful unattended QLD
took 25m25s. LOD4 booted as System 1001 with microcode 323, passed SYS file
access, and the regenerated WORM font matched its AST source. UCADR and PROM
machine outputs matched their previous assemblies, as did both diagnostic
memory images and symbol sets.

**Rebuild of both releases (2026-09-22 and 23):** System 1000 and 1001 were
rebuilt from their tags, from trees extracted from the release archives, each
on its own machine and ports. The SYSTEM compiles took 2h27m each. MAKE-COLD
took 5m33s for 1001 and 6m45s for 1000. 1001's QLD ran unattended in 25m26s;
1000's was typed at the console and reached a partition size of 20842 blocks.
Reassembled microcode matched each release's `ucadr.mcr`, `.tbl` and `.locs`
byte for byte. A copy of each release pack booted against the extracted
sources.

**Earlier System 1000 verification:** verified end to end twice on 2026-09-16. First from a stock System 100 band on the bootstrap subnet; then, the same night, by the 1000 band rebuilding the final tree on the site's own subnet 376, from a tree with every compiled file removed. That second build compiled SYSTEM, made a cold load, loaded it with `QLD` to a partition size of 20842 blocks, and saved a band that boots as "LMI System, band 1 of LISPM-1 / Experimental System 1000 / Microcode 323" and answers `(1000 "177202" 65153 256)`.

| Step | Result |
|---|---|
| Readtables, SYSTEM, ZWEI, cold-load builder | 281 compiled files; SYSTEM took 6511 s |
| Cold load onto LOD3 | built, boots |
| `QLD` | inner system and site files over MINI, then the rest over FILE |
| Object-use analysis | 10 minutes 35 seconds |
| Size of the finished world | 20614 blocks |
| Saved band | LOD5, "Exp 1000.0", boots and answers |

## Bootstrapping on the System 100 base

This tree is System 100's, and a world of the same lineage is the right thing
to compile it with. LM-3 publishes one: the `system-100-0` release, a pack
image with a checksum, whose band is "Exp 100.0" on LOD2 with microcode 323 in
MCR1. Fetch it, copy it somewhere of your own --- a file service pointed at a
fetched tree will write into it --- and boot that.

**Chaos addresses.** That band's routing table holds 96 subnets
(`network/chaos/chsncp.lisp`, before the change here), so it cannot run on subnet
376 or any subnet from 96 up: it traps as the network starts. Bootstrap on
subnet 6, where the release's own host table already expects a file host at
`3060` and a Lisp Machine at `3050`. Run the server as OZ at 3060 and the
machine at 3050, and the stock band knows OZ without a site edit. The band this system
builds has the larger table and can then move to 376.

**Pointing it at the tree.** No site file is needed to compile, only the
translations, which can be typed:

```lisp
(login "LISPM" "OZ" t)
(fs:set-logical-pathname-host "SYS" :physical-host "OZ"
  :translations '(("SITE;" "//site//") ("*; *; *;" "//sys//*//*//*//")
                  ("*; *;" "//sys//*//*//") ("*;" "//sys//*//")))
```

Every slash is doubled because the TELNET listener reads traditional syntax.

**There is no SYSTEM-MACROS here.** That system is a System 30x addition; this
base does not define it, and asking for it gets "LOAD could not find any file
related to SYS: SITE; SYSTEM-MACROS SYSTEM". The job it did --- compiling
SYSTEM's definition files before anything tries to load them --- is done by
hand instead, in the order SYSTEM's own ALLDEFS module lists them
(`sys/sysdcl.lisp:10-16`):

```lisp
(qc-file "SYS: SYS2; DEFMAC LISP")
(qc-file "SYS: SYS2; LMMAC LISP")
(qc-file "SYS: EH; ERRMAC LISP")
(qc-file "SYS: SYS2; STRUCT LISP")
(qc-file "SYS: SYS2; SETF LISP")
(qc-file "SYS: SYS; TYPES LISP")
```

**Then the systems**, with the version left where it is:

```lisp
(make-system 'system :recompile :noload :noconfirm :nowarn :no-increment-patch)
```

**`:NOWARN` rather than `:DEFAULTED-BATCH`.** Both stop the build asking
questions, but they are not the same thing. `:NOWARN` (`sys2/maksys.lisp:474`)
sets four variables and opens no file: `INHIBIT-FDEFINE-WARNINGS` to
`:JUST-WARN`, more-processing off, batch mode on, and `*QUERY-TYPE*` to
`:NOCONFIRM`. `:DEFAULTED-BATCH` (`:482`) does all that *and* writes a compiler
warnings database to the login user's home directory on the file server ---
`/lispm/cwarns.lisp` for user LISPM. If the server has no such directory to
write into, the build stops at once with "Access to file denied", which is what
happened here on the first attempt; a server that reports it differently says
"Directory not found" instead. `:BATCH` implies `:NOWARN` (`:1564`), not the
other way round.

So either give the server a writable home directory for the user, or ask for
`:NOWARN` and do without the database --- which this repository ignores anyway.

### What the System 100 build met, in order

- **`SYSTEM-MACROS` does not exist here**; compile SYSTEM's six ALLDEFS files by hand (above).
- **The warnings database** goes to the login user's home directory under `:DEFAULTED-BATCH`; use `:NOWARN` or give the server a writable `/lispm/`.
- **`COLDUT` names package COLD**, which exists only once `SYS: COLD; COLDPK LISP` is loaded, so load that first; then `qc-file` `COLDUT` and `COLDLD`, then `(make-system 'cold :compile :noconfirm)`.
- **`MAKE-COLD`'s partition question traps over TELNET** (issue 4). Replacing `FQUERY` for the duration answers it: `(let ((old (symbol-function 'fquery))) (unwind-protect (progn (fset 'fquery (function (lambda (&rest ignore) t))) (funcall (intern "MAKE-COLD" "COLD") "LOD3")) (fset 'fquery old)))`. Check first that every file of `COLD-LOAD-FILE-LIST` has a QFASL.
- **A cold load has no TELNET.** `(si:qld)` is typed at the console, which muir serves over RFB; a client sending key events slowly is enough.
- **The site files must be compiled** into the directory served as `SYS: SITE;` --- `site`, `lmlocs` and the host table --- or `QLD` stops at "File not found" for `/site/site.qfasl`.
- **WORMCH is generated from its AST source.** Before loading HACKS into a cold world, use the running build band's font converter and QFASL writer:

  ```lisp
  (let ((name (fed:read-ast-into-font
                "SYS: DEMO; WORMCH AST" 'fonts:worm)))
    ;; A fresh world needs the special declaration before the assignment.
    (compiler:dump-forms-to-file "SYS: DEMO; WORMCH QFASL"
      (list (list 'proclaim (list 'quote (list 'special name)))
            (list 'setq name (list 'quote (symbol-value name))))
      '(:package :user)))
  ```

  `SYS: SYS; UCINIT QFASL` is a tracked binary input, as are the fonts without recovered sources and `DEMO; TVBGAR`. Preserve these inputs when clearing generated QFASLs for a clean build.
- **Answer the "additional systems to load" question with `()`.** In this base ZWEI and the rest are components of System and are already loaded.

### Moving the new band to the site's own subnet

The bootstrap ran on subnet 6 because the stock band could not route the site's
subnet. The band it builds can, so the last step moves it:

1. **Serve the site's real files** as `SYS: SITE;`, still at the bootstrap
   addresses, and compile them with the new band:
   `(make-system 'site :compile :noload :noconfirm :nowarn)`.
2. **Load them**, the host table last, since it redefines OZ's address:
   `(let ((si:inhibit-fdefine-warnings :just-warn)) (load "SYS: SITE; SITE QFASL") (load "SYS: SITE; LMLOCS QFASL") (load "SYS: SITE; HSTTBL QFASL"))`.
   `(chaos:address-parse "OZ")` then answers the site's address.
3. **Save to a partition the running world is not paging from**, such as LOD4:
   `(si:disk-save "LOD4" t)`. The machine reboots into it at its old address,
   finds no time server, and asks for the date; that is expected.
4. **Stop the machine, make that partition current**, and restart the file
   server and the machine at the site's addresses. On this site the new band
   asked OZ at 177201 for the time within three seconds of booting at 177202,
   and answered `(1000 "177202" 65153 256)` for its version, its address, OZ's
   address and the size of its routing table.

### What the self-hosted rebuild added

- **Compile the readtables even when nothing else seems to need them.** `MAKE-COLD` reads `SYS: IO; RDTBL QFASL` and `CRDTBL QFASL`, which `si:rtc-file` makes and `MAKE-SYSTEM` does not; with compiled output cleared, the cold load stops at "File not found" for them.
- **Nothing else may log in while a build runs.** A Lisp Machine has one user, and `LOGIN` logs out first, closing every file connection; a second TELNET session's login killed a SYSTEM compile mid-write.
- **A long compile can exhaust the band.** Near the end of SYSTEM, in the demos, the machine halted in `TRAP`'s recursive-error check. A reboot and `(make-system 'system :compile :noload :noconfirm :nowarn :no-increment-patch)` finished the rest, compiling only what was missing. Reboot again before `MAKE-COLD`, which also needs room.

### What the 2026-09-22 rebuild added

- **A QFASL records the site of the band that compiled it.** `QC-FILE` puts
  `:SITE ,SI:SITE-NAME` in the file's `:COMPILE-DATA` (`sys/qcfile.lisp:179`),
  and `DUMP-FORMS-TO-FILE` does the same through `SHORT-SITE-NAME`
  (`sys/qcfasd.lisp:454`); "these properties wind up on the GENERIC-PATHNAME",
  so the built world carries them too. A build on a band of another site
  therefore writes that site's name into every QFASL. Give the build band the
  new site first, then compile:

  ```lisp
  (login "LISPM" "OZ" t)
  (let ((si:inhibit-fdefine-warnings :just-warn))
    (load "SYS: SITE; SYS TRANSLATIONS") (load "SYS: SITE; SITE QFASL")
    (load "SYS: SITE; LMLOCS QFASL") (load "SYS: SITE; HSTTBL QFASL"))
  si:site-name
  (si:disk-save "LOD2" t)
  ```

  The site files loaded here may have been compiled at the old site; the
  build compiles them again. Make the saved partition current and compile
  from it, so a reboot during the build keeps the new site. The header also
  records the user and the machine's location name. **Not for System 1002**
  built on System 1001's band: see "Building System 1002's release" below.
- **Clear generated QFASLs by the tracked list, not by pattern.** The tree
  tracks some binaries (`sys/sys/ucinit.qfasl`, `sys/demo/tvbgar.qfasl` and
  fonts), and a clean build must keep them. Compare against the release
  archive's file list, sorted with `LC_ALL=C` before `comm`.
- **Read the microcode file list from `ucadr/ucode.lisp` with its comments.**
  System 1000's list has `"UC-PUP"` commented out; assembling it in adds code
  that the released microcode does not have.

### Writing a release pack

A release pack has muir's default layout and only the microcode and the band loaded (`diskpack`, muir `daefb0c` or later):

```
initialize                               2 MCR, PAGE, 4 LOD of 49419 blocks
name LISPM-1
comment 1001
load-from MCR1 <build pack> MCR1         the microcode the band was verified with
modify MCR1 keep UCADR 323
load-from LOD1 <build pack> LOD4         the verified full band
modify LOD1 keep Exp 1001
current LOD1
current MCR1
```

`load-from` copies blocks, not partition comments, hence the two `modify` steps. Take the release's checksum from a pack that has never been booted: a running machine writes its own pack. Boot-test a disposable copy against
the sources extracted from the release archive. All unused release partitions,
including PAGE, must contain only zeroes.

## Building System 1002's release

System 1002 is built on System 1001's band, whose time code is MIT's and
which reads FILE dates at its site's zone, and it is booted and checked with
ozd serving FILE dates in UTC, as 1002 reads them. So the build runs in two
halves with two ozd settings, and a few gates after QLD show that the halves
met. This is the procedure for the release (Q12, §1.4). The bands built from
this branch so far (`docs/release-1002.md`) were incremental builds over
System 1001's build tree; the release is built clean, and repeats their
checks.

**Inputs.**

- **The tree, exported from the release's commit**: `git archive <sha>`, never
  a working tree. An export holds no generated file. A tree used before must
  first lose its generated QFASLs by the tracked list (above), keeping the
  tracked binaries.
- **`sys/ubin/`, assembled from that commit's `sys/ucadr/`**: microcode 1000,
  `ua:version-number` 1000 (see "Assembling the microcode"), twice, byte for
  byte, and equal to the four SHA-256 in `docs/release-1002.md`; the PROM
  files unchanged, `promh.mcr` SHA-256 `2c667f99...`.
- **The builder: `release-1001-pack.img`, LOD1** ("Exp 1001"), the pack
  checked by its SHA-256 `279e597891a0d8263a82d52898dbc2194e7c0f19cbca194d8aaf5750226b7298`
  before use (LOD1's blocks, 65569 to 114987, `29aefb7e...`), with MCR1
  loaded with microcode 1000 from the step above, "UCADR 1000". The build
  runs on muir-sim's `cadr`, micro engine, and the served `SYS: UBIN;` holds
  microcode 1000's `ucadr.tbl`.
- **ozd `d2908d9` or later** (`--file-dates`), named in the build record
  with muir-sim's commit.

**Do not give the builder 1002's site, `TZDATA`, `TIME` or `OPEN`.** Its site
stays System 1001's (`:MIT`, zone `-1`, the name the QFASLs record, as 1002's
is), so skip "Give the build band the new site first". System 1001's site
initialization cannot take 1002's zone name, and 1002's `TIME` or `OPEN` in
the builder would change how it reads and prints the dates of stages 1-4.
The build only compiles 1002's files; it never loads them.

**Stages 1-4 on the builder, ozd at `--file-dates mit --timezone -1`**, the
builder's own site zone, so that it reads every file's date exactly:
readtables, site and SYSTEM compiled with `:recompile` (a clean build, not
`:compile` over an older tree), WORMCH, the COLD system and `MAKE-COLD`:

```lisp
(login "LISPM" "OZ" t)
(qc-file "SYS: SYS; SYSDCL LISP")
(let ((si:inhibit-fdefine-warnings :just-warn)) (load "SYS: SYS; SYSDCL QFASL"))
;; SYSTEM's six ALLDEFS files by qc-file, in order (above)
(make-system 'site :recompile :noload :noconfirm :nowarn)
(qc-file-load "SYS: IO; RTC LISP")
(si:rtc-file "SYS: IO; RDTBL LISP")
(si:rtc-file "SYS: IO; CRDTBL LISP")
;; WORMCH from its AST source (above)
(make-system 'system :recompile :noload :noconfirm :nowarn :no-increment-patch)
(or (numberp time:*timezone*) (ferror nil "The builder's time zone is no longer a number"))
(load "SYS: COLD; COLDPK LISP")
(qc-file "SYS: COLD; COLDUT LISP")
(qc-file "SYS: COLD; COLDLD LISP")
(make-system 'cold :noconfirm)
(or (numberp time:*timezone*) (ferror nil "The builder's time zone is no longer a number"))
;; MAKE-COLD into LOD3 with FQUERY answered (section 4)
```

The gate before `MAKE-COLD` stops the build if anything loaded 1002's time
code into the builder: `*TIMEZONE*` a string is 1002's site on 1001's code.

**Then stop the machine and ozd.** Make LOD3 current, and start ozd again
with `--file-dates utc` (its default) and no `--timezone`.

**Stages 5-7 and every check at `utc`**: the cold boot, QLD by COLDRUN
(section 6), the save to LOD4 (section 7), and all the checks below and of
Q12 §1.4.

**The gates after QLD.** Each must hold; the first two read ozd's log from
the cold boot on, the others run on the saved band with the build's tree
served.

1. **No second load of the cold load's files**: after the cold boot, ozd's
   log shows no read of a file of `COLD-LOAD-FILE-LIST`
   (`sys/sys/sysdcl.lisp:420`), nor of `IO; RDTBL` or `CRDTBL`. A read means
   a recorded date differed from the server's, and QLD then also stops at
   `**MORE**` on the cold-load stream.
2. **QLD ran unattended**: COLDRUN reported `qld-complete` and then
   `script-ends` (ozd's `--log-mini`).
3. **Every loaded id is right**: no file's loaded id holds its date as text,
   and every numeric one is the file's mtime plus 2208988800 (the ids are on
   the generic pathnames' `:FILE-ID-PACKAGE-ALIST`, in
   `FS:*PATHNAME-HASH-TABLE*`).
4. **Nothing is new**: `(make-system 'system :print-only :noconfirm)` lists
   nothing.
5. **The date check** of Q12 §1.11 (`docs/release-1002.md`, Time zones).

**The one hole, and its remedy.** Stages 1-4 read dates at zone `-1` with
MIT's summer time, and that rule's encoding has one repeated hour a year in
which a printed local time means two instants: for a file whose mtime is in
2026-10-26T23:00Z to 24:00Z the builder reads the date an hour early, and
QLD loads the cold load's files again and stops at `**MORE**`, so gate 1
fails. Measured with every QFASL dated 23:30Z: the cold load recorded
`10/26/26 22:30:00`; with every QFASL dated 22:00Z, an hour before, the
build passed. So before `MAKE-COLD`, look for such QFASLs,

```
find <tree> -name '*.qfasl' -newermt '2026-10-26 23:00Z' ! -newermt '2026-10-27 00:00Z'
```

and, if there are any, date them to the present (`touch`) once that hour has
passed.

**From System 1003 on** the builder is a 1002 band, which reads FILE dates in
UTC, and the whole build runs with ozd at `utc`: there are no two halves, no
`--timezone`, and no hole.

## Publishing a release

A release is built and checked by the SHA of one commit, never by a branch
or a working tree, and published in the order below: the checks come before
anything is public, and a draft is downloaded back and checked before it is
published. The CADR's releases (`release-1NNN`) come from `cadr`; QUUX's
(`release-2NNN`) and the rolling release `dev-system-for-quux` come from
`main`, whose `docs/building.md` has their steps. The commands say
`release-1002`. They are run from a checkout of `cadr`; `<sha>`, `<dir>`,
`<dl>`, `<body>` and `<msg>` are placeholders, and `<remote>` is the
repository's SSH URL (user `git`, host `github.com`, path
`metebalci/muir-sys.git`; written out, it has the shape of an e-mail
address, which the scan refuses in the sources).

**The assets.** `<dir>` holds exactly what is uploaded, and nothing is
written into it after the checks:

| | |
|---|---|
| Pack | `release-1002-pack.img.gz` |
| Sources | `release-1002-sys.tar.gz` |
| Sums | `SHA256SUMS` |

The pack is written as in "Writing a release pack" (above): a CADR pack,
which begins with its label, `LABL`, and has no partition table of any
other kind. There is no PROM asset and no README: the CADR's PROM is MIT's,
and its files stay in `sys/ubin/`.

The sources are `git archive --prefix=release-1002/ <sha>` plus `sys/ubin/`
assembled from that commit's `sys/ucadr/`, with no COLDRUN. Every member of
the tarball is owned by root, uid and gid 0 and user and group name root, as
`git archive` writes them: a member added from the build tree carries its
owner's uid and user name in its tar header, as the eleven `sys/ubin/`
members of `release-1000`'s and `release-1001`'s sources tarballs did until
both were replaced on 27 Sep 2026 with the same files owned by root, and the
scan refuses it. Add `sys/ubin/` with its owner set to root (a `filter` in
Python's `tarfile.add`, or GNU tar's `--owner=root:0 --group=root:0`).

The sources and the pack are gzipped one way, with no name and no date, by
Python's `gzip` module at its default level, 9:

```
python3 -c 'import gzip, shutil, sys
with open(sys.argv[1], "rb") as s, open(sys.argv[2], "wb") as o, \
     gzip.GzipFile(filename="", mode="wb", fileobj=o, mtime=0) as g:
    shutil.copyfileobj(s, g)' <file> <file>.gz
```

`release-1000`'s and `release-1001`'s assets were made this way. `gzip -9
-n` writes other bytes from the same tar (1001's sources: 4,343,401 bytes
where this gives 4,344,017), so a digest is reproduced only by this route.

**1. Build and check by SHA**, then write and check the sums and scan
everything that will be public:

```
tools/release-sums <dir>                       # writes <dir>/SHA256SUMS
tools/release-sums --check <dir>
tools/release-scan <dir> <body> <msg>
tar -tvzf <dir>/release-1002-sys.tar.gz | awk '$2 != "root/root"'
tar --numeric-owner -tvzf <dir>/release-1002-sys.tar.gz | awk '$2 != "0/0"'
```

The two `tar` lines print nothing: every member is root's by name and by
number. The scan refuses any other owner too; the lines say it without
reading the scan's output.

`tools/release-sums` writes one line per asset in byte order of the names,
plus one for the pack uncompressed under its name without `.gz`,
`release-1002-pack.img`, which is no asset (a fetch script checks the pack
as it decompresses it). `--check` fails on a missing file, where `sha256sum
-c --ignore-missing` would pass it, and on a file that no line names.
`<body>` is the release body, written from `docs/release-1002.md`; `<msg>` a
file holding the tag message of step 3. `tools/release-scan` reads every
byte: each file in the sources tarball and its tar headers, and the pack
whole, raw. It passes only what its four rules allow (MIT's addresses in
`sys/man/bug-mail.txt`, what `release-1001`'s assets already hold, the
system's own `/home/lispm`, and the cache default of `tools/lispm-check`);
anything else fails the release. Its baseline,
`tools/release-scan.baseline`, is written from `release-1001`'s two assets,
checked against their published digests first: `tools/release-scan
--make-baseline tools/release-scan.baseline release-1001-sys.tar.gz
release-1001-pack.img.gz`. The tools are the same on both lines. Their
self-test is `tools/release-test --pack <a CADR pack> --disk <a QUUX disk>`;
the QUUX disk, a VHD with a GPT, comes from `main`'s line, since the test
also holds the scan's reading of a VHD.

**2. The SHA is on `cadr` and not on `main`.** This clone has no remote, so
both tips are fetched by `<remote>`:

```
git fetch <remote> \
    +refs/heads/main:refs/remotes/origin/main \
    +refs/heads/cadr:refs/remotes/origin/cadr
git merge-base --is-ancestor <sha> origin/cadr &&
    ! git merge-base --is-ancestor <sha> origin/main && echo on cadr alone
```

`release-1001` (`d0d68de`) and older are on both lines.

**3. An annotated tag at the SHA**, like `release-1000`'s and
`release-1001`'s, with Mete's identity as the tagger, unsigned:

```
git tag -a release-1002 -F <msg> <sha>        # <msg>: "Release 1002: <one line>"
tools/release-scan --tag release-1002
git push <remote> refs/tags/release-1002
git ls-remote <remote> 'refs/tags/release-1002^{}'
```

The last prints `<sha>`. From here the tag is public and never moves;
everything before this step can still be done again.

**4. A draft:**

```
gh release create release-1002 -R metebalci/muir-sys --draft --verify-tag \
    --target <sha> --title "System 1002" --notes-file <body> <dir>/*
```

`--verify-tag` refuses a tag that is not on GitHub. The title is "System N".

**5. Downloaded back and checked**, into an empty directory `<dl>`, with the
API's JSON kept outside it:

```
gh release download release-1002 -R metebalci/muir-sys -D <dl>
gh release view release-1002 -R metebalci/muir-sys --json assets > <api.json>
tools/release-sums --check <dl> --api <api.json>
tools/release-scan <dl>
tar -tvzf <dl>/release-1002-sys.tar.gz | awk '$2 != "root/root"'
tar --numeric-owner -tvzf <dl>/release-1002-sys.tar.gz | awk '$2 != "0/0"'
tar -tzf <dl>/release-1002-sys.tar.gz | cut -d/ -f1 | sort -u
gzip -dc <dl>/release-1002-pack.img.gz | head -c 4; echo
```

`--api` compares the digests GitHub computed for the uploaded assets with
the files: the release's assets must be exactly the directory's, each with
its file's SHA-256 (it fails, saying so, if the JSON gives no digest). The
two owner lines print nothing, as in step 1, the third `tar` line prints
the tag alone, `release-1002`, and the last line `LABL`, the pack's label.
While it is a draft an asset's URL is not public, so `curl -fsI` of it
fails. Whether `gh release download` reads a draft's assets is measured on
the first draft; if it does not, the API's digests of the uploaded bytes
and the scan of `<dir>` stand in. A failure is mended in the draft (`gh
release delete-asset`, `gh release upload`, and step 5 again); the tag
stays.

**6. Published with Latest explicit:**

```
gh release edit release-1002 -R metebalci/muir-sys --draft=false --latest
gh api repos/metebalci/muir-sys/releases/latest --jq .tag_name
```

While no QUUX release exists, the newest release is Latest, so a CADR
release is published with `--latest` and the last line prints its tag. Once
a QUUX release exists, the newest QUUX release is Latest, and a CADR release
after it is published with `--latest=false`; the last line then prints that
QUUX release's tag (Q12 §1.9). GitHub orders releases by their tag's date,
so Latest is always set and read back. Last, a fresh download without
credentials, by the path the fetch scripts use
(`https://github.com/metebalci/muir-sys/releases/download/release-1002/<asset>`,
each asset and `SHA256SUMS`, with `curl -fsSLO`), passes `tools/release-sums
--check`.

## The stages

A world cannot be built from nothing, so each stage runs on the one before.

1. **Compile.** A running band compiles every source file into a QFASL file.
2. **Make a cold load.** The cold-load builder, running in the old world, lays a minimal world word by word onto an empty partition.
3. **Boot the cold load.** It has a reader, an evaluator, a fasloader and MINI, but no compiler, window system or FILE client.
4. **Load the rest.** `SI:QLD` fetches the inner system through MINI, turns on the network and FILE, and loads everything else with `MAKE-SYSTEM`.
5. **Save.** `DISK-SAVE` writes the finished world to a partition, which then boots like any band.

## What is needed

- **A running band** to compile with, such as a 1000 band, **whose site is the site being built** (see "What the 2026-09-22 rebuild added" below).
- **A file server for `SYS:`** that serves both FILE and MINI. ozd does.
- **A site.** The repository includes an example `site/` directory. The build loads `SYS: SITE; SITE`, `LMLOCS`, `HSTTBL` and `SYS TRANSLATIONS` (`sys/sysdcl.lisp:598-605`). They must be compiled for the site first, with `(make-system 'site :compile :noload :noconfirm)`.
- **The translations file must survive the traditional readtable.** A cold load reads it with `MINI-READFILE` (`cold/mini.lisp:319`), which ignores the file's attribute list, so it is read in traditional syntax whatever the file says. There a slash escapes the next character. A file whose targets are Unix paths must therefore double every slash and name no readtable, or the cold load stops with "End of file ... in the middle of the list". MIT's own site file never met this: its targets are TOPS-20 paths with no slashes. This is metebalci/muir-sys issue 9.
- **A free partition for the cold load,** and a larger one for the saved world (step 7).
- **A console or generated COLDRUN script** for steps 5 and 6. The TELNET server is not part of a cold load; System 1001 can run QLD from the script described below. System 1000 cannot: its `(si:qld)` is typed at the console, which muir serves over RFB, and QLD then asks for a list of additional systems, answered with `()`.

Every session that reads or writes files must log in first, for example with `(login "LISPM" t)`.

## 1. Compile the readtables

The standard readtables are not compiled by the Lisp compiler. `io/rdtbl.lisp` signals an error if it is compiled or loaded (`io/rdtbl.lisp:5-6`). The readtable compiler `SI:RTC-FILE` reads it and writes its QFASL file (`io/rtc.lisp:847-858`).

The readtable compiler is in no system (`sys/sysdcl.lisp` does not name `IO; RTC`), and a 1000 band does not have it loaded: `(fboundp 'si:rtc-file)` is `NIL`. So compile and load it first:

```lisp
(qc-file-load "SYS: IO; RTC LISP")
(si:rtc-file "SYS: IO; RDTBL LISP")
(si:rtc-file "SYS: IO; CRDTBL LISP")
```

The cold-load builder loads both QFASL files specially (`cold/coldut.lisp:1244-1247`), and `SYSTEM-INTERNALS` only loads them (`sys/sysdcl.lisp:122`, `:126`).

## 2. Compile the systems

`SYSTEM` includes ZWEI and HACKS in this System 100-based tree. There is no
`SYSTEM-MACROS` system. Compile SYSTEM's six ALLDEFS files in the order given
above, and compile the site files before the cold load:

```lisp
(make-system 'site :recompile :noload :noconfirm :nowarn)
(make-system 'system :recompile :noload :noconfirm :nowarn)
```

For a clean build, clear generated QFASLs first, preserving the tracked binary
inputs described above. Regenerate both readtables and WORMCH from source.
Keep the source tree unchanged throughout compilation and cold loading.

`:RECOMPILE` rebuilds every compilation target. `:NOLOAD` suppresses final
loading into the build band, but still loads definitions required by compile
steps. Use a compatible build band and compile the current `SYS; SYSDCL`
source before loading its QFASL. `:NOWARN` enables unattended compilation
without requiring a compiler-warning database in the login directory.

Compiling SYSTEM increments its major version once. The final 1001 build
advanced the directory from 1000 to 1001 while the running checkpoint stayed
1000. For a recovery or a rebuild of the same version, add
`:NO-INCREMENT-PATCH`; check the directory before deciding whether to advance
it. Do not increment again merely because an interrupted build is resumed.

The final 1001 SYSTEM compile took 2 hours 17 minutes 36 seconds on muir's
micro engine. A long compile can exhaust the build world's address space;
reboot before assembling microcode or making the cold load. If compilation
was interrupted, directly compile any missing or incomplete outputs before
resuming with `:COMPILE` and `:NO-INCREMENT-PATCH`.

## 3. Build the cold-load builder

```lisp
(load "SYS: COLD; COLDPK LISP")
(qc-file "SYS: COLD; COLDUT LISP")
(qc-file "SYS: COLD; COLDLD LISP")
(make-system 'cold :noconfirm)
```

The `COLD` system (`cold/coldpk.lisp:57-64`) compiles and loads `COLD; COLDUT` and `COLDLD`, and loads the cold-load parameters from `COLD; QCOM` and `QDEFS`. It keeps the new world's symbols in its own package, so the new world may differ incompatibly from the old one (`cold/coldpk.lisp:9-24`).

**MINI's server address is fixed when `COLD; MINI` is compiled.** It is the Chaos address of the host that `SYS:` translates to at that moment (`cold/mini.lisp:26-34`). So step 2 must run with `SYS:` on the file server that the cold load will read from.

A quick check before making the cold load: the server's Chaos address appears in `cold/mini.qfasl` as a 16-bit word, low byte first. For a server at octal 177201, the bytes are `81 fe` at an even offset. The first build found it there, and found neither System 304's server address, octal 4403, nor System 100's, octal 3060. The machine's own address also appears; MINI replaces that routing address with the server's when both are on one subnet (`cold/mini.lisp:69-70`). A byte search suggests the address rather than proving it.

## 4. Make the cold load

```lisp
(cold:make-cold "LOD3")
```

The symbol cannot be read before the package exists, so in a world where COLD has not been loaded yet, either run the COLD system first or call it as `(funcall (intern "MAKE-COLD" "COLD") "LOD3")`. A form naming a package that does not exist stops at a reader error, and over TELNET the session then waits at that prompt.

The COLD system has the same resume trap as the others: `COLD; COLDUT` and `COLD; COLDLD` must be compiled by hand with `qc-file` before `(make-system 'cold :compile :noconfirm)` will run, since it reads their compiled files' properties.

**Files the cold load reads over MINI use spaces only, and no page marks.**
MINI's character stream hands the server's bytes to the reader untranslated
(`MINI-ASCII-STREAM`, `sys/cold/mini.lisp:265`), unlike the streams the file
system uses after the handover, which map ASCII 10, 11, 12, 14, 15 and 177 to
the machine's own Backspace, Tab, Line, Page, Newline and Rubout
(`TYI-FROM-ASCII-STREAM`, `sys/io/stream.lisp:611`). An ASCII tab therefore
arrives as a character the traditional readtable does not class as
whitespace, and a continuation line that begins with one is read as part of
the token above it: the form acquires an argument nobody wrote, and the error
surfaces far from the file. This binds `site/sys.translations` and
`site/coldrun.lisp`; the sources QLD reads later are full of tabs and page
marks and are fine. lmz-sys, bishop's line, met this in practice
(`2e684c2`); it has not been reproduced here, where the site files have never
contained a tab.

**Choose the destination explicitly.** The verified unattended build used
the temporary `FQUERY` override shown above after checking and clearing LOD3.
The earlier System 100 bring-up required console input because of TELNET
line-input bugs; System 1001 includes those fixes. Never answer a partition
overwrite question automatically without first checking its destination.

**Keep typed forms short.** A cold load's console has a small wired keyboard buffer, and a long line is silently truncated: a 130-character form typed at about twelve characters a second stopped echoing after sixty characters, and the reader simply waited for the rest. Type short forms, or type slowly, and read back what the screen echoed before pressing Return.

`MAKE-COLD` (`cold/coldut.lisp:1194-1218`) marks the partition "cold-incomplete", builds the areas, NIL and T, loads the files of `COLD-LOAD-FILE-LIST` (`sys/sysdcl.lisp:499-523`) and the readtables, and records the physical file names MINI will ask for (`cold/coldut.lisp:1249-1256`). It then sets the partition's comment to "cold" and the date. The partition must not be the one the running world was booted from.

## 5. Boot the cold load

Make the cold load's partition the current band, then boot. With the machine stopped, muir's `diskpack` does it. The same stop is the moment to make room for the finished world, since both are label edits:

```
diskpack pack.img "delete LOD6"
diskpack pack.img "modify LOD5 48450"
diskpack pack.img "current 3"
```

`show` then marks the current band with an asterisk. On the pack this left LOD3 holding the cold load, LOD5 holding 48450 blocks for the save, and LOD9 still holding the old world to fall back on.

`SET-CURRENT-BAND` is exported (`cold/global.lisp:1507`) and belongs to the disk-label editor (`io/disk.lisp:16`), but its definition was not found in `io/`, `sys/` or `sys2/`.

The cold load greets with "Lisp Machine cold load environment, beware!" (`sys/ltop.lisp:338`).

**Boot it cold.** muir-fpga measured that a warm boot of a System 304 band halts in the microcode about 20 milliseconds in, while a cold boot is clean. This has not been checked here. Restarting muir is a cold boot. A cold boot clears the screen only after the band has been read, about a minute in.

### One binary file QLD needs

`QLD` loads `SYS: SYS; UCINIT QFASL` while making System, after the compiler
and `COLD; DEFMIC` and `DOCMIC`, and stops with

```
>>ERROR: File not found for SYS: SYS; UCINIT QFASL
```

if it is absent. It records the functions microcompiled into the microcode,
and nothing here can write it again: its writer, `WRITE-INITIALLY-MICROCOMPILED-FILE`
(`sys/mlap.lisp:552`), has no caller. So it is tracked, System 100's copy of
2,844 bytes.

## 6. Load the rest

For an unattended load, generate `site/coldrun.lisp`, served as
`SYS: SITE; COLDRUN LISP`, with these forms:

```lisp
(si:qld '(:noconfirm :no-reload-system-declaration) nil)
(si:mini-report "qld-complete")
```

The cold load reads and runs this script before entering its listener.
The script is local build input, ignored by Git and outside the SITE
compilation list. The runner stays in `sys/cold/mini.lisp`. It resolves the
script's logical pathname while compiling, because MINI has no pathname
translator at cold boot. With the supplied site translations, ozd sees
`/site/coldrun.lisp`. Changing that translation requires recompiling MINI
and rebuilding the cold band.

The second argument to QLD suppresses the additional-systems question.
Use forms supported by the cold environment before QLD has loaded the rest
of the system. With ozd's `--log-mini`, a successful run reports
`qld-complete` followed by `script-ends`. Saving the finished band is a
separate step.

If the script is absent, the cold load enters its ordinary listener. To
load interactively, use the cold load's console:

```lisp
(si:qld)
```

`QLD` (`sys/ltop.lisp:653-700`):

1. loads the inner system through MINI (`:660`), then the pathname and FILE code (`:664`);
2. reads the site files, reinitializes the network, and logs in as LISPM on the host of `SYS:`;
3. loads `MAKSYS`, `PATCH` and `SYSDCL`, then runs `MAKE-SYSTEM` on `System`;
4. asks for a list of further systems to load, such as `(zwei)`;
5. prints the partition size the world will need, from `ESTIMATE-DUMP-SIZE` (`sys/qmisc.lisp:1279`), and the disk label, and says "OK, now do a DISK-SAVE".

**MINI trouble.** Run ozd with `--log-mini`: it logs each file MINI reads, and each it refuses with the reason. A refusal is where the cold load stops. Every name MINI asks for must exist at that exact path, case included, under the file server's roots.

**A reboot within three minutes fails once.** After every boot, the cold load's first MINI connection uses index 1, and MINI never closes it. If the cold load is booted again within three minutes of its last MINI connection, ozd still holds that connection and discards the new request as a duplicate. The first `(si:qld)` then fails with "RFC fail" after about 20 seconds. Trying again works, because it uses the next index.

## The halt this build met, in QLD

On the first build the cold load booted and `QLD` read its whole inner system and the site files through MINI, then the machine stopped itself with nothing printed. Three runs halted with identical registers: the program counter three instructions into `TRANS-REALLY-TRAP` (`ucadr/uc-transporter.lisp:143`) and the last microinstruction at `ILLOP`.

**It is an unbound variable read while traps are disabled.** The cold-boot path clears `M-TRAP-ENABLE` (`ucadr/uc-cold-disk.lisp:644`, "MACROCODE WILL TURN ON TRAPS WHEN READY"), and macrocode turns traps on only in `LISP-REINITIALIZE` (`sys/ltop.lisp:329-331`). Until then `TRAP` becomes `ILLOP`, which halts (`ucadr/uc-interrupt.lisp:9`, `ucadr/uc-cadr.lisp:88`).

**Naming the variable, without a debugger.** The trapping Q is in `MD`, whose data type is `DTP-NULL` and whose pointer is the symbol itself. A cold load's band is uncompressed, so virtual address N is word N of the partition, and reading the band at that address gives the symbol header and its print name. Here it was `SCHEDULER-STACK-GROUP`, declared with no value at `sys2/prodef.lisp:22` and set only by `PROCESS-INITIALIZE` (`sys2/proces.lisp:1068`).

**A work-around at the console, before `(si:qld)`:**

```lisp
(setq si:scheduler-stack-group nil)
```

It stops the halt, because a `DEFVAR` with no value does not overwrite a bound variable. In that run the load then went further but still failed: the transporter trap was signalled as "Microcode bug: no error-table entry", since a cold load has not loaded `SYS: UBIN; UCADR TBL` yet (`eh/eh.lisp:2324`), and the Chaos code then failed at interrupt level trying to answer a packet. The fix is to declare the variable with a value and recompile that file, which a cold load reads through MINI rather than carrying inside it. This is metebalci/muir-sys issue 6, and this system has made that change: `sys2/prodef.lisp` now declares the variable `NIL`, with a comment saying why.

**With that fixed, a cold load gets much further and stops again.** It loads the inner system, the pathname and file code and the site files, runs `LISP-REINITIALIZE` as far as "Turning off INHIBIT-SCHEDULING-FLAG", and then breaks with "Unknown stream operation", which is MINI's own message (`cold/mini.lisp:232`, `:268`) for an operation its streams do not implement. The reader is in the file-system package at that point. The message does not name the operation, which is metebalci/muir-sys issue 7.

**Reading the failure from the file server's log.** When the world stops receipting, the server keeps retransmitting its unreceipted packet every half second, and a crippled world answers with a lost-packet message, which the server logs as the connection closing. So the last file read before that line names the file the band died in, which is a second witness to what the console says.

## What had to be changed in the sources

The system does not rebuild itself as it stands. These are the changes here to the tree, each with a comment in the source saying why, and each filed as an issue so that upstream can take it or refuse it.

| File | Change | Issue |
|---|---|---|
| `sys2/prodef.lisp:22` | `SCHEDULER-STACK-GROUP` is declared `NIL` instead of being left unbound | 6 |
| `cold/mini.lisp` | the "Unknown stream operation" message names the operation | 7 |
| `cold/mini.lisp` | MINI's two streams answer `:SEND-IF-HANDLES` instead of signalling | 7 |

**Why the first is needed.** A cold load runs with traps disabled until `LISP-REINITIALIZE` enables them, and `PROCESS-WAIT` reads that variable while deciding how to wait. Read unbound in that window, the reference traps, `TRAP` becomes `ILLOP` and the machine halts with nothing printed. Declaring it `NIL` costs nothing, since `PROCESS-INITIALIZE` still sets the real stack group later.

**Why the second is needed.** Without it the cold load stops at "Unknown stream operation" without saying which one, which is the only fact needed to go further.

**Why the third is needed.** `:SEND-IF-HANDLES` means "send this message only if you handle it". A flavor instance answers it through `VANILLA-FLAVOR`; MINI's streams are closures and answered nothing, so an optional message became a fatal error. `IO; STREAM:64` asks any stream for its byte size that way, which is where a cold load met it.

Everything else in this document is procedure rather than a change to the sources: compiling the definition files first, rebooting when the world runs out of address space, compiling by hand the file a trap interrupted, typing at the console because line reads over TELNET trap, and merging partitions to make room for the saved world.

## 7. Save the band

After QLD completes and the new world's version and SYS file access pass:

```lisp
(si:disk-save "LOD4" t)
```

The second argument suppresses questions. Use a destination large enough for
the finished world; muir's current default LOD partitions hold 49419 blocks.
The build clears LOD4 with the emulator stopped before booting the cold band,
so no older band data remains beyond the new saved world's end. Preserve a
backup of the existing full band first.

Saving resets networking and boots the saved world, so a TELNET driver can
lose its connection before printing a completion marker. Reconnect and verify
the loaded band, System version and SYS file access. With the emulator
stopped, copy verified LOD3 to LOD1 and LOD4 to LOD2 for the development
layout, preserve their comments, and select LOD2 for subsequent boots.

## Checks

- The cold load's partition comment says "cold" and the date.
- `QLD` ends with "OK, now do a DISK-SAVE".
- The saved band boots and prints the herald with its system versions.
- Over TELNET, `(+ 1 2)` returns `3`.

## Assembling the microcode

`sys/ubin/` is not in the repository; a release carries it, assembled from
`sys/ucadr/`. Verified on 2026-09-17 on a 1000 band: everything it holds
was assembled from these sources, and matches System 100's.

**Load the assembler.** `(make-system 'cadr-micro-assembler :compile :noconfirm :nowarn)`
(`sys/sysdcl.lisp:400`). It is not in the band.

**UCADR, the microcode.** `sys/ucadr/ucode.lisp` defines a `UCODE` system over
the 23 `uc-*` files, whose `MICRO-ASSEMBLE-SYSTEM-DO-IT` (`sys/cadrlp.lisp:457`)
asks for a version number when the output has none, as on a Unix file server,
and `WRITE-VARIOUS-OUTPUTS-SYSTEM` asks "WRITE-MCR?". Call what it calls, with
the same list of files as truenames, the version set and the question answered:

```lisp
(setq ua:version-number 323)
(let ((ua:file-truenames-listified (mapcar #'ua:listify-pathname files)))
  (ua:assemble-system (send (fs:parse-pathname "SYS: UBIN; UCADR") :new-version 323)
                      files nil nil t))
```

with `Y-OR-N-P` answering yes. Leaving `FILE-TRUENAMES-LISTIFIED` unbound
writes an empty source list into `UCADR SYM`. Reading takes about 7 minutes
and assembly 3 on muir's micro engine. It writes `ucadr.mcr`, `.sym`, `.tbl`
and `.locs`: `mcr`, `tbl` and `locs` are byte for byte System 100's. `sym`
holds the same symbols in the order of a hash table, and names its source host
OZ, not MIT-OZ.

**Reboot before assembling again.** A second `ua:assemble-system` in the
same band reuses the source it read the first time, even when the files have
changed: on 2026-09-23 a second assembly after a source edit came out byte for
byte the same as the first, and its log had no "Read-in time" line. Boot the
band afresh for every assembly of changed sources.

**Serve the table of the microcode that runs.** A band whose microcode is not
the one it was saved with reads `SYS: UBIN; UCADR TBL` at boot, and ozd serves
files without versions, so the served `sys/ubin/` must hold the running
microcode's `ucadr.tbl`. With System 1001's band on microcode 1000 and 323's
table served, the machine never reached its TELNET server.

**PROMH, the boot PROM.** `(ua:assemble "SYS: UCADR; PROMH TEXT")`, with
standard input answering `9` for the version and `T` for "T IF FOR PROM", and
`Y-OR-N-P` yes. It writes beside its source, in `sys/ucadr/`, and the four files
move to `ubin/`. The machine code, table and location map match the earlier
assembly byte for byte. Symbol-file ordering and assembler bookkeeping can
differ; compare the symbols and machine outputs separately.

**DCFU and MEMD, the disk formatter and memory test.** In a freshly booted band
each, since a dump includes every symbol the assembler holds:
`(ua:assemble "SYS: UCADR; DCFU TEXT")` with version `4`, or `MEMD LISP` with
`1`, `Y-OR-N-P` answering no, then `(ua:cons-dump-memories)` with
`*PRINT-BASE*` 8, which writes `SYS: UBIN; DCFU ULOAD` or `MEMD ULOAD`. Their
memory images are System 100's; their symbols are the same, in another order.
This needed a fault fixed in `sys/cdmp.lisp` first.

**MCR1.** `diskpack <pack> load MCR1 sys/ubin/ucadr.mcr`, then
`modify MCR1 keep UCADR 323`. The partition it writes is block for block the
one LM-3's System 100 pack has.
