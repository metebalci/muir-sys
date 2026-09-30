#!/usr/bin/env python3
"""The cross build's check 3: a cold load's partition, read on the host, holds
NIL's and T's symbols where the cold load's own map says.

Usage: check3.py IMAGE WORD-BITS PAGE-SIZE [QNIL QT]
IMAGE is the partition's first blocks as cold:cross-copy-partition writes them:
word a at byte a * word-bytes, least significant byte first; 4 bytes a word at
32 bits, 5 at 40 (packed storage, contract G1 4.1 and 4.3: the tag in the fifth
byte).  The map is the cold load's own: the system communication area on page
1 (appendix A1.9), whose %SYS-COM-AREA-ORIGIN-PNTR points at REGION-ORIGIN,
whose entry for RESIDENT-SYMBOL-AREA is where NIL is, T five words after it.
QNIL and QT, the words MAKE-COLD reports for them (cold:cross-make-cold), are
compared when given.  Also checks the band format (2002 for 40-bit words, A1.12)
and the pointer width, and prints a census of the words by data type.  The data
types, areas and array types are read from the tree this script is in
(sys/cold/qcom.lisp).  Exits 1 on a failure.
"""
import collections
import os
import re
import struct
import sys

TREE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def qlist(path, name):
    text = open(path, 'rb').read().decode('latin-1')
    m = re.search(r"\(DEFCONST %s '\((.*?)\)\)" % re.escape(name), text, re.S | re.I)
    body = re.sub(r';[^\n]*', '', m.group(1))
    return [t.upper() for t in body.split()]


QCOM = os.path.join(TREE, 'sys/cold/qcom.lisp')
DTP = {n: i for i, n in enumerate(qlist(QCOM, 'Q-DATA-TYPES'))}
AREAS = qlist(QCOM, 'AREA-LIST')
SYSCOM = qlist(QCOM, 'SYSTEM-COMMUNICATION-AREA-QS')
ARTS = qlist(QCOM, 'ARRAY-TYPES')
CDR = {'NORMAL': 0, 'ERROR': 1, 'NIL': 2, 'NEXT': 3}


class Image:
    def __init__(self, path, bits):
        self.data = open(path, 'rb').read()
        self.bits = bits
        self.nbytes = 5 if bits == 40 else 4
        self.ptr_bits = 32 if bits == 40 else 25
        self.type_bits = 6 if bits == 40 else 5

    def word(self, a):
        o = a * self.nbytes
        if o + self.nbytes > len(self.data):
            raise IndexError('address %o past the image' % a)
        return int.from_bytes(self.data[o:o + self.nbytes], 'little')

    def split(self, a):
        w = self.word(a)
        ptr = w & ((1 << self.ptr_bits) - 1)
        dtp = (w >> self.ptr_bits) & ((1 << self.type_bits) - 1)
        cdr = w >> (self.ptr_bits + self.type_bits)
        return cdr, dtp, ptr, w

    def fixnum(self, a):
        cdr, dtp, ptr, w = self.split(a)
        if dtp != DTP['DTP-FIX']:
            return None
        if ptr >= 1 << (self.ptr_bits - 1):
            ptr -= 1 << self.ptr_bits
        return ptr

    def string(self, a):
        """The characters of the ART-STRING whose header is at a."""
        cdr, dtp, ptr, w = self.split(a)
        if dtp != DTP['DTP-ARRAY-HEADER']:
            return None, 'header at %o is %s' % (a, dtp)
        art = (ptr >> 19) & 0o37
        ndims = (ptr >> 12) & 7
        n = ptr & 0o1777
        if ARTS[art] != 'ART-STRING' or ndims != 1 or (ptr >> 11) & 1:
            return None, 'header at %o: type %s dims %d' % (a, ARTS[art], ndims)
        chars = []
        for i in range((n + 3) // 4):
            cdr2, dtp2, ptr2, w2 = self.split(a + 1 + i)
            if self.bits == 40 and (cdr2, dtp2) != (0, DTP['DTP-FIX']):
                return None, 'character word at %o has tag %o' % (a + 1 + i, w2 >> 32)
            field = w2 & 0xFFFFFFFF
            chars += [(field >> (8 * k)) & 0xFF for k in range(4)]
        return ''.join(chr(c) for c in chars[:n]), None


def main():
    path, bits, page = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    reported = [int(x) for x in sys.argv[4:6]] if len(sys.argv) >= 6 else None
    im = Image(path, bits)
    out, fails = [], 0

    def expect(what, ok, detail=''):
        nonlocal fails
        out.append('%-4s %s %s' % ('ok' if ok else 'FAIL', what, detail))
        if not ok:
            fails += 1

    out.append('image %s: %d bytes, %d-bit words of %d bytes, pages of %d words'
               % (os.path.basename(path), len(im.data), bits, im.nbytes, page))
    sc = page                                   # the system communication area: page 1
    cdr, dtp, ro, w = im.split(sc + SYSCOM.index('%SYS-COM-AREA-ORIGIN-PNTR'))
    expect('%SYS-COM-AREA-ORIGIN-PNTR is a locative', dtp == DTP['DTP-LOCATIVE'],
           'at %o: dtp %d -> %o' % (sc, dtp, ro))
    origins = {name: im.fixnum(ro + i) for i, name in enumerate(AREAS)}
    expect('REGION-ORIGIN holds fixnums', all(v is not None for v in origins.values()))
    expect('the map puts SYSTEM-COMMUNICATION-AREA on page 1',
           origins['SYSTEM-COMMUNICATION-AREA'] == page,
           'origin %o' % origins['SYSTEM-COMMUNICATION-AREA'])
    expect('the map puts REGION-ORIGIN where %SYS-COM-AREA-ORIGIN-PNTR points',
           origins['REGION-ORIGIN'] == ro, 'origin %o' % origins['REGION-ORIGIN'])
    rsa = origins['RESIDENT-SYMBOL-AREA']
    for name, addr in (('NIL', rsa), ('T', rsa + 5)):
        cdr, dtp, pname, w = im.split(addr)
        expect('%s: header' % name, cdr == CDR['NEXT'] and dtp == DTP['DTP-SYMBOL-HEADER'],
               'at %o: word %o, cdr %d, dtp %d' % (addr, w, cdr, dtp))
        s, err = im.string(pname)
        expect('%s: print name' % name, s == name, repr(s) if s is not None else err)
        cdr, dtp, ptr, w = im.split(addr + 1)
        expect('%s: value cell is itself' % name,
               dtp == DTP['DTP-SYMBOL'] and ptr == addr and cdr == CDR['NEXT'],
               'dtp %d -> %o' % (dtp, ptr))
        cdr, dtp, ptr, w = im.split(addr + 2)
        expect('%s: function cell is DTP-NULL' % name, dtp == DTP['DTP-NULL'] and ptr == addr)
        cdr, dtp, ptr, w = im.split(addr + 3)
        expect('%s: property list is NIL or a list' % name,
               (dtp == DTP['DTP-SYMBOL'] and ptr == rsa) or dtp == DTP['DTP-LIST'],
               'dtp %d -> %o' % (dtp, ptr))
        cdr, dtp, ptr, w = im.split(addr + 4)
        expect('%s: package cell is NIL' % name, dtp == DTP['DTP-SYMBOL'] and ptr == rsa,
               'dtp %d -> %o cdr %d' % (dtp, ptr, cdr))
        if reported:
            want = reported[0] if name == 'NIL' else reported[1]
            got = (DTP['DTP-SYMBOL'] << im.ptr_bits) | addr
            expect('%s: where MAKE-COLD said' % name, want == got,
                   'reported %o, found %o' % (want, got))
    bf = im.fixnum(sc + SYSCOM.index('%SYS-COM-BAND-FORMAT'))
    expect('%%SYS-COM-BAND-FORMAT is %s' % ('2002' if bits == 40 else '0'),
           bf == (0o2002 if bits == 40 else 0), 'octal %o' % bf if bf is not None else 'not a fixnum')
    pw = im.fixnum(sc + SYSCOM.index('%SYS-COM-POINTER-WIDTH'))
    expect('%SYS-COM-POINTER-WIDTH', pw == im.ptr_bits, repr(pw))
    vs = im.fixnum(sc + SYSCOM.index('%SYS-COM-VALID-SIZE'))
    expect('%SYS-COM-VALID-SIZE is within the image',
           vs is not None and vs * im.nbytes <= len(im.data) + page * im.nbytes,
           'octal %o, image ends at %o' % (vs or 0, len(im.data) // im.nbytes))
    # a census of the image's words by data type, and its first floats and bignums
    census = collections.Counter()
    floats, bignums = [], []
    for a in range(len(im.data) // im.nbytes):
        cdr, dtp, ptr, w = im.split(a)
        census[dtp] += 1
        if dtp == DTP['DTP-SMALL-FLONUM'] and bits == 40 and len(floats) < 12:
            floats.append(struct.unpack('>f', struct.pack('>I', ptr))[0])
        if dtp == DTP['DTP-EXTENDED-NUMBER'] and len(bignums) < 4:
            bignums.append(ptr)
    names = {v: k for k, v in DTP.items()}
    out.append('     words by data type: ' + ', '.join('%s %d' % (names.get(k, 'DTP-%d' % k)[4:], n)
                                                      for k, n in sorted(census.items())))
    if floats:
        out.append('     first floats (binary32): %s' % ', '.join('%g' % f for f in floats))
    for p in bignums:
        cdr, dtp, hdr, w = im.split(p)
        digits = [im.split(p + 1 + i)[2] for i in range(min(3, hdr & 0o377))]
        out.append('     bignum at %o: header dtp %d field %o, digits %s' % (p, dtp, hdr, digits))
    out.append('RESULT %s (%d failures)' % ('PASS' if fails == 0 else 'FAIL', fails))
    print('\n'.join(out))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
