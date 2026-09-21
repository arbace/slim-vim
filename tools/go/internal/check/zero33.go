package check

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"

	"slimvim.local/tools/internal/harness"
)

func init() { register("zero33", Zero33) }

var (
	z33Named = regexp.MustCompile(`\{\s*"([^"]*)"`)
	z33Err   = regexp.MustCompile(`\bE\d+:`)
	z33Code  = regexp.MustCompile(`^E\d+$`)
	z33ErrW  = regexp.MustCompile(`\bE\d+\b`)
)

// z33Ask is one pty session with no file argument, and the `term=` and
// `t_Co=` answers scraped from every line of it.
func z33Ask(bin string, env []string, term string) []string {
	d, err := os.MkdirTemp("", "ztermcheck-")
	if err != nil {
		return nil
	}
	defer os.RemoveAll(d)
	text, _, err := harness.Session(bin, nil, [][]byte{[]byte(":set term? t_Co?\r"), []byte(":q!\r")},
		term, 20*time.Second, time.Second, d, env, 0, 0)
	if err != nil {
		return nil
	}
	var got []string
	for _, line := range strings.Split(strings.ToValidUTF8(string(text), "�"), "\n") {
		for _, kw := range []string{"term=", "t_Co="} {
			if i := strings.Index(line, kw); i >= 0 {
				if fs := strings.Fields(line[i:]); len(fs) > 0 {
					got = append(got, fs[0])
				}
			}
		}
	}
	return got
}

func z33Lines(p string) []string {
	s := readFile(p)
	if s == "" {
		return nil
	}
	return strings.Split(strings.TrimSuffix(s, "\n"), "\n")
}

func z33Asked(row string) string {
	i, j := strings.Index(row, "'"), strings.LastIndex(row, "'")
	if i < 0 || j <= i {
		return ""
	}
	return row[i+1 : j]
}

func printPrefixed(w io.Writer, prefix, text string) {
	for _, l := range strings.Split(strings.TrimRight(text, "\n"), "\n") {
		fmt.Fprintln(w, prefix+l)
	}
}

func unifiedHead(w io.Writer, a, b string, n int) {
	o, _ := exec.Command("diff", a, b).Output()
	ls := strings.Split(strings.TrimRight(string(o), "\n"), "\n")
	for _, l := range head(ls, n) {
		fmt.Fprintln(w, "               "+l)
	}
}

// Zero33 is zero phase 33, whole: the terminal table is asked with
// `+set term={name}`.
func Zero33(w io.Writer, args []string) error {
	if len(args) < 1 {
		return fmt.Errorf("usage: check zero33 <work-dir>")
	}
	work := args[0]
	const self = 33
	f := filepath.Join(work, "zero-vim.c")
	base := ".reference/zero-baselines"
	tmp, err := os.MkdirTemp("", "zero33")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	T := func(n string) string { return filepath.Join(tmp, n) }
	home, _ := os.MkdirTemp(tmp, "home-")
	env := harness.Env(home)

	// --- 0. the baselines must already be the new shape ----------------------
	if _, e := os.Stat(base + "/ref-term.txt"); e == nil {
		rows := z33Lines(base + "/ref-term.txt")
		ok := len(rows) == len(harness.Terms)
		for _, r := range rows {
			if !strings.HasPrefix(r, ":set term='") {
				ok = false
			}
		}
		if !ok {
			b := &rep{tag: "baselines", w: w}
			b.say("%s/ref-term.txt is not the table this phase asks for:", base)
			for _, l := range head(rows, 2) {
				fmt.Fprintln(w, "                 "+l)
			}
			b.cont("Zero phase 0 records it, from whim-vim.c -- the pipeline's")
			b.cont("immutable input -- and REFUSES to overwrite a set that")
			b.cont("differs, so a changed harness needs both paths removed:")
			fmt.Fprintln(w, "                 rm -rf .reference/zero-baselines .cache/r0 && make zero-phase-0")
			return harness.ErrReported
		}
	}

	// --- 1. the tree is untouched --------------------------------------------
	before := sha256File(f)

	// --- 2. the build ---------------------------------------------------------
	var whim chan error
	if _, e := os.Stat("whim-vim.c"); e == nil {
		whim = make(chan error, 1)
		go func() { whim <- exec.Command("gcc", "-O0", "-static", "-s", "-o", T("whim-vim"), "whim-vim.c").Run() }()
		defer func() {
			if whim != nil {
				<-whim
			}
		}()
	}
	_ = exec.Command("make", "-C", work, "clean").Run()
	if err := exec.Command("make", "-C", work).Run(); err != nil {
		(&rep{tag: "build", w: w}).say("FAILED -- rerun by hand: make -C %s", work)
		return harness.ErrReported
	}
	bin := filepath.Join(work, "zero-vim")
	if !staticFacts(w, bin) {
		return harness.ErrReported
	}
	if err := exec.Command("gcc", "-c", "-O0", "-fno-stack-protector", "-o", T("new.o"), f).Run(); err != nil {
		return harness.ErrReported
	}
	u, _ := exec.Command("nm", "-u", T("new.o")).Output()
	nu := 0
	for _, l := range strings.Split(string(u), "\n") {
		if strings.TrimSpace(l) != "" {
			nu++
		}
	}
	x, _ := exec.Command("nm", "--extern-only", "--defined-only", T("new.o")).Output()
	var ext []string
	for _, l := range strings.Split(string(x), "\n") {
		if fs := strings.Fields(l); len(fs) > 0 {
			ext = append(ext, fs[len(fs)-1])
		}
	}
	sort.Strings(ext)
	if es := trSpace(ext); es != "main " {
		(&rep{tag: "symbols", w: w}).say("the output defines external symbols other than main: %s", es)
		return harness.ErrReported
	}
	(&rep{tag: "symbols", w: w}).say("`main` is still the only external symbol, over %d undefined", nu)

	// --- 3. the new table means what it claims ------------------------------
	ztc := func(b, out string) error {
		return exec.Command("tools/st.sh", "ztermcheck", b, out).Run()
	}
	if ztc(bin, T("term")) != nil {
		return harness.ErrReported
	}
	tb := "  table        "
	rule, ok := z33Rule(f, T("term"), bin, env)
	printPrefixed(w, tb, rule)
	if !ok {
		return harness.ErrReported
	}

	// --- 4. it is the same table everywhere ----------------------------------
	sm := &rep{tag: "same", w: w}
	if whim != nil && <-whim == nil {
		whim = nil
		if ztc(T("whim-vim"), T("term-whim")) != nil {
			return harness.ErrReported
		}
		if readFile(T("term")) != readFile(T("term-whim")) {
			sm.say("whim-vim.c -- the pipeline's immutable input, and where the baselines come from -- records a DIFFERENT table:")
			unifiedHead(w, T("term-whim"), T("term"), 20)
			return harness.ErrReported
		}
		sm.say("whim-vim, built -O0 -static -s, records the identical table: the baseline is this table and not a third thing")
	} else {
		whim = nil
		sm.say("no whim-vim.c to build -- the input's own recording not rechecked")
	}
	bd := &rep{tag: "boundaries", w: w}
	if fi, e := os.Stat(".build-zero"); e == nil && fi.IsDir() {
		os.MkdirAll(T("bins"), 0o755)
		os.MkdirAll(T("rows"), 0o755)
		var names []string
		for i := 0; i <= self; i++ {
			t := fmt.Sprintf(".build-zero/r%d.tar", i)
			if _, e := os.Stat(t); e != nil {
				continue
			}
			r := fmt.Sprintf("r%d", i)
			b, e := exec.Command("tar", "-xOf", t, "./zero-vim").Output()
			if e != nil {
				if b, e = exec.Command("tar", "-xOf", t, "zero-vim").Output(); e != nil {
					continue
				}
			}
			if len(b) == 0 {
				continue
			}
			os.WriteFile(T("bins/"+r), b, 0o755)
			names = append(names, r)
		}
		sem := make(chan struct{}, 8)
		var wg sync.WaitGroup
		for _, r := range names {
			wg.Add(1)
			sem <- struct{}{}
			go func(r string) {
				defer wg.Done()
				ztc(T("bins/"+r), T("rows/"+r))
				<-sem
			}(r)
		}
		wg.Wait()
		if len(names) == 0 {
			bd.say(".build-zero holds no boundary binary -- the table not rechecked across the pipeline")
		} else {
			ents, _ := os.ReadDir(T("rows"))
			var rs []string
			for _, e := range ents {
				rs = append(rs, e.Name())
			}
			sort.Strings(rs)
			bad := false
			for _, r := range rs {
				if readFile(T("term")) != readFile(T("rows/"+r)) {
					bd.say("%s records a different table:", r)
					unifiedHead(w, T("rows/"+r), T("term"), 6)
					bad = true
				}
			}
			if bad {
				bd.cont("The baseline and the recordings do NOT move together, and re-recording would change an earlier phase's declared delta.")
				return harness.ErrReported
			}
			bd.say("all %d recorded boundary binaries up to r%d record the SAME table as whim-vim and as this one, one digest across every one of them", len(names), self)
		}
	} else {
		bd.say("no .build-zero here -- the pipeline-wide check runs where the tars are")
	}

	// --- 5. the instrument is deterministic ------------------------------------
	if !recordThrice(w, bin, f, tmp) {
		return harness.ErrReported
	}
	run1 := T("run1")
	(&rep{tag: "instrument", w: w}).say("%d cases, %d commands, %d command lines, %d pty scenarios, %d terminals: 3 identical runs, digests included",
		dirCount(filepath.Join(run1, "screen")), countHeaders(filepath.Join(run1, "ref-excmds.txt")),
		countHeaders(filepath.Join(run1, "ref-argv.txt")), countHeaders(filepath.Join(run1, "ref-pty.txt")),
		countLines([]byte(readFile(filepath.Join(run1, "ref-term.txt")))))

	// --- 6. the instrument can fail, and the one it replaces cannot ---------
	af := &rep{tag: "ablefail", w: w}
	t := readFile(f)
	i := strings.Index(t, "builtin_terminals[] = {")
	if i < 0 {
		return fmt.Errorf("builtin_terminals[] is not in %s", f)
	}
	j := strings.Index(t[i:], "\n};") + i
	var trows []string
	named := regexp.MustCompile(`^\s*\{\s*"`)
	for _, r := range strings.Split(t[i:j], "\n") {
		if named.MatchString(r) {
			trows = append(trows, r)
		}
	}
	if len(trows) == 0 {
		fmt.Fprintln(w, "builtin_terminals[] has no named row to delete: the break cannot be made")
		return harness.ErrReported
	}
	row := trows[len(trows)-1]
	if strings.Count(t, row+"\n") != 1 {
		fmt.Fprintf(w, "%s is not one line of the file, so deleting it would delete more\n", pyRepr(row))
		return harness.ErrReported
	}
	gone := regexp.MustCompile(`^\s*\{\s*"([^"]*)"`).FindStringSubmatch(row)[1]
	broken := T("broken")
	os.MkdirAll(broken, 0o755)
	os.WriteFile(filepath.Join(broken, "zero-vim.c"), []byte(strings.Replace(t, row+"\n", "", 1)), 0o644)
	if err := copyExec(filepath.Join(work, "Makefile"), filepath.Join(broken, "Makefile")); err != nil {
		return err
	}
	if exec.Command("make", "-C", broken).Run() != nil {
		af.say("the patched copy did not build -- the break is wrong, not the corpus")
		return harness.ErrReported
	}
	if ztc(filepath.Join(broken, "zero-vim"), T("broken-term")) != nil {
		return harness.ErrReported
	}
	moved, mok := z33Moved(T("term"), T("broken-term"), gone)
	if !mok {
		printPrefixed(w, "  ablefail     ", moved)
		unifiedHead(w, T("term"), T("broken-term"), 10)
		return harness.ErrReported
	}
	oldQ := func(b, out string) {
		rows := make([]string, len(harness.Terms))
		var wg sync.WaitGroup
		for k, term := range harness.Terms {
			wg.Add(1)
			go func(k int, term string) {
				defer wg.Done()
				got := strings.Join(z33Ask(b, env, term), " ")
				if got == "" {
					got = "(none)"
				}
				rows[k] = fmt.Sprintf("TERM=%-20s -> %s", pyRepr(term), got)
			}(k, term)
		}
		wg.Wait()
		os.WriteFile(out, []byte(strings.Join(rows, "\n")+"\n"), 0o644)
	}
	oldQ(bin, T("old-in"))
	oldQ(filepath.Join(broken, "zero-vim"), T("old-broken"))
	oin := readFile(T("old-in"))
	if strings.Contains(oin, "(none)") {
		af.say("the old question recorded (none) on an unbroken binary -- the control is broken, not the editor")
		return harness.ErrReported
	}
	if oin != readFile(T("old-broken")) {
		af.say("the OLD question saw the deleted row, which contradicts the reason for this phase:")
		unifiedHead(w, T("old-in"), T("old-broken"), 10)
		return harness.ErrReported
	}
	ans := map[string]bool{}
	oldRows := z33Lines(T("old-in"))
	for _, l := range oldRows {
		if k := strings.LastIndex(l, "-> "); k >= 0 {
			ans[l[k+3:]] = true
		} else {
			ans[l] = true
		}
	}
	af.say("%s, and 0 of %d under the question this replaces -- whose %d rows carry %d distinct answer between them", moved, len(oldRows), len(oldRows), len(ans))

	// --- 7. the declared delta ------------------------------------------------
	if err := run(w, "sh", "tools/zerodelta.sh", bin, f, "--phase", "33"); err != nil {
		return harness.ErrReported
	}

	// --- 1, concluded ---------------------------------------------------------
	if sha256File(f) != before {
		(&rep{tag: "source", w: w}).say("zero-vim.c was modified by a phase that must not modify it")
		return harness.ErrReported
	}
	(&rep{tag: "source", w: w}).say("zero-vim.c unchanged, %d lines: r33 is its input's tree, and only the instrument moved", countLines([]byte(readFile(f))))
	return nil
}

// z33Rule is section 3's partition: the recording against builtin_terminals[]
// and the default measured from the binary.  It returns the text the heredoc
// printed, or the message it exited with, and whether it passed.
func z33Rule(src, rec, bin string, env []string) (string, bool) {
	text := readFile(src)
	i := strings.Index(text, "builtin_terminals[] = {")
	if i < 0 {
		return "builtin_terminals[] is not in the source: nothing to check the table against", false
	}
	j := strings.Index(text[i:], "\n};")
	if j < 0 {
		return "builtin_terminals[] is not in the source: nothing to check the table against", false
	}
	var resolves []string
	for _, m := range z33Named.FindAllStringSubmatch(text[i:i+j], -1) {
		resolves = append(resolves, m[1])
	}
	if len(resolves) == 0 {
		return "builtin_terminals[] holds no named row: the rule below would be vacuous", false
	}
	d, _ := os.MkdirTemp("", "ztermcheck-")
	defer os.RemoveAll(d)
	out, _, _ := harness.Session(bin, nil, [][]byte{[]byte(":set term? t_Co?\r"), []byte(":q!\r")},
		"xterm", 20*time.Second, time.Second, d, env, 0, 0)
	def := ""
	for _, line := range strings.Split(strings.ToValidUTF8(string(out), "�"), "\n") {
		if k := strings.Index(line, "term="); k >= 0 && !z33Err.MatchString(line) {
			def = strings.Fields(line[k:])[0]
			break
		}
	}
	if def == "" {
		return "the binary answered nothing with no +set term= at all: the default is unmeasurable", false
	}
	rows := z33Lines(rec)
	asked := make([]string, len(rows))
	for k, r := range rows {
		asked[k] = z33Asked(r)
	}
	if strings.Join(asked, "\x00") != strings.Join(harness.Terms, "\x00") || len(asked) != len(harness.Terms) {
		q := func(s []string) string {
			o := make([]string, len(s))
			for k, v := range s {
				o[k] = pyRepr(v)
			}
			return "[" + strings.Join(o, ", ") + "]"
		}
		return fmt.Sprintf("the table asks about %s, and termcheck names %s", q(asked), q(harness.Terms)), false
	}
	var bad []string
	for k, row := range rows {
		name := asked[k]
		_, answer, _ := strings.Cut(row, " -> ")
		fields := strings.Fields(answer)
		got := ""
		var errs []string
		for _, x := range fields {
			if got == "" && strings.HasPrefix(x, "term=") {
				got = x
			}
			if z33Code.MatchString(x) {
				errs = append(errs, x)
			}
		}
		if contains(resolves, name) {
			if len(errs) > 0 || got != "term="+name {
				bad = append(bad, fmt.Sprintf("%-22s resolves in builtin_terminals[] and answered %s", pyRepr(name), answer))
			}
		} else if len(errs) == 0 || got != def {
			bad = append(bad, fmt.Sprintf("%-22s is in no row of builtin_terminals[] and answered %s, where a refusal and %s were due", pyRepr(name), answer, def))
		}
	}
	if len(bad) > 0 {
		return "the table does not mean what builtin_terminals[] says:\n  " + strings.Join(bad, "\n  "), false
	}
	nRef := 0
	for _, a := range asked {
		if !contains(resolves, a) {
			nRef++
		}
	}
	return fmt.Sprintf("%d rows: %d names builtin_terminals[] carries, each resolving to itself, and %d refused with an E5NN and left at %s", len(rows), len(rows)-nRef, nRef, def), true
}

// z33Moved is section 6's heredoc: exactly the deleted name's row moved, and
// from resolving to refused.
func z33Moved(was, now, gone string) (string, bool) {
	a, b := z33Lines(was), z33Lines(now)
	if len(a) != len(b) {
		return fmt.Sprintf("the broken build recorded %d rows where the input recorded %d", len(b), len(a)), false
	}
	var mv [][2]string
	for k := range a {
		if a[k] != b[k] {
			mv = append(mv, [2]string{a[k], b[k]})
		}
	}
	if len(mv) != 1 {
		return fmt.Sprintf("deleting the %s row moved %d rows, and exactly 1 was due", pyRepr(gone), len(mv)), false
	}
	name := z33Asked(mv[0][0])
	if name != gone {
		return fmt.Sprintf("deleting the %s row moved the %s row instead", pyRepr(gone), pyRepr(name)), false
	}
	_, before, _ := strings.Cut(mv[0][0], " -> ")
	_, after, _ := strings.Cut(mv[0][1], " -> ")
	if !contains(strings.Fields(before), "term="+gone) || !z33ErrW.MatchString(after) {
		return fmt.Sprintf("the %s row went %s -> %s, where resolving -> refused was due", pyRepr(gone), before, after), false
	}
	return fmt.Sprintf("deleting the %s row from builtin_terminals[] moves EXACTLY 1 of %d rows here, %s -> %s", pyRepr(gone), len(a), before, after), true
}
