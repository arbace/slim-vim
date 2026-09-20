# tools/

The harnesses that check `slim-vim.c` and the passes that keep it in shape. They
lived in a session scratchpad through the run, which is why `CLAUDE.md` used to
name things that were not in the repository; they are here now.

Everything takes paths on the command line and **does nothing at import time**.
That rule is not stylistic: a helper module whose top level read `sys.argv` and
rewrote the source once made an importing pass report "0 changed" when what had
actually happened was an import crash.

## go/ — the toolset, in one binary

`tools/go/` is this toolset rewritten in Go, built into one `slimtools`
binary by **`gobuild.sh`**, which is content-keyed the way the memoize is:
the key is every `.go` file plus `go.mod`, `go.sum` and the cc/v4 patch, so
a build is skipped when nothing that decides the output has moved.

**The sweep, the canonicalisers and every whim/zero cutter are Go.**
`tools/sweep.sh` and `tools/canon.sh` are four-line wrappers onto
`slimtools`; every phase program in `pipes/` calls them by the same path
with the same arguments and cannot tell the difference. That is the whole
cutover -- 264 phase programs were not edited, and the two shell scripts
name their Go sources in comments so that **`implhash.sh` still hashes the
implementation into every phase's key**. `implhash` greps for paths and
does not know what a comment is, which is the mechanism the Python
`import` comments already use for `cutil.py` and `macros.py`.

**All 57 cutters the whim and zero pipelines use have a Go counterpart**,
in `tools/go/internal/cut/`, each compared against the Python it replaces
on a corpus of recorded boundaries, per-phase edit inputs and per-tool
inputs. The nineteen slim-only cutters are deliberately not ported: the
slim pipeline was out of scope.

**What RE2 cannot spell is the interesting part.** Go's regexp has no
lookaround of either kind, by design -- it is what buys the linear-time
guarantee -- and six cutters depend on one:

| where | the Python | what replaces it |
| --- | --- | --- |
| `nocmdargs` | `(?=[ \t]*case 'T':\n)` | match the trailing context, put it back |
| `noarglist`, `nowindows` | `^(?![ \t]*\[?CMD_)` | two tests over the lines |
| `nobackup` | `(?<=[ ,])name(?=,)` | test the bytes either side |
| `noconv` | `(?<![\w*])ptr\(` | test the preceding byte |
| `utf8only` | `(?<![=!<>])(?:...)?=(?!=)` | a hand-written scanner |
| `lfonly` | `(?=\n[ \t]*\{...)` | inline it -- the fold uses only the match's START |

A capturing rewrite is NOT equivalent in general, which is why `nobackup`
and `noconv` test bytes instead: a capture consumes its delimiters, so two
matches sharing one would lose the second.

**And two differences in the languages themselves.** Python's `re.escape`
escapes a SPACE and Go's `QuoteMeta` does not -- irrelevant to matching,
since `\ ` and a bare space are the same to a regex, but `nowinsizes`
then does `.replace(r'\ ', r'\s*')` to widen it, and without the escape
there is nothing to find. And Python's `%r` is single-quoted where Go's
`%q` is double, which is `cutil.PyRepr`.

**ORDER IS OUTPUT.** Every cutter prints a line as each edit succeeds, so
the sequence of calls IS the sequence of lines. Go invites grouping edits
of the same shape into a loop; two cutters were written that way and the
comparison caught both, with byte-identical trees and differently-ordered
reports.

**It is verified against the pipelines and not against itself.**
`make whim-verify` reproduces all 13 recorded boundaries with Go driving
the sweep, and `make zero-verify` 45 of 46 -- where the one failure was
shown to be the harness's and not the sweep's by two measurements: the
failing unit's output tree digests **equal to the recorded boundary**, and
a control run with the Python sweep restored that scores **the same 45 of
46 on a different unit**. Three runs have now failed three different
units, by the two mechanisms `CLAUDE.md` already documents as open --
`zpty.py`'s stall under load, and the `undo_redo` record whose cursor
column is derived from a scrubbed string's length.

**cc/v4 is pinned and patched, not vendored.** `go.mod` pins
`modernc.org/cc/v4` at a released version and `patches/cc-v4-c23.patch`
adds what this tree's C needs; `gobuild.sh` materialises the patched fork
under `.cache/`. The parser has **no role in the sweep** and is not used
there: by the time a sweep runs, six deleting tools have cut the text with
no compile in between, so a parser would fail on it. It belongs to the
phase edits, whose input is a boundary that compiled.

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
  a fixed set of scenarios. `ptyrun.py` holds **`stage()`**, which is the same rule
  as `zstream.py`'s and deliberately a second copy of it: **a harness that copies
  the binary it is about to exec must copy it once per binary, under a lock, in a
  child process**, because `copy2` in one thread and a `fork` in another make
  `execve` fail with `Text file busy` — 5 of 100 idle runs of `termcheck.py` before,
  0 of 100 after. It is duplicated rather than imported because `implhash.sh`
  follows named paths one level, so importing zero's tool here would put it in
  slim's and whim's keys.
- **`termcheck.py`** — what each `$TERM` resolves to and how many colours it
  gets, for every name in the table and every name dropped from it. An empty
  answer is retried at a longer settle before it is believed: under the load of
  a full `verify.sh` the screen is sometimes not drawn yet, and that is a slow
  terminal, not a missing one.
- **`zscreen.py`**, **`zstream.py`**, **`zrec.py`** — zero's instrument, which is
  the screen. `zstream.py` runs the editor with a keystroke FILE on stdin and keeps
  its stdout; `zscreen.py` replays those escape sequences into a 24x80 matrix and
  snapshots it at every `\x1b[?25h`, which is where a redraw ends and is the only
  reason a message line is recordable; `zrec.py` is the sectioned record shape and
  the two scrubs a recording needs (undo's "1 second ago" and the version banner's
  build timestamp, each padded to the width it replaces, because a screen is
  columns). A CJK glyph is two cells and a combining mark none — counting
  characters got two cases of 102 wrong against an independent emulator.
  `zstream.py` also holds **`stage()`**, the one place any zero harness or phase
  check copies the binary under test to the name `vim`: once per binary, under a
  lock, in a child process, because a `copy2` in one thread and a `fork` in another
  make `execve` fail with `Text file busy` — 15 of 18 units of one loaded
  `make zero-verify`.
- **`zcases.py`**, **`zexcmds.py`**, **`zargv.py`**, **`zpty.py`**,
  **`zmemline.py`** — the five corpora: 102 keystroke cases that type their own
  text under `'paste'`, every Ex command name typed at `:` and recorded by the
  message it prints, every command line the parser may see, the five pty scenarios
  for what only a terminal shows (the window size from `TIOCGWINSZ`, raw mode, the
  arrow keys in Normal mode and a **shifted** arrow, which is the one that found
  `keymodel=startsel` had never worked), and sixteen memline cases of 200 to 25,000
  lines. `zpty.py` types the next key when the redraw before it has **ended** — one
  more `\x1b[?25h` — and not when a clock says the editor has been quiet, and its
  child sets the window size before it execs: both were races, 16 of 60 runs under
  load before and 0 of 60 after. **`zrecord.sh <binary> <source> <outdir>`** runs all
  five and `ztermcheck.py` at once, in 5 s, and that is one *recording* — six parts
  and 122 records.
- **`zmemline.py`** is the sixth part and zero phase 40 is the reason it exists:
  every one of the 102 screen cases allocates exactly **one** data block, so a
  `zero-vim` with `pp->pb_pointer[idx].pe_line_count--` deleted from
  `ml_find_line()`'s descent recorded all 102 byte for byte and forty phases had
  been verified by a corpus that could not see the text layer at all. Its sixteen
  cases are built **in the editor** — there is no file argument, no `:edit` and no
  `:read` — and its depth is measured rather than intended: a data block splits in
  16 of 16 and the **root** splits in 4, against 0 of 102 for all seven markers. A
  memline record carries `stream N redraws` and no digest, because an undo's age
  leaks into the column of the `\033[K` that clears it and hashing the scrubbed
  stream would not close it; what replaces the digest is stronger — both clocks the
  core can read replaced by runaway counters move 0 of 16 memline records against 9
  of the 102 screen cases.
- **`ztermcheck.py`** — `termcheck.py` asked twice differently, for two reasons a
  phase apart. It asks **without a file argument**, because from zero phase 5 a file
  argument is an unknown option and the original's nineteen rows all read `(none)`;
  and since zero phase 33 it asks **`+set term={name}`** and not `$TERM`, because
  whim phase 19 removed the `getenv("TERM")` the editor read that with, so all
  nineteen rows answered `term=xterm-256color t_Co=256` — nineteen ways of recording
  that the environment does nothing. That was measured and not suspected: a
  prototype deleting eight of the ten built-in terminal names and three capability
  tables passed `zcompare.py` declaring nothing at all. The new question reaches
  `did_set_term()`, a refused name answers `E522` **and** the terminal the editor
  stayed on, and with one row deleted from `builtin_terminals[]` the new table moves
  1 of 19 where the old moved 0. It imports `termcheck.py` and replaces its `ask()`
  and `one()`, so the terminal list, the isolation and the format cannot drift;
  `termcheck.py` is left alone because whim's and slim's keys read its bytes.
- **`muslcase.py`**, **`muslctype.py`** — zero phase 15's two equivalence tools, and
  neither trusts the bytes the phase shipped. `muslcase.py --generate` writes musl's
  Unicode case mapping as `convertStruct` rows — the shape `zero-vim.c` already has
  for its own case tables — and `--verify <file.c>` re-derives every one of the
  1,114,112 codepoints from *this machine's* libc through ctypes and compares. So
  the 187 + 171 rows are data checked against the only authority there is rather
  than a remembered constant, and a musl upgrade that moved one codepoint fails the
  phase. `muslctype.py --verify <file.c>` slices the seventeen vendored functions
  **out of the produced source**, compiles them with `-Wall -Wextra` and runs them
  beside libc's; its domain is bounded on purpose and its docstring says what the
  unbounded run found. Both are proven able to fail.
- **`zhostonly.py <file.c>`** — zero phase 20's structural assertion, and the check
  that survives into the file split. Moving code from the core into the host block
  inside one translation unit frees no `nm -u` symbol, so the phase's real claim is
  *where* the code is, not how much libc is left: this requires every mention of 43
  host words — `sigaction`, `kill`, `ioctl`, `tcsetattr`, `select`, `nanosleep`,
  every `SIG*`, `struct termios`, `fd_set`, `ICANON`, `VMIN` and the rest — to be
  inside the `host_*`/`musl_*` block, with seven exceptions named one by one with
  their reason and their exact count. It ignores string literals (the file says
  `"close buffer"`) and `#` lines (`#include <errno.h>`), and it refuses to pass
  vacuously: the host region must be found, must define all fourteen of its
  functions, and must itself mention the six words that are the point.
- **`zcompare.py`** — a recording against the baselines, under what
  `pipes/zero.delta` declares: a record by name, or a whole *dimension* through
  `screen-moved` and `stderr-moved`. A dimension declared that did not move is a
  failure, as is a record that moved and was not declared.
- **`create_cmdidxs.py`** — regenerate the command lookup table; `--check`
  verifies it in place. Also the canary for anything that reshapes the table.
- **`verify.sh <baselines-dir>`** — every check above, run concurrently, one
  verdict, about 18 s. Proven to fail on a broken build, a behaviour change
  and a disturbed command table. The baselines live in `.reference/baselines`,
  which is gitignored: `tools/verify.sh .reference/baselines --enums`.
- **`whimdelta.sh <binary> <source> --phase N`**, **`zerodelta.sh`** the same — a
  pipeline's declared delta as a check: exactly what `pipes/<pipeline>.delta` lists
  up to phase N moved, and nothing else. `whimdelta.sh` compares the file-based
  harnesses with slim-vim's `.reference/baselines`; `zerodelta.sh` records with
  `zrecord.sh` and compares with `zcompare.py` against `.reference/zero-baselines`,
  which zero phase 0 records from whim-vim — so zero's delta is from whim, is
  cumulative, and starts empty. Two tools rather than one with a mode, because
  `whimdelta.sh` is in every whim stage's key.
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
`blankruns.py` · `joinparens.py` · `splitheads.py` · `brace.py` ·
`onestmt.py` · `onedecl.py` · `forcomma.py`. `untab.py` is in no loop and
`undowhile.py` is `pipes/slim9.sh`'s. Of the two this list omits, `forcomma.py`
is a no-op on `slim-vim.c` and **`blankruns.py` is not** — it collapses the one
run of two blank lines the file has, at line 41,086. So "each of these is
currently a no-op" is true of the seven named above and is not true of every
canonicaliser.

`decomment.py` is the same kind of pass but is *not* a no-op — it would take
the 245 banners with it. It is here for the rule it enforces, which nothing
else records: a comment becomes one space **plus the newlines it spanned**, and
it refuses outright if any multi-line comment has code on both sides.

## The three-tier memoize

`slim.mk` sequences the twelve phases; these implement the memoize described in
`CLAUDE.md` and `README.md`. None of them knows anything about the phases
themselves.

- **`memo.sh <unit> <work> <build> [pipeline]`** — the driver. A unit is a phase
  `N` or a whim stage `A-B`. Tier 3 (a cached result for this exact unit, input and
  implementation), else tier 2 (the unit's programs, run through `phaserun.sh`),
  else tier 1 (an agent) — and an agent run always leaves a tier 2 behind, so the
  same input never costs an agent twice. A stage whose program fails is never handed
  to an agent: its phases run one at a time through `memo.sh` itself, each with its
  own sweep, boundary and tier 1.
- **`stages.sh <pipeline> [--of N | --check]`** — the units a pipeline runs in, read
  from `pipes/<pipeline>.stages` (slim has none: one unit per phase), and the check
  that the schedule covers every phase once, in order, and keeps every `need` and
  `apart` the manifest declares. `whim.mk` builds its chain from it; `phaserun.sh`
  runs the check before every stage.
- **`packages.sh <pipeline> [--of N | --check]`** — the same phases read by concept:
  each `package` in `pipes/<pipeline>.stages` with its phases and the stages they
  fall in, and each `uses` line, one phase relying on a phase of another package,
  `mechanical` or `rationale`. The check refuses a phase in no package or in two, an
  unknown phase, package or kind, a `uses` inside one package and a `uses` whose
  dependency runs later. `make whim-verify` and `make whim-tip` run it first; nothing
  that runs a phase reads it, and it is a tool of its own rather than a mode of
  `stages.sh` because `phaserun.sh` names `stages.sh`, which puts every byte of it
  in every whim stage's cache key.
- **`phaserun.sh <pipeline> <unit> <work>`** — runs a unit's program. A whole
  `pipes/<pipeline><n>.sh` runs as it is. A stage runs every phase's
  `pipes/<pipeline><n>-edit.sh` in order on unswept text, one `sweep.sh`, every
  `-check.sh` in order, and then the pipeline's delta checker — `PDELTA` in
  `pipeline.sh`, `whimdelta.sh` or `zerodelta.sh` — with `--phase <last>` once. The parts share
  no shell: each phase gets a state directory, `.cache/state/<tag><n>`, with the
  line count of the text its edit was handed and the stage's symbol snapshot, and
  anything else the check needs the edit writes there by name. Each edit's result
  is cached under `.cache/edit/`, keyed by the tree it was handed and `implhash.sh
  --edit`, so editing one phase re-runs that edit and the ones whose input moved,
  then the sweep and the checks. `--parts` lists a unit's program files, and is how
  `memo.sh`, `implhash.sh`, `residue.sh` and `stages.sh` ask whether a phase is a
  program.
- **`implhash.sh <unit> [pipeline]`**, **`implhash.sh --edit <n> whim`** — half the
  cache key: the unit's programs (for a stage, both parts of every phase, the
  `phaserun.sh`, `sweep.sh` and `symbols.sh` run around them, and the lines of
  `pipes/<pipeline>.delta` up to its last phase with the pipeline's delta checker)
  plus every tool,
  patch, table and template they name, one level of indirection deep. Narrow on
  purpose, so editing `resolve.py` re-runs phase 5 and not all twelve, and
  declaring a new phase's delta moves no earlier key. `--edit` is one edit part and
  what it names: the key of that edit's cached result inside a stage.
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
  pipeline share one cached prefix. The orientation is the pipeline's: a whim agent
  is told `WHIM-GOAL.md`, `whim/`, the edit/check shape and `whimdelta.sh --phase N`,
  not slim's tree and build; a zero agent `ZERO-GOAL.md`, `zero/`, the `-no-pie
  -fno-stack-protector` build and `zerodelta.sh`.
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
- **`pipeline.sh slim|whim|zero`** — sourced, never run: the only place the
  pipelines differ (tag, work and build directories, source, document, delta
  checker, phase list). **Every whim split key contains it**, one name deep through
  `phaserun.sh`: one byte changed here moves all 12 whim stage keys and all 82 edit
  keys. Zero's phase list is therefore read from the `phases` line of
  `pipes/zero.stages`, which nothing hashes.
- **`verifypass.sh slim|whim|zero [unit...]`** — every recorded boundary checked at
  once. Each unit — a slim phase, a whim stage — runs on the recorded boundary before it, in a scratch root of
  its own with `tools/` and `pipes/` linked in and a `.cache/` nobody else writes, and must
  reproduce the boundary it recorded: by induction the same proof as a repass
  from an empty cache, in the wall time of the slowest unit (whim: 597 s, stage
  42-63). `make slim-verify`,
  `make whim-verify`; `JOBS=n` to run fewer at once.
- **`specpass.sh slim|whim|zero`** — a speculative repass: every unit at once on the
  previous pass's boundary before it, stored in the tier 3 cache under the key
  `memo.sh` looks up, so the sequential pass that follows is a hit wherever its
  input did not change. Advisory by construction — a wrong guess costs CPU, not
  correctness. `make whim-specpass`; `JOBS=n`, `KEEP=1`.
- **`phasebuild.sh <work> <lines-before>`** — a whim phase's build. `sweep.sh`
  compiles a plain object of each round's starting text in the background, and
  the round that changes nothing started from the final text, so this links that
  object with the work makefile's own flags instead of compiling again: 0.06 s
  against 5.5, and byte-identical to `make`. Not an object compiled with
  `-Wall -Wextra` — those flags move the code, 64 bytes of `.text`, and the
  sweep's own warning compile generates no code at all. Anything whose text no
  longer matches the object's recorded sha builds the ordinary way.
- **`phasecheck.sh <work> <source> <before-dir>`** — a whim phase's checks from
  one compile: it built, no warnings but the fall-throughs, `nm` prints only
  `main`, and the libc symbols it needs. When the sweep's last round saw this
  exact text it compiles nothing: the warnings are `deadsweep.py`'s stderr
  (`.cache/compile/last.txt`) and the object is `build.o`, each used only when
  its recorded sha is the source's.

## Phases that are programs

They live in `pipes/`, not here: `pipes/slim<N>.sh`, `pipes/whim0.sh` and
`pipes/zero0.sh` and `pipes/zero1.sh`, one file per phase, and `pipes/whim<N>-edit.sh` with
`pipes/whim<N>-check.sh` for whim phases 1–82 and `pipes/zero2-edit.sh` with
`pipes/zero2-check.sh`, run in stages by `phaserun.sh`.
`pipes/zero.stages` and `pipes/zero.delta` are zero's manifest and declared delta,
and `templates/zero.mk` is zero's work makefile as it enters the pipeline, whim's with
`-no-pie` (zero phase 1 adds `-fno-stack-protector` to the boundary's copy, not to
the template). Everything below them in this directory
is what they call. `pipes/whim.stages` is the stage manifest — the schedule, what
each edit needs of its input, and which checks need a boundary before a later
phase, and the packages, a concept-by-concept view of the same phases that runs
nothing — and `pipes/whim.delta` is every phase's declared delta, read by
`whimdelta.sh --phase N` and by phase 80's edit.
The slim ones that replaced an agent are described here. Each was written by diffing the two boundaries the agent left — `p2.tar`
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

Slim's Phase 8 runs all of them but `funcreach.py`, in one loop; whim's
`sweep.sh` runs all six in every phase with `canon.sh --once` as the SEVENTH
member of each round — not a pass after the loop, which is a different program:
canon runs at the end of every round because a round's cuts give it something
new to find, and moving it outside was measured to commute on one boundary and
not in general — in rounds until one changes nothing — skipping a tool in a round when it has
already run without changing exactly the current bytes, so the round that ends
the sweep is still one in which every tool has passed the final text. It runs
once per stage, between its edits and its checks, called by `phaserun.sh`, and
wherever an edit part sweeps part way through (14 of them, where a later cut in the
same phase needs the first one swept).

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
