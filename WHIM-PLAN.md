# WHIM-PLAN.md — how the whim pipeline could be better formed

It began as a plan, and nothing in `pipes/`, `tools/`, the makefiles or the two
products was touched to write it; sections 2d, 3 and 7 now also say what was built
from it and what that measured. Every number below was measured in a separate git
worktree and a scratch directory (a lab since deleted; see the appendix), against
the recorded boundaries of the current pipeline, and says what it was measured on.

**The fixed points.** `slim-vim.c` goes in and `whim-vim.c` comes out, byte for byte
what they are today. Everything between them may be reorganised. That constraint is
also the best tool this plan has: the 83 recorded boundaries are an oracle, so a
change meant to be neutral can be *proved* neutral against them, and a
reorganisation that moves intermediate boundaries is still held to the last one.

## Summary

| configuration of the same 83 phase programs | sweeps | wall, sequential |
| --- | --- | --- |
| **today**: `make whim-repass`, cold | 105 | **83 min 12 s** |
| stages: sweep only when the next phase refuses unswept text | 10 + 23 inner | 46 min 18 s |
| … and the symbol snapshot per stage, and warnings without codegen | 6 + 23 inner | 32 min 25 s |
| … and the nine inner sweeps that are not needed | 7 + 14 inner | **27 min 15 s** |
| **as built** (§2d): 12 stages, the checks forcing 5 more boundaries, every check and delta run, cold `make whim-repass` | 12 + 14 inner | **26 min 27 s** |
| **all 82 phases merged into one program** (§8), with that sweep schedule and phase 82's checks | 7 + 14 inner, one phase | 29 min 41 s |

Every row ends at the committed `whim-vim.c`, and in every row **each stage boundary
is byte-identical to the recorded boundary of the phase it ends at**. The staged rows
count edits and sweeps; the per-phase checks (§3d) add a few minutes to them.

**Merging every phase into one (§8) is no faster than stages and worse at everything
else** — and it makes the agent tier unusable: a million-token change, a recorded patch
that breaks on 62% of one-line upstream edits, and a goal-document section for the
wrong task.

**No phase program's edits were changed to get there.** The whole gain is in when the
sweep runs and how it computes. That is the first recommendation (§7): take it
before considering anything that moves a phase.

## 1. What the pass costs, and where it goes

**A cold sequential whim pass takes 83 min 12 s** — `make whim-repass` from an empty
cache, in the lab worktree, ending at `whim-vim.c` `5c481861f7f0` with all 83
boundaries matching. That is the number that matters: a new `slim-vim.c` changes
phase 0's input, nothing can be speculated, and every phase runs in sequence.
(`make whim-verify` takes four minutes only because it runs every phase on the
*recorded* boundary before it. It checks a pass; it cannot perform one.)

**The sweep is the pass.** Profiled phase by phase, sequentially:

| phase | wall | `sweep.sh` | its own edits | checks and delta |
| --- | --- | --- | --- | --- |
| 48 `:noswapfile` | 29 s | 24.6 s | 2.0 s | ~2 s |
| 65 rot13 … | 26 s | 20.7 s | 3.5 s | ~2 s |
| 29 `:command` | 42 s | 38.1 s | 0.6 s | ~3 s |
| 81 one command | 27 s | 18.0 s | 7.4 s | ~2 s |

70–90% of every phase is `tools/sweep.sh`, a fixed cost: a phase that deletes one
line pays it in full. **There are 105 sweeps in a pass** — 59 phases run one, 23 run
two, phase 0 none.

**Inside the sweep**, over all 82 phases' final sweeps (`e4`: an instrumented copy of
`sweep.sh`, 12 at a time, every output identical to its boundary) — 204 rounds, 2.5
per sweep, 2,907 s of tool time:

| tool | time | share | rounds where it changed the text |
| --- | --- | --- | --- |
| `deadsweep.py` (a full `gcc -c -O0 -Wall`) | 1,212 s | 42% | 112 of 204 |
| `canon.sh` (seven canonicalisers) | 590 s | 20% | 76 |
| `deadenums.py` (DWARF dumps) | 370 s | 13% | 26 |
| `deadfields.py` | 255 s | 9% | 12 |
| `funcreach.py` | 221 s | 8% | 35 |
| `typereach.py` | 190 s | 7% | 53 |
| `deadprotos.py` | 69 s | 2% | 41 |

Every sweep ends with a round in which nothing changes — 82 of the 204 exist only to
confirm the fixpoint.

So there are three ways to make the pass faster: **run fewer sweeps, make each one
cheaper, or run them on less text.** Measured, they are worth very different amounts,
and they are taken in that order.

## 2. Lever one: fewer sweeps

### 2a. What a sweep between two phases is for

Each `pipes/whimN.sh` was split at its **last** `tools/sweep.sh` into a *head* — its
edits, and any earlier sweep it runs — and a *tail*: the final sweep, the assertions,
the build, the probes and the delta.

- **Each head alone, then a sweep**, on the recorded boundary before it: **82 of 82
  reproduce their boundary.** The split is faithful.
- **Each adjacent pair of heads, then one sweep**: **74 of 81 reproduce the second
  boundary**, and the other seven refused rather than producing a wrong file.

The seven were then taken apart, and only **two** are about the text:

| edge | why a sweep was needed |
| --- | --- |
| 41 \| 42 | an anchor: 42 requires `buf_hide` to have exactly two mentions, and dead callers still held a third |
| 79 \| 80 | an anchor: 80 refuses while a live row still uses `ADDR_BUFFERS` |
| 29 \| 30, 68 \| 69, 69 \| 70, 72 \| 73, 74 \| 75 | **none**: the text after the first head does not compile, and **every phase program starts by compiling its input** (`tools/symbols.sh`, the symbol snapshot `phasecheck.sh` compares against at the end) |

The five compile-only edges are an artefact of where the snapshot is taken. Taken
once at the start of a stage instead of at the start of every phase, **all five
vanish** — measured: each pair, and the run 75–79, then reproduces its boundary on one
sweep. Run-level testing found one more real anchor edge inside 68–72 (72's
`ONE_WINDOW` expansion occurs 9 times instead of 3 until 68–71 are swept), and phase 82
needs a text that compiles *silently*, which only a sweep provides.

### 2b. Stages, measured end to end

`greedy.sh` is a whim pass that applies phase heads to unswept text and sweeps only
when the next head refuses — then requires the sweep to land on the recorded
boundary of the last phase applied. Sequential, no parallelism, on this machine:

**As the programs are today** (`e5`): 10 stages — `1–29`, `30–41`, `42–68`, `69`,
`70–72`, `73–74`, `75–78`, `79`, `80–81`, `82` — **2,778 s**, every stage boundary
identical to its recording.

**With the snapshot taken per stage and the sweep of §3a** (`e8`): 6 stages — `1–41`,
`42–71`, `72–78`, `79`, `80–81`, `82` — **1,945 s**, every stage boundary identical.

Now the time is almost all in the heads, not the sweeps: stage `1–41` is 815 s of
edits and a 41 s sweep. Two things make up those edits:

- **The 23 inner sweeps** some phases run between their own two cuts.
- **Edit tools working on larger, unswept text.** `cutil.blank()` is 0.3 s on a
  117,000-line file, and the fold helpers recompute it for every fold (§3c).

### 2c. The inner sweeps — and the failure the anchors cannot see

Each of the 23 phases with an inner sweep was run alone with it removed: **10 do not
need it** (12, 15, 17, 25, 35, 36, 39, 53, 55, 56) and 13 refuse without it.

**Then all ten were removed together, and the pass produced a different file.** Stage
`42–71` swept to text one option row longer than q71: `'arabic'` survived. Isolated
(`e11`): phase 53 without its inner sweep is fine alone, but phase 54 computes the
rows to cut *from the option table as it finds it*, found one row fewer, **and did not
refuse** — nothing about an under-cut looks wrong to the program doing it, and no
later phase takes the row.

This is the one real danger in regrouping, and it is a kind, not an instance:

> **A counted anchor fails loudly when its input is less swept than it expects. A
> computed set shrinks silently.**

Phases whose cut is computed from the text — "rows nothing reads", "options without a
variable", "functions whose whole body is a constant" — must see their input swept,
and that is a property to *declare* per phase, not to discover. It also makes the
recorded boundaries non-negotiable: without the byte comparison at every stage end,
`e10` would have shipped an editor with one more option.

With 53's inner sweep kept and the other nine removed (`e12`): 7 stages — `1–12`, `13–41`, `42–71`, `72–78`, `79`, `80–81`, `82` — **1,635 s**, every stage boundary identical. Phase 12 without its inner sweep costs a stage boundary before 13, and saves more than it costs.

### 2d. What it would take

The unit of the pipeline becomes the **stage**: a run of phase programs between two
sweeps.

1. **Split every phase program into edit and check.** `pipes/whimN.sh` becomes the
   head and the tail it already is. Mechanical: 82 of 82 heads reproduce.
2. **Move the symbol snapshot to the stage start**, and the check that compares
   against it to the stage end.
3. **A stage manifest**, `pipes/whim.stages`, listing each stage's phases, and **per
   phase, a declared requirement**: `swept` (its cut is computed from the text, or its
   anchors are counted against swept text), `compiles`, `silent`. The manifest is
   *checked*, not trusted: a stage boundary that does not reproduce is a failure.
4. **Boundaries at stage ends only**, keyed by the stage's input digest and the
   implhash of all its phases. `whim-verify` and `whim-specpass` run stages in
   parallel exactly as they run phases now.
5. **Checks at stage ends.** A stage's declared delta is its last phase's — the lists
   are cumulative — and each phase's own assertions and probes run there. A probe that
   must see an intermediate binary forces a stage boundary and says so in the manifest.

**As implemented (step 1 and the groundwork for 2–5).** Every `pipes/whimN.sh`, N = 1–82,
is now `pipes/whimN-edit.sh` and `pipes/whimN-check.sh`, split at its last sweep; phase 0
and every slim phase stay one file. `tools/phaserun.sh` runs a phase — edit, sweep,
check — and `memo.sh`, `verifypass.sh` and `specpass.sh` all call it; `implhash.sh`
hashes both parts plus `phaserun.sh`, `sweep.sh` and `symbols.sh`. The contract: the
check shares no shell state with the edit. A fresh state directory,
`.cache/state/qN`, carries the input's line count and **the symbol snapshot, which
the driver now takes** (item 2, at what is for now the start of a one-phase stage),
plus what an edit leaves by name: 80's prefix table `words`, 80's and 81's `old`
binary (built in the background and waited for before the edit exits), 82's include
count, removed lines and input text. The head-variable dependencies the survey found
were exactly those — `before_lines` and the snapshot in all 82, `$d`/`$pid_old` in
80–82, `REMOVED` in 80 (now read from `whim80-edit.sh`, as 81 and 82 already did),
and `silent`/`CC_CHECK`/`total` in 82, which its check redefines or reads back.
`pipes/whim.stages` is item 3's manifest, seeded from §2b–2c and from edit-only runs of
the split programs on the recorded boundaries, which named each refusal: 13
(`buf_check_timestamp` after an unswept 12), 42, 72, 79, 80 (anchors), 82 (silent). Nothing
reads it yet; boundaries are still per phase and `make whim-verify` reproduces all 83.

**As implemented (steps 3b–3e).** On branch `whim-stages`:

- *The runner.* `tools/phaserun.sh <pipeline> A-B <work>` runs a stage: the symbol
  snapshot once, every edit in order, one sweep, every check in order, then
  `whimdelta.sh --phase B` once. `tools/stages.sh` reads and checks the manifest.
  The nine inner sweeps of 2c are gone and 53's stays; 12's went too, which costs the
  boundary before 13 and nothing else, since a sweep there is a sweep either way and
  a boundary also serves caching and verification.
- *The checks.* Every non-last check was run on the recorded boundary at the end of
  e12's stages: of 75, 68 passed and 7 failed. 42 and 43 drove probes with `-c` and
  `:qall`, which 43 and 46 remove, and now use `+{command}` and `:q!` — 42's first
  two probes had been passing *vacuously* on every later binary, `-c` refused and
  the file untouched. The other five, and 80 against 81, assert what a later phase
  removes on purpose; bisected over the recorded boundaries they are `apart 42 70`,
  `60 64`, `64 66`, `72 73`, `75 78` and `80 81`, and each forces a boundary. The
  schedule became **0 | 1-12 | 13-41 | 42-63 | 64-65 | 66-71 | 72 | 73-77 | 78 | 79 |
  80 | 81 | 82** — five sweeps more than e12, and every check passes at its stage end.
- *What a check proves now, and where it moved.* The delta was checked 82 times,
  each phase its own list; it is checked at the 12 stage ends, the last phase's list,
  and `orphanopts.py` with it — so a transient difference inside a stage (`:recover`
  differed at 7–10 and not at 11) is no longer observed, though it is still declared
  in `pipes/whim.delta`. Symbols are compared with the stage's start, so "this phase
  must lower the count" (8, 12) means the stage must. Every other assertion, build and
  probe of a non-last phase runs unchanged on the stage's end: it proves the property
  of the stage's result rather than of that phase's, and the attribution to one phase
  inside a stage is what is given up. The six `apart` checks run on a boundary before
  the phase that invalidates them, as they must.
- *Boundaries and targets.* `memo.sh` keys a unit by (unit, the boundary before it,
  `implhash.sh` of every phase in it) — for a single phase the key it always had, so
  slim is untouched. `whim.mk` builds its chain from the manifest; `whim-phase-N`
  re-runs the stage containing N, `whim-replay-N` refuses a phase that is not a stage
  end, `whim-tip`, `whim-times` and `whim-record` work per stage, `whim-verify` and
  `whim-specpass` run stages in parallel. A failed stage runs its phases one at a time
  through `memo.sh` before anything reaches tier 1.
- *The edit cache (3d).* Each edit's result inside a stage is cached by the tree it is
  handed and its own implementation digest; on stage 42-63 (587 s cold) a harmless
  change to 50's edit ran one edit of 22 and the stage took 94 s; on 73-77, 45 s
  against 57.
- *The delta (3e).* `pipes/whim.delta`, one line per phase that changes the list;
  the computed lists equal the 82 written-out ones exactly (the three strings
  `whimdelta.sh` compares, for every phase), and phase 80's 489-word table cut is read
  from there instead of being a second copy.

Measured: `make whim-verify` reproduces all 13 units in 597 s wall (1,653 s of
stages); a cold `make whim-repass` from an empty cache takes **26 min 27 s** — against 83 min 12 s
per phase before any of this and 61 min 33 s after steps 1–2 — and every one of the 13
boundaries matches its recording, `whim-vim.c` `5c481861f7f0`. Stages 42-63 (587 s) and
13-41 (477 s) are two thirds of it, almost all edits.  After it, `make whim-verify` again: 13 of 13 in
600 s; and from an empty cache `make whim-specpass`: 13 units speculated in 599 s, then
13 of 13 tier-3 hits, 610 s in all.

**What it costs.** `whim-tip` re-runs a stage's edits instead of one phase's — seconds,
and the same one sweep. When a stage fails, the phase at fault is found by bisecting
the stage, which is `whim-verify` run on sub-stages. The tier-3 cache holds 7 entries
instead of 83. None of that is wall time.

## 3. Lever two: a cheaper sweep, with every boundary unchanged

These change how the sweep reaches its fixpoint and nothing about which one. The
existing recordings are the proof and `make whim-verify` is the check; no phase
program is touched. They help the staged pipeline and today's alike.

### 3a. Warnings without machine code — measured, −24% of sweep time

`deadsweep.py` needs `-Wunused-function` and file-scope `-Wunused-variable`, which
come from gcc's call graph; `-fsyntax-only` reports neither (measured). **`-flto
-fno-fat-lto-objects` does**: gcc builds the call graph, warns, and stops before
generating code. On the phase-32 input (129,322 lines) the warnings are byte-identical
— 42 lines, same hash — in 2.4 s instead of 6.0 s.

The full compile also produced the object `phasecheck.sh` runs `nm` over. That object
already exists: the sweep builds a plain `-O0` object of each round's text in the
background, for `phasebuild.sh` to link, and symbol names do not depend on warning
flags. So `phasecheck.sh` takes `build.o` when its sha matches.

Measured (`e6`, the same 82 sweeps at the same parallelism as `e4`): **all 82 outputs
identical**; `deadsweep` 1,212 → 520 s; total 2,907 → 2,196 s. Two small edits: a flag
list in `deadsweep.py`, a file name in `phasecheck.sh`.

**Done, on branch `whim-sweep`** (`phasecheck.sh` requires both `build.sha` and
`last.sha` to match, else compiles as before). Re-measured back to back with the
unchanged tools, the same 82 sweeps at 12: 2,864 → 2,228 s (−22%), `deadsweep`
1,186 → 528 s, 265 → 214 s wall; all 82 identical and all 83 boundaries reproduce
under `make whim-verify`, as do slim's 12 (Phase 8 calls `deadsweep.py` too).

### 3b. Do not re-run a tool on text it has already passed — simulated, −13%

Replaying the `e4` trace: skipping a tool whose last run was clean on the identical text
saves 9%; treating `canon.sh`'s changes as invisible to the six analyses (it only moves
layout, they only read tokens) saves 13%. It overlaps with 3a and cannot touch
`deadsweep`, which runs first in every round. Not yet run.

**Done with the plain rule only, on branch `whim-sweep`.** The canon rule was not
taken: `brace.py`, `onedecl.py` and `forcomma.py` change tokens, and the textual
tools read lines, so a sweep ending on it would end on text some tool never saw.
Measured after 3a, back to back: 182 of 1,428 tool runs skipped, 2,228 → 1,935 s
(−13%), 214 → 196 s wall; 2,864 → 1,935 s (−32%) for 3a and 3b together. All 82
identical, all 83 boundaries reproduce. The `blank()`/`depths()` cache of 3c is in
too: ten `find_definition` calls on one 127,000-line text, 6.2 → 0.6 s.

### 3c. Smaller, and not worth doing first

- **`cutil.blank()` per fold** — about 370 fold and find calls in the phase programs,
  0.3 s each on a large file. Caching the blanked text across consecutive folds of an
  unchanged text is small work; it matters more once stages make the texts larger.
- **A Python replacement for `deadsweep`'s compile** — 3a takes most of its cost, and
  it would have to match gcc's notion of "unused" exactly or the fixpoint moves.
- **Parallel analyses** — six mutators applied in sequence; making them
  analyse-then-apply is a rewrite for about two seconds a round.

### 3d. The checks

`whimdelta.sh`, `phasecheck.sh`, the build and each phase's probes are 2–3 s a phase,
and 10–25 s for the few that compare a before and an after binary (80, 81, 82) — about
five minutes across a pass. At stage ends, the delta runs seven times instead of 83. Two
maintenance fixes belong here too: the cumulative delta argument list is copied into
all 83 programs and grows by a phase each time (one `pipes/whim.delta` would replace
it), and the before/after probes rebuild the input binary each time, which a stage
boundary can provide once. **The first is done:** `pipes/whim.delta`, checked once per
stage (§2d); the second is not.

## 4. Lever three: less text per sweep — reordering

Sweep cost scales with file size, so the sum of lines swept is the cost model:
**10.44 M line-phases in today's order.** Sorting all 83 cuts largest-first — ignoring
every dependency, so a bound that cannot be reached — gives 8.66 M, **17% less**.

**With stages this nearly disappears**, because only seven texts are ever swept at a stage end. It is
worth doing only as part of a regrouping undertaken for other reasons (§5), never on
its own.

## 5. Packages: the pipeline as it could read

The order is the order the work was done in, and it shows. One concept is cut in many
places:

| concept | phases today |
| --- | --- |
| windows and tab pages | 36, 39, 40, 61, 68, 72, 73, 78 |
| buffers | 41, 42, 62, 71, 77 |
| the argument list | 38, 43, 45, 69 |
| shell and filters | 6, 8, 44, 56, 60 |
| encodings and file formats | 9, 12, 15, 17, 50, 51, 52, 53 |
| swap, memfile, recovery | 11, 21, 48, 70 |
| scripts and autocommands | 29, 34, 35, 37, 75 |
| mouse | 24, 67 |
| regexp | 5, 27, 76 |
| completion | 32, 59 |
| options, generically | 2, 16, 49, 54, 55, 57, 58, 64 |
| tags, jumps, marks | 10, 30, 63, 74 |
| consolidation | 33, 78, 79, 80, 81, 82 |

A package would drop a concept whole: its command-line flags, Ex commands, keys,
options and events, and the functions, variables, types and constants behind them —
the last mostly by the sweep.

### 5a. Layers or packages

Ordering by entry point — command-line options, then Ex commands, then keys, then
options, then whatever falls out — is **a layering**; a package is **a slicing by
concept**. The right shape is packages, each layered inside.

A feature dies when its **last** entry point goes, and one concept's entry points sit
in every layer. A window is created by `:split`, by `CTRL-W s`, by `-o`, and
internally by the autocommand window `aucmd_prepbuf()` opens. Remove every Ex command
first and no window code dies, because the keys still reach it; remove the keys and
none dies either, because the autocommand window does. **Only the last layer to touch
a concept frees anything**, so a pure layering carries every concept's code the
longest.

### 5b. "Falls out by itself" is half true

It is true of **unreachable** code: once the last entry point goes, the sweep takes
the rest without judgement. It is not true of **reachable, useless** code — phases 68,
71–73, 78 and 79, 5,083 lines: one window, one buffer, one frame structurally, empty
functions, constant predicates. The compiler sees every one of those called. No sweep
finds them and no order makes them fall out, so each package has two parts: *cut the
entry points* (sweep), then *fold what became constant* (sweep).

### 5c. Dependencies

Three kinds force the order, and the measurements above found instances of each:

1. **Entry points** — the window structure needs the autocommand window gone, so
   scripts and autocommands come before windows; one buffer needs one window and no
   argument list.
2. **Swept text** — counted anchors (41|42, 79|80, 72 after 68–71) and computed sets
   (54 after 53's second cut), the second kind silent.
3. **Postconditions** — "it compiles" (after 78; the five artefact edges), "it
   compiles silently" (82).

A proposed order that respects the known ones:

1. **consolidation that simplifies everything after it** — strip comments, the
   shortest-abbreviation command table, one line one command (today 80–82). None
   depends on a cut, and done first, no later anchor can match a comment and later
   command removals can **delete** table rows instead of pointing them at `ex_ni` and
   cleaning up at the end;
2. **environment and startup** (0–4, 9, 18–20, 23, 26, 43);
3. **regexp** (5, 27, 76) — the largest cut, so early;
4. **completion** (32, 59) — the second and third largest;
5. **scripts and autocommands** (29, 34, 35, 37, 75);
6. **files, directories, shell and filters** (6–8, 13, 14, 22, 25, 31, 44, 56, 60);
7. **encodings and file formats** (12, 15, 17, 50–53);
8. **swap, memfile, recovery** (11, 21, 48, 70);
9. **windows and tab pages** (24, 36, 39, 40, 61, 67, 68, 72, 73);
10. **buffers and the argument list** (38, 41, 42, 45–47, 62, 69, 71, 77);
11. **text operations** — indenting, lisp, formatting, motions (28, 57, 64–66);
12. **options, generically** (2, 16, 49, 54, 55, 58);
13. **tags, jumps, marks** (10, 30, 63, 74);
14. **the folds no package owns** — empty functions, constant predicates, system
    headers (78, 79, 82's headers).

This is derived from phase titles and the dependencies above. It has not been run.

### 5d. Implemented as virtual packages

**Built as a view, not a reordering.** `pipes/whim.stages` now carries 18 `package`
lines covering phases 0–82 once each, and **50 `uses` lines**, each a phase relying on
a phase of another package having run — 37 *mechanical* (without it the later phase
fails or cuts wrongly) and 13 *rationale* (it is the stated reason the cut is right)
— with the reason a phase program or
`WHIM-GOAL.md` states — checked against the program that did the work, not taken from
titles. `tools/packages.sh whim` prints them and `--check` refuses a phase in no
package or two, an unknown kind and a dependency that runs after its dependent, and
`make whim-verify` and `make whim-tip` run it first; `WHIM-GOAL.md`'s
*Concept index* lists every package with its phases, titles, stages and dependencies.
No phase, boundary or cache key moved: the tool is separate from `tools/stages.sh`
because `tools/phaserun.sh` names that script, which puts it in every stage's key.

The assignment differs from the table above where the programs say so: 44 (six of
seven rows are `:sort`, `:retab` and alignment) is `text`; 70 (`:e` reuses the one
buffer) is `buffers`; 19, 24, 61 and 67 are one `terminal` package; 33, 37, 47, 80 and
81 are `commands`; 78, 79 and 82 are `tidy`; 34 and 58 are `mappings`. Two dependencies
that looked likely did not survive reading: 76's orphan `p_re` comes from
phase 5 inside `regexp`, and nothing shows 27 relying on the UTF-8-only phases.

What the recorded dependencies say about the order proposed in §5c:

- **Two pairs of packages depend on each other**, so neither pair can run as two whole
  packages in either order without splitting one: `environment` and `swap` (26's
  signal handlers relied on 11 and 21 emptying `ml_sync_all()` and `preserve_exit()`;
  21 dropped the clock time because 20 took the zone), and `options` and `text` (60's
  `'formatprg'` went because 44 made `:!` `ex_ni`; 64's `=` operator went because 60
  took `'equalprg'`, 65's `g@` because 55 took `'operatorfunc'`).
- **Three steps of the proposed order are contradicted**: consolidation first (80's
  length field was freed by 79's fold, and its anchor needs 79's dead rows swept);
  completion before files and tags (32 relied on 7 and 10 having taken its sources);
  and text before options (64 and 65, above).
- **Two are confirmed**: scripts before windows (68's autocommand window went because
  35 made dispatch `return FALSE`), and windows before buffers (45, 46 and 77 rely on
  39).
- **`regexp`, `terminal`, `mappings` and `seed` rely on no other package**, and `tidy`
  relies on six — phase 79's step 1 asserts 28 constant bodies, eleven phases' work among them.
- **The computed cut is the one to watch**: `options` 54 relies on `encodings` 53's
  second cut being swept, and without it cut one row too few and did not refuse. A
  reordering would move exactly that kind of edge silently.

The `uses` lines are the dependencies a program or section *states*. They are not all
of them: every counted anchor also depends on the text every earlier phase left.

## 6. The honest cost of regrouping

Stages keep every program's anchors valid, because no program sees a text it was not
written for — the stage boundaries *are* recorded boundaries. **Moving a phase does
not.** Every anchor was counted against one predecessor text, and 83 programs, most
several hundred lines, would have their counts re-established against new ones. And
§2c shows what makes that dangerous rather than merely laborious: a computed cut on the
wrong text does not refuse.

What makes it tractable is the fixed endpoint. A moved phase that still lands on the
recorded `whim-vim.c` is proven whatever its intermediate boundaries; a moved phase
that refuses names its anchor; a moved phase that under-cuts is caught at the end.
But the end is the only check left for everything that moved, and a divergence found
there has to be bisected across everything that moved.

By the cost model it buys at most 17% on a pass that stages have already made mostly
edits. **The case for packages is modularity** — finding "everything this editor lost
about windows" in one place — **not wall time.**

## 7. Recommendation

In order, each verified before the next:

1. **§3a now.** Two small edits, −24% of every sweep, all 83 boundaries unchanged;
   `make whim-verify` is the proof.
2. **Stages (§2d).** Edit/check split, the snapshot per stage, a manifest with declared
   requirements, boundaries at stage ends. Measured at 27 min against 83, with every
   stage boundary one of today's recordings — so nothing already recorded is lost.
   **Done** (§2d, *As implemented*): twelve stages once the checks were counted,
   a cold pass of 26 min 27 s with every check run, and every stage boundary one of
   the recordings.
3. **§3b and the `blank()` cache**, measured the same way.
4. **Packages (§5), separately, and only for modularity.** If done, one package at a
   time: move its phases, require the recorded endpoint and the stage boundaries it
   still shares with today, bisect on failure. Never as a rewrite.
   **Done as a view only** (§5d): 18 packages and 50 substantiated cross-package
   dependencies in the manifest, checked by `tools/packages.sh`, indexed in
   `WHIM-GOAL.md`, with no phase moved. Moving phases is still not done, and two
   package pairs now known to depend on each other say it would take splitting first.

**Keeping the current phase programs is the right call for now.** They are ad hoc in
their order, but they are proven, and nearly all of them refuse loudly when their
input moves. What is wasteful is the schedule around them — 105 sweeps where 21
suffice — and that can be fixed without moving a single phase.

## 8. The extreme: every phase in one

### The construction

The lab's `mono.sh` was the whole whim pipeline as **one phase program**: one
symbol snapshot, the heads of phases 1–81 in order — each in a subshell of its own,
so their variables and traps cannot meet — a sweep only where the staged schedule of
§2c needs one (after 12, 41, 71, 78, 79 and 81), and then phase 82 whole, so its
sweep, its checks and the cumulative delta run once at the end. 9,391 lines; 21
sweeps, of which 14 are inner sweeps still inside the heads.

In the lab worktree it replaces `pipes/whim1.sh`, `WHIMPHASES` is `0 1`, and the
lab's recorded `q1` is today's final boundary, so the oracle itself is the check.

### What it does

| | today | one phase |
| --- | --- | --- |
| cold pass (`make whim-repass`, sequential) | 83 min 12 s | **29 min 41 s** |
| result | `5c481861f7f0` | `5c481861f7f0`, oracle `q1 matches e8c7db4443b3` |
| warm pass (tier 3) | ~1 s | 0.4 s |
| edit one line of one phase's program | that phase onwards; earlier phases cached | **every phase**: the key of the only phase moves, 30 min |
| `make whim-verify` (checks every boundary) | 4 min, 64 jobs at once | **30 min**: one job, nothing to parallelise |
| `make whim-specpass` | runs every phase at once | nothing to speculate on |
| a failure in what was phase 60 | reported as phase 60, after ~1 min of it | reported as "phase 1", after ~20 min, input restored, all of it discarded |
| declared delta | checked 83 times, each phase's own | checked once, cumulative; no phase owns a line of it |
| boundaries an agent-recorded patch can lean on | 83 | 1 |

**The wall time is the staged pipeline's**, not better: 29 min 41 s with the final
checks, against 27 min 15 s for seven stages without theirs. Merging programs buys
nothing the sweep schedule did not already buy — **the gain was never in the number of
phases, only in the number of sweeps.** Everything else in the table got worse.

### When the agent tier must kick in

`memo.sh` falls through to tier 1 when a program fails, runs `tools/agentphase.sh`, and
then `tools/synth.sh` records the difference between the input and the agent's output
as `tools/patches/<pipeline><N>-residue.patch` — the patch that becomes the phase's
fast path until someone replaces it with rules. For one merged phase, measured:

**The task no longer fits.** The input is `slim-vim.c`, 5,064,965 bytes. The true
change — `git diff --diff-algorithm=histogram` from q0 to the final boundary — is
**3,584,824 bytes: 114,379 patch lines in 1,516 hunks**, 96,861 lines removed and
2,631 added. At three to four bytes a token that is about a million tokens of change
over roughly 1.3–1.7 million tokens of input: more than a whole context window before
the agent has read one instruction. The instructions themselves are all of
WHIM-GOAL.md, 267,505 bytes, another 65–90 thousand tokens. The largest single phase
today, 5 (the NFA engine), is 523 KB of patch, and the median phase **27 KB** — a
change an agent can hold, read, and reason about whole.

**The agent would be told the wrong task.** `agentphase.sh` gives the agent the
section `## Phase <N>` of the goal document. For the merged phase that is `## Phase 1
— no $VIMRUNTIME`: 2,013 bytes, one of 82 tasks. It would do phase 1 faithfully, the
harness would record the result as the whole pass, and `synth.sh` would write it down
as the fast path. (The prompt also still describes the slim pipeline — `SLIM-GOAL.md`,
`upstream/`, `make -C upstream` — whatever pipeline calls it; a whim agent today is
misoriented at every granularity.)

**The residue would be larger than the change.** `synth.sh` diffs with plain `diff
-ruN`, and over a distance this long plain diff loses its alignment: the recorded
patch would be **7,045,434 bytes, 231,503 lines, claiming 53,859 added lines** in a
pass that adds almost none — bigger than all 82 per-phase patches together (4.3 MB),
and nearly twice the true change.

**And as a fast path it would almost never apply.** Every line of the final text was
traced back through all 82 phases to its line in `slim-vim.c`, and each phase charged
with the lines it changes and three of context either side — what `patch` needs to
apply a hunk. Then upstream was simulated moving:

| upstream moves by | the one merged patch breaks | per-phase patches broken, of 82 |
| --- | --- | --- |
| one line, anywhere | **62%** of the time | 0.7 on average (at most 9) |
| 5 lines in 3 places | **96%** | 2.4 |
| 10 lines in 10 places | **100%** | 8.4 |

61% of `slim-vim.c` sits inside or beside some phase's change. For a patch per phase
that is spread across 82 patches, and an ordinary upstream move breaks one or two of
them — each a 27 KB problem for an agent. For one patch it is concentrated, and the
same move breaks the whole pass every time: a million-token problem, every time
upstream moves, forever.

**Reconsolidating it into a program would be the whole project again.** `repair.sh`
hands an agent a failing phase, its error and the previous agent's account, and asks it
to fix the *program* — preferring rules to constants. For one phase that is a 9,391-line
program whose failure is somewhere in 82 concatenated concerns, with one boundary to
bisect against. The work that turned each phase's recording into rules — the residue
scoreboard of `CLAUDE.md`, 33,670 lines of phase 9 down to 134 — was possible because
each phase was one idea small enough to understand. Merged, "the residue" is the pass.

### Conclusions

1. **The unit of the sweep and the unit of understanding are different, and the
   pipeline conflates them.** Wall time wants few sweeps. Caching, parallel
   verification, diagnosis, declared deltas, agent fallback and patch robustness all
   want small phases. Nothing forces the two to be the same unit.
2. **So keep the phase, and move the sweep.** The staged design of §2d is exactly that:
   phases remain the programs, the declared deltas, the agent's task and the unit
   `synth.sh` records; stages decide only where the fixed cost of a sweep is paid. It
   has the one-phase pipeline's wall time and today's everything else.
3. **One refinement the experiment suggests.** Within a stage, cache each phase's
   *unswept* output keyed like any boundary. Editing phase 50 then re-runs heads
   50–71 and one sweep, not the whole stage — the development loop keeps its per-phase
   cost even though the sweep does not.
4. **Before any agent runs on whim again, `agentphase.sh` needs a whim prompt.** That
   is true at today's granularity, and the merged experiment only made it impossible to
   miss.

## Appendix: how the measurements were taken

The lab no longer exists: it was deleted once the staged pipeline merged, and it was
never tracked. What it was, so a measurement can be repeated from scratch:

- **A baseline worktree** — `git worktree add --detach` at `4683ba3`, with
  `.reference/baselines` linked and `.reference/whim-phases` copied. `make
  whim-repass` there was the 83 min 12 s baseline.
- **Heads** — every `pipes/whimN.sh` of `4683ba3` cut at its last `tools/sweep.sh`
  line. Variants: without the per-phase `tools/symbols.sh` snapshot; without every
  inner sweep; without only the nine inner sweeps that proved safe. The staged
  pipeline's `pipes/whimN-edit.sh` are the committed descendants of the first variant.
- **Trials** — heads of a run of phases applied in order to the recorded boundary
  before the first, one sweep, and a byte comparison with the recorded boundary after
  the last: singles and pairs (`e2`), runs (`e3`), runs without the snapshot (`e7`),
  inner sweeps one at a time (`e9`), the `'arabic'` isolation (`e11`).
- **Sweep profiles** — each phase's final sweep re-run on its saved pre-sweep text
  with every tool timed (`e4`), and again with §3a (`e6`).
- **Greedy staged passes** — heads applied to unswept text, sweeping only when the
  next head refuses (`e5`, `e8`, `e10` the divergent one, `e12`).
- **The one-phase experiment** — every head concatenated into one program installed
  as the only whim phase of the baseline worktree (`WHIMPHASES = 0 1`); and the
  per-phase and whole-pass patches with the origin-tracing simulation (§8).

The session that produced this document holds the scripts in full.
