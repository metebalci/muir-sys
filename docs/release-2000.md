# System 2000

What System 2000, the first release for QUUX, changes from System 1001.
Every change to a source file carries a comment in that file saying why.

- **The system number is 2000** (`patch/system.patch-directory`,
  `patch/system-2000.patch-directory`): QUUX's numbers are the 2000s and
  the CADR's the 1000s, for the system, the microcode and the PROM (Mete,
  2026-09-27). This system was 1002 from System 1001's release until then,
  so that no band built from main called itself 1001; the CADR's next
  system, on the `cadr` branch, is 1002.
- **Microcode 2000 and boot PROM 2000**, which were 1000 until then. The
  version is not in the sources but given to the assembler
  (`ua:version-number` and the output's version for `UCADR`, the version
  asked for `PROMH`), so no source changed for it.
  Assembled from the same sources, microcode 2000's `ucadr.mcr` differs
  from the Q11 microcode's (assembled as 1000) in one word, A memory 40,
  `A-VERSION` (`ucadr/uc-parameters.lisp:587-589`), which the Lisp
  variable `%MICROCODE-VERSION-NUMBER` is (`cold/qcom.lisp:975-977`);
  `ucadr.tbl` and `ucadr.sym` differ only in the version they record, and
  `ucadr.locs` not at all. PROM 2000's `promh.mcr` is PROM 1000's byte for
  byte, as the PROM neither prints nor checks a version; its `promh.tbl`
  and `promh.sym` differ only in the version. A band saved on microcode
  1000 boots on 2000 and loads its error table ("[Loading error table for
  microcode version 2000]"; band M4a, System 1002, on muir 1a89ed0).

## QUUX only

- **System 2000 runs only on QUUX** (the user, 2026-09-23, when this
  system was numbered 1002). The CADR's systems are the 1000s, on the `cadr`
  branch from System 1001 (Mete, 2026-09-27). The system assumes QUUX: `SI:MACHINE-PDL-BUFFER-LENGTH`
  reads the feature page with no CADR case, and `SI:PRINT-FEATURE-PAGE` no
  longer answers for a CADR.
- **A band stops on anything else.** `LISP-REINITIALIZE` (`sys/ltop.lisp`)
  first calls `SI:CHECK-MACHINE-IS-QUUX`: if the processor type is not
  QUUX's, it prints why on the cold-load stream and halts, as the
  microcode's `MACHINE-NOT-QUUX-6` does for the microcode. Loaded into System
  1001's band, it passes on QUUX and halts on a CADR running 323.
- **So a 2000 band is built on QUUX.** Compiling and making the cold load
  can still run on a 1001 band on the CADR; booting the cold load, QLD and
  the save run on QUUX with QUUX's microcode.
- **The whole build now runs on QUUX** (the user, 2026-09-25): the previous
  2000 band, in LOD2, compiles the changed files and makes the cold load in
  LOD3, which it boots with `(si:disk-restore "LOD3")`, or, for a new
  microcode, by a cold boot with bit 48 moved to LOD3; QLD and the save
  follow as before. Two builds of the same tree, one from a CADR-built band
  and one from its result, made cold loads byte for byte the CADR route's,
  and compiled files that differ from its only in their headers' time,
  system version and order, and in generated symbol numbers
  (docs/building.md, "Building a System 2000 band on QUUX"). The CADR route
  stays as the fallback until it is retired.

## QUUX

- **Microcode 2000 is QUUX's; the CADR runs MIT's 323, or its own
  microcode 1000 from System 1002 on.** QUUX is the CADR
  evolved: muir-sim runs it as `quux`, and muir-fpga builds it. This is the
  first change to the microcode itself, which stayed 323 while it was MIT's;
  it takes 2000, as QUUX's numbers are the 2000s (it was 1000 until
  2026-09-27, as the system took 1000 after System 100). Microcode 2000
  needs QUUX hardware revision 4:
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
    `TICK-PERIOD` and `TICK-STATUS` (`sys/cadsym.lisp`; revision 5 renamed
    `TICK-PERIOD` `INTERVAL-PERIOD`, and revision 10 retired it and
    `TICK-STATUS`, below). Boot starts it,
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
    takes word 100 <5> (<6> from revision 11, below) into `CHAOS-INTR` through `CHAOS-INTR-QUUX`, which
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
    interrupt from word 100 <3> (<4> from revision 11, below) and puts the key word into the wired
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
    contract Q2). The feature page, 17377000 (17777400 from revision 11,
    below), is QUUX's register page: word
    100 says who interrupted (<0> the tick, <1> the interval timer, <2>
    block-disk; revision 11's order below), a write to word 101, the error status, clears it, and bit
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
  - **The video controller is the display** (MONO TV until muir's contract
    Q13 renamed it, below). QUUX's display is a 1-bit frame buffer at
    physical 17000000, 1920 by 1080 at 60 words a line by default, with no
    sync program and no interrupt; muir can make it other sizes. The
    feature page gives its size, words 11-13, and the cold load reads them
    (`SI:VIDEO-WIDTH`, `-HEIGHT`, `-WORDS-PER-LINE`, `-BUFFER-ADDRESS`
    and `-BUFFER-LENGTH` in `sys/ltop.lisp`, each field taken out of its
    word with `%P-LDB`, since the cold load cannot take a bignum apart).
    The main screen is made from them when the window system loads
    (`window/shwarm.lisp`), the cold boot clears the whole buffer, the run
    lights follow the screen's size, and `SET-TV-SPEED`, which loaded the
    CADR TV's sync program, says there is none. The microcode's first
    run-light address is inside the video controller's default buffer, and `INTRX0` no
    longer reads the CADR TV's vertical flag.
  - **One band runs at any video controller size.** The window system is made at
    the size the feature page gave when the band was built, so at every
    boot `TV:SET-SCREENS-TO-VIDEO` (`window/shwarm.lisp`) moves the
    main screen, the who line and every window to the size it gives now:
    it shrinks the screens to the smaller of the two sizes, points every
    array at the new words per line and buffer, and grows them to the new
    size, the main screen scaling its windows. It follows MIT's
    `SET-TV-SPEED` and the Lambda's `SET-SCREEN-WIDTH`, and resets the
    Chaosnet first, as a window's change of size can let the scheduler
    run before the Chaosnet's own reset. The cold-load stream, which was
    the CADR's 768 by 896, takes the video controller's size when it is made and at
    every boot (`:SET-VIDEO`, `window/cold.lisp`), and the run lights
    are placed from the feature page (`sys/ltop.lisp`), not from a main
    screen that may still have the old size. Tested with a band built at
    1280 by 1024 and booted at 1024 by 768, 1280 by 1024 and 1920 by
    1080, the largest size supported.
  - **The TV sync program is gone, and with it most of the TV registers.**
    The video controller has no sync program, and of the CADR TV's control registers
    QUUX kept only register 0's black-on-white bit and register 4, the
    color map (the user); from revision 11 its one register is its mode,
    the register page's word 210, and register 4 is gone (below). So the sync routines and tables go from
    `window/cold.lisp` (`READ-SYNC`, `WRITE-SYNC`, `START-SYNC`,
    `STOP-SYNC`, `FILL-SYNC`, `CHECK-SYNC`, `SETUP-CPT`, `PROM-SETUP`,
    `CPT-SYNC2`), `SYNC-RAM-CONTENTS` from `window/shwarm.lisp`, and the
    CADR debugger's TV sync code from `cc/dmon.lisp`. The color TV code
    stays for a color display like the video controller, without its sync programs or
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
    2000 never runs with a map, a PDL buffer, an instruction or a clock the
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
    shows, is 4 under microcode 2000, the new constant `SI:QUUX-TYPE-CODE`
    (`window/cold.lisp`, exported from `cold/system.lisp`), after the Lambda's
    2 and the Explorer's 3; 323 gives the CADR's 1, `SI:CADR-TYPE-CODE`.
  - `cold/qcom.lisp`: `SIZE-OF-HARDWARE-LEVEL-2-MAP` is 4000, QUUX's, and
    the system communication area's layout comment gives both machines'.
- **The boot PROM, version 2000,** serves both machines. MIT's PROM (version
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
  Tested on muir 08a5fa3 with block-disk: the PROM loads the microcode, a
  cold load boots and QLDs, the saved band boots; Lisp reads the label and
  a band's first blocks, writes and reads back a block, read-compares, and
  a read past the end reports it; the host's reading of the pack agrees.
- **QUUX's disk in standard formats** (muir's contract Q8, approved by the
  user on 2026-09-25; in progress):
  - **The boot PROM saves nothing and writes nothing to the disk.** MIT's
    PROM used physical page 0 as its buffer, so it rewrote page 0 for good
    parity, saved it to disk block 1 and read it back at the end; on a disk
    with a GPT, block 1 is the partition table. Its buffer is now physical
    page 3, the first of pages 3-6 that the microcode's main-memory section
    (the microcode symbol area) fills: the PROM records that section when
    it meets it and loads it last, after the last word has been read
    through the buffer. `SAVE-A-PAGE`, its 0.1 s delay, `PAGE-0-PARITY-FIX`,
    `DISK-WRITE` and the read-back are gone. Two new error halts:
    `ERROR-TWO-MAIN-MEM-SECTIONS` for a second section with blocks, and
    `ERROR-BUFFER-NOT-LOADED` if the section does not cover page 3, checked
    before anything is loaded. The halts before them keep their addresses;
    `GO` moves from 36037 to 36043 (`ucadr/promh.text`). Tested on muir
    b7d3e82, micro and rtl, with band dev9: cold and warm boots keep the
    world; up to the microcode's location 6 the pack is unchanged, and of
    main memory only pages 3-6 and word 777 change.
  - **QUUX's `.mcr` is written in partition order**: each word's low half
    first, as the word lies in a microcode partition, padded to a whole
    block, so `dd` writes the file into a partition with no conversion. The
    same writer makes the boot PROM's file. `UA:*MCR-PARTITION-ORDER*`,
    `T` by default, bound to `NIL` gives MIT's order (`sys/qwmcr.lisp`).
    Lisp's readers of `.mcr` files still expect MIT's order:
    `READ-MCR-FILE` (`sys2/usymld.lisp`) and `COMPARE-MCR-FILE`
    (`cc/cadld.lisp`); `SI:LOAD-MCR-FILE` takes partition order (below).
  - **The boot PROM finds the microcode through the GPT**
    (`ucadr/promh.text`), in place of MIT's label. Block 0 is sectors 0
    and 1, so the header is its words 200-377: the signature "EFI PART" in
    words 200-201, the entry array's first sector in 222 (even, and 223
    zero) and an entry's size in 225 (200 bytes), or it halts at
    `ERROR-NO-GPT`. It reads the entries a block of eight at a time into its
    buffer and takes the first of the microcode's type (by the type's first
    word) with attribute bit 48; it halts at `ERROR-NO-CURRENT-MICR` if none
    is current and at `ERROR-ODD-MICR-START` if that partition starts on an
    odd sector. The partition's length is its own, from the entry. The new
    halts are after the last code (36632, 36634, 36636), so `GO` stays at
    36043; `ERROR-BAD-LABEL` and `ERROR-NO-MICR` are no longer reached. It
    still writes nothing to the disk, and in main memory only pages 3-6 and
    word 777. Tested on muir 7dfc41c, 0d14efc and 53ee46d, micro and rtl,
    with microcode `ucode-1000-gpt2` and the GPT band: cold boot, a warm
    boot that keeps the world, a save into LOD3 and `(disk-restore 3)` into
    it at 1280x1024; it boots with MCR1 current, with MCR2
    current (MCR1 zeroed), with both current (MCR2 zeroed: the first is
    taken), with the microcode's entry in the second block of entries, and
    with the entry array moved to sector 12; it halts at its named error on
    disks with none current, an odd start, a broken signature and an odd
    entry-array sector; both GPT copies are unchanged after every boot.
  - **The microcode reads the GPT** (`ucadr/uc-cold-disk.lisp`).
    `COLD-READ-GPT` replaces `COLD-READ-LABEL` and `COLD-FIND-PARTITION`.
    It checks for "EFI PART" in LBA 1 (block 0, word 200), for an even entry
    LBA and for 128-byte entries. It reads the entry array a block (8
    entries) at a time and scans every entry. The first PAGE entry gives
    `A-DISK-OFFSET` and `A-DISK-MAXIMUM`. The band is the first band (LOD)
    entry whose name starts with the four characters asked for; with none
    asked, it is the first with attribute bit 48, the current band.
    `A-LOADED-BAND` is set as before. It halts at `GPT-MISSING`,
    `GPT-NO-PAGE`, `GPT-NO-BAND` (no current band, or none of that name) or
    `GPT-ODD-START` (a partition that is not whole blocks); the halt's PC
    is the named location plus 1. An LBA is halved to a block. It reads
    into a page and uses a CCW address given by the caller, in new A
    variables (`A-GPT-BUFFER-PAGE`, `A-GPT-CCW`, `A-GPT-BLOCK`,
    `A-GPT-COUNT`, placed last so nothing moves, `ucadr/uc-parameters.lisp`).
    The cold boot and `%DISK-RESTORE` use page 0 with CCW 777, and
    `%DISK-SAVE` uses the copy buffer. The warm boot (`WARM-READ-GPT`)
    parks physical page 0 in PDL buffer 0-377 while it reads. So the
    microcode no longer writes blocks 1, 3 and 5, where MIT's saved pages
    0-2 and where GPT entries now are.
  - **Lisp reads the GPT** (`io/disk.lisp`). `READ-DISK-LABEL` reads block 0
    and up to 16 blocks of entries (`DISK-LABEL-RQB-PAGES` is 17). New
    accessors give an entry's type (by muir's four type GUIDs,
    `GPT-PARTITION-TYPES`), its name (the first four characters), its
    comment (after a space, at most 31 characters), bit 48, its start and
    its size. `FIND-DISK-PARTITION-BY-TYPE` finds a partition by type,
    optionally only one with bit 48. `FIND-DISK-PARTITION`, `PARTITION-LIST`
    (every used entry), `PARTITION-COMMENT` and their
    callers keep their signatures. `DISK-INIT` finds PAGE by type.
  - **The machine writes no GPT.** `WRITE-DISK-LABEL`, `SET-PACK-NAME`, the
    label editor and `COPY-DISK-LABEL` signal that they are retired and to
    use sgdisk. `UPDATE-PARTITION-COMMENT`, which `DISK-SAVE` calls, and
    `SET-CURRENT-BAND` and `SET-CURRENT-MICROLOAD` write nothing; each
    prints the sgdisk command that would do the change (`io/disk.lisp`,
    `io/dledit.lisp`). `CURRENT-BAND` and `CURRENT-MICROLOAD` go by type
    and bit 48. `FIND-MICROCODE-PARTITION` goes by type and the comment
    "UCADR n". `DISK-RESTORE` with no band restores the band with bit 48
    (`sys/qmisc.lisp`). `PRINT-DISK-LABEL` prints the GPT.
  - **The herald and `MACHINE-INSTANCE` name the machine from the host
    table** (`SI:LOCAL-MACHINE-NAME`, looked up when printed), since the GPT
    has no pack name (`io/disk.lisp`, `sys/genric.lisp`).
  - **`SI:LOAD-MCR-FILE` copies a partition-order `.mcr` unchanged.** It
    also writes a partial last block, which MIT's dropped (`io/disk.lisp`).
  - **A QUUX disk is at most 8 GiB** (2^24 LBAs), so the microcode and Lisp
    read only an LBA's low word.
  Tested on muir 7dfc41c, on T-300-size disks with a GPT, with a test PROM
  that loads the microcode from block 17 (the real PROM's GPT reader was not
  done yet). Cold boots by bit 48 of LOD4, LOD3 and LOD1; QLD; saves into
  LOD4, LOD1 and LOD3; an incremental save and its cold boot from its base
  band, found by name; a warm boot that keeps the world; `LOAD-MCR-FILE`.
  The Lisp readers match a host oracle, and the halts match negative disks.
  Both GPT copies are byte for byte unchanged after every run, and
  `(disk-restore 3)` works at 1280x1024, 1024x768 and 1920x1080 (the next
  item).
- **`%DISK-RESTORE` from a running band no longer hangs** (found and
  measured by muir). `DISK-RESTORE-1` gives the disk registers and the run
  light each a fake level-2 entry in the invalid block, in the slot their
  VMA<12:8> picks, so the two must differ. Lisp moves the run light to the
  video controller's last line (`TV::INITIALIZE-RUN-LIGHT-LOCATIONS`, `sys/ltop.lisp`).
  When the buffer is a multiple of 8K words, as at 1280x1024 and 1024x768,
  that is slot 37, the registers' own. The second entry replaced the first,
  the disk commands went to the frame buffer, and `DISK-AWAIT-READY` waited
  for ever on the command word it had written itself. A cold boot never
  hit this, because its run light is still at the microcode's boot address.
  `DISK-RESTORE-1` now resets `A-DISK-RUN-LIGHT` to that boot address
  before the two entries, as a cold boot has it; Lisp sets it again after
  the restore. A guard between the two entries halts at
  `RUN-LIGHT-SHARES-DISK-SLOT` if the two ever share a slot, rather than
  hang (`ucadr/uc-cold-disk.lisp`). Microcode `run/ucode-1000-gpt2`. The
  guard fired, halting at its PC, in a test build that left the reset out.
- **The band takes the PDL buffer's length from the machine.** A stack
  group's saved PDL phase is masked with `SI:PDL-BUFFER-LENGTH`
  (`sys2/proces.lisp`, and `eh/eh.lisp` rebuilding a frame), which was the
  CADR's 2000. It is set at every boot by `SI:MACHINE-PDL-BUFFER-LENGTH`:
  QUUX's feature page, word 3 (16384), or 2000 on a CADR, since a band can
  be booted on either machine.
- **Serve the running microcode's table.** A band whose microcode is not the
  one it was saved with reads `SYS: UBIN; UCADR TBL` at boot, so the served
  `SYS: UBIN;` must hold that microcode's `ucadr.tbl`.
- **A boot takes the time from QUUX's real-time clock** (muir's contract Q9,
  revision 9), so it asks the network for the time no more.
  `TIME:RTC-UNIVERSAL-TIME` reads word 103 of the register page, Unix
  seconds, when feature word 15 `<0>` says the clock is there, and adds
  2,208,988,800; `%XBUS-READ` returns the word signed, so a negative value,
  from 2038-01-19 on, has 2^32 added back. `INITIALIZE-TIMEBASE` reads it
  ahead of the network, which stays the source below revision 9, and
  `SET-LOCAL-TIME` reads neither: with no argument it still asks for the
  time. The clock is read-only; the time zone stays the site's
  (`io1/time.lisp`). Tested on muir 09e88ef with `--rtc` at 1790000000,
  2^31 and 2^32-1 and on the host's clock: the universal time is the clock
  plus the constant, and a boot sends no TIME request; on a revision 8
  muir the band asks for the time as before.
- **With the real-time clock, the wall clock reads it every time** (Q9, the
  user's ruling relayed by muir): `GET-UNIVERSAL-TIME` returns the clock
  plus `TIME:*RTC-OFFSET*`, and `UPDATE-TIMEBASE`, under `GET-TIME`, the
  who-line's clock, `PRINT-CURRENT-TIME` and the rest, decodes it, instead
  of counting seconds on the microsecond clock from a base taken at boot.
  The offset is 0, or what a time given to `SET-LOCAL-TIME` differs from the
  clock (`INITIALIZE-TIMEBASE` sets it, and keeps uptime as before); it is
  NIL without the clock, and the old count stands. The time is unknown
  exactly when it was (`*LAST-TIME-UPDATE-TIME*` NIL). `(TIME)`, timeouts,
  `PROCESS-SLEEP` and the scheduler stay on the tick and the microsecond
  clock (`io1/time.lisp`). Tested on muir e11026a, micro unpaced, with the
  change saved into a band: with `--rtc` fixed, `GET-UNIVERSAL-TIME` equals
  the clock at every sample over 65 s (it and the old count agree in rate
  there, but the count lagged the clock by up to a second); on the host's
  clock it equals the clock and the host's second, where the old count ran
  11 s ahead in 66 s; the who-line shows the clock's time; on muir 53ee46d
  (revision 8) the offset is NIL and the band asks the network, as before.
- **Files from QUUX's host through the file device, as `HOST:`** (muir's
  contract Q9, revision 9; migration step M2: `SYS:` stays on OZ).
  `io/fdev.lisp` drives the device polled, with its interrupt enable off:
  command and response rings of 16 entries of 8 words in one wired page,
  two wired pages a slot for names, a stream's data in its own wired
  four-page RQB, one READ or WRITE a page naming only the bytes wanted.
  Responses come in command order, so the tables are indexed by the command
  number. The reset (disable, wait for quiet with a timeout and a message,
  ring bases and sizes, enable, check the status) runs in
  `LISP-REINITIALIZE` before the error table is read, so every boot, cold or
  warm, re-points the device at the rings; a `:BEFORE-COLD` initialization
  disables it before a `DISK-SAVE`, and the next command enables it again.
  A command in flight at a disable may have taken effect on the host without
  an answer, and its waiter is told so. The constants are
  `SI:%FILE-DEVICE-...`, in that file alone.
- **`HOST`, the pathname host** (`io/file/hostfs.lisp`): Unix syntax, so
  `HOST: /sys/io/disk.lisp` names what `OZ: /sys/io/disk.lisp` names; on no
  network, so QFILE never takes it; the same instance always, put on the
  pathname host list when the file is loaded (before any translation names
  it) and again after `SITE-PATHNAME-INITIALIZE` drops every file host
  (`network/host.lisp`). Its access opens, reads, writes (supersede, error,
  append; the file lands whole at CLOSE), probes, lists directories (the
  wildcards matched in Lisp, exactly), completes, deletes, renames (never
  over a file) and creates directories. Characters are translated by the
  streams with ozd's tables, measured through ozd for all 256 bytes: reading
  maps LF to Return and CR to Line, Return and Line back to CR and LF, and
  BS, TAB, FF and DEL to their Lisp Machine characters and back; writing is
  the inverse. `:CHARACTERS :DEFAULT` is decided by the QFASL magic, as ozd
  does. Dates are the device's Unix seconds plus 2,208,988,800, never text;
  an output file's creation date comes only from CLOSE's reply, and
  `COPY-FILE` keeps a file's date. The home directory is
  `HOST: /home/<user>/`, the user id in lower case. Names are checked (1 to
  255 bytes of 040-176 a component) and `..` resolved before a command is
  sent. muir e11026a's own behaviour, as built: a DIRECTORY of a missing
  directory is DNF, names the host refuses are not listed, writes in
  progress (`.quux-write-*`) are hidden, and a name the host refuses with
  EINVAL is IPS.
- **The cold load reads its files through the file device** (muir's
  contract Q9, revision 9; migration step M3: after MINI, QLD still takes
  `SYS:` from OZ over Chaos). MINI (`cold/mini.lisp`) keeps a command ring
  and a response ring of two entries each and one 512-byte buffer in the
  free words `#o1100`-`#o1377` of `SCRATCH-PAD-INIT-AREA`, which is wired
  and straight-mapped. It resets the device (disable, quiet, ring bases,
  enable, check the status) whenever it finds the device off or with other
  rings, sends one command at a time and polls the response index: OPEN,
  a READ at an offset for each 512 bytes, CLOSE at the end of the file, and
  LOG. No server address is compiled into it any more, and it no longer
  touches the Chaos interface. Characters go through the same byte mapping
  ozd applied to MINI's character files, measured over Chaos on all 256
  bytes: BS, TAB, LF, FF, CR and DEL become Backspace, Tab, Return, Page,
  Line and Rubout, and those six characters' codes become BS, TAB, LF, FF,
  CR and DEL. The truename is the name asked for, and the date string is
  the file's time as ozd wrote it. The reports go to muir's log with the
  LOG command as `report: ...`, so a build watches muir's log for
  `report: script-ends`. MINI also logs one `mini: read NAME BYTES` line
  for each file. After QLD, `MINI-REPORT` uses the driver's
  `FILE-DEVICE-LOG` when it is loaded. Measured in a full build on QUUX
  (muir b777f19, micro engine), with the driver: 40 files, 1,508,398 bytes,
  all through the device, each byte for byte the host's file; the 38 that
  MINI also read over Chaos in the earlier build match it. ozd saw no MINI
  connection. QLD passed
  with no keys typed, and the band passed the usual checks.
- **`SYS:` is on `HOST`** (muir's contract Q9, revision 9; migration step
  M4). `site/sys.translations:31` names `HOST` as `SYS:`'s physical host,
  and the associated machine of LISPM-1 to LISPM-7 is `HOST`
  (`site/lmlocs.lisp:13-22`), so a login and the home directory on `HOST`
  need no Chaos peer; `site/site.lisp:16-19` says what OZ is still named
  for. A boot reads its error table through the file device and reaches the
  herald with no ozd and no Chaos peer at all, with the time from the
  real-time clock, and QLD runs the same way. The band was built on QUUX
  (muir b777f19, revision 9, micro engine) with dev11's microcode and PROM:
  the builder moved `SYS:` to `HOST` in its running world, recompiled SITE
  and SYSTEM (`:RECOMPILE`, 211 files, 1 h 52 min) through `HOST`, and made
  the cold load, all with ozd serving no file; the cold load then booted
  with no ozd and no Chaos peer, and COLDRUN ran QLD (16 min 22 s; MINI read
  40 files, 0 refused) and saved the band in LOD4 (21,207 blocks). The same
  cold load's QLD and save also ran on muir's rtl engine (53 min to the
  save, 21,191 blocks). In the band, every file of SYSTEM was loaded from
  `HOST`, 210 of SYSTEM's 215 QFASLs record a `HOST` source (the other 5
  record none), `(make-system 'system :print-only)` lists nothing (before,
  it listed `SYS: IO1; TIMPAR QFASL`), and the properties of all 430 of
  SYSTEM's sources and QFASLs are the same after a warm boot, after a
  restart of muir and on the rtl engine. The herald came 11.7 to 13.4 s
  after muir started (micro, with other machines running), against 13.9 and
  18.5 s for the previous band, whose `SYS:` is on OZ; reading the error
  table takes 7.12 s of the machine's time either way, the reader's work,
  not the transfer.
- **The boot PROM resets the devices and gives timer 0 its period** (muir's
  contract Q11, QUUX revision 10; in progress: the Q11 microcode comes
  after M4). On revision 10 a rise of `INTERRUPT-CONTROL<28>` resets no
  device and timer 0 has no reset period, so with the old PROM a reboot
  left timers and the file device running into the new microcode, and the
  band's tick never rose. The PROM no longer pulses `<28>` for 80 us
  (`ucadr/promh.text:402-415`, commented out); after the map and error stop
  it writes the register page's word 104 with `<0>` set, reset devices, and
  then word 111, timer 0's period, with 16,667 us, before its first disk
  command (`ucadr/promh.text:476-500`). Timer 0 stays off; the band turns it
  on at `BEG06`. On revision 9 both words are reserved, so this PROM resets
  no device there: a file device left enabled runs on through the PROM
  until the microcode's `RESET-MACHINE` pulses `<28>`. `GO` stays at 36043;
  the code ends at 36646 (was 36636), and the GPT halts move to 36642,
  36644 and 36646. Tested with dev11's microcode on muir 7a5136c (revision
  10) and b777f19 (revision 9), micro and rtl, with bands dev11 and M23b:
  each boots to its listener, and to it again after a `%DISK-RESTORE`, and
  `INTR-TICK` runs 600 times in 10 s of simulated time after each on both
  revisions (with the old PROM on revision 10: 0); muir's M9, M10 and M11
  pass with it, and fail with the old PROM.
- **The microcode resets the devices and runs the tick on the register
  page** (muir's contract Q11 and its Q9 reset amendment, QUUX revision 10;
  assembled as microcode 1000, then renumbered 2000 with the system). It
  needs revision 10: `RESET-MACHINE` first checks `MACHINE-ID` for the signature and a revision
  of 10 or more and otherwise halts at `MACHINE-NOT-QUUX-10`, before it
  writes the register page (`ucadr/uc-cold-disk.lisp:5-17`, the halt at
  :166-170); below revision 10 words 104 and 110-115 are reserved, so it
  would reset nothing and never start the tick. `INITIAL-MAP-A`'s own check
  stays at 6 (:85-91). In place of the 10-microsecond pulse of
  `INTERRUPT-CONTROL<28>` (commented out, :25-29), which drives nothing on
  revision 10, `RESET-MACHINE` writes word 104 with `RESET-DEVICES` (`<0>`)
  set (:30-32), so that a `%DISK-RESTORE`, which does not pass through the
  PROM, still leaves no file device enabled to complete queued commands into
  the new band's memory, and resets block-disk and the network as the pulse
  did; it then reads word 161 until the file device is quiet (`<1>`), for at
  most 2 seconds, the driver's own bound until muir-fpga measures the
  boards', and halts at `FILE-DEVICE-NOT-QUIET` past it (:33-47, the halt at
  :172-177); then it writes timer 0's period, 16,667 us, to word 111, since
  reset devices zeroes it (:51-55). `BEG06` turns the tick on by a write of
  401 to word 110 (on, periodic, its interrupt enable) through the map, and
  `INTR-TICK` clears it with 403, in place of their destination 3 writes
  (`ucadr/uc-cold-disk.lisp:884-896`, `ucadr/uc-interrupt.lisp:368-378`).
  Revision 10 keeps no alias of timer 0 there: destination 3 writes only M,
  as destination 4 does (Q11 as amended on 27 Sep; muir 1a89ed0), so a band
  on the previous microcode 1000 has no tick on revision 10, and this
  system's bands move to this microcode.
  `INTR` turns timer 1 or 2 off when word 100 `<1>` or `<7>` (`<2>` from
  revision 11, below) interrupts,
  since nothing uses them and a level nothing clears would interrupt for
  ever (`ucadr/uc-interrupt.lisp:75-82`, `INTR-TIMER-1-STRAY` and
  `INTR-TIMER-2-STRAY` at :350-361). The register page's new words are
  named in `ucadr/uc-cadr.lisp:65-82`. The assembler no longer names
  `TICK-CONTROL`, `INTERVAL-PERIOD` and `TICK-STATUS`, codes revision 10
  does not have; they came with QUUX's tick, and the CADR's microcode never
  named them (`sys/cadsym.lisp:453-466`, commented out).
  `SI:PRINT-FEATURE-PAGE` names words 15 and 16, the RTC and file device and
  the number of interval timers, and word 14 the microsecond clock alone
  (`sys/genric.lisp:1839-1853`). Named A, M and D memory is where it was, so
  bands saved on the previous microcode 1000 run on this one with its
  `UCADR TBL` served. Tested with band M4a (System 1002, Q9's step M4) on
  muir 947926e (revision 10) and b777f19 (revision 9), micro and rtl, each
  check also run against dev11's microcode or against this microcode with
  the one step taken out: on revision 9 it halts at `MACHINE-NOT-QUUX-10`
  with no write of words 104 or 110-115, with either PROM, and reaches
  them with the check's jumps removed; on revision 10 `INTR-TICK` runs 600
  times in 10 s of simulated time after the listener, with ten clock
  sequence breaks, and the mouse moves, also with dev11's PROM, which
  writes no period (dev11's microcode with that PROM: 0); it writes
  destination 3 not at all where dev11's microcode wrote it 363 times; a
  stray timer 1 or 2 costs one interrupt where dev11's microcode took
  18,000 in 50 ms; a `%DISK-RESTORE` and a warm boot through the PROM with
  the file device busy and timers 1 and 2 on reach the listener as fast as
  without, `RESET-MACHINE` reads word 161 once, no queued command runs
  after the reset, the driver finds the device disabled at its boot reset
  and a warm boot keeps the canary, where the same microcode without its
  word 104 write and wait (and dev11's PROM, for the warm boot) runs the
  queued commands and leaves the device enabled; a cold load's QLD through
  MINI reads the same 40 files, 1,508,936 bytes.
- **The register page is at 17777400, with block-disk and the video
  controller on it, and word 100 in its final order** (muir's contract
  Q13, QUUX revision 11; PROM 2000, microcode 2000 and System 2000 keep
  their numbers, being unreleased, and their files change). The page moves
  from 17377000 to the last page of the physical space, 17777400-17777777,
  fixed, so that the frame buffer may grow up to below it; block-disk's
  registers move from 17377774-17377777 to its words 200-203, and the
  video controller's mode from 17377760 to its word 210. Nothing answers
  at the old addresses on revision 11.
  - **The PROM** maps its virtual page 2 to physical page 37777, not 36776,
    and reaches block-disk at virtual 1200, word 200 of that page, not 774
    through page 1, which it no longer maps (`ucadr/promh.text:440-470`, the
    old lines commented out); two no-ops keep every later PROM address where
    it was, `GO` at 36043 and `DISK-AWAIT-PACK` at 36600 among them, and
    `promh.sym`, `.tbl` and `.locs` are unchanged: five words of the
    `.mcr` differ.
  - **The microcode** makes every register-page address from one base,
    `QUUX-REGISTER-PAGE-VIRTUAL-ADDRESS` 77777400 and its physical twin
    17777400 (`ucadr/uc-cadr.lisp:19-36`, :55-73, :78-121, the old
    `ASSIGN`s commented out). `INTR` reads word 100 in revision 11's order,
    `<0>`-`<2>` timers 0-2, `<3>` block-disk, `<4>` the keyboard, `<5>` the
    mouse, `<6>` the network, `<7>` the file device, keeping revision 10's
    priority (`ucadr/uc-interrupt.lisp:60-100`), and every bit now has a
    handler that clears its level or a stray that turns its enable off, so
    a stray enable costs one interrupt, not a storm: `INTR-DISK` takes
    block-disk's done to `DISK-COMPLETION` while a disk operation is
    pending and otherwise writes the command register 0, clearing `<11>`;
    `INTR-MOUSE-STRAY` writes word 123 0; `INTR-FILE-DEVICE-STRAY` writes
    word 160 back with `<8>` clear and `<0>` kept (:376-413). `RESET-MACHINE`
    asks for revision 11 and halts at `MACHINE-NOT-QUUX-11` below it
    (`ucadr/uc-cold-disk.lisp:5-23`, the halt at :172-178).
  - **Lisp** takes the page from `SI:FEATURE-PAGE-XBUS-ADDRESS`, now
    `#o777400` (`sys/ltop.lisp:114`), which `io/fdev.lisp`, `io1/time.lisp`
    and `sys2/proces.lisp` follow; the literals move with it: MINI's
    registers (`cold/mini.lisp:54-63`), the Chaosnet interface's
    (`network/chaos/chsncp.lisp:724`), the keyboard's interrupt enable
    (`window/cold.lisp:583`), the mouse (`window/mouse.lisp:49`), the mode
    and error status (`window/color.lisp:35-38`), block-disk's status
    (`io/disk.lisp:136`), and the video controller's mode, `#o777610`, the
    main screen's, the who line's and the cold-load stream's control
    address (`window/shwarm.lisp:1905`, `window/wholin.lisp:62`,
    `window/cold.lisp:1122`). `SI:PRINT-FEATURE-PAGE` prints the page's
    address without "Xbus" (`sys/genric.lisp:1866`).
  - **MONO TV is renamed the video controller**:
    `SI:VIDEO-WIDTH`, `-HEIGHT`, `-WORDS-PER-LINE`, `-BUFFER-LENGTH` and
    `-BUFFER-ADDRESS` (`sys/ltop.lisp:121-143`, the old definitions
    commented out), `TV:SET-SCREENS-TO-VIDEO`, `SCREEN-SET-VIDEO` and
    `SHEET-SET-VIDEO-PITCH` (`window/shwarm.lisp`), and the cold-load
    stream's `:SET-VIDEO` (`window/cold.lisp:1100`). `tools/lispm-check`
    passes muir-sim's `--video-size`, which replaces `--mono-tv-size`.
  - The band is built from its cold load, since the cold load and the
    screens saved in the band carry the old addresses. The builder (band
    M4a, whose Lisp reads the old page) compiled and made the cold load on
    muir-sim 4e0ca1b (revision 10) with the old microcode; the cold load
    then booted on muir-sim bba9b3a (revision 11) with the new PROM and
    microcode, and MINI read QLD's 40 files through the file device.
  - Tested on muir-sim bba9b3a, micro and rtl, at 1024x768, 1280x1024 and
    1920x1080: from power-on, after a `%DISK-RESTORE` and after a warm boot
    through the PROM the band reaches the listener, word 110 reads 401 and
    111 16,667, and `INTR-TICK` runs 600 times (599 twice) in 10 s of
    simulated time; after each, typed forms log in and load a file from
    `HOST:`, which writes one back holding `SI:PRINT-FEATURE-PAGE`'s "at
    17777400" with revision 11, the main screen's, the who line's and the
    cold-load stream's control address 777610, black-on-white toggled and
    read back at word 210 (4, then 0), word 103 equal to
    `GET-UNIVERSAL-TIME`, and a block written to LOD2 through block-disk
    and read back whole, which the host finds on the disk. A stray enable of
    the mouse, of timer 2, of block-disk's `<11>` with the disk idle and of
    the file device with responses waiting each enters its handler once,
    the file device staying enabled, where microcode 2000 before this
    change took 2,504 interrupts in 50 ms for the mouse and 3,622 in a
    second for the file device. On the `quux` executable (`--video-size
    1280x1024`, ozd as the Chaosnet peer) the herald names System 2000 and
    QUUX, TELNET reaches the listener over the Chaosnet, and `HOST-UP-P` of
    OZ is T. Across revisions: the old microcode, loaded by the new PROM on
    revision 11, halts at `FILE-DEVICE-NOT-QUIET`; the old PROM on revision
    11 and the new PROM on revision 10 wait at `DISK-AWAIT-PACK` (36600);
    the new microcode, loaded by the old PROM on revision 10, halts at
    `MACHINE-NOT-QUUX-11`.
- **The microcode fills the MACRO DISPATCH MEMORY and turns the fused
  return on** (muir's contract H8a, QUUX revision 12, plan slice S5;
  microcode 2000 keeps its number, being unreleased, and its files change).
  On revision 12 a return to the main loop that needs no instruction fetch
  runs the next macroinstruction's handler straight from the MACRO
  DISPATCH MEMORY, two microcycles sooner, once the MACRO-DISPATCH register
  is enabled; the enable is off after -RESET and cleared by every
  control-store write. So at every start of the microcode, before its first
  main-loop return (a cold or warm boot through the PROM, and a
  `%DISK-RESTORE`, which runs the microcode already loaded),
  `RESET-MACHINE` reads the feature page's word 17 and, when it is not 0,
  writes each of the 1,024 entries with `OPDTB`'s entry for its opcode,
  operand bit clear, then the register with `QMLP`, `A-LOCALP`'s and
  `M-AP`'s addresses and the enable (`ucadr/uc-cold-disk.lisp:65-99`).
  These are the generic handlers only, so the machine does what it did,
  sooner; specialised handlers are the next slice. The microcode cannot
  read D-MEM, so `OPDTB`'s 32 entries are kept a second time in A memory,
  `A-MACRO-DISPATCH-GENERIC`, after every earlier location
  (`ucadr/uc-parameters.lisp:1255-1297`; the unused opcodes' P and N are
  written as D-MEM's bits, 140000, since the assembler's `P-BIT` and
  `INHIBIT-XCT-NEXT-BIT` are the jump instruction's). The assembler names
  destinations 5 to 7 `MACRO-DISPATCH-REGISTER`, `MACRO-DISPATCH-INDEX`
  and `MACRO-DISPATCH-ENTRY` (`sys/cadsym.lisp:470-485`), and word 17's
  address is `QUUX-MACRO-DISPATCH-ENTRIES-PHYSICAL-ADDRESS`
  (`ucadr/uc-cadr.lisp:119-123`). No revision check: word 17 reads 0 below
  revision 12, where the fill is skipped, and destinations 5 to 7 would
  write only M there anyway. I memory grows by 15 words, all at or after
  `RESET-MACHINE`'s fill (every address before 26437 stays), and A memory
  by the 32-word table, which moves the A constants; named A, M and D
  memory stays where it was, so band 2000 runs on this microcode with its
  `UCADR TBL` served, and no band is rebuilt.
  - Tested on muir-sim cd072dc (S2), micro and rtl, with ref/band-2000's
    band and this microcode written over its MCR1, the RTC counted: on
    revision 12 `RESET-MACHINE` takes 8,275 microcycles, 67 before (the
    fill 8,193, the check 15), twice in a cold boot; at `BEG06` the
    register reads 22121500124 (octal: the enable, `M-AP` 21, `A-LOCALP`
    432, `QMLP` 124) and every entry equals D-MEM's `OPDTB` entry for its
    opcode; the band reaches the listener with 2,346,606 returns fused on
    micro and 2,330,433 on rtl, where muir-sim's own fill of the memory at
    the first `QMLP` gave 2,346,612 and 2,330,619. After a
    `%DISK-RESTORE` whose entry found every entry poisoned to `ILLOP` with
    the register left enabled, and after a warm boot through the PROM with
    the entries poisoned at 36000, every entry and the register are as a
    fill leaves them at `BEG06`, the listener comes back, and returns fuse
    again (2.33 million to the listener after the warm boot). Destinations
    5 to 7 are written only at the fill's three sites. On revision 11 the
    check costs 15 microcycles a start: `BEG06` comes 316 microcycles later
    on micro and 342 on rtl than with the microcode before this change,
    and the listener at the same step. muir-sim's profile on rtl (sync
    K=4, 4K cache, the Arty's memory timing): over its 12 workloads
    revision 11 runs 442,484,000 microcycles, as with the microcode before
    this change, and revision 12 fuses 6,629,269 returns and runs 2.98%
    fewer microcycles. `(car 5)` and twelve other forms answer the same
    on revision 12 with this microcode as with the one before.
- **No write the fused return forbids in the microcycle after a return**
  (muir's contract H8a section 3.3, as amended after its S3 review;
  microcode 2000 keeps its number, and its files change again). A fused
  return has chosen the next macroinstruction's handler before the
  microinstruction an XCT-NEXT runs after the return, and, when the
  handler's entry has the operand bit, loads PDL-INDEX with the operand's
  address at the end of it; so that microinstruction must not store in the
  PDL at PDL-INDEX (the word would land at the operand's address), nor
  write PDL-INDEX, `A-LOCALP`, `M-AP`, the location counter or M 31. 29
  `POPJ-AFTER-NEXT`s did. At each, the write is now made before the
  return, and the machine's state after it is what it was:
  - where the write and the `POPJ`'s own microinstruction are independent,
    they trade places, in the same two microcycles:
    `INSTRUCTION-STREAM-FETCHER` (M 31, `ucadr/uc-macrocode.lisp:75-82`),
    `QLLOCB` (`A-LOCALP`, `ucadr/uc-call-return.lisp:2528-2535`),
    `PAGE-TRACE-1` (`ucadr/uc-meter.lisp:275-281`), `P-B-X1` and
    `P-B-SL-1` (`ucadr/uc-page-fault.lisp:1510-1531`);
  - elsewhere the write moves to the microinstruction before the `POPJ`
    and a no-op follows it, one microcycle more: `QSTLOC` and `QSTARG`,
    the stores into a local or an argument, where the reason is explained
    (`ucadr/uc-macrocode.lisp:330-354`); `QVMALCL` and `QVMAARG`, where
    MIT's note that the push must not be the last microinstruction (the
    PDL has no pass-around) is kept by the no-op after it
    (`ucadr/uc-macrocode.lisp:356-390`); `FINISH-ENTERED-FRAME`,
    `QLLV-TAIL-REC-ADI`, `XPERMIT-TAIL-RECURSION`, `QLLENT` (`A-LOCALP`),
    `MKWRIT`, `XOCB3`, `XMESL*`, `XFEC`, `XFECM`, `XFECMVL`, `XCTO1`,
    `XSET-SELF-MAPPING-TABLE-1` and `LOAD-PDL-BUFFER-INDEX`
    (`ucadr/uc-call-return.lisp`, at each label);
    `STACK-CLOSURE-CLEAR-3`, `STACK-CLOSURE-CLEAR-FOUND`,
    `MAKE-STACK-CLOSURE-VECTOR-ARG`, `MAKE-STACK-CLOSURE-VECTOR-EMPTY` and
    `MAKE-STACK-CLOSURE` (`ucadr/uc-stack-closure.lisp`); `PGF-R-PDL` and
    `PGF-W-PDL` (`ucadr/uc-page-fault.lisp:248-315`).

  And `RESET-MACHINE`, where the MACRO DISPATCH MEMORY exists, writes
  `A-LOCALP` and `M-AP` with their own values right after the
  MACRO-DISPATCH register (`ucadr/uc-cold-disk.lisp:99-106`): the
  hardware's copies of the two, from which it makes the operand address,
  are taken only from writes of the addresses the register names, never
  read back from A and M memory, so without these writes they would start
  a warm boot or a `%DISK-RESTORE` with whatever they held. I memory grows
  by 26 words (24 no-ops and the two writes); named A, M and D memory
  stays where it was, and no band is rebuilt; `UCADR TBL` changes, since
  error-table entries move.
  - Tested on muir-sim 5c31525, with ref/band-2000's band and this
    microcode written over its MCR1. muir-sim's scan of every return whose
    next microinstruction runs lists 29 sites on the microcode before and
    none on this one. With the operand bit on every entry whose operand
    is a register and delta (`MUIR_H8A=operand`), the band never reached
    its listener on the microcode before, on micro or rtl; on this one it
    runs muir-sim's profile of 12 workloads on both, and the checker
    counts no forbidden write, no wrong handler, no wrong operand address
    and no base copy differing from its memory over the whole run (on rtl
    10,453,776 fused returns, 4,339,445 of them loading an operand
    address). With muir-sim's register write changed to load no copy, as
    the amended contract has it, the copies differ from `A-LOCALP` at
    `BEG06` after a cold boot and after a `%DISK-RESTORE` on the microcode
    before, and equal them on this one. On revisions 11 and 12, micro and
    rtl, the band cold boots to its listener, survives a `%DISK-RESTORE`
    and a warm boot through the PROM with the MACRO DISPATCH MEMORY
    poisoned; on revision 12, 21 forms, stores into locals and arguments,
    locatives to them, closures and multiple values among them, answer
    the same as on the microcode before, `(car 5)`'s error message too. The no-ops cost 2,638,886
    microcycles over the profile's 12 workloads on rtl at revision 12,
    0.60% of 439,386,000 (0.05% to 1.55% by workload; sort the most),
    counted at the no-ops themselves; `QSTLOC` is 64% of it, the PDL page
    faults and `MKWRIT` 29%.
- **Specialised handlers, first family: MOVE D-PDL of a local or an
  argument** (muir's contract H8a section 4, plan slice S6; microcode 2000
  keeps its number, and its files change again). The most frequent
  macroinstruction gets a handler of its own, `QIMOVE-PDL-OPERAND`
  (`ucadr/uc-macrocode.lisp:458-473`): one microinstruction that pushes the
  operand's typed pointer with CDR-NEXT and returns, and in the
  microinstruction after its `POPJ` the same typed pointer into M-T, as
  `QADLOC1` leaves it, since a branch after the MOVE tests M-T. Only the
  MACRO DISPATCH MEMORY names it: `RESET-MACHINE` writes it, with the
  operand bit, at indexes 425 and 426 (destination D-PDL, opcode 2,
  register LOCAL or ARG) after the generic fill and the register
  (`ucadr/uc-cold-disk.lisp:107-119`). So it runs only from a fused return
  with no fetch needed, with PDL-INDEX already holding the operand's
  address; the main loop's dispatch still runs `QIMOVE`. It is new code
  beside `OPDTB`'s; no generic handler changed. Its first microinstruction
  reads the PDL only at PDL-INDEX, and the one after its `POPJ` writes only
  M-T (section 3.3). I memory grows by 6 words and A memory by 3 constants;
  named A, M and D memory stays where it was, and no band is rebuilt.
  - Tested on muir-sim 3c4b4dc (a `git archive` copy with the profile's
    checkers watching from the microcode's own fill), with ref/band-2000's
    band and this microcode over its MCR1. The profile of 12 workloads on
    rtl (sync K=4, 4K cache, the Arty's memory timing, the RTC counted from
    a fixed second, `cons` after an untimed first `cons`): 1,636,318 MOVEs
    ran it, each 2 microcycles from its handler's first microinstruction
    to the next handler's instead of the generic 6, 6,545,272 microcycles
    fewer; the workloads took 434,236,000 microcycles, 1.23% fewer than
    439,636,000 before. Over the whole run, on rtl and on micro, the
    checker counts no forbidden write after a fused return, no wrong
    handler, no wrong operand address, no base copy differing from its
    memory, and no read by a handler's first microinstruction of the PDL
    word the microcycle before it writes (2,253,618 operand addresses loaded
    on rtl). muir-sim's scan of every return whose next microinstruction
    runs lists none, as before. 23 forms (arguments and locals of every
    kind, many locals, a branch on a moved value, loops, recursion,
    closures, `&optional`, errors) answer on both engines as on the
    microcode before, but for one array's printed address.
- **Specialised handlers, second family: POP and MOVEM into a local or an
  argument** (H8a section 4, S6). `QIPOP-OPERAND` and `QIMVM-OPERAND`
  (`ucadr/uc-macrocode.lisp:314-337`) store the top of the stack, popped or
  not, at PDL-INDEX and leave it in M-T, as `QIPOP` or `QIMVM` and `QSTLOC`
  do, in the `POPJ`'s own microinstruction; their first microinstruction is
  a no-op, since it must not read the PDL at the pointer, where the push the
  microcycle after a return may make lands only after it (section 3.3).
  `RESET-MACHINE` names them, with the operand bit, at indexes 1735 and 1736
  (POP, opcode 33) and 1535 and 1536 (MOVEM, opcode 13)
  (`ucadr/uc-cold-disk.lisp:120-130`). I memory grows by 14 words and A
  memory by 5 constants.
  - Tested as the first family: 462,731 POPs and MOVEMs ran them, 3
    microcycles each instead of 8, 2,313,655 fewer; the workloads took
    429,987,000 microcycles, 2.19% fewer than before the first family; the
    checker and the scan find nothing on either engine; 34 forms answer as
    on the microcode before.
- **Specialised handlers, third family: BR, BR-NIL and BR-NOT-NIL** (H8a
  section 4, S6). Six handlers (`ucadr/uc-macrocode.lisp:667-729`): a
  branch's offset is its `<8:0>`, so the index's register field is the
  offset's top three bits, and `RESET-MACHINE` names the `-POS` handlers at
  register fields 0-3 and the `-NEG` ones, which extend the sign as
  `QBRLZ1` does, at 4-7, for BR at 140-147, BR-NIL at 340-347 and
  BR-NOT-NIL at 540-547, the operand bit clear
  (`ucadr/uc-cold-disk.lisp:131-154`). BR-NIL and BR-NOT-NIL test M-T's
  typed pointer against NIL as `QBRNL` and `QBRNNL` do; a branch not taken
  returns by a conditional `POPJ` whose next microinstruction is not
  executed, and one taken writes the location counter in its `POPJ`'s own
  microinstruction, as `QBRLZ2` does. Offset 777, the long branch whose
  offset is in the next halfword, jumps to `QIBRN`, which does all it does
  today. I memory grows by 49 words and A memory by 9 constants.
  - Tested as the first family: 920,338 branches ran them, BR-NIL and
    BR-NOT-NIL in 3 microcycles not taken instead of 6, and 5 taken
    forward and 7 backward instead of 8 and 11, BR in 3 and 5 instead of 5
    and 8: 2,832,845 fewer; the workloads took 427,937,000 microcycles,
    2.66% fewer than before the first family; the checker and the scan
    find nothing; 48 forms, forward, backward and long branches of each
    kind among them, answer as on the microcode before.
- **Specialised handlers, fourth family: SETE-1+, + and < of a local or an
  argument, on fixnums** (H8a section 4, S6). `QISP1-OPERAND`,
  `QIADD-OPERAND` and `QILSP-OPERAND` (`ucadr/uc-macrocode.lisp:763-827`)
  judge by the typed pointers alone: SETE-1+ takes a fixnum from 0 to
  2^24-2, + and < two from 0 to 2^23-1, where the typed pointers' order is
  the numbers' and a sum cannot overflow. Anything else (a negative fixnum,
  a character, a flonum, a bignum, no number) jumps to the generic handler
  of the opcode, `QIND2` or `QIND1`, which does all it does today, its
  errors included; `<`, which pops the top in its second microinstruction,
  puts it back first. The results are the generic ones: SETE-1+ stores the
  fixnum one bigger and leaves it in M-T, + replaces the top with the sum
  (CDR-NEXT) and leaves it in M-T, < pops the top and leaves T or NIL in
  M-T. Their first microinstruction reads the PDL only at PDL-INDEX. The
  entries, with the operand bit, are at 1525 and 1526 (SETE-1+), 315 and
  316 (+) and 525 and 526 (<) (`ucadr/uc-cold-disk.lisp:155-170`). I memory
  grows by 37 words and A memory by 11 constants.
  - Tested as the first family: 195,775 SETE-1+ ran in 5 microcycles
    instead of 24, 23,158 + in 9 (or more, falling back) instead of 19, and
    9,937 < in 9 instead of 18: 4,039,599 fewer; the workloads took
    424,436,000 microcycles, 3.46% fewer than before the first family; the
    checker and the scan find nothing. 72 forms answer as on the microcode
    before on both engines. In the 7 of them whose instruction a fused
    return dispatches, the counts of executed microinstructions show the
    fallback taken exactly as often as the operands ask for it (7 of 10
    calls of <, 2 of 4 with a local, 3 of 4 of SETE-1+: a negative, a
    flonum, a bignum, 2^23 or more), and each error through it names the
    instruction and the argument as before ("The second argument to <, QUX,
    was of the wrong type"). With all four families, `RESET-MACHINE` takes
    8,372 microcycles on revision 12 (8,277 before them) and 82 on revision
    11, as before; on micro and rtl, revisions 11 and 12, the band reaches
    its listener from power-on, after a `%DISK-RESTORE` that found the
    entries poisoned and after a warm boot through the PROM, and on
    revision 12 `BEG06` finds each time the 36 specialised entries and
    every other entry `OPDTB`'s.
- **No call in the microcycle after a return that can reach the main
  loop** (muir's contract H8a section 3.3; microcode 2000 keeps its number,
  and its files change again). A fused return has chosen the next
  macroinstruction's handler before the microinstruction an XCT-NEXT runs
  after the return, so that microinstruction must not transfer control or
  move the micro stack either. At `XFXFLP` (`INTEGERP` and its fellows of an
  extended number) the `CALL-NOT-EQUAL ... XFALSE` after a `POPJ-AFTER-NEXT`
  did both: muir-sim's checker, with its prefetch, counted 20 moves of the
  micro stack and 20 wrong handlers in its bignum workload, though the
  answer was right (`XFALSE` returned to the handler). muir-sim's scan of
  every return whose next microinstruction runs, extended to a JUMP or
  DISPATCH there, a second `POPJ`, a push or pop of the micro stack and a
  write of the OA registers, and to the returns of a `DISPATCH` with the
  `POPJ` bit, lists 56 such returns on the microcode before, each a call.
  10 of them can pop the main loop's return, by a reading of the control
  flow from every handler and misc entry that holds every return the
  profile below saw fused; each now makes or tests its call before the
  return:
  - `XFXFLP` tests the header type with a conditional `POPJ` and then runs
    `XFALSE`'s two microinstructions (`ucadr/uc-fctns.lisp:1134-1146`):
    one microcycle more for a bignum, one fewer for anything else;
  - `XPCAL1` (`%P-CONTENTS-AS-LOCATIVE`, `ucadr/uc-fctns.lisp:1691-1701`),
    `GAHD1` (an array's header, `ucadr/uc-array.lisp:810-831`) and
    `SFLPCK1` (packing a small flonum, `ucadr/uc-arith.lisp:766-780`)
    return by a conditional `POPJ` with the write in its XCT-NEXT and jump
    for the rest, in the same microcycles; `GAHD1` falls into `GAHD3` for
    a long array, one microcycle fewer, and `GAHD-RANK-0` moves after it;
  - `XAPDLR` (`%ASSURE-PDL-ROOM`, `ucadr/uc-call-return.lisp:1747-1760`)
    tests the frame size before a conditional `POPJ`, one microcycle more;
  - `BIND-LEXICAL-ENVIRONMENT-1` and `MKWRIT1`
    (`ucadr/uc-call-return.lisp:460-467`, `:1107-1114`), `XAAI` and
    `XAAIA3` (`ucadr/uc-storage-allocation.lisp:904-916`, `:968-980`) and
    `MAKE-RATIONAL` (`ucadr/uc-arith.lisp:1332-1348`) make the write, then
    `CHECK-PAGE-WRITE`, then a `POPJ`: two microcycles more.

  The answers are the same, but where the call trapped: the traps of
  `SFLPCK1` and `XAPDLR` now find the return not yet made, as every other
  trap does, so a small-flonum exponent overflow names the instruction that
  overflowed (`*`) rather than the next one (`POP`), and proceeding from it
  with a new value works where it stopped the machine (`si:%halt`) before.
  The other 46 are in routines reached only by a call (the page-fault
  handlers, the transporter, consing, the array decoders, bignums, the
  disk, Chaosnet, `BITBLT`), whose returns go back into microcode. I memory
  grows by 10 words; named A, M and D memory stays where it was, and no band
  is rebuilt; `UCADR TBL` changes, since error-table entries move.
  - Tested on muir-sim 24583a1 (a `git archive` copy), with the band and
    PROM of ref/band-2000-h8a-s6 and this microcode over its MCR1. The
    profile of 12 workloads on rtl with the prefetch (`MUIR_PREFETCH=a-line`,
    the microcode's own fill, sync K=4, 4K cache, the Arty's memory timing,
    the RTC counted from a fixed second, `cons` after an untimed first
    `cons`): the checker counts no problem in any workload, where the
    microcode before had 40 in bignum, over 17,756,061 fused returns. The
    extended scan lists 46 returns, none of them able to pop the main
    loop's return; the ten sites' own cost, counted at their
    microinstructions, is 82,417 microcycles fewer over the 12 workloads
    (92,537 long arrays one fewer each, 9,873 more at the others), and the
    workloads took 394,590,000 microcycles against 394,437,000 before, a
    difference within the run-to-run spread of the macroinstructions the
    workloads execute. 33 forms (`INTEGERP`, `FLOATP`, `RATIONALP` and
    `COMPLEXP` of bignums, flonums, ratios and complex numbers, compiled and
    not, locatives, short, long and rank 0 to 2 arrays, small flonums,
    `%ASSURE-PDL-ROOM`, closures, multiple values, allocation, ratios,
    bignums) answer on micro and rtl as on the microcode before, but for
    the overflow's message above; and proceeding from a small-flonum
    overflow with a new value answers `(A 2.0s0 B)` where the microcode
    before stopped the machine, on both engines.

## Time zones

- **The site's `:TIMEZONE` takes a tzdata zone name** (the user,
  2026-09-25), such as `"Europe/Berlin"` (written `"Europe//Berlin"` in a
  site file, whose readtable escapes with a slash), and the default site
  now names that zone. The name is looked up in `SYS: IO1; TZDATA`, a
  table of every zone and link of tzdata 2026c (598 names) with the POSIX
  TZ string its compiled file ends with, today's rule; `sys/io1/gen-tzdata.py`
  makes it from the host's tzdata. The string gives the standard offset and
  the rule for daylight savings time: `PARSE-TZ-STRING` reads the POSIX
  format (IEEE Std 1003.1, `TZ`: `std offset [dst [offset] [,rule]]`, names
  of three letters or more or `<...>`, `Mm.w.d`, `Jn` and `n` dates, times
  from -167 to 167 hours as RFC 8536 allows), and a string with daylight
  savings time but no rule takes glibc's default, `M3.2.0,M11.1.0`.
  `*TIMEZONE*` stays a number, the hours west of standard time, which every
  reader of it expects; an offset that is not whole hours makes it a ratio
  (-11\2 for Asia/Kolkata), which decoding and encoding take. The parsed
  string is in `TIME:*TIMEZONE-RULE*` and the name in
  `TIME:*TIMEZONE-NAME*`; `SET-TIMEZONE-FROM-SITE` sets all three at every
  site initialization. A name tzdata does not know, a malformed string, and
  a zone whose daylight savings time is not one hour from standard
  (Antarctica/Troll, two hours; Australia/Lord_Howe and its link
  Australia/LHI, half an hour; the time code shifts by one hour) are errors
  that say which. Daylight savings time an hour behind standard, Europe/Dublin's
  winter, is turned round into an hour ahead.
- **A number in `:TIMEZONE` is a fixed offset with no daylight savings time.**
  This changes every site that gives a number: before, whatever the number,
  the machine applied the United States' rule of 1967 to 1986, from the
  last Sunday of April to the last Sunday of October, so the default site's
  `-1` was in summer time then, not from the last Sunday of March. `(:TIMEZONE 5)` is now EST all
  year; `"America/New_York"` gives today's United States rule.
- **`*DAYLIGHT-SAVINGS-TIME-P-FUNCTION*`** now defaults to
  `TIMEZONE-RULE-DAYLIGHT-SAVINGS-TIME-P`, which follows `*TIMEZONE-RULE*`
  and is never true without one. A function put there by hand stays when
  the site is initialized again, and it is now called with the year in full
  and the seconds and minutes from `ENCODE-UNIVERSAL-TIME` too, which gave
  it the hour alone and the year less 1900. `DAYLIGHT-SAVINGS-TIME-IN-NORTH-AMERICA-P`,
  `LAST-SUNDAY-IN-APRIL` (which took 2000 for a common year) and
  `LAST-SUNDAY-IN-OCTOBER` are gone; nothing else used them and none was
  exported. `WEEKDAY-IN-MONTH` finds the n-th or last weekday of a month on
  `GREGORIAN-DAY-COUNT`, the day count `ENCODE-UNIVERSAL-TIME` now shares
  (`io1/time.lisp`).
- Tested on muir e11026a, micro unpaced, on the dev11 band with Q9 part 1
  and the calendar fix, with the change loaded: 31,774 times from 2026 to
  2106 decoded as Python's zoneinfo (tzdata 2026c) does for Europe/Berlin,
  Europe/London, America/New_York, Australia/Sydney, Asia/Tokyo,
  Pacific/Auckland and ten more zones, as glibc does for six strings with
  `J`, `n`, negative and over-24-hour times and the default rule, and as a
  fixed offset for `5`: the second before and at each change, an hour and
  two hours either side, and the middle of each season; those two hours or
  more from a change also encoded back. Every table entry but the three
  refused parses, to the offset the host's reading gives, and 35 malformed
  strings each give their error. The who-line and `PRINT-CURRENT-TIME`
  showed Berlin's summer time, as the host's `TZ=Europe/Berlin date` did,
  and a file's date over OZ came back 7200 s behind the clock, as before.
  Saved into the band, a cold boot comes up with the zone set from the
  site. Around every change from 2026 to 2106, `ENCODE-UNIVERSAL-TIME` of
  the decoded time gives the time back, and so does
  `PARSE-UNIVERSAL-TIME` of it printed (DD-MMM-YYYY), except in the hour
  that happens twice as summer time ends, where both take standard time
  (162 times a zone); given the decoded zone, encoding gives every time
  back. At noon GMT on 1095 days from 1900 to 2106 (29 February and the
  days around 1 March 1900, 2000 and 2100 among them), decoding gives the
  day and parsing the printed day gives the time back.
- **A band from before this change cannot take a site that names a zone.**
  Its site initialization puts the string in `*TIMEZONE*`, and then every
  decoding fails ("The first argument to *, "Europe/Berlin", was of the
  wrong type"), measured on the dev11 band. A build on such a band loads
  the new `SYS: IO1; TZDATA` and `TIME` before the new site file, and
  `TZDATA` loads before `TIME` in the `TIME` system (`sys/sysdcl.lisp`).
- **FILE dates on the wire are UTC** (Mete, 2026-09-27), as on the CADR's
  System 1002; the machine still shows dates in its own local time. QUUX
  takes its system through the file device, whose dates are binary Unix
  seconds, so this is only for FILE over Chaosnet (`OZ:` and other hosts).
  `PARSE-DIRECTORY-DATE-PROPERTY` encodes its `MM/DD/YY HH:MM:SS` at zone 0
  (`io/file/open.lisp:1465`) and `PRINT-DIRECTORY-DATE-PROPERTY` decodes at
  zone 0 (`io/file/open.lisp:1480`), which also takes no daylight savings
  time. Every FILE date the client reads or sends goes through these two:
  the OPEN and CLOSE replies (`network/chaos/qfile.lisp:500`), directory
  listings and file properties (`READ-DIRECTORY-STREAM-ENTRY`,
  `io/file/open.lisp:1372`), CHANGE-PROPERTIES
  (`network/chaos/qfile.lisp:680-691`) and dates the cold load keeps as text
  (`io/file/pathst.lisp:473`). A date in any other form still goes to
  `TIME:PARSE-UNIVERSAL-TIME` at local time (`io/file/open.lisp:1468`).
- **The "date or never" properties go on the wire in UTC too**
  (`:REFERENCE-DATE` and the rest): their printer in
  `*KNOWN-DIRECTORY-PROPERTIES*` is now `PRINT-DIRECTORY-DATE-OR-NEVER-PROPERTY`
  (`io/file/open.lisp:1340`, `:1492`), "never" or the date as
  `PRINT-DIRECTORY-DATE-PROPERTY` prints it. That printer is used only on
  the wire, by CHANGE-PROPERTIES (`network/chaos/qfile.lisp:686`) and the
  band's own FILE server; `TV:PRINT-UNIVERSAL-TIME-OR-NEVER`, which printed
  local time, stays the choose-variable-values printer for showing such a
  date (`window/choice.lisp:1066`), so the local display is unchanged. The
  table is a `DEFVAR`: a band built from a new cold load has the new entry,
  but loading the file into a running band keeps the old one.
- **The fast parser also reads a four-digit year**, `MM/DD/YYYY HH:MM:SS` and
  `MM/DD/YYYY` (`io/file/open.lisp:1426`). `PRINT-DIRECTORY-DATE-PROPERTY`
  has always printed the year in full (MIT's `DECODE-UNIVERSAL-TIME` returns
  it so), which went to the full parser at local time: with the printer at
  UTC, a date this system printed read back moved by the site's offset. The
  band's own FILE server reads CHANGE-PROPERTIES dates with it
  (`file/server.lisp:990`).
- **The band's own FILE server sends UTC.** Its OPEN and CLOSE replies print
  the date with `CV-WIRE-TIME` (`file/server.lisp:50`): zone 0, and
  `MM/DD/YY HH:MM:SS` with a two-digit month, the form the fast parser takes;
  `:MM/DD/YY` printed the month in one digit before October, which a client
  read with the full parser at local time (`file/server.lisp:333`, `:340`,
  `:472`, `:787`, `:793`). The protocol-0 CLOSE reply named the date mode
  `:MM/MM/YY`, which has no date format and signals an error (MIT's). Its
  directory listings print creation and modification dates with
  `PRINT-DIRECTORY-DATE-PROPERTY`, so they are UTC too, and the "date or
  never" properties as the replies print a date, or "never"
  (`file/server.lisp:944-946`): with `TV:PRINT-UNIVERSAL-TIME-OR-NEVER` a date
  from January to September went to the client's full parser at local time
  and one from October to December to its fast parser as UTC, moved by the
  site's offset (measured at Europe/Berlin: 24 October 2026 23:30 GMT read
  back 7200 s late). `CV-TIME` stays local, for the server's lossage log.
- **A FILE server that sends its local time** (ozd's `--file-dates mit`, the
  own servers of Systems 100 to 1001) has its dates read as UTC, off by its
  zone's offset; ozd's default, `--file-dates utc`, agrees with this system.
- Checked on the System 2000 development band (microcode 2000, muir
  1a89ed0's `quux`) with `IO; FILE; OPEN` compiled and loaded, at
  Europe/Berlin and at a fixed `-1`: `"07/15/26 12:00:00"` parses to
  3993105600 (12:00 GMT) where the band gave 3993098400 (Berlin) and
  3993102000 (`-1`); 3993105600 prints `"07/15/2026 12:00:00"` where it
  printed 14:00 and 13:00; January the same; a printed date parses back to
  itself, the four-digit forms parse (they gave local time before), and
  `00/00/0000` is no date; `TIME:PRINT-UNIVERSAL-TIME` still shows
  `7/15/26 14:00:00` at Berlin and 13:00 at `-1`. With `FILE; SERVER`
  compiled and loaded too, `CV-WIRE-TIME` prints `07/15/26 12:00:00` at
  Berlin, `-1` and `5` alike, and five dates (summer, winter, both sides of
  the October change, 2001) read back through the fast parser as themselves;
  the old reply's form gave `7/15/26 14:00:00`.
  The "date or never" properties, at Berlin and `-1`: the server's listing
  line for 15 July and for 24 October 2026 (23:30 GMT, 01:30 in Berlin)
  reads back through `READ-DIRECTORY-STREAM-ENTRY` as the same second, and
  so does CHANGE-PROPERTIES's text through the server's parser, and "never"
  as NIL; before, 24 October came back 7200 s late at Berlin and 3600 s at
  `-1`, and each half put back fails those cases. The server itself was
  not run: the band has neither it nor the local file system it serves.
- **`tools/lispm-check` passes ozd's date flags on**: `--ozd-file-dates
  mit|utc` and `--ozd-timezone N` become ozd's `--file-dates` and
  `--timezone` (`docs/lispm-check.md`), so that a band of Systems 100 to 1001,
  which reads FILE dates at its site's zone, is served them so. Measured on
  the 1001 band: a file's date is exact with `mit` and `-1`, and 3600 s early
  in January and 7200 s early in July with ozd's default, `utc`.
- **The release tools** (`1331881`, `f5a60d5`, `2ab511f`), tracked by
  `.gitignore:39-42`. `tools/release-scan` reads every byte a release
  publishes by what a file holds (a gzip and its header, a tar's members and
  headers, a VHD through its block table, anything else raw) and fails on a
  local path, a private address, an e-mail address, this machine's or
  user's name, or a tar member not owned by root, uid and gid 0 and both
  names root (`tools/release-scan:300-308`), unless one of its four rules
  passes it (`tools/release-scan:42-54`); the names and the owner pass by no
  rule. Its baseline, `tools/release-scan.baseline`, holds the digests of
  what `release-1001`'s two assets already hold, the sources tarball as
  replaced with its members owned by root. `tools/release-sums` writes and
  checks `SHA256SUMS`, with a line for the disk or pack uncompressed, and
  with `--api` compares GitHub's digests of the uploaded assets.
  `tools/release-test` holds both to planted faults; its home directory is
  planted in `sys/io/file/open.lisp`, which both lines have
  (`tools/release-test:209`), and it refuses a fault planted into a file the
  tree does not have (`tools/release-test:108-112`).
- **`docs/building.md` says how a release is published**
  (`docs/building.md:676`): the assets of each kind of release, every
  tarball member owned by root, one gzip route (Python's `gzip`, no name, no
  date; `docs/building.md:712-720`), then by the SHA of one commit: the sums,
  the scan and the owners, the commit on its own line and not the other's,
  the annotated tag, a draft, the draft downloaded back and checked (sums
  against GitHub's digests, scan, owners, the VHD's `conectix` or the pack's
  `LABL`), and publishing with Latest set and read back
  (`docs/building.md:827-841`).
- **`docs/building.md` says how QUUX's release disk is written**
  (`docs/building.md:315-350`): a new GPT disk in the build disk's layout
  with only the microcode in MCR1 and the band in LOD1, both with bit 48 and
  named "MCR1 UCADR 2000" and "LOD1 System 2000", the rest zero; the
  `sgdisk`, `dd` and `qemu-img` commands, the check that the VHD converts
  back to the raw disk, and the raw disk's SHA-256 as the build's identity.
  release-2000's disk was written by exactly these commands.
- **The README and these notes speak of the release as made**: the
  README's System 2000 section, its releases paragraph (a QUUX release
  carries a VHD disk, the sources and the boot PROM, and `SHA256SUMS`),
  muir-sim as `quux` rather than `--machine quux`, and the heading "How it
  was written"; here, the opening and the microcode bullet under QUUX.

## Faults fixed

- **`HOST` gives a `SYS:` file's physical truename.** `MAKE-SYSTEM` asks
  for the properties of `SYS:` pathnames, which the logical host passes on
  to `HOST` untranslated, and the `:TRUENAME` it got back was the logical
  pathname itself: never `EQUAL` to a loaded file's id, whose truename is
  `HOST`'s. With `SYS:` on `HOST`, `MAKE-SYSTEM` therefore loaded every file
  of a system again, and QLD reloaded the cold load's files and stopped at
  the first redefinition query (`*IOLST`, defined by `SYS: SYS; QFCTNS` and
  again by `SYS: IO; QIO`). A logical pathname's truename is now its
  translation (`io/file/hostfs.lisp:138-151`); red and green in the
  builder: `(eq truename (send p :translated-pathname))` was NIL, now T.
- **The cold load records each file's date as a number.** The cold-load
  builder printed the date into the file's loaded id
  (`cold/coldld.lisp:115-131`, the old lines commented out), and it stayed a
  string until the time parser came in and parsed it
  (`FS:CANONICALIZE-COLD-LOADED-TIMES`), after QLD's `MAKE-SYSTEM` had
  compared it with `HOST`'s date, a number: a string never equals it. A date
  printed and parsed later also moves by any difference between the zones
  of the two. It is now the universal time itself; in the cold load of the
  M4 build the ids of `SYS: IO; QIO`, `SYS2; CHARACTER` and `SYS; LTOP` equal
  `HOST`'s truename and date, and QLD no longer loads those files again and
  runs to its end with no query.
- **Dates in 1900, 2000 and from 2100 on are right.**
  `DECODE-UNIVERSAL-TIME-WITHOUT-DST` took every fourth year for a leap year,
  so it gave 29 February for 1 March 1900 and 2100, a day early for the rest
  of 1900 and from 2100 on, and 6 February 2106 for the real-time clock's
  last second, 2^32-1 (the 7th); it now uses Howard Hinnant's
  `civil_from_days`. `ENCODE-UNIVERSAL-TIME` counted every fourth year too
  (a day late from 2101), counted one leap day before 1900 (a day early all
  through 1900), and asked `LEAP-YEAR-P` about the year less 1900, which
  said 2000 was none (a day early from 1 March 2000); it now counts by the
  Gregorian rule. Both were MIT's (`io1/time.lisp`). Checked against the
  host's calendar at 1384 times from 1900 to 2^32-1 of the clock, every
  year's 1 January, 28 February, 29 February, 1 March and 31 December among
  them: decoding was wrong at 43 and encoding at 45; now at none.
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

- **QLD no longer stops at its second load of `CHSNCP QFASL`** with
  "(:INTERNAL GET-NEXT-PKT 0) is an invalid function". That load replaces
  the network code over the network, and fasload installs a function
  before the `#'(LAMBDA ...)` inside it, so until the lambda arrives the
  function holds the list `(:INTERNAL GET-NEXT-PKT 0)`. The loader, waiting
  for the next packet of that very file in the gap, called it; with that
  one named, the scheduler stopped the same way on the receiver's,
  `(:INTERNAL CHAOS::RECEIVE-ANY-FUNCTION 0)`. Every wait in the file now
  uses a named predicate defined above its user: those of `GET-NEXT-PKT`,
  `SEND-PKT`, `ALLOCATE-INT-PKT`, `RECEIVE-ANY-FUNCTION` and `BACKGROUND`
  (`network/chaos/chsncp.lisp`). MIT's; it shows only when a wait falls in
  the gap, which a file server that sends a packet for each
  acknowledgement makes likely.

- **Encoding and parsing a date agree with decoding on summer time.**
  `ENCODE-UNIVERSAL-TIME`, and `PARSE-UNIVERSAL-TIME` through it, asked the
  rule about the year less 1900, and `LAST-SUNDAY-IN-APRIL` took 1900 off
  again, so from 2000 on they put the change on other days than decoding
  did: at noon GMT on 27 April 2026 the old band decoded 14:00 and encoded
  and parsed that back an hour late, and on 26 October an hour early. The
  rule now gets the year in full (`io1/time.lisp`); MIT's.
- **The directory date parser checks its fields.** `FS:PARSE-DIRECTORY-DATE-PROPERTY`
  took any two digits, so a month of 13 stopped it with "The subscript 13
  ... was out of range", and a day of 99 or a time of 25:61 made another
  time silently. A date out of range is now no date, as 00/00/00 already
  was (`io/file/open.lisp`); MIT's. Only dates over OZ go through it.

- **A physical pathname matches its own pattern again, so QLD no longer
  loads MINI's files twice.** `:PATHNAME-MATCH` and `:PATHNAME-MATCH-SPECS`
  took the pattern's components raw and the sample's through the accessors,
  which convert solid case, and compared them with case: a `HOST:` (or any
  Unix or LMFS) pattern such as `HOST: /sys/*/*` matched no pathname, not
  even itself. So nothing on `HOST` back-translated into `SYS:`: every file
  MINI loaded kept its loaded id and its functions' source file on a `HOST:`
  generic pathname, QLD's `MAKE-SYSTEM` found no id on the `SYS:` one and
  loaded all 36 of MINI's `SYS:` QFASLs a second time. Both methods now
  take the pattern's device, directory, name and type through the accessors
  too, and compare in interchange case (`io/file/pathnm.lisp:1948-1991`, the
  old lines commented out); a logical pattern matches as before, and case
  stays significant. `FILE-DEVICE-WILD-MATCH`'s comment gives its reason
  anew (`io/file/hostfs.lisp:353-360`). Red and green with `lispm-check` on
  the System 2000 development band: a `HOST:` pathname matches itself, the
  generic pathname of `HOST: /sys/sys2/flavor.qfasl`,
  `/sys/io/file/pathst.qfasl` and `/site/site.qfasl` is the `SYS:` one,
  back-translation gives `SYS: SYS2; FLAVOR QFASL`, `SYS: IO; FILE; PATHST
  QFASL` and `SYS: SITE; SITE QFASL`, and dired's wildcard match of a `HOST:`
  directory holds: all NIL or an error before, T after; translation and case
  unchanged.
- **MINI records a file's date as the device's number.** MINI printed each
  file's date as text (`MINI-DATE-STRING`), and the text stayed text until
  TIMPAR came in, which `MAKE-SYSTEM "System"` itself loads, after it has
  compared every file's id; text never equals `HOST`'s number, so with the
  fault above fixed QLD would still load MINI's files again. MINI now keeps
  the open's mtime as it came, its two halves `(high . low)`
  (`cold/mini.lisp:245-262`; `MINI-DATE-STRING` and `MINI-TWO-DIGITS`
  commented out at `:138-175`), and `CANONICALIZE-COLD-LOAD-PATHNAMES`, which
  QLD runs before `MAKE-SYSTEM`, makes it a universal time with
  `FILE-DEVICE-UNIVERSAL-TIME`, as `HOST`'s `:CREATION-DATE` does
  (`MINI-DATE-UNIVERSAL-TIME`, `io/file/pathst.lisp:331-339`, `:405-409`).
  MINI stays free of bignums and prints no date. In a fresh cold load and
  QLD with both changes: no `HOST:` generic pathname carries an id (the
  development band had 40), every id is a number equal to the served
  date (39 differed), 35 of MINI's 36 `SYS:` QFASLs keep MINI's id alone,
  `(make-system 'system :print-only)` lists nothing, and the quux process
  opened 1 of MINI's files again after MINI, where the ids show 36 before;
  the next bullet fixes that one.
- **`SYS: SITE; HSTTBL QFASL` is loaded once.** `CANONICALIZE-COLD-LOAD-PATHNAMES`
  gave MINI's id the name MINI opened merged into `SYS:`'s physical
  pathname as its truename. For a file one directory deep,
  `/site/hsttbl.qfasl`, that pathname's directory is the string `"site"`,
  while the truename `HOST` gives `MAKE-SYSTEM` is the translation of
  `SYS: SITE; HSTTBL QFASL` (`FILE-DEVICE-TRUENAME`,
  `io/file/hostfs.lisp:138-151`), whose directory is the list `("site")`:
  two pathnames, never `EQUAL`, so QLD loaded the host table a second time.
  Files two or more deep give the same pathname both ways. The truename is
  now the translation of the name's `SYS:` back-translation, and the merged
  pathname only for a name with none (`io/file/pathst.lisp:387-404`, the old
  lines commented out). Red and green on the new band, with MINI's id for
  `HSTTBL` put back as MINI leaves it and canonicalized again: its truename
  `EQ` to `HOST`'s and `FILE-NEWER-THAN-INSTALLED-P` were NIL and T, now T
  and NIL; `FLAVOR` and `PATHST` give T and NIL both times. In a fresh cold
  load and QLD: the quux process opened none of MINI's files after MINI
  (strace), all 36 of MINI's `SYS:` QFASLs keep MINI's id alone, no `HOST:`
  generic carries an id, every id equals its served date, and
  `:print-only` lists nothing. The CADR's line never had it: QFILE's
  truename is parsed from the server's name, as MINI's is.
- **The band's own FILE server prints the year in four digits.**
  `CV-WIRE-TIME` printed `MM/DD/YY HH:MM:SS`, and a client's parser takes a
  two-digit year within fifty years of the present, so a file of 1970 read
  as 2070 and one of 2099 as 1999. It now prints `MM/DD/YYYY HH:MM:SS`
  (`file/server.lisp:42-60`, the old lines commented out), which the fast
  parser reads as UTC, as ozd's `--file-dates utc` prints its FILE and MINI
  dates from ozd `52eb6b0`. `PRINT-DIRECTORY-DATE-PROPERTY` already printed
  four digits, and the parser reads both forms. Red and green on the System
  2000 development band with `FILE; SERVER` compiled and loaded: 1970-01-01
  and 2099-12-31 printed `01/01/70` and `12/31/99` and read back
  3155760000 s off, and now print `01/01/1970 00:00:00` and
  `12/31/2099 23:59:59` and read back exactly; 2026 and the 17-character
  form are unchanged. This line's cold load reads dates from the file
  device as numbers, so nothing else here prints a date for the wire.

- **A band run on a CADR no longer says System 1001 is the CADR's last.**
  `CHECK-MACHINE-IS-QUUX` printed "This band runs only on QUUX: System 1001
  is the last for the CADR." before it halts, wrong since the CADR's line
  went on with 1002; it prints "This band runs only on QUUX: the CADR's
  systems are the 1000s." (`sys/ltop.lisp:155-158`, the old line commented
  out).

## Known faults found, not yet fixed

- **A date printed MM/DD parses as DD/MM outside the United States.** The
  default print mode is `:MM//DD//YY`, but `SET-MONTH-AND-DATE`
  (`io1/timpar.lisp`) reads two numbers of 12 or less as month and day only
  when `*TIMEZONE*` is 4 to 10, and as day and month otherwise. At noon GMT
  on 1095 days from 1900 to 2106, the MM/DD/YYYY form parsed back wrong on
  212, every one whose day and month are both 12 or less and differ (1 to
  4 March, less 3 March), in Europe/Berlin
  and Australia/Sydney, and on none in America/New_York or at zone 5. MIT's;
  the default site had it with -1 already.

- **`(%div 0 0)` returns 0** rather than signalling division by zero: `QDIV`
  returns 0 for a zero dividend before it looks at the divisor. MIT's.
- **The inspector traps on a symbol that has a function but no value.**
  `(inspect 'car)` stops with "The variable CAR is unbound" in
  `(:METHOD TV:BASIC-INSPECT :OBJECT-SYMBOL)`: its "Function is" line
  takes `SYMBOL-VALUE` where it means the function
  (`window/inspct.lisp:383`). Found on System 2000 while checking its
  release; the line is as System 100 has it.
- **`LISTF` over TELNET traps after the listing.** `(listf "SYS: SITE;")`
  typed at the TELNET listener prints the directory, then stops with
  "Some argument to ARRAY-ACTIVE-LENGTH, NIL, was of the wrong type" in
  `:STRING-OUT` of the TELNET stream, under `STREAM-COPY-UNTIL-EOF`. The
  same on microcode 2000 before and after contract H8a; not tried at the
  console, and the cause is not sought yet.
- **Video controller sizes above 1920 by 1080 are not supported** (the user,
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

- **The site defines seven Lisp Machines, LISPM-1 to LISPM-7** (the user,
  2026-09-25), at Chaos 177201 to 177207 (`site/hosts.text`), each with a
  location (`site/lmlocs.lisp`), "Lisp Machine One" to "Seven", so up to
  seven machines run at the default site with nothing to configure. A machine
  at an address the site did not know called itself UNKNOWN-CHAOS-177203 in
  the herald, "Unknown" by location, with ED-FILE as its associated machine;
  at 177203 it is now LISPM-3, "Lisp Machine Three", with OZ.

## Asking the machine

- **`SI:MACHINE-TYPE-CODE`** returns 1 on a CADR and 4 on QUUX, the type code
  the microcode set at boot from `MACHINE-ID`; `MACHINE-TYPE` gives its name.
- **`SI:PRINT-FEATURE-PAGE`** prints QUUX's feature page, read with
  `%XBUS-READ` at 17777400 (17377000 below revision 11): the machine ID with its signature, revision
  and type, and the sizes of the level-1 entry, the level-2 map, the PDL
  buffer, control store, A memory and dispatch memory. On a CADR, which has no
  such page and times out if it is read, it says so instead.

## Taken from lmz-sys

What lmz-sys, bishop's line, fixed after the two lines
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
  PROM's and microcode 2000's QUUX handling added.

Not taken: that line's reader and naming changes for Common Lisp (`#T`, the
comparison names in ASCII), bishop's stack-frame operations, and its
correction of the run-light comment in `sys/ltop.lisp`, which describes
code this tree still has (`SET-UP-SCAN-LINE-TABLE` in `window/shwarm.lisp`).
