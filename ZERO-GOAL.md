# ZERO-GOAL.md — reduce whim-vim to an embeddable editor core

`whim-vim.c` is an embedded editor: one static binary that expects nothing to have
been installed for it. **`zero-vim.c` is what is left when the editor stops being a
program at all, and becomes a component a host program runs.**

```
slim-vim.c = F(upstream@sha)          SLIM-GOAL.md
whim-vim.c = G(slim-vim.c)            WHIM-GOAL.md
zero-vim.c = H(whim-vim.c)            this document
```

The three pipelines are the same construct — a phase is a function of the tree it
is handed, memoized in three tiers — and share the driver, the boundaries, the
oracle, the synthesiser and every harness. What differs is what the phases remove,
and what each pipeline's behaviour is measured against.

**This document is iterative, and so far it has seventeen phases.** Phase 0 is the
seed, phase 1 is a compiler flag, phase 2 is the first cut in the source — the first
piece of *a component, not a program* — phase 3 changes no source at all: it
replaces the instrument every later phase is measured with; phase 4 removes Ex mode,
phase 5 leaves the command line as `+{command}` and `-T {term}`, and phases 6 to 13
are *no filesystem* on request: the editor loses every way to write a file, then
every way to read one, then every way to name another one to edit, then the
machinery that read the bytes — which by then nothing could reach — then the
buffer's own name, with the last three questions the core asked the filesystem on
its own initiative, then the refusal that asked whether the text had been saved,
which by then had no remedy to offer, then the option rows that reported settings
nothing read, and finally the two `FILE *` that had never been opened. After
thirteen the core has no `open`, no `stat`, no stdio stream and no fourth
descriptor: it can read, write, close and dup fds 0, 1 and 2 and nothing else.
Phases 14 and 15 are *no musl dependencies* on request, for the half of that charter
item which is pure computation: twenty-eight libc functions — the strings and memory
blocks, the character classes, the numbers, the sort — defined in the file as local
`static` ones instead of asked of a host, which takes `nm -u` from 61 to 33 and is the
first change in the pipeline that makes the file *longer*. Phase 16 then removes the
six `#include`s that nothing names any more, eighteen directives to twelve, and it is
the first phase in any of the three pipelines to change a directive count.
Phases
are added one at a time, each on the user's own
request, and each is written into this document, into `pipes/` and into
`pipes/zero.delta` and `pipes/zero.stages` when it is added — never in advance.

## The charter

Zero vim is an **embeddable editor core**: a library-shaped piece of C that a host
links in or translates, rather than a process that owns a terminal and a disk. What
the concept is, as the user has stated it, and in no particular order of phases:

- **A component, not a program.** `main()` is demoted. A small host launcher,
  `editor.c`, holds what remains of the C library calls — the part that talks to an
  operating system — and `zero-vim.c` is what it drives.
- **No musl dependencies** in `zero-vim.c` itself. Whatever the core still needs
  from the world, the host provides.
- **The screen and all visual editing stay.** This is still vim to look at and to
  type into; what goes is the editor's reach outside itself.
- **No filesystem access.** Reading and writing files is the host's business, not
  the core's.
- **The text representation moves, later, from lines to a structure.** A tree that
  mirrors an abstract syntax tree, with the line view that every motion, command and
  redraw expects simulated on top of it.
- **`zero-vim.c` stays pure C without a preprocessor** — it inherited 18 directives
  from `whim-vim.c` and is down to **twelve**, every one an `#include` of a system
  header, and **no phase adds a `#define`, a conditional or an `#include`** — because a
  following repository transpiles it to the JVM, and every construct in the file is one
  that translation has to understand. **A phase may remove one**, and phase 16 is the
  first that did. That permission is stated here because the old reading — a count the
  pipeline preserves — is exactly why phase 13 measured that removing three of them was
  free and declined, writing *"the count stays 18"* into its own program. Nothing is
  ever added back: the twelve reach `select`, `gettimeofday`, `fd_set`, `struct
  timeval` and every `*_MAX` only through musl's own `sys/param.h` →
  `sys/resource.h` → `sys/time.h` → `sys/select.h`, which is recorded as a fragility
  rather than repaired with three more directives.

None of that is done by phase 0, and none of it is a commitment to an order. Each
item becomes a phase, or several, when one is asked for.

## What is measured

The same two numbers as `WHIM-GOAL.md`, reported by `make score` beside slim-vim and
whim-vim: **bytes to store** and **libc symbols still referenced**. For zero the
second is the direct measure of the charter — "no musl dependencies" is that count
reaching the set the launcher, and not the core, supplies.

## The rules

1. **Removal is computed, not listed.** Cut the entry points and let the sweep find
   what becomes unreachable (`WHIM-GOAL.md`, *The sweep*). The same six kinds, the
   same tools.
2. **Every phase states its delta, in advance, as a check.** `pipes/zero.delta` is
   the list — an Ex command by name, `case:` for a screen case, `argv:` for a
   command line, `term-moved`, `pty-moved`, and the two dimensions `screen-moved`
   and `stderr-moved` — in `pipes/whim.delta`'s grammar, and
   `tools/zerodelta.sh --phase N` shows exactly that set moved and no more. "Some
   cases differ" is not a check, and neither is a dimension declared that nothing
   touched: `tools/zcompare.py` refuses a `-moved` token whose dimension did not
   move.
3. **The delta is from whim-vim, not from slim-vim, and it is cumulative.** Zero's
   behaviour is compared with `.reference/zero-baselines`, which phase 0 records
   from the committed `whim-vim.c` built with whim's own compile line — the
   **input's** behaviour, frozen. Everything whim removed is therefore already in
   them, `pipes/zero.delta` starts empty, and the lines up to phase N are the whole
   difference from the input at N, as whim's are from slim. A phase declares what
   *it* changes, and every phase after it is held to that line too. Recording them from the pipeline's input is
   legitimate, and is not the mistake `CLAUDE.md` warns about: that is a pipeline
   re-recording its baselines from its own current binary, which agrees by
   construction. `whim-vim.c` is immutable to this pipeline, and phase 0 also proves
   the recording is whim-vim's (see *Phase 0*).
4. **`zero-vim.c` is produced from the committed `whim-vim.c`**, not from a pass of
   the other pipeline. `make zero-vim` needs no clone, no network and no agent, and
   the memoize key is `whim-vim.c`'s digest and the implementation's. `whim.sha`
   records the `whim-vim.c` a committed `zero-vim.c` was produced from, as
   `slim.sha` does for whim.
5. **Phases are programs, not agents.** A phase is `pipes/zero<N>.sh`, or an edit and
   a check, `pipes/zero<N>-edit.sh` and `pipes/zero<N>-check.sh`, run by
   `tools/phaserun.sh` in stages with one sweep between the edits and the checks,
   exactly as whim's are. The tier-1 agent is the fallback the construct has, not a
   way to write a phase.
6. **Stages and packages are declared and checked.** `pipes/zero.stages` holds the
   phase list (`phases`), the schedule (`stage`, `need`, `apart`, read by
   `tools/stages.sh`) and the concept view (`package`, `uses`, read by
   `tools/packages.sh`), with `pipes/whim.stages`' meanings. `make zero-verify` and
   `make zero-tip` run `tools/packages.sh zero --check` first.
7. **`zero-vim.c` carries no comments.** It starts with none, because `whim-vim.c`
   has none, and no phase writes one.
8. **The compile line is `gcc -O0 -fno-stack-protector -static -no-pie -s`.**
   `-no-pie` is the one difference the seed introduces: whim and slim keep `-O0
   -static -s`, a static-PIE, and zero's binary is an ordinary static executable —
   `readelf -h` says `EXEC`, with no `INTERP`, no dynamic section and no relocations
   — because a core with nothing left to relocate is one a host can place without a
   loader. Every further flag is **a phase of its own**, and a phase changes the
   flags by editing the boundary's `zero/Makefile`, never `tools/templates/zero.mk`,
   which is the pipeline's input and part of r0's input digest.
   `-fno-stack-protector` is phase 1.
9. **`tools/` is shared, and gated.** A change to a tool a whim or slim phase names
   must leave `make whim-verify` (every stage boundary reproduces) and `make
   slim-verify` (12 of 12) passing, and should move no whim or slim cache key.
   `tools/implhash.sh` output for every whim unit, whim edit and slim phase is the
   check; prefer a zero-only tool (`tools/zerodelta.sh`) or a value in
   `tools/pipeline.sh` to an edit of a hashed tool. **Never write a zero tool's path
   into `tools/phaserun.sh`**: every whim edit's key reads what that file names.

## Adding a phase

Only on request, and one at a time:

1. Write the program: `pipes/zero<N>-edit.sh <work> <state>` and
   `pipes/zero<N>-check.sh <work> <state>`, as `WHIM-GOAL.md`'s *Adding a phase*
   describes for whim.
2. **Declare its delta** in `pipes/zero.delta`, before running it.
3. **Place it**: add N to the `phases` line of `pipes/zero.stages` — the phase list
   lives there and not in `tools/pipeline.sh`, so adding a zero phase moves no whim
   key — then a `stage` line for it (or widen the last stage), any `need` and `apart`
   it has, and put it in a `package` with its `uses` lines. `tools/stages.sh zero
   --check` and `tools/packages.sh zero --check` must be silent.
4. Write its `## Phase N — ...` section here.
5. `make zero-tip` runs the last stage and records it; `make zero-verify` then proves
   every stage from the recorded one before it.

## Phase 0 — seed, and prove the copy is a copy

`zero-vim.c` starts as a byte-for-byte copy of the committed `whim-vim.c`, and the
phase is `pipes/zero0.sh`, one whole program. Four things, each depending on the one
before:

1. **The seed is the input.** `cmp` against `whim-vim.c`; the boundary digest is the
   same file's.
2. **It builds, absolutely static.** `make -C zero` with `tools/templates/zero.mk`,
   `gcc -O0 -static -no-pie -s`, and then `readelf`: the type is `EXEC`, there is no
   `INTERP`, no dynamic section and no relocation. Measured on this input: 894,088
   bytes, where whim's static-PIE of the same source is 955,976 bytes, `DYN`, with a
   dynamic section and 1,986 relative relocations.
3. **The zero baselines are whim-vim's.** `whim-vim.c` is built in a scratch
   directory with `tools/templates/whim.mk` — whim's compile line — and the three
   harnesses whim's delta reads, `behaviour.py`, `exsweep.py` and `termcheck.py`,
   record it three times; the runs must be identical. If `.reference/zero-baselines`
   exists the recording must equal it, and it is never overwritten: a difference
   means a harness or the input changed, and has to be named. If it does not exist,
   it is written.
4. **zero-vim does exactly what whim-vim does.** `tools/zerodelta.sh zero/zero-vim
   zero/zero-vim.c --phase 0`, with `pipes/zero.delta` empty, requires no behaviour
   case, no Ex command and not the terminal table to move — so `-no-pie` changed
   nothing a harness sees. And `tools/whimdelta.sh --phase 82` on the same binary,
   against slim-vim's baselines, shows whim's whole declared delta still holds: the
   frozen whim behaviour is intact under the new compile line.

A tier-3 hit on this phase records nothing, because the phase does not run. So
`zero.mk` checks afterwards: `zero-pass`, and `zero-phase-N` — and through them
`zero-repass`, `zero-specpass`, `zero-tip` and the `zero-vim.c` rule — run
`zero-baselines-check` once the chain has reached its boundary, and it refuses unless
`.reference/zero-baselines` holds a non-empty `behaviour/`, `ref-exsweep.txt` and
`ref-term.txt`, naming the fix: `rm -rf .cache/r0 && make zero-phase-0`. The check
lives in `zero.mk`, which no implementation digest reads, so it moves no key.

## Phase 1 — the stack protector goes

`pipes/zero1.sh`, one whole program: there is no source edit, so there is nothing
for a sweep to do and a split phase would pay for one. `zero-vim.c` comes out of it
byte for byte as it went in, and what changes is one line of `zero/Makefile`:

```make
CFLAGS  = -O0                       ->  CFLAGS  = -O0 -fno-stack-protector
```

**Why.** gcc 15 on this machine enables `-fstack-protector-strong` by default, so
every function with a local array or an address-taken local gets a canary and the
object calls `__stack_chk_fail`. That is a symbol the core would have to be given by
its host, for a check the editor does not ask for — and *what it must be given* is
the number `ZERO-GOAL.md` measures. Measured on this input: the undefined symbols of
`gcc -c` on `zero-vim.c` go from **80 to 79**, the one that goes is
`__stack_chk_fail` and nothing comes, and the binary goes from **894,088 to 869,512
bytes**.

**Where the flag lives.** In the boundary — the tree a phase transforms — and not in
`tools/templates/zero.mk`, which is the pipeline's *input*: the input rule copies it
into `zero/Makefile`, and editing it would move r0's input digest and invalidate
phase 0's recording. The product rule in `zero.mk` cannot read `zero/`, which does
not exist in a checkout that only builds the committed `zero-vim.c`, so it states the
same flags once as `ZEROCFLAGS` and `ZEROLDFLAGS` — and `zero-pass` refuses to copy
`zero-vim.c` out when they differ from the `CFLAGS` and `LDFLAGS` of the makefile the
last phase left. The two statements cannot drift without a pass saying so; proven by
running `make zero-pass ZEROCFLAGS=-O0`, which refuses and names both. `make score`
passes both variables to `tools/score.sh`, which applies them to the object it counts
symbols in as well as to the binary — the count is otherwise taken with the default
CFLAGS, and would still show `__stack_chk_fail`.

**What the phase proves, in order:** the makefile has exactly one `CFLAGS` line and
it does not already carry the flag; the **old** flags do reference
`__stack_chk_fail` and the new ones do not — both measured with `nm -u` on unstripped
objects of the same source, so the check is one that can fail, and a compiler whose
default changed is reported rather than silently passing; `zero-vim.c` is unchanged;
the binary is still absolutely static (`EXEC`, no `INTERP`, no dynamic section, no
relocation); and `tools/zerodelta.sh --phase 1` sees no behaviour case, no Ex command
and no terminal-table row move against whim-vim's baselines. `pipes/zero.delta`
declares nothing for it, because a canary is code around the locals and not
behaviour.

It is `stage 1` and `package build` in `pipes/zero.stages`, with one `uses`:
`build:1 seed:0 mechanical`, because `zerodelta.sh` refuses without the
`.reference/zero-baselines` phase 0 records. It runs in 9 seconds.

## Phase 2 — the core stops diagnosing its own terminal

`pipes/zero2-edit.sh` and `pipes/zero2-check.sh`, `stage 2`, `package terminal`. The
first phase that cuts source, and the first piece of *a component, not a program*: a
host hands the core its input and output, and whether either is a terminal is the
host's business. Upstream's answer is to complain and then wait —

```
Vim: Warning: Output is not to a terminal
Vim: Warning: Input is not from a terminal
```

— on stderr, `out_flush()`, `exit(1)` if `--ttyfail` was given, and then
`ui_delay(2005L, TRUE)` so that a person can read them. All of it is
`check_tty()`'s second branch, and all of it goes, with the `--ttyfail` flag: its
`case '-'` test, the `parmp->tty_fail = TRUE` it set, and the `tty_fail` field of
`mparm_T`. `--ttyfail` becomes what any other unknown word is, `ME_UNKNOWN_OPTION`
through `mainerr()`.

**The pause was looked for, not assumed.** There are nine `ui_delay()` call sites in
`zero-vim.c` and exactly one is the warnings': 2005 ms, inside the branch that
printed them, under upstream's `scriptin[0] == NULL` ("do not pause while a script
is being read", which has nothing left to condition). The other eight are each a
different pause — 3001 ms for `W14: List of file names overflow`, 1002 ms for the
`'readonly'` warning, the 1000 ms slices of `ui_delay`'s own wait loop, 1003 and
3003 in `wait_return()`, 1006 in `check_for_delay()`, and `p_mat`'s two in
`showmatch()` — and none is reached from `check_tty()`. **Measured: the pause is
2,005 ms once, for both warnings together, not one per warning.**

**What stays, and the reader that forces each.** The `exmode_active` branch —
`if (!input_isatty) silent_mode = TRUE` — because Ex mode is a later phase, and it is
also what keeps `mch_input_isatty()` called. `stdout_isatty`, read outside `main` by
`out_redir = !stdout_isatty` in the message layer, which keeps its one assignment and
so `mch_check_win()` and that function's `isatty(1)`. `want_full_screen`, whose
second reader, `params.want_full_screen && !silent_mode`, survives the branch that
went. **So all five `isatty()` calls remain and the libc surface does not move:
79 undefined symbols before and after, the same set.** Folding an `isatty` caller is
a phase of its own if it is ever one; this phase is the warnings, the pause and the
flag. `check_tty()` then reads nothing from its argument, so it takes `void` and its
one caller drops the `&params` — the alternative being
`__attribute__((unused))` on a parameter nothing will read again.

**The delta is none, and every harness here is blind to it — so the phase's own
probes are the check.** `behaviour.py` and `exsweep.py` run the editor `-e -s`:
`exmode_active` is set before `check_tty()`, the first branch takes it, and the
warnings were never on any recorded stderr (grepped: the only baseline line
mentioning a terminal is `exsweep`'s `SKIPPED (hands over the terminal)`).
`termcheck.py` drives a real pty, where both streams *are* terminals. A delta of
"none" from a harness that cannot see the code proves nothing, so
`pipes/zero2-check.sh` measures the removed behaviour directly, in both directions:
the edit part first builds the binary the phase was **handed**, from the boundary's
own makefile flags, and every probe requires the old binary to do the thing and the
new one not to.

What they measured, `TERM=xterm`, stdin a file of `ihello world<Esc>:q!`, stdout a
file:

| | input binary | after |
| --- | --- | --- |
| stderr | 85 bytes, both warnings | **0 bytes** |
| elapsed | 2,010 ms | **5 ms** |
| stdout, the escape stream | 2,108 bytes | 2,108 bytes, **byte-identical** |
| exit | 0 | 0 |

`--ttyfail` exits 1 under both — the old binary because the flag asked it to, the new
one because the flag is gone — so the status is not the check and what `mainerr()`
prints is: `Unknown option argument: "--ttyfail"`, present after and absent before.
A bare `--` still ends the options, `+cmd` and `-T dumb` still work, each with the
same result from both binaries. And a real terminal is untouched: one `ptyrun`
session that types text, asks `:set term?` and `:wq` gives the same status, the same
file and the same answer either side — as do the 19 pty sessions `termcheck.py` runs
inside the declared delta.

**Measured, and what did not move.** 86,614 → 86,586 lines. The sweep found nothing
at all — no function, prototype, type, variable, field or enumerator — so the cut
orphaned nothing, which is what the kept readers above predicted. In the plain
object `.text` goes 654,846 → 654,576 bytes and `.rodata` 17,785 → 17,689, the two
strings and the branch; the stripped static binary is **869,512 bytes either side**,
the shrinkage absorbed by alignment padding. The phase runs in 28 seconds, 3.6 of
them the extra compile of the input binary its probes need. Its boundary is
`74ca3e1ffeb8`, and `make zero-verify` recomputes all three.

One `uses` line: `terminal:2 seed:0 mechanical`, for phase 1's reason —
`tools/zerodelta.sh` refuses without the `.reference/zero-baselines` phase 0 records,
and "none" is checked against them.

It does not run `tools/create_cmdidxs.py --check`, which every whim edit of the
command table ends with: the derived first-two-letters index went with the table whim
reduced, there are no `ex_cmdidxs.h` banners left in `whim-vim.c`, and the tool
raises rather than reporting nothing.

## Phase 3 — the instrument becomes the screen

**No source change at all**: `r3`'s `zero-vim.c` is `r2`'s byte for byte, and the
phase asserts it — the two boundaries have the same digest, `74ca3e1ffeb8`. What
changes is how every later phase is measured, and it had to change before those
phases are written rather than after.

### Why the old instrument stops working

`tools/behaviour.py` ends every case with `+w! <file>` and reads the file back;
`tools/exsweep.py` runs a command on a file and records the exit status and the
files left in the directory. Zero's editor is on its way to having **no file to
write, no file to read and no stream to print on** (`ZERO-PLAN.md`), so both stop
being instruments the moment the phases they exist to measure land. Waiting until
then would mean removing the filesystem and the means of noticing it in one step.

### What replaces it

`tools/zrecord.sh`: **keystrokes in on stdin, escape sequences out on stdout, and
a screen rebuilt from them**. No pty, no settle time, no ANSI stripping and no
Press-ENTER hazard; the terminal is 80x24 by construction because the window-size
ioctl fails on a pipe. Five parts, and a recording is all five:

| | what it is | how big |
| --- | --- | --- |
| `screen/` | `tools/zcases.py`: 102 keystroke cases, one record each | 141 KB |
| `ref-excmds.txt` | `tools/zexcmds.py`: every Ex command name typed at `:` | 111 rows |
| `ref-argv.txt` | `tools/zargv.py`: every command line the parser may see | 30 rows |
| `ref-pty.txt` | `tools/zpty.py`: what only a real terminal shows | 4 scenarios |
| `ref-term.txt` | `tools/ztermcheck.py`: whim's `termcheck.py` with no file argument (phase 5) | 19 terminals |

**One screen per redraw, taken from the bytes.** The editor hides the cursor while
it draws and shows it when the screen is settled, so `\x1b[?25h` is a step boundary
visible in the stream. That is what makes the message line recordable: the keys
that quit the editor wipe it, and with only the final screen every row of the
command sweep read `~`. It is also why the sweep is now a *message-level* record
where the file-based one was an exit status — retiring `:write` will move
`E32: No file name` to `E492`, which the old sweep could not have seen, both being
exit 1.

**A case types its own text under `'paste'`.** Nothing can load a file, so the seed
is typed — and typing is subject to the compiled-in `ai si et sts=4` and the four
mappings. `+set paste` (on the command line, before the first screen) turns exactly
those off, and a typed `:set nopaste` puts them back before the case's real editing,
which happens under the real defaults. `'paste'` and `+{command}` therefore survive
every zero phase by decision, and are named as such wherever a later phase might
take them.

**Two things are scrubbed, padded to the width they replace**: undo's
"1 second ago", which comes from `time()`, and `mainerr()`'s version banner, which
carries `__DATE__`. The padding is not cosmetic — the screen is columns, and a
shorter replacement moved the ruler into a different one.

### The delta grammar grows two dimensions

`case:NAME`, a command name, `argv:NAME`, `term-moved` and `pty-moved` name one
record each. `screen-moved` and `stderr-moved` name a **dimension** of every
record: what the editor drew, and what it wrote to stderr. A dimension token
excludes that dimension from every comparison and is itself checked — a phase that
declares `screen-moved` and draws the same screens fails, which was proven by
declaring it here and watching `tools/zcompare.py` refuse. Everything outside the
declared dimension is still compared record by record.

### The baselines are the input's behaviour, and the delta is cumulative

`.reference/zero-baselines` is recorded by **phase 0** from `whim-vim.c` built with
whim's own compile line — three recordings that must be identical — and is compared,
never silently overwritten. So the difference a phase declares is the difference
from the **input**, and the lines up to phase N are the whole of it, exactly as
whim's are against slim's baselines.

That is why phase 3 makes phase 2's delta visible. Phase 2 removed the two "not to
a terminal" warnings and the two-second pause, and declared nothing, because every
old harness ran the editor `-e -s` or on a pty and could not see them. The new
instrument runs it on a pipe, which is precisely where they were printed:
**`2   stderr-moved`** is the line, and it is checked at r2 and at every boundary
after it. Measured: all 102 cases, 109 of the 111 command rows (`:stop` and
`:suspend` are skipped) and 13 of the 30 command lines differ in their stderr **and
in nothing else** — the screens, the stream digests, the exit statuses, the bells,
the pty scenarios and the terminal table are identical.

### What the phase proves

1. the tree is untouched — `zero-vim.c` in, `zero-vim.c` out, same sha;
2. it builds with the boundary's flags and is still `EXEC`, no `INTERP`, no
   dynamic section, no relocation;
3. **the instrument is deterministic**: three recordings of that binary, identical,
   *including the sha256 of every stdout stream* — stronger than "the screens
   agree", since a redraw that draws the same result differently moves the digest;
4. **the instrument can fail**: a scratch copy of the source with `do_addsub()`
   returning `FAIL` — `CLAUDE.md`'s canonical break — moves **exactly 11 of the 102
   cases**, the ten that increment or decrement plus `mb_incr`, and nothing else.
   A corpus that cannot fail is not evidence;
5. the declared delta holds (`tools/zerodelta.sh --phase 3`);
6. **the bridge still stands**: `tools/whimdelta.sh` on the same binary against
   slim-vim's baselines gives whim's whole declared delta, 489 commands and 11
   cases. The file-based harnesses are kept untouched — they are whim's and slim's,
   and they are the only recording the two pipelines share. Nothing zero does from
   here reads them.

### Measured

One recording is **5.1 s** (its parts run at once; the 102 cases alone are 0.5 s
against a binary with no startup pause and 2.4 s against whim-vim, which still has
one). The phase runs in **30 s**, phase 0 in **33 s** with its three recordings and
the baseline write, and the whole four-phase pass cold in **1 m 45 s**;
`make zero-verify` reproduces all four boundaries in **36 s** of wall time over
109 s of phases. The recording is 180 KB on disk. No whim or slim cache key moved:
all 107 — 13 whim stages, 82 whim edits, 12 slim phases — are identical to `main`'s.

It is `stage 3` and `package harness` in `pipes/zero.stages`, with two `uses`
lines: `harness:3 seed:0 mechanical`, because it is measured against the baselines
phase 0 records *in the shape phase 0 now records them*, and `harness:3 terminal:2
rationale`, because the delta it proves is phase 2's.

**The old recording had to be removed once, by hand.** The two shapes have no file
in common, so phase 0 names the old one rather than printing a diff of everything
against everything: `rm -rf .reference/zero-baselines && rm -rf .cache/r0 && make
zero-phase-0`. It refuses rather than overwriting, which is the property that makes
the baselines a reference at all.

**Removing it means removing it, and that was got wrong once.** The new recording
was written *into* the old directory rather than in place of it, so
`.reference/zero-baselines` kept `behaviour/` and `ref-exsweep.txt` beside
`screen/` — and phase 0's `diff -r` then reported two extras on every run and
refused, while the "old shape" branch above did not fire, `screen/` being present.
The two are the pre-phase-3 file-based recording and nothing records them now;
deleting them is what phase 0 asks for when it says *name which before removing*,
and it makes `make zero-verify` reproduce r0 again. Phase 5 is where that was
found, because it is the first phase whose gate ran every boundary from the
recorded one before it.

## Phase 4 — no streaming Ex

`pipes/zero4-edit.sh` and `pipes/zero4-check.sh`, `stage 4`, `package streams`. The
second cut, and the first that removes a *mode*. Ex mode is the arrangement a core
does not have: the editor takes stdin over, prints its own prompt, reads a line at a
time and writes the result back on stdout. Silent mode comes with it — the message
layer redirected into `printf()` and stdout buffered through `setvbuf()` — and both
are entered from the command line (`-e`, `-E`, `-s`, `-v`) or from the keyboard
(`Q`, `gQ`).

`do_exmode()` (96 lines), `getexmodeline()` (263) and `nv_exmode()` (12) go, the
four option cases go, and then `exmode_active` (49 mentions) and `silent_mode` (23)
are constantly FALSE and fold at every reader. **The two counts are the whole
argument and are asserted both ways**: 49 and 23 before, every use gone after, with
the nineteen identifiers that go with them — counted by `\b`, because
`pending_exmode_active` contains `exmode_active` and a plain substring count says
53.

**Every fold is counted and scoped to one function, because the polarity is not the
same at every site.** `if (exmode_active)` folds never; `if (!exmode_active)` folds
always; and `msg_start()`'s `if (exmode_active != EXMODE_NORMAL)` folds **always**,
because `0 != 1` is TRUE. That one sits among its opposites and reads exactly like
them, and getting it backwards would have given every message Ex mode's newline,
with nothing in the build to say so. Two other shapes needed care: `fold_never` on
an `if` rewrites the `else if` after it into an `if`, so `main_loop`'s next anchor
is written without the `else` it had a moment earlier; and `command_line_scan` has
two `if (exmode_active)`, so the four option cases go first or the counted fold
refuses — loudly, which is the point.

**Three functions are deleted by name rather than left to the sweep.** A function
whose address is taken is reachable as far as gcc is concerned: `getexmodeline` is
passed to `do_cmdline()` and compared with `getline_equal()`. Its last live
reference is one disjunct of `do_cmdline`'s 200-column `while` condition — miss it
and 263 lines survive silently. `nv_exmode` goes the same way, because an
`nv_cmds[]` row is a reference: **the `'Q'` row is repointed at `nv_error` and never
deleted**, a hole being what moves every key past it onto another key's handler.

**Six write-only leftovers go by hand**, because nothing sees them:
`ex_pressedreturn`, `ex_no_reprint` (seven writes), `ex_exitval`,
`previous_got_int`, `use_plus_cmd` and `exmode_was`. A file-scope static that is
assigned and never read draws no warning at all, and the locals draw
`-Wunused-but-set-variable`, which `tools/deadsweep.py` does not act on.
`main_loop`'s `noexmode` parameter and the `theend:` label it jumped to go with
them — an unused label *is* a warning, and `tools/phasecheck.sh` fails on it.

**`check_tty()` is deleted here, and that is a gap in the sweep worth naming.**
Folding its one remaining branch leaves `int input_isatty; input_isatty =
mch_input_isatty();` — set and never read, which is exactly the kind
`deadsweep.py` does not act on. Measured: the sweep reports `left alone 1` and
settles with the warning still there. So the function and its call in `main()` go by
name, and `mch_input_isatty()` — whose only caller it was — is what the sweep takes,
with the fifth `isatty()` call. **It is phase 2's cut as much as this one's**: phase
2 kept that branch deliberately, saying Ex mode was a later phase's, which is why
the manifest carries `uses streams:4 terminal:2 mechanical`. `ZERO-PLAN.md`'s table
gives `isatty` to P2; it arrives here.

**What stays, and the reader that forces each.** `getexline()`, because `:append`,
`:insert` and `:change` read their lines through it and not through the Ex-mode
reader. `exe_commands()`, because it runs the `+{command}` list every harness here
drives the editor with — only its last statement folds. And everything the argv
phase owns: `case NUL`'s `EDIT_STDIN` arm, `read_cmd_fd = 2`, `had_minmin`, the file
argument, `ME_TOO_MANY_ARGS` and its `main_errors[]` row, `case 'T'`. The check
names each of them.

### The declared delta, and the one the plan over-declared

Six records move, and every one is a way *in* to Ex mode: `case:key_Q`,
`case:key_gQ`, `argv:-e`, `argv:-E`, `argv:-e_-s`, `argv:-v`. The two keys drew
`Entering Ex mode.  Type "visual" to go to Normal mode.` and now beep once, from
`nv_error` and from `nv_g_cmd`'s `default: clearopbeep`; the command lines are
`mainerr(ME_UNKNOWN_OPTION)` like any other unknown letter.

**`-s` alone is not declared.** `case 's'` set silent mode only `if (exmode_active)`
and called `mainerr()` otherwise, so a bare `-s` was an unknown option *before* this
phase; measured, its record is byte-identical. `ZERO-PLAN.md`'s P3 row lists it.
Two of the four that are declared — `-e` and `-e -s` — differ only in stderr, which
`stderr-moved` already excuses everywhere; they are named anyway, because they are
ways into Ex mode and this is the phase that closes them.

### The probes, and why a delta is not enough here

The baselines are one recording of one binary, so `tools/zerodelta.sh` can say
"exactly these six moved" and cannot say "the old binary entered Ex mode". The check
says it, by running both: the binary the phase was **handed**, built by the edit
part from the boundary's own makefile flags, and the one it made. **29 probes, in
two halves** — six required to move and 23 required not to — each of the six also
required to show Ex mode, or an option the old parser accepted, on the *old* binary.
A probe that only looks at the new binary passes on a phase that did nothing.

The 23 are `-s` alone, six `+{command}` forms, `:append`/`:insert`/`:change`,
`:visual`/`:vi`/`:view`/`:ex` from Normal mode (whose Ex-mode escape this phase
folded away), bare `-`, `--`, `-- +q!`, one and two file arguments, the three `-T`
spellings and an ordinary edit. Each record is built the way `tools/zcases.py`
builds one and scrubbed the same way, because `mainerr()` prints the version banner
and two binaries built a minute apart disagree on `__DATE__` for a reason that is
not the editor's behaviour — which is precisely why `-s` reads as unchanged and
must.

Two pty sessions beside them: `Q`, `visual<CR>`, `<Esc>:q!` — Ex mode entered by the
old binary and by nothing now — and an editing session identical either side. **The
`<Esc>` is not decoration.** Without Ex mode those six letters are Normal-mode keys
that end in Insert mode, `:q!` is typed into the buffer, and the session runs to the
timeout and is killed: status 9, measured, and it looked like a broken harness.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 86,586 | **85,813** (−773) |
| functions | 1,867 | 1,862 |
| `nm -u` | 80 | **78** — `setvbuf`, `stdout`, nothing else |
| `isatty(` calls | 5 | **4**, and the symbol stays |
| binary | 869,512 | **861,288** |

Five functions: `do_exmode`, `getexmodeline`, `nv_exmode` and `check_tty` by name,
`mch_input_isatty` by the sweep — which is clean in two rounds and also takes the
three single-constant enums `EXMODE_NORMAL`, `EXMODE_VIM` and `BO_EX`, each with an
explicit value, so nothing renumbers. In the plain object `.text` goes 654,576 →
648,968 and `.rodata` 17,689 → 17,625. `stdout` was the file's only mention, and it
was `setvbuf`'s argument.

The phase is **81 s** cold and 51 s with its edit cached; its boundary is
`97a2ab4895e7`, and `make zero-verify` recomputes all five in 81 s of wall time over
191 s of phases. No whim or slim cache key moved: all 107 are identical to `main`'s.

Its placement carries one thing the schedule does not need yet and will:
`apart 2 4`. Phase 2's check runs both of its binaries with `-e -s` and requires
exit 0, which is how it proves `--`, `+cmd` and `-T` still work — and this phase
removes `-e`. Every zero phase is a stage of its own today, so the line is a
statement; it becomes a constraint the moment two of them share a sweep.

## Phase 5 — argv is `+{command}` and `-T {term}`

`pipes/zero5-edit.sh` and `pipes/zero5-check.sh`, `stage 5`, `package streams`. A
core is handed its buffer by a host, not by a shell. What phases 2 and 4 left of
`command_line_scan()` is five things — `+cmd`, `-T`, a bare `-`, `--` and a file
argument — and this phase takes the last three, which are exactly the three that
name a **file** or a **stream** to edit. Everything the parser does not recognise
is now what every other unknown word already was, `mainerr(ME_UNKNOWN_OPTION)`.

**The file-argument arm is replaced, not deleted**, and that is not tidiness: with
no `else` at all a bare word matches neither `+` nor `-`, `argv[0][argv_idx]` is
not NUL for any word of more than one character, and the `while` never advances.
Deleting it gives an infinite loop, not an error. What goes with it is
`parmp->edit_type = EDIT_FILE`, the `vim_strsave()` and the `buflist_add()` that
put the name in the buffer list. `case NUL` — the bare `-`, with `EDIT_STDIN` and
`read_cmd_fd = 2` — and `case '-'` — where `--` set `had_minmin` and made every
later word a file name — fall to `default:` instead. `--foo` reached
ME_UNKNOWN_OPTION from *inside* `case '-'` and reaches it from `default:` now, so
only `--` itself changes.

**`ME_TOO_MANY_ARGS` had exactly those two call sites**, so it goes with its row in
`main_errors[]` — and **the enumerator is the row index**, so the three after it
move down by one. That is the renumbering `CLAUDE.md` warns about, done on purpose:
the table and the enum are rewritten from **one parse of both**, which is what
makes the mapping a fact rather than two edits that agree, and the check compares
the DWARF enumerator values of the binary the phase was handed with the ones it
made. Measured: **1,327 in, 1,323 out** — `ME_TOO_MANY_ARGS` and the three `EDIT_*`
gone, `ME_ARG_MISSING` 2→1, `ME_GARBAGE` 3→2, `ME_EXTRA_CMD` 4→3, and **1,320
unmoved**. A wrong index here shows up nowhere else: the build is perfectly happy
with it, and `-Txterm` would simply start printing another message.

`main_errors[]` keeps a **sixth** row, `"Invalid argument for"`, which no
enumerator named before this phase either. It is whim's leftover, and this phase
removes the row an enumerator it removes points at and nothing else.

**What `params.edit_type` then is: EDIT_NONE, for ever**, because nothing assigns
it. Its two readers are in `vim_main2()` and their polarity is opposite — `==
EDIT_STDIN` folds never, taking `read_stdin()`'s only call with it, and `!=
EDIT_STDIN` folds always, leaving `newline_on_exit` under the two conditions that
were already there. The field, the three `EDIT_*` enumerators, `read_stdin()` and
`buflist_add()` are then what the **sweep** takes: `deadfields.py` for the field —
there is no `ml_recover()` in this file, so a struct is no longer a disk format —
`deadenums.py` for the enumerators, and `deadsweep.py` for the two functions. Two
rounds, 79 lines.

### Where the line is against the later phases

Three things this phase could have taken and did not, each asserted by a **count**
so that taking them would fail here rather than widen quietly:

* **`readfile()`'s stdin half** is the "nothing reads a byte" phase's
  (`ZERO-PLAN.md` P8). What goes here is the *function* `read_stdin()`, argv's
  entry point into that code; the 23 remaining mentions of the name are the
  **parameter** of `readfile()`, `read_buffer()` and `open_buffer()`, and the check
  requires exactly 23.
* **`read_cmd_fd`** keeps its definition and its twelve remaining mentions. Only
  the assignment was argv's; nothing writes it now, so it is 0 for ever and folding
  it belongs with stdin. A file-scope static that is read and never written draws
  no warning, so the sweep would not have touched it either way.
* **The buffer's name** is P9's. Nothing here touches `b_ffname`, `b_sfname` or
  `b_fname`: what goes is the one call that ever gave the startup buffer a name
  from argv. `create_windows()` already opens an unnamed buffer when argv named
  none — that is `tools/zargv.py`'s `(none)` row — so the startup path is the one
  that was always there.

**There is no `usage()` to leave alone.** A phase that removes options usually owes
the help text an apology; `grep -i usage zero-vim.c` finds nothing at all, whim
having removed it, and `--help` is already `Unknown option argument: "--help"` in
the baselines.

### The declared delta: six command lines, and nothing else

`argv:-`, `argv:--`, `argv:f.txt`, `argv:f.txt_g.txt`, `argv:+q!_f.txt` and
`argv:--_+q!` — six of `tools/zargv.py`'s 30 rows, every one a way of naming a file
or a stream:

* **`-` was the row that blocked.** The editor read the keystroke file itself as
  buffer text, closed fd 0, duped stderr and waited there for keys that never came;
  the baseline record is `blocked` and it cost the harness its timeout on every
  run. It is `Unknown option argument: "-"`, exit 1, now.
* **`f.txt` and `+q! f.txt`** opened a buffer and drew a screen; both are exit 1
  with an empty stream.
* **`--` and `-- +q!` disagreed with each other** in the baselines, because `+q!`
  after `--` was a *file name* rather than a command. They agree now, and that
  difference is the whole of what `--` did.
* **`f.txt g.txt` is declared although `stderr-moved` would absorb it**: it exited
  1 with an empty stream for `Too many edit arguments: "g.txt"` and exits 1 with an
  empty stream for `Unknown option argument: "f.txt"`. It is the two-file-argument
  row and this is the phase that removes file arguments, so the list says so rather
  than letting a dimension cover it — phase 4's reason for naming `-e`.

**Nothing else moves, and the corpus is the reason it cannot**: every one of the
102 screen cases seeds itself by *typing* under `'paste'`, so not one passes a file
argument. Measured: 102/102 cases, 111/111 Ex-command rows, the four pty scenarios
and all 24 other command lines identical — including every `+{command}` form and
all three `-T` spellings.

### The instrument this phase broke, and the one that replaced it

**`tools/termcheck.py` asks its question with a file argument.** It is whim's and
slim's, the one harness zero kept (phase 3), and it opens a three-line `f.txt` so
that the screen has something on it before `:set term? t_Co?`. From this boundary
that argument is an unknown option, the editor exits 1 before drawing, and **all
nineteen rows read `(none)`** — measured. That is the harness failing, not the
terminal table moving, and declaring `term-moved` for it would switch the terminal
table off for every phase after this one, which is the one thing a phase must not
buy its way out with.

So zero's recording now uses **`tools/ztermcheck.py`**: `termcheck.py` imported
with its `ask()` replaced and nothing else, so the terminal list, the environment
isolation, the settle ladder and the output format stay in one place and cannot
drift from whim's. Editing `termcheck.py` itself is what rule 9 forbids — it is
named by `tools/whimdelta.sh` and `tools/verify.sh`, so its bytes are in every whim
stage's key. **The swap is proven, not asserted**, in three places: the new tool
records `.reference/zero-baselines/ref-term.txt` byte for byte from the binary this
phase was *handed* (which still accepts a file argument, so both forms work on it),
the old tool records nineteen `(none)` rows from the one it *made*, and phase 0 —
which records from `whim-vim.c` three times and compares with the baselines —
reproduces `r0` unchanged under the new instrument. Only `tools/zrecord.sh` changed
to name it, which re-keyed zero's five earlier phases and **no whim or slim key**:
all 107 are identical to `main`'s.

### The probes, and why the delta is not enough

The baselines are one recording of one binary, so `tools/zerodelta.sh` can say
"exactly these six moved" and cannot say "the old binary opened the file". The
check says it, by running both — the binary the phase was **handed**, built by the
edit part from the boundary's own makefile flags, and the one it made. **22 probes,
six required to move and 16 required not to**, and each of the six is also required
to show the old behaviour on the *old* binary: a buffer drawn and exit 0 for
`f.txt`, `Too many edit arguments` for two of them, `blocked` for the bare `-`, and
`--` reading differently from `-- +q!`. Proven able to fail in both directions: run
with the old binary on both sides all six report *was to move and did not*, and
with the new binary on both sides they add *the input binary already refused it, so
this proves nothing*.

The 16 are `+`, `+q!`, `+set nu`, two `+{command}`s at once, **`+set paste`** with
typing under it — `'paste'` and `+cmd` are what the whole corpus is seeded with and
this is the phase that could have lost both — the three `-T` spellings and an
unknown terminal name, the four options that were already unknown, and an ordinary
keystroke edit. Two pty sessions beside them: `vim f.txt` on a real terminal, which
the old binary edits and the new one refuses with wait status 256, and an editing
session with no arguments, identical either side.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 85,813 | **85,734** (−79) |
| functions | 1,862 | 1,860 |
| enumerators (DWARF) | 1,327 | **1,323** |
| `nm -u`, zero's flags | 77 | **77**, the same set |
| `nm -u`, as `phasecheck.sh` counts it | 78 | 78 (the extra is `__stack_chk_fail`) |
| `.text` / `.rodata` of the plain object | 648,968 / 17,625 | 648,496 / 17,609 |
| binary | 861,288 | **861,288** |

**Nothing is freed, and that is the measurement rather than a disappointment**:
`read_stdin()`'s `close()` and `dup()` have other callers and `buflist_add()` names
no libc directly, so the undefined set is equal — stated as an equality, so a
symbol *arriving* would fail. The binary does not move either: 472 bytes of `.text`
and 16 of `.rodata` go, and alignment padding absorbs them, exactly as in phase 2.

The phase is **52 s** cold and 57 s under `make zero-verify`, which recomputes all
six boundaries in 80 s of wall time over 247 s of phases. A `make zero-repass` from
an empty zero cache ran the first five in **152 s** — 30, 12, 28, 31, 51 — and took
phase 5 from tier 3, so the whole pipeline cold is 204 s; every boundary matched
its recording. Its own is `d466c3b9245b`.

Its placement carries one new constraint, and it is measured rather than predicted:
**`apart 4 5`**. Phase 4's check names `EDIT_STDIN`, `read_cmd_fd = 2`,
`had_minmin`, `buflist_add` and `ME_TOO_MANY_ARGS` one by one and requires each to
be *there* — "it is the argv phase's to take" — and this phase takes all five. Run
on a phase 5 tree it says `'EDIT_STDIN' went, and it is the argv phase's to take`
and exits 1. Phase 2's check would fail on a phase 5 tree too, but a stage holding
2 and 5 holds 4, and `apart 2 4` already forbids that.

Two `uses` lines: `streams:5 seed:0 mechanical`, because the six declared records
are compared with the baselines phase 0 records, and `streams:5 harness:3
mechanical`, because an argv record is something a zero recording only has from
phase 3. Phase 4 is in the same package, so the ordering between them is the
package's and not a `uses`.

## Phase 6 — no write

`pipes/zero6-edit.sh` and `pipes/zero6-check.sh`, `stage 6`, `package files`. A
core does not own a disk: reading and writing files is the host's business, and
this is the first half of taking the filesystem away. The six Ex commands that
put bytes on one go — `:write :wq :xit :exit :update :saveas` — and with them
everything only they reached.

### Four anchors, and not one fold

The phase is four edits, and every removal after them is the sweep's
(rule 1). The `cmdnames[]` row is the only reference a command handler has, so
taking the row is what makes the handler unreachable:

1. the six enumerators of `enum CMD_index`, one line each;
2. the six `cmdnames[]` rows, one physical line each, designated `[CMD_x] = {`;
3. `nv_Zet`'s `ZZ`, which runs the command *string* `"x"` → `"q!"`;
4. `do_one_cmd`'s `:w>>` / `:w!` parse — an `if (ea.cmdidx == CMD_write ||
   ea.cmdidx == CMD_update) {…}` with no else — deleted as **text** rather than
   folded, because its condition names two of the enumerators that are going. It
   has to go in the same edit as anchor 1 or nothing declares what it reads.

**The alternative was measured.** An edit that also deletes `ex_write`,
`ex_update`, `ex_exit`, `do_write`, `check_writable`, `check_overwrite`,
`not_writing` and `check_readonly` by name produces a **byte-identical swept
file**, in 3 sweep rounds against 4 and 17 seconds against 22. Four seconds is
not a reason to write eight names into a phase program, so the minimal edit is
what runs.

**The text the edit leaves does not compile, and the program says so.** Six
mentions of the six enumerators survive it — `CMD_saveas` five times and
`CMD_wq` once — every one inside `ex_write`, `do_write` or `ex_exit`. The edit
asserts exactly that, as a computation rather than a list: each survivor is
inside a function definition, and no surviving `cmdnames[]` row names that
function, which is the whole argument that `funcreach.py` takes them in the
sweep's first round. `tools/phasecheck.sh` in the check is where *it compiles*
is asserted.

### `ZZ` is `ZQ`, and that is a decision

`nv_Zet` runs a command **string**, so nothing here breaks at compile time:
left alone, `ZZ` would type `:x` at a command that no longer exists and answer
`E492`. `case:zz_key` therefore moves whatever is done — `E32` today, `E492` if
the string is left, nothing at all with `"q!"` — so this phase owns it rather
than leaving a dead command named in the source. It is the user's settled
decision that ZZ is ZQ. `ZERO-PLAN.md` gives it to the `:q` phase; that row is
annotated as built.

### No DWARF dump, and phase 5's reason for one does not apply

Deleting the six renumbers **89** survivors, and every one is a `CMD_*`.
Measured with `tools/enumvals.sh`: **1,323 enumerator values in, 1,303 out** —
the six, plus fourteen single-constant explicit-value enums the sweep takes with
their types (`CPO_FNAMEAPP CPO_FNAMEW CPO_FWRITE CPO_KEEPRO CPO_OVERNEW
CPO_PLUS NODE_NORMAL NODE_OTHER NODE_WRITABLE SHM_WRI SHM_WRITE SMALLBUFSIZE
TRUNC_ON_OPEN WRITEBUFSIZE`) — 89 moved and nothing else touched, nothing
arriving.

Phase 5 compared DWARF either side because `main_errors[]` was a table written
in its enumerators' order, where a wrong index was invisible to the build.
`cmdnames[]` is **designated**: a row lands at its own enumerator whatever the
numbering is, the `static_assert` on the row count catches a dropped pair, and
all 105 surviving names are dispatched by `tools/zexcmds.py` inside the declared
delta. Three checks the build cannot dodge, and none of them needs the values.

**The row floor now has five rows of margin.** `cmdnames[]` goes 111 → 105 and
`tools/create_cmdidxs.py`'s `names()` refuses a table of fewer than 100 — a
regex that stops matching otherwise yields a plausible all-zero index, so the
floor is deliberate. `tools/zexcmds.py` enumerates the table through it, so
crossing it would stop zero's command sweep rather than give a wrong answer.
`ZERO-PLAN.md` 3a: the `:edit` phase spends the margin, and it is the phase that
must lower the floor.

### Two traps, and both make the obvious check the wrong one

- **`check_readonly` is also a local**, in `readfile()`: `int check_readonly;`
  and three uses. After the phase `grep -cw` is **4, not 0**, so a phase-4-style
  "every name at zero mentions" loop fails on a correct phase. What must be gone
  is the definition, `^check_readonly(`, and the four survivors are required to
  be inside `readfile()`.
- **`"write"` survives**, as the `'write'` option's name, and `E32: No file
  name` with it — still reachable through `check_fname()` from `do_ecmd()` and
  `ex_bang()`. A "no mention of write anywhere" check fails on a correct phase
  just as surely.

### The declared delta, and what the corpus cannot see

`6   case:cmd_write case:zz_key` and the six rows `write wq xit exit update
saveas`. The two kinds of movement are different: `cmd_write` goes from `E32: No
file name` to `E492: Not an editor command: write`, `zz_key` loses its bell,
its `E32` and two snapshots — and the six command rows **cease to exist**,
because `tools/zexcmds.py` enumerates 105 names where it enumerated 111.
Measured with `tools/zcompare.py`: the other 100 screen cases, the other 105
command rows, all 30 command lines, the four pty scenarios and the terminal
table are identical.

**And that is the whole of what any recording here can see.** Every one of the
102 screen cases types its own text and names no file, so `cmd_write` types
`:write` with no file name and what the baselines hold is an editor that
**failed** to write. "cmd_write and zz_key moved" is equally consistent with a
phase that changed one error message and left `buf_write()` reachable.

### The probes, which are the only evidence writing went

**26, on both binaries** — the one the phase was handed, built by the edit part
from the boundary's own makefile flags, and the one it made — **in a directory
they keep**. `tools/zstream.py`'s `session()` throws its run directory away,
which is the one thing a phase about files cannot do, so the runner is in the
check and adds one section to the record: what the run left on the disk.

- **`write_roundtrip`** types `WROTEME`, writes it to `out.txt`, empties the
  buffer and reads the file back. The old binary answers `"out.txt" 1L, 8B`; the
  new one `E484: Can't open file out.txt` and an empty buffer. It leans on
  `:read`, which the next phase removes — harmless, because `make zero-verify`
  runs every check on its own boundary.
- **`:w :sav :update :wq :x` with a file name**: `{'out.txt': 6}` on the old
  binary and `{}` on the new, for all five, with `:wq` and `:x` going exit 0 → 1.
- **Eight spellings** — `:w :x :wq :up :sav a :w! :w >>f :w !cat` — each E492
  now and none before, which is the inheritance check `CLAUDE.md`'s `:help` →
  `:helpclose` trap asks for.
- **Ten that must not move and do not**: `:q` on a modified buffer (still E37 —
  `check_changed` stays and is the `:q` phase's), `:q!`, `:read` (still E32, the
  read phase's), `:edit`, `:file`, `:%!sort`, `:s/x/y/`, `u`, CTRL-G and an
  ordinary edit.
- **A pty session**, because every probe above went through a pipe: `:wq
  out.txt` writes the file and quits on the old binary and answers E492 here,
  and an editing session is identical either side.

**Proven able to fail in both directions**: with the old binary on both sides
all sixteen report *was to move and did not*; with the new binary on both sides
they add *the input binary left {}, not a 6-byte out.txt, so this proves nothing
about writing*.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 85,734 | **84,675** (−1,059) |
| functions | 1,860 | 1,841 (−19) |
| enumerators (DWARF) | 1,323 | 1,303 |
| `cmdnames[]` rows | 111 | **105** |
| `nm -u`, zero's flags | 77 | **71** |
| `nm -u`, as `phasecheck.sh` counts it | 78 | **72** |
| `.text` / `.rodata` of the plain object | 648,496 / 17,609 | 640,449 / 17,289 |
| binary | 861,288 | **847,656** |

**The six that go are `chmod fchmod fstat ftruncate lstat unlink`**, and they
are the first any zero phase has freed. The check states the set rather than a
count, and requires `stat`, `open`, `access`, `fsync` and `getcwd` to be
**still** undefined, so a cut reaching into a later phase fails here rather than
widening quietly: `stat` is down from 14 calls to 8 and belongs to the phase
that gives up the buffer's name, `open` and `access` to the one that stops
reading a byte, `fsync` to the options.

Nineteen functions go, none of them named by the edit — `ex_write ex_update
ex_exit do_write check_writable check_overwrite not_writing check_readonly
check_file_readonly buf_write buf_write_bytes check_mtime time_differs
write_eintr vim_fexists mch_setperm mch_fsetperm mch_nodetype u_update_save_nr`
— with one struct field, `exarg_T.append`, and 39 string literals. The sweep is
**4 rounds, 22 s**, and the phase **46–49 s**. Its boundary is `8ce685cf2592`,
and `make zero-verify` recomputes all seven in 80 s of wall time over 299 s of
phases.

**What no instrument here sees, said out loud.** `p_fs`, `p_write` and `p_wa`
lose their last readers and keep their rows and their `:set` answers — removing
a row is the options phase's, and `tools/orphanopts.py` refuses a global whose
row has gone, so they are asserted at exactly two mentions each. Six
`'cpoptions'` and two `'shortmess'` letters lose their readers with no
observable change, the validity lists being string literals. `'readonly'` keeps
its `W10` warning and its `[RO]` indicator. And the row floor now has five rows
of margin rather than eleven.

### Its placement

`stage 6`, `package files`, and two `uses` lines: `files:6 seed:0 mechanical`,
because the declared records are compared with the baselines phase 0 records,
and `files:6 harness:3 mechanical`, because the old file-based sweep recorded an
exit status and `:write` went from E32 to E492 without changing it — phase 3's
message-level record is what can see this phase at all.

**`apart 5 6` is measured rather than predicted.** Phase 5's check states that
*it* frees no libc symbol, as a `cmp` against the stage's starting undefined
set, and inside a stage every check compares with the **stage's** start. Run as
one stage — `tools/phaserun.sh zero 5-6` — phase 5's check fails with *the libc
surface moved, and this phase frees nothing* and names all six.

**There is deliberately no `apart 2 6`.** Phase 2's check drives a pty with
`:wq` and reads the file back, which this phase would break — but measured, it
already fails identically on a phase **5** tree (status 256, the file
unchanged), because the session opens `f.txt` as a file *argument* and never
reaches the `:wq`. So the failure at 6 is phase 5's, a stage holding 2 and 6
holds 4, and `apart 2 4` forbids it already. Phase 4's check fails on a phase 6
tree for the reasons `apart 4 5` records.

## Phase 7 — no read

`pipes/zero7-edit.sh` and `pipes/zero7-check.sh`, `stage 7`, `package files`. The
other half of taking the filesystem away. Phase 6 removed the six commands that put
bytes on a disk; this one removes the command that takes them off it on request —
`:read` — and with it the `:r !cmd` arm, which was the last caller of the filter and
shell plumbing whim left as stubs. What is left of reading a file is `readfile()`
itself, which the startup path still uses, and this phase asserts by count that it
is untouched.

### Three anchors, and one fold that is a judgement

1. the `CMD_read` enumerator of `enum CMD_index`, one line;
2. the `cmdnames[]` row, one physical line, designated `[CMD_read] = {`;
3. `do_one_cmd`'s `if (ea.cmdidx == CMD_read) {…}` — the parse that turns `:r!` and
   `:r !cmd` into a filter — deleted as **text** rather than folded, because its
   condition names the enumerator that is going, and in the same edit as anchor 1.

**No handler is named.** The row is the only reference a command handler has, so
taking the row is what makes `ex_read` unreachable, and `do_bang`, `do_shell`,
`do_filter`, `check_secure` and `prevcmd_is_set` follow it — `:!` has not existed
since whim, and phase 6 swept `ex_write`, which held `do_bang`'s other call.

**The fold is `exarg_T.usefilter`, and it is the one thing here no tool could have
found.** Phase 6 removed one of its two writers (`:w >>`, `:w !cmd`) and anchor 3
removes the other, so after the edit the field is **written nowhere** — and
`do_one_cmd` memsets the struct, so all seven readers are constantly FALSE.
`tools/deadfields.py` removes a field nothing *names*, and gcc has no warning for a
member that is only read, so neither would ever have reported it. The six
surviving tests are folded with their polarity stated — two `&& !ea.usefilter`
conjuncts and one `|| ea.usefilter` disjunct in `do_one_cmd`, a
`!eap->usefilter &&` and the whole `if (eap->usefilter && strpbrk(repl, "!"))` arm
and one more conjunct in `expand_filename` — and the field goes with them.
**Measured both ways**: the fold costs 13 lines and gives a **byte-identical
recording**, because it removes tests whose answer was already fixed.

**The text the edit leaves does not compile**, and the edit says so as a
computation rather than a list: one mention of `usefilter` survives, in `ex_read`,
whose only reference was the row that just went, and no surviving `cmdnames[]` row
names that function — which is the whole argument that `funcreach.py` takes it in
the sweep's first round. `tools/phasecheck.sh` in the check is where *it compiles*
is asserted. It is phase 6's shape exactly, one name instead of six.

### The traps, which make the obvious check the wrong one

- **`secure` is not `check_secure`.** The function goes; the variable keeps
  **eleven** mentions, being the vimrc and tag-search flag half the editor tests.
  Only the two inside `check_secure()` went. A copied "every name at zero" loop
  fails on a correct phase.
- **The bare word `read` survives three times** — two `read(fd, …)` calls and an
  E222 string — and `readfile` 5, `read_buffer` 17, `open_buffer` 6, `read_edit` 2,
  `readonly` 4, `shell` 1 and `filter` 2. The eight names that genuinely reach zero
  are `ex_read do_bang do_shell do_filter check_secure prevcmd_is_set prevcmd
  CMD_read`.
- **`E32: No file name` survives and `E484: Can't open file` does not.** E32 is
  still reachable through `check_fname()` from `do_ecmd()`; `ex_read` was E484's
  last speaker, and after this phase nothing in the file says it. Both are asserted,
  in opposite directions, with `"read"`, E12, E34 and E319 — the four strings the
  five swept functions were the last to say.

**No DWARF dump, for phase 6's reason.** Deleting one enumerator renumbers 46
survivors and every one is a `CMD_*`; `cmdnames[]` is designated, the
`static_assert` on the row count catches a dropped pair, and all 104 names are
dispatched by `tools/zexcmds.py` inside the declared delta. Measured with
`tools/enumvals.sh` anyway, once, for this document: **1,303 values in, 1,302 out**,
`CMD_read` the only one gone, 46 moved, nothing arriving.

**The row floor now has four rows of margin.** `cmdnames[]` goes 105 → 104 and
create_cmdidxs's `names()` refuses a table of fewer than 100. `ZERO-PLAN.md` 3a: the
`:edit` phase spends the rest, and it is the phase that must lower the floor.

### The declared delta, and what the corpus cannot see

`7   case:cmd_read case:read_cmd_gone` and the sweep row `read`. `cmd_read` types
`:read` **with no file name**, so what the baselines hold is an editor that *failed*
to read, `E32: No file name`; it is `E492: Not an editor command: read` now.
`read_cmd_gone` types `:r !echo piped`, which whim's stub answered with
`E319: Sorry, the command is not available in this version`; it is E492 now, one
snapshot fewer and the same single bell either side. The `read` row does not change
message — it **ceases to exist**, `tools/zexcmds.py` enumerating 104 names where it
enumerated 105.

**`filter_gone` is not declared, and `ZERO-PLAN.md`'s P6 row over-declares it.**
`:!` has not existed since whim, so `:%!sort` already answered E492 on the input
binary and its record is byte-identical. What this phase removes is the code behind
a command that was already gone — which the check asserts, by requiring E492 on
*both* binaries.

Measured with `tools/zcompare.py`: the other 100 screen cases, the other 103 command
rows, all 30 command lines, the four pty scenarios and the terminal table are
identical.

### The probes, which are the only evidence reading went

**25, on both binaries** — the one the phase was handed, built by the edit part from
the boundary's own makefile flags, and the one it made — eleven required to move and
fourteen required not to.

**The file they read is `keys` itself.** `tools/zstream.py` writes a session's
keystrokes into a file called `keys` in the run directory and feeds it on stdin, so
there is always one file there and no runner has to plant one: `:r keys` reads it
back. **What proves the bytes arrived is the Escape in them** — the keystroke file
holds `…\x1b:q!\r`, which `tools/zscreen.py` draws as `^[:q!^M`, and an Escape can
only be in the buffer if the file was read. The *message* is not the check: `:1r
keys` reads the file and leaves the message line blank, measured, so only `:r keys`
is asked for `"keys" [noeol] 1L, 33B`.

- **`r_keys` and `r_range`** (`:r keys`, `:1r keys`): the keystrokes in the buffer
  on the old binary, E492 and nothing read on this one.
- **`r_missing`** (`:1r nosuch`): `E484: Can't open file nosuch` before, E492 now —
  the probe that pairs with E484 having no speaker left in the source.
- **`r_bang`** (`:r !echo piped`): **E319 in the stream** on the old binary and not
  here. It is in the stream and never in a snapshot, because the message is drawn, a
  `Press ENTER` prompt follows and the next redraw wipes the line before the cursor
  comes back, which is where `tools/zscreen.py` takes its picture. Its presence on
  the old binary is also the proof that no shell ever ran: the stub refused before
  one could.
- **Five spellings** — `:r :re :rea :r! :r !cat` — each E492 now and none before,
  which is the inheritance check `CLAUDE.md`'s `:help` → `:helpclose` trap asks for,
  with `:redo`, `:redraw`, `:registers` and `:reg` required not to move at all.
- **Fourteen that must not move and do not**: `:%!sort`, `:redo`, `:redraw`,
  `:registers`, `:reg`, `:undo`, `:edit`, `:print`, `:append`/`:insert`/`:change`,
  `:q` on a modified buffer (still E37), `:q!` and an ordinary editing session. The
  ones that must not move are required to be *doing* something — `:append` shows its
  added line, `:registers` prints its table **in the stream**, for E319's reason.
- **Two pty sessions**, because every probe above went through a pipe: `:r
  planted.txt`, where **the runner writes the file** — the editor has had no way to
  write one since phase 6 — which the old binary reads into the buffer and this one
  answers E492; and an editing session identical either side.

**Proven able to fail in both directions**: with the old binary on both sides all
eleven report *was to move and did not*, and with the new binary on both sides they
add *the keystroke file did not reach the buffer on the input binary, so this proves
nothing about reading*. Both pty sessions fail the same way round.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 84,675 | **84,453** (−222) |
| functions | 1,841 | 1,835 (−6) |
| enumerators (DWARF) | 1,303 | 1,302 |
| `cmdnames[]` rows | 105 | **104** |
| `nm -u`, zero's flags | 71 | **71, the same set** |
| `nm -u`, as `phasecheck.sh` counts it | 72 | 72 |
| `.text` / `.data` of the plain object | 640,449 / 38,923 | 638,960 / 38,699 |
| binary | 847,656 | **847,368** |

**Nothing is freed, and the check states it as an equality** — a `cmp` of the whole
undefined set — so a symbol *arriving* would fail too. `:read` reached `readfile()`,
which the startup path still uses, and the shell stubs never called a shell: this
phase removes two commands and not the read path, and `open`, `read`, `close` and
`stat` are required to be **still** undefined, `ZERO-PLAN.md` P8 being the phase
that frees them. `.rodata` does not move at all and `.data` loses 224 bytes,
because the five strings are `static char e_…[]` arrays and not `const`.

Six functions go, none of them named by the edit — `ex_read do_bang do_shell
do_filter check_secure prevcmd_is_set` — with three prototypes and five file-scope
variables: `prevcmd` and the four error strings, `"read"` having gone with the row.
The `usefilter` field is the edit's, and the only removal this phase names. The sweep is
**3 rounds, 19 s**, and the phase **43–47 s**. Its boundary is `8f1a98bef913`, and
`make zero-verify` recomputes all eight in 80 s of wall time over 344 s of phases.

### Its placement

`stage 7`, `package files`, and two `uses` lines: `files:7 seed:0 mechanical`,
because the declared records are compared with the baselines phase 0 records, and
`files:7 harness:3 mechanical`, because the old file-based sweep recorded an exit
status and `:read` goes from E32 to E492 without changing it — phase 3's
message-level record is what can see this phase at all. **There is no `files:7
files:6` line**: `tools/packages.sh --check` refuses a `uses` inside one package,
the ordering between two phases of the same package being the package's.

**`apart 6 7` is measured rather than predicted.** Phase 6's check names `do_bang`
among the things a later phase takes — "it is a later phase's" — and requires
`cmdnames[]` to hold 105 rows. Run on the tree this phase leaves it answers
`do_bang went, and it is a later phase's` and `cmdnames[] has 104 rows and names()
reads 104; both must be 105`, and exits 1. Its `write_roundtrip` probe reads the
file back with `:r out.txt` and would fail too; the source assertions come first.

**And `need 7 swept`, which is the first `need` the zero manifest has.** The edit's
anchor is `usefilter` at exactly 10 mentions — the field, the two writes anchor 3
removes and seven reads. On the text phase 6's *edit* leaves there are **eleven**,
`ex_write` still being there to read one, and the counted anchor refuses: measured
with `tools/phaserun.sh zero 6-7`, which says `usefilter has 11 mentions, expected
10`. The same run shows the edit's build of the input binary failing on phase 6's
non-compiling intermediate, which is true of every zero edit that builds one and is
not declared for that reason.

## Phase 8 — no `:edit`, and no `gf`

`pipes/zero8-edit.sh` and `pipes/zero8-check.sh`, `stage 8`, `package files`. Phases
6 and 7 took the commands that put bytes on a disk and the one that takes them off
it. This one takes the commands that point the editor **at** a file — `:edit :enew
:ex :visual :view` — and the four Normal-mode keys that do the same thing from the
buffer's own text, `gf gF [f ]f`. What is left of opening anything is `readfile()`
and `open_buffer()`, which the startup path still uses, and this phase asserts by
count that it has not reached them.

**What the five commands were, measured from outside rather than read.**
`do_exedit` is thirty lines after phase 4 — a lock guard, a `readonlymode`
save/set/restore testing `CMD_view` and `CMD_enew`, `setpcmark()` and one
`do_ecmd()` call — so on the input binary, in a directory holding a file called
`keys`: `:e! keys` loads it (`"keys" [noeol] 1L, 30B`), `:ex! keys` and `:visual!
keys` do exactly the same, `:view! keys` loads it **and makes `:set ro?` answer
`readonly`**, and `:enew!` empties the buffer. One handler, `ex_edit`, is all five
rows, which is why the five go together.

### Six anchors, and the sixth is measured

1. five enumerators of `enum CMD_index`, one line each;
2. five `cmdnames[]` rows, one physical line each, designated `[CMD_x] = {`;
3. `do_one_cmd`'s `curbuf_locked()` exemption: the `ea.cmdidx != CMD_edit` conjunct
   goes and **`CMD_file` stays**, `:file` being the buffer-name phase's. It must go
   in the same edit as anchor 1, and it is **the one anchor outside the table and
   the keys** — an edit shaped like the table forgets it, and the build is what
   catches that;
4. `nv_g_cmd`'s `case 'f': case 'F': nv_gotofile(cap); break;` arm. `case 'f':`
   alone occurs six times in that function and the four-line block once;
5. the same call in `nv_brackets`;
6. `do_one_cmd`'s `if (ea.argt & EX_ARGOPT) { while (… getargopt(&ea) …) }`.

**The sixth is worth its lines, and that is a measurement.** `EX_ARGOPT` — `++ff=`,
`++enc=`, `++bin`, `++edit` — was on five rows: `:read`, which phase 7 took, and
these four. After anchor 2 it is on **none**, so the block can never be entered,
`getargopt()` can never run, and `exarg_T.read_edit` is written by nothing and read
by nothing. Deleting it hands all three to the sweep: 30 lines, a seventeenth
function, and a recording **byte-identical** to the one the five anchors alone
produce — `++edit` was only ever accepted by the commands this phase removes, so
there is nothing to declare. `EX_CMDARG` reaches zero rows too and is deliberately
left: `do_ecmd_lnum` is written through `eval_vars()`, which is the buffer-name
phase's, so the fold round it belongs there.

**Anchor 5 is not a `cutil.fold_never`, and the reason is indentation.**
`fold_never` keeps an `else` body by dedenting it four columns, which is right when
the body was written one level in. This one was not: upstream's `else` here has no
braces at all — the `if` is inside `#ifdef FEAT_SEARCHPATH` — so slim's bracing pass
put a `{`/`}` round the rest of the function and left every line at the function's
own four columns. Dedenting would have put forty lines at **column zero**, and
`CLAUDE.md`'s *Verification tiers* says no tier can see indentation. So the head and
its matching closer are deleted as counted text, found by brace matching and
required to be a line of its own, and the body keeps what it had.

**No handler is named.** The row is the only reference a command handler has, so
taking the five rows is what makes `ex_edit` unreachable and sixteen more follow it.

**The text the edit leaves does not compile**, as phases 6 and 7 leave theirs: three
mentions of `CMD_enew` and `CMD_view` survive, all inside `do_exedit`, and the edit
asserts that as a computation — every survivor is inside a function definition and
no surviving `cmdnames[]` row names that function, which is the whole argument that
`funcreach.py` takes it in the sweep's first round.

### The hazard this phase does not have, asserted anyway

**No `nv_cmds[]` row is deleted or repointed.** There is no row for `gf`, `gF`, `[f`
or `]f`: they are arms inside two handlers whose `g`, `[` and `]` rows dispatch
dozens of other keys. That is an argument, and `CLAUDE.md`'s twelve-phase arrow-key
bug is what an argument costs when it is wrong, so the check measures it: **fifty
`g*`, `[` and `]` keys pressed on both binaries, and exactly four moved** — `gf gF
[f ]f` — the other 46 identical in exit, bells, snapshots and stream digest.
`tools/nvidxcheck.py` still reports 194 rows indexed once each.

### The row floor is crossed here, and the floor moves in the same commit

`cmdnames[]` goes **104 → 99**, and create_cmdidxs's `names()` refused a table of
fewer than 100. **The failure is not the one the name suggests**: measured, it is
`no command table found in either shape`, because `names()` tries both parsers with
`check=False` and neither answer clears the bar. `tools/zexcmds.py` enumerates
zero's whole Ex sweep through it, so the old floor would have stopped the sweep,
`tools/zerodelta.sh`, the recording and every later phase's check rather than giving
a wrong answer. `ZERO-PLAN.md` decision 8 is settled: **lowered to 80, deliberately,
in the phase that crosses it, with the reason in the tool's own docstring.** The
margin is 19 rows and the next row the plan removes is `:file`'s.

**What the floor edit costs, measured over all 115 implementation keys**
(`tools/implhash.sh` for every whim stage, every whim edit, every slim phase and
every zero phase): **28 move** — 6 whim stages (42-63, 66-71, 72, 73-77, 78, 79), 15
whim edits (58, 63, 66, 68–79), 2 slim phases (6, 7) and 5 zero phases (2, 4, 5, 6,
7). The last five are there only because their programs name the tool's path in a
comment; `implhash.sh` greps for paths and does not know what a comment is. Every
one of those phases calls the tool with a 489- or 600-row table, so `--check` passes
identically and every boundary reproduces; the cost is CPU in a repass. **Gated on
both**: `make slim-verify` 12 of 12 (394 s of phases in 114 s of wall time) and
`make whim-verify` 13 of 13 (1,638 s in 595 s), green after the edit. This is rule 9
being paid rather than avoided — a zero-only tool was not an option, because the
floor is inside the tool the sweep reads the table with.

### The traps, which make the obvious check the wrong one

- **Five pairs where one name is a prefix of another and only one goes**:
  `check_lnums`/`check_lnums_both`, `reset_VIsual`/`reset_VIsual_and_resel`,
  `u_unchanged`/`u_unch_branch`, `do_ecmd`/`do_ecmd_cmd`, `otherfile`/`otherfile_buf`.
  Every count in both programs is `\b`-anchored for that reason.
- **`"edit"` reaches zero and `"ex"` does not.** `getargopt()`'s `++edit` strncmp
  was the last speaker of `"edit"` once the row went, and anchor 6 takes it; `"ex"`
  survives as one word of `'belloff'`'s value list. A check that wanted both to
  survive fails on this phase, and one that wanted both gone fails on a correct one.
- **`E447: Can't find file "%s" in path` survives.** `nv_gotofile()` was not its only
  speaker, so the message the key probes look for on the old binary is still in the
  source afterwards. It is the **key** that went, not the string.
- **Three things are left write-only rather than removed**, and are asserted at
  their counts so that a later widening has to move them: `readonlymode` (5
  mentions, one write, and that write `FALSE`), `do_ecmd_cmd` (6) and `do_ecmd_lnum`
  (2).

**`'undoreload'` is not this phase's, and it earns the plan's `uses` line.** `p_ur`'s
only reader was inside `do_ecmd`, so it is now a global with an option row and
nothing that reads it. Removing the row would change what `:set ur?` answers, which
nothing this pipeline records sweeps, so the delta could not be checked — and
`tools/orphanopts.py` refuses the opposite direction, a global whose row has gone.
It is asserted at exactly 2 mentions **with** its row, and
`uses options:11 files:8 mechanical  'undoreload' is read by do_ecmd` is the line
the options phase carries.

### The line against the byte-reader phase, and one correction to the plan

`readfile` keeps exactly **5** mentions — its prototype, its definition and the
three calls in `read_buffer()` and `open_buffer()` — and `read_buffer` 17.
`open_buffer` goes **6 → 5**, and that is the number `ZERO-PLAN.md` 3c got
backwards: it says `readfile`'s last caller is `do_ecmd`, and `do_ecmd` called
`open_buffer`. What this phase costs the read path is one call site. The plan's
`uses files:8 files:7` line is corrected there.

### The declared delta, and what the corpus cannot see

`8   case:cmd_edit case:key_gf` and the five rows `edit enew ex view visual`. The
two kinds of movement are different:

- **`cmd_edit`** types `:edit` with no file name, so the baselines hold an editor
  that got as far as `check_changed()` and refused — `E37: No write since last
  change (add ! to override)`. It is `E492: Not an editor command: edit` now.
- **`key_gf`** presses `gf` on a word naming nothing, so the baselines hold
  `E447: Can't find file "nosuchfile" in path` — an editor that **looked**. The key
  beeps from `nv_g_cmd`'s `default: clearopbeep` now, where every other unused `g`
  key does: the record loses one snapshot and keeps **one bell either side**, so the
  check is the screen and the snapshot count and not the bell.
- the five `ref-excmds.txt` rows do not change message, they **cease to exist**:
  `tools/zexcmds.py` enumerates 99 names where it enumerated 104.

Measured with `tools/zcompare.py`: the other 100 screen cases, the other 94 command
rows, all 30 command lines, the four pty scenarios and the terminal table are
identical.

### The probes, which are the only evidence

**34, on both binaries** — the one the phase was handed, built by the edit part from
the boundary's own makefile flags, and the one it made — twenty required to move and
fourteen not, plus the fifty-key sweep and two pty sessions.

**The file they open is `keys` itself.** `tools/zstream.py` writes a session's
keystrokes into a file called `keys` in the run directory and feeds it on stdin, so
there is always one file there and no runner has to plant one. **What proves the
bytes arrived is the Escape in them** — the keystroke file holds `…\x1b:q!\r`, which
`tools/zscreen.py` draws as `^[:q!^M`, and nothing typed at `:` can put an Escape in
the buffer.

- **`edit_keys`, `ex_keys`, `visual_keys`, `view_keys`**: the keystrokes in the
  buffer and the file named on the old binary, E492 and nothing opened on this one.
  `view_keys` then asks `:set ro?` and requires `readonly` before and `noreadonly`
  after, which is the whole of what `do_exedit` did with `CMD_view`.
- **`enew_bang`**: the old binary throws the text away and this one does not.
- **`key_gf gF [f ]f`**: E447 on the old binary — the proof that the key reached
  `nv_gotofile()` and looked — and **one snapshot fewer** afterwards, the bell
  unchanged.
- **Ten spellings** — `:e :ed :edit :enew :ex :vi :vis :vie :view :visual` — each
  answering E37 before and E492 now, which is the inheritance check `CLAUDE.md`'s
  `:help` → `:helpclose` trap asks for. **`:en` is the eleventh and is not one of
  them**: `enew`'s shortest abbreviation is three characters, so `:en` matched
  nothing before this phase either, and it is asserted as E492 on *both* sides —
  whim's Phase 80 rule, measured rather than argued.
- **Fourteen that must not move**: `:en`, `:earlier`, `:verbose set ro?`,
  `:vglobal/a/d`, `:vmap`, `:file` (still `[No Name]`), `:read keys` (E492 on both,
  phase 7 having taken it), `:print`, `:append`, `:registers`, CTRL-G, `:q` on a
  modified buffer (still E37), `:q!` and an ordinary editing session. The ones that
  must not move are required to be *doing* something.
- **Two pty sessions**: `:e! planted.txt`, where the runner writes the file — the
  editor has had no way to write one since phase 6 — which the old binary loads and
  this one answers E492; and an editing session identical either side.

**Proven able to fail in both directions**: with the new binary on both sides all
twenty report *was to move and did not* and add *the keystroke file did not reach
the buffer on the input binary, so this proves nothing about opening a file*; with
the old binary on both sides they add *the new binary opened the file anyway*.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 84,453 | **83,755** (−698) |
| functions | 1,835 | 1,818 (−17) |
| type definitions | 1,010 | 998 |
| enumerators (DWARF) | 1,302 | **1,286** |
| `cmdnames[]` rows | 104 | **99** |
| `nm -u`, as `phasecheck.sh` counts it | 72 | **72, the same set** |
| `.text` / `.data` of the plain object | 638,960 / 38,699 | 633,907 / 38,571 |
| binary | 847,368 | **838,856** |

**Nothing is freed, and the check states it as an equality** — a `cmp` of the whole
undefined set, so a symbol *arriving* would fail too. `:edit` reached `do_ecmd()`,
which reached `open_buffer()` and `readfile()`, and both are the startup path's, so
`open`, `read`, `close` and `stat` are required to be **still** undefined,
`ZERO-PLAN.md` P8 being the phase that frees them.

Seventeen functions go, none of them named by the edit — `do_ecmd` (328 lines),
`get_visual_text`, `check_lnums_both`, `do_exedit`, `nv_gotofile`, `grab_file_name`,
`prepare_help_buffer`, `u_unch_branch`, `text_or_buf_locked`, `reset_VIsual`,
`reset_VIsual_and_resel`, `delbuf_msg`, `ex_edit`, `u_unchanged`, `otherfile`,
`check_lnums` and `getargopt` — with two struct fields, sixteen enumerators and
seven string literals (`"edit" "enew" "view" "visual"`, E143, E1546 and the help
buffer's `'iskeyword'`). **Sixteen enumerators go and 87 renumber, every one of the
87 a `CMD_`**, and the check dumps DWARF either side and requires it: the sixteen
are the five `CMD_`, `EX_ARGOPT`, and ten single-constant enums the sweep takes with
their types (`CPO_GOTO1 DOCMD_RANGEOK ECMD_FORCEIT ECMD_HIDE ECMD_NOWINENTER
ECMD_OLDBUF ECMD_SET_HELP FNAME_REL FNAME_UNESC READ_NOWINENTER`). The sweep is **3
rounds** and the phase **50 s**. Its boundary is `eeb4031a31b4`, and `make
zero-verify` recomputes all nine in 79 s of wall time over 394 s of phases.

### Its placement

`stage 8`, `package files`, and two `uses` lines: `files:8 seed:0 mechanical`,
because the declared records are compared with the baselines phase 0 records, and
`files:8 harness:3 mechanical`, because the old file-based sweep recorded an exit
status and `:edit` goes from E37 to E492 without changing it. **There is no `files:8
files:7` line**, for phase 7's reason: `tools/packages.sh --check` refuses a `uses`
inside one package.

**`need 8 swept`, measured.** The edit's anchor is `readfile` at exactly 5 mentions.
On the text phase 7's *edit* leaves there are **seven**, `ex_read` still being there
to make two of them, and the counted anchor refuses: `tools/phaserun.sh zero 7-8`
says `readfile has 7 mentions, expected 5`. The same run shows the edit's build of
the input binary failing on phase 7's non-compiling intermediate, which is true of
every zero edit that builds one and is not declared for that reason.

**`apart 7 8`, measured.** Phase 7's check requires `check_fname` at 4 mentions,
`open_buffer` at 6 and `read_edit` at 2, names `do_ecmd` and `otherfile` as a later
phase's, and requires `cmdnames[]` to hold 104 rows with `:edit` among them. Run on
the tree this phase leaves it gives seven complaints — `:edit went, and it is not
this phase's` and `do_ecmd went, and it is a later phase's` among them — and exits 1.

**And deliberately no `apart 6 8`**, which is the shape of the missing `apart 2 6`.
Phase 6's check *does* fail on a phase 8 tree — measured: `do_bang went`, `otherfile
went`, `cmdnames[] has 99 rows and names() reads 99; both must be 105`, exit 1 — but
a stage holding 6 and 8 holds 7, and `apart 6 7` forbids that already.

## Phase 9 — nothing reads a byte

`pipes/zero9-edit.sh` and `pipes/zero9-check.sh`, `stage 9`, `package files`. Phases
6, 7 and 8 took every way to *ask* for a file. This one takes the machinery those
commands used: `readfile()`, 787 lines, `read_buffer()`, the four functions of the
message layer that reported what had been read, and eleven more the sweep finds
under them. The file loses 1,183 lines and the core loses `access`, `fcntl` and
`open` — the first libc symbols a zero phase has freed since phase 6.

### What makes this phase different from every one before it

**`readfile()` was already unreachable when the phase was handed the tree**, and
that is the whole of what makes it delicate rather than difficult. Its three call
sites are one in `read_buffer()` and two in `open_buffer()`, and `read_buffer`'s
only callers are those same two arms. The outer arm needs `curbuf->b_ffname !=
NULL` and the inner one a `read_stdin` argument that all four callers pass as
`FALSE`; phase 5 took the file argument and the bare `-`, and phases 6, 7 and 8 took
every command that could name a file. Nothing the editor can be given reaches it.
gcc keeps the code only because it cannot prove `b_ffname != NULL` never holds.

So **the difference this phase makes is between code that cannot run and code that
is not there**, and no behavioural probe can see it. A recording that *moved* would
mean the cut was wrong. That is why the declared delta is nothing at all, and why
the evidence is something else.

### Four anchors, all inside `open_buffer()`

1. the `if (curbuf->b_ffname != NULL) {…} else if (read_stdin) {…}` pair, as exact
   text with the blank line after it — 36 lines holding all three calls into the
   read path;
2. `int read_fifo = FALSE;`, whose only writer was anchor 1;
3. `else if (retval == OK && !read_stdin && !read_fifo)` → `else if (retval == OK)`,
   where anchor 2's second reader was;
4. the signature — `open_buffer(int read_stdin, exarg_T *eap, int flags_arg)` →
   `open_buffer(void)` — the `int flags = flags_arg;` local, and the four call sites
   in `enter_buffer`, `ml_append_flags`, `ml_replace_len` and `create_windows`,
   every one of which already passed `FALSE, NULL, 0`.

**There is no prototype for `open_buffer`.** It is defined above its first call, so
the `static int open_buffer(…);` line the proto block would hold does not exist, and
a phase that edits one fails loudly. Anchor 4 edits the definition alone.

**Anchor 4 is what takes `read_stdin` to zero, and it is measured rather than
argued.** Without it `open_buffer` keeps three parameters nothing reads, and **the
sweep cannot see them**: `tools/sweep.sh` compiles with `-Wno-unused-parameter`, so
an unused parameter is invisible where an unused local is not. Measured both ways
on this input: anchors 1–3 alone leave the sweep deleting the `int flags =
flags_arg;` local by its own unused-variable pass and `read_stdin` alive at exactly
**one** mention, the parameter. Both swept files are **82,572 lines** and differ in
exactly **five** — the signature and the four calls — the two binaries are the same
830,440 bytes, and **the two recordings are byte-identical**. The fold costs
nothing, says what is true, and is taken.

**One further fold is declined, deliberately.** After anchor 1, `retval` in
`open_buffer` is `OK` from its initialiser to its return and nothing between can
change it, so `if (retval != OK) return retval;` is dead, the function could be
`void`, and the two `open_buffer() == FAIL` guards in the `ml_*` layer can never
hold. That is memline tidy, not the read path. The edit asserts `retval` at its **5
mentions with one assignment** and says it is constant, and the 75-line function is
left for a later phase.

**The text this edit leaves compiles**, where phases 6, 7 and 8 each left theirs
broken until the sweep had run: nothing it removed was named from outside what it
removed, so there is no dangling enumerator and no handler without a row. `readfile` goes 5 → 3
and `read_buffer` 17 → 15, and the survivors are not calls — a prototype, two
definitions, and **fourteen mentions of `readfile`'s own local `int read_buffer =
(flags & READ_BUFFER);`**. The edit asserts exactly that, and the two entry points
the sweep starts from are exactly the two `-Wunused-function` warnings the text
produces: `read_buffer` and `fix_help_buffer`.

### The evidence, which is an instrumented pair and nothing else

There is no behavioural must-differ probe and no dishonest one is offered instead.
What the check does is build **the source the phase was handed, twice**:

- **probe** — `old.c` with `(void)write(2, "READFILE-ENTERED\n", 17);` as
  `readfile()`'s first statement. Recorded with `tools/zrecord.sh`: **0 of the 106
  records** carry the marker.
- **ctl** — the *identical* instrument in `open_buffer()`, which **is** reached.
  **104 of the same 106** carry it.

The zero is the claim; the 104 is what makes it a probe that can fail. The two
records that stay quiet under `ctl` are `ref-pty.txt` and `ref-term.txt`, and the
reason is the instrument and not the editor — both drive a real pty and keep what
was *drawn*, where the other three keep stderr separately. They are named in the
check so that a third going quiet is a failure rather than a shrug.

**Proven able to fail, by measurement**: with `readfile` replaced by `open_buffer`
in the probe build, the check reports *104 of 106 records ENTERED readfile() on the
binary this phase was handed* and exits 1.

**Eight adversarial sessions** run on both instrumented binaries, and they are the
part that asks whether anything could still get in. Naming a buffer after a real
file that exists and then making the editor want its contents is the shape of every
way back into `readfile()` there was: `:file /etc/hostname` and then `G`, an insert
and an undo, `:bdelete`, the `%` register, and then `:new`, `:ball`, `:buffer 1` and
the `#` register. **Each reached `open_buffer()` and not one reached `readfile()`** —
and the first half of that is checked too, because a session that gets nowhere is
not an adversary.

### The declared delta is nothing at all, and it is measured twice

`pipes/zero.delta` gets a comment for phase 9 and no line, as phases 0, 1 and 3 do.
**`diff -rq` over two full `tools/zrecord.sh` recordings — the binary the phase was
handed against the one it made — is empty**: all 102 screen cases, all 111
Ex-command rows, all 30 command lines, the four pty scenarios and the nineteen
terminal rows. `tools/zerodelta.sh --phase 9` then finds the same against whim-vim's
frozen baselines, with the eight lines phases 2 to 8 declared and nothing new.

The check also runs eight sessions directly between the two binaries and requires
each to be identical **and to be doing something**: an ordinary editing session,
`:file` and CTRL-G (still `[No Name]`), `:registers` with its table in the stream,
the `%` and `#` registers, `:q` on a modified buffer (still E37) and `:q!`.

### The traps, which make the obvious check the wrong one

- **`check_readonly` reaches zero here, not at phase 6.** It was `readfile()`'s
  *local*, four mentions since phase 6, and a check copied from that phase fails on
  a correct phase 9.
- **`readonlymode` goes 5 → 3**, where phase 8's check asserts 5: `readfile` held
  two of them. It is still write-only and `FALSE`, and still the options phase's.
- **`msg_scrolled_ign` becomes read-only, and nothing sees it.** Four writers, all
  inside `filemess()` and `readfile()`; after this phase it is `FALSE` for ever with
  one reader left, in `msg_puts_attr_len()`. gcc has no warning for a variable that
  is only read, `deadsweep.py` removes what is unused rather than what is constant,
  and `deadfields.py` is about struct members. It is asserted at **2 mentions,
  read-only**, and handed on rather than folded.
- **Four struct fields become write-only and `deadfields.py` cannot see them**,
  because they are still *named* — by the writes in `buf_store_time()` and
  `set_b0_fname()`: `b_mtime_read`, `b_mtime_read_ns`, `b_orig_size`, `b_orig_mode`,
  three mentions each, of which exactly one is not a write. They go with the
  buffer's name in phase 10. (`b_mtime` and `b_mtime_ns` are read, but only to feed
  `b_mtime_read`, so the whole six-field cluster is dead from outside.)
- **`"[RO]"` goes 3 → 2 and `"[readonly]"` 2 → 1**, each losing `readfile`'s copy
  and keeping the rest, and **CTRL-G's counter survives** — `"%ld line --%d%%--"` is
  `fileinfo()`'s and was never `readfile`'s. All three are asserted at their counts,
  which is the opposite direction from the 24 strings that go.
- **`read_cmd_fd` does not move at all**: 12 mentions on 11 lines, and every one of
  them the terminal's — `fill_input_buf()` and `mch_settmode()`.
- **`setfname` goes 3 → 2**, because `set_rw_fname` was its second caller. That is
  what makes phase 10 possible.

### Seventeen enumerators go and nothing renumbers

`typereach.py` deletes **seventeen whole anonymous enum definitions** — the eight
`READ_*` flags, and `BF_NEW_W`, `CONV_RESTLEN`, `CPO_FNAMER`, `NOTDONE`, `O_EXTRA`,
`SHM_LAST`, `SHM_LINES`, `SHM_OVER` and `SHM_OVERALL` — and a whole definition
leaving takes no survivor's value with it. The check dumps DWARF either side and
requires exactly that: **1,286 → 1,269, not one survivor renumbered and none
arriving**, so no parallel table can have shifted. That is the opposite of phase 8,
where 87 renumbered, and it is worth the four seconds either side to say.

**No `cmdnames[]` row and no `nv_cmds[]` row is touched**: this phase removes no
command. The table is the same 99 rows phase 8 left, `names()` reads 99, the
`static_assert` is in place, and the floor phase 8 lowered to 80 is asserted **by
using it** — the checked parser is called and must not refuse — rather than by
grepping for the number. `tools/nvidxcheck.py` still reports 194 rows indexed once
each. `E32: No file name` survives with `check_fname` at 3 mentions, and E37 with
`check_changed` at 4.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 83,755 | **82,572** (−1,183) |
| functions | 1,818 | 1,802 (−16) |
| type definitions | 998 | 981 (−17) |
| enumerators (DWARF) | 1,286 | **1,269** |
| `cmdnames[]` rows | 99 | 99 — untouched |
| `nm -u`, as `phasecheck.sh` counts it | 72 | **69** |
| `.text` / `.data` / `.rodata` of the object | 633,907 / 38,571 / 17,225 | 623,651 / 38,379 / 16,921 |
| binary | 838,856 | **830,440** |

**Three symbols go and the check names the set, not the count**: `access`, `fcntl`
and `open` were `readfile()`'s and nothing else's. `read`, `close` and `dup` **stay**
and are the terminal's alone — `fill_input_buf()` and `mch_settmode()` — so a check
that read "the file symbols went" would be wrong here; `stat`, `getcwd` and
`strerror` are phase 10's and `fsync` the `FILE *` phase's, and all seven are
required to be **still** undefined.

Sixteen functions go, none of them named by the edit: `readfile` (787 lines),
`read_buffer`, `read_eintr`, `readfile_linenr`, `filemess`, `msg_add_fname`,
`msg_add_lines`, `msg_add_eol`, `after_pathsep`, `dir_of_file_exists`,
`fix_help_buffer`, `gettail_sep`, `mch_isdir`, `set_rw_fname`,
`u_find_first_changed` and `utf_ptr2len_len` — with fifteen prototypes, three
file-scope error strings, seventeen enumerators and **24 string literals**, which
are the whole of the message layer: `"%s%ldL, %lldB"`, `"[noeol]"`,
`"[READ ERRORS]"`, `"[New DIRECTORY]"`, `"Vim: Reading from stdin...\n"`, E200, E201,
E812 and sixteen more. Nothing in the instrument loses a message: the last thing
that could print `"keys" 1L, 30B` was `:read`/`:edit`. The sweep is **3 rounds** and
the phase **42 s**. Its boundary is `6755bb567bea`, and `make zero-verify`
recomputes all ten in 80 s of wall time over 448 s of phases.

### Its placement

`stage 9`, `package files`, and two `uses` lines: `files:9 seed:0 mechanical`,
because `tools/zerodelta.sh` compares the recording with the baselines phase 0
records and this phase's whole declaration is that nothing in them moved, and
`files:9 streams:5 mechanical`, because the `read_stdin` *argument* anchor 4 removes
is `FALSE` at all four call sites only since phase 5 took the bare `-` and
`EDIT_STDIN` with it. **There is no `files:9 files:7` or `files:9 files:8` line**,
for phase 7's reason — `tools/packages.sh --check` refuses a `uses` inside one
package — and both dependencies are real and are stated here and in the program's
head instead: `:read` held two of `readfile`'s seven mentions before phase 7, and
`do_ecmd` passed `eap` and flags to `open_buffer` until phase 8, which is what lets
the signature fold happen at all.

**`need 9 swept`, measured.** The edit's anchor is `open_buffer` at exactly 5
mentions — the definition and four callers, every one of them `open_buffer(FALSE,
NULL, 0)`, which is what lets anchor 4 rewrite all four by text. On the text phase
8's *edit* leaves there are **six**: `do_ecmd` is still there to make
`(void)open_buffer(FALSE, eap, readfile_flags);`, the one call site the rewrite
would **not** match and one the sweep would then delete, hiding the mistake.
`tools/phaserun.sh zero 8-9` says `open_buffer has 6 mentions, expected 5`. The same
run shows the edit's build of the input binary failing on phase 8's non-compiling
intermediate, which is true of every zero edit that builds one and is not declared
for that reason.

**`apart 8 9`, measured.** Phase 8's check draws its line against this phase as
counts — `readfile` 5, `read_buffer` 17, `readonlymode` 5, `b_ffname` 43,
`b_fname` 37 — so that reaching into the read path would fail rather than widen
quietly. Run on the tree this phase leaves it gives five complaints, `readfile has 0
mentions, expected 5` among them, and exits 1. Its symbol check would fail too,
being a `cmp` of the whole undefined set against a phase that frees three, but the
source assertions come first.

## Phase 10 — the buffer has no name

`pipes/zero10-edit.sh` and `pipes/zero10-check.sh`, `stage 10`, `package files`.
Phases 6, 7 and 8 took every way to *ask* for a file and phase 9 took the machinery
that read one. What was left of the filesystem in this editor is a **name**: three
`char_u *` fields on every buffer — `b_ffname`, `b_sfname`, `b_fname` — and the one
command that could still set them, `:file`. This phase takes the command, stops
`buflist_new()` naming the buffer it makes, folds the sixteen places that ask what
the name is, and hands the sweep **sixty functions**, the largest number any zero
phase has. It is also where the core stops asking the filesystem questions of its
own initiative: `stat`, `getcwd` and `strerror` go, and with `access`, `fcntl` and
`open` already gone at phase 9 **the process has no way left to acquire a fourth
file descriptor**.

### Seven parts, and every removal that is not one of them is the sweep's

**A — `:file` goes.** The enumerator, the `cmdnames[]` row, and **both** of
`do_one_cmd`'s `CMD_file` tests: the `curbuf_locked()` conjunct phase 8 deliberately
kept, saying this phase would take it, and the second test below it. All in the same
edit as the enumerator or the text does not compile. The row is the only reference a
handler has, so taking it is what makes `ex_file` unreachable, and `rename_buffer`
and `setfname` follow — `set_rw_fname` having been `setfname`'s second caller until
phase 9 took it. **`fileinfo()` survives**, with three callers: CTRL-G, `g CTRL-G`
and the startup message.

**B — `buflist_new()` never names.** Its one call site is `create_windows`', and it
has passed `NULL, NULL` since phase 5 took the file argument. So both parameters go
with the `fname_expand`/`stat`/`buflist_findname_stat` prologue, the
`if (ffname != NULL)` assignment that *was* the naming, the failure arm's frees and
the `st.st_dev` block — nine counted replacements inside one definition, plus the
prototype and the call.

**C — sixteen folds, one per site, each with its constant written out in the
program.** The three fields are NULL for ever, so `== NULL` is TRUE and folds always
and `!= NULL` is FALSE and folds never. **The invariant is computed before anything
is folded**: every write to the three fields is enumerated and required to be inside
`buflist_new`, `setfname`, `rename_buffer` or `shorten_buf_fname` — the four this
phase accounts for — and a write anywhere else would make every fold a guess.

**D — `EX_XFILE` reaches zero rows, which is the largest part of the phase and is
computed.** `:read` was one of its six rows and phase 7 took it; four more went with
the `:edit` family at phase 8; `:file` was the last. So `do_one_cmd`'s
`if ((ea.argt & EX_XFILE) && expand_filename(…) == FAIL)` can never be entered, and
folding it never hands the sweep **32 of the sixty functions** — `expand_filename`,
`eval_vars`, `find_cmdline_var`, the whole `ExpandOne`/`ExpandFromContext`/
`gen_expand_wildcards` layer, `vim_FullName`, `mch_FullName`, `FullName_save`,
`shorten_fname`, `home_replace_save`, `backslash_halve` and the `ff_*` remnants. It
is phase 8's `EX_ARGOPT` in exactly the same shape. One more edit goes with it:
`separate_nextcmd`'s `eap->argt & (EX_CTRLV | EX_XFILE)` loses the second disjunct,
which is 0 for every row, and that is what takes the enumerator itself to zero.

**E — two write-only leftovers nothing can see.** `readonlymode` had one reader,
inside `open_buffer`, and part C folds it; a file-scope static that is assigned and
never read draws no warning and `deadsweep.py` acts on warnings, so it goes by hand
with the `if` around its write — an `if` with an empty body being something no tool
here removes either. `b_dev_valid`'s one surviving assignment is part B's fold of
the device block, and `deadfields.py` removes a field nothing *names*, not one that
is only written, so it goes by hand too and the three fields it guards sweep.

**F — `shorten_fnames()` stops asking where it is.** `shorten_buf_fname()` is empty
after part C, so the `mch_dirname()` cwd fetched for it is fetched for nothing. The
signature folds to `void` in the same edit, for phase 9's measured reason:
`tools/sweep.sh` compiles with `-Wno-unused-parameter`, so an unused parameter is
invisible where an unused local is not.

**G — nothing looks a name up on a disk.** `find_file_name_in_path()`'s
`if (options & FNAME_EXP)` arm searched `'path'` and `mch_getperm()`ed each
candidate; the other arm returns the word itself. Folding the arm never is the
charter reading of *no filesystem access*: the editor extracts text and asks
nothing. `find_file_in_path()` and `mch_getperm()` are then the sweep's, and `stat`
goes with them. **The cost is that CTRL-F and CTRL-P become indistinguishable**, and
that is the one piece of behaviour this phase gives up beyond `:file`.

### Three things about the folds that a tool would have got wrong

**`buflist_name_nr` is folded at its callers and never in place, and the agent that
surveyed this phase made the mistake first.** Its body is `buf =
buflist_findnr(fnum); if (buf == NULL || buf->b_fname == NULL) return FAIL; *fname =
buf->b_fname; … return OK;`. Folding the whole `if` away gives a function that
returns OK with `*fname` never written — a silent behaviour change in the direction
that crashes. What is true is that it returns **FAIL always**, so the fold belongs
at `getaltfname()`, which becomes `emsg(E23); return NULL;`, and at `ex_display()`,
whose `"#` block then does nothing and goes whole. Only then is it uncalled.

**Three sites have an `else` and `cutil.fold_always` refuses them, by design.**
Keeping a body and dropping an else is not what it does, so `fileinfo()`,
`set_b0_fname()` and `get_trans_bufname()` use a local `fold_always_else()` that
keeps the if body dedented four columns — right only because each of the three was
**read** first, phase 8's anchor 5 being what a wrong dedent costs. The helper
refuses a body that is not written one level in.

**Four more are a function whose whole body is the `if`.** `buf_spname()`,
`buf_get_fname()`, `check_fname()` and `getaltfname()` each end in a second
`return`, and `fold_always` there leaves it behind **unreachable and alive** —
measured: `return buf->b_fname;` would have kept `b_fname` referenced for ever and
no sweep tool removes it. Those four are exact-text rewrites of the body.

**And two folds the brief asked for are not made.** Both of `eval_vars()`'s
`if (b_fname == NULL)` arms are inside a function part D makes unreachable —
`expand_filename()` and `expand_wildcards_eval()` are its only callers and both go —
so folding inside text the sweep deletes changes no output and states nothing. Rule
1 applies, and the check requires `eval_vars` at 0 mentions instead.

### What the screen shows afterwards

`[No Name]` survives and is now **the only thing `buf_spname()` can return**, not
one of two answers. CTRL-G prints `"[No Name]" [Modified] 1 line --100%--`
byte-identically either side, and so do `g CTRL-G`, the status line and `:ls`.
`:registers` does not move either: its `"%` and `"#` lines were never printed,
`b_fname` having been NULL since phase 5.

**Three flags are left read-only and named rather than folded.** `BF_NOTEDITED` can
never be set — `setfname()` was its only writer — and `BF_NEW` never could; both are
still read by `fileinfo()`, so CTRL-G asks two questions whose answer is fixed.
`b_shortname` has the same shape and was **already** write-only before this phase.
Folding any of the three changes the string set for no gain, so all three are
asserted where they are. `msg_scrolled_ign` is phase 9's leftover and does not move.

**`"file"` reaches zero and `E32: No file name` does not.** `check_fname()` survives
folded to an unconditional `emsg`, because `get_spec_reg()`'s `%` still calls it.
**`E447: Can't find file "%s" in path` does reach zero here**, and phase 8's check
asserts it *survives* — part G takes its last speaker. The two checks disagree on
purpose, and `apart 8 10` is unnecessary only because `apart 8 9` and `apart 9 10`
already forbid the stage.

### The declared delta: one case and one row

```
10    case:cmd_file
      file
```

`cmd_file` types `:file` with no argument, so what the baselines hold is the CTRL-G
line for `[No Name]` — an editor that answered with the buffer's name. It is
`E492: Not an editor command: file` now, with the **same exit, the same bells and
the same snapshot count**, the stream going 2,310 → 2,327 bytes. The `ref-excmds.txt`
row `file` does not change message: it **ceases to exist**, `tools/zexcmds.py`
enumerating 98 names where it enumerated 99.

**Nothing else can move, and the reason is stronger than a measurement**: every fold
takes the branch the code already took at run time. Measured with
`tools/zcompare.py`: the other 101 screen cases, the other 97 command rows, all 30
command lines, the four pty scenarios and the terminal table are identical —
`:filter` and `:fixdel` among them, and `:q` on a modified buffer (still E37).

### The probes, which are the only evidence a buffer could be named

**21, on both binaries** — the one the phase was handed, built by the edit part from
the boundary's own makefile flags, and the one it made — eight required to move and
thirteen not.

- **`file_rename` is the probe.** `ihello<Esc>:file NEWNAME<CR>` and then CTRL-G:
  the old binary answers `"NEWNAME" [Modified][Not edited] 1 line --100%--` and this
  one `"[No Name]" [Modified] 1 line --100%--`. That line, on the *old* binary, is
  the whole evidence that a buffer could be named, and **the corpus cannot see it**:
  every case types its own text and names nothing. `[Not edited]` is `BF_NOTEDITED`,
  which `rename_buffer()` set and which nothing can set now. `file_bang` is the same
  with `:file!`.
- **`cp_missing` is the only probe that shows the old binary asking the disk.** With
  `nosuchfile` under the cursor, `: CTRL-R CTRL-P <CR>` was **silent** before —
  `find_file_in_path()` stat()ed the name, found nothing and yielded NULL, so nothing
  reached the command line — and answers `E492: Not an editor command: nosuchfile`
  now. Its pair **`cp_existing` must not move and does not**, which is what says part
  G removed the lookup and not the extraction: with `keys` under the cursor — the
  keystroke file `tools/zstream.py` always leaves in the run directory — both
  binaries answer `E488: Trailing characters: eys`, `:k` being a command of its own.
  `cf_existing` is the same session with CTRL-F, which never expanded.
- **Five spellings** — `:f :fi :fil :file :file!` — each E492 now and none before,
  `:file`'s row having given its shortest abbreviation as one character. `:filter`
  and `:fixdel` are the neighbours required not to move, which is the inheritance
  check `CLAUDE.md`'s `:help` → `:helpclose` trap asks for.
- **Thirteen that must not move and do not**: CTRL-G, `g CTRL-G`, `:registers` with
  its table **and without a `"%` or `"#` line**, the `%` and `#` registers,
  `cp_existing`, `cf_existing`, `:filter`, `:fixdel`, `:ls`, `:q` on a modified
  buffer (still E37), `:q!` and an ordinary editing session. Each is required to be
  *doing* something.
- **Two pty sessions**, because every probe above went through a pipe: `:file
  NEWNAME` then CTRL-G, which renames on the old binary and answers E492 and
  `[No Name]` here, and an editing session identical either side.

**Proven able to fail in both directions**: with the new binary on both sides all
eight report *was to move and did not* and add *the input binary did not name the
buffer NEWNAME, so this proves nothing*; with the old binary on both sides they add
*the new binary named the buffer anyway* and *a removed name has been inherited*.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 82,572 | **80,387** (−2,185) |
| functions | 1,803 | **1,743** (−60) |
| type definitions | 981 | 922 |
| enumerators (DWARF) | 1,269 | **1,197** |
| `buf_T` fields | | **−12** |
| `cmdnames[]` rows | 99 | **98** |
| `nm -u`, as `phasecheck.sh` counts it | 69 | **66** |
| binary | 830,440 | **812,744** |

**Three symbols go and the check names the set, not the count**: `stat` was
`mch_getperm()`'s and nothing else's, `getcwd` and `strerror` were `mch_dirname()`'s.
`read`, `close` and `dup` **stay** and are the terminal's alone, and `fsync` is
`ui_write`'s and the `FILE *` phase's; all four are required to be still undefined,
and `open access fcntl chmod fchmod fstat lstat unlink` to be still **absent**, which
is the file-descriptor invariant stated as a check.

**Seventy-two enumerators go and eighty-five renumber, every one of the 85 a
`CMD_`** — the `EXPAND_*`, `WILD_*`, `EW_*`, `XP_BS_*`, `SPEC_*`, `BLOCK0_*`, `BLN_*`,
`ESTACK_*`, `VSE_*` and `VALID_*` families leave as whole anonymous definitions, which
takes no survivor's value with them, and `CMD_file`'s row is what moves the rest.
`cmdnames[]` is designated, so a row lands at its own enumerator whatever the
numbering is — but 85 movers from one family is exactly the case `CLAUDE.md` says a
build is happy to get wrong, so the check dumps DWARF either side and requires it.

The sweep is **4 rounds** and the phase **67 s**. Its boundary is `2829849cb53a`, and
`make zero-verify` recomputes all eleven in 80 s of wall time over 523 s of phases.

### Its placement

`stage 10`, `package files`, and two `uses` lines: `files:10 seed:0 mechanical`,
because the declared records are compared with the baselines phase 0 records, and
`files:10 harness:3 mechanical`, because `:file` went from the CTRL-G line to E492
with the **same exit status** — the old file-based sweep recorded an exit status, so
phase 3's message-level record is what can see this phase at all. **There is no
`files:10 files:7`, `files:10 files:8` or `files:10 files:9` line**, for phase 7's
reason — `tools/packages.sh --check` refuses a `uses` inside one package — and all
three dependencies are real and are stated in the program's head instead: `:read` was
one of the six `EX_XFILE` rows and phase 7 took it, four more went with the `:edit`
family at phase 8, which is what makes `:file` the last and part D possible, and
`set_rw_fname` was `setfname`'s second caller and went with `readfile` at phase 9.

**`need 10 swept`, measured.** The edit's anchor is `b_ffname` at exactly 32
mentions, with `b_sfname` at 26 and `b_fname` at 29. On the text phase 9's *edit*
leaves there are **forty**, `readfile()` still being there to make eight of them, and
the counted anchor refuses: `tools/phaserun.sh zero 9-10` says `b_ffname has 40
mentions, expected 32`. Unlike 7, 8 and 9, the text before it **compiles** — phase
9's edit left valid C — so the refusal is the counted anchor alone.

**`apart 9 10`, measured.** Phase 9's check draws its line against this phase as
counts — `b_ffname` 32, `b_sfname` 26, `b_fname` 29, `setfname` 2, `readonlymode` 3,
`eval_vars` 4, `mch_dirname` 5 and the four write-only fields at 3 each — and names
the four as things phase 10 takes. This phase takes every one to 0. Run on the tree
it leaves, phase 9's check gives eighteen count complaints, `b_ffname has 0 mentions,
expected 32` among them, plus `b_mtime_read is no longer a field of buf_T`, and exits
1. **There is deliberately no `apart 8 10`**, although phase 8's check does fail here
— it requires E447 to survive — because a stage holding 8 and 10 holds 9, and `apart
8 9` forbids that already. It is the shape of the missing `apart 2 6` and `apart 6 8`.

## Phase 11 — `:q` quits, and `ZZ` is `ZQ`

`pipes/zero11-edit.sh` and `pipes/zero11-check.sh`, `stage 11`, `package buffers`.
Phases 6 to 10 took every way to reach a file. What was left of the filesystem in
this editor was a **refusal**: `:q` on a modified buffer answered `E37: No write
since last change (add ! to override)` and stayed. The protection has no remedy once
nothing can be written — there is no `:w` to answer it with and no file the text
could have come from — so it is a door onto nothing, and this phase takes it. `:q`,
`:q!`, `ZZ` and `ZQ` are one thing afterwards.

### One anchor, and eleven of the sixteen functions are a surprise

`ex_quit()` is `if ((check_changed(…)) || (check_changed_any(…))) { not_exiting(…); }
else { getout(0); … }`, and the test *is* the refusal. Folding it **never** keeps
the `else` — quit — and is the last reference `check_changed()` has. That single
fold is the phase; the edit names not one function.

**Fifteen functions follow by reachability and eleven of them are not the refusal at
all.** `check_changed_any()`'s tail is *"go to the buffer that refused"* — it calls
`set_curbuf()`, which calls `enter_buffer()` and `win_enter_ext()` — and after whim
removed the buffer list and the window commands, **that tail was the last caller of
the whole switch-buffer/switch-window island**: `add_bufnum`, `set_curbuf`,
`enter_buffer`, `win_enter`, `win_enter_ext`, `goto_tabpage_win`, `goto_tabpage_tp`,
`get_winopts`, `find_wininfo`, `buflist_findfpos` and `buflist_getfpos`. After this
phase the editor has no code for entering a different buffer or a different window.

**The island is a graph and not a fan, and the edit computes that before it folds
anything.** Only `add_bufnum`, `set_curbuf` and `goto_tabpage_win` are called by
`check_changed_any` itself; the other eight hang off those. So what is required is
that *every* call to any of the eleven is inside `check_changed_any` or inside
another of the eleven — and a check that asked for the simpler shape would fail on a
correct phase. Three of the fifteen also have **no prototype**, being defined above
their first call (`check_changed_any` and `no_write_message_nobang` at two mentions,
`add_bufnum` at three for having two calls), so a loop that wanted three for all of
them refuses. Both facts were discovered by the counted anchors refusing.

### Two extras, each measured byte-identical in the recording

**A — two struct fields that become write-only, which no tool can see.** This is
phase 7's `usefilter` judgement in a smaller shape: `deadfields.py` removes a field
nothing *names*, and gcc has no warning for a member that is only written.
`win_T.w_topline_was_set`'s only reader was in `enter_buffer()` and
`wininfo_S.wi_changelistidx`'s only reader was in `get_winopts()`. The declaration
and the one surviving write of each go by hand, and **the text the edit leaves does
not compile** — both readers are still there, inside functions the sweep is about to
take — which is said in the program rather than discovered, as `pipes/zero7-edit.sh`
says of its own.

**B — the tail that cannot run.** After the fold `ex_quit()` ended `int save_exiting
= exiting; exiting = TRUE; getout(0); not_exiting(save_exiting);`. `getout()` sets
`exiting = TRUE` **itself** and ends in `mch_exit()`, which never returns, so the
first, second and fourth statements are dead and gcc cannot prove it. Replacing the
four with `getout(0);` orphans `not_exiting()`, and **`not_exiting()` is the refusal
machinery** — `exiting = save_exiting; settmode(TMODE_RAW);`, the "we changed our
mind, put the terminal back" — so it is this phase's and not tidy. The fold is right
only because `getout()` sets `exiting` for itself; check that before making it on
another tree.

### What survives, and why a check copied from phases 6 to 10 fails here

* **The buffer still knows it is modified.** `bufIsChanged` goes 10 → 7 and
  `curbufIsChanged` does not move at all: CTRL-G still prints `[Modified]`, the
  status line still draws `[+]`, `:set modified?` still answers. What went is the
  refusal, not the state.
* **`:q` can still decline.** `text_locked()`, `curbuf_locked()` and
  `before_quit_autocmds()` all return early **above** the anchor and are untouched.
* **Phases 6, 7, 8, 9 and 10 each assert `E37: No write since last change` survives**
  and name `check_changed` as the `:q` phase's. This is the `:q` phase, so the check
  asserts the opposite in both directions: E37 must be absent here and must have been
  present in the input. `apart 10 11` records it.
* **`open_buffer` goes 5 → 4** — `enter_buffer()` was one of its four callers — where
  phases 9 and 10 both pin it at 5. `buf_spname` goes 5 → 4 and `exiting` 17 → 13.
* **`p_wh` looks write-only and is not.** It goes 4 → 2, the two reads inside the
  island having gone, and what is left is its declaration, which carries the
  initialiser, and one real reader in the frame layer. A naive "uses − writes − 1 ≤ 0"
  scan reports it; the check's scan excludes the declaration **by position** and then
  reports nothing but `vim_ignored`, upstream's sink for an ignored return value,
  which is write-only in the input too. Running it on both texts and requiring the
  same set is what stops an empty answer being a broken scan rather than a clean phase.
* **`SHM_FILEINFO` leaves**, and it is the `'shortmess'` `F` letter: its only reader
  was inside `enter_buffer()`. The letter is accepted and inert afterwards. That is
  the options phase's and no flag string is touched here.
* **`ZZ` is already `ZQ` and stays so.** `nv_Zet` has run `do_cmdline_cmd("q!")` for
  `case 'Z'` and for `case 'Q'` since phase 6. The strings are **not** rewritten to
  `"q"`: it would move `zz_key` and `zq_key` for no gain, and `case:zz_key` is phase
  6's declaration.
* **There are no `'confirm'`-style prompts to worry about**: `grep -cw confirm` on the
  input is 0, whim having removed the dialog layer. Said out loud so that the next
  reader does not go looking.

### Twelve enumerators go and nothing renumbers

`typereach.py` takes twelve as whole anonymous definitions — the four `CCGD_`, the
two `DOBUF_`, `SHM_FILEINFO` and the five `WEE_` — and a whole definition leaving
takes no survivor's value with it. The check dumps DWARF either side and requires
exactly that: **1,197 → 1,185, not one survivor renumbered and none arriving.** That
is the opposite of phase 10, where 85 moved, and it is worth the four seconds either
side to say rather than assume. **No `cmdnames[]` row and no `nv_cmds[]` row moves**:
98 rows, `names()` reads 98, the `static_assert` is in place and `nvidxcheck` reports
194.

### The declared delta: one case and one row, and the row is a third kind

```
11    case:quit_modified
      quit
```

`quit_modified` types text and then `:q`, so what the baselines hold is an editor
that refused: the E37 line goes, the one bell with it, and the record loses a
snapshot — 2,342 → 2,213 bytes. **The exit status does not move there, and that is
the corpus's limit rather than the phase's**: every `zcases.py` case ends with a
trailing `:q!`, which quits the old binary too.

The `ref-excmds.txt` row `quit` **changes message and does not cease to exist**,
unlike every row phases 6 to 10 declared: `:quit` is still a command with its row, so
`tools/zexcmds.py` enumerates the same 98 names and compares the block, whose `msgs`
go from `:set nopaste / E37… / :q!` to `:set nopaste / :quit`. The `cquit` row does
not move. Measured with `tools/zcompare.py`: the other 101 screen cases, the other 97
command rows, all 30 command lines, the four pty scenarios and the terminal table are
identical.

### The probes, which are the only evidence the refusal went

Seventeen, on both binaries — the one the phase was handed, built by the edit part
from the boundary's own makefile flags, and the one it made — six required to move
and eleven not.

* **`q_alone` is the probe.** `ihello<Esc>`, `:set nopaste`, `:q` **and nothing after
  it**. The old binary draws E37, runs out of stdin, prints `Vim: Finished.` and exits
  **1**; this one quits on the `:q` and exits **0**. That difference is the whole
  phase measured from outside and no recording can see it.
* **Five more spellings of the same refusal** — `:q` with the trailing `:q!` (the
  declared case), `:1q`, `:qu`, `:quit`, and `x` then `:q` — each required to have
  refused **before** and not to now, and each to lose the E37 snapshot. `q_modified`'s
  bells must go 1 → 0.
* **Eleven that must not move and are required to be *doing* something**: `q_clean`
  (`:q` on an **unmodified** buffer, status 0 either side and no E37 anywhere — it
  took the else arm before this phase and takes it now, which makes it `q_alone`'s
  pair), `q_bang`, `zz_key` and `zq_key` — which must also be identical **to each
  other** — `cquit` (exit 1 either side), `ctrl_g` (must say `[Modified]`),
  `cmd_set_ro`, `cmd_set_mod` (`:set modified?` must answer), `reg_list`, `cmd_undo`
  and an ordinary editing session.
* **A real terminal**, because every probe above went through a pipe: `ityped<Esc>`,
  `:q`, `:q!`. On the old binary the `:q` draws E37 and leaves the editor running, so
  the `:q!` is what ends the session; here the `:q` quits and the `:q!` reaches
  nothing. An ordinary pty editing session beside it is identical either side.

**Proven able to fail in both directions**: with the new binary on both sides all six
report *was to move and did not* and add *the input binary did not refuse, so this
proves nothing about a refusal being removed* and *exited 0, expected 1*; with the old
binary on both sides they add *this binary still refuses* and *exited 1, expected 0*.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 80,387 | **79,866** (−521) |
| functions | 1,742 | **1,726** (−16) |
| type definitions | 922 | 910 |
| enumerators (DWARF) | 1,197 | **1,185** |
| struct fields | | **−2**, by hand |
| `cmdnames[]` rows | 98 | 98 — untouched |
| `nm -u`, as `phasecheck.sh` counts it | 66 | **66** |
| binary | 812,744 | **804,360** |

**Nothing is freed, and the check states it as an equality** — a `cmp` of the whole
undefined set, so a symbol *arriving* fails too. Sixteen functions go and not one was
libc's last caller: the refusal printed through `emsg()` and the island moved windows,
neither of which reaches the C library on its own. `fclose`, `getc`, `putc` and
`fsync` are required to be **still** undefined and are the `FILE *` phase's; `open`,
`access`, `fcntl`, `stat`, `getcwd` and `strerror` to be still **absent**.

The sweep is **3 rounds** and the phase **97 s**. Its boundary is `b81ce6372fc4`, and
`make zero-verify` recomputes all twelve in 107 s of wall time over 629 s of phases.

### Its placement

`stage 11`, `package buffers` — the first phase of a package of its own — and two
`uses` lines: `buffers:11 seed:0 mechanical`, because the two declared records are
compared with the baselines phase 0 records, and `buffers:11 files:6 rationale`,
because the refusal has no remedy once nothing can be written: phase 6 took every
`:write`, so E37 asked for a save the editor no longer had any way to perform.

**`need 11 swept`, measured, and the brief that specified this phase said there was
none.** The invariant the whole phase rests on is that every call to any of the eleven
island functions is inside `check_changed_any` or inside another of the eleven. On the
text phase 10's *edit* leaves that is **false**: `buflist_findlnum()` is still there to
make `return buflist_findfpos(buf)->lnum;`, a call from outside the island, and phase
10's sweep is what takes it — so `buflist_findfpos` has four mentions where the anchor
wants three. `SHM_FILEINFO` refuses first, at 3 where it wants 2, `ex_file()` still
being there to read the `'shortmess'` `F` letter: `tools/phaserun.sh zero 10-11` says
`SHM_FILEINFO has 3 mentions, expected 2`. Unlike 7, 8 and 9 the text before it
**compiles** — phase 10's edit left valid C — so the refusal is the counted anchors
alone.

**`apart 10 11`, measured.** Phase 10's check pins `check_changed` at 4,
`no_write_message` at 3, `buf_spname` at 5 and `open_buffer` at 5, and requires `E37:
No write since last change` to survive. Run on the tree this phase leaves it gives
five complaints — `check_changed has 0 mentions, expected 4` among them, and `E37
went, and check_changed() is the :q phase's` — and exits 1. **Only `apart 10 11` is
written**, and the four before it are implied: a stage holding 6 and 11 holds 10, so
that line forbids it already. It is the shape of the missing `apart 2 6`, `apart 6 8`
and `apart 8 10`.

## Phase 12 — the options nothing reads

`pipes/zero12-edit.sh` and `pipes/zero12-check.sh`, `stage 12`, `package options`.
Phases 6 to 11 took every way to reach a file and then the refusal that guarded the
text. What they left behind is a set of **settings**: `options[]` rows whose global
nothing reads any more, so that `:set fsync?` answers a question about machinery that
is not there. An option that cannot do anything is a lie, and the same argument that
removed `:write` removes `'write'`.

### Which rows go is computed, not listed

The edit walks `options[]`, finds each row's `(char_u *)&p_xx` and counts readers of
that global outside the row, with `tools/dropoptions.py --strict`'s own exclusions —
another row, the row's `var` field, the variable's declaration (which is what the row
initialises), and taking the address, which asks which option a pointer refers to and
never touches the value. **Exactly seven of the 114 rows have no reader**, and the
program requires that set rather than naming six of them:

| row | var | indir | verdict |
| --- | --- | --- | --- |
| `fsync` | `p_fs` | `PV_BOTH` | goes, after `droplocal.py b_p_fs` |
| `modified` | `p_mod` | `PV_BUF` | **stays** |
| `prompt` | `p_prompt` | `PV_NONE` | goes |
| `readonly` | `p_ro` | `PV_BUF` | goes, by `ZERO-PLAN.md` decision 5 |
| `undoreload` | `p_ur` | `PV_NONE` | goes |
| `write` | `p_write` | `PV_NONE` | goes |
| `writeany` | `p_wa` | `PV_NONE` | goes |

**`'modified'` has no reader of `p_mod` either and must not go.** Decision 5 keeps it:
the state it reports lives in `b_changed`, not in `p_mod`, so `:set modified?` answers
correctly and the row is not a lie. A computation that took "no reader" as the
criterion would delete it, which is why the seven are computed and the six are
*chosen*. `dropoptions.py` refuses it anyway, on the `PV_` guard. It is now the only
option row with no reader of its own global.

**`'prompt'` is the find, and `ZERO-PLAN.md`'s row 11 computed four.** Its only reader
was `getexmodeline()`'s `if (p_prompt) msg_putchar(':');`, so it is **zero phase 4's
orphan**, collected here — which is a `uses` line the plan does not have.

**`'paste'` is exempt for ever**, and that is asserted rather than only written down:
`p_paste` has 12 mentions before and after, its five save slots `p_ai_nopaste`
`p_et_nopaste` `p_sts_nopaste` `p_tw_nopaste` `p_wm_nopaste` four each, and the edit
refuses outright if the computation ever offers `'paste'`. `+{command}` is likewise
untouched. That is the user's standing promise (`ZERO-PLAN.md` 2d and decision 8), and
the next person to widen the computation meets the assertion and not just a comment.

### Four parts, and only one of them is live code

**A — four clean rows**, `dropoptions.py --strict prompt undoreload write writeany`.
The sweep then takes the four globals as `-Wunused-variable`.

**B — `'fsync'`, which `--strict` alone refuses**, and not on a reader: the row is
`PV_BOTH + PV_BUF + BV_FS`, so the tool stops on the `PV_` guard, because *the row is
what initialises the global* (`'tagcase'` taught that by segfaulting before the first
keystroke). `droplocal.py b_p_fs` is the other half and goes first — six plumbing
sites, including `get_varp()`'s two-line "local if set" form — then `--strict --local
fsync`.

**C — `'readonly'`, which is live code and not an inert row.** `p_ro` the global has
had no reader since whim; what survives is the buffer-local `b_p_ro`, at ten mentions,
and since phase 6 nothing but `:set ro` can set it, which is decision 5's premise.
Five edits, in this order and for this reason:

1. **the W10 warning.** `change_warning()` and its six call sites, each one statement
   on a line of its own. There is **no prototype** — it is defined above its first
   call — so a program that removes one fails loudly. This also takes the
   `ui_delay(1002L, TRUE)` that phase 2 named as one of the eight other pauses, and
   the `static char *w_readonly` inside the function.
2. **the `[RO]` in `fileinfo()`.** The format string and the argument move
   **together**, `%s%s%s%s%s%s` to `%s%s%s%s%s`, and nothing in the build checks a
   `vim_snprintf_safelen` count.
3. **the `[RO]` on the status line**, in `win_redr_status()`: the name-padding
   disjunct and the block that appends the indicator.
4. **`did_set_readonly()`, by name and with the reason.** It is the row's callback and
   the row is its only other reference, so the sweep would take it — but `droplocal.py`
   runs in the *same edit* and would find it still reading `b_p_ro`. Measured without
   it: `droplocal: b_p_ro still has 1 mentions after the plumbing went`, which is the
   tool working. The alternative is an inner sweep; this is cheaper and honest.
5. the row, then `droplocal.py b_p_ro` — three plumbing sites.

**D — what the sweep then finds**: `SHM_RO`, `BV_FS`, `BV_RO`, `w_readonly`, the six
globals, and the `b_did_warn` field — which becomes dead **only after both**
`change_warning` and `did_set_readonly` have gone. Remove one and it is a field with
one reader and one writer, which no tool reports.

### The flag letters are not touched, and that is a decision

`'cpoptions'` and `'shortmess'` each have a **validity list that is a separate string
literal from the value**, so removing a letter from a list cannot move `:set cpo?` or
`:set shm?`. But it *would* turn `:set shm=F`, accepted silently, into `E539: Illegal
character`, and no corpus case, Ex row, argv row or pty scenario types `:set shm=` —
which is exactly the kind of change rule 2 exists to prevent. Accepting a letter that
does nothing is what upstream does for every feature a build lacks.

Measured: **23 of `'cpoptions'` 60 letters and 14 of `'shortmess'` 23 are inert** — in
a validity list with no enumerator of that value — and **this phase makes exactly one
more so, `'shortmess'`'s `r`**, whose `SHM_RO` goes with the `[RO]` indicator. Both
literals are asserted character for character, the inert sets are computed either side
and required to differ by exactly `{r}`, and four probes require `:set shm=F` and
`:set cpo=g` to be accepted silently on **both** binaries and `:set shm=y` and `:set
cpo=h` to answer E539 on both.

### The row floor, which this phase crosses

`tools/orphanopts.py` refused a table it parsed fewer than 100 distinct `&p_xx` out
of; this phase takes the count **102 → 96**, and its first call crosses it.
`tools/zerodelta.sh` runs that tool beside its harnesses, so crossing the floor does
not fail *this* phase — it fails the delta check of **every zero phase after it**, with
a message about a table that moved. It is the same failure shape as
`create_cmdidxs.py`'s 100-row floor at phase 8, arriving from a different table.

**The floor is 80 now, lowered in this phase's own commit**, with the reason in the
tool's docstring — the same number and the same argument as `create_cmdidxs.py`'s, so
that the two floors stay one idea. 80 leaves 16 globals of margin below 96 and the
plan removes no further rows. The check proves it **by using it**, not by grepping for
the number: the tool must not refuse, and its output on this source must be
byte-identical to its output on the input — five non-pointer orphans, which are
`'paste'`'s save slots, and every option pointer still with the row that sets it.

**It cost implementation keys, and that is stated rather than hidden.** `tools/whimdelta.sh`
names `orphanopts.py` and `tools/implhash.sh` hashes what a delta checker names, so
lowering the number re-keys whim and zero. Measured, before and after, over every
whim stage, every whim phase-as-unit, every whim edit, every slim phase and every zero
unit and edit: **12 whim stage keys, 4 whim edit keys, 82 whim phase-as-unit keys, 12
zero unit keys and 3 zero edit keys move, and not one slim key.** The tool's *verdict*
is unchanged everywhere — `slim-vim.c`, `whim-vim.c` and every zero boundary are far
above either floor, and the output is byte-identical — so no boundary can move; the
cost is CPU in a repass. `make whim-verify` and `make slim-verify` are the gate
`ZERO-GOAL.md` rule 9 asks for, and both were run.

### The declared delta is nothing at all, and the reason is not phase 9's

Phase 9 removed code that **could not run**. This phase removes code that **can run
and that the instrument cannot see**. Measured record by record:

* `:set <name>?` goes from an answer to `E518: Unknown option`, and **no recorded case
  or row asks any of the six.**
* **bare `:set` does not move**, because none of the six differs from its default, and
  its listing is wiped by the Press-ENTER redraw before `zscreen.py` takes its picture.
* **`:set all` does move** — `readonly`, `fsync`, `prompt` and `undoreload` are in the
  old stream and absent from the new — and `:set all` is in no harness. It is a probe.
* **the W10 warning and the two indicators move**, and no recorded case sets
  `'readonly'`: they need `:set ro`, which nothing types.
* `tools/zexcmds.py` records `exit`, `bells`, `stderr`, `text` and `msgs` for the `set`
  row and **no stream digest**, so even a change to what `:set` prints in the stream
  would be invisible there.

So a phase that did nothing and a phase that did everything have the same recording.
`diff -rq` over two full recordings — the binary the phase was handed against the one
it made — is **empty**, and `tools/zerodelta.sh --phase 12` finds the nine lines phases
2 to 11 declared and nothing new. `pipes/zero.delta` gets a comment and no line.

### The probes, which are not a supplement but the check

**Twenty-seven, on both binaries**, thirteen required to move and fourteen not.

* **`ro_w10` is the one that shows behaviour going rather than a row.** `:set ro` on an
  **unmodified** buffer, then an insert: the old binary prints `W10: Warning: Changing
  a readonly file` and **pauses a second** — 1,006 ms measured against 2 ms here, the
  same shape as phase 2's 2,010 ms → 5 ms. The message is never in a snapshot: it is
  drawn, a Press-ENTER follows and the redraw wipes it, exactly as `zero7-check`'s
  E319, so the assertion is on the *stream* and on the elapsed time. The buffer must be
  unmodified when `:set ro` runs — `change_warning()` returned early on `b_did_warn ||
  curbufIsChanged()` — so a probe that types its seed first shows nothing on either
  binary.
* **`ro_ctrlg`** (`[readonly]`, not `[RO]`, because `'shortmess'`'s default has no `r`),
  **`ro_shm_r`** (`:set shm=r` first, the only probe that reaches `SHM_RO`) and
  **`ro_statusline`** (`+set laststatus=2`, which `win_redr_status` is reached by
  nothing else here).
* **`set_all`**, and the six `:set <name>?` spellings plus `:set readonly` and `:set
  ro`, each an answer before and `E518: Unknown option` after.
* **Fourteen that must not move and are required to be *doing* something**:
  `paste_roundtrip` (the exempt option, which the whole corpus depends on),
  `mod_query`, `shm_query`, `cpo_query`, `shm_F`, `shm_bad`, `cpo_g`, `cpo_bad`,
  `nu_query`, `bare_set`, `set_listing`, `ctrl_g` (still `[Modified]`), `undo_case`
  and an ordinary editing session.

**Proven able to fail in both directions**: with the new binary on both sides all
thirteen report *was to move and did not* and add *the input binary did not warn* and
*took 10 ms … under half a second means it never drew it*; with the old binary on both
sides they add *this binary still warns*, *took 1,006 ms, so something is still
pausing* and *`:set ro` does not answer E518 now, so something can still mark a buffer
read only*.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 79,866 | **79,757** (−109) |
| functions | 1,726 | 1,724 (−2) |
| type definitions | 910 | 909 |
| enumerators (DWARF) | 1,185 | **1,182** (−3, nothing renumbers) |
| struct fields | | **−3** (`b_p_fs`, `b_p_ro`, `b_did_warn`) |
| `options[]` rows | 114 | **108** |
| distinct `&p_xx` in `options[]` | 102 | **96** |
| `cmdnames[]` rows | 98 | 98 — untouched |
| `nm -u`, as `phasecheck.sh` counts it | 66 | **66** |
| binary | 804,360 | **803,912** |

**Nothing is freed, and the check states it as an equality** — a `cmp` of the whole
undefined set. An option row is not a libc call, and `fsync` is still reached from
`ui_write()` and is the `FILE *` phase's.

**Three enumerators go and nothing renumbers, and `BV_RO` is why it needs saying**: it
is *unpinned*, so `BV_SI`, the next survivor, would follow it down. `tools/deadenums.py`
pins `BV_SI = 53` in the sweep and `enumvals.sh --verify` reports it there; the check's
independent dump either side requires `BV_SI` to hold its value and no other survivor
to move. `BV_FS` had an explicit value and so does its successor.

The sweep is **2 rounds** and the phase **37 s**. Its boundary is `fbaa6d80884b`.

### Its placement

`stage 12`, `package options`, and four `uses` lines: `options:12 seed:0 mechanical`,
because the declaration is "none" and "none" is checked against phase 0's baselines;
`options:12 files:6 mechanical` (`'write'`, `'writeany'` and `'fsync'` were
`do_write`'s, `not_writing`'s, `check_overwrite`'s and `buf_write`'s, and phase 6 left
`:set ro` as the only thing that could mark a buffer read only); `options:12 files:8
mechanical` (`'undoreload'` was read by `do_ecmd`); and **`options:12 streams:4
mechanical`, which the plan does not have** — `'prompt'`'s only reader was
`getexmodeline()`.

**`need 12 swept` is not required, and it was measured rather than assumed.**
`tools/phaserun.sh zero 11-12` runs phase 12's edit on the unswept text phase 11's edit
leaves, and every counted anchor matches: the same seven rows come back from the
computation and the cut ends at the same 108 rows and 96 globals. The run fails only
on the edit's build of its input binary, which is true of every zero edit that builds
one and is not declared for that reason.

**`apart 11 12`, measured.** Phase 11's check pins `p_ro` and `p_ur` at 2 mentions
**with their option rows** and says in as many words that removing one is the options
phase's. Run on the tree this phase leaves it gives six complaints — `p_ro has 0
mentions, expected 2`, `'readonly' lost its option row, and that is the options
phase's`, `curbufIsChanged has 6 mentions, expected 7` (`change_warning`'s early return
read it) and `the function count went 1742 -> 1724, expected 1742 -> 1726` among them —
and exits 1. Phase 10's check pins the same two rows and would fail too, but a stage
holding 10 and 12 holds 11 and `apart 10 11` forbids that already.

## Phase 13 — no `FILE *` that is never opened

`pipes/zero13-edit.sh` and `pipes/zero13-check.sh`, `stage 13`, `package tidy`. Two
`static FILE *` survive in this editor and **nothing has ever opened either of them in
any build of `zero-vim`**: `scriptin[NSCRIPT]`, which `-s {scriptfile}` filled and for
which whim removed the option, and `redir_fd`, which `:redir > file` filled and for
which whim removed the command. So this phase removes the **possibility** rather than
a behaviour — phase 9's situation and phase 9's answer.

### The counts are the argument, and each is computed before anything is folded

* **`scriptin[]` is assigned in exactly one place in the whole file**, and that place
  is `scriptin[curscript] = NULL;` inside `closescript()`. So it is NULL for ever.
* **`redir_fd`'s only assignment is its own declaration**, `= NULL`.
* **`ui_write()` has three mentions** — a prototype, a definition and one call — and
  that call passes `FALSE` for `console`.

The edit asserts all three as exact text before it folds anything, because every fold
rests on them; a fourth assignment anywhere would make every one a guess.

### Six anchors, in three groups

**A — `scriptin[]` is NULL for ever.** `may_sync_undo()` and `is_safe_now()` each lose
one conjunct and **survive**: `u_sync()` still runs on the same condition, and
`is_safe_now()` is still `stuff_empty() && typebuf.tb_len == 0 && !global_busy`.
`using_script()` is FALSE at both call sites — a `&& !using_script()` conjunct and a
`|| using_script()` disjunct — and the sweep then takes it. And `inchar()`'s script
reader goes as text with its local, after which `if (script_char < 0)` is always true
and folds; **that fold is what takes `closescript()`'s only caller**, and `fclose` and
`getc` with it.

**B — `redir_fd` is NULL for ever**, so `redirecting()` is FALSE always and folds at
both call sites, in `undo_cmdmod` and inside `redir_write()`. **Their indentation
differs**, which is what makes two separate one-count patterns honest rather than a
count of two over one pattern. The second fold takes the whole `fputs`/`putc` block.

**C — `ui_write()`'s `console`** is FALSE at its one call site, so the `vim_fsync(1)`
it guards can never be entered. **The parameter goes too**, and that is what makes the
cut honest: leaving it would leave `__attribute__((unused))` on something that will
never be read again — phase 2's argument for `check_tty(void)` — and `tools/sweep.sh`
compiles with `-Wno-unused-parameter`, so an unused parameter is invisible where an
unused local is not. `vim_fsync()` is then uncalled and `fsync` goes.

### Two locals are folded by hand and no tool covers either

**`retesc`** is written only inside the loop anchor A4 deletes and read once.
Afterwards it is a local that is **read and never written**: gcc has no warning for
that, `deadsweep.py` acts on warnings, and leaving it would mean `inchar()` returns an
uninitialised value on a path the compiler thinks exists. `return retesc;` becomes
`return FALSE;` and the declaration goes. It is folded **after** the two declarations
and **before** `fold_always`, because the fold dedents the body it keeps and a rewrite
counted against the original indentation refuses afterwards — which it did, the first
time this was run.

**`did_return`** is the same shape one level down: the `if (!did_return)` block the
`redir_write` extra removes is its only reader, and an `if` with an empty body is not
something any tool here removes either, so the block goes whole with `cutil.drop_if`
and the variable's two lines with it.

### The recommended extra is taken, and a second is declined

After B, `redir_write()` is `{ char_u *s = str; static int cur_col = 0; if (redir_off)
return; }` — the sweep takes the two variables and leaves a function with five callers
that cannot do anything. Leaving it is the "concept the table has and the code does
not" that whim's Phase 18 argued against, so it goes with its five call sites, and
`redir_off` — then written **five** times, not four, and read never, a file-scope
static that no warning covers — goes with them. `msg_puts_attr_len()`'s call was every
message the editor prints, and that is the one to notice: nothing is printed
differently, because `redir_write()` returned without doing anything at every one of
them.

**A second extra is declined and is a question for the user, not an oversight.** After
this phase `typedef struct stat stat_T;` has no user and `#include <sys/stat.h>` and
`#include <fcntl.h>` are needed by nothing. Removing all three is free and was
measured — same binary, byte-identical recording, four fewer lines — but it would be
**the first time any zero phase changes the directive count**, and the charter above
says `zero-vim.c` "inherits 18 directives from `whim-vim.c`". That sentence is a
statement about the pipeline, so the change belongs to whoever decides it, either here
or as an includes phase of its own. The count stays **18**.

**The user took it, as phase 16, and that phase found the paragraph above short by a
header and by a line.** There is a third that supplies nothing — `<iconv.h>`, whose
only occurrence in `zero-vim.c` is its own `#include` line, whim having removed the
conversion layer and left it — and the cut is five lines and not four, because the
typedef sits between two blank lines and one of them has to go with it. So the answer
here was **15 directives**, not 16, and phase 16 takes six because phases 14 and 15
emptied three more. The decision to decline was right for its reason: the charter now
says in as many words that a phase may remove a directive and may not add one.

### The honest problem, and the probe that answers it

Nothing this phase removes is reachable, so there is **no behavioural must-differ
probe** and no dishonest one is offered instead. The check builds the source the phase
was handed, twice:

- **probe** — `(void)write(2, "FILESTAR-ENTERED\n", 17);` at **five** places: the top
  of `closescript()`, inside `inchar()`'s `getc(scriptin[curscript])` loop, inside
  `redir_write()`'s `redirecting()` block, inside `undo_cmdmod`'s, and the top of
  `vim_fsync()`. **0 of the 106 records** carry the marker.
- **ctl** — the *identical* instrument at the top of `ui_write()`, which every byte
  the editor draws goes through. **105 of the same 106** carry it.

The zero is the claim; the 105 is what makes it a probe that can fail. **Proven able
to fail, by measurement**: with the instrument moved to `ui_write()` in the probe
build, the recording carries the marker in 105 of 106 records and the check reports
*105 of 106 records ENTERED one of the five sites on the binary this phase was handed*
and exits 1.

**Eighteen adversarial sessions** run on both instrumented binaries, and every one of
them is a way of making the editor **print**, which is where `redir_write()` sat —
`msg_puts_attr_len()` called it for every message. `:messages`, `:verbose set ai?`,
`:silent echo`, `:history`, `:registers`, `:display`, `ga`, an unknown command, `:set
all`, `:marks`, `:undolist`, `:changes`, `:map`, `:highlight`, `:normal ihi`,
`:g/a/p`, a recorded-and-replayed register and `:set verbose=9`. **Each reached
`ui_write()` and not one reached any of the five** — and the first half is checked
too, because a session that draws nothing is not an adversary.

### The declared delta is nothing at all, measured twice over

`diff -rq` over two full recordings — the binary the phase was handed against the one
it made — is **empty**: all 102 screen cases, all 111 Ex-command rows, all 30 command
lines, the four pty scenarios and the nineteen terminal rows. `tools/zerodelta.sh
--phase 13` then finds the same against whim-vim's frozen baselines, with the nine
lines phases 2 to 11 declared and nothing new. `pipes/zero.delta` gets a comment and
no line. Nine ordinary sessions run directly between the two binaries and each is
required to be identical **and** to be doing something.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 79,757 | **79,603** (−154) |
| functions | 1,724 | 1,719 (−5) |
| type definitions | 909 | 908 |
| enumerators (DWARF) | 1,182 | 1,181 (`NSCRIPT`, nothing renumbers) |
| `FILE` mentions | 2 | **0** |
| `#include` | 18 | 18 — untouched |
| `nm -u`, as `phasecheck.sh` counts it | 66 | **62** |
| `nm -u` with zero's own flags | 65 | **61** |
| binary | 803,912 | **799,816** |

**Four symbols go and the check names the set, not the count**: `fclose` and `getc`
were `closescript()`'s and `inchar()`'s script loop's, `putc` was `redir_write()`'s,
and `fsync` was `vim_fsync()`'s — whose only caller was `ui_write()`'s `console`
branch, which is why **`fsync` is this phase's and not the buffer-name phase's**.

**`fputs` does not go, and `ZERO-PLAN.md` row 12 says it does.** After this phase the
source names it nowhere and `nm -u` still lists it: gcc lowers `fprintf(stderr, "…")`
to it, exactly as it lowers `printf` to `fputc`, `fwrite` and `putchar`. The check
asserts the freed set as exactly `fclose fsync getc putc`, with `fputs fputc fwrite
putchar __errno_location` named as gcc's own and required to be **still** undefined.

**`ZERO-PLAN.md` §4b's invariant is assertable in its strongest form now**, and the
check states it: `open creat openat stat access fcntl getcwd strerror fopen fdopen
opendir` are absent from **both** the source and the undefined set. The core has no
`open`, no `stat`, no stdio stream and no fourth descriptor — it can read, write,
close and dup fds 0, 1 and 2 and nothing else.

The sweep is **3 rounds** and the phase **37 s**. Its boundary is `f995296f2536`.

### Its placement

`stage 13`, `package tidy`, and two `uses` lines: `tidy:13 seed:0 mechanical`, because
the "none" is checked against phase 0's baselines, and `tidy:13 terminal:2 rationale`,
because `ui_write()`'s `console` argument is FALSE at its one call site either way and
phase 2 is where the terminal stopped being asked anything — so dropping the parameter
rather than leaving `__attribute__((unused))` on it is that phase's argument for
`check_tty(void)`.

**`need 13 swept` is not required, and it was measured**: phase 13's edit applies
unchanged to the *unswept* text phase 12's edit leaves, every counted anchor at the
same number. The run fails only on the edit's build of its input binary, which is true
of every zero edit that builds one.

**`apart 12 13`, measured.** Phase 12's check pins `scriptin` at 8 mentions, `redir_fd`
at 6 and `vim_fsync` at 3 and names all three as the `FILE *` phase's; it also requires
`fclose`, `getc`, `putc` and `fsync` to be **still** undefined. Run on the tree this
phase leaves it gives three complaints — `redir_fd has 0 mentions, expected 6`,
`scriptin has 0 mentions, expected 8`, `vim_fsync has 0 mentions, expected 3` — and
exits 1. Its symbol check would fail too, being a `cmp` of the whole undefined set
against a phase that frees four, but the source assertions come first. Phase 11's check
pins the same three and would fail as well, but a stage holding 11 and 13 holds 12 and
`apart 11 12` forbids that already.

## Phase 14 — the strings are the editor's own

`pipes/zero14-edit.sh` and `pipes/zero14-check.sh`, `stage 14`, `package vendor`.
Seventeen of the 61 libc symbols zero-vim still asked for are string and memory work,
and every one of them is **pure computation**: no descriptor, no clock, no signal,
nothing the host owns. So they are not a boundary to move, they are code the file can
simply contain. This phase brings sixteen of them in as `static musl_*` functions
written from `/root/musl/src/string/`, and moves the seventeenth — `sprintf` — onto
the printf this editor already carries. `nm -u` goes **61 → 44** and the recording
does not move at all.

### The measurement the phase turned on, and it was the open question

**gcc emits calls to `memcpy` and `memset` for itself**, for aggregate assignments and
large zero initialisers, whatever the source calls. So renaming every call site might
have left both symbols undefined and forced a definition under the **real** name — and
a definition of `memcpy` cannot be `static` without the question of whether gcc's own
emitted call still binds to it, which is the "nothing is global but `main()`"
invariant at stake. Measured on this file and it does not happen: after the rename
`gcc -S` contains **not one call to any of the seventeen**, and all seventeen leave
`nm -u`.

Two things make that a bound rather than luck, both measured. gcc's `-O0` inline-copy
threshold is **between 8 KiB and 16 KiB** — an 8,192-byte struct assignment is
inlined, a 16,384-byte one calls `memcpy`. And `-Wlarger-than=8192` on `zero-vim.c`
reports **exactly one** object above 8 KiB, `options[]` at 13,536 bytes, which is a
table nothing assigns whole, while `-Wframe-larger-than=8192` reports none. The check
asserts the absence from the **assembly** as well as from `nm -u`, so a later phase
that adds a big aggregate and assigns it whole fails loudly rather than quietly
reacquiring a libc symbol.

**Measured and not taken:** `-fno-builtin` and `-ffreestanding` each *add* `abs
fprintf labs` and remove `fputc fputs fwrite putchar` — a different set, not a smaller
problem, and none of it this phase's. `ZEROCFLAGS` is untouched, so this phase edits
no makefile and `zero.mk` needs no change. **And, for the record, because it was the
question asked:** a `static` definition *does* satisfy gcc's own emitted call — a
64 KiB struct assignment beside `static void *memcpy(…)` compiles to `call
memcpy@PLT` and the object has no undefined symbols at all. The escape hatch existed
and was not needed.

### `sprintf` is two populations, and the split is the whole story

Of its **22** occurrences, **thirteen** are ordinary call sites and **nine are inside
`vim_vsnprintf_typval` itself** — which is what `vim_snprintf` calls, so using the
in-house printf for those nine would be circular. The user's decision was to use the
in-house one; it applies to thirteen of the twenty-two and cannot apply to the rest.

The thirteen become `vim_snprintf(dest, size, …)`, each a statement whose return value
was already discarded. **Every size argument is knowable and none is invented**: eight
are `sizeof()` of a visible array or the constant the buffer was allocated with —
`IObuff` is `alloc((1024+1))` and `NameBuff` is `alloc(PATH_MAX)` — three repeat the
`alloc()` expression from three lines above, and one is a pointer **parameter** where
`sizeof(buf)` would be 8 and wrong. `highlight_arg_to_string`'s bound is
`MAX_ATTR_LEN`, and **that is sound only because the function has exactly one
caller**, `highlight_list_arg`, whose local is `char_u buf[MAX_ATTR_LEN]`. Both
programs assert that caller count and pin it at two mentions for ever: a second caller
with a smaller buffer would silently invalidate the bound and nothing else here would
see it.

The nine are narrower than they look. `f` is built twenty lines above the call and is
`%`, an optional `h`/`l`/`ll`, and one of `p d o u x X` — **no flags, no width, no
precision**, because vim does all of those itself in `tmp[]` before and after. So the
nine are "write this integer in this base", and they become `musl_fmtnum()` and
`musl_fmtptr()`, which have no format string and are not a printf. `musl_fmtptr()`
reproduces musl's `%p` exactly — musl's `vfprintf` does `p = MAX(p, 2*sizeof(void*));
t = 'x'; fl |= ALT_FORM`, so a null pointer is `0x0000000000000000` and not glibc's
`(nil)`. The `char f[6]` block goes with them: leaving it would draw
`-Wunused-but-set-variable`, which is in `-Wall`.

### One thing changes on one reachable input, and it is a bug fix

`t_CF` is a **user-settable option** that `term_font()` uses as a **format string**
into `char buf[20]`, and `sprintf` has no bound. Measured: `:set t_CF=` followed by
forty `X` and `%d`, then `:highlight Search ctermfont=3` and a search, exits **−11
(SIGSEGV)** on the binary this phase was handed, and exits **0** here with the output
truncated to nineteen characters. It is the only reachable input on which this phase
changes what the editor does, and the check requires **both halves** — the old one
must die and the new one must not.

It is **not** a declared delta, and the reason is the one phase 12 established:
nothing in the instrument sets `t_CF`, and the only built-in `t_CF` is the `debug`
terminal's `"[CF%d]"`. The same probe records the rest of the difference rather than
hiding it: a user-set `%f`, `%b`, `%*d` or `%z` now renders as vim's own printf spells
it rather than as musl's — `[0.000000]` → `[f]`, nothing → `[1101]`, a garbage int →
the argument, nothing → `[z]` — while `%d` and `%1$d` are identical. **`%s` segfaults
on both binaries** and is pre-existing, not this phase's, and the check says so.

### The case fold is inlined, so that the next phase stays independent

`musl_strcasecmp` and `musl_strncasecmp` **do not call `tolower`**, and musl's do.
musl's `tolower()` in the C locale is `(unsigned)c - 'A' < 26 ? c | 32 : c` and
nothing else — `tolower.c` is `if (isupper(c)) return c | 32; return c;` and
`isupper.c` is `(unsigned)c-'A' < 26` — so the arithmetic is written out. The cast is
what keeps a byte over 127 out of the range test, and the check reads both bodies to
confirm it is there. Inlining costs nothing and it is what keeps this phase and phase
15 orderable either way: phase 15 counts `tolower` mentions, and four new ones here
would have tripped it. **`tolower` is at 2 mentions before and after.**

### Four functions are vendored for code that cannot run, and the check says so

Breaking each moves nothing in the 106-record corpus or in the probes, and the phase
states that rather than offering a probe that cannot fail:

* **`musl_strpbrk`** — its one site needs `P_NFNAME` or `P_NDNAME`, and each of those
  has exactly **two** mentions in the file, its own enumerator and that one test. No
  `options[]` row carries either, so the condition is false always.
* **`musl_memchr`** — its one site is `vim_vsnprintf_typval`'s `%.*s`, and the only
  `%.*s` format string in the file is the OSC-timeout message.
* **`musl_strchr`'s NUL arm** — both call sites pass `'%'`.
* **`musl_fmtptr`** — nothing formats a pointer.

Their correctness rests on musl's source and on a standalone comparison against libc,
not on the recording. `musl_strstr` and `musl_strpbrk` are **naive loops** rather than
musl's two-way and bitset versions, which is the "performance is not a concern"
licence being used deliberately.

### The declared delta is nothing at all, for a third reason

Phase 9's "none" was code that could not run. Phase 12's was code the instrument
cannot see. **This phase removes no code and changes no behaviour**, and a recording
that moved would mean a vendored function was wrong. `diff -rq` over two full
recordings is empty and `tools/zerodelta.sh --phase 14` finds exactly the lines phases
2 to 11 declared and nothing new — screen 102/102, `ref-excmds.txt` 111/111,
`ref-argv.txt` 30/30.

**Thirty-three probes run on both binaries and are byte-identical**, and they exist
because the corpus reaches only part of this: every one of the thirteen external
`sprintf` sites (`:highlight`, `:marks`, `:changes`, `ga`, `:set sw?`/`all`, a
recording register, `:set term? t_Co?`, `t_CF` used properly), the numbers the nine
internal ones formatted (CTRL-G, the search count, a `:%s` count, the `Ndd`/`N>>`/undo
line reports, the ruler and its percentage), and the three things nothing else
reaches — `:history SEARCH` and `:history ALL` for the case fold, `:highlight Search
ctermfg=1` twice for `memcmp`, and `:set winhighlight=` for `memcpy`.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 79,603 | **79,884** (+281) |
| functions | 1,719 | **1,738** (+19) |
| type definitions | 908 | 908 |
| enumerators (DWARF) | 1,181 | 1,181 — **not one value moved** |
| `cmdnames[]` / `options[]` | 98 / 108 | 98 / 108 |
| `sprintf` mentions | 22 | **0** |
| `vim_snprintf` mentions | 55 | 68 |
| `#include` | 18 | 18 — untouched |
| `nm -u`, as `phasecheck.sh` counts it | 62 | **45** |
| `nm -u` with zero's own flags | 61 | **44** |
| binary | 799,816 | **803,912** |

**The freed set is named and not counted**: `memchr memcmp memcpy memmove memset
sprintf strcasecmp strcat strchr strcmp strcpy strlen strncasecmp strncmp strncpy
strpbrk strstr`, and **nothing arrives**. The binary grows by exactly **4,096 bytes**,
one page — the seventeen libc objects that stop being linked in roughly pay for the C
added. The sweep removes **nothing**, in one round, and `canon.sh` settles on the
first: the vendored text is already in the file's shape. The phase is **29 s** and its
boundary is `17a649164516`.

**The nineteen definitions are written the way the rest of the file writes one** —
the return type indented four spaces on its own line, the name at **column 0** — and
that is not cosmetic. `tools/funcreach.py` reads a definition as
`^([A-Za-z_]\w*)\([^;\n]*\)[ \t]*$`, so a one-line header is invisible to it. This
phase first emitted them on one line and the reachability sweep counted 1,719
definitions afterwards, exactly what it counted before the phase ran; phase 15's agent
found it. Nothing was broken by it — the block calls no vim helper, so nothing could
be orphaned, and `-Wunused-function` still covered a dead one — but it was a trap for
the first phase to make one of these call into the editor, and it was repaired while
it was cheap. The repair is pure formatting and its check is **tier 1**: both sources
built with `SOURCE_DATE_EPOCH=0` give a binary of 805,544 bytes and `cmp` says
byte-identical.

### Its placement

`stage 14`, `package vendor`, and two `uses` lines: `vendor:14 seed:0 mechanical`,
because the "none" is checked against phase 0's baselines, and `vendor:14 harness:3
mechanical`, because the one must-differ probe is a **screen** record of a binary that
segfaults — the old file-based sweep recorded an exit status and could not tell a
crash from a quit.

**`need 14 swept` is not required**: every anchor is exact text or a counted
identifier, and the phase is a stage of one, so its input is a boundary and is swept
by construction. **`apart 13 14` is real and is not written**: phase 13's check
asserts the libc surface moves by exactly `fclose fsync getc putc` and names `fputs
fputc fwrite putchar` as still undefined, and this phase moves seventeen more — but a
stage holding 13 and 14 holds them adjacent and every zero phase is its own stage, so
it is the shape of the missing `apart 2 6`. **`apart 14 15` is phase 15's**, and it is
the one that matters: this check pins `tolower` and `toupper` and requires both still
undefined, and phase 15 takes them.

## Phase 15 — the character classes, the numbers and the sort

`pipes/zero15-edit.sh` and `pipes/zero15-check.sh`, `stage 15`, `package vendor`. Phase
14 took the strings; this takes everything else in `zero-vim.c` that is **pure
computation** — a function of its arguments that asks the operating system nothing —
and defines it in the file, as plain C, with no preprocessor and no comment. Eleven
undefined symbols go: `tolower toupper towlower towupper isalnum iscntrl ispunct`, the
character classes; `atoi atol`, the numbers; and `qsort bsearch`.

### `nm -u` is not the scope, and that is why the phase is bigger than that list

musl spells six more classifiers as **function-like macros** in `include/ctype.h` —
`isalpha isdigit isgraph islower isupper`, and `isspace` through `__isspace` — so a
source that calls them produces **no undefined symbol at all**. Five of them are live
here, at **seventeen sites**: `isdigit` 7, `isupper` 5, `isalpha` 3, `islower` 1,
`isgraph` 1. Until they go, `<ctype.h>` cannot, and a phase scoped by the symbol list
would have looked finished and left phase 16 unable to move.

So this phase asserts **phase 16's contract itself**, in both directions: a copy of the
produced source with `#include <ctype.h>` and `#include <wctype.h>` deleted must
compile **silently**, and the same deletion on the source the phase was handed must
fail — measured, **13 errors**. That pair, and not a grep, is what says phase 16 can
move. Neither copy goes near the tree; this phase changes no directive and the count
stays 18.

**The sign-extension question is moot at every one of the seventeen sites, twice
over.** Fifteen already cast to `(unsigned char)`, and the two that do not are
`regatom()`'s, where `int cu` runs `1..127`. And the replacements are **total over
`int` and bit-for-bit equal to musl's for every argument**: EOF, `INT_MIN` and
everything outside 0..255 give false for every classifier and the identity for both
mappings, exactly as musl's do. Measured once, over **all 4,294,967,296 `int` values:
zero disagreements**, in 66 seconds.

### The obvious reading of `towupper` and `towlower` is wrong

Their one live arm each is `if (!(cmp_flags & CMP_INTERNAL)) return towupper(a);`
inside `utf_toupper()` and `utf_tolower()`, and `'casemap'` defaults to
`"internal,keepascii"` — so they look unreachable without `:set casemap=`. **An
instrumented build marks 104 of the 106 records of a full recording, 892 times in one
trivial session.** The caller is `utf_islower()`/`utf_isupper()` from
`buf_init_chartab()`, running **before `'casemap'` has been applied**, with `cmp_flags`
still its static zero and arguments in **exactly 128..255**. They classify the whole
Latin-1 range at startup, and nothing in the source says so.

The other two mentions, in `vim_toupper()` and `vim_tolower()`, sit on the line after
an unconditional `return`, and gcc drops the unreachable block even at `-O0` — which is
why `iswupper`, whose **only** mention has that shape, is a name in the source and not
a symbol in the object.

### Four answers were built, recorded and probed

| | lines added | binary | corpus | the case probes |
| --- | --- | --- | --- | --- |
| musl's `casemap.h` verbatim | +548 | unchanged | identical | identical |
| **range-compressed (taken)** | +557 | +1,632 | identical | **identical** |
| vim's own table instead | +166 | −4,096 | identical | 2 of 5 differ |
| ASCII only | +188 | −4,096 | identical | 2 of 5 differ |

musl packs the mapping into a two-level base-6 table, 297 lines and forty lines of
`(v*mt[y]>>11)%6` bit arithmetic: exact, and the opposite of obvious idiomatic C.
Routing the calls to vim's own table instead costs **97 upper and 96 lower codepoints,
96 and 96 of them above U+00FF** — the one below, U+00DF, is neutralised twice in the
source, by `utf_islower()`'s `|| a == 0xdf` and by `swapchar()`'s hard-coded ß→ẞ.

**The ASCII fallback is rejected with a number, not an opinion.** It misclassifies
**62 of 128** Latin-1 bytes at startup — every accented letter and µ — and *every
harness here says it is fine*, because `'isprint'` (`"@,161-255"`) and `'iskeyword'`
(`"@,48-57,_,192-255"`) re-cover the same bytes by range: `g_chartab` and `b_chartab`
come out byte-identical under all four variants, and stay identical under `:set isk=@`
and `:set isp=@`. A variant whose only defence is that two option defaults happen to
paper over it is not one to ship.

What runs is the fourth: **musl's mapping range-compressed into the shape this file
already has**, `187 + 171` `convertStruct` rows read by `utf_convert()` — the same size
as vim's own 198 + 183, and read by the same function. Exact, and in the file's own
idiom. **Dropping `'casemap'`'s non-internal arm is a phase of its own and deliberately
not this one**: it would delete those 358 rows and take the binary down 5,728 bytes,
and deciding what `'casemap'` means in a core is a different idea from vendoring.

### The two data files are not remembered constants

`tools/musl-case.txt` is generated by `tools/muslcase.py --generate`, which reads
**this machine's libc** through `ctypes`; `--verify` re-derives every one of the
**1,114,112** codepoints from the same authority and refuses on one disagreement, in
1.4 s. A musl upgrade that moved one codepoint fails the phase rather than passing it
quietly. `tools/musl-ctype.txt` is the seventeen functions, and `tools/muslctype.py
--verify` slices them **out of the source the phase produced** — not out of the data
file, which would only prove the copy was faithful — compiles them with `-Wall
-Wextra` and runs them beside libc's, in 0.35 s. Both are proven able to fail:
perturbing one `convertStruct` offset, one `& 0x5f`, one comparator direction and one
`return` in the binary search each makes the matching tool refuse.

**`muslctype.py`'s domain is bounded on purpose and its docstring says so.** The 2³²
sweep costs 66 seconds, which is more than the rest of the phase, and a check that
doubles a phase's time stops being run. What runs is every int in [−1024, 1024], every
threshold in the definitions and its two neighbours, EOF, `INT_MIN`, `INT_MAX` and a
**fixed** pseudo-random sample of 1,000,000 — 1,002,140 values. Every one of the eleven
is a closed form in `(unsigned)c`, so a disagreement anywhere is a disagreement at a
threshold, and every threshold is in the bounded set.

### Three anchors and sixteen counted rewrites

**A — the seventeen functions and two prototypes**, at the **end of the block phase 14
started**, between the last `#include` and the enum wall, so the file has one vendored
block and not two. The anchor is the junction itself, the end of `musl_fmtptr()` and
the first enum. The prototypes are needed only because the two **dead** `return
towupper(c);` mentions are rewritten too and sit below.

**They use the file's two-line definition style, and that is mechanical rather than
cosmetic.** `tools/funcreach.py` finds a definition with `^([A-Za-z_]\w*)\(…\)$` —
the *name* at column 0, which is what `    static int` on its own line gives. Phase
14 wrote one-line headers, and **measured, `funcreach.py` saw 1,719 definitions on
this phase's input, exactly what it saw before phase 14 ran**: not one of its
nineteen was in the reachability graph. Nothing was wrong — the block calls nothing
`funcreach.py` tracks, and `-Wunused-function` still covers a dead one — but a
function written that way is outside the sweep, so these seventeen are written the
way the other 1,719 are.

**B — the two tables**, after vim's own `toUpper[]`, so musl's sit beside vim's and
`utf_convert()` is already declared above them.

**C — `return iswupper(c);`, deleted** rather than vendored, and that is measured
rather than argued: same file name, `SOURCE_DATE_EPOCH=0`, the binary is
**byte-identical either side**.

**D — sixteen counted rewrites, 44 call sites**, applied only to the text *after* the
inserted block, so that no vendored body rewrites itself — `musl_ispunct()` calls
`musl_isalnum()`, and a file-wide regex would have made `musl_tolower()`'s body read
`musl_musl_tolower`.

**The check counts them as a rule and not as a table of constants**, and writing it
that way is what found that they are **44 and not 42**: for each name it requires
`calls(new, "musl_N") == calls(old, "N") + calls(vendored text, "musl_N")`, both halves
read at run time, so it says *every site moved and none was invented* on whatever input
it is handed rather than on the one it was written against.

### Nothing in `tools/sweep.sh` covers an unreachable statement

gcc's `-Wunreachable-code` has been a no-op since gcc 4.5 and is not in `-Wall
-Wextra`; `deadsweep.py` acts on warnings; and `funcreach.py` and `typereach.py` read
*definitions*, so a libc name with no definition here is invisible to them. An
unreachable statement is a **sixth kind of dead thing** beside the five the sweep
knows. Measured: `zero-vim.c` holds **eighteen** of them and exactly **one** names a
libc symbol. This phase takes that one. The other seventeen are a phase of their own —
three are the folded Latin-1 arms of these same four functions, and deleting those
would orphan `latin1flags`, `latin1upper` and `latin1lower`, which would turn a
vendoring phase into a cut. The check requires all three to **survive**, because a
check that expected them at zero would fail on a correct phase.

### `qsort` is stable on purpose, and it cannot matter

`sort_strings()` has one caller, `ex_undolist()`, and the keys begin `"%6ld"` of
`uh_seq`, which is `++curbuf->b_u_seq_last` — **one assignment in the whole file** —
so `strcmp` can never return 0 there. The replacement is an insertion sort, **stable**
where musl's smoothsort is not: where they could differ it returns the input order,
which is a function of the input alone, and that is what a memoized pipeline wants.

Measured three ways. The same `:undolist` row order as the input binary over five runs;
an **anti-stable** build (`>=` for `>`) giving the same order too, because there are no
ties; and a **reversed** build giving `5 4 3 2` where the others give `2 3 4 5`, which
is the control that proves the probe can see the sort at all. `tools/muslctype.py`
proves the converse in C, where the editor cannot: on three equal keys the two sorts
place **2 of 5** pointers differently while sorting to the same strings.

**`:undolist` is not visible in the screen snapshots** — the Press-ENTER redraw wipes
it before the `\x1b[?25h` that ends a step — so the probe reads the row order out of
the raw stdout stream, and compares the order rather than a digest, because the rows
carry `"0 seconds ago"`.

### `bsearch` is a binary search, and one of its four tables has a duplicate row

All four were checked by running their real comparators over their real data:
`highlight_tab` 13 rows, `color_name_tab` 28 and `char_class_tab` 19 are strictly
increasing; **`key_names_table` has two adjacent rows both spelled `"Tab"`**, one
carrying `TAB` and one `K_TAB`. It is still sorted, and it is not a hazard, because
`get_special_key_code()` ends `return key == K_TAB ? TAB : key`. Measured: both
binaries resolve `<Tab>` to row 100.

musl's algorithm is kept line for line rather than a linear scan, for two reasons that
are both about failure modes: a scan would silently **repair** a future unsorted table,
and the binary search resolves that tie identically. Against libc: **1,845 lookups**
over sizes 0..40 and every key, **the same pointer every time** — which is stronger
than "it found something".

### `atoi` and `atol`

musl routes both through `strtol`-shaped code; the replacement is the plain loop — skip
`isspace`, an optional sign, then accumulate **negatively** so that `INT_MIN` and
`LONG_MIN` do not overflow on the way in. **Overflow is undefined in the real ones
too**, and these are undefined in the same place and no other; all ten call sites can
already be handed arbitrary digits by a user or a terminal. `getdigits()` does not skip
the whitespace `atol` skips — upstream's, unchanged, and a tidier `atol` would have
changed it. Measured against libc: **137,560 strings**, every one of length 1..4 over an
alphabet holding whitespace, both signs, digits, letters and the two high bytes `\x80`
and `\xff` — **zero disagreements**.

### The declared delta is nothing at all, and it is a third kind

Phase 9's was code that **could not run**; phase 13's was a **possibility that had
never existed**; this one is an **equality**. The code it replaces runs constantly, so
the evidence is equivalence rather than unreachability and **every probe is a
must-not-differ**.

And the corpus reaches none of it: every one of the 102 screen cases seeds itself by
typing ASCII, so nothing in it touches Unicode case folding, `'casemap'`, the four
`bsearch` tables or the sort. **Fourteen probe sessions run on both binaries beside the
recording** — six over an ASCII, a Latin-1, a Greek, a Cyrillic, a circled Latin and a
Coptic letter under every `'casemap'` the option can hold, four for the four `bsearch`
tables, three for `atoi` and `atol`, one for the chartab those 892 startup calls build,
and `:undolist`. **The probe text holds two groups on purpose**: the first three
letters separate an ASCII fallback and the last two separate vim's own table, and a
text with only one group would pass one of the two wrong answers. Validated against
both: with the vim-table build `case_empty` and `case_keepascii` move; with the ASCII
build they move **and** stop showing the Greek capital.

Two full recordings, the binary the phase was handed against the one it made, are
byte-identical — all 102 screen cases, all 111 Ex-command rows, all 30 command lines,
the four pty scenarios and the nineteen terminal rows — and `tools/zerodelta.sh --phase
15` finds the same against whim-vim's frozen baselines. `pipes/zero.delta` gets a
comment and no line.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 79,884 | **80,440** (+556) |
| functions | 1,738 | **1,755** (+17) |
| type definitions | 908 | 908 |
| enumerators (DWARF) | 1,181 | 1,181 — none gone, none arrived, none renumbered |
| `#include` | 18 | 18 — untouched |
| `nm -u`, as `phasecheck.sh` counts it | 45 | **34** |
| `nm -u` with zero's own flags | 44 | **33** |
| binary | 803,912 | **805,544** |

**The binary grows, and that is the measurement rather than a disappointment.** The 358
rows are data the image did not carry, and the musl objects they replace were smaller
because musl packs the same mapping into 16,998 bytes. Phase 14 was the first phase
in this pipeline to make the file longer and the image bigger; this is the second.

**Eleven symbols go and the check names the set, not the count** — `atoi atol bsearch
isalnum iscntrl ispunct qsort tolower toupper towlower towupper`, with nothing
arriving — and **five more identifiers leave the source with no symbol to show for it**,
`isalpha isdigit isgraph islower isupper` being macros in musl. The check asserts the
terminal, the memory, the message layer, the clock and the signals still undefined
beside them, and `ZERO-PLAN.md` §4b's invariant again.

The functions row is `funcreach.py`'s, and the **+17 is this phase's seventeen**. Both
absolute numbers here are 19 higher than they first read, because phase 14 emitted its
nineteen definitions with the header on one line, where `funcreach.py` cannot see them;
this phase's agent found that, phase 14 was restyled into the file's own shape, and the
difference the row records did not move.

The sweep is **1 round** and removes **nothing** — every one of the seventeen new
functions is called — and `tools/canon.sh` is a **no-op** on the output, so the
inserted text is already in the file's canonical form. The phase is **41 s**: 7 s the
edit and its build of the input binary, 6 s the sweep, 24 s the check and 4 s
`tools/zerodelta.sh`. `make zero-tip` is 48 s. Its boundary is `b1b12e506ceb`.

### Its placement

`stage 15`, `package vendor` with phase 14, and two `uses` lines: `vendor:15 seed:0
mechanical`, because the "none" is checked against phase 0's baselines, and `vendor:15
harness:3 mechanical`, because "nothing moved" is a statement about a zero recording
and a zero recording is what phase 3 made one. Phase 14 is in the same package, so the
ordering between them is the package's and not a `uses`.

**`need 15 swept` is not required, and it was measured**: every anchor is exact text,
every count was taken on unswept input, and the sweep removes nothing here.

**`apart 14 15`, measured.** Both checks state that the undefined set moved by exactly
**their** symbols — phase 14's seventeen strings, phase 15's eleven — and a stage
holding both takes one symbol snapshot at the stage's start. Run with a snapshot from
before phase 14, phase 15's check reports **28 symbols gone instead of 11** and exits
1. Phase 14's check fails the other way for a reason of its own: it pins `tolower` at
**2 mentions** and names it as the character-class phase's, and on the tree phase 15
leaves it is **0**.

`make zero-verify` reproduces every boundary in **110 s** of wall time over 863 s of
phases -- sixteen, r0 to r15, when this phase was written, and seventeen since -- and
all 107 whim and slim implementation keys are unchanged.

## Phase 16 — the includes nothing names

`pipes/zero16-edit.sh` and `pipes/zero16-check.sh`, `stage 16`, `package includes`.
`zero-vim.c` inherited **eighteen** preprocessor directives from `whim-vim.c`, every
one an `#include` of a system header, and fifteen phases removed none of them. Six are
now needed by nothing, and this phase takes them — **the first zero phase to change
that count**, and the only one whose evidence is a byte comparison rather than a
recording.

### Six headers, and three of them have been dead all along

| | why it is unused | since |
| --- | --- | --- |
| `<sys/stat.h>` | supplies **nothing**: its one user is `typedef struct stat stat_T;`, and nothing uses `stat_T` | before the pipeline |
| `<fcntl.h>` | supplies **nothing at all** — `fcntl`, `creat`, `openat` and every `O_*` at zero mentions | phase 9 |
| `<iconv.h>` | supplies **nothing at all**, and nobody had noticed: `iconv` occurs exactly once in `zero-vim.c` and that once is its own `#include` line | whim |
| `<string.h>` | the sixteen `mem*`/`str*` functions | phase 14 |
| `<ctype.h>` | **ten** identifiers | phase 15 |
| `<wctype.h>` | `towlower`, `towupper` — and `iswupper` | phase 15 |

**`<iconv.h>` is the find, and it was missed twice.** `ZERO-PLAN.md` §4 measures this
cut as "79,599 lines and **16 directives**", and `pipes/zero13-edit.sh` names two
headers where there are three. Both were counting `<sys/stat.h>` and `<fcntl.h>` and
neither looked at the rest; the answer is **15 directives** at that point and twelve
here.

**`<ctype.h>` is ten identifiers and not five, and the five that are invisible are the
interesting half.** `isalnum`, `iscntrl`, `ispunct`, `tolower` and `toupper` are real
calls and appear in `nm -u`. `isalpha`, `isdigit`, `isgraph`, `islower` and `isupper`
are musl **macros** — `#define isalpha(a) (0 ? isalpha(a) : (((unsigned)(a)|32)-'a') <
26)`, where the `0 ?` arm keeps the prototype visible and is never emitted — so they
are in no undefined set at all and a survey driven by the symbol list cannot see them.
Seventeen occurrences of real source, and `<ctype.h>` does not go until all ten are
handled.

**`iswupper` is the same shape one step further on**: a name the header had to supply
that was never a symbol either. Its one occurrence sits directly after
`return utf_isupper(c);` inside `vim_isupper()`, so gcc never emitted the call. Phase 15
deleted the statement rather than vendoring a function nothing calls.

### The typedef, which is the one silent drop in this file

`typedef struct stat stat_T;` goes in the same edit as its header, and that is not
tidiness. **Removing `<sys/stat.h>` alone compiles cleanly** — the typedef simply
declares a new, *incomplete* `struct stat` at file scope — and what is left is a lie
that only `sizeof(stat_T)` would ever expose. Measured both ways: `-Wall -Wextra
-Wno-unused-parameter` is silent on that file, and a two-line probe using `stat_T` by
value gives *"invalid application of `sizeof` to incomplete type `stat_T` {aka `struct
stat`}"*. The check's loop could not have caught it, because the loop asks the compiler
and the compiler is content.

**And no sweep could ever have taken it, for two textual reasons, both measured.**
`tools/typereach.py` takes as roots every identifier mentioned outside a type
definition, and this definition's name set is `{stat, stat_T}`. It is kept alive by
`update_search_stat()`'s local variable `searchstat_T stat;` **and by the `#include
<sys/stat.h>` line itself**, whose text contains the token `stat`. Measured:
`typereach.py` reports `0 unreachable` on the committed file, `0 unreachable` with only
the include gone, `0 unreachable` with only the local renamed, and **`1 unreachable —
stat,stat_T`** only when both are gone. Fifteen phases of sweeps had left it.

**One blank line goes with it.** The typedef sits between two blank lines, so deleting
the line alone leaves a run of two, which `CLAUDE.md` states this tree does not have —
and which neither verification tier can see. `tools/canon.sh` would collapse it inside
the sweep; the edit does it, so the text the sweep is handed is already right. Six
includes, the typedef and one blank is **eight lines**.

### The argument is a computation and not a list

A phase that deleted six named headers would prove only that six named headers were
deletable. `pipes/zero16-check.sh` proves something else, and it is the whole phase:

* **on the output**, each of the twelve surviving `#include`s is removed in turn and
  the compile **must fail**. A dead include that survived this phase would be a compile
  that succeeded.
* **on the source the phase was handed**, the identical loop over eighteen must find
  **exactly the six this phase removes** droppable and the other twelve not. That is
  the same loop proving it can fail, in the same run and on the same code path — phase
  13's `ui_write()` control in this phase's shape.

Thirty compiles, run at once, about five seconds. **gcc 15 defaults to C23, where an
implicit function declaration is a hard error**, so a header that still supplies a
function, a type, a macro constant or an enum constant cannot be dropped quietly:
there is no `-Wimplicit-*` to look for because there is nothing left to warn about.
Every one of the twelve refusals is recorded in the phase's output, so the check is a
statement of *why* each survivor is held as well as a test that it is.

Proven able to fail three ways, each measured on a scratch tree: a live `offsetof`
rewritten to `__builtin_offsetof` leaves `<stddef.h>` dead and the loop names it; the
typedef put back with its header gone is caught by the assertion above and not by the
loop; and one character changed in one string literal is caught by the `cmp`.

### `<sys/param.h>` is not touched, and the reason is recorded rather than repaired

Its **own** contribution to this file is `MIN` and `MAX`. Everything else it supplies
arrives through three levels of musl-internal inclusion — measured with `gcc -E -H`:

```
sys/param.h -> sys/resource.h -> sys/time.h -> sys/select.h
```

and `select`, `gettimeofday`, `fd_set`, `FD_SET`, `FD_ZERO`, `FD_ISSET`, `struct
timeval` and every `*_MAX` are supplied by **no other header in this file** — measured,
one probe per identifier against each of the eighteen. `zero-vim.c` has no
`<limits.h>`, no `<sys/time.h>` and no `<sys/select.h>`. That is a real fragility, and
it is written down instead of being fixed: fixing it means **adding** three directives,
and the charter says no phase adds one. If musl ever reorganises those headers the
build breaks outright, which is the loud failure and the acceptable one.

**Two of the twelve are held by almost nothing**, and the edit counts those exactly,
because the count is the statement. `<stddef.h>` is held by `offsetof` **alone**, nine
mentions — `size_t` and `NULL` come from six of the twelve, so nothing else there is at
risk. `<stdint.h>` is held by exactly **two** identifiers at one mention each:
`SIZE_MAX`, which has held it all along, and `uintptr_t`, **which phase 14 brought** —
the first thing in this pipeline's history to make a header *more* held rather than
less, and the reason the number is two. A later phase that took them would find this
check's loop reporting a dead include.

### The declared delta is nothing at all, and it is a fourth kind

Three phases before this one declared nothing, each for a different reason, and the
reason is the statement: **9** removed code that could not run, **12** removed code that
can run and that the instrument cannot see, **13** removed the possibility. **This phase
changes no code at all**, and its evidence is not that the recording did not move but
that **the binary is the same bytes** — the input's and the output's, both built with
`SOURCE_DATE_EPOCH=0` and the boundary's own flags, compared with `cmp`.

That is tier 1 of `CLAUDE.md`'s verification table, and it subsumes every screen case,
every Ex-command row, every command line and every pty scenario at once, because the
program that would be run is literally the same program. `tools/zerodelta.sh --phase 16`
runs and finds nothing moved, as it must; here it corroborates rather than proves.

**`SOURCE_DATE_EPOCH` is required and the file name is not.** `version.c`'s
`__DATE__ " " __TIME__` is the only thing in `zero-vim.c` that a build can vary — there
is no `__FILE__` and no `__LINE__` anywhere — so two ordinary builds of the same bytes
differ, measured, while the same source built under two different names and from two
different directories is identical. The `cmp` is also as sensitive as a comparison can
be: gcc writes a GNU build-id note near the front of the image and it is a hash of the
whole output, so any difference anywhere moves it and the first difference `cmp` reports
is always that note.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 80,440 | **80,432** (−8) |
| `#include` | **18** | **12** |
| other directives | 0 | 0 |
| functions | 1,755 | 1,755 — untouched |
| type definitions | 908 | **907** (−1, `stat_T`) |
| DWARF enumerators | 1,181 | 1,181 |
| `nm -u`, as `phasecheck.sh` counts it | 34 | **34 — the same set, as a `cmp`** |
| `nm -u` with zero's own flags | 33 | **33** |
| external symbols | `main` | `main` |
| binary | 805,544 | **805,544, byte-identical** |
| sweep | | **1 round, a complete no-op** |

**Nothing is freed and nothing arrives**, and the check states it as a `cmp` of the
whole undefined set rather than as a count: a header is not code, so a symbol moving in
either direction would mean the phase had done something it does not claim to do. The
sweep finds nothing at all — 0 prototypes, 0 functions, 0 variables, 0 types, 0 fields,
0 enumerators, `canon settled` — and the file it hands back is the one the edit wrote.
`main` is still the only external symbol, which is also the cheapest re-assertion that
phases 14 and 15 did not forget a `static`.

### Its placement

`stage 16`, `package includes`, and four `uses` lines: `includes:16 seed:0 mechanical`,
because the "none" is checked against phase 0's baselines; `includes:16 tidy:13
rationale`, because `pipes/zero13-edit.sh` names `<sys/stat.h>` and `<fcntl.h>`,
measures that removing them is free and **declines** — *"the count stays 18"* — so this
phase is that decision reversed; and one line each to `vendor:14` and `vendor:15`, whose vendoring
is the only reason `<string.h>`, `<ctype.h>` and `<wctype.h>` are unused.

**`need 16 swept` is not required, and it was measured.** The anchors are six exact
`#include <...>` lines at one occurrence each and one exact typedef line — text no
sweep has ever touched — and the computed part is a *compile* rather than a count, so
it cannot shrink silently on unswept text the way a counted cut can. Measured: the edit
applies unchanged to unswept text, and the sweep that follows it removes nothing.

**`apart 15 16`, and it is measured in both directions.** Phase 15's check requires the
three headers it emptied to be still present — "it is the includes phase's to take" —
and this phase removes them. And phase 16's check states that it frees **nothing**, as
a `cmp` of the stage's starting undefined set against the one it made; inside a stage
every check compares with the *stage's* start, and phase 15 frees eleven symbols, so in
a shared stage phase 16 says *"the libc surface moved, and REMOVING AN `#include`
CANNOT MOVE IT"* and names them. It is `apart 5 6`'s shape exactly.

**The edit refuses loudly on a tree the vendoring has not reached**, which is what
makes the six a requirement rather than a wish: run on the phase-13 boundary it says
*"`<string.h>` is NOT unused: memchr (1), memcmp (2), memcpy (7), memmove (159) …"* and
exits 1 with the file untouched.

### What zero-vim is after sixteen phases

```
zero-vim.c        80,432 lines          from whim-vim.c's 86,614  (-6,182, 7.1%)
functions         1,755
type definitions  907
DWARF enumerators 1,181
cmdnames[] rows   98    (create_cmdidxs floor 80; 18 rows of margin)
nv_cmds[] rows    194   (nvidxcheck: a permutation)
options[] rows    108, 96 distinct globals  (orphanopts floor 80; 16 of margin)
#include          12, every one a system header; no #define, no conditional
libc symbols      33 with zero's flags, 34 as tools/symbols.sh counts
binary            805,544 bytes, EXEC, no INTERP, no dynamic section, no relocation
declared delta    20 records + stderr-moved, from whim-vim
```

**Two of those numbers went the other way and that is the trade.** The file is 829
lines longer than it was after phase 13 and the binary 5,728 bytes larger, because
phases 14 and 15 move code *in*: twenty-eight libc functions are `static` definitions
here now instead of names a host has to answer. `ZERO-GOAL.md` measures bytes to store
**and** libc symbols to provide, and this is the first place the two disagree.

**The 33, attributed.** The whole host boundary that is left is a terminal, a message
line, memory, a clock and the process:

| why | symbols |
| --- | --- |
| **the terminal** | `read` `write` `close` `dup` `ioctl` `select` `tcgetattr` `tcsetattr` `nanosleep` `isatty` (10) |
| **messages before and after the screen** | `printf` `fflush` `stderr` (3) |
| **memory** | `malloc` `free` `realloc` (3) |
| **time** | `time` `gettimeofday` (2) |
| **signals and exit** | `sigaction` `sigaddset` `sigemptyset` `sigismember` `sigprocmask` `kill` `raise` `getpid` `exit` `_exit` (10) |
| **gcc's own**, named nowhere in the source | `__errno_location` `fputc` `fputs` `fwrite` `putchar` (5) |

**Four rows are gone and they were the pure computation**: strings and memory blocks
(17, with `sprintf`), character classes (7), numbers (2), sorting and searching (2).
Phases 14 and 15 put all 28 inside `zero-vim.c` as `static` definitions, `sprintf`
going onto the editor's own `vim_snprintf` rather than being copied. Nothing in the
list above is a function of its arguments alone: every one of the 33 asks the
operating system something.

`tools/symbols.sh` counts 34 because it compiles plain `-O0` and so adds
`__stack_chk_fail`, which zero's `-fno-stack-protector` removes. **`isatty` survives
with three call sites** and belongs to the terminal, not the filesystem —
`mch_check_win`'s `isatty(1)`, `mch_get_shellsize`'s `!isatty(fd) &&
isatty(read_cmd_fd)` and `fill_input_buf`'s `!did_read_something &&
!isatty(read_cmd_fd)`.

**The filesystem work is finished.** Phases 6 to 13 took, in order: every way to write
a file, every way to read one, every way to name another one to edit, the machinery
that read the bytes, the buffer's own name with the last three questions the core
asked a disk on its own initiative, the refusal that asked whether the text had been
saved, the option rows that reported settings nothing read, and the two `FILE *` that
were never opened.

**And the pure computation is finished too.** Phases 14, 15 and 16 took the other half
of *no musl dependencies*: the twenty-eight functions a host should never have been
asked for, and then the six headers that had nothing left to supply. What remains of
`ZERO-PLAN.md` is the host boundary itself: `main()` demoted to a launcher, the
terminal and the signal set moved out of the core, and the text representation changed
from lines to a tree. **Its §4c expected strings, memory and arithmetic to be what was
left in the core after that move; they are already gone, and the launcher has not been
written.**
