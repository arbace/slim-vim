# WHIM-GOAL.md — reduce slim-vim to an embedded editor

`slim-vim.c` is vim as one translation unit, with every feature upstream's
`tiny` configuration has. **`whim-vim.c` is what is left when the editor stops
expecting a filesystem to have been installed for it.**

```
slim-vim.c = F(upstream@sha)          SLIM-GOAL.md, ten phases
whim-vim.c = G(slim-vim.c)            this document
```

The two pipelines are the same construct — a phase is a function of the tree it
is handed, memoized in three tiers — and differ only in what they remove.
`SLIM-GOAL.md` removes *files and preprocessor* and changes nothing about what
the editor can do. **This one removes capability, on purpose**, and every phase
has to say which and prove it removed nothing else.

## The charter

Whim vim is an **embedded** editor: one static binary, no installation, nothing
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
   an option default, a branch of the environment layer — and let the sweep
   find what becomes unreachable: all six kinds of dead thing, in every phase
   (see *The sweep*). A phase that names 900 functions to
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
4. **`whim-vim.c` is produced from the committed `slim-vim.c`**, not from a
   pass. The two pipelines are decoupled: `make whim-vim` needs no clone, no
   network and no agent, and the memoize key is `slim-vim.c`'s digest and the
   implementation's, exactly as the other pipeline keys on upstream's sha.

## The sweep, and what unreachable covers

Every phase ends the same way: `tools/sweep.sh` deletes what the phase's cut
left unreachable, to a fixpoint, because each kind of dead thing orphans the
others — deleting a function orphans a type, deleting a type orphans a
prototype, deleting a field orphans an enumerator. **Six kinds, in every
phase:**

| | by what | islands? |
| --- | --- | --- |
| functions | `deadsweep.py` (gcc) and `funcreach.py` | yes — reachability |
| prototypes | `deadprotos.py` | n/a |
| types | `typereach.py` | yes — reachability |
| variables | `deadsweep.py`, `-Wunused-variable` | no — reference counting |
| struct fields | `deadfields.py` | no — a mention outside every type definition |
| enumerators | `deadenums.py` | no — a mention anywhere |

**The last two are covered by no warning at all**, and for a while they were
covered by no sweep either. A phase of its own asserted them, part way through
the pipeline and then again at the tip, because the first assertion had been
followed by nine phases that orphaned 40 more fields and 14 more enumerators and
nothing in their own sweeps noticed. **An invariant asserted in one place is a
cleanup.** Asserted in every sweep, it holds at every boundary, and no phase is
ever handed dead code by the one before it.

**A struct field is not a variable.** `deadfields.py` calls a field live if its
name appears outside every type definition, since a mention inside another struct
is a different field with the same name. It refuses what it cannot be sure of,
because being wrong here is silent:

- a bitfield or anonymous member, whose declaration does not say plainly what
  it declares;
- the last field of a struct, since an empty struct is not C and whole types
  are `typereach.py`'s;
- any field of a type that is ever initialised positionally.
  `static termrequest_T crv_status = {STATUS_GET, -1};` fills two fields and
  names neither, so the second looks dead, and removing it gives *"excess
  elements in struct initializer"* — a warning, not an error, which a sweep keyed
  on errors would have shipped;
- **every field, while `ml_recover()` exists.** Removing a field moves the ones
  after it, and until the editor cannot read a swap file, block zero and the
  memfile's pages are a disk format: a field nothing in the code reads is still
  a field another vim wrote. The question is asked of the file rather than of a
  phase number, so the field sweep starts by itself in the phase that removes
  recovery — and never in `slim-vim.c`, which keeps it. Measured: no phase before
  Phase 21 removes a field, and Phase 21 removes 80.

**An enumerator's value is its position**, so deleting one renumbers every
implicit one after it, and several enums index a parallel table. `deadenums.py`
reads the values from DWARF — `tools/enumvals.sh`, where the compiler has already
done the arithmetic for `1 << 3` and `0x80000000L` — pins the first survivor
after each deleted run, and dumps DWARF again after the sweep to require that no
survivor moved. The dump costs a debug build, so it is taken **on first need**:
most sweeps find no dead enumerator and never pay for it. A survivor DWARF has no
value for cannot be pinned, so the run before it stays — an unpinned survivor
renumbers silently, and a before-and-after comparison cannot see a name that is
in neither dump.

### The bug that asking about fields found first

`typereach.py` had a blind spot that no amount of new tooling would have
covered. `START` matched `struct X {` with the brace on the same line, and
**111 of this file's type definitions put the brace on the next line**. Those
were not definitions as far as the tool was concerned, so every field inside
them counted as a *root* — and a whole dead island lived on because of it:
`channel_T` is mentioned exactly twice outside its own definitions, and both are
fields, `jv_channel` in `jobvar_S` and `ch_next` in `channel_S`. `jobvar_S` was
invisible, so `jv_channel` was a root, so the `+channel` and `+job` types sat
there complete, long after every function that used them had gone.

Recognising the form took two goes, and both failures are the same shape as the
`deadsweep` bug in Phase 24:

1. `static struct modmasktable { … } mod_mask_table[] = { … };` is a type
   definition **and a variable** in one construct, and the declarator sits
   between the *struct's* closing brace and the `=` — not after the last `}`,
   which belongs to the initialiser. So the name was never collected, the tag
   was unreachable, and the whole construct went, leaving `mod_mask_table[i]`
   undeclared 40,000 lines away. A construct that declares a variable is not a
   type definition to delete; it is a variable, and `deadsweep.py` owns those.
2. `typedef struct { … } chanpart_T;` does **not** declare a variable — there
   the declarator names the type — so the rule above had to exclude typedefs.

Fixed, it removes **378 lines** on its own, and it made every sweep stronger.


## Phase 0 — seed, and prove the copy is a copy

`whim-vim.c` starts as a byte-for-byte copy of `slim-vim.c`, and the phase's
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
against `slim-vim`'s recorded baselines, and then records `whim-vim`'s own.

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

## Phase 3 — no introduction, and the command line says only what the editor still decides

**An embedded editor starts in a buffer, not on a title card, and is started by
something that knows what it wants.** This was two phases with a third's worth
of work left undone between them. They were one question — *what may an
invocation say?* — and are answered once.

### The introduction

- **`:intro` and `:version` point at `ex_ni`.**
- **The splash screen's two call sites go.** `maybe_intro_message()` is called
  from the *redraw path* when the buffer is empty and no file was named. It is
  not a command, so an editor whose `:intro` was `ex_ni` would still greet you
  on startup.
- **`-h`, `-?`, `--help` and `--version` go**, and with them `usage()` and
  `list_version()`, which `--version` was the other door to.

That last is where the removal pays. With `list_version()` gone the sweep takes
the version tables, the feature lists, and `pathdef`'s `compiled_user` and
`compiled_sys`, which bake the *building machine's hostname* into the binary.
Measured: the name appears once in this phase's input and nowhere in its output.
That is worth removing on an embedded artifact's account and worth removing
twice on a reproducible one — a binary that names the machine that built it
cannot be byte-identical anywhere else.

### The command line

`tools/dropopts.py` deletes each option's `case` label or `else if` link, so the
option reaches `mainerr(ME_UNKNOWN_OPTION)` — the path anything unrecognised
already takes. `tools/optreaders.py` then removes what only a dropped option
could ever set, and every reader of it, because a field nothing sets is still
*read*: no warning names it and no sweep can take it.

| | options | |
| --- | --- | --- |
| **refusing** | `-A`, `-F`, `-H`, `-g`, `-nb` | print "not enabled at compile time" and exit — what an unknown option does anyway, one message less specifically |
| **inert** | `-f`, `-X`, `-Y`, `-d`, `-U`, `--nofork`, `--literal`, `--gui-dialog-file`, `--startuptime`, `--log` | accepted with an empty body, or an argument that goes nowhere |
| **said another way** | `-l`, `-C`, `-N`, `-V`, `--noplugin` | each is a `:set` — `lisp showmatch`, `compatible`, `nocompatible`, `verbose` and `verbosefile`, `noloadplugins` |
| | `-n` | `'updatecount'` to 0, so no swap file is written; `:set updatecount=0` says the same, and from Phase 11 there is no swap file on disk to avoid |
| | `-p` | the files as tab pages; `-o` and `-O` still lay them out as windows |
| | `--clean` | `-u DEFAULTS`, and empty defaults for `'runtimepath'` and `'packpath'` |
| **a capability** | `--not-a-term` | see below |

**`--not-a-term` goes on purpose, and it is the one that removes something.** It
told a full-screen run with no terminal not to warn, not to wait, and not to
restore a title. Without it that run warns and waits two seconds, as it did
before the option existed. An embedded editor is given a terminal or run with
`-e`, and every harness here runs `-e -s`.

What goes with them, found by `optreaders.py` rather than by the sweep:
`early_arg_scan()`, which existed to refuse `-nb` before anything else ran; the
pre-scan of `argv` at the top of `main()` that set `params.clean` before options
existed, `set_init_1()`'s parameter, and `set_init_clean_rtp()`; `is_not_a_term()`
and `is_not_a_term_or_gui()`, whose eight callers each keep the branch they took
without the option; the reader that turned `-n` into `'updatecount'`;
`WIN_TABS` at seven tests in `create_windows()` and `edit_buffers()`,
`p_shm_save`, and `make_tabpages()`; and `More info with: "vim -h"`, which ended
every usage error by naming a removed option and a binary this one is not.

**Not here:** `-y`, `-Z`, `-t` and `-i` go in Phase 18, and `-r` and `-L` in
Phase 21, each with the capability it selected — a flag is pointless only once
the thing it chose is gone.

### The trap, and the harness it needed

`dropopts.py` removed a long option's `else if` and then asked whether the text
*before* it ended in `else` — which it never did, because the match had already
consumed that `else`. So removing **any** link turned the next `else if` into a
bare `if`, and the chain came apart: `--clean`, `--noplugin` and `--not-a-term`
each matched their own branch, failed every test after it, and reached `mainerr`
anyway. **Three options broken for thirty phases, and nothing noticed, because no
harness passed a single option** — `behaviour.py`, `exsweep.py` and
`termcheck.py` all run `-u NONE -e -s` and nothing else. The removed link's own
`else` decides now.

`tools/clicheck.py` is the harness that was missing. It runs every option the
parser has. A dropped one must exit 1 naming itself as unknown; a kept one must
not, and must do what it says wherever `:set`, a file or an exit status can show
it — `-c`, `+`, `--cmd`, `-S` and `-u` each set an option the run then reports,
`-b`, `-R`, `-m`, `-M` and `-w7` report theirs, `-W` and `-w` write their file,
`-v` leaves Ex mode and so warns that there is no terminal, and `--ttyfail`
exits 1. "It did not complain" is accepted only for `-s`, `-o`, `-O`, `-T`, `-`
and `--`, whose effects need a terminal to see. **Proven able to fail:** against
`slim-vim` 30 of its 52 cases are wrong, and against the `whim-vim` built before
this phase 12 are — every option this phase newly drops that still worked,
counting `-p2` and `-V9`.

`case 'X':` also appears in more than one switch in this file — the normal-mode
tables and `get_c_indent()` have their own — so everything `dropopts.py` does is
bounded by `command_line_scan()`'s own text, and a label it removes from one of
the parser's two switches it removes from the other.

### The delta

Cumulative against slim-vim's baselines: `:helpclose` from phase 1, and now
`:intro` and `:version`, which succeed in slim-vim and report E319 here. Nothing
else may move — and the pty scenarios are the ones to watch, since a startup
screen is exactly the kind of thing a terminal harness records. The command line
is `clicheck.py`'s to check, because nothing else ever passes an option.

Measured: **180,333 → 178,436 lines**, 1,368 of them taken by the sweep in three
rounds, and libc symbols 146 → 146 — the introduction and the command line were
never what the editor needed from the world.

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
| `-e` Ex mode | `-E` improved Ex | |

`diff` is not among them because it never selected a mode here: this build has
no diff feature, and the name only ever printed that and exited. `-d`, which
looks like its option, was an argument that went nowhere, and Phase 3 dropped
it.

**Corrected:** an earlier draft of this section claimed `view` set
`'undolevels'` to 10000 where `-R` did not. It is wrong. `p_uc = 10000` appears
at both sites in `slim-vim.c` — once in the `view` branch and once in the `-R`
case — so the two are exactly equivalent and the removal loses nothing at all.
The claim was written from the name-parsing code without checking the option
beside it, which is the mistake this document warns about everywhere else.

**The delta: none.** The harnesses stage the binary as `vim`, which selected
plain vim mode before and selects it now, so nothing they record can move. The
evidence is the score — and the fact that `whim-vim` can now be called anything
at all.

## Phase 5 — one regexp engine, not two

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

## Three phases moved to SLIM-GOAL.md

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

The third followed them later. "The table moves below what it names" moved
`cmdnames[]` below its handlers so the declarations it forced could go with the
rest, and that is a fact about a translation unit too: it is part of slim's
Phase 10 now.

## Phase 6 — the editor stops writing shell scripts, and stops drawing a menu

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
accepted and now does nothing is what Phase 3 exists to prevent.

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

## Phase 7 — the editor stops looking for files it was not given

Two removals that are the same thing seen from two sides: the editor asking the
filesystem what is around the file it was handed.

### Wildcards, the rest of the way

Phase 6 removed the expander that wrote shell scripts. This removes the
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
being a check. It also says something about Phase 10: the swap file is already
half unreachable.

Cumulatively: `helpclose intro version cd chdir lcd lchdir tcd tchdir pwd
recover`.

## Phase 8 — `:!` keeps its name and loses its process

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
opendir pipe readdir rmdir setsid stdin waitpid`. **This is the first whim
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

## Phase 9 — the editor stops asking the environment what language it is in

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
the machine**, which is the whole point, and it is what Phase 10 builds on.

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
`(char_u *)NULL` — they accept a value and store it nowhere. They are Phase 3's
rule arriving late rather than a new decision, and no behaviour can change.

### The delta

`:language` reports that it is not available. Nothing else: the process runs in
the C locale now, which is what it was already running in for every purpose this
build has. `setlocale`, `nl_langinfo` and `strcoll` leave the symbol table.

## Phase 10 — no tag stack

A tag jump is the editor discovering, on its own, that a file it was never told
about exists. `get_tagfname()` walks `'tags'` upward from the current file,
opens whatever it finds and binary-searches it — filesystem-layout knowledge of
exactly the kind Phase 7 removed from `'path'`, and the largest single item
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

## Phase 11 — nothing is written that was not asked for

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

**The automatic timestamp check remains**, for now. `check_timestamps()` is
still called from `main_loop()`, `edit()` and `wait_return()`, so the editor
still notices a file changing underneath it — retiring `:checktime` removed the
command, not the polling. That is a separate cut with a separate delta, and
**Phase 13 is where it happens**.

### The delta, and three things the harness knew better than the author

Eight command names report that they are not available; `'updatecount'` and
`'swapsync'` stop existing. `'swapfile'` cannot go — it is
`PV_BUF` and its row is what initialises the global, the trap Phase 10 records —
so it stays and is now always effectively off.

### `'directory'` was dropped here once, and that was a bug

It is in the list above no longer, and the correction is worth more than the
line it takes. A row is also what **initialises** its global, so a row can only
go once nothing reads the global — and `recover_names()` scans every directory
in `p_dir` looking for swap files, right up until Phase 21 deletes it. Dropping
the row here left `p_dir` NULL for ever, with a live dereference in
`check_overwrite()`, which asks whether *another* vim has a swap file beside the
file you are about to overwrite. So this shipped for twelve phases:

```
:w! <an existing other file>      ->      Segmentation fault
```

**Nothing saw it, and each reason is worth knowing.** The build is clean. The
dead-code sweep is silent, because an orphaned global is *used* — no
unused-variable warning names it. The linkage and symbol checks pass. The Ex
sweep runs every command from its own scratch directory, where the target does
not exist; the 67 behaviour cases write to the file they opened; and neither
writes over an existing file *under a different name* with `!`, which is the one
shape that reaches it.

`dropoptions.py --strict` refuses exactly this and did not exist when this phase
was written. The repair has three parts, and only the first is about this bug:

1. `'directory'` moves to Phase 21, where its last reader goes. Phase 11 keeps
   the row, so `p_dir` is initialised for every phase in between.
2. `tools/orphanopts.py` runs in **every** whim phase, out of `whimdelta.sh`. It
   parses `options[]`, collects every `&p_xx` it names, and compares that with
   every `p_xx` declared at file scope. It is type-aware, which is the whole
   trick: a `long` orphan reads as 0 and is reported, a `char_u *` orphan is
   fatal. `'updatecount'` is genuinely safe to drop here for that reason —
   `p_uc` reading 0 *is* "never create a swap file".
3. `--strict` learned that `varp == (char_u *)&p_x` takes an address rather than
   reading a value. Counting those made it refuse `'directory'` in Phase 21,
   where the row genuinely was inert — a guard that cries wolf gets turned off,
   which would have cost more than the bug did.

`mf_sync()`'s `MFS_FLUSH` tail goes here too, as the last reader of `p_sws`, and
takes `sync()` with it. It sat behind `if (mfp->mf_fd < 0) return FAIL;` and so
was never reached — latent rather than live, and removed for the same reason.

`:mksession` and `:mkview` **do not move**: they already failed. And `:recover`
**leaves** the cumulative list it joined in Phase 7 — removing globbing had
made it fail differently from the slim baseline, and `ex_ni` makes it fail the
same way again, so it stops being a difference. A cumulative delta can shrink,
which is not something a list maintained by hand would ever discover.

## Phase 12 — UTF-8, and no other encoding, ever

Phase 9 made `'encoding'` a property of the build rather than of the machine.
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
| `'fileencoding'`, `'bomb'` | `PV_BUF`, the trap Phase 10 recorded |

**A row is what initialises its global.** Phase 10 found that for a
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
is about to delete. Phase 2 (`'spell'`) and Phase 5 (`'regexpengine'`) both
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

## Phase 13 — the editor stops re-reading a file it has already read

vim watches the files it holds. `check_timestamps()` walks every buffer and
stats its file — from the main loop, from insert mode, from the `Press ENTER`
prompt, and whenever the terminal regains focus — and `buf_check_timestamp()`
does the same for one buffer on entering it. If the file moved underneath it
prompts, and with `'autoread'` it reloads.

That is the editor initiating filesystem traffic on its own account, which is
the boundary this fork narrows. **Phase 11 retired `:checktime`, which removed
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

## Phase 14 — a file name means the file of that name

`'path'` searching is the last of the three ways this editor knew where files
live, after globbing (Phase 7) and `'tags'` (Phase 10). `vim_findfile()` walks a
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
searching `'path'` for one. **No Ex command moves** — Phase 10's lesson again
rather than a surprise: retiring a command only shows in the sweep if it used to
*succeed*, and `:find`, `:sfind` and `:tabfind` already failed for want of an
argument.

## Phase 15 — the last two encoding options

**Phase 12 emptied `'fileencodings'` and said so, and it was true at startup and
not afterwards.** `set_option_default()` special-cases the option, so `:set
fencs&` restored `ucs-bom,utf-8,default,latin1` from `fencs_utf8_default` — a
third reference Phase 12 did not find, because it names the *string* rather than
the function the other two called. Measured on the shipped binary before this
was written:

```
  at startup           fileencodings=
  after :set fencs&    fileencodings=ucs-bom,utf-8,default,latin1
```

That is worth recording as a pattern and not just a fix. Phase 12 cut two
callers of `set_fencs_unicode()` and asked whether anything still called it;
nothing did. The question it did not ask was whether anything still used the
*value*, and a search for the function name cannot answer that.

Three readers go, and with them the two options can finally follow.
`set_option_default()` stops special-casing `'fileencodings'`, which is what
makes Phase 12's claim true at every moment rather than one. `readfile()` stops
choosing between an empty list and a list to walk, and takes the buffer's own
`'fileencoding'` — the branch the empty case already took. And
`did_set_encoding()` stops setting up a conversion between `'termencoding'` and
`'encoding'`, which `convert_setup()` has answered `CONV_NONE` to since Phase 12,
so the block could only ever have succeeded at doing nothing.

**`'encoding'` still cannot go, and here that stops being temporary.** `p_enc`
is the *name* of the one encoding, compared against in twenty-nine places.
Removing the option would mean removing the name, and the name is doing work.
Of the six encoding options this fork began with, one remains, and it reports
`utf-8` and refuses everything else.

### The delta

**None.** `:set fencs&` no longer restores a list of encodings this build cannot
convert between, which is a correction rather than a change.

## Phase 16 — six options that no longer decide anything

`'path'` and `'suffixesadd'` have been inert since the file finder went,
`'tags'` and `'tagcase'` since the tag stack, `'autoread'` since the timestamp
poll, and `'swapfile'` since the swap file. All six were still here, because a
row is what initialises its global and `tools/dropoptions.py` refuses to leave
one dangling — **Phase 10's trap, which this phase clears rather than works
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
and Phase 13 took the check out from between, so what was left was a variable
saved and restored across nothing at all. `do_set_option_bool()` special-cased
`:setlocal autoread` to mean "follow the global", the `-1` sentinel, and there
is no global to follow. `ml_open()` asked whether this buffer may have a swap
file; since Phase 11 the answer has been no whatever `'swapfile'` said, so it
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

## Phase 17 — the last two per-buffer encoding options

`'fileencoding'` names the encoding a buffer was read in and will be written
back in, and `'bomb'` whether it had a byte-order mark. With one encoding and no
BOM, both have had one possible value since Phase 12 — but **unlike the six
Phase 16 took, these are not plumbing.** Eight functions read them, and each had
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

## Phase 18 — nothing is read at startup, and nothing on the command line decides anything

### nothing is read at startup that was not named on the command line

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
names is not the editor going looking, and Phase 10 already settled `:source`.
`NONE`, `NORC` and `DEFAULTS` are still recognised as `-u` arguments and still
mean "read nothing" — which they now do by agreeing with everything else.

`set_init_xdg_rtp()` goes with them. It built a `'runtimepath'` out of
`$XDG_CONFIG_HOME`, and **Phase 1 emptied that option while this was still
filling it back in** — an option reported as empty and rebuilt at startup, which
is the kind of thing only a survey of every `getenv` finds. So does
`process_env()`, which ran `$VIMINIT` or `$EXINIT` as Ex commands, and `'exrc'`,
which selected between two searches that no longer happen.

#### The delta

**None, and that is the point rather than a surprise.** Every harness passes
`-u NONE`, so none of these paths was taken in a recorded run. What changes is
that the editor no longer needs to be told.

That is also why this phase comes before the one that removes `-u` itself. The
option is what suppresses the search; while the search exists, dropping the
option would change every harness at once. Once nothing is searched for, `-u
NONE` is a no-op and the option can go without moving a single recorded output.

### command-line options that no longer decide anything

Four outlived what they controlled, each in a different way.

| | why it is inert |
| --- | --- |
| `-y` | evim mode. `parmp->evim_mode` is assigned and read nowhere — its one reader was the line Phase 18 removed |
| `-Z` | restricted mode, whose purpose is to refuse shell commands. `check_restricted()` has two callers left: `do_bang()`, stubbed in Phase 8, and `ex_stop()`. No *live* command carries `EX_RESTRICT` either — the ten that do are all `ex_script_ni` |
| `-t` | jump to a tag at startup, by running `:ta <tag>`. Phase 10 retired `:tag`, so its whole effect is to run a command that reports it is not implemented |
| `-i` | the viminfo file. `'viminfo'` and `'viminfofile'` are wired to `(char_u *)NULL` in **both** editors — the tiny configuration has no viminfo at all |

**`-u <file>` stays.** Phase 18 removed every path the editor searched on its
own; a file the user names is not the editor going looking.

#### The harnesses change, and that is the check

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

#### Two cuts that landed in the wrong place first

Both are the same mistake and both were caught by the compiler rather than by
care. `case 't':` occurs in `get_c_indent()` as well, three thousand lines away
and about `'cinoptions'`, and a substitution with `count=1` takes whichever comes
first *in the file* — the first attempt cut a branch out of the C indenter.
`char_u *tagname;` is also a field of `taggy_T`, seventeen hundred lines
earlier. Everything that edits the option parser is now applied to
`command_line_scan()`'s body alone, and the struct field is anchored on `int
edit_type;`, which sits immediately above it and nowhere else.

#### The delta

**None.**

## Phase 19 — the terminal is what the build says

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

That is declared with `--term-moved`, which `tools/whimdelta.sh` grew for this
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

## Phase 20 — nothing outside the process is consulted

### there is no home directory

`$HOME` is where an editor keeps the things it was told not to keep. This fork
stopped writing them in Phase 11 and stopped looking for them in Phase 18, and
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

#### Where the symbol count moves

`getpwnam`, `getpwent`, `setpwent`, `endpwent` — 119 → 115. CLAUDE.md notes that
`getpwnam()` working under static musl is one of the two things that make this
binary honestly standalone. It no longer needs it.

#### Two corrections to what this phase was planned to do

**`getuid` and `getgid` do not go.** `buf_write()` uses them to check ownership
before overwriting a read-only file and to preserve owner and group. That is
file writing, which whim-vim keeps, and the plan was wrong to list them here.

**`getpwuid` does not go either.** `mch_get_uname()` is still reached from
`swapfile_info()`, under `-r`, which lists swap files that cannot exist — Phase
13 removed the swap file and left the option that reads them. That wants a phase
of its own rather than a corner of this one: `ml_recover()` alone is 559 lines,
`recover_names()` 216 and `swapfile_info()` 103.

#### The delta

**None the harness records.** `:e ~/notes` opens a file called `~/notes` in the
current directory, which no harness asks for.

`--term-moved` is **cumulative**, like the command list — the comparison is
always against the slim baseline, and Phase 19 collapsed that table for good, so
every phase after it declares the same thing. Discovered by this phase failing
when it did not.

### nothing is read from the environment

The third and last of the standalone phases. Phase 18 stopped reading
configuration files, Phase 20 stopped believing in a home directory, and this
one removes the environment itself — after it, no answer this editor gives
depends on how it was invoked.

**`vim_getenv()` had already been half dead, and that is what makes this
phase small.** Phase 1 folded its `vimruntime` flag to FALSE, so
`vim_getenv("VIMRUNTIME")` had been returning NULL unconditionally ever since,
and `"VIM"` was the only name left that could reach the `$VIM`/`'helpfile'`
fallback chain — which nothing asks for any more. So the function **can only
ever answer "not set"**, and every caller collapses to the branch it was
already taking:

| what it read | what took its place |
| --- | --- |
| `$VAR` in a file name (`expand_env_esc`) | the name, as written |
| `$PATH` (`expand_shellcmd`) | the pattern's own directory |
| `$VIMRUNTIME` (`fix_help_buffer`) | the `*local-additions*` scan, 111 lines, already a no-op |
| `$SHELL`, `$CDPATH`, `$VIM_POSIX` | the compiled-in defaults |
| `$TMPDIR`, `$TEMP`, `$TMP` | `/tmp`, which was always in the list |
| `$COLORFGBG` | what Phase 19 decided the terminal is |
| `$TZ` | `localtime_r`, which does the zone setup itself |
| `$VIM`, `$VIMRUNTIME`, `$MYVIMDIR`, written | nothing writes them |
| `environ`, walked for `$VAR` completion | the row and its `$`-prefix context go, as `~user`'s did |

`expand_env_esc` is the same answer Phase 20 gave `home_replace`: with the `$`
arm gone what remains is `skipwhite`, the backslash escape and the bound on
`dstlen`, and a name reaches its caller intact.

**`vimrc_found()` was already unreachable**, and finding that out is what kept
this phase from being an argument about whether `$VIM` should still be
published. Every `do_source()` call in the file passes `DOSO_NONE`, so the two
arms that called it have been dead since Phase 18. Deleting them takes
`vim_setenv`, `export_myvimdir` and `$MYVIMDIR` with them.

#### The check is the object, not the source

`getenv`, `setenv`, `unsetenv` and `environ` leave `nm -u`: **115 → 110**, the
fifth being `tzset`. Grepping the source is not sufficient and the phase does
both — the sweep is what removes `vim_getenv`, so asking before it runs gets
the wrong answer, which this pipeline has now learned four times.

#### What stays

`vim_localtime()` still calls `localtime_r()`, and musl reads `$TZ` inside it.
The rule this phase enforces is that *this source* asks the environment
nothing; making a file's timestamp display in UTC would be a different
decision, and not this one.

#### The delta

**None the harness records.** `:w $FOO.txt` writes a file called `$FOO.txt`,
`:e $HOME/notes.txt` needs a directory literally named `$HOME`, and
`:set shell?` says `sh` whatever `$SHELL` was — verified by hand, none of it
something a harness asks for.

## Phase 21 — there is nothing to recover, and the memfile is memory

### there is nothing to recover

Phase 11 made the swap file memory-only: the block structure is still built,
still paged, still where every line of the buffer lives, but it never reaches a
disk. What that left behind is the other half of the feature — the code that
reads *someone else's* swap file back, which is code for reading a file this
editor cannot have written.

`-r` and `-L` are the only two things that ever set `recoverymode`, so the
global folds to FALSE and its seven readers each collapse to the branch they
were already taking. Three of them are in `readfile()`, which had to know
whether it was filling a buffer from a swap file rather than from the file
itself; the other four are the two `-r`-with-no-file arms, the stdin arm, and
the recovery arm of `create_windows()`. `ml_recover()` (559 lines),
`recover_names()` (216) and `swapfile_info()` (103) go with them.

**This is where `getpwuid` goes** — the fifth of the five password-database
symbols, and the one Phase 20 said would need a phase of its own.
`swapfile_info()` called `mch_get_uname()` to say who owned a swap file.

`:recover` was pointed at `ex_ni` earlier and does not move. It already failed,
needing a swap file to read — which is Rule 3's other half: retiring a command
only shows in the Ex sweep if it used to *succeed*.

#### Time, which is the part that is a decision rather than a consequence

`swapfile_info()` was the only caller of `get_ctime()`, which left
`vim_localtime()` with exactly one user: `add_time()`, the timestamp in
`:undolist` and in `1 change; before #3`. It is dropped too, and **not because
it is unreachable**. `localtime_r()` asks libc what the local zone is, and
Phase 20 took away every way this editor could be told; a wall-clock time
without a zone is a wrong answer rather than a partial one. Undo history does
not outlive the process either — `:wundo` and `:rundo` have been `ex_ni` since
Phase 11 — so every time `add_time()` formats is within one session, and the
relative form it already used below 100 seconds is the true one. `strftime` and
both format strings go with it, and `:undolist` now reads `1 second ago` where
it used to read `14:23:07`.

#### Where the symbol count moves

**110 → 107**: `getpwuid`, `localtime_r`, `strftime`.

#### The delta

**None.** Verified by hand: `-r` is now `Unknown option argument: "-r"`,
`:undolist` prints `1 second ago`, and editing is untouched.

### the memfile is memory, and only memory

Phase 11 stopped the editor creating a swap file and Phase 21 stopped it reading
one back. What was left is a **file back-end with no file**: `memfile_T` still
carried a descriptor, still knew how to page a block out and read it in, and
still sized an LRU cache against how much memory the machine has — all of it
behind `if (mfp->mf_fd >= 0)`, and `mf_fd` could no longer be anything but −1.

The proof is short. `mf_open()` has two callers: `ml_open()` passes `(NULL, 0)`,
and `ml_recover()` passed a name — Phase 21 deleted it. Phase 11 stubbed
`ml_open_file()` to `b_may_swap = FALSE`. So nothing can hand the memfile a
name, `mf_do_open()` is unreachable, and `mf_write()` and `mf_read()` return
FAIL on their first lines.

Which makes **`'maxmem'` and `'maxmemtot'` options that decide nothing**:

```c
need_release = (mfp->mf_used_count >= mfp->mf_used_count_max
                || (total_mem_used >> 10) >= (long_u)p_mmt);
...
if (mfp->mf_fd < 0 || !need_release) { return NULL; }
```

`need_release` is the only place either is read, and the test in front of it is
always true — so the answer is computed and discarded. `mch_total_mem()` went to
real trouble to size that cache, through `sysinfo`, `sysconf` and `getrlimit`,
for a cache that never evicts.

Three more things fall out: `mch_get_host_name()`, which wrote the machine's
name into block zero so a recovering vim could say the swap file came from
elsewhere (**`uname`**); `lalloc()`'s retry loop, whose whole point was that
`mf_release_all()` might have freed memory by paging blocks to disk; and
`check_overwrite()`'s "swap file exists" warning.

**What does not change is the block structure.** Lines still live in blocks,
blocks still have numbers, `mf_trans` still maps them. This removes the ability
to *evict* a block, which was already impossible — not the ability to have one.

#### A bug this phase fixes, and where it came from

`check_overwrite()` is the last reader of `p_dir`, so **`'directory'` can
finally go**. Phase 11 dropped its row while this still read it, and a row is
what initialises its global — so `p_dir` was NULL for ever, and

```
:w! <an existing other file>      ->      Segmentation fault
```

shipped for twelve phases. Nothing saw it. The build is clean; an orphaned
global is *used*, so no unused-variable warning names it; the linkage and symbol
checks pass; and neither the Ex sweep nor the 67 behaviour cases write over an
existing file under a different name with `!`.

`dropoptions.py --strict` refuses exactly this and had not been written when
Phase 11 was. The repair is in three parts: Phase 11 keeps `'directory'` and
drops it here instead; `tools/orphanopts.py` checks the invariant in **every**
whim phase, and is type-aware — a `long` orphan reads as 0 and is reported, a
`char_u *` orphan is fatal; and `--strict` learned that `varp == (char_u *)&p_x`
takes an address rather than reading a value, which is what made it refuse a row
that was genuinely inert.

#### Where the symbol count moves

**107 → 104**: `sysinfo`, `getrlimit`, `uname`. `sysconf` stays — its other
caller is `_SC_SIGSTKSZ`, for `sigaltstack`.

#### The delta

**None.** `:w!` over an existing other file stops crashing and writes it, which
is what it should always have done, and the phase asserts that directly — no
harness does.

## Phase 22 — the working directory is where it started

`:cd`, `:lcd` and `:tcd` are `ex_ni`, `:!` no longer forks, and nothing else in
this editor moves the process. So **the directory it starts in is the one it
dies in**, and three pieces of machinery that exist because that was not true
stop being needed.

  * `mch_FullName()` chdir'd into the leading directory of a relative name,
    asked `getcwd()` where that had landed, and chdir'd back — via `fchdir()`
    on a descriptor it held open, falling back to `chdir()`. That dance is what
    resolved `..` and a symlinked directory on the way to a full name.
  * `win_fix_current_dir()` restores a window's or tab's local directory, and
    runs only when `w_localdir`, `tp_localdir` or `globaldir` is set. The first
    two come only from `:lcd` and `:tcd`; `globaldir` is assigned only inside
    this function. Unreachable.
  * `edit_buffers()` takes a `cwd` to return to between `-o` windows, and is
    passed `start_dir` — `static char_u *start_dir = NULL;`, which nothing
    assigns. The `-o` local-directory handling that set it is already gone.

### What it costs

A full name is now the working directory with the name appended, so `../x/y`
becomes `/cwd/../x/y` instead of `/real/x/y`. It opens the same file. What it
loses is that **two spellings of one path no longer compare equal**, so
`:e ../x/y` and `:e /real/x/y` are two buffers rather than one.

### The trap, and the harness that caught it

The first version of this dropped the dance and kept the rest of the function,
which reads `if ((force || !mch_isFullName(fname)) && ...)`. That condition is
true for an *absolute* name when `force` is set — harmless while the dance
existed, because the dance chdir'd to the name's own directory and `getcwd()`
came back with it. Without the dance, the working directory was prepended to a
name that already had one: `/tmp/x` became `/cwd//tmp/x`.

The delta check named it in one line — `:read`, `:write` and `:wq` moved, and
nothing else — which is the whole argument for declaring a delta in advance
rather than reading a diff afterwards. The fix is that `force` has nothing left
to re-resolve, so an absolute name is its own answer.

### `getcwd` stays, and is asked once

It has five callers through `mch_dirname()`: `shorten_fname1()` and
`shorten_fnames()` shorten every displayed name against it, `buf_modname()`
builds names from it, `modify_fname()` implements `%:p`, `fname2fnum()` resolves
a mark's file, and `mch_FullName()` is how a relative name becomes absolute at
all. Dropping it would mean `b_ffname` could not be a full path — a capability
cut rather than plumbing, and a different decision.

Since nothing can move the process, though, the answer cannot change. It is read
into a static on the first call and every later call is a copy: one syscall for
the life of the editor, where there used to be one per path operation.

### Where the symbol count moves

**103 → 101**: `chdir`, `fchdir`.

### The delta

**None the harness records** — and the phase adds a check of its own, because
none of them walks the path this changes: every harness edits a file in the
directory it is standing in. So it writes `sub/f.txt` from above and then
`../sub/f.txt` from inside `sub`, and requires the file to come back correct
both times.

## Phase 23 — no floating-point library

Three calls are the whole of libm in this editor, and they turn out to be two
different questions.

**`ceil()` and `floor()`** appear once, in the fuzzy matcher, as the two halves
of rounding half away from zero:

```c
(fzy_score < 0) ? (int)ceil(fzy_score * SCORE_SCALE - 0.5)
                : (int)floor(fzy_score * SCORE_SCALE + 0.5)
```

C's double-to-int conversion truncates **toward zero**, which is `ceil` for a
negative value and `floor` for a positive one — so biasing by half in the sign's
own direction and then converting gives the same answer for every input, and the
two arms collapse into one expression.

**`log10()` is not translated, because it cannot be**, and finding that out is
the useful part of this phase. It appears once, as
`max_prec -= (size_t)log10(abs_f)`, and the obvious integer equivalent —
dividing by ten until the value drops below ten — **is a different function**.
Just below a power of ten, `log10()` returns a double that rounds up to the
integer:

```
(size_t)log10(99.999999999999986)  ==  2        counting digits gives 1
```

`tools/nolibm_check.c` swept a million values through both forms and found 79
disagreements, all of that shape. A rounding rewrite that is merely believed is
how an off-by-one reaches a release — and here the check turned a translation
into a removal, which is the better phase.

### Nothing can reach the `%f` branch

So the whole floating-point branch of `vim_vsnprintf()` goes instead. The
premise is checkable and the phase checks it: **there is not one `%f`, `%F`,
`%e`, `%E`, `%g` or `%G` conversion in any format string in the file**, and the
single `vim_snprintf()` call whose format is not a literal takes a local
`char *fmt` that is one of two constants, `"%*ld "` and `"%-*ld "`. Without
`+eval` there is no `printf()` to supply one at run time either.

That takes the conversion case (139 lines), `TYPE_FLOAT` and its three arms,
`infinity_str()` and `typename_float` — and with them `log10`, `isinf` and
`isnan`. `TYPE_FLOAT` is the **last** enumerator, checked before removing it,
because several enums here index a parallel table.

`<math.h>` stays: `INFINITY` is the fuzzy matcher's score sentinel, in thirteen
places. Under musl libm is part of libc, so the link line does not change
either — what changes is that `nm -u` stops naming a floating-point function.

### Where the symbol count moves

**101 → 98**: `ceil`, `floor`, `log10`.

### The delta

**None.**

## Phase 24 — there is no mouse

A terminal mouse is a protocol, not a device: the terminal is asked to report
clicks, it sends escape sequences, the editor decodes them into key codes, and
the normal, insert and command-line loops dispatch those like any other key.
All four layers are here, and an editor driven from a keyboard needs none of
them.

**The island is bounded**, which is what makes this a cut rather than a rewrite.
Thirty-five functions mention the mouse and all but two are reached only from
each other, so `funcreach.py` deletes the interior once the roots are gone. The
tool removes only the roots:

| layer | what goes |
| --- | --- |
| the tables | 22 rows of `nv_cmds[]`, and the 14 `<LeftMouse>`/`<ScrollWheelUp>`/`<MouseMove>` rows of the key-name table, so `:map <LeftMouse>` no longer names anything |
| the dispatch | `edit()`'s insert-mode case run, `getcmdline_int()`'s six case runs, `]<LeftMouse>` in `nv_brackets()` and `g<LeftMouse>` in `nv_g_cmd()`, and the click that dismissed a `Press ENTER` prompt |
| the decoder | `check_termcode_mouse()`'s call, and 41 lines in `set_termname()` that read the terminal's 1006 capability, set `'ttymouse'` from it and install the termcodes |
| the switch | `setmouse()`'s **31** calls, every one a bare statement, and `mch_setmouse()`'s |
| the questions | `mouse_has()` and `mouse_has_any()`, whose three callers outside the island each become the answer they now always get |

### Two names that are not about the mouse

Both checked rather than assumed. `get_mouse_class()`, `find_start_of_word()`
and `find_end_of_word()` classify characters for **double-click word
selection** and are reached only from `do_mouse()`, so they go with it — the
name says mouse and the work is text, which is exactly the shape that survives a
careless sweep.

`WaitForCharOrMouse()` has no mouse in it at all: the name is left over from the
GUI build, where it also polled for motion events. Here it is `input_available()`
and `RealWaitForChar()`. It is folded into `WaitForChar()`, its only caller,
rather than left telling a lie.

### The enumerators stay

`KE_LEFTMOUSE`, `KS_MOUSE` and the rest are constants that cost nothing, and
**deleting an enumerator renumbers every one after it** — several enums in this
file index a parallel table. That is a different kind of change and does not
belong in a phase about capability.

### Four circles, and a tool bug

This phase found more than it removed, and all of it is the same shape: **an
option row is a root for reachability**, so a row keeps its own readers alive
and `--strict` then refuses to drop the row because those readers exist.

1. `did_set_string_option()` asks `if (varp == &p_mouse)`, and
   `check_mouse_termcode()` survives because `did_set_ttymouse()` names it.
2. `'mouse'`, `'mousemodel'` and `'ttymouse'` each name a `did_set_` and an
   `expand_set_` handler in the row itself, and `did_set_mousemodel()` reads
   `p_mousem`. The rows are pointed at NULL first; they go a moment later.
3. `:behave mswin` sets `'mousemodel'` **by name**, and the terminal's
   mouse-protocol reply sets `'ttymouse'` by name — the lookup that returns −1
   for a row that is not there and is not checked. `:behave` is about selection
   and keeps working; it just stops setting an option that has gone.
4. `didset_string_options()` dereferences every string option's global once at
   startup, which is the trap Phase 18 records. A row can be inert to every
   other reader and still be read there.

**And one real tool bug, which cost the most and was worth the most.** The first
run of this phase deleted **654 functions** and left a file that would not
compile. The cause:

```c
static struct mousetable
{
    int     pseudo_code;
    ...
} mouse_table[] =
{
    ...
};
```

gcc reports the unused variable at `} mouse_table[] =`, and `deadsweep.py` ran
forward from there — taking the initialiser and leaving the struct body open, so
the next declaration landed inside it and gcc said *"expected
specifier-qualifier-list before `static`"* a hundred lines later. Everything
after that was garbage compiling on garbage.

It is the same class of mistake as keying on a warning's sentence instead of its
option: **the extent of a thing is not "the line it was reported on"**.
`declaration_extent()` now walks *backwards* too when the declarator starts with
`}`, over the type body and its head. There are five constructs of that shape in
the file — `modmasktable`, `key_name_entry`, `mousetable`, `signalinfo` and
`termcode` — and this is the first phase that ever made one unused.

`dropoptions.py` was bounded at the same time: its guards looked 400 characters
ahead from the row's start, and `'mousefocus'` and `'mousehide'` are
`(char_u *)NULL` — GUI options with no global at all — so the search ran past
the end of the row and found the *next* option's variable. Every guard is now
bounded by the row's own braces.

### The delta

**None the harness records.** No Ex command is a mouse command, no behaviour
case clicks, and the pty harness types keys. The phase adds a check of its own:
`:set mouse=a` must be refused.

It took three tries to write that check, and each failure is one CLAUDE.md
already warns about. Reading the error message finds nothing, because silent Ex
mode prints nothing. Testing whether a later `:w` wrote the file finds nothing
either — **a failing `-c` does not abandon the ones after it**, so
`set nosuchopt` followed by `w` still writes. The exit status is the answer: 0
for an option that exists, 1 for one that does not. It is paired with
`:set ignorecase` as a control, so the check fails if the binary starts exiting
1 whatever it is asked.

## Phase 25 — a write is a write, and nobody owns it

### a write is a write

Writing a file in vim is not one operation. Before the new contents go anywhere
the old file may be renamed or copied aside, its permissions, owner, group, ACL
and timestamps carried over, the write attempted, and the whole thing rolled
back if it fails — and afterwards the copy is kept, or deleted, or renamed again
for `'patchmode'`. That is **437 lines of `buf_write()`**, and what `'backup'`,
`'writebackup'`, `'backupcopy'`, `'backupdir'`, `'backupext'`, `'backupskip'`
and `'patchmode'` are between them.

An embedded editor writes the file it was asked to write.

**`dobackup` is the hinge.** It is `(p_wb || p_bk || *p_pm != NUL)`, so with the
options gone it is FALSE, `backup` stays NULL and `backup_copy` stays FALSE —
and the tests spread through the rest of the function each collapse to the
branch they were already taking under `:set nobackup nowritebackup`, a
configuration vim has always supported. One of them is an `if`/`else if` whose
*else* is the live arm, so the pair collapses to that rather than going;
`buf_setino()` still has to happen.

Three things fall out that are worth naming separately:

  * **`vim_rename()` has five callers and all five are in here** — make the
    backup, put it back when the write fails, put it back when it is abandoned,
    and move it aside for `'patchmode'`. So `vim_copyfile()` goes with it, and
    that is `readlink`, `symlink` and `rename`.
  * `set_file_time()` carried the old file's timestamps onto the backup. One
    caller, and that is `utime`.
  * `mch_get_acl()`, `mch_set_acl()` and `mch_free_acl()` are **already stubs** —
    this build has no ACL support, so one returns NULL and the others do nothing
    with it. They went unnoticed for thirty phases because a stub compiles. The
    `vim_acl_T` that threaded through `buf_write()` to reach them goes too, and
    its three forward declarations go *here* rather than in the sweep: the sweep
    has to compile the file first, and a prototype naming a type this removes is
    an error, not a warning.

`fchown` and `umask` were not on the list and went anyway — every call to both
was inside the backup block.

#### The same circle, twice more

`'backupcopy'` names `did_set_backupcopy` and `expand_set_backupcopy` in its own
row, and `'backupext'` and `'patchmode'` share
`did_set_backupext_or_patchmode`; a row is a root, so the handlers survive the
sweep, read `p_bkc` and `p_bex`, and `--strict` then refuses to drop the row
that is the only thing keeping them alive. Phase 24 met this three times. The
rows are pointed at NULL first.

`didset_string_options()` reads `p_bkc` at startup — the trap Phase 18 records,
met again — and `set_init_default_backupskip()` looks its row up **by name**,
the lookup that returns −1 and is not checked.

#### Where the symbol count moves

**98 → 92**: `fchown`, `readlink`, `rename`, `symlink`, `umask`, `utime`.

#### The delta

**None the harness records.** `:w` writes; it just stops leaving a `~` file
beside what it wrote, which no harness asked for. The phase checks that
directly — overwrite a file and the directory must hold exactly what it held
before, with the new contents in it.

### nobody owns a file

An embedded editor runs where there are no users to tell apart, so asking who
you are is asking a question with no answer. Four places were still asking.

  * `:w!` on a read-only file makes it writable first, but only **if you own
    it**: `st_old.st_uid == getuid()`. The ownership test goes and the `chmod`
    stays. Nothing widens in practice — where the test used to say no, the
    `chmod` now says no instead, and the same error comes back by a different
    route.
  * When a write fails and `!` makes it retry, the mode carried onto the new
    file is masked to `0777`, dropping setuid, setgid and sticky — but only if
    you are not the owner. The test goes and **the masking stays**, which is the
    safe direction: a file this editor writes never carries a setuid bit.
  * `'modeline'` is forced off when `getuid() == ROOT_UID`, a protection against
    a modeline running as root. There is no root here and no `+eval` for a
    modeline to reach.
  * `get_user_name()` was stubbed to `return FAIL;` in Phase 20, when the
    password database went, and its two callers were left writing the answer
    into the swap file's block zero. The second one's `else` — the arm that
    spliced a user name into the recorded file name — has therefore been dead
    since Phase 20 and goes now, along with the `b0_uname` field itself. **A
    struct field is not a variable**: no warning names one that nothing reads,
    and the sweep cannot see it, so it has to be named here.

#### Permissions are not ownership

`chmod` and `fchmod` stay, through `mch_setperm()` and `mch_fsetperm()`. A file
still has a mode, `:w!` still has to clear the read-only bit to write, and the
mode of the file that was there is still put back on the file that replaces it.
Removing those would take `:w!` on a read-only file with them, which is a
capability and not a concept — so the phase asserts both halves: `getuid` and
`getgid` gone from `nm -u`, `mch_setperm`/`mch_fsetperm`/`mch_getperm` still
called, and `:w!` over a `chmod 444` file still writes it. No harness writes to
a read-only file, which is why that check lives here.

#### Where the symbol count moves

**92 → 90**: `getuid`, `getgid`.

#### The delta

**None.**

## Phase 26 — five signals, not twenty-one

`signal_info[]` had twenty-one entries and five handlers. Reviewed one at a
time, four earn their keep.

| kept | why |
| --- | --- |
| `SIGWINCH` | `sig_winch()` sets `do_resize`, read in nine places. Without it the editor never learns the terminal changed size. |
| `SIGINT` | `catch_sigint()` sets `got_int` — **read in 222 places**. That number is the argument: `got_int` is how every long operation is interruptible. Without the handler, CTRL-C reverts to its default action, which kills the process and loses the buffer, turning "stop that" into "lose your work". |
| `SIGTSTP` | CTRL-Z and `:suspend`, through `sig_tstp()` and `got_tstp`. The only caller of `raise()`. |
| `SIGHUP`, `SIGTERM` | reaching `deathtrap()`, so that a killed editor **puts the terminal back**. |

Sixteen entries and three handlers go: `SIGPWR`, whose handler called
`ml_sync_all()` — **an empty function** since Phase 21; `SIGUSR1`, whose flag
**nothing reads** (assigned and never examined, so `-Wunused-variable` never
fires and the sweep would never have found it); and `SIGQUIT`, `SIGILL`,
`SIGTRAP`, `SIGABRT`, `SIGFPE`, `SIGBUS`, `SIGSEGV`, `SIGSYS`, `SIGALRM`,
`SIGVTALRM`, `SIGPROF`, `SIGXCPU`, `SIGXFSZ`, `SIGUSR2`, `SIGPIPE`. With them go
`sigaltstack` and its stack — which existed so a SIGSEGV from stack overflow
could still run a handler, and SEGV no longer reaches one — and
`may_core_dump()`, which re-raises to produce a core there is nobody to read.

Eight signal names are left in the file: the five kept, plus `SIGCONT`,
`SIGALRM` and `SIGPIPE`, which `mch_suspend()` sets around the stop. The phase
asserts exactly that list.

**The cost, decided deliberately: a crash no longer restores the terminal.**
`SIGSEGV` and `SIGBUS` take their default action. The alternative is keeping a
handler for conditions this editor should not have, to tidy up after a bug that
should not exist.

### The reason to keep `SIGHUP` and `SIGTERM` was not true until this phase

This is the part worth recording, because the phase was written on a claim that
turned out to be false and the check is what caught it.

`deathtrap()` reaches `preserve_exit()` → `prepare_to_exit()`, which calls
`settmode(TMODE_COOK)` to put the terminal back. And:

```c
settmode(tmode_T tmode)
{
    if (!full_screen)
        return;
```

— while `deathtrap()` sets `full_screen = FALSE` several lines before it gets
there. So the editor printed `Vim: Caught deadly signal TERM`, emitted
`stoptermcap()`'s escapes, exited, and **left the terminal with `ICANON` and
`ECHO` off**. The shell that got it back was unusable; the user had to type
`reset` blind. Measured on the slave side of a pty, before and after the cut:
identical, and wrong both times. Upstream has the same hole.

The fix is additive, so the ordinary exit path is untouched: `full_screen` is
lent for the length of the call. The guard exists to avoid drawing on a screen
that is not there, and putting the terminal back is not drawing.

`mch_settmode()` would have been the more direct call and is not available —
it is defined 89,000 lines further down and `SLIM-GOAL.md` Phase 10 removed the
forward declaration nothing needed.

### The check

`tools/termrestore.py` opens a pty, starts the editor on it, **verifies it
really entered raw mode** — otherwise the test would pass for the wrong reason,
on an editor that never changed anything — sends `SIGTERM`, and requires
`ICANON` and `ECHO` back on the slave side. No harness here kills an editor
halfway: the behaviour cases and the Ex sweep run it to completion and the pty
harness quits cleanly. This is the one thing the kept signals are for, so it is
checked in the phase.

### Where the symbol count moves

**90 → 88**: `sigaltstack`, `sysconf`. `raise` stays — `sig_tstp()` needs it —
and so does `kill`, whose three sites are `mch_suspend()`, the signal-blocking
helper, and `may_core_dump()`; only the last goes.

### The delta

**None the harness records.** The Ex sweep records `:suspend` and `:stop` as
*skipped* — they hand over the terminal — and `SIGTSTP` stays regardless.

## Phase 27 — `[[=a=]]` stops meaning "a with any accent"

A POSIX bracket expression has three bracketed forms inside it, and they are
three different features that happen to share a syntax:

| | | |
| --- | --- | --- |
| `[[:alpha:]]` | a character **class** | stays |
| `[[.x.]]` | a collating **element** | stays |
| `[[=a=]]` | an equivalence **class** | goes |

The third means "this character and every accented form of it", and expanding it
takes **`reg_equi_class()`, 1,397 lines** — a switch over every base letter
listing its variants across Latin-1, Latin Extended-A and Latin Extended-B. It
was the largest single function left in the file and the least used: reached
only when a pattern contains `[=`, and nothing in the editor writes one.

Two call sites, and the sweep did the rest: the bracket parser in `regatom()`,
where the `get_equi_class()` arm goes so `[=` falls through to being taken one
character at a time; and `skip_regexp()`'s scan, which asked the same question
only to know how far to skip.

`\w`, `\a` and `[[:alpha:]]` are a different mechanism and are untouched. The
phase checks both halves, because only the pair is a check: `[[=a=]]` must stop
matching an accented `a`, and `[[:alpha:]]` must still classify.

## Phase 28 — C indenting

`get_c_indent()` was **1,534 lines** and the largest function left: a model of C
syntax built to answer one question, how far to indent this line. It knows about
labels, scope declarations, `case` bodies, continuation lines, comment blocks
and function arguments, and about `'cinoptions'`, a miniature language for
adjusting all of it. With `in_cinkeys()` and the `cin_*` helpers, **3,007 lines**.

`'autoindent'` stays — it is on by default here — and copies the previous line's
indent. That is what an embedded editor needs; the rest is a C compiler's front
end used for whitespace. `'lisp'` and `'indentexpr'` are different indenters and
are not touched.

Five options go, all `PV_BUF`: `'cindent'`, `'cinkeys'`, `'cinoptions'`,
`'cinscopedecls'`, `'cinwords'`.

### It is spelled in more places than it is named

The first cut found five call sites. The sweep found seven more, and each is a
different way of not being a call to `get_c_indent`:

  * `op_reindent(oap, get_c_indent)` — the `=` operator passes the indenter as a
    **function pointer**, so a grep for `get_c_indent(` does not see it. `=` now
    passes `get_indent`, which sets each line's indent to the indent it already
    has: a no-op, the honest answer for a buffer whose language the editor
    cannot read.
  * `preprocs_left()` and `may_do_si()` — `'smartindent'` **defers to**
    `'cindent'` when both are set, so both read `b_p_cin` without touching the
    indenter.
  * `parse_cino()` has **four** callers and none of them indents anything:
    opening a buffer, resizing a window, setting `'shiftwidth'` (some
    `'cinoptions'` are expressed in shiftwidths), and `check_buf_options()`.
  * `cin_is_cinword()`, reached from `'smartindent'`, because `'cinwords'` told
    it which keywords begin a block.
  * insert completion re-indents on accept, through `want_cindent`.

`cindent_on()` is left, returning FALSE. It has seven callers and five only ask
in order to do something else instead; an editor that answers "no, this buffer
is not C-indented" is telling the truth.

### A tool bug this found

`droplocal.py` counted a field's remaining mentions with `text.count(name)` and
no word boundary, so `b_p_cin` appeared to have 23 readers when it had none —
they were `b_p_cink`, `b_p_cino`, `b_p_cinsd` and `b_p_cinw`. Ordering the
arguments around it would have hidden the bug rather than fixed it.

### The awkward part

Insert mode tests for a re-indent in two places hundreds of lines apart, and the
first **jumps into the second**:

```c
if (cindent_on() && ctrl_x_mode_none())        ... goto force_cindent;
...
if (can_cindent && cindent_on() && ...)  { force_cindent: ... }
```

So the two have to go together or not at all — removing the second alone orphans
the label, and removing the first alone leaves a label nothing reaches.

Measured: 142,636 → 138,687 lines, 3,949 removed against 3,007 predicted; the
option plumbing and the `b_ind_*` fields were the difference.

## Phase 29 — `:command`, user-defined commands

`:command` lets a user give a name to an Ex command line and have it dispatched
like a built-in. The machinery is **1,451 lines**: a parser for the `-nargs`,
`-range`, `-complete` and `-bang` attributes; a per-buffer and a global growable
array of definitions; `uc_check_code()`, 286 lines, expanding `<args>`,
`<q-args>`, `<line1>`, `<count>`, `<bang>`, `<reg>` and `<mods>`; and a listing
mode.

**Without `+eval` a user command can only invoke built-in commands**, which makes
it a way of writing an alias — and this editor reads no vimrc, so the only way to
define one is to type `:command` by hand in the session where it is used.

What goes beyond the three commands: `do_ucmd()`, which `do_one_cmd()` reaches
when `ea.cmdidx` is negative — the marker for "this name is not in `cmdnames[]`,
try the user table" — so an unknown name is now simply not a command;
`find_ucmd()`'s two callers; **six rows of the completion table**, which kept six
`get_user_cmd_*` functions alive and which no grep for `do_ucmd` would find,
because a table row is a reference the same as a call; the walk past the end of
`cmdnames[]` in `expand_user_command_name()`; and the `b_ucmds` field.

### The delta is two names, not the three retired

`:command` with no arguments lists what is defined, and `:comclear` clears it:
both succeed today, so both move in the Ex sweep. **`:delcommand` does not** — it
is `EX_NEEDARG`, so the sweep's bare call already failed. Declaring three and
being told two is the check working, and it is Rule 3's other half: retiring a
command only shows in the sweep if it used to succeed.

## Phase 30 — `K` and the tag jumps, keeping `*` and `#`

`nv_ident()` is not one command, it is five, and they have nothing in common but
the first step — read the identifier under the cursor:

| | | |
| --- | --- | --- |
| `*` `#` `g*` `g#` | search for that word | **stay** |
| `K` | run `'keywordprg'` on it | goes |
| `]` `CTRL-]` `g]` | jump to its tag | goes |

`*` and `#` are among the most used keys in vim and are pure search, so this
phase **rewrites** the function rather than deleting it. `K` runs `'keywordprg'`
through a shell and Phase 6 took the shell; the tag jumps build `ta `, `tj `,
`ts ` or `he! ` and hand them to `do_cmdline_cmd()`, and Phase 10 made every one
of those `ex_ni`. Both arms have been building commands that fail.

### Rule 3 applies to normal-mode commands too

The first version **deleted** the `K` and `CTRL-]` rows from `nv_cmds[]`. It
built, it swept clean, it passed the linkage and symbol checks — and **39 of the
67 behaviour cases moved**: CTRL-A, joins, macros, marks, multibyte motions,
nothing to do with `K` or tags.

`nv_cmd_idx[]` is a `static const` array of **indices into `nv_cmds[]`**,
precomputed and sorted by command character, with `nv_max_linear` marking how
far a direct lookup works. Deleting two rows shifts every later index while the
precomputed table still points at the old positions, so every normal command
after them dispatches to the wrong function. It is the parallel-table trap the
enumerators have, one table over.

So **Rule 3 — a command is never deleted from the table, it is pointed at
`ex_ni`** — extends to `nv_cmds[]`, where the equivalent is `nv_error()`, the
handler already used for keys that do nothing.

### And the check had to be a pty

The first `*` check ran under `-e -s` and compared the file. The two binaries
disagreed — before the phase `:normal *dd` did nothing at all, after it the `*`
was ignored and the `dd` deleted line 1. **Neither is what `*` does.**
`normal_search()` wants a screen, so silent Ex mode measures something that is
not the feature. In a real pty both binaries give the same correct answer, and
`tools/starcheck.py` now asks it there: from `foo` on line 1, `*` must land on
the `foo` on line 5 and **skip `foobar`**, which `dd` then proves.

Measured: 136,700 → 136,451 lines; `nv_ident()` from 227 lines to the search
half. **The delta is none** — these are normal-mode keys, so no Ex command
moves.

## Phase 31 — file-name modifiers

`eval_vars()` expands `%` and `#` into the current and alternate file names, and
`<cword>`, `<afile>` and the rest. **That stays** — `:w %` and `:e #` are how a
file name is written without typing it.

What goes is the **suffix language** that may follow: `modify_fname()`, 426
lines implementing `:p` (full path), `:h` (head), `:t` (tail), `:r` (root),
`:e` (extension), `:s/from/to/`, `:gs`, `:~` and `:.`, applied left to right so
that `%:p:h:t` means something. It is a small programming language over path
strings, and **most of it asks questions this editor can no longer answer**:

| modifier | what it needed | which phase took it |
| --- | --- | --- |
| `:p` | where the working directory is | 24 — there is one answer now |
| `:~` | the notion of `$HOME` | 22 — nothing outside the process |
| `:s//` | a regexp over a file name | the only place a pattern is applied to something that is not buffer text |

**One caller**, which is why the cut is small: `eval_vars()` reaches it once, in
the arm that runs when the next character is not `<`. That arm goes, and with
it `tilde_file` and `skip_mod`, which existed only to be passed to it. The `<`
arm — which strips one extension and is not part of the modifier language —
stays. After this a modifier is left in the command line as the literal
characters it is written with, which is what an editor that does not know the
syntax does.

**The delta is none, so the phase checks both halves itself**, and only the
pair is a check: `:w %` must still write the file being edited, and `%:t` must
stop being a tail. One without the other passes on a `eval_vars()` that returns
NULL for everything.

Measured: 136,451 → 135,825 lines.

## Phase 32 — insert completion, the popup menu, and the keys that reached them

CTRL-N, CTRL-P and the whole CTRL-X family — `CTRL-X CTRL-F` for file names,
`CTRL-X CTRL-K` for a dictionary, `CTRL-X CTRL-L` for whole lines — plus the
popup menu that displays the matches. This is the largest single subsystem left
after the regexp engine, and it is the one whose sources are all gone already:
the tag stack went in Phase 10 and the `CTRL-]` key in Phase 30, the shell in
Phases 6 and 8, `'dictionary'` and `'thesaurus'` name files this editor has no
business reading, and `'completefunc'` needs the eval layer.

**Two cuts, with a sweep between them.** The first answers the questions
completion is entered through, so it produces nothing; the second removes the
code that kept asking. This was two phases, and the second existed only because
the first had stopped short.

### The predicates

**Nine predicates become constants**, and the sweep follows them:

```
ins_complete              FAIL        pum_visible                    FALSE
ins_compl_prep            FALSE       pum_redraw_in_same_position    FALSE
ins_compl_active          FALSE       pum_may_redraw   pum_undisplay   pum_display
ins_compl_has_autocomplete FALSE
```

Twelve option rows go with them — `autocomplete complete completefunc
completeopt dictionary infercase pumborder pummaxwidth pumopt pumheight pumwidth
thesaurus` — and six buffer-local fields, `b_p_cpt b_p_cot b_p_dict b_p_tsr
b_p_inf b_p_ac`.

### `didset_string_options()`, for the fourth time

This is the fourth phase to be caught by it, and this time it was a **segfault
before the first keystroke**. The function dereferences every string option's
global at startup, so dropping `'completeopt'`'s row while leaving

```c
opt_strings_flags(p_cot, p_cot_values, &cot_flags, TRUE);
```

hands a NULL to something that reads it. The editor did not mis-complete; it
did not start.

`orphanopts.py` existed precisely to catch this and did not, because it looked
for an explicit `*p_x` dereference and this is a bare argument. **It now counts
any mention at all.** A pointer nothing mentions is harmless — the sweep takes
it — and one that is mentioned while having no row to initialise it is a NULL
going somewhere, which is enough to fail on without judging the shape of the
somewhere. Re-run over every earlier boundary: no new complaints, so the
stricter rule costs nothing and closes the trap that had cost four phases.

### Checking that a key does nothing

Bare CTRL-N in insert mode is **already inert** in a build with nothing to
complete from, so a before/after comparison of it proves nothing either way.
`tools/complcheck.py` uses `CTRL-X CTRL-N` instead, which is unambiguous, and
checks the half that must survive in the same run: **insert mode still
inserts**. A completion check that only proves completion is gone also passes on
a binary that cannot type.

### The callers

**Seventy functions named `ins_compl_*`, `pum_*` or `compl_*` survive the
stubs.** They are *reachable*, so no sweep can touch them, and never *entered*,
because `ins_complete()` returns FAIL before any of them runs. `edit()` does not
reach completion through one door: it calls `ins_compl_addleader()`,
`ins_compl_bs()`, `ins_compl_accept_char()` and twenty-five more directly, and
`update_screen()`, `win_line()`, `showruler()` and `screen_puts_len()` each ask
`pum_visible()` on their own account. That is the shape worth naming: **a stub
answers a question; it does not remove the caller that asks it.** So the second
cut removes the callers, and the second sweep takes the callees.

What goes, all of it inside `edit()`:

| | |
| --- | --- |
| the CTRL-X submode | `ins_ctrl_x()` is empty, so `ctrl_x_mode` never leaves `CTRL_X_NORMAL` and every `ctrl_x_mode_*()` test is decided |
| the per-key completion arm | forty lines feeding each keystroke to the match list |
| `'autocomplete'` | six arming sites, three of them one-line blobs macro expansion left behind |
| the arrow keys | four `if (pum_visible()) goto docomplete;` arms on Up, Down, PageUp and PageDown |
| `docomplete:` | the label itself |

**What stays is the answer the stubs gave**: CTRL-N and CTRL-P are still
insert-mode keys, and they now do nothing, which is what an unbound key does.

**The sweep between the two cuts is kept, and it is not a formality.**
`tools/nocomplkeys.py` counts and matches text in `edit()` as the first sweep
leaves it, and a count taken over code about to be swept is a different count.

### A cut that is not unique is a guess

The first version dropped the autocomplete disarm by matching its condition,
`if (c != KE_CURSORHOLD && c != KE_COMPLETE_DELAY)`. That condition occurs
**three times inside `edit()`**, and the one the search took was

```c
        {
            lastc = c;
        }
```

— the last-character save, which has nothing to do with completion. It
compiled, it swept clean, the island still shrank by 2,400 lines, and **nothing
downstream objected.** `drop_unique()` now refuses any condition that is not
unique in the file; anything genuinely ambiguous is spelled out in full or
anchored to one function with `drop_if_in()`. The phase also asserts the `lastc`
line is still there, because that is the failure that got through.

### Two halves, and only the pair is a check

Completion must be absent — `tools/complcheck.py` — and the arrow keys, whose
`pum_visible()` arms this phase cuts, must still move the cursor. Cutting a
guard and the key's real body together is exactly what no completion check would
notice, so `tools/arrowcheck.py` asks in a pty: from `one/two/three`, `A` then
Down then `X` must give `twoX`. **It was proved able to fail first** — with
`ins_down()` removed it reports `oneX`.

### The delta

Measured: **135,524 → 127,353 lines** and symbols 88 → 88, the subsystem being
pure computation over things already removed. The thirteen functions that remain
of the island are constant-answer stubs the redraw layer asks on its own account.
**Merged, the phase reproduces the boundary the two phases recorded byte for
byte**, in 173 seconds against the 203 they took in sequence. **The delta is
none** — no behaviour case types CTRL-N, these are insert-mode keys, and no Ex
command moves.

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

**42% of `whim-vim`'s functions are never entered** — 1,163 of 2,738, holding
17,806 lines. Measured after completion's predicates were stubbed, and before
its callers were cut:

```
    235  do_window                  CTRL-W, which no harness presses
    158  win_equal_rec
    145  getexmodeline
    139  open_cmdwin
    136  eval_vars
    124  set_context_in_set_cmd     command-line completion
    123  set_context_by_cmdname
    119  op_replace
    117  scroll_cursor_bot
    108  op_insert
```

**The list is doing its job, and the way to read it is against the last
reading.** After Phase 6 it said 1,520 of 3,255 over 27,865 lines, with
`reg_equi_class` (775), `get_c_indent` (713), `do_mouse` (284) and
`modify_fname` (160) at the top. Phases 24, 27, 28 and 31 removed **all four**,
and 10,059 lines of never-entered code with them. That is what a kind-3 entry
looks like when it is acted on.

What is left at the top has changed kind. `do_window`, `op_replace`,
`op_insert` and `scroll_cursor_bot` are **kind 2** — reachable, useful, and
simply not exercised, which is a finding about the harness rather than the code;
nothing here should press CTRL-W on its behalf. The kind-3 entries are now
`set_context_in_set_cmd` and `set_context_by_cmdname`, which is command-line
completion, and `ins_compl_build_pum` at 98 lines — the tail of a completion
whose key handling had survived the stubs, and which Phase 32's second cut then
removed.

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
