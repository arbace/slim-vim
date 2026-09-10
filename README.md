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
- **Not yet deterministic, and becoming so one phase at a time.** The pass is
  ten make targets in `pass.mk`. A phase runs as a **program** if
  `tools/phase<N>.sh` exists and as an **agent** if it does not, so converting
  one is adding a file and the pass runs end to end throughout. An agent-run
  pass takes about an hour, only a couple of minutes of which are the machine;
  `GOAL.md` measures where that hour goes and which phases go first.

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

Each phase leaves a **boundary** behind — a restorable snapshot and a content
digest — which is what makes the deterministic rewrite affordable: converting a
phase means restoring the previous boundary, running the new program and
comparing the next digest, in seconds rather than an hour.

```sh
make repass          # force a pass when upstream has not moved
make phase-4         # re-run one phase from the previous boundary
make replay-3        # put upstream/ back to what phase 4 receives
make times           # where this pass's seconds went
```

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
