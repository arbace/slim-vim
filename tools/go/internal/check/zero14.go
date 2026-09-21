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

func init() { register("zero14", Zero14) }

var z14Seventeen = []string{"memmove", "strlen", "memset", "strncmp", "strcmp", "strcpy", "sprintf",
	"memcpy", "strncasecmp", "strcat", "strcasecmp", "strncpy", "strstr",
	"strchr", "memcmp", "memchr", "strpbrk"}

var z14Input = map[string]int{"memmove": 159, "strlen": 127, "memset": 79, "strncmp": 82, "strcmp": 62,
	"strcpy": 51, "sprintf": 22, "memcpy": 7, "strncasecmp": 13, "strcat": 6,
	"strcasecmp": 6, "strncpy": 4, "strstr": 3, "strchr": 2, "memcmp": 2,
	"memchr": 1, "strpbrk": 2, "vim_snprintf": 55, "tolower": 2}

var z14After = map[string]int{"musl_memmove": 160, "musl_strlen": 133, "musl_memset": 80,
	"musl_strncmp": 83, "musl_strcmp": 63, "musl_strcpy": 53, "musl_memcpy": 8,
	"musl_strncasecmp": 14, "musl_strcat": 7, "musl_strcasecmp": 7,
	"musl_strncpy": 5, "musl_strstr": 4, "musl_strchr": 3, "musl_memcmp": 3,
	"musl_memchr": 2, "musl_strpbrk": 3,
	"musl_fmtnum": 9, "musl_fmtptr": 2, "musl_fmtbase": 5,
	"vim_snprintf": 68, "vim_vsnprintf_typval": 4, "f_l": 0, "tolower": 2,
	"highlight_arg_to_string": 2, "highlight_list_arg": 11, "MAX_ATTR_LEN": 3}

// z14Sized are the twelve sites whose vim_snprintf must carry the size its
// destination really has -- a sprintf becoming a snprintf with the WRONG bound
// compiles, runs and truncates somewhere nobody looks.
var z14Sized = []struct{ what, needle string }{
	{"update_wincolor", `vim_snprintf((char *)str, sizeof("!(:") +  musl_strlen((char *)(opt)) ,`},
	{"show_one_mark", `vim_snprintf((char *)IObuff,  (1024+1) , " %c %6ld %4d ",`},
	{"ex_changes", `vim_snprintf((char *)IObuff,  (1024+1) , "%c %3d %5ld %4d ",`},
	{"do_ascii", `vim_snprintf((char *)IObuff + rlen, (size_t)( (1024+1)  - rlen), "%02x ",`},
	{"get_emsg_source", `vim_snprintf((char *)Buf,  musl_strlen((char *)(sname))  +  musl_strlen((char *)(p)) ,`},
	{"get_emsg_lnum", `vim_snprintf((char *)Buf,  musl_strlen((char *)(p))  + 20,`},
	{"option_value2string", `vim_snprintf((char *)NameBuff, PATH_MAX, "%ld",`},
	{"deadly_signal", `vim_snprintf((char *)IObuff,  (1024+1) , "Vim: Caught deadly signal`},
	{"recording_mode", `vim_snprintf(s, sizeof(s), " @%c", reg_recording);`},
	{"set_color_count", `vim_snprintf((char *)nr_colors, sizeof(nr_colors), "%d", t_colors);`},
	{"term_font", `vim_snprintf(buf, sizeof(buf), (char *) ( term_strings[(int)(KS_CF)] ) , 9 + n);`},
	{"term_color", `vim_snprintf(buf, sizeof(buf), format, lead, tail);`},
}

var z14Keep = []string{"read", "write", "close", "dup", "ioctl", "select", "tcgetattr", "tcsetattr",
	"nanosleep", "isatty", "printf", "fflush", "stderr", "fputs", "fputc", "fwrite", "putchar",
	"__errno_location", "malloc", "free", "realloc", "tolower", "toupper", "towlower", "towupper",
	"qsort", "bsearch"}

var z14Absent = []string{"open", "creat", "openat", "stat", "access", "fcntl", "getcwd", "strerror",
	"fopen", "fdopen", "opendir", "chmod", "fchmod", "fstat", "lstat", "unlink", "ftruncate",
	"fclose", "getc", "putc", "fsync"}

var z14CallRe = regexp.MustCompile(`call[[:space:]]+(memcpy|memset|memmove|strlen|sprintf|strcpy|strcat|strcmp|strncmp|strchr|strstr|memchr|memcmp|strncpy|strcasecmp|strncasecmp|strpbrk)\b`)

// Zero14 is phase 14's check: the libc that is pure computation, defined in
// the file as `static musl_*`.
func Zero14(w io.Writer, args []string) error {
	if len(args) < 2 {
		return fmt.Errorf("usage: check zero14 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	r := &rep{tag: "strings", w: w}
	f := filepath.Join(work, "zero-vim.c")
	beforeLines := strings.TrimSpace(readFile(filepath.Join(state, "input-lines")))
	src, err := os.ReadFile(f)
	if err != nil {
		return err
	}
	newT, oldT := string(src), readFile(filepath.Join(state, "old.c"))
	stop := func(format string, a ...any) error { r.say(format, a...); return harness.ErrReported }
	tmp, err := os.MkdirTemp("", "zero14")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)

	// --- 1. the source, as counts --------------------------------------------
	// OCCURRENCES: `grep -c` counts LINES and disagrees with eight of the
	// seventeen -- strncasecmp is 13 occurrences on 7 lines.
	var fail []string
	count := func(t, name string) int {
		return len(regexp.MustCompile(`\b` + regexp.QuoteMeta(name) + `\b`).FindAllString(t, -1))
	}
	sortedKeys := func(m map[string]int) []string {
		k := make([]string, 0, len(m))
		for x := range m {
			k = append(k, x)
		}
		sort.Strings(k)
		return k
	}
	for _, name := range sortedKeys(z14Input) {
		if count(oldT, name) != z14Input[name] {
			fail = append(fail, fmt.Sprintf("the input is not the file this phase was written against: %s %d, expected %d", name, count(oldT, name), z14Input[name]))
		}
	}
	// `(?<!_)\b` in the Python is `\b` alone: `_` is a word character, so a
	// word boundary already refuses a match inside musl_memmove.
	for _, name := range z14Seventeen {
		if k := count(newT, name); k > 0 {
			fail = append(fail, fmt.Sprintf("%s survives as a bare libc name %d times", name, k))
		}
	}
	for _, name := range sortedKeys(z14After) {
		if k := count(newT, name); k != z14After[name] {
			fail = append(fail, fmt.Sprintf("%s has %d mentions, expected %d", name, k, z14After[name]))
		}
	}
	if !regexp.MustCompile(`(?m)^highlight_arg_to_string\(int .*char_u      \*buf\)$`).MatchString(newT) {
		fail = append(fail, "highlight_arg_to_string is not defined with a char_u *buf parameter")
	}
	if strings.Count(newT, "    ts = highlight_arg_to_string(type, iarg, sarg, buf);\n") != 1 {
		fail = append(fail, "highlight_arg_to_string is not called exactly once from highlight_list_arg, and MAX_ATTR_LEN is only its size while that is true -- a second caller with a smaller buffer would make the bound wrong and nothing else here would see it")
	}
	if strings.Count(newT, "    char_u      buf[MAX_ATTR_LEN];\n") != 1 {
		fail = append(fail, "highlight_list_arg's `char_u buf[MAX_ATTR_LEN];` is gone, and it is where site 25443's bound comes from")
	}
	if !strings.Contains(newT, `vim_snprintf((char *)buf, MAX_ATTR_LEN, "%d", iarg - 1);`) {
		fail = append(fail, "site 25443 does not use MAX_ATTR_LEN as its bound")
	}
	for _, s := range z14Sized {
		if strings.Count(newT, s.needle) != 1 {
			fail = append(fail, fmt.Sprintf("%s does not call vim_snprintf with the size its destination really has", s.what))
		}
	}
	for _, fn := range []string{"musl_strcasecmp", "musl_strncasecmp"} {
		body := ""
		if a, z, ok := cutil.FindDefinition(src, cutil.Blank(src), fn); ok {
			body = newT[a:z]
		}
		if strings.Count(body, "(unsigned)*l - 'A' < 26 ? *l | 32 : *l") != 2 || strings.Count(body, "(unsigned)*r - 'A' < 26 ? *r | 32 : *r") != 2 {
			fail = append(fail, fmt.Sprintf("%s does not inline the C-locale tolower -- musl tolower.c is `if (isupper(c)) return c | 32; return c;` and isupper.c is `(unsigned)c-'A' < 26`, and the cast is what keeps a byte over 127 out of the range test", fn))
		}
	}
	var directives []string
	for _, l := range strings.Split(newT, "\n") {
		if strings.HasPrefix(l, "#") {
			directives = append(directives, l)
		}
	}
	allInclude := true
	for _, l := range directives {
		if !strings.HasPrefix(l, "#include <") {
			allInclude = false
		}
	}
	if len(directives) != 18 || !allInclude {
		fail = append(fail, fmt.Sprintf("the file has %d lines starting with #, and ZERO-GOAL.md says eighteen #includes and nothing else", len(directives)))
	}
	for _, p := range []struct{ tok, name string }{{"/*", "a block comment"}, {"\t", "a tab"}} {
		if strings.Count(newT, p.tok) != strings.Count(oldT, p.tok) {
			fail = append(fail, fmt.Sprintf("%s count moved %d -> %d, and this phase writes 301 lines of C with neither", p.name, strings.Count(oldT, p.tok), strings.Count(newT, p.tok)))
		}
	}
	if strings.Count(newT, "//") != strings.Count(oldT, "//") {
		fail = append(fail, fmt.Sprintf("`//` count moved %d -> %d", strings.Count(oldT, "//"), strings.Count(newT, "//")))
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
	for _, flag := range []string{"P_NFNAME", "P_NDNAME"} {
		if count(newT, flag) != 2 {
			fail = append(fail, fmt.Sprintf("%s has %d mentions, expected 2 -- its own enum and the one test in musl_strpbrk's only caller.  If an options[] row ever carries it, musl_strpbrk stops being unreachable and this phase's claim about it has to be re-measured", flag, count(newT, flag)))
		}
	}
	if len(regexp.MustCompile(`%\.\*s`).FindAllString(newT, -1)) != 1 {
		fail = append(fail, "there is no longer exactly one `%.*s` in the file, and it was the only thing that could reach musl_memchr")
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		return harness.ErrReported
	}
	r.say("the seventeen bare names at 0 and the sixteen musl_* at their source counts; sprintf and f_l at 0 and vim_snprintf 55 -> 68; tolower STILL AT 2, the case fold being musl's C-locale tolower inlined, so the character-class phase counts what it counted before")
	r.cont("highlight_arg_to_string has ONE caller and MAX_ATTR_LEN is its bound only while that holds -- pinned at two mentions, the definition and the call")
	r.cont("eighteen #include lines and no other directive, no comment and no tab added; cmdnames[] 98 rows, options[] 108, both untouched")

	// --- 2. the compile, the linkage and the libc surface --------------------
	before := strings.Fields(readFile(filepath.Join(state, "symbols", "undefined")))
	if err := run(w, "sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols")); err != nil {
		return harness.ErrReported
	}
	after := strings.Fields(readFile(".cache/symbols/last/undefined"))
	goneU, cameU := comm23(before, after), comm23(after, before)
	want := append([]string{}, z14Seventeen...)
	sort.Strings(want)
	if strings.Join(goneU, "\n") != strings.Join(want, "\n") || len(cameU) > 0 {
		r.say("the libc surface did not move by exactly the seventeen string and memory symbols:")
		r.cont("  gone: %s ", strings.Join(goneU, " "))
		r.cont("  came: %s ", strings.Join(cameU, " "))
		return harness.ErrReported
	}
	// gcc may emit a call to one of the seventeen that no source line writes: an
	// aggregate assignment or a large zero initialiser over -O0's threshold.
	asm := filepath.Join(tmp, "z.s")
	if err := exec.Command("gcc", "-S", "-O0", "-fno-stack-protector", "-o", asm, f).Run(); err != nil {
		return fmt.Errorf("gcc -S refused")
	}
	if calls := z14CallRe.FindAllStringSubmatch(readFile(asm), -1); len(calls) > 0 {
		r.say("gcc emitted a call to one of the seventeen that no source line writes:")
		counts := map[string]int{}
		var order []string
		for _, c := range calls {
			key := c[0]
			if counts[key] == 0 {
				order = append(order, key)
			}
			counts[key]++
		}
		sort.Strings(order)
		for _, k := range order {
			r.cont("  %7d %s", counts[k], k)
		}
		r.cont("That is an aggregate assignment or a large zero initialiser")
		r.cont("over gcc's -O0 threshold, which is between 8 KiB and 16 KiB.")
		return harness.ErrReported
	}
	for _, keep := range z14Keep {
		if !contains(after, keep) {
			return stop("%s went, and it is not this phase's: this phase is string and memory work and takes nothing else", keep)
		}
	}
	for _, absent := range z14Absent {
		if contains(after, absent) {
			return stop("%s is undefined, and the core has neither a way to open a file nor a stdio stream since phase 13", absent)
		}
	}
	r.say("symbols %s -> %s, and the set is exactly the seventeen -- with NOT ONE call to any of them left in the assembly, so gcc emits none of them for itself here and nothing had to be defined under a real name",
		strings.TrimSpace(readFile(".cache/symbols/last/before")),
		strings.TrimSpace(readFile(".cache/symbols/last/after")))

	// --- 3. the enumerators, which must not move at all ----------------------
	evOld, evNew := filepath.Join(tmp, "ev.old"), filepath.Join(tmp, "ev.new")
	var ewg sync.WaitGroup
	ewg.Add(1)
	go func() { defer ewg.Done(); exec.Command("sh", "tools/enumvals.sh", filepath.Join(state, "old.c"), evOld).Run() }()
	exec.Command("sh", "tools/enumvals.sh", f, evNew).Run()
	ewg.Wait()
	if err := z14Enums(r, readFile(evOld), readFile(evNew)); err != nil {
		return err
	}

	// --- 4. the binary -------------------------------------------------------
	_ = exec.Command("make", "-C", work, "clean").Run()
	if err := exec.Command("make", "-C", work).Run(); err != nil {
		(&rep{tag: "build", w: w}).say("FAILED -- rerun by hand: make -C %s", work)
		return harness.ErrReported
	}
	bin, _ := filepath.Abs(filepath.Join(work, "zero-vim"))
	old, _ := filepath.Abs(filepath.Join(state, "old"))
	now, _ := os.ReadFile(f)
	(&rep{tag: "build", w: w}).say("ok, %s -> %d lines, %d bytes", beforeLines, countLines(now), sizeOf(bin))

	return z14Probes(r, old, bin)
}

func z14Enums(r *rep, oldTxt, newTxt string) error {
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
			what  string
			names []string
		}{{"went", gone}, {"arrived", came}, {"renumbered", moved}} {
			if len(p.names) > 0 {
				r.say("enumerators %s: %s -- this phase deletes no type, no enum and no table row, so not one may move", p.what, strings.Join(p.names, " "))
			}
		}
		return harness.ErrReported
	}
	r.say("enumerators %d -> %d, not one value moved: this phase adds functions and renames call sites and touches no type, no enum and no table", len(o), len(n))
	return nil
}
