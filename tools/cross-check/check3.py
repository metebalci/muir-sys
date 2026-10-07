#!/usr/bin/env python3
"""The cross build's check 3: a cold load's partition, read on the host, holds
NIL's and T's symbols where the cold load's own map says.

Usage: check3.py [--qcom QCOM] IMAGE WORD-BITS PAGE-SIZE [QNIL QT]
IMAGE is the partition's first blocks as cold:cross-copy-partition writes them:
word a at byte a * word-bytes, least significant byte first; 4 bytes a word at
32 bits, 5 at 40 (packed storage, contract G1 4.1 and 4.3: the tag in the fifth
byte).  The map is the cold load's own: the system communication area on page
1 (appendix A1.9), whose %SYS-COM-AREA-ORIGIN-PNTR points at REGION-ORIGIN,
whose entry for RESIDENT-SYMBOL-AREA is where NIL is, T five words after it.
QNIL and QT, the words MAKE-COLD reports for them (cold:cross-make-cold), are
compared when given.  Also checks the band format (for 40-bit words 2012 when
the parameters have no page hash table area, revision 14's (contract G3
revision 14, 10.6; appendix A14.13), else 2002; 1102 for 32-bit words at
1024-word pages, 0 at 256-word pages; A1.12) and the pointer width, and prints
a census of the words by data type.  The data types, areas and array types are
read from the parameters the cold load was made with: QCOM, by default the
tree this script is in (sys/cold/qcom.lisp); the native control gives its own
tree's.  Exits 1 on a failure.

With the generational collector's parameters (contract G3 step 2, 9.3: QCOM
defines %%REGION-GENERATION) the band format is 2022 and %SYS-COM-MARK-BITMAP
0; every region whose bits ask for a first-object table (a tenured structure
region that is not free, fixed or extra-pdl; clarification 4) begins with one,
an ART-32B array of one dimension with an entry a page of the region, each
entry below the free pointer a fixnum offset at or below its page's first
word, in order, 0 for the pages the table covers; WORKING-STORAGE-AREA's area
bits carry %%REGION-EPHEMERAL and its region's bits do not, and every region
is tenured.
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
if len(sys.argv) > 2 and sys.argv[1] == '--qcom':
    QCOM = sys.argv[2]
    del sys.argv[1:3]
DTP = {n: i for i, n in enumerate(qlist(QCOM, 'Q-DATA-TYPES'))}
AREAS = qlist(QCOM, 'AREA-LIST')
SYSCOM = qlist(QCOM, 'SYSTEM-COMMUNICATION-AREA-QS')
ARTS = qlist(QCOM, 'ARRAY-TYPES')


def qalt(path, name):
    """The NAME VALUE pairs of an alternating DEFCONST list, values octal."""
    text = open(path, 'rb').read().decode('latin-1')
    m = re.search(r"\(DEFCONST %s '\((.*?)\)\)" % re.escape(name), text, re.S | re.I)
    toks = re.sub(r';[^\n]*', '', m.group(1)).split()
    return {toks[i].upper(): int(toks[i + 1], 8) for i in range(0, len(toks) - 1, 2)}


# the region bits' fields, as byte specifiers (position, size) and values
RB = qalt(QCOM, 'Q-REGION-BITS-VALUES')
GENERATIONS = '%%REGION-GENERATION' in RB


def field(value, spec):
    return (value >> (spec >> 6)) & ((1 << (spec & 0o77)) - 1)
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


def tables(im, sc, page, origins, expect, out):
    """The generational collector's cold load (contract G3 step 2, 6.1, 9.3)."""
    mb = im.fixnum(sc + SYSCOM.index('%SYS-COM-MARK-BITMAP'))
    expect('%SYS-COM-MARK-BITMAP is 0', mb == 0, repr(mb))
    bits = {n: im.fixnum(origins['REGION-BITS'] + i) for i, n in enumerate(AREAS)}
    area_bits = {n: im.fixnum(origins['AREA-REGION-BITS'] + i) for i, n in enumerate(AREAS)}
    length = {n: im.fixnum(origins['REGION-LENGTH'] + i) for i, n in enumerate(AREAS)}
    fp = {n: im.fixnum(origins['REGION-FREE-POINTER'] + i) for i, n in enumerate(AREAS)}
    gen, eph = RB['%%REGION-GENERATION'], RB['%%REGION-EPHEMERAL']
    expect('every region is tenured', all(field(bits[n], gen) == RB['%REGION-GENERATION-TENURED']
                                          for n in AREAS))
    wsa = 'WORKING-STORAGE-AREA'
    expect('WORKING-STORAGE-AREA\'s area bits carry %%REGION-EPHEMERAL, its region\'s do not',
           field(area_bits[wsa], eph) == 1 and field(bits[wsa], eph) == 0,
           'area bits %o, region bits %o' % (area_bits[wsa], bits[wsa]))
    expect('no other area is ephemeral',
           all(field(area_bits[n], eph) == 0 for n in AREAS if n != wsa))
    rule, words = [], 0
    for n in AREAS:
        b = bits[n]
        space = field(b, RB['%%REGION-SPACE-TYPE'])
        # a region of no length (the last area's, FASL-TEMP-AREA) holds none
        if length[n] and (field(b, RB['%%REGION-REPRESENTATION-TYPE']) == RB['%REGION-REPRESENTATION-TYPE-STRUCTURE']
                and field(b, gen) == RB['%REGION-GENERATION-TENURED']
                and space not in (RB['%REGION-SPACE-FREE'], RB['%REGION-SPACE-FIXED'],
                                  RB['%REGION-SPACE-EXTRA-PDL'])):
            rule.append(n)
    for n in rule:
        o, pages = origins[n], length[n] // page
        cdr, dtp, ptr, w = im.split(o)
        art = (ptr >> 19) & 0o37
        ndims = (ptr >> 12) & 7
        long_ = (ptr >> 11) & 1
        n_entries = im.fixnum(o + 1) if long_ else ptr & 0o1777
        head = 2 if long_ else 1
        ok = (dtp == DTP['DTP-ARRAY-HEADER'] and ARTS[art] == 'ART-32B' and ndims == 1
              and n_entries == pages and length[n] % page == 0)
        detail = 'origin %o: dtp %d %s %d dims, %s entries for %d pages' % (
            o, dtp, ARTS[art] if art < len(ARTS) else art, ndims, n_entries, pages)
        bad = None
        if ok:
            prev, end = 0, head + pages
            for k in range(-(-fp[n] // page)):
                c2, d2, e, w2 = im.split(o + head + k)
                if (c2, d2) != (0, DTP['DTP-FIX']) or e > k * page or e < prev or \
                        (k * page < end and e != 0) or (k == 0 and e != 0):
                    bad = 'entry %d: tag %o, %o' % (k, w2 >> 32, e)
                    break
                prev = e
        expect('%s begins with its first-object table' % n, ok and bad is None,
               detail + (', ' + bad if bad else ', free pointer %o' % fp[n]))
        words += head + pages
        # NR-SYM holds symbols alone, 5 words each, from the table's end: the
        # generator's count, which the cold load's first boot compares with
        # MAPATOMS-NR-SYM's visits (the review of the first-object table, P6)
        if n == 'NR-SYM' and ok:
            start, syms, others = head + pages, 0, 0
            for a in range(o + start, o + fp[n], 5):
                if im.split(a)[1] == DTP['DTP-SYMBOL-HEADER']:
                    syms += 1
                else:
                    others += 1
            expect('NR-SYM holds symbols alone after its table', others == 0
                   and (fp[n] - start) % 5 == 0, '%d symbols, %d other words at a stride of 5'
                   % (syms, others))
            out.append('     NR-SYM symbols: %d' % syms)
    out.append('     first-object tables: %d regions (%s), %d words' % (len(rule), ' '.join(rule), words))


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
    # 2002 for 40-bit words; 1102 for 32-bit words at 1024-word pages (contract
    # G2, option (w)); 0 for 32-bit words at 256-word pages (A1.12).  revision
    # 14's 40-bit cold load, without the page hash table area, is 2012 (contract
    # G3 revision 14, 10.6; appendix A14.13)
    # the generational collector's 40-bit cold load is 2022 (contract G3 step 2,
    # 9.3)
    want = ((0o2002 if 'PAGE-TABLE-AREA' in AREAS else 0o2022 if GENERATIONS else 0o2012)
            if bits == 40 else 0o1102 if page == 1024 else 0)
    expect('%%SYS-COM-BAND-FORMAT is %o' % want,
           bf == want, 'octal %o' % bf if bf is not None else 'not a fixnum')
    pw = im.fixnum(sc + SYSCOM.index('%SYS-COM-POINTER-WIDTH'))
    expect('%SYS-COM-POINTER-WIDTH', pw == im.ptr_bits, repr(pw))
    vs = im.fixnum(sc + SYSCOM.index('%SYS-COM-VALID-SIZE'))
    expect('%SYS-COM-VALID-SIZE is within the image',
           vs is not None and vs * im.nbytes <= len(im.data) + page * im.nbytes,
           'octal %o, image ends at %o' % (vs or 0, len(im.data) // im.nbytes))
    if GENERATIONS:
        tables(im, sc, page, origins, expect, out)
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
