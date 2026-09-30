# The system's checks

Cases that check the Lisp system in `sys/`, run on a band through
`tools/lispm-check`, as `tools/microcode-check/` does for the microcode.
Each check is a case file, `cases/NAME.cases`, with the Lisp it needs first,
if any, in `lisp/NAME.lisp`.

```
tools/system-check/run -- --band PACK --ubin UBIN                         # every check
tools/system-check/run interpreter-closure -- --band PACK --ubin UBIN     # one of them
tools/system-check/run interpreter-closure -- --band PACK --ubin UBIN \
    --compile --files sys/sys/eval.lisp                                   # a changed source first
```

Arguments after `--` go to every lispm-check run. A check runs against the
system the band was built with. To check a change to a source before a band is
built from it, compile and load that file first, with lispm-check's
`--compile` and `--files`; a check with its own `lisp/NAME.lisp` then needs
that file named in the same `--files`, as lispm-check takes one list.
lispm-check's default band, `run/check/band.img`, is System 1001's. The exit
status is 0 when every check passes.

| Check | What it checks |
|---|---|
| `interpreter-closure` | An interpreted closure made while `DEFAULT-CONS-AREA` is a temporary area leaves the enclosing, still running `LET` intact (`sys/sys/eval.lisp`, `UNSTACKIFY-ENVIRONMENT`). The `LET`'s frame is not forwarded into the temporary area, and after the area is reset and consed in again the `LET`'s variable keeps its value. The first case, a closure made in a permanent area, is the control. A system that conses the copies in the temporary area fails the other two. |
