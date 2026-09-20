package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

var (
	badCharWord = regexp.MustCompile(`\bbad_char\b`)
	badCharLine = regexp.MustCompile(`(?m)^[^\n]*\bbad_char\b[^\n]*$`)
	badBehavior = regexp.MustCompile(`\bbad_char_behavior\b`)
	elseHere    = regexp.MustCompile(`^[ \t]*else\b`)
)

// foldAll folds every occurrence, however many -- but at least one.
func (e ed) foldAll(seg []byte, pattern, what string) ([]byte, error) {
	re := regexp.MustCompile("(?m)" + pattern)
	n := len(re.FindAll(seg, -1))
	if n == 0 {
		return nil, fmt.Errorf("%s: %s -- no occurrence", e.tool, what)
	}
	out, err := cutil.FoldNever(seg, "(?m)"+pattern, n)
	if err != nil {
		return nil, fmt.Errorf("%s: %s -- %v", e.tool, what, err)
	}
	fmt.Fprintf(e.w, "  %-13s%s (%d)\n", e.tool, what, n)
	return out, nil
}

// keepThenChain handles `if (T) { A } else if ... else { ... }` with T always
// true: keep A, lose the rest of the chain.
//
// This is not FoldAlways, which refuses a block that has an else at all.  Here
// the else arms are the ones going, and there may be any number of them, so
// the walk continues while the next thing is an `else`.
func (e ed) keepThenChain(seg []byte, pattern, what string) ([]byte, error) {
	re := regexp.MustCompile("(?m)" + pattern)
	ms := re.FindAllIndex(seg, -1)
	if len(ms) != 1 {
		return nil, fmt.Errorf("%s: %s -- the condition occurs %d times, expected 1",
			e.tool, what, len(ms))
	}
	b := cutil.Blank(seg)
	k, o, c, head, err := cutil.Guarded(seg, b, ms[0])
	if err != nil {
		return nil, fmt.Errorf("%s: %s -- %v", e.tool, what, err)
	}
	if head != "if" {
		return nil, fmt.Errorf("%s: %s -- not a plain if", e.tool, what)
	}
	body := cutil.Dedent4(seg[o+bytes.IndexByte(seg[o:], '\n')+1 : bytes.LastIndexByte(seg[:c], '\n')+1])
	end := c + bytes.IndexByte(seg[c:], '\n') + 1
	for {
		nxt := elseHere.FindIndex(seg[end:])
		if nxt == nil {
			break
		}
		o2 := end + nxt[1] + bytes.IndexByte(b[end+nxt[1]:], '{')
		c2 := cutil.Match(b, o2)
		if c2 < 0 {
			return nil, fmt.Errorf("%s: %s -- an else arm is unbalanced", e.tool, what)
		}
		end = c2 + bytes.IndexByte(seg[c2:], '\n') + 1
	}
	e.say(what)
	out := make([]byte, 0, len(seg))
	out = append(out, seg[:k]...)
	out = append(out, body...)
	return append(out, seg[end:]...), nil
}

// KeepBytes makes an invalid byte kept, with nothing able to ask otherwise.
func KeepBytes(text []byte, w io.Writer) ([]byte, error) {
	e := ed{"keepbytes", w}
	var err error

	text, err = e.inFunction(text, "readfile", func(s []byte) ([]byte, error) {
		s, err := e.subOnce(s,
			`^[ \t]*if \(eap != NULL && eap->bad_char != 0\)\n[ \t]*\{\n`+
				`[ \t]*bad_char_behavior = eap->bad_char;\n`+
				`[ \t]*if \(set_options\)\n[ \t]*\{\n`+
				`[ \t]*curbuf->b_bad_char = eap->bad_char;\n[ \t]*\}\n[ \t]*\}\n`+
				`[ \t]*else\n[ \t]*\{\n[ \t]*curbuf->b_bad_char = 0;\n[ \t]*\}\n\n`,
			"readfile taking the behaviour from ++bad")
		if err != nil {
			return nil, err
		}
		// -1 means keep.  Drop (-2) never happens and neither does a replacement.
		s, err = e.foldAll(s, `^[ \t]*if \(bad_char_behavior ==  \(-2\) \)$`,
			"an invalid byte dropped")
		if err != nil {
			return nil, err
		}
		// The spacing is the expander's: `(-1) )` alone, `(-1)  && (...)` with two.
		s, err = e.foldAll(s, `^[ \t]*if \(bad_char_behavior !=  \(-1\)`+
			`(?: \)|  && \(fio_flags != 0 \|\| iconv_fd != \(iconv_t\)-1\)\))$`,
			"an invalid byte replaced")
		if err != nil {
			return nil, err
		}
		// After the drop test folds, the conversion loop's chain starts with
		// the keep test.
		s, err = e.keepThenChain(s, `^[ \t]*if \(bad_char_behavior ==  \(-1\) \)$`,
			"a converted invalid byte kept as it is")
		if err != nil {
			return nil, err
		}
		s, err = e.literal(s, " || (illegal_byte > 0 && bad_char_behavior !=  (-1) )", "",
			"an illegal byte making the buffer read-only", 1)
		if err != nil {
			return nil, err
		}
		s, err = e.subOnce(s, `^[ \t]*int[ \t]+bad_char_behavior = BAD_REPLACE;\n`,
			"readfile declaring the behaviour")
		if err != nil {
			return nil, err
		}
		if badBehavior.Match(s) {
			return nil, fmt.Errorf("keepbytes: readfile still names bad_char_behavior")
		}
		return s, nil
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "getargopt", func(s []byte) ([]byte, error) {
		s, err := e.foldAll(s,
			`^[ \t]*else if \( strncmp\(\(char \*\)\(arg\), \(char \*\)\("bad"\), \(3\)\)  == 0\)$`,
			"++bad")
		if err != nil {
			return nil, err
		}
		s, err = e.keepThenChain(s, `^[ \t]*if \(pp == &eap->force_enc\)$`,
			"++enc's value, the only one left to check")
		if err != nil {
			return nil, err
		}
		return e.subOnce(s, `^[ \t]*int[ \t]+bad_char_idx;\n`, "getargopt's ++bad index")
	})
	if err != nil {
		return nil, err
	}

	// The Python writes this as `\bbad_char\b(?!_)`, and the lookahead is
	// REDUNDANT rather than unspellable: `_` is a word character, so a word
	// boundary after "bad_char" already cannot occur inside
	// "bad_char_behavior".  Measured on the whole corpus, the two agree.
	if badCharWord.Match(bytes.ReplaceAll(text, []byte("int         bad_char;"), nil)) {
		var live []string
		for _, m := range badCharLine.FindAll(text, -1) {
			line := string(m)
			if strings.Contains(line, "int         bad_char;") ||
				strings.Contains(line, "get_bad_opt") {
				continue
			}
			line = strings.TrimSpace(line)
			if strings.HasPrefix(line, "eap->bad_char =") {
				continue
			}
			live = append(live, line)
		}
		if len(live) > 0 {
			return nil, fmt.Errorf("keepbytes: eap->bad_char still read: %s", pyList(live))
		}
	}

	e.say("an invalid byte is kept, and nothing can ask otherwise")
	return text, nil
}
