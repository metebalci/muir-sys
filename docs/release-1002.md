# System 1002

What the CADR's next release changes from System 1001. It is in progress on
the `cadr` branch: each change is recorded here as it is made. `main` is
QUUX's system, numbered from 2000; what this branch takes from it is a bug fix,
a change that needs no QUUX hardware, or a feature Mete chose for the CADR.
Every change to a source file carries a comment in that file saying why.

- **The system number is 1002** (`patch/system.patch-directory`,
  `patch/system-1002.patch-directory`), so that no band built from this
  branch calls itself 1001.

Each fix below was checked with `tools/lispm-check` on System 1001's release
band (`release-1001-pack.img`, microcode 323) under muir's `cadr`: its cases
failed on the band as released and passed with the changed file compiled and
loaded. That band reads FILE dates at its site's zone, so a check on it passes
`--ozd-file-dates mit --ozd-timezone -1` (`docs/lispm-check.md`).

## Time zones

- **The site's `:TIMEZONE` takes a tzdata zone name** (Mete, 2026-09-27, for
  the CADR), such as `"Europe/Berlin"` (written `"Europe//Berlin"` in a site
  file, whose readtable escapes with a slash), and the example site now
  names that zone (`site/site.lisp:15`). The name is looked up in
  `SYS: IO1; TZDATA`, a table of every zone and link of tzdata 2026c (598
  names) with the POSIX TZ string its compiled file ends with, today's rule;
  `sys/io1/gen-tzdata.py` makes it from the host's tzdata. The string gives
  the standard offset and the rule for daylight savings time
  (`PARSE-TZ-STRING`, `io1/time.lisp:307`). `*TIMEZONE*` stays a number, the
  hours west in standard time, which every reader of it expects; an offset
  that is not whole hours makes it a ratio. The parsed string is in
  `TIME:*TIMEZONE-RULE*` and the name in `TIME:*TIMEZONE-NAME*`;
  `SET-TIMEZONE-FROM-SITE` (`io1/time.lisp:418`) sets all three at every
  site initialization (`:876`). A name tzdata does not know, a malformed
  string, and a zone whose daylight savings time is not one hour from
  standard are errors that say which. `TZDATA` loads before `TIME`
  (`sys/sysdcl.lisp:154`).
- **A number in `:TIMEZONE` is a fixed offset with no daylight savings time.**
  Before, whatever the number, the machine applied the United States' rule of
  1967 to 1986, from the last Sunday of April to the last Sunday of October,
  so the example site's `-1` was in summer time then, not from the last
  Sunday of March.
- **`*DAYLIGHT-SAVINGS-TIME-P-FUNCTION*`** now defaults to
  `TIMEZONE-RULE-DAYLIGHT-SAVINGS-TIME-P` (`io1/time.lisp:371`), which follows
  `*TIMEZONE-RULE*` and is never true without one. It is called with the year
  in full, and with the seconds and minutes from `ENCODE-UNIVERSAL-TIME` too
  (`io1/time.lisp:191`). `DAYLIGHT-SAVINGS-TIME-IN-NORTH-AMERICA-P`,
  `LAST-SUNDAY-IN-APRIL` and `LAST-SUNDAY-IN-OCTOBER` are gone; nothing else
  used them. `WEEKDAY-IN-MONTH` finds the n-th or last weekday of a month on
  `GREGORIAN-DAY-COUNT` (`io1/time.lisp:166`), the day count
  `ENCODE-UNIVERSAL-TIME` now shares.
- Checked on the 1001 band with `SYS: IO1; TZDATA` and `TIME` compiled and
  loaded: the band's own site, `-1`, gives a fixed offset with no
  summer time; a site naming Europe/Berlin, through
  `SET-TIMEZONE-FROM-SITE`, gives -1, the name and the rule `CET`; noon GMT on
  15 January 2026 decodes to 13:00 standard time and on 15 July to 14:00
  summer time, and both encode back to the same second; the changes of 29
  March and 25 October 2026 fall at 01:00 GMT, the second before and the
  second at each; a printed summer time parses back to itself; an unknown
  zone name is an error naming it. A band loaded with the change keeps its
  old `*DAYLIGHT-SAVINGS-TIME-P-FUNCTION*`, since the variable is a
  `DEFVAR`; the check sets it as a band built with the change has it.
- **A band from before this change cannot take a site that names a zone.**
  Its site initialization puts the string in `*TIMEZONE*`, and every decoding
  then fails (measured on main). A build on such a band loads the new
  `SYS: IO1; TZDATA` and `TIME` before the new site file.
- **FILE dates on the wire are UTC** (Mete, 2026-09-27); the machine still
  shows dates in its own local time. `PARSE-DIRECTORY-DATE-PROPERTY` encodes
  its `MM/DD/YY HH:MM:SS` at zone 0 (`io/file/open.lisp:1465`) and
  `PRINT-DIRECTORY-DATE-PROPERTY` decodes at zone 0 (`io/file/open.lisp:1480`),
  which also takes no daylight savings time. Every FILE date the client reads
  or sends goes through these two: the OPEN and CLOSE replies
  (`network/chaos/qfile.lisp:500`), directory listings and file properties
  (`READ-DIRECTORY-STREAM-ENTRY`, `io/file/open.lisp:1372`), CHANGE-PROPERTIES
  (`network/chaos/qfile.lisp:680-691`) and, through
  `PARSE-COLD-LOADED-TIME` (below), the dates recorded before the time parser
  loads. A date in any other form still goes to
  `TIME:PARSE-UNIVERSAL-TIME` at local time (`io/file/open.lisp:1468`).
- **The "date or never" properties go on the wire in UTC too**
  (`:REFERENCE-DATE` and the rest): their printer in
  `*KNOWN-DIRECTORY-PROPERTIES*` is now `PRINT-DIRECTORY-DATE-OR-NEVER-PROPERTY`
  (`io/file/open.lisp:1340`, `:1492`), "never" or the date as
  `PRINT-DIRECTORY-DATE-PROPERTY` prints it. That printer is used only on
  the wire, by CHANGE-PROPERTIES (`network/chaos/qfile.lisp:686`) and the
  band's own FILE server; `TV:PRINT-UNIVERSAL-TIME-OR-NEVER`, which printed
  local time, stays the choose-variable-values printer for showing such a
  date (`window/choice.lisp:1066`), so the local display is unchanged. The
  table is a `DEFVAR`: a band built from a new cold load has the new entry,
  but loading the file into a running band keeps the old one.
- **The fast parser also reads a four-digit year**, `MM/DD/YYYY HH:MM:SS` and
  `MM/DD/YYYY` (`io/file/open.lisp:1426`). `PRINT-DIRECTORY-DATE-PROPERTY`
  has always printed the year in full (MIT's `DECODE-UNIVERSAL-TIME` returns
  it so), which went to the full parser at local time: with the printer at UTC,
  a date this system printed read back moved by the site's offset (measured:
  3993098400 for 3993105600 at Europe/Berlin). The band's own FILE server
  reads CHANGE-PROPERTIES dates with it (`file/server.lisp:990`).
- **The band's own FILE server sends UTC.** Its OPEN and CLOSE replies print
  the date with `CV-WIRE-TIME` (`file/server.lisp:50`): zone 0, and
  `MM/DD/YY HH:MM:SS` with a two-digit month, the form the fast parser takes;
  `:MM/DD/YY` printed the month in one digit before October, which a client
  read with the full parser at local time (`file/server.lisp:333`, `:340`,
  `:472`, `:787`, `:793`). The protocol-0 CLOSE reply named the date mode
  `:MM/MM/YY`, which has no date format and signals an error (MIT's). Its
  directory listings print creation and modification dates with
  `PRINT-DIRECTORY-DATE-PROPERTY`, so they are UTC too, and the "date or
  never" properties as the replies print a date, or "never"
  (`file/server.lisp:944-946`): with `TV:PRINT-UNIVERSAL-TIME-OR-NEVER` a date
  from January to September went to the client's full parser at local time
  and one from October to December to its fast parser as UTC, moved by the
  site's offset (measured at Europe/Berlin: 24 October 2026 23:30 GMT read
  back 7200 s late). `CV-TIME` stays local, for the server's lossage log.
- **A 1002 band wants ozd's `--file-dates utc`**, ozd's new default. A FILE
  server that sends its local time (ozd's `--file-dates mit`, the own servers
  of Systems 100 to 1001) has its dates read as UTC, off by its zone's offset.
- Checked on the 1001 band with `SYS: IO1; TZDATA`, `TIME` and
  `IO; FILE; OPEN` compiled and loaded, at Europe/Berlin and at a fixed `-1`:
  `"07/15/26 12:00:00"` parses to 3993105600 (12:00 GMT) where the band as
  released gave 3993098400 (Berlin) and 3993102000 (`-1`); 3993105600 prints
  `"07/15/2026 12:00:00"` where it printed 14:00 and 13:00; January the same;
  a printed date parses back to itself, the four-digit forms parse, and
  `00/00/0000` is no date; `TIME:PRINT-UNIVERSAL-TIME` still shows
  `7/15/26 14:00:00` at Berlin and 13:00 at `-1`. With `FILE; SERVER` compiled
  and loaded too, `CV-WIRE-TIME` prints `07/15/26 12:00:00` at Berlin, `-1`
  and `5` alike, and five dates (summer, winter, both sides of the October
  change, 2001) read back through the fast parser as themselves; the old
  reply's form gave `7/15/26 14:00:00`.
  The "date or never" properties, at Berlin and `-1`: the server's listing
  line for 15 July and for 24 October 2026 (23:30 GMT, 01:30 in Berlin)
  reads back through `READ-DIRECTORY-STREAM-ENTRY` as the same second, and
  so does CHANGE-PROPERTIES's text through the server's parser, and "never"
  as NIL; before, 24 October came back 7200 s late at Berlin and 3600 s at
  `-1`, and each half put back fails those cases. The server itself was
  not run: the band has neither it nor the local file system it serves.
- **A date recorded before the time parser loads is the server's UTC text.**
  While a cold load has no time parser, QFILE records a file's date as the
  text the server sent, less the month's leading zero
  (`network/chaos/qfile.lisp:495-500`), and the cold-load builder records
  each cold-loaded file's date as text too. QLD's `MAKE-SYSTEM` compares the
  two to tell whether a cold-loaded file must be loaded again, and TIMPAR's
  initialization later parses every such text (`CANONICALIZE-COLD-LOADED-TIMES`,
  `io/file/pathst.lisp:481`). With FILE dates in UTC on the wire both went
  wrong. The builder printed its own local time (`TIME:PRINT-UNIVERSAL-TIME`),
  an hour or two from the server's text, so QLD loaded every cold-loaded file
  again and stopped at `**MORE**` on the cold-load stream: measured in two
  builds from this branch, one as it was and one with `main`'s change, which
  records the date as a number (`8c2f00e`) and so never equals QFILE's text
  either. And a month before October, its zero gone, went to the full parser
  at the site's local time. Now the builder records the date as the server
  sends it, UTC with the month's zero dropped (`COLD-FILE-DATE-STRING`,
  `cold/coldld.lisp:120`, used at `:137`), and `PARSE-COLD-LOADED-TIME`
  (`io/file/pathst.lisp:473`) puts the zero back so that the fast parser
  reads the text as UTC. `main` keeps its numbers, which fit its file
  device, whose dates are numbers too. QFILE's comment, and MINI's, which
  records the same text, say whom their text matches now
  (`network/chaos/qfile.lisp:498`, `cold/mini.lisp:131`). This is
  `main`'s cold-load date fix (`8c2f00e`, Q12's backport inventory) taken in
  this branch's own form. Checked in builds from this branch on muir-sim's
  `cadr` (System 1001's band compiling and making the cold load, microcode
  1000), each incremental over System 1001's build tree; step 8 of Q12
  repeats the checks on the clean release build (`docs/building.md`,
  "Building System 1002's release"). QLD read none of the cold load's files
  again, the 19 of `COLD-LOAD-FILE-LIST` and the readtables `RDTBL` and
  `CRDTBL`, and ran to its end unattended, with the files dated in September
  and with every QFASL dated 5 October 2026 12:00 UTC; in the saved bands
  every loaded id that is a number, the cold load's 21 among them, equals the
  date the server gives (all 294 in the last build, with TIMPAR's fix under
  Faults fixed).
  On the 1001 band with `TIME` and `OPEN` loaded, a recorded text of
  15 January or 15 July 2026 12:00 came back 3600 and 7200 s off, and exact
  with `PARSE-COLD-LOADED-TIME`. `COLD-FILE-DATE-STRING` gives the text
  `date -u` does, the month's zero dropped, and the text parses back to the
  instant from 1970 to 2099: it prints the year in four digits, as the FILE
  server does (under Faults fixed).
- **The date check** (Q12, 1.11): a band built from this branch (the last
  of the incremental builds above), System 1002 on microcode 1000 under
  muir-sim's `cadr`, with ozd at its default
  `--file-dates utc`, once with the site at Europe/Berlin and once at `-1`.
  At noon UTC on 15 January, 15 April, 27 April, 15 July and 26 October
  2026, 1 March and 31 December 2000, and at 00:30 and 01:30 UTC on
  25 October 2026, both 02:30 of Berlin's repeated hour: a file whose mtime
  is the instant lists with that universal time, and a date the band sets on
  a file lists back as itself and is the file's mtime, to the second, in
  both runs. The control, ozd's `--file-dates mit --timezone -1`, is off by
  an hour in winter and two in summer; 1 March 2000 a day more, and
  31 December 2000 reads as no date at all. With the four-digit year (under
  Faults fixed) and ozd `52eb6b0`, 1970-01-01 00:00:00 and 2099-12-31
  23:59:59 UTC pass the same way in both runs.

## Faults fixed

- **FILE dates carry the year in four digits.** The cold-load builder's
  date text and the band's own FILE server printed `MM/DD/YY`, and the
  parser takes a two-digit year within fifty years of the present
  (`io1/time.lisp:177-184`), so a file of 1970 read as 2070 and one of 2099
  as 1999. ozd's `--file-dates utc` prints its FILE and MINI dates as
  `MM/DD/YYYY HH:MM:SS` from ozd `52eb6b0` on, and this line now prints the
  same: `COLD-FILE-DATE-STRING` (`cold/coldld.lisp:114-129`), whose text
  must equal QFILE's from the server so that QLD does not load the cold
  load's files again, and `CV-WIRE-TIME` (`file/server.lisp:42-60`), the
  old lines commented out in both. The parsers needed nothing:
  `PARSE-DIRECTORY-DATE-PROPERTY` reads the 19-character form and still
  the 17-character one, `PARSE-COLD-LOADED-TIME` puts the month's zero back
  in either, and `PRINT-DIRECTORY-DATE-PROPERTY` always printed four digits.
  Built with ozd `52eb6b0` only; an ozd before it sends two digits and
  every file MINI and QFILE read looks new to `MAKE-SYSTEM`.
  Red and green with `lispm-check` on System 1002 bands, the COLD system and
  `FILE; SERVER` compiled and loaded: for 1970-01-01 and 2099-12-31 both
  texts printed `70` and `99` and read back 3155760000 s off, and now print
  `1/01/1970 00:00:00` and `12/31/2099 23:59:59` (the builder's, month's zero
  dropped) and `01/01/1970 00:00:00` (the server's), and read back exactly;
  2000 and 2026 as before. A build like the ones above, with ozd `52eb6b0`
  at `mit -1` for the compile and the cold load and at `utc` from the cold
  boot: QLD read none of the cold load's files again (G1) and none of
  MINI's 38, ran unattended (G2), all 260 loaded ids equal their served
  dates (G3), `:print-only` lists nothing (G4), and the date check (G5,
  under Time zones) with a file of 1970-01-01 00:00:00 and one of 2099-12-31 23:59:59
  added lists and sets both exactly at Europe/Berlin and at `-1`, where
  ozd before `52eb6b0` gave them 3155760000 s off.
- **TIMPAR's own date is a number too.** Its initialization parses the
  recorded texts before TIMPAR's own loaded id is set, so that one stayed
  text, never equal to the file's date, and `MAKE-SYSTEM` took
  `SYS: IO1; TIMPAR` for a new file ever after. The id is text on the 1001
  band, and on a band built from this branch without this change
  `(make-system 'system :print-only)` listed TIMPAR. QLD now parses the
  recorded texts once more at its end (`sys/ltop.lisp:928-933`). MIT's;
  `main` has it fixed by the numbers of its file device. In a band built
  with the change no loaded id is text and `:print-only` lists nothing.
- **Dates in 1900, 2000 and from 2100 on are right.**
  `DECODE-UNIVERSAL-TIME-WITHOUT-DST` took every fourth year for a leap year,
  so it gave 29 February for 1 March 1900 and 2100, a day early for the rest
  of 1900 and from 2100 on, and 6 February 2106 for 2^32-1 seconds after
  1970 (the 7th); it now uses Howard Hinnant's `civil_from_days`
  (`io1/time.lisp:125`). `ENCODE-UNIVERSAL-TIME` counted every fourth year too
  (a day late from 2101), counted one leap day before 1900 (a day early all
  through 1900), and asked `LEAP-YEAR-P` about the year less 1900, which
  said 2000 was none (a day early from 1 March 2000); it now counts by the
  Gregorian rule. Both were MIT's. On the 1001 band,
  decoding 1 March 2100 and 1900, 31 December 1900 and 7 February 2106, and
  encoding 1 March 2000 and 1900, were wrong; with the change all eight
  dates are right.
- **Encoding and parsing a date agree with decoding on summer time.**
  `ENCODE-UNIVERSAL-TIME`, and `PARSE-UNIVERSAL-TIME` through it, asked the
  rule about the year less 1900, and `LAST-SUNDAY-IN-APRIL` took 1900 off
  again, so from 2000 on they put the change on other days than decoding
  did. On the 1001 band noon GMT on 27 April 2026 decoded to 14:00 in summer
  time and encoded back 3600 s off; the rule now gets the year in full
  (`io1/time.lisp:191`), and the time comes back. MIT's.
- **The directory date parser checks its fields.**
  `FS:PARSE-DIRECTORY-DATE-PROPERTY` took any two digits, so on the 1001 band
  a month of 13 stopped it with "The subscript 13 ... was out of range", and a
  day of 99 or a time of 25:61 made another time silently. A date out of
  range is now no date, as 00/00/00 already was (`io/file/open.lisp:1459`);
  a valid date still parses. MIT's.
- **The undefined-host fallback in `io/file/pathst.lisp` works.** Two places
  canonicalise the pathnames a cold load recorded, and each carries MIT's
  comment "Don't bomb out if host isn't defined" over an arm that bombs out:
  it sends `:PHYSICAL-HOST`, a message to a host, to a pathname. Both now ask
  the translated pathname for its host (`io/file/pathst.lisp:365`, `:436`).
  On the 1001 band `PATHNAME-FROM-COLD-LOAD-PATHLIST` of a host named
  `NOSUCHHOST` signalled that the logical pathname received an unclaimed
  `:PHYSICAL-HOST`; with the change it gives a pathname on OZ. Taken from
  lmz-sys, bishop's line (`6d1da93`).
- **The herald names the site, whatever it is.** MIT's `PRINT-HERALD`
  (`io/disk.lisp:1269`) printed "MIT System" for the site `:MIT` and "LMI
  System" for every other site, and trapped on an unbound site name in the
  line naming the machine. It prints the site's name now, and "UNKNOWN" when
  no site is loaded (`:1280`, `:1297`). On the 1001 band a site `:FOO` and a
  site of NIL both printed "LMI System"; with the change they print "FOO
  System" and "UNKNOWN System", and `:MIT` still prints "MIT System".
- **The error table is loaded at every boot.** A band caches its
  microcode's error table under the microcode's version number, and every
  unreleased build of a microcode keeps its number, so a band saved under
  one build kept that build's table under a later one and reported ordinary
  traps as "no error-table entry". `EH:INITIALIZE` (`eh/eh.lisp:2394`) now
  forgets the cached table at boot. On the 1001 band a cached table survived
  `EH:INITIALIZE`; with the change it is read again, and a trap (`(car 1)`)
  still reports correctly.
  - **So every boot reads `SYS: UBIN; UCADR TBL`.** Before, the table was
    read only when the microcode's version differed from the one the band
    last loaded; now the file server must serve the running microcode's
    `ucadr.tbl` in `SYS: UBIN;` at every boot, cold or warm.
- **QLD no longer stops at its second load of `CHSNCP QFASL`** with
  "(:INTERNAL GET-NEXT-PKT 0) is an invalid function". That load replaces
  the network code over the network, and fasload installs a function
  before the `#'(LAMBDA ...)` inside it, so a wait that falls in the gap
  calls the list `(:INTERNAL ... 0)`. Every wait in the file now uses a named
  predicate defined above its user: those of `GET-NEXT-PKT`, `SEND-PKT`,
  `ALLOCATE-INT-PKT`, `RECEIVE-ANY-FUNCTION` and `BACKGROUND`
  (`network/chaos/chsncp.lisp:909`, `:1173`, `:1253`, `:1743`, `:1860`).
  MIT's; it shows only when a wait falls in the gap, and it was not
  reproduced on the CADR. With the file compiled and loaded over the running
  network code on the 1001 band, the predicates are defined and a file
  probe over Chaos still answers.
- **`SI:LOAD-MCR-FILE` writes a partial last block.** It copied a `.mcr`
  file into a microcode partition a block at a time and, at the end of the
  file, returned without writing the block it had started, so a file that is
  not whole blocks lost its end without a word. That block is now written,
  filled with zeros (`io/disk.lisp:1413`). The micro-assembler's files end
  on a whole block (`sys/qwmcr.lisp:111` pads to a block before the symbol
  area, which is four pages), and every `.mcr` measured here does, so this
  system's own files never met it. On the 1001 band a file of 514 halfwords
  loaded its first block and left the second zero; with the change the
  second holds the last word, swapped as the first block's are, and zeros.
  MIT's; taken from `main` (`b729b53`, only this part of its
  `LOAD-MCR-FILE` change: the rest reads QUUX's partition order).
- **A physical pathname matches its own pattern again, so QLD no longer
  loads MINI's files twice.** `:PATHNAME-MATCH` and `:PATHNAME-MATCH-SPECS`
  took the pattern's components raw and the sample's through the accessors,
  which convert solid case, and compared them with case: an `OZ:` (or any
  Unix or LMFS) pattern such as `OZ: /sys/*/*` matched no pathname, not even
  itself. So nothing on OZ back-translated into `SYS:`: every file MINI
  loaded kept its loaded id and its functions' source file on an `OZ:`
  generic pathname, and QLD's `MAKE-SYSTEM`, finding no id on the `SYS:`
  one, read 34 of MINI's 38 files again over FILE in the build of the
  System 1002 band C2. Both methods now take the pattern's device,
  directory, name and type through the accessors too, and compare in
  interchange case (`io/file/pathnm.lisp:1948-1991`, the old lines commented
  out); a logical pattern matches as before, and case stays significant.
  Red and green with `lispm-check` on band C2: an `OZ:` pathname matches
  itself, the generic pathname of `OZ: /sys/sys2/flavor.qfasl`,
  `/sys/io/file/pathst.qfasl` and `/site/site.qfasl` is the `SYS:` one,
  back-translation gives the `SYS:` names, and dired's wildcard match of an
  `OZ:` directory holds; translation and case unchanged. A build like C2's
  with the change: FILE read none of MINI's files again from the cold boot
  on (C2: 34), MINI's files keep MINI's id on their `SYS:` generic, every
  loaded id is a number equal to the served date, and `(make-system 'system
  :print-only)` lists nothing. Taken from `main`, where it comes with a
  change to MINI's dates that this line does not need.

## The site

- **The site defines seven Lisp Machines, LISPM-1 to LISPM-7**, at Chaos
  177201 to 177207 (`site/hosts.text:11-17`), each with its name and
  location (`site/lmlocs.lisp:13-19`), so up to seven machines run at the
  site with no site files to edit. Not checked on a machine: the host table
  is generated from `hosts.text` by the SITE system.
- **The site names the zone Europe/Berlin** (see Time zones).

## Microcode 1000

- **The CADR's first changed microcode is 1000** (Mete, 2026-09-27: the
  CADR's numbers are in the 1000s and QUUX's in the 2000s; MIT's 323 stays
  as it is). It is 323 with the three fixes below and the PDL buffer's width
  named, assembled from `sys/ucadr/` with `ua:version-number` 1000 as
  `docs/building.md` describes; a band takes it from the MCR partition the
  label names, and reads its `ucadr.tbl` from `SYS: UBIN;`. It uses one more
  A-memory word (1177 against 323's 1176) and seven more I-memory locations.
  The outputs as assembled on 2026-09-28, twice, byte for byte (sha256):
  - `ucadr.mcr` `e16827c8a597f960bd5971df38565ce97415a17605b4953f7903aba0c700ab72`
  - `ucadr.tbl` `db5d83608fe3c7c63ec4e7ddc5cabff1bf86c221ddaa9bf450a8fcd9871f2737`
  - `ucadr.locs` `990536a35390c058b6ada50f0d9ca66094f3413489e75f8bd886e21a569914bb`
  - `ucadr.sym` `0f8645b3ef09312b4c9eb8d3581e9cb947c3c5575adf04d7424fa6378fb64d67`

  The number stays 1000, since it is unreleased; the assembly of 2026-09-27,
  before the trap fix below, gave `ucadr.mcr` `6b94aab7...`, `.tbl`
  `0545fbc2...`, `.locs` `77f365af...` and `.sym` `7c750b55...`, and the
  same sources assembled again on 2026-09-28 gave those four byte for byte.
- **The PDL buffer's width by name** (`ucadr/uc-macrocode.lisp`,
  `uc-page-fault.lisp`, `uc-stack-groups.lisp`): five masks written as
  `(BYTE-FIELD 10. 0)` and one comparison with the literal 2000 use
  `PDL-BUFFER-ADDRESS-MASK` and `PDL-BUFFER-SIZE-IN-WORDS`, which on the
  CADR are 10 bits and 2000 (`ucadr/uc-parameters.lisp:271,275`). Assembled
  on its own as 323 on a freshly booted 1001 band, it gave `ucadr.mcr`,
  `.tbl` and `.locs` byte for byte System 1001's.
- **Dividing by the most negative fixnum no longer corrupts or halts.**
  Negating -2^24, the most negative fixnum, gives 2^24, which must become a
  bignum, and making the bignum clobbers registers. `QDIV` kept a ratio's
  numerator in Q-R while its denominator was boxed, so on the 1001 band
  `(%div 5 -16777216)` gave `25\16777216`; `NORMALIZED-RATIONAL-FIX-SIGNS`,
  on the way from a bignum dividend, kept the numerator in M-J while it
  negated the denominator, and the next negation then got a raw integer and
  halted the machine, as `(floor 4294967295 -16777216)` did, in `XMINUS`.
  The unboxed numerator now waits in an A-memory word of its own,
  `A-QDIV-NUMERATOR` (`ucadr/uc-parameters.lisp:1221`, after the last
  variable, so no location moves), and the boxed one on the stack
  (`ucadr/uc-arith.lisp:1272`, `:3693`). MIT's. On System 1001's band booted
  on microcode 1000, `(%div 5 -16777216)` gives `-5\16777216`, the `FLOOR`
  gives -256 and -1, and `TRUNCATE`, `FLOOR`, `CEILING` and `%DIV` over 24
  values, the edges of the fixnum range and bignums among them, 2304 cases,
  agree with exact arithmetic on the host, but for `(%div 0 0)` (below).
- **`%DRAW-RECTANGLE` reads no row below the rectangle.** `XTVERS1` tested
  the column's remaining height at the top of its loop, after the jump back
  had started the read of the next row, so every erase read one row below
  its bottom; the count is now tested after each row, before the next read
  (`ucadr/uc-tv.lisp:327-342`). MIT's. With a read MAR on the word below a
  rectangle of four rows, drawn into a one-bit array laid over a vector,
  the MAR went off on 323 and does not on 1000; a MAR on the rectangle's
  last row goes off on both, and the words are left as they were.
- **A small-flonum overflow traps before its return, so proceeding from it
  works.** At `SFLPCK1` (packing a small flonum) and `XAPDLR`
  (`%ASSURE-PDL-ROOM`) the call to the trap sat in the microinstruction
  after a `POPJ-AFTER-NEXT`, so the trap ran with the return already made
  and the next macroinstruction fetched: the erring frame's PC was one
  instruction late. A small-flonum exponent overflow then named the next
  instruction ("POP produced a result too large", or
  `EH::MOVE-INSTRUCTION`) rather than `*`, and proceeding with a new value
  misplaced it: `(list 'a (* x x) 'b)` gave `(A NIL B)` or read a
  `DTP-FREE` word from the constants area, and `(* x x x x x)` of `1s10`
  gave `1.0s30` for `4.0s10`. `%ASSURE-PDL-ROOM`'s error, which cannot be
  proceeded from, left the PC one late too. Each now tests before it
  returns: `SFLPCK1` returns by a conditional `POPJ` with the store in its
  XCT-NEXT and jumps to `SFL-E-OV` on an overflow
  (`ucadr/uc-arith.lisp:760-773`), the same microcycles with no overflow;
  `XAPDLR` tests the frame size before a conditional `POPJ` and jumps to
  `XAPDLR1` (`ucadr/uc-call-return.lisp:1713-1727`), one microcycle more.
  MIT's, found on QUUX's line. On System 1001's band on microcode 1000,
  micro and rtl engines alike, 14 cases (proceeding with a new value three
  ways, the two messages, `%ASSURE-PDL-ROOM` within and over its limit, and
  the erring frame's PC at `CAR`'s trap, the overflow's and
  `%ASSURE-PDL-ROOM`'s) give 6 failures and 1 error before and pass after;
  microcode 323 gives the same answers as microcode 1000 before.
  Microcode 1000's earlier checks pass again: the smoke and
  `%DRAW-RECTANGLE` cases, and the 2304 division cases, whose output is
  byte for byte the earlier assembly's.

## Known faults found, not yet fixed

- **The boot PROM's `PAGE-0-PARITY-FIX` touches one word past page 0,**
  virtual 400, as MIT's own comment says. Left as it is for now (Mete,
  2026-09-27), with a comment at it in `ucadr/promh.text:403` so that a
  search finds it.
- **A date printed MM/DD parses as DD/MM outside the United States.** The
  default print mode is `:MM//DD//YY`, but `SET-MONTH-AND-DATE`
  (`io1/timpar.lisp`) reads two numbers of 12 or less as month and day only
  when `*TIMEZONE*` is 4 to 10: with Europe/Berlin `03/01/2026` parses as
  3 January. MIT's.
- **`(%div 0 0)` returns 0** rather than signalling division by zero: `QDIV`
  returns 0 for a zero dividend before it looks at the divisor. MIT's.

## Around the system

- **`tools/lispm-check`** checks a Lisp change on a saved band in seconds,
  from a checkpoint of the band at its prompt (`docs/lispm-check.md`).
  `--ozd-file-dates mit|utc` and `--ozd-timezone N` pass ozd's
  `--file-dates` and `--timezone` on, so that a band of Systems 100 to 1001,
  which reads FILE dates at its site's zone, is served them so: measured on the
  1001 band, a file's date is exact with `mit` and `-1`, and 3600 s early in
  January and 7200 s early in July with ozd's default, `utc`.
- **`docs/booting.md`** follows a CADR from power-on to the first
  macroinstruction, carried over from lmz-sys (`fecd0a5`) with every
  citation checked against this tree.
- **`docs/building.md`** says what the 2026-09-22 rebuild of Systems 1000
  and 1001 added, why files the cold load reads over MINI use spaces only
  (also in `site/sys.translations`), that a second assembly in one band
  reuses the sources it read, and that the served `SYS: UBIN;` must hold the
  running microcode's table. It says how System 1002's release is built
  (`docs/building.md:199`): a clean build from the commit on System 1001's
  band, ozd at `--file-dates mit --timezone -1` while that band compiles and
  makes the cold load and at `utc` from the cold boot on, the builder kept
  on its own site and time code, the gates after QLD, and the one hour of
  QFASL dates it cannot take.
- **The release tools, from `main`** (`1331881`, `f5a60d5`), tracked by
  `.gitignore:39-42`. `tools/release-scan` reads every byte a release
  publishes (a gzip and its header, a tar's members and headers, a pack raw,
  a VHD through its block table) and fails on a local path, a private
  address, an e-mail address, this machine's or user's name, or a tar member
  not owned by root, unless one of its four rules passes it; its baseline,
  `tools/release-scan.baseline`, holds the digests of what `release-1001`'s
  two assets already hold. `tools/release-sums` writes and checks
  `SHA256SUMS`, with a line for the pack uncompressed, and compares GitHub's
  digests of the uploaded assets. `tools/release-test` holds both to planted
  faults. Two changes from `main`'s: the self-test plants its home directory
  in `sys/io/file/open.lisp` (`tools/release-test:209`), since
  `sys/io/file/hostfs.lisp`, where `main`'s plants it, is QUUX's file device
  and not on this line, so that case saw no fault; and it now refuses a fault
  planted into a file the tree does not have (`tools/release-test:108-112`).
  Measured: all 25 cases hold with `release-1001-pack.img` and a System 2000
  disk; the scan of this line's `git archive` as a root-owned tarball and of
  a System 1002 pack pass with nothing FAIL and nothing new to the baseline.
- **`docs/building.md` says how a release is published**
  (`docs/building.md:310`): the assets `release-1002-pack.img.gz`,
  `release-1002-sys.tar.gz` and `SHA256SUMS`, every tarball member owned by
  root, one gzip route (Python's `gzip`, no name, no date), then by the SHA
  of one commit: the sums and the scan, the commit on `cadr` and not `main`,
  the annotated tag, a draft, the draft downloaded back and checked (sums
  against GitHub's digests, scan, owners, the pack's `LABL`), and publishing
  with Latest set and read back: Latest while no QUUX release exists, and
  `--latest=false` after one does (Q12 §1.9). From `main`'s section of the
  same name, for the CADR's line.
- **`cold/export.lisp` says where the sync functions live**: `SETUP-CPT`,
  `START-SYNC`, `STOP-SYNC` and `FILL-SYNC` are all defined in
  `WINDOW; COLD` (`cold/export.lisp:156-169`). From lmz-sys (`189eeea`).
- **Three places call lmz-sys "bishop's line"**, as these notes do, where
  they gave it the number that is now QUUX's system's: `docs/booting.md:8`,
  `docs/building.md:302` and the comment at `io/file/pathst.lisp:362`.
