#!/bin/sh
# Whim phase 21 -- there is nothing to recover, and the memfile is memory.
# See WHIM-GOAL.md.
#
# Usage: tools/whim21.sh <work-dir>      (run from the repository root)
#
# TWO CUTS IN ONE PHASE, and the second's central proof is made by the first.
#
# THERE IS NOTHING TO RECOVER.  Phase 11 made the swap file memory-only; what it
# left behind is the other half -- the code that reads SOMEONE ELSE'S swap file
# back, which is code for reading a file this editor cannot have written.  -r
# and -L are the only two things that ever set `recoverymode`, so the global
# folds to FALSE and its seven readers each collapse.  ml_recover (559 lines),
# recover_names (216) and swapfile_info (103) go, and mch_get_uname() with them
# -- which is where getpwuid finally goes.
#
# AND THE MEMFILE IS MEMORY, AND ONLY MEMORY.  memfile_T still carried a
# descriptor, still knew how to page a block out and read it in, and still sized
# an LRU cache against how much memory the machine has -- all behind
# `if (mfp->mf_fd >= 0)`.  THE PROOF IS THE FIRST CUT: mf_open() has two
# callers, ml_open() passes (NULL, 0) and ml_recover() passed a name, so once
# ml_recover() is gone nothing can hand the memfile a name and mf_fd can only be
# -1.  'maxmem' and 'maxmemtot' are then options that decide nothing, and
# mch_total_mem() sized that cache through sysinfo, sysconf and getrlimit.
#
# THREE MORE THINGS FALL OUT: mch_get_host_name() wrote the machine name into
# block zero (uname); lalloc()'s retry loop existed because mf_release_all()
# might free memory by paging to disk; and check_overwrite()'s "swap file
# exists" warning, the last reader of p_dir -- which is a bug fix, phase 11
# having dropped that row while this still read it.
#
# TIME IS A DECISION, not a consequence.  swapfile_info() was the only caller of
# get_ctime(), leaving vim_localtime() with one user: add_time(), the timestamp
# in :undolist.  It goes because localtime_r() asks libc what the local zone is
# and phase 20 took away every way this editor could be told; undo history does
# not outlive the process either, so the relative form is the true one.
#
# WHAT DOES NOT CHANGE: the block structure.  Lines still live in blocks, blocks
# still have numbers.  This removes the ability to EVICT a block.
#
# THE DELTA: none.
set -eu

work=${1:?usage: whim21.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/norecover.py "$f"
python3 tools/nomemfile.py "$f"


tools/sweep.sh "$f"
# The post-condition, asked after the sweep.
for g in recoverymode ml_recover recover_names swapfile_info mch_get_uname \
         vim_localtime localtime_r strftime; do
    n=$(grep -cw -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  recovery     $g still has $n mentions after the sweep"
        grep -nw -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  recovery     nothing reads a swap file, and nothing asks the wall clock"

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


tools/phasecheck.sh "$work" "$f" .cache/symbols/before
for g in getpwuid localtime_r strftime; do
    if grep -qx -- "$g" .cache/symbols/last/undefined; then
        echo "  symbols      $g is still undefined in the object"
        exit 1
    fi
done
echo "  symbols      getpwuid is gone -- the last of the five password symbols"
for g in sysinfo getrlimit uname; do
    if grep -qx -- "$g" .cache/symbols/last/undefined; then
        echo "  symbols      $g is still undefined in the object"
        exit 1
    fi
done
echo "  symbols      sysinfo, getrlimit and uname are gone from nm -u"

tools/phasebuild.sh "$work" "$before_lines"

# The check this phase owes phase 11: the crash it is fixing.  A harness that
# does not write over an existing file under another name with `!` cannot see
# it, and none of them does -- which is how it survived twelve phases.
ov=$(cd "$work" && rm -rf .ovtest && mkdir .ovtest && cd .ovtest \
     && printf 'one\n' > a.txt && printf 'two\n' > b.txt \
     && ../whim-vim -e -s -c 'w! b.txt' -c 'qa!' a.txt </dev/null >/dev/null 2>&1
     printf '%s' "$?:$(cat b.txt 2>/dev/null)")
rm -rf "$work/.ovtest"
if [ "$ov" != "0:one" ]; then
    echo "  overwrite    :w! over an existing other file gave $ov, expected 0:one"
    exit 1
fi
echo "  overwrite    :w! over an existing other file writes it"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
