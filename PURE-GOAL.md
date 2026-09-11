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

## Phase 6 — one regexp engine, not two

vim carries two regexp engines and an option to choose between them. **That is a
migration path** — the NFA engine was new once, and `'regexpengine'` existed so a
user could go back when it misbehaved — and an embedded fork inherits the
machinery without inheriting the reason.

This is the first removal here driven by *measurement* rather than by category.
`'regexpengine'` is compiled in as `1`, so nothing this editor does by default
enters the NFA code, and `tools/coverage.sh` never reached a line of it across
the behaviour cases, all 600 Ex commands and the pty scenarios. It was the
largest single entry on that list — `nfa_emit_equi_class` alone is 4,122 lines.

**It is not unused, so this is a decision.** `:set re=2` and `\%#=2` reach it,
and both go: the option is dropped and `vim_regcomp()` stops choosing.

**Checked before cutting**: the custom delimiter atoms this tree's upstream
branch exists for are implemented in *both* engines — `delimiter_atom` appears
once in the `regexp_bt.c` region and again in `regexp_nfa.c` — so the
backtracking engine keeps them and the feature survives intact. Removing the
engine that happened to carry a feature nothing else implements would have been
the one unrecoverable mistake available here.

Three entry points: `vim_regcomp()` compiles with the backtracking engine
unconditionally, `prog_magic_wrong()` stops asking whether a program came from
the NFA engine, and `'regexpengine'` goes through the same tool that dropped the
spell options.

**And the sweep could not finish it, which is this phase's real lesson.** With
the entry points cut, thirteen thousand lines were reachable from nothing — and
`-Wall` said not a word, because every function in the NFA engine is *mentioned*
by another function in it. A recursive-descent parser (`nfa_reg` →
`nfa_regbranch` → `nfa_regconcat` → `nfa_regpiece` → `nfa_regatom` → `nfa_reg`)
and a mutually recursive matcher (`nfa_regmatch` ↔ `addstate`) are immune to
reference counting by construction. `CLAUDE.md` records this trap for *types*;
it is the same shape for functions and nothing here computed it.

`tools/funcreach.py` is `typereach.py`'s argument applied to functions:
reachability from roots, not reference counts. Roots are `main` and every
function named outside all bodies — a handler in `cmdnames[]`, a callback in a
struct — **with prototypes stripped, because a declaration is not a use** and
this file has two thousand of them naming everything there is. It found 54
functions holding 13,376 lines, every one in the `regexp_nfa.c` region,
including seven that do not carry the prefix and that any name-based rule would
have missed.

**The delta: none the harness records.** It never sets `'regexpengine'` and
never writes `\%#=`, and every pattern it does use is compiled by the same
engine as before. That is what a default the product never changed means.

## Phase 7 — the forward declarations nothing needs

A forward declaration earns its place only when something uses the function
before it is defined — a caller higher up the file, a table of handlers,
mutual recursion. This file carries 2,580 and **533 are for functions nothing
mentions until after their own definition**: they say nothing the compiler does
not already know by the time it matters.

**The hazard, and why this is a phase rather than a `sed`:** a `static`
declaration is not only a declaration. A definition that follows one inherits
internal linkage from it, which is why 1,817 of the 3,289 definitions here do
not say `static` themselves and are static anyway. Delete such a prototype and
the function silently becomes *external* — `nm` grows a symbol, and this tree's
whole claim is that `main` is the only one.

So every dropped prototype hands `static` to its definition on the way out —
493 of them needed it — and the phase checks `nm` on the object afterwards
rather than assuming. Linkage preserved by construction, then verified.

Kept, necessarily: anything used before it is defined, including from a
file-scope table — `cmdnames[]` names six hundred handlers and sits above most
of them; one of every mutually recursive pair; and the 26 declarations with no
definition here at all, which are `osdef.h` describing libc and not ours to
remove.

**The delta: none.** Declarations are not behaviour.

## Phase 8 — every definition says its own linkage

1,473 definitions do not say `static` and are static anyway, because a
declaration earlier in the file said it for them and a definition that follows
one inherits its internal linkage.

That works, and **it is a trap with a long fuse.** Remove the declaration — for
being redundant, for tidiness, by accident — and the function quietly acquires
external linkage. Nothing fails. The build is clean, the editor runs, and `nm`
grows a symbol that this tree's central claim says cannot exist. Phase 7 met
that trap and worked around it, handing `static` to each definition whose
declaration it removed; this finishes the job from the other end.

After it, **no declaration anywhere is load-bearing for anything but order**, and
a prototype can be dropped for being unnecessary without anyone having to think
about linkage at all.

`main` is the exception and the only one — it is the entry point and the symbol
that is meant to be external. `nm` on the object proves it.

**The delta: none.** Linkage is not behaviour, and at `-O0` it is not even code,
which is exactly why `nm` is the only witness this phase has.

## Phase 9 — the table moves below what it names

`cmdnames[]` names six hundred Ex command handlers and sits near the top of the
file, so each of them needs a forward declaration — **not because anything calls
them early, but because a table mentions them early.** Moving the table below
its handlers removes 98 of those and costs one declaration of the table itself.

**Two of the three candidate tables cannot move**, and the reason is a language
rule rather than a gap in the tooling. `options[]` and `nv_cmds[]` are measured
with `sizeof()` by functions defined *above* them, and a tentative declaration
of an array has no size — the attempt fails at exactly that `sizeof`. They keep
their 229 declarations. Measuring that was cheaper than arguing about it.

The struct *type* stays where it was. These tables are written
`static struct cmdname { ... } cmdnames[] = {...};` — a type definition and an
object in one — and moving both would leave the declaration behind naming an
incomplete type.

**The delta: none.** Where a table sits is not behaviour.

### And that is the end of what ordering can buy

The remaining declarations were measured rather than guessed at. Of 3,234
functions, **1,335 are in a single mutually recursive component** that no
ordering can untangle — breaking it is a minimum feedback arc set, which is
NP-hard — and the other 1,895 are acyclic and could in principle be
topologically sorted to need no declaration at all. That is not worth doing:
it would buy about 1% of the file and destroy the banner structure that is the
only navigation 165,000 lines have.

## Phase 10 — the editor stops writing shell scripts, and stops drawing a menu

Two cuts, both at the boundary between the editor and everything outside it.

### Wildcards go to the shell, or nowhere

`expand_wildcards()` has **two** expanders behind it and only one of them is the
editor's own. `gen_expand_wildcards()` walks directories itself — `opendir`,
`readdir`, `unix_expandpath()` — and handles `*`, `?`, `[...]`, `~` and `$VAR`
without leaving the process. Everything it cannot do it hands to
`mch_expand_wildcards()`, which is a different animal: it sniffs `'shell'` for
csh, zsh or bash, picks one of five quoting styles, writes a shell *function*
into a temporary file, runs the shell and parses back a NUL-separated list.

That second expander is the editor doing the shell's job in 250 lines, and it
goes. **Shell-out itself stays** — `:!`, `:%!`, `:r !` and the `` `= `` form are
untouched — but the editor no longer generates shell in order to expand a
pattern. What reaches that path now returns unexpanded, which is exactly what
`save_patterns()` already did for a pattern with no wildcard in it at all.

One thing the cut has to carry with it: `save_patterns()` is defined sixty
thousand lines *below* its new caller, so it needs the forward declaration the
old expander's used to hold. Reusing that slot keeps `static` on it, which is
the difference between a file-local function and a new external symbol — hence
the `nm` check at the end of this phase as well as Phase 8's.

### The completion menu, in both of its forms

`'wildmenu'` draws the completion matches as a horizontal menu in the status
line and rebinds the arrow keys to walk it; `'wildoptions'=pum` draws the same
matches as a popup. Both are a *display* of what Tab completion already
computed, and both cost a control path reaching from the option table through
key translation into the redraw code.

**Dropping the option is not enough, and that is this phase's real lesson.**
`p_wmnu` is read at thirteen places, and the dead-code sweep counts references:
a variable that is never assigned TRUE makes every one of those branches
unreachable, and every one of them is still a reference. So `p_wmnu` is folded
to FALSE *at the source*, which turns thirteen reachability questions into the
one question the sweep can answer.

The popup form goes for the mirror image of that reason. With the option gone
`cmdline_pum_active()` can only ever answer FALSE — while still being *called*
ten times, which keeps two hundred lines alive that can no longer run. **The
popup menu itself stays**: `pum_display()` has a second caller in insert-mode
completion, so only the command line's use of it is cut. `'wildoptions'` keeps
its other three values and loses `pum`, because an option value that is still
accepted and now does nothing is what Phase 5 exists to prevent.

### The delta

`:e {a,b}.txt`, `:e 'quoted'` and a backtick in a file argument stop expanding
and name a file literally. `:e *.c`, `:e ~/x`, `:e $HOME/x` and file-name
completion are the native path and do not move. `'wildmenu'` and the `pum`
value of `'wildoptions'` stop existing, so Tab completion behaves as it does
under `set nowildmenu` — which is what this build now always is. **No Ex
command changes**, so the cumulative list is still `helpclose intro version`.

**The libc surface does not move at all, and that was expected.** Shell-out
keeps `fork`, `execvp`, `pipe` and `waitpid`. This phase buys complexity, not
dependencies — 1,109 lines of it — and it is worth doing on those terms alone.

**The directory syscalls are held by three things, and only one of them is the
wildcard layer**, which is worth writing down because it is the obvious next
guess and it is wrong. `unix_expandpath()` is the native expander. `readdir_core()`
is reached only from `delete_recursive()`, which removes the temp directory
tree. `vim_opentempdir()` holds an open `dirfd` on that directory as a lock.
The second and third are the **temp directory**, which exists for shell-out —
`:%!sort` writes a temp file — so they stay for as long as `:!` does.
`getcwd` is not in this layer at all: it is `mch_dirname()`, with eighteen
callers across `:pwd`, `:cd`, full-path resolution and the file finder.

Measured, rather than reasoned about: stubbing `gen_expand_wildcards()` to hand
every pattern back unexpanded — deleting the editor's own globbing outright —
removes 1,025 further lines and **not one libc symbol**. `opendir`, `readdir`,
`closedir`, `getcwd` and `lstat` all survive it. Lowering the surface is a
different question from this one, and the answer to it is not here.

## Phase 11 — the editor stops looking for files it was not given

Two removals that are the same thing seen from two sides: the editor asking the
filesystem what is around the file it was handed.

### Wildcards, the rest of the way

Phase 10 removed the expander that wrote shell scripts. This removes the
editor's own. `gen_expand_wildcards()` walked directories with `opendir` and
`readdir` to match `*`, `?`, `[...]`, `~` and `$VAR`, and now hands every
pattern back unchanged — which is not a stub written for the occasion but the
path vim already took for a pattern with no wildcard in it, `save_patterns()`,
`backslash_halve()` included.

**This costs something real and the cost was measured before it was chosen.**
`:e *.c` opens one buffer named `*.c`, and **file-name completion stops
working**: `:e ali<Tab>` used to produce `alias.c` by globbing `ali*` and now
produces `ali\*`. A shell expands `*.c` before vim ever sees it, which is the
argument for this living outside; inside the editor it is 1,025 lines.

### The current directory

`:cd`, `:chdir`, `:lcd`, `:lchdir`, `:tcd`, `:tchdir` and `:pwd` are retired to
`ex_ni`. A process with a notion of "where I am" that the user can move is a
process with a filesystem; an embedded editor handed a buffer has neither.

### Two things this does not do, both of which look as though it should

**`opendir` and `readdir` do not go with the globbing.** They are held by the
**temp directory** — `vim_opentempdir()`, and `delete_recursive()` via
`readdir_core()` — which exists so `:%!sort` has somewhere to put a file.
`vim_tempname()` has exactly two callers, `do_filter()` and `get_cmd_output()`,
both of them shell users, so the directory layer dies with shell-out in Phase
12 and not with globbing here. That was measured rather than reasoned about,
after reasoning about it gave the wrong answer twice.

**`getcwd` does not go either.** It is `mch_dirname()`, and `:cd`/`:pwd` are two
of its eleven callers; the rest are `buf_modname`, `mch_FullName`,
`shorten_fnames`, `modify_fname` and the file finder, all of them resolving a
path the user named. Retiring the commands does not touch it.

### The delta

`:e *.c` names a file literally, file-name completion stops completing, and
seven command names report "not implemented" instead of changing or printing a
working directory.

**And `:recover` moves, which this phase did not predict.** The check caught it,
not the author: `recover_names()` finds swap files by building the patterns
`*.sw?`, `.*.sw?` and `.sw?` and expanding them, so an editor that does not
expand patterns cannot find a swap file whose name it was not given. That is a
consequence of removing globbing rather than a bug in it, so it is declared —
the alternative, widening the list until it fits, is how a delta list stops
being a check. It also says something about Phase 14: the swap file is already
half unreachable.

Cumulatively: `helpclose intro version cd chdir lcd lchdir tcd tchdir pwd
recover`.

## Phase 12 — `:!` keeps its name and loses its process

`:!cmd`, `:[range]!cmd`, `:r !cmd`, `:w !cmd` and `:shell` keep their names,
their ranges and their parsing. What goes is everything under them — the fork,
the exec, the pipe, the wait — and **the temporary file with them**, because a
temp file is not interface. It exists only because a Unix shell needs a file to
read a range out of, and there is no longer a shell.

### The placement is the phase

`do_filter()` calls `vim_tempname()` *before* it reaches `mch_call_shell()`. So
stubbing the shell alone leaves the whole temporary-directory layer alive,
assembling a file for a command that will never run. Measured on a scratch
build before any of this was written down:

| cut at | libc symbols |
| --- | --- |
| `mch_call_shell` | 146 → 140 |
| `do_filter` / `do_shell` / `get_cmd_output` | 146 → **130** |

The second takes `closedir dirfd execvp flock fork fread fseek ftell mkdtemp
opendir pipe readdir rmdir setsid stdin waitpid`. **This is the first pure
phase whose point is the symbol count**, so the phase *checks* it: a run that
shrank the source and left the surface where it was would have cut in the wrong
place, which is the mistake the phase exists to avoid.

### Three entry points, and one call that outlived them

`do_filter()` and `do_shell()` report in the words `ex_ni` uses for a command
that is not in this build. `get_cmd_output()` returns NULL and says **nothing**
— it is an internal helper whose one caller, `find_locales()`, shells out to
`locale -a` to complete `:language` and already handles NULL; an `emsg` there
would fire on a Tab press rather than on a command.

And `ml_close_all()` calls `vim_deltempdir()` on the way out. Nothing creates a
temp directory any more, but the teardown was unconditional, and it was the last
thing holding `opendir` and `readdir`. Deleting nothing is not worth three
syscalls.

**`do_filter()` and `do_shell()` are left named and reporting rather than
retired to `ex_ni`, and that is deliberate.** An embedded editor with no process
of its own may still be handed a filter by its host, and those two functions are
where it would attach. That is the seam this phase is shaped around.

### The delta

Filtering and shelling out report `E319: Sorry, the command is not available in
this version` instead of running anything. `:language` completion stops listing
locales, silently.

## Phase 13 — the editor stops asking the environment what language it is in

`setlocale(LC_ALL, "")` reads `$LANG`, `$LC_ALL` and `$LC_CTYPE` at startup and
changes how this process compares strings, classifies characters and formats a
time. `:language` lets the user change it again. `enc_locale()` derives
`'encoding'` from `nl_langinfo(CODESET)`. All of it is the editor taking
instruction from whatever environment it happened to be started in.

### One edit here is not a removal, and the phase is wrong without it

**`'encoding'` compiles in as `latin1`.** It is only ever `utf-8` because
`set_init_default_encoding()` asks the locale at startup and overwrites the
default with the answer. Remove that call on its own and this silently becomes
a latin1 editor — every multibyte motion, every `:s` over non-ASCII, every file
read — and it would pass the build, the linkage check and the symbol check
without complaint. So `'encoding'` defaults to `utf-8` in the same edit that
removes the derivation, and the phase **checks the running binary's
`'encoding'`** rather than trusting that it did.

That is not a behaviour change on this target, and that was measured rather than
assumed: musl answers UTF-8 to `nl_langinfo(CODESET)` unconditionally, so the
derived value was already `utf-8` — with `$LANG` set, and with `$LANG` unset.
The change makes the encoding **a property of the build instead of a property of
the machine**, which is the whole point, and it is what Phase 14 builds on.

**And `set_init_default_encoding()` is replaced, not deleted**, which took three
tries to get right. It did three things: ask the locale, re-initialise the
multibyte layer for whatever it answered, and write that back as the option's
default. Only the first is locale. The second is load-bearing and invisible:
`p_enc` is set from the option table, and **nothing acts on it until `mb_init()`
runs**. Delete the call outright and `:set encoding?` says `utf-8` while
`enc_utf8` is still FALSE — the editor claims UTF-8 and behaves like latin1,
which is worse than either. The build is clean, the symbol check passes, and
`:set encoding?` gives the right answer, so nothing above the harness can see
it. Five multibyte behaviour cases could: `à é î` stopped upper-casing. The call
becomes `(void)mb_init();`.

Two smaller traps in the same phase, both of a kind this file already records.
`mb_init()`'s `if (enc_dbcs)` block needed **brace matching, not a regex** — a
lazy `(?:[^\n]*\n)*?\}` stops at the first line that is only a brace, which here
is an inner `if`'s, leaving `vim_free(p);` and a stray `}` at file scope, which
gcc reports four hundred lines away as *"data definition has no type or storage
class"*. And `vimconv` **stays**: `mb_init()` tests `vimconv.vc_type` again two
hundred lines below the block, and removing the declaration on the strength of
one visible use is a compile error a long way from the edit.

The phase itself had a third fault worth fixing rather than noting: **an error
is not a warning.** The warning sweep counted lines matching `warning:`, found
none in a run that had failed outright, and `set -e` on the next plain compile
ended the phase with no output at all. It now asks gcc whether it succeeded
before asking what it complained about.

### The four `lang*` options

`'langmap'`, `'langmenu'`, `'langnoremap'` and `'langremap'` are all wired to
`(char_u *)NULL` — they accept a value and store it nowhere. They are Phase 5's
rule arriving late rather than a new decision, and no behaviour can change.

### The delta

`:language` reports that it is not available. Nothing else: the process runs in
the C locale now, which is what it was already running in for every purpose this
build has. `setlocale`, `nl_langinfo` and `strcoll` leave the symbol table.

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

**47% of `pure-vim`'s functions are never entered** — 1,520 of 3,255, holding
27,865 lines, about a sixth of the file. Measured after Phase 10:

```
    775  reg_equi_class             the backtracking engine's equivalence classes
    713  get_c_indent               'cindent', which nothing here turns on
    284  do_mouse                   'mouse' is empty by default
    251  do_window                  CTRL-W, which no harness presses
    168  vim_findfile_init
    160  modify_fname
    158  win_equal_rec
    147  vim_findfile
```

**Compare it to the last reading and the list is doing its job.** It was taken
before Phase 6 and said 1,590 of 3,329 over 35,486 lines, with one entry —
`nfa_emit_equi_class`, 4,122 lines — as the whole top of it. Phases 6 to 10
removed 7,621 lines of never-entered code, and most of that is the NFA engine
Phase 6 cut. What is left at the top is a different
kind: `get_c_indent`, `do_mouse` and `do_window` are *kind 2*, reachable and
useful and simply not exercised, which is a finding about the harness rather
than about the code. Only `vim_findfile` and `vim_findfile_init` are kind 3 —
the file-lookup layer, which is a phase of its own.

**Also measured: the harness itself.** `tools/coverage.sh` was resolving the
source path relative to the wrong directory, so `exsweep.py` exited 1 and the
`&&` chain took the pty scenarios down with it — and what came back was a
figure computed from one harness out of three: 64% never entered instead of
47%. It was lower than the previous reading, it moved in a plausible direction,
and it was wrong. The three harnesses are now run and reported separately, so a
failure says so instead of quietly shrinking the denominator.

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
