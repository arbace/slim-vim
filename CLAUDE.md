# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repository.

**This file describes the tree as it now is.** If the two disagree, this file is
wrong — fix it. `GOAL.md` is a different document: the process that produced this
tree from a pristine vim, written to be handed to an agent that has no tree yet.
Nothing here is a record of how the work went; that log was folded into `GOAL.md`
and deleted.

## What this is

Vim 9.2 (upstream patch level 1037) as **one translation unit**. That number
moves: the input is cloned fresh, upstream keeps patching, and **Phase 1 is
where this line gets updated** — from `version.c`, not from memory. `vim.c` is
181,845 lines and is the whole editor; one `gcc` invocation builds it in about
8 seconds, into a standalone static binary.

**`vim.c` is produced, not edited into shape.** `GOAL.md` is the process that
turns a pristine vim tree into it, and the input is cloned fresh each time from
`github.com/arbace/vim`, branch `regexp-delimiter-atoms`. See *Regenerate
vim.c from upstream*. Editing `vim.c` directly is fine — but a change worth
keeping belongs in `GOAL.md` too, in the phase that owns it, or the next pass
silently drops it.

**Nothing is rebranded.** The program is vim, the binary is `vim`, and `$VIM`,
`$VIMRUNTIME`, `~/.vimrc` and every string are upstream's. Whatever the
checkout directory happens to be called is not a name this repository uses
anywhere.

**No feature was removed to get here**, which is the whole difference between
this tree and a stripped-down fork: `:help`, `:hardcopy`, the non-UTF-8
encodings, locale and iconv are all still present. Two things were removed
*afterwards*, deliberately and separately — six built-in terminal entries, and
bracketed paste — and both are described below.

The configuration is `tiny`, no GUI, no terminal library, **plus
`+extra_search`** — which upstream has no configure flag for.

**This repository holds the process, not the product.** Between passes it is
four things — `.gitignore`, this file, `GOAL.md` and `tools/` — and `vim.c`, the
`Makefile` and `LICENSE` appear when a pass produces them. A checkout that has
never run one has no editor in it, and everything below describes what a pass
makes rather than what is necessarily on disk right now.

It was started from a finished tree without the history that produced it, so
`git log` reaches back only as far as this repository's first commit. Everything
that history used to be consulted for is written down instead: `GOAL.md` is the
process, this file is what the result is and why. From here on every commit
message states the reasoning and how it was verified — that is the record, and
it is the only one.

## Layout

Forty tracked files once a pass has run: six at the root, and 34 in `tools/` —
33 passes and harnesses plus a `README.md`. Three of the six (`vim.c`,
`Makefile`, `LICENSE`) are products; the other three and `tools/` are the seed.

```
vim.c        the editor, headers and forward declarations included
Makefile     24 lines, two targets
tools/       the harnesses, and the passes that produced vim.c
CLAUDE.md  GOAL.md  LICENSE  .gitignore
```

`tools/` is the only tracked subdirectory and has a `README.md` of its own.
Nothing in it is part of the build; the build reads `vim.c` and nothing else.

Four things appear untracked, and `.gitignore` names all four and nothing
else: `vim`, which the build adds and `clean` removes; `.reference/`, a frozen
copy of this tree with the recorded baselines beside it (see below);
`TRANSCRIPT.md`, which `/export` writes whenever this file is updated; and
`upstream/`, the pristine vim tree a pass clones in, works on and deletes —
8,581 files that must never reach a commit, and which do not exist between
passes. The `.gitignore` upstream shipped named 91 paths, of which two still
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

Two targets, `vim` and `clean`. Everything else — `all`, `install`, `test`,
`proto`, `tags`, `depend`, `lint`, `shadow`, `distclean` — is gone, along with
the second makefile that recursed into `src/`. `all` went with them: it is a
convention for builds with more than one product, and this one has `vim`.

**There is no configure and nothing is generated.** `configure`, `configure.ac`,
`config.h.in`, `config.mk.in`, `osdef.sh`, `pathdef.sh`, `link.sh` and
`toolcheck` are gone. What they used to emit is ordinary text inside `vim.c`,
under its `config.h`, `osdef.h` and `pathdef.c` banners. To change the build,
edit those.

The build runs no shell script, writes no source, and has no object phase: one
`gcc` invocation turns `vim.c` straight into `vim`, which is the whole of
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

A copy of `vim.c`, the binary built from it, the two documents, `Makefile`,
`LICENSE`, `.gitignore` and `baselines/`. **It is not tracked and it is not a
precondition**: a pass produces it, so a checkout that has never run one has no
`.reference/` at all and everything here describes what exists afterwards.

**`baselines/` is the only part that matters, and the only part no commit can
reconstruct.** It is *data* — what the harnesses recorded from the Phase 1
binary, the last build that changes behaviour on purpose — and every phase since
has been required to match it. Everything else in `.reference/` is
`git archive HEAD` and an 8-second build.

**Never regenerate it from the current binary**, which would make the comparison
self-fulfilling. A pass records it in Phase 1 either way, but the recording only
proves something when there is an older one to compare it against first: the
first pass in a fresh checkout is self-certifying on behaviour, and every pass
after it is not. That is the whole reason to keep this directory across passes,
and the reason it is the one thing worth copying if this tree is ever moved.

`vim` there is built with `SOURCE_DATE_EPOCH=0`, so it is reproducible byte for
byte and usable as the left-hand side of a tier 1 check:

```sh
SOURCE_DATE_EPOCH=0 gcc -O0 -static -s -o /tmp/t/vim vim.c
cmp /tmp/t/vim .reference/vim
```

**The copies go stale the moment the tree moves and nothing warns you.** They
are a snapshot of a commit, not a mirror; `git diff` against that commit is the
honest comparison. Refresh them, or delete them and keep only `baselines/`,
rather than trusting a copy whose age you cannot see.

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

A case that writes no file records `<NO FILE WRITTEN>`, so a crash cannot pass
as a match, and every artifact is deleted before the run — **a harness that
diffs an output file it did not first delete keeps passing on the previous
run's file.**

**The harness was proven able to fail before it was trusted.** Making
`do_addsub()` return FAIL — CTRL-A a no-op — makes exactly the CTRL-A cases
differ and nothing else. A test suite that cannot fail is not evidence.

**`tools/create_cmdidxs.py`** regenerates what upstream generates with
`create_cmdidxs.vim`, which needs a vim with `+eval` and this build has none.
`python3 tools/create_cmdidxs.py vim.c --check` verifies the table in place, between
the `begin`/`end ex_cmdidxs.h` banners; `--update` rewrites it. It refuses to
generate anything from a parse that finds fewer than 100 command names, because
a regex that stops matching otherwise yields a plausible-looking all-zero index.
Treat it as a canary: a pass that reshapes the command table, or merely
re-indents a line of it, shows up here rather than as a wrong answer later.

### Four things a harness here has to get right

**A binary's own name changes what it does.** `parse_command_name()` reads
`argv[0]`: a basename starting with `r` turns on **restricted mode** and every
shell-out fails, `e` selects evim, `g` the GUI, and `view`/`ex` prefixes change
the mode again. A reference binary saved as `ref` made `:%!sort` and
`:r !echo` fail against a binary that was byte-identical to one called `vim`.
Every harness stages the binary under test into a temp directory as `vim`.
**Never name a vim binary anything else.**

**Anything about terminals, mappings, screen drawing or `:set` reporting needs a
real pty** — `-e -s` never initialises the terminal and reports empty values.
The pty driver uses `pty.fork()`, writes keystrokes with delays, strips ANSI
escapes, and puts a hard timeout on the read loop: an error at startup leaves
vim on a `Press ENTER` prompt and the loop would otherwise hang for ever. Before
concluding a pty harness is broken, check that what it reports is not simply
true — one scenario that looked wrong was `0Dworld`, which never enters insert
mode.

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

## The shape of vim.c

### One translation unit, one namespace

`vim.c` is what were 67 `.c` files, 30 `.h` and 66 `proto/*.pro`, in the order
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
the character arrays that replaced stringification, `typed_ahead()` on why
`'lazyredraw'` must not peek at input, and the compiled-in mappings on why
their left-hand sides are universal character names. Each says why the thing is
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

Every directive in `vim.c` is one of **41 `#include`s of a system header**, and
they are the first thing in the file. No `#define`, no `#undef`, no `#if`,
`#ifdef`, `#ifndef`, `#elif`, `#else`, `#endif`, `#pragma` or `#line`.
Preprocessing this file does nothing but paste in libc.

That the includes can come first is only possible because nothing in `vim.c` is
read by a header. The five feature-test macros (`_XOPEN_SOURCE`, `_BSD_SOURCE`,
`_SVID_SOURCE`, `_DEFAULT_SOURCE`, `_REENTRANT`) were the only candidates, and
deleting them left the preprocessed output byte-identical — musl declares
everything unconditionally. **If you ever build this against another libc, that
is the first thing to put back, above the first `#include`.** `_XOPEN_SOURCE
700` was upstream's, for `strptime()` and `mkdtemp()`; the other three were for
nanosecond timestamps in `struct stat`.

The 3,432 `#define`s became:

| | how many |
| --- | --- |
| deleted, nothing mentioned them | 911 |
| enumerators (`enum { … }`, `enum : long { … }`) | 1,444 |
| expanded at the use site | 1,027 macros |
| `static inline` function | 2 (`_`, `NGETTEXT`) |
| character arrays | 3 (the version strings) |
| written out (token pasting) | 3 (`pum_set_border`/`shadow`/`margin`) |
| an array with designated initialisers | 1 (the 600-command table) |

**`enum : long` is C23**, which gcc 15 compiles by default; it is what lets
`P_COLON = 0x80000000L` keep its width. A `static const int` will not do for
most of these — it cannot appear in a case label, an array size, an enumerator
initialiser or a static initialiser, and these do.

### Nothing is global but main()

`main()` is the only symbol with external linkage. `nm` on a build made without
`-s` is the check — the shipped binary is stripped and `nm` says "no symbols" —
and the only other globals are the C runtime's. Everything else is `static` — 4,199
declarations, of which 2,869 are the former `proto/*.pro` block near the top of
the file.

**A *function* definition following a `static` declaration inherits internal
linkage**, which is why three thousand definitions say nothing about it.
**Objects do not inherit**: a file-scope object with no storage class has
external linkage whatever a prior declaration said, and gcc rejects the pair.

The forward declarations are what keep definition order inside `vim.c` from
mattering. About half are redundant — the definition already precedes every use
— and could go; the rest are load-bearing.

### Braces are mandatory and nothing spans a line break

Every body of an `if`, `else`, `for`, `while` and `do` is a brace block,
including the 13,770 that were a single statement. The shape of every control
statement is the same, which is the point: a reader never has to decide how far
a body extends, and neither does a tool. **`-Wmisleading-indentation` reports
nothing and cannot.**

**A later phase undoes this, every time.** Bracing is Phase 7 and macro
expansion is Phase 9, and expansion pastes in `for` headers of its own: the
`FOR_ALL_*` loop macros become `for (...) for (...) if (...) { }` on one line.
This pass found **1,557 bodies not on a line of their own and 1,564 not
braced** after Phase 9, and an earlier one shipped them, because nothing
re-checked the invariant after the phase that broke it. **The canonicalizers
are cheap and idempotent — re-run them all to a fixpoint at the end**:
`splitheads.py`, `brace.py`, `joinparens.py`, `onestmt.py`, `onedecl.py`,
`untab.py` and `undowhile.py` are each a no-op on this file now, and that is a
check worth keeping, not just a fact.

**No parenthesised group spans a line break.** Every condition is on one line,
and so is every argument list — of a call, a declaration or a definition. A
body's extent is brace matching and a condition's extent is one line, so a
line-oriented tool never has to parse C. The trade is width: 2,479 lines are
over 120 columns and 461 over 200, the longest 1,084. Nothing here wraps to a
terminal.

**One statement per line and one declarator per declaration**, so an
unused-variable sweep deletes a line instead of rewriting one. `for` init
clauses have their comma operators hoisted out, except the one that declares —
hoisting *that* would widen the variables' scope. Increment clauses are left
alone; they run on `continue` too.

### No comments, no tabs

Beyond the banners and the five notes above there are none: 39,906 comments
went, a fifth of the tree. That was a deliberate trade and some of what went was
load-bearing knowledge the code does not state — why `CMD_SIZE` must come last,
what the `\%f)` regexp atom means. **It is not in this repository's history**,
so read it in upstream, which a pass clones fresh and the banners name, rather
than expecting `git blame` to have it. There are
22 further `/*` and `//` in the file and every one is inside a string literal:
`'comments'` defaults, `pack/*/start/*` globs, a `://` scheme test.

Not one tab either; 261,991 were expanded at the 8-column stops they were
written for, so the file renders identically at any `'tabstop'`. **Two** were
data rather than layout and are spelled `\t`: one in the `b:undo_ftplugin`
command string in `trigger_undo_ftplugin()`, and one inside the default
`'spellcapcheck'` pattern, where it sits in a regexp character class.

Upstream is `noet`, so anything imported from there needs expanding first.

**The paragraphing was never lost.** 17,265 blank lines, 9.5% of the file and
**5.18 per function** — the density of a build that kept its comments. Every
function is separated from the next, every declaration block from its body, no
run of two blank lines anywhere and none after an opening brace.

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

**No `do { ... } while (0)` remains.** All 1,764 that macro expansion left
behind are unwrapped. It needs **brace matching, not a regex**: 18 lines carry
two wrappers, one nested inside the other, and the spelling varies between
`while (0);` and `while (0) ;`. Check first that no body holds a `break` or
`continue`, which would bind to a different loop once the wrapper is gone.

Unlike bracing, this **does** change code generation: at `-O0` the never-taken
`while (0)` test is a real branch and `.text` shrinks — by 64 bytes here. What
must not change is **data**, and the check for that is the *strings*, not the
section: every string in `.rodata` is identical, while 337 four-byte words in
it move, because a switch jump table's entries are relative offsets into the
`.text` that shrank. `.data` differs only in pointers, each moved by one of two
amounts matching the code removed before it.

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

**An unknown or unset `$TERM` falls back to `xterm`, not `ansi`.** This matters
more than it sounds: `builtin_ansi` has *no key definitions*, so under it the
arrow keys, Home, End, Delete and the function keys arrive as a literal Escape
plus characters and quietly corrupt the buffer. It does not look like a terminal
problem, it looks like the editor mishandling a motion.

Two details that go with it:

- **The 256-colour add-on is chosen by the name the user set, not the
  fallback.** The unknown-terminal path reassigns `term`, so testing *that* for
  `256color` gives `alacritty-256color` eight colours. `set_termname()` keeps
  the original in `requested` for this one test.
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
`-u NONE` and compare. All 67 behaviour cases and all five pty scenarios are
identical, and `:set all` differs only in `'loadplugins'`, which `-u NONE` sets
and no default controls.

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
gcc -c -O0 -Wall -Wextra -Wno-unused-parameter -o /dev/null vim.c
```

**It reports nothing at all**, and that is the point: the sweep is a boolean,
not a number to compare against a remembered baseline. A new warning cannot hide
behind "the usual two". The 37 deliberate fall-throughs say so with
`__attribute__((fallthrough))`, a hint that changes no code.

Substituting `-fsyntax-only` is faster but does **not** report
`-Wunused-function`, which is the one you want after a removal. Delete what it
names and run it again — deleting a function orphans its callees, and reaching
silence took eight rounds.

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

Run both sweeps alternately to a joint fixpoint: removing a function orphans
types, and removing a type orphans functions.

**Deleting an enumerator renumbers the ones after it**, and several enums are
the index of a parallel table — `hl_flags[HLF_COUNT]`,
`first_autopat[NUM_EVENTS]`. Where a deletion would move a survivor, give it its
original value explicitly, then check with DWARF, which records every enumerator
and its value:

```sh
tools/enumvals.sh vim.c before.txt      # dump, make the change, dump again
```

Dump before and after; every name present in both must have the same value.
There are 2,935. That is a stronger check than the build, which is perfectly
happy to renumber a table index.

### Add a constant

Prefer an enumerator. **But an enumerator is an `int`, so `sizeof` on it is 4**
— the one conversion that changes meaning while keeping the token stream
identical, and it once broke every `:w`: `#define PATHSEP ((char_u)'/')` became
an enum and eight `sizeof(PATHSEP)` sites silently became 4. Before converting
anything, grep for `sizeof(NAME)` and for a cast wrapping the *whole* body — a
cast inside the expression is harmless, one around it is the macro telling you
its type is not `int`. Use `static const char_u` for those.

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
lives between marker comments in `vim.c`:

```sh
python3 tools/create_cmdidxs.py vim.c --check   # or --update to rewrite it
```

Two traps if you ever remove a command:

- **A removed name is inherited by the next command sharing its prefix.**
  Deleting only `CMD_help` makes `:help` silently run `:helpclose`. Check what a
  removed name now resolves to before assuming it errors.
- **Related commands do not sort together.** `:lhelpgrep` survives a sweep of
  everything starting with `help`, because it sorts under `l`. Grep for the
  *handler* name (`ex_helpgrep`), not the command name.

### Regenerate vim.c from upstream

`vim.c` is not maintained by editing it into a new shape; it is **produced**,
and `GOAL.md` is the process that produces it. A pass looks like this:

```sh
git clone --branch regexp-delimiter-atoms --depth 1 \
    https://github.com/arbace/vim upstream
rm -rf upstream/.git                       # immediately
#   ... GOAL.md Phases 0-9 run inside upstream/ ...                     
#   ... vim.c moves to the repository root ...
rm -rf upstream                            # nothing of it is kept
```

`upstream/` is a **staging directory, not a checkout of anything**. It is
gitignored, so its 8,581 files cannot reach a commit, and it does not exist
between passes. `tools/` is what the pass is run with; `.reference/baselines/`,
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
tools/refcheck.sh          # the last act of producing vim.c
```

`.reference/vim.c` *is* the previous pass's output, so a new one should differ
only by what upstream changed — usually nothing. The tool reports the source,
the binary (tier 1), the documents and whether baselines are present, and exits
non-zero on a source or binary difference.

**A missing `.reference/` is the normal starting state, not a failure.** It is
gitignored and produced, so a fresh checkout has none; `refcheck.sh` says
"nothing compared" and exits 0, and the pass is checked by `verify.sh` against
the baselines Phase 1 records. It never replaces `verify.sh` either — one
compares against the last pass, the other against recorded behaviour, and a pass
that reproduced last time's mistake exactly would satisfy the first.

**Everything this tree has is in the phases.** The terminal-table reduction,
the compiled-in vimrc and the `'lazyredraw'` fix are Phase 1, because Phase 1
is where behaviour changes and where the baselines are recorded; `-static -s`
is Phase 3, with the makefile. There is no list of extras to re-apply
afterwards — a bare run of Phases 0-9 reproduces this tree, not a plainer one,
and that is what makes the comparison worth running.

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

If you ever have to resolve conditionals again, `GOAL.md` Phase 5 has the
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
phase edits the sentences its work made wrong — which is `GOAL.md` rule 5, and
the reason the rule exists is the third failure above: a file written by
appending one section per phase ends up describing several trees at once. The
reasoning that does not belong here belongs in the commit messages, one per
phase.

Guard against that last one: **this file describes one state, the current one.**
When something changes, edit the sentence that is now wrong rather than
appending a new section that disagrees with it.

The numbers here are measurements, not estimates. Re-measure rather than
adjusting them by reasoning, and say what you measured.

Whenever you update this file, the user wants the session transcript exported
alongside it as `TRANSCRIPT.md`. `/export` is a Claude Code built-in, not
something an agent can invoke and not a shell command, so say so and let them
type it — do not quietly skip it.

## Commit style

A `type: summary` subject, then prose explaining *why* the change was made, what
was measured, and how it was verified. State deliberate omissions explicitly.
