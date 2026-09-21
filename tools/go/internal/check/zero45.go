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

func init() { register("zero45", Zero45) }

var (
	z45Name     = regexp.MustCompile(`\b[A-Za-z_][A-Za-z0-9_]*\b`)
	z45Alloc    = regexp.MustCompile(`\b(alloc\w*)\(sizeof\((\w+)\)\)`)
	z45AllocAny = regexp.MustCompile(`\balloc\w*\(`)
	z45Memfile  = regexp.MustCompile(`\bmemfile\b`)
	z45Tag      = regexp.MustCompile(`^(.*= )(.*);$`)
	z45Assert   = regexp.MustCompile(`static_assert\(PB_COUNT_MAX == \(\d+ - 8\)`)
)

// z45Code is the heredoc's code(): every string and character literal
// blanked to one space, escapes skipped two at a time, across newlines.
func z45Code(t string) string {
	var out strings.Builder
	i, n := 0, len(t)
	for i < n {
		c := t[i]
		if c == '"' || c == '\'' {
			q := c
			out.WriteByte(' ')
			i++
			for i < n && t[i] != q {
				if t[i] == '\\' {
					i += 2
				} else {
					i++
				}
			}
			i++
			continue
		}
		out.WriteByte(c)
		i++
	}
	return out.String()
}

// z45Instrument is this phase's MARK_PY: phase 40's five markers, three of
// them at lines this phase rewrote, so each side names its own.
func z45Instrument(src, dst string, out bool) (string, string) {
	pick := func(a, b string) string {
		if out {
			return a
		}
		return b
	}
	marks := []z44Mark{
		{"MLSPLITDATA", pick(`(?m)^        if \(\(hp_new = ml_new_data\(\)\) == nullptr\)$`,
			`(?m)^        if \(\(hp_new = ml_new_data\(mfp\)\) == nullptr\)$`), "before", ""},
		{"MLSPLITPTR", pick(`(?m)^                hp_new = ml_new_ptr\(\);$`,
			`(?m)^                hp_new = ml_new_ptr\(mfp\);$`), "before", ""},
		{"MLSPLITROOT", pick(`(?m)^                pp_new->pb_count = pp->pb_count;$`,
			`(?m)^ *musl_memmove\(\(char \*\)\(pp_new\), \(char \*\)\(pp\), \(usize\)page_size\) ;$`), "before", ""},
		{"MLIDXNZ", `(?m)^                ip->ip_index = idx;$`, "after", "idx > 0"},
		{"MLDEEP", `(?m)^        if \(\(top = ml_add_stack\(buf\)\) < 0\)$`, "before", "++zprobe_lvl >= 2"},
	}
	t := readFile(src)
	if n := len(z44Low.FindAllStringIndex(t, -1)); n != 1 {
		return "", fmt.Sprintf("the probe cannot declare its depth counter: the file has %d `low = 1;`", n)
	}
	loc := z44Low.FindStringIndex(t)
	t = t[:loc[0]] + "    int zprobe_lvl = 0;\n    low = 1;" + t[loc[1]:]
	var names []string
	for _, m := range marks {
		hits := regexp.MustCompile(m.pat).FindAllStringIndex(t, -1)
		if len(hits) != 1 {
			return "", fmt.Sprintf("the anchor for %s is in the source %d times, expected 1", m.name, len(hits))
		}
		h := hits[0]
		body := fmt.Sprintf("{ static int z_%s = 0; if (!z_%s) { z_%s = 1; host_message(\"%s\\n\", -1, TRUE); } }",
			m.name, m.name, m.name, m.name)
		ins := "        " + body + "\n"
		if m.cond != "" {
			ins = fmt.Sprintf("        if (%s) %s\n", m.cond, body)
		}
		if m.where == "before" {
			t = t[:h[0]] + ins + t[h[0]:]
		} else {
			e := h[1] + 1
			if e > len(t) {
				e = len(t)
			}
			t = t[:e] + ins + t[e:]
		}
		names = append(names, m.name)
	}
	os.WriteFile(dst, []byte(t), 0o644)
	return strings.Join(names, " "), ""
}

// Zero45 is phase 45's check: fold the node types.
func Zero45(w io.Writer, args []string) error {
	if len(args) != 2 {
		return fmt.Errorf("usage: check zero45 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	f := filepath.Join(work, "zero-vim.c")
	oldC := filepath.Join(state, "old.c")
	say := func(tag, format string, a ...any) { (&rep{tag: tag, w: w}).say(format, a...) }
	die := func(tag, format string, a ...any) error {
		say(tag, format, a...)
		return harness.ErrReported
	}
	prefixed := func(s string) {
		for _, l := range strings.Split(strings.TrimRight(s, "\n"), "\n") {
			fmt.Fprintf(w, "               %s\n", l)
		}
	}
	beforeRaw := strings.TrimRight(readFile(filepath.Join(state, "input-lines")), "\n")
	tmp, err := os.MkdirTemp("", "zero45-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	T := func(n string) string { return filepath.Join(tmp, n) }
	mkfile := readFile(filepath.Join(work, "Makefile"))
	mkdir := func(d string) {
		os.MkdirAll(T(d), 0o755)
		os.WriteFile(filepath.Join(T(d), "Makefile"), []byte(mkfile), 0o644)
	}
	_ = exec.Command("make", "-C", work, "clean").Run()
	newBin := filepath.Join(work, "zero-vim")
	if _, e := os.Stat(newBin); e == nil {
		return die("build", "the clean did not remove zero-vim, so nothing below would be a recording of this phase")
	}
	if err := exec.Command("make", "-C", work).Run(); err != nil {
		return die("build", "FAILED -- rerun by hand: make -C %s", work)
	}
	oldBin := filepath.Join(state, "old")

	// --- 2, 3 and 4: the source ---------------------------------------------------------
	newT, oldT := readFile(f), readFile(oldC)
	type gl struct{ name, n string }
	var gone []gl
	for _, l := range strings.Split(readFile(filepath.Join(state, "gone")), "\n") {
		if strings.TrimSpace(l) == "" {
			continue
		}
		i := strings.LastIndex(l, "\t")
		if i < 0 {
			gone = append(gone, gl{l, ""})
			continue
		}
		gone = append(gone, gl{l[:i], l[i+1:]})
	}
	var forsweep []string
	for _, l := range strings.Split(readFile(filepath.Join(state, "forsweep")), "\n") {
		if strings.TrimSpace(l) != "" {
			forsweep = append(forsweep, strings.TrimSpace(l))
		}
	}
	fanout, _ := strconv.Atoi(strings.TrimSpace(readFile(filepath.Join(state, "fanout"))))
	WITH := []string{"nextp", "error_noblock"}
	WRITTEN := []string{"PB_COUNT_MAX", "bh_id", "pb_hdr", "db_hdr", "ml_free_tree"}
	wc := func(t, n string) int {
		return len(regexp.MustCompile(`\b` + regexp.QuoteMeta(n) + `\b`).FindAllStringIndex(t, -1))
	}
	names := func(t string) map[string]bool {
		m := map[string]bool{}
		for _, x := range z45Name.FindAllString(z45Code(t), -1) {
			m[x] = true
		}
		return m
	}
	oldN, newN := names(oldT), names(newT)
	var left, came []string
	for x := range oldN {
		if !newN[x] {
			left = append(left, x)
		}
	}
	for x := range newN {
		if !oldN[x] {
			came = append(came, x)
		}
	}
	sort.Strings(left)
	sort.Strings(came)
	wantSet := map[string]bool{}
	for _, g := range gone {
		wantSet[g.name] = true
	}
	for _, x := range append(append([]string{}, forsweep...), WITH...) {
		wantSet[x] = true
	}
	wantLeft := z27Keys(wantSet)
	if strings.Join(left, " ") != strings.Join(wantLeft, " ") {
		return die("partition", "the names that leave are %s and this phase accounts for %s", z43PyList(left), z43PyList(wantLeft))
	}
	wr := append([]string{}, WRITTEN...)
	sort.Strings(wr)
	if strings.Join(came, " ") != strings.Join(wr, " ") {
		return die("partition", "the names that arrive are %s and this phase writes %s", z43PyList(came), z43PyList(wr))
	}
	sum := 0
	var gn []string
	for _, g := range gone {
		n, _ := strconv.Atoi(g.n)
		if wc(oldT, g.name) != n {
			return die("partition", "the edit recorded %s at %s mentions of the input and it has %d", g.name, g.n, wc(oldT, g.name))
		}
		sum += n
		gn = append(gn, g.name)
	}
	say("partition", "the file's whole vocabulary moves by %d names out and %d in: %s -- %d mentions -- the edit's; %s "+
		"the sweep's; %s with the function that held them; and %s written", len(left), len(came), strings.Join(gn, ", "),
		sum, strings.Join(forsweep, ", "), strings.Join(WITH, ", "), strings.Join(WRITTEN, ", "))
	for _, n := range forsweep {
		if wc(oldT, n) < 2 {
			return die("division", "%s has %d mentions in the input, so leaving it for the sweep would not be leaving anything", n, wc(oldT, n))
		}
	}
	say("division", "the edit takes the %d names above, every one of which is reachable code no sweep could see, and "+
		"leaves %s at one mention each -- their own definitions -- which is the whole of what the sweep finds",
		len(gone), strings.Join(forsweep, " and "))
	structOf := func(name string) ([]string, error) {
		m := regexp.MustCompile(`(?ms)^struct ` + name + `\n\{\n(.*?)^\};$`).FindStringSubmatch(newT)
		if m == nil {
			return nil, die("record", "struct %s is not in the output", name)
		}
		var out []string
		for _, l := range strings.Split(m[1], "\n") {
			if strings.TrimSpace(l) != "" {
				out = append(out, strings.TrimSpace(l))
			}
		}
		return out, nil
	}
	lastWords := func(xs []string) string {
		var o []string
		for _, x := range xs {
			fs := strings.Fields(x)
			o = append(o, fs[len(fs)-1])
		}
		return strings.Join(o, " ")
	}
	hdr, e := structOf("block_hdr")
	if e != nil {
		return e
	}
	ptr, e := structOf("pointer_block")
	if e != nil {
		return e
	}
	dat, e := structOf("data_block")
	if e != nil {
		return e
	}
	if lastWords(hdr) != "bh_id;" {
		return die("record", "struct block_hdr is not the node's one-member tag: %s", strings.Join(hdr, " "))
	}
	if lastWords(ptr) != "pb_hdr; pb_count; pb_pointer[PB_COUNT_MAX];" {
		return die("record", "struct pointer_block is not a tag, a count and a fixed array of entries: %s", strings.Join(ptr, " "))
	}
	if lastWords(dat) != "db_hdr; db_line_count; db_line[DB_LINE_MAX];" {
		return die("record", "struct data_block is not a tag, a count and a fixed array of records: %s", strings.Join(dat, " "))
	}
	if !strings.HasPrefix(ptr[0], "bhdr_T") || !strings.HasPrefix(dat[0], "bhdr_T") {
		return die("record", "the tag is not the FIRST member of both node types, so (PTR_BL *)hp and (bhdr_T *)pp would not be the same address")
	}
	if z45Memfile.MatchString(z45Code(newT)) || !z45Memfile.MatchString(z45Code(oldT)) {
		return die("record", "there is still a memfile in the output, or there was none in the input")
	}
	if !regexp.MustCompile(fmt.Sprintf(`enum \{ PB_COUNT_MAX = %d \};`, fanout)).MatchString(newT) {
		return die("record", "PB_COUNT_MAX is not the %d the edit fixed it at", fanout)
	}
	say("record", "a node is `{%s}` and then either `{%s}` or `{%s}`, the tag first in both, and there is no memfile in "+
		"the file at all", strings.Join(hdr, " "), strings.Join(ptr[1:], " "), strings.Join(dat[1:], " "))
	bodyOf := func(t, head string) (string, error) {
		m := regexp.MustCompile(`(?ms)^` + regexp.QuoteMeta(head) + `\n\{\n(.*?)^\}$`).FindStringSubmatch(t)
		if m == nil {
			return "", die("alloc", "%s is not in the output to be read", head)
		}
		return m[1], nil
	}
	for _, x := range [][2]string{{"ml_new_data(void)", "DATA_BL"}, {"ml_new_ptr(void)", "PTR_BL"}} {
		b, e := bodyOf(newT, x[0])
		if e != nil {
			return e
		}
		got := z45Alloc.FindAllStringSubmatch(b, -1)
		if len(got) != 1 || got[0][1] != "alloc_clear" || got[0][2] != x[1] {
			var gs []string
			for _, g := range got {
				gs = append(gs, fmt.Sprintf("('%s', '%s')", g[1], g[2]))
			}
			return die("alloc", "%s allocates [%s], and a node is ONE alloc_clear of sizeof(%s)", x[0], strings.Join(gs, ", "), x[1])
		}
		if len(z45AllocAny.FindAllStringIndex(b, -1)) != 1 {
			return die("alloc", "%s asks for memory more than once", x[0])
		}
	}
	for _, head := range []string{"ml_new_data(memfile_T *mfp)", "ml_new_ptr(memfile_T *mfp)"} {
		if !regexp.MustCompile(`(?m)^` + regexp.QuoteMeta(head) + `$`).MatchString(oldT) {
			return die("alloc", "the input's %s is not where this check reads it", head)
		}
	}
	ab, e := bodyOf(oldT, "mf_alloc_bhdr(memfile_T *mfp, int page_count)")
	if e != nil {
		return e
	}
	if len(z45AllocAny.FindAllStringIndex(ab, -1)) != 2 || !strings.Contains(ab, "mf_page_size") {
		return die("alloc", "the input does not make TWO allocations per node, a header and a page of mf_page_size")
	}
	say("alloc", "each constructor makes ONE allocation, alloc_clear(sizeof(DATA_BL)) and alloc_clear(sizeof(PTR_BL)): "+
		"where the input allocated a bhdr_T AND a page of mf_page_size for each of the two kinds, four allocations of "+
		"4,128 bytes between them where there are now two of 1,040 and 4,088")

	// --- 3b. sizeof(PTR_EN) == 16, COMPILED, on both cuts ------------------------------------
	writeCut := func(src, dst string) int {
		lines := z28Cut(readFile(src))
		text := ""
		for _, l := range lines {
			text += l + "\n"
		}
		os.WriteFile(dst, []byte(text), 0o644)
		return len(lines)
	}
	cutLines := writeCut(f, T("cut.c"))
	cutOld := writeCut(oldC, T("cut.old.c"))
	for _, side := range []string{"new", "old"} {
		src := T("cut.c")
		if side == "old" {
			src = T("cut.old.c")
		}
		os.WriteFile(T("en."+side+".c"), []byte(readFile(src)+"static_assert(sizeof(PTR_EN) == 16, \"the tree fanout is computed from this\");\n"), 0o644)
		c := exec.Command("gcc", "-fsyntax-only", T("en."+side+".c"))
		var eb strings.Builder
		c.Stderr = &eb
		if err := c.Run(); err != nil {
			say("fanout", "sizeof(PTR_EN) is NOT 16 on the %s side, so the tree's fanout has moved and zero phase 40's "+
				"root-split coverage is not what it was:", side)
			L := strings.Split(strings.TrimRight(eb.String(), "\n"), "\n")
			if len(L) > 3 {
				L = L[:3]
			}
			prefixed(strings.Join(L, "\n"))
			return harness.ErrReported
		}
		os.WriteFile(T("bad."+side+".c"), []byte(readFile(src)+"static_assert(sizeof(PTR_EN) == 8, \"the control\");\n"), 0o644)
		if exec.Command("gcc", "-fsyntax-only", T("bad."+side+".c")).Run() == nil {
			return die("fanout", "the %s cut accepts sizeof(PTR_EN) == 8 as well as == 16, so the assertion above is not an assertion", side)
		}
	}
	say("fanout", "sizeof(PTR_EN) == 16 compiles against BOTH cuts and == 8 compiles against neither, so the entry is the "+
		"width it was and PB_COUNT_MAX is (4096 - 8) / 16 = 255 either side")

	// --- 5. two full recordings ---------------------------------------------------------------
	for _, x := range [][3]string{{newBin, f, "rec1"}, {newBin, f, "rec2"}, {oldBin, oldC, "rec0"}} {
		c := exec.Command("sh", "tools/zrecord.sh", x[0], x[1], T(x[2]))
		c.Stderr = w
		if err := c.Run(); err != nil {
			return harness.ErrReported
		}
	}
	if dl := diffRQ(T("rec1"), T("rec2")); len(dl) > 0 {
		say("record", "two recordings of the same binary differ, so nothing below is evidence")
		if len(dl) > 3 {
			dl = dl[:3]
		}
		prefixed(strings.Join(dl, "\n"))
		return harness.ErrReported
	}
	if dl := diffRQ(T("rec0"), T("rec1")); len(dl) > 0 {
		say("record", "the output does not record what the input records:")
		if len(dl) > 5 {
			dl = dl[:5]
		}
		prefixed(strings.Join(dl, "\n"))
		return harness.ErrReported
	}
	countDir := func(d string) int { es, _ := os.ReadDir(d); return len(es) }
	say("record", "%d screen cases, %d memline cases and four tables, byte for byte the input's, twice",
		countDir(filepath.Join(T("rec1"), "screen")), countDir(filepath.Join(T("rec1"), "memline")))

	// --- 6. the corpus reaches the tree, case by case --------------------------------------
	mkdir("pnew")
	mkdir("pold")
	marksNew, msg := z45Instrument(f, filepath.Join(T("pnew"), "zero-vim.c"), true)
	if msg != "" {
		say("probe", "the instrument could not be built from this phase's output:")
		prefixed(msg)
		return harness.ErrReported
	}
	marksOld, msg := z45Instrument(oldC, filepath.Join(T("pold"), "zero-vim.c"), false)
	if msg != "" {
		say("probe", "the instrument could not be built from this phase's input:")
		prefixed(msg)
		return harness.ErrReported
	}
	buildPair := func(a, b, msgA, msgB, tag string) error {
		var wg sync.WaitGroup
		var ea, eb error
		wg.Add(2)
		go func() { defer wg.Done(); ea = exec.Command("make", "-C", T(a)).Run() }()
		go func() { defer wg.Done(); eb = exec.Command("make", "-C", T(b)).Run() }()
		wg.Wait()
		if ea != nil {
			return die(tag, "%s", msgA)
		}
		if eb != nil {
			return die(tag, "%s", msgB)
		}
		return nil
	}
	if e := buildPair("pnew", "pold", "the instrumented output did not build", "the instrumented input did not build", "probe"); e != nil {
		return e
	}
	runAll := func(cmds [][]string) error {
		var wg sync.WaitGroup
		errs := make([]error, len(cmds))
		for i, c := range cmds {
			i, c := i, c
			wg.Add(1)
			go func() {
				defer wg.Done()
				cmd := exec.Command(c[0], c[1:]...)
				cmd.Stderr = w
				errs[i] = cmd.Run()
			}()
		}
		wg.Wait()
		for _, e := range errs {
			if e != nil {
				return e
			}
		}
		return nil
	}
	if runAll([][]string{
		{"sh", "tools/st.sh", "zmemline", filepath.Join(T("pnew"), "zero-vim"), T("pnew-mem")},
		{"sh", "tools/st.sh", "zmemline", filepath.Join(T("pold"), "zero-vim"), T("pold-mem")},
		{"sh", "tools/st.sh", "zcases", filepath.Join(T("pnew"), "zero-vim"), T("pnew-scr")},
	}) != nil {
		return harness.ErrReported
	}
	listDir := func(d string) []string {
		es, _ := os.ReadDir(d)
		var ns []string
		for _, en := range es {
			ns = append(ns, en.Name())
		}
		sort.Strings(ns)
		return ns
	}
	mnew, mold := strings.Fields(marksNew), strings.Fields(marksOld)
	per := func(d string, marks []string) (map[string]map[string]bool, []string) {
		out := map[string]map[string]bool{}
		ns := listDir(d)
		for _, n := range ns {
			t := harness.DecodeReplace([]byte(readFile(filepath.Join(d, n))))
			s := map[string]bool{}
			for _, m := range marks {
				if strings.Contains(t, m) {
					s[m] = true
				}
			}
			out[n] = s
		}
		return out, ns
	}
	nw, nOrder := per(T("pnew-mem"), mnew)
	od, oOrder := per(T("pold-mem"), mold)
	sc, _ := per(T("pnew-scr"), mnew)
	if strings.Join(nOrder, "\x00") != strings.Join(oOrder, "\x00") {
		fmt.Fprintln(w, "the two sides did not record the same cases")
		return harness.ErrReported
	}
	setStr := func(s map[string]bool) string { return z43PyList(z27Keys(s)) }
	eqSet := func(a, b map[string]bool) bool { return setStr(a) == setStr(b) }
	var mv []string
	for _, n := range nOrder {
		if !eqSet(nw[n], od[n]) {
			mv = append(mv, n)
		}
	}
	if len(mv) > 0 {
		var ds []string
		for k, n := range mv {
			if k >= 3 {
				break
			}
			ds = append(ds, fmt.Sprintf("%s %s against %s", n, setStr(nw[n]), setStr(od[n])))
		}
		fmt.Fprintf(w, "%s reach a different part of the tree than they did: %s\n", strings.Join(mv, " "), strings.Join(ds, "; "))
		return harness.ErrReported
	}
	tot := map[string]int{}
	for _, m := range mnew {
		for _, n := range nOrder {
			if nw[n][m] {
				tot[m]++
			}
		}
	}
	var zero []string
	for _, m := range mnew {
		if tot[m] == 0 {
			zero = append(zero, m)
		}
	}
	if len(zero) > 0 {
		fmt.Fprintf(w, "the corpus reaches none of: %s -- a corpus that MEANS to reach a split and does not is the defect "+
			"zero phase 40 exists to end\n", strings.Join(zero, " "))
		return harness.ErrReported
	}
	scrSet := map[string]bool{}
	for _, s := range sc {
		for m := range s {
			scrSet[m] = true
		}
	}
	if len(scrSet) > 0 {
		fmt.Fprintf(w, "%s is reached by the 102 screen cases, so the memline corpus is not what makes the text layer "+
			"visible on this boundary\n", strings.Join(z27Keys(scrSet), " "))
		return harness.ErrReported
	}
	var root []string
	for _, n := range nOrder {
		if nw[n]["MLSPLITROOT"] {
			root = append(root, n)
		}
	}
	var tp []string
	for _, m := range mnew {
		tp = append(tp, fmt.Sprintf("%s %d", m, tot[m]))
	}
	say("probe", "%s -- the same markers in the same cases as the input, case by case; the ROOT SPLIT is reached by %d "+
		"of %d, %s, and 0 of the 102 screen cases reach any of them", strings.Join(tp, "  "), len(root), len(nOrder),
		strings.Join(root, " "))

	// --- 7. what a node costs the arena ---------------------------------------------------
	arenaEdit := func(src, dst string) string {
		t := readFile(src)
		edits := [][2]string{
			{`(?m)^static int host_code;$`, "static long z_arena;\nstatic int host_code;"},
			{`(?m)^host_alloc\(usize n\)\n\{$`, "host_alloc(usize n)\n{\n    z_arena += (long)((n + 15) & ~(usize)15);"},
			{`(?m)^    host_code = r;$`, "    host_code = r;\n" +
				"    { char b[48]; char d[24]; int i = 0; int k = 0; long v = z_arena;\n" +
				"      b[i++] = 90; b[i++] = 65; b[i++] = 61;\n" +
				"      if (v == 0) { d[k++] = 48; }\n" +
				"      while (v > 0) { d[k++] = (char)(48 + (v % 10)); v /= 10; }\n" +
				"      while (k > 0) { b[i++] = d[--k]; }\n" +
				"      b[i++] = 10; host_message(b, i, TRUE); }"},
		}
		for _, x := range edits {
			hs := regexp.MustCompile(x[0]).FindAllStringIndex(t, -1)
			if len(hs) != 1 {
				return fmt.Sprintf("the arena counter anchor %s is in the source %d times, expected 1",
					pyRepr26(strings.TrimPrefix(x[0], "(?m)")), len(hs))
			}
			t = t[:hs[0][0]] + x[1] + t[hs[0][1]:]
		}
		os.WriteFile(dst, []byte(t), 0o644)
		return ""
	}
	mkdir("anew")
	mkdir("aold")
	msg = arenaEdit(f, filepath.Join(T("anew"), "zero-vim.c"))
	if msg == "" {
		msg = arenaEdit(oldC, filepath.Join(T("aold"), "zero-vim.c"))
	}
	if msg != "" {
		say("arena", "the counter could not be built:")
		prefixed(msg)
		return harness.ErrReported
	}
	if e := buildPair("anew", "aold", "the instrumented output did not build", "the instrumented input did not build", "arena"); e != nil {
		return e
	}
	if runAll([][]string{
		{"sh", "tools/st.sh", "zmemline", filepath.Join(T("anew"), "zero-vim"), T("anew-mem")},
		{"sh", "tools/st.sh", "zmemline", filepath.Join(T("aold"), "zero-vim"), T("aold-mem")},
	}) != nil {
		return harness.ErrReported
	}
	perZA := func(d string) (map[string]int64, []string) {
		out := map[string]int64{}
		ns := listDir(d)
		for _, n := range ns {
			var best int64
			for _, m := range z44ZA.FindAllStringSubmatch(readFile(filepath.Join(d, n)), -1) {
				v, _ := strconv.ParseInt(m[1], 10, 64)
				if v > best {
					best = v
				}
			}
			out[n] = best
		}
		return out, ns
	}
	na, naOrder := perZA(T("anew-mem"))
	oa, oaOrder := perZA(T("aold-mem"))
	minOld := int64(-1)
	for _, v := range oa {
		if minOld < 0 || v < minOld {
			minOld = v
		}
	}
	if strings.Join(naOrder, "\x00") != strings.Join(oaOrder, "\x00") || len(na) == 0 || minOld == 0 {
		return die("arena", "the counter recorded nothing, so this section would be vacuous")
	}
	var worse, wv []string
	for _, n := range naOrder {
		if na[n] >= oa[n] {
			worse = append(worse, n)
			wv = append(wv, fmt.Sprintf("%d/%d", na[n], oa[n]))
		}
	}
	if len(worse) > 0 {
		if len(worse) > 3 {
			worse, wv = worse[:3], wv[:3]
		}
		return die("arena", "%s ask the host for at least as much as the input did (%s), and one allocation of 1,040 bytes "+
			"where there were two of 32 and 4,096 must cost less in every session", strings.Join(worse, " "), strings.Join(wv, " "))
	}
	pn, fall := naOrder[0], naOrder[0]
	minRatio := 0.0
	for i, n := range naOrder {
		if na[n] > na[pn] {
			pn = n
		}
		r := float64(na[n]-oa[n]) / float64(oa[n])
		if i == 0 || float64(na[n])/float64(oa[n]) < float64(na[fall])/float64(oa[fall]) {
			fall = n
		}
		if i == 0 || r < minRatio {
			minRatio = r
		}
	}
	say("arena", "all %d memline sessions ask the host for LESS than the input: the heaviest, %s, asks %d bytes where it "+
		"asked %d, %+.1f%%, and the biggest fall is %s at %+.1f%%; nothing is freed, so that is a session's TRAFFIC and "+
		"not its live data", len(na), pn, na[pn], oa[pn], 100.0*float64(na[pn]-oa[pn])/float64(oa[pn]), fall, 100.0*minRatio)

	// --- 8. the controls -------------------------------------------------------------------
	type ctlT struct{ name, pat, lit string }
	const REW = "\x00"
	MUST := []ctlT{
		{"newdata_tag", `(?m)^(    dp->db_hdr\.bh_id = )(.*);$`, REW},
		{"newptr_tag", `(?m)^(    pp->pb_hdr\.bh_id = )(.*);$`, REW},
		{"leaftest", `(?m)^        if \(hp->bh_id ==  \(\(.d. << 8\) \+ .a.\) \)$`, REW},
		{"rootcount", `(?m)^                pp_new->pb_count = pp->pb_count;\n`, ""},
		{"rootcopy", `(?m)^ *musl_memmove\(\(char \*\)\(&pp_new->pb_pointer\[0\]\), \(char \*\)\(&pp->pb_pointer\[0\]\)[^\n]*\n`, ""},
		{"ptrcap", `if \(pp->pb_count < PB_COUNT_MAX\)`, REW},
		{"ptrsize", `(?m)^    pp =  \(PTR_BL \*\)alloc_clear\(sizeof\(PTR_BL\)\) ;$`, "    pp =  (PTR_BL *)alloc_clear(sizeof(DATA_BL)) ;"},
		{"datasize", `(?m)^    dp =  \(DATA_BL \*\)alloc_clear\(sizeof\(DATA_BL\)\) ;$`, "    dp =  (DATA_BL *)alloc_clear(sizeof(DATA_BL) / 2) ;"},
		{"leafcap", `(?m)^    if \(dp->db_line_count < DB_LINE_MAX\)$`, REW},
	}
	BLIND := []ctlT{
		{"fanout", `(?m)^enum \{ PB_COUNT_MAX = (\d+) \};$`, REW},
		{"noclear", `alloc_clear\(sizeof\(DATA_BL\)\)`, "alloc(sizeof(DATA_BL))"},
		{"nofree", `(?m)^    vim_free\(hp\);\n`, ""},
	}
	rewrite := func(name, s string) string {
		switch name {
		case "newdata_tag", "newptr_tag":
			return z45Tag.ReplaceAllString(s, "${1}(${2}) + 1;")
		case "leaftest":
			return strings.Replace(s, "==", "!=", 1)
		case "ptrcap", "leafcap":
			return strings.ReplaceAll(s, "<", "<=")
		case "fanout":
			return "enum { PB_COUNT_MAX = 511 };"
		}
		return s
	}
	var every, must []string
	for _, c := range MUST {
		must = append(must, c.name)
	}
	for _, c := range append(append([]ctlT{}, MUST...), BLIND...) {
		hs := regexp.MustCompile(c.pat).FindAllStringIndex(newT, -1)
		if len(hs) != 1 {
			say("controls", "a control could not be made from this phase's output:")
			prefixed(fmt.Sprintf("the %s control anchor matches %d lines, expected 1", c.name, len(hs)))
			return harness.ErrReported
		}
		h := hs[0]
		rp := c.lit
		if rp == REW {
			rp = rewrite(c.name, newT[h[0]:h[1]])
		}
		t := newT[:h[0]] + rp + newT[h[1]:]
		if t == newT {
			say("controls", "a control could not be made from this phase's output:")
			prefixed(fmt.Sprintf("the %s control changed nothing, so it would not be a control", c.name))
			return harness.ErrReported
		}
		if c.name == "leafcap" {
			t = strings.Replace(t, "if (dp->db_line_count >= DB_LINE_MAX && db_idx", "if (dp->db_line_count > DB_LINE_MAX && db_idx", 1)
		}
		if c.name == "fanout" {
			if loc := z45Assert.FindStringIndex(t); loc != nil {
				t = t[:loc[0]] + "static_assert(PB_COUNT_MAX == (8192 - 16)" + t[loc[1]:]
			}
		}
		d := filepath.Join(T("ctl"), c.name)
		os.MkdirAll(d, 0o755)
		os.WriteFile(filepath.Join(d, "zero-vim.c"), []byte(t), 0o644)
		os.WriteFile(filepath.Join(d, "Makefile"), []byte(mkfile), 0o644)
		every = append(every, c.name)
	}
	var wgC sync.WaitGroup
	cerr := make([]error, len(every))
	for i, c := range every {
		i, c := i, c
		wgC.Add(1)
		go func() { defer wgC.Done(); cerr[i] = exec.Command("make", "-C", filepath.Join(T("ctl"), c)).Run() }()
	}
	wgC.Wait()
	for _, e := range cerr {
		if e != nil {
			return die("controls", "a control did not build -- the break is wrong, not the corpus")
		}
	}
	mkdir("fan")
	if _, m := z45Instrument(filepath.Join(T("ctl"), "fanout", "zero-vim.c"), filepath.Join(T("fan"), "zero-vim.c"), true); m != "" {
		fmt.Fprintln(w, m)
		return harness.ErrReported
	}
	var fanErr error
	var wgF sync.WaitGroup
	wgF.Add(1)
	go func() { defer wgF.Done(); fanErr = exec.Command("make", "-C", T("fan")).Run() }()
	for _, c := range every {
		c := c
		wgC.Add(1)
		go func() {
			defer wgC.Done()
			bin := filepath.Join(T("ctl"), c, "zero-vim")
			exec.Command("sh", "tools/st.sh", "zcases", bin, filepath.Join(T("ctl"), c, "screen")).Run()
			exec.Command("sh", "tools/st.sh", "zmemline", bin, filepath.Join(T("ctl"), c, "memline")).Run()
		}()
	}
	wgF.Wait()
	if fanErr != nil {
		wgC.Wait()
		return die("controls", "the instrumented fanout control did not build")
	}
	exec.Command("sh", "tools/st.sh", "zmemline", filepath.Join(T("fan"), "zero-vim"), T("fan-mem")).Run()
	wgC.Wait()
	WHY := map[string]string{
		"fanout": "PB_COUNT_MAX = 511, which is what an 8-byte PTR_EN would give: THE FANOUT IS INVISIBLE TO A RECORDING, " +
			"and what it really costs is below",
		"noclear": "alloc() for alloc_clear(): the host's arena is a bump pointer over fresh pages, so the memory is already " +
			"zero -- which is a fact about this host and not a promise the core may rest on, and ml_open's error path does " +
			"rest on it",
		"nofree": "ml_free_tree() walking the tree and freeing NOTHING, so a closed buffer keeps every node it had: " +
			"ZERO-GOAL.md's charter says host_free() returns without doing anything, so what a core gives back is " +
			"unobservable by construction",
	}
	movedOf := func(base, cand string) (int, int, bool) {
		m, t := 0, 0
		for _, part := range []string{"screen", "memline"} {
			bdir, ndir := filepath.Join(base, part), filepath.Join(cand, part)
			if fi, e := os.Stat(ndir); e != nil || !fi.IsDir() {
				return 0, 0, false
			}
			for _, n := range listDir(bdir) {
				t++
				p := filepath.Join(ndir, n)
				if _, e := os.Stat(p); e != nil || !z30Same(filepath.Join(bdir, n), p) {
					m++
				}
			}
		}
		return m, t, true
	}
	type row struct {
		c            string
		moved, total int
	}
	var rows []row
	for _, c := range every {
		m, t, ok := movedOf(T("rec1"), filepath.Join(T("ctl"), c))
		if !ok {
			fmt.Fprintf(w, "the %s control recorded nothing at all\n", c)
			return harness.ErrReported
		}
		rows = append(rows, row{c, m, t})
	}
	var bad []string
	for _, r := range rows {
		if contains(must, r.c) && r.moved == 0 {
			bad = append(bad, r.c)
		}
	}
	if len(bad) > 0 {
		return die("controls", "%s moved no record at all, so this check would pass on a binary that had lost the thing "+
			"they break", strings.Join(bad, " "))
	}
	bad = nil
	for _, r := range rows {
		if !contains(must, r.c) && r.moved != 0 {
			bad = append(bad, r.c)
		}
	}
	if len(bad) > 0 {
		return die("controls", "%s moved a record, and each of those three is stated here as a thing the corpus CANNOT "+
			"see -- the measurement has changed and the reason written beside it is now wrong", strings.Join(bad, " "))
	}
	var mp []string
	for _, r := range rows {
		if contains(must, r.c) {
			mp = append(mp, fmt.Sprintf("%s %d/%d", r.c, r.moved, r.total))
		}
	}
	say("controls", "%d that must move a recording do: %s", len(must), strings.Join(mp, "  "))
	for _, r := range rows {
		if !contains(must, r.c) {
			say("blind", "%s 0/%d -- %s", r.c, r.total, WHY[r.c])
		}
	}
	hit := map[string]int{}
	for _, n := range listDir(T("fan-mem")) {
		t := harness.DecodeReplace([]byte(readFile(filepath.Join(T("fan-mem"), n))))
		for _, m := range mnew {
			if strings.Contains(t, m) {
				hit[m]++
			}
		}
	}
	var lost, hp []string
	for _, m := range mnew {
		if hit[m] == 0 {
			lost = append(lost, m)
		}
		hp = append(hp, fmt.Sprintf("%s %d", m, hit[m]))
	}
	if len(lost) == 0 {
		return die("fanout", "PB_COUNT_MAX = 511 still reaches every marker, so the fanout does NOT decide the corpus's "+
			"coverage and this phase's central claim is wrong")
	}
	say("fanout", "and what PB_COUNT_MAX = 511 costs, which no recording showed: %s -- %s go to 0.  391 data blocks is "+
		"more than 255 and less than 511, so an 8-byte PTR_EN would take the root split out of the corpus WITHOUT MOVING "+
		"ONE RECORD", strings.Join(hp, "  "), strings.Join(lost, " "))

	// --- 9. zero phase 44's prediction, measured --------------------------------------------
	mkdir("oldcap")
	nt := strings.Replace(oldT, "    if (dp->db_line_count < DB_LINE_MAX)", "    if (dp->db_line_count <= DB_LINE_MAX)", 1)
	nt = strings.Replace(nt, "if (dp->db_line_count >= DB_LINE_MAX && db_idx", "if (dp->db_line_count > DB_LINE_MAX && db_idx", 1)
	if nt == oldT {
		say("prediction", "phase 44's own control could not be made from this phase's input:")
		prefixed("the leaf capacity bound is not where zero phase 44 left it")
		return harness.ErrReported
	}
	os.WriteFile(filepath.Join(T("oldcap"), "zero-vim.c"), []byte(nt), 0o644)
	if exec.Command("make", "-C", T("oldcap")).Run() != nil {
		return die("prediction", "phase 44's control did not build on the input")
	}
	ocb := filepath.Join(T("oldcap"), "zero-vim")
	exec.Command("sh", "tools/st.sh", "zcases", ocb, filepath.Join(T("oldcap"), "screen")).Run()
	exec.Command("sh", "tools/st.sh", "zmemline", ocb, filepath.Join(T("oldcap"), "memline")).Run()
	oi, ti, ok := movedOf(T("rec0"), T("oldcap"))
	if !ok {
		return die("prediction", "%s recorded nothing at all", T("oldcap"))
	}
	oo, to, ok := movedOf(T("rec1"), filepath.Join(T("ctl"), "leafcap"))
	if !ok {
		return die("prediction", "%s recorded nothing at all", filepath.Join(T("ctl"), "leafcap"))
	}
	if oi != 0 {
		return die("prediction", "the leaf capacity bound widened by one moves %d of %d records on the INPUT, where zero "+
			"phase 44 measured 0 -- so the comparison below is not the one that phase set up", oi, ti)
	}
	if oo == 0 {
		return die("prediction", "the leaf capacity bound widened by one still moves nothing, so allocating a block at "+
			"its own size did NOT make the off-by-one visible and zero phase 44's prediction is unmet")
	}
	say("prediction", "zero phase 44 wrote that allocating a block at its own size would make an off-by-one in the "+
		"capacity bound VISIBLE.  Its own control, the leaf capacity test widened by one, moves %d of %d records on this "+
		"phase's INPUT -- the 0 of 118 that phase recorded -- and %d of %d here.  A leaf is 1,040 bytes of its own "+
		"allocation now and was 1,040 bytes of a 4,096-byte page", oi, ti, oo, to)

	// --- 10. the symbols, the cut, and the ordinary checks ------------------------------------
	for _, x := range [][2]string{{f, "new.o"}, {oldC, "old.o"}} {
		if exec.Command("gcc", "-c", "-O0", "-fno-stack-protector", "-o", T(x[1]), x[0]).Run() != nil {
			return harness.ErrReported
		}
	}
	uNew := nmField26(T("new.o"), []string{"-u"}, 1)
	uOld := nmField26(T("old.o"), []string{"-u"}, 1)
	if g, c := comm23(uOld, uNew), comm23(uNew, uOld); len(g)+len(c) > 0 {
		say("symbols", "this phase frees no libc symbol and needs none, and the set moved:")
		for _, n := range g {
			fmt.Fprintf(w, "               %s\n", n)
		}
		for _, n := range c {
			fmt.Fprintf(w, "               \t%s\n", n)
		}
		return harness.ErrReported
	}
	say("symbols", "%d undefined names, the input's set exactly, a comm empty both ways: a node allocated at its own size "+
		"asks the host for nothing the editor did not already ask it for", len(uNew))
	if cutLines < 70000 {
		return die("cut", "the core is %d lines, so the cut found the wrong line", cutLines)
	}
	for _, l := range strings.Split(readFile(T("cut.c")), "\n") {
		if z30Dir.MatchString(l) {
			return die("cut", "the core holds a directive")
		}
	}
	gw := func(cut string) (string, error) {
		c := exec.Command("gcc", "-fsyntax-only", "-Wall", "-Wextra", "-Wno-unused-parameter", cut)
		var eb strings.Builder
		c.Stderr = &eb
		err := c.Run()
		return eb.String(), err
	}
	wn, err := gw(T("cut.c"))
	if err != nil {
		return die("cut", "the core does not parse on its own")
	}
	wo, _ := gw(T("cut.old.c"))
	ifc := func(s string) []string {
		set := map[string]bool{}
		for _, m := range z44IfaceGrp.FindAllString(s, -1) {
			set[m] = true
		}
		return z27Keys(set)
	}
	ifOld, ifNew := ifc(wo), ifc(wn)
	if strings.Join(ifOld, "\n") != strings.Join(ifNew, "\n") {
		say("cut", "the core -> host interface moved, and this phase adds no host call:")
		os.WriteFile(T("if.old"), []byte(strings.Join(ifOld, "\n")+"\n"), 0o644)
		os.WriteFile(T("if.new"), []byte(strings.Join(ifNew, "\n")+"\n"), 0o644)
		for _, l := range z30Diff(T("if.old"), T("if.new")) {
			fmt.Fprintf(w, "               %s\n", l)
		}
		return harness.ErrReported
	}
	say("cut", "the core is %d lines and was %d, 0 directives, 0 errors, and the interface is the input's %d names unchanged",
		cutLines, cutOld, len(ifNew))
	nb2, _ := os.ReadFile(f)
	say("source", "%s -> %d lines; the binary is %d bytes against the input's %d", beforeRaw, countLines(nb2),
		sizeOf(newBin), sizeOf(oldBin))
	zh := exec.Command("sh", "tools/st.sh", "zhostonly", f)
	zh.Stdout, zh.Stderr = w, w
	if err := zh.Run(); err != nil {
		return harness.ErrReported
	}
	pc := exec.Command("sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols"))
	pc.Stdout, pc.Stderr = w, w
	if err := pc.Run(); err != nil {
		return harness.ErrReported
	}
	return nil
}
