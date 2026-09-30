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
  (it becomes 1001 then). It is microcode 1000 with the two fixes below,
  assembled from `sys/ucadr/` as `docs/building.md` describes; the same
  sources without them assemble to System 1002's `ucadr.mcr`, `.tbl`,
  `.locs` and `.sym` byte for byte. The fixes change six control-store
  words and add four after `GCDBB-LONG`, so every word from `GCDBB-NO-LUCK`
  on is four locations later; every other word, every dispatch entry and
  every symbol is the same once moved, and three A-memory words that hold
  control-store addresses move with them. The outputs (sha256):
  - `ucadr.mcr` `66126d29de19391f57cf375a487e12b07af3b78f8d1d827bf126be0601c45921`
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

## Known faults found, not yet fixed

- **An interpreted `CONDITION-CASE` now and then signals "The argument CONS
  was 0, which is not a cons."** In a loop of 100,000 interpreted
  `(condition-case (c) (+ a b) (error ...))` at the listener, one to three
  iterations signal it from the interpreter's own binding code: `LET-IF`'s
  `PARALLEL-BINDING-LIST` (`sys/eval.lisp:1323-1370`), which builds its
  binding frame as a list on the stack, finds that list broken. It happens
  on microcode 1000 as released too, before the stack-group halt fixed
  above, and never in the same loop compiled (1,000,000 iterations). Not
  yet found; a process switch while the frame is built is the suspect.
