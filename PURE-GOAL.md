# PURE-GOAL.md — reduce slim-vim to an embedded editor

`slim-vim.c` is vim as one translation unit, with every feature upstream's
`tiny` configuration has. **`pure-vim.c` is what is left when the editor stops
expecting a filesystem to have been installed for it.**

```
slim-vim.c = F(upstream@sha)          SLIM-GOAL.md, ten phases
pure-vim.c = G(slim-vim.c)            this document
```

The two pipelines are the same construct — a phase is a function of the tree it
is handed, memoized in three tiers — and differ only in what they remove.
`SLIM-GOAL.md` removes *files and preprocessor* and changes nothing about what
the editor can do. **This one removes capability, on purpose**, and every phase
has to say which and prove it removed nothing else.

## The charter

Pure vim is an **embedded** editor: one static binary, no installation, nothing
read from disk that was not compiled in. That is a different product from
slim-vim rather than a better one, and both are kept.

Four kinds of work, in rough order of value:

1. **Pruning** — capability that presumes an installed runtime.
2. **Dropping dependencies**, at run time and at build time. An embedded target
   cares less about bytes than about what it needs from the world.
3. **Simplification** — what the removals leave behind, which is usually more
   than they took.
4. **Optimisation** — last, because measuring it before the shape has settled
   optimises the wrong thing.

## What is measured

**Binary size and external surface**, reported by `make pure-score`:

| | what it says |
| --- | --- |
| stripped bytes | what the target has to store |
| libc symbols still referenced | what the target has to provide |
| source lines | how much is left to reason about |

The symbol set is the one that matters. An embedded target is defined by what
it must supply, not by what it costs, and a phase that shrinks the binary while
adding a syscall has gone backwards. **Both numbers go in the same direction or
the phase is wrong.**

## The rules

1. **Removal is computed, not listed.** Cut the entry points — a command row,
   an option default, a branch of the environment layer — and let the dead-code
   sweep find what becomes unreachable. A phase that names 900 functions to
   delete has written down what the compiler already knows, and will be wrong
   the first time upstream moves.
2. **Every phase states its delta, in advance, as a check.** This is the whole
   difference from `SLIM-GOAL.md`, where any behavioural change is a bug. Here
   a change is the *point*, so the phase must say which behaviour changes and
   the harness must show exactly that set and no more. "Six cases differ" is a
   check; "some cases differ" is not.
3. **A command is never deleted from the table; it is pointed at `ex_ni`.**
   `enum CMD_index`, `cmdnames[]` and the derived `ex_cmdidxs` block keep their
   shape, nothing renumbers, and the trap `SLIM-GOAL.md` records — deleting
   `:help` makes the name resolve to `:helpclose` — cannot fire. The command
   still parses and reports that it is not implemented, which is also the
   honest answer for an editor that has no runtime to show you.
4. **`pure-vim.c` is produced from the committed `slim-vim.c`**, not from a
   pass. The two pipelines are decoupled: `make pure-vim` needs no clone, no
   network and no agent, and the memoize key is `slim-vim.c`'s digest and the
   implementation's, exactly as the other pipeline keys on upstream's sha.

## Phase 0 — seed, and prove the copy is a copy

`pure-vim.c` starts as a byte-for-byte copy of `slim-vim.c`, and the phase's
only job is to establish that. It matters because everything after it is
measured as a delta: if the seed is not identical, every later phase's report
is against the wrong thing.

The check is `cmp`, and the boundary digest is the same file's.

## Phase 1 — no `$VIMRUNTIME`

**The first ground truth: there is no runtime directory.** Nothing is installed
beside the binary, so every path that goes looking for one is dead weight and,
worse, a promise the editor cannot keep — `:help` that opens nothing is more
confusing than `:help` that says it is not implemented.

Four entry points are cut, and everything unreachable behind them is *found*
rather than listed:

- **Six command rows point at `ex_ni`**: `:help`, `:helpclose`, `:helptags`,
  `:runtime`, `:exusage`, `:viusage`. All six exist only to read or display
  files from the runtime directory.
- **`'helpfile'` and `'runtimepath'` default to `""`**, in both halves of the
  `{vi, vim}` pair. They named `$VIMRUNTIME/doc/help.txt` and a five-element
  path through `~/.vim` and `$VIM/vimfiles`.
- **The `VIMRUNTIME` branches of `vim_getenv()` and `vim_setenv()` go.** That
  is the layer that *derives* a runtime directory from the executable's own
  path when the variable is unset, which is precisely the behaviour an embedded
  binary must not have.
- **The `help.c` region** — 981 lines, 13 functions — is then unreachable and
  the sweep removes it, along with whatever else it was the only caller of.

**The delta this is allowed to cause**, and nothing else: the six commands
report `E319` instead of acting, and `:set helpfile? runtimepath?` report
empty. Every other behaviour case, every other Ex command, every pty scenario
and the whole terminal table are unchanged. The harness checks exactly that
against `slim-vim`'s recorded baselines, and then records `pure-vim`'s own.

### The trap

`:help` is not the only way in. `'helpfile'` is read by anything that opens
help, `$VIMRUNTIME` is consulted by the vimrc search, and `:runtime` is what
`:packadd` was built on. Cutting the commands without cutting the option
defaults leaves an editor that still tries to open a file it will never find —
which is why the option defaults are part of *this* phase and not a later one.

## Phase 2 — the options for features that are not here

**There are no commands to cut, and checking that first is the point.** All
fourteen `:menu` commands and all eight `:spell` ones are *already* `ex_ni`:
upstream's `tiny` configuration never compiled them, and the slim pipeline's
empty-object prune removed their sources. A phase that repointed them would be
busywork dressed as progress, and this one asserts the fact rather than assuming
it — if a handler ever comes back, it fails and says so.

What survived those features is their **settings**. Six spell options and one
menu option are still in the table, still settable, still listed by `:set all`,
and read by nothing whatsoever. That is the same lie `:help` told: a control the
editor offers and cannot honour. So `'spell'`, `'spellcapcheck'`,
`'spellfile'`, `'spelllang'`, `'spelloptions'`, `'spellsuggest'` and
`'menuitems'` go, along with their entries in `modeline_whitelist[]`, which
would otherwise outlive the options they name.

**`'mousemodel'` is deliberately kept**, and it is the interesting one. It looks
like a menu option and is not: `:behave` sets it, and it selects how a mouse
click behaves in a terminal — which this build still does.

**The delta is cumulative and does not grow here.** `:set spell` becomes E518
and `:set all` stops listing seven options, but the Ex sweep exercises commands
rather than settings, so it records nothing new. The evidence that this phase
did something is the score, not the delta — which is the honest way round, and
better than inventing a delta to point at.

## Phase 3 — no splash screen, no `:intro`, no `:version`

**An embedded editor starts in a buffer, not on a title card.** Three entry
points, and the third is why this is not simply two more rows repointed:

- **`:intro` and `:version` point at `ex_ni`.**
- **The splash screen's two call sites go.** `maybe_intro_message()` is called
  from the *redraw path* when the buffer is empty and no file was named. It is
  not a command, so an editor whose `:intro` was `ex_ni` would still greet you
  on startup.

- **`--version`, `--help` and `-h`/`-?` stop being options.** Their branches
  become `mainerr(ME_UNKNOWN_OPTION, ...)` — what an unrecognised option
  already does — so nothing is left that exists only to refuse.

That last one is where the phase pays. `--version` was the other door to
`list_version()`, and with that gone the sweep removed **1,041 lines in a single
round**: the version tables, the feature lists, and `pathdef`'s `compiled_user`
and `compiled_sys`, which bake the *building machine's hostname* into the
binary. Measured: the string `satoshi` appears once in `slim-vim` and not at all
in `pure-vim`. That is worth removing on an embedded artifact's account and
worth removing twice on a reproducible one — a binary that names the machine
that built it cannot be byte-identical anywhere else.

**The delta**, cumulative against slim-vim's baselines: `:helpclose` from phase
1, and now `:intro` and `:version`, which succeed in slim-vim and report E319
here. Nothing else may move — and the pty scenarios are the ones to watch,
since a startup screen is exactly the kind of thing a terminal harness records.
The command-line flags change nothing the harness can see, because it never
passes them; the evidence for those is the score and the missing hostname.

## Phase 4 — the binary's name stops choosing what it does

`parse_command_name()` reads `argv[0]` and picks a mode from it: a leading `r`
is restricted mode, `e` selects evim, `g` the GUI, and `view`, `diff` and `ex`
prefixes each change it again. **That is a Unix *installation* convention** —
symlink `rvim`, `view` and `ex` at one binary and let the name decide — and an
embedded editor, which is one file that was never installed, has no use for it.

It is also the trap this repository has paid for more than once. A reference
binary saved as `ref` runs restricted, where every shell-out fails. Renaming the
product to `slim-vim` needed a side-by-side check before it could be trusted.
And every harness here stages the binary under test as `vim` for no reason
except this function. Removing it removes the whole class.

**Nothing is lost, and that is checked rather than asserted.** Every mode the
name could select has an option that selects it explicitly, and
`tools/noargv0.py` refuses to run unless all of them are still there:

| | | |
| --- | --- | --- |
| `-Z` restricted | `-R` readonly | `-y` evim |
| `-e` Ex mode | `-E` improved Ex | `-d` diff |

**Corrected:** an earlier draft of this section claimed `view` set
`'undolevels'` to 10000 where `-R` did not. It is wrong. `p_uc = 10000` appears
at both sites in `slim-vim.c` — once in the `view` branch and once in the `-R`
case — so the two are exactly equivalent and the removal loses nothing at all.
The claim was written from the name-parsing code without checking the option
beside it, which is the mistake this document warns about everywhere else.

**The delta: none.** The harnesses stage the binary as `vim`, which selected
plain vim mode before and selects it now, so nothing they record can move. The
evidence is the score — and the fact that `pure-vim` can now be called anything
at all.

## Phase 5 — options that accept and do nothing, or only refuse

The argument that removed `'spelllang'` in phase 2, applied to the command line.
**An option the editor accepts and ignores is a lie**, and an option whose whole
body is an error message is a branch that exists only to say no. Both are better
expressed by the option not existing — a path this build already has, since
`mainerr(ME_UNKNOWN_OPTION)` is what anything unrecognised reaches.

| | |
| --- | --- |
| **inert** | `-f`, `-X`, `-Y`, `--nofork`, `--literal`, `--gui-dialog-file` — accepted, empty body, or an argument that goes nowhere |
| **refusing** | `-A`, `-F`, `-H` print "not enabled at compile time" and exit; `-g` starts a GUI that does the same |
| **vestigial** | `--help` and `--version`, cut in phase 3 but left as string comparisons that matched and then called `mainerr` |

That last row is phase 3 finishing its own job. A branch that exists only to
reach the default is worse than no branch, and leaving it was an oversight the
option listing found.

**The delta: none the harness records**, because it never passes these. The
evidence is the score and the error strings leaving the binary.

### The trap

`case 'X':` appears in more than one switch in this file — the normal-mode
command tables have their own — so a scan for it over the whole file finds the
wrong one and then says something confusing about a shared body. The argument
parser is the switch that ends in `mainerr(ME_UNKNOWN_OPTION)`, and
`tools/dropopts.py` bounds itself to that before it looks for anything.

## Unused, and unuseful

These are different questions and only one of them has a tool.

**Unused** is what the compiler can prove: nothing reaches it. Every phase here
ends with the sweep run to a joint fixpoint, so unused code never survives a
phase, and no judgement is involved.

**Unuseful** is code that is reachable, compiles, would run, and should not be
here. No warning will ever name it. The only way to make it tractable is to
measure: `tools/coverage.sh` builds with `--coverage`, runs every harness there
is — the behaviour cases, all 600 Ex commands, the pty scenarios — and ranks
what was never entered by size.

**That list is evidence, not a verdict**, and it has at least three kinds in it:

1. **genuinely unuseful** — a feature this product's own defaults never reach;
2. **useful but unexercised** — error paths, rare modes, `vim -` reading stdin.
   A hit here is a finding about the *harness*, and arguably the more valuable
   of the two;
3. **reachable only through something already removed** — the best candidates,
   and the reason to re-run this after every phase.

Deleting from the list without deciding which kind each entry is would remove
working features and call it progress.

### What it says today

**48% of `pure-vim`'s functions are never entered** — 1,590 of 3,329, holding
35,486 lines, about a fifth of the file. The top of the list is one item:

```
   4122  nfa_emit_equi_class        the NFA engine's equivalence classes
    775  reg_equi_class
    710  nfa_regmatch
    636  nfa_regatom
    315  post2nfa
```

`'regexpengine'` is compiled in as **1**, the backtracking engine, so nothing
this editor does by default ever enters the NFA engine — perhaps six thousand
lines of it. It is not unused: `:set re=2` and `\%#=2` still reach it. So it is
the first real decision of the "unuseful" kind, and it is a *capability*
decision rather than a sweep: the question is whether an embedded editor should
carry a second regexp engine that its own defaults never select.

Below it the list is mostly kind 2 and kind 3 — `mainerr` and `get_number_arg`
(error paths the harness never triggers), `read_stdin`, `mch_expand_wildcards`
and `vim_findfile` (the file-lookup layer, which is a phase of its own).

## What comes next

Not yet done, in the order they are worth doing:

- **`'runtimepath'` and the file-lookup layer**: `:source`, `$VIM`, `~/.vim`,
  the vimrc search. Phase 1 empties the option; this removes the machinery.
- **State on disk**: viminfo, swap files, sessions, views. An embedded editor
  that writes four dotfiles into `$HOME` is not embedded.
- **Build-time dependencies**: what the compile line still assumes about the
  host — the headers included, the libc features used, the locale and iconv
  layers, and whether any of it can be answered at compile time instead.
- **Optimisation**, last and deliberately: `-O0` is right for a tree rebuilt
  more often than it is run, and wrong for a binary shipped to a device.
