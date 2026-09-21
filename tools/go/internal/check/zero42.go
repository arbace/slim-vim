package check

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
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
	"time"

	"slimvim.local/tools/internal/harness"
)

func init() { register("zero42", Zero42) }

var (
	z42Ident    = regexp.MustCompile(`[A-Za-z_]\w*`)
	z42Test     = regexp.MustCompile(`(?m)^( *)if \(hp-> bh_hashitem\.mhi_key  != (\d)\)$`)
	z42IfaceWrn = regexp.MustCompile(`warning: '([A-Za-z_0-9]*)' used but never defined`)
	z42MemName  = regexp.MustCompile(`^.*memline/([a-z_]*) .*$`)
	z42RootProb = regexp.MustCompile(`ROOTPROBE pres=(\d+) over=(\d+)`)
	z42Clock    = regexp.MustCompile(`\d+ seconds? ago`)
	z42SplitIn  = regexp.MustCompile(`split_root=[1-9]`)
	z42PresOut  = regexp.MustCompile(`ROOTPROBE pres=[1-9]`)
)

var z42Names = []string{"neg_new", "neg_add", "neg_del", "neg_find", "ctl_data",
	"b0_open", "b0_flags", "b0_fname", "split_seen", "split_root", "find_ptr"}

// z42Body is the instrument's two functions, generated from the names as the
// heredoc generated them.
func z42Body() string {
	var calls []string
	for _, n := range z42Names {
		calls = append(calls, fmt.Sprintf("    write(2, \" %s=\", %d);\n    probe_num(probe_%s);", n, len(n)+2, n))
	}
	return `
    static void
probe_num(long v)
{
    char b[24];
    int i = 24;

    if (v == 0)
    {
        b[--i] = '0';
    }
    while (v > 0)
    {
        b[--i] = (char)('0' + v % 10);
        v /= 10;
    }
    write(2, b + i, (usize)(24 - i));
}

    static void
probe_dump(void)
{
    write(2, "PROBE", 5);
` + strings.Join(calls, "\n") + `
    write(2, "\n", 1);
}

`
}

type z42Mark struct{ name, anchor, marked, what string }

var z42Marks = []z42Mark{
	{"neg_new", "        if (negative)\n        {\n            hp-> bh_hashitem.mhi_key  = mfp->mf_blocknr_min--;",
		"        if (negative)\n        {\n            probe_neg_new++;\n            hp-> bh_hashitem.mhi_key  = mfp->mf_blocknr_min--;",
		"mf_new()'s negative branch"},
	{"neg_add", "    if (hp-> bh_hashitem.mhi_key  >= 0)\n    {\n        return OK;\n    }\n",
		"    if (hp-> bh_hashitem.mhi_key  >= 0)\n    {\n        return OK;\n    }\n    probe_neg_add++;\n",
		"mf_trans_add() past its early return"},
	{"neg_del", "    if (np == nullptr)\n    {\n        return old_nr;\n    }\n",
		"    if (np == nullptr)\n    {\n        return old_nr;\n    }\n    probe_neg_del++;\n",
		"mf_trans_del() past its early return"},
	{"neg_find", "                if (bnum < 0)\n                {\n                    bnum2 = mf_trans_del(mfp, bnum);",
		"                if (bnum < 0)\n                {\n                    probe_neg_find++;\n                    bnum2 = mf_trans_del(mfp, bnum);",
		"ml_find_line()'s negative-block arm"},
	{"ctl_data", "ml_new_data(memfile_T *mfp, int negative, int page_count)\n{",
		"ml_new_data(memfile_T *mfp, int negative, int page_count)\n{\n    probe_ctl_data++;", "ml_new_data()"},
	{"b0_open", "    b0p->b0_id[0] = BLOCK0_ID0;", "    probe_b0_open++;\n    b0p->b0_id[0] = BLOCK0_ID0;",
		"ml_open()'s first header write"},
	{"b0_flags", "            b0p = (ZERO_BL *)(hp->bh_data);\n            b0p-> b0_fname[B0_FNAME_SIZE_ORG - 1]  = buf->b_changed ? B0_DIRTY : 0;",
		"            b0p = (ZERO_BL *)(hp->bh_data);\n            probe_b0_flags++;\n            b0p-> b0_fname[B0_FNAME_SIZE_ORG - 1]  = buf->b_changed ? B0_DIRTY : 0;",
		"ml_setflags()'s header write"},
	{"b0_fname", "set_b0_fname(ZERO_BL *b0p, buf_T *buf)\n{\n", "set_b0_fname(ZERO_BL *b0p, buf_T *buf)\n{\n    probe_b0_fname++;\n",
		"set_b0_fname()"},
	{"split_seen", "                hp_new = ml_new_ptr(mfp);", "                probe_split_seen++;\n                hp_new = ml_new_ptr(mfp);",
		"ml_append_int()'s split loop"},
	{"split_root", "                 musl_memmove((char *)(pp_new), (char *)(pp), (usize)page_size) ;\n                pp->pb_count = 1;",
		"                probe_split_root++;\n                 musl_memmove((char *)(pp_new), (char *)(pp), (usize)page_size) ;\n                pp->pb_count = 1;",
		"ml_append_int()'s root-preserving branch"},
	{"find_ptr", "        if ((top = ml_add_stack(buf)) < 0)", "        probe_find_ptr++;\n        if ((top = ml_add_stack(buf)) < 0)",
		"ml_find_line()'s descent into a pointer block"},
}

// z42Keys builds a keystroke list the way the heredocs build theirs.
func z42Lines(n int, f func(int) string) [][]byte {
	k := [][]byte{[]byte("i")}
	for i := 0; i < n; i++ {
		k = append(k, []byte(f(i)))
	}
	return append(k, []byte("\x1b"))
}

func z42Repeat(k [][]byte, s string, n int) [][]byte {
	for i := 0; i < n; i++ {
		k = append(k, []byte(s))
	}
	return k
}

// Zero42 is phase 42's check: the swap file's residue.
func Zero42(w io.Writer, args []string) error {
	if len(args) != 2 {
		return fmt.Errorf("usage: check zero42 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	f := filepath.Join(work, "zero-vim.c")
	oldC := filepath.Join(state, "old.c")
	const TAG = "swapres"
	r := &rep{tag: TAG, w: w}
	say := func(format string, a ...any) { r.say(format, a...) }
	die := func(format string, a ...any) error {
		r.say(format, a...)
		return harness.ErrReported
	}
	for _, x := range [][2]string{
		{oldC, "the edit left no $state/old.c"},
		{filepath.Join(state, "edit.c"), "the edit left no $state/edit.c, so what the EDIT removed and what the SWEEP removed cannot be told apart"},
		{filepath.Join(state, "old"), "the edit left no input binary"},
	} {
		if fi, e := os.Stat(x[0]); e != nil || !fi.Mode().IsRegular() {
			return die("%s", x[1])
		}
	}
	tmp, err := os.MkdirTemp("", "zero42-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	T := func(n string) string { return filepath.Join(tmp, n) }
	head := func(p string, n int) string {
		s := strings.TrimRight(readFile(p), "\n")
		L := strings.Split(s, "\n")
		if len(L) > n {
			L = L[:n]
		}
		return strings.Join(L, "\n")
	}
	mk := readFile(filepath.Join(work, "Makefile"))
	cflagsS, ldflagsS := "", ""
	if m := z29CFlags.FindStringSubmatch(mk); m != nil {
		cflagsS = m[1]
	}
	if m := z29LDFlags.FindStringSubmatch(mk); m != nil {
		ldflagsS = m[1]
	}
	link := func(src, out, logPath string) error {
		a := append(append(strings.Fields(cflagsS), strings.Fields(ldflagsS)...), "-o", out, src)
		c := exec.Command("gcc", a...)
		c.Env = append(os.Environ(), "SOURCE_DATE_EPOCH=0")
		lf, _ := os.Create(logPath)
		defer lf.Close()
		c.Stderr = lf
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
	newT := readFile(f)
	os.WriteFile(T("new.c"), []byte(newT), 0o644)
	jNew := start(func() error { return link(T("new.c"), T("new"), T("e.new")) })

	// --- 0. the variants --------------------------------------------------------------
	oldT := readFile(oldC)
	one := func(text, s, what string) error {
		if strings.Count(text, s) != 1 {
			return die("`%s` is not in that source exactly once, so a control built "+
				"from it would not be one", what)
		}
		return nil
	}
	var dn []string
	for _, n := range z42Names {
		dn = append(dn, "probe_"+n)
	}
	DECLS := "static long " + strings.Join(dn, ", ") + ";\n\n"
	BODY := z42Body()
	const EXIT = "    static void\nhost_exit(int r)\n{\n"
	if e := one(oldT, EXIT, "host_exit()"); e != nil {
		return e
	}
	if strings.Contains(oldT, "probe_neg_new") {
		return die("the input already says `probe_neg_new`")
	}
	const MFNEW = "    static bhdr_T *\nmf_new("
	p := strings.Replace(oldT, MFNEW, DECLS+MFNEW, 1)
	if p == oldT {
		return die("mf_new() is not defined in this tree's shape, so the counters " +
			"have nowhere to go above their first use")
	}
	for _, m := range z42Marks {
		if e := one(p, m.anchor, m.what); e != nil {
			return e
		}
		p = strings.Replace(p, m.anchor, m.marked, 1)
		if strings.Count(p, "probe_"+m.name+"++") != 1 {
			return die("the marker for %s was not planted exactly once", m.what)
		}
	}
	p = strings.Replace(p, EXIT, BODY+EXIT+"    probe_dump();\n", 1)
	os.WriteFile(T("probe.c"), []byte(p), 0o644)
	ctl := map[string]string{
		"c_open": strings.Replace(oldT, "    b0p->b0_id[0] = BLOCK0_ID0;", "    return FAIL;\n    b0p->b0_id[0] = BLOCK0_ID0;", 1),
		"c_bnum": strings.Replace(newT, "    pp->pb_pointer[0].pe_bnum = 1;", "    pp->pb_pointer[0].pe_bnum = 2;", 1),
		"c_root": strings.Replace(newT, "                if (hp-> bh_hashitem.mhi_key  != 0)\n", "                if (hp-> bh_hashitem.mhi_key  != 1)\n", 1),
	}
	for _, k := range []string{"c_bnum", "c_open", "c_root"} {
		base := newT
		if k == "c_open" {
			base = oldT
		}
		if ctl[k] == base {
			return die("the control %s changed nothing, so it would not be a control", k)
		}
		os.WriteFile(T(k+".c"), []byte(ctl[k]), 0o644)
	}
	const DEP = "static long pr_pres, pr_over;\n\n"
	DBODY := strings.SplitN(strings.ReplaceAll(BODY, "probe_num", "pr_num"), "    static void\nprobe_dump", 2)[0]
	for _, x := range [][2]string{{"wkp", newT}, {"rootp", ctl["c_root"]}} {
		q := strings.Replace(x[1], MFNEW, DEP+MFNEW, 1)
		q = strings.Replace(q, "                 musl_memmove((char *)(pp_new), (char *)(pp), (usize)page_size) ;\n                pp->pb_count = 1;",
			"                pr_pres++;\n                 musl_memmove((char *)(pp_new), (char *)(pp), (usize)page_size) ;\n                pp->pb_count = 1;", 1)
		q = strings.Replace(q, "            iemsg(e_updated_too_many_blocks);", "            pr_over++;\n            iemsg(e_updated_too_many_blocks);", 1)
		q = strings.Replace(q, EXIT, DBODY+EXIT+"    write(2, \"ROOTPROBE pres=\", 15);\n"+
			"    pr_num(pr_pres);\n    write(2, \" over=\", 6);\n    pr_num(pr_over);\n"+
			"    write(2, \"\\n\", 1);\n", 1)
		if strings.Count(q, "pr_pres++") != 1 || strings.Count(q, "pr_over++") != 1 || !strings.Contains(q, "ROOTPROBE") {
			return die("the depth instrument did not plant on %s", x[0])
		}
		os.WriteFile(T(x[0]+".c"), []byte(q), 0o644)
	}
	say("six variants written: probe, the INPUT with eleven counters -- four on " +
		"the negative-block island, three on block zero, and ml_new_data(), the root split " +
		"and the pointer-block descent as controls; c_open, the input with its first " +
		"header write replaced by `return FAIL;`; c_bnum and c_root, the output with each " +
		"of the two block numbers this phase moved put back; and wkp and rootp, the output " +
		"and c_root with a counter on the root-preserving branch and on the overflow that " +
		"follows when it is not taken")
	jobs := map[string]*job{}
	for _, v := range []string{"probe", "c_open", "c_bnum", "c_root", "wkp", "rootp"} {
		v := v
		jobs[v] = start(func() error { return link(T(v+".c"), T(v), T("e."+v)) })
	}
	os.WriteFile(T("canon.c"), []byte(newT), 0o644)
	var canonLog []byte
	jCanon := start(func() error {
		var e error
		canonLog, e = exec.Command("sh", "tools/canon.sh", T("canon.c")).CombinedOutput()
		return e
	})

	// --- 1. the source: what the EDIT took and what the SWEEP took ------------------
	mid := readFile(filepath.Join(state, "edit.c"))
	declaredIn, _ := strconv.Atoi(strings.TrimSpace(readFile(filepath.Join(state, "input-lines"))))
	nl := func(s string) int { return strings.Count(s, "\n") }
	if nl(oldT) != declaredIn {
		return die("the text the edit was handed is %d lines and the driver recorded %d", nl(oldT), declaredIn)
	}
	say("%d -> %d -> %d lines: the EDIT took %d and the SWEEP took %d more, %d altogether",
		nl(oldT), nl(mid), nl(newT), nl(oldT)-nl(mid), nl(mid)-nl(newT), nl(oldT)-nl(newT))
	words := func(s string) map[string]bool {
		m := map[string]bool{}
		for _, x := range z42Ident.FindAllString(s, -1) {
			m[x] = true
		}
		return m
	}
	EDIT := []string{"mf_dirty", "mfdirty_T", "MF_DIRTY_NO", "MF_DIRTY_YES", "MF_DIRTY_YES_NOSYNC", "mf_sync",
		"mf_trans", "mf_trans_add", "mf_trans_del", "mf_blocknr_min", "mf_neg_count", "newfile", "infile",
		"pe_old_lnum", "lnum_left", "lnum_right", "bnum2", "mf_dont_release", "new_bnum", "old_nr", "dirty", "VIM"}
	type sw struct{ k, v string }
	SWEEP := []sw{
		{"ZERO_BL", "a type nothing reaches"}, {"block0", "its struct tag"}, {"b0p", "the only pointer to it"},
		{"b0_id", "a header field"}, {"b0_version", "a header field"}, {"b0_page_size", "a header field"},
		{"b0_fname", "a header field"}, {"b0_magic_long", "a header field"}, {"b0_magic_int", "a header field"},
		{"b0_magic_short", "a header field"}, {"b0_magic_char", "a header field"},
		{"BLOCK0_ID0", "an enumerator nothing mentions"}, {"BLOCK0_ID1", "an enumerator nothing mentions"},
		{"B0_FNAME_SIZE_ORG", "an enumerator nothing mentions"}, {"B0_MAGIC_LONG", "an enumerator nothing mentions"},
		{"B0_MAGIC_INT", "an enumerator nothing mentions"}, {"B0_MAGIC_SHORT", "an enumerator nothing mentions"},
		{"B0_MAGIC_CHAR", "an enumerator nothing mentions"}, {"B0_DIRTY", "an enumerator nothing mentions"},
		{"BH_DIRTY", "an enumerator nothing mentions"}, {"MFS_ZERO", "an enumerator nothing mentions"},
		{"ML_APPEND_NEW", "an enumerator nothing mentions"}, {"ML_LOCKED_DIRTY", "an enumerator nothing mentions"},
		{"ML_LOCKED_POS", "an enumerator nothing mentions"}, {"NR_TRANS", "a type nothing reaches"},
		{"nr_trans", "its struct tag"}, {"nt_hashitem", "its fields"}, {"nt_new_bnum", "its fields"},
		{"set_b0_fname", "a static function with no caller"}, {"long_to_char", "a static function with no caller"},
		{"ml_setflags", "a static function with no caller"}, {"mf_hash_free_all", "a static function with no caller"},
		{"Version", "a static object nothing reads"}, {"VIM_VERSION_SHORT", "the only thing it held"},
		{"e_didnt_get_block_nr_two", "a static object nothing reads"},
	}
	LITERAL := map[string]bool{"x10111213L": true, "x20212223L": true, "x30313233L": true, "x55": true}
	wo, wm, wn := words(oldT), words(mid), words(newT)
	var intro []string
	for x := range wn {
		if !wo[x] {
			intro = append(intro, x)
		}
	}
	sort.Strings(intro)
	if len(intro) > 0 {
		return die("the phase introduces %d names the input did not have (%s), and it must "+
			"introduce none", len(intro), strings.Join(intro, " "))
	}
	minus := func(a, b map[string]bool) map[string]bool {
		out := map[string]bool{}
		for x := range a {
			if !b[x] {
				out[x] = true
			}
		}
		return out
	}
	goneEdit, goneSweep := minus(wo, wm), minus(wm, wn)
	sweepSet := map[string]bool{}
	for _, s := range SWEEP {
		sweepSet[s.k] = true
	}
	editSet := map[string]bool{}
	for _, s := range EDIT {
		editSet[s] = true
	}
	for _, x := range []struct {
		what      string
		got, want map[string]bool
	}{{"EDIT", goneEdit, editSet}, {"SWEEP", goneSweep, sweepSet}} {
		var extra, missing []string
		for k := range x.got {
			if !x.want[k] && !LITERAL[k] {
				extra = append(extra, k)
			}
		}
		for k := range x.want {
			if !x.got[k] {
				missing = append(missing, k)
			}
		}
		sort.Strings(extra)
		sort.Strings(missing)
		if len(extra)+len(missing) > 0 {
			es, ms := strings.Join(extra, " "), strings.Join(missing, " ")
			if es == "" {
				es = "none"
			}
			if ms == "" {
				ms = "none"
			}
			return die("the %s removes %d and this phase accounts for %d -- unaccounted: %s; "+
				"accounted but still here: %s", x.what, len(x.got), len(x.want), es, ms)
		}
	}
	nEnum, nFunc := 0, 0
	for _, s := range SWEEP {
		if strings.Contains(s.v, "enumerator") {
			nEnum++
		}
		if strings.Contains(s.v, "function") {
			nFunc++
		}
	}
	say("%d names leave in the EDIT and %d more in the SWEEP, and every one is accounted "+
		"for.  THE DIVISION IS THE PHASE'S WHOLE ARGUMENT: nothing that is WRITTEN is in "+
		"the sweep's set, because no tool in tools/ can see a write -- the edit's set is "+
		"four write-only fields, a write-only state machine, two unreachable functions, four "+
		"parameters and four locals; the sweep's is what those left behind, %d of them "+
		"enumerators and %d functions with no caller", len(goneEdit), len(goneSweep), nEnum, nFunc)
	for _, x := range [][2]string{
		{"mf_new(memfile_T *mfp, int page_count)", "mf_new() takes no `negative`"},
		{"mf_put(bhdr_T *hp)", "mf_put() takes neither a memfile nor a state"},
		{"ml_new_data(memfile_T *mfp, int page_count)", "ml_new_data() takes no `negative`"},
		{"ml_append(linenr_T    lnum, char_u      *line, colnr_T     len)", "ml_append() takes no `newfile`"},
	} {
		if c := strings.Count(newT, x[0]); c != 1 {
			return die("%s -- `%s` is in the output %d times", x[1], x[0], c)
		}
	}
	say("the four signatures this phase narrows are each in the output exactly once: " +
		"mf_new and ml_new_data without `negative`, ml_append without `newfile`, and mf_put " +
		"as `mf_put(bhdr_T *hp)`")
	if strings.Count(newT, "    bnum = 0;\n") != 1 {
		return die("ml_find_line() does not start its descent at block nr 0 exactly once")
	}
	tests := z42Test.FindAllStringSubmatch(newT, -1)
	var shallow, deep, all []string
	for _, t := range tests {
		if len(t[1]) == 4 {
			shallow = append(shallow, t[2])
		} else if len(t[1]) > 4 {
			deep = append(deep, t[2])
		}
		all = append(all, fmt.Sprintf("%d:%s", len(t[1]), t[2]))
	}
	if strings.Join(shallow, ",") != "0,1" || strings.Join(deep, ",") != "0" {
		return die("the output tests a block number in %d places -- %s -- and after this phase "+
			"ml_open() tests 0 then 1 and ml_append_int() tests 0", len(tests), strings.Join(all, " "))
	}
	if strings.Count(newT, "    pp->pb_pointer[0].pe_bnum = 1;") != 1 {
		return die("ml_open()'s root does not point at block nr 1")
	}
	say("the two surviving blocks are numbered from 0: ml_find_line() descends from block " +
		"nr 0, ml_open() takes block nr 0 for the root and block nr 1 for the data, and its " +
		"root points at 1")
	dirs := func(s string) []int {
		var d []int
		for i, l := range strings.Split(s, "\n") {
			if z35Dir.MatchString(l) {
				d = append(d, i)
			}
		}
		return d
	}
	dOld, dNew := dirs(oldT), dirs(newT)
	contig := len(dNew) > 0
	for k := range dNew {
		if contig && dNew[k] != dNew[0]+k {
			contig = false
		}
	}
	if len(dOld) != len(dNew) || !contig {
		return die("the output holds %d directives where the input held %d, or they are not "+
			"contiguous", len(dNew), len(dOld))
	}
	say("the %d `#include`s are untouched and contiguous, at line %d where they were at %d, "+
		"and this phase adds no preprocessor line and removes none", len(dNew), dNew[0]+1, dOld[0]+1)

	// --- 2. the cut -------------------------------------------------------------------
	iface := map[string][]string{}
	cutN := map[string]int{}
	for _, x := range [][2]string{{"old", oldC}, {"new", f}} {
		var lines []string
		for _, l := range strings.Split(readFile(x[1]), "\n") {
			if z38Inc.MatchString(l) {
				break
			}
			lines = append(lines, l)
		}
		// This heredoc's cut is the NAIVE awk, `{ exit } { print }`, with no
		// trailing-blank drop -- one line more than `make editor.c` on the
		// same text -- and the port keeps it, since the count is printed.
		text := ""
		for _, l := range lines {
			text += l + "\n"
		}
		cp := T("cut-" + x[0] + ".c")
		os.WriteFile(cp, []byte(text), 0o644)
		if len(lines) <= 1000 {
			return die("the %s cut is %d lines, so the boundary is not where this check thinks", x[0], len(lines))
		}
		hashes := 0
		for _, l := range lines {
			if z30Dir.MatchString(l) {
				hashes++
			}
		}
		if hashes != 0 {
			return die("the %s cut holds %d preprocessor directives and the core may hold none", x[0], hashes)
		}
		c := exec.Command("gcc", "-O0", "-fno-stack-protector", "-fsyntax-only", cp)
		var eb strings.Builder
		c.Stderr = &eb
		if err := c.Run(); err != nil {
			return die("the %s cut does not compile on its own", x[0])
		}
		if strings.Contains(eb.String(), "error:") {
			return die("the %s cut draws an error under -fsyntax-only", x[0])
		}
		wo2, _ := exec.Command("gcc", "-c", "-O0", "-fno-stack-protector", "-o", T("cut-"+x[0]+".o"), cp).CombinedOutput()
		set := map[string]bool{}
		for _, m := range z42IfaceWrn.FindAllStringSubmatch(string(wo2), -1) {
			set[m[1]] = true
		}
		iface[x[0]] = z27Keys(set)
		cutN[x[0]] = len(lines)
	}
	if strings.Join(iface["old"], "\n") != strings.Join(iface["new"], "\n") {
		sym := map[string]bool{}
		for _, n := range comm23(iface["old"], iface["new"]) {
			sym[n] = true
		}
		for _, n := range comm23(iface["new"], iface["old"]) {
			sym[n] = true
		}
		return die("the core -> host interface moved: %s", z31Words(z27Keys(sym)))
	}
	say("the cut is %d -> %d lines, every line this phase removes is ABOVE the boundary, 0 of them begin with `#`, "+
		"both draw 0 errors under -fsyntax-only, and the core -> host interface is the same %d names either "+
		"side: %s", cutN["old"], cutN["new"], len(iface["new"]), z31Words(iface["new"]))

	// --- 3. the tools that assert a place, a floor and a linkage --------------------
	jNew.wg.Wait()
	if jNew.err != nil {
		return die("the output did not build: %s", head(T("e.new"), 3))
	}
	newSize, oldSize := sizeOf(T("new")), sizeOf(filepath.Join(state, "old"))
	for _, tool := range []string{"zhostonly", "orphanopts"} {
		c := exec.Command("sh", "tools/st.sh", tool, f)
		c.Stdout, c.Stderr = w, w
		if err := c.Run(); err != nil {
			return harness.ErrReported
		}
	}
	pc := exec.Command("sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols"))
	pc.Stdout, pc.Stderr = w, w
	if err := pc.Run(); err != nil {
		return harness.ErrReported
	}
	jCanon.wg.Wait()
	if jCanon.err != nil {
		return die("tools/canon.sh failed on the output")
	}
	if !z30Same(T("canon.c"), f) {
		cl := strings.Split(strings.TrimRight(string(canonLog), "\n"), "\n")
		return die("tools/canon.sh is not a no-op on the output: %s", cl[len(cl)-1])
	}
	say("tools/canon.sh is a no-op on the output, so the file the sweep left is canonical")
	for _, x := range [][2]string{{oldC, "old.o"}, {f, "new.o"}} {
		if err := exec.Command("gcc", "-c", "-O0", "-fno-stack-protector", "-o", T(x[1]), x[0]).Run(); err != nil {
			return harness.ErrReported
		}
	}
	uOld := nmField26(T("old.o"), []string{"-u"}, 1)
	uNew := nmField26(T("new.o"), []string{"-u"}, 1)
	if strings.Join(uOld, "\n") != strings.Join(uNew, "\n") {
		sym := map[string]bool{}
		for _, n := range comm23(uOld, uNew) {
			sym[n] = true
		}
		for _, n := range comm23(uNew, uOld) {
			sym[n] = true
		}
		return die("the undefined set moved by %s and this phase frees none", z31Words(z27Keys(sym)))
	}
	extOut, _ := exec.Command("nm", "--extern-only", "--defined-only", T("new.o")).Output()
	ext := ""
	for _, l := range strings.Split(strings.TrimRight(string(extOut), "\n"), "\n") {
		fs := strings.Fields(l)
		if len(fs) > 2 {
			ext += fs[2] + " "
		} else {
			ext += " "
		}
	}
	if ext != "main " {
		return die("the object defines `%s` where it must define exactly main", ext)
	}
	say("the undefined set is UNCHANGED, %d names either side -- %s-- and `nm --extern-only --defined-only` prints "+
		"exactly main.  A phase that deletes core code and crosses no boundary frees no symbol, and this is that "+
		"stated as an equality rather than as a count", len(uNew), z31Words(uNew))
	say("the binary is %d bytes in and %d out, %d fewer", oldSize, newSize, oldSize-newSize)

	// --- 4. the two recordings ----------------------------------------------------------
	oldBin, _ := filepath.Abs(filepath.Join(state, "old"))
	var wgR sync.WaitGroup
	var errRO, errRN error
	wgR.Add(2)
	go func() {
		defer wgR.Done()
		c := exec.Command("sh", "tools/zrecord.sh", oldBin, oldC, T("REC-old"))
		c.Stderr = w
		errRO = c.Run()
	}()
	go func() {
		defer wgR.Done()
		c := exec.Command("sh", "tools/zrecord.sh", T("new"), T("new.c"), T("REC-new"))
		c.Stderr = w
		errRN = c.Run()
	}()
	wgR.Wait()
	if errRO != nil {
		return die("the input binary could not be recorded")
	}
	if errRN != nil {
		return die("the output binary could not be recorded")
	}
	if out, err := exec.Command("diff", "-r", T("REC-old"), T("REC-new")).CombinedOutput(); err != nil {
		L := strings.Split(strings.TrimRight(string(out), "\n"), "\n")
		if len(L) > 4 {
			L = L[:4]
		}
		return die("the recordings differ, and this phase declares nothing: %s", strings.Join(L, "\n"))
	}
	countDir := func(d string) int { e, _ := os.ReadDir(d); return len(e) }
	say("TWO FULL RECORDINGS, BYTE-IDENTICAL: %d screen cases, %d memline cases, the Ex sweep, the argv sweep, "+
		"the pty scenarios and the terminal table, from the binary the edit was handed and from the one it produced",
		countDir(filepath.Join(T("REC-new"), "screen")), countDir(filepath.Join(T("REC-new"), "memline")))

	// --- 5. the probes ----------------------------------------------------------------
	jobs["probe"].wg.Wait()
	if jobs["probe"].err != nil {
		return die("the instrumented build failed: %s", head(T("e.probe"), 3))
	}
	type bg struct {
		name string
		err  error
	}
	var wgP sync.WaitGroup
	res := map[string]error{}
	var mu sync.Mutex
	runBG := func(name string, fn func() error) {
		wgP.Add(1)
		go func() {
			defer wgP.Done()
			e := fn()
			mu.Lock()
			res[name] = e
			mu.Unlock()
		}()
	}
	runBG("sc", func() error { return exec.Command("sh", "tools/st.sh", "zcases", T("probe"), T("SC-probe")).Run() })
	runBG("ex", func() error {
		return exec.Command("sh", "tools/st.sh", "zexcmds", T("probe"), T("probe.c"), T("ex-probe.txt")).Run()
	})
	runBG("av", func() error { return exec.Command("sh", "tools/st.sh", "zargv", T("probe"), T("argv-probe.txt")).Run() })
	runBG("ml", func() error { return exec.Command("sh", "tools/st.sh", "zmemline", T("probe"), T("ML-in")).Run() })
	runBG("st", func() error {
		type cs struct {
			name string
			keys [][]byte
		}
		CASES := []cs{
			{"4k lines", append(z42Lines(4000, func(i int) string { return fmt.Sprintf("line %d of the buffer here\n", i) }),
				[]byte("G"), []byte(":q!\r"))},
			{"25k lines", append(z42Repeat([][]byte{[]byte("i")}, strings.Repeat("x", 19)+"\n", 25000),
				[]byte("\x1b"), []byte("G"), []byte(":q!\r"))},
			{"25k dGG+undo", append(z42Repeat([][]byte{[]byte("i")}, strings.Repeat("y", 19)+"\n", 25000),
				[]byte("\x1b"), []byte("ggdG"), []byte("u"), []byte("G"), []byte(":q!\r"))},
			{"25k mid-delete", append(z42Repeat(append(z42Lines(25000, func(i int) string { return fmt.Sprintf("z%d\n", i) })[:25001],
				[]byte("\x1b"), []byte("12000G")), "dd", 2000), []byte("G"), []byte(":q!\r"))},
			{"25k sort", append(z42Lines(25000, func(i int) string { return fmt.Sprintf("%d\n", 7919*i%99991) }),
				[]byte(":sort\r"), []byte("G"), []byte(":q!\r"))},
			{"mid churn", append(z42Repeat(z42Lines(2000, func(i int) string { return fmt.Sprintf("abcdefghij%d\n", i) }), "1000Gdd", 300),
				[]byte("G"), []byte(":q!\r"))},
			{"sort big", append(z42Lines(3000, func(i int) string { return fmt.Sprintf("s%d\n", 7919*i%10000) }),
				[]byte(":sort\r"), []byte("G"), []byte(":q!\r"))},
			{"join all", append(z42Lines(2000, func(i int) string { return fmt.Sprintf("j%d\n", i) }),
				[]byte("gg"), []byte("2000J"), []byte(":q!\r"))},
		}
		var out strings.Builder
		for _, c := range CASES {
			_, _, se, rc, err := harness.ZSession(T("probe"), c.keys, "xterm", nil, 24, 80, 600*time.Second)
			if err != nil {
				return err
			}
			fmt.Fprintf(&out, "%s rc=%d\n%s\n", c.name, rc, harness.DecodeReplace(se))
		}
		return os.WriteFile(T("stress-probe.txt"), []byte(out.String()), 0o644)
	})
	wgP.Wait()
	for _, x := range [][2]string{
		{"sc", "the screen corpus failed on the instrumented build"},
		{"ex", "the Ex sweep failed on the instrumented build"},
		{"av", "the argv sweep failed on the instrumented build"},
		{"ml", "phase 40's memline corpus failed on the instrumented build"},
		{"st", "the stress sessions failed on the instrumented build"},
	} {
		if res[x[0]] != nil {
			return die("%s", x[1])
		}
	}
	var rxParts []string
	for _, n := range z42Names {
		rxParts = append(rxParts, n+`=(\d+)`)
	}
	RX := regexp.MustCompile(`PROBE ` + strings.Join(rxParts, " "))
	tot, hit := map[string]int{}, map[string]int{}
	nrec := 0
	scan := func(text string) int {
		got := 0
		for _, m := range RX.FindAllStringSubmatch(text, -1) {
			nrec++
			got++
			for k, n := range z42Names {
				v, _ := strconv.Atoi(m[k+1])
				tot[n] += v
				if v != 0 {
					hit[n]++
				}
			}
		}
		return got
	}
	listDir := func(d string) []string {
		es, _ := os.ReadDir(d)
		var ns []string
		for _, e := range es {
			ns = append(ns, e.Name())
		}
		sort.Strings(ns)
		return ns
	}
	files := listDir(T("SC-probe"))
	marked := 0
	for _, n := range files {
		if scan(readFile(filepath.Join(T("SC-probe"), n))) > 0 {
			marked++
		}
	}
	if marked != len(files) || len(files) == 0 {
		return die("the instrumented build marked %d of %d screen cases, and it must "+
			"mark every one -- the counters are printed from host_exit(), which every "+
			"case reaches", marked, len(files))
	}
	for _, extra := range []string{"ex-probe.txt", "argv-probe.txt", "stress-probe.txt"} {
		scan(readFile(T(extra)))
	}
	mem := listDir(T("ML-in"))
	memMarked := 0
	for _, n := range mem {
		if scan(readFile(filepath.Join(T("ML-in"), n))) > 0 {
			memMarked++
		}
	}
	if memMarked != len(mem) || len(mem) == 0 {
		return die("the instrumented build marked %d of %d memline cases, and it must "+
			"mark every one", memMarked, len(mem))
	}
	var bad []string
	for _, k := range []string{"neg_new", "neg_add", "neg_del", "neg_find"} {
		if hit[k] > 0 {
			bad = append(bad, k)
		}
	}
	if len(bad) > 0 {
		return die("%s fired in a recorded session, so the negative-block island is "+
			"NOT unreachable and this phase must not remove it", strings.Join(bad, " "))
	}
	if hit["ctl_data"] < nrec/2 {
		return die("the control fired in %d of %d records, and an instrument that "+
			"marks almost nothing proves nothing about the four that mark none", hit["ctl_data"], nrec)
	}
	B0 := []string{"b0_open", "b0_flags", "b0_fname"}
	minB0 := hit[B0[0]]
	for _, k := range B0 {
		if hit[k] < minB0 {
			minB0 = hit[k]
		}
	}
	b0h := fmt.Sprintf("%d/%d/%d", hit[B0[0]], hit[B0[1]], hit[B0[2]])
	if minB0 < nrec/2 {
		return die("the block-zero markers fired in %s of %d records, and this half of "+
			"the phase is code that RUNS -- an instrument that does not see it running "+
			"is not measuring what the check claims", b0h, nrec)
	}
	say("THE NEGATIVE-BLOCK HALF IS PHASE 9'S KIND -- CODE THAT COULD NOT RUN: "+
		"the four markers on mf_new()'s negative branch, mf_trans_add() past its early "+
		"return, mf_trans_del() past its own and ml_find_line()'s `bnum < 0` arm fired in "+
		"0 of %d records -- %d screen, %d memline, %d from the two sweeps and %d stress "+
		"sessions -- against a control of identical shape in ml_new_data() that fired "+
		"in %d of them, %d times", nrec, len(files), len(mem), nrec-len(files)-len(mem)-8, 8,
		hit["ctl_data"], tot["ctl_data"])
	say("THE BLOCK-ZERO HALF IS PHASE 12'S KIND -- CODE THAT RUNS AND THE "+
		"INSTRUMENT CANNOT SEE: the three markers on the header writes fired in %s of %d "+
		"records, %s times, and the two full recordings above are the same bytes.  An "+
		"empty declaration is a different statement in each half, and only the second one "+
		"is about the harness", b0h, nrec, fmt.Sprintf("%d/%d/%d", tot[B0[0]], tot[B0[1]], tot[B0[2]]))
	say("AND THE CORPUS CANNOT SEE THE ROOT AT ALL: ml_find_line() descended into "+
		"a pointer block in %d of %d records and %d times, but ml_append_int()'s split "+
		"loop was reached in %d and its root-preserving branch in %d.  That is why "+
		"sections 7b and 8 exist: phase 40's memline corpus, and sixty thousand lines "+
		"driven by hand", hit["find_ptr"], nrec, tot["find_ptr"], hit["split_seen"], hit["split_root"])

	// --- 6. the controls that MUST move the recording --------------------------------
	for _, v := range []string{"c_open", "c_bnum", "c_root"} {
		jobs[v].wg.Wait()
		if jobs[v].err != nil {
			return die("%s did not build", v)
		}
	}
	scErr := map[string]error{}
	var wgS sync.WaitGroup
	for _, v := range []string{"c_open", "c_bnum", "c_root"} {
		v := v
		wgS.Add(1)
		go func() {
			defer wgS.Done()
			e := exec.Command("sh", "tools/st.sh", "zcases", T(v), T("SC-"+v)).Run()
			mu.Lock()
			scErr[v] = e
			mu.Unlock()
		}()
	}
	wgS.Wait()
	d := map[string]int{}
	for _, v := range []string{"c_open", "c_bnum", "c_root"} {
		if scErr[v] != nil {
			return die("the screen corpus failed on %s", v)
		}
		d[v] = len(diffRQ(filepath.Join(T("REC-new"), "screen"), T("SC-"+v)))
	}
	total := countDir(filepath.Join(T("REC-new"), "screen"))
	if d["c_open"] != total {
		return die("c_open -- the input's first header write replaced by `return FAIL;` -- moves %d of %d screen cases, and it must move every one", d["c_open"], total)
	}
	if d["c_bnum"] != total {
		return die("c_bnum -- ml_open()'s root pointing at the old block number -- moves %d of %d screen cases, and it must move every one", d["c_bnum"], total)
	}
	if d["c_root"] != 0 {
		return die("c_root moves %d screen cases, and the measurement this check is built on is that it moves none", d["c_root"])
	}
	say("the controls: c_open moves %d of %d screen cases and c_bnum moves %d, so the corpus can see both ml_open() "+
		"and the block numbering -- and c_root moves %d, which is the finding sections 7b and 8 are for: the ONE line "+
		"of this phase that every one of the 102 screen cases is blind to", d["c_open"], total, d["c_bnum"], d["c_root"])

	// --- 7. BH_LOCKED -----------------------------------------------------------------------
	if !strings.Contains(newT, "BH_LOCKED") {
		return die("BH_LOCKED has gone, and this phase does not remove it")
	}
	nLocked := 0
	for _, l := range strings.Split(newT, "\n") {
		if strings.Contains(l, "BH_LOCKED") {
			nLocked++
		}
	}
	say("BH_LOCKED stays: it is read by mf_put()'s `e_block_was_not_locked` test, which is the one thing bh_flags is "+
		"asked, and %d mentions of it survive", nLocked)

	// --- 7b. phase 40's memline corpus -----------------------------------------------------
	if exec.Command("sh", "tools/st.sh", "zmemline", T("c_root"), T("ML-croot")).Run() != nil {
		return die("phase 40's corpus failed on the c_root control")
	}
	jobs["wkp"].wg.Wait()
	if exec.Command("sh", "tools/st.sh", "zmemline", T("wkp"), T("ML-out")).Run() != nil {
		return die("phase 40's corpus failed on the instrumented output")
	}
	if fi, e := os.Stat(T("ML-in")); e != nil || !fi.IsDir() {
		return die("section 5 left no instrumented memline record")
	}
	if fi, e := os.Stat(filepath.Join(T("REC-new"), "memline")); e != nil || !fi.IsDir() {
		return die("tools/zrecord.sh recorded no memline/, so phase 40's corpus is not in the recording this check compares")
	}
	var mv []string
	for _, l := range diffRQ(filepath.Join(T("REC-new"), "memline"), T("ML-croot")) {
		mv = append(mv, z42MemName.ReplaceAllString(l, "$1"))
	}
	moved := strings.TrimRight(strings.Join(mv, " ")+" ", " ")
	if moved == "" {
		return die("the c_root control moves NONE of phase 40's cases, so nothing in this pipeline can see ml_append_int()'s root test")
	}
	if !strings.Contains(" "+moved+" ", " mem_deep_jumps ") {
		return die("the c_root control moves %s, and mem_deep_jumps is the case measured to reach the root split on THIS phase's output", moved)
	}
	filesMatching := func(dir string, re *regexp.Regexp) int {
		n := 0
		for _, name := range listDir(dir) {
			if re.MatchString(readFile(filepath.Join(dir, name))) {
				n++
			}
		}
		return n
	}
	mlIn, mlOut := filesMatching(T("ML-in"), z42SplitIn), filesMatching(T("ML-out"), z42PresOut)
	if mlOut < 1 {
		return die("no case of phase 40's corpus reaches the root split on this phase's output")
	}
	if mlIn <= mlOut {
		return die("phase 40's corpus reaches the root split in %d cases on the input and %d on the output, and this phase can only make a pointer block hold MORE children, never fewer", mlIn, mlOut)
	}
	say("PHASE 40'S CORPUS SEES THIS PHASE, and it is the only recorded thing that does: the c_root control -- "+
		"ml_append_int()'s root test left at the old block number, which all 102 screen cases are blind to -- moves %s "+
		"of its sixteen cases.  AND THIS PHASE NARROWS WHAT THAT CORPUS REACHES: %d of the sixteen split the root on "+
		"the input and %d on the output, because phase 40 derived its buffer sizes from sizeof(PTR_EN) and "+
		"pe_old_lnum has left PTR_EN.  A case named for the root split is a case sized for a fanout, and this phase "+
		"changes the fanout", moved, mlIn, mlOut)

	// --- 8. the root split, which only sixty thousand lines reach ----------------------
	jobs["wkp"].wg.Wait()
	if jobs["wkp"].err != nil {
		return die("the depth instrument on the output did not build")
	}
	jobs["rootp"].wg.Wait()
	if jobs["rootp"].err != nil {
		return die("the depth instrument on c_root did not build")
	}
	keys := func(n int) [][]byte {
		k := z42Repeat([][]byte{[]byte("i")}, strings.Repeat("x", 19)+"\n", n)
		return append(k, []byte("\x1b"), []byte("G"), []byte(fmt.Sprintf("%dG", n/2)), []byte(":q!\r"))
	}
	reads := func(n int) [][]byte {
		k := z42Lines(n, func(i int) string { return fmt.Sprintf("L%07d\n", i) })
		for _, j := range []int{1, 1000, n / 2, n - 1} {
			k = append(k, []byte(fmt.Sprintf("%dG", j)))
		}
		return append(k, []byte("gg"), []byte("G"), []byte(":q!\r"))
	}
	type runR struct {
		rc      int
		sha     string
		err     []byte
		raw     []byte
		blocked bool
	}
	run := func(binary string, k [][]byte) runR {
		_, so, se, rc, err := harness.ZSession(binary, k, "xterm", nil, 24, 80, 900*time.Second)
		if err != nil {
			return runR{blocked: true}
		}
		sum := sha256.Sum256(z42Clock.ReplaceAll(so, []byte("<CLOCK>")))
		return runR{rc, hex.EncodeToString(sum[:])[:16], se, so, false}
	}
	type rp struct {
		pres, over int
		sha        string
	}
	got := map[string]rp{}
	for _, side := range []string{"wkp", "rootp"} {
		rr := run(T(side), keys(60000))
		if rr.blocked {
			return die("the %s session never returned", side)
		}
		m := z42RootProb.FindSubmatch(rr.err)
		if m == nil {
			return die("the depth instrument on %s printed no ROOTPROBE line", side)
		}
		pr, _ := strconv.Atoi(string(m[1]))
		ov, _ := strconv.Atoi(string(m[2]))
		got[side] = rp{pr, ov, rr.sha}
	}
	if got["wkp"].pres < 1 || got["wkp"].over != 0 {
		return die("at sixty thousand lines the OUTPUT preserved the root %d times and overflowed "+
			"%d -- it must preserve it at least once and never overflow, or this case is not "+
			"reaching the line the phase moves", got["wkp"].pres, got["wkp"].over)
	}
	if got["rootp"].pres != 0 || got["rootp"].over < 1 {
		return die("the control with the old block number preserved the root %d times and "+
			"overflowed %d -- it must do the opposite, or it is not a control", got["rootp"].pres, got["rootp"].over)
	}
	if got["wkp"].sha == got["rootp"].sha {
		return die("the output and the wrong-number control draw the same screen even at sixty " +
			"thousand lines, so nothing in this check can see the root test at all")
	}
	say("AT SIXTY THOUSAND LINES THE ROOT REALLY SPLITS, and the one line the "+
		"corpus is blind to becomes visible: the OUTPUT preserves the root %d time(s) and "+
		"never overflows, the control with ml_append_int()'s test left at the OLD block "+
		"number preserves it %d times and reaches e_updated_too_many_blocks %d time(s), and the "+
		"two draw DIFFERENT screens (%s against %s).  That is the check that `!= 0` is "+
		"right, said directly; 7b is the same fact said by the pipeline's own corpus",
		got["wkp"].pres, got["rootp"].pres, got["rootp"].over, got["wkp"].sha, got["rootp"].sha)
	type cs struct {
		name string
		keys [][]byte
	}
	CASES := []cs{
		{"60k + a jump to the middle", keys(60000)},
		{"60k with reads all over it", reads(60000)},
		{"60k deleted and undone", append(z42Repeat([][]byte{[]byte("i")}, strings.Repeat("y", 19)+"\n", 60000),
			[]byte("\x1b"), []byte("ggdG"), []byte("u"), []byte("G"), []byte(":q!\r"))},
		{"100k with five hundred deletions", append(z42Repeat(append(z42Lines(100000, func(i int) string {
			return fmt.Sprintf("z%07d\n", i)
		})[:100001], []byte("\x1b"), []byte("50000G")), "dd", 500), []byte("G"), []byte("25000G"), []byte(":q!\r"))},
	}
	var bad2 []string
	clocks := 0
	for _, c := range CASES {
		a := run(oldBin, c.keys)
		b := run(T("new"), c.keys)
		if a.blocked || b.blocked {
			return die("a session of %s never returned", c.name)
		}
		if z42Clock.Match(a.raw) {
			clocks++
		}
		if z42Clock.Match(b.raw) {
			clocks++
		}
		if a.rc != b.rc || a.sha != b.sha || !bytes.Equal(a.err, b.err) {
			bad2 = append(bad2, fmt.Sprintf("%s: (%d, '%s') against (%d, '%s')", c.name, a.rc, a.sha, b.rc, b.sha))
		}
	}
	if len(bad2) > 0 {
		return die("the input and the output differ on %s", strings.Join(bad2, "; "))
	}
	if clocks == 0 {
		return die("none of the %d sessions drew undo's `N seconds ago`, so the clock this "+
			"comparison folds out is not in them and the folding is hiding something else", len(CASES))
	}
	say("and the two binaries AGREE at that size: %d sessions of sixty thousand "+
		"lines and more -- built, jumped about in, read all over, deleted and undone, and "+
		"churned -- each drawing the same stream and exiting the same way, with undo's "+
		"wall clock folded out of %d of the %d streams.  The pointer "+
		"block holds MORE entries after this phase, because pe_old_lnum left PTR_EN, so "+
		"the tree is a different shape and the screen is the same", len(CASES), clocks, 2*len(CASES))

	// --- 9. what this phase declares ---------------------------------------------------
	decl, _ := exec.Command("sh", "tools/zerodelta.sh", "--declared", "42").Output()
	if strings.Join(strings.Fields(string(decl)), "") != "" {
		return die("pipes/zero.delta declares something for phase 42, and this phase declares nothing at all")
	}
	say("pipes/zero.delta declares NOTHING for this phase, and that is two statements and not one: the negative-block island could not run, and block zero ran everywhere and was never read")
	return nil
}
