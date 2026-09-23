# System 1002

What the next release changes from System 1001. It is in progress: each
change is recorded here as it is made. Every change to a source file carries
a comment in that file saying why.

- **The system number is 1002** (`patch/system.patch-directory`,
  `patch/system-1002.patch-directory`), set on main as soon as System 1001
  was released, so that no band built from main calls itself 1001.

## QUUX

- **One microcode for the CADR and QUUX, version 1000.** QUUX is the CADR
  evolved, and muir and muir-fpga run it with `--machine quux`. Its level-1
  map entry is six bits instead of five, using a bit the CADR leaves spare,
  so the level-2 map has 64 blocks of 32 pages instead of 32: 63 usable
  blocks map 504K words at once instead of 248K. This is the first change
  to the microcode itself, which stayed 323 while it was MIT's; it takes
  1000 as the system took 1000 after System 100. It reads which machine it
  is on at boot and serves both.
  - **The machine's id** is functional source 16, which the assembler now
    names `MACHINE-ID` (`sys/cadsym.lisp`). On QUUX it reads the signature
    0x5155 in bits 31:16, the hardware revision in 15:4 (1 is the six-bit
    level-1 entry; revisions are cumulative) and the processor type in 3:0;
    a CADR does not drive the source and reads all ones. muir's
    `docs/quux.md` holds the contract.
  - `ucadr/uc-cold-disk.lisp`: `INITIAL-MAP-A` reads `MACHINE-ID`. Without the
    signature the machine is a CADR, processor type 1, with the invalid
    level-1 entry 37; with it, the type is QUUX's own (4), and from revision
    1 the invalid entry is 77. Boot then sets every level-1 entry to all
    ones, zeroes the invalid block, and reads back block 0's entry: if it is
    not the invalid entry the id promised, the level-1 map is narrower than
    the id says, and the microcode halts at `MAP-WIDTH-MISMATCH` instead of
    letting blocks alias.
  - `ucadr/uc-page-fault.lisp`: the level-1 entry is read as six bits,
    MAP<29:24>, which a CADR reads with bit 29 always 0. It is written as two
    fields, bits 4:0 from VMA<31:27> as on the CADR and bit 5 from VMA<24>,
    which a CADR ignores. The three tests for the invalid entry, and the
    level-2 reuse pointer's wrap, compare against `A-LEVEL-1-MAP-INVALID`
    (`ucadr/uc-parameters.lisp`, after every other A-memory variable, so no
    location moves), 37 or 77, instead of the constant 37.
  - The reverse first-level map, one word per level-2 block, moves from
    system communication locations 440-477 to 640-737 on both machines: 64
    entries do not fit before the keyboard buffer header at 500. 640-677
    held only the Lambda's disk and memory tables. 700-717 held the
    swap-out CCW lists (`DISK-SWAP-OUT-CCW-BASE` in
    `ucadr/uc-parameters.lisp`), which move to 440-457, where the reverse
    map was, with the same 16 entries. The swap-in CCWs stay at 740-757,
    and the single-page CCW at 777.
  - `A-PROCESSOR-TYPE-CODE`, which the Lisp variable `SI:PROCESSOR-TYPE-CODE`
    shows, is set at boot: 1, `SI:CADR-TYPE-CODE`, or 4, the new constant
    `SI:QUUX-TYPE-CODE` (`window/cold.lisp`, exported from
    `cold/system.lisp`), after the Lambda's 2 and the Explorer's 3. No code
    tests it.
  - `cold/qcom.lisp`: `SIZE-OF-HARDWARE-LEVEL-2-MAP` is 4000, QUUX's, and
    the system communication area's layout comment says where the reverse
    map and the swap-out CCWs now are.
- **The band is unchanged by this.** System 1001's band runs on microcode
  1000 as it is; the Lisp changes above are for the next band. The served
  `SYS: UBIN;` must hold the running microcode's `ucadr.tbl`, which a band
  reads when its microcode is not the one it was saved with.

## Taken from the System 2000 line

What lmz-sys, the System 2000 line for bishop, fixed after the two lines
parted that holds for this line too. Each was checked against this tree
before it was taken.

- **The undefined-host fallback in `io/file/pathst.lisp` works.** Two places
  canonicalise the pathnames a cold load recorded, and each carries MIT's
  comment "Don't bomb out if host isn't defined" over an arm that bombs out:
  it sends `:PHYSICAL-HOST`, a message to a host, to a pathname, which no
  pathname flavor answers. Both now ask the translated pathname for its host,
  which is the physical one by construction. The arm runs only when a band
  names a host the machine has never heard of (lmz-sys `6d1da93`).
- **`cold/export.lisp` says where the sync functions live.** `SETUP-CPT`,
  `START-SYNC`, `STOP-SYNC` and `FILL-SYNC` are all defined in
  `WINDOW; COLD`, not in `WINDOW; SHWARM` or `WINDOW; COLOR` as the notes
  said (lmz-sys `189eeea`).
- **`site/sys.translations` and `docs/building.md` say why files the cold
  load reads over MINI use spaces only**: MINI hands the reader untranslated
  bytes, so an ASCII tab is not whitespace to it (lmz-sys `2e684c2`).

Not taken: that line's reader and naming changes for Common Lisp (`#T`, the
comparison names in ASCII), bishop's stack-frame operations, and its
correction of the run-light comment in `sys/ltop.lisp`, which describes
code this tree still has (`SET-UP-SCAN-LINE-TABLE` in `window/shwarm.lisp`).
