package edit

import (
	"fmt"
	"io"
	"regexp"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

var (
	autopatDecl  = regexp.MustCompile(`(?m)^static AutoPat \*first_autopat\[NUM_EVENTS\] = \{ NULL \};$`)
	bareDispatch = regexp.MustCompile(`(?m)^[ \t]*(?:\(void\))?apply_autocmds\w*\([^\n]*\);[ \t]*\n`)
	cmdTrigger   = regexp.MustCompile(`(?m)^[ \t]*trigger_cmd_autocmd\([^\n]*\);[ \t]*\n`)
	bareDeclOnly = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*[ \t]+\*?[A-Za-z_][A-Za-z0-9_]*;$`)
)

// writesTo returns the 1-based line of every assignment TO name, or to an
// element of it.
//
// It steps over a BALANCED SUBSCRIPT and only then looks at the operator.  A
// first version matched `name[^\n;]*=` and reported three writes that were the
// `!=` of the has_* predicates -- it spanned the subscript and landed on the
// comparison.  AN ASSERTION THAT CRIES WOLF IS WORSE THAN NONE, because the
// temptation is to loosen it until it passes.
func writesTo(text []byte, name string) []int {
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

// dropBareBlock deletes the innermost block enclosing a statement, REFUSING if
// that block still does real work -- anything but the statement itself and bare
// declarations.  It is for the husk a removed call leaves behind.
func (e *E) dropBareBlock(fn, stmt, what string) {
	e.InFunction(fn, func(e *E) {
		if e.Failed() {
			return
		}
		b := cutil.Blank(e.text)
		i := indexFrom(e.text, []byte(stmt), 0)
		if i < 0 {
			e.die("%s -- %s is not in %s", what, cutil.PyRepr(stmt), fn)
			return
		}
		depth, j := 0, i
		for ; j >= 0; j-- {
			if b[j] == '}' {
				depth++
			} else if b[j] == '{' {
				if depth == 0 {
					break
				}
				depth--
			}
		}
		if j < 0 {
			e.die("%s -- no enclosing block", what)
			return
		}
		c := cutil.Match(b, j)
		if c < 0 {
			e.die("%s -- unbalanced block", what)
			return
		}
		body := e.text[indexFrom(e.text, []byte("\n"), j)+1 : lastNewlineBefore(e.text, c)+1]
		for _, line := range strings.Split(string(body), "\n") {
			line = strings.TrimSpace(line)
			if line == "" || line == stmt || bareDeclOnly.MatchString(line) {
				continue
			}
			if len(line) > 60 {
				line = line[:60]
			}
			e.die("%s -- the block still does real work: %s", what, cutil.PyRepr(line))
			return
		}
		k := lastNewlineBefore(e.text, j) + 1
		e.say(what)
		out := append([]byte{}, e.text[:k]...)
		e.text = append(out, e.text[indexFrom(e.text, []byte("\n"), c)+1:]...)
	})
}

// Whim75 removes the autocommand dispatch, having first PROVED that nothing can
// register one.
func Whim75(text []byte, w io.Writer) ([]byte, error) {
	e := New("noautocmd", text, w)

	if len(autopatDecl.FindAll(text, -1)) != 1 {
		e.Refuse("the first_autopat declaration is not where this phase expects it")
		return e.Done()
	}
	if ws := writesTo(text, "first_autopat"); len(ws) != 1 {
		e.Refuse("first_autopat is assigned in %d place(s), not just its all-NULL initialiser (lines %s) -- an autocommand CAN be registered and this whole phase is wrong",
			len(ws), joinInts(ws))
		return e.Done()
	}
	e.say("confirmed: first_autopat is only ever the all-NULL initialiser")

	e.InFunction("close_buffer", func(e *E) {
		e.Literal(w75OldCb, w75NewCb, "close_buffer, whose abort label three gotos still target")
	})
	e.FoldNeverIn2("buf_freeall", `(?m)^[ \t]*if \(apply_autocmds\(EVENT_BUFUNLOAD,`, "unloading a buffer asking the autocommands first", 1)
	e.FoldNeverIn2("buf_freeall", `(?m)^[ \t]*if \(apply_autocmds\(EVENT_BUFWIPEOUT,`, "wiping a buffer asking them", 1)
	e.FoldNeverIn2("buflist_new", `(?m)^[ \t]*if \(apply_autocmds\(EVENT_BUFNEW,`, "a new buffer announcing itself", 1)
	e.FoldNeverIn2("readfile", `(?m)^[ \t]*if \(apply_autocmds_exarg\(EVENT_BUFREADCMD,`, "a read being handled by an autocommand instead", 1)
	e.FoldNeverIn2("readfile", `(?m)^[ \t]*else if \(apply_autocmds_exarg\(EVENT_FILEREADCMD,`, "and the file-read variant of the same", 1)
	e.FoldAlwaysIn("set_curbuf", `(?m)^[ \t]*if \(!apply_autocmds\(EVENT_BUFLEAVE,`, "leaving a buffer asking permission", 1)
	e.FoldAlwaysIn("buf_write", `(?m)^[ \t]*if \(!\(did_cmd = apply_autocmds_exarg\(EVENT_FILEAPPENDCMD,`, "an autocommand taking over an append", 1)
	e.FoldAlwaysIn("buf_write", `(?m)^[ \t]*if \(!\(did_cmd = apply_autocmds_exarg\(EVENT_FILEWRITECMD,`, "an autocommand taking over a write", 1)
	e.FoldNeverIn2("ins_redraw", `(?m)^[ \t]*if \(ready && has_textchangedI\(\)`, "insert mode reporting a change", 1)
	e.FoldNeverIn2("ins_redraw", `(?m)^[ \t]*if \(ready && has_textchangedP\(\)`, "and the popup-menu variant", 1)
	e.FoldNeverIn2("do_one_cmd", `(?m)^[ \t]*if \(p != NULL && ea\.cmdidx == CMD_SIZE && !ea\.skip && [^\n]*has_cmdundefined\(\)\)$`,
		"an unknown command being defined by an autocommand", 1)
	e.InFunction("buf_write", func(e *E) {
		e.Literal(w75lit4, "", "an autocommand taking over the whole write")
	})
	e.Body("ins_apply_autocmds", w75lit2, "ins_apply_autocmds, which dispatched and watched the tick")
	e.InFunction("ui_focus_change", func(e *E) {
		e.Literal(w75lit5, "", "a focus change telling the autocommands")
	})
	e.InFunction("open_buffer", func(e *E) {
		e.Literal(w75lit6, w75lit7, "open_buffer, keeping the flag clearing the autocmd call was wrapped around")
	})
	e.DropBlocks("buf_write", `(?m)^[ \t]*if \(!got_int\)$`, 1, "the post-write announcements")
	e.DropBlocks("set_termname", `(?m)^[ \t]*if \(curbuf->b_ml\.ml_mfp != NULL\)$`, 1, "a new terminal telling every buffer")
	e.Lines(`ins_apply_autocmds\(EVENT_[A-Z]+\);`, 6, "the insert-mode dispatches")
	e.FoldNeverIn2("ins_redraw", `(?m)^[ \t]*if \(ready && \(has_cursormovedI\(\)\)`, "insert mode reporting the cursor moved", 1)
	e.InFunction("free_buffer", func(e *E) {
		e.Lines(`aubuflocal_remove\(buf\);`, 1, "a freed buffer detaching its buffer-local patterns")
	})
	for _, ev := range []string{"VIMLEAVEPRE", "VIMLEAVE"} {
		ev := ev
		e.InFunction("getout", func(e *E) {
			e.Literal(fmt.Sprintf(w75lit14, ev), "", fmt.Sprintf("quitting unblocking autocommands to announce EVENT_%s", ev))
		})
	}
	e.InFunction("do_one_cmd", func(e *E) {
		e.Literal(w75lit8, w75lit9, "asking whether the command came from an autocommand")
	})
	e.InFunction("getcmdline_int", func(e *E) {
		e.Lines(`int[ \t]+cmdline_type;`, 1, "the command-line type")
	})
	e.InFunction("getcmdline_int", func(e *E) {
		e.Lines(`cmdline_type = firstc == NUL \? '-' : firstc;`, 1, "and the line that set it")
	})
	if !e.Failed() {
		n := len(bareDispatch.FindAll(e.Text(), -1))
		e.Set(bareDispatch.ReplaceAll(e.Text(), nil))
		e.say(fmt.Sprintf("every remaining bare dispatch (%d)", n))
		n = len(cmdTrigger.FindAll(e.Text(), -1))
		e.Set(cmdTrigger.ReplaceAll(e.Text(), nil))
		e.say(fmt.Sprintf("the command-line triggers (%d)", n))
	}
	e.InFunction("buf_write", func(e *E) {
		e.Literal(w75lit10, "", "buf_write bracketing the write with an autocommand buffer swap")
	})
	e.InFunction("buf_write", func(e *E) { e.Lines(`aco_save_T[ \t]+aco;`, 1, "its saved window") })
	e.InFunction("buf_write", func(e *E) { e.Lines(`bufref_T[ \t]+bufref;`, 1, "its buffer reference") })
	e.InFunction("buf_write", func(e *E) {
		e.Literal(w75lit11, w75lit12, "the write asking whether an autocommand had taken over")
	})
	e.FoldNeverIn2("buf_write", `(?m)^[ \t]*if \(did_cmd\)$`, "and the arm only an autocommand-driven write could reach", 1)
	e.InFunction("buf_write", func(e *E) {
		e.Lines(`int[ \t]+did_cmd = FALSE;`, 1, "and the flag no autocommand can set")
	})
	e.dropBareBlock("set_termname", "buf = curbuf;", "the husk the terminal notification left behind")
	return e.Done()
}

func init() { register("whim75", Whim75) }
