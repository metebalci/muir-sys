# System 2002

What QUUX's next release changes from System 2001. It is in progress on
`main`: each change is recorded here as it is made. Every change to a source
file carries a comment in that file saying why.

- **The system number is 2002** (`patch/system.patch-directory`,
  `patch/system-2002.patch-directory`), now that System 2001 is released,
  so that no band built from `main` calls itself 2001.
- **Microcode 2002 and boot PROM 2002.** System 2002, microcode 2002 and PROM
  2002 are released together, on QUUX's revision 15; revision 14, a step
  toward it, is an internal milestone and is never released on its own (Mete,
  2026-10-04). As for 2000 and 2001, the version is not in the sources but
  given to the assembler (`ua:version-number` and the output's version for
  `UCADR`, the version asked for `PROMH`), so no source changed for it.
