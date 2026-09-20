package edit

import (
	"io"
	"regexp"
	"strings"
)

var (
	btEngineWrite = regexp.MustCompile(`(?m)^[ \t]*prog->re_engine = BACKTRACKING_ENGINE;[ \t]*$`)
	retryOther    = `(?m)^[ \t]*if \(rmp->regprog->re_engine == AUTOMATIC_ENGINE && result ==  \(-1\) \)$`
)

// assignsTo is writesTo with `->name` fields included -- written the careful way
// after whim75, where a first guard matched `name[^\n;]*=` and reported the `!=`
// of three predicates as writes.  An assertion that cries wolf invites being
// loosened until it passes.
func assignsTo(text []byte, name string) []int {
	var out []int
	re := regexp.MustCompile(`\b` + regexp.QuoteMeta(name) + `\b`)
	for _, m := range re.FindAllIndex(text, -1) {
		end := m[1] + 80
		if end > len(text) {
			end = len(text)
		}
		s := strings.TrimLeft(string(text[m[1]:end]), " \t\n")
		if strings.HasPrefix(s, "[") {
			depth := 0
			for i, ch := range s {
				if ch == '[' {
					depth++
				} else if ch == ']' {
					depth--
					if depth == 0 {
						s = s[i+1:]
						break
					}
				}
			}
			s = strings.TrimLeft(s, " \t\n")
		}
		if strings.HasPrefix(s, "=") && !strings.HasPrefix(s, "==") {
			out = append(out, 1+countNewlines(text[:m[0]]))
		}
	}
	return out
}

// Whim76 leaves one regexp engine, having first proved there is only one.
func Whim76(text []byte, w io.Writer) ([]byte, error) {
	e := New("oneengine", text, w)

	if ws := assignsTo(text, "re_engine"); len(ws) != 1 {
		e.Refuse("re_engine is assigned in %d place(s) (lines %s), not once -- a second engine may exist and both retry blocks may be reachable",
			len(ws), joinInts(ws))
		return e.Done()
	}
	if !btEngineWrite.Match(text) {
		e.Refuse("the one assignment to re_engine is not to BACKTRACKING_ENGINE")
		return e.Done()
	}
	for _, gone := range []string{"nfa_regengine", "regexp_engine"} {
		if regexp.MustCompile(`\b` + gone + `\b`).Match(text) {
			e.Refuse("%s still exists -- the NFA engine is back and this phase is wrong", gone)
			return e.Done()
		}
	}
	e.say("confirmed: re_engine is written once, to BACKTRACKING_ENGINE, and only there")

	e.FoldNeverIn2("vim_regexec_string", retryOther, "a failed match recompiling with the other engine", 1)
	e.FoldNeverIn2("vim_regexec_multi", retryOther, "and the multi-line variant of the same", 1)
	e.InFunction("check_num_option_bounds", func(e *E) {
		e.Literal(w76lit2, "", "validating an option nothing can set")
	})
	e.Lines(`static long[ \t]+p_re;`, 1, "'regexpengine', which had no row to set it")
	e.Lines(`enum \{ AUTOMATIC_ENGINE = 0 \};`, 1, "the engine it chose between")
	return e.Done()
}

func init() { register("whim76", Whim76) }
