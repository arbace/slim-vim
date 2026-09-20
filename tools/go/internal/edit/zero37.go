package edit

import (
	"fmt"
	"io"
	"regexp"
	"sort"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

func init() { register("zero37", Zero37) }

var (
	z37Inc  = regexp.MustCompile(`^ *# *include <([A-Za-z0-9_/.]+)>$`)
	z37Dir  = regexp.MustCompile(`^ *#`)
	z37Word = regexp.MustCompile(`\bunion\b`)
	z37Tail = regexp.MustCompile(`^([ \t]*)([A-Za-z_]\w*)[ \t]*;`)
	z37Decl = regexp.MustCompile(`(?s)^(.*?)([A-Za-z_]\w*)[ \t]*;$`)
)

type z37Union struct {
	line        int
	name        string
	members     int
	indent      string
	start, end  int
	body        string
	member      string
	replacement string
	accessors   int
}

type z37Edit struct {
	a, b int
	rep  string
}

// Zero37 removes the degenerate unions -- the ones that unite nothing with
// anything, five single-member and one EMPTY, which ISO C forbids.
//
// NOTHING HERE IS A NAME THIS PROGRAM KNOWS IN ADVANCE: the braces are matched
// and the members counted at depth 1, so it states a property of the file rather
// than a memory of one.
func Zero37(text []byte, w io.Writer) ([]byte, error) {
	p := ph{"unions", w}
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
	lineOf := func(s string, pos int) int { return strings.Count(s[:pos], "\n") + 1 }

	lines := strings.Split(t, "\n")
	runsBefore := blankRuns(t)

	// ---- 0. the file this edit was written against ----------------------------
	var d []int
	for i, l := range lines {
		if z37Dir.MatchString(l) {
			d = append(d, i)
		}
	}
	if len(d) == 0 {
		return nil, p.die("the file has no preprocessor directive, so there is no boundary between the " +
			"core and the host")
	}
	for i := range d {
		if d[i] != d[0]+i {
			return nil, p.die("the %d directives are not on consecutive lines, so the first `#include` is not "+
				"a boundary", len(d))
		}
	}
	for _, i := range d {
		if !z37Inc.MatchString(lines[i]) {
			return nil, p.die("a directive is not an `#include <...>` of a system header, and no phase may add " +
				"one")
		}
	}
	bound := d[0]
	p.sayf("%d directives on consecutive lines from %d, every one an `#include <...>`; the core "+
		"is the %d lines above the first of them", len(d), bound+1, bound)

	// ---- 1. the literals ------------------------------------------------------
	spans, err := literalSpans(p, text)
	if err != nil {
		return nil, err
	}
	inLiteral := func(pos int) bool {
		lo, hi := 0, len(spans)
		for lo < hi {
			mid := (lo + hi) / 2
			if spans[mid][0] <= pos {
				lo = mid + 1
			} else {
				hi = mid
			}
		}
		k := lo - 1
		return k >= 0 && spans[k][0] <= pos && pos < spans[k][1]
	}
	p.sayf("%d string and character literals scanned, so every span below is over code", len(spans))

	// ---- 2. every union in the file, and which of them union nothing ----------
	var unions []*z37Union
	for _, m := range z37Word.FindAllStringIndex(t, -1) {
		if inLiteral(m[0]) {
			return nil, p.die("a literal holds the word `union` at line %d, which no literal in this file "+
				"ever has", lineOf(t, m[0]))
		}
		j := m[1]
		for j < len(t) && (t[j] == ' ' || t[j] == '\t' || t[j] == '\n') {
			j++
		}
		if j >= len(t) || t[j] != '{' {
			return nil, p.die("the `union` at line %d is not followed by a brace, so this is a union type "+
				"named rather than defined and the scanner cannot classify it", lineOf(t, m[0]))
		}
		depth, k, members := 0, j, 0
		for k < len(t) {
			c := t[k]
			if c == '{' {
				depth++
			} else if c == '}' {
				depth--
				if depth == 0 {
					break
				}
			} else if c == ';' && depth == 1 {
				members++
			}
			k++
		}
		if k >= len(t) {
			return nil, p.die("the union at line %d never closes", lineOf(t, m[0]))
		}
		tail := z37Tail.FindStringSubmatchIndex(t[k+1:])
		if tail == nil {
			return nil, p.die("the union at line %d does not end `} <name>;`, and this phase rewrites only "+
				"a union declared as one named field", lineOf(t, m[0]))
		}
		start := strings.LastIndex(t[:m[0]], "\n") + 1
		if strings.TrimSpace(t[start:m[0]]) != "" {
			return nil, p.die("the union at line %d does not begin its line", lineOf(t, m[0]))
		}
		unions = append(unions, &z37Union{
			line: lineOf(t, m[0]), name: t[k+1+tail[4] : k+1+tail[5]], members: members,
			indent: t[start:m[0]], start: start, body: t[j+1 : k], end: k + 1 + tail[1],
		})
	}
	coreLen := len(strings.Join(lines[:bound], "\n"))
	for _, u := range unions {
		if u.end > coreLen {
			return nil, p.die("a union is defined below the boundary, in the host, and this phase is about the " +
				"CORE")
		}
	}
	var degenerate, genuine []*z37Union
	for _, u := range unions {
		if u.members < 2 {
			degenerate = append(degenerate, u)
		} else {
			genuine = append(genuine, u)
		}
	}
	if len(degenerate) == 0 || len(genuine) == 0 {
		return nil, p.die("the scan found %d degenerate unions and %d genuine ones, and it must find both "+
			"-- a scanner that stopped matching would otherwise pass by finding nothing",
			len(degenerate), len(genuine))
	}
	gs := make([]string, len(genuine))
	for i, u := range genuine {
		gs[i] = fmt.Sprintf("%s (%d)", u.name, u.members)
	}
	p.sayf("%d `union` keywords in the core, every one of them a `union { ... } <name>;` field: "+
		"%d with fewer than two members and %d with two or more.  THE SEVEN THAT STAY ARE "+
		"DOING THE JOB A UNION IS FOR: %s",
		len(unions), len(degenerate), len(genuine), strings.Join(gs, ", "))
	ds := make([]string, len(degenerate))
	for i, u := range degenerate {
		kind := "empty"
		if u.members != 0 {
			kind = "1 member"
		}
		ds[i] = fmt.Sprintf("%s (%s)", u.name, kind)
	}
	p.sayf("THE %d THAT GO UNION NOTHING WITH ANYTHING: %s", len(degenerate), strings.Join(ds, ", "))

	// ---- 3. the partition -----------------------------------------------------
	var edits []z37Edit
	var report []string
	for _, u := range degenerate {
		if u.members != 0 {
			decl := strings.TrimSpace(u.body)
			mm := z37Decl.FindStringSubmatch(decl)
			if mm == nil || strings.Contains(decl, "\n") {
				return nil, p.die("the single member of `%s` is not one `<type> <name>;` on one line: %s",
					u.name, cutil.PyRepr(decl))
			}
			u.member = mm[2]
			u.replacement = u.indent + mm[1] + u.name + ";"
		}
		acc := 0
		var leftover []string
		for _, m := range regexp.MustCompile(`\b`+u.name+`\b`).FindAllStringIndex(t, -1) {
			switch {
			case inLiteral(m[0]):
				leftover = append(leftover, fmt.Sprintf("line %d %s",
					lineOf(t, m[0]), cutil.PyRepr("inside a literal")))
			case u.start <= m[0] && m[0] < u.end:
				// its own declaration, which this edit rewrites
			case u.member != "" && strings.HasPrefix(t[m[1]:], "."+u.member) &&
				!z37IsIdent(z37At(t, m[1]+1+len(u.member))):
				acc++
				edits = append(edits, z37Edit{m[1], m[1] + 1 + len(u.member), ""})
			default:
				lo := m[0] - 40
				if lo < 0 {
					lo = 0
				}
				hi := m[1] + 40
				if hi > len(t) {
					hi = len(t)
				}
				leftover = append(leftover, fmt.Sprintf("line %d %s",
					lineOf(t, m[0]), cutil.PyRepr(strings.ReplaceAll(t[lo:hi], "\n", "|"))))
			}
		}
		if len(leftover) > 0 {
			s := "s"
			if len(leftover) == 1 {
				s = ""
			}
			mem := u.member
			if mem == "" {
				mem = "<no member>"
			}
			return nil, p.die("`%s` has %d mention%s that is neither its own declaration nor a `.%s` access "+
				"on it, so this phase may not rewrite it: %s",
				u.name, len(leftover), s, mem, strings.Join(first(leftover, 4), "; "))
		}
		if u.members != 0 && acc == 0 {
			return nil, p.die("`%s` has no `.%s` access anywhere, so the field this phase would promote is "+
				"read by nothing and belongs to the sweep and not to this edit", u.name, u.member)
		}
		u.accessors = acc
		report = append(report, fmt.Sprintf("%s 1 + %d", u.name, acc))
		if u.members != 0 {
			edits = append(edits, z37Edit{u.start, u.end, u.replacement})
		} else {
			if z37At(t, u.end) != '\n' {
				return nil, p.die("the empty union `%s` does not end its line, so deleting it would take "+
					"code with it", u.name)
			}
			edits = append(edits, z37Edit{u.start, u.end + 1, ""})
		}
	}
	p.sayf("THE PARTITION HOLDS FOR ALL %d: every mention outside a literal is the "+
		"declaration or a `.member` access on it, and there is nothing else -- %s",
		len(degenerate), strings.Join(report, ", "))

	// ---- 4. the rewrite: one pass over the original text ----------------------
	sort.Slice(edits, func(i, j int) bool {
		if edits[i].a != edits[j].a {
			return edits[i].a < edits[j].a
		}
		if edits[i].b != edits[j].b {
			return edits[i].b < edits[j].b
		}
		return edits[i].rep < edits[j].rep
	})
	for i := 0; i+1 < len(edits); i++ {
		if edits[i].b > edits[i+1].a {
			return nil, p.die("two edit spans overlap at offset %d, so applying them in one pass would "+
				"corrupt the text", edits[i+1].a)
		}
	}
	var out strings.Builder
	last := 0
	for _, e := range edits {
		out.WriteString(t[last:e.a])
		out.WriteString(e.rep)
		last = e.b
	}
	out.WriteString(t[last:])
	t = out.String()
	p.sayf("%d spans rewritten in ONE pass over the original text: %d declarations and %d "+
		"`.member` accesses", len(edits), len(degenerate), len(edits)-len(degenerate))

	// ---- 5. what the file is now ----------------------------------------------
	L := strings.Split(t, "\n")
	left := z37Word.FindAllString(t, -1)
	if len(left) != len(genuine) {
		return nil, p.die("the file has %d `union` keywords and the %d genuine ones are what must remain",
			len(left), len(genuine))
	}
	for _, u := range degenerate {
		n := len(regexp.MustCompile(`\b`+u.name+`\b`).FindAllString(t, -1))
		want := 0
		if u.members != 0 {
			want = 1 + u.accessors
		}
		if n != want {
			return nil, p.die("`%s` has %d mentions and must have %d -- its own declaration and the %d "+
				"accesses that are now plain field references", u.name, n, want, u.accessors)
		}
		if u.members != 0 {
			if strings.Count(t, u.replacement+"\n") != 1 {
				return nil, p.die("`%s` is not declared exactly once as `%s`",
					u.name, strings.TrimSpace(u.replacement))
			}
			if regexp.MustCompile(`\b` + u.name + `\s*\.\s*` + u.member + `\b`).MatchString(t) {
				return nil, p.die("a `%s.%s` access survives", u.name, u.member)
			}
		}
	}
	var nd []int
	for i, l := range L {
		if z37Dir.MatchString(l) {
			nd = append(nd, i)
		}
	}
	if len(nd) != len(d) {
		return nil, p.die("the file has %d directives and had %d: this phase adds none and removes none",
			len(nd), len(d))
	}
	if nd[0]-d[0] != len(L)-len(lines) {
		return nil, p.die("the boundary moved by %d lines and the file by %d: every line this phase touches "+
			"is above the first `#include`", nd[0]-d[0], len(L)-len(lines))
	}
	if r := blankRuns(t); r != runsBefore {
		return nil, p.die("the edit left %d runs of two blank lines where there were %d", r, runsBefore)
	}
	p.sayf("`union` %d -> %d, %d -> %d lines, %d directives unmoved relative to the text, and "+
		"the blank-line runs unchanged at %d",
		len(unions), len(left), len(lines)-1, len(L)-1, len(nd), blankRuns(t))
	return []byte(t), nil
}

func z37At(s string, i int) byte {
	if i < 0 || i >= len(s) {
		return 0
	}
	return s[i]
}

// z37IsIdent is the Python's `(c or ' ').isalnum() or c == '_'`: the byte after
// a `.member` access must not continue the identifier.
func z37IsIdent(c byte) bool {
	return c == '_' || (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}
