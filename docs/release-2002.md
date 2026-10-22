# System 2002

What QUUX's next release changes from System 2001. It is in progress on
`main`: each change is recorded here as it is made. Every change to a source
file carries a comment in that file saying why.

- **The system number is 2002** (`patch/system.patch-directory`,
  `patch/system-2002.patch-directory`), now that System 2001 is released,
  so that no band built from `main` calls itself 2001.
- **Microcode 2002 and boot PROM 2002.** System 2002, microcode 2002 and PROM
  2002 are released together, on QUUX's revision 15; revision 14, a step
  toward it, is an internal milestone and is never released on its own (Mete,
  2026-10-04). As for 2000 and 2001, the version is not in the sources but
  given to the assembler (`ua:version-number` and the output's version for
  `UCADR`, the version asked for `PROMH`), so no source changed for it.
- **The microcode symbol area holds plain addresses**
  (`sys/sys/qwmcr.lisp:175-184`, WRITE-MICRO-CODE-SYMBOL-AREA-PART-2). The
  `.mcr` writer added the assembling world's fixnum tag to each entry of its
  main-memory section: a 32-bit world, System 2000's, puts it in `<29:25>`,
  pointer bits on the 40-bit machine, so on Systems 2001 and 2002 every entry
  read as its address plus `1200000000` (`MA-INFO` printed "ucode adr
  1200006130" for 6130); a 40-bit world puts it above the file's 32 bits.
  The microcode uses only `<13:0>` of an entry, so it was unaffected, but the
  same sources gave two files by the band that assembled them. For a 40-bit
  target each entry is now written as its value alone (the disk read puts
  tag 005 above it); a 32-bit target keeps the tag. Assembled on System
  2000's band and on System 2002's revision-14 band the files are now byte
  for byte the same; microcode and PROM 2002, unreleased and keeping their
  numbers, have new checksums: `ucadr.mcr`
  `9492d0d95427d38d3c89571eaf5025870b93e52fe5c0443a7c48bd4e92e1499d`
  (`.tbl` `92829944434d58658d25bd2c86336131a90b57cba1b336c0d76cced07ea1f56a`,
  `.locs` `1c9f78c7d59b7d4d8041b95cec6722727d2828b9a9cc95421dbf4efd15468c8f`,
  unchanged) and `promh.mcr`
  `6a09939858e470fa356112694b6088596b32f1453a43e935c2bbb55c0dc7b8fb`
  (`.tbl` `7d09233755ea154053980d261d62f308cdc442a616ff95fe9c707c84de45b0d6`,
  `.locs` `97eef746efccb8c508116e73242d2de6105979da48fb0d9f632cdc8500e03e5d`,
  unchanged); before, `ucadr.mcr`
  `225aee9bc7a1c62369f58e3b5b59b8f1525ecc1ca5b2829b71f62947a9f2af58` and
  `promh.mcr` `c053248cdab09ac3c23b2263433fddd63a12b3fc39627e5f7b24078039614e73`
  from System 2000's band.
- **FORMAT forgets the clause strings it gives back**
  (`sys/io/format.lisp:1315`, FORMAT-RECLAIM-CLAUSES). The clause buffer,
  FORMAT-CLAUSES-ARRAY, kept for the next call, still held each `~[`, `~<`
  or `~:[` clause's string after RETURN-ARRAY gave its storage back, and the
  collector scans the buffer whole, past its fill pointer. Once that
  storage's page was brought back fresh by CONSF (`M-DONT-SWAP-IN`),
  `%FIND-STRUCTURE-HEADER`'s scan back from the pointer could meet the
  GC-FORWARD words of an object copied before it, and the machine halted in
  ILLOP (HALT-CONS from XFSHS1+2): muir-sim's profile with continuous flips
  at 2 M words halted so on revision 14, and a planted run halts System 2001
  as well. The string's and the parameters'
  slots are now cleared as they are given back. `tools/system-check` gains
  `format-clauses` and `format-clauses-gc` (`cases-2mw/`, at 2 M words; its
  `run` now takes `cases-2mw/` as `tools/microcode-check`'s does).
- **After `SET-MAR`, every write into the range traps, not only the first**
  (`restore-mar-mode-from-foothold`, `sys/eh/eh.lisp:320-336`, called by
  `fh-applier`, `fh-applier-no-restart`, `fh-evaler` and
  `fh-stream-binding-evaler` when a throw leaves them, `:887`, `:900`,
  `:930`, `:976`). The error handler signals the MAR's break in the erring
  stack group through `run-sg`, which turns that stack group's MAR off while
  the handlers run (`:407`, MIT's line, marked "why??"); only
  `sg-restore-state`, on the return to the error handler, turned it back on.
  A break proceeded (the debugger's Resume, a handler returning
  `:no-action`) kept the MAR on, but one left by a throw (`condition-case`,
  an abort) left it off for good: the next write into the range did not
  trap, `mar-mode` said `NIL`, and `%MAR-LOW`, `%MAR-HIGH` and the pages'
  trap status stayed set. The FH- functions now put back the MAR mode saved
  in their foothold as they are thrown through, so the MAR stays armed until
  `CLEAR-MAR`, as after proceeding. The CADR's line has the same fix
  (System 1004). `tools/system-check`'s check `mar-range` has three new
  cases: System 2002's revision-14 band gives `(T NIL NIL)` for two writes
  left by throws and `mar-mode`, where `(T T :WRITE)` is expected, and
  `(T T NIL)` for a proceeded break then two left by throws; the control,
  two proceeded breaks, passes on both.
- **COLLAPSE-DUPLICATE-PNAMES leaves no symbol in the package it gives back**
  (`sys/sys2/gc.lisp:1324-1332`, run by `FULL-GC` with `:DUPLICATE-PNAMES`).
  It interns every pname in the package "GC Temporary", which makes a new
  symbol there for each first pname, moves the ones with no value,
  definition or properties into `WORTHLESS-SYMBOL-AREA`, a static area the
  collector scans, then kills the package and gives its storage back with
  `RETURN-STORAGE`. Those symbols kept the package in their package cell: on
  the revision 14 hand-over's band 25,416 symbols, 2 of them in
  `WORTHLESS-SYMBOL-AREA`. Once that storage was consed again, reading such
  a symbol's package halted the machine (an array consed where the package
  was, then `TYPEP` and `ARRAY-LENGTH` of the package: HALT-CONS at PC
  11214, `GAHD1+6`, on microcode 2002). The package's symbols are now left
  with no package before it is killed. `tools/system-check` gains
  `collapse-pnames`; without the change its first case gives
  `(T 25416 2)` where `(T 0 0)` is expected, with it all four cases pass.
  The CADR's line has the same fault and the same fix.
- **The demo's PAINT-COM-TEXT-LEAVE forgets the string it gives back**
  (`sys/demo/npaint.lisp:947-952`). It returned the special
  `PAINT-TEXT-HOLDING-STRING`'s string with `RETURN-ARRAY` and left the
  special naming it, a pointer the collector scans to storage given back.
  The file does not load on this system (`DEFCLASS` is gone), so this is
  for the record. `tools/system-check` gains `npaint-text-leave`, which reads
  that one definition from the file: without the change the special names
  the string consed next, `(T T T)` where `(NIL NIL NIL)` is expected; with
  it both cases pass. The CADR's line has the same change.
- **`+`, `*` and `MAX` called as functions take a subnormal single first**
  (`sys/sys/qfctns.lisp:1585-1590`, PLUS; `:1620-1625`, TIMES;
  `:1499-1502`, MAX). PLUS started its sum from 0 and TIMES its product from
  1, so a subnormal first argument went alone through `(+ 0 x)` or
  `(* 1 x)`, whose result, a subnormal, trapped
  `FLOATING-EXPONENT-UNDERFLOW` when packed, since no subnormal is made
  (`SFLPACK-P`); MAX compared its first argument with itself, with the same
  trap. So, interpreted or through `APPLY` and `FUNCALL`,
  `(* x (scale-float 1.0 40))` and `(+ x 1.0)` trapped where the operands
  swapped gave the normal result, and under `ZUNDERFLOW` the product was 0.0;
  compiled code, where `(* a b)` is one instruction, was right, as are `-`,
  `//`, `MIN` and the comparisons, which start from their first argument.
  The microcode reads a subnormal operand in either position. A float first
  argument now starts the sum, the product and MAX's comparisons; any other
  starts from 0 or 1 as before, so a character still becomes its code and a
  non-number signals as before. System 2001 has the fault, against its notes
  (`docs/release-2001.md:1224`); it is not patched. `tools/system-check`
  gains `subnormal-operand-order`: the revision 14 hand-over's band fails
  14 of its 49 cases without the change (13 traps and the 0.0 under
  `ZUNDERFLOW`), and passes all 49 with it. The CADR's line has no
  subnormal floats, and there `(+ 0 x)` and `(* 1 x)` of a float are
  exact, so it is not affected.
- **The incremental save's compare reads pages by fixnum addresses**
  (`COMPARE-RANGE` and `PAGE-TAGS-EQUAL`, `sys/io1/inc.lisp:667`, `:711`).
  It walked every page of memory by locatives, the extra pdl's pages among
  them; a sequence break in that window switched stack groups, the pdl
  buffer's dump took the locative for a pointer into the extra pdl, and
  `EXTRA-PDL-TRAP` (`sys/ucadr/uc-transporter.lisp`) copied the word it named
  as an object's header, so the machine halted at ILLOP from `SINFSH`'s
  dispatch, in `tools/microcode-check`'s `generational-rqb` at `SINF-FLO` (on
  micro at 4, 5 and 6 ticks and on rtl at 5 and 6, measured). The two pages'
  addresses are now fixnums and each word is read through `%POINTER-PLUS` and
  `%P-LDB`, which reads the word at its argument's pointer field and
  transports nothing (`XPLDB`, `sys/ucadr/uc-fctns.lisp:1225`); the tags,
  `<39:32>`, are compared word for word as before. `tools/system-check`'s
  new check `extra-pdl-locative` holds the compare's fixnum addresses of an
  extra pdl page across a forced stack-group switch, and its plant file a
  locative, which halts the machine.
- **Every single prints as text that reads back as it** (`print-flonum`,
  `sys/io/print.lisp:645-660`, `:671-676`, `:686-699`, `:712-713`;
  `flonum-digits`, `:745-826`; MIT's). The printer scaled a float outside
  [1e-3, 1e7) to [1, 10) by floating multiplication or division, which
  loses bits, and printed the scaled float's digits: the most positive
  single printed as `3.4028237e38`, which reads as an infinity, the least
  positive normal one as `1.1754943e-38`, below it, which underflows, and
  6.02e23 as `6.0200005e23`. `flonum-digits` gives the E format's digits
  exactly, in integers, from the float's bits: the fewest that read back as
  the float (Steele and White's free-format method, as Burger and Dybvig
  give it). The printer negated a positive float first, and for a subnormal
  that signalled "MINUS produced a result too small", as arithmetic makes no
  subnormal. Since the reader underflows below the least normal single, as
  arithmetic does, a subnormal now prints as
  `#.(SI:SINGLE-FLOAT-FROM-BITS #x...)`, its bits in hexadecimal, as an
  infinity prints as its constant (`SINGLE-FLOAT-FROM-BITS`,
  `sys/sys2/numer.lisp:582`). Floats in [1e-3, 1e7) print as before.
  `tools/system-check` gains `float-round-trip`: 18 extremes and constants
  of both signs, 1522 powers of two and the singles beside them, 152 singles
  nearest powers of ten, 3000 pseudo-random normal singles and 208
  subnormals. The System 2001 hand-over band of 81b3973, whose float code
  is this tree's, fails 6 of its 8 cases and errs in one: 12, 338, 0, 802
  and 208 singles do not come back; with the change all 8 pass. The
  CADR's line has the same printer fault, and a reader fault besides, both
  fixed there in System 1004.
- **FORMAT's `~E` and `~G` give a float's exact digits**
  (`sys/io/format.lisp:826-846`, FORMAT-CTL-HAIRY-E-FORMAT; `:952-955`,
  `:965-968`, FORMAT-CTL-HAIRY-G-FORMAT; `sys/io/print.lisp:845-915`,
  `flonum-decimal-exponent`, `flonum-e-exponent`, `flonum-scaled-to-string`;
  `flonum-digits`, `:748-751`, `:771-775`, `:792-796`, `:810-825`). `~E` took
  its power of ten and its digits from `SCALE-FLONUM`, which scales the
  float to [1, 10) by floating multiplication and loses bits, and from
  `FLONUM-TO-STRING` of the scaled float: it printed the most positive single
  as `3.4028237e+38`, which reads as an infinity, the least positive normal
  one as `1.1754943e-38` and 6.02e23 as `6.0200005e+23`. `~G` chose between
  `~F` and `~E` by `SCALE-FLONUM`'s power of ten, one off for 36 of the 152
  singles nearest powers of ten. Both stopped on every subnormal, as `ABS`
  of one signals "ABS produced a result too small", and on zero, with a
  subscript error in `SCALE-FLONUM`. `~E` now prints the printer's digits
  (`flonum-digits`, the fewest that read back as the float) with their
  exponent, a subnormal too (`-1.0e-45`), and zero as `0.0e+0`; `~G` takes the
  float's power of ten exactly, in integers, from its bits. Digits cut by
  `~,dE` or by the width round to the nearest, a tie to the even digit, as
  IEEE 754 rounds: `~,2E` of 1.375 gives `1.38e+0` and of 1.125 `1.12e+0`
  (MIT's `~E` rounded a tie down, giving `1.37e+0`; `flonum-digits` rounded it
  up, giving `1.13e+0`). `flonum-digits` rounds its cut so for every caller,
  `PRINT-FLONUM`'s MAX-DIGITS too. `~F`, and `~G` when it chooses `~F`, still
  round a tie down, in `FLONUM-TO-STRING` (`~,2F` of 0.375 is `0.37`). The
  exponent's width is chosen before the digits round, as MIT's `~E` chose
  it: `~,1E` of the single nearest 9.96e-10 is `1.0e-09`, as before.
  `flonum-digits` also counts a decimal halfway to a neighbour as the
  float's when the significand is even, as the reader rounds such a decimal
  to even: 1.5e10, halfway between two singles, now prints as `1.5e10`, not
  `1.5000001e10`, and `~E` gives `1.5e+10` as before. When the cut leaves a
  single digit, that digit now rounds: `~,0E` of 9.7 gives `1e+1` where it
  gave `9e+0`, as the old `FLONUM-TO-STRING` truncated an integer digit.
  `tools/system-check` gains `format-float-digits` (43 cases, its functions
  in `lisp/float-round-trip.lisp`): `~E`, `~,3E`, `~G` and `~,4G` over
  `float-round-trip`'s samples, against the printer's digits, and ties that
  tell the three rounding rules apart. The tree before the change fails
  19 of the 43 and errs in 2 (revision 14). `~E` gives other digits for 2223 of the 4690 floats of the
  samples that are not subnormal, and `~E` and `~G` stop on all 208
  subnormals. With the change all 43 pass, on revisions 14 and 15. The
  CADR's line has the same `~E` and `~G` path.
- **FORMAT's `~F`, `~$` and `~G` give a float's exact digits**
  (`sys/io/format.lisp:772-784`, FORMAT-CTL-HAIRY-F-FORMAT; `:980-982`,
  FORMAT-CTL-HAIRY-G-FORMAT; `:1013-1025`, FORMAT-CTL-MONEY; `:868-874`,
  FORMAT-CTL-HAIRY-E-FORMAT; `sys/io/print.lisp:916-993`,
  `flonum-half-compare`, `flonum-fixed-to-string`). They took their digits
  from `FLONUM-TO-STRING`, which carried nothing out of the integer part
  from 2^24 up, so `~F` of the single nearest 1e11 printed `:0000000000.0`
  (36 of the 152 singles nearest powers of ten, under `~F`, `~G` and `~$`
  alike). It also took half a gap on both sides of a power of two, where the
  gap below is half the gap above, so 46 powers of two (34 under `~G`), such
  as 2^-103, printed digits that read back as the single below. It rounded a
  cut digit's tie down, and it truncated the integer digit when no fraction
  digit was left (`~,0F` of 3.7 printed `3.`). `~F` and `~$` stopped on
  every subnormal, as `ABS` of one signals, a negative scale (`~,,-2F`)
  stopped with a subscript error, and a positive one multiplied the float.
  `flonum-fixed-to-string` lays out `flonum-digits`'s digits as
  `FLONUM-TO-STRING` laid out its own: the width, the dropped leading zero,
  overflow and padding as before. A cut rounds to the nearest, a tie to the
  even digit, as `~E`'s does: `~,2F` of 0.375 gives `0.38` (it gave `0.37`)
  and of 0.125 `0.12`. A cut to no fraction digits rounds the integer digits
  (`~,0F` of 3.7 gives `4.`, `~5F` of 123456.7 `123457.`), and the scale
  moves the point exactly. `~F` and `~$` pass the float itself, as `~G` does.
  `~$` keeps its 1e50 test for numbers other than floats only, since no
  finite single reaches it. With no width, `~,2,,0E` prints its leading
  zero, `0.12e+3`, as when a width leaves room for it; comparing the width
  with NIL stopped it with an error. MIT's lines are commented out in place.
  `tools/system-check` gains `format-float-fixed` (58 cases, its functions in
  `lisp/float-round-trip.lisp`). The tree before the change fails 18 of the
  58 and errs in 8; with it all 58 pass, on revisions 14 and 15. The CADR's
  line has the same `FLONUM-TO-STRING` and the same `~E` code, but no
  subnormals.
- **The printer prints `~F`'s digits** (`sys/io/print.lisp:1019-1025`,
  `PRINT-FLONUM-INTERNAL`). A float in [1e-3, 1e7), printed with no exponent,
  took its digits from `FLONUM-TO-STRING`. Where two shortest decimals lie
  equally near the float, that took the lower and `flonum-digits` the upper,
  so `prin1` and `~F` gave other digits, both reading back: 2097152.25
  printed as `2097152.2` and `~F` gave `2097152.3`. Of the samples of
  `float-round-trip`, 19 such floats change, all of the form n.25 or n.75 (or
  382884.625) between 2^18 and 2^22. The printer now lays out
  `flonum-digits`'s digits with `flonum-fixed-to-string`, as `~F`, `~$`,
  `~G` and the E format do. `float-printing`, `float-round-trip`,
  `float-reading` and the format checks pass. `format-float-fixed` gains five
  cases, which fail 4 without the change. `FLONUM-TO-STRING` stays, and
  nothing in this tree calls it; it is still exported (`sys/cold/export.lisp:129`).
- **A float halfway between two shortest decimals prints the even one**
  (`sys/io/print.lisp:820-828`, `flonum-digits`; its comment `:751-753`).
  Where two decimals of the fewest digits lie equally near the float and both
  read back as it, `flonum-digits` took the upper, Burger and Dybvig's
  choice; it now takes the one with the even last digit, as IEEE 754 rounds
  a tie and as a cut at `MAX-DIGITS` already did. `prin1`, `~F`, `~$`, `~G`
  and `~E`'s free-format digits all follow: 2097152.25 prints as `2097152.2`
  (it printed `2097152.3`) and 382884.625 as `382884.62`. Of the 19 such
  floats in `float-round-trip`'s samples, 13 change; the six of the form n.75
  already ended in an even digit. The earlier line is commented out in
  place. `format-float-fixed` gains four cases and changes one: the 19
  floats' `prin1` and `~F` texts, and two of them under `~E`. The tree
  before the change fails 5 of the 67, and so does it with the upper digit
  put back alone. With the change all pass on revisions 14 and 15, as do
  `format-float-digits`, `format-float`, `float-printing`, `float-reading`,
  `float-round-trip` (every printed float reads back) and `format-clauses`.
  The CADR's line has the same upper-digit choice in its `flonum-digits`.
- A new check, `tools/system-check/cases/pointer-unsigned.cases` (row in
  `tools/system-check/README.md`): `SI:%POINTER-UNSIGNED`
  (`sys/sys/qrand.lisp:21`) and `SI:PRINT-POINTER-FIELD`
  (`sys/io/print.lisp:574`) on 32-bit fields with <31> set and clear. System
  2001 printed `#x807FFFFF` as `-17F800001`, its `%POINTER-UNSIGNED` (MIT's,
  from `sys/sys/qmisc.lisp`) adding the shifted sign bit instead of
  subtracting it; System 2002's already subtracts it.
- **A locative into the middle of an extra-pdl object is copied out with the
  object** (`EXTRA-PDL-TRAP-2`, `sys/ucadr/uc-transporter.lisp:558-585`;
  `TRANS-COPY-1K`, `:357-363`). A bignum made by arithmetic lies in
  `EXTRA-PDL-AREA` until it is stored. When a pointer into it is stored, or
  dumped from the pdl buffer at a stack-group switch, the write test calls
  `EXTRA-PDL-TRAP`, which copies the object with `TRANS-COPY` and then reads
  the copy's header to find its boxed words. It read that header at the
  copy of the pointer stored, which for a locative to one of the bignum's
  digits is that digit: `SINFSH` dispatched on the digit's header-type bits,
  so bits that name no header type halted the machine in `ILLOP`
  (`SINF-FLO`) and any other gave a wrong number of boxed words, which the
  trap then write-tested. `TRANS-COPY` now leaves the copy's first word in
  `A-TRANS-TEM`, and the trap reads the header there. MIT's microcode has
  the same path; fixed on the CADR's line in the same way.
  `tools/microcode-check`'s new check `extra-pdl-interior` stores a
  locative to 2^63's second digit, a word of 0, into an array and holds one
  across a stack-group switch: microcode 2002 halted at `SINF-FLO` on micro
  and rtl, and with the change its three cases pass, interpreted and
  compiled. `tools/system-check`'s planted `extra-pdl-locative` holds a
  locative past every object of the extra pdl; the trap gives it the
  copy's address plus its offset, so the plant fails its second case,
  `(T NIL)`, on both engines; before, the run halted or not by what lay at
  that address (at `SINF-FLO`, `TRANS-REALLY-TRAP` or `SG-LOAD-STATIC-STATE`,
  and on rtl once not at all), a fault of the microcode and not of the
  engines. Microcode 2002's files changed again, one instruction more: at
  revision 14 `ucadr.mcr`
  `3a89c1bef30604a577dcff7e0333f4735afcbc9d6510fa1ffd690d835f238d9f`, at
  revision 15 `ucadr.mcr`
  `33d546109530fa8e3f31cd3a43fbd8633a3d8a10dcc25ccd26e1709462390fbf`, both
  with `.tbl` `22632c9d4862e9b694367da58de8c59d00c7814782f18fffa52693b4bbf5881b`,
  `.locs` `9f7918e8e496a3d1d1161c7417b37df1549a53c86aa48496300c0cf08aa4ea79`
  and `.sym` `7e7f11c636e489f4803f07ad074fe8ddaa76488d3b44d66dde65eb8b7f8bbcf4`;
  `promh.mcr` is unchanged at both. System 2002's band on the revision-14
  microcode passes step 2's gate on micro and on rtl as before, the new
  check with it (on rtl `generational-tuning`'s case that counts automatic
  young collections fell short once in three runs, as it did in three runs
  on the microcode before the change); at revision 15 System 2002 reaches its listener on micro;
  `tools/assembler-check` passes all 30 checks, its revision-15 counts
  unchanged.
- **Region-to-area's walk keeps its region across the interrupts it can
  take** (`REGION-TO-AREA-WALK`, `sys/ucadr/uc-page-fault.lisp:2504-2518`).
  `REGION-TO-AREA` keeps each region's area in a byte of
  `A-REGION-AREA-MAP`, and a byte that says not yet known makes it walk the
  region's list thread and keep what it finds. The walk held the region
  number in `A-TEM1` across its reads, which page faults and interrupts
  clobber, and an interrupt can be taken at each read: the tick's
  `TRACK-MOUSE` (`sys/ucadr/uc-track-mouse.lisp:202`) sets `A-TEM1` to 4
  times the mouse's delta, 0 at rest, so the area went into region 0's
  byte, and `%AREA-NUMBER` and the transporter's destination area were wrong
  for region 0's objects until the next boot. `generational-tuning`'s
  `gt-check` found it now and then (micro at 2 MW, rtl at 32 MW). A swap-in
  during the walk did no harm: it leaves `A-TEM1` at the faulting address,
  whose low byte is the region's in the page-aligned thread. The region is
  now kept in `M-A`, which page faults and interrupts keep. The CADR's line
  is not affected: MIT's `REGION-TO-AREA` walks for every call, with no
  table, and keeps nothing across its reads. `tools/microcode-check`'s new
  check `region-area-map-interrupt` runs the tick at 200 and 50
  microseconds while every region's byte is forgotten and looked up again:
  microcode 2002 without the change failed all three storms in each of 5
  runs at revision 14 (micro 3, rtl 2) and two of three in a run at revision
  15 (micro), and with the change all pass at both.
  Microcode 2002's files changed again, one instruction fewer: at revision 14
  `ucadr.mcr`
  `3c441381b47d01b2fbcdadbd2d6f6e3582575929251273e7fd67276b3fbab650`, at
  revision 15 `ucadr.mcr`
  `d52ab0e7fd9e2c84b9bf1f275baf6113d4071a56fc672171ae3e53bca6ff98a0`, both
  with `.tbl` `f656fc9cbcd843adcdc582268c7489bb4c7d3db647afa46a4a48f74fdf4133fa`,
  `.locs` `6f8437661b18529ae5a24dfacf9a58376e37412f1ef69d7d2d72b041e4360f60`
  and `.sym` `126c54ea4e8b670d9120af77c6e17be1069c56362b3abdd65f69f509a0e2c4f5`;
  `promh.mcr` is unchanged at both. System 2002's band on the revision-14
  microcode passes step 2's gate on micro and on rtl as before, the new
  check with it (on rtl C15, the incremental save and the self-test first
  timed out with the host heavily loaded, and passed run again); at
  revision 15 System 2002 reaches its listener on micro (muir-sim ffb241b);
  `tools/assembler-check` passes all 30 checks, its revision-15 counts and
  the profile unchanged.
- **`generational-tuning` waits for its three young flips**
  (`tools/system-check/cases/generational-tuning.cases`). The case that
  counts the young collections eden's filling starts consed a fixed 600 K
  words with eden at 128 K and wanted three flips; it now conses until the
  third, at most 1.2 M words, and records the first flip's words. GC-ON sets
  the clock's sequence break to every 6 60ths but leaves the count it was
  making at once a second, so the first flip after it can come up to 59
  60ths late: forced through GC-OFF, a sleep and GC-ON on rtl, the first
  flip came at 206-213 K words and the fixed loop saw only three. That count
  is left as it is. The new case passes on micro and rtl and fails, as it
  must, with the GC process disabled.
- **`generational-tuning`'s C31 cases keep tenured collections off**
  (`tools/system-check/cases/generational-tuning.cases`). C31 (b) conses
  300,000 words right after a young flip and expects the cons to finish the
  collection. At 2 M words of main memory the tenured generation has then
  grown past its growth limit, a quarter of main memory, and when the GC
  process ran between the young collection's end and the case's read of
  `%GC-FLIP-READY` it reclaimed and started a tenured collection, and the
  case read NIL (the revision-14 soak at 2 M words: 1 run in 20 of the
  check, 3 in 20 of an instrumented copy). The
  collector did what it should; the case's expectation was wrong. (a) and (b)
  now run with `SI:GC-TENURED-AUTOMATIC` NIL, set and restored on any exit,
  and a case after them checks that the setting is the system's again.
  Forced by a growth limit of 1 word and a scheduler pass after the flip and
  after the cons, (b) read NIL with one tenured collection started in 6 runs
  of 6 before the change (2 M and 32 M words), and T in 6 of 6 after it.
  The check passes 20 runs of 20 at 2 M words on micro at revision 14 and
  at revision 15, and once on rtl at revision 15; with the restore taken
  out, the new case fails.
- **APPLY stops spreading at `%SPREAD`'s limit, with its error** (`UAPLY5`,
  `UAPLY-TOO-LARGE`, `sys/ucadr/uc-call-return.lisp:2150-2185`; MIT's).
  `APPLY` spread its list onto the stack with no size check, unlike `%SPREAD`
  and `%ASSURE-PDL-ROOM`, which stop a frame at 370 octal words and signal
  "Attempt to make a stack frame larger than 256. words."
  (`STACK-FRAME-TOO-LARGE`, `:1781-1916`). A call block opened above a larger
  frame holds its deltas to the active and open blocks in 8 bits
  (`%%LP-CLS-DELTA-TO-ACTIVE-BLOCK`, `%%LP-CLS-DELTA-TO-OPEN-BLOCK`,
  `sys/cold/qcom.lisp:628-631`), and they wrap. An interpreted function's
  entry (`INTP1`) opens `APPLY-LAMBDA`'s call block above its arguments, so
  `APPLY` of an interpreted `&rest` function to 252 arguments, a frame of 256
  words, halted the machine at `QMXSG` (`ILLOP`, "returning out top of stack
  group"; PC 1767), with or without a stack-group switch, on revisions 14 and
  15, micro and rtl; 250 and 251 returned. `APPLY` of a compiled function to
  300 arguments lost the listener instead: the throw out of the
  too-many-arguments error found no catch (`THROW-TAG-NOT-SEEN-ERROR`). The
  spread now stops after 249 arguments, flushes the call block it was filling,
  as a throw flushes a frame, so that the error's own frames open nothing
  above it, and signals `%SPREAD`'s error; a check that trapped with the call
  block still open left the machine in the throw (`XTHRW7`), the case
  unanswered. Fixed on the CADR's line in the same way.
  `tools/microcode-check`'s new check `apply-large-frame` applies interpreted
  `&rest` functions, one of them switching stack groups, to 249, 250, 252, 300
  and 600 arguments: microcode without the change returns 250 and halts at
  252, and with the check removed again the same (8 of its 12 cases fail or go
  unanswered); with the change its 12 cases pass on micro and rtl at both
  revisions. `rev14-fiddles`' interpreted frames take 248 arguments, not 250:
  `APPLY` spreads them with the hold's first, 249. The profile needs no
  change: no record's word moves, and the new jump has no record. Microcode
  2002's files changed again, eight instructions more: at revision 14
  `ucadr.mcr`
  `18ef4476f4727600ee57e7f301207974ddf4b753038009b4f008a9034b8240a5`, at
  revision 15 `ucadr.mcr`
  `e953197c00b7edee0f24c70ef2e460be70768ed86a184857dc929e88572c55af`, both
  with `.tbl`
  `eaa657df9c7cd4bd47b02d289ffa63eea3b81f6ad9840747f0e11e650f6d470e`, `.locs`
  `ece269715670c8faee9be05cf2e61dd74d2bac9168e425866c2828babffaa16f` and
  `.sym` `2efd4e36e65637e48bbd2087593580a686d0e98a8b18e526434b9757d47ea37d`;
  `promh.mcr` is unchanged at both. Step 2's gate was run with the change
  on b7943b2, before region-to-area's fix above, not on the tree with both:
  System 2002's band on that revision-14 microcode passes it on micro and on
  rtl as before, the new check and the save checks at 1920x1080 (C14) with
  it. With both changes the new check passes on micro and rtl at both
  revisions and `region-area-map-interrupt` on micro at revision 14; at
  revision 15 System 2002 reaches its listener on micro and on rtl; `tools/assembler-check` passes all
  30 checks, its revision-15 counts unchanged (359 hints, 140 predicted
  targets, every execution of the profile covered).
- **A call block is opened only below `%SPREAD`'s limit** (`CBM0`,
  `sys/ucadr/uc-macrocode.lisp:543-553`; `P3ZERO`, `P3ZERO-TOO-LARGE`,
  `CALL-BLOCK-TOO-LARGE`, `sys/ucadr/uc-call-return.lisp:15-50`). A call
  block holds its deltas to the active and open blocks in 8 bits
  (`%%LP-CLS-DELTA-TO-ACTIVE-BLOCK`, `%%LP-CLS-DELTA-TO-OPEN-BLOCK`,
  `sys/cold/qcom.lisp:628-631`), and the two openers, `CBM0` for macrocode
  calls and `P3ZERO` for the microcode's calls out to Lisp, stored them with
  no check: past 255 they wrapped, and the return through the block left
  the frames in disorder. 64 calls nested in one compiled expression, whose
  open blocks are 4 words of temporaries each, halted the machine at `TRAP`'s
  recursive-error `ILLOP` (PC `TRAP+13`); 4 calls nested above a compiled
  `&rest` frame of 240 arguments halted it at `QMMPO2`'s, in a process too;
  in a stack group of its own the 64 nested calls signalled a PDL overflow
  instead. Revision 13's microcode 2001 halts in the same way at 64.
  Each opener now refuses a block that would make the frame larger than
  `%SPREAD`'s and `%ASSURE-PDL-ROOM`'s limit, 370 octal (248) words counted
  as they count it, `PP - AP - 1`, with the block pushed: a delta to the
  active block, the larger of the two, of at most 249. It signals their
  error, `STACK-FRAME-TOO-LARGE`; `P3ZERO` pops the word it has already
  pushed first, and nothing else is changed, so the error is handled as
  any other and the listener answers afterwards, in a stack group of its own
  or a process as well. A check at 255 would not do: the error handler's
  frame, pushed where the refused block would have gone (`SG-SAVE-STATE`,
  `sys/eh/eh.lisp:250-255`), wraps in the same way, and the listener was
  lost at every refusal.
  Now refused, which worked before: 63 nested calls (a delta of 252; 62 is
  248); a compiled `&rest` function with 4 calls nested above 233 arguments
  (250; 232 is 249); an interpreted function given 246 to 251 arguments
  (its entry, `INTP1`, opens `APPLY-LAMBDA`'s block N + 4 words above it;
  245 is 249), so `APPLY` of an interpreted function now takes at most 245
  arguments, not 249, and `rev14-fiddles`' interpreted frames 244.
  The limit that remains: an interpreted function given 252 arguments or
  more by a compiled caller is refused too, but its frame is already past
  255 words when its entry opens the block, and the error handler's frame
  wraps: measured at 252 and 300 arguments, the error is signalled, the
  throw back to the listener finds no catch, and the listener is lost; the
  machine does not halt. The compiler does not limit the arguments of a
  call.
  `tools/microcode-check`'s new check `call-block-large-frame` opens blocks
  above such frames each way and at each limit, and in a stack group and a
  process: microcode without the change fails all ten of its error sections
  (four halt, six return), one that refuses only past 255 fails all ten
  (five lose the listener, five return), and with `P3ZERO`'s jump removed
  three fail; with the change its 22 cases pass on micro and rtl at revisions 14 and
  15, as do `apply-large-frame`, `rev14-fiddles` and
  `region-area-map-interrupt`. The two new jumps were never taken in the
  profile's 13 workloads on revision 15's pipeline at 2 M words (663,177
  opens) and need no hint: an open costs about two clocks more (1.8 on
  `calls-ack`, 2.0 on `calls-fib`, where it adds 0.8% to a macroinstruction's
  clocks), 0.30% of the 13 workloads' clocks. Microcode 2002's files changed again, seven instructions
  more: at revision 14 `ucadr.mcr`
  `2a6ee202765bcf0ac6b65c5cdcce5e02056602eae0d17f63fb90c847a45697f4`, at
  revision 15 `ucadr.mcr`
  `7dc213f7e82d5761c0a0a40ea03a0dee7cad9be10e2c7ec2fe37c5eab1c3e73e`, both
  with `.tbl`
  `0c10806bbd3c8362a2f3af0777edd17c3d49df51f5f339f8ab339eea773c0246`, `.locs`
  `8df06bad87552c572696b5207b6bf518686153030c666a939ba679d4cd1cd5fb` and
  `.sym` `40c6085b57e59608968de17467edcef8b632822368359c32e84bd41898e6d424`;
  `promh.mcr` is unchanged at both. Step 2's gate on revision 15 micro, with
  System 2002's band on this microcode, gives what it gave at revision 14
  with FORMAT's change, line for line, but for the new and changed checks
  above and three lines that differ by how they ran: `generational-rqb` runs
  once at revision 15's period, not at 4, 5 and 6 ticks; the band's FORMAT
  is older than its change, so `format-float-digits` passes, 43 of 43, only
  run with its files as its row says; `eden-default` is run when named.
  `tools/assembler-check` passes all 30 checks, its revision-15 counts
  unchanged (359 hints, 140 predicted targets, every execution of the
  profile covered).
- **"Creates the directory and tries again" works on `FILES:`**
  (`sys/io/file/hostfs.lisp:87-93`, `:251`, `:260`, `:271`, `:387`, `:715`).
  Opening a `FILES:` file for output in a directory that does not exist
  offered it, s-A in the debugger; it made the directory and then stopped at
  "Invalid proceed-type :RETRY-FILE-OPERATION returned by handler for
  #<FS::DIRECTORY-NOT-FOUND-ERROR ...>" (`sys/eh/ehf.lisp:861`), as System
  2001's notes record. `DIRECTORY-NOT-FOUND-ERROR` offers the option whatever
  the signal accepts and proceeds with `:RETRY-FILE-OPERATION`
  (`sys/io/file/open.lisp:190-201`), which the file device's operations did
  not offer: `FILE-DEVICE-ERROR` signals with no proceed type, and nothing
  around it gave one. QFILE signals the same way but runs each operation
  inside `FILE-OPERATION-RETRY` (`sys/io/file/access.lisp:14-27`), which
  offers the retry; the file device's operations that can fail, open,
  delete, rename, creating a directory and a directory's listing, now do
  too, so the option makes the directory and the open is tried again, and
  the debugger also offers "Retry the operation on the same file" for their
  errors. The operations that `FILES:` does not have (changing properties,
  links, expunge, remote connect) and the streams' reads, writes and closes
  offer no retry, as before. The other proceed types such an error can be
  offered are given by its callers or its condition, not by the device:
  `:NEW-PATHNAME`, from `OPEN`, `DELETEF` and the like
  (`FILE-RETRY-NEW-PATHNAME-IF`, `sys/sys2/lmmac.lisp:1324-1345`), writes
  another file instead (measured), and a full host's `:DIRED` and
  `:CLEAN-DIRECTORY` (`NO-MORE-ROOM-ERROR`) run their tool and return to the
  debugger without proceeding. `tools/system-check` gains
  `host-create-directory`, 24 cases: without the change 11 pass at
  revisions 14 and 15 on micro and 11 at revision 15 on rtl; with it 24 at
  each; with one operation's `FILE-OPERATION-RETRY` taken out, that
  operation's case fails, for each of the five.
- **An interpreted function runs while `SELF` is an instance**
  (`sys/sys/eval.lisp:2453-2467`, `:2486-2498`, `APPLY-LAMBDA`). Called
  while `SELF` is an instance, as a `CONDITION-BIND` handler written as
  `#'(lambda ...)` is when the error is signalled inside a method (the file
  system's `OPEN` signals from one), an interpreted `DEFMETHOD`, a
  `CONDITION-CALL` clause, or a lambda given to `:FUNCALL-INSIDE-YOURSELF`,
  every interpreted function stopped at "The function %PUSH is undefined."
  `APPLY-LAMBDA` binds the instance's variables and then pushes the binding
  of `.SLOTS.BOUND.INSTANCE.`; the push, and the place it compares, were
  wrapped in a `LOCALLY` for its `SPECIAL` declaration, and the compiler has
  no `LOCALLY` inside a body: it compiles one as a `%FEXPR-CALL` of the
  interpreter's `LOCALLY` (measured in the band's `APPLY-LAMBDA`), so the
  interpreter evaluated the `%PUSH`, an instruction with no function
  (`sys/cold/defmic.lisp:229`). A compiled handler is called directly and
  never met it, so the same code compiled worked. A `LET` with the
  declaration now carries it in compiled code, and the place is taken with
  `VARIABLE-LOCATION`. MIT's: System 100 on microcode 323 and System 1003
  fail the same way under muir-sim's cadr; the CADR's line has it too.
  `tools/system-check` gains `interpreted-function-under-self`, 9 cases:
  without the change 3 pass at revisions 14 and 15 on micro and 3 at
  revision 15 on rtl; with it 9 at each; with the first site's `LOCALLY`
  put back, its evalhook case fails (the hook saw `APPLY-LAMBDA`'s own form
  and the evaluation stopped at ".SLOTS.BOUND.INSTANCE. is unbound"), and
  with the second's, six cases fail at "%PUSH is undefined".
- **`LOCALLY` compiles** (`sys/sys/qcp1.lisp:2459-2465`,
  `sys/sys/qcluke.lisp:573-576`, `sys/sys/qcfile.lisp:528-533`, `:627-633`).
  The compiler had no `LOCALLY` of its own: in a function's body it compiled
  one as a `%FEXPR-CALL` of the interpreter's `LOCALLY` (`sys/sys/eval.lisp`)
  with the body quoted, so the body ran interpreted, without the function's
  lexical variables. `(defun f (x) (locally (declare (special y)) (list x)))`
  compiled stopped at "X is referenced as a free variable but not declared
  special", and the compile warned that X was bound but never used. The
  compiler's code walker took `LOCALLY` as a call with its arguments quoted
  too, so a closure whose body held one did not close over the variables
  used inside it; and a `LOCALLY` at the top level of a file was run at load
  as a random form, so its `DEFUN`s stayed interpreted. `LOCALLY` now
  compiles as a `LET` with no variables, which holds its declarations; the
  code walker walks its body as `PROGN`'s; and `COMPILE-DRIVER` takes a
  top-level `LOCALLY`'s forms as top-level forms with its declarations in
  effect. The last two are MIT's, from the patch file of System 99.21
  (`patch/system-99-21.lisp` of System 100, not kept in this tree), whose
  changes to these files System 100's sources never took. That patch's
  `DEFCOMPILER-SYNONYM` of `LOCALLY` to `PROGN` is replaced by the P1
  handler, which also holds under `DONT-OPTIMIZE`, where the synonym's
  rewrite is not made; its `SETF` and `LOCF` of `LOCALLY` are not taken.
  MIT's: System 100 on microcode 323 and System 1003 fail the same way; the
  CADR's line has it too. No other system source compiles a
  `LOCALLY`: APPLY-LAMBDA's two were taken out with the change above, and
  `sys/sys2/meth.lisp:118` and `:124` make interpreted methods.
  `tools/system-check` gains `compiled-locally`, 17 cases: without the
  change 6 pass at revisions 14 and 15 on micro and 6 at revision 15 on
  rtl; with it 17 at each; without the P1 handler 7 pass, without the code
  walker's property the closure's case fails, and without `COMPILE-DRIVER`'s
  clause the top-level `DEFUN` is not compiled. The system compiled
  natively with the compiler before and after the change
  (`tools/cross-build/cases/native-compile.cases`, revision 15 micro) gives
  218 QFASLs equal by `tools/cross-check/same40.py` but for the three
  compiler files' own.
- **The TELNET server closes when its client sends EOF**
  (`sys/network/chaos/chsaux.lisp:1268-1270`, ECHOING-STREAM's `:TYI`, and
  `:1290-1310`, TELNET-SERVER-EOF). `:TYI` reads NIL at end of file, and
  ECHOING-STREAM compared it with `#o37`: at a client's EOF alone (a TCP
  half-close through the gateway) the listener stopped at "The first
  argument to >, NIL, was of the wrong type", the debugger, reading the same
  stream, erred again one level deeper about every 0.27 s, and after about
  590 errors the band ran out of regions ("Address space low!") and halted
  in HALT-CONS, on System 2002 as on the CADR's 1002. After EOF then CLS,
  what the gateway sends when its TCP client closes, the server process
  ended without a close of its own and its connection was left in
  CLS-RECEIVED-STATE or LOS-RECEIVED-STATE. Now the server closes the stream
  normally, which on Chaos forces out what is buffered, sends EOF, waits until
  everything is acknowledged and then sends CLS, so the value of a form
  still running arrives first; then its process ends, as it does on a
  network error. The change is in the server's body, which uses only the
  stream and the process, so it moves with the body when the server is
  served over TCP. `tools/system-check` gains `telnet-eof`, a client on the
  band itself over Chaos to its own address: without the change 10 of its
  30 cases fail, with it all pass; with the EOF test inverted the check's own
  session closes at once, with the normal close left out (an abort, CLS
  alone) 4 cases fail, and without the end of the process 7 fail. ECHOING-STREAM's
  `:TYI` is unchanged since System 1000.
- **The numeric comparisons check every argument's type**
  (`sys/sys/qfctns.lisp:1514-1572`, GREATERP, LESSP, `=`, `<=` and `>=`;
  `sys/sys/qcopt.lisp:204-222`, ARITHEXP, and `:383-478`, the optimizers of
  `=`, `>`, `<`, `<=` and `>=`). The four ordering functions walked their
  arguments with NIL as the mark of no previous argument, so a first
  argument of NIL was never compared: `(< nil 60)` returned T, interpreted,
  through FUNCALL and APPLY, and `(< nil 1 2)` what the rest gave. Now they
  compare adjacent arguments from the first. One argument was checked by
  neither the functions nor the compiler: `(< nil)` and `(= nil)` returned
  T, and the compiler made `(< x)`, `(> x)`, `(<= x)` and `(>= x)`
  `(progn x 't)`, `(= x)` `'t` without evaluating x, and `(max x)` and
  `(min x)` x, so a compiled `(max nil)` was NIL. Now GREATERP, LESSP, `<=`
  and `>=` check a single argument with `CHECK-TYPE` as a non-complex number
  and `=` as a number, as MAX and MIN do; the optimizers give `'t` (MAX and
  MIN the constant) only when the one argument is a number constant of
  that type, and otherwise leave the form a call of the function. With no
  argument the comparisons still give T. A compiled call of two arguments is one
  instruction, which checks both types, and was not affected. MIT's: the
  text is System 100's, and System 100 and the CADR's 1002 and 1003 give the
  same results to the interpreted forms. `tools/system-check`
  gains `number-compare-type`, 61 cases: without the change 39 fail, with
  it all pass; with only LESSP changed 23 fail, without the change to `<=`
  and `>=` 10, with `<`'s optimizer unchanged 3, with ARITHEXP unchanged 2,
  and without the functions' check of one argument 18.
- **ODDP and EVENP are functions** (`sys/sys2/numer.lisp:393-408`). They
  are misc instructions declared as no Lisp functions
  (`sys/cold/defmic.lisp:98-99`), so the cold load gave them no function
  cell and nothing defined one: `(fboundp 'oddp)` was NIL, and every
  interpreted call, FUNCALL, APPLY and `#'oddp` signalled "The function ODDP
  is undefined." on every band; compiled calls, the misc instruction itself,
  worked. So `tools/system-check`'s `float-round-trip`, `format-float-digits`
  and `format-float-fixed` erred when run without `--compile`. Now
  `numer.lisp` defines both, MIT's definitions from its patches (System
  98.44, 99.10), never put in its sources: compiled, each body is the misc
  instruction (`MOVE D-PDL ARG|0`, `(MISC) ODDP D-RETURN`), not a call of
  itself. MIT's patch first removed a `COMPILER:P1` property of each; in this
  tree that handler is commented out (`sys/sys/qcp1.lisp:2808-2812`) and the
  band holds no `P1` and no optimizer for either, so no `REMPROP` is needed.
  MIT's documentation string for ODDP, which `DOCUMENTATION` gives over the
  DEFUN's, read "T is NUMBER is odd." and now reads "T if NUMBER is odd."
  (`sys/cold/docmic.lisp:311-315`). `tools/system-check` gains
  `oddp-evenp`, 26 cases, run without `--compile`: without the change 2 pass
  (the controls), with it all pass, with the ODDP definition alone the 12
  EVENP cases fail, and without the change to `docmic.lisp` ODDP's
  documentation case fails; with the change the three float checks pass
  without `--compile`. The CADR's line has the same bug.
- **The microcode takes revision 16's Ethernet device: its interrupt as a
  stray, and a wait for it to be quiet at reset** (QUUX's Ethernet
  contract, sections 2.6, 2.7 and 10; step E3). One microcode runs on
  revisions 15 and 16: revision 16 is revision 15 with the Ethernet device at
  register-page words 240-257, its interrupt word 100 `<8>` and feature word
  15 `<2>`, and boots revision 15's `.mcr` and PROM.
  - **The interrupt** (`INTR-ETHERNET-DEVICE`,
    `sys/ucadr/uc-interrupt.lisp:100`, `:443-469`). Word 100 `<8>` is up
    while word 240's `<8>`, the interrupt enable, is on and an Ethernet frame
    waits. The handler writes 240 back with `<8>` clear and `<0>`, the
    enable, as it was, so that the device runs on, the frame stays for the
    driver and the level goes down, and dismisses the interrupt. Before,
    `INTR` dismissed it untouched, and the level, never cleared, interrupted
    again at once for as long as the frame waited: on muir-sim's revision 16,
    micro, `INTR` was entered more than 524,288 times in 64 M microcycles,
    the listener still answering between them, against fewer than 2,048 with
    the write. With the write alone the bit was a stray while the driver
    polled; since M-ack's idle bound failed with the clock's break every tick
    (12-13% on micro at 19 ns), the contract's fallback is built: the handler
    also asks for a sequence break, as MIT's microcode can for a received
    Chaos packet (`:chaos`; the band enables only `:clock`,
    `sys/sys2/proces.lisp:1028`), and the network process sets `<8>` before
    each wait (the Lisp side, below). `%SEQUENCE-BREAK-SOURCE-ENABLE` does
    not gate this request, so `SB-ON` does not govern it: the network's
    arming of 240 `<8>` before each wait is its gate, and a band that never
    arms it never gets the break.
  - **The deferred sequence break is the machine's, not the stack group's**
    (`SGENT`, `sys/ucadr/uc-stack-groups.lisp:314-335`; section 2.6). A
    break that comes while scheduling is inhibited is deferred in
    `M-DEFERRED-SEQUENCE-BREAK-FLAG`, a bit of `M-FLAGS`, which `SGLV` saves
    with the stack group it leaves; `SGENT` restored the bit from the group
    it entered. The scheduler's whole pass is inside a `WITHOUT-INTERRUPTS`,
    so a break that came during it, the `<8>` of a frame that arrived after
    the network process's predicate was read, was dropped when the scheduler
    resumed a process, and the frame waited for the clock's next break: up to
    a second with the collector off (M-ack on micro at 48 ns, GC off: max
    1035.5 ms, p99 659.6, over its bounds; at 19 ns, GC on, max 105.4, p99
    39.8), and the scheduler's own saved bit stayed 1 for good once a break
    had been deferred in it. MIT's code, harmless with the clock's break
    alone. `SGENT` now carries the bit of the group it leaves into the group
    it enters, where `SB-REINSTATE` asks for the break again when
    scheduling is allowed there, and drops the entered group's saved copy.
    A break that lands inside a `WITHOUT-INTERRUPTS` is deferred again, as
    before; one carried into a coroutine that swaps its bindings is taken
    there, where MIT kept it for the caller's section's end. M-ack with it,
    max and p99 in ms (bounds 200 and 40): micro at 19 ns 29.1 / 10.1 GC on
    and 11.4 / 9.1 GC off, at 22.5 ns 33.6 / 10.3 and 12.3 / 9.9, at 48 ns
    45.3 / 13.6 and 14.7 / 11.3; rtl at 19 ns 9.9 / 3.1 and 3.9 / 3.1; idle,
    the loop 0.009% slower at 48 ns GC off, and on rtl -1.11% and 0.005%.
    The cost is one pass for each break carried into a group that may be
    scheduled: 0-1 a second under M-ack and T2's 1 MiB echoes, none idle,
    the longest pass 9.7 ms at 63.5 ns against the fastest clock's 16.7 ms
    (scratch counters); and each frame now wakes the network process at
    once rather than in a batch at the clock's next break: M-refill on micro
    at 19 ns, 100 frames a second, the workload 5.93 s against 4.32 s with
    MIT's `SGENT` (2.89 s with no frames).
    The profile's record of `SGENT1`'s jump on the swapped state moves with
    the jump, five words on, from `+25` to `+32` (octal;
    `sys/ucadr/ucadr-profile.text:1761`): at `+25` it fell on a word of
    another class, so the profile pass's report covered 72,821,976 of the
    profile's 72,822,600 jump executions and `tools/assembler-check` `rev15`
    failed. The record says 0, so the pass sets no hint there either way and
    `ucadr.mcr` is the same.
    The CADR's line has the same code, but its only break is the clock's.
    With the interrupt's break and this, the microcode's `ucadr.mcr` for
    revisions 15 and 16 is
    `9a922c9c6476a1ce3e379a7230a22d62f28b6eb263b0ee4749291b2ab7d99717`, with
    `.tbl` `71b0bffbfb531751723e90d793acb50632dca7bac5eb1dccec337c706c58be0b`,
    `.locs` `4a60063c839da57ae32cf373e5ec4a60d2f9488d1419c0ec0ffff4dc162eb8b8`
    and `.sym` `ee7424f68551af799709921d7488db72f7d5d104c4ac2dc1b8b7eaf6c63f6a85`
    (it was `dc031be9...` with the interrupt's break alone and `45ff6277...`
    with the stray); the boot PROM is unchanged.
  - **The quiet wait** (`RESET-MACHINE-ETHERNET-QUIET`,
    `ETHERNET-DEVICE-NOT-QUIET`, `sys/ucadr/uc-cold-disk.lisp:102-123`,
    `:608-614`). After reset devices and the file device's wait, the reset
    waits for the Ethernet device to be quiet (word 241 `<1>`), 2 seconds as
    the file device's, then halts at `ETHERNET-DEVICE-NOT-QUIET`: on a board
    a received frame's write that the reset overtook may still be in flight
    until the device's program drops its claim. The wait is gated on feature
    word 15 `<2>`, because on revision 15 word 241 is reserved and reads 0:
    an ungated wait halts every boot there. The register names are
    `sys/ucadr/uc-cadr.lisp:181-189`.
  - **The checks.** `tools/microcode-check`'s new `ethernet-stray`
    (`cases-16/`, run only when named on revision 16, with the new
    `ethernet-peer` behind the device; its README): 11 cases pass on micro
    and rtl; on microcode 2002 before the change 5 of them fail on both, and
    with a stray planted that writes 240 with 0 6 fail on micro. On micro a
    scratch count of the handler's address found it run three times, once each time
    `<8>` went up with a frame waiting. The wait, measured by booting on
    micro with a scratch plant in muir-sim that holds 241 `<1>` low: on
    revision 16 the boot stops at `ETHERNET-DEVICE-NOT-QUIET`, which
    microcode 2002 before the change boots past; without the plant the wait
    reads 241 once a reset and the boot goes on. On revision 15 the wait is
    never entered, and a copy with the gate removed halts at
    `ETHERNET-DEVICE-NOT-QUIET` there. System 2002's band on the new
    microcode passes `tools/microcode-check`'s 22 case files on revisions 15
    and 16, on micro and rtl, 622 cases, as the microcode before did on
    revision 15 in the soak of System 2002; `tools/assembler-check` passes
    all 30 checks, its revision-15 counts unchanged (359 hints, 140 predicted targets, every execution of
    the profile covered). `tools/microcode-check`'s new `sg-deferred-entry` (6 cases) enters a
    stack group in each of `D-SG-ENTER`'s resume states with a deferred break
    carried and scheduling allowed: the group breaks before its first form
    and returns its own value; MIT's `SGENT` fails the 4 entries. On the
    microcode with the deferred break the machine's, micro, revision 15
    passes the 23 case files, 628 cases, and revision 16 those and
    `ethernet-stray`, 639. `tools/system-check`'s new `sb-deferral` (below,
    the Lisp side's checks) times the pass after a break deferred in the
    scheduler's own.
  Microcode 2002's files changed again, 19 instructions more: at revision 14
  `ucadr.mcr`
  `068511118b1794abcea9b80f605a00500ecf07e0e9cb7eb479c2be5367b33b49`, at
  revision 15 `ucadr.mcr`
  `45ff6277b552970569f40aa7fa074eb9720787167e69970f643b7927d70f5767` with
  `.tbl` `0c57992d7f27cbc1d41e9ad537e691fdc67199509122ee18d3805c2ffa6f7240`,
  `.locs` `798fadee546184ec9e747987144c6fc9dde8c9af5aab5bece518550662ad3d67`
  and `.sym` `c37c7621bdcbcffccc2c62cdc4cb36eed2ac06d46059286235abb345dc20d9fa`,
  revision 14's `.sym` the same (before, at revision 15 `ucadr.mcr`
  `7dc213f7e82d5761c0a0a40ea03a0dee7cad9be10e2c7ec2fe37c5eab1c3e73e`);
  `promh.mcr` is unchanged,
  `3d93319a8e851f5f14a2fcd66cd1ed21abb33049c355edf8cc893c791fb4b124`.

- **The microcode drops Chaos and takes the network's interrupt as a stray**
  (QUUX's Ethernet contract, section 8, step R3; contract Q13's register page,
  word 100). `UC-CHAOS`, the chaosnet's interrupt handler, leaves the
  assembly (`sys/ucadr/ucode.lisp`), and with it `CHAOS-INTR-QUUX`, the
  60-cycle clock's retry of an aborted transmit and the PDP-11 path's poll of
  the CSR (`sys/ucadr/uc-interrupt.lisp`), and the misc instruction
  `%CHAOS-WAKEUP`, whose 560 is free (`sys/cold/defmic.lisp`). Word 100
  `<6>`, the Chaosnet interface's request, goes to a stray,
  `INTR-NETWORK-STRAY` (`sys/ucadr/uc-interrupt.lisp:460`), since the
  microcode still runs on revision 15, and on 16 until the interface goes
  (step R4): it writes the CSR, word 140, 0, which turns both interrupt
  enables off and drops the level, and dismisses the interrupt. The A memory
  variables of the chaosnet stay in place, unused, so no later location
  moves. `tools/assembler-check/run` and `tools/cross-build/run` drop
  `UC-CHAOS` from their file lists. The profile's 57 records of `uc-chaos`'s
  words and its `INTR-TICK+3`, the clock's test of an aborted transmit, are
  commented out of `sys/ucadr/ucadr-profile.text`: left in, 45,392 of its
  executions fell on keys no longer found, and `INTR-TICK+3` on 60CYC-0's
  word; without them the profile pass covers all of its 72,777,045, and
  sets 348 hints, not 359 (`PROFILE_REPORT_15`, `PROFILE_15`,
  `tools/assembler-check/run`). The profile was not measured again on the
  changed microcode: its other records are as measured, and a fresh
  measurement belongs to the later work on performance.
- **The file device's pathname host is FILES** (`sys/io/file/hostfs.lisp:168-173`,
  `site/sys.translations:33`, `site/site.lisp:32`, `site/lmlocs.lisp:17-27`).
  With QUUX's network on Ethernet, "host" means a host of the network, as the
  machine's own host name does; the folders the file device serves, and every
  machine's associated machine, are now `FILES` (`FILES: /home/lispm/`,
  `(login "LISPM" "FILES" t)`, the herald's "with associated machine FILES").
  Systems 2000 and 2001 call it `HOST`. The computer QUUX runs on is still its
  host, and MIT's network sense of the word stays. A band reads the
  translations of its own tree: a band that names the host HOST, served this
  tree, keeps `SYS:` on HOST, and one that names it FILES, served an older
  tree, keeps FILES. A leftover `HOST:` in a FILES band parses silently as a
  relative directory on FILES, and every open of it then fails with
  "Directory not found". The comments that mean the pathname host, the case
  files and the documents follow; `HOSTFS`, `FILE-DEVICE-HOST` and the case
  `host-create-directory` keep their names, which mean the host computer's
  folders and MIT's pathname host. The cross build's log directory, which named
  HOST, now defaults to the user's home directory at `CROSS-BEGIN`
  (`sys/cold/cross.lisp:54-59`, `:705-709`), so the file names no pathname
  host. The route's builder is the renamed builder, System 2002's hand-over
  with the rename loaded and saved (`docs/building.md`, "The renamed
  builder"), since a QFASL's source id and a cold load's truenames record the
  compiling band's name for the host.
- **A key typed early in the boot no longer halts the machine**
  (`PROM`, location 6, `sys/ucadr/uc-cadr.lisp:237-264`). Location 6 chooses
  between a cold boot and a warm boot by the keyboard: MIT's test read one
  key word and took any word but the cold boot word, Rubout's, for a warm
  boot. On QUUX the keyboard is a FIFO (contract Q3), which keeps every word
  typed since the band last read it, so a key typed while the PROM ran, as a
  client typing at the glass TTY's connect does, was taken for a warm boot
  after power-on, with no band in memory: BEG0000's read of virtual 4031
  faulted, and ILLOP halted the machine with 32063 in the lights. On
  revision 16, micro, typing at the connect halted 10 boots in 10. Now
  location 6 reads the FIFO to its last word, the boot word being the last
  one the keyboard sends (it holds the key-ups back after it; `ukbd.lisp`'s
  `check-boot`), and warm-boots only when that word is the warm boot word:
  bits 13-6 360, as the I/O board decodes the boot word, with boot code 62,
  Return's (`ukbd.lisp`: "5-0 46 (octal) if cold, 62 (octal) if warm"), as
  MIT's comment above the test says. Any other word, the cold boot word
  among them, and no word give a cold boot. A warm boot asked for with no
  band in memory still halts at ILLOP, as MIT's does. Keys typed before
  location 6 are read and dropped. `tools/microcode-check`'s new `boot-keys`
  (its README) types the keys while the machine is held at muir's prompt,
  then boots it: on revision 16, micro, MIT's test fails 3 of its 6 cases (a
  key and Control-Meta-Rubout after power-on halt at 32063, and
  Control-Meta-Rubout on the running band, the key-downs ahead of the boot
  word, warm-boots), and the new one passes all 6, on micro and on rtl;
  without the draining, the first word alone, the two Return cases
  cold-boot, and without the boot code's test the two Rubout cases
  warm-boot. Typing at the glass TTY's connect, 10 boots on micro: 10 halts
  before, none after. `tools/assembler-check`'s `write-i-mem` and
  `write-i-mem-slot` named the refused word by its address, I-MEM 56, which
  the six words move to 64; they now name it by its label and offset,
  `XWIPM-I-14+1`, as the map-after-start plants do
  (`tools/assembler-check/run:115-120`, `:696-699`). On revision 16, micro,
  System 2002's band on the new microcode passes `tools/microcode-check`'s
  suite (684 cases; `network-stray` skipped there),
  `tools/assembler-check`'s 30 checks (247 cases) and `tools/system-check`'s
  `warm-boot`. The CADR's line has the same test, where its one register
  keeps the last word. Microcode 2002's files changed again, 6 instructions
  more at location 6, which move the words after them by 6, and from
  `QMLP`, which `sys/ucadr/uc-macrocode.lisp` puts at a multiple of 4
  (`MODULO 4`), by 8; A memory holds two more constants, 360 and 62:
  `ucadr.mcr`
  `28e08799204ca1134c9c19dcbb8ce95524e31177a304f370e6df538e227ef39a` with
  `.tbl` `8d5de5f0bbc37f062957671cadab74be00681bc88cff51ef0c46406effaec16c`,
  `.locs` `e599b17b8ef6d3c3755ad2dca6f6a27179802cb07cdc7eebcd19e41eb2064839`
  and `.sym` `ffb0214b364f6eb5c31233f23c85155bb21a752dd18a532ede2a91e85e4a7df3`
  (before, `ucadr.mcr`
  `0292aac86ba39058fa323c70de564cff03ed83d13d43061b701407a95cbae581`);
  `promh.mcr` is unchanged,
  `3d93319a8e851f5f14a2fcd66cd1ed21abb33049c355edf8cc893c791fb4b124`.

## Revision 14

QUUX's revision 14 (contract G3, revision 14, and its appendix A14) gives the
machine a 32-bit virtual address space with untranslated windows at its top,
a two-level page table that the hardware walks through a TLB, and the
microcode only for the faults the walk leaves.

### The micro-assembler

- **The micro-assembler assembles for revision 14** when
  `ua:*hardware-revision*` is 14 (the default is 13, at which every output is
  byte for byte what it was): condition 12, M <= A unsigned, with
  `jump-less-or-equal-unsigned`, `jump-greater-than-unsigned` and their call,
  return and xct-next forms (`sys/sys/cadsym.lisp`); the write-map operation
  word's names, `write-map-operation` (`VMA<33:32>`), `write-map-none`,
  `-direct-write`, `-invalidate`, `-empty`, and `write-map-entry`
  (`VMA<29:0>`); the pointer-type register's words 222 and 223,
  `pointer-type-register-0-31` and `pointer-type-register-32-63`, the bits of
  `ua:*pointer-types*` (`pointer-type-register-word`) (`sys/sys/cadsym.lisp`,
  `sys/sys/cadrlp.lisp`); all of them refused at revision 13
  (`cons-lap-symeval` and the jump word, `sys/sys/cadrlp.lisp`).
  `docs/building.md`, "Assembling the microcode", says how.
- **A revision-14 `.mcr` starts with section 6**, code 6, start 0, one word,
  the hardware revision 14 (`write-mcr-file`, `sys/sys/qwmcr.lisp`).
- **A revision-14 assembly of the microcode is refused before anything is
  written** when `A-PDL-BUFFER-VIRTUAL-ADDRESS` is not at A 430 or
  `A-PDL-BUFFER-HEAD` not at A 431 (`check-pinned-a-locations`); when a
  map-bit dispatch table tells apart a data type outside
  `ua:*pointer-types*`, A14.5's 19 types, when the register's two words are
  not that set's bits, or a map-bit dispatch reads another table
  (`check-map-bit-tables`); when a word writes the location counter through
  the right shift or by an arithmetic function other than ADD, SUB, M+1 and
  M-1 (`check-lc-writes`); or when a TLB direct write outside the PDL
  buffer's dump, its refill and their recovery is followed, on any path
  before its invalidation, by a second memory start, a MAP(MD) read, a
  dispatch, a call other than to a halt, a return or another write-map
  (`check-fiddle-windows`, revision 14's fiddle rule) (`sys/sys/cadrlp.lisp`).
- **`tools/assembler-check`** checks all of this with planted microcode (its
  README): `rev13`, `rev14`, `tree`, `bits`, `pinned`, `map-table`,
  `map-set`, `map-constant`, `lc-shift`, `lc-mm` and `fiddle`. Its `rev13`
  and `rev14` checks assemble as version 2001, since they compare the
  outputs with release 2001's `sys/ubin/`. Their `--ucadr-ref` names a
  directory laid out as the tree, and the release's `sys/cold/qcom.lisp`
  and `sys/cold/defmic.lisp` replace the tree's with its `sys/ucadr/`
  (`REF_FILES`, `tools/assembler-check/run`): the micro-assembler reads them
  for the microcode's constants, and release 2001's microcode read with
  revision 14's `qcom.lisp` stopped at an unbound
  `%PHT-MAP-STATUS-META-BITS-ONLY`.

### The microcode and the boot PROM

Labels are cited rather than lines, since these files are still changing.

- **The microcode pages through the two-level page table.** The page hash
  table, its search, the level-1 and level-2 map reloads and the old ager are
  gone, commented out in place (`sys/ucadr/uc-page-fault.lisp`). A TLB miss
  is the hardware's walk; the microcode sees only the faults it leaves: D-PGF
  status 0 (no entry: PGF-NO-ENTRY; an address in no region is the error
  ADDRESS-IN-NO-REGION, one in a region is ILLOP), 1 (not in core:
  PGF-NOT-IN-CORE, SWAPIN), 2 (read only), 3-5 (ILLOP), 6 (MAR), 7 (the
  A-memory window, PGF-A-MEMORY). New routines: FIND-PAGE-ENTRY and
  FIND-PAGE-ENTRY-OR-MAKE (the walk in microcode, taking a page-table frame
  with TAKE-TABLE-FRAME), the slot bitmap (ALLOCATE-SLOT, FREE-SLOT,
  SLOT-SET, SLOT-CLEAR), SWAPIN (a run of pages in consecutive slots of one
  region in one transfer), FINDCORE (a clock over the physical page data: a
  free frame is taken, a page whose accessed bit is 0 evicted, the ager's lap
  clearing accessed bits), and EVICT-PAGE (written to its slot only if
  modified; a fresh page never written leaves with no slot and comes back as
  CZRR fills it).
- **Misc ops on the new tables:** %CHANGE-PAGE-STATUS, %CREATE-PHYSICAL-PAGE,
  %DELETE-PHYSICAL-PAGE, %PAGE-IN, %PAGE-STATUS and %PHYSICAL-ADDRESS read
  and write page-table entries and the physical page data
  (`uc-page-fault.lisp`, XCPGS to XPHYADR); freeing a region's pages frees
  their frames and slots (FREE-PAGE-RESOURCES).
- **`%FINDCORE` returns the frame as a fixnum** (`uc-page-fault.lisp`,
  XFINDCORE). It returned FINDCORE's bare `M-B`, data type 0, and
  PAGE-IN-WORDS's `(* (%findcore) page-size)` halted in ILLOP through
  QIMUL's D-NUMARG1, so a saved band halted as it booted.
- **MAKE-REGION** (`uc-storage-allocation.lisp`) refuses a region past the
  commit limit (VIRTUAL-MEMORY-OVERFLOW), places an ephemeral region in
  [32000000000, 34000000000) and any other in [the region floor,
  32000000000), and writes its pages' entries; the region floor is
  A-REGION-FLOOR (A 142), read from the system communication area at boot.
  UPDATE-REGION-PHT updates the entries for a flip and keeps the ephemeral
  reference bit <19>.
- **The PDL buffer's dump and refill** write the TLB directly and invalidate
  after (the "fiddle"); the dump sets A 430/431 to their post-dump values
  before its first write, and a status-6 fault inside the fiddle is
  recovered (P-B-FIDDLE-AGAIN, P-R-FIDDLE-AGAIN). FORCE-WR-RDONLY is a
  direct write, the store, and an invalidation.
- **Address compares are unsigned** where an address may be at or above 2^31
  (contract G3 revision 14, 10.1): every compare the census of the
  microcode's address compares marked to change, each with the old line
  commented out beside it.
- **Devices:** %XBUS-READ/-WRITE through 35760000000 with a bound check
  (ARGTYP XBUS-OFFSET); %UNIBUS-READ/-WRITE are errors (ARGTYP
  UNIBUS-ADDRESS); the register page at 35777777400; disk command lists and
  error logging through the physical memory window (`uc-disk.lisp`).
- **Cold boot and bands** (`uc-cold-disk.lisp`): DISK-RESTORE sizes memory
  through the physical memory window, builds the tables (directory in the
  last four frames, word 220; the physical page data; the slot bitmap; words
  222/223, the pointer-type register, before Lisp runs), copies the band into
  the paging partition's slots page k to slot k, and makes the regions'
  entries (BUILD-REGION-ENTRIES). Band formats 2010 (saved), 2011
  (incremental) and 2012 (cold load); 2000-2002 halt at BAND-NOT-REVISION-14,
  and a machine not at revision 14 halts at MACHINE-NOT-QUUX-14. DISK-SAVE
  evicts every page first (SWAP-OUT-ALL-PAGES) and copies each region's pages
  from their slots (DISK-SAVE-REGIONWISE-SUBR), runs of consecutive slots in
  one transfer. The incremental restore (DISK-RESTORE-INCREMENTAL) copies
  the base band into slots 0 on and the incremental pages after it.
- **The boot PROM** (`sys/ucadr/promh.text`): its first act checks the
  revision (halt ERROR-NOT-REVISION-14); it writes no map, reaches the
  registers at 35777777400 and its buffer at 36000006000, and refuses a
  microcode whose section 6 is not revision 14 (halt
  ERROR-MICROCODE-NOT-REVISION-14).
- **The sources' microcode assembles only at revision 14**: its paging is
  revision 14's page table, and the PROM, also assembled at 14, refuses a
  machine and a microcode of another revision (`docs/building.md`,
  "Assembling the microcode"). `tools/assembler-check`'s `tree` assembles
  it, and `fiddle` plants a dispatch in FORCE-WR-RDONLY's window, which is
  refused.

- **Microcode 2002 halts at MACHINE-NOT-QUUX-14 below revision 14 when it is
  loaded another way** (appendix A14.13): the PROM entry's first read, the
  keyboard's status through the device window, which revision 13 does not
  have, faulted and halted at PHYS-MEM-READ-2's ILLOP before RESET-DEVICES'
  check could name the halt. It now calls PROM-ENTRY-READ
  (`sys/ucadr/uc-cadr.lisp`, `sys/ucadr/uc-cold-disk.lisp`), which checks
  MACHINE-ID first, as RESET-DEVICES does; one word as before, so nothing
  after it in the entry moves. `tools/cross-build`'s guards show the halt,
  and the old one with the microcode before the change.
- **An incremental band restores** (`sys/ucadr/uc-cold-disk.lisp:992`):
  DSR-MASK-BIT took the bit's place in its mask word from A-WALK-INDEX,
  which is the page's index in the band while DISK-SAVE-REGIONWISE-SUBR
  saves but its region's first page's while BUILD-REGION-ENTRIES restores,
  so every page but a region's first took another page's bit and the
  restored world read pages from the wrong slots; every incremental band
  halted in its boot. It now takes it from A-MASK-K, as it takes the word.
  Found by the first incremental save and restore on revision 14
  (`tools/cross-build`'s `incremental` step); the save is unchanged.
- **UN-CONS backs up the scavenger's pointer as an offset**
  (`sys/ucadr/uc-storage-allocation.lisp:1922`): it compared the region's
  REGION-GC-POINTER, relative to the origin, with the freed block's end as
  an address, signed, so below 2^31 it never backed the pointer up, and from
  2^31 up, an ephemeral region, it always did, writing an address into
  REGION-GC-POINTER. It now compares with the free pointer it has just
  written. Found by the ephemeral run's check that every region's free and
  scavenger pointers are offsets within it (`tools/system-check`,
  `rev14-ephemeral`). The CADR's line has the same compare.

### The Lisp side

Citations are of the files as this step left them.

- **Addresses are unsigned** (contract G3 revision 14, 10.1, 10.10). An
  address is the fixnum whose 32-bit field is the address, negative as a
  number from 2^31 up:
  - `%POINTER-UNSIGNED` gives N + 2^32 for a negative field; it added
    -2^32 and made the field more negative (-1 gave -4294967297). It and
    `%MAKE-POINTER-UNSIGNED` move from `sys/sys/qmisc.lisp` to the cold load,
    `sys/sys/qrand.lisp:21`, `:29`.
  - `%POINTER-LESSP` compares the two fields unsigned, each with bit 31
    flipped, not by the sign of their modular difference
    (`sys/sys2/lmmac.lisp:379`).
  - The printer prints an address unsigned (`SI:PRINT-POINTER-FIELD`,
    `sys/io/print.lisp:574`; `PRINTING-RANDOM-OBJECT`, `sys/io/rddefs.lisp:221`;
    and the 22 other places that printed `%POINTER` with `~O`, in
    `sys/eh/ehc.lisp`, `sys/eh/ehf.lisp`, `sys/io/rddefs.lisp`,
    `sys/io/rtc.lisp`, `sys/network/chaos/chsncp.lisp`, `sys/sys/clpack.lisp`,
    `sys/sys/qrand.lisp`, `sys/sys2/class.lisp`, `sys/sys2/describe.lisp`,
    `sys/window/basstr.lisp`, `sys/window/cold.lisp`, `sys/window/inspct.lisp`,
    `sys/window/sheet.lisp`, `sys/window/tscrol.lisp`).
  - Generic `+`, `-` and `1+` on an address gave a bignum at or across 2^31,
    whose own storage a subprimitive then used: the address is made by
    `%POINTER-PLUS`, an offset by `%POINTER-DIFFERENCE`, a place in an object
    by its offset compared with 0 and the size, a loop over pages by a count
    of pages. In `WIRE-DISK-RQB` (`sys/io/disk.lisp:344`), `WIRE-WORDS`
    (`:1677`), `PAGE-ARRAY-CALCULATE-BOUNDS` (`:2138`), `BUFFER-RESET`
    (`sys/io1/meter.lisp:28`), `DESCRIBE-LOCATIVE`
    (`sys/sys2/describe.lisp:371`), `ARRAY-INITIALIZE` and
    `ADJUST-ARRAY-SIZE` (`sys/sys/qrand.lisp:826`, `:1447`),
    `UNSTACKIFY-ENVIRONMENT` (`sys/sys/eval.lisp:2173`),
    `FLAG-ALREADY-OPTIMIZED` and `ALREADY-OPTIMIZED-P`
    (`sys/sys/qcp1.lisp:979`, `:993`), the micro-compiler's exit vector
    (`MA-RESET-MICRO-CODE-ENTRY-ARRAYS`, `MA-REBOOT`,
    `MA-INITIALIZE-EXIT-VECTOR`, `MA-LOAD-EXIT-VECTOR-Q`,
    `sys/sys/mlap.lisp:475`, `:500`, `:526`, `:545`), `FILE-DEVICE-STATE`
    (`sys/io/fdev.lisp:501`), `RQB-DATA-POINTER` (`sys/io1/inc.lisp:44`),
    `VMEM-RQB-DATA` (`sys/cold/coldut.lisp:116`),
    `VIRTUAL-ADDRESS-TO-PDL-INDEX` and `SYMBOL-FROM-VALUE-CELL-LOCATION`
    (`sys/eh/eh.lisp:1191`, `:2118`), and the Unibus channel functions
    (`sys/io/unibus.lisp:169` on; dead on QUUX).
  - `SET-MAR` and `CLEAR-MAR` (`sys/sys/qmisc.lisp:859`, `:846`) visit each
    page of the range once, the addresses ordered unsigned
    (`SI::MAP-MAR-PAGES`, `:825`). The old loops stepped `#o200` words and
    compared signed: past 2^31 they ended at once, and on any machine they
    could miss the page holding the range's last word when it lay in that
    page's first 127 words.
- **The windows' addresses** (appendix A14.1, contract 10.8), each built by
  `SI:%MAKE-POINTER-UNSIGNED` (`sys/cold/qcom.lisp:484` on): A memory's window
  35700000000, the `%XBUS` base 35760000000, the Unibus's 34400000000 (no
  Unibus; nothing answers there), and two new constants,
  `PHYSICAL-MEMORY-VIRTUAL-ADDRESS` 36000000000 and
  `EPHEMERAL-SPACE-VIRTUAL-ADDRESS` 32000000000 (`sys/cold/qcom.lisp:496`,
  `:499`; `sys/cold/qdefs.lisp:181`, `sys/sys/ltop.lisp:66`,
  `sys/cold/system.lisp:129`). Sums with them are made by `%POINTER-PLUS`
  (`FEATURE-PAGE-FIELD`, `sys/sys/ltop.lisp:138`; the mouse,
  `sys/window/mouse.lisp:148`, `:465`; `FIXNUM-READ-METER-FOR-SCHEDULER`,
  `sys/sys2/prodef.lisp:175`; the A-memory forwarding addresses,
  `sys/cold/qcom.lisp:1410`). `VIDEO-BUFFER-ADDRESS` returns feature word 13
  as it is, the buffer's virtual address (`sys/sys/ltop.lisp:181`). The
  feature page prints its address unsigned, and word 2 as the TLB's entries
  (`PRINT-FEATURE-PAGE`, `sys/sys/genric.lisp:1837`, `:1892`).
- **The process run light is an address in the frame buffer**, two words after
  the disk run light, read and written whole (`TV:WHO-LINE-RUN-LIGHT-LOC`,
  `sys/window/cold.lisp:34`; `RUN-LIGHT-FOR-CADR` and a new setter,
  `SET-RUN-LIGHT-FOR-CADR`, `sys/sys2/prodef.lisp:204`, `:207`, in place of
  its `SETF` method, which the cross build cannot give the target changed,
  called by the scheduler, `sys/sys2/proces.lisp:789`, `:800`;
  `WHO-LINE-UPDATE`, `sys/window/wholin.lisp:109`). It was an `%XBUS`
  offset, which reached the buffer only while the buffer sat at the i/o
  region's base; the buffer is now below the `%XBUS` base.
- **No page hash table** (contract 3.2, 9.1, 10.5): PAGE-TABLE-AREA and
  PHYSICAL-PAGE-DATA leave the area list, so every later area's number is two
  lower (`sys/cold/qcom.lisp`, `sys/cold/qdefs.lisp`); the page entry's, the
  directory's and physical-page-data's fields replace the page hash table's
  (`PAGE-ENTRY-VALUES`, `sys/cold/qcom.lisp:1053`); the system communication
  area's page-table words become `%SYS-COM-PHYSICAL-PAGE-DATA` and `-SIZE`,
  with `%SYS-COM-SLOT-BITMAP` and `%SYS-COM-COMMIT-LIMIT` new (`:194` on);
  `%COMPUTE-PAGE-HASH` goes (`sys/cold/defmic.lisp:246`). Lisp reads the
  tables through the physical memory window (`SI:PHYSICAL-MEMORY-WORD`,
  `SI:PAGE-ENTRY`, `SI:PAGE-ENTRY-SLOT`, `SI:FRAME-WIRED-P`,
  `sys/io/disk.lisp:1594`, `:1598`, `:1612`, `:1619`), and their users are
  rewritten over them: `WIRE-PAGE`, `UNWIRE-PAGE` (`sys/io/disk.lisp:1627`,
  `:1658`), `PAGE-OUT-WORDS` (`:2217`), `PAGE-IN-WORDS` (by runs of slots,
  `:2356`), `SET-MEMORY-SIZE` and `SET-MAR` (`sys/sys/qmisc.lisp:24`, `:859`),
  `DEALLOCATE-PAGES` and `SET-SCAVENGER-WS` (`sys/sys2/gc.lisp:913`, `:985`),
  `COUNT-WIRED-PAGES` and `PRINT-AREAS-OF-WIRED-PAGES`
  (`sys/sys2/describe.lisp:647`, `:664`), `MAKE-AREA`
  (`sys/sys/qfctns.lisp:2862`, a writable area's pages status 4,
  read/write-first being retired).
- **The address space map** is 64 pages, a byte for each of the 32-bit space's
  262,144 quanta, as long as the array the cold load makes, on a 64-page
  boundary, at 200000 (`sys/cold/qcom.lisp:404`; `CREATE-AREAS`,
  `sys/cold/coldut.lisp:616`); the cold load writes all of it
  (`INIT-ADDRESS-SPACE-MAP`, `:1483`), and stops if the array does not fill
  the area (`:1118`). EXTRA-PDL-AREA is 55 pages, ending on a quantum
  boundary at 600000.
- **Band formats 2010 saved, 2011 incremental, 2012 cold load** (appendix
  A14.13; `sys/io/disk.lisp:1261`, `sys/cold/coldut.lisp:1393`).
- **The commit limit**: `VIRTUAL-MEMORY-SIZE` is the paging partition's slots
  plus the pageable frames, from the cold boot (`DISK-INIT`,
  `sys/io/disk.lisp:1489`); the collector's free space is it less the words
  of every region that is not free, the fixed areas' and eden's included, as
  the microcode's commit check at `MAKE-REGION` counts them, since a fixed
  area's pages own paging slots too (`GET-FREE-SPACE-SIZE-1`,
  `sys/sys2/gc.lisp:219`). `MEASURED-SIZE-OF-PARTITION`
  (`sys/io/disk.lisp:1444`) gives the band's own size as the paging partition
  it needs, and `SYS-COM-PAGE-NUMBER` (`:1294`) takes an address's page from
  its 32 bits.
- **The incremental band's mask** has a bit a page of the band, in the band's
  own order, region by region (`BAND-PAGE-INDEX`, `sys/io1/inc.lisp:57`),
  not a bit a virtual page (contract 10.7 item 2).
- **An incremental save's mask and the pages it saves come from one state
  of the regions.** The mask was computed early in DISK-SAVE, with every
  process still running, and the regions' pages were saved later, so a
  process consing between the two shifted the mask's indexes; on revision
  14 it wrote no band at all, with or without another process consing.
  DISK-SAVE-INCREMENTAL (`sys/io1/inc.lisp:106`) now runs inside
  DISK-SAVE's last WITHOUT-INTERRUPTS, where no other process runs, with
  every array, disk buffer and the base partition's address made before it
  takes a snapshot of each region's free pointer (`REGION-PAGES-SNAPSHOT`,
  `:85`), from which both the mask and the region table's marks are made.
  Just before `%DISK-SAVE`, DISK-SAVE-INCREMENTAL-VERIFY (`:96`) checks the
  regions against the snapshot; if one changed, no band is written and the
  save stops with an error naming the region, after which the machine wants
  a warm boot, as after CHECK-PARTITION-SIZE's late error
  (`sys/sys/qmisc.lisp:1926`). FIND-MAX-ADDR now runs before the snapshot
  (`:1886`): with a region at or above 2^31 it makes bignums on the extra
  PDL, which the check took for a changed region. The first check of the
  partition's size, before the partition's comment is changed, now comes
  before the compare, so it asks room for a whole band; the check after the
  compare asks only for the incremental band's. `tools/cross-build`'s
  `incremental` step saves while another process conses.
- **Errors for revision 14's microcode**: `ADDRESS-IN-NO-REGION`, a reference
  to a page with no entry (`sys/eh/ehf.lisp:2363`); the argument types
  `XBUS-OFFSET`, a fixnum from 0 to 17777777, and `UNIBUS-ADDRESS`, which
  nothing is, QUUX having no Unibus (`:1600` on). The error handler saves a
  register's pointer as a locative unless it is in no region; it saved one
  with <31:28> set as its field, untransported, which ephemeral space's are
  (`SG-SAVE-STATE`, `sys/eh/eh.lisp:242`).
- **The Chaosnet test program loads on QUUX.** `chatst.lisp` read the Chaos
  interface's number register through `%UNIBUS-READ` at load time
  (`SET-BASE-ADDRESS`), which is an error on QUUX, so the load of the system
  stopped at that file; it now runs only on a machine that is not QUUX
  (`sys/network/chaos/chatst.lisp:486`).
- **A band must fit the paging partition** too, since it is restored into its
  slots (`CHECK-PARTITION-SIZE`, `sys/sys/qmisc.lisp:1895`;
  `PAGE-PARTITION-SIZE`, `sys/io/disk.lisp:45`).
- **The region floor** (contract 10.11): `SI:REGION-FLOOR-DEFAULT`,
  `SI:REGION-FLOOR-P` and `SI:SET-REGION-FLOOR` (`sys/sys/qfctns.lisp:3012`,
  `:3019`, `:3027`), over the A-memory variable `%REGION-FLOOR`
  (`sys/cold/qcom.lisp:1332`), kept for a saved band in
  `%SYS-COM-REGION-FLOOR`, which the cold load sets to the first unfixed
  area's address; and `%%REGION-EPHEMERAL`, region bit 13, an ephemeral
  area's flag (`sys/cold/qcom.lisp:122`).
- **FEF instruction words are fixnums, tag 005** (contract G1 2.6; contract
  8.3, 10.6), fasloaded (`FASL-OP-FRAME`, `sys/sys/qfasl.lisp:954`) or
  compiled to core (`LAP-OUTPUT-WORD`, `sys/sys/qclap.lisp:388`); they were
  tagged as symbols (303 and 203). The cold load wrote them so already.
  REL's loader stores raw words and writes no tag at all.
- **Faults fixed that System 2001 has too**: `WIRE-WORDS` never wired the
  last page of its range, nor any page of a range within one page, and
  `WIRE-STRUCTURE` stopped with an argument error on every call
  (`sys/io/disk.lisp:1677`; measured on System 2001); `PAGE-OUT-WORDS`
  offered its range's first page every time (`:2217`); `SYS-COM-PAGE-NUMBER`
  made a bignum of an address from 2^31 up (`:1294`); `SET-MAR` could miss
  the page holding its range's last word (above; measured on System 2001).
  The CADR's line has the same code for the first three and `SET-MAR`.
- **The cold-load generator keys revision 14's layout on the target's
  parameters** (`TARGET-HAS-PAGE-HASH-TABLE-P`, `sys/cold/coldut.lisp:612`),
  so that revision 13's still give their cold load byte for byte; the cross
  build's builder is System 2001's band, and a file carrying the word-width
  mark is foreign only when the target's word is not the builder's
  (`CROSS-FOREIGN-FILE-P`, `sys/cold/cross.lisp:657`) (`tools/cross-check/run`,
  `crossdefs.py`, `check3.py`, `cases/native.cases`; `sys/cold/crossdefs.lisp`
  against System 2001's tree).
- **A flip no longer walks each old region's pages to remap them**
  (contract G3 revision 14, 9.4): DEALLOCATE-END-OF-REGION
  (`sys/sys2/gc.lisp:888`) called INVALIDATE-REGION-MAPPING, a
  `%CHANGE-PAGE-STATUS` of every page of the region, which rewrote each entry
  unchanged on revision 14, where the flip's UPDATE-REGION-PHT writes the
  entries; measured on micro at 32 M words, its share of a flip's pause went
  from 157-217 ms to 74-85 ms (`:910`).
- **CHANGE-REGION-TO-NEW-SPACE and INVALIDATE-REGION-MAPPING are removed**
  (`sys/sys2/gc.lisp:886`), commented out in place: nothing in `sys/` or
  `tools/`, the microcode and the cold load included, calls them once
  DEALLOCATE-END-OF-REGION's call is commented out (`:1540`).
  `tools/system-check`'s `generational-reclaim` gains a case for the pages
  a tenured flip cuts off its old regions' ends (`GENCOL-TAILS-RUN`,
  `tools/system-check/lisp/generational-collector.lisp:695`): after the
  flip each has status 0 or lies in a region made since that reused its
  quantum. No other case saw those pages: with
  `lisp/generational-collector-plant-nodealloc.lisp` (DEALLOCATE-PAGES doing
  nothing, `:1549`) every case of `generational-collector`,
  `generational-reclaim`, `generational-tuning` and
  `region-area-map-interrupt` passed (micro, revision 14), and the new case
  fails, 1,632 to 1,920 of 1,936 cut-off pages keeping an entry that no
  region reused (micro, revisions 14 and 15, 5 runs each).
- **The microcode metering ranges name microcode 2002's labels**
  (`sys/sys2/usymld.lisp:1081`, `:1093`, `:1121`): the map reload's ranges
  are empty, there being none, and the hash table's search is the page
  table's, FIND-PAGE-ENTRY to TAKE-TABLE-FRAME; seven of their labels were
  gone.
- **Checks**: `tools/system-check` gains `unsigned-addresses`, `fef-tags`,
  `mar-range` and `rev14-addresses` (its README); `rev14-addresses` needs
  revision 14. `herald-machine-type`'s Microcode line is checked against the
  running microcode's number, not "Microcode 2001". `tools/microcode-check`'s
  `address-past-28-bits`, which expected revision 13's fault for an address
  past 28 bits, is replaced by `address-in-no-region`: on revision 14 such
  an address is in the space, and a reference to a page of no region is the
  error ADDRESS-IN-NO-REGION.
- **The first band's route and its checks**: `tools/cross-build/run`
  assembles the microcode and PROM twice, cross-builds on System 2001's band
  (`tools/cross-check`'s checks 3 and 2, the site, WORMCH), boots the cold
  load on revision 14 through QLD and DISK-SAVE, rebuilds natively twice, and
  runs G2 section 7's checks (a)-(d), appendix A14.13's guards and the high
  band (its README). `tools/microcode-check` gains `rev14-fiddles`,
  `rev14-paging` (`cases-2mw/`, at 2 M words) and `rev14-mutants`, and
  `tools/system-check` gains `rev14-ephemeral`, the four
  `rev14-straddle-*` runs and `rev14-code-anywhere` (their READMEs).
  `tools/cold-compare` reads revision 14's cold load, whose AREA-NAME is area
  11, not 13. `tools/cross-check/compare.py` explains a function whose
  defining form names a compile-time definition `sys/cold/crossdefs.lisp`
  lists as `:changed` or `:new` (revision 14's `PRINTING-RANDOM-OBJECT` in
  the `:PRINT-SELF` methods of 10 files).
- **`tools/lispm-check`'s setup waits on the machine, not on a clock**
  (`tools/lispm-check:51-59`, `:155-236`, `:451-494`, `:671-730`, `:862`,
  `:876-877`, `:1035`, `:1149-1152`, `:1213-1215`; `docs/lispm-check.md:44-52`,
  `:83-84`, `:213-216`, `:234`): on a loaded host the cold boot and the setup's
  forms took longer than their fixed limits (300 s to the TELNET banner, 120 s
  a form) while the machine still ran, so a loaded machine reported a failure
  at setup. The setup and the probe now wait as long as the machine gets CPU
  time. A machine that gets none for 60 s (stopped), or that runs without
  answering until `--setup-limit` (1800 s by default,
  `LISPM_CHECK_SETUP_LIMIT`), is reported as a hang, exit status 3, distinct
  from a failure (2).
- **`tools/cross-build/run`'s wrapper race**: the step's threads that wrote
  the same wrapper at once shared one temporary file, so one thread's
  `os.replace` took it from under another's `chmod` and that thread raised
  `FileNotFoundError`; each writer now has its own temporary file
  (`tools/cross-build/run:190-198`). A thread that raises now fails its step
  and is named (`in_threads`, `tools/cross-build/run:109-129`, used at `:594`,
  `:649` and `:835`); before, the step judged only by the other threads'
  results and went on.

## The generational collector

Step 2 (contract G3 step 2): MIT's incremental copying collector, extended
with generations. An ephemeral area's new objects are made in eden; a young
collection flips eden and both survivor spaces and copies each survivor one
step on, to survivor space 1, survivor space 2, then the tenured generation;
a tenured collection is MIT's collection over every dynamic region.

### The microcode

Microcode 2002 still (it is unreleased); its files changed, and the receivers
get the new checksums. Labels are cited, in `sys/ucadr/`.

- **A region's generation** (contract 3.1, 9.1 item 1): region bits <6:5>,
  `REGION-GENERATION` (`uc-parameters.lisp`; 0 tenured, 1 eden, 2 survivor
  space 1, 3 survivor space 2), qcom's `%%REGION-GENERATION`; the assembly
  stops if qcom names it elsewhere (`REGION-GENERATION-QCOM-CHECK`).
- **Allocation by generation** (3.2): a cons goes into a region of its
  generation (`CONS-GENERATION`, `uc-storage-allocation.lisp`): the
  mutator's in an ephemeral area (`%%REGION-EPHEMERAL` in its area bits) is
  eden's, in any other area tenured; a transporter's copy goes to the
  destination the promotion table gives. CONS-CHECK-NEW and CONS-CHECK-COPY
  take only a region of that generation, and a static region only a tenured
  cons (`D-CONS-1`); RCONS makes a new region with that generation, in
  ephemeral space (bit 13) exactly when it is not tenured, so an ephemeral
  area's tenured regions lie below it.
- **Pretenuring** (3.2): a cons of more words than the pretenuring threshold
  in an ephemeral area goes to a tenured region (`CONS-GENERATION-PRETENURED`)
  and does not fill the cons cache (`SCONS2`, `LCONS2`), so the area's next
  small conses still go to eden.
- **The words consed since the last flip** (4.1): SCAV0 adds every word the
  mutator conses, `%GC-CONS-WORK` (XGCCW) its argument, and every flip clears
  them (XFLIP).
- **The first-object table** (6.1, 6.2; item 2): MAKE-REGION begins a tenured
  structure region that is not fixed or extra-pdl (`FIRST-OBJECT-TABLE-P`)
  with an ART-32B array of an entry a page, a long header past 1777 pages,
  entry 0 and the entries of the table's own pages 0, and the free pointer
  and the scavenger's pointer after it (`MAKE-REGION-TABLE`); CONSF writes,
  for each page whose first word the new object holds, the object's start
  (`CONSF-TABLE`); RCONS makes a new region big enough for the object and its
  table (`RCONS-NEED`), without which an object as big as the area's regions
  never fitted; UN-CONS clears the cons cache of a region with a table, whose
  limit it left past a page boundary. A region that should begin with a
  table and does not halts at FIRST-OBJECT-TABLE-MISSING
  (`CONSF-TABLE-CHECK`).
- **The transporter** (5; item 3): TRANS-OLD-COPY reads the source region's
  generation and the promotion table, `A-GC-PROMOTION`, bits <2g+1:2g>, for
  the copy's destination (`uc-transporter.lisp`); EXTRA-PDL-TRAP's copy, a
  new object, takes its area's allocation generation.
- **The young flip** (4.2; item 4): `(%gc-flip -1)` flips only the regions
  whose generation is not tenured, new or copy (`XFLIP-YOUNG`), and arms the
  marked-page walk; `(%gc-flip t)` is the tenured flip, as before.
- **The marked-page walk** (4.4, 4.5; item 5): beside the region loop, the
  scavenger visits every page to its free pointer's page of every tenured
  region that is new, copy, static or a scavenged fixed one, reading its entry
  through the physical memory window; a page whose <19> the setter marked is
  scanned as one step, a list page word by word, a structure page object by
  object from its first-object table's entry (a fixed region's from its
  origin), only the boxed words in the page and a PDL to its active top,
  each through TRANSPORT-SCAV; if no young pointer is left there, <19> is
  cleared in the entry and the TLB entry invalidated, with no reference to the
  page between (`SCAV-WALK`, `SCAV-WALK-PAGE`, `SCAV-WALK-WORDS`). Copyspace
  first: after a scanned page the region loop runs again if the transporter
  has consed; when the walk is done the region loop runs once more, and only
  then is `%GC-FLIP-READY` set (`SCAV3`, `SCAV5`).
- **The marked-page walk passes over a husk's body-forwards**
  (`sys/ucadr/uc-storage-allocation.lisp:860-889`, `SCAV-WALK-WORDS`).
  ADJUST-ARRAY-SIZE grows an array that is not at the end of its region by
  copying it, and STRUCTURE-FORWARD leaves a husk: a header-forward to the
  new copy in its header, a body-forward to that header in every other
  word, the leader's before the header. In a young collection the new copy
  of a tenured array, made in eden, is in oldspace. The walk dispatched every
  word through `TRANSPORT-SCAV`, so it met a leader word's body-forward
  before the header-forward and followed it through the header-forward to
  the new copy without transporting it first; when the flip had already
  transported that copy (held by a local: the PDL buffer is a root), the
  word there was a GC-forward and the machine halted in ILLOP at
  `SCAV-WALK-WORDS` (native5's compile of the system, the cross build's
  route on step 2's first band). A body-forward points into its own tenured
  husk, never at a young object, so the walk now passes over it; the husk's
  header-forward is dispatched as any word. Microcode 2002's files changed
  again: `ucadr.mcr`
  `826c766ca53ca5d4aa5c282c52dfe6b24cd50c5f7d878f03dc362063df9dfc90`,
  `.tbl` `25c8d252cf6c9a6b062c9c6edfaa356ed8ed65cc7ccc40b7337c1d988173c552`,
  `.locs` `f1a24e3e905959d764f586133d6a841e54ea64bf430e2b9ebaced399e83651c0`;
  `promh.mcr` is unchanged.
- **The setter's enable at every start** (8.3.5; item 6): INITIAL-MAP writes
  register-page word 221 = 1 after the pointer-type register
  (`uc-cold-disk.lisp`).
- **Lisp's three names** (item 7): `A-GC-WORDS-CONSED-SINCE-FLIP`,
  `A-GC-PROMOTION` and `A-GC-PRETENURE-THRESHOLD` follow `A-REGION-FLOOR`, at
  A 143-145, as qcom's A-MEMORY-LOCATION-NAMES has them; the unused
  `A-DISK-DOING-READ-COMPARE`, `A-DISK-CYL-BEG` and `A-DISK-CYL-END` are
  commented out, so `A-PDL-BUFFER-VIRTUAL-ADDRESS` and `A-PDL-BUFFER-HEAD`
  stay at A 430 and 431. The threshold is 32768 until Lisp writes it.
- **The mark bitmap** (8.3; item 8): after a save's pages, a second walk over
  them from region 0 writes each page's <19> as a bit, 32 to a fixnum word,
  32768 to a page, right after the band's last page and inside its valid
  size; `%SYS-COM-MARK-BITMAP` (system communication area word 30) holds its
  first band page (`DSR-MARK-BITMAP`, `uc-cold-disk.lisp`). A restore of a
  saved or incremental band checks it (below) and, once every entry is made
  and before the TLB is emptied, ORs each 1 bit into its page's entry
  (`APPLY-MARK-BITMAP`, from COLD-SWAP-IN); a cold load and the return from
  a save apply none.
- **The band formats** (8.3, 9.1 items 8 and 9): 2020 saved, 2021
  incremental, 2022 a cold load. A band of 2010-2012, revision 14's, halts at
  BAND-NOT-GENERATIONAL; 2000-2002 still at BAND-NOT-REVISION-14. A saved or
  incremental band whose `%SYS-COM-MARK-BITMAP` is 0 halts at
  MARK-BITMAP-MISSING, and one whose bitmap does not end where the band
  does (its first page plus a page per 32768 pages of the walk not its valid
  pages) at MARK-BITMAP-WRONG-SIZE.
- **The warm boot** (8.3.5; item 10): BEG0000 arms the marked-page walk again
  when any region is oldspace (`SCAV-WALK-ARM-IF-OLDSPACE`), since a warm
  boot loads A memory afresh and forgets the walk's place.
- **Checks**: `tools/microcode-check` gains `generational` (items 1-7: the
  three A-memory fixnums, the setter's enable, allocation by generation and
  pretenuring, the first-object table, the young flip, ages by the promotion
  table, C1-C5, C7, C8 and C18's microcode parts, and a husk's leader met by
  the walk, `gen-husk-leader`, which gets no answer on the walk without the
  change above), `generational-save`
  (item 8: a session, a save and a boot), `generational-static` (item 7 in the
  symbol table, and against a qcom that names them) and
  `generational-mutants` (a partial fix of each item planted and assembled),
  in its README, `cases-2mw/generational-2mw` (C17, a marked page out of
  core, at 2 M words) and `generational-rqb` (an RQB in a fresh
  `DISK-BUFFER-AREA` region, whose first-object table leaves its free pointer
  off a page boundary: it passes once the Lisp side's `MAKE-DISK-RQB` pads the
  region, and fails with this tree's). `tools/microcode-check/run` loads the Lisp files a case
  file's first line names (`; lisp: A.lisp,B.lisp`), so that two checks share
  one. The three new A-memory fixnums move the counter block up by three, so
  `tools/cross-build/lisp/coldrun.lisp` and `lisp/rev14-paging.lisp` read the
  paging counters with `SI:READ-METER` instead of at A 154, 155 and 157.
  `rev14-paging`'s young array of 1 M words would be pretenured under the
  collector's microcode; `REV14P-YOUNG-FILL` raises the threshold past it
  while it is made, when A 143-145 hold fixnums (`lisp/rev14-paging.lisp`).

- **REGION-TO-AREA by a table** (contract G3 step 2, clarification 18;
  `uc-page-fault.lisp`, `REGION-TO-AREA`):
  A memory's `A-REGION-AREA-MAP` (`uc-parameters.lisp`, 64 words after the
  mark bitmap's variables, outside the Q part) holds each region's area
  number, a byte a region, four a word; 377 says not known, and then the
  region's list thread is walked once, as MIT's REGION-TO-AREA did for every
  call, and the area kept in its byte. `FREE-REGION` sets a freed region's
  byte to 377 (`REGION-AREA-MAP-FORGET`, `uc-storage-allocation.lisp`), since
  the number may next be made for another area, and every boot all of them
  (`REGION-AREA-MAP-CLEAR`, from `BEG0000`, `uc-cold-disk.lisp`). The
  transporter calls it for every object it copies, and the walk was 18-23% of
  the scavenger's time in a young collection; with the table 2%, and the
  scavenging 3.6-3.8 µs a word copied against 4.7-5.0 (T1). A memory's
  constants now end at 1551, below the mouse arrays at 1600. Checked by
  `tools/system-check/cases/generational-tuning.cases`: a planted partial fix,
  `FREE-REGION` without the forget, fails two cases.
- **One cons scavenges at most a page's units** (contract G3 step 2, 4.5,
  amendment 8; `uc-storage-allocation.lisp`, `SCAV0`, `SCAV0-BOUNDED`): a
  cons of n words still counts its 4n units in `A-CONS-WORK-DONE`, but
  scavenges at most `PAGE-SIZE`, 1,024, of them while the **backlog**,
  `A-CONS-WORK-DONE` less `A-SCAV-WORK-DONE` with this cons's 4n counted, is
  at most the **backlog limit**,
  1,048,576 units, K times a working-storage region; above the limit it
  scavenges its whole 4n, as MIT's did. Later conses, each scavenging its
  own share while the scavenger is behind, and idle time do the rest. One
  cons scavenged up to all of a collection's remaining work at once: the
  error handler's `ASSURE-FREE-SPACE` (`sys/eh/eh.lisp:100`, called outside
  any flip) took 188.9 ms at 2 M words, a planted 200 K-word array 211-239
  ms; at a young flip with a live block in eden a 4,098-word cons took up to
  87.9 ms, 19.4 ms with a bound of 4,096 units and 3.6-4.3 ms with the page
  (T1, M-a). The limit keeps MIT's free-space rule (`gc.lisp`,
  `GC-GET-COMMITTED-FREE-SPACE`): through a tenured collection, a stream of
  64 K-word arrays finished it after 1,114,112 words consed unbounded,
  1,441,792 with the page and the limit, and not after 19,660,800 (300
  arrays) with the page alone (M-b). Above the limit a large cons pays
  MIT's burst (up to 1.1 s in M-b, as unbounded).
- **A stack group's saved accumulator that holds a body-forward is left as
  it is** (`SG-LOAD-BLOCK-INTO-PDL-BUFFER`,
  `sys/ucadr/uc-stack-groups.lisp:173-193`; `SCAVL3`,
  `sys/ucadr/uc-storage-allocation.lisp:603-616`). `STRUCTURE-INFO` leaves a
  `DTP-BODY-FORWARD` in `M-A` after it measures a structure-forwarded object
  (`SINFS-HFWD`, `:2176`), and a process switch saves `M-A` in the stack
  group's leader. `TRANS-BFWD` (`sys/ucadr/uc-transporter.lisp:321`) takes a
  body-forward as relative to the address it was read from, so the resume's
  transport of the leader and the scavenger's, when a young collection
  copies the stack group, followed it from the leader slot to an unrelated
  address. With the leader in ephemeral space that address lay in no region,
  and the page fault's trap, taken where no trap can be, halted the machine
  in `ILLOP` (PC 24770). The reclaim checker
  (`tools/system-check/lisp/generational-collector.lisp`) measures every
  object, a tenured husk among them, and so made C14 (c) of the save checks
  halt at 1920x1080: the halted stack group's saved `M-A` was a body-forward
  to a husk's header-forward, and A-PGF-VMA was exactly that forward's
  target plus the leader slot's offset from the husk. Both now leave a
  body-forward as it is, as `SCAV-WALK-WORDS` already did. Fixed on the
  CADR's line in the same way. `tools/microcode-check`'s new check
  `sg-saved-body-forward` puts such a word in a stack group's saved `M-A`,
  built so that following it lands on 2^31, in no region: microcode without
  the change halts at the resume, and with only the resume fixed, in the
  young collection that copies the stack group (`SCAVL3+4`); with the change
  its four cases pass, interpreted and compiled. C14's reproducer, the
  second session's cases on a band the first saved at 1920x1080, halted 6
  times in 6 and with the change passed 6 in 6 (on the microcode of the
  hand-over's commit with the change). The profile's record of
  `SG-LOAD-BLOCK-INTO-PDL-BUFFER`'s dispatch moves with the dispatch, to
  `+6` (`sys/ucadr/ucadr-profile.text:1745`). Microcode 2002's files
  changed again, four instructions more: at revision 14 `ucadr.mcr`
  `435edb07b00457bf31a1db1a3d125a8d9f6d65337ddcc0ea2725a1ec07573afb`, at
  revision 15 `ucadr.mcr`
  `01c62e2cbb33f151c5f41c25550dbe6dc321f1f778bf025635998c20d8eaf377`, both
  with `.tbl` `403027d72b51e911e801ab0d586fc870cade2b4304fd1e0d9b8b6820bb24ab01`,
  `.locs` `6f8437661b18529ae5a24dfacf9a58376e37412f1ef69d7d2d72b041e4360f60`
  and `.sym` `a648682a908f23fb779c2fafc9a9bd1c2fbe78acbcee00b3f947cdcef9f89d7a`;
  `promh.mcr` is unchanged at both. System 2002's band on the revision-14
  microcode passes step 2's gate on micro and on rtl as before, with the new
  check and the save checks at 1920x1080 (C14) added to it; at revision 15
  System 2002 reaches its listener on micro; `tools/assembler-check` passes
  all 30 checks, its revision-15 counts unchanged (359 hints, 140 predicted
  targets, every execution of the profile covered).

### The Lisp side

Written before the microcode and the cold load that it needs; compiled on
System 2001's band, not yet run there but for its logic. Citations are of the
files as this step left them. Revision 1 of the contract (a save keeps young
objects young) changed the save, the band's formats and the boot.

- **The generation field and the collector's A-memory variables**
  (`sys/cold/qcom.lisp:155`, `:1361`): `%%REGION-GENERATION`, region bits
  `<6:5>`, spare before: 0 tenured, 1 eden, 2 survivor space 1, 3 survivor
  space 2; after `%REGION-FLOOR`, `%GC-WORDS-CONSED-SINCE-FLIP` (the words
  consed since the last flip, which a flip clears), `%GC-PROMOTION` (the
  promotion table, two bits a source generation) and
  `%GC-PRETENURE-THRESHOLD`.
- **Young and tenured collections** (`sys/sys2/gc.lisp`): `GC-FLIP-NOW`
  takes the kind, `:TENURED` by default, and a tenure-all flag (`:360`); a
  young flip runs no next-flip list, resets no static region's scan pointer,
  deallocates no region's end and makes no notification, and both write the
  promotion table, computed before the pause from survivor space 1's words
  against the soft cap (`GC-PROMOTION-TABLE`, `:212`). The GC process
  (`:886`) reclaims a collection when the scavenger is done, then starts a
  tenured collection by MIT's free-space rule or after the tenured
  generation's growth by `GC-TENURED-GROWTH-LIMIT`, else a young one when the
  words consed since the last flip reach eden's size (`GC-COLLECTION-DUE`,
  `:916`); young collections report nothing (`GC-RECLAIM-OLDSPACE`, `:700`).
  `GC-STATUS` prints the generations and the collections by kind (`:616`;
  `GC-GET-GENERATION-SIZES`, `:195`).
- **The settings** (`:98`-`:129`): `GC-EDEN-SIZE` (NIL, 1/4 of main
  memory; 1/16 before, below), `GC-SURVIVOR-CAP` (NIL, eden's size), `GC-TENURED-GROWTH-LIMIT`
  (`:DEFAULT`, 1/4 of main memory) and `GC-PRETENURE-THRESHOLD` (32 K words),
  each read at the next flip; and the answers to two of the contract's
  questions, one variable each, both T: `GC-ON-AT-BOOT` (Q-GCa: `GC-BOOT`,
  `:1041`, turns automatic collection on at every boot; `GC-ON` takes
  `NO-QUERY`, `:970`, and `GC-OFF` no longer removes the boot's
  initialization) and `GC-TENURED-AUTOMATIC` (Q-GCb). The third, Q-GCc, was
  answered the other way (below), and its variable, `GC-SAVE-TENURES-ALL`,
  is commented out (`:107`).
- **A save keeps young objects young** (contract revision 1, 8.3.1;
  `sys/sys/qmisc.lisp:1844`; `GC-PREPARE-FOR-DISK-SAVE`,
  `sys/sys2/gc.lisp:1110`): DISK-SAVE finishes any collection, runs one young
  collection to its reclaim with the normal promotion table, and keeps the GC
  process stopped until the save; the ephemeral areas stay ephemeral, so what
  DISK-SAVE conses afterwards is young, and the microcode's save writes each
  page's young-pointer mark into the band's mark bitmap. A save that does not
  happen enables the GC process again if automatic collection is on
  (`GC-AFTER-DISK-SAVE-ABORT`, `:1119`). Revision 0's save, which made the
  ephemeral areas not ephemeral and tenured every young object, is commented
  out (`:1049`-`:1093`). DISK-SAVE itself never tenures; the build tenures
  a band it builds before its save, with `(SI:GC-FLIP-NOW :YOUNG T)` and
  `SI:GC-RECLAIM-OLDSPACE` (contract 9.4).
- **No save while a mark is in the TLB only** (8.3.1, 8.3.3;
  `sys/sys/qmisc.lisp:1954`, `:1983`): just before `%DISK-SAVE`, where the
  incremental save's check of the regions runs, DISK-SAVE reads
  register-page word 224, the write-backs of a page's mark that the guard
  refused (`DISK-SAVE-REFUSED-WRITE-BACKS`, `:1994`), and refuses the save
  while it is not 0, as it refuses a region changed since the incremental
  save's snapshot: the band is not written, and an error says so.
- **The mark bitmap's room** (8.3.2): `ESTIMATE-DUMP-SIZE`
  (`sys/sys/qmisc.lisp:2026`) adds the bitmap's pages, one for each 32,768
  pages of the band's walk (`MARK-BITMAP-PAGES`, `:2050`), to the
  partition size it asks for; `%SYS-COM-MARK-BITMAP`
  (`sys/cold/qcom.lisp:281`), after `%SYS-COM-REGION-FLOOR`, holds the band
  page of the bitmap's first page, 0 in a cold load; the area has 2 spare
  words left.
- **Band formats 2020 and 2021** (8.3, 9.4; `sys/io/disk.lisp:1268`):
  `BAND-FORMAT-COMPRESSED` and `BAND-FORMAT-INCREMENTAL`, which Lisp's band
  readers compare with, are 2020 and 2021 (the cold load is 2022); step 2's
  microcode refuses revision 14's 2010-2012.
- **A warm boot mid-collection keeps the collection's promotion table**
  (8.3.5): the flip keeps its table (`GC-COLLECTION-PROMOTION`,
  `sys/sys2/gc.lisp:241`), and `GC-BOOT` and `GC-ON` give the microcode that
  table while a region is oldspace (`GC-RUNNING-PROMOTION-TABLE`, `:250`),
  since A memory is loaded afresh at the boot, its 0 the tenure-all table;
  `GC-ON` gave a table computed then.
- **Areas** (`sys/sys/qfctns.lisp:2868`; `sys/sys2/gc.lisp:1134`-`:1171`):
  `MAKE-AREA` takes `:GC :EPHEMERAL`, which gives the area's bits
  `%%REGION-EPHEMERAL` and a tenured first region, and refuses it with
  `:PDL`; `MAKE-AREA-STATIC` and `MAKE-AREA-TEMPORARY` (`:2858`) refuse an
  ephemeral area, `MAKE-AREA-DYNAMIC` (so `CLEAN-UP-STATIC-AREA` too) refuses
  `MACRO-COMPILED-PROGRAM`; `MAKE-AREA-STATIC-INTERNAL` and
  `MAKE-AREA-REGIONS-STATIC` (`:1343`) change tenured regions only.
  `FULL-GC` (`:1218`) finishes any collection, flips every region with the
  tenure-all table, and turns automatic collection back on if it was on.
- **The first-object table's Lisp writers** (`sys/sys/qrand.lisp:1448`):
  `REGION-HAS-FIRST-OBJECT-TABLE-P` names the regions that have one (tenured
  structure regions not free, fixed or extra-pdl); `GC-RESET-FREE-POINTER`
  (`:1495`) writes the entries of the pages it newly covers with the growing
  object's start, which `ADJUST-ARRAY-SIZE` passes (`:1636`), and refuses to
  move up in such a region without it; `FILL-UP-REGION`
  (`sys/sys2/gc.lisp:1369`) writes each filler page's own start;
  `RESET-TEMPORARY-AREA` (`sys/sys/qrand.lisp:1423`) resets to the table's
  end.
- **Hash tables rehash after a young flip only if they hold a young key**
  (`sys/sys2/hash.lisp:87`-`:114`): `HASH-TABLE-GC-GENERATION-NUMBER` keeps
  the generation and, negated, the young flag (n >= 0 none, -1 rehash at the
  next miss, n <= -2 young at generation -2 - n), with the leader unchanged;
  `%GC-TENURED-FLIP-GENERATION` is the generation after the last tenured
  flip. `SXHASH` notes a young object hashed by address
  (`SXHASH-HASHED-YOUNG-ADDRESS`, `sys/sys/qrand.lisp:201`;
  `YOUNG-POINTER-P`, `:196`), `:PUT-HASH` and `PUTHASH-BOOTSTRAP` mark the
  table (`sys/sys2/hashfl.lisp:179`, `sys/sys2/hash.lisp:394`), a rehash
  finds the flag again (`:268`, `:301`), and `:GET-HASH`, `:REM-HASH` and
  `INSTANCE-HASH-FAILURE` (`sys/sys2/flavor.lisp:2843`) test staleness so.
- **The incremental save is refused after a tenured flip only**
  (`sys/io1/inc.lisp:170`; `GC-TENURED-FLIP-SINCE-P`,
  `sys/sys2/gc.lisp:255`): the base band may hold young objects, and a young
  flip may have freed its young regions and reused their numbers, but pages
  are paired by region number and place and compared word for word, so the
  save stays right; a tenured flip moves most pages, and the save would gain
  nothing.
- **What needs a page boundary pads to one** (clarification 11; the review
  of the first-object table): a region of `DISK-BUFFER-AREA` begins with its
  first-object table, so a fresh one's free pointer lies past the table, off
  a page boundary, where MIT's code found its first object. `MAKE-DISK-RQB`
  (`sys/io/disk.lisp:291`) gives back its three arrays when `RQB-BUFFER` is
  not on a page boundary, pads the region to one with an `ART-32B` filler
  (`DISK-BUFFER-REGION-PAD-TO-PAGE`, `:325`) and makes the RQB again: before,
  every RQB made in a fresh region stopped at "... not on a page boundary",
  the incremental save's compare and the file device's ring among them.
  `PAGE-RQB` is made the same way (`MAKE-PAGE-RQB`, `:2152`), where it lay 17
  words past a boundary, across two pages of which `WIRE-PAGE-RQB` wired the
  first alone. `WIRE-DISK-RQB` (`:402`) and `WIRE-PAGE-RQB` (`:2165`) refuse
  an RQB off a page boundary before any transfer. The `UNIBUS-CHANNEL`
  resource (`sys/io/unibus.lisp:44`) says why QUUX never needs the same.
- **Walkers from a region's origin start after its table** (clarification
  12): `MAPATOMS-NR-SYM` (`sys/sys/qrand.lisp:2428`), which a cold load's
  first boot runs in `PKG-INITIALIZE`, took the table's header and entries
  of each region of `NR-SYM` and `WORTHLESS-SYMBOL-AREA` for symbols; it and
  `PRINT-INT-PKT-STATUS` (`sys/network/chaos/chsncp.lisp:2207`) now start
  at `REGION-FIRST-OBJECT-TABLE-END`.
- **The cold load** (contract 9.3, 9.4; `sys/cold/coldut.lisp`), keyed on
  the target's parameters defining `%%REGION-GENERATION`
  (`TARGET-HAS-GENERATIONS-P`, `:621`), so that revision 14's still give
  their cold load (2012) byte for byte (the cross build's native control):
  each region of the rule of contract 6.1 begins with its first-object
  table (`MAKE-FIRST-OBJECT-TABLES`, `:656`, called by `CREATE-AREAS`,
  `:796`); `ALLOCATE-BLOCK` (`:811`) gives each page whose first word a
  block holds the start of the object the block belongs to, its callers
  saying which blocks begin an object (a string, a symbol, a bignum, an
  array's leader or header, a FEF's header, `sys/cold/coldld.lisp:668`).
  A region of no length, FASL-TEMP-AREA's, the cold load's last area, has
  no room for a table and gets none; nothing is consed in it.
  WORKING-STORAGE-AREA's area bits carry `%%REGION-EPHEMERAL` while its
  region stays tenured (`:788`); the format is 2022 (`:1517`) and
  `%SYS-COM-MARK-BITMAP` 0 (`:1483`), the system communication area 31
  words (`:1453`): revision 14's cold load left that word as the partition
  held it.
- **The first band's route** (contract 9.4): `tools/cross-build/run` builds
  from System 2002's revision-14 hand-over band (`--builder-revision 14`,
  its PROM, its tree as the base; `sys/cold/crossdefs.lisp` listed against
  it), its bands are format 2020, and `tools/cross-build/lisp/coldrun.lisp`
  tenures every young object before each save the build makes (a young flip
  with the tenure-all table, reclaimed), reporting the young words before and
  after, as `docs/building.md` does by hand. Its guards (`guards.py`) add
  C27's lines; the step `built` saves band4 once more without the tenuring
  and records each band's young words (C29), and checks its RQBs and
  `DISK-BUFFER-AREA`'s tables (`cases/built.cases`). `tools/cross-check`'s
  `check3.py` checks step 2's cold load (the tables, the ephemeral working
  storage, 2022, the bitmap's word, NR-SYM's symbols) and `native.cases`
  asks for no generations in the builder's own parameters, compiling the
  builder's own generator from its sources, since System 2002's hand-over
  tree carries no QFASL of it. The step high counts a region of a dynamic
  area below the floor as holding objects only past its first-object table
  (`tools/cross-build/lisp/high.lisp`): FASL-TABLE-AREA's region that the
  full collection leaves empty holds its table alone, 49 words, and was
  taken for one holding an object.
- **The cross build gives the compile the tree's special variables**
  (`sys/cold/cross.lisp`, `CROSS-DECLARE-SPECIALS`, `CROSS-END`;
  `tools/cross-check/crossdefs.py`, `sys/cold/crossdefs.lisp`'s
  `*CROSS-SPECIALS*`). A `DEFVAR` proclaims its variable special only while
  its own file compiles; natively every later compile knows it from the loaded
  file, but the builder has not loaded the tree, so `sys/sys2/hashfl.lisp`'s
  `:PUT-HASH`, compiled for the target, bound `SXHASH-HASHED-YOUNG-ADDRESS`
  (`sys/sys/qrand.lisp:201`) as a local. On the cross-built band `SXHASH`'s
  young flag then stayed set in the global value and every hash table counted
  as holding a young key: an EQ table given a symbol after an EQUAL table was
  given a young array was young, `(T T)` where the native band gives
  `(NIL NIL)`. The route's check (a) found the FEF differing from the native
  build's. `crossdefs.py` now lists every special variable of the tree that
  the builder's system has not (16 proclaimed on System 2002's revision-14
  band, of 20 listed), and `CROSS-BEGIN` proclaims them for the cross build's
  duration; a special the tree dropped stops it. `hashfl.lisp` compiled so on
  the builder is the native build's, as `same40.py` compares them; check 1
  gains three cases.
- **Checks**: `tools/system-check` gains `generational-collector`, with the
  table checker and the reclaim checker and three files of planted partial
  fixes, and `save/`, the save checks (C14, C25-C29's Lisp parts), each a
  session, a `DISK-SAVE` and a boot, with two files of planted partial fixes
  (its README); they need step 2's microcode and band. And
  `generational-table-users` (P2-P5 of the review: the split retry, an RQB
  off a page boundary refused, `PAGE-RQB`, `MAPATOMS-NR-SYM`, the Chaosnet
  buffers), with three files planting the functions as they were.
- **Checks run on step 2's first band**: automatic collection is on at
  every boot there, and its flips moved what two checks of 2 M words plant
  (`rev14-paging`'s fresh pages read back other than their fill,
  `format-clauses-gc`'s planted region was freed), so both turn it off first,
  as revision 14's band had it
  (`tools/microcode-check/cases-2mw/rev14-paging.cases`,
  `tools/system-check/cases-2mw/format-clauses-gc.cases`).
  `generational-save` expects survivor space 2 for the two lists stored
  before the save, since `DISK-SAVE`'s own young collection moves them on
  from survivor space 1 (`tools/microcode-check/generational-save:184`,
  `lisp/generational-save.lisp`).
- **A simple process that would wait no longer stops the scheduler**
  (`sys/sys2/proces.lisp:811`; MIT's, so System 2001 has it too). A simple
  process's function runs in the scheduler, which cannot wait, and
  `PROCESS-WAIT` there throws to `PROCESS-WAIT-IN-SCHEDULER`, whose catch was
  only around the wait functions: the throw found none, the scheduler stopped
  in the cold load stream's debugger, and every process and the network with
  it. The dormant file connection GC, a simple process run every minute,
  did so when it sent a host `:SEND-IF-HANDLES` while the TELNET server held
  that flavor's method table, rehashing it after a flip: `FULL-GC` typed
  right after `GC-IMMEDIATELY` sometimes got no answer, and the connection
  was given up after 180 s. The scheduler now catches the throw around a
  simple process's function, and the process runs it again from its start a
  tick later (`SIMPLE-PROCESS-RETRY-P`, `:712`). Checked by `tools/system-check`'s
  `scheduler-simple-wait`.
- **The generational collector's checks, after their first runs on step 2's
  band** (`tools/system-check/`):
  - the table checker (`lisp/generational-collector.lisp:181`) leaves out
    old regions, which `GC-RECLAIM-OLDSPACE-AREA` keeps when old as their
    area's only region (`sys/sys2/gc.lisp:752`): after a tenured collection
    four were left, one holding forwarded objects, and its walk's
    `%STRUCTURE-TOTAL-SIZE` met a `DTP-GC-FORWARD` word and halted the
    machine (`XFSHS1`, after the reclaim checker's case, whose case itself
    passed with the connection alive). Since clarification 16 (below) a
    reclaim keeps no region old; the checker still leaves old regions out,
    since they exist while a collection runs and it may be called then;
  - C6 (b) (`:263`) grows an array of the long format: 10 elements is the
    short one, and growing past 1,023 is a copy, never in place. C6 (b)
    and (c) (`:286`) first leave stale entries above the free pointer, by
    arrays given back, since a fresh table's entries are valid starts and a
    missing writer went unseen; the planted writers now fail them, (T 3)
    and 1. C6 (a) gains two give-backs in a row (`GENCOL-C6A2`, `:230`),
    which E1's `uncons-keeps-cache` microcode fails and the first C6 (a)
    case passes (clarification 13);
  - C17's case at 32 MW is commented out: `PAGE-OUT-WORDS` only offers a page
    to be swapped out (`sys/io/disk.lisp:2291`), so the page stayed in core.
    C17 is `tools/microcode-check`'s `generational-2mw`;
  - C25 (b) (`lisp/generational-collector-save.lisp:84`, `:108`;
    `save/before.cases`) makes its referrer: the layout has no symbol
    between the wired size and `1000000`, only the fixed areas' regions, so
    the search found none and (b) went unchecked; now a young symbol names
    an area, and `AREA-NAME`'s word for it, on a page wired for the restore,
    holds the only reference.
- **Cross-check check 1 runs on a builder of IEEE singles**
  (`tools/cross-check/cases/check1.cases:24`): reading the literal `1e-40`
  signals `FLOATING-EXPONENT-UNDERFLOW` on Systems 2001 and 2002, as their
  arithmetic does below the smallest normal single (no subnormal is made;
  `float-reading`), and stopped the check. The subnormal case reads the
  literal where the builder's floats are wider and takes the subnormal's own
  bits where it signals; the underflow case reads `1e-46` under
  `ZUNDERFLOW`. The decoder of a target's single, `COLD:BINARY32-TO-FLOAT`
  (`sys/cold/coldld.lisp:417`), made a subnormal by `SCALE-FLOAT`, which
  signalled the same on such a builder (check 1's round trips of 71362 and
  1); there it now takes the subnormal's bits as the float. The encoder,
  `COMPILER:FLOAT-TO-BINARY32` (`sys/sys/qcfasd.lisp:349`), went through
  `INTEGER-DECODE-FLOAT`, whose `ABS` of a subnormal signalled it too; on
  such a builder a single's bits are now its own field. Neither changes a
  normal single's bits.
- **Revision 14's ephemeral and list straddle checks run under the
  generational collector** (`tools/system-check/`): `rev14-ephemeral` read
  the setter's enable (word 221) as 0, revision 14's boot, which step 2's
  microcode turns on at every start, and made its old array in
  `WORKING-STORAGE-AREA`, now ephemeral, so the array was young; it now
  expects 1 and makes the array in a dynamic area of its own
  (`cases/rev14-ephemeral.cases`, `lisp/rev14-ephemeral.lisp:54`).
  `rev14-straddle-working-storage` placed `WORKING-STORAGE-AREA`'s next list
  region across 2^31, but an ephemeral area's conses go to eden, above 2^31,
  never to a region the floor places: it straddles a dynamic list area of its
  own instead and conses the workloads' lists there (`REV14S-LIST-AREA`,
  `lisp/rev14-straddle.lisp`). Before, 2 failures each on step 2's band; after,
  35 of 35 and 9 of 9.
- **`tools/cross-build/run` gives its lispm-check runs the run's engine**
  (`tools/cross-build/run:216`): a run on rtl booted its sessions on rtl but
  ran every lispm-check, a saved band's boot among them, on micro,
  lispm-check's default; so did `tools/microcode-check/generational-save`,
  which uses it.
- **A reclaim leaves no area holding an old region** (contract G3 step 2,
  clarification 16; `sys/sys2/gc.lisp:763`, `:786`): `GC-RECLAIM-OLDSPACE-AREA`
  kept an area's only region when it was old, MIT's rule, whose own comment
  marks its reason ("no place to remember its bits") no longer true. After a
  collection in which every object of some area died, such regions stayed
  (three on the high band after its `FULL-GC`: `TV:SCROLL-LIST-AREA`,
  `SI:FLAVOR-DATA-AREA` and `FASL-TABLE-AREA`; four on native6 after one
  tenured collection), so `SI:GC-OLDSPACE-P` said a collection was running
  when none was, a saved band's boot found oldspace and armed the
  marked-page walk (`generational-save`'s bitmap case found 77 of 274 pages
  unmarked on the high band, and `save/after.cases`' first case gave
  `(NIL T)`), and regions of forwarded objects stayed for object walkers to
  meet. The last old region is now freed with `%GC-FREE-REGION`, like every
  other, and the area is given a new empty region in the same step, inside
  the reclaim's `WITHOUT-INTERRUPTS`: `%MAKE-REGION` from `AREA-REGION-BITS`
  with `%%REGION-EPHEMERAL` cleared and the generation tenured, at
  `AREA-REGION-SIZE`, as `MAKE-AREA` makes an area's first region
  (`sys/sys/qfctns.lisp:3038`), so below ephemeral space. The area is never
  left without a region: RCONS reads the first element of an area's region
  list as a region before it tests for the end marker. No microcode
  changes. Checked by `tools/system-check`'s new `generational-reclaim`, C30
  (`cases/generational-reclaim.cases`, `lisp/generational-collector.lisp:583`),
  with three planted partial fixes (`lisp/generational-collector-plant-keep-old.lisp`,
  `-plant-free-only.lisp`, `-plant-new-keeps-bit-13.lisp`).
  `tools/microcode-check/generational-save` gains a case after its bitmap
  case: no young flip ran between the save and the check
  (`GS-NO-FLIP-SINCE-SAVE`, `tools/microcode-check/lisp/generational-save.lisp:82`;
  `generational-save:190`), since the boot's checks run with collections on
  and a later flip's walk may clear a mark legitimately.
- **The flip's after-flip initializations scavenge nothing** (contract G3
  step 2, clarification 18; `sys/sys2/gc.lisp`, `GC-FLIP-NOW`): they run with
  `INHIBIT-SCAVENGING-FLAG` bound to T, so that their conses add their work
  to the scavenger's debt, paid by later conses at K=4 (contract 4.5), rather
  than scavenging it inside the flip's WITHOUT-INTERRUPTS. `EH`'s
  `ASSURE-FREE-SPACE` conses 4,096 words twice, each scavenging 16 K words of
  work at once: young flips took 59-115 ms with it, 9.5-12.6 ms now (T1).
- **The GC process's priority and the scheduler's clock**
  (contract G3 step 2, clarification 18; `sys/sys2/gc.lisp`, `GC-ON`,
  `GC-OFF`; `GC-PROCESS-PRIORITY`, 5, and `GC-SEQUENCE-BREAK-TICKS`, 6):
  GC-ON gives the GC process a priority above the user's processes and the
  clock's sequence break every 6 60ths of a second; GC-OFF gives back the
  microcode's once a second and the priority 0. The scheduler runs
  only at a sequence break or when the running process waits, so at the
  default priority a young collection waited for the listener's quantum, one
  second, and at once a second the priority alone still let eden overshoot by
  up to a second's consing: young flips came 4.0 M words consed apart at eden
  2 M, now 2.10-2.18 M (T1). The faster clock costs 1.47% of S4's time with
  the collector off; every 20 60ths, 0.44%.
- **`tools/system-check/cases/generational-tuning.cases`** checks the three:
  the after-flip initializations see scavenging inhibited and the flag is the
  collector's again after the flip (fails with GC-FLIP-NOW as it was);
  `%AREA-NUMBER` of every region in use against its list thread, before and
  after the table fills, and after a young collection's regions are freed and
  one is made again for a new area (fails with the planted `FREE-REGION`);
  the priority and the clock after GC-ON, and both after GC-OFF (fails with
  GC-ON as it was, or with either setting alone).

- **The committed free space counts the backlog limit** (contract G3 step 2,
  4.5, amendment 8; `sys/sys2/gc.lisp`, `GC-BACKLOG-LIMIT`,
  `GC-GET-COMMITTED-FREE-SPACE`): the bound on one cons's scavenging may
  add up to the backlog limit over K, 262,144 words, to the
  consing a collection needs beyond MIT's rule, and
  `GC-GET-COMMITTED-FREE-SPACE` commits it besides. `GC-BACKLOG-LIMIT`
  mirrors the microcode's constant at `SCAV0`. Checked by
  `generational-tuning`'s C31 (a)-(c): a 200,000-word cons right after a
  young flip leaves the collection running (fails if a cons scavenges its
  whole 4n), a 300,000-word one, over the limit, finishes it (fails without
  the limit), and the committed free space is MIT's figure plus 262,144
  words for fixed space sizes (fails without the term).
- **Eden's default is a quarter of main memory** (contract G3 step 2,
  section 10; `sys/sys2/gc.lisp`, `GC-EDEN-WORDS`): `GC-EDEN-SIZE` NIL now means
  1/4 of main memory in words, 524,288 at 2 M words and 8,388,608 at 32 M,
  not 1/16; it stays a word count with no page alignment, since eden is full
  when the words consed since the flip reach it. With the fixes above, T1
  measured 1/4 as the only size that keeps the long session's collector time
  near the 5% gate (+2.6% at 2 M words, −18.3% against a collector-off
  baseline that pages at 8 M, +5.4% at 32 M) with every pause within its limit
  (young flip 10.3-18.2 ms), and at which data living a few flips dies in the
  survivor spaces (28 K words tenured against 2.98 M at 1/16). Checked by
  `generational-collector`'s defaults case and the new `eden-default` (32 M
  words) and `eden-default-2mw` (2 M words), which fail at 1/16.
- **Which pauses §13 gates** (contract G3 step 2, clarification 17):
  automatic collection's in the workloads; a batch a program asks for
  (FULL-GC, GC-IMMEDIATELY, GC-RECLAIM-OLDSPACE, GC-FLIP-NOW over a running
  collection, DISK-SAVE's collections, the build route's) is reported, not
  gated. No code change.

## Revision 15

QUUX's revision 15 (contract G3 revision 15, and its appendix A15b): the
pipelined micro-engine, its 64-bit microinstruction, and the OA registers read
only through the OA selects: the micro-assembler, the microcode with its
selects, the boot PROM's new reader and the loaders. Until release-2002 the
tree assembles for revision 14 too, which the boards run until then.

### The micro-assembler

- **One target description** (`sys/sys/uatarget.lisp:61`,
  `*assembly-targets*`; loaded before the assembler, `sys/sys/sysdcl.lisp:394`):
  every parameter of the machine an assembly is for, the word's width and
  fields, the data type and fixnum tag, each memory's size, the
  microinstruction's width, the `.mcr`'s format and sections, the extension's
  fields, the OA registers and the fields their selects reach.
  `ua:*word-width*` and `ua:*hardware-revision*` name it (`assembly-target`,
  `:150`; 32 bits at 13 the CADR, 40 bits at 13, 14 or 15 QUUX's), and an
  unknown pair is refused before assembly (`sys/sys/cadrlp.lisp:375`). The
  assembler takes the dispatch memory's size and address field, the memories'
  sizes (`CONS-LAP-ALLOCATE-ARRAYS`, `:447`, in place of the assembling
  world's `SI:SIZE-OF-HARDWARE-CONTROL-MEMORY`), the revision a name needs
  (`cons-lap-symeval`, `:1623`) and the checks that apply (`:751`) from it;
  the `.mcr` writer takes its section 6, A memory's section and the symbol
  area's tag from it (`write-mcr-file`, `sys/sys/qwmcr.lisp:58`, `:203`), the
  tag now the target's own rather than the world's compiled-in `DTP-FIX` and
  `%%Q-DATA-TYPE`. Revisions 13 and 14 and the CADR write what they wrote:
  microcode and PROM 2002 for revision 14, assembled on System 2000's 32-bit
  band and on System 2002's 40-bit one, are byte for byte today's.
- **Revision 15's `.mcr` is self-describing** (appendix A15b.7;
  `write-mcr-sections`, `sys/sys/qwmcr.lisp:221`): the format word
  `0x51550001` and the number of sections, then each section's 8-word header
  (type, items, actual and storage widths, start, three zero words) and its
  items, least significant word first: 6 the hardware revision, 1 the control
  store at 64 bits (the PROM's own from 36000), 2 the dispatch memory with odd
  parity in `<17>` (`d-mem-odd-parity`, `:294`), 3 the symbol area at 40 bits,
  each word tag 005 over its value, 4 A memory at 40 bits; zeros to the
  block's end. An item wider than its width, a control store section where
  the loaders refuse it (`check-control-store-section`, `:301`), or a base
  version is refused rather than written. The same sources at revision 15
  give the same `ucadr.mcr` and `promh.mcr` on a 32-bit band and a 40-bit one.
- **The OA selects** `oa-low-select` and `oa-high-select`, the extension's
  `<60>` and `<61>` (`sys/sys/cadsym.lisp:524`), assemble as nothing below
  revision 15, where IMOD ors the register into the next word as the select
  does, so one source means the same at 14 and 15 (`sys/sys/cadrlp.lisp:304`);
  revision 14's names are marked with their revision, 14, and so are taken
  at 15 (`:300`).
- **The OA select check** (appendix A15b.15; `check-oa-selects`,
  `sys/sys/cadrlp.lisp:1312`, `oa-select-breaches`, `:1244`) runs over the
  assembled I-MEM and D-MEM of every revision-15 assembly, the microcode's
  (`:760`) and the PROM's (`:1523`), and refuses: a word that writes
  `OA-REG-LOW` or `OA-REG-HIGH` unless every word that can run next selects
  it (a write in a return's slot is refused); a selecting word that can be
  entered other than right after such a write, at a return point or at an
  entry point; and two selects on a word, a select with the PDL address
  field, `oa-low-select` with the hint, `oa-high-select` on a dispatch, and
  `oa-low-select` on a dispatch other than a dispatch-memory write without
  POPJ. It follows the delay slot and N: after a jump with N its slot runs only
  when the jump is not taken, and a dispatch's slot follows each entry's N.
  Each breach is printed with the word and the rule. The sources' microcode
  and PROM carry their selects ("The microcode and the boot PROM", below)
  and pass; `ua:*oa-select-check-refuses*` nil (`:1057`) prints the breaches
  and writes the files all the same, for measuring only.
- **D is enabled on revision 15** (appendix A15b.9; `RESET-MACHINE`,
  `sys/ucadr/uc-cold-disk.lisp:150`): the MACRO-DISPATCH register is written
  with D's enable, `<30>`, beside the enable, `<31>`, on a machine of
  revision 15 or later (MACHINE-ID's `<15:4>`, read at run time, as
  `XWIPM-I` reads it), so that a return that needs a fetch fuses on the
  fetched word. Revisions 14 and 15 assemble the same `<47:0>`.
- **The main-loop return check** (contract H8a 3.3; the D-timing ruling;
  `check-main-loop-return-slots`, `sys/sys/cadrlp.lisp`): on revision 15 the
  micro-assembler refuses a word that can run as the delay slot of a
  main-loop return and uses the SPC stack (a POPJ, a call or a return, a
  dispatch that pushes its own address or has P or R entries, functional
  source 1 or 14, functional destination 15). A fused return keeps the stack
  at the return, where an unfused one pops it, so such a slot sees two
  different stacks. The main-loop returns are found by a walk at call depth 0
  from the handlers the main loop enters (`main-loop-returns`): 391 in
  microcode 2002, for revisions 14 and 15, and no slot of theirs uses the
  stack.
- **The profile pass** (appendix A15b.8; `profile-pass`,
  `sys/sys/cadrlp.lisp`, run after the checks on every revision-15 assembly
  of the microcode) reads the profile, `sys/ucadr/ucadr-profile.text`: one
  line a site, keyed by the nearest preceding label and an octal offset. It
  sets H, `<48>`, on a conditional jump whose majority transfers, and a
  dispatch's predicted address, `<61:48>`, with P and R inverted in `<62>`
  and `<63>`. A key not found, or found on a word of another class, gives
  zero, and so does H with `oa-low-select`. From the word itself it sets the
  PDL address field (E `<48>`, B `<50:49>`, D `<58:51>`) of every ALU word
  that writes PDL-INDEX with `M-AP`, the PDL pointer or PDL-INDEX plus an A
  constant, or `A-LOCALP` plus an M constant, D within −128 to 127 and no
  select (A15b.2; `pdl-field-of`): 82 words of microcode 2002. It reports
  the share of the profile's conditional jumps' and dispatches' executions
  it covers. `check-extension` then refuses an extension that breaks A15b.2's
  rules (`extension-breaches`). Revision 14's assembly is unchanged.
- **The profile** (`sys/ucadr/ucadr-profile.text`) is muir-sim's profile
  harness's on microcode 2002 for revision 15 with D on, `rtl`, 32 MW, the
  twelve workloads and bitblt: 1,405 conditional jumps and 376 dispatches
  that ran, 72,822,600 and 32,404,727 executions, the record predicting
  95.91% and 77.82% of them. Every record lands on a word of its class, so
  the pass covers all of their executions: it sets H on 359 jumps and a
  predicted transfer on 140 dispatches (64 jumps, 35 calls, 41 returns),
  and leaves the other 1,046 jumps and 236 dispatches at zero, their
  fall-through or drop-through prediction.
- **`tools/assembler-check`** gains `rev15`, `oa-select` and the checks
  under "The checks" below (its README), with the fixture `lisp/oasel.lisp`;
  **`tools/cross-build`**
  gains `--asm-target` and `--oa-select-check` for the assembly step (its
  README). `docs/building.md`, "Assembling the microcode", says how.
- **`tools/assembler-check`'s `rev13` and `rev14` compare the microcode
  symbol area with release 2001's by value** (`symbol_area_values`,
  `same_symbol_area`, `tools/assembler-check/run:422`): release 2001's
  `sys/ubin/` stays their reference, but its symbol area carries the 32-bit
  world's fixnum tag in `<29:25>`, which the writer no longer adds ("The
  microcode symbol area holds plain addresses", above), so both checks failed
  since that fix. The tag is stripped from each word before the comparison;
  every other part of the files is still compared byte for byte, and each run
  shows that a planted change in a symbol area value is caught
  (`symbol_area_control`).

### The microcode and the boot PROM

- **Both revisions until release-2002.** The tree's microcode and boot PROM
  assemble for revisions 14 and 15, so fixes made on this line still reach
  the boards, which run revision 14 until then.
  - The OA selects assemble as nothing below 15 (above).
  - `promh.text` is both revisions' PROM, chosen by `*hardware-revision*` at
    assembly (`(if ...)` blocks, `sys/ucadr/promh.text:33` on): revision
    14's as it was, and revision 15's. PROM 2002 for revision 14 assembles to
    the file it was, byte for byte.
  - `tools/cross-build` still assembles for revision 14 by default.
  - The revision-14 and revision-15 assemblies of the microcode have the
    same `<47:0>`, word for word, and the same dispatch memory, A memory and
    symbol area: revision 15 adds only the selects in `<63:48>`
    (`tools/assembler-check`'s `dual`). The PROM's two differ by design.
- **The OA selects** (appendix A15b.15; amendment 1, 1.7): every word that
  reads `OA-REG-LOW` or `OA-REG-HIGH`, which revision 15 no longer ors into
  whatever word runs next, names the register by its OA select, and carries
  the comment `;reads oa-reg-low (rev 15)` or `;reads oa-reg-high (rev 15)`.
  **167 in all:** the microcode has 159, 129 `oa-low-select` and 30
  `oa-high-select`. These are amendment 1's 149 sites, `XWIPM-I`'s second
  write (below), and the 9 of `REGION-TO-AREA`, `REGION-AREA-MAP-FORGET` and
  `REGION-AREA-MAP-CLEAR` (6 low, 3 high; `sys/ucadr/uc-page-fault.lisp:2492`,
  `:2529`, `:2546`). `MISC1A`'s four landing words `MISC1A+4`,
  `MISC-TO-STACK`, `MISC-TO-RETURN` and `MISC-TO-LAST` are among them
  (`sys/ucadr/uc-macrocode.lisp`, `sys/ucadr/uc-call-return.lisp`). The boot
  PROM has 8, all `oa-low-select`: `CLEAR-M-MEMORY`, `CLEAR-A-MEMORY`,
  `CLEAR-I-MEMORY`, `CLEAR-D-MEMORY`, the control store's and the dispatch
  memory's loops, `FILL-M-LOOP` and `FILL-A-LOOP` (`sys/ucadr/promh.text`).
- **`TRANS-DROP-THROUGH` no longer modifies the dispatch it returns to**
  (`sys/ucadr/uc-transporter.lisp:179`). It ored all ones into the dispatch's
  address through `OA-REG-LOW` in a return's slot, so that the dispatch ran
  again at entry 7777, a drop-through; on revision 15 no word changes
  another. It pops the dispatch's own address, adds one, writes it to
  `OA-REG-LOW` at `OAL-JUMP` and jumps there through `oa-low-select`: the
  dispatch's slot and then the word after it, as the drop-through did, one
  word more. `P-B-MR0-HACK` (`:631`), pushed as a return address, goes on at
  its jump to `P-B-MR0` as before.
- **A transport or write test that also returned** (`(popj-after-next
  dispatch transport ...)`, `(popj-after-next gc-write-test)`, 41 words) is a
  dispatch through a copy of its table whose drop-throughs return,
  `D-TRANSPORT-RETURN` and `D-GC-WRITE-TEST-RETURN`
  (`sys/ucadr/uc-parameters.lisp:2376`, `:2656`; `TRANSPORT-RETURN`,
  `TRANSPORT-IVC-RETURN`, `TRANSPORT-WRITE-RETURN`, `GC-WRITE-TEST-RETURN`,
  `:474`), with a `(popj)` after its slot. A drop-through there ran the slot
  and then returned through the dispatch's own popj, which the new
  `TRANS-DROP-THROUGH` cannot run again: it went on at the word after the
  slot, the next function's first word (`XEVC+3`, reached 8 times in a boot,
  ran on into `XVCL`), and the boot halted at `TRAP`. Each table entry is the
  original's but for its drop-throughs, `(p-bit r-bit)` by the table's
  constant, which are `(r-bit)`, a return after the slot, so a dispatch costs
  what it did; the `(popj)` runs only after `TRANS-DROP-THROUGH`'s jump. The
  micro-assembler refuses, on revision 15, a dispatch that pushes its own
  address and carries POPJ (`check-returning-dispatches`,
  `sys/sys/cadrlp.lisp:771`), and MIT's comments that invited one
  (`sys/ucadr/uc-parameters.lisp:399`, `:462`) say so; the map-bit check
  reads the two copies too, where a microcode defines them.
  `tools/assembler-check` holds each copy equal to its original, entry for
  entry, a drop-through made a return.
- **The WRITE-I-MEM check** (`check-write-i-mem`, `sys/sys/cadrlp.lisp:810`):
  on revision 15 the micro-assembler refuses a WRITE-I-MEM in any form but
  MIT's (`IR<9:0>` = 1647, no POPJ) or in a delay slot (after a jump or call
  with N clear, a POPJ word or a dispatch).
- **The map-after-start check** (`check-map-after-start`,
  `sys/sys/cadrlp.lisp:1433`, `start-breaches`, `:1381`): on revision 15 the
  micro-assembler refuses a word that reads the map (`MAP`, functional
  source 11, or a dispatch on map bits) where it can run in the microcycle
  right after a memory start (VMA or MD with START-READ or START-WRITE) or
  the instruction fetch's (a dispatch with `IR<24>`), and a start in a
  return's slot, whose next word is not known. Port B's lookup then never
  needs WB's walk fill, write-back or translation of the same clock. MIT's
  microcode already put a page-fault check between every start and the map
  read after it. The one start in a return's slot,
  `ADDRESS-SPACE-MAP-STORE`'s write (`sys/ucadr/uc-storage-allocation.lisp:1515`),
  now carries the `POPJ-AFTER-NEXT` itself, with a no-op as its slot: one
  word more, and a clock more each time a region is made or freed.
- **The MD-after-start check** (in the map-after-start check's pass): on
  revision 15 the micro-assembler refuses a word that writes `MD` where it
  can run right after a memory start, read, write or the instruction
  fetch's. After a read the word reads `MD` as the start found it, and an
  `MD` it writes gives way to the read's word; a write carries `MD` as its
  start's own microcycle leaves it. Either way the word would not do what it
  says. `QMLP` to `QMLP+3`, where a return that asks for the fetch lands,
  are held to both rules by name. MIT's microcode and PROM have no such word.
- **The checks' successor relation** (`oa-run-tables`,
  `sys/sys/cadrlp.lisp:1185`, shared by the OA select, map-after-start and
  MD-after-start checks) follows a transfer with a slot of its own that
  itself runs in another transfer's slot: its transfers are pending on each
  of that transfer's targets, to a fixed point. The successor sets of 31
  words grow; it hid no breach.
- **A memory's head-room** (`check-a-memory-head-room`,
  `sys/sys/cadrlp.lisp:825`, every revision): the assembly is refused unless
  A memory's variables and constants end at or below the mouse's arrays,
  which sit at fixed locations from 1600 (`MOUSE-CURSOR-PATTERN-AMEM-LOC`,
  `sys/ucadr/uc-parameters.lisp:1721`) and are written at run time. Only
  variables running into the constants were refused before, so constants
  running into the arrays would have assembled without a word, and the
  region-area map's 100 words brought them close. Microcode 2002's
  variables end at 1036 and its constants at 1550: 23 words remain below
  1600.
- **`QMDTBD` has sixteen entries** (`sys/ucadr/uc-parameters.lisp:1759`): its
  users at `QIMOVE-EXIT` and `QARYR5+10` dispatch on `%%LP-CLS-DESTINATION`,
  four bits, and entries 10-17 lay in `D-MISC-DEST`, whose landing words now
  select, so the OA select check held them entered from there. Entries 5-17
  are `ILLOP`; no destination above 4 is stored. **`QBROP1` and `QBOPT4`**
  have the same shape, `%%FEF-INIT-OPTION`, four bits, into the 8-entry
  `QBOPNP` and `QBOPTT`, and stay as MIT has them: the option holds 0-7, so
  the overrun is unreachable, and the check does not refuse it. Their words
  change only because the tables they would overrun into moved.
- **`%WRITE-INTERNAL-PROCESSOR-MEMORIES`'s control store code** (`XWIPM`,
  `sys/ucadr/uc-cadr.lisp:249`, `XWIPM-I`, `:295`) takes the halves of the
  machine's revision, MACHINE-ID's `<15:4>` read at run time: on 15, `D-HI`
  and `D-LOW` whole to `WRITE-I-MEM`, which takes the word's `<63:32>` from
  `A<31:0>` and `<31:0>` from `M<31:0>` (appendix A15b.4); below 15, `<47:24>`
  and `<23:0>` as before (`xwipm-i-14`, `:300`). The A memory and dispatch
  memory codes keep their halves.
- **Microcode 2002 for revision 14 against the generational collector's**
  (`a537ba9`), label for label (each word keyed by the nearest preceding
  label and its offset, a jump's target through its key, a dispatch by the
  entries it can read, an A source by the constant it reads): equal but at
  `XWIPM` and `XWIPM-I` (one word more, the revision's test and its two
  writes; A15b.4), `TRANS-DROP-THROUGH` and the 41 returning dispatches with
  their `(popj)`s, the dispatches whose four-bit field reads past an 8-entry
  table (`QIMOVE-EXIT`, `QARYR5+10`, `QBROP1`, `QBOPT4`),
  `ADDRESS-SPACE-MAP-STORE`'s last two words and its no-op, and alignment
  padding after `XHALT`. Revision 15's differs from revision 14's only in
  the selects.
- **Boot PROM 2002 for revision 15** reads the self-describing `.mcr`
  (appendix A15b.7; `process-section`, `sys/ucadr/promh.text:1056`): the
  format word 0x51550001, the number of sections, section 6 first holding 15,
  then sections 1-4 at most once each and in order, each header's widths,
  start and unused words checked, the padding of every item zero. Its halts:
  `ERROR-NOT-REVISION-15` (`GO`, `:278`, now 15 or more), `ERROR-MCR-FORMAT`,
  `ERROR-MICROCODE-NOT-REVISION-15`, `ERROR-SECTION-ORDER`, `ERROR-BAD-WIDTH`,
  `ERROR-NONZERO-PADDING` (`:1466` on), and, kept, `ERROR-BAD-SECTION-TYPE`,
  `ERROR-BAD-ADDRESS`, `ERROR-MICROCODE-TOO-BIG` and `ERROR-BUFFER-NOT-LOADED`
  (a symbol area other than 6000 for 2000 items, or none). The control
  store's items are written whole, word 0 to `M`, word 1 to `A`. **The
  microcode symbol area** (section 3, 6000-7777) is staged in the PDL buffer
  at 4000-5777 as A memory is at 0-1777, and copied into place at
  `DONE-LOADING` (`copy-sym-loop`, `:1261`), so the PROM's buffer stays
  physical page 3, the symbol area's page, which the PROM loads afresh: a
  warm boot keeps main memory and the PROM saves nothing (Q8), and a buffer
  on any other page would overwrite a page of the running world. The PROM's
  words run from 36000 to 37016, 527 of its 1,024.

- **The microcode's revision check follows the assembly target** (contract G3
  revision 15b, appendix A15b.1; `sys/ucadr/uc-cold-disk.lisp:75`, `:559`).
  RESET-DEVICES and PROM-ENTRY-READ halted at `MACHINE-NOT-QUUX-14` below
  revision 14 whatever the target; they now compare with the assembly's
  `UA:*HARDWARE-REVISION*`, so microcode 2002 for revision 15 halts below 15,
  as A15b.1 says (`MACHINE-NOT-QUUX-15` names the same location), and a
  revision-14 assembly is as before. muir cannot run that mix (no PROM loads
  a revision-15 `.mcr` on revision 14, and quux refuses the file), so
  `tools/assembler-check`'s `rev15` reads the assembly instead
  (`revision_checks`): every jump to `MACHINE-NOT-QUUX-14` compares with the
  signature 50525 or the revision, two of each, and the revision is 15. The
  route's revision-15 assembly before the change fails it (14 twice).

### The Lisp side

- **The microcode loader takes the control store's layout from the target
  description** (`sys/sys2/usymld.lisp`): `LOAD-MODULE` and
  `BLAST-WITH-IMAGE` (`:516`, `:631`) pass each control store word to
  `%WRITE-INTERNAL-PROCESSOR-MEMORIES` as the target's two halves
  (`control-store-word-halves`, `sys/sys/uatarget.lisp:181`): `<47:24>` and
  `<23:0>` as before, `<63:32>` and `<31:0>` at revision 15 (appendix
  A15b.4), each a fixnum through `%LOGDPB`, and refused in a world whose
  fixnum is narrower than a half. `READ-MCR-FILE` reads revision 15's
  `.mcr` (`:830`, `read-mcr-sections`, `:902`), holding its format word, its
  sections' order and widths and its padding to the target's.
- **`%%LP-CLS-ATTENTION` is documented as unused** (`sys/cold/qcom.lisp:609`):
  nothing in this tree sets or reads the call state's attention bit, `<24>`
  (no name refers to it, no Lisp code takes the byte `3001` of a call state,
  and no microcode word tests that bit; the PROM's two `(byte-field 1 30)`
  tests are of Q-R in its self-test), and revision 15 reads no call-state bit.
- **The micro-LAP loader's control store write** (`MA-LOAD-C-MEM`,
  `sys/sys/mlap.lisp:516`) passes `<63:32>` and `<31:0>` on a QUUX of
  revision 15 or later, MACHINE-ID's revision read from the feature page,
  and `<47:24>` and `<23:0>` as before elsewhere.

### The control store's writers and readers (appendix A15b.4)

| Writer or reader | What it does on revision 15 |
|---|---|
| The boot PROM, `CLEAR-I-MEMORY` and `PROCESS-I-MEM-SECTION` (`promh.text`) | `WRITE-I-MEM` of a 64-bit word: `CLEAR-I-MEMORY` writes zeros to 0-35777; the reader writes each item, `<31:0>` from M, `<63:32>` from A, the address through `oa-low-select` |
| The boot PROM, `CLEAR-D-MEMORY` and `PROCESS-D-MEM-SECTION` | the dispatch memory, 17 bits an entry, as before, the address through `oa-low-select` |
| `XWIPM`, `%WRITE-INTERNAL-PROCESSOR-MEMORIES` (`uc-cadr.lisp`) | code 1: the machine's revision's halves, on 15 `D-HI` and `D-LOW` whole; codes 2 and 4 as before; each write's address through `oa-low-select` |
| `LOAD-MODULE`, `BLAST-WITH-IMAGE` (`sys2/usymld.lisp`, the microcode loader) | the halves of the target named by `ua:*word-width*` and `ua:*hardware-revision*` (`control-store-word-halves`): set 15 to load a revision-15 machine |
| `MA-LOAD-C-MEM` (`sys/mlap.lisp`, micro-LAP; no caller loads microcompiled code on QUUX) | the halves by the machine's revision (above) |
| `READ-MCR-FILE`, `read-mcr-sections` (`usymld`) | reads revision 15's `.mcr` into an image, 64-bit control store words |
| The micro-assembler's image (`cadrlp`, `qwmcr`) | assembles and writes 64-bit words |
| `cc/` (the CADR's debugger over the debug cable: `CC-READ-C-MEM`, `CC-WRITE-C-MEM`, `lcadrd`, `cadld`, `diags`) and `memd`, `praid` | the CADR's; QUUX has no debug cable, unchanged |
| The microcode | no word reads the control store; `XWIPM-I` is the only microcode writer besides the PROM |
| The simulator's checkpoint, the console's readout, the fabric's | not Lisp or microcode: the simulator's and the fabric's own |

### The checks

- **`tools/assembler-check`**: `rev15` assembles the microcode and the PROM
  with their selects under the OA select check as it refuses, finds no
  breach, the extension holding the selects alone (129 and 30; 8 and 0), and
  each -RETURN table equal to its original but at the drop-throughs; `dual`
  assembles the tree at 14 and at 15 and holds their `<47:0>`, dispatch
  memory, A memory and symbol area equal, a change planted in one word
  caught, and its revision-14 assemblies pass the WRITE-I-MEM,
  map-after-start and MD-after-start checks too. The plants `oa-drop-low`,
  `oa-drop-high`, `oa-drop-entry`, `oa-drop-prom`, `oa-old-drop-through`,
  `oa-no-writer` and `popj-dispatch` are each refused naming the word and
  rule, and `return-table-drift`'s one drifted entry is found; `rev15` is
  their control. `write-i-mem` finds each breach of the WRITE-I-MEM check
  planted in the microcode's image, and `write-i-mem-slot` is refused.
  `map-after-start` finds each of four planted breaches, a map read reached
  through a slot's slot among them, and not their controls;
  `map-after-start-return-slot`, `ADDRESS-SPACE-MAP-STORE` as MIT wrote it,
  is refused. `md-after-start` finds each of seven planted `MD` writes, after
  reads, writes and the fetch, and not their controls.
  `a-memory-head-room` is refused; `tree` is its control. `profile` runs
  the profile pass with a hand-made profile and holds each hint, each
  predicted target, each key not found or on another class, three PDL
  address fields and the report, and `extension-breaches` finds each of
  three planted breaches of A15b.2's rules; `rev15` holds the extension by
  class. The other checks assemble the tree at 14, as before.
- **The boot and the warm boot.** On muir-sim's `micro` engine at revision
  15, the PROM loads microcode 2002 and System 2002 reaches its listener. A
  value set before a warm boot (Control-Meta-Return) reads back after it, on
  both revisions, and MA-INFO prints each microcode entry's address as the
  symbol file has it (`car`: `XCAR`), with no high bits (both measured
  before the generational collector's merge).
- **Revision 14's suites.** System 2002's band with microcode 2002 for
  revision 14 passes the microcode check and the system check on `micro` and
  `rtl`, the generational collector's checks among them
  (`generational-collector`, `-reclaim`, `-tuning`, `-rqb` at 4, 5 and 6
  ticks).
- **The PROM's clearing.** With A, M, the dispatch memory and the control
  store below 36000 filled with patterns, the PROM stopped after
  `CLEAR-D-MEMORY` leaves the control store below 36000 and the dispatch
  memory all zero, and A and M zero but at the PROM's own variables and
  constants, on both engines.
- **Coverage** (measured before the generational collector's merge). The
  microcode check and the system check, with cases for the rarer sites, the
  mouse moved and clicked, a warm boot and a disk save, run 145 of amendment
  1's 147 microcode OA sites on revision 15 (each PROM site too); the two left, `MC-DOSX+2` and `MC-SOP+3`, serve microcompiled code,
  which QUUX does not run. `TRANS-DROP-THROUGH` returned to plain transport
  and write-test dispatches (13 sites) and to the -RETURN ones (`XEVC+3`,
  `MVRB2+3`, `QRAR4+5`, `AREFI-INSTANCE-NEW+12`); `P-B-MR0-HACK` ran 1,616
  times but was always returned to plainly. Reaching it through
  `TRANS-DROP-THROUGH` takes an extra-PDL trap in the PDL buffer's dump that
  ends in `TRANS-DROP-THROUGH`, and the dump stores the pointer below the PDL
  buffer's new address, so the trap always copies the object and returns
  plainly (inferred from the code, not measured).
- **The gate on revision 15.** Step 2's gate runs on revision 15 with these
  changes to the checks:
  - `tools/system-check/cases/rev14-addresses.cases:45` reads MACHINE-ID's
    revision as 14 or later, since revision 15 keeps revision 14's address
    space and reads 15 there.
  - `eden-default`, whose case expects 32 M words' sizes, moves to
    `tools/system-check/cases-32mw/`, run only when named, as `cases-2mw/`'s
    checks are (`tools/system-check/run:26`).
  - `tools/microcode-check/generational-save:130` gives each of its session's
    forms ten times the time on rtl, where `SI:GS-SUMS` took over its 120 s
    at 2 M words.
  - C15, the warm boot, becomes a harness of its own,
    `tools/system-check/warm-boot` with `lisp/warm-boot.lisp`, which gives
    the TELNET server time to end before the warm boot and answers the
    console's "Reset it?" when the boot lands while a process runs.
  - `tools/lispm-check-test/run.sh:37` refuses `--engine rtl`: its question
    cases are bounded at 20 s of host time.

## Revision 16: the Ethernet device

QUUX's revision 16 adds the Ethernet device on the register page, words
240-257 (QUUX's Ethernet contract, sections 2 and 10). Its stack's first part
is here: the driver, the network process, ARP, IPv4 and ICMP echo, `PING`,
TCP, and TELNET and the test echo service over TCP (the contract's sections 5
and 7). Chaos stayed beside it until the checks ran over TCP (section 8, R2),
and then left the band and the microcode (step R3, below).

### The Lisp side

- **The Ethernet device's driver and the network process**
  (`sys/network/ip/ether.lisp`, new, package INTERNET). Its rings share one
  wired page, 16 transmit entries and 32 receive entries; its buffers are
  1,536 bytes, two to a wired page, so that none crosses a page
  (`ETHER-RESET`, `:200`). The reset disables the device, waits for it to be
  quiet, writes the bases and sizes, enables it with its interrupt off and
  gives every receive buffer. The network process, at priority 25, waits on a
  predicate that reads register 251 and the earliest timer and conses nothing;
  each pass takes every received frame, writes 252, gives the buffers back
  through 250 and runs the timers (`NETWORK-PASS`, `:436`;
  `ETHER-TAKE-FRAMES`, `:274`). The driver keeps a total of each of status
  241's four counters (`TYPE-FILTER-TOTAL`, `IPV4-CHECKS-TOTAL`). The network
  starts at every boot on a machine whose feature word 15 `<2>` is set and
  whose register 255 is not 0, and stops before a disk save. Its timers run
  on the processor's microsecond clock: `TIME` counts 16,384 us, and a
  second of it is 0.983 s, under the contract's 1 s less a tick.
- **ARP, IPv4, ICMP echo and `PING`** (`sys/network/ip/ipv4.lisp`, new).
  ARP replies only to a request for the band's own address, learns by RFC
  826's merge, keeps 16 entries 10 minutes from the last ARP packet from
  their address, sends at most one request a second for an address, holds
  the newest datagram waiting and drops it once the third request has gone a
  second unanswered (`ARP-RECEIVE`, `:275`; `ARP-HOLD`, `:198`;
  `ARP-TIMERS`, `:230`), and sends one gratuitous ARP as the network starts.
  IPv4 takes datagrams for the band's address, skips options, drops source
  routes, fragments and protocols other than ICMP, and counts them; it sends
  IHL 5, TTL 64 and a new identification for each datagram, on the subnet
  directly and through the gateway otherwise (`IPV4-RECEIVE`, `:380`;
  `IPV4-SEND`, `:329`). Every echo request for the band is answered.
  `(IP:PING "a.b.c.d")` sends one echo request, waits at least a second for
  the reply with its identifier and sequence, prints the round trip and
  returns them (`:462`). No checksum is computed: the device fills them in
  and checks them (section 2.4).
- **TCP** (`sys/network/ip/tcp.lisp`, new; QUUX's Ethernet contract, 5.5
  and 6): passive open only; MSS 1460 offered on the SYN-ACK, the send MSS
  min(the peer's, 1,460), 536 with none; options parsed anywhere, an illegal
  length dropping the segment; 8,192-byte buffers each way; in-order delivery
  only, every segment answered once for its batch (`TCP-BATCH-END`); sender
  silly window avoidance by MUST-38's four rules with the 200 ms override,
  receiver silly window avoidance by the effective send MSS
  (`TCP-OUTPUT`, `:400`; `TCP-WINDOW`, `:313`); RFC 6298's RTO (1 s first,
  200 ms floor, 60 s cap, doubling, Karn's rule), RFC 5681's slow start and
  congestion avoidance, back to SND.UNA with one segment after a timeout
  (`TCP-EXPIRE`, `:797`); R1 (3, then the next hop's ARP entry goes), R2 (100 s
  for data, 180 s for a SYN-ACK, each from the first sending of the oldest
  unacknowledged segment); the persist timer; RST in the window, challenge
  ACKs, MUST-63's sources refused; 8 connections and a backlog of 4; TIME-WAIT
  60 s in 64 records apart from the connections (`TCP-TIME-WAIT-SEGMENT`,
  `:765`); FIN-WAIT-2's 60 s; the urgent pointer kept; RFC 6528's ISN, the
  4 us clock and a keyed xorshift hash (`TCP-ISN`, `:264`). Sequence numbers
  are 32-bit fixnums added and compared through `%POINTER-PLUS` and
  `%POINTER-DIFFERENCE`: 10^6 additions and comparisons across the wrap cons
  0 words (measured). A connection, as ARP's resolution in `ipv4.lisp`, is an
  array read and set through substs (`TCB-STATE`, `ARP-RESOLUTION-HELD` and
  the rest): the cross build refuses a new structure, which it cannot give the
  compile for the target without changing the builder's world
  (`sys/cold/cross.lisp`, CROSS-DECLARE-DEFINITIONS).
- **TCP timestamps, for RTT measurement only** (`sys/network/ip/tcp.lisp`;
  QUUX's Ethernet contract, 5.5, amendment 4; RFC 7323). Behind 20% loss
  toward the band a 1 MiB echo from Linux did not finish in 900 s: with
  in-order delivery and no timestamps every ACK after a timeout covers
  retransmitted data, so Linux took no RTT sample and its backoff grew to
  9-13, its RTO to 120 s. A SYN with the timestamps option now makes a
  timestamped connection (`TCP-RECEIVE-CLOSED`, `:659`), whose every segment,
  a resent one and an RST too, carries TSval, a millisecond clock counted
  exactly from the network clock and its wraps as the ISN's (`TCP-CLOCK-TRACK`,
  `:261`; `TCP-TS-NOW`, `:280`), and TSecr, TS.Recent (`TCP-SEND`, `:371`;
  the option laid out by `TCP-RAW-SEND`, `:318`). TS.Recent and
  Last.ACK.sent (`TCB-TS-RECENT`, `:134`) follow RFC 7323 4.3: a TSval is
  taken when it is not older, modulo 2^32, and its segment starts at or before
  Last.ACK.sent, so a segment beyond a hole is not echoed and the one that
  fills it is (`TCP-TS-RECENT-UPDATE`, `:595`). Options give MSS and TSval
  (`TCP-OPTIONS`, `:574`, which replaces `TCP-OPTION-MSS`). On a timestamped
  connection a segment but an RST without the option is dropped silently, and
  the connection is never aborted for it (`TCP-RECEIVE-ON`, `:692`); its
  effective send MSS is 12 bytes less (`%TCP-TIMESTAMPS-LENGTH`); its
  TIME-WAIT record answers with the option and drops a segment without it but
  a SYN (`TCP-TIME-WAIT-SEGMENT`, `:844`). A SYN without the option makes a
  connection as before. No PAWS, no window scaling, no SACK; in-order
  delivery stays; the band takes no RTT sample from TSecr. A connection is
  56 words. `sys/cold/crossdefs.lisp` gains the two substs and the new
  specials.
- **No RTT sample from a SYN-ACK sent again for a duplicate SYN**
  (`sys/network/ip/tcp.lisp`, `TCB-SYNACK-RESENT`, `:140`, set at `:723`,
  read at `:749`; QUUX's Ethernet contract, 5.5; RFC 6298 section 3, Karn;
  MUST-18). A duplicate SYN in SYN-RECEIVED makes the band send its SYN-ACK
  again, with no timeout counted, so the handshake's ACK gave an RTT sample
  timed from the first SYN-ACK: a duplicate SYN 0.8 s after it made the first
  data RTO 2.4 s instead of 1 s (`karn-dup-syn`, below), and in T4's
  loss20-both row a 64 KiB echo took 75.7 s. The resend is now marked and the
  ACK gives no sample; the RTO stays the first, 1 s, with no RFC 6298 (5.7)
  and no cut of the initial window, since no timer ran out. A connection is 57
  words. `sys/cold/crossdefs.lisp` gains the subst.
- **TCP's streams, the servers and the band's own host**
  (`sys/network/ip/servers.lisp`, new; QUUX's Ethernet contract, 5.6 and 7):
  stream flavors composed as Chaos's (`chuse.lisp`), the ASCII-translating one
  over `SI:BUFFERED-TYI-TYO-STREAM`, `MAKE-TCP-STREAM` with `:R2` (MUST-21);
  a dispatch from port to server; the TELNET server on port 23, MIT's body
  (`chsaux.lisp`, the herald, the IAC flush, `CHAOS:ECHOING-STREAM` and its
  close at EOF) over a TCP stream (`TELNET-SERVER-FUNCTION`, `:143`); the
  test echo service on port 7 while `IP:*TEST-ECHO-SERVICE*` is T
  (`:186`); the functions the segment scripts' control session calls; and
  `SI:LOCAL-HOST` from the band's address, else the Chaos host, else an
  unnamed host (`:249`). A stream's errors signal `SYS:CONNECTION-LOST` and
  `SYS:HOST-STOPPED-RESPONDING` with the foreign host given.
- **Senders give the network process its turn** (`sys/network/ip/ether.lisp`,
  `NETWORK-YIELD`, `WITH-NETWORK-LOCK`): a TELNET session echoing a typed form
  one character a segment held the network lock at each clock tick, and the
  network process, at priority 25, found it held each time and took no frame
  for 120 ms, so the receive ring overflowed (measured: entries 87-126 waiting,
  then drops). The network's start is its process's first act, so that at
  boot the gratuitous ARP comes once the boot's initializations have ended.
- **A sender runs at the network process's priority while it holds the
  network lock** (`WITH-NETWORK-LOCK`, `sys/network/ip/ether.lisp:577`;
  `NETWORK-RAISE-PRIORITY`, `:517`, `NETWORK-RESTORE-PRIORITY`, `:540`,
  `NETWORK-SHIFT-ENTRY`, `:457`, `NETWORK-MOVE-ENTRY`, `:477`; QUUX's Ethernet contract, section 5.1,
  senders; M-ack). A sender at a user's priority, preempted by the clock's
  break while it held the lock, waited behind a compute-bound process of its
  own priority for that process's quantum, a second, and the network
  process, at 25, waited on the lock with it: no ACK went out for a second
  (M-ack on micro at 19 ns: one stall of about a second in each run, max
  940-1029 ms). The holder is now raised to 25, or kept at its own priority
  if that is higher, before it takes the lock, and restored after it releases
  it, at the outermost hold only, in an `UNWIND-PROTECT`; the yield comes
  after the restore. The raise and the restore move the holder's entry in
  `SI:ACTIVE-PROCESSES` themselves rather than by `:SET-PRIORITY`, whose pair
  cost 0.83 ms on micro at 19 ns, on every section: the raise puts the entry
  after every entry at 25 or above, where `:SET-PRIORITY` puts it, and the
  restore puts it back at its place before the section when the entries
  around that place still bracket its priority, and otherwise where
  `:SET-PRIORITY` would. The pair now costs 0.29 ms (10,000 pairs at the
  listener, measured).
- **A received frame wakes the network process through the device's
  interrupt, and the clock's break comes every tick only while a timer of the
  network's is due within 2 s** (section 2.6's fallback; `NETWORK-TOP-LEVEL`,
  `ETHER-ARM-INTERRUPT`, `NETWORK-CLOCK-RULE`, `NETWORK-WAKEUP-P`,
  `:613-672`). Before each wait the network process sets register 240 `<8>`;
  the microcode clears it and asks for a sequence break (above), a break that
  the scheduler no longer drops when it comes during its pass (`SGENT`,
  above). `SB-ON` does not govern this break: the arming is its gate. The network
  no longer asks for the break every tick while it is up, which cost an idle
  band 12-13% on micro at 19 ns: its wait predicate also wakes it once a
  timer of its own is due within 2 s while the break is slower, and it asks
  for the break every tick until no timer is due within 2 s. Idle, the
  loop of M-ack's idle check is now 0.01-0.08% slower with the network up
  than with it stopped, on micro at 19 and 48 ns and on rtl at 19 ns.
- **A broadcast goes to the Ethernet broadcast address** (`IPV4-SEND`): a
  datagram to the subnet's broadcast, or to 255.255.255.255, is sent with no
  ARP.
- **The clock's rate has one owner** (`sys/sys2/gc.lisp:150`,
  `REQUEST-CLOCK-RATE`). GC-ON wrote 6 into `%TV-CLOCK-RATE` and GC-OFF 60,
  so GC-OFF would undo the network's rate of every tick (section 2.6). Each
  user now asks for a rate by name, GC-ON and GC-OFF among them (`:1130`,
  `:1159`), and the meter holds the smallest asked for, or 60.
- **The INTERNET system** (`sys/sys/sysdcl.lisp`), a component of SYSTEM
  after CHAOS, compiles and loads the four files.
- **`sys/cold/crossdefs.lisp`** lists the four files' compile-time definitions
  and specials, and `SI:CLOCK-RATE-REQUESTS`.
- **An error in a TELNET session while it holds the network lock aborts that
  session, not the stack** (`TELNET-SESSION-LOCK-ERROR` and
  `TELNET-SERVER-FUNCTION`, `sys/network/ip/servers.lisp:184`, `:200`). An
  error signalled in the session's send path inside `WITH-NETWORK-LOCK` (as
  a reload whose files did not match the running stack's structures raised:
  a subscript out of range in `TCP-SEND`) entered the debugger on the
  session's own TCP stream, whose output signalled it again, 12 to 96 levels
  deep, and kept `NETWORK-LOCK`: the network process blocked on it at the
  next frame (`NETWORK-PASS`), so the whole stack was dead and new
  connections found no route. A handler in the session now throws such an
  error out of it, which unwinds the lock; the connection is closed with
  abort, the error recorded in `TELNET-SERVER-LAST-ERROR` and a notice sent
  to the console (`TV:NOTIFY`). An error with the lock free, or a network
  error, takes its old path. `tools/tcp-check`'s new parts `lockerror` and
  `lockerror-lisp` plant a microcode and a Lisp error there: on a band built
  before it the first fails before the change (the session in the debugger, the
  control session never answering again), both pass with it, and a partial
  fix that frees the lock but leaves the session in the debugger fails.
- **A killed TELNET session no longer leaks its connection.** A session's
  process killed with `(send p :kill)`, in `READ-LINE`, in the debugger or
  holding `NETWORK-LOCK`, left its connection `ESTABLISHED`, and once the
  band's 8 connections were used port 23 refused. Two faults, two changes.
  The server dispatch now runs every server inside an `UNWIND-PROTECT` that
  closes its connection with abort (`TCP-SERVER-RUN` and `TCP-SERVER-START`,
  `sys/network/ip/servers.lisp:142`, `:148`), the layer at which the chaos
  servers close (`WITH-OPEN-STREAM`, `sys/network/chaos/chsaux.lisp:1246`):
  the TELNET server's own abort close was not in one, and the test echo
  server has none; after a server's own close `TCP-CLOSE` sends nothing.
  And a kill of a process that runs in another stack group than its initial
  one unwinds the initial one too, as a reset does, and dies there
  (`(PROCESS :RESET)`, `sys/sys2/proces.lisp:217`): MIT's kill restarted
  that other stack group, the error handler's for a process in the
  debugger, in `PROCESS-KILL-TOP-LEVEL`, so none of the initial one's
  `UNWIND-PROTECT`s ran. For the current process the stack group it runs in
  is taken from `%CURRENT-STACK-GROUP`, not from its `STACK-GROUP` slot,
  which only the scheduler sets: after a return to the initial stack group
  that did not pass through the scheduler (Resume in the debugger, a
  reset's unwind, a coroutine's return) the slot is stale, and a kill
  judged by it unwinds the stack group it runs in and halts the machine
  (HALT-CONS). `tools/tcp-check`'s new part `kill` (`kill.py`) kills
  sessions in `READ-LINE` (K1), in the debugger (K2), under the network
  lock (K7), the test echo server (E1) and a session killing itself at the
  debugger (S1), with a clean close as a control (C2); `tools/system-check`
  gains `process-kill-debugger`, `process-kill-stale-slot`,
  `process-reset-debugger`, `process-debugger-abort`,
  `process-debugger-proceed` and `warm-boot-debugger`. Before the change
  every kill case but C2 fails and `process-kill-debugger` passes 9 of 14;
  with the dispatch's close alone K2 and `process-kill-debugger` still fail;
  with both, all pass; a kill judged by the slot alone halts the machine in
  S1, `process-kill-stale-slot`, `process-reset-debugger`,
  `process-debugger-proceed` and `warm-boot-debugger`.
- **Chaos leaves QUUX's band** (QUUX's Ethernet contract, section 8, step R3).
  The NCP and its services are no longer loaded; their files stay in the tree,
  their loading commented out in place. The CHAOS system, CONVERSE (SEND over
  Chaos), SUPDUP (the SUPDUP and TELNET clients), band transfer
  (`sys/sys2/band.lisp`), the QFILE client and PEEK's Chaos and QFILE panes
  leave SYSTEM, and CHSNCP, CHUSE and QFILE the cold load's MINI list
  (`sys/sys/sysdcl.lisp`). Moved first, out of `chsaux.lisp`, to files
  independent of the protocol: the TELNET server's body, ECHOING-STREAM and
  TELNET-SERVER-EOF (`sys/network/telnet.lisp`, new, in SI;
  `SI:TELNET-SERVER-BODY`, `:14`), which TCP's TELNET server now calls
  (`sys/network/ip/servers.lisp:171`); the host table's parser and compiler
  (`sys/network/host.lisp:567`, in SI, so `SYS: SITE; HSTTBL` is compiled and
  loaded in SI, not CHAOS; `sys/sys2/maksys.lisp`'s `:GENERATE-HOST-TABLE`);
  `REMOTE-NETWORK-ERROR`'s host, now the one the signaller passes, as TCP's
  streams do (`sys/eh/ehf.lisp:1364`); and `SI:LOCAL-HOST`, which the NCP set
  from the Chaos address (the machine's name now has its own bullet, below).
  The site's associated machine is FILES for a machine LMLOCS does not name
  too (`site/site.lisp`, `:DEFAULT-ASSOCIATED-MACHINE`). Chaos's uses elsewhere are commented out
  in place: the remote disk and `PRINT-AVAILABLE-BANDS`' Lisp machines
  (`sys/io/disk.lisp`), PEEK's Active Servers mode and its SUPDUP, TELNET
  and QSEND commands (`sys/window/peek.lisp`), the who-line's Chaos servers
  (`sys/window/wholin.lisp`), Terminal F and H and System C, S and T
  (`sys/window/basstr.lisp`), the window menu's Supdup and Telnet
  (`sys/window/sysmen.lisp`), the HOSTS and LISPM alarms
  (`sys/demo/alarm.lisp`), the birthday time spec, which fingered over Chaos
  (`sys/io1/timpar.lisp`), the spelling server (`sys/zwei/ispell.lisp`), the
  NCP's reset at a disk save (`sys/sys/qmisc.lisp`), at a screen change
  (`sys/window/shwarm.lisp`) and its servers' switch at boot
  (`sys/sys/ltop.lisp`), `CHAOS-BUFFER-AREA` in the incremental save
  (`sys/io1/inc.lisp`), FINGER's cache at login (`sys/io/file/access.lisp`),
  the network's unknown hosts in `FS:GET-PATHNAME-HOST`
  (`sys/io/file/pathnm.lisp`), the site's integrity check of the Chaos
  address and a host's `:CONNECT` (`sys/network/host.lisp`), and `:CHAOS` in
  `*FEATURES*`. The three system communication slots of the Chaos lists are
  reserved, never reused (`%SYS-COM-RESERVED-1` to `-3`,
  `sys/cold/qcom.lisp:247`; the cold load writes them NIL,
  `sys/cold/coldut.lisp:1534`). On a machine with no Ethernet device
  (revision 15) the band has no network and says so once at each boot
  (`NETWORK-BOOT-START`, `sys/network/ip/ether.lisp:712`). OZ, the site's
  Chaos file, time and host-table server, is no longer named
  (`site/site.lisp`), as nothing could reach it. The unloaded Chaos files
  carry a line saying so. `sys/cold/crossdefs.lisp` adds
  `SI:LOCAL-HOST-FUNCTIONS`.
- **The machine's name** (QUUX's Ethernet contract, section 5.6, "From
  R3"; `SI:FIND-LOCAL-HOST`, `sys/network/host.lisp`). With the NCP gone the
  Chaos address names no machine. At every cold boot, on revisions 15 and 16
  alike, the name is taken from the first that gives one: the name file,
  `SYS: SITE; HOSTNAME` (`site/hostname` under the file device's root, one
  line, as Unix's `/etc/hostname`); the name `(si:set-host-name "name")` gave
  the running band, which a `DISK-SAVE` keeps (`sys/network/host.lisp`;
  `SI:SET-PACK-NAME`, with which MIT's Lambda named a machine that had no
  Chaos address, still refuses and names `SI:SET-HOST-NAME`, as the GPT has
  no pack name); the site table's host whose INTERNET
  address is register 255's, on revision 16 (`INTERNET-LOCAL-HOST`,
  `sys/network/ip/servers.lisp`); else LOCALHOST, a new entry of the site
  table (`site/hosts.text`, its address the host table's form only: the band
  has no loopback) with an LMLOCS row, "localhost", associated machine FILES
  (`site/lmlocs.lisp`). The name file is read at the cold boot only;
  `SI:SET-HOST-NAME` sets the current name, naming the running machine at
  once over the name file's name too, and with NIL drops the name given,
  the machine taking what the order gives without it. A name the site
  table lacks makes a host of that name with no address. `SI:LOCAL-HOST-NAME`, the pretty name and the
  associated machine follow from the host: the cold initialization of
  `SET-LOCAL-HOST-VARIABLES` finds the host first, and the internet's start
  and `SET-HOST-NAME` set them after it (a separate "Local host"
  initialization with `:first` had run after it, `:first` meaning "run now",
  so the names were the saved band's). `docs/building.md`, "Naming a
  machine", says how. `tools/system-check`'s new `machine-name` boots the
  band at the console (revision 15 has no network for a session) with no
  name file, with one (and `SET-HOST-NAME` over it, then NIL), after
  `SET-HOST-NAME` and a save, with both, and on
  16 with a matching INTERNET entry; `local-host` checks that
  `SI:LOCAL-HOST-NAME` is the host's name over TCP.
- **A band on revision 16 whose Ethernet device has no address says so once
  at each boot** (`NETWORK-BOOT-START`, `sys/network/ip/ether.lisp:718`),
  where it would have started the network: "its Ethernet device has no IPv4
  address (word 255 is 0)". Before, it said nothing.

### The checks

- **`tools/microcode-check`'s `network-stray` runs on revision 15 alone**
  (QUUX's Ethernet contract, section 8, step R4): R4 took the Chaosnet
  interface from revision 16, whose words 140-157 are reserved and whose
  word 100 `<6>` is never set, so on 16 the check's CSR reads 0 and its 6
  cases failed. It moves to `cases-15/` (`cases-15/network-stray.cases`),
  run only when named as `cases-2mw/`'s and `cases-16/`'s are, and `run`
  skips a check of `cases-15/` on another revision in one line, asking the
  `--quux` machine its revision as lispm-check does
  (`tools/microcode-check/run:42-56`). On revision 15 it passes 6 of 6 and
  its planted control fails 3 as before; the stray it checks,
  `INTR-NETWORK-STRAY`, is still reachable there.
- **`tools/segment-check`**: the control forms name the stack's functions
  and variables (`scripts.py`, `CONTROL`); the pass latency is 7 ms, from the
  band's measured timers (`PASS_LATENCY`; `README.md`); `ping` also pings the
  subnet's broadcast, which must go to the Ethernet broadcast address with no
  ARP request, and the stand-in's plant `broadcast-ping-arp` fails it; `wrap`
  also echoes 64 KB across 2^31, where sequence numbers held signed and
  compared plainly go wrong (the stand-in's `seq-signed-no-wrap`, and the
  band's own plant, which passed the 2^32 wrap alone); `close` also checks
  that the test echo service closes with FIN at the peer's EOF. The band's 27
  planted faults, each failing its script, are in `README.md`, "The band's
  plants".
- **`tools/system-check/cases/network-lock-ceiling.cases`** (new, with
  `lisp/network-lock-ceiling.lisp`): the ceiling's priorities inside and after
  a section, nested holds, a throw and an error out of one, a process above the
  ceiling; the order of `SI:ACTIVE-PROCESSES` and the holder's place in it
  inside and after a section, and a section that moves its own entry; 3 of the
  first 8 fail without the change; of all 11, 5 fail with a ceiling that never
  restores and 2 with one that sets the priority but never moves the entry
  (`tools/system-check/README.md`).
- **`tools/system-check/cases/sb-deferral.cases`** (new, with
  `lisp/sb-deferral.lisp`): a clock break deferred in the scheduler's pass,
  with a compute process to resume, brings the next pass within 100 ms:
  6-13 ms on micro at 19 ns with the deferred break the machine's, about
  1,005 ms with MIT's `SGENT` (microcode `dc031be9`), in all three trials; a
  coroutine called inside a `WITHOUT-INTERRUPTS` after a break was deferred
  there takes the break, the caller's bit 0 after the return (1 with MIT's).
  MIT's `SGENT` fails 2 of its 5 cases (`tools/system-check/README.md`).
- **`tools/system-check/cases/generational-tuning.cases`**: the clock's rate
  after GC-ON and GC-OFF is the smallest any user asks for, 6 and 60 unless the
  network asks for every tick, as it does while a timer of its own is due
  within 2 s (`:45`, `:69`).
- **`tools/lispm-check` takes a tap on revision 16, and `--network tcp`**
  (QUUX's Ethernet contract, sections 3, 7 and 8 R1; `docs/lispm-check.md`,
  "The network"). On revision 16 every run takes a host-only tap of the pool
  through the fault relay, `LISPM_CHECK_TAPS` its range (`tap_range`,
  `tools/lispm-check:427`; `TapLink`, `:476`), the indexes that have a
  checkpoint for the key first (`:1596`), and gives the machine the tap's
  `--ethernet-socket`, `--ip-address` and `--ip-gateway` at the setup and at
  every resume (`:521`). A checkpoint is made for each tap index, its key
  naming QUUX's address behind the tap and its setup version 3
  (`SETUP_VERSION_TAP`, `:938`); revision 15's and the CADR's keys are as
  before. The revision is asked of the machine once a build
  (`machine_revision`, `:536`). `--network tcp` carries the session over the
  build host's own TCP from a socket bound to the tap to the band's TELNET
  server, with no Chaos cable and no ozd (`NETWORKS`, `:615`; `_open`,
  `:707`), and closes the setup's session cleanly, to the band's EOF, so that
  the checkpoint holds no connection (`close_session`, `:778`);
  `--chaos-address` is given in both networks, so one checkpoint serves both.
  `options` and `prepare` (`:1473`, `:1545`) split the command line and the
  setup from `main`. Its self-test, `tools/lispm-check-test/network.sh`, is
  new.
- **`tools/fault-relay/relay`** (new; its README): the Ethernet frame mover
  with counts and its own check of every Ethernet frame the band sends
  (`check_frame`, `:215`), which takes host-only taps only; and T4's faults,
  seeded: loss, duplicates, reordering, a byte changed inside the IPv4
  datagram toward the band, jitter, each direction or both, frames of other
  types injected toward the band, held until SIGUSR2 with `--arm-on-signal`
  (`Faults`, `:287`), and each direction's TCP resends counted (`:390`).
  `tools/fault-relay/test` (new) checks the faults with no tap and no band.
  `tools/lispm-check` passes it `LISPM_CHECK_RELAY_FLAGS` (`:493`).
- **`tools/tcp-check/run`** (new; its README): T2, Linux's own TCP to the band
  through the relay and a tap: TELNET sessions, the test echo service at 1 B
  to 1 MiB by sha256, 1,000 connections in a row, 8 at once and a ninth
  refused (`part_telnet` to `part_limit`, `:218`-`:273`); M-tap's stall
  test, by name (`part_stall`, `:311`); and T4's parts, by name, the
  connection table empty after (`part_table`, `:364`) and the band's totals
  of 241 `<15:9>` and `<7:4>` equal to the frames the relay corrupted and
  injected (`part_totals`, `:391`), with `--faults` (`:431`).
- **T1's Timestamps group** (`tools/segment-check/scripts.py`, `ts_open` to
  `ts_missing`, `:2398`-`:2582`; its README; QUUX's Ethernet contract, 9,
  amendment 4): `ts-negotiation`, `ts-echo`, `ts-mss` and `ts-missing`. What
  every script checks holds the timestamps option to its connection, keyed
  by the four-tuple of the peer's latest SYN (`Session.ts_problem`,
  `tools/segment-check/session.py:136`): on a SYN-ACK only if the SYN offered
  it, then on every segment but an RST, a resent one and a TIME-WAIT record's
  answer too, none without it, and TSval never going back; and the peer's side
  answers a timestamped connection as Linux does (`PeerConn`, `:244`).
  `check.py` takes a timestamps option of length 10. The stand-in band has the
  timestamps and fourteen plants of them (`tools/segment-check/standin.py`,
  `ts_update`, `:1063`), and `test` checks the option's parsing. No script
  before the group changed its expectations; `handshake`, whose SYN is
  Linux's, now makes a timestamped connection on the band.
- **`karn-dup-syn`** (`tools/segment-check/scripts.py`, `karn_dup_syn`,
  `:2655`; its README): after a control connection whose first data RTO is the
  200 ms floor, a duplicate SYN 0.8 s after the first SYN-ACK, answered
  before the band's timer, then the handshake's ACK: the first data RTO is
  1 s within a tick. The stand-in samples only from a SYN-ACK sent once
  (`tools/segment-check/standin.py:964`), and its plants
  `karn-synack-resample` and `karn-synack-retry` (`:182`, `:184`) fail the
  script at 2.4 s and at 3 s.
- **T4's table part waits for the table to empty** (`tools/tcp-check/run`,
  `part_table`, `:450`; `TABLE_WAIT`, `:446`): the band's connections are
  counted once a second until only the control session's is left, for at most
  120 s, above R2's 100 s, and the line gives the wait and, on a failure, each
  connection left by remote port and state. One count right after the echo
  part failed loss20-both on seed 1 on a connection rightly in LAST-ACK,
  whose last ACK the relay had lost and which the band closed 3.3 s later.
- **T4's bound at 20% loss and its endings clause** (`tools/tcp-check/run`;
  its README, "The wall bound"; QUUX's Ethernet contract, section 9, T4): at
  20% loss the floor is T0 + 120 s, M staying 14 (`WALL_FLOOR_HIGH`, `:531`;
  `wall_floor`, `:727`; `judge_session`, `:733`); below it the bound stays
  max(10 x T0, T0 + 60 s). On a correct stack a 64 KiB echo at 20% loss took
  up to 93.8 s counted, from Linux's own RTO and backoff, against 61.4 s; a
  band whose backoff an ACK never clears still fails, at 132.7 s to 900 s. An
  early ending is now judged in the 100 s up to the ending sender's last
  transmission of its oldest unacknowledged segment, an ACK counting only up
  to that transmission's next RTO, twice the gap before it and at most 120 s
  (`Way.ending_explained`, `:658`; `ENDING_RTO_MAX`, `:524`): the band's R2
  is silent, and Linux heard of one 420 s later through a zero-window probe
  answered by RST, after an ACK of the band's segment had reached it too
  late, so the record's last 100 s held nothing to explain it. The bound's
  conditions are stated: micro at 20 ns, unpaced, one wall-clocked run at a
  time, since the band's timers run on machine time and Linux's on the
  host's. `tools/tcp-check/test` (new) checks the judge on made-up records.
- **`tools/fault-relay/relay --trace FILE`**: a line for every frame at its
  arrival (`in`, `LOST`) and its sending (`out`), with TCP's ports, flags,
  numbers and length (`Trace`, `:402`).
- **T4's wall bound and M-loss in `tools/tcp-check/run`** (its README, "The
  wall bound", "M-loss"; QUUX's Ethernet contract, 9 and 15, amendment 4):
  every echo session judged against max(M x T0, T0 + 60 s), M 10 and at 20%
  loss `--wall-m-high`, T0 from a run with no faults (`--wall-base-out`),
  runs of four or more failed transmissions of one segment not counted, and
  at 20% loss an early ending passes when the relay's trace explains it
  (`Way`, `:515`; `judge_session`, `:627`; `wall_judge`, `:655`); the echo
  part keeps every session and what it read (`Band.echo_session`, `:148`);
  `--parts mloss`, one 1 MiB echo with Linux's backoff read by `ss -tnio`
  every 2 s (`part_mloss`, `:722`).
- **`tools/segment-check/measure`** (new; `tools/segment-check/README.md`,
  "The measurements"): section 15's M-refill (`m_refill`, `:110`; the boards,
  `BOARDS`, `:56`) and M-ack (`m_ack`, `:183`) on the clocked socket.
- **`tools/gtcp/run`** (new; its README): the gate G-TCP (QUUX's Ethernet
  contract, section 8 R2). Each unit of a units file (`read_units`,
  `tools/gtcp/run:100`), a lispm-check case file or a check of system-check,
  microcode-check or assembler-check with its own flags, runs over Chaos, TCP
  and Chaos again on one tap, resuming that index's checkpoint (`run_unit`,
  `:181`), and with `--faulty` once more over TCP through the fault relay.
  Each verdict line is a case (`cases_of`, `:140`), and its pass/fail is
  compared (`judge`, `:158`): the two Chaos runs differing make it flaky,
  listed and not gated; the TCP run alone differing makes it a difference,
  gated; a case failing in every run is said (`report`, `:220`). `--compare`
  lists the cases two soak runs differ on (`compare`, `:255`).
  `tools/gtcp/test` (new) checks it on stand-in suites.
- **TCP is the default network on revision 16** (QUUX's Ethernet contract,
  section 8 R2, the switch; `docs/lispm-check.md`, "The network"). A
  `tools/lispm-check` run that names no network, by `--network` or
  `LISPM_CHECK_NETWORK`, goes over TCP on revision 16 and over Chaos on
  revisions 13-15 and the CADR (`default_network`, `resolve_network`,
  `tools/lispm-check:593`, `:598`; the flag's default, `:1587`; `prepare`,
  `:1646`), so a check on revision 16 starts no ozd; before, every run's
  default was Chaos. A band without the network on revision 16 wants
  `--network chaos`, as microcode-check's `ethernet-stray` now names it
  (`tools/microcode-check/README.md`). The tools that build their own
  sessions take the network and the tap through the new helper
  `harness_network` (`tools/lispm-check:609`): `tools/system-check/warm-boot`
  (`:70`; over TCP the session before the warm boot closes cleanly, `:189`)
  and `tools/cross-build/run`'s sessions (`Run.session`, `:272`), and with
  them `tools/microcode-check/generational-save`. A save gives no answer
  over either network, and a refused one neither (the save is judged by its
  partition); over TCP the band's network stops as the save begins, so the
  silence is waited for 120 s rather than 600 (`:312`). The route's
  machine runs at revision 16 and the microcode and PROM are assembled for
  15, which 16 runs (`MACHINE_REVISION`, `ASM_TARGET`,
  `tools/cross-build/run:72`; one revision, 14, was both): its QLD boots,
  its sessions and its lispm-check runs are on 16, over TCP with no ozd. The
  builder stays at its own band's revision over Chaos. The self-tests:
  `tools/lispm-check-test/network.sh` gains the default's cases (`default`,
  `variable`, `rev15-default`, `cadr-default`),
  `tools/lispm-check-test/harnesses.sh` (new) checks the two harnesses on
  revisions 16 and 15, and `tools/cross-build/test` (new) checks the route's
  and the builder's revisions and networks with a stand-in quux and ozd.
- **cross-build's guards for revision 15** (contract G3 revision 15b,
  appendix A15b.1; `run_all_15`, `tools/cross-build/guards.py:382`). With the
  route's microcode and PROM assembled for revision 15, A14.13's guards
  stopped at once (the microcode does not open with section 6), and their
  controls would boot revision 15's PROM on revision 14, which quux refuses.
  `run_all` (`:163`) now chooses by the assembled `ucadr.mcr`: A15b.1's for
  revision 15's, A14.13's (`run_all_14`, `:177`) for revision 14's. A15b.1's:
  quux refuses PROM 2002 for revision 15 on revisions 14 and 13, and the old
  PROMs on 15, naming format and revision (`refused`, `:367`); a revision-14
  disk on 15 halts at `ERROR-MCR-FORMAT`, the route's disk on 14 at
  `ERROR-MICROCODE-NOT-REVISION-14` and on 13 at `ERROR-BAD-SECTION-TYPE`,
  its microcode with section 6 saying 14 at
  `ERROR-MICROCODE-NOT-REVISION-15`; C27's band formats under the route's
  microcode on 15 and revision 14's on 14; the route's disk runs on revision
  16; a checkpoint of 14 is refused on 15 and one of 15 on 14. Each halt has
  its control, which runs past it.
- **lispm-check asks the machine's revision with no engine named**
  (`machine_revision`, `tools/lispm-check:544`). It was asked with `--micro`,
  which quux refuses for rtl's own flags (`--memory-timing`, `--cache`), so
  a run through a wrapper that gives them, as the soak's rtl lanes do,
  failed before it began, and on revision 16 could not take TCP, the
  default. quux's own engine is rtl, and only rtl has flags of its own; the
  asking takes about 4 ms. `tools/lispm-check-test/network.sh`'s new case
  `rtl-flags` fails without the change.
- **Chaos's own checks leave with it** (QUUX's Ethernet contract, section 8,
  step R3). `tools/microcode-check`'s `chaos-transmit-order` is retired with
  `uc-chaos`. Its new `network-stray` (with `lisp/network-stray.lisp`)
  enables the Chaosnet interface's transmit interrupt with the transmitter
  idle, which requests at once, and the stray must leave the CSR's enables 0
  and word 100 `<6>` down; the receive enable alone, with nothing received,
  is the control. `tools/system-check`'s `generational-table-users` P5 was
  `PRINT-INT-PKT-STATUS`'s walk of `CHAOS-BUFFER-AREA`; it is now
  `RESET-TEMPORARY-AREA`'s reset to a table region's end, in a scratch area
  and in the compiler's temporary area, each reset then refilled with 40
  buffers walked from the table's end; its plant, `-plant-reset.lisp` (MIT's
  reset to 0), fails the scratch area's reset, and the refill after it, over
  the table, leaves the machine with no answer; `-plant-chaos.lisp` is gone.
  The new `chaos-census` (with `lisp/chaos-census.lisp`) is the step's
  census: no file of Chaos loaded and no `CHAOS:` symbol in any FEF found by
  walking every structure region, nor in the initialization lists' forms; on
  a band from before the step it finds 9 files, 3,525 (FEF, symbol) pairs
  over 14,670 FEFs and 22 initializations.
- **`tools/lispm-check --network files`** (QUUX's Ethernet contract, section
  18, Q-N13 (a); `docs/lispm-check.md`, "`--network files`"): a third network,
  for a band checked without its network, on revision 15, whose band has no
  Chaos and no Ethernet device since R3, and on 16 with no tap
  (`tools/lispm-check:746`). The session goes through request and answer
  files in the login's home on the file device's host: `FileSession`
  (`:1310`) writes `hc-K.req` and reads `hc-K.ans` once `hc-K.done` is there;
  HC-SERVE (`tools/lispm-check-lisp/hc-serve.lisp`, new), a loop at the
  band's listener, runs each request through the tool's own helper and holds
  no file open between its polls. The setup (`setup_files`, `:1557`) lays the
  helper and HC-SERVE out as the login's init file (`:1037`), types
  `(login "LISPM")` and `(hc-serve)` at the console through muir-sim's glass
  TTY once the machine has run 20 million microcycles (`:1465-1474`), waits
  for `hc-ready.txt`, and takes the checkpoint at the machine's prompt while
  HC-SERVE waits (`take_checkpoint`, `:1521`): a refusal for a command
  queued is taken again, up to 20 times (`:1482`), and one for a handle open
  fails the setup. A check resumes it and types nothing, its first request
  the one the setup's JSON names (`:1742`, `:1778`). Its key ends `-files-`
  and HC-SERVE's sha256 (`:2115`); no tap is taken (`:2098`); the CADR
  (`:655`), `--file-server ozd` (`:2086`), the tools that take their network
  through `harness_network` (`:683`) and `tools/tcp-check/run` (`:1131`)
  refuse it. Its self-test is `tools/lispm-check-test/files.sh` (new, with
  `files.cases`, `expected-files.txt` and the plant `hc-serve-held.lisp`),
  which `network.sh` runs last: revision 15 and 16 on micro and 15 on rtl,
  each with the 11 verdicts of `files.cases`, and the plants, an HC-SERVE
  holding a file open (the setup must fail) and a session that reads the
  answer before `.done` (`files.cases`'s `early-answer` must catch it). Of
  three mutants of the tool, a retry on a handle open, a tap taken under
  `files` and the requests numbered from 1 in a check, each fails a lane;
  the tool before the change fails all 8 lanes run on it (the rtl lane
  skipped).
