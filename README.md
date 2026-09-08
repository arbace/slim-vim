# Vim as one translation unit

This repository holds a **process**, not a product. It turns a pristine
[vim](https://github.com/vim/vim) tree into a single C file — `vim.c`, about
182,000 lines — that one `gcc` invocation compiles into a working, standalone
`vim` in roughly eight seconds.

**Between passes there is no editor here.** `vim.c`, the `Makefile` and
`LICENSE` are *products*: they appear when you run a pass and are regenerated
from upstream the next time. A fresh checkout containing only `.gitignore`,
`README.md`, `CLAUDE.md`, `GOAL.md` and `tools/` is the intended state, not a
missing file.

### What it is not

- **Not a fork, and nothing is rebranded.** The program is vim, the binary is
  `vim`, and `$VIM`, `$VIMRUNTIME`, `~/.vimrc` and every string are upstream's.
  Whatever you call the checkout directory is not a name this tree uses.
- **Not a feature-stripped vim.** No feature was removed to get here: the
  reduction is in *files and preprocessor*, not in what the editor can do. The
  build is upstream's `tiny` configuration plus `+extra_search`.
- **But it does not behave like a stock vim.** It ships no vimrc, so what one
  would have said is compiled in instead: eighteen option defaults — among them
  `tabstop=4`, `shiftwidth=4`, `softtabstop=4`, `expandtab`, `autoindent`,
  `nocompatible`, `hlsearch` and `ruler` — plus four mappings, with bracketed
  paste never enabled. `-u NONE` does not undo any of it; these are the
  defaults. `CLAUDE.md` lists them all and says which half of each `{vi, vim}`
  pair was edited.
- **Not one command.** `GOAL.md` is a prompt for an agent, executed phase by
  phase with verification at every boundary. There is no `run.sh`.

The result has no preprocessor left in it: every directive in `vim.c` is one of
41 `#include`s of a system header. `main()` is the last thing in the file and
the only symbol with external linkage.

## Running a pass

Read `GOAL.md` first — all of it. The ordering is the point; four of its ten
phases exist only to make the later ones safe.

```sh
git clone --branch regexp-delimiter-atoms --depth 1 \
    https://github.com/arbace/vim upstream
rm -rf upstream/.git                  # immediately: that remote is read-only input
#   ... GOAL.md Phases 0-9 run inside upstream/ ...
#   ... vim.c, the Makefile and LICENSE move to the repository root ...
rm -rf upstream                       # nothing else of it is kept
```

`upstream/` is a staging directory, gitignored, and does not exist between
passes. Everything this tree has is produced by those phases — there is no list
of extras to re-apply afterwards, which is what makes the end-of-pass
comparison mean anything.

Then build and check:

```sh
make                                  # one gcc invocation, ~8 s
tools/verify.sh .reference/baselines  # behaviour, Ex sweep, pty, terminals, warnings
tools/refcheck.sh                     # this pass against the previous pass's output
```

`verify.sh` compares the editor's *behaviour* against recordings made by an
earlier pass; `refcheck.sh` compares the *source and binary* against that pass's
output, which for an unchanged upstream should differ by nothing at all. Neither
substitutes for the other. Both are optional on a first run, which has nothing
to compare against and is self-certifying — say so rather than implying more.

## Where to read what

| | |
| --- | --- |
| `GOAL.md` | the process: ten phases, the traps each one hits, and why the order is what it is |
| `CLAUDE.md` | the result: what `vim.c` is, how it is built and verified, and every deliberate divergence from upstream |
| `tools/README.md` | the harnesses and passes, and what each is for |

Those two documents are the authority. This file is a front door and
deliberately carries no figures that would go stale; `CLAUDE.md`'s numbers are
measurements, re-taken every pass.

## Licence

Vim's own, unmodified, in `LICENSE` — clause II.1 requires it to ship with a
modified Vim, and it is copied from the clone by each pass rather than
maintained here.
