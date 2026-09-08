# GOAL.md — reduce vim to one translation unit

A prompt for a fresh agent. The input is a pristine vim tree cloned into
`upstream/` and stripped of its git metadata; see *Setting up*. The output is
`vim.c`, the `Makefile` and `LICENSE` at the repository root, and `upstream/` is
deleted.

Read all of it before starting. The ordering is the point: four phases exist
only to make the later ones safe. Two runs of this process have paid for every
trap recorded here, and both runs' corrections are folded in.

**Nothing this tree has lives outside these phases.** There is no list of
extras applied afterwards — that is what makes the end-of-pass comparison
against `.reference/` mean something.

## The nine rules that would have saved the most time

Everything below is detail. These are the ones that cost real work when they
were not known.

1. **A marker answers "did this happen at all"; the question is usually "did
   this happen every time".** This is Phase 5's whole difficulty, and getting it
   wrong twice produced two builds that compiled and ran and were wrong.
2. **Key on the warning *option*, never the warning text.**
   `-Wunused-function` and `-Wunused-variable` emit the same sentence.
   Confusing them deleted 500 lines and broke a symbol two hundred lines away.
3. **An expander must rescan its own output**, because the preprocessor does.
   Missing that left 282 undeclared symbols.
4. **Delete before converting.** A quarter of the macros were mentioned nowhere
   but their own definition.
5. **Removing a directive is a matching problem, not a text substitution.**
   Deleting an `#ifdef` and leaving its `#endif` closed an include guard three
   thousand lines early, and the error surfaced in an unrelated header.
6. **vim reads its own `argv[0]`.** A reference binary named `ref` is in
   restricted mode and fails every shell-out. Stage the binary under test as
   `vim`.
7. **The broad, boring sweep is the one that catches things.** The one
   segfault that reached a build was invisible to 67 hand-written behaviour
   cases and to the pty scenarios; the mechanical sweep over all 600 Ex command
   names found it.
8. **Do the irreversible part last, or make the pass idempotent.** Two scripts
   died halfway with their file moves already done. Keep a copy of the file
   before every pass; re-running from it is then the whole recovery procedure.
9. **An invariant nothing re-checks is not an invariant.** Bracing ran before
   macro expansion, expansion pasted in `for` headers of its own, and 1,558
   unbraced bodies sat in a file whose documentation said every body was
   braced — through two whole runs. The Phase 7 passes are idempotent and cost
   seconds: re-run all of them at the end and require every one to report zero.

## The target

One file, `vim.c`, that `gcc -O0` compiles into a working `vim`. No second
source file, no header, no generated file, no build script, no preprocessor
beyond `#include` of system headers.

The tree ends as `LICENSE`, `Makefile`, `vim.c`, `CLAUDE.md`, `GOAL.md`,
`.gitignore` and a `tools/` directory holding the harnesses and the passes that
did the work. Keep the tools in the repository, not in a scratchpad: a
scratchpad does not survive the session, and `CLAUDE.md` will end up naming
things that no longer exist.

**There is no rebranding.** The program, the binary, the single translation
unit, the banner, `$VIM`, `$VIMRUNTIME`, `~/.vimrc` and every string are vim,
exactly as upstream wrote them, and no other product name appears anywhere in
the tree. Whatever the checkout directory is called is not one of them. The
makefile rule is `vim: vim.c`.

There is no collision to worry about: upstream has no `vim.c`, and `VIMNAME` is
already `vim`, so the executable's name needs no change at all. `vim.h` and
`vim.c` coexist only between Phase 6 creating the merged file and the same phase
deleting the header it absorbed.

**Do not remove features.** No `:help`, no `:hardcopy`, no encodings, no
commands. The only edits before the single TU exists are the ones the process
below actually requires. Feature removal is a separate project afterwards.

## Ground rules

1. **Build the verification before the first change**, and prove it can fail.
2. **Write the parsing helpers once**, in Phase 0, and import them everywhere.
3. **Never parse C with a regex over the whole file.** Extract the construct by
   brace or paren matching, operate on that, write it back.
4. **One commit per step**, with prose: why, what was measured, how it was
   checked, what was deliberately left out.
5. **Write `CLAUDE.md` incrementally, from Phase 1 onward** — not once at the
   end. Record what a phase established and every trap it hit, while the reason
   is still in front of you. Its figures are measurements: re-measure them rather
   than adjusting them by reasoning, and say what was measured. Writing the
   sentence is what forces you to check the claim — several errors surfaced
   exactly that way, and two reached a commit message unverified when the step
   was skipped.
6. **Keep a running log while you work, and fold it into this file at the
   end.** One entry per phase: what was done, what it measured, what went wrong,
   and everything in this document that turned out to be wrong, missing or in
   the wrong order. The log is a working artifact, not a deliverable — when the
   run is over, its lessons belong here and the log itself is deleted. Record
   the dead ends: an approach that failed and why is worth more to the next
   revision than a clean summary of what worked.
7. **If a transformation cascades wrong, reset to the last good commit and
   replay.** Do not patch. A bad fold deletes code, the dead-code sweep then
   deletes its callers, and you will not find every site by hand. This was used
   twice and was cheap both times.
8. **Save a copy of the file before every pass.** The passes are pure functions
   of the previous text, so re-running from the copy after a fix is the entire
   recovery procedure. Phase 7 hit three compile failures and needed no revert.
9. **Do the irreversible part last.** A script that moves files and then writes
   should write first. Twice a pass raised after its moves and left a half-done
   tree that could not simply be re-run.
10. `make -j` throughout — the machine has 64 cores. Per-file passes over the 67
    translation units should run in parallel too.
11. **`upstream/` is input, and its `.git` goes before anything else.** That
    remote is never written to and the staging directory never reaches a
    commit; `.gitignore` names it, and the pass deletes it at the end. See
    *Setting up*.

## Verification tiers — pick the cheapest that applies

| the change is | the check is |
| --- | --- |
| pure formatting | **the binary is byte-identical** (`cmp`) |
| token-preserving (directives, macro expansion) | the **token stream** is identical |
| anything else | the full harness against the current baseline |

### Tier 1 needs three things arranged, not one

- **Nothing embedding `__LINE__`.** That is the assertions, and they go in
  Phase 0.
- **No `-g`.** DWARF records a line number for everything, so with debug info a
  blank line moves the binary although no token did.
- **`SOURCE_DATE_EPOCH`, and there are two values in play.** `refcheck.sh`
  rebuilds with `SOURCE_DATE_EPOCH=0` because that is what `.reference/vim` was
  built with, while `tools/build.sh` pins `1700000000` for comparing two of your
  own builds. Mixing them produces a difference at byte 745 that is the
  timestamp and nothing else.
- **`SOURCE_DATE_EPOCH`.** `version.c` embeds `__DATE__` and `__TIME__`, so any
  two builds differ. This looks like a choice between the version banner and the
  cheapest verification tier, and it is not: **gcc honours `SOURCE_DATE_EPOCH`
  for both macros**, so the verification build pins the timestamp and an
  ordinary build still records the real one. `HAVE_DATE_TIME` stays.

Put all three in one `build.sh`, and **make it clean first**: a verification
build uses different flags, and leaving its objects for the next ordinary `make`
to reuse produces a binary that is neither. Compile both sides **from the same
file name** or `__FILE__` differs.

### Tier 2 means tokens, and needs a tokeniser

`gcc -E -P` preserves horizontal whitespace and line structure, so a change that
only moves tokens shows up as a textual difference and is not one. Collapsing
whitespace is not enough either — `(int);` and `(int) ;` are the same two
tokens. Write a small C tokeniser and compare the lists. Two "failures" in the
second run were the comparator rather than the change, and one of those was a
character-constant pattern with a backslash too many, which split `'\t'` into
four tokens and made every diff after it meaningless.

**A token-neutral change can still be wrong.** Deleting all 19 `#undef`s left
the token stream identical for all 67 units *and* produced macro redefinition
warnings, which is undefined behaviour that happened to come out right. Check
the warnings, not only the tokens.

**`tools/verify.sh <baselines-dir>` is all of tier 3 in one command**, run
concurrently, in about 18 seconds. Use it at every phase boundary. Add
`--enums` around anything that could renumber an enumerator.

### Checks that pass while doing nothing

- **`objcopy -O binary --only-section=X f /dev/stdout` writes nothing and exits
  0.** Comparing two such streams reports every pair of binaries identical.
  Write to real files.
- **A "clean rebuild is byte-identical" check passes if the rebuild did not
  happen.** `make clean` had failed, so `make` rebuilt nothing and `cmp`
  compared a binary with itself. The rebuild took 0.021 s and that was the only
  visible sign. Check the *time*, or check the artifact was actually removed.
- **A script that printed a success message has not necessarily written
  anything.** Re-read the file, or grep for the new text.
- **`gcc` exits 0 with warnings.** A check that tests the exit status of the
  warning sweep passes always. The requirement is that it prints *nothing*.
  This was written into `verify.sh` wrong on the first attempt and found by
  making it fail on purpose — which is the rule, and it applies to every new
  check, not only to the behaviour harness.
- **Tier 1 and tier 2 cannot see readability.** They are blind to blank lines,
  indentation and paragraphing. A pass that changes those needs a count of them
  as its own check. See Phase 4.

## What parallelises, and what does not

The second run took hours, and **almost none of it was compute**. A full
verification — build, 67 behaviour cases, 600 Ex commands, five pty sessions, the
terminal table, the command-table canary and a zero-warning sweep — is
`tools/verify.sh`, and it takes **18 seconds**, eight of them the build. The
time went into writing passes and diagnosing the ones that were wrong.

That shapes what is worth parallelising.

**Worth it, and already done:**

- `tools/verify.sh` runs every harness concurrently and gives one verdict. It
  is proven to fail on a broken build, on a behaviour change, and on a blank
  line landing in the generated table.
- The pty harnesses spend their time in keystroke delays, not work, so their
  sessions run together: 14.6 s to 3.7 s, and 19.8 s to 1.6 s.
- Phase 4's passes are per-file; Phase 5's preprocessing of all 67 units in
  parallel takes 0.2 s.

**Not worth it, and here is why.** The transformation phases are a strict
serial chain: each one rewrites the single file the next one reads. Two agents
editing `vim.c` at once conflict, and no amount of concurrency changes that.
Nor is there useful fan-out *within* a phase — the passes are whole-file linear
scans measured in seconds.

**Where a second agent does earn its keep: adversarial review of a pass before
it runs.** Three faults cost this process a reset each, and all three were
*design* errors in a pass, invisible until verification caught the damage:

- the marker rule that tested presence when the question was "every time";
- the sweep that keyed on a warning's sentence rather than its option;
- the expander that did not rescan its own output.

None was a coding slip; each was a rule that looked right. Before running a new
pass over the whole file, hand its source to a fresh agent with one question:
*what input makes this wrong?* It is read-only, it is independent of the main
line, and it is aimed at exactly the failure mode that actually happens here.
The three above are now written down, so the question to ask about a *fourth*
pass is what else is of that shape.

Do not use a second agent to run a phase, to verify in the background while the
main line proceeds (rule 7 wants the reset to happen before anything builds on
top), or to write a harness unsupervised — a suite that cannot fail is the one
thing worse than no suite, and only the self-test rules that out.

## Setting up

**Nothing is rewound and no branch is created.** Earlier runs replayed the
whole process onto a branch rewound to a pristine commit. That is over: the
input comes from outside the repository, so the repository has no reason to give
up its history and every pass is an ordinary commit on the working branch.

### What this repository holds between passes

Four things, and they are the whole seed: `.gitignore`, `CLAUDE.md`, this file
and `tools/`. **`vim.c`, the `Makefile` and `LICENSE` are products** — the first
two are written by Phases 3 and 6, the third is copied from the clone — so a
checkout that has never run a pass has no editor in it, and that is the intended
state rather than a missing file.

`CLAUDE.md` describes the tree a pass produces. Before the first pass it reads
as a specification and afterwards as a description, and rule 5 is what keeps it
the latter: each phase edits the sentences its own work made wrong.

### The pass, start to finish

```sh
git clone --branch regexp-delimiter-atoms --depth 1 \
    https://github.com/arbace/vim upstream
rm -rf upstream/.git                       # immediately, see below
#   ... Phases 0-9 run inside upstream/ ...
#   ... vim.c, the Makefile and LICENSE move to the repository root ...
rm -rf upstream                            # nothing else of it is kept
```

`upstream/` is a **staging directory, not a checkout of anything**. It is
gitignored, so its 8,581 files cannot reach a commit, and it does not exist
between passes. The repository the work is committed to is the one it sits in.

**Drop `upstream/.git` before touching anything, and never touch that remote.**
`--depth 1` already means there is no history worth keeping, and deleting the
metadata makes it impossible to push to, fetch into, or re-point
`github.com/arbace/vim` by accident — that repository is read-only input.
Deleting it first rather than last is the whole safeguard; a `.git` that
survives until the end is a `.git` that can be used by mistake in between.

### Upstream moves, and following it is the point

**Measure the delta before starting, and do not assume it is zero.** The clone
is whatever upstream is now, and a pass exists partly to carry the tree forward
onto it. The measurement takes one command against the previous pass's input —
or, failing that, against what `version.c` says — and it decides whether this
is an ordinary pass or one that needs thought:

- **Confined to code this configuration does not compile** — `+eval`, the GUI,
  another platform, `runtime/`, `src/testdir/` — is the ordinary case. Phases 2
  and 5 delete it and the produced `vim.c` comes out unchanged apart from
  `version.c`'s patch table. Note the delta and carry on.
- **Reaching code this build does compile** is the case to slow down for. It is
  not a problem — it is the reason to run a pass at all — but it will move the
  behaviour baselines, and a moved baseline needs the same treatment as a
  deliberate change: establish what moved against the *previous* binary before
  re-recording, and say in the commit which upstream patch caused it.

At the time of writing the input is **9.2.1037**, the same patch level as the
previous pass's input, so the delta is nil and this is the most ordinary case
there is. The pass reproduced all four baselines byte for byte, and the finished
`vim.c` differed from the previous one by a single line — a stray blank line the
earlier pass had left before `init_mappings()`'s closing brace — while the
**binary came out byte-identical**, 2,208,088 bytes. That is the first time the
end-to-end check has had both halves available here, and it is what the whole
workflow is for. **Expect this paragraph to be stale** — re-measure rather than
trusting it, and update it in the same pass.

**Phase 1 updates the patch level in `CLAUDE.md`**, from `version.c` rather
than from memory. It is the one number in that file which changes for a reason
outside this repository.

### The end-to-end check this buys

`.reference/vim.c` is the previous pass's output. A pass is finished when the
new one **differs from it only by what upstream changed**, and for a `tiny`
build that is expected to be nothing at all. `tools/refcheck.sh` runs the
comparison and is the last act of producing `vim.c`; see *Done when*.

**Everything this tree has is in the phases**, which is what makes that check
mean anything. There is no list of extras to remember and re-apply afterwards:
the terminal-table reduction, the compiled-in vimrc and the `'lazyredraw'` fix
are Phase 1, where behaviour changes and where the baselines are recorded, and
`-static -s` is Phase 3, with the rest of the makefile. A bare run of Phases
0-9 reproduces this tree, not a plainer one.

**`.reference/` is produced, not required.** It is gitignored, so a checkout
that has never run a pass has none, and that is the ordinary starting state
rather than something missing. `refcheck.sh` reports "nothing compared" and
exits 0; Phase 1 records the baselines; the pass ends by writing `.reference/`
for the next one.

**The first pass proves less than every pass after it, and it is worth being
plain about which.** It still proves the tree is internally consistent — it
builds, `-Wall -Wextra` is silent, every canonicalisation pass is a no-op, no
enumerator moved, the command table regenerates byte for byte. What it cannot
prove is that the *editor* is the one a previous pass produced, because the
recordings it checks against are its own. From the second pass on it can, and
that is the strongest check in this document.

### The tools already exist

`tools/` is in this repository and stays there — the pass does not rebuild it.
Twenty-two passes and harnesses, proven across two full runs; the
specifications in Phase 0 are what to build from if they are ever lost, and
what to check them against if they are not. `create_cmdidxs.py` in particular
was made shape-agnostic precisely so it survives the merge.

The baselines in `.reference/baselines/` are the other thing that does not come
from `upstream/`, and the only thing in the repository that no commit can
reconstruct. They are recordings of the Phase 1 binary, and Phase 1 is the only
place behaviour changes, so a pass either reproduces them or has gone wrong.
Re-record only when Phase 1 itself is deliberately changed — and if this tree is
ever moved, `baselines/` is the one directory worth carrying over, because
everything else is `git archive` and an 8-second build.

If a phase goes wrong, `git reset --hard` to its last good commit and redo it —
that is rule 7, and it is cheap because every phase is one commit.

## Phase 0 — reference, tools, harness

**Do not write the tools again.** They are in `tools/` in this repository and
the pass does not touch them; the specifications below are what to build from
if they are ever lost, and what to check them against if they are not. Run them
from the repository root against paths inside `upstream/`.

**All of them, including the ones that look finished.** `dropsrc.py`,
`splice.py`, `merge.py`, `keepset.py`, `macros.py`, `cond.py`, `plant.py`,
`resolve.py`, `toenum.py`, `expand.py` and `reblank.py` cannot run against the
*finished* `vim.c` — there are no separate sources, no directives and no macros
left in it — and were once deleted for that reason. Every one of them is needed
by a pass, because a pass works on the tree before those things are gone. The
test is "does the process need it", not "does it run against `vim.c`".

- `./configure --with-features=tiny --disable-gui && make -j` (21 s). Keep this
  binary — **and name it `vim`**, see below. **Run make as `make -C upstream/src`,
  never after a `cd`**: the repository root has a makefile of its own whose
  default target is also `vim`, so a `cd` that does not stick rebuilds *that*
  and reports success while the tree under test is untouched. The harness
  self-test then reported zero differing cases for a binary that had never been
  rebuilt. It is the baseline for **Phase 1
  only**; Phase 1 changes behaviour on purpose, so the run's real baseline is
  re-recorded at the end of it.
- **`tools/cutil.py`, the shared library, with no side effects at import
  time.** A
  helper module whose top level reads `sys.argv` and rewrites the source made a
  pass silently do nothing; its "0 changed" was an import crash. Provide: blank
  literals (preserving offsets), blank *comments only* (a different thing —
  Phase 4 needs both), match braces, match parens, per-character nesting depth,
  split on a top-level operator, collapse whitespace by walking the *real*
  string, delete a function by name, iterate a whole-file pass in one linear
  scan.
- **`tools/behaviour.py`** — 60+ independent cases, each seeding a file, running one
  editing task through `-e -s`, writing an output file, and recording a missing
  output file as a distinct value so a crash cannot pass as a match. Cover
  **CTRL-A/CTRL-X over every `'nrformats'`**, autoindent, `'formatoptions'`,
  comment leaders, insert-mode CTRL-V/CTRL-W/backspace, multibyte motions and
  case changes, substitution flavours, operators, text objects, macros,
  undo/redo, registers, marks, sort, filters, `'fileformat'`/`'bomb'`/`'binary'`.
- **Prove the harness can fail.** Make `do_addsub()` return FAIL — CTRL-A a
  no-op — and confirm exactly the CTRL-A cases differ and nothing else. A suite
  that cannot fail is not evidence. This self-test earns its keep immediately:
  in the second run it reported 13 differing cases where only 11 were
  explicable, and the two extra were the argv[0] fault below.

### vim reads its own `argv[0]`, and a badly named binary is a different editor

`parse_command_name()` looks at the basename: a leading `r` is **restricted
mode**, in which every shell-out fails; `e` selects evim; `g` the GUI; and
`view`/`ex` prefixes change the mode again. A reference binary saved as `ref`
made `:%!sort` and `:r !echo` fail against a binary that was byte-identical to
one called `vim`.

Fix it at the root: **every harness copies the binary under test to a temp
directory as `vim` before running it**, so no caller can get this wrong.

### The Ex-command sweep

Dispatch every command name once, each from **its own scratch directory** —
`:mkvimrc`, `:mkexrc`, `:mksession`, `:mkview` and `:wviminfo` write into the
cwd, and a sweep run from the repository root commits two of those files by
accident and lies in both directions. Record what each command left behind.

Two things it has to be taught:

- **`:suspend` and `:stop` signal the process group** and stop the harness's own
  shell; exit 148 is 128 + SIGTSTP. Run each command with a session of its own.
- **Quit with `:qall!`, not `:q!`**, or the window-opening commands (`:new`,
  `:split`, `:tabnew`, `:vsplit`, the `:sb*` family) flip between exit 0 and 1
  between runs. Skip the commands that hand over the terminal — `:shell`,
  `:suspend`, `:stop`, `:terminal`, `:gui`, `:gvim`.

**Require three consecutive identical runs before accepting it as a baseline.**
A nondeterministic baseline is worse than none: it produces a phantom diff in a
later phase and costs a bisect.

### The rest of Phase 0

- A pty driver: `pty.fork()`, keystrokes with delays, strip ANSI, hard timeout.
  An error at startup leaves vim on a `Press ENTER` prompt and the read loop
  hangs. **Before fixing a pty harness, check that what it reports is not simply
  true** — a scenario that looked broken was `0Dworld`, which never enters
  insert mode, and the editor was right. A workaround was written for it and
  then reverted.
- A terminal-resolution check: what each `$TERM` resolves to and how many
  colours it gets. Phase 1 rewrites that machinery and this is what pins it.
- A canary: regenerate `ex_cmdidxs.h` and require it byte-identical. **Validate
  it against the checked-in file** — that is the strongest validation available
  and it caught two formatting errors in the generator immediately. Note that
  `command_count` is 600 while `grep -c 'EXCMD('` says 602: the two extra are
  the `# define EXCMD(...)` lines. Anchor the count at column 0.
- **Delete the `assert()` calls — there are eight, not four.** Four is the count
  in a *finished* file; the unpruned tree compiles eight, in `buffer.c`,
  `ex_cmds.c`, `highlight.c` (three), `linematch.c` (two) and `window.c`. About
  180 more live in files this configuration does not compile.
  **Find them from the objects, not the sources**, and anchor the pattern:
  `nm -u x.o | grep '^ *U __assert_fail$'`. A loose grep matches vim's own
  `in_assert_fails` global and gives the wrong answer, twice.
  `<assert.h>` goes too — `static_assert` is a C23 keyword.

## Phase 1 — freeze the configuration

Target: `tiny`, no GUI, no terminal library, **plus `+extra_search`**, nothing
else from `normal`.

- Make tiny and no-GUI the `configure.ac` defaults, so a bare `./configure`
  produces them. **The `--enable-gui` default is not the only GUI switch**:
  `test "${enable_gui-yes}"` runs *earlier* than the option is defaulted and
  turns on the X11 probe by itself. Both have to change.
- **Edit `configure.ac` and the generated `auto/configure` to say the same
  thing.** Editing the `.ac` alone does nothing, and regenerating with a newer
  autoconf than the tree was written for is not worth the churn on a file about
  to be deleted. `sh -n` the generated script afterwards.
- **`+extra_search` has no configure flag** — not in `configure.ac`, not in
  `--help`, and `--enable-search-extra` is silently ignored by autoconf.
  `CFLAGS=-DFEAT_SEARCH_EXTRA` gets two files in and then fails on an eval-layer
  symbol. It needs four source edits and no fewer, and the build names them one
  at a time in this order: `feature.h` ungates `FEAT_SEARCH_EXTRA`;
  `drawline.c` adds it to the `LINE_ATTR` guard; `match.c` wraps the two
  `pos_list` branches in `#ifdef FEAT_EVAL`; `cmdexpand.c` guards a call into
  `syntax.c`.
- Drop the terminal library: the `tinfo/ncurses/termlib/termcap/curses` search
  exists only to satisfy `tgetent()`, so skip it entirely and make the hard
  error conditional on `--with-tlib` having been given. Six defines fall out
  undefined by themselves. `term_set_winsize()` moves out of
  `#if defined(HAVE_TGETENT)` — it is the one link error, and it needs only
  `T_CWS` and the minimal `tgoto()` `term.c` already carries.
- **Built-in terminals: the table ends up with exactly these ten.** `ansi`,
  `vt100`, `xterm`, `xterm-256color`, `screen`, `screen-256color`, `tmux`,
  `tmux-256color`, `dumb`, `debug`.

  Six names are *added* — `screen`, `tmux`, the two `-256color` aliases and
  `vt100`. **`apply_builtin_tcap()` stops reading at `BT_EXTRA_KEYS`**, so the
  8-colour rows must go *above* that marker in `builtin_xterm[]`; appended at
  the end they are never applied and `TERM=xterm` reports an empty `t_Co` while
  `ansi` and `vt100`, whose tables have no marker, are fine. `screen` and `tmux` drive the xterm table, and **`vt100` needs no
  new table**: `builtin_vt320`'s own comment says it covers VT1x0 through
  VT3x0 and it already has the keys and `KS_CCO "8"`, so rename that table
  `builtin_vt100` and let `vt100` be the only name on it. `builtin_ansi` and
  `builtin_xterm` need the 8-colour capabilities terminfo used to supply.

  Six are *removed* — `vt320`, `vt52`, `iris-ansi`, `pcansi`, `win32`,
  `amiga` — with their tables, about 340 lines, and the `vim_is_iris()`
  special case in `find_builtin_term()`, which the dead-code sweep will report
  in Phase 8 if it is left. This build is Unix-only and none of the six
  describes a terminal anything reaches it through. **Every one of them must
  then resolve to the `xterm` fallback below, and `termcheck.py` records a row
  for each saying so** — a baseline that states the fallback is what would
  catch one creeping back in, and one that simply stopped mentioning them
  would not.
- **Default an unknown or unset `$TERM` to `xterm`, not `ansi`.**
  `builtin_ansi` has no key definitions, so arrow keys, Home, End and Delete
  arrive as literal Escape plus characters and corrupt the buffer while looking
  like an editor bug. Choose the 256-colour add-on from the name the user set,
  not the fallback — the unknown-terminal path reassigns `term`, and testing
  *that* gives `alacritty-256color` eight colours. Keep the diagnostic to one
  line and drop the two-second pause.
- `./configure` one last time; commit `config.h`, `osdef.h`, `pathdef.c` and the
  settings as ordinary checked-in text; delete configure, `configure.ac`,
  `config.h.in`, `config.mk.in`, `config.mk.dist`, `osdef.sh`, `osdef1.h.in`,
  `osdef2.h.in`, `pathdef.sh`, `link.sh`, `toolcheck`. `link.sh` only ever
  invoked the linker directly here, so the rule *becomes* the direct link.
- **Freezing breaks `clean` in three places, not one.** It names `osdef.h` and
  `pathdef.c`, which are checked-in sources now — that would delete the
  configuration on the next `make clean`. It also recurses into `po/` and
  `auto/wayland/`, which read paths the freeze removes. After moving any file
  from generated to checked-in, grep the makefile for its name.

### Compile the vimrc in — and fix `'lazyredraw'` first

The editor ships with no vimrc, so what a vimrc would have said is compiled in:
eighteen option defaults, four mappings, and one terminal capability dropped.

    nocompatible  autoindent  expandtab  history=9999  hlsearch
    keymodel=startsel  lazyredraw  nojoinspaces  regexpengine=1  ruler
    smartindent  scrolloff=1  shiftround  smarttab  softtabstop=4
    shiftwidth=4  tabstop=4  undolevels=9999  t_BE=

    map <Tab> %      map! <char-0xa7> <C-_>      nmap é u      nmap á <C-R>

- **`'lazyredraw'` needs a fix landed before it becomes a default**, or every
  `-e -s` run silently starts doing nothing. `redrawing()` and `messaging()`
  call `char_avail()` whenever `p_lz` is set, and under `-e -s` that reads
  ahead on stdin, where end of input means "quit": one `-c` that reports a
  change is enough to exit and abandon every `-c` after it, with status 0.
  Route both through a `typed_ahead()` that is `char_avail()` except in silent
  mode. Upstream has the same hole and never notices, because its `-u NONE`
  leaves `'lazyredraw'` off.

  It reproduces only with enough lines to make the substitution *report*, and
  piping an empty line instead of `/dev/null` hides it entirely:

  ```sh
  vim -u NONE -i NONE -e -s -c 'set lz' -c '%s/aaa/BBB/' -c 'wq' f.txt </dev/null
  ```

- **`P_VI_DEF` decides which half of a row's `{vi, vim}` default pair to
  edit.** With it, the vim half is unused and one edit covers both. Without it
  — `'history'`, `'ruler'`, `'compatible'` — set both, or the result depends on
  `'compatible'`, which is one of the things being changed. `'compatible'` also
  has an initialiser of its own, `p_cp`, because vim only clears it on finding
  a vimrc.
- **`t_BE` is a terminal capability, not an option default.** `optiondefs`
  already defaults it to `""`; `builtin_xterm[]` is what sets it, so drop its
  `KS_CBE` row and bracketed paste is never enabled.
- **The mappings go through `init_mappings()`**, upstream's own hook. The
  `struct initmap` it reads sits inside a `#if defined(MSWIN) || defined(MACOS_X)`
  guard; hoist it out. Plain `:map` is four modes **including select** —
  leaving `MODE_SELECT` out shows up as `nox` where `:map` prints a blank mode
  column. Write non-ASCII left-hand sides as universal character names
  (`"\u00a7"`), so the source stays pure ASCII as it is everywhere else.

**Prove the compiled defaults are the vimrc, not merely close to it.** Run the
binary from before this step with `-u <the vimrc>` against the one after with
`-u NONE`: all 67 behaviour cases, all five pty scenarios and `:set all` must
agree. Exactly one option legitimately differs — `'loadplugins'`, which
`-u NONE` sets and no default controls.

**The comparison binary needs the `'lazyredraw'` fix too.** Built without it and
run with a vimrc that sets `lz`, it hits the hole on eight of the 67 cases and
writes no file at all, and the diff then looks like eight default differences
that are nothing of the kind. Better still, check against the *recorded*
baseline rather than against a rebuilt binary: it is stronger evidence and it
needs no second build.

### Then, and only then, record the baselines

**Add behaviour cases for `+extra_search` and check which of them discriminate.**
`:set hlsearch` and `:set incsearch` succeed *without* the feature, because vim
keeps hidden definitions for options a build lacks; `:match` and `:nohlsearch`
go from exit 1 to exit 0 and are the real evidence.

**Record every baseline from the Phase 1 binary** — three identical runs each,
or it is not a baseline.

**If `.reference/baselines/` already exists, compare before you overwrite.** An
older set is the only evidence that this pass produced the same editor as the
last one, and re-recording over it destroys that evidence in the one moment it
could have been used. Diff the new recordings against the old first: all four
should be byte-identical, and if any is not, the cause is either something you
changed in Phase 1 on purpose or an upstream patch that reached code this
configuration compiles — name which, in the commit, before replacing anything.
If there is no older set, record and carry on; that is a first pass.

Note what the recordings encode: the ten
terminals with six fallback rows among them, and an editor with the vimrc
already in it, so `nocompatible` makes `u` multi-level and `softtabstop` makes
a Tab four spaces.

**Phase 1 is the last step that changes behaviour on purpose, and that is a
rule about the whole process, not a description of this one.** Everything after
it is required to leave the editor alone, which is what makes a recorded
baseline evidence rather than a memo. A behaviour change made later cannot be
checked against anything: the baseline has to be re-recorded from the binary
that made it, and it then agrees by construction. If something behavioural
turns out to be missing, come back to Phase 1 and redo from here — that is
rule 7, and it is cheaper than it sounds.

## Phase 2 — prune the tree

Keep `LICENSE`, `Makefile` and `src/`. Nothing else — not `runtime/`,
`src/testdir/`, the docs, `xxd`, `libvterm`, `po/`, the CI configuration or the
upstream dotfiles. There is no git metadata to keep: `upstream/.git` went
before any of this started.

**`LICENSE` comes from `upstream/`, and is the one file kept from it for its own
sake.** Clause II.1 requires Vim's licence to be included unmodified in a
modified Vim, and the file headers that carried the attribution go with the
comments in Phase 4. Copy it to the root alongside `vim.c` at the end of the
pass and keep it byte-identical to the clone's — never hand-edited, and never
carried forward from a previous pass, since the clone is where the authoritative
copy is.

**Measure the keep-set with `-MD` and use the `.d` files alone.** They record
every file the compiler opened, which is the question being asked.
**`tools/keepset.py` still advertises the union in its own docstring**, so call
`from_depfiles()` and ignore `from_make()` rather than running its `main()`. Do *not*
union them with make's expanded prerequisite list: `make -p` returns the whole
rule database, including rules for the GUI, perl, wayland and libvterm this
build never reaches — 441 entries against 254, and the extra 187 are junk. The
makefile's own needs are three named files (`Makefile`, `config.mk`,
`create_cmdidxs.py`), not a set to compute. And `xdiff/xdiff.h`, the classic
example of a prerequisite the compiler never opens, is in fact opened — by
`vim.h`, unconditionally, for `mmfile_t`.

**Note that `make` at the top level breaks before `make -C src` does**: the
top-level makefile `include`s `Filelist`, which the top-level prune deletes.
Measure from inside `src/` until the flatten.

Then delete the sources that **compile to nothing**: `nm --defined-only` on the
object comes back empty, so the file cannot be contributing to the link. 61 of
128 here — the whole eval layer, all nine `vim9*.c`, `syntax.c`, `quickfix.c`,
the spell and terminal code. This removes no feature; there is nothing there to
remove. It reached a fixpoint in one round.

**Removing a `.c` takes five edits, and the fifth is not in the makefile.** The
`SRC` list, the `OBJ` list, the `.pro` list, its build rule, its proto rule —
and the `#include` of its `.pro` in `proto.h`, which `dropsrc.py` does *not*
touch. **`proto.h` writes them `"clientserver.pro"`, not `"proto/clientserver.pro"`**
(the path came from `-Iproto`), so grepping for the latter finds nothing and
reports the job done. That last one is what bites: the
makefile edits all succeed and the build then fails in every remaining
translation unit at once with `fatal error: clientserver.pro: No such file or
directory`. Tell a build rule from a dependency-only rule by whether a
tab-indented recipe follows.

**All three lists are indented with one tab**, `SRC` as `\tfoo.c \` and the
other two as `\tobjects/foo.o \` and `\tproto/foo.pro \`. A pattern written
for two tabs on the latter pair removes only the `SRC` entries and says nothing;
the file is already deleted by then, so the build stops at *No rule to make
target 'clipboard.c'*. And a build rule may carry extra prerequisites —
`objects/clipboard.o: clipboard.c $(WAYLAND_SRC)` — so match the target, not the
whole line.

**Pruning forces more makefile work than "edit only where forced" suggests.**
Five things must go before `make` will run at all, and the first is nominally
Phase 3's:

- the hand-written dependency block — 176 dependency-only rules in this run,
  told from build rules by whether a tab-indented recipe follows — now naming
  headers that do not exist;
- `TOOLS = xxd/xxd$(EXEEXT)` and the xxd build rule, or the default target
  stops at *No rule to make target 'xxd/xxd.c'*;
- `include Make_all.mak` and `include testdir/Make_all.mak`, which carried only
  `TAGS_FILES` and the test name lists;
- `$(TERM_DEPS)` and `$(XDIFF_INCL)` on the `terminal.o` and `diff.o` rules;
- `$(MKDIR_P)`, which is `install-sh -d`, `install-sh` having existed only to
  create the one `objects/` directory.

**And one that will fork-bomb the machine if you leave it.** Thirteen rules end
`cd <dir>; $(MAKE) ...` — into `testdir/`, `libvterm/`, `auto/wayland/`,
`$(PODIR)` and `xxd/`. Once the prune deletes those directories the `cd` fails,
the `;` runs `$(MAKE)` **in the same directory on the same makefile**, and it
recurses. `clean` reaches two of them through its `testclean` prerequisite, so
`make clean` is enough: it reached 50,106 processes and a load average of 1,400
before it was killed, and `pkill -9 make` does not clear it — the survivors
respawn faster than they die, so kill the process group. Remove all thirteen
and empty `testclean` *before* running `make clean` even once.

**Then flatten.** Move everything from `src/` to the root and delete the
top-level makefile that existed only to recurse into it. Keep `proto/` as the
one subdirectory until Phase 6 absorbs it. Do this now: every tool written from
here on takes a path, and one directory level is one fewer thing for each of
them to be wrong about.

**Check who includes a file before moving it.** `xdiff/xdiff.h` was moved on
the assumption that `diff.c` was the consumer; `diff.c` had already been
deleted as an empty object, and the real include is in `vim.h`. The move had
already happened when the script raised — rule 9.

## Phase 3 — one Makefile, nothing generated

One small makefile, two targets, `vim` and `clean`. No dependency block, no
shell script, no `CPPFLAGS` or `LDLIBS`. 3,570 lines become about 24.

**Keep the object phase until Phase 6.** GOAL's older advice was to drop it here
on the grounds that compiling and linking separately gives the same binary. That
is true of the *finished* single file and false now: measured, one
`gcc -O0` invocation over the 67 units takes **13.4 s**, while per-file objects
with `make -j64` and a link take **1.1 s**. Phases 4 through 8 rebuild
constantly. Drop the object phase when there is one file to compile and nothing
left to parallelise. (The two do not in fact produce a byte-identical binary
either — they differ at byte 857, which is section ordering, not code.)

Give every object a dependency on every header, in one line. It is deliberately
coarse: a full rebuild is a second, and a rule that cannot be stale is worth
more than a precise one that can.

**Getting `-I` and `-D` off the compile line takes source edits.**

- `-DHAVE_CONFIG_H` is not a define to relocate — the block it guards has to be
  *unwrapped*, and that is where this phase goes wrong. See below.
- `-I` needs two edits: `proto.h` must name its 97 `.pro` includes by path, and
  `xdiff.h`'s `#include "../vim.h"` only ever resolved because `-Iproto` made
  `proto/../vim.h` mean this directory.
- **`-lm` is not needed at all** under musl, so there is nothing to move into
  `LDLIBS`. Another libc would want it back.

Build at **`-O0`**, and with no `-g`: this tree is rebuilt far more often than
the editor is used, and debug info destroys tier 1. `_FORTIFY_SOURCE` goes with
`-O2`, its checks needing sizes the optimiser computes.

**`LDFLAGS = -static -s`** is the whole of the standalone binary. gcc defaults
to PIE here, so the result is a *static-PIE*: `readelf -h` still says `DYN` and
ASLR still applies. Static costs 817 KB and `-s` takes 807 KB of it back, so
standalone lands within 10 KB of the dynamic unstripped build.

Two consequences worth knowing before they surprise you. **`ldd` is not the
check** — on a static-PIE it prints a musl line that looks like a dependency
and is not one; `readelf -l` for `INTERP` and `readelf -d` for `NEEDED` are,
and both must come back empty. And **`-s` breaks `nm`**, which Phase 8 needs to
show that `main()` is the only external symbol: build without it for that,
`make LDFLAGS=-static`, and `make CFLAGS=-g LDFLAGS=-static` for the DWARF
enumerator dump. The `.text` of either is identical to the shipped one.

This does not touch tier 1: two static builds of the same file name with
`SOURCE_DATE_EPOCH` pinned are byte-identical, and 50 inserted blank lines
still produce the same bytes.

Freeze the generated headers — `ex_cmdidxs.h`, `nv_cmdidxs.h` and the rest — as
checked-in sources; their generation rules go with the rest of the makefile.

### The trap: unwrapping a conditional is a matching problem

`#ifdef HAVE_CONFIG_H` spans **fifty lines** — the `sizeof(int)` check, the
feature-test macros, a Cygwin `fchdir` workaround and `UINT32_TYPEDEF`. Removing
only its opening line leaves the `#endif` to close `#ifndef VIM__H` instead,
three thousand lines early. `vim.h` then stops guarding itself, and because
`xdiff.h` includes `vim.h` back, half of `vim.h` is processed twice per
translation unit. What gcc reports is a **redeclared enumerator in
`termdefs.h`**, a file with no include guard of its own and no connection to any
of it.

Two things make that slow to diagnose, and both are worth knowing up front:

- **The `-H` include trace looks the same whether a guard works or not.** It
  lists a re-entered file at the next nesting level either way; what
  distinguishes them is whether anything *below* that file is listed too. Settle
  it with a four-line probe before reading the real trace.
- **Do not write a preprocessor to debug the preprocessor.** A
  directive-balance checker written on the spot reported a final depth of 220 on
  a balanced file. The compiler is the authority.

## Phase 4 — the cheap line-level normalisations

None of these needs to understand C, so do them now, per file, in parallel.

1. **Splice out backslash line continuations** (482). This is translation phase
   2, so it cannot change the token stream — including inside a `#define` body.
   The one thing that would make it unsafe is trailing whitespace between a
   backslash and its newline; check first that there is none.
2. **Expand tabs to spaces at the 8-column stops they were written for**
   (261,991). **Two** tabs are data rather than layout and become `\t`: the one
   in the `b:undo_ftplugin` command string in `trigger_undo_ftplugin()`, and one
   inside the default `'spellcapcheck'` pattern in `optiondefs.h`, where it sits
   in a **regexp character class** — expanding that one silently changes which
   characters the pattern matches, behind a feature that is switched off, where
   no test would catch it.
   **Finding them needs two different blankings**: a tab is data iff blanking
   *literals and comments* hides it while blanking *comments only* does not.
   One blanking reports twenty thousand false positives, every tab in every
   comment.
3. **Drop every comment** (39,906, taking 50,328 lines). Move the licence text
   to `LICENSE` — clause II.1 requires it in a modified vim, so this is required,
   not optional.

   **Do not use `gcc -fpreprocessed -dD -E -P` for this.** It works, and `-P`
   also throws away every blank line, so the paragraphing that separates
   functions goes with the comments.

   **And do not collapse a multi-line comment onto one line either**, though
   that is what the standard says. Deciding afterwards whether a now-empty line
   *had been* blank needs the two texts walked together, and a resync heuristic
   gets it wrong at scale — 26,476 blank lines to 3,884 in the second run, with
   both verification tiers passing, because neither can see a blank line.

   Replace each comment with **one space plus the newlines it spanned**. Line i
   of the output is then line i of the input, so a line that became empty held
   only a comment and a line that was blank stays blank, and the question never
   arises. That is equivalent to the standard's rule exactly when **no
   multi-line comment has code on both sides of it**; check, and refuse if any
   does. In this tree the count is **zero**, so the third run kept all 26,476
   blank lines with the token stream and the binary both unchanged.

   The single space matters as much as the newlines: blanking a comment to its
   full width instead leaves the indentation of what follows wrong, which the
   command-table canary catches immediately — its rows are written
   `  /* a */ 0,`.

### Blank lines are the one thing the verification cannot see

Tier 1 and tier 2 both passed the second run's comment removal, and both were
right: the binary was byte-identical and the token stream was unchanged. The
pass still lost most of the file's paragraphing, and recovering it afterwards
took two more passes and never got all of it back.

So: **count blank lines and function-boundary blank lines before and after, and
require them to survive.** With the pass written as above they survive exactly,
and this check takes one line. A line that held only a comment is dropped; a line
that was already blank is kept. The rule is easy to state and easy to get wrong,
because deciding "was this line blank before?" after a substitution that can
join lines needs the two texts walked together, not resynced by heuristic.

If it is lost anyway it can be recovered, and nearly completely, but only if
the recovery is done properly. Match each blank line by **the pair of lines it
sat between**, taken from the tree as it stood before the comments went — line
numbers are useless by then. Five things that rule has to get right:

- **Count, do not test presence.** A closing brace followed by a closing brace
  occurs with a blank between it *somewhere*, and inserting one at every
  occurrence doubles the file's blank-line count. Require the pair to be
  *usually* separated.
- **A comment-only line is not a blank line.** Counting it as a gap puts a blank
  wherever a comment used to be — 3,442 of them immediately after an opening
  brace, which is nobody's style.
- **Normalise the old copy the same way the current file was** before reading
  pairs off it: splice, expand tabs, strip comments, join parenthesised groups,
  one statement per line. A pair whose neighbours have since been rewritten
  matches nothing. That copy is never compiled, so it only has to be
  *comparable* — a comment stripper that preserves the line count exactly is
  fine here and would be wrong as a Phase 4 pass.
- **Step over the braces Phase 7 inserted.** A blank after a one-line `if` body
  now has that body's closing brace between it and its old neighbour. Let the
  match skip lines that are nothing but a brace, and put the blank before the
  second half of the pair. Worth more than any other single refinement.
- **Add the two rules that need no history**: a blank after every top-level
  closing brace, and one between a function's declarations and its first
  statement.

Then measure the ceiling rather than guessing at it. Of the old tree's blank
lines, ask how many have **both** neighbours still present in the new file, how
many have one, and how many have neither. Here it was 54 / 29 / 17 per cent:
the first group is fully recoverable and was, a single-line-anchor rule reaches
a tenth of the second, and the third sits in code that no longer exists. Expect
to land near nine tenths of the density of a build that never lost them.

## Phase 5 — resolve every conditional directive

**Token-level, and it must precede canonicalisation**, because `#if` groups
interleave with braces and make brace matching impossible until they are gone.
8,251 groups become 17, and a third of the tree goes with them.

Do not evaluate the conditions. **Plant a unique token in every branch of every
group, preprocess once, and keep the branches whose token comes out.** Only the
preprocessor knows:

- **Definedness is position-dependent.** An include guard like `VIM_H` is
  defined at the *end* of preprocessing, so a `-dM` dump makes it look constant
  and resolving `#ifndef VIM_H` to false deletes the contents of every header.
- **A macro can reach one translation unit and not another.** `TIOCGETP` and
  `CRMOD` arrive only in what was `os_unix.c`.

### Marking naively is wrong in two ways, and both compile and run

1. **A group reached in one unit and not in another looks resolvable.** Marking
   says "this branch's token came out", which is true of `#ifdef DO_INIT` in
   `globals.h` — from `main.c`, the only unit that reaches it. Resolving it
   hands all 66 other units the initialisers that belong to `main.c`, and 66 of
   67 units then differ.
   **The fix is a second marker planted immediately before the group.** That
   lets a unit distinguish "reached it and took no branch" from "never got
   here". Every unit that reaches a group votes; resolve only when they all
   agree.
2. **Presence is not enough; count the markers.** `ex_cmds.h` is read twice in
   `ex_docmd.c` with `DO_DECLARE_EXCMD` toggled, so a branch taken on the first
   pass and skipped on the second is *present* without being uniformly live.
   Removing that guard makes the second pass emit `enum CMD_index` and
   `cmd_addr_T` a second time. **A branch is uniformly live only when its marker
   appears exactly as often as the group was reached.**

Resolution is then outermost-first by construction: a group inside a branch
being dropped is never emitted, so it is never judged on its own.

**Leave whole-file include guards alone.** Within a unit the true branch is
taken exactly once, so the markers say "always live" — and removing the guard is
precisely what lets a header be read twice. `vim.h` includes `xdiff.h`, which
includes `vim.h` back. They go in the merge.

Verify with tier 2. That check caught both faults above, in a build that was
otherwise perfectly happy. **`gcc -E` is cheap** — all 67 units in parallel take
0.2 s — so there is no reason to economise on measurements here.

`#undef` goes the same way, but check the *warnings* as well as the tokens: some
undefine a macro never defined, and for the rest the macro simply stays defined
— unless it is redefined later, which is undefined behaviour that happens to
work. `TEXT_TO_INSERT`, defined twice in adjacent `case` arms, becomes two
names; `#undef EXCMD` has to stay until the X-macro does.

## Phase 6 — merge into one translation unit

Concatenate the `.c` files alphabetically with `main()`'s file last, embed the
headers where they were included, once each, and put the `proto/*.pro`
declarations in one block near the top.

**Keep a banner comment per former file** — `// ==================== ops.c ====================`
and `begin`/`end` markers for headers. They are the only comments in the file
and the only navigation in 180,000 lines, and they name the upstream file whose
comments still explain the code. 245 lines is a bargain.

**Hoist every system `#include` to lines 1..N.** This is only possible because
nothing in the file is read by a header. The feature-test macros
(`_XOPEN_SOURCE`, `_BSD_SOURCE`, `_SVID_SOURCE`, `_DEFAULT_SOURCE`,
`_REENTRANT`) are glibc-era and do nothing under musl: delete them and confirm
the preprocessed output is byte-identical.

**Three macros must be hoisted into a preamble as well.** `EXTERN` (which
`main.c` defined), `IN_OPTION_C` (which `option.c` did) and `USING_FLOAT_STUFF`
change what the headers produce. `EXTERN` is what makes `globals.h` define
rather than declare, which is exactly right when there is one unit. Miss
`IN_OPTION_C` and a handful of options are declared `extern` and never defined.

**Inline `ex_cmds.h` twice.** That is what it was for — one list expanded into
`enum CMD_index` and into `cmdnames[]`. Do not try to be clever: inlining it
literally twice turns one conditional whose answer differs *within* a unit into
two conditionals with one answer each.

**Then re-run the Phase 5 resolver on the merged file.** Every conditional Phase
5 had to leave alone — the guards, `EXTERN`/`DO_INIT`, `IN_OPTION_C`,
`DO_DECLARE_EXCMD` — exists precisely because units disagreed, and there is now
one unit. 22 groups in, 0 out, token-identical. Disable the include-guard
exception for this pass; nothing can be included twice any more.

**Find the file-local name collisions *before* merging**, with `nm` over the
per-file objects: any name defined in more than one object is a collision
waiting to happen, and after the merge there are no per-file objects to compare.
There were four — `compl_match_array` and `compl_match_arraysize` in
`cmdexpand.c` and `insexpand.c`, `sort_compare` in `ex_cmds.c` and `strings.c`,
and the macro `GAP` in `option.c` and `term.c`. Ignore gcc's `.0`/`.1` suffixed
names, which are function-local statics. **`nm` cannot see macros**, so the
fourth is found only by the compiler's redefinition warning.

Two more things this phase has to do deliberately:

- **`main()` is not last on its own** — `main.c` has functions after it. Move it,
  and make its closing brace the final line.
- **`pathdef.c` still describes the old build**, with `-I`, `-D`, `-g -O2` and
  `-lintl` in strings that `:version` prints. Make them name the command that is
  actually run.

**The cmdidxs canary will break here, which is the canary working.** In this
run it broke on a single stray blank line the merge left inside the block:
check that the *numbers* it generates match the ones in place, then `--update`
to restore the canonical form. It also picked its parser by file name, and
there is only one file now. Make it shape-agnostic
— try both parsers, take whichever finds at least 100 names — teach it that the
600 EXCMD rows appear **twice**, and have it check itself in place between the
`begin`/`end ex_cmdidxs.h` banners.

## Phase 7 — canonicalise, before anything reads C syntax

**Everything after this point needs to know where a condition, a body and a
statement begin and end.** Make it syntactic and the tools stop parsing C; leave
it implicit and every later pass is a fresh chance to get an extent wrong.

Do the passes in this order. Every one is tier 1; if `cmp` disagrees it was not
formatting. Save a copy before each (rule 8) — the second run hit three compile
failures here and needed no revert, because re-running from the copy after each
fix was the whole recovery.

1. Collapse runs of blank lines to one.
2. **Join every parenthesised group onto one line** — conditions, and argument
   lists of calls, declarations and definitions (11,258 lines joined). Count
   parens only; a line ending in `,` inside braces is a table row, not a wrapped
   argument list, and joining those puts a 600-entry table on one line.
3. **Split same-line bodies onto their own line** — `if (x) return;` becomes two
   lines. Only 40 sites, since vim's style already does this, but the pass is
   what lets the bracer assume "a head is a whole line ending in `)`". GOAL used
   to fold this into the bracing and it does not belong there.
4. **Brace every body** of `if`, `else`, `for`, `while` **and `do`** — 12,206.
   `-Wmisleading-indentation` then reports nothing and cannot.
5. **One statement per line** (1,040), splitting on top-level semicolons only.
6. **One declarator per declaration** (262), so the unused-variable sweep
   deletes a line instead of rewriting one. Be conservative: no top-level
   parenthesis, and every declarator after the type must look like one.
7. **Hoist comma operators out of `for` init clauses** — 15 clauses have one,
   and this run hoisted 12 — but **not when the init clause declares**, and not
   when the clause contains a call or a cast, which the previous pass also
   declined. Hoist every initialiser *but the last*, so `for (n1 = 0, n2 = 0; …)`
   becomes `n1 = 0;` and `for (n2 = 0; …)`. `for (int i = n - 1, j = m - 1; ...)` scopes `i` and
   `j` to the loop, and hoisting widens that to the enclosing block, which is a
   change and not a formatting one.

Leave increment clauses alone; they run on `continue` too.

### Traps

- **A following `else` belongs to the statement only when that statement is
  itself an `if`.** A `for` or `while` that happens to be an `if`'s body must
  not swallow it, or the closing brace lands on the far side of the `else` and
  the `else` body ends up inside the loop. An `else if` chain is one statement.
- **A `while` that terminates a `do` is not a head, and it does not always say
  so by ending in `;`.** 33 sites are written

      }
      while (cond)
          ;

  with the semicolon on its own line, which makes the `while` line
  character-for-character a valid loop head. **Identify them in a pass of their
  own, iterated to a fixpoint**, before bracing starts: identifying one changes
  the extent of an enclosing statement and can reveal another.
- **A do-while ends at its semicolon, which may be on a later line** than the
  `while`. Getting this wrong puts a brace between the two.
- **Count parens and braces on text with literals blanked.** This tree has
  `')'`, `'{'` and `'}'` as character constants.
- **A label's colon can be a character constant too.** Splitting `case ':':` on
  the first colon gives `case ':` and a run of "missing terminating '" errors.
  The same blanking rule applies to colons as to braces.
- **Blanked literals say where a literal is, not what is in it.** Collapsing
  whitespace by testing blanked text deletes literal contents — `'\n'` became
  `''`, 630 compile errors.
- **Whole-file passes must be one linear scan.** "Find one, fix it, rescan from
  the top" is O(n²) and does not finish on this file.
- A pass that declines a construct must put its input back **exactly** as it
  found it. One re-indented what it could not join and broke the cmdidxs canary.
- **`brace.py` prints its do-terminator count first**, so a fixpoint loop that
  reads the first number out of each pass's output never converges — it sees a
  constant 33 for ever. Read the *second* line for the count that matters.
- **Self-test every detector on an input whose answer you know**, before
  trusting a zero. Two written in this run reported "nothing to do" while being
  simply wrong: one took the paren depth *at* the `(` (0) instead of inside it
  (1) and so never found the `;` delimiting a `for` init clause; the other
  anchored on `^vim\.c:` while being handed an absolute path, and printed
  "0 remaining" with 37 warnings standing. Neither wrote anything, which is the
  only reason they were cheap.

## Phase 8 — internal linkage, then dead code to a fixpoint

**Before the macro work, not after** — every macro deleted here is one you do not
have to convert.

**Join the split declarations first.** 526 are written

```c
EXTERN char e_internal_error_lalloc_zero[]
        INIT(= "E341: Internal error: lalloc(0, )");
```

with balanced parentheses, so Phase 7's joining pass had no reason to touch
them. "Delete the line" then leaves half a declaration behind and the failure
surfaces as an unrelated undeclared symbol.

Make every symbol but `main()` `static`: the `proto.h` block says `static`
(2,869 of them), and **a *function* definition following a `static` declaration
inherits internal linkage**, so three thousand definitions need no edit.

- **Objects do not inherit.** A file-scope object definition with no storage
  class has external linkage whatever a prior `static` declaration said, and gcc
  rejects the pair with "non-static declaration follows static declaration".
  Twelve need the keyword twice.
- **One prototype must stay non-static.** `mch_rename` is a function-like macro
  for `rename`, so `static int mch_rename(...)` declares libc's `rename` static.
  Any prototype whose name is a macro defined earlier in the file is a
  declaration of the expansion, not of itself.
- **Two prototypes carry their attribute on a *continuation* line.** That line
  ends in `;`, so a pass that inserts `static` before "the line ending in `;`"
  produces `static ATTRIBUTE_FORMAT_PRINTF(3, 0);`. Put the keyword at the
  start of the declaration.
- **`EXTERN` is what makes the globals external, and it has to become
  `static`.** Do it textually: expanding it as a macro pads every one of the
  1,055 sites with a space on each side and leaves ` static  int p_ai;`.
  `PLURAL_MSG` is the same shape — it emits a bare `char var[]`, which leaves
  two error strings external.
- **`nm` the *object*, not the linked binary.** A static musl binary defines
  1,400-odd symbols of its own and buries the answer; `gcc -c` then
  `nm --extern-only --defined-only` prints exactly `main`.

`nm` is the check: `main` and the C runtime, nothing else.

Now `-Wall -Wextra` is a real dead-code detector. Sweep to a joint fixpoint,
alternating — it took eight rounds, because deleting a function orphans its
callees.

- Functions and variables: `gcc -c -O0 -Wall -Wextra`, not `-fsyntax-only`,
  which does not report `-Wunused-function`.
- **Key the sweep on the warning option, never the sentence.**
  `'X' defined but not used` is emitted for both functions and variables, and
  only `[-Wunused-function]` versus `[-Wunused-variable]` distinguishes them.
  Treating every hit as a function computes an extent starting at an unused
  error string and running to the closing brace of the next function below —
  **500 lines** — and the symptom is an unrelated symbol going undeclared two
  hundred lines away. Three rounds ran on top of the damage before it was
  noticed; recovery was rule 7.
- **`-Wunused-const-variable=` carries a trailing `=`**, so a pattern anchored
  on `variable]` silently misses every unused constant.
- **An unused *variable* is not one line.** 39 file-scope tables put their
  initialiser on the *next* line — `static char *(features[]) =` then a brace
  block, `base64_table` then its string — so deleting the reported line leaves
  the initialiser behind as a bare expression, and gcc says *expected identifier
  or '(' before string constant* somewhere unrelated. `deadsweep.py` now runs to
  the declaration's real end (depth zero and a terminating `;`); do not instead
  join every line ending in `=`, of which the finished file legitimately has
  161.
- Types: no flag exists. Compute **reachability, not reference counts** — a
  mention inside another type definition is not a use, and two types naming each
  other keep each other alive for ever. Roots are mentions outside *every* type
  definition. 65 of 344 were unreachable, including whole islands.
- Enumerators: no flag either, and **an enum's constants are referenced without
  its tag**, so they decide whether the definition is dead.

**Deleting an enumerator renumbers the ones after it**, and several enums index a
parallel table (`hl_flags[HLF_COUNT]`, `first_autopat[NUM_EVENTS]`). Pin a
survivor's value explicitly where a deletion would move it, then check with
DWARF: dump every enumerator and its `const_value` before and after and require
every surviving name to keep its value.

**Expect a warning or two to be a real finding rather than dead code.** Here:
`:winpos` parsed two numbers nothing reads any more, and since the parse has a
side effect the calls stay and only the variables go; and the swap-file age
check compared `st.st_mtime` against `time(NULL) - sinfo.uptime` with `uptime`
unsigned, making the subtraction unsigned and liable to wrap.

## Phase 9 — leave the preprocessor behind

Every `#define` goes. **Count them with `^[[:space:]]*#[[:space:]]*define`, never
`^#define`** — whitespace between `#` and the keyword is insignificant to C, and
plenty are written `# define`, invisible to a regex anchored at column 0 and to
every figure derived from it.

**Delete before converting.** 910 of 3,432 are mentioned nowhere but their own
definition — configuration flags whose conditionals Phase 5 already resolved.
Deleting those is free, provably token-neutral, and removes a quarter of the
work.

Preferred forms for the rest, in order:

- **Enumerator** — `enum { ... }`, or `enum : long { ... }` to keep width. A
  `static const int` will not do for most: it cannot appear in a case label, an
  array size, an enumerator initialiser or a static initialiser.
- **`static inline` function** for expression macros.
- **Expansion at the use site** when neither fits. **Expansion is safe in a way
  a function is not**: it cannot change the preprocessed token stream, whereas a
  function changes types and can drop a diagnostic silently.

Convert only macros with a **literal** integer or character body wholesale
(1,444 here). Those are already `int`, so the `sizeof` trap below cannot bite,
and they have no dependency on definition order.

### What the preprocessor can do that C cannot

- **Stringify.** `VIM_TOSTR(VIM_VERSION_MAJOR)` gives `"9"` only while
  `VIM_VERSION_MAJOR` is a macro; as an enumerator the *name* is stringified, so
  the version string becomes 35 characters and is `STRCPY`d into a 20-byte
  buffer. **The trap is not confined to the macros that stringify** — it reaches
  every name they can be handed, transitively. Find them by looking for the `#`
  operator, following macros that pass a parameter to a stringifier, and
  collecting the identifiers those are called with.
  The answer is a **character array built from the constants**:
  `{'0' + MAJOR, '.', '0' + MINOR, NUL}` keeps one source of truth and `sizeof`
  still gives the length. What it cannot do is literal concatenation, so places
  that pasted `"VIM - Vi IMproved " VIM_VERSION_MEDIUM` take the value through
  `%s`.
- **Paste tokens.** `DEFINE_PUM_SETTER(feature)` defines three near-identical
  functions by pasting; write them out.
- **Rescan its own output.** **So must your expander.** A macro name that
  arrives as an *argument* is invisible until the enclosing expansion has been
  done: `INIT(= MAXLNUM)` expands to `= MAXLNUM`, and `MAXLNUM` only then
  becomes available. One pass plus deleting the definitions left **282
  undeclared symbols**. Keep the table after the `#define`s are gone and iterate
  to a fixpoint — eight rounds here.
- **Variadic macros are not expandable and must be handled by hand.**
  `LOG_TRN(fmt, ...)` has a `do { } while (0)` body -- a no-op debug hook -- and
  the expander deleted its `#define` while leaving three call sites, whose
  arguments then referred to variables that exist only inside the call. Delete
  the statements; the errors are *implicit declaration of function 'LOG_TRN'*
  and three undeclared names on one line.

### The other traps

- **An enumerator is an `int`, so `sizeof` on it is 4.** This is the one
  conversion that changes meaning while keeping the token stream identical, and
  it once broke every `:w`: `#define PATHSEP ((char_u)'/')` became an enum and
  eight `sizeof(PATHSEP)` sites silently became 4. Before converting, grep for
  `sizeof(NAME)` and for a cast wrapping the *whole* body; use
  `static const char_u` for those.
- **Enumerators collide where macros did not.** Identical macro redefinition is
  legal, so a header inlined twice defines 31 constants twice — an error as
  enumerators. And a macro may shadow an existing enumerator nothing references
  any more, which is legal for a macro and an error for an enumerator: the
  regexp engine's opcode `WHITE` shadowed the colour enum's `WHITE`.
- **159 macros are defined inside a struct body**, where a bare
  `enum { X = 1 };` declares nothing and gcc says so. Hoist them.
- **Converting a macro can produce new *type* warnings.** `TRUE` as `1`
  converted to any enum silently; as an enumerator of its own anonymous enum it
  does not, and three calls passing `TRUE` where a `getline_opt_T` was wanted
  had to name the value they meant.
- **Substitute all parameters simultaneously.** One at a time lets an argument's
  own text be rewritten by a later parameter — that corrupted `nv_cmds[]` and
  unbound `b`, `c` and `d`.
- **`_()` and `NGETTEXT` keep their names** as inline functions carrying
  `__attribute__((format_arg(1)))`, which is how glibc declares `gettext`.
  Without it `-Wformat-security` stops seeing through the call. **The check is
  that the warning set is unchanged**, not that it builds; and expect a few call
  sites that handed the macro a `char_u *` to need an explicit cast, which a
  macro did silently and a function does not.
- An **X-macro** expanded twice — the 600-command table — becomes two explicit
  lists that **designated initialisers** keep aligned: `[CMD_append] = {...}`
  puts each row at its own enumerator, which is stronger than the macro's
  guarantee of equal *order*. Add a `static_assert` on the row count.
- Two enumerators may be impossible to remove: the last constant of an enum whose
  *type* is still a live struct field. C has no empty enum. Say so and stop.

### Finish

**Unwrap the `do { ... } while (0)` wrappers that expansion leaves behind** —
1,767 of them on 627 lines. Macro bodies were written that way so they would
swallow a semicolon, and there are no macros.

**Brace matching, not a regex**, and the reason is not the one usually given: by
this point Phase 7 has put every wrapper on a single line, so greedy-versus-
non-greedy is not the problem. The problem is that 18 lines carry *two*
wrappers, one nested in the other, and the spelling varies between `while (0);`
and `while (0) ;`. Find `do {`, match the brace, require `while (0)` and a
semicolon after it, and repeat until the line has none left — that handles
nesting innermost-outward for free. An anchored pattern gets the other 609 and
fails silently on these.

Check first that no body holds a `break` or `continue`, which would bind to a
different loop once the wrapper is gone. Refuse rather than guess; none did
here.

**Split the result on top-level semicolons.** Phase 7 canonicalised before
Phase 9 expanded, so a wrapper's body has several statements on one line; the
unwrapping restores the one-statement-per-line invariant as a side effect, and
took the file from 253 multi-statement lines to 16.

**Then re-run every Phase 7 pass until each is a no-op, and treat anything less
as unfinished.** This rule was already here, phrased as "re-run the joining and
splitting passes", and both runs read it as the two it names. It is all of
them. What the narrow reading missed: expansion pastes in `for` *headers* of
its own — the `FOR_ALL_*` loop macros become `for (...) for (...) if (...) { }`
on one line — leaving 1,558 bodies not on a line of their own and 1,575 not
braced, in a file whose documentation claimed every body was a brace block.
They survived two complete runs, because a fact nothing re-checks is not an
invariant. The passes are idempotent and cost seconds; the check is that
`splitheads.py`, `brace.py`, `joinparens.py`, `onestmt.py`, `onedecl.py`,
`untab.py` and `undowhile.py` all report zero, and `onestmt.py` needs iterating
— it splits one label off a `case A: case B: case C:` line per pass.

Re-canonicalising is free to verify: it changes no tokens' meaning, so `.text`,
`.rodata` and `.data` all come out byte-identical, and here the whole binary
did.

**This is the one step in Phase 9 that tier 1 does not cover.** At `-O0` the
never-taken `while (0)` test is a real branch and code disappears. What must not
change is *data*, so compare `.rodata` and `.data`, written to real files.
**Expect the shape of the answer, not the numbers**: one run measured a 64-byte
`.text` shrink with 337 words moving in `.rodata`, and the next measured
`.rodata` byte-identical, unchanged section sizes and addresses, and `.data`
differing in 876 pointers every one of which moved by exactly −12.

**Do not expect `.rodata` byte-identical — compare its *strings*.** A previous
run's did come out identical and the rule was written down as if that were a
law; it is not. A switch jump table lives in `.rodata` and its entries are
relative offsets into `.text`, so every table after removed code moves: 337
four-byte words here, by −16, −32 or −64 depending on how much was removed
before each. `strings` over the two sections is the check that means something,
and it must come back identical. `.data` differs only in pointers, each moved
by one of those same amounts.

**Prefer a name to an expansion, and check the balance at the end.** The
instruction is to leave the preprocessor behind, not to leave *naming* behind:
an object-like macro should become an enumerator or a `static const`, and a
function-like one a `static inline` function, before expansion is considered.
Expansion is the fallback for what neither can express — and it is a one-way
door, because 18,186 expansions cannot be read back into 1,022 names. Both runs
drifted toward it: the second converted **two** macros to inline functions
where the first had converted many, and the difference is not in what C allows
but in how early expansion was reached for. Count the outcomes at the end of
Phase 9 and justify the expansion column, rather than discovering its size
later.

Then a **zero warning baseline** under `-Wall -Wextra`, so the sweep is a
boolean and not a number to remember. Make deliberate fall-throughs say
`__attribute__((fallthrough))` — a hint that changes no code — and **place them
using gcc's own `note: here`**, which names the label. Two simpler rules both
fail: inserting after the statement gcc points at can land between an `if` body
and its `else`, and scanning forward for the next `case` puts it inside a nested
`switch` when the fall-through crosses one.

### Tidy what the process itself leaves behind

Three things nothing else removes, all of them cheap and all of them missed
once:

- **Empty banner pairs.** Merging inlines each header where it was included, so
  a header whose whole content was conditional leaves a `begin`/`end` pair
  around nothing. Six survived here — `protodef.h`, `feature.h`, `beval.h`,
  `alloc.h`, `linematch.pro`, `os_unixx.h` — for two runs. Drop the pair and
  the blank line inside it, then collapse the blanks the removal joins.
- **Blank lines an opening brace now precedes.** A dead branch removed from the
  top of a block leaves its blank behind; upstream has 29 in the whole tree.
- **The `.gitignore`.** It is upstream's, and after Phase 2 all but two of its
  91 entries name paths that no longer exist. What is left to ignore is the
  binary, the frozen reference and the exported transcript.

## Done when

- `make clean && make` produces `vim` from `vim.c` alone, in about 8 s;
- `behaviour.py`, the Ex-command sweep, the pty session and the terminal table are
  identical to the Phase 1 baseline;
- `-Wall -Wextra` is silent — reports *nothing at all*;
- the only directives are the system `#include`s at the top of the file;
- `main()` is last, its closing brace the final line, and `nm` shows no other
  global — on a build made without `-s`, since the shipped one is stripped;
- no `do { ... } while (0)` remains;
- **every Phase 7 pass reports zero**, run one last time in any order;
- **the paragraphing survived**: a blank line after essentially every function's
  closing brace, and a blank-line count in the same order as the input's;
- `upstream/` is deleted, and `git status` shows nothing untracked from it;
- `CLAUDE.md` describes the tree as it now is, patch level included, and every
  number in it was re-measured rather than reasoned about;
- and the check that subsumes most of the above, **run automatically as the
  last act of producing `vim.c`**:

```sh
tools/refcheck.sh          # brief report against .reference/, if there is one
```

`.reference/vim.c` *is* the previous pass's output, so a new one should differ
from it only by what upstream changed — nothing at all, when the delta was
confined to code this configuration does not compile, and otherwise a diff you
can name the upstream patch for. **A difference is a result, not a failure**:
report it with what caused it rather than reaching for `--force` or
re-recording over it. The tool reports the
source, the binary (tier 1, same file name, pinned epoch), the documents and
whether baselines are there, and exits non-zero on any difference in the first
two.

**A missing `.reference/` is the ordinary starting state.** It is gitignored and
produced, so a checkout that has never run a pass has none; `refcheck.sh`
reports "nothing compared" and exits 0, and the rest of the verification is
unchanged. Never skip `verify.sh` because `refcheck.sh` was clean — one compares
against the last pass, the other against recorded behaviour, and a pass that
reproduced last time's mistake exactly would satisfy the first.

Then fold the run's log into this file and delete it, and write `.reference/` —
`vim.c`, the binary built with `SOURCE_DATE_EPOCH=0`, the documents and
`baselines/` — so the next pass has this one to compare against. That last step
is what turns a self-certifying first pass into a checkable second one, so it is
not optional even though nothing fails without it.
