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
