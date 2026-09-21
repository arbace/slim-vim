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

	"slimvim.local/tools/internal/harness"
)

func init() { register("zero15", Zero15) }

var z15Provided = strings.Fields(`isalnum isalpha isblank iscntrl isdigit isgraph islower isprint
ispunct isspace isupper isxdigit isascii toascii tolower toupper
iswalnum iswalpha iswblank iswcntrl iswdigit iswgraph iswlower
iswprint iswpunct iswspace iswupper iswxdigit towlower towupper
towctrans wctrans wctype iswctype`)

var z15Had = strings.Fields("isalnum isalpha isdigit isgraph islower ispunct iscntrl isupper iswupper tolower toupper towlower towupper")

var z15Defs = strings.Fields(`musl_isdigit musl_isalpha musl_isupper musl_islower musl_isgraph
musl_isspace musl_isalnum musl_iscntrl musl_ispunct musl_tolower musl_toupper musl_atoi
musl_atol musl_bsearch musl_qsort musl_towupper musl_towlower`)

var z15Rewritten = strings.Fields("tolower toupper towlower towupper isalnum iscntrl ispunct isalpha isdigit isgraph islower isupper isspace atoi atol qsort bsearch")

// z15Calls is `(?<![\w])name\s*\(`: a call whose name is not the tail of a
// longer identifier.  RE2 has no lookbehind, so the byte before is tested.
func z15Calls(text, name string) int {
	re := regexp.MustCompile(regexp.QuoteMeta(name) + `\s*\(`)
	n := 0
	for _, m := range re.FindAllStringIndex(text, -1) {
		if m[0] > 0 {
			c := text[m[0]-1]
			if c == '_' || (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') {
				continue
			}
		}
		n++
	}
	return n
}

// Zero15 is phase 15's check: the character classes, the two ato*, qsort and
// bsearch, vendored as static musl_* functions.
func Zero15(w io.Writer, args []string) error {
	if len(args) < 2 {
		return fmt.Errorf("usage: check zero15 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	r := &rep{tag: "vendor", w: w}
	f := filepath.Join(work, "zero-vim.c")
	beforeLines := strings.TrimSpace(readFile(filepath.Join(state, "input-lines")))
	src, err := os.ReadFile(f)
	if err != nil {
		return err
	}
	newT, oldT := string(src), readFile(filepath.Join(state, "old.c"))
	stop := func(format string, a ...any) error { r.say(format, a...); return harness.ErrReported }
	tmp, err := os.MkdirTemp("", "zero15")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	words := func(t, name string) int {
		return len(regexp.MustCompile(`\b` + regexp.QuoteMeta(name) + `\b`).FindAllString(t, -1))
	}

	// --- 1. the source, as counts --------------------------------------------
	var fail []string
	var left []string
	for _, n := range z15Provided {
		if z15Calls(newT, n) > 0 {
			left = append(left, n)
		}
	}
	if len(left) > 0 {
		fail = append(fail, fmt.Sprintf("<ctype.h>/<wctype.h> still has a user: %s", strings.Join(left, " ")))
	}
	if words(newT, "iswupper") > 0 {
		fail = append(fail, "iswupper survives, and it was the dead statement")
	}
	for _, t := range []string{"wint_t", "wctype_t", "wctrans_t"} {
		if words(newT, t) > 0 {
			fail = append(fail, fmt.Sprintf("%s is still named, and it is <wctype.h>'s", t))
		}
	}
	var had []string
	for _, n := range z15Provided {
		if z15Calls(oldT, n) > 0 {
			had = append(had, n)
		}
	}
	wantHad := append([]string{}, z15Had...)
	sort.Strings(had)
	sort.Strings(wantHad)
	if strings.Join(had, " ") != strings.Join(wantHad, " ") {
		fail = append(fail, fmt.Sprintf("the input is not the file this phase was written against: it calls %s", strings.Join(had, " ")))
	}
	if words(oldT, "iswupper") == 0 {
		fail = append(fail, "the input did not name iswupper, so deleting it proves nothing")
	}
	for _, name := range z15Defs {
		if len(regexp.MustCompile(`(?m)^`+regexp.QuoteMeta(name)+`\(`).FindAllString(newT, -1)) != 1 {
			fail = append(fail, fmt.Sprintf("%s is not defined exactly once", name))
		}
	}
	block := readFile("tools/musl-ctype.txt") + readFile("tools/musl-case.txt")
	for _, name := range []string{"tolower", "toupper", "towlower", "towupper", "isalnum", "iscntrl",
		"ispunct", "isalpha", "isdigit", "isgraph", "islower", "isupper", "isspace", "atoi", "atol", "qsort", "bsearch"} {
		want := z15Calls(oldT, name) + z15Calls(block, "musl_"+name)
		if got := z15Calls(newT, "musl_"+name); got != want {
			fail = append(fail, fmt.Sprintf("musl_%s is called %d times, expected %d -- the %d sites the input called %s at, plus the %d times the vendored text names it",
				name, got, want, z15Calls(oldT, name), name, z15Calls(block, "musl_"+name)))
		}
	}
	moved := 0
	for _, n := range z15Rewritten {
		moved += z15Calls(oldT, n)
	}
	if moved != 44 {
		fail = append(fail, fmt.Sprintf("the input has %d call sites to rewrite, not the 44 this phase was written against", moved))
	}
	for _, name := range []string{"toUpper", "toLower"} {
		want := words(oldT, name)
		if words(newT, name) != want || words(newT, "musl_"+name) != want {
			fail = append(fail, fmt.Sprintf("%s is named %d times and musl_%s %d, and both must be %d -- vim KEEPS its own case tables and musl's sit BESIDE them",
				name, words(newT, name), name, words(newT, "musl_"+name), want))
		}
	}
	if z15Calls(newT, "utf_convert") != z15Calls(oldT, "utf_convert")+2 {
		fail = append(fail, fmt.Sprintf("utf_convert is called %d times, expected %d -- its own callers plus the two wrappers this phase adds",
			z15Calls(newT, "utf_convert"), z15Calls(oldT, "utf_convert")+2))
	}
	for _, p := range []struct {
		name string
		want int
	}{{"latin1flags", 3}, {"latin1upper", 2}, {"latin1lower", 2}, {"sort_strings", 3}, {"sort_compare", 2}} {
		if k := words(newT, p.name); k != p.want {
			fail = append(fail, fmt.Sprintf("%s has %d mentions, expected %d -- the folded Latin-1 arms and the sort are not this phase's", p.name, k, p.want))
		}
	}
	var directives []string
	allInc := true
	for _, l := range strings.Split(newT, "\n") {
		if strings.HasPrefix(l, "#") {
			directives = append(directives, l)
			if !strings.HasPrefix(l, "#include <") {
				allInc = false
			}
		}
	}
	if len(directives) != 18 || !allInc {
		fail = append(fail, "the directives are not the 18 #includes they were")
	}
	if !strings.Contains(newT, "#include <ctype.h>") || !strings.Contains(newT, "#include <wctype.h>") {
		fail = append(fail, "a header was removed, and removing them is phase 16's")
	}
	rows := z6RowRe.FindAllString(newT, -1)
	got, _ := harness.CommandNamesIn(src, "zero-vim.c")
	if len(rows) != 98 || len(got) != 98 {
		fail = append(fail, fmt.Sprintf("cmdnames[] has %d rows and names() reads %d; both must be 98", len(rows), len(got)))
	}
	if i := strings.Index(newT, "static struct vimoption options[]"); i >= 0 {
		j := strings.Index(newT[i:], "\n};")
		if len(z12RowRe.FindAllString(newT[i:i+j], -1)) != 108 {
			fail = append(fail, "options[] is not the 108 rows phase 12 left")
		}
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		r.cont("nm -u under-reports <ctype.h> by FIVE macro names; latin1flags,")
		r.cont("latin1upper and latin1lower SURVIVE, being read only from the")
		r.cont("unreachable arms this phase does not touch.")
		return harness.ErrReported
	}
	r.say("nothing <ctype.h> or <wctype.h> provides is called anywhere and iswupper is gone -- while the input called twelve of them and named iswupper, so the assertion is one that can fail; seventeen musl_ definitions, 44 rewritten call sites; vim keeps toUpper[] and toLower[] and musl's sit BESIDE them, utf_convert at six callers; latin1flags 3, latin1upper 2 and latin1lower 2 SURVIVING, because the seventeen other statements that cannot run are a phase of their own; 18 directives, both headers still there because removing them is phase 16's")

	// --- 2. the two equivalence tools ----------------------------------------
	for _, t := range []string{"muslcase", "muslctype"} {
		if err := run(w, "sh", "tools/st.sh", t, "--verify", f); err != nil {
			return harness.ErrReported
		}
	}

	// --- 3. the header contract, in both directions --------------------------
	strip := func(in, out string) {
		var keep []string
		for _, l := range strings.Split(readFile(in), "\n") {
			if l == "#include <ctype.h>" || l == "#include <wctype.h>" {
				continue
			}
			keep = append(keep, l)
		}
		os.WriteFile(out, []byte(strings.Join(keep, "\n")), 0o644)
	}
	noinc, noincOld := filepath.Join(tmp, "noinc.c"), filepath.Join(tmp, "noinc-old.c")
	strip(f, noinc)
	strip(filepath.Join(state, "old.c"), noincOld)
	gccArgs := []string{"-c", "-O0", "-Wall", "-Wextra", "-Wno-unused-parameter", "-o", "/dev/null"}
	if out, err := exec.Command("gcc", append(gccArgs, noinc)...).CombinedOutput(); err != nil || len(out) > 0 {
		r.say("the produced source does not compile without <ctype.h> and <wctype.h>, so phase 16 could not remove them:")
		lines := strings.Split(strings.TrimRight(string(out), "\n"), "\n")
		for i, l := range lines {
			if i >= 5 {
				break
			}
			r.cont("  %s", l)
		}
		return harness.ErrReported
	}
	if exec.Command("gcc", append(gccArgs, noincOld)...).Run() == nil {
		return stop("the INPUT also compiles without the two headers, so this check cannot fail and proves nothing")
	}
	oldErr, _ := exec.Command("gcc", "-c", "-O0", "-o", "/dev/null", noincOld).CombinedOutput()
	r.say("the produced source compiles SILENTLY with #include <ctype.h> and <wctype.h> deleted, and the source this phase was handed gives %d errors under the same deletion -- that pair, and not a grep, is what says phase 16 can move",
		countLinesWith(oldErr, "error:"))

	// --- 4. the compile, the linkage and the libc surface --------------------
	before := strings.Fields(readFile(filepath.Join(state, "symbols", "undefined")))
	if err := run(w, "sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols")); err != nil {
		return harness.ErrReported
	}
	after := strings.Fields(readFile(".cache/symbols/last/undefined"))
	goneU, cameU := comm23(before, after), comm23(after, before)
	if strings.Join(goneU, " ") != "atoi atol bsearch isalnum iscntrl ispunct qsort tolower toupper towlower towupper" || len(cameU) > 0 {
		r.say("the libc surface did not move by exactly the eleven:")
		r.cont("  gone: %s ", strings.Join(goneU, " "))
		r.cont("  came: %s ", strings.Join(cameU, " "))
		return harness.ErrReported
	}
	for _, keep := range strings.Fields("read write close dup ioctl select tcgetattr tcsetattr nanosleep isatty printf fflush stderr malloc free realloc time gettimeofday sigaction kill raise getpid exit _exit __errno_location") {
		if !contains(after, keep) {
			return stop("%s went, and it is not this phase's: this phase takes only what is a function of its arguments", keep)
		}
	}
	for _, absent := range strings.Fields("open creat openat stat access fcntl getcwd strerror fopen fdopen opendir fclose getc putc fsync") {
		if contains(after, absent) {
			return stop("%s is undefined, and the core has had no way to open a file since phase 13", absent)
		}
	}
	r.say("symbols %s -> %s, the set is exactly atoi atol bsearch isalnum iscntrl ispunct qsort tolower toupper towlower towupper -- and FIVE MORE identifiers left the source with no symbol to show for it, isalpha isdigit isgraph islower isupper being macros in musl, which is why phase 16 needs this phase's own count and not nm -u",
		strings.TrimSpace(readFile(".cache/symbols/last/before")),
		strings.TrimSpace(readFile(".cache/symbols/last/after")))

	// --- 5. the enumerators --------------------------------------------------
	evOld, evNew := filepath.Join(tmp, "ev.old"), filepath.Join(tmp, "ev.new")
	var ewg sync.WaitGroup
	ewg.Add(1)
	go func() { defer ewg.Done(); exec.Command("sh", "tools/enumvals.sh", filepath.Join(state, "old.c"), evOld).Run() }()
	exec.Command("sh", "tools/enumvals.sh", f, evNew).Run()
	ewg.Wait()
	if err := z15Enums(r, readFile(evOld), readFile(evNew)); err != nil {
		return err
	}

	// --- 6. the structural tools, none of whose tables this phase touches ----
	for _, t := range []string{"nvidx", "orphanopts"} {
		if err := run(w, "sh", "tools/st.sh", t, f); err != nil {
			return harness.ErrReported
		}
	}

	// --- 7. the binary -------------------------------------------------------
	_ = exec.Command("make", "-C", work, "clean").Run()
	if err := exec.Command("make", "-C", work).Run(); err != nil {
		(&rep{tag: "build", w: w}).say("FAILED -- rerun by hand: make -C %s", work)
		return harness.ErrReported
	}
	bin, _ := filepath.Abs(filepath.Join(work, "zero-vim"))
	old, _ := filepath.Abs(filepath.Join(state, "old"))
	hdr, _ := exec.Command("readelf", "-h", bin).Output()
	if !regexp.MustCompile(`Type:.*EXEC`).Match(hdr) {
		return stop("the binary is no longer EXEC")
	}
	if pl, _ := exec.Command("readelf", "-l", bin).Output(); strings.Contains(string(pl), "INTERP") {
		return stop("the binary grew an INTERP")
	}
	if dyn, _ := exec.Command("readelf", "-d", bin).Output(); strings.Contains(string(dyn), "Dynamic section") {
		return stop("the binary grew a dynamic section")
	}
	now, _ := os.ReadFile(f)
	(&rep{tag: "build", w: w}).say("ok, %s -> %d lines, %d bytes -- and it GROWS, because the 358 convertStruct rows are data the image did not carry and musl packed the same mapping into 16,998 bytes",
		beforeLines, countLines(now), sizeOf(bin))

	return z15Probes(r, old, bin)
}

func z15Enums(r *rep, oldTxt, newTxt string) error {
	load := func(s string) map[string]string {
		m := map[string]string{}
		for _, l := range strings.Split(s, "\n") {
			if i := strings.LastIndexByte(l, '='); i > 0 {
				m[l[:i]] = l[i+1:]
			}
		}
		return m
	}
	o, n := load(oldTxt), load(newTxt)
	var gone, came, moved []string
	for k := range o {
		if _, ok := n[k]; !ok {
			gone = append(gone, k)
		} else if n[k] != o[k] {
			moved = append(moved, k)
		}
	}
	for k := range n {
		if _, ok := o[k]; !ok {
			came = append(came, k)
		}
	}
	sort.Strings(gone)
	sort.Strings(came)
	sort.Strings(moved)
	if len(gone)+len(came)+len(moved) > 0 {
		for _, p := range []struct {
			what string
			s    []string
		}{{"went", gone}, {"arrived", came}, {"renumbered", moved}} {
			if len(p.s) > 0 {
				r.say("enumerators %s: %s", p.what, strings.Join(p.s, " "))
			}
		}
		return harness.ErrReported
	}
	r.say("enumerators %d -> %d: not one went, arrived or renumbered -- this phase adds functions and two convertStruct tables and touches no enum", len(o), len(n))
	return nil
}
