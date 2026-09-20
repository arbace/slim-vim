package edit

import (
	"fmt"
	"io"
	"os"
	"regexp"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

func init() { registerArgs("zero35", Zero35) }

var (
	z35Seed    = "void *malloc(usize n);"
	z35CastFd1 = regexp.MustCompile(`\(int\)write\(1, `)
)

// Zero35 makes the core call nothing but the host: `malloc`, `free` and `write`
// become `host_alloc`, `host_free` and `host_write`, three prototypes above the
// boundary and three definitions below it.
//
// ITS ANCHORS ARE A PARTITION AND NOT A COUNT, and phase 34 is why.  They first
// asserted `malloc` at 2 mentions, `free` at 3 and `write` at 2 -- the counts
// measured on one boundary -- and phase 34's realloc rewrite took two of them to
// 4 and 5.  A count is a fact about a tree that WAS measured; a partition is a
// fact about the tree that arrives.
func Zero35(text []byte, w io.Writer, args []string) ([]byte, error) {
	p := ph{"hostcall", w}
	if len(args) != 1 {
		return nil, p.die("usage: edit zero35 <file> <state-dir>")
	}
	state := args[0]
	t := string(text)

	mentions := func(s, name string) int {
		return len(regexp.MustCompile(`\b`+name+`\b`).FindAllString(s, -1))
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
		if c := strings.Count(t, old); c != 1 {
			return p.die("%s occurs %d times, expected 1 -- %s", what, c, why)
		}
		t = strings.Replace(t, old, new, 1)
		return nil
	}
	shortName := func(l string) string { return z36Name.ReplaceAllString(l, "$1") }

	L := strings.Split(t, "\n")
	linesBefore := len(L) - 1
	runsBefore := blankRuns(t)

	// ---- 0. the boundary -----------------------------------------------------
	var directives []int
	for i, l := range L {
		if z36Dir.MatchString(l) {
			directives = append(directives, i)
		}
	}
	if len(directives) != 11 {
		return nil, p.die("the file holds %d preprocessor directives and this phase was written against "+
			"the eleven `#include`s phase 21 left", len(directives))
	}
	for i := range directives {
		if directives[i] != directives[0]+i {
			return nil, p.die("the eleven directives are not eleven consecutive lines")
		}
	}
	for _, i := range directives {
		if !z36Inc.MatchString(L[i]) {
			return nil, p.die("a directive is not an `#include <...>` of a system header, and no phase may " +
				"add one")
		}
	}
	boundary := directives[0]
	p.sayf("the boundary is line %d, the first of the eleven `#include`s, and there is not a "+
		"directive above it", boundary+1)

	// ---- 1. the core's block of ordinary declarations, FOUND rather than assumed
	var seed []int
	for i, l := range L[:boundary] {
		if l == z35Seed {
			seed = append(seed, i)
		}
	}
	if len(seed) != 1 {
		return nil, p.die("the core does not declare `void *malloc(usize n);` exactly once, so this " +
			"phase has not been handed the file it was written for")
	}
	lo, hi := seed[0], seed[0]
	for lo > 0 && z36IsDecl(L[lo-1]) {
		lo--
	}
	for hi+1 < boundary && z36IsDecl(L[hi+1]) {
		hi++
	}
	blockBefore := append([]string{}, L[lo:hi+1]...)
	for _, line := range z35Go {
		if !contains(blockBefore, line) {
			return nil, p.die("`%s` is not in the core's block of ordinary declarations, which is %s",
				line, strings.Join(blockBefore, " / "))
		}
	}
	if L[lo-1] != "" || L[hi+1] != "" {
		return nil, p.die("the block is not a paragraph of its own -- line %d is %s and line %d is %s",
			lo, cutil.PyRepr(L[lo-1]), hi+2, cutil.PyRepr(L[hi+1]))
	}
	names := make([]string, len(blockBefore))
	for i, l := range blockBefore {
		names[i] = shortName(l)
	}
	p.sayf("the core's block of ordinary declarations is lines %d-%d, %d of them, and every "+
		"one is a libc function the core calls: %s",
		lo+1, hi+1, len(blockBefore), strings.Join(names, " "))

	// ---- 2. the three names, above the boundary and below it -----------------
	core := strings.Join(L[:boundary], "\n")
	host := strings.Join(L[boundary:], "\n")
	ncalls := map[string]int{}
	for _, r := range []struct {
		name  string
		nhost int
		why   string
	}{
		{"malloc", 0, "lalloc(), and whatever else has come to ask for memory"},
		{"free", 1, "vim_free(), update_wincolor() and the rest; and " +
			"format_overflow_error() below the boundary"},
		{"write", 1, "mch_write(); and host_message() below the boundary"},
	} {
		occ := mentions(core, r.name)
		paren := len(callsNotAfterWord([]byte(core), r.name))
		if occ != paren {
			return nil, p.die("`%s` has %d mentions above the boundary and only %d of them are followed by "+
				"`(` -- every one must be the declaration or a call, and this phase will not "+
				"rewrite what it cannot classify", r.name, occ, paren)
		}
		if paren < 2 {
			return nil, p.die("`%s` is %d call-shaped mentions above the boundary, and this phase needs its "+
				"declaration and at least one call -- %s", r.name, paren, r.why)
		}
		if k := mentions(host, r.name); k != r.nhost {
			return nil, p.die("`%s` has %d mentions below the boundary and this phase was written against "+
				"%d -- %s", r.name, k, r.nhost, r.why)
		}
		ncalls[r.name] = paren - 1
	}
	// `write` LOSES ITS FIRST ARGUMENT, so its rewrite is not a rename and the
	// descriptor has to be CHECKED: host_write(s, len) writes to the screen, and
	// the host is where fd 1 is named.
	fd1 := 0
	for _, m := range regexp.MustCompile(`write\(1, `).FindAllStringIndex(core, -1) {
		if m[0] > 0 && isWordByte(core[m[0]-1]) {
			continue
		}
		fd1++
	}
	if fd1 != ncalls["write"] {
		return nil, p.die("%d of the core's %d write() calls are to fd 1 -- host_write() takes no "+
			"descriptor, so a write to anything else is a call this phase cannot move",
			fd1, ncalls["write"])
	}
	for _, name := range []string{"host_alloc", "host_free", "host_write"} {
		if mentions(t, name) > 0 {
			return nil, p.die("`%s` is already a name in this file", name)
		}
	}
	s := "s"
	if ncalls["malloc"] == 1 {
		s = ""
	}
	p.sayf("the partition holds: above the boundary `malloc` is its declaration and %d call%s, "+
		"`free` its declaration and %d, `write` its declaration and %d -- every one to fd 1 "+
		"-- and NOTHING above the boundary mentions any of the three in any other way.  "+
		"Below it: 0, 1 and 1, which is where they are going",
		ncalls["malloc"], s, ncalls["free"], ncalls["write"])

	// ---- 3. the three declarations leave the core's block --------------------
	var blockAfter []string
	for _, l := range blockBefore {
		if !contains(z35Go, l) {
			blockAfter = append(blockAfter, l)
		}
	}
	oldBlock := strings.Join(blockBefore, "\n") + "\n"
	dropped := 0
	if len(blockAfter) > 0 {
		if err := swap(oldBlock, strings.Join(blockAfter, "\n")+"\n",
			"the core's block of declarations",
			"the three this phase owns come out of it and the rest stay where they are"); err != nil {
			return nil, err
		}
		dropped = len(z35Go)
	} else {
		if err := swap(oldBlock+"\n", "", "the core's block of declarations AND its trailing "+
			"blank line",
			"the block is empty now, and a paragraph separator with nothing to separate "+
				"is the run of two blank lines this file does not have"); err != nil {
			return nil, err
		}
		dropped = len(blockBefore) + 1
	}

	// ---- 4. and three arrive at the end of the core -> host boundary block ---
	if err := swap("static void host_message(const char *msg, int len, int err);\n",
		"static void host_message(const char *msg, int len, int err);\n"+
			strings.Join(z35Protos, "\n")+"\n",
		"the last of the core -> host prototypes phase 25 left",
		"the boundary is ONE block, and these three belong at the end of it rather than "+
			"wherever a declaration happened to fit"); err != nil {
		return nil, err
	}

	// ---- 5. every call site, COMPUTED ----------------------------------------
	// The core half ONLY: the host below calls free() and write() for itself and
	// must not be touched.
	L = strings.Split(t, "\n")
	bnd := -1
	for i, l := range L {
		if z36Dir.MatchString(l) {
			bnd = i
			break
		}
	}
	core, host = strings.Join(L[:bnd], "\n"), strings.Join(L[bnd:], "\n")
	done := map[string]int{}
	var n int
	cb := []byte(core)
	cb, n = subNotAfterWord(cb, "malloc", "host_alloc")
	done["malloc"] = n
	cb, n = subNotAfterWord(cb, "free", "host_free")
	done["free"] = n
	core = string(cb)
	// The CAST FORM IS TAKEN FIRST so the bare form cannot strip the call out
	// from under it: host_write() returns int, having narrowed inside the host
	// where the libc type is visible.
	cast := len(z35CastFd1.FindAllString(core, -1))
	core = z35CastFd1.ReplaceAllString(core, "host_write(")
	bare := 0
	var out strings.Builder
	last := 0
	for _, m := range regexp.MustCompile(`write\(1, `).FindAllStringIndex(core, -1) {
		if m[0] > 0 && isWordByte(core[m[0]-1]) {
			continue
		}
		out.WriteString(core[last:m[0]])
		out.WriteString("host_write(")
		last = m[1]
		bare++
	}
	out.WriteString(core[last:])
	core = out.String()
	done["write"] = cast + bare
	for _, name := range []string{"malloc", "free", "write"} {
		if done[name] != ncalls[name] {
			return nil, p.die("%d `%s` call sites were rewritten and section 2 counted %d",
				done[name], name, ncalls[name])
		}
		if mentions(core, name) > 0 {
			return nil, p.die("`%s` still appears above the boundary after its call sites were rewritten",
				name)
		}
	}
	t = core + "\n" + host
	s = "s"
	if done["malloc"] == 1 {
		s = ""
	}
	p.sayf("%d call site%s rewritten to `host_alloc`, %d to `host_free` and %d to `host_write` "+
		"(%d of them shedding an `(int)` cast that the host now does) -- every one COMPUTED "+
		"from the text, and no mention of any of the three left above the boundary",
		done["malloc"], s, done["free"], done["write"], cast)

	// ---- 6. the host defines the three, below the boundary -------------------
	if err := swap("    int\nmain(int argc, char **argv)\n{\n",
		z35Defs+"    int\nmain(int argc, char **argv)\n{\n",
		"the launcher's head, the last function in the file",
		"the three definitions go immediately above it, below host_exit and host_message "+
			"and in the order their prototypes are written"); err != nil {
		return nil, err
	}

	// ---- 7. what the file is now ---------------------------------------------
	L = strings.Split(t, "\n")
	boundary = -1
	for i, l := range L {
		if z36Dir.MatchString(l) {
			boundary = i
			break
		}
	}
	core, host = strings.Join(L[:boundary], "\n"), strings.Join(L[boundary:], "\n")
	for _, r := range []struct {
		name         string
		ncore, nhost int
	}{{"malloc", 0, 1}, {"free", 0, 2}, {"write", 0, 2}} {
		if mentions(core, r.name) != r.ncore || mentions(host, r.name) != r.nhost {
			return nil, p.die("`%s` ends at %d mentions above the boundary and %d below, expected %d and "+
				"%d", r.name, mentions(core, r.name), mentions(host, r.name), r.ncore, r.nhost)
		}
	}
	for _, r := range []struct{ name, was string }{
		{"host_alloc", "malloc"}, {"host_free", "free"}, {"host_write", "write"},
	} {
		want := ncalls[r.was] + 2
		if k := mentions(t, r.name); k != want {
			return nil, p.die("`%s` has %d mentions, expected %d -- its prototype, the %d call sites it "+
				"took over from `%s` and its definition", r.name, k, want, ncalls[r.was], r.was)
		}
	}
	have := append([]string{}, L[lo:lo+len(blockAfter)]...)
	if strings.Join(have, "\x00") != strings.Join(blockAfter, "\x00") {
		return nil, p.die("the ordinary declarations left above the boundary are %s and the input's "+
			"block minus the three is %s", z36Or(have), z36Or(blockAfter))
	}
	if L[lo-1] != "" || L[lo+len(blockAfter)] != "" {
		return nil, p.die("what is left of the block is not a paragraph of its own")
	}
	// AND NOWHERE ELSE ABOVE THE BOUNDARY, which needs one more test than DECL:
	// macro expansion left ordinary STATEMENTS at column 0 that match a
	// declaration's shape exactly, and what tells them apart is the line above.
	var stray []string
	for i := 0; i < boundary; i++ {
		if z36IsDecl(L[i]) && (L[i-1] == "" || z36IsDecl(L[i-1])) &&
			!(lo <= i && i < lo+len(blockAfter)) {
			stray = append(stray, fmt.Sprintf("%d:%s", i+1, L[i]))
		}
	}
	if len(stray) > 0 {
		return nil, p.die("an ordinary declaration is above the boundary and outside the block: %s",
			strings.Join(first(stray, 4), " / "))
	}
	if err := os.WriteFile(state+"/block-before",
		[]byte(strings.Join(blockBefore, "\n")+"\n"), 0o644); err != nil {
		return nil, p.die("%v", err)
	}
	var after strings.Builder
	for _, l := range blockAfter {
		after.WriteString(l + "\n")
	}
	if err := os.WriteFile(state+"/block-after", []byte(after.String()), 0o644); err != nil {
		return nil, p.die("%v", err)
	}
	if len(blockAfter) > 0 {
		var left []string
		for _, l := range blockAfter {
			left = append(left, shortName(l))
		}
		p.sayf("the core's block of ordinary declarations is %d lines and was %d: %s remain, "+
			"and each is a libc function some LATER phase owns",
			len(blockAfter), len(blockBefore), strings.Join(left, " "))
	} else {
		p.sayf("THE CORE'S BLOCK OF ORDINARY DECLARATIONS IS EMPTY: it was %d lines and it is "+
			"now none.  Above the first `#include` there is no declaration that is not "+
			"`static`, so the core names no libc function at all and every outward call it "+
			"makes is a `musl_` or a `host_`", len(blockBefore))
	}

	// DECLARATION BEFORE USE, COMPUTED.
	for i, name := range []string{"host_alloc", "host_free", "host_write"} {
		proto := z35Protos[i]
		var pr, df, uses []int
		for j, l := range L {
			if l == proto {
				pr = append(pr, j)
			}
			if strings.HasPrefix(l, name+"(") && j+1 < len(L) && L[j+1] == "{" {
				df = append(df, j)
			}
		}
		for j, l := range L {
			if len(callsNotAfterWord([]byte(l), name)) > 0 && !contains(pr, j) && !contains(df, j) {
				uses = append(uses, j)
			}
		}
		if len(pr) != 1 || len(df) != 1 || len(uses) == 0 {
			return nil, p.die("`%s` has %d prototypes, %d definitions and %d call sites",
				name, len(pr), len(df), len(uses))
		}
		lowU, highU := uses[0], uses[len(uses)-1]
		if !(pr[0] < lowU && highU < df[0] && df[0] > boundary) {
			return nil, p.die("`%s`: prototype at %d, calls at %d..%d, definition at %d, boundary at %d "+
				"-- the prototype must be above every call, the definition below every one "+
				"and the definition below the boundary",
				name, pr[0]+1, lowU+1, highU+1, df[0]+1, boundary+1)
		}
		var where []string
		for _, u := range uses {
			where = append(where, fmt.Sprintf("%d", u+1))
		}
		s := "s"
		if len(uses) == 1 {
			s = ""
		}
		p.sayf("`%s`: prototype line %d, %d call site%s at %s, definition line %d, which is "+
			"below the boundary at %d",
			name, pr[0]+1, len(uses), s, strings.Join(where, " "), df[0]+1, boundary+1)
	}

	if len(L)-1 != linesBefore+21-dropped {
		return nil, p.die("the file is %d lines and the input was %d -- expected %d more: three "+
			"prototypes and three five-line definitions with a blank line after each is 21 "+
			"in, and %d out of the core's block",
			len(L)-1, linesBefore, 21-dropped, dropped)
	}
	if r := blankRuns(t); r != runsBefore {
		return nil, p.die("the edit left %d runs of two blank lines where there were %d", r, runsBefore)
	}
	var d []int
	for i, l := range L {
		if z36Dir.MatchString(l) {
			d = append(d, i)
		}
	}
	okd := len(d) == 11 && d[0] == boundary
	for i := range d {
		if d[i] != d[0]+i {
			okd = false
		}
	}
	if !okd {
		return nil, p.die("the output does not have the same eleven contiguous `#include` directives -- " +
			"this phase adds DECLARATIONS and DEFINITIONS, never a directive")
	}
	p.sayf("%d -> %d lines, the eleven #includes untouched at line %d, and no run of two "+
		"blank lines", linesBefore, len(L)-1, boundary+1)
	return []byte(t), nil
}
