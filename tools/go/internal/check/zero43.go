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

func init() { register("zero43", Zero43) }

var (
	z43Lit      = regexp.MustCompile(`"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'`)
	z43DQ       = regexp.MustCompile(`"(?:[^"\\\n]|\\.)*"`)
	z43Ident    = regexp.MustCompile(`[A-Za-z_]\w*`)
	z43Mfget3   = regexp.MustCompile(`\bmf_get\s*\([^)]*,[^)]*,`)
	z43Page     = regexp.MustCompile(`enum \{ MEMFILE_PAGE_SIZE = (\d+) \};`)
	z43Arena    = regexp.MustCompile(`enum \{ HOST_ARENA_BYTES = [^;]*\};`)
	z43Tree     = regexp.MustCompile(`TREE (\d+) (\d+) (\d+) (\d+) (\d+)`)
	z43Clock    = regexp.MustCompile(`\d+ seconds? ago`)
	z43Iemsg    = regexp.MustCompile(`(?m)^( *)iemsg\([^\n]*e_line_count_wrong_in_block[^\n]*\);$`)
	z43E323Num  = regexp.MustCompile(`E323: Line count wrong in block \d`)
	z43E323Any  = regexp.MustCompile(`E323[^\x1b]*`)
	z43IfaceWrn = regexp.MustCompile(`warning: '([A-Za-z_][A-Za-z_0-9]*)' used but never defined`)
)

const z43Rig = "enum { HOST_ARENA_BYTES = 1536 * 1024 * 1024L };"

const z43Counters = "static long ev_root;\nstatic long ev_ptr;\nstatic long ev_data;\n" +
	"static long ev_depth;\nstatic long ev_blocks;\n\n"

const z43Dump = `    static void
ev_num(long v)
{
    char        d[24];
    int         i = 24;

    if (v == 0)
    {
        d[--i] = '0';
    }
    while (v > 0)
    {
        d[--i] = (char)('0' + (int)(v % 10));
        v /= 10;
    }
    write(2, d + i, (usize)(24 - i));
}

`

var z43Anch = [][3]string{
	{"ev_data", "        dp_right = (DATA_BL *)(hp_right->bh_data);", "the data-block split"},
	{"ev_root", "                 musl_memmove((char *)(pp_new), (char *)(pp), (usize)page_size) ;", "the root-preserving branch of ml_append_int()"},
	{"ev_ptr", "            total_moved = pp->pb_count - pb_idx - 1;", "the pointer-block split"},
	{"ev_blocks", "    dp->db_id =  (('d' << 8) + 'a') ;", "a new data block"},
}

const z43Depth = "        ip->ip_low = low;\n        ip->ip_high = high;\n        ip->ip_index = -1;"

// z43PyList is Python's repr of a sorted list of names.
func z43PyList(xs []string) string {
	var q []string
	for _, x := range xs {
		q = append(q, "'"+x+"'")
	}
	return "[" + strings.Join(q, ", ") + "]"
}

// Zero43 is phase 43's check: a block number becomes a reference.
func Zero43(w io.Writer, args []string) error {
	if len(args) != 2 {
		return fmt.Errorf("usage: check zero43 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	f := filepath.Join(work, "zero-vim.c")
	oldC := filepath.Join(state, "old.c")
	const TAG = "refblocks"
	r := &rep{tag: TAG, w: w}
	say := func(format string, a ...any) { r.say(format, a...) }
	die := func(format string, a ...any) error {
		r.say(format, a...)
		return harness.ErrReported
	}
	for _, x := range [][2]string{
		{oldC, "the edit left no input source"},
		{filepath.Join(state, "old"), "the edit left no input binary"},
		{filepath.Join(state, "edit.c"), "the edit left no $state/edit.c, so what the EDIT removed and what the SWEEP removed cannot be told apart"},
	} {
		if fi, e := os.Stat(x[0]); e != nil || !fi.Mode().IsRegular() {
			return die("%s", x[1])
		}
	}
	mk := readFile(filepath.Join(work, "Makefile"))
	cflagsS, ldflagsS := "", ""
	if m := z29CFlags.FindStringSubmatch(mk); m != nil {
		cflagsS = m[1]
	}
	if m := z29LDFlags.FindStringSubmatch(mk); m != nil {
		ldflagsS = m[1]
	}
	tmp, err := os.MkdirTemp("", "zero43-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	T := func(n string) string { return filepath.Join(tmp, n) }
	newT := readFile(f)
	os.WriteFile(T("new.c"), []byte(newT), 0o644)
	var wgAll sync.WaitGroup
	defer wgAll.Wait()
	var errNew, errCanon error
	var canonLog []byte
	var wgNew, wgCanon sync.WaitGroup
	wgNew.Add(1)
	wgAll.Add(1)
	go func() {
		defer wgAll.Done()
		defer wgNew.Done()
		a := append(append(strings.Fields(cflagsS), strings.Fields(ldflagsS)...), "-o", T("new"), T("new.c"))
		c := exec.Command("gcc", a...)
		c.Env = append(os.Environ(), "SOURCE_DATE_EPOCH=0")
		lf, _ := os.Create(T("e.new"))
		c.Stderr = lf
		errNew = c.Run()
		lf.Close()
	}()
	os.WriteFile(T("canon.c"), []byte(newT), 0o644)
	wgCanon.Add(1)
	wgAll.Add(1)
	go func() {
		defer wgAll.Done()
		defer wgCanon.Done()
		canonLog, errCanon = exec.Command("sh", "tools/canon.sh", T("canon.c")).CombinedOutput()
	}()

	// --- 1. the source: the edit and the sweep, kept apart -------------------------
	oldT := readFile(oldC)
	mid := readFile(filepath.Join(state, "edit.c"))
	declaredIn, _ := strconv.Atoi(strings.TrimSpace(readFile(filepath.Join(state, "input-lines"))))
	nl := func(s string) int { return strings.Count(s, "\n") }
	words := func(s string) map[string]bool {
		m := map[string]bool{}
		for _, x := range z43Ident.FindAllString(z43Lit.ReplaceAllString(s, `""`), -1) {
			m[x] = true
		}
		return m
	}
	if nl(oldT) != declaredIn {
		return die("the text the edit was handed is %d lines and the driver recorded %d", nl(oldT), declaredIn)
	}
	say("%d -> %d -> %d lines: the EDIT took %d and the SWEEP took %d more, %d altogether",
		nl(oldT), nl(mid), nl(newT), nl(oldT)-nl(mid), nl(mid)-nl(newT), nl(oldT)-nl(newT))
	EDIT := []string{"blocknr_T", "mf_hashitem_T", "mf_hashitem_S", "mf_hashtab_T", "mf_hashtab_S", "mhi_key",
		"mhi_next", "mhi_prev", "mht_mask", "mht_count", "mht_buckets", "mht_small_buckets", "mht_fixed",
		"MHT_INIT_SIZE", "MHT_LOG_LOAD_FACTOR", "MHT_GROWTH_FACTOR", "bh_hashitem", "pe_bnum", "ip_bnum",
		"pe_page_count", "bh_page_count", "mf_blocknr_max", "mf_free_first", "mf_used_last", "mf_hash",
		"mf_ins_hash", "mf_rem_hash", "mf_find_hash", "mf_ins_free", "mf_rem_free", "mf_hash_init",
		"mf_hash_free", "mf_hash_find", "mf_hash_add_item", "mf_hash_rem_item", "mf_hash_grow", "bnum_left",
		"bnum_right", "page_count_left", "page_count_right", "e_line_count_wrong_in_block_nr", "freep", "mht",
		"mhi", "tails", "buckets", "bnum"}
	SWEEP := []string{"e_didnt_get_block_nr_zero", "e_didnt_get_block_nr_one"}
	ARRIVE := map[string]string{
		"ml_root": "the root block, which no descent can reach", "pe_block": "what a pointer entry holds instead of a number",
		"ip_block": "what a stack entry holds instead of a number", "e_line_count_wrong_in_block": "E323 without its %ld",
		"bp_left": "the left half of a split", "bp_right": "the right half of a split",
	}
	wo, wm, wn := words(oldT), words(mid), words(newT)
	setMinus := func(a, b map[string]bool) []string {
		var out []string
		for x := range a {
			if !b[x] {
				out = append(out, x)
			}
		}
		sort.Strings(out)
		return out
	}
	goneEdit, goneSweep, arrived := setMinus(wo, wm), setMinus(wm, wn), setMinus(wn, wo)
	var arrKeys []string
	for k := range ARRIVE {
		arrKeys = append(arrKeys, k)
	}
	sort.Strings(arrKeys)
	sortedCopy := func(xs []string) []string { y := append([]string{}, xs...); sort.Strings(y); return y }
	for _, x := range []struct {
		got, want []string
		what      string
	}{{goneEdit, sortedCopy(EDIT), "the edit"}, {goneSweep, sortedCopy(SWEEP), "the sweep"}, {arrived, arrKeys, "this phase"}} {
		if strings.Join(x.got, " ") != strings.Join(x.want, " ") {
			verb := "leave"
			if x.what == "this phase" {
				verb = "arrive"
			}
			return die("%s: the names that %s are %s and this phase accounts for %s", x.what, verb,
				z43PyList(x.got), z43PyList(x.want))
		}
	}
	say("%d names leave in the EDIT and %d in the SWEEP, and they are different kinds: the "+
		"edit takes what is WRITTEN -- four struct fields, two locals and the free list -- "+
		"because no tool in tools/ can see a write, and the sweep takes the two message "+
		"objects, which are unreferenced and are -Wunused-variable", len(goneEdit), len(goneSweep))
	var ap []string
	for _, k := range arrived {
		ap = append(ap, fmt.Sprintf("%s (%s)", k, ARRIVE[k]))
	}
	say("%d names arrive and no more: %s", len(arrived), strings.Join(ap, ", "))
	litSet := func(s string) map[string]bool {
		m := map[string]bool{}
		for _, x := range z43DQ.FindAllString(s, -1) {
			m[x] = true
		}
		return m
	}
	so, sn := litSet(oldT), litSet(newT)
	rem, add := setMinus(so, sn), setMinus(sn, so)
	wantRem := sortedCopy([]string{`"E323: Line count wrong in block %ld"`, `"E298: Didn't get block nr 0?"`, `"E298: Didn't get block nr 1?"`})
	if strings.Join(rem, "\x00") != strings.Join(wantRem, "\x00") {
		return die("the string literals this phase removes are %s, and it accounts for E323 with "+
			"its %%ld and the two E298s", z43PyList(rem))
	}
	if strings.Join(add, "\x00") != `"E323: Line count wrong in block"` {
		return die("the string literals this phase adds are %s, and it adds one", z43PyList(add))
	}
	say("THE STRINGS MOVE BY EXACTLY FOUR: `E323: Line count wrong in block %%ld` becomes " +
		"`E323: Line count wrong in block`, because there is no number left to print, and " +
		"the two `E298: Didn't get block nr N?` go with the tests that raised them.  " +
		"Section 9 is what makes that a measurement rather than a claim")
	for _, x := range [][2]string{
		{"    bhdr_T      *pe_block;", "a pointer entry"},
		{"    bhdr_T      *ip_block;", "a stack entry"},
		{"    bhdr_T      *ml_root;", "the memline"},
	} {
		if strings.Count(newT, x[0]) != 1 {
			return die("%s does not hold a `bhdr_T *` in the one shape this tree declares one", x[1])
		}
	}
	if !strings.Contains(newT, "mf_get(memfile_T *mfp, bhdr_T *hp)") {
		return die("mf_get() does not take a block")
	}
	if z43Mfget3.MatchString(newT) {
		return die("mf_get() is still called with three arguments somewhere")
	}
	say("mf_get(mfp, hp) takes a block, and no call of it anywhere has three arguments; " +
		"pe_block, ip_block and ml_root are all `bhdr_T *`")

	// --- 2. the block arithmetic, derived from both sources ------------------------
	derive := func(path, tag string) (int, []int, error) {
		t := readFile(path)
		out := []string{"#include <stdio.h>", "#include <stddef.h>", "typedef unsigned char char_u;"}
		for _, pat := range []string{`(?m)^typedef [^\n]*\blinenr_T;$`, `(?m)^typedef [^\n]*\bshort_u;$`,
			`(?m)^typedef [^\n]*\blong_u;$`, `(?m)^typedef [^\n]*\bblocknr_T;$`} {
			if m := regexp.MustCompile(pat).FindString(t); m != "" {
				out = append(out, m)
			}
		}
		out = append(out, "typedef struct block_hdr bhdr_T;", "typedef struct pointer_entry PTR_EN;")
		for _, name := range []string{"struct pointer_entry", "struct pointer_block", "struct data_block"} {
			m := regexp.MustCompile(`(?s)` + regexp.QuoteMeta(name) + `\n\{.*?\n\};`).FindString(t)
			if m == "" {
				return 0, nil, die("%s is not defined in %s in the one shape this tree writes a struct", name, path)
			}
			out = append(out, m)
		}
		pm := z43Page.FindStringSubmatch(t)
		if pm == nil {
			return 0, nil, die("the page size is not an enumerator in %s", path)
		}
		out = append(out, `int main(void){printf("%zu %zu %zu %zu\n",sizeof(PTR_EN),`+
			`offsetof(struct pointer_block,pb_pointer),`+
			`(`+pm[1]+`-offsetof(struct pointer_block,pb_pointer))/sizeof(PTR_EN),`+
			`offsetof(struct data_block,db_index));return 0;}`)
		c := T("derive-" + tag + ".c")
		os.WriteFile(c, []byte(strings.Join(out, "\n")), 0o644)
		if err := exec.Command("gcc", "-O0", "-o", c[:len(c)-2], c).Run(); err != nil {
			return 0, nil, fmt.Errorf("derive: gcc failed on %s", c)
		}
		o, _ := exec.Command(c[:len(c)-2]).Output()
		var v []int
		for _, x := range strings.Fields(string(o)) {
			n, _ := strconv.Atoi(x)
			v = append(v, n)
		}
		page, _ := strconv.Atoi(pm[1])
		if len(v) != 4 {
			return 0, nil, fmt.Errorf("derive: %s printed %q", c, o)
		}
		return page, v, nil
	}
	pageO, vo, e := derive(oldC, "old")
	if e != nil {
		return e
	}
	pageN, vn, e := derive(f, "new")
	if e != nil {
		return e
	}
	enO, offO, maxO, dbiO := vo[0], vo[1], vo[2], vo[3]
	enN, offN, maxN, dbiN := vn[0], vn[1], vn[2], vn[3]
	if pageO != pageN || offO != offN || dbiO != dbiN {
		return die("the page size, the pointer-block header or the data-block header moved, and "+
			"this phase touches none of the three: (%d, %d, %d) against (%d, %d, %d)", pageO, offO, dbiO, pageN, offN, dbiN)
	}
	if enN >= enO {
		return die("sizeof(PTR_EN) is %d and was %d -- this phase takes a `long` block number to a "+
			"pointer and removes an `int`, so it must shrink", enN, enO)
	}
	if maxN <= maxO {
		return die("pb_count_max is %d and was %d -- a smaller entry must fit MORE per page", maxN, maxO)
	}
	say("THE POINTER ENTRY SHRINKS AND THE TREE GETS WIDER, derived by compiling "+
		"the structs out of both sources and not written here: sizeof(PTR_EN) %d -> %d "+
		"bytes (a %d-byte block number and a %d-byte page count become one %d-byte "+
		"reference), so pb_count_max -- how many children one %d-byte pointer block holds "+
		"-- goes %d -> %d.  A ROOT SPLIT NEEDS MORE THAN THAT MANY LIVE DATA BLOCKS, "+
		"which is why sections 5 and 7 measure the corpus rather than assume it",
		enO, enN, 8, 4, 8, pageN, maxO, maxN)
	dbi, page := dbiN, pageN

	// --- 3. the build ------------------------------------------------------------------
	wgNew.Wait()
	if errNew != nil {
		fmt.Fprint(w, readFile(T("e.new")))
		return die("the output does not build with '%s' '%s'", cflagsS, ldflagsS)
	}
	if sizeOf(T("e.new")) > 0 {
		fmt.Fprint(w, readFile(T("e.new")))
		return die("the output builds with something to say")
	}
	wgCanon.Wait()
	if errCanon != nil {
		w.Write(canonLog)
		return die("tools/canon.sh is not a no-op on the output")
	}
	pcOut, pcErr := exec.Command("sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols")).CombinedOutput()
	if pcErr != nil {
		w.Write(pcOut)
		return die("tools/phasecheck.sh refuses the output")
	}
	for _, l := range strings.Split(strings.TrimSuffix(string(pcOut), "\n"), "\n") {
		if string(pcOut) == "" {
			break
		}
		fmt.Fprintf(w, "  %s\n", l)
	}
	if exec.Command("sh", "tools/st.sh", "nvidx", f).Run() != nil {
		return die("nvidx refuses the output")
	}
	if out, err := exec.Command("sh", "tools/st.sh", "orphanopts", f).CombinedOutput(); err != nil {
		w.Write(out)
		return die("orphanopts refuses the output")
	}
	if out, err := exec.Command("sh", "tools/st.sh", "zhostonly", f).CombinedOutput(); err != nil {
		w.Write(out)
		return die("zhostonly refuses the output")
	}
	oo, _ := exec.Command("sh", "tools/st.sh", "orphanopts", f).CombinedOutput()
	say("tools/phasecheck.sh, nvidx, orphanopts and zhostonly all pass, and tools/canon.sh is a no-op: this phase "+
		"touches no option row, no nv_cmds[] row and nothing below the boundary -- %s", strings.ReplaceAll(string(oo), "\n", ""))

	// --- 4. the cut `make editor.c` makes ---------------------------------------------
	var cutL []string
	for _, l := range strings.Split(newT, "\n") {
		if z38Inc.MatchString(l) {
			break
		}
		cutL = append(cutL, l)
	}
	cutText := ""
	for _, l := range cutL {
		cutText += l + "\n"
	}
	os.WriteFile(T("editor.c"), []byte(cutText), 0o644)
	cutDirs := 0
	for _, l := range cutL {
		if z30Dir.MatchString(l) {
			cutDirs++
		}
	}
	if cutDirs != 0 {
		return die("the cut has %d preprocessor directives and the core is plain C", cutDirs)
	}
	if len(cutL) <= 70000 {
		return die("the cut is %d lines, so the first #include is not where it was", len(cutL))
	}
	sc := exec.Command("gcc", "-fsyntax-only", "-O0", "-fno-stack-protector", T("editor.c"))
	var sb strings.Builder
	sc.Stderr = &sb
	if err := sc.Run(); err != nil {
		fmt.Fprint(w, sb.String())
		return die("the core alone does not pass -fsyntax-only")
	}
	cc := exec.Command("gcc", "-c", "-O0", "-fno-stack-protector", "-o", T("cut.o"), T("editor.c"))
	var cb strings.Builder
	cc.Stderr = &cb
	cc.Run()
	set := map[string]bool{}
	for _, m := range z43IfaceWrn.FindAllStringSubmatch(cb.String(), -1) {
		set[m[1]] = true
	}
	iface := z27Keys(set)
	other := 0
	for _, l := range strings.Split(cb.String(), "\n") {
		if strings.Contains(l, "warning:") {
			other++
		}
	}
	if other != len(iface) {
		return die("the core alone warns %d times and %d of them are the interface, so it says something else as well", other, len(iface))
	}
	say("the cut is %d lines with 0 directives, compiles with no error and no warning but its interface, and that "+
		"interface is the same %d names it was: %s", len(cutL), len(iface), strings.Join(iface, " ")+" ")

	// --- 5..9: the measurements --------------------------------------------------------
	oldBin, _ := filepath.Abs(filepath.Join(state, "old"))
	newBin := T("new")
	one := func(text, s, what string) error {
		if strings.Count(text, s) != 1 {
			return die("`%s` is not in that source exactly once, so a variant built from it would "+
				"not be one", what)
		}
		return nil
	}
	rig := func(text, what string) (string, error) {
		m := z43Arena.FindString(text)
		if m == "" {
			return "", die("%s has no `HOST_ARENA_BYTES` enumerator, and sections 5 and 7 raise the "+
				"arena so that this phase's evidence does not rest on phase 41's number", what)
		}
		out := strings.Replace(text, m, z43Rig, 1)
		if out == text && m != z43Rig {
			return "", die("the arena rig changed nothing in %s", what)
		}
		return out, nil
	}
	instrument := func(text, what string) (string, error) {
		p := strings.Replace(text, "enum { STACK_INCR = 5 };", "enum { STACK_INCR = 5 };\n\n"+strings.TrimRight(z43Counters, "\n"), 1)
		if p == text {
			return "", die("%s does not declare STACK_INCR, so the counters have nowhere to go", what)
		}
		for _, a := range z43Anch {
			if e := one(p, a[1], a[2]); e != nil {
				return "", e
			}
			ind := len(a[1]) - len(strings.TrimLeft(a[1], " \t\n\r\v\f"))
			p = strings.Replace(p, a[1], strings.Repeat(" ", ind)+a[0]+"++;\n"+a[1], 1)
		}
		if e := one(p, z43Depth, "ml_find_line()'s push"); e != nil {
			return "", e
		}
		p = strings.Replace(p, z43Depth, z43Depth+"\n        if ((long)top + 1 > ev_depth)\n"+
			"        {\n            ev_depth = (long)top + 1;\n        }", 1)
		const EXIT = "    static void\nhost_exit(int r)\n{\n"
		if e := one(p, EXIT, "host_exit()"); e != nil {
			return "", e
		}
		p = strings.Replace(p, EXIT, z43Dump+EXIT+
			"    write(2, \"TREE \", 5);\n"+
			"    ev_num(ev_root);\n    write(2, \" \", 1);\n"+
			"    ev_num(ev_ptr);\n    write(2, \" \", 1);\n"+
			"    ev_num(ev_data);\n    write(2, \" \", 1);\n"+
			"    ev_num(ev_depth);\n    write(2, \" \", 1);\n"+
			"    ev_num(ev_blocks);\n    write(2, \"\\n\", 1);\n", 1)
		for _, a := range z43Anch {
			if strings.Count(p, a[0]+"++") != 1 {
				return "", die("the counter %s was not planted exactly once in %s", a[0], what)
			}
		}
		return p, nil
	}
	srcs := map[string]string{}
	ro, e := rig(oldT, "the input")
	if e != nil {
		return e
	}
	rn, e := rig(newT, "the output")
	if e != nil {
		return e
	}
	tOld, e := instrument(ro, "the input")
	if e != nil {
		return e
	}
	tNew, e := instrument(rn, "the output")
	if e != nil {
		return e
	}
	srcs["tree_old"], srcs["tree_new"] = tOld, tNew
	srcs["rig_old"], srcs["rig_new"] = ro, rn
	type ctlT struct{ name, anchor, repl, what string }
	for _, c := range []ctlT{
		{"c_root", "                if (hp != buf->b_ml.ml_root)", "                if (hp != nullptr)", "ml_append_int()'s root test"},
		{"c_stack", "        ip->ip_block = bp;", "        ip->ip_block = buf->b_ml.ml_root;", "ml_find_line()'s push of the block"},
		{"c_descend", "                bp = pp->pb_pointer[idx].pe_block;", "                bp = pp->pb_pointer[0].pe_block;", "ml_find_line()'s step down"},
		{"c_mlroot", "    buf->b_ml.ml_root = hp;\n", "", "ml_open()'s one write of ml_root"},
		{"c_pages", "    if ((hp->bh_data = alloc((usize)mfp->mf_page_size * page_count)) == nullptr)",
			"    if ((hp->bh_data = alloc((usize)mfp->mf_page_size)) == nullptr)", "mf_alloc_bhdr()'s allocation"},
	} {
		if e := one(newT, c.anchor, c.what); e != nil {
			return e
		}
		v := strings.Replace(newT, c.anchor, c.repl, 1)
		if v == newT {
			return die("the control %s changed nothing, so it would not be a control", c.name)
		}
		rv, e := rig(v, c.name)
		if e != nil {
			return e
		}
		srcs[c.name] = rv
	}
	const E323 = "                vim_snprintf((char *)IObuff, emsg_iobuff_room(), e_line_count_wrong_in_block_nr, bnum);"
	if e := one(oldT, E323, "E323's arm"); e != nil {
		return e
	}
	const REACHED = "        if ((top = ml_add_stack(buf)) < 0)"
	if e := one(oldT, REACHED, "ml_find_line()'s descent into a pointer block"); e != nil {
		return e
	}
	const MARK = "{ static int mark_seen; if (!mark_seen) { mark_seen = 1; host_message(\"MARK-E323\\n\", 10, TRUE); } }\n"
	me, e := rig(strings.Replace(oldT, E323, "                "+MARK+E323, 1), "m_e323")
	if e != nil {
		return e
	}
	srcs["m_e323"] = me
	mr, e := rig(strings.Replace(oldT, REACHED, "        "+MARK+REACHED, 1), "m_reach")
	if e != nil {
		return e
	}
	srcs["m_reach"] = mr
	const SCAN = "            t = pp->pb_pointer[idx].pe_line_count;"
	for _, x := range [][2]string{{"f_old", oldT}, {"f_new", newT}} {
		if e := one(x[1], SCAN, "ml_find_line()'s read of a pointer entry's line count"); e != nil {
			return e
		}
		q := strings.Replace(x[1], SCAN, "            t = 0;", 1)
		m := z43Iemsg.FindStringSubmatchIndex(q)
		if m == nil {
			return die("%s has no iemsg of E323 on a line of its own, so the arm cannot be made "+
				"to draw and stop", x[0])
		}
		ind := q[m[2]:m[3]]
		q = q[:m[1]] + "\n" + ind + "out_flush();\n" + ind + "host_exit(0);" + q[m[1]:]
		rq, e := rig(q, x[0])
		if e != nil {
			return e
		}
		srcs[x[0]] = rq
	}
	B := map[string]string{}
	var bmu sync.Mutex
	var buildErr string
	sem := make(chan struct{}, 8)
	var wgB sync.WaitGroup
	names := make([]string, 0, len(srcs))
	for k := range srcs {
		names = append(names, k)
	}
	sort.Strings(names)
	for _, name := range names {
		name := name
		wgB.Add(1)
		sem <- struct{}{}
		go func() {
			defer wgB.Done()
			defer func() { <-sem }()
			p := T(name + ".c")
			os.WriteFile(p, []byte(srcs[name]), 0o644)
			a := append(append(strings.Fields(cflagsS), strings.Fields(ldflagsS)...), "-o", T(name), p)
			c := exec.Command("gcc", a...)
			c.Env = append(os.Environ(), "SOURCE_DATE_EPOCH=0")
			var eb strings.Builder
			c.Stderr = &eb
			err := c.Run()
			bmu.Lock()
			defer bmu.Unlock()
			if err != nil && buildErr == "" {
				s := strings.TrimSpace(eb.String())
				if len(s) > 400 {
					s = s[:400]
				}
				buildErr = fmt.Sprintf("the variant %s does not build: %s", name, s)
			}
			B[name] = T(name)
		}()
	}
	wgB.Wait()
	if buildErr != "" {
		return die("%s", buildErr)
	}
	say("%d variants built: the input and the output with five tree counters each, the same "+
		"two with the arena raised and nothing else, five controls, two markers and two "+
		"forced builds", len(B))

	// --- 5. the sixteen memline cases ------------------------------------------------------
	type ev5 [5]int
	corpus := func(binary, tag string) (map[string]ev5, error) {
		out := T("mem-" + tag)
		os.RemoveAll(out)
		exec.Command("sh", "tools/st.sh", "zmemline", binary, out).Run()
		got := map[string]ev5{}
		ents, _ := os.ReadDir(out)
		var ns []string
		for _, en := range ents {
			ns = append(ns, en.Name())
		}
		sort.Strings(ns)
		for _, name := range ns {
			txt := readFile(filepath.Join(out, name))
			ms := z43Tree.FindAllStringSubmatch(txt, -1)
			if len(ms) == 0 {
				return nil, die("the memline case %s on %s printed no TREE line, so the instrument did "+
					"not reach host_exit()", name, tag)
			}
			var v ev5
			for i := 0; i < 5; i++ {
				for _, m := range ms {
					x, _ := strconv.Atoi(m[i+1])
					if x > v[i] {
						v[i] = x
					}
				}
			}
			got[name] = v
			if strings.Contains(txt, "arena exhausted") {
				return nil, die("the memline case %s exhausted the arena even with the rig raised to "+
					"%s, so nothing in section 5 is a measurement of this phase", name, z43Rig)
			}
		}
		return got, nil
	}
	a, e := corpus(B["tree_old"], "old")
	if e != nil {
		return e
	}
	b, e := corpus(B["tree_new"], "new")
	if e != nil {
		return e
	}
	akeys := make([]string, 0, len(a))
	for k := range a {
		akeys = append(akeys, k)
	}
	sort.Strings(akeys)
	if len(a) != len(b) {
		return die("the two binaries record different memline cases")
	}
	for k := range a {
		if _, ok := b[k]; !ok {
			return die("the two binaries record different memline cases")
		}
	}
	tup := func(v ev5) string {
		return fmt.Sprintf("(%d, %d, %d, %d, %d)", v[0], v[1], v[2], v[3], v[4])
	}
	var movedD []string
	for _, k := range akeys {
		if a[k] != b[k] {
			movedD = append(movedD, fmt.Sprintf("%s %s against %s", k, tup(a[k]), tup(b[k])))
		}
	}
	if len(movedD) > 0 {
		return die("THE TREE IS REACHED DIFFERENTLY: %s", strings.Join(movedD, "; "))
	}
	var roots, deep []string
	maxBlocks := 0
	for _, k := range akeys {
		if a[k][0] > 0 {
			roots = append(roots, k)
		}
		if a[k][3] > 1 {
			deep = append(deep, k)
		}
		if a[k][4] > maxBlocks {
			maxBlocks = a[k][4]
		}
	}
	if len(roots) == 0 {
		return die("NOT ONE of the %d memline cases splits the root, so this phase changed "+
			"ml_append_int()'s root test with nothing to see it do so.  That is a corpus "+
			"whose case sizes are line counts against a tree that now holds %d children per "+
			"pointer block, and it is not something this phase may work around: the sizes "+
			"have to be derived from the block arithmetic (zero phase 40)", len(a), maxN)
	}
	var parts []string
	for _, k := range akeys {
		v := a[k]
		parts = append(parts, fmt.Sprintf("%s=%d/%d/%d/%d/%d", strings.ReplaceAll(k, "mem_", ""), v[0], v[1], v[2], v[3], v[4]))
	}
	say("THE SIXTEEN MEMLINE CASES AGREE, EVENT FOR EVENT: %s", strings.Join(parts, ", "))
	say("and the corpus still REACHES the code this phase changes: %d of %d cases split the "+
		"root (%s) and %d descend past a second pointer block (%s), against a pointer block "+
		"that now holds %d children where it held %d.  The largest case makes %d data blocks",
		len(roots), len(a), strings.Join(roots, ", "), len(deep), strings.Join(deep, ", "), maxN, maxO, maxBlocks)

	// --- 6. two whole recordings -------------------------------------------------------
	var wgR sync.WaitGroup
	for _, x := range [][3]string{{"old", oldBin, oldC}, {"new", newBin, f}} {
		x := x
		wgR.Add(1)
		go func() {
			defer wgR.Done()
			exec.Command("sh", "tools/zrecord.sh", x[1], x[2], T("rec-"+x[0])).Run()
		}()
	}
	wgR.Wait()
	if out, err := exec.Command("diff", "-r", T("rec-old"), T("rec-new")).Output(); err != nil {
		s := string(out)
		if len(s) > 3000 {
			s = s[:3000]
		}
		return die("the two recordings differ, and this phase declares nothing at all:\n%s", s)
	}
	nrec := len(walkFiles(T("rec-old")))
	say("TWO WHOLE RECORDINGS, BYTE FOR BYTE: %d records -- 102 screen cases, 16 memline "+
		"cases, every Ex command, every command line, four pty scenarios and the terminal "+
		"table -- from the binary this phase was handed and from the binary it makes, and "+
		"`diff -r` says nothing", nrec)

	// --- 7. the phase's own deep sessions ------------------------------------------------
	const PAD = 19
	perBlock := (page - dbi) / (PAD + 1 + 4)
	LINES := int(float64((maxN+2)*perBlock) * 1.5)
	keys := func(n int, tail [][]byte) [][]byte {
		k := [][]byte{[]byte("i")}
		for i := 0; i < n; i++ {
			k = append(k, []byte(fmt.Sprintf("%07d", i)+strings.Repeat("y", PAD-7)+"\n"))
		}
		k = append(k, []byte("\x1b"))
		k = append(k, tail...)
		return append(k, []byte(":q!\r"))
	}
	type runR struct {
		rc       int
		sha      string
		err, out []byte
	}
	run := func(binary string, k [][]byte) (runR, error) {
		_, so, se, rc, err := harness.ZSession(binary, k, "xterm", nil, 24, 80, 900*time.Second)
		if err != nil {
			return runR{}, die("a session on %s never returned", filepath.Base(binary))
		}
		sum := sha256.Sum256(z43Clock.ReplaceAll(so, []byte("<CLOCK>")))
		return runR{rc, hex.EncodeToString(sum[:])[:16], se, so}, nil
	}
	type evt struct {
		v   ev5
		sha string
	}
	evs := map[string]evt{}
	for _, side := range []string{"tree_old", "tree_new"} {
		rr, e := run(B[side], keys(LINES, [][]byte{[]byte("gg"), []byte("G"), []byte(fmt.Sprintf("%dG", LINES/2))}))
		if e != nil {
			return e
		}
		m := z43Tree.FindStringSubmatch(harness.DecodeReplace(rr.err))
		if m == nil {
			return die("the tree instrument on %s printed no TREE line", side)
		}
		var v ev5
		for i := 0; i < 5; i++ {
			v[i], _ = strconv.Atoi(m[i+1])
		}
		evs[side] = evt{v, rr.sha}
	}
	eo, en := evs["tree_old"], evs["tree_new"]
	if eo.v[2] != en.v[2] || eo.v[3] != en.v[3] || eo.v[4] != en.v[4] || eo.v[0] != en.v[0] {
		return die("at %d lines the input and the output disagree about the DATA layer or the root: "+
			"%s against %s", LINES, tup(eo.v), tup(en.v))
	}
	if en.v[1] > eo.v[1] {
		return die("at %d lines the output splits a pointer block %d times and the input %d -- a "+
			"block that holds %d children where it held %d cannot split MORE often", LINES, en.v[1], eo.v[1], maxN, maxO)
	}
	if eo.sha != en.sha {
		return die("at %d lines the input and the output draw different streams: %s against %s", LINES, eo.sha, en.sha)
	}
	if en.v[0] < 1 || en.v[3] < 2 {
		return die("at %d lines the output's root split %d times and its deepest descent was %d -- "+
			"the size is derived from pb_count_max=%d and %d lines a block, so if the root "+
			"does not split the derivation is wrong", LINES, en.v[0], en.v[3], maxN, perBlock)
	}
	say("THE PHASE'S OWN SESSION, at %d lines DERIVED from pb_count_max=%d and %d lines a "+
		"block and not written here: %d data blocks, %d deep, the root split %d time(s) -- "+
		"the same on both binaries -- and the SAME STREAM (%s), while the pointer layer is "+
		"deliberately NOT the same, %d pointer-block splits against the input's %d, because "+
		"a pointer block now holds %d children where it held %d",
		LINES, maxN, perBlock, en.v[4], en.v[3], en.v[0], en.sha, en.v[1], eo.v[1], maxN, maxO)
	type deepT struct {
		name string
		tail [][]byte
	}
	half := []byte(fmt.Sprintf("%dG", LINES/2))
	var dels [][]byte
	dels = append(dels, half)
	for i := 0; i < 500; i++ {
		dels = append(dels, []byte("dd"))
	}
	dels = append(dels, []byte("gg"), []byte("G"))
	DEEP := []deepT{
		{"built, jumped to both ends and the middle", [][]byte{[]byte("gg"), []byte("G"), half}},
		{"read all the way through", [][]byte{[]byte(":/y/y/"), []byte("\r"), []byte("gg")}},
		{"deleted and undone", [][]byte{[]byte("ggdG"), []byte("u"), []byte("G")}},
		{"five hundred deletions in the middle", dels},
	}
	var bad []string
	var dnames []string
	for _, d := range DEEP {
		dnames = append(dnames, d.name)
		x, e := run(B["rig_old"], keys(LINES, d.tail))
		if e != nil {
			return e
		}
		y, e := run(B["rig_new"], keys(LINES, d.tail))
		if e != nil {
			return e
		}
		if x.rc != y.rc || x.sha != y.sha {
			bad = append(bad, fmt.Sprintf("%s: (%d, '%s') against (%d, '%s')", d.name, x.rc, x.sha, y.rc, y.sha))
		}
	}
	if len(bad) > 0 {
		return die("the input and the output differ on %s", strings.Join(bad, "; "))
	}
	sort.Strings(dnames)
	say("and they agree in %d more sessions of %d lines -- %s -- each drawing the same "+
		"stream and exiting the same way", len(DEEP), LINES, strings.Join(dnames, "; "))

	// --- 8. the controls -------------------------------------------------------------------
	small := [][]byte{[]byte("ihello\x1b"), []byte("yy"), []byte("5p"), []byte("gg"), []byte("G")}
	type sess struct {
		name string
		keys [][]byte
	}
	SESSION := []sess{
		{"deep", keys(LINES, [][]byte{[]byte("gg"), []byte("G"), half})},
		{"small", keys(200, small)},
		{"long", [][]byte{[]byte("i" + strings.Repeat("q", 20000) + "\x1b"), []byte("gg"), []byte("$"), []byte("G"), []byte(":q!\r")}},
	}
	type rs struct {
		rc  int
		sha string
	}
	base := map[string]rs{}
	for _, s := range SESSION {
		x, e := run(B["rig_new"], s.keys)
		if e != nil {
			return e
		}
		base[s.name] = rs{x.rc, x.sha}
	}
	CTL := [][2]string{
		{"c_root", "ml_append_int()'s root test made a test nothing passes, so the root is split like any other block and the tree loses its head"},
		{"c_stack", "every stack entry remembers the ROOT instead of the block it came down through, so ML_FIND resumes in the wrong place"},
		{"c_descend", "every descent takes the FIRST child of a pointer block instead of the one whose line counts cover the line"},
		{"c_mlroot", "ml_open() never writes ml_root, so every descent starts at nullptr"},
	}
	seen := map[string]map[string]bool{}
	for _, c := range CTL {
		got := map[string]bool{}
		anyMoved := false
		for _, s := range SESSION {
			x, e := run(B[c[0]], s.keys)
			if e != nil {
				return e
			}
			got[s.name] = (rs{x.rc, x.sha}) != base[s.name]
			if got[s.name] {
				anyMoved = true
			}
		}
		if !anyMoved {
			return die("the control %s -- %s -- changes nothing in any of the %d sessions, so "+
				"nothing in this check can see it", c[0], c[1], len(SESSION))
		}
		seen[c[0]] = got
	}
	if !seen["c_mlroot"]["small"] {
		return die("the control that never writes ml_root leaves a two-hundred-line session alone, " +
			"so that session cannot fail at all and the `blind` finding below is vacuous")
	}
	var blind []string
	for _, c := range CTL {
		if !seen[c[0]]["small"] {
			blind = append(blind, c[0])
		}
	}
	if len(blind) == 0 {
		return die("every control moves the two-hundred-line session as well, so none of them is a " +
			"control the 102 screen cases could not see, and this check has not shown that " +
			"zero phase 40 was needed")
	}
	sk := make([]string, 0, len(seen))
	for k := range seen {
		sk = append(sk, k)
	}
	sort.Strings(sk)
	var mparts []string
	for _, k := range sk {
		var ns []string
		for n, v := range seen[k] {
			if v {
				ns = append(ns, n)
			}
		}
		sort.Strings(ns)
		mparts = append(mparts, fmt.Sprintf("%s moves %s", k, strings.Join(ns, ", ")))
	}
	sort.Strings(blind)
	say("FOUR CONTROLS, EACH MOVING SOMETHING: %s.  %d of them (%s) leave a two-hundred-line "+
		"session alone, which is the case zero phase 40 exists for -- a binary that draws "+
		"every screen case correctly and gets the tree wrong -- and c_mlroot moves all three, "+
		"which is what keeps that finding from being a session nothing could fail",
		strings.Join(mparts, "; "), len(blind), strings.Join(blind, ", "))
	cp := 0
	for _, s := range SESSION {
		x, e := run(B["c_pages"], s.keys)
		if e != nil {
			return e
		}
		if (rs{x.rc, x.sha}) != base[s.name] {
			cp++
		}
	}
	say("and a fifth that moves NOTHING and is reported: c_pages, mf_alloc_bhdr() sizing "+
		"every block one page, moves %d of the %d sessions -- because phase 41's arena has "+
		"no redzone, so writing past a short allocation is a memory bug rather than a "+
		"difference (CLAUDE.md, the last row of the verification table).  What says the "+
		"allocation is still right is the text: `page_count` still multiplies the page size "+
		"in mf_alloc_bhdr(), which is why removing the FIELD is safe", cp, len(SESSION))

	// --- 9. E323 ------------------------------------------------------------------------
	exec.Command("sh", "tools/zrecord.sh", B["m_e323"], oldC, T("rec-mark-e323")).Run()
	exec.Command("sh", "tools/zrecord.sh", B["m_reach"], oldC, T("rec-mark-reach")).Run()
	carry := func(root string) (int, int) {
		hit, tot := 0, 0
		for _, rel := range walkFiles(root) {
			tot++
			if strings.Contains(readFile(filepath.Join(root, rel)), "MARK-E323") {
				hit++
			}
		}
		return hit, tot
	}
	h1, t1 := carry(T("rec-mark-e323"))
	h2, t2 := carry(T("rec-mark-reach"))
	if h1 > 0 {
		return die("E323's arm is reached by %d of %d records, so it is not unreachable and this "+
			"phase changes a message something draws", h1, t1)
	}
	if h2 < t2/4 {
		return die("the same marker on the line above E323 is carried by only %d of %d records, so "+
			"the instrument is not proving anything", h2, t2)
	}
	fk := [][]byte{[]byte("ihello\x1b"), []byte("gg"), []byte(":q!\r")}
	smOld, e := run(B["f_old"], fk)
	if e != nil {
		return e
	}
	smNew, e := run(B["f_new"], fk)
	if e != nil {
		return e
	}
	if smOld.rc != 0 || smNew.rc != 0 {
		return die("a forced build did not exit cleanly (%d, %d), so what it drew is not what the "+
			"arm draws", smOld.rc, smNew.rc)
	}
	if !bytes.Contains(smOld.out, []byte("E323")) || !bytes.Contains(smNew.out, []byte("E323")) {
		return die("the forced builds do not draw E323, so the arm was not forced")
	}
	from := func(b []byte) []byte {
		i := bytes.Index(b, []byte("E323"))
		s := b[i:]
		if len(s) > 60 {
			s = s[:60]
		}
		return s
	}
	if !bytes.Contains(smOld.out, []byte("E323: Line count wrong in block 0")) {
		return die("the forced input does not draw E323 with a block number, so the message this "+
			"phase changes is not the one being exhibited: %s", z30BytesRepr(from(smOld.out)))
	}
	if !bytes.Contains(smNew.out, []byte("E323: Line count wrong in block")) || z43E323Num.Match(smNew.out) {
		return die("the forced output draws %s, and this phase leaves E323 with no number", z30BytesRepr(from(smNew.out)))
	}
	say("E323 IS THE ONE STRING AND IT IS NOT DRAWN: the input built with a marker on that "+
		"arm carries it in %d of %d records of a whole recording, and the IDENTICAL marker "+
		"on the line above it -- the descent into a pointer block -- is carried by %d of "+
		"%d.  Both sources built with the scan forced to find nothing DO draw it, and what "+
		"they draw is %s against %s", h1, t1, h2, t2,
		z30BytesRepr(bytes.TrimSpace(z43E323Any.Find(smOld.out))), z30BytesRepr(bytes.TrimSpace(z43E323Any.Find(smNew.out))))

	// --- 10. what this phase declares ---------------------------------------------------
	decl, _ := exec.Command("sh", "tools/zerodelta.sh", "--declared", "43").Output()
	if strings.Join(strings.Fields(string(decl)), "") != "" {
		return die("pipes/zero.delta declares something for phase 43, and this phase declares nothing at all")
	}
	say("pipes/zero.delta declares NOTHING for this phase: CLAUDE.md's sixth kind, the code runs and the instrument " +
		"sees it do the same thing.  One statement inside it is the second kind -- E323's text, which can run and " +
		"no recording reaches -- and section 9 is the probe it owes")
	return nil
}
