package check

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"

	"slimvim.local/tools/internal/harness"
)

func init() { register("zero41", Zero41) }

var (
	z41Arena   = regexp.MustCompile(`ARENA used=(\d+) calls=(\d+)`)
	z41Exhaust = regexp.MustCompile(`zero-vim: host arena exhausted: (\d+) bytes, (\d+) used, request (\d+)`)
	z41Grows   = regexp.MustCompile(`grows=(\d+)`)
	z41Type    = regexp.MustCompile(`(?m)^ *Type: *([A-Z]*)`)
)

const z41Dump = `static int host_arena_say(char *b, int at, const char *s);
static int host_arena_num(char *b, int at, usize v);
static usize host_arena_used;
static long host_arena_calls;

    static void
host_exit(int r)
{
    {
        char        b[96];
        int         at = 0;

        at = host_arena_say(b, at, "ARENA used=");
        at = host_arena_num(b, at, host_arena_used);
        at = host_arena_say(b, at, " calls=");
        at = host_arena_num(b, at, (usize)host_arena_calls);
        at = host_arena_say(b, at, "\n");
        host_message(b, at, TRUE);
    }
`

const z41Driver = `
main(int argc, char **argv)
{
    if (argc == 2 && argv[1][0] == 'Z')
    {
        char        b[512];
        int         k;
        const char  *fm[7];

        fm[0] = "%1$s";
        fm[1] = "%1$s-%2$s";
        fm[2] = "%1$s/%2$s/%3$s/%1$s";
        fm[3] = "%1$s|%2$s|%3$s|%4$s|%5$s";
        fm[4] = "%1$s.%2$s.%3$s.%4$s.%5$s.%6$s.%7$s.%8$s.%9$s";
        fm[5] = "%2$s-%1$s-%2$s-%3$s-%1$s";
        fm[6] = "%1$d+%2$d=%2$d";
        for (k = 0; k < 6; k++)
        {
            vim_snprintf(b, sizeof(b), fm[k], "a", "bb", "ccc", "dddd", "eeeee",
                         "ffffff", "ggggggg", "hhhhhhhh", "iiiiiiiii");
            host_message(b, -1, 1);
            host_message("\n", 1, 1);
        }
        vim_snprintf(b, sizeof(b), fm[6], 11, 22);
        host_message(b, -1, 1);
        host_message("\n", 1, 1);
        host_message("grows=", 6, 1);
        b[0] = (char)('0' + probe_grow / 10);
        b[1] = (char)('0' + probe_grow % 10);
        b[2] = '\n';
        host_message(b, 3, 1);
        return 0;
    }
`

// z41Bss is `readelf -S | grep -A1 '\.bss' | tail -1 | awk '{print $1}'`
// read as hex: the size, which non-wide readelf prints on the line after
// the section's name.
func z41Bss(bin string) int64 {
	out, _ := exec.Command("readelf", "-S", bin).Output()
	L := strings.Split(strings.TrimRight(string(out), "\n"), "\n")
	last := -1
	for i, l := range L {
		if strings.Contains(l, ".bss") {
			last = i
		}
	}
	if last < 0 {
		return 0
	}
	line := L[last]
	if last+1 < len(L) {
		line = L[last+1]
	}
	fs := strings.Fields(line)
	if len(fs) == 0 {
		return 0
	}
	v, _ := strconv.ParseInt(fs[0], 16, 64)
	return v
}

// Zero41 is phase 41's check: freeing is free.
func Zero41(w io.Writer, args []string) error {
	if len(args) != 2 {
		return fmt.Errorf("usage: check zero41 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	f := filepath.Join(work, "zero-vim.c")
	oldC := filepath.Join(state, "old.c")
	r := &rep{tag: "arena", w: w}
	stop := func(format string, a ...any) error {
		r.say(format, a...)
		return harness.ErrReported
	}
	raw := func(format string, a ...any) { fmt.Fprintf(w, format+"\n", a...) }
	head := func(ls []string, n int, prefix string) {
		for i, l := range ls {
			if i >= n {
				break
			}
			fmt.Fprintf(w, "%s%s\n", prefix, l)
		}
	}
	fileLines := func(p string) []string {
		s := strings.TrimRight(readFile(p), "\n")
		if s == "" {
			return nil
		}
		return strings.Split(s, "\n")
	}
	beforeRaw := strings.TrimRight(readFile(filepath.Join(state, "input-lines")), "\n")
	arenaS := strings.TrimRight(readFile(filepath.Join(state, "arena-bytes")), "\n")
	arena, _ := strconv.ParseInt(strings.TrimSpace(arenaS), 10, 64)
	tmp, err := os.MkdirTemp("", "zero41-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	T := func(n string) string { return filepath.Join(tmp, n) }
	mk := readFile(filepath.Join(work, "Makefile"))
	cflagsS, ldflagsS := "", ""
	if m := z29CFlags.FindStringSubmatch(mk); m != nil {
		cflagsS = m[1]
	}
	if m := z29LDFlags.FindStringSubmatch(mk); m != nil {
		ldflagsS = m[1]
	}
	link := func(src, out, logPath string, extra ...string) error {
		a := append(append(append(strings.Fields(cflagsS), extra...), strings.Fields(ldflagsS)...), "-o", out, src)
		c := exec.Command("gcc", a...)
		c.Env = append(os.Environ(), "SOURCE_DATE_EPOCH=0")
		if logPath != "" {
			lf, _ := os.Create(logPath)
			defer lf.Close()
			c.Stderr = lf
		}
		return c.Run()
	}
	var wgAll sync.WaitGroup
	defer wgAll.Wait()
	type job struct {
		wg  sync.WaitGroup
		err error
	}
	start := func(fn func() error) *job {
		j := &job{}
		j.wg.Add(1)
		wgAll.Add(1)
		go func() { defer wgAll.Done(); defer j.wg.Done(); j.err = fn() }()
		return j
	}
	jNew := start(func() error { return link(f, T("new"), "") })

	// --- 0. every variant this check builds -------------------------------------------
	t := readFile(f)
	oldT := readFile(oldC)
	one := func(text, s, what string) (string, error) {
		if strings.Count(text, s) != 1 {
			return "", stop("`%s` is not in that source exactly once, so a control built "+
				"from it would not be one", what)
		}
		return s, nil
	}
	RET, e := one(t, "    p = (char *)host_arena + host_arena_used;\n", "host_alloc's return")
	if e != nil {
		return e
	}
	BUMP, e := one(t, "    host_arena_used += want;\n", "host_alloc's bump")
	if e != nil {
		return e
	}
	SIZE, e := one(t, "enum { HOST_ARENA_BYTES = 1024 * 1024 * 1024 };\n", "the arena size")
	if e != nil {
		return e
	}
	INCL, e := one(t, "#include <stdlib.h>\n", "<stdlib.h>")
	if e != nil {
		return e
	}
	if arena != 1024*1024*1024 {
		return stop("the edit recorded an arena of %d bytes and the output says 1 GiB", arena)
	}
	ctl := map[string]string{
		"ca":      strings.Replace(strings.Replace(t, RET, "    return nullptr;\n", 1), BUMP, "", 1),
		"cnb":     strings.Replace(t, BUMP, "", 1),
		"ctiny":   strings.Replace(t, SIZE, "enum { HOST_ARENA_BYTES = 256 * 1024 };\n", 1),
		"cstdlib": strings.Replace(t, INCL, "", 1),
	}
	FREEP, e := one(oldT, "    free(p);\n", "the input's host_free body")
	if e != nil {
		return e
	}
	ctl["cf"] = strings.Replace(oldT, FREEP, "    (void)p;\n", 1)
	EXIT, e := one(t, "    static void\nhost_exit(int r)\n{\n", "host_exit()")
	if e != nil {
		return e
	}
	p := strings.Replace(t, EXIT, z41Dump, 1)
	p = strings.Replace(p, "static usize host_arena_used;\n", "static usize host_arena_used;\nstatic long host_arena_calls;\n", 1)
	p = strings.Replace(p, RET, "    host_arena_calls++;\n"+RET, 1)
	ctl["probe"] = p
	const GROWOLD = "            new_types =  realloc(((char **)*ap_types), (arg * sizeof(const char *))) ;\n"
	const GROWNEW = "            new_types = (const char **)host_alloc(arg * sizeof(const char *));\n"
	for _, x := range []struct{ tag, src, grow string }{{"din", oldT, GROWOLD}, {"dout", t, GROWNEW}} {
		h, e := one(x.src, "\nmain(int argc, char **argv)\n{\n", "the launcher's head")
		if e != nil {
			return e
		}
		d := strings.Replace(x.src, h, z41Driver, 1)
		g, e := one(x.src, x.grow, "adjust_types's grow arm")
		if e != nil {
			return e
		}
		d = strings.Replace(d, g, "            probe_grow++;\n"+g, 1)
		a, e := one(x.src, "\n    static int\nadjust_types(", "adjust_types()")
		if e != nil {
			return e
		}
		d = strings.Replace(d, a, "\nstatic int probe_grow;\n\n    static int\nadjust_types(", 1)
		ctl[x.tag] = d
	}
	keys := make([]string, 0, len(ctl))
	for k := range ctl {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, name := range keys {
		if ctl[name] == t && name != "cf" && name != "din" {
			return stop("%s changed nothing", name)
		}
		os.WriteFile(T(name+".c"), []byte(ctl[name]), 0o644)
	}
	r.say("eight variants written: ca host_alloc always nullptr, cnb the offset " +
		"never advances, ctiny a 256 KiB arena, cstdlib the output without <stdlib.h>, cf " +
		"PHASE 35'S OWN control on the INPUT (host_free does nothing), probe the output " +
		"with the arena reported from host_exit, and din/dout the positional-format driver " +
		"built into both")
	jobs := map[string]*job{}
	for _, v := range []string{"ca", "cnb", "ctiny", "cstdlib", "cf", "probe"} {
		v := v
		jobs[v] = start(func() error { return link(T(v+".c"), T(v), T("e."+v)) })
	}
	for _, v := range []string{"din", "dout"} {
		v := v
		jobs[v] = start(func() error { return link(T(v+".c"), T(v), T("e."+v), "-Wno-format") })
	}
	os.WriteFile(T("canon.c"), []byte(t), 0o644)
	var canonLog []byte
	jCanon := start(func() error {
		var e error
		canonLog, e = exec.Command("sh", "tools/canon.sh", T("canon.c")).CombinedOutput()
		return e
	})

	// --- 1. the source, as a partition of the input -------------------------------
	beforeLines, _ := strconv.Atoi(strings.TrimSpace(beforeRaw))
	mentions := func(text, name string) int {
		return len(regexp.MustCompile(`\b` + name + `\b`).FindAllStringIndex(text, -1))
	}
	cut := func(text string) ([]int, string, []string) {
		L := strings.Split(text, "\n")
		var b []int
		for i, l := range L {
			if z35Dir.MatchString(l) {
				b = append(b, i)
			}
		}
		if len(b) == 0 {
			return nil, text, L
		}
		return b, strings.Join(L[:b[0]], "\n"), L
	}
	ob, ocore, _ := cut(oldT)
	nb, ncore, NL := cut(t)
	for _, name := range []string{"malloc", "free", "realloc"} {
		was, now := mentions(oldT, name), mentions(t, name)
		if was < 1 {
			r.bad("the INPUT does not mention `%s` at all, so this phase has not been "+
				"handed the file it was written for", name)
		}
		if now > 0 {
			r.bad("`%s` still has %d mentions in the output", name, now)
		}
	}
	for _, name := range []string{"host_arena", "host_arena_used", "host_arena_say", "host_arena_num",
		"host_arena_exhausted", "HOST_ARENA_BYTES"} {
		if mentions(oldT, name) > 0 {
			r.bad("`%s` was already a name in the input", name)
		}
		if mentions(t, name) == 0 {
			r.bad("`%s` is not in the output at all", name)
		}
		if mentions(ncore, name) > 0 {
			r.bad("`%s` is mentioned ABOVE the boundary, and every line this phase "+
				"writes is below it", name)
		}
	}
	for _, x := range [][2]string{
		{"host_arena_say", "    static int\n"}, {"host_arena_num", "    static int\n"},
		{"host_arena_exhausted", "    static void\n"}, {"host_alloc", "    static void *\n"},
		{"host_free", "    static void\n"},
	} {
		if strings.Count(t, x[1]+x[0]+"(") != 1 {
			r.bad("`%s` is not defined exactly once in the `    static <type>` shape, "+
				"and everything this file defines has internal linkage", x[0])
		}
	}
	if ncore != ocore {
		r.bad("the text above the first `#include` is not byte-identical in and out, " +
			"and this phase is entirely below it")
	}
	sameIdx := len(ob) == len(nb)
	for k := range ob {
		if sameIdx && ob[k] != nb[k] {
			sameIdx = false
		}
	}
	if len(ob) != 11 || len(nb) != 11 || !sameIdx {
		r.bad("the eleven `#include` directives are not on the same eleven lines in " +
			"and out -- this phase adds none, removes none and moves none")
	}
	if !strings.Contains(t, "static max_align_t host_arena[") {
		r.bad("the arena is not an array of `max_align_t`, so its alignment is not the " +
			"strictest any object in this translation unit can ask for")
	}
	if strings.Count(t, "alignof(max_align_t)") != 2 {
		r.bad("the rounding does not use `alignof(max_align_t)` twice -- the mask and " +
			"the addend -- so it is arithmetic about a machine rather than about the " +
			"requirement")
	}
	if hi := strings.Index(t, "    static void *\nhost_alloc("); hi >= 0 {
		body := t[hi:]
		if k := strings.Index(body, "\n}\n"); k >= 0 {
			body = body[:k+3]
		}
		if strings.Contains(body, "nullptr") {
			r.bad("host_alloc() can return a null pointer, and this phase's arena is " +
				"meant to abort rather than let lalloc() report an out-of-memory it " +
				"could carry on from")
		}
	}
	if k := strings.Index(t, "host_arena_exhausted(usize n)"); k >= 0 {
		s := t[k:]
		if len(s) > 800 {
			s = s[:800]
		}
		if !strings.Contains(s, "host_exit") {
			r.bad("host_arena_exhausted() does not reach host_exit(), so exhaustion would " +
				"return into host_alloc and hand out the arena anyway")
		}
	}
	if err := r.done(); err != nil {
		return err
	}
	r.say("THE PARTITION: `malloc` %d mentions in and 0 out, `free` %d and 0, "+
		"`realloc` %d and 0 -- every one of them was below the boundary and in one of the "+
		"four runs of text the edit rewrites, and the output does not name a libc "+
		"allocator anywhere.  Two were the wrappers phase 35 wrote; the other two are the "+
		"sites phase 35 and phase 34 each SAW and left, in the formatter island phase 27 "+
		"moved below the includes -- and they had to move here, because a free() or a "+
		"realloc() of a pointer the arena handed out is undefined from this phase on",
		mentions(oldT, "malloc"), mentions(oldT, "free"), mentions(oldT, "realloc"))
	r.cont("THE ARENA is %d bytes of `max_align_t`, rounded with "+
		"`alignof(max_align_t)` and not with a number, and host_alloc() has no `nullptr` "+
		"in it at all: exhaustion goes to host_arena_exhausted(), which names the arena, "+
		"what is used and the request, and ends the process", arena)
	r.cont("%d -> %d lines, %d more; the core above the boundary is BYTE-IDENTICAL "+
		"and the eleven #includes are on the same eleven lines", beforeLines, len(NL)-1, len(NL)-1-beforeLines)

	// --- 2. THE CUT --------------------------------------------------------------------
	type cutT struct {
		lines, errs, warns int
		names              []string
		log                string
		objOK              bool
	}
	editorcut := func(src, dst string) (cutT, error) {
		lines := z28Cut(readFile(src))
		text := ""
		for _, l := range lines {
			text += l + "\n"
		}
		os.WriteFile(dst, []byte(text), 0o644)
		for _, l := range lines {
			if z30Dir.MatchString(l) {
				return cutT{}, stop("the cut of %s holds a directive, so it found the wrong line", src)
			}
		}
		if len(lines) <= 70000 {
			return cutT{}, stop("the cut of %s is %d lines, and zero.mk's floor is 70,000 -- a cut that found "+
				"line 1 would be empty and every check below would pass on nothing", src, len(lines))
		}
		os.Remove(dst + ".o")
		c := exec.Command("gcc", "-c", "-O0", "-fno-stack-protector", "-o", dst+".o", dst)
		var eb strings.Builder
		c.Stderr = &eb
		c.Run()
		var cu cutT
		cu.lines, cu.log = len(lines), eb.String()
		for _, l := range strings.Split(cu.log, "\n") {
			if strings.Contains(l, "error:") {
				cu.errs++
			}
			if strings.Contains(l, "warning:") {
				cu.warns++
			}
			if m := z35Warn.FindStringSubmatch(l); m != nil {
				cu.names = append(cu.names, m[1])
			}
		}
		sort.Strings(cu.names)
		_, e := os.Stat(dst + ".o")
		cu.objOK = e == nil
		return cu, nil
	}
	co, e := editorcut(oldC, T("cut-old.c"))
	if e != nil {
		return e
	}
	cn, e := editorcut(f, T("cut-new.c"))
	if e != nil {
		return e
	}
	for _, x := range []struct {
		w, path string
		c       cutT
	}{{"old", T("cut-old.c"), co}, {"new", T("cut-new.c"), cn}} {
		if x.c.errs != 0 || !x.c.objOK {
			r.say("the %s cut does not compile: %d errors", x.w, x.c.errs)
			var el []string
			for _, l := range strings.Split(x.c.log, "\n") {
				if strings.Contains(l, "error:") {
					el = append(el, l)
				}
			}
			head(el, 3, "               ")
			return harness.ErrReported
		}
		if x.c.warns != len(x.c.names) {
			r.say("the %s cut has a warning that is not a 'used but never defined':", x.w)
			var wl []string
			for _, l := range strings.Split(x.c.log, "\n") {
				if strings.Contains(l, "warning:") && !strings.Contains(l, "used but never defined") {
					wl = append(wl, l)
				}
			}
			head(wl, 3, "               ")
			return harness.ErrReported
		}
		if out, _ := exec.Command("nm", "--extern-only", "--defined-only", x.path+".o").Output(); len(out) > 0 {
			r.say("the %s cut DEFINES an external symbol, and the core defines none -- main is the host's:", x.w)
			head(strings.Split(strings.TrimRight(string(out), "\n"), "\n"), 3, "               ")
			return harness.ErrReported
		}
	}
	cutBytes, _ := os.ReadFile(T("cut-new.c"))
	fb, _ := os.ReadFile(f)
	if len(fb) < len(cutBytes) || string(fb[:len(cutBytes)]) != string(cutBytes) {
		return stop("the cut is not a byte prefix of zero-vim.c")
	}
	if !z30Same(T("cut-old.c"), T("cut-new.c")) {
		r.say("THE CUT MOVED, and this phase is host-only.  It is below the first")
		raw("               #include from end to end, so `make editor.c` must write the same bytes:")
		out, _ := exec.Command("cmp", T("cut-old.c"), T("cut-new.c")).CombinedOutput()
		head(strings.Split(strings.TrimRight(string(out), "\n"), "\n"), 2, "               ")
		head(z30Diff(T("cut-old.c"), T("cut-new.c")), 6, "               ")
		return harness.ErrReported
	}
	if strings.Join(co.names, "\n") != strings.Join(cn.names, "\n") {
		return stop("the cut's warning set moved, which cannot happen when the cut itself did not")
	}
	r.say("THE CUT IS BYTE-IDENTICAL -- `make editor.c`'s own rule, %d lines and %d bytes either side, a `cmp` and "+
		"not a count.  THAT IS THE WHOLE OF \"this phase touches no core line\", and it subsumes every screen "+
		"case, every Ex command and every pty scenario at once for the part of the file the project is FOR: the "+
		"core that would be transpiled is literally the same text.  Its warning set, the core -> host interface, "+
		"is the same %d names, which follows rather than being a second fact", cn.lines, len(cutBytes), len(cn.names))

	// --- 3. the binary --------------------------------------------------------------------
	jNew.wg.Wait()
	if jNew.err != nil {
		return stop("the output did not build with '%s' '%s'", cflagsS, ldflagsS)
	}
	oldSize, newSize := sizeOf(filepath.Join(state, "old")), sizeOf(T("new"))
	hdr, _ := exec.Command("readelf", "-h", T("new")).Output()
	if m := z41Type.FindSubmatch(hdr); m == nil || string(m[1]) != "EXEC" {
		return stop("readelf -h no longer says EXEC")
	}
	if ph, _ := exec.Command("readelf", "-l", T("new")).Output(); strings.Contains(string(ph), "INTERP") {
		return stop("the image has an INTERP segment")
	}
	if dy, _ := exec.Command("readelf", "-d", T("new")).Output(); strings.Contains(string(dy), "NEEDED") || strings.Contains(string(dy), "Tag") {
		return stop("the image has a dynamic section")
	}
	if rl, _ := exec.Command("readelf", "-r", T("new")).Output(); strings.Contains(string(rl), "R_X86") {
		return stop("the image carries relocations")
	}
	obss, nbss := z41Bss(filepath.Join(state, "old")), z41Bss(T("new"))
	slack := arena / 1024
	if d := nbss - obss; d < arena-slack || d > arena+slack {
		return stop("%s", fmt.Sprintf(".bss grew by %d bytes and the arena is %d -- the arena is not in .bss, which is the only reason it can cost nothing to store", d, arena))
	}
	if newSize >= oldSize {
		r.say("the image is %d bytes and was %d.  That is a measurement and not a requirement, but it is reported "+
			"here because the expected direction is DOWN: .bss is NOBITS, so the arena adds no bytes to the file, "+
			"and musl's allocator is no longer linked in", newSize, oldSize)
	}
	r.say("THE IMAGE: EXEC, no INTERP, no dynamic section, no relocation -- phases 0 and 1's four facts, undisturbed "+
		"by a %d-byte object.  `.bss` goes %d -> %d bytes, a growth of %d, which is the arena LESS %d -- musl's own "+
		"allocator state, `__malloc_context` and five smaller objects, leaving .bss with the three symbols.  AND "+
		"THE FILE SHRINKS, %d -> %d, %d bytes: `.bss` is NOBITS, so the section header records a size and the "+
		"file holds none of it, and what does leave the file is musl's allocator itself",
		arena, obss, nbss, nbss-obss, arena-(nbss-obss), oldSize, newSize, oldSize-newSize)

	// --- 4. linkage and the symbols ----------------------------------------------------------
	os.WriteFile(T("before.u"), []byte(readFile(filepath.Join(state, "symbols", "undefined"))), 0o644)
	pc := exec.Command("sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols"))
	pc.Stdout, pc.Stderr = w, w
	if err := pc.Run(); err != nil {
		return harness.ErrReported
	}
	lastU := ".cache/symbols/last/undefined"
	bu, lu := fileLines(T("before.u")), fileLines(lastU)
	gone, came := z31Words(comm23(bu, lu)), z31Words(comm23(lu, bu))
	if gone != "free malloc realloc " || came != "" {
		g, c := gone, came
		if g == "" {
			g = "nothing"
		}
		if c == "" {
			c = "nothing"
		}
		r.say("THE UNDEFINED SET DID NOT MOVE AS THIS PHASE CLAIMS.")
		raw("               gone: %s, and it must be exactly free malloc realloc", g)
		raw("               came: %s", c)
		return harness.ErrReported
	}
	for _, s := range []string{"malloc", "free", "realloc", "calloc", "reallocarray"} {
		if contains(lu, s) {
			return stop("`%s` is in nm -u, and nothing in this file may ask a host for memory but host_alloc", s)
		}
	}
	r.say("SYMBOLS %s -> %s, and the set moves by EXACTLY free, malloc and realloc, as a comm empty in the other "+
		"direction.  Three symbols leave because their last CALLER left the file, which is the only way one ever "+
		"leaves a single translation unit -- and no allocator name is undefined any more.  main is still the only "+
		"external symbol", strings.TrimRight(readFile(".cache/symbols/last/before"), "\n"),
		strings.TrimRight(readFile(".cache/symbols/last/after"), "\n"))

	// --- 5. THE EVIDENCE: two recordings, and a control that moves all of them -------------
	jobs["ca"].wg.Wait()
	if jobs["ca"].err != nil {
		r.say("the control ca did not build:")
		head(fileLines(T("e.ca")), 5, "               ")
		return harness.ErrReported
	}
	oldBin, _ := filepath.Abs(filepath.Join(state, "old"))
	var wgR sync.WaitGroup
	recErr := make([]error, 3)
	for k, x := range [][3]string{{"old", oldBin, oldC}, {"new", T("new"), f}, {"ca", T("ca"), T("ca.c")}} {
		k, x := k, x
		wgR.Add(1)
		go func() {
			defer wgR.Done()
			recErr[k] = recCmd("sh", "tools/zrecord.sh", x[1], x[2], T("REC-"+x[0]))
		}()
	}
	wgR.Wait()
	if recReport(w, recErr...) {
		return harness.ErrReported
	}
	base := walkFiles(T("REC-new"))
	if len(base) < 100 {
		return stop("a recording holds %d records, and a comparison of two things "+
			"nothing wrote passes.  The count is REPORTED and not pinned: it is 122 "+
			"here -- 102 screen cases, 16 memline cases and four sweeps -- and was 106 "+
			"before zero phase 40 added the memline corpus", len(base))
	}
	movedRec := func(which string) ([]string, error) {
		d := T("REC-" + which)
		if strings.Join(walkFiles(d), "\x00") != strings.Join(base, "\x00") {
			return nil, stop("the recording of %s holds different records from the output's", which)
		}
		var mv []string
		for _, n := range base {
			if !z30Same(filepath.Join(T("REC-new"), n), filepath.Join(d, n)) {
				mv = append(mv, n)
			}
		}
		return mv, nil
	}
	same, e := movedRec("old")
	if e != nil {
		return e
	}
	if len(same) > 0 {
		show := same
		if len(show) > 8 {
			show = show[:8]
		}
		r.say("THE RECORDING MOVED, in %d of %d records: %s", len(same), len(base), strings.Join(show, " "))
		r.cont("This phase declares NOTHING.  The editor asks for exactly the memory " +
			"it asked for before and is handed as much of it; what changed is where the " +
			"bytes come from and that giving them back costs nothing.")
		return harness.ErrReported
	}
	mca, e := movedRec("ca")
	if e != nil {
		return e
	}
	if len(mca) != len(base) {
		return stop("THE CONTROL ca DID NOT SHOW: with host_alloc returning nullptr "+
			"always, %d of %d records move and every one must -- an editor that cannot "+
			"allocate cannot draw", len(mca), len(base))
	}
	r.say("THE RECORDING IS BYTE-IDENTICAL, all %d records -- 102 screen cases, "+
		"every Ex command typed at `:`, every command line the parser may see, the four "+
		"pty scenarios and the terminal table.  EVERY ONE of them runs on the arena from "+
		"its first allocation, which is what makes an empty `diff -r` strong here: this is "+
		"not a subject the corpus has to be steered towards, it is the one thing every "+
		"session does thousands of times", len(base))
	r.cont("AND IT CAN FAIL: host_alloc returning nullptr always moves %d of %d -- "+
		"every record there is", len(mca), len(base))

	// --- 6. THE ARENA -------------------------------------------------------------------------
	jobs["probe"].wg.Wait()
	if jobs["probe"].err != nil {
		r.say("the instrumented build failed:")
		head(fileLines(T("e.probe")), 5, "               ")
		return harness.ErrReported
	}
	for _, v := range []string{"cnb", "cf", "ctiny", "cstdlib"} {
		jobs[v].wg.Wait()
		if jobs[v].err != nil {
			r.say("the control %s did not build:", v)
			head(fileLines(T("e."+v)), 5, "               ")
			return harness.ErrReported
		}
	}
	type corp struct{ v, kind string }
	cErr := map[corp]error{}
	var mu sync.Mutex
	var wgC sync.WaitGroup
	for _, v := range []string{"probe", "cnb", "cf"} {
		for _, k := range [][2]string{{"zcases", "SC"}, {"zmemline", "ML"}} {
			v, k := v, k
			wgC.Add(1)
			go func() {
				defer wgC.Done()
				e := exec.Command("sh", "tools/st.sh", k[0], T(v), T(k[1]+"-"+v)).Run()
				mu.Lock()
				cErr[corp{v, k[1]}] = e
				mu.Unlock()
			}()
		}
	}
	os.WriteFile(T("keys-q"), []byte(":q!\r"), 0o644)
	session := func(bin, errFile string) {
		in, _ := os.Open(T("keys-q"))
		defer in.Close()
		ef, _ := os.Create(T(errFile))
		defer ef.Close()
		c := exec.Command("./"+bin, "+set paste")
		c.Dir = tmp
		var env []string
		for _, kv := range os.Environ() {
			k := kv[:strings.IndexByte(kv+"=", '=')]
			switch k {
			case "VIMINIT", "EXINIT", "HOME", "VIM", "VIMRUNTIME", "XDG_CONFIG_HOME", "TERM":
				continue
			}
			env = append(env, kv)
		}
		c.Env = append(env, "HOME=", "VIM=", "VIMRUNTIME=", "XDG_CONFIG_HOME=", "TERM=xterm")
		c.Stdin, c.Stdout, c.Stderr = in, nil, ef
		err := c.Run()
		os.WriteFile(T("rc."+errFile), []byte(strconv.Itoa(z36ShellRC(err, c.ProcessState))+"\n"), 0o644)
	}
	session("ctiny", "tiny.err")
	session("new", "big.err")
	wgC.Wait()
	for _, v := range []string{"probe", "cnb", "cf"} {
		if cErr[corp{v, "SC"}] != nil {
			return stop("the screen corpus failed on %s", v)
		}
		if cErr[corp{v, "ML"}] != nil {
			return stop("the memline corpus failed on %s", v)
		}
	}
	type corpus struct {
		part, pre string
		floor     int
	}
	CORPORA := []corpus{{"screen", "SC", 100}, {"memline", "ML", 10}}
	cases := map[string][]string{}
	for _, c := range CORPORA {
		ents, _ := os.ReadDir(filepath.Join(T("REC-new"), c.part))
		var ns []string
		for _, en := range ents {
			ns = append(ns, en.Name())
		}
		sort.Strings(ns)
		cases[c.part] = ns
		if len(ns) < c.floor {
			return stop("the %s corpus is %d cases and a comparison over a corpus "+
				"nothing wrote passes", c.part, len(ns))
		}
	}
	movedC := func(which, side string) (map[string][]string, error) {
		out := map[string][]string{}
		for _, c := range CORPORA {
			d := T(c.pre + "-" + which)
			ents, _ := os.ReadDir(d)
			var ns []string
			for _, en := range ents {
				ns = append(ns, en.Name())
			}
			sort.Strings(ns)
			if strings.Join(ns, "\x00") != strings.Join(cases[c.part], "\x00") {
				return nil, stop("the %s %s corpus holds different cases", which, c.part)
			}
			a := filepath.Join(T("REC-"+side), c.part)
			for _, n := range cases[c.part] {
				if !z30Same(filepath.Join(a, n), filepath.Join(d, n)) {
					out[c.part] = append(out[c.part], n)
				}
			}
		}
		return out, nil
	}
	peak := map[string]int64{}
	calls := map[string]int64{}
	for _, c := range CORPORA {
		seen := 0
		for _, n := range cases[c.part] {
			m := z41Arena.FindStringSubmatch(readFile(filepath.Join(T(c.pre+"-probe"), n)))
			if m == nil {
				continue
			}
			seen++
			u, _ := strconv.ParseInt(m[1], 10, 64)
			k, _ := strconv.ParseInt(m[2], 10, 64)
			if u > peak[c.part] {
				peak[c.part] = u
			}
			calls[c.part] += k
		}
		if seen != len(cases[c.part]) {
			return stop("the instrumented build marked %d of the %d %s cases, and it "+
				"must mark every one: the counter is printed from host_exit(), which "+
				"every case reaches", seen, len(cases[c.part]), c.part)
		}
	}
	high := peak["screen"]
	if peak["memline"] > high {
		high = peak["memline"]
	}
	total := calls["screen"] + calls["memline"]
	if high < 100000 || total < 10000 {
		return stop("the instrument reports a high-water of %d bytes over %d calls, and "+
			"a corpus that hammers lalloc() cannot give numbers that small -- the "+
			"counters are not on the path", high, total)
	}
	if peak["memline"] <= peak["screen"] {
		return stop("the heaviest memline case asks for %d bytes and the heaviest "+
			"screen case for %d.  The memline corpus builds buffers of thousands of "+
			"lines and the screen corpus does not, so if it is not asking for MORE "+
			"memory it is not the corpus this arena was sized from", peak["memline"], peak["screen"])
	}
	if high*4 > arena {
		return stop("the corpus asks for %d bytes at its worst and the arena is %d.  "+
			"Less than four times the measured high-water is not a margin, it is a "+
			"coincidence waiting to end: either the arena grows or this phase is wrong "+
			"about the workload", high, arena)
	}
	r.say("THE HIGH-WATER, MEASURED ON THIS PHASE'S OWN OUTPUT and over BOTH "+
		"corpora, marking every case of each: the heaviest of the %d memline cases asks "+
		"host_alloc for %d bytes and the heaviest of the %d screen cases for %d -- 115 "+
		"times less -- across %d calls in all.  So the arena is %.1f times what the corpus "+
		"has ever needed and is %.2f%% used at its worst.  Nothing is freed, so that number "+
		"is the session's whole allocation TRAFFIC and not its live data, which is why it "+
		"is the number the arena has to be sized from AND why it is a memline case that "+
		"sets it: a 25,000-line buffer edited in the middle churns the text layer, and "+
		"churn is traffic", len(cases["memline"]), peak["memline"], len(cases["screen"]),
		peak["screen"], total, float64(arena)/float64(high), 100.0*float64(high)/float64(arena))
	cnb, e := movedC("cnb", "new")
	if e != nil {
		return e
	}
	cf, e := movedC("cf", "old")
	if e != nil {
		return e
	}
	for _, c := range CORPORA {
		if len(cnb[c.part]) != len(cases[c.part]) {
			return stop("THE CONTROL cnb DID NOT SHOW: with the offset never advancing, "+
				"host_alloc hands the same block out every time, and that moves %d of "+
				"the %d %s cases where it must move every one.  Without this control "+
				"the bump is untested: a `host_alloc` that returned the arena's base "+
				"for ever would pass the symbol check, the cut and the size assertion",
				len(cnb[c.part]), len(cases[c.part]), c.part)
		}
		if len(cf[c.part]) > 0 {
			return stop("PHASE 35 MEASURED ITS `cf` CONTROL AT 0 OF 102 AND IT MOVES %d "+
				"OF THE %d %s CASES HERE.  That control -- host_free doing nothing, "+
				"built from the INPUT -- is the whole reason this phase could be "+
				"written; if it moves a case, freeing was never free and something has "+
				"changed underneath both phases", len(cf[c.part]), len(cases[c.part]), c.part)
		}
	}
	r.say("THE CONTROLS, AND THE ONE THAT MOVES NOTHING IS REPORTED AND NOT HIDDEN:")
	r.cont("  the bump  the offset never advancing moves %d of %d screen cases and "+
		"%d of %d memline cases.  It is the only control here that tests the ALLOCATOR "+
		"rather than the wrapper -- `ca` above moves everything for any broken host_alloc "+
		"at all, and this one is still a bump allocator in every respect except that its "+
		"bookkeeping does nothing", len(cnb["screen"]), len(cases["screen"]), len(cnb["memline"]),
		len(cases["memline"]))
	r.cont("  host_free doing NOTHING AT ALL moves 0 of %d screen cases and 0 of %d "+
		"memline cases, and that is PHASE 35'S OWN CONTROL re-run on this phase's input "+
		"rather than a new claim -- on a corpus phase 35 did not have.  A leak is invisible "+
		"to this corpus too, so the byte-identical recording above is NOT what says the "+
		"freeing changed; it says the ALLOCATION did not.  What says the freeing changed is "+
		"`free` leaving nm -u", len(cases["screen"]), len(cases["memline"]))

	// --- 7. THE GUARD -----------------------------------------------------------------------
	const small = 256 * 1024
	tiny, big := readFile(T("tiny.err")), readFile(T("big.err"))
	rcTiny, _ := strconv.Atoi(strings.TrimSpace(readFile(T("rc.tiny.err"))))
	rcBig, _ := strconv.Atoi(strings.TrimSpace(readFile(T("rc.big.err"))))
	m := z41Exhaust.FindStringSubmatch(tiny)
	if m == nil {
		t120 := tiny
		if len(t120) > 120 {
			t120 = t120[:120]
		}
		return stop("THE GUARD DID NOT SHOW: a 256 KiB arena ran a bare session to the "+
			"end and printed %s on stderr.  The abort is the one branch of this phase a "+
			"recording can never take, so it is the one that most needs a probe", pyRepr26(t120))
	}
	size, _ := strconv.ParseInt(m[1], 10, 64)
	used, _ := strconv.ParseInt(m[2], 10, 64)
	req, _ := strconv.ParseInt(m[3], 10, 64)
	if size != small {
		return stop("the message names an arena of %d and the control was built with %d", size, small)
	}
	if used+req <= size {
		return stop("the message says %d used and %d requested, which FITS in %d -- the "+
			"abort fired on a request the arena could have served", used, req, size)
	}
	if rcTiny == 0 {
		return stop("the exhausted binary exited 0.  It must not: a host that runs out " +
			"of memory and says so with a success status is a silent failure with " +
			"extra steps")
	}
	if strings.TrimSpace(big) != "" || rcBig != 0 {
		b80 := big
		if len(b80) > 80 {
			b80 = b80[:80]
		}
		return stop("the SAME session on the real output wrote %s to stderr and exited "+
			"%d.  Both halves are needed: an abort that fired on every session would "+
			"pass the test above and be a catastrophe", pyRepr26(b80), rcBig)
	}
	r.say("THE GUARD, ON BOTH SIDES: with a 256 KiB arena a bare session aborts with "+
		"`host arena exhausted: %d bytes, %d used, request %d` and exits %d -- the request "+
		"that did not fit is the screen, the single largest allocation this editor makes -- "+
		"and the identical session on the %d-byte output writes nothing to stderr and exits "+
		"0.  The message names the arena, what was used and what was asked for, because a "+
		"host that dies owes the next person the three numbers that decide what to change",
		size, used, req, rcTiny, arena)

	// --- 8. THE PROBE the corpus cannot give ------------------------------------------------
	for _, v := range []string{"din", "dout"} {
		jobs[v].wg.Wait()
		if jobs[v].err != nil {
			r.say("the driver %s did not build:", v)
			head(fileLines(T("e."+v)), 5, "               ")
			return harness.ErrReported
		}
	}
	runD := func(v string) (string, int) {
		c := exec.Command("./"+v, "Z")
		c.Dir = tmp
		var ob, eb strings.Builder
		c.Stdout, c.Stderr = &ob, &eb
		err := c.Run()
		return eb.String(), z36ShellRC(err, c.ProcessState)
	}
	a, rcA := runD("din")
	b, rcB := runD("dout")
	for _, x := range []struct {
		w  string
		rc int
	}{{"din", rcA}, {"dout", rcB}} {
		if x.rc != 0 {
			return stop("the %s driver exited %d", x.w, x.rc)
		}
	}
	ma, mb := z41Grows.FindStringSubmatch(a), z41Grows.FindStringSubmatch(b)
	if ma == nil || mb == nil {
		return stop("a driver printed no `grows=` line, so nothing says it reached the " +
			"arm this phase rewrote")
	}
	if n, _ := strconv.Atoi(ma[1]); n < 5 || ma[1] != mb[1] {
		return stop("the grow arm was entered %s times in the input and %s in the "+
			"output, and the driver is written to enter it many times in both -- a "+
			"probe that reaches the rewritten line zero times proves nothing", ma[1], mb[1])
	}
	if a != b {
		a200, b200 := a, b
		if len(a200) > 200 {
			a200 = a200[:200]
		}
		if len(b200) > 200 {
			b200 = b200[:200]
		}
		return stop("THE TWO DRIVERS PRINT DIFFERENT BYTES, so the realloc rewrite is "+
			"not faithful:\n               in  %s\n               out %s", pyRepr26(a200), pyRepr26(b200))
	}
	if n := len(strings.Split(a, "\n")); n < 8 {
		return stop("the driver printed %d lines and it formats seven strings", n)
	}
	r.say("THE PROBE FOR WHAT NO RECORDING CAN REACH: adjust_types() grows *ap_types "+
		"only when a format string carries a positional spec, and NOT ONE STRING LITERAL "+
		"IN THIS FILE HAS ONE -- so no session in the corpus has ever entered the arm this "+
		"phase rewrote.  The same driver built into the input and into the output runs six "+
		"ascending positional formats through it, enters the grow arm %s times in each, and "+
		"the two binaries print the same bytes.  Its sibling, format_overflow_error()'s "+
		"free of argcopy, cannot be probed because it cannot RUN: its guard is "+
		"`overflow_err`, which is `tvs != nullptr`, and vim_vsnprintf_typval has one caller "+
		"in this file passing nullptr -- phase 9's and phase 17's kind, and it is rewritten "+
		"for the same reason a dead branch is kept correct", ma[1])

	// --- 9. the host's vocabulary is still the host's --------------------------------------
	zh := exec.Command("sh", "tools/st.sh", "zhostonly", f)
	zh.Stdout, zh.Stderr = w, w
	if err := zh.Run(); err != nil {
		return harness.ErrReported
	}
	r.say("and that is phase 20's check, undisturbed and unamended.  zhostonly reads the host region from " +
		"host_winch_pending to musl_suspend's last brace, and this phase writes NOTHING in it: host_alloc and " +
		"host_free have sat BELOW that brace since phase 35 put them beside main.  Neither `malloc`, `free`, " +
		"`realloc`, `max_align_t` nor `alignof` is in that tool's vocabulary, so it needed no new word and no new " +
		"exception -- the phase moves memory, not a syscall")

	// --- 10. <stdlib.h>, measured and declined -----------------------------------------------
	if !z30Same(T("cstdlib"), T("new")) {
		return stop("the output built WITHOUT <stdlib.h> is not byte-identical to the output, so the directive is " +
			"not dead after all and the sentence below would be wrong")
	}
	r.say("<stdlib.h> IS NOW DEAD AND IT STAYS, which is measured rather than argued: malloc, free and realloc were "+
		"its only users, and the output built with the directive DELETED is BYTE-IDENTICAL, %d bytes either way.  "+
		"ZERO-GOAL.md lets a phase remove a directive; phase 13 is the precedent for declining, having measured "+
		"that removing three was free and written \"the count stays 18\" into its own program.  Eleven stays "+
		"eleven: this phase's subject is the allocator, the removal is free for whoever asks for it, and a phase "+
		"that changes two things cannot say which one a difference came from", sizeOf(T("new")))

	// --- 11. canon -----------------------------------------------------------------------------
	jCanon.wg.Wait()
	if !z30Same(T("canon.c"), f) {
		r.say("tools/canon.sh CHANGED THE OUTPUT, and it must be a no-op:")
		head(z30Diff(f, T("canon.c")), 6, "               ")
		return harness.ErrReported
	}
	canonWord := ""
	for _, l := range strings.Split(string(canonLog), "\n") {
		if z35CanonLn.MatchString(l) {
			canonWord = z35CanonLn.ReplaceAllString(l, "")
			break
		}
	}
	r.say("tools/canon.sh is a NO-OP on the output (%s)", canonWord)
	return nil
}
