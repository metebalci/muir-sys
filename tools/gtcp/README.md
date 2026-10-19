# G-TCP: the gate before the tools switch to TCP

`tools/gtcp/run` is QUUX's Ethernet contract's gate G-TCP (section 8 R2;
amendment 2, 5.3): on the R1 band and its checkpoint, the same band and
microcode for both transports, every suite runs twice over Chaos and once
over TCP, and each case's pass/fail over TCP must equal its pass/fail over
Chaos. Python's standard library only.

```
tools/gtcp/run --units FILE [--taps LIST] [--out DIR] [--faulty 'RELAY-FLAGS']
               [--order chaos,tcp,chaos] [-- LISPM-CHECK-ARGS...]
tools/gtcp/run --compare A B [--out DIR]
tools/gtcp/test
```

**The units.** `--units` names one unit a line: a case file of
`tools/lispm-check` (`lispm-check CASES [ARG...]`), a check of
`tools/system-check` or `tools/microcode-check` (`system-check CHECK
[ARG...]`, ARG the check's own lispm-check arguments from its README, such as
`--compile` or `--timeout 7200`, given after the gate's so that they win), a
check of `tools/assembler-check` (`assembler-check CHECK [ARG...]`), or any
command (`command NAME CMD [ARG...]`), which finds the run in `GTCP_RUN`
(`chaos1`, `tcp`, `chaos2`, `faulty`) and lispm-check's arguments,
shell-quoted, in `GTCP_LISPM_CHECK_ARGS`. The arguments after `--` go to
every run's lispm-check: `--band`, `--quux`, `--ubin`, `--engine` and the
rest, so micro and rtl are two runs of the gate.

**One tap a unit.** A unit's runs hold one tap: `LISPM_CHECK_TAPS` names it,
and `LISPM_CHECK_NETWORK` gives the run's network, so each run takes that tap
and resumes that index's checkpoint, which the first run on it makes when
there is none (amendment 2, 5.1). Units run in parallel, one on each tap of
`--taps` (tap indexes as lispm-check takes them; 8-15 by default). The runs
go Chaos, TCP, Chaos (`--order`), so that a drift in time shows as the two
Chaos runs differing rather than as a difference of TCP's.

**The cases and the verdict.** A case is a verdict line lispm-check prints
(`PASS`, `FAIL` or `ERROR` and its form), keyed by its unit, its form and its
place among the lines of that form; a unit with no such lines is one case,
its verdict the run's exit status. A case missing from a run, which ended
before it, is a fail. The verdict compared is pass (`PASS`) or fail
(anything else): printed values are not compared (section 8 R2), nor `FAIL`
against `ERROR`, though both are reported. Each case is then

| Kind | When | Gated |
|---|---|---|
| `equal` | the three runs agree | |
| `flaky` | the two Chaos runs differ | no: listed and reported |
| `difference` | the Chaos runs agree and the TCP run does not | yes |

and the exit status is 1 when any case is a difference, 0 when none is, and
2 when the gate's run itself failed. A case that fails in every run is equal
and gates nothing, so the report says so for each unit (`FAILS-EVERYWHERE`)
and counts them: a check run without its own flags fails that way (on
band4-e3, revision 16, micro, `fef-tags` without `--compile` and
`scheduler-simple-wait` without a longer `--timeout`, both of which pass with
them, as the soak runs them).

**T4's TELNET suite** (section 9: at 5% loss with 5% reorder it gives
G-TCP's pass/fail): `--faulty '--loss 5 --reorder 5 --seed 1'` adds a fourth
run, over TCP through the fault relay with those faults
(`LISPM_CHECK_RELAY_FLAGS`), judged as the TCP run is.

**The soak** (section 8 R2, T6): `--compare A B` lists the cases whose
pass/fail differ between two runs of the soak matrix, each a directory of
lispm-check outputs compared by their paths below it; each listed case is
then run again on one index both ways, as a unit of the gate, before it
counts as a difference.

**Output.** `DIR/UNIT/RUN.out` for each run, headed by its network, tap and
command; `DIR/report.txt`, every case that is not equal in all runs and a
count line, `gtcp: N cases: E equal, F flaky (listed, not gated), D
differences`; and `DIR/report.json`, every case's verdicts. `DIR` is
`run/gtcp/DATE-TIME` unless `--out` says.

**Its self-test**, `tools/gtcp/test`, runs the gate on stand-in suites with
no band: a case failing over TCP alone is a difference and the exit 1; one
failing in the second Chaos run alone is flaky and not gated (exit 0 alone);
cases missing from a cut-short TCP run are differences; a run with no
verdict lines is one case; `FAIL` against `ERROR` is equal and reported; the
faulty run's failure is a difference; a unit's runs hold one tap; a check's
own flags reach each of its runs after the gate's; a case failing everywhere
is said; `--compare` lists a differing case. Planted
faults in the gate, each failing it: flaky cases gated, missing cases taken
as passes, verdict kinds compared, the TCP run ignored, a check's own flags
dropped.

**What the gate does not reach.** The tools that build their own sessions
from lispm-check's classes (cross-build's sessions, `system-check/warm-boot`,
`microcode-check/generational-save`) are not units of the gate. Since R2's
switch (QUUX's Ethernet contract, section 8 R2) they take their network and
tap through lispm-check's `harness_network`, over TCP by default on
revision 16, and `tools/lispm-check-test/harnesses.sh` checks them on
revisions 16 and 15.

**What it found.** On the stack with amendment 4's changes, G-TCP's 1,445
cases on micro were all equal between the networks. On rtl, 1,444 were
equal; the one difference, microcode-check's `sg-deferred-entry`, came from
the check's exact count of the network process's passes, and with the
check corrected it was equal over Chaos and TCP on both engines. The soak's
`micro-kria-32mw` lane, run both ways (section 9, T6, which one lane
satisfies), agreed case for case under `--compare`.
