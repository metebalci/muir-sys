# T2: the build host's own TCP to the band

`tools/tcp-check/run` is T2 of QUUX's Ethernet contract (section 9): Linux's
own TCP, its sockets as clients, to the band through the fault relay
(`tools/fault-relay/`) and a pooled tap. Python's standard library only.

```
tools/tcp-check/run [--parts telnet,echo,churn,limit,stall,table,totals]
                    [--echo-sizes 1,1024,65536,1048576] [--echo-times 10] [--connections 1000]
                    [--stall 30,180] [--faults 'RELAY-FLAGS'] [--transfer-timeout S]
                    [--trace FILE] [--wall-base FILE] [--wall-m 10] [--wall-m-high 14]
                    [--wall-base-out FILE] [--wall-log FILE] [--mloss-size N] [--ss-log FILE]
                    [-- LISPM-CHECK-ARGS...]
```

It is `tools/lispm-check`'s own code, loaded from beside it: the flags after
`--` are lispm-check's (`--band`, `--quux`, `--ubin`, `--tree`, `--engine`,
`--file-server`, `--network`, `--keep`, and `LISPM_CHECK_TAPS` and
`LISPM_CHECK_PORTS`), and it takes a tap and resumes that index's checkpoint
as lispm-check does, making it first when there is none. The machine must be
revision 16 and the band one with the network. The control session is a
TELNET session over lispm-check's `--network`, `tcp` unless another is
given, on which it turns the test echo service on (`IP:*TEST-ECHO-SERVICE*`)
and reads the band's connections and TIME-WAIT records. Then, from sockets
bound to the run's tap to QUUX's address behind it:

| Part | It checks |
|---|---|
| `switch` | the test switch is turned on at the control session |
| `telnet` | three TELNET sessions to port 23 one after another and two at once: each gets the banner, answers a form, and at the client's EOF its server closes its side, with FIN (section 7) |
| `echo` | the test echo service, port 7, both ways at once: each size (1 B, 1 KiB, 64 KiB, 1 MiB) sent ten times while its echo is read, the echo equal to what was sent by sha256 |
| `churn` | 1,000 connections to port 7 opened and closed in a row, each echoing one byte; after them the band has no connection but the control session's, and 64 TIME-WAIT records or fewer |
| `limit` | with the control session closed first, since it is one of the 8: 8 connections at once, each echoing a byte, and a ninth refused with RST; after them none but a new control session's |
| `relay` | the fault relay, which checks every Ethernet frame the band sends with its own code, found none bad |

The status is 0 when every line passes, 1 when one fails, 2 when the run
itself failed (lispm-check's), 3 for a hang in the setup. T2 asserts
outcomes, not timers (section 9, "How the wall-clocked lanes are judged");
the wall clock bounds each transfer only (`--transfer-timeout`, 900 s).

```
LISPM_CHECK_TAPS=8-15 LISPM_CHECK_PORTS=LO-HI tools/tcp-check/run -- \
    --band DISK --ubin DIR --quux QUUX16 --file-server device --keep
```

## Measured (E5, slice 1)

On micro, revision 16. On a band without the stack (the control session over
Chaos) every line fails for its own reason: the test switch is no variable of
the band, each part finds no route to the band (nothing answers ARP), and the
relay sees no frame from it. On the band with the stack (the control session
over TCP) every line passes: 1 MiB echoed ten times in 214 s, about 49 KB/s
each way at once; 1,000 connections in 68 s, after which the band holds none
but the control session's and no TIME-WAIT record (the client closes first);
the stall's session answers 0.4 s after the machine goes on, after 30 s and
after 180 s; the relay checked 15,642 frames from the band and found none bad.

## T4: through the relay's faults

`--faults 'FLAGS'` gives the fault relay its faults (`tools/fault-relay/`,
"The faults"), through `LISPM_CHECK_RELAY_FLAGS`, with `--arm-on-signal`:
the relay moves frames clean until the control session has read the band's
totals, and `faults on` says when they start. Two parts are T4's, each run
when named:

| Part | It checks |
|---|---|
| `table` | after the parts before it, the band holds no connection but the control session's: counted once a second until none is left, for at most 120 s, above R2's 100 s; its line gives the wait and the counts, and on a failure each connection left, by remote port and state. A single count failed on a connection rightly in LAST-ACK, whose last ACK the relay had lost and which the band closed 3.3 s later |
| `totals` | since the faults started, the band's total of 241 `<15:9>`, the IPv4 checks, has risen by exactly the frames the relay corrupted toward it, and of `<7:4>`, the type filter, by exactly the frames it injected (a frame still in flight is waited for, up to 5 s) |

T4's matrix is `--parts echo,table,totals --faults '--inject 100 --seed 1
FAULT --direction D'` for each fault of section 9 (loss 1, 5 and 20%,
duplicates 5%, reordering 5%, jitter 0-50 ms; each direction alone and both,
and corruption of 1% toward the band), against one run with no fault, whose
echo's time is the base of the bound of ten times. The relay's report
(`relay.json`, kept with `--keep`) gives each direction's resends.

### The wall bound

T4's wall bound (section 9, "How the wall-clocked lanes are judged",
amendment 4) is per session: one echo of one size. `--wall-base FILE` turns
it on, FILE giving T0 of each size, the median of its sessions with no
faults, which `--wall-base-out FILE` writes from a run with none. Each
session must end within max(M x T0, T0 + 60 s), M `--wall-m`, 10; at 20%
loss within max(M x T0, T0 + 120 s), M `--wall-m-high`, 14: about twice
M-loss's worst seed, 6.9 x T0 (below, "Measured"). The floor of 120 s at 20%
loss: on a correct stack a 64 KiB echo took up to 93.8 s counted there,
Linux's own RTO and backoff after RTT samples taken from the band's late
ACKs, against 61.4 s; a band whose backoff an ACK never clears took 132.7 s
to 900 s, against 121.4 s. Not counted is the time inside a run of four or
more failed transmissions of one segment, from the run's first to the
segment's next transmission, a transmission failing when the relay lost it
or when no ACK covering it reached its sender before the next. At 20% loss a
session may also end early, by the band's R2 or by Linux's abort: such an
ending passes when, in the 100 s up to the ending sender's last transmission
of its oldest unacknowledged segment, every transmission of that segment
failed, an ACK counting only up to that last transmission's next RTO (twice
the gap from the transmission before it, at most 120 s), and what was echoed
before the end is exact. The window ends at that transmission and not at the
session's end, since the band's R2 is silent and its peer may hear of it much
later: on seed 3 of loss20-both the band closed a 1 MiB echo by R2 at about
132 s and Linux heard of it at 554 s, through a zero-window probe answered by
RST, after an ACK of the band's segment had reached it too late. The record
is the relay's trace (`--trace FILE`, the relay's `--trace`). The `wall` line
judges every echo session of the run; `--wall-log` keeps each session's
figures (its time, the time counted, the runs excused, the bound).

**The conditions** the bound is set for: micro at 20 ns, unpaced, one
wall-clocked run (T2 or a T4 row) at a time on the host. The band's timers run
on its own clock, machine time, and Linux's on the host's; measured by the
band's TSval against the relay's clock, micro at 20 ns ran at 0.76-0.78 of
real time alone and at 0.61 beside other runs, micro at 48 ns at about 1.0,
and rtl at 20 ns at 0.073.

`tools/tcp-check/test` checks the judge itself on made-up relay records, with
no machine: an ending by the band's R2 and one by Linux's abort, each
explained only with the window at the sender's last transmission and the ACKs
counted to its next RTO; one whose last transmission was acknowledged in time,
not explained; and the floor and M at 20% and at 5% loss. Each of six partial
changes (the window moved for one sender only, the ACKs counted to the end, the
floor raised at every rate or at none, M dropped at 20%) fails a case.

```
tools/tcp-check/run --parts echo,table --wall-base-out base.json --trace none.trace -- ...
tools/tcp-check/run --parts echo,table,totals --faults '--inject 100 --seed 1 --loss 5 --direction both' \
    --trace loss5.trace --wall-base base.json --wall-log loss5.wall -- ...
```

### M-loss

`--parts mloss` is section 15's M-loss (amendment 4): one echo of
`--mloss-size` (1 MiB), with Linux's state of the connection read by
`ss -tnio` every 2 s (`--ss-log` keeps the samples). It passes when the echo
ends as T4 allows, byte-exact or by the endings clause above, and at every
sample whose `bytes_acked` rose by at least one MSS since the one before,
Linux's backoff is 3 or less. Its line gives the echo's time against T0 (with
`--wall-base`) and Linux's largest backoff, overall and at a sample after
progress. The runs are 20% loss toward the band and both ways, seeds 1 to 3:

```
tools/tcp-check/run --parts mloss,table --faults '--seed 1 --loss 20 --direction to-band' \
    --trace to-band-s1.trace --ss-log to-band-s1.ss --wall-base base.json -- ...
```

### Measured (amendment 4)

On micro at 19 ns, revision 16, band4 with E3's microcode: T0 of 1 MiB 32.5 s
on the stack without timestamps and 30.2 s with them (`--wall-base-out`,
loaded host). M-loss:

| Run | Without timestamps | With them |
|---|---|---|
| to band, seed 1 | FAIL: no EOF in 900 s, 197,748 bytes; backoff 11 | PASS: 88.6 s, 2.9 x T0; backoff at most 2 |
| to band, seed 2 | FAIL: 900 s, 598,272 bytes; backoff 11 | PASS: 80.1 s, 2.7 x; 3 |
| to band, seed 3 | FAIL: 900 s, 435,320 bytes; backoff 10 | PASS: 95.4 s, 3.2 x; 4 (2 after progress) |
| both, seed 1 | FAIL: 900 s, 206,508 bytes; backoff 8 | PASS: 177.2 s, 5.9 x; 2 |
| both, seed 2 | FAIL: 900 s, 394,684 bytes; backoff 13 | PASS: 208.2 s, 6.9 x; 4 (3 after progress) |
| both, seed 3 | FAIL: 900 s, 316,576 bytes; backoff 9 | PASS: 195.1 s, 6.5 x; 5 (3 after progress) |

T4's matrix of 20 runs with the timestamps and the wall bound (M 10, 14 at
20% loss): every line of every run passes, the 800 sessions all within
their bounds; the slowest 1 MiB session at 5% loss took 2.1 x T0, and at
20% loss both ways 8.1 x (6.8 x counted).

## Still to come

- **The TELNET suite at 5% loss and 5% reorder** gives G-TCP's pass/fail:
  lispm-check's cases with `LISPM_CHECK_RELAY_FLAGS` set, against G-TCP's
  own runs, once G-TCP's harness exists.
