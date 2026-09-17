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

**This document is iterative, and so far it has four phases.** Phase 0 is the seed,
phase 1 is a compiler flag, phase 2 is the first cut in the source — the first
piece of *a component, not a program* — and phase 3 changes no source at all: it
replaces the instrument every later phase is measured with. Phases are added one at a time, each on the user's own
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
- **`zero-vim.c` stays pure C without a preprocessor** — it inherits 18 directives
  from `whim-vim.c`, every one an `#include` of a system header, and no phase adds a
  `#define` or a conditional — because a following repository transpiles it to the
  JVM, and every construct in the file is one that translation has to understand.

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
| `ref-term.txt` | `tools/termcheck.py`, whim's own, unchanged | 19 terminals |

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
