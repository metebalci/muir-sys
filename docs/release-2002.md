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
  (`CROSS-FOREIGN-FILE-P`, `sys/cold/cross.lisp:634`) (`tools/cross-check/run`,
  `crossdefs.py`, `check3.py`, `cases/native.cases`; `sys/cold/crossdefs.lisp`
  against System 2001's tree).
- **A flip no longer walks each old region's pages to remap them**
  (contract G3 revision 14, 9.4): DEALLOCATE-END-OF-REGION
  (`sys/sys2/gc.lisp:888`) called INVALIDATE-REGION-MAPPING, a
  `%CHANGE-PAGE-STATUS` of every page of the region, which rewrote each entry
  unchanged on revision 14, where the flip's UPDATE-REGION-PHT writes the
  entries; measured on micro at 32 M words, its share of a flip's pause went
  from 157-217 ms to 74-85 ms (`:910`).
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
  scavenges at most `PAGE-SIZE`, 1,024, of them while the **backlog
  (proposed term)**, `A-CONS-WORK-DONE` less `A-SCAV-WORK-DONE` with this
  cons's 4n counted, is at most the **backlog limit (proposed term)**,
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
  add up to the backlog limit (proposed term) over K, 262,144 words, to the
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
only through the OA selects. This part is the micro-assembler's and the
loader's; the microcode's selects and the boot PROM's new reader follow.

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
  `<60>` and `<61>` (`sys/sys/cadsym.lisp:522`), are revision 15's names,
  refused below it (`sys/sys/cadrlp.lisp:305`); revision 14's names are
  marked with their revision, 14, and so are taken at 15 (`:300`).
- **The OA select check** (appendix A15b.15; `check-oa-selects`,
  `sys/sys/cadrlp.lisp:1201`, `oa-select-breaches`, `:1099`) runs over the
  assembled I-MEM and D-MEM of every revision-15 assembly, the microcode's
  (`:751`) and the PROM's (`:1292`), and refuses: a word that writes
  `OA-REG-LOW` or `OA-REG-HIGH` unless every word that can run next selects
  it (a write in a return's slot is refused); a selecting word that can be
  entered other than right after such a write, at a return point or at an
  entry point; and two selects on a word, a select with the PDL address
  field, `oa-low-select` with the hint, `oa-high-select` on a dispatch, and
  `oa-low-select` on a dispatch other than a dispatch-memory write without
  POPJ. It follows the delay slot and N: after a jump with N its slot runs only
  when the jump is not taken, and a dispatch's slot follows each entry's N.
  Each breach is printed with the word and the rule. The sources' microcode,
  with no selects yet, is refused at revision 15 at each of its 147 writes
  and the PROM at its 8; `ua:*oa-select-check-refuses*` nil (`:971`) writes
  the files all the same, for measuring only.
- **`tools/assembler-check`** gains `rev15`, `oa-refused` and `oa-select`
  (its README), with the fixture `lisp/oasel.lisp`; **`tools/cross-build`**
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
