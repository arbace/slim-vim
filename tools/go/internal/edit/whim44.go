package edit

import (
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

// bangRow is the nv_cmds[] row for the `!` operator.  A row is POINTED AT
// nv_error and never deleted: nv_cmd_idx[] is a sorted index computed once and
// written into the C, so deleting a row leaves the index its old length and
// every key past the hole resolving to another key's row.
var bangRow = regexp.MustCompile(`(?m)^([ \t]*\{'!', )nv_operator(, 0, 0\} ,)$`)

var retabCompletion = regexp.MustCompile(`(?m)^[ \t]*case CMD_retab:\n[ \t]*xp->xp_context = EXPAND_RETAB;\n[ \t]*xp->xp_pattern = arg;\n[ \t]*break;\n\n`)

// Whim44 takes the filter operator and :retab's completion.
func Whim44(text []byte, w io.Writer) ([]byte, error) {
	if n := len(bangRow.FindAll(text, -1)); n != 1 {
		return nil, fmt.Errorf("whim44: the ! operator row -- matched %d times", n)
	}
	text = bangRow.ReplaceAll(text, []byte("${1}nv_error${2}"))
	fmt.Fprintln(w, "  filters      the ! operator's row points at nv_error")

	blanked := cutil.Blank(text)
	a, z, ok := cutil.FindDefinition(text, blanked, "set_context_by_cmdname")
	if !ok {
		return nil, fmt.Errorf("whim44: set_context_by_cmdname is not defined at file scope")
	}
	fn := text[a:z]
	if n := len(retabCompletion.FindAll(fn, -1)); n != 1 {
		return nil, fmt.Errorf("whim44: completion for :retab -- matched %d times", n)
	}
	out := append([]byte{}, text[:a]...)
	out = append(out, retabCompletion.ReplaceAll(fn, nil)...)
	out = append(out, text[z:]...)
	fmt.Fprintln(w, "  filters      completion for :retab")
	return out, nil
}

func init() { register("whim44", Whim44) }
