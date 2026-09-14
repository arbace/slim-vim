#!/bin/sh
# Whim phase 28 -- C indenting.  See WHIM-GOAL.md.
#
# Usage: tools/whim28.sh <work-dir>      (run from the repository root)
#
# get_c_indent() is 1,534 lines and the largest function left in the file: a
# model of C syntax built to answer one question, how far to indent this line.
# With in_cinkeys() and the cin_* helpers it comes to 3,007 lines.
#
# 'autoindent' stays -- it is on by default here -- and copies the previous
# line's indent, which is what an embedded editor needs.  'lisp' and
# 'indentexpr' are different indenters and are not touched.
#
# FIVE OPTIONS, ALL PV_BUF, so the rows go with --local and the buffer fields
# with droplocal.py afterwards, in that order: the option callbacks read the
# field, so the sweep that removes them has to run in between.
#
# THE DELTA: none the harness records.  Four behaviour cases exercise indenting
# and all four are 'autoindent' and 'formatoptions', not 'cindent' -- the phase
# checks that directly, by indenting a C fragment and requiring the result the
# line above gives rather than the one C syntax would.
set -eu

work=${1:?usage: whim28.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/nocindent.py "$f"
# --local WITHOUT --strict, which phase 16 settled: the global-read guard runs
# before droplocal.py, and the reader it finds -- `buf->b_p_cin = p_cin;` -- is
# the buffer-copy plumbing droplocal owns.  The post-sweep greps below are the
# check instead.
python3 tools/dropoptions.py "$f" --local \
    cindent cinkeys cinoptions cinscopedecls cinwords


tools/sweep.sh "$f"
python3 tools/droplocal.py "$f" b_p_cin b_p_cink b_p_cino b_p_cinsd b_p_cinw
tools/sweep.sh "$f"

for g in get_c_indent in_cinkeys do_c_expr_indent b_p_cin b_p_cino p_cinw; do
    n=$(grep -c -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  cindent      $g still has $n mentions after the sweep"
        grep -n -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
# and the indenters that are not this one
for g in get_lisp_indent get_indent; do
    if [ "$(grep -c "\b$g(" "$f" || true)" = 0 ]; then
        echo "  cindent      $g went too -- 'lisp' and 'autoindent' are not this"
        exit 1
    fi
done
echo "  cindent      no C syntax model; 'autoindent' and 'lisp' untouched"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

# 'autoindent' must still indent, and `:set cindent` must now be refused.  The
# control is what makes the second a check rather than a tautology.
ai=$(cd "$work" && rm -rf .citest && mkdir .citest && cd .citest \
     && printf '    one\n' > f.txt \
     && ../whim-vim -e -s -c 'set autoindent' -c 'normal Gotwo' -c 'wq' f.txt \
            </dev/null >/dev/null 2>&1
     sed -n 2p f.txt | cat -A | head -1)
probe() {
    (cd "$work" && ./whim-vim -e -s -c "set $1" -c 'qa!' </dev/null >/dev/null 2>&1)
    echo $?
}
rm -rf "$work/.citest"
case $ai in
    '    two$') ;;
    *) echo "  autoindent   a new line gave '$ai', expected four spaces then two"; exit 1 ;;
esac
[ "$(probe autoindent)" = 0 ] || { echo "  options      the control failed"; exit 1; }
[ "$(probe cindent)" = 0 ] && { echo "  options      :set cindent was accepted"; exit 1; }
echo "  autoindent   still indents; :set cindent is refused"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
