# Vim as one translation unit

> One C file. One `gcc` invocation. A standalone `vim`. Three times over.

**An experiment, and the editor is the excuse.** The question is whether problem
solving can be *represented* — written down as a function, cached like one, and
checked like one — when part of the work needs judgement and the rest does not.

So this is a **process, not a product**. It turns a pristine
[vim](https://github.com/vim/vim) tree into a single `slim-vim.c`, and then keeps
going: each product is a *function of the one before it*, memoized in three tiers
by a makefile.

```sh
make
```

`make` asks `git ls-remote` for upstream's branch head. If it matches the
committed `upstream.sha`, it compiles `slim-vim.c` and stops. If not, it runs a
pass: clone, transform in twelve phases, delete the clone, record the sha.

## Three products, one construct

```
slim-vim.c = F(upstream@sha)          SLIM-GOAL.md
whim-vim.c = G(slim-vim.c)            WHIM-GOAL.md
zero-vim.c = H(whim-vim.c)            ZERO-GOAL.md
```

| | |
| --- | --- |
| **`slim-vim.c`** | The whole editor as **one translation unit** — what were dozens of `.c`, `.h` and `proto/*.pro` files, with no preprocessor left in it and no feature taken out. `make` builds it. |
| **`whim-vim.c`** | The same editor with **no runtime to install**: one static binary that reads nothing from disk that was not compiled into it. Capability is removed here *on purpose*, so every phase declares what it removes before it runs. `make whim-vim`. |
| **`zero-vim.c`** | An **embeddable editor core**, growing one phase at a time: heading for no filesystem, no streams, `main()` demoted to a host launcher, and eventually nothing from libc that the host cannot supply. The screen and all visual editing stay. `make zero-vim`. |

The three pipelines — `slim.mk`, `whim.mk`, `zero.mk` — are the same construct and
differ only in what their phases do. The driver, the boundaries, the oracle and
the synthesiser are shared, and the targets are symmetric on purpose, so a target
that exists on one side and not another is a question rather than an accident.

What differs is the **rules**. A slim phase changes nothing about what the editor
can do, and any behavioural change is a bug. A whim or zero phase changes what the
editor can do deliberately, states which behaviour moves in advance, and is held to
having caused exactly that and nothing else.

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
path the first time it is ever run. Every whim and zero phase is a program today;
slim is the one that can still fall through to the agent.

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

**The whim and zero passes run in *stages*** — a run of phases whose edits share
one sweep, since the sweep is most of what a phase costs. The schedule is declared
in `pipes/whim.stages` and `pipes/zero.stages`, read by concept as well as by
order, and checked rather than trusted: `tools/stages.sh` and `tools/packages.sh`
refuse a manifest that does not hold, and every stage must still end on its
recorded boundary. `CLAUDE.md` has the detail.

## What it is, and is not

| | |
| --- | --- |
| **Not a fork** | Only the delivered files carry this repository's names. Inside the C, `$VIM`, `$VIMRUNTIME`, `~/.vimrc` and every string are upstream's, untouched. |
| **Not stripped** | No feature was removed to make `slim-vim.c` — `:help`, `:hardcopy`, the encodings, locale and iconv are all here. Upstream's `tiny` plus `+extra_search`. Losing capability is what the *other two* pipelines are for, and they say what they lose. |
| **Not stock, though** | It ships no vimrc, so one is compiled in: `tabstop=4`, `expandtab`, `autoindent`, `nocompatible`, `hlsearch`, `ruler` and more. `-u NONE` undoes none of it. |
| **Not portable yet** | Alpine and musl: `-O0 -static -s`, no feature-test macros, no `-lm`. Another libc wants them back. |
| **Not maintained by hand** | `slim-vim.c`, `whim-vim.c`, `zero-vim.c` and `LICENSE` are products of a pass; the makefiles, the documents, `tools/`, `pipes/` and `.gitignore` are the seed. An edit to a product that is worth keeping belongs in the phase that owns it. |

## Commands

| | slim | whim | zero |
| --- | --- | --- | --- |
| build the product | `make` | `make whim-vim` | `make zero-vim` |
| force a pass | `make slim-repass` | `make whim-repass` | `make zero-repass` |
| re-run one phase | `make slim-phase-N` | `make whim-phase-N` | `make zero-phase-N` |
| check every recorded boundary at once | `make slim-verify` | `make whim-verify` | `make zero-verify` |
| where the seconds went | `make slim-times` | `make whim-times` | `make zero-times` |
| how much is still a recorded diff | `make slim-residue` | `make whim-residue` | `make zero-residue` |

And three that belong to no one pipeline: `make score` puts all three products
side by side — bytes to store, libc symbols to provide — `make clean` removes all
three binaries, and `make clean-cache` empties the tier-3 cache they share.

| | |
| --- | --- |
| `tools/verify.sh .reference/baselines` | behaviour, Ex sweep, pty, terminals, warnings |
| `tools/refcheck.sh` | this pass's source and binary against the last one's |
| `make slim-refpass` · `make slim-compare` | the whole slim pass as one agent · that answer against this one |

`verify.sh` checks *behaviour* against recordings, `refcheck.sh` checks *bytes*
against the previous output; neither substitutes for the other, and both are
inert on a first run — which is self-certifying, and said out loud for that
reason. Whim and zero are checked differently, because a phase there is *meant*
to change behaviour: each declares its delta in `pipes/whim.delta` or
`pipes/zero.delta`, and its own check proves that the declared set moved and
nothing else.

## Where to read what

**`CLAUDE.md`** is the result: what each product is, how the three pipelines are
built and verified, every divergence from upstream. The **GOAL** documents are the
processes — `SLIM-GOAL.md` for the twelve phases that make one translation unit,
`WHIM-GOAL.md` for the removals that make it installable-free, `ZERO-GOAL.md` for
the core it is becoming. The **PLAN** documents are what was measured before
building: `WHIM-PLAN.md` on how that pipeline could be better formed,
`ZERO-PLAN.md` on the phases zero has not run yet. `pipes/` is the phases
themselves, `tools/README.md` covers the harnesses and everything a phase calls.
Those are the authority — this file carries no figures, so a third description
cannot drift from them.

## Licence

Vim's own, unmodified, in `LICENSE` — clause II.1 requires it to ship with a
modified Vim, and each pass copies it from the clone rather than maintaining it
here.
