"""The checks every segment script makes of every Ethernet frame the band
sends (QUUX's Ethernet contract, section 9, T1, "Checksums sent"), with the
scripts' own checksum code (frames.py).

What a sent Ethernet frame must be, from the contract:
- its type IPv4 or ARP: the type filter refuses any other on transmit
  (section 2.4);
- its source the band's MAC address;
- ARP: Ethernet and IPv4, the band's MAC and IPv4 address as the sender
  (section 5.2); a reply goes to its target, except the gratuitous ARP's
  reply form, broadcast with sender and target address alike (RFC 5944
  section 4.6, which section 9 T1 accepts beside the request form);
- its length: 42 bytes for ARP and 14 + the total length for IPv4, since
  padding to 60 bytes is the host side's (section 2.3);
- IPv4: IHL 5, TOS 0, DF clear, not a fragment, TTL 64, the band's address
  as source, protocol ICMP or TCP, and a right header checksum
  (section 5.3, "Sent datagrams");
- ICMP: a right checksum;
- TCP: a right checksum; ACK set on every segment but an RST; options that
  parse; MSS only on a SYN; no window
  scaling, SACK or timestamps; no urgent data; at most 1,460 data bytes and
  a window of at most 8,192 (section 5.5).

`problems(frame, params)` returns a list of what is wrong, empty when
nothing is.
"""

import frames as F


def problems(frame, p, peer_macs=None):
    """PEER_MACS: the MAC addresses an IPv4 datagram may go to, by default
    the peer's alone (a script that moves the band's ARP entry for the peer
    allows the one it gave)."""
    out = []
    e = F.parse_ether(frame)
    if e.error:
        return [e.error]
    if e.src != p.band_mac:
        out.append('Ethernet source %s, not the band\'s %s' % (F.mac_text(e.src), F.mac_text(p.band_mac)))
    if e.type == F.ETH_ARP:
        a = F.parse_arp(e.payload)
        if a.error:
            return out + [a.error]
        if a.sha != p.band_mac:
            out.append('ARP sender MAC %s, not the band\'s' % F.mac_text(a.sha))
        if a.spa != p.band_ip:
            out.append('ARP sender address %s, not the band\'s' % F.ip_text(a.spa))
        if a.op == F.ARP_REPLY and e.dst != a.tha and a.spa != a.tpa:
            out.append('an ARP reply to %s sent to %s' % (F.mac_text(a.tha), F.mac_text(e.dst)))
        if len(frame) != 42:
            out.append('an ARP Ethernet frame of %d bytes, not 42' % len(frame))
        return out
    if e.type != F.ETH_IPV4:
        return out + ['the band sent Ethernet type 0x%04x, which the type filter refuses' % e.type]
    ip = F.parse_ipv4(e.payload)
    if ip.error:
        return out + [ip.error]
    if len(frame) != 14 + ip.total:
        out.append('an Ethernet frame of %d bytes for a total length of %d, not 14 + %d' % (
            len(frame), ip.total, ip.total))
    if not ip.csum_ok:
        out.append('a wrong IPv4 header checksum 0x%04x' % ip.csum)
    if ip.ihl != 5:
        out.append('IPv4 IHL %d, not 5' % ip.ihl)
    if ip.tos != 0:
        out.append('IPv4 TOS %d, not 0' % ip.tos)
    if ip.df:
        out.append('IPv4 DF set')
    if ip.mf or ip.offset or ip.reserved_flag:
        out.append('IPv4 fragment bits MF %d offset %d reserved %d' % (ip.mf, ip.offset, ip.reserved_flag))
    if ip.ttl != p.ttl:
        out.append('IPv4 TTL %d, not %d' % (ip.ttl, p.ttl))
    if ip.src != p.band_ip:
        out.append('IPv4 source %s, not the band\'s' % F.ip_text(ip.src))
    if e.dst not in (peer_macs or (p.peer_mac,)):
        out.append('an IPv4 datagram to Ethernet %s, not the peer\'s %s' % (
            F.mac_text(e.dst), F.mac_text(p.peer_mac)))
    if ip.proto == F.IP_ICMP:
        m = F.parse_icmp(ip.payload)
        if m.error:
            return out + [m.error]
        if not m.csum_ok:
            out.append('a wrong ICMP checksum 0x%04x' % m.csum)
        if (m.type, m.code) not in ((F.ICMP_ECHO_REPLY, 0), (F.ICMP_ECHO, 0)):
            out.append('ICMP type %d code %d, not an echo' % (m.type, m.code))
        return out
    if ip.proto != F.IP_TCP:
        return out + ['IPv4 protocol %d, not ICMP or TCP' % ip.proto]
    s = F.parse_tcp(ip.src, ip.dst, ip.payload)
    if s.error:
        return out + [s.error]
    if not s.csum_ok:
        out.append('a wrong TCP checksum 0x%04x' % s.csum)
    if s.reserved:
        out.append('TCP reserved bits %d' % s.reserved)
    if not s.flags & F.ACK and not s.flags & F.RST:
        # A receiver drops a segment without ACK in a synchronized state
        # (RFC 9293 section 3.10.7.4); the band opens passively only, so
        # every segment it sends but an RST answering one without ACK has it.
        out.append('a TCP segment without ACK')
    kinds = [k for k, _ in s.options if k != 1]
    if s.mss is not None and not s.flags & F.SYN:
        out.append('an MSS option on a segment without SYN')
    if s.mss == -1:
        out.append('an MSS option of the wrong length')
    for k in kinds:
        if k != 2:
            out.append('TCP option %d offered (no window scaling, SACK or timestamps)' % k)
    if s.flags & F.URG or s.urg:
        out.append('urgent data sent (URG %d, pointer %d)' % (bool(s.flags & F.URG), s.urg))
    if len(s.data) > 1460:
        out.append('%d data bytes in one segment, over 1,460' % len(s.data))
    if s.window > 8192:
        out.append('a window of %d, over the 8,192-byte buffer' % s.window)
    return out
