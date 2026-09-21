package check

import (
	"fmt"
	"io"
	"path/filepath"
	"strings"

	"slimvim.local/tools/internal/harness"
)

func init() {
	register("whim59", Whim59)
	register("whim60", Whim60)
	register("whim61", Whim61)
	register("whim62", Whim62)
	register("whim63", Whim63)
	register("whim64", Whim64)
	register("whim65", Whim65)
}

// grepNum is "$(grep -n PAT f)", as a refusal prints it.
func grepNum(p, pat string, m gmode) string {
	nums, ls := grepLines(readFile(p), pat, m)
	var o []string
	for i := range nums {
		o = append(o, fmt.Sprintf("%d:%s", nums[i], ls[i]))
	}
	return strings.Join(o, "\n")
}

func Whim59(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim59", args)
	if err != nil {
		return err
	}
	if callers := grepC(s.src(), `\bExpandOne\(`, gERE); callers != 3 {
		s.echo("  nocompletion ExpandOne is named %d times, expected 3 (prototype, definition, expand_filename)", callers)
		nums, ls := grepLines(s.src(), `\bExpandOne\(`, gERE)
		for i := range nums {
			s.echo("%s", cutC(fmt.Sprintf("%d:%s", nums[i], ls[i]), 120))
		}
		return harness.ErrReported
	}
	if !s.goneW("  nocompletion ", `\b%s\b`, gERE, gERE, true, nil, "p_wc", "p_wcm", "p_wim", "p_wop", "p_wig", "p_wic", "wim_flags", "nextwild", "showmatches", "cmdline_wildchar_complete", "set_expand_context",
		"set_one_cmd_context", "ExpandSettings", "ExpandMappings", "ExpandBufnames", "expand_argopt", "get_next_or_prev_match",
		"find_longest_match", "did_wild_list", "check_opt_wim") {
		return harness.ErrReported
	}
	s.echo("  nocompletion no completion key, context, match list or wild* option is left")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	if !s.unknownOpts(d, "  nocompletion ", "wildchar", "wildcharm", "wildmode", "wildoptions", "wildignore", "wildignorecase") {
		return harness.ErrReported
	}
	o := filepath.Join(d, "onlyone.txt")
	put(o, "x\n")
	inD(d, "-e", "-s", "+e onlyone.txt", "+1s/x/y/", "+w", "+q!")
	if catS(o) != "y" {
		s.echo("  nocompletion :e onlyone.txt did not edit it: '%s'", catS(o))
		return harness.ErrReported
	}
	s.echo("  nocompletion :set sw works; the wild* options are unknown; :e still edits a named file")
	return nil
}

func Whim60(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim60", args)
	if err != nil {
		return err
	}
	if !s.goneW("  nosixopts    ", `\b%s\b`, gERE, gERE, true, nil, "p_su", "match_suffix", "p_fic", "p_acl", "delay_pending", "acl_elapsed", "p_vfile", "verbose_fd", "verbose_open", "verbose_stop", "verbose_enter", "verbose_leave",
		"p_debug", "p_fp", "b_p_fp", "p_ep", "b_p_ep", "get_equalprg", "did_set_verbosefile", "did_set_debug") {
		return harness.ErrReported
	}
	s.echo("  nosixopts    none of the seven options or their readers is left")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	if !s.unknownOpts(d, "  nosixopts    ", "suffixes", "fileignorecase", "autocompletedelay", "verbosefile", "debug", "formatprg", "equalprg") {
		return harness.ErrReported
	}
	g := filepath.Join(d, "g.txt")
	put(g, "aaa bbb\n")
	inD(d, "-e", "-s", "+set tw=4", "+1normal! gqq", "+wq", "g.txt")
	if bar(g) != "aaa|bbb|" {
		s.echo("  nosixopts    gqq with tw=4 left '%s'", bar(g))
		return harness.ErrReported
	}
	s.echo("  nosixopts    :set sw works; the seven are unknown; gq still formats internally")
	return nil
}

func Whim61(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim61", args)
	if err != nil {
		return err
	}
	if !s.goneW("  notitle      ", `\b%s\b`, gERE, gERE, true, nil, "p_title", "p_titlelen", "p_titleold", "p_titlestring", "p_icon", "p_iconstring", "maketitle", "resettitle", "mch_settitle", "mch_restore_title",
		"set_title_defaults", "need_maketitle", "lasttitle", "lasticon", "oldtitle", "oldicon", "term_settitle", "term_push_title", "term_pop_title") {
		return harness.ErrReported
	}
	s.echo("  notitle      nothing sets, restores, pushes or pops the terminal's title")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	if !s.unknownOpts(d, "  notitle      ", "title", "titlelen", "titleold", "titlestring", "icon", "iconstring") {
		return harness.ErrReported
	}
	s.echo("  notitle      :set sw works; the six title and icon options are unknown")
	return nil
}

func Whim62(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim62", args)
	if err != nil {
		return err
	}
	if !s.goneW("  nobufopts    ", `\b%s\b`, gERE, gERE, true, nil, "b_p_bl", "b_p_bt", "b_p_ft", "p_bl", "p_bt", "p_ft", "p_jop", "jop_flags", "p_ut", "p_aw", "p_awa", "autowrite", "autowrite_all", "bt_dontwrite", "bt_dontwrite_msg",
		"bt_nofilename", "bt_nofileread", "bt_prompt", "set_buflisted", "did_set_buftype", "did_set_buflisted", "did_set_filetype_or_syntax",
		"do_filetype_autocmd", "b_did_filetype", "b_au_did_filetype", "CCGD_AW", "nofile_err",
		"before_blocking", "trigger_cursorhold", "updatescript", "ml_sync_all", "scriptout", "did_start_blocking") {
		return harness.ErrReported
	}
	s.echo("  nobufopts    none of the seven options, the bt_ helpers or the autowrite path is left")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	if !s.unknownOpts(d, "  nobufopts    ", "buflisted", "buftype", "filetype", "jumpoptions", "updatetime", "autowrite", "autowriteall") {
		return harness.ErrReported
	}
	f := filepath.Join(d, "w.txt")
	put(f, "x\n")
	inD(d, "-e", "-s", "+1s/x/y/", "+w", "+q!", "w.txt")
	if catS(f) != "y" {
		s.echo("  nobufopts    :w did not write: '%s'", catS(f))
		return harness.ErrReported
	}
	s.echo("  nobufopts    :set sw works; the seven are unknown; :w still writes")
	return nil
}

func Whim63(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim63", args)
	if err != nil {
		return err
	}
	if !s.goneW("  nojumplist   ", `\b%s\b`, gERE, gERE, true, nil, "w_jumplist", "w_jumplistlen", "w_jumplistidx", "movemark", "cleanup_jumplist", "copy_jumplist", "free_jumplist", "ex_jumps", "ex_clearjumps") {
		return harness.ErrReported
	}
	if !grepQ(s.src(), "w_pcmark", gBRE) {
		s.echo("  nojumplist   w_pcmark went too -- the '' mark was not the jump list's")
		return harness.ErrReported
	}
	if !grepQ(s.src(), "movechangelist", gBRE) {
		s.echo("  nojumplist   movechangelist went too -- g; and g, were not the jump list's")
		return harness.ErrReported
	}
	s.echo("  nojumplist   no jump list is left; the '' mark and the change list are")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	if inD(d, "-e", "-s", "+jumps", "+q!") == 0 {
		s.echo("  nojumplist   :jumps was accepted")
		return harness.ErrReported
	}
	j := filepath.Join(d, "j.txt")
	put(j, "a\nb\nc\n")
	inD(d, "-e", "-s", "+1", "+normal! 3G", "+normal! \017", "+s/^/X/", "+wq", "j.txt")
	if bar(j) != "a|b|Xc|" {
		s.echo("  nojumplist   CTRL-O moved the cursor: '%s'", bar(j))
		return harness.ErrReported
	}
	k := filepath.Join(d, "k.txt")
	put(k, "a\nb\nc\n")
	inD(d, "-e", "-s", "+1", "+normal! 3G''", "+s/^/Y/", "+wq", "k.txt")
	if bar(k) != "Ya|b|c|" {
		s.echo("  nojumplist   '' did not return to line 1: '%s'", bar(k))
		return harness.ErrReported
	}
	s.echo("  nojumplist   :jumps is refused; CTRL-O stays put; '' still jumps back")
	return nil
}

func Whim64(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim64", args)
	if err != nil {
		return err
	}
	if !s.goneW("  noformatopts ", `\b%s\b`, gERE, gERE, true, nil, "p_fo", "p_flp", "p_com", "p_para", "p_sections", "b_p_fo", "b_p_flp", "b_p_com", "has_format_option", "get_leader_len", "get_last_leader_offset",
		"auto_format", "check_auto_format", "did_add_space", "paragraph_start", "same_leader", "skip_comment", "get_number_indent", "ends_in_white",
		"inmacro", "buf_has_cstyle_comments", "end_comment_pending", "Insstart_textlen", "Insstart_blank_vcol", "did_set_formatoptions",
		"did_set_comments", "OPENLINE_DO_COM", "OPENLINE_COM_LIST", "OPENLINE_FORMAT", "OPENLINE_KEEPTRAIL", "INSCHAR_DO_COM", "INSCHAR_COM_LIST",
		"COM_MAX_LEN", "FO_WRAP", "FO_AUTO",
		"op_format", "format_lines", "fmt_check_par", "nv_gd", "find_decl", "OP_FORMAT", "OP_FORMAT2", "INSCHAR_FORMAT", "INSCHAR_NO_FEX", "cursor_start",
		"op_reindent", "bangredo", "OP_INDENT", "OP_FILTER", "CPO_FILTER",
		"cindent_on", "can_cindent", "set_can_cindent") {
		return harness.ErrReported
	}
	if !s.keptE("  noformatopts ", " went too -- it was not the formatter's", "internal_format", "comp_textwidth", "startPS", "findpar", "check_linecomment", "op_shift", "op_colon", "do_bang", "do_filter",
		"may_do_si", "did_si", "can_si", "can_si_back") {
		return harness.ErrReported
	}
	s.echo("  noformatopts no leader, format flag, nroff macro, formatter or declaration search is left; the wrap is")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	if !s.unknownOpts(d, "  noformatopts ", "formatoptions", "formatlistpat", "comments", "paragraphs", "sections") {
		return harness.ErrReported
	}
	wt := filepath.Join(d, "w.txt")
	put(wt, "")
	inD(d, "-e", "-s", "+set tw=10", "+normal! Aaaa bbb ccc ddd", "+wq", "w.txt")
	if bar(wt) != "aaa bbb|ccc ddd|" {
		s.echo("  noformatopts typing did not wrap at 'textwidth': '%s'", bar(wt))
		return harness.ErrReported
	}
	g := filepath.Join(d, "g.txt")
	put(g, "one two three four five six seven eight nine ten\nshort\n")
	inD(d, "-e", "-s", "+1", "+set tw=10", "+normal! gqq", "+wq", "g.txt")
	if bar(g) != "one two three four five six seven eight nine ten|short|" {
		s.echo("  noformatopts gqq still formatted: '%s'", bar(g))
		return harness.ErrReported
	}
	inD(d, "-e", "-s", "+1", "+set tw=10", "+normal! gqj", "+wq", "g.txt")
	if bar(g) != "one two three four five six seven eight nine ten|short|" {
		s.echo("  noformatopts gq with a motion still formatted: '%s'", bar(g))
		return harness.ErrReported
	}
	gd := filepath.Join(d, "gd.txt")
	put(gd, "int x;\n\nvoid f(void)\n{\n    int x;\n    x = x + 1;\n}\n")
	inD(d, "-e", "-s", "+6", "+normal! 0fxgd", "+s/^/HERE /", "+wq", "gd.txt")
	if !grepQ(readFile(gd), `^HERE     x = x + 1;$`, gBRE) {
		s.echo("  noformatopts gd moved the cursor: %s", grepNum(gd, "HERE", gBRE))
		return harness.ErrReported
	}
	op := filepath.Join(d, "op.txt")
	for _, k := range []string{"=", "!"} {
		put(op, "a\nb\nc\n")
		inD(d, "-e", "-s", "+1", "+normal! "+k+"jix", "+wq", "op.txt")
		if bar(op) != "a|b|c|" {
			s.echo("  noformatopts %s still ran as an operator: '%s'", k, bar(op))
			return harness.ErrReported
		}
	}
	put(op, "a\nb\nc\n")
	inD(d, "-e", "-s", "+1", "+normal! ix", "+wq", "op.txt")
	if bar(op) != "xa|b|c|" {
		s.echo("  noformatopts the control insert failed: '%s'", bar(op))
		return harness.ErrReported
	}
	si := filepath.Join(d, "si.txt")
	put(si, "if (x) {\n")
	inD(d, "-e", "-s", "+set si sw=4", "+normal! GA\ry;", "+normal! o}", "+wq", "si.txt")
	if strings.ReplaceAll(catA(si), "\n", "|") != "if (x) {$|    y;$|}$|" {
		s.echo("  noformatopts smartindent stopped indenting: '%s'", bar(si))
		return harness.ErrReported
	}
	p := filepath.Join(d, "p.txt")
	put(p, "a\n.PP\nb\n")
	inD(d, "-e", "-s", "+1", "+normal! }", "+s/^/X/", "+wq", "p.txt")
	if bar(p) != "a|.PP|Xb|" {
		s.echo("  noformatopts } stopped somewhere other than the last line: '%s'", bar(p))
		return harness.ErrReported
	}
	s.echo("  noformatopts the five are unknown; typing wraps at 'textwidth'; gqq, gqj, gd, = and ! do nothing; } passes .PP")
	return nil
}

func Whim65(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim65", args)
	if err != nil {
		return err
	}
	if !s.goneW("  norot13      ", `\b%s\b`, gERE, gERE, true, nil, "OP_ROT13", "op_function", "OP_FUNCTION", "ins_ctrl_x", "e_eval_feature_not_available") {
		return harness.ErrReported
	}
	if !s.keptE("  norot13      ", " went too -- it was not rot13's", "swapchar", "op_tilde", "OP_TILDE", "OP_UPPER", "OP_LOWER", "nv_search", "get_op_type") {
		return harness.ErrReported
	}
	if !grepQ(s.src(), `^[ \t]*case Ctrl_P:`, gERE) {
		s.echo("  norot13      Insert-mode CTRL-P lost its case and would insert a control character")
		return harness.ErrReported
	}
	if !grepQ(s.src(), `\bcase 'y':`, gERE) {
		s.echo("  norot13      zy went with the operators")
		return harness.ErrReported
	}
	s.echo("  norot13      no rot13, operator function or empty key handler is left")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	t := filepath.Join(d, "t.txt")
	for _, p := range [][2]string{{"g?g?", "abc def|ghi|"}, {"g??", "abc def|ghi|"}, {"g@g@", "abc def|ghi|"},
		{"gUU", "ABC DEF|ghi|"}, {"guu", "abc def|ghi|"}, {"g~~", "ABC DEF|ghi|"}, {"zyy", "abc def|ghi|"}} {
		put(t, "abc def\nghi\n")
		inD(d, "-e", "-s", "+1", "+normal! "+p[0], "+wq", "t.txt")
		if got := bar(t); got != p[1] {
			s.echo("  norot13      %s gave '%s', expected '%s'", p[0], got, p[1])
			return harness.ErrReported
		}
	}
	s.echo("  norot13      g? and g@ do nothing; gU, gu and g~ still change case; zy still yanks")
	return nil
}
