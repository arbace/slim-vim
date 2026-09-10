# tools/

The harnesses that check `vim.c` and the passes that keep it in shape. They
lived in a session scratchpad through the run, which is why `CLAUDE.md` used to
name things that were not in the repository; they are here now.

Everything takes paths on the command line and **does nothing at import time**.
That rule is not stylistic: a helper module whose top level read `sys.argv` and
rewrote the source once made an importing pass report "0 changed" when what had
actually happened was an import crash.

## The shared library

- **`cutil.py`** — blank literals preserving offsets, blank comments only (a
  different thing), match braces and parens, per-character nesting depth, split
  on a top-level operator, collapse whitespace by walking the *real* string,
  find and delete a function by name, run a whole-file pass as one linear scan.

## Checking

- **`behaviour.py`** — 67 independent editing cases.
  `behaviour.py <binary> <outdir>`.
- **`exsweep.py`** — dispatch all 600 Ex command names, each in its own scratch
  directory and its own session.
- **`ptyrun.py`**, **`ptycheck.py`** — drive a real terminal; the second records
  a fixed set of scenarios.
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
  `.reference/`: source, binary (tier 1), documents, baselines present. Exits
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

`decomment.py` is the same kind of pass but is *not* a no-op — it would take
the 245 banners with it. It is here for the rule it enforces, which nothing
else records: a comment becomes one space **plus the newlines it spanned**, and
it refuses outright if any multi-line comment has code on both sides.

## The three-tier memoize

`pass.mk` sequences the ten phases; these implement the memoize described in
`CLAUDE.md` and `README.md`. None of them knows anything about the phases
themselves.

- **`memo.sh <n> <work> <build>`** — the driver. Tier 3 (a cached result for
  this exact input and implementation), else tier 2 (`tools/phase<n>.sh`), else
  tier 1 (an agent) — and an agent run always leaves a tier 2 behind, so the
  same input never costs an agent twice.
- **`implhash.sh <n>`** — half the cache key: the phase's program plus every
  tool, patch, table and template it names, one level of indirection deep.
  Narrow on purpose, so editing `resolve.py` re-runs phase 5 and not all ten.
- **`synth.sh <n> <build>`** — memoize an agent's *behaviour* as code: diff the
  two boundaries, write `patches/p<n>-residue.patch`, and write a
  `phase<n>.sh` that applies it if the phase had none.
- **`residue.sh`** — the scoreboard. How much of each phase is still a recorded
  diff rather than a rule, which is the number to drive down.
- **`repair.sh`** — after the fast path failed and the agent succeeded: fix the
  *program*, not the symptom, and say plainly when a change genuinely needs
  judgement.
- **`preflight.sh`** — what a pass needs on this machine, asked before the
  clone rather than ten minutes in: the GNU userland the phase programs assume
  (`sed -i`, `mv -t`, `nm --defined-only`), the toolchain, and — only if some
  phase still lacks a program — a `claude` that can actually authenticate.
- **`agentphase.sh <n> <work>`** — one `claude -p` scoped to a single phase,
  handed the tree at that phase's input and forbidden everything outside it.
  The prompt is assembled invariant-first, phase-text-last, so the ten phase
  agents share one cached prefix instead of making ten.
- **`agentdocs.sh`** — the document update, run only when `vim.c` actually
  changed. A pass that reproduced the previous one made no sentence wrong.
- **`snapshot.sh`**, **`restore.sh`** — a boundary is a tar (the restore point,
  everything) plus a content digest (the meaning: sources, no `objects/`, no
  `config.log`, which carries a timestamp and would make no boundary ever equal
  itself twice).
- **`oracle.sh <n>`** — compare a boundary against the recorded one. An
  agent-recorded boundary is *advisory* and a mismatch is a report; a boundary
  promoted after an end-to-end verified run is a *check* and a mismatch is a
  failure.

## Phases that are programs

Each was written by diffing the two boundaries the agent left — `p2.tar`
against `p3.tar` says exactly what Phase 3 did, with no prose in between — and
each reproduces that boundary byte for byte.

- **`phase0.sh`** — configure, build, delete the asserts, rebuild, and check
  the harness disagrees with the baselines in exactly the six cases Phase 1
  owns. **32 s against 2 m 57 s.** Uses `dropasserts.py`.
- **`phase1.sh`** — apply `patches/phase1.patch`, delete the configure
  machinery, rebuild, and run all four harnesses against the baselines. **18 s
  against 17 m 16 s.** This is the phase that changes behaviour, so it is also
  the phase that pins it.
- **`phase2.sh`** — prune to what the compiler opens, and flatten. **4 s against
  7 m 13 s.** Both deletions are *computed*: a source whose object defines no
  symbols compiles to nothing (61 of 128), and a file the `-MD` dependency
  files never name was never opened. Installs `templates/pruned.mk` rather than
  operating on upstream's makefile.
- **`phase3.sh`** — unwrap `HAVE_CONFIG_H`, name the 97 `.pro` includes by
  path, point `xdiff.h` at `vim.h`, install the makefile, drop `config.mk`.
  **1 s against 7 m 02 s.** Uses `unwrapif.py` and `templates/upstream.mk`.
- **`phase4.sh`** — splice, untab, decomment, and require the blank-line count
  not to move. **63 s against 5 m 41 s.**
- **`phase5.sh`** — plant, tally, resolve, drop `#undef`, tier 2 across all 67
  units. **8 s against 7 m 00 s.** 8,251 conditional groups become 17.
- **`phase7.sh`** — the seven canonicalisers to a joint fixpoint, checked by
  tier 1. **40 s against 5 m 24 s.** Uses `canon.sh`.
- **`phase9.sh`** — delete, split the X-macro, convert, expand, unwrap,
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
  `vim.c`, because the round count decides how many constants ever reach
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
  `make refpass`, then `make compare`. Kept because the phase programs are
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

`deadsweep.py` (delete what `-Wall -Wextra` names, once — it keys on the
warning *option*, never the sentence, and deletes a variable's whole
declaration rather than its first line, because 39 file-scope tables put the
initialiser on the next one) · `typereach.py`
(type definitions nothing outside a type definition mentions)

## The passes a run needs

These cannot run against the *finished* `vim.c` — it has no separate sources, no
directives and no macros left — and they were once deleted for exactly that
reason. Every one of them is needed by a pass, because a pass works on the tree
before those things are gone, and two had to be rewritten from memory when they
turned out to be missing. **The test is "does the process need it", not "does it
run against `vim.c`".**

`keepset.py` (what the compiler opens) · `dropsrc.py` (remove a source and all
five of its mentions) · `splice.py` (translation phase 2) · `merge.py` ·
`macros.py` + `cond.py` (parse `#define`s, and conditional groups into a tree) ·
`plant.py` + `resolve.py` (conditional resolution by marker counting) ·
`toenum.py` · `expand.py` · `reblank.py` (recover paragraphing, if it is ever
lost again)

`GOAL.md` describes what each phase uses them for; `README.md` at the root is
the front door to both.

**A tool that nothing calls is not necessarily dead, and this repository has
now watched that happen twice.** Phase 0 warns about the first form: a pass
needs `merge.py`, `plant.py` and the rest, none of which can run against the
*finished* `vim.c`, and two were once deleted for looking unused and had to be
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
