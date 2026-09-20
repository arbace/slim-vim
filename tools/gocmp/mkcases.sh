#!/bin/sh
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
out=tools/go/internal/harness/cases.go
cat > "$out" <<'HDR'
package harness

// behaviourCases is tools/behaviour.py's CASES, transcribed by a program and
// not by hand: 67 small independent edits, each recorded.
//
// The 16-case harness that preceded it could not see the damage a bad
// constant-fold did, because it never incremented a hex number or stripped
// autoindent.  This one drives the normal-mode and Ex surface broadly.
//
// It is NOT the sweep that finds everything: the one segfault that reached a
// build here -- a version string overflowing a 20-byte buffer, so :intro
// crashed -- was invisible to all 67 of these and to every pty scenario, and
// the mechanical dispatch over every Ex command name found it.  Breadth of
// shape and breadth of entry point are different things.
var behaviourCases = []struct {
	name string
	text string
	cmds []string
}{
HDR
cat ${GOCMP:-tools/gocmp}/cases.go.txt >> "$out"
echo '}' >> "$out"
gofmt -l "$out" || true
grep -c '^	{"' "$out"
