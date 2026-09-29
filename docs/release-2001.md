# System 2001

What QUUX's next release changes from System 2000. It is in progress on
`main`: each change is recorded here as it is made. Every change to a source
file carries a comment in that file saying why.

- **The system number is 2001** (`patch/system.patch-directory`,
  `patch/system-2001.patch-directory`), now that System 2000 is released,
  so that no band built from `main` calls itself 2000.
- **Microcode 2001 and boot PROM 2001**, the numbers of the first 40-bit
  QUUX, revision 13 (Mete, 2026-09-28). As for 2000, the version is not in
  the sources but given to the assembler (`ua:version-number` and the
  output's version for `UCADR`, the version asked for `PROMH`), so no
  source changed for it. This supersedes Q12's rule (its section 1.1) that
  the microcode and the PROM keep 2000 until a changed one is released.
