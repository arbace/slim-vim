#!/bin/sh
# Zero phase 12, the check -- the options nothing reads.
# See pipes/zero12-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero12-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero12-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old`, the binary this phase was HANDED,
# and `old.c`, the source it was built from.
#
# EVERY VISIBLE EFFECT OF THIS PHASE IS OUTSIDE THE INSTRUMENT, and that is the one
# thing to understand about this check.  ``zexcmds`` records `exit`, `bells`,
# `stderr`, `text` and `msgs` for the `set` row and NO stream digest, so even a
# change to what `:set` prints in the stream would be invisible there; no recorded
# case or row asks `:set ro?`, `:set fsync?`, `:set write?`, `:set wa?`, `:set
# undoreload?` or `:set prompt?`; bare `:set` does not move, because none of the six
# differs from its default and the listing is wiped by the Press-ENTER redraw before
# zscreen.py takes its picture; and no case sets `'readonly'`, so the W10 warning and
# the two `[RO]` indicators are never drawn.  A phase that did nothing and a phase
# that did everything have the SAME RECORDING.  So the probes are not a supplement
# here, they are the check.
#
# SIX THINGS ARE PROVED, and the fourth is the phase.
#
# 1. THE CUT.  Six rows go, of a computed seven; two functions go BY NAME and with
#    the reason stated (`change_warning` and `did_set_readonly` -- see the edit); and
#    the sweep then takes the six globals, `SHM_RO`, `BV_RO`, `BV_FS`, the static
#    string `w_readonly` and the `b_did_warn` field.
#
#    THE TRAPS, ALL MEASURED:
#      * `'modified'` STAYS and has no reader of `p_mod` either.  Decision 5 keeps
#        it -- the state it reports lives in `b_changed` -- and `dropoptions.py`
#        refuses a PV_BUF row anyway.  A check that wanted every readerless row gone
#        would fail on a correct phase.
#      * `b_did_warn` becomes dead only after BOTH `change_warning` and
#        `did_set_readonly` have gone.  Remove one and it is a field with one reader
#        and one writer, which no tool reports.
#      * `w_readonly` is a `static char *` INSIDE `change_warning()`, not at file
#        scope, so a check that greps for it at file scope finds nothing either way.
#      * `'paste'` IS EXEMPT FOR EVER (ZERO-PLAN.md 2d and decision 8, the user's
#        standing promise): `p_paste` 12 mentions and its five `*_nopaste` save slots
#        at four each, before and after, and `+{command}` untouched.  The next person
#        to widen the computation must meet this assertion, not just the comment.
#
# 2. THE FLAG LETTERS ARE NOT TOUCHED, AND IT IS ASSERTED RATHER THAN DESCRIBED.
#    `'cpoptions'` and `'shortmess'` each have a validity list that is a separate
#    string literal from the value, so removing a letter from a list could not move
#    `:set cpo?` or `:set shm?` -- but it WOULD turn `:set shm=F`, accepted silently,
#    into `E539: Illegal character`, and no corpus case, Ex row, argv row or pty
#    scenario types `:set shm=`.  That is exactly the change ZERO-GOAL.md rule 2
#    exists to prevent, so both literals are compared character for character against
#    the input, and four probes require `:set shm=F` and `:set cpo=g` to be accepted
#    on both binaries and `:set shm=y` and `:set cpo=<a non-letter>` to answer E539 on
#    both -- `h` is in neither list, `'cpoptions'` having only `H`.  Measured here:
#    23 of `'cpoptions'` 60 letters and 14 of `'shortmess'` 23 are inert, and THIS
#    PHASE MAKES EXACTLY ONE MORE SO -- `'shortmess'`'s `r`.
#
# 3. THE ROW FLOOR, WHICH THIS PHASE CROSSES.  ``orphanopts`` refused a table
#    it parsed fewer than 100 distinct `&p_xx` out of, and this phase takes the count
#    102 -> 96.  `tools/zerodelta.sh` runs that tool beside its harnesses, so crossing
#    the floor would not fail this phase -- it would fail the delta check of EVERY
#    zero phase after it.  The floor is 80 now, lowered in this phase's own commit
#    with the reason in the tool's docstring, the same number and the same argument as
#    `create_cmdidxs`'s so that the two floors stay one idea.  The check
#    requires the floor to be BELOW the count it will meet -- by using it, not by
#    grepping for the number -- and requires the tool's output on this source to be
#    byte-identical to its output on the input: no option global is orphaned, in
#    either direction.
#
# 4. THE PROBES, ON BOTH BINARIES, WHICH ARE THE WHOLE EVIDENCE.  Thirteen must move
#    and thirteen must not.  `ro_w10` is the one that shows the phase removing
#    BEHAVIOUR rather than a row: `:set ro` on an unmodified buffer, then an insert,
#    and the old binary prints `W10: Warning: Changing a readonly file` and PAUSES A
#    SECOND -- 1,008 ms measured against 3 ms here, the same shape as phase 2's
#    2,010 ms -> 5 ms.  The message is never in a snapshot: it is drawn, a Press-ENTER
#    follows and the redraw wipes it, exactly as zero7-check's E319, so the assertion
#    is on the STREAM and on the elapsed time.  THE BUFFER MUST BE UNMODIFIED WHEN
#    `:set ro` RUNS -- `change_warning()` returned early on `b_did_warn ||
#    curbufIsChanged()` -- so a probe that types its seed first shows nothing on
#    either binary.
#
# 5. AND `:set all` IS IN NO HARNESS.  It is the only thing that lists every option
#    name, so it is the only way to see four rows cease to exist; `readonly`, `fsync`,
#    `prompt` and `undoreload` are in the old stream and absent from this one.
#
# 6. THE LINE AGAINST THE PHASE AFTER THIS ONE, stated as counts: `scriptin` 8,
#    `redir_fd` 6 and `vim_fsync` 3, with `fclose`, `getc`, `putc` and `fsync`
#    asserted STILL undefined.  `fsync` is still reached from `ui_write` and is the
#    FILE* phase's.
#
# A record is built the way `zcases` builds one and scrubbed the same way
# (tools/zrec.py).

# THE BODY IS GO: tools/go/internal/check/zero12.go and tools/go/internal/check/zero12probes.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/enumvals.sh
#   tools/phasecheck.sh
#   tools/st.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero12-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero12-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero12 "$work" "$state"
