package dead

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"

	"slimvim.local/tools/internal/cutil"
)

// warningLine is gcc's `file:line:col: warning: text`.
//
// The [^:]+ for the filename means a path containing a colon silently drops
// EVERY warning, and the sweep then converges immediately on unchanged text.
// Kept as it stands: the paths in use are relative, and this is what the
// comparison is against.
var warningLine = regexp.MustCompile(`^[^:]+:(\d+):\d+: warning: (.*)$`)

// The TEXT is the same for a function and a variable -- "'X' defined but not
// used" -- and only the option in brackets says which.  Matching on the text
// alone treats an unused error string as a function definition and deletes 500
// lines, because the extent scan then runs from the string to the closing
// brace of the next function it finds.
//
// neverDefined is the exception: it is keyed on the sentence alone, with no
// option bracket, because gcc emits that text under -Wunused-function and the
// sentence is unambiguous.
var (
	neverDefined = regexp.MustCompile(`'(\w+)' declared 'static' but never defined`)
	deadFunction = regexp.MustCompile(`'(\w+)' defined but not used \[-Wunused-function\]`)
	deadVariable = regexp.MustCompile(`(?:'(\w+)' defined but not used|unused variable '(\w+)')` +
		` \[-Wunused(?:-const)?-variable=?\]`)
)

// Warning is one gcc warning: the 1-based line it names, and its text.
type Warning struct {
	Line int
	Text string
}

// GccWarnings asks gcc what it warned about, and optionally keeps what it
// produced under keep/.
//
// It generates NO machine code.  The two warnings this reads --
// -Wunused-function and file-scope -Wunused-variable -- come from gcc's call
// graph, which -fsyntax-only never builds and so reports neither, measured.
// -flto -fno-fat-lto-objects does build it, warns, and writes GIMPLE instead
// of compiling: the same warnings byte for byte, in 2.4 seconds instead of
// 6.0 on a 129,000-line file.  An LTO object has no symbols for nm to read,
// which is why what is kept is the stderr and its sha and not an object.
//
// It goes in .cache/ and NOT in the work tree: a file left in the work tree is
// a file the boundary digest counts.
func GccWarnings(path, keep string) ([]Warning, error) {
	if keep != "" {
		if err := os.MkdirAll(keep, 0o755); err != nil {
			return nil, err
		}
		os.Remove(filepath.Join(keep, "last.o"))
	}
	cmd := exec.Command("gcc", "-c", "-O0", "-flto", "-fno-fat-lto-objects",
		"-Wall", "-Wextra", "-Wno-unused-parameter", "-o", "/dev/null", path)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	_ = cmd.Run() // gcc's status is not consulted: a file that fails to compile
	// yields no warning lines, and the tool is then a no-op.

	if keep != "" {
		if err := os.WriteFile(filepath.Join(keep, "last.txt"), stderr.Bytes(), 0o644); err != nil {
			return nil, err
		}
		src, err := os.ReadFile(path)
		if err != nil {
			return nil, err
		}
		sum := sha256.Sum256(src)
		if err := os.WriteFile(filepath.Join(keep, "last.sha"),
			[]byte(hex.EncodeToString(sum[:])+"\n"), 0o644); err != nil {
			return nil, err
		}
	}

	var out []Warning
	for _, line := range bytes.Split(stderr.Bytes(), []byte{'\n'}) {
		m := warningLine.FindSubmatch(line)
		if m == nil {
			continue
		}
		n, err := strconv.Atoi(string(m[1]))
		if err != nil {
			continue
		}
		out = append(out, Warning{n, string(m[2])})
	}
	return out, nil
}

func braceDelta(b []byte) int {
	return bytes.Count(b, []byte("{")) - bytes.Count(b, []byte("}"))
}

// FunctionExtent returns the first and last line indices of the definition
// reported at lineno, or ok=false.
func FunctionExtent(lines [][]byte, lineno int) (int, int, bool) {
	i := lineno - 1
	if i < 0 || i >= len(lines) {
		return 0, 0, false
	}
	// Walk back over the return type, which vim puts on its own line.
	start := i
	for start > 0 {
		prev := rtrimSpace(lines[start-1])
		if len(trimSpace(prev)) == 0 {
			break
		}
		if endsAnyByte(prev, ";{}:") || startsAny(ltrimSpace(prev), "#", "//") {
			break
		}
		start--
	}
	j := i
	for j < len(lines) && bytes.IndexByte(cutil.Blank(lines[j]), '{') < 0 {
		j++
	}
	if j >= len(lines) {
		return 0, 0, false
	}
	depth := 0
	started := false
	for j < len(lines) {
		b := cutil.Blank(lines[j])
		depth += braceDelta(b)
		if bytes.IndexByte(b, '{') >= 0 {
			started = true
		}
		if started && depth <= 0 {
			return start, j, true
		}
		j++
	}
	return 0, 0, false
}

// DeclarationExtent returns the first and last line indices of the
// declaration reported at lineno, or ok=false.
//
// "Delete the line" is wrong for the file-scope tables whose initialiser
// starts on the NEXT line: deleting only the first leaves the initialiser
// behind as a bare expression.  Run to where the declaration actually ends --
// depth back to zero and a terminating semicolon.
func DeclarationExtent(lines [][]byte, lineno int) (int, int, bool) {
	i := lineno - 1
	if i < 0 || i >= len(lines) {
		return 0, 0, false
	}
	depth := 0
	j := i
	found := false
	for j < len(lines) {
		b := cutil.Blank(lines[j])
		depth += braceDelta(b) + bytes.Count(b, []byte("(")) - bytes.Count(b, []byte(")"))
		if depth <= 0 && bytes.HasSuffix(rtrimSpace(b), []byte(";")) {
			found = true
			break
		}
		j++
		if j-i > 4000 { // runaway: decline rather than guess
			return 0, 0, false
		}
	}
	if !found {
		return 0, 0, false
	}

	// AND BACKWARDS, when the declarator closes a type definition:
	//
	//	static struct mousetable
	//	{ ... } mouse_table[] =
	//	{ ... };
	//
	// gcc reports the unused variable at `} mouse_table[] =`, and running
	// forward from there takes the initialiser and leaves the struct body
	// open.  The next declaration lands inside it and gcc says "expected
	// specifier-qualifier-list before 'static'" a hundred lines later -- which
	// is how this was found, in the phase that removed the mouse.  It is the
	// same class of mistake as keying on a warning's sentence instead of its
	// option: the extent of a thing is not the line it was reported on.
	if bytes.HasPrefix(ltrimSpace(lines[i]), []byte("}")) {
		depth = 1
		k := i - 1
		for k >= 0 {
			b := cutil.Blank(lines[k])
			depth += -braceDelta(b)
			if depth == 0 {
				break
			}
			k--
		}
		if k < 0 {
			return 0, 0, false // unbalanced: decline rather than guess
		}
		for k > 0 {
			prev := trimSpace(lines[k-1])
			if len(prev) == 0 || endsAnyByte(prev, ";}{:") || startsAny(prev, "//", "#") {
				break
			}
			k--
		}
		i = k
	} else if i > 0 &&
		!startsAny(ltrimSpace(lines[i]), "static", "const", "struct", "enum", "union") &&
		bytes.HasPrefix(trimSpace(lines[i-1]), []byte("{")) &&
		bytes.HasSuffix(rtrimSpace(cutil.Blank(lines[i-1])), []byte("}")) {
		// AND THE SAME TYPE WRITTEN ON ONE LINE, which gcc reports a line
		// lower.  The declarator does not start with '}', so the case above
		// never looked, and the sweep deleted the table and left
		// `static struct {...}` open at file scope, where it swallowed the
		// next declaration.
		k := i - 1
		for k > 0 {
			prev := trimSpace(lines[k-1])
			if len(prev) == 0 || endsAnyByte(prev, ";}{:") || startsAny(prev, "//", "#") {
				break
			}
			k--
		}
		i = k
	}

	return i, j, true
}

// SweepCounts is what DeadSweep reports.
type SweepCounts struct {
	Proto, Func, Var, Other, Lines int
}

// DeadSweep deletes what gcc says is unused.
//
// Deletions are collected as a set of line indices and applied by filtering,
// which is order-independent -- the docstring says bottom-up, and the code has
// always been the filter.
func DeadSweep(path, keep string) ([]byte, SweepCounts, error) {
	src, err := os.ReadFile(path)
	if err != nil {
		return nil, SweepCounts{}, err
	}
	lines := bytes.Split(src, []byte{'\n'})

	ws, err := GccWarnings(path, keep)
	if err != nil {
		return nil, SweepCounts{}, err
	}

	kill := map[int]bool{}
	var c SweepCounts
	for _, w := range ws {
		switch {
		case neverDefined.MatchString(w.Text):
			kill[w.Line-1] = true
			c.Proto++
		case deadFunction.MatchString(w.Text):
			if a, z, ok := FunctionExtent(lines, w.Line); ok {
				for i := a; i <= z; i++ {
					kill[i] = true
				}
				c.Func++
			} else {
				c.Other++
			}
		case deadVariable.MatchString(w.Text):
			if a, z, ok := DeclarationExtent(lines, w.Line); ok {
				for i := a; i <= z; i++ {
					kill[i] = true
				}
				c.Var++
			} else {
				c.Other++
			}
		default:
			c.Other++
		}
	}
	c.Lines = len(kill)

	kept := make([][]byte, 0, len(lines))
	for i, l := range lines {
		if !kill[i] {
			kept = append(kept, l)
		}
	}
	out := bytes.Join(kept, []byte{'\n'})
	if len(out) == 0 || out[len(out)-1] != '\n' {
		out = append(out, '\n')
	}
	return out, c, nil
}

func endsAnyByte(s []byte, set string) bool {
	if len(s) == 0 {
		return false
	}
	return bytes.IndexByte([]byte(set), s[len(s)-1]) >= 0
}

func startsAny(s []byte, prefixes ...string) bool {
	for _, p := range prefixes {
		if bytes.HasPrefix(s, []byte(p)) {
			return true
		}
	}
	return false
}

func ltrimSpace(s []byte) []byte {
	return bytes.TrimLeft(s, " \t\n\v\f\r\x1c\x1d\x1e\x1f")
}
