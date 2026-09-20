package edit

import (
	"io"
	"regexp"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

func init() { register("zero13", Zero13) }

var z13Before = map[string]int{
	"scriptin": 8, "curscript": 11, "NSCRIPT": 3, "saved_typebuf": 2,
	"closescript": 3, "using_script": 3, "script_char": 6, "retesc": 3,
	"redir_fd": 6, "redir_off": 7, "redir_write": 7, "redirecting": 4,
	"did_return": 3,
	"vim_fsync":  3, "ui_write": 3, "mch_write": 2, "FILE": 2,
	"may_sync_undo": 3, "is_safe_now": 3, "free_typebuf": 5,
	"read_cmd_fd": 12,
}

var z13After = map[string]int{
	"redirecting": 2, "closescript": 2, "vim_fsync": 2, "using_script": 1,
	"redir_write": 0, "redir_off": 0, "did_return": 0, "retesc": 0, "script_char": 0,
	"scriptin": 4, "curscript": 7,
	"may_sync_undo": 3, "is_safe_now": 3,
	"ui_write": 3, "mch_write": 2, "read_cmd_fd": 12,
}

var (
	z13ScriptWrite = regexp.MustCompile(`\bscriptin\s*\[[^\]]*\]\s*=[^=][^;\n]*;`)
	z13RedirWrite  = regexp.MustCompile(`(?m)^[ \t]*(?:static\s+FILE\s*\*\s*)?redir_fd\s*=[^=][^;]*;$`)
	z13UiCall      = regexp.MustCompile(`(?m)^[ \t]*ui_write\([^;\n]*\);$`)
	z13RedirOff    = regexp.MustCompile(`(?m)^[ \t]*redir_off = (?:TRUE|FALSE);\n`)
)

// Zero13 removes the two `static FILE *` that nothing has ever opened in any
// build of zero-vim, ui_write()'s console parameter, and the five functions the
// sweep finds under them.
//
// ITS ARGUMENT IS TEXTUAL AND THE INVARIANT IS COMPUTED: scriptin[] is assigned
// ONCE in the whole file, to NULL, inside the function this phase removes, and
// redir_fd only by its own declaration -- so the phase removes the POSSIBILITY
// and not a behaviour.
func Zero13(text []byte, w io.Writer) ([]byte, error) {
	p := ph{"nofile", w}
	var err error

	mentions := func(t []byte, name string) int {
		return len(regexp.MustCompile(`\b`+name+`\b`).FindAll(t, -1))
	}
	textEdit := func(t []byte, old, new, what string, n int) ([]byte, error) {
		k := strings.Count(string(t), old)
		if k != n {
			return nil, p.die("%s -- the text occurs %d times, expected %d: %s",
				what, k, n, cutil.PyRepr(zHead(old, 70)))
		}
		p.say(what)
		return []byte(strings.ReplaceAll(string(t), old, new)), nil
	}
	fold := func(t []byte, fn, how, pattern, what string, n int) ([]byte, error) {
		a, z, ok := cutil.FindDefinition(t, cutil.Blank(t), fn)
		if !ok {
			return nil, p.die("%s is not defined", fn)
		}
		f := cutil.FoldNever
		switch how {
		case "always":
			f = cutil.FoldAlways
		case "drop":
			f = cutil.DropIf
		}
		body, err := f(t[a:z], pattern, n)
		if err != nil {
			return nil, p.die("%s -- %v", what, err)
		}
		p.say(what)
		return []byte(string(t[:a]) + string(body) + string(t[z:])), nil
	}
	joined := func(ms []string, n int) string {
		out := make([]string, len(ms))
		for i, m := range ms {
			out[i] = zHead(strings.TrimSpace(m), n)
		}
		return strings.Join(out, " | ")
	}

	// ---- 0. the shape every anchor below was counted against ------------------
	for _, name := range sortedKeys2(z13Before) {
		if k := mentions(text, name); k != z13Before[name] {
			return nil, p.die("%s has %d mentions, expected %d -- the anchors below were counted "+
				"against a different file", name, k, z13Before[name])
		}
	}
	p.say("scriptin 8, redir_fd 6, redirecting 4, ui_write 3, FILE 2 -- the file the six " +
		"anchors were counted against")

	// ---- THE INVARIANT, COMPUTED BEFORE ANYTHING IS FOLDED --------------------
	sw := z13ScriptWrite.FindAllString(string(text), -1)
	if len(sw) != 1 || sw[0] != "scriptin[curscript] = NULL;" {
		out := make([]string, len(sw))
		for i, m := range sw {
			out[i] = zHead(m, 60)
		}
		return nil, p.die("scriptin[] is assigned %d times and not once to NULL alone: %s",
			len(sw), strings.Join(out, " | "))
	}
	rw := z13RedirWrite.FindAllString(string(text), -1)
	if len(rw) != 1 || rw[0] != "static FILE *redir_fd  = NULL ;" {
		return nil, p.die("redir_fd is assigned %d times and not once by its declaration alone: %s",
			len(rw), joined(rw, 60))
	}
	calls := z13UiCall.FindAllString(string(text), -1)
	if len(calls) != 1 || calls[0] != "    ui_write(out_buf, len, FALSE);" {
		return nil, p.die("ui_write has %d call sites and not the one that passes FALSE: %s",
			len(calls), joined(calls, 60))
	}
	p.say("scriptin[] is assigned ONCE in the whole file, to NULL, inside closescript(); " +
		"redir_fd only by its own declaration; ui_write() has ONE call and it passes " +
		"FALSE.  That, and nothing weaker, is why every fold below may take a constant -- " +
		"and it is also the whole claim of the phase: neither FILE* has ever been opened " +
		"in any build of zero-vim")

	// ---- A. scriptin[] is NULL for ever ---------------------------------------
	for _, e := range []struct {
		old, new, what string
		n              int
	}{
		{z13lit1, z13lit2, "may_sync_undo: `scriptin[curscript] == NULL` is TRUE, so the conjunct " +
			"goes -- the function SURVIVES and u_sync() still runs on the rest", 1},
		{z13lit3, "", "is_safe_now: the same conjunct, and the same survival -- " +
			"stuff_empty() && typebuf.tb_len == 0 && !global_busy is what is left", 1},
		{" && !using_script()", "", "nv_visual: `!using_script()` is TRUE, so the conjunct goes", 1},
		{" || using_script()", "", "skip_showmode: `using_script()` is FALSE, so the disjunct goes -- and " +
			"that was its last caller", 1},
		{z13lit4, "", "inchar()'s script reader: the loop needs `scriptin[curscript] != NULL`, " +
			"which is FALSE, so it never ran -- and it was closescript()'s only " +
			"caller and getc()'s", 1},
	} {
		if text, err = textEdit(text, e.old, e.new, e.what, e.n); err != nil {
			return nil, err
		}
	}
	// `retesc` IS READ AND NEVER WRITTEN AFTER A4, which draws no warning and
	// which deadsweep.py does not act on.
	if k := mentions(text, "retesc"); k != 2 {
		return nil, p.die("retesc has %d mentions after the loop went, expected 2 -- its declaration "+
			"and its one read", k)
	}
	for _, e := range []struct{ old, new, what string }{
		{z13lit5, z13lit6, "inchar: `retesc` is read and never written now -- no warning covers " +
			"that, and the value it would return is uninitialised, so the read " +
			"becomes the FALSE it was initialised to"},
		{z13lit7, "", "and its declaration goes with it"},
		{z13lit8, "", "and the script_char local itself, which nothing writes now"},
	} {
		if text, err = textEdit(text, e.old, e.new, e.what, 1); err != nil {
			return nil, err
		}
	}
	// IT IS FOLDED LAST, after the two locals above: fold_always dedents the body
	// it keeps, and `return retesc;` sits inside it -- a rewrite counted against
	// the original indentation would refuse afterwards.
	if text, err = fold(text, "inchar", "always", `(?m)^    if \(script_char < 0\)$`,
		"inchar: `script_char < 0` is TRUE for ever now, so the whole rest of the "+
			"function is what runs -- the body is dedented one level", 1); err != nil {
		return nil, err
	}

	// ---- B. redir_fd is NULL for ever -----------------------------------------
	// THE TWO PATTERNS DIFFER ONLY IN INDENTATION, and that is deliberate: a
	// single pattern with a count of two would fold two different shapes with one
	// rule.
	if text, err = fold(text, "undo_cmdmod", "never", `(?m)^        if \(redirecting\(\)\)$`,
		"undo_cmdmod: `redirecting()` is FALSE, so unwinding :silent never resets "+
			"msg_col for a redirection that is not happening", 1); err != nil {
		return nil, err
	}
	if text, err = fold(text, "redir_write", "never", `(?m)^    if \(redirecting\(\)\)$`,
		"redir_write: the same constant takes the whole body -- the fputs() and "+
			"putc() block, which is putc's only caller and fputs's only NAMED one", 1); err != nil {
		return nil, err
	}
	if k := mentions(text, "redirecting"); k != 2 {
		return nil, p.die("redirecting has %d mentions after both callers were folded, expected 2 -- "+
			"its prototype and its definition, for the sweep", k)
	}

	// ---- the recommended extra: the no-op that is left ------------------------
	out, err := cutil.DropIf(text, `(?m)^    if \(!did_return\)$`, 1)
	if err != nil {
		return nil, p.die("msg_end's `if (!did_return)` block -- %v", err)
	}
	text = out
	p.say("msg_end's `if (!did_return)` block, which held one of the five calls: dropping " +
		"the call alone would leave an `if` with an empty body, which is not something " +
		"any tool here removes")
	for _, e := range []struct {
		old, what string
		n         int
	}{
		{z13lit9, "emsg_core's two calls that echoed the error's source line", 2},
		{z13lit10, "emsg_core's call that echoed the message itself", 1},
		{z13lit11, "msg_puts_attr_len's call, which was every message the editor prints", 1},
		{z13lit12, "redir_write's prototype", 1},
	} {
		if text, err = textEdit(text, e.old, "", e.what, e.n); err != nil {
			return nil, err
		}
	}
	var removed bool
	if text, removed = cutil.DeleteDefinition(text, "redir_write"); !removed {
		return nil, p.die("redir_write has no definition to remove")
	}
	if k := mentions(text, "redir_write"); k != 0 {
		return nil, p.die("redir_write still has %d mentions", k)
	}
	p.say("redir_write itself, which could no longer do anything: five call sites and the " +
		"definition")

	// A local draws -Wunused-but-set-variable, which the sweep may act on; a
	// FILE-SCOPE static draws NOTHING AT ALL -- phase 10's `readonlymode` in this
	// phase's shape -- so both go here rather than being left to a tool.
	for _, e := range []struct{ old, what string }{
		{z13lit13, "msg_end's `did_return`, written once and read never now"},
		{z13lit14, "and its one write"},
	} {
		if text, err = textEdit(text, e.old, "", e.what, 1); err != nil {
			return nil, err
		}
	}
	if k := len(z13RedirOff.FindAll(text, -1)); k != 5 {
		return nil, p.die("redir_off has %d writes, expected 5 -- a phase written from a description "+
			"of four would leave one behind", k)
	}
	text = z13RedirOff.ReplaceAll(text, nil)
	if text, err = textEdit(text, z13lit15, "",
		"and redir_off: FIVE writes, not four, and no reader at all -- a "+
			"file-scope static that is assigned and never read draws no warning, "+
			"and tools/deadsweep.py acts on warnings", 1); err != nil {
		return nil, err
	}
	if mentions(text, "redir_off") > 0 || mentions(text, "did_return") > 0 {
		return nil, p.die("redir_off or did_return survives")
	}

	// ---- C. ui_write's console ------------------------------------------------
	for _, e := range []struct{ old, new, what string }{
		{z13lit16, z13lit17, "ui_write's prototype loses the console parameter"},
		{z13lit18, z13lit19, "and the definition: `console` is FALSE at the one call site, so the " +
			"vim_fsync(1) it guarded can never be entered, and ui_write is " +
			"mch_write now -- which is what takes vim_fsync() and fsync()"},
		{z13lit20, z13lit21, "and its one call site, which already passed FALSE"},
	} {
		if text, err = textEdit(text, e.old, e.new, e.what, 1); err != nil {
			return nil, err
		}
	}

	// ---- what the sweep is handed, as a count rather than as trust ------------
	for _, name := range sortedKeys2(z13After) {
		if k := mentions(text, name); k != z13After[name] {
			return nil, p.die("%s has %d mentions after the cut, expected %d", name, k, z13After[name])
		}
	}
	p.say("the cut is done: redirecting, closescript and vim_fsync at two mentions each " +
		"-- a prototype and a definition -- and using_script at ONE, its definition " +
		"alone, having never had a prototype; scriptin 4 and curscript 7, every one of " +
		"them inside a function the sweep now reads as unreachable; may_sync_undo and " +
		"is_safe_now SURVIVING at three; and read_cmd_fd 12, still the terminal's")
	return text, nil
}
