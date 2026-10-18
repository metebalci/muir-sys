"""What a segment script runs on: the machine clock, the Ethernet frames
the band sends, each checked as it arrives, and the peer's side of a TCP
connection.

A script is written in machine time.  It queues Ethernet frames for the band
(`send`), runs the machine in steps (`run`, `wait_for`, `quiet`), and fails
with a reason (`Fail`) naming what it expected and the machine time by which
it did not come.  Every Ethernet frame the band sends passes through
check.problems first (QUUX's Ethernet contract, section 9, T1, "What every
script checks"), and through two checks that need the whole run: no two of
the band's IPv4 datagrams share a destination, protocol and identification
(section 5.3), and no data goes past the largest right edge the peer has
offered on its connection.  The first problem fails the script.

The timestamps option (RFC 7323; section 5.5, amendment 4) is checked by
connection, keyed by the four-tuple of the peer's latest SYN on it: a SYN-ACK
carries it only if that SYN did; once a SYN-ACK has carried it, every segment
on the connection but an RST carries it, a resent one too; without it, none
does; and the band's TSval on a connection never goes back, modulo 2^32.  The
peer's side (PeerConn) answers a timestamped connection as Linux does: the
option on every segment it sends, and 12 bytes less data in each.

Every Ethernet frame the scripts send shorter than 60 bytes is padded to 60
with nonzero bytes, as a NIC delivers it, so that a stack taking a length
from the Ethernet frame rather than from the IPv4 total length fails.

The scripts answer the band's ARP requests for the peer's own address
themselves unless a script turns that off (`arp_answer = False`), since
every exchange but ARP's own needs the band to reach the peer.
"""

import struct

import check
import frames as F

MS = 1_000_000
S = 1_000_000_000


class Fail(Exception):
    """A script's check failed: the band, not the harness."""


class Params:
    """The addresses and times a run uses.  The defaults are quux0's, which
    are muir's defaults since amendment 2 (QUUX's Ethernet contract, section
    3: tap quuxN's /30 has the peer at 169.254.1NN.1 and the band at
    169.254.1NN.2; --ethernet-mac 02:00:00:00:00:01 and the taps' MAC
    02:00:00:00:00:02).  They are flags of the runner, so a run can follow
    another tap's; every other address the scripts use (the subnet's
    broadcast, addresses off the subnet) is derived from these."""

    def __init__(self, band_mac='02:00:00:00:00:01', band_ip='169.254.100.2', prefix=30,
                 peer_mac='02:00:00:00:00:02', peer_ip='169.254.100.1', ttl=64,
                 boot_wait=120 * S, answer=1 * S, step=1 * MS, echo_port=7, telnet_port=23, pad=True):
        self.band_mac, self.peer_mac = F.mac(band_mac), F.mac(peer_mac)
        self.band_ip, self.peer_ip = F.ip(band_ip), F.ip(peer_ip)
        self.prefix, self.ttl = prefix, ttl
        self.boot_wait, self.answer, self.step = boot_wait, answer, step
        self.echo_port, self.telnet_port = echo_port, telnet_port
        self.pad = pad


class Seen:
    """One Ethernet frame the band sent, at machine time T, parsed."""

    def __init__(self, t, raw):
        self.t, self.raw = t, raw
        self.eth = F.parse_ether(raw)
        self.arp = self.ip = self.icmp = self.tcp = None
        if self.eth.error:
            return
        if self.eth.type == F.ETH_ARP:
            self.arp = F.parse_arp(self.eth.payload)
        elif self.eth.type == F.ETH_IPV4:
            self.ip = F.parse_ipv4(self.eth.payload)
            if self.ip.error:
                return
            if self.ip.proto == F.IP_ICMP:
                self.icmp = F.parse_icmp(self.ip.payload)
            elif self.ip.proto == F.IP_TCP:
                self.tcp = F.parse_tcp(self.ip.src, self.ip.dst, self.ip.payload)

    def __str__(self):
        return '%s at %s' % (F.describe(self.raw), at(self.t))


def at(ns):
    """A machine time for a message: seconds with nine places."""
    return '%d.%09d s' % divmod(ns, S)


class Session:
    def __init__(self, peer, params, note=None):
        self.peer, self.p = peer, params
        self.seen = []          # every Seen, in order
        self.arp_answer = True
        self.conns = []
        self.note = note or (lambda line: None)
        self.started = None     # the gratuitous ARP, once seen
        self.idents = {}        # (destination, protocol, identification) -> Seen
        self.peer_macs = None   # check.problems's; None for the peer's own
        # The timestamps option by four-tuple (peer address, peer port, band
        # port): whether the peer's latest SYN offered it, whether the band's
        # SYN-ACK carried it, and the band's latest segment with it.
        self.ts_syn, self.ts_conn, self.ts_last = {}, {}, {}

    @property
    def now(self):
        return self.peer.now

    # ----------------------------------------------------------------------
    def send(self, frame, at_=None):
        self.note_syn(frame)
        if self.p.pad and len(frame) < 60:
            frame = frame + bytes(0xA5 ^ i for i in range(60 - len(frame)))
        self.peer.deliver(frame, at_)

    def note_syn(self, frame):
        """A SYN the peer sends starts its four-tuple's timestamps afresh."""
        e = F.parse_ether(frame)
        if e.error or e.type != F.ETH_IPV4:
            return
        ip = F.parse_ipv4(e.payload)
        if ip.error or ip.proto != F.IP_TCP:
            return
        t = F.parse_tcp(ip.src, ip.dst, ip.payload)
        if t.error or not t.flags & F.SYN or t.flags & F.ACK:
            return
        key = (ip.src, t.sport, t.dport)
        self.ts_syn[key] = t.tsval is not None
        self.ts_conn.pop(key, None)
        self.ts_last.pop(key, None)

    def ts_problem(self, s):
        """What is wrong with band segment S's timestamps option, or None
        (RFC 7323 3.2; section 5.5)."""
        t = s.tcp
        key = (s.ip.dst, t.dport, t.sport)
        has = t.tsval is not None
        on = self.ts_conn.get(key)
        if t.flags & F.SYN:
            if has and not self.ts_syn.get(key):
                return 'the timestamps option on a SYN-ACK whose SYN offered none'
            if on and not has:
                return 'a SYN-ACK without the timestamps option on a timestamped connection'
            self.ts_conn[key] = has
        elif t.flags & F.RST:
            if has and not on:
                return 'the timestamps option on an RST of a connection without timestamps'
        elif on and not has:
            return 'a segment without the timestamps option on a timestamped connection'
        elif has and not on:
            return 'the timestamps option on a connection without timestamps'
        if has:
            last = self.ts_last.get(key)
            if last is not None and ((t.tsval - last.tcp.tsval) & 0xFFFFFFFF) >= 0x80000000:
                return 'TSval went back from %d (%s) to %d' % (last.tcp.tsval, last, t.tsval)
            self.ts_last[key] = s
        return None

    def ether_to_band(self, type_, payload, dst=None):
        self.send(F.ether(dst or self.p.band_mac, self.p.peer_mac, type_, payload))

    def ipv4_to_band(self, proto, payload, src=None, **kw):
        self.ether_to_band(F.ETH_IPV4, F.ipv4(src or self.p.peer_ip, self.p.band_ip, proto, payload, **kw))

    def run(self, until):
        """Run the machine to UNTIL; check and return what the band sent."""
        new = [Seen(t, raw) for t, raw in self.peer.run_until(until)]
        for s in new:
            self.seen.append(s)
            self.note('band %s' % s)
            bad = check.problems(s.raw, self.p, self.peer_macs)
            if bad:
                raise Fail('a bad Ethernet frame from the band (%s): %s' % ('; '.join(bad), s))
            if s.tcp is not None and not s.tcp.error:
                bad = self.ts_problem(s)
                if bad:
                    raise Fail('a bad Ethernet frame from the band (%s): %s' % (bad, s))
            if s.ip is not None:
                key = (s.ip.dst, s.ip.proto, s.ip.ident)
                if key in self.idents:
                    raise Fail('an IPv4 identification repeated, %d to %s protocol %d: %s and %s' % (
                        s.ip.ident, F.ip_text(s.ip.dst), s.ip.proto, self.idents[key], s))
                self.idents[key] = s
            if self.arp_answer and s.arp and s.arp.op == F.ARP_REQUEST and s.arp.tpa == self.p.peer_ip \
                    and s.arp.spa != s.arp.tpa:
                self.send(F.ether(s.arp.sha, self.p.peer_mac, F.ETH_ARP,
                                  F.arp(F.ARP_REPLY, self.p.peer_mac, self.p.peer_ip, s.arp.sha, s.arp.spa)))
            for c in self.conns:
                c.take(s)
        for c in self.conns:
            c.after_step()
        return new

    def wait_for(self, until, pred, step=None):
        """Run in steps (STEP, default the run's) until a frame the band
        sends satisfies PRED, and return it (a Seen), or None at machine
        time UNTIL.  The long scripts idle in larger steps."""
        while self.now < until:
            for s in self.run(min(self.now + (step or self.p.step), until)):
                if pred(s):
                    return s
        return None

    def quiet(self, until, pred, what, step=None):
        """Run to UNTIL; fail if the band sends a frame satisfying PRED."""
        s = self.wait_for(until, pred, step)
        if s is not None:
            raise Fail('%s: %s' % (what, s))

    def boot(self):
        """Wait for the band's gratuitous ARP, the network's start (section
        5.2), up to the boot wait, and return it; None if it never came.  The
        scripts then go on from here either way, so that each fails for its
        own reason on a band without the stack."""
        g = self.wait_for(self.p.boot_wait, self.is_gratuitous)
        self.started = g
        if g is None:
            self.note('no gratuitous ARP by %s; going on' % at(self.now))
        return g

    def is_gratuitous(self, s):
        return s.arp is not None and s.arp.spa == self.p.band_ip and s.arp.tpa == self.p.band_ip

    # ----------------------------------------------------------------------
    def echo_request(self, ident, seq, data, src=None):
        self.ipv4_to_band(F.IP_ICMP, F.icmp(F.ICMP_ECHO, 0, ident, seq, data), src=src)

    def connect(self, sport, dport, iss, options=b'', window=65535):
        c = PeerConn(self, sport, dport, iss, window)
        self.conns.append(c)
        c.syn(options)
        return c


# The peer's TSval on a timestamped connection: its own millisecond clock,
# machine time from this base, unless a script sets PeerConn.ts_val.
PEER_TS_BASE = 1000


class PeerConn:
    """The peer's side of one TCP connection: an active open, data sent in
    order within the band's window, and the band's data acknowledged at the
    end of each step.  The link is the clocked socket, which loses nothing, so
    the peer never retransmits.  When its SYN offered the timestamps option
    and the band's SYN-ACK carried it, every segment the peer sends carries
    it (TSval its clock, or ts_val when a script sets one; TSecr the band's
    latest TSval), unless a script leaves it out (ts_send, or segment's ts),
    and its segments hold 12 bytes less data, as Linux's do."""

    def __init__(self, s, sport, dport, iss, window):
        self.s, self.sport, self.dport = s, sport, dport
        self.iss, self.window = iss, window
        self.snd_nxt = iss              # the peer's next sequence number
        self.snd_una = iss
        self.irs = None                 # the band's ISN, from its SYN-ACK
        self.rcv_nxt = None
        self.synack = None
        self.received = b''             # the band's data, in order
        self.segments = []              # every Seen of this connection
        self.data_segments = []
        self.band_window = None
        self.band_mss = None
        self.pending = b''              # data still to send
        self.need_ack = False
        self.auto_ack = True
        self.rst = None
        self.fin = None
        self.offers = []                # (time, window, ack or None) the peer sent
        self.ack_quiet = 0              # hold an ACK until the band is this long quiet
        self.probes = []                # one-octet zero-window probes
        self.last_band = None           # the time of the band's last segment here
        self.ts_offered = False         # the SYN carried the timestamps option
        self.ts_ok = False              # and the band's SYN-ACK did too
        self.ts_val = None              # a fixed TSval a script sets; None for the clock
        self.ts_base = PEER_TS_BASE     # the clock's TSval at machine time 0
        self.ts_recent = 0              # the band's latest TSval, echoed
        self.ts_send = True

    def ours(self, s):
        t = s.tcp
        return t is not None and t.sport == self.dport and t.dport == self.sport

    def tsval_now(self):
        if self.ts_val is not None:
            return self.ts_val & 0xFFFFFFFF
        return (self.ts_base + self.s.now // MS) & 0xFFFFFFFF

    def segment(self, flags, data=b'', seq=None, options=b'', ack=True, ts=None):
        p = self.s.p
        if self.ts_ok and (self.ts_send if ts is None else ts) and not F.has_timestamps(options):
            options = options + F.OPT_NOP + F.OPT_NOP + F.opt_timestamps(self.tsval_now(), self.ts_recent)
        a = self.rcv_nxt if (ack and self.rcv_nxt is not None) else 0
        if ack and self.rcv_nxt is not None:
            flags |= F.ACK
        seg = F.tcp(p.peer_ip, p.band_ip, self.sport, self.dport, self.snd_nxt if seq is None else seq,
                    a, flags, self.window, data, options)
        self.offers.append((self.s.now, self.window, a if flags & F.ACK else None))
        self.s.ipv4_to_band(F.IP_TCP, seg)

    def right_edge(self, t):
        """The largest right edge the peer had offered in segments sent
        before machine time T, or None."""
        best = None
        for when, window, a in self.offers:
            if when >= t:
                break
            base = a if a is not None else ((self.irs + 1) & 0xFFFFFFFF if self.irs is not None else None)
            if base is None:
                continue
            edge = (base + window) & 0xFFFFFFFF
            if best is None or ((edge - best) & 0xFFFFFFFF) < 0x80000000:
                best = edge
        return best

    def current_edge(self):
        """The right edge of the peer's latest offer, or None."""
        for when, window, a in reversed(self.offers):
            if a is not None:
                return (a + window) & 0xFFFFFFFF
            if self.irs is not None:
                return (self.irs + 1 + window) & 0xFFFFFFFF
        return None

    def syn(self, options):
        self.ts_offered = F.has_timestamps(options)
        self.segment(F.SYN, options=options, ack=False)
        self.snd_nxt = (self.iss + 1) & 0xFFFFFFFF
        self.snd_una = self.snd_nxt

    def ack(self):
        self.segment(0)
        self.need_ack = False

    def take(self, s):
        if not self.ours(s):
            return
        t = s.tcp
        self.segments.append(s)
        self.last_band = s.t
        if t.tsval is not None:
            self.ts_recent = t.tsval
        if t.flags & F.RST:
            self.rst = s
            return
        if t.flags & F.SYN:
            if self.synack is None:
                self.synack = s
                self.irs = t.seq
                self.rcv_nxt = (t.seq + 1) & 0xFFFFFFFF
                self.band_mss = t.mss
                self.ts_ok = self.ts_offered and t.tsval is not None
            self.band_window = t.window
            return
        if t.flags & F.ACK and self.irs is not None:
            if ((t.ack - self.snd_una) & 0xFFFFFFFF) <= ((self.snd_nxt - self.snd_una) & 0xFFFFFFFF):
                self.snd_una = t.ack
            self.band_window = t.window
        if t.data:
            edge = self.right_edge(s.t)
            end = (t.seq + len(t.data)) & 0xFFFFFFFF
            if len(t.data) == 1 and self.window == 0 and t.seq == self.rcv_nxt:
                # A zero-window probe of one octet of new data at the
                # current edge, RCV.NXT while the window is 0 (RFC 9293
                # section 3.8.6.1, MUST-36; F27): past the edge by design,
                # and not taken.
                self.probes.append(s)
                self.need_ack = True
                return
            if edge is None or 0 < ((end - edge) & 0xFFFFFFFF) < 0x80000000:
                raise Fail('data past the right edge the peer offered (%s): %s' % (
                    'none offered' if edge is None else 'it ends %d bytes past %d' % ((end - edge) & 0xFFFFFFFF,
                                                                                    edge), s))
            self.data_segments.append(s)
            if t.seq == self.rcv_nxt:
                # The peer takes data only within the window it last
                # offered, as a receiver does, and acknowledges the rest
                # untaken (RFC 9293 section 3.10.7.4).
                cur = self.current_edge()
                room = len(t.data) if cur is None else (cur - self.rcv_nxt + 2 ** 31) % 2 ** 32 - 2 ** 31
                take = t.data[:max(0, room)]
                self.received += take
                self.rcv_nxt = (self.rcv_nxt + len(take)) & 0xFFFFFFFF
            self.need_ack = True
        if t.flags & F.FIN and self.rcv_nxt is not None and \
                ((t.seq + len(t.data)) & 0xFFFFFFFF) == self.rcv_nxt:
            self.fin = s
            self.rcv_nxt = (self.rcv_nxt + 1) & 0xFFFFFFFF
            self.need_ack = True

    def after_step(self):
        """Send what the band's window allows, at most the band's MSS a
        segment, and acknowledge what came in this step."""
        sent = False
        if self.irs is not None and self.rst is None:
            mss = (self.band_mss or 536) - (12 if self.ts_ok else 0)
            while self.pending:
                in_flight = (self.snd_nxt - self.snd_una) & 0xFFFFFFFF
                room = (self.band_window or 0) - in_flight
                if room <= 0:
                    break
                n = min(mss, room, len(self.pending))
                chunk, self.pending = self.pending[:n], self.pending[n:]
                self.segment(F.PSH if not self.pending else 0, chunk)
                self.snd_nxt = (self.snd_nxt + n) & 0xFFFFFFFF
                sent = True
        # With ack_quiet the ACK waits until the band has been quiet on the
        # connection that long (contract section 9, T1, F15: a script that
        # fills the peer's window holds its ACK so that the edge stands still).
        due = self.last_band is None or self.s.now - self.last_band >= self.ack_quiet
        if self.need_ack and self.auto_ack and not sent and due:
            self.ack()
        self.need_ack = False if sent else self.need_ack

    def write(self, data):
        self.pending += data
