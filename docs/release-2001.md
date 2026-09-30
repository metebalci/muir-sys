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
