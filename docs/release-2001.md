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
