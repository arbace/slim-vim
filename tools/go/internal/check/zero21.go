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
	"strings"
	"sync"
	"syscall"

	"slimvim.local/tools/internal/harness"
)

func init() { register("zero21", Zero21) }

var z21PrintfStmt = regexp.MustCompile(`^\s*(printf|fprintf)\(`)

// z21BareWrite is `(?<![_A-Za-z])write\(` on one line, which RE2 cannot say.
func z21BareWrite(l string) bool {
	for i := 0; ; {
		k := strings.Index(l[i:], "write(")
		if k < 0 {
			return false
		}
		k += i
		if k == 0 {
			return true
		}
		c := l[k-1]
		if !(c == '_' || c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z') {
			return true
		}
		i = k + 1
	}
}

// Zero21 is phase 21's check: the messages are the editor's, the writing is
// the host's.
func Zero21(w io.Writer, args []string) error {
	if len(args) < 2 {
		return fmt.Errorf("usage: check zero21 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	r := &rep{tag: "message", w: w}
	f := filepath.Join(work, "zero-vim.c")
	beforeLines := strings.TrimSpace(readFile(filepath.Join(state, "input-lines")))
	tmp, err := os.MkdirTemp("", "zero21")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	mk := readFile(filepath.Join(work, "Makefile"))
	cflags, ldflags := strings.Fields(z9Flag(mk, "CFLAGS")), strings.Fields(z9Flag(mk, "LDFLAGS"))
	newC, oldC := readFile(f), readFile(filepath.Join(state, "old.c"))
	stop := func(format string, a ...any) error { r.say(format, a...); return harness.ErrReported }

	// --- 1. the three extra sources ------------------------------------------
	A := "        int w = (int)write(err ? 2 : 1, msg + off, (size_t)(n - off));\n"
	if strings.Count(newC, A) != 1 {
		return stop("host_message()'s one write() is not in the output exactly once, so the control below would not be the control")
	}
	os.WriteFile(filepath.Join(tmp, "ctl.c"), []byte(strings.ReplaceAll(newC, A, strings.Replace(A, "err ? 2 : 1", "err ? 1 : 1", 1))), 0o644)
	const mark = `     write(2, "MESSAGE-OUT\n", 12) ;`
	var out []string
	n := 0
	for _, l := range strings.Split(oldC, "\n") {
		if z21PrintfStmt.MatchString(l) {
			out = append(out, mark)
			n++
		}
		out = append(out, l)
	}
	if n != 19 {
		return stop("the instrument went on %d statements of the input, expected the 19 that put bytes on a stream (16 fprintf + 3 printf; the fflush emits nothing of its own)", n)
	}
	os.WriteFile(filepath.Join(tmp, "IN.c"), []byte(strings.Join(out, "\n")), 0o644)
	B := "host_message(const char *msg, int len, int err)\n{\n    int         n = len;\n"
	C := B + "\n    write(2, \"MESSAGE-OUT\\n\", 12);\n"
	if strings.Count(newC, B) != 1 {
		return stop("host_message()'s head is not in the output exactly once")
	}
	os.WriteFile(filepath.Join(tmp, "OUT.c"), []byte(strings.ReplaceAll(newC, B, C)), 0o644)
	r.say("the control (`err ? 2 : 1` made `err ? 1 : 1`, one character) and the instrumented pair (the input marked at all %d output statements, the output marked once inside host_message) are written", n)
	builds := map[string]chan error{}
	for _, v := range []string{"ctl", "IN", "OUT"} {
		ch := make(chan error, 1)
		builds[v] = ch
		go func(v string) {
			a := append(append(append([]string{}, cflags...), ldflags...), "-o", filepath.Join(tmp, v), filepath.Join(tmp, v+".c"))
			ch <- exec.Command("gcc", a...).Run()
		}(v)
	}

	// --- 2. the source -------------------------------------------------------
	var fail []string
	mentions := func(t, name string) int {
		return len(regexp.MustCompile(`\b` + name + `\b`).FindAllString(t, -1))
	}
	for _, p := range []struct {
		name string
		want int
	}{{"fprintf", 16}, {"stderr", 17}, {"fflush", 1}, {"printf", 13}, {"errno", 3}, {"info_message", 9}, {"vim_host_exit", 3}} {
		if m := mentions(oldC, p.name); m != p.want {
			fail = append(fail, fmt.Sprintf("the input has %d mentions of `%s`, expected %d", m, p.name, p.want))
		}
	}
	if strings.Count(oldC, "#include <stdio.h>\n") != 1 {
		fail = append(fail, "the input did not include <stdio.h> exactly once")
	}
	for _, name := range []string{"vim_host_message", "host_message"} {
		if mentions(oldC, name) > 0 {
			fail = append(fail, fmt.Sprintf("`%s` was already in the input, so its arrival proves nothing", name))
		}
	}
	for _, name := range []string{"fprintf", "stderr", "fflush", "FILE", "stdout"} {
		if m := mentions(newC, name); m > 0 {
			fail = append(fail, fmt.Sprintf("`%s` has %d mentions and should have none", name, m))
		}
	}
	if regexp.MustCompile(`(?m)^\s*(?:printf|fprintf|fflush)\(`).MatchString(newC) {
		fail = append(fail, "a statement still begins with printf(, fprintf( or fflush(")
	}
	for _, p := range []struct {
		name string
		want int
		why  string
	}{
		{"printf", 10, "THE COUNTING TRAP: nine `format(printf, ...)` attributes and the string \"E767: Too many arguments for printf()\".  None is a call, and `assert printf at 0` fails on a correct phase"},
		{"vim_host_message", 10, "the declaration, vim_main()'s installation and the EIGHT call sites -- 4 in msg_puts_printf, 2 in exit_scroll, 1 in report_term_error, 1 in mainerr"},
		{"host_message", 2, "the launcher's definition and the argument main() passes.  `vim_host_message` is a DIFFERENT word to \\b"},
		{"vim_host_exit", 3, "phase 19's, untouched"},
		{"host_exit", 2, "phase 19's, untouched"},
		{"vim_main", 2, "its definition and the one call from the launcher"},
		{"main", 1, "still the only bare `main` in the file"},
		{"msg_use_printf", 6, "a prototype, a definition and four call sites -- UNTOUCHED.  It returns TRUE in 23 of 106 records, so it is not dead and folding it is a later phase"},
		{"msg_puts_printf", 3, "a prototype, a definition and one call -- all 75 lines stay and only what they call changes"},
		{"info_message", 9, "untouched: the four sites that read it kept their `if (info_message)` shape, so this phase changes which primitive writes and nothing about which stream"},
		{"errno", 3, "UNCHANGED, and said out loud: the #include and two uses, both inside phase 20's host block.  __errno_location is NOT this phase's and is required below to be still undefined"},
		{"vim_snprintf", 73, "four more than the input -- report_term_error and mainerr each assemble in two arms, with the only formatter the file has had since phase 14"},
		{"musl_strlen", 134, "one more than the input: host_message's, in the len < 0 arm.  The launcher may call it -- it is the same translation unit and it goes to the host file at the split"},
	} {
		if m := mentions(newC, p.name); m != p.want {
			fail = append(fail, fmt.Sprintf("`%s` has %d mentions, expected %d -- %s", p.name, m, p.want, p.why))
		}
	}
	type wl struct {
		n int
		l string
	}
	var ws []wl
	L := strings.Split(newC, "\n")
	for i, l := range L {
		if z21BareWrite(l) {
			ws = append(ws, wl{i + 1, strings.TrimSpace(l)})
		}
	}
	wj := func(x []wl, max int) string {
		var s []string
		for i, v := range x {
			if max >= 0 && i >= max {
				break
			}
			s = append(s, fmt.Sprintf("%d: %s", v.n, v.l))
		}
		return strings.Join(s, "; ")
	}
	if len(ws) != 2 {
		fail = append(fail, fmt.Sprintf("there are %d bare write() call sites, expected 2 -- mch_write's write(1, ...) and host_message's write(err ? 2 : 1, ...): %s", len(ws), wj(ws, 6)))
	} else if !strings.Contains(ws[0].l, "write(1, (char *)s, len)") || !strings.Contains(ws[1].l, "err ? 2 : 1") {
		fail = append(fail, "the two write() call sites are not mch_write's and host_message's: "+wj(ws, -1))
	}
	if mentions(oldC, "write")-mentions(newC, "write") != -1 {
		fail = append(fail, fmt.Sprintf("`write` moved by %d mentions, expected exactly +1 -- host_message's", mentions(newC, "write")-mentions(oldC, "write")))
	}
	rows := z6RowRe.FindAllString(newC, -1)
	got, _ := harness.CommandNamesIn([]byte(newC), "zero-vim.c")
	if len(rows) != 98 || len(got) != 98 {
		fail = append(fail, "cmdnames[] is not the 98 rows phase 10 left -- this phase touches no Ex command")
	}
	if i := strings.Index(newC, "static struct vimoption options[]"); i >= 0 {
		j := strings.Index(newC[i:], "\n};")
		if m := len(z12RowRe.FindAllString(newC[i:i+j], -1)); m != 107 {
			fail = append(fail, fmt.Sprintf("options[] has %d rows, expected the 107 phase 20 left -- this phase touches no option", m))
		}
	}
	dirs := func(t string) (int, bool) {
		c, ok := 0, true
		for _, l := range strings.Split(t, "\n") {
			if strings.HasPrefix(l, "#") {
				c++
				if !strings.HasPrefix(l, "#include <") {
					ok = false
				}
			}
		}
		return c, ok
	}
	dn, dok := dirs(newC)
	do, _ := dirs(oldC)
	if do != 12 || dn != 11 || !dok {
		fail = append(fail, fmt.Sprintf("the directive count is %d -> %d, expected 12 -> 11 with every survivor an #include of a system header.  ZERO-GOAL.md permits a phase to REMOVE one and forbids adding one; this is the second removal in the pipeline, and <stdio.h> is the header these seven symbols came from", do, dn))
	}
	if strings.Contains(newC, "<stdio.h>") {
		fail = append(fail, "<stdio.h> is still named somewhere in the output")
	}
	for k := 1; k < len(L); k++ {
		if L[k] == "" && L[k-1] == "" {
			fail = append(fail, "there is a run of two blank lines, which canon.sh should have taken")
			break
		}
	}
	var before int
	fmt.Sscan(beforeLines, &before)
	if len(L)-1 != before+25 {
		fail = append(fail, fmt.Sprintf("the file is %d lines and the input was %d -- expected exactly 25 more: 2 for the pointer and its blank line, 1 for vim_main's installation, 1 net in report_term_error, 23 for host_message and the blank line above it, less 1 for the fflush and less 1 for <stdio.h>.  The six one-for-one sites and mainerr are line-neutral", len(L)-1, before))
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		return harness.ErrReported
	}
	r.say("fprintf 16 -> 0, stderr 17 -> 0, fflush 1 -> 0, and printf 13 -> 10 -- NOT 0, because nine of the ten survivors are `format(printf, ...)` attributes and the tenth is the E767 string, and none of the three that were calls is left")
	r.cont("exactly TWO bare write() call sites: mch_write's write(1, ...) and host_message's write(err ? 2 : 1, ...).  msg_use_printf 6, msg_puts_printf 3 and info_message 9 are UNTOUCHED, and errno does not move at all (3 -> 3)")
	r.cont("directives 12 -> 11, <stdio.h> gone and named nowhere; cmdnames[] 98 and options[] 107 unchanged; no run of two blank lines")

	// --- 3. phase 20's structural check --------------------------------------
	if err := run(w, "tools/st.sh", "zhostonly", f); err != nil {
		return harness.ErrReported
	}

	// --- 4. the compile, the linkage and the libc surface --------------------
	beforeU := strings.Fields(readFile(filepath.Join(state, "symbols", "undefined")))
	if err := run(w, "sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols")); err != nil {
		return harness.ErrReported
	}
	after := strings.Fields(readFile(".cache/symbols/last/undefined"))
	goneU, cameU := comm23(beforeU, after), comm23(after, beforeU)
	if strings.Join(goneU, " ") != "fflush fputc fputs fwrite printf putchar stderr" || len(cameU) > 0 {
		r.say("the libc surface did not move by exactly those seven:")
		r.cont("gone: %s", trSpace(goneU))
		r.cont("came: %s", trSpace(cameU))
		r.cont("NOTHING MAY ARRIVE, and nothing else may leave.  fputc, fputs,")
		r.cont("fwrite and putchar are gcc's, named nowhere in the source, and")
		r.cont("were PREDICTED to leave with the construct.")
		return harness.ErrReported
	}
	for _, want := range strings.Fields("write read __errno_location ioctl select tcgetattr tcsetattr nanosleep sigaction sigemptyset kill getpid malloc free realloc time gettimeofday") {
		if !contains(after, want) {
			r.say("%s is NOT undefined any more, and this phase does not", want)
			r.cont("claim to free it.  __errno_location in particular is held")
			// The shell's backquotes ran `== EINTR` as a command, which failed
			// and printed nothing: the line reads "by phase 20's two  tests".
			r.cont("by phase 20's two  tests and leaves at the split.")
			return harness.ErrReported
		}
	}
	for _, absent := range strings.Fields("open creat openat stat access fcntl getcwd strerror fopen fdopen opendir fclose getc putc fsync exit _exit close dup isatty") {
		if contains(after, absent) {
			return stop("%s is undefined, and no phase since 13 has put it back", absent)
		}
	}
	r.say("symbols %s -> %s, the gone set is EXACTLY fflush fputc fputs fwrite printf putchar stderr and NOTHING arrives -- four of the seven (fputc fputs fwrite putchar) are gcc's own, named nowhere in the source, predicted to leave with the construct and verified by building",
		strings.TrimSpace(readFile(".cache/symbols/last/before")), strings.TrimSpace(readFile(".cache/symbols/last/after")))
	r.say("write and read are REQUIRED still present -- the core still writes fd 1 through mch_write and the host writes fd 2 through host_message, which is what is left of ZERO-PLAN.md 4c; __errno_location is required present too, and it is phase 20's")

	// --- 5. the binary -------------------------------------------------------
	b := &rep{tag: "build", w: w}
	_ = exec.Command("make", "-C", work, "clean").Run()
	if _, err := os.Stat(filepath.Join(work, "zero-vim")); err == nil {
		b.say("the clean did not remove zero-vim")
		return harness.ErrReported
	}
	if err := exec.Command("make", "-C", work).Run(); err != nil {
		b.say("FAILED -- rerun by hand: make -C %s", work)
		return harness.ErrReported
	}
	bin, _ := filepath.Abs(filepath.Join(work, "zero-vim"))
	old, _ := filepath.Abs(filepath.Join(state, "old"))
	b.say("ok, %s -> %d lines, %d bytes", beforeLines, countLines([]byte(readFile(f))), sizeOf(bin))
	for _, v := range []string{"ctl", "IN", "OUT"} {
		if err := <-builds[v]; err != nil {
			return stop("one of the control or instrumented builds failed")
		}
	}

	// --- 6. five recordings, all at once -------------------------------------
	recs := [][3]string{{"old", old, filepath.Join(state, "old.c")}, {"new", bin, f},
		{"ctl", filepath.Join(tmp, "ctl"), filepath.Join(tmp, "ctl.c")},
		{"IN", filepath.Join(tmp, "IN"), filepath.Join(tmp, "IN.c")},
		{"OUT", filepath.Join(tmp, "OUT"), filepath.Join(tmp, "OUT.c")}}
	errs := make([]error, len(recs))
	var wg sync.WaitGroup
	for i, v := range recs {
		wg.Add(1)
		go func(i int, v [3]string) {
			defer wg.Done()
			errs[i] = exec.Command("sh", "tools/zrecord.sh", v[1], v[2], filepath.Join(tmp, "REC-"+v[0])).Run()
		}(i, v)
	}
	wg.Wait()
	for _, e := range errs {
		if e != nil {
			return stop("a recording failed")
		}
	}

	// --- 7. the probes -------------------------------------------------------
	if err := z21Probes(r, old, bin, tmp); err != nil {
		return err
	}

	// --- 8. the second opinion, on the control -------------------------------
	zd, zerr := exec.Command("sh", "tools/zerodelta.sh", filepath.Join(tmp, "ctl"), filepath.Join(tmp, "ctl.c"), "--phase", "21").CombinedOutput()
	tail5 := func() {
		ls := strings.Split(string(zd), "\n")
		if len(ls) > 0 && ls[len(ls)-1] == "" {
			ls = ls[:len(ls)-1]
		}
		if len(ls) > 5 {
			ls = ls[len(ls)-5:]
		}
		for _, l := range ls {
			fmt.Fprintln(w, l)
		}
	}
	if zerr == nil {
		r.say("tools/zerodelta.sh ACCEPTED the control, which sends every")
		r.cont("message to stdout instead of stderr.  It must refuse.")
		tail5()
		return harness.ErrReported
	}
	named := 0
	const phrase = "ref-argv.txt moved and was not declared: "
	for _, l := range strings.Split(string(zd), "\n") {
		if k := strings.Index(l, phrase); k >= 0 {
			for _, tok := range strings.Split(l[k+len(phrase):], " ") {
				if strings.Contains(tok, "argv:") {
					named++
				}
			}
		}
	}
	if named < 1 {
		r.say("tools/zerodelta.sh refused the control for some other reason:")
		tail5()
		return harness.ErrReported
	}
	r.say("the second opinion: tools/zerodelta.sh REFUSES the control and names %d argv rows, against the 24 records diff -r sees.  That gap is exactly why diff -r is the first check and this is the second: ten of the 24 are rows phases 4 and 5 already declared, and tools/zcompare.py no longer compares them", named)
	return nil
}

func z21Env(tmp string) []string {
	var env []string
	for _, kv := range os.Environ() {
		k := kv[:strings.IndexByte(kv, '=')]
		switch k {
		case "LINES", "COLUMNS", "VIMINIT", "EXINIT", "MYVIMRC", "TERM", "HOME", "VIM", "VIMRUNTIME", "XDG_CONFIG_HOME":
			continue
		}
		env = append(env, kv)
	}
	return append(env, "TERM=xterm", "HOME="+tmp+"/h", "VIM="+tmp+"/h/nv",
		"VIMRUNTIME="+tmp+"/h/nv", "XDG_CONFIG_HOME="+tmp+"/h/xdg")
}

// z21Seq runs the editor with fd 2 a SOCK_SEQPACKET socket, which keeps one
// message per write(): (number of writes, the bytes).
func z21Seq(binary, tmp string, args []string) (int, []byte) {
	vim, err := harness.Stage(binary)
	if err != nil {
		return -1, nil
	}
	fds, err := syscall.Socketpair(syscall.AF_UNIX, syscall.SOCK_SEQPACKET, 0)
	if err != nil {
		return -1, nil
	}
	a, bf := fds[0], os.NewFile(uintptr(fds[1]), "seq")
	dn, _ := os.OpenFile(os.DevNull, os.O_RDWR, 0)
	c := exec.Command(vim, args...)
	c.Env = z21Env(tmp)
	c.Stdin, c.Stdout, c.Stderr = dn, dn, bf
	e := c.Start()
	bf.Close()
	dn.Close()
	if e == nil {
		c.Wait()
	}
	var msgs [][]byte
	buf := make([]byte, 65536)
	for {
		n, _, err := syscall.Recvfrom(a, buf, syscall.MSG_DONTWAIT)
		if err != nil || n <= 0 {
			break
		}
		msgs = append(msgs, append([]byte{}, buf[:n]...))
	}
	syscall.Close(a)
	return len(msgs), bytes.Join(msgs, nil)
}

func z21Stderr(binary, tmp string, args []string) []byte {
	vim, err := harness.Stage(binary)
	if err != nil {
		return nil
	}
	c := exec.Command(vim, args...)
	c.Env = z21Env(tmp)
	var so, se bytes.Buffer
	c.Stdout, c.Stderr = &so, &se
	c.Run()
	return se.Bytes()
}

var z21Compiled = regexp.MustCompile(`compiled [^)]*`)

func z21Scrub(b []byte) []byte { return z21Compiled.ReplaceAll(b, []byte("<compiled>")) }

type z21Marks struct {
	hit   []string
	total int
}

func z21Marked(d string) map[string]z21Marks {
	const M = "MESSAGE-OUT"
	out := map[string]z21Marks{}
	sd := filepath.Join(d, "screen")
	ents, _ := os.ReadDir(sd)
	var names []string
	for _, e := range ents {
		names = append(names, e.Name())
	}
	sort.Strings(names)
	var hit []string
	for _, n := range names {
		if strings.Contains(readFile(filepath.Join(sd, n)), M) {
			hit = append(hit, n)
		}
	}
	out["screen"] = z21Marks{hit, len(names)}
	for _, name := range []string{"ref-argv.txt", "ref-excmds.txt", "ref-pty.txt", "ref-term.txt"} {
		txt := readFile(filepath.Join(d, name))
		// re.split(r'(?m)^(?==== )') -- a cut before every line that begins
		// "=== ", which RE2 cannot say as a lookahead.
		cuts := []int{0}
		for i := 0; ; {
			k := strings.Index(txt[i:], "\n=== ")
			if k < 0 {
				break
			}
			cuts = append(cuts, i+k+1)
			i = i + k + 1
		}
		cuts = append(cuts, len(txt))
		var h []string
		total := 0
		for i := 0; i+1 < len(cuts); i++ {
			blk := txt[cuts[i]:cuts[i+1]]
			if strings.TrimSpace(blk) == "" {
				continue
			}
			total++
			if strings.Contains(blk, M) {
				h = append(h, strings.SplitN(blk, "\n", 2)[0])
			}
		}
		out[name] = z21Marks{h, total}
	}
	return out
}

func z21DiffCount(a, b string) int {
	o, _ := exec.Command("diff", "-r", a, b).Output()
	s := string(o)
	if s == "" {
		return 0
	}
	return len(strings.Split(strings.TrimSuffix(s, "\n"), "\n"))
}

func z21Probes(r *rep, old, bin, tmp string) error {
	g := map[string]any{}
	type seq struct {
		n int
		b []byte
	}
	for _, p := range []struct {
		k, b string
		a    []string
	}{{"seq_Q_old", old, []string{"-Q"}}, {"seq_Q_new", bin, []string{"-Q"}},
		{"seq_T_old", old, []string{"-T", "no-such-term-9x"}}, {"seq_T_new", bin, []string{"-T", "no-such-term-9x"}}} {
		n, b := z21Seq(p.b, tmp, p.a)
		g[p.k] = seq{n, b}
	}
	x9, x2, z2 := "-"+strings.Repeat("x", 900), "-"+strings.Repeat("x", 2000), strings.Repeat("z", 2000)
	jobs := map[string]func() any{
		"long900_old":  func() any { return z21Stderr(old, tmp, []string{x9}) },
		"long900_new":  func() any { return z21Stderr(bin, tmp, []string{x9}) },
		"long2k_old":   func() any { return z21Stderr(old, tmp, []string{x2}) },
		"long2k_new":   func() any { return z21Stderr(bin, tmp, []string{x2}) },
		"termlong_old": func() any { return z21Stderr(old, tmp, []string{"-T", z2}) },
		"termlong_new": func() any { return z21Stderr(bin, tmp, []string{"-T", z2}) },
		"diff_new":     func() any { return z21DiffCount(tmp+"/REC-old", tmp+"/REC-new") },
		"diff_ctl":     func() any { return z21DiffCount(tmp+"/REC-old", tmp+"/REC-ctl") },
		"mark_IN":      func() any { return z21Marked(tmp + "/REC-IN") },
		"mark_OUT":     func() any { return z21Marked(tmp + "/REC-OUT") },
	}
	var mu sync.Mutex
	var wg sync.WaitGroup
	for k, fn := range jobs {
		wg.Add(1)
		go func(k string, fn func() any) {
			defer wg.Done()
			v := fn()
			mu.Lock()
			g[k] = v
			mu.Unlock()
		}(k, fn)
	}
	wg.Wait()
	by := func(k string) []byte { return g[k].([]byte) }
	var fail []string
	dNew, dCtl := g["diff_new"].(int), g["diff_ctl"].(int)
	if dNew != 0 {
		fail = append(fail, fmt.Sprintf("THE RECORDING MOVED: `diff -r` of the binary this phase was handed and the one it made reports %d lines, and this phase declares NOTHING.  The same bytes must reach the same file descriptors at the same moments; only the syscall underneath them changes", dNew))
	}
	if dCtl == 0 {
		fail = append(fail, "THE CONTROL DID NOT MOVE.  `write(err ? 2 : 1, ...)` made `write(err ? 1 : 1, ...)` sends every message to stdout instead of stderr, which must move all 24 message-bearing records.  A check that cannot fail is not evidence")
	}
	for _, p := range []struct {
		tag, args          string
		nold, nnew, nbytes int
	}{{"Q", "-Q", 6, 1, 96}, {"T", "-T no-such-term-9x", 5, 1, 54}} {
		o, n := g["seq_"+p.tag+"_old"].(seq), g["seq_"+p.tag+"_new"].(seq)
		if o.n != p.nold || n.n != p.nnew {
			fail = append(fail, fmt.Sprintf("seq_%s (`%s`): %d write()s on the input and %d here, expected %d and %d", p.tag, p.args, o.n, n.n, p.nold, p.nnew))
		}
		if len(o.b) != p.nbytes || len(n.b) != p.nbytes {
			fail = append(fail, fmt.Sprintf("seq_%s: %d bytes on the input and %d here, expected %d on both -- the SYSCALLS collapse and the BYTES do not", p.tag, len(o.b), len(n.b), p.nbytes))
		}
		if !bytes.Equal(z21Scrub(o.b), z21Scrub(n.b)) {
			fail = append(fail, fmt.Sprintf("seq_%s: the byte stream on fd 2 differs.  old=%q new=%q", p.tag, o.b, n.b))
		}
	}
	if !bytes.Equal(z21Scrub(by("long900_old")), z21Scrub(by("long900_new"))) || len(by("long900_old")) != 995 {
		fail = append(fail, fmt.Sprintf("an unknown option of 900 characters is not the same 995 bytes on both binaries (%d and %d) -- the 1024-byte assembly buffer is biting earlier than measured, or the message moved", len(by("long900_old")), len(by("long900_new"))))
	}
	if len(by("long2k_old")) != 2095 || len(by("long2k_new")) != 1023 {
		fail = append(fail, fmt.Sprintf("an unknown option of 2,000 characters gives %d bytes on the input and %d here, expected 2,095 and exactly 1,023 -- the cap this phase introduces is stated, not discovered, and a cap that drifted either way is a different phase", len(by("long2k_old")), len(by("long2k_new"))))
	}
	if len(by("termlong_old")) != 2039 || len(by("termlong_new")) != 1023 {
		fail = append(fail, fmt.Sprintf("a -T of 2,000 characters gives %d bytes on the input and %d here, expected 2,039 and exactly 1,023 -- the same cap reached by the other speaker, which has no version banner in front of it", len(by("termlong_old")), len(by("termlong_new"))))
	}
	a, b := g["mark_IN"].(map[string]z21Marks), g["mark_OUT"].(map[string]z21Marks)
	for _, k := range []string{"screen", "ref-argv.txt", "ref-excmds.txt", "ref-pty.txt", "ref-term.txt"} {
		if strings.Join(a[k].hit, "\x00") != strings.Join(b[k].hit, "\x00") {
			fail = append(fail, fmt.Sprintf("the instrumented pair disagrees on %s: the input marks %d record(s) and the output %d.  Same places, same times, different primitive -- and that is the whole evidence that an empty declaration is empty for the right reason", k, len(a[k].hit), len(b[k].hit)))
		}
	}
	for _, k := range []string{"screen", "ref-excmds.txt", "ref-pty.txt", "ref-term.txt"} {
		if len(a[k].hit) > 0 {
			fail = append(fail, fmt.Sprintf("%s carries the marker in %d record(s) and should carry it in none: nothing in the corpus but a command line ever makes this editor write to a stream", k, len(a[k].hit)))
		}
	}
	av := a["ref-argv.txt"]
	if len(av.hit) != 24 || av.total != 30 {
		fail = append(fail, fmt.Sprintf("the instrument marks %d of the %d argv rows, expected 24 of 30 -- 23 mainerr and one report_term_error, which is also what says the other four speakers (msg_puts_printf x4, exit_scroll x2) fire in ZERO of 106 records", len(av.hit), av.total))
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		return harness.ErrReported
	}
	sq := func(k string) seq { return g[k].(seq) }
	r.say("MUST NOT DIFFER: the whole recording, `diff -r`, %d lines -- 102 screen cases, ref-excmds.txt, ref-argv.txt, ref-pty.txt and ref-term.txt.  THAT is the check and not tools/zerodelta.sh, which accepts further movement in the ten argv rows phases 4 and 5 already declared", dNew)
	r.cont("MUST DIFFER, the control: this phase's own output with `err ? 2 : 1` made `err ? 1 : 1`, one character, moves %d lines of `diff -r`.  The table can fail", dCtl)
	r.cont("MUST DIFFER, the write boundaries, with a SOCK_SEQPACKET fd 2: `-Q` is %d writes of %d bytes on the input and %d of %d here; `-T no-such-term-9x` is %d of %d and %d of %d.  The same bytes, one syscall -- and the latent hazard goes with them, stdout's buffered printf arm arriving after everything the editor drew",
		sq("seq_Q_old").n, len(sq("seq_Q_old").b), sq("seq_Q_new").n, len(sq("seq_Q_new").b),
		sq("seq_T_old").n, len(sq("seq_T_old").b), sq("seq_T_new").n, len(sq("seq_T_new").b))
	r.cont("THE INSTRUMENTED PAIR, phase 9's shape: the input built with write(2, \"MESSAGE-OUT\\n\", 12) at all 19 output statements and the output with the IDENTICAL instrument inside host_message() mark exactly the same %d of the 30 argv rows, by name, and 0 of 102 screens, 0 excmds, 0 pty, 0 term.  The 24 are 23 mainerr and one report_term_error, so msg_puts_printf and exit_scroll's printf arm fire in ZERO of 106 records and are nonetheless kept", len(av.hit))
	r.cont("THE BOUND, stated rather than discovered: an unknown option of 900 characters is the same %d bytes on both binaries and one of 2,000 is %d bytes on the input and exactly %d here; a -T of 2,000 is %d against %d -- the same cap, reached by the other speaker.  1024 is IOSIZE and is what every other message in this editor is built in",
		len(by("long900_old")), len(by("long2k_old")), len(by("long2k_new")), len(by("termlong_old")), len(by("termlong_new")))
	return nil
}
