# Vim as one translation unit

> One C file. One `gcc` invocation. A standalone `vim`.

**An experiment, and the editor is the excuse.** The question is whether problem
solving can be *represented* — written down as a function, cached like one, and
checked like one — when part of the work needs judgement and the rest does not.

So this is a **process, not a product**. It turns a pristine
[vim](https://github.com/vim/vim) tree into a single `slim-vim.c`: the product is
a *function of upstream*, memoized in three tiers by a makefile.

```sh
make
```

`make` asks `git ls-remote` for upstream's branch head. If it matches the
committed `upstream.sha`, it compiles `slim-vim.c` and stops. If not, it runs a
pass: clone, transform in twelve phases, delete the clone, record the sha.

## One product, and what grows from it

```
slim-vim.c = F(upstream@sha)          SLIM-GOAL.md
```

`slim-vim.c` is the whole editor as **one translation unit** — what were dozens of
`.c`, `.h` and `proto/*.pro` files, with no preprocessor left in it and no feature
taken out. A slim phase changes nothing about what the editor can do, and any
behavioural change is a bug.

**It is also an input.** [arbace/go-whim](https://github.com/arbace/go-whim) takes
this repository's `slim-vim.c` and runs two further pipelines on it, with a Go
toolset: *whim*, which removes capability on purpose until nothing need be
installed beside the binary, and *zero*, which turns that into an embeddable editor
core. They grew up here and moved there; this repository keeps only the slim
pipeline and its Python and shell tools.

## The three-tier memoize

A pass is a sequence of phases, `pₙ = fₙ(pₙ₋₁)`. Each falls through three
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
never the whole pass.

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
| **Not a fork** | Only the delivered files carry this repository's names. Inside the C, `$VIM`, `$VIMRUNTIME`, `~/.vimrc` and every string are upstream's, untouched. |
| **Not stripped** | No feature was removed to make `slim-vim.c` — `:help`, `:hardcopy`, the encodings, locale and iconv are all here. Upstream's `tiny` plus `+extra_search`. Losing capability is what arbace/go-whim is for, and it says what it loses. |
| **Not stock, though** | It ships no vimrc, so one is compiled in: `tabstop=4`, `expandtab`, `autoindent`, `nocompatible`, `hlsearch`, `ruler` and more. `-u NONE` undoes none of it. |
| **Not portable yet** | Alpine and musl: `-O0 -static -s`, no feature-test macros, no `-lm`. Another libc wants them back. |
| **Not maintained by hand** | `slim-vim.c` and `LICENSE` are products of a pass; the makefile, the documents, `tools/`, `pipes/` and `.gitignore` are the seed. An edit to a product that is worth keeping belongs in the phase that owns it. |

## Commands

| | |
| --- | --- |
| build the product | `make` |
| force a pass | `make slim-repass` |
| re-run one phase | `make slim-phase-N` |
| check every recorded boundary at once | `make slim-verify` |
| where the seconds went | `make slim-times` |
| how much is still a recorded diff | `make slim-residue` |

`make clean` removes the binary, and `make clean-cache` empties the tier-3 cache.

| | |
| --- | --- |
| `tools/verify.sh .reference/baselines` | behaviour, Ex sweep, pty, terminals, warnings |
| `tools/refcheck.sh` | this pass's source and binary against the last one's |
| `make slim-refpass` · `make slim-compare` | the whole slim pass as one agent · that answer against this one |

`verify.sh` checks *behaviour* against recordings, `refcheck.sh` checks *bytes*
against the previous output; neither substitutes for the other, and both are
inert on a first run — which is self-certifying, and said out loud for that
reason.

## Where to read what

**`CLAUDE.md`** is the result: what the product is, how the pipeline is built and
verified, every divergence from upstream. **`SLIM-GOAL.md`** is the process, the
twelve phases that make one translation unit. `pipes/` is the phases themselves,
`tools/README.md` covers the harnesses and everything a phase calls.
Those are the authority — this file carries no figures, so a third description
cannot drift from them.

## Licence

Vim's own, unmodified, in `LICENSE` — clause II.1 requires it to ship with a
modified Vim, and each pass copies it from the clone rather than maintaining it
here.
