# How a machine boots

This is the path from power-on to the first macroinstruction: the boot PROM
loads microcode, the microcode loads a world, and the microcode enters one Lisp
function. It follows the tree's own code, and each claim cites a file and line.

It was carried over from the System 2000 line (lmz-sys `fecd0a5`) and every
citation re-checked against this tree. Line numbers in `promh.text`,
`uc-disk.lisp` and `uc-cold-disk.lisp` are those of commit `0ec714d`, before
QUUX's disk became block-disk; the labels named with them are still there,
except those block-disk removed, as noted below. Nothing here is about compiling or
building; `docs/building.md` covers that.

## The three stages

| Stage | Who runs | What it produces |
|---|---|---|
| 1 | the boot PROM, `ucadr/promh.text` | I, D and A/M memory loaded from the MCR partition |
| 2 | the loaded microcode, `ucadr/uc-cadr.lisp` and `uc-cold-disk.lisp` | a valid virtual memory, from a band |
| 3 | the same microcode, `uc-cold-disk.lisp:741-793` | a stack frame entering `LISP-TOP-LEVEL` |

## Stage 1: the PROM loads microcode

The PROM is `sys/ucadr/promh.text`, assembled to `sys/ubin/promh.mcr`. It runs
from I-memory location 0 and knows nothing about bands, Lisp or virtual memory.
This tree's PROM is version 1000, MIT's version 9 changed so that one PROM
serves the CADR and QUUX (commit `d85b54a`).

It first tests the hardware a bit at a time --- every bit of a word of zeros,
the ALU's carries, the byte hardware, M-memory, A-memory and the PDL buffer
(`:168-259`) --- because a fault found here is better than a world that boots
wrong. Then it clears M and A memory, the PDL buffer, the SPC stack, both
levels of the map, I-memory and D-memory, so their parity is good
(`:261-354`), and sets up four map entries, the only ones it uses
(`:383-387`):

| virtual page | maps to |
|---|---|
| 0 | the first page of main memory |
| 1 | the disk control registers |
| 2 | the debug (spy) interface at Unibus 766000 |
| 3 | the second page of main memory, the system communication area |

Two of the clears are written for QUUX, whose PDL index may be 12 or 14 bits
instead of 10 and whose level-2 map has 64 blocks instead of 32.
`CLEAR-PDL-BUFFER` starts from a pointer of all ones, so the first push lands
at 0 at any width and it clears words 0-1777 (`:299-309`). `CLEAR-LEVEL-2-MAP`
clears 64 blocks, writing a level-1 entry's bits 4:0 from VMA<31:27> and its
bit 5 from VMA<24>, which a CADR ignores; on a CADR blocks 40-77 are 0-37
again (`:323-334`).

### Why it saves physical page 0

The PROM has no buffer of its own. It reads the disk label into physical page
0, and `GET-NEXT-PAGE` reads every block of the microcode partition into
physical page 0 as well (`:636-644`). So merely running destroys one page of
main memory --- and on a warm boot that page belongs to a live Lisp world.

Before touching it, the PROM therefore writes physical page 0 out to disk block
1, which the label format reserves for this purpose (`SAVE-A-PAGE`, `:427-441`).
MIT's PROM verified the write with a read-compare and retried on failure. On
QUUX's disk, block-disk, there is no read-compare, so the PROM writes the
block once and halts at `ERROR-DISK-ERROR` if the write fails. At `DONE-LOADING` it reads the block
back into page 0 (`:587-591`). The page is borrowed and returned.

### Finding the microcode

The label is block 0. Word 0 must be the four characters `LABL` and word 1 must
be 1, or the PROM halts at `ERROR-BAD-LABEL` (`DECODE-LABEL`, `:460-466`).
Words 2 to 5 give the disk geometry, which QUUX's PROM skips: block-disk is
addressed by block number, where MIT's PROM divided each block number into a
cylinder, head and sector. **Word 6 names the current microcode
partition** (`:467-481`). Word 200 is the number of partitions, word 201 the
size of a partition descriptor, and word 202 begins the table (`:482-489`); the
PROM walks it for a descriptor whose first word is that name (`SEARCH-LABEL`,
`:496-503`), and takes the start block and length from the two words after it
(`FOUND-PARTITION`, `:505-513`).

Which microcode a machine runs is therefore a property of the pack, written in
one word of its label, not of the PROM.

### What a microcode partition contains

The partition is a sequence of sections. Each begins with three words: the
section type, the initial address and the number of locations (`:515-527`). The
PROM dispatches on the type (`:528-532`):

| type | meaning | how it is loaded |
|---|---|---|
| 1 | I-memory | two words per microinstruction, written with `WRITE-I-MEM` (`:534-547`) |
| 2 | D-memory, the dispatch RAM | one word each, through `WRITE-DISPATCH-RAM` (`:549-559`) |
| 3 | main memory | a fourth header word gives the physical address, and whole blocks are read straight from the partition (`:561-574`) |
| 4 | A and M memory | words are pushed onto the PDL buffer (`:576-585`) |

The other end of this format is `sys/sys/qwmcr.lisp`, which writes it: "An MCR
file looks a lot like a microcode partition" (`:9-12`). It emits I-memory as
type 1, D-memory as type 2, A/M as type 4 (`:45-48`), and the microcode symbol
area as a type 3 main-memory section addressed to that area's origin
(`WRITE-MICRO-CODE-SYMBOL-AREA-PART-1`, `:92-104`). That last section matters
at run time: it is the table the `MISC` macroinstruction dispatches through
(`uc-macrocode.lisp:498-504`, `uc-cold-disk.lisp:722-723`), so the mapping
from a misc opcode to a microcode address arrives with the microcode, in the
same file.

A/M memory goes through the PDL buffer rather than straight into place because
the PROM's own constants and temporaries live in A/M. It cannot write them
until it has finished needing them, so it stacks the new contents and copies
them in as its last act (`FILL-M-LOOP` and `FILL-A-LOOP`, `:596-613`). That is
also why `Q-R`, `MD` and `VMA` are loaded a few instructions earlier, with the
note "Note that Q-R, MD, and VMA are already set up" (`:592-594`, `:618`):
after the fill, no A/M constant of the PROM's exists any more.

`FILL-A-LOOP` stops after 2000 words, when the PDL index's bit 10 sets, as
well as when the index wraps to 0 (`:603-613`). MIT's loop stopped only at the
wrap, which a 10-bit CADR index reaches after 1777. On QUUX's wider index it
ran on, the 10-bit A address wrapped, and zeros overwrote A memory from
location 0.

### The handoff

The PROM ends by writing 44 to Unibus 766012 --- `ERROR-STOP-ENABLE` plus
`PROM-DISABLE` --- and jumping to I-memory location 6 (`JUMP-TO-6`,
`:614-622`). Both programs keep a spin loop there that counts `Q-R` down
(`promh.text:81-84`, `uc-cadr.lisp:64-66`), so the machine is looping at
location 6 when the PROM switches off underneath it and the loaded microcode's
location 6 continues the same loop. It works because the two agree on where
the constant -1 lives: the PROM's `A-ONES` is A-memory location 3
(`promh.text:33-36`), and the microcode's `A-MINUS-ONE` is annotated "MUST BE
3" (`uc-parameters.lisp:528-531`). `FILL-M-LOOP` puts the microcode's -1
there, since writing M memory also writes the A location that shadows it
(`uc-parameters.lisp:521-526`), and it survives only because `FILL-A-LOOP`
stops at 2000: on QUUX a fill that wrapped wrote 0 into location 3, and the
loop at location 6 never ended.

## Stage 2: the microcode loads a world

The landing site is `PROM` at I-memory location 6 in `uc-cadr.lisp:64-81`. It
reads the keyboard to decide what kind of boot this is: if the keyboard is not
ready, or the keycode is 46, Rubout, it cold-boots; otherwise the world in
memory is assumed valid and it jumps straight to `BEG0000`.

A cold boot enters `COLD-BOOT` (`uc-cold-disk.lisp:326`), which is
`%DISK-RESTORE` asked for the current band. It resets the machine, sizes main
memory by writing and reading in 16K steps until a location does not answer
(`:346-356`), and reads the label to find **both the paging partition and the
band's partition** (`COLD-READ-LABEL`, `:824-865`); `A-DISK-OFFSET` becomes the
disk address of virtual location 0, the start of the paging partition
(`:853`).

### The map, and which machine this is

Resetting the machine drops into `INITIAL-MAP` (`:5-31`), on a cold boot at
`DISK-RESTORE-1` and on either kind at `BEG0000` (`:339`, `:709`). Its first
act, in microcode 1000, is to ask which machine it is on. `INITIAL-MAP-A`
reads `MACHINE-ID`, functional source 16 (`sys/cadsym.lisp:338-344`): on QUUX
its bits 31:16 are the signature 0x5155, and a CADR does not drive the source
and reads all ones (`:31-45`).

| machine | `A-PROCESSOR-TYPE-CODE` | `A-LEVEL-1-MAP-INVALID` |
|---|---|---|
| CADR, no signature | 1 | 37 |
| QUUX | its own type from bits 3:0, 4 | 77 from hardware revision 1 (bits 15:4), else 37 |

It then sets every level-1 entry to all ones --- five bits on a CADR, six on
QUUX (`:46-53`) --- and reads block 0's entry back: if it is not the invalid
entry `MACHINE-ID` promised, the level-1 map is narrower than the id says, and
the microcode halts at `MAP-WIDTH-MISMATCH` rather than let blocks alias
(`:54-59`, `:108-111`). It zeroes the invalid block (`:60-65`), maps the wired
pages one to one (`:66-91`), and writes the reverse first-level map, one word
per level-2 block, at locations 640-737 of the system communication page
(`:93-106`); the 64 entries do not fit where the CADR's 32 were, so the
swap-out CCWs move to 440-457 (`uc-parameters.lisp:938-941`). Both variables
are A-memory locations set here at every boot (`uc-parameters.lisp:731-733`,
`:1222-1228`).

### Loading the band

It then reads the band's first three pages into core pages 0 to 2 (`:363-368`)
and consults the system communication area, now at physical 400, for
`%SYS-COM-BAND-FORMAT` (`:369-373`):

| format | meaning |
|---|---|
| 0 | expanded; in practice a cold-load band |
| 1000 | compressed, copied region by region |
| 1001 | incremental |

The important part is what "loading a band" means. The band is **copied into
the paging partition**, not into memory: `DISK-COPY-SECTION` reads from `M-I`
in the band and writes to `M-Q` in the paging area (`:978-987`), and for a
compressed band each region goes to the block matching its virtual address,
`M-Q` being the region origin plus `A-DISK-OFFSET` (`:430-431`). Only then does
`COLD-SWAP-IN` read the wired pages into core, again from `A-DISK-OFFSET`
(`:599-609`). Everything else arrives later as page faults. The band does not
get loaded; it becomes the backing store.

## Stage 3: entering Lisp

Both kinds of boot converge on `BEG0000` (`:676`), which reinitializes the
flags, disables scheduling and scavenging, resets the machine and rebuilds the
map (`:676-709`).

`BEGCM4` (`:741-750`) then copies virtual locations 1000 onward ---
`SCRATCH-PAD-INIT-AREA`, which is part of the band --- into A-memory starting at
`A-SCRATCH-PAD-BEG`. The list and the A-memory are in the same order
(`cold/qdefs.lisp:320-326`, `uc-parameters.lisp:596-600`):

| slot | A-memory |
|---|---|
| `INITIAL-TOP-LEVEL-FUNCTION` | `A-INITIAL-FEF` |
| `ERROR-HANDLER-STACK-GROUP` | `A-QTRSTKG` |
| `CURRENT-STACK-GROUP` | `A-QCSTKG` |
| `INITIAL-STACK-GROUP` | `A-QISTKG` |

The cold loader writes slot 0 as a locative to the function cell of
`LISP-TOP-LEVEL` (`cold/coldut.lisp:954-956`), and the microcode reads through
it, marked `;INDIRECT` (`:751-759`), so a world runs whatever that cell holds
now rather than whatever it held when the band was written.

The microcode then builds one stack frame by hand: it pushes the FEF, refuses
anything that is not a `DTP-FEF-POINTER`, sets `M-AP`, and takes the initial PC
out of the FEF header (`:770-785`). Finally (`:788-792`):

```
	((MICRO-STACK-DATA-PUSH) A-MAIN-DISPATCH)	;PUSH MAGIC RETURN
	(JUMP-XCT-NEXT QLENX)			;CALL INITIAL FUNCTION, NEVER RETURNS
```

`QLENX` (`uc-call-return.lisp:2194-2197`) sets `LOCATION-COUNTER` to the FEF's
address doubled plus that PC and then `POPJ`s --- to the address just pushed,
`A-MAIN-DISPATCH`, which is `QMLP`, the main instruction loop
(`uc-parameters.lisp:1178`, `uc-macrocode.lisp:9`).

So nothing jumps to an address in the band. The machine builds a frame for
`LISP-TOP-LEVEL` (`sys/ltop.lisp:67`), points the macro PC at that function's
first instruction and falls into the main loop; the first macroinstruction it
ever executes is that function's call to `LISP-REINITIALIZE` (`:68`). A warm
boot takes the same path from `BEG0000` and re-enters the same function, which
is why it keeps the world and loses the stack.

## What belongs to the machine and what belongs to the files

Four things in this sequence are hardware: the PROM running from I-memory
location 0, the location-6 handshake with `PROM-DISABLE`, the keyboard
registers that choose cold or warm, and `MACHINE-ID`, which tells the
microcode whether it runs on a CADR or on QUUX. Everything else is a file
format --- the label, the partition table, the section types, the band formats
and the scratch-pad init area --- and a machine that reads those formats boots
the same way whatever its microcode looks like.
