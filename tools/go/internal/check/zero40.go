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

func init() { register("zero40", Zero40) }

type z40Mark struct{ name, anchor, where, cond, extra string }

const z40Page = "        page_count = ((space_needed +  (__builtin_offsetof(DATA_BL, db_index)) ) + page_size - 1) / page_size;\n"

var z40Marks = []z40Mark{
	{"MLSPLITDATA", z40Page, "before", "", ""},
	{"MLBIGLINE", z40Page, "after", "page_count > 1", ""},
	{"MLSPLITPTR", "                hp_new = ml_new_ptr(mfp);\n", "before", "", "        ++zprobe_ptr;\n"},
	{"MLSIBSPLIT", "                if (hp-> bh_hashitem.mhi_key  != 1)\n                {\n                    break;\n                }\n", "before", "zprobe_ptr == 1", ""},
	{"MLSPLITROOT", "                 musl_memmove((char *)(pp_new), (char *)(pp), (usize)page_size) ;\n", "before", "", ""},
	{"MLIDXNZ", "                ip->ip_index = idx;\n", "after", "idx > 0", ""},
	{"MLDEEP", "        if ((top = ml_add_stack(buf)) < 0)\n", "before", "++zprobe_lvl >= 2", ""},
}

var z40Decls = [][2]string{
	{"    bnum = 1;\n", "    int zprobe_lvl = 0;\n"},
	{"            if (pp->pb_count < pp->pb_count_max)\n", "            int zprobe_ptr = 0;\n"},
}

// z40Probe is MARK_PY: seven once-per-process host_message() markers.
func z40Probe(t string) (string, []string, error) {
	for _, d := range z40Decls {
		if n := strings.Count(t, d[0]); n != 1 {
			return "", nil, fmt.Errorf("the probe anchor %s is in the source %d times, expected 1", pyRepr(strings.TrimSpace(d[0])), n)
		}
		t = strings.Replace(t, d[0], d[1]+d[0], 1)
	}
	var names []string
	for _, m := range z40Marks {
		if n := strings.Count(t, m.anchor); n != 1 {
			return "", nil, fmt.Errorf("the probe anchor for %s is in the source %d times, expected 1", m.name, n)
		}
		body := fmt.Sprintf("{ static int z_%s = 0; if (!z_%s) { z_%s = 1; host_message(\"%s\\n\", -1, TRUE); } }\n", m.name, m.name, m.name, m.name)
		ins := m.extra + "        " + body
		if m.cond != "" {
			ins = m.extra + fmt.Sprintf("        if (%s) %s", m.cond, body)
		}
		if m.where == "before" {
			t = strings.Replace(t, m.anchor, ins+m.anchor, 1)
		} else {
			t = strings.Replace(t, m.anchor, m.anchor+ins, 1)
		}
		names = append(names, m.name)
	}
	return t, names, nil
}

var z40Ctl = map[string][][2]string{
	"descent": {{"            pp->pb_pointer[idx].pe_line_count--;\n", ""}},
	"lineadd": {{"        pp->pb_pointer[ip->ip_index].pe_line_count += count;\n", ""}},
	"cache": {{"            if (ip->ip_low <= lnum && ip->ip_high >= lnum)\n",
		"            if (ip->ip_low <= lnum && ip->ip_high + 1 >= lnum)\n"}},
	"reshape": {{"    pp->pb_count_max =  (short_u)(((mfp)->mf_page_size - __builtin_offsetof(PTR_BL, pb_pointer)) / sizeof(PTR_EN)) ;\n",
		"    pp->pb_count_max =  (short_u)(((mfp)->mf_page_size - __builtin_offsetof(PTR_BL, pb_pointer)) / sizeof(PTR_EN) / 4) ;\n"}},
	"clock": {
		{"host_time(void)\n{\n    return time(nullptr);\n}\n",
			"host_time(void)\n{\n    static long z_t = 2000000000L;\n    z_t += 7;\n    return z_t;\n}\n"},
		{"musl_now_ms(void)\n{\n    struct timeval tv;\n",
			"musl_now_ms(void)\n{\n    static long z_ms = 0;\n    z_ms += 997;\n    return z_ms;\n    struct timeval tv;\n"},
	},
}

// prefixed is `sed 's/^/PREFIX/'` over a heredoc's whole output.
func prefixed(w io.Writer, prefix, text string) {
	for _, l := range strings.Split(strings.TrimRight(text, "\n"), "\n") {
		fmt.Fprintln(w, prefix+l)
	}
}

// Zero40 is zero phase 40, whole: the instrument could not see the text layer.
func Zero40(w io.Writer, args []string) error {
	if len(args) < 1 {
		return fmt.Errorf("usage: check zero40 <work-dir>")
	}
	work := args[0]
	f := filepath.Join(work, "zero-vim.c")
	base := ".reference/zero-baselines"
	tmp, err := os.MkdirTemp("", "zero40")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	T := func(n ...string) string { return filepath.Join(append([]string{tmp}, n...)...) }

	// --- 0. the baselines must already hold the new part ------------------
	if fi, e := os.Stat(base); e == nil && fi.IsDir() {
		if _, e := os.Stat(base + "/memline"); e != nil {
			b := &rep{tag: "baselines", w: w}
			b.say("%s has no memline/ -- it is the recording of five parts", base)
			b.cont("and a recording is six now (tools/zrecord.sh).  Zero phase 0")
			b.cont("records them, from whim-vim.c -- the pipeline's immutable")
			b.cont("input -- and REFUSES to overwrite a set that differs, so")
			b.cont("BOTH paths have to go:")
			fmt.Fprintln(w, "                 rm -rf .reference/zero-baselines .cache/r0 && make zero-phase-0")
			return harness.ErrReported
		}
	}

	// --- 1. the tree is untouched -----------------------------------------
	before := sha256File(f)

	// --- 2. the build ------------------------------------------------------
	_ = exec.Command("make", "-C", work, "clean").Run()
	if err := exec.Command("make", "-C", work).Run(); err != nil {
		(&rep{tag: "build", w: w}).say("FAILED -- rerun by hand: make -C %s", work)
		return harness.ErrReported
	}
	bin := filepath.Join(work, "zero-vim")
	if !staticFacts(w, bin) {
		return harness.ErrReported
	}
	if exec.Command("gcc", "-c", "-O0", "-fno-stack-protector", "-o", T("new.o"), f).Run() != nil {
		return harness.ErrReported
	}
	x, _ := exec.Command("nm", "--extern-only", "--defined-only", T("new.o")).Output()
	var ext []string
	for _, l := range lines(string(x)) {
		if fs := strings.Fields(l); len(fs) > 0 {
			ext = append(ext, fs[len(fs)-1])
		}
	}
	sort.Strings(ext)
	if es := trSpace(ext); es != "main " {
		(&rep{tag: "symbols", w: w}).say("the output defines external symbols other than main: %s", es)
		return harness.ErrReported
	}
	u, _ := exec.Command("nm", "-u", T("new.o")).Output()
	(&rep{tag: "symbols", w: w}).say("`main` is still the only external symbol, over %d undefined", len(lines(string(u))))

	// --- 3. the corpus is sized against the source's own arithmetic --------
	sizes, ok := z40Sizes(f, tmp)
	prefixed(w, "  arithmetic   ", sizes)
	if !ok {
		return harness.ErrReported
	}

	// --- 4. the depth is reached, and the old corpus does not reach it -----
	src := readFile(f)
	probed, marks, perr := z40Probe(src)
	if perr != nil {
		(&rep{tag: "probe", w: w}).say("the instrument could not be built from this source:")
		fmt.Fprintln(w, "               "+perr.Error())
		return harness.ErrReported
	}
	mk := readFile(filepath.Join(work, "Makefile"))
	setup := func(dir, text string) {
		os.MkdirAll(T(dir), 0o755)
		put(T(dir, "zero-vim.c"), text)
		put(T(dir, "Makefile"), mk)
	}
	setup("probe", probed)
	for _, c := range []string{"descent", "lineadd", "cache", "reshape", "clock"} {
		t := src
		for _, e := range z40Ctl[c] {
			if n := strings.Count(t, e[0]); n != 1 {
				(&rep{tag: "ablefail", w: w}).say("a control could not be made from this source:")
				fmt.Fprintf(w, "               a %s control anchor is in the source %d times, expected 1\n", c, n)
				return harness.ErrReported
			}
			t = strings.Replace(t, e[0], e[1], 1)
		}
		setup(c, t)
	}
	reprobed, _, _ := z40Probe(readFile(T("reshape", "zero-vim.c")))
	setup("reprobe", reprobed)
	dirs := []string{"probe", "descent", "lineadd", "cache", "reshape", "clock", "reprobe"}
	errs := make([]error, len(dirs))
	var wg sync.WaitGroup
	for i, d := range dirs {
		wg.Add(1)
		go func(i int, d string) { defer wg.Done(); errs[i] = exec.Command("make", "-C", T(d)).Run() }(i, d)
	}
	wg.Wait()
	for _, e := range errs {
		if e != nil {
			(&rep{tag: "ablefail", w: w}).say("an instrumented or control copy did not build -- the break is wrong, not the corpus")
			return harness.ErrReported
		}
	}
	quiet := func(args ...string) error { return exec.Command("tools/st.sh", args...).Run() }
	for _, a := range [][]string{{"zmemline", T("probe", "zero-vim"), T("probe-mem")},
		{"zcases", T("probe", "zero-vim"), T("probe-screen")},
		{"zmemline", T("reprobe", "zero-vim"), T("reprobe-mem")}} {
		if quiet(a...) != nil {
			return harness.ErrReported
		}
	}
	cover, deep, ok := z40Cover(T("probe-mem"), T("probe-screen"), marks)
	prefixed(w, "  probe        ", cover)
	if !ok {
		return harness.ErrReported
	}

	// --- 5. the instrument is deterministic ---------------------------------
	if !recordThrice(w, bin, f, tmp) {
		return harness.ErrReported
	}
	run1 := T("run1")
	(&rep{tag: "instrument", w: w}).say("%d cases, %d memline cases, %d commands, %d command lines, %d pty scenarios, %d terminals: 3 identical runs",
		dirCount(filepath.Join(run1, "screen")), dirCount(filepath.Join(run1, "memline")),
		countHeaders(filepath.Join(run1, "ref-excmds.txt")), countHeaders(filepath.Join(run1, "ref-argv.txt")),
		countHeaders(filepath.Join(run1, "ref-pty.txt")), countLines([]byte(readFile(filepath.Join(run1, "ref-term.txt")))))

	// --- 6. the instrument can fail, and the one it joins cannot ------------
	for _, c := range []string{"descent", "lineadd", "cache", "reshape", "clock"} {
		if quiet("zmemline", T(c, "zero-vim"), T("mem-"+c)) != nil || quiet("zcases", T(c, "zero-vim"), T("scr-"+c)) != nil {
			return harness.ErrReported
		}
	}
	res, ok := z40Controls(run1, tmp, deep, T("probe-mem"), T("reprobe-mem"))
	prefixed(w, "  ablefail     ", res)
	if !ok {
		fmt.Fprintln(w, "               A corpus that cannot fail is not evidence, and one that")
		fmt.Fprintln(w, "               fails differently is not this corpus.")
		return harness.ErrReported
	}

	// --- 7. the declared delta ----------------------------------------------
	if run(w, "sh", "tools/zerodelta.sh", bin, f, "--phase", "40") != nil {
		return harness.ErrReported
	}

	// --- 1, concluded ---------------------------------------------------------
	if sha256File(f) != before {
		(&rep{tag: "source", w: w}).say("zero-vim.c was modified by a phase that must not modify it")
		return harness.ErrReported
	}
	(&rep{tag: "source", w: w}).say("zero-vim.c unchanged, %d lines: r40 is its input's tree, and only the instrument moved", countLines([]byte(readFile(f))))
	return nil
}

// z40Sizes is section 3: the block arithmetic lifted out of the source and
// compiled, and the corpus's sizes checked against it.
func z40Sizes(src, tmp string) (string, bool) {
	text := readFile(src)
	var parts []string
	for _, name := range []string{"char_u", "short_u", "linenr_T", "blocknr_T", "PTR_EN"} {
		m := regexp.MustCompile(`(?m)^typedef [^\n;]*\b` + name + `;$`).FindString(text)
		if m == "" {
			return fmt.Sprintf("typedef %s is not in the source: the arithmetic cannot be derived", name), false
		}
		parts = append(parts, m)
	}
	m := regexp.MustCompile(`(?m)^enum \{ MEMFILE_PAGE_SIZE = (\d+) \};$`).FindString(text)
	if m == "" {
		return "MEMFILE_PAGE_SIZE is not an enumerator in the source", false
	}
	parts = append(parts, m)
	for _, name := range []string{"pointer_entry", "pointer_block", "data_block"} {
		m := regexp.MustCompile(`(?ms)^struct ` + name + `\n\{.*?^\};$`).FindString(text)
		if m == "" {
			return fmt.Sprintf("struct %s is not in the source", name), false
		}
		parts = append(parts, m)
	}
	prog := strings.Join(parts, "\n") + `
int printf(const char *, ...);
int main(void) {
    printf("%d %d %d %d %d\n", (int)MEMFILE_PAGE_SIZE,
        (int)__builtin_offsetof(struct data_block, db_index),
        (int)__builtin_offsetof(struct pointer_block, pb_pointer),
        (int)sizeof(struct pointer_entry), (int)sizeof(unsigned));
    return 0;
}
`
	d := filepath.Join(tmp, "derive")
	os.MkdirAll(d, 0o755)
	put(filepath.Join(d, "d.c"), prog)
	if out, err := exec.Command("gcc", "-O0", "-o", filepath.Join(d, "d"), filepath.Join(d, "d.c")).CombinedOutput(); err != nil {
		return string(out), false
	}
	o, err := exec.Command(filepath.Join(d, "d")).Output()
	if err != nil {
		return "the derived program did not run", false
	}
	var v []int
	for _, x := range strings.Fields(string(o)) {
		n, _ := strconv.Atoi(x)
		v = append(v, n)
	}
	page, dataHdr, ptrHdr, ptrEn, idx := v[0], v[1], v[2], v[3], v[4]
	lb := harness.ZmemLineBytes()
	perBlock := (page - dataHdr) / (lb + 1 + idx)
	pbMax := (page - ptrHdr) / ptrEn
	rootSplit := (pbMax + 1) * perBlock
	set := map[int]bool{}
	for _, s := range harness.ZmemSizes() {
		set[s] = true
	}
	var sizes []int
	for s := range set {
		sizes = append(sizes, s)
	}
	sort.Ints(sizes)
	if len(sizes) == 0 {
		return "zmemline builds no buffer at all: the corpus would be vacuous", false
	}
	if sizes[0] <= perBlock {
		return fmt.Sprintf("the corpus's smallest buffer is %d lines and one data block holds %d, so its smallest case need not have a tree at all", sizes[0], perBlock), false
	}
	if last := sizes[len(sizes)-1]; last <= rootSplit {
		return fmt.Sprintf("the corpus's largest buffer is %d lines and the root pointer block holds %d children of %d lines each, so %d lines are needed before it can split", last, pbMax, perBlock, rootSplit), false
	}
	var ss []string
	past1, pastRoot := 0, 0
	for _, s := range sizes {
		ss = append(ss, strconv.Itoa(s))
		if s > perBlock {
			past1++
		}
		if s > rootSplit {
			pastRoot++
		}
	}
	return fmt.Sprintf("page %d, data header %d, index %d, PTR_EN %d: a %d-byte line packs %d to a block and pb_count_max is %d, so the root splits past %d lines\n"+
		"%d cases build %s lines: %d past one block, %d past the root split",
		page, dataHdr, idx, ptrEn, lb, perBlock, pbMax, rootSplit,
		harness.ZmemCaseCount(), strings.Join(ss, ","), past1, pastRoot), true
}

// z40Read is every record in a directory, by name.
func z40Read(d string) map[string]string {
	out := map[string]string{}
	e, _ := os.ReadDir(d)
	for _, x := range e {
		out[x.Name()] = strings.ToValidUTF8(readFile(filepath.Join(d, x.Name())), "�")
	}
	return out
}

// z40Cover is section 4's heredoc: every marker in at least one memline
// record and in none of the screen cases; the deep cases, for section 6.
func z40Cover(memdir, scrdir string, marks []string) (string, []string, bool) {
	if len(marks) == 0 {
		return "the probe placed no marker at all, so this check would be vacuous", nil, false
	}
	hits := func(d string) map[string]map[string]bool {
		out := map[string]map[string]bool{}
		for n, t := range z40Read(d) {
			out[n] = map[string]bool{}
			for _, m := range marks {
				if strings.Contains(t, m) {
					out[n][m] = true
				}
			}
		}
		return out
	}
	mem, scr := hits(memdir), hits(scrdir)
	var missing []string
	for _, m := range marks {
		found := false
		for _, v := range mem {
			if v[m] {
				found = true
			}
		}
		if !found {
			missing = append(missing, m)
		}
	}
	if len(missing) > 0 {
		return "the memline corpus reaches none of: " + strings.Join(missing, " ") +
			"\nA corpus that MEANS to reach a split and does not is the defect this phase exists to end.", nil, false
	}
	seenSet, reach := map[string]bool{}, 0
	for _, v := range scr {
		if len(v) > 0 {
			reach++
		}
		for m := range v {
			seenSet[m] = true
		}
	}
	if len(seenSet) > 0 {
		var seen []string
		for m := range seenSet {
			seen = append(seen, m)
		}
		sort.Strings(seen)
		return fmt.Sprintf("%d of the %d screen cases already reach %s, so the premise of this phase is wrong on this boundary and the corpus below is not what makes the text layer visible", reach, len(scr), strings.Join(seen, " ")), nil, false
	}
	var deep []string
	for n, v := range mem {
		if v["MLDEEP"] {
			deep = append(deep, n)
		}
	}
	sort.Strings(deep)
	if len(deep) == 0 {
		return "no memline case descends past one pointer block", nil, false
	}
	var counts []string
	for _, m := range marks {
		c := 0
		for _, v := range mem {
			if v[m] {
				c++
			}
		}
		counts = append(counts, fmt.Sprintf("%s %d", m, c))
	}
	return fmt.Sprintf("%d markers on the memline tree, each in at least one of %d memline records and in 0 of %d screen cases:\n  %s",
		len(marks), len(mem), len(scr), strings.Join(counts, "  ")), deep, true
}

// z40Controls is section 6's heredoc.
func z40Controls(run1, tmp string, deep []string, probeMem, reprobeMem string) (string, bool) {
	moved := func(a, b map[string]string) []string {
		set := map[string]bool{}
		for n := range a {
			set[n] = true
		}
		for n := range b {
			set[n] = true
		}
		var out []string
		for n := range set {
			av, aok := a[n]
			bv, bok := b[n]
			if aok != bok || av != bv {
				out = append(out, n)
			}
		}
		sort.Strings(out)
		return out
	}
	baseMem, baseScr := z40Read(filepath.Join(run1, "memline")), z40Read(filepath.Join(run1, "screen"))
	corrupt := []string{"descent", "lineadd", "cache", "reshape"}
	by, byscr := map[string][]string{}, map[string][]string{}
	for _, c := range append(corrupt, "clock") {
		by[c] = moved(baseMem, z40Read(filepath.Join(tmp, "mem-"+c)))
		byscr[c] = moved(baseScr, z40Read(filepath.Join(tmp, "scr-"+c)))
	}
	var bad []string
	for _, c := range corrupt {
		if len(byscr[c]) > 0 {
			bad = append(bad, fmt.Sprintf("the %s control moved %d of the %d SCREEN cases (%s), so the old corpus is not blind to it and this phase has the wrong premise",
				c, len(byscr[c]), len(baseScr), strings.Join(head(byscr[c], 5), " ")))
		}
	}
	for _, c := range []string{"descent", "lineadd"} {
		if len(by[c]) == 0 {
			bad = append(bad, fmt.Sprintf("the %s control moved NO memline record: a corpus that cannot fail is not evidence", c))
		}
	}
	if strings.Join(by["cache"], " ") != strings.Join(deep, " ") {
		mv := strings.Join(by["cache"], " ")
		if mv == "" {
			mv = "(nothing)"
		}
		bad = append(bad, fmt.Sprintf("the cache control moved %s, and the cases the probe measured as descending past one pointer block are %s -- the two must be the same set, or the deep cases are decoration", mv, strings.Join(deep, " ")))
	}
	if len(by["reshape"]) > 0 {
		bad = append(bad, fmt.Sprintf("the reshape control moved %s: quartering pb_count_max changes the TREE and not the editor, so a corpus that moves is recording the data structure rather than the behaviour", strings.Join(by["reshape"], " ")))
	}
	if len(by["clock"]) > 0 {
		bad = append(bad, fmt.Sprintf("the clock control moved %s: a memline record must not depend on what time it is, and the stream digest this corpus drops was dropped for exactly that", strings.Join(by["clock"], " ")))
	}
	if len(byscr["clock"]) == 0 {
		bad = append(bad, fmt.Sprintf("the clock control moved none of the %d screen cases either, so it changed nothing and its empty memline result proves nothing", len(baseScr)))
	}
	splits := func(d string) map[string]bool {
		out := map[string]bool{}
		for n, t := range z40Read(d) {
			if strings.Contains(t, "MLSPLITROOT") {
				out[n] = true
			}
		}
		return out
	}
	was, now := splits(probeMem), splits(reprobeMem)
	subset := true
	for n := range now {
		if !was[n] {
			subset = false
		}
	}
	if subset {
		bad = append(bad, fmt.Sprintf("quartering pb_count_max left the same %d cases splitting the root, so the control changed no tree and its empty result proves nothing", len(was)))
	}
	if len(bad) > 0 {
		return strings.Join(bad, "\n"), false
	}
	return fmt.Sprintf("5 controls, and 0 of the %d screen cases moved by any of the four corruptions:\n", len(baseScr)) +
		fmt.Sprintf("  descent  pe_line_count-- gone from ml_find_line: %d of %d memline records move\n", len(by["descent"]), len(baseMem)) +
		fmt.Sprintf("  lineadd  ml_lineadd's deferred adjustment gone:  %d of %d move\n", len(by["lineadd"]), len(baseMem)) +
		fmt.Sprintf("  cache    ML_FIND stack one line too wide:        %d of %d move, and they are exactly the %d the probe measured descending past one pointer block\n", len(by["cache"]), len(baseMem), len(deep)) +
		fmt.Sprintf("  reshape  pb_count_max quartered:                 0 of %d move, while the root split goes from %d cases to %d\n", len(baseMem), len(was), len(now)) +
		fmt.Sprintf("  clock    both clocks run away from the wall:     0 of %d move, and %d of the %d screen cases do (%s) -- the record carries no timestamp, and the control is not a no-op",
			len(baseMem), len(byscr["clock"]), len(baseScr), strings.Join(byscr["clock"], " ")), true
}
