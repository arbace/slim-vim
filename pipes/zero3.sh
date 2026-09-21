#!/bin/sh
# Zero phase 3 -- the instrument becomes the screen.  See ZERO-GOAL.md, ZERO-PLAN.md.
#
# Usage: pipes/zero3.sh <work-dir>       (run from the repository root)
#
# NO SOURCE CHANGE AT ALL: r3's zero-vim.c is r2's, byte for byte, and this phase
# asserts it.  What changes is how every later phase is measured.
#
# Zero's editor is on its way to having no file to write, no file to read and no
# stream to print on, so `tools/behaviour.py` -- which ends every case with
# `+w! <file>` and reads the file back -- and `tools/exsweep.py` -- which runs a
# command on a file and records the exit status -- stop being instruments the
# moment the phases they are meant to measure land.  A whole-program phase is
# right here because there is no source edit for a sweep to follow.
#
# The instrument they are replaced with is `tools/zrecord.sh`: keystrokes in on
# stdin, escape sequences out on stdout, and a screen per redraw rebuilt from them
# (ZERO-PLAN.md 2).  Five parts -- 102 keystroke cases, every Ex command typed at
# `:`, every command line the parser may see, four pty scenarios for what only a
# terminal shows, and whim's own terminal table.
#
# WHAT THIS PHASE PROVES, in order, each depending on the one before:
#
#   1. the tree is untouched: zero-vim.c is what the phase was handed;
#   2. it builds with the boundary's flags, and is still absolutely static;
#   3. THE INSTRUMENT IS DETERMINISTIC: three recordings of that binary, byte for
#      byte identical, digests included;
#   4. THE INSTRUMENT CAN FAIL: a copy of the source with do_addsub() returning
#      FAIL -- CLAUDE.md's canonical break -- must move EXACTLY the eleven cases
#      that increment or decrement, and no others.  A corpus that cannot fail is
#      not evidence;
#   5. the declared delta holds: tools/zerodelta.sh --phase 3 against
#      .reference/zero-baselines, which zero phase 0 records from whim-vim.  Those
#      baselines are the INPUT's behaviour, so the delta is cumulative -- phase 2
#      removed the two "not to a terminal" warnings, and `stderr-moved` is that,
#      declared once and checked at every phase after it;
#   6. the old instrument still reaches whim's baselines: tools/whimdelta.sh on the
#      same binary against .reference/baselines, which is the only bridge between
#      the two pipelines' recordings and is kept for exactly that.

# THE BODY IS GO: tools/go/internal/check/zero3.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/pipeline.sh
#   tools/st.sh
#   tools/whimdelta.sh
#   tools/zerodelta.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero3.sh <work-dir>}
exec tools/st.sh check zero3 "$work"
