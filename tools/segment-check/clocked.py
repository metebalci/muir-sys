"""The peer's side of muir's clocked Ethernet socket.

QUUX's Ethernet contract, section 3: muir connects as a client to a UNIX
stream socket (`--ethernet-socket PATH,clocked`).  Every record is
[u32 length][u64 machine ns][Ethernet frame], big-endian.  A record of length
0 is a control record: from the peer "run until" its time, from muir
"reached" its time.  muir runs to the time the peer last named, sends the
Ethernet frames the band sent since its last "reached", each with its time,
then "reached", and waits; a frame from the peer is delivered at the first
clock at or after its time, never before the time already reached.

Peer listens, accepts muir, and keeps the machine clock (`now`, the last
"reached"), the frames waiting to be delivered, and every frame the band has
sent with its time (`sent`), so that two runs can be compared bit for bit.
Python's standard library only.
"""

import os
import select
import socket
import struct

HEAD = struct.Struct('>IQ')
MAX_FRAME = 65535


class PeerError(Exception):
    """The machine broke the protocol, closed the socket or went silent: a
    fault of the harness or the machine, never a band's failing check."""


class Peer:
    def __init__(self, path, wall_timeout=600.0):
        """Listen on the UNIX socket PATH.  WALL_TIMEOUT is the host's
        seconds a single "run until" may take before the run is given up."""
        self.path = path
        self.wall_timeout = wall_timeout
        if os.path.exists(path):
            os.unlink(path)
        self.listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.listener.bind(path)
        self.listener.listen(1)
        self.conn = None
        self.now = None          # the machine time last reached, ns
        self.outgoing = []       # records not yet written
        self.sent = []           # [(ns, frame)] the band sent, in order
        self.records = 0         # control records exchanged, for the log
        self._buf = b''

    def accept(self, wall_timeout=120.0, alive=None):
        """Wait for muir to connect, then for its first "reached".  ALIVE,
        when given, is called every half second and returns a reason when
        the machine has died before connecting."""
        waited = 0.0
        while True:
            r, _, _ = select.select([self.listener], [], [], 0.5)
            if r:
                break
            waited += 0.5
            if alive is not None:
                why = alive()
                if why:
                    raise PeerError('the machine stopped before connecting: %s' % why)
            if waited >= wall_timeout:
                raise PeerError('no machine connected in %.0f s of wall time' % wall_timeout)
        self.conn, _ = self.listener.accept()
        self.listener.close()
        os.unlink(self.path)
        self._wait_reached()
        return self.now

    # ----------------------------------------------------------------------
    def deliver(self, frame, at=None):
        """Queue FRAME to be delivered at machine time AT (default: now).
        Delivery happens at the first clock at or after AT."""
        if at is None:
            at = self.now
        if at < self.now:
            raise PeerError('a delivery at %d ns, before the time reached, %d ns' % (at, self.now))
        if not 0 < len(frame) <= MAX_FRAME:
            raise PeerError('a frame of %d bytes cannot be sent' % len(frame))
        self.outgoing.append(HEAD.pack(len(frame), at) + bytes(frame))

    def run_until(self, t):
        """Send what is queued and "run until T"; return the frames the band
        sent meanwhile, [(ns, frame)]."""
        first = len(self.sent)
        data = b''.join(self.outgoing) + HEAD.pack(0, t)
        self.outgoing = []
        try:
            self.conn.sendall(data)
        except OSError as e:
            raise PeerError('writing to the machine: %s' % e)
        self._wait_reached()
        if self.now < t:
            raise PeerError('asked to run until %d ns, the machine reached %d ns' % (t, self.now))
        return self.sent[first:]

    def close(self):
        if self.conn is not None:
            try:
                self.conn.close()
            except OSError:
                pass
            self.conn = None

    # ----------------------------------------------------------------------
    def _read(self, n):
        while len(self._buf) < n:
            r, _, _ = select.select([self.conn], [], [], self.wall_timeout)
            if not r:
                raise PeerError('the machine sent nothing for %.0f s of wall time' % self.wall_timeout)
            try:
                chunk = self.conn.recv(65536)
            except OSError as e:
                raise PeerError('reading from the machine: %s' % e)
            if not chunk:
                raise PeerError('the machine closed the socket')
            self._buf += chunk
        out, self._buf = self._buf[:n], self._buf[n:]
        return out

    def _wait_reached(self):
        while True:
            length, t = HEAD.unpack(self._read(HEAD.size))
            if length == 0:
                if self.now is not None and t < self.now:
                    raise PeerError('"reached" %d ns after %d ns: time went back' % (t, self.now))
                self.now = t
                self.records += 1
                return
            frame = self._read(length)
            if self.sent and t < self.sent[-1][0]:
                raise PeerError('a frame sent at %d ns after one at %d ns' % (t, self.sent[-1][0]))
            self.sent.append((t, frame))
