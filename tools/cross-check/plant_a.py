#!/usr/bin/env python3
"""The controls of same40.py, the comparison of contract G2 section 7's checks
(a) and (d) (its check (c)): for each rule by which same40.py lets two QFASLs
differ, a change planted inside a function that rule covers, which must be
reported, and the change the rule is for, which must not.

Usage: plant_a.py TREE
TREE holds sys/ with QFASLs of the 40-bit machine (a native build's).  Each
plant copies one QFASL to a scratch tree, changes words in it, and compares it
with the original (same40.py --floats).  Prints one line a plant and exits 1
when a plant is not judged as it must be.

  instruction in a float's function  one instruction halfword of a FEF that
                                     holds a float, flipped: must DIFFER
  float, one unit in the last place  must pass, the float listed
  float, two units                   must DIFFER
  compile time                       the attribute list's compile data: equal
  generated symbol's number          equal
  generated symbol made a plain one  its G made H: must DIFFER
  EXPR-SXHASH value                  equal
  a fixnum beside it                 another fixnum of that FEF: must DIFFER
  GENTEMP name in a local map        its number changed: equal
  a macro's hash in the record       (SI:FASL-RECORD-FILE-MACROS-EXPANDED): equal
  local-map name made another        its first letter changed: must DIFFER
"""
import io
import os
import shutil
import struct
import sys
import tempfile
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qfasl  # noqa: E402
import same40  # noqa: E402
from qfasl import Float32  # noqa: E402


class Where(qfasl.Decoder):
    """The decoder, keeping where in the file it read what a plant changes."""

    def __init__(self, data):
        super().__init__(data)
        self.at_floats, self.at_frames, self.at_symbols, self.at_fixed = [], [], [], []

    def op_float(self):
        p = self.pos
        r = super().op_float()
        f = self.table[r]
        if isinstance(f, Float32):
            self.at_floats.append((f.bits, p))
        return r

    def op_frame(self):
        r = super().op_frame()
        f = self.table[r]
        self.at_frames.append((f, self.pos - len(f.halfwords)))
        return r

    def op_symbol(self):
        p, n = self.pos, self.glen
        r = super().op_symbol()
        self.at_symbols.append((str(self.table[r]), p, n))
        return r

    def op_fixed(self):
        p, n = self.pos, self.glen
        r = super().op_fixed()
        self.at_fixed.append((self.table[r], p, n))
        return r


def words_of(path):
    data = open(path, 'rb').read()
    return list(struct.unpack('<%dH' % (len(data) // 2), data[:len(data) // 2 * 2])), data


def write(path, words, data):
    out = bytearray(data)
    struct.pack_into('<%dH' % len(words), out, 0, *words)
    open(path, 'wb').write(bytes(out))


def judge(orig_tree, rel, words, data):
    """same40 --floats on the planted file against the original: its output."""
    tmp = tempfile.mkdtemp(prefix='plant-a-')
    try:
        p = os.path.join(tmp, rel)
        os.makedirs(os.path.dirname(p))
        write(p, words, data)
        a = os.path.join(tmp, 'a')
        os.makedirs(os.path.dirname(os.path.join(a, rel)))
        shutil.copy2(os.path.join(orig_tree, rel), os.path.join(a, rel))
        buf = io.StringIO()
        sys_argv = sys.argv
        sys.argv = ['same40.py', '--floats', '--only', rel, tmp, a]
        try:
            with redirect_stdout(buf):
                rc = same40.main()
        finally:
            sys.argv = sys_argv
        return rc, buf.getvalue()
    finally:
        shutil.rmtree(tmp)


def find_file(tree, want):
    for root, _, files in sorted(os.walk(os.path.join(tree, 'sys'))):
        for f in sorted(files):
            if f.endswith('.qfasl'):
                p = os.path.join(root, f)
                try:
                    d = Where(open(p, 'rb').read()).run()
                except Exception:
                    continue
                if want(d):
                    return os.path.relpath(p, tree), d
    raise SystemExit('plant_a: no QFASL in %s fits' % tree)


def main():
    tree = sys.argv[1]
    fails, out = 0, []

    def plant(name, rel, change, must):
        nonlocal fails
        words, data = words_of(os.path.join(tree, rel))
        what = change(words)
        rc, text = judge(tree, rel, words, data)
        got = 'DIFFER' if rc else ('FLOAT' if 'FLOAT ' in text else 'EQUAL')
        ok = got == must
        fails += 0 if ok else 1
        out.append('%-4s %-36s %s: %s; reported %s, must be %s'
                   % ('ok' if ok else 'FAIL', name, rel, what, got, must))

    # a FEF holding a float
    rel, d = find_file(tree, lambda d: any(any(isinstance(q, Float32) for q in f.qs)
                                           for f, _ in d.at_frames))
    fef, at = next((f, a) for f, a in d.at_frames if any(isinstance(q, Float32) for q in f.qs))

    def flip(w):
        w[at] ^= 1
        return 'halfword 0 of %s %o -> %o' % (fef.name, w[at] ^ 1, w[at])
    plant('instruction in a float\'s function', rel, flip, 'DIFFER')
    bits, fp = d.at_floats[0]

    def ulp(k):
        def f(w):
            w[fp + 1] = (w[fp + 1] + k) & 0xFFFF
            return 'float %08X -> %04X%04X' % (bits, w[fp], w[fp + 1])
        return f
    plant('float, one unit in the last place', rel, ulp(1), 'FLOAT')
    plant('float, two units', rel, ulp(2), 'DIFFER')

    # the compile time in the attribute list
    def ctime(w):
        pl = d.plist
        data_ = [pl[i + 1] for i in range(0, len(pl) - 1, 2)
                 if str(pl[i]).upper().endswith(('FASD-DATA', 'COMPILE-DATA'))][0]
        t = data_[2]
        for i in range(len(w) - 1):
            if (w[i] << 16 | w[i + 1]) == t:
                w[i + 1] ^= 1
                return 'compile time %d changed by one' % t
        raise SystemExit('plant_a: compile time not found')
    plant('compile time', rel, ctime, 'EQUAL')

    # a generated symbol
    import re
    gen = re.compile(r'^(#:[A-Za-z*%-]*?|G)\d+$')
    rel, d = find_file(tree, lambda d: any(gen.match(s) and s.startswith('G') for s, _, _ in d.at_symbols))
    s, p, n = next(x for x in d.at_symbols if gen.match(x[0]) and x[0].startswith('G'))

    def renumber(w):
        # the last character pair: its low byte is a digit
        lo = w[p + n - 1] & 0o377
        hi = w[p + n - 1] >> 8
        last = hi if hi != 0o200 else lo
        new = ord('1') if last != ord('1') else ord('2')
        w[p + n - 1] = (new << 8 | lo) if hi != 0o200 else (hi << 8 | new)
        return 'symbol %s, its last digit changed' % s
    plant('generated symbol\'s number', rel, renumber, 'EQUAL')

    def plain(w):
        w[p] = (w[p] & 0o177400) | ord('H')
        return 'symbol %s made H%s' % (s, s[1:])
    plant('generated symbol made a plain one', rel, plain, 'DIFFER')

    # EXPR-SXHASH
    def has_sx(d):
        return any(isinstance(q, list) and any(isinstance(e, list) and e[:1] and str(e[0]).endswith('EXPR-SXHASH')
                                               for e in q) for f, _ in d.at_frames for q in f.qs)
    rel, d = find_file(tree, has_sx)
    sx, sxfef = None, None
    for f, _ in d.at_frames:
        for q in f.qs:
            if isinstance(q, list):
                for e in q:
                    if isinstance(e, list) and e[:1] and str(e[0]).endswith('EXPR-SXHASH'):
                        sx, sxfef = e[1], f
    loc = next((p_, n_) for v, p_, n_ in d.at_fixed if v == sx)

    def rehash(w):
        w[loc[0] + loc[1] - 1] ^= 1
        return 'EXPR-SXHASH %d changed' % sx
    plant('EXPR-SXHASH value', rel, rehash, 'EQUAL')
    # a fixnum constant of the same FEF, as the decoder read it
    consts = [q for q in sxfef.qs[1:] if isinstance(q, int) and not isinstance(q, bool) and q > 1 and q != sx]
    other = next((v, p_, n_) for v, p_, n_ in d.at_fixed if v in consts)

    def refix(w):
        w[other[1] + other[2] - 1] ^= 1
        return 'fixnum %d changed' % other[0]
    plant('a fixnum beside it', rel, refix, 'DIFFER')

    # a GENTEMP name in a local map
    lm = re.compile(r'^PKT\d+$')
    rel, d = find_file(tree, lambda d: any(lm.match(x) for x, _, _ in d.at_symbols))
    s2, p2, n2 = next(x for x in d.at_symbols if lm.match(x[0]))

    def renum2(w):
        lo, hi = w[p2 + n2 - 1] & 0o377, w[p2 + n2 - 1] >> 8
        if hi != 0o200:
            w[p2 + n2 - 1] = ((ord('1') if hi != ord('1') else ord('2')) << 8) | lo
        else:
            w[p2 + n2 - 1] = (hi << 8) | (ord('1') if lo != ord('1') else ord('2'))
        return 'local-map name %s, its number changed' % s2
    plant('GENTEMP name in a local map', rel, renum2, 'EQUAL')

    def rename2(w):
        w[p2] = (w[p2] & 0o177400) | ord('Q')
        return 'local-map name %s made Q%s' % (s2, s2[1:])
    plant('local-map name made another', rel, rename2, 'DIFFER')

    # a definition's hash in the file's record of the macros it expanded
    def mx_of(d):
        for e in d.events:
            t = same40.render(list(e), None)
            if 'FASL-RECORD-FILE-MACROS-EXPANDED' in t:
                for name, h in re.findall(r'\(([^\s()]+) (\d{6,})\)', t):
                    if any(v == int(h) for v, _, _ in d.at_fixed):
                        return name, int(h)
        return None
    rel, d = find_file(tree, lambda d: mx_of(d) is not None)
    mname, mhash = mx_of(d)
    mloc = next((p_, n_) for v, p_, n_ in d.at_fixed if v == mhash)

    def remx(w):
        w[mloc[0] + mloc[1] - 1] ^= 1
        return 'the hash %d of %s in the macros-expanded record changed' % (mhash, mname)
    plant('a macro\'s hash in the record', rel, remx, 'EQUAL')

    # the plant the review of check (b) measured: an instruction of hash's
    # HASH-TABLE-MAXIMAL-FULLNESS, which holds a float
    rel = 'sys/sys2/hash.qfasl'
    if os.path.exists(os.path.join(tree, rel)):
        d = Where(open(os.path.join(tree, rel), 'rb').read()).run()
        hf = [(f, a) for f, a in d.at_frames if str(f.name).endswith('HASH-TABLE-MAXIMAL-FULLNESS')]
        if hf and len(hf[0][0].halfwords) > 2:
            f2, a2 = hf[0]

            def flip2(w):
                w[a2 + 2] ^= 1
                return 'halfword 2 of %s %o -> %o' % (f2.name, w[a2 + 2] ^ 1, w[a2 + 2])
            plant('instruction in HASH-TABLE-MAXIMAL-FULLNESS', rel, flip2, 'DIFFER')
    print('\n'.join(out))
    print('RESULT %s (%d failures)' % ('PASS' if not fails else 'FAIL', fails))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
