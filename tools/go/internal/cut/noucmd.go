package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

const ucmdDispatch = `    if ( ((int)(ea.cmdidx) < 0) )
    {
        do_ucmd(&ea);
    }
    else
    {
`

var (
	ucmdComplRows = regexp.MustCompile(
		`(?m)^[ \t]*\{EXPAND_USER_(?:COMMANDS|ADDR_TYPE|CMD_FLAGS|NARGS|COMPLETE|COMPLETEOPT), ` +
			`get_user_(?:commands|cmd[a-z_]*), FALSE, TRUE\},\n`)
	ucmdFindA = regexp.MustCompile(`(?m)^[ \t]*p = find_ucmd\(eap, p, NULL, xp, complp\);\n`)
	ucmdFindB = regexp.MustCompile(`(?m)^[ \t]*p = find_ucmd\(eap, p, full, NULL, NULL\);\n`)
	ucmdCtx   = regexp.MustCompile(
		`(?m)^[ \t]*case CMD_command:\n[ \t]*return set_context_in_user_cmd\(xp, arg\);\n\n?` +
			`[ \t]*case CMD_delcommand:\n[ \t]*xp->xp_context = EXPAND_USER_COMMANDS;\n` +
			`[ \t]*xp->xp_pattern = arg;\n[ \t]*break;\n\n?`)
	ucmdLeft = regexp.MustCompile(`\b(?:do_ucmd|ucmds)\b`)
)

// NoUcmd removes user-defined commands.
func NoUcmd(text []byte, w io.Writer) ([]byte, error) {
	k := bytes.Index(text, []byte(ucmdDispatch))
	if k < 0 {
		return nil, fmt.Errorf("noucmd: the user-command dispatch is not where this expects")
	}
	// Keep the else body: an unknown name has already been rejected upstream.
	blanked := cutil.Blank(text)
	elseAt := k + len(ucmdDispatch) - 30
	elseAt += bytes.Index(text[elseAt:], []byte("else"))
	o := elseAt + bytes.IndexByte(blanked[elseAt:], '{')
	c := cutil.Match(blanked, o)
	if c < 0 {
		return nil, fmt.Errorf("noucmd: the user-command dispatch is unbalanced")
	}
	body := cutil.Dedent4(text[o+bytes.IndexByte(text[o:], '\n')+1 : bytes.LastIndexByte(text[:c], '\n')+1])
	end := c + bytes.IndexByte(text[c:], '\n') + 1
	var buf []byte
	buf = append(buf, text[:k]...)
	buf = append(buf, body...)
	text = append(buf, text[end:]...)
	fmt.Fprintln(w, "  noucmd       the dispatch for a name that is not in cmdnames[]")

	// Six rows of the completion table keep six get_user_cmd_* functions
	// alive, and expand_user_command_name() is how `:`-completion walks past
	// the end of cmdnames[] into the user table.  None of them was found by
	// grepping for do_ucmd -- A TABLE ROW IS A REFERENCE THE SAME AS A CALL.
	if n := len(ucmdComplRows.FindAll(text, -1)); n != 6 {
		return nil, fmt.Errorf("noucmd: expected 6 completion rows, matched %d", n)
	}
	text = ucmdComplRows.ReplaceAll(text, nil)
	text = bytes.Replace(text,
		[]byte("    return get_user_commands(NULL, idx - (int)CMD_SIZE);"),
		[]byte("    return NULL;"), 1)

	// find_ucmd() looks a name up in the user table; two callers, one in the
	// completion path and one in do_one_cmd's name scan.
	n := 0
	var hit bool
	if text, hit = replaceFirst(ucmdFindA, text, ""); hit {
		n++
	}
	if text, hit = replaceFirst(ucmdFindB, text, ""); hit {
		n++
	}
	if n != 2 {
		return nil, fmt.Errorf("noucmd: find_ucmd has %d callers here, expected 2", n)
	}

	if text, hit = replaceFirst(ucmdCtx, text, ""); !hit {
		return nil, fmt.Errorf("noucmd: the :command completion contexts are not where this expects")
	}
	fmt.Fprintln(w, "  noucmd       six completion rows, the name walk past cmdnames[], "+
		"and two completion contexts")

	var err error
	if text, err = cutCounted(text, `(?m)^[ \t]*uc_clear\(&buf->b_ucmds\);\n`,
		"noucmd", "the buffer's table", 1); err != nil {
		return nil, err
	}
	if text, err = cutCounted(text, `(?m)^[ \t]*garray_T    b_ucmds;\n`,
		"noucmd", "the b_ucmds field", 1); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  noucmd       the per-buffer command table")

	fmt.Fprintf(w, "  noucmd       %d do_ucmd/ucmds mentions left for the sweep\n",
		len(ucmdLeft.FindAll(text, -1)))
	return text, nil
}
