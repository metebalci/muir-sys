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
  (it becomes 1001 then). It is microcode 1000 with the three fixes below,
  assembled from `sys/ucadr/` as `docs/building.md` describes; the same
  sources without them assemble to System 1002's `ucadr.mcr`, `.tbl`,
  `.locs` and `.sym` byte for byte. The fixes change seven control-store
  words and add four after `GCDBB-LONG`, so every word from `GCDBB-NO-LUCK`
  on is four locations later; every other word, every dispatch entry and
  every symbol is the same once moved, and three A-memory words that hold
  control-store addresses move with them. The outputs (sha256):
  - `ucadr.mcr` `ec7263ea988da1ba6300953b7266f2c032f9242e3be432e47392f4bcea6f56a0`
  - `ucadr.tbl` `01f20b6f9a22778f3bfed34acf7d151da82251b218908c302cb8f7145dffa201`
  - `ucadr.locs` `4b19782bcdb715f68c8541590e28cc7b2a2e988b951bada707455689669ee22b`
  - `ucadr.sym` `99b50807fcb3bb32a6f91b4b8e62abb3a3aae0718acfb5ebc5eb2b441ec2282e`
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
  (`sys/eval.lisp:1372-1375`, `:1187`), and a closed-over frame's words to
  their copies (`sys/eval.lisp:2123-2144`). After a process switch the slot
  was a copy of the cell: a `SETQ` wrote the stack and not the variable, and
  the frame's last slot took the cell's cdr code, cdr-next where it had
  cdr-nil, so `PARALLEL-BINDING-LIST` (`sys/eval.lisp:1323-1383`) walked past
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
- **An interpreted `LET` keeps its variables while a closure is made under
  it with a temporary `DEFAULT-CONS-AREA`.** Making an interpreted closure
  (`INTERPRETER-ENCLOSE`, `sys/eval.lisp:2094`) copies every stack frame
  of its environment, the frames of callers still running included, and
  forwards the stack words to the copies (`UNSTACKIFY-ENVIRONMENT`,
  `sys/eval.lisp:2123-2144`). It consed the copies in `DEFAULT-CONS-AREA`,
  which `QC-FILE` binds to the compiler's temporary area
  (`sys/qcfile.lisp:362`) and resets for every file
  (`sys/qcdefs.lisp:246`, `:253`). So a `MAKE-SYSTEM` typed inside a `LET`
  at the listener lost that `LET`'s frame once compile-time code made a
  closure and the area was reset: every interpreted variable reference then
  failed ("The argument to CAR, ..., was of the wrong type"), the compiler's
  own error recovery, an interpreted lambda, failed the same way, and the
  errors nested until the region table was full and the machine halted in
  `TRAP`'s recursive-error check. The copies are now consed in
  `BACKGROUND-CONS-AREA` (`sys/eval.lisp:2118-2124`), which MIT keeps for
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
