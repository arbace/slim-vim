#!/bin/sh
# Whim phase 50 -- only LF text files.  See WHIM-GOAL.md.
#
# Usage: pipes/whim50-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Every line ends with LF when it is read and when it is written, and a CR is a
# character like any other.  -b goes, and with it 'binary', 'fileformat',
# 'fileformats', 'endofline', 'fixendofline', 'endoffile', 'textmode' and
# 'textauto', and the ++bin, ++nobin and ++ff arguments.  See tools/lfonly.py.
#
# THE DELTA: no Ex command; the behaviour cases ff_dos and binary_mode, whose
# :set ff=dos and :set binary are refused now.
set -eu

work=${1:?usage: whim50-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

python3 tools/dropopts.py "$f" -b
python3 tools/lfonly.py "$f"
# The rows go before the sweep and without --strict: their callbacks, and the
# format functions the sweep has not taken yet, still read them.  The
# post-condition below is the check.
python3 tools/dropoptions.py "$f" --local binary fileformat endofline fixendofline endoffile textmode
python3 tools/dropoptions.py "$f" fileformats textauto

tools/sweep.sh "$f"
python3 tools/droplocal.py "$f" b_p_bin b_p_ff b_p_fixeol b_p_tx

# tools/phaserun.sh sweeps next, then runs pipes/whim50-check.sh.
