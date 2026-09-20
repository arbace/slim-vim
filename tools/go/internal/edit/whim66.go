package edit

import (
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

// methodTest is `if (cap->nchar == 'm' || cap->nchar == 'M')`, which appears
// TWICE in nv_bracket_block: the head that picks the character to match, and
// the half that walks out to the method.
const methodTest = `(?m)^[ \t]*if \(cap->nchar == 'm' \|\| cap->nchar == 'M'\)$`

// Whim66 takes the sentence, paragraph and section motions, the bracket
// commands that found a comment or a method, and the text objects for them.
func Whim66(text []byte, w io.Writer) ([]byte, error) {
	e := New("nopara", text, w)

	for _, m := range []struct{ key, handler, what string }{
		{`\(`, "nv_brace", "( by sentence"},
		{`\)`, "nv_brace", ") by sentence"},
		{`\{`, "nv_findpar", "{ by paragraph"},
		{`\}`, "nv_findpar", "} by paragraph"},
	} {
		e.Sub(fmt.Sprintf(`(?m)^([ \t]*\{'%s', )%s(, 0, [^}]*\} ,)$`, m.key, m.handler),
			"${1}nv_error${2}", 1, fmt.Sprintf("%s points at nv_error", m.what))
	}
	e.InFunction("nv_brackets", func(e *E) {
		e.FoldNever(`(?m)^[ \t]*else if \(cap->nchar == '\[' \|\| cap->nchar == '\]'\)$`, "[[ ]] [] ][ by section")
	})
	e.Literal(`vim_strchr((char_u *)"{(*/#mM", cap->nchar)`, `vim_strchr((char_u *)"{(", cap->nchar)`,
		"[ no longer taking a comment, #if or method")
	e.Literal(`vim_strchr((char_u *)"})*/#mM", cap->nchar)`, `vim_strchr((char_u *)"})", cap->nchar)`,
		"] no longer taking a comment, #if or method")

	e.InFunction("nv_bracket_block", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(cap->nchar == '\*'\)$`, "[* and ]* spelled as [/ and ]/")
		e.FoldAlways(`(?m)^[ \t]*if \(cap->nchar != 'm' && cap->nchar != 'M'\)$`,
			"a miss beeping, which only a method did not")
		// The counted helpers cannot express "the second of two" -- they refuse
		// on any count but the one given -- so the walk-out is cut from a slice
		// that STARTS at it, and only then is the head the single match the
		// counted fold wants.
		if !e.Failed() {
			re := regexp.MustCompile(methodTest)
			hits := re.FindAllIndex(e.Text(), -1)
			if len(hits) != 2 {
				e.Refuse("nv_bracket_block -- the method test matched %d times, expected 2", len(hits))
				return
			}
			t := e.Text()
			cut := lastNewlineBefore(t, hits[1][0]) + 1
			tail, err := cutil.DropIf(t[cut:], methodTest, 1)
			if err != nil {
				e.Refuse("walking out to a method start or end -- %v", err)
				return
			}
			e.Set(append(append([]byte{}, t[:cut]...), tail...))
			e.say("walking out to a method start or end")
		}
		e.FoldNever(methodTest, "a method's braces choosing the character to match")
		e.Lines(`pos_T[ \t]+prev_pos;`, 1, "nv_bracket_block declaring prev_pos")
		e.Lines(`prev_pos\.lnum = 0;`, 1, "the previous match, which only a method walk-out read")
		e.Lines(`prev_pos = new_pos;`, 1, "remembering the previous match")
	})

	e.InFunction("nv_object", func(e *E) {
		e.Cut(`(?m)^[ \t]*case 'p':\n[ \t]*flag = current_par\(cap->oap, cap->count1, include, 'p'\);\n[ \t]*break;\n`, 1,
			"ip and ap, the paragraph objects")
		e.Cut(`(?m)^[ \t]*case 's':\n[ \t]*flag = current_sent\(cap->oap, cap->count1, include\);\n[ \t]*break;\n`, 1,
			"is and as, the sentence objects")
	})

	e.FoldNever(`(?m)^[ \t]*else if \(c == '\{' \|\| c == '\}'\)$`, "'{ and '} as line addresses")
	e.FoldNever(`(?m)^[ \t]*else if \(c == '\(' \|\| c == '\)'\)$`, "'( and ') as line addresses")
	return e.Done()
}

func init() { register("whim66", Whim66) }
