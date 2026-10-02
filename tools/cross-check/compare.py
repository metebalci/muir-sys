#!/usr/bin/env python3
"""The cross build's QFASLs against a native build's, function by function
(a preview of contract G2 section 7's check (a)): every FEF that differs must
be explained.

Usage: compare.py [--prefix P] CROSS-TREE NATIVE-TREE LOG-DIR...
CROSS-TREE and NATIVE-TREE each hold sys/ with sources and QFASLs (the cross
build's served copy, and System 2000's release tree).  The LOG-DIRs hold the
cross compile's logs, P*cross-NNNN.txt and P*cross-table.txt (check2.py).

A FEF that differs is explained as a whole function, not word by word, when
the function shows one of these (this compares with System 2000's 32-bit
QFASLs; G2 section 7's check (a), against a native build of the 40-bit
machine, is same40.py, word by word):
  constant       the log shows a changing constant read or folded in its function
  float          it holds a float (IEEE single against this world's formats)
  lsh or rot     the log shows an LSH or ROT left to the target in its function
  closure slots  a list of slot numbers marked by the fixnum sign bit, bit 31
                 against bit 24 (sys/sys/qcp1.lisp, boxed-sign-bit-mark)
  generated names  the words differ only in the numbers of generated symbols
  #.             the word holds, as a token, the value a #. of a changing
                 constant gave
Files whose source differs between the trees are listed apart.  Exits 1 when a
file with the same source has a difference not explained.
"""
import collections
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qfasl  # noqa: E402
from qfasl import Float32  # noqa: E402

GENSYM = re.compile(r'\bG\d{3,5}\b')
FLOAT_KINDS = ('SMALL-FLOAT-BITS', 'FLONUM-NIBBLES', 'NEW-FLOAT')


def norm(x):
    if isinstance(x, Float32) or (isinstance(x, tuple) and x and x[0] in FLOAT_KINDS):
        return 'FLOAT'
    s = qfasl.show(x)
    s = GENSYM.sub('G#', s)
    return re.sub(r"\(:EXPR-SXHASH \d+\)", '(:EXPR-SXHASH #)', s)


def has_float(x):
    if isinstance(x, Float32):
        return True
    if isinstance(x, tuple) and x and x[0] in FLOAT_KINDS:
        return True
    if isinstance(x, list):
        return any(has_float(e) for e in x)
    if isinstance(x, tuple):
        return any(has_float(e) for e in x[1:])
    return False


def short(name):
    """A function spec without package prefixes: SI::FOO -> FOO, and
    (:INTERNAL TV::BAR 2) -> (INTERNAL BAR 2)."""
    return re.sub(r'[A-Za-z0-9*%-]*::?', '', str(name))


def main():
    args = sys.argv[1:]
    prefix = 'x'
    if args[:1] == ['--prefix']:
        prefix, args = args[1], args[2:]
    cross, native, logs = args[0], args[1], args[2:]
    table = sorted(glob.glob(os.path.join(logs[0], prefix + '*cross-table.txt')))[0]
    changed = set()
    for line in open(table, encoding='latin-1'):
        f = line.rstrip('\n').split('\t')
        if f[0] == 'T' and f[2] != f[3]:
            changed.add(f[1])
    touched = collections.defaultdict(set)
    sharp_values = {}
    declined = set()
    for d in logs:
        for p in glob.glob(os.path.join(d, prefix + '*cross-[0-9]*.txt')):
            for line in open(p, encoding='latin-1'):
                f = line.rstrip('\n').split('\t')
                if f[0] == 'R' and f[2] in changed:
                    touched[short(f[5])].add(f[2])
                elif f[0] in ('X', 'S'):
                    form = f[2] if f[0] == 'X' else f[1]
                    hit = set(re.findall(r'[^\s()]+', form)) & changed
                    if hit and f[0] == 'X':
                        touched[short(f[1])] |= hit
                    elif hit:
                        sharp_values[f[2]] = hit
                elif f[0] == 'L':
                    declined.add(short(f[1]))
    out, counts = [], collections.Counter()
    unexplained = []
    for p in sorted(glob.glob(os.path.join(cross, 'sys', '**', '*.qfasl'), recursive=True)):
        rel = os.path.relpath(p, cross)
        q = os.path.join(native, rel)
        if not os.path.exists(q):
            counts['no native file'] += 1
            continue
        src_c = os.path.join(cross, rel[:-6] + '.lisp')
        src_n = os.path.join(native, rel[:-6] + '.lisp')
        src_same = (os.path.exists(src_c) and os.path.exists(src_n) and
                    open(src_c, 'rb').read() == open(src_n, 'rb').read())
        try:
            dc, dn = qfasl.decode(p), qfasl.decode(q)
        except Exception as e:
            out.append('  cannot decode %s: %s' % (rel, e))
            counts['decode error'] += 1
            continue
        fc = collections.defaultdict(list)
        fn = collections.defaultdict(list)
        for f in dc.fefs:
            fc[norm(f.name)].append(f)
        for f in dn.fefs:
            fn[norm(f.name)].append(f)
        file_diff = []
        for name in sorted(set(fc) | set(fn)):
            a, b = fc.get(name, []), fn.get(name, [])
            if len(a) != len(b):
                file_diff.append((name, 'count %d/%d' % (len(a), len(b)), False))
                continue
            for x, y in zip(a, b):
                if [norm(v) for v in x.qs[1:]] == [norm(v) for v in y.qs[1:]] and \
                   x.halfwords == y.halfwords:
                    continue
                why = []
                key = short(name)
                if key in touched:
                    why.append('constant ' + ' '.join(sorted(s.split(':')[-1] for s in touched[key])))
                if any(has_float(v) for v in x.qs):
                    why.append('float')
                if key in declined:
                    why.append('lsh or rot left to the target')
                for u, v in zip(x.qs[1:], y.qs[1:]):
                    if norm(u) == norm(v):
                        continue
                    if (isinstance(u, list) and isinstance(v, list) and len(u) == len(v) and u and
                            all(isinstance(m, int) and isinstance(n, int) and
                                m - n in (0, 2**24 - 2**31) for m, n in zip(u, v))):
                        why.append('closure slots')
                        continue
                    if re.sub(r'([A-Z])\d+\b', r'\1#', norm(u)) == \
                       re.sub(r'([A-Z])\d+\b', r'\1#', norm(v)):
                        why.append('generated names')
                        continue
                    s = qfasl.show(u)
                    for val, hit in sharp_values.items():
                        if val and re.search(r'(?<![\w.-])%s(?![\w.-])' % re.escape(val), s):
                            why.append('#. ' + ' '.join(sorted(n.split(':')[-1] for n in hit)))
                            break
                file_diff.append((name, ', '.join(why) or '?', bool(why)))
        if not file_diff:
            counts['same'] += 1
            continue
        if not src_same:
            counts['source differs'] += 1
            out.append('  source differs: %s (%d fefs differ)' % (rel, len(file_diff)))
            continue
        bad = [d for d in file_diff if not d[2]]
        counts['explained' if not bad else 'unexplained'] += 1
        out.append('  %s %s: %d fefs differ, %d unexplained'
                   % ('EXPL' if not bad else 'UNEX', rel, len(file_diff), len(bad)))
        for name, why, ok in file_diff:
            out.append('      %s %s: %s' % ('ok ' if ok else '???', name, why))
        if bad:
            unexplained.append(rel)
    print('files: %s' % dict(counts))
    print('\n'.join(out))
    print('RESULT %s (%d files with unexplained differences: %s)'
          % ('PASS' if not unexplained else 'FAIL', len(unexplained), unexplained))
    return 1 if unexplained else 0


if __name__ == '__main__':
    sys.exit(main())
