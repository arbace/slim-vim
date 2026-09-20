#!/bin/sh
# Whim phase 12 -- UTF-8, and no other encoding, ever.  See WHIM-GOAL.md.
#
# Usage: pipes/whim12-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Phase 9 made 'encoding' a property of the build rather than of the machine.
# This makes it not a setting at all: mb_init() accepts utf-8 and returns
# "invalid argument" for anything else, so `:set enc=latin1` fails the way a
# misspelt value fails, and the latin1 and DBCS character paths lose their only
# caller and are swept.
#
# THE CONVERSION LAYER IS CUT AT ITS ENTRY POINTS, NOT UNPICKED FROM ITS
# CALLERS, and that is the whole shape of this phase.  readfile() is 1,758 lines
# with conversion woven through a retry loop, partial-character carry-over and a
# `goto retry`; buf_write() is much the same.  Excising that by hand is the kind
# of surgery that compiles, passes a symbol check, and corrupts a file on some
# path nobody tested.  Instead six functions answer differently -- my_iconv_open
# fails, convert_setup produces CONV_NONE, string_convert returns NULL,
# check_for_bom finds none, make_bom writes none -- and every one of those is an
# answer the callers already branch on.  iconv failing is the case upstream
# supports for a system without it.
#
# Only then are the branches that can no longer be taken deleted, and only
# because the calls inside them are what keep iconv, iconv_open and iconv_close
# in the symbol table.  A dependency linked in and never reached is exactly what
# this pipeline exists to remove.
#
# 'encoding' CANNOT be dropped even though it is PV_NONE: its row is what
# initialises p_enc, read in twenty-nine places, so removing it would leave a
# NULL global -- Phase 10's trap in its other form.  It stays, reports utf-8,
# and refuses anything else.
#
# THE DELTA: a byte-order mark becomes three ordinary bytes at the top of the
# buffer, which is what ignoring it means, and the bomb_on behaviour case moves
# because of it.  Of the six encoding options only 'charconvert' can actually
# GO: 'fileencodings' and 'termencoding' are PV_NONE and not reached by name,
# and dropping either still segfaults, because readfile() dereferences p_fencs
# and did_set_encoding() dereferences p_tenc.  'fileencodings' keeps its row
# and loses its content instead.  'fileencoding' and 'bomb' are PV_BUF.  A row
# is what INITIALISES its global; an option is only inert when nothing reads
# that global any more, and `dropoptions` now checks exactly that.
set -eu

work=${1:?usage: whim12-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- cut the entry points -------------------------------------------------
tools/st.sh noenc "$f"

# No sweep here.  One stood here, and the lines after it were written for swept text,
# but this phase and every stage it has run in reproduce their boundaries without
# it (WHIM-PLAN.md 2c; pipes/whim.stages) -- the stage's one sweep does its work.
tools/st.sh dropoptions "$f" --strict charconvert

# tools/phaserun.sh sweeps next, then runs pipes/whim12-check.sh.
