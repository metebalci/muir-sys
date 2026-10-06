# The microcode's checks

Cases that check the microcode assembled from `sys/ucadr/`, run on a band
through `tools/lispm-check`. Each check is a case file, `cases/NAME.cases`,
with the Lisp it needs first, if any, in `lisp/NAME.lisp`.

```
tools/microcode-check/run -- --band PACK --ubin UBIN              # every check
tools/microcode-check/run pdl-refill -- --band PACK --ubin UBIN   # one of them
tools/microcode-check/run pdl-refill -- --band PACK --ubin UBIN --engine rtl
```

Arguments after `--` go to every lispm-check run. The machine runs the
microcode in the band's current microload, not the one in `ubin/`, so the band
must carry the microcode under test: put `sys/ubin/ucadr.mcr` in its current
MCR partition with `diskpack PACK load MCR2 ucadr.mcr` (muir-sim), and serve
the same `ubin/`, whose `ucadr.tbl` the cold boot reads. lispm-check's default
band, `run/check/band.img`, runs MIT's microcode 323. The exit status is 0 when
every check passes.

| Check | What it checks |
|---|---|
| `chaos-transmit-order` | The Chaosnet's transmit list goes out oldest first (`CHAOS-XMT-0`, `CHAOS-XMT-DONE`, `CHAOS-XMT-TAIL`, `sys/ucadr/uc-chaos.lisp`). `CTO-RUN` (`lisp/chaos-transmit-order.lisp`) pushes four full-length UNC packets back to back inside `WITHOUT-INTERRUPTS`, each to its own absent host, 177270 to 177273, and notes the order in which they leave the transmit list. The pushes are `TRANSMIT-INT-PKT`'s own push (`CTO-PUSH`): the whole of `TRANSMIT-INT-PKT` takes about 500 us of the CADR's time, too long to land four inside the first packet's frame. The precondition is that all four are on the list after the last push, the first still on the cable ("window entered"); one packet alone leaving is the control. Microcode that sends and pops the head, MIT's, frees a packet pushed while another is on the cable unsent and sends the old one again: they leave in another order than (0 1 2 3), and muir-sim's `--chaos-trace` (through a wrapper of `cadr`) shows 0, 2, 1, 0 on the cable. |
| `pdl-refill` | The PDL buffer refill brings a one-q-forward back into the buffer as it was written (`sys/ucadr/uc-page-fault.lisp`, `PB-TRANS`). An interpreted special binding's slot is still the forward, ending its frame, after a process switch, and a `SETQ` after the switch reaches the variable. The first case, with no switch, is the control. Microcode that follows the forward fails the other three. |
| `zero-length-region` | Freeing a region of no length leaves the regions around it alone (`sys/ucadr/uc-storage-allocation.lisp`, `FREE-REGION` and `UPDATE-REGION-PHT`). It frees the region of no length the cold load gives `FASL-TEMP-AREA`, as a full GC does, and checks that the region whose first quantum holds its origin still has that quantum in the address space map, that the page below the origin is still in the page hash table, and that `ROOM` still finds every region's area. The first two cases check that the band has such a region. Microcode without the fix halts in the third case, at `GET-MAP-BITS`'s "Region not found", so the case has no answer. |
| `findcore-fixnum` | `%FINDCORE` returns the frame's number as a fixnum, and `PAGE-IN-WORDS` pages a run of pages in with it (`sys/ucadr/uc-page-fault.lisp`, `XFINDCORE`). `lisp/findcore-fixnum.lisp` takes a frame with `%FINDCORE` and gives it back, and pages four pages of `P-N-STRING` that are not in core in with `PAGE-IN-WORDS`, comparing each with its blocks in the PAGE partition. The first case, that there are such pages, is the control. Microcode whose `%FINDCORE` returns the frame's number with data type 0, as QUUX's did, fails the check before its cases: System 1003's band on it runs macrocode but never reaches its TELNET prompt (measured, 300 s). |
| `un-cons-gc-pointer` | `UN-CONS` backs the scavenger's pointer, `REGION-GC-POINTER`, up to the free pointer it lowers (`sys/ucadr/uc-storage-allocation.lisp`, `UN-CONS-1`). `lisp/un-cons-gc-pointer.lisp` adds 1 to a bignum of three words in an area of its own, through `SI:NUMBER-CONS-AREA`, so that the sum gives its fourth word back, and reads the region's pointers. The scavenger passing those words first is planted by setting the gc pointer above the free pointer. The first three cases are controls: the sum takes three words, and with the gc pointer at the free pointer it stays at or below it. Microcode that compares the relative gc pointer with the object's end as an address, MIT's, leaves the planted pointer above the free pointer and fails the last two. |
