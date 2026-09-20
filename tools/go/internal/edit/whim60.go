package edit

import "io"

// Whim60 takes six options that share nothing but being unreachable: 'suffixes',
// 'fileignorecase', 'autocompletedelay', 'verbosefile', 'debug', and the pair
// 'formatprg'/'equalprg'.
func Whim60(text []byte, w io.Writer) ([]byte, error) {
	e := New("nosixopts", text, w)

	// 'suffixes'
	e.InFunction("ExpandOne_start", func(e *E) {
		e.Cut(`(?m)^[ \t]*for \(i = 0; i < 2; \+\+i\)\n[ \t]*\{\n[ \t]*if \(match_suffix\(xp->xp_files\[i\]\)\)\n[ \t]*\{\n[ \t]*\+\+non_suf_match;\n[ \t]*\}\n[ \t]*\}\n`,
			1, "a single match chosen by 'suffixes'")
	})
	e.InFunction("expand_wildcards", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(\*num_files > 1 && !got_int\)$`, "matches reordered by 'suffixes'")
	})

	// 'fileignorecase'
	e.LiteralN("regmatch.rm_ic = p_fic;", "regmatch.rm_ic = FALSE;", 2,
		"file patterns ignoring case by 'fileignorecase'")
	e.InFunction("fname_match", func(e *E) {
		e.Literal("rmp->rm_ic = p_fic || ignore_case;", "rmp->rm_ic = ignore_case;",
			"buffer names ignoring case by 'fileignorecase'")
	})
	e.InFunction("vim_fnamecmp", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(p_fic\)$`, "vim_fnamecmp ignoring case")
	})
	e.InFunction("vim_fnamencmp", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(p_fic\)$`, "vim_fnamencmp ignoring case")
	})

	// 'autocompletedelay'
	e.InFunction("inchar_loop", func(e *E) {
		e.Cut(`(?m)^[ \t]*bool delay_pending = [^;]*;\n[ \t]*long acl_elapsed = [^\n]*;\n\n?`, 1,
			"an autocomplete delay that is never pending")
		e.Literal(" && !delay_pending", "", "blocking without waiting on the delay")
		e.FoldNever(`(?m)^[ \t]*else if \(delay_pending\)$`, "waiting out the autocomplete delay")
		e.DropIf(`(?m)^[ \t]*if \(delay_pending && acl_elapsed >= p_acl && maxlen >= 3 && !typebuf_changed\(tb_change_cnt\)\)$`,
			"the autocomplete delay expiring")
	})

	// 'verbosefile'
	e.InFunction("redir_write", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(\*p_vfile != NUL && verbose_fd == NULL\)$`,
			"opening 'verbosefile' on first write")
		e.FoldNeverN(`(?m)^[ \t]*if \(verbose_fd != NULL\)$`, 2, "writing to 'verbosefile'")
	})
	e.InFunction("redirecting", func(e *E) {
		e.Sub(`return redir_fd != NULL \|\| \*p_vfile != NUL\s*;`, "return redir_fd != NULL;", 1,
			"redirecting to 'verbosefile'")
	})
	e.InFunction("verbose_enter", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(\*p_vfile != NUL\)$`, "verbose_enter silencing for 'verbosefile'")
	})
	e.InFunction("verbose_leave", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(\*p_vfile != NUL\)$`, "verbose_leave silencing for 'verbosefile'")
	})
	e.Sub(`(?m)^[ \t]*verbose_(?:enter|leave)\(\);\n`, "", 4,
		"calls to the emptied verbose_enter and verbose_leave")
	e.InFunction("verbose_enter_scroll", func(e *E) {
		e.FoldNever(`(?m)^[ \t]*if \(\*p_vfile != NUL\)$`, "verbose_enter_scroll silencing for 'verbosefile'")
	})
	e.InFunction("verbose_leave_scroll", func(e *E) {
		e.FoldNever(`(?m)^[ \t]*if \(\*p_vfile != NUL\)$`, "verbose_leave_scroll silencing for 'verbosefile'")
	})

	// 'debug'
	e.InFunction("emsg_not_now", func(e *E) {
		e.Literal("(emsg_off > 0 && vim_strchr(p_debug, 'm') == NULL && vim_strchr(p_debug, 't') == NULL)",
			"(emsg_off > 0)", "'debug' m and t showing suppressed errors")
	})
	e.InFunction("emsg_core", func(e *E) {
		e.Literal("if (!emsg_off || vim_strchr(p_debug, 't') != NULL)", "if (!emsg_off)",
			"'debug' t handling errors under emsg_off")
	})
	e.InFunction("vim_beep", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(vim_strchr\(p_debug, 'e'\) != NULL\)$`, "'debug' e showing Beep!")
	})

	// 'formatprg' and 'equalprg'
	e.InFunction("do_pending_operator", func(e *E) {
		e.Literal("if (oap->op_type == OP_INDENT && *get_equalprg() == NUL)", "if (oap->op_type == OP_INDENT)",
			"= through 'equalprg'")
		e.FoldNever(`(?m)^[ \t]*if \(\*p_fp != NUL \|\| \*curbuf->b_p_fp != NUL\)$`, "gq through 'formatprg'")
	})
	e.InFunction("op_colon", func(e *E) {
		e.FoldNever(`(?m)^[ \t]*if \(oap->op_type == OP_INDENT\)$`, "op_colon building an 'equalprg' filter")
		e.FoldNever(`(?m)^[ \t]*if \(oap->op_type == OP_FORMAT\)$`, "op_colon building a 'formatprg' filter")
	})
	return e.Done()
}

// Whim60EP takes get_varp()'s per-buffer resolution of 'equalprg'.  A second
// entry for whim56kp's reason: it stands after a dropoptions call in the phase
// program, and folding it in would move the cut.
//
// The report line is the heredoc's last statement and it prints AFTER the
// write, which is why a filtered read of the file missed it and the port was
// briefly silent.  editcmp caught it in both directions -- first that the
// message existed, then that removing it was wrong -- which is the whole reason
// the report is compared and not only the tree.
func Whim60EP(text []byte, w io.Writer) ([]byte, error) {
	e := New("nosixopts", text, w)
	e.Cut(`(?m)^[ \t]*case[^\n]*\bBV_EP\b[^\n]*\n[ \t]*return \*curbuf->b_p_ep != NUL\n[ \t]*\? \(char_u \*\)&curbuf->b_p_ep : p->var;\n`,
		1, "get_varp no longer resolves 'equalprg' per buffer")
	return e.Done()
}

func init() {
	register("whim60", Whim60)
	register("whim60ep", Whim60EP)
}
