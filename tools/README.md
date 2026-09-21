# tools/

The harnesses that check `slim-vim.c` and the passes that keep it in shape. They
lived in a session scratchpad through the run, which is why `CLAUDE.md` used to
name things that were not in the repository; they are here now.

Everything takes paths on the command line and **does nothing at import time**.
That rule is not stylistic: a helper module whose top level read `sys.argv` and
rewrote the source once made an importing pass report "0 changed" when what had
actually happened was an import crash.

**The whim and zero pipelines, and the Go toolset they run, are not here.** They
grew up in this repository and moved to
[arbace/go-whim](https://github.com/arbace/go-whim), which takes `slim-vim.c` as
its input. Some of the history below still names their tools; those files live
there now, as Go.

## The shared library

- **`cutil.py`** — blank literals preserving offsets, blank comments only (a
  different thing), match braces and parens, per-character nesting depth, split
  on a top-level operator, collapse whitespace by walking the *real* string,
  find and delete a function by name, run a whole-file pass as one linear scan.

## Checking

- **`behaviour.py`** — 67 independent editing cases, run at once.
  `behaviour.py <binary> <outdir>`.
- **`exsweep.py`** — dispatch all 600 Ex command names, each in its own scratch
  directory and its own session, all at once, with the rows written in table
  order so the recording is the same bytes it was when they ran in sequence.
- **`ptyrun.py`**, **`ptycheck.py`** — drive a real terminal; the second records
  a fixed set of scenarios. `ptyrun.py` holds **`stage()`**: **a harness that copies
  the binary it is about to exec must copy it once per binary, under a lock, in a
  child process**, because `copy2` in one thread and a `fork` in another make
  `execve` fail with `Text file busy` — 5 of 100 idle runs of `termcheck.py` before,
  0 of 100 after.
- **`termcheck.py`** — what each `$TERM` resolves to and how many colours it
  gets, for every name in the table and every name dropped from it. An empty
  answer is retried at a longer settle before it is believed: under the load of
  a full `verify.sh` the screen is sometimes not drawn yet, and that is a slow
  terminal, not a missing one.
- **`create_cmdidxs.py`** — regenerate the command lookup table; `--check`
  verifies it in place. Also the canary for anything that reshapes the table.
- **`verify.sh <baselines-dir>`** — every check above, run concurrently, one
  verdict, about 18 s. Proven to fail on a broken build, a behaviour change
  and a disturbed command table. The baselines live in `.reference/baselines`,
  which is gitignored: `tools/verify.sh .reference/baselines --enums`.
- **`build.sh`** — the reproducible build tier 1 needs: no `-g`, pinned
  `SOURCE_DATE_EPOCH`, and a clean first.
- **`refcheck.sh [reference-dir]`** — the end-of-pass comparison against
  `.reference/`: source, binary (tier 1), baselines present. Exits
  non-zero on a source or binary difference. A missing reference directory is
  reported and exits 0 — a first pass has nothing to compare against.
- **`tier2.py`** — compare two preprocessed files as **token** streams.
- **`enumvals.sh`** — dump every enumerator and its value from DWARF.

## Shape

Each of these is **idempotent and currently a no-op**, which makes running it a
check rather than a change. Run them after anything that rewrites code in bulk:
bracing once ran before macro expansion, expansion pasted in `for` headers of
its own, and 1,558 unsplit bodies sat in the file through two runs because
nothing re-ran the pass that would have found them.

`untab.py` · `splitheads.py` · `brace.py` · `joinparens.py` · `onestmt.py` ·
`onedecl.py` · `undowhile.py`

`canon.sh`'s own seven are a different set, in a fixed order that matters:
`blankruns` · `joinparens` · `splitheads` · `brace` · `onestmt` · `onedecl` ·
`forcomma`. `untab.py` is in no loop and `undowhile.py` is `pipes/slim9.sh`'s. Of the two
this list omits, `forcomma` is a no-op on `slim-vim.c` and **`blankruns` is
not** — it collapses the one run of two blank lines the file has, at line
41,078. So "each of these is currently a no-op" is true of the seven named above
and is not true of every canonicaliser.

`decomment.py` is the same kind of pass but is *not* a no-op — it would take
the 245 banners with it. It is here for the rule it enforces, which nothing
else records: a comment becomes one space **plus the newlines it spanned**, and
it refuses outright if any multi-line comment has code on both sides.

## The three-tier memoize

`slim.mk` sequences the twelve phases; these implement the memoize described in
`CLAUDE.md` and `README.md`. None of them knows anything about the phases
themselves.

- **`memo.sh <unit> <work> <build> [pipeline]`** — the driver. A unit is a phase
  `N`. Tier 3 (a cached result for this exact unit, input and
  implementation), else tier 2 (the unit's programs, run through `phaserun.sh`),
  else tier 1 (an agent) — and an agent run always leaves a tier 2 behind, so the
  same input never costs an agent twice.
- **`stages.sh <pipeline> [--of N | --check]`** — the units a pipeline runs in: read
  from `pipes/<pipeline>.stages` when there is one, and slim has none, so one unit
  per phase.
- **`phaserun.sh <pipeline> <phase> <work>`** — runs a phase's program,
  `pipes/<pipeline><n>.sh`. `--parts` lists it, and is how `memo.sh`,
  `implhash.sh`, `residue.sh` and `stages.sh` ask whether a phase is a program.
- **`implhash.sh <phase> [pipeline]`** — half the cache key: the phase's program
  plus every tool, patch, table and template it names, one level of indirection
  deep. Narrow on purpose, so editing `resolve.py` re-runs phase 5 and not all
  twelve.
- **`synth.sh <n> <build>`** — memoize an agent's *behaviour* as code: diff the
  two boundaries, write `patches/p<n>-residue.patch`, and write a
  `phase<n>.sh` that applies it if the phase had none.
- **`phasename.sh <n>`** — what a phase is called, read out of `SLIM-GOAL.md`'s
  headings, so the progress log and the document cannot disagree.
- **`residue.sh`** — the scoreboard. How much of each phase is still a recorded
  diff rather than a rule, which is the number to drive down.
- **`repair.sh`** — after the fast path failed and the agent succeeded: fix the
  *program*, not the symptom, and say plainly when a change genuinely needs
  judgement.
- **`preflight.sh`** — what a pass needs on this machine, asked before the
  clone rather than ten minutes in: the GNU userland the phase programs assume
  (`sed -i`, `mv -t`, `nm --defined-only`), the toolchain, and — only if some
  phase still lacks a program — a `claude` that can actually authenticate.
- **`agentphase.sh <n> <work> [pipeline]`** — one `claude -p` scoped to a single
  phase, handed the tree at that phase's input and forbidden everything outside it.
  The prompt is assembled invariant-first, phase-text-last, so the phase agents of a
  pipeline share one cached prefix.
- **`agentdocs.sh`** — the document update, run only when `slim-vim.c` actually
  changed. A pass that reproduced the previous one made no sentence wrong.
- **`snapshot.sh`**, **`restore.sh`** — a boundary is a tar (the restore point,
  everything) plus a content digest (the meaning: sources, no `objects/`, no
  `config.log`, which carries a timestamp and would make no boundary ever equal
  itself twice).
- **`oracle.sh <n>`** — compare a boundary against the recorded one. An
  agent-recorded boundary is *advisory* and a mismatch is a report; a boundary
  promoted after an end-to-end verified run is a *check* and a mismatch is a
  failure.
- **`pipeline.sh slim`** — sourced, never run: the pipeline's tag, work and build
  directories, source, document and phase list.
- **`verifypass.sh slim [unit...]`** — every recorded boundary checked at once.
  Each phase runs on the recorded boundary before it, in a scratch root of its own
  with a snapshot of `tools/` and `pipes/` and a `.cache/` nobody else writes, and
  must reproduce the boundary it recorded: by induction the same proof as a repass
  from an empty cache, in the wall time of the slowest phase. `make slim-verify`;
  `JOBS=n` to run fewer at once.

## Phases that are programs

They live in `pipes/`, not here: `pipes/slim<N>.sh`, one file per phase. Everything
below them in this directory is what they call. The slim ones that replaced an agent are described here. Each was written by diffing the two boundaries the agent left — `p2.tar`
against `p3.tar` says exactly what Phase 3 did, with no prose in between — and
each reproduces that boundary byte for byte.

- **`pipes/slim0.sh`** — configure, build, delete the asserts, rebuild, and check
  the harness disagrees with the baselines in exactly the six cases Phase 1
  owns. **33 s against 2 m 57 s.** Uses `dropasserts.py`.
- **`pipes/slim1.sh`** — apply `patches/slim1.patch`, delete the configure
  machinery, rebuild, and run all four harnesses against the baselines. **17 s
  against 17 m 16 s.** This is the phase that changes behaviour, so it is also
  the phase that pins it.
- **`pipes/slim2.sh`** — prune to what the compiler opens, and flatten. **5 s against
  7 m 13 s.** Both deletions are *computed*: a source whose object defines no
  symbols compiles to nothing (61 of 128), and a file the `-MD` dependency
  files never name was never opened. Installs `templates/pruned.mk` rather than
  operating on upstream's makefile.
- **`pipes/slim3.sh`** — unwrap `HAVE_CONFIG_H`, name the 97 `.pro` includes by
  path, point `xdiff.h` at `vim.h`, install the makefile, drop `config.mk`.
  **1 s against 7 m 02 s.** Uses `unwrapif.py` and `templates/upstream.mk`.
- **`pipes/slim4.sh`** — splice, untab, decomment, and require the blank-line count
  not to move. **63 s against 5 m 41 s.**
- **`pipes/slim5.sh`** — plant, tally, resolve, drop `#undef`, tier 2 across all 67
  units. **8 s against 7 m 00 s.** 8,251 conditional groups become 17.
- **`pipes/slim7.sh`** — the seven canonicalisers to a joint fixpoint, checked by
  tier 1. **39 s against 5 m 24 s.** Uses `canon.sh`.
- **`pipes/slim9.sh`** — delete, split the X-macro, convert, expand, unwrap,
  canonicalise. **34 s against 943 s**, with a 134-line residue where it began
  as a 33,670-line recording. Uses `dropmacros.py`, `xmacro9.py`,
  `gettext9.py`, `toenum.py`, `expand.py`, `undowhile.py` and `canon.sh`.

- **`dropasserts.py`** — the eight `assert()` calls and the `<assert.h>` that
  declares them, found from the **objects** (`nm -u` for `__assert_fail`),
  because a grep over the sources matches vim's own `in_assert_fails` and gets
  the count wrong.
- **`unwrapif.py`** — delete a conditional group's two directives and keep its
  body, by **matching** rather than substituting. Deleting `#ifdef
  HAVE_CONFIG_H` alone leaves its `#endif` to close `#ifndef VIM__H` three
  thousand lines early, and gcc then reports a redeclared enumerator in
  `termdefs.h`. It refuses when the group has an `#else`.
- **`canon.sh`** — the seven canonicalisers to a joint fixpoint, looping until
  the file stops changing. Stronger than running each once, and Phase 9 calls
  it too, because macro expansion re-breaks exactly what Phase 7 fixed.
- **`blankruns.py`**, **`forcomma.py`** — collapse runs of blank lines; hoist
  comma operators out of `for` init clauses, declining the ones that *declare*
  (hoisting would widen the scope) or contain a call.
- **`dropmacros.py`** — delete the `#define`s nothing mentions, in **exactly
  one round**. Iterating finds 48 more and produces a permanently different
  `slim-vim.c`, because the round count decides how many constants ever reach
  `toenum.py` — 1,444 enumerators against 1,410.
- **`xmacro9.py`** — `ex_cmds.h` is inlined twice with `EXCMD` meaning two
  different things either side of an `#undef`, and an expander keyed by name
  takes the second body for both — which puts 600 struct initialisers inside
  `enum CMD_index`. It splits the two definitions by their `#undef` region,
  rewrites the row body as a designated initialiser, and adds the
  `static_assert` that catches a dropped last row.
- **`gettext9.py`** — `_()` and `NGETTEXT` become inline functions rather than
  being expanded, because `format_arg` is what keeps `-Wformat`,
  `-Wformat-security` and `-Wformat-nonliteral` seeing through them. Expanding
  them builds cleanly and loses the diagnostics silently, so the check is that
  the warning set is unchanged.
- **`undefs.py`** + **`renames.txt`** — remove `#undef`, splitting any macro
  that was defined twice into two names from the table. It refuses on an
  unlisted one rather than guessing, which is how it found `PLURAL_MSG` (two
  arms of a conditional, no `#undef` between them, nothing to do) and `EXCMD`
  (kept until the X-macro goes in Phase 9). `renames.txt` is the one place this
  process stores a decision it cannot derive.
- **`agentpass.sh`** — the whole pass by one agent, the reference path.
  `make slim-refpass`, then `make slim-compare`. Kept because the phase programs are
  brittle where an agent is not: when upstream moves under a patch, this is
  what still produces an answer, and the difference between the two answers is
  the specification for repairing the fast path.
- **`templates/pruned.mk`** — the makefile Phase 2 installs while pruning. It
  takes an explicit `SRC` from `srcs.mk`, because not every `.c` in the tree is
  a source of this build at that point and the authoritative list is the set of
  objects the previous phase's build left.
- **`templates/upstream.mk`** — the 65-line makefile Phase 3 installs into the
  staging tree, checked in rather than written each pass. It uses `$(wildcard)`
  and so bakes in no file list; keeping it as text also stops a pass rewriting
  its prose slightly differently every time, which is a boundary difference
  that means nothing and has to be explained anyway.

## Auditing

`deadsweep.py` (delete what `-Wall -Wextra` names, once, from a compile with
`-flto -fno-fat-lto-objects` that warns and generates no code — it keys on the
warning *option*, never the sentence, and deletes a variable's whole
declaration rather than its first line, because 39 file-scope tables put the
initialiser on the next one) · `typereach.py`
(type definitions nothing outside a type definition mentions) · `funcreach.py`
(functions no root reaches, islands included) · `deadprotos.py` (declarations
of functions that no longer exist) · `deadenums.py` (enumerators nothing
mentions, survivors pinned to their DWARF values, `--verify` afterwards) ·
`deadfields.py` (struct fields nothing outside a type names — refused while
`ml_recover()` exists, because a struct layout is then a disk format)

Slim's Phase 8 runs all of them but `funcreach.py`, in one loop.

## The passes a run needs

These cannot run against the *finished* `slim-vim.c` — it has no separate sources, no
directives and no macros left — and they were once deleted for exactly that
reason. Every one of them is needed by a pass, because a pass works on the tree
before those things are gone, and two had to be rewritten from memory when they
turned out to be missing. **The test is "does the process need it", not "does it
run against `slim-vim.c`".**

`keepset.py` (what the compiler opens) · `dropsrc.py` (remove a source and all
five of its mentions) · `splice.py` (translation phase 2) · `merge.py` ·
`macros.py` + `cond.py` (parse `#define`s, and conditional groups into a tree) ·
`plant.py` + `resolve.py` (conditional resolution by marker counting) ·
`toenum.py` · `expand.py` · `reblank.py` (recover paragraphing, if it is ever
lost again)

`SLIM-GOAL.md` describes what each phase uses them for; `README.md` at the root is
the front door to both.

**A tool that nothing calls is not necessarily dead, and this repository has
now watched that happen twice.** Phase 0 warns about the first form: a pass
needs `merge.py`, `plant.py` and the rest, none of which can run against the
*finished* `slim-vim.c`, and two were once deleted for looking unused and had to be
written again from memory.

The second form appeared when Phase 9 was a synthesised patch — a recording of
what an agent did, which swallowed the work `undowhile.py` and `toenum.py` used
to do, leaving both referenced by nothing. Replacing that recording with rules
brought them straight back into use, which is the clearest evidence available
that the residue really was standing in for algorithms rather than for nothing.
`reblank.py` is still waiting its turn.

The test is "does the process need it", not "does anything call it today".

Gone for good: `rename.bat`, which was **upstream's** — a Win32 build helper
that survived every pruning pass because Vim's own tree has a `tools/` too.

## Where a harness loses the reason

*Several examples here are from the whim and zero pipelines, which now live in
arbace/go-whim; the lessons are general.*

**Five things look alike in a report and are not, and they differ by WHERE the
reason went.** Four are defects and the repairs are different; the fifth is a
correct program that a document described wrongly, and a reader who lumps it in
with the others goes looking for a bug that is not there.

| what it is | where the reason goes | the repair | here |
| --- | --- | --- | --- |
| a recording harness backgrounded as `… >/dev/null 2>&1 &`, collected by a bare `wait` | discarded **before it is written** | capture it | **repaired**, in 15 zero checks, now in arbace/go-whim |
| `verifypass.sh` testing `if ! …` | collapsed to **one word** — SIGKILL, a torn script and an assertion failure all read the same | report the status, not the test | **repaired**, it takes `rc=$?` and prints it |
| a driver piping each step through `tail -12` | written and then **thrown away** | keep all of it | the other session's `clonepass.sh`, reported against itself |
| `git bundle verify` | **never computed** — it validates the header and the prerequisites and does not read the packfile | perform the recovery | external, and *Four checks that pass while doing nothing* in `CLAUDE.md` |
| `pipes/slim1.sh`'s absent-baseline `exit 0` | **nowhere** | none | a correct program; the defect was the documentation |

The first three are one sentence — **a harness that captures only the end of what
it ran cannot report the reason for anything that happened in the middle** — and
the fourth is a different failure wearing the same face, where there is no reason
to lose because nothing looked. The taxonomy is the other session's; the
`live`/`repaired` column is this tree measured rather than remembered.

**The fifth is the one worth stating separately.** `pipes/slim1.sh` prints
*"baselines absent — first pass, nothing to compare against. Record them from
this binary before Phase 2"* and exits 0. It loses nothing, computes nothing and
says precisely what it did and did not do. It is not a defective harness at all
— `CLAUDE.md` claimed a pass records the baselines, and that sentence was wrong
for as long as nothing could test it from outside a tree that had already run.
**A correct refusal and a silent pass are told apart by what the program says,
not by what a document says about it.**

**A sixth belongs beside that table on a different axis, and it was caught one
keystroke from being published as a finding.** The other session checked whether
`main`'s `bundlecheck.sh` still carried the absolute-path repair with

    grep -c 'cd "$(dirname "$f")" && pwd' tools/gocmp/bundlecheck.sh

got **0**, and nearly reported that the fix was missing — a fabricated alarm
about the one file whose entire subject is a fabricated alarm. The text is there,
at line 71.

**The cause took two wrong answers to find, and the second was published before
it was checked.** It is not shell expansion: the single quotes hold and `printf`
shows the pattern reaching the command byte for byte. It is not the BRE dialect
either, which is what this file said first — that story came from `grep -F`
matching and bare `grep` not, which was true and was not the reason. **The reason
is that the two runs were not the same program.** In an interactive Claude Code
shell `grep` is a shell *function* that dispatches to `ugrep`; a script, or
`bash -c`, or `command grep`, gets GNU grep. Measured on the same pattern and the
same file in one command:

```
function grep (ugrep)   0
command grep (GNU)      1
GNU grep -F             1
```

So the other session's in-script `1` was right all along and the `0` was an
artifact of where it was typed. **The tool you believe you are running may not be
the program that answers**, and a count is a fact about a binary as much as about
a file.

Everything this session measured with a bare `grep` was re-checked against
`command grep` for that reason; the published edit-port figures are unaffected
(0 heredocs, 31 whim files, 34 calls, 41 zero files under both), because a plain
literal pattern is where the two agree. It is the metacharacter-heavy pattern
that separates them, which is exactly the pattern somebody reaches for when
checking whether a line of shell is present.

**That is not where the reason is lost — it is a check answered by a program the
caller did not think it was running.** The other four compute an answer and mislay it; this one
computes a correct answer to a question it was never asked, and the answer is
indistinguishable from the true negative. The repair is what this tree does
everywhere else and what settled it that time: **compare the object, do not
interrogate it.** `cmp` against a known-good copy said *identical, 140 lines* in
one command and could not have been fooled by its own pattern.

**The rule, which is not about `grep`: when a count is the evidence, name the
program.** `command grep`, or `-F`, or better a `cmp`, which cares about neither
the dialect nor the `PATH`. Both sessions audited every figure they had published
from a pattern, GNU against ugrep, on the same files — line counts, directive
counts, `__DATE__` presence in all three products, the zero-heredoc check,
`\bmain\b`, the edit-part counts, the fourteen backgrounded zero checks — and
**every one agrees**. Exactly one pattern differed, the one already retracted.
The two programs part company only where the pattern is metacharacter-heavy,
which is the pattern somebody reaches for when asking whether **a line of shell**
is present, and that is the question both sessions were asking when it bit.

One figure was worth re-taking rather than re-confirming, and asking what the
difference *was* changed which number the table should quote. Fourteen zero
checks background `zrecord.sh`; a fixed-string count of the backgrounding idiom
gives **15**. Both programs agree on both numbers. The fifteenth is
`pipes/zero42-check.sh`, and it is not a different construct — it backgrounds the
recording tools directly and discards their output **five times**, at lines 500,
502, 504, 510 and 643, collecting them with the same bare `wait … || die`:

```
tools/st.sh zcases   "$tmp/probe" "$tmp/SC-probe"   >/dev/null 2>&1 &
tools/st.sh zexcmds  "$tmp/probe" … "$tmp/ex-probe.txt" >/dev/null 2>&1 &
tools/st.sh zargv    "$tmp/probe" "$tmp/argv-probe.txt" >/dev/null 2>&1 &
tools/st.sh zmemline "$tmp/probe" "$tmp/ML-in"      >/dev/null 2>&1 &
```

**And the fifteenth is the shape wearing a message that looks informative**, which
makes it the worst of them to read. Its collection is not a bare `wait` but a
`wait … || die` that names the harness:

```
wait $pid_sc || die "the screen corpus failed on the instrumented build"
wait $pid_ex || die "the Ex sweep failed on the instrumented build"
wait $pid_av || die "the argv sweep failed on the instrumented build"
wait $pid_ml || die "phase 40's memline corpus failed on the instrumented build"
```

Each says **which** and never **why**, because the why went to `/dev/null`
before the `wait` could reach it. A reader handed *the screen corpus failed on
the instrumented build* has a sentence, a phase and no reason, and will go
hunting the phase rather than the stall — so a message that names its subject is
**more** misleading here than silence, not less.

**So the two counts answer two questions and the table wanted the other one.**
`CLAUDE.md`'s sentence names `zrecord.sh`, and 14 is right for that sentence.
This table is about a *shape*, and for the shape it is **15** — fourteen through
`zrecord.sh` and one through five direct calls. A reader who repairs the fourteen
and stops leaves the same defect standing in `zero42-check.sh`, which is the
outcome the entry exists to prevent. **A disagreement between two counts is not
always two answers to one question — and when it is, the cheap check is which
question you are actually asking.**

**And the second-order point, which is the two-harness rule arriving somewhere
new: this was only findable because two sessions ran the same pattern in
different contexts and refused to average the results.** One session alone has
one number, believes it, and has nothing to reconcile. Keeping the contradiction
unexplained across three exchanges is what preserved the evidence — the tidy move
was to pick a story, and **both stories on offer were wrong**. The rule that
falls out is narrower than "get two implementations" and more useful: *an
unexplained disagreement is data; resolving it by choosing the likelier side
destroys it.*

## A verdict true of both outcomes

**The four entries above are about where a REASON is lost. There is a fifth
class that loses no reason at all**, and it was found three times in one hour by
two sessions who had each just written the other's instance down.

It computes a **true fact**, and the fact is compatible with both the success
and the failure it exists to distinguish:

| the check | the true fact | the two states it cannot separate |
| --- | --- | --- |
| `git bundle verify` on a truncated bundle | the header and prerequisites are sound | a recoverable bundle, and one whose packfile is gone |
| a watcher reporting `last rNONE of 45` | there are no boundary files | a pass that failed at once, and a scratch directory that was deleted |
| `settle.sh` reporting a product `clean` | the file does not differ from git | produced and matched, and **never produced at all** |

The third is this repository's own *a "clean rebuild is byte-identical" check
passes if the rebuild never happened*, arriving in the **report** rather than in
the build — and the second was written into a watcher by the session that had
just warned the other about the third.

**The repair is the same in all three and it is not another check.** Make the
instrument report the **state**, not the comparison. A watcher that says
*deleted* / *exited* / *still running* cannot be read as a boundary count. A
product check that says *written 05:19:33 against a boundary of 05:19:33* cannot
be read as produced when nothing produced it — `<pipe>-pass` extracts the product
from the last boundary's tar, so a product **older** than that boundary was never
copied out. A bundle check that performs the recovery cannot be satisfied by a
header. **None of the three adds an assertion; each adds a distinction the old
output could not carry.**

Applied to this tree as a check rather than as a story: `slim-vim.c` is at least
as new as p11, `whim-vim.c` as q82 and `zero-vim.c` as r45, so all three were
produced and not merely unchanged. `zero.mk`'s own product guard is the
content half of the same question and the two are worth having together —
one asks *is it the right bytes*, the other *did anything write it*.

**Four mechanisms were stated confidently in one day and the measurement
disagreed with every one.** They are worth listing together, because the list
says something the individual findings do not:

| the confident claim | what measuring it said |
| --- | --- |
| a `grep` returning 0 is shell expansion, then a BRE dialect | neither — the shell's `grep` is a function dispatching to `ugrep` |
| an `r39 FAILED` belongs to the run that just finished | it came from a different scratch that happened to be in view |
| r44's two failures are one flake with two faces | two routes — the controls' corpus holds no pty scenario at all |
| `( a; b ) &` discards `a`'s status, so one line cannot fix it | `set -eu` is inherited, the `wait` sees rc 1, and one line does fix it |

**Every one was settled by running it and none by reasoning about it, and three
of the four were caught by the other session rather than by their author.** That
ratio is the argument for two sessions rather than one careful one, and it is a
different argument from the two-harness rule above: that rule is about *coverage*
neither author chose, and this is about **a claim's author being the worst placed
person to test it** — not through carelessness, but because the reasoning that
produced the claim is the reasoning available for checking it.

The shape they share is that each confident claim was **true of something**: of a
different shell's `grep`, of a real scratch, of a real flake, of a subshell
without `set -e`. **A mechanism that fits is not a mechanism that ran**, and the
distance between them is one command.

**The fit is what makes it dangerous.** Not one of the four was a guess. Each was
a correct piece of knowledge applied to the wrong object, which is the failure
that **feels like competence while it is happening** — there is no moment of
doubt to notice, because the reasoning is sound and only its subject is wrong.
That is also why the blank output matters more than it looks: both sessions'
first attempt at the `set -e` measurement printed **nothing**, `set -e` having
killed the probe at the non-zero `wait`, and a blank where a number belongs is
the one result nobody is tempted to publish. The trap was hit twice and caught
twice by the same property — it produced no plausible answer.

**That generalises into a design rule, and it is the opposite of the usual
instinct.** The outputs that get published are the plausible ones, so **a trap
that yields no answer is self-limiting and a trap that yields a reasonable one is
not**. All four mechanisms above were the second kind: a count, a scratch, a
failure message and a shell semantics claim, each of them a sentence somebody
would repeat. The usual thing asked of a tool is that it degrade gracefully —
return something, carry on, do not make a fuss. **Every one of the four would
have been worse under that instinct**, and the instruments that served best here
were the ones that failed loudly and emptily: a probe that printed nothing, a
`cmp` that cannot be fooled by its own pattern, a `stages.sh` that refuses before
any check runs. Prefer an instrument that produces no answer to one that produces
a defensible one.

