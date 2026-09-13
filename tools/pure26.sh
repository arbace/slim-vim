#!/bin/sh
# Pure phase 26 -- the memfile is memory, and only memory.  See PURE-GOAL.md.
#
# Usage: tools/pure26.sh <work-dir>      (run from the repository root)
#
# Phase 13 stopped the editor creating a swap file and phase 25 stopped it
# reading one back.  What is left is a FILE BACK-END WITH NO FILE: memfile_T
# still carries a descriptor, still knows how to page a block out and read it
# in, and still sizes an LRU cache against how much memory the machine has --
# all of it behind `if (mfp->mf_fd >= 0)`, and mf_fd can no longer be anything
# but -1.
#
# The proof is short.  mf_open() has two callers: ml_open() passes (NULL, 0),
# and ml_recover() passed a name -- phase 25 deleted it.  So nothing can hand
# the memfile a name, mf_do_open() is unreachable, and mf_write() and mf_read()
# return FAIL on their first lines.
#
# WHICH MAKES 'maxmem' AND 'maxmemtot' OPTIONS THAT DECIDE NOTHING: both are
# read only to compute `need_release`, and the test in front of it is always
# true, so the answer is computed and discarded.  mch_total_mem() went to some
# trouble to size that cache -- sysinfo, sysconf and getrlimit -- for a cache
# that never evicts.
#
# THREE MORE THINGS FALL OUT: mch_get_host_name(), which wrote the machine name
# into block zero (uname); lalloc()'s retry loop, whose point was that
# mf_release_all() might have freed memory by paging blocks to disk; and
# check_overwrite()'s "swap file exists" warning, which asks whether ANOTHER vim
# is editing the file you are overwriting.
#
# THAT LAST ONE IS A BUG FIX.  It is the final reader of p_dir, so 'directory'
# can finally go -- phase 13 dropped its row while this still read it, which
# left p_dir NULL for ever and made `:w!` over an existing other file segfault
# for twelve phases.  Phase 13 keeps the row now; tools/orphanopts.py is the
# standing check, and it runs in every pure phase.
#
# WHAT DOES NOT CHANGE: the block structure.  Lines still live in blocks, blocks
# still have numbers, mf_trans still maps them.  This removes the ability to
# EVICT a block, which was already impossible.
#
# THE DELTA: none.  `:w!` over an existing other file stops segfaulting and
# writes, which is what it should always have done.
set -eu

work=${1:?usage: pure26.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/nomemfile.py "$f"


tools/sweep.sh "$f"

# The rows go after the sweep: --strict refuses a row whose global anything
# still reads, and before the sweep the readers this phase orphaned are still
# there.  A check asked one step too early gets the wrong answer.
python3 tools/dropoptions.py "$f" --strict directory maxmem maxmemtot
tools/sweep.sh "$f"

for g in mf_fd mf_fname mf_ffname mf_write mf_read mf_release total_mem_used p_mmt p_dir \
         mch_total_mem mch_get_host_name; do
    n=$(grep -cw -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  memfile      $g still has $n mentions after the sweep"
        grep -nw -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  memfile      no descriptor, no eviction, no memory budget"

tools/canon.sh "$f"



tools/phasecheck.sh "$work" "$f" .cache/symbols/before

for g in sysinfo getrlimit uname; do
    if grep -qx -- "$g" .cache/symbols/last/undefined; then
        echo "  symbols      $g is still undefined in the object"
        exit 1
    fi
done
echo "  symbols      sysinfo, getrlimit and uname are gone from nm -u"

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" >/dev/null 2>&1; then
    echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$work/pure-vim") bytes"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi

# The check this phase owes phase 13: the crash it is fixing.  A harness that
# does not write over an existing file under another name with `!` cannot see
# it, and none of them does -- which is how it survived twelve phases.
ov=$(cd "$work" && rm -rf .ovtest && mkdir .ovtest && cd .ovtest \
     && printf 'one\n' > a.txt && printf 'two\n' > b.txt \
     && ../pure-vim -e -s -c 'w! b.txt' -c 'qa!' a.txt </dev/null >/dev/null 2>&1
     printf '%s' "$?:$(cat b.txt 2>/dev/null)")
rm -rf "$work/.ovtest"
if [ "$ov" != "0:one" ]; then
    echo "  overwrite    :w! over an existing other file gave $ov, expected 0:one"
    exit 1
fi
echo "  overwrite    :w! over an existing other file writes it"

# --- the delta, cumulative --------------------------------------------------
tools/puredelta.sh "$work/pure-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
