#!/usr/bin/env python3
"""The cross build's check 2: the log of a cross compile shows no value of this
world's for a constant that changes.

Usage: check2.py [--prefix P] LOG-DIR...
The LOG-DIRs hold the per-file logs P*cross-NNNN.txt that cold:cross-write-log
writes, and the first holds the table P*cross-table.txt (cold:cross-write-table).
The prefix is the log directory's (x for check 2, c for check 3's compile).

Records, tab-separated, printed in base 10 with package prefixes:
  F file            E file status
  R context symbol target-value this-world's-value function
  X function form value           (a fold)
  S form value                    (a #.)
  M context symbol function       (a watched symbol with no target value)
  L function form                 (an LSH or ROT of constants left to the target)
For every fold and #. whose form names a constant that changes (one whose
target value differs from this world's), the form is evaluated here with the
target's values and with this world's, and the logged value must be the
target's; forms of functions this evaluator does not know are listed as not
evaluated.  Every R record is checked against the table.  Files served from
SYS: CROSS-CHECK; are the controls, reported apart.  Exits 1 on a failure.
"""
import collections
import glob
import os
import re
import sys

CONTROLS = '//cross-check//'


class Sym(str):
    @property
    def name(self):
        return self.split(':')[-1].strip('|')


def tokens(s):
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if c.isspace():
            i += 1
        elif c in '()':
            yield c
            i += 1
        elif c == "'":
            yield "'"
            i += 1
        elif c == '"':
            j = i + 1
            while j < n and s[j] != '"':
                j += 2 if s[j] == '/' else 1
            yield ('STR', s[i + 1:j])
            i = j + 1
        elif s.startswith('#<', i):
            depth, j = 0, i
            while j < n:
                if s.startswith('#<', j):
                    depth += 1
                    j += 2
                    continue
                if s[j] == '>':
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            yield ('OPAQUE', s[i:j + 1])
            i = j + 1
        else:
            j = i
            while j < n and not s[j].isspace() and s[j] not in '()"':
                if s[j] == '/':
                    j += 2
                    continue
                if s[j] == '|':
                    k = s.find('|', j + 1)
                    j = (k + 1) if k >= 0 else n
                    continue
                j += 1
            yield ('ATOM', s[i:j])
            i = j


INT = re.compile(r'^[+-]?[0-9]+\.?$')
FLOAT = re.compile(r'^[+-]?[0-9]*\.[0-9]+([eEsSfF][+-]?[0-9]+)?$|^[+-]?[0-9]+[eEsS][+-]?[0-9]+$')


def atom(t):
    if INT.match(t):
        return int(t.rstrip('.'))
    if FLOAT.match(t):
        try:
            return float(re.sub('[sSfF]', 'e', t))
        except ValueError:
            pass
    return Sym(t)


def read(s):
    toks = list(tokens(s))
    pos = [0]

    def one():
        t = toks[pos[0]]
        pos[0] += 1
        if t == '(':
            out = []
            while toks[pos[0]] != ')':
                if toks[pos[0]] == ('ATOM', '.'):
                    pos[0] += 1
                    out = ('DOTTED', out, one())
                    continue
                out.append(one())
            pos[0] += 1
            return out
        if t == "'":
            return [Sym('GLOBAL:QUOTE'), one()]
        if isinstance(t, tuple) and t[0] == 'ATOM':
            return atom(t[1])
        return t
    return one()


class NoEval(Exception):
    pass


def ldb(spec, x):
    pos, size = spec >> 6, spec & 0o77
    return (x >> pos) & ((1 << size) - 1)


def dpb(v, spec, x):
    pos, size = spec >> 6, spec & 0o77
    m = ((1 << size) - 1) << pos
    return (x & ~m) | ((v << pos) & m)


def _prod(a):
    r = 1
    for x in a:
        r *= x
    return r


def _fold(a, f, z):
    r = z
    for x in a:
        r = f(r, x)
    return r


FUNS = {
    '+': lambda *a: sum(a), '-': lambda a, *b: -a if not b else a - sum(b),
    '*': lambda *a: _prod(a), '1+': lambda a: a + 1, '1-': lambda a: a - 1,
    'MINUS': lambda a: -a, 'ASH': lambda a, n: a << n if n >= 0 else a >> -n,
    'LDB': ldb, 'DPB': dpb, 'LOGAND': lambda *a: _fold(a, lambda x, y: x & y, -1),
    'LOGIOR': lambda *a: _fold(a, lambda x, y: x | y, 0),
    'LOGXOR': lambda *a: _fold(a, lambda x, y: x ^ y, 0), 'LOGNOT': lambda a: ~a,
    'BYTE': lambda s, p: (p << 6) | s, 'MAX': max, 'MIN': min, 'ABS': abs,
    'TRUNCATE': lambda a, b=1: int(a / b), 'FLOOR': lambda a, b: a // b,
    '=': lambda a, b: a == b, 'EQ': lambda a, b: a == b, 'EQL': lambda a, b: a == b,
    '>': lambda a, b: a > b, '<': lambda a, b: a < b, 'NOT': lambda a: not a,
    'ZEROP': lambda a: a == 0, 'PLUSP': lambda a: a > 0, 'MINUSP': lambda a: a < 0,
    'LENGTH': lambda a: len(a),
}


def ev(form, values):
    if isinstance(form, bool) or isinstance(form, (int, float)):
        return form
    if isinstance(form, Sym):
        if form.name == 'T':
            return True
        if form.name == 'NIL':
            return False
        if form in values:
            return values[form]
        raise NoEval('symbol %s' % form)
    if isinstance(form, list) and form:
        head = form[0]
        if isinstance(head, Sym) and head.name == 'QUOTE':
            return form[1]
        if isinstance(head, Sym) and head.name in FUNS:
            return FUNS[head.name](*[ev(a, values) for a in form[1:]])
        raise NoEval('function %s' % head)
    raise NoEval('form %r' % (form,))


def names(form, acc):
    if isinstance(form, Sym):
        acc.add(form)
    elif isinstance(form, list):
        for x in form:
            names(x, acc)
    elif isinstance(form, tuple) and form and form[0] == 'DOTTED':
        names(form[1], acc)
        names(form[2], acc)
    return acc


def unquote(v):
    if isinstance(v, list) and len(v) == 2 and isinstance(v[0], Sym) and v[0].name == 'QUOTE':
        return v[1]
    # a fold with several values, (values 'a 'b ...): its first value
    if isinstance(v, list) and len(v) >= 2 and isinstance(v[0], Sym) and v[0].name == 'VALUES':
        return unquote(v[1])
    return v


def truthy(v):
    return not (v is False or v == Sym('GLOBAL:NIL') or v == [])


def same(a, b):
    if isinstance(a, bool) or isinstance(b, bool):
        return truthy(a) == truthy(b)
    return a == b


def main():
    args = sys.argv[1:]
    prefix = 'x'
    if args[:1] == ['--prefix']:
        prefix, args = args[1], args[2:]
    dirs = args
    tables = sorted(glob.glob(os.path.join(dirs[0], prefix + '*cross-table.txt')))
    if not tables:
        raise SystemExit('no %s*cross-table.txt in %s' % (prefix, dirs[0]))
    target, here, unset = {}, {}, set()
    for line in open(tables[0], encoding='latin-1'):
        f = line.rstrip('\n').split('\t')
        if f[0] == 'T':
            target[Sym(f[1])] = unquote(read(f[2]))
            here[Sym(f[1])] = unquote(read(f[3]))
        elif f[0] == 'U':
            unset.add(Sym(f[1]))
    changed = {s for s in target if target[s] != here[s]}
    tv = {s: v for s, v in target.items() if isinstance(v, int)}
    hv = {s: v for s, v in here.items() if isinstance(v, int)}

    status = collections.Counter()
    reads = collections.Counter()
    bad_reads, folds, sharps, misses, declined = [], [], [], [], []
    seen = {}
    for d in dirs:
        for p in sorted(glob.glob(os.path.join(d, prefix + '*cross-[0-9]*.txt'))):
            cur = None
            for line in open(p, encoding='latin-1'):
                f = line.rstrip('\n').split('\t')
                k = f[0]
                if k == 'F':
                    cur = f[1]
                elif k == 'E':
                    seen[f[1]] = (f[2], p)
                elif k == 'R':
                    sym, val = Sym(f[2]), unquote(read(f[3]))
                    reads[(f[1], sym)] += 1
                    if sym in target and not same(val, target[sym]):
                        bad_reads.append((cur, f))
                elif k == 'X':
                    folds.append((cur, f[1], f[2], f[3]))
                elif k == 'S':
                    sharps.append((cur, f[1], f[2]))
                elif k == 'M':
                    misses.append((cur, f))
                elif k == 'L':
                    declined.append((cur, f[1], f[2]))

    # the controls, compiled from SYS: CROSS-CHECK; in the same session: the
    # planted fold must show the target's value, an uncovered #. must stop
    controls = {f: v for f, v in seen.items() if CONTROLS in f}
    control_lines = ['  control %s: %s' % (f, st) for f, (st, p) in sorted(controls.items())]
    for rec in folds + sharps:
        if CONTROLS in rec[0]:
            control_lines.append('  control record: %s' % '  '.join(rec[1:]))
    control_misses = [m for m in misses if CONTROLS in m[0]]
    misses = [m for m in misses if CONTROLS not in m[0]]
    folds = [r for r in folds if CONTROLS not in r[0]]
    sharps = [r for r in sharps if CONTROLS not in r[0]]
    seen = {f: v for f, v in seen.items() if CONTROLS not in f}
    for st, p in seen.values():
        status[st] += 1

    out = []
    out.append('table: %d symbols with a target value, %d changing, %d with none'
               % (len(target), len(changed), len(unset)))
    out.append('changing: ' + ' '.join(sorted(s.name for s in changed)))
    out.append('files compiled: %d; status %s' % (len(seen), dict(status)))
    out.append('misses (no target value): %d' % len(misses))
    for m in misses[:20]:
        out.append('  %s %s' % m)
    out.append('reads of watched symbols at interpreted points: %d records' % sum(reads.values()))
    ch = collections.Counter()
    for (ctx, sym), n in reads.items():
        if sym in changed:
            ch[(ctx, sym.name)] += n
    for (ctx, name), n in sorted(ch.items()):
        out.append("  changing %-12s %-28s %5d, each the target's value" % (ctx, name, n))
    out.append("reads whose value is not the table's: %d" % len(bad_reads))
    for r in bad_reads[:20]:
        out.append('  BAD %s %s' % r)
    out.append('LSH or ROT of constants left to the target (not folded): %d' % len(declined))
    for rec in declined:
        out.append('  %s  %s  %s' % rec)
    out.append('controls:')
    out.extend(control_lines)
    for m in control_misses:
        out.append('  control miss: %s %s' % (m[0], m[1][1:]))

    def check(kind, records, formpos, valpos):
        n_changed = n_ok = 0
        bad, unchecked, lsh = [], [], []
        for rec in records:
            form = read(rec[formpos])
            val = unquote(read(rec[valpos]))
            if isinstance(form, list) and form and isinstance(form[0], Sym) and \
               form[0].name in ('LSH', 'ROT'):
                lsh.append(rec)
            if not (names(form, set()) & changed):
                continue
            n_changed += 1
            try:
                t = ev(form, tv)
            except NoEval as e:
                unchecked.append((rec, str(e)))
                continue
            try:
                h = ev(form, hv)
            except NoEval:
                h = None
            if same(val, t):
                n_ok += 1
            else:
                bad.append((rec, t, h))
        out.append('%s: %d in all, %d naming a changing constant, %d evaluated here to the logged '
                   '(target) value, %d not, %d not evaluable here; %d of LSH or ROT'
                   % (kind, len(records), n_changed, n_ok, len(bad), len(unchecked), len(lsh)))
        for rec, t, h in bad[:20]:
            out.append('  BAD %s  target %r here %r' % ('  '.join(rec), t, h))
        for rec, why in unchecked[:40]:
            out.append('  not evaluated (%s): %s' % (why, '  '.join(rec)))
        for rec in lsh:
            out.append('  LSH/ROT fold: %s' % ('  '.join(rec)))
        return len(bad) + len(lsh)

    fails = len(misses) + len(bad_reads)
    fails += check('folds', folds, 2, 3)
    fails += check('#.', sharps, 1, 2)
    out.append('RESULT %s (%d failures)' % ('PASS' if fails == 0 else 'FAIL', fails))
    print('\n'.join(out))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
