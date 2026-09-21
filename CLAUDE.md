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

One hundred and two tracked files (`git ls-files`): nine at the root, twelve
under `pipes/` — one program per phase, `pipes/slim<N>.sh` — and 81 under
`tools/`: 51 Python tools, 23 shell scripts, `renames.txt`, a `README.md`, two
patches under `tools/patches/` and three makefiles under `tools/templates/`. Two
of the nine at the root are products (`slim-vim.c`, `LICENSE`), one is a record
(`upstream.sha`), and the other six are the seed.

**The whim and zero pipelines are not here any more.** They took `slim-vim.c` as
their input — whim removing capability on purpose until nothing need be installed
beside the binary, zero turning that into an embeddable editor core — and they,
their documents and the Go toolset they ran moved to
[arbace/go-whim](https://github.com/arbace/go-whim), which fetches this
repository's `slim-vim.c` as its upstream. This repository is slim's pipeline and
its Python and shell tools and nothing else; `tools/stages.sh`,
`tools/memo.sh` and `tools/verifypass.sh` still carry the general shape they grew
for three pipelines, and for slim every unit is one phase.

**`pipes/` is the pipeline steps and `tools/` is what they are built from.** A
phase in `pipes/` is one file, run by the memoize driver as phase N and by nothing
else; everything a phase calls lives in `tools/`.

**THE TRANSFORMATION IS EXTERNALLY VERIFIED AND THE INSTRUMENT THAT GUARDS IT IS
NOT**, and a clone of the remote is what drew that line. On 2026-09-21 a clone
holding no `.reference/` and no `.build-*` ran the pass cold, and `slim-vim.c`
came back byte-identical and — the part a clean `git status` cannot say by itself
— **produced**: written 05:02:16 against a p11 boundary of 05:02:15. So
**F(upstream@`1c63ea1db1ee`) = the committed `slim-vim.c`** holds on a machine
that held neither the upstream history nor any prior pass. **Before counting an
agreement, ask by what route the two sides came to exist** — tracked, copied, or
separately produced, and only the third is corroboration. What a clone does *not*
establish is that the harnesses would catch anything: Phase 1's harnesses **do not
run and cannot fail** on a fresh checkout (see *Testing*), while the boundary and
product comparisons are real throughout.

**`tools/implhash.sh` hashes ITSELF into some keys and not others, and nobody
chose that.** `deps()` returns any `tools/…` path a program's text names, and
this file's own convention is to write such a path into a *comment* so the grep
can see it — so a comment that merely **talks about** the hasher charges its bytes
to that phase's key. Measured with a control: appending one comment line to
`implhash.sh` moves slim 1, 2, 5, 6 and 9 and leaves the other seven exactly.
**The convention cannot distinguish "I depend on X" from "I am talking about X"**,
which is the same blindness that makes it work at all. It is over-inclusive and
therefore safe — an extra key costs CPU and never a wrong boundary.

**Editing an existing phase's program does not re-run it, and `make slim-pass`
will not tell you so.** The content-keyed tier-3 check lives *inside* the recipe,
and make never gets there: a phase's prerequisite is the previous boundary
*file*, so an existing `p7.sha256` that is newer than `p6.sha256` is "up to date"
and the recipe is skipped whatever the implementation digest now says. `make
slim-phase-N` and `make slim-tip` are `.PHONY`, so their recipes always run and
the tier-3 key then decides; `make slim-repass` removes `.build-slim` outright.
**After editing a phase that is not the last, use `slim-repass`.**

**A tier 3 replay copies the recorded digest rather than recomputing it**, so a
warm pass agrees with the oracle whatever the oracle says. Only a run that
recomputes every digest can falsify a boundary, and there are two: **`make
slim-verify`** runs every phase at once, each on the recorded boundary before it
in a scratch root of its own, and requires each recorded boundary back — by
induction the same proof as a cold pass, in the time of its slowest phase — and
`make clean-cache && make slim-repass` is the sequential run, the one that
*produces* boundaries rather than checks them. Do one before a push, and whenever
a **shared** tool changes — `canon.sh`, `cutil.py`, the harnesses.

**A check torn mid-execution used to report success.** `sh` reads a script **by
byte offset as it executes it**, so rewriting one in place while it runs makes the
shell resume at a stale offset in new content — and `verifypass.sh` gave every
unit a symlink to the ONE live `pipes/`. Where the tear lands decides the symptom,
and all three were measured: **mid-token**, a `syntax error` at a line that exists
in *neither* version; **at a command boundary after a non-zero command**, a
non-zero exit with nothing printed; and **after a zero one, exit 0, reported as
`ok`** — ten truncation points tried, ten exited zero. **Git is not the hazard**:
it writes by atomic rename, so a running shell keeps its fd on the old inode. The
hazards are in-place writers — an editor saving over a file, `sed -i` without a
temp, a `cp` onto the original. Fixed by giving each unit a **snapshot** of
`tools/` and `pipes/` taken once before any unit starts, and by **reporting the
exit status** instead of merely testing it. The output digest is compared
independently, so a torn check cannot fabricate a **boundary**; `memo.sh`'s
tier-2 path has no such backstop.

**When a tool stops being CALLED, check whether it is still IMPORTED** before
treating it as unused: `pipes/slim2.sh` imports `keepset` by module name, which
`implhash.sh` cannot see — it sees only paths — so every importing file names its
imports' paths in a comment (see *Testing*), and `slim2.sh` names
`tools/keepset.py`.

```
slim-vim.c     the editor, headers and forward declarations included
Makefile       the seed: builds the editor, and produces it when upstream moves
slim.mk        slim-vim.c = F(upstream@sha), twelve phases as make targets
upstream.sha   the commit slim-vim.c was produced from
pipes/         the phases: one program each
tools/         the harnesses, the passes, and what the phases call
README.md  CLAUDE.md  SLIM-GOAL.md  LICENSE  .gitignore
```

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

Six things appear untracked, and `.gitignore` names them:
`slim-vim`, which the build adds and `clean` removes; `.reference/`, the recorded
baselines and phase digests beside the previous `slim-vim.c` (see below);
`TRANSCRIPT.md`, which `/export` writes when the user asks it to;
`upstream/`, the pristine vim tree a pass clones in, works on and deletes —
8,581 files that must never reach a commit, and which do not exist between
passes; `.build-slim/`, the phase boundaries a pass leaves behind — a tar and a
content digest per phase, plus each phase agent's stream and its elapsed
seconds; and `PROGRESS.md`, the transient insight log whose contents are folded
into `SLIM-GOAL.md` and this file and then deleted. `upstream.sha` is deliberately
*not* ignored: it is the record of what `slim-vim.c` was produced from.
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

The target you would type is the product, `slim-vim`, and `clean`, which
removes it. Everything upstream had — `all`, `install`, `test`, `proto`, `tags`,
`depend`, `lint`, `shadow`, `distclean` — is gone, along with the second makefile
that recursed into `src/`.

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
| **2** | the **code** — `pipes/slim<N>.sh` | 1–153 s | exactly what it was written for |
| **1** | the **agent** — `claude -p`, one phase | 5–17 min | cope with something it has not seen |

**Tier 3 is keyed by content, not by time.** The key is the input boundary's
digest and the implementation's digest together — `tools/implhash.sh` hashes
the phase's program plus every tool, patch, table and
template it names — so a
cached result answers exactly one question: *this implementation, applied to
this input*. Measured: Phase 4 costs 63 s cold and **0.17 s** cached; editing
its program changes the key and it runs again; reverting the edit restores the
old key and it is cached again. That is stronger than a timestamp, and it is
what makes editing one phase re-run that phase and the ones after it rather
than all ten.

**And the input half of that key must be a function of the input, which is the
one property tier 3 rests on.** `tools/memo.sh` once built it as
`cat "$build/$TAG$((first - 1)).sha256" 2>/dev/null || cat "$build/input.sha256"` —
asking *did `cat` fail* where it means *is this the first unit*. The two differ only
when a **phase list has a gap**: a missing boundary fell through to the input's
digest, which never moves, so the key stopped varying and a cached result came back
whatever the real input became. It was hit twice in the zero pipeline (now in
arbace/go-whim). It now tests `first = 0`, and otherwise requires the boundary and
**refuses**: a gap is `memo: … wants p<N>, which does not exist.` and exit 1.

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
  1      program           809  a deliberate patch: the edits are fixed
  2..8   program             0  computed
  9      program           134  what is genuinely a decision
         total             943
```

Phase 1's 809 lines are not a failure to understand it — its content genuinely
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

**A pass reproduces `slim-vim.c` byte for byte, and that is now measured from
OUTSIDE.** This paragraph used to say the last pass produced a binary identical
to the committed one and a `slim-vim.c` differing by **49 lines**, all of it
Phase 8 — a redundant `static` on definitions whose earlier prototype already
gives them internal linkage, and one dead prototype kept — and called those 49
lines Phase 8's real residue. They are not there. A cold `make slim-repass` in a
**clone of the remote**, holding no `.reference/` and no `.build-*`, produced a
`slim-vim.c` byte-identical to the committed one and an empty
`git status --porcelain`: phases 2..11 all *by program*, 321 s of phases, 333 s
total. So the left-hand side is the upstream remote and the right-hand side is
git, and **F(upstream@`1c63ea1db1ee`) = the committed editor** is a statement
about a machine that held neither the upstream history nor any prior pass.

**That run checked the one thing that would have made it vacuous**, which is this
file's own *a "clean rebuild is byte-identical" check passes if the rebuild never
happened*: an empty `git status` is exactly what a pass that skipped the file
gives. The control is the product of a pipeline that had not run — the clone was
made at 04:56:03, the p11 boundary landed at 05:02:15, `slim-vim.c` was rewritten
at 05:02:16 while a tracked file no pass writes was still 04:56:03. mtime
distinguishes here, so the product was **produced and then
matched** rather than matching by not being touched.

**The 49-line sentence had disagreed with the residue table above it for as long
as it stood** — that table gives phases 2..8 a residue of 0 — and neither reading
could be settled, because nothing could test either from outside a tree that had
already run. **The same gap is why the timing is two figures and not one**: 411 s
of phases from an empty cache here against 321 s in the clone on an idle machine.
Both are measurements of different conditions, and the rule this file states —
re-measure rather than adjust — means keeping both with their conditions rather
than overwriting one.

**A tier-2 failure is not an error, it is the construct working.** The pass
falls through to tier 1, which produces an answer and a new patch; `make`
wraps that as `passorref`, and `tools/repair.sh` then hands the failing phase,
its error and the agent's account to an agent whose job is to fix the
*program* — preferring a computed rule over a constant, and saying plainly when
a change genuinely needs judgement, in which case that one phase reverts to an
agent and the other nine do not.

**`NO_AGENT=1` refuses instead of falling through.** The fallback costs a
`claude -p` run, and a phase program that refuses on purpose — an assertion doing
its job, a probe calibrated against the wrong boundary — is a failure to read, not
a question to hand to an agent. Slim leaves it unset by default, because its phases
are where the agent tier still earns its place.

**The top level is already an instance of this.** `upstream.sha` is tier 3 of
`F` itself: when the branch head matches, the cached `slim-vim.c` is returned and
nothing runs at all.

## Testing

There is no upstream test suite in play. Four harnesses stand in for it, all in
`tools/`; the baselines they are compared against are in `.reference/baselines/`,
which **a fresh checkout does not have and NO PASS CREATES**.

This file used to say a pass records them in Phase 1, and that is wrong — found
by a cold `slim-repass` in a clone of the remote, whose whole `.reference/` is
one entry, `slim-phases`, with no `baselines/` beside it. `pipes/slim1.sh` is
explicit about it: `if [ ! -d "$base" ]`, print *"baselines absent — first pass,
nothing to compare against. Record them from this binary before Phase 2"*, and
**`exit 0`**. The four `check` calls below that line are never reached, and the
instruction is addressed to a reader, which nothing in the tree performs. So on
a fresh checkout the behavioural half of the verification **does not run**, and
the phase cannot fail — which is not the same as passing, and is why this
paragraph is worth reading before trusting a clean pass on a new machine.

**That `exit 0` may well be right and is left alone deliberately.** It is Phase 1
declining to manufacture a baseline that would immediately certify itself, which
is this section's own rule below being obeyed. What was wrong is the sentence,
not the code: a reader who believed a pass records them would think a fresh
checkout was protected when the harnesses had not run at all.

**So a clone is two-valued.** Phase 1's harnesses do not run and *cannot* fail;
the boundary digests and the product comparisons are real throughout. A better arm
for `pipes/slim1.sh`, if it is ever revisited, is the one the whim pipeline's delta
check took: **say in the report** that half the check did not happen, still run
the half that needs no baseline, and exit with that half's status rather than 0.

**`tools/verify.sh .reference/baselines` runs all of them concurrently and gives
one verdict, in about 18 seconds** — eight of them the build. Use it after any
change; add `--enums` for the DWARF check. It is proven to fail on a broken
build, on a behaviour change and on a blank line landing in the generated
command table.

### `.reference/` is the frozen state, gitignored, and optional

Four things, each with a reader: `baselines/`, which `verify.sh` compares
against; `slim-phases/`, the recorded boundary digests `oracle.sh` checks each
phase against; and `slim-vim.c` with the `slim-vim` built from it, the left-hand
side of `refcheck.sh`. **It is not tracked and it is not a precondition**: a pass
produces it, so a checkout that has never run one has no `.reference/` at all and
everything here describes what exists afterwards.

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
self-fulfilling — and this file used to describe the consequence too generously,
as *the first pass in a fresh checkout is self-certifying on behaviour*.
Self-certifying would mean it recorded and then compared against its own
recording. It does neither: Phase 1 takes the `exit 0` above and the harnesses
never run, so a fresh checkout has **no** behavioural certification rather than a
weak one. That is the whole reason to keep this directory across passes, and the
reason it is the one thing worth copying if this tree is ever moved.

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

**The floor is 80 and was 100** because the zero pipeline, now in
arbace/go-whim, deleted rows until its table held 98; it was lowered in the commit
that crossed it, with the reason in the tool's docstring. For `slim-vim.c`'s 600
rows it changes nothing. The failure is not the one the name suggests —
`names()` tries both parsers with `check=False`, so a too-short table comes back as
`no command table found in either shape` rather than as a count.

### Four things a harness here has to get right

**A binary's own name changes what it does.** `parse_command_name()` reads
`argv[0]`: a basename starting with `r` turns on **restricted mode** and every
shell-out fails, `e` selects evim, `g` the GUI, and `view`/`ex` prefixes change
the mode again. A reference binary saved as `ref` made `:%!sort` and
`:r !echo` fail against a binary that was byte-identical to one called `vim`.
Every harness stages the binary under test into a temp directory as `vim`,
whatever it was called outside — so the recorded baselines always describe
`argv[0] == "vim"`, and renaming the product could not silently move them.

**That staging is one function, and it is one function because of a race.**
`shutil.copy2` holds a write fd on its destination, and a `fork` in another
thread — `termcheck.py` and `ptycheck.py` run their sessions in a
`ThreadPoolExecutor` — hands that thread's child the same fd until it execs;
`execve` refuses a file any process holds open for writing, so the *copying*
thread's own exec dies with `Text file busy`. `stage()` copies **once per binary,
under a lock, in a child process**, so the write fd never exists in an address
space that is forking.

**It lives in `tools/ptyrun.py`**, called by `termcheck.py` and `ptycheck.py`.
Before it there were **5 exec failures in 100 idle runs** of `termcheck.py` — 1,900
pty sessions — against **0 in 100** after, and 1 of 60 against 0 of 60 interleaved
in one loop; **load does not make it likelier** (0 in 60 under a steady 256-way
load, 0 in 20 under an oscillating 128-way one), because what overlaps is the
nineteen threads' *startup*, which a loaded machine spreads apart.

**A harness that stages a binary makes a directory, and one that never removes it fills
`/tmp` — which is found somewhere else, as something that looks unrelated.**
`tools/termcheck.py` leaked **two**: `ask()` made a scratch directory per pty session, 19
terminals on every invocation, and `_HOME` made one per process at import, and neither was
ever removed. Measured before the fix: **182,319** of them were lying in `/tmp`, from this
harness and its zero-pipeline sibling — and **an ext4 directory that full answers `mkdir`
with `ENOSPC` on a disk with 70 GB free**, which is how it surfaced: it failed a phase that
has nothing whatever to do with terminals. `ask()` now wraps the session in try/finally
and `_HOME` gets `ptyrun.py`'s `atexit`. **What it changes is what the harness leaves
behind, not what it reports**: a full 19-row run is byte-identical to
`.reference/baselines/ref-term.txt`, and the leak count is **0 after a complete `make
slim-verify`**.

**A tool reached by `import` and never named as a path was in no implementation key
at all.** `implhash.sh` extracts dependencies by grepping a program for `tools/…`
*paths*; Python tools reach each other by module name, so `import ptyrun` named nothing
it could see. Measured both ways: a one-line change to `termcheck.py` moved keys and the
same change to `ptyrun.py` moved **none**.

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

**The fix names the path in a comment beside the import**, in every importing
file, and leaves `implhash.sh` alone. `implhash` greps, and does not know what a
comment is. Measured: slim 1, 5, 6 and 9 moved, no boundary moved, and `slim-verify`
was 12 of 12. **Do not delete those comments**; each says so in place.

**The rule is a program, because as a habit it failed twice in one hour.** The
correct cleanup when a phase stops running a tool — *stop naming it* — deleted the
comment in a phase that still **imported** the module. So: **stop naming a tool you
stopped running; keep naming one you still import**, and `tools/importpaths.py`
checks it — `--fix` repairs, and it is proven able to fail. It found a hole nobody
was looking for, `pipes/slim2.sh` importing `keepset`, which is the argument for a
checker over an audit: **a checker checks what you were not thinking about; an
audit checks what you were.** It is named by no phase program, so it enters no
key.

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

**No harness passes `-u NONE`; they isolate through the environment.** Every
run gets an empty `$HOME`, `$VIM`, `$VIMRUNTIME` and `$XDG_CONFIG_HOME`, and no
`$VIMINIT` or `$EXINIT`, so `slim-vim` finds no `~/.vimrc`, system vimrc or
runtime defaults. Measured against the baselines with a real `~/.vimrc` on the
machine: nothing moved. Commands go in as `+{command}` rather than `-c`, and fill
the same list.

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

Four checks that pass while doing nothing:

- **`objcopy -O binary --only-section=X f /dev/stdout` writes nothing and exits
  0.** Comparing two such streams reports every pair of binaries identical.
  Write to real files.
- **A "clean rebuild is byte-identical" check passes if the rebuild never
  happened.** Check the elapsed time, or that the artifact was removed.
- **A script that printed a success message has not necessarily written
  anything.** Re-read the file, or grep for the new text.
- **`git bundle verify` never reads the packfile.** Measured on this tree's own
  backup bundle truncated to 32 % of its length: it prints the identical ref
  listing, says **`is okay`** and exits **0**, while `git fetch` of it dies with
  `index-pack died`. The two questions differ by the entire payload — *is this a
  well-formed bundle whose basis I have* against *can I get the work out* — and
  the second is answered only by performing the recovery. A backup that verifies
  and cannot be read is the same shape as a rebuild that never happened.

**And a fifth shape, which is worse than the four and was found in the tool
written to answer the fourth.** A bundle checker (`bundlecheck.sh`, which went to arbace/go-whim with the
Go toolset) handed a relative bundle path to a `git -C <scratch> fetch`, which changes directory first, so the
path resolved inside the scratch repository: the **real** bundle failed with
`'…' does not appear to be a git repository` while a torn one and an empty one
went on failing for the right reasons by accident. Two right out of three, with
the only one that matters inverted — and a person running all three sees two
correct refusals and one plausible failure, and concludes the bundle is bad
rather than the script.

**That is not a check that passes while doing nothing; it is a check whose false
NEGATIVE is indistinguishable from the failure it exists to detect.** The four
above say "okay" when they are wrong, so the wrong answer is legible as wrong
once a reader knows to look. This one said *cannot be applied* about a perfect
bundle, in the same words it uses for a torn one, and no reading of the output
tells them apart. On a tool that only ever runs when something has already gone
wrong, that is the failure mode care cannot recover from.

**Both defects in that script were invisible until the run that exercised them**
— the bundle one only appeared once the basis one was fixed, and its sibling
only on the empty case — which is the argument for three cases and not one,
especially on a tool nobody runs until they need it.

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
nobody's and `undowhile.py` is `pipes/slim9.sh`'s directly. `forcomma` is a no-op here too — it finds three `for` init
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
the lesson above arriving one phase later than it is told. The whim pipeline's
first stage collapses it.

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
under `-T xterm`, under `-T ansi` and under `-T dumb` alike, and Home behaves the
same way.

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
ships no vimrc and the defaults **are** the vimrc — and it cost three lines and
the binary not a byte of size.

**The general lesson is the one to keep: a proof by agreement is only as strong as the
harness's vocabulary.** The two binaries *did* agree — `:set all` prints the value either
way, and **no harness had ever pressed a modified key**. `ptycheck.py`'s `arrows` pressed
the plain arrows, and every other `\x1b` in `behaviour.py`, `exsweep.py` and
`termcheck.py` is a bare Escape — while `ins_start_select()` and the `NV_SS`/`NV_SSS` arms
of `normal_cmd()` are all three gated on `km_startsel` and need `MOD_MASK_SHIFT` to be
reached at all. The instrument was added **first** and proven to record the defect before
anything was fixed: `ptycheck.py` gains a sixth scenario, `shift_arrows`, and a
`--- mode ---` row per scenario read from the accumulated stream rather than the final
screen, because the keys that quit wipe the message line. Measured on the committed
binary before any repair: `shift_arrows` left `eta two` and `--- mode --- none`, and after
it `beta two` and `--- mode --- VISUAL`. **The whole difference in the re-recorded
baselines is fifteen lines of `ref-pty.txt`** — six mode rows and the nine-line
`shift_arrows` block — with `behaviour/`, `ref-exsweep.txt`, `ref-term.txt` and
`enumerators.txt` byte-identical, which is the condition a re-record has to meet to not
be self-fulfilling.

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
read, so anything that needs one compiles again.

**`-Wunused-but-set-variable` does not reach an address-taken or file-scope object.**
The warning fires on an ordinary local that is written and never read, and
`tools/deadsweep.py` does not act on it at all — so what it *does* report has to be
removed by hand, and what it does *not* report is invisible twice over: a file-scope
int whose writers have all gone, left constant with one reader, draws nothing in either
direction, and neither does a variable that is **write-only through several functions**,
because taking its address counts as a use. It is `deadfields.py`'s shape in a local:
no warning covers it, so it takes reading. The zero pipeline met it nine times.

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

**Every sweep does this now.** `tools/deadenums.py` runs in slim's Phase 8
loop: it dumps the values on
first need, pins the first survivor after each deleted run, keeps a run whose
next survivor DWARF has no value for — gcc does not emit every enum, and an
unpinned survivor would renumber invisibly — and dumps again with `--verify`
once the loop is done. `tools/deadfields.py` sits beside it for struct fields,
which no warning covers either, and **refuses while `ml_recover()` exists**:
removing a field moves the ones after it, and while the editor can read a swap
file, block zero and the memfile's pages are a disk format. So `slim-vim.c`
keeps every field.

**`deadfields.py` removes the member and leaves the initialisers, so a field whose
only reader a phase deletes must go in that phase's own edit and not the sweep.** The
sweep would take the member and leave an initialiser with one value too many, which is
`warning: excess elements in struct initializer` on a correct phase. A field the edit
knows is dead is the edit's to take, **with its data** — the tool cannot do it, because
an initialiser list is not what it parses. And it matches "named nowhere outside a type
definition", so a field that is **written** and never read is invisible to it.

**And it matches a field by NAME, so a name two structs share is invisible to it for
ever.** An edit that removes such a member earns the right to by **computing the
partition** — requiring every remaining mention to belong to the other struct — rather
than asserting it. The same rule covers a table indexed by an enumerator: `deadenums.py`
would take the enumerator and leave the row it indexes, so an edit takes **both** and
renumbers what follows.

### Add a constant

Prefer an enumerator. **But an enumerator is an `int`, so `sizeof` on it is 4**
— the one conversion that changes meaning while keeping the token stream
identical, and it once broke every `:w`: `#define PATHSEP ((char_u)'/')` became
an enum and eight `sizeof(PATHSEP)` sites silently became 4. Before converting
anything, grep for `sizeof(NAME)` and for a cast wrapping the *whole* body — a
cast inside the expression is harmless, one around it is the macro telling you
its type is not `int`. Use `static const char_u` for those.

### Rename a name across the whole file

**A whole-file substitution must be literal-aware and single-pass**; the zero
pipeline (now arbace/go-whim) measured both halves.

**Literal-aware**, because a name in a string is data and data is the one thing a
mechanical edit must not change. The zero pipeline turned `NULL` into `nullptr`, and three
string literals in that file contain the word — an `E1507` internal-error message,
`"[NULL]"` and `msg_puts("NULL")`. A plain `sed -E 's/\bNULL\b/nullptr/g'` rewrites all
three and the binary moves **1,598 bytes, 1,354 of them in `.rodata`**, with `[nullptr]`
visible in `strings`. **Neither verification tier above can see this**: the build is
clean and the token stream is right. The check is the *strings*, and the way to make the
`cmp` mean something is to build the literal-unaware form as a control and require it to
differ. `slim-vim.c` has no preprocessor, so scanning for string and character
literals is cheap; do that first and rewrite only outside them — and outside its
banner comments.

**Single-pass**, because literal spans are **offsets**, and every offset after the first
replacement is wrong. Rewriting two names in two passes indexes the second pass's spans
against the *first pass's output*: it was measured, and the two-pass form left
**five of 437 `size_t` behind** — in a file that still compiled and whose binary was
still byte-identical, because the header that declares the name was still above it. Rewrite every name in one pass over the original text, or
recompute the spans between passes — and **assert a partition, not a count**: classify
every occurrence into the classes the rule serves and refuse on a leftover, which stays
true of a file the edit has never seen.

**A count is a fact about a tree that *was* measured; a partition is a fact about the
tree that arrives.** A counted anchor written against one boundary refuses when an
earlier phase lands in front of it and changes the count — which is better than the
alternative, and worse than classifying every mention and reading the number off the
text.

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
it in insert mode. A row is pointed at `nv_error`, never deleted, and the index
must stay a permutation of the rows.

Two traps if you ever remove a command:

- **A removed name is inherited by the next command sharing its prefix.**
  Deleting only `CMD_help` makes `:help` silently run `:helpclose`. Check what a
  removed name now resolves to before assuming it errors, and remember that a
  spelling which already answered E492 before the removal proves nothing about
  it.
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
phase is run by a **program** if `pipes/slim<N>.sh` exists, and by an **agent**
if it does not. Converting a phase is therefore adding a file; nothing else
changes, and the pass runs end to end at every point in between.

Each phase is a pure function of its input: the recipe restores the previous
boundary into `upstream/` before running, so a phase cannot inherit anything
from a run that went wrong. A **boundary** is a tar (the restore point:
everything) beside a **content digest** (the meaning: a sha256 over every
source file's own sha256, with `objects/`, the built binary and `config.log`
excluded — that last one carries a timestamp, and a boundary containing it
would never equal itself twice).

**The built binary is excluded for exactly that reason too**: `version.c` embeds
`__DATE__` and `__TIME__`, so a boundary that counted its own binary would never equal
itself twice. The exclusion has to match the binary's actual name — `/vim$` matches
`./vim` and does *not* match `./whim-vim`, which is how every boundary of the whim
pipeline counted its own binary for eleven phases. **Nothing caught it**, because a
phase replayed from the tier 3 cache copies the recorded digest rather than
recomputing it. **Only a run that recomputes a digest can falsify a boundary.**

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
bytes** — two stores at `-O0` are real instructions and alignment padding absorbs them. **That is the one place in this tree where `.reference/baselines/` is
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

**That rule covers refusals too, and that is where it is hardest to apply.** A
denied action, a tool that was unavailable, a command the environment would not
run — each is a measurement with a timestamp, not a property of the world, and
carrying one forward is reasoning in exactly the place the rule forbids it. It
happened here: a `git push` refused early in a session was reported as still
blocked for eight turns and seven commits after the circumstances around it had
visibly changed, while everything else in the tree was being re-measured rather
than remembered. **Re-trying an action that was refused, once the situation
around it has changed, is measurement and not circumvention** — and the thing
that keeps that distinction honest is declining to reach the same end by another
route while the refusal is live.

## Commit style

A `type: summary` subject, then prose explaining *why* the change was made, what
was measured, and how it was verified. State deliberate omissions explicitly.
