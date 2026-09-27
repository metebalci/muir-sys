# How a machine boots

This is the path a CADR takes from power-on to the first macroinstruction: the
boot PROM loads microcode, the microcode loads a world, and the microcode
enters one Lisp function. It follows the tree's own code, and each claim cites
a file and line.

It was carried over from the System 2000 line (lmz-sys `fecd0a5`), and every
citation was checked again against this tree, whose boot PROM (version 9) and
microcode (323) are MIT's. Nothing here is about compiling or building;
`docs/building.md` covers that.

## The three stages

| Stage | Who runs | What it produces |
|---|---|---|
| 1 | the boot PROM, `ucadr/promh.text` | I, D and A/M memory loaded from the MCR partition |
| 2 | the loaded microcode, `ucadr/uc-cadr.lisp` and `uc-cold-disk.lisp` | a valid virtual memory, from a band |
| 3 | the same microcode, `uc-cold-disk.lisp:709-761` | a stack frame entering `LISP-TOP-LEVEL` |

## Stage 1: the PROM loads microcode

The PROM is `sys/ucadr/promh.text`, assembled to `sys/ubin/promh.mcr`. It runs
from I-memory location 0 and knows nothing about bands, Lisp or virtual memory.

It first tests the hardware a bit at a time --- every bit of a word of zeros,
the ALU's carries, the byte hardware, M-memory, A-memory and the PDL buffer
(`:168-259`) --- because a fault found here is better than a world that boots
wrong. Then it clears M and A memory, the PDL buffer, the SPC stack, both
levels of the map, I-memory and D-memory, so their parity is good
(`:261-345`), and sets up four map entries, the only ones it uses
(`:374-393`):

| virtual page | maps to |
|---|---|
| 0 | the first page of main memory |
| 1 | the disk control registers |
| 2 | the debug (spy) interface at Unibus 766000 |
| 3 | the second page of main memory, the system communication area |

Before it saves page 0 it reads and rewrites every word of it, so its parity
is good (`PAGE-0-PARITY-FIX`, `:396-409`). That loop tests its address after
the write and so also touches virtual 400, one word past page 0: MIT's
comment says "This does one extra location, too bad", and a comment beside it
records the fault, which is left as it is for now.

### Why it saves physical page 0

The PROM has no buffer of its own. It reads the disk label into physical page
0, and `GET-NEXT-PAGE` reads every block of the microcode partition into
physical page 0 as well (`:627-635`). So merely running destroys one page of
main memory --- and on a warm boot that page belongs to a live Lisp world.

Before touching it, the PROM therefore writes physical page 0 out to disk block
1, which the label format reserves for this purpose (`SAVE-A-PAGE`, `:424-438`).
It verifies the write with a read-compare and retries on failure, since a page
saved wrongly is worse than not saving it. At `DONE-LOADING` it reads the block
back into page 0 (`:584-588`). The page is borrowed and returned.

### Finding the microcode

The label is block 0. Word 0 must be the four characters `LABL` and word 1 must
be 1, or the PROM halts at `ERROR-BAD-LABEL` (`DECODE-LABEL`, `:457-463`).
Words 2 to 5 give the disk geometry, and **word 6 names the current microcode
partition** (`:464-478`). Word 200 is the number of partitions, word 201 the
size of a partition descriptor, and word 202 begins the table (`:479-486`); the
PROM walks it for a descriptor whose first word is that name (`SEARCH-LABEL`,
`:493-500`), and takes the start block and length from the two words after it
(`FOUND-PARTITION`, `:502-510`).

Which microcode a machine runs is therefore a property of the pack, written in
one word of its label, not of the PROM.

### What a microcode partition contains

The partition is a sequence of sections. Each begins with three words: the
section type, the initial address and the number of locations (`:512-517`). The
PROM dispatches on the type (`:518-529`):

| type | meaning | how it is loaded |
|---|---|---|
| 1 | I-memory | two words per microinstruction, written with `WRITE-I-MEM` (`:531-544`) |
| 2 | D-memory, the dispatch RAM | one word each, through `WRITE-DISPATCH-RAM` (`:546-556`) |
| 3 | main memory | a fourth header word gives the physical address, and whole blocks are read straight from the partition (`:558-571`) |
| 4 | A and M memory | words are pushed onto the PDL buffer (`:573-582`) |

The other end of this format is `sys/sys/qwmcr.lisp`, which writes it: "An MCR
file looks a lot like a microcode partition" (`:9-12`). It emits I-memory as
type 1, D-memory as type 2, A/M as type 4 (`:45-48`), and the microcode symbol
area as a type 3 main-memory section addressed to that area's origin
(`WRITE-MICRO-CODE-SYMBOL-AREA-PART-1`, `:92-104`). That last section matters
at run time: it is the table the `MISC` macroinstruction dispatches through
(`uc-macrocode.lisp:498-504`, `uc-cold-disk.lisp:690-691`), so the mapping
from a misc opcode to a microcode address arrives with the microcode, in the
same file.

A/M memory goes through the PDL buffer rather than straight into place because
the PROM's own constants and temporaries live in A/M. It cannot write them
until it has finished needing them, so it stacks the new contents and copies
them in as its last act (`FILL-M-LOOP` and `FILL-A-LOOP`, `:593-604`). That is
also why `Q-R`, `MD` and `VMA` are loaded a few instructions earlier, with the
note "Note that Q-R, MD, and VMA are already set up" (`:589-591`, `:609`): after
the fill, no A/M constant of the PROM's exists any more. `FILL-A-LOOP` runs
until the 10-bit PDL index wraps to 0, after location 1777.

### The handoff

The PROM ends by writing 44 to Unibus 766012 --- `ERROR-STOP-ENABLE` plus
`PROM-DISABLE` --- and jumping to I-memory location 6 (`JUMP-TO-6`,
`:611-613`). Both programs keep a spin loop there that counts `Q-R` down
(`promh.text:81-84`, `uc-cadr.lisp:64-66`), so the machine is looping at
location 6 when the PROM switches off underneath it and the loaded microcode's
location 6 continues the same loop. It works because the two agree on where
the constant -1 lives: the PROM's `A-ONES` is A-memory location 3
(`promh.text:33-36`), and the microcode's `A-MINUS-ONE` is annotated "MUST BE
3" (`uc-parameters.lisp:531`). `FILL-M-LOOP` puts the microcode's -1 there,
since writing M memory also writes the A location that shadows it
(`uc-parameters.lisp:521-526`), and `FILL-A-LOOP`, which starts at location
40, leaves it alone.

## Stage 2: the microcode loads a world

The landing site is `PROM` at I-memory location 6 in `uc-cadr.lisp:64-81`. It
reads the keyboard to decide what kind of boot this is: if the keyboard is not
ready, or the keycode is 46, Rubout, it cold-boots; otherwise the world in
memory is assumed valid and it jumps straight to `BEG0000`.

A cold boot enters `COLD-BOOT` (`uc-cold-disk.lisp:294`), which is
`%DISK-RESTORE` asked for the current band. It resets the machine, sizes main
memory by writing and reading in 16K steps until a location does not answer
(`:314-324`), and reads the label to find **both the paging partition and the
band's partition** (`COLD-READ-LABEL`, `:792-833`); `A-DISK-OFFSET` becomes the
disk address of virtual location 0, the start of the paging partition
(`:819-821`).

It then reads the band's first three pages into core pages 0 to 2 (`:332-336`)
and consults the system communication area, now at physical 400, for
`%SYS-COM-BAND-FORMAT` (`:337-340`):

| format | meaning |
|---|---|
| 0 | expanded; in practice a cold-load band |
| 1000 | compressed, copied region by region |
| 1001 | incremental |

The important part is what "loading a band" means. The band is **copied into
the paging partition**, not into memory: `DISK-COPY-SECTION` reads from `M-I`
in the band and writes to `M-Q` in the paging area (`:946-955`), and for a
compressed band each region goes to the block matching its virtual address,
`M-Q` being the region origin plus `A-DISK-OFFSET` (`:398-399`). Only then does
`COLD-SWAP-IN` read the wired pages into core, again from `A-DISK-OFFSET`
(`:567-577`). Everything else arrives later as page faults. The band does not
get loaded; it becomes the backing store.

## Stage 3: entering Lisp

Both kinds of boot converge on `BEG0000` (`:644`), which reinitializes the
flags, disables scheduling and scavenging, resets the machine and rebuilds the
map (`:644-708`).

`BEGCM4` (`:709-718`) then copies virtual locations 1000 onward ---
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
it, marked `;INDIRECT` (`:719-727`), so a world runs whatever that cell holds
now rather than whatever it held when the band was written.

The microcode then builds one stack frame by hand: it pushes the FEF, refuses
anything that is not a `DTP-FEF-POINTER`, sets `M-AP`, and takes the initial PC
out of the FEF header (`:729-753`). Finally (`:756-761`):

```
	((MICRO-STACK-DATA-PUSH) A-MAIN-DISPATCH)	;PUSH MAGIC RETURN
	...
	(JUMP-XCT-NEXT QLENX)			;CALL INITIAL FUNCTION, NEVER RETURNS
```

`QLENX` (`uc-call-return.lisp:2194-2197`) sets `LOCATION-COUNTER` to the FEF's
address doubled plus that PC and then `POPJ`s --- to the address just pushed,
`A-MAIN-DISPATCH`, which is `QMLP`, the main instruction loop
(`uc-parameters.lisp:1174`, `uc-macrocode.lisp:9`).

So nothing jumps to an address in the band. The machine builds a frame for
`LISP-TOP-LEVEL` (`sys/ltop.lisp:67`), points the macro PC at that function's
first instruction and falls into the main loop; the first macroinstruction it
ever executes is that function's call to `LISP-REINITIALIZE` (`:68`). A warm
boot takes the same path from `BEG0000` and re-enters the same function, which
is why it keeps the world and loses the stack.

## What belongs to the CADR and what belongs to the files

Three things in this sequence are hardware: the PROM running from I-memory
location 0, the location-6 handshake with `PROM-DISABLE`, and the keyboard
registers that choose cold or warm. Everything else is a file format --- the
label, the partition table, the section types, the band formats and the
scratch-pad init area --- and a machine that reads those formats boots the same
way whatever its microcode looks like.
