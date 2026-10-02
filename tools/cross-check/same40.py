#!/usr/bin/env python3
"""Two builds' QFASLs of the 40-bit machine against each other (contract G2
section 7, checks (a) and (d)): the cross build's against the native rebuild's,
or two native rebuilds'.  Each QFASL of TREE-A's sys/ (and site/) is decoded
with its counterpart in TREE-B (qfasl.py) and compared after normalisation,
as docs/building.md's UNFASL listings were:

  - the attribute list, without the compile data (the time, the system
    version, the user and the machine, the site), which every compile changes,
    and in any order (two compiles of one source order it differently);
  - fasl table indexes, which the decoder resolves to the values they name;
  - generated symbols' numbers (G1234, #:PKT2, ...);
  - EXPR-SXHASH values, which hash the generated symbols;
  - in a FEF's local map (debugging information), names ending in a number,
    which GENTEMP makes from a counter of the session;
  - in the file's record of the macros its compile expanded
    (SI:FASL-RECORD-FILE-MACROS-EXPANDED), each definition's SXHASH, which
    depends on the compiling world's floats for a definition holding one.

Everything else must be equal, word by word: every FEF's boxed words (the
constants, the names, the argument description) and instruction halfwords,
every array, and every evaluation, value and function cell the file sets.
Floats are compared by their binary32 bits.  With --floats, a float may
differ from its counterpart by one unit in the last place, as G2 section 7
allows for the cross build's (its literals rounded twice, through the builder's
floats); every such float is listed, with its file, item and both values, and
every other word of its item must still be equal.

Usage: same40.py [--floats] [--sources] [--only DIR] TREE-A TREE-B
With --sources, a file that differs while its source (the .lisp beside it)
differs between the trees is reported as SOURCE and not counted as a failure.
Prints one line a file that differs, with its first differing item, a FLOAT
line for each float one unit apart (--floats), and a summary; exit 1 when a
file differs or is missing from TREE-B.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qfasl  # noqa: E402
from qfasl import Arr, Fef, Float32  # noqa: E402

GENERATED = re.compile(r'(#:[A-Za-z*%-]*?|\bG)\d+\b')
SXHASH = re.compile(r'\(:EXPR-SXHASH -?\d+\)')
DROP_KEYS = ('FASD-DATA', 'COMPILE-DATA')
GENTEMP = re.compile(r'(?<![\w*%:.-])([A-Z][A-Z*%-]*?)\d+(?![\w*%-])')


MACRO_HASH = re.compile(r'\(([^\s()]+) -?\d+\)')


def macros_expanded(text):
    """Inside the file's (SI:FASL-RECORD-FILE-MACROS-EXPANDED ...), which lists
    the macros and defsubsts the compile expanded, each with the SXHASH of its
    definition (for make-system to see a change), the hash written as #: the
    compiling world's SXHASH of a definition that holds a float depends on its
    floats.  The names are kept, and the code the expansions made is compared
    word by word."""
    out, i = [], 0
    key = 'FASL-RECORD-FILE-MACROS-EXPANDED '      # SI: or no prefix, by the file's package
    while True:
        j = text.find(key, i)
        if j < 0:
            out.append(text[i:])
            return ''.join(out)
        j = max(text.rfind('(', 0, j), i)
        depth, k = 0, j
        while k < len(text):
            if text[k] == '(':
                depth += 1
            elif text[k] == ')':
                depth -= 1
                if depth == 0:
                    break
            k += 1
        out.append(text[i:j])
        out.append(MACRO_HASH.sub(r'(\1 #)', text[j:k + 1]))
        i = k + 1


def local_maps(text):
    """Inside each (COMPILER:LOCAL-MAP ...), the debugging information that
    names a FEF's local slots, names ending in a number written as NAME#: a
    macro's GENTEMP names its variables by a counter of the session (CHAOS's
    CONVERT-TO-PKT, PKT32 in one build and PKT33 in the next)."""
    out, i = [], 0
    key = '(COMPILER:LOCAL-MAP '
    while True:
        j = text.find(key, i)
        if j < 0:
            out.append(text[i:])
            return ''.join(out)
        depth, k = 0, j
        while k < len(text):
            if text[k] == '(':
                depth += 1
            elif text[k] == ')':
                depth -= 1
                if depth == 0:
                    break
            k += 1
        out.append(text[i:j])
        out.append(GENTEMP.sub(r'\1#', text[j:k + 1]))
        i = k + 1


def render(x, floats):
    """A value as text, normalised.  With FLOATS a list, each float is written
    as F and its binary32 bits are appended to FLOATS, in order."""
    if isinstance(x, Float32):
        if floats is not None:
            floats.append(x.bits)
            return 'F'
        return '#x%08X' % x.bits
    if isinstance(x, Fef):
        return '#<FEF %s %s | %s>' % (
            render(x.name, floats),
            ' '.join(render(q, floats) for q in x.qs[1:]),
            ' '.join('%o' % h for h in x.halfwords))
    if isinstance(x, Arr):
        return '#<ARRAY %s %s %s %s | %s>' % (
            x.type, render(x.dims, floats), render(x.leader, floats),
            ' '.join(render(d, floats) for d in x.data),
            ' '.join('%o' % h for h in x.halfwords))
    if isinstance(x, list):
        return '(' + ' '.join(render(e, floats) for e in x) + ')'
    if isinstance(x, tuple):
        return '[' + ' '.join(render(e, floats) for e in x) + ']'
    s = qfasl.show(x)
    return SXHASH.sub('(:EXPR-SXHASH #)', GENERATED.sub(r'\1#', s))


def one_ulp(a, b):
    """True if binary32 bits A and B are one unit in the last place apart."""
    return (a >> 31) == (b >> 31) and abs((a & 0x7FFFFFFF) - (b & 0x7FFFFFFF)) == 1


def plist(d, floats):
    p = d.plist or []
    out = []
    for i in range(0, len(p) - 1, 2):
        if not any(str(p[i]).upper().endswith(k) for k in DROP_KEYS):
            fl = [] if floats else None
            out.append((render(p[i], fl) + ' ' + render(p[i + 1], fl), fl))
    return sorted(out, key=lambda t: t[0])


def items(path, floats):
    """The file's items, each (text, floats).  FLOATS true takes each item's
    floats apart: F in the text, their bits in the list (else None)."""
    d = qfasl.decode(path)
    out = plist(d, floats)
    for x in [list(e) for e in d.events] + list(d.fefs):
        fl = [] if floats else None
        out.append((render(x, fl), fl))
    return [(macros_expanded(local_maps(SXHASH.sub('(:EXPR-SXHASH #)', t))), fl) for t, fl in out]


def compare_floats(x, y):
    """Items X and Y (items(..., True)) equal but for floats one unit apart:
    (True, [(item, index, a, b)...]), else (False, None)."""
    if len(x) != len(y):
        return False, None
    near = []
    for k, ((tx, fx), (ty, fy)) in enumerate(zip(x, y)):
        if tx != ty or len(fx) != len(fy):
            return False, None
        for i, (a, b) in enumerate(zip(fx, fy)):
            if a == b:
                continue
            if not one_ulp(a, b):
                return False, None
            near.append((k, i, a, b))
    return True, near


def main():
    args = sys.argv[1:]
    floats = '--floats' in args
    sources = '--sources' in args
    args = [a for a in args if a not in ('--floats', '--sources')]
    only = None
    if args[:1] == ['--only']:
        only, args = args[1], args[2:]
    a, b = args
    counts = {'bytes': 0, 'normalised': 0, 'floats only': 0, 'source differs': 0, 'differ': 0, 'missing': 0}
    bad = []
    for top in ('sys', 'site'):
        for root, _, files in sorted(os.walk(os.path.join(a, top))):
            for f in sorted(files):
                if not f.endswith('.qfasl'):
                    continue
                p = os.path.join(root, f)
                rel = os.path.relpath(p, a)
                if only and not rel.startswith(only):
                    continue
                q = os.path.join(b, rel)
                if not os.path.exists(q):
                    counts['missing'] += 1
                    bad.append(rel)
                    print('MISSING %s' % rel)
                    continue
                if open(p, 'rb').read() == open(q, 'rb').read():
                    counts['bytes'] += 1
                    continue
                try:
                    x, y = items(p, False), items(q, False)
                except Exception as e:
                    counts['differ'] += 1
                    bad.append(rel)
                    print('UNDECODED %s: %s' % (rel, e))
                    continue
                if x == y:
                    counts['normalised'] += 1
                    continue
                if floats:
                    ok, near = compare_floats(items(p, True), items(q, True))
                    if ok:
                        counts['floats only'] += 1
                        for k, i, fa, fb in near:
                            print('FLOAT %s: item %d, float %d: %08X %08X, one unit in the last place'
                                  % (rel, k, i, fa, fb))
                        continue
                sa, sb = (os.path.join(t, rel[:-len('.qfasl')] + '.lisp') for t in (a, b))
                if sources and os.path.exists(sa) and os.path.exists(sb) and \
                        open(sa, 'rb').read() != open(sb, 'rb').read():
                    counts['source differs'] += 1
                    print('SOURCE %s: its source differs between the trees' % rel)
                    continue
                counts['differ'] += 1
                bad.append(rel)
                k = next((i for i, (u, v) in enumerate(zip(x, y)) if u != v), min(len(x), len(y)))
                u = x[k][0] if k < len(x) else '<none>'
                v = y[k][0] if k < len(y) else '<none>'
                print('DIFFER %s: item %d of %d/%d\n  A %s\n  B %s' % (rel, k, len(x), len(y), u[:400], v[:400]))
    print('files: %s' % counts)
    print('RESULT %s' % ('PASS' if not bad else 'FAIL (%d)' % len(bad)))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
