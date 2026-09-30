#!/usr/bin/env python3
"""Decode a QFASL file of this tree: its groups, its fasl table, and what each
group builds, as Python values.  Not a loader: an evaluation is kept as
('EVAL', form), a FEF as a Fef holding its boxed words' values and its
instruction halfwords.

A file compiled for the 40-bit machine names its word in its attribute list,
:WORD-WIDTH 40 (compiler:fasd-attributes-list, sys/sys/qcfasd.lisp), and holds
each float as FASL-OP-FLOAT with the flag set and two nibbles of IEEE binary32
bits, high first (compiler:fasd-binary32); decoded here as a Float32.  In a
32-bit file that group is today's small float, kept undecoded.

The FASL ops, the FEF header's layout and the fasl table's parameters are read
from the tree this script is in (sys/cold/qdefs.lisp, sys/cold/qcom.lisp).

Usage: qfasl.py FILE.qfasl [--fefs] [--dump]
"""
import os
import re
import struct
import sys

TREE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def _read_list(path, name):
    text = open(path, 'rb').read().decode('latin-1')
    m = re.search(r"\(DEFCONST %s '\((.*?)\)\)" % re.escape(name), text, re.S | re.I)
    if not m:
        raise SystemExit('no %s in %s' % (name, path))
    body = re.sub(r';[^\n]*', '', m.group(1))
    return [t.upper() for t in body.split()]


FASL_OPS = _read_list(os.path.join(TREE, 'sys/cold/qdefs.lisp'), 'FASL-OPS')
FEFHI = _read_list(os.path.join(TREE, 'sys/cold/qcom.lisp'), 'FEFHI-INDEXES')
FCTN_NAME = FEFHI.index('%FEFHI-FCTN-NAME')
TABLE_PARAMS = _read_list(os.path.join(TREE, 'sys/cold/qdefs.lisp'), 'FASL-TABLE-PARAMETERS')
EVALED = TABLE_PARAMS.index('FASL-EVALED-VALUE')
WORKING_OFFSET = 0o40


class Sym(str):
    """A symbol, printed with its package prefix as dumped."""


class Fef:
    def __init__(self, header, qs, mods, halfwords):
        self.header, self.qs, self.mods, self.halfwords = header, qs, mods, halfwords

    @property
    def name(self):
        return self.qs[FCTN_NAME] if len(self.qs) > FCTN_NAME else None

    def __repr__(self):
        return '#<FEF %s>' % (self.name,)


class Arr:
    def __init__(self, type_, dims, leader, nsp):
        self.type, self.dims, self.leader, self.nsp = type_, dims, leader, nsp
        self.data, self.halfwords = [], []

    def __repr__(self):
        return '#<ARRAY %s %s>' % (self.type, self.dims)


class Float32(float):
    """A float read as IEEE binary32 bits, which it keeps."""
    def __new__(cls, bits):
        v = struct.unpack('>f', struct.pack('>I', bits))[0]
        o = float.__new__(cls, v)
        o.bits = bits
        return o


class Decoder:
    def __init__(self, data):
        self.words = struct.unpack('<%dH' % (len(data) // 2), data[:len(data) // 2 * 2])
        self.pos = 0
        self.table = None
        self.plist = None
        self.width = 32
        self.events = []     # (kind, ...) of each group that does something
        self.fefs = []
        self.floats = []

    def nib(self):
        w = self.words[self.pos]
        self.pos += 1
        return w

    def next_nib(self):
        if self.glen <= 0:
            raise ValueError('group overflow at word %d' % self.pos)
        self.glen -= 1
        return self.nib()

    def enter(self, v):
        self.table.append(v)
        return len(self.table) - 1

    def value(self):
        return self.table[self.group()]

    def group(self):
        bits = self.nib()
        if not bits & 0o100000:
            raise ValueError('no check bit at word %d: %o' % (self.pos - 1, bits))
        saved = (getattr(self, 'gflag', None), getattr(self, 'glen', None))
        self.gflag = bool(bits & 0o40000)
        self.glen = (bits >> 6) & 0o377
        if self.glen == 0o377:
            self.glen = self.nib()
        op = FASL_OPS[bits & 0o77]
        fn = getattr(self, 'op_' + op[len('FASL-OP-'):].replace('-', '_').lower(), None)
        if fn is None:
            raise ValueError('unhandled %s at word %d' % (op, self.pos - 1))
        r = fn()
        self.gflag, self.glen = saved
        return r

    def whack(self):
        self.table = [None] * WORKING_OFFSET
        self.ret = None
        while self.ret is None:
            self.group()
        return self.ret

    def run(self):
        if self.nib() != 0o143150 or self.nib() != 0o71660:
            raise ValueError('not a QFASL file')
        while self.whack() != 'eof':
            pass
        return self

    # the ops
    def op_noop(self):
        return 0

    def op_index(self):
        return self.next_nib()

    def op_large_index(self):
        hi = self.next_nib()
        lo = self.next_nib()
        return (hi << 16) | lo

    def _string(self):
        s = []
        while self.glen > 0:
            n = self.next_nib()
            s.append(chr(n & 0o377))
            if (n >> 8) != 0o200:
                s.append(chr(n >> 8))
        return ''.join(s)

    def op_string(self):
        return self.enter(self._string())

    def op_symbol(self):
        s = self._string()
        return self.enter(Sym(('#:' if self.gflag else '') + s))

    def op_package_symbol(self):
        n = self.next_nib()
        count = 2 if n in (2, 0o402) else n
        parts = [self.value() for _ in range(count)]
        sep = '::' if n == 0o402 else ':'
        return self.enter(Sym(sep.join(str(p) for p in parts)))

    def op_fixed(self):
        v = 0
        for _ in range(self.glen):
            v = (v << 16) | self.next_nib()
        return self.enter(-v if self.gflag else v)

    def op_character(self):
        v = 0
        for _ in range(self.glen):
            v = (v << 16) | self.next_nib()
        return self.enter(('CHAR', -v if self.gflag else v))

    def op_float(self):
        if self.gflag:
            hi = self.next_nib()
            lo = self.next_nib()
            if self.width == 40:
                f = Float32((hi << 16) | lo)
            else:
                f = ('SMALL-FLOAT-BITS', (hi << 16) | lo)
        else:
            f = ('FLONUM-NIBBLES', self.next_nib(), self.next_nib(), self.next_nib())
        self.floats.append(f)
        return self.enter(f)

    def op_new_float(self):
        nibs = [self.next_nib() for _ in range(self.glen)]
        f = ('NEW-FLOAT', self.gflag, nibs)
        self.floats.append(f)
        return self.enter(f)

    def op_rational(self):
        return self.enter(('RATIONAL', self.value(), self.value()))

    def op_complex(self):
        return self.enter(('COMPLEX', self.value(), self.value()))

    def _list(self, component=False):
        n = self.next_nib()
        items = [self.value() for _ in range(n)]
        if self.gflag:
            items = ('DOTTED', items)
        if component:
            self.table[EVALED] = items
            return EVALED
        return self.enter(items)

    def op_list(self):
        return self._list()

    def op_temp_list(self):
        return self._list()

    def op_list_component(self):
        return self._list(True)

    def op_array(self):
        self.value()                            # area
        type_ = self.value()
        dims = self.value()
        self.value()                            # displaced-p
        lead = self.value()
        self.value()                            # index offset
        nsp = self.value() if self.gflag else None
        return self.enter(Arr(type_, dims, lead, nsp))

    def op_null_array_element(self):
        return self.enter(('NULL',))

    def op_initialize_array(self):
        idx = self.group()
        arr = self.table[idx]
        num = self.value()
        for _ in range(num):
            arr.data.append(self.value())
        return idx

    def op_initialize_numeric_array(self):
        idx = self.group()
        arr = self.table[idx]
        num = self.value()
        arr.halfwords = [self.nib() for _ in range(num)]
        return idx

    def op_array_push(self):
        self.value()
        self.value()
        return 0

    def op_eval(self):
        form = self.table[self.next_nib()]
        self.events.append(('EVAL', form))
        self.table[EVALED] = ('EVAL', form)
        return EVALED

    def op_eval1(self):
        form = self.value()
        self.events.append(('EVAL', form))
        return self.enter(('EVAL', form))

    def op_move(self):
        frm = self.next_nib()
        to = self.next_nib()
        if to == 0o177777:
            return self.enter(self.table[frm])
        while len(self.table) <= to:
            self.table.append(None)
        self.table[to] = self.table[frm]
        return to

    def op_frame(self):
        qcount = self.next_nib()
        ucount = self.next_nib()
        self.glen = self.next_nib()
        header = self.value()
        self.next_nib()
        qs, mods = [header], [0]
        for _ in range(1, qcount):
            qs.append(self.value())
            mods.append(self.next_nib())
        halfwords = [self.next_nib() for _ in range(2 * ucount)]
        fef = Fef(header, qs, mods, halfwords)
        self.fefs.append(fef)
        return self.enter(fef)

    def op_function_header(self):
        self.value()
        self.value()
        return 0

    def op_function_end(self):
        return 0

    def _storein(self, kind):
        data = self.table[self.next_nib()]
        sym = self.value()
        self.events.append((kind, sym, data))
        return 0

    def op_storein_symbol_value(self):
        return self._storein('SET')

    def op_storein_function_cell(self):
        return self._storein('FSET')

    def op_storein_property_cell(self):
        return self._storein('PLIST')

    def op_storein_symbol_cell(self):
        cell = self.next_nib()
        data = self.value()
        sym = self.value()
        self.events.append((('SET', 'FSET', 'PLIST')[cell - 1], sym, data))
        return 0

    def op_storein_array_leader(self):
        self.next_nib()
        self.next_nib()
        self.next_nib()
        return 0

    def _fetch(self, kind):
        return self.enter((kind, self.value()))

    def op_fetch_symbol_value(self):
        return self._fetch('SYMEVAL')

    def op_fetch_function_cell(self):
        return self._fetch('FSYMEVAL')

    def op_fetch_property_cell(self):
        return self._fetch('PLIST')

    def op_apply(self):
        count = self.next_nib()
        fn = self.value()
        args = [self.value() for _ in range(count)]
        self.events.append(('APPLY', fn, args))
        self.table[EVALED] = ('APPLY', fn, args)
        return EVALED

    def op_end_of_whack(self):
        self.ret = 'end-of-whack'
        return 0

    def op_end_of_file(self):
        self.ret = 'eof'
        return 0

    def op_soak(self):
        for _ in range(self.next_nib()):
            self.value()
        return self.group()

    def op_set_parameter(self):
        self.value()
        self.group()
        return 0

    def op_file_property_list(self):
        plist = self.value()
        self.plist = plist
        for i in range(0, len(plist) - 1, 2):
            if str(plist[i]).upper().endswith('WORD-WIDTH'):
                self.width = plist[i + 1]
        return 0


def decode(path):
    return Decoder(open(path, 'rb').read()).run()


def show(x):
    """x printed: a Float32 with its bits, lists in parentheses."""
    if isinstance(x, Float32):
        return '%r[#x%08X]' % (float(x), x.bits)
    if isinstance(x, list):
        return '(' + ' '.join(show(e) for e in x) + ')'
    if isinstance(x, tuple) and x and x[0] == 'DOTTED':
        return '(' + ' '.join(show(e) for e in x[1][:-1]) + ' . ' + show(x[1][-1]) + ')'
    if isinstance(x, int) and not isinstance(x, bool):
        return '%d' % x
    return str(x)


if __name__ == '__main__':
    d = decode(sys.argv[1])
    print('plist', show(d.plist))
    print('word-width', d.width)
    if '--fefs' in sys.argv:
        for f in d.fefs:
            print('FEF', show(f.name), ' '.join(show(q) for q in f.qs[len(FEFHI) - 1:]))
    if '--dump' in sys.argv:
        for e in d.events:
            print(' '.join(show(x) for x in e))
