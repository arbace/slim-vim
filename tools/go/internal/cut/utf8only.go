package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"
	"sort"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

const (
	markT = "__T__"
	markF = "__F__"
	markZ = "__Z__"
)

// utf8Flags are the five encoding flags and the constant each becomes.
//
// A SLICE, not a map: the substitution order decides nothing here (the five
// names are disjoint) but the count is reported, and a stable order keeps the
// two implementations saying the same thing on a refusal.
var utf8Flags = []struct{ name, tok string }{
	{"enc_utf8", markT}, {"has_mbyte", markT}, {"enc_latin1like", markT},
	{"enc_dbcs", markZ}, {"enc_unicode", markZ},
}

var (
	markRe     = regexp.MustCompile(`\b(?:__T__|__F__|__Z__)\b`)
	callRe     = regexp.MustCompile(`[\w\]\)]\s*\(`)
	returnHead = regexp.MustCompile(`^(\s*return\s+)`)
	ctrlBefore = regexp.MustCompile(`\b(?:if|while|switch|for)\s*$`)
	forBefore  = regexp.MustCompile(`\bfor\s*$`)
	elseAhead  = regexp.MustCompile(`^[ \t]*else\b`)
	ctrlMark   = regexp.MustCompile(`(?m)^([ \t]*)(else if|if|while) \((__T__|__F__|__Z__)\)$`)
	zeroCmpA   = regexp.MustCompile(`^(__Z__|0)\s*(==|!=)\s*(__Z__|0|DBCS_\w+)$`)
	zeroCmpB   = regexp.MustCompile(`^(DBCS_\w+|0)\s*(==|!=)\s*(__Z__)$`)
	funcHeads  = regexp.MustCompile(`(?m)^(\w+)\([^;\n]*\)[ \t]*\n\{`)
	flagDecls  = regexp.MustCompile(
		`(?m)^static int\s+(?:enc_utf8|has_mbyte|enc_dbcs|enc_unicode|enc_latin1like)\s+=\s*[^;\n]*;\n`)
	flagAssign = regexp.MustCompile(
		`(?m)^[ \t]*(?:enc_unicode|enc_utf8|enc_dbcs|has_mbyte|enc_latin1like) = [^;\n]*;\n`)
)

func isAssignPrefixByte(c byte) bool {
	return strings.IndexByte("+-*/%&|^", c) >= 0
}

// findAssign returns the index just past the `=` of the first assignment
// operator in b, or -1.
//
// The Python writes this as `(?<![=!<>])(?:[+\-*/%&|^]|<<|>>)?=(?!=)`, a
// NEGATIVE LOOKBEHIND, which RE2 does not have.  Spelled out: an `=` not
// followed by `=`, whose operator (with an optional +-*/%&|^ or << or >>
// before it) is not itself preceded by = ! < >.  That is what distinguishes
// `+=` and `>>=`, which ARE assignments, from `<=`, `>=`, `==` and `!=`, which
// are not.
func findAssign(b string) int {
	for i := 0; i < len(b); i++ {
		if b[i] != '=' {
			continue
		}
		if i+1 < len(b) && b[i+1] == '=' {
			continue
		}
		start := i
		if i >= 2 && (b[i-2:i] == "<<" || b[i-2:i] == ">>") {
			start = i - 2
		} else if i >= 1 && isAssignPrefixByte(b[i-1]) {
			start = i - 1
		}
		if start > 0 && strings.IndexByte("=!<>", b[start-1]) >= 0 {
			continue
		}
		return i + 1
	}
	return -1
}

// hasAssign reports whether b contains an assignment or ++ / --.
func hasAssign(b string) bool {
	if strings.Contains(b, "++") || strings.Contains(b, "--") {
		return true
	}
	return findAssign(b) >= 0
}

// outer reports whether s is one parenthesised group, parentheses included.
func outer(s string) bool {
	if !strings.HasPrefix(s, "(") || !strings.HasSuffix(s, ")") {
		return false
	}
	return cutil.Match(cutil.Blank([]byte(s)), 0) == len(s)-1
}

// constOf folds a fully-simplified expression to a constant, if it is one.
func constOf(e string) (val, ok bool) {
	s := strings.TrimSpace(e)
	for outer(s) {
		s = strings.TrimSpace(s[1 : len(s)-1])
	}
	switch s {
	case markT:
		return true, true
	case markF, markZ:
		return false, true
	}
	return false, false
}

// pure reports whether an expression has no side effect: no assignment, no
// call.  An impure operand cannot be dropped from a || or && chain.
func pure(e string) bool {
	b := string(cutil.Blank([]byte(e)))
	return !hasAssign(b) && !callRe.MatchString(b)
}

// maskDeep blanks everything at parenthesis depth above zero, so a test can
// ask about the top level only.
func maskDeep(b string) string {
	dep := cutil.Depths([]byte(b))
	out := []byte(b)
	for i := range out {
		if dep[i] != 0 {
			out[i] = ' '
		}
	}
	return string(out)
}

// simplify returns e with every constant marker expression folded; spacing
// outside is kept.
func simplify(e string) string {
	lead := e[:len(e)-len(strings.TrimLeft(e, " \t\n\r\v\f"))]
	trail := e[len(strings.TrimRight(e, " \t\n\r\v\f")):]
	s := strings.TrimSpace(e)
	if s == "" || !markRe.MatchString(s) {
		return e
	}
	sb := cutil.Blank([]byte(s))
	if cutil.FindTop([]byte(s), sb, ',') >= 0 {
		return e
	}
	// An assignment at the top of the expression is left to the statement code.
	if hasAssign(maskDeep(string(sb))) {
		return e
	}

	if q := cutil.FindTop([]byte(s), sb, '?'); q >= 0 {
		cond, rest := s[:q], s[q+1:]
		rb := cutil.Blank([]byte(rest))
		colon := cutil.FindTop([]byte(rest), rb, ':')
		if colon < 0 {
			return e
		}
		head := rest[:colon]
		if cutil.FindTop([]byte(head), cutil.Blank([]byte(head)), '?') >= 0 {
			return e
		}
		yes, no := rest[:colon], rest[colon+1:]
		c2 := simplify(cond)
		if k, ok := constOf(c2); ok {
			if k {
				return lead + strings.TrimSpace(simplify(yes)) + trail
			}
			return lead + strings.TrimSpace(simplify(no)) + trail
		}
		nw := fmt.Sprintf("%s ? %s : %s", strings.TrimSpace(c2),
			strings.TrimSpace(simplify(yes)), strings.TrimSpace(simplify(no)))
		if nw != s {
			return lead + nw + trail
		}
		return e
	}

	for _, o := range []struct {
		op   string
		stop bool
	}{{"||", true}, {"&&", false}} {
		parts := cutil.SplitTop([]byte(s), sb, o.op)
		if len(parts) > 1 {
			var out []string
			for _, p := range parts {
				p2 := strings.TrimSpace(simplify(string(p)))
				if k, ok := constOf(p2); ok {
					if k == !o.stop {
						continue // the neutral operand goes
					}
					allPure := true
					for _, x := range out {
						if !pure(x) {
							allPure = false
							break
						}
					}
					if allPure {
						if o.stop {
							return lead + markT + trail
						}
						return lead + markF + trail
					}
					if o.stop { // an impure prefix stays
						out = append(out, markT)
					} else {
						out = append(out, markF)
					}
					break
				}
				out = append(out, p2)
			}
			if len(out) == 0 {
				if o.stop {
					return lead + markF + trail
				}
				return lead + markT + trail
			}
			nw := strings.Join(out, " "+o.op+" ")
			if nw != s {
				return lead + nw + trail
			}
			return e
		}
	}

	if strings.HasPrefix(s, "!") && !strings.HasPrefix(s, "!=") {
		inner := simplify(s[1:])
		if k, ok := constOf(inner); ok {
			if k {
				return lead + markF + trail
			}
			return lead + markT + trail
		}
		if strings.TrimSpace(inner) != strings.TrimSpace(s[1:]) {
			return lead + "!" + strings.TrimSpace(inner) + trail
		}
		return e
	}

	if outer(s) {
		inner := simplify(s[1 : len(s)-1])
		if k, ok := constOf(inner); ok {
			if k {
				return lead + markT + trail
			}
			return lead + markF + trail
		}
		if inner != s[1:len(s)-1] {
			return lead + "(" + strings.TrimSpace(inner) + ")" + trail
		}
		return e
	}

	m := zeroCmpA.FindStringSubmatch(s)
	if m == nil {
		m = zeroCmpB.FindStringSubmatch(s)
	}
	if m != nil {
		isZero := func(x string) bool { return x == markZ || x == "0" }
		equal := isZero(m[1]) && isZero(m[3])
		if m[2] == "==" {
			if equal {
				return lead + markT + trail
			}
			return lead + markF + trail
		}
		if equal {
			return lead + markF + trail
		}
		return lead + markT + trail
	}
	return e
}

// enclosingGroup returns the innermost parenthesis group around pos.
func enclosingGroup(text string, b []byte, dep []int, pos int) (int, int, bool) {
	d := dep[pos]
	i := pos
	for i > 0 {
		i--
		if b[i] == '(' && dep[i] < d {
			c := cutil.Match(b, i)
			if c > pos {
				return i, c, true
			}
			d = dep[i]
		} else if (b[i] == '{' || b[i] == ';' || b[i] == '}') && dep[i] < d {
			return 0, 0, false
		}
	}
	return 0, 0, false
}

// statementBounds gives the statement around pos at brace depth: from after
// ; { } to its ;.
func statementBounds(text string, b []byte, dep []int, pos int) (int, int) {
	d := dep[pos]
	i := pos
	for i > 0 && !(strings.IndexByte(";{}", b[i-1]) >= 0 && dep[i-1] <= d) {
		i--
	}
	j := pos
	for j < len(text) && !(b[j] == ';' && dep[j] <= d) {
		j++
	}
	return i, j
}

// simplifyFunction folds every marker expression in one function body.
func simplifyFunction(body string) (string, int) {
	changes := 0
	for round := 0; round < 200; round++ {
		b := cutil.Blank([]byte(body))
		dep := cutil.Depths(b)
		progressed := false
		for _, mk := range markRe.FindAllStringIndex(body, -1) {
			pos := mk[0]
			if o, c, ok := enclosingGroup(body, b, dep, pos); ok {
				before := strings.TrimRight(body[:o], " \t\n\r\v\f")
				control := ctrlBefore.MatchString(before)
				call := !control && before != "" &&
					(isAlnumByte(before[len(before)-1]) || before[len(before)-1] == '_' ||
						before[len(before)-1] == ')' || before[len(before)-1] == ']')
				inner := body[o+1 : c]
				ib := cutil.Blank([]byte(inner))
				pieces := cutil.SplitTop([]byte(inner), ib, ",")
				isFor := forBefore.MatchString(before)
				if len(pieces) > 1 || call || isFor {
					sep := ","
					if isFor {
						sep = ";"
					}
					pieces = cutil.SplitTop([]byte(inner), ib, sep)
					newPieces := make([]string, len(pieces))
					for i, p := range pieces {
						newPieces[i] = simplify(string(p))
					}
					newInner := strings.Join(newPieces, sep)
					if newInner != inner {
						body = body[:o+1] + newInner + body[c:]
						progressed = true
						break
					}
					continue
				}
				newInner := simplify(inner)
				_, isConst := constOf(newInner)
				t := strings.TrimSpace(newInner)
				if !control && isConst && (t == markT || t == markF || t == markZ) {
					body = body[:o] + t + body[c+1:]
					progressed = true
					break
				}
				if newInner != inner {
					body = body[:o+1] + newInner + body[c:]
					progressed = true
					break
				}
				continue
			}
			i, j := statementBounds(body, b, dep, pos)
			stmt := body[i:j]
			sb := string(cutil.Blank([]byte(stmt)))
			var head, rhs string
			if ma := returnHead.FindStringIndex(stmt); ma != nil {
				head, rhs = stmt[:ma[1]], stmt[ma[1]:]
			} else {
				a := findAssign(sb)
				if a < 0 {
					continue
				}
				head, rhs = stmt[:a], stmt[a:]
			}
			newRhs := simplify(rhs)
			if newRhs != rhs {
				body = body[:i] + head + newRhs + body[j:]
				progressed = true
				break
			}
		}
		if !progressed {
			break
		}
		changes++
	}
	return body, changes
}

func isAlnumByte(c byte) bool {
	return ('0' <= c && c <= '9') || ('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z')
}

// foldControls folds if / else if / while on a constant marker.
func foldControls(body string) (string, int, error) {
	n := 0
	for {
		m := ctrlMark.FindStringSubmatchIndex(body)
		if m == nil {
			return body, n, nil
		}
		indent := body[m[2]:m[3]]
		head := body[m[4]:m[5]]
		val := body[m[6]:m[7]]
		truth := val == markT
		pat := regexp.MustCompile(`(?m)^[ \t]*` + regexp.QuoteMeta(head) + ` \(` + val + `\)$`)
		if truth && head == "while" {
			return "", 0, fmt.Errorf("utf8only: while (TRUE) from a marker -- not expected")
		}
		if !truth {
			// A function can hold the same false condition more than once, one
			// nested inside another's block.  Folding the OUTER one first makes
			// the inner vanish, so fold from the LAST occurrence: its block and
			// its else chain lie after it, and nothing before it moves.
			all := pat.FindAllStringIndex(body, -1)
			last := all[len(all)-1]
			start := strings.LastIndexByte(body[:last[0]], '\n') + 1
			out, err := cutil.FoldNever([]byte(body[start:]), pat.String(), 1)
			if err != nil {
				return "", 0, fmt.Errorf("utf8only: %v", err)
			}
			body = body[:start] + string(out)
			n++
			continue
		}
		b := cutil.Blank([]byte(body))
		mm := pat.FindStringIndex(body)
		k, o, c, _, err := cutil.Guarded([]byte(body), b, mm)
		if err != nil {
			return "", 0, fmt.Errorf("utf8only: %v", err)
		}
		end := c + strings.IndexByte(body[c:], '\n') + 1
		tailStart := end
		for {
			nxt := elseAhead.FindStringIndex(body[end:])
			if nxt == nil {
				break
			}
			at := end + nxt[1]
			o2 := at + bytes.IndexByte(b[at:], '{')
			c2 := cutil.Match(b, o2)
			if c2 < 0 {
				return "", 0, fmt.Errorf("utf8only: an else block is unbalanced")
			}
			end = c2 + strings.IndexByte(body[c2:], '\n') + 1
		}
		if head == "if" {
			kept := string(cutil.Dedent4([]byte(
				body[o+strings.IndexByte(body[o:], '\n')+1 : strings.LastIndexByte(body[:c], '\n')+1])))
			body = body[:k] + kept + body[end:]
		} else {
			lineEnd := mm[0] + strings.IndexByte(body[mm[0]:], '\n')
			body = body[:mm[0]] + indent + "else" + body[lineEnd:tailStart] + body[end:]
		}
		n++
	}
}

// Utf8Only leaves no test of the encoding to answer.
func Utf8Only(text []byte, w io.Writer) ([]byte, error) {
	if n := len(flagDecls.FindAll(text, -1)); n != 5 {
		return nil, fmt.Errorf("utf8only: expected five flag declarations, found %d", n)
	}
	text = flagDecls.ReplaceAll(text, nil)

	a, z, ok := cutil.FindDefinition(text, cutil.Blank(text), "mb_init")
	if !ok {
		return nil, fmt.Errorf("utf8only: mb_init is not defined at file scope")
	}
	seg := text[a:z]
	if n := len(flagAssign.FindAll(seg, -1)); n != 5 {
		return nil, fmt.Errorf("utf8only: expected five assignments in mb_init, found %d", n)
	}
	seg = flagAssign.ReplaceAll(seg, nil)
	var buf []byte
	buf = append(buf, text[:a]...)
	buf = append(buf, seg...)
	text = append(buf, text[z:]...)
	fmt.Fprintln(w, "  utf8only     the five flags lose their declarations and mb_init() "+
		"its assignments")

	marks := 0
	for _, f := range utf8Flags {
		re := regexp.MustCompile(`\b` + f.name + `\b`)
		marks += len(re.FindAll(text, -1))
		text = re.ReplaceAll(text, []byte(f.tok))
	}
	fmt.Fprintf(w, "  utf8only     %d mentions become constant markers\n", marks)

	// Which functions hold a marker, in the order they first appear -- the
	// Python builds this with bisect over the function heads.
	type head struct {
		at   int
		name string
	}
	var heads []head
	for _, m := range funcHeads.FindAllSubmatchIndex(text, -1) {
		heads = append(heads, head{m[0], string(text[m[2]:m[3]])})
	}
	starts := make([]int, len(heads))
	for i, h := range heads {
		starts[i] = h.at
	}
	var names []string
	seen := map[string]bool{}
	for _, mk := range markRe.FindAllIndex(text, -1) {
		k := sort.SearchInts(starts, mk[0]+1) - 1
		if k >= 0 && !seen[heads[k].name] {
			seen[heads[k].name] = true
			names = append(names, heads[k].name)
		}
	}

	exprs, folds := 0, 0
	for _, name := range names {
		fa, fz, ok := cutil.FindDefinition(text, cutil.Blank(text), name)
		if !ok {
			return nil, fmt.Errorf("utf8only: %s holds a marker and is not a function at "+
				"file scope", name)
		}
		body := string(text[fa:fz])
		body, c1 := simplifyFunction(body)
		body, c2, err := foldControls(body)
		if err != nil {
			return nil, err
		}
		body, c3 := simplifyFunction(body)
		body, c4, err := foldControls(body)
		if err != nil {
			return nil, err
		}
		exprs += c1 + c3
		folds += c2 + c4
		var nb []byte
		nb = append(nb, text[:fa]...)
		nb = append(nb, body...)
		text = append(nb, text[fz:]...)
	}
	fmt.Fprintf(w, "  utf8only     %d expression simplifications and %d statement folds "+
		"in %d functions\n", exprs, folds, len(names))

	left := len(markRe.FindAll(text, -1))
	text = bytes.ReplaceAll(text, []byte(markT), []byte("TRUE"))
	text = bytes.ReplaceAll(text, []byte(markF), []byte("FALSE"))
	text = regexp.MustCompile(`\b__Z__\b`).ReplaceAll(text, []byte("0"))
	fmt.Fprintf(w, "  utf8only     %d constants left where they are an operand or a value, "+
		"written as TRUE, FALSE or 0\n", left)
	for _, f := range utf8Flags {
		if regexp.MustCompile(`\b` + f.name + `\b`).Match(text) {
			return nil, fmt.Errorf("utf8only: %s is still named", f.name)
		}
	}
	fmt.Fprintln(w, "  utf8only     no test of the encoding is left to answer")
	return text, nil
}
