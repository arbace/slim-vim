# Vim as one translation unit

**Experimental.** This repository holds a **process**, not a product: it turns a
pristine [vim](https://github.com/vim/vim) tree into a single C file, `vim.c`,
that one `gcc` invocation compiles into a working, standalone `vim`.

**Between passes there is no editor here.** `vim.c` and `LICENSE` are
*products* — they appear when you run a pass and are regenerated from upstream
the next time. A checkout containing only `.gitignore`, `Makefile`,
`README.md`, `CLAUDE.md`, `GOAL.md` and `tools/` is the intended state, not a
missing file.

**The `Makefile` is the seed, not a product**, and it is what runs a pass:
`vim.c` depends on the upstream branch head, which every `make` asks
`git ls-remote` for and compares against the committed `upstream.sha`.

**Built for Alpine Linux and musl.** The compile line is `-O0 -static -s` and
nothing else: musl's libm is part of libc, and musl declares everything
unconditionally, so upstream's feature-test macros are gone. Another libc wants
them — and `-lm` — put back; `CLAUDE.md` says where.

### What it is not

- **Not a fork, and nothing is rebranded.** The program is vim, the binary is
  `vim`, and `$VIM`, `$VIMRUNTIME`, `~/.vimrc` and every string are upstream's.
- **Not a feature-stripped vim.** The reduction is in *files and preprocessor*,
  not in what the editor can do. The build is upstream's `tiny` configuration
  plus `+extra_search`.
- **But it does not behave like a stock vim.** It ships no vimrc, so what one
  would have said is compiled in instead: eighteen option defaults — among them
  `tabstop=4`, `shiftwidth=4`, `expandtab`, `autoindent`, `nocompatible`,
  `hlsearch` and `ruler` — plus four mappings, with bracketed paste never
  enabled. `-u NONE` does not undo any of it. `CLAUDE.md` lists them all.
- **Not one program but three, per phase.** See *The three-tier memoize*
  below: the pass falls through a cached result, a deterministic program, and
  an agent, in that order. Nine of the ten phases have a program.

## Running a pass

```sh
make
```

That is the whole of it. `make` asks `git ls-remote` for the upstream branch
head; when it matches `upstream.sha` it just compiles the committed `vim.c` in
about eight seconds, and when it does not it clones `upstream/`, deletes its
`.git` immediately because that remote is read-only input, runs the pass,
deletes `upstream/` and records the new sha. Nothing of the clone survives, and
everything this tree has is produced by the phases — there is no list of extras
to re-apply afterwards.

```sh
make repass          # force a pass when upstream has not moved
make phase-4         # re-run one phase from the previous boundary
make replay-3        # put upstream/ back to what phase 4 receives
make times           # where this pass's seconds went
make residue         # how much of each phase is still a recorded diff
make refpass         # the whole pass as one agent, into a directory of its own
make compare         # that answer against this one
```

## The three-tier memoize

**`vim.c` is a function of upstream, and this repository is that function,
memoized.** The pass is ten phases, `p_N = f_N(p_{N-1})`, and each phase has
three implementations that are tried in order:

| tier | what it is | what it can do |
| --- | --- | --- |
| **3** | the cached **result** for this input | nothing; it is an answer |
| **2** | a deterministic **program** | exactly what it was written for |
| **1** | an **agent**, scoped to one phase | cope with something it has not seen |

Tier 3 is keyed by content — the input boundary's digest and the
implementation's digest together — so a cached result answers exactly one
question, and editing one phase re-runs that phase and the ones after it rather
than all ten. A phase that costs a minute cold costs a fifth of a second warm.

Tier 1 is slow and cannot be checked against itself: two agent runs on the same
input have been measured to differ. **What makes it pay is what it leaves
behind** — the difference between the two boundaries it produced is written out
as a patch, and a phase with no program gets one that applies it. So the same
input never costs an agent twice, and every phase acquires a fast path the
first time it is ever run.

That synthesised patch is a working tier 2 and a poor one: it reproduces one
transformation of one input and breaks the moment upstream edits a line it
touches. **Replacing it with rules — a computed set, a table, a transformation
over every line of a shape — is the work, and the size of what is left is the
score.** `make residue` keeps it. Zero means a phase is understood; a thousand
lines means it is remembered.

When a program fails, that is the construct working rather than an error: the
pass falls through to the agent, which produces an answer, and a repair step
then fixes the *program* so the next upstream change costs less than this one
did.

Read `GOAL.md` before you expect to follow along. The ordering is the point.
Then check the result:

```sh
tools/verify.sh .reference/baselines  # behaviour, Ex sweep, pty, terminals, warnings
tools/refcheck.sh                     # this pass against the previous pass's output
```

`verify.sh` compares the editor's *behaviour* against recordings made by an
earlier pass; `refcheck.sh` compares the *source and binary* against that pass's
output. Neither substitutes for the other, and both are inert on a first run,
which is self-certifying.

## Where to read what

| | |
| --- | --- |
| `GOAL.md` | the process: ten phases, the traps each hits, why the order is what it is |
| `CLAUDE.md` | the result: what `vim.c` is, how it is built and verified, every deliberate divergence from upstream |
| `tools/README.md` | the harnesses and passes, and what each is for |

Those two documents are the authority. This file carries no figures that would
go stale; `CLAUDE.md`'s numbers are measurements, re-taken every pass.

## Licence

Vim's own, unmodified, in `LICENSE` — clause II.1 requires it to ship with a
modified Vim, and each pass copies it from the clone rather than maintaining it
here.
