package edit

import (
	"fmt"
	"io"
	"os"
	"regexp"
	"sort"
	"strings"
)

func init() { registerArgs("zero43", Zero43) }

var (
	z43Lit     = regexp.MustCompile(`"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'`)
	z43Head    = regexp.MustCompile(`^([A-Za-z_]\w*)\s*\(`)
	z43IncLine = regexp.MustCompile(`^ *# *include `)
	z43DirLine = regexp.MustCompile(`^ *#`)
)

// z43Names are the names this edit partitions, plus the three it introduces.
var z43Names = []string{"blocknr_T", "mf_hashitem_T", "mf_hashtab_T", "mhi_key", "mhi_next",
	"mhi_prev", "bh_hashitem", "pe_bnum", "ip_bnum", "pe_page_count",
	"bh_page_count", "mf_blocknr_max", "mf_free_first", "mf_used_last",
	"mf_hash", "ml_root", "pe_block", "ip_block"}

var (
	z43HashImpl = []string{"mf_hash_init", "mf_hash_free", "mf_hash_find", "mf_hash_add_item",
		"mf_hash_rem_item", "mf_hash_grow"}
	z43HashWrap = []string{"mf_ins_hash", "mf_rem_hash", "mf_find_hash"}
	z43FreeList = []string{"mf_ins_free", "mf_rem_free"}
)

// Zero43 turns a block number into a reference: `pe_bnum` and `ip_bnum` become
// `bhdr_T *`, `memline_T` gains `ml_root`, and the hash table that turned an
// integer into a page goes with the free list and `mf_blocknr_max`.
func Zero43(text []byte, w io.Writer, args []string) ([]byte, error) {
	p := ph{"refblocks", w}
	if len(args) != 1 {
		return nil, p.die("usage: edit zero43 <file> <state-dir>")
	}
	state := args[0]
	t := string(text)
	nIn := strings.Count(t, "\n")

	lines := func() []string { return strings.Split(t, "\n") }
	mentions := func(s, name string) int {
		return len(regexp.MustCompile(`\b(?:`+name+`)\b`).FindAllString(s, -1))
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
	swap := func(old, new, what, why string) error {
		c := strings.Count(t, old)
		if c != 1 {
			return p.die("%s occurs %d times, expected %d -- %s", what, c, 1, why)
		}
		t = strings.ReplaceAll(t, old, new)
		return nil
	}
	// heads: every definition in this tree's ONE shape -- a name at column 0 with
	// `(` after it and `{` at column 0 on the next line, closed by `}` at column 0.
	type head struct {
		a, b int
		name string
	}
	headsOf := func(src string) []head {
		L := strings.Split(src, "\n")
		var out []head
		for i, l := range L {
			m := z43Head.FindStringSubmatch(l)
			if m != nil && i+1 < len(L) && L[i+1] == "{" {
				end := i + 1
				for end < len(L) && L[end] != "}" {
					end++
				}
				if end < len(L) {
					out = append(out, head{i, end, m[1]})
				}
			}
		}
		return out
	}
	// owners: {function name: how many of its lines say `name`}.  THIS IS THE
	// PHASE'S UNIT OF ASSERTION -- WHERE a name is said and not how often, because
	// the phase before this one moves the counts.
	owners := func(name string) map[string]int {
		L := lines()
		hs := headsOf(t)
		who := func(i int) string {
			for _, h := range hs {
				if h.a <= i && i <= h.b {
					return h.name
				}
			}
			return "<file scope>"
		}
		re := regexp.MustCompile(`\b` + name + `\b`)
		d := map[string]int{}
		for i, l := range L {
			if re.MatchString(l) {
				d[who(i)]++
			}
		}
		return d
	}
	places := func(name string, expect []string, what string) error {
		got := owners(name)
		var gk []string
		for k := range got {
			gk = append(gk, k)
		}
		sort.Strings(gk)
		ek := append([]string{}, expect...)
		sort.Strings(ek)
		if strings.Join(gk, "\x00") != strings.Join(ek, "\x00") {
			return p.die("`%s` is said in %s and this phase accounts for %s -- %s",
				name, z43PyList(gk), z43PyList(ek), what)
		}
		var parts []string
		for _, k := range gk {
			parts = append(parts, fmt.Sprintf("%s %d", k, got[k]))
		}
		p.sayf("`%s` is said in %d places and nowhere else: %s",
			name, len(got), strings.Join(parts, ", "))
		return nil
	}
	cut := func(a, b, what string) (int, error) {
		for _, s := range []struct{ v, side string }{{a, "start"}, {b, "end"}} {
			if c := strings.Count(t, s.v); c != 1 {
				return 0, p.die("the %s of %s occurs %d times and a cut needs exactly one",
					s.side, what, c)
			}
		}
		i, j := strings.Index(t, a), strings.Index(t, b)
		if i >= j {
			return 0, p.die("%s: the start is not above the end", what)
		}
		n := strings.Count(t[i:j], "\n")
		t = t[:i] + t[j:]
		return n, nil
	}

	// ---- 0. the file this edit is handed --------------------------------------
	literals := z43Lit.FindAllString(t, -1)
	var inlit []string
	for _, n := range z43Names {
		re := regexp.MustCompile(`\b` + n + `\b`)
		for _, s := range literals {
			if re.MatchString(s) {
				inlit = append(inlit, n)
				break
			}
		}
	}
	if len(inlit) > 0 {
		return nil, p.die("%s appear inside a string literal, so a line-oriented partition would read "+
			"data as code", strings.Join(inlit, ", "))
	}
	for _, n := range []string{"ml_root", "pe_block", "ip_block"} {
		if k := mentions(t, n); k != 0 {
			return nil, p.die("`%s` is already said %d times, and this phase is what introduces it", n, k)
		}
	}
	p.sayf("%d string and character literals, and not one of them holds any of the %d names "+
		"this edit partitions or the 3 it introduces", len(literals), len(z43Names)-3)

	var incs, directives []int
	for i, l := range lines() {
		if z43IncLine.MatchString(l) {
			incs = append(incs, i)
		}
		if z43DirLine.MatchString(l) {
			directives = append(directives, i)
		}
	}
	if len(incs) != len(directives) || len(incs) == 0 {
		return nil, p.die("the input has %d preprocessor directives and %d of them are `#include`, and "+
			"this phase adds none and removes none", len(directives), len(incs))
	}
	boundary := incs[0]
	p.sayf("the input is %d lines with %d `#include`s and no other directive, the first at "+
		"line %d -- the line between the core and the host", nIn, len(incs), boundary+1)

	// ---- 1. where every name this phase removes is said -----------------------
	for _, pl := range []struct {
		name   string
		expect []string
		what   string
	}{
		{"mhi_key", []string{"<file scope>", "mf_new", "ml_open", "ml_append_int",
			"mf_hash_find", "mf_hash_add_item", "mf_hash_rem_item", "mf_hash_grow"},
			"it is the hash key, the number mf_new() hands out and the number the tree stored"},
		{"bh_hashitem", []string{"<file scope>", "mf_new", "ml_open", "ml_append_int"},
			"it is the hash item embedded in every block header"},
		{"pe_bnum", []string{"<file scope>", "ml_open", "ml_find_line", "ml_append_int"},
			"it is the block number a pointer entry stores"},
		{"ip_bnum", []string{"<file scope>", "ml_find_line", "ml_append_int", "ml_delete_int",
			"ml_lineadd"}, "it is the block number a stack entry remembers"},
		{"pe_page_count", []string{"<file scope>", "ml_open", "ml_find_line", "ml_append_int"},
			"it is mf_get()'s third argument, stored so the lookup could size the page"},
		{"bh_page_count", []string{"<file scope>", "mf_new", "mf_alloc_bhdr", "ml_append_int"},
			"it is the page count a block header carries"},
		{"mf_blocknr_max", []string{"<file scope>", "mf_open", "mf_new", "mf_get"},
			"it is the counter the block numbers came from"},
		{"mf_free_first", append([]string{"<file scope>", "mf_open", "mf_close", "mf_new"}, z43FreeList...),
			"it is the head of the free list, which is keyed by block number"},
		{"mf_used_last", []string{"<file scope>", "mf_open", "mf_ins_used", "mf_rem_used"},
			"it is the tail of the used list"},
	} {
		if err := places(pl.name, pl.expect, pl.what); err != nil {
			return nil, err
		}
	}

	L := lines()
	peRe := regexp.MustCompile(`\bpe_page_count\b`)
	peWr := regexp.MustCompile(`\bpe_page_count\s*=`)
	var peReads []int
	for i, l := range L {
		if peRe.MatchString(l) && !peWr.MatchString(l) && !strings.Contains(l, "int         pe_page_count;") {
			peReads = append(peReads, i)
		}
	}
	if len(peReads) != 1 || !strings.Contains(L[peReads[0]], "page_count =") {
		return nil, p.die("`pe_page_count` has %d readers and this phase rests on its having one, the "+
			"argument mf_get() is about to lose", len(peReads))
	}
	p.sayf("`pe_page_count` is read ONCE in the whole file -- %s -- and that read is the third "+
		"argument of mf_get(); every other mention of it is a write", strings.TrimSpace(L[peReads[0]]))

	ulRe := regexp.MustCompile(`\bmf_used_last\b`)
	ulWr := regexp.MustCompile(`\bmf_used_last\s*=`)
	var lastw, lastr []int
	for i, l := range L {
		if ulRe.MatchString(l) {
			lastw = append(lastw, i)
			if !ulWr.MatchString(l) && !strings.Contains(l, "bhdr_T      *mf_used_last;") {
				lastr = append(lastr, i)
			}
		}
	}
	if len(lastr) > 0 {
		var shown []string
		for _, i := range lastr {
			shown = append(shown, strings.TrimSpace(L[i]))
		}
		return nil, p.die("`mf_used_last` is read at %s, and this phase removes it as a write-only field",
			strings.Join(shown, ", "))
	}
	p.sayf("`mf_used_last` IS WRITE-ONLY: %d mentions, its declaration and %d writes and not "+
		"one read -- phase 42 took ml_setflags(), which was the last thing that walked the "+
		"used list backwards.  No warning gcc emits covers a struct member in either "+
		"direction, so it goes in this edit with its writes", len(lastw), len(lastw)-1)

	callIn := func(name string) []string {
		hs := headsOf(t)
		who := func(i int) string {
			for _, h := range hs {
				if h.a <= i && i <= h.b {
					return h.name
				}
			}
			return "<file scope>"
		}
		re := regexp.MustCompile(`\b` + name + `\s*\(`)
		seen := map[string]bool{}
		for i, l := range lines() {
			if re.MatchString(l) {
				seen[who(i)] = true
			}
		}
		delete(seen, "<file scope>")
		delete(seen, name)
		var out []string
		for k := range seen {
			out = append(out, k)
		}
		sort.Strings(out)
		return out
	}
	insIn, remIn := callIn("mf_ins_hash"), callIn("mf_rem_hash")
	if strings.Join(insIn, ",") != "mf_get,mf_new" || strings.Join(remIn, ",") != "mf_free,mf_get" {
		return nil, p.die("the hash is inserted into from %s and removed from from %s, and this phase "+
			"rests on mf_new() and mf_get() being the only insertions and mf_free() and "+
			"mf_get() the only removals", z43PyList(insIn), z43PyList(remIn))
	}
	p.sayf("THE HASH HOLDS EVERY LIVE BLOCK: it is inserted into by %s and removed from by "+
		"%s, and mf_get() does both in one breath to move a block to the head of the used "+
		"list -- so a lookup by a number the tree stored cannot miss, and the pointer it "+
		"would have returned is the same answer",
		strings.Join(insIn, " and "), strings.Join(remIn, " and "))

	// ---- 2. the types ---------------------------------------------------------
	for _, s := range []struct{ old, new, what, why string }{
		{z43s0Old, z43s0New, z43s0What, z43s0Why},
		{z43s1Old, z43s1New, z43s1What, z43s1Why},
		{z43s2Old, z43s2New, z43s2What, z43s2Why},
		{z43s3Old, z43s3New, z43s3What, z43s3Why},
		{z43s4Old, z43s4New, z43s4What, z43s4Why},
	} {
		if err := swap(s.old, s.new, s.what, s.why); err != nil {
			return nil, err
		}
	}

	// ---- 3. the memfile -------------------------------------------------------
	// Eleven functions go, and they go HERE and not to tools/sweep.sh: every one
	// names a type or a field removed above, so leaving them for the sweep would
	// leave a file that does not compile for the sweep to ask gcc about.
	all := append(append(append([]string{}, z43HashWrap...), z43FreeList...), z43HashImpl...)
	for _, name := range all {
		re := regexp.MustCompile(`(?m)^static [\w *]*` + name + `\([^\n]*\);\n`)
		m := re.FindStringIndex(t)
		if m == nil {
			return nil, p.die("`%s` has no forward declaration in the one shape this tree writes them", name)
		}
		t = t[:m[0]] + t[m[1]:]
	}
	p.sayf("%d forward declarations go: %s", len(all), strings.Join(all, ", "))

	for _, s := range []struct{ old, new, what, why string }{
		{z43s5Old, z43s5New, z43s5What, z43s5Why},
		{z43s6Old, z43s6New, z43s6What, z43s6Why},
		{z43s7Old, z43s7New, z43s7What, z43s7Why},
		{z43s8Old, z43s8New, z43s8What, z43s8Why},
		{z43s9Old, z43s9New, z43s9What, z43s9Why},
	} {
		if err := swap(s.old, s.new, s.what, s.why); err != nil {
			return nil, err
		}
	}
	n, err := cut(z43c10A, z43c10B, z43c10What)
	if err != nil {
		return nil, err
	}
	p.sayf("the three one-line wrappers go, %d lines: %s", n, strings.Join(z43HashWrap, ", "))

	for _, s := range []struct{ old, new, what, why string }{
		{z43s11Old, z43s11New, z43s11What, z43s11Why},
		{z43s12Old, z43s12New, z43s12What, z43s12Why},
		{z43s13Old, z43s13New, z43s13What, z43s13Why},
	} {
		if err := swap(s.old, s.new, s.what, s.why); err != nil {
			return nil, err
		}
	}
	n, err = cut(z43c14A, z43c14B, z43c14What)
	if err != nil {
		return nil, err
	}
	p.sayf("the free list and the hash implementation go, %d lines: %s, the two MHT_ "+
		"enumerators and %s", n, strings.Join(z43FreeList, ", "), strings.Join(z43HashImpl, ", "))

	// ---- 4. the memline -------------------------------------------------------
	for _, s := range []struct{ old, new, what, why string }{
		{z43s15Old, z43s15New, z43s15What, z43s15Why},
		{z43s16Old, z43s16New, z43s16What, z43s16Why},
		{z43s17Old, z43s17New, z43s17What, z43s17Why},
		{z43s18Old, z43s18New, z43s18What, z43s18Why},
		{z43s19Old, z43s19New, z43s19What, z43s19Why},
		{z43s20Old, z43s20New, z43s20What, z43s20Why},
		{z43s21Old, z43s21New, z43s21What, z43s21Why},
		{z43s22Old, z43s22New, z43s22What, z43s22Why},
		{z43s23Old, z43s23New, z43s23What, z43s23Why},
		{z43s24Old, z43s24New, z43s24What, z43s24Why},
		{z43s25Old, z43s25New, z43s25What, z43s25Why},
		{z43s26Old, z43s26New, z43s26What, z43s26Why},
		{z43s27Old, z43s27New, z43s27What, z43s27Why},
		{z43s28Old, z43s28New, z43s28What, z43s28Why},
		{z43s29Old, z43s29New, z43s29What, z43s29Why},
		{z43s30Old, z43s30New, z43s30What, z43s30Why},
		{z43s31Old, z43s31New, z43s31What, z43s31Why},
	} {
		if err := swap(s.old, s.new, s.what, s.why); err != nil {
			return nil, err
		}
	}

	// The seven remaining stores, as a partition over the two labels: every store
	// of a pointer entry's block is one of these two, and a leftover refuses.
	for _, e := range []struct{ old, new, side string }{
		{"pe_bnum = bnum_left;", "pe_block = bp_left;", "left"},
		{"pe_bnum = bnum_right;", "pe_block = bp_right;", "right"},
	} {
		c := strings.Count(t, e.old)
		if c < 1 {
			return nil, p.die("no store of the %s label is left, and a split has two sides", e.side)
		}
		t = strings.ReplaceAll(t, e.old, e.new)
		p.sayf("%d stores of the %s label", c, e.side)
	}
	for _, old := range []string{z43pc1, z43pc2, z43pc3} {
		if strings.Count(t, old) < 1 {
			return nil, p.die("a page-count store this phase accounts for is not there: %s",
				z43PyRepr(old))
		}
		t = regexp.MustCompile(`\n *`+regexp.QuoteMeta(strings.TrimRight(old, "\n"))).
			ReplaceAllString(t, "")
	}
	c := strings.Count(t, "mf_get(mfp, ip->ip_bnum, 1)")
	if c < 1 {
		return nil, p.die("no stack-walk fetch is left, and the three loops that climb the tree all make one")
	}
	t = strings.ReplaceAll(t, "mf_get(mfp, ip->ip_bnum, 1)", "mf_get(mfp, ip->ip_block)")
	p.sayf("%d stack-walk fetches become mf_get(mfp, ip->ip_block)", c)

	// ---- 5. what is left, as a partition --------------------------------------
	gone := append([]string{"blocknr_T", "mf_hashitem_T", "mf_hashtab_T", "mhi_key", "mhi_next", "mhi_prev",
		"mht_mask", "mht_count", "mht_buckets", "mht_small_buckets", "mht_fixed",
		"MHT_INIT_SIZE", "MHT_LOG_LOAD_FACTOR", "MHT_GROWTH_FACTOR", "bh_hashitem",
		"pe_bnum", "ip_bnum", "pe_page_count", "bh_page_count", "mf_blocknr_max",
		"mf_free_first", "mf_used_last", "mf_hash", "page_count_left",
		"page_count_right", "bnum_left", "bnum_right"}, all...)
	var left []string
	for _, n := range gone {
		if k := mentions(t, n); k > 0 {
			left = append(left, fmt.Sprintf("%s %d", n, k))
		}
	}
	if len(left) > 0 {
		lead := "names this phase removes are"
		if len(left) == 1 {
			lead = "a name this phase removes is"
		}
		return nil, p.die("%s still said: %s.  If they are `blocknr_T`, `mf_hashitem_T` and "+
			"`mf_hashtab_T` at one mention each, the input is UNSWEPT: phase 42 leaves "+
			"`mf_hash_free_all` standing for tools/sweep.sh and its forward declaration "+
			"names all three (`need 43 swept` in pipes/zero.stages)",
			lead, strings.Join(left, ", "))
	}
	p.sayf("%d names are gone from the whole file: the two hash types and blocknr_T, their "+
		"nine fields and three enumerators, the four block-number fields, the two page "+
		"counts, the free list, the used tail and the eleven functions", len(gone))

	for _, pl := range []struct {
		name   string
		expect []string
		what   string
	}{
		{"ml_root", []string{"<file scope>", "ml_open", "ml_append_int", "ml_find_line"},
			"the root is set in ml_open(), tested in ml_append_int() and is where every " +
				"descent starts"},
		{"pe_block", []string{"<file scope>", "ml_open", "ml_find_line", "ml_append_int"},
			"exactly where pe_bnum was"},
		{"ip_block", []string{"<file scope>", "ml_find_line", "ml_append_int", "ml_delete_int",
			"ml_lineadd"}, "exactly where ip_bnum was"},
	} {
		if err := places(pl.name, pl.expect, pl.what); err != nil {
			return nil, err
		}
	}

	standing := []string{"e_didnt_get_block_nr_zero", "e_didnt_get_block_nr_one"}
	for _, name := range standing {
		if k := mentions(t, name); k != 1 {
			return nil, p.die("`%s` has %d mentions and this edit leaves it at one, its own definition, "+
				"which is what the sweep takes", name, k)
		}
	}
	p.sayf("%d names are left standing for tools/sweep.sh: %s -- each is an unreferenced "+
		"file-scope object, which is -Wunused-variable and the one kind of dead thing in "+
		"this phase that a tool can see", len(standing), strings.Join(standing, ", "))

	// ---- 6. the shape of what is written out ----------------------------------
	if r := blankRuns(t); r > 0 {
		return nil, p.die("%d runs of two blank lines -- no verification tier can see paragraphing "+
			"(CLAUDE.md, *Verification tiers*)", r)
	}
	var incs2, dirs2 []int
	for i, l := range lines() {
		if z43IncLine.MatchString(l) {
			incs2 = append(incs2, i)
		}
		if z43DirLine.MatchString(l) {
			dirs2 = append(dirs2, i)
		}
	}
	if len(incs2) != len(incs) || len(dirs2) != len(incs2) {
		return nil, p.die("the output has %d directives and %d of them are `#include`, against %d and %d",
			len(dirs2), len(incs2), len(directives), len(incs))
	}
	for i := range incs2 {
		if incs2[i] != incs2[0]+i {
			return nil, p.die("the eleven `#include`s are not contiguous any more")
		}
	}
	nOut := strings.Count(t, "\n")
	p.sayf("%d -> %d lines before the sweep, %d fewer, the %d `#include`s untouched and still "+
		"contiguous, and no run of two blank lines", nIn, nOut, nIn-nOut, len(incs2))

	// The edit leaves its own output beside the input, so the check can say what
	// the EDIT removed and what the SWEEP removed separately.
	if err := os.WriteFile(state+"/edit.c", []byte(t), 0o644); err != nil {
		return nil, p.die("%v", err)
	}
	if err := os.WriteFile(state+"/boundary-in", []byte(fmt.Sprintf("%d\n", boundary+1)), 0o644); err != nil {
		return nil, p.die("%v", err)
	}
	return []byte(t), nil
}

// z43PyList is Python's str() of a list of strings, which the refusals quote.
func z43PyList(s []string) string {
	out := make([]string, len(s))
	for i, v := range s {
		out[i] = "'" + v + "'"
	}
	return "[" + strings.Join(out, ", ") + "]"
}

// z43PyRepr is Python's %r of a string that may hold a newline.
func z43PyRepr(s string) string {
	return "'" + strings.ReplaceAll(strings.ReplaceAll(s, "\\", "\\\\"), "\n", "\\n") + "'"
}
