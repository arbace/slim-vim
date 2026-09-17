# WHIM-GOAL.md — reduce slim-vim to an embedded editor

`slim-vim.c` is vim as one translation unit, with every feature upstream's
`tiny` configuration has. **`whim-vim.c` is what is left when the editor stops
expecting a filesystem to have been installed for it.**

```
slim-vim.c = F(upstream@sha)          SLIM-GOAL.md, twelve phases
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
3. **A command is deleted from both lists, and no other command inherits its
   words.** Until Phase 80 a removed command was pointed at `ex_ni` and kept its
   row, because the lookup took the first row whose name began with what was
   typed, so every row decided the abbreviations of the rows below it — the trap
   `SLIM-GOAL.md` records, where deleting `:help` makes the name run
   `:helpclose`. Phase 80 gave each row its shortest abbreviation and deleted the
   489 stubs. A typed word now names a row only if it is at least that long, so
   a match is unique, and a deleted row's words resolve to nothing: E492.
4. **`whim-vim.c` is produced from the committed `slim-vim.c`**, not from a
   pass. The two pipelines are decoupled: `make whim-vim` needs no clone, no
   network and no agent, and the memoize key is `slim-vim.c`'s digest and the
   implementation's, exactly as the other pipeline keys on upstream's sha.
5. **`whim-vim.c` carries no comments.** Phase 82 removed every one. A phase's
   replacement text contains no `//` or `/*` outside a string literal, and a
   comment an edit would make wrong is deleted, not reworded.

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

**The sweep is not written into a phase program; the driver runs it, once per
stage.** Phases 1–82 are each two files: `pipes/whim<N>-edit.sh` makes the cut (and
may sweep part way through, where a second cut needs the first one swept), and
`pipes/whim<N>-check.sh` asserts, builds and probes. A **stage** is a run of phases
whose edits share one sweep: `tools/phaserun.sh` runs every edit in order on text no
sweep has touched since the stage began, one `tools/sweep.sh`, every check in order
on the swept text and its binary, and then the declared delta once. The check shares
nothing with the edit but the work tree and a state directory — the line count of
the text its edit was handed, the stage's symbol snapshot, and whatever file the
edit names for it. Only a stage's end is a boundary.

`pipes/whim.stages` is the schedule — 0 | 1-12 | 13-41 | 42-63 | 64-65 | 66-71 | 72 |
73-77 | 78 | 79 | 80 | 81 | 82 — and two kinds of fact that decide it, both measured
and both checked by `tools/stages.sh`:

- **what an edit needs of its input** (`need P swept|silent|swept-inner:K`). **A
  phase whose cut is computed from the text must see it swept** — phase 54 after 53
  without its inner sweep cut one option row too few and did not refuse — so that
  requirement is declared, not discovered. A counted anchor refuses on unswept text;
  a computed set shrinks silently.
- **which checks must see a boundary before a later phase** (`apart P K`). Inside a
  stage every check runs on the stage's end, so a check that asserts something a
  later phase removes on purpose — 64's "startPS stays", which 66 takes — fails
  there, and the two phases go in different stages.

And a stage whose end does not reproduce its recording is a failure, which is the
check behind both: without it the silent under-cut would have shipped.

`pipes/whim.delta` is rule 2's list, **written once**: for each phase, the Ex
commands, behaviour cases (`case:`) and terminal table (`term-moved`) it changes,
and `drop:` for a command that stops differing. The lines up to a phase are the
whole difference from slim at that phase; `tools/whimdelta.sh --phase N` checks a
binary against exactly that, and a stage checks its last phase's.

### Adding a phase

1. Write `pipes/whim<N>-edit.sh <work> <state>` — the cut — and
   `pipes/whim<N>-check.sh <work> <state>` — the assertions, `tools/phasecheck.sh`,
   `tools/phasebuild.sh` and the probes. Neither sweeps at its end and neither checks
   the delta; anything the check needs from the edit goes in `$state` by name.
2. **Declare its delta** in `pipes/whim.delta`: a line `N  command… case:name…`, or
   none if the harness sees nothing new — before running it.
3. **Place it in the schedule.** Add N to `WHIMPHASES` in `whim.mk` and to the whim
   `PHASE_LIST` in `tools/pipeline.sh`, then add `stage N` to `pipes/whim.stages` as a
   stage of its own, or widen the last stage to end at N. It must start a stage if its edit counts anchors against,
   or computes its cut from, swept text (declare `need N swept`), or needs a silent
   compile (`need N silent`). It must not share a stage with an earlier phase whose
   check it breaks (declare `apart P N`) — run the earlier checks on its result to
   find out.
   Then put N in the `package` line of its concept (or a new one), declare a `uses`
   line for each phase of another package it relies on, and run
   `tools/packages.sh whim --check`, which refuses a phase in no package. Nothing
   runs the packages, so this moves no key.
4. `make whim-tip` runs the last stage and records its boundary; `make whim-verify`
   then proves every stage from the recorded one before it.

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


## Concept index: the phases as packages

The phase sections below are in the order the work was done, and it shows: windows
are cut in six places, buffers in nine, options in eight. This index reads the same
83 phases **by concept** — eighteen *packages* — so that "everything this editor
lost about windows" is one list. It is placed here, after the rules and the sweep
that every phase shares and before the first phase section, because it is a table of
contents for those sections: it introduces nothing a phase depends on, and every
line of it points down into one of them.

**A package is a view, and nothing runs it.** No phase moved, no boundary moved, and
no cache key moved: the schedule is still `pipes/whim.stages`' `stage` lines, and a
package's phases are spread across stages. The data is two more kinds of line in the
same file — `package NAME P...`, and `uses A:P B:Q KIND why` for a phase that relies
on a phase of another package having run — which `tools/stages.sh` ignores and
`tools/packages.sh whim` prints. `tools/packages.sh whim --check` refuses a phase in
no package or in two, an unknown phase or package, a `uses` inside one package and a
`uses` whose dependency runs later. It is a tool of its own because
`tools/phaserun.sh` names `tools/stages.sh`, which puts every byte of that script in
every stage's cache key.

**Packages were assigned from what each phase's program does, not from its title**,
and a phase that does two things is in the package of the larger cut: phase 6 cuts
the shell's wildcard expander and the wildmenu and is in `files`; phase 44 retires
`:!` and six text commands and is in `text`; phase 70 makes `:e` reuse the one
buffer and removes swap-file detection and is in `buffers`.

**Each dependency is tagged with its kind.** *Mechanical*: without the earlier
phase the later one fails or cuts wrongly — an anchor or assertion refuses, a tool
refuses to drop an option something still reads, a computed set comes out
different, or what it removes as dead or constant would still be live. *Rationale*:
the later phase would still run and cut the same thing, and the earlier one is the
reason given that the cut costs nothing or is the right call. Of the 50, 37 are
mechanical and 13 are rationale. `tools/packages.sh whim --check` refuses any other
kind, and `make whim-verify` and `make whim-tip` run that check before they start.

**A `uses` line is only written where a phase program or a section here says so**,
and each was checked against the program that did the work — which is how four
phase numbers in the prose were found stale (26's `ml_sync_all()` was emptied by 11,
its `preserve_exit()` loop by 21; `K`'s `:!` lost its process in 8; `ins_ctrl_x()`
was emptied by 32). Dependencies inside a package are its order and are not listed.
Where the reason is a constant a later phase asserts or folds, the dependency is
real: phase 79's step 1 requires each of 28 bodies to be `return <constant>;`, and
refuses if the phase that made it so had not run.

| package | phases |
| --- | --- |
| [`seed`](#seed) | 0 |
| [`environment`](#environment) | 1 9 20 23 26 |
| [`options`](#options) | 2 16 49 54 55 56 60 62 |
| [`startup`](#startup) | 3 4 18 43 |
| [`regexp`](#regexp) | 5 27 76 |
| [`files`](#files) | 6 7 8 13 14 22 25 31 |
| [`tags`](#tags) | 10 30 63 74 |
| [`swap`](#swap) | 11 21 48 |
| [`encodings`](#encodings) | 12 15 17 50 51 52 53 |
| [`terminal`](#terminal) | 19 24 61 67 |
| [`text`](#text) | 28 44 57 64 65 66 |
| [`scripts`](#scripts) | 29 35 75 |
| [`completion`](#completion) | 32 59 |
| [`commands`](#commands) | 33 37 47 80 81 |
| [`mappings`](#mappings) | 34 58 |
| [`windows`](#windows) | 36 39 40 68 72 73 |
| [`buffers`](#buffers) | 38 41 42 45 46 69 70 71 77 |
| [`tidy`](#tidy) | 78 79 82 |

### seed

The copy that every later phase is measured against. Stage `0`.

| phase | title | stage |
| --- | --- | --- |
| 0 | seed, and prove the copy is a copy | `0` |

### environment

What the host would have to provide: an installed runtime, a locale, a home directory and environment variables, a maths library, signals. Stages `1-12`, `13-41`.

| phase | title | stage |
| --- | --- | --- |
| 1 | no `$VIMRUNTIME` | `1-12` |
| 9 | the editor stops asking the environment what language it is in | `1-12` |
| 20 | nothing outside the process is consulted | `13-41` |
| 23 | no floating-point library | `13-41` |
| 26 | five signals, not twenty-one | `13-41` |

Relies on:

- **20** after **18** (`startup`), *mechanical* — vimrc_found()'s callers are dead: every do_source() passes DOSO_NONE since 18
- **26** after **11** (`swap`), *rationale* — SIGPWR's handler called ml_sync_all(), empty since 11 (tools/noswap.py)
- **26** after **21** (`swap`), *rationale* — deathtrap() cannot preserve: 21 removed preserve_exit()'s loop (tools/nomemfile.py)

Relied on by: 12 (`encodings`), 21 (`swap`), 25 (`files`), 31 (`files`).

### options

Options as a table: the rows no feature reads any more, and every way to make two copies of one differ. Stages `1-12`, `13-41`, `42-63`.

| phase | title | stage |
| --- | --- | --- |
| 2 | the options for features that are not here | `1-12` |
| 16 | six options that no longer decide anything | `13-41` |
| 49 | one set of options | `42-63` |
| 54 | no option without a variable | `42-63` |
| 55 | no option nothing reads | `42-63` |
| 56 | no shell, runtime or keyword-program options | `42-63` |
| 60 | no suffix, case, delay, verbose-file, debug or filter-program options | `42-63` |
| 62 | no buffer-type, file-type, listing, jump, update-time or autowrite options | `42-63` |

Relies on:

- **16** after **10** (`tags`), *mechanical* — 'tags' and 'tagcase' have decided nothing since the tag stack went
- **16** after **11** (`swap`), *mechanical* — 'swapfile': ml_open() says no swap file whatever it is set to, since 11
- **16** after **13** (`files`), *mechanical* — 'autoread': ex_drop() saved and restored it around a check 13 removed
- **16** after **14** (`files`), *mechanical* — 'path' and 'suffixesadd' have decided nothing since the file finder went
- **54** after **53** (`encodings`), *mechanical* — its row set is COMPUTED, and holds 'arabic' only once 53's second cut is swept
- **56** after **8** (`files`), *mechanical* — 'shell', 'shellquote', 'shellredir': no shell is run since 8
- **56** after **30** (`tags`), *mechanical* — 'keywordprg': K went in 30
- **60** after **7** (`files`), *mechanical* — 'suffixes' ordered wildcard matches, and nothing has expanded since 7
- **60** after **44** (`text`), *mechanical* — 'formatprg', 'equalprg' only built a :{range}! line, ex_ni since 44
- **62** after **11** (`swap`), *mechanical* — 'updatetime': the idle sync reached ml_sync_all(), empty since 11
- **62** after **35** (`scripts`), *mechanical* — 'buflisted', 'filetype': their readers chose events, and 35 made dispatch FALSE

Relied on by: 64 (`text`), 65 (`text`).

### startup

What an invocation may say: the binary's name, the command-line flags, and the files read before the first command. Stages `1-12`, `13-41`, `42-63`.

| phase | title | stage |
| --- | --- | --- |
| 3 | no introduction, and the command line says only what the editor still decides | `1-12` |
| 4 | the binary's name stops choosing what it does | `1-12` |
| 18 | nothing is read at startup, and nothing on the command line decides anything | `13-41` |
| 43 | no -c, --cmd, -R, -m, -M or -w | `42-63` |

Relied on by: 20 (`environment`), 35 (`scripts`).

### regexp

One engine, and the parts of a pattern nothing here writes. Stages `1-12`, `13-41`, `73-77`.

| phase | title | stage |
| --- | --- | --- |
| 5 | one regexp engine, not two | `1-12` |
| 27 | `[[=a=]]` stops meaning "a with any accent" | `13-41` |
| 76 | one regexp engine, so no retry | `73-77` |

### files

The editor reaching the filesystem on its own account: globbing, directories, `path` search, timestamps, backups, the shell and file-name modifiers. Stages `1-12`, `13-41`.

| phase | title | stage |
| --- | --- | --- |
| 6 | the editor stops writing shell scripts, and stops drawing a menu | `1-12` |
| 7 | the editor stops looking for files it was not given | `1-12` |
| 8 | `:!` keeps its name and loses its process | `1-12` |
| 13 | the editor stops re-reading a file it has already read | `13-41` |
| 14 | a file name means the file of that name | `13-41` |
| 22 | the working directory is where it started | `13-41` |
| 25 | a write is a write, and nobody owns it | `13-41` |
| 31 | file-name modifiers | `13-41` |

Relies on:

- **25** after **20** (`environment`), *mechanical* — get_user_name() is `return FAIL;` since 20, so its caller's test folds
- **31** after **20** (`environment`), *rationale* — :~ shortened a name under $HOME, a notion 20 removed

Relied on by: 16 (`options`), 30 (`tags`), 32 (`completion`), 33 (`commands`), 44 (`text`), 56 (`options`), 60 (`options`), 79 (`tidy`).

### tags

Finding a place by name: the tag stack and tag keys, the jump list, file marks. Stages `1-12`, `13-41`, `42-63`, `73-77`.

| phase | title | stage |
| --- | --- | --- |
| 10 | no tag stack | `1-12` |
| 30 | `K` and the tag jumps, keeping `*` and `#` | `13-41` |
| 63 | no jump list | `42-63` |
| 74 | no file marks | `73-77` |

Relies on:

- **30** after **8** (`files`), *rationale* — K ran 'keywordprg' through :!, which has had no process since 8
- **74** after **70** (`buffers`), *rationale* — fname2fnum() is an empty body since 70, left for the file-mark cut

Relied on by: 16 (`options`), 32 (`completion`), 56 (`options`).

### swap

The swap file, recovery, and the memfile as a disk format. Stages `1-12`, `13-41`, `42-63`.

| phase | title | stage |
| --- | --- | --- |
| 11 | nothing is written that was not asked for | `1-12` |
| 21 | there is nothing to recover, and the memfile is memory | `13-41` |
| 48 | no `:noswapfile` | `42-63` |

Relies on:

- **21** after **20** (`environment`), *rationale* — :undolist's clock time goes because 20 took every way of being told the zone

Relied on by: 16 (`options`), 17 (`encodings`), 26 (`environment`), 62 (`options`), 70 (`buffers`), 77 (`buffers`).

### encodings

One encoding and one line ending: UTF-8, LF, and the conversion layer behind them. Stages `1-12`, `13-41`, `42-63`.

| phase | title | stage |
| --- | --- | --- |
| 12 | UTF-8, and no other encoding, ever | `1-12` |
| 15 | the last two encoding options | `13-41` |
| 17 | the last two per-buffer encoding options | `13-41` |
| 50 | only LF text files | `42-63` |
| 51 | a byte that is not UTF-8 is kept as it is | `42-63` |
| 52 | UTF-8 is not a question | `42-63` |
| 53 | no conversion layer, no 'encoding' | `42-63` |

Relies on:

- **12** after **9** (`environment`), *mechanical* — mb_init() refuses all but utf-8; the compiled default is utf-8 only since 9
- **17** after **11** (`swap`), *mechanical* — add_b0_fenc() wrote into a swap file's block zero, and 11 left none

Relied on by: 54 (`options`), 79 (`tidy`).

### terminal

What the terminal is told and asked beyond drawing: its type from the environment, the mouse protocol, the window title. Stages `13-41`, `42-63`, `66-71`.

| phase | title | stage |
| --- | --- | --- |
| 19 | the terminal is what the build says | `13-41` |
| 24 | there is no mouse | `13-41` |
| 61 | no window title | `42-63` |
| 67 | no mouse, no spell plumbing, no write-only flags | `66-71` |

### text

Operations on text that go: C and lisp indenting, filters and alignment, formatting, rot13 and the operator function, sentence and paragraph motions. Stages `13-41`, `42-63`, `64-65`, `66-71`.

| phase | title | stage |
| --- | --- | --- |
| 28 | C indenting | `13-41` |
| 44 | no filters, sorting or alignment | `42-63` |
| 57 | no lisp | `42-63` |
| 64 | no formatting, comment or nroff-macro options | `64-65` |
| 65 | no rot13, no operator function, no empty key handler | `64-65` |
| 66 | no sentences, paragraphs, sections, methods, #if blocks or comment blocks | `66-71` |

Relies on:

- **44** after **8** (`files`), *rationale* — :r !cmd and :w !cmd keep reaching do_bang() for 8's refusal
- **64** after **60** (`options`), *mechanical* — = only re-applied the existing indent once 'equalprg' went in 60
- **65** after **55** (`options`), *rationale* — g@ had no 'operatorfunc' to call after 55
- **65** after **32** (`completion`), *mechanical* — ins_ctrl_x() is empty since 32 (tools/nocomplkeys.py), so its call goes

Relied on by: 60 (`options`).

### scripts

Anything that runs later or from a file: user commands, scripts and sessions, autocommands. Stages `13-41`, `73-77`.

| phase | title | stage |
| --- | --- | --- |
| 29 | `:command`, user-defined commands | `13-41` |
| 35 | no scripts, no session, no autocommands | `13-41` |
| 75 | no autocommands | `73-77` |

Relies on:

- **35** after **18** (`startup`), *rationale* — a script has nowhere to come from: nothing is read at startup since 18

Relied on by: 62 (`options`), 68 (`windows`), 78 (`tidy`), 79 (`tidy`).

### completion

Insert-mode and command-line completion. Stages `13-41`, `42-63`.

| phase | title | stage |
| --- | --- | --- |
| 32 | insert completion, the popup menu, and the keys that reached them | `13-41` |
| 59 | no command-line completion | `42-63` |

Relies on:

- **32** after **10** (`tags`), *rationale* — the tag source of CTRL-X completion was already gone
- **32** after **7** (`files`), *rationale* — file-name completion went through the globbing 7 removed

Relied on by: 65 (`text`), 79 (`tidy`).

### commands

The Ex command layer itself: rows that only refuse, rows that duplicate a key, the table, and the bar. Stages `13-41`, `42-63`, `80`, `81`.

| phase | title | stage |
| --- | --- | --- |
| 33 | commands whose machinery has already gone | `13-41` |
| 37 | no command that does nothing | `13-41` |
| 47 | no `:startinsert`, `:startreplace`, `:startgreplace` or `:stopinsert` | `42-63` |
| 80 | the Ex command table, cut to the commands that exist | `80` |
| 81 | one line, one command | `81` |

Relies on:

- **33** after **8** (`files`), *rationale* — :shell's row goes because it has answered E319 since 8
- **80** after **79** (`tidy`), *mechanical* — the length field's one reader, the Vim9 whole-name check, is dead since 79

### mappings

Keys the editor rewrites as they are typed: abbreviations and language mappings. Stages `13-41`, `42-63`.

| phase | title | stage |
| --- | --- | --- |
| 34 | no abbreviations | `13-41` |
| 58 | no language mappings | `42-63` |

### windows

One tab page, one window, one frame — first the commands, then the structure. Stages `13-41`, `66-71`, `72`, `73-77`.

| phase | title | stage |
| --- | --- | --- |
| 36 | one tab page, always | `13-41` |
| 39 | one window, always | `13-41` |
| 40 | no window sizes to set | `13-41` |
| 68 | one window, structurally | `66-71` |
| 72 | one window, one tabpage, structurally | `72` |
| 73 | one frame | `73-77` |

Relies on:

- **68** after **35** (`scripts`), *mechanical* — the autocommand window ran autocommands, and dispatch is FALSE since 35

Relied on by: 45 (`buffers`), 46 (`buffers`), 77 (`buffers`), 78 (`tidy`), 79 (`tidy`).

### buffers

One buffer and no argument list — first the commands, then the structure. Stages `13-41`, `42-63`, `66-71`, `73-77`.

| phase | title | stage |
| --- | --- | --- |
| 38 | the argument list is walked by `:next` and `:previous` alone | `13-41` |
| 41 | the buffer list is walked by `:bnext` and `:bprevious` alone | `13-41` |
| 42 | one buffer, always | `42-63` |
| 45 | no `:drop` | `42-63` |
| 46 | no `:wall`, `:qall`, `:quitall`, `:wqall` or `:xall` | `42-63` |
| 69 | one file argument, and no argument list | `66-71` |
| 70 | :e reloads in place, and there is no swap file | `66-71` |
| 71 | one buffer, structurally | `66-71` |
| 77 | no buffer-name argument matching | `73-77` |

Relies on:

- **45** after **39** (`windows`), *rationale* — with one window :drop was :args plus :first
- **46** after **39** (`windows`), *mechanical* — with one window :qall is :q, which is what exsweep.py falls back to
- **70** after **11** (`swap`), *mechanical* — ml_open_file() is only `b_may_swap = FALSE` since 11
- **70** after **21** (`swap`), *mechanical* — findswapname, swapfile_info and ml_recover went with recovery in 21
- **77** after **11** (`swap`), *mechanical* — it asserts every EX_BUFNAME row is ex_ni; :checktime went in 11
- **77** after **39** (`windows`), *mechanical* — the same assertion; :sbuffer went in 39

Relied on by: 74 (`tags`), 79 (`tidy`).

### tidy

What no package owns: empty functions, write-only counters, constant predicates, headers and comments. Stages `78`, `79`, `82`.

| phase | title | stage |
| --- | --- | --- |
| 78 | empty functions, write-only counters, and the window id | `78` |
| 79 | the constant-return predicates | `79` |
| 82 | the system headers nothing needs, and every comment | `82` |

Relies on:

- **78** after **75** (`scripts`), *mechanical* — autocmd_blocked and prevwin lost their last readers in 75
- **78** after **68** (`windows`), *mechanical* — w_id is a constant only because 68 left one window
- **79** after **13** (`files`), *mechanical* — asserts check_timestamps() is `return 0;`, which 13 made it
- **79** after **17** (`encodings`), *mechanical* — asserts bomb_size() is `return 0;`, which 17 made it
- **79** after **32** (`completion`), *mechanical* — asserts pum_visible(), ins_compl_active() and five more are constant (32)
- **79** after **35** (`scripts`), *mechanical* — asserts in_vim9script() and the `has_*()` event tests are FALSE (35)
- **79** after **59** (`completion`), *mechanical* — asserts wc_use_keyname() is `return FALSE;`, which 59 made it
- **79** after **36** (`windows`), *mechanical* — asserts tabline_height() is `return 0;`, which 36 made it
- **79** after **39** (`windows`), *mechanical* — asserts check_can_set_curbuf_forceit/_disabled() are TRUE (39)
- **79** after **68** (`windows`), *mechanical* — asserts only_one_window() is `return TRUE;`, which 68 made it
- **79** after **72** (`windows`), *mechanical* — asserts current_win_nr() and current_tab_nr() are `return 1;` (72)
- **79** after **73** (`windows`), *mechanical* — asserts stl_connected() is `return FALSE;`, which 73 made it
- **79** after **69** (`buffers`), *mechanical* — asserts check_more() is OK and append_arg_number() is 0 (69)

Relied on by: 80 (`commands`).

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
`termcheck.py` all ran `-u NONE -e -s` and nothing else. The removed link's own
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

Measured: **180,328 → 178,431 lines**, 1,368 of them taken by the sweep in three
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
8 and not with globbing here. That was measured rather than reasoned about,
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

All of it goes, **and so does `-u`**. `-u <file>` was the one branch left that
read a file, and `-u NONE` — how every harness kept a vimrc out of a recorded run
— is a no-op once nothing is searched for. With no path to search and no name to
be given, `source_startup_scripts()` has no body, its call goes, and the sweep
takes it; the `-u NONE` test in `main()` that switched `'loadplugins'` off goes
with the option it asked about. `:source` stays until Phase 35.

**It goes here, not later, so that no tool depends on it.** The harnesses are
shared with the slim pipeline, whose editor still searches, so they could not
simply stop passing `-u NONE`. They isolate through the environment instead — an
empty `$HOME`, `$VIM`, `$VIMRUNTIME` and `$XDG_CONFIG_HOME` — which is what `-u
NONE` was for and holds for both editors. Measured against `slim-vim`, with a
real `~/.vimrc` present on the machine: 0 of 67 behaviour cases, 0 of 600 Ex
commands and 0 of 19 terminal rows differ from the baselines recorded with `-u
NONE`, and `tools/verify.sh` is all clear. `tools/clicheck.py` still checks `-u
rc.vim` as an option at Phase 3, where it exists.

`set_init_xdg_rtp()` goes with them. It built a `'runtimepath'` out of
`$XDG_CONFIG_HOME`, and **Phase 1 emptied that option while this was still
filling it back in** — an option reported as empty and rebuilt at startup, which
is the kind of thing only a survey of every `getenv` finds. So does
`process_env()`, which ran `$VIMINIT` or `$EXINIT` as Ex commands, and `'exrc'`,
which selected between two searches that no longer happen.

#### The delta

**None, and that is the point rather than a surprise.** No harness passes `-u`,
and under an empty environment none of these paths is taken. What changes is
that the editor no longer needs to be told — and that it can no longer be told.
The phase checks that `-u NONE` is now an unknown option against a control that
still runs.

### command-line options that no longer decide anything

Four outlived what they controlled, each in a different way.

| | why it is inert |
| --- | --- |
| `-y` | evim mode. `parmp->evim_mode` is assigned and read nowhere — its one reader was the line Phase 18 removed |
| `-Z` | restricted mode, whose purpose is to refuse shell commands. `check_restricted()` has two callers left: `do_bang()`, stubbed in Phase 8, and `ex_stop()`. No *live* command carries `EX_RESTRICT` either — the ten that do are all `ex_script_ni` |
| `-t` | jump to a tag at startup, by running `:ta <tag>`. Phase 10 retired `:tag`, so its whole effect is to run a command that reports it is not implemented |
| `-i` | the viminfo file. `'viminfo'` and `'viminfofile'` are wired to `(char_u *)NULL` in **both** editors — the tiny configuration has no viminfo at all |

**`-u` went above**, with the search it used to suppress.

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
| the tables | 22 rows of `nv_cmds[]` point at `nv_error`, and the 14 `<LeftMouse>`/`<ScrollWheelUp>`/`<MouseMove>` rows of the key-name table go, so `:map <LeftMouse>` no longer names anything |
| the dispatch | `edit()`'s insert-mode case run, `getcmdline_int()`'s six case runs, `]<LeftMouse>` in `nv_brackets()` and `g<LeftMouse>` in `nv_g_cmd()`, and the click that dismissed a `Press ENTER` prompt |
| the decoder | `check_termcode_mouse()`'s call, and 41 lines in `set_termname()` that read the terminal's 1006 capability, set `'ttymouse'` from it and install the termcodes |
| the switch | `setmouse()`'s **31** calls, every one a bare statement, and `mch_setmouse()`'s |
| the questions | `mouse_has()` and `mouse_has_any()`, whose three callers outside the island each become the answer they now always get |

### The rows of nv_cmds[] are pointed away, never deleted

**This phase first deleted the 22 rows, and the arrow keys stopped working in
normal mode for twelve phases.** Normal mode finds a key's handler through
`nv_cmd_idx[]`, a sorted index into `nv_cmds[]` that upstream generates and this
tree writes into the C as a constant. Deleting rows left the index 22 entries
longer than the table, still compiling, and every key found past the first hole
resolved to another key's row. Nothing noticed because every harness that typed
an arrow typed it in insert mode, which decodes the arrows in a `switch`.

So the rows stay and answer `nv_error` — rule 3, applied to the normal-mode
table, which is what Phase 30 already did for `K` and CTRL-]. Two checks now
guard it: `tools/nvidxcheck.py`, run by `phasecheck.sh` in every phase, requires
the index to be a permutation of the table's rows, and `tools/arrowcheck.py` —
retired after Phase 82, see there — pressed all four arrows in normal mode, in the `ESC O` form a terminal sends once
vim has switched its keypad to application mode.

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
`ml_sync_all()` — **an empty function** since Phase 11; `SIGUSR1`, whose flag
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

Measured: 142,170 → 138,178 lines, 3,992 removed against 3,007 predicted; the
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
through `:!` and Phase 8 took the process behind it; the tag jumps build `ta `, `tj `,
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

Measured: 136,190 → 135,941 lines; `nv_ident()` from 227 lines to the search
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

Measured: 135,941 → 135,315 lines.

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
notice, so `tools/arrowcheck.py` (since retired) asked in a pty: from `one/two/three`, `A` then
Down then `X` must give `twoX`. **It was proved able to fail first** — with
`ins_down()` removed it reports `oneX`.

### The delta

Measured: **135,315 → 127,131 lines** and symbols 88 → 88, the subsystem being
pure computation over things already removed. The thirteen functions that remain
of the island are constant-answer stubs the redraw layer asks on its own account.
**Merged, the phase reproduces the boundary the two phases recorded byte for
byte**, in 173 seconds against the 203 they took in sequence. **The delta is
none** — no behaviour case types CTRL-N, these are insert-mode keys, and no Ex
command moves.

## Phase 33 — commands whose machinery has already gone

Every one of these still had a handler, and every one refused or did nothing
when run with a sensible argument. That was measured one at a time, in Ex mode,
reading the message each left behind:

| command | what it said |
| --- | --- |
| `:shell` | `E319`, no processes since Phase 8 |
| `:gui`, `:gvim` | `E25`, no GUI in this build |
| `:cdo` `:cfdo` `:ldo` `:lfdo` | `E319`, no quickfix lists |
| `:vim9cmd` | `E319`, no eval layer |
| `:endclass` `:endinterface` `:endenum` `:public` `:static` `:this` | Vim9 class keywords, invalid without the eval layer |
| `:digraphs` | `E196`, no digraphs in this build |
| `:redrawtabpanel` | `E1547`, no tab panel |
| `:colorscheme` | `E185`, no colour scheme to find — nothing is installed |

**A command that only says no is a row pointing at a handler that exists to say
no.** So the rows go to `ex_ni` — rule 3, the table keeps its shape — and the
sweep takes `ex_shell`, `ex_nogui`, `ex_digraphs`, `ex_redrawtabpanel`,
`ex_colorscheme` and `load_colors()`, which nothing else called. `ex_listdo`
stays, because `:argdo`, `:bufdo`, `:windo` and `:tabdo` use it, and its two tests
for the quickfix commands are folded rather than left asking a question that can
no longer be true. `ex_wrongmodifier` stays for the modifiers that still work.

**`:!` is the one refusal kept, and on purpose.** `:!cmd`, `:r !cmd` and `:w !cmd`
are how a user reaches for a process, and the answer Phase 8 gave them is the
sentence it prints. `:filetype` and `:vim9script` are not here either: they run
without an error, and nothing measured shows them refusing.

Left alone, as every earlier phase left them: the arms of
`set_context_by_cmdname()` that set up command-line completion for these names.
A retired row still parses, so its completion context still fires, and it
completes nothing.

### A tool bug this found

`tools/retire.py` matched a row with exactly one space before the handler, and
the `:gui` and `:gvim` rows are spelled `- 1,  ex_nogui ,` — macro expansion's
spacing. It refused, loudly, which is what it is for; the rule is the row, not
the spacing, so it takes any whitespace now. The six earlier phases that retire
rows with it were re-verified and all reproduce their boundaries.

### The delta

**`:colorscheme`**, which run bare reported the current scheme and succeeded in
`slim-vim`, and now reports that it is not implemented. Every other row already
failed, or is one the sweep skips because it hands over the terminal. Measured:
127,131 → **127,037 lines**, libc symbols 88 → 88.

## Phase 34 — no abbreviations

An abbreviation is a word the editor rewrites as you type it. Nothing reads a
vimrc here, so the only way to have one was to type `:abbreviate` in the session
that wanted it — and the twelve rows that did that, `:abbreviate`, `:noreabbrev`,
`:unabbreviate`, `:abclear` and their `i` and `c` forms, go to `ex_ni`.

**Retiring the rows removes the answer, not the question.** Insert mode asked
`echeck_abbr()` on ESC, CTRL-O, CTRL-L, Tab, Enter and every non-word character,
and the command line asked `ccheck_abbr()` twice, and each would go on asking
for ever and being told no. `tools/noabbr.py` removes the questions, each a fold
whose answer is now known:

- `if (echeck_abbr(...)) { ... }` and `if (ccheck_abbr(...)) { ... }` guard what
  happens when an abbreviation fired, so the blocks go;
- `!echeck_abbr(x) && c != Ctrl_RSB` is `c != Ctrl_RSB`;
- `(ccheck_abbr(x) || c == Ctrl_RSB)` is `c == Ctrl_RSB` — CTRL-] on the command
  line still triggers "an abbreviation", which is to say nothing, and still does
  not insert itself.

The sweep then takes `check_abbr()` — 195 lines — its two wrappers,
`ex_abbreviate` and `ex_abclear`. **What stays** is the mapping code's `abbr`
parameters and list, which mappings share; nothing can put an entry on that list
any more, and nothing here pretends that makes the shared code smaller.

The tool's own check failed twice before the phase ran, both times on itself:
it counted `check_abbr()` calls inside the two wrappers the sweep removes, and
then prototypes it matched with one space where the file has two. **A check that
cannot tell a caller from a definition is measuring the wrong thing**, and it
now asks only about calls outside the definitions going away.

### The delta

**The nine rows that succeeded run bare** — `:abbreviate`, `:noreabbrev` and
`:abclear` with their `i` and `c` forms, which listed or cleared nothing and
exited 0 — measured before the cut. The three `:unabbreviate` rows already failed
with no argument. Measured: 127,037 → **126,756 lines**, libc symbols 88 → 88.

## Phase 35 — no scripts, no session, no autocommands

Three things that are one question: can the editor be told to do something
later, or somewhere else, by a file? A script is commands read from a file, a
session is a script the editor wrote about itself, and an autocommand is a
command registered now to run when an event happens. None of them has anywhere
to come from: nothing is installed, no vimrc is searched for, and since Phase 18
nothing at all is read at startup.

| | what goes |
| --- | --- |
| scripts | `:source` `:scriptencoding` `:scriptversion` `:vim9script` `:legacy`, the `vim9cmd` modifier, `'loadplugins'` |
| the session | `:redir` `:sleep` `:smile` `:sandbox`, `-S`, `-s file`, `-w`/`-W file`, `'sessionoptions'` `'viewoptions'` `'viewdir'` |
| autocommands | `:autocmd` `:augroup` `:doautocmd` `:doautoall` `:noautocmd` `:filetype` `:setfiletype`, the engine, `'eventignore'` `'eventignorewin'` |

The sixteen rows go to `ex_ni`. `tools/nosession.py` removes what a row cannot:

- **The modifiers are parsed by name.** `parse_command_modifiers()` matches
  `legacy`, `noautocmd`, `sandbox` and `vim9cmd` before the table is consulted,
  so retiring a row changes nothing about `:noautocmd w`. The four blocks go,
  with the save and restore of `'eventignore'` that `:noautocmd` did.
- **The engine is answered at its doors.** `apply_autocmds_group()`,
  `has_autocmd()` and the per-event `has_*()` say no, and the `trigger_*()`
  helpers and `may_trigger_win_scrolled_resized()` do nothing — which is what
  each already did with no autocommand defined. The sweep takes the engine
  behind the doors. The calls that fire events stay: each is a call to a
  constant now, and removing them is a phase of its own.
- **Filetype detection after a rename** ran only when the `filetypedetect` group
  existed, which only `:augroup` or `:autocmd` could make; both tests fold, and
  `do_doautocmd()` goes with its last callers.
- **`in_vim9script()` is FALSE**: it was true only after `:vim9script` or under
  `vim9cmd`.
- **Suspending stays.** CTRL-Z, `:stop` and `:suspend` still hand the terminal
  back to the shell. The first version of this phase took them as part of the
  session and they were put back on request: suspending is job control, and
  nothing about it is read from or written to a file.
- **The command line loses its scripts.** `-S`, `-s file` outside Ex mode, and
  `-w file`/`-W file` are unknown options. `-s` keeps silent Ex mode after `-e`,
  `-wN` still sets `'window'`, and `-u file` stays.

### Two options that have to go before the sweep

`dropoptions.py --strict` refused `'eventignore'` after the first sweep: the
readers `event_ignored()` and `check_ei()` were still live. Two things held them.
`did_set_eventignore()` is the callback of **both** `'eventignore'` and
`'eventignorewin'`, and calls `check_ei()` — so while either row stands, the
reader is reachable from the option table and no sweep can take it, and
`--strict` cannot be satisfied in either order. And the WinScrolled/WinResized
scan read `'eventignorewin'` from every window before learning that neither
event had an autocommand.

So both rows go **before** the sweep and without `--strict`, and the
post-condition is the check: after the sweep nothing names `p_ei`, `wo_eiw`,
`check_ei`, `event_ignored` or `check_window_scroll_resize`. The enumerator
`WV_EIW` stays, named only by its own declaration: the `WV_` and `BV_` index
enums are anonymous, `enum { WV_LIST = 0, ... }`, and the definition finder
`deadenums.py` walks sees only tagged and typedef'd enums, so it never examines
them. That is a gap in a shared tool, measured here and not yet closed — closing
it changes every phase's implementation digest.
`'eventignorewin'` is window-local and `tools/droplocal.py` knows only buffer
fields, so `nosession.py` removes its field and the four places that maintain
it — `get_varp()`, `copy_winopt()`, `check_winopt()`, `clear_winopt()` — itself.

### The delta

**The ten rows that succeeded run bare** — `:sleep`, `:smile`, `:vim9script`,
`:autocmd`, `:augroup`, `:doautocmd`, `:doautoall`, `:noautocmd`, `:sandbox` and
`:filetype` — measured before the cut. `:source`, `:redir`, `:scriptencoding`,
`:scriptversion`, `:legacy` and `:setfiletype` already failed with no argument.
No harness sources, redirects,
suspends or defines an autocommand, and each passes `-s` only after `-e`.
Measured: 126,756 → **123,384 lines**, libc symbols 88 → 88.

## Phase 36 — one tab page, always

A tab page is a set of windows the editor can switch between whole. The
tab-page list is also the container every window lives in — `curtab` and
`first_tabpage` are read in hundreds of places — so **it stays, with exactly one
entry**, and every way to make or reach a second one goes.

The fifteen rows go to `ex_ni`: `:tab`, `:tabnew`, `:tabedit`, `:tabclose`,
`:tabonly`, `:tabnext`, `:tabNext`, `:tabprevious`, `:tabfirst`, `:tabrewind`,
`:tablast`, `:tabmove`, `:tabs`, `:tabdo` and `:redrawtabline`.
`tools/notabs.py` removes what a row cannot:

- **The `:tab` modifier** is matched by name in `parse_command_modifiers()`, and
  it was the only thing that set `cmdmod.cmod_tab`. With it gone every test of
  `cmod_tab` is decided: the tab branches of `:all`, `:ball`, `:drop`,
  `:argedit`, `:wincmd` and the command-line window fold.
- **The handlers the tab commands shared** keep their other users. `:tabnew` and
  `:tabedit` went through `ex_splitview()` with `:split` and `:new`, and `:tabdo`
  through `ex_listdo()` with `:windo`, so only their terms and branches go.
- **Each key keeps the answer it already gave with one tab page.**
  `goto_tabpage(n)` with a single tab page beeps when `n > 1` and otherwise does
  nothing, and there is never a last-used tab page. So `gt`, CTRL-PageDown and
  CTRL-W gt beep for a count above 1; `gT`, CTRL-PageUp and CTRL-W gT do
  nothing; `g<Tab>`, CTRL-Tab and CTRL-W g`<Tab>` beep; insert mode's
  CTRL-PageUp and CTRL-PageDown stay no-ops. The keys are not given a new
  meaning — they lose a function nothing could reach.
- **CTRL-W T and CTRL-W gf/gF open a tab page and nothing else**, so they beep
  now, as an unknown window command does. CTRL-W T with one window used to say
  "Already only one window"; that message goes with the command.
- **The tab line** is 0 lines and `draw_tabline()` draws nothing — what both
  answered for one tab page under the default `'showtabline'`. `win_split()`
  no longer asks `may_open_tabpage()` whether a `:tab`-modified split became a
  tab page — a stub would have answered, and left the caller and the function
  alive, which is how the first run of this phase failed. The sweep then takes `'showtabline'`, `'tabline'`
  and `'tabpagemax'`'s readers, and `dropoptions.py --strict` their rows.
  `'tabclose'` is the Phase 35 trap again: its own callback, `did_set_tabclose()`,
  reads `p_tcl`, so while the row stands the reader is live and no order of sweep
  and `--strict` works. Its row goes before the sweep, and the post-condition —
  nothing names `p_tcl` or `tcl_flags` afterwards — is the check.

Left alone, as every earlier phase left them: the completion arms of
`set_context_by_cmdname()` for these names.

### The delta

**The thirteen rows that succeeded run bare** — `:tab`, `:tabedit`, `:tabfirst`,
`:tabmove`, `:tablast`, `:tabnext`, `:tabnew`, `:tabonly`, `:tabprevious`,
`:tabNext`, `:tabrewind`, `:tabs` and `:redrawtabline` — measured before the cut.
`:tabclose` and `:tabdo` already failed with no argument. No harness opens a tab
page. Measured: 123,384 → **122,290 lines**, libc symbols 88 → 88.

## Phase 37 — no command that does nothing

What was left in the table after Phase 36, read handler by handler, had ten
rows that either did nothing or did something this editor does not want:

| rows | what they did |
| --- | --- |
| `:browse`, `:confirm` | modifiers whose flags went with the file browser and the dialogs; each skipped its own name and ran the rest |
| `:tmap`, `:tnoremap`, `:tunmap`, `:tmapclear` | stored mappings for terminal-job mode, which nothing enters — no assignment puts `MODE_TERMINAL` in `State` |
| `:winpos` | "not implemented" bare; with two numbers, checked them and did nothing |
| `:behave` | set `'selection'`, `'selectmode'` and `'keymodel'` to another editor's habits — `mswin`'s naming the mouse, which Phase 24 removed |
| `:mode` | a screen-mode switch no terminal here has; bare, a redraw |
| `:open` | vi's open mode, which here was a cursor move followed by `:visual` |

All ten go to `ex_ni`. `tools/noinert.py` removes what a row cannot:

- **`:browse` and `:confirm` are matched by name in
  `parse_command_modifiers()`**, before the table, so their branches go; the
  name then reaches the table and is not implemented. `:browse set ic` no longer
  sets anything.
- **Terminal-job mappings.** `get_map_mode()` loses its `'t'` and
  `map_mode_to_chars()` the letter it printed. The `MODE_TERMINAL` enumerator
  and the masks that test it stay — constants, costing nothing.
- **Completion.** Unlike the phases before it, this one takes the
  `set_context_by_cmdname()` arms for its names, because `:behave`'s is what
  kept `get_behave_arg()` alive.

**`:highlight` stays.** It sets the colours of highlight groups, and `Search` is
the one `'hlsearch'` draws with; the defaults are applied through
`do_highlight()` whether or not the command exists, but changing them needs it.
Syntax highlighting is not in this build — the `:syntax` row already points
at `ex_ni`.

### The delta

**The seven rows that succeeded run bare** — `:browse`, `:confirm`, `:mode`,
`:open`, `:tmap`, `:tmapclear` and `:tnoremap`, read from the slim baseline.
`:behave`, `:tunmap` and `:winpos` already failed with no argument. Measured:
122,290 → **122,145 lines**, libc symbols 88 → 88.

## Phase 38 — the argument list is walked by `:next` and `:previous` alone

**The list stays.** `vim a b c` fills it, `:next` and `:previous` move through
it, `:next x y` replaces it, `:drop` sets it, and quitting with files not yet
edited is still refused. Every other command on it goes — twenty-five rows:
`:args`, `:argglobal`, `:arglocal`, `:argadd`, `:argdelete`, `:argdedupe`,
`:argedit`, `:argument`, `:sargument`, `:first`, `:sfirst`, `:rewind`,
`:srewind`, `:last`, `:slast`, `:snext`, `:wnext`, `:Next`, `:sNext`,
`:sprevious`, `:wNext`, `:wprevious`, `:all`, `:sall` and `:argdo`.

**`:Next` is a row of its own**, spelled apart from `:previous` though it shares
the handler, so `:N` goes with it; `:prev` still reaches `:previous`.

`tools/noarglist.py` removes what a row cannot:

- **The shared handlers keep their other users.** `:snext` went through
  `ex_next()`, and `:argdo` through `ex_listdo()` with `:bufdo` and `:windo`, so
  only their terms go; `do_argfile()` no longer spares `:argdo` the `'` mark.
  **`ex_rewind()` stays**, because `:drop` ends in it — the `:first` row going
  does not make its handler dead, and the phase checks that it survives.
- **Completion** for `:argdo` and `:argdelete`, and the argument-list expansion
  only `:argdelete` asked for, so the sweep takes `get_arglist_name()`.

The sweep takes the handlers, `do_arg_all()` and its helpers, `alist_new()` —
only `:arglocal` gave a window a list of its own — and `list_in_columns()`,
which only `:args` printed with.

### The delta

**The sixteen rows that succeeded run bare** — `:all`, `:args`, `:argadd`,
`:argdelete`, `:argdedupe`, `:argglobal`, `:arglocal`, `:argument`, `:first`,
`:last`, `:rewind`, `:sargument`, `:sall`, `:sfirst`, `:slast` and `:srewind`,
read from the slim baseline. The other nine already failed with no argument.
Measured: 122,145 → **121,368 lines**, libc symbols 88 → 88.

## Phase 39 — one window, always

The window list is the container the editor draws into, and `aucmd_prepbuf()`
still slots its hidden autocommand window into the frame tree beside the user's
with `win_split_ins()`. So **the list stays, with one user window in it**, and
every way to make, reach, resize, close or bind a second one goes.

Thirty-two rows go to `ex_ni`: `:split`, `:vsplit`, `:new`, `:vnew`, `:sview`,
`:close`, `:only`, `:resize`, `:wincmd`, `:windo`, `:syncbind`, `:hide`, `:sbuffer`,
`:sbNext`, `:sball`, `:sbfirst`, `:sblast`, `:sbmodified`, `:sbnext`,
`:sbprevious`, `:sbrewind`, `:ball`, `:unhide`, `:sunhide`, and the eight split
modifiers `:aboveleft`, `:leftabove`, `:belowright`, `:rightbelow`, `:topleft`,
`:botright`, `:vertical` and `:horizontal`. `tools/nowindows.py` removes what a row
cannot:

- **The modifiers** are matched by name in `parse_command_modifiers()` and were
  all that set `cmdmod.cmod_split`. **`:hide {cmd}` is a modifier too, and stays**
  — only bare `:hide`, which closed the window, is a row.
- **CTRL-W** points at `nv_error`, and `do_window()` goes with every window command
  behind it.
- **The command-line window is a split**, so it goes: `q:`, `q/` and `q?` are the
  recordings they would be without it, CTRL-F on the command line is an ordinary
  key, and every test of `cmdwin_type`, `cmdwin_win`, `cmdwin_buf` and
  `cmdwin_result` folds. `vgetorpeek()`'s `tc` remembered the previous key for one
  of those tests alone, and goes with it — the warning check caught it.
- **`-o` and `-O`** are unknown options, and startup opens no window per file:
  `create_windows()` loses its count and `edit_buffers()` its call.
  `tools/clicheck.py` still lists them as accepted, because it runs at Phase 3
  where they are; the phase checks they are refused, in its terms.
- **The paths that still split.** `:drop` split when the buffer could not be
  abandoned, and now does what `:first` does — refuses. `do_argfile()`'s `s`
  commands, `goto_buffer()`'s `:sb` family and `buflist_getfile()`'s
  `'switchbuf'` block fold.
- **`'scrollbind'`, `'cursorbind'`** bind one window to another, and
  **`'winfixbuf'`** is answered by splitting: their tests fold, their assignments
  and `get_varp()`/`copy_winopt()` plumbing go, and the rows go before the sweep.
  `'switchbuf'`, `'scrollopt'`, `'cmdwinheight'` and `'cedit'` lose their last
  reader here too — `'cedit'` via `didset_options()`, which a first run missed —
  and `'previewheight'` and `'previewwindow'` had none.

Left alone: `check_can_set_curbuf_disabled()` and `_forceit()` now always answer
yes and keep their nine callers, and `z{height}<CR>` still resizes the one window.

Checked in a terminal against `slim-vim`: after CTRL-W s, CTRL-W v or `q:`, `:q`
leaves the editor, where slim-vim stays open with the second window.

### The delta

**The twenty-seven rows that succeeded run bare**, read from the slim baseline.
`:close`, `:hide`, `:sbmodified`, `:wincmd` and `:windo` already failed.
Measured: 121,368 → **118,516 lines**, libc symbols 88 → 88.

## Phase 40 — no window sizes to set

With one window, `'winheight'`, `'winminheight'`, `'winwidth'`, `'winminwidth'`,
`'helpheight'`, `'splitbelow'`, `'splitright'`, `'splitkeep'`, `'equalalways'`,
`'eadirection'`, `'winfixheight'` and `'winfixwidth'` have nothing to decide. The
rows go. **The values do not**, and that is the whole difficulty of the phase.

The frame arithmetic still runs — `aucmd_prepbuf()` inserts its hidden window
with `win_split_ins()` and `win_close()` takes it out — and it reads the size
globals as it goes. A row is what writes a default into its global (see
`tools/orphanopts.py`), so dropping one alone would leave `p_wmh` at 0 and
`p_spk` NULL. **`tools/nowinsizes.py` gives each global its default as an
initialiser of its own** before the rows go: `FALSE`, `FALSE`, `"cursor"`, `TRUE`,
`"both"`, `1`, `1`, `20`, `1`. The value is exactly what the defaults gave, and
nothing can change it; the arithmetic keeps its own temporary writes, which a
variable allows as well as an option. `orphanopts.py` accepts an initialised
global by construction.

The two window-local fields are never set now, so their tests fold instead:
`win_split_ins()` keeping a fixed size, `winframe_remove()` passing over one,
`frame_setheight()`/`frame_setwidth()` reserving room for one, `win_enter_ext()`
sparing one, and `command_height()`'s loop over fixed-height frames, which never
runs. `frame_fixed_height()` and `frame_fixed_width()` answer `FALSE` for a window
and keep their recursive callers. `'helpheight'` had no reader but the callback
it shared with `'winheight'`, and the sweep takes both.

### The delta

**None the Ex sweep records beyond Phase 39's** — no row is retired. Each of the
twelve names is refused by `:set` now, which the phase probes against a
`:set ignorecase` control. Measured: 118,516 → **118,130 lines**, libc symbols
88 → 88.

## Phase 41 — the buffer list is walked by `:bnext` and `:bprevious` alone

**The list stays.** Every file edited is a buffer on it, `:bnext` and
`:bprevious` move through it, `:e #` reaches the alternate one, and
quitting still refuses while a hidden buffer is changed. Every other command on
it goes — fifteen rows: `:buffer`, `:buffers`, `:files`, `:ls`, `:badd`, `:balt`,
`:bdelete`, `:bunload`, `:bwipeout`, `:bfirst`, `:brewind`, `:blast`,
`:bmodified`, `:bNext` and `:bufdo`.

**`:bNext` is a row of its own**, spelled apart from `:bprevious` though it shares
the handler, so `:bN` goes with it; `:bp` still reaches `:bprevious`.

`tools/nobuflist.py` removes what a row cannot:

- **`:badd` and `:balt`** went through `ex_edit()` and `do_exedit()` with `:edit`,
  so only their terms go — and `do_ecmd()`'s `ECMD_ADDBUF` and `ECMD_ALTBUF`
  paths, which nothing else passed.
- **`:bdelete`, `:bwipeout` and `:bunload`** were `do_bufdel()` and `do_buffer()`,
  which the sweep takes. That leaves `do_buffer_ext()` one caller, `goto_buffer()`,
  and one action, `DOBUF_GOTO`, so its `unload` is always false and every branch
  that unloaded, deleted or wiped folds. **That fold is true only after the
  sweep**, so the phase asks after it: exactly one call, and that one.
  `set_curbuf()` and `empty_curbuf()` keep their unload paths, because
  `check_changed_any()` still passes one. `do_one_cmd()` stops asking whether a
  buffer-name argument belongs to one of the three.
- **Completion** for the retired names. `ex_listdo()` had `:bufdo` as its last
  user and goes whole.

A first run counted the retired names before the sweep, and found four in
`ex_listdo()` and `ex_bunload()` — handlers with no row, which the sweep then
took. The count is asked after the sweep now.

### The delta

**The ten rows that succeeded run bare** — `:buffer`, `:bNext`, `:bdelete`,
`:bfirst`, `:blast`, `:brewind`, `:buffers`, `:bwipeout`, `:files` and `:ls`, read
from the slim baseline. `:badd`, `:balt`, `:bmodified`, `:bufdo` and `:bunload`
already failed with no argument. Measured: 118,130 → **117,506 lines**, libc
symbols 88 → 88.

## Phase 42 — one buffer, always

The buffer list is the container the editor edits in — `firstbuf`, `curbuf` and
the buffer hash table are read everywhere — so **it stays, with exactly one
buffer on it between commands**. Two decisions were the user's, not the
process's, and were asked: editing another file **reuses the one buffer**, and
**there is no alternate file**.

**The mechanism is `'bufhidden=wipe'`, made unconditional.** `do_ecmd()` still
makes the new buffer and then closes the old one; it closes it with `DOBUF_WIPE`
instead of `DOBUF_UNLOAD`, or not at all under `ECMD_HIDE`. So `:e`, `:enew`,
`:next`, `:previous`, `:drop` and `gf` work as before, and a file left behind
takes its undo history, marks and local options with it. Changes cannot be lost
by it: `do_ecmd()` has already refused a changed buffer unless it was written or
`!` was given, exactly as under `'nohidden'`.

Three rows go to `ex_ni` — `:bnext`, `:bprevious` and `:keepalt` — and
`tools/onebuffer.py` removes what a row cannot:

- **Nothing is hidden.** `buf_hide()` answered from `'hidden'`, the `:hide`
  modifier and `'bufhidden'`, and all three go, so each of its sixteen call sites
  folds as if it said no and the sweep takes it. `close_buffer()` stops reading
  `'bufhidden'`, and `tools/droplocal.py` takes the field.
- **No alternate file**, which is itself a second buffer. Nothing writes
  `w_alt_fnum`: `do_ecmd()`, `set_curbuf()`, `do_exedit()` and `win_init()` stop,
  `:file`, `:read` and `:write` stop making an alternate buffer for a name, and
  `buflist_findnr(0)` and a `#` pattern find nothing — which is what they did when
  there was no alternate. CTRL-^ points at `nv_error`; `:e #` fails.
- **`:saveas` renamed the buffer by swapping names with an alternate buffer**
  made for the new name. With no alternate it would have written the file and
  kept the old name, so it renames the one buffer with `setfname()`. It is the one
  addition in the phase, and the reason is that the mechanism, not the behaviour,
  needed a second buffer.
- **The argument list stops making buffers.** `alist_add()` put every file
  argument on the buffer list, unloaded, when it was named. An entry is a name now,
  buffer number 0 — `alist_name()` and `editing_arg_idx()` already fall back to the
  name — and the one buffer is named for the first file only while it is still the
  empty buffer startup made.

**Stays:** `:qall`, `:wall`, `:wqall` and `:xall`, which are `:q` and `:w` with one
buffer, and which every harness here quits with. `'buflisted'`, whose field is
internal state the buffer code reads. No command-line option opened more than one
buffer, so none goes.

The phase checks the behaviour it changes against what it replaces: under
`'nohidden'` an unloaded buffer keeps its marks, so marking a line, editing
another file and coming back finds the mark; with one buffer it is gone, and
deleting to it changes nothing. It checks that `:e #` is refused and that
`:saveas` renames.

Two first runs failed usefully: the leftover counts included `setaltfname()` and
`buf_hide()`, which have no caller and which the sweep takes, and
`rename_buffer()`'s `xfname` had held the old short name for the alternate alone.

### The delta

**`:bnext`, `:bprevious` and `:keepalt`**, which succeeded run bare. Measured:
117,506 → **117,013 lines**, libc symbols 88 → 88.

## Phase 43 — no -c, --cmd, -R, -m, -M or -w

Six command-line options become what any unknown option is: exit 1, naming
itself. `+{command}` stays, and fills the same list `-c` did.

`tools/dropopts.py` removes `-R`, `-w` and `--cmd`, and the argument switch's
`case 'c':`. It refuses the other two, rightly, and `tools/nocmdargs.py` cuts them
by hand: **`-c` has a body of its own that falls through** into `-T` and `-u` —
`-c{command}` takes the rest of its argument and breaks, `-c {command}` falls
through to ask for the next one — and **`-M` falls through into `-m`**, so the
pair goes together. `--cmd` was the only long option that took an argument, so
the argument switch's `case '-':` goes, the option switch's one
`if (!want_argument)` can no longer be false, and `exe_pre_commands()` loses its
call and goes with the fields it read.

**The harnesses drove the editor with `-c`.** `tools/behaviour.py` and
`tools/exsweep.py` pass `+{command}` now, and — since Phase 18 took `-u` — no
`-u NONE` either. It is the same list in the same order,
so the change moves nothing against any binary either pipeline has made —
measured against `.reference/slim-vim`: 0 of 67 behaviour cases and 0 of 600
Ex-sweep rows differ from the baselines recorded with `-c`. Both are in every
phase's implementation digest, through `whimdelta.sh` and `verify.sh`, so every
boundary in both pipelines was verified again after the change.
`tools/clicheck.py` still passes `-c`: it runs at Phase 3, where `-c` exists.

The phase checks each dropped spelling — `-c qa!`, `-cqa!`, `--cmd qa!`, `-R`,
`-m`, `-M`, `-w7` — against a `+qa!` control.

### The delta

**None the Ex sweep records.** Measured: 117,013 → **116,892 lines**, libc
symbols 88 → 88.

## Phase 44 — no filters, sorting or alignment

Seven rows go to `ex_ni`: `:!` (with `:{range}!`), `:sort`, `:uniq`, `:retab`,
`:left`, `:center` and `:right`. **`:!` was kept in Phase 8 on purpose**, as the
sentence it printed instead of starting a process; it is dropped here on
request. The `!` operator key built nothing but a `:{range}!` command line, so
its row in `nv_cmds[]` points at `nv_error` — pointed, not deleted, as every row
there is. Completion for `:retab` goes with its row.

**`:r !cmd` and `:w !cmd` stay as they were.** They reach `do_bang()` through
`:read` and `:write`, not through the `:!` row, and keep Phase 8's refusal:
without their `!` being special, `:w !cmd` would write a file of that name.

### The delta

**The six rows that succeeded run bare** — `:sort`, `:uniq`, `:retab`, `:left`,
`:center` and `:right` — and **three behaviour cases**, `retab`, `sort_u` and
`sort_n`, which used them. `:!` already differed from Phase 8. Measured: 116,892
→ **115,798 lines**.

## Phase 45 — no `:drop`

`:drop` edited a file by making it the argument list and going to its first
entry: with one window and one buffer it was `:args` plus `:first`, both gone.
`ex_drop()` was the last caller of `set_arglist()` and `ex_rewind()`, and the
sweep takes all three.

### The delta

**None.** `:drop` already failed with no argument. Measured: 115,798 → **115,744
lines**.

## Phase 46 — no `:wall`, `:qall`, `:quitall`, `:wqall` or `:xall`

With one window and one buffer these were `:w`, `:q`, `:wq` and `:x` under longer
names. `:quitall` is `:qall`'s long spelling, the same handler, and goes with it.
`do_wqall()` and `ex_quit_all()` go with their rows.

**`tools/exsweep.py` quit every run with `:qall!`**, which is what made `:new`,
`:split` and the other window commands deterministic in `slim-vim`. It now runs
the binary once with `+qall!` and quits with `:q!` wherever that fails — which is
the same thing from Phase 39 on, where there is one window. Against `slim-vim`
it still quits with `:qall!`, and `tools/verify.sh` is all clear. The phase
checks that `:q!` still quits and `:qa!` is not a command.

### The delta

**The five rows**, which succeeded run bare. Measured: 115,744 → **115,646
lines**.

## Phase 47 — no `:startinsert`, `:startreplace`, `:startgreplace` or `:stopinsert`

Commands that entered or left Insert mode from a command line. `i`, `R`, `gR`
and Esc are the keys for that, and stay.

### The delta

**The four rows**, which succeeded run bare. Measured: 115,646 → **115,588
lines**.

## Phase 48 — no `:noswapfile`

There has been no swap file since Phase 21: the memfile is memory. The modifier
set `CMOD_NOSWAPFILE`, whose two readers in `ml_open()` and `buf_copy_options()`
were already empty blocks. It is matched by name in `parse_command_modifiers()`
before the table, so its branch goes as well as its row, and so does its line in
the completion arm for modifiers.

### The delta

**The row**, which succeeded run bare. Measured: 115,588 → **115,568 lines**.

## Phase 49 — one set of options

Every buffer and window option has two copies inside the editor, a global and a
local one. **The storage stays**: collapsing it would touch every option's reader
for nothing a user can see. What goes is every way to make the two copies differ,
so that `:set` — which writes both — is the only way an option is given a value,
and there is one set of options as far as anything outside can tell.
`tools/oneoptset.py` removes the four things that made them differ:

- **`:setlocal` and `:setglobal`** wrote one copy each. Their rows go to `ex_ni`,
  `ex_set()` stops choosing a flag for them, and their completion arms go.
- **`:set opt<`** copied the global copy into the local one. `<` is no longer an
  accepted suffix, and its three branches — boolean, number, string — fold, so
  `:set ts<` is an error like any other malformed `:set`.
- **Modelines** set a file's local copy from a `vim: set ...:` line, and the user
  was asked and chose to drop them. The four calls of `do_modelines()` go and the
  sweep takes it and `chk_modeline()`; every test of `OPT_MODELINE`, a flag
  nothing passes after that, folds; and `'modeline'`'s save and restore around
  `'binary'` in `set_options_bin()` goes. Then the rows of `'modeline'`,
  `'modelines'`, `'modelineexpr'` and `'modelinestrict'` go, `droplocal.py` takes
  `b_p_ml`, and `b_p_ml_nobin` — not an option, so with no `get_varp()` case that
  tool knows — goes by hand. A first run found that.

**Left alone:** a value detected from the file being read. `'fileformat'`, and
`'binary'` from `-b`, are the current file's state, and with one buffer only ever
one file's.

The phase checks that `:set ts<` is refused against a `:set ts=3` control, and
that `>>` on a file whose modeline says `sw=2` indents by the compiled-in four.
**The first version of that check proved nothing.** It used `ff=dos`, and
`'modelinestrict'` let a modeline set only whitelisted options, which
`'fileformat'` is not, so it passed against binaries that still read modelines.
`'shiftwidth'` is on the whitelist: measured, the Phase 48 binary indents by two
and this one by four.

**Measuring it showed something else.** `slim-vim` indents by four too, and so do
whim Phases 0 to 24, with `:set modeline?` answering `nomodeline`; Phases 25 to 48
answer `modeline`. The harnesses run as root, and upstream forces `'modeline'` off
for root — the check Phase 25 removed, as its section says. So a modeline was
read, as root, from Phase 25 until this phase, and no harness case has a modeline
to notice. Diffing `:set all` between Phases 24 and 25 shows that it is the only
value that moved besides the backup options that phase removed on purpose.

### The delta

**`:setlocal` and `:setglobal`**, which succeeded run bare. Measured: 115,568 →
**115,246 lines**.

## Phase 50 — only LF text files

Every line ends with LF when it is read and when it is written, and a CR is a
character like any other. `-b` goes, and with it `'binary'`, `'fileformat'`,
`'fileformats'`, `'endofline'`, `'fixendofline'`, `'endoffile'`, and the old
spellings `'textmode'` and `'textauto'`; so do the `++bin`, `++nobin`, `++ff` and
`++fileformat` arguments. `tools/lfonly.py` removes what a row cannot:

- **`readfile()` stops choosing and detecting a format.** The choice from `++ff`,
  `'binary'` and `'fileformats'`, the DOS and Mac detection, the loop that split
  lines at CR, CR stripping and its retry as Unix, the CTRL-Z at the end of a DOS
  file and the "[CR missing]" message all fold. A last line with no LF is still
  read and still reported as "[noeol]" — that describes the file.
- **`buf_write()` writes LF after every line, the last included, and no CTRL-Z.**
  Its CR branch goes by a local helper that keeps an `if`'s body and drops its
  `else`, which `cutil.fold_always` rightly refuses to guess.
- **Everything that compared a buffer's format with the one it was read in** —
  `file_ff_differs()`, `save_file_ff()`, `set_file_options()` — has nothing to
  compare, so its callers fold, including `unchanged()`, `bufIsChangedNotTerm()`,
  `set_init_1()` and `did_set_modified()`, and the sweep takes it with
  `get_fileformat()`, `set_fileformat()`, `default_fileformat()`,
  `msg_add_fileformat()` and `set_options_bin()`. stdin and fifos stop being read
  as binary.
- **`'endofline'` and `'endoffile'` had no initialiser in `buf_copy_options()`** —
  only resets, which the cut removed — so `tools/droplocal.py` does not recognise
  their shape, and their fields go by hand. So does `b_no_eol_lnum`, the last-line
  marker a binary write used.

**Several first runs failed, each on a count.** Two `else if (curbuf->b_p_bin)` in
`readfile()` until the format chain folded first; the detection block's
`fileformat == -1` test repeated inside itself, now anchored on what follows it;
two `save_file_ff()` calls outside the functions that die, found once the final
check reported *where* each leftover call sits rather than comparing a total.

The phase checks that `-b` is unknown and `:set ff=dos` refused against a
`:set ts=3` control; that `:%s/$/X/` on a CR LF file writes `one\rX\n`, where a
DOS file gave `oneX\r\n`; and that a last line with no LF gains one.

### The delta

**No Ex command; the behaviour cases `ff_dos` and `binary_mode`**, whose
`:set ff=dos` and `:set binary` are refused. Measured: 115,246 → **114,399
lines**.

## Phase 51 — a byte that is not UTF-8 is kept as it is

**Phase 12 changed this without declaring it.** It made UTF-8 the only encoding by
cutting the conversion layer at its entry points, and its table lists what each
cut function now answers — but not what that does to a file that is not valid
UTF-8. `slim-vim` reads such a file by falling back to latin1 and writes its
bytes back unchanged. With no fallback, `readfile()` replaced every invalid byte
with `?` (`bad_char_behavior`'s default, `BAD_REPLACE`) and made the buffer
read-only, and a forced `:w` wrote the `?`s. Measured: `ok\n\xff bad\n` comes back
as `ok\n? bad\n` from every whim binary since Phase 12, and unchanged from
`slim-vim` and whim Phases 0 to 11. No harness case has an invalid byte, which is
how it went unnoticed; it was found planning the UTF-8 phase, and the user was
asked what an editor that only edits UTF-8 should do.

**The answer was what `++bad=keep` already did.** The byte stays in the buffer as a
byte, shows as `<ff>`, is written back as it was, and the buffer is not made
read-only; "[ILLEGAL BYTE in line N]" is still reported, because that describes
the file. So keeping is the only behaviour, and `tools/keepbytes.py` folds every
test of `bad_char_behavior` — in the UTF-8 check and in the conversion loops —
drops `++bad` from `getargopt()`, and lets the sweep take `get_bad_opt()` and the
buffer's `b_bad_char`.

The phase checks, against a UTF-8 edit as control, that a file with `\xff` is
written back byte for byte after an edit to another line, that reading it leaves
`noreadonly`, and that `++bad=keep` is refused. **Its first run failed on the
probe, not the editor**: `+s/ok/OK/` runs on the last line, where Ex mode starts,
and an `:s` that does not match there stops the `:wq` after it. The probe says
`+1s`.

### The delta

**None the harnesses record.** Measured: 114,399 → **114,275 lines**.

## Phase 52 — UTF-8 is not a question

Since Phase 12, `mb_init()` sets the same five globals to the same values every
time: `enc_utf8`, `has_mbyte` and `enc_latin1like` TRUE, `enc_dbcs` and
`enc_unicode` 0. **456 places still asked them**, in every shape C allows — a bare
`if`, a chain of `&&` and `||`, a ternary, a comparison with a DBCS code page, an
argument — and each one was a branch for an encoding this editor cannot have.

`tools/utf8only.py` folds them as constants, on the source, and **never drops a
side effect**:

1. The five lose their declarations and their assignments in `mb_init()`, and every
   other mention becomes a marker — `__T__` for the three that are TRUE, `__Z__`
   for the two that are 0. A marker is an identifier, so the text still parses,
   and a `TRUE` already in the source is never mistaken for one the tool made.
2. Every expression holding a marker is simplified, innermost first, to a
   fixpoint: a ternary on a constant condition becomes its branch; in an `||` list
   a false operand goes and a true one ends the list, in an `&&` list the reverse;
   `!` flips a constant; parentheses around one collapse; `__Z__ == DBCS_x` is
   false. **An operand is dropped only where C would not have evaluated it, or
   where it is pure** — no call, no assignment, no `++` or `--`. Otherwise it stays.
3. Every `if`, `else if` and `while` on a constant marker folds with its else chain,
   by brace matching — from the last occurrence in a function, because the same
   false condition can be nested inside its own block, and folding the outer one
   first makes the inner vanish. A first test run met exactly that.
4. What is left — a marker compared with something that is not a constant, or
   assigned — becomes `TRUE`, `FALSE` or `0` again.

Measured on the phase's input: 239 expression simplifications and 261 statement
folds in 178 functions, 7 constants left as values. The sweep then takes the DBCS
and latin1 paths nothing reaches, and with them two libc symbols, `iswupper` and
`mblen`.

**Tested before it became a phase, against the binary it replaces.** Applied to a
copy of the Phase 49 source, compiled with every warning the sweep does not own
silenced, built, and run through the behaviour and Ex-sweep harnesses beside the
unfolded binary: 0 of 67 cases and 0 of 600 rows differ. That test also caught the
tool's own mistakes twice before it counted — once by crashing, and once by
reporting "0 differ" for a file the crash had left unchanged, which is why the
test now refuses to compare unless the tool succeeded and the file moved.

The phase checks `gUU` over *à é* for `c3 80 c3 89 0a`, byte for byte, and `x` on a
three-byte character.

### The delta

**None.** Folding a constant changes no behaviour, and the harnesses — with their
multibyte motion, case and insertion cases — are the check. Measured: 114,275 →
**112,439 lines**, libc symbols 84 → 82.

## Phase 53 — no conversion layer, no 'encoding'

Phase 12 cut the conversion layer at its entry points and left its body. Two ways
in were still open: **`++enc`** on `:e`, `:r` and `:w`, and a buffer whose
`'buftype'` is `help`, which `readfile()` read as latin1-or-utf-8. `tools/noconv.py`
closes both, and then everything behind them has one answer: the encoding name is
always empty, `need_conversion("")` is false, and so `converted`, the conversion
flags, the iconv descriptor, the `'charconvert'` temporary file and the retry with
the next encoding never change. Every test of them folds, in `readfile()` and
`buf_write()`; `buf_write_bytes()` loses the UCS-2, UTF-16, UCS-4 and latin1
writers no flag reached; the byte-order-mark check goes, since `check_for_bom()`
has answered "none" since Phase 12; the rewind that retried another encoding goes,
with its `retry` and `failed` labels.

**`'encoding'` goes**, and `mb_init()` stops asking `p_enc` — **but its NULL
branch was taken, once.** `common_init_1()` calls `mb_init()` before any option
exists, and that call filled the byte-length table with 1s and returned;
`set_init_1()` made the real one. Folded as never-taken, the first call ran on into
`init_chartab()` with no `curbuf`, and the editor crashed before its first command.
So `common_init_1()` now does what its call did then. **`'makeencoding'` goes with it** —
it converted `:make` output, `:make` went long ago, and it shared
`did_set_encoding()`, which is why that function survived the first attempt.

**The terminal is not converted either, and this is not tidying.** `input_conv`
and `output_conv` were `CONV_NONE` whenever `'encoding'` was utf-8. The only
assignment of `input_conv.vc_factor` was in the `mb_init()` branch folded above,
and `fill_input_buf()` divides by it: a first version of this phase folded the one
and not the other, and would have built an editor that divided by zero on its
first read of input. The post-condition grep caught the survivor before the build
did. Their tests fold in `ui_write()`, `fill_input_buf()` and `utf_find_illegal()`.

**The ten `mb_*` function pointers are calls.** `mb_init()` pointed all ten at the
UTF-8 implementations every time; 390 calls through them become direct calls to
`utfc_ptr2len()`, `utf_ptr2char()` and the rest, and the latin1 implementations
they were initialised to are swept. `mb_tail_off()` kept two dead returns after
its last live one from Phase 52; they go, and `dbcs_head_off()` with them.

Completion for `++ff`, `++enc` and `++bad`, left behind by Phases 50, 51 and this
one, goes from `expand_argopt()` and `get_argopt_name()`.

**The sweep met a declaration shape it had never deleted.** `enc_canon_table[]`
and `enc_alias_table[]` are written `static struct`, then the whole body on one
line, then the declarator alone — and gcc reports the declarator's line.
`deadsweep.py` walked back over a type only when that line began with `}`, so it
took the table and left `static struct {...}` open at file scope, where the next
declaration became "duplicate 'static'". It now recognises the one-line body too.
The branch is new and the old one untouched, so no earlier boundary could move —
and `slim-verify` and `whim-specpass` were run to show it, since the tool is in
every phase's implementation digest.

Both this and the crash above were found the expensive way: the phase program
failed, the pass fell through to an agent, and the agent's account named the two
causes. Its boundary and its synthesised residue were discarded; the fixes are in
the programs.

The phase checks that `:set enc?`, `:set menc?` and `++enc` are refused, that `gUU`
over *à é* still gives `c3 80 c3 89 0a`, and that an invalid byte is still written
back unchanged.

### The delta

**None the harnesses record** — no case converts. Measured: 112,439 →
**110,672 lines**, libc symbols 82 → 81 (`lseek`, whose two callers were the
retry's rewind and the help buffer's look at a file's first line — the second
already unreachable, behind a `c = TRUE` its own test could never pass).

## Phase 54 — no option without a variable

A row of `options[]` whose variable is `(char_u *)NULL` is an option `:set` accepts,
reports and ignores: its feature was never compiled in — folding, syntax, the GUI,
printing, cscope, the interpreter DLLs — or went in an earlier phase. **172 of
them.** `pipes/whim54.sh` computes the set from the table rather than listing it,
so a row upstream adds later without a variable goes too, and hands it to
`dropoptions.py`. None was buffer- or window-local, and no code outside the table
names one by string.

**The pattern met two traps, both worth keeping.** The variable field has to be
matched, not the row: a string default is often `(char_u *)NULL` too, and a first
count by row put `'messagesopt'`, `'wincolor'` and `'winhighlight'` among them. And
the spacing varies — `'termguicolors'` is `(char_u*)NULL` — so a pattern with the
space found 165. **And a row's flags can wrap onto a second line** — `'diffopt'`,
`'foldmarker'`, `'guifont'`, `'guifontwide'`, `'breakindentopt'` and `'undodir'` — so
a flag list without whitespace in it left those six behind; they were found only
when the options that survived were read by eye. The post-condition had a trap of its own: a row's flags and its
variable are on two lines, so a `grep` for rows left counted 0 whatever was left.
It reads across lines now, and was checked to count 172 on the phase's input.

The phase checks `:set sw` still works and that `'foldmethod'`, `'cursorline'`,
`'undofile'` and `'clipboard'` are unknown.

### The delta

**None the harnesses record** — no case sets an option without a variable.
Measured: 110,672 → **110,025 lines**.

## Phase 55 — no option nothing reads

Phase 54 took the options with no variable. These have one, and nothing but the
option machinery reads it — the declaration and the row, `get_varp()` and the
buffer copy for a local one, `set_context_in_set_cmd()`'s completion, and a
`did_set_*` callback that only validates the value or fills a flag set nothing
reads. Setting any of them changed nothing:

    autocompletetimeout  cdhome  cdpath  completetimeout  imcmdline  secure
    shellcmdflag  shelltemp  shellxescape  shellxquote  shortname  ttybuiltin
    warn  xtermcodes  commentstring  completefuzzycollect  completeitemalign
    helpfile  lispoptions  operatorfunc

and sixteen terminal codes the built-in tables and `:set` store and the editor
never sends — `t_8b t_8f t_EC t_EI t_GP t_RB t_RC t_RF t_RS t_SC t_SH t_SI t_SR
t_WP t_XM t_u7`. Their `KS_` enumerators stay, since the built-in terminal tables
still name them.

**Found by reachability, not by name.** Each option's variable was mapped from its
row — `p_xx`, `b_p_xx` from `BV_XX`, `wo_xx` from `WV_XX` (not `w_p_xx`, which a first
count used and so found `'list'` and `'number'` unread), `KS_XX` for a terminal
code — and every mention attributed to its function. Mentions in the plumbing did
not count. **A callback counted only through what it touched:**
`'belloff'`, `'casemap'`, `'display'`, `'jumpoptions'` and `'keymodel'` looked
unused until their callbacks' flag sets were followed to `vim_beep()`, the case
mappers, screen drawing, the jump list and selection; `'modified'`, `'terse'` and
`'wincolor'` act in the callback itself. Those stay. `cfc_flags`, `cia_flags` and
`opfunc_cb` were set and never read, so their options go. No option of the 36 is
named by string anywhere outside the table.

One real reader had to go first: `'cdpath'` was completed as a directory list,
the only use of `p_cdpath`. The phase greps afterwards for every variable, flag set
and callback of the 36, so a reader that appears later fails it. It checks `:set
sw` still works and that `'shelltemp'`, `'commentstring'` and `t_EI` are unknown.

### The delta

**None the harnesses record** — no case sets one. Measured: 110,025 →
**109,655 lines**.

## Phase 56 — no shell, runtime or keyword-program options

Six options whose readers survived only in machinery with nothing left to serve.
**`'shell'`, `'shellquote'` and `'shellredir'`**: no shell is ever run — `call_shell()`
and `mch_call_shell()` went long before — so `'shell'` only chose the default of
`'shellredir'` in `set_init_3()` and whether filename escaping doubled a `!` for csh,
and `'shellquote'` only wrapped `do_bang()`'s command line. **`'runtimepath'` and
`'packpath'`**: there is no runtime to find. Their readers were the completion of
`:colorscheme`, `:compiler`, `:ownsyntax`, `:setfiletype`, `:packadd` and
`:runtime` — every one of them `ex_ni` — and of `:set ft=`, which listed runtime
syntax, indent and ftplugin names. **`'keywordprg'`**: `K` is gone; only `:set kp=`
defaulting to `:help` read it. Each reader is folded before the rows go, and the
phase greps afterwards for every variable and helper.

**One plumbing site had a shape `droplocal.py` did not know.** `get_varp()`'s "local
if set" case for `'keywordprg'` reads `&curbuf->b_p_kp`, without the parentheses
every other such case has, so its two mentions counted as readers and the tool
refused. The phase removes that case by hand first; the shared tool is unchanged,
so no other phase's key moved.

### The delta

**None the harnesses record.** Measured: 109,655 → **109,039 lines**.

## Phase 57 — no lisp

`'lisp'` and `'lispwords'` go, and with them everything they switched on:
`get_lisp_indent()` for autoindent, `=`, `gq` and new lines; `lisp_match()` over
`'lispwords'`; `-` as a keyword character; `;` line comments in
`check_linecomment()`; and `findmatchlimit()`'s lisp mode, which stopped `%` at a
`;` comment and skipped `#\(` character literals. `'lispoptions'` went in Phase 55.

`b_p_lisp` is folded as false at every reader rather than stubbed — nine places
in `findmatchlimit()` alone — so each branch it guarded is gone or taken
unconditionally. One test inverts: `op_reindent()` skipped the last line of a
range only when re-indenting with `get_lisp_indent()`, so its `how !=
get_lisp_indent` is always true and the branch is kept. The phase checks the two
options are unknown and that `%` on `(a ; b)` now matches across the `;`.

### The delta

**None the harnesses record** — no case sets `'lisp'`. Measured: 109,039 →
**108,651 lines**.

## Phase 58 — no language mappings

`'iminsert'` and `'imsearch'` are 0 from here on, so language mappings are never
active and nothing can make them so. `:lmap`, `:lnoremap`, `:lunmap` and
`:lmapclear` point at `ex_ni` and lose their completion. CTRL-^ in Insert mode and
on the command line is still consumed — its `case` stays, so it does not start
inserting itself — and toggles nothing. `MODE_LANGMAP` is never set, so every test
of it folds: in `edit()`, `ex_append()`, `ins_insert()`,
`normal_cmd_get_more_chars()`'s lookup for `r`, `f` and `t`, `getcmdline_int()`
for `/`, `?` and `@`, `handle_mapping()`, `vgetorpeek()`, `get_map_mode()` and
`map_mode_to_chars()`. The status line's `<lang>` goes with `get_keymap_str()`,
which only ever printed it.

**The declared delta was wrong once, and the harness said so.** It named all four
commands; `:lunmap`'s row did not move, because bare `:lunmap` already failed for
want of an argument and `ex_ni` fails too. The declaration was corrected rather
than the check widened. The phase checks the two options are unknown, `:lmap` is
refused, and CTRL-^ in Insert mode inserts nothing.

### The delta

`:lmap`, `:lnoremap` and `:lmapclear`, now `ex_ni`. Measured: 108,651 →
**108,374 lines**.

## Phase 59 — no command-line completion

The command line no longer completes anything. In `getcmdline_int()` the
`'wildchar'` and `'wildcharm'` keys, S-Tab, CTRL-D (list), CTRL-A (insert all),
CTRL-L (longest match) and CTRL-N/CTRL-P over matches go; each of those keys is now
an ordinary character, CTRL-N and CTRL-P browse history as they did when there were
no matches, and CTRL-L still adds a character to an incremental search. The six
wild* options go with them: `'wildchar'`, `'wildcharm'`, `'wildmode'`,
`'wildoptions'`, `'wildignore'` and `'wildignorecase'`.

What completion shared with filename expansion stays: `expand_filename()` →
`ExpandOne()` with `EXPAND_FILES`, and the argument list through
`expand_wildcards()`. So `ExpandFromContext()` keeps its file branch and loses the
rest — options, mappings, buffers, highlight groups, `++opt`, every command's
arguments — and `ExpandOne()` keeps the one mode its last caller asks for. The
phase checks after the sweep that `expand_filename()` is that last caller.

**Three things kept the machinery alive, and each was found by the post-condition
greps rather than by reading.** `didset_options2()` still parsed `'wildmode'` into
`wim_flags` at startup, which nothing read. Every `options[]` row still named the
callback that completes its value — 29 of them — so the table kept `ExpandGeneric()`
and the fuzzy matcher reachable; no code reads that field any more, and the rows
now hold `NULL`. And the check that `ExpandOne()` had one caller ran first before
the sweep, when its dead callers were all still there. The sweep then took
6,208 lines.

**`:e` does not expand a wildcard, and has not since Phase 7 — deliberately.** The
first probe here asked that `:e onlyo*` edit `onlyone.txt`. It failed, and failed
identically on the previous phase's binary, which wrote a file named `onlyo*`. That
is Phase 7's declared delta, not a regression: Phase 7 replaced
`gen_expand_wildcards()` with `save_patterns()`, so `:e *.c` names a file
literally, and said so. Bisecting the boundaries confirms it — q6 expands the
pattern, q7 does not. An earlier draft of this section called the loss silent and
placed it "at or before Phase 12"; that came from testing binaries before reading
Phase 7, and was wrong. This phase does not change it, and the probe checks `:e`
on a plain name instead.

### The delta

**None the harnesses record** beyond Phase 58's. Measured: 108,374 →
**102,166 lines**.

## Phase 60 — no suffix, case, delay, verbose-file, debug or filter-program options

Seven options whose default is the only value anything could still act on.
`'suffixes'` ordered wildcard matches, and wildcards have not expanded since
Phase 7 removed globbing, so `match_suffix()` and its two reordering blocks go.
`'fileignorecase'` is off, and its five tests fold as false. `'autocompletedelay'`
is 0, so `inchar_loop()`'s delay was never pending. `'verbosefile'` is empty, so
the file is never opened: `redir_write()`, `redirecting()` and the
`verbose_enter`/`verbose_leave` family fold, and `fopen` leaves the libc symbols.
`'debug'` is empty, and its tests in `emsg_not_now()`, `emsg_core()` and
`vim_beep()` fold.

**`'formatprg'` and `'equalprg'` were suspicious, and dead.** Their only effect was
to make `gq` and `=` build a `:{range}!prg` line, and `:!` has been `ex_ni` since
Phase 44 — so a non-empty value turned a working operator into an error. `gq` and
`=` take the internal path unconditionally now, and `op_colon()` loses its
indent and format branches. `get_varp()`'s `'equalprg'` case has the same
missing parentheses as `'keywordprg'`'s in Phase 56 and is removed by hand.
`'formatoptions'` and `'formatlistpat'`, suspected with them, are live —
auto-wrap, comment leaders, `gq`, `J` and numbered-list indent read them — and stay.

The phase checks the seven are unknown and that `gqq` with `tw=4` still breaks
`aaa bbb` into two lines.

### The delta

**None the harnesses record.** Measured: 102,166 → **101,826 lines**; libc symbols
81 → 80.

## Phase 61 — no window title

`'title'`, `'titlelen'`, `'titleold'`, `'titlestring'`, `'icon'` and `'iconstring'`
go, and with them everything that set or restored the terminal's title:
`maketitle()` and its thirteen callers, `need_maketitle` and the six places that
asked for an update, `resettitle()`, `mch_settitle()`, `mch_restore_title()` in
`:stop`, exit, a terminal change and `value_changed()`, `set_title_defaults()`,
`term_settitle()`, the X11 title and icon probes, and the title-stack push at
startup and pop at exit. The editor no longer writes to the terminal's title at
all. The `t_ts`, `t_fs`, `t_ST` and `t_RT` codes stay, with the other terminal codes.

**Two of the phase's own checks were wrong first, and both failed loudly.** One
guarded `do_exedit()`, where `n` held the argument index only to decide whether to
update the title, by requiring no other mention of `n` — but `n` also saves and
restores `readonlymode` around `:view`. It now requires exactly those three
mentions. The other counted five `need_maketitle = TRUE` assignments where there
are six: `maketitle()` sets it itself before an early return. Each was tried first on
a copy of the Phase 59 boundary, since this phase touches nothing Phase 60 does.

### The delta

**None the harnesses record.** Measured: 101,826 → **101,188 lines**.

## Phase 62 — no buffer-type, file-type, listing, jump, update-time or autowrite options

Seven options, each checked by what its readers still did:

- **`'buflisted'`** — every reader chose which autocommand event to fire, and
  `apply_autocmds_group()` has been `return FALSE` since autocommands went, or
  searched a buffer list of one. The `set_buflisted()` calls go with it.
- **`'filetype'`** — every reader fed the FileType event, which cannot fire, or
  `fix_help_buffer()`, and `:help` is `ex_ni`.
- **`'buftype'`** — the one that was live, but only through `:set bt=`: `nofile`,
  `nowrite`, `acwrite` and `prompt` refused `:w` and skipped reading, and `help` set
  `b_help`. Nothing inside the editor ever set it. `bt_dontwrite()`,
  `bt_nofilename()`, `bt_nofileread()` and `bt_prompt()` fold as false at every
  caller — including two inside one `snprintf` line in `fileinfo()`, the
  `[Not edited]` and `[New]` notes, and `buf_write()`'s `nofile_err`, set in three
  branches and read in two tests and one condition.
- **`'jumpoptions'`** — empty, so the "stack" behaviour of the jump list folds.
- **`'updatetime'`** — **dead, though it looked live.** After that long idle,
  `inchar_loop()` asked `trigger_cursorhold()`, which is `return FALSE`, and called
  `before_blocking()`. Its swap sync, `updatescript(0)`, reaches an `ml_sync_all()`
  whose body is empty; its terminal flush only writes while `sync_output_state` is
  above zero, which is inside `update_screen()` or `redraw_after_callback()` — both
  close it before returning, with no `return` or `goto` in between — so never at
  idle. The idle wait therefore goes: a wait with no timeout blocks at once, and
  `before_blocking()`, `updatescript()`, `ml_sync_all()` and the `scriptout`
  save and restore in `wait_return()` go with it. A first version of this phase
  kept the timeout at its 4000 ms default, on the strength of the call alone; it
  was corrected in place when the chain was read to the end.
- **`'autowrite'`** and **`'autowriteall'`** — off, so `autowrite()` always failed and
  `autowrite_all()` returned at once. Their callers fold, and so does the `CCGD_AW`
  flag — including the two places, `:next` and `do_argfile()`, that passed it
  unconditionally.

**The phase took six runs to get right, and every failure was the post-condition
grep or a tool refusing, never the build.** `droplocal.py` refused `b_p_bl` with
two plumbing sites where it requires three — the folds had already taken its
initialiser, so its field and `get_varp()` case go by hand — and then refused
`b_p_bt` because `fileinfo()` still called `bt_dontwrite()` a second time. The
grep then found `CCGD_AW` and `nofile_err` alive, and — once the idle wait was
removed — `did_start_blocking`, still read by the loop's exit test. That one needed
thought rather than deletion: blocking now starts on the first wait with no
timeout, so the flag was always TRUE where it was tested, and the term goes so that
an interrupted wait still returns instead of blocking again. Each was a reader the
first reading had missed, not a reader the check invented.

### The delta

**None the harnesses record.** Measured: 101,188 → **100,643 lines**.

## Phase 63 — no jump list

The per-window jump list goes: `w_jumplist`, `w_jumplistlen` and
`w_jumplistidx`; `setpcmark()` appending to it; CTRL-O and CTRL-I walking it
through `movemark()`; `:jumps` and `:clearjumps`, now `ex_ni`; `cleanup_jumplist()`;
copying it into a new window and freeing it with one; and the loops in
`mark_adjust_internal()`, `mark_col_adjust()`, `mark_forget_file()` and
`fmarks_check_names()` that kept its marks right when lines moved or a file was
forgotten.

**What stays, because it is not the jump list.** The previous-context mark behind
`''` and `` ` ` `` — `w_pcmark`, still set by `setpcmark()`. The change list and
`g;`/`g,`: `nv_pcmark()` served both, and keeps that half. `:keepjumps`, which
guards the pcmark and the change list too. And `JUMPLISTSIZE`, which sizes the
change list. CTRL-O in Select mode still runs one Visual command; elsewhere CTRL-O
and CTRL-I beep, and `<Tab>` is mapped to `%` in this build, so losing CTRL-I's
meaning costs nothing typed. The phase greps afterwards that `w_pcmark` and
`movechangelist` survived, since either going would mean it took more than the
jump list.

It was tried first on the Phase 61 boundary, before Phase 62 was recorded. That
trial failed only on the `'jumpoptions'` block Phase 62 removes — so it checked
this phase's own script and nothing else.

The phase checks `:jumps` is refused, CTRL-O after `3G` leaves the cursor on line
3, and `''` after `3G` still returns to line 1.

### The delta

`:jumps` and `:clearjumps`, now `ex_ni`. Measured: 100,643 → **100,354 lines**.

## Phase 64 — no formatting, comment or nroff-macro options

Five options, each dropped with the machinery that only it gave a meaning to.

- **`'comments'`** — no comment leader is recognised. `get_leader_len()` and
  `get_last_leader_offset()` would answer 0 and -1 everywhere, so every reader
  folds that way. The following all go:
  - `open_line()` copying, replacing, right-aligning and padding a leader;
  - `insertchar()` completing a `*/`, through `end_comment_pending`;
  - `J` removing leaders, through `skip_comment()`;
  - `same_leader()`, and the leader a formatted or wrapped line keeps;
  - `gd` skipping comment lines;
  - `%` skipping a `//` comment when `buf_has_cstyle_comments()` said the buffer
    looked like C.

  `check_linecomment()` stays, because `findmatchlimit()` still uses it.
- **`'formatoptions'`** — fixed at its default, `tcq`. With no leader, `c` and `q`
  have nothing to act on, so what is left is `t`:
  - Typing still wraps at `'textwidth'`, and `'paste'` still stops it, since
    `has_format_option()` answered FALSE under paste.
  - `gq` still formats.

  Every other flag was off, and its code goes:
  - `a`: `auto_format()`, `check_auto_format()`, `did_add_space` and all 18
    calls;
  - `w`, `n`, `2`, `b`, `l`, `v`, `m`, `M`, `B`, `1`, `p`, `]`, `j`, `r`, `o` and
    `/`.

  `format_lines()` is left as a plain paragraph loop with no second-line indent.
  `internal_format()` breaks only at blanks, which removes the multibyte branch,
  and `Insstart_textlen` and `Insstart_blank_vcol` go too.
- **`'formatlistpat'`** — only `n` read it, through `get_number_indent()`.
- **`'paragraphs'`** and **`'sections'`** — no nroff macro starts a paragraph or a
  section. `{`, `}`, `[[`, `]]`, `(`, `)` and the `ip`/`ap` objects stop at blank
  lines, form feeds and braces; `inmacro()` goes. These were not folded to their
  default, which would have kept a table of nroff macro names. Dropping the
  recognition is the same choice as for `'comments'`, whose default would have
  kept all of the leader machinery.

**And the two mechanisms that were left reading what those options described.**
An option and its only consumer are one cut, not two:

- **The format operator.** `gq` and `gw`, their doubled `gqq`/`gqgq`/`gww`/`gwgw`,
  `op_format()`, `format_lines()` and `fmt_check_par()`. A paragraph was only a
  paragraph in order to decide where a format stopped. What stays is the wrap
  while typing: `'textwidth'` and `'wrapmargin'` still break a line through
  `insertchar()` and `internal_format()`, and `'paste'` still stops it. With no
  `gq`, `INSCHAR_FORMAT` is never set, so `comp_textwidth()` loses the flag that
  chose the screen width for it, and `insertchar()` loses its `c == NUL` entry.
- **Go to local declaration.** `gd` and `gD`, `nv_gd()` and `find_decl()`, which
  searched from the start of the block the cursor was in. `gd` was the only
  caller. `gq`, `gw`, `gd` and `gD` now fall to `nv_g_cmd()`'s default and beep.
- **The `=` operator.** `==`, `=G` and the rest. `op_reindent()` re-applied
  `get_indent()` — the indent the line already has — because `'equalprg'` went in
  phase 60 and C-indenting is off, so `=` had nothing left to compute. Its
  `nv_cmds` row points at `nv_error`.
- **The `!` operator, which was already dead.** Its `nv_cmds` row has been
  `nv_error` for phases, and `get_op_type()` is reached only from `nv_operator()`,
  so `OP_FILTER` could no longer be set at all. What goes is the dispatch nothing
  reached: the `OP_FILTER` case, the `!` that `op_colon()` typed after a range,
  and `do_bang()`'s `bangredo` block — the only thing that set it. **`:w !cmd` and
  `:r !cmd` still reach `do_bang()`**, and `do_filter()` still says the command is
  not available in this version, so the filter commands are untouched.
- **What C-indenting left behind.** The engine went phases ago — no
  `get_c_indent()`, no `cin_*` anything, and none of `'cindent'`, `'cinoptions'`,
  `'cinkeys'`, `'cinwords'`, `'indentexpr'` or `'indentkeys'`. What stayed was a
  switch wired to `FALSE` and its plumbing: `cindent_on()`, which is
  `return FALSE`, and **`can_cindent`, written in ten places and read in none.**
  gcc does not warn about that — a static that is assigned counts as used — which
  is the same blind spot `deadfields.py` exists for, one level up. `cindent_on()`'s
  two callers fold: CTRL-U in `ins_bs()` keeps the indent for `'autoindent'` alone,
  and the multi-character insert in `insertchar()` stops asking. `set_can_cindent()`
  goes with the flag. Three of the ten writes are the whole body of an `if`, so the
  test goes too — and each is scoped to its function, because `if (inindent(0))`
  also guards `do_pending_operator()`'s `oap->motion_type = MLINE`, which stays.

**`'smartindent'` is kept, and checked rather than assumed.** `may_do_si()`,
`did_si`/`can_si`/`can_si_back`/`no_si` and `open_line()`'s `{`, `}`, `#` and `)`
rules are a different mechanism from `'cindent'`, and this build switches it on by
default. The phase greps that all four survive, and a probe indents `y;` by one
`'shiftwidth'` after a line ending in `{` and brings `}` back out.

The `opchars[]` rows for `g`+`q` and `g`+`w` stay. The table is positional — its
index *is* the `OP_*` value — so a removed row would renumber every operator
after it. Nothing reaches them: `nv_g_cmd()` reaches the default first.

**Deleted outright rather than left to the sweep**: `auto_format()`,
`check_auto_format()`, `paragraph_start()`, `op_format()`, `format_lines()` and
`fmt_check_par()`. The last three matter for order — `comp_textwidth()` loses its
argument in the same phase, and `format_lines()` would still be calling it with
one when the sweep compiles.

**The options half does not fold `format_lines()` or `fmt_check_par()` first.** An
earlier version did, twenty-odd edits deep, and then the operator half deleted
both. Folding a function that is about to go is work the phase throws away; the
output is identical either way, and that was checked rather than assumed.

**Seven dry runs, and not one failure was a broken build.**

1. **The script failed its own counts.** `open_line()`'s leader block holds
   `lead_len = 0` statements and an `if (lead_len > 0)` of its own, so it is
   dropped first, by a pattern anchored on its first declaration.
2. **`phasecheck.sh` found `extra_len` set and not read** — it sized the leader's
   allocation and nothing else.
3. **The post-condition grep found `oparg_T`'s `cursor_start`**, which was `gw`'s
   alone. `deadfields.py` will not touch it: `pagescroll()` has
   `oparg_T oa = { 0 };`, and a **positional** initialiser names no field, so the
   tool keeps every field of a type that has one. It goes by hand, and `{ 0 }`
   fills only the first field, so removing a later one is safe.
4. **`do_bang()`'s `theend:` label went unused.** The `bangredo` block held the
   only `goto` that reached it, and a label nothing jumps to is a warning. The
   free below it runs either way, so only the marker goes.
5. **The `=` probe asserted the wrong thing**, and the measurement is the useful
   part. A retired operator does not let the motion through: it abandons the rest
   of the sequence. Measured on the q63 boundary, `=jix` gave `xa|b|c|` — `=`
   took `j`, came back to line 1 and inserted — while `!jix`, already `nv_error`,
   left the file alone. So the check is that **both** keys now leave it alone,
   with `!` as the invariant that says what a retired operator looks like, and a
   bare `ix` as the control that proves the binary still inserts.

### The delta

Three behaviour cases: `format_gq` (`gqq` with `tw=20`, which now beeps and
changes nothing), and the two that set the options, `format_comment` and
`open_comment`. No Ex command moves — these are all Normal-mode keys, and
`:center`, `:left` and `:right` were `ex_ni` long before this phase.

The phase checks:
- the five options are unknown to `:set`;
- typing `aaa bbb ccc ddd` with `tw=10` still wraps to two lines;
- `gqq` and `gqj` leave a long line exactly as it was;
- `gd` on `x` leaves the cursor where it is;
- `=jix` and `!jix` leave the file alone, while `ix` still inserts;
- `'smartindent'` still indents `y;` after a line ending in `{`, and `}` comes back;
- `}` from line 1 passes `.PP` to the last line.

Two more failures came from the checks rather than the cuts:

6. **`if (inindent(0))` matched twice.** It guards a `can_cindent` write in `edit()`
   and `oap->motion_type = MLINE` in `do_pending_operator()`, which stays. Each of
   the three `if`-bodied writes is now scoped to its own function.
7. **The `'smartindent'` probe sent no carriage return**, so `GAy;` appended to the
   same line and the probe failed where the editor was right. Calibrated against
   the q63 binary, which gives `if (x) {` / `    y;` / `}` for the corrected keys.

Measured: 100,354 → **97,734 lines**.

## Phase 65 — no rot13, no operator function, no empty key handler

Three cuts, and only the first changes what the editor can do.

- **rot13.** `g?` is the one operator here that encodes rather than edits. It goes
  whole: `nv_g_cmd()`'s case, the `OP_ROT13` dispatch label, `nv_search()`'s
  redirect — which is how `g?` reaches the operator while a search is pending —
  and `swapchar()`'s three arms, after which `swapchar()` is the case-changing
  function it always really was.
- **The operator function.** `g@` has had nothing to call since the eval feature
  went: `op_function()` was one `emsg()`, and `'operatorfunc'` does not exist to
  name a function anyway. The dispatch, the `OP_FUNCTION` term in the
  `motion_force` test and `op_function()` itself go, and
  `e_eval_feature_not_available` falls to the sweep with its only reader.
- **An empty call.** `ins_ctrl_x()` had an empty body — CTRL-X in Insert mode
  began a completion, and completion went in phase 32. The key stays inert, but
  it no longer calls a function in order to do nothing.

**Three things are kept deliberately, because "does nothing" and "should be
deleted" are different claims.**

- **CTRL-P and CTRL-N in Insert mode are `break;`** — they do nothing *on purpose*.
  Deleting the labels would drop them into `normalchar`, which **inserts the
  control character**, so removing dead-looking code would add behaviour. The
  phase greps that `case Ctrl_P:` survives.
- **`zy`, `zp` and `zP` are live.** It looks as though `zy` must reach
  `internal_error("get_op_type()")`, since `opchars[]` has no `{'z','y'}` row —
  but `get_op_type()` special-cases `'z'`+`'y'` to `OP_YANK` before it consults
  the table. Measured on the q64 binary before cutting: no error, no message.
  This is why the "dead weight" list was checked key by key rather than read off
  the table.
- **The `opchars[]` rows for `g?` and `g@` stay**, for the reason phase 64
  records: the table is positional, so a removed row renumbers every operator
  after it. Nothing reaches them once `nv_g_cmd()` has no case.

The `'?'` and `'@'` case labels are edited **scoped to `nv_g_cmd()`**: another
switch entirely has `'?'` and `'@'` adjacent, and an unscoped edit would have had
two places to choose between — the same trap as `if (inindent(0))` in phase 64.

### The delta

**None.** No Ex command moves, and no behaviour case covers rot13 — the harness
never encodes anything. The probes check `g?g?` and `g??` no longer encode, that
`g@g@` is refused, that `gUU`, `guu` and `g~~` still change case (they share
`swapchar()` with the arms that went), and that `zyy` still yanks.

Measured: 97,734 → **97,684 lines**.

## Phase 66 — no sentences, paragraphs, sections, methods, #if blocks or comment blocks

One idea, cut at all three places it was reachable from. A sentence you cannot
move over is not one you can select, or address a line range with.

- **The motions.** `(` and `)` by sentence, `{` and `}` by paragraph — these four
  `nv_cmds` rows point at `nv_error` — and from `nv_brackets()`/`nv_bracket_block()`:
  `[[` `]]` `[]` `][` by section, `[m` `]m` `[M` `]M` to a method's braces, `[#` `]#`
  to the enclosing `#if`/`#endif`, and `[/` `]/` `[*` `]*` to the enclosing C comment.
  The dispatch sets shrink from `"{(*/#mM"`/`"})*/#mM"` to `"{("`/`"})"`.
- **The text objects.** `is`, `as`, `ip` and `ap` — `current_sent()` and
  `current_par()`.
- **The Ex addresses.** `'{`, `'}`, `'(` and `')` as line addresses, which
  `get_address()` answered by calling `findpar()` and `findsent()`.

After which `findsent()`, `findpar()` and `startPS()` have no callers at all, and
the concept is gone from the editor rather than merely unbound.

**What stays, and is checked rather than assumed**: `%` and the enclosing-bracket
motions `[{` `]}` `[(` `])`, which are `findmatchlimit()` and never had anything to
do with paragraphs; the `(` `)` `{` `}` `[` `]` `<` `>` **text objects** (`i{`, `a(`
…), which are `current_block()`; `iw`/`aw`; and the `'[` `']` `'<` `'>` marks, which
`get_address()` answers from stored positions.

**Four failures, all in the phase's own machinery rather than the tree.**

1. **The method test matched twice.** `if (cap->nchar == 'm' || cap->nchar == 'M')`
   is both the head that picks the character to match and the half that walks out
   to the method. The counted helpers cannot express "the second of two" — they
   die on any count but the one given — so the walk-out is cut from a slice that
   starts at it, and only then is the head the single match the counted fold wants.
2. **A dead assignment in the script itself**, left over from the first attempt at
   that ordering.
3. **`prev_pos` was set and not used** once the walk-out went. gcc reports
   `-Wunused-but-set-variable`, which `deadsweep.py` does not handle: it deletes
   *unused* variables, not written ones. The declaration and both writes go by
   hand. `c` is a plain unused variable after the same cut, and the sweep takes it.
4. **`lines()` was never defined in this script** — the three `prev_pos` removals
   were carried over from phase 64 without its helper.

### The delta

**None.** No behaviour case moves over a sentence or a paragraph, and no Ex
command changes. The probes check that each cut key leaves the file untouched —
a beep abandons the rest of a `:normal!` sequence, so the `ix` after it never
runs, with a bare `ix` as the control — that `[{` still walks out to the enclosing
`{`, `%` still matches, `di{` still deletes a block's contents without its braces,
and `'{,'}d` is refused.

Measured: 97,684 → **96,848 lines**.

## Phase 67 — no mouse, no spell plumbing, no write-only flags

Three cuts, none of which changes what the editor can do, because none of it
could happen in the first place. This is the first phase driven by
`tools/coverage.sh` and by a scan for **write-only statics**, rather than by a
capability to remove.

- **The mouse, which cannot arrive.** There is no `'mouse'` option row, and
  `setmouse()`, `mch_setmouse()`, `mouse_has()` and `p_mouse` are all gone, so
  nothing ever asks a terminal to report mouse events. What served them goes:
  `is_mouse_key()` and the term in the input loop that called it,
  `reset_dragwin()`/`reset_held_button()` with `dragwin` and `held_button`,
  `mouse_row`/`mouse_col` and `old_mouse_row`/`old_mouse_col` — a save-and-restore
  pair nothing else reads — the 18 mouse rows of `key_names_table`, the `[MOUSE]`
  entry of the terminal string table, and `check_termcode()`'s mouse matching.
  **The 26 `nv_cmds` rows stay at `nv_error`**: that table's index is a permutation
  of its rows, so a removed row renumbers the keys after it.
- **The spell plumbing.** `spellvars_T` was one field, `win_line()`'s `spv`
  parameter was already `__attribute__((unused))`, and `win_update()` declared one
  on the stack only to pass its address twice.
- **Fourteen write-only statics.** `did_check_timestamps`, `was_safe`,
  `did_emsg_syntax`, `typebuf_was_empty`, `in_mch_delay`, `mr_patternlen`,
  `frame_locked`, `swap_exists_did_quit`, `did_swapwrite_msg`, `autocmd_nested`,
  `dragwin`, `held_button`, `oldtitle_outdated`, `deadly_signal`. Two were a whole
  function body, so `state_no_longer_safe()` and its two calls go with `was_safe`.

**`vim_ignored` is not one of them, though it looks identical to the detector.**
Its five sites are `vim_ignored = ftruncate(...)`, `= dup(2)` and
`= write(1, ...)`: it exists to swallow `warn_unused_result`, and removing it
*adds* warnings — a `(void)` cast does not silence that attribute in gcc. The
phase greps that it survives.

**One real change of behaviour is buried in the mouse cut.**
`looks_like_mouse_start` is not mouse-specific despite its name: it is set for any
two-byte `ESC [` termcode whose third byte is not a digit, and it *defers* the
match so a longer code — a mouse one — can win instead. With no mouse code able to
arrive, deferring can only lose, so the fold makes such a code match at once.
`tools/arrowcheck.py`, which drove a real pty, was what would have caught that
going wrong, until it was retired after Phase 82.

**Two failures, both in the phase's own counting, and both caught by a guard
rather than by the build.**

1. **A probe that could not fail.** It asserted `:map <LeftMouse> x` is refused
   once the name is gone. Measured on both binaries: **an unrecognised `<...>` is
   taken as a literal string, not refused** — `<Foo>` and `<ZZnotakey>` are
   accepted too. The evidence that the names are gone is the grep; what the probe
   checks now is that a name which *does* exist still maps.
2. **Thirteen of eighteen rows.** Five mouse rows — `DecMouse`, `JsbMouse`,
   `NetMouse`, `PtermMouse`, `UrxvtMouse` — are written across **three** lines
   (`{`, `FALSE,`, then code and name), so a single-line pattern could not see
   them. This is phase 54's wrapped-option-row trap again. Both patterns are
   anchored on the *name*, which is what keeps them off the sixth three-line row,
   `SNR`.

### The delta

**None.** No key, command or option changes — every cut is code nothing could
reach. Measured: 96,848 → **96,636 lines**.

## Phase 68 — one window, structurally

**This phase establishes an invariant and then spends it**, which is why it is the
largest cut here since the early ones.

A window is created in exactly two places: `win_alloc_firstwin()`, once at startup,
and `win_split_ins()`, whose **only** caller is `aucmd_prepbuf()`. `win_split()`,
`make_windows()` and `win_new_tabpage()` have no mentions at all. A tabpage is
created once, by `alloc_tabpage()` in `win_alloc_first()`. So removing the
autocommand window means nothing can ever add a window or a tabpage again:

```
    firstwin == lastwin        first_tabpage->tp_next == NULL
```

`one_window()`, `last_window()` and `only_one_window()` are then constant TRUE —
not as an observation about the harness, but as a consequence of the two creation
sites — and every caller folds.

**Why the autocommand window can go.** `aucmd_prepbuf()` splits one open only when
no window shows the buffer, in order to run autocommands in it — and
`apply_autocmds_group()` has been `return FALSE` since autocommands went. The
window was built to run nothing.

**What was already a no-op**, which is why this removes capability from the source
and none from the editor:

- `win_close()` tests `last_window()` first and answers *cannot close last window*,
  so the calls in `ex_quit()`, `ex_exit()` and `do_exedit()` could never close
  anything — and the first two reach `getout(0)` before them regardless.
- `do_exedit()`'s call is guarded by `old_curwin != NULL`, and its one caller
  passes `NULL`.
- `close_windows()` loops `wp != NULL && !(firstwin == lastwin)`, false at once,
  then over tabpages other than `curtab`, of which there are none.

Gone with them: `win_split_ins`, `win_close`, `close_windows`, `win_close_othertab`,
`close_last_window_tabpage`, `close_tabpage`, `free_tabpage`, `winframe_remove`,
`win_equal`, `win_equal_rec`, `frame2win`, `win_altframe`, `is_aucmd_win`, the four
snapshot functions, `win_alloc_popup_win`, `win_init_popup_win` and the `aucmd_win[]`
table.

**What stays, and is checked rather than assumed.** `win_comp_pos()`,
`frame_comp_pos()`, `last_status()` and `last_status_rec()` are reached from
`shell_new_rows()` and `did_set_laststatus()`, so a terminal resize and
`:set laststatus` still compute the one window's geometry. The frame code does not
vanish wholesale.

**Four failures, and two of them were the kind that ship.**

1. **A splice that would have compiled.** The first version cut everything from the
   `aucmd_win[]` search through `curbuf = buf;` — which also swallowed
   `aco->save_curwin_id` and `aco->save_prevwin_id`, the two fields
   `aucmd_restbuf()`'s surviving branch reads back through `win_find_by_id()`. It
   would have built cleanly and restored from uninitialised stack. A count check on
   an unrelated line is what stopped it; the cut is now two narrow splices.
2. **`drop_if` refused an `else`, correctly.** `aucmd_restbuf()`'s
   `if (aco->use_aucmd_win_idx >= 0)` has one, and deleting the `if` alone would
   orphan it. `fold_never` is the helper for that shape.
3. **Three places managed the table without reading it** — `autocmd_init()`, whose
   whole body was a `memset` of it, and two loops in `screenalloc()` freeing and
   reallocating line sizes for windows that can no longer exist. The `can_cindent`
   shape from phase 64, found by the post-condition grep rather than by any warning.
4. **The must-go list contradicted the phase's own header.** It demanded
   `last_status_rec` reach zero mentions while the header said `last_status()`
   stays. The check was wrong, not the tree.

### The delta

**None.** No key, command or option changes. Measured: 96,636 → **94,122 lines**,
the largest single phase since the early cuts.

## Phase 69 — one file argument, and no argument list

**The order is the opposite of the obvious one, and the first attempt at this
phase proved why.** That attempt imposed buffer reuse inside `buflist_new()` and
deleted the argument-list call that reaches it — and that call is **the only thing
that names the first buffer**. `open_buffer()` reads through
`readfile(curbuf->b_ffname, …)`, so with no name it read nothing: the buffer came
up empty, every edit was a silent no-op, and `:wq` wrote the original bytes back.
It compiled cleanly and passed two of its three probes. It was dropped whole.

So this phase limits the command line **first** and leaves the naming path exactly
as it is:

- **One file argument.** A second non-option argument is
  `mainerr(ME_TOO_MANY_ARGS)`, which is what vim already answers for a second `-`.
  One file means one entry, which is what makes the list pointless rather than
  merely unused.
- **The name still goes through `buflist_add()`.** `curbuf` exists and is unnamed
  and empty when `command_line_scan()` runs — `main()` calls `common_init_2()`,
  which calls `win_alloc_first()`, before the scan — so `buflist_new()` reuses it
  and sets `b_ffname`, exactly as before. Only the *list* around that call goes.
- **The argument list.** `:next` and `:previous` point at `ex_ni`; the other 21
  argument commands already did. Gone with them: `ex_next`, `ex_previous`,
  `do_argfile`, `do_arglist`, `arglist_del_files`, `alist_set`, `alist_clear`,
  `alist_add`, `alist_add_list`, `alist_check_arg_idx`, `alist_name`,
  `check_arg_idx`, `editing_arg_idx`, `arg_all`, `check_arglist_locked`,
  `arg_had_last`, `global_alist`, `alist_T`, `aentry_T`, `w_alist`, `w_arg_idx`,
  `w_arg_idx_invalid` and `mparm_T.fname`.

**What folds because the count is always one**: `check_more()`, whose "N more
files to edit" refusal can never fire; `append_arg_number()`, the `(N of M)`
suffix; `##` in a file-name modifier, which had every argument to expand and now
has none; and the seven `ADDR_ARGUMENTS` arms of Ex range parsing.

**`ADDR_ARGUMENTS`'s labels stay, and its bodies go.** Deleting the labels earns
seven *"enumeration value not handled in switch"* warnings — those switches
enumerate `ADDR_*` exhaustively — which is what the sweep kept reporting as "left
alone 7" while never converging. Each arm gets a constant body instead.

### The delta

**None, and that was measured rather than assumed.** `:next` and `:previous` were
declared as moving and did not. An `exsweep` row is `exit= left= err=`, and with
one file argument `do_argfile()` already answered *"there is only one file to
edit"* — so pointing the rows at `ex_ni` changes the message text, which the sweep
does not record, while the exit status, the files touched and stderr all stay the
same. The declaration was **narrowed** to match the measurement; widening one to
fit is what `whimdelta.sh` exists to refuse.

The probes are **load-first**: `+$` then `+s/^/LAST /` proves the buffer holds the
file's lines, which is the check the abandoned attempt lacked and needed. Then
plain editing, a second file argument refused without writing either file, `:next`
refused, and `:e` still opening a second file.

Measured: 94,122 → **93,393 lines**.

## Phase 70 — :e reloads in place, and there is no swap file

**This invariant is imposed, not proved**, and that is the difference between it and
phase 68. One window fell out of the two places a window could be created. A second
*buffer* is genuinely reachable: `curbuf_reusable()` wants an unnamed, empty buffer,
so once the first file is named, `:e other` allocates a new `buf_T` and switches to
it. Measured on q69: `:e h2.txt` then `+wq h1.txt` writes **h2**.

So `do_ecmd()` is made to reuse the one buffer:

- the `other_file` branch renames `curbuf` with `setfname()` instead of calling
  `buflist_new()`, sets `oldbuf = FALSE`, and falls through;
- the reload path below it — `u_sync()`, `u_savecommon()`,
  `buf_freeall(curbuf, BFA_KEEP_UNDO)`, then `open_buffer(… READ_KEEP_UNDO)` —
  **already is** "wipe and re-read in place". Its gate widens from
  `!other_file && !oldbuf` to `!oldbuf`;
- the whole `if (buf != curbuf)` block goes: BufLeave, `buf_copy_options`, `u_sync`,
  `close_buffer(DOBUF_WIPE)`, the `auto_buf` dance, the `curwin->w_buffer` swap and
  `get_winopts`. It is removed by **brace matching**, not by matching its body —
  the body is long and macro-expanded, and three runs of an abandoned phase died on
  patterns transcribed from truncated views of exactly such lines.

**Order: `fname2fnum()` first.** It called `buflist_new(name, p, 1, 0)` to give a
file mark's file a buffer, and once reuse is unconditional that call would wipe the
buffer being edited. It is **folded to an empty body, not removed** —
`getmark_buf_fnum()` still calls it, and the file marks are a separate cut. An empty
shell with a live caller is the fold, not a leftover, so the check asserts that its
body can no longer reach `buflist_new()` rather than that the symbol is gone. A
first version demanded zero mentions and failed on its own terms.

**What is lost:** the state of the file you leave — its undo history and its marks.
`:e`, `:e!` and `:wq` keep working, on one buffer.

### No swap file, ever — not even one left from another age

Swap files are already never *written* here: `findswapname`, `p_swf`,
`swapfile_info`, `swapfile_unchanged`, `ml_recover` and `ml_sync_all` went with the
recovery phase, `mf_open()` is the in-memory memfile, and `ml_open_file()` had been
reduced to a single `b_may_swap = FALSE`.

What survived was the **detection** half — the prompt for a swap file somebody else
left behind — and it was already unreachable. Measured on q69 with a `.swp` sitting
beside the file: **no prompt at all**, no stderr, the edit and the write going
through in silence. This is the `can_cindent` shape again, a flag written in three
places and never once true, and the compiler cannot say so because assigning to a
static counts as using it.

So the whole surface goes together: `swap_exists_action`, the three `SEA_*` actions,
`handle_swap_exists()`, `check_swap_exists_action()`, `check_need_swap()`,
`ml_open_file()` and the `b_may_swap` field, with the `SEA_DIALOG` setters in
`do_ecmd`, `read_stdin` and `create_windows` and the three `SEA_QUIT` tests that
could never fire.

One of those tests is worth naming because it is not where it looks like it should
be: the *first change to a buffer* used to open its swap file, and that test lives in
`changed()`, not in `buf_write()`. Writing the host function from memory got it
wrong, and reading line 8756 got it right.

The three enums the sweep reports as "every constant is dead and the type is in use,
which cannot be expressed" are **inherited, not made here** — pristine q69 reports
the same three.

### The delta

**None.** `:e` prints nothing to stderr, and an `exsweep` row is `exit= left= err=`
— the same reason `:next` did not move in phase 69. Removing the swap surface moves
nothing either, for the same reason and one more: the prompt it removes was already
never reached. The probes are load-first and **quote-free**: `+$` then `+s/^/LAST /`
proves the buffer holds the file; then `:e h2.txt` leaving h1 untouched and writing
h2; plain editing; and `:e!` discarding an unwritten change. No probe key contains
`'`, which is what made an abandoned phase's mark probes measure nothing three times
over.

Measured: 93,393 → **93,127 lines**.

## Phase 71 — one buffer, structurally

**The invariant was already true; this phase removes the machinery that pretended
otherwise.** Phase 69 allowed at most one file argument, phase 70 made `:e` reuse the
one buffer, and every buffer Ex command had been retired long before that — all 24
rows (`:buffer`, `:buffers`/`:ls`/`:files`, `:bnext`, `:bprevious`, `:bNext`,
`:bfirst`, `:blast`, `:brewind`, `:bmodified`, `:bdelete`, `:bunload`, `:bwipeout`,
`:bufdo`, `:ball`, `:badd`, `:balt`) already read `ex_ni`, and `do_buffer`,
`do_bufdel`, `ex_buffer`, `ex_bufdo` and `ex_listdo` do not exist. So nothing can
make a second buffer: `win_alloc_first()` makes the one buffer at startup, *before*
`command_line_scan()`, and `buflist_add()` then names that same buffer through
`BLN_CURBUF`.

`buf_valid()` becoming `return buf == curbuf;` is the keystone — it makes
`set_curbuf()`'s `enter_buffer(lastbuf)` fallback unreachable, and the rest of that
function's other-buffer handling with it.

### Three things named b_next are not the buffer list

A regex over the name would gut the editor, so every edit is scoped by function:

- `buffblock_T.b_next` — the typeahead and redo chain: `bh_first`, `redobuff`,
  `old_redobuff`, `readbuf1`, `readbuf2`. About thirty sites.
- `free_buffer()` — `buf->b_next = au_pending_free_buf`, a free list.
- `buf_T.b_next`/`b_prev` — **this** is the buffer list, and only this.

`au_pending_free_buf` turned out to be written in two places and **read in none**:
nothing ever drained that chain, so the `autocmd_busy` branch leaked the buffer and
always had. It goes with the field it linked through, and `free_buffer()` now always
frees immediately.

### break binds to the loop, not to the braces

Folding `for ((buf) = firstbuf; …)` into `buf = curbuf;` rebinds any `break` or
`continue` in the body to whatever loop encloses it next — and brace depth has
nothing to do with which statements those are. `getout()`'s `break` sits two `if`s
deep and still bound to the walk; `buflist_findpat()`'s body has a `break` **and** a
`continue` that bind to the walk while a third `break` correctly belongs to an inner
window loop.

The first version folded both anyway. `getout()` failed to compile, which is the
cheap outcome. `buflist_findpat()` **compiled fine and changed behaviour** — its two
statements silently rebound to the enclosing `for (;;)` retry loop — and sat
undetected through three dry runs. So `fold_walk()` now refuses a body whose
`break`/`continue` is not inside a nested loop or switch of its own, and the two
functions are rewritten rather than folded. An earlier version of that guard tested
brace depth and would have passed `getout()`; depth is the wrong question.

With one buffer `buflist_findpat()` has nothing to retry — one candidate, so the
"more than one match" (`-2`) arm is unreachable by construction.

### What stays

`buf_hashtab` and `buflist_findnr()`, because five live callers still look a buffer
up by number: `eval_vars`, `setmark_pos`, `check_changed_any`, `buflist_nr2name` and
`buflist_getfile`. Collapsing that to a `curbuf` test is a separate step.
`DOBUF_WIPE_REUSE` keeps its enum and the two tests that name it — no caller ever
passes it, which is what made `close_buffer()`'s wipe splice unreachable; that splice
was guarded by `(b_prev != NULL || b_next != NULL)`, already false with one buffer.

### The delta

**None**, and `whimdelta.sh` confirms it. The buffer commands were already `ex_ni`,
so no `exsweep` row can move.

**A probe that cannot fail proves nothing, again.** The buffer-local mapping probe
was written `+normal! Q` — and `normal!` suppresses mappings *by definition*, so it
could never fire on any build. Calibrated against q70: `x` with the bang, `x!`
without it, and the phase-71 build gives `x!` too. The bang is gone and the comment
says not to put it back. It also corrected a belief: that walk is
`check_map_keycodes()`, which feeds `add_termcap_entry()`, **not** mapping lookup —
a mapping is found through `curbuf->b_maphash[]`, which never touches the list.

Measured: 93,127 → **92,749 lines**.

## Phase 72 — one window, one tabpage, structurally

**The invariant is provable, not imposed** — the phase 68 shape rather than the phase
70 one. Windows are created in exactly one place: `win_alloc(NULL, FALSE)` from
`win_alloc_firstwin()`, whose only caller is `win_alloc_first()` at startup.
`alloc_tabpage()` is called exactly once, from the same function, and `curtab` is set
to it there. `:tabnew`, `:tabedit`, `:split`, `:new` and the rest are already
`ex_ni`, and `aucmd_win` went in phase 68. So `firstwin == lastwin == curwin` and
`first_tabpage == curtab`, always.

### Two layers, folded as a pair

Nearly every tabpage walk immediately contains

```c
for ((wp) = ((tp) == curtab) ? firstwin : (tp)->tp_firstwin; (wp); (wp) = (wp)->w_next)
```

so folding the outer walk to `tp = curtab` makes that ternary constant-fold to
`firstwin`, and folding the inner one then gives `curwin`. Cutting one layer without
the other would leave half a traversal at 15 sites. 43 walks folded: 13 nested, 14
over the tabpage list, 16 over the window list.

**The whole tabpage-switching group hangs from one gate.** `goto_tabpage_tp()`'s body
is `if (tp != curtab && leave_tabpage(…) == OK)`, never true with one tabpage.
Folding that gate orphans `leave_tabpage`, `enter_tabpage`, `valid_tabpage`,
`use_tabpage`, `win_init`, `win_copy_options` and `win_init_some`, and the sweep
removes them — taking the last readers of `tp_firstwin`, `tp_lastwin` and
`tp_prevwin` with them, 13 dead fields in all. Nothing here deletes those by name.

### The break audit, run before writing the script

Phase 71 learned that folding a walk rebinds any `break`/`continue` in its body, and
that the failure can be silent. So this phase's walk audit ran **first**, and named
its seven exceptions in advance: `aucmd_prepbuf`, `can_unload_buffer`,
`borrow_stl_vsep_hl` (two walks), `current_win_nr`, `current_tab_nr`, `getout` and
`create_windows`. Each is rewritten rather than folded, and `fold_walks()` **dies**
rather than skipping if it ever meets an eighth. It did not.

`borrow_stl_vsep_hl` lends a status line's highlight to the separator beside it; with
one window there is no beside, so the function and its two calls go.

### What the walk audit could not see

`w_next` survived the fold with six readers, because `win_ins_lines`,
`win_del_lines` and `win_do_lines` ask `wp->w_next` as a **layout question** — "is
there anything below this window on the screen" — and never traverse. No `for` head
mentions them. The zero-mention assertion is what found them.

One of those is not cosmetic: `win_rest_invalid()` no longer walks, so it
dereferences its argument unconditionally, and the two surviving
`win_rest_invalid(wp->w_next)` calls would have passed NULL and crashed.

### A blind spot the sweep does not cover

Folding `for ((tp) = first_tabpage; …)` into `tp = curtab;` leaves a variable nothing
reads, which gcc reports as `-Wunused-but-set-variable` — and `deadsweep.py` handles
`unused-variable` and `unused-function` and **nothing else**. Eight functions were
left that way, which is what the sweep's persistent "left alone 8" meant.
`check_changed_any` and `min_rows_for_all_tabpages` still read their `tp`, so theirs
stay; `changed_common` had three assignments, not one.

The first count of five came from reading a gcc list I had truncated at twenty lines.
The full list is eight.

### What stays, deliberately

The **frame layer** — `topframe`, `frame_T`, `fr_next`, `fr_child`, `fr_parent`. One
window still has one frame and sizing needs it; cutting frames is its own phase.
**`b_nwindows`**: tracing every write, it is 1 at creation, balanced `++`/`--` in
`enter_buffer` and `aucmd_restbuf`, and `--` in `close_buffer` — genuinely 0 once the
window drops the buffer, so `<= 0` and `== 0` are live "not displayed" tests. An
earlier plan folded all 20 sites to a constant 1; that would have broken buffer
release silently. **`prevwin` and `w_id`**, which `aucmd_prepbuf`/`aucmd_restbuf` and
the incsearch state use, are not list state.

### The delta

**None**, and `whimdelta.sh` confirms it. Every window and tabpage Ex command was
already `ex_ni`.

**A third probe that could not fail.** The autocommand probe was written
`+autocmd BufWritePre * normal! A-au` — and `:autocmd`, `:augroup`, `:doautocmd` and
`:doautoall` are all `ex_ni` here, so it registered nothing and fired on no build.
Calibrated against q71: the same answer as this phase gives. After `<LeftMouse>` and
`normal!`, the rule that catches all three is now written into the script:
**calibrate a new probe against the previous boundary before trusting it**, which
costs one build. The replacements — a write that completes through `getout()`'s
rewritten BUFWINLEAVE block, and an `O` that exercises the folded scroll path — were
calibrated that way and pass on q71.

Measured: 92,749 → **92,110 lines**.

## Phase 73 — one frame

**The strongest invariant of this run, and it is proved by absence.** Grepping the
whole file for a write to `fr_child`, `fr_next`, `fr_prev` or `fr_parent` returns
**nothing at all**. The frame tree is never linked:

- `alloc_clear(sizeof(frame_T))` appears exactly once, in `new_frame()`, whose only
  caller is `win_alloc_firstwin()` — itself called once, from `win_alloc_first()`;
- `new_frame()` writes `fr_layout = FR_LEAF` and `fr_win = wp`, and nothing else ever
  writes `fr_layout`;
- `win_alloc_firstwin()` sets `topframe = curwin->w_frame`;
- there is no `frame_insert`, `frame_append`, `frame_remove`, `win_split` or
  `win_split_ins` anywhere — they went with the window layout in phases 68 and 72.

So `topframe == curwin->w_frame`, `fr_layout` is `FR_LEAF` forever, and the four tree
pointers are permanently NULL. Every `FR_ROW`/`FR_COL` branch is dead, every
`fr_child` walk iterates zero times, and every `fr_parent` walk stops on its first
test.

That makes this phase a set of **body replacements** rather than a fold campaign —
fifteen of them. Each function keeps the arm that runs and loses the arms that
cannot: `frame_fixed_height`/`frame_fixed_width` → `FALSE`; the minima keep their
leaf arm; `frame_check_height`/`frame_check_width` compare one frame;
`frame_comp_pos` keeps the `fr_win != NULL` arm; `frame_new_height` keeps the
cmdheight adjustment and `win_new_height`; `frame_new_width` clears `w_vsep_width`
and calls `win_new_width`; `frame_setheight` keeps the root arm and `frame_setwidth`
returns; `frame_add_height` loses the parent walk; `last_status_rec` keeps `FR_LEAF`;
`command_height` loses the walk to the widest ancestor; `stl_connected` → `FALSE`.

**The invariant is asserted in the phase, not just in this document.** The script
greps for a write to any tree pointer and dies if it finds one, so if an upstream
ever links a frame again this fails loudly instead of producing an editor that
silently mis-sizes its one window.

**The break hazard was handled by construction.** The audit named four loops whose
`break` binds to the loop being removed — `stl_connected`, `frame_new_height`,
`frame_new_width` (twice) and `command_height` — and all four were already in the
replace-whole-body set, so nothing was folded out from under a `break`. This is the
phase 71 lesson applied ahead of time, and it is why **this phase passed its first
dry run**, the only one in this run that did.

### What is not a constant

`frame_minheight()` reads `p_wh`, `p_wmh` and `w_status_height`, and `min_rows()` and
`did_set_cmdheight()`'s clamp both depend on the number it returns — so the leaf arm
keeps its arithmetic exactly and only the recursion goes. Replacing it with a literal
would silently change what `:set cmdheight=` accepts, which no probe here would have
caught. A post-condition asserts `p_wh` and `p_wmh` still appear in its body.

`fr_width` and `fr_height` stay: they are live layout state, read by `win_do_lines`,
`screen_ins_lines`, `screen_del_lines`, `redraw_block`, `screen_line`, `win_line` and
`did_set_cmdheight`. The **fields** stay; only the tree goes.

`frame_fixed_height`, `frame_fixed_width`, `frame_minwidth` and `frame_fix_height`
fall out by cascade once their callers' `wfh`/`wfw` loops vanish, and `FR_ROW` and
`FR_COL` lose every reader. Nothing deletes those by name.

### The delta

**None**, and `whimdelta.sh` confirms it. Every splitting and resizing Ex command is
already `ex_ni`, and `:set cmdheight=` keeps its accepted range because
`frame_minheight` kept its arithmetic.

Two new probes drive the rewritten bodies — `:set cmdheight=2` through
`did_set_cmdheight` → `command_height` → `frame_add_height`, and `:set laststatus=2`
through `last_status` → `last_status_rec` — and **both were calibrated against q72
before being trusted**, which is the rule three earlier probes in this run were
written in violation of.

Measured: 92,110 → **91,329 lines**.

## Phase 74 — no file marks

**This is the phase that was abandoned as 70**, and the difference between the two
attempts is the whole lesson.

The first attempt died three times on patterns transcribed from *truncated views* —
`ex_delmarks`' `|| to < from` tail, `clrallmarks`' `static int i = -1` guard over
`26 + 1` (not `26 + EXTRA_MARKS`, which is what I kept writing), and four adjust
sites I had never enumerated. Worse, its probes **measured nothing**: a mark name
like `'A` carries a quote, the shell quoting broke, and the key was never pressed —
so three runs produced no evidence either way. It was dropped on instruction.

This time every site was read with `cat -A` first, **every anchor was pre-flighted
against pristine q73 and came back ALL OK before the script ran**, and both probes
were calibrated on q73. It passed its first dry run.

### What goes

`namedfm[26 + EXTRA_MARKS]` — which is **both** the uppercase A–Z file marks and the
numbered 0–9 marks. One array, one set of code paths, so they cannot be separated;
and with viminfo long gone nothing could ever set the numbered ones anyway, so they
were a store no code could write.

`getmark_buf_fnum`'s A–Z/0–9 arm was the **only** caller of `buflist_getfile()` and of
`fname2fnum()` — the latter already an empty body from phase 70, folded there
precisely because *"the file marks are a separate cut"*. Removing the arm leaves
`posp` NULL, which `check_mark()` already reports as E20, exactly as an unset
lowercase mark does.

The sweep then took `buflist_nr2name`, `fmarks_check_one` and `getfile` by cascade.

### What stays

The lowercase marks `a`–`z` in `buf->b_namedm[]`, and every special mark — `'`,
`` ` ``, `"`, `^`, `.`, `[`, `]`, `<`, `>` — none of which touch `namedfm`. `:marks`
still lists what is left and `:delmarks` still clears it; uppercase and digits now
fall to "invalid argument".

**`fmark_T` stays**: `struct taggy` embeds it, so the tag stack depends on it. Only
`xfmark_T`, which exists to bolt a filename onto a mark, goes.

**`do_join()` has a parameter named `setmark`**, so every edit is scoped by function.
An unscoped pattern or a global rename would have corrupted it — the `b_next` lesson
from phase 71 wearing a different hat.

### The delta

**None**, and `whimdelta.sh` confirms it.

The probes are worth stating because this is where the first attempt failed. The
**discriminator** is a pair: on q73 a lowercase mark gives `K1|K2-kept|K3|` and an
uppercase mark gives `U1-up|U2|U3|`; after the cut lowercase is unchanged and
uppercase gives `U1|U2|U3|`. The uppercase half *changes*, which is what makes it
evidence rather than decoration. The mark name is kept out of shell-metacharacter
position by double-quoting the vim text.

`:marks` and `:delmarks` are **not** discriminators — both write the file either way
and neither reaches stderr — so they are no-crash checks only, and the script says so
rather than letting a later reader mistake them for proof.

Measured: 91,329 → **90,972 lines**.

## Phase 75 — no autocommands

**Proved by absence, not inferred from the command table.**
`first_autopat[NUM_EVENTS] = { NULL }` is the **only** write to that array in the
whole file; every other mention reads it. No autocommand pattern can ever be
registered. `:autocmd`, `:augroup`, `:doautocmd`, `:doautoall` and `:noautocmd` were
already `ex_ni`, but that is the weaker argument — the array being write-once-to-NULL
is the strong one.

It follows that `apply_autocmds_group()` was already `return FALSE;`, that its three
one-line wrappers made **all ~74 dispatch sites no-ops**, that
`has_cursormovedI`/`has_textchangedI`/`has_textchangedP` were always FALSE, and that
`au_cleanup`, `au_remove_pat`, `au_del_cmd` and `aubuflocal_remove` walked a
permanently empty list.

**The invariant is asserted in the phase**, and the assertion was *proved able to
fail*: injecting a synthetic `first_autopat[0] = NULL;` makes it fire. A first
version matched `first_autopat[^\n;]*=` and reported three writes that were the `!=`
of the `has_*` predicates — it spanned the subscript and landed on the comparison. An
assertion that cries wolf is worse than none, because the temptation is to loosen it
until it passes.

### Two sites rewritten, not folded

`close_buffer()` — the label `aucmd_abort:` sat **inside** the block guarded by
`apply_autocmds(EVENT_BUFWINLEAVE, …)`, with three `goto`s targeting it, two from
outside. Folding would have orphaned them: the phase-71 break-rebinding hazard
wearing a label instead of a loop. All three gotos fold away with their conditions,
so the label goes too and `if (abort_if_last)` carries the abort directly.

`buf_write()` — the 132-line block **looks** like pure scaffolding (`aco_save_T`,
`aucmd_prepbuf`/`restbuf`, `set_bufref`, `did_cmd`) but computes `buf_ffname`,
`buf_sfname`, `buf_fname_f` and `buf_fname_s`, which are **read a hundred lines
later** to restore `ffname`/`sfname`/`fname`. Deleting it wholesale would have broken
`:w` on a renamed buffer. The scaffolding goes; the flags stay, and a `:w dst.txt`
probe guards it.

### Classification had to be done by hand

A scan got two sites **backwards**. `7712` and `7741` read
`if (!(did_cmd = apply_autocmds_exarg(...)))` — negated *with an embedded assignment*
— so they are always **TRUE** (`fold_always`), not always false. A
`startswith("if (!apply_autocmds")` test cannot see the `!(var = …)` shape, and
folding them the other way deletes the branch that runs.

`did_cmd` then needed its **two readers folded before its declaration was removed**;
doing it the other way round leaves them undeclared, which is precisely the compile
error a first version produced.

### Ordering is part of the edit

Three edits depend on an *earlier* edit having created their target, and must run
after it: `buf_write`'s scaffold and `set_termname`'s husk only take their final
shape once the blanket dispatch removal has emptied them. Pre-flighting those against
an already-swept tree confirms the shape while saying nothing about when it becomes
valid — the fix is to **replay the script's own steps** and read the result.

`set_termname`'s husk is removed by brace matching keyed on `buf = curbuf;`, not by a
literal: the literal was transcribed twice from a post-sweep tree where `deadsweep`
had already dropped the now-unused `aco_save_T aco;`. The helper **refuses** a block
that does any real work, and that refusal was demonstrated before being relied on.

### What survives, deliberately

`block_autocmds`/`unblock_autocmds` keep four caller pairs that are not autocommand
code — `set_string_option_direct_in_win`, `u_undoredo`, `win_alloc` — so both stay,
and `autocmd_blocked` stays with them as a **write-only counter** belonging to the
combined phase. Asserting any of the three reached zero would fail the phase on its
own terms.

### The delta

**None**, and `whimdelta.sh` confirms it. Nothing could fire an autocommand, so
removing the dispatch cannot change what the editor does.

A `:%!sort` probe was written and **discarded**: `!` went in phase 64, so it fails on
the baseline too and would have measured nothing. The eight that remain — load,
write, `:w name`, `:e`, `:g`, `:s`, `:m`, undo, insert — were each calibrated against
q74 first.

Gone: the `EVENT_` enum (123 enumerators), `event_tab` (127 rows), `AutoPat`,
`AutoCmd`, `AutoPatCmd_T`, `active_apc_list`, `first_autopat`, `last_autopat`,
`aucmd_prepbuf`, `aucmd_restbuf`, `aco_save_T`, `getnextac`, `auto_next_pat`,
`event_nr2name` and all four dispatch wrappers.

Measured: 90,972 → **89,804 lines**.

## Phase 76 — one regexp engine, so no retry

**Proved by a single assignment.** `prog->re_engine = BACKTRACKING_ENGINE` is the only
place `re_engine` is ever written, so the field can hold no other value — and both

```c
if (rmp->regprog->re_engine == AUTOMATIC_ENGINE && result == -1)
```

blocks, one in `vim_regexec_string` and one in `vim_regexec_multi`, are unreachable.
They exist to recompile a pattern with the backtracking engine when the automatic
choice failed; with one engine there is nothing to fall back to. `nfa_regengine` and
`regexp_engine` were already at zero — the NFA engine went in an earlier phase, and
these two blocks were what remained pointing at its corpse.

**What went with them.** `p_re` entirely: it is an **orphan option** — no row in the
table sets it, so it reads as 0 for ever — and its only uses were a `< 0 || > 2`
validation that could never fire and the save/restore inside the two dead blocks.
`AUTOMATIC_ENGINE`, which had no other reader. And `nfa_regprog_T` with `nfa_state_T`
by cascade: their only non-type mentions were the two
`((nfa_regprog_T *)rmp->regprog)->pattern` casts **inside** the dead blocks — a husk
kept alive purely by unreachable code. The sweep deleted three type definitions.

`orphanopts` independently confirms the claim: its count fell from six orphans to
five, with `p_re` gone from the list.

### The guard was proved against both failure modes

The phase asserts in-flight that `re_engine` has exactly one assignment and that it
is to `BACKTRACKING_ENGINE`. Before relying on it, it was checked three ways: it
reports one on the real file, it **fires** when a second write is injected, and it
does **not** miscount a `!=` comparison as a write — which is exactly the cry-wolf
bug that cost an iteration in phase 75, where a guard matched `name[^\n;]*=`, spanned
the subscript and landed on the comparison.

### Audited before writing, not after

Both blocks are 25 lines, carry no `break` or `continue` that would rebind, contain
no label, and are followed by no `else` — so `fold_never` takes them without any of
the hazards phases 71, 72 and 75 each ran into. No edit's target is created by an
earlier edit either, so the specific-then-blanket ordering problem does not arise.
**It passed its first dry run.**

### The delta

**None**, and `whimdelta.sh` confirms it. The blocks never ran, so removing them
cannot change a match.

The probes exercise **matching**, not editing, because a load-and-edit probe would
pass whatever happened to the regexp layer: a quantified `%s/a\+/X/g`, `:g` over a
pattern driving `vim_regexec_multi`, capture groups with back-references, a counted
non-capturing group `\%(a\|b\)\{2}` — the shape the NFA engine used to be chosen for
— and a plain search. All five were calibrated against q75 first.

Measured: 89,804 → **89,713 lines**.

## Phase 77 — no buffer-name argument matching

`do_one_cmd()` computes

```c
ni = (!(cmdidx < 0) && (cmd_func == ex_ni || cmd_func == ex_script_ni))
```

— "this command is not implemented" — and **seven** later checks consult it before
doing work. One does not: the `EX_BUFNAME` pre-dispatch block, guarded only by
`!(cmdidx < 0)`, which compiles a regexp and matches it against the buffer to turn
`:buffer foo` into a line number.

**Every command carrying `EX_BUFNAME` is `ex_ni`** — `:buffer`, `:bdelete`,
`:bunload`, `:bwipeout`, `:checktime`, `:sbuffer` and `:pbuffer`. That last one is
worth noting: an earlier hand grep found only six because `:pbuffer`'s row spells the
handler with surrounding spaces (` ex_ni `). The phase counts the rows **dynamically**
and asserts every handler is `ex_ni`, so it is right regardless of how many there are.

**The edit is a fold, not a guard.** Adding `&& !ni` would leave a block that can
still never run — dead weight wearing a condition. The condition is false for every
command that reaches it, so `fold_never` removes it outright and `buflist_findpat`
loses its only caller.

### A goto statement, not a label

The block contains `goto doend;`, and that is safe: `doend` is `do_one_cmd`'s shared
exit label with 27 gotos targeting it, so this removes a goto **statement**. The
distinction is the one that mattered for `readfile`'s `theend` in phase 75, and for
`close_buffer`'s `aucmd_abort`, where the label itself sat inside the fold and three
gotos would have been orphaned.

### What went by cascade

`buflist_findpat` (71 lines), `file_pat_to_reg_pat` (167), `buflist_match` (13) and
`fname_match` — the last reachable only through the pattern matcher and not
predicted. 306 lines against an estimate of 251. Nothing is deleted by name here;
removing the one call site orphans them all and the sweep takes them.

### The delta

**None**, and `whimdelta.sh` confirms it. `:buffer foo` already exited 1 with nothing
on stderr — `ex_ni` sets `eap->errmsg` rather than printing, and an `exsweep` row is
`exit= left= err=`. Measured on q76: exit 1, empty stderr, file written either way.
So the gain is code, not behaviour, and the phase says so rather than claiming a
user-visible fix.

`:buffer nosuchname` is therefore **not used as a discriminator** — only as a
does-not-crash check. The probes that can actually fail exercise what survives: the
load, a write, `:e` naming a file (the argument path *next to* the one removed), and
`:g` taking a pattern. All were calibrated against q76 first.

It passed its first dry run.

Measured: 89,713 → **89,407 lines**.

## Phase 78 — empty functions, write-only counters, and the window id

Three unrelated kinds of leftover, all invisible to the compiler and so to every
sweep this pipeline runs. A fourth — the constant-return predicates — was **split
out into its own phase** once the survey showed it is not one shape but several:
only about twenty of the twenty-nine sit in a foldable `if`, the rest needing
term-level or expression edits, seven fold sites carry an `else`, one needs a rewrite
for an escaping `break`, and one is a function pointer in an option table row that
must not be touched. Bundling them here would have repeated the shape that cost
phase 75 eight iterations.

**Fifteen empty functions, 49 call sites.** Each was emptied by an earlier phase and
left with its callers in place. **Every one of the 49 is a bare statement** — checked,
not assumed: none appears in an `if`, an assignment or any larger expression, so a
line removal cannot corrupt a condition. That was the trap in phase 75, where
`ins_apply_autocmds` calls were invisible to a regex anchored on `apply_autocmds`.
The phase re-checks each body is still empty before removing its calls, and counts
mentions against bare-calls-plus-prototype-plus-definition so a hidden use fails the
phase rather than the compiler.

**`nv_nop` is not among them.** It is empty by design — the `nv_cmds` row for
`KE_NOP` — and `nvidxcheck.py` requires `nv_cmd_idx[]` to stay a permutation.

**Six write-only statics**: `autocmd_blocked` (its reader went in 75),
`autocmd_no_enter`, `autocmd_no_leave`, `redrawing_for_callback`, `prevwin`,
`last_win_id`. `block_autocmds()`/`unblock_autocmds()` become empty and **stay** —
eight live call sites, one deliberately unpaired in `deathtrap()` where the process
is dying and never unblocks.

**Two that the same scan flags and that must not be touched**: `breakcheck_count` is
*read* by `if (++breakcheck_count >= BREAKCHECK_SKIP)`, and `vim_ignored` is the
deliberate sink for discarded return values kept in phase 67. A scanner counting
`++x` as a write, unable to see the read in `x = call()`, reports both as write-only.

**The window id**, one chain: with one window `curwin->w_id` is constant, so both
`if (is_state.winid != curwin->w_id)` guards in `getcmdline_int` can never fire —
matched by regex, not a literal, because they sit at different indents. Folding them
makes `winid` write-only, then `w_id`, then `last_win_id` and `LOWEST_WIN_ID`.

### The field that was not dead

`termrequest_T.tr_start` was on the Tier-1 list with **one** identifier mention — its
declaration — and removing it produced three *"excess elements in struct
initializer"* errors. `termrequest_T` is positionally initialised three times as
`{STATUS_GET, -1}`, and **that `-1` is `tr_start`**. A positional initialiser names
nothing, so counting identifiers cannot see the use — which is exactly why
`deadfields.py` exempts every field of a type that has one. The exemption was
recorded during the audit and then ignored.

`cmdarg_T.prechar` is the contrasting case and was removed safely: its only
positional initialiser is `cmdarg_T ca = { 0 };`, which supplies one value and
zero-fills the rest, so it cannot overflow. The distinction is whether the initialiser
supplies enough values to reach the field being removed.

Two assertions in this phase also had to be repaired before it would run: one still
demanded `tr_start` reach zero while another demanded it survive, and an initialiser
count used `[a-z_]+_status`, which cannot match the digit in `u7_status`.

### The delta

**None**, and `whimdelta.sh` confirms it. An empty function called or not called does
the same nothing, a counter nobody reads has no effect, and the two `winid` guards
could never fire. The inventory was produced by two independent scanners that agree
exactly on all 16 empty functions and 32 stubs.

Measured: 89,407 → **89,233 lines**.

## Phase 79 — the constant-return predicates

Twenty-eight functions whose whole body is `return <constant>;`. Each was emptied by
an earlier phase and left with its callers in place, so the editor still asks "is the
popup menu visible", "are we in a Vim9 script", "is there more than one window" — and
still branches on an answer that cannot change. No sweep can see this: at `-O0` each
is a real call and a real branch, and the code is *reachable*. Unuseful, not unused.

**The invariant is asserted, not trusted.** Step 1 reads all 28 definitions and
requires each body to be exactly `return <expected>;`, with the expected token written
out per name. If an upstream ever gives one a real body the phase fails instead of
folding a live predicate. That is phase 77's pattern, and it is the only thing between
a fold and a wrong answer.

### Four that look identical and are not

A scan for `return <single token>;` reports 32. Four of those tokens are **variables**:
`get_hislen`→`hislen`, `is_maphash_valid`→`maphash_valid`, `get_search_pat`→`mr_pattern`,
`get_text_locked_msg`→ a static message. My first classifier said *thirteen* of the 32
returned a variable — it had matched the bare tokens `0`, `1` and `NULL` against
unrelated declarations elsewhere in the file. Reading the **definitions** gives four.
Supplying the expected constant per name is what makes that error impossible to repeat
silently, and an assertion requires all four to survive.

**`did_set_number_relativenumber` is a constant and still is not touched.** Its only
two mentions are option-table rows where it appears as a *function pointer* with no
call parentheses. Folding is meaningless and deleting it would leave two rows pointing
at nothing. An assertion requires both rows intact.

### `binds_out` vetoes fold_always, not fold_never

`parse_command_modifiers`' `if (vim9script)` block contains a `break` that binds to the
enclosing `for (;;)` — the shape that made `buflist_findpat` change behaviour silently
in phase 71. But that phase **folded a walk**, keeping the body while removing the loop
around it, so the `break` rebound. `fold_never` **deletes** the body, `break` and all,
and the condition was false, so it never fired. Every `fold_always` site here was
audited separately and none contains an escaping `break`.

### Three second-order cuts, each proved in the phase

**`skip_for_popup`** is not a stub on entry — it has three returns. Once `pum_under_menu`
and `pum_visible` fold, both its guards go and it becomes `return FALSE;`. The phase
re-runs the same `const_of()` check to *prove* the collapse before using it, then takes
nine more sites.

**`may_have_range`** is a local of `do_one_cmd` with two writes. One is inside the
`if (vim9script && …)` block this phase folds; the other is that block's `else` arm,
`may_have_range = TRUE;`. After the fold it has one write, is constantly true, and both
readers fold.

**`wc`** in `option_value2string` is `long wc = 0;` whose only "write" is `&wc` passed to
`wc_use_keyname` — which never dereferences `wcp`. So **both** arms of that chain are
dead, not just the first, and it collapses to the `sprintf`. Read from the body, not
assumed; the phase asserts `wcp` is absent from it.

`need_check_timestamps`, `need_redraw` and `bom_count` each become write-only once the
stub feeding them is gone, so their tests fold and the variables sweep.

### Ordering, and the ternary that spans a line break

Specific literals run before blanket regexes **except where a blanket edit creates the
specific one's target**. Three places turn on it, and the third is the sharp one: the
address ternary in `do_one_cmd` is the rare construct in this tree that spans a line
break, so it must be replaced *before* the blanket `current_win_nr` pass — which would
otherwise rewrite one half and leave `eap->line2 = eap->addr_type == ADDR_WINDOWS`
dangling. All 74 anchors were counted against the q78 tree before the program was
written, and that pre-flight caught the one edit I had never transcribed:
`&& !at_ins_compl_key()`, which I knew about only from a truncated survey line.

**No term edit ends in whitespace.** `only_one_window() && check_changed_any` becomes
`check_changed_any` rather than stripping `only_one_window() && `, because a literal
with a trailing space lost it passing through an editor in phase 71.

### Two bugs, both in the checks rather than the edits

**An assertion that a correct edit could not satisfy.** `vim9script` was in the
zero-mention loop, but four mentions survive and none is the identifier: three
former-file banner comments and the `[CMD_vim9script]` row, where it is the command
*name* — a string literal. A bare word count cannot tell an identifier from a comment
or a string. Phase 78 made this same mistake twice in one script.

**`set -e` killed the phase on the behaviour it was checking.** The quit probes were
written `( … ); rc=$?`, and a subshell whose status is not *tested* aborts under
`set -e`. The second probe runs `:q` on a **modified** file, which exits 1 by design —
so the script died after the build with every probe unrun, and the truncated log made
it look like a clean finish. The form is `rc=0; ( … ) || rc=$?`, which is a tested
context. Phases 77 and 78 avoided this with `|| true` and never needed the status.

### The delta

**None**, and `whimdelta.sh` confirms it. Every fold removes a branch whose condition
cannot hold and every term edit removes a constantly-true conjunct or a constantly-false
disjunct. The quit path is the one place where an error would be silent rather than
fatal — `check_more()` feeds the four `ex_quit`/`ex_exit` conditions that decide whether
`getout(0)` runs, so wrong folding makes the editor refuse to quit or quit without
saving. Five quit probes calibrated on q78 guard it: `:q` refuses a modified file,
`:q!` discards, `:wq` and `:x` write and exit.

Measured: 89,233 → **88,636 lines**.

## Phase 80 — the Ex command table, cut to the commands that exist

600 rows in `enum CMD_index` and `cmdnames[]`, and **489 were `ex_ni` or
`ex_script_ni`**. Every phase that removed a command had pointed its row at the stub
and left it, under rule 3 as it then read, because a row still did one job: its
*name* decided what every abbreviation of every other name meant. The rows, and the
two-level prefix index generated from them, were kept for that alone.

**The rows go and what they were for stays.** The old lookup took the first row, in
index order, whose name started with the typed word, so a command's shortest
abbreviation was implied by every row above it. Measured on q79: deleting the 489
rows in place hands **15 prefixes** that used to reach a stub to a live command —
`:n` to `nmap`, `:o` to `omap`, `:h` to `highlight`, `:sa` to `saveas`, `:la` to
`later`, `:en` to `enew`, `:ve` to `verbose`. No live command would lose an
abbreviation or gain another's; an error would just quietly become a mapping
listing.

So each surviving row **carries its shortest abbreviation**, computed from the
600-row table before a row is touched, in the field that held the name's length —
whose one reader was the Vim9 whole-name check, dead since Phase 79. A word names a
row when it is a prefix of the name and at least that long. That makes a match
**unique**, which makes row order irrelevant, which makes the index pointless:
`cmdidxs1`, `cmdidxs2`, `command_count` and E943 go, and the lookup is a scan of 111
rows. `tools/create_cmdidxs.py --check`, which fifteen phases between 58 and 79 ran, has no
block to check in `whim-vim.c` any more and is not called from here on. Its `names()`
still reads the table for `exsweep.py`, and refuses fewer than 100 rows; a phase that
takes the table below that has to lower the floor.

**Proved rather than argued, twice.** The program models the old lookup — the index
read out of the file, its start points and all — and the new one, over all 2,538
prefixes of the 600 names. They must agree wherever the old answer survives, find
nothing wherever it did not, and no word may match two rows. Then every one of those
words, plus 94 command lines covering every address form the surviving commands
take, goes through **both binaries** — the input's, built in the background while
the edits run, and the output — comparing exit status, stderr, the file afterwards
and anything left in the directory. Words the old table sent to `:stop` or
`:suspend` are left out, as the command sweep leaves those commands out.

### What went with the rows

- **26 `CMD_` tests** of commands that no longer exist: `:wincmd`'s address type, the
  filename-escaping exceptions for `:grep`, `:make` and `:terminal`, `:new`/`:split`/
  `:sview` in `do_exedit`, `:try`, the Vim9 `:final` and `:horizontal` quirks, and
  the index's two start points `CMD_Next` and `CMD_bang`.
- **The `ni` flag** in `do_one_cmd`, which exempted a stub from the range, bang,
  count and argument checks. No row can raise it.
- **The user-command test `(int)cmdidx < 0`**: nothing assigns a negative index.
- **The `py3` and `vim9` digit rules** in `find_ex_command`: no row left starts with
  `py` or `vim`.
- **Seven address types** only stub rows used — argument list, buffers, loaded
  buffers, two for tab pages, two for quickfix — 49 case labels, 35 whole arms, and
  the buffer-offset arithmetic behind them. The program refuses to delete an arm
  that the arm above it can fall into.
- **`:if`, and with it `ea.skip`.** `:if` was a stub row that `do_one_cmd`
  special-cased to raise `if_level`, which made later commands skipped. But `:if`
  takes the rest of its line, `if_level` is reset at the end of every `do_cmdline`,
  and nothing passes `DOCMD_REPEAT`, so no command could ever run with it raised.
  `ea.skip` was already constantly false, and its nineteen readers fold.

### The delta

A removed name gives **E492 "Not an editor command"** instead of E319, with the same
exit status, and the command sweep cannot see the text. Two things can see a
difference, and both were agreed before the program was written:

- **`:if`** was accepted silently (exit 0) and is an error now (exit 1).
- **`stub|cmd`** used to run `cmd` after the stub's error, because a stub row with
  `EX_TRLBAR` split its line at the bar; an unknown name takes the whole line.
  `:buffer|%s/a/X/|w` wrote the substitution before and writes nothing now.
  `:h|…` is the control: `:help`'s row never had `EX_TRLBAR`, and it comes out the
  same.

And every removed row leaves the command sweep, which dispatches the names in the
table — so the declared list is Phase 79's plus all 489, and the program requires
that list to be exactly the stub rows.

### What the dry runs caught

All five were in the checks or my arithmetic, not the edits: a `vim9` word check
that matched the string literal `"vim9"` (which is how the digit rules were found); a
lookup span counted as 31 lines that is 33; `cutil.delete_definition` returning a
pair, not the text; a "no `sizeof(\"` left" check that matched unrelated string
lengths elsewhere in the file; and `:h|…` expected to differ, because I assumed every
stub row split at the bar without reading `:help`'s flags.

Measured: 88,636 → **87,142 lines**, the binary 1,008,424 → 955,976 bytes.

## Phase 81 — one line, one command

An Ex line could hold several commands separated by `|` and end in a `"` comment.
Both exist for scripts — a vimrc, a sourced file, a function body — and this editor
reads none. Every command it runs was typed, came from `+cmd`, or came from a
mapping's right-hand side. So a line is one command now, and `|` and `"` are ordinary
argument characters. **A newline still ends a command**: that is the rule itself, and
the newline branch of `separate_nextcmd` is kept exactly as it was.

**The machinery was small and in one place.** `separate_nextcmd` split a bar-splitting
command's argument at `|`, `"` or a newline; `check_nextcmd`, `find_nextcmd`,
`ends_excmd` and `ends_excmd2` each knew the same three characters; and a handful of
callers knew them again — `:substitute`'s tail, the trailing-characters check in
`do_one_cmd`, `:a|text`, `:|` printing the line, and the whole-line `:" comment`
with the `starts_with_colon` flag that only existed to feed it.

**Decided before it was written:**

- `a|b` — the bar is argument text. A command without `EX_EXTRA` reports E488; one
  with it takes the bar. `:map Q A|b` now maps `Q` to `A|b`.
- `a " x` — the quote is argument text too, so `:set ts=3 " x` is an error and
  `:" x` is E492.
- `\|` means nothing special: the backslash stays, so `:map Q A\|b` maps to `A\|b`.
  CTRL-V handling is unchanged.

**`EX_NOTRLCOM` stays.** Its comment meaning is gone, but it still decides whether
trailing spaces are stripped, which is what lets a mapping end in a space.

### The delta

No behaviour case, terminal row or swept command uses a bar or a comment, so the
cumulative list is phase 80's, unchanged, and `whimdelta.sh` confirms it. What moves
is probed directly: 43 cases through q80's binary and this one, comparing exit
status, stderr and what was written. Fourteen differ, each declared with its reason;
29 controls must not — `:s/a\|b/…/` and `:g/a\|c/d` (a bar inside a pattern was
never a separator), `:normal! A|x`, `:map Q A"b` (a mapping never took a comment),
CTRL-V before a bar, and two commands separated by a real newline.

One expectation in the corpus was wrong on the first run, and not the edit: the
mapping cases assumed the cursor on line 1, and `-e -s` starts on the last line.

Measured: 87,142 → **87,107 lines**. A small cut by count — the point was the
rule, and the splitter was never large.

## Phase 82 — the system headers nothing needs, and every comment

`whim-vim.c` opened with the same 41 `#include`s as `slim-vim.c`, and eighty-one
phases had taken away most of what they were for — the directory walker, the locale,
the password file, `dlopen`, `setjmp`, the maths library, `utime`, `uname`. The
object leaves 80 symbols for musl to supply, and a header that provides none of them
is a dependency on the host that buys nothing.

**The set is computed, not listed.** A header's name says what it is for, not what
this file takes from it, and musl's headers include one another. So each `#include`
is deleted in turn and the compile must stay **silent** under the sweep's flags; gcc
15 compiles C23, where an undeclared function or an unknown type is an error, so
silence means nothing the header provided was used. 28 of 41 can go on their own, in
parallel. Together they do not build — some pairs each carry what the other declares
— so they are removed one at a time, keeping each removal only while the build stays
silent.

**From the bottom, and the first dry run is why.** Walked top down, it dropped
`<string.h>` and `<stdlib.h>`, whose declarations happen to arrive through headers
further down, and kept `<wchar.h>`. The general headers come first, so walking up
from the end drops the specific ones and keeps what everything else leans on.
`<iconv.h>` stays: no iconv function is called, but `iconv_t` is still named.

**The proof is the binary, byte for byte.** A header can define a function-like
macro that shadows a function — musl's `<ctype.h>` does — and losing one would change
code silently if the prototype still came from elsewhere. So the input and output are
both built with `SOURCE_DATE_EPOCH` pinned, from the same file name, and must be
identical. They are, 955,976 bytes, which makes "no delta" a measurement.

Removed, 23: `limits.h` `sys/types.h` `dirent.h` `sys/time.h` `pwd.h` `sys/file.h`
`strings.h` `setjmp.h` `locale.h` `float.h` `math.h` `inttypes.h` `stdbool.h`
`sys/select.h` `wchar.h` `utime.h` `langinfo.h` `sys/sysinfo.h` `sys/wait.h`
`stropts.h` `sys/utsname.h` `dlfcn.h` `sys/resource.h`. Left, 18: `stdio.h` `ctype.h`
`sys/stat.h` `stdlib.h` `unistd.h` `sys/param.h` `time.h` `signal.h` `string.h`
`errno.h` `stdint.h` `wctype.h` `stdarg.h` `stddef.h` `fcntl.h` `iconv.h`
`sys/ioctl.h` `termios.h`.

### Every comment

The same phase strips every comment: the former-file banners, the seven notes, and
the lines earlier whim phases wrote to explain themselves — 314 lines, and the blank
lines around the banners that would otherwise have doubled up. `whim-vim.c` carries
code and nothing else from here, and **no later phase writes a comment into it**
(rule 5); the reasoning lives in the phase programs, this file and the commit
messages. Comments are found by a scanner that knows string and character literals,
because `"pack/*/start/*"` and `"://"` are data. Comments never reach the binary —
nothing uses `__LINE__` — so the byte-for-byte check covers this cut too, and the
paragraphing is checked separately: no run of blank lines, and the counts of blank
lines after `{` and before `}` unchanged.

Measured: 87,107 → **86,614 lines**.

### `arrowcheck.py` retired

The pty check that the arrow keys still move the cursor ran in 46 phases, from 24
on, at about **20 seconds of wall time each** — for most phases more than the
phase's own work. It guarded against one accident: the mouse phase deleting
`nv_cmds[]` rows under a precomputed index, which `tools/nvidxcheck.py` now catches
structurally, in `phasecheck.sh`, in no measurable time. One accident does not buy
a pty session per phase for ever, so the call went from every phase program and the
tool was deleted. Phase 32's own check keeps its completion half.

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

**36% of `whim-vim`'s functions are never entered** — 750 of 2,065, holding
11,235 lines. Measured after Phase 67:

```
    258  win_split_ins              the window layout, reachable only via aucmd_prepbuf
    158  win_equal_rec
    136  eval_vars                  % and # expansion in an Ex line
    117  scroll_cursor_bot
    115  op_replace                 Visual-block r
    108  op_insert                  Visual-block I and A
    101  do_more_prompt
    100  handle_csi
     98  cursor_pos_info            g CTRL-G
     98  change_indent              Insert-mode CTRL-D and CTRL-T
     94  shift_block
     91  win_close
     91  file_pat_to_reg_pat
     89  nv_zet                     the z commands
     89  internal_format            wrapping at 'textwidth'
```

**Two entries were examined in this review and deliberately not cut**, which is
worth recording so the next pass does not re-litigate them.

**The `z` commands are kind 2.** `nv_zet` (177 lines), `nv_z_get_count` (54) and
`set_leftcol` (52, called from `nv_zet` alone) would free 283 lines — but not
`scroll_cursor_top`, `scroll_cursor_halfway` or `scroll_cursor_bot`, which keep
external callers in `update_topline()` and `scroll_redraw()` and so stay whatever
happens to `z`. What would go is view positioning (`zt`, `zz`, `zb`, `z<CR>`,
`z.`, `z-`), horizontal scrolling (`zh`, `zl`, `zH`, `zL`, `zs`, `ze`, which do
nothing unless `'wrap'` is off) and `zp`/`zP`/`zy`. **Kept**: `zz` centring the
current line has no replacement among CTRL-E/CTRL-Y, CTRL-D/CTRL-U, CTRL-F/CTRL-B
or H/M/L, and a never-entered `nv_zet` is a statement about the harness, which
presses no `z`.

**The window layout is not the kind-3 candidate it looks like.** 2,162 lines
across 21 functions — `win_split_ins` (538 by its own extent), `win_equal_rec`
(314), `win_close` (196), `last_status_rec` (149), the `frame_*` family — and
`win_split()`, `win_new_tabpage()` and `make_windows()` have **zero** mentions, so
nothing user-facing can split a window. But `win_split_ins()`'s caller is
`aucmd_prepbuf()`, which is called from `open_buffer()`, `buf_write()`,
`ins_redraw()` and `set_termname()` — all live. It is reachable and never taken,
not unreachable. Cutting it means proving the autocommand window can never be
created and folding those four callers: a phase, not a sweep.

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
  host — the 18 headers Phase 82 left, the 80 libc symbols still called, the locale and iconv
  layers, and whether any of it can be answered at compile time instead.
- **Optimisation**, last and deliberately: `-O0` is right for a tree rebuilt
  more often than it is run, and wrong for a binary shipped to a device.
