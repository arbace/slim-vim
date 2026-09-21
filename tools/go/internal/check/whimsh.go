package check

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"slimvim.local/tools/internal/harness"
)

// The whim checks that were plain shell, and what they need to stay that.
//
// Each check is a line-for-line transcription of its pipes/whim<N>-check.sh:
// the same assertions in the same order, the same text on the same line, the
// same first refusal ending the run.  These are the shell's primitives, and
// the one that is easy to get wrong is the first: grep without -E is a BASIC
// regular expression, where ( ) { } | + ? are LITERALS, and RE2 reads every
// one of them as an operator -- so a BRE handed to Go unconverted is either a
// compile error or, worse, a pattern that matches something else.

// wsh is one check's shell: its work tree, its state directory, the source
// and the line count the edit was handed.
type wsh struct {
	w                   io.Writer
	work, state, f      string
	before              string
	srcCache            string
	srcRead             bool
}

func newWsh(w io.Writer, name string, args []string) (*wsh, error) {
	if len(args) < 2 {
		return nil, fmt.Errorf("usage: check %s <work-dir> <state-dir>", name)
	}
	s := &wsh{w: w, work: args[0], state: args[1]}
	s.f = filepath.Join(s.work, "whim-vim.c")
	s.before = strings.TrimSpace(readFile(filepath.Join(s.state, "input-lines")))
	return s, nil
}

// src is the source, read once: nothing a check does after its first grep
// writes whim-vim.c.
func (s *wsh) src() string {
	if !s.srcRead {
		s.srcCache, s.srcRead = readFile(s.f), true
	}
	return s.srcCache
}

func (s *wsh) echo(format string, a ...any) { fmt.Fprintf(s.w, format+"\n", a...) }

func (s *wsh) phasecheck() error {
	if run(s.w, "sh", "tools/phasecheck.sh", s.work, s.f, filepath.Join(s.state, "symbols")) != nil {
		return harness.ErrReported
	}
	return nil
}

func (s *wsh) phasebuild() error {
	if run(s.w, "sh", "tools/phasebuild.sh", s.work, s.before) != nil {
		return harness.ErrReported
	}
	return nil
}

// st runs `tools/st.sh <args>` with its output passed through, as a check's
// own_checks does, and reports whether it succeeded.
func (s *wsh) st(args ...string) bool {
	return run(s.w, "tools/st.sh", args...) == nil
}

// ---- grep --------------------------------------------------------------

type gmode int

const (
	gBRE  gmode = iota // grep
	gERE               // grep -E
	gBREw              // grep -w
	gEREw              // grep -Ew
	gFix               // grep -F
)

// bre2re translates a GNU basic regular expression into RE2.
func bre2re(p string) string {
	var b strings.Builder
	for i := 0; i < len(p); i++ {
		c := p[i]
		switch {
		case c == '\\' && i+1 < len(p):
			i++
			switch d := p[i]; d {
			case '(', ')', '{', '}', '|', '+', '?':
				b.WriteByte(d)
			case '<', '>':
				b.WriteString(`\b`)
			default:
				b.WriteByte('\\')
				b.WriteByte(d)
			}
		case c == '[':
			j := i + 1
			if j < len(p) && p[j] == '^' {
				j++
			}
			if j < len(p) && p[j] == ']' {
				j++
			}
			for j < len(p) && p[j] != ']' {
				if p[j] == '[' && j+1 < len(p) && (p[j+1] == ':' || p[j+1] == '.' || p[j+1] == '=') {
					if k := strings.Index(p[j+2:], string(p[j+1])+"]"); k >= 0 {
						j += k + 4
						continue
					}
				}
				j++
			}
			if j >= len(p) {
				b.WriteString(regexp.QuoteMeta(p[i:]))
				return b.String()
			}
			b.WriteString(strings.ReplaceAll(p[i:j+1], `\`, `\\`))
			i = j
		case strings.IndexByte("(){}|+?", c) >= 0:
			b.WriteByte('\\')
			b.WriteByte(c)
		default:
			b.WriteByte(c)
		}
	}
	return b.String()
}

// ere2re is GNU ERE into RE2: the same but for \< and \>.
func ere2re(p string) string {
	return strings.NewReplacer(`\<`, `\b`, `\>`, `\b`).Replace(p)
}

func gre(pat string, m gmode) *regexp.Regexp {
	var r string
	switch m {
	case gBRE:
		r = bre2re(pat)
	case gERE:
		r = ere2re(pat)
	case gBREw:
		r = `\b(?:` + bre2re(pat) + `)\b`
	case gEREw:
		r = `\b(?:` + ere2re(pat) + `)\b`
	case gFix:
		r = regexp.QuoteMeta(pat)
	}
	return regexp.MustCompile(r)
}

func lines(text string) []string {
	if text == "" {
		return nil
	}
	return strings.Split(strings.TrimSuffix(text, "\n"), "\n")
}

// grepLines is every line of text grep would print, with its number.
func grepLines(text, pat string, m gmode) (nums []int, out []string) {
	re := gre(pat, m)
	for i, l := range lines(text) {
		if re.MatchString(l) {
			nums, out = append(nums, i+1), append(out, l)
		}
	}
	return
}

func grepC(text, pat string, m gmode) int { n, _ := grepLines(text, pat, m); return len(n) }
func grepQ(text, pat string, m gmode) bool { return grepC(text, pat, m) > 0 }

// grepO is `grep -o`: every match, in order.
func grepO(text, pat string, m gmode) []string {
	re := gre(pat, m)
	var out []string
	for _, l := range lines(text) {
		out = append(out, re.FindAllString(l, -1)...)
	}
	return out
}

// cutC is `cut -c1-N`, which counts bytes.
func cutC(l string, n int) string {
	if len(l) > n {
		return l[:n]
	}
	return l
}

// show is `grep -n PAT f | head -3 | sed 's/^/               /' | cut -c1-100`.
func (s *wsh) show(pat string, m gmode) {
	nums, ls := grepLines(s.src(), pat, m)
	for i := 0; i < len(nums) && i < 3; i++ {
		fmt.Fprintln(s.w, cutC(fmt.Sprintf("               %d:%s", nums[i], ls[i]), 100))
	}
}

// gone is the loop nearly every check opens with: each pattern must have no
// line in the source, and the first that does is named, with whatever the
// check says next and three matching lines.  count and shown are separate
// modes because one check counts with one grep and shows with another.
func (s *wsh) gone(prefix string, count, shown gmode, display bool, extra []string, pats ...string) bool {
	return s.goneW(prefix, "%s", count, shown, display, extra, pats...)
}

// goneW is gone where the loop greps a pattern built around the name --
// `grep -cE "\b$g\b"` -- and names the bare $g when it refuses.
func (s *wsh) goneW(prefix, wrap string, count, shown gmode, display bool, extra []string, names ...string) bool {
	for _, g := range names {
		pat := strings.ReplaceAll(wrap, "%s", g)
		if n := grepC(s.src(), pat, count); n != 0 {
			s.echo("%s%s still has %d mentions after the sweep", prefix, g, n)
			for _, e := range extra {
				s.echo("%s", e)
			}
			if display {
				s.show(pat, shown)
			}
			return false
		}
	}
	return true
}

// undefined is `grep -qx SYM .cache/symbols/last/undefined`.
func undefined(sym string) bool {
	for _, l := range lines(readFile(".cache/symbols/last/undefined")) {
		if l == sym {
			return true
		}
	}
	return false
}

func symNum(which string) int {
	n, _ := strconv.Atoi(strings.TrimSpace(readFile(".cache/symbols/last/" + which)))
	return n
}

// awkRanges is `awk '/FROM/,/TO/' f`: every range, each from a line FROM
// matches to the next line TO matches, the start line included in both tests.
func awkRanges(text, from, to string) string {
	f, t := regexp.MustCompile(from), regexp.MustCompile(to)
	var out []string
	in := false
	for _, l := range lines(text) {
		if !in && f.MatchString(l) {
			in = true
		}
		if in {
			out = append(out, l)
			if t.MatchString(l) {
				in = false
			}
		}
	}
	if len(out) == 0 {
		return ""
	}
	return strings.Join(out, "\n") + "\n"
}

// ---- files --------------------------------------------------------------

// catS is "$(cat f)": the contents with trailing newlines removed, empty when
// there is no file.
func catS(p string) string { return strings.TrimRight(readFile(p), "\n") }

// bar is "$(tr '\n' '|' < f)".
func bar(p string) string { return strings.ReplaceAll(readFile(p), "\n", "|") }

func put(p, s string) { os.WriteFile(p, []byte(s), 0o644) }

// odX is "$(od -An -tx1 f | tr -d ' \n')".
func odX(p string) string {
	var b strings.Builder
	for _, c := range []byte(readFile(p)) {
		fmt.Fprintf(&b, "%02x", c)
	}
	return b.String()
}

// odC is "$(od -An -c f | tr -d ' \n')": printable bytes as themselves, the
// C escapes od knows by name, and every other byte as three octal digits.
func odC(p string) string {
	var b strings.Builder
	for _, c := range []byte(readFile(p)) {
		switch c {
		case 0:
			b.WriteString(`\0`)
		case '\a':
			b.WriteString(`\a`)
		case '\b':
			b.WriteString(`\b`)
		case '\f':
			b.WriteString(`\f`)
		case '\n':
			b.WriteString(`\n`)
		case '\r':
			b.WriteString(`\r`)
		case '\t':
			b.WriteString(`\t`)
		case '\v':
			b.WriteString(`\v`)
		default:
			if c >= 0x20 && c < 0x7f {
				if c != ' ' {
					b.WriteByte(c)
				}
			} else {
				fmt.Fprintf(&b, "%03o", c)
			}
		}
	}
	return b.String()
}

// odCs is "$(od -An -c f | tr -s ' ')", which only a refusal prints; close
// enough to read, and never compared.
func odCs(p string) string {
	o, _ := exec.Command("sh", "-c", `od -An -c "$1" | tr -s ' '`, "sh", p).Output()
	return strings.TrimRight(string(o), "\n")
}

// catA is `cat -A`: $ at every line end, ^I for tab, ^X and M- for the rest.
func catA(p string) string {
	var b strings.Builder
	for _, c := range []byte(readFile(p)) {
		switch {
		case c == '\n':
			b.WriteString("$\n")
		case c == '\t':
			b.WriteString("^I")
		case c >= 0x80:
			b.WriteString("M-")
			c -= 0x80
			fallthrough
		default:
			switch {
			case c < 0x20:
				b.WriteByte('^')
				b.WriteByte(c + 64)
			case c == 0x7f:
				b.WriteString("^?")
			default:
				b.WriteByte(c)
			}
		}
	}
	return b.String()
}

// ---- running the editor ---------------------------------------------------

// scratch is `d=$(mktemp -d); cp "$work/whim-vim" "$d/vim"`.
func (s *wsh) scratch() (string, func()) {
	d, _ := os.MkdirTemp("", "whimchk")
	copyExec(filepath.Join(s.work, "whim-vim"), filepath.Join(d, "vim"))
	return d, func() { os.RemoveAll(d) }
}

func envWith(kv ...string) []string {
	drop := map[string]bool{}
	for _, x := range kv {
		drop[x[:strings.IndexByte(x, '=')]] = true
	}
	var env []string
	for _, x := range os.Environ() {
		if i := strings.IndexByte(x, '='); i >= 0 && drop[x[:i]] {
			continue
		}
		env = append(env, x)
	}
	return append(env, kv...)
}

// vimRC is `(cd DIR && [HOME=HOME] BIN ARGS... </dev/null >/dev/null 2>&1)`
// and its exit status.
func vimRC(dir, home, bin string, args ...string) int {
	_, rc := vimOut(dir, home, bin, false, args...)
	return rc
}

// vimOut is the same with stdout and stderr captured together, as
// `$(cd DIR && BIN ARGS </dev/null 2>&1)` captures them -- minus the trailing
// newlines $( ) strips.
func vimOut(dir, home, bin string, capture bool, args ...string) (string, int) {
	c := exec.Command(bin, args...)
	c.Dir = dir
	if home != "" {
		c.Env = envWith("HOME=" + home)
	}
	var o bytes.Buffer
	if capture {
		c.Stdout, c.Stderr = &o, &o
	}
	err := c.Run()
	rc := 0
	if err != nil {
		if _, ok := err.(*exec.ExitError); ok {
			rc = exitCode(err)
		} else {
			rc = 127
		}
	}
	return strings.TrimRight(o.String(), "\n"), rc
}

// inD runs the scratch copy the way the later checks do:
// `(cd "$d" && HOME="$d" ./vim ARGS </dev/null >/dev/null 2>&1)`.
func inD(d string, args ...string) int { return vimRC(d, d, "./vim", args...) }

// inWork is `(cd "$work" && ./whim-vim ARGS </dev/null >/dev/null 2>&1)`.
func (s *wsh) inWork(args ...string) int { return vimRC(s.work, "", "./whim-vim", args...) }

// outWork is `$(cd "$work" && ./whim-vim ARGS </dev/null 2>&1)` and its status.
func (s *wsh) outWork(args ...string) (string, int) {
	return vimOut(s.work, "", "./whim-vim", true, args...)
}

// sub makes `$work/<name>` afresh, as `rm -rf .x && mkdir .x`.
func (s *wsh) sub(name string) string {
	p := filepath.Join(s.work, name)
	os.RemoveAll(p)
	os.MkdirAll(p, 0o755)
	return p
}

// lsA is "$(ls -A | tr '\n' ' ')".
func lsA(dir string) string {
	e, _ := os.ReadDir(dir)
	var n []string
	for _, x := range e {
		n = append(n, x.Name())
	}
	sort.Strings(n)
	var b strings.Builder
	for _, x := range n {
		b.WriteString(x + " ")
	}
	return b.String()
}

// sedN is `sed -n Np f`.
func sedN(p string, n int) string {
	ls := lines(readFile(p))
	if n-1 < len(ls) {
		return ls[n-1]
	}
	return ""
}

// std is the whole of a check whose body is the two tools and nothing else.
func stdWhim(name string) Func {
	return func(w io.Writer, args []string) error {
		s, err := newWsh(w, name, args)
		if err != nil {
			return err
		}
		if err := s.phasecheck(); err != nil {
			return err
		}
		return s.phasebuild()
	}
}

// odXs is "$(od -An -tx1 f)" as a refusal prints it.
func odXs(p string) string {
	o, _ := exec.Command("od", "-An", "-tx1", p).Output()
	return strings.TrimRight(string(o), "\n")
}
