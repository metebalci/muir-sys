#!/usr/bin/env python3
"""The stand-in band: a small program that plays muir's side of the
clocked Ethernet socket and answers as QUUX's stack should, so that the
segment scripts can be shown right before the Lisp stack exists.

It connects to the peer's UNIX socket as muir does (QUUX's Ethernet
contract, section 3), keeps a machine clock on a grid of edges (8.5 ns by
default, the Kria's), delivers each Ethernet frame at the first edge at or
after its time, sends its own with their times, answers "run until" with
"reached", and waits.  Behind that is the least of section 5 the scripts of
slice 0 reach:
- the device (section 2.4): its MAC address filter, the type filter, the
  IPv4 checks, and a transmit 20 us after the previous one;
- ARP (5.2): one gratuitous ARP at the network's start, replies only for its
  own address, RFC 826's merge rule, at most one request a second for an
  address with the newest datagram held and dropped after three;
- IPv4 (5.3): options skipped by IHL, a loose or strict source route,
  a fragment, another address or another protocol dropped; ICMP echo
  (5.4);
- TCP (5.5): passive open on the TELNET port (a banner after the ACK) and on
  the echo port, MSS 1460 on the SYN-ACK, an 8,192-byte window, the send MSS
  min(the peer's, 1460) or 536, options parsed in any segment and unaligned,
  an illegal length dropping it, in-order delivery only (a segment beyond
  RCV.NXT dropped and acknowledged, an overlap's new part taken, an old
  duplicate acknowledged), segments sent by MUST-38's first two rules,
  an initial window of three segments, acknowledgment of every segment, and
  a retransmission at 1 s, doubling.

Its checksums are its own code (`csum` below), written apart from the
scripts' (frames.py) so that one fault in both cannot hide itself.

`--plant NAME` puts one fault in, for counting what the scripts catch
(PLANTS lists them).  Standard library only.
"""

import argparse
import hashlib
import heapq
import os
import random
import re
import socket
import struct
import sys

HEAD = struct.Struct('>IQ')

# Each plant: what it does, the script meant to catch it, and words its
# failure reason must hold.  `run --plants` counts a plant caught only when
# that script fails for that reason, so that a plant caught by an unrelated
# timeout proves nothing.  T5's own list (contract section 9, T5) is planted
# here where a script of slices 0, 1 and 3 can see it, marked T5.
PLANTS = {
    'ip-checksum': ('the IPv4 header checksum of every sent datagram is one off',
                    'icmp-echo', 'wrong IPv4 header checksum'),
    'tcp-checksum': ('the TCP checksum of every sent segment is one off', 'handshake', 'wrong TCP checksum'),
    'tcp-checksum-zero': ('T5: the TCP checksum not filled in (0)', 'handshake', 'wrong TCP checksum'),
    'icmp-checksum': ('the ICMP checksum of every echo reply is one off', 'icmp-echo', 'wrong ICMP checksum'),
    'synack-mss': ('the SYN-ACK offers MSS 1400, not 1460', 'mss', 'largest segment is 1400'),
    'send-mss-1400': ('with MSS 65480 from the peer the send MSS is 1400, not 1460', 'mss',
                      'largest segment is 1400 bytes, not 1460'),
    'send-mss-default': ('T5: a default MSS of 1460, not 536', 'mss', 'over 536'),
    'window': ('the advertised window is 4096, not 8192', 'handshake', 'window is 4096'),
    'synack-wscale': ('the SYN-ACK offers window scaling', 'handshake', 'TCP option 3 offered'),
    'banner-early': ('the banner is sent before the ACK', 'handshake', 'before the handshake\'s ACK'),
    'no-banner': ('the TELNET server sends no banner', 'handshake', 'no banner'),
    'arp-any': ('T5: ARP answering every request', 'arp', 'ARP sender address'),
    'arp-dropped': ('T5: ARP dropped by the device', 'arp', 'no ARP reply for the band\'s own address'),
    'garp-twice': ('two gratuitous ARPs, 2 s apart', 'arp', '2 gratuitous ARPs'),
    'arp-rate': ('ARP requests every 0.5 s', 'arp', 'more than one a second'),
    'echo-id': ('the echo reply\'s identifier is changed', 'icmp-echo', 'says id'),
    'echo-seq': ('the echo reply\'s sequence is changed when it is 0xffff', 'icmp-echo', 'seq 65534'),
    'echo-data': ('the echo reply\'s last data byte is changed', 'icmp-echo', 'changed its data'),
    'answer-ipv6': ('an IPv6 Ethernet frame is sent back', 'other-types', 'Ethernet type 0x86dd'),
    'answer-0804': ('a 0x0804 Ethernet frame makes the band announce itself again', 'other-types',
                    'an answer to an IPv6 or 0x0804'),
    'other-types-reset': ('an IPv6 Ethernet frame resets every TCP connection', 'other-types', 'reset'),
    'ipv6-passed': ('T5 end to end: an IPv6 Ethernet frame passed by the type filter (not counted)',
                    'other-types', 'type filter\'s total rose by 2'),
    'type-uncounted': ('T5 end to end: an Ethernet frame dropped by type, but not counted', 'other-types',
                       'type filter\'s total rose by 0'),
    'ttl': ('TTL 255, not 64', 'icmp-echo', 'TTL 255'),
    'df': ('DF set on every datagram', 'icmp-echo', 'DF set'),
    'pad-sent': ('every sent Ethernet frame padded to 60 bytes', 'arp', 'not 42'),
    'ident-constant': ('the IPv4 identification is always 1', 'icmp-echo', 'identification repeated'),
    'ident-copied': ('the echo reply copies the request\'s identification', 'icmp-echo',
                     'identification repeated'),
    'jitter': ('a send time that changes from run to run', 'icmp-echo', 'not deterministic'),
    'old-dup-unacked': ('an old duplicate is not acknowledged', 'data', 'the same 4 bytes again: no ACK'),
    # Slice 1: data and options.
    # (in-order data taken but not acknowledged by the stack is not a plant:
    # every server here writes back what it reads, and its output carries
    # the ACK at once, so the fault changes nothing on the wire.)
    'ooo-queued': ('a segment beyond RCV.NXT is kept and taken once the gap fills', 'data', 'ACK +12'),
    'ooo-silent': ('a segment beyond RCV.NXT is dropped without an ACK', 'data', 'out of order'),
    'overlap-whole': ('an overlapping segment is taken whole, its old part again', 'data', 'ACK +20'),
    'seq-no-wrap': ('T5: sequence numbers compared without wrap', 'data', 'ACK'),
    'length-from-frame': ('the stack takes the datagram to the Ethernet frame\'s end, not to TL', 'data',
                          'control form'),
    'bad-option-taken': ('a zero or overlong option length ends the options and the segment is taken',
                         'options', 'taken, not dropped'),
    'unknown-option-drop': ('a segment with an unknown option is dropped', 'options',
                            'a SYN with unaligned options: no SYN-ACK'),
    'option-stop-unknown': ('T5: option parsing stopping at an unknown kind', 'mss',
                            'largest segment is 536 bytes, not 1460'),
    'nop-illegal': ('a NOP option drops the segment', 'options', 'no SYN-ACK'),
    'window-ignored': ('T5: the sender ignoring the peer\'s window', 'mss', 'past the right edge'),
    'window-edge-off-by-one': ('T5: the window edge off by one', 'mss', 'past the right edge'),
    'echo-port-open': ('the echo service open before its switch', 'mss', 'port 7 open before the test switch'),
    # Slice 3: IP and checksums received.
    'ip-checksum-unchecked': ('T5 end to end: a bad Ethernet frame delivered (IPv4 header checksum)',
                              'checksums-received', 'bad IPv4 header checksum answered'),
    'icmp-checksum-unchecked': ('a bad ICMP checksum is not dropped', 'checksums-received',
                                'bad ICMP checksum answered'),
    'tcp-checksum-unchecked': ('a bad TCP checksum is not dropped', 'checksums-received',
                               'bad TCP checksum answered'),
    'ipv4-uncounted': ('the IPv4 checks drop but do not count', 'checksums-received',
                       'IPv4 checks\' total rose by 0'),
    'padding-summed': ('T5: Ethernet padding summed in the device\'s checks', 'icmp-echo',
                       'no echo reply to id 0 seq 0'),
    'ihl-ignored': ('T5: IHL ignored, the payload taken at byte 20', 'ip-options',
                    'NOPs and a record route'),
    'options-dropped': ('a datagram with any IPv4 option is dropped', 'ip-options', 'NOPs and a record route'),
    'source-route-taken': ('a loose or strict source route is taken', 'ip-options', 'source route answered'),
    'fragment-taken': ('T5: fragments accepted (a first fragment, MF set)', 'ip-options',
                       'first fragment (MF set) holding a whole echo answered'),
    'later-fragment-taken': ('a later fragment (offset not 0, MF clear) is taken', 'ip-options',
                             'later fragment'),
    'other-address-taken': ('a datagram to any address is taken', 'ip-options', 'answered'),
    'udp-answered': ('a UDP datagram is answered with ICMP port unreachable', 'ip-options', 'ICMP type 3'),
    # Slice 2: RST, SYN and close.
    'rst-out-of-window-accepted': ('T5: an RST accepted out of the window', 'rst',
                                   'an out-of-window RST aborted'),
    'rst-exact-only': ('only an RST at RCV.NXT is taken (RFC 5961), one inside the window challenged', 'rst',
                       'strictly inside the window'),
    'rst-synrcvd-ignored': ('an RST in SYN-RECEIVED is ignored', 'rst', 'SYN-RECEIVED'),
    'rst-no-signal': ('the echo service sees EOF, not the error, after an RST', 'rst',
                      'not SYS:CONNECTION-LOST'),
    'syn-estab-reset': ('a SYN in ESTABLISHED resets the connection', 'syn', 'not a challenge ACK'),
    'syn-from-broadcast': ('T5: a SYN accepted from a broadcast source', 'syn', 'SYN from 255.255.255.255 answered'),
    'closed-port-silent': ('a closed port answers nothing', 'syn', 'closed port 9'),
    'table-9': ('a table of 9 connections', 'syn', 'ninth connection'),
    'backlog-5': ('a backlog of 5', 'syn', 'fifth half-open'),
    'backlog-rst': ('a SYN past the backlog gets RST, not dropped', 'syn', 'fifth half-open'),
    'fin-no-seq': ('T5: FIN consuming no sequence number', 'close', 'the peer closing first'),
    'eof-no-close': ('the server does not close on EOF (F22)', 'close', 'the peer closing first: no FIN from the band'),
    'closing-broken': ('a FIN in FIN-WAIT-1 crossing ours is ignored', 'close', 'CLOSING'),
    'time-wait-skipped': ('T5: TIME-WAIT skipped', 'close', 'no TIME-WAIT'),
    'time-wait-30': ('TIME-WAIT of 30 s', 'time-wait', 'TIME-WAIT ended before 60 s'),
    'tw-fin-unacked': ('a resent FIN in TIME-WAIT not acknowledged', 'time-wait', 'our FIN resent'),
    'tw-syn-refused': ('a SYN above RCV.NXT in TIME-WAIT gets a challenge ACK', 'time-wait',
                       'a SYN above its final RCV.NXT'),
    # The slices 0-3 review.
    'dup-delivered': ('a duplicate is delivered to the server again', 'data', 'the echo service got'),
    'overlap-old-delivered': ('an overlap\'s old part is delivered again', 'data', 'the echo service got'),
    'rst-no-ack': ('a refusing RST without ACK (F20)', 'mss', 'not RST-ACK of the SYN'),
    'data-without-ack': ('data segments sent without ACK', 'handshake', 'without ACK'),
    'length-rules-off': ('the device ignores section 2.4.2\'s lengths for the checked protocols',
                         'checksums-received', 'not by the 6 bad ones'),
    'table-first': ('the table checked before the backlog (F21)', 'syn', 'the backlog is checked first'),
    'half-open-uncounted': ('half-open connections not counted among the 8 (F21)', 'syn',
                            'past 7 and a half-open one'),
    'tw-syn-low-accepted': ('a SYN at or below RCV.NXT in TIME-WAIT opens a connection (F24)', 'time-wait',
                            'at or below its final RCV.NXT'),
    # Slice 4: retransmission, windows and MUST-38.
    'first-rto-3s': ('the first RTO 3 s, not 1 s', 'rto', 'the first RTO'),
    'rto-floor-1s': ('the RTO floor RFC 6298\'s 1 s, not 200 ms', 'rto', 'the 200 ms floor'),
    'rto-no-double': ('T5: the RTO not doubled', 'rto', 'the RTO doubled'),
    'karn-off': ('T5: Karn\'s rule not applied (a sample from a resent segment)', 'rto', 'Karn: Z resent'),
    'timer-no-restart': ('T5: the retransmit timer not restarted on an ACK', 'rto-restart', 'the timer restarted'),
    'cwnd-not-reset': ('T5: the congestion window not reset on a timeout', 'cwnd-reset', 'after the timeout'),
    'r1-no-arp': ('no negative advice after R1: the ARP entry kept (MUST-20)', 'r2', 'no ARP request'),
    'r2-at-timer': ('R2 checked only when the timer runs out, closing at 102.2 s, not 100 s (O4)', 'r2',
                    'HOST-STOPPED-RESPONDING'),
    'r2-no-signal': ('R2 closes, but the stream signals nothing', 'r2', 'HOST-STOPPED-RESPONDING'),
    'persist-off': ('T5: a zero window never probed', 'zero-window', 'probes in 200 s'),
    'persist-no-backoff': ('zero-window probes without backoff', 'zero-window', 'zero-window probe 2'),
    'zero-window-abort': ('a zero window probed for 60 s, then the connection aborted', 'zero-window',
                          'zero-window probe'),
    'ack-ignored-at-zero-window': ('an ACK not processed at the band\'s own zero window (MUST-66)',
                                   'own-zero-window', 'was not processed'),
    'rst-ignored-at-zero-window': ('an RST at RCV.NXT not taken at the band\'s own zero window (MUST-66)',
                                   'own-zero-window', 'RST at RCV.NXT at the band'),
    'receiver-sws-off': ('T5: receiver silly window avoidance off', 'own-zero-window', 'less than one MSS'),
    'rule1-off': ('MUST-38 rule 1 off: a full MSS waits', 'must-38', 'rule 1'),
    'rule3-off': ('MUST-38 rule 3 off: half the largest window waits', 'must-38', 'rule 3'),
    'override-off': ('T5: the override timer off', 'must-38', 'rule 4'),
    'smaller-window-ignored': ('a smaller window value ignored, the old one kept', 'must-38',
                               'past the shrunk window'),
    'own-probe-unanswered': ('a probe without data below RCV.NXT not answered at the band\'s zero window',
                             'own-zero-window', 'a probe without data'),
    'constant-isn': ('T5: a constant ISN', 'isn', 'two ISNs on one four-tuple'),
    'isn-no-clock': ('the ISN without its clock term', 'isn', 'two ISNs on one four-tuple'),
    'isn-no-tuple': ('the ISN\'s hash without the four-tuple', 'isn',
                     'within a tick and the pass latency\'s worth'),
    'isn-no-tuple-clock': ('the ISN\'s hash without the four-tuple, its clock read as each SYN is taken (F30)',
                           'isn', 'within a tick and the pass latency\'s worth'),
    'rule2-off': ('MUST-38 rule 2 off: all queued that fits waits', 'must-38', 'rule 2'),
    'r1-early': ('the ARP entry dropped after 2 retransmissions, not R1 = 3', 'r2', 'before R1'),
    'shrink-old-edge-kept': ('the old right edge kept past a shrink (MUST-34)', 'shrink', 'past the shrunk window'),
    'usable-unsigned': ('the usable window taken without its sign (MUST-34)', 'shrink', 'past the shrunk window'),
    # Slice 5.
    'urg-ignored-at-zero-window': ('URG not processed at the band\'s own zero window (MUST-66)', 'urgent',
                                   'URG at the band'),
    'rto-cap-120': ('the RTO capped at 120 s, not 60 s', 'synack-r2', 'the RTO capped at 60 s'),
    'synack-r2-100': ('R2 for a SYN-ACK 100 s, not 180 s', 'synack-r2', 'resent'),
    'no-rule-5-7': ('RFC 6298 (5.7) not applied: data after a resent SYN-ACK at the 1 s RTO', 'rule-5-7',
                    'RFC 6298 (5.7)'),
    'fin-wait-2-forever': ('FIN-WAIT-2 never times out', 'fin-wait-2', 'still there'),
    'fin-wait-2-30': ('FIN-WAIT-2 of 30 s, not 60 s', 'fin-wait-2', 'ended before'),
    'isn-hook-ignored': ('the ISN hook not used', 'wrap', 'the ISN hook was not used'),
    'isn-hook-sticky': ('the ISN hook used twice', 'wrap', 'the ISN hook used twice'),
    'ping-takes-any-reply': ('the band\'s ping reports a reply of another sequence', 'ping',
                             'before the reply matching'),
    'no-psh': ('no PSH on the last segment of a push (MUST-61)', 'mss', 'MUST-61'),
    # Slice 5b.
    'synack-r2-150': ('R2 for a SYN-ACK 150 s, not 180 s', 'synack-r2', 'before 180 s less a tick'),
    'synack-r2-at-timer': ('R2 for a SYN-ACK checked only when the timer runs out, closing at 183 s', 'synack-r2',
                           'not LISTEN\'s RST'),
    'synack-r1-no-arp': ('no negative advice after R1 on a SYN-ACK\'s resends (MUST-20, -22; F33)', 'synack-r2',
                         'no ARP request for the peer between the SYN-ACK'),
    'ping-seq-only': ('the band\'s ping matches replies by sequence only', 'ping', 'before the reply matching'),
    'ping-reports-request': ('the band\'s ping takes any reply and reports its own request\'s fields', 'ping',
                             'before the reply matching'),
    'no-gateway-route': ('a datagram off the subnet sent directly, not through the gateway (section 5.3)', 'ping',
                         'not the gateway'),
    'urgent-last-octet': ('the urgent pointer taken as the last urgent octet (RFC 1122; MUST-62)', 'urgent',
                          'one octet with an urgent pointer of 10 read'),
    'urgent-received-only': ('the urgent amount counting only octets received (F32)', 'urgent',
                             'one octet with an urgent pointer of 10 read'),
    'urgent-mode-kept': ('urgent mode never left once the pointer is read past', 'urgent', 'the tenth read'),
    'urgent-zero-window-from-start': ('the urgent amount counted from the stream\'s start at the zero window',
                                      'urgent', 'at most 8,202'),
    'iw3-after-synack-resend': ('an initial window of 3 x MSS after a resent SYN-ACK (RFC 5681 section 3.1; F34)',
                                'rule-5-7', 'F34'),
    'fin-wait-2-from-ack': ('FIN-WAIT-2 timed from the peer\'s ACK of the band\'s FIN, not the FIN (F35)',
                            'fin-wait-2', 'still there'),
    'close-then-abort': ('the server\'s later close of a stream the band closed sends RST (F36)', 'fin-wait-2',
                         'a later close by its server sends nothing'),
    'isn-hook-consumed-by-refused': ('the ISN hook taken by a refused SYN (F36)', 'wrap', 'after a refused one'),
    'arp-cache-forever': ('ARP entries never time out (section 5.2)', 'arp-cache', 'still used'),
    'arp-cache-300': ('ARP entries kept 5 minutes, not 10', 'arp-cache', 'restarted its 10 minutes'),
    'arp-cache-refresh-on-use': ('an ARP entry\'s 10 minutes restarted by each use (RFC 1122 section 2.3.2.1: '
                                 '"even if they are in use")', 'arp-cache', 'still used'),
    # Slice 6.
    'r2-hook-ignored': ('R2\'s keyword ignored: the R2 hook\'s connection closes at 100 s (MUST-21; F41)', 'r2-hook',
                        'R2 of 10 s by the keyword'),
    'r2-hook-sticky': ('the R2 hook kept for every later connection (F41)', 'r2-hook',
                       'the hook used for more than one'),
    'arp-merge-no-restart': ('RFC 826\'s merge updating an entry without restarting its 10 minutes (F42)',
                             'arp-cache', 'restarted its 10 minutes'),
    'arp-learn-any': ('an ARP entry added from any ARP packet, not only one for the band (F44)', 'arp',
                      'not for the band (RFC 826'),
    'arp-merge-untargeted-ignored': ('an ARP packet for another address not updating the entry (F44)', 'arp',
                                     'the MAC address the peer'),
    'arp-older-held': ('the older datagram held, not the newer (F43)', 'arp', 'not the newer alone'),
    'arp-count-restarted': ('a newer held datagram restarting the count of requests: a fourth request (F43)',
                            'arp-hold', 'a fourth ARP request'),
    'arp-late-reply-sends': ('the held datagram kept after the third request and sent on a late reply (F43)',
                             'arp-hold', 'the held datagram is dropped by then'),
}

# Measurement variants: right behaviours run by the pass-latency sweep, not
# by `run --plants`: they measure how late a pass can be against T1's
# allowance for a late timer (F45; section 9, T1, Latency), so their
# failures are counted, not required to be none.
MEASURES = {
    'pass-order': 'in tick mode, the network process woken by each Ethernet frame and taking it a seeded 0-1 ms '
                  'after it arrives (the pass latency), answering at once and arming its timers from then; each '
                  'timer pass a seeded 0-1 ms after its tick, the frames waiting by then handled first (section 5.1)',
    'pass-clock-restart': 'pass-order, and each timer restarted from the clock read in its pass, not from its tick',
    'pass-busy': 'pass-order, each frame taken up to a tick and the pass latency after it arrives, as when another '
                 'process holds the machine until the next tick',
}

# Variants: right behaviours the scripts must pass.
VARIANTS = {
    # What the contract leaves open (the slice 4 review): each a right band.
    'ack-past-snd-nxt-acked': 'an ACK past SND.NXT answered with an ACK and dropped (RFC 9293 section 3.10.7.4)',
    'probe-moves-snd-nxt': 'a zero-window probe octet sent as new data, moving SND.NXT, with Linux\'s backoff '
                           'reset by a valid RTT sample',
    'cwnd-abc': 'slow start by RFC 5681\'s equation (2), cwnd += min(N, SMSS)',
    'isn-clock-at-take': 'the ISN\'s clock read as each SYN is taken, 100 us apart in one pass',
    'persist-from-zero-window': 'the persist timer from the zero window\'s arrival (SHLD-29 read so)',
    'override-restart-on-ack': 'the override timer restarted by an ACK that leaves the data held (F28 leaves it free)',
    'garp-reply': 'the gratuitous ARP in RFC 5944\'s reply form, broadcast',
    'dup-ack-on-drop': 'a segment with an illegal option length dropped and answered with a duplicate ACK (F16)',
    'zero-length-probe': 'zero-window probes of no data at SND.UNA - 1, as Linux sends them, '
                         'not one octet of new data',
    'server-process': 'each server a process of its own, its output later than the ACK and carrying the ACK '
                      'of its moment; the listener echoing what it reads',
    # Slice 5b.
    'resend-no-psh': 'resent segments without PSH (whether a resend carries it is free)',
    'r1-every-resend': 'negative advice at every retransmission from R1 on (RFC 9293 section 3.8.3 (b), "reaches '
                       'or exceeds")',
}

ETH_IPV4, ETH_ARP = 0x0800, 0x0806
SYN, FIN, RST, PSH, ACK, URG = 0x02, 0x01, 0x04, 0x08, 0x10, 0x20
MS, S = 1_000_000, 1_000_000_000
BCAST = b'\xff' * 6


class Plants(str):
    """--plant's names, comma-separated, so that a plant and a variant can
    be combined: == and != test whether a name is among them."""

    def __new__(cls, text):
        o = str.__new__(cls, text or '')
        o.names = {n for n in (text or '').split(',') if n}
        return o

    def __eq__(self, other):
        return other in self.names if isinstance(other, str) else NotImplemented

    def __ne__(self, other):
        r = self.__eq__(other)
        return r if r is NotImplemented else not r

    __hash__ = str.__hash__

    def __bool__(self):
        return bool(self.names)


def csum(data):
    """The Internet checksum, the stand-in's own: 16-bit words summed with
    struct, folded, complemented."""
    if len(data) % 2:
        data = data + b'\0'
    total = sum(struct.unpack('>%dH' % (len(data) // 2), data))
    total = (total >> 16) + (total & 0xFFFF)
    total += total >> 16
    return ~total & 0xFFFF


def mac(t):
    return bytes(int(x, 16) for x in t.split(':'))


def ip4(t):
    return bytes(int(x) for x in t.split('.'))


def seq_lt(a, b):
    return ((a - b) & 0xFFFFFFFF) > 0x7FFFFFFF


class Conn:
    def __init__(self, key, irs, iss, mss, window, port):
        self.key, self.port = key, port
        self.irs, self.iss = irs, iss
        self.rcv_nxt = (irs + 1) & 0xFFFFFFFF
        self.snd_una = iss
        self.snd_nxt = (iss + 1) & 0xFFFFFFFF
        self.mss = mss
        self.peer_window = window
        self.state = 'SYN-RECEIVED'
        self.buf = b''          # sent and unacknowledged, then unsent
        self.cwnd = 3 * mss
        self.ssthresh = 65535
        self.max_wnd = window   # the largest window the peer has offered
        self.max_sent = self.snd_nxt    # the end of the furthest byte sent
        # RFC 6298: the first RTO 1 s, then SRTT and RTTVAR; the backoff
        # doubles it on each timeout and an ACK of new data clears it.
        self.srtt = self.rttvar = None
        self.rto_base = 1 * S    # (set again by Band for the first-rto-3s plant)
        self.backoff = 0
        self.retries = 0        # timeouts in a row, for R1
        self.timed = None       # (end, sent): the one segment being timed
        self.first_tx = []      # [(end, time first sent)], for Karn and R2
        self.synack_tx = None
        self.rbuf = b''         # received, not yet read by the server
        self.adv_edge = None    # the right edge last advertised
        self.persist = None     # the persist timer's generation, when running
        self.persist_backoff = 0
        self.override = None    # the override timer's generation, when running
        self.r2_gen = 0
        self.timer = None       # (time, generation)
        self.ooo = {}           # the ooo-queued plant's store
        self.close_req = False  # the server closes: a FIN once the data is out
        self.fin_seq = None     # our FIN's sequence number, once sent
        self.gen = 0


class Band:
    def __init__(self, a, out):
        self.a = a
        self.plant = a.plant
        if self.plant == 'isn-no-tuple-clock':
            # Both at once: the hash without the four-tuple, the clock read
            # as each SYN is taken.
            self.plant = Plants(a.plant + ',isn-no-tuple,isn-clock-at-take')
        self.mac, self.ip = mac(a.mac), ip4(a.ip)
        self.mask = (0xFFFFFFFF << (32 - a.prefix)) & 0xFFFFFFFF
        self.gw = ip4(a.gateway)
        self.out = out          # emit(t, frame)
        self.arp = {}           # ip -> mac
        self.arp_gen = {}       # ip -> the generation of its entry's 10 minutes
        self.pending = {}       # ip -> [held datagram, requests, last time]
        self.conns = {}
        self.ident = 0
        self.key = hashlib.sha256(b'stand-in key %d' % a.rtc).digest()
        self.timers = []        # heap of (t, n, fn)
        self.n = 0
        self.tick = False       # timers on 1/60 s ticks (--timing tick)
        self.in_timer = False
        self.late = 0           # the timer pass's lateness (the pass-order variant)
        self.echo_on = self.plant == 'echo-port-open'
        self.type_total = 0     # status 241 <7:4>'s total, the driver's
        self.ipv4_total = 0     # <15:9>'s
        self.timewait = {}      # key -> TIME-WAIT record
        self.next_isn = None    # the control session's ISN hook
        self.next_r2 = None     # and its R2 hook, in seconds
        self.ping = None        # (ident, seq, control connection) awaiting a reply
        self.ping_seq = 0
        self.echo_condition = None   # the last condition the echo service saw
        # The control session's forms, from scripts.CONTROL: each a
        # template whose %d arguments become numbers to match.
        self.forms = []
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import scripts
        for name, (form, _) in scripts.CONTROL.items():
            text = form.replace('%%', '\x01').replace('%d', '\x02').replace('\x01', '%')
            pattern = re.escape(text.encode() + b'\r').replace(b'\x02', rb'(\d+)')
            self.forms.append((re.compile(pattern), name))

    def lt(self, a, b):
        """A before B modulo 2^32; the seq-no-wrap plant compares plainly."""
        return a < b if self.plant == 'seq-no-wrap' else seq_lt(a, b)

    # ---- timers ------------------------------------------------------------
    def at(self, t, fn):
        if self.tick:
            # The first tick boundary at or after T, a tick being 1/60 s.
            # (A time already on a boundary, which is a rounded 1/60 s,
            # stays there.)
            k = -(-(t * 60 - 59) // S)
            t = -(-k * S // 60)
        self.n += 1
        # With the pass-order variant the timer pass of a tick starts a
        # seeded 0-1 ms after it, and every Ethernet frame delivered by then
        # is handled first (section 5.1: frames, then timers).  The timers
        # are reckoned in ticks, so FN still gets the tick's time, and its
        # output goes LATE after it.
        late = self.pass_late(t) if self.tick and self.plant == 'pass-order' else 0
        heapq.heappush(self.timers, (t + late, self.n, fn, t, late))

    def pass_late(self, t):
        h = hashlib.sha256(b'pass %d %d' % (self.a.seed, t)).digest()
        return int.from_bytes(h[:4], 'big') % MS

    def start(self):
        self.at(self.a.boot_ns, self.gratuitous)
        if self.plant == 'garp-twice':
            self.at(self.a.boot_ns + 2 * S, self.gratuitous)

    def gratuitous(self, t):
        if self.plant == 'garp-reply':
            body = self.arp_body(2, self.mac, self.ip, self.mac, self.ip)
        else:
            body = self.arp_body(1, self.mac, self.ip, b'\0' * 6, self.ip)
        self.out(t, BCAST + self.mac + struct.pack('>H', ETH_ARP) + body)

    # ---- frames in ---------------------------------------------------------
    def receive(self, t, f):
        """The device (section 2.4): the MAC address filter, the type filter
        counted in <7:4>, the IPv4 checks counted in <15:9>; then the stack."""
        if len(f) < 14:
            return
        dst, src, typ = f[:6], f[6:12], struct.unpack('>H', f[12:14])[0]
        if dst != self.mac and dst != BCAST:
            return
        if typ not in (ETH_IPV4, ETH_ARP):
            if not (self.plant == 'ipv6-passed' and typ == 0x86DD) and self.plant != 'type-uncounted':
                self.type_total += 1
            if typ == 0x86DD:
                if self.plant == 'answer-ipv6':
                    self.out(t, src + self.mac + f[12:14] + f[14:])
                if self.plant == 'other-types-reset':
                    for c in list(self.conns.values()):
                        self.send_tcp(t, c, RST | ACK, b'', c.snd_nxt)
                        del self.conns[c.key]
            if typ == 0x0804 and self.plant == 'answer-0804':
                self.gratuitous(t)
            return
        if typ == ETH_ARP:
            if self.plant != 'arp-dropped':
                self.receive_arp(t, f[14:])
            return
        if not self.ipv4_checks(f):
            if self.plant != 'ipv4-uncounted':
                self.ipv4_total += 1
            return
        self.receive_ip(t, f[14:] if self.plant == 'length-from-frame' else f[14:14 + self.tl(f)])

    def tl(self, f):
        return struct.unpack('>H', f[16:18])[0]

    def ipv4_checks(self, f):
        """Well-formed (n >= 34, version 4, IHL >= 5, H <= TL, 14 + TL <= n),
        a right header checksum, and for TCP, UDP and ICMP not in a fragment
        a right checksum over TL's bytes (section 2.4)."""
        n = len(f)
        if n < 34 or f[14] >> 4 != 4 or f[14] & 15 < 5:
            return False
        h, total = 4 * (f[14] & 15), self.tl(f)
        if h > total or 14 + total > n:
            return False
        d = f[14:] if self.plant == 'padding-summed' else f[14:14 + total]
        if csum(d[:h]) != 0 and self.plant != 'ip-checksum-unchecked':
            return False
        if struct.unpack('>H', d[6:8])[0] & 0x3FFF:
            return True         # a fragment: only its header is checked
        proto, body = d[9], d[h:]
        # Section 2.4.2's lengths for the checked protocols.
        if self.plant != 'length-rules-off':
            if proto == 6 and len(body) < 20 or proto == 1 and len(body) < 8:
                return False
            if proto == 17 and (len(body) < 8 or struct.unpack('>H', body[4:6])[0] != len(body)):
                return False
        if proto == 1 and csum(body) != 0 and self.plant != 'icmp-checksum-unchecked':
            return False
        if proto in (6, 17):
            if proto == 17 and len(body) >= 8 and body[6:8] == b'\0\0':
                return True     # UDP's 0: no checksum
            pseudo = d[12:20] + bytes([0, proto]) + struct.pack('>H', len(body))
            if csum(pseudo + body) != 0 and not (proto == 6 and self.plant == 'tcp-checksum-unchecked'):
                return False
        return True

    def arp_body(self, op, sha, spa, tha, tpa):
        return struct.pack('>HHBBH', 1, ETH_IPV4, 6, 4, op) + sha + spa + tha + tpa

    def receive_arp(self, t, b):
        if len(b) < 28 or struct.unpack('>HHBB', b[:6]) != (1, ETH_IPV4, 6, 4):
            return
        op = struct.unpack('>H', b[6:8])[0]
        sha, spa, tpa = b[8:14], b[14:18], b[24:28]
        merged = False
        if spa in self.arp and not (self.plant == 'arp-merge-untargeted-ignored' and tpa != self.ip):
            # RFC 826's merge: the entry updated, and its 10 minutes restarted
            # (F42; the arp-merge-no-restart plant updates it only).
            if self.plant == 'arp-merge-no-restart':
                self.arp[spa] = sha
            else:
                self.learn(t, spa, sha)
            merged = True
        if self.plant == 'arp-learn-any' and not merged and spa != self.ip:
            self.learn(t, spa, sha)     # an entry added from any ARP packet
            merged = True
        if tpa == self.ip or self.plant == 'arp-any':
            if not merged and tpa == self.ip:
                self.learn(t, spa, sha)
            if op == 1:
                self.out(t, sha + self.mac + struct.pack('>H', ETH_ARP) +
                         self.arp_body(2, self.mac, tpa, sha, spa))
        if spa in self.arp and spa in self.pending:
            held = self.pending.pop(spa)[0]
            if held is not None:
                self.out(t, self.arp[spa] + self.mac + struct.pack('>H', ETH_IPV4) + held)

    def learn(self, t, ip, hw):
        """An entry learned or refreshed by an ARP packet (RFC 826's merge):
        kept 10 minutes from then, even while it is used (section 5.2; RFC
        1122 section 2.3.2.1, "periodically time out cache entries, even if
        they are in use", the timeout restarted when the entry is refreshed
        by an ARP packet from the host)."""
        self.arp[ip] = hw
        g = self.arp_gen[ip] = self.arp_gen.get(ip, 0) + 1
        if self.plant == 'arp-cache-forever':
            return
        life = 300 * S if self.plant == 'arp-cache-300' else 600 * S

        def expire(tt, ip=ip, g=g):
            if self.arp_gen.get(ip) == g:
                self.arp.pop(ip, None)
        self.at(t + life, expire)

    def receive_ip(self, t, d):
        """The stack's IPv4 (section 5.3): the device has checked it."""
        if len(d) < 20:
            return
        h = 20 if self.plant == 'ihl-ignored' else 4 * (d[0] & 15)
        if d[16:20] != self.ip and self.plant != 'other-address-taken':
            return
        flags = struct.unpack('>H', d[6:8])[0]
        if flags & 0x3FFF and not (self.plant == 'fragment-taken' and flags & 0x1FFF == 0) \
                and not (self.plant == 'later-fragment-taken' and not flags & 0x2000):
            return              # a fragment
        opts = d[20:4 * (d[0] & 15)]
        if opts.strip(b'\0') and self.plant == 'options-dropped':
            return
        i = 0
        while i < len(opts):
            k = opts[i]
            if k == 0:
                break
            if k == 1:
                i += 1
                continue
            if k in (131, 137) and self.plant != 'source-route-taken':
                return          # a source route
            if i + 1 >= len(opts) or opts[i + 1] < 2:
                return
            i += opts[i + 1]
        proto, src, body = d[9], d[12:16], d[h:]
        if proto == 1:
            self.receive_icmp(t, src, body, d[4:6])
        elif proto == 6 and len(body) >= 20:
            self.receive_tcp(t, src, body)
        elif proto == 17 and self.plant == 'udp-answered':
            r = struct.pack('>BBHI', 3, 3, 0, 0) + d[:h + 8]
            self.send_ip(t, src, 1, r[:2] + struct.pack('>H', csum(r)) + r[4:])

    # ---- frames out --------------------------------------------------------
    def send_ip(self, t, dst, proto, body, ident=None):
        self.ident = (self.ident + 1) & 0xFFFF
        if self.plant == 'ident-constant':
            self.ident = 1
        ttl = 255 if self.plant == 'ttl' else self.a.ttl
        flags = 0x4000 if self.plant == 'df' else 0
        idn = self.ident if ident is None else struct.unpack('>H', ident)[0]
        hdr = struct.pack('>BBHHHBBH4s4s', 0x45, 0, 20 + len(body), idn, flags, ttl, proto, 0,
                          self.ip, dst)
        c = csum(hdr)
        if self.plant == 'ip-checksum':
            c ^= 1
        d = hdr[:10] + struct.pack('>H', c) + hdr[12:] + body
        # Routing (section 5.3): on the subnet directly, any other through the
        # gateway; the no-gateway-route plant sends every datagram directly.
        hop = dst if self.same_subnet(dst) or self.plant == 'no-gateway-route' else self.gw
        if hop in self.arp:
            if self.plant == 'arp-cache-refresh-on-use':
                self.learn(t, hop, self.arp[hop])
            self.out(t, self.arp[hop] + self.mac + struct.pack('>H', ETH_IPV4) + d)
            return
        p = self.pending.get(hop)
        if p is None:
            self.pending[hop] = [d, 0, None]
            self.resolve(t, hop)
        elif self.plant == 'arp-older-held':
            pass                # the older datagram kept
        else:
            # The newest datagram is held, replacing the older, and the count
            # of requests goes on (F43); the arp-count-restarted plant starts
            # it again.
            p[0] = d
            if self.plant == 'arp-count-restarted':
                p[1] = 0

    def resolve(self, t, hop):
        p = self.pending.get(hop)
        if p is None:
            return
        gap = S // 2 if self.plant == 'arp-rate' else S
        if p[1] >= 3:
            # The third request unanswered as long as the band waits between
            # requests: the held datagram drops and no fourth goes (F43).  The
            # arp-late-reply-sends plant keeps it for a late reply.
            if p[2] is not None and t - p[2] < gap:
                return
            if self.plant == 'arp-late-reply-sends':
                return
            del self.pending[hop]
            return
        if p[2] is not None and t - p[2] < gap:
            return
        p[1] += 1
        p[2] = t
        self.out(t, BCAST + self.mac + struct.pack('>H', ETH_ARP) +
                 self.arp_body(1, self.mac, self.ip, b'\0' * 6, hop))
        self.at(t + gap, lambda tt, hop=hop: self.resolve(tt, hop))

    # ---- ICMP --------------------------------------------------------------
    def receive_icmp(self, t, src, m, ident_in=None):
        if len(m) >= 8 and m[0] == 0 and self.ping is not None:
            ident, seq = struct.unpack('>HH', m[4:8])
            want_id, want_seq, c = self.ping
            if self.plant == 'ping-takes-any-reply' or self.plant == 'ping-reports-request' or \
                    (self.plant == 'ping-seq-only' and seq == want_seq) or (ident, seq) == (want_id, want_seq):
                # It matches replies by identifier and sequence (the plants:
                # any reply; by sequence only; any reply, reporting the
                # request's own fields).
                self.ping = None
                if self.plant == 'ping-reports-request':
                    ident, seq = want_id, want_seq
                c.buf += ('\r\n{sc-pinged %d %d}\r\n' % (ident, seq)).encode()
                self.output(t, c)
            return
        if len(m) < 8 or m[0] != 8:
            return
        ident, seq = struct.unpack('>HH', m[4:8])
        data = m[8:]
        if self.plant == 'echo-id':
            ident ^= 0x0100
        if self.plant == 'echo-seq' and seq == 0xFFFF:
            seq = 0xFFFE
        if self.plant == 'echo-data' and data:
            data = data[:-1] + bytes([data[-1] ^ 0x40])
        r = struct.pack('>BBHHH', 0, 0, 0, ident, seq) + data
        c = csum(r)
        if self.plant == 'icmp-checksum':
            c ^= 1
        self.send_ip(t, src, 1, r[:2] + struct.pack('>H', c) + r[4:],
                     ident=ident_in if self.plant == 'ident-copied' else None)

    # ---- TCP ---------------------------------------------------------------
    def isn(self, t, key):
        """RFC 6528: the microsecond clock in 4 us units plus a keyed hash
        of the four-tuple (section 5.5)."""
        if self.plant == 'constant-isn':
            return 0x12345678
        if self.next_isn is not None and self.plant != 'isn-hook-ignored':
            # The test hook: the ISN of the next connection taken, used once
            # (the isn-hook-sticky plant keeps it).
            n = self.next_isn
            if self.plant != 'isn-hook-sticky':
                self.next_isn = None
            return n
        h = hashlib.sha256(self.key + (b'' if self.plant == 'isn-no-tuple' else repr(key).encode())).digest()
        if self.plant == 'isn-clock-at-take':
            # Each SYN of one pass taken 100 us after the one before.
            self.isn_k = getattr(self, 'isn_k', 0) + 1 if getattr(self, 'isn_t', None) == t else 0
            self.isn_t = t
            t = t + 100_000 * self.isn_k
        clock = 0 if self.plant == 'isn-no-clock' else t // 4000
        return (clock + int.from_bytes(h[:4], 'big')) & 0xFFFFFFFF

    def receive_tcp(self, t, src, seg):
        sport, dport, seq, ack, offw, win = struct.unpack('>HHIIHH', seg[:16])
        urg = struct.unpack('>H', seg[18:20])[0]
        off, flags = offw >> 12, offw & 0x3F
        if off < 5 or 4 * off > len(seg):
            return
        opts, data = seg[20:4 * off], seg[4 * off:]
        peer_mss, i = None, 0
        while i < len(opts):
            k = opts[i]
            if k == 0:
                break
            if k == 1:
                if self.plant == 'nop-illegal':
                    return
                i += 1
                continue
            if i + 1 >= len(opts) or opts[i + 1] < 2 or i + opts[i + 1] > len(opts):
                if self.plant == 'bad-option-taken':
                    break
                c = self.conns.get((src, sport, dport))
                if self.plant == 'dup-ack-on-drop' and c is not None and not flags & RST:
                    # Dropped, and answered with an ACK of the unchanged
                    # state, which F16 allows.
                    self.send_tcp(t, c, ACK, b'', c.snd_nxt)
                return          # an illegal length drops the segment
            if k != 2 and self.plant == 'unknown-option-drop':
                return
            if k != 2 and self.plant == 'option-stop-unknown':
                break
            if k == 2 and opts[i + 1] == 4:
                peer_mss = struct.unpack('>H', opts[i + 2:i + 4])[0]
            i += opts[i + 1]
        key = (src, sport, dport)
        tw = self.timewait.get(key)
        if tw is not None and self.timewait_segment(t, key, tw, seq, flags, data):
            return
        c = self.conns.get(key)
        if c is None:
            if flags & RST:
                return
            open_ports = (self.a.telnet_port, self.a.echo_port) if self.echo_on else (self.a.telnet_port,)
            if flags & SYN and not flags & ACK and dport in open_ports:
                if self.refused_source(src):
                    return          # MUST-63: refused silently
                # The backlog first, then the table, where every connection
                # from SYN-RECEIVED to LAST-ACK counts (F21).
                half = sum(1 for x in self.conns.values() if x.state == 'SYN-RECEIVED' and x.port == dport)
                table = len(self.conns) if self.plant != 'half-open-uncounted' else \
                    sum(1 for x in self.conns.values() if x.state != 'SYN-RECEIVED')
                full_table = table >= (9 if self.plant == 'table-9' else 8)
                if self.plant == 'table-first' and full_table:
                    self.refuse(t, src, dport, sport, seq)
                    return
                if half >= (5 if self.plant == 'backlog-5' else 4):
                    if self.plant == 'backlog-rst':
                        self.refuse(t, src, dport, sport, seq)
                    return          # a full backlog: dropped
                if full_table:
                    self.refuse(t, src, dport, sport, seq)
                    return          # a full table: RST
                mss = min(peer_mss if peer_mss is not None else
                          (1460 if self.plant == 'send-mss-default' else 536),
                          1400 if self.plant == 'send-mss-1400' else 1460)
                c = Conn(key, seq, self.isn(t, key), mss, win, dport)
                if dport == self.a.echo_port and self.next_r2 is not None and self.plant != 'r2-hook-ignored':
                    # The R2 hook: this connection's R2, through section 5.5's
                    # keyword, used once (F41; the r2-hook-sticky plant keeps it).
                    c.r2 = self.next_r2 * S
                    if self.plant != 'r2-hook-sticky':
                        self.next_r2 = None
                if self.plant == 'first-rto-3s':
                    c.rto_base = 3 * S
                self.conns[key] = c
                self.send_synack(t, c)
                if self.plant == 'banner-early' and dport == self.a.telnet_port:
                    # 50 ms after the SYN-ACK, so that the SYN-ACK is out
                    # (the ARP hold keeps only the newest datagram).
                    self.at(t + 50 * MS, lambda tt, c=c: self.queue(tt, c, self.banner()))
                return
            # No connection: RST (a closed port, or a segment on a
            # listening port that belongs to no connection).
            if self.plant == 'closed-port-silent' and dport not in open_ports:
                return
            if self.plant == 'isn-hook-consumed-by-refused' and flags & SYN:
                self.next_isn = None    # a refused SYN takes the hook, which F36 forbids
            if flags & ACK:
                self.raw_tcp(t, src, dport, sport, ack, 0, RST, 0)
            elif self.plant == 'rst-no-ack':
                self.raw_tcp(t, src, dport, sport, 0, 0, RST, 0)
            else:
                self.raw_tcp(t, src, dport, sport, 0, (seq + len(data) + (1 if flags & SYN else 0)) & 0xFFFFFFFF,
                             RST | ACK, 0)
            return
        if flags & RST:
            if self.rst_acceptable(c, seq):
                if self.plant == 'rst-synrcvd-ignored' and c.state == 'SYN-RECEIVED':
                    return
                del self.conns[key]
                if c.port == self.a.echo_port and c.state != 'SYN-RECEIVED':
                    # The echo service's stream signals the error (section
                    # 9, T1, RST), and the service keeps it.
                    self.echo_condition = 'EOF' if self.plant == 'rst-no-signal' else 'SYS:CONNECTION-LOST'
            elif self.plant == 'rst-exact-only' and self.in_window(c, seq):
                self.send_tcp(t, c, ACK, b'', c.snd_nxt)   # RFC 5961's challenge ACK
            return
        if flags & SYN:
            if c.state == 'SYN-RECEIVED' and seq == c.irs:
                self.send_synack(t, c)
            elif self.plant == 'syn-estab-reset':
                self.send_tcp(t, c, RST | ACK, b'', c.snd_nxt)
                del self.conns[key]
            else:
                self.send_tcp(t, c, ACK, b'', c.snd_nxt)   # a challenge ACK (RFC 5961 section 4)
            return
        if not flags & ACK:
            return
        if flags & URG and not (self.plant == 'urg-ignored-at-zero-window' and self.window(c) == 0):
            # The urgent pointer is kept even when the data is not taken, at
            # a zero window (MUST-66): RCV.UP, the byte after the urgent data.
            up = (seq + urg) & 0xFFFFFFFF
            if getattr(c, 'rcv_up', None) is None or self.lt(c.rcv_up, up):
                c.rcv_up = up
        if c.state == 'SYN-RECEIVED':
            # The ACK of the SYN-ACK, and of any data sent with it.
            if not (self.lt(c.iss, ack) and not self.lt(c.snd_nxt, ack)):
                return
            c.state = 'ESTABLISHED'
            c.buf = c.buf[(ack - c.iss - 1) & 0xFFFFFFFF:]
            c.snd_una = ack
            c.peer_window = win
            c.max_wnd = max(c.max_wnd, win)
            c.timer = None
            if c.synack_tx is not None and c.retries == 0:
                self.sample(c, t - c.synack_tx)
            elif c.retries and c.srtt is None and self.plant != 'no-rule-5-7':
                # RFC 6298 (5.7): the SYN-ACK was resent and the RTO is
                # below 3 s, so data starts at 3 s.
                c.rto_base = 3 * S
            if c.retries and self.plant != 'iw3-after-synack-resend':
                # RFC 5681 section 3.1: after a lost SYN-ACK the initial
                # window is one segment (section 5.5; F34).
                c.cwnd = c.mss
            c.retries = 0
            c.backoff = 0
            if c.port == self.a.telnet_port and self.plant not in ('banner-early', 'no-banner'):
                self.queue(t, c, self.banner())
        elif not (self.plant == 'ack-ignored-at-zero-window' and self.window(c) == 0):
            # An ACK of what was never sent: RFC 9293 section 3.10.7.4 has it
            # answered with an ACK and dropped (the ack-past-snd-nxt-acked
            # variant); the stand-in drops it silently.
            if self.lt(c.max_sent, ack):
                if self.plant == 'ack-past-snd-nxt-acked':
                    self.send_tcp(t, c, ACK, b'', c.snd_nxt)
                return
            # A valid ACK is taken even at our own zero window (MUST-66).
            if self.lt(c.snd_una, ack) and not self.lt(c.max_sent, ack):
                self.acked(t, c, ack)
                if c.fin_seq is not None and ack == (c.fin_seq + 1) & 0xFFFFFFFF:
                    # Our FIN is acknowledged.
                    if c.state == 'FIN-WAIT-1':
                        c.state = 'FIN-WAIT-2'
                        self.fin_wait_2_arm(t, c)
                    elif c.state == 'CLOSING':
                        self.enter_timewait(t, c)
                        return
                    elif c.state == 'LAST-ACK':
                        del self.conns[key]
                        return
            if ack == c.snd_una or self.lt(c.snd_una, ack):
                self.window_update(t, c, win)
        need_ack = False
        if not data and not flags & (SYN | FIN) and c.state != 'SYN-RECEIVED' and \
                self.plant != 'own-probe-unanswered':
            # A segment without data that is not acceptable, such as a probe
            # below RCV.NXT, gets an ACK (RFC 9293 section 3.10.7.4, Table 5).
            w = self.window(c)
            ok = seq == c.rcv_nxt if w == 0 else \
                not self.lt(seq, c.rcv_nxt) and self.lt(seq, (c.rcv_nxt + w) & 0xFFFFFFFF)
            need_ack = not ok
        if data and c.state in ('ESTABLISHED', 'FIN-WAIT-1', 'FIN-WAIT-2'):
            if seq == c.rcv_nxt:
                room = self.window(c)
                take = data[:room]
                c.rcv_nxt = (c.rcv_nxt + len(take)) & 0xFFFFFFFF
                if take:
                    self.deliver(t, c, take)
                need_ack = True
                if self.plant == 'ooo-queued':
                    while c.rcv_nxt in c.ooo:
                        more = c.ooo.pop(c.rcv_nxt)
                        c.rcv_nxt = (c.rcv_nxt + len(more)) & 0xFFFFFFFF
            elif self.lt(seq, c.rcv_nxt) and self.lt(c.rcv_nxt, (seq + len(data)) & 0xFFFFFFFF):
                # An overlap: only its new part is taken.
                take = data if self.plant == 'overlap-whole' else data[(c.rcv_nxt - seq) & 0xFFFFFFFF:]
                c.rcv_nxt = (c.rcv_nxt + len(take)) & 0xFFFFFFFF
                self.deliver(t, c, data if self.plant == 'overlap-old-delivered' else take)
                need_ack = True
            elif self.plant == 'old-dup-unacked' and self.lt(seq, c.rcv_nxt):
                pass
            elif self.lt(c.rcv_nxt, seq):
                # Beyond RCV.NXT: dropped and answered with an ACK (5.5,
                # in-order delivery only).
                if self.plant == 'ooo-queued':
                    c.ooo[seq] = data
                need_ack = self.plant != 'ooo-silent'
            else:
                # An old duplicate: acknowledged, not delivered.
                if self.plant == 'dup-delivered':
                    self.deliver(t, c, data)
                need_ack = True
        elif data:
            need_ack = True     # after the peer's FIN: acknowledged, not taken
        if flags & FIN and ((seq + len(data)) & 0xFFFFFFFF) == c.rcv_nxt:
            if c.state == 'ESTABLISHED':
                c.rcv_nxt = (c.rcv_nxt + 1) & 0xFFFFFFFF
                c.state = 'CLOSE-WAIT'
                # The stream reads EOF, and the server closes its side.
                if self.plant != 'eof-no-close':
                    c.close_req = True
                need_ack = True
            elif c.state == 'FIN-WAIT-2':
                c.rcv_nxt = (c.rcv_nxt + 1) & 0xFFFFFFFF
                self.send_tcp(t, c, ACK, b'', c.snd_nxt)
                self.enter_timewait(t, c)
                return
            elif c.state == 'FIN-WAIT-1' and self.plant != 'closing-broken':
                # Both FINs crossed: CLOSING, our FIN still unacknowledged.
                c.rcv_nxt = (c.rcv_nxt + 1) & 0xFFFFFFFF
                c.state = 'CLOSING'
                need_ack = True
        elif flags & FIN and c.state in ('CLOSE-WAIT', 'LAST-ACK', 'CLOSING') and \
                ((seq + len(data) + 1) & 0xFFFFFFFF) == c.rcv_nxt:
            need_ack = True     # the peer's FIN again
        if not self.output(t, c) and need_ack:
            self.send_tcp(t, c, ACK, b'', c.snd_nxt)

    # ---- RST, SYN and close (section 5.5) ---------------------------------
    def refuse(self, t, src, dport, sport, seq):
        """RFC 9293 section 3.10.7.1's RST to a SYN: <SEQ=0><ACK=SEG.SEQ+1>
        <CTL=RST,ACK> (F20); the rst-no-ack plant's has no ACK."""
        if self.plant == 'isn-hook-consumed-by-refused':
            self.next_isn = None
        if self.plant == 'rst-no-ack':
            self.raw_tcp(t, src, dport, sport, 0, 0, RST, 0)
        else:
            self.raw_tcp(t, src, dport, sport, 0, (seq + 1) & 0xFFFFFFFF, RST | ACK, 0)

    def in_window(self, c, seq):
        """SEQ in our receive window; at a zero window only RCV.NXT."""
        w = self.window(c) if c.state != 'SYN-RECEIVED' else 8192
        if w == 0:
            return seq == c.rcv_nxt and self.plant != 'rst-ignored-at-zero-window'
        return not self.lt(seq, c.rcv_nxt) and self.lt(seq, (c.rcv_nxt + w) & 0xFFFFFFFF)

    def rst_acceptable(self, c, seq):
        """An RST is taken when its sequence number is in the window
        (section 5.5)."""
        if self.plant == 'rst-out-of-window-accepted':
            return True
        if self.plant == 'rst-exact-only':
            return seq == c.rcv_nxt
        return self.in_window(c, seq)

    def refused_source(self, src):
        """MUST-63's sources: a broadcast, either, multicast or class E,
        0.0.0.0, loopback, and the band's own address."""
        n = int.from_bytes(src, 'big')
        me = int.from_bytes(self.ip, 'big')
        subnet_bcast = (me & self.mask) | (~self.mask & 0xFFFFFFFF)
        if self.plant == 'syn-from-broadcast' and n in (0xFFFFFFFF, subnet_bcast):
            return False
        return n in (0xFFFFFFFF, subnet_bcast, 0, me) or n >= 0xE0000000 or (n >> 24) == 127

    def enter_timewait(self, t, c):
        """TIME-WAIT: 60 s of machine time, apart from the connections."""
        del self.conns[c.key]
        if self.plant == 'time-wait-skipped':
            return
        tw = {'rcv_nxt': c.rcv_nxt, 'snd_nxt': c.snd_nxt, 'gen': 0}
        self.timewait[c.key] = tw
        self.timewait_arm(t, c.key, tw)

    def timewait_arm(self, t, key, tw):
        tw['gen'] += 1
        g = tw['gen']
        length = 30 * S if self.plant == 'time-wait-30' else 60 * S

        def end(tt):
            if self.timewait.get(key) is tw and tw['gen'] == g:
                del self.timewait[key]
        self.at(t + length, end)

    def timewait_segment(self, t, key, tw, seq, flags, data):
        """A segment to a TIME-WAIT record; False to go on as with no
        connection (a SYN above its final RCV.NXT opens a new one)."""
        src, sport, dport = key
        if flags & RST:
            return True
        if flags & SYN and not flags & ACK:
            if (self.lt(tw['rcv_nxt'], seq) and self.plant != 'tw-syn-refused') or \
                    self.plant == 'tw-syn-low-accepted':
                del self.timewait[key]
                return False
            self.raw_tcp(t, src, dport, sport, tw['snd_nxt'], tw['rcv_nxt'], ACK, 8192)
            return True
        if flags & FIN:
            # The peer's FIN again: acknowledged, and TIME-WAIT restarts.
            if self.plant != 'tw-fin-unacked':
                self.raw_tcp(t, src, dport, sport, tw['snd_nxt'], tw['rcv_nxt'], ACK, 8192)
                self.timewait_arm(t, key, tw)
            return True
        # Any other segment that is not acceptable gets an ACK of the final
        # RCV.NXT (RFC 9293 section 3.10.7.4; F23); an acceptable bare ACK,
        # at RCV.NXT with nothing in it, gets nothing.
        if data or seq != tw['rcv_nxt']:
            self.raw_tcp(t, src, dport, sport, tw['snd_nxt'], tw['rcv_nxt'], ACK, 8192)
        return True

    def deliver(self, t, c, data):
        """Hand DATA to the connection's server: the echo service writes it
        back, the TELNET server's listener reads it.  With the server-process
        variant the server is a process of its own: the stack only
        acknowledges now, and the server's output is built later, after a
        delay (seeded, up to a tick, under --timing tick), in order, with
        the ACK of that moment; and the listener echoes what it reads, as
        MIT's ECHOING-STREAM does, after its opening flush of three bytes for
        each IAC."""
        if c.port == self.a.echo_port:
            c.rbuf += data          # the echo service reads it when it can
        if self.plant != 'server-process':
            if c.port == self.a.echo_port:
                self.pump(t, c)
            else:
                self.listener(t, c, data)
            return
        delay = self.rng.randrange(S // 60) if self.tick else 3 * MS
        when = max(t + delay, getattr(c, 'server_at', 0))
        c.server_at = when

        def run(tt, c=c, data=data):
            if self.conns.get(c.key) is not c:
                return
            if c.port == self.a.echo_port:
                self.pump(tt, c)
            else:
                if not getattr(c, 'flushed', False):
                    c.flushed = True
                    while data[:1] == b'\xff':
                        data = data[3:]
                c.buf += data           # the listener's echo
                self.listener(tt, c, data)
            self.output(tt, c)
        self.at(when, run)

    def listener(self, t, c, data):
        """The TELNET server's listener: a form of the control session's
        table, once whole, is done and its marker printed (the stand-in
        prints only the marker, not the listener's echo)."""
        c.typed = getattr(c, 'typed', b'') + data
        for pattern, name in self.forms:
            m = pattern.search(c.typed)
            if not m:
                continue
            c.typed = c.typed[m.end():]
            args = [int(g) for g in m.groups()]
            if name == 'echo-on':
                self.echo_on = True
                marker = '{sc-echo-on}'
            elif name == 'totals':
                marker = '{sc-totals %d %d}' % (self.type_total, self.ipv4_total)
            elif name == 'condition':
                marker = '{sc-condition %s}' % (self.echo_condition or 'NIL')
            elif name == 'r2-next':
                self.next_r2 = args[0]
                marker = '{sc-r2-set}'
            elif name == 'isn-next':
                self.next_isn = args[0] & 0xFFFFFFFF
                marker = '{sc-isn-set}'
            elif name == 'urgent':
                target = next((x for x in self.conns.values() if x.key[1] == args[0]), None)
                marker = '{sc-urgent %d %d}' % self.urgent_state(target)
            elif name == 'ping':
                # The band's ping (section 5.4; F36): an echo request; the
                # marker is printed when the reply that matches it comes, or
                # as NIL NIL after a wait of 1 s.
                self.ping_seq += 1
                self.ping = (0x5150, self.ping_seq, c)
                ping = self.ping

                def give_up(tt, ping=ping):
                    if self.ping is ping:
                        self.ping = None
                        ping[2].buf += b'\r\n{sc-pinged NIL NIL}\r\n'
                        self.output(tt, ping[2])
                body = struct.pack('>BBHHH', 8, 0, 0, 0x5150, self.ping_seq) + b'segment script ping'
                body = body[:2] + struct.pack('>H', csum(body)) + body[4:]
                self.send_ip(t, bytes(args[:4]), 1, body)
                self.at(t + 1 * S, give_up)
                continue
            elif name == 'close':
                target = next((x for x in self.conns.values() if x.key[1] == args[0]), None)
                if target is not None:
                    target.close_req = True
                    self.output(t, target)
                    if self.plant == 'close-then-abort':
                        # The server's later close aborts: RST in FIN-WAIT-1
                        # or -2 (RFC 9293 section 3.10.5), which F36 forbids.
                        def abort(tt, c=target):
                            if self.conns.get(c.key) is c and c.state in ('FIN-WAIT-1', 'FIN-WAIT-2'):
                                self.send_tcp(tt, c, RST | ACK, b'', c.snd_nxt)
                                del self.conns[c.key]
                        self.at(t + 1 * S, abort)
                marker = '{sc-closed %d}' % args[0]
            else:
                continue
            c.buf += ('\r\n%s\r\n' % marker).encode()

    def urgent_state(self, c):
        """The urgent state of C's stream (section 5.5, F32): waiting or
        not, and the octets from the next one the server reads up to the
        urgent pointer, those not yet received included; (0, 0) with no
        pointer or once the server has read up to it.  The plants are the
        readings F32 rejects."""
        up = getattr(c, 'rcv_up', None) if c else None
        if up is None:
            return 0, 0
        read = (c.rcv_nxt - len(c.rbuf)) & 0xFFFFFFFF
        if self.plant == 'urgent-last-octet':
            # RFC 1122 section 4.2.2.4: the pointer is the last urgent octet.
            return (1, (up - read + 1) & 0xFFFFFFFF) if not self.lt(up, read) else (0, 0)
        if self.plant == 'urgent-mode-kept':
            return 1, (up - read) & 0xFFFFFFFF if self.lt(read, up) else 0
        if not self.lt(read, up):
            return 0, 0
        if self.plant == 'urgent-received-only':
            return 1, ((up if self.lt(up, c.rcv_nxt) else c.rcv_nxt) - read) & 0xFFFFFFFF
        if self.plant == 'urgent-zero-window-from-start' and self.window(c) == 0:
            return 1, (up - c.irs - 1) & 0xFFFFFFFF
        return 1, (up - read) & 0xFFFFFFFF

    def banner(self):
        # TELNET's WILL ECHO and WILL SUPPRESS-GO-AHEAD, then a herald.
        return bytes([255, 251, 1, 255, 251, 3]) + b'\r\nStand-in band, segment scripts.\r\n'

    def queue(self, t, c, data):
        c.buf += data
        self.output(t, c)

    # ---- sending (section 5.5) ------------------------------------------
    def output(self, t, c):
        """Send what MUST-38's rules allow, all data being pushed: (1) a full
        MSS; (2) all that is queued, if it fits now; (3) at least half the
        largest window the peer has offered; (4) the rest when the override
        timer of 200 ms expires.  Always within the peer's window and the
        congestion window; a zero window starts the persist timer."""
        sent = False
        while True:
            flight = (c.snd_nxt - c.snd_una) & 0xFFFFFFFF
            if c.state == 'SYN-RECEIVED' and self.plant != 'banner-early':
                return sent
            if c.state == 'SYN-RECEIVED':
                flight -= 1     # the SYN's own number
            if c.fin_seq is not None:
                return sent     # nothing after our FIN
            unsent = c.buf[flight:]
            if not unsent:
                if c.close_req and c.state in ('ESTABLISHED', 'CLOSE-WAIT'):
                    # The close: a FIN after the data, which takes a
                    # sequence number (the fin-no-seq plant's does not).
                    c.fin_seq = c.snd_nxt
                    c.fin_tx = t
                    self.send_tcp(t, c, FIN | ACK, b'', c.snd_nxt)
                    if self.plant != 'fin-no-seq':
                        c.snd_nxt = (c.snd_nxt + 1) & 0xFFFFFFFF
                        self.sent_new(t, c, c.fin_seq, c.snd_nxt)
                    c.state = 'FIN-WAIT-1' if c.state == 'ESTABLISHED' else 'LAST-ACK'
                    if c.timer is None:
                        self.arm(t, c)
                    return True
                return sent
            window = c.peer_window + (1 if self.plant == 'window-edge-off-by-one' else 0)
            if self.plant == 'shrink-old-edge-kept' and window > 0 and getattr(c, 'kept_edge', None) is not None:
                # The edge never moves left: an old one kept past a shrink.
                window = max(window, (c.kept_edge - c.snd_una + 2 ** 31) % 2 ** 32 - 2 ** 31)
            usable = (c.cwnd if self.plant == 'window-ignored' else min(window, c.cwnd)) - flight
            if self.plant == 'usable-unsigned' and usable < 0:
                usable &= 0xFFFF   # the usable window taken without its sign
            if usable <= 0:
                if c.peer_window == 0 and flight == 0:
                    self.persist_start(t, c)
                return sent
            d = len(unsent)
            n = min(c.mss, usable, d)
            rule1 = min(d, usable) >= c.mss and self.plant != 'rule1-off'
            rule2 = d <= usable and self.plant != 'rule2-off'
            rule3 = min(d, usable) * 2 >= c.max_wnd and self.plant != 'rule3-off'
            if not (rule1 or rule2 or rule3 or getattr(c, 'forced', False)):
                self.override_start(t, c)
                return sent
            c.forced = False
            push = n == d and self.plant != 'no-psh' and \
                not (self.plant == 'resend-no-psh' and self.lt(c.snd_nxt, c.max_sent))
            self.send_tcp(t, c, ACK | (PSH if push else 0), unsent[:n], c.snd_nxt)
            start = c.snd_nxt
            c.snd_nxt = (c.snd_nxt + n) & 0xFFFFFFFF
            self.sent_new(t, c, start, c.snd_nxt)
            sent = True
            if c.timer is None:
                self.arm(t, c)

    def sent_new(self, t, c, start, end):
        """A segment [START, END) sent: time it if it is new data (Karn: a
        resent one is never timed), and note its first transmission."""
        if self.lt(c.max_sent, end):
            if not self.lt(start, c.max_sent) and c.timed is None:
                c.timed = (end, t)
            c.first_tx.append((end, t))
            c.max_sent = end
            if len(c.first_tx) == 1:
                self.r2_arm(t, c)

    def rto(self, c):
        base = c.rto_base
        if self.plant != 'rto-no-double':
            base = base << c.backoff
        return min(base, 120 * S if self.plant == 'rto-cap-120' else 60 * S)

    def sample(self, c, r):
        """An RTT sample R (RFC 6298 section 2): SRTT, RTTVAR and the RTO,
        at least 200 ms (the rto-floor-1s plant: RFC 6298's 1 s)."""
        if c.srtt is None:
            c.srtt, c.rttvar = r, r // 2
        else:
            c.rttvar = (3 * c.rttvar + abs(c.srtt - r)) // 4
            c.srtt = (7 * c.srtt + r) // 8
        floor = 1 * S if self.plant == 'rto-floor-1s' else 200 * MS
        c.rto_base = min(max(floor, c.srtt + max(1000, 4 * c.rttvar)), 60 * S)

    def acked(self, t, c, ack):
        """An ACK of new data: the send buffer, the RTT sample, the timer
        restarted (RFC 6298 section 5.3), slow start or congestion
        avoidance (RFC 5681)."""
        c.acked_at = t
        n = (ack - c.snd_una) & 0xFFFFFFFF
        c.buf = c.buf[n:]
        c.snd_una = ack
        if self.lt(c.snd_nxt, ack):
            c.snd_nxt = ack
        if c.timed is not None and not self.lt(ack, c.timed[0]):
            self.sample(c, t - c.timed[1])
            c.timed = None
            if self.plant == 'probe-moves-snd-nxt':
                # Linux: one backoff for the retransmission and the persist
                # timers, reset by a valid RTT sample.
                c.persist_backoff = 0
        elif self.plant == 'karn-off' and c.first_tx and c.retries:
            # Karn's rule broken: a sample from a resent segment, timed
            # from its first transmission.
            self.sample(c, t - c.first_tx[0][1])
        while c.first_tx and not self.lt(ack, c.first_tx[0][0]):
            c.first_tx.pop(0)
            self.r2_arm(t, c)
        c.retries = 0
        c.backoff = 0
        if c.cwnd < c.ssthresh:
            # RFC 5681 section 3.1: a whole SMSS for each ACK, or (the
            # cwnd-abc variant) equation (2)'s min(N, SMSS).
            c.cwnd += min(n, c.mss) if self.plant == 'cwnd-abc' else c.mss
        else:
            c.cwnd += max(1, c.mss * c.mss // c.cwnd)
        if c.snd_una != c.snd_nxt or c.fin_seq is not None and c.snd_una != c.max_sent:
            if self.plant != 'timer-no-restart' or c.timer is None:
                c.timer = None
                self.arm(t, c)
        else:
            c.timer = None
        if c.port == self.a.echo_port:
            self.pump(t, c)

    def window_update(self, t, c, win):
        if self.plant == 'smaller-window-ignored' and 0 < win < c.peer_window:
            return
        was = c.peer_window
        if win > 0:
            edge = (c.snd_una + win) & 0xFFFFFFFF
            kept = getattr(c, 'kept_edge', None)
            if kept is None or 0 < ((edge - kept) & 0xFFFFFFFF) < 0x80000000:
                c.kept_edge = edge
        c.peer_window = win
        c.max_wnd = max(c.max_wnd, win)
        if win > 0 and c.persist is not None:
            c.persist = None
            c.persist_backoff = 0
            if c.snd_una != c.snd_nxt and c.timer is None:
                self.arm(t, c)      # a probe octet that moved SND.NXT is resent
        if win == 0 and (was != 0 or getattr(c, 'zero_since', None) is None):
            c.zero_since = t
        if win > 0:
            c.zero_since = None

    def window(self, c):
        """Our receive window: the free space of the 8,192-byte buffer,
        its right edge moved only by at least the connection's effective send
        MSS, min(the peer's MSS, 1,460) (receiver silly window avoidance,
        MUST-39, F25; the receiver-sws-off plant moves it by any amount)."""
        free = 8192 - len(c.rbuf)
        edge = (c.rcv_nxt + free) & 0xFFFFFFFF
        if c.adv_edge is None or self.plant == 'receiver-sws-off' or \
                ((edge - c.adv_edge) & 0xFFFFFFFF) < 0x80000000 and ((edge - c.adv_edge) & 0xFFFFFFFF) >= c.mss:
            c.adv_edge = edge
        w = (c.adv_edge - c.rcv_nxt) & 0xFFFFFFFF
        return 0 if w >= 0x80000000 else min(w, 8192)

    def pump(self, t, c):
        """The echo service: it reads what has arrived while its writes
        fit the 8,192-byte send buffer, writes it back and pushes."""
        room = 8192 - len(c.buf)
        if room > 0 and c.rbuf:
            k = min(room, len(c.rbuf))
            was = self.window(c)
            c.buf += c.rbuf[:k]
            c.rbuf = c.rbuf[k:]
            if self.window(c) != was and was == 0:
                # The window opened from zero: say so at once.
                self.send_tcp(t, c, ACK, b'', c.snd_nxt)

    # ---- timers -------------------------------------------------------------
    def arm(self, t, c):
        c.gen += 1
        rto = self.rto(c)
        c.timer = (t + rto, c.gen)
        g = c.gen
        self.at(t + rto, lambda tt, c=c, g=g: self.expire(tt, c, g))

    def expire(self, t, c, g):
        """The retransmission timer: the RTO doubles (RFC 6298 section 5.5),
        after R1 = 3 the next hop's ARP entry goes (MUST-20), the congestion
        window drops to one segment and the sender goes back to SND.UNA, so
        one segment goes and new data only as ACKs come (RFC 5681 section
        3.1)."""
        if self.conns.get(c.key) is not c or c.gen != g or c.timer is None:
            return
        c.timer = None
        c.retries += 1
        c.backoff += 1
        c.timed = None
        if self.plant == 'r2-at-timer' and c.first_tx and t - c.first_tx[0][1] >= getattr(c, 'r2', 100 * S):
            return self.r2_close(t, c)
        if c.state == 'SYN-RECEIVED' and self.plant == 'synack-r2-at-timer' and t - c.synack_tx >= 180 * S:
            # R2 checked only when the timer runs out: closed at 183 s.
            del self.conns[c.key]
            return
        r1 = c.retries >= 4 if self.plant == 'r1-every-resend' else c.retries == (3 if self.plant == 'r1-early' else 4)
        if r1 and self.plant != 'r1-no-arp' and \
                not (c.state == 'SYN-RECEIVED' and self.plant == 'synack-r1-no-arp'):
            # R1 = 3 retransmissions made: the next hop's entry goes, so the
            # fourth needs ARP again.
            hop = c.key[0] if self.same_subnet(c.key[0]) else self.gw
            self.arp.pop(hop, None)
        if c.state == 'SYN-RECEIVED':
            self.send_synack(t, c)
            return
        flight = (c.snd_nxt - c.snd_una) & 0xFFFFFFFF
        if c.fin_seq is not None:
            if c.buf and flight:
                n = min(c.mss, len(c.buf))
                self.send_tcp(t, c, ACK, c.buf[:n], c.snd_una)
            elif flight:
                self.send_tcp(t, c, FIN | ACK, b'', c.fin_seq)
            self.arm(t, c)
            return
        if self.plant != 'cwnd-not-reset':
            c.ssthresh = max(flight // 2, 2 * c.mss)
            c.cwnd = c.mss
        c.snd_nxt = c.snd_una
        c.forced = True     # the resent segment goes whatever MUST-38 says
        self.output(t, c)
        if c.timer is None and c.snd_una != c.max_sent:
            self.arm(t, c)

    def same_subnet(self, ip):
        return (int.from_bytes(ip, 'big') & self.mask) == (int.from_bytes(self.ip, 'big') & self.mask)

    def r2_arm(self, t, c):
        """R2: 100 s, or what the R2 hook gave the connection (F41), from the
        first transmission of the oldest unacknowledged segment the
        connection closes, at that time (O4)."""
        c.r2_gen += 1
        if not c.first_tx or self.plant == 'r2-at-timer':
            return
        g, deadline = c.r2_gen, c.first_tx[0][1] + getattr(c, 'r2', 100 * S)

        def fire(tt, c=c, g=g):
            if self.conns.get(c.key) is c and c.r2_gen == g:
                self.r2_close(tt, c)
        self.at(deadline, fire)

    def r2_close(self, t, c):
        del self.conns[c.key]
        if c.port == self.a.echo_port and self.plant != 'r2-no-signal':
            self.echo_condition = 'SYS:HOST-STOPPED-RESPONDING'

    def persist_start(self, t, c):
        """The persist timer: probes of a zero window from the RTO, backing
        off to 60 s, never aborting while they are acknowledged (MUST-35 to
        -37)."""
        if c.persist is not None or self.plant == 'persist-off':
            return
        c.persist_gen = getattr(c, 'persist_gen', 0) + 1
        c.persist = c.persist_gen
        c.persist_start_t = getattr(c, 'persist_start_t', None) or t
        self.persist_arm(t, c)

    def persist_arm(self, t, c):
        g = c.persist
        base = c.rto_base if self.plant == 'persist-no-backoff' else c.rto_base << c.persist_backoff
        delay = min(base, 60 * S)
        if self.plant == 'persist-from-zero-window' and c.persist_backoff == 0 and \
                getattr(c, 'zero_since', None) is not None:
            # SHLD-29 read from the zero window's arrival, not from the data
            # waiting under it.
            delay = max(0, c.zero_since + delay - t)

        def fire(tt, c=c, g=g):
            if self.conns.get(c.key) is not c or c.persist != g:
                return
            if self.plant == 'zero-window-abort' and tt - c.persist_start_t >= 60 * S:
                return self.r2_close(tt, c)
            # A probe of one octet of new data (RFC 9293 section 3.8.6.1,
            # MUST-36), or with the zero-length-probe variant Linux's
            # zero-length one at SND.UNA - 1; the peer answers either.
            flight = (c.snd_nxt - c.snd_una) & 0xFFFFFFFF
            if self.plant == 'zero-length-probe' or not c.buf[flight:flight + 1]:
                self.send_tcp(tt, c, ACK, b'', (c.snd_una - 1) & 0xFFFFFFFF)
            elif self.plant == 'probe-moves-snd-nxt' and flight:
                # The octet already out, unacknowledged: probe with it again.
                self.send_tcp(tt, c, ACK, c.buf[:1], c.snd_una)
            elif self.plant == 'probe-moves-snd-nxt':
                # The octet sent as new data: SND.NXT moves and it is timed,
                # but neither the retransmission timer nor R2 runs on it.
                start = c.snd_nxt
                self.send_tcp(tt, c, ACK, c.buf[flight:flight + 1], c.snd_nxt)
                c.snd_nxt = (c.snd_nxt + 1) & 0xFFFFFFFF
                if self.lt(c.max_sent, c.snd_nxt):
                    if c.timed is None:
                        c.timed = (c.snd_nxt, tt)
                    c.max_sent = c.snd_nxt
            else:
                self.send_tcp(tt, c, ACK, c.buf[flight:flight + 1], c.snd_nxt)
            c.persist_backoff += 1
            self.persist_arm(tt, c)
        self.at(t + delay, fire)

    def override_start(self, t, c):
        if self.plant == 'override-restart-on-ack' and c.override is not None and \
                getattr(c, 'override_at', None) != t and getattr(c, 'acked_at', None) == t:
            c.override = None       # an ACK that leaves the data held restarts it
        if c.override is not None or self.plant == 'override-off':
            return
        c.override_at = t
        c.override_gen = getattr(c, 'override_gen', 0) + 1
        c.override = g = c.override_gen

        def fire(tt, c=c, g=g):
            if self.conns.get(c.key) is not c or c.override != g:
                return
            c.override = None
            c.forced = True
            self.output(tt, c)
        self.at(t + 200 * MS, fire)

    def fin_wait_2_arm(self, t, c):
        """FIN-WAIT-2 ends 60 s after the band's FIN, the application having
        closed (section 5.5; F31)."""
        if self.plant == 'fin-wait-2-forever':
            return
        length = 30 * S if self.plant == 'fin-wait-2-30' else 60 * S

        def end(tt, c=c):
            if self.conns.get(c.key) is c and c.state == 'FIN-WAIT-2':
                del self.conns[c.key]
        # From the band's FIN (F35); the fin-wait-2-from-ack plant times it
        # from the peer's ACK of the FIN, Linux's origin.
        self.at((t if self.plant == 'fin-wait-2-from-ack' else c.fin_tx) + length, end)

    def send_synack(self, t, c):
        opts = struct.pack('>BBH', 2, 4, 1400 if self.plant == 'synack-mss' else 1460)
        if self.plant == 'synack-wscale':
            opts += bytes([1, 3, 3, 0])
        self.send_tcp(t, c, SYN | ACK, b'', c.iss, opts)
        if c.synack_tx is None:
            c.synack_tx = t
            # R2 for a SYN-ACK, 180 s from its first transmission: the
            # half-open connection goes back to LISTEN (section 5.5).
            limit = 100 * S if self.plant == 'synack-r2-100' else 150 * S if self.plant == 'synack-r2-150' \
                else 180 * S
            if self.plant == 'synack-r2-at-timer':
                limit = None

            def r2(tt, c=c):
                if self.conns.get(c.key) is c and c.state == 'SYN-RECEIVED':
                    del self.conns[c.key]
            if limit is not None:
                self.at(t + limit, r2)
        if c.timer is None:
            self.arm(t, c)

    def send_tcp(self, t, c, flags, data, seq, opts=b''):
        src, sport, dport = c.key
        if self.plant == 'data-without-ack' and data:
            flags &= ~ACK
        win = 8192 if flags & SYN else self.window(c)
        self.raw_tcp(t, src, dport, sport, seq, c.rcv_nxt, flags, 4096 if self.plant == 'window' else win,
                     data, opts)

    def raw_tcp(self, t, dst, sport, dport, seq, ack, flags, win, data=b'', opts=b''):
        off = 5 + len(opts) // 4
        h = struct.pack('>HHIIHHHH', sport, dport, seq, ack, (off << 12) | flags, win, 0, 0) + opts
        pseudo = self.ip + dst + bytes([0, 6]) + struct.pack('>H', len(h) + len(data))
        c = csum(pseudo + h + data)
        if self.plant == 'tcp-checksum':
            c ^= 1
        if self.plant == 'tcp-checksum-zero':
            c = 0
        self.send_ip(t, dst, 6, h[:16] + struct.pack('>H', c) + h[18:] + data)


# --------------------------------------------------------------------------
# muir's side of the clocked socket.

class Clock:
    """Edges every GRID half-nanoseconds, the first at GRID."""

    def __init__(self, grid):
        self.grid = grid

    def edge_at_or_after(self, half_ns):
        return max(self.grid, -(-half_ns // self.grid) * self.grid)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--socket', required=True, help='the peer\'s UNIX socket')
    ap.add_argument('--mac', default='02:00:00:00:00:01')
    ap.add_argument('--ip', default='169.254.100.2')
    ap.add_argument('--prefix', type=int, default=30)
    ap.add_argument('--gateway', default='169.254.100.1')
    ap.add_argument('--ttl', type=int, default=64)
    ap.add_argument('--telnet-port', type=int, default=23)
    ap.add_argument('--echo-port', type=int, default=7)
    ap.add_argument('--boot-ns', type=int, default=50 * MS, help='when the network starts, machine ns')
    ap.add_argument('--microcycle-ns', type=float, default=8.5)
    ap.add_argument('--rtc', type=int, default=1700000000, help='seeds the ISN key, as the RTC does')
    ap.add_argument('--plant', help='a plant or variant, or several comma-separated')
    ap.add_argument('--timing', choices=('exact', 'tick'), default='exact',
                    help='tick: timers on 1/60 s ticks and seeded answer delays up to a tick')
    ap.add_argument('--seed', type=int, default=1, help='the tick mode\'s delays')
    a = ap.parse_args()
    a.plant = Plants(a.plant)
    for n in a.plant.names:
        if n not in PLANTS and n not in VARIANTS and n not in MEASURES:
            ap.error('no plant or variant %r' % n)
    if a.plant == 'pass-clock-restart' or a.plant == 'pass-busy':
        a.plant = Plants(a.plant + ',pass-order')
    # The pass model (MEASURES): every frame taken in the network process's
    # pass, when its seeded delay ends, and answered at once.
    passes = a.timing == 'tick' and a.plant == 'pass-order'

    clock = Clock(int(round(a.microcycle_ns * 2)))
    sent = []                   # (half-ns, frame) not yet reported
    last_tx = [0]
    # The stack's processing time before the device takes a frame, and the
    # device's 20 us transmit (section 2.4; docs of muir's device).
    proc, tx = 2 * 30_000, 2 * 20_000

    rng = random.Random(a.seed)
    tick2 = 2 * S // 60         # half-ns in a tick, rounded down

    def emit(t_ns, frame):
        if a.plant == 'pad-sent' and len(frame) < 60:
            frame = frame + bytes(60 - len(frame))
        t = t_ns * 2 + proc
        if a.timing == 'tick' and not band.in_timer and not passes:
            # The network process's pass: an answer takes up to a tick.  A
            # timer's own output goes at its tick.  (With the pass model the
            # frame itself is taken late instead, and answered at once.)
            t += rng.randrange(tick2)
        if band.in_timer:
            t += 2 * band.late
        t = max(t, last_tx[0]) + tx
        if a.plant == 'jitter':
            t += 2 * (int.from_bytes(os.urandom(2), 'big') % 1000)
        t = clock.edge_at_or_after(t)
        last_tx[0] = t
        sent.append((t, frame))

    band = Band(a, emit)
    band.rng = random.Random(a.seed + 1)
    if a.timing == 'tick':
        band.tick = True
    band.start()
    inbound = []                # heap of (half-ns, n, frame); n < 0 once taken late (passes)
    taken = [0]
    n = 0
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(a.socket)
    rf = s.makefile('rb')
    reached = 0
    target = 0
    while True:
        # Run to the first edge at or after the target: deliveries and
        # timers in time order, then report.
        end = clock.edge_at_or_after(max(target * 2, reached))
        while True:
            nxt = []
            if inbound and inbound[0][0] <= end:
                nxt.append((inbound[0][0], 0))
            if band.timers and band.timers[0][0] * 2 <= end:
                nxt.append((band.timers[0][0] * 2, 1))
            if not nxt:
                break
            t, kind = min(nxt)
            if kind == 0:
                _, k, f = heapq.heappop(inbound)
                if passes and k > 0:
                    # Delivered: taken when its seeded delay ends (0-1 ms, or
                    # with pass-busy up to a tick more), in order, its timers
                    # armed from then.  Each is
                    # taken at least a half-ns after the one before, so that
                    # no two share a time and the heap cannot reorder them
                    # (the peer never resends, so a reordered segment stalls).
                    delay = rng.randrange(2 * MS) + (rng.randrange(tick2) if a.plant == 'pass-busy' else 0)
                    taken[0] = max(t + delay, taken[0] + 1)
                    heapq.heappush(inbound, (taken[0], -k, f))
                    continue
                band.receive(t // 2, f)
            else:
                _, _, fn, tt, band.late = heapq.heappop(band.timers)
                band.in_timer = True
                if a.plant == 'pass-clock-restart':
                    # Timers reckoned from the clock read in their pass.
                    tt, band.late = tt + band.late, 0
                fn(tt)
                band.in_timer = False
                band.late = 0
        reached = end
        out = b''
        keep = []
        for t, f in sent:
            if t <= reached:
                out += HEAD.pack(len(f), t // 2) + f
            else:
                keep.append((t, f))
        sent[:] = keep
        out += HEAD.pack(0, reached // 2)
        try:
            s.sendall(out)
        except OSError:
            return 0
        # Records until a "run until".
        while True:
            h = rf.read(HEAD.size)
            if len(h) < HEAD.size:
                return 0
            length, t = HEAD.unpack(h)
            if length == 0:
                target = t
                break
            f = rf.read(length)
            n += 1
            # Delivered at the first edge at or after its time, never
            # before the time reached.
            heapq.heappush(inbound, (clock.edge_at_or_after(max(t * 2, reached)), n, f))


if __name__ == '__main__':
    sys.exit(main())
