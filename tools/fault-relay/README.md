# The fault relay

`tools/fault-relay/relay` puts a band behind a tap of the pool: a tap of
muir-sim's `tools/quux-taps` at one end, and at the other a UNIX stream
socket that muir's `--ethernet-socket` connects to, in its plain mode (QUUX's
Ethernet contract, section 3). It is the Ethernet frame mover (muir-sim's
`tools/ethernet-frame-mover`) with the fault relay's additions: counts, and a
check of every Ethernet frame the band sends with its own code (section 9).
Python's standard library only.

```
tools/fault-relay/relay [--tap NAME[,NAME...]] [--report FILE] PATH
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

## Still to come (E5's later slices)

- **T4's faults** (section 9): loss of 1%, 5% and 20%, duplicates 5%,
  reordering 5%, one changed byte inside the IPv4 datagram of 1% of the
  frames toward the band, counted, and delay jitter of 0-50 ms, each
  direction alone and both together, from a seed; and 100 Ethernet frames of
  other types (0x86DD, 0x0804, 0x8100) injected toward the band, one after
  each frame the band sends. They go in `Relay.to_band` and `Relay.to_tap`,
  with flags named then (proposed: `--seed`, and one flag for each fault).
- **The check shown to catch a bad band**: run against a muir build with T5's
  end-to-end plant "the TCP checksum not filled in", the relay must count
  bad frames. On a good band it finds none (T2), which shows only that it
  raises no false alarm.
