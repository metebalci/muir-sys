#!/usr/bin/env python3
"""check3.py's control: plant two faults in copies of a cold load's image and
show that check3.py fails on each: NIL's header made a DTP-FIX, and a letter of
NIL's print name changed.

Usage: plant3.py IMAGE WORD-BITS PAGE-SIZE
The copies are written beside IMAGE and removed.  Exits 1 unless check3.py
fails on both.
"""
import os
import subprocess
import sys

img, bits, page = sys.argv[1], int(sys.argv[2]), sys.argv[3]
nb = 5 if bits == 40 else 4
pb = 32 if bits == 40 else 25
tb = 6 if bits == 40 else 5
data = open(img, 'rb').read()
w0 = int.from_bytes(data[0:nb], 'little')
pname = w0 & ((1 << pb) - 1)
plants = []
# NIL's header's data type from DTP-SYMBOL-HEADER (4) to DTP-FIX (5)
w = (w0 & ~(((1 << tb) - 1) << pb)) | (5 << pb)
b1 = bytearray(data)
b1[0:nb] = w.to_bytes(nb, 'little')
plants.append(('NIL header type', b1))
# the second character of NIL's print name, I made J
b2 = bytearray(data)
b2[(pname + 1) * nb + 1] = ord('J')
plants.append(('NIL print name', b2))
here = os.path.dirname(os.path.abspath(__file__))
caught = 0
for i, (name, b) in enumerate(plants):
    path = '%s.planted%d' % (img, i)
    try:
        open(path, 'wb').write(b)
        r = subprocess.run([sys.executable, os.path.join(here, 'check3.py'), path, str(bits), page],
                           capture_output=True, text=True)
    finally:
        os.remove(path)
    lines = [l for l in r.stdout.splitlines() if l.startswith('FAIL') or l.startswith('RESULT')]
    print('planted %s: exit %d; %s' % (name, r.returncode, ' | '.join(lines)))
    caught += r.returncode == 1
print('RESULT %s (%d of %d planted faults caught)'
      % ('PASS' if caught == len(plants) else 'FAIL', caught, len(plants)))
sys.exit(0 if caught == len(plants) else 1)
