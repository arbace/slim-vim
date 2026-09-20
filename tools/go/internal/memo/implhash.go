// Package memo is the content-addressed half of the three-tier memoize:
// what a phase's implementation IS, so that a cached result answers exactly
// one question -- this implementation, applied to this input.
package memo

import (
	"bufio"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"slimvim.local/tools/internal/pipeline"
)

// depPath is tools/implhash.sh's extraction rule, unchanged.
//
// It greps a program's TEXT for literal paths under tools/ and pipes/.  That
// is exact enough and keeps the invalidation narrow -- editing resolve.py
// should re-run phase 5, not all ten -- and it is a blind grep rather than a
// parser, which is why a Python `import` names nothing it can see and why the
// convention is to write the path in a comment beside the import.  Do not
// delete those comments.
//
// The suffix list is a whitelist.  Anything not ending in one of these is
// invisible to the key, which is the trap a Go rewrite has to face: a .go file
// or an extensionless binary would not be hashed at all, and edits to it would
// move no key.
var depPath = regexp.MustCompile(`(tools|pipes)/[A-Za-z0-9_/-]+\.(py|sh|txt|mk|patch|go|mod|sum)`)

// depDir is the other half of that rule and it was MISSING HERE, which is the
// defect this comment exists to keep from recurring.
//
// A bare directory mention -- `tools/go/` -- expands to every file under it.
// The two implementations of this key diverged at the cutover commit, where
// tools/sweep.sh became a wrapper naming .go paths that this regexp matched
// and the shell's did not, and the gap widened when the shell gained the
// directory rule and this file did not follow.  Fifty-five of seventy-one unit
// keys disagreed and nothing noticed, because nothing runs both.
//
// (?m) is load-bearing.  grep applies the pattern per LINE, so its `$` is end
// of line; Go's default `$` is end of TEXT, which would match the directory at
// the very end of a file and nowhere else.
//
// The trailing class is what keeps `tools/patches/x.patch` from being read as
// a directory: the character after the final slash must not continue a path.
// It also means a BARE `tools/` mention expands nothing, because the pattern
// needs a second slash -- measured, `see tools/ for more` yields no match
// while `and tools/go/ here` yields `tools/go/`.
var depDir = regexp.MustCompile(`(?m)(tools|pipes)/[A-Za-z0-9_/-]*/([^A-Za-z0-9_/.-]|$)`)

// deps returns the paths a program names: the direct matches, plus every file
// under any directory it names.
//
// Files are emitted and directories never are, so a caller's regular-file
// guard and its second level of indirection work unchanged.  Every caller
// sorts what it gets, so the order within this function is not observable;
// the directory half is sorted anyway to match the shell's `LC_ALL=C sort`
// and keep the two texts comparable by eye.
func deps(path string) []string {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var out []string
	for _, m := range depPath.FindAll(data, -1) {
		out = append(out, string(m))
	}

	var dirs []string
	for _, m := range depDir.FindAll(data, -1) {
		d := string(m)
		// Drop the delimiter the pattern had to consume.  `sed 's#[^/]$##'`:
		// the last byte goes unless it is the slash itself, which is the case
		// where the directory ended the line.
		if n := len(d); n > 0 && d[n-1] != '/' {
			d = d[:n-1]
		}
		dirs = append(dirs, d)
	}

	var files []string
	for _, d := range sortUnique(dirs) {
		fi, err := os.Stat(d)
		if err != nil || !fi.IsDir() {
			continue
		}
		// `find <d> -type f`: regular files only, so a symlink or a socket
		// under tools/go/ is skipped exactly as the shell skips it.
		_ = filepath.WalkDir(d, func(p string, e fs.DirEntry, err error) error {
			if err != nil {
				return nil
			}
			if e.Type().IsRegular() {
				files = append(files, p)
			}
			return nil
		})
	}
	sort.Strings(files)
	return append(out, files...)
}

// isFile is the shell's `[ -f "$d" ]`, which os.Stat alone is not: Stat
// succeeds for a directory, and hashing one would read nothing and silently
// widen the key's meaning.
func isFile(path string) bool {
	fi, err := os.Stat(path)
	return err == nil && fi.Mode().IsRegular()
}

func sortUnique(in []string) []string {
	seen := map[string]bool{}
	var out []string
	for _, s := range in {
		if !seen[s] {
			seen[s] = true
			out = append(out, s)
		}
	}
	sort.Strings(out)
	return out
}

// ImplHash is the identity of a phase's tier-2 implementation: half of a
// memoize key, the other half being the input boundary.
//
// What counts as the implementation is the phase's own program -- or its edit
// and check parts -- plus everything it names: the tools it calls, the patches
// it applies, the tables it reads, the templates it installs.  One level of
// indirection is followed, which covers canon.sh naming seven canonicalisers.
//
// A phase with no program has no implementation to hash and answers "agent":
// tier 1 is not cacheable, because it is not a function.
//
// editOnly asks for the EDIT part alone, which is the key phaserun caches that
// edit's result under inside a stage.
func ImplHash(p pipeline.P, unit string, editOnly bool) (string, error) {
	progs := p.Parts(unit)
	if editOnly {
		var only []string
		for _, s := range progs {
			if strings.HasSuffix(s, "-edit.sh") {
				only = append(only, s)
			}
		}
		if len(only) == 0 {
			return "", fmt.Errorf("implhash: phase %s has no edit part", unit)
		}
		progs = only
	}
	if len(progs) == 0 {
		return "agent", nil
	}

	split := false
	for _, s := range progs {
		if strings.HasSuffix(s, "-edit.sh") {
			split = true
			break
		}
	}

	h := sha256.New()
	cat := func(path string) {
		if data, err := os.ReadFile(path); err == nil {
			h.Write(data)
		}
	}

	for _, prog := range progs {
		cat(prog)
	}

	// The declared delta is data: the driver checks it after a stage, and
	// phase 80's edit reads its table cut from it.  What is hashed is the
	// lines for the unit's phases and every phase before them -- not the whole
	// file, so declaring a new phase's delta at the end moves no earlier key
	// -- and, for a unit, the pipeline's checker with what it names.
	if split {
		if lines, err := deltaLines(p, unit, editOnly); err == nil {
			h.Write(lines)
		}
		if !editOnly && p.Delta != "" {
			cat(p.Delta)
			for _, e := range sortUnique(deps(p.Delta)) {
				cat(e)
			}
		}
	}

	// A split phase's implementation is both parts and what phaserun runs
	// between and before them -- the sweep and the symbol snapshot -- which
	// the programs no longer name.  Those are level-one names, as they were
	// when every program named tools/sweep.sh itself, so the sweep's own tools
	// are still hashed.  A whole program hashes exactly as it always did.
	var level1 []string
	for _, prog := range progs {
		level1 = append(level1, deps(prog)...)
	}
	if !editOnly && split {
		level1 = append(level1, "tools/phaserun.sh", "tools/sweep.sh", "tools/symbols.sh")
	}
	for _, d := range sortUnique(level1) {
		if !isFile(d) {
			continue
		}
		cat(d)
		for _, e := range sortUnique(deps(d)) {
			if isFile(e) {
				cat(e)
			}
		}
	}

	return hex.EncodeToString(h.Sum(nil))[:16], nil
}

// deltaLines selects the lines of pipes/<pipeline>.delta this unit owns.
//
// A line beginning with a digit starts a phase's block, and the block runs
// until the next such line -- so a continuation belongs to the phase above it.
// Comments and blank lines are skipped.
func deltaLines(p pipeline.P, unit string, editOnly bool) ([]byte, error) {
	path := "pipes/" + p.Impl + ".delta"
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	n := unit
	if i := strings.Index(unit, "-"); i >= 0 {
		n = unit[i+1:]
	}
	limit, err := strconv.Atoi(n)
	if err != nil {
		return nil, err
	}

	var out bytes.Buffer
	cur := 0
	s := bufio.NewScanner(f)
	s.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)
	for s.Scan() {
		line := s.Text()
		t := strings.TrimLeft(line, " \t")
		if strings.HasPrefix(t, "#") || strings.TrimSpace(line) == "" {
			continue
		}
		if len(line) > 0 && line[0] >= '0' && line[0] <= '9' {
			f := strings.Fields(line)
			if v, err := strconv.Atoi(f[0]); err == nil {
				cur = v
			}
		}
		if cur <= limit && (!editOnly || cur == limit) {
			out.WriteString(line)
			out.WriteByte('\n')
		}
	}
	return out.Bytes(), s.Err()
}
