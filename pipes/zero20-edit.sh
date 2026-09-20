#!/bin/sh
# Zero phase 20 -- the signals and the terminal are the host's.  See ZERO-GOAL.md.
#
# Usage: pipes/zero20-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# ZERO-PLAN.md 4c's third step, and the largest of the three: `mch_get_shellsize`,
# `mch_settmode` and the signal handlers move across, "which takes ioctl, tcgetattr,
# tcsetattr, select, nanosleep and the nine signal symbols with them".  It takes none
# of them, and the phase says so rather than implying a reduction it does not make.
#
# WITHIN ONE TRANSLATION UNIT, MOVING CODE FROM THE CORE TO THE HOST FREES NOTHING.
# A symbol leaves `nm -u` when its last CALLER leaves the file, and that is the split.
# So `sigaction`, `sigemptyset`, `kill`, `ioctl`, `tcgetattr`, `tcsetattr`,
# `nanosleep` and `select` all survive this phase -- every one of them now called
# from the 240-line host block at the bottom of the file and from nowhere else.
# WHAT LEAVES IS WHAT THE PHASE DELETES: `raise sigaddset sigismember sigprocmask`,
# which were `mch_signal()`'s fifty lines of sigset() emulation and `sig_tstp`'s
# re-raise, and `close dup isatty`, which were the two dead descriptor sites and the
# three questions about terminals that nothing asks any more.  31 -> 24.
#
# THE PHASE'S VALUE IS STRUCTURAL, AND ``zhostonly`` IS THAT CLAIM AS AN
# ASSERTION: every mention of the host's vocabulary -- 43 words, from `sigaction` to
# `VMIN` -- is inside the host block, with eight named exceptions in the core that are
# the deadly-signal message and the clock.  Without that tool the strongest available
# form of "the core names none of this" is `sigaction` at 2 mentions, which says
# nothing about where.
#
# ------------------------------------------------------------------------------------
# WHAT THE HOST TELLS THE EDITOR, AND WHY IT IS IN BAND
#
# The editor had five signal handlers.  Four of them existed to tell it something:
# SIGWINCH "you were resized", SIGTSTP "you were asked to stop", SIGCONT "you were
# continued", SIGINT "the user interrupted you".  A host cannot deliver a signal to a
# core it is linked into -- there is no such thing -- so the four become BYTES the
# core reads from its input, which is the one channel that already exists.  The fifth,
# the deadly pair SIGHUP/SIGTERM, is not a message: it is the process ending, and it
# stays (below).
#
# THE WIRE FORMAT FOR THE RESIZE IS NOT OURS, AND IT WAS ALREADY IN THE FILE.
# `handle_csi()` has always parsed DEC private mode 2048's notification
# (`CSI 48 ; rows ; cols ; hpx ; wpx t`, Tim Culverhouse, 2024) -- and the arm could
# never run, because `\033[?2048$p`, the DECRQM query a terminal answers to set
# `win_resize_setting`, appears NOWHERE in slim-vim.c, whim-vim.c or zero-vim.c.  So
# the whole negotiation was dead code guarding a working parser.  This phase deletes
# the negotiation, the 'termresize' option that drove it and the two state variables,
# and makes the notification unconditional -- and the HOST writes it, from its own
# SIGWINCH handler and its own ioctl.
#
# WHY THE HOST KEEPS THE ioctl RATHER THAN RELYING ON THE TERMINAL.  Mode 2048 is
# implemented by ghostty, kitty, foot, iTerm2, contour and Bobcat, and NOT by xterm,
# tmux, GNU screen, WezTerm, Alacritty, VTE, Konsole, st, Windows Terminal, urxvt or
# Zellij -- and tmux and screen TERMINATE it, answering DECRQM with the correct "not
# recognised" and forwarding nothing.  A core that relied on the terminal would be an
# editor that never learns it was resized under tmux.  Deleting the host's
# `TIOCGWINSZ` instead would free `ioctl` and an eleventh #include and cost that,
# which is a number bought with the terminal.
#
# `\033[?1z` IS OURS AND IS IN NO SPEC, and that is said here rather than discovered.
# `first == '?' && argc == 1 && arg[0] == 1 && trail == 'z'` reaches no existing arm
# (the `?`-prefixed arms end in `c`, `y` and `u`), and `z` is a letter so the trail
# scan stops on it.  Doing real work from inside the termcode parser has precedent in
# the file: the resize arm calls `set_shellsize()`, which redraws the whole screen.
#
# THE INTERRUPT TRAVELS AS THE BYTE IT ALREADY IS.  `catch_sigint` set `got_int`
# directly; the host instead hands the core a `0x03`, which `fill_input_buf`'s own
# CTRL-C scan turns into `got_int` -- the only way `got_int` is ever set in raw mode,
# because raw mode clears ISIG.  IT IS NOT OPTIONAL: with no handler at all, SIG_DFL
# KILLS the editor, and the `10gs` probe found it -- CTRL-C during a `gs` sleep raises
# SIGINT, because the sleep mode deliberately leaves ISIG on (below).  Measured on the
# binary this phase was handed and on a build with no SIGINT handler: `kill -INT`
# mid-session leaves the first editing and kills the second with SIG2.
#
# CTRL-Z IS THE ONE THING THAT CANNOT GO IN BAND, and `musl_suspend()` is why there is
# one call out and not zero.  In raw mode ISIG is clear, so the keyboard CTRL-Z
# arrives as the byte 0x1a, reaches `nv_cmds[]`'s real `{Ctrl_Z, nv_suspend, 0, 0}`
# row, and THE CORE DECIDES to suspend.  A one-way host->core channel has no way to
# carry that decision back.  The external `kill -TSTP` is the other direction and fits
# the in-band path exactly.
#
# ------------------------------------------------------------------------------------
# THE TERMINAL: TWO OPERATIONS, NOT A MODE SETTER
#
# `settmode(tmode_T)` is nine call sites and a three-valued mode, and every site is
# attached to an OPERATION: the editor takes the terminal, gives it back, suspends,
# resumes, sleeps, or re-asserts that it still holds it.  Exposing `musl_set_raw(int)`
# would move the syscall without moving the responsibility, so `settmode()` splits at
# the one line that was ever the host's -- `mch_settmode(tmode)` -- into `term_enter()`
# and `term_leave()`, which keep the escape sequences (`t_BE`/`t_TI`, `t_CBD`/`t_TE`)
# because those are screen work.  `cur_tmode` becomes a boolean, `mch_cur_tmode` goes
# (the two were measured equal at all eleven sites), and `tmode_T` with `TMODE_SLEEP`
# goes to the sweep.
#
# `TMODE_SLEEP` IS NOT "DISCARD INPUT" AND `musl_delay`'s PARAMETER SAYS SO.  Measured
# from `mch_settmode`: the sleep mode is the SAVED termios with ICANON and ECHO
# cleared, applied TCSANOW and not TCSAFLUSH -- nothing is flushed and nothing is
# discarded.  What is different from raw mode is that ISIG is left ON, so the INTR
# character raises SIGINT and cuts the `nanosleep` short.  `10gs` then CTRL-C recovers
# in about 1.8 s on the binary this phase was handed and on this one, and NEVER
# recovers (measured to 26 s) on a build of this phase's own output with the two
# `host_tty_set` calls deleted.  The parameter is `interruptible`.
#
# NOTHING ASKS WHETHER THIS IS A TERMINAL, which is ZERO-PLAN.md 1's decision 7 --
# "the check goes entirely" -- finally kept: phases 2 and 4 left three `isatty()`
# calls alive and this takes all three.  `mch_check_win` and `stdout_isatty` go, and
# `nv_esc`'s `out_redir` folds to the terminal arm.  `musl_is_terminal()` is NOT
# written: the two questions had different subjects (fd 1 for the size, fd 0 for the
# input) and neither survives its caller, so a host call to answer a question nobody
# asks afterwards is boundary surface for nothing.
#
# THE CORE CANNOT ACQUIRE A DESCRIPTOR AT ALL ANY MORE.  `fill_input_buf`'s
# `close(0); vim_ignored = dup(2);` arm -- the core reopening its own stdin from its
# stderr when stdin hit EOF and was not a terminal -- is the core second-guessing the
# host about where input comes from, and once the host owns the terminal that is the
# host's business.  ZERO-PLAN.md 4b's invariant becomes absolute: the core is handed
# fds 0, 1 and 2 and that is the whole of it.  The behaviour that goes is real and
# probe-only: with stdin at EOF and a TERMINAL on fd 2 the old binary reopens fd 0 and
# carries on editing (2,016 bytes drawn), where this one prints `Vim: Finished.` and
# exits (168 bytes).  Zero of 253 recorded rows reach it.
#
# ------------------------------------------------------------------------------------
# WHAT STAYS IN THE CORE, AND EACH IS A DECISION
#
# `deathtrap` STAYS AND THE HOST INSTALLS IT, which is the whole reason the signal
# phase and the terminal phase were merged into one.  A host-side deadly handler that
# merely died would leave the terminal RAW -- measured on a prototype that deleted
# `deathtrap`: the process is killed by the signal, no message, tty still raw.  Keeping
# the body reachable costs nothing and keeps all of it: `deathtrap -> preserve_exit ->
# prepare_to_exit -> term_leave()` restores the tty, writes `Vim: Caught deadly signal
# TERM`, and ends through phase 19's `vim_host_exit` -> `__builtin_longjmp` -> `return
# 1`.  MEASURED identical on both binaries, to the byte: 2,241 on SIGTERM and 2,240 on
# SIGHUP, tty back to ICANON=1 ECHO=1 ISIG=1 ONLCR=1 ICRNL=1, exit 1.
#
# `vim_handle_signal` STAYS, and it is the one core mention of any host word that is
# not a message: `kill(getpid(), got_signal)`, re-raising a deadly signal that arrived
# while the editor was not reading.  Deleting it would make a deadly signal act in the
# middle of a screen update, which no recording can see.  ``zhostonly`` names
# it as an exception with that reason rather than loosening its pattern.
#
# `ui_get_shellsize()` STAYS A QUERY, and this is the design the survey got wrong.
# Making it "do I know my size?" -- a `shell_size_known` flag set by the host and by
# every notification -- BREAKS RESIZING, and the measurement is exact: at a
# `Press ENTER` prompt `set_shellsize()` does `State = MODE_SETWSIZE; return;` and
# DISCARDS the width and height it was given; `wait_return()` then calls
# `shell_resized()`, which is `set_shellsize(0, 0, FALSE)`, which learns the new size
# ONLY from `ui_get_shellsize()`'s side effect.  With the flag, a pty resized while
# the editor sits at a Press-ENTER prompt stays 24x80 for ever (measured, twice).  So
# `mch_get_shellsize()`'s body moves to the host as `musl_get_winsize(int *, int *)` --
# which is the name ZERO-PLAN.md 4c gave it -- and `ui_get_shellsize()` keeps its
# shape.  That also disposes of the `set_termname()` trap the survey spent an hour on:
# on a pipe the host's ioctl fails, `ui_get_shellsize()` returns FAIL exactly as
# before, `t_CWS` is still emitted and the recording does not move by one byte.
set -eu

work=${1:?usage: zero20-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero20-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a second
# time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero20 "$f"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  host         the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  host         the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from -- every probe in the check is a PAIR and this is the left-hand side"

# tools/phaserun.sh sweeps next, then runs pipes/zero20-check.sh.
