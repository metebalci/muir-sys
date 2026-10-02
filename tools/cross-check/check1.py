#!/usr/bin/env python3
"""The cross build's check 1: for every family of system constants at every
point where the compiler evaluates, the test file (lisp/family.lisp) compiled
by the cross compiler carries the target's values in its decoded QFASL, and not
this world's; and the controls (cases/check1.cases).

Usage: check1.py HOME-DIR
HOME-DIR holds what check1.cases left in HOST's home: native-family.qfasl,
id-family.qfasl, synth-family.qfasl, t40-family.qfasl, t40-planted.qfasl,
t40-defs.qfasl and
the tables synth-cross-table.txt and t40-cross-table.txt
(cold:cross-write-table).  Prints one table per target and exits 1 on a
failure.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qfasl  # noqa: E402
from qfasl import Float32  # noqa: E402

FAMILIES = [('qfield', '%%Q-POINTER'), ('dtp', 'DTP-LOCATIVE'), ('cdr', 'CDR-NEXT'),
            ('page', 'PAGE-SIZE'), ('fixnum', 'MOST-POSITIVE-FIXNUM'),
            ('array', '%%ARRAY-TYPE-FIELD'), ('artq', 'ART-Q'), ('char', '%%CH-FONT'),
            ('float', 'SINGLE-FLOAT-EXPONENT-OFFSET'), ('fef', '%FEFHI-FCTN-NAME'),
            ('header', '%HEADER-TYPE-ARRAY-LEADER'), ('disk', '%DISK-RQ-CCW-LIST'),
            ('vaddr', 'A-MEMORY-VIRTUAL-ADDRESS')]
POINTS = ['fold', 'sharp', 'mac', 'ct', 'cl']
FUNCTION = {'fold': 'XC-FOLD-%s', 'sharp': 'XC-SHARP-%s', 'mac': 'XC-USE-MAC-%s',
            'ct': 'XC-CT-%s', 'cl': 'XC-CL-%s'}


def parse_value(s):
    s = s.strip()
    try:
        return int(s)
    except ValueError:
        return s


def load_table(path):
    """name -> [(printed symbol, target value or None, this world's value)]"""
    t = {}
    for line in open(path, encoding='latin-1'):
        f = line.rstrip('\n').split('\t')
        if f[0] == 'T':
            t.setdefault(f[1].split(':')[-1], []).append((f[1], parse_value(f[2]), parse_value(f[3])))
        elif f[0] == 'U':
            t.setdefault(f[1].split(':')[-1], []).append((f[1], None, parse_value(f[2])))
    return t


def fefs(path):
    d = qfasl.decode(path)
    return d, {str(f.name): f for f in d.fefs}


def consts(fef):
    """A FEF's boxed words after its fixed header: its constants."""
    return fef.qs[len(qfasl.FEFHI) - 1:]


def list_with(fef, tag, fam, value):
    return any(isinstance(c, list) and len(c) == 3 and [str(c[0]), str(c[1])] ==
               [tag.upper(), fam.upper()] and c[2] == value for c in consts(fef))


def check_family_file(label, path, table, out):
    d, fs = fefs(path)
    fails = 0
    out.append('== %s: %s (word-width %s)' % (label, os.path.basename(path), d.width))
    out.append('%-8s %-30s %14s %14s  %s' % ('family', 'constant', 'target', 'here',
                                             ' '.join('%-6s' % p for p in POINTS)))
    for fam, name in FAMILIES:
        rows = table.get(name)
        if not rows or len(rows) != 1:
            out.append('%-8s %-30s  table has %s' % (fam, name, rows))
            fails += 1
            continue
        sym, target, here = rows[0]
        res = []
        for p in POINTS:
            fef = fs.get(FUNCTION[p] % fam.upper())
            if fef is None:
                res.append('nofef')
                fails += 1
                continue
            if p == 'fold':
                if name == 'MOST-POSITIVE-FIXNUM':
                    # not a system constant: no fold, a read of its value cell
                    ok = (not any(isinstance(c, int) and c in (here << 20, target << 20)
                                  for c in consts(fef))
                          and any(str(c).endswith('MOST-POSITIVE-FIXNUM') for c in consts(fef)))
                    res.append('cell' if ok else 'FAIL')
                else:
                    has_t = any(isinstance(c, int) and c == target << 20 for c in consts(fef))
                    has_h = here != target and any(isinstance(c, int) and c == here << 20
                                                   for c in consts(fef))
                    ok = has_t and not has_h
                    res.append(('ok' if here != target else 'same') if ok else 'FAIL')
            else:
                tag = {'sharp': 'SHARP', 'mac': 'MAC', 'ct': 'CT', 'cl': 'CL'}[p]
                ok = list_with(fef, tag, fam, target) and not (
                    here != target and list_with(fef, tag, fam, here))
                res.append(('ok' if here != target else 'same') if ok else 'FAIL')
            if res[-1] == 'FAIL':
                fails += 1
        out.append('%-8s %-30s %14s %14s  %s' % (fam, name, target, here,
                                                 ' '.join('%-6s' % r for r in res)))
    return d, fs, fails


def main():
    home = sys.argv[1]
    out = []
    fails = 0

    def j(name):
        return os.path.join(home, name)

    # the identity control: the cross compiler with this world's parameters
    # against the native compile; only XC-LSH differs, since a cross build
    # folds no LSH
    nat_d, nat = fefs(j('native-family.qfasl'))
    id_d, idf = fefs(j('id-family.qfasl'))
    differ = [n for n in nat if not (n in idf and [qfasl.show(x) for x in nat[n].qs[1:]] ==
                                     [qfasl.show(x) for x in idf[n].qs[1:]] and
                                     nat[n].halfwords == idf[n].halfwords)]
    # a cross build folds lsh with the target's fixnum (compiler:target-lsh),
    # here this world's, so every fef is the native compile's
    out.append('identity: %d of %d fefs identical (boxed words after the header, instructions);'
               ' differ: %s' % (len(nat) - len(differ), len(nat), differ))
    if differ:
        fails += 1

    for label, fam_file, tab in (('synthetic target', 'synth-family.qfasl', 'synth-cross-table.txt'),
                                 ('40-bit target', 't40-family.qfasl', 't40-cross-table.txt')):
        d, fs, f = check_family_file(label, j(fam_file), load_table(j(tab)), out)
        fails += f
        out.append('  mark: word-width %s (want 40)' % d.width)
        if d.width != 40:
            fails += 1

    # the compiler's own encodings, in the 40-bit file against the native one
    d40, f40 = fefs(j('t40-family.qfasl'))
    out.append("== the compiler's encodings (40-bit file, native file)")
    c40 = [c for c in consts(f40['XC-CLOSURE']) if isinstance(c, list) and c and
           all(isinstance(x, int) for x in c)]
    cn = [c for c in consts(nat['XC-CLOSURE']) if isinstance(c, list) and c and
          all(isinstance(x, int) for x in c)]
    ok = bool(c40 and cn and all(-2**31 <= x < -2**31 + 1000 for x in c40[0])
              and all(-2**24 <= x < -2**24 + 1000 for x in cn[0]))
    out.append('  closure slots: 40-bit %s, native %s  %s' % (c40, cn, 'ok' if ok else 'FAIL'))
    fails += 0 if ok else 1
    fl = [c for c in consts(f40['XC-FLOATS']) if isinstance(c, list)]
    got = fl[0] if fl else []
    bits = ['%08X' % x.bits if isinstance(x, Float32) else repr(x) for x in got]
    exp = ['3FC00000', 'C0200000', '3DCCCCCD', '40490FDB', '3FC00000', '3DCCCCCD', '60AD78EC']
    ok = len(bits) == 7 and all(e is None or e == b for e, b in zip(exp, bits))
    out.append('  floats (binary32): %s  %s' % (bits, 'ok' if ok else 'FAIL'))
    fails += 0 if ok else 1
    big = [c for c in consts(f40['XC-BIG']) if isinstance(c, list)]
    ok = bool(big) and big[0] == [2147483647, -2147483648, 16777216, 2147483648]
    out.append('  integers: %s  %s' % (big and big[0], 'ok' if ok else 'FAIL'))
    fails += 0 if ok else 1
    ch = [c for c in consts(f40['XC-CHAR']) if isinstance(c, list)]
    ok = bool(ch) and ch[0] == [('CHAR', 97), ('CHAR', 0o100000040)]
    out.append('  characters: %s  %s' % (ch and ch[0], 'ok' if ok else 'FAIL'))
    fails += 0 if ok else 1
    lsh40 = consts(f40['XC-LSH'])
    ok = any(isinstance(c, int) and c == 1 << 30 for c in lsh40)
    out.append('  lsh 1 30 folded with the target\'s fixnum: 40-bit constants %s; native %s  %s'
               % ([qfasl.show(c) for c in lsh40], [qfasl.show(c) for c in consts(nat['XC-LSH'])],
                  'ok' if ok else 'FAIL'))
    fails += 0 if ok else 1
    ash = [c for c in consts(f40['XC-ASH']) if isinstance(c, int)]
    ok = 2048576 in ash
    out.append('  ash 1 20 folded: %s  %s' % (ash, 'ok' if ok else 'FAIL'))
    fails += 0 if ok else 1
    out.append('  marks: native %s, identity %s (a 32-bit file carries none)' % (nat_d.width, id_d.width))
    if nat_d.width != 32 or id_d.width != 32:
        fails += 1

    # the planted fold
    dp, fp = fefs(j('t40-planted.qfasl'))
    pf = [c for c in consts(fp['XC-PLANTED-FOLD']) if isinstance(c, int)]
    ps = [c for c in consts(fp['XC-PLANTED-SHARP']) if isinstance(c, list)]
    ok = 1024 * 1024 in pf and 256 * 1024 not in pf and bool(ps) and ps[0][1] == 32
    out.append('  planted: fold %s (want %d), #. %s (want 32)  %s'
               % (pf, 1024 * 1024, [qfasl.show(p) for p in ps], 'ok' if ok else 'FAIL'))
    fails += 0 if ok else 1

    # the tree's compile-time definitions, given to every compile for the
    # target by cross-begin (SYS: COLD; CROSSDEFS): NUMDEF's defsubst, and
    # PRODEF's macro, whose byte the compiler folds under the hook
    # (lisp/defs.lisp)
    dd, fd = fefs(j('t40-defs.qfasl'))
    se = [c for c in consts(fd['XC-SHORT-EXPONENT']) if isinstance(c, int)]
    ok = 0o2710 in se and 0o2110 not in se
    out.append('  %%short-float-exponent: constants %s (want %d, the tree\'s (byte 8 23.); not %d)  %s'
               % (se, 0o2710, 0o2110, 'ok' if ok else 'FAIL'))
    fails += 0 if ok else 1
    hw = fd['XC-METER'].halfwords
    ok = 0o76037 in hw and 0o76030 not in hw
    out.append('  fixnum-read-meter-for-scheduler: byte %s (want push of #o37, 76037; not #o30, 76030)  %s'
               % ([oct(h) for h in hw if h & ~0o777 == 0o76000], 'ok' if ok else 'FAIL'))
    fails += 0 if ok else 1

    # what the compiler decides by the target's values, not this world's
    tc = fd['XC-TABLE-CONSTANT']
    syms = [qfasl.show(c) for c in consts(tc) if not isinstance(c, (int, float, list))]
    ok = (16 in consts(tc) or 0o76020 in tc.halfwords) and not any('DISK-BLOCKS-PER-PAGE' in x for x in syms)
    out.append('  disk-blocks-per-page folded: constants %s, halfwords %s  %s'
               % ([qfasl.show(c) for c in consts(tc)], [oct(h) for h in tc.halfwords], 'ok' if ok else 'FAIL'))
    fails += 0 if ok else 1
    rc = [c for c in consts(fd['XC-ROT']) if isinstance(c, int)]
    ok = -2**31 in rc
    out.append('  rot 1 31 folded with the target\'s fixnum: %s (want %d)  %s' % (rc, -2**31, 'ok' if ok else 'FAIL'))
    fails += 0 if ok else 1
    # a misc instruction: opcode 15 in bits 12-9, the misc number in bits 8-0
    misc = [h & 0o777 for h in fd['XC-FLOAT-PROTO'].halfwords if (h >> 9) & 0o17 == 0o15]
    ok = 0o651 in misc and 0o307 not in misc
    out.append('  (float x 0f0): misc %s (want SMALL-FLOAT 651, not INTERNAL-FLOAT 307)  %s'
               % ([oct(m) for m in misc], 'ok' if ok else 'FAIL'))
    fails += 0 if ok else 1
    sf = [c for c in consts(fd['XC-SMALL-FLOAT']) if isinstance(c, Float32)]
    ok = bool(sf) and sf[0].bits == 0x3EAAAAAB
    out.append('  small-float folded: %s (want 3EAAAAAB)  %s'
               % (['%08X' % c.bits for c in sf], 'ok' if ok else 'FAIL'))
    fails += 0 if ok else 1

    sl = [c for c in consts(fd['XC-SHORT-LITERAL']) if isinstance(c, list)]
    bits = ['%08X' % x.bits for x in sl[0] if isinstance(x, Float32)] if sl else []
    ok = bits == ['3FA66666', '3F333333']
    out.append('  short-float literals: %s (want 3FA66666 3F333333)  %s' % (bits, 'ok' if ok else 'FAIL'))
    fails += 0 if ok else 1
    d2, f2 = fefs(j('t40-defs2.qfasl'))
    sq = [c for c in consts(f2['XC-SQRT']) if isinstance(c, Float32)]
    ok = bool(sq) and abs(sq[0].bits - 0x3FB504F3) <= 1
    out.append('  (sqrt 2) folded after NUMDEF met: %s (want 3FB504F3)  %s'
               % (['%08X' % c.bits for c in sq], 'ok' if ok else 'FAIL'))
    fails += 0 if ok else 1

    fl = [c for c in consts(fd['XC-FULLNESS']) if isinstance(c, Float32)]
    ok = ['%08X' % c.bits for c in fl] == ['3F333333']
    out.append('  a listed defsubst\'s float (hash-table-maximal-fullness): %s (want 3F333333)  %s'
               % (['%08X' % c.bits for c in fl], 'ok' if ok else 'FAIL'))
    fails += 0 if ok else 1
    dd = [c for c in consts(fd['XC-DEDUP']) if isinstance(c, Float32)]
    ok = len(dd) == 1 and dd[0].bits == 0x3FB8AA3B
    out.append('  two literals of one target float: constants %s (want one, 3FB8AA3B)  %s'
               % (['%08X' % c.bits for c in dd], 'ok' if ok else 'FAIL'))
    fails += 0 if ok else 1

    ll = [c for c in consts(fd['XC-LONG-LITERAL']) if isinstance(c, list)]
    bits = ['%08X' % x.bits for x in ll[0] if isinstance(x, Float32)] if ll else []
    ok = bits == ['3F800001']
    out.append('  a long literal read exactly: %s (want 3F800001)  %s' % (bits, 'ok' if ok else 'FAIL'))
    fails += 0 if ok else 1
    pc = [c for c in consts(fd['XC-PI2']) if isinstance(c, Float32)]
    ok = ['%08X' % c.bits for c in pc] == ['3FC90FDB']
    out.append('  1.570796326 and 1.5707963185: constants %s (want one, 3FC90FDB)  %s'
               % (['%08X' % c.bits for c in pc], 'ok' if ok else 'FAIL'))
    fails += 0 if ok else 1

    out.append('RESULT %s (%d failures)' % ('PASS' if fails == 0 else 'FAIL', fails))
    print('\n'.join(out))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
