package edit

import (
	"fmt"
	"io"
	"os"
	"regexp"
	"sort"
	"strings"
)

func init() { registerArgs("zero44", Zero44) }

const z44DbLineMax = 64

// z44Bit is the mark, which used to be the top bit of an offset.  Zero phase 9's
// macro expansion left it spelled out, and this is THE TEXT and not a description
// of it.
const z44Bit = "((unsigned)1 << ((sizeof(unsigned) * 8) - 1))"

// z44Gone are the five names the leaf stops having, and the one flag whose only
// caller goes with ml_flush_line()'s fallback.
var z44Gone = []string{"db_free", "db_txt_start", "db_txt_end", "db_index", "ML_APPEND_MARK"}

// z44Homes is where a mention of a gone name is allowed to be in the INPUT.  A
// mention anywhere else is a rule this edit does not have, and it refuses rather
// than leaving it.
var z44Homes = []string{"<file scope>", "ml_open", "ml_get_buf", "ml_append_int", "ml_delete_int",
	"ml_setmarked", "ml_firstmarked", "ml_clearmarked", "ml_flush_line", "ml_new_data"}

var (
	z44Decl     = regexp.MustCompile(`^\s+(?:static\s+)?[A-Za-z_][A-Za-z0-9_]*(?:\s+\*?[A-Za-z_][A-Za-z0-9_]*)*\s+\*?([A-Za-z_][A-Za-z0-9_]*)\s*(?:=[^;]*)?;$`)
	z44FnHead   = regexp.MustCompile(`^([a-zA-Z_][a-zA-Z0-9_]*)\(`)
	z44MlFlags  = regexp.MustCompile(`ml_flags \|=`)
	z44DlText   = regexp.MustCompile(`\.dl_text\s*=[^=]`)
	z44Interior = regexp.MustCompile(`\(char_u? \*\)dp[a-z_]* *\+`)
)

// z44NotDecl: `return OK;` has the shape of a declaration and is not one.  The
// first word of a declaration is a type, never one of these.
var z44NotDecl = []string{"return", "goto", "break", "continue", "case", "else", "do"}

// Zero44 de-pages the leaf: a data block stops being an index of byte offsets
// over a text arena and becomes `DATA_LN db_line[DB_LINE_MAX]`, so a line's text
// is its own allocation valid for the lifetime of the process.
func Zero44(text []byte, w io.Writer, args []string) ([]byte, error) {
	p := ph{"leaf", w}
	if len(args) != 1 {
		return nil, p.die("usage: edit zero44 <file> <state-dir>")
	}
	state := args[0]
	lines := strings.Split(string(text), "\n")
	nIn := len(lines)
	t0 := string(text)

	// die here prints on stdout and exits 1, which is the heredoc's own `die`:
	// this phase writes its refusals into the report and not onto stderr.
	die := func(format string, a ...interface{}) error {
		fmt.Fprintf(w, "  leaf         %s\n", fmt.Sprintf(format, a...))
		return fmt.Errorf("")
	}
	say := func(format string, a ...interface{}) {
		fmt.Fprintf(w, "  leaf         %s\n", fmt.Sprintf(format, a...))
	}
	mentions := func(s, name string) int {
		return len(regexp.MustCompile(`\b`+regexp.QuoteMeta(name)+`\b`).FindAllString(s, -1))
	}

	// --- finding things ------------------------------------------------------
	fn := func(name string) (int, int, error) {
		var hits []int
		for i, l := range lines {
			if strings.HasPrefix(l, name+"(") {
				hits = append(hits, i)
			}
		}
		if len(hits) != 1 {
			return 0, 0, die("%s is not a definition head exactly once (%d), so this edit cannot "+
				"find the function it is about", name, len(hits))
		}
		head := hits[0] - 1
		if !strings.HasPrefix(strings.TrimLeft(lines[head], " \t"), "static") {
			return 0, 0, die("%s has no `static` line above its name", name)
		}
		i := hits[0]
		for lines[i] != "{" {
			i++
		}
		depth := 0
		for {
			depth += strings.Count(lines[i], "{") - strings.Count(lines[i], "}")
			if depth == 0 {
				return head, i, nil
			}
			i++
		}
	}
	one := func(lo, hi int, pat string) (int, error) {
		re := regexp.MustCompile(pat)
		var hits []int
		for i := lo; i <= hi; i++ {
			if re.MatchString(lines[i]) {
				hits = append(hits, i)
			}
		}
		if len(hits) != 1 {
			return 0, die("%s matches %d lines where this edit needs exactly one",
				z43PyRepr(pat), len(hits))
		}
		return hits[0], nil
	}
	firstMatch := func(lo, hi int, pat string) (int, error) {
		re := regexp.MustCompile(pat)
		for i := lo; i <= hi; i++ {
			if re.MatchString(lines[i]) {
				return i, nil
			}
		}
		return 0, die("%s matches nothing where this edit needs it", z43PyRepr(pat))
	}
	// stmtEnd: last index of the statement starting at a, following any `else`
	// chain.
	stmtEnd := func(a int) int {
		i := a
		for {
			depth, seen, j := 0, false, i
			for {
				depth += strings.Count(lines[j], "{") - strings.Count(lines[j], "}")
				seen = seen || strings.Contains(lines[j], "{")
				if (seen && depth == 0) || (!seen && strings.HasSuffix(strings.TrimRight(lines[j], " \t"), ";")) {
					break
				}
				j++
			}
			k := j + 1
			for k < len(lines) && strings.TrimSpace(lines[k]) == "" {
				k++
			}
			if k < len(lines) && strings.HasPrefix(strings.TrimSpace(lines[k]), "else") {
				i = k
				continue
			}
			return j
		}
	}
	enclosing := func(i int) string {
		for j := i; j >= 0; j-- {
			if lines[j] == "}" {
				return "<file scope>"
			}
			m := z44FnHead.FindStringSubmatch(lines[j])
			if m != nil && j > 0 && strings.HasPrefix(strings.TrimLeft(lines[j-1], " \t"), "static") {
				return m[1]
			}
		}
		return "<file scope>"
	}
	// carry: the `ml_flags |=` statements inside [lo,hi], re-indented.  They are
	// CARRIED and not written: ML_LOCKED_DIRTY and ML_LOCKED_POS are zero phase
	// 42's to remove, and an edit that spelled them would break on it.
	carry := func(lo, hi, indent int) []string {
		var out []string
		for i := lo; i <= hi; i++ {
			if z44MlFlags.MatchString(lines[i]) {
				out = append(out, strings.Repeat(" ", indent)+strings.TrimSpace(lines[i]))
			}
		}
		return out
	}
	// lastArg: line i's call to callee loses its last argument, or gets `new` in
	// its place.  The argument is found by PLACE and never by its text, because
	// what it says is zero phase 42's and 43's to change and what it IS is this
	// phase's.
	lastArg := func(i int, callee, new string) (string, error) {
		m := regexp.MustCompile(regexp.QuoteMeta(callee) + `\(`).FindStringIndex(lines[i])
		if m == nil {
			return "", die("line %d does not call %s", i+1, callee)
		}
		depth, j := 1, m[1]
		var commas []int
		for {
			c := lines[i][j]
			if c == '(' {
				depth++
			} else if c == ')' {
				depth--
				if depth == 0 {
					break
				}
			} else if c == ',' && depth == 1 {
				commas = append(commas, j)
			}
			j++
		}
		if len(commas) == 0 {
			return "", die("%s is called with one argument, so there is no last one to name", callee)
		}
		last := commas[len(commas)-1]
		was := lines[i][last+1 : j]
		add := ""
		if new != "" {
			add = ", " + new
		}
		lines[i] = lines[i][:last] + add + lines[i][j:]
		return was, nil
	}

	// --- the partition, before anything is changed ---------------------------
	before := map[string]int{}
	var strays []string
	for _, name := range append(append([]string{}, z44Gone...), z44Bit) {
		pat := `\b` + regexp.QuoteMeta(name) + `\b`
		if name == z44Bit {
			pat = regexp.QuoteMeta(name)
		}
		re := regexp.MustCompile(pat)
		var hits []int
		for i, l := range lines {
			if re.MatchString(l) {
				hits = append(hits, i)
			}
		}
		if len(hits) == 0 {
			return nil, die("%s is not in the input at all, so this phase has already run or the "+
				"leaf is not the one it was written against", name)
		}
		if name == z44Bit {
			before[name] = strings.Count(t0, z44Bit)
		} else {
			before[name] = mentions(t0, name)
		}
		for _, i := range hits {
			if !contains(z44Homes, enclosing(i)) {
				strays = append(strays, fmt.Sprintf("%s in %s (line %d)", name, enclosing(i), i+1))
			}
		}
	}
	if len(strays) > 0 {
		return nil, die("a name this phase removes is mentioned where it has no rule: %s",
			strings.Join(first(strays, 5), "; "))
	}
	sum := 0
	for _, n := range z44Gone {
		sum += before[n]
	}
	say("the input mentions %s -- %d times between them, the top bit %d more -- and every "+
		"mention is in the struct, the enumerator or one of the eight memline functions "+
		"this edit rewrites", strings.Join(z44Gone, ", "), sum, before[z44Bit])

	// --- 1. the typedef, the record and the block ----------------------------
	i := z44Index(lines, "typedef struct data_block       DATA_BL;")
	lines = append(lines[:i+1], append(append([]string{}, z44b0...), lines[i+1:]...)...)

	a := z44Index(lines, "struct data_block")
	b := a
	for lines[b] != "};" {
		b++
	}
	var members []string
	for _, l := range lines[a+2 : b] {
		if strings.TrimSpace(l) != "" {
			members = append(members, strings.TrimSpace(l))
		}
	}
	if len(members) != 6 || members[len(members)-1] != "unsigned    db_index[1];" {
		return nil, die("struct data_block is not the header-index-arena block this phase replaces: %s",
			strings.Join(members, " "))
	}
	lines = z44Splice(lines, a, b+1, z44b1)

	// --- 2. one line's text is its own allocation ----------------------------
	lo, _, err := fn("ml_open")
	if err != nil {
		return nil, err
	}
	lines = z44Splice(lines, lo, lo, z44b2)

	// --- 3. ml_new_data has no page count ------------------------------------
	i, err = one(0, len(lines)-1, `^static bhdr_T \*ml_new_data\(memfile_T \*`)
	if err != nil {
		return nil, err
	}
	was, err := lastArg(i, "ml_new_data", "")
	if err != nil {
		return nil, err
	}
	if strings.TrimSpace(was) != "int" {
		return nil, die("ml_new_data's prototype does not end in a plain `int` parameter: %s", was)
	}
	lo, hi, err := fn("ml_new_data")
	if err != nil {
		return nil, err
	}
	if was, err = lastArg(lo+1, "ml_new_data", ""); err != nil {
		return nil, err
	}
	if !strings.Contains(was, "page_count") {
		return nil, die("ml_new_data's last parameter is not the page count: %s", was)
	}
	k, err := one(lo, hi, `mf_new\(`)
	if err != nil {
		return nil, err
	}
	if was, err = lastArg(k, "mf_new", "1"); err != nil {
		return nil, err
	}
	if !strings.Contains(was, "page_count") {
		return nil, die("ml_new_data does not hand its page count to mf_new: %s", was)
	}
	a, err = one(lo, hi, `^    dp->db_txt_start = dp->db_txt_end = `)
	if err != nil {
		return nil, err
	}
	b, err = one(lo, hi, `^    dp->db_free = `)
	if err != nil {
		return nil, err
	}
	if b != a+1 {
		return nil, die("ml_new_data does not set the arena on two consecutive lines")
	}
	lines = z44Splice(lines, a, b+1, nil)

	// --- 4. ml_open's one empty line -----------------------------------------
	if lo, hi, err = fn("ml_open"); err != nil {
		return nil, err
	}
	if a, err = one(lo, hi, `^    dp->db_index\[0\] = --dp->db_txt_start;$`); err != nil {
		return nil, err
	}
	if b, err = one(lo, hi, `^    \*\(\(char_u \*\)dp \+ dp->db_txt_start\) = NUL;$`); err != nil {
		return nil, err
	}
	lines = z44Splice(lines, a, b+1, z44b3)
	if lo, hi, err = fn("ml_open"); err != nil {
		return nil, err
	}
	if k, err = one(lo, hi, `ml_new_data\(`); err != nil {
		return nil, err
	}
	if _, err = lastArg(k, "ml_new_data", ""); err != nil {
		return nil, err
	}

	// --- 5. ml_get_buf reads a record ----------------------------------------
	if lo, hi, err = fn("ml_get_buf"); err != nil {
		return nil, err
	}
	if a, err = one(lo, hi, `^        idx = lnum - buf->b_ml\.ml_locked_low;$`); err != nil {
		return nil, err
	}
	if b, err = one(lo, hi, `^        buf->b_ml\.ml_line_len = end - start;$`); err != nil {
		return nil, err
	}
	lines = z44Splice(lines, a, b+1, z44b4)

	// --- 6. ml_append_int ----------------------------------------------------
	if lo, hi, err = fn("ml_append_int"); err != nil {
		return nil, err
	}
	if a, err = one(lo, hi, `^    int         line_count;$`); err != nil {
		return nil, err
	}
	lines = z44Splice(lines, a+1, a+1, z44b5)

	if lo, hi, err = fn("ml_append_int"); err != nil {
		return nil, err
	}
	if a, err = one(lo, hi, `^    space_needed = len \+ `); err != nil {
		return nil, err
	}
	lines = z44Splice(lines, a, a+1, z44b6)

	if lo, hi, err = fn("ml_append_int"); err != nil {
		return nil, err
	}
	if a, err = one(lo, hi, `db_free < space_needed && db_idx == line_count - 1`); err != nil {
		return nil, err
	}
	lines[a] = z44s0

	if lo, hi, err = fn("ml_append_int"); err != nil {
		return nil, err
	}
	if a, err = one(lo, hi, `^    if \(\(long\)dp->db_free >= space_needed\)$`); err != nil {
		return nil, err
	}
	if k, err = firstMatch(a, hi, `if \(flags & ML_APPEND_MARK\)`); err != nil {
		return nil, err
	}
	lines = z44Splice(lines, a, stmtEnd(k)+1, z44b7)

	if lo, hi, err = fn("ml_append_int"); err != nil {
		return nil, err
	}
	if a, err = one(lo, hi, `^            lines_moved = line_count - db_idx - 1;$`); err != nil {
		return nil, err
	}
	if b, err = one(lo, hi, `offsetof\(DATA_BL, db_index\)`); err != nil {
		return nil, err
	}
	lines = z44Splice(lines, a, b+1, z44b8)

	if lo, hi, err = fn("ml_append_int"); err != nil {
		return nil, err
	}
	if k, err = one(lo, hi, `ml_new_data\(`); err != nil {
		return nil, err
	}
	if _, err = lastArg(k, "ml_new_data", ""); err != nil {
		return nil, err
	}

	if lo, hi, err = fn("ml_append_int"); err != nil {
		return nil, err
	}
	if a, err = one(lo, hi, `^        if \(!in_left\)$`); err != nil {
		return nil, err
	}
	b = stmtEnd(a)
	for _, headPat := range []string{`^        if \(lines_moved\)$`, `^        if \(in_left\)$`} {
		k := b + 1
		for strings.TrimSpace(lines[k]) == "" {
			k++
		}
		if !regexp.MustCompile(headPat).MatchString(lines[k]) {
			return nil, die("the split arm is not the three statements this edit replaces, at %s", lines[k])
		}
		b = stmtEnd(k)
	}
	lines = z44Splice(lines, a, b+1, z44b9)

	// --- 7. ml_delete_int ----------------------------------------------------
	if lo, hi, err = fn("ml_delete_int"); err != nil {
		return nil, err
	}
	if a, err = one(lo, hi, `^    line_start = `); err != nil {
		return nil, err
	}
	b = stmtEnd(a + 1)
	if !strings.Contains(strings.Join(lines[a:b+1], "\n"), "db_index[idx - 1]") {
		return nil, die("the line_size computation is not the two-armed one this edit removes")
	}
	lines = z44Splice(lines, a, b+1, nil)

	if lo, hi, err = fn("ml_delete_int"); err != nil {
		return nil, err
	}
	if a, err = one(lo, hi, `^        text_start = dp->db_txt_start;$`); err != nil {
		return nil, err
	}
	if b, err = one(lo, hi, `^        --\(dp->db_line_count\);$`); err != nil {
		return nil, err
	}
	lines = z44Splice(lines, a, b+1, z44b10)

	// --- 8. the mark is a field ----------------------------------------------
	if lo, hi, err = fn("ml_setmarked"); err != nil {
		return nil, err
	}
	if a, err = one(lo, hi, `^    dp->db_index\[lnum - curbuf->b_ml\.ml_locked_low\] \|= `); err != nil {
		return nil, err
	}
	lines[a] = z44s1
	for _, name := range []string{"ml_firstmarked", "ml_clearmarked"} {
		if lo, hi, err = fn(name); err != nil {
			return nil, err
		}
		if a, err = one(lo, hi, `^            if \(\(dp->db_index\[i\]\) & `); err != nil {
			return nil, err
		}
		if b, err = one(lo, hi, `^                \(dp->db_index\[i\]\) &= `); err != nil {
			return nil, err
		}
		lines = z44Splice(lines, a, b+1, z44b11)
	}

	// --- 9. ml_flush_line stores the pointer ---------------------------------
	if lo, hi, err = fn("ml_flush_line"); err != nil {
		return nil, err
	}
	if a, err = one(lo, hi, `^            idx = lnum - buf->b_ml\.ml_locked_low;$`); err != nil {
		return nil, err
	}
	if k, err = firstMatch(a, hi, `^            if \(\(int\)dp->db_free >= extra\)$`); err != nil {
		return nil, err
	}
	b = stmtEnd(k)
	kept := carry(a, b, 12)
	repl := append([]string{}, z44b12...)
	if len(kept) > 0 {
		repl = append(repl, "")
		repl = append(repl, kept...)
	}
	lines = z44Splice(lines, a, b+1, repl)
	if lo, hi, err = fn("ml_flush_line"); err != nil {
		return nil, err
	}
	if a, err = one(lo, hi, `^        vim_free\(new_line\);$`); err != nil {
		return nil, err
	}
	lines = z44Splice(lines, a, a+2, nil)

	// --- 10. ML_APPEND_MARK has no caller left -------------------------------
	markRe := regexp.MustCompile(`\bML_APPEND_MARK\b`)
	var left []int
	for i, l := range lines {
		if markRe.MatchString(l) {
			left = append(left, i)
		}
	}
	if len(left) != 1 || !strings.HasPrefix(lines[left[0]], "enum { ML_APPEND_MARK") {
		return nil, die("ML_APPEND_MARK is still mentioned %d times and not only by its own "+
			"enumerator, so the flag has a caller this edit did not see", len(left))
	}
	lines = z44Splice(lines, left[0], left[0]+1, nil)

	// --- 11. the locals the rewrite stopped using ----------------------------
	// COMPUTED, not listed: a declaration whose name is left mentioned once in
	// its own function is mentioned only by itself.
	var droppedLocals []string
	for _, name := range []string{"ml_open", "ml_get_buf", "ml_append_int", "ml_delete_int",
		"ml_setmarked", "ml_firstmarked", "ml_clearmarked", "ml_flush_line", "ml_new_data"} {
		for {
			lo, hi, err = fn(name)
			if err != nil {
				return nil, err
			}
			body := strings.Join(lines[lo:hi+1], "\n")
			found := false
			for i := lo; i <= hi; i++ {
				m := z44Decl.FindStringSubmatch(lines[i])
				if m == nil {
					continue
				}
				if contains(z44NotDecl, strings.Fields(lines[i])[0]) {
					continue
				}
				if mentions(body, m[1]) == 1 {
					droppedLocals = append(droppedLocals, name+":"+m[1])
					lines = z44Splice(lines, i, i+1, nil)
					found = true
					break
				}
			}
			if !found {
				break
			}
		}
	}
	say("%d locals the rewrite stopped using, found by counting their own name: %s",
		len(droppedLocals), strings.Join(droppedLocals, " "))

	// --- the partition again, on the output ----------------------------------
	t := strings.Join(lines, "\n")
	for _, name := range z44Gone {
		if k := mentions(t, name); k != 0 {
			return nil, die("%s survives the edit with %d mentions", name, k)
		}
	}
	if k := strings.Count(t, z44Bit); k != 0 {
		return nil, die("the stolen top bit survives the edit %d times", k)
	}
	if z44Interior.MatchString(strings.ReplaceAll(t, "(char *)dp", "(char_u *)dp")) {
		return nil, die("an interior pointer into a data block survives the edit")
	}
	if strings.Contains(t, "offsetof(DATA_BL") {
		return nil, die("a data block is still being measured with offsetof")
	}
	if strings.Count(t, "offsetof(PTR_BL") != 1 {
		return nil, die("ml_new_ptr's offsetof is not where it was: a POINTER block is still a " +
			"page and is not this phase's")
	}
	for _, name := range []string{"dl_text", "dl_len", "dl_marked", "DB_LINE_MAX", "ml_alloc_line"} {
		if mentions(t, name) == 0 {
			return nil, die("%s is not in the output, so the replacement did not land", name)
		}
	}

	// The lifetime rule, as a partition over every assignment to a record's text.
	got := map[string]int{}
	total := 0
	for i, l := range lines {
		if z44DlText.MatchString(l) {
			got[enclosing(i)]++
			total++
		}
	}
	want := map[string]int{"ml_open": 1, "ml_append_int": 3, "ml_flush_line": 1}
	if !z44SameCount(got, want) {
		return nil, die("a record's text is assigned in %s, and the lifetime rule this phase pins "+
			"says it is assigned in exactly %s", z44PyDict(got), z44PyDict(want))
	}
	var wk []string
	for k := range want {
		wk = append(wk, k)
	}
	sort.Strings(wk)
	var shown []string
	for _, k := range wk {
		shown = append(shown, fmt.Sprintf("%s x%d", k, want[k]))
	}
	say("a record's text is assigned in exactly %d places -- %s -- and freed in none, "+
		"so a pointer ml_get() returned stays readable for the life of the process",
		total, strings.Join(shown, ", "))

	var gone strings.Builder
	for _, n := range append(append([]string{}, z44Gone...), z44Bit) {
		fmt.Fprintf(&gone, "%s\t%d\n", n, before[n])
	}
	if err := os.WriteFile(state+"/gone", []byte(gone.String()), 0o644); err != nil {
		return nil, die("%v", err)
	}
	if err := os.WriteFile(state+"/dbmax", []byte(fmt.Sprintf("%d\n", z44DbLineMax)), 0o644); err != nil {
		return nil, die("%v", err)
	}
	say("%d -> %d lines: the leaf is an array of %d records and a line's text is its own "+
		"allocation", nIn, len(lines), z44DbLineMax)
	return []byte(t), nil
}

func z44Index(lines []string, s string) int {
	for i, l := range lines {
		if l == s {
			return i
		}
	}
	return -1
}

// z44Splice is Python's `lines[a:b] = rows`.
func z44Splice(lines []string, a, b int, rows []string) []string {
	out := make([]string, 0, len(lines)-(b-a)+len(rows))
	out = append(out, lines[:a]...)
	out = append(out, rows...)
	return append(out, lines[b:]...)
}

func z44SameCount(a, b map[string]int) bool {
	if len(a) != len(b) {
		return false
	}
	for k, v := range a {
		if b[k] != v {
			return false
		}
	}
	return true
}

// z44PyDict is Python's str() of a {str: int} dict, which the refusal quotes.
func z44PyDict(m map[string]int) string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	out := make([]string, len(keys))
	for i, k := range keys {
		out[i] = fmt.Sprintf("'%s': %d", k, m[k])
	}
	return "{" + strings.Join(out, ", ") + "}"
}
