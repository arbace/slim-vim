#!/bin/sh
# Zero phase 11, the check -- `:q` quits, and nothing refuses any more.
# See pipes/zero11-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero11-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero11-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old`, the binary this phase was HANDED,
# and `old.c`, the source it was built from: the left-hand side of every
# before-and-after count, and of every probe.
#
# SIX THINGS ARE PROVED HERE, and the fifth is the only one that can say what this
# phase actually did to the editor.
#
# 1. THE CUT, WHICH IS THE SWEEP'S AND NOT THE EDIT'S.  SIXTEEN functions go and the
#    edit names none of them, from ONE fold.  ELEVEN OF THE SIXTEEN ARE A SURPRISE
#    and are the largest part of the phase: `check_changed_any()`'s tail is "go to
#    the buffer that refused", and after whim removed the buffer list and the window
#    commands that tail was the last caller of the whole switch-buffer/switch-window
#    island.  The list below is a RECORDING of what the sweep did, which is the only
#    place a list of removed names belongs (ZERO-GOAL.md rule 1), and the COUNT is
#    asserted beside it -- 1,742 definitions to 1,726 -- because a check written
#    from ZERO-PLAN.md's three names would pass while the island silently went.
#
#    THE TRAPS, ALL MEASURED, that make a copied loop wrong here:
#      * `bufIsChanged` GOES 10 -> 7 AND MUST NOT GO TO 0, and `curbufIsChanged`
#        does not move at all.  The buffer still knows it is modified: CTRL-G still
#        prints `[Modified]`, the status line still draws `[+]`, `:set modified?`
#        still answers.  What went is the refusal, not the state.
#      * `text_locked`, `curbuf_locked` and `before_quit_autocmds` DO NOT MOVE.  All
#        three return early ABOVE the anchor, so `:q` can still decline -- just not
#        for the reason this phase removed.
#      * `open_buffer` goes 5 -> 4, `buf_spname` 5 -> 4 and `exiting` 17 -> 13.
#        Phase 9's brief pinned `open_buffer` at 5 and phase 10's check at 5; both
#        were right there and would fail here, `enter_buffer()` having been one of
#        its four callers.
#      * `p_wh` LOOKS WRITE-ONLY AND IS NOT.  It goes 4 -> 2 -- the two reads in
#        `win_enter_ext`'s callee went with the island -- and the two that are left
#        are its declaration, which carries the initialiser, and one real reader in
#        the frame layer.  A "uses - writes - 1 <= 0" scan reports it and is wrong.
#      * `SHM_FILEINFO` leaves, and it is the `'shortmess'` `F` letter.  The letter
#        is accepted and inert afterwards; that is the options phase's and the flag
#        strings are not touched here.
#
# 2. NOTHING IS LEFT WRITE-ONLY, AND IT IS COMPUTED ON BOTH TEXTS.  A file-scope
#    static that is assigned and never read draws no warning, deadsweep.py acts on
#    warnings, and nothing else here looks -- phase 10 had to take `readonlymode` by
#    hand for exactly that shape.  So the scan runs on the source this phase was
#    handed as well as on the one it made, and the two answers must be the SAME SET
#    and must be exactly `vim_ignored`, upstream's sink for a return value that is
#    deliberately ignored.  It finding something either side is what makes an empty
#    answer a scan failure rather than a phase succeeding.  `p_wh` is what the
#    OBVIOUS scan gets wrong and this one does not: a "uses - writes - 1 <= 0" count
#    charges its initialiser to the writes.  The TWO STRUCT FIELDS that did become
#    write-only are the edit's extra A and are already gone -- no warning and no tool
#    sees a member that is only written.
#
# 3. THE LINE AGAINST THE PHASES AFTER THIS ONE, stated as counts so that reaching
#    into one would fail here rather than widen quietly: `p_ro` 2 and `p_ur` 2 WITH
#    their option rows (the options phase's), `read_cmd_fd` 12 (the terminal's),
#    and `scriptin` 8, `redir_fd` 6 and `vim_fsync` 3 (the FILE* phase's), with
#    `fclose`, `getc`, `putc` and `fsync` asserted STILL undefined.
#
# 4. THE ENUMERATORS, DUMPED EITHER SIDE.  Twelve go -- the four `CCGD_`, the two
#    `DOBUF_`, `SHM_FILEINFO` and the five `WEE_` -- and NOTHING RENUMBERS, because
#    typereach.py takes whole anonymous definitions and a whole definition leaving
#    takes no survivor's value with it.  That is the opposite of phase 10, where 85
#    moved, and it is worth the four seconds either side to say so rather than
#    assume it.
#
# 5. THE PROBES, ON BOTH BINARIES, BECAUSE THE CORPUS CANNOT SEE THE EXIT STATUS.
#    The one case it sees is `quit_modified`, and it ends with a trailing `:q!` --
#    which quits the OLD binary too, so the status is 0 either side and what the
#    recording holds is a message that changed.  `q_alone` is the probe that is not:
#    `ihello<Esc> :set nopaste :q` AND NOTHING AFTER IT.  The old binary draws
#    `E37: No write since last change (add ! to override)`, runs out of stdin,
#    prints `Vim: Finished.` and exits 1; this one quits on the `:q` and exits 0.
#    That difference -- 1 to 0 -- is the whole phase measured from outside, and no
#    recording can see it.
#
#    THE MUST-NOT-MOVE HALF IS REQUIRED TO BE DOING SOMETHING, or "it did not move"
#    is two failures agreeing: `ctrl_g` must say `[Modified]`, `editing` must say
#    `alpha`, `cquit` must exit 1 on both, `q_clean` must exit 0 on both with no E37
#    anywhere -- it is `:q` on an UNMODIFIED buffer, which took the else arm before
#    this phase and takes it now -- and `zz_key`/`zq_key` must leave the same screen.
#
# 6. A REAL TERMINAL, because every probe above went through a pipe.  On a pty the
#    old binary answers E37 to `:q` and is still running, so the `:q!` after it
#    reaches the command line; this one draws no E37 at all.  THE OPPOSITE PAIR --
#    "the `:q!` did not reach the new binary" -- IS NOT ASSERTED, and it is a race:
#    once the editor has quit the pty leaves raw mode and whether the trailing
#    keystrokes are echoed back depends on how fast the process exits.  What the `:q`
#    quit is `q_alone`'s to say, by its exit status through a pipe.  An ordinary
#    editing session beside it must be identical either side.
#
# A record is built the way `zcases` builds one and scrubbed the same way
# (tools/zrec.py).  tools/zstream.py's session() is not called directly because this
# check needs the raw stream, the exit status and the snapshot count beside the
# screens.

# THE BODY IS GO: tools/go/internal/check/zero11.go and tools/go/internal/check/zero11probes.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/enumvals.sh
#   tools/phasecheck.sh
#   tools/st.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero11-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero11-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero11 "$work" "$state"
