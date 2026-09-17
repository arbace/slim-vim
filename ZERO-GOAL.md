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

**This document is iterative, and so far it has one phase.** Phase 0 is the seed.
No other phase exists yet; phases are added one at a time, each on the user's own
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
   the list — Ex commands, `case:` behaviour cases, `term-moved` — in
   `pipes/whim.delta`'s grammar, and `tools/zerodelta.sh --phase N` shows exactly
   that set moved and no more. "Some cases differ" is not a check.
3. **The delta is from whim-vim, not from slim-vim.** Zero's behaviour is compared
   with `.reference/zero-baselines`, which phase 0 records from the committed
   `whim-vim.c` built with whim's own compile line. Everything whim removed is
   therefore already in them, `pipes/zero.delta` starts empty, and a zero phase
   declares only what *it* changes. Recording them from the pipeline's input is
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
8. **The compile line is `gcc -O0 -static -no-pie -s`.** This is the one difference
   the seed introduces. whim and slim keep `-O0 -static -s`, a static-PIE; zero's
   binary is an ordinary static executable — `readelf -h` says `EXEC`, with no
   `INTERP`, no dynamic section and no relocations — because a core with nothing left
   to relocate is one a host can place without a loader. Any further flag, such as
   `-fno-stack-protector`, is a phase of its own.
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

A tier-3 hit on this phase records nothing, because the phase does not run. A tree
with the cache and no `.reference/zero-baselines` gets them back with
`rm -rf .cache/r0 && make zero-phase-0`.
