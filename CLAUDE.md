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
181,844 lines and is the whole editor; one `gcc` invocation builds it in about
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
six things — `.gitignore`, `Makefile`, `README.md`, this file, `SLIM-GOAL.md` and
`tools/` — and `slim-vim.c` and `LICENSE` appear when a pass produces them. A
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

A hundred and thirty-two tracked files once both pipelines have run: thirteen
at the root, and 119 under
`tools/` — the passes, the harnesses, the phase programs (ten for `slim.mk`,
seventeen for `pure.mk`), the memoize
driver, a `README.md`, and the data a pass cannot derive: `renames.txt`,
`patches/` and `templates/`. Three of the thirteen are products
(`slim-vim.c`, `pure-vim.c`, `LICENSE`), two are records (`upstream.sha`,
`slim.sha`), and the other eight and `tools/` are the seed.

```
slim-vim.c     the editor, headers and forward declarations included
pure-vim.c     the same editor with no runtime to install
Makefile       the seed: builds both, and produces them when their input moves
slim.mk        slim-vim.c = F(upstream@sha), ten phases as make targets
pure.mk        pure-vim.c = G(slim-vim.c), the same construct
upstream.sha   the commit slim-vim.c was produced from
slim.sha       the slim-vim.c pure-vim.c was produced from
tools/         the harnesses, the passes, and the phases that are programs
README.md  CLAUDE.md  SLIM-GOAL.md  PURE-GOAL.md  LICENSE  .gitignore
```

**There are two pipelines, and they are the same construct.** `slim.mk` and
`pure.mk` differ only in what their phases do; the driver, the boundaries, the
oracle and the synthesiser are shared, and `tools/pipeline.sh` is the whole of
the parameterisation.

**Their names are symmetric, and that is maintained deliberately.** Every
variable is `SLIM*`/`PURE*` and every target is `slim-*`/`pure-*`, so a target
that exists on one side and not the other is a question rather than an accident:

| | slim | pure |
| --- | --- | --- |
| run a pass | `slim-pass` | `pure-pass` |
| force one | `slim-repass` | `pure-repass` |
| one phase, replay | `slim-phase-N` `slim-replay-N` | `pure-phase-N` `pure-replay-N` |
| record, time, score | `slim-record` `slim-times` `slim-residue` | `pure-record` `pure-times` `pure-residue` |
| throw away the work | `slim-clean` | `pure-clean` |

Three targets are deliberately one-sided and each says why. `slim-promote-N` has
no twin because promotion exists to turn an *agent*-recorded boundary into a
check, and every pure phase is a program. `slim-clone`, `slim-preflight`,
`slim-refpass`, `slim-compare` and `slim-passorref` have none because only the
slim pipeline has a remote to clone, a network to check for, and a reference
path run by one agent. And two targets belong to neither: `clean-cache` empties
the tier-3 cache both share, and `score` reports the pair side by side — bytes
to store and symbols to provide — which is why it is not `pure-score`. The distinction that matters is in the *rules*:
`SLIM-GOAL.md` changes nothing about what the editor can do and any behavioural
change is a bug, while `PURE-GOAL.md` removes capability on purpose — so every
phase there declares its delta in advance and the harness proves it caused that
and nothing else.

**`upstream.sha` is tracked, and that is load-bearing rather than tidy.** It is
what `make` compares the branch head against, so a checkout without one has
nothing to compare and fires a whole pass on a tree that is already correct —
which is the same hazard, arriving by a different route, that made the
dependency content-based instead of a timestamp. The makefile writes it after a
pass succeeds; committing it alongside the `slim-vim.c` it describes is what keeps
the next `make` cheap.

`README.md` is the front door and carries no figures; this file and `SLIM-GOAL.md`
are the authority, which is what keeps a third description from drifting.

`tools/` is the only tracked subdirectory at the root and has a `README.md` of
its own; `tools/templates/` beneath it holds the makefile Phase 3 installs into
the staging tree.
Nothing in it is part of the build; the build reads `slim-vim.c` and nothing else.

Six things a pass produces appear untracked, and `.gitignore` names them:
`vim`, which the build adds and `clean` removes; `.reference/`, a frozen
copy of this tree with the recorded baselines beside it (see below);
`TRANSCRIPT.md`, which `/export` writes whenever this file is updated;
`upstream/`, the pristine vim tree a pass clones in, works on and deletes —
8,581 files that must never reach a commit, and which do not exist between
passes; `.build-slim/`, the phase boundaries a pass leaves behind — a tar and a
content digest per phase, plus each phase agent's stream and its elapsed
seconds; and `PROGRESS.md`, the transient insight log whose contents are folded
into `SLIM-GOAL.md` and this file and then deleted. `upstream.sha` is deliberately
*not* ignored: it is the record of what `slim-vim.c` was produced from.
`.gitignore` also names what the tools and the editors leave lying
about: `*.swp`, `__pycache__/`, `*.pyc` and `.claude/`. The `.gitignore` upstream shipped named 91 paths, of which two still
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

Two targets you would type, `slim-vim` and `clean` — and `clean` removes both
products, because there are two. Everything upstream had —
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
| **2** | the **code** — `tools/<pipeline><N>.sh` | 1–380 s | exactly what it was written for |
| **1** | the **agent** — `claude -p`, one phase | 5–17 min | cope with something it has not seen |

**Tier 3 is keyed by content, not by time.** The key is the input boundary's
digest and the implementation's digest together — `tools/implhash.sh` hashes
the phase's program plus every tool, patch, table and template it names — so a
cached result answers exactly one question: *this implementation, applied to
this input*. Measured: Phase 4 costs 63 s cold and **0.17 s** cached; editing
its program changes the key and it runs again; reverting the edit restores the
old key and it is cached again. That is stronger than a timestamp, and it is
what makes editing one phase re-run that phase and the ones after it rather
than all ten.

**Tier 1 is not a function, and is never treated as one.** Two agent runs on
identical input have been measured to differ — Phase 5 produced a different
`edit.c` the second time. Its result is cached, but its boundary is *advisory*
and never a check.

**The point of tier 1 is what it leaves behind.** When an agent runs,
`tools/synth.sh` diffs the two boundaries and writes the difference out as
`tools/patches/p<N>-residue.patch`, plus a `phase<N>.sh` that applies it if the
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

**A pass costs about ten minutes** with every phase a program: 31 s, 20 s, 6 s,
1 s, 63 s, 12 s, 11 s, 40 s, 385 s, 34 s. It cost 24 minutes with Phase 9 at
tier 1, and 67 when one agent did all of it. **Phase 8 is now two thirds of the
total**, being compile-bound — the static loop plus eight sweep rounds, each
running gcc twice over a 177,000-line file — and is where the next minute comes
from.

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

A copy of `slim-vim.c`, the binary built from it, the two documents, `Makefile`,
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
SOURCE_DATE_EPOCH=0 gcc -O0 -static -s -o /tmp/t/vim slim-vim.c
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
`python3 tools/create_cmdidxs.py slim-vim.c --check` verifies the table in place, between
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
Every harness stages the binary under test into a temp directory as `vim`,
whatever it was called outside — so the recorded baselines always describe
`argv[0] == "vim"`, and renaming the product could not silently move them.

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
| deleted, nothing mentioned them | 909 |
| enumerators (`enum { … }`, `enum : long { … }`) | 1,443 |
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
and the only other globals are the C runtime's. Everything else is `static` — 4,288
declarations, of which 1,993 are the former `proto/*.pro` block near the top of
the file, the rest of that block having gone to the dead-code sweep.

**A *function* definition following a `static` declaration inherits internal
linkage**, which is why three thousand definitions say nothing about it.
**Objects do not inherit**: a file-scope object with no storage class has
external linkage whatever a prior declaration said, and gcc rejects the pair.

The forward declarations are what keep definition order inside `slim-vim.c` from
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
This pass found **1,542 bodies not on a line of their own and 1,564 not
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

**The paragraphing was never lost.** 17,264 blank lines, 9.5% of the file and
**5.21 per function** — the density of a build that kept its comments. Every
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
tools/enumvals.sh slim-vim.c before.txt      # dump, make the change, dump again
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
lives between marker comments in `slim-vim.c`:

```sh
python3 tools/create_cmdidxs.py slim-vim.c --check   # or --update to rewrite it
```

Two traps if you ever remove a command:

- **A removed name is inherited by the next command sharing its prefix.**
  Deleting only `CMD_help` makes `:help` silently run `:helpclose`. Check what a
  removed name now resolves to before assuming it errors.
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

**The pass is `slim.mk`, and it is ten make targets, not one agent.** A phase's
prerequisite is the previous phase's boundary, so `make` sequences them — and a
phase is run by a **program** if `tools/<pipeline><N>.sh` exists and by an **agent**
if it does not. Converting a phase is therefore adding a file; nothing else
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
`./pure-vim`, so every pure boundary counted its own binary — and `version.c`
embeds `__DATE__` and `__TIME__`, so no pure boundary was ever equal to itself
twice. **Nothing caught it for eleven phases**, and the reason is worth keeping:
a phase replayed from the tier 3 cache copies the recorded digest rather than
recomputing it, so a cached pass agrees with the oracle whatever the oracle
says. **Only a run from an empty cache can falsify a boundary.** `make pure-repass`
after `rm -rf .cache/q*` is that run, and it is the check to make before
trusting a recording — every pure boundary reproduces under it, each phase a
program.

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
tools/refcheck.sh          # the last act of producing slim-vim.c
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
is Phase 3, on the scaffolding makefile that lives inside `upstream/` and dies
with it — the root `Makefile` is the seed and no phase writes it. There is no
list of extras to re-apply afterwards — a bare run of Phases 0-9 reproduces
this tree, not a plainer one, and that is what makes the comparison worth
running. It has been run: the pass of 2026-09-10 reproduced `slim-vim.c` **byte for
byte** against the previous one, 181,844 lines, and the binary with it,
2,208,088 bytes.

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

Whenever you update this file, the user wants the session transcript exported
alongside it as `TRANSCRIPT.md`. `/export` is a Claude Code built-in, not
something an agent can invoke and not a shell command, so say so and let them
type it — do not quietly skip it.

## Commit style

A `type: summary` subject, then prose explaining *why* the change was made, what
was measured, and how it was verified. State deliberate omissions explicitly.
