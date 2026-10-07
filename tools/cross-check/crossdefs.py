#!/usr/bin/env python3
"""The cross build's list of the tree's compile-time definitions, made from the
sources (tools/cross-check/README.md, "The tree's definitions").

A file compiled for the target by the cross build expands a macro or open-codes
a defsubst with the definition the builder has, which is the builder's own
system's (BASE) unless the tree's has been given to the compile.  This lists,
mechanically, every compile-time definition of the tree whose text is not
BASE's: new, changed, or gone (BASE has it and the tree does not).  Text is
compared as tokens, comments dropped, case folded outside strings.

It lists too the tree's special variables that BASE has not (*cross-specials*):
a DEFVAR, DEFPARAMETER, DEFCONST, DEFCONSTANT or DEFGLOBAL, or a top-level
SPECIAL, PROCLAIM or DECLARE of SPECIAL.  Each proclaims its variable special
when its own file compiles, and natively every later compile knows it from the
loaded file; the builder has not loaded the tree, so a compile for the target
of another file that binds the variable bound it lexically (hashfl.lisp's
:PUT-HASH and SXHASH-HASHED-YOUNG-ADDRESS, qrand.lisp's, found by the route's
check (a)).  A special BASE has and the tree has not is listed :gone, which
the cross build refuses, as it cannot unproclaim one without changing the
builder.

Usage:
  crossdefs.py TREE BASE [--lisp OUT]   list; --lisp writes the list as Lisp
                                        (cold:*cross-definitions*)
  crossdefs.py TREE BASE --check FILE   exit 1 unless FILE is what --lisp writes
  crossdefs.py TREE BASE --all ...      every compile-time definition, those
                                        BASE has as they are too
                                        (status :same), for a probe of
                                        declaring them all
  crossdefs.py TREE BASE --census [--table CROSS-TABLE]
                                        the #, census: every #, inside a
                                        compile-time definition (exit 1 if any),
                                        and the new or changed DEFCONSTANTs whose
                                        form reads a constant the cross table
                                        (cold:cross-write-table) changes
TREE and BASE are trees with sys/ (BASE: the builder's system's: System 2001's
for revision 14's cross build, e.g. muir-sim's
ref/band-2001-81b3973/handover-2001-81b3973-sys.tar.gz unpacked, or `git archive
release-2001`; System 2000's for G2's).
"""
import os
import re
import sys

DEFINERS = {'DEFMACRO', 'DEFSUBST', 'DEFSETF', 'DEFINE-SETF-METHOD', 'DEFSTRUCT',
            'DEFF-MACRO', 'DEFLAMBDA-MACRO', 'MACRO', 'DEFINE-MODIFY-MACRO',
            'DEFMACRO-DISPLACE', 'DEFSUBST-WITH-PARENT'}
WRAPPERS = {'EVAL-WHEN', 'PROGN', 'LOCAL-DECLARE', 'COMPILER-LET', 'LOOP-MACRO-PROGN'}
CONSTANTS = {'DEFCONSTANT', 'DEFCONST', 'DEFPARAMETER'}


class Str(str):
    """A string literal's text."""


class Tok(str):
    """An atom or a reader prefix, case folded."""


def attributes(text):
    m = re.search(r'-\*-(.*?)-\*-', text.split('\n', 1)[0])
    out = {}
    if m:
        for part in m.group(1).split(';'):
            if ':' in part:
                k, v = part.split(':', 1)
                out[k.strip().upper()] = v.strip()
    return out


def tokenize(text, esc):
    """Yield '(' ')' Str Tok, with positions."""
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c in ' \t\r\n\f':
            i += 1
        elif c == ';':
            j = text.find('\n', i)
            i = n if j < 0 else j + 1
        elif c in '()':
            yield c, i
            i += 1
        elif c == '"':
            j = i + 1
            buf = []
            while j < n and text[j] != '"':
                if text[j] == esc:
                    j += 1
                buf.append(text[j] if j < n else '')
                j += 1
            yield Str(''.join(buf)), i
            i = j + 1
        elif c in "'`":
            yield Tok(c), i
            i += 1
        elif c == ',':
            if text[i + 1:i + 2] == '@':
                yield Tok(',@'), i
                i += 2
            else:
                yield Tok(','), i
                i += 1
        elif c == '#' and i + 1 < n:
            d = text[i + 1]
            if d == '|':
                depth, j = 1, i + 2
                while j < n and depth:
                    if text.startswith('|#', j):
                        depth -= 1
                        j += 2
                    elif text.startswith('#|', j):
                        depth += 1
                        j += 2
                    else:
                        j += 1
                i = j
            elif d in '\\/' or (d not in ' \t\r\n\f()";|\'.,+-' and
                                re.match(r'#[^\s()";/\\]{1,4}[/\\]', text[i:i + 7])):
                # a character, #/x or #\x, also with a prefix between the #
                # and the slash (bits, as #\032/x in some files): one
                # character, or a name of letters
                k = i + 1
                while text[k] not in '/\\':
                    k += 1
                j = k + 2
                while j < n and (text[j].isalnum() or text[j] in '-_') and text[k + 1].isalpha():
                    j += 1
                yield Tok(text[i:j].upper() if j > k + 2 else text[i:j]), i
                i = j
            elif d == '(':
                # #( a vector: the list that follows is read as one
                yield Tok('#'), i
                i += 1
            elif d in "'.,":
                yield Tok('#' + d), i
                i += 2
            elif d in '+-':
                yield Tok('#' + d), i
                i += 2
            else:
                # #o17, #x.., #b.., #q, #m, #n: the dispatch and its atom
                j = i + 2
                while j < n and text[j] not in ' \t\r\n\f()";':
                    j += 1
                yield Tok(text[i:j].upper()), i
                i = j
        else:
            j = i
            buf = []
            while j < n and text[j] not in ' \t\r\n\f()";\'`,':
                if text[j] == esc and j + 1 < n:
                    buf.append(text[j:j + 2])
                    j += 2
                    continue
                if text[j] == '|':
                    # |...|, in which the escape character quotes a |
                    k = j + 1
                    while k < n and text[k] != '|':
                        k += 2 if text[k] == esc else 1
                    buf.append(text[j:k + 1])
                    j = k + 1
                    continue
                buf.append(text[j].upper())
                j += 1
            yield Tok(''.join(buf)), i
            i = j


def read_forms(text, esc):
    """Top-level forms: (nested lists of Str/Tok, start, end)."""
    stack, forms, starts = [], [], []
    for t, pos in tokenize(text, esc):
        if t == '(' and not isinstance(t, (Str, Tok)):
            stack.append([])
            starts.append(pos)
        elif t == ')' and not isinstance(t, (Str, Tok)):
            if not stack:
                continue
            lst = stack.pop()
            st = starts.pop()
            if stack:
                stack[-1].append(lst)
            else:
                forms.append((lst, st, pos + 1))
        else:
            if stack:
                stack[-1].append(t)
            else:
                forms.append((t, pos, pos + len(t)))
    return forms


def name_of(form):
    """The name a definition defines: a symbol, a structure's name, or for a
    function spec such as (AND ALTERNATE-MACRO-DEFINITION) the spec's text,
    which is not the symbol's own definition."""
    if len(form) < 2:
        return None
    x = form[1]
    if isinstance(x, list):
        if str(form[0]) == 'DEFSTRUCT':
            x = x[0] if x and not isinstance(x[0], list) else None
        else:
            return flat(x)
    return str(x) if x is not None else None


def definitions(form, out, top=True):
    """(kind, name, form) for each compile-time definition in FORM."""
    if not isinstance(form, list) or not form or isinstance(form[0], list):
        return
    head = str(form[0])
    if head in DEFINERS:
        n = name_of(form)
        if n:
            out.append((head, n, form))
    elif head in WRAPPERS:
        for sub in form[2:] if head in ('EVAL-WHEN', 'LOCAL-DECLARE', 'COMPILER-LET') else form[1:]:
            definitions(sub, out, False)


# the definers that proclaim their variable special when their file compiles:
# DEFVAR, DEFPARAMETER and DEFCONSTANT expand to (eval-when (compile)
# (proclaim '(special x))) (sys/sys2/lmmac.lisp), DEFCONST is DEFPARAMETER,
# and ZWEI's DEFGLOBAL is a DEFVAR (sys/zwei/defs.lisp)
SPECIAL_DEFINERS = {'DEFVAR', 'DEFPARAMETER', 'DEFCONST', 'DEFCONSTANT', 'DEFGLOBAL'}


def specials(form, out):
    """(kind, name) for each variable a top-level FORM makes special: a
    special-variable definer's, (SPECIAL a ...), or (PROCLAIM '(SPECIAL a ...))
    or (DECLARE (SPECIAL a ...)) at top level, through the forms that hold
    others."""
    if not isinstance(form, list) or not form or isinstance(form[0], list):
        return
    head = str(form[0])
    if head in SPECIAL_DEFINERS:
        if len(form) > 1 and isinstance(form[1], Tok):
            out.append((head, str(form[1])))
    elif head == 'SPECIAL':
        out.extend((head, str(x)) for x in form[1:] if isinstance(x, Tok))
    elif head in ('PROCLAIM', 'DECLARE'):
        for x in form[1:]:
            if isinstance(x, list) and x and str(x[0]) == 'SPECIAL':
                out.extend((head, str(y)) for y in x[1:] if isinstance(y, Tok))
    elif head in WRAPPERS:
        for sub in form[2:] if head in ('EVAL-WHEN', 'LOCAL-DECLARE', 'COMPILER-LET') else form[1:]:
            specials(sub, out)


def special_rows(t, b):
    """(rel, kind, name, status, package) for each special variable of the
    tree that BASE has not (status special), and of BASE that the tree has not
    (gone); a name is compared without its package prefix."""
    def collect(scanned):
        found = {}
        for rel in sorted(scanned):
            att, _, _, forms = scanned[rel]
            for fm in forms:
                out = []
                specials(fm, out)
                for k, n in out:
                    found.setdefault(n.split(':')[-1], (rel, k, n, att.get('PACKAGE', 'USER')))
        return found
    ts, bs = collect(t), collect(b)
    rows = [(rel, k, n, 'special', pkg) for key, (rel, k, n, pkg) in ts.items() if key not in bs]
    rows += [(rel, k, n, 'gone', pkg) for key, (rel, k, n, pkg) in bs.items() if key not in ts]
    return sorted(rows)


FLOAT = re.compile(r'^[-+]?(\d+\.\d+|\.\d+)([esfdlESFDL][-+]?\d+)?$|^[-+]?\d+(\.\d*)?[esfdlESFDL][-+]?\d+$')
FUNCTION_KINDS = {'DEFMACRO', 'DEFSUBST', 'MACRO', 'DEFF-MACRO', 'DEFLAMBDA-MACRO', 'DEFMACRO-DISPLACE'}


def has_float(form):
    """True if FORM holds a float literal, which the builder read with its own
    floats (System 2000's short float held 17 bits of significand)."""
    if isinstance(form, list):
        return any(has_float(x) for x in form)
    return isinstance(form, Tok) and bool(FLOAT.match(str(form)))


def flat(form):
    if isinstance(form, list):
        return '(' + ' '.join(flat(x) for x in form) + ')'
    if isinstance(form, Str):
        return '"' + form + '"'
    return str(form)


def contains_sharp_comma(form):
    if isinstance(form, list):
        return any(contains_sharp_comma(x) for x in form)
    return isinstance(form, Tok) and form == '#,'


def scan(tree):
    """{relative path: (attributes, [(kind, name, text, form)], [constant forms], [top forms])}"""
    out = {}
    root = os.path.join(tree, 'sys')
    for d, dns, files in os.walk(root):
        # the cross-check's own files, served as SYS: CROSS-CHECK; in its
        # copies of the tree, are not the tree's
        dns[:] = [x for x in dns if os.path.join(d, x) != os.path.join(root, 'cross-check')]
        for f in files:
            if not f.lower().endswith('.lisp'):
                continue
            p = os.path.join(d, f)
            text = open(p, 'rb').read().decode('latin-1')
            att = attributes(text)
            rt = att.get('READTABLE', 'ZL').upper()
            esc = '\\' if rt in ('CL', 'COMMON-LISP') or att.get('SYNTAX', '').upper().startswith('COMMON') else '/'
            # the parse must close every list it opens, or the list is not trusted
            depth = 0
            for tok, _ in tokenize(text, esc):
                if type(tok) is str and tok in '()':
                    depth += 1 if tok == '(' else -1
                    if depth < 0:
                        break
            if depth != 0:
                raise SystemExit('crossdefs: %s does not parse into whole forms' % p)
            forms = [f_ for f_, _, _ in read_forms(text, esc)]
            defs = []
            for form in forms:
                found = []
                definitions(form, found)
                defs.extend((k, n, flat(fm), fm) for k, n, fm in found)
            consts = [fm for fm in forms if isinstance(fm, list) and fm and not isinstance(fm[0], list)
                      and str(fm[0]) in CONSTANTS]
            out[os.path.relpath(p, tree)] = (att, defs, consts, forms)
    return out


def logical(rel):
    """sys/sys2/numdef.lisp -> SYS: SYS2; NUMDEF"""
    parts = rel.split('/')[1:]
    name = parts[-1][:-len('.lisp')].upper()
    return 'SYS: %s %s' % (' '.join(p.upper() + ';' for p in parts[:-1]), name)


def compare(tree, base, every=False):
    t, b = scan(tree), scan(base)
    bdefs = {}
    for rel, (_, defs, _, _) in b.items():
        for k, n, text, _ in defs:
            bdefs.setdefault((k, n), []).append((rel, text))
    tkeys = set()
    rows = []
    for rel in sorted(t):
        att, defs, _, _ = t[rel]
        for k, n, text, fm in defs:
            tkeys.add((k, n))
            old = bdefs.get((k, n))
            if old is None:
                status = 'new'
            elif any(text == o for _, o in old):
                # the same text, but its floats were read by the builder: a
                # macro or defsubst is given to the compile as the tree's
                if has_float(fm) and k in FUNCTION_KINDS:
                    status = 'floats'
                elif not every:
                    continue
                else:
                    status = 'same'
            else:
                status = 'changed'
            rows.append((rel, k, n, status, att.get('PACKAGE', 'USER')))
    for (k, n), olds in sorted(bdefs.items()):
        if (k, n) not in tkeys:
            for rel, _ in olds:
                rows.append((rel, k, n, 'gone', b[rel][0].get('PACKAGE', 'USER') if rel in b else 'USER'))
    return rows, t, b


def lisp_text(rows, srows):
    out = [';;; -*- Mode:LISP; Package:COLD; Base:10; Lowercase:T; Readtable:ZL -*-',
           '',
           ';;; The tree\'s compile-time definitions that the cross build gives every',
           ';;; compile for the target (cold:cross-begin, sys/cold/cross.lisp): each',
           ';;; (file kind name status), status :new, :changed, :gone (the builder\'s',
           ';;; system has it and the tree does not), or :floats (a macro or defsubst of the',
           ';;; same text that holds a float literal, which the builder read with its',
           ';;; own floats).  Written by tools/cross-check/crossdefs.py',
           ';;; from the sources; run it again after a change, since the cross build',
           ';;; checks that this list is what the sources give.',
           '',
           '(setq *cross-definitions* \'(']
    for rel, k, n, status, _ in rows:
        out.append('  ("%s" %s "%s" :%s)' % (logical(rel), k.lower(), n.replace('/', '//').replace('"', '/"'),
                                            status))
    out.append('  ))')
    out += ['',
            ';;; The tree\'s special variables that the builder\'s system has not, which',
            ';;; the cross build proclaims special in the builder while it compiles for',
            ';;; the target (cold:cross-begin): each (file kind name status), status',
            ';;; :special, or :gone (the builder\'s system has it and the tree does not),',
            ';;; which the cross build refuses.',
            '',
            '(setq *cross-specials* \'(']
    for rel, k, n, status, _ in srows:
        out.append('  ("%s" %s "%s" :%s)' % (logical(rel), k.lower(), n.replace('/', '//').replace('"', '/"'),
                                            status))
    out.append('  ))')
    return '\n'.join(out) + '\n'


def census(t, b, table):
    out, bad = [], 0
    out.append('== #, inside a compile-time definition (macro, defsubst, setf, structure)')
    for rel in sorted(t):
        for k, n, _, fm in t[rel][1]:
            if contains_sharp_comma(fm):
                out.append('  %s %s %s' % (rel, k, n))
                bad += 1
    out.append('  %d found' % bad)
    out.append('== #, elsewhere, by enclosing top-level form (evaluated in the target at load time)')
    total = 0
    for rel in sorted(t):
        for fm in t[rel][3]:
            if contains_sharp_comma(fm):
                head = str(fm[0]) if isinstance(fm, list) and fm and not isinstance(fm[0], list) else '?'
                if head in DEFINERS:
                    continue
                total += 1
                out.append('  %s %s %s' % (rel, head, name_of(fm) if isinstance(fm, list) else ''))
    out.append('  %d top-level forms' % total)
    changing = set()
    if table:
        for line in open(table, encoding='latin-1'):
            f = line.rstrip('\n').split('\t')
            if f[0] == 'T' and len(f) >= 4 and f[2] != f[3]:
                changing.add(f[1].split(':')[-1].upper())
    bconst = {}
    for rel, (_, _, consts, _) in b.items():
        for fm in consts:
            bconst[name_of(fm)] = flat(fm)
    out.append('== new or changed constants whose form reads a constant the cross table changes%s'
               % ('' if table else ' (no --table: every new or changed constant)'))
    nc = 0
    for rel in sorted(t):
        for fm in t[rel][2]:
            n = name_of(fm)
            if bconst.get(n) == flat(fm):
                continue
            syms = set()

            def walk(x):
                if isinstance(x, list):
                    for y in x:
                        walk(y)
                elif isinstance(x, Tok):
                    syms.add(str(x).split(':')[-1])
            walk(fm[2:3])
            hit = sorted(syms & changing) if table else sorted(syms)
            if table and not hit:
                continue
            nc += 1
            out.append('  %s %s %s %s' % (rel, fm[0], n, ('reads ' + ' '.join(hit)) if table else
                                          ('new' if n not in bconst else 'changed')))
    out.append('  %d listed' % nc)
    return out, bad


def main():
    a = sys.argv[1:]
    if len(a) < 2:
        raise SystemExit(__doc__)
    tree, base = a[0], a[1]
    rows, t, b = compare(tree, base, '--all' in a)
    if '--census' in a:
        table = a[a.index('--table') + 1] if '--table' in a else None
        out, bad = census(t, b, table)
        print('\n'.join(out))
        return 1 if bad else 0
    srows = special_rows(t, b)
    text = lisp_text(rows, srows)
    if '--check' in a:
        f = a[a.index('--check') + 1]
        cur = open(f, encoding='latin-1').read() if os.path.exists(f) else ''
        if cur != text:
            print('crossdefs: %s is not the list the sources give; run crossdefs.py %s %s --lisp %s'
                  % (f, tree, base, f))
            return 1
        print('crossdefs: %s is current (%d definitions, %d special variables)' % (f, len(rows), len(srows)))
        return 0
    if '--lisp' in a:
        open(a[a.index('--lisp') + 1], 'w', encoding='latin-1').write(text)
    for rel, k, n, status, pkg in rows + srows:
        print('%-8s %-32s %-18s %s' % (status, rel, k, n))
    return 0


if __name__ == '__main__':
    sys.exit(main())
