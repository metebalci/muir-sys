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
| `pdl-refill` | The PDL buffer refill brings a one-q-forward back into the buffer as it was written (`sys/ucadr/uc-page-fault.lisp`, `PB-TRANS`). An interpreted special binding's slot is still the forward, ending its frame, after a process switch, and a `SETQ` after the switch reaches the variable. The first case, with no switch, is the control. Microcode that follows the forward fails the other three. |
| `zero-length-region` | Freeing a region of no length leaves the regions around it alone (`sys/ucadr/uc-storage-allocation.lisp`, `FREE-REGION` and `UPDATE-REGION-PHT`). It frees the region of no length the cold load gives `FASL-TEMP-AREA`, as a full GC does, and checks that the region whose first quantum holds its origin still has that quantum in the address space map, that the page below the origin is still in the page hash table, and that `ROOM` still finds every region's area. The first two cases check that the band has such a region. Microcode without the fix halts in the third case, at `GET-MAP-BITS`'s "Region not found", so the case has no answer. |
