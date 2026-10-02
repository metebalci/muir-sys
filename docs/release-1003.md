# System 1003

What the CADR's next release changes from System 1002. It is in progress on
the `cadr` branch: each change is recorded here as it is made. `main` is
QUUX's system, numbered from 2000; what this branch takes from it is a bug fix,
a change that needs no QUUX hardware, or a feature Mete chose for the CADR.
Every change to a source file carries a comment in that file saying why.

- **The system number is 1003** (`patch/system.patch-directory`,
  `patch/system-1003.patch-directory`), now that System 1002 is released,
  so that no band built from this branch calls itself 1002. The microcode
  stays 1000 and moves to 1001 only when a changed microcode is next
  released.
- **A compiled `(gcd n)` or `(\\ n)` with one argument works** (`convert-\\`,
  `sys/sys/qcopt.lisp:320-334`). The optimizer built `(internal-\\ n nil)`
  from it, so the call signalled that `NIL` was of the wrong type; with fewer
  than two arguments it now leaves the form alone, and the call goes to the
  function `\\`. Two or more arguments compile as before.
- **`tools/release-scan` finds a private address that ends a sentence**
  (`tools/release-scan:116-119`). Its IPv4 pattern refused a match followed by
  any dot, so the full stop after an address hid it; it now refuses only a
  digit or a dot followed by a digit, as muir-website's public-content check
  does. `tools/release-test` plants such an address in a Lisp file, case (e)
  (`tools/release-test:23-24`, `:69`, `:216-220`), and it fails with the one
  FAIL line it planted.
- **The microcode changes, and keeps the number 1000 until it is released**
  (it becomes 1001 then). It is microcode 1000 with the four fixes below,
  assembled from `sys/ucadr/` as `docs/building.md` describes; the same
  sources without them assemble to System 1002's `ucadr.mcr`, `.tbl`,
  `.locs` and `.sym` byte for byte. The fixes change seven control-store
  words and add six: one before `FREE-REGION-1`, one before
  `UPDATE-REGION-PHT-0` and four after `GCDBB-LONG`, so every word from
  `FREE-REGION-1` on is one location later, from `UPDATE-REGION-PHT-0` on
  two and from `GCDBB-NO-LUCK` on six; every other word, every dispatch
  entry and every symbol is the same once moved, but for the new label
  `FREE-REGION-2`, and 26 A-memory words that hold control-store addresses
  move with them. Its outputs are given with the cold boot's changes for
  60 boards below, which change it again. `ucadr.sym` is not given: it
  holds the same symbols in the order of a hash table, which differs with
  the band that assembles it. These sources gave one file on System 1001's
  band and another on System 1002's, the same lines once sorted.
- **`GCD` of two bignums is never negative.** When the shorter of two
  bignums of two or more words divides the longer, `GCDBB-LONG` returned the
  divisor with its sign, so `(gcd (expt 2 90) (- (expt 2 31)))` gave
  -2147483648, and `LCM`, compiled `GCD` and `SYS:INTERNAL-\\` with it. It
  now calls `UN-CONS` and returns the divisor through `BIGNUM-ABS`, as
  `GCD-IS-ABS-M-B` does (`ucadr/uc-hacks.lisp:543-559`). MIT's. Of 82 cases
  (every mix of signs over fixnums and bignums, remainders zero and not,
  interpreted and compiled, `LCM` and `//`), 14 failed on microcode 1000 as
  released and all pass with the fix, micro and rtl engines alike; the
  one-argument cases of the compiled `(gcd n)` fix above pass on both, and
  microcode 1000's own checks (the smoke, `%DRAW-RECTANGLE`, division and
  proceed cases) pass with it.
- **A stack group whose saved registers hold a forwarding word resumes.**
  `SG-LOAD-BLOCK-INTO-PDL-BUFFER` reloads a stack group's leader a word at
  a time, passing each word through `TRANSPORT-AC`, and stepped `VMA` to the
  next word. When a saved accumulator held a `DTP-ONE-Q-FORWARD` (or a
  header or body forward), the transporter followed it by moving `VMA` to
  the forward's target, so every later leader word, the PDL pointers and
  the state among them, was read from the words after that target, and the
  machine halted at `SWAPIN+12` or `SGENT1+2`. The leader's address is now
  kept in `M-2`, which the transporter and page faults preserve, and `VMA`
  is loaded from it for every word (`ucadr/uc-stack-groups.lisp:162-181`,
  `:230-234`); `SGENT` restores `M-2` from the stack group afterwards.
  MIT's. A stack group run once, its saved `M-A` replaced by a one-Q
  forward, and resumed halted at `SWAPIN+12` (PC 24155) on microcode 1000
  as released, micro and rtl engines alike, and returns 7 with the fix; the
  same store of a fixnum resumes on both.
- **An interpreted special binding survives a process switch.** When the
  PDL buffer is refilled from memory (`PDL-BUFFER-REFILL`,
  `ucadr/uc-page-fault.lisp:1509`), a word that needs the transporter goes
  through `PB-TRANS`, which dispatched on `TRANSPORT-NO-EVCP` and so followed
  a `DTP-ONE-Q-FORWARD`: the word came back into the buffer as a copy of the
  forward's target, cdr code and all. The interpreter forwards a special
  variable's slot in its binding frame to the variable's value cell
  (`sys/eval.lisp:1397-1400`, `:1212`), and a closed-over frame's words to
  their copies (`sys/eval.lisp:2173-2194`). After a process switch the slot
  was a copy of the cell: a `SETQ` wrote the stack and not the variable, and
  the frame's last slot took the cell's cdr code, cdr-next where it had
  cdr-nil, so `PARALLEL-BINDING-LIST` (`sys/eval.lisp:1348-1408`) walked past
  the end of its frame, and an interpreted `CONDITION-CASE` now and then
  signalled "The argument CONS was 0, which is not a cons." `PB-TRANS` now
  dispatches on `TRANSPORT-NO-EVCP-KEEP-OQF`, the same dispatch with I-ARG
  bit 3, which leaves a one-Q forward as it is
  (`ucadr/uc-parameters.lisp:327-333`, `ucadr/uc-page-fault.lisp:1576-1581`):
  one control-store word, `PB-TRANS+12`, changes, and nothing moves. MIT's,
  in microcode 323 as well. `tools/microcode-check/run pdl-refill` fails
  three of its four cases on microcode 1000 without the fix, on the micro
  and rtl engines and on muir-fpga's CADR, and passes all four with it. In
  loops of 100,000 iterations of the `CONDITION-CASE` the error came 17
  times in 600,000 iterations on micro, 3 in 400,000 on rtl and 1 in 230,000
  on muir-fpga's CADR without the fix, and not in 400,000 on micro with it.
- **A full GC leaves every region in the address space map.** The cold
  load gives its last area, `FASL-TEMP-AREA`, a region of no length at the
  end of its areas (`CREATE-AREAS`, `sys/cold/coldut.lisp:389-403`; the
  sort at `:1181` expects it), where the next region made begins: in the
  bands of Systems 1001 and 1002 and in one built from this branch it is
  region 41, at the origin of another region. `FREE-REGION` and
  `UPDATE-REGION-PHT` (`ucadr/uc-storage-allocation.lisp`) step through a
  region's quanta and pages testing at the end of each loop, so for a region
  of no length they stored 0 in the address space map for the quantum at its
  origin, and called `XCPGS0` on the page below it, both another region's.
  A full GC frees that region once `FASL-TEMP-AREA` has a second one
  (`GC-RECLAIM-OLDSPACE`, `sys2/gc.lisp:439-443`), an area at a time with
  other processes running between areas. When one of them made a region at
  that quantum after `WORKING-STORAGE-AREA`'s old regions were freed and
  before `FASL-TEMP-AREA`'s were, the new region dropped out of the map: the
  next `ROOM` or GC signalled "The argument AREA was NIL, which is not an
  area number" (`GC-GET-SPACE-SIZES`, `sys2/gc.lisp:189`), and a reference
  that missed the map halted at `GET-MAP-BITS+13`, "Region not found"
  (`ucadr/uc-page-fault.lisp:215`). Both loops now return first for a
  region of no length (`ucadr/uc-storage-allocation.lisp:829-835`, `:841`,
  `:863-866`); two control-store words are added. MIT's, in microcode 323
  as well. With a 3,000,000-word array filled, checked, kept across
  `GC-IMMEDIATELY`, checked again, dropped and collected again, at 32
  boards on muir-sim's micro engine, the band built from this branch failed
  in 4 of 20 runs before the fix and System 1002's release band in 2 of 10,
  each failure with that one quantum out of the map, and the band built
  from this branch passed 20 of 20 with it. With a region made at that
  quantum just before `FASL-TEMP-AREA`'s old regions are freed (advice on
  `GC-RECLAIM-OLDSPACE-AREA`), the same band failed 5 of 5 runs without the
  fix and passed 10 of 10 with it. `tools/microcode-check/run
  zero-length-region` frees the region directly: it halts at
  `GET-MAP-BITS+13` on this branch's microcode without the fix, on the
  micro and rtl engines, and on System 1002's, and passes all four cases
  with it on both engines.
- **An interpreted `LET` keeps its variables while a closure is made under
  it with a temporary `DEFAULT-CONS-AREA`.** Making an interpreted closure
  (`INTERPRETER-ENCLOSE`, `sys/eval.lisp:2144`) copies every stack frame
  of its environment, the frames of callers still running included, and
  forwards the stack words to the copies (`UNSTACKIFY-ENVIRONMENT`,
  `sys/eval.lisp:2173-2194`). It consed the copies in `DEFAULT-CONS-AREA`,
  which `QC-FILE` binds to the compiler's temporary area
  (`sys/qcfile.lisp:362`) and resets for every file
  (`sys/qcdefs.lisp:246`, `:253`). So a `MAKE-SYSTEM` typed inside a `LET`
  at the listener lost that `LET`'s frame once compile-time code made a
  closure and the area was reset: every interpreted variable reference then
  failed ("The argument to CAR, ..., was of the wrong type"), the compiler's
  own error recovery, an interpreted lambda, failed the same way, and the
  errors nested until the region table was full and the machine halted in
  `TRAP`'s recursive-error check. The copies are now consed in
  `BACKGROUND-CONS-AREA` (`sys/eval.lisp:2168-2174`), which MIT keeps for
  functions "which want to update permanent data structures and may be
  called even when DEFAULT-CONS-AREA is a temporary area"
  (`sys/qfctns.lisp:12-15`); the old code broke that rule. MIT's; the
  QUUX line has the same fix. `docs/building.md` also says to call
  `MAKE-SYSTEM` with no interpreted binding around it. The system's checks,
  `tools/system-check/` (its `README.md`; `.gitignore` tracks it), hold the
  case: `tools/system-check/run interpreter-closure` fails two of its four
  cases on System 1002's band with this line's microcode and passes all four
  with `eval.lisp` compiled and loaded, and a SYSTEM compile inside a `LET`,
  which stopped at `SYS: SYS; QFCTNS` and halted in `TRAP`, compiles all its
  files with it. Interpreted closures over `LET`, `LET*`, `FLET`, `BLOCK` and
  `TAGBODY` give what they gave before.
- **Interpreted closures, and the code around them, see the variables in
  scope.** Three faults in `sys/eval.lisp`, all MIT's, on microcode 323
  too, and in System 100's `eval.lisp` as well; the QUUX line has the same
  fixes.
  - `LET*` (`SERIAL-BINDING-LIST`, `sys/eval.lisp:1409`) builds its frame
    on the stack a variable at a time and, after each init form, stores the
    frame into the link that holds it in the environment. A closure made in
    an init form copies that link and the frame built so far out of the stack
    and forwards the stack words to the copies (`UNSTACKIFY-ENVIRONMENT`), so
    the link is the closure's; storing the stack frame back into it gave the
    closure and the body a frame whose first words are forwarded.
    `GET-LEXICAL-VALUE-CELL` compares the words of a frame in the PDL buffer
    as they are and does not follow a forward
    (`ucadr/uc-fctns.lisp:1771-1784`), so
    `(let* ((y 2) (f (function (lambda () y)))) (funcall f))` found `Y` free,
    in the closure and in the body, and a closure made in the first init form
    saw the variable it initializes. When the link was forwarded, the
    variable and the ones after it are now bound in a new frame in the heap,
    in front of the copies, as a `LET*` of more than 16 variables binds them
    (`sys/eval.lisp:1434-1445`, `:1477`, `:1489-1501`). `PROG*` and `DO*`
    use the same macro.
  - A lambda's `&optional`, `&key` and `&aux` variables
    (`APPLY-LAMBDA-BINDVAR`) are bound the same way, the frame extended on
    the stack after each init form. After a closure made in an init form had
    taken the link, the words added later were seen by no one, so
    `(funcall (function (lambda (y &aux (f (function (lambda () y)))) (funcall f))) 21)`
    found `F` free in the body. When the link was forwarded, a new link is
    now pushed in front of the closure's, and a new frame started in it
    (`sys/eval.lisp:2303-2319`).
  - `EVAL1`, calling an interpreted closure, bound the closure's environment
    before `EVAL-LAMBDA` evaluated the arguments, so they were evaluated in
    the closure's environment and not where the call is:
    `(flet ((g (x) x)) (let ((y 21)) (g y)))` found `Y` free, and a
    recursive `LABELS` function did not see its own argument. An interpreted
    closure over a lambda now goes to `EVAL-LAMBDA` whole, and `APPLY-LAMBDA`
    binds its environment once the arguments are evaluated
    (`sys/eval.lisp:674-686`, `:709`, `:827`, `:917`). An applyhook, as
    the stepper's, is still given the lambda with the closure's environment
    bound and in its environment argument (`sys/eval.lisp:905-910`).
  - The system's checks hold all three: `tools/system-check/run
    interpreter-closure-scope` fails fifteen of its 28 cases on System 1002's
    band with this line's microcode and passes all 28 with `eval.lisp`
    compiled and loaded; its applyhook and evalhook cases see the same calls,
    functions, arguments and forms with and without the fixes. With the
    fixes, `interpreter-closure` passes, and interpreted closures over `LET`,
    `LET*`, `FLET`, `BLOCK` and `TAGBODY` give what they gave before, but for
    the two that found `Y` free, which now give `(1 2)` and `42`.
- **Main memory of up to 60 boards, 3,932,160 words (3840K).** muir-sim's
  `cadr` keeps 32 boards, 2048K, by default; `cadr --main-memory-boards 60`
  gives this system 3840K, all the memory below the Xbus I/O space at
  physical 17000000. Bands before System 1003, MIT's System 100 among them,
  halt in the cold boot on more than 32 boards on the microcode they were
  released with (measured at 33, 59 and 60 on Systems 100, 1001 and 1002).
  MIT's tables and cold boot were made for 2 megawords:
  - **The page tables hold 60 boards** (`cold/qcom.lisp:284-296`):
    PHYSICAL-PAGE-DATA is 60 pages, a word a page of main memory, and
    PAGE-TABLE-AREA 256 pages: 4 words a page, as the cold boot fills it
    (half full), rounded up to a power of two (below). They were 32 and
    128, 2 megawords. The wired areas now end at 83,968 words (244000)
    rather than 44,032. EXTRA-PDL-AREA, which must end on an address-space
    quantum boundary, is 111 pages rather than 75 and ends at 340000 rather
    than 200000 (`cold/qcom.lisp:316-323`); MICRO-CODE-ENTRY-AREA and the
    areas after it start there. A machine with fewer boards uses its share
    of the tables, and the cold boot gives the unused pages of both to
    paging, as MIT's did below 2 megawords. Wired pages, from `ROOM`: 172
    at 32 boards, as on the band built without the change, 301 at 33, 327
    at 59 and 328 at 60. The free virtual space is 48K smaller (9936K
    rather than 9984K). The wired areas take more of the level-2 map,
    which the cold boot sets up for them (`INIMAP7`,
    `ucadr/uc-cold-disk.lisp:46-50`): 11 of its 32 blocks rather than 6,
    and with the one kept for faults, 20 are left for paging rather than
    25. This system now needs at
    least 2 boards, where System 1002 boots on 1; on 1 board it halts in
    the cold boot (`FATAL-DISK-ERROR+1`), its wired areas being past the
    memory.
  - **The memory probe stops at physical 17000000**, where 60 boards end
    and the Xbus I/O space begins (`ucadr/uc-cold-disk.lisp:328-339`). The
    frame buffer there reads back what is written, so with 60 boards the
    probe counted it as 32K more memory.
  - **The cold boot uses no more memory than the band's tables serve**
    (`ucadr/uc-cold-disk.lisp:593-618`): the smaller of
    PHYSICAL-PAGE-DATA's words and a quarter of PAGE-TABLE-AREA's, read from
    the band's area origins (`GET-AREA-ORIGINS`, now called before the
    memory size is stored), not from a constant. Past them it halted in
    `XCPPG1`, "Bigger than space allocated"
    (`ucadr/uc-page-fault.lisp:1333`). So a band with 2-megaword tables
    uses 2048K of a bigger machine: this system built with MIT's table
    sizes cold-booted, loaded (`QLD`) and saved at 60 boards, and its band
    reports 2048K there, as System 1002's band does on this microcode.
  - **The page table's size is rounded up to a power of two**
    (`ucadr/uc-cold-disk.lisp:624-638`). `COMPUTE-PAGE-HASH` masks the hash
    to the size's power of two and wraps what is past the size once
    (`ucadr/uc-page-fault.lisp:683-690`), so a size between two powers got
    twice the hashes on its first words. With 4 words a page at 60 boards,
    61,440 words, the first 4096 words were loaded twice: after filling
    3,500,000 words, an entry sat on average 3.07 words from its hash and
    at most 370, against 3.05 and 26 at 32 boards, and a full GC with the
    array live took about 140 s rather than 103 s at 32. With 65,536 words
    the entries sit 2.80 words from their hash on average and at most 14 at
    60 boards (2.72 and 14 at 59, 1.09 and 8 at 33; 32 boards keep 32,768
    words and 3.05 and 26), and the full GC takes 103 s at 60 boards, as at
    32 (102 s on the band built without the change): the GC's paging is
    the same at both sizes (about 250,000 `FINDCORE` steps and 82,000 disk
    reads), so the 37 s were spent searching the page table. At 33 to 59
    boards the table is 65,536 words too, which wires up to 124 pages more
    than 4 words a page would.
  - **The cold boot direct-maps 128K rather than 64K** while it reads the
    wired areas and fills the tables (`ucadr/uc-cold-disk.lisp:307-313`),
    and so does `%DISK-SAVE` while it writes the wired pages (`:284-289`),
    since the wired areas and the CCW list put after them now end past 64K.
  - **The end of PHYSICAL-PAGE-DATA's valid entries is set again at every
    cold boot** (`ucadr/uc-cold-disk.lisp:664-672`), with the scan pointers
    of `FINDCORE` and the ager. It was set when the microcode was loaded
    and on a warm boot, and only raised after, so `%DISK-RESTORE` of a band
    whose table is elsewhere kept the old end: from this system at 32
    boards, `(disk-restore 1)` of System 1002's band left it at 72,448,
    past 1002's table (35,584 to 43,775), and the machine halted in
    `FATAL-DISK-ERROR` when a 3,500,000-word array was made. Now it is
    43,776, and the array is filled, checked, kept through a full GC and
    checked again.
  - **A wired page's PHYSICAL-PAGE-DATA entry is written at its page
    number** (`ucadr/uc-cold-disk.lisp:687-700`). MIT's code merged the
    page number's low 8 bits into the table's origin, which serves only
    wired pages below 64K. With the larger tables the wired pages run past
    page 255: their entries landed on those of pages 0 and up, their own
    stayed as the band had them, their frames were paged into, and at 32
    boards the cold load halted in `FINDCORE` during `QLD`, reading a
    page's data as a table entry. QUUX's line has the same change.
  - **The swap recommendations are unchanged.**
    `MEMORY-SIZE-SWAP-RECOMMENDATION-ALIST` (`sys2/gc.lisp:1018`) has
    entries from 320K to 1024K, which `DEFAULT-SWAP-RECOMMENDATIONS` matches
    exactly, so at 2048K, the default, no entry applies, and the areas keep
    the cold load's 0; above 2048K the same holds. Measured: 0 for
    WORKING-STORAGE-AREA at 32, 33, 59 and 60 boards, as on System 1002's
    band.
  - **The microcode changes again and keeps the number 1000**: microcode
    1000 with the fixes above and these changes to the cold boot, which add
    21 control-store words, so every word from `MEM-SIZE-LOOP` on moves;
    the constant 17000000 is a new A-memory constant, so the A-constants
    start one location later (`A-CONSTANT-LOC` 1177 to 1200). `ucadr.tbl` is
    the same. Assembled twice, each on a freshly booted band, the four
    files were the same both times. The outputs, of microcode 1000 with
    all the changes above (sha256):
    - `ucadr.mcr` `02e09d0925af6117200996fb09413c90e664593bf84255e48105defa1479e2b9`
    - `ucadr.tbl` `e510ce7cc4d7d1241b706ffbeef5c0e0caef10704dcb5dc477090fbc18898efd`
    - `ucadr.locs` `f4a8b1662a0756f8eda70aa58eaac9551be6422cd04aae863da4863f49b94d1a`
    - `ucadr.sym` is not given (above).

    A System 1003 band needs it: on the microcode before these changes the
    band halts in the cold boot (`XRGN1+2`), its wired areas being past the
    64K mapped. `docs/building.md` says so for the build.
  - Measured on muir-sim's `cadr`, micro engine, with this system built
    from this tree: the herald and `ROOM` say 2048K at 32 boards, 2112K at
    33, 3776K at 59 and 3840K at 60, and the microcode's own figures, the
    end of PHYSICAL-PAGE-DATA's entries and the page table's size, agree
    with each. A paging check, an array of 3,500,000 words filled and
    checked, a full GC with it live, checked again, then dropped and a GC
    again, keeps the array intact three times at 60 boards, three at 32
    and once each at 33 and 59; at 60 boards all 7168 page frames above
    2048K then hold pages. In two of those runs, one at 32 boards and one
    at 60, a `ROOM` after the first GC and the second GC failed with "The
    argument AREA was NIL", a fault of MIT's GC that this change does not
    touch; the band built without the change shows it too. A band saved at 60 boards boots there with
    3840K. `tools/lispm-check-test` (selftest), `tools/system-check` and
    `tools/microcode-check` give the same results at 32 and 60 boards as
    this tree's band without the change at 32.
- **The herald says how to give the system more memory** when the machine
  has less than the page tables serve (`io/disk.lisp:1291-1302`):

  ```
  This system can use up to 3840K of physical memory:
  use --main-memory-boards 60 in muir-sim or muir-fpga.
  ```

  The most is computed from the band's PHYSICAL-PAGE-DATA and
  PAGE-TABLE-AREA, as the cold boot computes it, and compared with the
  memory the cold boot found, the figure the herald prints; one line, 105
  characters, is wider than the console. It shows at 32, 33 and 59 boards
  and not at 60, from `PRINT-HERALD` and on the console after the cold
  boot.
- **A machine whose `sys/` holds no `ubin/ucadr.tbl` boots.** System 1002
  read `SYS: UBIN; UCADR TBL` at every boot, so with the file absent (an
  empty `sys/`, or one without `ubin/`) the boot stopped at "LOAD could not
  find any file related to OZ: /sys/ubin/ucadr.tbl". `EH:INITIALIZE`
  (`sys/eh/eh.lisp:2403-2417`) now forgets the band's cached table only when
  the file can be read (`error-table-file-p`, `sys/eh/eh.lisp:2311-2315`,
  which counts a missing file or directory as absent). Without it, the
  band's own table, the one it was built with, is kept when it is for the
  running microcode's version, and the console says so:

  ```
  [No error table file for microcode version 1000; using the band's own]
  ```

  For another version the load fails as before. A served file is still read
  at every boot, so a rebuilt microcode's table replaces the band's; a band
  booted without the file on a different build of the same-numbered
  microcode uses the table it was built with. On a band built from this
  tree and saved to LOD4 as a release band is, booted with no `ucadr.tbl`
  and with an empty `sys/`, the boot completes, prints the line, and
  `(car 1)` reports "The argument to CAR, 1, was of the wrong type"; the
  band without the change stops at that LOAD's question. With the table served
  it prints "[Loading error table for microcode version 1000]", and a
  served table with one entry added is the one in use (705 entries, the
  band's 704). `tools/lispm-check-test` (selftest), `tools/system-check`'s
  interpreter-closure cases and `tools/microcode-check` give the same
  results as the band without the change.
