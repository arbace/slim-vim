#!/bin/sh
# Zero phase 8, the check -- nothing can point the editor at another file any more.
# See pipes/zero8-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero8-check.sh <work-dir> <state-dir>     (run from the repository root)
#
# Runs after pipes/zero8-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old`, the binary this phase was HANDED,
# and `old.c`, the source it was built from, which is the left-hand side of every
# before-and-after count below.
#
# SIX THINGS ARE PROVED HERE, and the fourth is the only one that can say what this
# phase is actually for.
#
# 1. THE CUT, which is the sweep's work and not the edit's.  Seventeen functions go,
#    none of them named by the edit -- do_ecmd (328 lines), get_visual_text,
#    check_lnums_both, do_exedit, nv_gotofile, grab_file_name, prepare_help_buffer,
#    u_unch_branch, text_or_buf_locked, reset_VIsual, reset_VIsual_and_resel,
#    delbuf_msg, ex_edit, u_unchanged, otherfile, check_lnums and getargopt -- with
#    two struct fields (exarg_T.read_edit and one more the sweep found), the five
#    CMD_ enumerators, EX_ARGOPT and seven string literals.  Listing them here is a
#    RECORDING of what the sweep did, which is the only place a list of removed
#    names belongs.
#
#    THE TRAPS, ALL MEASURED, that make a copied "every name at zero mentions" loop
#    the wrong check:
#      * `check_lnums` and `check_lnums_both`, `reset_VIsual` and
#        `reset_VIsual_and_resel`, `u_unchanged` and `u_unch_branch`, `do_ecmd` and
#        `do_ecmd_cmd`, `otherfile` and `otherfile_buf` are five pairs where one
#        name is a prefix of another and only one of each pair goes.  Every count
#        here is `\b`-anchored for that reason.
#      * `"edit"` REACHES ZERO AND `"ex"` DOES NOT.  `getargopt()`'s `++edit`
#        strncmp was the last speaker of `"edit"` once the row went, and anchor 6
#        takes it; `"ex"` survives as one word of `'belloff'`'s value list.  A
#        "no mention of edit anywhere" check fails on a correct phase, and a
#        "both survive" check fails on this one.
#      * `E447: Can't find file "%s" in path` SURVIVES.  nv_gotofile() was not its
#        only speaker, so the message the `gf` probe looks for on the OLD binary is
#        still in the source afterwards -- it is the KEY that went, not the string.
#      * `readonlymode`, `do_ecmd_cmd` and `do_ecmd_lnum` are left WRITE-ONLY rather
#        than removed, and are asserted at their counts.  `readonlymode` is FALSE
#        for ever, `do_ecmd_lnum` is written through eval_vars() which is the
#        buffer-name phase's, and a struct member that is only written draws no
#        warning from anything.
#
# 2. THE LINE AGAINST THE PHASE THAT STOPS READING A BYTE (ZERO-PLAN.md P8), stated
#    as counts so that taking any of it here would fail rather than widen quietly:
#    `readfile` keeps EXACTLY 5 mentions -- its prototype, its definition and the
#    three calls in read_buffer() and open_buffer() -- and `read_buffer` 17.
#    `open_buffer` goes 6 -> 5, and that is the one number ZERO-PLAN.md 3c got
#    backwards: do_ecmd was a caller of `open_buffer`, NOT of `readfile`, so what
#    this phase costs the read path is one call site and nothing else.  The `uses`
#    line the plan wrote for P8 is corrected there.
#
# 3. `'undoreload'` IS NOT THIS PHASE'S.  `p_ur`'s only reader was inside do_ecmd,
#    so after this phase it is a global with an option row and nothing that reads
#    it -- which is the options phase's to remove, not this one's: removing a row
#    changes what `:set` answers and nothing here sweeps `:set`, so the delta could
#    not be checked, and `orphanopts` refuses the opposite direction.  It is
#    asserted at exactly 2 mentions WITH its row, and the manifest carries
#    `uses options:11 files:8 mechanical` for the phase that takes it.
#
# 4. THE PROBES, on BOTH binaries, because THE CORPUS CANNOT SEE A FILE BEING
#    OPENED.  The two cases it does see are `cmd_edit`, which types `:edit` with no
#    file name and has only ever recorded `E37: No write since last change`, and
#    `key_gf`, which presses `gf` on a word naming nothing and recorded E447.  A
#    declared delta of "those two moved" is therefore consistent with a phase that
#    changed two error messages and left do_ecmd() reachable.  So the probes run the
#    binary this phase was handed beside the one it made, and the ones that matter
#    require the OLD binary to pull a file off the disk and the new one to refuse.
#
#    THE FILE IS `keys` ITSELF.  tools/zstream.py writes a session's keystrokes into
#    a file called `keys` in the run directory and feeds it on stdin, so there is
#    always one file there to open and no runner has to plant one: `:e! keys` loads
#    it, and WHAT PROVES THE BYTES ARRIVED IS THE ESCAPE IN THEM -- the keystroke
#    file holds `...\x1b:q!\r`, which tools/zscreen.py draws as `^[:q!^M`, and an
#    Escape can only be in the buffer if the file was opened.
#
#    AND THE FOUR COMMANDS ARE PROVED TO HAVE BEEN `:edit` IN DISGUISE: `:ex! keys`
#    and `:visual! keys` load the file exactly as `:e! keys` does, `:view! keys`
#    loads it AND makes `:set ro?` answer `readonly`, and `:enew!` empties the
#    buffer.  That is do_exedit's thirty lines, measured from the outside.
#
# 5. THE KEYS, AND THE HAZARD THIS PHASE DOES NOT HAVE.  No `nv_cmds[]` row is
#    touched: `gf`, `gF`, `[f` and `]f` are arms inside two handlers whose `g`, `[`
#    and `]` rows dispatch dozens of other keys.  CLAUDE.md's twelve-phase arrow-key
#    bug was a deleted row under a precomputed index, and the general guard is
#    `nvidx`, which tools/phasecheck.sh runs.  The specific one is here:
#    FIFTY `g*`, `[` and `]` keys are pressed on both binaries and exactly four must
#    move, which is what proves the two large handlers survived the two cuts inside
#    them.
#
# 6. A REAL TERMINAL.  Every probe above went through a pipe.  The session types
#    `:e <file>` on a pty, where the file is one the RUNNER wrote -- the editor has
#    had no way to write one since phase 6 -- and the old binary puts its line in
#    the buffer while this one answers E492.  An ordinary editing session beside it
#    is required to be identical.
#
# A record is built the way `zcases` builds one and scrubbed the same way
# (tools/zrec.py).  tools/zstream.py's session() is not called directly because this
# check needs the raw stream beside the screens.

# THE BODY IS GO: tools/go/internal/check/zero8.go and tools/go/internal/check/zero8probes.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/enumvals.sh
#   tools/phasecheck.sh
#   tools/st.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero8-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero8-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero8 "$work" "$state"
