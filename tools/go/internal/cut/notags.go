package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"
)

// notagsEdits are the seven places a tag could still be asked for, each with
// the words its refusal uses.  Every one is COUNTED: a tag edit that matched
// twice would take a second construct with the same shape somewhere else in the
// file, and one that matched none has had its anchor moved under it.
var notagsEdits = []struct {
	what, pat, repl string
	want            int
}{
	{"the <Help> key, which reached do_tag through ex_help",
		`(?m)[ \t]*if \(!checkclearopq\(cap->oap\)\)\n[ \t]*\{\n` +
			`[ \t]*ex_help\(NULL\);\n[ \t]*\}\n`,
		"    (void)checkclearopq(cap->oap);\n", 1},
	{"CTRL-T, the tag stack pop",
		`(?m)[ \t]*if \(!checkclearopq\(cap->oap\)\)\n[ \t]*\{\n` +
			`[ \t]*do_tag\(\(char_u \*\)"", DT_POP[^\n]*\n[ \t]*\}\n`,
		"    (void)checkclearopq(cap->oap);\n", 1},
	{"tag completion on the command line",
		`(?m)[ \t]*if \(xp->xp_context == EXPAND_TAGS \|\| xp->xp_context == EXPAND_TAGS_LISTFILES\)\n` +
			`[ \t]*\{\n[ \t]*return expand_tags\([^\n]*\n[ \t]*\}\n`, "", 1},
	{"help-tag completion on the command line",
		`(?m)[ \t]*if \(xp->xp_context == EXPAND_HELP\)\n[ \t]*\{\n` +
			`[ \t]*if \(find_help_tags\([^\n]*\n[ \t]*\{\n[ \t]*return OK;\n[ \t]*\}\n` +
			`[ \t]*return FAIL;\n[ \t]*\}\n\n?`, "", 1},
	{"the ten command cases that asked for a tag context",
		`(?m)(?:[ \t]*case CMD_(?:tag|stag|ptag|ltag|tselect|stselect|ptselect|tjump|stjump|ptjump):\n)+` +
			`[ \t]*if \(vim_strchr\(p_wop, WOP_TAGFILE\) != NULL\)\n` +
			`[ \t]*\{\n[^\n]*\n[ \t]*\}\n[ \t]*else\n[ \t]*\{\n[^\n]*\n[ \t]*\}\n` +
			`[ \t]*xp->xp_pattern = arg;\n[ \t]*break;\n`, "", 1},
	{"CTRL-X CTRL-] tag completion in insert mode",
		`(?m)[ \t]*case  \(5 \+ CTRL_X_WANT_IDENT\) :\n` +
			`[ \t]*get_next_tag_completion\(\);\n[ \t]*break;\n\n?`, "", 1},
	{"-complete=tag as a name :command accepts",
		`(?m)[ \t]*\{\(EXPAND_TAGS\), \{\(\(char_u \*\)"tag"\),[^\n]*\n`, "", 1},
}

// NoTags removes every way to ask for a tag.
func NoTags(text []byte, w io.Writer) ([]byte, error) {
	for _, e := range notagsEdits {
		re := regexp.MustCompile(e.pat)
		n := len(re.FindAll(text, -1))
		if n != e.want {
			return nil, fmt.Errorf("notags: %s -- expected %d, matched %d", e.what, e.want, n)
		}
		text = re.ReplaceAllLiteral(text, []byte(e.repl))
		fmt.Fprintf(w, "  notags       %s\n", e.what)
	}
	fmt.Fprintf(w, "  notags       %d do_tag mentions and %d find_tags mentions left "+
		"for the sweep\n",
		bytes.Count(text, []byte("do_tag")), bytes.Count(text, []byte("find_tags")))
	return text, nil
}
