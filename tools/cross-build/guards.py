"""The guards for tools/cross-build's step guards: contract G3 revision 15b
appendix A15b.1's for a route whose microcode is revision 15's, the default
(run_all_15, below), and contract G3 revision 14 appendix A14.13's for one
whose microcode is revision 14's (run_all_14); run_all chooses by the
assembled ucadr.mcr's first word.  In each, each mix of revision, PROM,
microcode and band that must stop is booted and must halt where the guard
says; each has a control, the nearest right mix, which must not halt
there.  A run is quux with --stop-after, whose last "PC n" line is where the
machine stood; a PROM's halt (JUMP HALT-CONS) shows the label itself, the
microcode's (CALL ILLOP) the word after it.

A14.13's:

  prom-file-rev13 PROM 2002's .mcr on revision 13: quux refuses the file, whose
                  section 6 says revision 14, before the PROM runs
  prom-rev13      PROM 2002 without its section 6 on revision 13, so that it
                  runs: its first act halts at ERROR-NOT-REVISION-14
                  (control: PROM 2002 on revision 14 leaves the PROM)
  uc2001-rev14    revision 13's microcode, 2001, on a revision-14 disk under
                  PROM 2002: ERROR-MICROCODE-NOT-REVISION-14
                  (control: microcode 2002 leaves the PROM)
  disk14-rev13    a revision-14 disk (microcode 2002) on revision 13 under
                  PROM 2001 (the builder's): ERROR-BAD-SECTION-TYPE (control:
                  microcode 2001 leaves the PROM)
  uc2002-rev13    microcode 2002 loaded otherwise on revision 13: its .mcr
                  without section 6, which PROM 2001 loads: MACHINE-NOT-QUUX-14
                  (control: microcode 2002 on revision 14 under PROM 2002
                  runs past it)
  band2001        System 2001's band under microcode 2002:
                  BAND-NOT-REVISION-14 (control: the first band runs past it)
  checkpoint      a revision-13 checkpoint resumed on revision 14, and a
                  revision-14 one on 13: refused (control: each resumes on
                  its own revision)

The generational collector (contract G3 step 2 revision 1, 9.4, C27) moves
the route on: its microcode, still 2002 at revision 14, takes formats
2020-2022 alone, and the builder is revision 14's band.  The lines above are
booted with step 2's microcode and band (band4) where they had revision 14's,
and with revision 13's pieces (System 2001's disk and sys/ubin/, the run's
--previous-band and --previous-ubin) where they had the builder's.  C27's:

  band2010        revision 14's band (the builder's, format 2010) under step
                  2's microcode: BAND-NOT-GENERATIONAL (control: the same band
                  under revision 14's microcode, the builder's, runs past it)
  band2011, band2012  the same band with its format word made 2011 and 2012
                  (the halt is decided on that word alone): BAND-NOT-GENERATIONAL
                  (control: band4 runs past it)
  band2001        (above) a 2000 band: BAND-NOT-REVISION-14
  bitmap-missing  band4 with %SYS-COM-MARK-BITMAP made 0: MARK-BITMAP-MISSING
                  (control: band4)
  bitmap-size     band4 with %SYS-COM-MARK-BITMAP one page later than its
                  bitmap: MARK-BITMAP-WRONG-SIZE (control: band4)
  step2-on-step1  band4 (2020) under revision 14's microcode: BAND-NOT-40-BIT
                  (control: the builder's band under it runs past)
  cold-on-step1   step 2's cold load (2022) under revision 14's microcode:
                  BAND-NOT-40-BIT (control: the same cold load under step 2's
                  microcode runs past it)
"""
import os
import re
import shutil
import subprocess
import time

CYCLES = 600000000
# a revision-15 .mcr's first word, the format word 0x51550001 (appendix
# A15b.7), little endian as the file holds it
FORMAT_WORD_15 = bytes([0x01, 0x00, 0x55, 0x51])


def label_of(symfiles, first, pc):
    """PC as octal and LABEL+offset: from the PROM's symbols at 36000 and
    above, else from FIRST's (the microcode's, or the PROM's for a PROM's
    guard), the nearest label at or below it."""
    if pc is None:
        return '-'
    f = first if pc < 0o36000 else ([x for x in symfiles if 'promh' in x and x == first]
                                    or [x for x in symfiles if 'promh' in x])[0]
    best = None
    t = open(f, encoding='latin-1').read().split()
    for k in range(len(t) - 2):
        if (t[k + 1] == 'I-MEM' and re.match(r'[0-7]+$', t[k + 2])
                and not t[k].startswith('I-MEM-LOC')):
            a = int(t[k + 2], 8)
            if a <= pc and (best is None or a > best[0]):
                best = (a, t[k])
    return '%o (%s+%o)' % (pc, best[1], pc - best[0]) if best else '%o' % pc


def symbol(symfile, name):
    text = open(symfile, encoding='latin-1').read()
    m = re.search(r'(?:^|\s)' + re.escape(name) + r' I-MEM (\d+)', text, re.I)
    if not m:
        raise SystemExit('guards: no %s in %s' % (name, symfile))
    return int(m.group(1), 8)


def quux(run, where, name, rev, disk, prom=None, extra=()):
    """Run quux at REV on DISK; returns (exit status, last PC or None, output).
    Its stdin stays open while it runs: at its end quux leaves a running
    machine at once."""
    env = dict(os.environ, MUIR_QUUX_REVISION=str(rev))
    with run.lock:
        port = run.qld_ports.pop(0)
    cmd = [os.path.abspath(run.a.quux), '-c', '/dev/null', '--micro', '--disk-pack', disk,
           '--terminal', '127.0.0.1:%d' % port] + list(extra)
    if prom:
        cmd += ['--prom', prom]
    log = os.path.join(where, name + '.log')
    try:
        with open(log, 'w') as f:
            f.write('MUIR_QUUX_REVISION=%d %s\n' % (rev, ' '.join(cmd)))
            f.flush()
            p = subprocess.Popen(cmd, env=env, stdin=subprocess.PIPE, stdout=f,
                                 stderr=subprocess.STDOUT)
            try:
                # once the machine has stopped (a halt, or --stop-after), it
                # waits at quux's prompt: quit it
                t0 = time.time()
                while p.poll() is None and time.time() - t0 < 1800:
                    time.sleep(1)
                    if re.search(r'^PC \d+|ran out at \d+; PC \d+', open(log, encoding='latin-1').read(),
                                 re.M):
                        try:
                            p.stdin.write(b'quit\n')
                            p.stdin.flush()
                        except OSError:           # it has quit already
                            pass
                        p.wait(timeout=60)
            finally:
                if p.poll() is None:
                    p.kill()
                    p.wait()
                try:
                    p.stdin.close()
                except OSError:
                    pass
    finally:
        with run.lock:
            run.qld_ports.append(port)
    out = open(log, encoding='latin-1').read()
    # where it stood: "PC n; ..." after a halt, "ran out at N; PC n" after --stop-after
    pcs = re.findall(r'(?:^|ran out at \d+; )PC (\d+)', out, re.M)
    return p.returncode, (int(pcs[-1], 8) if pcs else None), out


def word(v):
    """A fixnum's five bytes in a band, tag 005."""
    return (v & 0xffffffff).to_bytes(4, 'little') + b'\x05'


def patched(src, dest, words):
    """A copy of the band SRC whose page 1 (the system communication area)
    has WORDS ({index: fixnum}) written."""
    shutil.copy(src, dest)
    with open(dest, 'r+b') as f:
        for k, v in words.items():
            f.seek(5 * 1024 + 5 * k)
            f.write(word(v))
    return dest


def run_all(run):
    """The guards for the microcode the route assembled: A15b.1's when it is
    revision 15's self-describing .mcr (its format word first), A14.13's when
    it opens with section 6, revision 14's.  The route assembles for revision
    15 by default since its machine moved to revision 16 (QUUX's Ethernet
    contract, section 8 R2, clarified 19 Oct); before, this was A14.13's
    alone, and on a revision-15 assembly it stopped at once ("does not open
    with section 6")."""
    head = open(os.path.join(run.ubin, 'ucadr.mcr'), 'rb').read(4)
    if head == FORMAT_WORD_15:
        return run_all_15(run)
    return run_all_14(run)


def run_all_14(run):
    where = os.path.join(run.out, 'guards')
    os.makedirs(where, exist_ok=True)
    work = os.path.join(run.work, 'guards')
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work)
    if not (run.a.previous_band and run.a.previous_ubin):
        raise SystemExit('guards: --previous-band and --previous-ubin (System 2001\'s) are needed')
    # step 2's microcode and PROM 2002 (assembled); revision 14's microcode,
    # the builder's (step 1); revision 13's, System 2001's, with PROM 2001
    ub, bub, pub = run.ubin, run.a.builder_ubin, run.a.previous_ubin
    prom14 = os.path.join(ub, 'promh.mcr')
    prom13 = os.path.join(pub, 'promh.mcr')
    uc2, uc1, uc13 = (os.path.join(d, 'ucadr.mcr') for d in (ub, bub, pub))
    # the bands' own partitions, read off their disks: band4 (2020), the
    # builder's (2010), System 2001's (2000), and check 3's cold load (2022)
    band2_lod = os.path.join(work, 'band2.lod')
    run.read_part(os.path.join(run.bands, 'band4.img'), 'LOD1', band2_lod)
    def current_band(disk, dest):
        img = os.path.join(work, 'copy.img')
        run.raw_copy(disk, img)
        cur = [p for p in run.gpt(img) if p[5] and p[4] >> 48 & 1]
        run.read_part(img, cur[0][1].split()[0], dest)
        os.unlink(img)
        return dest
    band14_lod = current_band(run.a.builder, os.path.join(work, 'band14.lod'))
    band13_lod = current_band(run.a.previous_band, os.path.join(work, 'band13.lod'))
    cold2 = os.path.join(run.work, 'cold-3.img')
    fmt2, valid2 = run.band_header(os.path.join(run.bands, 'band4.img'),
                                   run.part(os.path.join(run.bands, 'band4.img'), 'LOD1')[2])
    with open(band2_lod, 'rb') as f:
        f.seek(5 * 1024 + 5 * 30)
        bitmap = int.from_bytes(f.read(4), 'little')
    run.record('  guards: band4 format %o, valid %d words, mark bitmap at band page %d'
               % (fmt2, valid2, bitmap))
    # microcode 2002 without its section 6, the first 16 bytes (code 6, start
    # 0, count 1, the revision)
    head = open(uc2, 'rb').read()
    if head[:4] != b'\x06\0\0\0':
        raise SystemExit('guards: %s does not open with section 6' % uc2)
    uc2_bare = os.path.join(work, 'ucadr-no-section-6.mcr')
    open(uc2_bare, 'wb').write(head[16:])
    # and PROM 2002 without its section 6, which quux would refuse on revision
    # 13 before the PROM ran: so that the PROM's own first act is seen
    phead = open(prom14, 'rb').read()
    prom14_bare = os.path.join(work, 'promh-no-section-6.mcr')
    open(prom14_bare, 'wb').write(phead[16:] if phead[:4] == b'\x06\0\0\0' else phead)

    def disk(name, mcr, lod):
        d = os.path.join(work, name + '.img')
        run.make_disk(d, mcr, {'LOD1': lod})
        return d
    d2 = disk('d2', uc2, band2_lod)
    d13 = disk('d13', uc13, band13_lod)
    d2uc13 = disk('d2uc13', uc13, band2_lod)
    dbare = disk('dbare', uc2_bare, band2_lod)
    dband13 = disk('dband13', uc2, band13_lod)
    # C27 (contract G3 step 2 revision 1)
    d2010 = disk('d2010', uc2, band14_lod)
    d14 = disk('d14', uc1, band14_lod)
    d2011 = disk('d2011', uc2, patched(band14_lod, os.path.join(work, 'b2011.lod'), {8: 0o2011}))
    d2012 = disk('d2012', uc2, patched(band14_lod, os.path.join(work, 'b2012.lod'), {8: 0o2012}))
    dmissing = disk('dmissing', uc2, patched(band2_lod, os.path.join(work, 'bmissing.lod'), {30: 0}))
    dsize = disk('dsize', uc2, patched(band2_lod, os.path.join(work, 'bsize.lod'), {30: bitmap + 1}))
    d2on1 = disk('d2on1', uc1, band2_lod)
    dcold1 = disk('dcold1', uc1, cold2)
    dcold2 = disk('dcold2', uc2, cold2)
    psym14, psym13 = os.path.join(ub, 'promh.sym'), os.path.join(pub, 'promh.sym')
    usym2, usym1 = os.path.join(ub, 'ucadr.sym'), os.path.join(bub, 'ucadr.sym')
    stop = ['--stop-after', str(CYCLES)]
    cases = [
        # name, revision, disk, prom, the halt (sym, label, offset), control
        ('prom-rev13', 13, d2, prom14_bare, (psym14, 'ERROR-NOT-REVISION-14', 0),
         ('prom-rev14-control', 14, d2, prom14)),
        ('uc2001-rev14', 14, d2uc13, prom14, (psym14, 'ERROR-MICROCODE-NOT-REVISION-14', 0),
         ('uc2002-rev14-control', 14, d2, prom14)),
        ('disk14-rev13', 13, d2, prom13, (psym13, 'ERROR-BAD-SECTION-TYPE', 0),
         ('disk13-rev13-control', 13, d13, prom13)),
        ('uc2002-rev13', 13, dbare, prom13, (usym2, 'MACHINE-NOT-QUUX-14', 1),
         ('uc2002-rev14-control-2', 14, d2, prom14)),
        ('band2001', 14, dband13, prom14, (usym2, 'BAND-NOT-REVISION-14', 1),
         ('band2002-control', 14, d2, prom14)),
        ('band2010', 14, d2010, prom14, (usym2, 'BAND-NOT-GENERATIONAL', 1),
         ('band2010-on-step1-control', 14, d14, prom14)),
        ('band2011', 14, d2011, prom14, (usym2, 'BAND-NOT-GENERATIONAL', 1),
         ('band2020-control', 14, d2, prom14)),
        ('band2012', 14, d2012, prom14, (usym2, 'BAND-NOT-GENERATIONAL', 1),
         ('band2020-control-2', 14, d2, prom14)),
        ('bitmap-missing', 14, dmissing, prom14, (usym2, 'MARK-BITMAP-MISSING', 1),
         ('band2020-control-3', 14, d2, prom14)),
        ('bitmap-size', 14, dsize, prom14, (usym2, 'MARK-BITMAP-WRONG-SIZE', 1),
         ('band2020-control-4', 14, d2, prom14)),
        ('step2-on-step1', 14, d2on1, prom14, (usym1, 'BAND-NOT-40-BIT', 1),
         ('band2010-on-step1-control-2', 14, d14, prom14)),
        ('cold-on-step1', 14, dcold1, prom14, (usym1, 'BAND-NOT-40-BIT', 1),
         ('cold2022-control', 14, dcold2, prom14)),
    ]
    ok = True
    # quux itself refuses PROM 2002's .mcr on revision 13: its section 6 says 14
    rc, pc, out = quux(run, where, 'prom-file-rev13', 13, d2, prom14, stop)
    refused = rc != 0 and 'section 6 says hardware revision 14' in out
    ok &= refused
    run.record('  guard prom-file-rev13: quux %s PROM 2002\'s file on revision 13 (exit %d)'
               % ('refuses' if refused else 'DOES NOT REFUSE', rc))
    symfiles = [usym2, usym1, psym14, psym13]
    for name, rev, d, prom, (sym, label, off), (cname, crev, cd, cprom) in cases:
        want = symbol(sym, label) + off
        rc, pc, _ = quux(run, where, name, rev, d, prom, stop)
        fired = pc == want
        rc2, pc2, _ = quux(run, where, cname, crev, cd, cprom, stop)
        # the control: the machine ran, left the PROM and is not at the
        # guard's halt
        ran = pc2 is not None and pc2 != want and pc2 < 0o36000
        ok &= fired and ran
        run.record('  guard %s: %s (halted at %s, want %s+%d = %o); control %s: %s (at %s)' % (
            name, 'fires' if fired else 'DOES NOT FIRE', label_of(symfiles, sym, pc),
            label, off, want, cname, 'runs past it' if ran else 'FAILED',
            label_of(symfiles, sym, pc2)))
    # the checkpoints: one written at each revision, resumed on the other
    for rev, other, d, prom in ((13, 14, d13, prom13), (14, 13, d2, prom14)):
        chk = os.path.join(work, 'r%d.chk' % rev)
        quux(run, where, 'checkpoint-%d-write' % rev, rev, d, prom,
             ['--stop-after', '20000000', '--checkpoint', chk])
        if not os.path.exists(chk):
            ok = False
            run.record('  guard checkpoint %d: no checkpoint written' % rev)
            continue
        rc, pc, out = quux(run, where, 'checkpoint-%d-on-%d' % (rev, other), other, d, None,
                           ['--resume', chk, '--stop-after', '1000000'])
        refused = rc != 0 and re.search(r'revision %d' % rev, out) is not None
        rc2, pc2, out2 = quux(run, where, 'checkpoint-%d-on-%d-control' % (rev, rev), rev, d, None,
                              ['--resume', chk, '--stop-after', '1000000'])
        ran = rc2 == 0 and pc2 is not None
        ok &= refused and ran
        run.record('  guard checkpoint %d on %d: %s (exit %d); control on %d: %s' % (
            rev, other, 'refused' if refused else 'NOT REFUSED', rc, rev,
            'resumes' if ran else 'FAILED (exit %d)' % rc2))
    shutil.rmtree(work, ignore_errors=True)
    return ok


# --------------------------------------------------------------------------
# The guards of contract G3 revision 15b, appendix A15b.1, for a route whose
# microcode and PROM are revision 15's (the route's default target since its
# machine moved to revision 16).  The pieces: the route's microcode and PROM
# 2002 for revision 15 (assembled), revision 14's microcode and PROM 2002 for
# revision 14 (the builder's, --builder-ubin and --builder-prom), revision
# 13's, System 2001's, with PROM 2001 (--previous-band, --previous-ubin).
#
#   prom15-file-rev14, prom15-file-rev13
#                  PROM 2002 for revision 15 given to quux on revision 14 and
#                  13: refused, naming the format and the revision, before
#                  the PROM runs (so its own first act, ERROR-NOT-REVISION-15,
#                  is not reached on muir)
#   prom14-file-rev15, prom13-file-rev15
#                  an old PROM, revision 14's and 2001, on revision 15:
#                  refused, naming the revision
#   disk14-rev15   a revision-14 disk (the builder's, microcode 2002 for
#                  revision 14) on revision 15 under PROM 2002 for 15: word 0
#                  is 6, not the format word: ERROR-MCR-FORMAT
#                  (control: the route's disk under it leaves the PROM)
#   disk15-rev14   the route's disk on revision 14 under PROM 2002 for 14:
#                  ERROR-MICROCODE-NOT-REVISION-14 (control: the builder's
#                  disk under it leaves the PROM)
#   disk15-rev13   the route's disk on revision 13 under PROM 2001:
#                  ERROR-BAD-SECTION-TYPE (control: System 2001's disk)
#   uc15-says-14   the route's microcode with its section 6 saying 14, on
#                  revision 15: ERROR-MICROCODE-NOT-REVISION-15 (A15b.7's
#                  halt; control: the route's disk)
#   band formats   A15b.1: revision 15 changes none, so C27's lines stand,
#                  under the route's microcode on revision 15 (band2010,
#                  band2011, band2012, band2001, bitmap-missing, bitmap-size)
#                  and under revision 14's on 14 (step2-on-step1,
#                  cold-on-step1), with A14.13's controls
#   rev16-control  the route's disk under PROM 2002 for 15 on revision 16,
#                  the route's own machine: it leaves the PROM and runs on
#   checkpoint     a revision-14 checkpoint resumed on 15, and a revision-15
#                  one on 14: refused (control: each resumes on its own)
#
# Not checked here, since muir cannot reach it: PROM 2002 for revision 15's
# own halt on revision 14 (quux refuses the file first, prom15-file-rev14),
# and the revision-15 microcode loaded directly on revision 14 (no PROM loads
# it there: disk15-rev14).  The microcode's halt there, at MACHINE-NOT-QUUX-14
# below the assembly's revision (sys/ucadr/uc-cold-disk.lisp, RESET-DEVICES),
# is checked in the assembly instead: tools/assembler-check's rev15,
# revision_checks, reads the A constants its jumps compare with.

# the revision-15 .mcr's section 6 value, the hardware revision: the 11th
# 32-bit word (the format word, the number of sections, section 6's 8-word
# header, its one item)
SECTION_6_VALUE_15 = 10 * 4


def refused(run, where, name, rev, prom, wants):
    """quux given PROM on revision REV must refuse it, its message holding
    every text of WANTS; the machine never starts."""
    d = os.path.join(run.work, 'guards', 'empty.img')
    if not os.path.exists(d):
        with open(d, 'wb') as f:
            f.truncate(1 << 20)
    rc, pc, out = quux(run, where, name, rev, d, prom, ['--stop-after', '1'])
    ok = rc != 0 and all(w in out for w in wants)
    m = re.search(r'quux: --prom [^\n]*', out)
    run.record('  guard %s: quux %s it (exit %d): %s' % (
        name, 'refuses' if ok else 'DOES NOT REFUSE', rc, (m.group(0) if m else out.strip()[-160:])[:300]))
    return ok


def run_all_15(run):
    where = os.path.join(run.out, 'guards')
    os.makedirs(where, exist_ok=True)
    work = os.path.join(run.work, 'guards')
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work)
    if not (run.a.previous_band and run.a.previous_ubin and run.a.builder_prom):
        raise SystemExit('guards: --previous-band, --previous-ubin (System 2001\'s) and --builder-prom are needed')
    ub, bub, pub = run.ubin, run.a.builder_ubin, run.a.previous_ubin
    prom15, prom14, prom13 = (os.path.join(ub, 'promh.mcr'), run.a.builder_prom,
                              os.path.join(pub, 'promh.mcr'))
    uc15, uc14, uc13 = (os.path.join(d, 'ucadr.mcr') for d in (ub, bub, pub))
    if open(uc15, 'rb').read(4) != FORMAT_WORD_15 or open(prom15, 'rb').read(4) != FORMAT_WORD_15:
        raise SystemExit('guards: %s and %s are not both revision 15\'s .mcr' % (uc15, prom15))
    band4_lod = os.path.join(work, 'band4.lod')
    run.read_part(os.path.join(run.bands, 'band4.img'), 'LOD1', band4_lod)

    def current_band(disk, dest):
        img = os.path.join(work, 'copy.img')
        run.raw_copy(disk, img)
        cur = [p for p in run.gpt(img) if p[5] and p[4] >> 48 & 1]
        run.read_part(img, cur[0][1].split()[0], dest)
        os.unlink(img)
        return dest
    band14_lod = current_band(run.a.builder, os.path.join(work, 'band14.lod'))
    band13_lod = current_band(run.a.previous_band, os.path.join(work, 'band13.lod'))
    cold2 = os.path.join(run.work, 'cold-3.img')
    fmt2, valid2 = run.band_header(os.path.join(run.bands, 'band4.img'),
                                   run.part(os.path.join(run.bands, 'band4.img'), 'LOD1')[2])
    with open(band4_lod, 'rb') as f:
        f.seek(5 * 1024 + 5 * 30)
        bitmap = int.from_bytes(f.read(4), 'little')
    run.record('  guards (A15b.1): band4 format %o, valid %d words, mark bitmap at band page %d'
               % (fmt2, valid2, bitmap))
    # the route's microcode with its section 6 saying 14
    body = bytearray(open(uc15, 'rb').read())
    if body[SECTION_6_VALUE_15:SECTION_6_VALUE_15 + 4] != (15).to_bytes(4, 'little'):
        raise SystemExit('guards: %s: no 15 at section 6\'s item' % uc15)
    body[SECTION_6_VALUE_15:SECTION_6_VALUE_15 + 4] = (14).to_bytes(4, 'little')
    uc15_says_14 = os.path.join(work, 'ucadr-says-14.mcr')
    open(uc15_says_14, 'wb').write(bytes(body))

    def disk(name, mcr, lod):
        d = os.path.join(work, name + '.img')
        run.make_disk(d, mcr, {'LOD1': lod})
        return d
    d15 = disk('d15', uc15, band4_lod)
    d14 = disk('d14', uc14, band14_lod)
    d13 = disk('d13', uc13, band13_lod)
    d15says14 = disk('d15says14', uc15_says_14, band4_lod)
    d2010 = disk('d2010', uc15, band14_lod)
    d2011 = disk('d2011', uc15, patched(band14_lod, os.path.join(work, 'b2011.lod'), {8: 0o2011}))
    d2012 = disk('d2012', uc15, patched(band14_lod, os.path.join(work, 'b2012.lod'), {8: 0o2012}))
    dband13 = disk('dband13', uc15, band13_lod)
    dmissing = disk('dmissing', uc15, patched(band4_lod, os.path.join(work, 'bmissing.lod'), {30: 0}))
    dsize = disk('dsize', uc15, patched(band4_lod, os.path.join(work, 'bsize.lod'), {30: bitmap + 1}))
    d2on1 = disk('d2on1', uc14, band4_lod)
    dcold1 = disk('dcold1', uc14, cold2)
    dcold2 = disk('dcold2', uc15, cold2)
    psym15, psym14, psym13 = (os.path.join(d, 'promh.sym') for d in (ub, bub, pub))
    usym15, usym14 = os.path.join(ub, 'ucadr.sym'), os.path.join(bub, 'ucadr.sym')
    stop = ['--stop-after', str(CYCLES)]
    ok = True
    # quux refuses a PROM file for another revision before the PROM runs
    ok &= refused(run, where, 'prom15-file-rev14', 14, prom15,
                  ('a revision-15 .mcr', 'for hardware revision 15', 'this is revision 14'))
    ok &= refused(run, where, 'prom15-file-rev13', 13, prom15,
                  ('a revision-15 .mcr', 'for hardware revision 15', 'this is revision 13'))
    ok &= refused(run, where, 'prom14-file-rev15', 15, prom14,
                  ('a file for hardware revision 14', 'this is revision 15'))
    ok &= refused(run, where, 'prom13-file-rev15', 15, prom13,
                  ('a file for revision 13 or below', 'this is revision 15'))
    cases = [
        # name, revision, disk, prom, the halt (sym, label, offset), control
        ('disk14-rev15', 15, d14, prom15, (psym15, 'ERROR-MCR-FORMAT', 0),
         ('disk15-rev15-control', 15, d15, prom15)),
        ('disk15-rev14', 14, d15, prom14, (psym14, 'ERROR-MICROCODE-NOT-REVISION-14', 0),
         ('disk14-rev14-control', 14, d14, prom14)),
        ('disk15-rev13', 13, d15, prom13, (psym13, 'ERROR-BAD-SECTION-TYPE', 0),
         ('disk13-rev13-control', 13, d13, prom13)),
        ('uc15-says-14', 15, d15says14, prom15, (psym15, 'ERROR-MICROCODE-NOT-REVISION-15', 0),
         ('disk15-rev15-control-2', 15, d15, prom15)),
        ('band2010', 15, d2010, prom15, (usym15, 'BAND-NOT-GENERATIONAL', 1),
         ('band2010-on-rev14-control', 14, d14, prom14)),
        ('band2011', 15, d2011, prom15, (usym15, 'BAND-NOT-GENERATIONAL', 1),
         ('band2020-control', 15, d15, prom15)),
        ('band2012', 15, d2012, prom15, (usym15, 'BAND-NOT-GENERATIONAL', 1),
         ('band2020-control-2', 15, d15, prom15)),
        ('band2001', 15, dband13, prom15, (usym15, 'BAND-NOT-REVISION-14', 1),
         ('band2020-control-3', 15, d15, prom15)),
        ('bitmap-missing', 15, dmissing, prom15, (usym15, 'MARK-BITMAP-MISSING', 1),
         ('band2020-control-4', 15, d15, prom15)),
        ('bitmap-size', 15, dsize, prom15, (usym15, 'MARK-BITMAP-WRONG-SIZE', 1),
         ('band2020-control-5', 15, d15, prom15)),
        ('step2-on-rev14', 14, d2on1, prom14, (usym14, 'BAND-NOT-40-BIT', 1),
         ('band2010-on-rev14-control-2', 14, d14, prom14)),
        ('cold-on-rev14', 14, dcold1, prom14, (usym14, 'BAND-NOT-40-BIT', 1),
         ('cold2022-control', 15, dcold2, prom15)),
    ]
    symfiles = [usym15, usym14, psym15, psym14, psym13]
    for name, rev, d, prom, (sym, label, off), (cname, crev, cd, cprom) in cases:
        want = symbol(sym, label) + off
        rc, pc, _ = quux(run, where, name, rev, d, prom, stop)
        fired = pc == want
        rc2, pc2, _ = quux(run, where, cname, crev, cd, cprom, stop)
        # the control: the machine ran, left the PROM and is not at the
        # guard's halt
        ran = pc2 is not None and pc2 != want and pc2 < 0o36000
        ok &= fired and ran
        run.record('  guard %s: %s (halted at %s, want %s+%d = %o); control %s: %s (at %s)' % (
            name, 'fires' if fired else 'DOES NOT FIRE', label_of(symfiles, sym, pc),
            label, off, want, cname, 'runs past it' if ran else 'FAILED',
            label_of(symfiles, sym, pc2)))
    # the route's own machine, revision 16, runs the route's disk
    rc, pc, _ = quux(run, where, 'rev16-control', 16, d15, prom15, stop)
    ran = pc is not None and pc < 0o36000
    ok &= ran
    run.record('  guard rev16-control: the route\'s disk on revision 16 %s (at %s)'
               % ('runs' if ran else 'FAILED', label_of(symfiles, usym15, pc)))
    # the checkpoints: one written at each revision, resumed on the other
    for rev, other, d, prom in ((14, 15, d14, prom14), (15, 14, d15, prom15)):
        chk = os.path.join(work, 'r%d.chk' % rev)
        quux(run, where, 'checkpoint-%d-write' % rev, rev, d, prom,
             ['--stop-after', '20000000', '--checkpoint', chk])
        if not os.path.exists(chk):
            ok = False
            run.record('  guard checkpoint %d: no checkpoint written' % rev)
            continue
        rc, pc, out = quux(run, where, 'checkpoint-%d-on-%d' % (rev, other), other, d, None,
                           ['--resume', chk, '--stop-after', '1000000'])
        refused_ = rc != 0 and re.search(r'revision %d' % rev, out) is not None
        rc2, pc2, out2 = quux(run, where, 'checkpoint-%d-on-%d-control' % (rev, rev), rev, d, None,
                              ['--resume', chk, '--stop-after', '1000000'])
        ran = rc2 == 0 and pc2 is not None
        ok &= refused_ and ran
        run.record('  guard checkpoint %d on %d: %s (exit %d); control on %d: %s' % (
            rev, other, 'refused' if refused_ else 'NOT REFUSED', rc, rev,
            'resumes' if ran else 'FAILED (exit %d)' % rc2))
    shutil.rmtree(work, ignore_errors=True)
    return ok
