package edit

import (
	"bytes"
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

var (
	nextcmdCalls = regexp.MustCompile(`\bseparate_nextcmd\(([^;]*)\);`)
	cmdArgtRow   = func(c string) *regexp.Regexp {
		return regexp.MustCompile(`(?m)^    \[CMD_` + c + `\] = \{.*\(long_u\)\(([^)]*)\)`)
	}
)

// term replaces a fragment n times, refusing on any other count.  It is
// Literal under whim81's own name.
func (e *E) term(frag, repl string, n int, what string) { e.LiteralN(frag, repl, n, what) }

// Whim81 makes a command line one command: no bar separator and no trailing
// comment, so `|` and `"` stop being syntax.
func Whim81(text []byte, w io.Writer) ([]byte, error) {
	e := New("onecommand", text, w)

	var calls []string
	for _, m := range nextcmdCalls.FindAllSubmatch(text, -1) {
		c := string(m[1])
		if !bytes.HasPrefix([]byte(c), []byte("exarg_T")) {
			calls = append(calls, c)
		}
	}
	if len(calls) != 1 || calls[0] != "&ea, FALSE" {
		e.Refuse("separate_nextcmd is called as %s, expected once with FALSE", cutil.PyRepr(fmt.Sprint(calls)))
		return e.Done()
	}
	for _, c := range []string{"append", "insert", "change"} {
		m := cmdArgtRow(c).FindSubmatch(text)
		if m == nil || bytes.Contains(m[1], []byte("EX_EXTRA")) {
			e.Refuse(":%s is not a command without EX_EXTRA", c)
			return e.Done()
		}
	}
	e.say("confirmed: one caller of separate_nextcmd, and :append, :insert, :change take no argument")

	e.term("        else if ((*p == '\"' && !(eap->argt & EX_NOTRLCOM) && ((eap->cmdidx != CMD_at && eap->cmdidx != CMD_star) || p != eap->arg)) || (*p == '|' && eap->cmdidx != CMD_append && eap->cmdidx != CMD_change && eap->cmdidx != CMD_insert) || *p == '\\n')",
		"        else if (*p == '\\n')", 1, "separate_nextcmd splits at a newline and nothing else")
	e.term("if ((eap->argt & (EX_CTRLV | EX_XFILE)) || keep_backslash)",
		"if (eap->argt & (EX_CTRLV | EX_XFILE))", 1, "its one caller never keeps a backslash")
	e.FoldAlways(`(?m)^[ \t]*if \(!keep_backslash\)$`, "so a backslash before a newline always goes")
	e.term(w81lit1, "    return (c == NUL || c == '\\n');", 1, "ends_excmd: the end of the line")
	e.term(w81lit2, "    return (c == NUL || c == '\\n');", 1, "ends_excmd2: the same")
	e.term(w81lit3, w81lit4, 1, "find_nextcmd: the next line")
	e.term(w81lit5, w81lit6, 1, "check_nextcmd: the same")
	e.term("if (!(ea.argt & EX_EXTRA) && *ea.arg != NUL && *ea.arg != '\"' && (*ea.arg != '|' || (ea.argt & EX_TRLBAR) == 0))",
		"if (!(ea.argt & EX_EXTRA) && *ea.arg != NUL)", 1, "a bar or a quote after a command is trailing characters")
	e.term("if (*ea.cmd == NUL || comment_start(ea.cmd, starts_with_colon) || (ea.nextcmd = check_nextcmd(ea.cmd)) != NULL)",
		"if (*ea.cmd == NUL || (ea.nextcmd = check_nextcmd(ea.cmd)) != NULL)", 1, "a line that is a comment is not empty")
	e.Lines(`int         starts_with_colon = FALSE;`, 1, "do_one_cmd no longer asks where the colon was")
	e.DropIf(`(?m)^[ \t]*if \(comment_start\(eap->cmd, starts_with_colon\)\)$`, "the modifier parser skips no comment")
	e.DropIf(`(?m)^[ \t]*if \(\*eap->cmd == ':'\)$`, "and records no colon")
	e.Lines(`int     starts_with_colon = FALSE;`, 1, "nor keeps the flag")
	e.term("if ((*eap->cmd == '|' || (exmode_active && eap->cmd != (char_u *)exmode_plus + 1)))",
		"if (exmode_active && eap->cmd != (char_u *)exmode_plus + 1)", 1, "`:|` no longer prints the line")
	e.term(w81lit7, w81lit8, 1, ":substitute takes no trailing comment")
	e.FoldNever(`(?m)^[ \t]*if \(\*eap->arg == '\|'\)$`, ":append takes no text after a bar")

	// The closing assertion: the six parsers must no longer mention either
	// character at all, and comment_start must have lost its last caller.
	for _, p := range []struct{ pat, what string }{{`'\|'`, "a bar"}, {`'"'`, "a quote"}} {
		for _, fn := range []string{"separate_nextcmd", "ends_excmd", "ends_excmd2", "find_nextcmd", "check_nextcmd", "do_one_cmd"} {
			if e.Failed() {
				return e.Done()
			}
			body, ok := e.BodyOf(fn)
			if !ok {
				e.Refuse("%s is not defined", fn)
				return e.Done()
			}
			if regexp.MustCompile(p.pat).Match(body) {
				e.Refuse("%s still tests for %s", fn, p.what)
				return e.Done()
			}
		}
	}
	if !e.Failed() {
		stripped := bytes.ReplaceAll(e.Text(), []byte("comment_start(char_u"), nil)
		if bytes.Contains(stripped, []byte("comment_start(")) {
			e.Refuse("comment_start still has a caller")
			return e.Done()
		}
		e.say("no command parser tests for a bar or a quote")
	}
	return e.Done()
}

func init() { register("whim81", Whim81) }
