# System 2001

What QUUX's next release changes from System 2000. It is in progress on
`main`: each change is recorded here as it is made. Every change to a source
file carries a comment in that file saying why.

- **The system number is 2001** (`patch/system.patch-directory`,
  `patch/system-2001.patch-directory`), now that System 2000 is released,
  so that no band built from `main` calls itself 2000.
- **Microcode 2001 and boot PROM 2001**, the numbers of the first 40-bit
  QUUX, revision 13 (Mete, 2026-09-28). As for 2000, the version is not in
  the sources but given to the assembler (`ua:version-number` and the
  output's version for `UCADR`, the version asked for `PROMH`), so no
  source changed for it. This supersedes Q12's rule (its section 1.1) that
  the microcode and the PROM keep 2000 until a changed one is released.
- **The micro-assembler assembles for a 40-bit word** when
  `ua:*word-width*` is `40.` (`sys/sys/cadrlp.lisp:227-258`): the fields of
  contract G2's appendix A1. At its default, `32.`, the words are what they
  were: microcode 2000's `ucadr.mcr`, `ucadr.tbl` and `ucadr.locs`, and
  PROM 2000's outputs, assemble byte for byte as released. At 40 bits:
  - a byte instruction's rotate is `IR<5:0>` and its length − 1 `IR<11:6>`,
    so a byte is up to 40 bits long; a longer byte, or one starting past
    bit 39, is refused (`BYTE-FIELD` in `CONS-LAP-EVAL`,
    `sys/sys/cadrlp.lisp:1642-1685`);
  - a jump's or a dispatch's rotate keeps `IR<4:0>` and puts its bit 5 in
    `IR<47>`, and an LDB's, a jump's and a dispatch's rotate is reflected
    mod 40 (`CONS-LAP-REFLECT-ROTATE-40`, `sys/sys/cadrlp.lisp:1433-1445`,
    `:1461-1477`);
  - LC byte mode (`INSTRUCTION-STREAM`) is `IR<24>` in a byte instruction,
    whose `IR<11:10>` are now length bits, and only on LDB; a deposit or an
    ALU word with it, and a byte instruction with `HALT-CONS`, are refused
    (`CONS-LAP-DEFAULT-AND-BUGGER`, `sys/sys/cadrlp.lisp:1359-1429`).
    `INSTRUCTION-STREAM` and `HALT-CONS` became fields with the values they
    had, so that the assembler sees them in a word
    (`sys/sys/cadsym.lisp:71-82`);
  - the dispatch memory has 4,096 entries, its address `IR<23:12>`
    (`sys/sys/cadrlp.lisp:289-296`, `:359-361`, `:741-745`, `:960-969`,
    `:1100-1103`);
  - a constant, and an A or M location's initial value, is zero-extended
    from 32 bits, so -1 is `37777777777`, and a value that fits neither 40
    bits nor 32 signed bits is refused (`CONS-LAP-WORD-VALUE`,
    `sys/sys/cadrlp.lisp:1173-1176`, `:1485-1487`, `:1505-1507`); a
    `BYTE-VALUE` in a field of 32 bits or more, such as the pointer, is
    placed by arithmetic, since `DPB` takes only fields that fit in a fixnum
    (`sys/sys/cadrlp.lisp:1832-1838`);
  - the `.mcr` file holds A memory as section 5, two words a location, its
    `<31:0>` and then `<39:32>` (`WRITE-A-MEM`,
    `sys/sys/qwmcr.lisp:72-76`, `:110-118`, `:142-145`).
- **A compiled `(gcd n)` or `(\\ n)` with one argument works** (`convert-\\`,
  `sys/sys/qcopt.lisp:320-334`). The optimizer built `(internal-\\ n nil)`
  from it, so the call signalled that `NIL` was of the wrong type; with fewer
  than two arguments it now leaves the form alone, and the call goes to the
  function `\\`. Two or more arguments compile as before.
- **`tools/release-scan` finds a private address that ends a sentence**
  (`tools/release-scan:115-118`). Its IPv4 pattern refused a match followed by
  any dot, so the full stop after an address hid it; it now refuses only a
  digit or a dot followed by a digit, as muir-website's public-content check
  does. `tools/release-test` plants such an address in a Lisp file, case (e)
  (`tools/release-test:23-24`, `:69`, `:216-220`), and it fails with the one
  FAIL line it planted.
- **`GCD` of two bignums is never negative.** When the shorter of two
  bignums of two or more words divides the longer, `GCDBB-LONG` returned the
  divisor with its sign, so `(gcd (expt 2 90) (- (expt 2 31)))` gave
  -2147483648, and `LCM`, compiled `GCD` and `SYS:INTERNAL-\\` with it. It
  now calls `UN-CONS` and returns the divisor through `BIGNUM-ABS`, as
  `GCD-IS-ABS-M-B` does (`sys/ucadr/uc-hacks.lisp:543-559`). MIT's; the
  CADR's line has the same fix. Of 82 cases (every mix of signs over fixnums
  and bignums, remainders zero and not, interpreted and compiled, `LCM` and
  `//`), 14 fail on Y3's band with microcode 2001 as it was and all pass
  with the fix, and the 22 cases of the compiled one-argument `(gcd n)` pass.
- **A stack group whose saved registers hold a forwarding word resumes.**
  `SG-LOAD-BLOCK-INTO-PDL-BUFFER` reloads a stack group's leader a word at
  a time, passing each word through `TRANSPORT-AC`, and stepped `VMA` to the
  next word. When a saved accumulator held a `DTP-ONE-Q-FORWARD` (or a
  header or body forward), the transporter followed it by moving `VMA` to
  the forward's target, so every later leader word, the PDL pointers and
  the state among them, was read from the words after that target, and the
  machine halted at `SWAPIN+12` or `SGENT1+2`. The leader's address is now
  kept in `M-2`, which the transporter and page faults preserve, and `VMA`
  is loaded from it for every word (`sys/ucadr/uc-stack-groups.lisp:162-181`,
  `:230-234`); `SGENT` restores `M-2` from the stack group afterwards.
  MIT's; the CADR's line has the same fix. A stack group run once, its
  saved `M-A` replaced by a one-Q forward, and resumed halts at `SWAPIN+12`
  on Y3's band with microcode 2001 as it was, and returns 7 with the fix;
  the same store of a fixnum resumes on both.
- **An interpreted special binding survives a process switch.** When the
  PDL buffer is refilled from memory (`PDL-BUFFER-REFILL`,
  `sys/ucadr/uc-page-fault.lisp:1735`), a word that needs the transporter
  goes through `PB-TRANS`, which dispatched on `TRANSPORT-NO-EVCP` and so
  followed a `DTP-ONE-Q-FORWARD`: the word came back into the buffer as a
  copy of the forward's target, cdr code and all. The interpreter forwards a
  special variable's slot in its binding frame to the variable's value cell
  (`sys/sys/eval.lisp:1397-1400`, `:1212`), and a closed-over frame's words
  to their copies (`sys/sys/eval.lisp:2173-2194`). After a process switch
  the slot was a copy of the cell: a `SETQ` wrote the stack and not the
  variable, and the frame's last slot took the cell's cdr code, cdr-next
  where it had cdr-nil, so `PARALLEL-BINDING-LIST`
  (`sys/sys/eval.lisp:1348-1408`) walked past the end of its frame, and an
  interpreted `CONDITION-CASE` now and then signalled "The argument CONS was
  0, which is not a cons." `PB-TRANS` now dispatches on
  `TRANSPORT-NO-EVCP-KEEP-OQF`, the same dispatch with I-ARG bit 3, which
  leaves a one-Q forward as it is (`sys/ucadr/uc-parameters.lisp:350-356`,
  `sys/ucadr/uc-page-fault.lisp:1802-1807`). MIT's, in microcode 323 as
  well; the CADR's line has the same fix. The microcode's checks,
  `tools/microcode-check/` (its `README.md`; `.gitignore` tracks it), hold
  the case: `run pdl-refill` fails three of its four cases on Y3's band with
  microcode 2001 as it was and passes all four with the fix, on the micro
  and rtl engines.
- **The three fixes change seven control-store words and add four**
  (`GCDBB-LONG+14` and `+16`; `SG-LOAD-BLOCK-INTO-PDL-BUFFER+0`,
  `SG-L-P-B-1+1`, `SGENT+2` and `+3`; `PB-TRANS+12`; four after
  `GCDBB-LONG+17`), so every word from `GCDBB-LONG+20` (`GCDBB-NO-LUCK`) on
  is four locations later; every other word, every dispatch entry and every
  symbol of Y3's microcode 2001 is the same once moved, and the A-memory
  words that hold control-store addresses move with them. The number stays
  2001; `ucadr.mcr` is now `060a30b75c143d84fbfc1a6db37ced0b7141378380ebe4a7dab307b2e22dc753`.
  Boot PROM 2001 assembles to the same four files.
- **An interpreted `LET` keeps its variables while a closure is made under
  it with a temporary `DEFAULT-CONS-AREA`.** Making an interpreted closure
  (`INTERPRETER-ENCLOSE`, `sys/sys/eval.lisp:2144`) copies every stack frame
  of its environment, the frames of callers still running included, and
  forwards the stack words to the copies (`UNSTACKIFY-ENVIRONMENT`,
  `sys/sys/eval.lisp:2173-2194`). It consed the copies in `DEFAULT-CONS-AREA`,
  which `QC-FILE` binds to the compiler's temporary area
  (`sys/sys/qcfile.lisp:362`) and resets for every file
  (`sys/sys/qcdefs.lisp:246`, `:253`). So a `MAKE-SYSTEM` typed inside a `LET`
  at the listener lost that `LET`'s frame once compile-time code made a
  closure and the area was reset: every interpreted variable reference then
  failed ("The argument to CAR, ..., was of the wrong type"), the compiler's
  own error recovery, an interpreted lambda, failed the same way, and the
  errors nested until the region table was full and the machine halted in
  `TRAP`'s recursive-error check. The copies are now consed in
  `BACKGROUND-CONS-AREA` (`sys/sys/eval.lisp:2168-2174`), which MIT keeps for
  functions "which want to update permanent data structures and may be
  called even when DEFAULT-CONS-AREA is a temporary area"
  (`sys/sys/qfctns.lisp:12-15`); the old code broke that rule. MIT's; the
  CADR's line has the same fix. `docs/building.md` also says to call
  `MAKE-SYSTEM` with no interpreted binding around it. The system's checks,
  `tools/system-check/` (its `README.md`; `.gitignore` tracks it), hold the
  case: `run interpreter-closure` fails two of its four cases on Y3's band
  as it was and passes all four with `eval.lisp` compiled and loaded, and a
  SYSTEM compile inside a `LET`, which halted in `TRAP` on System 2000's
  band, compiles all its files with it. With the fix, Y3's page cases and
  band 2000's 33 cases pass on Y3's band, and interpreted closures over
  `LET`, `LET*`, `FLET`, `BLOCK` and `TAGBODY` give what they gave before.
- **Interpreted closures, and the code around them, see the variables in
  scope.** Three faults in `sys/sys/eval.lisp`, all MIT's, on microcode 323
  too, and in System 100's `eval.lisp` as well; the CADR's line has the same
  fixes.
  - `LET*` (`SERIAL-BINDING-LIST`, `sys/sys/eval.lisp:1409`) builds its frame
    on the stack a variable at a time and, after each init form, stores the
    frame into the link that holds it in the environment. A closure made in
    an init form copies that link and the frame built so far out of the stack
    and forwards the stack words to the copies (`UNSTACKIFY-ENVIRONMENT`), so
    the link is the closure's; storing the stack frame back into it gave the
    closure and the body a frame whose first words are forwarded.
    `GET-LEXICAL-VALUE-CELL` compares the words of a frame in the PDL buffer
    as they are and does not follow a forward
    (`sys/ucadr/uc-fctns.lisp:1790-1803`), so
    `(let* ((y 2) (f (function (lambda () y)))) (funcall f))` found `Y` free,
    in the closure and in the body, and a closure made in the first init form
    saw the variable it initializes. When the link was forwarded, the
    variable and the ones after it are now bound in a new frame in the heap,
    in front of the copies, as a `LET*` of more than 16 variables binds them
    (`sys/sys/eval.lisp:1434-1445`, `:1477`, `:1489-1501`). `PROG*` and `DO*`
    use the same macro.
  - A lambda's `&optional`, `&key` and `&aux` variables
    (`APPLY-LAMBDA-BINDVAR`) are bound the same way, the frame extended on
    the stack after each init form. After a closure made in an init form had
    taken the link, the words added later were seen by no one, so
    `(funcall (function (lambda (y &aux (f (function (lambda () y)))) (funcall f))) 21)`
    found `F` free in the body. When the link was forwarded, a new link is
    now pushed in front of the closure's, and a new frame started in it
    (`sys/sys/eval.lisp:2303-2319`).
  - `EVAL1`, calling an interpreted closure, bound the closure's environment
    before `EVAL-LAMBDA` evaluated the arguments, so they were evaluated in
    the closure's environment and not where the call is:
    `(flet ((g (x) x)) (let ((y 21)) (g y)))` found `Y` free, and a
    recursive `LABELS` function did not see its own argument. An interpreted
    closure over a lambda now goes to `EVAL-LAMBDA` whole, and `APPLY-LAMBDA`
    binds its environment once the arguments are evaluated
    (`sys/sys/eval.lisp:674-686`, `:709`, `:827`, `:917`). An applyhook, as
    the stepper's, is still given the lambda with the closure's environment
    bound and in its environment argument (`sys/sys/eval.lisp:905-910`).
  - The system's checks hold all three: `tools/system-check/run
    interpreter-closure-scope` fails fifteen of its 28 cases on Y3's band as
    it was and passes all 28 with `eval.lisp` compiled and loaded; its
    applyhook and evalhook cases see the same calls, functions, arguments
    and forms with and without the fixes. With the fixes,
    `interpreter-closure`, Y3's page cases and band 2000's 33 cases pass on
    Y3's band, and interpreted closures over `LET`, `LET*`, `FLET`, `BLOCK`
    and `TAGBODY` give what they gave before, but for the two that found `Y`
    free, which now give `(1 2)` and `42`.
- **The cross build** (contract G2, section 7, option (iii)): System 2000's
  band compiles SYSTEM for the 40-bit machine and writes its cold load, as
  `docs/building.md` ("Cross-building for the 40-bit QUUX") describes.
  - `cold/cross.lisp` (new). The target's table (`cross-build-table`,
    `cold/cross.lisp:132`): the cold-load generator's parameters with the
    target's overlay; for the constants those do not define, their
    `DEFCONSTANT`s in the tree being built (`:177-228`); the fixnum limits
    from the target's pointer field. One evaluator hook gives every
    interpreted evaluation of a watched symbol the target's value while a
    file compiles, and a symbol with none stops the file, its QFASL not
    written, also after a fold whose own error is only a warning
    (`cross-evalhook`, `cross-read`, `cross-compile-stream`, `:302-380`).
    What the hook cannot see is checked before anything is compiled: data
    type numbers, the compiler's misc instructions, and the FEF, FASL and
    character formats (`:235-298`). Every fold, `#.`, watched read and
    `LSH` or `ROT` left unfolded is logged (`:382-411`). The builder never
    loads a 40-bit QFASL: where `MAKE-SYSTEM` loads one, it loads its own
    compile of the source, and it tells such a file by its first bytes,
    since reading its attribute list first changed what the load did
    (`cross-fasload-internal`, `cross-marked-file-p`, `cross-host-fasl`,
    `:413-465`). Then
    `cross-begin`, `cross-end`, `cross-compile-system`, `cross-make-cold`,
    `cross-copy-partition`, and `cross-redump-value-file` for the cold
    load's font, which the tree holds only as a 32-bit file (`:469-593`).
  - `cold/target40.lisp` (new): the 40-bit word's fields (G1, section 2.1)
    and 1024-word pages, loaded over `QCOM` until `QCOM` carries them.
  - `sys/qcdefs.lisp:744-766`: `*cross-target*`, `target-value` and
    `target-word-width`, which the compiler's own encodings ask.
  - `sys/qcp1.lisp:410-413`, `:582`: a closure's local slots are marked with
    the target's fixnum sign bit, bit 31 on the 40-bit machine
    (`boxed-sign-bit-mark`); the `%LOGDPB` it replaces is commented out.
  - `sys/qcopt.lisp:295-300`: a cross build folds no `LSH` or `ROT`, which
    work on the fixnum's width; the target computes them.
  - `sys/qcfasd.lisp`: in a file for the 40-bit machine every float is an
    IEEE single (`:247`, `:260`, `fasd-binary32` and `float-to-binary32`,
    `:295-330`), rounded as IEEE 754 rounds to nearest: `1e50` in
    `io/format.lisp:946` becomes an infinity. Float arrays are refused in a
    cross build (`:396-404`), and the attribute list says `:WORD-WIDTH 40`
    (`fasd-attributes-list`, `:507-509`); a 32-bit file carries no mark and
    is unchanged.
  - `sys/qfasl.lisp:198-205`, `:240-243`: the fasloader refuses a file
    whose word is not its world's (`qfasl-word-width`), so neither world
    loads the other's files.
  - `cold/coldut.lisp`: a page is `blocks-per-page` disk blocks (1 today, 4
    for 1024-word pages of 32-bit words, 5 for 40-bit ones) and a word
    `word-bytes` bytes of the page's 8-bit buffer, least significant first
    (`:18-26`, `:64-164`, `load-parameters` `:403-428`); data words carry
    the tag 005 in a 40-bit cold load (`vunboxed`, `:227-235`), where a
    float is an IEEE single (`:680-681`), a bignum keeps the CADR's layout,
    31-bit digits (`store-bignum-40`, `:782-814`), and the band format is
    2002 (`:1237`, appendix A1.12); the system communication area's base is
    its area's origin rather than 400 (`:1154-1155`, A1.9).
    `vstore-contents` keeps a word's cdr code by `LDB` and `DPB`
    (`:246-252`): `DEPOSIT-FIELD` returns its third argument unchanged when
    the first is a bignum, as a 32-bit word with its cdr code set is. A
    32-bit cold load made by this generator is byte for byte the one System
    2000's makes.
  - `cold/coldld.lisp`: a 40-bit file's floats are binary32
    (`q-fasl-op-small-float`, `binary32-to-float`, `:388-425`), its numeric
    array data are data words (`:512`, `:585-602`), and a file whose word
    is not the cold load's is refused, whether it names its word
    (`q-fasl-op-file-property-list`, `:878-899`) or has no attribute list,
    which makes it a 32-bit file (`cold-fasload`, `:83-91`).
- **The cross build's checks, `tools/cross-check/`** (its `README.md`;
  `docs/building.md`, "Checking the cross build"): a driver, `run`, which
  primes the builder band (`cases/prime.cases`) and runs each check through
  `tools/lispm-check` on a copy of the tree, with its test files (`lisp/`)
  served as `SYS: CROSS-CHECK;`, and the host programs that read what the
  builder wrote: `qfasl.py` decodes a QFASL, 40-bit ones included;
  `check1.py` finds each family of system constants at each point where the
  compiler evaluates with the target's value; `check3.py` reads a cold load's
  image and `plant3.py` plants faults it must catch; `check2.py` checks a
  cross compile's log of folds and `#.`; `compare.py` compares cross QFASLs
  with System 2000's function by function. The native control
  (`cases/native.cases`) makes System 2000's cold load with its own generator
  and with this tree's, which must be byte for byte the same. `.gitignore`
  tracks the directory. `docs/lispm-check.md:66-68`: a compiler file patched
  alone into a band built before the cross build needs `sys/sys/qcdefs.lisp`
  loaded first.
- **1024-word pages on revision 12** (contract G2, section 5.4, option (w);
  appendix A1.9 and A1.12): a page is 1024 words, and on revision 12's map,
  whose entries stay 256 words, it is four map entries and four 1 KiB disk
  blocks. A page frame is four consecutive 256-word hardware pages on a
  1024-word boundary; its page hash table entry names the first, and entry
  k of the page maps PHT2 + k. Bands of 256-word pages do not run on it.
  - `sys/cold/qcom.lisp`: `PAGE-SIZE` 2000 and `%%Q-POINTER-WITHIN-PAGE`
    0012 (`:57`, `:838`); `DISK-BLOCKS-PER-PAGE`, 4, a new system constant
    (`:841`; `sys/cold/qdefs.lisp:161`); `%%PHT1-VIRTUAL-PAGE-NUMBER` 1216
    and `%PHT-DUMMY-VIRTUAL-ADDRESS` 37777 (`:860-861`). Every fixed area on
    its own page (A1.9, option (b)): the system communication area at 2000
    with its offsets kept, so the swap-out CCW list is at 2040, the
    keyboard buffer's header at 2100, the disk error log at 2200-2237, the
    reverse level-1 map at 2240-2337, the swap-in list at 2340 and the CCW
    of a one-block transfer at 2377 (`:129-131`); the cold load's area sizes
    in pages of 1024 words (`:326-352`), so that the microcode symbol area
    is page 3, 6000-7777, and `EXTRA-PDL-AREA` still ends at 200000.
  - `sys/cold/coldut.lisp`: a disk block is 1024 bytes whatever the
    builder's page (`:425-430`); a 32-bit cold load of 1024-word pages has
    band format 1102 (`:1241-1250`). The condition is written with `NOT` and
    `=`: this readtable reads `/=` as `=`, which gave a 32-bit cold load
    2002 and a 40-bit one 1102 until the cross build's checks caught it.
  - **The map** (`sys/ucadr/uc-page-fault.lisp`; G2 section 5.4, option (w),
    four map entries a page), every site where the microcode writes the map
    for a page: a reload (`PGF-RL`, `:708`) and the
    first write (`PGF-RWF`, `:658`) write all four entries, PHT2 + k; the
    early write-back (`COREF-CCW-ADD`, `:1013`), eviction (`PHTDELX`,
    `:1147`), the age trap (`AGER2`, `:1396`) and `%CHANGE-PAGE-STATUS`
    (`XCPGS2`, `:1511`) flush all four; a fresh page is filled a quarter at
    a time (`CZRR`, `:1335`). The page hash table's page field is
    `VMA<23:10>` (`:74`) and the hash is computed from it
    (`COMPUTE-PAGE-HASH`, `:763`). The fields that mean the page (the frame,
    `PHT2-PAGE-FRAME-NUMBER`, `VMA-PAGE-ADDR-PART`) move to bit 10; those
    that mean a map entry or a disk block are new and stay at bit 8
    (`VMA-PHYS-MAP-ENTRY-PART`, `VMA-BLOCK-PART`, `VMA-MAP-ENTRY-IN-PAGE`,
    `:88-110`); `%PHYSICAL-ADDRESS` (`:1607`) and the I/O pages' direct map
    (`PGF-MM0`, `:462`) take the entry's part.
  - **Swapping** (`sys/ucadr/uc-page-fault.lisp`, `uc-disk.lisp`,
    `uc-parameters.lisp`; G2 section 5.2, page = block in the CCW lists and
    the swap lists): a page takes four CCWs, a block each
    (`WRITE-PAGE-CCWS`, `uc-page-fault.lisp:1231-1248`, from `COREFOUND1A`,
    `COREF-CCW-ADD-1` and `SWAPIN1`); a multi-page swap-in is at most
    `DISK-SWAP-IN-MAX-PAGES`, 4 (`uc-page-fault.lisp:818-823`,
    `uc-parameters.lisp:971-984`); `START-DISK-N-PAGES` counts blocks
    (`uc-disk.lisp:62-97`) and the swap handler starts at the page's first
    block (`uc-disk.lisp:11-16`). `MAP-ENTRY-SIZE`, `DISK-BLOCK-SIZE`,
    `BLOCKS-PER-PAGE` and `LOW-PAGES-BLOCKS` are named
    (`uc-parameters.lisp:169-188`).
  - **The boot and the band** (`sys/ucadr/uc-cold-disk.lisp`): the loops
    that set up the wired map step map entries, not pages (`INIMAP2`,
    `INIMAP3`, `INIM3A`, `:228-269`; `BEGCM1`, `BEGCM3`, `:1077-1087`; G2
    section 5.4, option (w)); `DISK-SAVE` counts blocks, each region saved
    to the end of the page its free pointer is in, and the band's valid size
    is blocks (`:375-505`; G2 section 5.2, page = block in save and restore
    and the band's valid size); it writes format 1100, or 1101 for an
    incremental band, and `%DISK-RESTORE` and the cold boot take 1100, 1101
    and 1102 and halt at the new `BAND-NOT-1024-WORD-PAGES` on anything
    else, so a band of 256-word pages is refused rather than taken for a
    cold load (`:313-318`, `:655-674`; appendix A1.12); an incremental
    band's bitmap has a bit a block (`:415-418`, `:899-902`), its data
    blocks at 14, 15 and 16 of the band (`:817-837`; G2 section 5.2). The
    system communication area's addresses are 2000's here and in
    `uc-chaos.lisp`, `uc-interrupt.lisp` and `uc-storage-allocation.lisp`
    (appendix A1.9, option (b)); the keyboard's channel is at 2100
    (`INTR-KBD`, `uc-interrupt.lisp:366-373`, and `:224-227`; A1.9: at 500,
    in the resident symbol area's page, a key's word went to a garbage
    address and the machine halted in `SWAPIN` at interrupt level);
    `MAKE-REGION` compares the disk's size in blocks
    (`uc-storage-allocation.lisp:237-238`, `:280-281`) and the meter buffer
    is one block (`uc-meter.lisp:35-38`), page = block (G2 section 5.2).
  - **Boot PROM 2001** (`sys/ucadr/promh.text`; G2 section 5.2, the PROM's
    buffer and the fixed areas' origins; appendix A1.9): the buffer is 6000-6377,
    the first block of the microcode symbol area, and virtual page 0 maps
    it; the CCW is 2377, which virtual page 3 maps (`:60-67`, `:92-94`,
    `:338`, `:470-498`, `:763-766`, `:880`). Every other address is as in
    PROM 2000.
  - **Disk transfers in Lisp** (`sys/io/disk.lisp`): an RQB holds pages of
    1024 words and has a CCW for each block (`MAKE-DISK-RQB`, `:207`;
    `WIRE-DISK-RQB`, `:316`); `DISK-BLOCK-WORDS` and `RQB-NBLOCKS`
    (`:76-88`). Disk addresses stay blocks, so a transfer is whole pages:
    the callers that want one block read the page it starts
    (`READ-DISK-LABEL`, `:847`; `DISK-READ-COMPARE-WIRED`, `:406`; the
    remote and CC handlers, `:564`, `:757`), a band's system communication
    area is its block 4 (`BAND-SYS-COM-BLOCK`, `:1158-1185`, with the band
    formats and `SYS-COM-BLOCK-COUNT`, which counts blocks rounded up, as an
    incremental band's size need not be whole pages), and the partition
    functions count blocks (`DESCRIBE-PARTITION`, `FIND-PLAUSIBLE-PARTITIONS`,
    `GET-UCODE-VERSION-OF-BAND`, `MEASURED-SIZE-OF-PARTITION`,
    `:1190-1365`); `DISK-INIT`'s virtual memory is the paging partition's
    whole pages below A memory, whose page is the address's bits 10-23
    (`:1379-1390`; a `FLOOR` of that negative fixnum made the size negative,
    and `ADDRESS-SPACE-WARNING` stopped the cold load's QLD); `LOAD-MCR-FILE`
    writes a page at a time (`:1538`); `COPY-DISK-PARTITION` and
    `COMPARE-DISK-PARTITION` move 22 pages at a time and refuse to pass the
    target partition's end (`:1678`, `:1769`); the page RQB of
    `PAGE-IN-WORDS` is a long array at 1024 words, one data word shorter,
    its CCW list a word later (`:1875-1898`; as it was, `DISK-SAVE`'s
    `PAGE-IN-WORDS` read stopped short and the machine halted), and
    `PAGE-IN-WORDS` writes four CCWs a page (`:2018`).
    `sys/io/fdev.lisp:164-171`: the file device's buffer address is its
    page's first CCW.
  - **The rest of Lisp** (M1's class (a), G2 section 5): the disk error log
    at 2200 (`sys/io/dledit.lisp:147-150`, `sys/sys/qmisc.lisp:1819-1826`);
    `DISK-SAVE`'s highest virtual address and partition check in pages of
    1024 words and blocks (`sys/sys/qmisc.lisp:1814-1818`, `:1832-1846`);
    the page number of an address (`sys/sys2/gc.lisp:922-925`,
    `sys/sys2/describe.lisp:658-661`); the keyboard buffer's header at 2100
    (`sys/window/cold.lisp:499-593`); the incremental save and its checks,
    a bit a block (`sys/io1/inc.lisp`); the band transfer server, still 17
    blocks a packet group, reading a page before writing part of it
    (`sys/sys2/band.lisp:10-16`, and the servers); the remote disk server
    (`sys/network/chaos/chsaux.lisp:942-995`); the meters' disk buffer, one
    block (`sys/io1/meter.lisp`); the `.mcr` file's blocks of 400 words
    (`sys/sys2/usymld.lisp:827-834`, `sys/sys/qwmcr.lisp:137-138`); the
    local file system's pages are blocks, read and written through whole
    pages (`sys/file/fsdefs.lisp:274-348`, `fsguts.lisp`, `fsstr.lisp`).
  - **The cross build of a 32-bit target of 1024-word pages**
    (`sys/cold/cross.lisp`, `cross-foreign-file-p`, `:446-458`, used by
    `cross-fasload-internal`, `:420-424`): such a target's files name no
    word width, but fold its page into their code, so where `MAKE-SYSTEM`
    loads one while it compiles, the builder loads its own compile of the
    source instead, as it does a 40-bit file's; a file with no source (a
    font) is loaded as it is. Loaded as it was, the target's `SYS: IO;
    FDEV`, which `HOST-FILE-IO` loads, stopped System 2000's builder at an
    illop in `%FIND-STRUCTURE-HEADER`. `docs/building.md` ("A band of
    1024-word pages for revision 12") gives the build.
  - `tools/cross-check`: the tree's `QCOM` has 1024-word pages, so priming
    gives 4 blocks a page (`cases/prime.cases:24-26`), the identity control
    puts this world's page back (`lisp/pages256.lisp`,
    `cases/check1.cases:48-51`, `run:46`), `check3.py` wants band format
    1102 of a 32-bit cold load at 1024-word pages (`:143-147`), and check 1
    compiles and loads a file for this tree's own target, whose load must be
    replaced by the builder's compile while a font's is not
    (`cases/check1.cases:54-64`); with `cross.lisp` as it was, those cases
    fail.
- **The first 40-bit QUUX, revision 13** (contract G2; its appendix A1):
  microcode 2001 and boot PROM 2001 for the 40-bit word, and the cold load
  cross-built for it, which boots on revision 13 to its herald. Every source
  change carries a comment "quux revision 13", the old code commented out in
  place.
  - **`sys/cold/qcom.lisp`**: the word's fields (G1 section 2.1): cdr code
    `<39:38>`, data type `<37:32>`, the field `<31:0>`, a fixnum's sign bit
    31 (`Q-FIELD-VALUES`); the ADI and special-PDL flags stay in the cdr
    code, now bits 38 and 39 (G1 section 2.2); the region bits and the page
    hash table's second word as the 28-bit level-2 map entry, whose ten bits
    above the 18-bit page move up by 4, and the first word's page at
    `<27:10>`, the dummy page 777777 (A1.7); `ART-32B` holds 32 bits (G1
    section 2.6); A memory's window at 1757776000 and the I/O region at
    1760000000 (A1.7); the dispatch memory's 4,096 entries, the level-1
    map's 8,192 and the level-2 map's 4,096; `PHYSICAL-PAGE-DATA` and
    `ADDRESS-SPACE-MAP` 4 pages each (4 M words, and a byte for each of the
    28-bit space's quanta), `EXTRA-PDL-AREA` 5 pages fewer so that it still
    ends at 200000, a level-1 block's boundary.
  - **The micro-assembler** reads `QCOM` into its own package, and QCOM's
    40-bit constants set the running 32-bit world's own values: System
    2000's band halted loading the micro-assembler. `sys/sys/uashadow.lisp`
    (new) shadows in `UA`, before `QCOM` is read, each numeric constant of
    `QCOM` whose value differs from the running world's; `SYS: SYS; SYSDCL`
    reads it first (`CADR-MICRO-ASSEMBLER`). `sys/sys/cadsym.lisp`: the
    jump conditions 10 (fixnum overflow) and 11 (unsigned less than) of
    A1.3, as `JUMP-IF-FIXNUM-OVERFLOW` and its kin.
  - **Microcode 2001** (`sys/ucadr/`), over contract G2 section 6 and M4's
    list:
    - the fields (`uc-parameters.lisp`), and every data type dispatch at 64
      entries and the map-bit ones at 128 (G2 section 2.4); OAL fields of
      6 bits and a 12-bit dispatch address; the LC and interrupt-control
      flags 8 bits higher (A1.6: sequence break 34, interrupt enable 35,
      need-fetch 39);
    - **fixnums of 32 bits** with the overflow condition (`uc-arith.lisp`,
      `FIXPACK-T`, `FIXPACK-P`, `fix-overflow-33`, `fixbox-t`, `fixbox-p`;
      `D-FXOVCK` and the 25-bit sign extension gone); a bignum's one digit
      is always a fixnum, and so is -2^31, whose magnitude takes two digits
      (`bcleanup-2-digits`, `uc-arith.lisp:4210`); `ASH` of a fixnum to the
      left, with no headroom above 32 bits, shifts in the word when bits 31
      to 31 − n all equal the sign, and takes the bignum path otherwise
      (`XASH2`, `uc-logical.lisp:363`);
    - **family 4 rewritten** (G2 section 2.7): each operand a dispatch on its
      data type that falls through for `DTP-FIX`, and the overflow
      condition (`uc-macrocode.lisp`, `d-fixnum-else-qind1`, `-qind2`);
    - **arithmetic takes M's tag** (G2 section 2.2): where the tag came from
      the A side, the sum is made first and the tag added by a logical
      function or a `DPB`: bignum headers (nine sites, `ADD` to `IOR`),
      `G-L-P`'s list pointer (`XGLOP1`, `uc-array.lisp:1431`), the cons
      caches' free pointers (`uc-storage-allocation.lisp:219`, `:266`), the
      array-leader and `ART-32B` headers, `MVRC`'s locative
      (`uc-call-return.lisp:1224`) and the Chaosnet bit count;
    - **constants zero-extended from 32 bits** (A1.5): `FILL-WITH-THINGS`
      took its cdr code, cdr-next, from `(A-CONSTANT -1)`, which now has no
      cdr code, so every `MAKE-LIST` list was cdr-normal
      (`uc-storage-allocation.lisp:1062`);
    - **the rotator is a ring of 40** (A1.2): a right rotate by n is 40 − n,
      50 octal less n, in `LDB` and `DPB` by run-time byte pointers
      (`uc-fctns.lisp`, `uc-array.lisp` `QBFXIT`, `uc-hacks.lisp`), `LSH`,
      `ROT`, `ASH`, the bignum shifts (`BIDIV-NORMALIZE-ENCODE-SHIFT`,
      `BIGNUM-RIGHT-JUST-FFO`, the unnormalize loops, `GCDBB`), `GCD`'s byte
      pointer, the address space map's byte, and the display's
      `%DRAW-CHAR`, `SELECT-SHEET`, the mouse cursor's second column and
      `BITBLT`, whose source rotate is taken mod 40 and whose byte pointers
      keep the word's bit offset mod 32 (`uc-tv.lisp`, `BITBLT-INNER-LOOP`,
      `:687`); M memory holds two constants, now 40 and 50, and the 31. and
      24. that were the others are made from 40 (`M-A-1`) or become 40;
    - **the map and paging** for 28-bit addresses and 1024-word pages, one
      map entry and one command-list entry a page (A1.7, A1.11;
      `uc-page-fault.lisp`, `uc-disk.lisp`): level 1 by `VA<27:15>` with the
      invalid block 177 and its reverse map at 2400-2577 (A1.8), level 2 of
      28 bits; a reference whose address has `<31:28>` set halts at the new
      `ADDRESS-PAST-28-BITS` (`uc-page-fault.lisp:524`), placed where nothing
      falls into it; the page hash from `VMA<27:16>`; the band's pages 5
      blocks, packed;
    - **the boot** (`uc-cold-disk.lisp`): the revision check asks for 13
      and halts at `MACHINE-NOT-QUUX-13` below it (G2 section 2.8); the
      initial map for the 7-bit level 1; the GPT read by 4-byte transfers
      and compared with fixnum constants (A1.11); `%DISK-SAVE` writes band
      format 2000 as a fixnum, and the restore takes the fixnums 2000 and
      2002, halts at `INCREMENTAL-BAND-NOT-SUPPORTED` for 2001 and at the
      new `BAND-NOT-40-BIT` for anything else (A1.12);
    - `SIZE-OF-HARDWARE` and the dispatch memory at 4,096 (A1.4), the
      I/O region and A memory's window (`uc-cadr.lisp`), the register page
      at 1777777400 and the run light at 1760000036.
  - **Boot PROM 2001** (`sys/ucadr/promh.text`): every disk read is a
    4-byte transfer of a page, four blocks, into the buffer, physical page 3
    (A1.11); a fixnum zero, made before the constants, under `A-1` to `A-4`,
    the GPT's signature words, the microcode's type word and the entry size,
    and ordering tests for the counts read from disk; the self-test's add
    with its ones on the A side; the 7-bit level-1 and 28-bit level-2 maps
    cleared and written as A1.7 says, virtual page 0 the buffer, 1 the
    system communication area for the CCW at 2377, 2 the register page at
    virtual 5400; interrupt enable at bit 35; the dispatch memory's 4,096
    entries; A memory as section 5 (A1.12), and a section 4, A memory at 32
    bits, halts at the new `ERROR-A-MEM-SECTION-32-BITS` (G2 section 2.8).
  - **Lisp**: the register page is `#o17777400` from the I/O region's base
    (`FEATURE-PAGE-XBUS-ADDRESS`, `sys/sys/ltop.lisp`; MINI's constants,
    `sys/cold/mini.lisp`; the keyboard, mouse, Chaosnet, disk status and
    screen-control addresses), and the frame buffer's physical base
    1760000000 (`VIDEO-BUFFER-ADDRESS`).
  - **The cross build**: `cross-check-formats` lets
    `%%ADI-PREVIOUS-ADI-FLAG` move with the cdr code
    (`cross-format-exceptions`, `sys/cold/cross.lisp`), since neither the
    compiler nor the FASL format holds it; `cross-dump-symbol-value` dumps
    the value file's symbol with its package's prefix, so that the cold
    load's `FONTS:CPTFONT` is the one the font file sets (it made a second
    symbol, and the cold-load stream stopped on the unbound one);
    `tools/cross-check/cases/prime.cases` expects the tree's 40-bit
    parameters.
