# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repository.

**This file describes the tree as it now is.** If the two disagree, this file is
wrong — fix it. `SLIM-GOAL.md` is a different document: the process that produced this
tree from a pristine vim, written to be handed to an agent that has no tree yet.
Nothing here is a record of how the work went; that log was folded into `SLIM-GOAL.md`
and deleted.

## What this is

Vim 9.2 (upstream patch level 1037) as **one translation unit**. That number
moves: the input is cloned fresh, upstream keeps patching, and **Phase 1 is
where this line gets updated** — from `version.c`, not from memory. `slim-vim.c` is
180,847 lines and is the whole editor; one `gcc` invocation builds it in about
8 seconds, into a standalone static binary.

**`slim-vim.c` is produced, not edited into shape.** `SLIM-GOAL.md` is the process that
turns a pristine vim tree into it, and the input is cloned fresh each time from
`github.com/arbace/vim`, branch `regexp-delimiter-atoms`. See *Regenerate
slim-vim.c from upstream*. Editing `slim-vim.c` directly is fine — but a change worth
keeping belongs in `SLIM-GOAL.md` too, in the phase that owns it, or the next pass
silently drops it.

**The files are named `slim-vim`; the program is not.** `slim-vim.c` and the
`slim-vim` it compiles to are named for this repository, and that is the whole
extent of it: inside the C, `$VIM`, `$VIMRUNTIME`, `~/.vimrc`, `VIMNAME`, the
banner and every string are upstream's, untouched. A rename there would be a
fork; a rename of the file is a file name.

**A vim binary's own name changes what it does**, so the new one was checked
rather than assumed. `parse_command_name()` reads `argv[0]`: a leading `r` is
restricted mode, `e` selects evim, `g` the GUI, and `view`, `vim`, `diff` and
`ex` prefixes each change the mode again. `slim-vim` matches none of them and
falls through to plain vim — verified by running both names side by side, where
`:r !echo` works and `readonly` is off under each.

**No feature was removed to get here**, which is the whole difference between
this tree and a stripped-down fork: `:help`, `:hardcopy`, the non-UTF-8
encodings, locale and iconv are all still present. Two things were removed
*afterwards*, deliberately and separately — six built-in terminal entries, and
bracketed paste — and both are described below.

The configuration is `tiny`, no GUI, no terminal library, **plus
`+extra_search`** — which upstream has no configure flag for.

**This repository holds the process, not the product.** Between passes it is
seven things — `.gitignore`, `Makefile`, `README.md`, this file, `SLIM-GOAL.md`,
`tools/` and `pipes/` — and `slim-vim.c` and `LICENSE` appear when a pass produces them. A
checkout that has never run one has no editor in it, and everything below
describes what a pass makes rather than what is necessarily on disk right now.

**The `Makefile` is part of the seed and drives the pass**, which is the one
thing here that is not upstream's and not produced. `make` asks
`git ls-remote` what the branch head is, compares it against `upstream.sha`,
and when they differ clones `upstream/`, deletes its `.git`, runs one
`claude -p` carrying the process, deletes `upstream/` and records the sha. A
pass must never write over it, and the only two files a pass moves to the root
are `slim-vim.c` and `LICENSE`.

It was started from a finished tree without the history that produced it, so
`git log` reaches back only as far as this repository's first commit. Everything
that history used to be consulted for is written down instead: `SLIM-GOAL.md` is the
process, this file is what the result is and why. From here on every commit
message states the reasoning and how it was verified — that is the record, and
it is the only one.

## Layout

Six hundred and forty-two tracked files once all three pipelines have run
(`git ls-files`): nineteen at the root, 268 under `pipes/` — the phase programs,
twelve for `slim.mk`, 165 files for `whim.mk`'s eighty-three phases and eighty-seven for
`zero.mk`'s forty-six, and each staged pipeline's stage manifest and declared delta — and
355 under `tools/`. Those 355 are three things and it is worth keeping them apart:
**175** are the passes, the harnesses, the canonicalisers and cutters the
phases call, the memoize driver, a `README.md`, and the data a pass cannot derive
(`renames.txt`, `patches/` and `templates/`); **130** are `tools/go/`, the
toolset the sweep and the canonicalisers actually run, which `tools/implhash.sh`
hashes as a directory; and **50** are `tools/gocmp/`, the comparisons that
produced the Go port's numbers against the Python each replaces, named by no
phase program and in no key. Four of the nineteen are products
(`slim-vim.c`, `whim-vim.c`, `zero-vim.c`, `LICENSE`), three are records
(`upstream.sha`, `slim.sha`, `whim.sha`), and the other twelve — `WHIM-PLAN.md`
and `.gitignore` among them — `tools/` and `pipes/` are the seed.

**`pipes/` is the pipeline steps and `tools/` is what they are built from.** A
phase in `pipes/` is either one file, `<pipeline><N>.sh`, or two,
`<pipeline><N>-edit.sh` and `<pipeline><N>-check.sh`, and is run by the memoize
driver as phase N of that pipeline and by nothing else; everything a phase calls
lives in `tools/`. Every slim phase, whim phase 0 and zero phases 0, 1, 3, 33 and 40 are
one file; whim phases 1–82 and zero phases 2, 4–32, 34–39 and 41–45 are split.

**A split phase is an edit and a check, and the sweep is the driver's.** The
programs' last sweep used to be the line between the two, and 70–90% of every
phase's time. **The whim pass runs in *stages*:** a run of phases whose edits share
one sweep. `tools/phaserun.sh` takes the stage's symbol snapshot once, runs every
edit part in order on text no sweep has touched since the stage began, runs
`tools/sweep.sh` once, runs every check part in order on the one swept text and its
one binary, and then checks the declared delta once, for the stage's last phase. A
single split phase is a stage of one. The check reads nothing from the edit's
shell: what passes between them is files in a state directory, `.cache/state/q<N>`,
which the driver makes fresh and seeds with the line count of the text the edit is
handed and the stage's symbol snapshot; an edit that needs to hand its check more
names the file (phase 80's `words`, 80's and 81's `old` binary, 82's `keep`).

`pipes/whim.stages` is the schedule, and **it is checked, not trusted**, twice:
`tools/stages.sh` refuses a schedule that breaks what the manifest declares, and
every stage must end on its recorded boundary. Two kinds of declaration. `need P
swept|silent|swept-inner:K` is what phase P's edit needs of its input — a counted
anchor refuses loudly on unswept text, but a *computed* cut shrinks silently (54
after 53 without its inner sweep cut one option row too few and did not refuse),
which is why it is declared rather than discovered. `apart P K` says P's check was
measured to fail once K has run — it asserts something K removes on purpose — so
they must be in different stages. The schedule is **0 | 1-12 | 13-41 | 42-63 |
64-65 | 66-71 | 72 | 73-77 | 78 | 79 | 80 | 81 | 82**: twelve sweeps where there
were 105. **Only a stage's end is a boundary** — nothing between q12 and q41 exists
on disk.

The same manifest also reads the phases **by concept**, and that view runs nothing.
`package NAME P...` puts every phase in one of eighteen packages (`windows` is 36 39
40 68 72 73), and `uses A:P B:Q KIND why` records a phase relying on a phase of
another package — 50 of them, each with the reason a phase program or `WHIM-GOAL.md`
states (`options:54 encodings:53 mechanical`: 54's computed cut needs 53's second
cut swept). KIND is `mechanical` (37: without the earlier phase the later one fails
or cuts wrongly) or `rationale` (13: the earlier phase is only the stated reason the
cut is right). `tools/stages.sh` ignores both kinds; `tools/packages.sh whim` prints
them with the stages each package falls in, and `--check` refuses a phase in no
package or in two, an unknown phase or package, an unknown kind, and a `uses` whose
dependency runs later. **`make whim-verify` and `make whim-tip` run that check
first** and stop on its message; it is wired into `whim.mk` and nowhere a phase
runs, since `whim.mk` is in no implementation digest (`implhash.sh` only follows
`tools/` and `pipes/` paths).
`WHIM-GOAL.md`'s *Concept index* is the same data as prose. **It is a separate tool,
not a mode of `stages.sh`, because `tools/phaserun.sh` names `stages.sh` and
`implhash.sh` therefore hashes every byte of it into every whim stage's key**:
measured, one appended comment line moved 13-41's key and 72's. The manifest itself
is named by no program, so a package edit moves no key.

`pipes/whim.delta` is the declared delta, **stated once**: per phase, the Ex
commands, behaviour cases and terminal table it changes. The lines up to a phase
are the whole difference from slim-vim at that phase, which is why a stage checks
only its last phase's (`tools/whimdelta.sh --phase N`). It used to be written out
at the end of every check, 82 growing copies.
Both run from the repository root, so a path in either names the other directly.
`tools/implhash.sh` follows paths into both when it hashes a phase, and the
scratch roots of `whim-verify` and `whim-specpass` link both in.

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
leftovers of cuts already made. See *The core and the host
are one file with a line
in it* below.

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
gone. That is *Rename a name across the whole file* below, and the general rule it states:
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
  says `EXEC` where whim-vim and slim-vim say `DYN`: see *The binary is standalone*.
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

**The sweep and the canonicalisers are Go, and so is every whim/zero cutter.**
`tools/sweep.sh` and `tools/canon.sh` are four-line wrappers onto one
`slimtools` binary built from `tools/go/` by `tools/gobuild.sh`; the 264 phase
programs call them by the same paths with the same arguments and were not
edited. All 57 cutters the whim and zero pipelines call have a Go counterpart in
`tools/go/internal/cut/`, though nothing runs them yet; the nineteen slim-only
ones have none, the slim pipeline being out of scope for that work. **The Python
tools are all still here and still work** — nothing was deleted, and the three
files a phase reaches that changed are the two wrappers and `implhash.sh`.
`tools/README.md` has the detail, including the six cutters that depend on a
lookaround RE2 does not have and what replaces each, and `tools/gocmp/` is every
comparison that produced the port's numbers, run against the Python each
replaces.

**The Go toolchain is now a hard dependency of every pipeline**, where `python3`
and `gcc` were enough before: no Go, no sweep. `modernc.org/cc/v4@v4.29.7` is
pinned in `tools/go/go.mod` and patched by `tools/patches/cc-v4-c23.patch` for
two C23 productions it lacks, and `gobuild.sh` composes them into `.cache/`
rather than vendoring — a patched `vendor/` fails `go mod verify` and is silently
overwritten by the next re-vendor. Measured: the module resolves from the local
module cache with `GOPROXY=off`, so `make clean-cache` is safe on a machine with
no network, but a fresh one needs a fetch.

**The cutover's own claim about `implhash.sh` was false, and that is the whole
reason the hasher now hashes a directory.** It was written as *the wrappers name
their Go sources in comments, so implhash still hashes the implementation* —
the `cutil.py`/`macros.py` mechanism above — and `deps()` matched
`(py|sh|txt|mk|patch)` with no `go` in it. Measured on whim 13-41, each with the
control that says the test can fail: editing `tools/go/internal/sweep/sweep.go`
moved **nothing** where editing `tools/sweep.sh` moved `5167f167 → ce069cdc`,
and over that same edit `gobuild.sh` built a **different binary**,
`.cache/gobin/6299d7c16bab003e → 85d00b718029a8b7`. The implementation changed,
the binary changed, and the memoize could not tell — which is this file's own
hazard at the scale of the whole sweep. `tools/patches/cc-v4-c23.patch` was
invisible for a *second* reason, and the two must not be confused: it is three
hops from a phase program (program → `sweep.sh` → `gobuild.sh` → patch) and
`deps()` is applied twice, so no change to the regex would have reached it. The
wrappers name it directly now.

**The fix hashes a DIRECTORY and not a list of files**, because `gobuild.sh`
already defines the binary's identity as every file under `tools/go` plus
`go.mod`, `go.sum` and the patch — so a computed traversal of that tree is
*exact*, not an over-approximation. A curated list was the artifact that failed:
the wrappers named 18 of 128 `.go` files, and four the sweep certainly reaches —
`cutil/body.go`, `cutil/definition.go`, `cutil/split.go`, `canon/strings.go` —
were in neither. It takes every file with no name filter, deliberately: a filter
is another curated list and can drop a real dependency, where taking everything
can only admit one that should not be there. The cost is stated rather than
hidden — `internal/harness/` and `internal/cut/` are hashed too, so editing a
dormant cutter re-runs every phase.

**`tools/implhash.sh` hashes ITSELF into some keys and not others, and nobody
chose that.** `deps()` returns any `tools/…` path a program's text names, and
this file's own convention is to write such a path into a *comment* so the
grep can see it — so a comment that merely **talks about** the hasher charges its
bytes to that phase's key. `tools/termcheck.py`, `tools/pipeline.sh`,
`tools/plant.py`, `tools/resolve.py`, `tools/canon.sh`, `tools/dropmacros.py`,
`tools/expand.py` and `tools/toenum.py` each explain `implhash.sh` in prose, so
slim 1, 5, 6 and 9 and zero 0, 3 and 33 all carry its bytes while whim 0 does
not. Measured with a control: appending one comment line to `implhash.sh` moves
slim 1 (`66e00026 → 5055d424`) and slim 9 (`c7cb0299 → 03ba6443`) and leaves whim
0 at `ac6ae604` exactly. **The convention cannot distinguish "I depend on X" from
"I am talking about X"**, which is the same blindness that makes it work at all.
It is over-inclusive and therefore safe — an extra key costs CPU and never a
wrong boundary — and it is left alone on purpose: making it uniform means hashing
the hasher into every key, which is a decision about whether the memoize's own
algorithm is part of the implementation it memoizes.

**It was gated the way this section asks, and it does NOT meet the "should move
no key" half.** `make slim-verify` 12 of 12 (347 s of phases in 113 s),
`make whim-verify` 13 of 13 (1,293 s in 477 s) and `make zero-verify` **46 of
46** — r32 and r41 failed under 64-way load and both reproduce their recorded
digests alone, `00b6b2bf1584` in 50 s and `8b24aa615879` in 36 s against 121 s
and 127 s, which is the `zpty.py` stall this file already documents. **143 of the
153 keys move**, and they cannot not: `sweep.sh` and `canon.sh` are what the
phase programs name. That is the shape adding zero had, and `create_cmdidxs.py`'s
floor, and `orphanopts.py`'s. The ten that hold are whim 0, slim 0, 2, 3, 4, 8,
10 and 11, and zero 1 and 40.

**The sweep was checked against the one it replaces, and not only against the
boundaries.** The pre-cutover Python `sweep.sh` and `canon.sh` out of the history,
run on zero phase 42's real unswept output — 79,380 lines, three rounds, 86 lines
removed, so not two no-ops agreeing — give **byte-identical output and a
byte-identical report**, the skip cache's `passed this text already` entries
included. 15.7 s against 8.6 s. Speed is a wash where the work is not the sweep:
zero's 46 units are 3,723 s of phases with Go against 3,744 s with Python,
because zero's phases are gcc and recordings.

**`tools/` is shared, and a change to it is gated.** A tool a whim or slim phase
names must leave `make whim-verify` and `make slim-verify` passing, and should move
no whim or slim key: compare `tools/implhash.sh` for every whim unit, every whim
edit (`--edit N`) and every slim phase before and after. Adding zero *did* move keys,
once and unavoidably — every driver sources `tools/pipeline.sh` by path, and it is
in every whim split key — so the change that added the `zero` case also made
`tools/phaserun.sh` and `tools/implhash.sh` take the delta checker from
`pipeline.sh`'s `PDELTA` rather than naming `whimdelta.sh`: measured, the moved set is
exactly the 12 whim stage keys and 82 edit keys that a one-byte change to
`pipeline.sh` alone moves, and nothing else; whim phase 0 and all 12 slim keys are
unchanged. **Never write a zero tool's path into `tools/phaserun.sh`**: every whim
edit's key reads what that file names.

```
slim-vim.c     the editor, headers and forward declarations included
whim-vim.c     the same editor with no runtime to install
zero-vim.c     whim-vim.c, on its way to an embeddable core
Makefile       the seed: builds all three, and produces them when their input moves
slim.mk        slim-vim.c = F(upstream@sha), twelve phases as make targets
whim.mk        whim-vim.c = G(slim-vim.c), the same construct
zero.mk        zero-vim.c = H(whim-vim.c), the same construct, 46 phases so far
upstream.sha   the commit slim-vim.c was produced from
slim.sha       the slim-vim.c whim-vim.c was produced from
whim.sha       the whim-vim.c zero-vim.c was produced from
pipes/         the phases that are programs: one file, or an edit and a check
tools/         the harnesses, the passes, and what the phases call
README.md  CLAUDE.md  SLIM-GOAL.md  WHIM-GOAL.md  WHIM-PLAN.md  ZERO-GOAL.md  ZERO-PLAN.md  LICENSE  .gitignore
```

**There are three pipelines, and they are the same construct.** `slim.mk`,
`whim.mk` and `zero.mk` differ only in what their phases do; the driver, the
boundaries, the oracle and the synthesiser are shared, and `tools/pipeline.sh` is
the whole of the parameterisation — with one exception, below: zero's phase list.

**Their names are symmetric, and that is maintained deliberately.** Every
variable is `SLIM*`/`WHIM*`/`ZERO*` and every target is `slim-*`/`whim-*`/`zero-*`,
so a target that exists on one side and not another is a question rather than an
accident:

| | slim | whim | zero |
| --- | --- | --- | --- |
| run a pass | `slim-pass` | `whim-pass` | `zero-pass` |
| force one | `slim-repass` | `whim-repass` | `zero-repass` |
| one phase, replay | `slim-phase-N` `slim-replay-N` | `whim-phase-N` `whim-replay-N` | `zero-phase-N` `zero-replay-N` |
| add a phase at the end | `slim-tip` | `whim-tip` | `zero-tip` |
| record, time, score | `slim-record` `slim-times` `slim-residue` | `whim-record` `whim-times` `whim-residue` | `zero-record` `zero-times` `zero-residue` |
| check every boundary at once | `slim-verify` | `whim-verify` | `zero-verify` |
| speculate every phase, then pass | — | `whim-specpass` | `zero-specpass` |
| throw away the work | `slim-clean` | `whim-clean` | `zero-clean` |

**zero is whim's twin target for target**, and its boundary tag is `r` (`r0`,
`.cache/r0`, `.reference/zero-phases`) as whim's is `q`. Four targets are one-sided
and each says why. `whim-specpass` and `zero-specpass` have no slim
twin yet: it was built for the pipeline where every phase is a program, and a
slim phase can still fall through to an agent, which is not a function and
cannot be speculated on. `slim-promote-N` has
no twin because promotion exists to turn an *agent*-recorded boundary into a
check, and every whim phase is a program. `slim-clone`, `slim-preflight`,
`slim-refpass`, `slim-compare` and `slim-passorref` have none because only the
slim pipeline has a remote to clone, a network to check for, and a reference
path run by one agent. And two targets belong to none: `clean-cache` empties
the tier-3 cache all three share, and `score` reports them side by side — bytes
to store and symbols to provide — which is why it is not `whim-score`. The distinction that matters is in the *rules*:
`SLIM-GOAL.md` changes nothing about what the editor can do and any behavioural
change is a bug, while `WHIM-GOAL.md` removes capability on purpose — so every
phase there declares its delta in advance and the harness proves it caused that
and nothing else.

**Adding a whim phase does not re-run the stages before it — `make` sees to that,
and the cache does not.** A unit's key is the unit (`13-41`), the boundary before it
and `tools/implhash.sh` of every phase in it — both parts of each, the `phaserun.sh`,
`sweep.sh` and `symbols.sh` the driver runs around them, the tools those programs
*name* and the tools *those* name, and the lines of `pipes/whim.delta` up to the
unit's last phase — not `whim.mk` and not the whole delta file. **But
`tools/pipeline.sh` is in it**, one name deep through `phaserun.sh`, and whim's phase
list is written there. Measured: one byte changed in `pipeline.sh` moves all 12 split
stage keys and all 82 edit keys (whim phase 0 and every slim phase keep theirs). So
adding N to whim's `PHASE_LIST` leaves every earlier boundary *file* in place, and
`make whim-tip` still runs only the last stage — but every earlier tier-3 entry is
stale, and the next `whim-repass` recomputes them all (`whim-specpass` is the cheap
way back). Zero's phase list is kept out of `pipeline.sh` for exactly this reason.
A new phase either starts a stage of its own — `stage 83` in the manifest, and it
must if its edit needs swept input — or joins the last one, which re-runs that
stage's edits from the edit cache (below) and its one sweep. `make whim-tip` runs
the last stage and records it, and that is the whole loop while an idea is being
tried out.

**Editing an existing phase's program does not re-run it, and `make whim-pass`
will not tell you so.** The content-keyed tier-3 check lives *inside* the
recipe, and make never gets there: a phase's prerequisite is the previous
boundary *file*, so an existing `q27.sha256` that is newer than `q26.sha256` is
"up to date" and the recipe is skipped whatever the implementation digest now
says. Measured: with `pipes/whim33.sh` (now `whim33-edit.sh`) edited so `implhash.sh` returns a
different key, `make -n whim-pass` plans **no phase recipes at all**. A rewrite
of the unreachability phase's program silently did not execute this way, and the
pass reported success.

Three targets do force it, and one of them is the one to reach for: `make
whim-phase-N` and `make whim-tip` are `.PHONY`, so their recipes always run and
the tier-3 key then decides; `make whim-repass` removes `.build-whim` outright.
**`make whim-phase-N` runs the stage that contains N** — nothing else has an input
to start from — and the stages after it still do not run. **After editing a phase
that is not in the last stage, use `whim-repass`.**

**Inside a stage, each edit is cached by its input.** `tools/phaserun.sh` keys an
edit's result by the phase, the digest of the tree it is handed and `implhash.sh
--edit N` — the edit part and what it names — and stores the tree it leaves and its
state directory under `.cache/edit/`. Editing phase K's program re-runs K's edit and
then only the edits whose input really moved, then the one sweep and every check.
Measured on stage 42-63, which is 587 s cold and almost all edits: with a harmless
line added to `whim50-edit.sh`, 21 of its 22 edits came from the cache and the stage
took **94 s**, q63 as recorded. On 73-77: 57 s with every edit run, 45 s with one,
1.6 s from tier 3 once the line was taken out again. A stage that fails is not handed to an agent: `memo.sh` runs
its phases one at a time, each with its own sweep, boundary and tier 1 — tried with
80 and 81 put back in one stage, where 80's check fails, and q81 came out as recorded.

**`make whim-specpass` is the same pass, and it waits only where it has to.**
A pass is sequential because phase N reads boundary N-1, but a repass has the
previous pass's boundaries lying in `.build-whim`. `tools/specpass.sh` runs every
stage at once on those, in scratch roots of its own, and stores each result in
the tier 3 cache under exactly the key `memo.sh` will look up — the unit, the
input digest, the implementation digest — and then `whim-repass` runs. Wherever
a phase's real input is the one speculated on, its lookup is a hit; from the
first phase whose input really changed, nothing matches and it runs as before.
The lookup *is* the "did the boundary change" check, so a wrong guess costs CPU
and never correctness. Measured from an empty whim cache, with stages: **610
seconds**, all 13 units speculated in 599 s of wall time and then 13 of 13 hits,
every boundary matching its recording — where the cold sequential repass of the
same tree took 1,587. That is the case of a change to tools that moves no output. A change to
phase K's output still runs K onwards in sequence; only the phases before it are
free.

**What that loop cannot do is falsify the boundaries before it**, and the
distinction matters more than the minutes it saves. A tier 3 replay **copies**
the recorded digest rather than recomputing it, so a warm pass agrees with the
oracle whatever the oracle says — which is how a wrong boundary went unnoticed
for eleven phases. Only a run that recomputes every digest can catch that, and
there are two. **`make whim-verify`** runs every stage at once, each on the
recorded boundary before it in a scratch root of its own, and requires each
recorded boundary back — by induction the same proof, in **597 s** on 64 CPUs, the
length of its longest stage (42-63), against 1,653 s of stages in sequence.

**A check torn mid-execution used to report success, and that is the same failure
arriving by a third door.** `sh` reads a script **by byte offset as it executes it**, so
rewriting one in place while it runs makes the shell resume at a stale offset in new
content — and `verifypass.sh` gave every unit a symlink to the ONE live `pipes/`, so a
single in-place edit could reach every running check at once. Where the tear lands
decides which symptom you see, and all three are measured: **mid-token**, a
`syntax error: unexpected "("` at a line that exists in *neither* version; **at a command
boundary after a non-zero command**, a non-zero exit with nothing printed; and **at a
command boundary after a zero one, exit 0, reported as `ok`** — ten truncation points
were tried and **ten exited zero**, silently, with the remaining assertions never run.
**Git is not the hazard**, which is worth knowing before anyone hunts the wrong thing: it
writes by atomic rename, so a running shell keeps its fd on the old inode and reads it to
the end — measured both ways, an in-place `cp` tore and a `mv -f` of the same content did
not. The hazards are in-place writers: an editor saving over a file, `sed -i` without a
temp, a `cp` onto the original. Fixed by giving each unit a **snapshot** of `tools/` and
`pipes/` the parent takes once before any unit starts — 4 MB against a run of minutes —
so a verify is a function of the tree as it was when the run began; and by **reporting
the exit status** instead of merely testing it, `if ! …` having rendered a SIGKILL, a
torn script and an assertion failure as the same word. Proven by the experiment it is
for: `pipes/zero29-check.sh` overwritten in place 25 s into a verify, while r29 was
executing it, and r29 came back `ok`. In `verifypass.sh` the output digest is compared
independently, so a torn check cannot fabricate a **boundary** — what is lost is the
check's evidence; `memo.sh`'s tier-2 path has no such backstop.

**And the tracked product file is not checked by anything, which is a fourth door.** The
committed `zero-vim.c` went **two phases stale** — r36's 79,799 lines while the pipeline
and the recorded boundary were at r38's 79,668 — and every check passed throughout,
correctly: **the boundaries are tars and digests under `.build-zero`, and
`tools/verifypass.sh` reproduces each one from the recorded boundary before it**, so
nothing in the memoize reads the file at the root. `make zero-verify` reported 39 of 39
while the product was wrong by two phases, and it was right to. The mechanism is the
merging workflow and not the phases: **`make zero-tip` records a boundary and `make
zero-pass` is what copies the product out of the last boundary's tar**, so running only
the first after every merge leaves the tracked product behind however correct the
pipeline is. A phase branch that omits `zero-vim.c` is a defect in that branch — it has
happened at 25, 26, 37 and 38 — but a merger who never runs `zero-pass` turns a defect in
one branch into a stale product whatever the branches do. **The one thing that does read
it is `make editor.c`**, which answers about whatever file is there; so does every survey
run against the repository, and a survey's line numbers taken from a stale file are two
phases wrong with nothing to say so.

**There is now a guard, and it is deliberately a warning and not a failure.** `zero.mk`
compares the tracked `zero-vim.c` against the last recorded boundary's and, when they
differ, prints what the file is, what it should be and the one command that fixes it —
proven both ways, silent on a tree whose product is r41 and, with one line appended,
*the tracked zero-vim.c is NOT r41 — 79661 lines here*. A target that **refused** there
would refuse the normal case: between a phase landing and `zero-pass` running the product
is *expected* to lag its boundary, and such a target would be disabled within a day.
`zero.mk` is in no implementation digest — `tools/implhash.sh` follows only `tools/` and
`pipes/` paths — so the guard moves no key, re-runs no phase and cannot change a boundary.

`make clean-cache
&& make whim-repass` is the sequential run, and the one that *produces*
boundaries rather than checks them: record from a cold pass, then verify. Do it
before a push, and whenever a
**shared** tool changes — `sweep.sh`, `canon.sh`, **everything under
`tools/go/`**, `phasecheck.sh`, `whimdelta.sh` — though those are in every
phase's implhash, so everything re-runs then anyway. **The Python `deadsweep.py`,
`typereach.py`, `funcreach.py`, `deadfields.py`, `deadenums.py` and `cutil.py`
are no longer on that list, and the reason is not that they were deleted**: they
are all still here and still run standalone, but since the cutover no phase
reaches them, so editing one changes no pipeline and moves no key. Their Go
counterparts under `tools/go/internal/` are what a phase runs, and they are
hashed as a directory rather than as a list of files — see `tools/implhash.sh`,
where a list of 18 of 128 named files is the mistake that rule exists to
prevent.
`tools/zhostonly.py` is deliberately **not** in that list: it is named by zero phase
checks and by nothing else, so it enters no whim or slim key at all. Adding it moved
none — measured as 107 whim and slim keys and 20 existing zero unit keys, all identical
either side — and **editing it since has cost only zero keys**, six when phase 26 changed
its exception grammar, four when phase 27 added two named exceptions and **ten when
phase 28 added `gettimeofday` as a host word** (zero units and edits 20, 21, 25, 26 and
27), with 107 whim
and slim keys identical each time. It is now named by the checks of phases 20, 21, 25,
26, 27, 28, 30, 32, 34 to 39 and 41 to 45, each of which runs it on **its own** output,
and by five edits besides.

**`upstream.sha` is tracked, and that is load-bearing rather than tidy.** It is
what `make` compares the branch head against, so a checkout without one has
nothing to compare and fires a whole pass on a tree that is already correct —
which is the same hazard, arriving by a different route, that made the
dependency content-based instead of a timestamp. The makefile writes it after a
pass succeeds; committing it alongside the `slim-vim.c` it describes is what keeps
the next `make` cheap.

`README.md` is the front door and carries no figures; this file and `SLIM-GOAL.md`
are the authority, which is what keeps a third description from drifting.

`tools/` and `pipes/` are the only tracked subdirectories at the root, and
`tools/` has a `README.md` of its own; `tools/templates/` beneath it holds the makefile Phase 3 installs into
the staging tree.
Nothing in it is part of the build; the build reads `slim-vim.c` and nothing else.

Six things a pass produces appear untracked, and `.gitignore` names them:
`vim`, which the build adds and `clean` removes (and `slim-vim`, `whim-vim` and
`zero-vim`, the same way); `.reference/`, the recorded
baselines and phase digests beside the previous `slim-vim.c` (see below);
`TRANSCRIPT.md`, which `/export` writes when the user asks it to;
`upstream/`, the pristine vim tree a pass clones in, works on and deletes —
8,581 files that must never reach a commit, and which do not exist between
passes; `.build-slim/` (and `.build-whim/`, `.build-zero/`), the phase boundaries a pass leaves behind — a tar and a
content digest per phase, plus each phase agent's stream and its elapsed
seconds; and `PROGRESS.md`, the transient insight log whose contents are folded
into `SLIM-GOAL.md` and this file and then deleted. `upstream.sha` is deliberately
*not* ignored: it is the record of what `slim-vim.c` was produced from.
It also names `editor.c`, which `make editor.c`
writes and which is a **prefix of a tracked file** git already has every byte of.
`.gitignore` also names what the tools and the editors leave lying
about: `*.sw[a-p]`, `__pycache__/`, `*.pyc` and `.claude/`. **The swap pattern is a
range and not `*.swp`, because vim names the FIRST swap file `.swp` and then walks
backwards** — `.swo`, `.swn`, `.swm` and on down — so a second session on the same file,
or a crashed one, leaves a name `*.swp` does not cover; naming only that left `.swn` and
`.swo` untracked-but-reported in the root, which is how it was noticed. The `.gitignore` upstream shipped named 91 paths, of which two still
existed — `src/testdir/`, `runtime/doc/tags-*`, `nsis/icons/*` and the rest
went with the tree they belonged to.

There is no `src/`, no `proto/`, no `runtime/`, no `testdir/`, no `xxd`, no
`libvterm`, no `po/`, no `objects/`, no `install-sh`, no `config.mk`.

`LICENSE` is not optional: clause II.1 requires Vim's licence to be included
unmodified in a modified Vim, and the file headers that carried the attribution
went with the comments. It is **copied from the clone by each pass**, not
maintained here, so it is byte-identical to upstream's by construction.

## Build

```sh
make                 # from the repository root
```

The targets you would type are the products, `slim-vim`, `whim-vim` and
`zero-vim`, and `clean`, which removes all three binaries. Everything upstream had —
`all`, `install`, `test`, `proto`, `tags`, `depend`, `lint`, `shadow`,
`distclean` — is gone, along with the second makefile that recursed into
`src/`. `all` went with them: it is a convention for builds with more than one
product, and this one has `vim`.

**`vim` depends on `slim-vim.c`, and `slim-vim.c` depends on upstream**, which is a
remote rather than a file: every `make` asks `git ls-remote` for the branch
head and compares it against `upstream.sha`. It cannot be a timestamp — `git
clone` writes every file at checkout time in arbitrary order, so a stamp
landing a second after `slim-vim.c` would fire a multi-hour pass on a tree that is
exactly right. When the sha matches, or the remote is unreachable, `make`
builds the committed `slim-vim.c` and says so in one line. When it does not, the
recipe clones `upstream/`, deletes its `.git` immediately, runs the pass, and
writes `upstream.sha` only after the pass has left a `slim-vim.c` behind, so a
failed pass leaves the record alone and the next `make` retries.

**There is no configure and nothing is generated.** `configure`, `configure.ac`,
`config.h.in`, `config.mk.in`, `osdef.sh`, `pathdef.sh`, `link.sh` and
`toolcheck` are gone. What they used to emit is ordinary text inside `slim-vim.c`,
under its `config.h`, `osdef.h` and `pathdef.c` banners. To change the build,
edit those.

The build runs no shell script, writes no source, and has no object phase: one
`gcc` invocation turns `slim-vim.c` straight into `vim`, which is the whole of
`clean`'s job to remove. `make clean && make` is a real from-scratch rebuild and
it is one command. `-j` has nothing left to parallelise.

**The compile line is `-O0 -static -s` and nothing else.**

- **No `-I`.** Every include names a path that resolves from this directory.
- **No `-D`.** `config.h`'s content is included outright, not behind
  `HAVE_CONFIG_H`. `_REENTRANT` did nothing under musl.
- **No `LDLIBS`.** musl's libm is part of libc, so even `-lm` is unnecessary —
  a build against another libc would need it back.
- **No `_FORTIFY_SOURCE`**: its checks need object sizes the optimiser computes,
  so it does nothing at `-O0`.
- **No `-g`**: debug info records a line number for everything, which would make
  a formatting change move the binary and destroy the cheapest verification
  there is. `gcc -O0 -g` still works when you need it — the DWARF enumerator
  check below does.

`-O0` is a deliberate trade: the tree is rebuilt far more often than the editor
is used, and the editor is a few times slower for it. Reconsider if that stops
being true.

### The binary is standalone

`-static -s`: nothing to resolve at run time, no symbol table. gcc defaults to
PIE here, so the result is a **static-PIE** — `readelf -h` still says `DYN` and
ASLR still applies.

**`zero-vim` adds `-no-pie`, and is an ordinary static executable instead.** A
static-PIE is position-independent code that relocates itself at startup: whim-vim
carries a dynamic section and 1,986 `R_X86_64_RELATIVE` relocations for its own
start-up code to apply. Without PIE the linker fixes every address, so `readelf -h`
says `EXEC`, `readelf -l` shows no `INTERP`, `readelf -d` finds no dynamic section and
`readelf -r` no relocation — and the image is 894,088 bytes against 955,976 for the
same source. Zero phase 0 requires all four facts. What it gives up is ASLR of the
image; what it gains is a core a host can place without a loader.

**`zero-vim` also compiles with `-fno-stack-protector`** (zero phase 1). gcc here
enables `-fstack-protector-strong` by default, which puts a canary in every function
with a local array and a call to `__stack_chk_fail` in the object — a symbol the
core would need from libc for nothing the editor does. Without it the object's
undefined symbols go from 80 to 79, exactly that one, and the binary from 894,088
bytes to 869,512; the harnesses see no difference. Phase 1 requires all four readelf
facts again.

**`ldd` is not the check.** On a static-PIE it prints a musl line that looks
like a dependency and is not one. `readelf -l` for `INTERP` and `readelf -d`
for `NEEDED` are, and both come back empty.

The four combinations, measured:

| | unstripped | stripped |
| --- | --- | --- |
| dynamic | 2,198,472 | 1,986,312 |
| static | 3,015,552 | **2,208,088** |

Static costs 817 KB and `-s` takes 807 KB of it back, so standalone is within
10 KB of what the dynamic unstripped build cost.

**`-s` breaks `nm`**, which is the check for what has external linkage. Build
without it when you need symbols: `make LDFLAGS=-static`, or `make CFLAGS=-g
LDFLAGS=-static` for the DWARF enumerator dump. The `.text` of either is
identical to the shipped one.

What usually makes a static musl binary a lie is `dlopen()`, and there is none.
The two libc facilities commonly stubbed out in static builds both work here:
`iconv_open()` (musl's tables are compiled in) and `getpwnam()` (musl has no NSS
to miss, so `~root/` expands).

## The three-tier memoize

**`slim-vim.c` is a function of upstream, and this repository is that function,
memoized.** Everything else here follows from taking that literally.

```
slim-vim.c = F(upstream@sha)          decomposed as    p_N = f_N(p_{N-1})
```

Each phase `f_N` has three implementations, at three costs, and a pass falls
through them in order:

| tier | what it is | cost | what it can do |
| --- | --- | --- | --- |
| **3** | the **result** — the boundary itself | 0.17 s | nothing; it is an answer |
| **2** | the **code** — `pipes/<pipeline><N>.sh`, or a stage of `-edit.sh` and `-check.sh` parts | 1–600 s | exactly what it was written for |
| **1** | the **agent** — `claude -p`, one phase | 5–17 min | cope with something it has not seen |

**Tier 3 is keyed by content, not by time.** The key is the input boundary's
digest and the implementation's digest together — `tools/implhash.sh` hashes
the phase's program (for a whim stage, both parts of every phase in it, the sweep
between, and the declared delta up to its end) plus every tool, patch, table and
template it names — so a
cached result answers exactly one question: *this implementation, applied to
this input*. Measured: Phase 4 costs 63 s cold and **0.17 s** cached; editing
its program changes the key and it runs again; reverting the edit restores the
old key and it is cached again. That is stronger than a timestamp, and it is
what makes editing one phase re-run that phase and the ones after it rather
than all ten.

**And the input half of that key can stop being a function of the input, which is the
one property tier 3 rests on.** `tools/memo.sh` built it as
`cat "$build/$TAG$((first - 1)).sha256" 2>/dev/null || cat "$build/input.sha256"` —
asking *did `cat` fail* where `tools/verifypass.sh` and `tools/specpass.sh` both ask *is
this the first unit*. Those are the same answer to different questions, and the
difference shows only when a **phase list has a gap**: a missing `r<first-1>` fell
through to `input.sha256`, which is `whim-vim.c`'s digest and never moves, so the key
stopped varying and a cached result came back whatever the real input became. It was not
hypothetical — two zero phases hit it independently while numbered into a gap left for
phases that had not been written yet, and `make zero-tip` reported a boundary in twelve
seconds that was one of them applied to the wrong tree, with `long time(long *tp);` still
in it. It now asks the question the other two ask — test `first = 0`, otherwise require
the boundary and **refuse** — so a gap is `memo: zero unit 40 wants r39, which does not
exist.` and exit 1. **Deliberately not done**: `verifypass.sh` and `specpass.sh` still
chain a unit to `r<first-1>` and so still require a contiguous list. They fail loudly on
the missing tar rather than silently, so they carry no version of this defect, and
teaching all three to read a unit's input from the stage manifest would make gaps
*legal* — a design change about whether phase numbers may have holes, not a bug fix.

**Tier 1 is not a function, and is never treated as one.** Two agent runs on
identical input have been measured to differ — Phase 5 produced a different
`edit.c` the second time. Its result is cached, but its boundary is *advisory*
and never a check.

**The point of tier 1 is what it leaves behind.** When an agent runs,
`tools/synth.sh` diffs the two boundaries and writes the difference out as
`tools/patches/p<N>-residue.patch`, plus a `pipes/<pipeline><N>.sh` that applies it if the
phase had no program at all. So the same input never costs an agent twice, and
a phase acquires a fast path the first time it is ever run. A cached agent
answer saves one repetition; a *synthesised program* saves every future one.

**The synthesised form is a legitimate tier 2 and a poor one**, and the
difference is the whole of the remaining work. A patch reproduces one
transformation of one input, says nothing about why, and fails the moment
upstream edits a line it touches. A rule — a computed set, a table, a
transformation over every line of a shape — does not care. So:

> **The residual patch size is the measure of how well a phase is understood.**
> Zero means the phase is understood. A thousand lines means it is remembered.

`make slim-residue` is the scoreboard. As of this writing:

```
  phase  tier          residue  notes
  0      program             0  computed
  1      program           797  a deliberate patch: the edits are fixed
  2..8   program             0  computed
  9      program           134  what is genuinely a decision
         total             931
```

Phase 1's 797 lines are not a failure to understand it — its content genuinely
*is* a set of fixed edits, and the tree cannot state them. That is the one
place a patch is the right answer rather than a placeholder. Phase 9's 33,670
were the opposite: a recording of 33,670 lines, produced automatically the
first time it ran. Replacing it with rules took it to **134**, and what is left
is exactly what `SLIM-GOAL.md` says cannot be mechanical — 37 fall-through
attributes, the three `pum_set_*` functions written out because C cannot paste
tokens, the version strings — plus twelve empty banner pairs that could still
go. A 251-fold shrink, and the phase went from 943 seconds to **34**.

The rules that did it are worth naming, because each was a *general* fact the
tree could state rather than a special case. `ex_cmds.h` is inlined twice with
`EXCMD` meaning two different things either side of an `#undef`, and an
expander keyed by name takes the second body for both — so the two definitions
are split by their `#undef` region first, and then the enum and the table each
expand from their own. `_()` and `NGETTEXT` are excluded from expansion because
`format_arg` is what keeps `-Wformat` seeing through them, so the check there is
that the *warning set* is unchanged rather than that it builds. And macros are
deleted before conversion in exactly one round, because the round count decides
how many constants ever reach `toenum.py`.

**A pass costs 411 seconds** with every phase a program, measured by a cold `make
slim-repass` from an empty cache: 33 s, 17 s, 5 s, 1 s, 63 s, 8 s, 12 s, 39 s,
153 s, 34 s, 22 s, 24 s. It cost 24 minutes with Phase 9 at tier 1, and 67 when
one agent did all of it. **Phase 8 is the largest part, 153 s and over a third of
the total**, being compile-bound — the static loop plus eight sweep rounds, each
a gcc compile of a 177,000-line file — and is where the next minute comes from.
The pass is sequential by nature; checking its twelve recorded boundaries is not,
and `make slim-verify` does that in the 170 s of its slowest phase.

**The last pass produced a binary byte-identical to the committed one** and a
`slim-vim.c` differing by 49 lines, all of it Phase 8: a redundant `static` on
definitions whose earlier prototype already gives them internal linkage, and
one dead prototype kept. Neither changes the program — `-s` strips the symbol
table, so the two compile to the same bytes — and the committed form is the
better one, so it stands. Those 49 lines are Phase 8's real residue and the
next thing to drive to zero.

**A tier-2 failure is not an error, it is the construct working.** The pass
falls through to tier 1, which produces an answer and a new patch; `make`
wraps that as `passorref`, and `tools/repair.sh` then hands the failing phase,
its error and the agent's account to an agent whose job is to fix the
*program* — preferring a computed rule over a constant, and saying plainly when
a change genuinely needs judgement, in which case that one phase reverts to an
agent and the other nine do not.

**`NO_AGENT=1` refuses instead of falling through**, and `zero.mk` sets it for
every unit it runs. The fallback costs a `claude -p` run, and a phase program
that refuses on purpose — an assertion doing its job, a probe calibrated against
the wrong boundary — is a failure to read, not a question to hand to an agent. It
cost four minutes once, while zero phase 3 was being written. Slim is unguarded,
because its phases are where the agent tier still earns its place.

**The top level is already an instance of this.** `upstream.sha` is tier 3 of
`F` itself: when the branch head matches, the cached `slim-vim.c` is returned and
nothing runs at all.

## Testing

There is no upstream test suite in play. Four harnesses stand in for it, all in
`tools/`; the baselines they are compared against are in `.reference/baselines/`,
which **a pass records in Phase 1 and a fresh checkout does not have**. Until one
has run there is nothing to compare against — the harnesses still run, they just
have no older recording to disagree with.

**`tools/verify.sh .reference/baselines` runs all of them concurrently and gives
one verdict, in about 18 seconds** — eight of them the build. Use it after any
change; add `--enums` for the DWARF check. It is proven to fail on a broken
build, on a behaviour change and on a blank line landing in the generated
command table.

### `.reference/` is the frozen state, gitignored, and optional

Seven things, each with a reader: `baselines/`, which `verify.sh` and
`whimdelta.sh` compare against; `zero-baselines/`, which `zerodelta.sh` compares
against; `slim-phases/`, `whim-phases/` and `zero-phases/`, the recorded boundary
digests `oracle.sh` checks each phase against; and `slim-vim.c` with the `slim-vim`
built from it, the left-hand side of `refcheck.sh`. **It is not tracked and it
is not a precondition**: a pass produces it, so a checkout that has never run
one has no `.reference/` at all and everything here describes what exists
afterwards.

**It holds no copy of the documents, `Makefile`, `LICENSE` or `.gitignore`.**
It once did. Nothing failed on them — `refcheck.sh` reported them "changed",
which was true of every pass — and they were four days and hundreds of lines
stale when they went. Those files are tracked, and `git diff` is the comparison.

**`baselines/` is the part that matters most, and the only part no commit can
reconstruct.** It is *data* — what the harnesses recorded from the Phase 1
binary, the last build that changes behaviour on purpose — and every phase since
has been required to match it. The source and binary are `git archive` of a
commit and an 8-second build, and the phase digests are a pass from an empty
cache.

**Never regenerate it from the current binary**, which would make the comparison
self-fulfilling. A pass records it in Phase 1 either way, but the recording only
proves something when there is an older one to compare it against first: the
first pass in a fresh checkout is self-certifying on behaviour, and every pass
after it is not. That is the whole reason to keep this directory across passes,
and the reason it is the one thing worth copying if this tree is ever moved.

**`zero-baselines/` is recorded from a binary, and that is not this mistake.** The
mistake is a pipeline re-recording from its *own* current binary, which then agrees
by construction. Zero phase 0 records from the pipeline's immutable input —
`whim-vim.c`, built with whim's compile line — three runs that must be identical;
an existing set is compared and never overwritten; and the zero binary is then held
to it. A tier-3 hit on phase 0 records nothing, so `zero-pass` and `zero-phase-N`
(and every zero target that goes through them) end with `zero-baselines-check`,
which **refuses** when `zero-baselines/` lacks `screen/`, `memline/`, `ref-excmds.txt`,
`ref-argv.txt`, `ref-pty.txt` or `ref-term.txt` — the shape phase 3's instrument records
and **phase 40 grew by one**, which is why the check names the shape rather than merely
testing that the directory exists — and names the fix,
`rm -rf .reference/zero-baselines .cache/r0 && make zero-phase-0`. It is in
`zero.mk`, which no key reads.

`slim-vim` there is built with `SOURCE_DATE_EPOCH=0`, so it is reproducible
byte for byte and usable as the left-hand side of a tier 1 check:

```sh
SOURCE_DATE_EPOCH=0 gcc -O0 -static -s -o /tmp/t/slim-vim slim-vim.c
cmp /tmp/t/slim-vim .reference/slim-vim
```

**The source and binary go stale the moment the tree moves and nothing warns
you.** They are a snapshot of a commit, not a mirror, and they are meant to be
the *previous* pass's output; refresh them when a pass is accepted, rather than
trusting a copy whose age you cannot see.

Note what that last proof was for: **`gcc` exits 0 with warnings**, so a check
that tests the exit status of the warning sweep passes always. `verify.sh` was
written that way first. The requirement is that the sweep prints *nothing*.

**`tools/behaviour.py`** — `python3 tools/behaviour.py <binary> <outdir>` runs 67 independent
editing cases and writes one file per case; run it against two binaries and
`diff -r` the directories. It covers CTRL-A/CTRL-X over every `'nrformats'`,
autoindent, `'formatoptions'` and comment leaders, insert-mode
CTRL-V/CTRL-W/backspace, multibyte motions and case changes, substitution
flavours, operators and text objects, macros, undo/redo, registers, marks, sort,
filters, `'fileformat'`/`'bomb'`/`'binary'`, and four cases for `+extra_search`.

**The cases run at once**, and so do `exsweep.py`'s 600 dispatches: each already
had a directory of its own, and each writes a result nothing else reads, so the
recordings are the same bytes — checked against the baselines — while the harness
takes 1.2 s instead of 4.4.

A case that writes no file records `<NO FILE WRITTEN>`, so a crash cannot pass
as a match, and every artifact is deleted before the run — **a harness that
diffs an output file it did not first delete keeps passing on the previous
run's file.**

**The harness was proven able to fail before it was trusted.** Making
`do_addsub()` return FAIL — CTRL-A a no-op — makes exactly the CTRL-A cases
differ and nothing else. A test suite that cannot fail is not evidence.

**`tools/create_cmdidxs.py`** regenerates what upstream generates with
`create_cmdidxs.vim`, which needs a vim with `+eval` and this build has none.
`python3 tools/create_cmdidxs.py slim-vim.c --check` verifies the table in place, between
the `begin`/`end ex_cmdidxs.h` banners; `--update` rewrites it. It refuses to
generate anything from a parse that finds fewer than **80** command names, because
a regex that stops matching otherwise yields a plausible-looking all-zero index.
Treat it as a canary: a pass that reshapes the command table, or merely
re-indents a line of it, shows up here rather than as a wrong answer later.

**That floor is live in the zero pipeline**, where it is not a canary but a
constraint. `zero-vim.c` has no `ex_cmdidxs.h` banners left — whim's Phase 80 took
the derived index with the 489 stub rows — so what zero uses is `names()`, and
`tools/zexcmds.py` enumerates the whole command sweep through it. Zero phase 6
deleted six rows, phase 7 a seventh, phase 8 five more and phase 10 `:file`'s,
111 → 98, where it has stayed — phases 11 to 45 remove no row, and every phase from 20
on touches no `cmdnames[]` row at all — **which is why
the floor is 80 and was 100**. It was lowered in phase 8's
own commit, which is the phase that crosses it (`ZERO-PLAN.md` decision 8), never
silently and with the reason in the tool's docstring; the margin is **18 rows**.
Two things that edit taught, both measured. The failure is not
the one the name suggests — `names()` tries both parsers with `check=False`, so a
99-row table came back as `no command table found in either shape` rather than as a
count. And **it moved 28 of the 115 implementation keys**: 6 whim stages, 15 whim
edits, 2 slim phases and 5 zero phases, the last five only because their programs
name the tool's path in a comment and `implhash.sh` greps for paths. `make
slim-verify` (12 of 12) and `make whim-verify` (13 of 13) are the gate rule 9 asks
for, and both were green after it.

**`tools/orphanopts.py` has a floor of its own and it moved the same way, at zero
phase 12.** It parses `options[]` for every `&p_xx` and refused a table it found fewer
than 100 distinct globals in — the same "a regex that stopped matching would pass for
the wrong reason" argument. Zero phase 12 drops six rows, 102 -> 96, and
`tools/zerodelta.sh` runs that tool beside its harnesses, so crossing the floor would
not fail that phase: it would fail the **delta check of every zero phase after it**.
Lowered to 80 in phase 12's own commit, with the reason in the docstring and the same
number and the same sentence as `create_cmdidxs.py`'s, so the two floors stay one
idea; 16 globals of margin. It cost **12 whim stage keys, 4 whim edit keys, 12 zero
unit keys and 3 zero edit keys, and no slim key** — `whimdelta.sh` names the tool and
`implhash.sh` hashes what a delta checker names. The tool's *verdict* is unchanged
everywhere, `slim-vim.c`, `whim-vim.c` and every zero boundary being far above either
floor, so no boundary can move and the cost is CPU in a repass; `make whim-verify` and
`make slim-verify` are the gate and both were run. Zero phase 20 takes `'termresize'`,
and every phase after it takes no row, so the figure the floor reads is still **95
distinct globals**, 15 of margin — `whim-vim.c`'s 102, less phase 12's six rows and phase
20's one.

**The row count beside it is 109 and not the 107 carried since phase 16**, and the
difference is a method and not a removal: measured on the committed `zero-vim.c`, rows of
`options[]` whose name is not a `t_` terminal capability number **109**, against
`whim-vim.c`'s 116 and `slim-vim.c`'s 466, and 116 − 6 − 1 = 109 exactly. **The globals
figure is the one that has tracked every removal and the one the tool actually parses**,
`orphanopts.py`'s "rows" being the set of distinct `&p_xx` it finds; prefer it when the
two are quoted together.

**`tools/zhostonly.py` is zero's third tool of this kind, and it asserts a place rather
than a count.** Zero phase 20 moves the signal handlers, the window size, the terminal
mode, the delay and the wait into a `host_*`/`musl_*` block at the bottom of
`zero-vim.c` — and inside ONE translation unit that frees no `nm -u` symbol, because a
symbol leaves when its last *caller* leaves the file. So the phase's real claim is
**where** the code is, and this is that claim as an assertion: 45 host words —
`sigaction`, `kill`, `ioctl`, `tcsetattr`, `select`, `nanosleep`, `gettimeofday` since
phase 28, `getpid` since phase 36, every `SIG*`, `struct
termios`, `fd_set`, `ICANON`, `VMIN` — and every mention of every one of them must be
inside the block. Exceptions are named with their reason and their exact count — and since zero phase 26
**a count is a tuple of the values it takes**, one per phase that runs the tool, because
the core's vocabulary shrinks between them and a single number would make a phase that
narrowed it look like a breakage. They are the whole of what the core still says: `signal_info[]` and `deathtrap`
name `SIGHUP` and `SIGTERM` because that is the *message* the editor prints,
`vim_handle_signal` re-raises a deferred deadly signal with `kill`, and the core
declares that `kill` itself. Run on the committed `zero-vim.c` it reports **64 mentions
of the 45 words, all inside the 256-line block**, and **6 of its 18 named exceptions live
in the core** — `SIGHUP` and `SIGTERM`, three times each, and nothing else, because the
editor **prints** those two names. **The memline arc needed no new word and no new
exception**: phase 41's `host_alloc` and `host_free` have sat below `musl_suspend()`'s
brace since phase 35, and none of `malloc`, `free`, `realloc`, `max_align_t` or `alignof`
is in the vocabulary. **The clock's exceptions are what
the tuple was built for, and they are now spent.** `elapsed_T`'s `struct timeval`
exception ended at phase 26, which made it the core's own tagless struct of two `long`s;
phase 28 then added `gettimeofday` to the word list and named the five core call sites
phase 26 had moved, at the counts they had at r20, r21 and r25, because `\b` does not
match inside `musl_gettimeofday` and the bare libc name is what is being asserted about.
It ignores string literals — the file
contains `hash_remove(&buf_hashtab, hi, "close buffer")`, and a tool that read that as
a `close()` would report the buffer layer as filesystem code — and `#` lines, because
`#include <errno.h>` and `#include <sys/ioctl.h>` name two of the words. Like the two
floors above it **refuses to pass vacuously**: the host region must be found, must
define all fourteen of its functions, and must itself mention `sigaction ioctl
tcsetattr nanosleep select kill`. **There is no file split for it to survive into** — `ZERO-PLAN.md` §4c settled on one
file with two parts — so what it reads is a *region*, from `host_winch_pending` to
`musl_suspend`'s last brace, and that is why zero phase 26 had to define
`musl_gettimeofday` inside the block rather than below it.

### Four things a harness here has to get right

**A binary's own name changes what it does.** `parse_command_name()` reads
`argv[0]`: a basename starting with `r` turns on **restricted mode** and every
shell-out fails, `e` selects evim, `g` the GUI, and `view`/`ex` prefixes change
the mode again. A reference binary saved as `ref` made `:%!sort` and
`:r !echo` fail against a binary that was byte-identical to one called `vim`.
Every harness stages the binary under test into a temp directory as `vim`,
whatever it was called outside — so the recorded baselines always describe
`argv[0] == "vim"`, and renaming the product could not silently move them.

**That staging is one function per pty layer, and it is one function because of a
race.** `shutil.copy2` holds a write fd on its destination, and a `fork` in another
thread — every zero harness runs its cases in a `ThreadPoolExecutor`, and so do
`termcheck.py` and `ptycheck.py` — hands that thread's child the same fd until it
execs; `execve` refuses a file any process holds open for writing, so the *copying*
thread's own exec dies with `Text file busy`. Measured in zero on r1: 0 of 20 runs of
`zcases.py`/`zargv.py` idle and **8 of 20** under a steady 64-way load, and a
`make zero-verify` under that load lost **15 of its 18 units**, almost every one of
them this. `stage()` copies **once per binary, under a lock, in a child process**,
so the write fd never exists in an address space that is forking.

**There are two `stage()`s and the duplication is deliberate.**
`tools/zstream.py`'s is zero's, called by every zero harness and every zero phase
check; `tools/ptyrun.py`'s is the pty layer's, called by `termcheck.py`,
`ptycheck.py`, `ztermcheck.py` and the eight zero checks that drive a terminal. In
`ptyrun.py` it is **5 exec failures in 100 idle runs** of `termcheck.py` — 1,900 pty
sessions — against **0 in 100** after, and 1 of 60 against 0 of 60 interleaved in one
loop; **load does not make it likelier** (0 in 60 under a steady 256-way load, 0 in
20 under an oscillating 128-way one), because what overlaps is the nineteen threads'
*startup*, which a loaded machine spreads apart. `ptyrun.py` does not import
`zstream.py` because `implhash.sh` follows named paths one level and `pipes/slim1.sh`
names `termcheck.py`, which names `ptyrun.py`: the import would put a zero tool in
slim's and whim's implementation keys for ever.

**A harness that stages a binary makes a directory, and one that never removes it fills
`/tmp` — which is found somewhere else, as something that looks unrelated.**
`tools/termcheck.py` leaked **two**: `ask()` made a scratch directory per pty session, 19
terminals on every invocation, and `_HOME` made one per process at import, and neither was
ever removed, where `tools/ptyrun.py` beside it has always registered an `atexit` rmtree
for its staging directory. Measured before the fix: **182,319** of them were lying in
`/tmp`, 100,280 from `termcheck.py` and 82,039 from `tools/ztermcheck.py` — and **an ext4
directory that full answers `mkdir` with `ENOSPC` on a disk with 70 GB free**, which is
how it surfaced: it failed **zero phase 9** mid-run, a phase that has nothing whatever to
do with terminals. `ask()` now wraps the session in try/finally and `_HOME` gets
`ptyrun.py`'s `atexit`. **What it changes is what the harness leaves behind, not what it
reports**, and that is the thing to check rather than assume: a full 19-row run is
byte-identical to `.reference/baselines/ref-term.txt`, and the leak count is **0 after a
complete `make slim-verify` and `make whim-verify` together**, which before the change
were the two largest producers in the tree. `termcheck.py` is in every pipeline's
implementation digest, so keys moved and were measured rather than predicted, one unit per
pipeline either side: slim phase 1 **moved** and slim phase 9 **same** — it names neither
the tool nor anything that does — whim stage 13-41 moved and whim phase 0 same, zero 33
and 39 both moved. The gate this file asks for when a shared tool changes was run and
green: `slim-verify` 12 of 12 (431 s of phases in 120 s) and `whim-verify` 13 of 13
(1,700 s in 598 s), every boundary reproduced, so the cost is CPU in a repass and not
correctness.

**A tool reached by `import` and never named as a path was in no implementation key
at all**, and three were. `implhash.sh` extracts dependencies by grepping a program
for `tools/…` *paths*; Python tools reach each other by module name, so
`import ptyrun` named nothing it could see. Measured both ways: a one-line change to
`termcheck.py` moved 28 of the 144 keys (1 slim, 12 whim units, 1 whim edit, 12 zero
units, 2 zero edits) and the same change to `ptyrun.py` moved **none**.

**Two of the three were transformers, and that is why it mattered.** `ptyrun.py` is a
harness and a harness writes no tree, so its invisibility cost nothing. But
`tools/cond.py` — imported by `plant.py` and `resolve.py`, which resolve the
conditional directives in slim's Phase 5 — and `tools/macros.py` — imported by
`toenum.py`, `expand.py` and `dropmacros.py`, which are Phase 9's macro expansion —
*produce the tree*. Editing either would have changed a phase's output, moved no key,
and let a warm repass replay the old boundary and report success. That is the hazard
**Editing an existing phase's program does not re-run it** describes, one level
deeper: the phase's own program is untouched and innocent, and the thing that
actually changed is invisible. It was harmless only because nobody had edited those
two since the caches were warmed, which is luck rather than a property.

**The fix names the path in a comment beside the import**, in all six importing
files, and leaves `implhash.sh` alone. `implhash` greps, and does not know what a
comment is — the same mechanism that re-keyed zero phases 2 and 4 when they named
`create_cmdidxs.py` in a comment, used deliberately here. Measured: 29 keys move
(slim 1, 5, 6, 9; all 12 whim stages; whim edit 80; 13 zero units), no boundary
moves, and `slim-verify` 12 of 12, `whim-verify` 13 of 13 and `zero-verify` 20 of 20
all pass. **Do not delete those comments**; each says so in place.

**The product is `slim-vim`, and that name was checked rather than assumed.**
It matches none of the prefixes above and falls through to plain vim: run side
by side against the same binary named `vim`, `:r !echo` works and `readonly` is
off under both. Any *other* name still needs the same check before it is used.

**Anything about terminals, mappings, screen drawing or `:set` reporting needs a
real pty** — `-e -s` never initialises the terminal and reports empty values.
The pty driver uses `pty.fork()`, writes keystrokes with delays, strips ANSI
escapes, and puts a hard timeout on the read loop: an error at startup leaves
vim on a `Press ENTER` prompt and the loop would otherwise hang for ever. Before
concluding a pty harness is broken, check that what it reports is not simply
true — one scenario that looked wrong was `0Dworld`, which never enters insert
mode.

**A pty harness waits on content, never on a clock**, and `tools/zpty.py` is where
that is written down. It used to type the next key once output had been quiet for
0.25 s, which is a reading of the machine's load: under enough of one the editor
stalls mid-redraw, the key goes in early, and the answer the scenario asked for is
wiped before any redraw ends on it. It now waits for one more `\x1b[?25h` —
show cursor, which is where a redraw *ends* and where `tools/zscreen.py` snapshots
— and only then asks about quiet. **The window size is set by the child before it
execs** for the same reason: `TIOCSWINSZ` on the master after `pty.fork()` is a bet
that the parent beats the child's startup, and losing it leaves a 24-row scroll
region on a 30-row screen, where three message lines overwrite each other on the
bottom row. Measured against the recorded baselines under one oscillating 192-way
load, alternating the two versions: **16 of 60 runs failed before and 0 of 60
after**. A deadline is still there and it is the failure path: a wait that reaches
it writes a `stalled` section into the record, says so on stderr and exits 1,
rather than returning a short capture silently.

**And fourteen zero checks throw that message away, so the phase fails with
nothing printed.** `tools/zrecord.sh` is started in the background as
`… >/dev/null 2>&1 &` and collected later by a bare `wait $pid` under `set -eu`,
so a stalled recording exits the check with rc 1 and no output at all. Measured:
in one `make zero-verify`, r41 printed `zpty.py: NO REDRAW ENDED INSIDE THE
DEADLINE` — its recording is in the foreground — while **r32 printed a successful
assertion as its last line and then exited 1**, and the two failures are the same
stall. The shape is in the checks of zero phases 21, 25, 26, 27, 28, 29, 30, 31,
32, 34, 35, 36, 37 and 41. It is NOT the failure `verifypass.sh` was hardened
against: these do fail, and the harness does say which unit and where its log is.
What is lost is only the reason — but the reason is what tells a reader whether
the phase is wrong or the machine was busy, so a whole verify can be spent
looking for an assertion that never failed. **A check that backgrounds work must
capture its output and print it when the `wait` refuses.** Not fixed here: it is
fourteen phase programs and their keys, and it deserves a pass of its own.

**The stall itself has a favourite scenario, which is worth knowing before
blaming a phase.** `zpty.py`'s `sel_arrows` is the newest of the five — added with
the `keymodel=startsel` repair — and it is the longest and the only one that
presses a modified key. r41's stall was on it. Two units failing out of 46 under
64-way load, both passing alone in less than half the time they took to fail, is
the load and not the tree; the check is to re-run the unit by itself
(`sh tools/verifypass.sh --one zero <N> <scratch>`, after `rm -rf` of that unit's
directory and result, which it will not overwrite).

**The Ex-command sweep dispatches all 600 command names, each from its own
scratch directory.** `:mkvimrc`, `:mkexrc`, `:mksession`, `:mkview` and
`:wviminfo` write into the cwd; run from the repository root they get committed
by accident, and with the files already present two of the commands return 1
instead of 0, so a comparison against a reference recorded the same way agrees
for the wrong reason. It also records what each command left behind.

Two things it had to be taught: `:suspend` and `:stop` signal the **process
group** and stop the harness's own shell (exit 148 is 128 + SIGTSTP), so each
run gets a session of its own; and quitting with `:qall!` rather than `:q!` is
what makes the window-opening commands (`:new`, `:split`, `:tabnew`, `:vsplit`,
the `:sb*` family) deterministic. Commands that hand over the terminal —
`:shell`, `:suspend`, `:stop`, `:terminal`, `:gui`, `:gvim` — are recorded as
skipped.

**This is the sweep that catches things.** The one segfault that reached a build
here — a version string overflowing a 20-byte buffer, so `:intro` crashed — was
invisible to all 67 behaviour cases and to every pty scenario. The boring
mechanical dispatch over every entry point found it.

**No harness passes `-u NONE`; they isolate through the environment.** Every
run gets an empty `$HOME`, `$VIM`, `$VIMRUNTIME` and `$XDG_CONFIG_HOME`, and no
`$VIMINIT` or `$EXINIT`, so `slim-vim` finds no `~/.vimrc`, system vimrc or
runtime defaults — and `whim-vim`, which has had no `-u` since its Phase 18,
needs no option to be told. Measured against the slim baselines with a real
`~/.vimrc` on the machine: nothing moved. Commands go in as `+{command}` rather
than `-c` for the same reason — `whim-vim` has no `-c` — and fill the same list.

**Check what a test did, not what it returned.** Silent Ex mode exits 0 on
almost anything.

## Verification tiers

Pick the cheapest that applies:

| the change is | the check is |
| --- | --- |
| pure formatting | the binary is **byte-identical** (`cmp`) |
| token-preserving | the **token stream** is identical |
| anything else | the full harness against the recorded baselines |

**Tier 1 works, and needs three things arranged.** No `__LINE__` anywhere — the
four `assert()` calls upstream compiles are gone, and `<assert.h>` with them,
`static_assert` being a C23 keyword. No `-g`. And `SOURCE_DATE_EPOCH`, because
`version.c`'s `__DATE__`/`__TIME__` otherwise differ between any two builds;
gcc honours it for both macros, so a verification build pins the timestamp while
an ordinary build still records the real one. Compile both sides **from the same
file name** or `__FILE__` differs. Proven: 50 blank lines inserted anywhere
produce a byte-identical binary.

**Tier 2 means tokens, and needs a tokeniser.** `gcc -E -P` preserves horizontal
whitespace, so `(int);` and `(int) ;` differ textually and not in tokens.
Collapsing whitespace is not enough either. A token-neutral change can still be
wrong — check the *warnings* too.

Three checks that pass while doing nothing:

- **`objcopy -O binary --only-section=X f /dev/stdout` writes nothing and exits
  0.** Comparing two such streams reports every pair of binaries identical.
  Write to real files.
- **A "clean rebuild is byte-identical" check passes if the rebuild never
  happened.** Check the elapsed time, or that the artifact was removed.
- **A script that printed a success message has not necessarily written
  anything.** Re-read the file, or grep for the new text.

And one thing no tier can see: **blank lines, indentation and paragraphing.** A
pass that touches those needs a count of them as its own check.

**When tier 1 is out of reach there is more than one thing to do about it, and zero's
last twenty phases used nine.** Each is stronger than *the harness agreed*, and which
one applies is decided by what the change can and cannot move:

| the change | what it cannot move | the evidence |
| --- | --- | --- |
| renames, expansions, deleted attributes (23, 24, 26's six) | a single instruction | **`cmp` of the binary** — tier 1, and it subsumes every case at once |
| code motion inside one function's reach (25, 26's clock) | what the editor draws | **a byte-identical recording**, with a control that moves it |
| a self-declaration replacing a header's (26, 32) | the header, which is still above it | **`static_assert` and deliberately wrong declarations**, compiled against the thing about to leave |
| moving 1,568 lines past the rest (27) | the *lines* | **a multiset equality on the source**: no input line missing, only the 32 written added |
| respelling a call the corpus never reaches (30, 32) | how often the thing is *reached* | **an instrumented pair**: the same `write(2, …)` at every site on both sides, with a control that marks a different count |
| new code with new arithmetic (28, 31) | the size of what it emits | **an accounting**: `.text` +42 bytes, function by function, or ±1 ms over 20,000,000 random pairs |
| a rewrite whose failures are memory bugs, not differences (34) | a leak, a double free, an overread | **a unit harness under AddressSanitizer**, both versions extracted from their own sources at run time into one driver, with a named finding per control |
| a change entirely below the boundary (41) | one line of the core | **`cmp` of `make editor.c`** — tier 1 on the part of the file the project is *for*, and it subsumes every case at once for it |
| a representation the corpus cannot see at all (44, 45) | the tree's *shape*, only its answers | **controls that must move and controls that must not**, each of the latter with the reason it cannot be seen, run under a second instrument the recording does not use |

**The last row is the one a recording provably cannot reach**, and phase 34 is where that
was measured rather than assumed: copying the *new* length instead of the old is a
heap-buffer-overflow **read** whose bytes land exactly where the `musl_memset` that
follows overwrites them, so every one of the 106 records agrees and the program is
wrong. Six of seven controls move under the sanitizer, each with its own finding; the
seventh — dropping a null guard — moves **nothing**, is reported rather than hidden, and
the guard is kept for what `ZERO-PLAN.md` §4c asks of the core, that its meaning be on
the page and not in what a libc happens to tolerate.

The third and the fourth are the ones worth remembering. **Cross-checking against a
header that is about to leave** is a check with an expiry date, and the phase that can
write it is the phase before the one that makes it impossible — which is the whole
reason zero 26 and 27 are two phases rather than one. **A multiset equality on the
source** is tier 1 one level up: when every address must move, the thing that must not
change is the text, and *the output is the input's lines rearranged, plus exactly these
thirty-two* is a claim a phase that altered a character on the way could not make.

**And the last row is the one the memline arc is about, where a control that moves
nothing is the finding.** Phase 44 had to choose `DB_LINE_MAX` and the corpus cannot see
the value at all — 32, 64, 128 and even 1 record all 118 cases byte for byte — so *the
recording agrees* would have been **vacuous**, and the parameter was chosen by what the
corpus **reaches** instead: 64, because 255, the value that exactly fills the page and
wastes nothing, reaches no pointer-block split and would have blinded the instrument on
the very phase that rewrites the tree. Phase 45's `fanout` control is the same shape
carried to its conclusion: setting `PB_COUNT_MAX = 511` moves **0 of 118 records** and
takes three tree markers from 1 to 0, so **narrowing `PTR_EN` would take the root split
out of the corpus without moving one record** — which is why the file now carries a
`static_assert` that refuses to compile instead of a paragraph asking a reader to
remember.

## The shape of slim-vim.c

### One translation unit, one namespace

`slim-vim.c` is what were 67 `.c` files, 30 `.h` and 66 `proto/*.pro`, in the order
the preprocessor used to paste them: sources alphabetically with `main.c` last,
and **`main()` is literally the last thing in the file**, its closing brace the
final line.

**272 comment lines survive, and 245 of them are banners** introducing the
former files:

```c
// ==================== ops.c ====================
// ---------------- begin structs.h ----------------
// ---------------- end structs.h ----------------
```

Searching for `==== ops.c ====` or `begin structs.h` finds that code, and names
the upstream file whose comments and history explain it. The banners once kept
`git log --follow` reaching a former file's history through the merge; that
history is not in this repository, so they are navigation now — which is reason
enough to keep them in a file this size.

The other 27 lines are seven notes, at the seven places where the code alone
would mislead: the file header, the constants hoisted out of struct bodies, the
three macros the headers read before they are included, `format_arg` on `_()`,
the character arrays that replaced stringification, the two command lists that
designated initialisers keep aligned, and the three `pum_set_*` functions that
were written out because C cannot paste tokens. Each says why the thing is
shaped as it is, which nothing in the C can.

**File-local names are global now.** Two former files cannot both have a static
of the same name. The compiler catches most collisions but **not two tentative
definitions** (`static int x;` with no initialiser) — C merges those silently —
and it cannot see macro collisions at all. Four names had to be renamed at the
merge; `cmdline_match_array`, `cmdline_match_arraysize`, `string_sort_compare`
and `TERMCODE_GAP` carry prefixes for that reason, as does the regexp opcode
`RE_WHITE`, which collided with the colour enum's `WHITE`.

**A build is all or nothing.** Touching anything recompiles the editor.
`regexp_bt.c` and `regexp_nfa.c` were `#include`d by `regexp.c` rather than
compiled separately, and are inlined here like any other file.

### There is no preprocessor left

Every directive in `slim-vim.c` is one of **41 `#include`s of a system header**, and
they are the first thing in the file. No `#define`, no `#undef`, no `#if`,
`#ifdef`, `#ifndef`, `#elif`, `#else`, `#endif`, `#pragma` or `#line`.
Preprocessing this file does nothing but paste in libc.

**`whim-vim.c` has 18 of them and `zero-vim.c` has 11**, and zero's are the
only ones any pipeline has ever *removed*: zero phase 16 took six that nothing named and
phase 21 took `<stdio.h>` with the seven symbols it freed.
`ZERO-GOAL.md`'s charter is the rule — no phase adds a directive, and a phase may
remove one — and the count is checked rather than believed, both by that phase's edit
and by a loop in its check that drops each survivor in turn and requires the compile
to fail.

**And zero's eleven are not at the top of the file any more.** See below.

That the includes can come first is only possible because nothing in `slim-vim.c` is
read by a header. The five feature-test macros (`_XOPEN_SOURCE`, `_BSD_SOURCE`,
`_SVID_SOURCE`, `_DEFAULT_SOURCE`, `_REENTRANT`) were the only candidates, and
deleting them left the preprocessed output byte-identical — musl declares
everything unconditionally. **If you ever build this against another libc, that
is the first thing to put back, above the first `#include`.** `_XOPEN_SOURCE
700` was upstream's, for `strptime()` and `mkdtemp()`; the other three were for
nanosecond timestamps in `struct stat`.

The 3,433 `#define`s became:

| | how many |
| --- | --- |
| deleted, nothing mentioned them | 912 |
| enumerators (`enum { … }`, `enum : long { … }`) | 1,443 |
| expanded at the use site | 1,041 macros |
| `static inline` function | 2 (`_`, `NGETTEXT`) |
| character arrays | 3 (the version strings) |
| written out (token pasting) | 3 (`pum_set_border`/`shadow`/`margin`) |
| an array with designated initialisers | 1 (the 600-command table) |

**`enum : long` is C23**, which gcc 15 compiles by default; it is what lets
`P_COLON = 0x80000000L` keep its width. A `static const int` will not do for
most of these — it cannot appear in a case label, an array size, an enumerator
initialiser or a static initialiser, and these do.

### The core and the host are one file with a line in it

This is `zero-vim.c` and not `slim-vim.c`, and it is the thing the whole zero pipeline
was for. From zero phase 27 the eleven `#include`s are **not** the first thing in the
file: they sit at **line 76,689**, and **the first `#include` is the boundary between
the editor core and its host**. Nothing else marks it — no comment, no banner, no name,
because `zero-vim.c` carries no comments at all.

```sh
make editor.c        # 76,687 lines, cut at the first #include of 78,666
```

That rule is `awk '/^ *# *include / { exit } { a[NR] = $0; if (NF) last = NR }'` and then
print up to `last` — one clause for the cut and no judgement, plus a trailing-blank-line
drop so the file ends on its last line. **Quote it entire or not at all.** The naive
prefix `/^ *# *include / { exit } { print }` gives **one more line** on the same text, so
a program that takes the naive form while its comment says it takes `zero.mk`'s reports a
figure that differs by one from its neighbour's **on the same file**, and a reader
comparing two consecutive phase commits sees an off-by-one that is in neither phase.
Zero phases 38 and 39 did exactly that, and were repaired; the defect that propagated was
the **comment**, which claimed to be the rule beside an `awk` that was not.

What it writes is a **complete translation unit** with three properties the ordinary build
cannot see:

- **0 lines beginning with `#`.** Above the boundary there is no preprocessor syntax at
  all: the core is plain C. `[[fallthrough]]` (zero phase 24) is C23 *statement* syntax
  and not a directive, which is why the swap was allowed. The guard is `^ *#` and not
  `#`, because **`#` is an ordinary character in 63 places** in the cut —
  `enum { CPO_HASH = '#' };`, `if (ptr[0] == '#')`, the two latin1 case tables, an
  `E1281` message — and a guard that refuses any `#` refuses every valid cut for ever.
- **0 errors under `-fsyntax-only`.**
- **A warning set that IS the interface.** **Eighteen** names, every one
  `used but never defined`: `vim_snprintf`, `host_exit`, `host_message`, `host_time`
  since zero phase 32, `host_alloc`, `host_free` and `host_write` since 35, `host_raise`
  since 36, and the
  ten
  `musl_*`. The check computes the same eighteen a second way — the names defined below
  the cut and mentioned above it — and requires the two to match. **A phase states that
  set as a rule and never as a table of constants**: phase 28 renamed one of the names,
  32 added one, 35 added three and 36 added one, and every check that compares the
  input's cut with its
  own at
  run time survived all four, while the two that wrote thirteen names out are why
  `apart 27 32`, `apart 28 32`, `apart 27 35` and `apart 28 35` exist. **An interface
  that grows is the point and not a regression**: an implicit libc dependency hidden in a
  bare declaration becoming an explicit named call is what the line is for, and phase
  35's three are `malloc`, `free` and `write`.
- **And the warning set is not enough on its own**, which phase 36 is where this tree
  found out. gcc says `'X' used but never defined` for a `static` function and **says
  nothing whatever about an ordinary one**, so a bare `extern` declaration of a libc
  function is invisible to that check — which is exactly how `getpid` and `kill` sat
  above the boundary for nine phases without the interface set noticing. The check
  compiles the cut to an **object** and takes `nm -u` of it: 18 names, every one of them
  defined below the boundary in the same file, computed from the text and not listed
  anywhere — with the identical computation on phase 36's input finding two that are
  not, which is what keeps the emptiness from being two numbers agreeing.

Three mistakes are **silent in an ordinary build and caught by nothing else**: a
`#define` above the cut (1 directive where 0 are allowed), an `#include` back at line 1
(the cut is 0 lines, which is what the line floor catches), and one core function
quietly moved below the boundary, which changes the eighteen by exactly its name.

**Only the core → host direction ever needs a declaration.** Everything above the cut is
visible below it, in one translation unit, so the host calls `vim_main`, `deathtrap`
and `musl_memcpy` for free and the core pays for **one block of seventeen prototypes**,
the ten `musl_*` and
`host_exit`/`host_message`/`host_alloc`/`host_free`/`host_write`/`host_time`/`host_raise`
— eighteen
names with
`vim_snprintf`, whose
own prototype sits where the formatter used to be defined. That
asymmetry is why the design is one file and not two; `.claude/briefs/zero-split.md`
surveyed the two-file alternative, measured it at 130 implementation keys to teach the
tools, and it was abandoned.

**Three things the core no longer takes from a header**, each a phase: `NULL` and
`size_t` are `nullptr` and `typedef typeof(sizeof(0)) usize;` (23); `time_t`,
`sig_atomic_t`, `struct timeval`, `MIN`, `MAX` and `offsetof` are the
core's own, with nine plain libc prototypes (26); and twelve constants — the eight
`*_MAX`/`*_MIN`, `SIZE_MAX`, `PATH_MAX`, `EXIT_FAILURE`, `SIGHUP`, `SIGTERM` — are
enumerators, eight derived from the type system and four asserted (27). **An enumerator
and not a `static const int`, because `PATH_MAX` is an array bound.**

**`uintptr_t` is a fourth and the direction is the other way**, which is worth stating
because `pipes/zero26-check.sh` still names it and the file does not. Phase 26 did not
give the core a `uintptr_t` of its own: it **took the type away**, rewriting the one cast
that used it — `(unsigned long long)(uintptr_t)p`, in `musl_fmtptr` — as `(usize)`, the
name phase 23 had already made the core's, and then asserting the type is **0** in the
core along with `time_t`, `sig_atomic_t`, `size_t`, `MIN`, `MAX` and `offsetof`. Measured
on the committed file: `uintptr_t` appears **0** times in `zero-vim.c`, core and host
alike, and 0 in `whim-vim.c` too. Where it survives is inside a `_Generic((usize)0,
uintptr_t: 1, default: 0)` in phase 26's own check — a cross-check against `<stdint.h>`,
which was still above the core when that phase ran and could not be written after phase
27, and not a core spelling at all.

**Those nine prototypes are none now**, and each phase that shortened them had a
different argument. Phase 28 deleted the tagless clock struct outright, `musl_now_ms`
returning a scalar where `musl_gettimeofday` took two out-parameters. Phase 31 vendored
`abs` and `labs`, which the core **called** and which gcc never emitted a call for — the
first application of *the core may not depend on latent compiler behaviour*. And phase
32 took `time`, replacing what that prototype really pinned with a `static_assert` that
pins what it was believed to: `long time(long *tp);` above `<time.h>` checked
`long == time_t` and **never** `time_T == long`, measured by changing `time_T` to `int`
with the prototype left alone and getting a **silent** compile, so the core now carries
`static_assert(_Generic((time_T)0, time_t: 1, default: 0), "time_T is time_t");` below
the includes instead. **Phase 34 took `realloc` and phase 35 took `malloc`, `free` and
`write`**, and the two are different acts: 35 moved three calls to the other side of the
line, while 34 could not, because **`realloc` is the one libc function that cannot be
vendored or wrapped from the core's side at all** — to move the old contents it needs to
know how many bytes the old block held, and `void *realloc(void *p, usize n)` does not
carry that number; musl reads it back out of the chunk header below the pointer, which is
a fact about musl's heap and not about C. So there is no `musl_realloc` to write, and the
route is each call site supplying the length it already knows: `ga_grow_inner()`'s
`ga_itemsize * ga_maxlen`, computed one line later to zero the tail and hoisted above the
allocation, and `get_keystroke()`'s `buflen` before the `+= 100` immediately above the
call. **Phase 36 emptied the block**, and the two names it held went by different routes:
`kill` **moved**, `vim_handle_signal()`'s `kill(getpid(), got_signal)` becoming
`host_raise(got_signal)` — which takes **no pid**, because a core that can no longer ask
for its own process id must not be handed one, the same rule as `host_write` dropping fd 1
and `musl_read_input` dropping fd 0 — while the deferral itself stays in the core, so the
editor still decides *when* a deferred deadly signal acts and only the raising crosses the
line; and `getpid` was **avoidable**, `mch_get_pid()`'s one caller writing a `b0_pid` that
has been read by nothing since `whim-vim.c`. So the sentence this arc was building to is
now written down, and it is *the core names no libc function at all* — which is a claim
about the whole cut and not about a paragraph, and is checked as one.

**Below the boundary a constant's own name is the macro**, so `static_assert(INT_MAX ==
INT_MAX)` is a tautology about `<limits.h>` and says nothing about the core. Each assert
restates the **deriving expression** — `static_assert((int)(~0u >> 1) == INT_MAX,
"INT_MAX");` — emitted from the same table as the enumerator's own initialiser so it is
not typed twice. Measured: the wrong derivation in both places fails, and the same wrong
enumerator with the naive assert **builds in silence**.

**The core uses no floating point at all, and that is an invariant rather than a count.**
It is met **by construction** and by no phase: the configuration is `tiny`, which has no
`+float`, and whim removed the eval layer that `float_T` belonged to. Measured on the cut
`make editor.c` writes, and on the whole of `zero-vim.c`: **0** occurrences of `float` and
**0** of `double` outside two string literals (`p_ambw_values`' `"double"` and the
`'ambiwidth'` report that echoes it); no floating-point literal and no `%f`, `%e` or `%g`
conversion — the one `%e` a regex finds is inside the `t_CXM` capability string
`\033[?1006;1000%?%p1%{1}%=%th%el%;`, where it is terminfo's *else*; **no libgcc
soft-float helper in `nm -u`**, which is the check a `double` reaching a `long double`
path would trip; and, in `gcc -O0 -c`'s 162,278 lines of disassembly, **0 x87 and 0 SSE
floating-point instructions**. The only `xmm` registers named at all are a `pxor`, four
`movaps` and a `movq` zeroing a 72-byte stack local in `pagescroll()`, and eight `movaps`
in `vim_snprintf()`'s varargs register-save area, which the System V ABI emits behind
`test %al,%al` and which no call in this program ever reaches with `al` non-zero.
**`slim-vim.c` does not share this**: it has `<float.h>`, `typedef double float_T`, a
`score_t` and a `va_arg(*ap, double)`. It is whim's removal of the eval layer that makes
the statement true, and it is worth stating here because a transpiler and a host both
care — `ZERO-PLAN.md` §4d is where the porter's side of it is written.

**The order of phases 26 and 27 was forced by the preprocessor**, and it is worth
knowing before anything here is rearranged. `enum : int { INT_MAX = … };` placed *after*
`<limits.h>` is `enum : int { 0x7fffffff = … };`, a syntax error — so the constants can
only be written once the includes have moved. And every cross-check of a core-owned
spelling against the header it replaces can only be written *while the header is still
above it*. Hence 26 then 27, and nothing else.

### Nothing is global but main()

`main()` is the only symbol with external linkage. `nm` on a build made without
`-s` is the check — the shipped binary is stripped and `nm` says "no symbols" —
and the only other globals are the C runtime's. Everything else is `static`:
3,578 file-scope lines begin with the keyword, and 1,951 of those are prototypes
— what the dead-code sweep and Phase 10 left of the former `proto/*.pro` block
near the top of the file.

**A *function* definition following a `static` declaration inherits internal
linkage**, which is why three thousand definitions say nothing about it.
**Objects do not inherit**: a file-scope object with no storage class has
external linkage whatever a prior declaration said, and gcc rejects the pair.

**The keyword is checked, and the zero pipeline is where that started to matter.**
`tools/phasecheck.sh` requires `nm` on the object to print exactly `main`, and zero
phases 14 and 15 are the first change in any of the three pipelines to *add* hundreds
of file-scope definitions rather than remove them — twenty-eight libc functions
brought into `zero-vim.c` as `static`, with `musl_abs` and `musl_labs` joining them at
phase 31. One missing keyword there would be the first
break of this invariant, and that check is what says there is none.

The forward declarations are what keep definition order inside `slim-vim.c` from
mattering, and **the redundant ones are gone**: Phase 10 moved the command table
below the handlers it names and then dropped 640 of them, handing `static` to
each definition whose declaration went, and Phase 11 then gave the keyword to the
other 1,441 that had been inheriting it. Every
definition now states its own linkage, so no declaration is load-bearing for
anything but order, and one can be removed without anyone having to think about
linkage at all.

### Braces are mandatory and nothing spans a line break

Every body of an `if`, `else`, `for`, `while` and `do` is a brace block,
including the 13,770 that were a single statement. The shape of every control
statement is the same, which is the point: a reader never has to decide how far
a body extends, and neither does a tool. **`-Wmisleading-indentation` reports
nothing and cannot.**

**A later phase undoes this, every time.** Bracing is Phase 7 and macro
expansion is Phase 9, and expansion pastes in `for` headers of its own: the
`FOR_ALL_*` loop macros become `for (...) for (...) if (...) { }` on one line.
This pass found **1,542 bodies not on a line of their own and 1,564 not
braced** after Phase 9, and an earlier one shipped them, because nothing
re-checked the invariant after the phase that broke it. **The canonicalizers
are cheap and idempotent — re-run them all to a fixpoint at the end**:
`splitheads.py`, `brace.py`, `joinparens.py`, `onestmt.py`, `onedecl.py`,
`untab.py` and `undowhile.py` are each a no-op on this file now, and that is a
check worth keeping, not just a fact. **That list is not `canon.sh`'s**, and
the difference is where the run of two blank lines below went unnoticed:
`canon.sh` runs seven passes in a fixed order — `blankruns`, `joinparens`,
`splitheads`, `brace`, `onestmt`, `onedecl`, `forcomma` — while `untab.py` is
nobody's and `undowhile.py` is `pipes/slim9.sh`'s directly. Since the Go
cutover those seven are `tools/go/internal/canon/` and **not** the `.py` files
of the same names, which are still here and still run standalone; the list
above is of the Python tools, and that is the point of the sentence rather
than an oversight. `forcomma` is a no-op here too — it finds three `for` init
clauses with a top-level comma and declines all three — and `blankruns` is the
one that is **not**.

**No parenthesised group spans a line break.** Every condition is on one line,
and so is every argument list — of a call, a declaration or a definition. A
body's extent is brace matching and a condition's extent is one line, so a
line-oriented tool never has to parse C. The trade is width: 2,468 lines are
over 120 columns and 461 over 200, the longest 1,084. Nothing here wraps to a
terminal.

**One statement per line and one declarator per declaration**, so an
unused-variable sweep deletes a line instead of rewriting one. `for` init
clauses have their comma operators hoisted out, except the one that declares —
hoisting *that* would widen the variables' scope. Increment clauses are left
alone; they run on `continue` too.

### No comments, no tabs

Beyond the banners and the seven notes above there are none: 39,648 comments
went, taking 51,452 lines with them — a fifth of the tree. That was a deliberate trade and some of what went was
load-bearing knowledge the code does not state — why `CMD_SIZE` must come last,
what the `\%f)` regexp atom means. **It is not in this repository's history**,
so read it in upstream, which a pass clones fresh and the banners name, rather
than expecting `git blame` to have it. There are
295 further occurrences of `/*` and `//`, on 16 lines, and every one is inside a
string literal: `'comments'` defaults, `pack/*/start/*` globs, a `://` scheme
test.

Not one tab either; 261,321 were expanded at the 8-column stops they were
written for, so the file renders identically at any `'tabstop'`. **Two** were
data rather than layout and are spelled `\t`: one in the `b:undo_ftplugin`
command string in `trigger_undo_ftplugin()`, and one inside the default
`'spellcapcheck'` pattern, where it sits in a regexp character class.

Upstream is `noet`, so anything imported from there needs expanding first.

**The paragraphing was never lost.** 17,194 blank lines, 9.5% of the file and
**5.31 per function** — the density of a build that kept its comments. Every
function is separated from the next, every declaration block from its body, and
none follows an opening brace. **There is one run of two blank lines**, at line
41,086, between `static struct cmdname cmdnames[];` and the `end ex_cmds.h`
banner. Phase 10 deleted the declaration that stood between them and `canon.sh`
runs in phases 7 and 9 only, so nothing re-canonicalises after it — which is
the lesson above arriving one phase later than it is told. Whim's first stage
takes it: `blankruns` collapses the run, and every whim and zero boundary
from q12 on has none.

That is a consequence of how the comments were removed, and it is the one thing
here much cheaper to get right than to fix afterwards. Each comment became **one
space plus the newlines it spanned**, so line *i* of the output is line *i* of
the input and the question "was this line blank before?" never arises.
Collapsing a multi-line comment onto one line — what the standard says — forces
that question, and answering it by resyncing two texts gets it wrong at scale,
invisibly, because neither verification tier can see a blank line.

The line-preserving rule is equivalent to the standard's exactly when **no
multi-line comment has code on both sides of it**. `tools/decomment.py` checks
and refuses otherwise; in this tree the count is zero.

**No `do { ... } while (0)` remains.** All 1,757 that macro expansion left
behind are unwrapped. It needs **brace matching, not a regex**: 18 lines carry
two wrappers, one nested inside the other, and the spelling varies between
`while (0);` and `while (0) ;`. Check first that no body holds a `break` or
`continue`, which would bind to a different loop once the wrapper is gone.

Unlike bracing, this **does** change code generation: at `-O0` the never-taken
`while (0)` test is a real branch, and the code before a pointer's target
shrinks. What must not change is **data**, and the check for that is the
*strings*, not the section. This pass measured `.rodata` byte-identical, its
strings identical, and `.data` differing only in **876 pointers, every one
moved by exactly −12 bytes** — the section sizes and addresses did not move at
all, the shrinkage being absorbed by alignment padding. An earlier pass
measured a 64-byte `.text` shrink and 337 four-byte words moving in `.rodata`,
because a switch jump table's entries are relative offsets into `.text`; expect
the shape of the answer, not the numbers.

## Deliberate divergences from upstream

### The configuration is frozen

Features `tiny`, no GUI, no terminal library, plus `+extra_search`.

**`+extra_search` has no configure flag.** `--enable-search-extra` does not
exist and autoconf ignores an unknown `--enable-*` silently, so it *looks* like
it worked; `CFLAGS=-DFEAT_SEARCH_EXTRA` gets two files in and then fails on the
eval layer. It takes four source edits and no fewer, each marked in place:
`feature.h` ungates it, `drawline.c` adds it to the `LINE_ATTR` guard (because
`'hlsearch'` uses `did_line_attr`), `match.c` wraps the two `pos_list` branches
in `FEAT_EVAL`, and `cmdexpand.c` guards a call into `syntax.c`.

**Upstream never builds this combination**, so expect the same if another
`FEAT_NORMAL` feature is enabled — and fix it rather than reverting.

### There is no terminal library

`HAVE_TGETENT` is undefined and nothing links `libncursesw` or `libtinfo`. The
`tinfo/ncurses/termlib/termcap/curses` search existed only to satisfy
`tgetent()`, which this build never calls. `TERMINFO`, `HAVE_OSPEED`,
`HAVE_UP_BC_PC`, `HAVE_DEL_CURTERM` and `TGETENT_ZERO_ERR` fall out undefined
on their own. `term_set_winsize()` is defined unguarded — `os_unix.c` calls it
unguarded, and it is the one hard blocker to building without a terminal
library.

Terminal capabilities come from the built-in tables alone, and there are ten:

    ansi   vt100   xterm   xterm-256color
    screen   screen-256color   tmux   tmux-256color   dumb   debug

`screen`, `tmux`, the `-256color` names and `vt100` are additions; terminfo used
to supply them. `screen` and `tmux` drive the xterm table. `builtin_ansi` and
`builtin_xterm` were given the 8-colour capabilities they never had upstream,
for the same reason.

**That is `slim-vim.c` and `whim-vim.c`; `zero-vim.c` has two**, `xterm-256color` and
`debug`, since zero phase 38 — an embeddable core has no business carrying ten terminal
descriptions, the host decides what it is attached to, and the one it keeps is already
the compiled default. The eight names that went resolve to `E522` now, and with them
went three capability tables and `find_builtin_term()`'s xterm-family clause, which was
the whole `xterm` *family* — `xterm nxterm kterm mlterm rxvt screen.xterm` all resolved
through that one row, and none of them is among the nineteen the harness asks about.

**Six of upstream's entries were dropped**: `vt320`, `vt52`, `iris-ansi`,
`pcansi`, `win32` and `amiga`, with their tables — 340 lines — and the
`vim_is_iris()` special case in `find_builtin_term()` that the sweep then
reported as dead. This build is Unix-only and none of them describes a terminal
anything reaches it through. `vt100` had been an alias for the vt320 table;
that table is now `builtin_vt100` and `vt100` is the only name on it, which
loses nothing — upstream's own comment says it covers VT1x0 through VT3x0.

All six now resolve to the `xterm` fallback below, and `tools/termcheck.py`
records a row for each saying so, which is what would catch one creeping back
in.

**An unknown or unset `$TERM` falls back to `xterm`, not `ansi`.** `builtin_ansi`
has *no key definitions* — `:set t_ku?` under it is `E846: Key code not set`, as
it is under `dumb` — and this file used to say that the arrow keys, Home, End,
Delete and the function keys therefore arrive as a literal Escape plus characters
and quietly corrupt the buffer. **Measured, in a pty, that is wrong for the keys
it names first, and the reason is worth knowing.** `handle_csi_function_key()`
decodes `CSI A/B/C/D` as the arrows, `CSI F`/`CSI H` as End/Home and `CSI P/Q/R/S`
as F1–F4 **generically, whatever the terminal table says** — so with the three
lines `aaa`, `bbb`, `ccc` in the buffer, `gg`, Down, `x` leaves `bb` under the
default terminal,
under `-T xterm`, under `-T ansi` and under `-T dumb` alike, on `slim-vim` and on
`zero-vim`, and Home behaves the same way. **That measurement cannot be repeated on
`zero-vim` as it now stands**, and the reason is two phases rather than a doubt: since
zero phase 38 there is no `ansi` and no `dumb` table to name, and since 39 there is no
`-T` to name one with — `+set term=` is the only way in there, and `xterm-256color` and
`debug` are the only two names it accepts.

**What is real is narrower, and it is the other spelling of the same key.** The
xterm table sets `t_ks`, which puts the terminal into application-cursor-key mode,
so its own `t_ku` is `\033OA` — SS3, not CSI — and *that* has no generic decoder:
under `-T ansi` a typed `\033OB` is Escape, `O` (open a line above) and `B`, which
is the corruption the old sentence described, measured as `['BX','aaa','bbb','ccc']`
where every other terminal gives `['aaa','bbbX','ccc']`. **A table with no key
definitions also never asks for that mode**, having no `t_ks`, so a terminal in its
normal state sends CSI and nothing is lost. The remaining casualty is the
`~`-terminated family: `\033[3~` (Delete) deletes a character under `xterm` and is
**swallowed** under `ansi` — a silent no-op in normal mode and nothing inserted in
insert mode — which is a key that stops working rather than a buffer that is
damaged. `\033[15~` (F5) is the same under every table.

Two details that go with it:

- **The 256-colour add-on is chosen by the name the user set, not the
  fallback.** The unknown-terminal path reassigns `term`, so testing *that* for
  `256color` gives `alacritty-256color` eight colours. `set_termname()` keeps
  the original in `requested` for this one test. **`zero-vim.c` no longer has
  `requested`**: phase 39 removed the path that reassigned `term`, leaving only the
  `term += 8` that strips a `builtin_` prefix, and a needle beginning with `2` cannot
  match inside that prefix — which the phase checked rather than asserted. The **test**
  is still there and was measured rather than folded: forced TRUE it moves 1 of the 19
  terminal rows and forced FALSE 18, so the two surviving names really do disagree on it.
- **The diagnostic is one line.** It used to print the name, then every built-in
  terminal, then the fallback, then pause two seconds.

`term_strings_not_set()` is no longer guarded by
`HAVE_TGETENT || FEAT_TERMGUICOLORS`; the 256-colour add-on needs it always.

### Defaults are compiled in, not read from a vimrc

Eighteen option defaults are changed in what was `optiondefs.h`, one built-in
terminal capability is dropped, and four mappings are installed. Together they
are exactly a vimrc, and the binary needs none:

    nocompatible  autoindent  expandtab  history=9999  hlsearch
    keymodel=startsel  lazyredraw  nojoinspaces  regexpengine=1  ruler
    smartindent  scrolloff=1  shiftround  smarttab  softtabstop=4
    shiftwidth=4  tabstop=4  undolevels=9999  t_BE=

    map <Tab> %      map! <char-0xa7> <C-_>      nmap é u      nmap á <C-R>

**Which half of the default pair to edit is decided by `P_VI_DEF`.** A row's
default is `{vi, vim}`, and `P_VI_DEF` means the vim half is unused — one edit
covers both. `'history'`, `'ruler'` and `'compatible'` do *not* carry it, so
both halves are set, and the result cannot depend on `'compatible'`.
`'compatible'` also has an initialiser of its own, `p_cp = FALSE`, because vim
only clears it when it finds a vimrc and there is none.

`t_BE` is not an option default but a terminal capability: `optiondefs` already
defaults it to `""`, and `builtin_xterm[]` was what set it. Its `KS_CBE` row is
gone, so bracketed paste is never enabled.

The mappings go through `init_mappings()`, upstream's own hook — the `struct
initmap` it used to read sat inside a `MSWIN || MACOS_X` guard that went with
the platform. `map` is four modes including **select**; leaving `MODE_SELECT`
out shows up as `nox` where `:map` should print a blank mode column. The three
non-ASCII left-hand sides are written as universal character names (`\u00a7`),
so the file stays pure ASCII as it is everywhere else.

**`'lazyredraw'` is why this needed a fix first.** See *Gotchas*: `redrawing()`
peeking at input under `-e -s` makes a headless run silently do nothing, and it
only bites a build where the option is on by default.

**This is permanent, and the behaviour harness now encodes it.** Four of the 67
cases changed and each traces to one option: `ins_bs` and both undo cases to
`nocompatible` — Vi's `u` is a toggle, vim's is multi-level — and `ins_tab_et`
to `softtabstop=4`. The Ex sweep over all 600 commands and the terminal table
did not move at all.

The proof that the compiled defaults *are* the vimrc, rather than something
close to it: run the previous binary with `-u <the vimrc>` and this one with
`-u NONE` and compare. All 67 behaviour cases and all six pty scenarios are
identical, and `:set all` differs only in `'loadplugins'`, which `-u NONE` sets
and no default controls.

**That proof was blind on one of the eighteen, and `keymodel=startsel` had never worked
in any build of this editor.** `set_options_default()` installs an option's default
**value** and runs no callback, and `km_startsel`/`km_stopsel` are computed in exactly
one place, `did_set_keymodel()` — so `:set km?` printed `keymodel=startsel` while
`km_startsel` stayed `FALSE`, and a shifted arrow did a word motion instead of starting
Select mode. **It is the only one of the eighteen with that shape**: the only `P_STRING`
among them, and the only one whose entire effect is a flag a callback derives.
`'shiftwidth'`, `'tabstop'`, `'undolevels'` and `'hlsearch'` have callbacks too and their
readers use `p_sw`, `p_ts`, `p_ul` and `p_hls` directly, all four measured working under
a clean `$HOME`. **Upstream has the same gap and cannot see it**:
`didset_string_options()` recomputes fifteen string options' derived flags at startup and
`keymodel` is not one of them, which costs upstream nothing because its default is the
empty string and `km_startsel = FALSE` is then right by accident. Only a build that
compiles in a non-empty default reaches it, and this is the only such build. The repair
is the one `'compatible'` already uses, in the same hunk and the same idiom —
`km_startsel = TRUE; km_stopsel = FALSE;` by hand in `set_init_1()`, because this build
ships no vimrc and the defaults **are** the vimrc — and it cost all three products three
lines and no binary a byte of size.

**The general lesson is the one to keep: a proof by agreement is only as strong as the
harness's vocabulary.** The two binaries *did* agree — `:set all` prints the value either
way, and **no harness in any of the three pipelines had ever pressed a modified key**.
`ptycheck.py`'s `arrows`, `zcases.py`'s `ins_arrows` and `nav_arrows` and `zpty.py`'s
`nav_arrows` press the plain arrows, and every other `\x1b` in `behaviour.py`,
`exsweep.py`, `zcases.py`, `zexcmds.py`, `zargv.py`, `termcheck.py` and `clicheck.py` is a
bare Escape — while `ins_start_select()` and the `NV_SS`/`NV_SSS` arms of `normal_cmd()`
are all three gated on `km_startsel` and need `MOD_MASK_SHIFT` to be reached at all. The
instrument was added **first** and proven to record the defect before anything was fixed:
`ptycheck.py` gains a sixth scenario, `shift_arrows`, and a `--- mode ---` row per
scenario read from the accumulated stream rather than the final screen, because the keys
that quit wipe the message line; `zpty.py` gains the same scenario as `sel_arrows`, and
**in `zpty.py` and not `zcases.py` deliberately**, a 103rd screen case being a new record
that eight zero phase checks' arithmetic would have to move. Measured on the committed
binaries before any repair: `shift_arrows` left `eta two` and `--- mode --- none`, and
after it `beta two` and `--- mode --- VISUAL`. **The whole difference in the re-recorded
baselines is fifteen lines of `ref-pty.txt`** — six mode rows and the nine-line
`shift_arrows` block — with `behaviour/`, `ref-exsweep.txt`, `ref-term.txt` and
`enumerators.txt` byte-identical, which is the condition a re-record has to meet to not
be self-fulfilling. No declared delta moved in either downstream pipeline: whim and zero
inherit the working flag from the same source line, whim's cumulative delta is still
exactly 489 commands and 11 cases, and `pipes/whim.delta` and `pipes/zero.delta` are
untouched.

## Gotchas

- **`'lazyredraw'` must not peek at input when there is no screen.** It is on
  by default here, and off in upstream's `-u NONE`, which is why this only
  bites this tree. `redrawing()` and `messaging()` called `char_avail()`
  whenever `p_lz` was set, and under `-e -s` that reads ahead on stdin, where
  end of input means "quit": a single `-c` that reported a change was enough to
  exit and abandon every `-c` after it — silently, with status 0. Both now go
  through `typed_ahead()`, which is `char_avail()` except in silent mode.

  It reproduces only with enough lines to make the substitution *report*, and
  piping an empty line instead of `/dev/null` hides it:

  ```sh
  vim -u NONE -i NONE -e -s -c 'set lz' -c '%s/aaa/BBB/' -c 'wq' f.txt </dev/null
  ```

  Upstream has the same hole. The lesson generalises: **`char_avail()` is not a
  free look at a keyboard.**

- **A headless `-e -s` run can silently do nothing, and exits 0 either way.**
  The same command that edits a file on its own has left it untouched when
  stdout was a pipe inside a shell loop. Check what a run *did* — the file's
  contents — never the exit status.

- **A script that printed a success message has not necessarily written
  anything.** An edit run once reported rewriting a section and raised before
  its `write()`, and the claim reached a commit message unverified. Re-read the
  file, or grep for the new text.

## How to do things

### Audit for dead code

One command, and everything is in one file with internal linkage, so a function
or object the compiler cannot see used is not used:

```sh
gcc -c -O0 -Wall -Wextra -Wno-unused-parameter -o /dev/null slim-vim.c
```

**It reports nothing at all**, and that is the point: the sweep is a boolean,
not a number to compare against a remembered baseline. A new warning cannot hide
behind "the usual two". The 37 deliberate fall-throughs say so with
`__attribute__((fallthrough))`, a hint that changes no code.

Substituting `-fsyntax-only` is faster but does **not** report
`-Wunused-function`, which is the one you want after a removal. Delete what it
names and run it again — deleting a function orphans its callees, and reaching
silence took eight rounds.

**`-flto -fno-fat-lto-objects` is the fast form that does report it**: gcc
builds the call graph, warns, and writes GIMPLE instead of generating code. The
warnings are byte-identical, in 2.4 s instead of 6.0 on a 129,000-line file, and
that is what `tools/deadsweep.py` compiles with. It leaves no object `nm` can
read, so `tools/phasecheck.sh` takes the plain `-O0` object `sweep.sh` builds in
the background for the phase's link, `.cache/compile/build.o`, when both its sha
and the warnings' sha are the source's — and compiles for itself otherwise.

**`-Wunused-but-set-variable` does not reach an address-taken or file-scope object,
and it is a pattern rather than an incident — nine objects in four zero phases so
far.** The warning fires on an ordinary local that is written and never read, and
`tools/deadsweep.py` does not act on it at all — so what it *does* report has to be
removed by hand, and what it does *not* report is invisible twice over. Zero phase 9 met
it as `msg_scrolled_ign`, a file-scope int whose four writers all went with
`filemess()` and `readfile()`, leaving it constant with one reader — which gcc has no
warning for in either direction; zero phase 20 met it twice in
one edit — `did_read_something`, left set and never read once `fill_input_buf`'s
`close(0); dup(2)` arm went, and `*interrupted`, which is **write-only through three
functions** (`RealWaitForChar` writes it, `WaitForChar` passes it on, `inchar_loop`
declares it and passes `&interrupted` and never reads it) and draws nothing because
taking a variable's address counts as a use. It is `deadfields.py`'s shape in a local:
no warning covers it, so it takes reading.

**And the memline arc met it four more times, as a *cascade* rather than as a find**,
which is the form to expect from here on. Removing a struct member that nothing reads
leaves the locals that computed its value written and never read, and gcc reports those —
so they are the **edit's** and not the sweep's, because `deadsweep.py` does not act on
the warning. Zero phase 42 took `pe_old_lnum` and with it `lnum_left`, `lnum_right` and
`ml_find_line()`'s `dirty`; phase 43 took `pe_page_count`, whose one read in the whole
file was an argument `mf_get()` stopped taking, and with it `page_count_left` and
`page_count_right`. **The measurement is that the cascade was measured and not
predicted**: the phase removed the field, compiled, and read the two new warnings off
gcc. Phase 42 also met the same blindness one level up — **four groups of swap-file
bookkeeping that `tools/deadfields.py` reports as 0 fields, because every one of them is
*written***: eight `struct block0` fields with 12 writes and 0 reads, a `mf_dirty` whose
two reads are each the condition of an `if` whose only statement writes it again, a
`BH_DIRTY` set three times and tested nowhere, and `mf_dont_release`, a
`static int … = FALSE;` read twice and **assigned nowhere in the file**. gcc has no
warning for any of those in either direction, so an edit must name them and no tool will
help — and the phase found a **fifth** the survey had missed, `ML_LOCKED_DIRTY`, set 8
times and tested nowhere once `mf_put()` lost its state arguments, which is the same
invisible write-only state the phase exists to remove.

**The distinction that goes with it: unreachable *evidence* is not unreachable code.**
Phase 42 surveyed `BH_LOCKED`, which looks exactly like `BH_DIRTY`'s twin, and left it —
its one reader is `mf_put()`'s `e_block_was_not_locked` internal-error test, so a binary
whose `mf_put()` **sets** the bit instead of clearing it draws all 102 screen cases
identically. The recording says nothing because the reader is a test that then never
fires, and that is not a licence to delete it.

**Key on the warning option, never the sentence.** `'X' defined but not used` is
emitted for both functions and variables, and only `[-Wunused-function]` versus
`[-Wunused-variable]` distinguishes them. Treating every hit as a function
computes an extent from an unused error string to the closing brace of the next
function below — 500 lines — and the symptom is an unrelated symbol going
undeclared. `-Wunused-const-variable=` carries a trailing `=`.

Warnings that need dataflow only appear with optimisation; adding `-O2` to the
sweep is worth doing before a release.

### Types and enumerators, which no warning covers

For types there is no flag. Count identifiers and compute **reachability, not
reference counts** — a mention inside another type definition is not a use, and
two types naming each other keep each other alive for ever. Roots are the
mentions outside *every* type definition: a prototype, a variable, a cast, a
`sizeof`. That is what finds a tangled dead island.

**An enum's constants are referenced without its tag**, so they decide whether
the definition is dead. Leave them out of the count and you delete an enum half
the file uses by name.

**And an enum need not have a tag at all.** The option-index lists are written
`enum` on one line and `{` on the next, with no name, and the definition finder
`typereach.py` and `deadenums.py` share did not recognise that head — so neither
tool ever looked inside them, and an enumerator nothing named survived every
sweep. It recognises the bare `enum` head now.

Run both sweeps alternately to a joint fixpoint: removing a function orphans
types, and removing a type orphans functions.

**Deleting an enumerator renumbers the ones after it**, and several enums are
the index of a parallel table — `hl_flags[HLF_COUNT]`,
`first_autopat[NUM_EVENTS]`. Where a deletion would move a survivor, give it its
original value explicitly, then check with DWARF, which records every enumerator
and its value:

```sh
tools/enumvals.sh slim-vim.c before.txt      # dump, make the change, dump again
```

Dump before and after; every name present in both must have the same value.
There are 2,858. That is a stronger check than the build, which is perfectly
happy to renumber a table index.

**Every sweep does this now, in both pipelines.** `tools/deadenums.py` runs in
slim's Phase 8 loop and in every whim phase's `sweep.sh`: it dumps the values on
first need, pins the first survivor after each deleted run, keeps a run whose
next survivor DWARF has no value for — gcc does not emit every enum, and an
unpinned survivor would renumber invisibly — and dumps again with `--verify`
once the loop is done. `tools/deadfields.py` sits beside it for struct fields,
which no warning covers either, and **refuses while `ml_recover()` exists**:
removing a field moves the ones after it, and while the editor can read a swap
file, block zero and the memfile's pages are a disk format. So `slim-vim.c`
keeps every field, and `whim-vim.c` loses its dead ones from the phase that
removes recovery on.

**`deadfields.py` removes the member and leaves the initialisers, so a field whose
only reader a phase deletes must go in the EDIT and not the sweep.** Zero phase 20
deletes `catch_signals()`, which was the only reader of `struct signalinfo`'s `deadly`;
the sweep duly took the member and left `{SIGHUP, "HUP", TRUE}` with three values for
two fields, which is `warning: excess elements in struct initializer` three times and
`tools/phasecheck.sh` failing on a correct phase. A field the edit knows is dead is the
edit's to take, **with its data** — and the tool cannot do it, because an initialiser
list is not what it parses. **Zero phases 42 and 43 are the same rule with the tool
reporting zero**: `deadfields.py` matches "named nowhere outside a type definition", and
every field those two phases remove is **written** — `struct block0`'s eight with 12
writes and 0 reads, `pe_old_lnum` with 7 and 0, `mf_used_last`, `bh_page_count`,
`pe_page_count` and `pe_bnum` — so run against either input it reports **0 fields** and
the edit must name all of them itself.

**And it matches a field by NAME, so a name two structs share is invisible to it for
ever.** Zero phase 39 removes `mparm_T.term`, whose only writer was the `-T` argument
block, and `zero-vim.c` holds **32** mentions of another struct's `.term` — `attr_entry`'s
`ae_u.term` — so the tool can never report this one dead however long it runs. The edit
takes the member, and the way it earns the right to is by **computing the partition**,
requiring every `.term` left in the file to belong to `ae_u`, rather than asserting it.
The same rule covers a table indexed by an enumerator: `deadenums.py` would take
`ME_ARG_MISSING` and leave the `main_errors[]` row it indexes, so phase 39 takes **both**
and renumbers what follows, which is this paragraph's lesson one table up.

### Add a constant

Prefer an enumerator. **But an enumerator is an `int`, so `sizeof` on it is 4**
— the one conversion that changes meaning while keeping the token stream
identical, and it once broke every `:w`: `#define PATHSEP ((char_u)'/')` became
an enum and eight `sizeof(PATHSEP)` sites silently became 4. Before converting
anything, grep for `sizeof(NAME)` and for a cast wrapping the *whole* body — a
cast inside the expression is harmless, one around it is the macro telling you
its type is not `int`. Use `static const char_u` for those.

### Rename a name across the whole file

**A whole-file substitution must be literal-aware and single-pass**, and zero phase 23
measured both halves — the first as a control it kept, the second as a defect it caught
before the phase ran.

**Literal-aware**, because a name in a string is data and data is the one thing a
mechanical edit must not change. Zero phase 23 turned `NULL` into `nullptr`, and three
string literals in that file contain the word — an `E1507` internal-error message,
`"[NULL]"` and `msg_puts("NULL")`. A plain `sed -E 's/\bNULL\b/nullptr/g'` rewrites all
three and the binary moves **1,598 bytes, 1,354 of them in `.rodata`**, with `[nullptr]`
visible in `strings`. **Neither verification tier above can see this**: the build is
clean and the token stream is right. The check is the *strings*, and the way to make the
`cmp` mean something is to build the literal-unaware form as a control and require it to
differ. `zero-vim.c` and `whim-vim.c` have no preprocessor and no comments, so scanning
for string and character literals is exact and cheap; do that first and rewrite only
outside them.

**Single-pass**, because literal spans are **offsets**, and every offset after the first
replacement is wrong. Rewriting two names in two passes indexes the second pass's spans
against the *first pass's output*: zero phase 23 measured it, and the two-pass form left
**five of 437 `size_t` behind** — in a file that still compiled and whose binary was
still byte-identical, because the header that declares the name was still above it.
Every check the phase had passed on that file except the count. It would have surfaced
three phases later as unexplained errors in a move that had nothing to do with it, with
nothing pointing back. Rewrite every name in one pass over the original text, or
recompute the spans between passes — and **assert a partition, not a count**: classify
every occurrence into the classes the rule serves and refuse on a leftover, which stays
true of a file the edit has never seen.

**The partition rule has a second measurement, and it is the one that shows what a count
costs.** Zero phase 35 rewrites `malloc`, `free` and `write` at their core call sites,
and was written against a boundary where they had 2, 3 and 2 mentions. Phase 34 then
landed in front of it, rewrote `realloc` as a malloc-copy-free at two more sites, and
took two of those counts to 4 and 5 — and the anchors **refused**, which is what a
counted anchor is for and better than the alternative. Both programs now classify every
mention above the boundary as the name's own declarator or a call of it, delete the
declaration, rewrite every call, and **read the number off the text**; a mention that is
neither — an address taken, a variable of the same name — refuses rather than surviving
into a file whose declaration is gone. A count is a fact about a tree that *was*
measured; a partition is a fact about the tree that arrives.

### Change the Ex command table

The commands live in **two** lists the compiler keeps aligned: `enum CMD_index`
names and numbers them, and `cmdnames[]` describes them, one designated row per
command:

```c
    [CMD_append] = {(char_u *)"append", STRLEN_LITERAL("append"), ex_append, …},
```

Editing means editing both, and **the designator is what makes that safe**: a
row lands at its own enumerator whatever order the rows are written in, so the
two cannot drift. That is stronger than the X-macro this replaced, which only
guaranteed the two expansions had the same *order*. A `static_assert` on the row
count catches a dropped last entry; a dropped middle row leaves a zeroed hole,
which the 600-command sweep catches.

A third table is *derived*: what was `ex_cmdidxs.h` maps first and second letter
to a position in `cmdnames[]`, so removing an entry shifts every later index. It
lives between marker comments in `slim-vim.c`:

```sh
python3 tools/create_cmdidxs.py slim-vim.c --check   # or --update to rewrite it
```

**The normal-mode table has the same shape and no designators.** `nv_cmds[]`
lists the keys and `nv_cmd_idx[]` is a sorted index into it, computed once and
written into the C. Delete a row and the index still compiles, still has its old
length, and every key found past the hole resolves to another key's row — the
whim pipeline's mouse phase did that, and the arrow keys stopped working in
normal mode for twelve phases, because every harness that pressed an arrow did
it in insert mode. A row is pointed at `nv_error`, never deleted, and
`tools/nvidxcheck.py`, run by every whim phase's `phasecheck.sh`, requires the
index to be a permutation of the rows.

Two traps if you ever remove a command:

- **A removed name is inherited by the next command sharing its prefix.**
  Deleting only `CMD_help` makes `:help` silently run `:helpclose`. Check what a
  removed name now resolves to before assuming it errors. `whim-vim.c` does not
  have this trap: from its Phase 80 each row carries its shortest abbreviation,
  the lookup is a scan with no index, and a deleted row's words resolve to
  nothing. That is an argument, and zero phase 6 turned it into a measurement:
  having removed `:write :wq :xit :exit :update :saveas`, it types `:w :x :wq :up
  :sav a :w! :w >>f :w !cat` and requires every one to answer E492 — and requires
  none of them to have answered E492 before. **The rule has a second half, and
  zero phase 8 measured that too**: a word SHORTER than a row's own shortest
  abbreviation matched nothing before the row went either, so `:en` was E492 on
  both binaries while the other ten spellings of `:edit`/`:enew`/`:ex`/`:view`/
  `:visual` all moved. A spelling that was already E492 proves nothing about the
  phase, so it belongs in the must-*not*-differ half, with the reason.
- **Related commands do not sort together.** `:lhelpgrep` survives a sweep of
  everything starting with `help`, because it sorts under `l`. Grep for the
  *handler* name (`ex_helpgrep`), not the command name.

### Regenerate slim-vim.c from upstream

`slim-vim.c` is not maintained by editing it into a new shape; it is **produced**,
and `SLIM-GOAL.md` is the process that produces it. **The makefile runs the pass**,
so there is nothing to type but `make`:

```sh
make                 # ls-remote, compare against upstream.sha, and if they
                     # differ: clone upstream/, rm -rf upstream/.git, run one
                     # claude -p over SLIM-GOAL.md, rm -rf upstream/, record the sha
```

**The pass is `slim.mk`, and it is twelve make targets, not one agent.** A phase's
prerequisite is the previous phase's boundary, so `make` sequences them — and a
phase is run by a **program** if `pipes/<pipeline><N>.sh` exists — or, for a split
phase, its `-edit.sh` and `-check.sh`, which `tools/phaserun.sh` runs with the sweep
between them — and by an **agent** if it does not. Converting a phase is therefore adding a file; nothing else
changes, and the pass runs end to end at every point in between.

Each phase is a pure function of its input: the recipe restores the previous
boundary into `upstream/` before running, so a phase cannot inherit anything
from a run that went wrong. A **boundary** is a tar (the restore point:
everything) beside a **content digest** (the meaning: a sha256 over every
source file's own sha256, with `objects/`, the built binary and `config.log`
excluded — that last one carries a timestamp, and a boundary containing it
would never equal itself twice).

**The built binary is excluded for exactly that reason too**, and the exclusion
has to name it in both pipelines: `/vim$` matches `./vim` and does *not* match
`./whim-vim`, so every whim boundary counted its own binary — and `version.c`
embeds `__DATE__` and `__TIME__`, so no whim boundary was ever equal to itself
twice. **Nothing caught it for eleven phases**, and the reason is worth keeping:
a phase replayed from the tier 3 cache copies the recorded digest rather than
recomputing it, so a cached pass agrees with the oracle whatever the oracle
says. **Only a run that recomputes a digest can falsify a boundary.** `make
whim-verify` is the fast one and `make whim-repass` after `make clean-cache` the
sequential one, and one of them is the check to make before trusting a recording
— every whim stage boundary reproduces under both, each stage a program.

`src/xxd/xxd`, upstream's other built binary, is excluded for a reason of the same
kind: its debug info records the directory it was built in, so slim's first two
boundaries depended on *where* the phase ran. A pass that always runs in
`upstream/` could never show that. `make slim-verify`, which runs each phase in a
scratch root of its own, showed it on its first run — and stripped of that path
the two binaries were identical.

```sh
make slim-repass          # force a pass on a tree whose sha already matches
make slim-phase-4         # re-run one phase from the previous boundary
make slim-replay-3        # put upstream/ back to what phase 4 receives
make slim-times           # where this pass's seconds went
make slim-promote-4       # make an advisory boundary a hard check
```

That is what makes the deterministic rewrite affordable: **converting a phase
costs seconds, not an hour** — restore the previous boundary, run the program,
compare the next digest. No agent, no full pass.

A recorded boundary is one of two things, and the difference is deliberate. An
**advisory** one came from an agent, which is not required to be
byte-reproducible mid-pass, and a mismatch is a report. A **check** was
promoted after a deterministic run passed end to end, and a mismatch is a
failure. Promoting a boundary from the run it is meant to check would make it
agree with itself, which is the `.reference/` mistake in a smaller shape.

**A pass cost 67 minutes when one agent did all of it, under two of them
machine time**, and `SLIM-GOAL.md`'s *Where the hour goes* has the per-phase
breakdown, including the finding that splitting it into one agent per phase
made it *slower* — 89 minutes — because each agent re-orients from scratch.

**Seven phases are programs, and they run in 2 m 46 s against the 52 m 33 s the
same seven cost as agents**: Phase 0 (32 s), 1 (18 s), 2 (4 s), 3 (1 s), 4
(63 s), 5 (8 s) and 7 (40 s). Each reproduces the boundary the agent it
replaced recorded — byte for byte, except Phase 2, which installs its own
makefile instead of performing surgery on upstream's and so differs in exactly
that file and `config.mk`, both of which Phase 3 discards. Measured: p3 comes
out identical either way.

**The whole pass by one agent is kept, and is not a fallback but a pair.**
`make slim-refpass` runs it into a work directory of its own and `make slim-compare` puts
its `slim-vim.c` beside this one's. The programs are fast and brittle — each written
against one upstream — and the agent is slow and can think. When upstream moves
under a patch, the reference path is what still produces an answer, and the
difference between the two is the specification for repairing the fast path.

The document update is conditional. A pass that reproduced the previous `slim-vim.c`
byte for byte made no sentence here wrong, so `docs-if-changed` asks `git` —
`slim-vim.c` is tracked — and only calls an agent when there is a real difference to
describe.

`upstream/` is a **staging directory, not a checkout of anything**. It is
gitignored, so its 8,581 files cannot reach a commit, and it does not exist
between passes. `tools/` and `pipes/` are what the pass is run with; `.reference/baselines/`,
once a pass has made it, is what the next one is checked against. Nothing in
`upstream/` survives.

**`upstream/.git` goes before anything else is touched, and that remote is
never written to.** `github.com/arbace/vim` is read-only input; `--depth 1`
means there is no history worth keeping, and deleting the metadata first makes
pushing, fetching or re-pointing it impossible for the rest of the pass.
Deleting it at the end instead would leave a window in which it could be used
by mistake.

**The end check is a whole-process diff, and it runs automatically:**

```sh
tools/refcheck.sh          # the last act of producing slim-vim.c
```

`.reference/slim-vim.c` *is* the previous pass's output, so a new one should
differ only by what upstream changed — usually nothing. The tool reports the
source, the binary (tier 1) and whether baselines are present, and exits
non-zero on a source or binary difference.

**A missing `.reference/` is the normal starting state, not a failure.** It is
gitignored and produced, so a fresh checkout has none; `refcheck.sh` says
"nothing compared" and exits 0, and the pass is checked by `verify.sh` against
the baselines Phase 1 records. It never replaces `verify.sh` either — one
compares against the last pass, the other against recorded behaviour, and a pass
that reproduced last time's mistake exactly would satisfy the first.

**Everything this tree has is in the phases.** The terminal-table reduction,
the compiled-in vimrc, the `'lazyredraw'` fix and the `keymodel=startsel`
initialiser are Phase 1, because Phase 1
is where behaviour changes and where the baselines are recorded; `-static -s`
is Phase 3, on the scaffolding makefile that lives inside `upstream/` and dies
with it — the root `Makefile` is the seed and no phase writes it. There is no
list of extras to re-apply afterwards — a bare run of Phases 0-11 reproduces
this tree, not a plainer one, and that is what makes the comparison worth
running. It has been run: the pass of 2026-09-10 reproduced `slim-vim.c` **byte for
byte** against the previous one, and the binary with it,
2,208,088 bytes. The `keymodel` repair then moved it by exactly the three lines it adds
to `set_init_1()`, 180,844 → 180,847, with the binary the **same size and not the same
bytes** — two stores at `-O0` are real instructions and alignment padding absorbs them —
and all three products re-passed from it, `whim-vim.c` to 86,617 lines and `zero-vim.c`
to 79,592 at r39. **That is the one place in this tree where `.reference/baselines/` is
allowed to move**, and the whole difference was checked line by line before it was
accepted: fifteen lines of `ref-pty.txt` and nothing else.

### Import one thing from upstream by hand

Upstream is `ts=8 sw=4 noet` and full of conditionals. Anything brought across
needs its tabs expanded at 8-column stops, its comments removed, its bodies
braced and its parenthesised groups joined before it will match this file. The
passes for each are in `tools/` and are idempotent, so running them on the
whole file afterwards is the cheapest way to be sure.

**"Unused here" used to mean "not dead"** — a function flagged by `-Wall` might
have callers behind a `#ifdef` this configuration did not compile. That warning
is spent *here*: there are no conditionals, every caller is visible, and unused
means unused. It still applies to anything imported, where the `#ifdef`s are
real.

If you ever have to resolve conditionals again, `SLIM-GOAL.md` Phase 5 has the
method, and it is not the obvious one.

## Keeping this file current

**Update it whenever the tree stops matching it — no need to be asked.** It has
been wrong three times: once when an edit script reported a section rewritten
and raised before its `write()`; once when it described `src/` and `build/`
directories that no longer existed; and once when it accumulated per-phase
sections that contradicted each other, so that its first description of the tree
said 165 files and `proto/` while its later one said one translation unit. Each
time the cost was a reader trusting it.

**A pass does not start this file from scratch.** It carries forward, and every
phase edits the sentences its work made wrong — which is `SLIM-GOAL.md` rule 5, and
the reason the rule exists is the third failure above: a file written by
appending one section per phase ends up describing several trees at once. The
reasoning that does not belong here belongs in the commit messages, one per
phase.

Guard against that last one: **this file describes one state, the current one.**
When something changes, edit the sentence that is now wrong rather than
appending a new section that disagrees with it.

The numbers here are measurements, not estimates. Re-measure rather than
adjusting them by reasoning, and say what you measured.

## Commit style

A `type: summary` subject, then prose explaining *why* the change was made, what
was measured, and how it was verified. State deliberate omissions explicitly.
