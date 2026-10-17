# The fault relay

`tools/fault-relay/relay` puts a band behind a tap of the pool: a tap of
muir-sim's `tools/quux-taps` at one end, and at the other a UNIX stream
socket that muir's `--ethernet-socket` connects to, in its plain mode (QUUX's
Ethernet contract, section 3). It is the Ethernet frame mover (muir-sim's
`tools/ethernet-frame-mover`) with the fault relay's additions: counts, and a
check of every Ethernet frame the band sends with its own code (section 9).
Python's standard library only.

```
tools/fault-relay/relay [--tap NAME[,NAME...]] [--report FILE]
                        [--seed N] [--loss P] [--duplicate P] [--reorder P] [--corrupt P]
                        [--jitter MS] [--direction to-band|from-band|both] [--inject N]
                        [--arm-on-signal] PATH
tools/fault-relay/test
```

It takes a tap as the mover does, and prints the mover's line once it holds
one and listens at `PATH`:

```
quux1 --ip-address 169.254.101.2/30 --ip-gateway 169.254.101.1
```

- `--tap` names the taps to try, in order; a tap another program holds is
  passed for the next, and when every tap tried is held it exits with status
  75, so that its caller waits and tries again. Without it, the pool from
  `quux0` up. It takes host-only taps only, each with a /30 of its own
  (the contract, amendment 3): a LAN tap is refused.
- `--report FILE` gets the counts and the check's findings as JSON, when the
  relay ends (SIGTERM or ^C) and on SIGUSR1: Ethernet frames and bytes each
  way by Ethernet type, the frames the tap gave while no machine was
  connected, the connections, and each bad frame from the band (its number,
  what is wrong, its first 64 bytes; the first 50, the rest counted).

One machine is connected at a time, and a machine that closes leaves the
relay holding its tap for the next: one run of `tools/lispm-check` starts one
relay, which serves the setup's machine and then the check's, so the run
holds its tap throughout.

**The check.** An ARP frame is 42 bytes, for Ethernet and IPv4, a request or
a reply; an IPv4 frame is version 4 with IHL 5 or more, 14 + TL bytes long,
not a fragment, its header checksum good, and its TCP, UDP or ICMP checksum
good (RFC 791, 768, 792, 9293; RFC 1071's sum, written out in the relay); any
other Ethernet type is bad. A bad frame is moved all the same and only
counted: the relay reports, it does not filter, and Linux behind the tap
checks every checksum again.

**Who runs it.** `tools/lispm-check` on revision 16, for every run
(`docs/lispm-check.md`, "The network"), and so `tools/tcp-check/run` (T2).

## The faults (T4)

Section 9's fault matrix, each fault drawn by one random generator seeded by
`--seed` (1 by default), in the order the frames come:

| Flag | What it does to a frame on a direction the faults take |
|---|---|
| `--loss P` | loses it, P percent of the time |
| `--duplicate P` | sends it twice, the copy 1 ms after |
| `--reorder P` | holds it 20 ms, so that the frames after it overtake it |
| `--corrupt P` | toward the band only, as section 9 has it: changes one byte inside its IPv4 datagram, the bytes from the IPv4 header to its total length, never the Ethernet header or padding; ARP is left alone |
| `--jitter MS` | delays it by a uniform 0 to MS ms, a direction's frames kept in their order (reordering is `--reorder`'s) |
| `--direction D` | which directions the faults take: `to-band`, `from-band` or `both` (the default) |
| `--inject N` | sends N Ethernet frames of other types toward the band, 0x86DD, 0x0804 and 0x8100 in turn, to the MAC address the band sends from, one after each frame the band sends; after the faults, so that none is lost |
| `--arm-on-signal` | no fault and no injection until SIGUSR2: `tools/tcp-check/run` reads the band's totals first, and a setup's cold boot runs clean |

The report's `faults` gives what was done each way (lost, duplicated,
reordered, corrupted, delayed), the frames injected and the settings, and
each direction's `resent`: the TCP segments with data, SYN or FIN that end at
or before the furthest sequence number already seen on their connection that
way, the band's resends from it and Linux's toward it (section 9: "resend
counts are reported"). `tools/lispm-check` passes `LISPM_CHECK_RELAY_FLAGS`
to the relay it starts, and `tools/tcp-check/run --faults` sets it.

`tools/fault-relay/test` checks the faults with no tap and no band: each
rate over 20,000 frames within five standard deviations, the frames lost and
sent twice equal to the counts, the changed byte inside the datagram and
nowhere else, ARP untouched, jitter within its bound and in order, the
directions, the injected frames' count, types and address, and one seed one
plan. Planted faults in the relay, each failing it: a byte changed anywhere
in the frame, a lost frame counted and sent, the injected frames counted and
not made, a corruption not counted (which also fails T4's `totals` against
the band, `tools/tcp-check/`).

## Still to come

- **The check shown to catch a bad band**: run against a muir build with T5's
  end-to-end plant "the TCP checksum not filled in", the relay must count
  bad frames. On a good band it finds none (T2), which shows only that it
  raises no false alarm.
