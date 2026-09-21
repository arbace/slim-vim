package check

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"slimvim.local/tools/internal/harness"
)

func init() {
	register("whim25", Whim25)
	register("whim26", Whim26)
	register("whim27", Whim27)
	register("whim28", Whim28)
	register("whim29", Whim29)
	register("whim30", Whim30)
	register("whim31", Whim31)
	register("whim32", Whim32)
	register("whim34", Whim34)
	register("whim35", Whim35)
	register("whim36", Whim36)
	register("whim37", Whim37)
	register("whim38", Whim38)
	register("whim39", Whim39)
	register("whim40", Whim40)
	register("whim41", Whim41)
}

// goneTools is the commonest whole check: the names gone, the verdict, and the
// two tools.
func goneTools(name, prefix, wrap string, m gmode, verdict string, names ...string) Func {
	return func(w io.Writer, args []string) error {
		s, err := newWsh(w, name, args)
		if err != nil {
			return err
		}
		if !s.goneW(prefix, wrap, m, m, true, nil, names...) {
			return harness.ErrReported
		}
		s.echo("%s", verdict)
		if err := s.phasecheck(); err != nil {
			return err
		}
		return s.phasebuild()
	}
}

// kept is `grep -q "\b$g("` refusing when the name is gone.
func (s *wsh) keptCall(prefix, why string, names ...string) bool {
	for _, g := range names {
		if grepC(s.src(), `\b`+g+`(`, gBRE) == 0 {
			s.echo("%s%s%s", prefix, g, why)
			return false
		}
	}
	return true
}

// keptE is `grep -qE "\b$g\b" f || { echo ...; exit 1; }`.
func (s *wsh) keptE(prefix, why string, names ...string) bool {
	for _, g := range names {
		if !grepQ(s.src(), `\b`+g+`\b`, gERE) {
			s.echo("%s%s%s", prefix, g, why)
			return false
		}
	}
	return true
}

func Whim25(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim25", args)
	if err != nil {
		return err
	}
	if !s.gone("  backup       ", gBRE, gBRE, true, nil, `p_bk\b`, `p_wb\b`, `p_bkc\b`, `p_bdir\b`, `p_bex\b`, `p_bsk\b`, `p_pm\b`,
		"b_p_bkc", "vim_rename", "vim_copyfile", "set_file_time", "mch_get_acl",
		"vim_acl_T", "backup_copy", "dobackup") {
		return harness.ErrReported
	}
	s.echo("  backup       nothing is copied aside, renamed, or timestamped")
	if !s.gone("  owner        ", gBRE, gBRE, true, nil, "getuid", "getgid", "get_user_name", "ROOT_UID", "b0_uname") {
		return harness.ErrReported
	}
	s.echo("  owner        nothing asks who you are")
	if !s.keptCall("  permissions  ", " went too -- permissions are not ownership", "mch_setperm", "mch_fsetperm", "mch_getperm") {
		return harness.ErrReported
	}
	s.echo("  permissions  chmod and fchmod stay: a file still has a mode")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if !s.symsGone("utime", "readlink", "symlink", "rename") {
		return harness.ErrReported
	}
	s.echo("  symbols      utime, readlink, symlink and rename are gone from nm -u")
	if !s.symsGone("getuid", "getgid") {
		return harness.ErrReported
	}
	s.echo("  symbols      getuid and getgid are gone from nm -u")
	if err := s.phasebuild(); err != nil {
		return err
	}
	d := s.sub(".bktest")
	put(filepath.Join(d, "f.txt"), "one\n")
	vimRC(d, "", "../whim-vim", "-e", "-s", "-c", "%s/one/two/", "-c", "wq", "f.txt")
	bk := fmt.Sprintf("%s:%s", lsA(d), catS(filepath.Join(d, "f.txt")))
	os.RemoveAll(d)
	if bk != "f.txt :two" {
		s.echo("  overwrite    a write left '%s', expected 'f.txt :two'", bk)
		return harness.ErrReported
	}
	s.echo("  overwrite    overwriting a file leaves the file, and nothing beside it")
	d = s.sub(".rotest")
	put(filepath.Join(d, "f.txt"), "one\n")
	os.Chmod(filepath.Join(d, "f.txt"), 0o444)
	vimRC(d, "", "../whim-vim", "-e", "-s", "-c", "%s/one/two/", "-c", "wq!", "f.txt")
	ro := catS(filepath.Join(d, "f.txt"))
	os.Chmod(filepath.Join(d, "f.txt"), 0o644)
	os.RemoveAll(d)
	if ro != "two" {
		s.echo("  readonly     :w! over a read-only file gave '%s', expected 'two'", ro)
		return harness.ErrReported
	}
	s.echo("  readonly     :w! over a read-only file still writes it")
	return nil
}

func Whim26(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim26", args)
	if err != nil {
		return err
	}
	set := map[string]bool{}
	for _, x := range grepO(s.src(), `\bSIG[A-Z0-9]*\b`, gBRE) {
		set[x] = true
	}
	var ns []string
	for k := range set {
		ns = append(ns, k)
	}
	sort.Strings(ns)
	named := strings.Join(ns, " ") + " "
	if len(ns) == 0 {
		named = ""
	}
	if named != "SIGALRM SIGCONT SIGHUP SIGINT SIGPIPE SIGTERM SIGTSTP SIGWINCH " {
		s.echo("  signals      the file names: %s", named)
		s.echo("               expected the five kept, plus SIGCONT/SIGALRM/SIGPIPE,")
		s.echo("               which mch_suspend() sets around the stop")
		return harness.ErrReported
	}
	if !s.gone("  signals      ", gBRE, gBRE, false, nil, "sigaltstack", "may_core_dump", "catch_sigpwr", "catch_sigusr1", "got_sigusr1",
		"signal_stack", "sigstk") {
		return harness.ErrReported
	}
	s.echo("  signals      %d in the table; resize, interrupt,", grepC(s.src(), "{SIG", gBRE))
	s.echo("               suspend, and a terminal put back on the way out")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if !s.symsGone("sigaltstack", "sysconf") {
		return harness.ErrReported
	}
	s.echo("  symbols      sigaltstack and sysconf are gone from nm -u")
	if err := s.phasebuild(); err != nil {
		return err
	}
	if s.st("termrestore", filepath.Join(s.work, "whim-vim")) {
		s.echo("  terminal     SIGTERM still puts the terminal back")
		return nil
	}
	s.echo("  terminal     SIGTERM left the terminal raw -- the deathtrap is what")
	s.echo("               this phase kept SIGHUP and SIGTERM for")
	return harness.ErrReported
}

func Whim27(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim27", args)
	if err != nil {
		return err
	}
	if !s.gone("  equiclass    ", gBRE, gBRE, false, nil, "reg_equi_class", "get_equi_class") {
		return harness.ErrReported
	}
	if !s.keptCall("  equiclass    ", " went too -- [[:alpha:]] and [[.x.]] are different", "get_char_class", "get_coll_element") {
		return harness.ErrReported
	}
	s.echo("  equiclass    [[=a=]] is gone; [[:alpha:]] and [[.x.]] are not")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d := s.sub(".eqtest")
	put(filepath.Join(d, "f.txt"), "xax\nx\303\241x\nx=x\n")
	vimRC(d, "", "../whim-vim", "-e", "-s", "-c", "s/[[=a=]]/#/g", "-c", "wq", "f.txt")
	t := strings.ReplaceAll(readFile(filepath.Join(d, "f.txt")), "\n", " ")
	put(filepath.Join(d, "g.txt"), "a1b\n")
	vimRC(d, "", "../whim-vim", "-e", "-s", "-c", "s/[[:alpha:]]/#/g", "-c", "wq", "g.txt")
	alpha := strings.ReplaceAll(readFile(filepath.Join(d, "g.txt")), "\n", " ")
	os.RemoveAll(d)
	if strings.Contains(t, "x#x") {
		s.echo("  equiclass    [[=a=]] still matched an accented a")
		return harness.ErrReported
	}
	if alpha != "#1# " {
		s.echo("  equiclass    [[:alpha:]] gave '%s', expected '#1# '", alpha)
		return harness.ErrReported
	}
	s.echo("  equiclass    [[=a=]] is literal now, and [[:alpha:]] still classifies")
	return nil
}

func Whim28(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim28", args)
	if err != nil {
		return err
	}
	if !s.gone("  cindent      ", gBRE, gBRE, true, nil, "get_c_indent", "in_cinkeys", "do_c_expr_indent", "b_p_cin", "b_p_cino", "p_cinw") {
		return harness.ErrReported
	}
	if !s.keptCall("  cindent      ", " went too -- 'lisp' and 'autoindent' are not this", "get_lisp_indent", "get_indent") {
		return harness.ErrReported
	}
	s.echo("  cindent      no C syntax model; 'autoindent' and 'lisp' untouched")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d := s.sub(".citest")
	put(filepath.Join(d, "f.txt"), "    one\n")
	vimRC(d, "", "../whim-vim", "-e", "-s", "-c", "set autoindent", "-c", "normal Gotwo", "-c", "wq", "f.txt")
	ai := ""
	if l := sedN(filepath.Join(d, "f.txt"), 2); l != "" || len(lines(readFile(filepath.Join(d, "f.txt")))) >= 2 {
		put(filepath.Join(d, ".l2"), l+"\n")
		ai = strings.TrimSuffix(catA(filepath.Join(d, ".l2")), "\n")
	}
	os.RemoveAll(d)
	if ai != "    two$" {
		s.echo("  autoindent   a new line gave '%s', expected four spaces then two", ai)
		return harness.ErrReported
	}
	if s.probeSet("autoindent") != 0 {
		s.echo("  options      the control failed")
		return harness.ErrReported
	}
	if s.probeSet("cindent") == 0 {
		s.echo("  options      :set cindent was accepted")
		return harness.ErrReported
	}
	s.echo("  autoindent   still indents; :set cindent is refused")
	return nil
}

func Whim29(w io.Writer, args []string) error {
	return goneTools("whim29", "  ucmd         ", "%s", gBRE, "  ucmd         no user command table, and no dispatch into one",
		"do_ucmd", "uc_check_code", "uc_add_command", "b_ucmds", "ex_delcommand")(w, args)
}

func Whim30(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim30", args)
	if err != nil {
		return err
	}
	if !s.gone("  ident        ", gBRE, gBRE, true, nil, "nv_K_getcmd", "do_nv_ident", "g_tag_at_cursor") {
		return harness.ErrReported
	}
	for _, g := range []string{"{'*', nv_ident", "{'#', nv_ident", "{POUND, nv_ident", "{Ctrl_RSB, nv_error", "{'K', nv_error"} {
		if grepC(s.src(), g, gFix) == 0 {
			s.echo("  ident        %s went -- * and # are the half this phase keeps", g)
			return harness.ErrReported
		}
	}
	s.echo("  ident        no keywordprg and no tag jump; * # and POUND still dispatch")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	if s.st("starcheck", filepath.Join(s.work, "whim-vim")) {
		s.echo("  ident        * still finds the next whole word, and skips foobar")
		return nil
	}
	s.echo("  ident        * no longer searches -- it is the half this phase keeps")
	return harness.ErrReported
}

func Whim31(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim31", args)
	if err != nil {
		return err
	}
	if n := grepC(s.src(), "modify_fname", gBRE); n != 0 {
		s.echo("  fnamemod     modify_fname still has %d mentions after the sweep", n)
		return harness.ErrReported
	}
	if grepC(s.src(), `\beval_vars(`, gBRE) == 0 {
		s.echo("  fnamemod     eval_vars went too -- %% and # are the half this keeps")
		return harness.ErrReported
	}
	s.echo("  fnamemod     no suffix language; %% and # still expand")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d := s.sub(".fmtest")
	os.MkdirAll(filepath.Join(d, "sub"), 0o755)
	put(filepath.Join(d, "sub", "f.txt"), "one\n")
	vimRC(d, "", "../whim-vim", "-e", "-s", "-c", "w! copy.txt", "-c", "qa!", "sub/f.txt")
	vimRC(d, "", "../whim-vim", "-e", "-s", "-c", "normal Gotwo", "-c", "w! %", "-c", "qa!", "sub/f.txt")
	t := strings.ReplaceAll(readFile(filepath.Join(d, "sub", "f.txt")), "\n", " ")
	os.RemoveAll(d)
	if t != "one two " {
		s.echo("  fnamemod     `:w %%` gave '%s', expected 'one two '", t)
		return harness.ErrReported
	}
	s.echo("  fnamemod     `:w %%` still writes the file being edited")
	return nil
}

func Whim32(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim32", args)
	if err != nil {
		return err
	}
	if !s.goneW("  compl        ", `\b%s\b`, gERE, gERE, true, nil, "ins_compl_get_exp", "pum_redraw", "ins_compl_next", "b_p_cpt", "b_p_dict", "p_pumheight",
		"docomplete", "ctrl_x_mode", "ins_complete", "ins_compl_addleader", "ins_compl_bs",
		"compl_busy", "compl_match_array", "ins_compl_show_pum", "ins_compl_build_pum",
		"ins_compl_has_autocomplete") {
		return harness.ErrReported
	}
	s.echo("  compl        no sources, no match list, no menu, no CTRL-X mode, no docomplete")
	if grepC(s.src(), `^\s*lastc = c;`, gERE) != 1 {
		s.echo("  compl        the lastc save is gone -- the disarm cut took the wrong block")
		return harness.ErrReported
	}
	s.echo("  compl        the lastc save is untouched")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	if s.st("complcheck", filepath.Join(s.work, "whim-vim")) {
		s.echo("  compl        insert mode still inserts; CTRL-X CTRL-N completes nothing")
		return nil
	}
	s.echo("  compl        insert mode or CTRL-X CTRL-N is not behaving as declared")
	return harness.ErrReported
}

func Whim34(w io.Writer, args []string) error {
	return goneTools("whim34", "  abbr         ", `\b%s\b`, gERE, "  abbr         nothing defines, lists or expands an abbreviation",
		"check_abbr", "echeck_abbr", "ccheck_abbr", "ex_abbreviate", "ex_abclear")(w, args)
}

func Whim35(w io.Writer, args []string) error {
	return goneTools("whim35", "  session      ", `\b%s\b`, gERE, "  session      no script, session or autocommand machinery is left",
		"ex_source", "ex_redir", "ex_sleep", "ex_smile", "ex_scriptencoding", "ex_scriptversion",
		"ex_vim9script", "ex_autocmd", "ex_doautocmd", "ex_doautoall", "ex_filetype", "ex_setfiletype",
		"do_autocmd", "do_doautocmd", "event_ignored", "check_ei", "did_set_eventignore", "p_ei", "p_lpl",
		"wo_eiw", "check_window_scroll_resize", "au_has_group")(w, args)
}

func Whim36(w io.Writer, args []string) error {
	return goneTools("whim36", "  tabs         ", `\b%s\b`, gERE, "  tabs         nothing makes, reaches, moves, lists or draws a second tab page",
		"ex_tabclose", "ex_tabnext", "ex_tabmove", "ex_tabonly", "ex_tabs", "ex_redrawtabline",
		"goto_tabpage", "goto_tabpage_lastused", "win_new_tabpage", "tabpage_close", "tabpage_move",
		"may_open_tabpage", "p_stal", "p_tpm", "p_tcl", "tcl_flags", "postponed_split_tab")(w, args)
}

func Whim37(w io.Writer, args []string) error {
	return goneTools("whim37", "  inert        ", `\b%s\b`, gERE, "  inert        no handler left for a command that did nothing",
		"ex_behave", "ex_mode", "ex_open", "ex_winpos", "get_behave_arg",
		"e_winpos_requires_two_number_arguments", "e_screen_mode_setting_not_supported")(w, args)
}

func Whim38(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim38", args)
	if err != nil {
		return err
	}
	if !s.goneW("  arglist      ", `\b%s\b`, gERE, gERE, true, nil, "ex_args", "ex_argadd", "ex_argdelete", "ex_argdedupe", "ex_argedit", "ex_argument",
		"ex_last", "ex_wnext", "ex_all", "get_arglist_name") {
		return harness.ErrReported
	}
	if !s.keptE("  arglist      ", " is gone, and :next, :previous or :drop needed it", "ex_next", "ex_previous", "do_argfile", "ex_rewind") {
		return harness.ErrReported
	}
	s.echo("  arglist      :next, :previous and :drop walk the list; nothing else does")
	if err := s.phasecheck(); err != nil {
		return err
	}
	return s.phasebuild()
}

func Whim39(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim39", args)
	if err != nil {
		return err
	}
	if !s.goneW("  windows      ", `\b%s\b`, gERE, gERE, true, nil, "ex_splitview", "ex_close", "ex_only", "ex_resize", "ex_wincmd", "ex_syncbind", "ex_buffer_all",
		"do_window", "nv_window", "win_split", "make_windows", "edit_buffers", "open_cmdwin",
		"cmdwin_type", "cmdwin_win", "cmdwin_buf", "cmdwin_result", "cedit_key", "p_cedit", "p_cwh",
		"p_sbo", "p_swb", "swb_flags", "swbuf_goto_win_with_buf", "tabpage_new",
		"do_check_scrollbind", "do_check_cursorbind", "check_scrollbind",
		"wo_scb", "wo_crb", "wo_wfb", "cmod_split", "postponed_split", "window_count", "window_layout") {
		return harness.ErrReported
	}
	s.echo("  windows      nothing makes, reaches, closes or binds a second window")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	for _, o := range []string{"-o", "-O", "-o2"} {
		out, rc := s.outWork(o, "-e", "-s", "-c", "qa!")
		if !strings.Contains(out, "Unknown option argument") {
			s.echo("  cli          %s is not refused as unknown (exit %d): %s", o, rc, out)
			return harness.ErrReported
		}
		if rc != 1 {
			s.echo("  cli          %s exits %d, expected 1", o, rc)
			return harness.ErrReported
		}
	}
	s.echo("  cli          -o and -O are unknown options")
	return nil
}

func Whim40(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim40", args)
	if err != nil {
		return err
	}
	if !s.goneW("  winsizes     ", `\b%s\b`, gERE, gERE, true, nil, "p_hh", "wo_wfh", "wo_wfw", "did_set_winheight_helpheight", "did_set_winminheight",
		"did_set_winwidth", "did_set_winminwidth", "did_set_equalalways", "did_set_eadirection",
		"did_set_splitkeep", "expand_set_eadirection", "expand_set_splitkeep") {
		return harness.ErrReported
	}
	s.echo("  winsizes     no row, callback or field is left for a window size")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	if s.probeSet("ignorecase") != 0 {
		s.echo("  options      the control failed: :set ignorecase exits non-zero too")
		return harness.ErrReported
	}
	for _, o := range []string{"winheight", "winminheight", "winwidth", "winminwidth", "helpheight", "splitbelow", "splitright",
		"splitkeep", "equalalways", "eadirection", "winfixheight", "winfixwidth"} {
		if s.probeSet(o+"?") == 0 {
			s.echo("  options      :set %s? was accepted, so the option is still there", o)
			return harness.ErrReported
		}
	}
	s.echo("  options      the twelve sizing options are refused, :set ignorecase still taken")
	return nil
}

func Whim41(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim41", args)
	if err != nil {
		return err
	}
	if !s.goneW("  buflist      ", `\b%s\b`, gERE, gERE, true, nil, "ex_buffer", "do_exbuffer", "buflist_list", "ex_bmodified", "ex_brewind", "ex_blast",
		"ex_bunload", "do_bufdel", "do_buffer", "ex_listdo") {
		return harness.ErrReported
	}
	calls := grepC(s.src(), `\bdo_buffer_ext\(`, gERE)
	gotos := grepC(s.src(), "do_buffer_ext(DOBUF_GOTO, ", gBRE)
	if calls != 3 || gotos != 1 {
		s.echo("  buflist      do_buffer_ext has %d mentions and %d DOBUF_GOTO calls, expected 3 and 1", calls, gotos)
		return harness.ErrReported
	}
	nums, ls := grepLines(s.src(), `\bCMD_(buffer|bNext|badd|balt|bdelete|bfirst|blast|bmodified|brewind|buffers|files|ls|bufdo|bunload|bwipeout)\b`, gERE)
	tbl := gre(`^[0-9]+:[ \t]*(\[CMD_|CMD_)`, gERE)
	var left []string
	for i := range nums {
		if l := fmt.Sprintf("%d:%s", nums[i], ls[i]); !tbl.MatchString(l) {
			left = append(left, l)
		}
	}
	if len(left) > 0 {
		s.echo("  buflist      a retired buffer command is still named outside the table:")
		for _, l := range head(left, 5) {
			s.echo("               %s", cutC(l, 120))
		}
		return harness.ErrReported
	}
	if !s.keptE("  buflist      ", " is gone, and :bnext or :bprevious needed it", "ex_bnext", "ex_bprevious", "goto_buffer") {
		return harness.ErrReported
	}
	s.echo("  buflist      :bnext and :bprevious walk the list; nothing else does")
	if err := s.phasecheck(); err != nil {
		return err
	}
	return s.phasebuild()
}
