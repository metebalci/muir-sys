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
lispm-check's default band, `run/check/band.img`, is System 2000's. The exit
status is 0 when every check passes.

| Check | What it checks |
|---|---|
| `float-printing` | An IEEE single's infinity prints as `#.SI:SINGLE-FLOAT-POSITIVE-INFINITY` or `-NEGATIVE-INFINITY` and reads back to the same bits (`sys/io/print.lisp`, `PRINT-FLONUM`; `sys/sys2/numer.lisp`). Run it with the tree's files compiled first: `--compile --files sys/io/print.lisp,sys/sys2/numer.lisp`. The first four cases, finite floats printing as before, are controls. A printer that scales an infinity by powers of ten prints `1.0e153` and fails the two printing cases. |
| `interpreter-closure` | An interpreted closure made while `DEFAULT-CONS-AREA` is a temporary area leaves the enclosing, still running `LET` intact (`sys/sys/eval.lisp`, `UNSTACKIFY-ENVIRONMENT`). The `LET`'s frame is not forwarded into the temporary area, and after the area is reset and consed in again the `LET`'s variable keeps its value. The first case, a closure made in a permanent area, is the control. A system that conses the copies in the temporary area fails the other two. |
| `interpreter-closure-scope` | Interpreted closures, and the code around them, see the variables in scope (`sys/sys/eval.lisp`, `SERIAL-BINDING-LIST`, `APPLY-LAMBDA-BINDVAR` and `EVAL1`). A closure made in a `LET*` init form sees the variables bound before it, not the one it initializes; the `LET*`'s body sees all of them, shares them with the closure, and still does once the closure has returned; the closure works after the `LET*` has returned. `PROG*` does the same, and so does a lambda's `&optional` or `&aux` init form. The arguments of a call to a local function (`FLET`, `LABELS`) are evaluated where it is called, not in the function's environment. The first five cases are controls, which pass without the fixes: closures over `LET`, a call to an `FLET` function with a constant or a variable bound outside it, a `LET*` of more than 16 variables (built in the heap) and a special variable. The last eight are controls too, with the definitions they need: an applyhook that applies as the stepper does sees the same calls, functions and arguments, and an evalhook the same forms. A system that stores a frame back into the link a closure took, extends it there, or binds a closure's environment before evaluating its arguments fails the other fifteen; one that hands the applyhook the closure instead of its lambda fails the applyhook case. |
