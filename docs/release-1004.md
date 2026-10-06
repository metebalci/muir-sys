# System 1004

What the CADR's next release changes from System 1003. It is in progress on
the `cadr` branch: each change is recorded here as it is made. `main` is
QUUX's system, numbered from 2000; what this branch takes from it is a bug fix,
a change that needs no QUUX hardware, or a feature Mete chose for the CADR.
Every change to a source file carries a comment in that file saying why.

- **The system number is 1004** (`sys/patch/system.patch-directory`,
  `sys/patch/system-1004.patch-directory`), now that System 1003 is released,
  so that no band built from this branch calls itself 1003.
