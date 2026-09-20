package edit

import (
	"fmt"
	"io"
	"regexp"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

func init() { register("zero4", Zero4) }

var z4Before = map[string]int{
	"exmode_active": 49, "silent_mode": 23, "pending_exmode_active": 4,
	"exmode_plus": 3, "exmode_was": 2, "do_exmode": 4, "getexmodeline": 6,
	"nv_exmode": 3, "EXMODE_NORMAL": 6, "EXMODE_VIM": 5, "BO_EX": 2,
	"ex_pressedreturn": 7, "ex_no_reprint": 11, "ex_exitval": 3,
	"previous_got_int": 4, "use_plus_cmd": 5, "s_vbuf": 4,
	"e_at_end_of_file": 2, "noexmode": 4, "check_tty": 2,
	"mch_input_isatty": 2,
}

// z4After: every use is gone and what remains of each name is its definition,
// each of them a kind tools/sweep.sh deletes.  Stated as a number per name, so a
// use that survived shows up HERE and not as a warning five minutes later.
var z4After = map[string]int{
	"exmode_active": 1, "silent_mode": 1, "pending_exmode_active": 1,
	"exmode_plus": 1, "exmode_was": 0, "do_exmode": 0, "getexmodeline": 1,
	"nv_exmode": 1, "EXMODE_NORMAL": 1, "EXMODE_VIM": 1, "BO_EX": 1,
	"ex_pressedreturn": 0, "ex_no_reprint": 0, "ex_exitval": 0,
	"previous_got_int": 0, "use_plus_cmd": 0, "s_vbuf": 1,
	"e_at_end_of_file": 1, "noexmode": 0, "check_tty": 0,
	"mch_input_isatty": 1,
}

var (
	z4Isatty   = regexp.MustCompile(`\bisatty\(`)
	z4BreakCon = regexp.MustCompile(`\b(break|continue)\b`)
)

// Zero4 removes Ex mode, silent mode and the `-e -E -s -v` options.
func Zero4(text []byte, w io.Writer) ([]byte, error) {
	p := ph{"noexmode", w}
	var err error

	mentions := func(t []byte, name string) int {
		return len(regexp.MustCompile(`\b`+name+`\b`).FindAll(t, -1))
	}
	// line is a whole line by its trimmed text; head is a line that STARTS with
	// this and runs on -- the 200-column conditions.
	line := func(body string) string { return `(?m)^[ \t]*` + regexp.QuoteMeta(body) + `$` }
	head := func(body string) string { return `(?m)^[ \t]*` + regexp.QuoteMeta(body) + `.*$` }

	inFunction := func(t []byte, name string, edit func([]byte) ([]byte, error)) ([]byte, error) {
		a, z, ok := cutil.FindDefinition(t, cutil.Blank(t), name)
		if !ok {
			return nil, p.die("%s is not defined", name)
		}
		body, err := edit(t[a:z])
		if err != nil {
			return nil, err
		}
		return []byte(string(t[:a]) + string(body) + string(t[z:])), nil
	}
	// guardedBody is the block an `if` guards, for the break/continue audit:
	// fold_always leaves the body where it was, so neither changes which loop it
	// binds to, but a body that carries one is a body whose condition was doing
	// more than choosing, and that is worth failing on rather than assuming.
	guardedBody := func(s []byte, at int) []byte {
		b := cutil.Blank(s)
		lp := strings.Index(string(s[at:]), "(") + at
		rp := cutil.Match(b, lp)
		o := rp + 1
		for o < len(s) && (s[o] == ' ' || s[o] == '\t' || s[o] == '\n') {
			o++
		}
		c := cutil.Match(b, o)
		if c < 0 {
			return nil
		}
		return s[o:c]
	}
	fold := func(t []byte, kind, fn, pattern, what string, n int) ([]byte, error) {
		out, err := inFunction(t, fn, func(s []byte) ([]byte, error) {
			if kind == "always" {
				for _, m := range regexp.MustCompile(pattern).FindAllIndex(s, -1) {
					if z4BreakCon.Match(guardedBody(s, m[0])) {
						return nil, p.die("%s -- the body kept by this fold carries a break or continue", what)
					}
				}
			}
			f := cutil.FoldNever
			if kind == "always" {
				f = cutil.FoldAlways
			}
			o, err := f(s, pattern, n)
			if err != nil {
				return nil, p.die("%s -- %v", what, err)
			}
			return o, nil
		})
		if err != nil {
			return nil, err
		}
		p.say(what)
		return out, nil
	}
	// within reports only when the caller gives it a `what`: a second or third
	// edit that finishes the one above it has nothing of its own to say.
	within := func(t []byte, fn, old, new, what string, n int) ([]byte, error) {
		out, err := inFunction(t, fn, func(s []byte) ([]byte, error) {
			k := strings.Count(string(s), old)
			if k != n {
				wh := what
				if wh == "" {
					wh = "in " + fn
				}
				return nil, p.die("%s -- %s occurs %d times in %s, expected %d",
					wh, cutil.PyRepr(old), k, fn, n)
			}
			return []byte(strings.ReplaceAll(string(s), old, new)), nil
		})
		if err != nil {
			return nil, err
		}
		if what != "" {
			p.say(what)
		}
		return out, nil
	}
	literal := func(t []byte, old, new, what string, n int) ([]byte, error) {
		k := strings.Count(string(t), old)
		if k != n {
			return nil, p.die("%s -- %s occurs %d times, expected %d", what, cutil.PyRepr(old), k, n)
		}
		p.say(what)
		return []byte(strings.ReplaceAll(string(t), old, new)), nil
	}
	dropDefinition := func(t []byte, name, what string) ([]byte, error) {
		out, ok := cutil.DeleteDefinition(t, name)
		if !ok {
			return nil, p.die("%s -- %s is not defined", what, name)
		}
		p.say(what)
		return out, nil
	}

	// ---- 0. the invariants the cut rests on -----------------------------------
	for _, name := range sortedKeys(z4Before) {
		if k := mentions(text, name); k != z4Before[name] {
			return nil, p.die("%s has %d mentions, expected %d -- the anchors below were counted "+
				"against a different file", name, k, z4Before[name])
		}
	}
	if k := len(z4Isatty.FindAll(text, -1)); k != 5 {
		return nil, p.die("isatty is called %d times, expected 5", k)
	}
	p.say("21 identifiers at their counted mentions: exmode_active 49, silent_mode 23, isatty 5 calls")

	// ---- 1. the two keys, and the three functions they reach ------------------
	// The row is REPOINTED, never deleted (CLAUDE.md, `nvidx`).
	if text, err = literal(text, z4lit3, z4lit4,
		"the 'Q' row points at nv_error, so Q beeps like any unused key", 1); err != nil {
		return nil, err
	}
	if text, err = literal(text, z4lit5, "", "gQ's arm of nv_g_cmd, which falls to default: clearopbeep", 1); err != nil {
		return nil, err
	}
	if text, err = dropDefinition(text, "nv_exmode", "nv_exmode"); err != nil {
		return nil, err
	}
	if text, err = dropDefinition(text, "do_exmode", "do_exmode, the Ex-mode loop"); err != nil {
		return nil, err
	}
	if text, err = literal(text,
		"(getline_equal(fgetline, cookie, getexmodeline) || getline_equal(fgetline, cookie, getexline))",
		"getline_equal(fgetline, cookie, getexline)",
		"do_cmdline stops asking whether it is reading Ex-mode lines", 1); err != nil {
		return nil, err
	}
	if text, err = dropDefinition(text, "getexmodeline", "getexmodeline, the Ex-mode line reader"); err != nil {
		return nil, err
	}

	// ---- 2. the four command-line options -------------------------------------
	// They go BEFORE the `case NUL` fold below, because until they do there are
	// two `if (exmode_active)` in command_line_scan and a counted fold refuses --
	// loudly, which is the point.
	for _, o := range []struct{ opt, body string }{
		{"e", z4lit6}, {"E", z4lit7}, {"s", z4lit8}, {"v", z4lit9},
	} {
		if text, err = literal(text,
			fmt.Sprintf("            case '%s':\n%s                break;\n\n", o.opt, o.body), "",
			fmt.Sprintf("-%s is an unknown option", o.opt), 1); err != nil {
			return nil, err
		}
	}

	// ---- 3. every reader of exmode_active, in file order ----------------------
	type act struct {
		kind, fn, pat, old, new, what string
		n                             int
	}
	for _, a := range []act{
		{kind: "never", fn: "do_ecmd", pat: line("if (exmode_active)"), n: 1,
			what: "do_ecmd no longer puts the cursor on the last line"},
		{kind: "never", fn: "ex_substitute", pat: line("if (exmode_active)"), n: 1,
			what: "ex_substitute keeps its 85-line interactive else"},
		{fn: "do_one_cmd", old: "if (sourcing || exmode_active)", new: "if (sourcing)", n: 1,
			what: "do_one_cmd asks only whether it is sourcing"},
		{kind: "never", fn: "ex_range_without_command",
			pat: line("if (exmode_active && eap->cmd != (char_u *)exmode_plus + 1)"), n: 1,
			what: "a bare range is no longer an implicit :print"},
		{kind: "never", fn: "parse_command_modifiers",
			pat: head("if (*eap->cmd == NUL && exmode_active && "), n: 1,
			what: "an empty Ex-mode line is no longer the + command"},
		{kind: "never", fn: "do_exedit",
			pat: line("if (exmode_active && (eap->cmdidx == CMD_visual || eap->cmdidx == CMD_view))"), n: 1,
			what: ":visual, :vi and :view lose the branch that left Ex mode"},
		{fn: "do_exedit", old: z4lit10, new: "\n", n: 1,
			what: "and exmode_was, which only that branch read"},
		{kind: "never", fn: "ex_read", pat: line("if (empty && exmode_active)"), n: 1,
			what: ":read stops deleting the empty line it read into"},
		{kind: "never", fn: "cmdline_erase_chars", pat: line("if (exmode_active)"), n: 1,
			what: "backspacing off the start of a command line leaves Normal mode again"},
		{kind: "never", fn: "getcmdline_int", pat: head("if (exmode_active && c != ESC && "), n: 1,
			what: "a trailing backslash no longer continues a command line"},
		{kind: "never", fn: "getcmdline_int",
			pat: line("if (exmode_active && (ex_normal_busy == 0 || typebuf.tb_len > 0))"), n: 1,
			what: "and ESC on a command line is an abort again"},
		{fn: "compute_cmdrow", old: "if (exmode_active || (msg_scrolled != 0 && !updating_screen))",
			new: "if (msg_scrolled != 0 && !updating_screen)", n: 1,
			what: "compute_cmdrow asks only about the scroll"},
		{kind: "never", fn: "readfile", pat: line("if (exmode_active)"), n: 1,
			what: "readfile leaves the cursor on the first line read"},
		{kind: "never", fn: "vgetorpeek", pat: line("if (pending_exmode_active)"), n: 1,
			what: "an interrupted nested main_loop has no Ex mode to return to"},
		{fn: "vgetorpeek", old: "if (typebuf.tb_len > 0 && advance && !exmode_active)",
			new: "if (typebuf.tb_len > 0 && advance)", n: 1,
			what: "and the partial command is shown whenever there is one"},
		{fn: "msg_strtrunc", old: " && !exmode_active && msg_silent == 0)", new: " && msg_silent == 0)", n: 1,
			what: "msg_strtrunc truncates as it does on a screen"},
		{fn: "msg_may_trunc", old: "(shortmess(SHM_TRUNC) && !exmode_active)", new: "shortmess(SHM_TRUNC)", n: 1,
			what: "and so does msg_may_trunc"},
		{kind: "always", fn: "wait_return", pat: line("if (!exmode_active)"), n: 2,
			what: "wait_return moves the command row, both times"},
		{kind: "never", fn: "wait_return", pat: line("else if (exmode_active)"), n: 1,
			what: "and no longer answers its own prompt with a space"},
		// THE POLARITY TRAP.  0 != EXMODE_NORMAL is TRUE, so this one folds
		// ALWAYS while both of its neighbours fold never.
		{kind: "always", fn: "msg_start", pat: line("if (exmode_active != EXMODE_NORMAL)"), n: 1,
			what: "msg_start keeps the cmdline_row it set after a newline (0 != 1 is TRUE)"},
		{fn: "msg_puts_display", old: "if (cmdline_row > 0 && !exmode_active)", new: "if (cmdline_row > 0)", n: 1,
			what: "msg_puts_display scrolls the command row"},
		{fn: "msg_puts_display", old: " && !msg_no_more && !exmode_active)", new: " && !msg_no_more)", n: 1,
			what: "and the more-prompt is offered whenever the screen is full"},
		{fn: "screen_puts_len", old: z4lit12, new: "\n", n: 1,
			what: "a character is redrawn when it changed, and not otherwise"},
		{fn: "set_shellsize_inner", old: " || State == MODE_CONFIRM || exmode_active)",
			new: " || State == MODE_CONFIRM)", n: 1,
			what: "a resize repeats the message only at a prompt"},
		{kind: "always", fn: "vim_main2", pat: line("if (!exmode_active)"), n: 1,
			what: "vim_main2 stops scrolling messages at startup"},
		{kind: "never", fn: "vim_main2", pat: line("if (exmode_active)"), n: 2,
			what: "and clears the screen, and leaves the cursor where the file put it"},
		{kind: "never", fn: "main_loop",
			pat: line("if (noexmode && global_busy && !exmode_active && previous_got_int)"), n: 1,
			what: "CTRL-C in a :global no longer drops into Ex mode"},
		// fold_never rewrote the `else if` that followed into an `if`, so this
		// one is written without the `else` it had a moment ago.
		{kind: "always", fn: "main_loop", pat: line("if (!global_busy || !exmode_active)"), n: 1,
			what: "and swallows the interrupt as it always did outside :global"},
		{kind: "always", fn: "main_loop", pat: line("if (!exmode_active)"), n: 1,
			what: "the main loop stops scrolling messages"},
		{fn: "main_loop", old: "if (skip_redraw || exmode_active)", new: "if (skip_redraw)", n: 1,
			what: "and redraws unless the last command asked it not to"},
		{kind: "never", fn: "main_loop", pat: line("if (exmode_active)"), n: 1,
			what: "and runs normal_cmd, which is now the only thing it can run"},
		{kind: "never", fn: "getout", pat: line("if (exmode_active)"), n: 1,
			what: "the exit status is the one getout was given"},
		{kind: "never", fn: "command_line_scan", pat: line("if (exmode_active)"), n: 1,
			what: "a bare `-` is stdin again, which the argv phase owns"},
	} {
		if a.kind != "" {
			text, err = fold(text, a.kind, a.fn, a.pat, a.what, a.n)
		} else {
			text, err = within(text, a.fn, a.old, a.new, a.what, a.n)
		}
		if err != nil {
			return nil, err
		}
	}
	// check_tty() IS DELETED HERE RATHER THAN FOLDED, and the reason is a gap in
	// the sweep worth naming: folding its one branch leaves a local that is
	// written and never read, which is -Wunused-but-set-variable, and
	// deadsweep.py acts only on -Wunused-variable and -Wunused-function.
	if text, err = dropDefinition(text, "check_tty", "check_tty, which has nothing left to ask"); err != nil {
		return nil, err
	}
	if text, err = within(text, "main", z4lit13, "\n", "and its call in main", 1); err != nil {
		return nil, err
	}
	// exe_commands MUST SURVIVE: it is what runs `+{command}`, and every harness
	// here drives the editor with one.  Only its last statement folds.
	if text, err = fold(text, "always", "exe_commands", line("if (!exmode_active)"),
		"exe_commands stops scrolling messages, and keeps running +cmd", 1); err != nil {
		return nil, err
	}

	// ---- 4. every reader of silent_mode, in file order ------------------------
	for _, a := range []act{
		{fn: "change_warning", old: "if (msg_silent == 0 && !silent_mode)", new: "if (msg_silent == 0)", n: 1,
			what: "the 'readonly' warning pauses whenever it is shown"},
		{fn: "print_line", old: z4lit14, new: "\n", n: 1, what: "print_line prints on the screen, once"},
		{fn: "print_line", old: z4lit15, new: "\n", n: 1},
		{kind: "never", fn: "print_line", pat: line("if (save_silent)"), n: 1,
			what: "and no longer flushes a line it never buffered"},
		{kind: "always", fn: "msg_puts_printf", pat: line("if (!(silent_mode && p_verbose == 0))"), n: 1,
			what: "msg_puts_printf writes what it is given"},
		{fn: "msg_puts_printf", old: "if (*p != NUL && !(silent_mode && p_verbose == 0))",
			new: "if (*p != NUL)", n: 1, what: "including the last piece"},
		{kind: "never", fn: "do_set", pat: line("if (silent_mode && did_show)"), n: 1,
			what: ":set prints its listing on the screen"},
		{fn: "showoneopt", old: z4lit14, new: "\n", n: 1, what: "and so does one option"},
		{fn: "showoneopt", old: z4lit15, new: "\n", n: 1},
		{fn: "showoneopt", old: z4lit16, new: "\n", n: 1},
		{kind: "never", fn: "exit_scroll", pat: line("if (silent_mode)"), n: 1,
			what: "exiting scrolls the screen as it does from Normal mode"},
		{fn: "typed_ahead", old: "return (!silent_mode && char_avail());", new: "return char_avail();", n: 1,
			what: "typed_ahead is char_avail() again -- slim's 'lazyredraw' fix had only one caller"},
		{kind: "never", fn: "set_termname", pat: line("if (silent_mode)"), n: 1,
			what: "a terminal is set up whenever one is named"},
		{kind: "always", fn: "ui_write", pat: line("if (!(silent_mode && p_verbose == 0))"), n: 1,
			what: "ui_write writes"},
		{kind: "never", fn: "read_error_exit", pat: line("if (silent_mode)"), n: 1,
			what: "a read error is reported before the exit, not instead of it"},
		// This is the whole of setvbuf, and the file's only mention of stdout.
		{kind: "never", fn: "main", pat: line("if (silent_mode)"), n: 1,
			what: "main stops buffering stdout: setvbuf and stdout leave the binary"},
		{fn: "main", old: "if (params.want_full_screen && !silent_mode)",
			new: "if (params.want_full_screen)", n: 1, what: "and sets up the terminal when it is asked to"},
	} {
		if a.kind != "" {
			text, err = fold(text, a.kind, a.fn, a.pat, a.what, a.n)
		} else {
			text, err = within(text, a.fn, a.old, a.new, a.what, a.n)
		}
		if err != nil {
			return nil, err
		}
	}

	// ---- 5. what nothing reads any more, and no warning names -----------------
	// A file-scope static that is written and never read draws no warning at all,
	// and a local one draws -Wunused-but-set-variable, which deadsweep.py does not
	// act on.  Six of them, and they are invisible to every tool here.
	if text, err = literal(text, z4lit17, "\n", "ex_pressedreturn", 1); err != nil {
		return nil, err
	}
	if text, err = within(text, "parse_command_modifiers", z4lit18, "\n", "and its one remaining write", 1); err != nil {
		return nil, err
	}
	if text, err = literal(text, z4lit19, "\n", "ex_no_reprint", 1); err != nil {
		return nil, err
	}
	if text, err = literal(text, z4lit20, "\n", "and its seven writes", 6); err != nil {
		return nil, err
	}
	if text, err = literal(text, z4lit21, "\n", "and the seventh", 1); err != nil {
		return nil, err
	}
	if text, err = literal(text, z4lit22, "\n", "ex_exitval", 1); err != nil {
		return nil, err
	}
	if text, err = within(text, "emsg_core", z4lit23, "\n", "and its one write", 1); err != nil {
		return nil, err
	}
	if text, err = within(text, "main_loop", z4lit24, "\n",
		"previous_got_int, which only the Ex-mode arm read", 1); err != nil {
		return nil, err
	}
	if text, err = within(text, "main_loop", z4lit25, "\n", "", 1); err != nil {
		return nil, err
	}
	if text, err = within(text, "main_loop", z4lit26, "", "", 1); err != nil {
		return nil, err
	}
	if text, err = fold(text, "never", "parse_command_modifiers", line("if (use_plus_cmd)"),
		"use_plus_cmd: the two arms of the :visual range rewrite", 2); err != nil {
		return nil, err
	}
	if text, err = fold(text, "never", "parse_command_modifiers", line("else if (use_plus_cmd)"),
		"and the + command it stood for", 1); err != nil {
		return nil, err
	}
	if text, err = within(text, "parse_command_modifiers", z4lit27, "\n", "and the flag itself", 1); err != nil {
		return nil, err
	}

	// ---- 6. main_loop's second parameter, and the label it jumped to ----------
	if text, err = literal(text, z4lit28, z4lit29, "main_loop's prototype", 1); err != nil {
		return nil, err
	}
	if text, err = literal(text, z4lit30, z4lit31, "its definition", 1); err != nil {
		return nil, err
	}
	if text, err = literal(text, z4lit32, z4lit33, "and its one caller", 1); err != nil {
		return nil, err
	}
	if text, err = within(text, "main_loop", z4lit34, z4lit35,
		"the theend: label, which nothing jumps to now", 1); err != nil {
		return nil, err
	}

	// ---- 7. what is left is exactly what the sweep can take -------------------
	for _, name := range sortedKeys(z4After) {
		k := mentions(text, name)
		if k != z4After[name] {
			why := "more went than was meant to"
			if k > z4After[name] {
				why = "a use survived"
			}
			return nil, p.die("%s has %d mentions after the cut, expected %d -- %s",
				name, k, z4After[name], why)
		}
	}
	// `E501: At end-of-file` is not checked here: it is the initialiser of
	// e_at_end_of_file, whose last reader was do_exmode, and the string leaves
	// with the variable in the sweep.  The check asks for it afterwards.
	if strings.Contains(string(text), "Entering Ex mode") {
		return nil, p.die("'Entering Ex mode' survives the edit")
	}
	p.say("every use of all 21 is gone; eleven lone definitions and mch_input_isatty " +
		"are what the sweep takes")
	return text, nil
}
