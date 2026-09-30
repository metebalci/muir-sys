#!/usr/bin/env python3
"""tools/microcode-check/fixpack-flag.py [UCADR-DIR]: a static check of
microcode 2001's sources (sys/ucadr/uc-*.lisp by default) for the rule that
FIXPACK-T and FIXPACK-P rely on (contract G2 section 2.2, appendix A1.3): they
test the fixnum overflow flag, which every executed ALU word loads, so the
last word executed before the test must be the ALU word that made M-1, or a
logical ALU word, whose flag is 0 and which boxes M-1 as it is.  Nothing else
may come between: no call, no page-fault check, no dispatch, no byte word.

For each jump to FIXPACK-T or FIXPACK-P the word that sets the flag is the
jump's own next word when the jump is -XCT-NEXT, and otherwise the word
before the jump.  That word must be an ALU word: an arithmetic one writing
M-1, or a logical one.  Prints each site and its word, and a FAIL line for
each that breaks the rule; exit status 0 when none does."""
import glob, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
UCADR = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', '..', 'sys', 'ucadr')
ARITH = {'ADD', 'SUB', 'M+A+1', 'M-A-1', 'M+M', 'M+M+1', 'M+1', 'M-1'}
LOGICAL = {'SETA', 'SETM', 'SETZ', 'SETO', 'SETCA', 'SETCM', 'AND', 'IOR', 'XOR', 'ANDCA',
           'ANDCM', 'ANDCB', 'ORCA', 'ORCM', 'ORCB', 'EQV'}
TARGETS = {'FIXPACK-T', 'FIXPACK-P'}


def forms(path):
    """Each top-level microcode form of PATH, as (line, text), comments dropped;
    labels and ERROR-TABLE forms are skipped."""
    lines = open(path, encoding='latin-1').read().split('\n')
    i = 0
    while i < len(lines):
        code = lines[i].split(';')[0]
        if '(' not in code or code.lstrip().upper().startswith('(SETQ'):
            i += 1
            continue
        text, start = code[code.index('('):], i
        depth = text.count('(') - text.count(')')
        while depth > 0 and i + 1 < len(lines):
            i += 1
            c = lines[i].split(';')[0]
            text += ' ' + c
            depth += c.count('(') - c.count(')')
        i += 1
        t = ' '.join(text.split()).upper()
        if t.startswith('(ERROR-TABLE') or t.startswith('(LOCALITY') or t.startswith('(START-DISPATCH') \
           or t.startswith('(END-DISPATCH') or t.startswith('(MISC-INST-ENTRY'):
            continue
        yield start + 1, t


def kind(t):
    """ALU-ARITH, ALU-LOGICAL, or what else the word T is, and its destinations."""
    m = re.match(r'\(\(([^()]*)\)\s*(\S+)', t)
    if m:
        dest, fn = m.group(1).split(), m.group(2).rstrip(')')
        if fn in ARITH:
            return 'alu-arith', dest
        if fn in LOGICAL or fn.startswith('A-') or fn.startswith('M-') or fn.startswith('(A-CONSTANT') \
           or fn.startswith('(M-CONSTANT') or fn in ('MD', 'READ-MEMORY-DATA', 'Q-R', 'VMA', 'PDL-POP'):
            return 'alu-logical', dest
        return 'byte-or-other', dest
    head = t[1:].split()[0].rstrip(')') if len(t) > 1 else t
    if head.startswith('POPJ-AFTER-NEXT'):
        return 'popj', []
    return head.lower(), []


def main():
    bad = sites = 0
    for path in sorted(glob.glob(os.path.join(UCADR, 'uc-*.lisp'))):
        fs = list(forms(path))
        for k, (line, t) in enumerate(fs):
            words = set(re.findall(r'[A-Z0-9+*-]+', t))
            if not (words & TARGETS) or not re.match(r'\((JUMP|CALL)', t):
                continue
            sites += 1
            xct = 'XCT-NEXT' in t.split()[0]
            fl, ft = fs[k + 1] if xct else fs[k - 1]
            what, dest = kind(ft)
            ok = (what == 'alu-arith' and 'M-1' in dest) or what == 'alu-logical'
            print('%s %s:%d %s\n      flag from %s:%d (%s) %s'
                  % ('ok  ' if ok else 'FAIL', os.path.basename(path), line, t,
                     os.path.basename(path), fl, what, ft))
            bad += 0 if ok else 1
    print('%d sites, %d break the rule' % (sites, bad))
    return 1 if bad or not sites else 0


sys.exit(main())
