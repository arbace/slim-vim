#!/bin/sh
# Whim phase 3 -- no introduction, and the command line says only what the
# editor still decides.  See WHIM-GOAL.md.
#
# Usage: pipes/whim3.sh <work-dir>       (run from the repository root)
#
# ONE PHASE WHERE THERE WERE TWO.  The first cut :intro, :version and the
# splash, and turned --help, --version and -h into mainerr calls without
# deleting the comparisons.  The second deleted those along with a dozen inert
# or refusing options, using a tool that split the long-option chain as it went
# -- which broke --clean, --noplugin and --not-a-term, and nothing noticed,
# because no harness passes an option.  Both were one question: what may an
# invocation say?
#
#   the introduction   :intro, :version, and the splash screen's two call sites
#   vestigial          -h -? --help --version, which printed usage() and
#                      list_version(); those go with them, and with
#                      list_version() goes the building machine's hostname
#   refusing           -A -F -H (not compiled in), -g (no GUI), -nb (no netbeans)
#   inert              -f -X -Y -d -U --nofork --literal --gui-dialog-file
#                      --startuptime --log -- accepted, or an argument that
#                      goes nowhere
#   another way to say it
#                      -l -C -N -V --noplugin, all of them :set; -n, which set
#                      'updatecount' for a swap file that is memory from Phase
#                      12; -p, which laid files out as tab pages where -o and -O
#                      still give windows; --clean, which was -u DEFAULTS and an
#                      empty 'runtimepath' and 'packpath'
#   no terminal        --not-a-term.  This one is a capability, and it goes on
#                      purpose: a full-screen run with no terminal now warns and
#                      waits, as it did before the option existed.  An embedded
#                      editor is given a terminal or run with -e.
#
# THE DELTA, cumulative against slim-vim's baselines: helpclose from phase 1,
# and now intro and version.  No harness passes an option, so the evidence for
# the command line is tools/clicheck.py, which runs every one the parser has --
# the dropped ones must be unknown and the rest must still do what they say.
set -eu

work=${1:?usage: whim3.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/nointro.py "$f"
python3 tools/dropopts.py "$f" \
    -h '-?' -A -F -H -g -f -X -Y -d -U -l -C -N -n -p -V \
    --help --version --clean --literal --nofork --noplugin --not-a-term \
    --gui-dialog-file --startuptime --log
python3 tools/optreaders.py "$f"

tools/sweep.sh "$f"

# The post-condition, asked after the sweep because it is the sweep that takes
# the functions: nothing the introduction or a dropped option needed is left.
for g in '\blist_version\b' '\busage\(' '\bmaybe_intro_message\b' \
         '\bcompiled_(user|sys)\b' '\bearly_arg_scan\b' '\bmake_tabpages\b' \
         '\bset_init_clean_rtp\b' \
         '\bis_not_a_term' 'More info with' '"-nb"' \
         '"(not-a-term|noplugin|startuptime|gui-dialog-file|nofork|--clean)"'; do
    n=$(grep -cE -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  cmdline      $g still has $n mentions after the sweep"
        grep -nE -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  cmdline      nothing the introduction or a dropped option needed is left"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

# --- what an invocation can say ----------------------------------------------
own_checks() {
    python3 tools/clicheck.py "$work/whim-vim"
}
# The phase's own check needs only the binary, and so does the delta: they run
# side by side, and this one's verdict is read after the delta has finished.
checks=$(mktemp)
trap 'rm -f "$checks"' EXIT
own_checks > "$checks" 2>&1 &
pid_checks=$!

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" helpclose intro version

if wait $pid_checks; then cat "$checks"; else cat "$checks"; exit 1; fi
