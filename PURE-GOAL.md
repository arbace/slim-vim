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

**Binary size and external surface**, reported by `make score`:

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

## Phases 7 and 8 moved to SLIM-GOAL.md

They were "the forward declarations nothing needs" and "every definition says
its own linkage", and this was the wrong home for them. **Neither removes a
capability**, which is the only thing this document is for; both are simply true
of a single translation unit whatever it contains, so they belong to whichever
pipeline first has one — which is the slim one, from its Phase 6 onward. They
are `SLIM-GOAL.md` Phases 10 and 11 now, and `slim-vim.c` carries their result.

Keeping them here had a cost beyond misfiling. `tools/allstatic.py` did in one
pass exactly what slim's Phase 8 was doing with one process per symbol — two
pipelines away from the phase that needed it — and that duplication is why
slim's Phase 8 took 369 seconds instead of 115.

## Phase 7 — the table moves below what it names

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

## Phase 8 — the editor stops writing shell scripts, and stops drawing a menu

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
the `nm` check at the end of this phase as well as SLIM-GOAL.md Phase 11's.

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

## Phase 9 — the editor stops looking for files it was not given

Two removals that are the same thing seen from two sides: the editor asking the
filesystem what is around the file it was handed.

### Wildcards, the rest of the way

Phase 8 removed the expander that wrote shell scripts. This removes the
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
being a check. It also says something about Phase 12: the swap file is already
half unreachable.

Cumulatively: `helpclose intro version cd chdir lcd lchdir tcd tchdir pwd
recover`.

## Phase 10 — `:!` keeps its name and loses its process

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

## Phase 11 — the editor stops asking the environment what language it is in

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
the machine**, which is the whole point, and it is what Phase 12 builds on.

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

## Phase 12 — no tag stack

A tag jump is the editor discovering, on its own, that a file it was never told
about exists. `get_tagfname()` walks `'tags'` upward from the current file,
opens whatever it finds and binary-searches it — filesystem-layout knowledge of
exactly the kind Phase 9 removed from `'path'`, and the largest single item
left in the tree at 2,364 lines.

### Four entry points that are not commands

Retiring the fifteen rows is most of it, and would have removed almost nothing
on its own, because each of these keeps the whole subtree alive by itself:

- **`nv_help()` — the `<Help>` key — calls `ex_help()`, which calls `do_tag()`.**
  `:help` has been `ex_ni` since Phase 1, but the *key* was never cut, so the
  entire help-tag search survived a phase that believed it had removed it. This
  is the clearest case in this tree for the rule that entry points are cut, not
  commands.
- `nv_tagpop()` — CTRL-T — calls `do_tag()` straight out of `nv_cmds[]`.
- `ExpandFromContext()` dispatches `EXPAND_TAGS` to `expand_tags()` and
  `EXPAND_HELP` to `find_help_tags()`. Completion is a caller like any other.
- `get_next_completion_match()` dispatches CTRL-X CTRL-] to
  `get_next_tag_completion()`.

**CTRL-`]` is not on that list and does not need to be.** `nv_ident()` builds
the string `":ta "` and runs it as an Ex command, so retiring the row is enough
and the key reports what `:tag` reports — which is also the honest answer.

### What stays

`vim_findfile()`. `'tags'` searching and `'path'` searching share it, and
`find_file_in_path_option()` still serves `:find` and `gf`. Cutting that is a
separate decision from this one, because `gf` is a normal-mode command a user
would miss, and it deserves to be made on its own.

### Two options that cannot go, and the trap they exposed

Six of the eight tag options are dropped. **`'tags'` and `'tagcase'` are
`PV_BOTH` — buffer-local — and their rows are also what initialise their
globals**, because `set_init_1()` sets `p_tags` and `p_tc` by walking
`options[]`. Remove the row and the global stays NULL, and any reader the sweep
does not reach dereferences it at startup.

`'tagcase'` is the one that taught this. Dropping it **built cleanly, swept to
silence, passed the linkage and symbol checks, and segfaulted before the first
keystroke.** From outside, the harness reported it as *every* behaviour case,
the terminal table and *every* Ex command moving at once — which is what a crash
looks like through a delta check. Every option any phase had dropped until then
was `PV_NONE`, so nothing had ever exercised this path.

`tools/dropoptions.py` now refuses a row whose `indir` is not `PV_NONE`, and
says why. Refusing is the right answer rather than handling it: removing the
buffer-local field, its initialiser, its copy, its free and its readers is real
surgery, and it should be a phase that says so rather than a side effect of a
call that looks like the six beside it. The two options stay, inert, until then.

### The delta

**One row moves, not fifteen**, and the difference is worth keeping. Retiring a
command only shows up in the Ex sweep if the command used to *succeed*: `:tag`,
`:tjump` and the rest already failed for want of a tags file to read, and
`ex_ni` fails too, so their recorded exit is unchanged. `:tags` listed an empty
tag stack and exited 0, and now reports instead. CTRL-`]` and CTRL-T report what
`:tag` reports. The declared list is what moved, not what was cut.

## Phase 13 — nothing is written that was not asked for

A swap file is not a recovery add-on bolted to the side of the editor. It is
**memline's backing store**: created beside every file you open, written to as
you type, deleted on a clean exit. For an embedded editor it is the last thing
writing a file nobody asked for, and it is why `'directory'` is searched for a
free `.swp` name and why a 576-line recovery reader exists.

**What goes is the file, not the memline.** `mf_open()` already supports a
memfile with no name — that is what `:set noswapfile` has always produced — so
the buffer keeps its block structure and never acquires a fd. The cost is real
and was agreed before any of it was written: **no crash recovery**, and a buffer
larger than memory can no longer page out to disk.

Five entry points, because `ml_open_file()` has seven callers and no-oping them
one at a time would be seven chances to miss one. `ml_open_file()` returns
having set `b_may_swap = FALSE`, so the callers that retry stop retrying — a
body that merely returned would search `'directory'` again on the next
keystroke. `ml_preserve()`, `ml_sync_all()` and `ml_setname()` become no-ops:
flushing, syncing and renaming a file that does not exist. And the `SEA_RECOVER`
arm of the ATTENTION prompt goes, which is the only way into `ml_recover()` once
`:recover` is retired.

With it go the two other things that wrote without being asked: `:mkvimrc`,
`:mkexrc`, `:mksession` and `:mkview`, which drop a script into the current
directory, and `:checktime`.

### The check this phase exists for

No build can make it, so the phase runs the binary: **edit a file in an empty
directory and nothing may be left beside it.** `ls -A` must show exactly the
file that was edited.

### Not done here

**The automatic timestamp check remains.** `check_timestamps()` is still called
from `main_loop()`, `edit()` and `wait_return()`, so the editor still notices a
file changing underneath it — retiring `:checktime` removed the command, not the
polling. That is a separate cut with a separate delta.

### The delta, and three things the harness knew better than the author

Eight command names report that they are not available; `'directory'`,
`'updatecount'` and `'swapsync'` stop existing. `'swapfile'` cannot go — it is
`PV_BUF` and its row is what initialises the global, the trap Phase 12 records —
so it stays and is now always effectively off.

`:mksession` and `:mkview` **do not move**: they already failed. And `:recover`
**leaves** the cumulative list it joined in Phase 9 — removing globbing had
made it fail differently from the slim baseline, and `ex_ni` makes it fail the
same way again, so it stops being a difference. A cumulative delta can shrink,
which is not something a list maintained by hand would ever discover.

## Phase 14 — UTF-8, and no other encoding, ever

Phase 11 made `'encoding'` a property of the build rather than of the machine.
This makes it **not a setting at all**: `mb_init()` accepts `utf-8` and returns
"invalid argument" for anything else, so `:set enc=latin1` fails the way a
misspelt value fails, and the latin1 and DBCS character paths lose their only
caller and are swept.

### The conversion layer is cut at its entry points, not unpicked from its callers

This is the shape of the phase and the reason it is small. `readfile()` is 1,758
lines with conversion woven through a retry loop, partial-character carry-over
and a `goto retry`; `buf_write()` is much the same. Excising that by hand is the
kind of surgery that compiles, passes a symbol check, and corrupts a file on
some path nobody tested.

Instead **six functions answer differently**, and every one of those answers is
a case the callers already branch on:

| | now answers | which is what happens when |
| --- | --- | --- |
| `my_iconv_open()` | failure | the system has no iconv — a case upstream supports |
| `convert_setup()` | `CONV_NONE` | source and target encodings are the same |
| `string_convert()` | `NULL` | there is nothing to convert |
| `check_for_bom()` | no BOM found | the file has none |
| `make_bom()` | writes nothing | `'bomb'` is off |
| `convert_input_safe()` | the input unchanged | no input conversion is set up |

Nothing is restructured. The sweep then takes `convert_setup_ext`,
`string_convert_ext` and `iconv_string`, because nothing reaches them.

**Only then** are the seven branches that can no longer be taken deleted — and
only because the calls inside them are what keep `iconv`, `iconv_open` and
`iconv_close` in the symbol table. A dependency that is linked in and never
reached is exactly what this pipeline exists to remove. Each is a brace-matched
`if` with no `else`, and **every anchor names a line of the body, not just the
condition**: `if (fio_flags == 0)` occurs twice in `readfile()` and the first has
an `else` after it, so the obvious anchor deleted the wrong block and left an
orphaned `else` — which gcc reported as *"expected `}` before `else`"* and then
as two undefined labels six hundred lines away. The same shape as
`funcreach.py`'s two regex bugs: a span that ended in the wrong place.

### Two checks no build can make

An editor that silently stopped being a UTF-8 editor passes the build, the
linkage check and the symbol check. So the phase runs the binary: `'encoding'`
must report `utf-8`, and `gUU` over `à é` must produce `À É` — byte for byte,
`c3 80 c3 89 0a`. It also asserts that **no symbol beginning `iconv` is linked**,
asked of the object and after the sweep, because asking the source beforehand
gets the wrong answer: `iconv_string()` is still there at that point and it is
the sweep that removes it.

### What cannot go, and the rule that finally states why

**Of the six encoding options, only `'charconvert'` can actually be removed.**
The other five each fail for what turns out to be the same reason, arrived at
three times by three different routes:

| | why it stays |
| --- | --- |
| `'encoding'` | `PV_NONE`, but `p_enc` is read in twenty-nine places |
| `'fileencodings'` | `PV_NONE`, not reached by name — and `readfile()` dereferences `p_fencs` |
| `'termencoding'` | `PV_NONE` — and `did_set_encoding()` dereferences `p_tenc` |
| `'fileencoding'`, `'bomb'` | `PV_BUF`, the trap Phase 12 recorded |

**A row is what initialises its global.** Phase 12 found that for a
buffer-local option and guarded on `PV_`; this phase found it for a `PV_NONE`
option reached by *name* (`set_string_option_direct((char_u *)"fencs", …)`,
which answers `E685` and then segfaults) and then again for one reached only
through its variable. The `PV_` test and the name test are both special cases of
the real invariant: **an option is inert only when nothing reads its global any
more.** One whose feature has truly gone has an unread global and the sweep
deletes it a moment later; one that is still read is not inert, it is live code
with its initialiser removed.

**The `PV_` test is unconditional; the other two are `--strict`, and that
distinction is not tidiness.** `PV_BUF` is a property of the row, true whenever
you look. "Nothing reads this global" is only true *after the sweep*, and most
phases drop their options before it — so asking then names the readers the sweep
is about to delete. Phase 2 (`'spell'`) and Phase 6 (`'regexpengine'`) both
fail that question and are both correct. This phase drops after sweeping and so
asks in strict mode. It is the same mistake this phase made twice more — a check
placed one step too early — and it is worth naming because it looks like
rigour.

`'fileencodings'` keeps its row and loses its content — empty is the branch
`readfile()` already takes when a user empties it.

### The delta

A byte-order mark becomes three ordinary bytes at the top of the buffer, which
is what ignoring it means, and the `bomb_on` behaviour case moves because of it.
`'charconvert'` stops existing. **No Ex command moves.**

## Phase 15 — the editor stops re-reading a file it has already read

vim watches the files it holds. `check_timestamps()` walks every buffer and
stats its file — from the main loop, from insert mode, from the `Press ENTER`
prompt, and whenever the terminal regains focus — and `buf_check_timestamp()`
does the same for one buffer on entering it. If the file moved underneath it
prompts, and with `'autoread'` it reloads.

That is the editor initiating filesystem traffic on its own account, which is
the boundary this fork narrows. **Phase 13 retired `:checktime`, which removed
the command; this removes the polling, which is what actually reached the
disk.** What is left is an editor that reads a file when told to and writes it
when told to.

`check_timestamps()` returns 0 without looking at anything, and its four callers
are left calling it. Stubbing rather than unpicking them is deliberate: each
sits in a different control structure and each already handles that answer. The
three direct `buf_check_timestamp()` calls — in `do_ecmd()`, `enter_buffer()`
and `ex_drop()` — are deleted, because with the poll gone they are the only
thing keeping 339 lines of checking and reloading alive.

**`check_mtime()` stays.** `buf_write()` calls it before overwriting a file that
changed since it was read, and that is not polling: it happens only when the
user asks to write, and it is what stops a write silently clobbering someone
else's edit. `b_mtime_read` is still recorded on read, so it still works.

`'autoread'` cannot go — `PV_BOTH`, and its row is what initialises the global.
It stays, and now decides nothing.

### The delta

**None the harness records.** Nothing it does changes a file behind the editor's
back, so nothing it does reaches this code — which is worth stating rather than
glossing, because a phase with no delta is either well-chosen or untested, and
the only way to tell them apart is to say which you think it is.

## Phase 16 — a file name means the file of that name

`'path'` searching is the last of the three ways this editor knew where files
live, after globbing (Phase 9) and `'tags'` (Phase 12). `vim_findfile()` walks a
path list downward and upward, remembers directories it has visited so a symlink
loop cannot trap it, and can be asked for the second match and the third — 866
lines of filesystem-layout knowledge behind `:find`, `:sfind`, `:tabfind` and
`gf`.

`:find`, `:sfind` and `:tabfind` are retired: the whole of what they do is the
search.

**`gf` is kept, and resolves the name literally.** It is the one place a user
names a file from *inside the buffer* rather than on a command line, and taking
it away would be taking away the naming rather than the searching. So
`find_file_in_path()` stops consulting `'path'` and answers the only question
left — is there a file of this name? Fifteen lines against eight hundred and
sixty-six, and it reaches the filesystem no differently from `:e`.

Two details of the contract it has to keep, both visible in
`find_file_name_in_path()`: `first == FALSE` asks for the *next* match, which is
what `3gf` and `]f` use, and there is never a next one now — so it answers NULL
and the caller's loop ends, which is the same answer the search gave when the
path held one match. And the result is owned by the caller, so it is allocated
even though the name is already in hand.

`'path'` and `'suffixesadd'` cannot go — `PV_BOTH` and `PV_BUF`, and a row is
what initialises its global. They stay, and now decide nothing.

### The delta

`gf` opens the name under the cursor if there is a file of that name rather than
searching `'path'` for one. **No Ex command moves** — Phase 12's lesson again
rather than a surprise: retiring a command only shows in the sweep if it used to
*succeed*, and `:find`, `:sfind` and `:tabfind` already failed for want of an
argument.

## Phase 17 — the last two encoding options

**Phase 14 emptied `'fileencodings'` and said so, and it was true at startup and
not afterwards.** `set_option_default()` special-cases the option, so `:set
fencs&` restored `ucs-bom,utf-8,default,latin1` from `fencs_utf8_default` — a
third reference Phase 14 did not find, because it names the *string* rather than
the function the other two called. Measured on the shipped binary before this
was written:

```
  at startup           fileencodings=
  after :set fencs&    fileencodings=ucs-bom,utf-8,default,latin1
```

That is worth recording as a pattern and not just a fix. Phase 14 cut two
callers of `set_fencs_unicode()` and asked whether anything still called it;
nothing did. The question it did not ask was whether anything still used the
*value*, and a search for the function name cannot answer that.

Three readers go, and with them the two options can finally follow.
`set_option_default()` stops special-casing `'fileencodings'`, which is what
makes Phase 14's claim true at every moment rather than one. `readfile()` stops
choosing between an empty list and a list to walk, and takes the buffer's own
`'fileencoding'` — the branch the empty case already took. And
`did_set_encoding()` stops setting up a conversion between `'termencoding'` and
`'encoding'`, which `convert_setup()` has answered `CONV_NONE` to since Phase 14,
so the block could only ever have succeeded at doing nothing.

**`'encoding'` still cannot go, and here that stops being temporary.** `p_enc`
is the *name* of the one encoding, compared against in twenty-nine places.
Removing the option would mean removing the name, and the name is doing work.
Of the six encoding options this fork began with, one remains, and it reports
`utf-8` and refuses everything else.

### The delta

**None.** `:set fencs&` no longer restores a list of encodings this build cannot
convert between, which is a correction rather than a change.

## Phase 18 — six options that no longer decide anything

`'path'` and `'suffixesadd'` have been inert since the file finder went,
`'tags'` and `'tagcase'` since the tag stack, `'autoread'` since the timestamp
poll, and `'swapfile'` since the swap file. All six were still here, because a
row is what initialises its global and `tools/dropoptions.py` refuses to leave
one dangling — **Phase 12's trap, which this phase clears rather than works
around.**

### The order is the phase, and it is forced rather than chosen

1. the three readers that are not plumbing
2. the rows, with `--local`
3. **the sweep** — which is what removes `did_set_tagcase()` and
   `did_set_swapfile()`, the option callbacks, reachable only from the rows
4. the buffer fields and their plumbing
5. the sweep again

**Steps 3 and 4 cannot swap**, and the reason is a property of how this pipeline
sweeps rather than of the code. The callbacks read the buffer field, so removing
the field first stops the file compiling; the sweep works by reading gcc's
*warnings*, so a file that does not compile is a file the sweep cannot act on,
and the callbacks would stay for ever. Every other phase has been free to order
its cut however it liked; this one is not.

### The three that are not plumbing

`ex_drop()` set `'autoread'` on, checked the timestamp, and set it back —
and Phase 15 took the check out from between, so what was left was a variable
saved and restored across nothing at all. `do_set_option_bool()` special-cased
`:setlocal autoread` to mean "follow the global", the `-1` sentinel, and there
is no global to follow. `ml_open()` asked whether this buffer may have a swap
file; since Phase 13 the answer has been no whatever `'swapfile'` said, so it
now says no directly.

Everything else is the five fixed idioms every buffer-local option has — the
field in `buf_T`, the initialiser in `buf_copy_options()`, `check_buf_options()`,
`free_buf_options()`, and one or two `get_varp()` cases — which is what makes
`tools/droplocal.py` possible at all. It takes the *field* name rather than the
option's, because by the time it runs the row is already gone and there is
nothing left to look the field up from.

### The delta

**None.** All six report `E518: Unknown option` instead of a value that decided
nothing.

## Phase 19 — the last two per-buffer encoding options

`'fileencoding'` names the encoding a buffer was read in and will be written
back in, and `'bomb'` whether it had a byte-order mark. With one encoding and no
BOM, both have had one possible value since Phase 14 — but **unlike the six
Phase 18 took, these are not plumbing.** Eight functions read them, and each had
to be looked at:

| | what it wanted them for |
| --- | --- |
| `buf_write()`, `readfile()` | the conversion target, and whether to write a BOM |
| `bomb_size()` | how many bytes of the file are a BOM, for `g CTRL-G` |
| `save_file_ff()`, `file_ff_differs()` | remembering the pair, so `:w` can warn they changed |
| `utf_find_illegal()` (`g8`) | converting to the buffer's encoding to find a byte illegal in it |
| `add_b0_fenc()` | writing the name into a swap file's block zero |

None of those questions has more than one answer now, and the last has no swap
file to write into.

**What the options leave behind is a pair of remembered copies in `buf_T`** —
`b_start_fenc` and `b_start_bomb`, written on every read and looked at by
nobody. A struct field is not a variable, so no warning reports it and the
sweep cannot see it, which is why those are listed in the tool rather than left
to fall out. The same is true of `gvarp`, the local that asked *which* encoding
option was being set: there is one.

`'fileformat'`, `'endofline'` and `'endoffile'` can still change under a buffer,
so `file_ff_differs()` keeps those and loses only the two that cannot.

### The delta

**None.** Both report `E518` instead of a value with one possible setting. What
is left is `'encoding'`, alone, reporting `utf-8`.

## Phase 20 — nothing is read at startup that was not named on the command line

An editor that goes looking for its own configuration has a filesystem layout in
its head. `source_startup_scripts()` tried, in order:

```
$VIMRUNTIME/evim.vim      $VIMRUNTIME/defaults.vim      $VIM/vimrc
$VIMINIT                  $HOME/.vimrc                  $HOME/.exrc
./.vimrc                  ./.exrc
```

— the last two only with `'exrc'` on, and each guarded by an ownership check,
because reading a config file out of the current directory is a way to be handed
someone else's commands.

All of it goes. **`-u <file>` stays, and so does `:source`**: a file the user
names is not the editor going looking, and Phase 12 already settled `:source`.
`NONE`, `NORC` and `DEFAULTS` are still recognised as `-u` arguments and still
mean "read nothing" — which they now do by agreeing with everything else.

`set_init_xdg_rtp()` goes with them. It built a `'runtimepath'` out of
`$XDG_CONFIG_HOME`, and **Phase 1 emptied that option while this was still
filling it back in** — an option reported as empty and rebuilt at startup, which
is the kind of thing only a survey of every `getenv` finds. So does
`process_env()`, which ran `$VIMINIT` or `$EXINIT` as Ex commands, and `'exrc'`,
which selected between two searches that no longer happen.

### The delta

**None, and that is the point rather than a surprise.** Every harness passes
`-u NONE`, so none of these paths was taken in a recorded run. What changes is
that the editor no longer needs to be told.

That is also why this phase comes before the one that removes `-u` itself. The
option is what suppresses the search; while the search exists, dropping the
option would change every harness at once. Once nothing is searched for, `-u
NONE` is a no-op and the option can go without moving a single recorded output.

## Phase 21 — command-line options that no longer decide anything

Four outlived what they controlled, each in a different way.

| | why it is inert |
| --- | --- |
| `-y` | evim mode. `parmp->evim_mode` is assigned and read nowhere — its one reader was the line Phase 20 removed |
| `-Z` | restricted mode, whose purpose is to refuse shell commands. `check_restricted()` has two callers left: `do_bang()`, stubbed in Phase 10, and `ex_stop()`. No *live* command carries `EX_RESTRICT` either — the ten that do are all `ex_script_ni` |
| `-t` | jump to a tag at startup, by running `:ta <tag>`. Phase 12 retired `:tag`, so its whole effect is to run a command that reports it is not implemented |
| `-i` | the viminfo file. `'viminfo'` and `'viminfofile'` are wired to `(char_u *)NULL` in **both** editors — the tiny configuration has no viminfo at all |

**`-u <file>` stays.** Phase 20 removed every path the editor searched on its
own; a file the user names is not the editor going looking.

### The harnesses change, and that is the check

All three stop passing `-i NONE`, and `slim-vim` — which still has the option —
must still match its recorded baselines afterwards. It does. That is what proves
the option was a no-op *there* too, rather than only here: `-i NONE` has been
doing nothing for as long as this fork has existed, which is exactly why it was
passed for years without anyone noticing.

`set_init_restricted_mode()` goes with `-Z`, and is a small find of its own: it
read `$SHELL` at startup and turned restricted mode on when the answer was
`nologin` or `false`. An environment read, deciding a mode that restricts
nothing. `EX_RESTRICT` comes out of the twenty-four rows that carry it, because
a flag nothing reads is a concept the table still has and the code does not.

### Two cuts that landed in the wrong place first

Both are the same mistake and both were caught by the compiler rather than by
care. `case 't':` occurs in `get_c_indent()` as well, three thousand lines away
and about `'cinoptions'`, and a substitution with `count=1` takes whichever comes
first *in the file* — the first attempt cut a branch out of the C indenter.
`char_u *tagname;` is also a field of `taggy_T`, seventeen hundred lines
earlier. Everything that edits the option parser is now applied to
`command_line_scan()`'s body alone, and the struct field is anchored on `int
edit_type;`, which sits immediately above it and nowhere else.

### The delta

**None.**

## Phase 22 — the terminal is what the build says

Five environment variables describe the terminal and the editor believed all of
them: `$TERM` picks a capability table, `$LINES` and `$COLUMNS` override the size
the kernel reports, `$COLORS` overrides the colour count, `$COLORFGBG` the
background.

### The compiled name is `xterm-256color`, and that is the whole care here

Measured on the shipped binary before choosing:

```
TERM=xterm-256color   -> term=xterm-256color  t_Co=256
TERM=xterm            -> term=xterm           t_Co=8
TERM= (unset)         -> term=xterm           t_Co=8
```

`set_termname()` keeps the *requested* name and tests
`strstr(requested, "256color")` to apply `builtin_256colors` on top of whichever
table it chose. So **the obvious fallback — the one the unset case already took
— would have cost eight of every nine colours the terminal can show**, silently,
for nothing. `xterm-256color` resolves to the same `builtin_xterm` table and
keeps the add-on.

### The size is still autodetected

`ioctl(TIOCGWINSZ)` stays; only the `$LINES`/`$COLUMNS` override goes. Verified
on a pty: with the window at 24×80 and `LINES=9 COLUMNS=9` in the environment,
the editor reports 24×80. An editor that believes `$LINES` over the kernel is
one that draws off the bottom of a resized window.

`-T <term>` stays. It is not the environment, and with one compiled default it
is the only way left to say "this is a dumb terminal"; the ten built-in entries
are still there and `-T` still reaches them.

### The delta

**The terminal table collapses.** Nineteen rows, one per `TERM` the harness
tries, each of which used to resolve to its own entry — now every one of them,
including unset and `no-such-term-9x`, answers `term=xterm-256color t_Co=256`.

That is declared with `--term-moved`, which `tools/puredelta.sh` grew for this
phase. Until now no phase could move that table, so *"expected unchanged"* was
the whole check; a phase that makes every terminal resolve to one entry has to
be able to say so, and the flag asserts the table moved rather than merely
allowing it to.

### `cutil.drop_if`, extracted here

Four phase tools had written their own "delete an `if` and the block it guards",
and four had written the same bug: a lazy `(?:[^\n]*\n)*?\}` to find the end,
which stops at the first line that is only a brace — an inner block's, whenever
there is one. This phase made it five. It is one function in `cutil.py` now,
brace-matched, refusing a block that has an `else`.

## Phase 23 — there is no home directory

`$HOME` is where an editor keeps the things it was told not to keep. This fork
stopped writing them in Phase 13 and stopped looking for them in Phase 20, and
what was left is the *notion* of a home directory — `~/x` meaning a path, `~bob`
meaning someone else's, and `/home/you/x` displayed back as `~/x`.

All three go, and the last is why this is not only a `getenv` removal:
`home_replace()` has **thirteen callers**, every one a place that shows the user
a file name. It becomes a bounded copy, so the thirteen keep working and a name
is shown as what it is.

The user database goes with them — `init_users()`, `add_user()`, `match_user()`
and `get_users()` exist so that `~bob` can complete, and `mch_get_uname()` so
that a swap file could say who wrote it. Two smaller things fall out and had to
be taken by hand, because `-Wunused-but-set-variable` is not a shape the sweep
deletes: `at_start`, which existed only to know whether a `~` began a path, and
`startstr_len`, measured for the one test that used it.

### Where the symbol count moves

`getpwnam`, `getpwent`, `setpwent`, `endpwent` — 119 → 115. CLAUDE.md notes that
`getpwnam()` working under static musl is one of the two things that make this
binary honestly standalone. It no longer needs it.

### Two corrections to what this phase was planned to do

**`getuid` and `getgid` do not go.** `buf_write()` uses them to check ownership
before overwriting a read-only file and to preserve owner and group. That is
file writing, which pure-vim keeps, and the plan was wrong to list them here.

**`getpwuid` does not go either.** `mch_get_uname()` is still reached from
`swapfile_info()`, under `-r`, which lists swap files that cannot exist — Phase
13 removed the swap file and left the option that reads them. That wants a phase
of its own rather than a corner of this one: `ml_recover()` alone is 559 lines,
`recover_names()` 216 and `swapfile_info()` 103.

### The delta

**None the harness records.** `:e ~/notes` opens a file called `~/notes` in the
current directory, which no harness asks for.

`--term-moved` is **cumulative**, like the command list — the comparison is
always against the slim baseline, and Phase 22 collapsed that table for good, so
every phase after it declares the same thing. Discovered by this phase failing
when it did not.

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
27,865 lines, about a sixth of the file. Measured after Phase 8:

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
