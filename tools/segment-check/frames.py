"""Ethernet II, ARP, IPv4, ICMP and TCP: building and parsing, with the
segment scripts' own checksum code.

QUUX's Ethernet contract, section 9, T1: every script checks every checksum
of every Ethernet frame the band sends "with its own code".  So nothing here
comes from muir's checksum offload; the Internet checksum is RFC 1071's sum,
written out below, and the TCP and ICMP checks are made over the pseudo-header
and the bytes as they arrive.  Python's standard library only.

A parse never raises on a malformed frame: it returns an object whose
`error` names what is wrong, so that a check can report it as a failure of
the band rather than as a crash of the harness.
"""

import struct

ETH_IPV4 = 0x0800
ETH_ARP = 0x0806
ETH_IPV6 = 0x86DD
ETH_CHAOS = 0x0804

IP_ICMP = 1
IP_TCP = 6

BROADCAST = b'\xff' * 6

# TCP flags, the low byte of the offset word.
FIN, SYN, RST, PSH, ACK, URG = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20


def mac(text):
    """'02:00:00:00:00:01' -> 6 bytes."""
    b = bytes(int(x, 16) for x in text.split(':'))
    if len(b) != 6:
        raise ValueError('a MAC address is six bytes: %r' % text)
    return b


def mac_text(b):
    return ':'.join('%02x' % x for x in b)


def ip(text):
    """'192.0.2.1' -> 4 bytes."""
    b = bytes(int(x) for x in text.split('.'))
    if len(b) != 4:
        raise ValueError('an IPv4 address is four bytes: %r' % text)
    return b


def ip_text(b):
    return '.'.join(str(x) for x in b)


# --------------------------------------------------------------------------
# The Internet checksum (RFC 1071), the scripts' own.

def ones_sum(data, start=0):
    """The 16-bit one's complement sum of DATA, big-endian words, an odd
    last byte padded with zero, folded."""
    s = start
    n = len(data)
    for i in range(0, n - 1, 2):
        s += (data[i] << 8) | data[i + 1]
    if n & 1:
        s += data[n - 1] << 8
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return s


def checksum(data, start=0):
    """The checksum field that makes DATA (with the field zero) sum to all
    ones."""
    return (~ones_sum(data, start)) & 0xFFFF


def pseudo_sum(src, dst, proto, length):
    """The TCP pseudo-header's sum: source, destination, zero and protocol,
    and the TCP length."""
    return ones_sum(src + dst + bytes([0, proto]) + struct.pack('>H', length))


# --------------------------------------------------------------------------
# Ethernet II

class Ether:
    def __init__(self, dst, src, type_, payload, error=None):
        self.dst, self.src, self.type, self.payload, self.error = dst, src, type_, payload, error


def ether(dst, src, type_, payload):
    return dst + src + struct.pack('>H', type_) + payload


def parse_ether(frame):
    if len(frame) < 14:
        return Ether(b'', b'', 0, b'', 'an Ethernet frame of %d bytes, under 14' % len(frame))
    if len(frame) > 1514:
        return Ether(frame[0:6], frame[6:12], 0, b'', 'an Ethernet frame of %d bytes, over 1514' % len(frame))
    t, = struct.unpack('>H', frame[12:14])
    return Ether(frame[0:6], frame[6:12], t, frame[14:])


# --------------------------------------------------------------------------
# ARP (RFC 826), Ethernet and IPv4 only

ARP_REQUEST, ARP_REPLY = 1, 2


class Arp:
    def __init__(self, op, sha, spa, tha, tpa, error=None):
        self.op, self.sha, self.spa, self.tha, self.tpa, self.error = op, sha, spa, tha, tpa, error


def arp(op, sha, spa, tha, tpa):
    return struct.pack('>HHBBH', 1, ETH_IPV4, 6, 4, op) + sha + spa + tha + tpa


def parse_arp(payload):
    if len(payload) < 28:
        return Arp(0, b'', b'', b'', b'', 'an ARP packet of %d bytes, under 28' % len(payload))
    htype, ptype, hlen, plen, op = struct.unpack('>HHBBH', payload[:8])
    a = Arp(op, payload[8:14], payload[14:18], payload[18:24], payload[24:28])
    if (htype, ptype, hlen, plen) != (1, ETH_IPV4, 6, 4):
        a.error = 'ARP for hardware %d, protocol 0x%04x, lengths %d and %d, not Ethernet and IPv4' % (
            htype, ptype, hlen, plen)
    elif op not in (ARP_REQUEST, ARP_REPLY):
        a.error = 'ARP operation %d' % op
    return a


# --------------------------------------------------------------------------
# IPv4 (RFC 791)

class Ipv4:
    def __init__(self):
        self.error = None


def ipv4(src, dst, proto, payload, ident=0, ttl=64, tos=0, df=False, mf=False, offset=0,
         options=b'', csum=None):
    """An IPv4 header and PAYLOAD; OPTIONS are padded with zeros to a
    multiple of four.  CSUM, when given, replaces the right checksum (a
    script that sends a bad one)."""
    options = options + b'\0' * (-len(options) % 4)
    ihl = 5 + len(options) // 4
    flags = (0x4000 if df else 0) | (0x2000 if mf else 0) | (offset & 0x1FFF)
    h = struct.pack('>BBHHHBBH4s4s', 0x40 | ihl, tos, 4 * ihl + len(payload), ident, flags,
                    ttl, proto, 0, src, dst) + options
    c = checksum(h) if csum is None else csum
    return h[:10] + struct.pack('>H', c) + h[12:] + payload


def parse_ipv4(payload):
    """The datagram in an Ethernet frame's PAYLOAD.  `pad` is what follows
    its total length."""
    p = Ipv4()
    p.raw = payload
    if len(payload) < 20:
        p.error = 'an IPv4 datagram of %d bytes, under 20' % len(payload)
        return p
    vi, p.tos, p.total, p.ident, flags, p.ttl, p.proto, p.csum, p.src, p.dst = struct.unpack(
        '>BBHHHBBH4s4s', payload[:20])
    p.version, p.ihl = vi >> 4, vi & 15
    p.df, p.mf, p.offset = bool(flags & 0x4000), bool(flags & 0x2000), flags & 0x1FFF
    p.reserved_flag = bool(flags & 0x8000)
    if p.version != 4:
        p.error = 'IPv4 version %d' % p.version
        return p
    if p.ihl < 5:
        p.error = 'IPv4 IHL %d, under 5' % p.ihl
        return p
    h = 4 * p.ihl
    if h > len(payload):
        p.error = 'IPv4 header of %d bytes in %d' % (h, len(payload))
        return p
    if p.total < h or p.total > len(payload):
        p.error = 'IPv4 total length %d, header %d, in %d bytes' % (p.total, h, len(payload))
        return p
    p.header = payload[:h]
    p.options = payload[20:h]
    p.payload = payload[h:p.total]
    p.pad = payload[p.total:]
    p.csum_ok = ones_sum(p.header) == 0xFFFF
    return p


# --------------------------------------------------------------------------
# ICMP (RFC 792): echo

ICMP_ECHO_REPLY, ICMP_ECHO = 0, 8


class Icmp:
    def __init__(self):
        self.error = None


def icmp(type_, code, ident, seq, data, csum=None):
    m = struct.pack('>BBHHH', type_, code, 0, ident, seq) + data
    c = checksum(m) if csum is None else csum
    return m[:2] + struct.pack('>H', c) + m[4:]


def parse_icmp(payload):
    m = Icmp()
    if len(payload) < 8:
        m.error = 'an ICMP message of %d bytes, under 8' % len(payload)
        return m
    m.type, m.code, m.csum, m.ident, m.seq = struct.unpack('>BBHHH', payload[:8])
    m.data = payload[8:]
    m.csum_ok = ones_sum(payload) == 0xFFFF
    return m


# --------------------------------------------------------------------------
# TCP (RFC 9293), options included

class Tcp:
    def __init__(self):
        self.error = None


def opt_mss(n):
    return struct.pack('>BBH', 2, 4, n)


OPT_NOP = b'\x01'
OPT_EOL = b'\x00'
OPT_SACK_PERMITTED = b'\x04\x02'


def opt_wscale(n):
    return bytes([3, 3, n])


def opt_timestamps(val, ecr):
    return struct.pack('>BBII', 8, 10, val, ecr)


# Linux's SYN: MSS, SACK permitted, timestamps, NOP, window scale.
def linux_syn_options(mss=1460, ts=1, wscale=7):
    return opt_mss(mss) + OPT_SACK_PERMITTED + opt_timestamps(ts, 0) + OPT_NOP + opt_wscale(wscale)


def tcp(src, dst, sport, dport, seq, ack, flags, window, data=b'', options=b'', urg=0, csum=None):
    """A TCP segment; OPTIONS are raw bytes, padded with zeros (EOL) to a
    multiple of four, so that a script can send them unaligned or unknown."""
    options = options + b'\0' * (-len(options) % 4)
    off = 5 + len(options) // 4
    h = struct.pack('>HHIIHHHH', sport, dport, seq & 0xFFFFFFFF, ack & 0xFFFFFFFF,
                    (off << 12) | flags, window, 0, urg) + options
    seg = h + data
    c = checksum(seg, pseudo_sum(src, dst, IP_TCP, len(seg))) if csum is None else csum
    return seg[:16] + struct.pack('>H', c) + seg[18:]


def parse_tcp_options(raw):
    """[(kind, body)] for RAW, or a string saying what is wrong: a zero or
    overlong length (MUST-7).  EOL ends the list; NOP is kept as (1, b'')."""
    out, i = [], 0
    while i < len(raw):
        kind = raw[i]
        if kind == 0:
            break
        if kind == 1:
            out.append((1, b''))
            i += 1
            continue
        if i + 1 >= len(raw):
            return 'option %d at %d has no length byte' % (kind, i)
        n = raw[i + 1]
        if n < 2:
            return 'option %d at %d has length %d' % (kind, i, n)
        if i + n > len(raw):
            return 'option %d at %d has length %d, past the header' % (kind, i, n)
        out.append((kind, raw[i + 2:i + n]))
        i += n
    return out


def parse_tcp(src, dst, payload):
    """The segment in an IPv4 PAYLOAD from SRC to DST."""
    s = Tcp()
    if len(payload) < 20:
        s.error = 'a TCP segment of %d bytes, under 20' % len(payload)
        return s
    (s.sport, s.dport, s.seq, s.ack, offw, s.window, s.csum, s.urg) = struct.unpack(
        '>HHIIHHHH', payload[:20])
    s.off = offw >> 12
    s.flags = offw & 0x3F
    s.reserved = (offw >> 6) & 0x3F
    if s.off < 5 or 4 * s.off > len(payload):
        s.error = 'TCP data offset %d in %d bytes' % (s.off, len(payload))
        return s
    s.raw_options = payload[20:4 * s.off]
    s.data = payload[4 * s.off:]
    s.csum_ok = ones_sum(payload, pseudo_sum(src, dst, IP_TCP, len(payload))) == 0xFFFF
    o = parse_tcp_options(s.raw_options)
    if isinstance(o, str):
        s.error = 'TCP options: ' + o
        s.options = []
    else:
        s.options = o
    s.mss = None
    for kind, body in s.options:
        if kind == 2:
            s.mss = struct.unpack('>H', body)[0] if len(body) == 2 else -1
    return s


def flags_text(f):
    return ''.join(c for c, b in (('F', FIN), ('S', SYN), ('R', RST), ('P', PSH), ('A', ACK),
                                  ('U', URG)) if f & b) or '-'


# --------------------------------------------------------------------------
# A one-line description, for logs and failure reasons.

def describe(frame):
    e = parse_ether(frame)
    if e.error:
        return e.error
    head = '%s>%s ' % (mac_text(e.src), mac_text(e.dst))
    if e.type == ETH_ARP:
        a = parse_arp(e.payload)
        if a.error:
            return head + a.error
        return head + 'ARP %s %s(%s) -> %s' % ('request' if a.op == 1 else 'reply', ip_text(a.spa),
                                                mac_text(a.sha), ip_text(a.tpa))
    if e.type != ETH_IPV4:
        return head + 'type 0x%04x, %d bytes' % (e.type, len(e.payload))
    p = parse_ipv4(e.payload)
    if p.error:
        return head + p.error
    head += '%s>%s ' % (ip_text(p.src), ip_text(p.dst))
    if p.proto == IP_ICMP:
        m = parse_icmp(p.payload)
        if m.error:
            return head + m.error
        return head + 'ICMP type %d code %d id %d seq %d, %d data' % (m.type, m.code, m.ident, m.seq,
                                                                     len(m.data))
    if p.proto == IP_TCP:
        s = parse_tcp(p.src, p.dst, p.payload)
        if s.error:
            return head + s.error
        return head + 'TCP %d>%d %s seq %d ack %d win %d len %d%s' % (
            s.sport, s.dport, flags_text(s.flags), s.seq, s.ack, s.window, len(s.data),
            ' mss %d' % s.mss if s.mss is not None else '')
    return head + 'protocol %d' % p.proto
