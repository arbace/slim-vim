# Vim as one translation unit

**Experimental.** This repository holds a **process**, not a product: it turns a
pristine [vim](https://github.com/vim/vim) tree into a single C file, `vim.c`,
that one `gcc` invocation compiles into a working, standalone `vim`.

**Between passes there is no editor here.** `vim.c`, the `Makefile` and
`LICENSE` are *products* — they appear when you run a pass and are regenerated
from upstream the next time. A checkout containing only `.gitignore`,
`README.md`, `CLAUDE.md`, `GOAL.md` and `tools/` is the intended state, not a
missing file.

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
- **Not one command.** `GOAL.md` is a prompt for an agent, run phase by phase
  with verification at every boundary. There is no `run.sh`.

## Running a pass

Read `GOAL.md` first — all of it. The ordering is the point.

```sh
git clone --branch regexp-delimiter-atoms --depth 1 \
    https://github.com/arbace/vim upstream
rm -rf upstream/.git                  # immediately: that remote is read-only input
#   ... GOAL.md Phases 0-9 run inside upstream/ ...
#   ... vim.c, the Makefile and LICENSE move to the repository root ...
rm -rf upstream                       # nothing else of it is kept
```

`upstream/` is a gitignored staging directory that does not exist between
passes, and everything this tree has is produced by those phases — there is no
list of extras to re-apply afterwards. Then build and check:

```sh
make                                  # one gcc invocation
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
