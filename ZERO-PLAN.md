# ZERO-PLAN.md — how zero-vim loses the filesystem, the streams and its own `main()`

`ZERO-GOAL.md` is the charter and has two phases in it. This is the plan for the
next eleven: **the editor stops being something you pipe text through and becomes
something you type at, on a screen, and nothing else.** It was written without
touching a single pipeline file, tool or phase program — every number below was
measured in this worktree and in a scratch directory (`/tmp/zpty`, `/tmp/zfs`; see
the appendix), against the committed `zero-vim.c`, which is `whim-vim.c` byte for
byte and builds with zero's phase-1 line into 869,512 bytes and 79 undefined
symbols.

**The fixed point.** `whim-vim.c` goes in. What comes out has no way to read or
write a file, no stdin to take text from, no stdout to give it back on, no Ex
mode, no silent mode, and no opinion about whether it is talking to a terminal. It
still draws a screen and still edits text.

## Summary

| | today | after the eleven phases |
| --- | --- | --- |
| lines of `zero-vim.c` | 86,614 | **≈ 80,300** (−5,636 measured by reachability, −≈700 estimated from folds) |
| functions | 1,874 | **1,719** (−155, measured) |
| undefined symbols (`nm -u`) | 79 | **≈ 60** (measured by simulation) |
| binary | 869,512 bytes | not estimated |
| what argv accepts | `+cmd`, `-T`, `-e`, `-E`, `-s`, `-v`, `-`, `--`, `--ttyfail`, one file | **`+{command}` and `-T {term}`** |
| how it is tested | 67 file-based cases, 111 Ex commands by exit status, 5 pty scenarios | **102 keystroke cases, 111 Ex commands by the message they print, 27 invocations, 5 pty scenarios** |
| what a test run costs | 1.2 s (file) + 20 s (pty) | **0.53 s** for 102 cases (measured on a patched binary; 6.4 s until the tty warnings go) |

**This table is the forecast it was written as, and the pipeline is forty-six phases
past it.** What actually happened is in `ZERO-GOAL.md`, one *What zero-vim is after
phase N* block per phase; the current one reads 78,666 lines, 1,734 functions, 14
undefined symbols and a 760,424-byte binary, and argv is `+{command}` alone. §4 below is
where this document says which of its own rows landed and which were wrong.

**The harness is the hard part and it is solved.** Not with a pty: with a
keystroke file on stdin, the escape-sequence stream on stdout, and a screen
rebuilt from that stream. 102 cases, **eight consecutive runs byte-identical
including the sha256 of the byte stream**. Of the six deliberate breaks it was
tested against, four move exactly 11, 2, 1 and 1 case of 102, and two — a deleted
`nv_cmds[]` row and a changed default — move 100, which is itself a property to
declare.

## 1. The decisions this plan is built on

These came from the user and are not open questions. Each is recorded with what it
costs, because several of them are the reason a phase exists.

1. **No load path.** Text does not come in on stdin; `vim -` and `EDIT_STDIN` go
   with the file argument. Nothing outside the process can put text in the buffer.
2. **No save path.** Text does not go out — no stdout dump, no `:w` anywhere, and
   "not even `editor.c` will have save/load". The embedding host owns both.
3. **No streaming Ex.** With neither stream there is nothing for `-e`, `-E`, `-s`,
   Ex mode (`Q`, `gQ`, `do_exmode`) or silent mode to do. `zero-vim` is "just a
   visual editor accepting input and emitting screen output through terminal
   connection".
4. **Testing is through that connection only** — keystrokes in, screen out. §2.
5. **`:q` always quits**, and `ZZ` becomes `ZQ`: the protection that says "no write
   since last change" has no remedy left to offer.
6. **The buffer keeps no file name.** The window will later be a view over an
   edn-like tree that simulates lines; that is not this plan.
7. **Do not ask whether stdin or stdout is a terminal.** The check goes entirely —
   not `--ttyfail`'s refusal made default, but no check at all.
8. **`+{command}` and `'paste'` survive every phase**, as harness infrastructure.
   No phase may retire either; a phase that would (a command-line cut, an options
   tidy that drops rows whose readers went) must exempt them and say so.
9. **argv accepts `+{command}` and nothing else** — **reversed by the user on
   2026-09-19**, and the decision it replaces is kept here because a reversed
   decision is worth more than an absent one: it read *"argv accepts
   `+{command}` and `-T {term}`, and nothing else"*, `--` going too, since with
   no file argument it only means "treat the next `+cmd` as a file", which then
   errors. That half stands. What changed is `-T`: which terminal the core
   drives is the **host's** business by the same argument as decision 7, and a
   core that keeps a command-line option for it is keeping a program's facility
   inside a component. **The option buys nothing that `+{command}` — which
   decision 8 promises to keep for ever — does not already buy**, measured here
   on the r32 binary: `-T ansi` and `+set term=ansi` both answer `term=ansi`,
   `t_ti=`, `t_te=`, and `-T debug` and `+set term=debug` both answer
   `t_ti=[TI]`. **Two things it costs, measured in the same run and not hidden.**
   The fallback goes: `-T no-such-term-9x` resolves to `xterm` and runs, where
   `+set term=no-such-term-9x` is `E522: Not found in termcap` — arguably the
   better answer, a core that does not claim to be a terminal it is not, but the
   fallback's own code becomes dead. And a probe that wants a non-default
   terminal table **before the editor's first screen** cannot be written
   afterwards: `-T debug` writes `[24CWS80][TI][KS]…` from byte 0, where
   `+set term=debug` writes 111 bytes of xterm prologue first. The phase that
   removes it is not landed; `-T {term}` is what phases 5 to 32 left, and four
   existing checks type it, which costs nothing — a phase check runs only against
   the two binaries of its own phase. `.claude/briefs/zero-terminals.md` §6d and
   §10 are the survey the reversal came from.

## 2. The harness

### 2a. The pty is not the instrument, and here is why

`tools/ptyrun.py` and `tools/ptycheck.py` already drive a pty, and
`tools/ptycheck.py` says in its own comment what the problem is: *"The screen dump
itself is too timing-dependent to compare directly"* — so it records only the lines
that answer a `:set` query. That is not a behaviour harness; it is a spot check.
The pty adds four hazards that `CLAUDE.md` names — the Press-ENTER prompt that
swallows keys, the read loop that hangs for ever without a hard timeout, ANSI
escapes that have to be stripped before anything can be compared, and keystroke
timing that decides whether an Escape is an Escape or the start of a key code.

It also adds one that is not in `CLAUDE.md` and that this work measured: a case
whose command exits the editor (`:cquit`) races with the keystrokes still to be
typed, which the pty then **echoes onto a screen nothing is drawing any more**. One
run in four of a 111-command pty sweep recorded those echoes. The fix is to stop
typing when the child is gone, and the general lesson is that a pty harness has
state the editor does not control.

I built the pty harness anyway, because it was the obvious reading of the
constraint, and it worked: 92 cases, eight identical runs, 1.9 s. Then the
requirement changed to no-tty-check, which makes the simpler instrument possible,
and the pty corpus shrinks to the handful of things only a real terminal shows
(§2j). **The pty work is not wasted**: the screen emulator it needed is the same
one the stream harness uses, and the two instruments were compared against each
other (§2c).

### 2b. Keystroke file in, escape-sequence stream out

```
    keys        a file:      ":set paste\r" "ialpha\rbeta\x1b" ":set nopaste\r" "..."
    invocation  ./vim +cmd… < keys > stream 2> errors
    record      the screen, rebuilt from `stream`; plus exit status, stderr,
                the stream's length and sha256
```

There is no pty, no `select` loop, no settle time, no ANSI stripping and no
Press-ENTER hazard: a hit-enter prompt is simply what the screen says at that
point. The terminal is **80×24 by construction** — the window-size ioctl fails on a
pipe and the built-in fallback applies — and `$LINES`/`$COLUMNS` cannot override it
(whim's Phase 19 took that away).

Measured on the committed binary, `TERM=xterm`, stdin a file and stdout a file:
`ihello world<Esc>:q!<CR>` exits 0 and writes a 2,294-byte stream carrying the
typed text; three runs are byte-identical. The whole of it is 30 lines of Python
around `subprocess.run(..., start_new_session=True)`.

**Two things it must get right, both measured.**

* **A session of its own.** `:stop` and `:suspend` signal the process *group*
  with SIGTSTP. Without `start_new_session=True` the command sweep stopped the
  shell that ran it — exit 148, which looks like the harness dying at command 100.
  They are also on the sweep's skip list, as they are in the file-based sweep.
* **A timeout, and a recording for what hits it.** `vim -` in this harness reads
  the *keystroke file* as buffer text, then `close(0); dup(2)` and waits on stderr
  for keys that never come: measured, 30 s per invocation. An invocation that
  hangs is recorded as `TIMEOUT`, not treated as a crash.

### 2c. The screen, rebuilt from the stream

The record is not the byte stream (which is unreadable and moves whenever a redraw
is re-ordered) but the screen that stream produces. The editor emits a small set
of sequences under `xterm-256color`: CUP, CUU/CUD/CUF/CUB, EL, ED, IL, DL, ICH,
DCH, DECSTBM, SGR, private modes, CR, LF, BS, TAB, BEL. 180 lines of Python
replays them into a 24×80 matrix.

**One screen per redraw, from the stream alone.** The editor hides the cursor while
it draws and shows it when the screen is settled and it is about to wait for a key.
`\x1b[?25h` is therefore a step boundary *visible in the bytes*, and a record can
hold a screen per redraw without a pty and without timing:

```python
if params == '?25' and final == 'h':
    snap = (self.dump(), self.y, self.x, self.bells)
    if not self.snaps or self.snaps[-1][0] != snap[0]:
        self.snaps.append(snap)
```

That is what makes the messages recordable. With only the final screen, every row
of the command sweep read `msg : ~`, because the keys that quit the editor wipe the
message line; with per-redraw snapshots, `:write` leaves `E32: No file name` in
snapshot 4 and it stays in the record.

**A terminal is columns, not characters.** The first emulator counted characters,
and 2 of 88 cases disagreed with `pyte` — both CJK: `日` is two cells wide and a
combining mark is none. `unicodedata.east_asian_width` and `unicodedata.combining`
are enough, and are in the standard library:

```python
def cellwidth(ch):
    if unicodedata.combining(ch) or unicodedata.category(ch) in ('Mn', 'Me', 'Cf'):
        return 0
    return 2 if unicodedata.east_asian_width(ch) in ('W', 'F') else 1
```

**Cross-checked against a real emulator.** `pyte` 0.8.2 happens to be installed
here, so every case was rendered twice — once by the in-house emulator, once by
`pyte` — and after the width fix **88 of 88 screens and 88 of 88 cursor positions
agree**. `pyte` is not a dependency of the plan (it chokes on vim's private SGR
`\x1b[>4;2m` and has to be fed a filtered stream); it is the oracle the in-house
one was proved against, and the repository's tools stay standard-library-only.

**The two instruments agree on the outcome and not on the intermediate states.**
For all 92 cases of the pty corpus, **the final text area is identical** in pty and
stream mode. Only 66 of 92 *intermediate* screens match verbatim, and the reason is
not a bug: when input is already pending the editor skips redraws, so the stream
contains fewer screens than a pty session where every keystroke group is followed
by a pause. The insert-mode and listing cases are the ones that differ. **The
stream harness records what the editor draws when it has nothing left to read**,
which is the honest thing for it to record.

### 2d. How a case gets its text: `:set paste`

Nothing can load text, so a case types it — and typing is subject to the
compiled-in `'ai' 'si' 'et' 'sts=4' 'ts=4' 'sw=4'` and to the four compiled-in
mappings. `:set paste` turns off exactly that interference. Measured on the
committed binary: `O    indented`, `o<Tab>TAB`, `oplain` gives
`"    indented" / "    <Tab>TAB" / "    plain"` without it and
`"    indented" / "<Tab>TAB" / "plain"` with it.

So the shape of a case is:

```
    args = ['+set paste', '+set <whatever the case needs>']
    keys = [ 'i<seed text>\x1b', ':set nopaste\r', <the case's real editing>, '\x1b:q!\r' ]
```

and a case that is *about* `'ai'` or `'et'` simply does its typing after
`:set nopaste`. Both forms were measured: `+set paste` on the command line works in
this harness (`+{command}` runs before the first screen is drawn), and so does a
typed `:set paste\r`.

**`:set nopaste` restores everything, including from non-default values** —
measured, which matters because the five global save slots `p_ai_nopaste`,
`p_et_nopaste`, `p_sts_nopaste`, `p_tw_nopaste`, `p_wm_nopaste` (56420–56424) are
the shape `tools/orphanopts.py` warns about and the buffer-local
`b_p_*_nopaste` fields do the real work:

| | `ai` | `et` | `sts` | `tw` | `wm` | `sm` |
| --- | --- | --- | --- | --- | --- | --- |
| defaults | on | on | 4 | 0 | 0 | off |
| after `:set paste` | off | off | 0 | 0 | 0 | off |
| after `:set nopaste` | on | on | 4 | 0 | 0 | off |
| from `noai sts=0 tw=9`, after paste/nopaste | off | on | 0 | 9 | 0 | off |

`'paste'` also takes the mapping layer out of the way: `vgetorpeek`'s condition at
28207 excludes mapping in Insert and Command-line mode while it is on, so a seed
cannot be rewritten by `map! <char-0xa7> <C-_>`. That is a second reason the option
is harness infrastructure and survives every phase (decision 8), and the corpus has
a case (`map_in_paste`) that records exactly it.

### 2e. What is recorded

One file per case:

```
=== incr_hex   exit=0 bells=1 stream=2371B sha=dc2753fe11c84d69 snaps=7
--- stderr: Vim: Warning: Output is not to a terminal / Vim: Warning: Input is not …
--- snap 0 cursor=23,79 bells=0
<24 lines of screen, right-stripped>
--- snap 1 cursor=0,0 bells=0
…
```

* **the screen per redraw** — what the editor drew, in columns;
* **the cursor** — where it left the cursor, which the text does not show;
* **the bell count** — `\x07` is how the editor says a key did nothing, and a
  refusal that beeps is a recording rather than an absence;
* **exit status and stderr** — the process's own answer;
* **the stream's length and sha256** — a tripwire under the screen: it moves when
  the *drawing* changes even though the result does not. It is recorded because it
  is free; a phase that legitimately re-orders drawing declares it.

**One normalisation, and it is padded.** Undo reports how long ago a change was
made ("1 second ago", from `time()`), and that is the only nondeterminism measured
in the corpus. It is replaced by `<ago>` **padded to the width it replaced**,
because the screen is columns: a shorter token moved the ruler into a different
one, and three of eight runs disagreed until the padding went in.

A second normalisation is needed for the argv record and not for the corpus:
`mainerr()` prints the version banner, which carries `__DATE__`/`__TIME__`
("compiled Sep 17 2026 18:19:28"). Three runs of one binary agree; a rebuild would
not. The record scrubs `compiled <date> <time>`.

### 2f. Determinism, measured

| | runs | result |
| --- | --- | --- |
| 92-case pty corpus | 8 | identical |
| 92-case pty corpus, all 92 at once under eight concurrent `gcc` | 2 | identical, and identical to the sequential runs |
| 102-case stream corpus | 8 (92 cases) + 3 (102 cases) | identical, **including the sha256 of every byte stream** |
| 111-command stream sweep | 4 | identical |
| 27-invocation argv record | 3 | identical |

Wall times: 102 cases in **6.4 s** against the committed binary, and **0.53 s**
against a binary with the tty warnings and their `ui_delay(2005)` removed (the
phase-2 shape — §3, P2). The sweep is 6.3 s, the argv record 5.0 s (of which 5.0 s
is the one `TIMEOUT`). The pty corpus was 1.9 s.

### 2g. Sensitivity, measured — six deliberate breaks

A corpus that cannot fail is not evidence (`CLAUDE.md`). Six patched copies of
`zero-vim.c` were built in `/tmp` and run through the stream corpus:

| break | what it patches | cases that move (of 102) |
| --- | --- | --- |
| `do_addsub` returns `FAIL` — `CLAUDE.md`'s canonical break | one line | **11**: the ten CTRL-A/CTRL-X cases and `mb_incr`, and nothing else |
| `CTRL-G` prints nothing (`fileinfo()` call removed) | one line | **1**: `ctrl_g`. **The file-based harness could not see this at all** — no file was written differently |
| `check_changed()` returns `FALSE` (planned phase P10) | one line | **2**: `quit_modified` and `cmd_edit` (`:edit` answered E37 too); and 6 of 111 sweep rows — `edit enew ex quit view visual`, E37 → E32 or success. **Built as zero phase 11 and it is 1 and 1**: five of the six rows went with `:edit` at phase 8 and `cmd_edit` with them, and `quit` changes message rather than ceasing to exist |
| `ZZ` runs `q!` instead of `x` (planned phase P10) | one line | **1**: `zz_key` |
| one `nv_cmds[]` row deleted under the precomputed index — the real twelve-phase arrow-key bug | one line | **100**, several with a non-zero exit: the editor cannot even quit. The two that do *not* move are `ctrl_c_clean` and `ctrl_c_changed`, which exit before a key is looked up |
| `'ruler'` default off | one row | **100**, each by the same single line, and the same two exceptions |

The first four are the shape a phase check wants: a small, named set — and the
two-case answer for `check_changed()` is the corpus being more exact than the
author, who expected one. The last two say the corpus is *maximally* sensitive to
anything that changes every screen, which is a property to declare rather than to
fix (§5, decision 3).

### 2h. The corpus: 102 cases

`tools/behaviour.py`'s 67 cases are the model. Of those:

* **50 translate directly** — the CTRL-A/CTRL-X family over every `'nrformats'`,
  autoindent and formatting, insert-mode CTRL-V/CTRL-W/backspace, multibyte
  motions and case changes, substitution flavours, operators and text objects,
  macros, undo/redo, registers, marks, `:move`/`:copy`, `:normal`, and the four
  `+extra_search` cases. The seed is typed under `'paste'` instead of being loaded
  from a file, and the assertion is the screen instead of the written file.
* **7 become "the feature is gone" witnesses** — `retab_gone`, `sort_gone`,
  `filter_gone`, `read_cmd_gone`, `put_expr_gone`, `ff_gone`, `bomb_gone`. whim
  already removed the commands and the options; what the case records now is the
  refusal message, which is more than the file harness could see (it saw only a
  non-zero exit).
* **3 cannot survive at all** — the three that only existed to check what was
  *written*: `'fileformat'`, `'bomb'` and `'binary'` change bytes on the way to a
  file, and there is no file. Two of them remain as option witnesses above; what is
  genuinely lost is any coverage of write-time transformation, and nothing replaces
  it because nothing performs it.
* **7 gain a companion** — `ins_arrows`, `nav_arrows`, `nav_home_end`, `key_Q`,
  `key_gQ`, `map_tab_percent`, `map_e_acute_undo`: keys that were untestable
  without a terminal.

Then 35 cases exist only because there is a screen: `startup` (the empty buffer,
the `~` filler and the ruler), `ruler_move`, `showmode_ins` (`-- INSERT --`),
`term_report`, `scroll_ctrl_f`, `scroll_zz`, `ctrl_g`, `ctrl_g_count`,
`visual_show`, `set_listing`, `hit_enter` (the Press-ENTER prompt as a *recording*
rather than a hazard), `unknown_cmd`, `search_count`, `search_wrap`, `reg_list`,
`mark_list`, `map_list`, `map_in_paste`, `undo_U`, `percent_match`,
`ctrl_c_clean`, `ctrl_c_changed`, and one per feature a phase removes —
`quit_modified`, `zz_key`, `cmd_write`, `cmd_read`, `cmd_edit`, `cmd_file`,
`key_gf`, `reg_percent`. **A phase whose delta no case can see is a phase with no
check**, so each planned removal has a case before the phase is written.

### 2i. The Ex-command sweep survives, and gets stronger

The file-based sweep recorded `exit=`, the files left in the cwd, and stderr. None
of the three exists here. What is left is what the editor **says**, which the
per-redraw snapshots make recordable. 111 commands, each typed at `:` after a
three-line seed, in a session of its own:

```
=== write          exit=0   bells=0 snaps=6
    text: alpha | beta | gamma
    msgs: … ;; E32: No file name … ;; :q!
=== quit           exit=0   …  msgs: … ;; E37: No write since last change (add ! to override)
=== file           exit=0   …  msgs: … ;; "[No Name]" [Modified] 3 lines --100%--
=== highlight      exit=1   …  msgs: … ;; -- More --
=== cquit          exit=1   …
```

That is a *message-level* record where the old one was an exit status: retiring
`:write` moves `E32` to `E492`, which the file sweep could not have seen (both are
exit 1). 111 commands in 6.3 s, four identical runs, 27 KB.

Two things it needs, both measured. A listing that pages (`:highlight`) does not
stop for `ESC`, and the session then ran to the timeout; `q` ends the `--More--`
listing, and in Normal mode `q` followed by `ESC` is an aborted recording that
changes nothing (`.` would also work, but it repeats the last change and polluted
the row). And `:stop`/`:suspend` are skipped, as they are today.

### 2j. The argv record, and the pty corpus that stays

**argv is not keystrokes**, so it needs its own instrument — `tools/clicheck.py`'s
shape in stream form. 27 invocations, each recorded by exit status, stderr and
whether a screen was drawn at all; three runs identical; 5.0 s. It is the only
thing that can check phases P2, P3 and P4, and today it reads, among others:

```
'-T' 'xterm'    exit=0  stream=2117
'-T'            exit=1  stream=0     Argument missing after: "-T"
'-Txterm'       exit=1  stream=0     Garbage after option argument: "-Txterm"
'-e'            exit=1  stream=0
'-E'            exit=0  stream=0
'-'             TIMEOUT (took over the input and never returned)
'--ttyfail'     exit=1  stream=0
'f.txt' 'g.txt' exit=1  stream=0     Too many edit arguments: "g.txt"
'-R' '-c' '-u' '-i' '-m' '-Z' '--help' '--version'   exit=1   Unknown option argument
```

**A small pty corpus stays**, five scenarios, for the two things a pipe cannot
show: that the window size comes from the terminal (`TIOCGWINSZ` on a real pty
versus the 80×24 fallback) and that raw mode is entered and restored
(`tcgetattr`/`tcsetattr` succeed on a tty and fail harmlessly on a pipe). Those are
`termcheck.py`'s and `ptycheck.py`'s territory and they already exist; what goes is
the *behaviour* corpus's dependence on a pty.

### 2k. What `.reference/zero-baselines` becomes

Three recordings, replacing today's `behaviour/`, `ref-exsweep.txt` and
`ref-term.txt`:

```
.reference/zero-baselines/
    screen/            102 keystroke cases, one file each     (166 KB)
    ref-excmds.txt     111 Ex commands, by the message        (27 KB)
    ref-argv.txt       27 invocations                         (2 KB)
    ref-term.txt       the terminal table                     (pty)
    ptycheck.txt       the five pty scenarios that stay       (pty)
```

**As built it is `ref-pty.txt` rather than `ptycheck.txt`, and it is six directories and
files rather than five**: zero phase 40 added `memline/`, sixteen cases that build
buffers of 200 to 25,000 lines in the editor, because everything above records a corpus
that allocates **exactly one data block per case** and therefore cannot see the text
layer as a tree at all. `zero.mk`'s `zero-baselines-check` names the shape and not merely
the directory, which is why it noticed. **Adding a part cost four phase checks their
arithmetic** — 9, 13, 30 and 34 pinned the record count as an equality and 25, 35, 36 and
37 as a floor, and only the equalities broke; all four are computed now.

Recorded, as today, **from the frozen `whim-vim.c` input** built with whim's own
compile line, three times, requiring the three runs to be identical — `ZERO-GOAL.md`
rule 3, unchanged. Recording them from the pipeline's input is legitimate where
recording them from its current output would not be.

The programs are zero-only files, named by `pipes/zero0.sh` and
`tools/zerodelta.sh` and by nothing whim or slim runs — `tools/zscreen.py` (the
emulator), `tools/zstream.py` (the driver), `tools/zcases.py` (the corpus),
`tools/zexcmds.py` (the command sweep) and `tools/zargv.py` (the invocations) —
which is `ZERO-GOAL.md` rule 9's requirement and the precedent `zerodelta.sh` set.
The shared `behaviour.py`, `exsweep.py` and `termcheck.py` are not touched, so no
whim or slim key moves. (`termcheck.py` is still untouched, and from phase 5 it is
no longer *run*: zero records the terminal table with `tools/ztermcheck.py`, which
imports it and replaces the one call that passes a file argument.)

**This is a change to phase 0's program**, not a new phase: `pipes/zero0.sh` is
what records the baselines and what refuses when they differ. It moves phase 0's
implementation digest, so phases 0 and 1 re-run (9 s and a build), and
`.reference/zero-baselines` is rewritten once, with the difference named — which is
what the existing refusal text already asks for. `tools/zerodelta.sh` reads the new
recordings, and the old file-based harnesses stay exactly where they are, untouched,
for slim and whim (`ZERO-GOAL.md` rule 9: a zero tool is a new file, never an edit
to a hashed one).

**There is no case-by-case equivalence with the old corpus, and this plan does not
pretend otherwise.** A file-based case asserted the bytes of a written file; a
keystroke case asserts a screen. The evidence that the new corpus is worth
trusting is §2f (it is deterministic, including under load), §2c (it agrees with
`pyte`, and with a pty on every case's outcome) and §2g (it catches five
deliberate breaks, three of them in exactly one named case, and one of them
invisible to the old corpus).

### 2l. Hazards this instrument has

Measured, all of them:

1. **A typed Escape followed by `[`** would be read as a key code, because with the
   whole keystroke file available there is no pause to tell them apart. No case in
   the corpus does it; one that needs to must put the Escape in its own read, which
   the stream harness cannot do — that is a case for the pty corpus.
2. **A command that takes over the input** (`:append` and friends) must be closed
   by the case itself (`.` on a line of its own). Measured: `:append`,
   `inserted`, `.` works, and `:a/:i/:c` use `getexline`, not the Ex-mode line
   reader, so they survive P3.
3. **EOF is an exit, not a quit.** A keystroke file that does not quit ends with
   the editor exiting 1 and clearing the screen. Every case quits.
4. **`:stop`/`:suspend`** need the session of their own (§2b).
5. **The version banner carries a build timestamp** and must be scrubbed from the
   argv record (§2e).
6. **The bell is part of the record** and the corpus's own quit keystroke
   (`ESC` in Normal mode) rings it. That is deterministic and left in.

### 2m. As implemented, in zero phase 3

The instrument in this section is built: `tools/zscreen.py`, `zstream.py`,
`zrec.py`, `zcases.py`, `zexcmds.py`, `zargv.py`, `zpty.py`, `zrecord.sh` and
`zcompare.py`, 1,144 lines, named by nothing whim or slim runs. `ZERO-GOAL.md`'s
*Phase 3* is what it does and what it proved. **Five things differ from the design
above**, each because building it said so:

1. **A case's options and `'paste'` go on the command line**, as `+set paste`
   rather than a typed `:set paste` — §5.11's recommendation, taken. It removes two
   snapshots per case, and it exercises `+{command}` in all 102.
2. **The corpus is 102 cases, not 92**: the eight "one case per thing a later phase
   removes" (`key_Q`, `cmd_write`, `key_gf`, …) and the two CTRL-C cases were
   written in, so every planned phase has something that can see it.
3. **The record is sectioned** — `--- exit`, `--- bells`, `--- stream`,
   `--- stderr`, `--- snap N` — because `screen-moved` and `stderr-moved` have to
   drop a *dimension* of every record and compare the rest. The design said
   "record both"; the sections are how a comparator is told which is which.
4. **A `-moved` token is itself checked.** Declaring a dimension that did not move
   fails, which the design did not ask for and which the first version accepted:
   with both tokens declared, a difference explained by one of them counted as
   evidence for both.
5. **The pty corpus is four scenarios, not five**, and none of them records a
   screen: `tools/ptycheck.py`'s lesson is that a pty screen dump is a recording of
   the machine's load, so each scenario is an extraction — the size, the term name,
   the line the editing left.

One number in §2f moved: the corpus is **0.5 s** here against the phase-2 binary
(the 6.4 s measurement was the phase-1 binary, which still had the two-second
pause), and a whole recording — four corpora and the terminal table, run at once —
is **5.1 s**.

## 3. The phases

### 3a. First, a thing the sweep can no longer do: `ex_ni` is gone

whim's rule 3 was *a command is never deleted from the table*: the row's name still
decided what every abbreviation of every other name meant, so a retired command
pointed at `ex_ni`. **Phase 80 removed `ex_ni` with the 489 stub rows** — measured:
zero mentions in `zero-vim.c`, and a patch that pointed `:write` at `ex_ni` does not
compile.

So a zero phase that removes a command **deletes its row and its enumerator**. That
is safe now and was not before, for three reasons, each of which has to hold:

* whim 80 gave every surviving row its shortest abbreviation and made a match
  require at least that many characters, so **row order is irrelevant** and no
  removed name can be inherited by the next row (`SLIM-GOAL.md`'s `:help` →
  `:helpclose` trap cannot fire);
* `cmdnames[]` is **designated** (`[CMD_write] = {…}`), so deleting the enumerator
  and the row together cannot misalign them, and
  `static_assert(sizeof(cmdnames)/sizeof(cmdnames[0]) == CMD_SIZE)` catches a
  dropped one either way — measured: deleting six rows without their enumerators
  fails the assertion at compile time;
* `tools/create_cmdidxs.py`'s `names()` **refused a table with fewer than 100
  rows**, and it is what the command sweep enumerates. 111 − 12 = 99. **The floor
  had to be lowered deliberately, in the phase that crosses it**, or the sweep
  stops working with a message about a parse that cannot be right. *Done, as
  zero phase 8*, which took the table 104 → 99: the floor is **80** and the
  message the old one gave was not the one this line predicts — `no command table
  found in either shape`, because `names()` tries both parsers with `check=False`.
  Twenty-eight implementation keys moved with it, gated on `slim-verify` and
  `whim-verify`.

`nv_cmds[]` rows are the opposite: they are **pointed at `nv_error`, never
deleted**, and `tools/nvidxcheck.py` requires the precomputed index to stay a
permutation — §2g's fifth break is what happens otherwise.

### 3b. The eleven phases

| # | phase | removes | frees | delta in the new corpus |
| --- | --- | --- | --- | --- |
| 2 | nothing asks whether this is a terminal | the two warnings, `ui_delay(2005)`, `tty_fail`/`--ttyfail`, `stdout_isatty`, `mch_check_win`, `mch_input_isatty`, the four `isatty()` calls, `check_tty` | **`isatty`** | every record's stderr line (`stderr-moved`); measured on a patched build: 102 of 102 records move, each by one line, and the corpus goes 6.4 s → **0.53 s** |
| 3 | no streaming Ex | `-e -E -s -v`, `Q`, `gQ`, `do_exmode` (95 lines), `getexmodeline` (262), `silent_mode` (23 mentions), `exmode_active` (49 mentions, constant `FALSE`), `pending_exmode_active`, `s_vbuf`, `main_loop`'s `noexmode` | **`setvbuf`** (and the `stdout` reference) | `key_Q`, `key_gQ`; argv rows `-e -E -s -v` |
| 4 | argv is `+{command}` and `-T {term}` — **built, as zero phase 5** | the file argument and `buflist_add`, bare `-`/`EDIT_STDIN`, `--`, `ME_TOO_MANY_ARGS`, `had_minmin`, `read_cmd_fd`'s reassignment, and `params.edit_type` with `read_stdin()` | — | **as listed, plus `+q! f.txt`**: 79 lines, six argv rows, nothing else |
| 5 | no write — **built, as zero phase 6** | the six rows and their enumerators, `nv_Zet`'s `ZZ`, `do_one_cmd`'s `:w>>`/`:w!` parse; the sweep then takes `do_write`, `buf_write`, `buf_write_bytes`, `check_overwrite`, `check_writable`, `check_mtime`, `not_writing`, `write_eintr`, `mch_setperm`, `mch_fsetperm`, `mch_nodetype`, `vim_fexists` and seven more — **19 functions; the file 85,734 → 84,675** | `chmod fchmod fstat ftruncate lstat unlink`, exactly | **`cmd_write` and `zz_key`; the six sweep rows CEASE TO EXIST, they do not change message** |
| 6 | no read — **built, as zero phase 7** | the `CMD_read` row and enumerator and `do_one_cmd`'s `:r!`/`:r !cmd` parse; the sweep then takes `ex_read`, `do_bang`, `do_shell`, `do_filter`, `check_secure` and `prevcmd_is_set` — **6 functions exact; the file 84,675 → 84,453**, which is 222 lines and not 194, the extra being the `usefilter` fold below | — | **`cmd_read` and `read_cmd_gone`; the sweep row `read` CEASES TO EXIST — but NOT `filter_gone`**, which was E492 on the input binary already |
| 7 | no `:edit`, and no `gf` — **built, as zero phase 8** | the five rows and enumerators, `do_one_cmd`'s `curbuf_locked()` exemption for `:edit` and its `++opt` parse, and the `gf`/`gF` and `[f`/`]f` **arms** — there are no `nv_cmds[]` rows for them; the sweep then takes `do_ecmd` (328), `do_exedit`, `ex_edit`, `grab_file_name`, `otherfile`, `nv_gotofile`, `text_or_buf_locked`, `check_lnums*`, `prepare_help_buffer`, `getargopt` and six more — **17 functions; the file 84,453 → 83,755** | — | **`cmd_edit` and `key_gf`; the five sweep rows CEASE TO EXIST** |
| 8 | nothing reads a byte — **built, as zero phase 9** | `open_buffer`'s two read arms, its `read_fifo` local and its signature; the sweep then takes `readfile` (787), `read_buffer`, `read_eintr`, `readfile_linenr`, `filemess`, `msg_add_fname`, `msg_add_lines`, `msg_add_eol` and eight more — **16 functions; the file 83,755 → 82,572**. `read_stdin` here is the ARGUMENT, not the function: `read_stdin()` was argv's and went with zero phase 5. `mch_isdir` and `set_rw_fname` land here and not in row 9 | `open access fcntl`, exactly | **nothing at all**: two full recordings byte-identical. The evidence is an instrumented build, not a record — see below |
| 9 | the buffer has no name — **built, as zero phase 10** | `:file`'s row, enumerator and BOTH of `do_one_cmd`'s `CMD_file` tests; `buflist_new`'s two name parameters and everything it did with them; sixteen folds of `b_ffname`/`b_sfname`/`b_fname` (**32/26/29 mentions, not 58/30/42** — phase 9 had already taken eleven of them); `do_one_cmd`'s `EX_XFILE` call, which reaches zero rows here; `readonlymode` and `b_dev_valid`'s last write; `shorten_fnames`' cwd; and `find_file_name_in_path`'s `FNAME_EXP` arm. The sweep then takes **60 functions** — `setfname`, `ex_file`, `rename_buffer`, `otherfile_buf`, `buf_setino`, `fix_fname`, `ml_upd_block0`, `ml_timestamp`, `eval_vars`, `expand_filename`, `find_cmdline_var`, the whole `ExpandOne`/`gen_expand_wildcards` layer, `vim_FullName`, `mch_FullName`, `mch_dirname`, `mch_getperm`, `shorten_*`, `home_replace_save` and the `ff_*` remnants — with twelve `buf_T` fields and 43 string literals; **the file 82,572 → 80,387**. `buf_spname` and `get_spec_reg` are NOT removed: both survive folded, `[No Name]` being the only answer left. **`mch_isdir` and `set_rw_fname` are not here — zero phase 9 took both**, and `setfname` had one caller left because of it | `stat getcwd strerror`, exactly — and **only with the `shorten_fnames` and `FNAME_EXP` folds**: `stat`'s last caller is `mch_getperm`, `getcwd`'s and `strerror`'s is `mch_dirname`. **Not `fsync`**, whose only caller is `ui_write` and which is row 12's | **`cmd_file` and the sweep row `file`, and nothing else**: `reg_percent` and `ctrl_g` are byte-identical, `b_fname` having been NULL since row 4 and `[No Name]` already what they printed |
| 10 | `:q` quits, `ZZ` is `ZQ` — **built, as zero phase 11** | ONE fold, of `ex_quit`'s refusal. This row names three functions and **sixteen** go: the five of the refusal — `check_changed`, `check_changed_any`, `no_write_message`, `no_write_message_nobang` and `not_exiting` — and then **eleven nobody foresaw**, `check_changed_any()`'s tail being the last caller of the whole switch-buffer/switch-window island: `add_bufnum`, `set_curbuf`, `enter_buffer`, `win_enter`, `win_enter_ext`, `goto_tabpage_win`, `goto_tabpage_tp`, `get_winopts`, `find_wininfo`, `buflist_findfpos` and `buflist_getfpos`. Two struct fields go by hand — `w_topline_was_set` and `wi_changelistidx`, write-only afterwards and invisible to `deadfields.py` — and `ex_quit`'s dead tail with them, since `getout()` sets `exiting` itself and never returns. **The file 80,387 → 79,866**; twelve enumerators go and nothing renumbers. **`nv_Zet`'s `:x` is not here — zero phase 6 took it** | — | **`quit_modified` and the sweep row `quit`, and nothing else**: the measurement below was taken before zero phase 8, which has since moved `cmd_edit` and removed the rows `edit enew ex view visual`. **`quit` CHANGES MESSAGE rather than ceasing to exist**, unlike every sweep row rows 5 to 9 declared, and the **exit status does not move in the corpus** — every case ends with a trailing `:q!`, so the 1 → 0 is a probe (`q_alone`) and not a record |
| 11 | the options nothing reads — **built, as zero phase 12** | The set is COMPUTED and it is **seven**, not four: `'fsync'` `'modified'` `'prompt'` `'readonly'` `'undoreload'` `'write'` `'writeany'` have no reader of their own global, and SIX are dropped. **`'prompt'` is missing from this row** — its only reader was `getexmodeline()`'s `if (p_prompt) msg_putchar(':');`, so it is zero phase 4's orphan. **`'modified'` stays** (decision 5, and `dropoptions.py` refuses a PV_BUF row). `'readonly'` is live code and not an inert row: `change_warning()` and its six calls, the `[RO]` in `fileinfo()` with its format string, the `[RO]` on the status line, and `did_set_readonly()`. **The flag letters are NOT touched** — see below. The sweep then takes `SHM_RO`, `BV_FS`, `BV_RO`, `w_readonly`, `b_did_warn` and the six globals; **the file 79,866 → 79,757**, and `options[]` 114 → 108 rows and 102 → 96 globals | — | none, measured: two full recordings byte-identical. `tools/dropoptions.py --strict` is the check for the four `PV_NONE` rows ONLY; `'fsync'` (PV_BOTH) and `'readonly'` (PV_BUF) are refused on the PV_ guard before the reader test is reached, and `tools/droplocal.py` is the tool and the check there |
| 12 | no `FILE *` that is never opened — **built, as zero phase 13** | `scriptin[]`, `redir_fd` and `ui_write`'s `console`, as stated — and with them `closescript()`, `using_script()`, `redirecting()`, `vim_fsync()` and **`redir_write()`**, which this row omits, plus `curscript`, `NSCRIPT`, `saved_typebuf[]`, `redir_off` and the two hand-folded locals `script_char` and `retesc`. `may_sync_undo()` and `is_safe_now()` SURVIVE one conjunct shorter. **The file 79,757 → 79,603**, and `FILE` is not named in `zero-vim.c` at all afterwards | **`fclose getc putc fsync`**, and this row is wrong twice: **`fputs` does NOT go** — the source names it nowhere and `nm -u` still lists it, gcc lowering `fprintf(stderr, ...)` to it — and **`fsync` is here, not in row 9**, its only caller being `vim_fsync()` and that function's only caller `ui_write()`'s `console` branch | none, measured: two full recordings byte-identical. The evidence is an instrumented build at FIVE places, 0 of 106, with the `ui_write()` control at 105 of 106, and eighteen adversarial sessions |

**EVERY ROW IS BUILT, and the numbering is not the table's.** Row 2 ran as zero
phase 2, row 3 as zero **phase 4**, row 4 as zero **phase 5**, row 5 as zero
**phase 6**, row 6 as zero **phase 7**, row 7 as zero **phase 8**, row 8 as zero
**phase 9**, row 9 as zero **phase 10**, row 10 as zero **phase 11**, row 11 as zero
**phase 12** and row 12 as zero **phase 13**, because the harness switch of §2 landed
between rows 2 and 3 as phase 3. This plan is done; what is left of it is §4c. `ZERO-GOAL.md` is what each one did; where this
table turned out to be wrong is said at the row.

#### P2 — nothing asks whether this is a terminal

Decision 7. `check_tty()` (86432) is the whole of it: it prints
`"Vim: Warning: Output is not to a terminal"` and
`"Vim: Warning: Input is not from a terminal"` to stderr and then, unless
`--ttyfail` was given, sleeps 2,005 ms. Measured on the committed binary with both
fds piped: the two lines, `ui_delay` costing 2.007 s, and exit 0; with
`--ttyfail`, the same two lines, no delay, exit 1.

Measured by the user on the same binary: the phase takes the object's undefined
symbols from **79 to 78**, the one that goes being `isatty`; and it makes the
102-case corpus cost **0.53 s instead of 6.4 s**, because the delay was two
seconds of every case.

Both go, along with `stdout_isatty` (3592, 6 mentions), `mch_check_win` (its
`isatty(1)` is the only thing it does, and `common_init_2`'s assignment at 86008
goes with it), `mch_input_isatty` (61535), `mch_get_shellsize`'s
`if (!isatty(1) && isatty(read_cmd_fd)) fd = read_cmd_fd;` (61888 — `fd` stays 1),
and `fill_input_buf`'s `!did_read_something && !isatty(read_cmd_fd)` arm (82807),
which reopened fd 0 from stderr when the first read came back empty. `tcgetattr`
and `tcsetattr` stay: a real terminal still needs raw mode, and on a pipe they fail
harmlessly.

**One behaviour question, and it had to be measured rather than reasoned.**
`nv_esc` (52449) computes `int out_redir = !stdout_isatty;` and, on a non-tty,
either prints `"Type  :qa!  and press <Enter> to abandon all changes and exit Vim"`
to stderr or runs `do_cmdline_cmd("qa")` — a command whim removed in Phase 46, so
it would answer E492. Folding `stdout_isatty` to `TRUE` sends both to the screen
instead. Measured: **neither is reachable in this harness.** That branch is behind
`cap->arg`, which is `TRUE` only for the `CTRL-C` row, and CTRL-C on a stream
exits through `preserve_exit()` — recorded screen `"Vim: Finished."`, exit 1 — before
`out_redir` matters. The corpus has `ctrl_c_clean` and `ctrl_c_changed` to pin
exactly that, and the declared delta for the fold is **none**.

#### P3 — no streaming Ex

Decision 3. `do_exmode` (95 lines) and `getexmodeline` (262) go; `Q`'s `nv_cmds[]`
row is pointed at `nv_error` and `gQ`'s arm of `nv_g_cmd` goes; `exmode_active`
becomes constantly `FALSE` and its 49 mentions fold, as `silent_mode`'s 23 do; and
`-e`, `-E`, `-s` and `-v` leave `command_line_scan`.

**The hazard: `exe_commands()` must not go with them.** The `+{command}` list is run
from `vim_main2()` (85903) by `exe_commands()` (86502), which touches neither Ex
mode nor silent mode — but it sits two lines from the `if (exmode_active)` that sets
the cursor to the last line, and `+cmd` is decision 8 infrastructure that the whole
harness depends on. The phase check runs the argv record, where five rows exercise
`+cmd`, and refuses if any of them stops working.

`getexline` (23843) **stays**: `:append`, `:insert` and `:change` read their lines
through it, not through the Ex-mode reader, and measured they still work
interactively. `print_line`'s `silent_mode` save/restore (16326) folds, and
`msg_puts_printf` stays — `msg_use_printf()` asks whether the *screen* is usable,
not whether the editor is silent, so `printf` survives this phase.

**As built, in zero phase 4**, and three things in the row above are wrong.
`-s` **alone does not move**: `case 's'` set silent mode only `if (exmode_active)`
and called `mainerr()` otherwise, so a bare `-s` was already an unknown option and
its record is byte-identical — the declared delta is `key_Q`, `key_gQ` and the argv
rows `-e`, `-E`, `-e -s`, `-v`. **`isatty` is freed here, not by P2**: phase 2 kept
`check_tty()`'s `if (exmode_active)` branch deliberately, so all five calls survived
it, and folding that branch here empties the function — which the sweep then cannot
take, because what is left is a local that is set and never read, a warning
`tools/deadsweep.py` does not act on. `check_tty()` and its call go by name and
`mch_input_isatty()` with the fifth `isatty()` follows. And `exe_commands()` did not
need special handling beyond folding its last statement. Measured: 86,586 → 85,813
lines, five functions, `nm -u` 80 → 78 (`setvbuf`, `stdout`), the binary 869,512 →
861,288 bytes, the phase 81 s.

#### P4 — argv is `+{command}` and `-T {term}`

Decision 9, **as it read when this was written** — §1 records the reversal, and
`-T {term}` is to go in a later phase, leaving `+{command}` as the whole of argv.
What is left of `command_line_scan` after P2 and P3 is `+cmd`, `-T`,
bare `-`, `--` and the file argument; this phase takes the last three. A bare word
becomes `ME_UNKNOWN_OPTION` — *"Unknown option argument: \"foo\""* — and
`ME_TOO_MANY_ARGS` loses both call sites.

**Deleting that enumerator renumbers a parallel table.** `main_errors[]` (85888) is
indexed by `ME_*`, so the row and the enumerator go together, in the order
`deadenums.py` requires: pin the survivors, dump DWARF before and after
(`tools/enumvals.sh`), and require no survivor to have moved.

**As built (zero phase 5), three things this section did not foresee.** *No
survivor can be pinned*: the enumerator **is** the row index, so the three after
the deleted one must move, and the check is that exactly they moved, by one, out of
1,327 — not that nothing moved. *The file-argument arm is replaced by
`mainerr(ME_UNKNOWN_OPTION)` and not deleted*, because a bare word that matches no
arm never advances the `while` and the parser loops for ever. And *`+q! f.txt`
moves too*, which this row's delta column missed: the option scan reads the whole
command line before anything runs, so a file argument after a `+cmd` is refused
before the `+cmd` is executed.

**And it breaks `tools/termcheck.py`**, which is whim's and asks its question with
a file argument: from this boundary all nineteen of its rows read `(none)`.
§2e/§2k's "the terminal table, unchanged" was wrong by one argument.
`tools/ztermcheck.py` — `termcheck.py` with its `ask()` replaced and nothing else —
records the same nineteen rows, proven from the binary the phase was handed and
from `whim-vim.c` in phase 0; `tools/termcheck.py` itself is untouched, so no whim
or slim key moves.

#### P5–P9 — the filesystem

The order is forced and the reason is `b_ffname`: `do_write`, `check_readonly` and
`do_ecmd` are its largest readers, so the **name goes last** (P9). Within that, the
write side goes before the read side because `:w !cmd` and `:r !cmd` share
`do_bang`, and `:edit` goes before `readfile` because `do_ecmd` is a caller of
`open_buffer`, which is `readfile`'s caller — one link further out than this line
said, measured as zero phase 8.

**As built (zero phase 6), four things this row did not foresee.** *`ZZ` moves
here, not at P10*: `nv_Zet` runs the command string `"x"`, so `case:zz_key` moves
whichever way it is left, and the phase that removes `:x` is the phase that owns
it — it is `"q!"` from zero phase 6, which is decision 5 arriving early. *The six
sweep rows do not change message, they cease to exist*: whim's Phase 80 removed
`ex_ni`, so a zero phase deletes the row and the enumerator (§3a) and
`tools/zexcmds.py` enumerates 105 names where it enumerated 111 — the column's
`E32/E471 → E492` describes the two screen cases and not the sweep. *The count was 17
functions and is **19***: `check_file_readonly` and `u_update_save_nr` are the two
the reachability simulation of §3d missed. Its 905 lines are function bodies and
are not comparable with the 1,059 the file actually lost, which includes the
prototypes, enumerators, blank lines and one struct field the sweep took with
them. And *no
handler is deleted by name*: the four anchors alone produce a byte-identical swept
file, measured against an edit that also deletes the eight handlers, so the phase
program names none of them.

**And the row floor is now live.** §3a's warning — `create_cmdidxs.names()` refuses
a table of fewer than 100 rows, and it is what the command sweep enumerates — had
five rows of margin after P5 and **four** after P6, not eleven. P7 spent the rest
(104 → 99) and lowered the floor to **80** in its own commit, as decision 8 says.
The margin is 19 rows and P9's `:file` spent one of them, 99 → 98: 18 left.

**As built (zero phase 7), four things the P6 row did not foresee.** *`filter_gone`
is not this phase's delta*: `:!` has not existed since whim, so `:%!sort` already
answered E492 on the input binary and its record is byte-identical — what the phase
removes is the code behind a command that was already gone, and the check asserts
E492 on both binaries rather than declaring the case. *The line count is 222, not
194*: the function count is exact at six, and the difference is the prototypes, the
five file-scope variables, the blank lines and the `usefilter` fold. *`do_bang`'s
other caller was `ex_write`'s `:w !cmd`*, which zero phase 6 swept — so the
ordering this section states (the write side before the read side, because the two
share `do_bang`) is what made the read side a three-anchor phase. And *one fold is
a judgement no tool could make*: `exarg_T.usefilter` is written by nothing once
both `:w !` and `:r !` are gone, and a struct member that is only read draws no
warning and is not what `tools/deadfields.py` removes, so the six surviving tests
and the field go by hand — measured byte-identical in the recording.

**As built (zero phase 8), five things the P7 row did not foresee.** *There are no
`gf`/`gF`/`[f`/`]f` rows to remove*: the four keys are **arms** inside `nv_g_cmd()`
and `nv_brackets()`, whose `g`, `[` and `]` rows dispatch dozens of other keys, so
this phase deletes no `nv_cmds[]` row at all and the usual hazard does not apply —
fifty of those keys were pressed on both binaries and exactly four moved. *There is
a sixth anchor the row does not list and it pays for itself*: `EX_ARGOPT` reaches
zero rows here, so `do_one_cmd`'s `++opt` block, `getargopt()` and
`exarg_T.read_edit` all go, for 30 lines and a **byte-identical** recording. *There
is one anchor outside the table and the keys*, `do_one_cmd`'s `curbuf_locked()`
exemption, which names `CMD_edit` in a conjunct and keeps `CMD_file`; an edit shaped
like the table forgets it and the build catches that. *The function count is 17, not
16, and the line count 698, not 618* — the seventeenth is `getargopt` and the
difference is prototypes, enumerators, blank lines and two struct fields. And *the
`:edit` row is `:ex` and `:visual` too*: `do_exedit` is thirty lines, so `:ex! f` and
`:visual! f` load a file exactly as `:e! f` does, `:view! f` loads it with
`'readonly'` and `:enew!` empties the buffer — measured on the input binary, because
no recording here can see a file being opened.

**As built (zero phase 9), five things the P8 row did not foresee.** *`read_stdin`
in the row is the ARGUMENT and not the function*: `read_stdin()` was argv's and went
with zero phase 5, and what this phase removes is the parameter of `open_buffer()`
and `read_buffer()` — which needs the signature fold, because `-Wno-unused-parameter`
makes an unused parameter invisible to the sweep where an unused local is not.
*`mch_isdir` and `set_rw_fname` land here, not in the name row*, and `set_rw_fname`
being `setfname`'s second caller is what makes P9 possible at all. *`fsync` is not
row 9's*: its only caller is `ui_write`, so it belongs to row 12 — the row above is
corrected. *The count is 16 functions and 1,183 lines*, against the nine names the
row listed; the difference is eleven the sweep found under them, fifteen prototypes,
three file-scope strings, seventeen enumerators and 24 string literals — the whole
message layer that reported what had been read. And *the delta is nothing at all,
which is a statement rather than an omission*: the read path stopped being reachable
at zero phase 8, so the phase removes code that could not run, two full recordings
are byte-identical, and the evidence is an instrumented build — the input source
compiled twice, with `write(2, …)` first in `readfile()` (0 of 106 records marked)
and then in `open_buffer()` (104 of 106, the identical instrument). The row's
"probed by the argv record and by `startup`" could not have worked: those records do
not move.

**As built (zero phase 10), six things the P9 row did not foresee.** *The three
name fields are 32/26/29 mentions, not 58/30/42*: zero phase 9 took eleven of them
with `readfile()`, and the count the row carried was whim-vim's. *`buf_spname()`,
`buf_get_fname()`, `get_spec_reg()`, `get_trans_bufname()`, `fileinfo()` and
`check_fname()` are NOT removed* — the row lists them among what goes, and every one
survives folded, because `[No Name]` is what they answer and `fileinfo()` still has
three callers. *There is an anchor the row does not list and it is the largest part
of the phase*: `EX_XFILE` reaches zero rows once `:file`'s goes — `:read` was one of
its six and phase 7 took it, four more went with the `:edit` family at phase 8 — so
`do_one_cmd`'s `expand_filename()` call can never be entered, and folding it hands
the sweep 32 of the sixty functions. It is phase 8's `EX_ARGOPT` exactly. *The freed
set is right only with two further folds*: `getcwd` and `strerror` need
`shorten_fnames()` to stop fetching a cwd for a now-empty `shorten_buf_fname()`, and
`stat` needs `find_file_name_in_path`'s `FNAME_EXP` arm folded away — which costs
CTRL-F and CTRL-P their difference, both becoming pure text extraction, and is the
charter reading. *The delta is one case and one row, not four*: `reg_percent` and
`ctrl_g` are byte-identical, `b_fname` having been NULL since zero phase 5 and
`[No Name]` already what they printed, and `:registers` never printed its `"%` and
`"#` lines at all. And *`buflist_name_nr` must be folded at its callers and never in
place*: folding `buf == NULL || b_fname == NULL` away inside it returns OK with
`*fname` never written, a silent behaviour change in the direction that crashes,
where the truth is that it returns FAIL always.

Two things P9 must decide rather than compute, both already measured — and both
came out as written:

* **`[No Name]` is already the answer.** `buf_get_fname()` (5617) returns
  `_("[No Name]")` when `b_fname` is `NULL`, and `win_redr_status` (11277) already
  draws it through `get_trans_bufname`. Nothing has to be written to give the
  buffer a display name; the name simply never gets set. The status line and
  `CTRL-G` change, and `startup`, `ruler_move`, `ctrl_g` and `cmd_file` are the
  cases that see it.
* **`'isfname'` is not a file option.** Its readers are `buf_init_chartab`,
  `parse_isopt` — and, through `vim_isfilec`, `regatom`, `regrepeat` and
  `regmatch`: the `\f` pattern atom. It stays.

#### P10 — `:q` quits, `ZZ` is `ZQ`

Decision 5. §2g measured this delta as 2 corpus cases and 6 sweep rows, and **five
sixths of it has already happened**: `:edit`, `:enew`, `:ex`, `:view` and `:visual`
all answered E37 before reaching their own refusal, and zero phase 8 removed all
five — so `cmd_edit` moved there, and their sweep rows do not exist to move. What is
left for this phase is **`quit_modified` and the sweep row `quit`**; `zz_key` moved
at zero phase 6. `check_changed()` is folded away rather than deleted first, because
`ex_quit` and `check_changed_any` call it — `do_ecmd` was the third caller and went
with phase 8.

**Built as zero phase 11, and three things here were wrong.** *(1)* The removal is
not three functions but **sixteen**, and the eleven this row does not name are the
larger half: `check_changed_any()`'s tail is "go to the buffer that refused", and
after whim removed the buffer list and the window commands that tail was the last
caller of the whole switch-buffer/switch-window island. The editor has no code for
entering a different buffer or window afterwards. *(2)* The row `quit` **changes
message rather than ceasing to exist** — `:quit` still has its row, so
`tools/zexcmds.py` enumerates the same 98 names and compares the block — which makes
it the first sweep row zero has declared that survives. *(3)* `need 11 swept` **is
required**, where the brief that specified the phase said there was none: on the
unswept text `buflist_findlnum()` still calls `buflist_findfpos()` from outside the
island, so the invariant every fold rests on is false and the counted anchor refuses.
Two extras the row does not mention were taken and each is byte-identical in the
recording: the two struct fields that become write-only, and `ex_quit`'s dead tail.

#### P11 — the options nothing reads

Computed, not listed: for each of the 116 non-`t_` rows, the set of functions that
mention its variable, minus the option-table plumbing. Four rows have no reader
outside the phases above — `'fsync'` (`buf_write`), `'write'`
(`not_writing`→`do_write`), `'writeany'` (`do_write`, `check_overwrite`),
`'undoreload'` (`do_ecmd`) — and `'readonly'` keeps only the `W10` warning and the
`[RO]` indicator, which decision 8's exemption does not cover and which this plan
recommends dropping (§5, decision 5).

`tools/dropoptions.py --strict` refuses a row while anything still reads its
global, and `tools/orphanopts.py` refuses a global whose initialising row has gone —
whim's Phase 11 left `p_dir` NULL and dereferenced before those guards existed.
**`'paste'` is exempt by decision 8**, and the phase program says so in a comment
that names this plan, so the next person to compute the set does not "fix" it.

**Built as zero phase 12, and four things here were wrong.** *(1)* The computed set is
**seven, not four**: `'prompt'` is missing from this section, and its only reader was
`getexmodeline()` — so it is zero phase 4's orphan, and the phase needs a `uses
options:12 streams:4` line this plan does not have. `'modified'` is the seventh and
**stays**, by decision 5. *(2)* *"dropoptions.py --strict refuses while a reader exists,
which is the check"* is true only for the four `PV_NONE` rows. `'fsync'` (PV_BOTH) and
`'readonly'` (PV_BUF) are refused on the **PV_ guard**, before the reader test is
reached and with a message about a segfault at startup rather than about readers;
`--local` plus `tools/droplocal.py` is the pair, and `droplocal.py` is what refuses
while a real reader survives — it did, on `did_set_readonly`, which is why that one
function is removed by name. *(3)* **The `'shortmess'` and `'cpoptions'` letters are
NOT dropped, deliberately.** Each list is a separate string literal from the value, so
removing a letter could not move `:set shm?` or `:set cpo?` — but it turns `:set shm=F`
from silently accepted into `E539`, and nothing in the instrument types `:set shm=`.
That is the change rule 2 exists to prevent. 23 of `'cpoptions'` 60 letters and 14 of
`'shortmess'` 23 are inert afterwards, and the phase makes exactly one more so,
`'shortmess'`'s `r`. *(4)* **`tools/orphanopts.py` has a 100-row floor of its own that
this phase crosses on its first drop** — 102 → 98 → 96 — which does not fail the phase
but fails `tools/zerodelta.sh` for every later phase, the same shape as decision 8's
floor arriving from a different table. It was lowered to 80 in the phase's own commit,
the same number and the same argument as `create_cmdidxs.py`'s.

#### P12 — no `FILE *` that is never opened

`scriptin[NSCRIPT]` and `redir_fd` are `static FILE *` that **nothing ever
assigns**: `closescript` calls `fclose` on one, `inchar` calls `getc` on it,
`redir_write` calls `fputs` and `putc` on the other, and all of it is unreachable
in the `can_cindent` sense — a static written nowhere and read everywhere, which no
warning can see. `ui_write`'s `vim_fsync(1)` is the same shape: its `console`
parameter is `FALSE` at the only call site (78780).

**Built as zero phase 13, and three things here were wrong or short.** *(1)*
`scriptin[]` IS assigned, once, in `closescript()` — to NULL — and `redir_fd` by its
own declaration; "nothing ever assigns" is what the phase must *prove* rather than
assume, and it proves it by requiring exactly those two assignments as exact text
before it folds anything. *(2)* **`fputs` does not go and `fsync` does**: the source
names `fputs` nowhere afterwards and `nm -u` still lists it, because gcc lowers
`fprintf(stderr, "…")` to it, exactly as it lowers `printf` to `fputc`, `fwrite` and
`putchar`; `fsync`'s only caller was `vim_fsync()`, so it belongs here and not to row
9. *(3)* The row omits `redir_write()` itself, which is a no-op after the fold and
goes with its five call sites, and with it `redir_off` — **five** writes and no
reader — and the two locals `retesc` and `did_return`, each read-or-written once and
covered by no warning and no tool. A fourth thing the row could not have known: the
`#include <sys/stat.h>` and `#include <fcntl.h>` that nothing needs afterwards were
**left alone**, because removing them would be the first change to the directive
count and that is the charter's to decide.

### 3c. Stages, packages, `need`, `apart`, `uses`

```
phases      0 1 2 3 4 5 6 7 8 9 10 11 12

stage       0
stage       1
stage       2-4
stage       5-7
stage       8
stage       9
stage       10
stage       11
stage       12

need  8  swept      readfile's arms are folded by counting what is left of them
need  9  swept      the b_fname reader set is COMPUTED; on unswept text it shrinks silently
need 11  swept      the option set is computed from the readers that remain
need 12  swept      "nothing assigns this" is a count, and dead code assigns things

apart 4  9          P4's check asserts the one buffer is still named by buflist_add
                   -- WRONG, as built: P4 (zero phase 5) removes buflist_add itself, and
                   what was measured instead is `apart 4 5` in zero's numbering, i.e.
                   the Ex-mode phase's check against the argv phase, which names
                   EDIT_STDIN, had_minmin, buflist_add and ME_TOO_MANY_ARGS as things
                   the argv phase is still to take
apart 7  9          P7's check asserts `:file` still reports a name
apart 9  10         P9's check asserts `:q` still refuses on a modified buffer
apart 4  5          NOT PREDICTED, and measured as built: `apart 5 6` in zero's
                   numbering.  P4's check (zero phase 5) states that IT frees no
                   libc symbol, as a cmp against the stage's starting undefined
                   set, and P5 (zero phase 6) frees six -- so the two cannot share
                   a sweep.  A check that asserts a NEGATIVE about the libc
                   surface is apart from every later phase that frees anything,
                   which is a shape the three predictions above all missed.

package  seed        0
package  build       1
package  terminal    2
package  streams     3 4
package  files       5 6 7 8 9
package  buffers     10
package  options     11
package  tidy        12

uses  streams:3   terminal:2   mechanical  silent_mode's last readers are the warnings 2 removes
uses  streams:4   streams:3    mechanical  -e/-E/-s leave the parser with 3; 4 removes what is left
uses  files:8     files:7      mechanical  open_buffer loses one of its four callers with do_ecmd, removed by 7
                                 -- WRONG as written, and corrected by measurement: it said
                                 readfile's last caller is do_ecmd.  do_ecmd called
                                 open_buffer, not readfile; after zero phase 8 readfile
                                 still has three call sites and open_buffer three callers.
                                 The two phases are in one package, so the line is a
                                 statement rather than a `uses` -- tools/packages.sh
                                 refuses a `uses` inside one package
uses  files:8     streams:4    mechanical  read_stdin's entry point is the bare `-`, removed by 4
uses  files:9     files:5      mechanical  b_ffname's largest readers are do_write and check_readonly
uses  files:9     files:7      mechanical  and do_ecmd, which 7 removes
uses  buffers:10  files:5      rationale   the protection has no remedy once nothing can be written
uses  options:11  files:5      mechanical  dropoptions --strict refuses 'fsync'/'write'/'writeany' before 5
uses  options:11  files:8      mechanical  'undoreload' is read by do_ecmd, removed by 8 (zero's
                                 numbering); asserted there at exactly 2 mentions with its row
uses  tidy:12     terminal:2   rationale   ui_write's console is FALSE at its one call site either way
```

The three `apart` lines are predictions, not measurements: whim's were found by
running each check against each candidate boundary, and zero's must be found the
same way once the programs exist.

### 3d. The cumulative measurement

Reachability over the call graph of all 1,874 functions (roots: `main` plus every
name mentioned outside every function body, as `tools/funcreach.py` computes them),
with each phase's entry points removed:

| cut, cumulatively | functions gone | lines gone | libc freed by reachability |
| --- | --- | --- | --- |
| P5, the write side | 17 | 905 | `chmod fchmod fstat ftruncate lstat unlink` |
| + P6, `:read` | 23 | 1,099 | — |
| + P7, `:edit` and `gf` | 39 | 1,717 | — |
| + P9, the name and everything that reads it | 140 | 4,305 | `+ fsync getcwd strerror` |
| + P8, `readfile` and the stdin reader | 152 | 5,268 | `+ access fcntl open` |
| + P3, Ex mode | **155** | **5,636** | — |

The rows are the order the *measurement* was taken in, not the order the phases
run in: P8's own cut is what is left of `readfile` once P7 has taken a caller of
`open_buffer` — **not of `readfile`**, which is the same correction the `uses` line
above carries, measured as zero phase 8 — and P9's is the largest of them whichever
side of P8 it falls. **`stat` is P9's, and not for the reason this said**: the last
call site is not `buflist_new`'s naming branch but `mch_getperm()`, reached from
`find_file_in_path()`, so it goes only because P9 also folds
`find_file_name_in_path`'s `FNAME_EXP` arm — measured as zero phase 10, where the
undefined set moves by exactly `getcwd stat strerror`.

5,636 lines is **6.5 %** of 86,614. The folds add to it and are **estimated**, not
measured: `exmode_active` (49 mentions), `silent_mode` (23), `stdout_isatty` (6),
`readfile`'s surviving arms, the five option rows, the two `FILE *`s — call it 700
lines, for ≈ 80,300.

Symbols: of the 79 the object needs today, **19 go** — `isatty setvbuf open access
fcntl stat lstat fstat chmod fchmod ftruncate unlink fsync getcwd strerror fclose
getc fputs putc` — leaving **60**, of which four (`__errno_location`, `fputc`,
`fwrite`, `putchar`) are gcc's lowering of `printf`/`fprintf` and not written
anywhere in the source. Measured by simulation over the same graph, not by building
the result.

**BUILT, ALL OF IT, AND THIS ESTIMATE IS WRONG THREE WAYS.** The thirteen phases are
done and `zero-vim.c` is **79,603 lines**, not ≈ 80,300 — **7,011 lines, 8.1 %**, where
this said 6.5 % plus about 700. **Seventeen symbols go, not nineteen, leaving 62** as
`tools/symbols.sh` counts and **61** with zero's own `-fno-stack-protector`. Two of
the nineteen are wrong: **`isatty` does not go** — phase 4 removed one of its five
call sites and three survive, all of them the terminal's — and **`fputs` does not go**,
the source naming it nowhere while gcc lowers `fprintf(stderr, "…")` to it. The
eighteen that went, in phase order, are `__stack_chk_fail` (1), `setvbuf` and `stdout`
(4), `chmod fchmod fstat ftruncate lstat unlink` (6), `access fcntl open` (9), `getcwd
stat strerror` (10) and `fclose getc putc fsync` (13). And **`fsync` belongs to row 12
and not row 9**, its only caller being `vim_fsync()`.

**AND THE NUMBER MOVED AGAIN, FOR A REASON THIS SECTION NEVER CONSIDERED.** This whole
estimate is about what *removal* frees. Zero phases 14 and 15 free 28 more symbols by
**moving code in** rather than out — the strings and memory blocks, the character
classes, the two `ato*`, `qsort` and `bsearch`, defined in `zero-vim.c` as `static`
functions — so `nm -u` is **33** with zero's flags, 34 as `tools/symbols.sh` counts,
and the file is **80,413 lines**, longer than the 79,603 thirteen phases left. Forty-six
of whim's 79 symbols have gone and the eighteen listed above are only the first of
them. The 8.1 % this section was corrected to is 7.2 % now, and a line count is no
longer the measure it was.

## 4. What remains

**THE PLAN IS BUILT AND WHAT REMAINS IS NOT WHAT THIS SECTION WAS WRITTEN FOR.**
Every row of §3b has landed, as zero phases 2 and 4 to 13; §4a and §4b below are
corrected from measurement in place. **And §4c has landed too**: `main()` is a launcher
(18, 19), the terminal and the signal set are the host's (20), both stream calls went
(21, 35), and the line between the core and the host is the file's first `#include`
(23, 25, 26, 27). **Phase 36 finished the sentence the whole of §4 was reaching for**:
the core's own block of plain libc declarations is empty and gone, so it names no libc
function at all — asserted on the cut compiled to an **object**, because a bare `extern`
is invisible to the warning check the boundary otherwise relies on. What the charter
still asks for after that is the **text
representation**, from lines to a tree — and §4d, added afterwards, is that same move
measured from the porter's end. **That move is now largely made**, as zero phases 40 to
45, and §4d is rewritten below from measurement rather than left as a forecast: the
memline is a counted tree of nodes holding line records, with no pages, no blocks and no
memfile, and the three constructs §4d called untranslatable are gone. **What is left of
the charter's line is the *outer* shape** — the tree is still an array-of-children B-tree
in one flat node type rather than the recursive structure a port would write, and a port
still has to be told what `bhdr_T`'s tag means. **Two phases have landed that are in no
part of this
plan**, and they are named here so the plan is not read as the whole account: 38 cut
`builtin_terminals[]` from ten names to `xterm-256color` and `debug`, and 39 removed
`-T {term}`, so `+{command}` is the whole command line and nothing outside the process
can say what terminal this is. Two smaller things are named here
rather than planned, because each is a decision and not a computation — **and the
first of the two has since been built, which is why its bullet is struck through**:

* ~~**the includes.**~~ **BUILT, AS ZERO PHASE 16, AND THIS BULLET IS WRONG TWICE.**
  It says two headers and there are **three** — `<iconv.h>` supplies nothing either,
  and its only occurrence in `zero-vim.c` was its own `#include` line, whim having
  removed the conversion layer and left it. And "79,599 lines and 16 directives" is
  **79,598 lines and 15**: the typedef sits between two blank lines and one of them
  goes with it, which is five lines and not four, and the header count was short by
  the one it missed. As built the phase takes **six**, because phases 14 and 15
  emptied `<string.h>`, `<ctype.h>` and `<wctype.h>` first — **eighteen directives to
  twelve** — and its evidence is a `cmp`: 805,544 bytes either side, both built with
  `SOURCE_DATE_EPOCH=0`. `ZERO-GOAL.md`'s charter now says a phase may remove a
  directive and may not add one.
* ~~**the clock.**~~ **BUILT, AS ZERO PHASES 28 AND 32, AND THE LAST CLAUSE IS WRONG.**
  It took two phases and not one, the elapsed-milliseconds clock crossing as
  `long musl_now_ms(void)` and the wall clock as `long host_time(void)` — and neither
  **frees** anything. `gettimeofday` and `time` are both still in `nm -u`, because a
  symbol leaves when its last *caller* leaves the **file** and both callers moved to the
  other side of a boundary inside one translation unit. What the core no longer does is
  *name* either one; the bullet predicted a symbol count and what it bought was a place.
  The undo message is still the one nondeterminism the corpus has to scrub (§2e) — **and
  the scrub does not close it**, which zero phase 40 measured: the leak is arithmetic on
  the scrubbed text's *width*, an undo reporting its age and the editor then positioning
  the cursor to clear the line, so `0 seconds ago` emits `\033[24;40H\033[K` and
  `1 second ago` emits `\033[24;39H`. Phase 40's own records count `\x1b[?25h` redraws
  instead of digesting the stream, and carry a clock control as the evidence; the other
  106 records still digest, and closing that is expensive rather than hard — the
  `--- stream` line is named in **eighty files**, forty-seven times in zero phase 12's
  check alone.

### 4a. The surviving libc, by reason

**MEASURED after zero phase 13, and this table was wrong twice and short by one.**
**`isatty` is missing from it and survives**, with three call sites —
`mch_check_win`'s `isatty(1)`, `mch_get_shellsize`'s `!isatty(fd) &&
isatty(read_cmd_fd)` and `fill_input_buf`'s `!did_read_something &&
!isatty(read_cmd_fd)` — so it belongs in the terminal row, making that row ten.
**`fputs` is missing from "gcc's own"**: the source names it nowhere and `nm -u`
still lists it. The predicted total of **60 is 61** (62 as `tools/symbols.sh`
counts, which compiles plain `-O0` and so adds `__stack_chk_fail` that zero's
`-fno-stack-protector` removes). Every other row is confirmed symbol for symbol.
Both corrections are in the table below.

**AND THEN FOUR OF ITS ROWS STOPPED EXISTING.** Zero phases 14 and 15 are *no musl
dependencies* for the half of the charter that is pure computation: the four rows
struck through below — strings and memory blocks (17, `sprintf` among them),
character classes (7), numbers (2), sorting and searching (2) — are **28 symbols that
are now `static` definitions inside `zero-vim.c`**, and `sprintf` went onto the
editor's own `vim_snprintf` rather than being copied. `nm -u` is **33** with zero's
flags (34 as `tools/symbols.sh` counts). What is left is six rows and not one of them
is a function of its arguments alone: every surviving symbol asks the operating system
something, which is the line this table was always trying to draw.

| why | symbols |
| --- | --- |
| **the terminal** (the whole of the host boundary that is left) | `read` `write` `close` `dup` `ioctl` `select` `tcgetattr` `tcsetattr` `nanosleep` **`isatty`** |
| **messages before and after the screen** | `printf` `fflush` `stderr` |
| **memory** | `malloc` `free` `realloc` |
| ~~**strings and memory blocks**~~ *(phase 14)* | ~~`memchr` `memcmp` `memcpy` `memmove` `memset` `strcasecmp` `strcat` `strchr` `strcmp` `strcpy` `strlen` `strncasecmp` `strncmp` `strncpy` `strpbrk` `strstr` `sprintf`~~ |
| ~~**character classes**~~ *(phase 15)* | ~~`isalnum` `iscntrl` `ispunct` `tolower` `toupper` `towlower` `towupper`~~ |
| ~~**numbers**~~ *(phase 15)* | ~~`atoi` `atol`~~ |
| ~~**sorting and searching**~~ *(phase 15)* | ~~`qsort` `bsearch`~~ |
| **time** | `time` `gettimeofday` |
| **signals and exit** | `sigaction` `sigaddset` `sigemptyset` `sigismember` `sigprocmask` `kill` `raise` `getpid` `exit` `_exit` |
| **gcc's own** | `__errno_location` `fputc` **`fputs`** `fwrite` `putchar` |

### 4b. What is still file-shaped afterwards

Almost nothing, and the residue is nameable:

* **`read`/`write`/`close`/`dup` on fds 0, 1 and 2.** After P8 there is no `open`,
  so the process cannot acquire a fourth descriptor — an invariant a phase check can
  assert mechanically (no `open`/`creat`/`openat`/`mkdir`/`rename`/`unlink`/
  `readlink`/`opendir` in the source, and none in `nm -u`). **It is asserted from
  zero phase 10 on**, which is where the last of them went: `access fcntl open` at
  phase 9 and `getcwd stat strerror` at phase 10, and phase 10's check requires all
  eleven to be absent from `nm -u` while `read close dup fsync` stay.
  **Zero phase 13 makes it stronger and it is right rather than merely holding**:
  there is no stdio stream either. `FILE` is not named in `zero-vim.c` at all (2 → 0)
  and `fclose getc putc fsync` are gone, so the invariant names `fopen fdopen fclose
  getc putc fsync` beside `open creat openat stat access fcntl getcwd strerror
  opendir` — and phase 13's check asserts every one of them absent from **both** the
  source and `nm -u`. The core can read, write, close and dup fds 0, 1 and 2 and
  nothing else.
* **Nothing phases 14 to 16 did touches this.** Those three free 28 symbols and
  remove six headers, and not one of the 28 and not one of the six is file-shaped:
  their checks state the surviving set as a `cmp`, so a file symbol *arriving* would
  fail as loudly as one leaving. Two of the six headers are the ones a file-opening
  core would have needed — `<sys/stat.h>` and `<fcntl.h>` — so from phase 16 the
  invariant is visible in the directive list as well as in `nm -u`.
* **`time()` and `gettimeofday()`.** `vim_time()` feeds undo's *"1 second ago"* and
  the command-line history's timestamps; `gettimeofday` times `:sleep`, the bell,
  key timeouts and OSC replies. The undo message is the one nondeterminism the
  corpus has to scrub (§2e), which is a hint: *"the editor stops asking what time
  it is"* is a phase, and it frees `time`. Not in this plan.
* **`exit`/`_exit` and the signal set.** whim's Phase 26 argued five signals are
  the minimum; a core that does not own the process wants none of them, and that is
  the host's business rather than a filesystem question.
* **The swap file's BOOKKEEPING outlived the swap file by twenty-nine phases**, and
  that is the residue this section did not name because no tool could see it. Every
  syscall went at 6 to 13 and the memline went on keeping a header block with the
  editor's version and the buffer's name, a translation table for blocks not yet
  written out, a three-valued dirtiness and a record of where each block's lines used
  to be — **all of it written and none of it read**, which is exactly the shape
  `tools/deadfields.py` cannot report (it matches a field named nowhere outside its
  own type) and gcc has no warning for. Zero phase 42 took it, naming every field
  itself, and measured the negative half as phase 9's kind — four markers on the
  negative-block island fire in **0 of 252 records** against a control of identical
  shape firing 2,141 times — and the block-zero half as phase 12's, three markers
  firing in 227, 214 and 227 records with two full recordings byte-identical anyway.
  **The lesson generalises past this phase: an invariant asserted over `nm -u` and
  over the source's *calls* says nothing about state that is merely maintained.**

### 4c. Toward the host boundary — a sketch, not a plan

Once argv is two options and nothing is loaded or saved, `main()` is a few lines of
terminal setup, a size query, and `vim_main2()`.

**THERE IS NO SPLIT INTO TWO FILES. IT IS ONE FILE WITH TWO PARTS, AND THE FIRST
`#include` IS THE BOUNDARY** — the user's design, 2026-09-18, replacing both earlier
readings of this section:

```
zero-vim.c   upper part   the core editor.  NO PREPROCESSOR SYNTAX AT ALL.  At its
                          top, the musl_-prefixed prototypes: its calls to the host.
             ----------   the first #include IS the boundary, and nothing else marks it
             lower part   the host.  The #includes, then the musl_ definitions,
                          host_exit, host_message, and main().
```

Everything stays `static` except `main`, which lives in the lower part. **When the
project concludes the product is the upper part**, taken up to and not including the
first `#include` — so the file that goes to the next repository is a *prefix* of this
one, extracted by a rule with no judgement in it.

This dissolves the problems the two-file version created rather than solving them,
and each was measured before the design was taken:

- **The boundary needs no marker.** It is a directive that has to be there anyway.
  No comment — which the no-comments rule forbids — no sentinel declaration, no data
  file naming the boundary functions.
- **"Nothing is global but `main()`" survives untouched**, because there is still one
  translation unit. `tools/phasecheck.sh`'s `grep -v '^main$'` and
  `tools/funcreach.py`'s `{'main'}` root need no change, and the 130 implementation
  keys that changing `phasecheck.sh` would have moved are not spent.
- **The dead-code sweep survives intact.** One translation unit means
  `-Wunused-function` stays a boolean and `funcreach.py`, `typereach.py` and
  `deadsweep.py` work exactly as they do today. MEASURED that the two-file version
  would have broken this: `funcreach.py` on `editor.c` alone deletes **49 functions
  and 1,080 lines** — the editor's whole startup — because its root is `{'main'}` and
  `main` leaves; and `-Wunused-function` is blind to a dead *external* function, so
  none of `-flto`, `-fwhole-program` or a plain `cat` recovers it.
- **No tool changes at all.** `PSOURCE`, `zero.mk`'s single `tar -xO`, `score.sh`,
  `symbols.sh`, `sweep.sh`, `zerodelta.sh` and `zrecord.sh` all keep working on one
  file, and the eleven files a split would have had to teach about two products stay
  as they are. Two planned phases — a tooling phase and a join/split tool pair — drop
  out entirely.
- **The build stays one `gcc` invocation.**

**The check that falls out of it is stronger than anything the two-file design had:
cut the file at the first `#include` and compile the upper part with
`-fsyntax-only`.** It must pass with no diagnostics, which proves the core is
header-free and self-contained — and it cannot pass vacuously, because a core still
needing a header fails loudly.

**`NULL` becomes `nullptr`, and there is nothing to declare.** Settled by the user,
2026-09-18, in place of an earlier `enum { nil = 0 };` which this supersedes
entirely. `nullptr` is a **C23 keyword**, and gcc here defaults to C23 — MEASURED,
`__STDC_VERSION__` is `202311L` — so the core needs no declaration, no enumerator and
no line at all for it. That is consistent with what the file already relies on: `enum
: long` and `static_assert` are both C23 and both already load-bearing here.

**It also disposes of the varargs hazard rather than managing it.** An enumerator
with the value 0 is a null pointer constant everywhere *except* a variadic argument,
where it would pass a four-byte `int` to a callee reading an eight-byte pointer with
no warning from gcc — measured. `nullptr` is typed: MEASURED,
`sizeof(nullptr) == sizeof(void *)`, so a variadic argument is pointer-sized and the
rule the phase would otherwise have had to prove and then assert for ever — *no bare
null constant inside a variadic argument list* — is not needed at all.

**`size_t` becomes `usize`, derived rather than asserted:
`typedef typeof(sizeof(0)) usize;`.** Settled by the user with the same message.
`typeof` is C23 and `sizeof(0)` has type `size_t` by definition, so this *is* `size_t`
on any target — MEASURED with `_Generic((usize)0, size_t: 1, default: 0)`, which holds,
so the two are the same type and not merely the same width. The alternative that was
on the table, `typedef unsigned long size_t;`, is correct on this target and silently
wrong on one where `size_t` is not `unsigned long`; this spelling cannot be. The
distinct name keeps the core from shadowing a name libc typedefs again below the
boundary, and nothing outside forces libc's spelling any more, the vendored
`musl_mem*`/`musl_str*` signatures being the core's own since phases 14 and 15.

**THE CORE IS OPTIMISED FOR TRANSPILATION, NOT FOR PERFORMANCE, AND SO IT MAY NOT
DEPEND ON LATENT COMPILER BEHAVIOUR.** The user's rule, 2026-09-19, and it governs
the phases still to come. The core is a text that another runtime will read; what
matters is that its meaning is on the page, not that gcc happens to compile it well.
Where the two conflict, the page wins — `-O0` was already that trade made once, and
this is the same trade made about *semantics* rather than speed.

It has teeth. `abs` and `labs` were called by the core and **never appeared in
`nm -u`**, because gcc lowers both to inline arithmetic — nothing in the language
promises that, and a compiler that emitted calls would silently have added two libc
symbols to a file whose whole claim is the shortness of that list. Vendoring them as
`musl_abs`/`musl_labs` removes the dependence, and MEASURED it frees no symbol at all:
the phase's value is that the core stops relying on something no standard states.

**It does not follow that every compiler-specific spelling must go, and one measured
case argues the other way.** All nine `__builtin_offsetof` uses in the core are
runtime expressions — `alloc(offsetof(T, tail) + len)`, pointer arithmetic, one
division — and MEASURED, none sits where an integer constant expression is required,
so the plain-C form compiles and agrees:

```c
(usize)&(((struct T *)0)->b)      /* "standard" C, and a null-pointer trick */
__builtin_offsetof(struct T, b)   /* a gcc token, and unmistakable */
```

The first only *looks* portable: it is a null dereference by the letter of the
standard, and a transpiler must pattern-match it out of ordinary pointer arithmetic —
failing silently into plausible nonsense if it does not. The second is one token with
two arguments that a reader of the text can special-case by name. For a target that
has no struct offsets at all, the explicit spelling is the safer one, so the builtin
stays and this paragraph is the reason. The rule is *do not depend on behaviour
nothing states*, not *avoid every extension*.

By that reading the core is clean. `typeof`, `nullptr`, `static_assert`, `enum : T`
and `[[fallthrough]]` are C23 and stated. The only `__attribute__` above the boundary
are `format_arg` on `_()` and `NGETTEXT` and `format(printf, 3, 4)` on `vim_snprintf`
— pure diagnostics that generate no code and that a transpiler drops. And
`__builtin_setjmp`/`__builtin_longjmp` are **below** the boundary, in the host, which
is where platform-specific code is allowed to live and the reason phase 19's choice
was acceptable.

**MEASURED, the size of what is left to do.** Moving the eleven `#include`s down to
just above the host block leaves a core of **79,928 lines** and a host of **235**,
and the compile gives **660 errors, every one of them a libc type or macro the core
takes from a header**: `size_t` 263, `va_list` 11 — which zero phase 22 has since
taken to 8, in four functions that all go below the boundary, so the core declares
nothing for it — `INT_MAX` 8, `time_t` 5, `sig_atomic_t` 5, and `NULL`. Giving the
core its own declarations for those is the whole of the remaining work, and it is the
same work the two-file version needed — the difference is everything else it was
going to cost.

The executable is still `zero-vim` and `argv[0]` is unchanged, so no harness moves.

The three steps that get there, in the order their measurements suggest: demote
`main()` to `vim_main(void)` and give the launcher the four calls `common_init_1`,
`common_init_2`, `termcapinit`, `screenalloc` now make; replace `mch_write`/
`fill_input_buf` with two function pointers the launcher installs (that is the
whole of `read`/`write`/`dup`/`close`); and move `mch_get_shellsize`,
`mch_settmode` and the signal handlers across, which takes `ioctl`, `tcgetattr`,
`tcsetattr`, `select`, `nanosleep` and the nine signal symbols with them. What is
left in the core after that is the fifth and sixth rows of §4a's table — strings,
memory and arithmetic — plus `printf` for the messages that appear before there is a
screen, which is itself a question for the host.

**THAT LAST SENTENCE CAME TRUE EARLY AND FROM THE OTHER DIRECTION.** The rows it
expected to be left in the core — strings, character classes, numbers and sorting —
are **gone from `nm -u` already**, taken by zero phases 14 and 15 *before* the
launcher was written: they are `static` definitions in `zero-vim.c` now, which is
where this section wanted them, reached by moving code in rather than by moving
`main()` out. So the arithmetic in the destination above is done and what is left of
§4c is exactly the three steps: `main()`, the two stream calls, and the terminal with
its signal set. After them the core's undefined set would be `malloc free realloc`,
`time gettimeofday`, `exit _exit` and gcc's five — and `printf`, still the open
question this section named.

**THE FIRST OF THE THREE IS DONE, AND THE ARITHMETIC ABOVE IS ONE SYMBOL OUT BECAUSE
OF IT.** Zero phase 18 demoted `main()` to `static int vim_main(int argc, char **argv)`
and put a launcher of its own at the bottom of the same file, and zero phase 19 gave
the core a `static void (*vim_host_exit)(int)` that `vim_main()` installs and
`mch_exit()` calls where `exit(r);` used to be. So `exit` and `_exit` are BOTH already
out of the list this section expected to be left with — `_exit` at phase 17, `exit`
here — and the launcher jumps with `__builtin_setjmp`/`__builtin_longjmp` rather than
`sigsetjmp`, because measured on this tree the library spelling costs two undefined
symbols and a thirteenth `#include` where the builtin costs nothing, and because the
signal mask the process ends with is UNCHANGED by the builtin and would have been
changed by `siglongjmp` (`exit()` was always called from inside the handler with the
handled signal blocked). What is left of §4c is the two stream calls and the terminal
with its signal set.

**One fact for whoever writes `editor.c`, measured at phase 16 and recorded nowhere
else.** The twelve `#include`s that survive are not twelve independent dependencies.
`select`, `gettimeofday`, `fd_set`, `FD_SET`, `FD_ZERO`, `FD_ISSET`, `struct timeval`
and every `*_MAX` reach `zero-vim.c` through **no header it names**: they arrive
transitively, from `<sys/param.h>` — whose own contribution is `MIN` and `MAX` —
through musl's `sys/resource.h` → `sys/time.h` → `sys/select.h`, measured with `gcc
-E -H` and with one probe per identifier against each of the eighteen. A host that is
not musl needs `<limits.h>`, `<sys/time.h>` and `<sys/select.h>` written in. Phase 16
recorded it rather than repairing it, because repairing it means adding directives and
the charter forbids that; the failure it leaves is loud — the build stops — which is
the acceptable one.

#### What "no preprocessor syntax at all" costs, measured on the file as it stands

The split is not "move `main()` out". A file with no directives has no libc **types**
and no libc **constants** either, and `zero-vim.c` names a great many of both. Counted
with `grep -owc` on the 80,413-line file:

| what it is | from | mentions |
| --- | --- | --- |
| `va_list` `va_start` `va_arg` `va_end` | `<stdarg.h>`, three of them **macros** | 15, 8, 21, 10 |
| `offsetof` | `<stddef.h>`, a **macro**, and the only thing holding that header | 9 |
| `size_t` / `NULL` | `<stddef.h>` | 430 / 2,564 |
| `MIN` / `MAX` | `<sys/param.h>`, **macros** | 7 / 16 |
| `SIZE_MAX` / `uintptr_t` | `<stdint.h>` | 1 / 1 |
| `errno` | `<errno.h>`, a **macro** for `*__errno_location()` | 3 |
| `EXIT_FAILURE` | `<stdlib.h>` | 1 |
| `struct termios` `struct winsize` `struct timeval` `struct timespec` | the terminal and the clock | 4, 1, 6, 1 |
| `sigset_t` `struct sigaction` `sighandler_T` `SIGHUP`… | `<signal.h>` | 1, 3, 5, … |
| `fd_set` `FD_SET` `FD_ZERO` `FD_ISSET` `TIOCGWINSZ` | `select` and `ioctl`, four of them **macros** | 6, 2, 3, 1, 1 |

So the rule forces a stronger interface than it first appears to ask for: **no libc
type may cross the boundary, only scalars.** `musl_get_winsize(int *rows, int *cols)`
rather than `ioctl` with a `struct winsize`; `musl_set_raw(int on)` rather than
`tcgetattr`/`tcsetattr` with a `struct termios`; `musl_wait_for_input(int ms)` rather
than `select` with an `fd_set` and a `struct timeval`. That is more work than a rename
and it is the right shape anyway — **it is also exactly what makes the file
transpile**, since a JVM target has no `struct termios` either. `size_t` and `NULL`
become a typedef and a constant `editor.c` declares for itself; `offsetof` becomes
`__builtin_offsetof`, which phase 16 already measured leaves `<stddef.h>` dead.

**`va_list` was the one with no scalar workaround, and it is settled: the variadic
layer goes to the host.** Decided by the user on 2026-09-18, against the alternative
of `__builtin_va_list` in `editor.c` — which keeps the letter of the rule, since it
needs no header, but puts a gcc extension in the one file whose point is to be plain
C, and which is the hardest thing here to transpile: a `va_list` walk is type-driven
at run time by the format string, where Java varargs hand you an `Object[]`. The
option that looks worse by this repository's own vendoring principle — a formatter is
pure computation, and phases 14 and 15 established that what the file can compute it
computes — is the one that actually transpiles, and that is what the split exists to
serve. The inconsistency is real and is recorded here rather than glossed.

**From the core side it costs one prototype**, because a *caller* of a variadic
function needs no header at all: `...` is C syntax and only the callee that walks the
list needs `va_list`. MEASURED — `int musl_snprintf(char *, unsigned long, const char
*, ...);` followed by a call compiles `-Wall -Wextra` clean with no directive of any
kind.

**What it costs the core is that the eight wrappers cannot survive**, because C cannot
forward `...` — which is exactly why `vsnprintf` exists beside `snprintf`. MEASURED,
the functions that call `va_start`: `smsg`, `smsg_attr`, `smsg_attr_keep`, `semsg`,
`siemsg`, `vim_snprintf_add`, `vim_snprintf`, `vim_snprintf_safelen`, with
`vim_vsnprintf` and `vim_vsnprintf_typval` taking a list, the latter **734 lines**.
Each wrapper's call sites become two statements — `semsg("E123: %s", x)` into
`musl_snprintf(IObuff, IOSIZE, "E123: %s", x); emsg(IObuff);`, the same buffer they
already use. Counts: `semsg` ~94, `vim_snprintf_safelen` ~11, `smsg` ~10, `siemsg`
~10, the rest ~3, and `vim_snprintf`'s ~66 sites are a pure rename. About **130
sites**.

**It splits into two steps, and the first of them is DONE — zero phase 22.** The
wrapper expansion ran in one translation unit against the core's own `vim_snprintf`,
taking `va_start` from eight functions to one; the reorganisation then puts the
remaining variadic functions below the first `#include`, and above it there is only
the prototype. The first step's declared delta was nothing at all and was checked as
a byte-identical recording, which is a much stronger position to make the mechanical
edits from than making them while the file is being rearranged.

**As built, and two corrections the phase forced on the paragraph above.** It was
**129** sites, not ~130, and the split by wrapper is `semsg` 94, `vim_snprintf_safelen`
11, `smsg` 10, `siemsg` 10, `smsg_attr` 2, `smsg_attr_keep` 1, `vim_snprintf_add` 1.
And **four functions still hold a `va_list`, not three**: `vim_snprintf`,
`vim_vsnprintf`, `vim_vsnprintf_typval` and **`skip_to_arg`**, the positional-argument
walker, which this section had missed. All four go below the boundary.

**The counts in the table above are now the INPUT figures, not the tree's.** After
phase 22: `va_start` 1, `va_list` 8, `va_end` 3, `va_arg` 21 unchanged. And under the
one-file design nothing "moves to the host" in the sense of leaving the file — the
four functions end up below the first `#include`, in the same translation unit, which
is why the phase freed no symbol and asserted that as an equality.

**The split necessarily ends "nothing is global but `main()`" — and replaces it with
a named list rather than with nothing.** The user's constraint, 2026-09-18: *"of
course we need to introduce some global functions for the interaction between host
and editor, but keep it minimal as necessary."* So the invariant generalises instead
of lapsing. Today's check is `nm --extern-only --defined-only` giving exactly `main`;
afterwards it is **exactly the enumerated boundary and nothing else** — `vim_main`
out of `editor.c`, and the `musl_` set out of `zero-vim.c` — with any name not on the
list a failure. That is a stronger check than the one it replaces, because the list
has to be *written down and argued for* rather than being the single name a linker
happens to need, and every future phase that wants to add to it has to say so.

Two consequences of keeping it minimal, both worth settling before the split rather
than during it. **The boundary should be counted, not just listed**: the 33 symbols
`zero-vim.c` has now are not the same as the number of `musl_` prototypes it will
need, because several collapse — `tcgetattr` and `tcsetattr` become one `musl_set_raw`,
`select` with its `fd_set` becomes one `musl_wait_for_input`, `sigaction`/`sigprocmask`/
`sigemptyset`/`sigaddset`/`sigismember` become a flag the host sets and the editor
reads. Fewer, wider calls in plain scalars is both the minimal set and the
transpilable one. And **the `exit` decision simplifies**: the host callback chosen
while everything was still one file — a `static void (*vim_host_exit)(int)` installed
through a parameter, which named no symbol at all — can become a plain `musl_exit(int)`
prototype once there are two translation units. The function-pointer indirection was
there to avoid a global; with a declared boundary the global is the honest spelling.
Two translation
units mean `vim_main()` and every `musl_` the host provides have external linkage by
construction. Two tools hard-code the old invariant — `tools/phasecheck.sh:64`'s
`grep -v '^main$'` and `tools/funcreach.py:127`'s `{'main'}` root — and the cost of
touching the first was measured while reviewing `exit`: **one appended line to
`phasecheck.sh` moves 118 implementation keys**, 12 whim stages, 82 whim edits, 12
zero units and 12 zero edits, and no slim key. That is the argument for doing
everything that can be done *while the launcher still lives at the bottom of the
single file*, and splitting once, late.

One smaller consequence: each pipeline's product rule extracts **one** file from the
last boundary's tar (`zero.mk`, and the same shape in `slim.mk` and `whim.mk`). After
the split zero has two, and `make score`, the file census and `zero-pass`'s flags
check all assume one product per pipeline.

### 4d. What a JVM target cannot express, measured on the core as it stands

§4c's rule is *the core is optimised for transpilation, not for performance*, and the
question that rule implies has been asked of the cut `make editor.c` writes: **which
constructs in the 76,687 lines would a JVM port have to be told about, rather than
translate?** Three answers, and they are of very different sizes.

**THE LARGEST OF THE THREE IS GONE, AS ZERO PHASES 43, 44 AND 45.** When this section
was written the memline page was 34 + 45 + 14 mentions of three constructs a JVM cannot
express at all, and it dominated every other finding by an order of magnitude. Measured
on the phase 45 core, each of those counts is now **zero**:

| | phase 39 core | phase 45 core |
| --- | --- | --- |
| `db_index[1]`, declared length 1 and indexed to the line count | 34 | **0** |
| `pb_pointer[1]`, the same idiom | 45 | **0** |
| interior pointers of the shape `(char_u *)dp + start` | 14 | **0** |
| `DB_MARKED`, the top bit of an offset stolen as a flag | 17 expressions | **0**, a real field |
| `memfile` / `mf_*` | the whole layer | **0** |
| `__builtin_offsetof` above the boundary | 9 | **6** |
| right-shift operators | 65 | **59** |

**The rewrite was allowed at all because `DATA_BL` had stopped being a disk format**,
which is the correction this bullet most needed before it could be acted on. There was no
file to write a page to — zero phases 6 to 13 took every one — so the layout carried no
compatibility constraint and the lines→tree move was free to choose any representation it
liked. That is the **opposite** of `slim-vim.c`, where `tools/deadfields.py` refuses while
`ml_recover()` exists precisely because block zero and the memfile's pages *are* a disk
format there.

What replaced them is five struct definitions a port can read straight off:

```c
struct block_hdr     { short_u bh_id; };
struct pointer_entry { bhdr_T *pe_block; linenr_T pe_line_count; };
struct pointer_block { bhdr_T pb_hdr; short_u pb_count; PTR_EN pb_pointer[PB_COUNT_MAX]; };
struct data_line     { char_u *dl_text; colnr_T dl_len; char dl_marked; };
struct data_block    { bhdr_T db_hdr; linenr_T db_line_count; DATA_LN db_line[DB_LINE_MAX]; };
```

Every array has the length it was given, `PB_COUNT_MAX` is 255 and `DB_LINE_MAX` 64, a
child is a **reference** and not an integer key into a side hash table, and a line's text
is its own allocation whose lifetime is the process's. **Three `static_assert`s hold the
arithmetic in place**, including `PB_COUNT_MAX == (4096 - 8) / sizeof(PTR_EN)`, which
fails to compile if anything narrows the entry.

**What a port still has to be told about the memline is one thing and it is small**: the
node is **tagged, not subclassed**. `bhdr_T` is the first member of both node types, so
`(PTR_BL *)hp` and `(bhdr_T *)pp` are the same address and `bh_id` says which it is, at
**23** cast sites in the core. On a JVM that is two classes and a common supertype, or a
sealed pair, and the cast becomes a type test — a translation the porter has to *choose*
rather than one the C forces. That is the difference from what was here before, where
there was no translation to choose at all.

**Four smaller instances of the `[1]` idiom survive, and they are a different and much
easier shape.** `bt_regprog_T.program[1]`, `buffblock_T.b_str[1]`, `hlname_T.hn_key[1]`
and `msgchunk_T.sb_text[1]` are each a trailing `char_u` array allocated with
`alloc(__builtin_offsetof(T, member) + len + 1)` — six `offsetof` sites between them.
**None of them reads an offset back as an interior pointer and none steals a bit**, so
each is a plain "struct plus a variable-length byte string", which on a JVM is a field
holding a `byte[]`. **One of the four does do a `container_of`**, and that is the piece
to name rather than let a reader discover: `hlname_T` is recovered from a pointer to its
`hn_key` member by subtracting the `offsetof`, at two sites — `hi_key -
__builtin_offsetof(hlname_T, hn_key)` — which a JVM has no expression for at all and
which a port turns into a back-reference or an index.

**And one construct is unchanged and is now the largest of its kind left**: the regexp
backtracking stack builds typed pointers into a byte buffer at a computed byte offset,
`rp = (regitem_T *)((char *)regstack.ga_data + regstack.ga_len);`, at **three** sites
that build one and one more that compares against it. It is a growarray used as a stack
of **variable-sized** records, and a port has to give it a representation of its own
exactly as the memline page needed one. Three sites is a different order of work from the
memline's 93, and nothing in the pipeline has touched it.

**Two porter notes that are the opposite finding**, recorded because each looks like a
hazard and measures as nearly none:

* **`>>` is almost a non-issue.** The cut has **65** right-shift operators, 63 `>>` and
  two `>>=`. **45 carry an explicit `(unsigned)` cast at the shift itself** —
  `(unsigned)(c) >> 3`, `((unsigned)(-(key)) >> 8) & 0xff` — six more are the `~0u`,
  `~0ul` and `~0ull` of the limit enumerators, and the rest are on `long_u`, `hash_T` or
  `uvarnumber_T`. **Exactly three are on a signed operand**, and all three mask
  immediately afterwards: two in `blend_cterm_colors()` on `int default_rgb`
  (`(default_rgb >> 16) & 0xFF`) and one in `mf_hash_grow()` on `blocknr_T mhi_key`,
  which is `long`. So Java's `>>` versus `>>>` decides three expressions in the whole
  core, and in each the `& 0xFF` or `& (MHT_GROWTH_FACTOR - 1)` makes the two agree
  anyway.

  **Re-measured on the phase 45 core it is 59 and TWO**, and the one signed shift that
  went is the memline's: zero phase 43 deleted `mf_hash_grow()` with the hash table, so
  the only signed shifts left are `blend_cterm_colors()`'s pair, both masked with
  `& 0xFF`. **All six of the shifts that went belong to the swap file and the memfile** —
  three in the memfile hash, taken by phase 43, and three in `long_to_char()`, taken with
  block zero by phase 42 — which is the shape of every finding in this section: the
  constructs a port has to be told about were concentrated in the layer the pipeline was
  always going to rewrite.
* **`%` is NOT**, and a Clojure port must use `quot` and `rem` rather than `/` and
  `mod`. C's `%` takes the sign of its left operand; Clojure's `mod` is the floored
  modulus and is never negative for a positive divisor. `ex_history()` relies on the C
  rule and compensates for it by hand, at two adjacent sites:
  `hist[(hislen + j + idx + 1) % hislen].hisnum` **adds the modulus first** precisely
  because `j` is negative there. Under `mod` the bias is applied twice; under `rem` the
  line means what it means today.

**The core uses no floating point at all**, which is the third answer and the one that
costs a port nothing: it is why nothing above needs to say anything about rounding
modes, `strtod` or a soft-float library. It is met **by construction** and not by any
phase — the configuration is `tiny`, which has no `+float`, and whim removed the eval
layer `float_T` belonged to — and `CLAUDE.md` states it as a tree invariant with what
was measured.

## 5. Decision points

**Four are settled** (the user, 2026-09-17), and they are marked SETTLED below: 1 and 2
(record the per-redraw screens *and* the stream digest), 3 (add the `screen-moved` and
`stderr-moved` tokens), 5 and 6 (drop `'readonly'` with `W10` and `[RO]`, and delete the
`:file` row, keeping `CTRL-G`), and 8 (lower the row floor deliberately, in the phase
that crosses it). The rest stand as recommendations.

1. **SETTLED — what the corpus records.** Both the per-redraw screens, for reading and diffing, and
   the stream's sha256 as a tripwire beside them. The screens are what a human
   reads in a failure; the digest catches a redraw that draws the same result
   differently, which a phase should have to declare.
2. **SETTLED — per-redraw snapshots**, not only the last screen. It is what makes the message line recordable at all (§2c), it costs
   166 KB for 102 cases, and it localises a failure to a keystroke.
3. **SETTLED — `pipes/zero.delta` gains tokens for "everything moved"**: `screen-moved` and `stderr-moved`, in the shape of
   whim's `term-moved`. Measured: P2 moves all 102 records by one stderr line, and
   a `'ruler'` change would move all 102 screens. Listing 102 case names to say
   "the status line changed" is a list, not a check.
4. **Is the Ex-command sweep worth keeping in pty-less form?** Recommendation:
   **yes, and it is now better** — 111 commands, 6.3 s, four identical runs, and it
   records the *message* where the file sweep recorded only an exit status (§2i).
   It is also the only instrument that would notice a command silently changing
   which error it gives.
5. **SETTLED — `'readonly'` goes.** Drop the row in P11 with its `W10`
   warning and `[RO]` indicator: after P5 nothing can be written, and nothing but
   `:set ro` can set it. `'modifiable'` (a real protection) and `'modified'` (state
   a host wants) stay. **Done at zero phase 12 and confirmed by measurement**: the
   premise held — `b_p_ro` had ten mentions and `:set ro` was the only thing that
   could set it — and `'modified'` stays for a second reason this decision does not
   give, that `tools/dropoptions.py` refuses a `PV_BUF` row. `'readonly'` turned out
   to have **two** `[RO]` indicators, `fileinfo()`'s and `win_redr_status()`'s, and
   the W10 warning ended in a one-second `ui_delay`, which is the probe that shows
   the phase removing behaviour rather than a row. After it **nothing anywhere can
   mark a buffer read only**, and `'modifiable'` is the protection that remains.
6. **SETTLED — `:file` goes, `CTRL-G` stays.** Keep `CTRL-G` as buffer info
   (`[No Name]`, the line count, the percentage) and **delete the `:file` row**,
   which exists to rename. `fileinfo()` shrinks rather than going.
7. **`--More--` and the Press-ENTER prompt.** Recommendation: **keep both** and
   record them (`hit_enter`, `:highlight`). They are how the editor behaves when a
   message does not fit, and a phase that removed them would be removing screen
   behaviour, which decision 3 protects.
8. **SETTLED, AND DONE — row deletion crosses `create_cmdidxs.py`'s 100-row floor** (111 − 12 = 99), and the floor is lowered **to 80 in the phase that crosses it**, in the
   same commit, with the reason in the tool's docstring — and never silently.
   *Done as zero phase 8*, which took the table 104 → 99. Measured: the old floor
   failed with `no command table found in either shape` rather than a count, and the
   edit moved **28** implementation keys — 6 whim stages, 15 whim edits, 2 slim
   phases and 5 zero phases — every one of which still reproduces its boundary under
   `make whim-verify` and `make slim-verify`.
9. **`ME_TOO_MANY_ARGS` and the parallel `main_errors[]` table.**
   Recommendation: delete the row and the enumerator together in P4, with the
   DWARF before/after check (§P4). The alternative — leaving an unreachable row —
   is the "concept the table has and the code does not" that whim's Phase 18
   argued against.
10. **The five pty scenarios.** Recommendation: **keep them**, and reduce them to
    what only a terminal shows: the window size from `TIOCGWINSZ`, raw mode
    entered and restored, and one arrow-key scenario as a second opinion on
    `nvidxcheck.py`. **As built it is four and now five**, and the fifth is the
    counter-example to the reduction: `sel_arrows` presses a **shifted** arrow, which no
    harness in any of the three pipelines had ever done, and it is the only thing that
    can see `keymodel=startsel` — a compiled-in default that had never worked in any
    build, because `set_options_default()` runs no callback and `km_startsel` exists
    nowhere but `did_set_keymodel()`. **A scenario set reduced to what a terminal shows
    is still only as strong as the keys it presses.**
11. **Do the corpus's seeds use `+set paste` or a typed `:set paste`?**
    Recommendation: **`+set paste` on the command line** for the option setup and a
    typed `:set nopaste` before the real editing — it works (measured), it keeps
    the cmdline echo out of the early snapshots, and it exercises decision 8's
    `+cmd` on every single case.
12. **Whether P2's `out_redir` fold needs its own case.** Recommendation: it has
    two (`ctrl_c_clean`, `ctrl_c_changed`), and they record an exit rather than the
    branch — which is honest, and better than a case that cannot fail.

## 6. Measured versus estimated

**Measured** (in `/tmp/zpty` and `/tmp/zfs`, against the committed source and
binaries built from it): every line number and function extent quoted; the 79
symbols and every call site of each; the 155-function/5,636-line reachability
result and its five intermediate steps; the freed-symbol sets; the 19-symbol
projection; the whole of §2 — eight identical corpus runs, four identical sweep
runs, three identical argv runs, the run under load, the `pyte` cross-check (88 of
88 screens and cursors), the pty-versus-stream comparison (92 of 92 final text
areas; 66 of 92 intermediate screens), the five deliberate breaks, the
`:set paste`/`nopaste` restoration table, the tty warnings and their 2.007 s delay,
the 6.4 s → 0.53 s corpus cost, `ex_ni`'s absence and the `static_assert` failure,
`:append` working through `getexline`, `vim -` hanging for 30 s, `:stop` stopping
the harness's shell, the version banner's build timestamp, and the `<ago>` padding
failure.

**Estimated**: the ≈700 lines the constant folds remove and the ≈80,300-line total;
the binary size after the cut (not attempted); the `apart` lines in §3c; and the
per-phase order costs, which nothing has run yet.

## Appendix: how the measurements were taken

Everything ran in this worktree (`.claude/worktrees/zeroplan`, branch `zero-plan`)
and in two scratch directories, and **no pipeline file, tool or phase program was
touched**. The binary under test is the committed `zero-vim.c` compiled with zero's
phase-1 line, `gcc -O0 -fno-stack-protector -static -no-pie -s` — 869,512 bytes, 79
undefined symbols, which is what `ZERO-GOAL.md`'s Phase 1 records.

* `/tmp/zfs` — the call graph. `graph.py` collects every function definition at
  file scope (the brace-at-column-0 shape, plus the `main` header split across two
  lines that `tools/funcreach.py`'s regex misses), what each body mentions, and
  which libc names it names; `sim.py` removes a set of entry points, recomputes
  reachability from the same roots `funcreach.py` uses, and reports functions,
  lines and freed symbols. 1,874 definitions, 186 roots.
* `/tmp/zpty` — the harness. `screen.py` (the emulator and the `?25h` snapshot
  rule), `zpty.py` (the pty driver, kept for the comparison), `zstream.py` (the
  stream driver), `corpus.py` (102 cases), `run2.py`, `exsweep_stream.py`,
  `argvcheck.py`, and the patched sources `b1.c`–`b8.c` for the deliberate breaks.
* The five breaks: `do_addsub` returning `FAIL`; one `nv_cmds[]` row deleted;
  `CTRL-G`'s `fileinfo()` call removed; `check_changed()` returning `FALSE`;
  `nv_Zet`'s `"x"` replaced by `"q!"`; `'ruler'`'s default flipped; and the
  warnings-and-delay-free build used for the 0.53 s timing.

Both scratch directories are temporary by design. What is durable is this document
and, once the phases are written, the programs and their recorded boundaries.
