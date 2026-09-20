#!/bin/sh
# Does implhash now see the Go implementation?  Four controls, two of which
# MUST move and one of which must NOT -- a test where everything moves proves
# nothing, because a key that changes on every edit is as useless as one that
# never changes.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools

k()  { sh tools/implhash.sh "$1" whim; }

base=$(k 13-41)
base0=$(k 0)
printf 'whim 13-41 baseline                  %s\n' "$base"
printf 'whim 0     baseline                  %s\n' "$base0"

probe() {   # probe <file> <must-move: yes|no> <label>
    echo '' >> "$2"
    got=$(k 13-41)
    git checkout "$2" 2>/dev/null
    if [ "$1" = yes ]; then
        [ "$got" != "$base" ] && printf '  MOVES     %-38s %s\n' "$3" "$got" \
            || { printf '  STUCK     %-38s %s  <- FAIL\n' "$3" "$got"; exit 1; }
    else
        [ "$got" = "$base" ] && printf '  unchanged %-38s %s\n' "$3" "$got" \
            || { printf '  MOVED     %-38s %s  <- FAIL\n' "$3" "$got"; exit 1; }
    fi
}

probe yes tools/go/internal/sweep/sweep.go      'the sweep itself'
probe yes tools/go/internal/cutil/body.go       'a file NO list ever named'
probe yes tools/go/internal/harness/zpty.go     'a dormant harness file'
probe yes tools/go/go.mod                       'the module requirements'
probe yes tools/patches/cc-v4-c23.patch         'the cc/v4 patch (was level 3)'
probe yes tools/sweep.sh                        'the wrapper (the old control)'
probe yes tools/go/internal/cut/small.go        'a dormant cutter (documented cost)'

printf 'whim 13-41 restored                  %s\n' "$(k 13-41)"
printf 'whim 0     after all of it           %s   (must equal its baseline)\n' "$(k 0)"
[ "$(k 13-41)" = "$base" ] || { echo 'FAIL: 13-41 did not restore'; exit 1; }
[ "$(k 0)" = "$base0" ]    || { echo 'FAIL: whim 0 moved'; exit 1; }
echo 'controls: all as expected'
