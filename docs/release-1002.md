# System 1002

What the next release changes from System 1001. It is in progress: each
change is recorded here as it is made. Every change to a source file carries
a comment in that file saying why.

- **The system number is 1002** (`patch/system.patch-directory`,
  `patch/system-1002.patch-directory`), set on main as soon as System 1001
  was released, so that no band built from main calls itself 1001.

## QUUX

- **Microcode 1000 is QUUX's; the CADR keeps MIT's 323.** QUUX is the CADR
  evolved, and muir and muir-fpga run it with `--machine quux`. This is the
  first change to the microcode itself, which stayed 323 while it was MIT's;
  it takes 1000 as the system took 1000 after System 100. One band serves
  both machines: it asks the machine at boot what it is running on.
  Microcode 1000 needs QUUX hardware revision 2:
  - **A six-bit level-1 map entry** (revision 1), using a bit the CADR
    leaves spare, so the level-2 map has 64 blocks of 32 pages instead of
    32: 63 usable blocks map 504K words at once instead of 248K.
    `ucadr/uc-page-fault.lisp` reads the entry as MAP<29:24> and writes bits
    4:0 from VMA<31:27>, as on the CADR, and bit 5 from VMA<24>. The invalid
    entry is 77, in `A-LEVEL-1-MAP-INVALID`, which the three tests for it and
    the level-2 reuse pointer's wrap compare against.
  - **A 16K-word PDL buffer** (revision 2), a 14-bit pointer instead of the
    CADR's 10 bits and 1K words: `PDL-BUFFER-ADDRESS-MASK`, `-HIGH-BIT` and
    `PDL-BUFFER-SIZE-IN-WORDS` (`ucadr/uc-parameters.lisp`), which every
    PDL-buffer site now uses by name (five had the width as a literal).
    muir measured 16K against 1K and 4K on its thirteen workloads: 4.3% fewer
    microcycles in all, 29% fewer in deep recursion, with stack-group
    switching unchanged.
  - **The machine's id** is functional source 16, which the assembler now
    names `MACHINE-ID` (`sys/cadsym.lisp`): on QUUX the signature 0x5155 in
    bits 31:16, the hardware revision in 15:4 (cumulative) and the processor
    type in 3:0; a CADR does not drive the source and reads all ones. muir's
    `docs/quux.md` holds the contract. `INITIAL-MAP-A`
    (`ucadr/uc-cold-disk.lisp`) reads it at boot and halts at
    `MACHINE-NOT-QUUX-2` on anything but QUUX from revision 2, so microcode
    1000 never runs with a map or a PDL buffer the hardware lacks. It then
    sets every level-1 entry to 77, zeroes block 77, and halts at
    `MAP-WIDTH-MISMATCH` if block 0's entry does not read back as 77.
  - **The reverse first-level map**, one word per level-2 block, moves from
    system communication locations 440-477 to 640-737: 64 entries do not fit
    before the keyboard buffer header at 500. 640-677 held only the Lambda's
    disk and memory tables. 700-717 held the swap-out CCW lists
    (`DISK-SWAP-OUT-CCW-BASE`), which move to 440-457 with the same 16
    entries. The swap-in CCWs stay at 740-757, and the single-page CCW at
    777.
  - `A-PROCESSOR-TYPE-CODE`, which the Lisp variable `SI:PROCESSOR-TYPE-CODE`
    shows, is 4 under microcode 1000, the new constant `SI:QUUX-TYPE-CODE`
    (`window/cold.lisp`, exported from `cold/system.lisp`), after the Lambda's
    2 and the Explorer's 3; 323 gives the CADR's 1, `SI:CADR-TYPE-CODE`.
  - `cold/qcom.lisp`: `SIZE-OF-HARDWARE-LEVEL-2-MAP` is 4000, QUUX's, and
    the system communication area's layout comment gives both machines'.
- **The boot PROM, version 1000,** serves both machines. MIT's PROM (version
  9) copied A memory out of the PDL buffer until the index wrapped to 0,
  which a wider index never does in time: A memory was overwritten and the
  loaded microcode never started. It copies exactly 2000 words now, clears
  PDL words 0-1777 at any width, and clears all 64 level-2 blocks
  (`ucadr/promh.text`).
- **The band takes the PDL buffer's length from the machine.** A stack
  group's saved PDL phase is masked with `SI:PDL-BUFFER-LENGTH`
  (`sys2/proces.lisp`, and `eh/eh.lisp` rebuilding a frame), which was the
  CADR's 2000. It is set at every boot by `SI:MACHINE-PDL-BUFFER-LENGTH`:
  QUUX's feature page, word 3 (16384), or 2000 on a CADR, since a band can
  be booted on either machine.
- **Serve the running microcode's table.** A band whose microcode is not the
  one it was saved with reads `SYS: UBIN; UCADR TBL` at boot, so the served
  `SYS: UBIN;` must hold that microcode's `ucadr.tbl`.

## The herald

- **The herald names the site, whatever it is.** MIT's `PRINT-HERALD`
  (`io/disk.lisp`) printed "MIT System" for the site `:MIT` and "LMI System"
  for every other site, so a site copied from `site/` under its own name was
  told it ran LMI's system. It prints the site's name now, "FOO System" for a
  site `:FOO`, and "UNKNOWN" when no site is loaded (unbound or NIL), in the
  first line and in the line naming the machine, which trapped on an unbound
  site name. The MIT site prints exactly what it did.

- **The herald prints the machine type**, "Machine Type CADR" or "QUUX",
  under the microcode's version (`DESCRIBE-SYSTEM-VERSIONS`,
  `sys2/patch.lisp`). `MACHINE-TYPE` (`sys/genric.lisp`), which returned
  "CADR" whatever the machine, names it from the type code the microcode set
  at boot.

## Asking the machine

- **`SI:MACHINE-TYPE-CODE`** returns 1 on a CADR and 4 on QUUX, the type code
  the microcode set at boot from `MACHINE-ID`; `MACHINE-TYPE` gives its name.
- **`SI:PRINT-FEATURE-PAGE`** prints QUUX's feature page, read with
  `%XBUS-READ` at Xbus 17377000: the machine ID with its signature, revision
  and type, and the sizes of the level-1 entry, the level-2 map, the PDL
  buffer, control store, A memory and dispatch memory. On a CADR, which has no
  such page and times out if it is read, it says so instead.

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
- **`docs/booting.md`, how a machine boots**, from power-on through the
  PROM and the microcode to the first macroinstruction, carried over (lmz-sys
  `fecd0a5`) with every citation re-checked against this tree, and the
  PROM's and microcode 1000's QUUX handling added.

Not taken: that line's reader and naming changes for Common Lisp (`#T`, the
comparison names in ASCII), bishop's stack-frame operations, and its
correction of the run-light comment in `sys/ltop.lisp`, which describes
code this tree still has (`SET-UP-SCAN-LINE-TABLE` in `window/shwarm.lisp`).
