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

**This document is iterative, and so far it has forty-six phases.** Phase 0 is the
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
the first phase in any of the three pipelines to change a directive count. Phase 17 is
nine lines and one symbol: `deathtrap()`'s `entered >= 3` ladder, which no build of
zero-vim could ever have reached — two deadly signals, each blocked inside its own
handler — and with it `_exit`, leaving exactly one `exit()` call in the whole file.
Phases 18, 19 and 20 are *a component, not a program* on request, and they are
`ZERO-PLAN.md` §4c's three steps: `main()` becomes `static int vim_main(...)` with a
launcher of its own below it; `mch_exit()`'s last `exit(r);` becomes a call through a
pointer the launcher installs, so the editor hands the process back with a number
instead of ending it; and then the signal handlers, the window size, the terminal
mode, the delay and the wait all move into a host block at the bottom of the same
file, which takes `nm -u` to 24 and leaves the core making exactly two syscalls for
itself, a `read` of fd 0 and a `write` of fd 1. Phase 21 finishes §4c's second step:
every byte the editor put on a *stream* rather than a screen goes through one callback
the launcher installs, which takes `nm -u` to **17**, removes `<stdio.h>` and leaves
`write` the only syscall the core still makes for itself. Phases 22 and 23 are the
first of the reorganisation that draws the boundary itself: 22 expands the seven
wrappers that walk a `va_list` at their 129 call sites, so that `va_start` appears
**once** in the file and the formatter becomes movable, and 23 replaces `NULL` and
`size_t` with `nullptr` and a `usize` of the core's own — two names the **language**
supplies instead of a header — with a binary that is byte for byte the one it was
handed. Phase 24 is the one phase of the last five that is not about the boundary at
all: it asks which dialect of C the core is written in, takes 139 GNU attributes to
six — deleting 113 `unused`, **21 of which were false claims about code that uses its
parameter** — and keeps the six `format`/`format_arg` that are themselves the check
`-Wformat` performs. Phases 25, 26 and 27 finish the boundary: 25 makes the two host
calls plain, a forward declaration and a direct call where there was a function pointer
the launcher installed; 26 gives the core its own `time_T`, `volatile int`, `usize`,
tagless clock struct, `MIN`/`MAX` and `__builtin_offsetof`, and nine plain libc
prototypes, **while the real headers are still above them to be cross-checked against**;
and 27 moves the eleven `#include`s below the core, so that **above them there is not
one preprocessor directive** and the first `#include` is the line between the core and
the host. `make editor.c` writes the lines above it — **76,687** of `zero-vim.c`'s
78,666 today — and they are a complete translation unit whose warnings are the
interface. Phases 28 to 32 are five separate answers to *what the core may still name
and still call*: 28 gives the elapsed-milliseconds clock to the host as one scalar,
`long musl_now_ms(void)`, and deletes the tagless `struct timeval` mirror phase 26 had
to invent because a struct could not cross the line; 29 merges vim's Unicode case map
and the musl one phase 15 vendored into **one table, and it is the union** — a core
with no C library has nothing left for `'casemap'` to choose between; 30 folds the arm
of `msg_puts_attr_len()` that reached a terminal without a screen into two lines
addressed to the host, and is where phase 21's `exit_scroll` claim was measured and
corrected; 31 vendors `abs` and `labs`, which the core **called** and which never
appeared in `nm -u` because gcc lowers both to inline arithmetic — the first
application of `ZERO-PLAN.md` §4c's rule that the core is optimised for transpilation
and may not depend on latent compiler behaviour; and 32 sends the wall clock across
too, `host_time()` below the boundary where `vim_time()` was above it, replacing the
`long time(long *tp);` prototype with a `static_assert` that is strictly stronger than
what it removes. Phase 33 is the second in the pipeline to change no source at all: it
replaces the one part of the recording that still asked the **environment** about the
terminal, a question whim phase 19 had already stopped the editor reading, so that all
nineteen rows stopped saying the same thing. And 34 and 35 finish what 28, 31 and 32
were each a piece of: 34 rewrites `realloc` at the two core sites that used it, because
`realloc` is the one libc function that **cannot** be vendored — to move the old
contents it needs an old size its interface does not carry — and 35 sends `malloc`,
`free` and `write` to the host, so that the core's own block of ordinary libc
declarations is **two lines**, `getpid` and `kill`. Phase 36 takes both and the block
with them, by two different routes — `getpid` is avoidable outright and `kill` crosses as
`host_raise()` — so that **the core names no libc function at all**, a claim measured on
the cut compiled to an object and not on the block. Phase 37 is a tidy: six of the
thirteen `union` keywords unite nothing with anything, five single-member and one empty,
every one a leftover of a cut already made, and the binary is the same bytes either side.
And 38 and 39 are the terminal, which is the first thing zero has taken that the
recording can see since phase 11: 38 keeps **two** of the ten built-in terminal names,
`xterm-256color` and `debug`, and declares `term-moved` — the first use of a token that
had been in the grammar since phase 0 — and 39 removes `-T {term}`, so that
`+{command}` is the whole command line and nothing outside the process can say what
terminal this is. **And 40 to 45 are the memline, which is one arc and not six phases**,
the charter's *the text later held as a tree* begun: 40 changes no source and gives the
pipeline a corpus that can see the text layer at all, because a `zero-vim` with one line
deleted from `ml_find_line()`'s descent recorded all 102 screen cases byte for byte; 41
makes `host_alloc()` a bump allocator and `host_free()` a no-op, which is the charter's
*A GARBAGE COLLECTOR IS ASSUMED FROM HERE ON* and is what makes a record per line cheap;
42 clears out the swap file's residue, four groups of written-but-never-read bookkeeping
that no tool in `tools/` can see; 43 turns a **block number into a reference**, which is
the single thing in this pipeline that buys a JVM port the most; 44 lets the **leaf** stop
being a byte arena and become an array of line records, so a line's text is its own
allocation valid for the lifetime of the process; and 45 folds the node types, so that
there are no pages, no blocks and no memfile left — and turns the arc's standing hazard,
that shrinking `PTR_EN` would silently take the root split out of the corpus, into a
`static_assert` that fails to compile.
Phases
are added one at a time, each on the user's own
request, and each is written into this document, into `pipes/` and into
`pipes/zero.delta` and `pipes/zero.stages` when it is added — never in advance.

## The charter

Zero vim is an **embeddable editor core**: a library-shaped piece of C that a host
links in or translates, rather than a process that owns a terminal and a disk. What
the concept is, as the user has stated it, and in no particular order of phases:

- **A component, not a program.** `main()` is demoted. What remains of the C library
  calls — the part that talks to an operating system — is a host, and the core is what
  it drives. **The shape that was settled is one file with two parts, not two files**,
  and `editor.c` is the name of the *core*, not of the launcher this bullet first gave
  it to: from phase 27 `make editor.c` is the cut at the first `#include`, the 77,678
  lines above the boundary, and the host is everything below it in the same translation
  unit. `ZERO-PLAN.md` §4c is where that was decided and `.claude/briefs/zero-split.md`
  is the survey of the two-file design it replaced — abandoned, and worth reading only
  for what it measured the split would have cost.
- **No musl dependencies** in `zero-vim.c` itself. Whatever the core still needs
  from the world, the host provides.
- **The screen and all visual editing stay.** This is still vim to look at and to
  type into; what goes is the editor's reach outside itself.
- **No filesystem access.** Reading and writing files is the host's business, not
  the core's.
- **The text representation is PREPARED for a move it does not make.** The move from
  lines to a structure — a tree mirroring an abstract syntax tree, with the line view
  every motion, command and redraw expects simulated on top of it — **is not this
  repository's work and never was**: it happens after transpilation, in the repository
  that receives the core. What belongs here is everything that makes that move possible
  for somebody else: preparation, simplification and canonicalization, so the thing
  handed over is a representation a porter can read rather than one they must decode.
  Earlier drafts of this bullet had the move itself happening here, and that was the
  right plan for what was known then: the boundary had not been drawn, and where the
  core ended and its host began was exactly the question the pipeline was still
  answering. Once the core turned out to name no libc function at all, the handover
  point moved, and the move went with it. **The work argued for on the old premise is
  unaffected** — every reason to simplify the memline survives the move leaving, and
  the bullet below is why. A plan that shifts as the thing it plans comes into focus is
  the process working; this line records the shift so that a reader meeting both
  versions knows which is current and why they differ.
- **A GARBAGE COLLECTOR IS ASSUMED FROM HERE ON**, and it is assumed precisely so the
  core may stop earning its memory. The target is a JVM, where allocation is cheap and
  freeing is somebody else's problem, so the core is free to allocate finely — a record
  per line rather than a byte arena per page — and simply not free it. No real collector
  is built: `host_alloc` becomes a bump allocator in the host with enough arena for the
  test suite and `host_free` returns without doing anything, which is a change entirely
  below the boundary and touches no core line. **This is what makes the memline
  simplification cheap rather than clever.** The page arena exists for exactly one
  reason — to avoid a `malloc` per line — and once that reason is gone the arena, its
  fourteen interior pointers, its thirty-four `db_index` subscripts, its stolen flag bit
  and its three `offsetof` all go with it, by having nothing left to measure.
- **The memline page is the worst of what a JVM cannot express**, and it is the thing
  the two bullets above are aimed at: the page is a `struct data_block` whose last
  member is
  `unsigned db_index[1]` indexed to the block's line count, whose entries are byte
  offsets **into the same block** read back as fourteen interior pointers of the shape
  `(char_u *)dp + start`, whose top bit is stolen as the `DB_MARKED` flag, and whose
  two bytes of padding after `db_id` are load-bearing — `offsetof(DATA_BL, db_index)` is
  24 of a 32-byte struct and the page-count arithmetic uses it. `ZERO-PLAN.md` §4d
  states it and names the one other construct of the same shape. **And nothing
  constrains what replaces it**, which is worth knowing before the move is designed:
  the memfile is purely in memory — `mf_open()` takes no name, sets `mf_page_size` from
  a constant and hands out pages `alloc()` returns, `mf_sync()` clears the dirty flag
  and returns FAIL, and `mf_write`, `mf_read`, `mf_release`, `mf_fd` and `ml_recover`
  have **0 mentions** in `zero-vim.c` — so `DATA_BL` is an internal layout with no
  compatibility constraint on it and not a disk format any more.
- **`zero-vim.c` stays pure C without a preprocessor** — it inherited 18 directives
  from `whim-vim.c` and is down to **eleven**, every one an `#include` of a system
  header, and **since phase 27 not one of them is above the boundary**: the core, the
  77,678 lines `make editor.c` writes, has **no preprocessor syntax at all**, and
  **no phase adds a `#define`, a conditional or an `#include`** — because a
  following repository transpiles it to the JVM, and every construct in the file is one
  that translation has to understand. **A phase may remove one**, and phase 16 is the
  first that did, phase 21 the second, taking `<stdio.h>` with the seven symbols it
  freed. That permission is stated here because the old reading — a count the
  pipeline preserves — is exactly why phase 13 measured that removing three of them was
  free and declined, writing *"the count stays 18"* into its own program. Nothing is
  ever added back: the eleven reach `select`, `gettimeofday`, `fd_set` and `struct
  timeval` only through musl's own `sys/param.h` → `sys/resource.h` → `sys/time.h` →
  `sys/select.h`, which is recorded as a fragility rather than repaired with three more
  directives. **The `*_MAX` are no longer among them**: phase 27 made all twelve
  header-supplied constants the core used enumerators of its own, each one asserted
  against the header from **below** the boundary.

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

## The pipeline as it stands

**This section is the whole of zero read across its phases, and it lives here
rather than in `CLAUDE.md` because it is 910 lines of one pipeline's history in a
file that is loaded into every session.** What `CLAUDE.md` keeps is the summary
and a pointer to this heading; what is here is the phase-by-phase account, the
symbol accounting, the declared-delta taxonomy, the `apart` and `need`
derivations and the instrument's own history. Every sentence is as it stood in
`CLAUDE.md`, and three cross-references that named a section of that file now say
so; nothing else was edited in the move.

**The zero pipeline is `zero-vim.c = H(whim-vim.c)`, and so far it is a seed, a flag,
twenty cuts, three instruments, two demotions, a host block, a variadic collapse, a
dialect phase, two tidies, a case-table merge, a vendoring, two clock phases, two
allocation rewrites, two hand-overs to the host, the four that draw the boundary and the
three that make the text a tree — the
filesystem work is finished, the terminal is down to two names it can describe and no
way to be told which, **the memline has no pages, no blocks and no memfile left**, the
libc
that is pure computation is
inside the file, seven of the eighteen `#include`s are gone, the core has no `exit()`
call at all — it asks the host to end the process and the launcher at the bottom
of the same file returns the status out of `main()` — it installs no signal handler,
sets no terminal mode, runs no `select`, asks the kernel nothing about a window,
writes to no stream, **reads neither clock for itself** — the elapsed milliseconds
and the wall time both cross the boundary as `long` — and **allocates, frees and writes
nothing for itself either** — and since phase 41 **freeing is free**, `host_alloc()`
being a bump allocator into a 1 GiB arena and `host_free()` a function that returns —
`va_start` appears once in
the whole file, `NULL` and `size_t`
are gone in favour of two names the language supplies, and **the eleven `#include`s are
no longer at the top**: they sit at line 76,689 and the first of them is the line
between the core and the host. **And since phase 36 the core names no libc function at
all**: the block of ordinary, non-`static` declarations it kept above that line is empty
and gone, every outward call is a `musl_` or a `host_`, and the claim is checked by
compiling the cut to an object — 18 undefined names, every one of them defined below the
boundary in the same file.
`ZERO-GOAL.md` states what it is for — an embeddable editor core that keeps the
screen and all visual editing and loses the filesystem, with `main()` demoted to a
host launcher and the text later held as a tree — and has forty-six phases:
`pipes/zero0.sh`, the seed; `pipes/zero1.sh`, which adds `-fno-stack-protector`;
`pipes/zero2-edit.sh` with `pipes/zero2-check.sh`, the first source cut — the two
"not to a terminal" warnings, the two-second pause after them and `--ttyfail`;
`pipes/zero3.sh`, which changes no source at all and replaces the instrument
(below), so r3's tree and r2's have the same digest; `pipes/zero4-edit.sh` with
`pipes/zero4-check.sh`, which removes Ex mode, silent mode and the `-e -E -s -v`
options; `pipes/zero5-edit.sh` with `pipes/zero5-check.sh`, which leaves the
command line as `+{command}` and `-T {term}` — the file argument, the bare `-` and
`--` all become `mainerr(ME_UNKNOWN_OPTION)`; and `pipes/zero6-edit.sh` with
`pipes/zero6-check.sh`, which takes every way to write a file — the six Ex commands
`:write :wq :xit :exit :update :saveas`, four anchors and nineteen functions the
sweep finds, `ZZ` becoming `q!`; and `pipes/zero7-edit.sh` with
`pipes/zero7-check.sh`, which takes the way to read one — `:read` and its `:r !cmd`
arm, three anchors, six functions the sweep finds and one fold no tool could make,
the `exarg_T.usefilter` field that nothing writes once both `:w !` and `:r !` are
gone; and `pipes/zero8-edit.sh` with `pipes/zero8-check.sh`, which takes every way to
name another file to edit — the five Ex commands `:edit :enew :ex :visual :view`,
which are one handler, and the `gf gF [f ]f` keys, which are **arms** inside two
surviving handlers and not `nv_cmds[]` rows, six anchors and seventeen functions the
sweep finds; and `pipes/zero9-edit.sh` with `pipes/zero9-check.sh`, which takes the
machinery under all of those — `readfile()`, `read_buffer()` and the message layer
that reported what had been read, four anchors all inside `open_buffer()` and sixteen
functions the sweep finds; and `pipes/zero10-edit.sh` with `pipes/zero10-check.sh`,
which takes the buffer's **name** — `:file`, `buflist_new()`'s two name parameters,
sixteen folds of `b_ffname`/`b_sfname`/`b_fname`, and three further folds that free
the last three questions the core asked the filesystem — seven parts and **sixty**
functions the sweep finds, the most any zero phase has handed it; and
`pipes/zero11-edit.sh` with `pipes/zero11-check.sh`, which takes the last thing the
filesystem left behind — the **refusal**, `E37: No write since last change`, which has
had no remedy to offer since phase 6 took every `:write` — as ONE fold of `ex_quit`'s
test, and sixteen functions the sweep finds, eleven of them the whole
switch-buffer/switch-window island that hung off `check_changed_any()`'s tail and that
no plan foresaw; and `pipes/zero12-edit.sh` with `pipes/zero12-check.sh`, **the
options nothing reads** — six `options[]` rows of a *computed* seven whose global has
no reader left, `'fsync' 'prompt' 'readonly' 'undoreload' 'write' 'writeany'`, with
`'readonly'`'s `W10` warning, its one-second pause and its two `[RO]` indicators;
and `pipes/zero13-edit.sh` with `pipes/zero13-check.sh`, **no `FILE *` that is never
opened** — `scriptin[NSCRIPT]` and `redir_fd`, two `static FILE *` that nothing has
ever opened in any build of zero-vim, `ui_write()`'s `console` parameter, and the
five functions the sweep finds under them; `pipes/zero14-edit.sh` with
`pipes/zero14-check.sh` and `pipes/zero15-edit.sh` with `pipes/zero15-check.sh`, **the
libc that is pure computation**, defined in the file as local `static musl_*`
functions — the sixteen `mem*`/`str*` of `<string.h>`, with `sprintf` moved onto the
editor's own `vim_snprintf` instead, then the character classes, the two `ato*`,
`qsort` and `bsearch`; and `pipes/zero16-edit.sh` with
`pipes/zero16-check.sh`, **the includes nothing names** — six of eighteen,
`<sys/stat.h>` `<fcntl.h>` `<iconv.h>` dead since before the pipeline and `<string.h>`
`<ctype.h>` `<wctype.h>` dead since phase 15, with the `stat_T` typedef no sweep could
take; and `pipes/zero17-edit.sh` with `pipes/zero17-check.sh`, **the deadly ladder
that cannot run** — the nine lines of `deathtrap()`'s `entered >= 3` arm,
`reset_signals()`, `_exit(8)` and `exit(7)`, which no build of zero-vim could ever
reach; and `pipes/zero18-edit.sh` with `pipes/zero18-check.sh`, **`main()` demoted to
`vim_main()`** — `static`, with a six-line launcher appended below it, both still in the
one file; and `pipes/zero19-edit.sh` with `pipes/zero19-check.sh`, **the core can no
longer stop the process** — `mch_exit()`'s `exit(r);` becomes `vim_host_exit(r);`
through a pointer the launcher installs, and the launcher lands on `__builtin_setjmp`
and returns the status; and `pipes/zero20-edit.sh` with `pipes/zero20-check.sh`, **the
signals and the terminal are the host's** — the five signal handlers, `mch_settmode`'s
three-valued mode, `mch_delay`'s sleep, `RealWaitForChar`'s `select`, `mch_get_shellsize`
and all three `isatty()` calls move into a 229-line `host_*`/`musl_*` block at the
bottom of the same file, the resize and the external stop and the interrupt arrive as
**bytes** in the input stream, and `fill_input_buf`'s `close(0); dup(2)` arm goes; and
`pipes/zero21-edit.sh` with `pipes/zero21-check.sh`, **the messages are the editor's and
the writing is the host's** — twenty output statements in five functions become eight
calls through one `vim_host_message(msg, len, err)` the launcher installs, with
`<stdio.h>` and seven symbols going with them; and `pipes/zero22-edit.sh` with
`pipes/zero22-check.sh`, **the variadic collapse** — the seven wrappers that walk a
`va_list` expanded at their 129 call sites into `vim_snprintf` plus the tail each
already had, five helpers against seven deleted definitions, so `va_start` appears
**once**; and `pipes/zero23-edit.sh` with `pipes/zero23-check.sh`, **`nullptr` and
`usize`** — `NULL` 2,555 → 3 and `size_t` 437 → 0, two names the language supplies
instead of a header, on a **byte-identical binary**; `pipes/zero24-edit.sh` with
`pipes/zero24-check.sh`, **the attributes** — 139 GNU `__attribute__` to six, the 113
`unused` deleted (**21 of them false**, marking a parameter the code reads), the 20
`fallthrough` respelled as the C23 `[[fallthrough]]`, and the three `format` and three
`format_arg` kept because they *are* the check `-Wformat` performs; `pipes/zero25-edit.sh`
with `pipes/zero25-check.sh`, **the plain host calls** — the two function pointers the
launcher installed become a forward declaration and a direct call, so `vim_main(int argc,
char **argv)` is phase 18's signature again; `pipes/zero26-edit.sh` with
`pipes/zero26-check.sh`, **the header types and macros the core can own** — `time_t`,
`sig_atomic_t`, `uintptr_t`, `struct timeval`, `MIN`, `MAX` and `offsetof` become the
core's own and nine libc prototypes are written out, **while the headers are still above
them to be cross-checked against**; and `pipes/zero27-edit.sh` with
`pipes/zero27-check.sh`, **the move** — the eleven `#include`s go below the core, twelve
header-supplied constants become enumerators asserted from below, and the formatter's
private island follows the four `va_list` functions down; and `pipes/zero28-edit.sh`
with `pipes/zero28-check.sh`, **the scalar clock** — `long musl_now_ms(void)` replaces
`void musl_gettimeofday(long *, long *)` and takes `elapsed_T`, `elapsed()` and the
out-parameter pair with it, **so no host call's shape is decided any more by a type the
core cannot name**; and `pipes/zero29-edit.sh` with `pipes/zero29-check.sh`, **the case
tables become one, and it is the union** — vim's `toUpper[]`/`toLower[]` and the
`musl_to*[]` phase 15 vendored disagreed at 97 upper and 96 lower codepoints, vim's
newer by ninety-six and musl's knowing `ß → ẞ` alone, and a core with no C library has
nothing for `'casemap'` to choose between; and `pipes/zero30-edit.sh` with
`pipes/zero30-check.sh`, **the message fold** — `msg_puts_attr_len()`'s never-taken arm
becomes one `host_message()` call, with `msg_puts_printf()` and `vim_strlen_maxlen()`
going, and **two folds measured and declined**; and `pipes/zero31-edit.sh` with
`pipes/zero31-check.sh`, **`abs` and `labs`** — called by the core, never in `nm -u`
because gcc lowers both to inline arithmetic, and vendored so that the core stops
depending on behaviour nothing states; and `pipes/zero32-edit.sh` with
`pipes/zero32-check.sh`, **the wall clock crosses too** — `vim_time()` becomes
`host_time()` below the boundary, `long time(long *tp);` leaves the core's prototype
block and a `static_assert` stronger than it replaces it; and `pipes/zero33.sh`,
**the terminal table is asked a question it can answer** — the second phase that changes
no source at all, replacing `$TERM`, which whim phase 19 stopped the editor reading, with
`+set term={name}`, so nineteen rows that carried one answer between them carried ten
resolutions and nine refusals — two and seventeen since phase 38; and
`pipes/zero34-edit.sh` with
`pipes/zero34-check.sh`, **the core stops reallocating** — `realloc` rewritten at its two
core sites as a `host` allocation, a `musl_memcpy` of the **old** size and a free, because
`realloc` is the one libc function that cannot be vendored at all: to move the old
contents it needs a length its interface does not carry; and `pipes/zero35-edit.sh` with
`pipes/zero35-check.sh`, **the core calls nothing but the host** — `malloc`, `free` and
`write` become `host_alloc`, `host_free` and `host_write`, three prototypes above the
boundary and three definitions below it; and `pipes/zero36-edit.sh` with
`pipes/zero36-check.sh`, **the core names no libc function at all** — the last two
declarations go, and by different routes: `getpid` is **avoidable outright**, its one
caller `mch_get_pid()` feeding a `b0_pid` that whim's removal of recovery had already
left write-only, so the write, the function and the field all go and nothing calls a
host; `kill` is **moved**, `vim_handle_signal()`'s `kill(getpid(), got_signal)` becoming
`host_raise(got_signal)`, which takes no pid because a core that cannot ask for its own
process id must not be handed one; and `pipes/zero37-edit.sh` with
`pipes/zero37-check.sh`, **the degenerate unions** — six of the thirteen `union`
keywords unite nothing with anything, five single-member (`uh_next`, `uh_prev`,
`uh_alt_next`, `uh_alt_prev`, `vval`) and one **empty** (`es_info`), every one a leftover
of a cut already made and the last of them a GNU extension ISO C forbids, on a
**byte-identical binary**; and `pipes/zero38-edit.sh` with `pipes/zero38-check.sh`, **the
eight terminal names** — `builtin_terminals[]` goes from ten rows to **two**,
`xterm-256color`, which is already the compiled default, and `debug`, with three
capability tables, `find_builtin_term()`'s xterm-family clause and a repair to
`set_termname()`'s no-screen fallback that is not optional; and `pipes/zero39-edit.sh`
with `pipes/zero39-check.sh`, **`-T {term}` goes** — `command_line_scan()` becomes one
`if (argv[0][0] == '+')` and one `else` answering `mainerr(ME_UNKNOWN_OPTION)`, with two
`main_errors[]` rows and their enumerators, `mparm_T.term`, and the no-screen arm of
`set_termname()` that only `-T` could reach; and then the **memline arc**, which is one
arc and not six phases — `pipes/zero40.sh`, **the instrument could not see the text
layer**, a whole-phase program that changes no source and adds the sixth part of a
recording, because a `zero-vim` with `pp->pb_pointer[idx].pe_line_count--` deleted from
`ml_find_line()`'s descent recorded **all 102 screen cases byte for byte** and forty
phases had been verified by a corpus that allocates exactly one data block a case;
`pipes/zero41-edit.sh` with `pipes/zero41-check.sh`, **freeing is free** — `host_alloc()`
a bump allocator into a 1 GiB arena and `host_free()` a function that returns, the
charter's *a garbage collector is assumed from here on* built entirely below the
boundary, with `free malloc realloc` leaving `nm -u`; `pipes/zero42-edit.sh` with
`pipes/zero42-check.sh`, **the swap file's residue** — `struct block0` with eight fields
written and none read, the negative block numbers `ml_append()`'s `newfile` could never
make, a three-layer dirtiness nothing tests and `pe_old_lnum`, none of which any tool in
`tools/` can see because **every one of them is written**; `pipes/zero43-edit.sh` with
`pipes/zero43-check.sh`, **a block number becomes a reference** — `pe_bnum` and `ip_bnum`
become `bhdr_T *`, `memline_T` gains `ml_root`, and the hash table that turned an integer
into a page goes with the free list and `mf_blocknr_max`, eleven functions and three
types; `pipes/zero44-edit.sh` with `pipes/zero44-check.sh`, **de-page the leaf** — a data
block stops being an index of byte offsets over a text arena and becomes
`DATA_LN db_line[DB_LINE_MAX]`, so a line's text is its own allocation valid for the
lifetime of the process, taking `db_index`'s 34 mentions, the fourteen interior pointers
and both `offsetof(DATA_BL, db_index)` **by having nothing left to measure**; and
`pipes/zero45-edit.sh` with `pipes/zero45-check.sh`, **fold the node types** — `bhdr_T`
becomes `struct block_hdr { short_u bh_id; }`, `memfile_T` goes entirely, a node is one
allocation at its own size (1,040 bytes for a leaf and 4,088 for a branch against 4,128
for either before), and the file gains a `static_assert` that **fails to compile** if a
later phase narrows `PTR_EN`, so
`zero-vim.c` is
now 78,666 lines
against `whim-vim.c`'s 86,617, and `access`, `fcntl` and `open` join the six libc
symbols phase 6 freed, with `getcwd`, `stat` and `strerror` at phase 10, `fclose`,
`getc`, `putc` and `fsync` at phase 13, seventeen at phase 14, eleven at phase 15 and
`_exit` at phase 17, `exit` at phase 19, `close dup isatty raise sigaddset
sigismember sigprocmask` at phase 20, `fflush fputc fputs fwrite printf putchar
stderr` at phase 21 and `free malloc realloc` at phase 41:
phases 7, 8, 11, 12, 16, 18, 22 to 40 and 42 to 45 free none and say so as an equality,
and phases
9, 10, 13, 14, 15, 17, 19, 20, 21 and 41 name the set each frees rather than the count.
**Five of those equalities are about a symbol a reader expects the phase to take**:
phase 28 says it of `gettimeofday`, 32 of `time`, 34 of `realloc`, 35 of `malloc`,
`free` and `write`, and 36 of `getpid` and `kill`, because the host still calls each one
and a symbol leaves when its last *caller* leaves the **file**. **Phase 41 reads that
rule the other way**: the callers did not move, the *calls* went, because what changed is
what is behind `host_alloc` and `host_free` and not where they are — and it is the first
zero phase since 28 to free a symbol at all. **Phase 43's equality is the one worth
reading twice**: it deletes a hash table, a free list, three types and eleven functions
and frees nothing, because all of it was **pure computation inside the file**, reaching
the outside only through `alloc()` and `vim_free()`.

**After zero phase 13 the core cannot acquire a file descriptor and holds no stdio
stream, and that is an invariant rather than a count.** `open`, `access` and `fcntl` went at phase 9 and
`stat`, `getcwd` and `strerror` at phase 10, with `chmod fchmod fstat ftruncate
lstat unlink` already gone at phase 6 — so nothing in `zero-vim.c` can name anything
on a disk, and `read`, `write`, `close` and `dup` work on fds 0, 1 and 2 alone.
Phase 10's check asserts it in both directions: the undefined set must move by
exactly `getcwd stat strerror`, none of the eleven may be back, and `read close dup
fsync` must still be there — `fsync` being `ui_write()`'s and the `FILE *` phase's.
Phases 11 and 12 assert it again while freeing nothing themselves, and **phase 13
finishes it**: `FILE` is not named in `zero-vim.c` at all (2 → 0), `fclose getc putc
fsync` are gone, and the check requires `open creat openat stat access fcntl getcwd
strerror fopen fdopen opendir` absent from **both** the source and `nm -u`. The core
can read, write, close and dup fds 0, 1 and 2 and nothing else. `ZERO-PLAN.md` §4b
states the invariant and it is assertable in that strongest form from here on.

**After forty-six phases zero-vim is 78,666 lines and 14 libc symbols, and what is
left of the host boundary is a line in the file and nothing else.** From
`whim-vim.c`'s 86,617 lines, 869,512
bytes and 79 symbols that is **−7,951 lines (9.2 %), −109,088 bytes and −65 symbols**;
the binary is 760,424 bytes, still `EXEC` with no `INTERP`, no dynamic section and no
relocation. **The file grew for the first time at phases 14 and 15** — 79,603 →
80,440 lines — because those phases move code *in*, which is the trade the symbol
count is the measure of, and 21, 22, 23, 26, 27, 31, 34, 35 and 41 each grew it again for
the same reason; 41's 68 lines are **every one of them below the first `#include`**, which
is the whole of *this phase touches no core line* and is checked as a `cmp` of
`make editor.c` rather than argued. **Phases 23, 24, 25, 26, 27 and 28 all leave the binary at exactly 788,488
bytes**, and only the first two leave it the same *bytes*: 24 is a `cmp`, 25 differs in
347,279 bytes, and 26, 27 and 28 differ because a call and a move at `-O0` are
different code. **Only three of phases 29 to 39 move the size at all**: 29 —
788,488 → 782,760, 358 sixteen-byte case-map rows out and one in — and then the terminal
pair, 38 taking eight rows and three capability tables to **781,096** and 39 taking a
parser arm and an unreachable fallback to **781,064**. The rest leave it where it was,
30 to 37 at 782,760, where 31 differs in 604,650 bytes for putting two definitions
near the front of the file, 35 in 206,588 and 36 in 397,978 for the same reason — and
**37 is the only one of them that is the same bytes**, which is its whole evidence.
**The memline arc then moves it four times and is the largest run of shrinkage since the
case tables**: 41 to **772,872**, which is smaller although the file grew by 68 lines and
`.bss` by a gigabyte, because `.bss` is `NOBITS` and musl's allocator left the link; 42
to **768,744**; 43 to **760,456**; 44 to 760,456 again — the same size, different bytes,
absorbed by alignment padding; and 45 to **760,424**.
**Phases 33 and 40 change no
source at all, as phase 3 did**, so r33's `zero-vim.c` is r32's byte for byte and r40's
is r39's, and each boundary digest is its input's — `d2a14122ccf7` either side of 33 and
`68e450fd6912` either side of 40.
**Phases 17, 18 and 19 each leave the image at exactly the same 805,544
bytes** — different bytes, the same size, the difference absorbed by alignment padding
— although 17 removed nine lines, 18 added five and 19 added eighteen. Their measure is
the symbol, not the size, and 18's is neither: it frees nothing and says so as a `cmp`.

The 14 are the terminal (`read ioctl select tcgetattr tcsetattr nanosleep`), `write`,
the clock
(`time gettimeofday`, **both of them the host's since phase 32**), signals (`sigaction
sigemptyset kill getpid`), and one gcc emit
the source names nowhere (`__errno_location`). **Not one of the 14 is called from the
core any more**: `realloc` went to the host at phase 34, `write`, `malloc` and `free` at
35, and `getpid` and `kill` at 36 — which is why there is no longer a row for *the one
syscall the core does for itself*. **And the memory row is gone outright**: phase 41 made
`host_alloc` a bump allocator over one static arena and `host_free` a function that
returns, so `malloc`, `free` and `realloc` have no caller anywhere in the file. The three
were the only users of `<stdlib.h>`, which is **dead and stays**, measured — the output
built with the directive deleted is byte-identical, 772,872 either way — on phase 13's
precedent for declining, because a phase that changes two things cannot say which one a
difference came from. `tools/symbols.sh` counts 15 because it
compiles plain `-O0` and so adds `__stack_chk_fail`. **The messages row is gone and the
"gcc's own" row is down from five to one**: phase 21 deleted every `printf` and
`fprintf` call, which took `fflush` and `stderr` with them and took `fputc fputs fwrite
putchar` — four symbols the source has never named, gcc's own expansion of
`printf("%s", x)` — with the construct. **The signals row used to be "signals and
exit", then "signals", and is now four calls the HOST BLOCK makes** — `kill` and
`getpid` were the core's last two until phase 36 and `host_raise()` makes both now:
phase 17 took the
`_exit(8)`/`exit(7)` pair that could not run, phase 19 took `mch_exit`'s `exit(r);`, the
one that did, and phase 20 took `raise sigaddset sigismember sigprocmask` with the fifty
lines of `mch_signal()` that emulated `sigset()`. **There is no row for strings,
character classes, numbers or sorting any more**: those 28 were the pure computation,
and phases 14 and 15 put them inside the file as `static` definitions rather than asking
a host for them.

**All 14 are now called from the host and from nowhere else** —
`read ioctl select tcgetattr tcsetattr nanosleep sigaction sigemptyset`, `gettimeofday`
since phase 26 put `musl_gettimeofday` in the host block, `time` since phase 32 put
`host_time()` there, `write` since phase 35, and `getpid kill` since 36 — with
`__errno_location`, which no line of either
half names and which gcc emits for the host's three `errno` mentions — **measured by
splitting
the file at the first `#include`**, which since phase 27 is an exact line and not a
region anybody has to identify. Measured on the committed `zero-vim.c` that way: **the
core's whole vocabulary of the fourteen is three English words inside string
literals** — the two `NGETTEXT`
strings in `op_shift()` that say *time*, and `E222`'s *"already read from"*. That is the
thing `nm -u` cannot show: moving a
call from the core into the host inside ONE translation unit frees no symbol, because a
symbol leaves when its last *caller* leaves the file and that is the split.
`tools/zhostonly.py` is the assertion instead — **45 host words**, `getpid` having
joined them at phase 36, every one of their 64
mentions inside the 256-line
block, and a named exception with a reason for each thing the core still says. Run on
the committed `zero-vim.c` it reports **6 of
its 18 named exceptions live in the core, and all six are one thing**: `SIGHUP` and
`SIGTERM`, three times each, in `signal_info[]`, in `deathtrap()` and as the two
enumerators phase 27 wrote with the `static_assert` that checks them against the header
below. They are there because the editor **prints** those two names. **Until phase 36
there were eight, and the two that went are the whole of what the core still said that
was not a message**: `mch_get_pid()`'s `getpid()` and `vim_handle_signal()`'s
`kill(getpid(), got_signal)`, the deferred re-raise, which is now `host_raise()` inside
the block and calls both from there. `musl_suspend()` still calls `kill` too, which is
why `HOST_MUST` can go on requiring it.
`write` was shared from phase 21 to 34, `mch_write`'s `write(1, …)` in the core and
`host_message`'s in the launcher, and **since phase 35 both are the host's**, as are the
three allocations — `host_alloc`, `host_free` and `host_write` are three prototypes at
the end of the one declaration block and three five-line definitions below the boundary.
**The clock is not split any more** — `gettimeofday` went to the host at phase 26,
because `struct
timeval` is a layout the core must not name; phase 28 replaced the out-parameter pair
with `long musl_now_ms(void)`, a **scalar**, so that no host call's shape is decided by
a type the core cannot spell; and phase 32 sent `vim_time()` over as `host_time()`, so
`time` has **no core call site at all**.
**`getpid` was the last one that was not the host's, and phase 36 did not move it — it
removed the need for it.** `mch_get_pid()` was `return (long)getpid();` with exactly one
caller, writing a `b0_pid` that nothing reads: block zero's process id, whose readers
went with recovery in `whim-vim.c` itself, so the field has had two mentions — its
declaration and that write — since before this pipeline began. The write goes, the
function goes with it, the sweep takes the forward declaration and the field, and no
host call is added at all. **Zero phase 20 saw it coming and said so**: *“`b0_pid` is
written and never read, so one line frees it whenever block zero is somebody's phase”*.
`__errno_location` is the one symbol that was never anybody's call, and phase 21 says so
rather than implying
otherwise: `errno` has three mentions and did not move at all when stdio went — the
`#include`, the `tcsetattr` retry and the `select` test — so **`<errno.h>` leaves the
CORE and the symbol leaves the process at the split**.

**`ZERO-PLAN.md` §4c is built out, and phases 35 and 36 finished it.** Its three steps
were `main()`, the two stream calls, and the terminal with its signal set; 18 and 19 did
the first, 20 did the third, 21 did half of the second and **35 did the other half** — so
**the core makes no syscall for itself at all**, and since 36 names no libc function
either. All three `write` call sites and the one
`read` are below the boundary: `musl_read_input`'s `read(0, …)` where phase 20 put it,
`host_message`'s and `host_write`'s. Phases 14 to 16
reached §4c's closing sentence early, the two rows it expected to be left in the core
being gone before the launcher existed; it expected `exit` and `_exit` still to be
there after the move, and both are gone; and it expected the third step to take
`ioctl`, `tcgetattr`, `tcsetattr`, `select`, `nanosleep` and the nine signal symbols
out of `nm -u`, which it does not and cannot. **`isatty` was the terminal's and not the
filesystem's** — three call sites, `ZERO-PLAN.md` §4a had it going, and §1's decision 7
(*"do not ask whether stdin or stdout is a terminal"*) was only two thirds kept until
phase 20 took all three. **§4c's boundary is now drawn, and it is the `boundary`
package: phases 23, 25, 26, 27, 28 and 34** — one file with two parts rather than two
files,
the `#include`s moved to line 76,689 and **the first one the line between the core and
the host**, marked by nothing else. 23 was first and deliberately the smallest, because
it is the one a `cmp` can check; 25 made the two host calls plain; 26 gave the core its
own types and macros *while the headers were still above them to check against*; 27
performed the move; **28 is the one that finished what the line is for** — it
deleted the tagless `struct timeval` mirror 26 had to invent, so that no core → host
signature's shape is decided any more by a type the core cannot name, all eighteen of
them now taking scalars and byte buffers only; and **34 is in the package because its
product is one line fewer in the block 26 wrote**, not because anything is vendored —
`realloc` is the one libc function that *cannot* be vendored, needing an old size its
interface does not carry, so the core loses it by each call site supplying the length it
already knows. Phase 24, the attributes, sits between
them in a package of its own, `dialect`, and moves no line at all; phases 30, 32, 35, 36
and 41 are
`host`, because they move a thing the core did for itself **across** a line already
drawn — 41 being the one that moves nothing and changes what is *behind* a name the
core already asked through, which is why its evidence is that `make editor.c` is
**byte-identical in and out**, 77,681 lines and 2,064,232 bytes; and 37 and 42 are
`tidy` with phase 13, because five of 37's six unions and all four of 42's groups are
leftovers of cuts already made. See *The core and the host are one file with a line in it* in `CLAUDE.md`.

**What phases 38 and 39 take is not the boundary but the terminal, and that is the
`terminal` package: 2, 38 and 39.** Phase 2 removed the **question** the core asked about
a terminal it had not been told about — the two "not to a terminal" warnings, the pause
and `--ttyfail`; phase 38 removed the **vocabulary**, eight of the ten built-in terminal
names with three capability tables and `find_builtin_term()`'s xterm-family clause,
leaving `xterm-256color` and `debug`; and phase 39 removed the **telling**, `-T {term}`,
so nothing outside the process can say what terminal this is and `+set term=` inside the
editor is the only way. **38 is the first zero phase to declare anything since phase
11**, and the first ever to use `term-moved`, a token that had been in the grammar since
phase 0 with nothing to say.

**And what the last six take is the text layer, which is one arc and not six phases —
`harness:40`, `host:41`, `tidy:42` and the `memline` package, 43, 44 and 45.** The order
is the argument. **40 had to be first**, because until it ran nothing in the pipeline
could tell a working memline from a broken one: a `zero-vim` with
`pp->pb_pointer[idx].pe_line_count--` deleted from `ml_find_line()`'s descent records
**all 102 screen cases byte for byte**, every one of them allocating exactly one data
block, so `idx` is 0 every time and a pointer entry's line count never decides anything.
`tools/zmemline.py` is sixteen cases of 200 to 25,000 lines built **in the editor** —
there is no file argument, no `:edit` and no `:read` — and its depth is measured and not
intended: a data block splits in 16 of 16 and the **root** splits in 4, against 0 of 102
for all seven markers. **41 made the work cheap**, `host_alloc()` becoming a bump
allocator and `host_free()` a function that returns, which is the charter's *a garbage
collector is assumed from here on*: the core may allocate a record per line and simply
not free it. **42 cleared the way**, four groups of swap-file bookkeeping that is
**written and never read** and that no tool in `tools/` can see for exactly that reason.
Then **43 turned a block number into a reference** — `pe_bnum` and `ip_bnum` become
`bhdr_T *` and the hash table that resolved integers to pages has nothing left to look
up — **44 let the leaf stop being a byte arena**, so a line's text is its own allocation
valid for the lifetime of the process, and **45 folded the node types**, so a node is one
allocation at its own size and `memfile_T` is gone. **45 also ends the arc's standing
hazard the only way that survives a reader who has not read the documents**: the file
carries `static_assert(PB_COUNT_MAX == (4096 - 8) / sizeof(PTR_EN), …)`, which **fails to
compile** if a later phase narrows the entry — because an 8-byte `PTR_EN` would put the
fanout at 511, the corpus's deepest case builds 391 data blocks, and root-split coverage
would go to zero **without moving one record**. That last is demonstrated and not argued:
the `fanout` control moves 0 of 118 and takes three markers from 1 to 0.

**Phase 12 is the other zero phase that declares nothing, and for the opposite
reason.** Phase 9 removed code that could not run; phase 12 removes code that *can*
run and that the instrument cannot see — no recorded case or row asks `:set ro?` or
any of the other five, bare `:set` is wiped by the Press-ENTER redraw before a
snapshot is taken, `tools/zexcmds.py` keeps no stream digest for the `set` row, and
nothing types `:set ro`, so the `W10` warning and the two `[RO]` indicators are never
drawn. Two full recordings are byte-identical, and the evidence is 27 probes on both
binaries — `ro_w10` being the one that shows behaviour going: `:set ro` on an
unmodified buffer and then an insert draws `W10: Warning: Changing a readonly file`
and pauses **1,006 ms** on the binary the phase was handed and **2 ms** here.

**Phase 13 is the third that declares nothing and it is phase 9's kind, not phase
12's — and phase 17 is that kind too**, nine lines of `deathtrap()` that no build of
zero-vim could reach, because `catch_signals()` installs with `sa_flags = 0` and
`signal_info[]` has exactly two deadly rows, so `entered` can reach 2 and never 3. Its
evidence is the same source built five ways, of which two differ in **one `sigaction`
field**: with `sa_flags = 0` a forced double signal stops at depth 2 and exits 1, and
with `SA_NODEFER` it reaches depth 3, runs the ladder and exits **7** — which is
`exit(7)` executing — and one forced signal further exits **8**, which is `_exit(8)`.
Phase 13's own argument was textual: `scriptin[]` is assigned once in the whole file — to NULL, inside the
function the phase removes — and `redir_fd` only by its own declaration, so neither
`FILE *` has ever been opened in any build of zero-vim and the phase removes the
*possibility*. Its evidence is the source it was handed, built with
`write(2, "FILESTAR-ENTERED\n", 17)` at **five** places (**0 of 106 records**) and
then with the identical instrument on `ui_write()` (**105 of 106**), plus eighteen
adversarial sessions that are each a way of making the editor *print* — which is
where `redir_write()` sat.

**Phase 9 is the one zero phase no recording can see, and it says so.** `readfile()`
was already unreachable when it ran — phases 5 to 8 had taken every way to name a
file — so its declared delta is *nothing at all*, two full recordings are
byte-identical, and the evidence is an instrumented pair: the input source built
twice, with `write(2, "READFILE-ENTERED\n", 17)` first in `readfile()` (**0 of 106
records** carry it) and then in `open_buffer()` (**104 of 106**, the identical
instrument), plus eight adversarial sessions that name the buffer after a real file
and are required to reach `open_buffer()` and not `readfile()`. An empty declaration
is a statement here rather than an omission: the phase removes code that could not
run.

**Phase 16 is the fourth, and its empty declaration is the strongest of the four
because a byte comparison settles it.** Phases 9, 12 and 13 each removed *something* —
code that could not run, code the instrument cannot see, a possibility. Phase 16
removes six `#include` lines and one typedef and **changes no code at all**, so its
evidence is not that the recording did not move but that the binary is the same bytes:
805,544 either side, both built with `SOURCE_DATE_EPOCH=0` and the boundary's own
flags. That is verification tier 1 below, and it subsumes every screen case, every
Ex-command row, every command line and every pty scenario at once, because the program
that would be run is literally the same program. Its own argument is a *computation*
rather than a list: each of the twelve surviving `#include`s is dropped in turn and the
compile must fail, and the identical loop on the source it was handed must find exactly
the six it removes — the same loop proving it can fail, in the same run.
**Phase 23 is that kind too, on three thousand edits instead of seven**: `NULL` → `nullptr`
and `size_t` → `usize` change no statement, so the evidence is `cmp` — 788,488 bytes
either side — and the control is what keeps it from being two numbers agreeing, the same
edit with the string literals *not* excluded differing by 1,598 bytes, 1,354 of them in
`.rodata`.
**Phases 14 and 15 declare nothing for a fifth reason and it is the weakest**: their
code changes and their binary moves, and the claim is that twenty-eight replacement
implementations do what the ones they replace did. Their own checks argue that.
**Phase 29 is a ninth kind, and the only one where the behaviour really did move**: both
arms of `'casemap'` change — 96 upper and 96 lower codepoints gain a mapping on the
non-internal arm and `ß → ẞ` arrives on the default one — and the corpus cannot see any
of it, because all 102 screen cases seed themselves by typing ASCII and none touches the
option. So the declaration is empty and the phase owes twelve probes, six that must
differ and six that must not, plus a claim checked over **all 1,114,112 codepoints**
with the musl half re-derived from this machine's libc rather than from the bytes the
phase deleted. **Phase 31's is a tenth**: `abs` and `labs` were never in `nm -u` at all,
gcc lowering both to inline arithmetic, so the phase's whole value is that the core
stops depending on behaviour nothing states — and the evidence is neither a `cmp` nor a
recording but an **accounting**, the object's `.text` growing by exactly 42 bytes, which
is `musl_abs` (19) plus `musl_labs` (24) plus what the three callers gained or lost
(−2, +1, 0) and nothing else. **Phase 33's is an eleventh, and it is phase 3's**: the
phase changes no source at all, so nothing about the editor's behaviour *can* have
moved, and what it has to argue instead is that the **comparison** moved safely — which
it does by measurement rather than by citation, `./zero-vim` extracted from all 33
recorded boundary tars plus `whim-vim.c` built with whim's own line giving **one digest
across every one of them** under the new question, as the old question gave one across
every one of them.
**Phases 34 and 35 are the strongest instance of a kind already on this list and not a
new one**, and it is worth saying which: their evidence is two byte-identical recordings,
which is usually the weak answer, and here it is not, because what they touch is on the
path of everything. `ga_grow_inner()` is driven **4,289 times per recording** on both
sides, 2,739 of those with `ga_data == nullptr`, and the control that keeps 34's rewrite
and copies nothing moves **102 of 102** screen cases; `lalloc()`, `vim_free()` and
`mch_write()` are entered **53,848, 22,417 and 1,012 times** over the 102 cases, and
`host_write` writing half the bytes moves 102 of 102 while `host_write` reporting half
moves 0 — which is 35's claim about the return value measured rather than argued. 34 also
owes a harness rather than probes, because **its four traps are memory bugs and not
differences**: an AddressSanitizer driver built at run time from both sources, where six
of seven controls each produce their own named finding.

Phases are added one at a time, on request. Its input is the **committed**
`whim-vim.c`, immutable, and `whim.sha` records the one a committed `zero-vim.c` was
produced from, exactly as `slim.sha` does for whim. It is born staged:
`pipes/zero.stages` (a stage per phase and seventeen packages: `seed 0`, `build 1`,
`terminal 2 38 39`, `harness 3 33 40`, `streams 4 5`, `files 6 7 8 9 10`, `buffers 11`,
`options 12`, `tidy 13 37 42`, `vendor 14 15 31`, `includes 16`,
`host 17 18 19 20 21 30 32 35 36 41`,
`format 22`, `boundary 23 25 26 27 28 34`, `casemap 29`, `dialect 24` and
`memline 43 44 45`, with `apart 2 4` — phase 2's
check runs both its binaries with `-e -s`, which phase 4 removes — `apart 4 5`,
because phase 4's check names `EDIT_STDIN`, `had_minmin`, `buflist_add` and
`ME_TOO_MANY_ARGS` as things the argv phase is still to take, `apart 5 6`,
because phase 5's check states that *it* frees no libc symbol and phase 6 frees
six, `apart 6 7`, because phase 6's check names `do_bang` as a later phase's and
requires 105 rows, `apart 7 8`, because phase 7's check names `do_ecmd` and
`otherfile` as a later phase's and requires 104 rows with `:edit` among them,
`apart 8 9`, because phase 8's check requires `readfile` at 5 mentions and
`read_buffer` at 17 and phase 9 takes both to 0, `apart 9 10`, because phase 9's
check draws its line against the name phase as counts — `b_ffname` 32, `b_fname` 29
and sixteen more — and phase 10 takes every one to 0, and `apart 10 11`, because
phases 6 to 10 all assert `E37: No write since last change` survives and name
`check_changed` as the `:q` phase's — only the last of the five is written, a stage
holding 6 and 11 holding 10 already — and `apart 11 12`, because phase 11's check pins
`p_ro` and `p_ur` at 2 mentions with their option rows and phase 12 removes both, and
`apart 12 13`, because phase 12's check pins `scriptin` at 8, `redir_fd` at 6 and
`vim_fsync` at 3 and names all three as the `FILE *` phase's, and
five `need`s, `need 7 swept` — phase 7's `usefilter` anchor counts eleven mentions on
the text phase 6's edit leaves and ten on the swept one — `need 8 swept`, phase
8's `readfile` anchor counting seven where it wants five, `ex_read` still being there
to make two of them, and `need 9 swept`, phase 9's `open_buffer` anchor counting six
where it wants five, `do_ecmd` still being there to make the one call site its
signature fold would not rewrite, `need 10 swept`, phase 10's `b_ffname` anchor
counting forty where it wants 32, `readfile()` still being there to make eight of
them, and `need 11 swept`, phase 11's `buflist_findfpos` anchor counting four where it
wants three, `buflist_findlnum()` still being there to call it from outside the island
the whole phase rests on — **`need 12 swept` and `need 13 swept` are both measured NOT
to be required**, phase 12's computation giving the same seven rows on unswept text
and phase 13's anchors all holding there) and `pipes/zero.delta`
(`2 stderr-moved`, phase 4's six records, phase 5's six command lines, phase 6's
two cases and six command rows, phase 7's two cases and one, phase 8's two cases
and five, **nothing at all for phase 9**, phase 10's one case and one row, and phase
11's one case and one row — where the row `quit` is the first zero has declared that
**changes message rather than ceasing to exist** — and **nothing at all for phases
12 and 13**, and **nothing at all for 14 through 37** —
where 16's, 23's, 24's and 37's empty declarations are the fourth kind above, a byte-identical
binary; 18's, 19's, 21's, 25's, 32's, 34's and 35's are a sixth, the code runs and the
instrument sees it
do the same thing; 20's, 22's, 28's and 30's are phase 2's and phase 12's, the code runs
and the instrument cannot
see it, so each owes probes and they run fifteen, 263, four and 36 of them; 26's is a seventh,
six of its seven changes a `cmp` and only the clock a recording; 27's is an eighth,
**the source is the same lines rearranged** — not one of the input's 80,197 lines
missing and 35 added — because a phase that moves 1,568 lines of definitions can have no
`cmp` at all; 29's is a ninth and the one where behaviour really moved, on both arms of
`'casemap'`, invisible to a corpus that types ASCII; 31's is a tenth, an accounting
of 42 bytes of `.text` for a phase that frees no symbol because there was none to free;
33's is an eleventh, a phase that changes no source at all, where what has to be
argued is that the comparison moved safely and not that the editor did not; and **36's is
phase 2's and phase 12's again** — the code runs and the instrument cannot see it — where
the two halves are invisible for **opposite** reasons, the `b0_pid` write running in 102
of 102 screen cases and moving nothing because nothing reads the field, and the deferred
re-raise firing in **0** of 102 because no keystroke corpus sends the editor a deadly
signal, so the phase owes probes and builds six binaries of its own — **and then
`38 term-moved` and phase 39's four command lines, the first lines the file has gained
since phase 11 that are not a comment**: 38 moves eight of `tools/ztermcheck.py`'s
nineteen rows, each from `term=<itself>` to `E522 term=xterm-256color t_Co=256`, and 39
moves `-T xterm`, `-T no-such-term-9x`, `-T` and `-Txterm`, **two of which were already
errors and moved anyway** because the messages they gave were `ME_ARG_MISSING` and
`ME_GARBAGE`, enumerators whose last use was the argument block that went — **and then
nothing at all again for 40 to 45**, which between them are four of the kinds already on
this list: 40's is 33's and 3's, no source changed at all; 41's and 43's are the sixth,
the code runs and the instrument sees it do the same thing — 43's being the strongest
instance the pipeline has, because every keystroke this editor draws reaches its text
through the function it rewrites; 42's is phase 9's and phase 12's **at once**, code that
could not run and code that runs everywhere and the instrument cannot see, both carried
by one instrumented build over **252 records**; and 44's and 45's are the **weakest**,
phases 14 and 15's, the code changing and the binary moving with nothing but controls to
say a replacement does what the original did — eleven of them for 44 and twelve for 45,
each with the three that must *not* move named with the reason each cannot be seen),
checked
by `tools/stages.sh zero` and `tools/packages.sh zero` as whim's are. The last two
`apart` lines are the same shape as `apart 5 6`: `apart 14 15`, because each of those
two checks states that the undefined set moved by exactly *its* symbols and a stage
takes one snapshot at its start, and `apart 15 16`, in both directions — phase 15's
check requires `<ctype.h>` and `<wctype.h>` still present, and phase 16's states as a
`cmp` that it frees nothing while phase 15 frees eleven — and `apart 16 17`, in one
direction only: phase 16's check requires the file to have lost exactly eight lines and
phase 17 takes nine more, while phase 17's own check passes on a shared stage. The
last two are the same shape and both measured: `apart 17 18`, because phase 17's check
requires the file to have lost exactly nine lines and 18 adds five (`the file lost 4
lines, expected 9`), and `apart 18 19`, because phase 18's check builds its own control
by rewriting `mch_exit`'s `exit(r);` and phase 19 has replaced that line (`the control
edit changed nothing`) — each in one direction only, the later phase's check passing on
the shared stage either time. **`apart 19 20` is the first that is both directions**,
and its measured message is the one a reader would not predict: `tools/phaserun.sh zero
19-20` on r18 stops in phase 19's check with ``deathtrap` as a whole word has 4
mentions, expected 3` — a phase about *removing* signal handling leaves one MORE
mention of a handler, because the host installs the core's `deathtrap` rather than
replacing it. The other direction is reasoning rather than a second run, because 19's
check refuses first and there is nothing after it to observe: phase 20's check states
its gone set as one `comm` against the stage's symbol snapshot, and a stage takes one
snapshot at its start, so on a shared stage it would be handed r18's set and the gone
set would be its seven plus `exit`. That is `apart 14 15`'s shape.

**The last three are measured too, and each is one direction only.** `apart 20 21`:
phase 20's check states the twelve `#include` directives as a property it preserves and
phase 21 takes `<stdio.h>`, so a 20-21 stage stops with *"the output does not have
exactly the twelve `#include` directives phase 16 left"* — and the same run measures the
other half, phase 21's edit applying unchanged to phase 20's unswept output, which is
why there is no `need 21 swept`. `apart 21 22`, and its first complaint is not the
predicted one: ``printf` has 4 mentions, expected 10` — **six of phase 21's nine
`format(printf, …)` attributes sit on the wrapper prototypes phase 22 deletes**, which
is phase 21's own counting trap read from the other end. And `apart 22 23`, where a
phase that renamed nothing breaks on a phase that renamed two type names: phase 22
writes its four controls by matching the helpers' text **verbatim**, two of the three
hold `if (IObuff == NULL)`, and phase 23 spells that `nullptr` — so it stops at its
first act with ``iobuff_room` is not in the output exactly once, so the controls below
would not be controls`. **A check that quotes C is a dependency on spelling**, and that
is the general form of it.

**The last four continue the pattern, and one of them is the general form of a second
dependency.** There is **no `apart 23 24` and no `need 24`** — measured in one run,
where `tools/phaserun.sh zero 23-24` on r22 runs both edits, one sweep and both checks
and every part passes. `apart 24 25`'s first complaint is the one nobody would predict:
**phase 24 records the six `format`/`format_arg` lines it keeps by LINE NUMBER**, and
phase 25 deletes an object with its blank line at 495, so everything below moves up by
two and the check stops at *"a line carrying a kept attribute is not the line it was,
byte for byte"*. **A check that pins a line number is a dependency on every line above
it**, which is the spelling trap one level up. `apart 25 26` is phase 25's line-count
assertion meeting the twenty-four lines phase 26 adds, and `apart 26 27` is phase 26's
sixteen `static_assert`s and four wrong declarations, **every one of which needs the
headers above the core** and none of which can compile once they are below. Each is one
direction only, the later phase's check passing on the shared stage, and **`need 25`,
`need 26` and `need 27` are all measured not to be required** — phase 26's case by a
direct `cmp`, phase 25's edit on r24 giving a `zero-vim.c` byte-identical to r25's.

**Phases 28 to 32 add eight more `apart` lines and no `need` at all** — each of the five
was measured to apply unchanged to the unswept text before it. `apart 27 28` is the
neatest of all of them: phase 27's boundary argument rests
on moving **one core function below the cut** as a control, the function it picked is
`elapsed`, and that is the function phase 28 deletes — so the check stops at its first
act with *"`elapsed` is not defined exactly once above the boundary, so the control that
moves one core function below it would not be a control"*. `apart 28 29` is arithmetic:
phase 28 states its own as a line count **of the core**, and a 28-29 stage gives it
*"the core is 77978 lines and was 78359, a difference of −381 where −16 was expected"*,
its −16 less phase 29's −365. `apart 30 31` is `apart 17 18`'s shape — phase 30's line
count meeting the ten lines phase 31 adds to the same swept text. `apart 21 30` could
not be run at all, seven phases and their state directories sitting between the two, so
it was measured by **applying phase 21's pin table directly** to the tree phase 30
leaves: of its thirteen pinned names seven are already broken by phases 22–29, four are
untouched, and exactly two move here. And phase 32 carries **four**: 26 and 27 both hold
the nine-entry `PROTOS` list and now find three of the nine at 0, and 27 and 28 both
**write the boundary out as thirteen names** where phase 32 makes it fourteen — which is
the argument for computing a set at run time rather than quoting it, made from the
losing side.

**Phases 33 to 36 add ten more, and one pair is forbidden rather than declared.** 34
carries three — `apart 26 34` and `apart 27 34`, because both those checks assert
`void *realloc(void *p, usize n);` on a line of its own exactly once and it is not there
any more, and `apart 30 34` in **both** directions, phase 30's line count meeting the ten
lines 34 adds and 34's meeting the eighty-one 30 removes. 35 carries six: 26 and 27's
`PROTOS` list again, now with **seven** of its nine at 0 and only `getpid` and `kill` at
1; 27 and 28's written-out boundary, seventeen names where 32 made it fourteen;
`apart 30 35`, which is the sharpest instance this pipeline has of *a check that CALLS
libc from above the boundary is a dependency on the core still declaring it* — phase 30's
check writes `write(2, "T-cleos\n", 8);` **into the core** to build an instrumented
control, so run as a pair it does not compile at all; and `apart 34 35`, measured as a
real shared stage, where phase 34's check stops four ways and two of them are
`apart 22 23`'s lesson landing on the phase that had just taught it — 34's check matches
the code it wrote **verbatim**, `pp = malloc(new_len);` and `free(gap->ga_data);`, and 35
renames exactly those calls. **There cannot be an `apart 33 34` at all, and that is a
measurement and not an omission**: a stage of more than one phase is made of split
programs and `pipes/zero33.sh` is ONE file, so `stage 33-34` is refused before any check
runs — `phase 33 is in stage 33-34 but is not an edit and a check` from
`tools/stages.sh`, and `zero phase 33 has no edit and check to run` from
`tools/phaserun.sh`. **No `need 33`, `need 34`, `need 35` or `need 36`** — 35's measured
three times, on phases 30's, 32's and 34's unswept output, and 36's on 35's, with the
prototype it is about to orphan still there and `b0_pid` still a field.

**Phase 36 carries exactly one `apart` line and the reason it carries only one is worth
copying.** `apart 35 36` was measured as a real shared stage on r34, and phase 35's check
stops three ways, the first being the block the phase exists to empty: *the ordinary
declarations above the boundary are none and the input's block minus the three is
`int getpid(void); / int kill(int pid, int sig);`*. Six further lines — 26, 27, 28, 30, 32
and 34, every one of whose checks this output also breaks, 26's and 27's nine-entry
`PROTOS` list reaching **zero of nine** on it — are **deliberately not written**, because
every one of them is already broken by phase 35 and recorded against it, and any stage
holding 36 and one of the six would have to hold 35 too. **A redundant `apart` nobody
measured is worse than none.**

**The last three are one each, and two of them are arithmetic.** `apart 36 37` is the
only one of the three measured in **both** directions, both phases being split: 36's
check stops on its own line count — *the file is 79786 lines and the input was 79804
(79804 recorded) — expected 79799* — and, run the other way on exactly the tree the
driver would hand it next, **37's check stops too**, with *the six declarations are 13
lines shorter between them* and *the boundary moved by 15 lines and the file by 13*. The
two extra lines are **phase 36's residue**, `mch_get_pid`'s forward declaration and the
`b0_pid` member, which 36 leaves for the sweep on purpose, arriving inside 37's
arithmetic because a stage sweeps **once**, at the end: *a phase that states its line
count against its own edit cannot share a sweep with a phase that leaves work for it.*
`apart 37 38` is `apart 17 18`'s shape — 37's line count meeting the 118 lines 38 takes
out of the same swept text — and `apart 38 39` is the sharpest form of `apart 22 23`'s
lesson this pipeline has: phase 38's check builds its first control by finding **the
fallback it repaired**, and phase 39 deletes that fallback, so a 38-39 stage stops at 38's
**first act** with *set_termname() names 0 of the surviving rows and this check needs
one — the fallback*. **A check that depends on the code the phase repaired is a
dependency on the next phase not needing it.** No `need 37`, `need 38` or `need 39` —
37's and 39's measured on the unswept output before them, 38's reported as **vacuous**,
phase 37's sweep removing nothing at all.

**The memline arc adds three `apart` lines and two `need`s, and one `apart` is forbidden
rather than declared.** There is **no `apart 39 40` and no `need 40`**, for the reason
there is no `apart 33 34`: `pipes/zero40.sh` is one file, so `stage 39-40` is refused
before any check runs — *phase 40 is in stage 39-40 but is not an edit and a check* from
`tools/stages.sh` and *zero phase 40 has no edit and check to run* from
`tools/phaserun.sh`, both measured — and `need` is a statement about an **edit part**,
which a whole-phase program has none of. **`apart 41 42` is measured and is not the
mechanism the phase predicted**: it expected `apart 14 15`'s shape, an undefined-set
equality against a stage's one snapshot, and what actually fires is phase 41's **own
promise** — `tools/phaserun.sh zero 41-42` on r40 stops with *the text above the first
`#include` is not byte-identical in and out, and this phase is entirely below it*. **A
phase that promises to touch no core line cannot share a stage with one that deletes 366
of them.** **There is no `apart 42 43`, deliberately**, although phase 42's check quotes
verbatim two lines phase 43 rewrites and would stop: `need 43 swept` already forbids the
only stage that could hold both, `tools/stages.sh` answering *43 needs swept input and
does not start a stage (42-43)* and exiting 1 before any check runs, and **an `apart`
nobody can measure is phase 36's rule**. **`apart 43 44` is `apart 36 37` in its sharper
form**: phase 43 states the division between its edit and its sweep as a **partition over
names**, a stage sweeps once at the end, and the ten names phase 44's edit orphans land
in phase 43's sweep set, so the check stops naming all twelve — *36-37 was that lesson in
a line count; this is the same lesson in a set, and a set is what a later phase is more
likely to state.* And `apart 44 45` is phase 44's own scope statement read from the other
end, and needed no reasoning: that phase wrote that `offsetof(PTR_BL, pb_pointer)`
measures a **pointer** block and is not the leaf, and says it as a count of 1, so running
its check on the r45 tree gives *`ml_new_ptr`'s offsetof moved*.

**`need 43 swept` and `need 45 swept` are both required, and neither breaks where a reader
would guess.** 43's is not a counted anchor at all: phase 42 leaves `mf_hash_free_all`
standing for the sweep and its **forward declaration** names all three types 43 deletes,
so the edit runs to its last act and refuses with *names this phase removes are still
said: `blocknr_T` 1, `mf_hashitem_T` 1, `mf_hashtab_T` 1* — **the cut applied cleanly and
the partition refused, which is what a partition is for.** 45's is **the first in this
pipeline about blank lines**: the edit asserts it leaves no run of two blank lines
anywhere, which is a statement about *this* edit only if the text it was handed had none,
and phase 44's unswept output has one at line 33,815 that `canon.py` removes in phase 44's
sweep. **The order of those two tests is the whole of it** — asked the other way round the
refusal blamed this phase for the previous one's residue. There is **no `need 42`** for a
reason stronger than a stage measurement (phase 41's sweep is a **no-op**, so there is no
unswept text to be handed at all) and **no `need 44`**, measured as an *equality* rather
than as a run that did not refuse: handed phase 43's unswept output, the file the one
sweep leaves is byte-identical to the sequential run's, 78,859 lines either way.

**Phase 35's anchors are a partition and not a count, and phase 34 is why.** It first
asserted `malloc` at 2 mentions, `free` at 3 and `write` at 2 — the counts measured on
the boundary it was written against — and then phase 34's `realloc` rewrite took two of
them to 4 and 5 and the anchors **refused**, which is what a counted anchor is for. Both
programs now assert the *shape* instead: every mention of each name above the boundary is
its own declarator or a call of it, the declaration goes, every call is rewritten, and how
many there are is read off the text — with a mention that is neither, an address taken or
a variable of the name, refusing rather than surviving into a file whose declaration is
gone. That is *Rename a name across the whole file* in `CLAUDE.md`, and the general rule it states:
**assert a partition, not a count**, because a count is a fact about a tree that was
measured and a partition is a fact about the tree that arrives.

**A phase can break a harness rather than change behaviour, and the two must not be
confused.** `tools/termcheck.py` — whim's, and the one instrument the three
pipelines shared — asks `:set term? t_Co?` with a file argument on the command
line, so from zero phase 5 it records nineteen empty rows. Declaring `term-moved`
for that would have switched the terminal table off for every later phase; instead
`tools/ztermcheck.py` imports `termcheck.py` and replaces the one call that passes
a file, and it is proven to record the baseline's nineteen rows from the binary
phase 5 was handed and from `whim-vim.c` in phase 0. `termcheck.py` itself is
untouched, which is what keeps whim's and slim's keys where they were; only
`tools/zrecord.sh` names the new tool, and that re-keyed zero's five earlier phases
and nothing else.

**And a harness can be blind for a reason that has nothing to do with the phase it is
run for.** That is what zero phase 33 found and fixed. `ztermcheck.py` still asked
`$TERM`, and **whim phase 19 had removed the `getenv("TERM")` the editor read it with** —
*the terminal is what the build says* — so all nineteen rows of
`.reference/zero-baselines/ref-term.txt` said `term=xterm-256color t_Co=256`: nineteen
ways of recording that the environment does nothing. It was content-free and measurably
so — **a prototype that deleted eight of the ten built-in terminal names and three of the
nine capability tables, 118 lines of terminal description, passed `tools/zcompare.py`
against the real baselines declaring nothing at all**. The question is now
`+set term={name}` on the command line, which reaches `did_set_term()`, and a refused
name answers `E522 term=<the terminal the editor stayed on> t_Co=…` — the error *and*
the terminal, which is what makes a refusal distinguishable from the old vacuous row.
**The new instrument is proven able to
fail and the old one proven not to be**, in one measurement: with one row deleted from
`builtin_terminals[]` the new table moves exactly 1 of 19 and the old one moves 0 of 19.
**And the prototype then became phase 38**, which is why those nineteen rows now read
**two names resolving to themselves, sixteen refused as `E522 term=xterm-256color
t_Co=256` and one `E529`**, the empty string, which `'term'` refuses before any table is
consulted.
**The re-record was safe because the baseline and every phase's recording move
together**, and `pipes/zero33.sh` measures that rather than citing it: `./zero-vim` out
of every recorded boundary tar **up to its own number** plus `whim-vim.c` built with
whim's own line gives one digest across every one of them, so `term-moved` stays
undeclared at every phase before it. The incantation, and **both halves are needed** —
measured, with only
`.cache/r0` removed `pipes/zero0.sh` refuses and names `ref-term.txt`, which is right —
is `rm -rf .reference/zero-baselines .cache/r0 && make zero-phase-0`.

**That bound is a repair, and the rule behind it is general.** The loop globbed
`.build-zero/r*.tar` and required one terminal table across **all** boundaries, which was
true when it was written and reaches boundaries that did not exist then — so phase 38
moving the table on purpose made **phase 33's** check fail, measured with 38's tar
present: *r38 records a different table:*, exit 1. **A phase may assert anything it likes
about the past; it may not assert that the future will not change what it measured.** And
the place it would have struck is worth knowing: `make zero-verify` could never have
caught it, because a verify scratch root links `tools/`, `pipes/` and the baselines and
has **no `.build-zero`**, so section 4 takes its "no boundary binary" arm there. It would
have struck a sequential `make zero-repass` in the repository root — the run that
*produces* boundaries rather than checking them, and the more expensive one to lose.

**A declared delta of none can be a harness that cannot see the phase**, and zero
phase 2 was the case: `behaviour.py` and `exsweep.py` run the editor `-e -s`, where
Ex mode takes `check_tty()`'s other branch, and `termcheck.py` drives a real pty
where both streams *are* terminals — so nothing recorded ever held those warnings.
Its check therefore builds the binary the phase was **handed** and requires the old
one to warn and pause (85 bytes of stderr, 2,010 ms) and the new one not to (0 bytes,
5 ms), with the 2,108-byte escape stream byte-identical. **When a phase's delta is
none because the harnesses are blind rather than because nothing moved, the phase
owes probes of its own** — and when a later phase gives the pipeline an instrument
that *can* see it, the delta is declared where it happened: phase 3 made
`2 stderr-moved` true and checkable, at r2 and at every boundary after it.

**Zero's instrument is the screen, and it is zero's own** (phase 3, `ZERO-PLAN.md`).
A recording is `tools/zrecord.sh`: keystrokes in a file on stdin, escape sequences
out on stdout, and a 24x80 screen rebuilt from them by `tools/zscreen.py` — snapshot
at every `\x1b[?25h`, which is where a redraw ends, and which is the only reason the
message line is recordable at all. **Six parts and 122 records**, where phase 3 made five
and 106: 102 keystroke cases that type their
own text under `'paste'` (`zcases.py`), every Ex command typed at `:` and recorded by
the message it prints (`zexcmds.py`), every command line the parser may see
(`zargv.py`), five pty scenarios for the window size, raw mode and a modified key
(`zpty.py`),
the terminal table (`ztermcheck.py`, whim's `termcheck.py` asked without a file
argument and, since phase 33, with `+set term={name}` instead of `$TERM` — see above),
and, since **phase 40**, sixteen memline cases of 200 to 25,000 lines built in the editor
(`zmemline.py`), which are the only part that can see the text layer as a tree.

**A memline record carries `stream N redraws` and no digest, and that is a defect phase
40 found rather than a shortcut.** `tools/zrec.py` scrubs the undo message's age padded to
the width it replaces, so the *screen* is protected — but the leak is **arithmetic on that
text's width**: an undo reports its age and the editor then positions the cursor to clear
the line, so `0 seconds ago` emits `\033[24;40H\033[K` and `1 second ago` emits
`\033[24;39H`, a column derived from a scrubbed string's length and living in bytes the
scrub never touches. **Hashing the scrubbed stream would not close it.** It failed zero
phase 16, whose binary is byte-identical either side, which is the only reason it was
catchable. What replaces the digest is stronger than one: both clocks the core can read
replaced by runaway counters move **0 of 16 memline records against 9 of the 102 screen
cases**, which says the record does not depend on the clock **at all**. `zcases.py` still
digests the raw stream and that is **open**: the `--- stream` line is named in eighty
files, forty-seven times in zero phase 12's check alone, so it is expensive rather than
difficult and deserves a pass of its own.

**Adding a part to a recording breaks every check that pinned its size, and there is no
way to add one that does not.** A new part is a new **file** whatever shape it takes, so
`zpty.py`'s precedent — one record however many scenarios it holds — could not be
followed; measured, zero phase 9 stopped with *a recording is 122 files, not the 106 this
phase counted*. Four phases had tested the count as an **equality** (9, 13, 30, 34) and
four as a floor of 100 (25, 35, 36, 37), and only the four equalities broke. They are now
**computed** — phase 9's control must mark *total − 2*, quiet only in `ref-pty.txt` and
`ref-term.txt`, and the other three take the floor their siblings already use — which is
this file's own rule that **a number a phase cannot move is reported and not pinned**.
The same rule is why `zpty.py` and not `zcases.py` got the `keymodel` repair's scenario.
It is deterministic — three recordings
per phase 0 and phase 3 run, identical, *including the sha256 of every stdout
stream* — and it is proven able to fail: `do_addsub()` returning `FAIL` moves exactly
11 of the 102 cases. The file-based `behaviour.py` and `exsweep.py` are untouched:
they are whim's and slim's, and phase 3 keeps `whimdelta.sh` as the one bridge
between the two pipelines' recordings.

**Three things differ from whim, and each was decided rather than inherited:**

- **The compile line is `gcc -O0 -fno-stack-protector -static -no-pie -s`.** The
  seed adds `-no-pie` (`tools/templates/zero.mk`), which is why `readelf -h zero-vim`
  says `EXEC` where whim-vim and slim-vim say `DYN`: see *The binary is standalone* in `CLAUDE.md`.
  Phase 1 adds `-fno-stack-protector` by editing the boundary's `zero/Makefile` —
  never the template, which is the pipeline's input and in r0's digest. The product
  rule cannot read `zero/`, so `zero.mk` states the flags once more, as `ZEROCFLAGS`
  and `ZEROLDFLAGS`, and `zero-pass` refuses to copy `zero-vim.c` out when they
  differ from the last boundary makefile's `CFLAGS` and `LDFLAGS` (proven to refuse).
  `make score` passes both to `tools/score.sh`, so zero's symbol count is taken with
  zero's flags.
- **Zero's behaviour is measured against its own baselines**,
  `.reference/zero-baselines`, which zero phase 0 records from `whim-vim.c` built
  with whim's compile line. So `pipes/zero.delta` starts empty and each zero phase
  declares only what it changes relative to whim, checked by `tools/zerodelta.sh`
  — `whimdelta.sh`'s rule and grammar against those baselines. Phase 0 also runs
  the harnesses on the `-no-pie` binary and requires no difference at all, and
  runs `tools/whimdelta.sh --phase 82` on it against slim-vim's baselines, which
  still holds: 489 commands and 11 cases, exactly whim's declared delta.
- **Zero's phase list is the `phases` line of `pipes/zero.stages`**, not a
  `PHASE_LIST` written into `tools/pipeline.sh`, because `pipeline.sh` is in every
  whim split key (above) and a zero phase added there would re-key all of whim.


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
6. **`make zero-pass`, which is the step that copies the product out.** `zero-tip`
   records a boundary and nothing else; the tracked `zero-vim.c` is an **output** of the
   memoize and an input to nothing, so it can be arbitrarily wrong while every boundary
   reproduces. Measured: running only the first left the tracked product **two phases
   stale** — r36's 79,799 lines while the pipeline was at r38's 79,668 — and it was
   pushed in that state, with `make zero-verify` reporting every boundary reproducing,
   correctly, throughout. `zero.mk` now **warns** when the tracked file is not the last
   boundary's, printing what it is, what it should be and the one command that fixes it;
   it is a warning and not a failure because between a phase landing and `zero-pass`
   running the product is *expected* to lag, and a target that refused there would be
   disabled within a day. The contributing half is that a phase branch need not carry
   the product — 37, 38 and 39 each committed their programs and their manifest lines
   and not `zero-vim.c` — so the guard is at the merger's end.

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
ioctl fails on a pipe. Five parts, and a recording is all five — **six since phase 40**,
and 122 records where this phase made 106:

| | what it is | how big |
| --- | --- | --- |
| `screen/` | `tools/zcases.py`: 102 keystroke cases, one record each | 141 KB |
| `ref-excmds.txt` | `tools/zexcmds.py`: every Ex command name typed at `:` | 111 rows |
| `ref-argv.txt` | `tools/zargv.py`: every command line the parser may see | 30 rows |
| `ref-pty.txt` | `tools/zpty.py`: what only a real terminal shows | 4 scenarios, 5 since the `keymodel` repair |
| `ref-term.txt` | `tools/ztermcheck.py`: whim's `termcheck.py` with no file argument (phase 5) | 19 terminals |
| `memline/` | `tools/zmemline.py`, **phase 40**: buffers big enough to make the text layer a tree | 16 cases |

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
left in the core after that move; they are already gone.** Phases 18 and 19 are the
demotion itself: the launcher exists, at the bottom of the same file, and the core
asks it to end the process rather than ending it.

## Phase 17 — the deadly ladder that cannot run

`pipes/zero17-edit.sh` and `pipes/zero17-check.sh`, `stage 17`, `package host`. Nine
lines, one libc symbol, and the smallest zero phase so far. `deathtrap()` — the handler
for the deadly signals — opens with a ladder that counts how often it has been entered:

```c
    if (entered >= 3)
    {
        reset_signals();
        if (entered >= 4)
        {
            _exit(8);
        }
        exit(7);
    }
```

**`entered` cannot reach 3 in any build of zero-vim**, so this removes a *possibility*
and not a behaviour. That is phase 13's kind of cut rather than phase 9's: phase 9 took
code that had *become* unreachable, when phases 5 to 8 removed every way to name a file,
and this — like the two `FILE *` — was never reachable in anything the pipeline has ever
produced.

### Why it cannot run, and why the obvious reason is the wrong one

Two facts, and **neither is zero's doing**:

* `catch_signals()` installs the deadly handler with `sigemptyset(&sa.sa_mask)` and
  **`sa.sa_flags = 0`**. No `SA_NODEFER`, so the signal being handled is blocked for the
  duration of its own handler.
* `signal_info[]` carries exactly **two** rows with `deadly = TRUE`, `SIGHUP` and
  `SIGTERM`. `SIGSEGV`, `SIGBUS`, `SIGILL` and `SIGFPE` are at **zero mentions** in
  `zero-vim.c` — whim removed all four — so there is no third deadly signal to arrive.

Two signals, each blocked inside its own handler, lets `entered` reach **2** — TERM
nested inside HUP's handler or the reverse, which is the `Vim: Double signal, exiting`
arm, and that arm calls `getout(1)` and never returns. It cannot reach 3: by then both
are blocked and nothing else is caught.

**The wrong reason is available and would be wrong elsewhere.** A phase that removed the
ladder because *"`reset_signals()` makes it unreachable"* would have the right answer for
the wrong reason — `reset_signals()` is **inside** the ladder and is never reached — and
would be wrong on any tree with three deadly signals. What the edit asserts, character for
character, is the two-row table and the `sa_flags = 0` arm, on the **output**, so that a
later phase cannot quietly falsify either without this check saying so.

### The argument is two binaries differing in one field

`pipes/zero17-check.sh` instruments the source the phase was **handed** —
`write(2, "DTn\n", 4)` immediately after `++entered;`, and `write(2, "DTLADDER\n", 9)` as
the first statement inside the ladder — and builds it five ways:

| | what it is | what it must report |
| --- | --- | --- |
| `in_mark` | the input, marked | **bombarded**: 8 concurrent sessions, 60 alternating SIGTERM/SIGHUP each at full speed. Every session reaches the handler, **the maximum `entered` ever observed is 2**, `DTLADDER` never appears |
| `in_forced` | plus `raise(SIGHUP)` in `preserve_exit()` and `raise(SIGTERM)` in the `entered == 2` arm | exactly `DT1 DT2`, no ladder, **exit 1** |
| `in_nodefer3` | the same source with **one field changed**, `sa.sa_flags = SA_NODEFER` | `DT1 DT2 DT3`, `DTLADDER`, **exit 7** — `exit(7)` running |
| `in_nodefer4` | plus one more forced signal at `entered == 3` | `DT1..DT4`, `DTLADDER`, **exit 8** — `_exit(8)` running |
| `out_forced` | **the output**, instrumented and forced identically | `DT1 DT2`, exit 1, and the same screen `in_forced` drew |

**`in_forced` and `in_nodefer3` are the whole phase in two binaries.** They differ in one
`sigaction` field and nothing else, and the ladder runs in one and not the other — so
both statements this phase deletes are live code that only the signal mask keeps out of
reach, and the bombardment's zero is a probe that is *proven* able to report otherwise.
That is phase 13's `ui_write()` control in this phase's shape, and it is stronger: the
control is not a different place in the program, it is the same place with the reason
removed.

The bombardment's assertion is deliberately **one-sided** — no session may report 3 or
more — so machine load can only ever weaken it, never make it fail spuriously. What load
*could* do is stop a session reaching the handler at all, which would make the zero
meaningless, so every session is required to have reported a depth. Measured over eight
runs: 8 of 8 sessions always reach it and between 2 and 8 of them reach depth 2.

### The stream is not comparable, and the screen is

The uninstrumented pair — the binary the phase was handed and the one it made — is sent a
single SIGTERM and a single SIGHUP, and the two must agree. **They cannot be compared as
byte streams.** The editor emits `\x1b[?4m`, a private mode that draws nothing, at a point
that depends on when its own flush happened: measured, `in_forced` and `out_forced` came
back 2,136 bytes each, byte-for-byte equal in three runs out of six and differing at
offset 2,003 in the other three, the whole difference being those five bytes sitting
before `\x1b[?25l` rather than after `\x1b[?25h`. The plain pair flaked the same way.

So the comparison is **what the editor drew** — `tools/zscreen.py`, zero's own instrument:
every snapshot, the final screen and the bell count, none of which a private mode touches
— beside the exit status and stderr, which are bytes and are compared as such. And the
screen is required to *carry* `Vim: Caught deadly signal TERM`/`HUP` and `Vim: Finished.`,
so the equality is not two blank screens agreeing. Six consecutive runs of the whole
phase were green.

**The harness waits on content, not on a clock**, for the same reason. A fixed sleep
signals the editor wherever its redraw had got to, and with sixteen sessions running at
once that is a recording of the machine's load; a quiet-for-300 ms drain was still wrong
once, on a startup that took longer than that to produce its first byte. The wait is for
the typed text to be on the screen *and then* for quiet, and a session that never gets
there is reported rather than compared.

### The counting trap

`exit` is a word this file uses for four things that are not a call. In the input:

```
    "Type  :qa!  and press <Enter> to abandon all changes and exit Vim"   a string
    "Type  :qa  and press <Enter> to exit Vim"                            a string
            exit(7);                                              this phase's
        exit(r);                                                  mch_exit's
                        goto exit;                                a goto, and
exit:                                                             its label, both
                                                                  in vim_regsub_both()
```

So **`assert exit at 0 mentions` fails on a correct phase**, and `assert 'exit(' at 0`
fails on `mch_exit(`, `preserve_exit(` and `getout(`. The assertion that works is
**`nm -u`** — the gone set is exactly `{_exit}`, nothing arrives, and `exit` is required
to be *still* undefined, being `mch_exit`'s and a later phase's. `_exit` as a word is
unambiguous, the label being `exit`, and it is asserted as well.

### Nothing is orphaned, and `reset_signals()` is the one that looks as though it should be

The ladder held one of `reset_signals()`'s four mentions; `mainerr()` holds another, so
the function stays and the check pins it at three. The sweep after the edit is a complete
no-op — 0 prototypes, 0 functions, 0 variables, 0 types, 0 fields, 0 enumerators, `canon
settled` — and `funcreach.py` reports 1,755 of 1,755 definitions reachable either side.

### The declared delta is nothing at all

`pipes/zero.delta` gets a comment and no line, and the reason is the statement. Five
phases now declare nothing and each for a different reason: **9** removed code that could
not run, **12** removed code that can run and that the instrument cannot see, **13**
removed the possibility, **16** changed no code at all, and **14** and **15** replaced
code with code that computes the same answers. **This one is 13's**: the ladder has never
been reachable in any build of zero-vim, so a recording that *moved* would mean the cut
was wrong. `tools/zerodelta.sh --phase 17` finds the corpus unmoved, as it must.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 80,432 | **80,423** (−9) |
| functions | 1,755 | 1,755 — untouched |
| type definitions | 907 | 907 |
| DWARF enumerators | 1,181 | 1,181 |
| `nm -u`, as `phasecheck.sh` counts it | 34 | **33**, gone set exactly `{_exit}` |
| `nm -u` with zero's own flags | 33 | **32** |
| external symbols | `main` | `main` |
| `#include` | 12 | 12 |
| binary | 805,544 | **805,544 — the same size, different bytes** |
| sweep | | **1 round, a complete no-op** |
| phase | | **17 s** |

**Nine lines of code that never ran cost no bytes at all**, which is worth saying because
it is the opposite of what the line count suggests: the image is the same 805,544 and the
two binaries are not the same bytes, so what the ladder occupied was absorbed by alignment
padding. This phase's measure is the symbol, not the size.

### Its placement

`stage 17`, `package host` — new, and it is where `main()`'s demotion and `mch_exit`'s
one remaining `exit(r)` will go — with two `uses` lines, `exit:17 seed:0 mechanical` and
`exit:17 harness:3 mechanical`, which is what every phase declaring "nothing moved" owes.

**`need 17 swept` is not required**, and the anchors say why: every one is exact text at a
counted occurrence — the nine-line ladder, the six `exit` lines one by one, `signal_info[]`
and `catch_signals()`'s deadly arm — and none of it is text any sweep has ever touched.

**`apart 16 17`, measured.** Phase 16's check requires the file to have lost **exactly
eight** lines and this phase takes nine more: `tools/phaserun.sh zero 16-17` reports *"the
file lost 17 lines, expected 8"* and exits 1. Its libc check would fail as well — phase 16
states as a `cmp` that it frees **nothing**, inside a stage every check compares with the
*stage's* start, and this phase frees `_exit` — but the source assertions come first. It
is `apart 15 16`'s shape in **one** direction only: phase 17's own check passes on a 16-17
stage, phase 16 having freed nothing for it to be blamed for. And **no `apart 15 17`** is
written, although phase 15's check does require `_exit` to be still undefined: a stage
holding 15 and 17 holds 16, and `apart 15 16` forbids that already.

### What zero-vim is after seventeen phases

```
zero-vim.c        80,423 lines          from whim-vim.c's 86,614  (-6,191, 7.1%)
functions         1,755
type definitions  907
DWARF enumerators 1,181
cmdnames[] rows   98    (create_cmdidxs floor 80; 18 rows of margin)
nv_cmds[] rows    194   (nvidxcheck: a permutation)
options[] rows    108, 96 distinct globals  (orphanopts floor 80; 16 of margin)
#include          12, every one a system header; no #define, no conditional
libc symbols      32 with zero's flags, 33 as tools/symbols.sh counts
binary            805,544 bytes, EXEC, no INTERP, no dynamic section, no relocation
declared delta    20 records + stderr-moved, from whim-vim
```

**The 32, attributed.** One row of the table moved and it is the last row of the host
boundary that is not a device:

| why | symbols |
| --- | --- |
| **the terminal** | `read` `write` `close` `dup` `ioctl` `select` `tcgetattr` `tcsetattr` `nanosleep` `isatty` (10) |
| **messages before and after the screen** | `printf` `fflush` `stderr` (3) |
| **memory** | `malloc` `free` `realloc` (3) |
| **time** | `time` `gettimeofday` (2) |
| **signals and exit** | `sigaction` `sigaddset` `sigemptyset` `sigismember` `sigprocmask` `kill` `raise` `getpid` `exit` (9) |
| **gcc's own**, named nowhere in the source | `__errno_location` `fputc` `fputs` `fwrite` `putchar` (5) |

**`exit` is now a single call site**, `mch_exit`'s `exit(r);`, and that is what this phase
was for as much as the symbol: the next phase in this package has one line to replace in
one function rather than three in two.

## Phase 18 — `main()` is demoted to `vim_main()`

`pipes/zero18-edit.sh` and `pipes/zero18-check.sh`, `stage 18`, `package host`. Five
lines, no libc symbol, and `ZERO-PLAN.md` §4c's first step. What was

```c
    int
main
(int argc, char **argv)
{
    ...
    return vim_main2();
}
```

becomes `static int vim_main(int argc, char **argv)` with the **same body, byte for
byte**, and a six-line launcher is appended below it:

```c
    int
main(int argc, char **argv)
{
    return vim_main(argc, argv);
}
```

The editor runs one call frame deeper and does exactly what it did. Nothing else moves;
this is deliberately the only thing the phase does.

### Both stay in `zero-vim.c`, and that is the point rather than a compromise

Two tools hard-code today's invariant: `tools/phasecheck.sh`'s `grep -v '^main$'` and
`tools/funcreach.py`'s `{'main'}` root. Splitting the launcher into a second translation
unit is what breaks both, and the cost was measured while `exit` was being reviewed —
**one appended line to `tools/phasecheck.sh` moves 118 implementation keys**: 12 whim
stages, 82 whim edits, 12 zero units, 12 zero edits, and no slim key. So every demotion
that *can* be done inside one file is done inside one file, and the split happens once,
late, when there is nothing left to do before it.

**`vim_main` is `static` for the same reason.** Nothing outside this file calls it, and
a non-static one would be the first external symbol any zero phase has ever added.
`nm --extern-only --defined-only` on the object still prints exactly `main`.

### The name was checked for a collision rather than assumed

`vim_main2()` already exists — it is upstream's, the second half of the old `main()`
split at the point where the screen is up — and `vim_main` had **zero** mentions as a
whole word. C has no prefix collision, but a reader greps, so the edit and the check pin
all three words separately: `main` 1 (the launcher's head, and the only bare `main` in
80,000 lines), `vim_main` 2 (its definition and the one call — a third would be a
prototype, and a function defined above its only call needs none), `vim_main2` 2
(untouched). `\b` does not match inside `main_loop`, `main_errors` or `vim_main2`, and a
substring grep does.

### A fossil goes with it, and it turns out not to be cosmetic

`main()`'s head was spelled over **three** lines because upstream had an `#ifdef`
between the name and the argument list, giving MS-Windows a different signature; slim's
phase 5 took the conditional and left the line break. Every other function in this file
spells its head over two, so `vim_main` gets the ordinary shape and the new `main` gets
it too.

**Measured: `tools/funcreach.py`'s definition finder never matched the three-line head.**
`main` had never been one of the definitions it counts — its `{'main'}` root was a name
added by hand to a set that did not contain it. So 1,755 definitions become **1,757**
for one new function, and the second is `main` itself, seen for the first time. All
1,757 are reachable.

### The evidence is every way the editor can end

The binary is **not** byte-identical and is not asserted to be: at `-O0` an extra call
frame is real code. Measured, both built `SOURCE_DATE_EPOCH=0` with the boundary's own
flags: **805,544 bytes either side — the same size, different bytes**, the frame
absorbed by alignment padding. So phase 16's tier-1 argument is not available here and
something else has to stand in its place.

What stands in its place is the six routes `ZERO-PLAN.md` maps that a probe can reach
from outside, run on **both** binaries:

| | how it starts | path | status |
| --- | --- | --- | --- |
| `quit` | `+q!` | `ex_quit` → `getout(0)` | **0** |
| `cquit3` | `+cq 3` | `ex_cquit` → `getout(3)` | **3** |
| `eof` | stdin at `/dev/null` | `read_error_exit` → `preserve_exit` → `getout(1)` | **1** |
| `badopt` | `-Z` | `mainerr` → `mch_exit(1)` | **1** |
| `sigterm` | SIGTERM | `deathtrap` → `preserve_exit` → `getout(1)` | **1** |
| `sighup` | SIGHUP | the same | **1** |

`return vim_main(argc, argv);` puts a value in the program's path that was not there
before, and that table is what says it arrives. **The binary the phase was handed is
required to give the same six**, so an agreement cannot be two wrong answers agreeing.

**And the table is proven able to fail.** The output is built a second time with
`mch_exit`'s `exit(r)` changed to `exit(r + 1)` — one character — and all six move:
1, 4, 2, 2, 2, 2. Six statuses that agree prove nothing unless a wrong one would have
been caught, which is phase 17's `SA_NODEFER` control in this phase's shape.

**`/dev/null` and not a pipe, and that is a measurement.** With stdin a pipe the harness
closes, the EOF row came back as a twenty-second timeout on four binaries out of five
and as a clean 1 on the fifth — a race in the *harness*, not in the editor. A file that
is already at end of file has no race in it, and the four non-signal rows are then
deterministic over repeated runs.

### The declared delta is nothing at all

`pipes/zero.delta` gets a comment and no line, and this is a **sixth** kind of empty
declaration. The five before it each removed *something*: **9** code that could not run,
**12** code that can run and that the instrument cannot see, **13** a possibility, **16**
no code at all with the binary the same bytes, **14** and **15** code replaced by code
that computes the same answers. **This one adds a call frame and removes nothing**, so
there is nothing to declare and nothing for a recording to show. `tools/zerodelta.sh
--phase 18` finds the corpus unmoved, as it must: 102 of 102 screen cases, 111 of 111
Ex-command rows, 30 of 30 command lines.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 80,423 | **80,428** (+5) |
| functions `funcreach` counts | 1,755 | **1,757** — one new, and `main` seen at last |
| type definitions | 907 | 907 |
| `nm -u`, as `phasecheck.sh` counts it | 33 | **33, identical as a `cmp`** |
| `nm -u` with zero's own flags | 32 | **32** |
| external symbols | `main` | `main` |
| `#include` | 12 | 12 |
| binary | 805,544 | **805,544 — the same size, different bytes** |
| sweep | | **1 round, a complete no-op** |
| phase | | **22 s** |

### Its placement

`stage 18`, `package host` beside phase 17, with `uses host:18 seed:0 mechanical` and
`uses host:18 harness:3 mechanical` — the two every phase declaring "nothing moved"
owes.

**`need 18 swept` is not required.** Both anchors are exact text at a counted
occurrence — the three-line head, and the file's last two lines — and neither is text a
sweep has ever touched.

**`apart 17 18`, measured.** Phase 17's check requires the file to have lost **exactly
nine** lines and this phase adds five, so on a shared stage the one swept text 17's
check is handed is four lines shorter than its input rather than nine:
`tools/phaserun.sh zero 17-18` on r16 reports *"the file lost 4 lines, expected 9"* and
exits 1. It is `apart 16 17`'s shape in **one** direction only — phase 18's own check
compares against the text *its* edit was handed, which is 17's output either way, so it
passes on a 17-18 stage.

### What zero-vim is after eighteen phases

```
zero-vim.c        80,428 lines          from whim-vim.c's 86,614  (-6,186, 7.1%)
functions         1,757  (1,755 + vim_main, + main itself, now a shape funcreach sees)
type definitions  907
DWARF enumerators 1,181
cmdnames[] rows   98    (create_cmdidxs floor 80; 18 rows of margin)
nv_cmds[] rows    194   (nvidxcheck: a permutation)
options[] rows    108, 96 distinct globals  (orphanopts floor 80; 16 of margin)
#include          12, every one a system header; no #define, no conditional
libc symbols      32 with zero's flags, 33 as tools/symbols.sh counts
binary            805,544 bytes, EXEC, no INTERP, no dynamic section, no relocation
declared delta    20 records + stderr-moved, from whim-vim
```

**Nothing in the table moved but the line count and the function count**, which is what
a phase that renames one function and adds another is entitled to move. `exit` is still
`mch_exit`'s single call site; the next phase in this package is the one that takes it.

## Phase 19 — the core can no longer stop the process

`pipes/zero19-edit.sh` and `pipes/zero19-check.sh`, `stage 19`, `package host`.
Eighteen lines, one libc symbol, and `ZERO-PLAN.md` §4c's second step. `mch_exit()`'s
last statement stops being `exit(r);`:

```c
static void (*vim_host_exit)(int);

    static void
mch_exit(int r)
{
    ...
    ml_close_all(TRUE);

    vim_host_exit(r);
}
```

`vim_main()` takes the callback as a third parameter and installs it as its first
statement, and phase 18's six-line launcher becomes twenty:

```c
static void *host_jump[5];
static int host_code;

    static void
host_exit(int r)
{
    host_code = r;
    __builtin_longjmp(host_jump, 1);
}

    int
main(int argc, char **argv)
{
    if (__builtin_setjmp(host_jump) != 0)
    {
        return host_code;
    }
    return vim_main(argc, argv, host_exit);
}
```

The editor no longer ends the process. It hands the process back, with a number.
**`nm -u` 32 → 31, the gone set exactly `{exit}`, and nothing arrives** — an indirect
call through a pointer names no symbol, and *returning* from `main()` ends the process
without naming one either.

### Why a function pointer, and why the other two routes are not available

* **Thread a status up through every caller.** Not expensive — *not writable*.
  `cmdnames[].cmd_func` is `void (*)(exarg_T *)` for all 98 rows and
  `nv_cmds[].cmd_func` is `void (*)(cmdarg_T *)` for all 194, each dispatched through
  one indirect call, so every handler would have to change signature together; and
  `deathtrap` is `void (*)(int)` by the kernel's contract and cannot participate at
  all. Say it plainly, because "thread the value up" is the first thing a reader
  proposes.
* **A `setjmp` in the core.** It puts the mechanism in the file that is meant to stop
  naming mechanisms, and it costs symbols.
* **The core calls out and does not come back.** `vim_host_exit(r);` is four words of C
  that say exactly that; the host decides *how*. It is the one route whose C text
  already says what a JVM host would have to do — an interface call whose
  implementation throws.

**The indirection is temporary and `ZERO-PLAN.md` §4c says so.** It exists because
everything is still one translation unit and *nothing is global but `main()`* is still
the invariant: a pointer the launcher installs through a parameter adds no external
symbol, where a `musl_exit(int)` the host defines would. Once the file is split there
*is* a declared boundary, `vim_host_exit` becomes a plain `musl_exit(int)` prototype at
the top of the editor file, and the parameter and the pointer both go.

### The mechanism in the launcher is measured, and the review that proposed this phase got it wrong

Returning from `main()` is what ends the process without naming `exit`, and getting
back to `main()` from inside `deathtrap` needs a non-local jump. All four spellings,
measured on this tree:

| the launcher jumps with | `nm -u` | what it costs |
| --- | --- | --- |
| **`__builtin_setjmp`/`__builtin_longjmp`** | **32 → 31** | nothing arrives; no header |
| `sigsetjmp`/`siglongjmp` | 32 → **33** | `+sigsetjmp` `+siglongjmp`, `+<setjmp.h>` |
| `setjmp`/`longjmp` | 32 → **33** | `+setjmp` `+longjmp`, `+<setjmp.h>` |
| the launcher calls `exit(r)` | 32 → 32 | nothing moves; the phase achieves nothing |

**The two library spellings are net worse than not doing the phase**: `exit` leaves and
two symbols arrive in its place, plus a thirteenth `#include` in a file whose last
phase but two removed six. The review this phase comes from recommended `sigsetjmp`,
having counted the *core* at 42 with the launcher's cost attributed to a host file that
does not exist yet; in one translation unit there is no separate. So
`pipes/zero19-check.sh` **builds the `sigsetjmp` variant on every run** and requires
`nm -u` to show 33 against the output's 32, with `sigsetjmp` and `siglongjmp` present
and `exit` gone from both — the road not taken as a number rather than a memory. It is
compiled to an object; it is an answer, not a program.

### The one thing `sigsetjmp` would have bought, and the measurement that says it is not needed

`__builtin_longjmp` does not restore the process signal mask and `siglongjmp` does, so
after a jump out of `deathtrap` on SIGTERM the landing site still has SIGTERM blocked.
**That is exactly the state the process already died in.** Measured on the source this
phase was handed, with a `sigprocmask`/`sigismember` probe immediately before
`exit(r);`, and on the output with the identical probe immediately before the launcher
returns:

| | before `exit(r);` (input) | before `return host_code;` (output) |
| --- | --- | --- |
| SIGTERM | `TERM-MASKED HUP-CLEAR` | `TERM-MASKED HUP-CLEAR` |
| SIGHUP | `TERM-CLEAR HUP-CLEAR` | `TERM-CLEAR HUP-CLEAR` |

`exit()` was always being called from inside the handler with the handled signal
blocked. SIGHUP is clear only because `prepare_to_exit()` calls
`mch_signal(SIGHUP, SIG_IGN)`, which unblocks it on the way past. So the builtin
**preserves** the mask the process ends with and `siglongjmp` would have **changed**
it. The check asserts the pair every run, and requires the input's half to be non-empty
so the equality is not two silences agreeing.

A host that keeps running rather than returning is where the mask would matter, and
there is none: `main()` lands and returns four lines later. When the file is split that
host writes `musl_exit(int)` for itself and owns the question along with `sigprocmask`,
which is a symbol the *host* is allowed to name.

**One thing is deliberate and is said here rather than discovered later.** A non-local
jump out of a signal handler is undefined by the letter of C11 when the signal
interrupted a function that is not async-signal-safe, which here it always does —
`deathtrap` already calls `out_str`, `sprintf`, `ml_close_all` and `free`, and upstream
has always done that and got away with it because the process was about to die. The
design that removes it is the signal handlers becoming the host's — `sig_winch`'s
`do_resize = TRUE; return;` applied to the deadly two — which is a later phase and the
first of these with a real declared delta.

### The evidence

The six routes again, on both binaries, every one of which now leaves `mch_exit`
through the pointer, lands in `main()` and comes back as a **return value**:

```
quit=0   cquit3=3   eof=1   badopt=1   sigterm=1   sighup=1
```

**Proven able to fail**: the output built again with `host_exit`'s `host_code = r;`
made `host_code = r + 1;` — one character — moves all six, to 1, 4, 2, 2, 2, 2. That is
the value travelling from `mch_exit` through a function pointer, into a jump buffer and
out of `main()`, and the control is what says the table measures it.

**One finding the harness cost, and the program now records it.** The EOF row's status
is a statement about the harness's fd 2 as much as about the editor.
`fill_input_buf()` answers a read of nothing on a non-tty fd 0 with `close(0);
vim_ignored = dup(2);` and tries again — so the EOF route's *second* read is a read of
whatever stderr is. Measured on the binary this phase was handed: with stderr at
`/dev/null` the second read is another end of file, `read_error_exit` runs and the
status is 1; with stderr a **pipe the harness holds open**, the editor waits there for
keys that never come and the row times out on every binary. Both probes use
`/dev/null`. `tools/zstream.py`'s docstring has the same finding from the other end,
about `vim -`.

### The counting trap, one phase further on

`exit` as a word is **5** in the input and **4** in the output, and the number of
statements beginning with `exit(` is **1 → 0**. The four that stay are two string
literals (`"Type  :qa!  and press <Enter> to abandon all changes and exit Vim"` and its
shorter twin) and a `goto exit;` with its `exit:` label inside `vim_regsub_both()`. So
`assert exit at 0 mentions` fails on a correct phase, and `assert 'exit(' at 0` fails
on `mch_exit(`, `preserve_exit(`, `prepare_to_exit(`, `read_error_exit(`, `getout(` and
now `vim_host_exit(` and `host_exit(` as well. The assertion that works is `nm -u`, and
it is asserted in both directions: `exit` `_exit` `abort` `_Exit` `quick_exit` `atexit`
and every spelling of a jump must be **absent**.

### The declared delta is nothing at all

`pipes/zero.delta` gets a comment and no line, and it is phase 18's kind. Everything
`mch_exit` does before the changed line is untouched — the terminal restored, the
screen scrolled, the memfile closed — so what the editor *draws* on its way out cannot
move, and the recording is of what the editor draws. **18 and 19 are the first two
phases in this pipeline whose empty declaration means neither "nothing ran" nor "the
instrument cannot see it": the code runs, the instrument sees it, and it does the same
thing.** `tools/zerodelta.sh --phase 19` finds the corpus unmoved: 102 of 102 screen
cases, 111 of 111 Ex-command rows, 30 of 30 command lines.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 80,428 | **80,446** (+18) |
| functions | 1,757 | **1,758** (`host_exit`) |
| type definitions | 907 | 907 |
| `nm -u`, as `phasecheck.sh` counts it | 33 | **32**, gone set exactly `{exit}` |
| `nm -u` with zero's own flags | 32 | **31** |
| external symbols | `main` | `main` |
| `#include` | 12 | 12 |
| binary | 805,544 | **805,544 — the same size, different bytes** |
| sweep | | **1 round, a complete no-op** |
| phase | | **24 s** |

### Its placement

`stage 19`, `package host` beside 17 and 18, with `uses host:19 seed:0 mechanical` and
`uses host:19 harness:3 mechanical`.

**`need 19 swept` is not required**: every anchor is exact text at a counted occurrence
— `mch_exit()`'s definition and its tail, `vim_main()`'s head, and the file's last six
lines — and none of it is text a sweep has ever touched.

**`apart 18 19`, measured, and the measurement found a better reason than the four that
were predicted.** Phase 18's check fails at its **first act**: it builds its own control
by rewriting `mch_exit`'s `exit(r);` to `exit(r + 1);` with `sed`, and refuses when
that changes nothing — and this phase has replaced that line. `tools/phaserun.sh zero
18-19` on r17 reports *"the control edit changed nothing — mch_exit's `exit(r);` is not
where this phase expects it"* and exits 1. Three more of its assertions would have
failed after it — the `cmp` on an undefined set that a stage snapshots once at its
start, the five-line gain where a 18-19 stage gains 23, and the six-line launcher it
requires the file to end with. **One direction only**: phase 19's own check compares
against the text *its* edit was handed and its gone set from r17 is still exactly
`exit`, 18 having freed nothing for it to be blamed for, so it passes on a 18-19 stage.

### What zero-vim is after nineteen phases

```
zero-vim.c        80,446 lines          from whim-vim.c's 86,614  (-6,168, 7.1%)
functions         1,758
type definitions  907
DWARF enumerators 1,181
cmdnames[] rows   98    (create_cmdidxs floor 80; 18 rows of margin)
nv_cmds[] rows    194   (nvidxcheck: a permutation)
options[] rows    108, 96 distinct globals  (orphanopts floor 80; 16 of margin)
#include          12, every one a system header; no #define, no conditional
libc symbols      31 with zero's flags, 32 as tools/symbols.sh counts
binary            805,544 bytes, EXEC, no INTERP, no dynamic section, no relocation
declared delta    20 records + stderr-moved, from whim-vim
```

**The 31, attributed.** One row of the table lost its last member:

| why | symbols |
| --- | --- |
| **the terminal** | `read` `write` `close` `dup` `ioctl` `select` `tcgetattr` `tcsetattr` `nanosleep` `isatty` (10) |
| **messages before and after the screen** | `printf` `fflush` `stderr` (3) |
| **memory** | `malloc` `free` `realloc` (3) |
| **time** | `time` `gettimeofday` (2) |
| **signals** | `sigaction` `sigaddset` `sigemptyset` `sigismember` `sigprocmask` `kill` `raise` `getpid` (8) |
| **gcc's own**, named nowhere in the source | `__errno_location` `fputc` `fputs` `fwrite` `putchar` (5) |

**The row used to be "signals and exit" and it is now "signals".** What is left of the
host boundary is a terminal, a clock, three allocations and eight signal calls — and
§4c's remaining step is the one that takes the first and the last of those out
together.

## Phase 20 — the signals and the terminal are the host's

`pipes/zero20-edit.sh` and `pipes/zero20-check.sh`, `stage 20`, `package host`.
`ZERO-PLAN.md` §4c's third step, and it is **one** phase where the plan and two
surveys had two. The signals half on its own leaves the terminal in **raw mode** after
`kill -TERM`, because the only way to delete the core's signal handlers is to delete
`deathtrap`, and `deathtrap` is what restores it. Keeping `deathtrap` and having the
host merely *install* it costs nothing and keeps all of it:

```c
    static void
musl_host_init(void)
{
    host_catch(SIGHUP, deathtrap);
    host_catch(SIGTERM, deathtrap);
    host_catch(SIGWINCH, host_on_winch);
    host_catch(SIGCONT, host_on_winch);
    host_catch(SIGTSTP, host_on_tstp);
    host_catch(SIGINT, host_on_int);
    host_catch(SIGPIPE, SIG_IGN);
    host_catch(SIGALRM, SIG_IGN);
}
```

`deathtrap → preserve_exit → prepare_to_exit → term_leave()` still runs, and phase
19's `vim_host_exit` → `__builtin_longjmp` turns `mch_exit(1)` into `return 1`, so the
handler needs nothing of its own. Measured, identical on both binaries: `kill -TERM`
exits 1, restores the terminal to `ICANON=1 ECHO=1 ISIG=1 ONLCR=1 ICRNL=1`, and draws
`Vim: Caught deadly signal TERM` and `Vim: Finished.` in **2,241 bytes** — SIGHUP the
same in **2,240**. There is no phase 21.

### Within one translation unit, moving code frees nothing — and the phase says so

A symbol leaves `nm -u` when its last **caller** leaves the file, and that is the
split. `sigaction`, `sigemptyset`, `kill`, `ioctl`, `tcgetattr`, `tcsetattr`,
`nanosleep`, `select` and `__errno_location` all survive this phase; every one of them
is now called from a 229-line host block at the bottom of the same file and from
nowhere else. **What leaves is what the phase DELETES**, stated as one `comm` because
the two halves are one phase:

```
nm -u  31 → 24, gone exactly
    close  dup  isatty  raise  sigaddset  sigismember  sigprocmask
arrived: nothing
```

`raise` was `sig_tstp`'s re-raise. `sigaddset sigismember sigprocmask` were
`mch_signal()`'s fifty lines emulating `sigset()`, where the host's `host_catch()` is
four lines of `sigaction`. `isatty` is all three surviving calls. `close` and `dup` are
`mch_tcgetattr`'s dead `close(tty_fd)` and `fill_input_buf`'s `close(0); dup(2)` arm.

**So the phase's real claim is structural, and it ships the assertion for it.**
`tools/zhostonly.py` is new, zero-only, and named by `pipes/zero20-check.sh` alone: 43
host words — `sigaction`, `kill`, `ioctl`, `tcsetattr`, `select`, `nanosleep`, every
`SIG*`, `struct termios`, `fd_set`, `ICANON`, `VMIN` — and **every mention of every one
of them must be inside the host block**. It reports 60 mentions of 43 words, all of
them there. Seven exceptions are named with their reason and their exact count, and
they are the whole of what the core still says: `signal_info[]` and `deathtrap` name
`SIGHUP` and `SIGTERM` because that is the **message** the editor prints,
`vim_handle_signal` re-raises a deferred deadly signal with `kill`, and `elapsed_T` is
`struct timeval` because it is the clock. It ignores string literals — the file
contains `hash_remove(&buf_hashtab, hi, "close buffer")`, and a tool that read that as
a `close()` would report the buffer layer as filesystem code — and `#` lines, because
`#include <errno.h>` and `#include <sys/ioctl.h>` name two of the words. It refuses to
pass vacuously: the host region must be found, must define all fourteen of its
functions, and must itself mention `sigaction ioctl tcsetattr nanosleep select kill`.
Without it the strongest available form of *the core names none of this* is
`sigaction` at 2 mentions, which says nothing about **where**.

### The in-band protocol was already in the file, and it could never run

This is the finding that reframed the phase. `handle_csi()` has always parsed DEC
private mode 2048's notification — `CSI 48 ; rows ; cols ; hpx ; wpx t`, specified by
Tim Culverhouse in 2024 — and carried the whole negotiation around it:
`win_resize_setting`, `win_resize_enabled`, `term_set_win_resize()`, the `'termresize'`
option with its `inband`/`sigwinch` values, and the `CSI ? 2048 h` / `l` it writes.

**And none of it could ever run.** `win_resize_setting` is written in exactly one place
in `zero-vim.c` — inside the parser for the DECRQM *response*, `CSI ? 2048 ; Ps $ y` —
and `\033[?2048$p`, the DECRQM **query** that is the only thing a terminal answers with
that response, appears **nowhere in `slim-vim.c`, `whim-vim.c` or `zero-vim.c`**. The
editor never asks, so it is never told, so `win_resize_setting` is 0 for ever,
so `term_set_win_resize(true)` always takes its first branch and sets
`win_resize_enabled = false`, so the notification arm is unreachable. Proven by running
it: typing `\x1b[48;30;100t` at the committed binary inserts the escape **as buffer
text**. So the phase deletes the negotiation, the option that drove it and the two
state variables, and switches the parser on — and the **host** writes the
notification, from its own SIGWINCH handler and its own `ioctl`.

That is the cheapest half of the phase, and it is half a deletion of code that could
not run rather than half a rewrite.

### Why the host keeps its `ioctl`, which is the decision the whole design turns on

Mode 2048 is a good protocol that almost nothing implements. Source-verified:

| implements 2048 | does **not** |
| --- | --- |
| ghostty, kitty, foot, iTerm2, contour, Bobcat | **xterm, tmux, GNU screen, WezTerm, Alacritty, VTE/gnome-terminal, Konsole, Windows Terminal, rxvt-unicode, st, Rio, zutty, xterm.js, Zellij, mintty, Terminator, mlterm, Warp, Hyper** |

**tmux and GNU screen terminate it**: their private-DECSET whitelists stop short of
2048, their DECRQM arms answer `CSI ? 2048 ; 0 $ y` — the correct *"not recognised"* —
and neither forwards `CSI ? 2048 h` outward. A core that relied on the terminal would
be an editor that never learns it was resized under tmux. The alternative query,
XTWINOPS `CSI 18 t`, is a **round trip** whose answer races real keystrokes in the same
stream, is unsupported by `st`, and can be switched off by xterm's `allowWindowOps` —
and it answers "what size am I", never "did it change".

So the host keeps `SIGWINCH` and `TIOCGWINSZ` and **injects** the notification the
spec defines. Deleting the host's `ioctl` instead would free `ioctl` and an eleventh
`#include` and cost exactly that list of terminals: a number bought with the terminal.

### The four messages become bytes, and the one that cannot

Four of the five handlers existed to *tell the editor something*, and a host cannot
deliver a signal to a core it is linked into — there is no such thing. So the four
become bytes on the channel that already exists:

| the host catches | the core reads |
| --- | --- |
| `SIGWINCH`, `SIGCONT` | `CSI 48 ; rows ; cols ; 0 ; 0 t` — the mode-2048 notification |
| `SIGTSTP` | `\033[?1z` |
| `SIGINT` | the byte `0x03` |
| `SIGHUP`, `SIGTERM` | nothing — it is not a message, it is the process ending |

**`\033[?1z` is ours and is in no spec**, and that is said here rather than discovered.
`first == '?' && argc == 1 && arg[0] == 1 && trail == 'z'` reaches no existing arm —
the `?`-prefixed arms end in `c`, `y` and `u` — and `z` is a letter, so the trail scan
stops on it. Doing real work from inside the termcode parser has precedent in the file:
the resize arm calls `set_shellsize()`, which redraws the whole screen.

**The interrupt travels as the byte it already is, and it is not optional.**
`catch_sigint` set `got_int` directly. The host instead hands the core a `0x03`, which
`fill_input_buf`'s own CTRL-C scan turns into `got_int` — the only way `got_int` is
ever set in raw mode anyway, because raw mode clears `ISIG`. **With no handler at all,
`SIG_DFL` KILLS the editor**: measured, `kill -INT` mid-session leaves the binary this
phase was handed editing and kills a no-handler build with SIG2. The `10gs` probe is
what found it, because the sleep mode deliberately leaves `ISIG` on (below).

**Keyboard CTRL-Z is the one thing that cannot go in band**, and `musl_suspend()` is
why there is one call out and not zero. In raw mode `ISIG` is clear, so CTRL-Z arrives
as the byte `0x1a`, reaches `nv_cmds[]`'s real `{Ctrl_Z, nv_suspend, 0, 0}` row, and
**the core decides** to suspend. A one-way host→core channel has no way to carry that
decision back. The external `kill -TSTP` is the other direction and fits the in-band
path exactly, which is the asymmetry stated once:

```c
    static void
musl_suspend(void)
{
    host_catch(SIGTSTP, SIG_DFL);
    kill(0, SIGTSTP);
    host_catch(SIGTSTP, host_on_tstp);
}
```

`mch_suspend()` goes from 27 lines to eight, and `in_mch_suspend`, `sigcont_received`
and the four-iteration `mch_delay` back-off loop go with it. The first existed only so
the core's own `sig_tstp` could tell *my* stop from *someone else's*, and the second
only to drive the loop: **the call returning is the handshake.**

### The terminal is two operations, not a mode setter

`settmode(tmode_T)` had nine call sites and a three-valued mode, and every site is
attached to an **operation** — the editor takes the terminal, gives it back, suspends,
resumes, sleeps, or re-asserts that it still holds it. Exposing `musl_set_raw(int)`
would move the syscall without moving the responsibility. So `settmode()` splits at the
one line that was ever the host's:

```c
    if (termcap_active && tmode != TMODE_SLEEP && cur_tmode != TMODE_SLEEP)
        ... out_str(t_CBD); out_str_t_TE();     /* leaving  -- screen work, stays */
        ... out_str_t_BE(); out_str_t_TI();     /* entering -- screen work, stays */
    out_flush();
    mch_settmode(tmode);                        /* <- the only host part */
```

into `term_enter()` and `term_leave()`, which keep the escape sequences because those
are screen work. `cur_tmode` becomes a boolean `term_entered`, `mch_cur_tmode` goes —
the two were equal at every one of the eleven call sites, over 521 recorded
observations — and `tmode_T` with `TMODE_COOK`, `TMODE_RAW` and `TMODE_SLEEP` goes to
the sweep, along with `MCH_DELAY_SETTMODE`, which had no caller.

**The two sites that look like exceptions are re-assertions, and a re-assertion is an
idempotent operation.** `getcmdline_int`'s `settmode(TMODE_RAW)` found the terminal
already raw on all 521 observations, and `ask_yesno`'s runs only `if (exiting)`, after
`prepare_to_exit` cooked it. Both are `term_enter()`.

### `TMODE_SLEEP` leaves `ISIG` on deliberately, and the `gs` probe is what proves it

The parameter is `interruptible`, not `discard_input`, and the code says so. Measured
from `mch_settmode`: the sleep mode is the **saved** termios with `ICANON` and `ECHO`
cleared and `VMIN=1 VTIME=0`, applied **`TCSANOW`, not `TCSAFLUSH`** — nothing is
flushed and nothing is discarded. What is different from raw mode is that **`ISIG` is
left on**, so the terminal's INTR character raises `SIGINT` and cuts the `nanosleep`
short instead of sitting in the input queue.

That is load-bearing, and a phase that "simplified" `musl_delay()` into a plain
`nanosleep` would break CTRL-C during `gs` with no recorded harness able to see it —
`gs` is in no case. So the check builds **this phase's own output** with `musl_delay()`'s
two `host_tty_set()` calls deleted and nothing else, and runs `10gs` followed by CTRL-C
1.5 s later on all three:

| binary | comes back |
| --- | --- |
| the one this phase was handed | **1.81 s** |
| this phase's output | **1.81 s** |
| this phase's output without the sleep mode | **never** — killed at 99 s |

Two numbers agreeing prove nothing if a wrong one is not caught.

### Nothing asks whether this is a terminal, which is decision 7 finally kept

`ZERO-PLAN.md` §1's decision 7 is *"do not ask whether stdin or stdout is a terminal.
The check goes entirely."* Phases 2 and 4 left three `isatty()` calls alive and this
takes all three: `mch_check_win`'s, `mch_get_shellsize`'s (with the whole function),
and `fill_input_buf`'s (with the arm below). `stdout_isatty` folds to TRUE and
`nv_esc`'s `out_redir` folds to the terminal arm — **both arms together**, because
folding one leaves an `if (out_redir)` with no definition. **`musl_is_terminal()` is
deliberately NOT written**: the two questions had different subjects — fd 1 for the
size, fd 0 for the input — and neither survives its caller, so a host call to answer a
question nobody asks afterwards is boundary surface for nothing.

### The core cannot acquire a descriptor at all any more

`fill_input_buf`'s `close(0); vim_ignored = dup(2);` arm reopened the editor's stdin
from its stderr when stdin hit end of file and was not a terminal. **That is the core
second-guessing the host about where input comes from**, and once the host owns the
terminal it is the host's business. `ZERO-PLAN.md` §4b becomes absolute: the core is
handed fds 0, 1 and 2 and that is the whole of it — it cannot open, close or duplicate
anything.

The behaviour that goes is real and probe-only. With stdin at EOF and a **terminal on
fd 2** the old binary reopens fd 0 and carries on editing (2,016 bytes of drawn
screen); this one prints `Vim: Finished.` and exits 1 (168 bytes). It fired **0 times
across all 253 recorded rows**, which is why the declaration is empty and the probe is
the evidence.

### `ui_get_shellsize()` stays a query, and this is a design the survey got wrong

The survey proposed making it *"do I know my size?"* — a `shell_size_known` flag set by
the host and by every notification. **That breaks resizing, and the measurement is
exact.** At a `Press ENTER` prompt `set_shellsize()` does

```c
    if (State == (0x2000 | MODE_NORMAL) || State == MODE_SETWSIZE)
    {
        State = MODE_SETWSIZE;
        return;
    }
```

and **discards the width and height it was given**. `wait_return()` then calls
`shell_resized()`, which is `set_shellsize(0, 0, FALSE)`, which reaches
`mustset || (ui_get_shellsize() == FAIL && height != 0)` — and learns the new size only
from `ui_get_shellsize()`'s **side effect**. With the flag, a pty resized while the
editor sits at that prompt stays 24x80 for ever; measured twice, and the in-band
notification is delivered and parsed and still lost.

So `mch_get_shellsize()`'s body moves to the host as `musl_get_winsize(int *, int *)` —
`ZERO-PLAN.md` §4c's own name for it — and `ui_get_shellsize()` keeps its shape. That
also disposes of the trap the survey spent an hour on: on a pipe the host's `ioctl`
fails, `ui_get_shellsize()` returns FAIL exactly as `mch_get_shellsize()` did,
`set_termname()` still emits `t_CWS`, and the recording does not move by one byte. The
flag version cost 10 bytes of stream in every one of the 102 cases.

### `vim_handle_signal` stays, and it is the one core mention that is not a message

It is the deferral machine: `ui_inchar` calls it with `-2` before a long wait and `-1`
after, and `deathtrap` consults it to *defer* a deadly signal arriving while the editor
is not reading, re-raising it later with `kill(getpid(), got_signal)`. Deleting it
would make a deadly signal act in the middle of a screen update — a behaviour change no
recording can see. So it stays, and `tools/zhostonly.py` names it as an exception with
that reason rather than loosening its pattern.

### The wait has two answers, not three

`musl_wait_for_input(long ms)` returns 1 (something to read) or 0 (the time elapsed);
`ms < 0` waits for ever. There is no "interrupted", and the reason is measured:
**nothing reads the one that exists today.** `RealWaitForChar` writes `*interrupted` in
two places, `WaitForChar` passes it through, and `inchar_loop` declares
`int interrupted = FALSE;`, passes `&interrupted` and **never reads it** — eleven
mentions, not one of them a read. The whole `efds` set exists only to produce it, and
it goes.

**The `EINTR` retry does not disappear; it moves inside the host**, and so does the
pending-flag check, which must happen on **both** sides of the `select`: only after an
`EINTR`, and a signal arriving while the editor is not inside `select` is lost until
the next keystroke; only before it, and one arriving during it is lost until it
returns. That is why the signals half's proposed `musl_input_pending()` and the
terminal half's `musl_wait_for_input()` are **one function** and the phase declares one:

```c
    static int
musl_wait_for_input(long ms)
{
    ...
    for (;;)
    {
        if (host_winch_pending || host_tstp_pending || host_int_pending) { return 1; }
        FD_ZERO(&rfds);
        FD_SET(0, &rfds);
        ret = select(1, &rfds, NULL, NULL, tvp);
        if (ret == -1 && errno == EINTR) { continue; }
        return ret > 0 && FD_ISSET(0, &rfds);
    }
}
```

`tvp` is computed once, before the loop, because Linux decrements it in place and the
`goto select_eintr` it replaces did the same.

### Two findings that are patterns, not incidents

* **A struct field whose only reader the phase deletes must go in the EDIT, not the
  sweep.** `signal_info[]`'s `deadly` was read only by `catch_signals()`.
  `tools/deadfields.py` duly removed the **member** — and left the three initialisers
  behind: `warning: excess elements in struct initializer`, three times, which
  `tools/phasecheck.sh` then fails on. A field the edit knows is dead is the edit's to
  take, **with its data**.
* **`-Wunused-but-set-variable` does not reach an address-taken or file-scope object**,
  and this phase met it twice in one edit: `did_read_something`, left set and never read
  by the reopen arm going, and `*interrupted`, write-only through three functions
  because `inchar_loop` takes its address. `CLAUDE.md` records that `deadsweep.py` does
  not act on that warning; both had to be removed by hand.

### The declared delta is nothing at all, and it is phase 2's kind

`pipes/zero.delta` gets a comment block and no line. Two full recordings either side
are **byte-identical** — 102 screen cases, `ref-excmds.txt`, `ref-argv.txt`,
`ref-pty.txt`, `ref-term.txt` — and `tools/zerodelta.sh --phase 20` finds the corpus
unmoved: 102 of 102, 111 of 111, 30 of 30.

But it is **phase 2's** kind and not phase 18's: the code runs and the instrument
*cannot see it*. On a pipe `tcgetattr`/`tcsetattr` fail and change nothing; no recorded
case sends a signal, resizes a window, types `gs`, or reaches EOF with a terminal on
fd 2. So the phase owes probes, and the check runs **fifteen** on both binaries.

**MUST DIFFER (7)**

| probe | the input | this |
| --- | --- | --- |
| `resize_inband` — `ESC[48;30;100t` then `:set columns?` | the escape lands as buffer text, 2,248 B | `columns=100`, 5,279 B |
| `trz_query` — `:set trz?` | `termresize=` | `E518: Unknown option: trz?` |
| `trz_set` — `:set trz=sigwinch` | accepted, no message | `E518` |
| `inband_stop` — `ESC[?1z` | not a command; the session ends at EOF, rc 1 | runs `:stop`, comes back, `:q!` quits, rc 0 |
| `eof_on_tty2` — stdin `/dev/null`, a pty on fd 2 | **still editing**, 2,016 B | `Vim: Finished.`, exit 1, 168 B |
| `ctrl_c_redir` — CTRL-C, stdout a pipe | `do_cmdline_cmd("qa")` → `E492` | `Type :qa and press <Enter> to exit Vim` |
| `tstp_external` — `kill -TSTP` | 4,379 B | 4,356 B — the in-band path |

**MUST NOT DIFFER (8)**

| probe | both binaries |
| --- | --- |
| `sigterm_restores` | exit 1, tty back to `ICANON=1 ECHO=1 ISIG=1 ONLCR=1 ICRNL=1`, both messages, **2,241 B** |
| `sighup_restores` | the same, **2,240 B** |
| `sigint_external` | survives and keeps editing, 2,327 B |
| `ctrl_z_key`, `stop_cmd` | 4,401 B and 4,379 B, editing afterwards |
| `raw_mode_live` | `ICANON=0 ECHO=0 ISIG=0 ONLCR=0 ICRNL=0` while editing |
| `pty_resize` | 24x80 asked, resized to 30x100, asked again: `lines=30 columns=100` |
| `stopcont` | a whole screen redrawn on CONT — 1,986 B and 2,008 B |
| `gs_interrupt` | 1.81 s, with its control at 99 s |

**A pty byte count is not an assertion, and the check says which are which.** The pty
probes drive a real terminal with real waits, so what they assert is structural — exit
status, terminal mode, what text was drawn — and the counts are reported. The two
places a count **is** the evidence are `tstp_external`, where it must differ, and
`stopcont`, where both must draw a whole screen. The pipe probes, which are
`tools/zstream.py` and deterministic, assert exactly.

**One correction to a number the survey recorded.** It reported the committed binary
drawing 2,008 bytes on `kill -STOP; kill -CONT` and a variant without the fix drawing
63. Re-measured: the committed binary draws **69 B** in one harness shape and
**1,986 B** in another, because `mch_signal()` installs with `SA_RESTART` and the
`select` simply restarts — `sigcont_handler`'s `redraw_later(UPD_CLEAR)` is deferred to
the next keystroke. Catching `SIGCONT` with the same handler as `SIGWINCH`, and
dropping the notification arm's `if (height != Rows || width != Columns)` guard so that
a notification is always a full redraw, is still right; the reason is *the screen is
correct at once instead of at the next keystroke*, not *a regression is avoided*.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 80,446 | **80,148 (−298)** |
| functions | 1,758 | **1,757** |
| type definitions | 907 | **904** (`tmode_T`, and the two the sweep found with it) |
| DWARF enumerators | 1,181 | **1,177** (`TMODE_COOK` `TMODE_RAW` `TMODE_SLEEP` `MCH_DELAY_SETTMODE`) |
| `nm -u` with zero's own flags | 31 | **24**, the gone set as one `comm` |
| `nm -u` as `tools/symbols.sh` counts it | 32 | **25** |
| external symbols | `main` | `main` |
| `#include` | 12 | 12 |
| `options[]` rows | 108 | **107** (`'termresize'`) |
| `cmdnames[]` rows | 98 | 98 — **no Ex command is touched** |
| `nv_cmds[]` rows | 194 | 194 |
| binary | 805,544 | **797,192 (−8,352)** |
| sweep | | 2 rounds, 0 warnings |
| phase | | **56 s**, of which the probes are most |

### Its placement

`stage 20`, `package host` beside 17, 18 and 19, with `uses host:20 seed:0`,
`uses host:20 harness:3` and `uses host:20 terminal:2 rationale` — phase 2 removed the
two "not to a terminal" warnings, and this is where the core stops asking the kernel
about a terminal at all. The two dependencies a reader expects, on phases 18 and 19,
**cannot be written**: `tools/packages.sh --check` refuses a `uses` inside one package,
and 17–20 are one. Their reasons are in the phase program's header instead — the host
block goes inside the launcher region phase 18 created, and the deadly-signal restore
ends in phase 19's `vim_host_exit` → `__builtin_longjmp` → `return 1`.

**`need 20 swept` is not required, and it was measured.** The edit applied to the
unswept text phase 19's edit leaves gives the identical 80,447 → 80,181; every anchor
is exact text at a counted occurrence.

**`apart 19 20`, measured, and the first of its three messages is the one a reader
would not predict.** `tools/phaserun.sh zero 19-20` on r18 stops in phase 19's check
with `` `deathtrap` as a whole word has 4 mentions, expected 3 `` — a phase about
*removing* signal handling leaves one **more** mention of a handler, because the host
installs the core's rather than replacing it. The other two are ordinary: `the file
gained -280 lines, expected 18`, and `options[] is not the 108 rows phase 12 left`.
**This one is both directions**, unlike 16–17, 17–18 and 18–19: phase 20's own check
states its gone set as one `comm` against the stage's symbol snapshot, and a stage
takes one snapshot at its start — so on a 19-20 stage it is handed r18's set and the
gone set is its seven **plus `exit`**. That is `apart 14 15`'s shape, and it is
reasoning from the two programs rather than a second run, because 19's check refuses
first and there is nothing after it to observe.

### What zero-vim is after twenty phases

```
zero-vim.c        80,148 lines          from whim-vim.c's 86,614  (-6,466, 7.5%)
functions         1,757
type definitions  904
DWARF enumerators 1,177
cmdnames[] rows   98    (create_cmdidxs floor 80; 18 rows of margin)
nv_cmds[] rows    194   (nvidxcheck: a permutation)
options[] rows    107, 95 distinct globals  (orphanopts floor 80; 15 of margin)
#include          12, every one a system header; no #define, no conditional
libc symbols      24 with zero's flags, 25 as tools/symbols.sh counts
binary            797,192 bytes, EXEC, no INTERP, no dynamic section, no relocation
declared delta    20 records + stderr-moved, from whim-vim
```

**The 24, attributed — and two rows are now the host block's alone.**

| why | symbols |
| --- | --- |
| **the terminal**, every one of them in the host block | `read` `write` `ioctl` `select` `tcgetattr` `tcsetattr` `nanosleep` (7) |
| **messages before and after the screen** | `printf` `fflush` `stderr` (3) |
| **memory** | `malloc` `free` `realloc` (3) |
| **time** | `time` `gettimeofday` (2) |
| **signals**, all four in the host block | `sigaction` `sigemptyset` `kill` `getpid` (4) |
| **gcc's own**, named nowhere in the source | `__errno_location` `fputc` `fputs` `fwrite` `putchar` (5) |

`getpid` is the odd one: it is `mch_get_pid()`'s, called once to write `b0_pid` into
block zero, and `vim_handle_signal()`'s re-raise — neither is this phase's, and `b0_pid`
is written and never read, so one line frees it whenever block zero is somebody's
phase. `__errno_location` stays too, and the phase says so rather than implying
otherwise: `errno` has exactly three mentions and does not move at all — the
`#include <errno.h>`, the `tcsetattr` retry and the `select` test — and the last two are
host-side now, so **`<errno.h>` leaves the CORE and the symbol leaves the process at the
split**.

**`ZERO-PLAN.md` §4c is built out.** Its three steps were `main()`, the two stream
calls, and the terminal with its signal set; 18 and 19 did the first and this does the
third, and the second is what is left — `mch_write`'s `write(1, …)` and
`musl_read_input`'s `read(0, …)`, the last two syscalls the core still makes for
itself. What remains after that is the file split, and `tools/zhostonly.py` is the
check that survives into it: when `editor.c` and `zero-vim.c` become two files, the
host block becomes the second file and the tool becomes `grep` over the first.

## Phase 21 — the messages are the editor's, the writing is the host's

`pipes/zero21-edit.sh` and `pipes/zero21-check.sh`, `stage 21`, `package host`.
`ZERO-PLAN.md` §4c's second step, and the half of it that is not the screen: *"`printf`
for the messages that appear before there is a screen, which is itself a question for
the host"*. Every byte this file has ever put on a **stream** instead of a screen now
goes through one callback the launcher installs, in exactly phase 19's shape:

```c
static void (*vim_host_message)(const char *msg, int len, int err);

    static void
host_message(const char *msg, int len, int err)
{
    ...
    int w = (int)write(err ? 2 : 1, msg + off, (size_t)(n - off));
    ...
}
```

`vim_main()` takes it as a fourth parameter and installs it beside `vim_host_exit`; the
two become `musl_` prototypes at the split, together. `<stdio.h>` goes with the symbols
— **twelve directives become eleven**, the second time a zero phase has removed one and
the same argument phase 16 made.

**Formatting stays in the core, and that is what turns twenty statements into eight call
sites.** `vim_snprintf` has been the only formatter in the file since phase 14, so the
two multi-part speakers assemble into a 1024-byte local and hand over one string, and
the other six sites are one call each with the text unchanged. Measured with a
`SOCK_SEQPACKET` socketpair as fd 2, which preserves write boundaries exactly: `-Q` was
**6 writes of 96 bytes and is 1 write of 96**; `-T no-such-term-9x` was **5 of 54 and is
1 of 54**. The same bytes, one syscall — and the latent hazard goes with them, stdout's
buffered `printf` arm arriving after everything the editor drew.

### Four of the seven symbols are named nowhere in the source

Unlike phase 20 this one really frees symbols, and the reason is the rule phase 20
stated: a symbol leaves when its last **caller** leaves the file. `printf` and `fprintf`
were being *called* here, not merely mentioned.

```
nm -u  24 → 17, gone exactly
    fflush  fputc  fputs  fwrite  printf  putchar  stderr
arrived: nothing
```

**`fputc`, `fputs`, `fwrite` and `putchar` have never appeared in `zero-vim.c` at all.**
They are what gcc emits for `printf("%s", x)` and `fprintf(stderr, "%s", x)`, and no
grep of the source could have found them. So they were **predicted** to leave with the
construct and then **verified by building** — which is the whole reason the check states
the claim as one `comm` with an *empty* `arrived` side rather than as a count. A
prediction about a symbol the source does not name has nothing but the linker to
confirm it.

**`__errno_location` is not this phase's and the check requires it PRESENT.** `errno` is
3 → 3, its two uses being `host_tty_set`'s and `musl_wait_for_input`'s `EINTR` tests,
both inside phase 20's host block. It leaves at the split, not here — said out loud,
because a reader who watches seven symbols go will look for the eighth.

**And `printf` is not at 0.** It is 13 → 10, and none of the ten is a call: nine are
`__attribute__((format(printf, …)))` and one is the string `"E767: Too many arguments
for printf()"`. `assert printf at 0` fails on a correct phase. The assertions that work
are `fprintf` 16 → 0, `stderr` 17 → 0, `fflush` 1 → 0, `printf` 13 → 10, and `nm -u`.

### The inventory is twenty statements in five functions, and the brief said twenty-one in six

The survey this phase was written from counted twenty-one output statements in six
functions, and the sixth was `nv_esc`'s `Type :qa! and press <Enter> to abandon all
changes`. **Phase 20 had already taken it**, with `stdout_isatty` and the `out_redir`
arm it sat in. So `fprintf` is sixteen here and not seventeen, `stderr` is seventeen and
not eighteen, and there are **eight call sites and not nine**. The edit counts its input
rather than trusting the survey, which is the only reason the arithmetic closed:

| function | statements | what it says |
| --- | --- | --- |
| `mainerr` | 6 `fprintf` | the version banner and the argv refusal |
| `report_term_error` | 7 `fprintf` | `'<term>' not known, defaulting to 'xterm'` |
| `set_termname` | 1 `fflush` | eleven lines *below* the call above, not inside it |
| `msg_puts_printf` | 2 `printf`, 2 `fprintf` | whatever message was being printed |
| `exit_scroll` | 1 `printf`, 1 `fprintf` | `"\n"` / `"\r\n"` on the way out |

The instrument goes on **nineteen** of the twenty, `fflush` taking no message.

### `msg_puts_printf()` and `exit_scroll`'s printf arm are deliberately KEPT

All 75 lines of the first and the else arm of the second stay, and that is a decision
rather than an oversight. **`msg_use_printf()` is not dead: it returns TRUE 23 times in
106 records** — once in each `mainerr` record, from `mch_exit` → `exit_scroll()`'s else
arm → `msg_clr_eos_force()`, where `full_screen` is FALSE and the body it guards
therefore does nothing. It is never true at `msg_puts_attr()`'s call site, so
`msg_puts_printf()` is entered **0 of 106 records** against a control that marks 100 of
102 screens. That is phase 12's kind of dead and not phase 9's: the branch *can* be
taken and never is.

Folding either would run `screen_fill()` on a screen the test has just called unusable —
`msg_clr_eos_force()` with no valid screen, or `msg_puts_display()` on a screen
`msg_use_printf()` has just said is not there. Removing them is a separate phase with a
separate question — *"the screen is always usable in this build"* — and phase 12's kind
of evidence to gather, and **it would free nothing, because the symbols are gone here**.

**PHASE 30 CORRECTED THIS, AND THE PART THAT IS WRONG IS THE PART ABOUT
`exit_scroll`.** This phase's check says the two speakers "fire in ZERO of 106
records", which is true of the **corpus** and true of the **editor** only for
`msg_puts_printf()`. `exit_scroll()`'s printf arm is **alive**, with no signal at all:
measured in phase 30's check, it moves **three of that phase's 32 stream probes**
(`t_ti_more`, `debug_more`, `term_ti_then_ti` — each `:set t_ti=X` or `-T debug`, a
paged `:set all`, exit) and **three of its four deadly-signal probes**. It is invisible
here because a recording drives one pty on which fd 1 and fd 2 are the same device and
the two bytes are the same two bytes either way — `out_char('\n')` emits `\r` first —
so the fold moves them from **fd 2 to fd 1** and nothing in this pipeline's instrument
can see that. It is therefore not merely undone but **undeclarable**, and it belongs to
whichever phase decides the core writes nothing to fd 2 at all. The other half of the
sentence survives intact: `msg_clr_eos_force()`'s test cannot be folded safely, and
phase 30 measured *why* — `screen_fill()` returns early on `ScreenLines == nullptr`, so
the fold leaves the whole 106-record recording byte-identical and two probes see the
eighteen extra bytes it emits after `Vim: Finished.`

### The bound that comes with the buffer, stated rather than declared

`mainerr`'s `str` and `report_term_error`'s `term` are both argv, so assembling into a
1024-byte buffer caps a message that used to be unbounded. That is a real behaviour
change and **no instrument in this pipeline can see it**, because nothing in the corpus
comes within 800 characters of the bound and `pipes/zero.delta` is a list of records
that moved. So it is not declared; it is pinned as probes, in both directions and in
both speakers, so it cannot drift:

| probe | the input | this |
| --- | --- | --- |
| an unknown option of **900** characters | 995 B | **995 B — byte-identical** |
| an unknown option of **930** characters | 1,025 B | **1,023 B — the turn** |
| an unknown option of **2,000** characters | 2,095 B | **exactly 1,023 B** |
| `-T` of **900** characters | 939 B | **939 B — byte-identical** |
| `-T` of **2,000** characters | 2,039 B | **exactly 1,023 B** |

1024 is `IOSIZE`, which is what every other message in this editor is built in. The
counts are **raw and not scrubbed** except at 900: the version banner's
`__DATE__`/`__TIME__` differ between two builds and their *length* does not, so only the
equality needs scrubbing and the caps do not.

### `zerodelta.sh` is the second opinion here and not the first

The declared delta is nothing at all, and two full recordings either side are
**byte-identical** — `diff -r` reports 0 lines across 102 screen cases, `ref-excmds.txt`,
`ref-argv.txt`, `ref-pty.txt` and `ref-term.txt`. The control proves that table can
fail: `write(err ? 2 : 1, …)` made `write(err ? 1 : 1, …)`, **one character**, moves 24
records and **217 lines** of `diff -r`.

**And it confirms a trap the survey named.** Run on the same control,
`tools/zerodelta.sh` names only **fourteen** of those twenty-four, because ten of them
are argv rows phases 4 and 5 already declared (`-`, `--`, `-e`, `-E`, `-e -s`, `-v`,
`f.txt`, `f.txt g.txt`, `+q! f.txt`, `-- +q!`) and `tools/zcompare.py` therefore accepts
any *further* movement in them silently. A declared row is not compared again. So this
check diffs the two recordings itself and keeps `zerodelta.sh` as the second opinion —
run on the control, where it must refuse.

**The instrumented pair is what makes the empty declaration mean something**, and it is
phase 9's shape: the input built with `write(2, "MESSAGE-OUT\n", 12)` at all nineteen
output statements and the output with the identical instrument inside `host_message()`
mark **exactly the same 24 of the 30 argv rows, by name**, and 0 of 102 screens, 0 of
`ref-excmds.txt`, 0 of `ref-pty.txt` and 0 of `ref-term.txt`. Same places, same times,
different primitive. The 24 are 23 `mainerr` and one `report_term_error` — which is also
what says the other four speakers fire in zero of 106 records.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 80,148 | **80,173 (+25)** |
| functions | 1,757 | **1,758** (`host_message`) |
| type definitions | 904 | 904 |
| DWARF enumerators | 1,177 | 1,177 |
| `nm -u` with zero's own flags | 24 | **17**, the gone set as one `comm` |
| `nm -u` as `tools/symbols.sh` counts it | 25 | **18** |
| external symbols | `main` | `main` |
| `#include` | 12 | **11** (`<stdio.h>`) |
| bare `write()` call sites | 1 | **2** — `mch_write`'s and `host_message`'s |
| `options[]` rows | 107 | 107 |
| `cmdnames[]` rows | 98 | 98 |
| `nv_cmds[]` rows | 194 | 194 |
| binary | 797,192 | **784,392 (−12,800)** |
| sweep | | 0 warnings |
| phase | | **28 s** |

### Its placement

`stage 21`, `package host` beside 17, 18, 19 and 20, with `uses host:21 seed:0` and
`uses host:21 harness:3` mechanical, `uses host:21 vendor:14 mechanical` — `mainerr` and
`report_term_error` assemble with `vim_snprintf`, which is the only formatter left in
the file because phase 14 put `sprintf` onto it rather than vendoring one — and
`uses host:21 includes:16 rationale`, because a phase may remove a directive at all only
since phase 16 replaced the charter's old reading of the directive count as a property
the pipeline preserves.

**`need 21 swept` is not required, and it was measured** in the same run that measured
`apart 20 21`: phase 21's edit applied to the **unswept** text phase 20's edit leaves
gives 80,181 → 80,206, every one of its anchors holding — the twelve input counts, the
twenty statements, the eleven output counts and the whole launcher tail. Its cuts are
exact text in functions no sweep touches and its computed parts are counts of words a
sweep cannot create, so there is nothing that could shrink silently.

**`apart 20 21`, measured, one direction only.** `tools/phaserun.sh zero 20-21` on r19
runs both edits and two sweeps and stops in phase 20's check on one message — *"the
output does not have exactly the twelve `#include` directives phase 16 left"*. Phase 20
states the twelve as a property it preserves and this phase takes `<stdio.h>`. There is
a second reason the run never reaches, and it is `apart 14 15`'s and `apart 19 20`'s
shape: phase 20 states its gone set as one `comm` against the **stage's** symbol
snapshot, a stage takes one snapshot at its start, so on a 20-21 stage its gone set
would be its seven plus these seven.

### What zero-vim is after twenty-one phases

```
zero-vim.c        80,173 lines          from whim-vim.c's 86,614  (-6,441, 7.4%)
functions         1,758
type definitions  904
DWARF enumerators 1,177
cmdnames[] rows   98    (create_cmdidxs floor 80; 18 rows of margin)
nv_cmds[] rows    194   (nvidxcheck: a permutation)
options[] rows    107, 95 distinct globals  (orphanopts floor 80; 15 of margin)
#include          11, every one a system header; no #define, no conditional
libc symbols      17 with zero's flags, 18 as tools/symbols.sh counts
binary            784,392 bytes, EXEC, no INTERP, no dynamic section, no relocation
declared delta    20 records + stderr-moved, from whim-vim
```

**The 17, attributed — and a whole row of the table is gone.**

| why | symbols |
| --- | --- |
| **the terminal**, every one of them in the host block | `read` `ioctl` `select` `tcgetattr` `tcsetattr` `nanosleep` (6) |
| **the two writes** — `mch_write`'s in the core, `host_message`'s in the launcher | `write` (1) |
| **memory** | `malloc` `free` `realloc` (3) |
| **time** | `time` `gettimeofday` (2) |
| **signals** — `sigaction` and `sigemptyset` in the host block, `kill` and `getpid` in both | `sigaction` `sigemptyset` `kill` `getpid` (4) |
| **gcc's own**, named nowhere in the source | `__errno_location` (1) |

**There is no row for "messages before there is a screen" any more**, and the five-strong
"gcc's own" row is down to one. `write` has a row of its own because it is the only one
here the **core** still does for itself as well as the host: `mch_write`'s
`write(1, …)`, which with `musl_read_input`'s `read(0, …)` is all of `ZERO-PLAN.md`
§4c's remaining step.

## Phase 22 — the variadic collapse

`pipes/zero22-edit.sh` and `pipes/zero22-check.sh`, `stage 22`, `package format`.
C cannot forward `...` — which is why `vsnprintf` exists beside `snprintf` — so a
function that takes `...`, opens a `va_list` and hands it to `vim_vsnprintf` cannot
survive a split unless the formatter goes with it. There are eight such functions.
**Seven are wrappers over the eighth**, and this phase expands every one of their 129
call sites into `vim_snprintf(…)` plus the tail the wrapper ran afterwards.

**`va_start` goes from eight functions to one**, and that is the whole product: no libc
symbol falls, no Ex command goes, no option goes, no message changes, and the binary
gets *bigger*. This is the half of the `va_list` decision that needs only one file, and
it exists separately for the reason `ZERO-PLAN.md` §4c gives — its declared delta must
be nothing at all, provable as a byte-identical recording, which is a far stronger
position from which to make 129 mechanical edits than making them while everything else
is moving.

| wrapper | mentions | protos | own def | **call sites** |
| --- | --- | --- | --- | --- |
| `smsg` | 12 | 1 | 1 | **10** |
| `smsg_attr` | 4 | 1 | 1 | **2** |
| `smsg_attr_keep` | 2 | **0** | 1 | **1** |
| `semsg` | 96 | 1 | 1 | **94** |
| `siemsg` | 12 | 1 | 1 | **10** |
| `vim_snprintf_add` | 3 | 1 | 1 | **1** |
| `vim_snprintf_safelen` | 13 | 1 | 1 | **11** |
| | | | | **129** |

`smsg_attr_keep` has no prototype and `vim_snprintf` has **two**, so a phase that
deletes "the prototype and the definition" for each of seven names fails on the first
and leaves one behind on the second.

### No message logic was written, because the tails already existed

Read each wrapper beside its non-variadic twin and the wrapper *is* the twin with a
format in front of it. `semsg`'s tail is `emsg()`, `siemsg`'s is `iemsg()`, `smsg`'s is
`msg()`, `smsg_attr`'s `msg_attr()`, `smsg_attr_keep`'s `msg_attr_keep(…, TRUE)`. All
five already existed and all five were already called from elsewhere. What is left over
is the two guards, and those become helpers: `iobuff_room()`, `emsg_iobuff_room()`,
`iobuff_or()`, `safelen_result()` and `append_room()` — **five helpers against seven
deleted definitions, which is the whole of 1,758 → 1,756.**

**The size-zero trick is what makes the expansion exactly faithful, and it was measured
rather than assumed.** `vim_vsnprintf_typval` guards every write with
`if (str_l < str_m)` and terminates with `if (str_m > 0)`, so `vim_snprintf(buf, 0, …)`
**writes nothing and does not fault** — measured with a build whose first act is
`vim_snprintf(canary, 0, …)` and `vim_snprintf(NULL, 0, …)`: all eight canary bytes
untouched, no fault on the null destination. So a helper returning 0 reproduces **both**
of the wrapper's guards — `emsg_off > 0` and `IObuff == NULL` — with **no conditional at
any site**. That is why there are five helpers and not an `if`/`else` written out 117
times.

### The sites come in three shapes, and an edit that emits two statements always gets two of them wrong

| shape | sites | what the expansion does |
| --- | --- | --- |
| a plain statement alone on its line | **92** | two lines at the same indentation |
| a **whole block on one line** inside `parse_fmt_types` | **7** | inline on the same line — two lines would put a statement in front of the closing brace |
| **value position** | **30** | a comma expression, the format call then the tail |

The 30 are the 18 `return (semsg(…), rc_did_emsg = TRUE, (void *)NULL);` comma
expressions in the regexp engine, all eleven `vim_snprintf_safelen`s — whose value is
consumed at every site, five of them `+=` — and `vim_snprintf_add`'s one. A statement is
told from an operand by the character after the closing paren. **The comma shape already
existed in the file**, as `return (iemsg(e_internal_error_in_regexp), rc_did_emsg =
TRUE, (void *)NULL);`, so the expansion invents no idiom.

The survey split them 93 / 29 / 7 and put `vim_snprintf_add`'s site in the plain column;
it is in value position, and the implementation's 92 / 30 / 7 is the count that makes
the edit correct.

### All 129 formats are non-literals, which is why the warning list is the check that matters

The thing a reader expects to be a problem is not one, and the measurement is the
opposite of the expected answer: **every one of `semsg`'s 94 formats is `_(e_name)` or
`(const char *)(_(e_name))`**, where `e_name` is a `static char e_name[] = "E123: …";`
array. Whim's constant fold turned upstream's string macros into arrays, so **there is
no string literal at a `semsg` site anywhere in the file.** It changes nothing about the
edit, which copies the format *expression* verbatim into `vim_snprintf`'s third
argument — but it means the build cannot catch a mis-expanded argument list.

What can is `-Wformat=2`. The wrappers carry `format(printf, 1, 2)` / `(2, 3)` / `(3,
4)` and `vim_snprintf` carries `format(printf, 3, 4)`, and every expansion puts the
format expression at `vim_snprintf`'s third parameter — so gcc checks exactly what it
checked before. **115 `-Wformat-nonliteral` warnings in 53 functions before, and the
identical 115 in the identical 53 after**, compared as an exact list equality and not as
two numbers. `_()` and `NGETTEXT()` are `static inline __attribute__((format_arg(1)))`,
so gcc sees through them either side.

**And the invariant fired for real on its first run**, which is the part worth keeping.
It reported `115 warnings in 0 distinct functions`: gcc quotes identifiers as `'x'`
under the phase's locale and as curly quotes under the author's, so the function-name
regex matched nothing and an empty list compared equal to an empty list. The regex
matches both quotings now, and **a zero-function list can no longer pass for an
equality** — a list comparison that can be satisfied by two empty lists is the same
mistake as a test that cannot fail.

The other thing that could have gone wrong was measured too. The expansion mentions the
format **twice** — once in `vim_snprintf`, once in the tail's `iobuff_or(F)` — and over
all 129 sites every format expression is side-effect-free: 118 are `_(e_name)`, a bare
`e_name` or a literal, 8 are `NGETTEXT(a, b, n)` (a pure inline `return`), 2 are a `? :`
over two `_()`s, and 1 is a parameter.

### `nm -u` cannot move for a restructure inside one translation unit, and the check asserts that as an equality

```
nm -u  17 → 17, THE SAME SET
gone: nothing        arrived: nothing
```

A reader meeting a 129-site phase expects a symbol to fall, and none can: a symbol
leaves when its last **caller** leaves the file, and nothing left. `vim_vsnprintf_typval`
still does every conversion in the same file, and `<stdarg.h>`'s three names are macros
and a compiler builtin type, which are no symbol at all. **The binary GROWS — 784,392 →
788,488 — and the check requires it to**, because at `-O0` 129 sites that carried one
call now carry a format call and a tail call. It is the same fact wearing its other
face, and the check reports the number rather than letting it look like a mistake.

What the phase moves is not code across a boundary but the **possibility of drawing
one**: eight functions calling `va_start` cannot be split, one can.

### Two controls move nothing, and they are kept

The recording is nearly blind to this phase, and that is measured rather than asserted.
The input source built again with `write(2, "ZW|<wrapper>|<format>\n", …)` at the entry
to each of the seven, run over the 102 screen cases: `vim_snprintf_safelen` is entered
**617** times, `smsg_attr_keep` **6**, `vim_snprintf_add` **2**, and `smsg`, `smsg_attr`,
`semsg` and `siemsg` **not once**. `semsg` is 94 of the 129 sites and the screen corpus
enters it zero times. So the phase owes probes, and the check runs **263** on both
binaries — the Ex-command errors, 132 regexp errors over both engines and three magic
settings (which are where the 18 comma-expression sites live), the report messages, the
substitute-confirm prompt, undo, CTRL-G and the ruler, and four incsearch probes with a
bad pattern, which are the only way to reach a `semsg` under `emsg_off > 0`. The same
instrument says they enter `semsg` **232 times over 34 distinct formats** and reach **67
of the 129 sites**.

**263 probes, 0 differ. Four deliberate breaks, and two of them move nothing on
purpose:**

| break | records that differ |
| --- | --- |
| both room helpers return 20 instead of `IOSIZE` | **129 of 263** |
| every `semsg` site given `msg()` for a tail instead of `emsg()` | **155 of 263** |
| `safelen_result`'s clamp reduced to `return str_l;` | **0 of 263** |
| all three guards removed | **0 of 263** |

The two zeroes are reported rather than dropped, in the program, the delta file and
here, because **they are the honest statement of what this evidence cannot reach**: the
clamp needs a message longer than 1,025 bytes out of `fileinfo`, and the guards need
`IObuff == NULL`, which is an out-of-memory failure of the first two allocations the
process makes. Reporting them as 0 is the difference between *"the probes prove the
guards are load-bearing"*, which would be false, and *"the guards are correct by
construction and the probes say so about the other two"*.

The other 62 sites are covered by the edit being **one rule applied uniformly** and by
the whole-file equalities above. `semsg`'s unreached sites are out-of-memory reports and
the twenty inside the formatter itself — which fire only on a format string the editor
would have to have got wrong, and every format in this file is one of its own — and
`siemsg`'s ten are the memfile detecting its own corruption.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 80,173 | **80,176 (+3)** |
| functions | 1,758 | **1,756** — seven wrappers out, five helpers in |
| type definitions | 904 | 904 |
| DWARF enumerators | 1,177 | **1,177**, and not one went, arrived or renumbered |
| `va_start` / `va_list` / `va_end` | 8 / 15 / 10 | **1 / 8 / 3** |
| `vim_snprintf` mentions | 73 | **201** — one per site less the redundant second prototype |
| `-Wformat-nonliteral` | 115 in 53 functions | **the identical 115 in the identical 53** |
| `nm -u` with zero's own flags | 17 | **17, the same set**, a `comm` empty both ways |
| `nm -u` as `tools/symbols.sh` counts it | 18 | **18** |
| external symbols | `main` | `main` |
| `#include` | 11 | 11 |
| `options[]` / `cmdnames[]` / `nv_cmds[]` rows | 107 / 98 / 194 | 107 / 98 / 194 |
| binary | 784,392 | **788,488 (+4,096)** |
| sweep | | takes nothing, 0 warnings |
| phase | | **37 s** |

**Four functions still hold a `va_list`** — `vim_snprintf`, `vim_vsnprintf`,
`vim_vsnprintf_typval` and `skip_to_arg`, the positional-argument walker, which
`ZERO-PLAN.md` named as three. All four belong below the first `#include` when the
reorganisation comes.

### Its placement

`stage 22`, `package format`. **`format` is a new package and it is deliberately not
`vendor`**: nothing is brought in. A layer is *flattened* — seven wrappers over one
formatter become 129 call sites and five helpers, so that `va_start` appears once and
the formatter becomes movable. Its `uses` are `format:22 seed:0` and
`format:22 harness:3` mechanical, `format:22 vendor:14 rationale` — `musl_strlen` is
what `append_room()` measures the appended string with, and phase 14 is where the core
got its own string functions — and `format:22 host:21 mechanical`, because phase 21
routed `mainerr` and `report_term_error` through `vim_snprintf`, so the mention count
this phase's arithmetic starts from is phase 21's. **The check therefore asserts
`vim_snprintf`'s count only AFTER**, as the transformer's own arithmetic against
whatever it was handed.

**`need 22 swept` is not required, and it was measured** in the same run that measured
`apart 21 22`: this edit finds its sites by word boundary and balanced parens over the
whole file and asserts no counted anchor a sweep can move, and on phase 21's **unswept**
output it finds the same 129 sites in the same 92 / 7 / 30 shapes, 80,174 → 80,182
lines.

**`apart 21 22`, measured, and the first complaint is not the predicted one.**
`tools/phaserun.sh zero 21-22` on r20 stops in phase 21's check with **``printf` has 4
mentions, expected 10``** — phase 21's own documented counting trap read from the other
end. None of the ten is a call; nine are `format(printf, …)` attributes, and **six of
those nine sit on the wrapper prototypes this phase deletes**. The other three
complaints are ordinary: ``vim_snprintf` has 201 mentions, expected 73``, ``musl_strlen`
has 135 mentions, expected 134`` — `append_room()`'s — and *the file is 80176 lines and
the input was 80148, expected exactly 25 more*. **One direction only**, and it is not
observable in that run because 21's check refuses first.

### What zero-vim is after twenty-two phases

```
zero-vim.c        80,176 lines          from whim-vim.c's 86,614  (-6,438, 7.4%)
functions         1,756
type definitions  904
DWARF enumerators 1,177
cmdnames[] rows   98    (create_cmdidxs floor 80; 18 rows of margin)
nv_cmds[] rows    194   (nvidxcheck: a permutation)
options[] rows    107, 95 distinct globals  (orphanopts floor 80; 15 of margin)
#include          11, every one a system header; no #define, no conditional
libc symbols      17 with zero's flags, 18 as tools/symbols.sh counts
binary            788,488 bytes, EXEC, no INTERP, no dynamic section, no relocation
declared delta    20 records + stderr-moved, from whim-vim
va_start          1, in vim_snprintf
```

**The 17 are phase 21's 17, unchanged**, and that is this phase's claim rather than an
omission. What it produced is not a symbol, a line count or a row but a *shape*: one
`va_start` in the file, which is what the split needs and what nothing before it could
have asserted.

## Phase 23 — `nullptr` and `usize`

`pipes/zero23-edit.sh` and `pipes/zero23-check.sh`, `stage 23`, `package boundary`.
`ZERO-PLAN.md` §4c settled the design: **there is no split into two files, there is one
file with two parts, and the first `#include` is the boundary.** The core is the prefix
above it and must name nothing a header supplies. Four phases draw that line; this is
the first, and it is deliberately the smallest **because it is the one that can be
checked by `cmp`**.

Two names the core takes from a header are replaced by two the **language** supplies:

```c
    NULL    →  nullptr                            a C23 keyword; nothing is declared
    size_t  →  usize                              typedef typeof(sizeof(0)) usize;
```

Neither is a new dependency. gcc here defaults to C23 — `__STDC_VERSION__` is
`202311L` — and this file already depends on it for `enum : long`, `static_assert` and
the lowercase `bool`/`true`/`false` it uses throughout. The check states the dependency
as a measurement rather than leaving it implicit: it lifts the typedef line **out of the
output** and compiles it four ways, where gcc's default and `-std=c23` must accept it
and `-std=c11` and `-std=c99` must refuse.

**Both spellings came from the user and both beat what had been proposed.** An
enumerator with the value 0 is a null pointer constant everywhere except a variadic
argument, where it passes four bytes to a callee reading eight **with no warning from
gcc**; `nullptr` is typed, so the hazard does not exist and the rule the phase would
have had to assert for ever is not needed. And `typeof(sizeof(0))` **is** `size_t` on
any target, because `sizeof(0)` has that type by definition — proved in the same
translation unit as the real `<stddef.h>` with `_Generic((usize)0, size_t: 1, default:
0)`, which is the same *type* and not merely the same width. `typedef unsigned long
size_t;` is correct here and silently wrong elsewhere, and silent when it is right, so
nothing in this repository could have told the two apart.

The `#include`s stay at the top. Moving them is phase 27 — 26 when this was written,
before the attributes took the number 24. Eleven directives sit on the
first eleven lines and the typedef on line 13, which is the whole of **+2 lines**.

### The binary is byte-identical, and that is the whole of the evidence

`cmp` of the input's binary against the output's, both built with
`SOURCE_DATE_EPOCH=0` and the boundary's own flags: **788,488 bytes either side, no
difference at all**. That is tier 1 of `CLAUDE.md`'s verification table, and it subsumes
every screen case, every Ex-command row, every command line and every pty scenario at
once, **because the program that would be run is the same program**. `nm -u` holds still
as a `comm` empty both ways, `main` is still the only external symbol, the sweep took
nothing and canon settled in one round. `tools/zerodelta.sh --phase 23` still runs and
corroborates; it is not the evidence. It is phase 16's shape exactly, on three thousand
edits instead of seven.

### Every `size_t` was partitioned before any was renamed

`NULL` 2,555 → 3 and `size_t` 437 → 0, and the second number is a **partition and not a
count**. The edit classifies all 437 into

| class | sites |
| --- | --- |
| casts — `(size_t)` and `((size_t)` | **202** |
| declarations — parameter, local, struct field, return type | **235** |
| anything else | **0** |

and **refuses on a leftover**. A leftover would be a use a typedef does not serve — a
case label, an array bound, a `sizeof(size_t)` — and there are none. The classification
is computed from the text, so it stays true of a file this phase has never seen; the
edit asserts no *count* of its input at all, because one rule applied to every
occurrence is correct for any number of them, and pinning the count would make the phase
refuse on a tree that is merely bigger without making a wrong substitution any more
visible.

**The eleven vendored signatures change with everything else, and that is not an
interface change.** `musl_memcpy musl_memmove musl_memset musl_memcmp musl_memchr
musl_strncpy musl_strncmp musl_strncasecmp musl_bsearch musl_qsort` take `usize`
parameters and `musl_strlen` returns one. They have been the core's own `static`
definitions since phases 14 and 15 — nothing outside this file calls them — so renaming
their parameter type changes no contract with anybody.

### Three `NULL`s survive, and the control is what proves they matter

Three string literals in this file contain `NULL`:

```
"E1507: Internal error: ap_types or ap_types[idx] is NULL: %d: %s"
"[NULL]"          the printf layer's stand-in for a null %s argument
"NULL"            what ga_print writes for an empty growarray
```

and no literal contains `size_t`. So the substitution is not a `sed`: it scans the file
for string and character literals first — cheap and exact here, this file having no
preprocessor and no comments — and rewrites only outside them.

**The check builds the literal-unaware form as a control and requires it to differ.**
Measured: a plain line-wise `\bNULL\b` → `nullptr` gives a binary **1,598 bytes
different — 50 in `.text`, 174 in `.data` and 1,354 in `.rodata`** — and `strings` finds
`[nullptr]`, `nullptr` and an E1507 message that names a C keyword at the user. That is
`CLAUDE.md`'s rule that *what must not change is data, and the check for that is the
strings*, arriving on a phase nobody expected it on. Without the control the `cmp` above
is a pair of numbers agreeing, and a test that cannot fail is not evidence.

The survey measured the same control at **1,597 bytes and 49 in `.text`**; it ran it on
r21, and on r22 — the text this phase was actually handed — it is 1,598 and 50. The
`.rodata` and `.data` figures are the same either side, which is what says the extra
byte is code motion and not another string.

### The one-pass rule, which is worth more than the phase

**Both names must be rewritten in ONE pass over the original text**, and that is not
tidiness. A second pass indexes literal spans computed on the **first pass's output**,
and every span after the first replacement is shifted. Measured: the two-pass form
leaves **five of the 437 `size_t` behind** — and leaves a file that still **compiles**,
whose binary is still **byte-identical**, because `<stddef.h>` is still above every line
of it. Every check this phase has passes on that file except the count.

It would have surfaced at phase 27, as five unexplained errors in a move that had
nothing to do with them and nothing pointing back here. **A whole-file substitution is
literal-aware and single-pass**, and `CLAUDE.md` records it as a pattern now rather than
as this phase's incident.

### The thirty `(void *)NULL` become plain `nullptr`, and the survey said eighteen

That is a decision and not a mechanical consequence: a mechanical `\bNULL\b` → `nullptr`
leaves them as `(void *)nullptr`, which compiles and is byte-identical. The cast exists
for exactly one hazard — an untyped null constant in a variadic argument position
passing a four-byte `int` where the callee reads an eight-byte pointer — and `nullptr`
is typed, `sizeof(nullptr) == sizeof(void *)`, so the cast now says nothing a reader
needs. Doing it here rather than later is what keeps those sites from being touched
twice.

**The survey counted eighteen of them and it was simply wrong**, at r22 and at r21
alike. Re-measured, there are **thirty**: 28 comma expressions in the regexp parser,
`return (emsg(…), rc_did_emsg = TRUE, (void *)NULL);`, where the cast was carrying the
comma expression's type, and 2 returns in `get_register`. `nullptr_t` converts to any
pointer type on return, so they are the same program — which the `cmp` says. The
survey's occurrence counts were r21's as well, and phase 22 moved both.

### And one control that moves nothing, reported rather than dropped

Reverting one `usize` to `size_t` compiles cleanly and gives a byte-identical binary,
because the `#include`s are still at the **top** of the file and `size_t` is therefore
still declared above every line of it. That is the honest statement of what this phase's
evidence cannot reach: **the rename is not yet load-bearing**, and it becomes so at
phase 27, where the same control is three hard errors — measured there and exactly
three: reverting one `usize` in `musl_bsearch`'s signature gives two `unknown type name
'size_t'` and one implicit declaration at its call site. It is phase 22's b3/b4 in this
phase's shape.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 80,176 | **80,178 (+2)** — the typedef and its blank |
| functions | 1,756 | 1,756 |
| type definitions | 904 | **905** (`usize`) |
| DWARF enumerators | 1,177 | 1,177 |
| `NULL` | 2,555 | **3**, all three inside string literals |
| `nullptr` | 0 | **2,552** |
| `size_t` | 437 | **0** — 202 casts and 235 declarations, nothing left over |
| `usize` | 0 | **438** — the 437 and its own typedef |
| `(void *)NULL` | 30 | **0** |
| `nm -u` with zero's own flags | 17 | **17, the same set**, a `comm` empty both ways |
| `nm -u` as `tools/symbols.sh` counts it | 18 | **18** |
| external symbols | `main` | `main` |
| `#include` | 11 | 11, on the first eleven lines |
| `options[]` / `cmdnames[]` / `nv_cmds[]` rows | 107 / 98 / 194 | 107 / 98 / 194 |
| binary | 788,488 | **788,488 — `cmp`-identical** |
| sweep | | takes nothing, 0 warnings, canon settles in one round |
| phase | | **18 s** |

### Its placement

`stage 23`, `package boundary`. **The package is `boundary` and not `language`**,
although `language` is what this phase and the plain-host-call phase do: the four are one
idea — 23, the two names the language supplies instead of a header; then the two host
calls that become plain ones; then the header types and macros the core can own; then the
move itself — and `language` would have named the first and the second of those while
leaving the other two in a package that did not describe them. **They were numbered 23 to
26 when this was written and they are 23, 25, 26 and 27**: the attributes were asked for
in between and took the number 24, which is `package dialect` and not this idea at all. Its `uses` are `boundary:23 seed:0 mechanical`,
`boundary:23 vendor:14 rationale` and `boundary:23 vendor:15 rationale` for the eleven
vendored signatures above, and `boundary:23 host:21 mechanical` — this edit puts the
typedef directly below the **last** `#include` and asserts eleven directives on the
first eleven lines, and the eleventh and the count are phase 21's, which took
`<stdio.h>` with the seven symbols it freed.

**`need 23 swept` is not required, and it was measured** in the same run that measured
`apart 22 23`. This edit asserts **no count of its input**, so there is no counted anchor
that could shrink silently; what it asserts is structural — eleven directives on the
first eleven lines, `usize` and `nullptr` at zero, the three literals holding `NULL`, and
the partition — and every one of those held on the unswept text phase 22's edit leaves,
giving the same 2,552, 437 and 30. The one number that differs is the blank-line runs it
preserves, 5 on unswept text against 0 on swept, and it **preserves whatever it is
handed** rather than requiring a value.

**`apart 22 23`, measured, and the refusal is a phase that renamed nothing breaking on a
phase that renamed two type names.** `tools/phaserun.sh zero 22-23` on r21 runs both
edits and two sweeps and stops at phase 22's check's **first act** — ``iobuff_room` is
not in the output exactly once, so the controls below would not be controls`. Phase 22
writes its four controls by matching the helpers' text **verbatim**, and two of the three
hold `if (IObuff == NULL)`, which this phase spells `nullptr`. Behind that refusal sit
every other literal text it names: `safelen_result`'s clamp is `((size_t)str_l >= str_m)
? …` and all six declarations it requires are `static size_t …`. **One direction
observed**, because 22's check refuses first; what the run does show is phase 23's edit
applying unchanged to phase 22's unswept output, and its own input binary building to the
same 788,488 bytes.

### What zero-vim is after twenty-three phases

```
zero-vim.c        80,178 lines          from whim-vim.c's 86,614  (-6,436, 7.4%)
functions         1,756
type definitions  905
DWARF enumerators 1,177
cmdnames[] rows   98    (create_cmdidxs floor 80; 18 rows of margin)
nv_cmds[] rows    194   (nvidxcheck: a permutation)
options[] rows    107, 95 distinct globals  (orphanopts floor 80; 15 of margin)
#include          11, on the first eleven lines; no #define, no conditional
libc symbols      17 with zero's flags, 18 as tools/symbols.sh counts
binary            788,488 bytes, EXEC, no INTERP, no dynamic section, no relocation
declared delta    20 records + stderr-moved, from whim-vim
va_start          1, in vim_snprintf
NULL / size_t     3 (all in string literals) / 0
```

**Three phases in a row have declared nothing**, and each is a different kind of nothing:
21 the code runs and the instrument sees it do the same thing; 22 the code runs and the
instrument is nearly blind to it, so 263 probes stand in; 23 **the binary is the same
bytes**, which is the strongest kind this pipeline has — phase 16's, and the reason this
phase was made the smallest of the four rather than the first convenient one.

## Phase 24 — the attributes

`pipes/zero24-edit.sh` and `pipes/zero24-check.sh`, `stage 24`, `package dialect`.
`__attribute__` is a GNU extension, and a core on its way to another runtime was
carrying 139 of them. This phase looks at all 139, in three groups, and takes a
different decision on each:

```
    113   __attribute__((unused))         deleted
     20   __attribute__((fallthrough));   respelled  [[fallthrough]];
      6   format / format_arg             kept
```

139 → 6, **117 lines changed, not one line added or removed**, and not one statement
changed. None of the three kinds emits code — `unused` suppresses a diagnostic,
`fallthrough` gives one a hint, `format` decides what gcc will check — so the binary is
byte-identical, 788,488 bytes either side.

### Why the 113 said nothing, and why upstream needs them

Every dead-code compile in this pipeline is `-Wall -Wextra -Wno-unused-parameter`
(`tools/deadsweep.py`, `tools/phasecheck.sh`), so an unused **parameter** is not
diagnosed whatever is written on it. Upstream carries the marker because upstream
compiles this file in configurations where a parameter is used and others where it is
not; there are no configurations here, and have not been since slim's Phase 5. Measured:
with all 113 gone the sweep's own command line prints nothing at all.

### All 113 were on parameters, computed twice rather than assumed

Every one sits inside a parenthesised group whose innermost enclosing `(` is preceded by
exactly a function name, and the **97 lines** that carry them are all function
*definition* headers, each followed by a line that is `{` — so not one is on a variable,
an object, a type or a field. No parenthesised group in this file spans a line break
(`CLAUDE.md`), so that is a computation on one line and not a parse of C.

The compiler says it a second way. With `-Wunused-parameter` turned back **on**, the
output warns **135** times against the input's **43**, and every one of the 92 new
warnings is `-Wunused-parameter` at a line that carried an attribute — **not one
`-Wunused-variable`**, which is what a deletion that had reached an object would have
produced.

### Twenty-one of the 113 were false, and that is the find of the phase

113 sites, 92 warnings. **The difference is 21 attributes that marked a parameter this
build uses**:

```
    ex_cquit(exarg_T *eap)         reads eap->addr_count on its first line
    check_winopt(winopt_T *wop)    dereferences wop five times
    deathtrap(int sigarg)          compares sigarg against SIGHUP
```

There the attribute was not redundant, it was a **claim the code contradicts** — a
statement some earlier whim or zero phase made untrue, and nothing in either pipeline
checked. So the phase does not delete 113 redundant markers: it deletes 92 unnecessary
ones and **21 wrong statements**, and the check names them rather than letting the
arithmetic swallow them.

### `[[fallthrough]]` is not refused under `-std=c11`, which is an argument against the swap

The swap is one-for-one and textual: all 20 sites were standalone statements on lines of
their own, `[[` occurs **0** times in the input and **20** in the output, and
`-Wimplicit-fallthrough` is silent either side, so not one suppression was lost. It is
not a directive either — C23 attribute syntax is a *statement* in the grammar, spelled
with brackets, and the charter's rule is about preprocessor syntax.

What it costs is stated rather than glossed, and it is **weaker than phase 23's
`typeof`**, which `-std=c11` refuses outright. Measured: gcc accepts `[[fallthrough]]`
under every `-std` it has, as an extension; below C23 `-Wpedantic` says *ISO C does not
support '[[]]' attributes before C23* and **`-pedantic-errors` refuses it** — where the
GNU spelling it replaces is accepted even there, being a reserved identifier. So taken
alone **the swap narrows the dialects this file compiles under**. It costs nothing in
practice, because the file has been C23 by four other routes since before this phase,
and that too is computed rather than argued: `-std=c11` on the whole file gives the
**same 729 errors** before and after.

An honest argument against a change belongs in the phase that makes it, not in the
commit of the phase that has to undo it.

### Two of the twenty are already redundant, and are named rather than pruned

Lines 11480 and 20181, after `case ESC:` and `case Ctrl_P:`: each follows a case label
with **no statement at all**, where C falls through silently and gcc has nothing to
diagnose. They are computed from the structure and required to agree with the control's
count — two independent methods for one number — and then **kept**. What makes a
fallthrough deliberate is the author saying so, not the compiler currently asking, and a
phase that quietly drops what it noticed was unnecessary is how a real suppression goes
missing later.

### The evidence splits in two, and the phase says so

For the **133** that go or change spelling, the binary is the evidence: `cmp`-identical,
which is `CLAUDE.md`'s tier 1 and subsumes every screen case, every Ex-command row,
every command line and every pty scenario at once, because the program that would be run
is the same program.

For the **6** that stay, **the binary is blind** — measured, removing all six as well
leaves it *still* `cmp`-identical while `-Wformat=2` goes from **115**
`-Wformat-nonliteral` warnings to **zero**. So the warnings are their evidence, and the
form is phase 22's invariant reused verbatim: the identical 115 warnings in the
identical **53** functions before and after, compared as list equality, with two controls
that break it in opposite directions — `vim_snprintf`'s `format(printf, 3, 4)` removed
gives **0**, and `_()`'s `format_arg(1)` removed gives **135**, gcc having lost its way
through the translation wrapper.

That is what the six are for. Phase 22 expanded seven wrappers into 129 direct calls, so
**one attribute now type-checks 201 `vim_snprintf` mentions**, and `format_arg` on `_()`
and `NGETTEXT` is why `CLAUDE.md` records that those two were never macro-expanded. The
rule the phase applies is therefore not *remove GNU extensions* but **remove every
attribute whose job another flag already does, and keep every attribute that IS the
flag**.

### Four controls, and one of them is the one that makes `cmp` mean something

c1 and c2 are the two above. c3 blanks all 20 `[[fallthrough]];` and gets **18** warnings
where there were none — which is also how the two redundant sites are confirmed from the
other end. c4 replaces **one** of them by `break;` — the smallest change at those sites
that is a change to the *program* rather than to a diagnostic — and moves **512,594
bytes** of binary. Without c4 the byte-identical binary is two numbers agreeing.

### One fact about the tools, which is why the check is seconds and not minutes

`CLAUDE.md` records that `-fsyntax-only` does not report `-Wunused-function`. It does not
report **`-Wimplicit-fallthrough`** either, which needs the CFG — measured, the c3
control warns 18 times under `-c` and **zero** times under `-fsyntax-only`. A fallthrough
section written with it would have passed while checking nothing. It *does* report
`-Wunused-parameter` and `-Wformat-nonliteral`, which is what the other sections use.

### The trap was the whitespace, not the attribute

Each attribute was written with **two** spaces before it and **one** after, so deleting
the text alone leaves a doubled space or a space before a paren — and `tools/canon.sh`
does not fix either. The check measures it: the count of doubled spaces before a `,` or
a `)` is **639 either side**, and canon is a no-op on the output.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 80,178 | **80,178** — 117 lines changed, none added, none removed |
| bytes | 2,139,325 | **2,136,127** |
| `__attribute__` | 139 | **6** — three `format`, three `format_arg` |
| `__attribute__((unused))` | 113 | **0** — on 97 definition headers, 21 of them false |
| `__attribute__((fallthrough))` | 20 | **0** |
| `[[fallthrough]]` | 0 | **20** |
| `-Wunused-parameter` when asked for | 43 | **135** — 92 new, not one `-Wunused-variable` |
| `-Wformat-nonliteral` under `-Wformat=2` | 115 in 53 functions | **115 in the same 53** |
| `-std=c11` errors on the whole file | 729 | **729** |
| functions / type definitions / DWARF enumerators | 1,756 / 905 / 1,177 | 1,756 / 905 / 1,177 |
| `nm -u` with zero's own flags | 17 | **17, the same set**, a `comm` empty both ways |
| external symbols | `main` | `main` |
| `#include` | 11 | 11, on the first eleven lines |
| `options[]` / `cmdnames[]` / `nv_cmds[]` rows | 107 / 98 / 194 | 107 / 98 / 194 |
| binary | 788,488 | **788,488 — `cmp`-identical** |
| sweep | | takes nothing, canon a no-op |
| phase | | **22 s** |

### Its placement

`stage 24`, and **a package of its own, `dialect`**, which is the one placement decision
here. The boundary is where the line between core and host falls, and this phase moves
no line: it asks which dialect of C the core is written in and which of its extensions
are still being paid for. `boundary` would have made the package mean two things.
Its `uses` are `dialect:24 seed:0 mechanical`; `dialect:24 tidy:13 rationale`, because
phase 13 dropped `ui_write()`'s `console` parameter rather than leaving
`__attribute__((unused))` on it and said so in as many words — that was this phase's
judgement one phase at a time; `dialect:24 format:22 mechanical`, phase 22's 129 direct
calls being why one `format` attribute now carries 201 mentions; and
`dialect:24 boundary:23 mechanical`, the `%d` probe being built from the output's own
lines — `vim_snprintf`'s prototype and the `typedef typeof(sizeof(0)) usize;` it needs to
compile — both of which read `usize` because of phase 23.

**`apart 23 24` and `need 24` are both measured NOT to be required**, in one run:
`tools/phaserun.sh zero 23-24` on r22 runs both edits, one sweep and both checks, and
every part passes. This phase touches no `NULL`, no `size_t` and none of the helpers
phase 23's controls quote, and phase 23 neither creates nor destroys an attribute; the
edit asserts no count of its input that a sweep could move, what it asserts being a
partition and a shape.

**This phase renumbered the three that follow it, and this document had the old numbers
until now.** `ZERO-PLAN.md` §4c's reorganisation steps 24, 25 and 26 are phases 25, 26
and 27, which `pipes/zero.stages` states; *Phase 23 — `nullptr` and `usize`* above said
*"26, the move itself"* and has been corrected to say 27. The phase *programs* are
deliberately **not** corrected — `pipes/zero23-*.sh` still says "phase 26" where it means
the move — because every byte of a phase program is in its unit's implementation digest,
and a comment fixed there re-keys a boundary to change nothing.

### What zero-vim is after twenty-four phases

```
zero-vim.c        80,178 lines          from whim-vim.c's 86,614  (-6,436, 7.4%)
functions         1,756
type definitions  905
DWARF enumerators 1,177
GNU attributes    6, all format or format_arg
cmdnames[] rows   98    (create_cmdidxs floor 80; 18 rows of margin)
nv_cmds[] rows    194   (nvidxcheck: a permutation)
options[] rows    107, 95 distinct globals  (orphanopts floor 80; 15 of margin)
#include          11, on the first eleven lines; no #define, no conditional
libc symbols      17 with zero's flags, 18 as tools/symbols.sh counts
binary            788,488 bytes, EXEC, no INTERP, no dynamic section, no relocation
declared delta    nothing since phase 11 -- 2 stderr-moved and the records of 4 to 11
```

**Four phases in a row have now declared nothing**, and 23 and 24 are the same kind: the
binary is the same bytes. The difference between them is what that kind can and cannot
carry. Phase 23's whole content was inside the `cmp`; a sixth of this phase's — the six
attributes it keeps — is outside it, and the phase had to go and get a second instrument
for that part rather than let the strongest evidence it had cover a decision the evidence
cannot see.

## Phase 25 — the plain host calls

`pipes/zero25-edit.sh` and `pipes/zero25-check.sh`, `stage 25`, `package boundary`.
The core reached the host through two function pointers:

```c
    static void (*vim_host_exit)(int);                          phase 19's, one call site
    static void (*vim_host_message)(const char *, int, int);    phase 21's, eight
```

each a file-scope object installed through a parameter of `vim_main()` that `main()`
passed. This phase makes both of them ordinary calls to `static` functions declared
above and defined below. **Two objects, two parameters, two assignments and two
arguments go; two prototypes arrive**, and `vim_main(int argc, char **argv)` is exactly
the signature phase 18 wrote when it demoted `main()`. 80,178 → 80,173 lines.

### The indirection had one reason, and the design changed underneath it

`pipes/zero19-edit.sh` states it in as many words: *a pointer the launcher installs
through a parameter adds no external symbol, where a `musl_exit(int)` the host defines
would.* The invariant it was protecting is `nm --extern-only --defined-only` printing
exactly `main`, and under **two translation units** the sentence is true — the host's
definition of a function the core calls has external linkage by construction.

`ZERO-PLAN.md` §4c is now one file with two parts and the first `#include` as the
boundary, so the host's definitions sit below the core in the **same** translation unit.
A `static` forward declaration above and a `static` definition below is all a direct call
needs, and the global the indirection existed to avoid does not appear at all. The
machinery outlived its argument by six phases, which is the ordinary way a design change
leaves debris.

### The control that matters is the one that would have passed unnoticed

This is the phase that makes the core **name** the host's two functions, so
`nm --extern-only --defined-only` is the assertion it could have broken, and both halves
of the `static` trap are built on the phase's own output:

```
    static off the two PROTOTYPES                gcc refuses --
                                                 "static declaration of 'host_exit'
                                                  follows non-static declaration"
    static off the prototypes AND the            the build is SILENT and the object
    definitions                                  defines host_exit, host_message, main
```

The second is the mistake nothing else here would have caught: it compiles, it links, it
runs, every recording matches, and the core has quietly acquired two external symbols.
The check runs it every time. A third control deletes the two prototype lines and
requires the file **not** to compile, which is what makes *load-bearing* a measurement
rather than a description.

Each prototype is built out of its definition's own lines rather than retyped, so the two
cannot disagree. Measured on the output: `host_exit` declared at line 3533, called at
55872, defined at 80137; `host_message` declared at 3534, called at eight sites from
37649 to 79847, defined at 80144 — declared above every use and defined below every one,
which is the shape that keeps the declaration serving when a later phase moves the
definitions further down. It did: phase 27 moved them, and these two lines did not change.

### The evidence is the recording, because the binary moves

788,488 bytes either side and **347,279 of them differing**. An indirect call through a
pointer loads the pointer and calls a register where a direct call is relative to a known
address, and removing two file-scope objects moves what follows them; at `-O0` that is
simply different code. So this phase cannot use tier 1, does not pretend to, and falls
back on what every zero phase before 23 used: **two full recordings, `diff -r` empty
across all 106 records** — the 102 screen cases, every Ex command typed at `:`, every
command line the parser may see, the four pty scenarios and the terminal table.

And it can fail, **once for each name the phase makes direct**, which is what keeps an
empty `diff -r` from being a harness that recorded nothing. `host_exit`'s own
`host_code = r;` changed to `r + 1` moves **105 of the 106** records — every one but the
terminal table, which records no exit status. `host_message`'s `write(err ? 2 : 1, …)`
with the two streams swapped moves **`ref-argv.txt` and nothing else**, which is phase
21's own finding read back: everything reaching that function is a message printed before
there is a screen.

### The two prototypes join phase 20's nine, and that is the point of doing it here

The core → host boundary is now **one block of eleven declarations** rather than nine in
a block and two wherever an object happened to sit. `tools/zhostonly.py` — phase 20's
structural check — is run rather than assumed: its vocabulary is libc's terminal, signal
and descriptor names, `host_exit` and `host_message` are not in it, and it passes
unchanged at 60 mentions of 43 words, all inside the host block, with the same seven
named exceptions.

### It answers phase 22's open question rather than leaving it

Phase 22's survey flagged that 20 of its 129 new call sites sat inside the functions a
**split** would have moved, so host code would be calling back into the core's `emsg()`
and reading the core's `IObuff` — a genuine boundary question with three unattractive
answers. Under one file there is no question, and the measurement is here rather than in
a note somebody has to find: the four functions that still hold a `va_list` —
`vim_snprintf`, `vim_vsnprintf`, `vim_vsnprintf_typval` and `skip_to_arg` — call
**twenty distinct core functions at forty-one sites** and read `IObuff` once, and not one
of those costs a declaration. **Everything above the cut is visible below it**; only the
core → host direction ever needs a name declared, which is why this phase costs two
prototypes and not four.

### The declared delta is nothing at all, and it is phase 21's kind

The code runs, the instrument sees it, and it does the same thing. Not a `cmp` — that
kind belongs to 16, 23 and 24 — and not a blindness either: the recording is shown able
to see both names change.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 80,178 | **80,173 (−5)** |
| `vim_host_exit` / `vim_host_message` | 3 / 10 | **0 / 0** |
| `host_exit` / `host_message` | 2 / 2 | **3 / 10** |
| `exit_fn` / `message_fn` | 2 / 2 | **0 / 0** |
| `vim_main`'s signature | four parameters | `(int argc, char **argv)` — phase 18's, back again |
| core → host prototypes | 9 | **11**, one block |
| functions / type definitions / DWARF enumerators | 1,756 / 905 / 1,177 | 1,756 / 905 / 1,177 |
| `nm -u` with zero's own flags | 17 | **17, the same set**, a `comm` empty both ways |
| external symbols | `main` | **`main`**, with both halves of the trap built |
| `#include` | 11 | 11, on the first eleven lines |
| `options[]` / `cmdnames[]` / `nv_cmds[]` rows | 107 / 98 / 194 | 107 / 98 / 194 |
| binary | 788,488 | **788,488 bytes, 347,279 of them differing** |
| records that moved | | **0 of 106** |
| sweep | | takes nothing, one round, canon a no-op |
| phase | | **25 s** |

### Its placement

`stage 25`, `package boundary` with 23, 26 and 27 — it writes no C23 and removes no GNU
extension, so `dialect` would be wrong; what it changes is how the core names what is on
the other side of the line. Its `uses` are `boundary:25 seed:0 mechanical`;
`boundary:25 harness:3 mechanical`, its evidence being a recording and not a `cmp`;
`boundary:25 host:18 rationale`, the signature it gives back being the one phase 18
wrote; `boundary:25 host:19 mechanical`, for the pointer, the parameter, the assignment
and the reason they were a pointer — and for the launcher it must leave untouched, `exit`
staying out of `nm -u` because `host_exit()` still records a status and jumps; and
`boundary:25 host:20 mechanical` and `boundary:25 host:21 mechanical` for the block the
two prototypes join and the eight call sites and the control that reads back phase 21's
finding.

**`apart 24 25` is measured, and its first complaint is one nobody would predict.**
`tools/phaserun.sh zero 24-25` on r23 stops inside **phase 24's** check with *"a line
carrying a kept attribute is not the line it was, byte for byte: lines 847 852 3081
3092"* — phase 24 records the six `format`/`format_arg` lines it keeps **by line
number**, and this phase deletes the `vim_host_message` object with its blank line at
495, so everything below moves up by two. A check that pins a line number is a dependency
on every line above it, exactly as a check that quotes C is a dependency on spelling
(`apart 22 23`). One direction only, measured: phase 25's check passes on the tree that
stage leaves.

**`need 25 swept` is measured NOT to be required**: this edit applies unchanged to the
unswept text phase 24's edit leaves, giving the same 80,178 → 80,173 and the same line
numbers.

### What zero-vim is after twenty-five phases

```
zero-vim.c        80,173 lines          from whim-vim.c's 86,614  (-6,441, 7.4%)
functions         1,756
type definitions  905
DWARF enumerators 1,177
core -> host      11 prototypes in one block; no function pointer left between them
#include          11, on the first eleven lines; no #define, no conditional
libc symbols      17 with zero's flags, 18 as tools/symbols.sh counts
binary            788,488 bytes, EXEC, no INTERP, no dynamic section, no relocation
declared delta    nothing since phase 11 -- 2 stderr-moved and the records of 4 to 11
```

**The product was not in this phase's branch.** `zero-vim.c` landed in a commit of its
own after the merge, as phase 26's did, where phases 24 and 27 carried theirs in the
branch. Nothing was lost — the file is r25's boundary either way, and `make zero-verify`
reproduces it — but a merge whose diff holds the programs and not the thing they produce
is easy to read as a phase that changed no source, and it is worth knowing that two of
these four look like that in `git log`.

## Phase 26 — the header types and macros the core can own

`pipes/zero26-edit.sh` and `pipes/zero26-check.sh`, `stage 26`, `package boundary`.
Eight things the core took from a header stop coming from one:

```
    time_t          →  typedef long time_T;  plus  long time(long *tp);
    sig_atomic_t    →  volatile int                       2 in the core; the host's 3 stay
    uintptr_t       →  usize                              1 site
    struct timeval  →  a TAGLESS struct of two longs, and musl_gettimeofday(long *, long *)
    MIN / MAX       →  the text the preprocessor gives, at 19 lines
    offsetof        →  __builtin_offsetof                 9 sites
```

and the nine libc functions the core still calls — `malloc realloc free time getpid kill
write labs abs` — get plain prototypes, none of them `static`. 80,173 → 80,197 lines,
exactly the 24 the edit adds.

### It comes BEFORE the move, and the ordering is the whole of its evidence

Every declaration here replaces something a header **still supplies from above it**, so
the ordinary build cross-checks each one for free. After the move there is nothing left
to check against, and the check that can be written then is only *it compiles*.

**Sixteen `static_assert`s**, all silent, compare every core-owned spelling against the
header type it replaces:

```c
    sizeof(elapsed_T) == sizeof(struct timeval)              and both offsets, both widths
    _Generic((usize)0,  uintptr_t: 1, default: 0)            and again against size_t
    _Generic((time_T)0, time_t:    1, default: 0)
    _Generic((int)0,    sig_atomic_t: 1, default: 0)
    _Generic(time, long (*)(long *): 1, default: 0)
    __builtin_offsetof(T, m) == offsetof(T, m)               at all six types the 9 sites use
```

Every one of them **names a header type**, so not one can be written once phase 27 moves
the includes below. They are a control in the check and never in the product, and a
seventeenth with one comparison deliberately wrong must fail — so they are compiled and
not merely present.

**Four deliberately wrong declarations give four diagnostics**, which is the same
argument from the other side: `int time(int *tp);`, `void *malloc(int n);` and
`long getpid(void);` are each `conflicting types`, and `static void *malloc(usize n);` —
the trap the survey names — is `error: static declaration of 'malloc' follows non-static
declaration`. After the move the first three become **nothing at all** and the fourth
changes shape entirely. One more argument for doing this first, and phase 27 measured
where the fourth went.

### Six of the seven changes are tier 1, and the check says so as an equality

Six of them are a rename or an expansion the preprocessor was already performing, so
none can generate a different instruction. That is stated rather than claimed: **with the
clock ALONE reverted, the binary is `cmp`-identical** to the 788,488-byte one the phase
was handed. So `time_T`, `volatile int`, `usize`, the 23 `MIN`/`MAX` expansions,
`__builtin_offsetof` and the nine prototypes are `CLAUDE.md`'s tier 1 — literally the
same program — and only the clock has anything to answer for.

**The seventh is the clock, and it is the only libc *type* the core could not rename
away.** `struct timeval` is a **layout**, so `elapsed_T` becomes the core's own tagless
`struct { long tv_sec; long tv_usec; }` and the five `gettimeofday(&X, nullptr)` calls go
through a new `musl_gettimeofday(long *, long *)` in the host block. That is a call and
two stores where there was a syscall wrapper, so the binary moves, and **two full
recordings, `diff -r` empty across all 106 records**, are what answers for it.

The recording is not blind to it: `musl_gettimeofday` writing its two fields the wrong
way round moves **six of the 102 screen cases** — `key_Q`, `key_gQ`, `key_gf`, `macro_q`,
`reg_percent` and `ruler_move`.

### `MIN` and `MAX` are read from the header, not written into the program

The edit sends `MIN(ZZA,ZZB)` and `MAX(ZZA,ZZB)` through the preprocessor with
`<sys/param.h>` included and turns what comes back — `(((ZZA)<(ZZB))?(ZZA):(ZZB))` —
into its template. That is the only honest meaning of *the exact text the header gives*,
and the check re-derives the same two shapes and requires 7 more `MIN` expansions and 16
more `MAX` ones, with the repeated argument really repeated. **Two of the 19 lines pass a
call as an argument and so evaluate it twice** — exactly as the macro did, which is what
the `cmp` proves and what writing `<` by hand would have quietly fixed into a different
program.

### Two corrections to the brief, both measured, and both make the rule stronger

**A core-defined `struct timeval` tag is NOT a hard error.** The brief says it is
`error: redefinition`. Measured: **C23 permits a struct to be redeclared with the same
members**, so gcc 15's default dialect is *silent* both ways round, and only `-std=c11`
and `-std=c17` refuse it. The tagless struct is still mandatory, for a better reason than
a diagnostic — **the core must not define a libc tag at all**, and the layout equality
has to be **asserted**, which is what three of the sixteen `static_assert`s do. A rule
that rests on a diagnostic the standard has since removed is a rule with a shelf life.

**There is no `musl_time`.** The brief has the core calling its own
`long musl_time(long *)`. `time` keeps its name, so that `long time(long *tp);` sits
above `<time.h>`'s own declaration of the same function and gcc compares the two, where
a wrapper would have cast any mismatch away at its own boundary.

**AND WHAT THAT PROTOTYPE PINNED IS NOT WHAT THIS SECTION SAID IT WAS.** It read
*"precisely what pins `time_T`'s width"*, and so does this phase's commit; **phase 32
measured it and both are wrong**. The prototype pinned `long == time_t` — real, and
phase 32's `m1` compile re-ran this phase's own control to confirm it, `int time(int
*tp);` giving `conflicting types for 'time'`. Nothing in it ever mentioned `time_T`, and
phase 32's `m2` is the proof: **this phase's output with `typedef long time_T;` changed
to `int` and the prototype left untouched compiles in SILENCE.** What checked
`time_T == time_t` here was `_Generic((time_T)0, time_t: 1, default: 0)`, one of the
sixteen `static_assert`s above — a **control in the check**, never in the product —
which is exactly why phase 32 had to
put `static_assert(_Generic((time_T)0, time_t: 1, default: 0), "time_T is time_t");`
into `zero-vim.c` when it took the prototype away.

### The tool changed, and that is the tool working

`tools/zhostonly.py` refused, as predicted — its two `struct timeval` exceptions read
*"the clock's, and not this phase's … somebody else's later phase"*, and this is that
phase; `kill` acquires one for the core's own prototype. But a swapped exception list was
not enough. The tool runs in the checks of phases **20, 21, 25 and 26, each on its own
output**, and the core's vocabulary shrinks between them — so an exception's count is now
the **tuple of values it takes**, each written with the phase that made it true. What it
refuses is still a count nobody has written down, so *an exception that stops being true
is a fact this tool is meant to notice* holds, and the phase that ends one comes here and
says so. Measured with `tools/implhash.sh`: 107 whim and slim keys identical either side,
six zero keys move — the units and edits whose programs name the tool.

### A control can be right and still be a bad check

The must-differ control — `musl_gettimeofday` writing its two fields the wrong way round
— **stalls `tools/zpty.py`**. An editor whose clock runs backwards has timeouts that
never expire, so the harness waits out its deadline, writes `stalled` and exits 1 two
minutes later, which is correct behaviour on a deliberately broken binary and a flaky
check. The control is `zcases.py` alone for that reason. **A check should not depend on
how long a harness takes to give up.**

### The declared delta is nothing at all, and it is a sixth kind

Not code that could not run (9, 17), not code the instrument cannot see (12), not a
possibility removed (13), not a `cmp` of the binary (16, 23, 24), and not phase 25's *the
code runs and the instrument sees it do the same thing* either. It is **six of seven
changes that are a `cmp` and one that is a recording**, and the phase separates them
rather than taking the weaker evidence for all of it.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 80,173 | **80,197 (+24)** |
| `time_t` / `time_T` | 6 / 5 | **0 / 10** |
| `sig_atomic_t` | 5 | **3**, all three the host block's |
| `uintptr_t` | 1 | **0** |
| `offsetof` / `__builtin_offsetof` | 9 / 0 | **0 / 9** |
| `MIN(` + `MAX(` | 7 + 16, on 19 lines | **0**, expanded in place |
| `struct timeval` | 6 — 4 core, 2 host | **3**, all host |
| `gettimeofday` | 5 | **1**, inside `musl_gettimeofday` |
| libc prototypes in the core | 0 | **9**, none `static` |
| functions | 1,756 | **1,757** (`musl_gettimeofday`) |
| type definitions / DWARF enumerators | 905 / 1,177 | 905 / 1,177 |
| `nm -u` with zero's own flags | 17 | **17, the same set**, a `comm` empty both ways |
| external symbols | `main` | `main` |
| `#include` | 11 | 11, on the first eleven lines |
| `options[]` / `cmdnames[]` / `nv_cmds[]` rows | 107 / 98 / 194 | 107 / 98 / 194 |
| binary | 788,488 | **788,488** — and `cmp`-identical with the clock alone reverted |
| records that moved | | **0 of 106**; the wrong-way-round clock moves 6 of 102 cases |
| sweep | | takes nothing, canon a no-op |
| phase | | **27 s** |

### Its placement

`stage 26`, `package boundary` beside 23, 25 and 27. Its `uses` are
`boundary:26 seed:0 mechanical` and `boundary:26 harness:3 mechanical` for the recording;
`boundary:26 host:20 mechanical`, because `musl_gettimeofday` is **defined inside the
host block phase 20 created**, immediately above `musl_delay` — `tools/zhostonly.py`
reads the host region as the lines from `host_winch_pending` to `musl_suspend`'s last
brace, so a definition below `musl_suspend` would put a `struct timeval` outside it and
the tool would refuse; and `boundary:26 host:19 rationale`, because the two
`sig_atomic_t` this phase respells are the core's and the three it leaves alone are the
host block's — the split that makes that sentence meaningful is the launcher phases 18
and 19 put at the bottom of the file.

**`apart 25 26` is measured, not predicted.** `tools/phaserun.sh zero 25-26` on r24 runs
both edits, one sweep and then **phase 25's** check, which stops at *"the file is 80197
lines and the input was 80178 (80178 recorded) — expected exactly five fewer"*: this
phase adds twenty-four lines to the text before that check reads it. **`need 26 swept` is
measured NOT to be required**, in the same run — both edits came from the edit cache,
which is keyed on the digest of the tree each is handed, and a direct `cmp` confirms it:
phase 25's edit applied to r24 gives a `zero-vim.c` byte-identical to r25's, so the sweep
between them is a complete no-op.

### What zero-vim is after twenty-six phases

```
zero-vim.c        80,197 lines          from whim-vim.c's 86,614  (-6,417, 7.4%)
functions         1,757
type definitions  905
DWARF enumerators 1,177
header names left above the host block   the twelve *_MAX, PATH_MAX, EXIT_FAILURE,
                                         SIGHUP and SIGTERM -- and nothing else
#include          11, on the first eleven lines; no #define, no conditional
libc symbols      17 with zero's flags, 18 as tools/symbols.sh counts
binary            788,488 bytes, EXEC, no INTERP, no dynamic section, no relocation
declared delta    nothing since phase 11 -- 2 stderr-moved and the records of 4 to 11
```

**Recorded as a follow-up rather than done here.** Every core use of the clock is *stamp
now, then ask how many milliseconds have passed*: `elapsed()` is one `gettimeofday` and a
subtraction, and its four callers all compare the result against a millisecond count. So
the core never needs the **layout**, only a scalar, and a `long musl_now_ms(void)` would
take `struct timeval`, `gettimeofday` and the tagless-struct question out of the core
together. The tagless struct is an interim shape, kept because it is what was surveyed
and what the evidence above was measured against; the scalar clock is a phase of its own,
if it is asked for.

**Its product landed separately too**, like phase 25's: the branch and the merge hold the
programs, and `zero-vim.c` came in the commit after.

## Phase 27 — the move: the first `#include` becomes the boundary

`pipes/zero27-edit.sh` and `pipes/zero27-check.sh`, `stage 27`, `package boundary`.
This is what the pipeline had been clearing the ground for. **The eleven `#include`s
move from the first eleven lines to line 78,360, and above them there is not one
preprocessor directive.** `zero-vim.c` is now one translation unit with a core editor on
top, written in plain C with no directives at all, and a host below that begins with the
includes. **The first `#include` IS the boundary**, marked by nothing else — no comment,
no banner, no name — and `make editor.c` writes the **78,358 lines** above it.

That target existed before this phase, writing an empty file on purpose, so that the
phase that fills it would change the source and not the makefile. It did.

### The order was forced, and it is why 26 and 27 are two phases

```c
    enum : int { INT_MAX = (int)(~0u >> 1) };       placed AFTER <limits.h> is
    enum : int { 0x7fffffff = (int)(~0u >> 1) };    a syntax error
```

So the derived constants can only be written **once the includes have moved**, and phase
26's sixteen `static_assert`s against the headers can only be written **while they are
still above**. Two phases, in that order, and neither could have held the other's work.
The check proves the first half on the product rather than arguing it: with `<limits.h>`
put back at line 1 the build stops on that line with *expected identifier before numeric
constant*.

### The constants are asked for, not remembered

The edit performs the move, compiles the cut alone, and **collects every name gcc says is
undeclared: 23 errors naming exactly twelve**. A thirteenth would mean phase 26 did not
finish; one this program declared and gcc did not ask for would be a declaration nobody
needs. Eight are derived from the type system and four asserted:

```
    INT_MAX 14   INT_MIN 2   LONG_MAX 51   LONG_MIN 1        derived: (int)(~0u >> 1) and kin
    LLONG_MAX 3  LLONG_MIN 1 ULLONG_MAX 10 SIZE_MAX 1
    PATH_MAX 12  EXIT_FAILURE 1  SIGHUP 2  SIGTERM 2         asserted against the header below
```

(the counts are the core's mentions at r26). **All twelve are enumerators**, including
the four asserted ones, because `PATH_MAX` is an **array bound** — and a `static const
int` cannot appear in an array bound, a case label or an enumerator initialiser
(`CLAUDE.md`, *Add a constant*).

Re-measured from the product: delete the twenty enumerator lines from `editor.c` and gcc
gives the same **23 errors over exactly those twelve names**, `INT_MAX` eight times,
`PATH_MAX` five and the other ten once each.

### Below the includes, `INT_MAX` IS the macro, so each assert restates the derivation

This is the design point the brief could not have foreseen, and it is what the move costs.
Phase 26 could compare every core-owned spelling against the header still above it. Here
the headers are **below**, and below them the name `INT_MAX` is `<limits.h>`'s macro — so

```c
    static_assert(INT_MAX == INT_MAX, "INT_MAX");        a tautology about the header
    static_assert((int)(~0u >> 1) == INT_MAX, "INT_MAX");  what the phase writes
```

The twelve asserts the phase puts **into the product** compare the **deriving
expression** against the header, and the left-hand side is not typed twice: it is emitted
from the same table as the enumerator's own initialiser, and the check reads both back
out of the source and requires them equal as text. Measured both ways — the wrong
derivation in both places is `static assertion failed`, and **the same wrong enumerator
with the assert written the naive way builds in silence**.

### What moves below is computed to a fixpoint, not listed

The four functions that hold a `va_list` are named, because `va_list` is `<stdarg.h>`'s
and the core cannot declare it: `vim_snprintf`, `vim_vsnprintf`, `vim_vsnprintf_typval`
and `skip_to_arg` — the fourth being the one `ZERO-PLAN.md` §4c missed and phase 22
counted. **Everything else follows from compiling the cut**: move what gcc calls unused,
compile again, repeat.

The brief's single round is only the first of **five**. The fixpoint takes **15
functions, 18 objects and 3 enum blocks** — the formatter's whole private island, down to
`musl_strchr`, `format_typeof` and the eleven `typename_*` strings — where one round
takes seven things. The stopping rule is `vim_main` and `deathtrap`, the two the **host**
calls, which are unused above the cut by construction and stay there. Enum blocks are
found by **counting**, not by compiling: no warning gcc has can see a dead enumerator
(`CLAUDE.md`).

That is **78,358 lines** in the cut where one round gives 79,079, and it is the right
answer because **the cut is the deliverable**: shipping 15 dead functions inside it would
be a defect, and *nothing above the boundary is dead* is now a checkable sentence.
Measured on the product, the moved island is lines 78,385–79,952 — **1,568 lines** — and
1,874 lines sit below the cut in all, of which the 280-line host block was already at the
bottom and did not move.

### There is no `cmp` to be had, so tier 1 moved up a level, onto the source

Every address below the first moved definition moves with it, so the binary cannot be the
evidence and the phase does not pretend otherwise. What replaces it is `CLAUDE.md`'s tier
1 **one level up**, stated and checked as a **multiset**:

> not one of the input's 80,197 lines is missing from the output, and the only lines the
> output adds are the **32** this phase writes — twenty enumerator lines and twelve
> `static_assert`s — plus three blanks where an emptied paragraph left two.

**A phase that moved code and altered a character of it on the way could not say that.**
Re-measured independently by sorting both files: 0 lines missing, 35 added, and the 35
are exactly the 32 and three blanks. 80,197 → 80,232 lines.

The recording answers for the thirty-two: two full recordings, of the binary the phase
was handed and of its own, **byte-identical across all 106 records**. `nm -u` is the same
17 names in both directions — **moving a definition inside ONE translation unit frees
nothing and needs nothing**, because a symbol leaves when its last caller leaves the
*file* — and `nm --extern-only --defined-only` is still exactly `main`. The claim of this
phase is structural and not a symbol count.

### The cut's own check is four parts, and three of them are silent in an ordinary build

`awk '/^ *# *include / { exit }'` — one clause, no judgement — gives the prefix, and then:

```
    0 lines beginning with #                 a #define above the cut gives 1
    a floor of 70,000 lines                  an #include back at line 1 gives a cut of 0
    0 errors under -fsyntax-only
    a warning set EQUAL to the declared boundary
```

The fourth is the interesting one. The cut's warnings **are** the core → host interface:
**thirteen names, every one `used but never defined`** — `vim_snprintf`, `host_exit`,
`host_message` and the ten `musl_*` — computed a second way from the text, as the names
defined below the cut and mentioned above it, and required to match. Verified here
independently: 0 errors, 13 warnings, and the cut an exact byte prefix of `zero-vim.c`.

Each of the three mistakes is built both ways in the check, and **each is silent in the
ordinary build**: a `#define` above the cut, an `#include` back at line 1, and one core
function — `elapsed` — quietly moved below the boundary, which changes the thirteen by
exactly its name. Nothing else in this pipeline can see any of them.

### Two corrections, and one of them was in the makefile

**The brief's `static` trap is wrong.** It says a `static` libc prototype above the
boundary makes the link fail. It does not: gcc gives `<stdlib.h>`'s own declaration
internal linkage too, warns on **that** line — *'malloc' declared 'static' but never
defined* — links against libc regardless, and produces a binary `cmp`-identical to the
product's. So the trap phase 26 caught with a hard error is now a warning, and what
stands between the core and it is the sweep's rule that the build print **nothing**, plus
this check's assertion that none of the nine prototypes is `static`.

**And `zero.mk`'s `editor.c` guard was wrong, in a way it could only be once the cut was
not empty.** It refused if the cut held a `#` of **any** kind — but `#` is an ordinary
character, and the editor is full of it:

```c
    enum { CPO_HASH = '#' };
    if (ptr[0] == '#')
    "E1281: Atom '\%%#=%c' must be at the start of the pattern"
    the two latin1 case tables
```

Measured on the first cut this rule ever produced, **63 lines** hold one and none is a
directive — so the guard would have refused every valid cut for ever. It is `^ *#` now,
which is what the rule's own paragraph already said it meant, and it is 0 on the cut and
11 on the whole file. The agent was told not to touch that file and changed it anyway,
with the measurement and a flag saying so, which was the right call. **The phase's merge
commit says 54 lines and the tree says 63**; 63 is the number `zero.mk` and the phase
commit carry, and the number reproduced here.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 80,197 | **80,232 (+35)** — 32 written, 3 blanks |
| input lines missing from the output | | **0**, as a multiset |
| first `#include` | line 1 | **line 78,360** |
| directives above the first `#include` | 11 | **0** |
| `make editor.c` | an empty file | **78,358 lines**, 0 directives, 0 errors, 13 warnings |
| moved below | | 4 va_list functions + 15 functions, 18 objects, 3 enum blocks, 5 rounds |
| the island's extent | | lines 78,385–79,952, **1,568 lines** |
| constants written above | 0 | **12 enumerators**, 8 derived and 4 asserted |
| `static_assert` in the product | 1 | **13** — the `cmdnames[]` one and this phase's twelve |
| functions | 1,757 | 1,757 |
| type definitions | 905 | **909** |
| DWARF enumerators | 1,177 | **1,189 (+12)** |
| `nm -u` with zero's own flags | 17 | **17, the same set**, a `comm` empty both ways |
| external symbols | `main` | `main` |
| `options[]` / `cmdnames[]` / `nv_cmds[]` rows | 107 / 98 / 194 | 107 / 98 / 194 |
| binary | 788,488 | **788,488 bytes, and not the same bytes** |
| records that moved | | **0 of 106** |
| sweep | | takes nothing, canon a no-op |
| phase | | **64 s**, the longest any zero phase has taken |

### Its placement

`stage 27`, `package boundary`, the last of the four. Its `uses` are
`boundary:27 seed:0 mechanical` and `boundary:27 harness:3 mechanical`, the evidence
being a recording; `boundary:27 format:22 mechanical`, because what moves below is **four**
functions and not eleven only because phase 22 collapsed the seven `va_list` wrappers into
their call sites; `boundary:27 host:20 mechanical`, the includes landing immediately above
`host_winch_pending`, the first line of the block phase 20 created and where
`tools/zhostonly.py` starts reading; and `boundary:27 host:21 mechanical`, the eleven
directives on the first eleven lines being what phase 21 left, which this edit asserts
before lifting the block.

`tools/zhostonly.py` gained two named exceptions here and nothing else:
`<file scope>` now says `SIGHUP` and `SIGTERM` twice each — the core's own
`enum { SIGHUP = 1 };` and the `static_assert` below the includes that checks it — both
outside the host region because that region begins at `host_winch_pending` and the
includes are above it. Measured: the tool passes on the phase's input and on its output,
and the edit moves **four zero unit keys (20, 21, 25, 26**, the phases whose checks name
it**) and no whim, whim edit or slim key at all**.

**`apart 26 27` is measured, not predicted**, by running phase 26's check on the tree
phase 27 leaves: it stops with *"the output is 80232 lines and the input was 80173, a
difference of 59 where 24 was expected"* and *"the output does not have exactly eleven
directives on its first eleven lines"* — and behind those, its sixteen `static_assert`s
and four mismatched declarations **cannot compile at all**, because every one of them
needs the headers above the core. One direction only: phase 27's own check passes on that
stage. **There is no `need 27`**, also measured — the edit applied to phase 26's unswept
output gives a `zero-vim.c` `cmp`-identical to the swept path's, and it asserts no count
of its input that a sweep could move.

### What zero-vim is after twenty-seven phases

```
zero-vim.c        80,232 lines          from whim-vim.c's 86,614  (-6,382, 7.4%)
                  78,358 above the boundary, 1,874 below it
functions         1,757
type definitions  909
DWARF enumerators 1,189
cmdnames[] rows   98    (create_cmdidxs floor 80; 18 rows of margin)
nv_cmds[] rows    194   (nvidxcheck: a permutation)
options[] rows    107, 95 distinct globals  (orphanopts floor 80; 15 of margin)
#include          11, at line 78,360, and NOT ONE DIRECTIVE above them
core -> host      13 names: vim_snprintf, host_exit, host_message, ten musl_*
libc symbols      17 with zero's flags, 18 as tools/symbols.sh counts
binary            788,488 bytes, EXEC, no INTERP, no dynamic section, no relocation
declared delta    nothing since phase 11 -- 2 stderr-moved and the records of 4 to 11
make editor.c     78,358 lines: 0 directives, 0 errors, 13 warnings, all of them
                  `used but never defined` and all of them the interface
```

**`ZERO-PLAN.md` §4c is built out.** Its design was one file with two parts and the first
`#include` as the boundary, and the four phases that draw it are done: 23 replaced the two
names a header supplied with two the language does, 25 made the two host calls plain, 26
gave the core its own types and macros, and 27 moved the includes. **Seven phases in a row
have declared nothing** — 21 through 27 — and among them are five distinct kinds of
evidence: the code runs and the instrument sees it (21, 25, 26's clock), the instrument is
nearly blind and 263 probes stand in (22), the binary is the same bytes (23, 24), six of
seven changes are a `cmp` and one is a recording (26), and the source is the same lines
rearranged (27). The last is new, and it is the one a pipeline needs the day it starts
moving code rather than deleting it.

## Phase 28 — the scalar clock

`pipes/zero28-edit.sh` and `pipes/zero28-check.sh`, `stage 28`, `package boundary`.
The core's whole use of time is *stamp now, then ask how many milliseconds have
passed*. That is four places — `do_sleep`'s `done < msec` loop, `vim_beep`'s 500 ms
rate limit, `handle_osc`'s `>= p_ost` timeout and `inchar_loop`'s deadline — and **not
one of them reads a field, prints a reading or compares two stamps**. So the core never
needed the *layout* of a clock, only a scalar, and this phase gives it one:

```c
    long musl_now_ms(void)          replaces    void musl_gettimeofday(long *, long *)
    X = musl_now_ms();                          a stamp
    musl_now_ms() - X                           a reading
```

Three things phase 26 created go together and are at **0** afterwards: `elapsed_T`, its
tagless mirror of `struct timeval`, whose layout that phase had to `static_assert`
equal; `elapsed()`, whose whole body was one clock read and one subtraction; and
`musl_gettimeofday`, **whose out-parameter pair existed only because a struct could not
cross the boundary**. 80,232 → 80,222 lines.

### What it earns, and the check is careful not to claim more

Every one of the thirteen core → host signatures takes **scalars and byte buffers
only** — `void`, `int`, `long`, `usize`, `char *` and `int *`, with `vim_snprintf`'s
`...` held to printf arguments by `format(printf, 3, 4)` on a `-Wall -Wextra` clean
build. **That was already true at r27**, phase 26 having chosen `long *, long *`
precisely so that `struct timeval` would not cross, and the check computes the property
on the *input* as well as the output for exactly that reason. What is new is that the
**workaround** is gone: no host call's shape is decided any more by a type the core
cannot name.

`nm -u` is the same 17 names and **`gettimeofday` is still one of them**, stated as an
equality because a reader expects a clock phase to free a clock symbol. It cannot: the
host still calls it to implement `musl_now_ms`, and a symbol leaves when its last
*caller* leaves the **file**, which is the split and not this phase.

### Two decisions, both measured

**The origin is the whole second of the first call, not 1970.** Every core use is a
difference, so the origin is free — and on a target where `long` is 32 bits `tv_sec *
1000` is signed overflow on the **first** call and every call after it, measured with
`-fsanitize=signed-integer-overflow` as *`1789797927 * 1000 cannot be represented in
type 'int'`*, where `(tv_sec - base) * 1000` is exact for 2^31 ms, **24.86 days** of
uptime. The base is taken **lazily** rather than in `musl_host_init()`, because an
ordering dependency between two host functions is what a host rewrite breaks silently.
The origin being a whole second is what makes it behaviourally invisible, and the
`epoch` variant's probes and full recording are the product's.

**Precision is not lost and the rounding point moves.** `elapsed()` subtracted and
*then* divided; `musl_now_ms` divides at each reading and the caller subtracts.
Microseconds were already discarded either way — but the two roundings are not the same
function, and the check compiles a probe and runs it over **20,000,000 random pairs**:
the difference is exactly ±1 ms and never more, 24.95 % one lower, 50.08 % equal,
24.97 % one higher, with neither formula closer to the truth. The control is the `ceil`
variant, which rounds every reading **up** — twice the perturbation this change can
cause — and whose probes and full recording are also the product's.

### The declared delta is nothing at all, and it is phase 2's kind

The code runs and the instrument cannot see it, **measured rather than inferred**: of
the 102 screen cases, 95 ring the bell once and 7 not at all, and **not one rings it
twice**, so `vim_beep`'s 500 ms limit — the only clock reading a screen case can reach
— is never asked to suppress anything. Three controls say it from the other side: a
clock that never advances, one that runs backwards and one that runs 1000× fast each
move **0 of the 102**.

So the phase owes probes, and they are built on **`gs`** — `nv_g_cmd`'s `s` arm is
`do_sleep(count * 1000)`, the one call site a keystroke file can drive and the only way
real time passes inside the editor. `1gs` is 1,009 ms on the binary the phase was
handed and 1,008 on its own, `2gs` 2,005 and 2,004, and `hgshh` rings **2** bells on
both — `vim_beep`'s threshold in both directions in one probe. Each half fails on a
control aimed at it: with the clock 1000× fast `2gs` returns after one wait; with a
clock that never advances `1gs` **never returns**; with `vim_beep`'s 500 written
500000 `hgshh` rings 1 bell and with it written −1 it rings 3.

**The sleep assertion was wrong once and the fix is the interesting part** (commit
`6ef24b7`, after the phase landed). It asked for `2gs - 1gs >= 900`, and **both numbers
are wall-clock times taken from outside, around whole editor runs**, so each carries its
own startup jitter: phase 30's verify caught it on a loaded machine with `1gs` inflated
to 1,133 ms against `2gs` at 2,006, and a correct phase failed. Widening the threshold
would move the boundary rather than remove it. **A lower bound on a sleep cannot flake
in that direction** — a sleep takes at least as long as it asks for and load can only
make it longer — so the assertion is `2gs >= 1900`, and the `fast` control still breaks
it at 1,008 ms.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 80,232 | **80,222 (−10)** |
| `elapsed_T` / `elapsed()` / `musl_gettimeofday` | 3 things | **0** |
| `make editor.c` | 78,358 lines | **78,342**, 0 directives, 13 boundary names |
| the boundary | 13 names | **13**, `musl_gettimeofday` → `musl_now_ms`, asserted as a *set* |
| `nm -u` | 17 | **17, the same set**, `gettimeofday` among them |
| external symbols | `main` | `main` |
| binary | 788,488 | **788,488 bytes, and not the same bytes** |
| records that moved | | **0 of 106**, on four recordings — input, output, `ceil`, `epoch` |

### Its placement

`stage 28`, `package boundary` — **not `host`**, and the phase argues it: `boundary` is
not only where the line falls but what the core may **name** at it, which is what 23, 25
and 26 each did, and this is 26's clock item finished; `host` would be wrong more
plainly, since 17 to 21 move code into the launcher and this phase moves none. Four
`uses`: `seed:0` and `harness:3` for the recording — where the check says outright that
the recording is the **weakest** part of the evidence — `host:20`, because `musl_now_ms`
is defined inside the block that phase created and `tools/zhostonly.py` reads the host
region from `host_winch_pending`, and `host:18`, because the probes rest on the editor
being an ordinary program a keystroke file can drive to exit.

`apart 27 28` is measured by running phase 27's check on the tree this phase leaves: it
stops at its first act with *"`elapsed` is not defined exactly once above the boundary,
so the control that moves one core function below it would not be a control"* — **phase
27's boundary argument rests on moving one core function below the cut, and the function
it picked is the one this phase deletes**. One direction only. `need 28 swept` is
measured *not* to be required: run on the unswept tree from phase 27's edit cache, this
edit gives a byte-identical `zero-vim.c` and the sweep after it is a complete no-op.

`tools/zhostonly.py` gains `gettimeofday` as a host word, which this phase is what makes
permanently true, with the five core call sites phase 26 moved named as exceptions at
the counts they had at r20, r21 and r25. Measured: exactly ten keys move — zero units
and edits 20, 21, 25, 26 and 27 — and **not one slim or whim key of the 107**.

## Phase 29 — the case tables become one, and it is the union

`pipes/zero29-edit.sh` and `pipes/zero29-check.sh`, `stage 29`, `package casemap`.
`zero-vim.c` carried **two complete Unicode simple-case maps** and they did the same
job: vim's own `toUpper[]`/`toLower[]`, there since whim, and musl's, which phase 15
added as `musl_toUpper[]`/`musl_toLower[]` range-compressed into the same
`convertStruct` shape so that `towupper` and `towlower` could leave `nm -u`. Which one
the editor consults is decided by `'casemap'`. **A core with no C library has nothing
to choose between**, so this phase makes it one table — and the table is the **union**.

### The survey said the two "differ on 2 of 5 probes", and five characters cannot see 193 codepoints

Expanded over the whole of `0..0x10FFFF`, from the file and again from this machine's
libc through `ctypes`, the two disagree at **97 upper and 96 lower** codepoints, at
none of which both map to different characters, and the split is lopsided:

* **vim maps and musl does not, 96 and 96**: all of Vithkuqi, all of Garay, the enclosed
  Latin letters `U+24B6..U+24CF` and `U+24D0..U+24E9`, Glagolitic `U+2C2F`/`U+2C5F`, the
  recent Latin Extended-D additions, `U+019B`, `U+0264`, `U+1C89`, `U+1C8A`. **vim's
  table is simply newer** — it knows Unicode 14's Vithkuqi and Unicode 16's Garay, and
  musl's `casemap.h` predates both.
* **musl maps and vim does not, exactly one**: `U+00DF → U+1E9E`, the sharp s.

So *use vim's* loses the sharp s and *use musl's* loses ninety-six. **Each table knew
something the other did not, and the union is the only answer that keeps both.** It is
**computed, not written down**: the edit expands both tables, refuses on a codepoint
they map differently, requires that no existing row covers one it is about to insert —
`utf_convert()` binary-searches on `rangeEnd`, so a row inside another row is
unreachable — inserts `{0xdf,0xdf,-1,7615}` at its sorted place, and re-expands and
requires the result to be exactly the union. It also parses and re-emits all four
tables **before** changing anything and refuses unless the re-emission is byte-identical
to the text it came from, so the row it writes is in `tools/canon.sh`'s shape by
construction.

### The one row is a deliberate divergence from Unicode, taken knowingly

Unicode's **simple** uppercase of `U+00DF` is `U+00DF`; `U+1E9E` is musl's tailoring,
and putting it into vim's own table changes the **default** `'casemap'`. What it buys is
that the file stops contradicting itself: `swapchar()` has hard-coded `ß → ẞ` for `gU`,
`g~` and `~` all along, so before this phase the table and the keystroke gave different
answers for the same character.

### The delta runs on both arms, and that is what a reader gets wrong

On the **non-internal** arm — `:set casemap=` or `casemap=keepascii`, which read musl's
table and now read the union — 96 upper and 96 lower codepoints **gain a mapping they
never had** and `ß` **keeps** the one it had. On the **default** arm the single row
arrives. Six probe sessions move and six must not, and the six that must not are the
ninety-six proving they did not regress on the arm that always had them, the sharp s
keeping what it had on the arm that always had it, `g~g~` on `ß`, and `:set isk=@` then
`dw` on `café naïve`.

**Two traps the probes had to get right, both measured.** `gU`, `g~` and `~` **cannot
show the sharp s at all**, `swapchar()` hard-coding the mapping before it consults any
table — so the row is reachable only through `\u`/`\U` in a substitution, which goes
`do_upper` → `vim_toupper` → `utf_toupper` and hits the table directly. And the chartab
that the 892 startup calls of `towupper`/`towlower` build **does not move**, although
those calls run with `cmp_flags` still 0 and therefore take the non-internal arm: the
union equals musl's table at every one of `128..255`, the two having disagreed below
`U+0100` at `U+00DF` alone.

### The declared delta is nothing at all, and that is the harness and not the phase

The corpus cannot see any of this — all 102 screen cases seed themselves by typing
ASCII and none touches `'casemap'`, the Ex sweep reads the message a command prints, the
argv records are command lines, the pty scenarios are the window size and raw mode. Two
full recordings are byte-identical in all 106 records, so `pipes/zero.delta` gains no
line. **That is phase 2's situation — a blind harness rather than a static phase — and a
phase in it owes probes of its own.** Two controls, each computed from the two sources
rather than spelled out: `vimonly` is the output with musl's contribution taken back
out, and the default-arm probe then records exactly what the **input** recorded;
`vimless` is the output with `toUpper[]` replaced by the input's `musl_toUpper[]` — the
merge done the careless way round — and the circled letter goes, which is the regression
no record could report.

**The check's strongest assertion is not a row count.** The produced tables are expanded
over all 1,114,112 codepoints and required to be exactly the union in three directions,
with the musl half **re-derived from libc** rather than from the bytes the phase
deleted, and a perturbed row proving the comparison can fail. Beside it is a rule rather
than a number: what the phase changes on the default arm, and what it stops mapping, are
both **computed** from the two input tables, and every member of both must appear in the
probe text.

### Measured

| | input | after |
| --- | --- | --- |
| `toUpper[]` | 198 rows, 1,477 codepoints | **199 rows, 1,478** |
| `toLower[]` | 183 rows, 1,460 codepoints | **183, 1,460** — musl's lower table added nothing |
| `musl_toUpper[]` / `musl_toLower[]` | present | **gone** |
| lines | 80,222 | **79,857 (−365)** — 358 sixteen-byte rows out and one in |
| `make editor.c` | 78,342 | **77,977**, the same −365 |
| binary | 788,488 | **782,760 (−5,728)** |
| `nm -u` | 17 | **17, the same set** — changing *data* frees no symbol and needs none |
| DWARF enumerators | 1,189 | **1,189**, none gone, arrived or renumbered |
| `options[]` / `cmdnames[]` | 107 / 98 | 107 / 98 |
| records that moved | | **0 of 106**, against twelve probes that carry the phase |

### Its placement

A package of one, `casemap`, deliberately **not** `vendor`: `vendor` is *nothing is
brought in*, and this phase brings nothing in and frees no symbol — what it decides is
what the core's case map **is**, which is phase 12's argument and whim's Phase 18's
applied to data instead of to an option row. Three `uses`: `seed:0` and `harness:3`,
and `vendor:15`, because without phase 15 there is one case table already and no union
to take.

`apart 28 29` is measured with `tools/phaserun.sh zero 28-29` on r27: phase 28 states
its arithmetic as a line count of **the core** and stops at *"the core is 77978 lines
and was 78359, a difference of −381 where −16 was expected"* — its own −16 less this
phase's 365. One direction only, measured too: phase 29's check was then run on the tree
that stage leaves and every part of it passed. **No `need 29 swept`**, measured in the
same run.

**Two things about the pipeline this phase ran into, recorded and not acted on.** `make
zero-verify` cannot run while the phase list has a gap — `tools/verifypass.sh` takes the
previous boundary as `r$((first - 1))`, so a reserved-but-unlanded number makes it die
on a missing tar. And `make zero-tip` in a fresh worktree re-runs every phase, because
`git worktree add` gives `whim-vim.c` a new mtime and `$(ZEROBUILD)/input.sha256`
depends on it.

## Phase 30 — the message fold: `msg_puts_printf()` and the branch that reaches it

`pipes/zero30-edit.sh` and `pipes/zero30-check.sh`, `stage 30`, `package host`.
`msg_puts_attr_len()` ends in a two-armed test: the true arm handed the message to
`msg_puts_printf()`, 75 lines that reach the terminal **without a screen**, and the
false arm draws it. The true arm is never taken, and this phase folds it to two lines
that say the same thing to the host:

```c
    host_message((char *)str, maxlen, !info_message);
    msg_didout = TRUE;
```

`msg_puts_printf()`, its prototype, and `vim_strlen_maxlen()` and its prototype — which
the sweep finds, that function's only call being inside it — go with it. **Two
functions, not one**: 1,756 definitions → 1,754, and 79,857 → 79,766 lines, the edit
adding one and the sweep taking 92.

### Which kind of dead, and it is not phase 9's

Phase 9 removed code that **could not run**. This removes code that **can** run and
never does, which is phase 12's kind, and the difference decides what evidence is owed.
`msg_use_printf()` is a live predicate: instrumented on this phase's own output it
answers TRUE **23 times**, every one at `msg_clr_eos_force()`, every one in
`ref-argv.txt`, one per `mainerr` row — with `full_screen` FALSE in all 23, so the body
it guards is a no-op. The phase therefore leaves the predicate at six mentions and
claims only that **one of its four call sites is dead**. The evidence is phase 12's
shape: the input source built twice with the identical `write(2, "PP-ENTERED\n", 11)`,
first in `msg_puts_printf()` — **0 of 106 records** — and then in `msg_puts_display()` —
**103 of 106, 5,749 occurrences**.

### Why the message is kept rather than dropped

Deleting the arm's body outright is five lines smaller and records identically. It was
rejected: **a phase about removing dead *code* must not quietly remove a
*capability*.** `host_message(msg, len, err)` takes `len < 0` as `strlen` and `len >= 0`
as an exact count, which **is** `msg_puts_printf`'s own `maxlen` contract, measured by
reading both. The arm is never executed, so equivalence is not claimed: what the two
lines do not reproduce is the CR-before-NL insertion and the `msg_col` bookkeeping, and
no recording or probe in this pipeline can reach either.

### That the recording did not move is not the check, and this is where that matters most

**The two folds this phase declines also record byte-identically, and one of them is
wrong.** So the check is 36 probes and an instrumented pair, and it **builds the
rejected folds and requires each to move a named probe**:

* **`msg_clr_eos_force()`'s test cannot be folded safely.** Phase 21 said folding it
  "would run `screen_fill()` with no valid screen". That is right, and the number behind
  it is the interesting part: `screen_fill()` returns early on `ScreenLines == nullptr`,
  and `ScreenLines` **is** null in all 23 `mainerr` cases, which are the only 23 places
  the predicate is TRUE in a recording — **so the fold leaves the whole 106-record
  recording byte-identical and a phase checked only against the corpus would ship it**.
  Two probes see it: `t_ti_stopterm` 2,266 → 2,280 bytes and `hup_clean` 2,124 → 2,142,
  the extra eighteen being `\x1b[24;63H\x1b[K\x1b[24;1H` **after** `Vim: Finished.` —
  the editor erasing the last line of a screen it has just declared unusable, on its way
  out. Guarding with `msg_check_screen()` instead is **not** a cheaper spelling of the
  same thing: it drops the `swapping_screen() && !termcap_active` disjunct, which is
  exactly what `t_ti_stopterm` reaches.
* **`exit_scroll()`'s printf arm is ALIVE, and phase 21 was wrong to name it a follow-up
  beside `msg_puts_printf()`.** `pipes/zero21-check.sh` says the two "fire in ZERO of
  106 records"; that is true of the **corpus** and true of the editor only for the
  first. With **no signal at all** the arm fires in **three of this phase's 32 stream
  probes** — `t_ti_more`, `debug_more`, `term_ti_then_ti` — and in **three of its four
  deadly-signal probes**. Folding it to `out_char('\n')` is not a crash risk:
  `out_char('\n')` emits `\r` first, so the bytes on the wire are the same two. It moves
  them **from fd 2 to fd 1**, and on a pty where both descriptors are the same device
  the combined stream is byte-identical — which is why `tools/zpty.py` could never see
  it and why folding it here would be **undeclarable**. It belongs to whichever phase
  decides the core writes nothing to fd 2 at all. The check builds that fold too and
  requires it to move exactly those three stream probes and those three signal probes,
  so *"this phase did not disturb it"* is measured rather than asserted — and that is
  what the four deadly-signal probes are for, and why they run **with fd 2 on a pipe of
  its own**.

### A counting trap that cost a first attempt at the anchor

`    if (msg_use_printf())` at four spaces is a **substring** of the same line at eight,
so `str.count()` says 3 where `grep -c '^    if (msg_use_printf())$'` says 2 — the third
match being `exit_scroll`'s. And there are **four** call sites, not three: the fourth is
written `if (!msg_use_printf())` in `hit_return_msg()`, and an edit that greps for the
positive spelling misses it. The anchor is the four-line block, whose count is 1, and
all three untouched sites are asserted verbatim before and after.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 79,857 | **79,766** — the edit adds 1, the sweep takes 92 |
| function definitions | 1,756 | **1,754** |
| `make editor.c` | 77,977 | **77,886**, 0 directives, 0 errors, the boundary unchanged |
| `nm -u` | 17 | **17, the same set** |
| binary | 782,760 | **782,760** |
| records that moved | | **0 of 106**, with 32 stream probes and 4 signal probes identical |

### Its placement

`stage 30`, `package host 17 18 19 20 21 30`, because this is phase 21's own follow-up
and not a tidy-up. Three `uses`: `seed:0` and `harness:3` for the recording, and
`boundary:25`, because `host_message()` is a name the `editor.c` cut enumerates only
since phase 25 turned the function pointer into a declaration. There is deliberately
**no `uses host:30 host:21`** — `uses` records a dependency *across* packages and
`tools/packages.sh --check` refuses one inside a package — so that relation is written
as a comment on the `package host` line instead.

`apart 21 30`, measured rather than assumed: phase 21's check pins thirteen names, of
which **seven are already broken by phases 22–29**, four are untouched here, and exactly
**two** move at this phase — `msg_puts_printf` 3 → 0 and `info_message` 9 → 7.
`msg_use_printf` stays at 6, which is the other half of phase 21's assertion and
survives intact. **No `need 30`**: the edit's one anchor is a four-line block of exact
text whose count is 1, and no count a sweep can move.

**Phases 28 and 29 landed while this one was being written**, and the independence was
measured rather than assumed: every counted anchor has the same value on r27, on r28 and
on r29. One thing did move — phase 28 renames `musl_gettimeofday` to `musl_now_ms`, and
that name is one of the boundary names the `editor.c` cut prints. This check never
writes that set out: it computes it from the input and from the output and requires the
two to be equal, so the rename cost it nothing. **That is the whole argument for
counting a set as a rule rather than as a table of constants.**

## Phase 31 — `abs` and `labs`, the two the core took on trust

`pipes/zero31-edit.sh` and `pipes/zero31-check.sh`, `stage 31`, `package vendor`.
**The core is optimised for transpilation, not for performance, and so it may not depend
on latent compiler behaviour** (`ZERO-PLAN.md` §4c, the user's rule). This is the first
application of it, and by every number this pipeline usually reports it does nothing:
`nm -u` is the same 17 names either side, as a `comm` empty in both directions.

**That is the phase.** `abs` and `labs` were **called** by the core, at three sites, and
were in the undefined set **zero times** — measured here, the input's whole assembly
(`gcc -S -O0`) mentions neither name, because gcc lowers both to inline arithmetic.
Nothing in the language promises that. A compiler that emitted the calls the source
literally asks for would have added two libc symbols to a file whose whole claim is the
shortness of that list, **and nothing in the pipeline would have said so until it
happened**. So the phase frees nothing and says so as an equality; what it removes is a
dependence on behaviour nothing states.

Two prototypes leave the core's libc declaration block, which phase 26 wrote and which
goes **9 entries to 7** — found by its *shape*, a contiguous run of top-level
declarations above the first `static`, and never by line number. The three call sites
become `musl_abs` and `musl_labs`, by the literal-aware single pass `CLAUDE.md` asks
for. And two definitions land in the `musl_` block phases 14 and 15 built, immediately
above `musl_bsearch`, so the four `<stdlib.h>` functions the core owns — `musl_atoi`,
`musl_atol`, `musl_abs`, `musl_labs` — sit together and above every use.

### musl's spelling is copied and not improved, and the undefined behaviour with it

`/root/musl/src/stdlib/abs.c` and `labs.c` are one line each, `a>0 ? a : -a`, and the
check proves that choosing it **costs nothing** rather than arguing it: `a > 0 ? a : -a`
and `a < 0 ? -a : a`, both taken out of the output, compile to byte-identical machine
code at `-O0` and at `-O2`, and agree at all 4,294,967,296 `int` values and at
20,000,006 `long` ones including `LONG_MIN` and `LONG_MAX`.

`-a` overflows at `INT_MIN` and at `LONG_MIN`, so both vendored functions are undefined
there — **and so are libc's, by the same expression, and so is musl's own source**. The
pair is *faithful rather than safer*: a phase that quietly made the core's arithmetic
differ from the libc it replaces would be a behaviour change wearing a vendoring phase's
clothes. What is measured instead is whether the three sites can be driven there, and
they cannot — `last_status_rec`'s two operands are window heights, which
`limit_screen_size()` clamps at 1,000 rows, and the two `labs` arguments are differences
of line numbers, so `LONG_MIN` needs a buffer of 2^63 lines. Instrumented, the largest
magnitude any of the three is ever handed over 51 probe calls is **22**.

### What the image may do is a rule and not a coincidence

There is no `cmp` to be had — at `-O0` a call to a static function is a call and inline
arithmetic is not — so what is asserted is that the difference is **accounted for
instruction by instruction**: the object's `.text` grows by exactly **42 bytes**, which
is `musl_abs` (19) plus `musl_labs` (24) plus what the three callers gained or lost
(−2, +1, 0) **and nothing else**, and the linked image is 782,760 bytes either side with
604,650 of them different, which is what putting a definition near the front of a file
does.

**Only `.text` and `.eh_frame` change size** — no data section moves a byte, which is
the *this phase changes code, not data* claim — and neither changes by more than one
alignment unit. Which of the two happens is a property of the **input**, measured both
ways for the identical edit: 0 on the r29 tree and 64 here. Written as *"every section
but `.eh_frame` keeps its size and its address"* — true on r29 — the check **refused
this rebase**, naming `.text` and `.fini`, and that is the assertion working and the
phase being fine.

### The corpus cannot see this phase at all

Measured rather than assumed: the output built with a probe on each of the three
arguments enters **none** of them in 106 records, and its recording is byte-identical to
the product's. So the phase owes probes, and runs three, one per site — `+set rnu` with
sixty lines (46 calls, arguments −21 to 22), sixty long wrapped lines then CTRL-F CTRL-F
CTRL-B CTRL-B (3 calls), and `:set laststatus=2` then `=0` (2 calls). **Two of the three
are proven able to fail**, by a control whose `musl_abs` and `musl_labs` return their
argument unchanged. **`stl` does not, and the check reports it rather than hiding it**:
its site is reached twice and its answer guards only `w_prev_height = w_height`, which
`win_new_height()` already assigns on every path that changes a height. That site is
proven **reached** and not proven **observable**, and the equivalence above is its
evidence.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 79,766 | **79,776 (+10)**, all of it core |
| `make editor.c` | 77,886 | **77,896** |
| the libc prototype block | 9 entries | **7** |
| `abs` / `labs` in `nm -u` | 0 | **0** — they were never there, and that is the point |
| `nm -u` | 17 | **17, the same set** |
| object `.text` | | **+42 bytes**, accounted for instruction by instruction |
| binary | 782,760 | **782,760**, 604,650 bytes different |
| records that moved | | **0 of 106**, against three probes the corpus cannot reach |

### Its placement

`stage 31`, `package vendor 14 15 31`. Four `uses`: `seed:0` and `harness:3`, the corpus
reaching none of the three call sites so a probe here is a screen recorded from a
keystroke file; `boundary:26`, the two prototypes it deletes being that phase's; and
`boundary:27`, the check asserting that both definitions land **above** the first
`#include`, which is the boundary only because of the move.

**Both schedule declarations are measured, in one run.** `tools/phaserun.sh zero 30-31`
on r29 runs both edits, one sweep and both checks and stops in phase 30's — *"the output
is 79776 lines and the input was 79857, a difference of 81 where 91 was expected"* —
because the ten lines this edit adds land in the same swept text. That is `apart 17 18`'s
shape exactly, and it is one direction only. The same run measures that **`need 31
swept` is not required**, this edit applying unchanged to phase 30's unswept output with
all five anchors holding.

## Phase 32 — the clock crosses the boundary

`pipes/zero32-edit.sh` and `pipes/zero32-check.sh`, `stage 32`, `package host`.
The core read **two** clocks and only one of them had crossed. Phase 28 gave the
elapsed-milliseconds clock to the host as `long musl_now_ms(void)`; the wall clock
stayed behind as `static time_T vim_time(void) { return time(nullptr); }`, with five
call sites, `long time(long *tp);` in the core's own libc prototype block, and **two
more reads that bypassed the wrapper altogether** inside `ui_focus_change()`. Two steps,
in order: those two become `vim_time()`, and the wrapper then moves below the first
`#include` as `host_time()`, declared in the core's host block beside `host_exit` and
`host_message`.

Afterwards **the core does not name `time` at all** — four mentions in the input's core
to none, counted on the **literal-stripped** text because two `NGETTEXT` strings in
`op_shift()` say the English word and a count that read those would be counting English.
`host_time` is 8 above the boundary (the declaration and seven call sites, the input's
five plus the two that bypassed the wrapper) and 1 below. The libc prototype block goes
**7 entries to 6**, losing `time` and nothing else — `malloc realloc free getpid kill
write` — phase 31 having vendored `abs` and `labs` out of it immediately before. The
block is found by its **shape**, a run of non-blank lines around a line already required
to be unique, so phase 31 landing under this phase cost it no edit at all. The file is
**79,776 lines either side**: the core loses 7 and the host gains exactly 7.

### The prototype never pinned `time_T`, and that corrects something written down twice

Phase 26's commit and the brief for this one both say that `typedef long time_T;` is
correct because `long time(long *tp);` sits above `<time.h>`'s declaration of the same
function, where gcc compares the two. **Half of that is true and the important half is
not**, and the `m2` compile is what says so: the input with `time_T` changed to `int`
and the prototype **left alone** compiles in **silence**. The prototype pinned
`long == time_t`; nothing ever checked `time_T == long`. So this phase does not preserve
a guarantee, it **replaces a weaker one with a stronger one**:

```c
    static_assert(_Generic((time_T)0, time_t: 1, default: 0), "time_T is time_t");
```

beside the twelve constants phase 27 put below the includes, **which is the only place
in the file where a core name and a header name are both in scope**. Four compiles, all
in the check. `m1`: the input with the prototype written `int time(int *tp);` is
`conflicting types for 'time'` — that *was* the guarantee, and it is a real one. `m2`,
as above: silent. `p1`: the output with the assert deleted and `time_T` perturbed
compiles in silence too — **the regression this phase would otherwise have shipped, and
the reason the prototype could not simply be deleted**. `p2` and `p3`: with the assert
present, `int` and `long long` both give `static assertion failed: "time_T is time_t"`.
The one line names `time_T` itself, which the prototype could not.

### `host_time()` returns `long` and not `time_T`, which is a decision

Its definition is below the boundary and `time_T` is a core typedef above it, so the
host half could not name it once the file is cut at the first `#include`.
`musl_now_ms()` returns `long` for that reason and this is its sibling — the two halves
of the clock now cross in the same shape, and the boundary's stated property that every
core → host signature takes scalars and byte buffers only survives a **fourteenth**
name. Nothing is converted at any call site, `time_T` being `long` on the page, and the
check asserts the typedef line itself.

### The recording is the weakest part of the evidence, and the check says so

Two full recordings are byte-identical across all 106 records — but **not one of the 102
screen cases reaches `ui_focus_change()`**, which is the only function whose reads this
phase respells in place. So the phase owes an instrument, and it has two.

An **instrumented pair**: `write(2, "TICK\n", 5)` at every clock read on each side —
three sites on the input (the wrapper, and `ui_focus_change`'s two, as comma expressions
so that the tick is exactly where the read is), one on the output, because afterwards
there is only one — with the two instrumented 102-case recordings required to be
byte-identical. They are, and the instrument is not silent: it marks **100 of 102 cases
with 410 reads** in all, the two it misses being `ctrl_c_clean` and `ctrl_c_changed`,
which exit before a key is looked up.

And **focus probes**, because a keystroke file *can* reach `ui_focus_change()`: `\033[I`
and `\033[O` are `KE_FOCUSGAINED` and `KE_FOCUSLOST`, and `set_termname()` registers
both unconditionally — **`ZERO-PLAN.md` §2l's hazard, that a typed Escape followed by
`[` is read as a key code, used deliberately**. `\033[O \033[I` reads the clock 3 times
and `\033[O \033[I \033[O \033[I` reads it 4, identically on both binaries; the
arithmetic is 0 + 2 + 0 + 1 at the four calls plus one for the `:q!`, `focus_state`
starting MAYBE so that the first FocusLost reads nothing and the first FocusGained finds
`last_time` at 0 and takes both reads. **The two reads are still two reads**, in the
same two statements and the same order, so they straddle a second neither more nor less
often than before — and the control is that question made into a program: `hoist` is the
output with the two reads collapsed into one local, and it gives 5 on the second probe
where the product gives 4. `focus` does **not** separate them (3 either way, by a
different route), which is why there are two probes and the check says which one is
load-bearing.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 79,776 | **79,776** — the core loses 7 and the host gains 7 |
| `time` named in the core | 4 | **0**, on the literal-stripped text |
| the libc prototype block | 7 entries | **6** |
| `make editor.c` | 77,896 | **77,889**, 0 directives, 0 errors |
| the boundary | 13 names | **14**, `host_time` arriving and nothing gone |
| `nm -u` | 17 | **17, the same set** — `time` does not leave, and that is said as an equality |
| external symbols | `main` | `main` |
| binary | 782,760 | **782,760 bytes, and not the same bytes** |
| records that moved | | **0 of 106**, with an instrumented pair and two focus probes behind it |

### A hazard this phase found in the shared recording, recorded and deliberately not worked around

Comparing two **full** recordings is load-sensitive in exactly three records, and the
clock phase is the one that would notice. `tools/zrec.py` scrubs the undo message's
elapsed time to `<ago>` **padded to the width it replaces**, so the *screen* is
protected — but the record also carries `--- stream <len> sha=<…>`, taken over the
**raw** byte stream, where `0 seconds ago` and `1 second ago` are 13 bytes and 12.
Measured with a control built for it — `add_time()` reporting one second more — exactly
three records move, `undo_after_ins`, `undo_block` and `undo_redo`, which are exactly
the three whose screen carries `<ago>`, and in each exactly **one line** moves, the
`--- stream` line, with all 24 screen lines byte-identical. One 33-way concurrent `make
zero-verify` failed here on `undo_after_ins` alone. **It is not this phase's to fix** —
hashing the scrubbed stream in `tools/zrec.py` would re-key all 33
phases and require `.reference/zero-baselines` to be recorded again — **and not this
phase's to paper over either**, a private exclusion being a check narrowed to fit what
it saw. The comparison stays an exact `diff -rq` and the hazard is written into the
check's header. What matters for this phase is that the exposure is **unchanged** by it,
which is what the instrumented pair measures.

**AND HASHING THE SCRUBBED STREAM WOULD NOT CLOSE IT, which zero phase 40 measured
afterwards and which this paragraph got wrong.** The scrub rewrites the age's TEXT,
padded; the leak is *arithmetic on that text's width*. An undo reports its age and the
editor then positions the cursor to clear the line, so `0 seconds ago` emits
`\033[24;40H\033[K` and `1 second ago` emits `\033[24;39H` — a column derived from a
scrubbed string's length, in a byte sequence the scrub never touches. It failed zero
phase 16, whose binary is byte-identical either side, which is the only reason it was
catchable at all. The fix that does work is phase 40's: record `stream N redraws`, a
count of `\x1b[?25h`, instead of a digest, and let a clock control carry the evidence —
both readable clocks replaced by runaway counters move 0 of 16 memline records against
9 of 102 screen cases, which says the record does not depend on the clock AT ALL, and a
digest never could. `tools/zmemline.py` does this; `tools/zcases.py` still digests the
raw stream, and the change is expensive rather than hard: the `--- stream` line is named
in eighty files, forty-seven times in zero phase 12's check alone.

### Its placement

`stage 32`, `package host 17 18 19 20 21 30 32`, because this is what that package is:
a thing the core did for itself becomes a thing it asks the host to do, declared in the
one host block and defined below the boundary — `host_exit` (19), `host_message` (21),
`host_time`. It is deliberately **not** `boundary`, which *draws* the line (23, 25, 26,
27, 28); this phase moves one function across a line already drawn. Five `uses`:
`seed:0` and `harness:3`; `boundary:26` for the prototype and the typedef it replaces;
`boundary:27` for the only place the `static_assert` can be written; and `boundary:28`
for `musl_now_ms`, whose shape and whose `nm -u` sentence this phase takes.

**Four `apart` lines.** Three are one fact measured three ways, phase 30's method of
applying each check's own assertion directly to the tree this phase leaves: 26 and 27
both carry the nine-entry `PROTOS` list and now find **three** of the nine at 0 — `labs`
and `abs`, already phase 31's, and `time`, which is this phase's — and 27 and 28 both
**write out** the boundary as thirteen names where this phase makes it fourteen, the
symmetric difference being exactly `{host_time}`. The fourth was measured with
`tools/phaserun.sh zero 31-32` on r30: `apart 31 32`, one direction only, where phase
31's check stops on three messages — the block losing `time` as well as `labs`/`abs`,
the core at a difference of 3 where 10 was expected, and *"the host changed size, and
this phase does not touch it"*. **No `need 32`**, measured in the same run.

## Phase 33 — the terminal table is asked with `+set term=`, not `$TERM`

`pipes/zero33.sh`, one whole program, `stage 33`, `package harness`. The second phase
in the pipeline that changes **no source at all** — phase 3 is the other — and it is
there for the same reason: the pipeline was about to measure itself with a question
that could not see the answer.

**The nineteen rows of `.reference/zero-baselines/ref-term.txt` were content-free, and
had been since phase 0.** Every one of them read

```
TERM='vt100'              -> term=xterm-256color t_Co=256
```

because whim phase 19 removed the `getenv("TERM")` from `termcapinit()` — *the terminal
is what the build says* — and left a compiled `"xterm-256color"` in its place. Nineteen
ways of recording that the environment does nothing.

**The measurement is the reason the phase exists rather than an argument for it.** A
prototype that DELETED eight of the ten built-in terminal names and three of the nine
capability tables — 118 lines of terminal description — passed `tools/zcompare.py`
against the real baselines **declaring nothing at all**. The only thing that moved in a
five-part recording was two lines of stderr, which `2 stderr-moved` already absorbs. A
phase may declare nothing only when the instrument could have seen it; here it could
not.

`tools/ztermcheck.py` now asks `+set term={name}` on the command line, which reaches
`did_set_term()` rather than `termcapinit()`'s compiled default, and records the `E5NN`
beside the answer where one is given. **Ten of the nineteen names resolve to
themselves** — `term=screen t_Co=8`, `term=debug t_Co=` — and **nine are refused**,
recorded as `E522 term=xterm-256color t_Co=256`: the error *and* the terminal the editor
stayed on, which is what makes a refusal distinguishable from the old vacuous row. It
goes straight to `+set term=` and never to `-T`, measured: a `-T` harness run against a
binary with no `-T` records nineteen `(none)` rows, and `+{command}` is `ZERO-PLAN.md`
decision 8, the one facility promised to survive every phase.

Two things the tool had to get right, both measured. The error line **echoes the
assignment** — `E522: Not found in termcap: term=vt320` — so a naive `find('term=')`
reports the *requested* name as the result; any line carrying an `E<digits>:` has the
code taken off it and is then skipped. And the row label is `:set term=` and not
`TERM=`, or the record would say `TERM='vt320'` about something that is not the
environment at all, so `termcheck.one` is overridden as well as `termcheck.ask`.
`tools/termcheck.py` itself is untouched: it is named by `tools/whimdelta.sh` and
`tools/verify.sh` and its bytes are in every whim stage's key (rule 9).

### The re-record is the delicate part, and it is not `CLAUDE.md`'s mistake

`CLAUDE.md`'s rule is *never regenerate it from the current binary, which would make the
comparison self-fulfilling*, and the mistake it names is a pipeline re-recording from
its **own output**. `pipes/zero0.sh` does the opposite and enforces it: the baselines
come from `whim-vim.c`, the pipeline's immutable input, built with **whim's** compile
line, recorded three times and required identical. Nothing zero produces is on the
recording side. The incantation is

```sh
rm -rf .reference/zero-baselines .cache/r0 && make zero-phase-0
```

and **both paths are needed**: measured, with only `.cache/r0` removed `pipes/zero0.sh`
refuses — *"baselines DIFFER from the recorded `.reference/zero-baselines` … a harness
changed, or the frozen `whim-vim.c` did. Name which before removing it"* — and exits 1
naming `ref-term.txt`. It is right to refuse. `zero.mk`'s `zero-baselines-check` said
only `rm -rf .cache/r0`, which is correct for the MISSING case and wrong for the
changed-harness case a reader will actually hit, so its message now names both paths and
says why; `zero.mk` is in no implementation digest.

### What makes the re-record safe is measured and not cited

The baseline and every phase's recording move **together**, and `pipes/zero33.sh`
measures that: `./zero-vim` extracted from every recorded boundary tar — all 33 of them —
plus `whim-vim.c` built with whim's own line records the same table, **one digest across
every one of them** under the new question, exactly as the old question gave one digest
across every one of them. So `term-moved` stays undeclared at every phase before this
one and after it, and `tools/zcompare.py` agrees: the declared delta at every boundary is
the cumulative list through phase 11 and nothing new, checked at 6, 15, 22 and 32 by hand
as well as at all 34 by `make`. **That check is also what covers a stale tier-3 replay**:
nineteen other zero units keep their keys and would replay with a `ref-term.txt` recorded
under the old question, so section 4 re-derives, for every recorded boundary binary, the
thing such a replay would carry over.

### The instrument is proven able to fail, and the one it replaces proven not to be

With **one** row deleted from `builtin_terminals[]` — the last named row, chosen by the
program and not written into it — the new table moves exactly **one** of its nineteen
rows, `term=debug t_Co=` → `E522 term=xterm-256color t_Co=256`, and the question this
replaces, asked of the same two binaries, moves **0 of 19**: its nineteen rows carry one
distinct answer between them. That pair is the whole phase in one measurement.

**Nothing the check asserts is a number that was observed.** The table has as many rows
as `tools/termcheck.py` has names; which of them resolve is read out of
`builtin_terminals[]` in the source the phase was handed; and what a refused name leaves
the terminal as is measured from the binary, by asking it with no `+set term=` at all,
rather than written down as `xterm-256color`. So the rules stay true of the phase that
deletes eight of those names. The undefined symbol count is **reported and not pinned**
for the same reason: a number this phase cannot move is not a check, it is a thing to go
stale.

### One second change to the tool, and it is not cosmetic

Every session made a scratch directory in `/tmp` and left it there. Measured while this
phase was being written: **182,319** of them were lying about — 100,280 `termcheck-*` and
82,039 `ztermcheck-*` — and an ext4 directory that full answers `mkdir` with `ENOSPC` on
a disk with 70 GB free. That failed zero phase 9, a phase with nothing to do with
terminals, in the middle of a run of this one. `ztermcheck.py` now removes its own
directory; `termcheck.py` is whim's and slim's and is left alone.

### Measured

| | input | after |
| --- | --- | --- |
| `zero-vim.c` | 79,776 lines | **79,776, byte for byte** — `cmp`-identical |
| the boundary digest | `d2a14122ccf7` | **`d2a14122ccf7`**, its input's |
| `make editor.c` | 77,889 | **77,889**, 11 `#include`s with none above them |
| binary | 782,760 | **782,760**, `EXEC`, no `INTERP`, no dynamic section, no relocation |
| `nm -u` | 17 | **17**, reported and not pinned |
| the nineteen rows | one answer between them | **ten resolve to themselves, nine are refused with `E522`** |
| a deleted `builtin_terminals[]` row | moves **0 of 19** | moves **1 of 19** |
| records that moved | | **0 of 106** — there is no source to move them |

### Its placement

`stage 33`, `package harness 3 33` — the package that changes no source at all. Two
`uses`: `seed:0`, because the nineteen rows it re-records are phase 0's and phase 0
**refuses** to overwrite a set that differs; and `streams:5`, because the question is
`+set term={name}` on a command line with **no file on it**, which phase 5 made an
unknown option — and which is also what left the old question asking `$TERM` with an
empty buffer.

**Phase 33 can share a stage with nothing and needs no `apart` to say so**, exactly as
phase 3 does not. A stage of more than one phase is made of **split** programs and
`pipes/zero33.sh` is one file, so the schedule is refused before any check runs:
measured, `stage 33-34` gives `phase 33 is in stage 33-34 but is not an edit and a check`
from `tools/stages.sh`, and `tools/phaserun.sh` refuses the same unit with `zero phase 33
has no edit and check to run`. Nor is there a `need`: a whole-phase program is handed the
previous boundary's tree and has no edit part for a sweep to precede.

**Key movement, measured over all 170 implementation keys of the three pipelines** — 12
slim phases, 13 whim stages, 82 whim edits, 33 zero units, 30 zero edits — in a scratch
copy of `tools/` and `pipes/`, one change at a time: editing `tools/ztermcheck.py` moves
**16, every one of them zero's** (units 0, 3, 5, 9, 13, 21, 25, 26, 27, 28, 29, 30, 31,
32 and edits 5 and 25), and **adding the phase moves 0 of 170** and adds one unit — which
is what zero's phase list living in `pipes/zero.stages` rather than in
`tools/pipeline.sh` buys.

## Phase 34 — the core stops reallocating

`pipes/zero34-edit.sh` and `pipes/zero34-check.sh`, `stage 34`, `package boundary`.

**`realloc` cannot be implemented from `malloc` and `free`**, and that is why this phase
is a rewrite of two call sites rather than a seventeenth vendored function beside phase
14's sixteen. To move the old contents it has to know how many bytes the old block held,
and its interface — `void *realloc(void *p, usize n)` — does not carry that number: musl
reads it back out of the **chunk header below the pointer**, which is a fact about musl's
heap and not about C. There is no `musl_realloc` that can be written at all, because
there is nothing to give the copy for a length. The only route left is each call site
with the size **it** knows, and the phase exists because both core sites know it.

`ga_grow_inner()` already computes its own — `old_len = (usize)gap->ga_itemsize *
gap->ga_maxlen;`, on the line after the call, to zero the new tail; the rewrite hoists
that line above the allocation and copies exactly it. `get_keystroke()`'s is `buflen`
before the `buflen += 100;` immediately above the call, and the rewrite saves it as
`t_buflen` beside the `t_buf` the input already saves, so the two halves of what
`realloc`'s interface does not carry — the old pointer and the old size — sit on adjacent
lines. `void *realloc(void *p, usize n);` leaves the core's libc prototype block, **six
lines to five** — a number the check COUNTS from its input rather than states, because
phases 31 and 32 shrank the same block just before this one.

**The symbol does not leave, and that is stated as an equality because a reader will
expect otherwise.** `nm -u` is 17 names before and 17 after, the same set as a `comm`
empty in both directions, with `realloc` still among them: the third call site is
`adjust_types()`, in the formatter island phase 27 moved below the first `#include`,
which is the host's and keeps it. Phases 14, 15 and 21 each require `realloc` to be
undefined and all three still pass. Phase 28 said the same of `gettimeofday` and phase 30
of the four stdio names.

### The four traps are memory bugs and not differences, so the phase owes a harness

A recording cannot see a leak, a double free, a premature free, or an overread whose
bytes are overwritten before anything reads them. `pipes/zero34-check.sh` extracts
`ga_grow_inner()`, `musl_memcpy()`, `musl_memset()`, `garray_T` and `get_keystroke`'s
extension block **from the input source and from the output at run time**, drops both
into the same AddressSanitizer driver, and drives eight doublings from an empty
growarray, six independent first grows, a failed allocation and the 100-byte extension.
The two transcripts are identical, 32 lines, and neither reports a finding.
`B.fail r=0 same=1` is trap 2: the allocation failed, `ga_data` is the block it was, and
the grow after it reads that block back intact.

**Six of seven controls move**, each with its own named finding rather than one bucket:
copying `new_len` instead of `old_len` is a heap-buffer-overflow **read** — and it is
invisible to any recording, the overread bytes landing where the `musl_memset` that
follows overwrites them; freeing the old block on the failure path is a
heap-use-after-free at the grow that follows; `get_keystroke` copying `buflen` is a
heap-buffer-overflow; not freeing the old buffer is a LeakSanitizer report; freeing it on
both paths is a heap-use-after-free. Copying **nothing** gives no sanitizer finding at
all and is caught by the transcript, 84 bytes lost.

**The seventh moves nothing and is reported rather than hidden.** Dropping the
`if (gap->ga_data != nullptr)` guard gives a byte-identical unit transcript and no
finding, because a null `ga_data` implies `ga_maxlen == 0` implies `old_len == 0`,
`musl_memcpy` is a plain `for (; n; n--)` loop that never dereferences, and
`free(nullptr)` is a no-op. The guard is kept for what `ZERO-PLAN.md` §4c asks of the
core — that its meaning be on the page, not in what a compiler or a libc happens to
tolerate — and the check proves what it buys with a driver whose `musl_memcpy` announces
a null source: **0** from the output, **8** from the unguarded control.

**Shrinking was measured, not assumed**, because copying the OLD size is wrong if either
site can ask for less than it has. Neither can: `ga_grow_inner`'s only caller enters it
when `ga_maxlen - ga_len < n` and the three statements above the allocation only raise
`n`, `get_keystroke` adds 100 immediately above the call, and an instrumented build marks
a shrink at **0 of 106 records**. The input's own
`musl_memset(pp + old_len, 0, new_len - old_len)` already relied on it, the length being
unsigned.

### The declared delta is nothing at all, and here that is the STRONG kind

Not phase 9's (code that could not run), not 12's or 13's or 30's (code the instrument
cannot see), not 16's or 23's (a byte-identical binary), and not 29's (different answers
no record holds). `ga_grow_inner()` is on the path of every growarray in the editor: the
same instrument inserted at a line both sources have counts **4,289** calls per recording
on the input and **4,289** on the output, **2,739** of them with `ga_data == nullptr` —
trap 1 is the majority case and not an edge — in 104 of the 106 records, the two that do
not mark being `ref-pty.txt` and `ref-term.txt`. Two full recordings are byte-identical,
and the control that keeps the rewrite and copies nothing moves **102 of the 102** screen
cases.

`get_keystroke`'s extension is the opposite and the check says so: it is **unreachable**
in a recording. An instrumented build of the input marks each of the five `continue`
paths inside its loop at 0 of 106 records, so `len` never exceeds one `ui_inchar()` and
`maxlen` never falls below 10, and a pty session feeding a partial escape sequence sixty
times does not reach it either. The unit harness is the only instrument that can drive
it, and it drives both versions.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 79,776 | **79,786 (+10)** — +5 at `ga_grow_inner`, +6 at `get_keystroke`, −1 for the prototype |
| `make editor.c` | 77,889 | **77,899**, same fourteen boundary names, compared at run time |
| the libc prototype block | 6 entries | **5** — counted from the input, not stated |
| `nm -u` | 17 | **17, the same set**, `realloc` still among them |
| external symbols | `main` | `main` |
| binary | 782,760 | **782,760 bytes, and not `cmp`-identical** |
| the ASan unit transcript | 32 lines, no finding | **32 lines, identical, no finding** |
| controls that move | | **6 of 7**, each with its own named finding |
| records that moved | | **0 of 106**, with 4,289 calls per recording behind it |

### Its placement

`stage 34`, `package boundary 23 25 26 27 28 34` — because the phase's product is one
line fewer in the block phase 26 wrote and phase 27 carried. **Not `vendor`**: nothing is
vendored here, this being the case where the core stops needing a libc function that
*cannot* be vendored. Three `uses`: `seed:0` and `harness:3`, and `vendor:14`, because the
copy both rewrites make is `musl_memcpy`, phase 14's static definition — which is also
why the null guard buys nothing measurable.

**Three `apart` lines, each measured rather than predicted.** `apart 26 34` and
`apart 27 34`: both of those checks assert `void *realloc(void *p, usize n);` is on a
line of its own exactly once, and it is not any more — run against this phase's output
each reports that one prototype and only that one. `apart 30 34`, both directions,
measured when the two were adjacent: on a shared stage phase 30's check stops with *"the
output is 79776 lines and the input was 79857, a difference of 81 where 91 was
expected"*, exactly the ten lines this phase adds, and this phase's check stops with the
mirror image, *"a difference of −82 where 10 was expected"*.

**The pair that would normally need measuring — 33 and 34 — cannot have an `apart` at
all, and that is itself a measurement.** A stage of more than one phase is made of split
programs and `pipes/zero33.sh` is ONE file, so the schedule is refused before any check
runs: `stage 33-34` gives `phase 33 is in stage 33-34 but is not an edit and a check`
from `tools/stages.sh`, and `tools/phaserun.sh` refuses the same unit with `zero phase 33
has no edit and check to run`. **`need 34` is measured not to be required** — the edit was
run on phase 30's unswept output, 79,858 lines against the swept 79,776, and every anchor
and every count held — and it could not be exercised anyway, a phase whose predecessor can
never share its stage being handed a boundary either way.

## Phase 35 — the core calls nothing but the host

`pipes/zero35-edit.sh` and `pipes/zero35-check.sh`, `stage 35`, `package host`. The three
libc functions the core still **called** for itself go to the host: `malloc`, called by
`lalloc()`; `free`, called by `vim_free()` and `update_wincolor()`; and `write`, called by
`mch_write()` — and, since phase 34 rewrote `realloc` as a malloc, a copy and a free, by
`ga_grow_inner()` and `get_keystroke()` as well.

Above the first `#include`, which since phase 27 **is** the boundary, `malloc` was 4
mentions, `free` 5 and `write` 2: each a declaration in the core's one run of ordinary,
non-`static` declarations, plus its call sites. All three are **0** now, and below the
boundary they are 1, 2 and 2 where they were 0, 1 and 1. Three `static` prototypes go in
the block phase 25 made one run of eleven, so the core → host boundary is still **one**
block of declarations and not a block plus three:

```c
    static void *host_alloc(usize n);
    static void host_free(void *p);
    static int  host_write(const char *s, int len);
```

and three definitions below the boundary make the same libc calls with the same
arguments.

### Not one of those counts is written down, and the reason is that they were once

This phase first asserted `malloc` 2, `free` 3 and `write` 2, the counts measured on the
boundary it was written against. **Phase 34 then rewrote `realloc` at two core sites and
took them to 4 and 5, and the anchors refused** — which is what counted anchors are for,
and better than the alternative. But a count is a fact about a tree that was measured and
a **partition** is a fact about the tree that arrives, so both programs now assert the
SHAPE: every mention of each name above the boundary is its own declarator or a call of
it; the declaration goes, every call is rewritten, and how many there are is read off the
text. A mention that is neither — an address taken, a variable of the name — **refuses**
rather than surviving into a file whose declaration is gone. That is `CLAUDE.md`'s rule
under *Rename a name across the whole file*, and it is what made phase 34 cost this phase
a re-run rather than an edit.

### The wrappers are faithful and not improved

This is the trap the phase could have fallen into with no recording seeing it.
`mch_write()` is `vim_ignored = (int)write(1, (char *)s, len);` — **one** `write(2)`, no
loop, the count assigned to the variable this tree keeps for results it means to ignore. A
short write LOSES those bytes today and `host_write()` loses them too: a wrapper that
looped would be a behaviour change in a phase that declares none, and output that silently
truncated under load is the worst outcome available here. `host_alloc()` returns what
`malloc()` returned, `nullptr` included, so `lalloc()`'s `clear_sb_text()` /
`do_outofmem_msg()` failure path is reached exactly as before; `host_free()` calls
`free()`, so it is null-safe for `free()`'s own reason — the core does not rely on that
(`vim_free()` tests `x != nullptr`, `update_wincolor()` frees only the arm it allocated,
and **0 of the corpus's 22,417 frees are null**) but the wrapper inherits it rather than
adding a test. `host_write()` **drops the descriptor** because its two neighbours on this
boundary already have: phase 20's `musl_read_input(char *, int)` reads fd 0 inside the
host and phase 21's `host_message(msg, len, err)` chooses its stream from a flag. A
descriptor is the host's idea of where the screen is; `host_write(s, len)` is the core's.

### Nothing is freed and the phase says so as an equality

`nm -u` is the same set in and out, a `comm` empty in both directions — 17 names with
zero's own flags, 18 as `tools/symbols.sh` counts — with `malloc`, `free` and `write`
still in it. That is this pipeline's own rule read back: **a symbol leaves when its last
CALLER leaves the file**, and inside one translation unit moving a call from the core into
the host moves no caller out. Phase 28 is the contrast, freeing `gettimeofday` because the
last caller went with it.

**What does move is the thing `nm -u` cannot show.** `make editor.c`'s cut — 77,899 lines
either side, a byte prefix of the file, 0 errors under `-fsyntax-only` — has a warning set
that IS the core → host interface, every name `used but never defined`, and it goes from
**14 names to 17**. `host_alloc`, `host_free` and `host_write` arrive and nothing leaves.
An implicit libc dependency hidden in a bare declaration becoming an explicit named call
is the point of the boundary, and an interface growing by exactly three is what that looks
like. The input's set is computed in the check at run time and never written down: a
written list has gone stale twice in this pipeline already.

### The declared delta is nothing at all, and here the recording is STRONG evidence

Two full `tools/zrecord.sh` recordings, `diff -r` empty across all 106 records. `lalloc()`
and `vim_free()` are on the path of essentially everything the editor does and
`mch_write()` is every byte it draws, so the corpus hammers all three. Measured on an
instrumented build of this phase's own output, over the 102 screen cases and marking every
one of them: **53,848** `host_alloc` calls with the largest 319,968 bytes; **22,417**
`host_free` calls with 0 null; **1,012** `host_write` calls with the largest 2,063 bytes
and 0 short. A by-hand session, `+normal 200000ax`, makes 400,475 `host_alloc` calls
against 479 for `ihello world<Esc>`, and frees 400,188 of them.

**And it can fail, once for each function — with two controls that move nothing, reported
and not hidden.** `host_alloc` returning `nullptr` always moves 106 of 106 records;
refusing only allocations above 200,000 bytes — in this editor exactly ONE, the screen —
moves 100 of 102 screen cases, the survivors being `ctrl_c_clean` and `ctrl_c_changed`,
which exit before a key is looked up. `host_write` writing HALF THE BYTES moves 102 of
102, and `host_write` writing every byte and REPORTING half moves **0 of 102**, which is
the phase's claim about the return value measured rather than argued. `host_free` doing
nothing at all moves 0 of 102, because a leak is invisible to a 106-record corpus; the
instrument is what says `host_free` is called, and the check says so in those words
instead of presenting a silent control as evidence. `host_free(nullptr)` on every draw
moves 0 of 102 and writes nothing.

**The `static` trap is built both ways.** `nm --extern-only --defined-only` is still
exactly `main`: with the keyword off the three prototypes gcc refuses — *"static
declaration of 'host_alloc' follows non-static declaration"* — and with it off the
prototypes AND the definitions the build is silent and the object defines `host_alloc`,
`host_free`, `host_write` and `main`. Deleting the three prototype lines gives 9 errors
naming all three, which is what makes them load-bearing rather than decorative.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 79,786 | **79,804 (+18)** — three prototypes and three five-line definitions with their blanks |
| `malloc` / `free` / `write` above the boundary | 4 / 5 / 2 | **0 / 0 / 0** |
| the same three below it | 0 / 1 / 1 | **1 / 2 / 2** |
| the core's plain libc prototype block | 5 lines | **2** — `getpid` and `kill` |
| `make editor.c` | 77,899 | **77,899**, 0 directives, 0 errors |
| the boundary | 14 names | **17**, computed at run time on both sides |
| `nm -u` | 17 | **17, the same set** — `malloc`, `free` and `write` all still in it |
| external symbols | `main` | `main` |
| binary | 782,760 | **782,760 bytes, 206,588 of them different** |
| `cmdnames[]` / `options[]` rows | 98 / 107 | 98 / 107 |
| records that moved | | **0 of 106**, against 53,848 + 22,417 + 1,012 instrumented calls |

### Its placement

`stage 35`, `package host 17 18 19 20 21 30 32 35` — a thing the core did for itself
becomes a thing it asks the host to do, declared in the one host block and defined below
the boundary. Four `uses`: `seed:0` and `harness:3`; `boundary:25`, a `static` forward
declaration above and a `static` definition below being all a direct call to the host
needs, which is that phase's finding; `boundary:27`, because *above the boundary* and
*below it* are a LINE NUMBER in this check and phase 27 is what made that line the split;
and `boundary:23`, because `host_alloc(usize n)` is spelled in the core's own type names
and a signature in `size_t` would name something no header above the boundary declares.

**Six `apart` lines, every one a measurement.** 26 and 27 carry a nine-entry `PROTOS` list
and require each `\n<prototype>\n` exactly once: on this output **two** are at 1 — `getpid`,
`kill` — and **seven** at 0, the three phases 31 and 32 took, `realloc` which 34 took, and
this phase's three; and 27 builds a control by putting `static ` in front of the `malloc`
prototype, which is no longer there to put it in front of. 27 and 28 write the boundary out
as a list of names and require the cut's warning set to be exactly it, and this phase makes
it seventeen where 32 made it fourteen.

**`apart 34 35` was measured as a REAL SHARED STAGE** — r33 restored, both edits, one sweep,
both checks — and phase 34's check stops four ways. The first two are its prototype block:
*the core's plain libc prototype block is 2 lines and the input's was 6, a difference of 4
where 1 was expected*, and *the prototype block lost [long write(…) / void \*malloc(…) /
void \*realloc(…) / void free(…)] and not realloc's line alone*. The other two are
`apart 22 23`'s lesson landing on the phase that had just taught it: *ga_grow_inner's
rewrite is not in the output exactly once*, and the same for `get_keystroke`'s, because
phase 34's check matches the code it wrote VERBATIM — `pp = malloc(new_len);`,
`free(gap->ga_data);` — and this phase renames exactly those calls. **A check that quotes C
is a dependency on the spelling**, and here the quoting phase and the respelling phase are
adjacent. One direction only: phase 35's check was then run on that same tree and every
part of it held.

`apart 30 35` is the same rule one level deeper, and it is kept from an earlier base
because it is the clearest instance of it: phase 30's check writes
`write(2, "T-cleos\n", 8);` INTO THE CORE to build an instrumented control, and relied on
the core's own declaration of `write` — so run as a pair it does not compile at all.
**A check that CALLS libc from above the boundary is a dependency on the core still
declaring it.** There is **no `need 35`**, measured three times — on phase 30's unswept
output, on phase 32's and on phase 34's — the partition holding identically each time.

### What this phase does not yet claim

The sentence this arc has been building to — that the core calls no libc function at all,
every outward call a `musl_` or a `host_` — is **not** stated, because it is not true of
this tree. `getpid` and `kill` remain, two lines of prototype and three call sites:
`mch_get_pid()`'s `getpid()`, and `vim_handle_signal()`'s `kill(getpid(), got_signal)`,
which re-raises a deferred deadly signal. The phase is written so that the claim becomes
true without another edit — the block is FOUND rather than assumed, the lines this phase
owns are taken out of whatever run holds them, the residue is printed, and when the residue
is empty the edit drops the block's trailing blank line with it — but **the phase that
takes those two is the one that gets to write it down.**

### What zero-vim is after phase 35

```
zero-vim.c        79,804 lines          from whim-vim.c's 86,614  (-6,810, 7.9%)
                  77,899 above the boundary, 1,905 below it
functions         1,759
type definitions  908
DWARF enumerators 1,189
cmdnames[] rows   98    (create_cmdidxs floor 80; 18 rows of margin)
nv_cmds[] rows    194   (nvidxcheck: a permutation)
options[] rows    107, 95 distinct globals  (orphanopts floor 80; 15 of margin)
#include          11, at line 77,901, and NOT ONE DIRECTIVE above them
core -> host      17 names: vim_snprintf, host_exit, host_message, host_time,
                  host_alloc, host_free, host_write, ten musl_*
libc prototypes   2 in the core: getpid kill
libc symbols      17 with zero's flags, 18 as tools/symbols.sh counts
binary            782,760 bytes, EXEC, no INTERP, no dynamic section, no relocation
declared delta    nothing since phase 11 -- 2 stderr-moved and the records of 4 to 11
make editor.c     77,899 lines: 0 directives, 0 errors, 17 warnings, all of them
                  `used but never defined` and all of them the interface
```

**Fifteen phases in a row have declared nothing** — 21 through 35 — and the kinds of
evidence that stand in for a recording are named rather than counted here; the one
numbered list is `CLAUDE.md`'s, and the taxonomy is written out at the end of phase 39.
**Phase 33's is a kind new with it, and it is phase 3's**: the phase changes no source at
all, so nothing about the editor's behaviour *can* have moved, and what has to be argued
instead is that the **comparison** moved safely. 34 and 35 are the strongest instance of a kind the pipeline already had —
two byte-identical recordings — because what they touch is on the path of everything:
34's `ga_grow_inner` at 4,289 calls a recording, 35's `lalloc`/`vim_free`/`mch_write` at
53,848, 22,417 and 1,012 over the screen cases, each with a control that moves 102 of 102
to say so. **Fifteen of the seventeen libc symbols are now
called from the host and from nowhere else**: `malloc`, `free` and `write` joined them
here, `time` at 32 and `gettimeofday` at 28, and `__errno_location` is gcc's own for the
host's `errno`. **The two that are not are `getpid` and `kill`.** What the core still does
for itself is one re-raise of a deadly signal and one `getpid()` that fills a `b0_pid`
nothing reads.

## Phase 36 — the core names no libc function at all

`pipes/zero36-edit.sh` and `pipes/zero36-check.sh`, `stage 36`, `package host`. Phase 35
ended with a sentence it would not write down, and this is the phase that gets to write
it. The core's block of ordinary, non-`static` declarations — the libc the editor spells
out by hand since phase 27 put the headers below it — was two lines, and both go:

```c
    int getpid(void);
    int kill(int pid, int sig);
```

**They are reached two different ways and only one of them needed a host call**, which is
the whole shape of the phase. `getpid` is **avoidable outright**. `mch_get_pid()` is
`return (long)getpid();` and had exactly one caller, `long_to_char(mch_get_pid(),
b0p->b0_pid)` in `ml_open()`; `b0_pid` is the process id written into block zero of a swap
file and had exactly two mentions in the whole file, its own declaration and that write.
It is **write-only, and not by anything zero did** — `whim-vim.c`, this pipeline's
immutable input, already has exactly those two, whim having taken the readers with
recovery. So the write goes, `mch_get_pid()` goes with it because the declaration it needs
is going, the sweep takes the forward declaration and the field, and `getpid` leaves the
core with nobody calling a host at all. Zero phase 20 saw it coming and said so in as many
words: *"`b0_pid` is written and never read, so one line frees it whenever block zero is
somebody's phase"*.

`kill` is **moved**. Its one core site is `vim_handle_signal()`'s `kill(getpid(),
got_signal);`, re-raising a deadly signal that arrived while the editor was not reading,
and it becomes `host_raise(got_signal);` — `static void host_raise(int sig);` at the end
of the single run of core → host prototypes phase 25 made one block of eleven, and a
definition inside the host region that calls `kill(getpid(), sig)`. **The deferral is not
dropped**: the blocked/`got_signal` mechanism is exactly what it was, so the core still
decides *when* the signal acts and only the raising crosses the line. **It takes no pid**,
which is phase 35's rule for `host_write` and phase 20's for `musl_read_input` applied
here: a core that can no longer ask for its own process id must not be handed one. And it
is spelled `kill(getpid(), sig)` and not libc's `raise()`, because `raise` has not been an
undefined symbol of this file since phase 20 and a wrapper reaching for it would **add** a
libc symbol in the phase whose subject is the core's last two.

### The claim is measured from the cut and not from the block, and those are two assertions

An empty block is a fact about a paragraph. *The core names no libc function at all* is a
fact about everything above the first `#include`, and the two are not the same sentence,
because **a bare `extern` declaration is invisible to the cut's ordinary check**: gcc
warns `'X' used but never defined` for a `static` function and says nothing whatever about
an ordinary one. That is exactly how two libc names sat above the boundary for nine phases
without the interface set noticing them.

So the check compiles `make editor.c`'s cut to an **object** and takes `nm -u` of it,
which is the set of names the core needs from outside *itself*: **19 in, 18 out**, and
every one of the 18 defined below the boundary in this same file, computed from the text
and listed nowhere. The identical computation on the input finds two that are not —
`getpid` and `kill` — and **that control is what keeps the emptiness from being two
numbers agreeing**. Neither cut defines an external symbol either: `main` is below the
boundary and is the host's.

### The phase frees no symbol and says so as an equality

`nm -u` is the same set in and out, a `cmp` in both directions, and `getpid` and `kill`
are both still in it: `host_raise()` calls both where `vim_handle_signal()` did,
`musl_suspend()` calls `kill` as well, and **a symbol leaves when its last caller leaves
the file**. What moves is the thing `nm -u` cannot show — the cut's warning set, the
core → host interface, from **17 names to 18**, `host_raise` arriving and nothing leaving.

And the thing no tool but `tools/zhostonly.py` can show: **above the boundary the core's
whole remaining vocabulary of the host is two words**, `SIGHUP` three times and `SIGTERM`
three, the two deadly signals the editor names because it **prints** them. The input said
`getpid` three times and `kill` twice as well, and those were the only mentions of any
host word in the core that were not a message. The tool reports 6 of its 18 named
exceptions live, and all six are that message.

### The fold this phase was asked to take does not exist, and the check says so

Phase 17 removed `deathtrap()`'s `entered >= 3` ladder as code no build of zero-vim could
reach, which leaves `entered` able to reach 2 and no further, and the question put to this
phase was whether that makes anything around the `if (entered == 2)` arm foldable.
Measured, it does not: **`entered` has exactly three reachable values and every one of
them is read.** 0 is read by the entry guard `if (entered == 0 && ...)`, which
distinguishes a first entry from a nested one; 1 and 2 are told apart **twice** — by the
double-signal arm, which calls `getout(1)` and never returns, and by `v_dying = entered;`,
whose value reaches `getout()`'s two `if (v_dying <= 1)` tests and selects the buffer
cleanup there. No two of the three states are interchangeable, so there is nothing to
fold. The non-fold is asserted as a byte comparison: `deathtrap()` is identical in and out
at 38 lines either side, and `vim_handle_signal()` differs in exactly one line.

### The declared delta is nothing at all, and the two halves are blind for opposite reasons

It is phase 2's kind and phase 12's — the code **runs** and the instrument cannot see it —
so the phase owes probes and builds six binaries of its own. That the corpus cannot see
either half is measured. An instrumented build of the input, over all 102 screen cases and
marking every one: the `b0_pid` write runs in **102 of 102** cases, 102 times in all, being
on the path of every buffer the editor opens, and the recording still does not move,
because nothing reads the field. The re-raise fires in **0 of 102**: nothing in the corpus
sends the editor a deadly signal, so `got_signal` is never set and the deferral has
nothing to re-raise. `vim_handle_signal()` itself is entered 4 times in 2 cases, which is
**reported and not pinned**, this phase being unable to move it — `ui_inchar()` calls it
only around a wait longer than 100 ms, and a corpus whose stdin is a file of keystrokes
almost never waits.

**So the two controls are on the one line the phase deletes**, and they are the phase
itself rather than a borrowed anti-vacuity check. That line replaced by `return FAIL;` —
the same line, in the same place — moves **106 of 106** records, so the corpus really does
execute it and the empty `diff -r` is not the corpus missing the code. The same line
writing a **constant** instead of the pid moves **0 of 106**, which is *`b0_pid` is
write-only* measured rather than argued, and a control that moves nothing is reported here
and not quietly dropped.

**The probe the other half owes is a forced deferral**, driven identically into both
binaries: `(void)vim_handle_signal(SIGTERM);` with `blocked` still TRUE and then
`(void)vim_handle_signal(-2);`, appended to `mch_init()` — exactly the path
`kill(getpid(), got_signal)` was on and `host_raise(got_signal)` is on now. Input and
output agree in every byte of stdout (48), stderr (0) and status (1), and the screen
carries `Vim: Caught deadly signal TERM` and `Vim: Finished.`. It can fail twice, and
identically on both binaries: with the re-raise **deleted** the deferred signal is simply
lost and the editor runs on to end of input (157 bytes), which says the probe goes through
the line this phase rewrites; and with the re-raise given `SIGHUP` instead of the signal
that was deferred the screen says `Caught deadly signal HUP` (47 bytes), which says the
**argument** crosses the boundary and not merely the call.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 79,804 | **79,799 (−5)** |
| the core's plain libc prototype block | 2 lines | **0 — the block is gone** |
| `nm -u` of the **cut**, compiled to an object | 19, two of them libc | **18, every one defined below the boundary** |
| `make editor.c` | 77,899 | **77,888**, 0 directives, 0 errors |
| the boundary's warning set | 17 names | **18**, computed at run time on both sides |
| `nm -u` of the whole file | 17 | **17, the same set** — `getpid` and `kill` still in it |
| external symbols | `main` | `main` |
| host words in the core (`zhostonly.py`) | `SIGHUP` 3, `SIGTERM` 3, `getpid` 3, `kill` 2 | **`SIGHUP` 3, `SIGTERM` 3** |
| the `#include`s | line 77,901 | line **77,890**, the same eleven consecutive lines |
| binary | 782,760 | **782,760 bytes, 397,978 of them different** |
| `cmdnames[]` / `options[]` rows | 98 / 107 | 98 / 107 |
| records that moved | | **0 of 106**, against a write executed 102 times |

### Its placement

`stage 36`, `package host` — a thing the core did for itself becomes a thing it asks the
host to do, or stops doing. It belongs beside 30, 32 and 35 rather than in `boundary`,
which is about drawing the line and about the core's own spelling of types and constants.
Four `uses`: `seed:0` and `harness:3`; `boundary:25`, the one prototype going at the end
of the single run of core → host declarations that phase made of eleven; and
`boundary:27`, because the whole claim is stated as a property of the **cut**, and the
first `#include` is the line between core and host only because 27 moved the eleven
directives below the core.

**One `apart` line, measured as a real shared stage**, r34 restored with both edits, one
sweep and both checks: phase 35's check stops three ways, the first being the block this
phase exists to empty — *the ordinary declarations above the boundary are none and the
input's block minus the three is `int getpid(void); / int kill(int pid, int sig);`* — then
*the file is 79799 lines and the input was 79786 — expected 18 more*, and *the boundary
moved from line 77901 to line 77890, and it must not*, which is phase 35's own statement
that it moves no line above the first `#include`. One direction only: phase 36's check was
then run on that same tree and every part held. **Six further `apart` lines are not
written, with the reason.** Phases 26, 27, 28, 30, 32 and 34 all have checks this output
breaks — 26's and 27's nine-entry `PROTOS` list reaches **zero of nine** on it, which is
this arc read from the losing side — but every one of them is already broken by phase 35
and recorded against it, and any stage holding 36 and one of the six would have to hold 35
too. **A redundant `apart` nobody measured is worse than none.** No `need 36`, measured in
the same run on phase 35's unswept output.

`tools/zhostonly.py` gains `getpid` as a host word and three named exceptions, and the
`vim_handle_signal:kill` exception gains a 0 beside its 1 — a count there is a **tuple**
of the values it takes, one per phase that runs the tool, because the core's vocabulary
shrinks between them. Measured, the cost of that tool edit is **20 zero keys and no whim
or slim key**: the units and the edits of phases 20, 21, 25, 26, 27, 28, 30, 32, 34 and
35, with all 107 whim unit, whim edit and slim phase keys byte-identical either side.
`make whim-verify` (13 of 13) and `make slim-verify` (12 of 12) are the gate rule 9 asks
for, and both were green.

## Phase 37 — the degenerate unions go

`pipes/zero37-edit.sh` and `pipes/zero37-check.sh`, `stage 37`, `package tidy`. Thirteen
`union` keywords in `zero-vim.c`, and **six of them union nothing with anything**. Five
are single-member — `u_header`'s `uh_next`, `uh_prev`, `uh_alt_next` and `uh_alt_prev`,
each `union { u_header_T *ptr; }`, and `typval_S.vval`, `union { varnumber_T v_number;
}` — and the sixth is **empty**, `union { } es_info;`, with one mention in the whole file
and no use at all.

Every one is a leftover of a cut already made. The `u_header` unions had an arm that named
a **swapfile block number** and it went with the swapfile; `vval` had nine arms and has had
one since the eval layer went; `estack_T.es_info` was a `ufunc_T *` beside an `sctx_T *`
and both went the same way. **A variant type with one variant is a value with a longer
spelling, and a variant type with no variants is a GNU C extension ISO C forbids** —
`ZERO-GOAL.md`'s core is what a transpiler reads, so both cost a reader something and
neither buys anything.

### Which six is computed, not listed

The edit scans for `union`, matches the braces, counts the member declarations at depth 1
and takes every union with fewer than two as degenerate — and it must find **both kinds**,
so a scanner that stopped matching cannot pass by finding nothing. Measured on r36: 1
member for `uh_next`, `uh_prev`, `uh_alt_next`, `uh_alt_prev` and `vval`, **0** for
`es_info`, and 2 or 3 for `ae_u`, `lv_u`, `os_oldval`, `os_newval`, `rs_u`, `se_u` and
`rs_un`, which stay byte for byte and whose text is required to occur once in both files.
Thirteen keywords become **seven**.

A single-member union becomes its member **carrying the union's name** — the replacement
text is the member's own declaration, so the type, the stars and the spacing are the
input's — and every `uh_next.ptr` becomes `uh_next`. The empty one is deleted outright.

### A partition and not a count

For each of the six, every mention outside a string literal must classify as **its own
declaration** or a **`.member` access on it**, and a mention that is neither refuses: a
whole-union assignment, a `sizeof`, a designated initialiser, or another struct with a
field of the same name and a different member would each stop the phase. Measured on r36:
`uh_next` 1 + 27, `uh_prev` 1 + 23, `uh_alt_next` 1 + 28, `uh_alt_prev` 1 + 26, `vval`
1 + 19, `es_info` 1 + 0, with nothing left over — **identical to what the same computation
gives on r35**, so phase 36 moved nothing of this phase's. Those numbers are read off the
text by both the edit and the check and written into neither, which is the lesson phase 35
was taught when phase 34 moved its counted anchors.

The rewrite is literal-aware and **single-pass**: 129 spans computed against the original
text and applied together, over 6,707 literals none of which holds any of the six names,
because a second pass would index spans computed on the first pass's output — phase 23
measured five of 437 `size_t` left behind that way.

### The evidence is that the binary is byte-identical, and the control is what makes it evidence

A union of one member has the size, the alignment and the offset of that member, and an
empty union contributes no storage, so no layout moves and `uh_next.ptr` and `uh_next`
name the same object at the same address. **782,760 bytes either side**, both built with
`SOURCE_DATE_EPOCH=0` and the boundary's own flags — tier 1 of `CLAUDE.md`'s verification
table, which subsumes every screen case, Ex-command row, command line and pty scenario at
once, because the program that would be run is literally the same program.

Two numbers agreeing prove nothing on their own, so **`c1` is built from the input's own
text**: this phase's output with the two fields it *promotes*, `uh_next` and `uh_prev`,
**exchanged** — a pure layout permutation of the very struct it rewrites. It builds and
differs in **31,056 bytes**, so the binary is demonstrably sensitive to that struct's
layout. Two further controls move nothing and are **reported rather than dropped**: `c2`
puts the empty union back and `c3` runs the phase backwards on `vval` with all 19
`.v_number` accesses, and both are byte-identical. That is the claim stated in the only
direction a control can state it in. All three are built from the input's own text and
never from C quoted in the check, because **a check that quotes C is a dependency on
spelling** (`apart 22 23`).

### The empty union's dialect argument is measured, not asserted

gcc reports `union has no members [-Wpedantic]` **once** on the input and not at all on
the output, and the rest of the pedantic diagnostic set does not move — 199 → 198, a
difference of exactly one. A minimal probe confirms the construct is a hard **error**
under `-pedantic-errors` and that the identical struct with a one-member union is silent:
the probe proving it can pass, in the same run.

### The declared delta is nothing at all, and it is the strongest kind and not the weakest

`pipes/zero.delta` gets a comment and no line. This is phase 16's and phase 23's kind — a
`cmp` of the binary — so the phase owes no probes, unlike 20 and 22, and asks nobody to
believe a replacement does what an original did, unlike 14 and 15. Two full
`tools/zrecord.sh` recordings are identical across all 106 records, and the check says in
those words that **with a byte-identical binary that is a check on the harness and not on
the phase**; it is not offered as the evidence.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 79,799 | **79,786 (−13)**, every one above the boundary |
| `union` keywords | 13 | **7**, computed |
| `make editor.c` | 77,888 | **77,875**, 0 directives, 0 errors |
| the boundary | 18 names | **18**, computed from the input at run time |
| `nm -u` | 17 | **17**, a `cmp` in both directions |
| external symbols | `main` | `main` |
| binary | 782,760 | **782,760 bytes, and the same bytes** |
| `cmdnames[]` / `options[]` rows | 98 / 107 | 98 / 107 |
| records that moved | | 0 of 106 — the harness, not the evidence |

### Its placement

`stage 37`, `package tidy 13 37 42` and **not `dialect`**: five of the six are leftovers of
earlier cuts, which is phase 13's kind, and only the sixth has a dialect argument.

**It was for a while the one phase after the seed with no `uses` line at all**, and that
looked defensible — its evidence is a `cmp` and not the recording, so it does not rest on
phase 0's baselines the way every other empty declaration does. **It was still wrong.**
`pipes/zero37-check.sh` names `tools/zerodelta.sh` twice, the delta check runs at its stage
end like every other phase's, and the two **other** `cmp`-evidenced phases, 16 and 23, both
declare the dependency — five `uses` lines and six respectively. So the line is written now,
with the reason it was missing recorded in it. It was found by a documentation pass and not
by anything failing, which is the property of `pipes/zero.stages` worth saying plainly: the
file is read by `tools/stages.sh` and `tools/packages.sh` and **named by no phase program**,
so `tools/implhash.sh` never hashes it. **A manifest edit is free, which is why package and
`uses` data can be kept honest without paying for a repass — and it is also why a wrong one
is never caught by anything running. The only guard on that file is a reader.** Measured
either side of the correction: slim 9, whim 13-41, zero 37 and zero 44 are byte-identical,
and both manifest checks pass.

**`apart 36 37` is written and was measured in both directions**, as a real shared stage on
r35, which 36 and 37 make possible by both being split. Phase 36's check stops first, with
*the file is 79786 lines and the input was 79804 (79804 recorded) — expected 79799* and
*the boundary moved from line 77901 to line 77877*: 36 states its arithmetic as a line
count and 37 takes 13 more. The other direction was **observed rather than reasoned**, by
running phase 37's check on exactly the tree and state directory the driver would have
handed it next: *the file is 79786 lines and the input was 79801 — the six declarations are
13 lines shorter between them*, then *the boundary moved by 15 lines and the file by 13*.
**The two extra lines are phase 36's residue** — `static long mch_get_pid(void);` and the
`b0_pid` member, which 36 deliberately leaves for the sweep — landing inside phase 37's
arithmetic because a stage sweeps **once**, at the end. The general form is now in the
manifest: *a phase that states its line count against its own edit cannot share a sweep
with a phase that leaves work for it.*

No `need 37`, measured in the same run: the edit was handed phase 36's **unswept** output
and every part held, at exactly the counts it gets on swept text. It asserts no count a
sweep can move. Adding the phase moved no existing implementation key — 144 whim, slim and
zero keys identical either side, with only z37 new.

## Phase 38 — the eight terminal names go, leaving two

`pipes/zero38-edit.sh` and `pipes/zero38-check.sh`, `stage 38`, `package terminal`.
`builtin_terminals[]` is the whole of what the core knows how to draw on: a name and a
capability table, ten times. **An embeddable core has no business carrying ten terminal
descriptions** — the host decides what it is attached to — so this phase keeps **two**:
`xterm-256color`, which is already the name `termcapinit()` substitutes when it is given
none, and `debug`, which draws its capabilities as text and is the only one readable
without a terminal at all. Which rows go is **the table minus the two**, computed from the
source; the two are the only names the phase writes down.

### This is the first zero phase to declare `term-moved`

The token has been in the delta grammar since phase 0 and no phase had used it, because
the terminal table was nineteen ways of recording that the environment decided nothing —
until zero phase 33 changed the question to `+set term={name}`. And **phase 33 exists
because a prototype of this cut passed `tools/zcompare.py` declaring nothing at all**. So
the declaration is a real delta and not a harness artefact, which is the distinction rule
2 and `CLAUDE.md`'s *A phase can break a harness rather than change behaviour* exist to
keep apart, and this phase is on the other side of it from phase 5's.

`pipes/zero.delta` states which **eight** of the nineteen rows move and to what, because
the token itself is whole-file: `xterm`, `screen`, `screen-256color`, `tmux`,
`tmux-256color`, `vt100`, `ansi` and `dumb`, each from `term=<itself>` to `E522
term=xterm-256color t_Co=256` — the answer the eight names that never had a row already
gave. The other eleven are byte-identical: `xterm-256color` and `debug` still resolve, the
eight unknown names were refusals already, and `''` is still `E529`, which is `'term'`
refusing an empty string before any table is consulted.

### Three things the cut drags with it, and none of them is in the row list

**Three capability tables lose their last row** — `builtin_ansi`, `builtin_vt100`,
`builtin_dumb` — and the sweep takes them, 103 lines. That set is **computed**, *a
`builtin_*` table whose only mention left is its own definition*, and the count is taken
on text whose string literals are blanked: `builtin_xterm` is also a string literal inside
`vim_is_xterm()`, and a count that read that as a reference would report a live table
dead.

**`find_builtin_term()`'s xterm-family special case can never fire again.** It is
`strcmp(name, "xterm") == 0 && vim_is_xterm(term)` — a test on the **row's** name — so once
no row carries that name its first conjunct is false for every row. gcc has no warning for
a condition false at run time and nothing in `tools/sweep.sh` reads one, so it goes in the
**edit**. It is dead twice over, measured: the output with the clause restored records byte
for byte what the output records, and the same marker inside it, written through
`host_message()`, is in **102 of 102** screen records on the input and **0** here. And the
finding a reader would not predict is that **every startup of the input resolved through
that clause** — the compiled default is `xterm-256color`, the `xterm` row sorts before it,
and `vim_is_xterm()` says yes — so the surviving row was never reached until now, and it
gives the same table.

**And `set_termname()`'s no-screen fallback named one of the eight.** An unknown name is
refused at run time (E522, the terminal left alone) but *before there is a screen* — the
`-T {term}` path — it is replaced by a name written in the source, and that name was
`"xterm"`. Left alone the cut would have left it dangling, and that was measured rather
than reasoned: with the repair left out, `-T xterm` and `-T no-such-term-9x` print `E437:
Terminal capability "cm" required` and draw **2,045 bytes where the baseline draws
2,117** — an editor with no cursor motion. The phase retargets the fallback onto
`termcapinit()`'s compiled default, computed from that function and required to be a
surviving row, and rewrites the message in the same step, because **nothing in the build
checks that a message tells the truth**. With the repair those two rows are the baseline's
again and `term-moved` is the whole difference; the check builds the repair-left-out form
as a control and requires it to move exactly those two records and no others.

### The edit is a partition and not a count, and it has to be literal-aware

A terminal name here is a string literal, and the same words appear as identifiers
(`builtin_xterm`), as prefixes (`musl_strncasecmp(name, "xterm", 5)`) and inside other
literals (`"screen.xterm"`). Every literal whose **content equals** a removed name must
fall in one of four classes — its row, the family clause, the fallback, or a counted
prefix test in `vim_is_xterm()` — and a leftover refuses. Measured on the input: 11
literals, 8 + 1 + 1 + 1. The prefix class is the only one kept, and keeping it is honest
because each must be an argument of a comparison with **its length written out**, so a
name compared in full could not hide there. All the text edits are applied in one pass
over the original offsets.

### The instrument is shown able to fail in both directions

On this phase's own output, with both rows derived from the tables and neither written
here: deleting the last row the output names moves exactly **1 of 19**, resolving →
refused, and putting the first removed name back moves exactly **1 of 19**, refused →
resolving. A cut of eight that moved seven or nine would have been seen.

### The phase owes probes the nineteen rows cannot give

Because the `xterm` row was the whole xterm **family** and not one name. Six prefixes read
out of `vim_is_xterm()` in the source the phase was handed — `xterm nxterm kterm mlterm
rxvt screen.xterm` — every one resolved before and every one is `E522` now, and **not one
of them is among the nineteen**. `xterm-kitty`, which that function already excluded, was
E522 either way. `:set term=builtin_xterm` is the same finding through `term_is_builtin()`,
which strips the prefix and leaves `xterm`.

### Nothing is freed, and the check says why rather than presenting it as a disappointment

`nm -u` is the same 17 symbols, a `comm` empty in both directions: **this phase deletes
data** — three static arrays and eight rows — **and data calls nothing**.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 79,786 | **79,668 (−118)** |
| `builtin_terminals[]` rows | 10 | **2**, computed as the table minus the two kept |
| `builtin_*` capability tables | 9 | **6** — three taken by the sweep, 103 lines |
| `make editor.c` | 77,876 | **77,758**, 0 directives, 0 errors |
| the boundary | 18 names | **18**, computed from the input at run time |
| `nm -u` | 17 | **17**, a `comm` empty both ways |
| binary | 782,760 | **781,096** |
| terminal rows that moved | | **8 of 19**, each `term=<itself>` → `E522 term=xterm-256color t_Co=256` |
| screen cases / Ex rows / command lines / pty scenarios | | **0 of 102, 0 of 98, 0 of 30, 0 of 4** |

The cut was stated here as its own check counted it, and that was **one more than phase
37's 77,875 on the same file**: this check took the naive `awk` prefix and phase 37's
takes `zero.mk`'s rule, which drops the cut's trailing blank line. Both are the same text.

**That has since been repaired in both programs, and the repair is worth stating because
the defect was a comment.** `pipes/zero38-check.sh`'s header said the cut was *"zero.mk's
own rule"* while the `awk` beside it was not — and 39 had the same line, and is where the
next phase would have copied it from. **A comment that claims to be the rule and is not is
the thing that propagates.** Both now carry the rule entire, `{ a[NR] = $0; if (NF) last =
NR }` and then print up to `last`, with the reason written beside it; so consecutive phase
commits no longer report cut figures that differ by one **on the same files**, where a
reader comparing them saw an off-by-one that was in neither phase. The figures above are
the numbers those checks printed at the time; the product rule makes them 77,875 and
77,757. The boundaries cannot move and did not — a check produces no tree — and both
phases were **verified to re-run at tier 2** rather than assumed to, because a tier-3
replay copies the recorded digest and would have agreed whatever the change did: r38 at
`9f2b37f26bef` and r39 at `68e450fd6912`. **On this tree a control run through `make` has
to print `tier 2` to be a control at all.**

### Its placement

`stage 38`, `package terminal`, which is *what the core still assumes about the terminal
it is attached to*. Phase 2 removed the **question** — the two "not to a terminal"
warnings, the pause and `--ttyfail`; this phase removes the **vocabulary**. The three
packages it is not in each say something: not `harness`, which changes no source, where
this changes what the editor does and declares a delta for it; not `host`, because nothing
crosses the boundary and the cut's warning set is unchanged either side; and not `tidy`,
because the rows removed are live code a `:set term=` still reaches. Four `uses`:
`seed:0`; `harness:33`, the phase that made those rows say something real; `streams:5`,
whose `-T {term}` is the only way into the fallback this phase repairs; and `host:21`,
whose `host_message()` is the only declared way the core reaches stderr and so the only
way to write an instrument into it.

**`apart 37 38`, one direction and both halves measured.** Phase 37's check states its own
size as a line count of the whole file and of the core, and this phase takes 118 more lines
out of the same swept text: `tools/phaserun.sh zero 37-38` on r36 runs both edits and one
sweep and then stops in phase 37's check with *the file is 79668 lines and the input was
79799* and *the boundary moved by 131 lines and the file by 13*. That is `apart 17 18`'s
shape exactly. The other half was **run** and not reasoned: phase 38's check, given that
stage's swept tree and its own state directory, passes every part, because everything it
asserts is against `$state/old.c`, which its own edit writes. There is **no `need 38`** and
the measurement is reported as vacuous — phase 37's sweep removes nothing, so its unswept
edit output is r37 byte for byte and there is no unswept text here that differs from a
swept one.

**`.reference/zero-baselines` is deliberately not re-recorded, and re-recording it would be
wrong.** `term-moved` is cumulative like `2 stderr-moved`: declared here and inherited by
every later phase, so `ref-term.txt` disagreeing with the baseline is exactly what the
declaration says. Phase 33 needed a re-record because the **harness** changed shape; this
phase changes the **editor**.

**And it broke another phase's program, which it measured and declined to repair.**
`pipes/zero33.sh`'s section 4 extracted `./zero-vim` from **every** `.build-zero/r*.tar`
and required one terminal table across all of them — a glob that reaches boundaries which
did not exist when the phase ran, so the first later phase to move the table on purpose
makes phase 33's check fail. Measured, with this phase's tar present: *r38 records a
different table:*, exit 1. Repairing another phase's program is a decision and not this
phase's to take, so it was reported; the fix bounds the loop by the phase's own number,
and the rule it states is **a phase may assert anything it likes about the past; it may
not assert that the future will not change what it measured.**

## Phase 39 — `-T {term}` goes, and the command line is `+{command}`

`pipes/zero39-edit.sh` and `pipes/zero39-check.sh`, `stage 39`, `package terminal`. Zero
phase 5 left argv as exactly two options: `+{command}`, which is how a **host** tells the
editor what to do, and `-T {term}`, which is how a **shell** told it what terminal it was
attached to. A core is told that by its host or not at all, and `-T` has had a replacement
inside the editor since before this pipeline began — `+set term=` reaches
`did_set_term()` and does everything `-T` did, which is why phase 33 rebuilt the terminal
harness on it rather than on `-T`. So the option goes, and after this phase
`command_line_scan()` is one `if (argv[0][0] == '+')` and one `else` answering
`mainerr(ME_UNKNOWN_OPTION)` — which is what every other word already answered.

### Six cuts, and five of them are dead code no sweep can see

gcc has no warning for a variable that is only ever FALSE, for a switch that has lost its
cases, for a statement after a `return`, or for a struct field whose name another struct
also uses — so all five go in the **edit**, which is `CLAUDE.md`'s rule and phase 38's
shape.

The option letters are **read out of** `command_line_scan()`'s first `switch (c)` rather
than written down. With no case left to set it, `want_argument` is FALSE for ever, so its
block goes and takes the argument switch, `parmp->term = argv[0]`, `ME_GARBAGE` and
`mainerr_arg_missing()` with it. The letter switch is then one `default:` and **is** its
body, which is a rewrite and not a change only because `mainerr()` does not return — read
off `mainerr()`, not assumed. The `-` arm and the last arm are then the same statement,
compared as **text** and collapsed into one else.

**The two `main_errors[]` rows go with their enumerators**, because the table is indexed
by them. `deadenums.py` would take the enumerator and leave the row, and the rows are
positional — `CLAUDE.md`'s `deadfields` lesson in a table — so the edit takes both,
renumbers `ME_EXTRA_CMD` 3 → 1, and deletes `mainerr_arg_missing()`, which cannot be left
for the sweep because it is `ME_ARG_MISSING`'s only other mention. Which enumerators die is
**computed** as those whose only remaining mention is their own `enum` line, and the check
is **DWARF and not the build**, in phase 5's shape: 1,189 enumerator values in, **1,187**
out, the two gone, `ME_EXTRA_CMD` lower by exactly the number of rows that went, and 1,186
unmoved.

**`mparm_T.term` goes in the edit for a reason phase 38 did not have.**
`tools/deadfields.py` matches by **name**, and this file holds 32 mentions of another
struct's `.term` member — `attr_entry`'s `ae_u.term` — so that tool can never see this one
dead. The edit **computes the partition**, every `.term` left belonging to `ae_u`, rather
than asserting it. `termcapinit()` then takes no name at all, and the compiled default it
substituted when given none, read out of the function, becomes its initialiser — which is
`pipes/zero13-edit.sh`'s `ui_write(console)` again.

### And then `set_termname()`'s no-screen arm cannot run, which is what phase 38 predicted

`set_termname()` has two call sites, partitioned by the edit: `termcapinit()`'s, before
there is a screen, which can no longer fail because the compiled default **is** a row of
`builtin_terminals[]`; and `did_set_term()`'s, at run time, where `starting` is
`NO_BUFFERS` or 0 — the edit reads **every assignment to `starting`** and requires none to
be `NO_SCREEN`. So the test folds always, the arm returns FAIL, and the three statements
after it — the fallback phase 38 repaired, `report_default_term()` and the option write
that recorded it — are unreachable and go, with `report_default_term()` falling to the
sweep as the phase's only sweep find.

**Measured, and the instrument is phase 38's**: with the same marker in the same place,
reached through `host_message()`, the input enters the fallback in exactly **2 of its 30
command rows** — `-T xterm` and `-T no-such-term-9x`, the only way in — and a control built
from this phase's **output** with the whole arm restored enters it in **none**, while
recording byte for byte what the output records.

### Phase 38's prediction was half right, and the other half is stated rather than quietly dropped

`report_term_error()` does **not** fall to the sweep. It is called **before** the
`starting != NO_SCREEN` test, so the run-time refusal still prints it — measured, `:set
term=vt320` on a pty prints it and then E522 on both binaries. What it said was `' not
known, defaulting to 'xterm-256color'`, and with no fallback left **that is a promise
nothing keeps**, so the clause naming it is cut in the same step, for phase 38's own
reason: nothing in the build checks that a message tells the truth. The name is read out
of the assignment the edit deletes.

### What rides along is `requested`, and not the 256-colour test

`set_termname()` kept the name it was **given** for one test, `musl_strstr(requested,
"256color")`, because the unknown-terminal path reassigned `term`; that path is what this
phase removes, so the only rewrite of `term` left is the `term += 8` that strips a
`builtin_` prefix, and a strstr cannot match inside that prefix because the needle begins
with a character the prefix does not contain — which the edit **checks** rather than
asserts. **The test itself does not fold and this phase declines to pretend it does**: the
two surviving terminal names disagree on it and `:set term=` still names either at run
time. Measured in both directions and kept in the check — with the name test forced TRUE
exactly **1 of the 19** terminal rows moves (`debug` gains `t_Co=256`), and with it forced
FALSE **18** do.

### The declared delta is four of thirty command lines, and the set is computed

A row must move **if and only if** one of its words is an option spelling a letter the
input's switch accepted and the output's does not:

```
  -T xterm             started and drew 2,117 bytes      -> exit 1, Unknown option
  -T no-such-term-9x   started and drew 2,117 bytes      -> exit 1, Unknown option
  -T                   Argument missing after: "-T"      -> exit 1, Unknown option
  -Txterm              Garbage after option argument     -> exit 1, Unknown option
```

The last two are the interesting half: **they were already errors and they moved anyway**,
because the two messages they gave were `ME_ARG_MISSING` and `ME_GARBAGE`, enumerators
whose last use was the `-T` argument block. A row that was already `Unknown option
argument` — every one of phase 5's leftovers — must **not** move, and the other 26 do not.
The 102 screen cases, the 98 Ex-command rows, the four pty scenarios and the 19 terminal
rows are the input's byte for byte: `term-moved` is phase 38's and cumulative, and this
phase's recording of the table is the input's.

### And the phase decomposes, which is also the instrument shown able to fail

The **input** with only the `case` arm deleted — `want_argument`, the argument switch,
both `ME_*` rows, the field, the unreachable fallback and `requested` all left in place —
records byte for byte what this phase's output records, and differs from the input. **So
the option letter is the whole of what moves behaviour**, and the other five cuts are
invisible to every part of a recording.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 79,668 | **79,589 (−79)** |
| the command line | `+{command}` and `-T {term}` | **`+{command}`**, every other word `ME_UNKNOWN_OPTION` |
| `main_errors[]` rows / DWARF enumerators | | two rows and two enumerators go; 1,189 → **1,187**, 1,186 unmoved |
| the cut at the first `#include` | 77,758 | **77,679**, eleven directives with none above them |
| the boundary | 18 names | **18**, unchanged |
| `nm -u` | 17 | **17**, a `comm` empty both ways |
| external symbols | `main` | `main` |
| binary | 781,096 | **781,064** |
| records that moved | | **4 of 30 command lines**, and nothing else |

### Its placement

`stage 39`, `package terminal`, and `streams` had a real claim on it that the manifest
answers: the phase removes the half of the command line phase 5 kept, in the same parser —
but of the six cuts, one is that parser arm and **the other five are all terminal code**.
The sentence the package makes reads straight on: phase 2 removed the **question** the core
asked about the terminal, 38 removed the **vocabulary** it could describe one with, and 39
removes the **telling** — after it nothing outside the process can say what terminal this
is, and `+set term=` inside the editor is the only way. Four `uses`: `seed:0`;
`harness:3`, which put an argv record in a zero recording at all; `streams:5`, whose
leftover this phase's whole subject is, and whose renumbered `main_errors[]` table it
checks against DWARF in that phase's own shape; and `host:21`, whose `host_message()` is
the instrument again.

**`apart 38 39`, one direction, both halves measured in the same run.** Phase 38's check
builds its first control by finding the fallback in `set_termname()`, and phase 39 deletes
the fallback outright, so `tools/phaserun.sh zero 38-39` on r37 stops in phase 38's check
at its **first act** with *set_termname() names 0 of the surviving rows and this check
needs one — the fallback*. **That is a check depending on the code it repaired still being
there**, which is the sharpest form of `apart 22 23`'s lesson: phase 38's repair is phase
39's dead code. The other direction was run rather than reasoned — phase 39's check passes
on that stage's tree, which is byte-identical to the sequential one. No `need 39`, measured
in the same run on phase 38's unswept output.

And `pipes/zero33.sh`, the one phase program that reads other boundaries, was run in the
repository root with this phase's tar present: *all 34 recorded boundary binaries up to r33
record the SAME table*, because its scan has been bounded by its own number since the fix
phase 38 asked for, and this phase changes no terminal row at all.

### What zero-vim is after phase 39

```
zero-vim.c        79,589 lines          from whim-vim.c's 86,614  (-7,025, 8.1%)
                  77,678 above the boundary, 1,911 below it
functions         1,757
type definitions  906
DWARF enumerators 1,187
cmdnames[] rows   98    (create_cmdidxs floor 80; 18 rows of margin)
nv_cmds[] rows    194   (nvidxcheck: a permutation)
options[] rows    107, 95 distinct globals  (orphanopts floor 80; 15 of margin)
built-in terminals 2 of whim's 10: xterm-256color and debug
#include          11, at line 77,680, and NOT ONE DIRECTIVE above them
core -> host      18 names: vim_snprintf, host_exit, host_message, host_time,
                  host_alloc, host_free, host_write, host_raise, ten musl_*
libc prototypes   0 -- the core names no libc function at all
libc symbols      17 with zero's flags, 18 as tools/symbols.sh counts
binary            781,064 bytes, EXEC, no INTERP, no dynamic section, no relocation
declared delta    term-moved at 38 and four command lines at 39, the first zero has
                  declared since phase 11 -- with 2 stderr-moved and the records of
                  4 to 11 before them
make editor.c     77,678 lines: 0 directives, 0 errors, 18 warnings, all of them
                  `used but never defined` and all of them the interface
```

**Seventeen phases in a row had declared nothing — 21 through 37 — and phase 38 ended the
run.** What stood in for a recording through those seventeen is a taxonomy and not a
tally, and this document **names** the kinds rather than counting them, because an ordinal
written into a phase section is frozen on the day it is written while the list keeps
growing: phase 18's section says *a sixth kind* over one merge of the list and phase 26's
says *a sixth kind* over another, and both were true when written. **`CLAUDE.md` carries
the one numbered list**, keyed to the order the kinds first appear in `pipes/zero.delta`,
and where an ordinal here and an ordinal there disagree, that one is the current one. The
kinds, by name:

* **code that could not run** (9, 17) — an instrumented pair reaching it 0 times;
* **code that runs and the instrument cannot see** (2, 12, 20, 22, 28, 30, 36) — the phase
  owes probes of its own;
* **a possibility removed** (13) — nothing had ever opened those `FILE *` in any build;
* **the binary is the same bytes** (16, 23, 24, 37) — tier 1, and the strongest, with a
  control that moves it to keep a `cmp` from being two numbers agreeing;
* **replacement code that computes the same answers** (14, 15) — the weakest, and their own
  checks argue it;
* **the code runs and the instrument sees it do the same thing** (18, 19, 21, 25, 32, 34,
  35) — strong exactly when what moved is on the path of everything;
* **part `cmp` and part recording, separated rather than averaged** (26);
* **the source is the same lines rearranged** (27) — a multiset equality, tier 1 one level
  up;
* **the behaviour really moved and the corpus cannot reach it** (29);
* **an accounting** (31) — 42 bytes of `.text`, for a phase that frees no symbol because
  there was none to free;
* **no source changed at all** (3, 33) — what has to be argued is that the **comparison**
  moved safely.

**Fifteen of the seventeen libc symbols are called from the host and from nowhere else**,
and since phase 36 **so are the other two**: `getpid` and `kill` are `host_raise()`'s and
`musl_suspend()`'s, and the core's whole vocabulary of the seventeen is three English
words inside string literals — the two `NGETTEXT` strings in `op_shift()` that say *time*,
and `E222`'s *"already read from"*, measured on this file.

## Phase 40 — the instrument could not see the text layer

`pipes/zero40.sh` — one file, like phases 0, 1, 3 and 33 — `stage 40`, `package harness
3 33 40`. It changes no source at all: r40's `zero-vim.c` is r39's byte for byte and its
boundary digest is its input's, `68e450fd6912` either side. What it adds is the **sixth
part of a recording**, `tools/zmemline.py`, and it is here for the reason phase 3 and
phase 33 were: **a harness that cannot see a phase must be fixed before the phase, never
after.** Phases 41 to 45 rewrite the memline, and until this phase ran nothing in the
pipeline could have told a working one from a broken one.

**One thing about every number from here on.** Between phase 39 and this phase the
`keymodel=startsel` repair landed in slim Phase 1, three lines in `set_init_1()`, and all
three products were re-passed from it — so every zero boundary gained three lines and
`r39` is **79,592** where the phase 39 section above says 79,589. Every figure in this
section and the five below it is post-repair, and every figure above it is pre-repair;
the difference is those three lines and nothing else. `CLAUDE.md` records what the repair
was and what it falsified.

### The blindness is measured and not suspected

A `zero-vim` with one line deleted from `ml_find_line()`'s `ML_DELETE` arm —
`pp->pb_pointer[idx].pe_line_count--;`, the statement that keeps a pointer entry's idea
of how many lines hang under it — records **all 102 screen cases byte for byte**. That
binary was built and both corpora run on it before this phase was written: 0 of 102
differ. **Forty phases had been verified by an instrument that could not see a corrupted
text layer at all.**

The reason, confirmed with an instrumented r39 rather than reasoned: every one of the
102 cases allocates **exactly one data block**. The root pointer block holds one entry
for the whole session, so `idx` is 0 every time, `ml_find_line()` never chooses among
entries, and `pe_line_count` is never the number that decides anything. A 4,096-byte
page holds 78 lines of the width these cases type and `pb_count_max` was 127, so a root
cannot split before **9,984 lines** — and the largest case in the 102 is nowhere near
it. All seven of the phase's markers fire in **0 of 102**.

### The corpus is sixteen cases, and its depth is measured rather than intended

`tools/zmemline.py` is sixteen cases building buffers of **200 to 25,000 lines**, and
they are built **in the editor**: there is no file argument (phase 5), no `:edit` (phase
8) and no `:read` (phase 7), so a case types one line under `'paste'` and replays a
three-key macro with a count — five keystrokes and about two seconds for 25,000 lines.
Every line begins with its own number, so a screen drawn with `'number'` shows the
tree's answer beside the question; each case churns the **middle** of the buffer and
then reads the whole of it back with a substitute count, and jumps to named lines and to
both ends.

**The block arithmetic is derived and not written down**, by compiling the struct
definitions out of the source the phase was handed — page 4,096, data header 24, index
entry 4, `PTR_EN` 32, so a 47-byte line packs 78 to a block and `pb_count_max` is 127 —
and the corpus's own sizes are then required to clear those thresholds. **A corpus that
means to reach a root split and does not is exactly the defect this phase exists to
end**, so the depth is a measurement:

| marker | 16 memline cases | 102 screen cases |
| --- | --- | --- |
| a data block splits | **16** | 0 |
| a pointer entry chosen at `idx > 0` | **16** | 0 |
| a data block of more than one page | **3** | 0 |
| a pointer block full | **4** | 0 |
| **the root splits** | **4** | 0 |
| a non-root pointer block splits | **4** | 0 |
| `ml_find_line()` descends through a second pointer block | **4** | 0 |

### Five controls, and the one that moves nothing is what makes the others mean something

Four are corruptions and each moves **0 of the 102**, which is the premise restated as a
measurement. Deleting `pe_line_count--` from the descent moves **7 of 16**; deleting
`ml_lineadd()`'s **deferred** adjustment — the other place a pointer entry's count is
maintained, and a different shape of mistake — moves **16 of 16**; widening
`ml_find_line()`'s `ML_FIND` stack by one line moves **4 of 16**, and they are exactly
the four the probe measured descending past one pointer block, which the check states as
a **rule** and not as a list of names.

The fifth quarters `pb_count_max` and moves **0 of 16** while the probe shows the root
split going from 4 cases to 13. That is not a failure: **the corpus records behaviour
and not tree shape**, and the control proves it is not a no-op by the probe rather than
by assertion. It is the same finding phase 44 meets again from the other side when it
has to choose `DB_LINE_MAX`, and phase 45 turns into a `static_assert`.

**A discarded control is reported rather than dropped.** Corrupting the root entry at the
split site moves nothing, because the next iteration overwrites it — and a control the
code repairs is not a control.

### It found a real defect, and it is not the one the scrub was written for

One record's stream digest moved in **1 of 48** whole recordings with every screen
identical. Phase 32's section above has the corrected account: the cause is not the
timestamp's text, which `tools/zrec.py` already rewrites padded, but **arithmetic on its
length**. An undo in a buffer this size reports its age and the editor then positions the
cursor to clear the rest of the line, so `0 seconds ago` emits `\033[24;40H\033[K` and
`1 second ago` emits `\033[24;39H\033[K`. A column derived from a scrubbed string's width
leaks the thing the scrub exists to hide, and it failed zero phase 16, whose binary is
byte-identical either side — which is the only reason it was catchable.

So **a memline record carries `stream N redraws` and no digest**, N being the count of
`\x1b[?25h`. What replaces the digest as evidence is the fifth control above's sibling:
both clocks the core can read replaced by counters that run away from the wall move **0
of 16 memline records against 9 of the 102 screen cases**. That is stronger than a
digest, because it says the record does not depend on the clock **at all** rather than
that two runs of it happened to agree. `tools/zcases.py` still digests the raw stream,
and closing that is expensive rather than difficult — see *What is still open* below.

### Four phases pinned the size of a recording, and had to stop

A new **part** of a recording is a new file whatever shape it takes, so `zpty.py`'s
precedent — one record however many scenarios it holds — could not be followed. Measured:
phase 9 stops with *a recording is 122 files, not the 106 this phase counted*. Phases 9,
13, 30 and 34 each tested the count as an **equality**; phases 25, 35, 36 and 37 tested
it as a floor of 100 and were unaffected. The four equalities are now **computed** —
phase 9's control must mark *total − 2*, quiet only in `ref-pty.txt` and `ref-term.txt`,
and the other three take the floor of 100 their siblings already use — which is
`CLAUDE.md`'s own rule that **a number a phase cannot move is reported and not pinned**.

### Measured

| | before | after |
| --- | --- | --- |
| `zero-vim.c` | 79,592 | **79,592**, byte for byte |
| the boundary digest | `68e450fd6912` | **`68e450fd6912`** |
| a recording | 106 records, five parts | **122 records, six parts** |
| memline cases | — | **16**, 200 to 25,000 lines |
| the seven markers, memline | — | 16 / 16 / 3 / 4 / **4** / 4 / 4 |
| the seven markers, screen | 0 of 102 | **0 of 102** |
| `make zero-verify` | | **41 of 41**, 2,771 s of phases in 129 s |
| keys moved | | **58 zero**, and not one whim or slim key |

A cold `make zero-repass` from an empty cache reproduces all 40 recorded boundaries and
adds r40. The 58 are all 40 zero units and 18 zero edits; `tools/zmemline.py`,
`tools/zrecord.sh` and `tools/zcompare.py` are named by no whim or slim phase, and that
is the measurement rather than the claim, so rule 9's gate does not apply.

### Its placement

`stage 40`, `package harness 3 33 40`, which is *the phase changed no source and moved
the instrument instead*. **There is no `apart 39 40` and no `need 40`**, and both are
refusals rather than omissions: `pipes/zero40.sh` is a whole-phase program, so
`stage 39-40` is answered by `tools/stages.sh` with *phase 40 is in stage 39-40 but is
not an edit and a check* and by `tools/phaserun.sh` with *zero phase 40 has no edit and
check to run in stage 39-40*, both measured — and `need` is a statement about an edit
part, which this phase has none of. That is `apart 33 34`'s shape exactly.

The declared delta is **nothing at all**, and it is phase 3's and phase 33's kind: the
phase changes no source, so nothing about the editor's behaviour *can* have moved, and
what it has to argue is that the **comparison** moved safely. It does that by requiring
every recorded boundary back.

### What is still open, stated as two things and not one

**The corpus can be made to reach further and the fix cannot land yet.** Branch
`zmemline-fix`, commit `4e9fb9c`: `tools/zmemline.py` derives its case sizes from the
block arithmetic instead of carrying them as constants, and chunks the buffer build.
Measured, it reaches a **root split in 4 of 16 cases** both at the real fanout and at a
forced `PB_COUNT_MAX = 511` — the value an 8-byte `PTR_EN` would give — where the corpus
as committed reaches **1 and 0**. It is blocked because **two merged checks assert the
corpus's insufficiency as a requirement**: `pipes/zero42-check.sh:686` requires
root-split coverage to *decrease* under phase 42's wider pointer block, and
`pipes/zero43-check.sh:557` requires identical tree-event tuples across a fanout change.
Both pass today **only because the instrument is too small to see otherwise**, so
landing the better corpus means rewriting two checks that were correct when they were
written. That is a phase's worth of work and is recorded here rather than done quietly.

**And the `ago` leak is still open in `tools/zcases.py`.** The fix that works is this
phase's — count redraws, and let a clock control carry the evidence — and applying it to
the other 106 records is expensive rather than hard: the `--- stream` line is named in
**eighty files**, forty-seven times in zero phase 12's check alone. It deserves a pass of
its own. Phase 32's section states the hazard and phase 16 is where it struck.

## Phase 41 — freeing is free, and the arena is measured

`pipes/zero41-edit.sh` and `pipes/zero41-check.sh`, `stage 41`, `package host`.
`host_alloc()` becomes a **bump allocator** into a fixed 1 GiB arena and `host_free()`
returns without doing anything. That is the charter bullet *A GARBAGE COLLECTOR IS
ASSUMED FROM HERE ON* built, and it is what makes the four phases after it cheap rather
than clever: the core may now allocate a record per line and simply not free it.

**The claim is "freeing is now free" and not "the core stopped freeing".** Every
`host_free()` call the core makes is still there and still made; a later phase may delete
them, which is the reason for doing this one first. Phase 35 moved `malloc` and `free`
across the line and wrote the two wrappers; this changes what is behind the two names and
nothing else.

### The strongest thing it says is a `cmp`, and it is a `cmp` of the core

The phase is host-only from end to end, so `make editor.c` — **77,681 lines, 2,064,232
bytes** — is **byte-identical in and out**. That subsumes every screen case, every
memline case, every Ex command, every command line and every pty scenario at once *for
the part of the file the project is for*, because the program a port would be handed is
literally the same text. It is the cleanest proof a phase is host-only that this pipeline
has, and it is a tier-1 check one level in from the whole binary. The recording is then
what says the **host** still answers the same way.

### The size could not have been measured one boundary earlier

The input built with a counter on `host_alloc()` that totals every request as the
allocator rounds it, dumped from `host_exit()`, over the whole of `tools/zrecord.sh`:
**268 sessions in 122 records, largest 200,458,672 bytes**, two recordings and the same
number. It is **one case**, phase 40's `mem_deep_jumps`, a 25,000-line buffer churned in
the middle; the next three memline cases are near 52 million, and the heaviest of the
**102 screen cases is 1,722,512**, which is **115 times less**.

So an arena sized from the 102 alone would have been sized from a corpus provably unable
to reach the text layer — the defect phase 40 exists to have ended, arriving one phase
later in a shape nobody predicted. **This phase found that out the hard way and the
record says so**: 64 MiB was written first and the recording refused it, *THE RECORDING
MOVED, in 1 of 122 records: memline/mem_deep_jumps*, the case dying with
`host arena exhausted: 67108864 bytes, 67058640 used, request 60263`, with 0 of 102
screen cases and 0 of the four sweeps moving.

1 GiB is **5.36 times** the measured high-water and 18.67 % used at its worst. The check
re-measures the high-water on its **own** output over both corpora every run and refuses
an arena less than four times it — and refuses as well if the heaviest memline case is
not heavier than the heaviest screen case, which is the lesson above written down as an
assertion rather than as a paragraph. So the size is a checked property and not a
remembered one, and a later phase that makes the memline allocate more is told by its own
check instead of by a crash.

### The phase overturns its own earlier reasoning, and the correction is worth more than the number

It first justified 64 MiB by *the abort path costs the arena times the harness's
concurrency* — "64 MiB across 64 threads is 4 GiB on a 62 GiB machine". **That is false
except for a runaway session**: an ordinary session's resident memory is its traffic,
which the arena does not change, and an untouched arena page costs nothing. Measured, the
same source at 64 MiB and at 1 GiB gives a **byte-identical image**, 772,872 either way,
because `.bss` is `NOBITS`. The size buys one thing, how far a runaway goes before it
dies loudly, and costs one thing, address space. The wrong argument and the measurement
that killed it are both in `pipes/zero.delta`, so the correction survives outside the git
log.

### And one measurement says why no number is safe

With nothing freed an arena holds a session's whole allocation **traffic** and not its
live data, and this editor's traffic is **quadratic in the length of a single line being
typed**: `+normal 200000ax` asks for 20,013,114,624 bytes across 400,475 calls, and
`+normal 500000ax` for 44,075,360,179. Phase 35's own by-hand probe was that command, so
a later phase that writes one like it will hit the wall. Buffers are linear and cheap by
comparison — 100,000 lines cost 12,862,224 bytes and 300,000 lines 35,157,264, about 112
a line. **It is churn and not size that fills an arena.**

### The real cost is not the arena, it is the resident memory

A bump allocator makes a session's peak RSS equal to its traffic. Measured with
`getrusage(RUSAGE_CHILDREN)` over a whole `tools/zmemline.py` run: the worst child peaks
at **13.6 MiB on the input and 191.8 MiB here**, fourteen times more, at either arena
size. Across a whole `make zero-verify` — 42 units at once — the peak is **13.7 GiB of a
62 GiB machine against 13.1 GiB** measured the same way on the boundary before it: 591
MiB and 4.4 % more, with 41 GiB still available. That is the charter's trade under
harness concurrency, on the record for the phases behind it, and it is the number to
watch as phases 42 to 45 change how much the memline allocates.

### Two of the four rewrites are not in the allocator, and without them the phase is wrong

The formatter's private island — the functions phase 27 moved below the includes because
they need `va_list` — still called libc's `free()` and libc's `realloc()` directly, on
pointers that came from `alloc_clear()`, which is to say from `host_alloc`. Phase 35 named
one in its own program (*"and `format_overflow_error()` below the boundary"*) and phase 34
named the other (*"`realloc` call is the host's and is not this phase's"*). **Both were
right while `host_alloc` WAS `malloc`**: the two allocators were one allocator. From this
phase a `free()` or a `realloc()` of an arena pointer is undefined, so they move — the
`realloc` by phase 34's own allocate-copy-free with phase 34's three traps read off this
site — and the byte-identical cut is what proves the phase did it without touching a core
line.

Neither is reachable by any recording and one cannot run at all, so the check owes a
probe and runs one: `adjust_types()` grows `*ap_types` only for a format string carrying
a **positional** spec, and not one string literal in this file has one, so the same
driver built into the input and the output runs six ascending positional formats through
it, enters the grow arm **17 times in each**, and the two binaries print the same bytes.
`format_overflow_error()` cannot be probed because it cannot run — its guard is
`overflow_err`, which is `tvs != nullptr`, and `vim_vsnprintf_typval()` has one caller in
this file passing `nullptr`. That is phase 9's and phase 17's kind, and it is kept correct
rather than left to rot.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 79,592 | **79,660 (+68)**, every one below the first `#include` |
| `make editor.c` | 77,681 | **77,681**, byte-identical, 2,064,232 bytes |
| `nm -u` | 17 | **14**, the set moving by exactly `free malloc realloc`, a `comm` empty the other way |
| `.bss` | 24,600 | **1,073,766,424** |
| binary | 781,064 | **772,872 — smaller**, because `.bss` is `NOBITS` and musl's allocator left the link |
| arena high-water | | **200,458,672 bytes**, one case, 5.36x under the ceiling |
| worst child RSS | 13.6 MiB | **191.8 MiB** |
| records that moved | | **0 of 122**, two full recordings byte-identical |

It is the **first zero phase since 28 to free a symbol, and it frees three**. The `.bss`
growth is the arena less 960 bytes, and the 960 is musl's own `__malloc_context` and five
smaller objects leaving with it. `EXEC`, no `INTERP`, no dynamic section and no
relocation are all still true of a gigabyte object.

**The controls, over both corpora.** `host_alloc` returning `nullptr` moves **122 of
122**. **The offset never advancing** moves 102 of 102 screen cases and 16 of 16 memline
cases, and it is the only one that tests the *allocator* rather than the wrapper: a
`host_alloc` that returned the arena's base for ever would pass the symbol check, the cut
and the size assertion. `host_free` doing nothing moves **0 of 102 and 0 of 16** — phase
35's own `cf` control re-run on this phase's input rather than a new claim, on a corpus
phase 35 did not have, and reported rather than hidden, because a leak is invisible to
this corpus too and it is `free` leaving `nm -u` that says the freeing changed. And the
guard, which no recording can take: a 256 KiB arena aborts with
`host arena exhausted: 262144 bytes, 113024 used, request 319968` and exits 1 — the
request being the screen, this editor's single largest allocation — while the identical
session on the real output is silent and exits 0.

**`<stdlib.h>` is now dead and it stays**, measured rather than argued: the output built
with the directive deleted is byte-identical, 772,872 either way. Eleven stays eleven,
on phase 13's precedent for declining — a phase that changes two things cannot say which
one a difference came from, and the removal is free for whoever asks for it.

### Its placement

`stage 41`, `package host 17 18 19 20 21 30 32 35 36 41`, because that is what the
package is: a thing the core did for itself becomes a thing it asks the host to do. Here
it is one step further — the core already asked, and what changes is the answer.
`tools/zhostonly.py` needed no new word and no new exception: `host_alloc` and `host_free`
have sat below `musl_suspend()`'s brace since phase 35, and none of `malloc`, `free`,
`realloc`, `max_align_t` or `alignof` is in its vocabulary.

**`apart 41 42` is measured and is not the mechanism the phase predicted.** It expected
`apart 14 15`'s shape, an undefined-set equality against a stage's one snapshot. What
actually fires is **this phase's own promise**: `tools/phaserun.sh zero 41-42` on r40
stops with *the text above the first `#include` is not byte-identical in and out, and
this phase is entirely below it*, and again on the directives' line numbers. **A phase
that promises to touch no core line cannot share a stage with one that deletes 366 of
them.** The other direction is reasoning: phase 42's check compares the undefined set of
the text its own edit was handed with its output, and on a shared stage phase 41's edit
has already taken the three symbols by then, so it would pass.

**There is no `need 42`, for a reason stronger than one stage's measurement**: phase 41's
**sweep is a no-op** — its edit's output on r40 is byte-identical to r41 — so there is no
unswept text for phase 42 to be handed at all. `make zero-verify` is 42 of 42.

## Phase 42 — the swap file's residue, and what no sweep could find

`pipes/zero42-edit.sh` and `pipes/zero42-check.sh`, `stage 42`, `package tidy 13 37 42`.
The filesystem went at phases 6 to 10 and the swap file's **bookkeeping** did not:
memline and memfile still kept a header block carrying the editor's version and the
buffer's name, a translation table for blocks not yet written out, a three-valued
dirtiness state, and a record of where each block's lines used to be. None of it can be
reached, none of it is read — and **not one of the four is visible to any tool in
`tools/`, because every one of them is written.**

`tools/deadfields.py` takes a field named nowhere outside its own type, and each of these
is named; run against the input it reports **0 fields**. gcc has no warning for a struct
member nothing reads, for an enumerator only ever OR-ed into a word nothing tests, or for
a file-scope object read twice and assigned nowhere;
`-Wunused-but-set-variable` does not reach a file-scope object and
`tools/deadsweep.py` does not act on it at all. So this is an **edit** and not a sweep,
and the check states the division rather than assuming it: **22 names leave in the edit
and 39 more in the sweep**, both sets named with the reason each is in the half it is in.

### The four, each proved as a partition over every mention

* **`struct block0`, the header.** **Eight** fields, not the survey's nine — phase 36
  already took `b0_pid`, so the edit reads the list **out of the struct** rather than
  from a list typed into it, which was already a phase out of date. 8 declarations, 12
  writes, **0 reads**. `ml_open()`'s thirty-two-line preamble goes with
  `set_b0_fname()`, `long_to_char()`, `ml_setflags()` and its two call sites, and the two
  surviving blocks move down by one: the pointer block is block nr 0 and the data block
  block nr 1.
* **Negative block numbers.** `mf_trans_add()` returns before doing anything unless a
  block number is negative, and the chain that could make one is **computed** in the
  edit: `mf_new()`'s callers pass `FALSE` or `ml_new_data()`'s own parameter,
  `ml_new_data()`'s pass `FALSE` or `flags & ML_APPEND_NEW`, `ML_APPEND_NEW` comes only
  from `ml_append()`'s `newfile`, and `newfile` is `FALSE` at **all eleven call sites**.
  `mf_trans_add`, `mf_trans_del`, three memfile fields, the parameter and two flags.
* **The dirtiness, write-only in all three layers.** `mf_dirty` has six writes and two
  reads and **each read is the condition of an `if` whose only statement writes the field
  again**, which the edit checks structurally; `bh_flags` is read in exactly one place
  and that read tests `BH_LOCKED`, so `BH_DIRTY` is set three times and **tested
  nowhere**; and `ML_LOCKED_DIRTY` and `ML_LOCKED_POS` are read at one place between
  them, the two arguments `mf_put()` stops taking. `mf_put()` is now `mf_put(bhdr_T *hp)`.
* **`pe_old_lnum`, 7 writes and 0 reads — and the three locals that go with it.** Taking
  the field leaves `lnum_left`, `lnum_right` and `ml_find_line()`'s `dirty` written and
  never read, which is `-Wunused-but-set-variable`, which `tools/deadsweep.py` does not
  act on, so they are the edit's for the same reason the fields are. And
  `mf_dont_release`, `static int mf_dont_release = FALSE;`, read twice and **assigned
  nowhere in the file**.

**A fifth the survey missed: `ML_LOCKED_DIRTY`'s ml-level twin.** `ML_LOCKED_DIRTY` is
set 8 times, cleared once and tested nowhere once `mf_put()` loses its state arguments —
and no warning covers a bit in a struct field. Leaving it would have created exactly the
invisible write-only state this phase exists to remove.

### And `BH_LOCKED` is not dead, which is the distinction worth keeping

It looks like `BH_DIRTY`'s twin and it **is** read, by `mf_put()`'s own
`e_block_was_not_locked` test. Measured: a binary whose `mf_put()` **sets** the bit
instead of clearing it draws all 102 screen cases identically, because the only reader is
an internal-error test that then never fires. **That is unreachable evidence, not
unreachable code**, and the phase leaves it alone and says so.

### The declared delta is nothing at all, and it is two kinds at once

The negative-block half is **phase 9's kind**, code that could not run; the block-zero
half is **phase 12's**, code that runs everywhere and the instrument cannot see. One
instrumented build of the input says both, over **252 records** — 102 screen, 16 memline,
126 from the two sweeps and eight stress sessions: the four markers on the negative-block
island fire in **0 of 252**, against a control of identical shape in `ml_new_data()`
firing in **227 of them, 2,141 times**, and the three markers on the header writes fire
in **227 / 214 / 227**, so that code runs nearly everywhere and the two full recordings
are byte-identical anyway.

**The check caught itself failing, and that is reported rather than smoothed away.** An
earlier draft computed each marker's indent from its anchor, which put two counters
**outside** the `if` they belonged in, and it refused with *`neg_new neg_find` fired in a
recorded session* — reporting the unreachable island as reachable. Every marker's
placement is now written out in full, with that measurement as the reason.

### The fanout changes, and that is what phase 40 is for

`pe_old_lnum` is a member of `PTR_EN`, so every pointer-block entry gets smaller and more
of them fit in a page: `sizeof(PTR_EN)` 32 → 24 and `pb_count_max` **127 → 170**, and the
root pointer block overflows **later**. A binary with `ml_append_int()`'s root test left
at the old block number — a real bug, the root not kept where `ml_find_line()` starts —
draws all 102 screen cases and all four of the survey's own deep cases **identically**;
what moves it is `mem_deep_jumps`, and that corpus is the only recorded thing that can.

**It also narrows what phase 40 reaches, measured 4 cases to 1** — `mem_root_split` among
them, the case named for the thing it no longer does — because phase 40 derived its
buffer sizes from `sizeof(PTR_EN)`. **A case named for the root split is a case sized for
a fanout.** The check asserts that as an *inequality* rather than a count, because this
phase can only make a pointer block hold more children. The corpus fix that would undo
the narrowing exists and cannot land; phase 40's section says why.

Section 8 of the check is the direct proof with an instrument: at sixty thousand lines
the output preserves the root once and never overflows, the control preserves it never
and reaches `e_updated_too_many_blocks`, and the two draw different screens. Four sessions
of sixty thousand lines and more then agree between the input and the output. Undo's
message carries a wall clock — four of five runs said `0 seconds ago` and one said
`1 second ago`, a difference between a binary and **itself** — so that phrase is folded to
a constant, and the check requires it present so the folding cannot hide anything.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 79,660 | **79,294 (−366)** — the edit takes 280 and the sweep 86 |
| names that leave | | **22 in the edit, 39 in the sweep**, both sets named |
| `sizeof(PTR_EN)` / `pb_count_max` | 32 / 127 | **24 / 170** |
| `make editor.c` | 77,681 | **77,315**, 0 directives, the same 18 interface names |
| `nm -u` | 14 | **14**, an equality: a phase that deletes core code and crosses no boundary can free nothing |
| binary | 772,872 | **768,744** |
| arena high-water | 200,458,672 | **200,449,792 — lower**, every memline case allocating less |
| records that moved | | **0 of 122** |

Every one of the sixteen memline cases allocates less, smaller structs outweighing the
free-list reuse that goes; phase 41's instrument reproduces its own published figure to
the byte on r41, which is what makes the r42 number trustworthy. `tools/canon.sh` is a
no-op on the output, and `zhostonly`, `orphanopts`, `nvidxcheck` and `phasecheck` all
pass unchanged.

### Its placement

`stage 42`, `package tidy 13 37 42`, which is *leftovers of cuts already made* — phase
13's `FILE *` that had never been opened and phase 37's unions that unite nothing are the
same shape as a swap file's header in an editor that has had no swap file since phase 6.
It is not `memline`, which is phases 43 to 45 and is about **representation**.

`apart 41 42` is phase 41's, above. **There is no `need 42`** — phase 41's sweep is a
no-op, so there is no unswept text to be handed — and the 41-42 run confirms it end to
end anyway: the stage's one sweep leaves a `zero-vim.c` byte-identical to r42.

The check is proven able to fail three ways, two of them while it was being written: the
indent draft above; the output with `ml_find_line()`'s descent put back to block nr 1
refuses at the block numbers; and the edit run on its own output refuses at
`struct block0`. `make zero-verify` is 43 of 43.

## Phase 43 — a block number becomes a reference

`pipes/zero43-edit.sh` and `pipes/zero43-check.sh`, `stage 43`, `package memline 43 44
45`. `pe_bnum` and `ip_bnum` become `bhdr_T *`, `memline_T` gains `ml_root`, and
`mf_get(mfp, nr, page_count)` becomes `mf_get(mfp, hp)`. The hash table that turned an
integer block number into a page then has nothing left to look up, so it goes — with the
free list it was keyed alongside, with `mf_blocknr_max` that handed the numbers out, and
with `pe_page_count`, whose one reader in the whole file was the argument `mf_get()` no
longer takes. `blocknr_T` 13 → 0, `mf_hashitem_T` 18 → 0, `mf_hashtab_T` 14 → 0, eleven
functions, 180 lines.

**This is the phase that buys the port the most, and it is worth being precise about what
it buys.** An integer key into a side hash table becomes an **object reference**, which is
the one thing a JVM has and C does not make you say. `ZERO-PLAN.md` §4d lists what a port
would have to be told about rather than translate, and the memline page is the whole of
that list; this removes the **outer** half of it, the indirection *between* pages. It does
**not** remove the inner half, and the phase says so rather than letting the headline
stand: the page is still a byte array, `db_index[1]` is still declared length 1 and
indexed to the block's line count, the fourteen `(char_u *)dp + start` interior pointers
are untouched, the top bit of an offset is still a flag, and the arena and its interior
pointers survive until phase 44. **A reference to a block whose innards are still a byte
array is halfway.**

### Why the lookup could not miss, which is the whole argument that a pointer is the same answer

Read off the text by the edit rather than asserted: the hash is inserted into by
`mf_new()` and `mf_get()` and removed from by `mf_free()` and `mf_get()`, which removes
and re-inserts in one breath to move a block to the head of the used list — so **every
live block has been in the hash since it was made**. Nothing has been written to a disk
since zero phase 6 and nothing could be read from one since phase 9, so there has never
been a block number in this build that named a page not already in memory.

No invariant broke, and both were looked for rather than assumed. **No block number is
stored anywhere else** — every mention of `pe_bnum`, `ip_bnum`, `mhi_key` and
`bh_hashitem` is partitioned by its owning function. **The hash provided no ordering
anything reads**: `mf_used_last` is write-only, there is no release path left, and one
`ml_root` suffices because a root split **preserves the root block's identity**.

### Four write-only fields go in the edit and not the sweep, and that is the rule rather than a choice

`tools/deadfields.py` takes a field named nowhere outside its own type and reports **0
fields** in this region, because every one of `mf_used_last`, `bh_page_count`,
`pe_page_count` and `pe_bnum` is **written**; gcc has no warning for a struct member in
either direction; and phase 20's trap is the other half — remove a member and leave its
initialiser and the compile says `excess elements in struct initializer`, which is a
correct phase failing. `mf_used_last` had been write-only since phase 42 took
`ml_setflags()`, its last reader. `bh_page_count` and `pe_page_count` become write-only
**here**, and that cascade was measured rather than predicted: with `pe_page_count`'s one
read gone, gcc reports `page_count_left` and `page_count_right` as
`-Wunused-but-set-variable`, which `tools/deadsweep.py` does not act on, so those two
locals are the edit's as well.

**Every assertion is a partition and not a count.** Phase 35 had to repair phase 34's
counted anchors, and phase 42 is this phase's direct predecessor and removes four fields
from the same two structs. So the edit asserts the **set of functions** that says each
name — `mhi_key` in eight places, `pe_bnum` in four, `ip_bnum` in five — and a name said
somewhere the phase does not account for refuses. The check states the difference the same
way: the names that leave in the edit (**47**), the names that leave in the sweep (**2**)
and the names that **arrive** (**6**) are three computed sets compared against three
written ones, over identifiers with string and character literals masked out first.

### It caught a lie the prototype would have shipped

`E323: Line count wrong in block %ld` is the only message in the file that printed a
block number, and there are none left. The survey's prototype passed `(long)0`, which
would have printed a falsehood for ever; the message becomes **`E323: Line count wrong in
block`**. The evidence is phase 9's shape: the input built with a latching marker on that
arm carries it in **0 of 122 records** and the identical marker one line above — the
descent into a pointer block — in **120 of 122**; then both sources are forced to take the
arm and both do draw it, `...in block 0` against `...in block`.

**How the arm is forced was arrived at by measurement, and two wrong ways are recorded
because each looks right.** Emptying the scan loop leaves `idx` at 0, `0 >= pb_count` is
false and the descent simply goes round again. Forcing the arm alone is not enough either:
`ml_find_line()` then returns `nullptr`, the editor dies of it — SIGSEGV, measured — and
the message never reaches the stream. What works is reading every entry's line count as 0,
which leaves `idx` at `pb_count`, and then making the arm draw and stop with `out_flush()`
and `host_exit(0)` right after the `iemsg`. That last edit is found by the **shape** of the
call and not its text, which is what lets one rule serve two sources that spell it
differently: the input formats a block number into `IObuff` and the output does not.

`E298: Didn't get block nr 0?` and `E298: Didn't get block nr 1?` are not changed but
**deleted**, with the two `ml_open()` tests that were the only thing that could raise them,
and both objects are left standing for `tools/sweep.sh` — which is the whole of what the
sweep does here, because the eleven functions that go all name a type or a field the edit
removes and leaving them would hand the sweep a file that does not compile.

### The declared delta is nothing at all, and it is the strongest instance of the sixth kind any zero phase has had

The code runs and the instrument sees it do the same thing — and it is strongest here for
a reason about **where** the phase is rather than how careful it was: **every keystroke
this editor draws reaches its text through `ml_find_line()`**. Two whole recordings are
byte-identical across all 122 records.

**And it is only the sixth kind because phase 40 exists.** Before it a recording was 102
screen cases that allocate exactly one data block each, and a binary with one line deleted
from `ml_find_line()`'s pointer bookkeeping recorded every one of them byte for byte; a
phase that rewrites the descent, measured against that, would have been the **second**
kind and would have owed probes for the whole text layer. So the check does not merely
diff the recording: it plants five counters — root splits, pointer-block splits,
data-block splits, deepest descent, data blocks made — in **both** sources and requires the
sixteen memline cases to agree event for event, which they do.

**Five controls, and the fifth moves nothing and is reported.** `c_root` (the root test
made a test nothing passes) and `c_stack` (every stack entry remembers the root) move a
65,149-line session and leave a two-hundred-line one alone — and that two-hundred-line
session is not an easy target: 200 lines of 20 bytes already fill two data blocks, so it
descends through a real pointer block and still cannot see either control. `c_descend`
(every descent takes the first child) moves both, and `c_mlroot` (`ml_open()` never writes
`ml_root`) moves all three sessions, which keeps the finding from being a session nothing
could fail. `c_pages` (`mf_alloc_bhdr()` sizing every block one page) moves **nothing**,
and the reason is worth having rather than hiding: since phase 41 `host_alloc` is a bump
allocator with no redzone and no free, so a block written past its end scribbles on arena
bytes nothing has handed out yet. **A short allocation there is a memory bug and not a
difference** — the last row of `CLAUDE.md`'s verification table, the one that needs a
sanitizer and not an instrument — and it is built, run and reported, which is phase 34's
seventh control exactly.

### The pointer entry shrinks and the tree gets wider, which is the thing a later phase has to know

Derived by compiling the structs out of both sources rather than written down:
`sizeof(PTR_EN)` **24 → 16** bytes, so `pb_count_max` — children per pointer block — goes
**170 → 255**, and a root split needs more than that many live data blocks. It was 127
before phase 42. The corpus's largest case makes **321**, so it still splits the root,
with 66 blocks of margin. Because of this the check's own deep session states the data
layer as an equality and the pointer layer as an **inequality**: at 65,149 lines — derived
from `pb_count_max` and the lines a data block holds, not typed in — both binaries make
386 data blocks, descend 2 deep and split the root once and draw the same stream, while
the output splits a pointer block **once** against the input's twice, because a wider
block splits no more often than a narrower one.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 79,294 | **78,977 (−317)** — the edit takes 315 and the sweep 2 |
| names | | **47 leave in the edit, 2 in the sweep, 6 arrive**, three computed sets |
| `blocknr_T` / `mf_hashitem_T` / `mf_hashtab_T` | 13 / 18 / 14 | **0 / 0 / 0** |
| `sizeof(PTR_EN)` / `pb_count_max` | 24 / 170 | **16 / 255** |
| `make editor.c` | 77,315 | **76,998**, 0 directives, the same 18 interface names |
| `nm -u` | 14 | **14**, an equality with its reason |
| binary | 768,744 | **760,456** |
| records that moved | | **0 of 122**, with five tree counters agreeing case for case |

`nm -u` does not move, and the reason is stated rather than the number: the hash, the free
list and the block numbers were **pure computation inside the file**, reaching the outside
only through `alloc()` and `vim_free()`, which have been `host_alloc` and `host_free`
since phase 35. `tools/zerodelta.sh --phase 43` reports *exactly as declared* — screen
102/102, memline 16/16, `ref-excmds.txt` 111/111 and `ref-argv.txt` 30/30 — which is a
different comparison from the check's own `diff -r` of two recordings: one asks whether
the output matches its input, the other whether it matches whim. The synthetic input the
phase was designed against is **byte-identical** to the real r42.

### Its placement

`stage 43`, `package memline 43 44 45`, which the charter names as the end of the road —
*the text later held as a tree*. It is not `buffers`, which is phase 11 and an Ex-level
refusal to quit, and not `tidy`, which is leftovers of cuts already made.

**`need 43 swept` is required and what breaks without it is not the anchor a reader would
guess.** Measured on exactly the text phase 42's edit leaves, the edit runs to its last
act and refuses with *names this phase removes are still said: `blocknr_T` 1,
`mf_hashitem_T` 1, `mf_hashtab_T` 1* — phase 42 leaves `mf_hash_free_all` standing for the
sweep and its **forward declaration** names all three of the types this phase deletes.
**The cut applied cleanly and the partition refused, which is what a partition is for.**

**There is deliberately no `apart 42 43`, and both halves are measured rather than
argued.** Phase 42's check quotes verbatim the two lines this phase rewrites —
`pp->pb_pointer[0].pe_bnum = 1;` 1 → 0 and `if (hp-> bh_hashitem.mhi_key != 0)` 2 → 0 — so
it would stop. But with `stage 42-43` in the manifest `tools/stages.sh` answers *43 needs
swept input and does not start a stage (42-43)* and exits 1 **before any check runs**:
`need 43 swept` already forbids the only stage that could hold both, and an `apart`
nobody can measure is phase 36's rule. Both halves are written down so the next reader
knows it was checked and not assumed.

## Phase 44 — de-page the leaf

`pipes/zero44-edit.sh` and `pipes/zero44-check.sh`, `stage 44`, `package memline`. A data
block stops being a **page of bytes** and becomes an **array of line records**. Until this
phase a leaf is a header, an index of byte offsets growing up from it and a text arena
growing down from the end of the page, with `db_free` bytes of gap where they meet: a
line's text lives inside the block, so inserting a line in the middle memmoves the arena
and rewrites every index below it, a line that grows past the gap is appended-and-deleted
into another block, and a line longer than a page makes the block two pages. After it the
leaf is

```c
struct { char_u *dl_text; colnr_T dl_len; char dl_marked; } db_line[DB_LINE_MAX];
```

and a line's text is **its own allocation**: inserting shifts records, not bytes, and
replacing stores a pointer.

**Why it is cheap now.** The arena exists for exactly one reason, to avoid a `malloc` per
line, and the charter has retired it — *A GARBAGE COLLECTOR IS ASSUMED FROM HERE ON*. This
phase spends what phase 41 bought. And the target representation is **today's dirty-line
path made permanent**, which is why the rewrite is 184 lines out and 71 in and not a
thousand: `ml_line_ptr` under `ML_LINE_DIRTY` is already a separately allocated `char_u *`
with `ml_line_len` beside it, so `ml_flush_line()`'s sixty-line *does the new text still
fit* branch — the memmove, the index fixup and the append-then-delete fallback — has
nothing left to decide and becomes one store.

### What goes, every count measured on the input and asserted as a partition

`db_free` 14 mentions, `db_txt_start` 29, `db_txt_end` 6 and `db_index` **34** all to
**zero**; the fourteen interior pointers of the shape `(char_u *)dp + start` to zero;
`DB_MARKED`'s stolen top bit, 17 expressions, to a real field; `ML_APPEND_MARK` 5; and
**both `offsetof(DATA_BL, db_index)` — by having nothing left to measure**, which is a
stronger removal than respelling them as `sizeof`, and which a prior survey verified was
byte-identical and recommended against for exactly this reason. The edit classifies every
mention of every one of them by its enclosing function and refuses on one that is not in
the struct, the enumerator or one of the eight memline functions it rewrites; the check
re-reads the input's counts **off the input** rather than trusting the numbers. **The
third memline `offsetof` stays and is named as not this phase's**: `ml_new_ptr()`'s
measures a *pointer* block, which is the branch and not the leaf.

### `DB_LINE_MAX` is a free parameter now, and it is chosen by instrument reachability

A leaf used to hold whatever fitted in a page and nothing decides it any more. **The
corpus cannot see the value at all**: 32, 64, 128 and even 1 record all 118 cases byte for
byte, so any argument from *the recording agrees* would have been vacuous. What it does
decide is how much of the tree the corpus **reaches**, measured with phase 40's markers on
r43, this phase's actual input:

| `DB_LINE_MAX` | SPLITDATA | SPLITPTR | SPLITROOT | IDXNZ | DEEP |
| --- | --- | --- | --- | --- | --- |
| 32 | 16 | 5 | 5 | 16 | 5 |
| **64** | **16** | **1** | **1** | **16** | **1** |
| 128 | 16 | 0 | 0 | 16 | 0 |
| 255 | 14 | 0 | 0 | 14 | 0 |
| r43, the input | 16 | 1 | 1 | 16 | 1 |

64 reaches exactly what the input reaches. **255 is the value that would fill the page and
it is the one that must not be chosen**: the natural-looking pick, the one that wastes
nothing, reaches no pointer-block split at all and would have blinded the instrument on
the very phase that rewrites the tree. That is phase 40's lesson applied to a parameter
instead of a corpus.

**And the margin is one case, which has narrowed under this phase.** The same table taken
on r40, where this was prototyped, read 6 / 5 / 1 / 0 in the SPLITROOT column: **128 was a
live choice then and reaches zero now.** Phase 42 took `pe_old_lnum` out of `PTR_EN` and
phase 43 took the block number and the page count, so `pb_count_max` has gone 127 → 170 →
255 while the corpus's buffer sizes have not moved. Measured directly with a counter on
`ml_new_data()`: `mem_deep_jumps` builds **321 data blocks on the input and 391 here**
against a `pb_count_max` of 255, and no other case comes near it on either side (204 / 155
/ 154 and 248 / 192 / 188). **A `PTR_EN` of 8 bytes would put `pb_count_max` at 511 and
take even 64 to zero** — at which point the corpus needs resizing or `DB_LINE_MAX` needs
lowering. The measurement stands; its margin does not, and that is the finding phase 45
turns into a compile error. The number, and that 32 reaches five, are written into the
edit, the delta and the commit, so lowering `DB_LINE_MAX` stays available if it is ever
preferred to resizing the corpus.

**This phase does not move `sizeof(PTR_EN)`**: 16 bytes either side, `struct
pointer_entry` byte-identical in and out, and the check pins `offsetof(PTR_BL,
pb_pointer)` at 1 → 1.

### The lifetime rule is pinned as a partition and not as prose

341 call sites depend on what `ml_get()` returns. It used to be a pointer **into the
page**, invalidated by any insert or delete in the same block, any flush of any line in it
and any split — the arena memmoves. It is now the record's own allocation and nothing
frees it, so **a pointer returned by `ml_get*()` is valid for the lifetime of the
process**. Stated as a partition — a record's text is written in exactly **five** places,
`ml_open` once, `ml_append_int` three times and `ml_flush_line` once, and freed in
**none** — and probed: a build that poisons the text a record stops owning moves **0 of
118**, which is the rule measured and not asserted.

**`ml_line_alloced()` is deliberately not simplified and the check enforces that.**
`del_bytes()` shortens `ml_line_len` in place under it and nothing would write that length
back, so `ML_LINE_DIRTY` must keep meaning *a replacement is pending* and not *the text is
allocated*. **It looks like an invitation and is a trap.**

### What it spends is measured, and it is the one cost no recording can see

The heaviest memline session asks the host for **201,927,792 bytes where the input asks
200,438,864**, +0.7 %, `mem_deep_jumps` either side. With nothing freed that is a
session's **traffic** and not its live data, which is why it is two hundred megabytes and
why phase 41's arena is a gigabyte. The counter is calibrated against a known answer
before it is believed — on the 233 non-memline sessions it reproduces phase 41's own
published high-water to the byte, **1,734,544** — and phase 41, rebased onto phase 40,
reached the same two numbers independently with an instrument written apart from this one.
The bound is **proven able to fail** rather than chosen: `ml_alloc_line()` over-allocating
by one page a line — the blunder the section is for — asks **304,354,000**, 1.52 times the
input, against the real output's 1.007.

### The leaf is still allocated as one memfile page, and that is deliberate scope with a measured cost

1,040 bytes of 4,096, asserted by a `static_assert` rather than left to be discovered. The
cost is reported and not hidden: the `cap` control, the capacity bound off by one, moves
**0 of 118**, because the 65th record lands in the page's spare room. Allocating a block
at its own size means giving memfile a **byte size where it has a page count**, which is
block *numbering* as well as block size — the machinery phase 43 has just rewritten — and a
phase that replaced the leaf's representation and changed how blocks are allocated in one
act would have two claims and one set of evidence. Phase 45 is that phase, and it measures
this prediction rather than repeating it. One prediction of this phase's had already come
true from the other side: `pe_page_count` and `bh_page_count` would be constant 1 after
it, and phase 43 removed both before it.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 78,977 | **78,859 (−118)** — 184 out and 71 in, and the sweep finds exactly one thing |
| `db_free` / `db_txt_start` / `db_txt_end` / `db_index` | 14 / 29 / 6 / 34 | **0 / 0 / 0 / 0** |
| interior pointers `(char_u *)dp + start` | 14 | **0** |
| `offsetof(DATA_BL, db_index)` | 2 | **0**, by having nothing left to measure |
| `make editor.c` | 76,998 | **76,880**, 0 directives, the same 18 interface names |
| `nm -u` | 14 | **14**, a `comm` empty both ways |
| binary | 760,456 | **760,456** — the same size, different bytes, absorbed by alignment padding |
| arena high-water | 200,438,864 | **201,927,792 (+0.7 %)** |
| records that moved | | **0 of 118** |

The declared delta is **nothing at all** and it is the **weakest** kind on the list, phases
14 and 15's: the code changes, the binary moves, and the claim is that a replacement does
what the original did. There is no `cmp` to be had, so the two byte-identical recordings
are the **floor** and the **eleven controls** are the evidence. Eight must move and do —
the text not copied 2 of 118, the stored length dropped 36, a mark never set 4, the delete
shifting one record too few 6, the insert opening its gap the wrong way 8, the split
moving one record too few 4, every read taking the block's first record 52, every length
short by one 38 — and three must not, each with the reason it cannot be seen: `poison`,
`cap` and `DB_LINE_MAX = 1`. **The split control is the one that says why phase 40 was not
optional: 0 of the 102 screen cases and 4 of the 16 memline cases.** The corpus per case is
the input's own numbers — MLSPLITDATA 16, MLSPLITPTR 1, MLSPLITROOT 1, MLIDXNZ 16, MLDEEP
1 — and one marker goes down because the code is gone: phase 40's MLBIGLINE, a data block
of more than one page, fires in 3 of 16 on the input and has **no anchor in the output at
all**.

### The rebase cost exactly two anchors and both refused loudly

Which is the design working. The edit is written so that every region is located by a
function name and its own first and last line, every call whose arity changes is rewritten
by **place** and not by argument text, and every `ml_flags |=` inside a replaced region is
**carried forward as found** — and that last one paid for itself exactly as intended, phase
42 having deleted `ML_LOCKED_DIRTY` and `ML_LOCKED_POS`, so `ml_flush_line()` now carries
nothing and the edit needed no change. What did move: `ml_alloc_line`'s insertion point was
anchored on `long_to_char()`, which phase 42 deleted with block zero, and now goes
immediately above `ml_open()`, its first caller, so it depends on the function it is about;
and the probe's depth counter was declared at `ml_find_line()`'s `bnum = 1;`, which phase
43 deleted with block numbers themselves, and is now at `low = 1;` beside it — the line
that says the same thing about the **search** rather than about the representation.

### Its placement

`stage 44`, `package memline`, which phase 43 opened and whose comment says *phase 44
replaces the leaf, so the package grows*.

**`apart 43 44` is `apart 36 37` in its sharper form.** `tools/phaserun.sh zero 43-44` on
r42 runs both edits, one sweep and phase 43's check and stops with *the sweep: the names
that leave are ['ML_APPEND_MARK', 'ML_DEL_NOPROP', 'data_moved', 'db_free', 'db_index',
'db_txt_end', 'db_txt_start', 'e_didnt_get_block_nr_one', 'e_didnt_get_block_nr_zero',
'line_start', 'space_needed', 'text_start'] and this phase accounts for
['e_didnt_get_block_nr_one', 'e_didnt_get_block_nr_zero']*. Phase 43 states the division
between its edit and its sweep as a **partition over names**, a stage sweeps **once** at
the end, and the ten names this edit orphans land in phase 43's sweep set. **36-37 was that
lesson in a line count; this is the same lesson in a set, and a set is what a later phase
is more likely to state.** One direction only: phase 44's check was then run on exactly the
tree the shared stage produced and every part passes.

**And there is no `need 44`, measured as an equality and not as a run that did not
refuse.** The same 43-44 stage hands this edit phase 43's **unswept** output, and the file
the one sweep leaves is byte-identical to the sequential run's, 78,859 lines either way.
**The edit does not merely survive unswept text; it cannot tell the difference.**

`tools/phaserun.sh zero 44` exits 0 in 70 s and `make zero-tip` records r44 as
`5677d3f826f4`. The sweep finds exactly one thing in the whole phase, `ML_DEL_NOPROP`, and
the check states that division: **`ML_APPEND_MARK` is reachable code that can never be
true once the fallback goes**, so no sweep can see it and the edit takes it.
`make zero-verify` is 45 of 45.

## Phase 45 — fold the node types

`pipes/zero45-edit.sh` and `pipes/zero45-check.sh`, `stage 45`, `package memline`. The
memfile goes, and with it the last thing between the tree and its nodes. Until this phase
a memline node is **two** allocations: a `bhdr_T` of four members — two used-list
pointers, a `char_u *bh_data` and a lock flag — and, hanging off it, a 4,096-byte page cast
to `PTR_BL *` or `DATA_BL *` by the two-byte id at its front, with a `memfile_T` of two
members owning the list head and the page size. After it

```c
struct block_hdr     { short_u bh_id; };
struct pointer_block { bhdr_T pb_hdr; short_u pb_count; PTR_EN pb_pointer[PB_COUNT_MAX]; };
struct data_block    { bhdr_T db_hdr; linenr_T db_line_count; DATA_LN db_line[DB_LINE_MAX]; };
```

**There are no pages, no blocks and no memfile left — just a counted tree of nodes holding
line records.** A node is **one allocation at its own size**, 1,040 bytes for a leaf and
4,088 for a branch against 4,128 for either of them before. `bhdr_T` is the node's **tag**
and the first member of both, so `(PTR_BL *)hp` and `(bhdr_T *)pp` are the same address
and the file needs no union; `memfile_T` has nothing left to hold and is gone; and
`ml_root` answers *does this buffer have a memline* where `ml_mfp` did, taking `memline_T`
from 104 bytes to 96. `mf_open/close/new/get/put/free/ins_used/rem_used/alloc_bhdr/
free_bhdr` all go, and `mf_close()`'s teardown becomes `ml_free_tree()` walking the tree,
which is the same set of nodes.

`bhdr_T` was **not** the wrapper around one pointer the brief hedged for, and the phase
says so: it was four members and 32 bytes, a doubly-linked used list, a `char_u *bh_data`
pointing at a separate page, and a `BH_LOCKED` flag. It is now two bytes.

### This is phase 44's own named next step, and both halves are measured rather than repeated

Quoted in that phase's program: *"Allocating a block at its own size means giving memfile a
byte size where it has a page count ... it would take the leaf from 112 bytes a line to 64,
and it would MAKE AN OFF-BY-ONE IN THE CAPACITY BOUND VISIBLE, which today it is not."*

Phase 44's own `cap` control — the leaf capacity test widened by one — is built from **this
phase's input and from its output in the same run**: **0 of 118 records on the input**,
which is the 0 of 118 phase 44 published, and **4 of 118 here**. The 65th record used to
land in the page's spare room and now lands past the end of a 1,040-byte allocation. Phase
44's other half does **not** reproduce, and the phase reports what it measured rather than
what was predicted: the leaf's node cost falls from **64.5 bytes a line to 16.25**, not
"112 to 64".

### What the phase could have destroyed, and the measurement that says it did not

`pb_count_max` was computed per block as `(4096 - 8) / sizeof(PTR_EN)` = **255**, and it is
the tree's **fanout**. Phase 40's corpus reaches a root split in exactly one of its sixteen
cases, `mem_deep_jumps`, which builds **391** data blocks; the other fifteen and all 102
screen cases reach none of it. A phase that took `sizeof(PTR_EN)` to 8 would put the fanout
at **511**, and 391 < 511 would take root-split coverage to **zero — silently**, because
the instrument would still run and still pass, which is the defect phase 40 exists to have
ended.

So `PTR_EN` is not touched, and the new struct has the same offset **by construction**: a
two-byte tag and a two-byte count where three shorts were, so `pb_pointer` starts at 8 and
`PB_COUNT_MAX = 255` is the number the input computes rather than a number chosen.
`static_assert(sizeof(PTR_EN) == 16, ...)` is appended to the `make editor.c` cut of both
sides and both compile, with `== 8` required to **fail** against both so the assertion is
an assertion. The five markers are then measured case by case on both binaries and are
identical: MLSPLITDATA 16, MLSPLITPTR 1, MLSPLITROOT 1, MLIDXNZ 16, MLDEEP 1, and 0 of 102
screen cases.

**And the file now carries**

```c
static_assert(PB_COUNT_MAX == (4096 - 8) / sizeof(PTR_EN), ...)
```

**which fails to compile if a later phase narrows the entry.** The whole memline arc has
been shadowed by the risk that shrinking `PTR_EN` to 8 would take `pb_count_max` to 511 and
root-split coverage to zero without anything noticing. **It is now a build error rather
than a thing to remember**, which is the arc's standing hazard ended in the only way that
survives a reader who has not read this document.

### The hazard is demonstrated and not argued

The `fanout` control sets `PB_COUNT_MAX = 511`, what an 8-byte entry would give. It moves
**0 of 118 records** — and that **is** the point: the same binary takes MLSPLITPTR,
MLSPLITROOT and MLDEEP **from 1 to 0**, so narrowing the entry would take the root split
out of the corpus **without moving one record**. It is run under phase 40's instrument as
well as under the recording, **because the recording is exactly what cannot see it**.

Two other controls move nothing and are reported with their reasons. `noclear` —
`alloc()` for `alloc_clear()` — moves nothing because the host's arena is a bump pointer
over fresh pages, so the memory is already zero: **a fact about this host and not a promise
the core may rest on**, though `ml_open()`'s error path does rest on it, and that zeroing
is kept and is load-bearing exactly once, the error path walking a root whose single entry
has not been filled in. `nofree` — `ml_free_tree()` freeing nothing — moves nothing because
`host_free()` has returned without doing anything since phase 41, so **what a core gives
back is unobservable by construction**.

### The partition is over the file's whole vocabulary

And not over a list of names the edit happens to know. String literals excluded —
`zero-vim.c` has no comments and no preprocessor, so the scan is exact — **exactly 30
identifiers leave and exactly 5 arrive**: 26 the edit takes (236 mentions of `bh_next`,
`bh_prev`, `bh_data`, `bh_flags`, `mf_used_first`, `mf_page_size`, `memfile`, `memfile_T`,
`ml_mfp`, `pb_id`, `db_id`, `pb_count_max`, `MEMFILE_PAGE_SIZE`, the ten `mf_*` functions,
`mfp`, `page_count` and `page_size`), 2 the sweep takes (`BH_LOCKED`, which
`deadenums.py` finds, and `e_block_was_not_locked`, which `deadsweep.py` does — the whole
of what the sweep finds in this phase), 2 that go with a function the edit deletes
(`mf_close`'s `nextp` and `ml_find_line`'s `error_noblock` label), and 5 written
(`PB_COUNT_MAX`, `bh_id`, `pb_hdr`, `db_hdr`, `ml_free_tree`).

The open-buffer predicate is stated the same way: `ml_root` is compared with `nullptr` in
**no** function in the input and `ml_mfp` in **fifteen**, and in the output `ml_root` is
compared in those fifteen **plus `ml_delete_int`**, which asked the same question through
a local copy.

**Nothing is freed that was not freed before.** `mf_close()` walked the used list at
`ml_close()` and the used list was exactly the set of live nodes, so `ml_free_tree()` walks
the **tree** and frees the same set; `mf_free()`'s two call sites become `vim_free(hp)`,
one allocation where there were two.

### Measured

| | input | after |
| --- | --- | --- |
| lines | 78,859 | **78,666 (−193)** |
| a node | 2 allocations, 4,128 bytes either kind | **1 allocation**, 1,040 leaf / 4,088 branch |
| `bhdr_T` / `memline_T` | 32 / 104 bytes | **2 / 96 bytes**; `memfile_T` gone |
| `sizeof(PTR_EN)` / `PB_COUNT_MAX` | 16 / 255 | **16 / 255**, by construction and asserted from the cut |
| identifiers | | **30 leave, 5 arrive**, a partition over the whole vocabulary |
| `make editor.c` | 76,880 | **76,687**, 0 directives, the same 18 interface names |
| `nm -u` | 14 | **14**, a `comm` empty both ways |
| binary | 760,456 | **760,424** |
| arena, heaviest case | 201,927,792 | **200,720,256 (−0.6 %)**, the biggest fall `mem_join_split` at −9.2 % |
| records that moved | | **0 of 118** |

**Every one of the sixteen memline sessions asks the host for less, and the difference is
arithmetic**: 391 data blocks times (4,128 − 1,040) is 1,207,408 of the 1,207,536 bytes
that go.

The declared delta is **nothing at all**, phases 14, 15 and 44's weakest kind — the code
changes, the binary moves, and the claim is that a replacement does what the thing it
replaces did. Two full recordings are byte-identical to the input's across all 118 cases
and four tables, so the recordings are the floor and not the evidence. **Twelve controls
carry the phase**, nine of which must move a recording and do: the leaf tagged wrong 118 of
118, the branch tagged wrong 118, the leaf test inverted 118, the root split forgetting its
count 1, the root split copying no entries 1, the branch capacity bound off by one 1, a
branch allocated at a leaf's size 6, a leaf allocated at half its size 16, the leaf
capacity bound off by one 4. Three must not, and each is named above with its reason.

### Its placement

`stage 45`, `package memline 43 44 45`. **The 45-on-44 dependency is the strongest in the
arc and is deliberately not a `uses` line**, both phases being in one package, so it is
written into the package comment instead; eight `uses` lines record the cross-package ones.
`tools/stages.sh zero --check` and `tools/packages.sh zero --check` both pass.

**`apart 44 45` is phase 44's own scope statement read from the other end, and it needed no
reasoning.** That phase wrote that `offsetof(PTR_BL, pb_pointer)` *"measures a POINTER
block, which is still a page of entries and is not the leaf ... De-paging the branch is a
phase of its own"*, and its check says it as a count of 1. Measured by running
`pipes/zero44-check.sh` on the r45 tree with phase 44's own state directory: *`ml_new_ptr`'s
offsetof moved, and a POINTER block is still a page and is not this phase's*. One direction
only, because there is nothing to observe in the other — the stage cannot run at all.

**`need 45 swept` is the first in this pipeline that is about blank lines**, and it is
`CLAUDE.md`'s *a pass that touches those needs a count of them as its own check* meeting a
shared sweep. The edit deletes whole functions and single statements out of the middle of
others, so it asserts that it leaves **no run of two blank lines anywhere** — which is a
statement about this edit only if the text it was handed had none. It had one: phase 44's
edit leaves a run of two at line 33,815 of its own unswept output, which `canon.py` removes
in phase 44's sweep. So the edit asks the **input** first, and `tools/phaserun.sh zero
44-45` on r43 stops with *the input already has a run of two blank lines, so this edit
cannot say it left none: it needs swept text*. **The order of those two tests is the whole
of it** — asked the other way round the refusal would have blamed this phase for the
previous one's residue.

`make zero-tip` records r45 = `698924a46bfa`, and `make zero-verify` reproduces it from r44
in a scratch root of its own. Two things not this phase's, both stated: r39 failed that
verify run on `ref-pty.txt` under a 64-way load and passes alone, which is the pty
flakiness `CLAUDE.md` already records; and **`del_file` is still an unread parameter of
`ml_close()`**, as it was of `mf_close()` before it — removing it reaches into
`'cpoptions'` through `CPO_PRESERVE`, which is not this phase's.

### What zero-vim is after phase 45

```
zero-vim.c        78,666 lines          from whim-vim.c's 86,617  (-7,951, 9.2%)
                  76,687 above the boundary, 1,979 below it
functions         1,734
type definitions  880
DWARF enumerators 1,167
cmdnames[] rows   98    (create_cmdidxs floor 80; 18 rows of margin)
nv_cmds[] rows    194   (nvidxcheck: a permutation)
options[] rows    109 that are not a t_ capability, 95 distinct globals
                        (orphanopts floor 80; 15 of margin)
built-in terminals 2 of whim's 10: xterm-256color and debug
#include          11, at line 76,689, and NOT ONE DIRECTIVE above them
core -> host      18 names: vim_snprintf, host_exit, host_message, host_time,
                  host_alloc, host_free, host_write, host_raise, ten musl_*
libc prototypes   0 -- the core names no libc function at all
libc symbols      14 with zero's flags, 15 as tools/symbols.sh counts
the memline       a tree of nodes, one allocation each: a leaf is 1,040 bytes
                  holding 64 line records, a branch 4,088 holding 255 children,
                  and a line's text is its own allocation nothing frees
binary            760,424 bytes, EXEC, no INTERP, no dynamic section, no relocation
declared delta    term-moved at 38 and four command lines at 39; 40 to 45 declare
                  nothing at all -- with 2 stderr-moved and the records of 4 to 11
                  before them
make editor.c     76,687 lines: 0 directives, 0 errors, 18 warnings, all of them
                  `used but never defined` and all of them the interface
```

**The `options[] rows` figure is stated here as the count that can be reproduced**: rows of
`options[]` whose name is not a `t_` terminal capability, 109, measured on this file. The
blocks above this one carry **107**, which no phase between phase 20 and here removed a row
to justify; the number that the floor actually reads, and that has tracked every removal
exactly, is the 95 distinct globals — `whim-vim.c`'s 116 and 102, less phase 12's six rows
and phase 20's `'termresize'`.

**Phases 40 to 45 are one arc and the documents carry it as one.** The instrument had to
exist before the work was checkable, which is 40; the bump allocator made per-line
allocation free, which is 41; 42 cleared the swap file's bookkeeping out of the way; 43
turned a block number into a reference; 44 let the leaf stop being a byte arena; and 45
ends it by folding the node types and turning the arc's standing hazard — that shrinking
`PTR_EN` would silently take the root split out of the corpus — into a `static_assert` that
fails to compile. Every one of 42 to 45 rests on a
measurement the corpus the pipeline had at phase 39 could not have taken — the fanout
narrowing, the tree events agreeing case for case, `DB_LINE_MAX`'s reachability table and
the `fanout` control — which is the whole argument for doing 40 first.

**The six phases declare nothing between them, and they are four different kinds.** 40 is
phase 3's and 33's — no source changed at all, so what has to be argued is that the
*comparison* moved safely. 41 is the sixth — the code runs and the instrument sees it do
the same thing — with a `cmp` of the **core** underneath it that no earlier phase could
offer. 42 is phase 9's and phase 12's **at once**, one instrumented build carrying both
halves. 43 is the sixth again and the strongest instance of it this pipeline has, because
every keystroke reaches its text through the function it rewrites. And 44 and 45 are the
**weakest** kind, phases 14 and 15's: the code changes, the binary moves, and eleven and
twelve controls carry each of them because nothing else can.
