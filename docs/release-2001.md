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
- **A compiled `(and x t)` returns `t`, not `x`** (`p2andor`,
  `sys/sys/qcp2.lisp:1725-1742`). Pass 2 dropped a trailing `t` from every
  `and`, so the compiled form returned `x` itself when it was non-nil, while
  the interpreter returned `t`; System 100's band does the same, so the rule is
  MIT's. The trailing `t` is now dropped only when the value is ignored. So
  `error-table-file-p` (`sys/eh/eh.lisp:2325`), compiled with this compiler,
  returns `t` rather than the truename; its callers use only its truth.
- **A compiled `(or (values x 2) nil)` passes one value, not two** (`p2andor`,
  `sys/sys/qcp2.lisp:1731-1742`, `1750-1753`). Pass 2 dropped every `nil` from
  an `or`, the trailing one too, so the form before it became the last form
  and passed all its values: under `multiple-value-list` or as a compiled
  function's value, `(or (values x 2) nil)` gave `x` and `2`, where the
  interpreter gives `x` alone, since only an `or`'s last form passes multiple
  values. System 100's band does the same, so the rule is MIT's. A trailing
  `nil` is now dropped only when one value is wanted (no multiple-value
  target, and not the function's return); `nil`s before the last form are
  dropped as before.
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
- **A full GC leaves every region in the address space map.** The cold
  load gives its last area, `FASL-TEMP-AREA`, a region of no length:
  `CREATE-AREAS` ends the areas at that area's origin, and a region's
  length is its area's bound less its origin (`sys/cold/coldut.lisp:604-618`,
  `:686-687`; the sort at `:1448-1449` expects it). In Y5's band of System
  2001 it is region 41, at 999424, the origin of region 42. `FREE-REGION` and
  `UPDATE-REGION-PHT` (`sys/ucadr/uc-storage-allocation.lisp`) step through a
  region's quanta and pages testing at the end of each loop, so for a region
  of no length they stored 0 in the address space map for the quantum at its
  origin, and called `XCPGS0` on the page below it, both another region's.
  A full GC frees that region once `FASL-TEMP-AREA` has a second one
  (`GC-RECLAIM-OLDSPACE`, `sys/sys2/gc.lisp:439-443`), an area at a time,
  with other processes running between areas; when one of them had made a
  region at that quantum in between, the new region dropped out of the map,
  and the next `ROOM` or GC signalled "The argument AREA was NIL, which is
  not an area number" (`GC-GET-SPACE-SIZES`, `sys/sys2/gc.lisp:189`), or a
  reference that missed the map halted at `GET-MAP-BITS`, "Region not found"
  (`sys/ucadr/uc-page-fault.lisp:306`). Both loops now return first for a
  region of no length (`sys/ucadr/uc-storage-allocation.lisp:884-891`,
  `:897`, `:919-923`). MIT's, in microcode 323 as well; the CADR's line has
  the same fix. `tools/microcode-check/run zero-length-region` frees the
  region as the GC does: on Y5's band and microcode 2001 it answers
  `(NIL T NIL)` in its third case (the quantum gone from the map, the page
  below gone from the page hash table) and `ROOM` signals "The argument AREA was NIL", on the
  micro and rtl engines, and with the fix all four cases pass on both.
- **The fix adds two control-store words**, one before `FREE-REGION-1` and
  one before `UPDATE-REGION-PHT-0`, so every word from `FREE-REGION-1` on is
  one location later and from `UPDATE-REGION-PHT-0` on two; every symbol of
  Y5's microcode 2001 is at the same place once moved, but for the new label
  `FREE-REGION-2`. The number stays 2001. Assembled twice from the sources,
  byte for byte the same, the outputs are (sha256):
  - `ucadr.mcr` `faf8ca9cc39077f4f430952c40ec178fa97d3a06b712ea2397e7921ad314e81a`
  - `ucadr.tbl` `c3aca75df862767a1c4ec600644a43de8c3e20b780c4e5b3d956d01007e09c09`
  - `ucadr.locs` `da13f170e32c9c5c738880a8f3f779b1dca5b9b472ee50e0a024ca6b6d2248e9`
  - `ucadr.sym` `2f7d93afa290b35a9260f8033762bb182f4677786a0974990da47c5450a902c0`

  Boot PROM 2001 is unchanged. On Y5's band with them, system-check passes
  93 of 93 and microcode-check 174 of 174 (Y5's 170 and the new four), on
  the micro and rtl engines.
- **No fixnum is sign-extended any more** (contract G2, section 6.1). MIT's
  microcode sign-extended a fixnum before arithmetic, copying its sign bit
  over the tag through `OA-REG-HIGH`, which turned `M-ZERO` into
  `M-MINUS-ONE`: `SIGN-EXTEND-M-1` (reached through `FXUNPK-P-1`),
  `FXUNPK-T-2`, `FIXGET-1`, `GET-ANY-CHAR`, `GET-CHAR-FIX`, `GET-FIX-ANY`
  and `XDIVD1` (`sys/ucadr/uc-arith.lisp`). At 40 bits a fixnum is the
  whole 32-bit field, arithmetic and the order conditions act on `<31:0>`,
  and the overflow condition finds a sum past 32 bits, so nothing needs the
  extension; and since constants and initial values are zero-extended
  (A1.5), both locations have `<39:32>` zero, so all it did was clear the
  tag. One `Q-POINTER` word does the same, and each of them is now that
  word (`sys/ucadr/uc-arith.lisp:24-32`, `:399-415`, `:549-552`,
  `:683-711`). The arithmetic type dispatches `D-NUMARG`, `D-NUMARG1` and
  `D-FIXNUM-NUMARG2` fall through for a fixnum or a character instead of
  calling the two unpackers (`sys/ucadr/uc-arith.lisp:1810`, `:1834`,
  `:1850`, `:1874`, `:1891`, `:1915`), and each of their 47 callers unpacks
  the argument in one word after the dispatch (the 1- and 2-argument
  functions and comparisons in `uc-arith.lisp`, `QIAND0` and its kin,
  `XBOOLE0` and `XASH` in `uc-logical.lisp`, `XEQUAL-XNUM`, `XLDB` and
  `XDPB` in `uc-fctns.lisp`); the direct calls in `XSCALE-FLOAT`,
  `XFLOOR-1-CEIL`, `XFLOOR-1-FLOOR`, `QDIV`, `ARITH-ANY-FIX`, `BFXDIV` and
  `XASH` became that word too. `FXUNPK-P-1` and `FXUNPK-T-2` stay, a
  `Q-POINTER` word and a return, for `GET-32-BITS`, `GET-FLONUM`,
  `%GC-CONS-WORK` and the triangle drawing in `uc-hacks.lisp`. `XABS` and
  `XFIX` box a fixnum through `fixbox-t` rather than `FIXPACK-T`, since the
  word before is now the unpacking byte word, which does not load the
  overflow flag (`sys/ucadr/uc-arith.lisp:1181-1185`, `:1276-1280`;
  `tools/microcode-check/fixpack-flag.py` passes). The 25-bit range checks
  and `D-FXOVCK` were already gone; the inline sign extension in the mouse
  tracking (`uc-track-mouse.lisp:229-230`, `:250-251`), a scale factor
  for `MPY`, is left as it is.
  - Over the 12 workloads of G2 S4's comparison (muir-sim's profile, rtl,
    K=4, the 4K cache, Arty timing, 2 M words), the microinstructions
    executed drop from 348,651,568 to 341,336,206 (−7.32 M, −2.10%), the
    microcycles by 2.34% and the time by 2.26%. The labels the change
    touched account for −6.17 M: `SIGN-EXTEND-M-1`'s 4.57 M,
    `FXUNPK-T-2`'s 2.73 M and `FXUNPK-P-1`'s 2.29 M less the 3.65 M of
    the unpacking words at the callers, and `GET-ANY-CHAR`'s 0.17 M; the
    other −1.14 M is elsewhere (paging, the disk, the main loop), since the
    runs no longer keep step and execute 0.24% fewer macroinstructions.
  - `tools/microcode-check/cases/fixnum-boundaries.cases` (new) takes
    `+`, `-`, `*`, `1+`, `1-`, `ASH`, the comparisons and `=`/`EQL`,
    the one-argument functions, the logical functions, `LDB`, `DPB`, the
    divisions, a bignum with a negative fixnum and characters, at
    2147483647 and -2147483648 and with negative operands, interpreted and
    compiled: 28 cases, which pass on microcode 2001 before the change and
    after it, on the micro and rtl engines. A partial change fails: of
    seven mutants assembled from the change, the six that leave out the
    unpacking at some callers (all of `D-FIXNUM-NUMARG2`'s, all of
    `D-NUMARG`'s, seven or six sites, or `QIMUL`'s second argument alone)
    or unpack without `Q-POINTER` (the tag kept) do not boot, the system's
    own arithmetic going wrong before its TELNET server answers; the
    seventh, `XHAUL`'s unpacking alone left out, boots and fails the
    `HAULONG` case. The change itself, run the same way, passes all 28.
  - The change moves most of the control store: 58 words more, every
    label from `FIXGET-1` on moves, and `SIGN-EXTEND-M-1` is gone. The
    number stays 2001. Assembled twice from the sources, byte for byte the
    same, the outputs are (sha256):
    - `ucadr.mcr` `be9f99719a4c6ef52cdfe5f0f2ecfa88c3ea0dc576e7701e41c781e0ea2190a2`
    - `ucadr.tbl` `0feeefd69430eebdec9894b489a9eb6ab64a04df5803b582d6e21760991f3b35`
    - `ucadr.locs` `e3328f6dd5257878b72586b2e93829e90f35e015e1c44cb935c34a69fa895068`
    - `ucadr.sym` `b9d93e3d4fe2ab82d86d416a3a7b4c3f8df693eeeba208ff903ed0ae3a4289eb`

    Boot PROM 2001 is unchanged. On Y5's band with them, system-check
    passes 93 of 93, microcode-check 202 of 202 (174 and the new 28), and
    System 2000's band cases 30 of 33 (the three not applicable, as
    before), on the micro and rtl engines.
- **A bignum minus or times -2^31, the most negative fixnum, is right
  again.** With 32-bit fixnums the magnitude of -2^31 is 2^31, which is no
  fixnum, and negating -2^31 in a 32-bit register gives -2^31 back.
  `BFXSUB`, a bignum minus a fixnum, negated the fixnum and went on as a
  bignum plus a fixnum, which took the -2^31 for a negative addend and
  subtracted its magnitude: `(- (expt 2 40) most-negative-fixnum)` was
  2^40 - 2^31 and `(- (expt 2 31) most-negative-fixnum)` was 0.
  `BFXMPY-OK`, a bignum times a negative fixnum in either order, negated
  it for `MULTIPLY-ONCE`, which got 20000000000 in `M-2`, no positive
  32-bit multiplier: `(* (expt 2 40) most-negative-fixnum)` was
  -9903517953099800764370386944. `FLOOR`, `CEILING`, `TRUNCATE`, `ROUND`
  and `MOD` make their remainder from the quotient through `QIMUL` and
  `QISUB` (`XFLOOR-2`, `sys/ucadr/uc-arith.lisp:1527-1546`), so their
  remainders went wrong too. Addition, the fixnum minus the bignum, the
  divisions, the comparisons and the rest were right. Now `BFXSUB` sends
  -2^31 straight to `BFXADD-1` as the magnitude 2^31 to add, which
  `BADD5` and `BSUB-C` take as an unsigned 32-bit digit with its carry, as
  a bignum plus -2^31 already did (`sys/ucadr/uc-arith.lisp:3991-3998`,
  `:4013-4016`); `BFXMPY-OK` sends it to the new `BFXMPY-SETZ`, which
  makes the product as the bignum's digits moved up one 31-bit place over
  a zero digit, the sign changed (`:4073-4078`, `:4106-4128`).
  - `tools/microcode-check/cases/bignum-fixnum-extremes.cases` (new, 119
    cases) takes 14 bignums from 2^31 to four digits, both signs, with
    -2147483648 and 2147483647: `+`, `-`, `*`, `QUOTIENT`, `REMAINDER`,
    `MOD`, `<`, `>`, `=`, `EQL` and `EQUAL`, then `FLOOR`, `CEILING`,
    `TRUNCATE`, `ROUND`, `GCD`, `LOGAND`, `LOGIOR`, `LOGXOR`, `MAX`, `MIN`
    and `CLI://`, the bignum first and the fixnum first, in an interpreted
    function and a compiled one, against values computed outside the
    machine. On microcode 2001 before the fix, 41 of them fail on the
    micro engine: the three forms above, and with -2^31 `(- b f)`,
    `(* b f)` and `(* f b)` for all 14 bignums, and the remainders of
    `MOD` and `FLOOR` for 5, `TRUNCATE` and `ROUND` for 4 and `CEILING`
    for 3, interpreted and compiled alike; nothing with 2147483647 fails.
    With the fix all 119 pass, on the micro and rtl engines.
  - The fix adds 18 control-store words, so every label from `BFXSUB` on
    moves. The number stays 2001. Assembled twice from the sources, byte
    for byte the same, the outputs are (sha256):
    - `ucadr.mcr` `b648486fba5fbeec8823fd1419e79b263db958031fa97317b0c0f57b15b7f292`
    - `ucadr.tbl` `ebf33853747ac3d7c0357210d7613b62c13c3bdf68f47dc48b1a80a9d7c2db8d`
    - `ucadr.locs` `904b96babea4de1397ab1f71768ec37b0e718bc7dc88cbab2bbb1a74e9c48d09`
    - `ucadr.sym` `3dbf06bc6f178756ee1dead271f3baa3ac80f0ff5d108e123dd6826ce2e4d923`

    Boot PROM 2001 is unchanged. On Y5's band with them, system-check
    passes 93 of 93, microcode-check 321 of 321 (202 and the new 119), and
    System 2000's band cases 30 of 33 (the three not applicable, as before),
    on the micro and rtl engines (on rtl the new cases ran in four parts,
    each from a fresh start, since a long run there slowed to minutes a
    case). The CADR's line does not have the fault:
    there a fixnum is 25 bits in a 32-bit register, so -2^24 negates to
    2^24, and the same cases scaled to -16777216 and 16777215 pass, 135 of
    135, on the CADR's current band and microcode.
- **A machine whose `sys/` holds no `ubin/ucadr.tbl` boots on the band's
  own error table.** Since System 1002 `EH:INITIALIZE` forgot the band's
  cached table at every boot, so every boot read `SYS: UBIN; UCADR TBL`,
  and with the file absent (an empty `sys/`, or one without `ubin/`) the
  boot stopped at "LOAD could not find any file related to HOST:
  /sys/ubin/ucadr.tbl", asking for a pathname. `EH:INITIALIZE`
  (`sys/eh/eh.lisp:2422-2432`) now forgets it only when the file can be
  read (`error-table-file-p`, `sys/eh/eh.lisp:2322-2329`, which counts a
  missing file or directory, `FS:FILE-LOOKUP-ERROR`, as absent; the
  pathname is `error-table-pathname`'s, `:2317-2320`, which
  `LOAD-ERROR-TABLE` loads, `:2308-2315`). Without the file the band's own
  table, the one its build loaded, is kept when it is for the running
  microcode's version, and the console says so:

  ```
  [No error table file for microcode version 2001; using the band's own]
  ```

  For another version the load fails as before. A served file is still
  read at every boot. The CADR's line has the same change.
  - A band built as Y5's was holds the table: read back from Y5's saved
    band, `EH:MICROCODE-ERROR-TABLE-VERSION-NUMBER` and
    `EH:ERROR-TABLE-NUMBER` are 2001 and `EH:ERROR-TABLE` holds 345
    entries, all 345 in the table of Y5's microcode and 82 of them in
    that of the microcode before this change (`b648486f`). So a band
    booted without the file uses the table of the microcode its build ran
    on, which is right only when the running microcode's `ucadr.tbl` is
    that one.
  - On a band built with the change as Y5's band was (this `eh.lisp`
    compiled on Y5's band, `MAKE-COLD` into LOD3, QLD on microcode
    `b648486f` at 32 M words and the save to LOD4; its cached table is
    that microcode's, 345 of 345), booted with no `ucadr.tbl` and with an
    empty `sys/`, the boot completes, prints the line, and `(car 1)`
    reports "The argument to CAR, 1, was of the wrong type"; Y5's band
    stops at the question above. With the file served it prints
    "[Loading error table for microcode version 2001]", and a served table
    with one entry added is the one in use (706 entries, the band's 705,
    and the added restart in `EH:RESTART-LIST`).
  - `error-table-file-p` returns the file's truename, not `T`: the
    compiler compiles `(and x t)` as `x` (a compiled
    `(defun f (x) (and (car x) t))` returns 5 for `'(5)`). Its one caller
    tests it for `NIL` only.
- **The cold boot unmaps the physical-page-data table's unused tail.**
  `REGION-ORIGIN` lies below `PAGE-TABLE-AREA` (`cold/qcom.lisp`,
  `AREA-LIST`), at 4096 against the table at 8192 and physical-page-data
  at 139264, so `COLD-REINIT-PPD-0`'s fill of the table with -1 and
  `BEGCM1`'s loop that takes the table's unused pages out of the map, both
  bounded by it, never ran. The fill wrote -1 into the word below
  `REGION-ORIGIN`, the last of `MICRO-CODE-SYMBOL-AREA`, where the area
  holds its fill word, and stopped. With less memory than the table's 32
  M words, the table's entries past the memory's pages kept the band's
  words and its pages past them stayed mapped to their own frames, while
  `COLD-REINIT-PPD` gave those frames to paging: each such frame was
  reachable at two virtual addresses. Both loops are now bounded by
  `ADDRESS-SPACE-MAP`'s origin, the table's end
  (`sys/ucadr/uc-cold-disk.lisp:1293-1299`, `:1417`, `:1422`), and the
  unmap starts at the table's valid end rounded up to a page
  (`:1402-1409`): MIT's "its page plus one" skipped the end's own page
  when the end fell on a page boundary, as it does with any multiple of
  16 boards. MIT's, in microcode 323 as well; the CADR's line has the same
  fix.
  - Measured on Y5's band at 256 boards (16 M words), before: all 16384
    entries past the memory's kept the band's words, none -1; all 16 pages
    from 152 on were mapped to their own frames, each frame holding a page
    paged in; a word written through page 152 was read changed through
    virtual page 2905, the page in frame 152. At 300 boards the same for
    the 14 pages from 154. At 512 (32 M words, the default) the table is
    full and has no tail. With the two comparisons alone, 15 of the 16
    pages at 256 boards left the map and page 152 stayed mapped, the alias
    still there; with the start rounded up as well, none stays, the write
    through page 152 is not seen through page 2905, and at 300 boards page
    154, which holds valid entries, stays mapped and the 13 above it do
    not. The word below `REGION-ORIGIN` keeps its fill word. The paging
    and full-GC workload of the next entry passes at 256 and 512 boards.
- **The cold boot's memory probe stops below the frame buffer's window,
  and memory is capped to the band's tables before its size is stored.**
  - `MEM-SIZE-LOOP` had no stop. It now stops at 1760000000, where
    revision 13's frame buffer window begins: main memory is below it, and
    the window reads back what is written, so it would be counted as
    memory after a memory that reached it
    (`sys/ucadr/uc-cold-disk.lisp:840-844`, `:849`). No memory muir-sim
    gives reaches it (1024 boards, 64 M words, end at 400000000); built
    with the stop at 100000000 instead, the microcode finds 16384K on 512
    boards, so the stop is taken.
  - The page table's size was capped to its area after
    `%SYS-COM-MEMORY-SIZE` was stored, so with more memory than the
    tables serve Lisp saw all of it: at 600 boards the herald said 38400K
    and at 1024 65536K, and `COUNT-WIRED-PAGES` read 32768 entries past
    physical-page-data at 1024 (1195 fixed wired pages, against 172);
    `SET-SCAVENGER-WS` and a warm boot's `WARM-READ-GPT` take their extent
    from the same size. The cold boot now caps the memory to what the
    band's own tables serve, a physical-page-data word and 4 page-table
    words a page, before it stores the size, as the CADR's line does
    (`:1259-1289`): 32 M words with this tree's tables, and a band with
    smaller tables uses that much of a bigger machine. The later cut of
    `M-S` to the page table's size is commented out, as it no longer
    applies (`:1326-1329`).
  - The page table's size, 4 words a page, is rounded up to a power of
    two (`:1301-1315`), as the CADR's line decided: `COMPUTE-PAGE-HASH`
    masks the hash to the size's power of two and wraps what is past the
    size once, so a size between two powers got twice the hashes on its
    first words. Its "times 4", a left shift, brought in `Q<31>`, which is
    1 at that point on revision 13, so the size was 4 times the pages plus
    one, a page more once rounded; it is a byte now (`:1297-1300`).
  - `COLD-SWAP-IN` starts the end of the valid physical-page-data entries
    at the table's origin and the findcore and aging scan pointers at page
    0 (`:1357-1366`), as the CADR's line does: they were set only when the
    microcode was loaded and on a warm boot, so after `%DISK-RESTORE` they
    kept the previous world's, wrong when that world's table was elsewhere
    or larger. Every 40-bit band has its tables at the same place, so no
    restore here showed it, and none was run.
  - Measured on Y5's band, micro, before and after (the paging and full-GC
    workload: a 2,000,000-word array filled, checked, kept through a full
    GC, checked, dropped and GC'd again; the paging partition holds 13 M
    words, so it cannot outgrow main memory here; probe lengths in words
    from a resident page's hash to its entry, after the second GC):

    | boards | memory found | page table, words | wired | probes, mean / max |
    |---|---|---|---|---|
    | 256 | 16384K / 16384K | 66560 / 65536 | 134 / 133 | 4.52 / 1790 → 5.86 / 1004 |
    | 300 | 19200K / 19200K | 77824 / 131072 | 148 / 200 | 2.05 / 108 → 1.73 / 6 |
    | 512 | 32768K / 32768K | 131072 / 131072 | 213 / 213 | 3.11 / 14 → 3.11 / 14 |
    | 600 | 38400K / 32768K | 131072 / 131072 | 213 / 213 | not run |
    | 1024 | 65536K / 32768K | 131072 / 131072 | 1236 / 213 | 2.93 / 14 → 3.11 / 14 |

    At 256 boards "before" is with the previous entry's change alone,
    which does not touch the page table. Before the change the page table at 256 and 300 boards was folded, the
    first 64512 and 53248 of its words taking two hashes each; after it
    no size is. A 300-board machine wires 52 more pages for the larger
    table. The long probes at 256 boards, before and after, come from the
    hash at a table of 65536 words with the band's pages, not from a fold.
    The full GC takes 32.0 to 32.1 s of machine time at every size, before
    and after, and every case of the workload passes.
  - This entry and the previous one move every label from `MEM-SIZE-LOOP`
    on; `ucadr.tbl` is unchanged, so a band built on the microcode before
    them holds this microcode's error table too. The number stays 2001.
    Assembled twice from the sources, byte for byte the same, the outputs
    are (sha256):
    - `ucadr.mcr` `ba3d9fe044ca4fdbd09d623d71b550b4400dc416f40faec9cc73bf74a7286eac`
    - `ucadr.tbl` `ebf33853747ac3d7c0357210d7613b62c13c3bdf68f47dc48b1a80a9d7c2db8d`
    - `ucadr.locs` `0b52148627b9a0f1f9432dba2950a95bf2ea189e0f0c7c6e41b3df4635a1610a`
    - `ucadr.sym` `a33a14e2ec514fd5ed4f7a0d73c0eaf78f5c09bdda1b3f335dd64f08ecfb0469`

    Boot PROM 2001 is unchanged. On the band built for the error table's
    entry above, with them, system-check passes 93 of 93,
    microcode-check 321 of 321 and System 2000's band cases 30 of 33 (the
    three not applicable, as before), on the micro and rtl engines (on rtl
    each case file ran from a fresh start, and `bignum-fixnum-extremes` in
    twenty, since a long run there slowed to minutes a case); booted with no `ucadr.tbl` it prints that entry's line
    and `(car 1)` is right.
- **`GCD`, `\\`, `LCM`, `\`, `REMAINDER` and `CLI:REM` with a float
  signal the wrong-type error instead of halting the machine.** A single
  float is an immediate on revision 13 whose pointer field holds its bits
  (`#x3FC00000` for 1.5), past the 28-bit address space. `GET-BIG-FIX` and
  `GET-ANY-BIG`, which `XGCD` (`INTERNAL-\\`) and `XREM` (`\`) reach
  through `GET-FIX-OR-BIGNUM` for an argument that is neither a fixnum nor
  a character, started a read at that field before `ASSURE-BIGNUM` tested
  the type, and the machine halted at `PGF-MAP-MISS` (PC 24173):
  `(gcd 1.5 2)`, `(gcd 2 1.5)`, `(\ 7 1.5)`. Now the callers only set
  `M-I`, and `ASSURE-BIGNUM` starts the read after its type test
  (`sys/ucadr/uc-arith.lisp:422`, `:434`, `:447`, `:456-467`; `GET-32-BITS`,
  `:482`, the same), so a float gets the "fixnum or a bignum" error that a
  symbol or a rational gets, as on the CADR. `CLI:REM` compiles to `\`
  and so takes no float, here as on the CADR.
  - `tools/microcode-check/cases/integer-ops-on-floats.cases` (new, 227
    cases): `GCD`, `\\`, `SYS:INTERNAL-\\`, `LCM`, `\`, `REMAINDER`,
    `CLI:REM`, `MOD`, `LOGAND`, `LOGIOR`, `LOGXOR`, `%DIV`, `ASH` and
    `LDB`, each with 1.5, `1\2`, `(int-char 97)` and `'foo` in each integer
    position, interpreted and in a compiled function, with two bignum
    controls through `ASSURE-BIGNUM`. On microcode 2001 before the fix the
    machine halts at the first float case, `(gcd 1.5 6)`; run one by one,
    the 28 float cases of the first seven functions halt and every other
    case answers as after the fix. With the fix all 227 pass.
  - The fix adds one control-store word, so every label from `GET-32-BITS`
    on moves, and `ucadr.tbl` changes. The number stays 2001. Assembled
    twice from the sources, byte for byte the same, the outputs are
    (sha256):
    - `ucadr.mcr` `8dd5369452afc40a9ecbf40a0fb8953fda8318006bc5b8be941ecccf0d3e9154`
    - `ucadr.tbl` `b9f10afe306187f29a0e299d320088b1c9601eb0e920289bde7489de67f06efc`
    - `ucadr.locs` `b73d818a579fc25d74f775fb6b7afcbdee43a6dd4b1eebd240c5f2d61a44e648`
    - `ucadr.sym` `b57e8f81cc65d03ea6ad3b7478c13abd553a8a1dc49d413729179d65ad0c8017`

    Boot PROM 2001 is unchanged. On the band built for the error table's
    entry above, with them, system-check passes 93 of 93, microcode-check
    548 of 548 (321 and the new 227) and System 2000's band cases 30 of 33
    (the three not applicable, as before), on the micro and rtl engines (on
    rtl each case file ran from a fresh start, the new one in four parts
    and `bignum-fixnum-extremes` in twenty, and the runs that stalled under
    host load ran again). The CADR's line does not halt: on its current band
    and microcode the 28 cases that halted here signal the same errors, as
    do the same functions with its small float `1.5s0`, and `CLI:REM`
    takes no float there either.
- **The page hash table stays spread under the incremental GC at 32 M
  words.** At 32 M words the incremental GC slowed from about 1.5 s to 10-19
  s for each 100K words consed, with stalls of 57 and 130 s, after four to
  eight flips, while the paging meters did not change: the page hash table
  held runs of 10,000 entries, and a search for a page not in it took 1,000
  probes. At 2, 8 and 12.5 M words it did not.
  - The cold boot entered the free pages every other entry down from the
    table's top, in frame order (`COLD-REINIT-PPD-3`,
    `sys/ucadr/uc-cold-disk.lisp:1394-1397` before), and findcore takes
    free pages in frame order (`FINDCORE0`,
    `sys/ucadr/uc-page-fault.lisp:981`), so it emptied the table an eighth
    at a time from the top. `FREE-REGION` (`XFREE-REGION`,
    `sys/ucadr/uc-storage-allocation.lisp:858-866`) made each freed page's
    entry a free page's in place (`XCPGS0`, the two lines now commented
    out at `sys/ucadr/uc-page-fault.lisp:1696-1697`), on the slot its virtual
    page had hashed to. With 25,000 of the 32,768 frames free, the eighths
    findcore had not reached kept their cold-boot entries and gained these,
    and went to 94-100% full. Dumps of the whole table every 2 blocks of a
    reproducer (80 blocks of 100K words, 7 to 8 flips) show it: findcore
    took 4096 entries from each of the top six eighths and 143 from the
    bottom two, and 18641 entries were made in place, 14178 of them not
    taken again by the end. `PHTDEL`'s rule that a free page's entry moves
    into any hole (`:1266`) moved tens to hundreds of entries a flip and is
    not the cause.
  - Now `XCPGS0`'s free-region path deletes the freed page's entry
    (`COREFOUND2`, `PHTDEL`) and enters the frame anew as a free page with
    `XCPPG1` at the first hole from the frame's hash xor 4 entries
    (`sys/ucadr/uc-page-fault.lisp:1698-1725`), and the cold boot puts each
    free page there too (`sys/ucadr/uc-cold-disk.lisp:1396-1418`). Each half
    alone fails: with the free-region path alone the table degenerated as
    before (longest run 11009, 930 probes a miss at block 80), with the
    cold boot alone later (2046 and 40, growing). Hashed by frame,
    consecutive frames spread over the table. At the hash itself every real
    page's slot held a free page, since the hash of a frame and of a
    virtual page from the same 128-page block start at the same offset in
    their 8-entry group (1334 of 1334 at the prompt, 4.6 probes a hit
    against 1.5); xor 4 takes the group's other half. MIT's, in microcode
    323 as well; the CADR's line has the same fix.
  - Measured with that reproducer, micro (longest run / probes a miss /
    probes a hit, at block 80): before, 11262 / 993 / 224 (a repeat 11281 /
    1005 / 312), from 2883 at the fourth flip; after, 14 / 2.0 / 1.1. Over 300
    blocks (26 flips) after, at most 16 / 2.2. At 2, 8 and 12.5 M words
    (100 blocks) after, at most 91 / 3.2, 22 / 2.3 and 7 / 1.7, where before
    it reached 303 / 13, 1837 / 106 and 455 / 7 for a while. In dumps taken
    without interrupts, before and after, no entry is out of a search's
    reach and no page is in the table twice.
  - The fix adds 26 control-store words, 17 in `XCPGS0`'s free-region
    path and 9 at `COLD-REINIT-PPD-3`, so every word from `XCPGS3` on is 17
    locations later and from `COLD-REINIT-PPD-4` on 26; A-memory and the
    dispatch memory keep their size, and `ucadr.tbl` changes. The number
    stays 2001. Assembled twice from the sources, byte for byte the same,
    the outputs are (sha256):
    - `ucadr.mcr` `c00c3e7ac8e70e22ba91f844d4b4362e2505000ca028053f41a42215df664efd`
    - `ucadr.tbl` `ceb290d0ea917f814ec5a0d3d33b454bb2b765253411183b6ad986049deddebe`
    - `ucadr.locs` `0585902f0b06e5352cb67a8ce5c6dfa2bce38ebecabcac87c739f600eb8a96f2`
    - `ucadr.sym` `488f043d52e9d0b7e7cdfbf35462c525b4c45e3a71e1df40e22644ce3d18041e`

    Boot PROM 2001 is unchanged. On the band built for the error table's
    entry above, its microcode replaced by them, system-check passes 93 of
    93, microcode-check 548 of 548 and System 2000's band cases 30 of 33
    (the three not applicable, as before), on the micro and rtl engines (on
    rtl each case file from a fresh start, `integer-ops-on-floats` in four
    parts and `bignum-fixnum-extremes` in twenty, and the runs that stalled
    under host load ran again).
  - Measured on that band, micro: the reproducer at 32 M words keeps the
    longest run at 16 or less and a miss at 2.2 probes or less in all 41
    of its dumps (7 flips; at block 80, 14 / 2.0 / 1.1), and at 2, 8 and
    12.5 M words (100 blocks) at most 79 / 3.2, 37 / 2.4 and 7 / 1.7. In
    the paging and full-GC workload (a 2,000,000-word array filled,
    checked, GC'd while live, checked, dropped and GC'd again) the real
    pages' entries sit 14 words in all from their hashes after the fill,
    rather than 2270, and the array stays intact. A cold boot, a warm boot
    (Control, Meta and Return) that keeps a variable, `(si:disk-save 3 t)`
    and the saved band's run, a cold boot of the saved band and
    `(si:disk-restore 3)` work, and a boot with an empty `sys/` and `site/`
    uses the band's own error table.
  - The cost: freeing a region now takes each of its pages in the table
    out and enters its frame again. Per flip of the incremental GC,
    `GC-RECLAIM-OLDSPACE-AREA` took 37.2 ms of machine time rather than
    19.0 ms at 32 M words (about 2,800 pages in the table freed: 13.2 µs a
    page rather than 6.8), and 28.1 ms rather than 14.9 ms at 2 M words
    (about 650 pages). A flip's machine time, a run's time over its flips,
    is 13 to 22 s: at 32 M words 17.7 s after (40 blocks of 100K words, 3
    flips) against 13.5 and 14.8 s before (4 flips, the same blocks); at 2
    M words 22.3 s against 22.1 s (100 blocks, 8 flips). The same consing
    took 53.2 s rather than 54.0 and 59.2 s at 32 M words and 178.1 s
    rather than 177.2 s at 2 M words, and the workload's full GC 32.12 s
    rather than 32.06 s. Before the fix, 100 blocks at 32 M words left the
    TELNET connection unanswered for 180 s, and ozd closed it.
- **QUUX's disk has a PAGE partition of 128 M words** (Mete, 2026-10-03).
  System 2000's disk kept the CADR pack's block numbers, and its PAGE of
  65,246 blocks, 13,049 pages of 5 blocks, gave 13,362,176 words of virtual
  memory, fewer than revision 13's 32 M words of main memory: the herald
  said "13049K virtual memory", and at 32 M words the incremental GC found
  6.85 M words free against the 8.42 M words it commits, so `GC-ON` asked
  "Try garbage collecting after all?" on the query stream, which a TELNET
  session never answers. The new layout (`docs/building.md`, "Writing
  QUUX's release disk") has a PAGE of 655,360 blocks, 131,072 pages,
  671,088,640 bytes; MCR1, MCR2 and the bands keep their sizes and order,
  the bands moved up by 590,114 blocks, and the disk is 853,359 blocks,
  873,839,616 bytes, rather than 263,245. The CADR's pack is unchanged. No
  source changed: `DISK-INIT` takes the virtual memory from the PAGE
  partition's whole pages (`sys/io/disk.lisp:1461-1463`), bounded only by
  A memory's address, 258,047 pages; the microcode takes its bounds from
  the GPT's PAGE entry (`sys/ucadr/uc-cold-disk.lisp:1748-1755`;
  `MAKE-REGION`, `sys/ucadr/uc-storage-allocation.lisp:765`); the
  address-space map covers all 16,384 quanta of the 28-bit space; and an
  incremental band's page bitmap, now 4 pages, fits the 8-page buffer
  below the copy buffer (`sys/ucadr/uc-cold-disk.lisp:1123`, `:1878`).
  Measured on micro at 32 M words, the band of the page hash table's entry
  above and its microcode on a disk of the new layout: the herald says
  "32768K physical memory, 131072K virtual memory",
  `SI:VIRTUAL-MEMORY-SIZE` is 134,217,728, the free space 127,713,312
  words against 109,144,239 committed, and a case of `GC-ON` and
  80,000 conses returns `T` without asking, where on the old layout, the
  same band and microcode, it waits for the answer. System-check passes
  93 of 93 on micro and on rtl, and microcode-check 548 of 548 on micro; a full save
  (`(si:disk-save 3 t)`), an incremental save (`(si:disk-save 3 t t)`), a
  cold boot of each saved band and `(si:disk-restore 3)` work.
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
    31-bit digits (`store-bignum-40`, `:782-814`), each digit's word tag 000,
    the whole word being the digit (see "Bignum digits" below), and the band format is
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
  - **Range checks are unsigned** (appendix A1.3):
    the array decoders', `G-L-P`'s, the leader's, `COPY-ARRAY-PORTION`'s,
    `ARRAY-PUSH`'s fill pointer, the string searches', `XINSTANCE-LOC`'s and
    the colour map's bounds checks jump or trap on the new unsigned
    condition (`CALL-GREATER-OR-EQUAL-UNSIGNED`, and
    `CALL-LESS-THAN-UNSIGNED` with its operands exchanged for a "greater
    than"), so a negative index, which a 32-bit fixnum can now be, signals
    `SUBSCRIPT-OUT-OF-BOUNDS` and writes nothing (`sys/ucadr/uc-array.lisp`,
    `uc-string.lisp`, `uc-call-return.lisp`, `uc-hacks.lisp`); a negative
    destination start makes `COPY-ARRAY-CONTENTS` copy nothing (`XCARC1`), as
    a 25-bit fixnum's field did. `tools/microcode-check/cases/range-checks.cases`.
  - **`GCD` of -2^31** (`GCD-FIX-FIX`, `sys/ucadr/uc-arith.lisp`): its
    magnitude is no fixnum, and negating it gave -2^31 back; with 0 or itself
    the result is the bignum 2^31, and with any other number the gcd of 2^30
    and it. `tools/microcode-check/cases/gcd-setz.cases`.
  - **Counters Lisp reads as fixnums stay fixnums** (contract G2 section
    2.2: an arithmetic result takes M's tag): `ARRAY-PUSH`'s fill pointer
    (`XFARY-1`, `uc-array.lisp`), `%REGION-CONS-ALARM` and `%PAGE-CONS-ALARM`
    (`MAKE-REGION`, `uc-storage-allocation.lisp`), and the metering
    counters `%METER-DISK-ADDRESS`, `%METER-DISK-COUNT` and
    `%METER-BUFFER-POINTER` (`uc-meter.lisp`) are summed and then given the
    fixnum's tag by `DPB`; summed with `M-ZERO` or `M-MINUS-ONE` they took
    tag 000, and the next reference trapped. `tools/microcode-check/cases/typed-a.cases`.
  - **+2^31 as a bignum is two digits**, 0 and 1: `BIGNUM-MINUS`, `FXBMPY`,
    `REMAINDER-FIX-BIG` and `FXBIDIV` (`uc-arith.lisp`) looked for it as
    one digit, as +2^24 was, so negating it, and -2^31's remainder and
    quotient by it, gave a bignum -2^31 or a wrong answer; the literal
    -2147483648 now reads as the fixnum. `tools/microcode-check/cases/setz.cases`.
  - **`FIXPACK`'s flag rule** is checked: `tools/microcode-check/fixpack-flag.py`
    reads every jump to `FIXPACK-T` and `FIXPACK-P` and the word that last
    sets the overflow flag before it.
  - **32 M words**: the page hash table is 128 pages and physical-page-data
    32, enough for 32 M words (`sys/cold/qcom.lisp`), `EXTRA-PDL-AREA` 43
    pages, ending at 700000; the page hash table's index in
    physical-page-data is `<19:0>` and the GC data `<31:20>` (appendix A1.9;
    `uc-page-fault.lisp`, `uc-cold-disk.lisp`, `sys/sys2/gc.lisp`,
    `sys/sys2/describe.lisp`), no page `3777777`; the cold boot enters no more
    main memory than the table holds, rather than filling entries below its
    origin. The wired words now end at 530000, above the 64 K words that
    `%DISK-RESTORE` and `%DISK-SAVE` map directly before the band's own map
    is made, and the swap-in's CCW list goes above them; both map 256 K words
    (`DISK-RESTORE-1`, `SWAP-OUT-ALL-PAGES`, `uc-cold-disk.lisp`), since a
    level-1 miss there would use the reverse map that the band's page 1 has
    just overwritten. The cold load boots to its herald with 32 M words.
  - **The swap-in cap** is 4 pages again (`DISK-SWAP-IN-MAX-PAGES`,
    `uc-parameters.lisp`), 4096 words, as revision 12's.
  - **Lisp's disk transfers** (appendix A1.11; `sys/io/disk.lisp`): a CCW names
    a page, and a transfer is 4-byte unless `*DISK-TRANSFER-PACKED*`: an RQB's
    page is `DISK-BLOCKS-PER-PAGE` blocks and its bytes come back as the disk
    holds them. A band's pages and the paging partition's are packed,
    `DISK-BLOCKS-PER-PACKED-PAGE`, 5, blocks each (`sys/cold/qcom.lisp`, with
    `%DISK-COMMAND-4-BYTE`): a band's system communication area is read packed
    (`READ-BAND-SYS-COM`), its formats are 2000 and 2001 and its counts words
    of 32 bits; `PAGE-IN-WORDS` reads packed pages; `DISK-INIT`'s virtual
    memory is A memory's page, bits 10-27, or the paging partition's packed
    pages; `CHECK-PARTITION-SIZE` counts packed blocks (`sys/sys/qmisc.lisp`);
    the file device takes a page's address from its one CCW (`sys/io/fdev.lisp`).
  - **Bignum digits carry tag 000**: a digit's word is the digit, its 31
    bits with `<39:31>` zero, as the CADR's word is; this amends contract G1
    section 2.6, under which data words carry 005. The microcode makes its
    digits so (a 31-bit `LDB` over `A-ZERO`, or `A-ZERO`), and so its
    whole-word digit compares (`BEQL`, `BSHFFL`, against `A-ZERO`) stay
    numeric as MIT wrote them; the cold load's bignums (`store-bignum-40`,
    `sys/cold/coldut.lisp`) now write the digit as it is rather than
    `vunboxed`. Read as an object, a digit is `DTP-TRAP`, and the transporter
    signals an error.
  - **Floats are IEEE singles** (contract G1 sections 2.3, 2.4; G2 section
    6.1). `DTP-SMALL-FLONUM` is the one float, its field an IEEE 754
    binary32; there is no boxed flonum. Its behaviour:
    - Arithmetic keeps the CADR's internal form, a 32-bit significand and an
      exponent excess 2000 (`uc-arith.lisp`), and packs the result to 24 bits
      rounded to nearest, ties to even (`SFLPACK-P`). The internal routines
      no longer round to 32 bits first: an inexact sum, product or quotient
      keeps its low bit set (`FRND`, `FDIV`), so a single is rounded once;
      rounded twice, 1.0 plus `SHORT-FLOAT-EPSILON` gave 1.0. A bignum's
      conversion still rounds at 32 bits on the next digit alone
      (`FLOAT-A-BIGNUM`). The reader read a number as floats too, scaled by
      a power of ten, and could be an ulp off; it now reads exactly (below,
      the float reader).
    - A result past the largest single is an infinity of its sign, not an
      error: there is no `FLOATING-EXPONENT-OVERFLOW` trap, by design, so a
      case that expects one (System 2000's `(* 1s10 1s10 1s10 1s10 1s10)`,
      and proceeding from the trap with a new value) does not apply. An
      infinity prints as `#.SI:SINGLE-FLOAT-POSITIVE-INFINITY` or
      `#.SI:SINGLE-FLOAT-NEGATIVE-INFINITY` (`PRINT-FLONUM`,
      `sys/io/print.lisp`; the constants in `sys/sys2/numer.lisp`), which read
      back as it; it printed as 1.0e153, the scaling by powers of ten having
      run past the table. `FORMAT`'s `~F`, `~E`, `~G` and `~$` print it as the
      printer does (below). One below the smallest normal single underflows as on the CADR:
      `FLOATING-EXPONENT-UNDERFLOW`, or 0.0 under `ZUNDERFLOW`; no subnormal
      is made. A subnormal operand is read as its value, an infinity or a
      NaN as an infinity (an exponent past any single's, so that it stays one
      through multiplication), and -0.0 as 0.0.
    - The boxed packers (`FLOPACK`) pack a single; `%FLOAT-DOUBLE` takes its
      low word's 32 bits unsigned; `ART-FLOAT` holds one single a word and
      `ART-COMPLEX-FLOAT` two (`uc-array.lisp`, `QFARY`, `QSFARY`;
      `sys/cold/qcom.lisp`), and a never-stored element reads as 0.0.
    - The shifts that align and truncate significands (`FADD`,
      `FLONUM-FIX-FLOOR`, `FLONUM-BIGFIX`, `FLOAT-A-BIGNUM`) rotate on the
      40-bit ring (appendix A1.2).
    - Lisp: the short float is the float, and `*READ-DEFAULT-FLOAT-FORMAT*`
      is `SHORT-FLOAT`, so floats read without and print without an exponent
      marker (`sys/io/read.lisp`); the reader divides by powers of ten above
      1e38 in steps. `FASL-OP-FLOAT` loads a 40-bit file's binary32
      (`sys/sys/qfasl.lisp`). The float accessors, `FLONUM-MANTISSA` and
      `FLONUM-EXPONENT`, the limits and epsilons (`sys/sys2/numdef.lisp`,
      `numer.lisp`) are the single's; single, long and double floats share
      them. `SQRT`, `LOG` and `RATIONALIZE` no longer set a boxed flonum's
      exponent in place (`numer.lisp`, `rat.lisp`).
  - **A numeric array's words start as fixnum zeros**, tag 005 (contract G1
    section 2.6; `XAAIA`, `uc-storage-allocation.lisp`); they started as tag
    000, and a string's words stayed so after `ASET`. `STRUCTURE-INFO` sizes
    `ART-FLOAT` at a word an element and `ART-COMPLEX-FLOAT` at two, as the
    garbage collector copies them.
  - **`GET`, `GETL` and `GET-LOCATION-OR-NIL` of an instance** send it the
    message again: `PLGET` marks an instance by setting the cdr code, now
    `<39:38>`, and its callers tested `<30>` (`uc-fctns.lisp`). The login's
    `FILE-LOGIN` sent a host `:CAR`. `GETL`'s message now carries the list of
    properties (`XGETL-INSTANCE` pushed `M-D`, which holds nothing there; the
    CADR's microcode did the same).
  - **`COPY-ARRAY-PORTION`** checks each start against its array's length
    (`XCAP`, `uc-array.lisp`): a negative start signals
    `SUBSCRIPT-OUT-OF-BOUNDS`, where the unsigned checks had taken it as an
    exhausted source.
  - **`RANDOM-INITIALIZE`** fills a 32-bit fixnum's `<31:24>` (`numer.lisp`); it
    knew 25- and 31-bit pointers only, and stopped `QLD` at "Bug in
    RANDOM-INITIALIZE".
  - **`QLD` of the 40-bit cold load** needs the fonts and demo data written
    again for 40 bits and the site files (`docs/building.md`, "Loading the
    40-bit cold load").
  - **`UCINIT` is compiled from a source** (`sys/sys/ucinit.lisp`, new;
    `sys/sys/sysdcl.lisp:193-197`, `COMPILER`'s `:COMPILE-LOAD` in place of
    its `:FASLOAD`). System 100's binary-only `SYS: SYS; UCINIT QFASL`, whose
    writer has no caller, held one thing: `EQUAL`'s `MCLAP`, microinstructions
    of the CADR's 32-bit word, and `(setq *initially-microcompiled-functions*
    '(equal))`. Microcode 2001 has no microcompiled function (its `EQUAL` is
    hand-written, `XEQUAL`), nothing reads the variable, and `MCLAP-LOAD`
    reads a function's `MCLAP` only when asked to load that function, so the
    source records none and the system needs nothing else; the CADR's
    microcode, and its microcompiler, keep System 100's file.
  - **A full garbage collection completes.** `PHT1-ALL-BUT-SWAP-STATUS-CODE`
    and `PHT1-ALL-BUT-AGE-AND-SWAP-STATUS-CODE` reach `<39>`
    (`uc-page-fault.lisp`), so the selective deposits into a page hash table
    entry (`PGF-AG`, `AGER2`, `AGER4`, `XCPGS3`) keep its tag; stopping at
    `<31>` they left tag 000, and `DEALLOCATE-PAGES` (`sys/sys2/gc.lisp`),
    which reads the entry as a fixnum, trapped in `SI:FULL-GC` and
    `SI:GC-IMMEDIATELY`. `tools/microcode-check/cases/full-gc.cases`.
  - **`NAMED-STRUCTURE-P`** reads element 0 of a structure with no leader by
    index 0 rather than -1, which the unsigned bounds check now refuses
    (`uc-fctns.lisp`).
  - **Incremental bands are saved and restored**, in pages of 5 blocks, packed,
    as a whole band's (`DISK-SAVE` with its third argument; decided on 30
    September). An incremental band is MIT's layout again in those pages:
    pages 0-2 the low pages, page 3 the base band's name and the mask's length,
    page 4 the base band's `REGION-FREE-POINTER` page, from page 5 the mask, a
    bit a page of virtual memory, then the pages that changed
    (`sys/io1/inc.lisp`, `INC-BAND-BASE-DATA-PAGE` and its kin, written and read
    packed; `uc-cold-disk.lisp`, `INC-BAND-BASE-DATA-PAGE` 17, `-FREE-POINTERS-PAGE`
    24 and `-BITMAP-PAGE` 31, their first blocks). The microcode's save and
    restore count the bitmap in pages again, keep a region's page numbers apart
    from its disk blocks, which are 5 a page (`DISK-SAVE-REGION`,
    `DISK-RESTORE-REGION`, `DISK-SR-1`, `DISK-RR-1`), and take the format 2001 to
    `DISK-RESTORE-INCREMENTAL`; `INCREMENTAL-BAND-NOT-SUPPORTED` and
    `DISK-SAVE`'s and `DISK-RESTORE`'s refusals are commented out
    (`sys/sys/qmisc.lisp`). A page is compared with the base band's whole,
    tags included (`COMPARE-RANGE`, `PAGE-TAGS-EQUAL`): the 16-bit view sees
    only `<31:0>`, and a page whose words changed only in their tags was taken
    as unchanged and lost. The pages of the region tables, which the restore
    reads before the bitmap, are always saved: omitted, the restore took the
    next page saved for them.
  - **A reference past the 28-bit space signals an error** (G2 section 2.6),
    and a pointer past it can be held, stored and saved. `ADDRESS-PAST-28-BITS`
    (`uc-page-fault.lisp:526-552`) traps from the page-fault level, as
    `WRITE-IN-READ-ONLY` does, with the error-table entry of that name; it
    halted. The address goes to the error handler in `M-T`, a fixnum of its
    field, and `VMA` is set to `NIL`, since a stack group's resume reads
    memory at its saved `VMA` to restore `MD` (`SGENT`), which would trap again
    inside the switch: with the address in `VMA`, the case
    `(car (%make-pointer dtp-list -1))` filled the region table and halted. The
    error holds the address as a locative, in its `:ADDRESS` property and its
    message alike: "There was a reference to #<DTP-LOCATIVE -1>, which is
    past the 28-bit address space." (`sys/eh/ehf.lisp:2337-2348`). The
    garbage collector's tests take such a pointer as neither oldspace nor
    extra PDL before they read the map, whose bits for it stay 0 (A1.7):
    `TRANS-OLD` and `EXTRA-PDL-TRAP-1` (`uc-transporter.lisp`) leave by
    `TRANS-DROP-THROUGH`, as for the A memory and I/O addresses that
    `GET-MAP-BITS` marks so. Without them a past-28 locative in a local halted
    the machine at the next process switch, one in a special halted it when
    stored or at the next full GC, and so did the trap's own state save;
    with them the four cases pass, and without either test, planted, all four
    halt again. `EH::SG-SAVE-STATE` (`sys/eh/eh.lisp`) saves a
    register holding such a pointer as its field, as a non-pointer, rather than
    transport it (`%P-CONTENTS-AS-LOCATIVE` signals the error, and did so in
    the error handler, where the condition's handler then never ran). Still
    halting, as on the CADR for free space: a forged forwarding pointer past
    the space met by the scavenger or in a switch. On System 1001 a reference
    through a pointer into free space halts at `SWAPIN` and the same pointer
    held across a process switch halts in `GET-MAP-BITS`.
    `tools/microcode-check/cases/address-past-28-bits.cases`.
  - **`%WRITE-INTERNAL-PROCESSOR-MEMORIES` writes an A or M location's 40
    bits** (`XWIPM`, `uc-cadr.lisp:224`): `D-HI`'s bits 15:8, which its callers
    fill from the word's bits 39:32 (`COMPILER:MA-LOAD-A-MEM`, the microcode
    loader in `sys/sys2/usymld.lisp`), are the tag; every location it wrote
    got tag 000. Its arguments keep their 24-bit pieces, which 32-bit fixnums
    hold as 25-bit ones did. `tools/microcode-check/cases/write-a-memory.cases`.
  - **`FORMAT`'s float directives** (`sys/io/format.lisp`): `~E`, and `~G`
    when it chooses `~E`, called `SI::SCALE-FLONUM` with a positive number,
    which it takes negative, and stopped with a subscript or overflow error
    for every float, on System 2000 too (`:826`, `:944`); `~G` with no width
    compared the exponent with `NIL`. An infinity under `~F`, `~E`, `~G` and
    `~$` prints as the printer prints it, right-justified in the width, or as
    the overflow characters when it does not fit (`FORMAT-INFINITY-P`,
    `FORMAT-CTL-INFINITY`, `:743-760`); `~F` printed the largest single's 39
    digits. `tools/system-check/cases/format-float.cases`.
  - **A process interrupt no longer halts the machine**
    (`SI:%POINTER-TYPE-P`, `sys/sys2/lmmac.lisp:301`): a code past
    `DTP-CHARACTER` is no data type and points nowhere. A register the
    microcode set to all ones (`SETO`: `M-K` in `%DRAW-CHAR` and the
    transporter, `M-E`) is saved so in a stack group's leader, data type 77,
    and `EH::SG-SAVE-STATE`, run by a process interrupt, followed it to
    address 37777777777 and halted: the end of every TELNET session but the
    last did so on the first 40-bit band. The defsubst is compiled into its
    callers. `tools/system-check/cases/process-interrupt.cases`.
  - **The cross build dumps a character as its field's bits, unsigned**
    (`FASD-CHARACTER`, `sys/sys/qcfasd.lisp:236-254`): System 2000's builder,
    of 25-bit fields, took a character with bit 24 set, a mouse character's,
    as negative and dumped it so, and the 40-bit target's character had
    `<31:25>` set (ZWEI's `*ILLEGAL-COMMAND-BARF-STRING-ALIST*` held
    -16777184 where a native compile holds 16777248).
    `tools/cross-check/` check 1 (`XC-CHAR`, `lisp/family.lisp`).
  - **The cross build encodes floats from the builder's own bits**
    (`HOST-INTEGER-DECODE-FLOAT`, `sys/sys/qcfasd.lisp:313-342`, used by
    `FLOAT-TO-BINARY32` in a builder of 25-bit fields). `cross-compile-system`
    loads the tree's `SYS2; NUMDEF`, a definitions file of SYSTEM, whose IEEE
    single's parameters and accessors then replace System 2000's own (now
    `CROSS-BEGIN` loads it, below), and
    `INTEGER-DECODE-FLOAT` misread every float of the files compiled after it:
    `SYS2; HASH`'s rehash size 1.3 was dumped as an infinity, 0.25 as
    `#x03FE0000`, and `QLD` of the cross build's cold load looped in
    `PUTHASH-BOOTSTRAP`. `tools/cross-check/` check 1 encodes four floats
    before and after loading the tree's `NUMDEF`.
  - **The cross build gives every compile for the target the tree's
    compile-time definitions** (`sys/cold/cross.lisp:67-97`, `:701-818`).
    A file compiled for the target expanded a macro, or open-coded a
    defsubst, with the builder's definition, System 2000's: `QFASL`'s
    `FASL-OP-NEW-FLOAT` took `%SHORT-FLOAT-EXPONENT` as `(byte 8 17.)` where
    the tree has `(byte 8 23.)`, since `MAKE-SYSTEM` loads the tree's
    `NUMDEF` only after the cold load's files are compiled.
    `sys/cold/crossdefs.lisp` (new) lists every compile-time definition of the
    tree whose text is not System 2000's (and the macros and defsubsts that
    hold a float literal, below), written from the sources by
    `tools/cross-check/crossdefs.py` (new), which the cross-check driver runs
    first to check that the list is current. `CROSS-BEGIN` reads each listed
    definition and evaluates it as the compiler does inside a file, which
    declares it and defines nothing; `CROSS-COMPILE-STREAM` (`:422`) starts
    every file with those declarations, and `CROSS-DECLARED-DEFINITION`, over
    `SI:DECLARED-DEFINITION`, stops a file that expands a listed name without
    one. Macros and defsubsts are given so; a changed structure or setf method,
    which would still change the builder when evaluated, makes `CROSS-BEGIN`
    refuse (`CROSS-CHECKED-KIND-P`, `:769`). `tools/cross-check/` check 1
    (`XC-SHORT-EXPONENT`, `lisp/defs.lisp`, and the control with `NUMDEF`'s
    definitions left out, under which `SYS: SYS; QFASL` does not compile).
  - **`FIXNUM-READ-METER-FOR-SCHEDULER` leaves its byte for the compiler to
    fold** (`sys/sys2/prodef.lisp:175-186`): `#,(1- %%Q-POINTER)` put in the
    value of the world that loaded the macro, which in a cross build is the
    builder's, `#o30`, and the scheduler's disk meters lost their top bits in
    the target, whose byte is `#o37`. `crossdefs.py --census` refuses a `#,`
    inside a compile-time definition. `tools/cross-check/` check 1
    (`XC-METER`).
  - **The cross build makes the target's system constants constants**
    (`CROSS-DECLARE-TARGET-CONSTANTS`, `sys/cold/cross.lisp:209-224`; undone
    by `CROSS-END`, `:819`): a symbol of the target's system-constant lists
    that System 2000 does not have, as `DISK-BLOCKS-PER-PAGE`, was compiled as
    a variable where a native compile folds it. Check 1 (`XC-TABLE-CONSTANT`).
  - **The compiler folds `LSH`, `ROT` and `SMALL-FLOAT` of constants as the
    target computes them** in a cross build (`TARGET-LSH`, `TARGET-ROT`,
    `TARGET-SMALL-FLOAT`, `sys/sys/qcdefs.lisp:768-807`; used by
    `ARITH-OPT-NON-ASSOCIATIVE`, `sys/sys/qcopt.lisp:301-315`): `LSH` and `ROT`
    were left for the target to compute, and `SMALL-FLOAT` made System 2000's
    short float, of 17 bits of significand. `FLOAT-OPTIMIZER`
    (`sys/sys/qcopt.lisp:360-380`) takes a float prototype as the target
    does, as its one float, the short float: `(float n 0f0)` in `LOG` compiled
    to `INTERNAL-FLOAT`, not `SMALL-FLOAT`. Check 1 (`XC-LSH`, `XC-ROT`,
    `XC-SMALL-FLOAT`, `XC-FLOAT-PROTO`).
  - **The cross build holds its floats as the target does**
    (`CROSS-READ-FLONUM`, `CROSS-TARGET-FLOAT`, `sys/cold/cross.lisp:481-541`),
    when the target's one float is the IEEE single (`TARGET-ONE-FLOAT-P`,
    `sys/sys/qcdefs.lisp:799`): a literal, also a short one, is read as the
    target reads it (the float reader, below), and the values of a fold and
    of `#.` are rounded to the target's single. Read as System 2000's short float, `HASH`'s
    `1.3s0` was dumped as `#x3FA66680` where a native compile has
    `#x3FA66666`; and two literals that are one float in the target
    (`1.442695s0` and `1.44269504` in `EXP`) were two constants.
    `FASD-SHORT-FLOAT` (`sys/sys/qcfasd.lisp:271-279`) stops a file that would
    dump a short float of the builder, of 17 bits. A macro or defsubst whose
    text is System 2000's but holds a float literal is in
    `sys/cold/crossdefs.lisp` too (`:floats`), since the builder read it with
    its own floats: `HASH-TABLE-MAXIMAL-FULLNESS`'s `0.7s0` was `#x3F333300`
    in `HASHFL`. Check 1 (`XC-SHORT-LITERAL`, `XC-DEDUP`, `XC-FULLNESS`, and
    `lisp/shortfloat.lisp`, which must not compile).
  - **Two constants no longer depend on the compiling world's floats**:
    `PHASE` (`sys/sys2/rat.lisp:142-146`) returns `#.pi` for a short float,
    where `#.(coerce pi 'short-float)` made System 2000's short float in a cross
    build; `SCALE-FLONUM` (`sys/io/print.lisp:677-681`) divides by `log2 10`
    written as a literal, where the fold of `(log 10s0 2s0)` gave the
    compiling world's `LOG`, `#x40549A7A` on revision 13, two units in the last
    place from the correctly rounded `#x40549A78`.
  - **The reader reads a float literal as the correctly rounded single**
    (`XR-READ-FLONUM`, `XR-FLOAT-BITS`, `XR-DECIMAL-TO-SINGLE-BITS`,
    `sys/io/read.lisp:1157-1241`; the old reader commented out at
    `:1108-1155`): every digit is kept in an integer, and the ratio of it and
    a power of ten is rounded once, to nearest, ties to even. Past the
    largest single a literal is an infinity; below the smallest normal one it
    underflows as arithmetic does, `FLOATING-EXPONENT-UNDERFLOW` or 0.0 under
    `ZUNDERFLOW`. The old reader took 12 digits into a float and scaled it
    by a power of ten, rounding twice: `1.570796326` was `#x3FC90FDA`, not
    `#x3FC90FDB`, `3.4028236e38` was the largest single, not an infinity, and
    `1.0000000596046447753906249999` was a unit too high. Reading a float takes
    2 to 5 ms more on the microcode simulator; the cold load reads none.
    The cross build reads its literals with the same functions
    (`CROSS-READ-FLONUM`, `CROSS-DEFINE-READER`,
    `sys/cold/cross.lisp:488-528`), so a native compile and a cross compile
    hold the same constants: `NUMER`'s `SIN-AUX`, whose `1.570796326` and
    `1.5707963185` are one single, and `LOG-AUX`, `COS`, `COSD` and `ATAN`,
    whose literals were an ulp apart. `tools/system-check/cases/float-reading.cases`
    (new); check 1 (`XC-LONG-LITERAL`, `XC-PI2`).
  - **The cross build does not load `SYS2; NUMDEF` into the builder**
    (`*CROSS-UNLOADED-FILES*`, `sys/cold/cross.lisp:564-594`): it redefines
    the builder's float functions for the target's floats, and a fold after
    it went wrong: `COLORHACK`'s `(sqrt 2)` was dumped as an infinity. Check 1
    (`XC-SQRT`, compiled after the load).
  - **G2 section 7 check (a) compares word by word**
    (`tools/cross-check/same40.py`): a float may differ from its counterpart
    by one unit in the last place, and each such float is listed; every other
    word of its function must be equal. Before, a function that held a float
    was accepted whatever else differed in it. In a FEF's local map the
    numbers that end `GENTEMP`'s names, a counter of the session, and in the
    file's record of the macros it expanded the hashes of their definitions,
    which depend on the compiling world's floats, are normalised.
    `tools/cross-check/plant_a.py` (new) plants a change for each rule and
    checks the verdict.
  - **G2 section 7 check (b), item 2, compares the cold loads object by
    object** (`tools/cold-compare`, new): step 6's cold load equals step 5's
    except for each file's attribute list, compared as a set of pairs, the
    keywords those lists intern, compared by name, and each file's compile
    time and creation date. A byte diff counted the reordered lists and moved
    keywords as differences and missed a word naming another keyword at an
    unchanged address. `tools/cold-compare-test` (new) plants the changes it
    must report and the one it must accept.
  - **The cold load is made in a 40-bit world too** (the native rebuild, G2
    section 7 step 5; `sys/cold/coldut.lisp:83-140`): a page goes to and from
    the disk through a one-page RQB by a packed transfer, its 5 blocks, the
    page buffer's bytes put into and taken from the page's words, since such a
    world transfers whole pages of 4 blocks (`VMEM-NATIVE-PACKED-P`,
    `VMEM-NATIVE-PACKED-IO`); a world of 256-word pages, as the cross build's
    builder, transfers blocks as before. `COLD:CROSS-COPY-PARTITION`
    (`sys/cold/cross.lisp:608`) reads 4 blocks a transfer there. Made on the
    first 40-bit band from the QFASLs of the cross build's check 3, the cold
    load is byte for byte the cross build's.
  - **The cross build's controls** (`tools/cross-check/`): the tree's `QCOM`
    now describes the 40-bit machine, so check 1's identity control and its
    32-bit target of 1024-word pages take this world's parameters over it
    (`lisp/world.lisp`, which gives every parameter this world also has its
    value here, the symbols in a value being the cold-load package's), the
    latter with `lisp/pages32.lisp`; `lisp/pages256.lisp` is gone.
