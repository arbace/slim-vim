package edit

import (
	"fmt"
	"io"
	"os"
	"regexp"
	"strings"
)

func init() { registerArgs("zero41", Zero41) }

// z41Names are the three libc allocators.  `\b` does not match inside
// `host_free`, `vim_free` or `realloc_cmdbuff` -- `_` is a word character --
// so these are the bare libc names.
var z41Names = []string{"malloc", "free", "realloc"}

var (
	z41Dir = regexp.MustCompile(`^ *# *`)
	z41Inc = regexp.MustCompile(`^#include <[A-Za-z0-9_/.]+>$`)
)

// Zero41 makes freeing free: host_alloc() becomes a bump allocator into a 1 GiB
// arena and host_free() a function that returns.
//
// IT TOUCHES NO CORE LINE, and that is the phase's central claim: the text above
// the first `#include` must be BYTE-IDENTICAL in and out.
func Zero41(text []byte, w io.Writer, args []string) ([]byte, error) {
	p := ph{"arena", w}
	if len(args) != 1 {
		return nil, p.die("usage: edit zero41 <file> <state-dir>")
	}
	state := args[0]
	t := string(text)

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

	L := strings.Split(t, "\n")
	linesBefore := len(L) - 1
	runsBefore := blankRuns(t)

	// ---- 0. the boundary, and the file this edit was written against ---------
	var directives []int
	for i, l := range L {
		if z41Dir.MatchString(l) {
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
		if !z41Inc.MatchString(L[i]) {
			return nil, p.die("a directive is not an `#include <...>` of a system header, and no phase may " +
				"add one")
		}
	}
	boundary := directives[0]
	coreBefore := strings.Join(L[:boundary], "\n")
	p.sayf("the boundary is line %d, the first of the eleven `#include`s, and there is not a "+
		"directive above it", boundary+1)

	// ---- 1. no literal holds any of the three names --------------------------
	spans, err := literalSpansShort(p, text)
	if err != nil {
		return nil, err
	}
	for _, name := range z41Names {
		re := regexp.MustCompile(`\b` + name + `\b`)
		var bad []string
		for _, s := range spans {
			if re.MatchString(t[s[0]:s[1]]) {
				bad = append(bad, t[s[0]:s[1]])
			}
		}
		if len(bad) > 0 {
			return nil, p.die("a literal holds the name `%s`: %s", name,
				strings.Join(first(bad, 3), " / "))
		}
	}
	p.sayf("%d string and character literals, and not one of them holds `malloc`, `free` or "+
		"`realloc`, so every mention the partition below classifies is code", len(spans))

	// ---- 2. THE PARTITION ----------------------------------------------------
	// A PARTITION AND NOT A COUNT.  How many mentions there are is read off the
	// text and never written down; what is written down is that every one falls
	// in a class this phase rewrites, and that a mention in no class REFUSES.
	classes := []struct{ what, text string }{
		{"host_alloc()'s body", z41AllocOld},
		{"host_free()'s body", z41FreeOld},
		{"format_overflow_error()'s free of argcopy", z41OverflowOld},
		{"adjust_types()'s realloc of *ap_types, with the failure test below it", z41ReallocOld},
	}
	var covered [][2]int
	for _, c := range classes {
		if k := strings.Count(t, c.text); k != 1 {
			return nil, p.die("%s is in the file %d times and must be there exactly once, so this phase "+
				"has not been handed the file it was written for", c.what, k)
		}
		a := strings.Index(t, c.text)
		covered = append(covered, [2]int{a, a + len(c.text)})
	}
	total := map[string]int{}
	var stray []string
	for _, name := range z41Names {
		n := 0
		for _, m := range regexp.MustCompile(`\b`+name+`\b`).FindAllStringIndex(t, -1) {
			in := false
			for _, c := range covered {
				if c[0] <= m[0] && m[1] <= c[1] {
					in = true
					break
				}
			}
			if in {
				n++
			} else {
				stray = append(stray, fmt.Sprintf("%s:%d", name, strings.Count(t[:m[0]], "\n")+1))
			}
		}
		total[name] = n
	}
	if len(stray) > 0 {
		s := "s"
		if len(stray) == 1 {
			s = ""
		}
		return nil, p.die("%d mention%s of one of the three is in none of the four classes this phase "+
			"rewrites: %s -- this phase will not leave a libc allocator call behind on a "+
			"pointer the arena handed out", len(stray), s, strings.Join(first(stray, 6), " "))
	}
	// AND ALL OF THEM ARE BELOW THE BOUNDARY, which is the host-only claim stated
	// as a place before it is stated as a `cmp`.
	for _, name := range z41Names {
		if regexp.MustCompile(`\b` + name + `\b`).MatchString(coreBefore) {
			return nil, p.die("`%s` is mentioned above the boundary, and phases 34 and 35 took the core's "+
				"last one -- this phase changes the host and nothing else", name)
		}
	}
	for _, n := range []string{"host_arena", "host_arena_used", "host_arena_say", "host_arena_num",
		"host_arena_exhausted", "HOST_ARENA_BYTES"} {
		if regexp.MustCompile(`\b` + n + `\b`).MatchString(t) {
			return nil, p.die("`%s` is already a name in this file", n)
		}
	}
	p.sayf("THE PARTITION HOLDS: `malloc` %d mentions, `free` %d and `realloc` %d, every one of "+
		"them below the boundary and inside one of the four runs of text this phase "+
		"rewrites -- host_alloc's body, host_free's body, format_overflow_error's free of "+
		"argcopy and adjust_types's realloc of *ap_types.  Nothing else in the file says "+
		"any of the three", total["malloc"], total["free"], total["realloc"])

	// ---- 3 to 6. the four replacements ---------------------------------------
	for _, e := range []struct{ old, new, what, why string }{
		{z41AllocOld, z41AllocNew, "host_alloc()'s definition",
			"the arena, its offset, the two message helpers and the abort go where the one " +
				"call of malloc() was, so the allocator and its data stay one paragraph of the " +
				"launcher region"},
		{z41FreeOld, z41FreeNew, "host_free()'s definition",
			"this is the whole of \"freeing is now free\": the parameter is named so the " +
				"signature does not move and discarded so the build is silent"},
		{z41OverflowOld, z41lit2, "format_overflow_error()'s free of argcopy",
			"argcopy came from alloc_clear(), which is host_alloc(), and from the line above " +
				"this one libc's free() of that pointer is undefined.  It is the same rename " +
				"phase 35 made at every core site, made at the one site below the boundary"},
		{z41ReallocOld, z41ReallocNew, "adjust_types()'s realloc of *ap_types",
			"phase 34's rewrite at the one site phase 34 left: allocate, copy what was there, " +
				"free the old block.  The old size is `*num_posarg` entries, which the function " +
				"already has, and the guard is the same `*ap_types != nullptr` the arm above tests"},
	} {
		if err := swap(e.old, e.new, e.what, e.why); err != nil {
			return nil, err
		}
	}

	// ---- 7. what the file is now ---------------------------------------------
	L = strings.Split(t, "\n")
	var d []int
	for i, l := range L {
		if z41Dir.MatchString(l) {
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
		return nil, p.die("the output does not have the same eleven contiguous `#include` directives at " +
			"the same line -- this phase adds no directive, removes none and moves none")
	}
	for _, name := range z41Names {
		if n := len(regexp.MustCompile(`\b`+name+`\b`).FindAllString(t, -1)); n != 0 {
			return nil, p.die("`%s` still has %d mentions after every class was rewritten", name, n)
		}
	}
	// THE CORE IS BYTE-IDENTICAL, which is this phase's central claim and is
	// asserted here before the check states it as `make editor.c`'s own `cmp`.
	if strings.Join(L[:d[0]], "\n") != coreBefore {
		return nil, p.die("the text above the boundary is not what it was: this phase is below it " +
			"entirely, and a difference there is a bug in one of the four replacements")
	}
	p.sayf("`malloc`, `free` and `realloc` are 0 mentions in the whole file, and the %d lines "+
		"above the boundary are BYTE-IDENTICAL to the input's -- the eleven #includes are "+
		"untouched at line %d", d[0], d[0]+1)

	// The arithmetic, computed rather than written: the four replacements' own
	// line counts.
	grew := 0
	for _, e := range [][2]string{
		{z41AllocOld, z41AllocNew}, {z41FreeOld, z41FreeNew},
		{z41OverflowOld, z41lit2}, {z41ReallocOld, z41ReallocNew},
	} {
		grew += len(strings.Split(e[1], "\n")) - len(strings.Split(e[0], "\n"))
	}
	if len(L)-1 != linesBefore+grew {
		return nil, p.die("the file is %d lines and the input was %d -- the four replacements are %d lines "+
			"more between them", len(L)-1, linesBefore, grew)
	}
	if r := blankRuns(t); r != runsBefore {
		return nil, p.die("the edit left %d runs of two blank lines where there were %d", r, runsBefore)
	}
	p.sayf("%d -> %d lines, %d more, which is exactly what the four replacements are worth; no "+
		"run of two blank lines", linesBefore, len(L)-1, grew)

	if err := os.WriteFile(state+"/arena-bytes",
		[]byte(fmt.Sprintf("%d\n", 1024*1024*1024)), 0o644); err != nil {
		return nil, p.die("%v", err)
	}
	return []byte(t), nil
}
