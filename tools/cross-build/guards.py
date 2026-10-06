"""The guards of contract G3 revision 14, appendix A14.13, for tools/cross-build's
step guards: each mix of revision, PROM, microcode and band that must stop is
booted and must halt where the guard says; each has a control, the nearest
right mix, which must not halt there.  A run is quux with --stop-after, whose
last "PC n" line is where the machine stood; a PROM's halt (JUMP HALT-CONS)
shows the label itself, the microcode's (CALL ILLOP) the word after it.

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
"""
import os
import re
import shutil
import subprocess
import time

CYCLES = 600000000


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


def run_all(run):
    where = os.path.join(run.out, 'guards')
    os.makedirs(where, exist_ok=True)
    work = os.path.join(run.work, 'guards')
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work)
    ub, bub = run.ubin, run.a.builder_ubin
    prom14 = os.path.join(ub, 'promh.mcr')
    # revision 13's PROM, 2001, as the builder's sys/ubin/ has it, so that its
    # halts are read from the .sym of the PROM that runs
    prom13 = os.path.join(bub, 'promh.mcr')
    uc14, uc13 = os.path.join(ub, 'ucadr.mcr'), os.path.join(bub, 'ucadr.mcr')
    band14 = os.path.join(run.bands, 'band4.img')
    # the bands' own partitions, read off their disks
    band14_lod = os.path.join(work, 'band14.lod')
    run.read_part(band14, 'LOD1', band14_lod)
    builder = os.path.join(work, 'builder.img')
    run.raw_copy(run.a.builder, builder)
    current = [p for p in run.gpt(builder) if p[5] and p[4] >> 48 & 1]
    band13_lod = os.path.join(work, 'band13.lod')
    run.read_part(builder, current[0][1].split()[0], band13_lod)
    os.unlink(builder)
    # microcode 2002 without its section 6, the first 16 bytes (code 6, start
    # 0, count 1, the revision)
    head = open(uc14, 'rb').read()
    if head[:4] != b'\x06\0\0\0':
        raise SystemExit('guards: %s does not open with section 6' % uc14)
    uc14_bare = os.path.join(work, 'ucadr-no-section-6.mcr')
    open(uc14_bare, 'wb').write(head[16:])
    # and PROM 2002 without its section 6, which quux would refuse on revision
    # 13 before the PROM ran: so that the PROM's own first act is seen
    phead = open(prom14, 'rb').read()
    prom14_bare = os.path.join(work, 'promh-no-section-6.mcr')
    open(prom14_bare, 'wb').write(phead[16:] if phead[:4] == b'\x06\0\0\0' else phead)

    def disk(name, mcr, lod):
        d = os.path.join(work, name + '.img')
        run.make_disk(d, mcr, {'LOD1': lod})
        return d
    d14 = disk('d14', uc14, band14_lod)
    d13 = disk('d13', uc13, band13_lod)
    d14uc13 = disk('d14uc13', uc13, band14_lod)
    dbare = disk('dbare', uc14_bare, band14_lod)
    dband13 = disk('dband13', uc14, band13_lod)
    psym14, psym13 = os.path.join(ub, 'promh.sym'), os.path.join(bub, 'promh.sym')
    usym14 = os.path.join(ub, 'ucadr.sym')
    stop = ['--stop-after', str(CYCLES)]
    cases = [
        # name, revision, disk, prom, the halt (sym, label, offset), control
        ('prom-rev13', 13, d14, prom14_bare, (psym14, 'ERROR-NOT-REVISION-14', 0),
         ('prom-rev14-control', 14, d14, prom14)),
        ('uc2001-rev14', 14, d14uc13, prom14, (psym14, 'ERROR-MICROCODE-NOT-REVISION-14', 0),
         ('uc2002-rev14-control', 14, d14, prom14)),
        ('disk14-rev13', 13, d14, prom13, (psym13, 'ERROR-BAD-SECTION-TYPE', 0),
         ('disk13-rev13-control', 13, d13, prom13)),
        ('uc2002-rev13', 13, dbare, prom13, (usym14, 'MACHINE-NOT-QUUX-14', 1),
         ('uc2002-rev14-control-2', 14, d14, prom14)),
        ('band2001', 14, dband13, prom14, (usym14, 'BAND-NOT-REVISION-14', 1),
         ('band2002-control', 14, d14, prom14)),
    ]
    ok = True
    # quux itself refuses PROM 2002's .mcr on revision 13: its section 6 says 14
    rc, pc, out = quux(run, where, 'prom-file-rev13', 13, d14, prom14, stop)
    refused = rc != 0 and 'section 6 says hardware revision 14' in out
    ok &= refused
    run.record('  guard prom-file-rev13: quux %s PROM 2002\'s file on revision 13 (exit %d)'
               % ('refuses' if refused else 'DOES NOT REFUSE', rc))
    symfiles = [usym14, psym14, psym13]
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
    for rev, other, d, prom in ((13, 14, d13, prom13), (14, 13, d14, prom14)):
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
