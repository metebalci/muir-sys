# System 1002

What the next release changes from System 1001. It is in progress: each
change is recorded here as it is made. Every change to a source file carries
a comment in that file saying why.

- **The system number is 1002** (`patch/system.patch-directory`,
  `patch/system-1002.patch-directory`), set on main as soon as System 1001
  was released, so that no band built from main calls itself 1001.

## QUUX only

- **System 1002 runs only on QUUX; System 1001 is the last release for the
  CADR** (the user, 2026-09-23). The CADR stays on System 100 and 1001 with
  MIT's microcode 323. The system assumes QUUX: `SI:MACHINE-PDL-BUFFER-LENGTH`
  reads the feature page with no CADR case, and `SI:PRINT-FEATURE-PAGE` no
  longer answers for a CADR.
- **A band stops on anything else.** `LISP-REINITIALIZE` (`sys/ltop.lisp`)
  first calls `SI:CHECK-MACHINE-IS-QUUX`: if the processor type is not
  QUUX's, it prints why on the cold-load stream and halts, as the
  microcode's `MACHINE-NOT-QUUX-6` does for the microcode. Loaded into System
  1001's band, it passes on QUUX and halts on a CADR running 323.
- **So a 1002 band is built on QUUX.** Compiling and making the cold load
  can still run on a 1001 band on the CADR; booting the cold load, QLD and
  the save run on QUUX with microcode 1000.

## QUUX

- **Microcode 1000 is QUUX's; the CADR keeps MIT's 323.** QUUX is the CADR
  evolved, and muir and muir-fpga run it with `--machine quux`. This is the
  first change to the microcode itself, which stayed 323 while it was MIT's;
  it takes 1000 as the system took 1000 after System 100.   Microcode 1000 needs QUUX hardware revision 4:
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
  - **Multiply and divide in one instruction each** (revision 3). The
    assembler names ALU functions 42 and 43 `MULTIPLY` and `DIVIDE`
    (`sys/cadsym.lisp`): one does what 32 `MULTIPLY-STEP`s did, the other
    what a `DIVIDE-FIRST-STEP` and 31 `DIVIDE-STEP`s did, with the first
    step's overflow bit in Q<31>. `MPY` (fixnum multiply, and
    `%MULTIPLY-FRACTIONS`), `DIV` (with its two other entries, the
    bignum-by-fixnum remainder loop and `%DIVIDE-DOUBLE`/`%REMAINDER-DOUBLE`)
    and the bignum division's quotient estimate use them
    (`ucadr/uc-arith.lisp`). The loops that take 31 steps for 31-bit bignum
    digits, the float divide's 30, and `DIVIDE-ONCE`'s, which has no first
    step, still step: they are not the 32 the instructions do. Compared
    over fixnums, edge values and bignums (multiply, quotient and remainder,
    GCD, `%MULTIPLY-FRACTIONS`, `%DIVIDE-DOUBLE`, `%REMAINDER-DOUBLE`, 15255
    results), microcode 1000 on QUUX revision 3 gives exactly what the
    stepwise microcode and MIT's 323 on a CADR give.
  - **The tick is the clock** (revision 4). The CADR's 60-cycle clock ---
    the mouse, the disk's idle count, the Chaosnet's transmit-abort wakeup
    and the sequence-break counter the scheduler runs on --- was the display
    board's vertical interrupt; the next display has none. QUUX's processor
    has a tick of its own, which the assembler names `TICK-CONTROL`,
    `TICK-PERIOD` and `TICK-STATUS` (`sys/cadsym.lisp`). Boot starts it,
    with its reset period of 16,667 microseconds, where the Unibus
    interrupts are enabled (`ucadr/uc-cold-disk.lisp`); `INTR` runs the
    60-cycle handler when its flag is up, and clears it
    (`ucadr/uc-interrupt.lisp`). The display's vertical interrupt, if the
    band enables it, is only cleared, or the clock would run twice as fast.
    `A-TV-CLOCK-RATE` is 60, the tick's rate, so the sequence-break clock
    is once a second (67 suited the display's 60.5 Hz). Lisp's time of day
    comes from the microsecond clock, which this does not touch.
  - **No Unibus** (muir's contract Q5): on QUUX every Unibus address is an
    NXM. After Q1-Q4 moved the clocks, the interrupt status, the keyboard,
    the mouse and the Chaosnet off it, the microcode's last two Unibus
    accesses go: boot no longer enables Unibus interrupts at 766040
    (`ucadr/uc-cold-disk.lisp`), and `INTR` dismisses an interrupt the
    register page's word 100 does not explain rather than look it up at
    766040 (`ucadr/uc-interrupt.lisp`). The cold load's own file client,
    MINI, read the host's address from Unibus 764142; it reads word 141
    (`cold/mini.lisp`). muir counted every Unibus access over a boot to
    the listener and on, and over a cold load's boot: none.
  - **The Chaosnet interface is on the register page** (muir's contract
    Q4), words 140-147, word 140+k for Unibus 764140+2k: the same
    registers in the same order. The microcode's accesses are all made from
    `A-CHAOS-CSR-ADDRESS`, now word 140 (`ucadr/uc-cadr.lisp`); `INTR`
    takes word 100 <5> into `CHAOS-INTR` through `CHAOS-INTR-QUUX`, which
    returns without touching the Unibus (`ucadr/uc-chaos.lisp`,
    `uc-interrupt.lisp`). Lisp addresses the registers as Xbus words and
    uses `%XBUS-READ` and `%XBUS-WRITE` (`network/chaos/chsncp.lisp`). The
    scheduler's own clock reader,
    `SI:FIXNUM-MICROSECOND-TIME-FOR-SCHEDULER-FOR-CADR`, reads the
    processor's clock (source 15) too; it still read Unibus 764120 after
    Q1 (`sys2/prodef.lisp`).
  - **The keyboard and the mouse are on the register page** (muir's
    contract Q3). Word 121's read takes the oldest key word, the 32-bit
    word Unibus 764100 and 764102 gave together; word 120 is the
    keyboard's status and bit 8 its interrupt enable; word 122 holds the
    mouse's X and Y counts and its buttons. `INTR` takes a keyboard
    interrupt from word 100 <3> and puts the key word into the wired
    keyboard buffer, the channel at sys-com 500, through the same code the
    Unibus keyboard used (`ucadr/uc-interrupt.lisp`); `TRACK-MOUSE` reads
    word 122 and takes it apart into the two registers it read before
    (`ucadr/uc-track-mouse.lisp`); the warm-boot test reads words 120 and
    121 (`ucadr/uc-cadr.lisp`). Lisp enables the keyboard's interrupt
    through word 120 (`SET-MOUSE-MODE`, `window/cold.lisp`) and reads the
    buttons from word 122 (`window/mouse.lisp`). There is no beeper:
    `%BEEP` no longer clicks, but still waits its time, which the screen's
    flash relies on (`ucadr/uc-hacks.lisp`).
  - **No stray Xbus accesses at boot.** muir traced every Xbus access that
    nothing answered on a 1280x1024 screen, and three were ours: the boot
    PROM's `PAGE-0-PARITY-FIX` read and wrote one word past page 0 (MIT's
    "one extra location, too bad"), now it stops at 377
    (`ucadr/promh.text`); the microcode's run light before Lisp sets it was
    at the bottom of a 1920x1080 buffer, now it is on the first line
    (`ucadr/uc-cadr.lisp`); and `%DRAW-RECTANGLE` started the read of the
    row below each rectangle before it tested whether the rectangle was
    done, so an erase under the who line read one row past the buffer; it
    now tests first (`XTVERS1`, `ucadr/uc-tv.lisp`). The CADR's TV memory
    ran on past its last line, which hid the last two.
  - **The register page, and the boot PROM at 36000** (revision 6, muir's
    contract Q2). The feature page, 17377000, is QUUX's register page: word
    100 says who interrupted (<0> the tick, <1> the interval timer, <2>
    block-disk), a write to word 101, the error status, clears it, and bit
    0 of word 102, the mode, is error stop. They replace the Unibus's
    interrupt status (766040), error status (766044) and mode register
    (766012). `INTR` (`ucadr/uc-interrupt.lisp`) reads word 100 first and
    takes the tick and the disk from it; the keyboard and the Chaosnet
    still interrupt through the Unibus until contracts Q3 and Q4 move them.
    Boot writes the mode and clears the error status on the register page
    (`ucadr/uc-cadr.lisp`, `uc-cold-disk.lisp`), and
    `COLOR:XBUS-READ-NO-PARITY` (`window/color.lisp`) turns error stop off
    and on there. The boot PROM is 1K words of the control store at
    36000-37777, where reset starts: it clears only 0-35777, halts at
    `ERROR-MICROCODE-TOO-BIG` if the microcode would reach 36000, sets error
    stop through word 102 (its page 2 maps the register page, not the
    Unibus), and ends with a jump to the microcode's location 6, with no
    PROM-disable write (`ucadr/promh.text`).
  - **The clocks are in the processor** (revision 5, muir's contract Q1).
    The tick is fixed at 60 Hz; destination 4, the tick's period until
    now, is the interval timer's period (`INTERVAL-PERIOD`), with its
    enable and clear in `TICK-CONTROL` <2> and <3>; and source 15,
    `MICROSECOND-CLOCK`, is a free-running 32-bit count of microseconds
    since power-on, read whole in one instruction (`sys/cadsym.lisp`). It
    replaces the I/O board's clock at Unibus 764120 and 764122: the
    microcode's `READ-MICROSECOND-CLOCK`, `READ-MICROSECOND-CLOCK-INTO-MD`
    and `READ-USEC-TIME` read the source (`ucadr/uc-cadr.lisp`), and Lisp
    reads it through a new misc instruction, `%MICROSECOND-CLOCK-LDB`
    (761, in GLOBAL: `cold/global.lisp`), which returns a field of one read
    as a fixnum, so that `TIME`
    (`sys/qrand.lisp`) takes its bits without consing;
    `TIME:MICROSECOND-TIME` and `TIME:FIXNUM-MICROSECOND-TIME`
    (`io1/time.lisp`) read the high field on both sides of the low. Feature
    page word 14 is 1 when these clocks are present, and
    `SI:PRINT-FEATURE-PAGE` names it.
  - **MONO TV is the display.** QUUX's display is a 1-bit frame buffer at
    physical 17000000, 1920 by 1080 at 60 words a line by default, with no
    sync program and no interrupt; muir can make it other sizes. The
    feature page gives its size, words 11-13, and the cold load reads them
    (`SI:MONO-TV-WIDTH`, `-HEIGHT`, `-WORDS-PER-LINE`, `-BUFFER-ADDRESS`
    and `-BUFFER-LENGTH` in `sys/ltop.lisp`, each field taken out of its
    word with `%P-LDB`, since the cold load cannot take a bignum apart).
    The main screen is made from them when the window system loads
    (`window/shwarm.lisp`), the cold boot clears the whole buffer, the run
    lights follow the screen's size, and `SET-TV-SPEED`, which loaded the
    CADR TV's sync program, says there is none. The microcode's first
    run-light address is inside MONO TV's default buffer, and `INTRX0` no
    longer reads the CADR TV's vertical flag.
  - **One band runs at any MONO TV size.** The window system is made at
    the size the feature page gave when the band was built, so at every
    boot `TV:SET-SCREENS-TO-MONO-TV` (`window/shwarm.lisp`) moves the
    main screen, the who line and every window to the size it gives now:
    it shrinks the screens to the smaller of the two sizes, points every
    array at the new words per line and buffer, and grows them to the new
    size, the main screen scaling its windows. It follows MIT's
    `SET-TV-SPEED` and the Lambda's `SET-SCREEN-WIDTH`, and resets the
    Chaosnet first, as a window's change of size can let the scheduler
    run before the Chaosnet's own reset. The cold-load stream, which was
    the CADR's 768 by 896, takes MONO TV's size when it is made and at
    every boot (`:SET-MONO-TV`, `window/cold.lisp`), and the run lights
    are placed from the feature page (`sys/ltop.lisp`), not from a main
    screen that may still have the old size. Tested with a band built at
    1280 by 1024 and booted at 1024 by 768, 1280 by 1024 and 1920 by
    1080, the largest size supported.
  - **The TV sync program is gone, and with it most of the TV registers.**
    MONO TV has no sync program, and of the CADR TV's control registers
    QUUX keeps only register 0's black-on-white bit and register 4, the
    color map (the user). So the sync routines and tables go from
    `window/cold.lisp` (`READ-SYNC`, `WRITE-SYNC`, `START-SYNC`,
    `STOP-SYNC`, `FILL-SYNC`, `CHECK-SYNC`, `SETUP-CPT`, `PROM-SETUP`,
    `CPT-SYNC2`), `SYNC-RAM-CONTENTS` from `window/shwarm.lisp`, and the
    CADR debugger's TV sync code from `cc/dmon.lisp`. The color TV code
    stays for a color display like MONO TV, without its sync programs or
    its waits for the retrace, which QUUX's registers no longer report:
    `WRITE-COLOR-MAP` writes register 4 directly, and
    `WRITE-COLOR-MAP-IMMEDIATE` is the same function
    (`window/color.lisp`). The microcode's `%XBUS-WRITE-SYNC`, which
    waited on a TV status bit, is gone and its misc opcode, 471, is free,
    as are `A-TV-REGS-BASE` and `TV-REGS-ADDRESS-BASE`.
  - **No speed bits.** QUUX's mode register (Unibus 766012) has no speed
    bits; every microcycle is one length. The microcode writes 44, not 46,
    where it sets the mode (`ucadr/uc-cadr.lisp`, `ucadr/uc-cold-disk.lisp`),
    and `COLOR:XBUS-READ-NO-PARITY` writes 40 and 44, not 42 and 46.
  - **The machine's id** is functional source 16, which the assembler now
    names `MACHINE-ID` (`sys/cadsym.lisp`): on QUUX the signature 0x5155 in
    bits 31:16, the hardware revision in 15:4 (cumulative) and the processor
    type in 3:0; a CADR does not drive the source and reads all ones. muir's
    `docs/quux.md` holds the contract. `INITIAL-MAP-A`
    (`ucadr/uc-cold-disk.lisp`) reads it at boot and halts at
    `MACHINE-NOT-QUUX-6` on anything but QUUX from revision 6, so microcode
    1000 never runs with a map, a PDL buffer, an instruction or a clock the
    hardware lacks. It then
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
  (`ucadr/promh.text`). With block-disk (below) it serves QUUX only.
- **QUUX's disk is block-disk** (muir's `--disk-controller block-disk`),
  the CADR controller's registers and command list with the drive's
  geometry taken out: the disk address is a block number, `<27:0>`, of one
  pack, unit 0; the commands are read and write only; and the status has
  four error bits, `<9>` no pack, `<13>` stopped by error, `<17>` past the
  end of the pack and `<20>` NXM. QUUX has no other disk (the user). So:
  - the boot PROM writes the block number as the disk address, waits for a
    pack rather than recalibrating, saves page 0 without a read-compare, and
    no longer reads the label's geometry or divides (`ucadr/promh.text`);
  - the microcode addresses blocks directly and treats every error as
    final, so its retry, recovery, recalibrate, read-compare and ECC code
    is gone, as are the recalibrates at boot and the reading of the
    geometry from the label (`ucadr/uc-disk.lisp`, `uc-cold-disk.lisp`);
    its geometry and read-compare variables stay, unused, so that A memory
    does not move;
  - Lisp's `DISK-RUN` (`io/disk.lisp`) puts the block number in the
    request, checks the final block and retries nothing; read-compare is
    done by reading into a second request and comparing; the status is
    read from the controller's register; `DECODE-DISK-STATUS`, the error
    log (`io/dledit.lisp`) and the band receiver (`sys2/band.lisp`) speak
    of blocks; `cold/qcom.lisp` names block-disk's status bits and masks.
  The label keeps its geometry words, for the tools that print them.
  Tested on muir 71953a2 with block-disk: the PROM loads the microcode, a
  cold load boots and QLDs, the saved band boots; Lisp reads the label and
  a band's first blocks, writes and reads back a block, read-compares, and
  a read past the end reports it; the host's reading of the pack agrees.
- **The band takes the PDL buffer's length from the machine.** A stack
  group's saved PDL phase is masked with `SI:PDL-BUFFER-LENGTH`
  (`sys2/proces.lisp`, and `eh/eh.lisp` rebuilding a frame), which was the
  CADR's 2000. It is set at every boot by `SI:MACHINE-PDL-BUFFER-LENGTH`:
  QUUX's feature page, word 3 (16384), or 2000 on a CADR, since a band can
  be booted on either machine.
- **Serve the running microcode's table.** A band whose microcode is not the
  one it was saved with reads `SYS: UBIN; UCADR TBL` at boot, so the served
  `SYS: UBIN;` must hold that microcode's `ucadr.tbl`.

## Faults fixed

- **Dividing by the most negative fixnum no longer corrupts or halts.**
  Negating -2^24, the most negative fixnum, gives 2^24, which must become a
  bignum, and making the bignum clobbers registers. `QDIV` kept a ratio's
  numerator in Q-R while its denominator was boxed, so `(%div 5 -16777216)`
  gave 39565/16777216; `NORMALIZED-RATIONAL-FIX-SIGNS`, on the way from a
  bignum dividend, kept the numerator in M-J while it negated the
  denominator, and the next negation then got a raw integer and halted the
  machine, as `(floor 4294967295 -16777216)` did. Both were MIT's, on
  microcode 323 as well. The unboxed numerator now waits in a word of A
  memory of its own, and the boxed one on the stack (`ucadr/uc-arith.lisp`).
  Checked against exact arithmetic on the host: `TRUNCATE`, `FLOOR`,
  `CEILING` and `%DIV` over 24 values, the edges of the fixnum range and
  bignums among them, 2304 cases.

- **The error table is loaded at every boot.** A band caches its
  microcode's error table under the microcode's version number, and every
  unreleased build keeps its number (1000), so a band saved under one build
  kept that build's table under a later one: an ordinary trap, such as one
  while compiling, was looked up at the wrong addresses and reported as
  "no error-table entry". `EH:INITIALIZE` (`eh/eh.lisp`) now forgets the
  cached table at boot, so it is read from `SYS: UBIN;` each time, as it was
  already whenever the version number changed.

## Known faults found, not yet fixed

- **`(%div 0 0)` returns 0** rather than signalling division by zero: `QDIV`
  returns 0 for a zero dividend before it looks at the divisor. MIT's.
- **MONO TV sizes above 1920 by 1080 are not supported** (the user,
  2026-09-24). At 2560 by 1440, what boot draws in the Lisp listener stops
  at pixel 2^21, row 819, until its next refresh; the cause is not sought.

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
