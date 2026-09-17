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
9. **argv accepts `+{command}` and `-T {term}`, and nothing else.** `--` goes too:
   with no file argument it only means "treat the next `+cmd` as a file", which
   then errors.

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
| `check_changed()` returns `FALSE` (planned phase P10) | one line | **2**: `quit_modified` and `cmd_edit` (`:edit` answered E37 too); and 6 of 111 sweep rows — `edit enew ex quit view visual`, E37 → E32 or success |
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
* `tools/create_cmdidxs.py`'s `names()` **refuses a table with fewer than 100
  rows**, and it is what the command sweep enumerates. 111 − 12 = 99. **The floor
  has to be lowered deliberately, in the phase that crosses it**, or the sweep
  stops working with a message about a parse that cannot be right.

`nv_cmds[]` rows are the opposite: they are **pointed at `nv_error`, never
deleted**, and `tools/nvidxcheck.py` requires the precomputed index to stay a
permutation — §2g's fifth break is what happens otherwise.

### 3b. The eleven phases

| # | phase | removes | frees | delta in the new corpus |
| --- | --- | --- | --- | --- |
| 2 | nothing asks whether this is a terminal | the two warnings, `ui_delay(2005)`, `tty_fail`/`--ttyfail`, `stdout_isatty`, `mch_check_win`, `mch_input_isatty`, the four `isatty()` calls, `check_tty` | **`isatty`** | every record's stderr line (`stderr-moved`); measured on a patched build: 102 of 102 records move, each by one line, and the corpus goes 6.4 s → **0.53 s** |
| 3 | no streaming Ex | `-e -E -s -v`, `Q`, `gQ`, `do_exmode` (95 lines), `getexmodeline` (262), `silent_mode` (23 mentions), `exmode_active` (49 mentions, constant `FALSE`), `pending_exmode_active`, `s_vbuf`, `main_loop`'s `noexmode` | **`setvbuf`** (and the `stdout` reference) | `key_Q`, `key_gQ`; argv rows `-e -E -s -v` |
| 4 | argv is `+{command}` and `-T {term}` — **built, as zero phase 5** | the file argument and `buflist_add`, bare `-`/`EDIT_STDIN`, `--`, `ME_TOO_MANY_ARGS`, `had_minmin`, `read_cmd_fd`'s reassignment, and `params.edit_type` with `read_stdin()` | — | **as listed, plus `+q! f.txt`**: 79 lines, six argv rows, nothing else |
| 5 | no write | `:write :wq :xit :exit :update :saveas` rows, `do_write`, `buf_write` (622), `buf_write_bytes`, `check_overwrite`, `check_writable`, `check_mtime`, `not_writing`, `write_eintr`, `mch_setperm`, `mch_fsetperm`, `mch_nodetype`, `vim_fexists` — **17 functions, 905 lines** | `chmod fchmod fstat ftruncate lstat unlink` | `cmd_write`; sweep rows `write wq xit exit update saveas` (E32/E471 → E492) |
| 6 | no read | `:read`, and with it `do_bang`, `do_shell`, `do_filter`, `check_secure`, `prevcmd_is_set` — **+6 functions, +194 lines** | — | `cmd_read`, `read_cmd_gone`, `filter_gone`; sweep row `read` |
| 7 | no `:edit`, and no `gf` | `:edit :enew :ex :visual :view` rows (the Ex-mode escape has nothing to escape from after P3), `do_ecmd` (331), `do_exedit`, `ex_edit`, `grab_file_name`, `otherfile`, `nv_gotofile` and the `gf gF [f ]f` rows, `text_or_buf_locked`, `check_lnums*`, `prepare_help_buffer` — **+16 functions, +618 lines** | — | `cmd_edit`, `key_gf`; sweep rows `edit enew ex visual view` |
| 8 | nothing reads a byte | `readfile` (787), `read_buffer`, `read_stdin`, `read_eintr`, `readfile_linenr`, `filemess`, `msg_add_fname`, `msg_add_lines`, `msg_add_eol`, and `open_buffer`'s read arms | `open access fcntl` | none measured; probed by the argv record and by `startup` |
| 9 | the buffer has no name | `b_ffname`/`b_sfname`/`b_fname` (58/30/42 mentions), `setfname`, `buflist_new`'s naming, `otherfile_buf`, `buf_setino`, `buf_spname`, `shorten_*`, `home_replace*`, `fix_fname`, `vim_FullName`, `mch_FullName`, `mch_dirname`, `mch_isdir`, `mch_getperm`, `eval_vars` (242), `expand_filename` (132), `find_cmdline_var`, `get_spec_reg`'s `%`/`#`/CTRL-F/CTRL-P, `:file`, `get_trans_bufname`, `set_b0_fname`, `ml_upd_block0`, `ml_timestamp`, `check_changed_any`, the wildcard remnants | `stat getcwd strerror fsync` | `cmd_file`, `reg_percent`, `ctrl_g` (the name in the info line), `startup`/`ruler_move` if the status line changes; sweep row `file` |
| 10 | `:q` quits, `ZZ` is `ZQ` | `check_changed`, `no_write_message`, `no_write_message_nobang`, `nv_Zet`'s `:x` | — | measured: **`quit_modified`, `cmd_edit`, `zz_key`, and sweep rows `edit enew ex quit view visual`** |
| 11 | the options nothing reads | `'fsync'`, `'write'`, `'writeany'`, `'undoreload'`, and `'readonly'` by decision; `'shortmess'` and `'cpoptions'` letters that lost their readers. **`'paste'` is exempt and the phase says so** | — | none (`:set` is not swept); `tools/dropoptions.py --strict` refuses while a reader exists, which is the check |
| 12 | no `FILE *` that is never opened | `scriptin[]` (3739, never assigned), `redir_fd` (3777, never assigned), `ui_write`'s `console` (its only caller passes `FALSE`) | `fclose getc fputs putc` | none |

**Three rows are built, and the numbering is not the table's.** Row 2 ran as zero
phase 2, row 3 as zero **phase 4** and row 4 as zero **phase 5**, because the
harness switch of §2 landed between rows 2 and 3 as phase 3. `ZERO-GOAL.md` is what
each one did; where this table turned out to be wrong is said at the row.

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

Decision 9. What is left of `command_line_scan` after P2 and P3 is `+cmd`, `-T`,
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
`do_bang`, and `:edit` goes before `readfile` because `do_ecmd` is its caller.

Two things P9 must decide rather than compute, both already measured:

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

Decision 5, and the phase whose delta is already measured (§2g): 2 corpus cases and
6 sweep rows. `check_changed()` is folded away rather than deleted first, because
`ex_quit`, `do_ecmd` and `check_changed_any` all call it; the sweep rows move
because `:edit`, `:enew`, `:ex`, `:view` and `:visual` all answered E37 before
reaching their own refusal.

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

#### P12 — no `FILE *` that is never opened

`scriptin[NSCRIPT]` and `redir_fd` are `static FILE *` that **nothing ever
assigns**: `closescript` calls `fclose` on one, `inchar` calls `getc` on it,
`redir_write` calls `fputs` and `putc` on the other, and all of it is unreachable
in the `can_cindent` sense — a static written nowhere and read everywhere, which no
warning can see. `ui_write`'s `vim_fsync(1)` is the same shape: its `console`
parameter is `FALSE` at the only call site (78780).

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
uses  files:8     files:7      mechanical  readfile's last caller is do_ecmd, removed by 7
uses  files:8     streams:4    mechanical  read_stdin's entry point is the bare `-`, removed by 4
uses  files:9     files:5      mechanical  b_ffname's largest readers are do_write and check_readonly
uses  files:9     files:7      mechanical  and do_ecmd, which 7 removes
uses  buffers:10  files:5      rationale   the protection has no remedy once nothing can be written
uses  options:11  files:5      mechanical  dropoptions --strict refuses 'fsync'/'write'/'writeany' before 5
uses  options:11  files:7      mechanical  'undoreload' is read by do_ecmd
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
run in: P8's own cut is what is left of `readfile` once P7 has taken its caller,
and P9's is the largest of them whichever side of P8 it falls. `stat` is not in any
row because its last call site is `buflist_new`'s naming branch, which P9 folds
rather than deletes.

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

## 4. What remains

### 4a. The surviving libc, by reason

| why | symbols |
| --- | --- |
| **the terminal** (the whole of the host boundary that is left) | `read` `write` `close` `dup` `ioctl` `select` `tcgetattr` `tcsetattr` `nanosleep` |
| **messages before and after the screen** | `printf` `fflush` `stderr` |
| **memory** | `malloc` `free` `realloc` |
| **strings and memory blocks** | `memchr` `memcmp` `memcpy` `memmove` `memset` `strcasecmp` `strcat` `strchr` `strcmp` `strcpy` `strlen` `strncasecmp` `strncmp` `strncpy` `strpbrk` `strstr` `sprintf` |
| **character classes** | `isalnum` `iscntrl` `ispunct` `tolower` `toupper` `towlower` `towupper` |
| **numbers** | `atoi` `atol` |
| **sorting and searching** | `qsort` `bsearch` |
| **time** | `time` `gettimeofday` |
| **signals and exit** | `sigaction` `sigaddset` `sigemptyset` `sigismember` `sigprocmask` `kill` `raise` `getpid` `exit` `_exit` |
| **gcc's own** | `__errno_location` `fputc` `fwrite` `putchar` |

### 4b. What is still file-shaped afterwards

Almost nothing, and the residue is nameable:

* **`read`/`write`/`close`/`dup` on fds 0, 1 and 2.** After P8 there is no `open`,
  so the process cannot acquire a fourth descriptor — an invariant a phase check can
  assert mechanically (no `open`/`creat`/`openat`/`mkdir`/`rename`/`unlink`/
  `readlink`/`opendir` in the source, and none in `nm -u`).
* **`time()` and `gettimeofday()`.** `vim_time()` feeds undo's *"1 second ago"* and
  the command-line history's timestamps; `gettimeofday` times `:sleep`, the bell,
  key timeouts and OSC replies. The undo message is the one nondeterminism the
  corpus has to scrub (§2e), which is a hint: *"the editor stops asking what time
  it is"* is a phase, and it frees `time`. Not in this plan.
* **`exit`/`_exit` and the signal set.** whim's Phase 26 argued five signals are
  the minimum; a core that does not own the process wants none of them, and that is
  the host's business rather than a filesystem question.

### 4c. Toward the host boundary — a sketch, not a plan

Once argv is two options and nothing is loaded or saved, `main()` is a few lines of
terminal setup, a size query, and `vim_main2()`. The shape the charter asks for is:

```
editor.c        main(), the terminal: tcgetattr/tcsetattr, TIOCGWINSZ, the signal
                handlers, read(0)/write(1), and the loop that hands bytes to the core
zero-vim.c      vim_main(), and no libc call that is not memory, strings or arithmetic
```

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
   a host wants) stay.
6. **SETTLED — `:file` goes, `CTRL-G` stays.** Keep `CTRL-G` as buffer info
   (`[No Name]`, the line count, the percentage) and **delete the `:file` row**,
   which exists to rename. `fileinfo()` shrinks rather than going.
7. **`--More--` and the Press-ENTER prompt.** Recommendation: **keep both** and
   record them (`hit_enter`, `:highlight`). They are how the editor behaves when a
   message does not fit, and a phase that removed them would be removing screen
   behaviour, which decision 3 protects.
8. **SETTLED — row deletion crosses `create_cmdidxs.py`'s 100-row floor** (111 − 12 = 99), and the floor is lowered **to 80 in the phase that crosses it**, in the
   same commit, with the reason in the tool's docstring — and never silently.
9. **`ME_TOO_MANY_ARGS` and the parallel `main_errors[]` table.**
   Recommendation: delete the row and the enumerator together in P4, with the
   DWARF before/after check (§P4). The alternative — leaving an unreachable row —
   is the "concept the table has and the code does not" that whim's Phase 18
   argued against.
10. **The five pty scenarios.** Recommendation: **keep them**, and reduce them to
    what only a terminal shows: the window size from `TIOCGWINSZ`, raw mode
    entered and restored, and one arrow-key scenario as a second opinion on
    `nvidxcheck.py`.
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
