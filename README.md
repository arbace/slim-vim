# Vim as one translation unit

> One C file. One `gcc` invocation. A standalone `vim`.

**An experiment, and the editor is the excuse.** The question is whether problem
solving can be *represented* — written down as a function, cached like one, and
checked like one — when part of the work needs judgement and the rest does not.

So this is a **process, not a product**: it turns a pristine
[vim](https://github.com/vim/vim) tree into a single `slim-vim.c`, and
`slim-vim.c` is a *function of upstream*, memoized in three tiers by a makefile.

```sh
make
```

`make` asks `git ls-remote` for upstream's branch head. If it matches the
committed `upstream.sha`, it compiles `slim-vim.c` and stops. If not, it runs a
pass: clone, transform in twelve phases, delete the clone, record the sha.

## The three-tier memoize

A pass is twelve phases, `pₙ = fₙ(pₙ₋₁)`. Each falls through three
implementations, cheapest first:

```
   ┌──────────────────────────────────────────────────────┐
   │  tier 3   the cached result for this exact input     │  instant
   │  tier 2   a deterministic program                    │  seconds
   │  tier 1   an agent, scoped to one phase              │  minutes
   └──────────────────────────────────────────────────────┘
      ▲                                                   │
      └───── every tier-1 run leaves a tier 2 behind ─────┘
```

**Tier 3** is keyed by content — the input's digest and the implementation's
digest together — so editing one phase re-runs that phase and the ones after it,
never all twelve.

**Tier 1 is the agent, and it is not a function.** Two runs on identical input
have been measured to differ, so its answer is cached and never trusted as a
check. What makes it pay is what it leaves behind: the difference between the
boundaries it produced is written out as a patch, so a phase acquires a fast
path the first time it is ever run.

**That patch is a working tier 2 and a poor one** — it reproduces one
transformation of one input and breaks the moment upstream edits a line it
touches. Replacing it with *rules* is the work, and what will not reduce to a
rule is the score, `make slim-residue`: zero means a phase is **understood**, a
thousand lines that it is only **remembered**.

That is the whole experiment — judgement is expensive and unrepeatable, so spend
it once and keep what it produced as something cheap and repeatable. A program
that fails is the construct working, not an error: the pass falls through to the
agent, and a repair step then fixes the *program*, so the next upstream change
costs less than this one did.

## What it is, and is not

| | |
| --- | --- |
| **Not a fork** | Only the delivered file carries this repository's name. Inside the C, `$VIM`, `$VIMRUNTIME`, `~/.vimrc` and every string are upstream's, untouched. |
| **Not stripped** | No feature was removed — `:help`, `:hardcopy`, the encodings, locale and iconv are all here. Upstream's `tiny` plus `+extra_search`. |
| **Not stock, though** | It ships no vimrc, so one is compiled in: `tabstop=4`, `expandtab`, `autoindent`, `nocompatible`, `hlsearch`, `ruler` and more. `-u NONE` undoes none of it. |
| **Not portable yet** | Alpine and musl: `-O0 -static -s`, no feature-test macros, no `-lm`. Another libc wants them back. |
| **Not an editor between passes** | `slim-vim.c` and `LICENSE` are products; the makefiles, the documents, `tools/` and `.gitignore` are the seed. |

## Commands

| | |
| --- | --- |
| `make slim-repass` · `make slim-phase-4` | force a pass · re-run one phase |
| `make slim-times` · `make slim-residue` | where the seconds went · how much is still a recorded diff |
| `make slim-refpass` · `make slim-compare` | the whole pass as one agent · that answer against this one |
| `tools/verify.sh .reference/baselines` | behaviour, Ex sweep, pty, terminals, warnings |
| `tools/refcheck.sh` | this pass's source and binary against the last one's |

`verify.sh` checks *behaviour* against recordings, `refcheck.sh` checks *bytes*
against the previous output; neither substitutes for the other, and both are
inert on a first run — which is self-certifying, and said out loud for that
reason.

## Where to read what

**`SLIM-GOAL.md`** is the process: twelve phases, the traps each hits, why the
order is what it is. **`CLAUDE.md`** is the result: what `slim-vim.c` is, how it
is built and verified, every divergence from upstream. **`tools/README.md`**
covers the harnesses. Those are the authority — this file carries no figures, so
a third description cannot drift from them.

## Licence

Vim's own, unmodified, in `LICENSE` — clause II.1 requires it to ship with a
modified Vim, and each pass copies it from the clone rather than maintaining it
here.
