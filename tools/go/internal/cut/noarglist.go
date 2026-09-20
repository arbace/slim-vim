package cut

import (
	"fmt"
	"io"
	"regexp"
	"strings"
)

var (
	// The Python writes this as one pattern with a NEGATIVE LOOKAHEAD,
	// `^(?![ \t]*\[?CMD_)...`, which RE2 cannot spell.  What it means is "a
	// line naming one of these and not itself a table row", which is two
	// tests over the lines.
	arglistNamed = regexp.MustCompile(`\bCMD_(argdo|snext|argdelete)\b`)
	arglistRow   = regexp.MustCompile(`^[ \t]*\[?CMD_`)
)

// NoArgList leaves only :next and :previous walking the argument list.
func NoArgList(text []byte, w io.Writer) ([]byte, error) {
	e := ed{"noarglist", w}
	var err error

	text, err = e.inFunction(text, "ex_next", func(seg []byte) ([]byte, error) {
		return e.literal(seg, " || eap->cmdidx == CMD_snext", "",
			":next asking whether it was :snext", 1)
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "do_argfile", func(seg []byte) ([]byte, error) {
		return e.literal(seg, "    else if (eap->cmdidx != CMD_argdo)\n", "    else\n",
			"do_argfile sparing :argdo the mark", 1)
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "ex_listdo", func(seg []byte) ([]byte, error) {
		seg, err := e.subOnce(seg,
			`^[ \t]*case CMD_argdo:\n[ \t]*i = eap->line1 - 1;\n[ \t]*break;\n`,
			":argdo's starting index")
		if err != nil {
			return nil, err
		}
		seg, err = e.foldNever(seg, `^[ \t]*if \(eap->cmdidx == CMD_argdo\)$`,
			":argdo stepping through the list")
		if err != nil {
			return nil, err
		}
		return e.foldNever(seg, `^[ \t]*if \(eap->cmdidx == CMD_argdo && i >= eap->line2\)$`,
			":argdo stopping at its range")
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "set_context_by_cmdname", func(seg []byte) ([]byte, error) {
		seg, err := e.subOnce(seg, `^[ \t]*case CMD_argdo:\n`, "completion for :argdo")
		if err != nil {
			return nil, err
		}
		return e.subOnce(seg, `^[ \t]*case CMD_argdelete:\n`+
			`[ \t]*while \(\(xp->xp_pattern = vim_strchr\(arg, ' '\)\) != NULL\)\n`+
			`[ \t]*\{\n[ \t]*arg = xp->xp_pattern \+ 1;\n[ \t]*\}\n`+
			`[ \t]*xp->xp_context = EXPAND_ARGLIST;\n[ \t]*xp->xp_pattern = arg;\n`+
			`[ \t]*break;\n\n`, "completion for :argdelete")
	})
	if err != nil {
		return nil, err
	}

	text, err = e.literal(text, "        {EXPAND_ARGLIST, get_arglist_name, TRUE, FALSE},\n", "",
		"the argument-list expansion", 1)
	if err != nil {
		return nil, err
	}

	if left := linesMatchingUnless(text, arglistNamed, arglistRow); len(left) > 0 {
		for i, l := range left {
			left[i] = strings.TrimSpace(l)
		}
		return nil, fmt.Errorf("noarglist: still named outside the table: %s",
			strings.Join(left, "; "))
	}

	e.say("only :next and :previous walk the argument list")
	return text, nil
}
