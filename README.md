# Vim as one translation unit

> One C file. One `gcc` invocation. A standalone `vim`.

**Experimental.** This repository is a **process**, not a product: it turns a
pristine [vim](https://github.com/vim/vim) tree into a single `slim-vim.c` — and
`slim-vim.c` is a *function of upstream*, memoized in three tiers by a makefile.

```sh
make        # that is the whole of it
```

`make` asks `git ls-remote` what upstream's branch head is. If it matches the
committed `upstream.sha`, it compiles `slim-vim.c` and stops. If it does not, it runs
a pass: clone, transform in ten phases, delete the clone, record the new sha.

---

## The three-tier memoize

The pass is ten phases, `pₙ = fₙ(pₙ₋₁)`. Each falls through three
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

**Tier 3** is keyed by content — the input boundary's digest and the
implementation's digest — so editing one phase re-runs that phase and the ones
after it, never all ten.

**Tier 1** is slow and cannot be checked against itself: two agent runs on
identical input have been measured to differ. What makes it pay is what it
leaves behind. The difference between the boundaries it produced is written out
as a patch, so a phase acquires a fast path the first time it is ever run.

**That patch is a working tier 2 and a poor one.** It reproduces one
transformation of one input and breaks the moment upstream edits a line it
touches. Replacing it with rules is the work; what will not reduce to a rule is
the score — `make residue`. Zero means a phase is *understood*; a thousand
lines, that it is only *remembered*. All ten are programs today.

A program that fails is the construct working, not an error: the pass falls
through to the agent, and a repair step then fixes the **program**, so the next
upstream change costs less than this one did.

---

## What it is, and is not

| | |
| --- | --- |
| **Not a fork** | Only the two delivered files carry this repository's name. Inside the C, `$VIM`, `$VIMRUNTIME`, `~/.vimrc`, `VIMNAME` and every string are upstream's, untouched. |
| **Not stripped** | No feature was removed — `:help`, `:hardcopy`, the encodings, locale and iconv are all here. The build is upstream's `tiny` plus `+extra_search`. |
| **Not stock, though** | It ships no vimrc, so one is compiled in: `tabstop=4`, `expandtab`, `autoindent`, `nocompatible`, `hlsearch`, `ruler` and more, plus a handful of mappings. `-u NONE` undoes none of it. |
| **Not portable yet** | Alpine and musl: `-O0 -static -s`, no feature-test macros, no `-lm`. Another libc wants them back. |
| **Not an editor between passes** | `slim-vim.c` and `LICENSE` are products; `Makefile`, `SLIM-GOAL.md`, `CLAUDE.md`, `tools/` and `.gitignore` are the seed. |

---

## Commands

| | |
| --- | --- |
| `make repass` | force a pass when upstream has not moved |
| `make phase-4` | re-run one phase from the previous boundary |
| `make replay-3` | put `upstream/` back to what phase 4 receives |
| `make times` · `make residue` | where the seconds went · how much is still a recorded diff |
| `make refpass` · `make compare` | the whole pass as one agent · that answer against this one |
| `tools/verify.sh .reference/baselines` | behaviour, Ex sweep, pty, terminals, warnings |
| `tools/refcheck.sh` | this pass's source and binary against the last one's |

`verify.sh` checks *behaviour* against recordings; `refcheck.sh` checks *bytes*
against the previous output. Neither substitutes for the other, and both are
inert on a first run — which is self-certifying.

---

## Where to read what

| | |
| --- | --- |
| **`SLIM-GOAL.md`** | the process — ten phases, the traps each hits, why the order is what it is |
| **`CLAUDE.md`** | the result — what `slim-vim.c` is, how it is built and verified, every divergence from upstream |
| **`tools/README.md`** | the harnesses and passes, and what each is for |

Those are the authority. This file carries no figures, so a third description
cannot drift from them; `CLAUDE.md`'s numbers are measurements, re-taken every
pass.

## Licence

Vim's own, unmodified, in `LICENSE` — clause II.1 requires it to ship with a
modified Vim, and each pass copies it from the clone rather than maintaining it
here.
