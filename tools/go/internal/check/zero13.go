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

	"slimvim.local/tools/internal/cutil"
	"slimvim.local/tools/internal/harness"
)

func init() { register("zero13", Zero13) }

const z13Mark = "FILESTAR-ENTERED"

var z13Gone = []string{"scriptin", "curscript", "NSCRIPT", "saved_typebuf", "closescript", "using_script",
	"redir_fd", "redir_off", "redir_write", "redirecting", "vim_fsync", "script_char",
	"retesc", "did_return", "FILE"}

// z13Sites are the five places the probe marks, each asserted to occur exactly
// once in the input so the instrument lands where the argument says it does.
var z13Sites = []struct{ text, what string }{
	{"closescript(void)\n{\n", "the top of closescript()"},
	{"    while (scriptin[curscript] != NULL && script_char < 0)\n    {\n", "inchar()'s script loop, which is getc()'s only caller"},
	{"    if (redirecting())\n    {\n", "redir_write()'s redirecting() block"},
	{"        if (redirecting())\n        {\n", "undo_cmdmod's redirecting() block"},
	{"vim_fsync(int fd)\n{\n", "the top of vim_fsync()"},
}

var z13Kept = map[string]int{
	"may_sync_undo": 3, "is_safe_now": 3, "free_typebuf": 4, "ui_write": 3, "mch_write": 2,
	"read_cmd_fd": 12, "p_paste": 12, "u_sync": 8,
}

var z13Absent = []string{"open", "creat", "openat", "fopen", "fdopen", "opendir", "stat",
	"access", "fcntl", "getcwd", "strerror", "fclose", "getc", "putc",
	"fsync", "mkdir", "rename", "unlink", "readlink"}

// Zero13 is phase 13's check: no FILE * that is never opened.
func Zero13(w io.Writer, args []string) error {
	if len(args) < 2 {
		return fmt.Errorf("usage: check zero13 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	r := &rep{tag: "nofile", w: w}
	f := filepath.Join(work, "zero-vim.c")
	beforeLines := strings.TrimSpace(readFile(filepath.Join(state, "input-lines")))
	stop := func(format string, a ...any) error { r.say(format, a...); return harness.ErrReported }
	tmp, err := os.MkdirTemp("", "zero13")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	inst := filepath.Join(tmp, "i")
	os.MkdirAll(inst, 0o755)

	// The two instrumented builds start first, as in zero9.
	mk := readFile(filepath.Join(work, "Makefile"))
	cflags, ldflags := strings.Fields(z9Flag(mk, "CFLAGS")), strings.Fields(z9Flag(mk, "LDFLAGS"))
	oldC := readFile(filepath.Join(state, "old.c"))
	mark := "    (void)write(2, \"" + z13Mark + "\\n\", 17);\n"
	probe := oldC
	for _, s := range z13Sites {
		if n := strings.Count(probe, s.text); n != 1 {
			return stop("%s occurs %d times in the input source, expected 1", s.what, n)
		}
		probe = strings.Replace(probe, s.text, s.text+mark, 1)
	}
	os.WriteFile(filepath.Join(inst, "probe.c"), []byte(probe), 0o644)
	const ctlHead = "ui_write(char_u *s, int len, int console  __attribute__((unused)) )\n{\n"
	if strings.Count(oldC, ctlHead) != 1 {
		return stop("ui_write does not open exactly once in the input source")
	}
	os.WriteFile(filepath.Join(inst, "ctl.c"), []byte(strings.Replace(oldC, ctlHead, ctlHead+mark, 1)), 0o644)
	var bwg sync.WaitGroup
	buildErr := map[string]error{}
	var bmu sync.Mutex
	for _, n := range []string{"probe", "ctl"} {
		bwg.Add(1)
		go func(n string) {
			defer bwg.Done()
			a := append(append(append([]string{}, cflags...), ldflags...), "-o", n, n+".c")
			c := exec.Command("gcc", a...)
			c.Dir = inst
			e := c.Run()
			bmu.Lock()
			buildErr[n] = e
			bmu.Unlock()
		}(n)
	}

	src, err := os.ReadFile(f)
	if err != nil {
		return err
	}
	newT := string(src)

	// --- 1. what went --------------------------------------------------------
	for _, g := range z13Gone {
		if n := countWord(src, g); n != 0 {
			return stop("'%s' still has %d mentions", g, n)
		}
	}
	r.say("FILE at 0 mentions -- the type is not named in zero-vim.c at all now -- with scriptin, curscript, NSCRIPT, saved_typebuf, closescript, using_script, redir_fd, redir_off, redir_write, redirecting, vim_fsync and the two hand-folded locals")

	// --- 2. and everything that must NOT be at zero --------------------------
	var fail []string
	count := func(t, name string) int {
		return len(regexp.MustCompile(`\b` + regexp.QuoteMeta(name) + `\b`).FindAllString(t, -1))
	}
	names := make([]string, 0, len(z13Kept))
	for n := range z13Kept {
		names = append(names, n)
	}
	sort.Strings(names)
	for _, name := range names {
		want := z13Kept[name]
		if k := count(newT, name); k != want {
			why := "something survived that should not have"
			if k < want {
				why = "this phase reached too far"
			}
			fail = append(fail, fmt.Sprintf("%s has %d mentions, expected %d -- %s", name, k, want, why))
		}
	}
	if !regexp.MustCompile(`(?m)^ui_write\(char_u \*s, int len\)$`).MatchString(newT) {
		fail = append(fail, "ui_write does not have a two-parameter signature: dropping the parameter is what makes the cut honest, because sweep.sh compiles with -Wno-unused-parameter and would never see it")
	}
	if !strings.Contains(newT, "ui_write(out_buf, len);") {
		fail = append(fail, "ui_write's one call site still passes a third argument")
	}
	bodyOf := func(fn string) string {
		if a, z, ok := cutil.FindDefinition(src, cutil.Blank(src), fn); ok {
			return newT[a:z]
		}
		return ""
	}
	if b := bodyOf("ui_write"); strings.Count(b, ";") != 1 || !strings.Contains(b, "mch_write") {
		fail = append(fail, fmt.Sprintf("ui_write is not mch_write() and nothing else now: %s", cutilRepr(b)))
	}
	if b := bodyOf("may_sync_undo"); strings.Contains(b, "scriptin") || !strings.Contains(b, "u_sync") || !strings.Contains(b, "arrow_used") {
		fail = append(fail, fmt.Sprintf("may_sync_undo is not one conjunct shorter with u_sync() still in it: %s", cutilRepr(b)))
	}
	safe := bodyOf("is_safe_now")
	for _, keep := range []string{"stuff_empty", "typebuf.tb_len", "global_busy"} {
		if !strings.Contains(safe, keep) {
			fail = append(fail, fmt.Sprintf("is_safe_now lost %s, and it keeps everything but the scriptin conjunct", keep))
		}
	}
	for _, g := range []string{"fputs", "fputc", "fwrite", "putchar"} {
		if count(newT, g) > 0 {
			fail = append(fail, fmt.Sprintf("%s is named in the source, and it should not be -- gcc lowers printf and fprintf to it", g))
		}
	}
	// `(?<![\w.>])name\s*\(` -- RE2 has no lookbehind, so the preceding byte is
	// tested directly: a call, not a member access `x.open(`, a `->open(` or a
	// longer identifier ending in the name.
	for _, absent := range z13Absent {
		if calledBare(newT, absent) {
			fail = append(fail, fmt.Sprintf("%s( is called in the source, and after this phase the core has no way to name or open anything", absent))
		}
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
	for _, p := range []struct {
		name string
		want int
	}{{"scriptin", 8}, {"redir_fd", 6}, {"redirecting", 4}, {"redir_write", 7}, {"vim_fsync", 3}, {"FILE", 2}, {"free_typebuf", 5}} {
		if count(oldC, p.name) != p.want {
			fail = append(fail, fmt.Sprintf("the input is not the file this phase was written against: %s %d, expected %d", p.name, count(oldC, p.name), p.want))
		}
	}
	if strings.Contains(oldC, "FILESTAR") || strings.Contains(newT, "FILESTAR") {
		fail = append(fail, "the instrument marker is in a source file, and it belongs only to the two builds this check makes in a temp directory")
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		r.cont("may_sync_undo and is_safe_now SURVIVE folded, and a check that")
		r.cont("expected them at 0 fails on a correct phase; fputs STAYS and is")
		r.cont("gcc's own, named nowhere in the source.")
		return harness.ErrReported
	}
	r.say("kept: may_sync_undo 3 and is_safe_now 3, both SURVIVING one conjunct shorter and still doing their work, free_typebuf 4 (closescript was its fifth mention), ui_write 3 with a TWO-parameter signature and mch_write() as its whole body")
	r.cont("fputs, fputc, fwrite and putchar are named nowhere in the source and are gcc's own -- ZERO-PLAN.md row 12 gives fputs to this phase and it does not go")
	r.cont("and nothing that could open or name anything is called: open, creat, openat, fopen, fdopen, opendir, stat, access, fcntl, getcwd, strerror, fclose, getc, putc and fsync are absent from the source")

	// --- 3. the compile, the linkage and the libc surface --------------------
	before := strings.Fields(readFile(filepath.Join(state, "symbols", "undefined")))
	if err := run(w, "sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols")); err != nil {
		return harness.ErrReported
	}
	after := strings.Fields(readFile(".cache/symbols/last/undefined"))
	goneU, cameU := comm23(before, after), comm23(after, before)
	if strings.Join(goneU, "\n") != "fclose\nfsync\ngetc\nputc" || len(cameU) > 0 {
		r.say("the libc surface did not move by exactly fclose, fsync, getc and putc:")
		r.cont("  gone: %s ", strings.Join(goneU, " "))
		r.cont("  came: %s ", strings.Join(cameU, " "))
		return harness.ErrReported
	}
	for _, keep := range []string{"read", "write", "close", "dup", "ioctl", "select", "tcgetattr", "tcsetattr",
		"nanosleep", "isatty", "printf", "fflush", "stderr", "fputs", "fputc", "fwrite", "putchar", "__errno_location"} {
		if !contains(after, keep) {
			return stop("%s went, and it is not this phase's: read, write, close, dup, ioctl, select, tcgetattr, tcsetattr, nanosleep and isatty are the terminal's, printf, fflush and stderr are the message layer's, and fputs, fputc, fwrite, putchar and __errno_location are gcc's own", keep)
		}
	}
	for _, absent := range []string{"open", "creat", "openat", "stat", "access", "fcntl", "getcwd", "strerror",
		"fopen", "fdopen", "opendir", "chmod", "fchmod", "fstat", "lstat", "unlink", "ftruncate", "fclose", "getc", "putc", "fsync"} {
		if contains(after, absent) {
			return stop("%s is undefined, and after this phase the core can neither open a file nor hold a stdio stream", absent)
		}
	}
	r.say("symbols %s -> %s, and the set is exactly fclose fsync getc putc -- with open, creat, openat, stat, access, fcntl, getcwd, strerror, fopen, fdopen and opendir absent, the core has no open, no stat, no stdio stream and no fourth descriptor: it can read, write, close and dup fds 0, 1 and 2 and nothing else",
		strings.TrimSpace(readFile(".cache/symbols/last/before")),
		strings.TrimSpace(readFile(".cache/symbols/last/after")))

	// --- 4. the enumerators --------------------------------------------------
	evOld, evNew := filepath.Join(tmp, "ev.old"), filepath.Join(tmp, "ev.new")
	var ewg sync.WaitGroup
	ewg.Add(1)
	go func() { defer ewg.Done(); exec.Command("sh", "tools/enumvals.sh", filepath.Join(state, "old.c"), evOld).Run() }()
	exec.Command("sh", "tools/enumvals.sh", f, evNew).Run()
	ewg.Wait()
	if err := z13Enums(r, readFile(evOld), readFile(evNew)); err != nil {
		return err
	}

	// --- 5. the binary -------------------------------------------------------
	_ = exec.Command("make", "-C", work, "clean").Run()
	if err := exec.Command("make", "-C", work).Run(); err != nil {
		(&rep{tag: "build", w: w}).say("FAILED -- rerun by hand: make -C %s", work)
		return harness.ErrReported
	}
	bin, _ := filepath.Abs(filepath.Join(work, "zero-vim"))
	old, _ := filepath.Abs(filepath.Join(state, "old"))
	now, _ := os.ReadFile(f)
	(&rep{tag: "build", w: w}).say("ok, %s -> %d lines, %d bytes", beforeLines, countLines(now), sizeOf(bin))

	bwg.Wait()
	if buildErr["probe"] != nil {
		return stop("the five-site probe did not build")
	}
	if buildErr["ctl"] != nil {
		return stop("the ui_write() control did not build")
	}
	return z13Evidence(r, tmp, inst, old, bin)
}

// calledBare is `(?<![\w.>])name\s*\(`: a call of name that is not a member
// access and not the tail of a longer identifier.
func calledBare(text, name string) bool {
	re := regexp.MustCompile(`\b` + regexp.QuoteMeta(name) + `\s*\(`)
	for _, m := range re.FindAllStringIndex(text, -1) {
		if m[0] > 0 {
			c := text[m[0]-1]
			if c == '.' || c == '>' || c == '_' || (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') {
				continue
			}
		}
		return true
	}
	return false
}

func z13Enums(r *rep, oldTxt, newTxt string) error {
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
	if strings.Join(gone, " ") != "NSCRIPT" || len(came) > 0 || len(moved) > 0 {
		if strings.Join(gone, " ") != "NSCRIPT" {
			g := strings.Join(gone, " ")
			if g == "" {
				g = "none"
			}
			r.say("the enumerators that went are %s, expected exactly NSCRIPT", g)
		}
		if len(came) > 0 {
			r.say("enumerators arrived: %s", strings.Join(came, " "))
		}
		if len(moved) > 0 {
			r.say("survivors renumbered: %s", strings.Join(moved, " "))
		}
		return harness.ErrReported
	}
	r.say("enumerators %d -> %d: NSCRIPT alone, as a whole anonymous definition, and not one survivor renumbered", len(o), len(n))
	return nil
}
