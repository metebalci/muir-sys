# T2: the build host's own TCP to the band

`tools/tcp-check/run` is T2 of QUUX's Ethernet contract (section 9): Linux's
own TCP, its sockets as clients, to the band through the fault relay
(`tools/fault-relay/`) and a pooled tap. Python's standard library only.

```
tools/tcp-check/run [--parts telnet,echo,churn,limit,stall,table,totals]
                    [--echo-sizes 1,1024,65536,1048576] [--echo-times 10] [--connections 1000]
                    [--stall 30,180] [--faults 'RELAY-FLAGS'] [--transfer-timeout S]
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
| `table` | after the parts before it, the band holds no connection but the control session's |
| `totals` | since the faults started, the band's total of 241 `<15:9>`, the IPv4 checks, has risen by exactly the frames the relay corrupted toward it, and of `<7:4>`, the type filter, by exactly the frames it injected (a frame still in flight is waited for, up to 5 s) |

T4's matrix is `--parts echo,table,totals --faults '--inject 100 --seed 1
FAULT --direction D'` for each fault of section 9 (loss 1, 5 and 20%,
duplicates 5%, reordering 5%, jitter 0-50 ms; each direction alone and both,
and corruption of 1% toward the band), against one run with no fault, whose
echo's time is the base of the bound of ten times. The relay's report
(`relay.json`, kept with `--keep`) gives each direction's resends.

## Still to come

- **The TELNET suite at 5% loss and 5% reorder** gives G-TCP's pass/fail:
  lispm-check's cases with `LISPM_CHECK_RELAY_FLAGS` set, against G-TCP's
  own runs, once G-TCP's harness exists.
