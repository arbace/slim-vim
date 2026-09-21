package check

import (
	"crypto/sha256"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"slimvim.local/tools/internal/harness"
)

func init() { register("zero3", Zero3) }

func sha256File(p string) string {
	b, _ := os.ReadFile(p)
	return fmt.Sprintf("%x", sha256.Sum256(b))
}

// staticFacts is the four readelf facts every whole-phase program asserts,
// and prints the one line that says so.
func staticFacts(w io.Writer, bin string) bool {
	typ, interp, dyn, rel := z22Readelf(bin)
	if typ != "EXEC" || interp != 0 || dyn != 1 || rel != 1 {
		(&rep{tag: "static", w: w}).say("NOT absolutely static: type %s, INTERP %d, no-dynamic %d, no-relocations %d", typ, interp, dyn, rel)
		return false
	}
	(&rep{tag: "build", w: w}).say("ok, %d bytes: EXEC, no INTERP, no dynamic section, 0 relocations", sizeOf(bin))
	return true
}

// recordThrice is `tools/zrecord.sh` three times over one binary, each run
// compared with the first as `diff -r` would.
func recordThrice(w io.Writer, bin, f, tmp string) bool {
	for i := 1; i <= 3; i++ {
		out := filepath.Join(tmp, fmt.Sprintf("run%d", i))
		if err := run(w, "sh", "tools/zrecord.sh", bin, f, out); err != nil {
			return false
		}
		if i != 1 {
			if d := diffRQ(filepath.Join(tmp, "run1"), out); len(d) > 0 {
				(&rep{tag: "instrument", w: w}).say("run %d differs from run 1 -- not deterministic, not an instrument:", i)
				for _, l := range head(d, 10) {
					fmt.Fprintln(w, "               "+l)
				}
				return false
			}
		}
	}
	return true
}

// countHeaders is `grep -c '^=== '`.
func countHeaders(p string) int {
	n := 0
	for _, l := range strings.Split(readFile(p), "\n") {
		if strings.HasPrefix(l, "=== ") {
			n++
		}
	}
	return n
}

func dirCount(p string) int {
	e, _ := os.ReadDir(p)
	return len(e)
}

// Zero3 is zero phase 3, whole: the instrument becomes the screen.
func Zero3(w io.Writer, args []string) error {
	if len(args) < 1 {
		return fmt.Errorf("usage: check zero3 <work-dir>")
	}
	work := args[0]
	f := filepath.Join(work, "zero-vim.c")
	tmp, err := os.MkdirTemp("", "zero3")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)

	// --- 1. the tree is untouched ----------------------------------------
	before := sha256File(f)

	// --- 2. the build, with the boundary's flags ------------------------
	_ = exec.Command("make", "-C", work, "clean").Run()
	if err := exec.Command("make", "-C", work).Run(); err != nil {
		(&rep{tag: "build", w: w}).say("FAILED -- rerun by hand: make -C %s", work)
		return harness.ErrReported
	}
	bin := filepath.Join(work, "zero-vim")
	if !staticFacts(w, bin) {
		return harness.ErrReported
	}

	// --- 3. the instrument is deterministic -------------------------------
	if !recordThrice(w, bin, f, tmp) {
		return harness.ErrReported
	}
	run1 := filepath.Join(tmp, "run1")
	cases := dirCount(filepath.Join(run1, "screen"))
	(&rep{tag: "instrument", w: w}).say("%d cases, %d commands, %d command lines, %d pty scenarios: 3 identical runs, digests included",
		cases, countHeaders(filepath.Join(run1, "ref-excmds.txt")), countHeaders(filepath.Join(run1, "ref-argv.txt")), countHeaders(filepath.Join(run1, "ref-pty.txt")))

	// --- 4. the instrument can fail ---------------------------------------
	af := &rep{tag: "ablefail", w: w}
	const expected = "decr_dec decr_hex incr_alpha incr_bin incr_count incr_dec incr_hex incr_midword incr_oct incr_unsigned mb_incr"
	broken := filepath.Join(tmp, "broken")
	os.MkdirAll(broken, 0o755)
	t := readFile(f)
	i := strings.Index(t, "\ndo_addsub(")
	if i < 0 {
		return fmt.Errorf("do_addsub( is not in %s", f)
	}
	j := strings.Index(t[i:], "{\n")
	if j < 0 {
		return fmt.Errorf("do_addsub has no body in %s", f)
	}
	j += i + 2
	os.WriteFile(filepath.Join(broken, "zero-vim.c"), []byte(t[:j]+"    return FAIL;\n"+t[j:]), 0o644)
	if err := copyExec(filepath.Join(work, "Makefile"), filepath.Join(broken, "Makefile")); err != nil {
		return err
	}
	if exec.Command("make", "-C", broken).Run() != nil {
		af.say("the patched copy did not build -- the break is wrong, not the corpus")
		return harness.ErrReported
	}
	bs := filepath.Join(tmp, "broken-screen")
	if err := exec.Command("tools/st.sh", "zcases", filepath.Join(broken, "zero-vim"), bs).Run(); err != nil {
		return harness.ErrReported
	}
	moved := movedNames(filepath.Join(run1, "screen"), bs)
	if moved != expected+" " {
		m := moved
		if m == "" {
			m = "(none)"
		}
		af.say("a broken do_addsub() moved a different set of cases:")
		fmt.Fprintf(w, "                 got      %s\n", m)
		fmt.Fprintf(w, "                 expected %s\n", expected)
		af.cont("A corpus that cannot fail is not evidence, and one that")
		af.cont("fails differently is not this corpus.")
		return harness.ErrReported
	}
	af.say("do_addsub() returning FAIL moves exactly 11 of %d cases, and nothing else", cases)

	// --- 5. the declared delta --------------------------------------------
	if err := run(w, "sh", "tools/zerodelta.sh", bin, f, "--phase", "3"); err != nil {
		return harness.ErrReported
	}

	// --- 6. the bridge to whim's baselines --------------------------------
	br := &rep{tag: "bridge", w: w}
	wl, err := exec.Command("sh", "-c", `. tools/pipeline.sh whim && echo "${PHASE_LIST##* }"`).Output()
	if err != nil {
		return harness.ErrReported
	}
	whimLast := strings.TrimSpace(string(wl))
	if fi, e := os.Stat(".reference/baselines/behaviour"); e == nil && fi.IsDir() {
		o, e := exec.Command("sh", "tools/whimdelta.sh", bin, f, "--phase", whimLast).CombinedOutput()
		if e != nil {
			w.Write(o)
			br.say("zero-vim does NOT show whim's declared delta to phase %s", whimLast)
			return harness.ErrReported
		}
		held := ""
		re := regexp.MustCompile(`^ *delta  *exactly as declared: (.*)$`)
		for _, l := range strings.Split(string(o), "\n") {
			if m := re.FindStringSubmatch(l); m != nil {
				held = m[1]
			}
		}
		cmds := held
		if k := strings.Index(held, ";"); k >= 0 {
			cmds = held[:k]
		}
		cs := held
		if k := strings.Index(held, "cases:"); k >= 0 {
			cs = held[k+len("cases:"):]
		}
		br.say("%d commands and %d cases against slim-vim's baselines, exactly whim's declared delta to phase %s", len(strings.Fields(cmds)), len(strings.Fields(cs)), whimLast)
	} else {
		br.say("no slim baselines at .reference/baselines -- whim's delta not rechecked")
	}

	// --- 1, concluded -----------------------------------------------------
	if sha256File(f) != before {
		(&rep{tag: "source", w: w}).say("zero-vim.c was modified by a phase that must not modify it")
		return harness.ErrReported
	}
	(&rep{tag: "source", w: w}).say("zero-vim.c unchanged, %d lines: r3 is r2's tree, and only the instrument moved", countLines([]byte(readFile(f))))
	return nil
}

// movedNames is the shell's
//
//	diff -rq a b | grep -E '^(Files|Only in)' | sed 's/^Only in [^:]*: //; s/ and .*//; s/.*screen\///' | sort -u | tr '\n' ' '
//
// over two flat screen directories.
func movedNames(a, b string) string {
	set := map[string]bool{}
	only := regexp.MustCompile(`^Only in [^:]*: `)
	and := regexp.MustCompile(` and .*`)
	scr := regexp.MustCompile(`.*screen/`)
	for _, l := range diffRQ(a, b) {
		if !strings.HasPrefix(l, "Files") && !strings.HasPrefix(l, "Only in") {
			continue
		}
		l = only.ReplaceAllString(l, "")
		l = and.ReplaceAllString(l, "")
		l = scr.ReplaceAllString(l, "")
		set[l] = true
	}
	var s []string
	for k := range set {
		s = append(s, k)
	}
	sort.Strings(s)
	out := ""
	for _, k := range s {
		out += k + " "
	}
	return out
}
