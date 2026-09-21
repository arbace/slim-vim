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

func init() { register("zero44", Zero44) }

const z44Bit = "((unsigned)1 << ((sizeof(unsigned) * 8) - 1))"

var (
	z44Ptr      = regexp.MustCompile(`\(char_u? \*\)dp[a-z_]* *\+`)
	z44FnHead   = regexp.MustCompile(`(?m)^([a-zA-Z_][a-zA-Z0-9_]*)\(`)
	z44DlText   = regexp.MustCompile(`\.dl_text\s*=[^=]`)
	z44Flush    = regexp.MustCompile(`(?ms)^ml_flush_line\(buf_T \*buf\)\n\{.*?^\}$`)
	z44FreeDb   = regexp.MustCompile(`free\([^)]*db_line`)
	z44Low      = regexp.MustCompile(`(?m)^    low = 1;$`)
	z44ZA       = regexp.MustCompile(`ZA=(\d+)`)
	z44IfaceGrp = regexp.MustCompile(`'[a-zA-Z_][a-zA-Z0-9_]*' used but never defined`)
)

type z44Mark struct{ name, pat, where, cond string }

// z44Instrument is MARK_PY: five (on the input six) once-per-process markers
// through host_message(), and the depth counter they need.
func z44Instrument(src, dst string, out bool) (string, string) {
	marks := []z44Mark{}
	if out {
		marks = append(marks, z44Mark{"MLSPLITDATA", `(?m)^        if \(\(hp_new = ml_new_data\(mfp[^\n]*$`, "before", ""})
	} else {
		marks = append(marks, z44Mark{"MLSPLITDATA", `(?m)^        page_count = \(\(space_needed \+ [^\n]*$`, "before", ""})
	}
	marks = append(marks,
		z44Mark{"MLSPLITPTR", `(?m)^                hp_new = ml_new_ptr\(mfp\);$`, "before", ""},
		z44Mark{"MLSPLITROOT", `(?m)^ *musl_memmove\(\(char \*\)\(pp_new\), [^\n]*$`, "before", ""},
		z44Mark{"MLIDXNZ", `(?m)^                ip->ip_index = idx;$`, "after", "idx > 0"},
		z44Mark{"MLDEEP", `(?m)^        if \(\(top = ml_add_stack\(buf\)\) < 0\)$`, "before", "++zprobe_lvl >= 2"},
	)
	if !out {
		marks = append(marks, z44Mark{"MLBIGLINE", `(?m)^        page_count = \(\(space_needed \+ [^\n]*$`, "after", "page_count > 1"})
	}
	t := readFile(src)
	if n := len(z44Low.FindAllStringIndex(t, -1)); n != 1 {
		return "", fmt.Sprintf("the probe cannot declare its depth counter: the file has %d `low = 1;`, "+
			"and the descent in ml_find_line has to start somewhere this can name", n)
	}
	loc := z44Low.FindStringIndex(t)
	t = t[:loc[0]] + "    int zprobe_lvl = 0;\n    low = 1;" + t[loc[1]:]
	var names []string
	for _, m := range marks {
		re := regexp.MustCompile(m.pat)
		hits := re.FindAllStringIndex(t, -1)
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

// Zero44 is phase 44's check: de-page the leaf.
func Zero44(w io.Writer, args []string) error {
	if len(args) != 2 {
		return fmt.Errorf("usage: check zero44 <work-dir> <state-dir>")
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
	tmp, err := os.MkdirTemp("", "zero44-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	T := func(n string) string { return filepath.Join(tmp, n) }
	_ = exec.Command("make", "-C", work, "clean").Run()
	newBin := filepath.Join(work, "zero-vim")
	if _, e := os.Stat(newBin); e == nil {
		return die("build", "the clean did not remove zero-vim, so nothing below would be a recording of this phase")
	}
	if err := exec.Command("make", "-C", work).Run(); err != nil {
		return die("build", "FAILED -- rerun by hand: make -C %s", work)
	}
	oldBin := filepath.Join(state, "old")

	// --- 2, 3 and 4: the source -----------------------------------------------------
	newT, oldT := readFile(f), readFile(oldC)
	type gl struct{ name, n string }
	var gone []gl
	for _, l := range strings.Split(readFile(filepath.Join(state, "gone")), "\n") {
		if strings.TrimSpace(l) == "" {
			continue
		}
		l = strings.TrimRight(l, "\n")
		i := strings.LastIndex(l, "\t")
		if i < 0 {
			gone = append(gone, gl{l, ""})
			continue
		}
		gone = append(gone, gl{l[:i], l[i+1:]})
	}
	dbmax, _ := strconv.Atoi(strings.TrimSpace(readFile(filepath.Join(state, "dbmax"))))
	wc := func(t, n string) int {
		return len(regexp.MustCompile(`\b` + regexp.QuoteMeta(n) + `\b`).FindAllStringIndex(t, -1))
	}
	for _, g := range gone {
		n, _ := strconv.Atoi(g.n)
		here := wc(oldT, g.name)
		if g.name == z44Bit {
			here = strings.Count(oldT, z44Bit)
		}
		if here != n {
			return die("partition", "the edit recorded %s at %d mentions of the input and it has %d", g.name, n, here)
		}
		there := wc(newT, g.name)
		if g.name == z44Bit {
			there = strings.Count(newT, z44Bit)
		}
		if there != 0 {
			return die("partition", "%s survives into the output", g.name)
		}
	}
	if strings.Contains(newT, "offsetof(DATA_BL") {
		return die("partition", "a data block is still measured with offsetof")
	}
	if strings.Count(oldT, "offsetof(DATA_BL") != 2 {
		return die("partition", "the input does not measure a data block with offsetof twice")
	}
	if strings.Count(newT, "offsetof(PTR_BL") != 1 || strings.Count(oldT, "offsetof(PTR_BL") != 1 {
		return die("partition", "ml_new_ptr's offsetof moved, and a POINTER block is still a page and is not this phase's")
	}
	ptrIn := len(z44Ptr.FindAllStringIndex(strings.ReplaceAll(oldT, "(char *)dp", "(char_u *)dp"), -1))
	ptrOut := len(z44Ptr.FindAllStringIndex(strings.ReplaceAll(newT, "(char *)dp", "(char_u *)dp"), -1))
	if ptrIn == 0 || ptrOut != 0 {
		return die("partition", "interior pointers into a data block: %d in the input, %d in the output, and this phase leaves none", ptrIn, ptrOut)
	}
	var gp []string
	for _, g := range gone {
		name := g.name
		if name == z44Bit {
			name = "the top bit"
		}
		gp = append(gp, fmt.Sprintf("%s %s -> 0", name, g.n))
	}
	say("partition", "%s all 0 in the output; %d interior pointers of the shape `(char_u *)dp + start` in the input and 0 "+
		"here; offsetof(DATA_BL) 2 -> 0 and offsetof(PTR_BL) 1 -> 1", strings.Join(gp, ", "), ptrIn)
	if wc(oldT, "ML_DEL_NOPROP") != 2 || wc(newT, "ML_DEL_NOPROP") != 0 {
		return die("division", "ML_DEL_NOPROP is %d in the input and %d in the output, and this phase leaves it for the "+
			"sweep to take from 2 to 0", wc(oldT, "ML_DEL_NOPROP"), wc(newT, "ML_DEL_NOPROP"))
	}
	say("division", "the edit takes ML_APPEND_MARK, which no sweep can see -- three arms of a flag whose one caller was "+
		"ml_flush_line()'s fallback -- and leaves ML_DEL_NOPROP, 2 -> 0, which is the whole of what the sweep finds")
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
	rec, e := structOf("data_line")
	if e != nil {
		return e
	}
	blk, e := structOf("data_block")
	if e != nil {
		return e
	}
	last := func(xs []string) string {
		var o []string
		for _, x := range xs {
			fs := strings.Fields(x)
			o = append(o, fs[len(fs)-1])
		}
		return strings.Join(o, " ")
	}
	if last(rec) != "*dl_text; dl_len; dl_marked;" {
		return die("record", "struct data_line is not the three members this phase writes: %s", strings.Join(rec, " "))
	}
	if last(blk) != "db_id; db_line_count; db_line[DB_LINE_MAX];" {
		return die("record", "struct data_block is not a header and an array of records: %s", strings.Join(blk, " "))
	}
	if n := wc(newT, "DB_LINE_MAX"); n < 3 {
		return die("record", "DB_LINE_MAX is named %d times and the capacity is read in at least three places", n)
	}
	if !strings.Contains(newT, "static_assert(sizeof(DATA_BL) <= MEMFILE_PAGE_SIZE") {
		return die("record", "nothing asserts that a leaf still fits the page memfile hands it")
	}
	say("record", "a leaf is `{%s}` x %d with a two-member header, and the compiler is what says it fits a page",
		strings.Join(rec, " "), dbmax)
	enclosing := func(i int) string {
		j := strings.LastIndex(newT[:i], "\n}\n")
		seg := newT[:i]
		if j > 0 {
			seg = newT[j:i]
		}
		if m := z44FnHead.FindStringSubmatch(seg); m != nil {
			return m[1]
		}
		return "<file scope>"
	}
	writes := map[string]int{}
	for _, m := range z44DlText.FindAllStringIndex(newT, -1) {
		writes[enclosing(m[0])]++
	}
	want := map[string]int{"ml_open": 1, "ml_append_int": 3, "ml_flush_line": 1}
	same := len(writes) == len(want)
	for k, v := range want {
		if writes[k] != v {
			same = false
		}
	}
	if !same {
		pyd := func(m map[string]int) string {
			var ks []string
			for k := range m {
				ks = append(ks, k)
			}
			sort.Strings(ks)
			var p []string
			for _, k := range ks {
				p = append(p, fmt.Sprintf("'%s': %d", k, m[k]))
			}
			return "{" + strings.Join(p, ", ") + "}"
		}
		return die("lifetime", "a record's text is written in %s and the rule this phase pins says %s", pyd(writes), pyd(want))
	}
	fm := z44Flush.FindString(newT)
	if fm == "" {
		return die("lifetime", "ml_flush_line is not in the output to be read")
	}
	if strings.Contains(fm, "vim_free") && !strings.Contains(fm, "ML_ALLOCATED") {
		return die("lifetime", "ml_flush_line frees something and it is not the ML_ALLOCATED arm")
	}
	if strings.Contains(fm, "vim_free(new_line)") {
		return die("lifetime", "ml_flush_line still frees the replacement it just stored, so the record and b_ml would both own it")
	}
	if z44FreeDb.MatchString(newT) {
		return die("lifetime", "the output frees a record's text, so a pointer ml_get() returned does not outlive its line")
	}
	say("lifetime", "a record's text is written in exactly %d places -- %s -- and freed in none, so A POINTER ml_get() "+
		"RETURNED IS VALID FOR THE LIFETIME OF THE PROCESS, where before it was invalidated by any insert, delete, "+
		"flush or split in the same block", 5, "ml_append_int x3, ml_flush_line x1, ml_open x1")
	if !strings.Contains(newT, "ML_LINE_DIRTY") || wc(newT, "ml_line_alloced") != wc(oldT, "ml_line_alloced") {
		return die("pending", "ml_line_alloced() moved: it still has to mean \"a replacement for this line is pending\" "+
			"and not \"this line's text is allocated\"")
	}
	say("pending", "ml_line_alloced() and ML_LINE_DIRTY are untouched: del_bytes() shortens ml_line_len in place under "+
		"them and nothing would write that length back")

	// --- 5. two full recordings, and they are the input's ---------------------------
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
	countDir := func(d string) int { e, _ := os.ReadDir(d); return len(e) }
	say("record", "%d screen cases, %d memline cases and four tables, byte for byte the input's, twice",
		countDir(filepath.Join(T("rec1"), "screen")), countDir(filepath.Join(T("rec1"), "memline")))

	// --- 6. the corpus reaches the tree -----------------------------------------------
	for _, d := range []string{"pnew", "pold"} {
		os.MkdirAll(T(d), 0o755)
		os.WriteFile(filepath.Join(T(d), "Makefile"), []byte(readFile(filepath.Join(work, "Makefile"))), 0o644)
	}
	marksNew, msg := z44Instrument(f, filepath.Join(T("pnew"), "zero-vim.c"), true)
	if msg != "" {
		say("probe", "the instrument could not be built from this phase's output:")
		prefixed(msg)
		return harness.ErrReported
	}
	marksOld, msg := z44Instrument(oldC, filepath.Join(T("pold"), "zero-vim.c"), false)
	if msg != "" {
		say("probe", "the instrument could not be built from this phase's input:")
		prefixed(msg)
		return harness.ErrReported
	}
	buildPair := func(a, b, whatA, whatB, tag string) error {
		var wg sync.WaitGroup
		var ea, eb error
		wg.Add(2)
		go func() { defer wg.Done(); ea = exec.Command("make", "-C", T(a)).Run() }()
		go func() { defer wg.Done(); eb = exec.Command("make", "-C", T(b)).Run() }()
		wg.Wait()
		if ea != nil {
			return die(tag, "%s", whatA)
		}
		if eb != nil {
			return die(tag, "%s", whatB)
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
		// Collected by bare `wait`s, as the shell does: a corpus that fails
		// ends the check with nothing printed.
		return harness.ErrReported
	}
	hits := func(d string, marks []string) map[string]int {
		out := map[string]int{}
		for _, m := range marks {
			out[m] = 0
		}
		es, _ := os.ReadDir(d)
		for _, en := range es {
			t := harness.DecodeReplace([]byte(readFile(filepath.Join(d, en.Name()))))
			for _, m := range marks {
				if strings.Contains(t, m) {
					out[m]++
				}
			}
		}
		return out
	}
	mnew, mold := strings.Fields(marksNew), strings.Fields(marksOld)
	nh, oh, sh := hits(T("pnew-mem"), mnew), hits(T("pold-mem"), mold), hits(T("pnew-scr"), mnew)
	var zero []string
	for _, k := range mnew {
		if nh[k] == 0 {
			zero = append(zero, k)
		}
	}
	if len(zero) > 0 {
		fmt.Fprintf(w, "the corpus reaches none of: %s -- a corpus that MEANS to reach a split and does not is the "+
			"defect zero phase 40 exists to end\n", strings.Join(zero, " "))
		return harness.ErrReported
	}
	var low, ln, lo []string
	for _, k := range mnew {
		if nh[k] < oh[k] {
			low = append(low, k)
			ln = append(ln, strconv.Itoa(nh[k]))
			lo = append(lo, strconv.Itoa(oh[k]))
		}
	}
	if len(low) > 0 {
		fmt.Fprintf(w, "the output reaches %s less often than the input did (%s against %s), so this phase narrowed "+
			"the instrument it depends on\n", strings.Join(low, " "), strings.Join(ln, " "), strings.Join(lo, " "))
		return harness.ErrReported
	}
	var scr []string
	for _, k := range mnew {
		if sh[k] > 0 {
			scr = append(scr, k)
		}
	}
	if len(scr) > 0 {
		fmt.Fprintf(w, "%s is reached by the 102 screen cases, so the memline corpus is not what makes the text layer "+
			"visible on this boundary\n", strings.Join(scr, " "))
		return harness.ErrReported
	}
	if v, ok := oh["MLBIGLINE"]; !ok || v == 0 {
		fmt.Fprintf(w, "the input never made a data block more than one page, so the path this phase removes was not "+
			"there to remove\n")
		return harness.ErrReported
	}
	var pn, po []string
	for _, k := range mnew {
		pn = append(pn, fmt.Sprintf("%s %d", k, nh[k]))
		po = append(po, fmt.Sprintf("%s %d", k, oh[k]))
	}
	say("probe", "%s  (the input: %s) and 0 of the 102 screen cases reach any of them; MLBIGLINE, a data block of "+
		"more than one page, was %d of 16 on the input and HAS NO ANCHOR HERE -- a record is a pointer, so the path "+
		"is gone", strings.Join(pn, "  "), strings.Join(po, "  "), oh["MLBIGLINE"])

	// --- 7. what a record representation costs the arena ---------------------------------
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
				pat := strings.TrimPrefix(x[0], "(?m)")
				return fmt.Sprintf("the arena counter anchor %s is in the source %d times, expected 1", pyRepr26(pat), len(hs))
			}
			t = t[:hs[0][0]] + x[1] + t[hs[0][1]:]
		}
		os.WriteFile(dst, []byte(t), 0o644)
		return ""
	}
	for _, d := range []string{"anew", "aold"} {
		os.MkdirAll(T(d), 0o755)
		os.WriteFile(filepath.Join(T(d), "Makefile"), []byte(readFile(filepath.Join(work, "Makefile"))), 0o644)
	}
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
	peak := func(d string) (int64, string) {
		var best int64
		who := ""
		es, _ := os.ReadDir(d)
		var ns []string
		for _, en := range es {
			ns = append(ns, en.Name())
		}
		sort.Strings(ns)
		for _, n := range ns {
			for _, m := range z44ZA.FindAllStringSubmatch(readFile(filepath.Join(d, n)), -1) {
				v, _ := strconv.ParseInt(m[1], 10, 64)
				if v > best {
					best, who = v, n
				}
			}
		}
		return best, who
	}
	nb, nwho := peak(T("anew-mem"))
	ob, owho := peak(T("aold-mem"))
	if ob == 0 || nb == 0 {
		return die("arena", "the counter recorded nothing, so this section would be vacuous")
	}
	if nb*4 > ob*5 {
		return die("arena", "the heaviest session asks for %d bytes where the input asked %d, a quarter as much again: a "+
			"per-line allocation is meant to cost the arena about what the page arena cost it", nb, ob)
	}
	who := nwho
	if nwho != owho {
		who = nwho + " and " + owho
	}
	say("arena", "the heaviest memline session asks the host for %d bytes where the input asked %d, %+.1f%% (%s either "+
		"side); nothing is freed, so that is TRAFFIC and not live data, and it is the one cost of this phase no "+
		"recording can see", nb, ob, 100.0*float64(nb-ob)/float64(ob), who)

	// --- 8. the controls ---------------------------------------------------------------
	type ctlT struct{ name, pat, lit string }
	MUST := []ctlT{
		{"copy", `(?m)^    text = alloc\(\(usize\)len\);$`, "    text = line;"},
		{"len", `(?m)^            dp->db_line\[idx\]\.dl_len = buf->b_ml\.ml_line_len;$`, ""},
		{"mark", `(?m)\.dl_marked = TRUE;$`, "\x00"},
		{"shift", `\(usize\)\(count - idx - 1\) \* sizeof\(DATA_LN\)`, "\x00"},
		{"ins", `&dp->db_line\[db_idx \+ 2\]\), \(char \*\)\(&dp->db_line\[db_idx \+ 1\]\)`, "\x00"},
		{"split", `\(usize\)\(lines_moved\) \* sizeof\(DATA_LN\)`, "\x00"},
		{"idx", `(?m)^        buf->b_ml\.ml_line_ptr = dp->db_line\[idx\]\.dl_text;$`, "\x00"},
		{"getlen", `(?m)^        buf->b_ml\.ml_line_len = dp->db_line\[idx\]\.dl_len;$`, "\x00"},
	}
	BLIND := []ctlT{
		{"poison", `(?m)^            dp->db_line\[idx\]\.dl_text = new_line;$`, "\x00"},
		{"cap", `(?m)^    if \(dp->db_line_count < DB_LINE_MAX\)$`, "\x00"},
		{"dbmax", `(?m)^enum \{ DB_LINE_MAX = \d+ \};$`, "enum { DB_LINE_MAX = 1 };"},
	}
	rewrite := func(name, s string) string {
		switch name {
		case "mark":
			return strings.ReplaceAll(s, "TRUE", "FALSE")
		case "shift":
			return strings.ReplaceAll(s, "- 1)", "- 2)")
		case "ins":
			return "&dp->db_line[db_idx + 1]), (char *)(&dp->db_line[db_idx + 2])"
		case "split":
			return strings.ReplaceAll(s, "(lines_moved)", "(lines_moved - 1)")
		case "idx":
			return strings.ReplaceAll(s, "[idx]", "[0]")
		case "getlen":
			return strings.TrimRight(s, ";") + " - 1;"
		case "poison":
			return "            (void) musl_memset((char *)(dp->db_line[idx].dl_text), (0x5a), ((usize)dp->db_line[idx].dl_len)) ;\n" + s
		case "cap":
			return strings.ReplaceAll(s, "<", "<=")
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
		if rp == "\x00" {
			rp = rewrite(c.name, newT[h[0]:h[1]])
		}
		t := newT[:h[0]] + rp + newT[h[1]:]
		if t == newT {
			say("controls", "a control could not be made from this phase's output:")
			prefixed(fmt.Sprintf("the %s control changed nothing, so it would not be a control", c.name))
			return harness.ErrReported
		}
		d := filepath.Join(T("ctl"), c.name)
		os.MkdirAll(d, 0o755)
		os.WriteFile(filepath.Join(d, "zero-vim.c"), []byte(t), 0o644)
		every = append(every, c.name)
	}
	cp := filepath.Join(T("ctl"), "cap", "zero-vim.c")
	os.WriteFile(cp, []byte(strings.Replace(readFile(cp), "if (dp->db_line_count >= DB_LINE_MAX && db_idx",
		"if (dp->db_line_count > DB_LINE_MAX && db_idx", 1)), 0o644)
	var wgC sync.WaitGroup
	cerr := make([]error, len(every))
	for i, c := range every {
		i, c := i, c
		os.WriteFile(filepath.Join(T("ctl"), c, "Makefile"), []byte(readFile(filepath.Join(work, "Makefile"))), 0o644)
		wgC.Add(1)
		go func() { defer wgC.Done(); cerr[i] = exec.Command("make", "-C", filepath.Join(T("ctl"), c)).Run() }()
	}
	wgC.Wait()
	for _, e := range cerr {
		if e != nil {
			return die("controls", "a control did not build -- the break is wrong, not the corpus")
		}
	}
	// Each control's two recorders keep their output, so that a recording that
	// died is told apart from a record that moved (recjob.go).
	ctlJobs := map[string][]*recJob{}
	for _, c := range every {
		c := c
		bin := filepath.Join(T("ctl"), c, "zero-vim")
		js := []*recJob{
			newRec("the "+c+" control's screen recording", "sh", "tools/st.sh", "zcases", bin, filepath.Join(T("ctl"), c, "screen")),
			newRec("the "+c+" control's memline recording", "sh", "tools/st.sh", "zmemline", bin, filepath.Join(T("ctl"), c, "memline")),
		}
		ctlJobs[c] = js
		wgC.Add(1)
		go func() {
			defer wgC.Done()
			js[0].run()
			js[1].run()
		}()
	}
	wgC.Wait()
	// A RECORDING THAT DIED IS NOT A RECORD THAT MOVED.  A record the baseline
	// holds and a control does not is what a recorder that died leaves, and the
	// count below would take it for a move -- which reads "poison moved a
	// record" off a busy machine, and passes a must-move control for nothing.
	for _, c := range every {
		for _, part := range []string{"screen", "memline"} {
			if miss := missingRecords(filepath.Join(T("rec1"), part), filepath.Join(T("ctl"), c, part)); len(miss) > 0 {
				fmt.Fprintf(w, "  %-12s the %s control's %s recording is missing %d records (%s), and counted they would be MOVED:\n",
					"record", c, part, len(miss), strings.Join(head(miss, 3), " "))
				if !recRefuse(w, ctlJobs[c]...) {
					fmt.Fprintf(w, "               its recorders both exited 0, so the records were removed after they were written\n")
				}
				return harness.ErrReported
			}
		}
	}
	WHY := map[string]string{
		"poison": "the text a record stops owning, overwritten the moment it is replaced: 0 of 118 is the lifetime rule " +
			"measured, nothing reads a replaced line through a pointer it kept",
		"cap": "the capacity bound off by one: a leaf is 1,040 bytes of a 4,096-byte page, so the 65th record lands in " +
			"the page's spare room and nothing notices -- the bound is soft until a block is allocated at its own size",
		"dbmax": "DB_LINE_MAX = 1, a leaf per line: the fanout is invisible to the corpus in both directions, which is " +
			"why the value is chosen by REACHABILITY and not by a recording",
	}
	type row struct {
		c            string
		moved, total int
	}
	var rows []row
	for _, c := range every {
		moved, total := 0, 0
		for _, part := range []string{"screen", "memline"} {
			bdir, ndir := filepath.Join(T("rec1"), part), filepath.Join(T("ctl"), c, part)
			if fi, e := os.Stat(ndir); e != nil || !fi.IsDir() {
				fmt.Fprintf(w, "the %s control recorded nothing at all\n", c)
				return harness.ErrReported
			}
			es, _ := os.ReadDir(bdir)
			var ns []string
			for _, en := range es {
				ns = append(ns, en.Name())
			}
			sort.Strings(ns)
			for _, n := range ns {
				total++
				p := filepath.Join(ndir, n)
				if _, e := os.Stat(p); e != nil || !z30Same(filepath.Join(bdir, n), p) {
					moved++
				}
			}
		}
		rows = append(rows, row{c, moved, total})
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
		// A blind control that moved because its recorder stalled has moved on the
		// machine and not in the editor; say so beside the verdict.
		for _, c := range bad {
			for _, j := range ctlJobs[c] {
				if j.failed() {
					j.tell(w)
				}
			}
		}
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

	// --- 9. the symbols, the cut, and the ordinary checks -------------------------------
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
	say("symbols", "%d undefined names, the input's set exactly, a comm empty both ways: a per-line allocation asks the "+
		"host for nothing the editor did not already ask it for", len(uNew))
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
