# System 1004

What the CADR's next release changes from System 1003. It is in progress on
the `cadr` branch: each change is recorded here as it is made. `main` is
QUUX's system, numbered from 2000; what this branch takes from it is a bug fix,
a change that needs no QUUX hardware, or a feature Mete chose for the CADR.
Every change to a source file carries a comment in that file saying why.

- **The system number is 1004** (`sys/patch/system.patch-directory`,
  `sys/patch/system-1004.patch-directory`), now that System 1003 is released,
  so that no band built from this branch calls itself 1003.
- **`SET-MAR` and `CLEAR-MAR` reach the page holding the range's last word**
  (`map-mar-pages`, `sys/sys/qmisc.lisp:808-826`; `clear-mar`, `:838-848`;
  `set-mar`, `:860-875`). Both stepped `#o200` words from the range's first
  word and stopped past its last: on the CADR's 256-word pages, when the last
  word lay in the first 127 words of a later page, the last step could fall
  in the page before, depending on the first word modulo 128, so that page
  never got the MAR's status and a write there was not trapped. Both now
  visit each page from the first word's to the last word's once, the pages
  counted from the difference of the two pages' addresses and the address
  stepped by `%pointer-plus`; `set-mar` takes the last word's address by
  `%pointer-plus` too, a fixnum also from 2^24 up. Fixed on `main` in the
  same way. `tools/system-check`'s new check `mar-range` sets the MAR over a
  range from 28 words below a page boundary to 50 past it: System 1003 fails
  its third case (a write of the last word does not trap) and passes the
  other three, the controls; with the change all four pass.
