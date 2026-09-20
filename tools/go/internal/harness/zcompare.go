package harness

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

// ZDeclared reads pipes/zero.delta and returns every token up to phase, and
// the ones phase itself declares.
//
// Zero's tokens are not whim's: a zero declaration names a screen case, a
// memline case, an argv row, an Ex command, or a whole DIMENSION of the
// recording -- screen-moved, stderr-moved, term-moved, pty-moved.
func ZDeclared(path string, phase int) (map[string]bool, []string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, nil, err
	}
	defer f.Close()
	tokens := map[string]bool{}
	var own []string
	cur := -1
	s := bufio.NewScanner(f)
	s.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)
	for s.Scan() {
		line := s.Text()
		if i := strings.Index(line, "#"); i >= 0 {
			line = line[:i]
		}
		if strings.TrimSpace(line) == "" {
			continue
		}
		words := strings.Fields(line)
		if len(words) > 0 && isDigits(words[0]) &&
			(len(line) == 0 || (line[0] != ' ' && line[0] != '\t')) {
			cur, _ = strconv.Atoi(words[0])
			words = words[1:]
		}
		if cur < 0 || cur > phase {
			continue
		}
		for _, w := range words {
			if strings.HasPrefix(w, "drop:") {
				delete(tokens, w[5:])
			} else {
				tokens[w] = true
			}
			if cur == phase {
				own = append(own, w)
			}
		}
	}
	return tokens, own, s.Err()
}

func isDigits(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			return false
		}
	}
	return true
}

func zDimensions(tokens map[string]bool) map[string]bool {
	d := map[string]bool{}
	if tokens["screen-moved"] {
		d["screen"] = true
	}
	if tokens["stderr-moved"] {
		d["stderr"] = true
	}
	return d
}

// compareSet is the per-record comparison: what moved and was not declared,
// and what was declared and did not move.
func compareSet(base, new map[string]string, prefix string,
	tokens, dims, movedDim map[string]bool) (bad, still []string) {

	names := map[string]bool{}
	for n := range base {
		names[n] = true
	}
	for n := range new {
		names[n] = true
	}
	var sorted []string
	for n := range names {
		sorted = append(sorted, n)
	}
	sort.Strings(sorted)

	for _, n := range sorted {
		b, hasB := base[n]
		x, hasX := new[n]
		_ = hasB
		_ = hasX
		token := n
		if prefix != "" {
			token = prefix + strings.ReplaceAll(n, " ", "_")
		}
		if b == x {
			if tokens[token] {
				still = append(still, token)
			}
			continue
		}
		if tokens[token] {
			continue
		}
		if len(dims) > 0 && Without(b, dims) == Without(x, dims) {
			// WHICH dimension moved is asked of each one ALONE: with two
			// tokens declared, "the difference vanishes under both" would
			// otherwise let a token nothing touched pass as used.
			for d := range dims {
				if Only(b, d) != Only(x, d) {
					movedDim[d] = true
				}
			}
			continue
		}
		bad = append(bad, token)
	}
	return bad, still
}

func readBlocks(path string) map[string]string {
	data, err := os.ReadFile(path)
	if err != nil {
		return map[string]string{}
	}
	return Blocks(string(data), "=== ")
}

func readDir(path string) map[string]string {
	ents, err := os.ReadDir(path)
	if err != nil {
		return map[string]string{}
	}
	out := map[string]string{}
	for _, e := range ents {
		if e.IsDir() {
			continue
		}
		data, err := os.ReadFile(filepath.Join(path, e.Name()))
		if err != nil {
			continue
		}
		out[e.Name()] = string(data)
	}
	return out
}

// ZCompare is tools/zcompare.py: the declared delta of a zero phase, checked
// against two recordings.
func ZCompare(basedir, newdir, delta string, phase int, w io.Writer) error {
	tokens, _, err := ZDeclared(delta, phase)
	if err != nil {
		return err
	}
	dims := zDimensions(tokens)
	movedDim := map[string]bool{}
	var fail, report []string

	for _, part := range []struct{ what, kind, prefix string }{
		{"screen", "dir", "case:"},
		{"memline", "dir", "mem:"},
		{"ref-excmds.txt", "blocks", ""},
		{"ref-argv.txt", "blocks", "argv:"},
	} {
		pb := filepath.Join(basedir, part.what)
		pn := filepath.Join(newdir, part.what)
		var b, x map[string]string
		if part.kind == "dir" {
			b, x = readDir(pb), readDir(pn)
		} else {
			b, x = readBlocks(pb), readBlocks(pn)
		}
		if len(b) == 0 {
			fail = append(fail, fmt.Sprintf(
				"  delta        the baselines hold no %s -- zero phase 0 records it", part.what))
			continue
		}
		bad, still := compareSet(b, x, part.prefix, tokens, dims, movedDim)
		if len(bad) > 0 {
			fail = append(fail, fmt.Sprintf("  delta        %s moved and was not declared: %s",
				part.what, strings.Join(bad, " ")))
		}
		if len(still) > 0 {
			fail = append(fail, fmt.Sprintf(
				"  delta        a token was declared for %s and did not move: %s",
				part.what, strings.Join(still, " ")))
		}
		report = append(report, fmt.Sprintf("%s %d/%d",
			part.what, len(b)-len(bad)-len(still), len(b)))
	}

	for _, part := range []struct{ what, token string }{
		{"ref-term.txt", "term-moved"},
		{"ref-pty.txt", "pty-moved"},
	} {
		pb := filepath.Join(basedir, part.what)
		pn := filepath.Join(newdir, part.what)
		db, eb := os.ReadFile(pb)
		dn, en := os.ReadFile(pn)
		same := eb == nil && en == nil && string(db) == string(dn)
		if tokens[part.token] && same {
			fail = append(fail, fmt.Sprintf(
				"  delta        %s was declared to move and did not", part.token))
		}
		if !tokens[part.token] && !same {
			fail = append(fail, fmt.Sprintf("  delta        %s moved, and no %s is declared",
				part.what, part.token))
		}
	}

	for _, pair := range []struct{ dim, token string }{
		{"screen", "screen-moved"},
		{"stderr", "stderr-moved"},
	} {
		if dims[pair.dim] && !movedDim[pair.dim] {
			fail = append(fail, fmt.Sprintf(
				"  delta        %s was declared and nothing moved in that dimension", pair.token))
		}
	}

	if len(fail) > 0 {
		for _, l := range fail {
			fmt.Fprintln(w, l)
		}
		fmt.Fprintln(w, "               A phase here may change behaviour, but only the behaviour")
		fmt.Fprintln(w, "               it said it would.  Anything else is a bug, and a delta")
		fmt.Fprintln(w, "               list that is merely widened to fit is not a check.")
		return fmt.Errorf("zcompare: not exactly as declared")
	}

	var shown []string
	for t := range tokens {
		shown = append(shown, t)
	}
	sort.Strings(shown)
	s := "none"
	if len(shown) > 0 {
		s = strings.Join(shown, " ")
	}
	fmt.Fprintf(w, "  delta        exactly as declared: %s\n", s)
	fmt.Fprintf(w, "               %s\n", strings.Join(report, ", "))
	return nil
}
