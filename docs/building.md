# Building the system from source

This is how a new world is built from the tree: compile the sources, make a cold load, boot it, load the rest of the system and save a band. It follows the tree's own code, and each claim cites a file and line.

**Status:** the procedure below was verified end to end on 2026-09-16, against a tree based on LM-3's System 304. It has since re-based on System 100, and the same build has not yet been run on it. The stages, the forms and the traps are the system's own and do not depend on the base; the line citations and the file list do, and are being checked as the build is repeated. The three source faults below are present in System 100 at the same places. The system compiled its whole tree, built a cold load, booted it, loaded the world through MINI and the file protocol, and saved a band that boots and answers.

| Step | Result |
|---|---|
| Readtables, SYSTEM, ZWEI, cold-load builder | 281 compiled files; SYSTEM took 6511 s |
| Cold load onto LOD3 | built, boots |
| `QLD` | inner system and site files over MINI, then the rest over FILE |
| Object-use analysis | 10 minutes 35 seconds |
| Size of the finished world | 20614 blocks |
| Saved band | LOD5, "Exp 1000.0", boots and answers |

## Bootstrapping on the System 100 base

This tree is System 100's, and a world of the same lineage is the right thing
to compile it with. LM-3 publishes one: the `system-100-0` release, a pack
image with a checksum, whose band is "Exp 100.0" on LOD2 with microcode 323 in
MCR1. Fetch it, copy it somewhere of your own --- a file service pointed at a
fetched tree will write into it --- and boot that.

**Chaos addresses.** That band's routing table holds 96 subnets
(`network/chaos/chsncp.lisp`, before the change here), so it cannot run on subnet
376 or any subnet from 96 up: it traps as the network starts. Bootstrap on
subnet 6, where the release's own host table already expects a file host at
`3060` and a Lisp Machine at `3050`. Run the server as OZ at 3060 and the
machine at 3050, and the stock band knows OZ without a site edit. The band this system
builds has the larger table and can then move to 376.

**Pointing it at the tree.** No site file is needed to compile, only the
translations, which can be typed:

```lisp
(login "LISPM" "OZ" t)
(fs:set-logical-pathname-host "SYS" :physical-host "OZ"
  :translations '(("SITE;" "//site//") ("*; *; *;" "//sys//*//*//*//")
                  ("*; *;" "//sys//*//*//") ("*;" "//sys//*//")))
```

Every slash is doubled because the TELNET listener reads traditional syntax.

**There is no SYSTEM-MACROS here.** That system is a System 30x addition; this
base does not define it, and asking for it gets "LOAD could not find any file
related to SYS: SITE; SYSTEM-MACROS SYSTEM". The job it did --- compiling
SYSTEM's definition files before anything tries to load them --- is done by
hand instead, in the order SYSTEM's own ALLDEFS module lists them
(`sys/sysdcl.lisp:10-16`):

```lisp
(qc-file "SYS: SYS2; DEFMAC LISP")   (qc-file "SYS: SYS2; STRUCT LISP")
(qc-file "SYS: SYS2; LMMAC LISP")    (qc-file "SYS: SYS2; SETF LISP")
(qc-file "SYS: EH; ERRMAC LISP")     (qc-file "SYS: SYS; TYPES LISP")
```

**Then the systems**, with the version left where it is:

```lisp
(make-system 'system :recompile :noload :noconfirm :nowarn :no-increment-patch)
```

**`:NOWARN` rather than `:DEFAULTED-BATCH`.** Both stop the build asking
questions, but they are not the same thing. `:NOWARN` (`sys2/maksys.lisp:474`)
sets four variables and opens no file: `INHIBIT-FDEFINE-WARNINGS` to
`:JUST-WARN`, more-processing off, batch mode on, and `*QUERY-TYPE*` to
`:NOCONFIRM`. `:DEFAULTED-BATCH` (`:482`) does all that *and* writes a compiler
warnings database to the login user's home directory on the file server ---
`/lispm/cwarns.lisp` for user LISPM. If the server has no such directory to
write into, the build stops at once with "Access to file denied", which is what
happened here on the first attempt; a server that reports it differently says
"Directory not found" instead. `:BATCH` implies `:NOWARN` (`:1564`), not the
other way round.

So either give the server a writable home directory for the user, or ask for
`:NOWARN` and do without the database --- which this repository ignores anyway.

## The stages

A world cannot be built from nothing, so each stage runs on the one before.

1. **Compile.** A running band compiles every source file into a QFASL file.
2. **Make a cold load.** The cold-load builder, running in the old world, lays a minimal world word by word onto an empty partition.
3. **Boot the cold load.** It has a reader, an evaluator, a fasloader and MINI, but no compiler, window system or FILE client.
4. **Load the rest.** `SI:QLD` fetches the inner system through MINI, turns on the network and FILE, and loads everything else with `MAKE-SYSTEM`.
5. **Save.** `DISK-SAVE` writes the finished world to a partition, which then boots like any band.

## What is needed

- **A running band** to compile with, such as a 1000.0 band.
- **A file server for `SYS:`** that serves both FILE and MINI. ozd does.
- **A site.** The tree has no `site/` directory, and the build loads `SYS: SITE; SITE`, `LMLOCS`, `HSTTBL` and `SYS TRANSLATIONS` (`sys/sysdcl.lisp:598-605`). They must be compiled for the site first, with `(make-system 'site :compile :noload :noconfirm)`.
- **The translations file must survive the traditional readtable.** A cold load reads it with `MINI-READFILE` (`cold/mini.lisp:319`), which ignores the file's attribute list, so it is read in traditional syntax whatever the file says. There a slash escapes the next character. A file whose targets are Unix paths must therefore double every slash and name no readtable, or the cold load stops with "End of file ... in the middle of the list". MIT's own site file never met this: its targets are TOPS-20 paths with no slashes. This is metebalci/muir-sys issue 9.
- **A free partition for the cold load,** and a larger one for the saved world (step 7).
- **The console,** for steps 5 and 6. The TELNET server is not part of a cold load.

Every session that reads or writes files must log in first, for example with `(login "LISPM" t)`.

## 1. Compile the readtables

The standard readtables are not compiled by the Lisp compiler. `io/rdtbl.lisp` signals an error if it is compiled or loaded (`io/rdtbl.lisp:5-6`). The readtable compiler `SI:RTC-FILE` reads it and writes its QFASL file (`io/rtc.lisp:847-858`).

The readtable compiler is in no system (`sys/sysdcl.lisp` does not name `IO; RTC`), and a 1000.0 band does not have it loaded: `(fboundp 'si:rtc-file)` is `NIL`. So compile and load it first:

```lisp
(qc-file-load "SYS: IO; RTC LISP")
(si:rtc-file "SYS: IO; RDTBL LISP")
(si:rtc-file "SYS: IO; CRDTBL LISP")
```

The cold-load builder loads both QFASL files specially (`cold/coldut.lisp:1244-1247`), and `SYSTEM-INTERNALS` only loads them (`sys/sysdcl.lisp:122`, `:126`).

## 2. Compile the systems

`SYSTEM` is the whole system except ZWEI (`sys/sysdcl.lisp:6-43`). ZWEI is compiled on its own (`sys/sysdcl.lisp:229`), and QLD loads it only when asked.

```lisp
(make-system 'system :recompile :noconfirm :defaulted-batch)
(make-system 'zwei :recompile :noconfirm :defaulted-batch)
```

- `:RECOMPILE` compiles every file even when its QFASL is newer (`sys2/maksys.lisp:466-468`).
- `:NOCONFIRM` asks nothing (`sys2/maksys.lisp:432`).
- `:DEFAULTED-BATCH` writes the compiler's warnings to the system's warnings file instead of the screen, and asks nothing (`sys2/maksys.lisp:502-521`). For `SYSTEM` that is `SYS: PATCH; SYSTEM-CWARNS LISP` (`sys/sysdcl.lisp:10`). The tracked `patch/cwarns-*.lisp` files come from upstream's last full build, by ams on 2023-03-22, which made `SYSTEM-INTERNALS`, then ZWEI, then COLD.

**Loading while compiling.** Without `:NOLOAD`, each new file is loaded into the compiling world as it is compiled, which changes that world as it goes. With `:NOLOAD`, every file is compiled against the definitions the band already has. That is safe only when the band was built from nearly the same sources. For the fork point it is: trunk at 1af7716f24 differs from the System 304 release by 5 commits in 4 files, none of them a definition file or `sys/sysdcl.lisp`. So it compiles with:

```lisp
(make-system 'system-macros :recompile :noload :noconfirm)
(make-system 'system :recompile :noload :noconfirm :defaulted-batch)
(make-system 'zwei :recompile :noload :noconfirm :defaulted-batch)
```

**`:NOLOAD` still loads definition files.** It removes only the top-level load steps (`sys2/maksys.lisp:452-456`). A load that another step depends on still happens, such as SYSTEM's `(:DO-COMPONENTS (:FASLOAD ALLDEFS))` (`sys/sysdcl.lisp:43`) or `(:COMPILE-LOAD MAIN (:FASLOAD DEFS))` in the component systems. On the first try, SYSTEM loaded `SYS: SYS2; DEFMAC QFASL` before compiling anything, and stopped with "File not found". So `SYSTEM-MACROS` (`sys/sysdcl.lisp:610-619`), which compiles exactly SYSTEM's six definition files and depends on nothing, goes first. It runs without `:DEFAULTED-BATCH` because it names no warnings file, and that keyword would then use the user's home directory. The definition files that are loaded come from the band's own sources, and `:DEFAULTED-BATCH` turns redefinition questions into warnings.

**Pace.** On muir's micro engine, `SYS: IO; DISK`, 2161 lines, compiled in 77 seconds of wall time. the first SYSTEM compile took 6511 seconds, about an hour and 49 minutes, and wrote 150 compiled files.

**Expected warnings.** The warnings database names 62 undefined functions. Most belong to systems that SYSTEM does not include, such as the CADR debugger, PRESS, FED, the IP code and Converse, and are harmless. Sixteen are functions that nothing in the tree defines, in Peek, the mouse code, `SYS; QMISC` and `SYS; QFCTNS`; that is issue 3.

**The world runs out of address space.** A long compile consumes areas and regions, and the world holds 255 of them (`SIZE-OF-AREA-ARRAYS`, `cold/qcom.lisp:803`, a base-8 file). The first build compiled all of SYSTEM and 24 files of ZWEI before the console began warning "Address space low!", counting down from 37 regions to 1, and the compile then stopped with `TRAP 5033 (REGION-TABLE-OVERFLOW)` inside `MAKE-SYMBOL`. Nothing is lost: the compiled files are already written. Reboot the machine and continue with `:COMPILE` instead of `:RECOMPILE`, which skips the files whose compiled form is newer than their source. Expect to reboot once or twice during a full build.

**Resuming needs the interrupted file compiled by hand.** `:COMPILE` decides what is out of date by reading the compiled file's property list (`SI::FILE-NEWER-THAN-INSTALLED-P` through `SI::SYSTEM-GET-FILE-PROPERTY-LIST`), and a missing compiled file signals "File not found" rather than meaning "compile it". The file the trap interrupted has no compiled form, so the resumed build stops on it at once. Compile the missing files directly first, then let `MAKE-SYSTEM` finish:

```lisp
(dolist (f '("DIRED" "BDIRED")) (qc-file (format nil "SYS: ZWEI; ~A LISP" f)))
(make-system 'zwei :compile :noload :noconfirm :defaulted-batch)
```

Which files are missing can be read off the system's module list in `sys/sysdcl.lisp` against the compiled files present.

**The version number rises.** Compiling a patchable system increments its major version, because `(:PATCHABLE ...)` includes that step (`sys2/maksys.lisp:1788-1789`). SYSTEM went from 1000 to 1001 and wrote `patch/system-1001.patch-directory`; ZWEI went from 130 to 131 and wrote `zwei/patch/zwei-131.patch-directory`. A build also rewrites the tracked warnings files and patch directories of the systems it makes. Pass `:NO-INCREMENT-PATCH` (`sys2/maksys.lisp:472-473`) to keep the number as it is.

## 3. Build the cold-load builder

```lisp
(make-system 'cold :compile :noconfirm)
```

The `COLD` system (`cold/coldpk.lisp:57-64`) compiles and loads `COLD; COLDUT` and `COLDLD`, and loads the cold-load parameters from `COLD; QCOM` and `QDEFS`. It keeps the new world's symbols in its own package, so the new world may differ incompatibly from the old one (`cold/coldpk.lisp:9-24`).

**MINI's server address is fixed when `COLD; MINI` is compiled.** It is the Chaos address of the host that `SYS:` translates to at that moment (`cold/mini.lisp:26-34`). So step 2 must run with `SYS:` on the file server that the cold load will read from.

A quick check before making the cold load: the server's Chaos address appears in `cold/mini.qfasl` as a 16-bit word, low byte first. For a server at octal 177201, the bytes are `81 fe` at an even offset. The first build found it there, and found neither System 304's server address, octal 4403, nor System 100's, octal 3060. The machine's own address also appears; MINI replaces that routing address with the server's when both are on one subnet (`cold/mini.lisp:69-70`). A byte search suggests the address rather than proving it.

## 4. Make the cold load

```lisp
(cold:make-cold "LOD3")
```

The symbol cannot be read before the package exists, so in a world where COLD has not been loaded yet, either run the COLD system first or call it as `(funcall (intern "MAKE-COLD" "COLD") "LOD3")`. A form naming a package that does not exist stops at a reader error, and over TELNET the session then waits at that prompt.

The COLD system has the same resume trap as the others: `COLD; COLDUT` and `COLD; COLDLD` must be compiled by hand with `qc-file` before `(make-system 'cold :compile :noconfirm)` will run, since it reads their compiled files' properties.

**Run it at the console, not over TELNET.** `MAKE-COLD` confirms before writing the partition, through `FQUERY` with `:TYPE :READLINE` (`io/disk.lisp:989`, `io1/fquery.lisp:407`), and a line read over TELNET takes a trap and leaves the session in the error handler; that is issue 4. At the console the question is answered from the keyboard. It is asked twice when the form is typed rather than evaluated from a script: the Return that ends the form is read as an empty answer, and the question is asked again. Answer the second one with `Yes` and Return. muir serves its console over RFB, so a viewer, or a small client sending key events, can type the form and the answer while a TELNET session stays open for anything that only prints.

**Keep typed forms short.** A cold load's console has a small wired keyboard buffer, and a long line is silently truncated: a 130-character form typed at about twelve characters a second stopped echoing after sixty characters, and the reader simply waited for the rest. Type short forms, or type slowly, and read back what the screen echoed before pressing Return.

`MAKE-COLD` (`cold/coldut.lisp:1194-1218`) marks the partition "cold-incomplete", builds the areas, NIL and T, loads the files of `COLD-LOAD-FILE-LIST` (`sys/sysdcl.lisp:499-523`) and the readtables, and records the physical file names MINI will ask for (`cold/coldut.lisp:1249-1256`). It then sets the partition's comment to "cold" and the date. The partition must not be the one the running world was booted from.

## 5. Boot the cold load

Make the cold load's partition the current band, then boot. With the machine stopped, muir's `diskpack` does it. The same stop is the moment to make room for the finished world, since both are label edits:

```
diskpack pack.img "delete LOD6"
diskpack pack.img "modify LOD5 48450"
diskpack pack.img "current 3"
```

`show` then marks the current band with an asterisk. On the pack this left LOD3 holding the cold load, LOD5 holding 48450 blocks for the save, and LOD9 still holding the old world to fall back on.

`SET-CURRENT-BAND` is exported (`cold/global.lisp:1507`) and belongs to the disk-label editor (`io/disk.lisp:16`), but its definition was not found in `io/`, `sys/` or `sys2/`.

The cold load greets with "Lisp Machine cold load environment, beware!" (`sys/ltop.lisp:338`).

**Boot it cold.** muir-fpga measured that a warm boot of a System 304 band halts in the microcode about 20 milliseconds in, while a cold boot is clean. This has not been checked here. Restarting muir is a cold boot. A cold boot clears the screen only after the band has been read, about a minute in.

### One generated file QLD needs

`SYS: SYS; UCINIT QFASL` is not source and is not carried here: the micro
assembler writes it (`sys/mlap.lisp:553`, `MA-WRITE-MCLAP-PROPS`), as it writes
everything in `ubin/`. But `QLD` loads it while making System, after the
compiler and `COLD; DEFMIC` and `DOCMIC`, and stops with

```
>>ERROR: File not found for SYS: SYS; UCINIT QFASL
```

if it is absent. So a fresh clone cannot finish a `QLD` until the microcode has
been assembled once, or the file is taken from a release. Assembling the
microcode is the honest answer and is not done here yet; until then the file
comes from the System 100 release, whose copy is 2,844 bytes.

## 6. Load the rest

At the cold load's console:

```lisp
(si:qld)
```

`QLD` (`sys/ltop.lisp:653-700`):

1. loads the inner system through MINI (`:660`), then the pathname and FILE code (`:664`);
2. reads the site files, reinitializes the network, and logs in as LISPM on the host of `SYS:`;
3. loads `MAKSYS`, `PATCH` and `SYSDCL`, then runs `MAKE-SYSTEM` on `System`;
4. asks for a list of further systems to load, such as `(zwei)`;
5. prints the partition size the world will need, from `ESTIMATE-DUMP-SIZE` (`sys/qmisc.lisp:1279`), and the disk label, and says "OK, now do a DISK-SAVE".

**MINI trouble.** Run ozd with `--log-mini`: it logs each file MINI reads, and each it refuses with the reason. A refusal is where the cold load stops. Every name MINI asks for must exist at that exact path, case included, under the file server's roots.

**A reboot within three minutes fails once.** After every boot, the cold load's first MINI connection uses index 1, and MINI never closes it. If the cold load is booted again within three minutes of its last MINI connection, ozd still holds that connection and discards the new request as a duplicate. The first `(si:qld)` then fails with "RFC fail" after about 20 seconds. Trying again works, because it uses the next index.

## The halt this build met, in QLD

On the first build the cold load booted and `QLD` read its whole inner system and the site files through MINI, then the machine stopped itself with nothing printed. Three runs halted with identical registers: the program counter three instructions into `TRANS-REALLY-TRAP` (`ucadr/uc-transporter.lisp:143`) and the last microinstruction at `ILLOP`.

**It is an unbound variable read while traps are disabled.** The cold-boot path clears `M-TRAP-ENABLE` (`ucadr/uc-cold-disk.lisp:644`, "MACROCODE WILL TURN ON TRAPS WHEN READY"), and macrocode turns traps on only in `LISP-REINITIALIZE` (`sys/ltop.lisp:329-331`). Until then `TRAP` becomes `ILLOP`, which halts (`ucadr/uc-interrupt.lisp:9`, `ucadr/uc-cadr.lisp:88`).

**Naming the variable, without a debugger.** The trapping Q is in `MD`, whose data type is `DTP-NULL` and whose pointer is the symbol itself. A cold load's band is uncompressed, so virtual address N is word N of the partition, and reading the band at that address gives the symbol header and its print name. Here it was `SCHEDULER-STACK-GROUP`, declared with no value at `sys2/prodef.lisp:22` and set only by `PROCESS-INITIALIZE` (`sys2/proces.lisp:1068`).

**A work-around at the console, before `(si:qld)`:**

```lisp
(setq si:scheduler-stack-group nil)
```

It stops the halt, because a `DEFVAR` with no value does not overwrite a bound variable. In that run the load then went further but still failed: the transporter trap was signalled as "Microcode bug: no error-table entry", since a cold load has not loaded `SYS: UBIN; UCADR TBL` yet (`eh/eh.lisp:2324`), and the Chaos code then failed at interrupt level trying to answer a packet. The fix is to declare the variable with a value and recompile that file, which a cold load reads through MINI rather than carrying inside it. This is metebalci/muir-sys issue 6, and this system has made that change: `sys2/prodef.lisp` now declares the variable `NIL`, with a comment saying why.

**With that fixed, a cold load gets much further and stops again.** It loads the inner system, the pathname and file code and the site files, runs `LISP-REINITIALIZE` as far as "Turning off INHIBIT-SCHEDULING-FLAG", and then breaks with "Unknown stream operation", which is MINI's own message (`cold/mini.lisp:232`, `:268`) for an operation its streams do not implement. The reader is in the file-system package at that point. The message does not name the operation, which is metebalci/muir-sys issue 7.

**Reading the failure from the file server's log.** When the world stops receipting, the server keeps retransmitting its unreceipted packet every half second, and a crippled world answers with a lost-packet message, which the server logs as the connection closing. So the last file read before that line names the file the band died in, which is a second witness to what the console says.

## What had to be changed in the sources

The system does not rebuild itself as it stands. These are the changes here to the tree, each with a comment in the source saying why, and each filed as an issue so that upstream can take it or refuse it.

| File | Change | Issue |
|---|---|---|
| `sys2/prodef.lisp:22` | `SCHEDULER-STACK-GROUP` is declared `NIL` instead of being left unbound | 6 |
| `cold/mini.lisp` | the "Unknown stream operation" message names the operation | 7 |
| `cold/mini.lisp` | MINI's two streams answer `:SEND-IF-HANDLES` instead of signalling | 7 |

**Why the first is needed.** A cold load runs with traps disabled until `LISP-REINITIALIZE` enables them, and `PROCESS-WAIT` reads that variable while deciding how to wait. Read unbound in that window, the reference traps, `TRAP` becomes `ILLOP` and the machine halts with nothing printed. Declaring it `NIL` costs nothing, since `PROCESS-INITIALIZE` still sets the real stack group later.

**Why the second is needed.** Without it the cold load stops at "Unknown stream operation" without saying which one, which is the only fact needed to go further.

**Why the third is needed.** `:SEND-IF-HANDLES` means "send this message only if you handle it". A flavor instance answers it through `VANILLA-FLAVOR`; MINI's streams are closures and answered nothing, so an optional message became a fatal error. `IO; STREAM:64` asks any stream for its byte size that way, which is where a cold load met it.

Everything else in this document is procedure rather than a change to the sources: compiling the definition files first, rebooting when the world runs out of address space, compiling by hand the file a trap interrupted, typing at the console because line reads over TELNET trap, and merging partitions to make room for the saved world.

## 7. Save the band

```lisp
(si:disk-save "LOD9")
```

`DISK-SAVE` (`sys/qmisc.lisp:1157`) asks for confirmation unless its second argument is true. The partition must hold at least the size QLD printed. A full 1000.0 world needs 25144 blocks, more than a standard LOD partition of 24225 blocks.

With the machine stopped, `diskpack` merges two neighbouring free partitions: delete the second, then grow the first into its blocks. On a standard pack, LOD5 and LOD6 are adjacent and LOD9 follows them:

```
diskpack pack.img "delete LOD6"
diskpack pack.img "modify LOD5 48450"
```

LOD5 then holds 48450 blocks and ends exactly where LOD9 begins, so no other partition moves. This was tried on a copy of the development pack: the label came out as expected, and LOD2 and LOD9 stayed byte for byte the same.

After saving, the microcode boots the saved world itself. Make that partition the current band so later boots use it.

## Checks

- The cold load's partition comment says "cold" and the date.
- `QLD` ends with "OK, now do a DISK-SAVE".
- The saved band boots and prints the herald with its system versions.
- Over TELNET, `(+ 1 2)` returns `3`.
