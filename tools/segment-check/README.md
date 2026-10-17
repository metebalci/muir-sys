# The segment scripts

T1 of QUUX's Ethernet contract (section 9): scripted exchanges of Ethernet
frames with a band, in muir's clocked mode, written before the Lisp stack so
that each fails on a band without it. Python with the standard library only.

```
tools/segment-check/test --jobs 4                        # the scripts' own check (about 50 minutes)
tools/segment-check/run --machine standin                # every script on the stand-in band
tools/segment-check/run --machine standin --plants       # every plant against every script
tools/segment-check/run --machine standin --plants --plants-own   # quick: each plant against its own script
tools/segment-check/run --machine micro --quux EXE --band PACK --prom PROM --file-root DIR
tools/segment-check/run --machine rtl ... --scripts arp,handshake --boot-wait 10
```

`run` starts a fresh machine for each run of each script, two runs a script
(`--runs`), and a script passes only if both runs pass and the band's
Ethernet frames, with the machine time each was sent, agree bit for bit.
Each line of its report says PASS, FAIL with the reason, or ERROR when the
harness or the machine broke (the socket closed, nothing connected), which
is never counted as the band failing. The exit status is 0 when every script
passes; with `--plants`, when every plant fails the script it is meant for,
for the reason it is meant to (a plant failing only some other script counts
as ELSEWHERE, not caught), and every variant passes every script.
`--log-dir` gets a `summary` and, for each script and run, `.frames` (every
Ethernet frame the band sent, described, with its time) and `.machine` (the
machine's command line and output).

On muir the run is `quux` on revision 16 (`MUIR_QUUX_REVISION=16`) with
`--no-pace`, a fixed `--rtc` so that the band's ISN key is the same in both
runs, the pack opened read-only, and `--ethernet-socket PATH,clocked`. At
most three muir runs at once is a fair load (`--jobs`).

## The pieces

| File | What it is |
|---|---|
| `clocked.py` | The peer's side of the clocked socket (contract section 3): listen, accept muir, "run until" and "reached", the machine clock, a frame delivered at a machine time, and every frame the band sent with its time. |
| `frames.py` | Ethernet II, ARP, IPv4 with options, ICMP and TCP with options (unknown, NOP-padded, unaligned), built and parsed, with the scripts' own Internet checksum (RFC 1071). Nothing comes from muir's checksum offload. |
| `check.py` | What every script checks in every Ethernet frame the band sends: its type, its addresses, every checksum, IPv4's sent fields (IHL 5, TOS 0, DF clear, TTL 64), and TCP's options, urgent pointer, segment size and window. |
| `session.py` | What a script runs on: machine time, frames to the band, frames from it each checked, the band's ARP requests for the peer answered, and the peer's side of a TCP connection. The addresses and times (`Params`). |
| `scripts.py` | The scripts. |
| `standin.py` | The stand-in band (below). |
| `run`, `test` | The runner, and the scripts' own check. |
| `measure` | Section 15's clocked measurements, M-refill and M-ack (below, "The measurements"). |

## The scripts

Every script first waits for the band's gratuitous ARP, the network's start,
for at most `--boot-wait` seconds of machine time (120 by default), and then
goes on whether it came or not, so that on a band without the stack each
fails for its own reason. An answer is waited for `--answer` seconds of
machine time (1 by default).

| Script | It checks (contract section) | On a band without the stack it fails with |
|---|---|---|
| `arp` | One gratuitous ARP, broadcast, a request or a reply (RFC 5944 section 4.6) whose sender and target addresses are both the band's. An ARP request from the peer for another address, before the band knows the peer, adds no entry (RFC 826's merge). With 14 echo requests from the peer waiting over 3.5 s and nothing answering, no two of the band's ARP requests for the peer are less than 1 s − 1/60 s apart. Of two echo requests then waiting on one resolution, only the newer is answered once the band learns the peer (F43). A request for the band's own address gets a reply naming both sides; an ARP request from the peer for another address, from another MAC address, moves the band's next datagram to that address with no request, and back (the merge, F44); requests for the peer's address, 192.0.2.9 and the /30's broadcast get none (5.2). | no gratuitous ARP by machine time T |
| `arp-cache` | A long script, about 611 s of machine time. An echo request makes the band resolve the peer; 10 s later the peer broadcasts an ARP request for another address, which restarts the entry's 10 minutes and draws no reply. An echo request 600 s, a tick and the pass latency after the band first used the entry is answered with no ARP request (the restart); one 600 s less a tick after the refresh too; one 600 s, a tick and the pass latency after the band's first datagram after the refresh needs a new request: an entry is kept 10 minutes from the last ARP packet from its address, whatever its target, even while it is used (5.2, F42; RFC 1122 section 2.3.2.1). | no ARP request for the peer by T, with an echo request waiting |
| `arp-hold` | One echo request, nothing answering the band's ARP requests, and a second while the first is held: three requests and no fourth in the 3 s after the third (the newer datagram replaces the older and the count goes on); the peer's ARP reply, once the third has gone unanswered for the band's interval, a tick and the pass latency, draws no echo reply; the merge learns it, so the next echo request is answered with no request (5.2; F43, F44). | no ARP request for the peer by T, with an echo request waiting |
| `icmp-echo` | Four echo requests (56 data bytes; 57, odd, with id and sequence 0xffff; none; 1,472) get replies with identifier, sequence and data kept (5.4). | no echo reply to id 4660 seq 1 by T |
| `handshake` | A SYN with Linux's options gets a SYN-ACK with SYN and ACK only, acknowledging the SYN, MSS 1460 and window 8192; nothing but a SYN-ACK comes in the 300 ms the ACK is held; the banner follows the ACK, at the SYN-ACK's sequence number plus one (5.5, 7). | no SYN-ACK from port 23 by T |
| `mss` | A SYN to port 7 gets an RST-ACK of the SYN (RFC 9293 section 3.10.7.1's form, F20) while the test switch is off; the switch is turned on through the control session. Then to the test echo service (section 7, port `--echo-port`), 4,000 bytes on a connection whose SYN has no MSS come back in segments of at most 536 bytes, and on one with MSS 65480 (behind an unknown option) of at most 1,460, the largest segment exactly that size, the first transmission of the segment that ends each echo with PSH (MUST-61; a resend may carry PSH or not), and the echo exactly the bytes sent, nothing more in a quiet period; 1,073 bytes on one whose peer offers a window of 1,072, holding its ACKs until the band has been quiet 300 ms (F15), never pass the right edge (5.5; MUST-15, -16). | no RST from the closed port 7 by T |
| `other-types` | During the control session, an IPv6 and a 0x0804 Ethernet frame, each to the band's MAC address and to broadcast, get no answer; the driver's total of the type filter's count, read on the control session before and after, rises by exactly 4; and the session is not reset and, once quiet (so that the listener's own output cannot stand in for the answer), acknowledges an old duplicate byte (2.4, the type filter; 5.1; 5.5). | the control session: no SYN-ACK from port 23 by T |
| `data` | On the test echo service, after the control session's switch, on a connection whose peer ISN is 10 below 2^32 so that the data crosses the wrap: in order data is acknowledged; the same bytes again are acknowledged again; bytes 8-11 before 4-7 get a duplicate ACK; the gap resent moves the ACK to 8 only, not 12, since a segment beyond RCV.NXT is dropped; an overlap moves it by its new part only; an old segment inside the data is acknowledged. Each ACK is read where the band's segments settle (none past the expected, the last before 300 ms of quiet exactly it), and the peer acknowledges the echo with its true SND.NXT. At the end the echo is bytes 0-15, each once and in order (5.5; F18). | the control session: no SYN-ACK from port 23 by T |
| `options` | On the test echo service, as `data`: a SYN whose MSS is unaligned behind a NOP, with an unknown option, is answered; data with an unknown option and with unaligned options is acknowledged; data with a zero, a one-byte and an overlong option length is dropped: no ACK moves (a duplicate ACK is allowed), no RST; the band then takes the same bytes; the echo is bytes 0-5 once; a SYN with an overlong length is not answered and a good SYN after it is (5.5; MUST-5, -6, -7, -64; F16). | the control session: no SYN-ACK from port 23 by T |
| `checksums-received` | After a control echo, an echo with a bad IPv4 header checksum, one with a bad ICMP checksum, a SYN with a bad TCP checksum (each one bit off), an ICMP message of 4 bytes, a TCP segment of 12 and a UDP datagram whose length field is not its own get no answer, and the driver's total of the IPv4 checks' count, read on the control session, rises by exactly 6, the type filter's not at all; an echo and a SYN after them are answered (2.4, 2.4.2, 5.1, 5.3; section 9, T1, IP). | no echo reply to the control echo by T |
| `ip-options` | An echo with NOPs and a record route is answered (options skipped); one with a loose or a strict source route is not; neither is a first fragment (MF set) or a later one (offset 16), each holding a whole echo; nor an echo to the /30's broadcast or to 192.0.2.9; nor UDP or protocol 47; neither total, read on the control session, moves, since each of these passes the device (F17); an echo after them is answered (5.3). | no echo reply to the control echo by T |
| `rst` | Through the control session the test switch goes on. On an echo connection whose server waits in a read, an RST at RCV.NXT gets no answer, the service's last condition read on the control session is SYS:CONNECTION-LOST, and a SYN on the four-tuple gets a SYN-ACK; an RST 1,000 past RCV.NXT, strictly inside the window, aborts too (an old segment then gets RST); RSTs past the right edge and before RCV.NXT are ignored (it gets an ACK); an RST in SYN-RECEIVED returns to LISTEN: no SYN-ACK is resent in 1.5 s and the SYN-ACK's ACK gets RST (5.5; MUST-11, -12). | the control session: no SYN-ACK from port 23 by T |
| `syn` | A SYN in ESTABLISHED gets a challenge ACK and the session goes on; a SYN to the closed port 9 gets RST-ACK of the SYN, an ACK there an RST at its ACK number; SYNs from 255.255.255.255, the /30's broadcast, 224.0.0.1, 240.0.0.1, 0.0.0.0, 127.0.0.1 and the band's own address get nothing; of five half-open SYNs the first four get SYN-ACKs and the fifth nothing; with 7 connections and a half-open one a SYN gets RST (half-open ones count among the 8); with 4 connections and 4 half-open a SYN gets nothing (the backlog is checked first); with eight connections a ninth SYN gets RST; every refusing RST of the closed port's form (5.5; MUST-63; F20, F21). | a session: no SYN-ACK from port 23 by T |
| `close` | The peer closing first: its FIN is acknowledged, the server closes on EOF, and after both FINs the four-tuple gets RST; this case rests on F22: the server closes when its client sends EOF. The band closing first through the control session: its FIN, ours acknowledged, then TIME-WAIT (an old segment gets an ACK). Both at once: ours crosses the band's unacknowledged FIN, the band in CLOSING acknowledges it, then TIME-WAIT. Every band segment after its FIN is at the FIN's number plus one (5.5; section 9, T1, Close). | the peer closing first: no SYN-ACK from port 23 by T |
| `time-wait` | A long script, about 62 s of machine time. Four connections closed by the band first: a resent FIN on one is acknowledged, and a SYN at its final RCV.NXT less one then gets the challenge ACK and leaves the record (F24); a SYN above another's final RCV.NXT opens a new connection; on a third, probed once, TIME-WAIT is still there 60 s less a tick after our FIN, and on a fourth, probed once, gone 60 s, a tick and the pass latency after the band acknowledged it (5.5; RFC 9293 section 3.10.7.4; F23). | the control session: no SYN-ACK from port 23 by T |
| `rto` | A SYN-ACK nobody acknowledges is resent after 1 s and again after 2 s (the first RTO, doubling); on a warmed echo connection an echo nobody acknowledges is resent after 200 ms and 400 ms (the floor, doubling); Karn: X resent once and acknowledged late gives no RTT sample, so after Y, acknowledged at once, Z is resent after 200 ms again. Every time within a tick early and a tick and the pass latency late; the band resolves the peer first, so that the first SYN-ACK is not held for ARP (5.5; RFC 6298; MUST-18). | no echo reply to an echo request before the SYN by T |
| `rto-restart` | Of two segments out, the first acknowledged 100 ms after it went, the second is resent no earlier than 200 ms less a tick after that ACK and before 400 ms: the timer restarted, not run from the second's own sending (RFC 6298 section 5.3; O2). | the control session: no SYN-ACK from port 23 by T |
| `cwnd-reset` | The initial window, 3 x 536 bytes, out and none acknowledged: after the timeout one segment goes and nothing more before an ACK; after an ACK of that one, at most two (slow start from one segment); the echo then completes exactly. It rests on the band going back to SND.UNA after a timeout, which F29 states (5.5; RFC 5681 section 3.1; O2). | the control session: no SYN-ACK from port 23 by T |
| `r2` | Long, about 110 s. An echo nobody acknowledges is resent at 0.2, 0.6, 1.4 ... 51 s (from 200 ms, doubling, each within a tick); no ARP request for the peer comes before R1 = 3 retransmissions, and one comes before the fourth (MUST-20); the connection still answers 100 s less a tick after the first transmission; after 100 s and a tick the echo service's condition is SYS:HOST-STOPPED-RESPONDING, nothing more is sent (no retransmission at 102.2 s) and the four-tuple gets RST (5.5; O4). | the control session: no SYN-ACK from port 23 by T |
| `r2-hook` | About 12 s. The control session's R2 hook set to 10 s: connection A, accepted next, and B after it, each with data nobody acknowledges. A answers 10 s less a tick after its data's first transmission; 10 s, a tick and the pass latency after it the echo service saw SYS:HOST-STOPPED-RESPONDING, nothing more was resent and its four-tuple gets RST; B, with the default R2, still answers (MUST-21; 5.5; F41). | the control session: no SYN-ACK from port 23 by T |
| `zero-window` | Long, about 205-265 s. The peer offers 536 from the SYN on, so of a 1,000-byte echo 536 goes and 464 waits; the peer's ACK of the 536, on a segment of one octet that the band answers at once, brings the zero window, and the first probe comes one RTO, 200 ms, after it (its early side from the peer's segment, its late side from the band's answer), each interval then doubling to 60 s within a tick. Every band segment in the zero window must be a probe in one of F27's forms (one octet at the right edge, or no data below the peer's RCV.NXT), the peer answers each as a receiver at a zero window does and takes none of its data; no RST, no abort; after 200 s the answer to the next probe opens the window, and the 1,000 bytes come exactly (5.5; MUST-35 to -37; F27; RFC 1122 section 4.2.2.17). | the control session: no SYN-ACK from port 23 by T |
| `own-zero-window` | The band's own buffers filled (the peer's window 0, so the echo service blocks writing and stops reading): its window reaches 0; a probe without data below its RCV.NXT gets an ACK of RCV.NXT with window 0; a probe of one octet at RCV.NXT, carrying an ACK that opens the peer's window, gets the same ACK, its octet is never delivered, and its ACK is taken (data comes); as the buffer drains and then over five echoes of 300 bytes, each forward move of the band's right edge is at least the connection's effective send MSS, min(the peer's MSS, 1,460) (receiver SWS, MUST-39, F25, O2); on a second filled connection an RST at RCV.NXT is still taken (MUST-66; RFC 9293 sections 3.8.6.1 and 3.10.7.4). | the control session: no SYN-ACK from port 23 by T |
| `must-38` | MUST-38's four rules (RFC 9293 section 3.8.6.2.1) on the echo service, the peer having offered 30,000 and the 4,000 bytes queued under a zero window: with a window of 2,000, (1) a full MSS goes at once; (4) the 540 left, its edge standing still, goes at the 200 ms override: no earlier than 200 ms less a tick after the full MSS, and no later than 200 ms and twice a tick and the pass latency after the script's ACK of it, since a band may let that ACK restart the timer (F28) and takes it up to a tick and the pass latency after it arrives (F47, F50); (2) once acknowledged, the 2,000 queued go at once; (3) on a connection whose largest window is 1,000, 1,000 goes at once; and nothing passes the shrunk window. | the control session: no SYN-ACK from port 23 by T |
| `shrink` | The window shrinks left of what the band has sent: 12,000 bytes queued under the peer's zero window, 8,192 then out under a window of 30,000, and an ACK of the first 1,000 with a window of 500. No new data goes past the new right edge (old data may be resent past it, MAY-7), the connection stays, and the data goes once the edge moves on, all 12,000 echoed exactly (MUST-34, SHLD-15; 5.5; F26). | the control session: no SYN-ACK from port 23 by T |
| `isn` | Two connections on one four-tuple 1 s apart get ISNs 250,000 apart within 4,417 (the clock in 4 us units, within a tick and the pass latency's worth, `scripts.ISN_SLACK`, since the band reads the clock as it takes each SYN, up to a tick and the pass latency after it arrives); two four-tuples at one time get ISNs more than that apart either way, so that their hashes differ and not only their clock terms (5.5; RFC 6528; O2; F30; F46). | no SYN-ACK by T |
| `urgent` | On a quiet echo connection, whose server has read all it got: one octet with URG and an urgent pointer of 10 leaves 9 octets waiting, read on the control session; 8 more leave 1; the tenth none, urgent mode left (MUST-30, -31, -33, -62; F32). At the band's own zero window, a segment of one octet with URG and an urgent pointer of 10: the band's segments settle on an ACK of RCV.NXT with window 0, the data not taken, and urgent data is waiting, at least 10 octets and at most 8,202 (MUST-66, RFC 9293 section 3.4; F31, F32). | the control session: no SYN-ACK from port 23 by T |
| `synack-r2` | Long, about 181 s. Two half-open connections, A and B, B's SYN 0.5 s after A's. A's SYN-ACK, nobody acknowledging it, is resent after gaps of 1, 2, 4, 8, 16, 32 and then 60 s (the RTO's 60 s cap), each within a tick, and no more; no ARP request for the peer before its third resend and one between its third and fourth (R1, MUST-20, -22; F33). A's ACK 180 s less a tick after its first SYN-ACK completes the handshake (the banner follows); B's, 180 s, a tick and the pass latency after its own, gets LISTEN's RST, `<SEQ=SEG.ACK><CTL=RST>` (R2 for a SYN-ACK at that time, not at the next retransmission; 5.5; F31). Only A is timed, and an ARP request counts as holding a resend only when the resend follows it within the round trip and a tick. | no echo reply to an echo request before the SYNs by T |
| `rule-5-7` | A SYN-ACK resent once and then acknowledged, with no RTT sample: of a 1,072-byte echo, two segments of 536, one goes and the other waits for its ACK (an initial window of one segment, RFC 5681 section 3.1; F34); the first is resent after 3 s within a tick (RFC 6298 (5.7); F31); the echo then completes exactly. | the control session: no SYN-ACK from port 23 by T |
| `fin-wait-2` | Long, about 62 s. Two connections closed by the band first, the application's own close (F36), the peer acknowledging the band's FIN 50 ms after it and sending none back: FIN-WAIT-2 is still there 60 s less a tick after the band's FIN on one, and gone 60 s, a tick and the pass latency after it on the other, each probed once; the origin is the FIN, so a band timing from the ACK fails (F35). No RST comes on either before its end: a later close by its server sends nothing (F36). (5.5; F31.) | the control session: no SYN-ACK from port 23 by T |
| `wrap` | The control session sets the ISN hook to 0xFFFFF000; a SYN to a closed port, refused, leaves it set, and the next connection's SYN-ACK has that ISN (the next SYN answered takes it, F36); the peer's is 0xFFFFF800, and 1 MB echoed crosses both wraps exactly within 60 s of machine time (an assumed rate, which E4 measures on the Lisp); the connection after has another ISN, the hook used once (section 9, T1, Sequence wrap; F6). | the control session: no SYN-ACK from port 23 by T |
| `ping` | The band's ping, called on the control session (5.4; F5, F36). Of the peer: its echo request goes to the peer's address and passes every check of a sent Ethernet frame; the peer answers with the wrong sequence and then the wrong identifier, nothing is reported in the 300 ms after, and after the right reply the ping reports it. Of an address off the subnet: its echo request goes through the gateway, to the gateway's MAC address with no ARP request for the address (5.3, Routing), and the reply is reported. | the control session: no SYN-ACK from port 23 by T |

**What every script checks** besides its own case, in every Ethernet frame
the band sends (`check.py`, `session.py`): its type, addresses and every
checksum; its length, 42 bytes for ARP and 14 + TL for IPv4, since padding is
the host side's; IPv4's sent fields; TCP's ACK flag on every segment but an
RST, options, urgent pointer, segment size and window; that no two of the band's IPv4 datagrams in a run share a
destination, protocol and identification; and that no data goes past the
largest right edge the peer has offered. Every Ethernet frame the scripts
send shorter than 60 bytes is padded to 60 with nonzero bytes, as a NIC
delivers it.

**The control session** (a PROPOSED term) is a TELNET session of the
script's own to port 23, on which it types fixed forms at fixed machine times
and waits for a marker the form prints, never for the listener's echo
(contract section 9, T1, "The way in"). The forms are in one table,
`scripts.CONTROL`, with the band's names (package INTERNET, nickname IP:
`IP:*TEST-ECHO-SERVICE*`, `IP:TYPE-FILTER-TOTAL`, `IP:IPV4-CHECKS-TOTAL`,
`IP:TEST-ECHO-SERVICE-CONDITION`, `IP:CLOSE-CONNECTION-FROM-PORT`,
`IP:*ISN-OF-NEXT-CONNECTION*`, `IP:*R2-OF-NEXT-CONNECTION*`,
`IP:URGENT-STATE-OF-PORT` and `IP:PING`), and the stand-in answers by the
same table.
What each form does is fixed (F36): the close is the application's own,
`:CLOSE` without abort, after which a later close by the server sends
nothing; the ISN hook takes an ISN as on the wire, 0 to 2^32 - 1, and the
next SYN answered with a SYN-ACK takes it; the R2 hook takes a number of
seconds, and the next connection the test echo service accepts gets it as its
R2, through the stream's keyword (F41); the urgent state is two numbers,
waiting or not and how much (F32); the ping waits at least 1 s for the reply
matching its identifier and sequence, ignores any other, and reports that
reply's fields or nothing.

**The pass latency** (section 9, T1, Latency; F45): the most the band's
network process starts its pass after a tick, or posts a timer's segment
after its due time: 7 ms (`scripts.PASS_LATENCY`, its one place), from E4's
measurement on the band (below, "The pass latency measured"). A timer checked within a tick may be up to a tick early and up to
a tick and the pass latency late (`near()`); a probe that a record has ended
goes a tick and the pass latency after its end is due, since the record ends
in the pass at the first tick at or after that and the pass takes the waiting
Ethernet frames before the timers (section 5.1). A late side is timed from a
frame of the band's where it can be, since the band may take a frame of the
peer's later than it arrives: `zero-window` brings the zero window on one
octet, so that the band's answer times the first probe's late side, and
`rto` and `synack-r2` let the band resolve the peer first, so that the first
SYN-ACK is not held for ARP.

**The pass latency measured** (E4, on the band with the stack, revision 16,
GC on, the Lisp's timers on the microsecond clock rather than on ticks): with
`--pass-latency-ms 0 --margins`, how late each timer's segment came after the
time its check wants, by the clocked socket's times. On micro at 8.5 ns
(`rto`, `rto-restart`, `must-38`, `isn`, `arp-hold`, `r2-hook`, `rule-5-7`,
`cwnd-reset`, `arp`) at most 3.8 ms (Karn's resend; the RTOs 1.9-2.2 ms, the
5.7 RTO 3.4 ms); on micro at 63.5 ns at most 6.6 ms (the 5.7 RTO; the RTOs
3.1-5.3 ms); ARP's requests 1.0009-1.0029 s apart. `must-38`'s override, timed
from the script's ACK, came 2.2 ms late at 8.5 ns and 18.5 ms at 63.5 ns,
inside its two ticks. So 7 ms, below a tick: no amendment. Before TCP, ARP
alone gave 0.8-1.5 ms at 8.5 ns, 1.1 ms at 63.5 ns and 0.075 ms on rtl.

The pass model is three measurement variants (`standin.MEASURES`), run by
the latency sweep (below) rather than by `--plants`. All three follow section
5.1's one network process (F52): `pass-order` is woken by each Ethernet frame
and takes it 0-1 ms after it arrives, unless a timer pass starts first, which
takes every frame waiting by its start before it runs the timers; each timer
pass starts 0-1 ms after its tick, and the timers are reckoned in ticks;
`pass-clock-restart` is that with each timer restarted from the clock read in
its pass; `pass-busy` is `pass-order` with each frame taken only in the pass
of the next tick, before that pass's timers, as when another process holds
the machine. Under them the ticks sit at a seeded phase and the network
starts off the grid, so that a seed draws the phase at which the scripts'
timeline, which follows the gratuitous ARP, meets the ticks.

**The latency sweep** runs the scripts under each measurement variant in
tick timing over seeds, with `run --margins FILE`: every timer check then
writes a line to FILE instead of failing (the script, the kind of check,
what it checks, its raw figure in ns and its excess over its late bound;
`near` checks log their time less the time wanted, gone probes 1 for found
gone, and an excess above 0 is a check that would fail), and
`run --pass-latency-ms MS` sets the pass latency the checks allow in place of
`scripts.PASS_LATENCY`. A sweep is then, for each variant, seed and latency:

```
tools/segment-check/run --machine standin --runs 1 --standin-timing tick --standin-seed SEED \
    --plant pass-busy --pass-latency-ms 0 --margins sweep/pass-busy-0-SEED.margins
```

counting the lines whose excess is above 0. At 0 some gone probes and late
sides fail; at the pass latency none should.

The addresses are flags of `run` (section 3, amendment 2): tap quuxN has a
/30 of its own, the peer, also the band's gateway, at 169.254.1NN.1 and the
band at 169.254.1NN.2. The defaults are quux0's, muir's own defaults: the
band 02:00:00:00:00:01 at 169.254.100.2/30, the peer 02:00:00:00:00:02 at
169.254.100.1. Every other address a script uses (the subnet's broadcast,
an address off the subnet) is derived from these.

## The band's plants (E4)

Planted faults in the band's own stack (contract section 9, T5), each a copy
of one file of `sys/network/ip/` with one change, loaded over the stack and
saved in a band of its own, and the script meant to catch it run once on
micro (the long ones at 63.5 ns). Every one fails its script:

| Plant | Script | Its failure |
|---|---|---|
| ARP answering every request | `arp` | an ARP reply for another address |
| four ARP requests before the drop | `arp-hold` | a fourth ARP request |
| the oldest held datagram kept | `arp` | the older of two answered |
| the merge not restarting an entry's 10 minutes | `arp-cache` | the entry gone 600 s after it was learned |
| every datagram sent directly, no gateway | the ping through lispm-check | no reply off the subnet |
| sequence numbers compared without wrap (signed) | `wrap` | across 2^31: the echo stops |
| the window edge off by one | `mss` | data past the right edge |
| the sender ignoring the peer's window | `mss` | data past the right edge |
| FIN consuming no sequence number | `close` | no answer after both FINs |
| an RST accepted out of the window | `rst` | an out-of-window RST aborted |
| option parsing stopping at an unknown kind | `mss` | MSS 65480 behind an unknown option not taken |
| TIME-WAIT skipped | `close` | no TIME-WAIT |
| the RTO not doubled | `rto` | the second RTO 1 s |
| Karn's rule not applied | `rto` | Z resent late |
| the retransmit timer not restarted on an ACK | `rto-restart` | resent 100 ms after the ACK |
| the congestion window not reset on a timeout | `cwnd-reset` | 2 more segments after the timeout |
| a zero window never probed | `zero-window` | 0 probes in 200 s |
| receiver silly window avoidance off | `own-zero-window` | the window opened by 1,000 bytes |
| the override timer off | `must-38` | rule 4: nothing |
| a constant ISN | `isn` | ISNs 1 s apart differ by 0 |
| a SYN accepted from a broadcast source | `syn` | a SYN-ACK to the Ethernet broadcast |
| a default MSS of 1460 | `mss` | 1,460 data bytes with no MSS |
| fragments accepted | `ip-options` | a first fragment answered |
| IHL ignored | `ip-options` | an echo with options unanswered |
| a segment beyond RCV.NXT taken | `data` | ACK past the gap |
| the echo service not closing at EOF | `close` | no FIN at EOF |
| R2 never closing | `r2` | sent after 100 s |

The signed plant survived the first form of `wrap`, whose numbers cross only
2^32: the band holds sequence numbers as signed fixnums, whose plain order
breaks at 2^31, so `wrap` also echoes 64 KB across 2^31 (the stand-in's
`seq-signed-no-wrap`). The echo service's plant survived `close`, whose
peer-first case was the TELNET server's, so `close` also checks the echo
service at EOF.

## The stand-in band

`standin.py` plays muir's side of the clocked socket and answers as the
stack should, so that the scripts are shown right before the Lisp exists:
it connects to the peer's socket, keeps a clock of 8.5 ns edges
(`--microcycle-ns`), delivers each frame at the first edge at or after its
time, sends its own 30 us after the event plus the device's 20 us (or, with
`--timing tick`, timers on 1/60 s ticks, their output at the tick, and
answers to the peer's frames delayed by seeded amounts up to a tick, as the
Lisp's network process runs), and
answers "run until" with "reached". Behind that it has the device's filters,
ARP (the gratuitous ARP 50 ms after the start, replies only for its own
address, the merge rule, entries kept 10 minutes from the last ARP packet
from their address, one request a second with the newest datagram held
and dropped after three), IPv4 (routing through the gateway off the subnet; options skipped; source routes, fragments,
other addresses and other protocols dropped; the device's checksum checks),
ICMP echo, and TCP's passive open on the TELNET and echo ports with MSS,
window, options parsed anywhere and an illegal length dropping the segment,
in-order delivery only, MUST-38's first two rules, three
segments of initial window, an ACK for every segment and a retransmission at
1 s. Its checksum code is its own, apart from the scripts', so that one
fault in both cannot hide itself; `test` holds both to the same vectors.

Its TCP also has the close's states (CLOSE-WAIT with the server closing on
EOF, LAST-ACK, FIN-WAIT-1 and -2, CLOSING), TIME-WAIT records of 60 s apart
from the connections (a resent FIN acknowledged and the record restarted, a
SYN above the final RCV.NXT taken as a new connection, any other segment with
data acknowledged), RSTs taken anywhere in the window, challenge ACKs, the
MUST-63 sources refused, a table of 8 connections and a backlog of 4 for each
listener; R1 and R2 of 180 s for a SYN-ACK, RFC 6298's (5.7) and an
initial window of one segment after a resent SYN-ACK; FIN-WAIT-2's 60 s;
the urgent pointer kept at a zero window; the control session's ISN hook and
ping (its wait of 1 s, then a report of nothing) and R2 hook; RFC 6298's RTO (1 s first, a 200 ms floor, doubling, 60 s at most,
Karn's rule, the timer restarted by an ACK of new data), going back to
SND.UNA with one segment after a timeout and slow start after, R1's negative
advice and R2 at 100 s from the oldest unacknowledged segment's first
transmission, the persist timer, MUST-38's four rules with the 200 ms
override, an 8,192-byte receive buffer read by the echo service only while
its writes fit an 8,192-byte send buffer, and receiver silly window
avoidance. Port 7 stays closed until the control session's switch form; the control
session's forms of `scripts.CONTROL` are answered with their markers, and the
device's counts of the type filter and the IPv4 checks are kept as the
driver's totals.

`--plant NAME` (or several, comma-separated, to combine a plant with a
variant) puts one fault in (`standin.PLANTS` lists each with the script
meant to catch it and the words its reason must hold; those marked T5 are the
contract's own list, section 9, T5, where a script here can see them), and
`run --plants` counts which scripts each one fails. `standin.VARIANTS` are
right behaviours, which every script must pass, most of them choices the
contract leaves open: an ACK past SND.NXT answered with an ACK; a zero-window
probe octet that moves SND.NXT, with Linux's backoff reset by an RTT sample;
RFC 5681's equation (2) in slow start; the ISN's clock read as each SYN is
taken; the persist timer from the zero window's arrival; the override timer
restarted by an ACK that leaves the data held (F28); Linux's zero-length
probe; the gratuitous ARP's reply form; a dropped segment answered with a
duplicate ACK (F16); resends without PSH; negative advice at every
retransmission from R1 on; and each server
a process of its own (`server-process`), its output built a delay after the
stack's ACK (3 ms, or seeded up to a tick under `--timing tick`) with the ACK
of that moment, the TELNET listener echoing what it reads after MIT's opening
flush of three bytes for each IAC. Before `data` and `options` moved to the
echo service, `data` failed under that variant (exact timing) for the wrong
reason, an ACK taken from older output. `test` runs it all under both timings; its tick run uses seed 2,
whose delays put two ARP requests 0.990 s apart, inside the tick of slack.

## The measurements: `measure`

`measure` runs section 15's clocked measurements on the same harness, one
machine and one configuration a run, and prints one `RESULT` line (`FAIL`
when the band failed, `ERROR` when the harness did). Both define their
workload on the control session and time it by the band's own microsecond
clock, which is machine time.

```
measure m-refill --quux EXE --band PACK --prom PROM --file-root DIR \
        --board kria|de25|arty --rate N --coherence sweep|line-clearing \
        --workload array|small [--iterations 20] [--feed-seconds 30]
measure m-ack --engine micro|rtl ... --board kria --gc on|off [--segments 1000] [--seed 1]
measure m-ack ... --gc on|off --idle-check [--idle-seconds 10]
```

**M-refill** (section 2.5's rule). rtl at the board's revision 15 fit:
`kria` 19 ns, a cache of 64K words, `--memory-timing kria`; `de25` 22.5 ns,
16K, `de25`; `arty` 48 ns, 4K, `arty` (muir-fpga's fits of 15 Oct). The
mechanism is `MUIR_ETHERNET_COHERENCE`, which the run passes to quux. From
the timed form's typing the peer delivers 1,514-byte UDP frames to the
band's discard port at `--rate` a second of machine time, for at most
`--feed-seconds`: each passes the device's checks, moves 251 and is dropped
by the stack (`dropped=`, the band's count, says they came; `no-buffer=` the
frames the device dropped for want of a buffer). The workload conses
nothing: `array` sums a 16,384-word array (2,048 lines) `--iterations`
times, `small` runs a fixnum loop as long. `SATURATED` marks a workload that
ended only after the frames stopped: the network process, at priority 25,
had taken every cycle while they came, and the time is a lower bound.

**M-ack** (section 2.6). With the compute-bound loop at priority 0 in the
control session's listener, the collector on and a consing loop, or off and
a loop that conses nothing, `--segments` one-byte data segments go to the
test echo service at seeded random machine times (gaps of 10 to 90 ms), and
each delay is the machine time from its delivery to the band's first segment
that acknowledges it: `max`, `p99` and `mean` against 200 ms and 40 ms.
`--idle-check` instead counts the loop's iterations in `--idle-seconds` with
the network up and idle, then stopped (`ip:network-stop`), and gives how much
slower the first is, against 1%. Two experiments, not the measurement:
`--echo-priority N` puts the test echo service's process at priority N, and
`--idle-tick` keeps the clock's break every tick in the stopped loop.
`--delays`, `--frames` and `--session-log` keep each delay, every frame the
band sent and what the band sent on each connection.
