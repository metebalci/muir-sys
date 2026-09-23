# System 1002

What the next release changes from System 1001. It is in progress: each
change is recorded here as it is made. Every change to a source file carries
a comment in that file saying why.

- **The system number is 1002** (`patch/system.patch-directory`,
  `patch/system-1002.patch-directory`), set on main as soon as System 1001
  was released, so that no band built from main calls itself 1001.

## QUUX

- **The microcode is for QUUX, and is version 1000.** QUUX is the CADR
  evolved, and muir and muir-fpga run it with `--machine quux`. Its level-1
  map entry is six bits instead of five, using a bit the CADR leaves spare,
  so the level-2 map has 64 blocks of 32 pages instead of 32: 63 usable
  blocks map 504K words at once instead of 248K. This is the first change
  to the microcode itself. It stayed 323 while it was MIT's, and it takes
  1000 as the system took 1000 after System 100.
  - `ucadr/uc-page-fault.lisp`: the level-1 entry is read as six bits,
    MAP<29:24>. It is written as two fields, bits 4:0 from VMA<31:27> as on
    the CADR and bit 5 from VMA<24>. The invalid entry, which points at the
    all-map-miss last block, is 77 instead of 37 in the three places that
    test for it and where a reused block's old entry is invalidated, and
    the level-2 reuse pointer wraps before 77.
  - The reverse first-level map, one word per level-2 block, moves from
    system communication locations 440-477 to 640-737: 64 entries do not fit
    before the keyboard buffer header at 500. 640-677 held only the Lambda's
    disk and memory tables. 700-717 held the swap-out CCW lists
    (`DISK-SWAP-OUT-CCW-BASE` in `ucadr/uc-parameters.lisp`), which move to
    440-457, where the reverse map was, with the same 16 entries. The
    swap-in CCWs stay at 740-757, and the single-page CCW at 777.
  - `ucadr/uc-cold-disk.lisp`: boot sets every level-1 entry to 77 and
    zeroes block 77, and then reads back the entry it wrote for block 0.
    A CADR reads bit 29 as 0, so there it reads 37, and the microcode halts
    at `QUUX-MAP-MISSING` instead of running until the first level-2 block
    past 37 silently aliases another.
  - `ucadr/uc-parameters.lisp`: `A-PROCESSOR-TYPE-CODE`, which the Lisp
    variable `SI:PROCESSOR-TYPE-CODE` shows, is 4, the new constant
    `SI:QUUX-TYPE-CODE` (`window/cold.lisp`, exported from `cold/system.lisp`),
    after the Lambda's 2 and the Explorer's 3. No code tests it.
  - `cold/qcom.lisp`: `SIZE-OF-HARDWARE-LEVEL-2-MAP` is 4000, and the
    system communication area's layout comment says where the reverse map
    now is.
- **The band is unchanged by this.** System 1001's band runs on microcode
  1000 as it is; the Lisp changes above are for the next band.
