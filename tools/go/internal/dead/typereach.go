package dead

import (
	"bytes"
	"regexp"
	"sort"

	"slimvim.local/tools/internal/cutil"
)

var (
	identRe = regexp.MustCompile(`\b[A-Za-z_]\w*\b`)

	startRe = regexp.MustCompile(`^(typedef\b|struct\s+\w+\s*\{|union\s+\w+\s*\{|` +
		`enum\s+\w*\s*\{|struct\s+\w+\s*;|union\s+\w+\s*;)`)

	// headOnly is the same heads with the brace on the NEXT line.  111 of
	// slim-vim.c's definitions are written that way -- `struct jobvar_S` on
	// one line and `{` on the next -- and without this they were not
	// definitions at all, so EVERY FIELD IN THEM COUNTED AS A ROOT.  That is
	// how a whole dead island survived: channel_T's only two mentions outside
	// its own definitions are both fields, in structs that were invisible.
	//
	// The brace on the next line is REQUIRED rather than optional: a bare
	// `struct foo` line with no brace after it is a variable declaration.
	//
	// An enum need not have a tag -- `enum` alone, `{` on the next line, is
	// how the option-index lists are written, and without the bare form
	// deadenums never saw them.  A struct or union without a tag cannot be
	// written that way and still declare anything, so only enum gets it.
	headOnly = regexp.MustCompile(`^(?:static\s+)?(?:(?:struct|union|enum)\s+\w+|enum)$`)

	tagRe        = regexp.MustCompile(`\b(?:struct|union|enum)\s+(\w+)`)
	enumBodyRe   = regexp.MustCompile(`^\s*(typedef\s+)?enum\b`)
	typedefBody  = regexp.MustCompile(`^\s*typedef\b`)
	typeKeywords = map[string]bool{}
)

func init() {
	for _, k := range []string{
		"typedef", "struct", "union", "enum", "const", "volatile", "unsigned",
		"signed", "short", "long", "int", "char", "float", "double", "void",
		"static", "extern", "register", "inline", "sizeof", "return", "if", "else",
		"for", "while", "do", "switch", "case", "default", "break", "continue",
		"goto",
	} {
		typeKeywords[k] = true
	}
}

// TypeDef is one top-level type definition: its byte span, the names it
// owns, and whether it may be deleted.
type TypeDef struct {
	Start, End int
	Names      map[string]bool
	Deletable  bool
}

// Definitions returns every top-level type definition in text, whose blanked
// form is b.
func Definitions(text, b []byte) []TypeDef {
	d := cutil.Depths(b)
	var out []TypeDef
	n := len(text)

	for i := 0; i < n; {
		j := bytes.IndexByte(text[i:], '\n')
		if j < 0 {
			j = n
		} else {
			j += i
		}
		line := text[i:j]
		ls := trimSpace(line)

		braceNext := false
		if d[i] == 0 && headOnly.Match(ls) {
			// The Python is `text[j+1:text.find('\n', j+1)] if j < n else ''`,
			// and when there is no further newline that index is -1, so the
			// slice drops the last byte of the file.  Kept, because it is what
			// the comparison is against; it can only matter on a file whose
			// last line is the brace.
			nxt := []byte{}
			if j < n {
				k := bytes.IndexByte(text[j+1:], '\n')
				if k < 0 {
					nxt = text[j+1 : n-1]
				} else {
					nxt = text[j+1 : j+1+k]
				}
			}
			braceNext = bytes.Equal(trimSpace(nxt), []byte("{"))
		}

		if d[i] == 0 && len(ls) > 0 && (startRe.Match(ls) || braceNext) {
			// The definition ends at the first top-level ';' from here.
			k := i
			depth := 0
			for k < n {
				switch b[k] {
				case '{', '[', '(':
					depth++
				case '}', ']', ')':
					depth--
				case ';':
					if depth == 0 {
						goto found
					}
				}
				k++
			}
		found:
			if k >= n {
				break
			}
			body := text[i : k+1]
			names := map[string]bool{}

			head := body
			if p := bytes.IndexByte(body, '{'); p >= 0 {
				head = body[:p]
			}
			if m := tagRe.FindSubmatch(head); m != nil {
				names[string(m[1])] = true
			}

			tail := body
			if p := bytes.LastIndexByte(body, '}'); p >= 0 {
				tail = body[p+1:]
			}
			addIdents(names, tail)

			// An enum's constants are referenced without its tag, so they
			// decide whether the definition is live.  Leave them out and the
			// whole enum looks dead.
			if enumBodyRe.Match(body) {
				var inner []byte
				if o := bytes.IndexByte(body, '{'); o >= 0 {
					c := bytes.LastIndexByte(body, '}')
					if c > o {
						inner = body[o+1 : c]
					}
				}
				ib := cutil.Blank(inner)
				for _, part := range cutil.SplitTop(inner, ib, ",") {
					if m := identRe.Find(part); m != nil && !typeKeywords[string(m)] {
						names[string(m)] = true
					}
				}
			}

			// Does it ALSO declare a variable?  `static struct modmasktable
			// { ... } mod_mask_table[] = { ... };` is a type definition and a
			// variable in one construct, and the declarator sits between the
			// struct's closing brace and the '=', not after the LAST '}',
			// which is the initialiser's -- so tail above never saw it.
			//
			// Such a construct is not a type definition to delete: it is a
			// variable, and deadsweep owns those.  It is still recorded, so
			// that the mentions inside it stop counting as roots, which is the
			// whole point of recognising the form.  A `typedef struct { ... }
			// chanpart_T;` does NOT declare a variable -- there the declarator
			// names the type -- so only a non-typedef construct can have one.
			deletable := true
			ob := -1
			if !typedefBody.Match(body) {
				ob = bytes.IndexByte(body, '{')
			}
			if ob >= 0 {
				cb := cutil.Match(cutil.Blank(body), ob)
				if cb > 0 {
					decl := rtrimSpace(body[cb+1:])
					if len(decl) > 0 {
						decl = decl[:len(decl)-1] // drop the ';'
					}
					if identRe.Match(decl) {
						deletable = false
						addIdents(names, decl)
					}
				}
			}

			out = append(out, TypeDef{i, k + 1, names, deletable})
			i = k + 1
			continue
		}
		i = j + 1
	}
	return out
}

func addIdents(into map[string]bool, s []byte) {
	for _, m := range identRe.FindAll(s, -1) {
		if !typeKeywords[string(m)] {
			into[string(m)] = true
		}
	}
}

// TypeReach finds the definitions nothing outside a type definition mentions.
//
// Reachability, not reference counting.  A type named only from inside another
// type definition is not in use, and if two name each other, counting says
// both are live for ever.  The roots are the mentions outside EVERY type
// definition -- a prototype, a variable, a cast, a sizeof -- and the answer is
// what those reach.
func TypeReach(text []byte) (defs []TypeDef, dead []int) {
	b := cutil.Blank(text)
	defs = Definitions(text, b)

	owner := map[string][]int{}
	for idx, def := range defs {
		for nm := range def.Names {
			owner[nm] = append(owner[nm], idx)
		}
	}

	spans := make([][2]int, len(defs))
	for i, d := range defs {
		spans[i] = [2]int{d.Start, d.End}
	}
	sort.Slice(spans, func(i, j int) bool { return spans[i][0] < spans[j][0] })

	live := map[int]bool{}
	si := 0
	for _, loc := range identRe.FindAllIndex(b, -1) {
		p := loc[0]
		for si < len(spans) && spans[si][1] <= p {
			si++
		}
		if si < len(spans) && spans[si][0] <= p && p < spans[si][1] {
			continue
		}
		for _, o := range owner[string(b[loc[0]:loc[1]])] {
			live[o] = true
		}
	}

	frontier := map[int]bool{}
	for k := range live {
		frontier[k] = true
	}
	for len(frontier) > 0 {
		next := map[int]bool{}
		for idx := range frontier {
			d := defs[idx]
			for _, m := range identRe.FindAll(b[d.Start:d.End], -1) {
				for _, o := range owner[string(m)] {
					if !live[o] {
						live[o] = true
						next[o] = true
					}
				}
			}
		}
		frontier = next
	}

	for i := range defs {
		if !live[i] && defs[i].Deletable {
			dead = append(dead, i)
		}
	}
	return defs, dead
}

// DeleteDefs removes the given definitions and the newlines that follow each,
// which is what keeps a deletion from leaving a blank hole.
func DeleteDefs(text []byte, defs []TypeDef, dead []int) []byte {
	sorted := append([]int(nil), dead...)
	sort.Ints(sorted)
	var out []byte
	last := 0
	for _, i := range sorted {
		out = append(out, text[last:defs[i].Start]...)
		last = defs[i].End
		for last < len(text) && text[last] == '\n' {
			last++
		}
	}
	return append(out, text[last:]...)
}

func trimSpace(s []byte) []byte  { return bytes.Trim(s, " \t\n\v\f\r\x1c\x1d\x1e\x1f") }
func rtrimSpace(s []byte) []byte { return bytes.TrimRight(s, " \t\n\v\f\r\x1c\x1d\x1e\x1f") }
