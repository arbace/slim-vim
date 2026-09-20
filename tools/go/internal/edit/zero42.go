package edit

import (
	"fmt"
	"io"
	"os"
	"regexp"
	"sort"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

func init() { registerArgs("zero42", Zero42) }

type z42Class struct {
	label string
	pat   *regexp.Regexp
}

// z42Left are the names this edit leaves STANDING for tools/sweep.sh, each a kind
// sweep finds.  Nothing that is WRITTEN is among them: that is the whole division
// of labour, and a write-only field or a set-and-never-tested bit is the edit's
// because no tool in tools/ can see one.
var z42Left = map[string]string{
	"set_b0_fname":             "a static function with no caller left",
	"long_to_char":             "a static function with no caller left",
	"mf_hash_free_all":         "a static function with no caller left",
	"ml_setflags":              "a forward declaration of a function that is gone",
	"Version":                  "a static object nothing reads",
	"e_didnt_get_block_nr_two": "a static object nothing reads",
	"ZERO_BL":                  "a type nothing reaches",
	"NR_TRANS":                 "a type nothing reaches",
	"BH_DIRTY":                 "an enumerator nothing mentions",
	"MFS_ZERO":                 "an enumerator nothing mentions",
	"ML_APPEND_NEW":            "an enumerator nothing mentions",
	"ML_LOCKED_POS":            "an enumerator nothing mentions",
	"ML_LOCKED_DIRTY":          "an enumerator nothing mentions",
}

// Zero42 takes the swap file's residue: four groups of bookkeeping that is
// WRITTEN and never read, which is exactly why no tool in tools/ can see any of
// it -- deadfields.py takes a field named nowhere outside its own type, and gcc
// has no warning for a file-scope object in either direction.
func Zero42(text []byte, w io.Writer, args []string) ([]byte, error) {
	p := ph{"swapres", w}
	if len(args) != 1 {
		return nil, p.die("usage: edit zero42 <file> <state-dir>")
	}
	state := args[0]
	t := string(text)

	mentions := func(name string) int {
		return len(regexp.MustCompile(`\b(?:`+name+`)\b`).FindAllString(t, -1))
	}
	blankRuns := func(s string) int {
		L := strings.Split(s, "\n")
		n := 0
		for i := 1; i < len(L); i++ {
			if L[i] == "" && L[i-1] == "" {
				n++
			}
		}
		return n
	}
	lines := func() []string { return strings.Split(t, "\n") }
	swap := func(old, new, what, why string, n int) error {
		c := strings.Count(t, old)
		if c != n {
			return p.die("%s occurs %d times, expected %d -- %s", what, c, n, why)
		}
		t = strings.ReplaceAll(t, old, new)
		return nil
	}
	drop := func(old, what, why string, n int) error { return swap(old, "", what, why, n) }
	// partition: every line that says `name` falls in exactly one class, and a
	// leftover refuses.
	partition := func(name string, classes []z42Class, what string) (map[string][]int, error) {
		L := lines()
		word := regexp.MustCompile(`\b(?:` + name + `)\b`)
		var seen []int
		for i, l := range L {
			if word.MatchString(l) {
				seen = append(seen, i)
			}
		}
		out := map[string][]int{}
		for _, c := range classes {
			out[c.label] = nil
		}
		for _, i := range seen {
			var hit []string
			for _, c := range classes {
				if c.pat.MatchString(L[i]) {
					hit = append(hit, c.label)
				}
			}
			if len(hit) != 1 {
				var labels []string
				for _, c := range classes {
					labels = append(labels, c.label)
				}
				return nil, p.die("`%s` at line %d -- %s -- falls in %d of the %d classes this phase "+
					"accounts for (%s), and every mention must fall in exactly one",
					name, i+1, strings.TrimSpace(L[i]), len(hit), len(classes),
					strings.Join(labels, ", "))
			}
			out[hit[0]] = append(out[hit[0]], i)
		}
		for _, c := range classes {
			if len(out[c.label]) == 0 {
				return nil, p.die("the class `%s` of `%s` holds no mention of it, so it is not a class of "+
					"this tree", c.label, name)
			}
		}
		var parts []string
		for _, c := range classes {
			parts = append(parts, fmt.Sprintf("%s %d", c.label, len(out[c.label])))
		}
		p.sayf("%s: %d mentions, every one in a class this phase accounts for -- %s",
			what, len(seen), strings.Join(parts, ", "))
		return out, nil
	}
	// body: the half-open line range of a definition in this tree's ONE shape --
	// the name at column 0 with `(` after it, `{` at column 0 next, closed by `}`
	// at column 0, with the return type on the indented line above.
	body := func(name string) (int, int, error) {
		L := lines()
		headRe := regexp.MustCompile(`^` + name + `\s*\(`)
		var heads []int
		for i, l := range L {
			if headRe.MatchString(l) && i+1 < len(L) && L[i+1] == "{" {
				heads = append(heads, i)
			}
		}
		if len(heads) != 1 {
			return 0, 0, p.die("`%s` is defined %d times at column 0 and this phase needs exactly one",
				name, len(heads))
		}
		end := heads[0]
		for end < len(L) && L[end] != "}" {
			end++
		}
		if end >= len(L) {
			return 0, 0, p.die("`%s` does not close at column 0", name)
		}
		if !regexp.MustCompile(`^    [\w *]+$`).MatchString(L[heads[0]-1]) {
			return 0, 0, p.die("the line above `%s`'s head is %s, and every definition in this tree "+
				"carries its return type there, indented", name, cutil.PyRepr(L[heads[0]-1]))
		}
		return heads[0] - 1, end + 1, nil
	}
	cutDefn := func(name, why string) (int, error) {
		lo, hi, err := body(name)
		if err != nil {
			return 0, err
		}
		L := lines()
		if L[hi] != "" {
			return 0, p.die("`%s`'s definition is not followed by a blank line", name)
		}
		if err := drop(strings.Join(L[lo:hi+1], "\n")+"\n",
			fmt.Sprintf("`%s`'s definition", name), why, 1); err != nil {
			return 0, err
		}
		return hi + 1 - lo, nil
	}
	cutRange := func(lo, hi int, what, why string) (int, error) {
		L := lines()
		if err := drop(strings.Join(L[lo:hi], "\n")+"\n", what, why, 1); err != nil {
			return 0, err
		}
		return hi - lo, nil
	}
	// cutAt deletes the given lines by the indices a partition computed a moment
	// ago.
	cutAt := func(idx []int) {
		L := lines()
		s := append([]int{}, idx...)
		sort.Sort(sort.Reverse(sort.IntSlice(s)))
		for _, i := range s {
			L = append(L[:i], L[i+1:]...)
		}
		t = strings.Join(L, "\n")
	}
	only := func(pred func(string) bool, what string, lo, hi, n int) ([]int, error) {
		L := lines()
		if hi < 0 {
			hi = len(L)
		}
		var got []int
		for i := lo; i < hi; i++ {
			if pred(L[i]) {
				got = append(got, i)
			}
		}
		if len(got) != n {
			var shown []string
			for _, i := range first(got, 6) {
				shown = append(shown, fmt.Sprintf("%d:%s", i+1, strings.TrimSpace(L[i])))
			}
			s := strings.Join(shown, " ")
			if s == "" {
				s = "none"
			}
			return nil, p.die("%s: %d lines where this phase needs %d -- %s", what, len(got), n, s)
		}
		return got, nil
	}

	linesBefore := len(lines()) - 1
	runsBefore := blankRuns(t)
	dirRe := regexp.MustCompile(`^ *# *`)
	var directivesBefore []int
	for i, l := range lines() {
		if dirRe.MatchString(l) {
			directivesBefore = append(directivesBefore, i)
		}
	}
	p.sayf("the input is %d lines with %d preprocessor directives, the first at line %d -- "+
		"this phase adds no directive and removes none",
		linesBefore, len(directivesBefore), directivesBefore[0]+1)

	// ==== PART 1 -- THE SWAP FILE'S HEADER BLOCK ===============================
	// The field list is READ OUT OF THE STRUCT and not written here: phase 36
	// already took `b0_pid`, so a list typed from a survey would be one name long.
	L := lines()
	sbv, err := only(func(l string) bool { return l == "struct block0" }, "`struct block0`", 0, -1, 1)
	if err != nil {
		return nil, err
	}
	sb := sbv[0]
	if L[sb+1] != "{" {
		return nil, p.die("`struct block0` does not open on the line below its tag")
	}
	end := sb + 2
	for end < len(L) && L[end] != "};" {
		end++
	}
	fieldRe := regexp.MustCompile(`^    [\w ]+?(\w+) *(\[[^]]*\])?;$`)
	var fields []string
	for i := sb + 2; i < end; i++ {
		m := fieldRe.FindStringSubmatch(L[i])
		if m == nil {
			return nil, p.die("`struct block0` has a member this phase cannot read: %s", cutil.PyRepr(L[i]))
		}
		fields = append(fields, m[1])
	}
	okF := len(fields) >= 5
	for _, f := range fields {
		if !strings.HasPrefix(f, "b0_") {
			okF = false
		}
	}
	if !okF {
		return nil, p.die("`struct block0` has members %s, and this phase was written against a header "+
			"block whose every field is a `b0_`", strings.Join(fields, " "))
	}
	p.sayf("`struct block0` is the swap file's header block and has %d fields: %s",
		len(fields), strings.Join(fields, " "))
	any := strings.Join(fields, "|")
	cls, err := partition(any, []z42Class{
		{"its declaration", regexp.MustCompile(`^    (char_u|long|int|short) +(` + any + `) *(\[[^]]*\])?;$`)},
		{"assigned", regexp.MustCompile(`^\s*b0p-> *(` + any + `)\b *(\[[^]]*\])? *=[^=]`)},
		{"copied into", regexp.MustCompile(`^\s*musl_(memmove|strncpy)\(\(char \*\)\((b0p->(` + any + `))\b|` +
			`^\s*long_to_char\([^,]+, b0p->(` + any + `)\);$`)},
	}, "the fields of `struct block0`")
	if err != nil {
		return nil, err
	}
	if len(cls["its declaration"]) != len(fields) {
		return nil, p.die("`struct block0` declares %d of the %d fields this phase was written against",
			len(cls["its declaration"]), len(fields))
	}
	nwrite := len(cls["assigned"]) + len(cls["copied into"])

	loOpen, hiOpen, err := body("ml_open")
	if err != nil {
		return nil, err
	}
	startv, err := only(func(l string) bool { return strings.HasPrefix(l, "    if ((hp = mf_new(") },
		"ml_open()'s first block allocation", loOpen, hiOpen, 1)
	if err != nil {
		return nil, err
	}
	stopv, err := only(func(l string) bool { return strings.HasPrefix(l, "    if ((hp = ml_new_ptr(") },
		"ml_open()'s pointer-block allocation", loOpen, hiOpen, 1)
	if err != nil {
		return nil, err
	}
	start, stop := startv[0], stopv[0]
	L = lines()
	pre := L[start:stop]
	for _, f := range append(append([]string{}, fields...),
		"set_b0_fname", "long_to_char", "mf_sync", "BLOCK0_ID0", "B0_DIRTY") {
		re := regexp.MustCompile(`\b` + f + `\b`)
		found := false
		for _, l := range pre {
			if re.MatchString(l) {
				found = true
				break
			}
		}
		if !found {
			return nil, p.die("ml_open()'s block-zero preamble (lines %d-%d) does not mention `%s`, so "+
				"it is not the region this phase was written for", start+1, stop, f)
		}
	}
	b0Re := regexp.MustCompile(`\bb0p\b`)
	var outside []string
	for i := loOpen; i < hiOpen; i++ {
		if start <= i && i < stop {
			continue
		}
		if b0Re.MatchString(L[i]) && !strings.HasPrefix(L[i], "    ZERO_BL ") {
			outside = append(outside, fmt.Sprintf("%d", i+1))
		}
	}
	if len(outside) > 0 {
		return nil, p.die("ml_open() says `b0p` outside the preamble at %s", strings.Join(outside, " "))
	}
	b0declV, err := only(func(l string) bool {
		return regexp.MustCompile(`^    ZERO_BL +\*b0p;$`).MatchString(l)
	}, "ml_open()'s `b0p`", loOpen, hiOpen, 1)
	if err != nil {
		return nil, err
	}
	b0decl := b0declV[0]
	npre, err := cutRange(start, stop, "ml_open()'s block-zero preamble",
		"it is the only place in the file that allocates block zero, and every "+
			"write to the header it then fills is inside it")
	if err != nil {
		return nil, err
	}
	if err := drop(L[b0decl]+"\n", "ml_open()'s `b0p` declaration",
		"the preamble this edit has just taken was its only user", 2); err != nil {
		return nil, err
	}
	p.sayf("ml_open()'s block-zero preamble is %d lines and they are gone: the mf_new() that "+
		"took block nr 0, %d of the %d header writes, the set_b0_fname() call, the mf_put() "+
		"and the mf_sync()", npre, nwrite-2, nwrite)

	// THE TWO SURVIVING BLOCKS MOVE DOWN BY ONE.
	for _, e := range []struct{ old, new, what, why string }{
		{z42lit4, z42lit5, "ml_open()'s test that the pointer block is block nr 1",
			"the pointer block is the first block allocated now, so it is block nr 0"},
		{z42lit6, z42lit7, "ml_open()'s pointer to the first data block",
			"the data block is the second block allocated now, so it is block nr 1"},
		{z42lit8, z42lit4, "ml_open()'s test that the data block is block nr 2",
			"the data block is the second block allocated now, so it is block nr 1"},
	} {
		if err := swap(e.old, e.new, e.what, e.why, 1); err != nil {
			return nil, err
		}
	}
	loFind, hiFind, err := body("ml_find_line")
	if err != nil {
		return nil, err
	}
	// only() here is the ASSERTION and not the index: the line must be INSIDE
	// ml_find_line() and nowhere else, so that the replacement below cannot land
	// in some other function that happens to spell it the same way.
	if _, err := only(func(l string) bool { return l == "    bnum = 1;" },
		"ml_find_line()'s root block", loFind, hiFind, 1); err != nil {
		return nil, err
	}
	if err := swap(z42lit9, z42lit10, "ml_find_line()'s root block number",
		"the tree is rooted at the pointer block, which is block nr 0 now", 1); err != nil {
		return nil, err
	}
	loApp, hiApp, err := body("ml_append_int")
	if err != nil {
		return nil, err
	}
	if _, err := only(func(l string) bool {
		return l == "                if (hp-> bh_hashitem.mhi_key  != 1)"
	}, "ml_append_int()'s test for the root pointer block", loApp, hiApp, 1); err != nil {
		return nil, err
	}
	if err := swap(z42lit11, z42lit12, "ml_append_int()'s test for the root pointer block",
		"a split that reaches the root must keep the root where the reader starts, and "+
			"that is block nr 0 now", 1); err != nil {
		return nil, err
	}
	p.say("the two surviving blocks move down by one: the pointer block is block nr 0 and " +
		"the data block block nr 1, in ml_open()'s three tests, ml_find_line()'s root and " +
		"ml_append_int()'s root split")

	cls, err = partition("ml_setflags", []z42Class{
		{"its forward declaration", regexp.MustCompile(`^static void ml_setflags\(buf_T \*buf\);$`)},
		{"its definition", regexp.MustCompile(`^ml_setflags\(buf_T \*buf\)$`)},
		{"a call site", regexp.MustCompile(`^\s*ml_setflags\((curbuf|buf)\);$`)},
	}, "`ml_setflags`")
	if err != nil {
		return nil, err
	}
	cutAt(cls["a call site"])
	if _, err := cutDefn("ml_setflags",
		"its body writes the header's dirty byte, sets BH_DIRTY and calls mf_sync(), "+
			"and every one of the three is write-only state this phase removes"); err != nil {
		return nil, err
	}

	// ==== PART 2 -- THE NEGATIVE BLOCK NUMBERS =================================
	L = lines()
	callLines := func(name string, skip ...string) []int {
		var out []int
	next:
		for i, l := range L {
			if len(callsNotAfterWord([]byte(l), name)) == 0 {
				continue
			}
			for _, s := range skip {
				if strings.HasPrefix(l, s) {
					continue next
				}
			}
			out = append(out, i)
		}
		return out
	}
	mlAppCalls := callLines("ml_append", "static int ml_append(", "ml_append(")
	commaFalse := regexp.MustCompile(`,\s*FALSE\)`)
	var bad []string
	for _, i := range mlAppCalls {
		if !commaFalse.MatchString(L[i]) {
			bad = append(bad, fmt.Sprintf("%d:%s", i+1, strings.TrimSpace(L[i])))
		}
	}
	if len(bad) > 0 {
		return nil, p.die("ml_append() is called at %d sites and %d of them do not pass FALSE for "+
			"`newfile` -- %s", len(mlAppCalls), len(bad), strings.Join(first(bad, 4), " "))
	}
	flagCalls := callLines("ml_append_flags", "static int ml_append_flags(", "ml_append_flags(")
	if len(flagCalls) != 2 {
		return nil, p.die("ml_append_flags() has %d call sites and this phase was written against two",
			len(flagCalls))
	}
	newdataCalls := callLines("ml_new_data", "static bhdr_T *ml_new_data(", "ml_new_data(")
	mfnewCalls := callLines("mf_new", "mf_new(")
	p.sayf("the chain that could make a block number negative, computed: ml_append() has %d "+
		"call sites and ALL %d pass FALSE for `newfile`; ml_append_flags() has %d, one the "+
		"ml_append() that has just been shown FALSE and one ML_APPEND_UNDO; ml_new_data() "+
		"has %d, one FALSE and one `flags & ML_APPEND_NEW`; mf_new() has %d, two FALSE and "+
		"one ml_new_data()'s own parameter.  So `negative` is FALSE at every reachable "+
		"call and mf_trans_add() returns OK before it does anything",
		len(mlAppCalls), len(mlAppCalls), len(flagCalls), len(newdataCalls), len(mfnewCalls))

	for _, e := range []struct{ old, new, what, why string }{
		{"mf_new(memfile_T *mfp, int negative, int page_count)",
			"mf_new(memfile_T *mfp, int page_count)", "mf_new()'s signature",
			"`negative` is FALSE at every call site"},
		{"    if (!negative && freep != nullptr && freep->bh_page_count >= page_count)",
			"    if (freep != nullptr && freep->bh_page_count >= page_count)",
			"mf_new()'s test of the free list", "`negative` is FALSE"},
		{z42lit13, z42lit14, "mf_new()'s negative branch", "the only arm that ever ran is the positive one"},
		{"static bhdr_T *ml_new_data(memfile_T *, int, int);",
			"static bhdr_T *ml_new_data(memfile_T *, int);", "ml_new_data()'s declaration", ""},
		{"ml_new_data(memfile_T *mfp, int negative, int page_count)",
			"ml_new_data(memfile_T *mfp, int page_count)", "ml_new_data()'s signature", ""},
		{"    if ((hp = mf_new(mfp, negative, page_count)) == nullptr)",
			"    if ((hp = mf_new(mfp, page_count)) == nullptr)", "ml_new_data()'s call of mf_new()", ""},
		{"    if ((hp = ml_new_data(mfp, FALSE, 1)) == nullptr)",
			"    if ((hp = ml_new_data(mfp, 1)) == nullptr)", "ml_open()'s call of ml_new_data()", ""},
		{"        if ((hp_new = ml_new_data(mfp, flags & ML_APPEND_NEW, page_count)) == nullptr)",
			"        if ((hp_new = ml_new_data(mfp, page_count)) == nullptr)",
			"ml_append_int()'s call of ml_new_data()",
			"`flags & ML_APPEND_NEW` is 0 at every call of ml_append_flags()"},
		{"    if ((hp = mf_new(mfp, FALSE, 1)) == nullptr)",
			"    if ((hp = mf_new(mfp, 1)) == nullptr)", "ml_new_ptr()'s call of mf_new()", ""},
		{"static int ml_append(linenr_T lnum, char_u *line, colnr_T len, int newfile);",
			"static int ml_append(linenr_T lnum, char_u *line, colnr_T len);",
			"ml_append()'s declaration", ""},
		{"ml_append(linenr_T    lnum, char_u      *line, colnr_T     len, int         newfile)",
			"ml_append(linenr_T    lnum, char_u      *line, colnr_T     len)",
			"ml_append()'s signature", ""},
		{"    return ml_append_flags(lnum, line, len, newfile ? ML_APPEND_NEW : 0);",
			"    return ml_append_flags(lnum, line, len, 0);", "ml_append()'s body",
			"`newfile` is FALSE at every call site, so the flag it chose is never set"},
	} {
		if err := swap(e.old, e.new, e.what, e.why, 1); err != nil {
			return nil, err
		}
	}
	var n int
	t, n = z42SubNotWord(t, `ml_append\(((?:[^()]|\([^()]*\))*), *FALSE\)`, func(m []string) string {
		return "ml_append(" + m[1] + ")"
	})
	if n != len(mlAppCalls) {
		return nil, p.die("%d ml_append() call sites were rewritten and %d were counted", n, len(mlAppCalls))
	}
	p.sayf("ml_append() loses `newfile` at its declaration, its definition and all %d call "+
		"sites, and ml_append_flags() is called with a flag word that can no longer hold "+
		"ML_APPEND_NEW", n)

	for _, e := range []struct{ old, what, why string }{
		{z42lit15, "ml_append_int()'s in-place ML_LOCKED_DIRTY and ML_LOCKED_POS",
			"both bits are written and neither is ever tested"},
		{z42lit16, "ml_append_int()'s split-block ML_LOCKED_DIRTY and ML_LOCKED_POS",
			"both bits are written and neither is ever tested"},
	} {
		if err := drop(e.old, e.what, e.why, 1); err != nil {
			return nil, err
		}
	}

	// ==== PART 3 -- THE DIRTY STATE MACHINE ====================================
	cls, err = partition("bh_flags", []z42Class{
		{"its declaration", regexp.MustCompile(`^    char        bh_flags;$`)},
		{"a write", regexp.MustCompile(`bh_flags (\|)?= `)},
		{"the one read", regexp.MustCompile(`^    flags = hp->bh_flags;$`)},
	}, "`bh_flags`")
	if err != nil {
		return nil, err
	}
	L = lines()
	loPut, hiPut, err := body("mf_put")
	if err != nil {
		return nil, err
	}
	var tests []int
	for i := loPut; i < hiPut; i++ {
		if strings.Contains(L[i], "flags & BH_") {
			tests = append(tests, i)
		}
	}
	if len(tests) != 1 || !strings.Contains(L[tests[0]], "BH_LOCKED") {
		return nil, p.die("the block header flags are tested at %d places and this phase needs exactly "+
			"one, mf_put()'s test of BH_LOCKED", len(tests))
	}
	total := 0
	for _, v := range cls {
		total += len(v)
	}
	p.sayf("BH_DIRTY IS WRITTEN AND NEVER TESTED: `bh_flags` has %d mentions, %d of them "+
		"writes and ONE read, and that read tests BH_LOCKED and nothing else",
		total, len(cls["a write"]))

	cls, err = partition("mf_dirty", []z42Class{
		{"its declaration", regexp.MustCompile(`^    mfdirty_T   mf_dirty;$`)},
		{"a write", regexp.MustCompile(`mf_dirty = MF_DIRTY_`)},
		{"a read", regexp.MustCompile(`mf_dirty (==|!=) MF_DIRTY_`)},
	}, "`mf_dirty`")
	if err != nil {
		return nil, err
	}
	L = lines()
	ifRe := regexp.MustCompile(`^\s*if \(.*mf_dirty (==|!=) MF_DIRTY_\w+\)$`)
	wrRe := regexp.MustCompile(`mf_dirty = MF_DIRTY_`)
	for _, i := range cls["a read"] {
		if !ifRe.MatchString(L[i]) {
			return nil, p.die("the read of `mf_dirty` at line %d is not the condition of an `if`", i+1)
		}
		var inner []int
		for j := i + 2; j < len(L); j++ {
			if strings.TrimSpace(L[j]) != "" {
				inner = append(inner, j)
			}
		}
		if strings.TrimSpace(L[i+1]) != "{" || len(inner) == 0 || !wrRe.MatchString(L[inner[0]]) ||
			strings.TrimSpace(L[inner[0]+1]) != "}" {
			return nil, p.die("the `if` at line %d does not guard exactly one statement, and that "+
				"statement must be another write of `mf_dirty` for the field to be "+
				"write-only", i+1)
		}
	}
	p.sayf("THE MEMFILE DIRTINESS IS A WRITE-ONLY STATE MACHINE: `mf_dirty` has %d writes and "+
		"%d reads, and each read is the condition of an `if` whose only statement writes "+
		"`mf_dirty` again -- so nothing outside the field ever learns its value",
		len(cls["a write"]), len(cls["a read"]))

	cls, err = partition("ML_LOCKED_DIRTY|ML_LOCKED_POS", []z42Class{
		{"its enumerator", regexp.MustCompile(`^enum \{ ML_LOCKED_(DIRTY|POS) = 0x0[48] \};$`)},
		{"set", regexp.MustCompile(`ml_flags \|= `)},
		{"cleared", regexp.MustCompile(`ml_flags &= ~\(ML_LOCKED_DIRTY \| ML_LOCKED_POS\);$`)},
		{"mf_put()'s two arguments", regexp.MustCompile(`^\s*mf_put\(mfp, buf->b_ml\.ml_locked, `)},
	}, "`ML_LOCKED_DIRTY` and `ML_LOCKED_POS`")
	if err != nil {
		return nil, err
	}
	cutAt(append(append([]int{}, cls["set"]...), cls["cleared"]...))
	if err := swap(z42lit17, z42lit18, "ml_find_line()'s release of the locked block",
		"the two bits it passed chose between marking a block dirty, which nothing tests, "+
			"and calling mf_trans_add(), which returns at once", 1); err != nil {
		return nil, err
	}

	// ==== PART 2b -- mf_put() loses both of its state arguments ================
	if err := swap(z42lit19, z42lit20, "mf_put()'s definition",
		"what is left of it is the one thing it did that anything reads: clearing BH_LOCKED", 1); err != nil {
		return nil, err
	}
	L = lines()
	var putCalls []int
	for i, l := range L {
		for _, m := range callsNotAfterWord([]byte(l), "mf_put") {
			if strings.HasPrefix(l[m[0]:], "mf_put(mfp, ") {
				putCalls = append(putCalls, i)
				break
			}
		}
	}
	t, n = z42SubNotWord(t, `mf_put\(mfp, ([\w>.\[\]+ -]+?), \w+, (TRUE|FALSE)\);`, func(m []string) string {
		return "mf_put(" + m[1] + ");"
	})
	if n != len(putCalls) {
		var shown []string
		for _, i := range first(putCalls, 4) {
			shown = append(shown, fmt.Sprintf("%d:%s", i+1, strings.TrimSpace(lines()[i])))
		}
		return nil, p.die("%d mf_put() call sites were rewritten and %d still pass a memfile -- %s",
			n, len(putCalls), strings.Join(shown, " "))
	}
	p.sayf("mf_put() is `mf_put(bhdr_T *hp)`: it clears BH_LOCKED, which is the one bit "+
		"anything tests, and its %d call sites lose the two arguments that chose between "+
		"writing BH_DIRTY and calling mf_trans_add()", n)

	if err := drop(z42lit21, "ml_find_line()'s translation of a negative block number",
		"no block number in any build of zero-vim is ever negative", 1); err != nil {
		return nil, err
	}
	if err := drop(z42lit22, "ml_find_line()'s `bnum2`", "its one use has gone", 1); err != nil {
		return nil, err
	}
	if err := drop(z42lit23, "mf_trans_add()'s declaration", "", 1); err != nil {
		return nil, err
	}
	ntrans, err := cutDefn("mf_trans_add", "it returned OK before doing anything unless a block "+
		"number was negative, and none ever is")
	if err != nil {
		return nil, err
	}
	n2, err := cutDefn("mf_trans_del", "its one call site was the arm under `bnum < 0`")
	if err != nil {
		return nil, err
	}
	ntrans += n2

	for _, f := range []string{"mf_trans", "mf_blocknr_min", "mf_neg_count"} {
		if k := mentions(f); k > 4 {
			return nil, p.die("`%s` has %d mentions and everything that used it has gone", f, k)
		}
	}
	if err := swap("    if (nr >= mfp->mf_blocknr_max || nr <= mfp->mf_blocknr_min)",
		"    if (nr >= mfp->mf_blocknr_max || nr < 0)", "mf_get()'s bounds test",
		"`mf_blocknr_min` is -1 from mf_open() onwards and only the negative branch of "+
			"mf_new() ever moved it, so `nr <= -1` is `nr < 0`", 1); err != nil {
		return nil, err
	}
	if err := swap(z42lit24, z42lit25, "mf_free()'s negative-block arm",
		"no block number is ever negative", 1); err != nil {
		return nil, err
	}
	for _, e := range []struct{ old, what string }{
		{z42lit26, "mf_open()'s initialisation of mf_trans"},
		{z42lit27, "mf_open()'s initialisation of mf_blocknr_min"},
		{z42lit28, "mf_open()'s initialisation of mf_neg_count"},
		{z42lit29, "mf_close()'s free of mf_trans"},
		{z42lit30, "the `mf_trans` field"},
		{z42lit31, "the `mf_blocknr_min` field"},
		{z42lit32, "the `mf_neg_count` field"},
	} {
		if err := drop(e.old, e.what, "", 1); err != nil {
			return nil, err
		}
	}
	p.sayf("the negative-block machinery is gone: mf_trans_add() and mf_trans_del() (%d lines), "+
		"the three memfile fields that served them, mf_get()'s lower bound and mf_free()'s "+
		"negative arm", ntrans)

	if err := drop(z42lit33, "the MF_DIRTY_YES_NOSYNC that is set around a buffer reload",
		"nothing reads it but the line that puts it back", 1); err != nil {
		return nil, err
	}
	if err := drop(z42lit34, "the MF_DIRTY_YES_NOSYNC that is read back",
		"its setter has just gone", 1); err != nil {
		return nil, err
	}
	if err := swap(z42lit35, z42lit36, "mf_open()'s initialisation of mf_dirty", "", 1); err != nil {
		return nil, err
	}
	if err := swap(z42lit37, z42lit38, "mf_new()'s two dirty marks",
		"neither is ever tested", 1); err != nil {
		return nil, err
	}
	if err := drop(z42lit39, "the `mf_dirty` field", "it is write-only", 1); err != nil {
		return nil, err
	}
	if err := drop(z42lit40, "`mfdirty_T`", "the one field of that type has gone", 1); err != nil {
		return nil, err
	}

	if k := mentions("mf_sync"); k != 1 {
		return nil, p.die("`mf_sync` has %d mentions and the edit has left it exactly one, its own "+
			"definition -- the ml_open() call went with the preamble and the ml_setflags() "+
			"call with the function", k)
	}
	if _, err := cutDefn("mf_sync", "its body writes `mf_dirty` and returns FAIL, and it has no "+
		"caller left"); err != nil {
		return nil, err
	}

	if _, _, err := body("ml_find_line"); err != nil {
		return nil, err
	}
	cls, err = partition("dirty", []z42Class{
		{"its declaration", regexp.MustCompile(`^    int         dirty;$`)},
		{"a write", regexp.MustCompile(`^\s*dirty = (TRUE|FALSE);$`)},
	}, "ml_find_line()'s `dirty`")
	if err != nil {
		return nil, err
	}
	cutAt(append(append([]int{}, cls["its declaration"]...), cls["a write"]...))

	// ==== PART 4 -- pe_old_lnum ================================================
	cls, err = partition("pe_old_lnum", []z42Class{
		{"its declaration", regexp.MustCompile(`^    linenr_T    pe_old_lnum;$`)},
		{"a write", regexp.MustCompile(`^\s*(pp|pp_new)->pb_pointer\[[^]]*\]\.pe_old_lnum = \w+;$`)},
	}, "`pe_old_lnum`")
	if err != nil {
		return nil, err
	}
	p.sayf("`pe_old_lnum` IS WRITE-ONLY: %d writes and not one read.  tools/deadfields.py "+
		"cannot see it -- that tool takes a field named nowhere outside its own type -- so "+
		"the field goes in the EDIT, with its writes", len(cls["a write"]))
	cutAt(cls["a write"])
	if err := drop(z42lit41, "the `pe_old_lnum` field", "", 1); err != nil {
		return nil, err
	}
	L = lines()
	emptyRe := regexp.MustCompile(`^\s*if \(lnum_(left|right)( != 0)?\)$`)
	var empties []int
	for i := 0; i < len(L)-2; i++ {
		if emptyRe.MatchString(L[i]) && strings.TrimSpace(L[i+1]) == "{" &&
			strings.TrimSpace(L[i+2]) == "}" {
			empties = append(empties, i)
		}
	}
	if len(empties) != 4 {
		return nil, p.die("%d `if (lnum_left|lnum_right)` blocks are empty now and this phase was written "+
			"against four", len(empties))
	}
	var flat []int
	for _, i := range empties {
		flat = append(flat, i, i+1, i+2)
	}
	cutAt(flat)
	if _, err := partition("lnum_left|lnum_right", []z42Class{
		{"its declaration", regexp.MustCompile(`^        linenr_T lnum_(left|right);$`)},
		{"a write", regexp.MustCompile(`^\s*lnum_(left|right) = (lnum \+ [12]|0);$`)},
	}, "ml_append_int()'s `lnum_left` and `lnum_right`"); err != nil {
		return nil, err
	}
	if err := drop(z42lit42, "the branch that computed lnum_left and lnum_right",
		"both are written and never read once `pe_old_lnum` has gone, and that is a "+
			"warning tools/deadsweep.py does not act on", 1); err != nil {
		return nil, err
	}
	if mentions("lnum_left") != 2 || mentions("lnum_right") != 2 {
		return nil, p.die("`lnum_left` has %d mentions and `lnum_right` %d, and the branch this edit has "+
			"just taken should leave each with its declaration and its one reset",
			mentions("lnum_left"), mentions("lnum_right"))
	}
	if err := drop(z42lit43, "the `lnum_left` declaration", "", 1); err != nil {
		return nil, err
	}
	if err := drop(z42lit44, "the `lnum_right` declaration", "", 1); err != nil {
		return nil, err
	}
	if err := drop(z42lit45, "the reset of lnum_left and lnum_right", "", 1); err != nil {
		return nil, err
	}

	declRe := regexp.MustCompile(`^static int      mf_dont_release  = FALSE ;$`)
	cls, err = partition("mf_dont_release", []z42Class{
		{"its declaration, with its only value", declRe},
		{"a read", regexp.MustCompile(`(\|\| mf_dont_release\)| && !mf_dont_release\))`)},
	}, "`mf_dont_release`")
	if err != nil {
		return nil, err
	}
	L = lines()
	assignRe := regexp.MustCompile(`\bmf_dont_release\b\s*=`)
	var assigns []string
	for i, l := range L {
		if assignRe.MatchString(l) && !contains(cls["its declaration, with its only value"], i) {
			assigns = append(assigns, fmt.Sprintf("%d", i+1))
		}
	}
	if len(assigns) > 0 {
		return nil, p.die("`mf_dont_release` is assigned at %s, so it is not the constant this phase takes",
			strings.Join(assigns, " "))
	}
	total = 0
	for _, v := range cls {
		total += len(v)
	}
	p.sayf("`mf_dont_release` IS A CONSTANT: %d mentions, its own declaration with `FALSE` and "+
		"%d reads, and NOT ONE assignment anywhere in the file -- and no warning gcc emits "+
		"covers a file-scope object in either direction", total, len(cls["a read"]))
	if err := swap(" || mf_dont_release)", ")", "ml_get_buf()'s test of mf_dont_release",
		"it is FALSE for ever, so the disjunct is the other operand", 1); err != nil {
		return nil, err
	}
	if err := swap(" && !mf_dont_release)", ")", "ml_find_line()'s test of mf_dont_release",
		"it is FALSE for ever, so the conjunct is the other operands", 1); err != nil {
		return nil, err
	}
	if err := drop(z42lit46, "the `mf_dont_release` declaration",
		"both of its readers have gone", 1); err != nil {
		return nil, err
	}

	// ---- WHAT IS LEFT FOR THE SWEEP -------------------------------------------
	var leftNames []string
	for name := range z42Left {
		leftNames = append(leftNames, name)
	}
	sort.Strings(leftNames)
	for _, name := range leftNames {
		if mentions(name) == 0 {
			return nil, p.die("the edit has already taken `%s`, which it leaves for the sweep (%s) -- so "+
				"the two halves of this phase no longer divide as its check states", name, z42Left[name])
		}
	}
	p.sayf("%d names are left standing for tools/sweep.sh: %s.  Each is a kind that sweep "+
		"finds; nothing that is WRITTEN is among them, because no tool in tools/ can see a "+
		"write", len(z42Left), strings.Join(leftNames, ", "))

	for _, name := range []string{"mf_dirty", "mfdirty_T", "MF_DIRTY_NO", "MF_DIRTY_YES",
		"MF_DIRTY_YES_NOSYNC", "mf_sync", "mf_trans", "mf_trans_add", "mf_trans_del",
		"mf_blocknr_min", "mf_neg_count", "pe_old_lnum", "mf_dont_release",
		"lnum_left", "lnum_right", "bnum2", "newfile"} {
		if k := mentions(name); k != 0 {
			return nil, p.die("`%s` still has %d mentions and the edit owns every one of them", name, k)
		}
	}
	if k := mentions("b0p"); k != 2 {
		return nil, p.die("`b0p` has %d mentions and the edit leaves two, both of them inside "+
			"set_b0_fname(), which tools/deadsweep.py takes", k)
	}
	for _, sig := range []string{"mf_new(memfile_T *mfp, int page_count)",
		"ml_new_data(memfile_T *mfp, int page_count)",
		"ml_append(linenr_T    lnum, char_u      *line, colnr_T     len)",
		"mf_put(bhdr_T *hp)"} {
		if strings.Count(t, sig) != 1 {
			return nil, p.die("`%s` is not in the output exactly once, so a signature this phase "+
				"narrowed is not the one it meant", sig)
		}
	}

	// ---- the paragraphs the cuts emptied --------------------------------------
	if runsBefore != 0 {
		return nil, p.die("the input already holds %d runs of two blank lines, and this file has none -- "+
			"so the arithmetic below could not tell this edit's from the input's", runsBefore)
	}
	L = lines()
	var made []int
	for i := 1; i < len(L); i++ {
		if L[i] == "" && L[i-1] == "" {
			made = append(made, i)
		}
	}
	cutAt(made)
	p.sayf("%d paragraphs were emptied outright and one blank line goes from each", len(made))
	if r := blankRuns(t); r != 0 {
		return nil, p.die("the edit left %d runs of two blank lines", r)
	}
	L = lines()
	var d2 []int
	for i, l := range L {
		if dirRe.MatchString(l) {
			d2 = append(d2, i)
		}
	}
	okd := len(d2) == len(directivesBefore)
	for i := range d2 {
		if d2[i] != d2[0]+i {
			okd = false
		}
	}
	if !okd {
		return nil, p.die("the output does not have the same %d contiguous directives the input had -- "+
			"this phase adds none and removes none", len(directivesBefore))
	}
	// The check states what the EDIT took and what the SWEEP took, separately, and
	// this is how it can: the text the edit hands on, kept beside the text it was
	// handed.
	if err := os.WriteFile(state+"/edit.c", []byte(t), 0o644); err != nil {
		return nil, p.die("%v", err)
	}
	p.sayf("%d -> %d lines before the sweep, %d fewer, the %d `#include`s untouched and still "+
		"contiguous, and no run of two blank lines",
		linesBefore, len(L)-1, linesBefore-(len(L)-1), len(d2))
	return []byte(t), nil
}

// z42SubNotWord is Python's `re.subn(r'(?<!\w)<pat>', repl, t)`: every match
// whose preceding byte is not a word character, rewritten in ONE pass over the
// original text.
func z42SubNotWord(t, pat string, repl func([]string) string) (string, int) {
	re := regexp.MustCompile(pat)
	var out strings.Builder
	last, n := 0, 0
	for _, m := range re.FindAllStringSubmatchIndex(t, -1) {
		if m[0] > 0 && isWordByte(t[m[0]-1]) {
			continue
		}
		groups := make([]string, len(m)/2)
		for i := range groups {
			if m[2*i] >= 0 {
				groups[i] = t[m[2*i]:m[2*i+1]]
			}
		}
		out.WriteString(t[last:m[0]])
		out.WriteString(repl(groups))
		last = m[1]
		n++
	}
	out.WriteString(t[last:])
	return out.String(), n
}
