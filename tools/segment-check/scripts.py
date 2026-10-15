"""The segment scripts (QUUX's Ethernet contract, section 9, T1): ARP,
ICMP echo, the handshake, MSS and other types (slice 0); data and options
(slice 1); IP and checksums received (slice 3).

Each script is a function of a Session.  It returns a line saying what it
saw when it passes, and raises session.Fail with a reason when the band does
not do what the contract says.  Every script first waits for the band's
gratuitous ARP (session.boot); only the ARP script fails without it, the
others go on and fail for their own reason.

The times a script waits are machine times: Params.answer (1 s by default)
for an answer, which leaves a band on muir's slowest clock room, and fixed
times named below where the contract gives one.
"""

import re

import frames as F
from session import Fail, MS, S, at

# The peer's ports and initial sequence numbers.  Fixed, so that two runs
# send the same Ethernet frames; the ISNs are far from 0 and from 2^31.
ISN_A = 0x1A2B3C4D
ISN_B = 0x5E6F7081


def subnet_broadcast(p):
    """The broadcast address of the band's subnet, from its address and
    prefix, so that the scripts follow the run's addresses."""
    n = int.from_bytes(p.band_ip, 'big') | (0xFFFFFFFF >> p.prefix)
    return n.to_bytes(4, 'big')


def tick_tolerance():
    """One clock tick, 1/60 s (section 2.6), the slack allowed on a rate."""
    return S // 60


# --------------------------------------------------------------------------
def other_mac(p):
    """A MAC address of the peer's other than its own, for the merge."""
    return p.peer_mac[:5] + bytes([p.peer_mac[5] ^ 0x80])


def peer_requests(s, lo, hi=None):
    """The band's ARP requests for the peer sent after LO (and up to HI)."""
    return [x for x in s.seen if x.arp and x.arp.op == F.ARP_REQUEST and x.arp.tpa == s.p.peer_ip
            and x.t > lo and (hi is None or x.t <= hi)]


def arp(s):
    """The band replies only to its own address, sends one gratuitous ARP,
    and sends at most one request a second; RFC 826's merge adds an entry
    only from a packet for the band and updates one from any; of two
    datagrams waiting on one resolution only the newer goes (section 5.2;
    F43, F44)."""
    p = s.p
    g = s.boot()
    if g is None:
        raise Fail('no gratuitous ARP by machine time %s' % at(s.now))
    if g.eth.dst != F.BROADCAST:
        raise Fail('the gratuitous ARP is sent to %s, not broadcast' % F.mac_text(g.eth.dst))

    # RFC 826's merge, before the band knows the peer: a request from the
    # peer for another address adds no entry, so the echo requests below
    # still need ARP requests.
    far = off_subnet(p)
    s.ether_to_band(F.ETH_ARP, F.arp(F.ARP_REQUEST, p.peer_mac, p.peer_ip, b'\0' * 6, far), dst=F.BROADCAST)

    # The rate.  Echo requests from the peer, which the band has not seen in
    # an ARP packet, every 250 ms for 3.5 s: to answer it must resolve the
    # peer, and the requests for it must be at least a second apart (one
    # tick of slack).  Nothing answers them here.
    s.arp_answer = False
    t0 = s.now + 10 * MS
    s.run(t0)
    for k in range(14):
        s.echo_request(0x4152, k, b'rate %02d' % k)
        s.run(s.now + 250 * MS)
    s.run(s.now + 500 * MS)
    reqs = [x for x in s.seen if x.t >= t0 and x.arp and x.arp.op == F.ARP_REQUEST and x.arp.tpa == p.peer_ip]
    if not reqs:
        if any(x.icmp is not None and x.icmp.type == F.ICMP_ECHO_REPLY for x in s.seen):
            raise Fail('echo replies to the peer with no ARP request: an entry added from the peer\'s ARP request '
                       'for another address, not for the band (RFC 826\'s merge, F44)')
        raise Fail('no ARP request for the peer %s by %s, with 14 echo requests waiting'
                   % (F.ip_text(p.peer_ip), at(s.now)))
    for a, b in zip(reqs, reqs[1:]):
        if b.t - a.t < S - tick_tolerance():
            raise Fail('two ARP requests for %s %d ns apart, at %s and %s: more than one a second'
                       % (F.ip_text(p.peer_ip), b.t - a.t, at(a.t), at(b.t)))
    rate_line = '%d requests for the peer in 3.5 s' % len(reqs)

    # Every resolution of the rate phase ends: three requests unanswered,
    # then the band's wait, and no fourth (F43).
    end = s.now + 10 * S
    while s.now < end and s.now - max([x.t for x in peer_requests(s, t0)] or [t0]) < 3 * S + TICK:
        s.run(s.now + 10 * MS)
    # Two echo requests waiting on one resolution: the newer replaces the
    # older (F43).
    s.echo_request(0x4155, 1, b'held older')
    s.run(s.now + 100 * MS)
    s.echo_request(0x4155, 2, b'held newer')
    s.run(s.now + 100 * MS)

    # A request for the band's own address gets a reply, to the asker; the
    # band learns the peer from it, and the held datagram goes.
    s.arp_answer = True
    s.ether_to_band(F.ETH_ARP, F.arp(F.ARP_REQUEST, p.peer_mac, p.peer_ip, b'\0' * 6, p.band_ip),
                    dst=F.BROADCAST)
    t1 = s.now
    r = s.wait_for(t1 + p.answer, lambda x: x.arp and x.arp.op == F.ARP_REPLY)
    if r is None:
        raise Fail('no ARP reply for the band\'s own address %s by %s' % (F.ip_text(p.band_ip), at(s.now)))
    if (r.arp.sha, r.arp.spa, r.arp.tha, r.arp.tpa) != (p.band_mac, p.band_ip, p.peer_mac, p.peer_ip):
        raise Fail('the ARP reply names the wrong addresses: %s' % r)
    s.run(t1 + p.answer)
    held = [x.icmp.seq for x in s.seen if x.t > t1 and x.icmp is not None and x.icmp.type == F.ICMP_ECHO_REPLY
            and x.icmp.ident == 0x4155]
    if held != [2]:
        raise Fail('of two echo requests waiting on one resolution the band answered %s, not the newer alone '
                   '(seq 2; the newest datagram is held, F43)' % (held or 'neither'))

    # The merge once the band knows the peer: a request from the peer for
    # another address, from another MAC address, updates the entry, and the
    # band's next datagram goes there with no request (F44); then back.
    for mac, what in ((other_mac(p), 'another MAC address'), (p.peer_mac, 'its own MAC address again')):
        s.peer_macs = (p.peer_mac, other_mac(p))
        s.ether_to_band(F.ETH_ARP, F.arp(F.ARP_REQUEST, mac, p.peer_ip, b'\0' * 6, far), dst=F.BROADCAST)
        s.run(s.now + 50 * MS)
        t2 = s.now
        s.echo_request(0x4156, 1 if mac != p.peer_mac else 2, b'merge')
        e = s.wait_for(t2 + p.answer, lambda x: x.icmp is not None and x.icmp.type == F.ICMP_ECHO_REPLY)
        if peer_requests(s, t2):
            raise Fail('an ARP request for the peer after its ARP request gave %s: %s' % (what, peer_requests(s, t2)[0]))
        if e is None:
            raise Fail('no echo reply after the peer\'s ARP request gave %s, by %s' % (what, at(s.now)))
        if e.eth.dst != mac:
            raise Fail('the echo reply went to %s, not %s, the MAC address the peer\'s ARP request for another '
                       'address gave (RFC 826\'s merge, F44)' % (F.mac_text(e.eth.dst), F.mac_text(mac)))
    s.peer_macs = None

    # Requests for other addresses get none: the peer's own, another on no
    # subnet of the band's, and the /30's broadcast.
    for other in (p.peer_ip, F.ip('192.0.2.9'), subnet_broadcast(p)):
        s.ether_to_band(F.ETH_ARP, F.arp(F.ARP_REQUEST, p.peer_mac, F.ip('192.0.2.1'), b'\0' * 6, other),
                        dst=F.BROADCAST)
        s.quiet(s.now + p.answer, lambda x: x.arp and x.arp.op == F.ARP_REPLY,
                'an ARP reply for %s, not the band\'s address' % F.ip_text(other))

    gs = [x for x in s.seen if s.is_gratuitous(x)]
    if len(gs) != 1:
        raise Fail('%d gratuitous ARPs, at %s; one is sent' % (len(gs), ', '.join(at(x.t) for x in gs)))
    return 'gratuitous ARP at %s; %s; the newer held datagram sent; the merge followed; own address answered; ' \
           '3 others not' % (at(g.t), rate_line)


# --------------------------------------------------------------------------
ECHOES = [
    (0x1234, 1, bytes(range(56))),                         # ping's own size
    (0xFFFF, 0xFFFF, bytes((7 * i) & 255 for i in range(57))),  # an odd length
    (0x0000, 0x0000, b''),                                 # no data
    (0x8001, 0x7FFF, bytes((i * 13 + 5) & 255 for i in range(1472))),  # the largest unfragmented
]


def icmp_echo(s):
    """Every echo request for the band's address gets a reply with the
    same identifier, sequence and data (section 5.4)."""
    p = s.p
    s.boot()
    for ident, seq, data in ECHOES:
        s.echo_request(ident, seq, data)
        t = s.now
        r = s.wait_for(t + p.answer, lambda x: x.icmp is not None and x.icmp.type == F.ICMP_ECHO_REPLY)
        if r is None:
            raise Fail('no echo reply to id %d seq %d (%d data bytes) by %s' % (ident, seq, len(data), at(s.now)))
        m = r.icmp
        if (m.ident, m.seq) != (ident, seq):
            raise Fail('the echo reply to id %d seq %d says id %d seq %d' % (ident, seq, m.ident, m.seq))
        if m.data != data:
            k = next((i for i, (a, b) in enumerate(zip(m.data, data)) if a != b), min(len(m.data), len(data)))
            raise Fail('the echo reply to id %d seq %d changed its data: %d bytes for %d, first difference at %d'
                       % (ident, seq, len(m.data), len(data), k))
        if r.ip.dst != p.peer_ip:
            raise Fail('the echo reply goes to %s' % F.ip_text(r.ip.dst))
    return '%d echoes answered with their fields kept' % len(ECHOES)


# --------------------------------------------------------------------------
def open_connection(s, sport, dport, iss, options, what, window=65535):
    """SYN; return the PeerConn with its SYN-ACK checked: SYN and ACK only,
    acknowledging the SYN."""
    c = s.connect(sport, dport, iss, options, window)
    c.auto_ack = False
    s.wait_for(s.now + s.p.answer, lambda x: c.ours(x))
    if c.rst is not None:
        raise Fail('%s: the SYN to port %d is answered by RST: %s' % (what, dport, c.rst))
    if c.synack is None:
        other = next((x for x in c.segments), None)
        if other is not None:
            raise Fail('%s: the SYN to port %d is answered by %s, not a SYN-ACK' % (what, dport, other))
        raise Fail('%s: no SYN-ACK from port %d by %s' % (what, dport, at(s.now)))
    t = c.synack.tcp
    if t.flags != F.SYN | F.ACK:
        raise Fail('%s: the SYN-ACK has flags %s' % (what, F.flags_text(t.flags)))
    if t.ack != (iss + 1) & 0xFFFFFFFF:
        raise Fail('%s: the SYN-ACK acknowledges %d, not %d' % (what, t.ack, (iss + 1) & 0xFFFFFFFF))
    return c


def refused(s, c, what):
    """C's SYN was refused with an RST of RFC 9293 section 3.10.7.1's form,
    which a connecting Linux accepts: <SEQ=0><ACK=the SYN's + 1><CTL=RST,ACK>
    (F20)."""
    r = c.rst
    if r is None:
        raise Fail('%s: no RST by %s' % (what, at(s.now)))
    if r.tcp.flags & (F.RST | F.ACK) != F.RST | F.ACK or r.tcp.seq != 0 or r.tcp.ack != (c.iss + 1) & 0xFFFFFFFF:
        raise Fail('%s: %s, not RST-ACK of the SYN (seq 0, ack %d)' % (what, r, (c.iss + 1) & 0xFFFFFFFF))


def handshake(s):
    """A SYN is answered by a SYN-ACK with MSS 1460 and window 8192, and
    the banner follows the ACK (section 9, T1; section 5.5)."""
    p = s.p
    s.boot()
    c = open_connection(s, 40001, p.telnet_port, ISN_A, F.linux_syn_options(), 'the handshake')
    t = c.synack.tcp
    if t.mss != 1460:
        raise Fail('the SYN-ACK\'s MSS is %s, not 1460' % t.mss)
    if t.window != 8192:
        raise Fail('the SYN-ACK\'s window is %d, not 8192' % t.window)
    # Hold the ACK for 300 ms, well inside the first RTO of 1 s: nothing
    # but the SYN-ACK's own retransmission may come meanwhile.
    s.quiet(s.now + 300 * MS, lambda x: c.ours(x) and not x.tcp.flags & F.SYN,
            'a segment before the handshake\'s ACK')
    if c.data_segments:
        raise Fail('data before the ACK: %s' % c.data_segments[0])
    c.ack()
    t_ack = s.now
    c.auto_ack = True
    d = s.wait_for(t_ack + 2 * p.answer, lambda x: c.ours(x) and len(x.tcp.data) > 0)
    if d is None:
        raise Fail('no banner by %s, %s after the ACK' % (at(s.now), at(s.now - t_ack)))
    if d.tcp.seq != c.irs + 1 & 0xFFFFFFFF:
        raise Fail('the banner starts at %d, not at the SYN-ACK\'s %d + 1' % (d.tcp.seq, c.irs))
    if c.rst is not None:
        raise Fail('RST after the ACK: %s' % c.rst)
    s.run(s.now + 100 * MS)
    return 'SYN-ACK at %s with MSS 1460 window 8192; banner of %d bytes from %s' % (
        at(c.synack.t), len(c.received), at(d.t))


# --------------------------------------------------------------------------
# --------------------------------------------------------------------------
# The control session (PROPOSED term; contract section 9, T1, "The way in"):
# a TELNET session of the script's own to port 23, on which it types fixed
# forms at fixed machine times and waits for a marker each form prints.  The
# marker is built by FORMAT from its pieces, so the listener's echo of the
# typed form never contains it.
#
# PLACEHOLDERS: the Lisp names below are not the band's.  muir-sys names the
# test switch and the driver's totals at E4, here and nowhere else; the
# stand-in band answers these forms by this table.
#
# Each form is a %-template: its %d are the arguments ask() gives, and a
# literal % is written %%.
# What each form does is fixed (F36, contract section 9, T1, "The way in");
# only the names are placeholders.
CONTROL = {
    # The test echo service's switch (section 7): port 7 opens.
    'echo-on': ('(progn (setq net:*test-echo-service* t) (format t "~%%{sc-~a}~%%" "echo-on"))',
                r'\{sc-echo-on\}'),
    # The driver's totals of status 241 <7:4>, the type filter, and <15:9>,
    # the IPv4 checks (section 5.1).
    'totals': ('(format t "~%%{sc-totals ~d ~d}~%%" (net:type-filter-total) (net:ipv4-checks-total))',
               r'\{sc-totals (\d+) (\d+)\}'),
    # The last condition the test echo service's stream signalled (section
    # 7), by name; NIL for none.
    'condition': ('(format t "~%%{sc-~a ~a}~%%" "condition" (net:test-echo-service-condition))',
                  r'\{sc-condition (\S+)\}'),
    # A close by the band of the connection whose foreign port is the
    # argument: the application's own close, the stream's :CLOSE without
    # abort, not :EOF.  The band then sends on it only what TCP sends: a
    # later close of that stream by its server, with abort or without,
    # sends nothing (section 9, T1, Close; F36).
    'close': ('(progn (net:close-connection-from-port %d) (format t "~%%{sc-~a ~d}~%%" "closed" %d))',
              r'\{sc-closed (\d+)\}'),
    # The ISN hook: NIL, or an ISN as on the wire, 0 to 2^32 - 1 (a bignum
    # above QUUX's largest fixnum; the band converts it once).  The next SYN
    # the band answers with a SYN-ACK takes it, and it is then NIL; a SYN
    # dropped or refused leaves it set (section 9, T1, Sequence wrap; F6,
    # F36).
    'isn-next': ('(progn (setq net:*isn-of-next-connection* %d) (format t "~%%{sc-~a}~%%" "isn-set"))',
                 r'\{sc-isn-set\}'),
    # The R2 hook: NIL, or a number of seconds.  The next connection the
    # test echo service accepts gets it as its R2, through section 5.5's
    # keyword (MUST-21), and it is then NIL (F41).
    'r2-next': ('(progn (setq net:*r2-of-next-connection* %d) (format t "~%%{sc-~a}~%%" "r2-set"))',
                r'\{sc-r2-set\}'),
    # The urgent state of the connection whose foreign port is the
    # argument: two numbers, 1 or 0 for urgent data waiting or not, and how
    # much, the octets from the next one the server reads up to the urgent
    # pointer, those not yet received included; "0 0" when it has no urgent
    # pointer or the server has read up to it (section 5.5; F32, F36).
    'urgent': ('(multiple-value-bind (w n) (net:urgent-state-of-port %d) '
               '(format t "~%%{sc-~a ~d ~d}~%%" "urgent" (if w 1 0) (or n 0)))',
               r'\{sc-urgent (\d+) (\d+)\}'),
    # The band's ping of a dotted address: one echo request.  It waits at
    # least 1 s for the reply that matches it by identifier and sequence,
    # ignores any other, and reports that reply's identifier and sequence,
    # or nothing (NIL NIL) (section 5.4; F5, F36).
    'ping': ('(multiple-value-bind (id seq) (net:ping "%d.%d.%d.%d") '
             '(format t "~%%{sc-~a ~a ~a}~%%" "pinged" id seq))',
             r'\{sc-pinged (\S+) (\S+)\}'),
}
CONTROL_PORT = 40099


def control(s):
    """Open the control session and let it settle."""
    c = open_connection(s, CONTROL_PORT, s.p.telnet_port, ISN_B ^ 0x00FF00FF, F.opt_mss(1460),
                        'the control session')
    settled(s, c, 'the control session')
    c.auto_ack = True
    return c


def ask(s, c, name, *args, wait=2 * S):
    """Type CONTROL[NAME]'s form, with ARGS, on the control session and
    return the groups of its marker, read from what the band sends after
    it: numbers as ints, names as strings."""
    form, marker = CONTROL[name]
    mark = len(c.received)
    c.write((form % args).encode() + b'\r')
    end = s.now + wait
    while s.now < end:
        s.run(s.now + s.p.step)
        m = re.search(marker.encode(), c.received[mark:])
        if m:
            return [int(g) if g.isdigit() else g.decode() for g in m.groups()]
        if c.rst is not None:
            raise Fail('the control session was reset: %s' % c.rst)
    raise Fail('no marker for the control form %r by %s' % (name, at(s.now)))


ECHO_BYTES = 4000


def echo_through(s, sport, iss, options, limit, what, data_bytes=ECHO_BYTES, window=65535, ack_quiet=0):
    """Open a connection to the echo service, send DATA_BYTES and take them
    back; every data segment the band sends must be at most LIMIT bytes,
    and the largest must be LIMIT exactly (contract section 9, T1, MSS:
    1,460-byte segments are echoed, and the service reads what has
    arrived)."""
    p = s.p
    c = open_connection(s, sport, p.echo_port, iss, options, what, window)
    c.ack_quiet = ack_quiet
    c.auto_ack = True
    c.ack()
    data = bytes((i * 31 + sport) & 255 for i in range(data_bytes))
    c.write(data)
    deadline = s.now + 5 * S
    while s.now < deadline and len(c.received) < len(data) and c.rst is None:
        s.run(s.now + p.step)
    if c.rst is not None:
        raise Fail('%s: RST from the echo service: %s' % (what, c.rst))
    sizes = [len(x.tcp.data) for x in c.data_segments]
    over = [x for x in c.data_segments if len(x.tcp.data) > limit]
    if over:
        raise Fail('%s: a segment of %d data bytes, over %d: %s' % (what, len(over[0].tcp.data), limit, over[0]))
    if len(c.received) < len(data):
        raise Fail('%s: %d of %d bytes echoed by %s' % (what, len(c.received), len(data), at(s.now)))
    # Exactly the bytes sent, once: nothing more comes in a quiet period.
    quiet_on(s, c, what)
    if c.received != data:
        raise Fail('%s: the echo is %d bytes for the %d sent, %s' % (
            what, len(c.received), len(data), 'the same at first' if c.received[:len(data)] == data else 'differing'))
    if max(sizes) != limit:
        raise Fail('%s: the largest segment is %d bytes, not %d' % (what, max(sizes), limit))
    # PSH on the first transmission of the segment that ends the echo: a
    # resend of it may come later and carry PSH or not (with the window of
    # 1,072 the last octet is resent, so the last segment seen is a resend).
    end = (c.irs + 1 + len(c.received)) & 0xFFFFFFFF
    last = next((x for x in c.data_segments if (x.tcp.seq + len(x.tcp.data)) & 0xFFFFFFFF == end), None)
    if last is None or not last.tcp.flags & F.PSH:
        raise Fail('%s: the last segment of the echo, a push, has no PSH (MUST-61): %s' % (
            what, last or 'no segment ends the echo'))
    return max(sizes)


# An unknown option before an unaligned MSS: a parser that stops at the
# unknown kind never sees the MSS.
OPT_UNKNOWN_THEN_MSS = b'\xfe\x03\x00' + F.opt_mss(65480)


def mss(s):
    """Port 7 is closed until the test switch is on (section 7); then a SYN
    without MSS makes the band send segments of 536 bytes at most and at
    largest, one with MSS 65480 (behind an unknown option) of 1,460, and a
    window of 1,072 offered by the peer is never passed (section 5.5;
    MUST-15, -16)."""
    p = s.p
    s.boot()
    d = s.connect(40005, p.echo_port, ISN_A ^ 0x5555, F.opt_mss(1460))
    s.wait_for(s.now + p.answer, lambda x: d.ours(x))
    if d.synack is not None:
        raise Fail('port 7 open before the test switch: %s' % d.synack)
    refused(s, d, 'the closed port 7')
    s.conns.remove(d)
    c = control(s)
    ask(s, c, 'echo-on')
    a = echo_through(s, 40002, ISN_A, b'', 536, 'no MSS')
    b = echo_through(s, 40003, ISN_B, OPT_UNKNOWN_THEN_MSS, 1460, 'MSS 65480')
    # 1,073 bytes into a window of 1,072: the last byte must wait for the
    # window to open.  The peer holds its ACKs until the band has been quiet
    # 300 ms, longer than the override timer and a GC pause and less than
    # the first RTO (F15), so that a byte past the edge is sent before any
    # new edge is offered and the check cannot excuse it.
    echo_through(s, 40006, ISN_A ^ 0xAAAA, F.opt_mss(536), 536, 'a window of 1072', data_bytes=1073,
                 window=1072, ack_quiet=QUIET)
    return 'port 7 closed, then opened; largest segment %d with no MSS, %d with MSS 65480; window 1072 kept' % (
        a, b)


# --------------------------------------------------------------------------
def ipv6_frame(p, dst):
    """An ICMPv6 echo request from a link-local address: an IPv6 Ethernet
    frame a Linux host might send."""
    body = bytes([128, 0, 0, 0, 0x12, 0x34, 0, 1]) + b'segment script'
    src6 = bytes.fromhex('fe800000000000000000000000000002')
    dst6 = bytes.fromhex('fe800000000000000000000000000001')
    head = bytes([0x60, 0, 0, 0]) + len(body).to_bytes(2, 'big') + bytes([58, 64]) + src6 + dst6
    return F.ether(dst, p.peer_mac, F.ETH_IPV6, head + body)


def chaos_frame(p, dst):
    """A 0x0804 Ethernet frame, Chaosnet's type, which QUUX no longer takes."""
    return F.ether(dst, p.peer_mac, F.ETH_CHAOS, bytes(16) + b'RFC TELNET' + bytes(24))


def other_types(s):
    """An IPv6 Ethernet frame and a 0x0804 one sent to the band get no
    answer, the driver's total of the type filter's count rises by exactly
    the number sent, and a session in progress, the control session, goes
    on unharmed (section 9, T1; the type filter, section 2.4)."""
    p = s.p
    s.boot()
    c = control(s)
    before = ask(s, c, 'totals')
    s.run(s.now + 200 * MS)
    for dst in (p.band_mac, F.BROADCAST):
        s.send(ipv6_frame(p, dst))
        s.send(chaos_frame(p, dst))
    # Anything but the session's own segments is an answer.
    s.quiet(s.now + p.answer, lambda x: not c.ours(x), 'an answer to an IPv6 or 0x0804 Ethernet frame')
    if c.rst is not None:
        raise Fail('the session was reset after the other types: %s' % c.rst)
    after = ask(s, c, 'totals')
    if after[0] - before[0] != 4:
        raise Fail('the type filter\'s total rose by %d, not by the 4 sent' % (after[0] - before[0]))
    # The session goes on: an old duplicate byte is acknowledged and not
    # delivered (section 5.5), so the band answers without the server
    # seeing anything.
    # The listener's own output carries the same ACK, so the session
    # settles first: then only the old duplicate can be answered.
    quiet_on(s, c, 'the control session')
    c.auto_ack = False
    c.segment(0, b'\0', seq=(c.snd_nxt - 1) & 0xFFFFFFFF)
    t = s.now
    r = s.wait_for(t + p.answer, lambda x: x.t > t and c.ours(x) and x.tcp.flags & (F.ACK | F.RST))
    if r is None:
        raise Fail('the session gave no ACK of an old duplicate by %s, after the other types' % at(s.now))
    if r.tcp.flags & F.RST:
        raise Fail('the session answered RST after the other types: %s' % r)
    if r.tcp.ack != c.snd_nxt:
        raise Fail('the session\'s ACK is %d, not %d' % (r.tcp.ack, c.snd_nxt))
    return 'no answer to 4 other-type Ethernet frames, the total up by 4; the session acknowledges at %s' % at(r.t)


# --------------------------------------------------------------------------
# Slice 1: data and options, on the test echo service (port 7, after the
# control session's switch), so that what the band delivers comes back and
# is checked: every byte once, in order.  An ACK is read where the band's
# segments settle, not from the first one after a send: a server's output
# built before the band took a segment carries the older ACK (contract
# section 9, T1, Data, F18).

QUIET = 300 * MS


def stream(n):
    """The peer's N bytes, each different from its neighbours."""
    return bytes((i * 37 + 11) & 255 for i in range(n))


def settled(s, c, what, quiet=QUIET, limit=5 * S):
    """A session, its first output (a banner) taken and acknowledged, and
    the band quiet on it for QUIET."""
    c.ack()
    c.auto_ack = True
    quiet_on(s, c, what, quiet, limit)
    c.auto_ack = False


def quiet_on(s, c, what, quiet=QUIET, limit=5 * S):
    """Run until the band has been quiet on C for QUIET."""
    end = s.now + limit
    last = s.now
    while s.now < end and s.now - last < quiet:
        for x in s.run(s.now + s.p.step):
            if c.ours(x):
                last = x.t
    if c.rst is not None:
        raise Fail('%s: RST on the session: %s' % (what, c.rst))
    if s.now - last < quiet:
        raise Fail('%s: the session never went quiet for %s by %s' % (what, at(quiet), at(s.now)))


def rel(c, a):
    """ACK number A as an offset from the peer's first data byte."""
    return (a - c.iss - 1 + 2 ** 31) % 2 ** 32 - 2 ** 31


def send_data(s, c, offset, n, options=b''):
    """N bytes of the stream at OFFSET from the peer's first data byte.  The
    peer's SND.NXT is the end of the furthest byte it has sent, so that its
    own ACKs stay in the band's window."""
    base = (c.iss + 1) & 0xFFFFFFFF
    seq = (base + offset) & 0xFFFFFFFF
    c.segment(F.PSH, stream(offset + n)[offset:], seq=seq, options=options)
    end = (seq + n) & 0xFFFFFFFF
    if 0 < ((end - c.snd_nxt) & 0xFFFFFFFF) < 0x80000000:
        c.snd_nxt = end
    return s.now


def expect_ack(s, c, t, offset, what):
    """The band's segments on C after T, until it is quiet for QUIET:
    none acknowledges past OFFSET, none is an RST, and the last
    acknowledges OFFSET exactly."""
    want = (c.iss + 1 + offset) & 0xFFFFFFFF
    end = t + s.p.answer + 5 * S
    last = None
    while s.now < end:
        for x in s.run(s.now + s.p.step):
            if x.t > t and c.ours(x):
                if x.tcp.flags & F.RST:
                    raise Fail('%s: RST: %s' % (what, x))
                if 0 < ((x.tcp.ack - want) & 0xFFFFFFFF) < 0x80000000:
                    raise Fail('%s: ACK %+d from the first data byte, past %+d' % (what, rel(c, x.tcp.ack), offset))
                last = x
        if last is not None and s.now - last.t >= QUIET:
            break
        if last is None and s.now - t > s.p.answer:
            raise Fail('%s: no ACK by %s' % (what, at(s.now)))
    if last is None or s.now - last.t < QUIET:
        raise Fail('%s: the band never went quiet by %s' % (what, at(s.now)))
    if last.tcp.ack != want:
        raise Fail('%s: ACK %+d from the first data byte, not %+d' % (what, rel(c, last.tcp.ack), offset))
    return last


def echo_session(s, sport, iss, options, what):
    """The control session's switch, then a quiet connection to the test
    echo service whose echoes the peer acknowledges."""
    c = control(s)
    ask(s, c, 'echo-on')
    e = open_connection(s, sport, s.p.echo_port, iss, options, what)
    e.ack()
    quiet_on(s, e, what)
    e.auto_ack = True
    return e


def delivered(s, e, n, what):
    """After the band is quiet, the echo is the stream's first N bytes,
    each once and in order: what the service was given."""
    quiet_on(s, e, what)
    want = stream(n)
    if e.received != want:
        k = next((i for i, (x, y) in enumerate(zip(e.received, want)) if x != y), min(len(e.received), n))
        raise Fail('%s: the echo service got %d bytes for %d, differing from byte %d on'
                   % (what, len(e.received), n, k))


def data(s):
    """In order, data is acknowledged and delivered once; a duplicate is
    acknowledged and not delivered; out of order it gets a duplicate ACK
    and is dropped, taken only when it is resent after the gap; an overlap
    delivers its new part only (section 5.5, in-order delivery only;
    section 9, T1, Data, F18)."""
    s.boot()
    # The peer's ISN 10 below 2^32, so that its data crosses the wrap at
    # byte 9 and every comparison of the band's must be modulo 2^32.
    c = echo_session(s, 40011, 0xFFFFFFF6, F.opt_mss(1460), 'data')
    expect_ack(s, c, send_data(s, c, 0, 4), 4, 'in order, 4 bytes')
    expect_ack(s, c, send_data(s, c, 0, 4), 4, 'the same 4 bytes again')
    expect_ack(s, c, send_data(s, c, 8, 4), 4, 'out of order, bytes 8-11 before 4-7')
    expect_ack(s, c, send_data(s, c, 4, 4), 8, 'the gap, bytes 4-7, resent')
    expect_ack(s, c, send_data(s, c, 8, 4), 12, 'bytes 8-11 resent after the gap')
    expect_ack(s, c, send_data(s, c, 8, 8), 16, 'an overlap, bytes 8-15 of which 12-15 are new')
    expect_ack(s, c, send_data(s, c, 6, 2), 16, 'an old segment inside the data taken')
    delivered(s, c, 16, 'data')
    return 'in order, duplicate, out of order, gap, overlap: every ACK as section 5.5 says; 16 bytes echoed once'


# Option lists, raw, as section 9 asks: unknown, NOP-padded and unaligned.
OPT_SYN_UNALIGNED = b'\x01\x02\x04\x05\xb4\xfe\x04\xab\xcd\x01\x00'   # NOP, MSS, unknown 254
OPT_UNKNOWN = b'\xfd\x06\x01\x02\x03\x04\x01\x01'                     # unknown 253, 2 NOPs
OPT_UNALIGNED = b'\x01\xfe\x03\x07\x01\x01\x01\x01'                   # NOP, unknown 254 of 3
OPT_ZERO = b'\xfe\x00\x00\x00'                                            # length 0
OPT_ONE = b'\x01\xfe\x01\x00'                                             # length 1
OPT_OVERLONG = b'\x01\x01\xfe\x0c'                                         # 12 bytes in 2


def options(s):
    """Unknown, NOP-padded and unaligned options are handled in a SYN and
    in data segments; a zero, one-byte or overlong option length drops the
    segment: the ACK does not move (a duplicate ACK is allowed), nothing is
    delivered, the connection is not reset, and the same bytes with good
    options are taken after (section 5.5; MUST-5, -6, -7, -64; F16)."""
    p = s.p
    s.boot()
    # A SYN whose only legal options are unaligned, with an unknown one.
    c = echo_session(s, 40012, ISN_A, OPT_SYN_UNALIGNED, 'a SYN with unaligned options')
    expect_ack(s, c, send_data(s, c, 0, 2, OPT_UNKNOWN), 2, 'data with an unknown option')
    expect_ack(s, c, send_data(s, c, 2, 2, OPT_UNALIGNED), 4, 'data with unaligned options')
    for opt, what in ((OPT_ZERO, 'a zero option length'), (OPT_ONE, 'an option length of 1'),
                      (OPT_OVERLONG, 'an overlong option length')):
        t = send_data(s, c, 4, 2, opt)
        s.quiet(t + p.answer, lambda x: c.ours(x) and x.tcp.flags & F.RST,
                'data with %s answered by RST' % what)
        moved = [x for x in c.segments if x.t > t and x.tcp.ack != (c.iss + 5) & 0xFFFFFFFF]
        if moved:
            raise Fail('data with %s taken, not dropped: %s' % (what, moved[0]))
    # The band goes on: the same bytes with good options are taken.
    expect_ack(s, c, send_data(s, c, 4, 2, F.OPT_NOP * 4), 6, 'after the dropped segments, data with NOPs')
    delivered(s, c, 6, 'options')
    # A SYN with an illegal option length gets nothing; then a good one is answered.
    d = s.connect(40013, p.echo_port, ISN_B, OPT_OVERLONG)
    s.quiet(s.now + p.answer, lambda x: d.ours(x), 'a SYN with an overlong option length answered')
    s.conns.remove(d)
    e = open_connection(s, 40014, p.echo_port, ISN_B, F.opt_mss(1460), 'a good SYN after the bad one')
    return 'unknown, NOP-padded and unaligned options taken; 3 illegal lengths dropped; 6 bytes echoed once; ' \
           'SYN-ACK at %s' % at(e.synack.t)


# --------------------------------------------------------------------------
# Slice 3: IP and checksums received (sections 2.4 and 5.3).

def echo_answered(s, ident, seq, what, **kw):
    """An echo request, and its reply with its fields kept."""
    data = b'segment script %s' % what.encode()
    s.ipv4_to_band(F.IP_ICMP, F.icmp(F.ICMP_ECHO, 0, ident, seq, data), **kw)
    t = s.now
    r = s.wait_for(t + s.p.answer, lambda x: x.icmp is not None and x.icmp.type == F.ICMP_ECHO_REPLY)
    if r is None:
        raise Fail('no echo reply to %s by %s' % (what, at(s.now)))
    if (r.icmp.ident, r.icmp.seq, r.icmp.data) != (ident, seq, data):
        raise Fail('the echo reply to %s does not keep its fields: %s' % (what, r))
    return r


def unanswered(s, what):
    """Nothing but ARP and the control session's own segments comes."""
    s.quiet(s.now + s.p.answer,
            lambda x: x.arp is None and not (x.tcp is not None and x.tcp.dport == CONTROL_PORT),
            '%s answered' % what)


def flip(c):
    """A checksum wrong by one bit."""
    return c ^ 0x0100


def checksums_received(s):
    """A bad IPv4 header, ICMP or TCP checksum is dropped by the device and
    gets no answer (section 9, T1, IP; section 2.4)."""
    p = s.p
    s.boot()
    echo_answered(s, 0x0301, 1, 'the control echo')
    c = control(s)
    before = ask(s, c, 'totals')
    good = F.icmp(F.ICMP_ECHO, 0, 0x0301, 2, b'bad header checksum')
    h = F.ipv4(p.peer_ip, p.band_ip, F.IP_ICMP, good)
    s.ether_to_band(F.ETH_IPV4, F.ipv4(p.peer_ip, p.band_ip, F.IP_ICMP, good,
                                      csum=flip(F.checksum(h[:10] + b'\0\0' + h[12:20]))))
    unanswered(s, 'an echo with a bad IPv4 header checksum')
    m = F.icmp(F.ICMP_ECHO, 0, 0x0301, 3, b'bad ICMP checksum')
    m = m[:2] + bytes([m[2] ^ 0x01, m[3]]) + m[4:]
    s.ipv4_to_band(F.IP_ICMP, m)
    unanswered(s, 'an echo with a bad ICMP checksum')
    seg = F.tcp(p.peer_ip, p.band_ip, 40021, p.telnet_port, ISN_A, 0, F.SYN, 65535, options=F.opt_mss(1460))
    seg = seg[:16] + bytes([seg[16] ^ 0x01, seg[17]]) + seg[18:]
    s.ipv4_to_band(F.IP_TCP, seg)
    unanswered(s, 'a SYN with a bad TCP checksum')
    # Section 2.4.2's lengths for the checked protocols: an ICMP message of
    # 4 bytes, a TCP segment of 12, and a UDP datagram whose length field
    # says 20 for its 12 bytes (with no checksum, 0).  The device drops each
    # by its length, whatever its checksum.
    c4 = F.checksum(bytes([F.ICMP_ECHO, 0, 0, 0]))
    s.ipv4_to_band(F.IP_ICMP, bytes([F.ICMP_ECHO, 0, c4 >> 8, c4 & 255]))   # its checksum right
    unanswered(s, 'an ICMP message of 4 bytes')
    short = F.tcp(p.peer_ip, p.band_ip, 40022, p.telnet_port, ISN_A, 0, F.SYN, 65535)[:12]
    s.ipv4_to_band(F.IP_TCP, short)
    unanswered(s, 'a TCP segment of 12 bytes')
    udp = (40023).to_bytes(2, 'big') + (9).to_bytes(2, 'big') + (20).to_bytes(2, 'big') + bytes(2) + b'udp!'
    s.ipv4_to_band(17, udp)
    unanswered(s, 'a UDP datagram whose length is not its own')
    after = ask(s, c, 'totals')
    if after[1] - before[1] != 6:
        raise Fail('the IPv4 checks\' total rose by %d, not by the 6 bad ones sent' % (after[1] - before[1]))
    if after[0] != before[0]:
        raise Fail('the type filter\'s total moved by %d' % (after[0] - before[0]))
    echo_answered(s, 0x0301, 4, 'the echo after them')
    c = open_connection(s, 40021, p.telnet_port, ISN_A, F.opt_mss(1460), 'the SYN after them')
    return ('bad IPv4 header, ICMP and TCP checksums and 3 bad lengths unanswered and counted; the band answers '
            'after them (SYN-ACK at %s)' % at(c.synack.t))


# IPv4 options: 4 NOPs and a record route of two slots; loose and strict
# source routes through 192.0.2.1.
IP_OPT_RR = b'\x01\x01\x01\x01' + bytes([7, 11, 4]) + bytes(8)
IP_OPT_LSRR = b'\x01' + bytes([131, 7, 4]) + bytes([192, 0, 2, 1])
IP_OPT_SSRR = b'\x01' + bytes([137, 7, 4]) + bytes([192, 0, 2, 1])


def ip_options(s):
    """IPv4 options are skipped, a loose or strict source route drops the
    datagram, fragments drop, and so do datagrams to another address or of
    another protocol (sections 5.3 and 9, T1, IP)."""
    p = s.p
    s.boot()
    echo_answered(s, 0x0302, 1, 'the control echo')
    # Every Ethernet frame below passes the device: neither total moves
    # (F17: a fragment is counted only for its header).
    c = control(s)
    before = ask(s, c, 'totals')
    r = echo_answered(s, 0x0302, 2, 'an echo with NOPs and a record route', options=IP_OPT_RR)
    for opt, what in ((IP_OPT_LSRR, 'a loose source route'), (IP_OPT_SSRR, 'a strict source route')):
        s.ipv4_to_band(F.IP_ICMP, F.icmp(F.ICMP_ECHO, 0, 0x0302, 3, b'source route'), options=opt)
        unanswered(s, 'an echo with %s' % what)
    # Each fragment carries a whole echo request with a right checksum, so
    # that a band that took fragments would answer it.
    whole = F.icmp(F.ICMP_ECHO, 0, 0x0302, 4, bytes(range(32)))
    s.ipv4_to_band(F.IP_ICMP, whole, mf=True, ident=0x77)
    unanswered(s, 'a first fragment (MF set) holding a whole echo')
    s.ipv4_to_band(F.IP_ICMP, whole, offset=2, ident=0x78)
    unanswered(s, 'a later fragment (offset 16 bytes) holding a whole echo')
    for dst in (subnet_broadcast(p), F.ip('192.0.2.9')):
        s.ether_to_band(F.ETH_IPV4, F.ipv4(p.peer_ip, dst, F.IP_ICMP,
                                          F.icmp(F.ICMP_ECHO, 0, 0x0302, 5, b'not the band')))
        unanswered(s, 'an echo to %s' % F.ip_text(dst))
    udp = (40031).to_bytes(2, 'big') + (9).to_bytes(2, 'big') + (12).to_bytes(2, 'big') + bytes(2) + b'udp!'
    s.ipv4_to_band(17, udp)
    unanswered(s, 'a UDP datagram')
    s.ipv4_to_band(47, bytes(8))
    unanswered(s, 'a protocol 47 datagram')
    after = ask(s, c, 'totals')
    if after != before:
        raise Fail('the totals moved from %s to %s, for Ethernet frames that pass the device' % (before, after))
    echo_answered(s, 0x0302, 6, 'the echo after them')
    return 'options skipped (reply at %s); source routes, fragments, other addresses and protocols unanswered' % (
        at(r.t))


# --------------------------------------------------------------------------
# Slice 2: RST, SYN and close (section 5.5; section 9, T1).

TICK = -(-S // 60)      # 1/60 s, rounded up to the nanosecond
# The pass latency (section 9, T1, Latency; F45): the most the band's
# network process starts its pass after a tick, or posts a timer's segment
# after its due time.  A timer checked within a tick may be up to a tick
# early, and up to a tick and this late (near()); a probe that a record has
# ended goes a tick and this after its end is due, since the record ends in
# the pass at the first tick at or after that, and the pass takes every
# waiting Ethernet frame before it runs the timers (section 5.1).  A T1
# parameter, 1 ms until E4 measures it; this is its one place.
PASS_LATENCY = 1 * MS


def settled_conn(s, sport, dport, iss, what, auto_ack=True):
    c = open_connection(s, sport, dport, iss, F.opt_mss(1460), what)
    settled(s, c, what)
    c.auto_ack = auto_ack
    return c


def probe(s, c, what):
    """An old duplicate byte (the SYN's own number) on C's four-tuple: a
    connection or a TIME-WAIT record answers it with an ACK, no connection
    with an RST.  Returns 'ACK' or 'RST'."""
    t = s.now
    c.segment(0, b'\0', seq=c.iss)
    r = s.wait_for(t + s.p.answer, lambda x: x.t > t and c.ours(x))
    if r is None:
        raise Fail('%s: no answer to an old duplicate on the four-tuple by %s' % (what, at(s.now)))
    return 'RST' if r.tcp.flags & F.RST else 'ACK'


def raw_segment(s, c, flags, seq, ack, data=b''):
    """A segment on C's four-tuple with the sequence and ACK numbers given."""
    seg = F.tcp(s.p.peer_ip, s.p.band_ip, c.sport, c.dport, seq, ack, flags, c.window, data)
    c.offers.append((s.now, c.window, ack if flags & F.ACK else None))
    s.ipv4_to_band(F.IP_TCP, seg)


def rst(s):
    """An RST in the window, at RCV.NXT and strictly inside it, aborts the
    connection, the server sees SYS:CONNECTION-LOST and the four-tuple is
    free; out of the window it is ignored; in SYN-RECEIVED it returns the
    connection to LISTEN (section 5.5, MUST-11, -12; section 9, T1, RST)."""
    p = s.p
    s.boot()
    c = control(s)
    ask(s, c, 'echo-on')
    # At RCV.NXT, on a connection to the echo service, whose server is
    # blocked in a read.
    e = settled_conn(s, 40031, p.echo_port, ISN_A, 'an echo connection')
    raw_segment(s, e, F.RST, e.snd_nxt, 0)
    s.quiet(s.now + p.answer, lambda x: e.ours(x), 'an answer to an RST at RCV.NXT')
    cond = ask(s, c, 'condition')[0]
    if 'CONNECTION-LOST' not in cond.upper():
        raise Fail('after an RST at RCV.NXT the echo service saw %s, not SYS:CONNECTION-LOST' % cond)
    s.conns.remove(e)
    open_connection(s, 40031, p.echo_port, (ISN_A + 100000) & 0xFFFFFFFF, F.opt_mss(1460),
                    'a SYN on the four-tuple after the RST')
    # Strictly inside the window, 1,000 past RCV.NXT (contract 5.5 takes
    # any in the window, not only RFC 5961's exact match).
    f = settled_conn(s, 40032, p.echo_port, ISN_B, 'a second echo connection')
    raw_segment(s, f, F.RST, (f.snd_nxt + 1000) & 0xFFFFFFFF, 0)
    s.quiet(s.now + p.answer, lambda x: f.ours(x), 'an answer to an RST strictly inside the window')
    if probe(s, f, 'after an RST strictly inside the window') != 'RST':
        raise Fail('an RST strictly inside the window did not abort the connection')
    # Out of the window, past its right edge and before RCV.NXT: ignored.
    g = settled_conn(s, 40033, p.echo_port, ISN_A ^ 0x1111, 'a third echo connection')
    raw_segment(s, g, F.RST, (g.snd_nxt + 9000) & 0xFFFFFFFF, 0)
    raw_segment(s, g, F.RST, (g.snd_nxt - 1) & 0xFFFFFFFF, 0)
    s.quiet(s.now + p.answer, lambda x: g.ours(x), 'an answer to an out-of-window RST')
    if probe(s, g, 'after two out-of-window RSTs') != 'ACK':
        raise Fail('an out-of-window RST aborted the connection')
    # In SYN-RECEIVED: back to LISTEN, so no SYN-ACK is resent at the
    # RTO (1 s), and the SYN-ACK's ACK finds no connection.
    h = s.connect(40034, p.telnet_port, ISN_B ^ 0x2222, F.opt_mss(1460))
    h.auto_ack = False
    s.wait_for(s.now + p.answer, lambda x: h.ours(x))
    if h.synack is None:
        raise Fail('SYN-RECEIVED: no SYN-ACK by %s' % at(s.now))
    raw_segment(s, h, F.RST, h.snd_nxt, 0)
    s.quiet(s.now + 1500 * MS, lambda x: h.ours(x), 'a SYN-ACK resent after an RST in SYN-RECEIVED')
    if probe(s, h, 'after an RST in SYN-RECEIVED') != 'RST':
        raise Fail('after an RST in SYN-RECEIVED the connection is still there')
    return 'RST at RCV.NXT and inside the window abort (%s); out of the window ignored; SYN-RECEIVED to LISTEN' % cond


# The subnet's broadcast and the band's own address are added from the run's
# addresses.
MUST_63 = ['255.255.255.255', '224.0.0.1', '240.0.0.1', '0.0.0.0', '127.0.0.1']


def syn(s):
    """A SYN in ESTABLISHED gets a challenge ACK; a closed port gives RST;
    a SYN from each MUST-63 source is dropped; a full backlog (4 half-open)
    drops; a full table (8 connections) gives RST (section 5.5)."""
    p = s.p
    s.boot()
    c = settled_conn(s, 40041, p.telnet_port, ISN_A, 'a session')
    t = s.now
    raw_segment(s, c, F.SYN, (c.iss + 1000000) & 0xFFFFFFFF, 0)
    r = s.wait_for(t + p.answer, lambda x: x.t > t and c.ours(x))
    if r is None:
        raise Fail('no challenge ACK to a SYN in ESTABLISHED by %s' % at(s.now))
    if r.tcp.flags & (F.SYN | F.RST) or not r.tcp.flags & F.ACK or r.tcp.ack != c.snd_nxt:
        raise Fail('a SYN in ESTABLISHED is answered by %s, not a challenge ACK of %d' % (r, c.snd_nxt))
    if probe(s, c, 'after the challenge ACK') != 'ACK':
        raise Fail('the session is gone after the challenge ACK')
    # A closed port: RST, for a SYN and for an ACK.
    d = s.connect(40042, 9, ISN_B, F.opt_mss(1460))
    s.wait_for(s.now + p.answer, lambda x: d.ours(x))
    refused(s, d, 'a SYN to the closed port 9')
    d.rst = None
    raw_segment(s, d, F.ACK, d.snd_nxt, 0x12345678)
    s.wait_for(s.now + p.answer, lambda x: d.ours(x) and x.tcp.flags & F.RST and x.t > d.segments[0].t)
    if d.rst is None or d.rst.tcp.seq != 0x12345678:
        raise Fail('an ACK to the closed port 9: %s, not RST at its ACK number' % (d.rst or 'no answer'))
    s.conns.remove(d)
    # MUST-63's sources: dropped silently.
    for src in MUST_63 + [F.ip_text(subnet_broadcast(p)), F.ip_text(p.band_ip)]:
        seg = F.tcp(F.ip(src), p.band_ip, 40043, p.telnet_port, ISN_A, 0, F.SYN, 65535, options=F.opt_mss(1460))
        s.ipv4_to_band(F.IP_TCP, seg, src=F.ip(src))
        s.quiet(s.now + p.answer, lambda x: x.ip is not None, 'a SYN from %s answered' % src)
    # The backlog: four half-open connections; a fifth SYN is dropped.
    half = []
    for k in range(5):
        h = s.connect(40044 + k, p.telnet_port, (ISN_B + 7919 * k) & 0xFFFFFFFF, F.opt_mss(1460))
        h.auto_ack = False
        half.append(h)
    s.run(s.now + p.answer)
    got = [h.synack is not None for h in half]
    if got[:4] != [True] * 4:
        raise Fail('the backlog: SYN-ACKs to %s of the first four SYNs' % got[:4])
    if half[4].segments:
        raise Fail('the fifth half-open SYN, past the backlog of 4, is answered: %s' % half[4].segments[0])
    for h in half[:4]:
        raw_segment(s, h, F.RST, h.snd_nxt, 0)
    s.run(s.now + 100 * MS)
    for h in half:
        s.conns.remove(h)
    # The table: 8 connections, the session one of them and a half-open
    # one counting too (F21): with 7 and a half-open one, a SYN gets RST.
    est = [c]
    for k in range(6):
        est.append(settled_conn(s, 40050 + k, p.telnet_port, (ISN_A + 104729 * k) & 0xFFFFFFFF,
                                'connection %d' % (k + 2)))
    h1 = s.connect(40056, p.telnet_port, ISN_B ^ 0x6666, F.opt_mss(1460))
    h1.auto_ack = False
    s.wait_for(s.now + p.answer, lambda x: h1.ours(x))
    n = s.connect(40059, p.telnet_port, ISN_B ^ 0x7777, F.opt_mss(1460))
    s.wait_for(s.now + p.answer, lambda x: n.ours(x))
    if n.synack is not None:
        raise Fail('a ninth connection, past 7 and a half-open one, is accepted: %s' % n.synack)
    refused(s, n, 'a ninth SYN, past 7 connections and a half-open one')
    s.conns.remove(n)
    # A full backlog and a full table: 4 connections and 4 half-open on
    # port 23; the backlog is checked first, so a SYN gets nothing (F21).
    for x in est[4:]:
        raw_segment(s, x, F.RST, x.snd_nxt, 0)
    s.run(s.now + 100 * MS)
    half = [h1]
    for k in range(3):
        h = s.connect(40060 + k, p.telnet_port, (ISN_B + 6151 * k) & 0xFFFFFFFF, F.opt_mss(1460))
        h.auto_ack = False
        half.append(h)
    s.run(s.now + p.answer)
    if not all(h.synack is not None for h in half):
        raise Fail('4 connections and 4 half-open: the half-open SYNs were not all answered')
    m = s.connect(40064, p.telnet_port, ISN_A ^ 0x4444, F.opt_mss(1460))
    s.quiet(s.now + p.answer, lambda x: m.ours(x),
            'a SYN past a full backlog and a full table answered (the backlog is checked first)')
    s.conns.remove(m)
    for h in half:
        raw_segment(s, h, F.RST, h.snd_nxt, 0)
    s.run(s.now + 100 * MS)
    # 8 connections, all established: a ninth SYN gets RST.
    for k in range(4):
        est.append(settled_conn(s, 40065 + k, p.telnet_port, (ISN_A + 7727 * k) & 0xFFFFFFFF,
                                'connection %d' % (k + 5)))
    n = s.connect(40069, p.telnet_port, ISN_B ^ 0x5151, F.opt_mss(1460))
    s.wait_for(s.now + p.answer, lambda x: n.ours(x))
    if n.synack is not None:
        raise Fail('the ninth connection, past the table of 8, is accepted: %s' % n.synack)
    refused(s, n, 'the ninth SYN, past the table of 8')
    return ('challenge ACK; closed port RST; %d MUST-63 sources dropped; backlog 4; table 8 with half-open ones, '
            'the ninth RST; the backlog before the table' % (len(MUST_63) + 2))


def band_fin(s, c, what, limit=None):
    """The band's FIN on C: one already come (it may ride on the ACK of
    ours), or the next."""
    r = next((x for x in c.segments if x.tcp.flags & F.FIN), None)
    if r is not None:
        return r
    r = s.wait_for(s.now + (limit or 2 * s.p.answer), lambda x: c.ours(x) and x.tcp.flags & F.FIN)
    if r is None:
        raise Fail('%s: no FIN from the band by %s' % (what, at(s.now)))
    return r


def after_fin(c, fin, what):
    """Every segment of C the band sends after its FIN carries the FIN's
    sequence number plus one: the FIN takes one (section 5.5)."""
    want = (fin.tcp.seq + len(fin.tcp.data) + 1) & 0xFFFFFFFF
    for x in c.segments:
        if x.t > fin.t and not x.tcp.flags & (F.FIN | F.RST) and x.tcp.seq != want:
            raise Fail('%s: a segment after the band\'s FIN at sequence %d, not %d (FIN takes a number): %s'
                       % (what, x.tcp.seq, want, x))


def our_fin(s, c, ack=None):
    """The peer's FIN on C; returns its sequence number."""
    seq = c.snd_nxt
    raw_segment(s, c, F.FIN | F.ACK, seq, c.rcv_nxt if ack is None else ack)
    c.snd_nxt = (c.snd_nxt + 1) & 0xFFFFFFFF
    return seq


def fin_acked(s, c, seq, what):
    t = s.now
    r = s.wait_for(t + s.p.answer, lambda x: x.t > t and c.ours(x) and x.tcp.ack == (seq + 1) & 0xFFFFFFFF)
    if r is None:
        raise Fail('%s: our FIN is not acknowledged by %s' % (what, at(s.now)))
    return r


def close(s):
    """Close in both directions and through CLOSING: the peer first, the
    band then closing on EOF; the band first, through the control session,
    then TIME-WAIT; both at once (section 5.5; section 9, T1, Close)."""
    p = s.p
    s.boot()
    # The peer first: the band acknowledges the FIN, its server closes on
    # EOF, and once its FIN is acknowledged the connection is gone.
    a = settled_conn(s, 40061, p.telnet_port, ISN_A, 'the peer closing first')
    fa = our_fin(s, a)
    fin_acked(s, a, fa, 'the peer closing first')
    f1 = band_fin(s, a, 'the peer closing first')
    s.run(s.now + 100 * MS)
    gone = probe(s, a, 'the peer closing first, after both FINs')
    after_fin(a, f1, 'the peer closing first')
    if gone != 'RST':
        raise Fail('the peer closing first: the connection is still there after both FINs')
    # The band first: its FIN, ours, and TIME-WAIT (an old segment gets an
    # ACK, not an RST).
    c = control(s)
    b = settled_conn(s, 40062, p.telnet_port, ISN_B, 'the band closing first')
    ask(s, c, 'close', b.sport, b.sport)
    f2 = band_fin(s, b, 'the band closing first')
    s.run(s.now + 100 * MS)
    fb = our_fin(s, b)
    fin_acked(s, b, fb, 'the band closing first')
    after_fin(b, f2, 'the band closing first')
    if probe(s, b, 'the band closing first, in TIME-WAIT') != 'ACK':
        raise Fail('the band closing first: no TIME-WAIT after both FINs')
    # Both at once: the band's FIN unacknowledged, ours crossing it.
    d = settled_conn(s, 40063, p.telnet_port, ISN_A ^ 0x3333, 'CLOSING', auto_ack=False)
    ask(s, c, 'close', d.sport, d.sport)
    f3 = band_fin(s, d, 'CLOSING')
    fd = our_fin(s, d, ack=f3.tcp.seq)
    fin_acked(s, d, fd, 'CLOSING (the band in CLOSING must acknowledge our FIN)')
    raw_segment(s, d, F.ACK, d.snd_nxt, (f3.tcp.seq + 1) & 0xFFFFFFFF)
    s.run(s.now + 100 * MS)
    after_fin(d, f3, 'CLOSING')
    if probe(s, d, 'CLOSING, then TIME-WAIT') != 'ACK':
        raise Fail('CLOSING: no TIME-WAIT after both FINs were acknowledged')
    return 'peer first to CLOSED; band first to TIME-WAIT; CLOSING to TIME-WAIT'


def time_wait(s):
    """TIME-WAIT answers a resent FIN, takes a SYN above its final RCV.NXT
    as a new connection, and ends at 60.0 s of machine time within a tick,
    probed once on each of two connections that had no resent FIN (section
    5.5; section 9, T1, Close).  A long script: about 62 s of machine time."""
    p = s.p
    s.boot()
    c = control(s)
    tw = {}
    for name, port in (('A', 40071), ('B', 40072), ('C', 40073), ('D', 40074)):
        x = settled_conn(s, port, p.telnet_port, (ISN_A + port * 65537) & 0xFFFFFFFF, 'connection %s' % name)
        ask(s, c, 'close', port, port)
        band_fin(s, x, 'connection %s' % name)
        s.run(s.now + 50 * MS)
        t_fin = s.now
        seq = our_fin(s, x)
        r = fin_acked(s, x, seq, 'connection %s' % name)
        tw[name] = (x, t_fin, r.t, seq)
    # D: the resent FIN is acknowledged.
    x, _, _, seq = tw['D']
    s.run(s.now + 1 * S)
    raw_segment(s, x, F.FIN | F.ACK, seq, x.rcv_nxt)
    fin_acked(s, x, seq, 'TIME-WAIT, our FIN resent')
    # D: a SYN at its final RCV.NXT less one gets the challenge ACK and the
    # record stays (F24).
    t = s.now
    raw_segment(s, x, F.SYN, seq, 0)
    r = s.wait_for(t + p.answer, lambda y: y.t > t and x.ours(y))
    if r is None or r.tcp.flags & (F.SYN | F.RST) or r.tcp.ack != (seq + 1) & 0xFFFFFFFF:
        raise Fail('TIME-WAIT, a SYN at or below its final RCV.NXT: %s, not the challenge ACK'
                   % (r or 'no answer'))
    if probe(s, x, 'TIME-WAIT after a SYN below RCV.NXT') != 'ACK':
        raise Fail('TIME-WAIT, a SYN at or below its final RCV.NXT ended the record')
    # C: a SYN above its final RCV.NXT opens a new connection.
    x, _, _, seq = tw['C']
    s.conns.remove(x)
    n = open_connection(s, x.sport, p.telnet_port, (seq + 1 + 100000) & 0xFFFFFFFF, F.opt_mss(1460),
                        'TIME-WAIT, a SYN above its final RCV.NXT')
    raw_segment(s, n, F.RST, n.snd_nxt, 0)  # done with it: back to LISTEN
    # A: still there a tick before 60 s from our FIN; B: gone a tick after
    # 60 s from its ACK of our FIN.
    xa, fin_a, _, _ = tw['A']
    s.run(fin_a + 60 * S - TICK)
    if probe(s, xa, 'TIME-WAIT at 60 s less a tick') != 'ACK':
        raise Fail('TIME-WAIT ended before 60 s less a tick from our FIN (%s)' % at(fin_a))
    xb, _, ack_b, _ = tw['B']
    s.run(max(s.now, ack_b + 60 * S + TICK + PASS_LATENCY))
    if probe(s, xb, 'TIME-WAIT at 60 s and a tick') != 'RST':
        raise Fail('TIME-WAIT still there 60 s and a tick after the band acknowledged our FIN (%s)' % at(ack_b))
    return 'resent FIN acknowledged; SYN above RCV.NXT accepted at %s; ended between 60 s - tick and 60 s + tick' % (
        at(n.synack.t))


# --------------------------------------------------------------------------
# Slice 4: retransmission, windows and MUST-38 (section 5.5; section 9, T1;
# O2).  Every timer is checked within a tick, from the band's own segments'
# times on the clocked socket.

LONG_STEP = 10 * MS     # the long scripts idle in steps of this


def near(dt, want, what):
    """A timer within its bounds (section 9, T1, Latency; F45): up to a tick
    early, and up to a tick and the pass latency late."""
    if dt < want - TICK or dt > want + TICK + PASS_LATENCY:
        raise Fail('%s: %s, not %s within a tick (early) or a tick and the pass latency (late)' % (
            what, at(dt), at(want)))


def resent_at(s, prev, cur):
    """When the band resent, for a resend at CUR after one at PREV: CUR, or,
    where an ARP request for the peer came between them (R1's negative
    advice, MUST-20, so the resend waited for the answer), that request's
    time, which is when the band acted.  A request counts only when the
    resend follows it within the ARP round trip (the long scripts' step, in
    which the peer answers) and a tick: with two connections timed at once,
    the other one's request can fall inside this one's interval and must
    not be taken for its resend's time."""
    hold = LONG_STEP + TICK + MS
    reqs = [x.t for x in s.seen if x.arp and x.arp.op == F.ARP_REQUEST and x.arp.tpa == s.p.peer_ip
            and prev < x.t <= cur and cur - x.t <= hold]
    return reqs[0] if reqs else cur


def warm(s, c, n=3):
    """N small echoes acknowledged at once, so the band has RTT samples and
    its RTO is the floor of 200 ms (RFC 6298; section 5.5)."""
    c.auto_ack = True
    for k in range(n):
        c.write(b'warm %d' % k)
        quiet_on(s, c, 'warming the connection', quiet=50 * MS)


def echo_conn(s, sport, iss, mss=536, window=65535, what='an echo connection'):
    """A connection to the test echo service (its switch already on),
    warmed; the peer acknowledges only when the script says."""
    e = open_connection(s, sport, s.p.echo_port, iss, F.opt_mss(mss), what, window)
    e.ack()
    warm(s, e)
    e.auto_ack = False
    return e


def ack_to(s, c, ack, window=None):
    """A pure ACK of ACK from the peer, with WINDOW (default C's)."""
    if window is not None:
        c.window = window
    raw_segment(s, c, F.ACK, c.snd_nxt, ack & 0xFFFFFFFF)


def copies(c, seq, since):
    """The band's data segments on C starting at SEQ, sent after SINCE."""
    return [x for x in c.data_segments if x.tcp.seq == seq and x.t > since]


def rto(s):
    """The first RTO is 1 s and doubles (a SYN-ACK nobody acknowledges); the
    floor is 200 ms after RTT samples, and doubles; no RTT sample is taken
    from a resent segment (Karn, MUST-18) (section 5.5; RFC 6298)."""
    p = s.p
    s.boot()
    # The band resolves the peer first, so that the first SYN-ACK is not
    # held for ARP and the first gap is the band's RTO alone.
    echo_answered(s, 0x5254, 1, 'an echo request before the SYN')
    h = s.connect(40101, p.telnet_port, ISN_A, F.opt_mss(1460))
    h.auto_ack = False
    s.wait_for(s.now + p.answer, lambda x: h.synack is not None)
    if h.synack is None:
        raise Fail('no SYN-ACK by %s' % at(s.now))

    def syns():
        return [y.t for y in h.segments if y.tcp.flags & F.SYN]
    for k, want, what in ((1, 1 * S, 'the first RTO (the SYN-ACK resent)'),
                          (2, 2 * S, 'the RTO doubled (the SYN-ACK resent again)')):
        s.wait_for(s.now + want + 2 * TICK + PASS_LATENCY + p.answer, lambda x: len(syns()) > k)
        if len(syns()) <= k:
            raise Fail('%s: not by %s' % (what, at(s.now)))
        near(syns()[k] - syns()[k - 1], want, what)
    raw_segment(s, h, F.RST, h.snd_nxt, 0)
    s.conns.remove(h)
    c = control(s)
    ask(s, c, 'echo-on')
    e = echo_conn(s, 40102, ISN_B)
    # The floor and its doubling: an echo nobody acknowledges.
    e.write(b'lost 1')
    first = s.wait_for(s.now + p.answer, lambda x: e.ours(x) and x.tcp.data == b'lost 1')
    if first is None:
        raise Fail('no echo of 6 bytes by %s' % at(s.now))
    for k, at_most, what in ((1, 200 * MS, 'the RTO after RTT samples (the 200 ms floor)'),
                             (2, 600 * MS, 'the RTO doubled from the floor')):
        s.wait_for(first.t + at_most + 2 * TICK + PASS_LATENCY, lambda x: len(copies(e, first.tcp.seq, first.t)) >= k)
        re = copies(e, first.tcp.seq, first.t)
        if len(re) < k:
            raise Fail('%s: not resent by %s' % (what, at(s.now)))
    near(re[0].t - first.t, 200 * MS, 'the RTO after RTT samples (the 200 ms floor)')
    near(re[1].t - re[0].t, 400 * MS, 'the RTO doubled from the floor')
    ack_to(s, e, e.rcv_nxt)
    s.run(s.now + 100 * MS)
    # Karn: X resent once, then acknowledged late; Y acknowledged at once;
    # Z resent at the floor again, since X gave no sample.
    e.write(b'karn X')
    x = s.wait_for(s.now + p.answer, lambda y: e.ours(y) and y.tcp.data == b'karn X')
    s.wait_for(x.t + 3 * S, lambda y: copies(e, x.tcp.seq, x.t))
    rx = copies(e, x.tcp.seq, x.t)
    if not rx:
        raise Fail('Karn: X was not resent by %s' % at(s.now))
    s.run(rx[0].t + 350 * MS)    # inside the doubled RTO: one resend only
    ack_to(s, e, e.rcv_nxt)
    s.run(s.now + 50 * MS)
    e.auto_ack = True
    e.write(b'karn Y')
    quiet_on(s, e, 'Karn: Y', quiet=100 * MS)
    e.auto_ack = False
    e.write(b'karn Z')
    z = s.wait_for(s.now + p.answer, lambda y: e.ours(y) and y.tcp.data == b'karn Z')
    s.wait_for(z.t + 3 * S, lambda y: copies(e, z.tcp.seq, z.t))
    rz = copies(e, z.tcp.seq, z.t)
    if not rz:
        raise Fail('Karn: Z resent after a resent X was acknowledged late: not by %s' % at(s.now))
    near(rz[0].t - z.t, 200 * MS, 'Karn: Z resent after a resent X was acknowledged late')
    ack_to(s, e, e.rcv_nxt)
    return 'first RTO 1 s, doubling; floor 200 ms, doubling; Karn: no sample from a resent segment'


def rto_restart(s):
    """The retransmission timer restarts when an ACK takes new data (RFC
    6298 section 5.3; O2): of two segments out, the first acknowledged after
    100 ms, the second is resent no earlier than one RTO (200 ms, less a
    tick) after that ACK, and before 400 ms."""
    p = s.p
    s.boot()
    c = control(s)
    ask(s, c, 'echo-on')
    e = echo_conn(s, 40103, ISN_A)
    e.write(bytes(range(256)) * 4 + bytes(48))        # 1,072 bytes: two segments of 536
    s.wait_for(s.now + p.answer, lambda x: len([y for y in e.data_segments if len(y.tcp.data) == 536]) >= 2)
    segs = [y for y in e.data_segments if len(y.tcp.data) == 536][:2]
    if len(segs) < 2:
        raise Fail('two segments of 536 bytes not echoed by %s' % at(s.now))
    s1, s2 = segs
    s.run(s1.t + 100 * MS)
    t_ack = s.now
    ack_to(s, e, s1.tcp.seq + 536)
    if not copies(e, s2.tcp.seq, s2.t):
        s.wait_for(t_ack + 400 * MS, lambda x: copies(e, s2.tcp.seq, s2.t))
    r = copies(e, s2.tcp.seq, s2.t)
    if not r:
        raise Fail('the second segment was not resent by %s' % at(s.now))
    if r[0].t - t_ack < 200 * MS - TICK or r[0].t - t_ack >= 400 * MS:
        raise Fail('the second segment resent %s after the ACK of the first, not one RTO after it (the timer '
                   'restarted)' % at(r[0].t - t_ack))
    ack_to(s, e, e.rcv_nxt)
    return 'resent %s after the ACK of the first, the timer restarted' % at(r[0].t - t_ack)


def cwnd_reset(s):
    """After a timeout with the initial window out, 3 x 536 bytes, one
    segment goes, and the rest from SND.UNA only as ACKs open the
    congestion window: at most two after its ACK (section 5.5 as F29 states
    it; RFC 5681 section 3.1; O2).  It rests on the band going back to
    SND.UNA after a timeout, which F29 makes a requirement."""
    p = s.p
    s.boot()
    c = control(s)
    ask(s, c, 'echo-on')
    e = echo_conn(s, 40104, ISN_B)
    data = bytes((i * 7) & 255 for i in range(3 * 536))
    before = len(e.data_segments)
    e.write(data)
    s.wait_for(s.now + 100 * MS, lambda x: False)
    out = []                            # the segments out, each once
    for y in e.data_segments[before:]:
        if all(y.tcp.seq != z.tcp.seq for z in out):
            out.append(y)
    if sum(len(y.tcp.data) for y in out) != len(data) or len(out) < 3:
        raise Fail('the initial window not out by %s: %d segments, %d bytes' % (
            at(s.now), len(out), sum(len(y.tcp.data) for y in out)))
    s1 = out[0]
    # A copy already seen counts; each look ends before the next RTO, the
    # copy + 400 ms.
    if not copies(e, s1.tcp.seq, s1.t):
        s.wait_for(s1.t + 300 * MS, lambda x: copies(e, s1.tcp.seq, s1.t))
    r = copies(e, s1.tcp.seq, s1.t)
    if not r:
        raise Fail('no segment resent after the timeout by %s' % at(s.now))
    s.run(r[0].t + 150 * MS)
    after = [y for y in e.data_segments if y.t > r[0].t]
    if after:
        raise Fail('after the timeout %d more segments went before any ACK: %s' % (len(after), after[0]))
    t = s.now
    ack_to(s, e, s1.tcp.seq + 536)
    s.run(t + 150 * MS)
    more = [y for y in e.data_segments if y.t > t]
    if len(more) > 2:
        raise Fail('after a timeout and one ACK, %d segments went, not at most 2 (slow start from one)' % len(more))
    e.auto_ack = True
    quiet_on(s, e, 'the rest of the echo')
    if e.received[-len(data):] != data:
        raise Fail('the echo after the timeout differs from what was sent')
    return 'one segment after the timeout; %d after the first ACK' % len(more)


def r2(s):
    """An echo nobody acknowledges is resent from 200 ms, doubling; after R1
    = 3 retransmissions the peer's ARP entry goes (MUST-20); R2 closes the
    connection 100 s after the first transmission, within a tick: alive
    just before, nothing resent after, and the stream signals
    SYS:HOST-STOPPED-RESPONDING (O4).  A long script: about 110 s."""
    p = s.p
    s.boot()
    c = control(s)
    ask(s, c, 'echo-on')
    e = echo_conn(s, 40105, ISN_A)
    e.write(b'r2 lost')
    first = s.wait_for(s.now + p.answer, lambda x: e.ours(x) and x.tcp.data == b'r2 lost')
    if first is None:
        raise Fail('no echo of 7 bytes by %s' % at(s.now))
    unacked = first.tcp.seq
    s.wait_for(first.t + 60 * S, lambda x: len(copies(e, unacked, first.t)) >= 8, step=LONG_STEP)
    re = [first] + copies(e, unacked, first.t)
    if len(re) < 9:
        raise Fail('R2: %d retransmissions by %s, not 8' % (len(re) - 1, at(s.now)))
    gap = 200 * MS
    for k in range(1, 9):
        before = resent_at(s, re[k - 2].t, re[k - 1].t) if k > 1 else re[0].t
        near(resent_at(s, re[k - 1].t, re[k].t) - before, gap, 'retransmission %d' % k)
        gap = min(2 * gap, 60 * S)
    def arps(lo, hi):
        return [x for x in s.seen if x.arp and x.arp.op == F.ARP_REQUEST and x.arp.tpa == p.peer_ip
                and lo < x.t <= hi]
    if arps(first.t, re[3].t):
        raise Fail('an ARP request for the peer before R1 = 3 retransmissions: %s' % arps(first.t, re[3].t)[0])
    if not arps(re[3].t, re[4].t):
        raise Fail('no ARP request for the peer between the third and fourth retransmissions (R1, MUST-20)')
    # Alive a tick before 100 s: an old duplicate is answered by an ACK
    # that leaves the band's data unacknowledged.
    s.run(max(s.now, first.t + 100 * S - TICK), )
    t = s.now
    raw_segment(s, e, F.ACK, e.iss, unacked, b'\0')
    r = s.wait_for(t + 2 * TICK, lambda x: x.t > t and e.ours(x))
    if r is None or r.tcp.flags & F.RST:
        raise Fail('R2: the connection is gone before 100 s less a tick: %s' % (r or 'no answer'))
    s.run(first.t + 100 * S + TICK + PASS_LATENCY)
    cond = ask(s, c, 'condition')[0]
    s.wait_for(first.t + 104 * S, lambda x: False, step=LONG_STEP)
    late = [x for x in e.segments if x.t > first.t + 100 * S + TICK + PASS_LATENCY and not x.tcp.flags & F.RST]
    if late:
        raise Fail('R2: the band sent after 100 s and a tick: %s' % late[0])
    if 'HOST-STOPPED-RESPONDING' not in cond.upper():
        raise Fail('R2: the echo service saw %s, not SYS:HOST-STOPPED-RESPONDING' % cond)
    if probe(s, e, 'after R2') != 'RST':
        raise Fail('R2: the connection is still there after 100 s')
    return 'resent from 200 ms doubling, ARP again after R1, closed at 100 s (%s)' % cond


def is_probe(c, x):
    """F27's two probe forms at the peer's zero window: one octet of new
    data at the right edge (RCV.NXT while the window is 0), or a segment
    without data below the peer's RCV.NXT.  A segment without data at
    RCV.NXT is not one: a receiver takes it without an answer."""
    t = x.tcp
    if len(t.data) == 1:
        return t.seq == c.rcv_nxt
    if not t.data:
        return 0 < ((c.rcv_nxt - t.seq) & 0xFFFFFFFF) < 0x80000000
    return False


def zero_window(s):
    """The peer's zero window is probed from one RTO after the band has data
    waiting under it, each interval doubling to 60 s, for 200 s of machine
    time (twice R2), the peer answering each probe as a receiver with a zero
    window does and taking none of its data, with no abort; then the
    peer's answer to a probe opens the window, as when the window update
    was lost, and the data comes (section 5.5; MUST-35 to -37; F27; RFC
    1122 section 4.2.2.17).  A long script: about 205-265 s."""
    p = s.p
    s.boot()
    c = control(s)
    ask(s, c, 'echo-on')
    # The peer offers 536, one MSS, from the SYN on: of a 1,000-byte echo
    # 536 goes and 464 waits, and the peer's ACK of the 536 brings the zero
    # window, the moment the persist timer is timed from.
    e = echo_conn(s, 40106, ISN_B, window=536)
    data = bytes((i * 11 + 3) & 255 for i in range(1000))
    start = len(e.received)
    e.write(data)
    got = s.wait_for(s.now + p.answer, lambda x: e.ours(x) and len(x.tcp.data) == 536)
    if got is None:
        raise Fail('the zero window: no 536 bytes of the echo by %s' % at(s.now))
    s.run(s.now + 2 * MS)
    # The zero window comes on a segment of one octet, so that the band
    # answers it at once: the first probe is timed from the peer's segment
    # on its early side and from the band's answer on its late side, since
    # the band may take a frame up to its pass latency or more after it
    # arrives, and its timer starts then (section 9, T1, Latency).
    e.window = 0
    raw_segment(s, e, F.ACK | F.PSH, e.snd_nxt, e.rcv_nxt, b'Z')
    e.snd_nxt = (e.snd_nxt + 1) & 0xFFFFFFFF
    data += b'Z'
    t0 = s.now
    answer = None
    probes = []
    end = t0 + 200 * S
    opened = None
    limit = end + 60 * S + 2 * TICK + PASS_LATENCY
    while s.now < limit and opened is None:
        for x in s.run(min(s.now + LONG_STEP, limit)):
            if not e.ours(x) or x.t <= t0:
                continue
            if x.tcp.flags & F.RST:
                raise Fail('the zero window: RST at %s' % at(x.t))
            if answer is None and x.tcp.ack == e.snd_nxt:
                answer = x
                if not x.tcp.data and not is_probe(e, x):
                    continue        # the ACK of the octet
            if not is_probe(e, x):
                raise Fail('the zero window: a segment that is not a probe (F27): %s' % x)
            probes.append(x)
            if x.t < end:
                ack_to(s, e, e.rcv_nxt, window=0)
            else:
                # The answer to the first probe after 200 s opens the window.
                e.auto_ack = True
                ack_to(s, e, e.rcv_nxt, window=65535)
                opened = x
                break
    if len(probes) < 3:
        raise Fail('the zero window: %d probes in 200 s' % len(probes))
    if opened is None:
        raise Fail('the zero window: no zero-window probe in the 60 s after 200 s')
    if answer is None:
        raise Fail('the zero window: the octet that brought it was never acknowledged')
    first = 'the first zero-window probe, one RTO after the zero window'
    if probes[0].t - t0 < 200 * MS - TICK:
        raise Fail('%s: %s after the peer\'s segment, not 200 ms less a tick or more' % (first, at(probes[0].t - t0)))
    if probes[0].t - answer.t > 200 * MS + TICK + PASS_LATENCY:
        raise Fail('%s: %s after the band\'s answer, more than 200 ms, a tick and the pass latency' % (
            first, at(probes[0].t - answer.t)))
    gap = 400 * MS
    for k in range(1, len(probes)):
        near(probes[k].t - probes[k - 1].t, gap, 'zero-window probe %d' % (k + 1))
        gap = min(2 * gap, 60 * S)
    quiet_on(s, e, 'after the window opened')
    if e.received[start:] != data:
        raise Fail('after the zero window: %d of %d bytes echoed' % (len(e.received) - start, len(data)))
    cond = ask(s, c, 'condition')[0]
    if cond.upper() != 'NIL':
        raise Fail('the zero window: the echo service saw %s' % cond)
    return '%d probes from the RTO backing off to 60 s, none taken; no abort; the window opened in an answer' % (
        len(probes))


def fill(s, e, extra=1000):
    """Fill the band's buffers: the peer's window 0, so the echo service's
    writes fill its 8,192-byte send buffer and it stops reading; then the
    8,192-byte receive buffer fills, and the band's window is 0."""
    ack_to(s, e, e.rcv_nxt, window=0)
    s.run(s.now + 50 * MS)
    e.write(bytes((i * 13) & 255 for i in range(16384 + extra)))
    z = s.wait_for(s.now + 5 * S, lambda x: e.ours(x) and x.tcp.window == 0 and x.tcp.flags & F.ACK
                   and ((x.tcp.ack - e.iss - 1) & 0xFFFFFFFF) > 8192)
    if z is None:
        raise Fail('the band\'s own window never reached 0 by %s' % at(s.now))
    s.run(s.now + 100 * MS)
    return z


def own_zero_window(s):
    """At the band's own zero window: a probe without data below its RCV.NXT
    gets an ACK of RCV.NXT with window 0; a probe of one octet at RCV.NXT,
    carrying an ACK that opens the peer's window, gets the same ACK, its
    octet not delivered, and its ACK taken (MUST-66, RFC 9293 sections
    3.8.6.1 and 3.10.7.4); an RST at RCV.NXT is taken (MUST-66).  As the
    band's buffer drains, and then over five echoes of 300 bytes, its right
    edge moves by at least the connection's effective send MSS, min(the
    peer's MSS, 1,460), at a time (receiver silly window avoidance, MUST-39;
    F25; O2)."""
    p = s.p
    s.boot()
    c = control(s)
    ask(s, c, 'echo-on')
    mss = 1460
    e = echo_conn(s, 40107, ISN_A, mss=mss)
    eff = min(mss, 1460)
    start = len(e.received)
    total = 16384 + 1000
    fill(s, e)
    t = s.now
    nxt = e.rcv_nxt                     # the band's SND.NXT
    raw_segment(s, e, F.ACK, (e.snd_nxt - 1) & 0xFFFFFFFF, e.rcv_nxt)
    # The answer, at the band's SND.NXT and without data (the band's own
    # probes of the peer's zero window are not it).
    r = s.wait_for(t + p.answer, lambda x: x.t > t and e.ours(x) and not x.tcp.data and x.tcp.seq == nxt)
    if r is None or r.tcp.ack != e.snd_nxt or r.tcp.window != 0:
        raise Fail('a probe without data at the band\'s zero window: %s, not an ACK of RCV.NXT with window 0'
                   % (r or 'no answer'))
    t = s.now
    e.window = 65535
    raw_segment(s, e, F.ACK, e.snd_nxt, e.rcv_nxt, b'X')
    r = s.wait_for(t + p.answer, lambda x: x.t > t and e.ours(x) and x.tcp.seq == nxt)
    if r is None or r.tcp.ack != e.snd_nxt:
        raise Fail('a probe of one octet at the band\'s zero window: %s, not an ACK of RCV.NXT'
                   % (r or 'no answer'))
    # Data past that: the probe's ACK, opening the peer's window, was taken.
    d = s.wait_for(t + p.answer, lambda x: x.t > t and e.ours(x) and len(x.tcp.data) > 1)
    if d is None:
        raise Fail('an ACK opening the peer\'s window at the band\'s zero window was not processed by %s' % at(s.now))
    e.auto_ack = True
    quiet_on(s, e, 'the drain', limit=20 * S)
    got = len(e.received) - start
    if got != total:
        raise Fail('the drain: %d bytes echoed for %d (the probe\'s octet is not delivered)' % (got, total))
    for k in range(5):
        e.write(bytes([k + 1]) * 300)
        quiet_on(s, e, 'an echo of 300 bytes', quiet=100 * MS)
    if len(e.received) - start != total + 1500:
        raise Fail('five echoes of 300 bytes: %d bytes echoed' % (len(e.received) - start - total))
    edges = []
    for x in e.segments:
        if x.t > t and x.tcp.flags & F.ACK and not x.tcp.flags & F.RST:
            edge = (x.tcp.ack + x.tcp.window) & 0xFFFFFFFF
            if edges and 0 < ((edge - edges[-1]) & 0xFFFFFFFF) < eff:
                raise Fail('the band\'s window opened by %d bytes, less than one MSS of %d: %s'
                           % ((edge - edges[-1]) & 0xFFFFFFFF, eff, x))
            if not edges or 0 < ((edge - edges[-1]) & 0xFFFFFFFF) < 0x80000000:
                edges.append(edge)
    # An RST at RCV.NXT, at a zero window: taken.
    f = echo_conn(s, 40108, ISN_B, mss=1460, what='a second echo connection')
    fill(s, f)
    raw_segment(s, f, F.RST, f.snd_nxt, 0)
    s.run(s.now + 100 * MS)
    if probe(s, f, 'after an RST at the band\'s zero window') != 'RST':
        raise Fail('an RST at RCV.NXT at the band\'s zero window was not taken')
    return 'both probes answered and an ACK and an RST taken at the zero window; the edge moved %d times, ' \
           'each by %d or more' % (max(0, len(edges) - 1), eff)


def must_38(s):
    """MUST-38's four rules (RFC 9293 section 3.8.6.2.1; section 5.5), on
    the test echo service, with the peer's window shrunk to 2,000 after it
    offered 30,000: (1) a full MSS goes at once though the window allows
    more; (4) the rest, 540, waits for the 200 ms override; (2) all that is
    queued goes at once when it fits; (3) with a largest window of 1,000,
    half of it goes at once; and nothing goes past a shrunk window."""
    p = s.p
    s.boot()
    c = control(s)
    ask(s, c, 'echo-on')
    a = echo_conn(s, 40109, ISN_A, mss=1460, window=30000)
    # The 4,000 bytes are queued under a zero window, so that when the
    # window opens to 2,000 (its edge left of the 30,000 offered: a shrunk
    # window) the band has more queued than it may send.
    ack_to(s, a, a.rcv_nxt, window=0)
    s.run(s.now + 20 * MS)
    data = bytes((i * 17 + 1) & 255 for i in range(4000))
    start = len(a.received)
    a.write(data)
    s.wait_for(s.now + p.answer, lambda x: a.ours(x) and x.tcp.ack == a.snd_nxt)
    s.run(s.now + 30 * MS)
    ack_to(s, a, a.rcv_nxt, window=2000)
    t0 = s.now
    # The full MSS is acknowledged at once with a window of 540, so the
    # edge stands still and no retransmission timer runs out first.
    one = s.wait_for(t0 + 200 * MS, lambda x: a.ours(x) and x.tcp.data)
    acked = None    # when the full MSS was acknowledged: rule 4's late side
    if one is not None and len(one.tcp.data) == 1460:
        acked = s.now
        ack_to(s, a, (one.tcp.seq + 1460) & 0xFFFFFFFF, window=540)
    # The rest when the override runs out, acknowledged at once.
    s.wait_for(t0 + 400 * MS, lambda x: a.ours(x) and x.tcp.data and x is not one)
    segs = [x for x in a.data_segments if x.t > t0 - 2 * MS]
    for x in segs:
        end = (x.tcp.seq + len(x.tcp.data)) & 0xFFFFFFFF
        lim = (segs[0].tcp.seq + 2000) & 0xFFFFFFFF
        if 0 < ((end - lim) & 0xFFFFFFFF) < 0x80000000:
            raise Fail('past the shrunk window of 2,000: %s' % x)
    if not segs or len(segs[0].tcp.data) != 1460 or segs[0].t - t0 > 200 * MS - TICK:
        raise Fail('rule 1: not a full MSS at once, but %s' % (segs[0] if segs else 'nothing'))
    if len(segs) < 2 or len(segs[1].tcp.data) != 540:
        raise Fail('rule 4: the 540 bytes left did not go at the override: %s'
                   % (', '.join(str(x) for x in segs[1:]) or 'nothing'))
    # Rule 4's two sides (F47, F50): the band starts the override timer as it
    # sends the full MSS, so the early side is timed from that segment; but
    # a band may let our ACK of it restart the timer (F28's freedom), and it
    # takes that ACK up to a tick and the pass latency after it arrives, so
    # the late side is timed from the ACK, with that and the timer's own
    # tick and pass latency: 200 ms and twice a tick and the pass latency.
    if acked is None:
        raise Fail('rule 1: the full MSS was not the first data within 200 ms, so not acknowledged')
    early = segs[1].t - segs[0].t
    late = segs[1].t - acked
    if early < 200 * MS - TICK or late > 200 * MS + 2 * (TICK + PASS_LATENCY):
        raise Fail('rule 4: the override timer: %s after the full MSS, not 200 ms less a tick or more; '
                   '%s after its ACK, not 200 ms and twice a tick and the pass latency or less' % (
                       at(early), at(late)))
    t1 = s.now
    ack_to(s, a, a.rcv_nxt, window=2000)
    s.wait_for(t1 + 150 * MS, lambda x: False)
    rest = [x for x in a.data_segments if x.t > t1]
    if sum(len(x.tcp.data) for x in rest) != 2000 or rest[-1].t - t1 > 200 * MS - TICK:
        raise Fail('rule 2: the 2,000 queued did not all go at once when they fit: %s'
                   % (', '.join(str(x) for x in rest) or 'nothing'))
    a.window = 30000
    a.auto_ack = True
    ack_to(s, a, a.rcv_nxt)
    quiet_on(s, a, 'rule 2')
    if a.received[start:] != data:
        raise Fail('MUST-38: the echo differs from the 4,000 bytes sent')
    # Rule 3: a largest window of 1,000, under the MSS: half of it at once.
    b = echo_conn(s, 40110, ISN_B, mss=1460, window=1000, what='a window of 1,000')
    data = bytes((i * 19 + 2) & 255 for i in range(3000))
    b.write(data)
    s.run(s.now + 2 * MS)
    t2 = s.now
    s.wait_for(t2 + 300 * MS, lambda x: False)
    first = [x for x in b.data_segments if x.t > t2 - 2 * MS]
    if not first or len(first[0].tcp.data) != 1000 or first[0].t - t2 > 200 * MS - TICK:
        raise Fail('rule 3: half the largest window did not go at once: %s' % (first[0] if first else 'nothing'))
    b.auto_ack = True
    quiet_on(s, b, 'rule 3')
    return 'rule 1 at once; rule 4 at %s; rule 2 at once; rule 3 at once; the shrunk window kept' % (
        at(segs[1].t - segs[0].t))


def shrink(s):
    """The window shrinks left of what the band has sent: with 8,192 bytes
    out under a window of 30,000 and more queued, an ACK of the first 1,000
    with a window of 500.  No new data goes past the new right edge (old
    data may be resent past it, MAY-7), the connection stays, and the data
    goes once the edge moves on (MUST-34, SHLD-15; section 5.5; F26)."""
    p = s.p
    s.boot()
    c = control(s)
    ask(s, c, 'echo-on')
    a = echo_conn(s, 40114, ISN_A, mss=1460, window=30000)
    base = len(a.received)
    first = a.rcv_nxt                   # the band's first byte of the echo
    before = len(a.data_segments)
    data = bytes((i * 23 + 9) & 255 for i in range(12000))
    # The 12,000 bytes go to the band under the peer's zero window, so the
    # band holds them all; then one ACK opens 30,000 and the peer sends
    # nothing more, so what the band sends stays unacknowledged.
    ack_to(s, a, a.rcv_nxt, window=0)
    s.run(s.now + 20 * MS)
    a.write(data)
    s.wait_for(s.now + p.answer, lambda x: a.ours(x) and x.tcp.ack == a.snd_nxt and not a.pending)
    ack_to(s, a, a.rcv_nxt, window=30000)
    s.wait_for(s.now + 150 * MS, lambda x: False)
    sent = a.data_segments[before:]
    if not sent:
        raise Fail('the shrink: nothing echoed by %s' % at(s.now))
    top = max(((x.tcp.seq + len(x.tcp.data) - first) & 0xFFFFFFFF) for x in sent)
    if top <= 1500:
        raise Fail('the shrink: only %d bytes out before it, not past the coming edge' % top)
    t = s.now
    edge = (first + 1500) & 0xFFFFFFFF
    ack_to(s, a, (first + 1000) & 0xFFFFFFFF, window=500)
    s.wait_for(t + 600 * MS, lambda x: False)
    for x in a.data_segments[before:]:
        # Before the shrink the band had nothing more it could send, its
        # send buffer full, so all it sends after is checked.
        if x.t <= t:
            continue
        end = (x.tcp.seq + len(x.tcp.data) - first) & 0xFFFFFFFF
        if end > max(top, 1500):
            raise Fail('new data past the shrunk window\'s edge (MUST-34, SHLD-15): %s' % x)
    if a.rst is not None:
        raise Fail('the shrink: the connection was reset: %s' % a.rst)
    a.window = 30000
    a.auto_ack = True
    ack_to(s, a, a.rcv_nxt)
    quiet_on(s, a, 'after the edge moved on', limit=10 * S)
    if a.received[base:] != data:
        raise Fail('after the shrink: %d of %d bytes echoed' % (len(a.received) - base, len(data)))
    return 'no new data past a window shrunk below SND.NXT (%d bytes out); the data after' % top


# The ISN's clock bound (section 9, T1, ISN; F46): the band reads the clock
# as it takes each SYN, up to a tick and the pass latency after the SYN
# arrives, and either SYN may be the late one, so a tick and the pass
# latency's worth in 4 us units, rounded up: 4,417 at 1 ms.  Taken from
# TICK and PASS_LATENCY, so that PASS_LATENCY stays its one place.
ISN_SLACK = -(-(TICK + PASS_LATENCY) // 4000)


def isn(s):
    """Two connections on one four-tuple 1 s apart get ISNs 250,000 apart
    (the clock in 4 us units), within a tick and the pass latency's worth,
    ISN_SLACK (4,417 at 1 ms), since the band reads the clock as it takes
    each SYN, up to a tick and the pass latency after it arrives; two
    four-tuples at one time get ISNs more than that apart, so that their
    hashes differ and not only their clock terms (section 5.5; RFC 6528;
    O2; F30; F46)."""
    p = s.p
    s.boot()
    a = s.connect(40111, p.telnet_port, ISN_A, F.opt_mss(1460))
    a.auto_ack = False
    t_a = s.now
    s.wait_for(s.now + p.answer, lambda x: a.synack is not None)
    if a.synack is None:
        raise Fail('no SYN-ACK by %s' % at(s.now))
    raw_segment(s, a, F.RST, a.snd_nxt, 0)
    s.conns.remove(a)
    s.run(t_a + 1 * S)
    b = s.connect(40111, p.telnet_port, (ISN_A + 7) & 0xFFFFFFFF, F.opt_mss(1460))
    b.auto_ack = False
    t_b = s.now
    s.wait_for(s.now + p.answer, lambda x: b.synack is not None)
    if b.synack is None:
        raise Fail('no SYN-ACK to the second SYN on the four-tuple by %s' % at(s.now))
    raw_segment(s, b, F.RST, b.snd_nxt, 0)
    s.conns.remove(b)
    step = (b.irs - a.irs) & 0xFFFFFFFF
    want = (t_b - t_a) // 4000
    if abs(step - want) > ISN_SLACK:
        raise Fail('two ISNs on one four-tuple %s apart differ by %d, not %d within %s' % (
            at(t_b - t_a), step, want, format(ISN_SLACK, ',')))
    x = s.connect(40112, p.telnet_port, ISN_B, F.opt_mss(1460))
    y = s.connect(40113, p.telnet_port, ISN_B, F.opt_mss(1460))
    x.auto_ack = y.auto_ack = False
    s.wait_for(s.now + p.answer, lambda z: x.synack is not None and y.synack is not None)
    if x.synack is None or y.synack is None:
        raise Fail('no SYN-ACKs to two SYNs at once by %s' % at(s.now))
    d = (x.irs - y.irs) & 0xFFFFFFFF
    if min(d, 2 ** 32 - d) <= ISN_SLACK:
        raise Fail('two four-tuples at one time got ISNs %d apart, within a tick and the pass latency\'s worth, %s (F30, F46)'
                   % (min(d, 2 ** 32 - d), format(ISN_SLACK, ',')))
    return 'ISNs %d apart in %s; two four-tuples different' % (step, at(t_b - t_a))


# --------------------------------------------------------------------------
# Slice 5 (section 9, T1; F31): URG at the band's zero window, the SYN-ACK's
# RTO cap and R2, RFC 6298 (5.7), FIN-WAIT-2's 60 s, sequence wrap with the
# ISN hook, the band's ping.

def urgent_segment(s, c, data, urg):
    """DATA at C's RCV.NXT with URG and the urgent pointer URG."""
    p = s.p
    seg = F.tcp(p.peer_ip, p.band_ip, c.sport, c.dport, c.snd_nxt, c.rcv_nxt, F.ACK | F.URG | F.PSH, c.window,
                data, urg=urg)
    c.offers.append((s.now, c.window, c.rcv_nxt))
    s.ipv4_to_band(F.IP_TCP, seg)


def urgent(s):
    """The urgent pointer points to the octet after the urgent data, and the
    stream says how much is waiting, from the next octet the server reads to
    the pointer, those not yet received included (section 5.5, F32; MUST-30,
    -31, -33, -62).  On a quiet echo connection, whose server has read all
    it got, one octet with URG and an urgent pointer of 10 leaves 9 waiting,
    8 more leave 1, and the tenth none: urgent mode is left (RFC 9293
    section 3.8.5).  At the band's own zero window a segment with data and
    URG is answered with an ACK of RCV.NXT, its data not taken (read where
    the band's segments settle, so that a persist probe is not taken for
    the answer), but its urgent pointer is: urgent data waiting, at least 10
    octets and at most 8,202, the buffer's 8,192 and the pointer's 10 (MUST-66,
    RFC 9293 section 3.4; F31, F32)."""
    p = s.p
    s.boot()
    c = control(s)
    ask(s, c, 'echo-on')
    # The quiet connection: the echo service reads all it gets, and the
    # peer acknowledges the echoes, so the read point is RCV.NXT.
    q = echo_conn(s, 40123, ISN_B, mss=1460, what='a quiet echo connection')
    q.auto_ack = True
    before = ask(s, c, 'urgent', q.sport)
    if before != [0, 0]:
        raise Fail('urgent data waiting before any was sent: the stream says %s' % before)
    got = len(q.received)
    urgent_segment(s, q, b'U', 10)
    q.snd_nxt = (q.snd_nxt + 1) & 0xFFFFFFFF
    for n_sent, more, want, what in ((1, b'u' * 8, [1, 9], 'one octet with an urgent pointer of 10 read'),
                                     (9, b'u', [1, 1], '8 more read'),
                                     (10, b'', [0, 0], 'the tenth read')):
        quiet_on(s, q, 'the urgent data echoed')
        if len(q.received) - got != n_sent:
            raise Fail('the urgent data: %d octets echoed, not the %d sent' % (len(q.received) - got, n_sent))
        state = ask(s, c, 'urgent', q.sport)
        if state != want:
            raise Fail('urgent data, %s: the stream says %s, %d waiting, not %s, %d (MUST-33, -62; F32)' % (
                what, 'waiting' if state[0] else 'nothing', state[1], 'waiting' if want[0] else 'nothing',
                want[1]))
        q.write(more)
    # The band's zero window.
    e = echo_conn(s, 40115, ISN_A, mss=1460)
    fill(s, e)
    before = ask(s, c, 'urgent', e.sport)
    if before[0]:
        raise Fail('urgent data waiting before any was sent: %s' % before)
    t = s.now
    urgent_segment(s, e, b'!', 10)
    try:
        r = expect_ack(s, e, t, rel(e, e.snd_nxt), 'URG with data at the band\'s zero window')
    except Fail as x:
        raise Fail('%s, not an ACK of RCV.NXT' % x)
    if r.tcp.window != 0:
        raise Fail('URG with data at the band\'s zero window: the band\'s last answer has window %d, not 0: %s'
                   % (r.tcp.window, r))
    w, n = ask(s, c, 'urgent', e.sport)
    if not w or not 10 <= n <= 8202:
        raise Fail('URG at the band\'s zero window not processed: the stream says %s, %d waiting, not at least '
                   '10 and at most 8,202 (F32)' % ('urgent' if w else 'nothing', n))
    return 'quiet: 9, 1, then none waiting; at the zero window the pointer taken, the data not, %d to the ' \
           'pointer' % n


def synack_r2(s):
    """Two half-open connections, A and B, B's SYN 0.5 s after A's.  A's
    SYN-ACK, nobody acknowledging it, is resent at 1, 3, 7, 15, 31 and 63 s,
    then at 123 s, the RTO capped at 60 s, each within a tick; no ARP
    request for the peer comes before its third resend, and one between its
    third and fourth (R1 for a SYN-ACK's resends, MUST-20, -22; F33).  R2
    for a SYN-ACK is bracketed: A's ACK 180 s less a tick after its first
    SYN-ACK completes the handshake (the banner follows), and B's 180 s and
    a tick after its own gets LISTEN's RST, <SEQ=SEG.ACK><CTL=RST> (RFC 9293
    section 3.10.7.2): the half-open connection closes at R2, not at the
    next retransmission (section 5.5; F31).  Only A is timed: B's ARP request can fall inside A's intervals.  A
    long script: about 181 s."""
    p = s.p
    s.boot()
    # The band resolves the peer first, so that A's first SYN-ACK is not
    # held for ARP: held, it leaves the wire later than the band's R2 is
    # timed from, by the ARP round trip and the band's taking of the reply,
    # and A's ACK a tick before 180 s from it could come after R2.
    echo_answered(s, 0x5352, 1, 'an echo request before the SYNs')
    a = s.connect(40116, p.telnet_port, ISN_A, F.opt_mss(1460))
    a.auto_ack = False
    s.wait_for(s.now + 500 * MS, lambda x: False)     # in steps, so that the band's ARP is answered at once
    b = s.connect(40122, p.telnet_port, ISN_B, F.opt_mss(1460))
    b.auto_ack = False
    s.wait_for(s.now + p.answer, lambda x: a.synack is not None and b.synack is not None)
    if a.synack is None or b.synack is None:
        raise Fail('no SYN-ACK by %s' % at(s.now))
    t0 = a.synack.t
    s.wait_for(t0 + 180 * S - TICK, lambda x: False, step=LONG_STEP)
    syns = [y.t for y in a.segments if y.tcp.flags & F.SYN]
    gaps = [1, 2, 4, 8, 16, 32, 60]
    if len(syns) < len(gaps) + 1:
        raise Fail('the SYN-ACK resent %d times by %s, not 7' % (len(syns) - 1, at(s.now)))
    for k, g in enumerate(gaps):
        before = resent_at(s, syns[k - 1], syns[k]) if k else syns[0]
        near(resent_at(s, syns[k], syns[k + 1]) - before, g * S, 'SYN-ACK resend %d (the RTO capped at 60 s)' % (k + 1))
    if len(syns) > len(gaps) + 1:
        raise Fail('a SYN-ACK resent at %s, more than 7 times before R2 of 180 s' % at(syns[len(gaps) + 1] - t0))

    def arps(lo, hi):
        return [x for x in s.seen if x.arp and x.arp.op == F.ARP_REQUEST and x.arp.tpa == p.peer_ip
                and lo < x.t <= hi]
    if arps(syns[0], syns[3]):
        raise Fail('an ARP request for the peer before R1 = 3 resends of the SYN-ACK: %s' % arps(syns[0], syns[3])[0])
    if not arps(syns[3], syns[4]):
        raise Fail('no ARP request for the peer between the SYN-ACK\'s third and fourth resends (R1, MUST-20, '
                   '-22; F33)')
    # A, a tick before R2: still half-open, so its ACK completes the
    # handshake and the banner follows.
    t = s.now
    raw_segment(s, a, F.ACK, a.snd_nxt, (a.irs + 1) & 0xFFFFFFFF)
    # B, a tick and the pass latency after R2: back in LISTEN.
    tb = max(s.now, b.synack.t + 180 * S + TICK + PASS_LATENCY)
    s.run(tb)
    ack_b = (b.irs + 1) & 0xFFFFFFFF
    raw_segment(s, b, F.ACK, b.snd_nxt, ack_b)
    s.wait_for(tb + p.answer, lambda x: (a.rst is not None or a.data_segments)
               and any(y.t > tb for y in b.segments))
    if a.rst is not None and a.rst.t > t:
        raise Fail('R2 for a SYN-ACK before 180 s less a tick: the ACK is answered by RST: %s' % a.rst)
    if not a.data_segments:
        raise Fail('R2 for a SYN-ACK: no banner after the ACK 180 s less a tick after the first SYN-ACK, by %s'
                   % at(s.now))
    r = next((y for y in b.segments if y.t > tb), None)
    if r is None or r.tcp.flags & (F.RST | F.ACK | F.SYN) != F.RST or r.tcp.seq != ack_b:
        raise Fail('R2 for a SYN-ACK: the ACK 180 s and a tick after the first SYN-ACK is answered by %s, not '
                   'LISTEN\'s RST <SEQ=%d><CTL=RST>' % (r or 'nothing', ack_b))
    raw_segment(s, a, F.RST, a.snd_nxt, 0)      # done with A
    return 'resent at 1, 3, 7, 15, 31, 63 and 123 s, ARP again after R1; alive 180 s - tick, gone 180 s + tick'


def rule_5_7(s):
    """After a resent SYN-ACK: the first RTO of data is 3 s (RFC 6298 (5.7);
    F31), and the initial window is one segment (RFC 5681 section 3.1; F34).
    Of a 1,072-byte echo, two segments of 536, one goes and the other waits
    for its ACK; the first is resent after 3 s within a tick, and the echo
    then completes exactly."""
    p = s.p
    s.boot()
    c = control(s)
    ask(s, c, 'echo-on')
    e = s.connect(40117, p.echo_port, ISN_B, F.opt_mss(536))
    e.auto_ack = False
    s.wait_for(s.now + 1500 * MS, lambda x: len([y for y in e.segments if y.tcp.flags & F.SYN]) >= 2)
    if len([y for y in e.segments if y.tcp.flags & F.SYN]) < 2:
        raise Fail('the SYN-ACK was not resent by %s' % at(s.now))
    e.ack()
    s.run(s.now + 20 * MS)
    data = bytes((i * 29 + 5) & 255 for i in range(2 * 536))
    start = len(e.received)
    e.write(data)
    first = s.wait_for(s.now + p.answer, lambda x: e.ours(x) and x.tcp.data)
    if first is None:
        raise Fail('no echo by %s' % at(s.now))
    s.wait_for(first.t + 3 * S + 2 * TICK + PASS_LATENCY, lambda x: copies(e, first.tcp.seq, first.t))
    other = [x for x in e.data_segments if x.tcp.seq != first.tcp.seq]
    if other:
        raise Fail('after a resent SYN-ACK more than one segment went before the first ACK (an initial window '
                   'of one segment, RFC 5681 section 3.1; F34): %s after %s' % (other[0], first))
    r = copies(e, first.tcp.seq, first.t)
    if not r:
        raise Fail('the first data after a resent SYN-ACK: not resent by %s' % at(s.now))
    near(r[0].t - first.t, 3 * S, 'the first RTO of data after a resent SYN-ACK (RFC 6298 (5.7))')
    e.auto_ack = True
    ack_to(s, e, e.rcv_nxt)
    quiet_on(s, e, 'the rest of the echo')
    if e.received[start:] != data:
        raise Fail('after a resent SYN-ACK: %d of %d bytes echoed' % (len(e.received) - start, len(data)))
    return 'one segment of %d before the first ACK; resent after 3 s; 1,072 bytes echoed' % len(first.tcp.data)


FIN_ACK_DELAY = 50 * MS


def fin_wait_2(s):
    """The band closes first (the application's own close, F36) and the
    peer sends no FIN: FIN-WAIT-2 ends 60 s after the band's FIN, within a
    tick, probed once on each of two connections.  The origin is the band's
    FIN, which is on the wire (F35), not the peer's ACK of it: the peer
    acknowledges the FIN 50 ms after it, more than a tick, so that a band
    timing from the ACK is still there at B's probe.  Until the probe the
    band sends no RST on either: a later close by its server sends nothing
    (F36).  Section 5.5; F31.  A long script: about 62 s."""
    p = s.p
    s.boot()
    c = control(s)
    rec = {}
    for name, port in (('A', 40118), ('B', 40119)):
        x = settled_conn(s, port, p.telnet_port, (ISN_A + port * 977) & 0xFFFFFFFF, 'connection %s' % name,
                         auto_ack=False)
        ask(s, c, 'close', port, port)
        f = band_fin(s, x, 'connection %s' % name)
        # The peer's ACK of the FIN, on purpose and late; none of ours.
        s.run(max(s.now, f.t + FIN_ACK_DELAY))
        ack_to(s, x, (f.tcp.seq + 1) & 0xFFFFFFFF)
        rec[name] = (x, f.t)
    xa, fa = rec['A']
    xb, fb = rec['B']
    s.wait_for(fa + 60 * S - TICK, lambda y: False, step=LONG_STEP)
    for x in (xa, xb):
        if x.rst is not None:
            raise Fail('an RST on a connection the band had closed, before its FIN-WAIT-2 ended (a later close '
                       'by its server sends nothing, F36): %s' % x.rst)
    if probe(s, xa, 'FIN-WAIT-2 at 60 s less a tick') != 'ACK':
        raise Fail('FIN-WAIT-2 ended before 60 s less a tick from the band\'s FIN (%s)' % at(fa))
    s.wait_for(max(s.now, fb + 60 * S + TICK + PASS_LATENCY), lambda y: False, step=LONG_STEP)
    if xb.rst is not None:
        raise Fail('an RST on a connection the band had closed, before its FIN-WAIT-2 ended (a later close '
                   'by its server sends nothing, F36): %s' % xb.rst)
    if probe(s, xb, 'FIN-WAIT-2 at 60 s and a tick') != 'RST':
        raise Fail('FIN-WAIT-2 still there 60 s and a tick after the band\'s FIN (%s)' % at(fb))
    return 'FIN-WAIT-2 ended between 60 s - tick and 60 s + tick after the band\'s FIN, its ACK 50 ms later'


WRAP_BYTES = 1 << 20
WRAP_DEADLINE = 60 * S


def wrap(s):
    """Both ISNs near 2^32, the peer's by the script and the band's by the
    test hook on the control session (used once), and 1 MB echoed across
    both wraps, exactly (section 9, T1, Sequence wrap; F6)."""
    p = s.p
    s.boot()
    c = control(s)
    ask(s, c, 'echo-on')
    hook = 0xFFFFF000
    ask(s, c, 'isn-next', hook)
    # A SYN refused leaves the hook set: only the next SYN answered with a
    # SYN-ACK takes it (F36).
    d = s.connect(40124, 9, ISN_B, F.opt_mss(1460))
    s.wait_for(s.now + p.answer, lambda x: d.ours(x))
    refused(s, d, 'a SYN to the closed port 9 after the ISN hook')
    s.conns.remove(d)
    e = open_connection(s, 40120, p.echo_port, 0xFFFFF800, F.opt_mss(1460), 'the wrapping connection')
    if e.irs != hook:
        raise Fail('the ISN hook was not used by the next SYN answered, after a refused one: the SYN-ACK\'s ISN '
                   'is %d, not %d' % (e.irs, hook))
    e.ack()
    e.auto_ack = True
    data = bytes((i * 131 + (i >> 8)) & 255 for i in range(WRAP_BYTES))
    e.write(data)
    # 60 s of machine time for 1 MB is an assumed rate (about 17 KB/s), not
    # yet measured on the Lisp (E4's first run or T2's 1 MiB echo gives
    # it); a band slower than that fails here, naming the deadline.
    deadline = s.now + WRAP_DEADLINE
    while s.now < deadline and len(e.received) < len(data) and e.rst is None:
        s.run(s.now + p.step)
    if e.rst is None and len(e.received) < len(data):
        raise Fail('across the wraps: %d of %d bytes echoed by the deadline, %s of machine time (an assumed '
                   'rate; E4 measures it)' % (len(e.received), len(data), at(WRAP_DEADLINE)))
    quiet_on(s, e, 'the wrap')
    if e.received != data:
        raise Fail('across the wraps: %d of %d bytes echoed%s' % (
            len(e.received), len(data), '' if len(e.received) != len(data) else ', differing'))
    other = open_connection(s, 40121, p.echo_port, ISN_A, F.opt_mss(1460), 'a connection after the hook')
    if other.irs == hook:
        raise Fail('the ISN hook used twice: the next connection\'s ISN is %d again' % hook)
    return '1 MB echoed across both wraps (band ISN %d, peer ISN %d)' % (hook, 0xFFFFF800)


def off_subnet(p):
    """An address on no subnet of the band's, from the documentation ranges
    (RFC 5737), so that its route is the gateway."""
    mask = (0xFFFFFFFF << (32 - p.prefix)) & 0xFFFFFFFF
    for a in ('192.0.2.9', '198.51.100.9', '203.0.113.9'):
        if int.from_bytes(F.ip(a), 'big') & mask != int.from_bytes(p.band_ip, 'big') & mask:
            return F.ip(a)
    raise Fail('no documentation address off the band\'s subnet')


def ping_request(s, c, dst, what):
    """Type the ping form for DST on the control session; return its echo
    request and the mark in the session's output."""
    form, _ = CONTROL['ping']
    mark = len(c.received)
    t = s.now
    c.write((form % tuple(dst)).encode() + b'\r')
    req = s.wait_for(t + 2 * S, lambda x: x.t > t and x.icmp is not None and x.icmp.type == F.ICMP_ECHO)
    asked = [x for x in s.seen if x.t > t and x.arp and x.arp.op == F.ARP_REQUEST and x.arp.tpa != s.p.peer_ip]
    if asked:
        # Off the subnet the route is the gateway: no ARP for the address.
        raise Fail('the band\'s ping of %s asked ARP for %s, not the gateway: %s' % (
            what, F.ip_text(asked[0].arp.tpa), asked[0]))
    if req is None:
        raise Fail('the band\'s ping of %s sent no echo request by %s' % (what, at(s.now)))
    if req.ip.dst != dst:
        raise Fail('the band\'s ping of %s sent its echo request to %s' % (what, F.ip_text(req.ip.dst)))
    return req, mark


def ping_report(s, c, mark, until):
    """The ping's report in the control session's output since MARK, by
    UNTIL: (identifier, sequence), 'nothing', or None if none came."""
    m = re.search(CONTROL['ping'][1].encode(), c.received[mark:])
    while m is None and s.now < until:
        s.run(min(s.now + s.p.step, until))
        m = re.search(CONTROL['ping'][1].encode(), c.received[mark:])
    if m is None:
        return None
    if not (m.group(1).isdigit() and m.group(2).isdigit()):
        return 'nothing'
    return int(m.group(1)), int(m.group(2))


def report_text(r):
    """A ping report (ping_report's) in words."""
    if r is None or r == 'nothing':
        return r or 'nothing at all'
    return 'id %d seq %d' % r


def ping(s):
    """The band's ping, called on the control session (section 5.4; F5,
    F36).  Of the peer: its echo request goes to the peer's address and
    passes every check of a sent Ethernet frame; replies with another
    sequence and with another identifier are ignored, so nothing is
    reported in the 300 ms after them; the right reply then is the one
    reported.  Of an address off the subnet: its echo request goes through
    the gateway, to the gateway's MAC address with no ARP request for the
    address itself (section 5.3, Routing), and its reply is reported."""
    p = s.p
    s.boot()
    c = control(s)
    req, mark = ping_request(s, c, p.peer_ip, 'the peer')
    m = req.icmp
    s.ipv4_to_band(F.IP_ICMP, F.icmp(F.ICMP_ECHO_REPLY, 0, m.ident, (m.seq + 1) & 0xFFFF, m.data))
    s.run(s.now + 5 * MS)
    s.ipv4_to_band(F.IP_ICMP, F.icmp(F.ICMP_ECHO_REPLY, 0, m.ident ^ 0x0101, m.seq, m.data))
    early = ping_report(s, c, mark, s.now + 300 * MS)
    if early is not None:
        raise Fail('the band\'s ping reported %s before the reply matching its request came (id %d seq %d; '
                   'replies of another sequence and another identifier must be ignored)' % (
                       report_text(early), m.ident, m.seq))
    s.ipv4_to_band(F.IP_ICMP, F.icmp(F.ICMP_ECHO_REPLY, 0, m.ident, m.seq, m.data))
    got = ping_report(s, c, mark, s.now + 2 * S)
    if got is None or got == 'nothing':
        raise Fail('the band\'s ping reported %s by %s, after the reply matching its request' % (
            report_text(got), at(s.now)))
    if got != (m.ident, m.seq):
        raise Fail('the band\'s ping reported id %d seq %d, not its own request\'s id %d seq %d' % (
            got + (m.ident, m.seq)))
    # Through the gateway: the peer is the gateway, and its MAC address is
    # the one check.py requires of every IPv4 datagram.
    far = off_subnet(p)
    req2, mark = ping_request(s, c, far, F.ip_text(far))
    m2 = req2.icmp
    s.ipv4_to_band(F.IP_ICMP, F.icmp(F.ICMP_ECHO_REPLY, 0, m2.ident, m2.seq, m2.data), src=far)
    got2 = ping_report(s, c, mark, s.now + 2 * S)
    if got2 != (m2.ident, m2.seq):
        raise Fail('the band\'s ping of %s reported %s, not id %d seq %d' % (
            F.ip_text(far), report_text(got2), m2.ident, m2.seq))
    return 'the ping of the peer ignored two wrong replies and reported the right one (id %d seq %d); %s through ' \
           'the gateway' % (got + (F.ip_text(far),))


ARP_LIFE = 600 * S      # section 5.2: each entry kept 10 minutes


def arp_cache(s):
    """The band's ARP entry for the peer is kept 10 minutes from the last
    ARP packet from the peer's address, request or reply, whatever its
    target, even while it is used, within a tick (section 5.2, F42; RFC 1122
    section 2.3.2.1).  An echo request makes the band resolve the peer; 10 s
    later the peer broadcasts an ARP request for another address, which
    restarts the 10 minutes and draws no reply.  An echo request 600 s, a
    tick and the pass latency after the band first used the entry is
    answered with no ARP request (the restart); one 600 s less a tick after
    the refresh too; one 600 s, a tick and the pass latency after the band's
    first datagram after the refresh needs a new request.  A long script:
    about 611 s."""
    p = s.p
    s.boot()

    def requests(lo, hi):
        return peer_requests(s, lo, hi)

    def echo(seq):
        t = s.now
        s.echo_request(0x4143, seq, b'arp cache %d' % seq)
        return t, s.wait_for(t + p.answer, lambda x: x.icmp is not None and x.icmp.type == F.ICMP_ECHO_REPLY)
    t = s.now
    s.echo_request(0x4143, 1, b'arp cache 1')
    req = s.wait_for(t + p.answer, lambda x: x.arp is not None and x.arp.op == F.ARP_REQUEST
                     and x.arp.tpa == p.peer_ip)
    if req is None:
        raise Fail('no ARP request for the peer by %s, with an echo request waiting' % at(s.now))
    learned = s.now                     # the peer's ARP reply goes now
    r = s.wait_for(learned + p.answer, lambda x: x.icmp is not None and x.icmp.type == F.ICMP_ECHO_REPLY)
    if r is None:
        raise Fail('no echo reply after the peer\'s ARP reply by %s' % at(s.now))
    used = r.t
    # The refresh: an ARP request from the peer for another address.
    s.wait_for(learned + 10 * S, lambda x: False, step=100 * MS)
    s.ether_to_band(F.ETH_ARP, F.arp(F.ARP_REQUEST, p.peer_mac, p.peer_ip, b'\0' * 6, off_subnet(p)),
                    dst=F.BROADCAST)
    refreshed = s.now
    t, r = echo(2)                      # taken after the refresh, in order
    if r is None:
        raise Fail('no echo reply after the peer\'s ARP request for another address, by %s' % at(s.now))
    if any(x.arp and x.t > refreshed for x in s.seen):
        raise Fail('an ARP packet after the peer\'s ARP request for another address: %s' % next(
            x for x in s.seen if x.arp and x.t > refreshed))
    after = r.t
    s.wait_for(used + ARP_LIFE + TICK + PASS_LATENCY, lambda x: False, step=1 * S)
    early = requests(req.t, s.now)
    if early:
        raise Fail('an ARP request for the peer before 10 minutes, with nothing sent: %s' % early[0])
    # Kept past 10 minutes from the learning: the refresh restarted it.
    t, r = echo(3)
    if requests(t, s.now):
        raise Fail('the ARP entry for the peer gone 600 s and a tick after it was learned (%s), though the peer\'s '
                   'ARP request at %s restarted its 10 minutes (F42): an ARP request at %s' % (
                       at(learned), at(refreshed), at(requests(t, s.now)[0].t)))
    if r is None:
        raise Fail('no echo reply 600 s after the ARP entry was learned, by %s' % at(s.now))
    # Still kept a tick before 10 minutes from the refresh.
    s.wait_for(refreshed + ARP_LIFE - TICK, lambda x: False, step=1 * S)
    t, r = echo(4)
    if requests(t, s.now):
        raise Fail('the ARP entry for the peer gone 600 s less a tick after the refresh (%s): an ARP request '
                   'at %s' % (at(refreshed), at(requests(t, s.now)[0].t)))
    if r is None:
        raise Fail('no echo reply 600 s less a tick after the refresh, by %s' % at(s.now))
    # Gone a tick and the pass latency after 10 minutes from the refresh,
    # timed from the band's first datagram after it, which follows the
    # refresh in the band's own order.
    s.run(max(s.now, after + ARP_LIFE + TICK + PASS_LATENCY))
    t, r = echo(5)
    asked = requests(t, r.t if r is not None else s.now)
    if not asked:
        raise Fail('the ARP entry for the peer still used 600 s and a tick after the refresh (%s): %s with no '
                   'ARP request (kept 10 minutes from the last ARP packet, even in use, section 5.2)' % (
                       at(refreshed), r or 'no echo reply'))
    if r is None:
        raise Fail('no echo reply after the new ARP request, by %s' % at(s.now))
    return 'refreshed at 10 s; kept at 600 s + tick from the learning and 600 s - tick from the refresh, gone at ' \
           '600 s + tick from it (a request at %s)' % at(asked[0].t)


def arp_hold(s):
    """One echo request with nothing answering the band's ARP requests: a
    second echo request while the first is held replaces it and the count
    of requests goes on, so three requests come and no fourth in the 3 s
    after the third; the peer's ARP reply, once the third has gone
    unanswered for the band's own interval (from its first two requests), a
    tick and the pass latency, draws no echo reply, the held datagram having
    dropped; the merge still learns it, the band being its target, so the
    next echo request is answered with no ARP request (section 5.2; F43,
    F44)."""
    p = s.p
    s.boot()
    s.arp_answer = False
    t0 = s.now
    s.echo_request(0x4148, 1, b'held 1')
    r1 = s.wait_for(t0 + p.answer, lambda x: x.arp is not None and x.arp.op == F.ARP_REQUEST
                    and x.arp.tpa == p.peer_ip)
    if r1 is None:
        raise Fail('no ARP request for the peer by %s, with an echo request waiting' % at(s.now))
    s.run(r1.t + 500 * MS)
    s.echo_request(0x4148, 2, b'held 2')
    s.wait_for(r1.t + 3 * S, lambda x: len(peer_requests(s, t0)) >= 3)
    reqs = peer_requests(s, t0)
    if len(reqs) < 3:
        raise Fail('%d ARP requests for the peer by %s, not 3' % (len(reqs), at(s.now)))
    a1, a2, a3 = (x.t for x in reqs[:3])
    gap = a2 - a1
    late = a3 + gap + TICK + PASS_LATENCY
    s.wait_for(late, lambda x: False)
    if len(peer_requests(s, t0)) > 3:
        raise Fail('a fourth ARP request for the peer: %s (three unanswered requests drop the datagram, and a newer '
                   'datagram does not restart the count, F43)' % peer_requests(s, t0)[3])
    t = s.now
    s.send(F.ether(p.band_mac, p.peer_mac, F.ETH_ARP, F.arp(F.ARP_REPLY, p.peer_mac, p.peer_ip, p.band_mac,
                                                         p.band_ip)))
    s.wait_for(max(t + p.answer, a3 + 3 * S), lambda x: False)
    sent = [x for x in s.seen if x.t > t and x.icmp is not None]
    if sent:
        raise Fail('the peer\'s ARP reply after the third request went unanswered for the band\'s interval drew %s: '
                   'the held datagram is dropped by then (F43)' % sent[0])
    if len(peer_requests(s, t0)) > 3:
        raise Fail('a fourth ARP request for the peer: %s (F43)' % peer_requests(s, t0)[3])
    t = s.now
    s.echo_request(0x4148, 3, b'held 3')
    e = s.wait_for(t + p.answer, lambda x: x.icmp is not None and x.icmp.type == F.ICMP_ECHO_REPLY)
    if peer_requests(s, t) or e is None:
        raise Fail('after the peer\'s late ARP reply an echo request %s: the merge learns a reply to the band '
                   '(F44)' % ('drew an ARP request' if peer_requests(s, t) else 'got no reply'))
    if e.icmp.seq != 3:
        raise Fail('after the late ARP reply the band answered %s' % e)
    return 'three requests %s apart, no fourth; the late reply sent nothing and was learned' % at(gap)


def r2_hook(s):
    """R2 set for one connection by its keyword, through the control
    session's R2 hook (MUST-21; F41): connection A, accepted after the hook
    is set to 10 s, and B after it, each with data nobody acknowledges.  A
    still answers 10 s less a tick after the first transmission of its
    data, and 10 s, a tick and the pass latency after it is closed: the
    echo service saw SYS:HOST-STOPPED-RESPONDING, nothing more was resent,
    and its four-tuple gets RST; B, given the default, still answers then.
    About 12 s of machine time."""
    p = s.p
    s.boot()
    c = control(s)
    ask(s, c, 'echo-on')
    ask(s, c, 'r2-next', 10)
    a = echo_conn(s, 40125, ISN_A, what='connection A')
    b = echo_conn(s, 40126, ISN_B, what='connection B')
    a.write(b'r2 hook A')
    fa = s.wait_for(s.now + p.answer, lambda x: a.ours(x) and x.tcp.data == b'r2 hook A')
    b.write(b'r2 hook B')
    fb = s.wait_for(s.now + p.answer, lambda x: b.ours(x) and x.tcp.data == b'r2 hook B')
    if fa is None or fb is None:
        raise Fail('no echo on connection %s by %s' % ('A' if fa is None else 'B', at(s.now)))
    s.wait_for(fa.t + 10 * S - TICK, lambda x: False, step=LONG_STEP)
    t = s.now
    raw_segment(s, a, F.ACK, a.iss, fa.tcp.seq, b'\0')
    r = s.wait_for(t + 2 * TICK, lambda x: x.t > t and a.ours(x))
    if r is None or r.tcp.flags & F.RST:
        raise Fail('the R2 hook: connection A gone before 10 s less a tick: %s' % (r or 'no answer'))
    s.wait_for(fa.t + 10 * S + TICK + PASS_LATENCY, lambda x: False, step=LONG_STEP)
    cond = ask(s, c, 'condition')[0]
    if 'HOST-STOPPED-RESPONDING' not in cond.upper():
        raise Fail('the R2 hook: 10 s and a tick after connection A\'s data the echo service saw %s, not '
                   'SYS:HOST-STOPPED-RESPONDING (R2 of 10 s by the keyword, MUST-21)' % cond)
    late = [x for x in a.segments if x.t > fa.t + 10 * S + TICK + PASS_LATENCY and not x.tcp.flags & F.RST]
    if late:
        raise Fail('the R2 hook: connection A sent after 10 s and a tick: %s' % late[0])
    if probe(s, a, 'connection A after its R2 of 10 s') != 'RST':
        raise Fail('the R2 hook: connection A still there after its R2 of 10 s')
    if probe(s, b, 'connection B, accepted after A') != 'ACK':
        raise Fail('the R2 hook: connection B, accepted after A, gone too: the hook used for more than one '
                   'connection (F41)')
    return 'connection A closed at its R2 of 10 s (%s); B kept the default' % cond


SCRIPTS = {
    'arp': arp,
    'arp-cache': arp_cache,
    'arp-hold': arp_hold,
    'icmp-echo': icmp_echo,
    'handshake': handshake,
    'mss': mss,
    'other-types': other_types,
    'data': data,
    'options': options,
    'checksums-received': checksums_received,
    'ip-options': ip_options,
    'rst': rst,
    'syn': syn,
    'close': close,
    'time-wait': time_wait,
    'rto': rto,
    'rto-restart': rto_restart,
    'cwnd-reset': cwnd_reset,
    'r2': r2,
    'r2-hook': r2_hook,
    'zero-window': zero_window,
    'own-zero-window': own_zero_window,
    'must-38': must_38,
    'shrink': shrink,
    'isn': isn,
    'urgent': urgent,
    'synack-r2': synack_r2,
    'rule-5-7': rule_5_7,
    'fin-wait-2': fin_wait_2,
    'wrap': wrap,
    'ping': ping,
}
