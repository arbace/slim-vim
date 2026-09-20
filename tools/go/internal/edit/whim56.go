package edit

import (
	"fmt"
	"io"
)

// exNiCompletions are commands whose handler is ex_ni -- present in the table,
// answering "not implemented" -- so completing their arguments is work for an
// answer nobody gets.
var exNiCompletions = []string{"colorscheme", "compiler", "ownsyntax", "setfiletype", "packadd"}

// runtimeContexts are the EXPAND_ contexts that named a file under
// 'runtimepath'.  There is no runtime directory in this build.
var runtimeContexts = []string{"COLORS", "COMPILER", "OWNSYNTAX", "FILETYPE", "PACKADD", "RUNTIME"}

// Whim56 takes 'shellredir' choosing itself by the shell's name, the shell
// quoting, and every completion that read the runtime directory.
func Whim56(text []byte, w io.Writer) ([]byte, error) {
	e := New("noshellrtp", text, w)

	// 'shellredir''s default was chosen by the name of 'shell'.
	e.InFunction("set_init_3", func(e *E) {
		e.Cut(`(?m)^[ \t]*idx_srr = findoption\(\(char_u \*\)"srr"\);\n`, 1,
			"set_init_3 looking up 'shellredir'")
		e.FoldNever(`(?m)^[ \t]*if \(idx_srr < 0\)$`,
			"set_init_3 without a 'shellredir' row")
		e.Cut(`(?m)^[ \t]*do_srr = !\(options\[idx_srr\]\.flags & P_WAS_SET\);\n`, 1,
			"set_init_3 asking whether 'shellredir' was set")
		e.Cut(`(?m)^[ \t]*p = get_isolated_shell_name\(\);\n`, 1,
			"set_init_3 naming the shell")
		e.DropIf(`(?m)^[ \t]*if \(p != NULL\)$`,
			"set_init_3 choosing 'shellredir' by shell")
	})
	e.InFunction("do_bang", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(\*p_shq != NUL\)$`,
			"do_bang wrapping the command in 'shellquote'")
	})
	e.InFunction("vim_strsave_fnameescape", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(what == VSE_SHELL && csh_like_shell\(\) && p != NULL\)$`,
			"filename escaping doubling ! for csh")
	})

	// Completion for commands that are ex_ni, and for :set ft=.
	e.InFunction("set_context_by_cmdname", func(e *E) {
		for _, c := range exNiCompletions {
			e.Cut(fmt.Sprintf(`(?m)^[ \t]*case CMD_%s:\n[ \t]*xp->xp_context = EXPAND_\w+;\n[ \t]*xp->xp_pattern = arg;\n[ \t]*break;\n\n?`, c),
				1, fmt.Sprintf("completing :%s, which is ex_ni", c))
		}
		e.Cut(`(?m)^[ \t]*case CMD_runtime:\n[ \t]*set_context_in_runtime_cmd\(xp, arg\);\n[ \t]*break;\n\n?`,
			1, "completing :runtime, which is ex_ni")
	})
	e.InFunction("ExpandFromContext", func(e *E) {
		for _, c := range runtimeContexts {
			e.FoldNever(fmt.Sprintf(`(?m)^[ \t]*if \(xp->xp_context == EXPAND_%s\)$`, c),
				fmt.Sprintf("expanding runtime names for EXPAND_%s", c))
		}
	})
	e.InFunction("set_context_in_set_cmd", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(options\[opt_idx\]\.var == \(char_u \*\)&p_ft\)$`,
			":set ft= completing runtime file types")
		e.FoldNever(`(?m)^[ \t]*if \(p == \(char_u \*\)&p_pp \|\| p == \(char_u \*\)&p_rtp\)$`,
			"'packpath' and 'runtimepath' completing as directories")
	})
	e.InFunction("stropt_get_newval", func(e *E) {
		e.FoldNever(`(?m)^[ \t]*if \(varp == \(char_u \*\)&p_kp && \(\*arg == NUL \|\| \*arg == ' '\)\)$`,
			":set kp= defaulting to :help")
	})

	return e.Done()
}

// Whim56KP takes get_varp()'s per-buffer resolution of 'keywordprg'.
//
// IT IS A SECOND ENTRY AND NOT PART OF Whim56, because in the phase program it
// stands AFTER two dropoptions calls rather than before them.  Folding the two
// heredocs into one call would have moved this cut earlier, which is a change
// to the phase and not to its spelling -- the kind a port must not make and the
// boundary would have caught.
func Whim56KP(text []byte, w io.Writer) ([]byte, error) {
	e := New("noshellrtp", text, w)
	e.Cut(`(?m)^[ \t]*case[^\n]*\bBV_KP\b[^\n]*\n[ \t]*return \*curbuf->b_p_kp != NUL\n[ \t]*\? \(char_u \*\)&curbuf->b_p_kp : p->var;\n`,
		1, "get_varp no longer resolves 'keywordprg' per buffer")
	return e.Done()
}

func init() {
	register("whim56", Whim56)
	register("whim56kp", Whim56KP)
}
