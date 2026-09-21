package check

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"slimvim.local/tools/internal/harness"
)

func init() {
	register("whim42", Whim42)
	register("whim43", Whim43)
	register("whim44", Whim44)
	register("whim45", Whim45)
	register("whim46", Whim46)
	register("whim47", Whim47)
	register("whim49", Whim49)
	register("whim50", Whim50)
	register("whim51", Whim51)
	register("whim52", Whim52)
	register("whim53", Whim53)
	register("whim55", Whim55)
	register("whim56", Whim56)
	register("whim57", Whim57)
	register("whim58", Whim58)
}

func Whim42(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim42", args)
	if err != nil {
		return err
	}
	if !s.goneW("  onebuffer    ", `\b%s\b`, gERE, gERE, true, nil, "buf_hide", "p_hid", "b_p_bh", "setaltfname", "buflist_altfpos", "w_alt_fnum", "goto_buffer",
		"do_buffer_ext", "ex_bnext", "ex_bprevious", "nv_hat", "did_set_bufhidden") {
		return harness.ErrReported
	}
	const cm = `cmod_flags (&|\|=) CMOD_(KEEPALT|HIDE)\b`
	if grepQ(s.src(), cm, gERE) {
		s.echo("  onebuffer    :keepalt or :hide is still set or tested after the sweep")
		nums, ls := grepLines(s.src(), cm, gERE)
		for i := 0; i < len(nums) && i < 3; i++ {
			s.echo("               %s", cutC(fmt.Sprintf("%d:%s", nums[i], ls[i]), 100))
		}
		return harness.ErrReported
	}
	calls := grepC(s.src(), `\bbuflist_new\(`, gERE)
	s.echo("  onebuffer    buflist_new is named %d times: %d calls", calls, grepC(s.src(), `^[ \t]+[^ \t].*\bbuflist_new\(`, gERE))
	s.echo("  onebuffer    nothing hides, nothing is the alternate, and a buffer left is wiped")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	a := filepath.Join(d, "a")
	put(a, "one\ntwo\nthree\n")
	put(filepath.Join(d, "b"), "other\n")
	vimRC(d, "", "./vim", "-e", "-s", "+2", "+mark a", "+e b", "+e a", "+'ad", "+w", "+q!", "a")
	if catS(a) != "one\ntwo\nthree" {
		s.echo("  onebuffer    a mark survived leaving its file -- the buffer was kept, not wiped")
		for _, l := range lines(readFile(a)) {
			s.echo("               %s", l)
		}
		return harness.ErrReported
	}
	if vimRC(d, "", "./vim", "-e", "-s", "+e b", "+e #", "+q!", "a") == 0 {
		s.echo("  onebuffer    :e # succeeded, so there is still an alternate file")
		return harness.ErrReported
	}
	put(a, "one\n")
	vimRC(d, "", "./vim", "-e", "-s", "+saveas c", "+s/$/X/", "+w", "+q!", "a")
	if catS(a) != "one" || catS(filepath.Join(d, "c")) != "oneX" {
		s.echo("  onebuffer    :saveas did not rename the buffer: a=%s c=%s", catS(a), catS(filepath.Join(d, "c")))
		return harness.ErrReported
	}
	s.echo("  onebuffer    a mark goes with its file, :e # is refused, :saveas renames")
	return nil
}

func Whim43(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim43", args)
	if err != nil {
		return err
	}
	if !s.goneW("  cmdargs      ", `\b%s\b`, gERE, gERE, true, nil, "exe_pre_commands", "pre_commands", "n_pre_commands", "reset_modifiable") {
		return harness.ErrReported
	}
	s.echo("  cmdargs      nothing collects or runs --cmd commands")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	if _, rc := s.outWork("-e", "-s", "+q!"); rc != 0 {
		s.echo("  cli          the control failed: +q! exits %d", rc)
		return harness.ErrReported
	}
	for _, o := range []string{"-c qa!", "-cqa!", "--cmd qa!", "-R", "-m", "-M", "-w7"} {
		out, rc := s.outWork(append(strings.Fields(o), "-e", "-s", "+q!")...)
		if !strings.Contains(out, "Unknown option argument") {
			s.echo("  cli          %s is not refused as unknown (exit %d): %s", o, rc, out)
			return harness.ErrReported
		}
		if rc != 1 {
			s.echo("  cli          %s exits %d, expected 1", o, rc)
			return harness.ErrReported
		}
	}
	s.echo("  cli          -c, --cmd, -R, -m, -M and -w are unknown; +{command} still runs")
	return nil
}

func Whim44(w io.Writer, args []string) error {
	return goneTools("whim44", "  filters      ", `\b%s\b`, gERE, "  filters      no :!, no sorting, no retab, no alignment; the ! key beeps",
		"ex_bang", "ex_sort", "ex_uniq", "ex_retab", "ex_align")(w, args)
}

func Whim45(w io.Writer, args []string) error {
	return goneTools("whim45", "  drop         ", `\b%s\b`, gERE, "  drop         nothing is left of :drop",
		"ex_drop", "set_arglist", "ex_rewind")(w, args)
}

func Whim46(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim46", args)
	if err != nil {
		return err
	}
	if !s.goneW("  allcmds      ", `\b%s\b`, gERE, gERE, true, nil, "do_wqall", "ex_quit_all") {
		return harness.ErrReported
	}
	s.echo("  allcmds      nothing is left of the -all commands")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	if out, rc := s.outWork("-e", "-s", "+q!"); rc != 0 {
		s.echo("  quit         +q! exits %d: %s", rc, out)
		return harness.ErrReported
	}
	if out, rc := s.outWork("-e", "-s", "+qa!"); rc != 1 {
		s.echo("  quit         +qa! exits %d, expected 1: %s", rc, out)
		return harness.ErrReported
	}
	s.echo("  quit         :q! quits, :qa! is not a command")
	return nil
}

func Whim47(w io.Writer, args []string) error {
	return goneTools("whim47", "  insertcmds   ", `\b%s\b`, gERE, "  insertcmds   no command enters or leaves Insert mode",
		"ex_startinsert", "ex_stopinsert")(w, args)
}

func Whim49(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim49", args)
	if err != nil {
		return err
	}
	if !s.goneW("  optset       ", `\b%s\b`, gERE, gERE, true, nil, "do_modelines", "chk_modeline", "p_mls", "p_mle", "p_mlstr", "p_ml", "p_ml_nobin", "b_p_ml", "b_p_ml_nobin",
		"modeline_whitelist", "is_modeline_whitelisted") {
		return harness.ErrReported
	}
	s.echo("  optset       no modeline, and nothing that set one copy of an option")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	if out, rc := s.outWork("-e", "-s", "+set ts=3", "+q!"); rc != 0 {
		s.echo("  optset       the control failed: :set ts=3 exits %d: %s", rc, out)
		return harness.ErrReported
	}
	if out, rc := s.outWork("-e", "-s", "+set ts<", "+q!"); rc != 1 {
		s.echo("  optset       :set ts< exits %d, expected 1: %s", rc, out)
		return harness.ErrReported
	}
	d, _ := os.MkdirTemp("", "whimchk")
	defer os.RemoveAll(d)
	m := filepath.Join(d, "m.txt")
	put(m, "one\n# vim: set sw=2:\n")
	// "$OLDPWD/$work/whim-vim": the work tree as seen from where the check runs.
	bin, _ := filepath.Abs(filepath.Join(s.work, "whim-vim"))
	vimRC(d, d, bin, "-e", "-s", "+1normal! >>", "+w", "+q!", "m.txt")
	if first := sedN(m, 1); first != "    one" {
		s.echo("  optset       a modeline set 'shiftwidth': the first line is '%s'", first)
		return harness.ErrReported
	}
	s.echo("  optset       :set ts< is refused, and a modeline sets nothing")
	return nil
}

func Whim50(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim50", args)
	if err != nil {
		return err
	}
	if !s.goneW("  lfonly       ", `\b%s\b`, gERE, gERE, true, nil, "get_fileformat", "get_fileformat_force", "set_fileformat", "default_fileformat", "file_ff_differs",
		"save_file_ff", "set_file_options", "set_options_bin", "msg_add_fileformat", "check_ff_value",
		"force_ff", "force_bin", "p_ffs", "p_bin", "b_p_bin", "b_p_ff", "b_p_eol", "b_p_fixeol", "b_p_eof", "b_p_tx",
		"b_start_ffc", "b_start_eol", "b_start_eof", "b_no_eol_lnum", "try_mac", "try_dos", "write_bin") {
		return harness.ErrReported
	}
	s.echo("  lfonly       no format, no binary mode, no end-of-line option")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	out, rc := vimOut(d, "", "./vim", true, "-b", "-e", "-s", "+q!")
	if !strings.Contains(out, "Unknown option argument") {
		s.echo("  lfonly       -b is not refused as unknown (exit %d): %s", rc, out)
		return harness.ErrReported
	}
	if vimRC(d, "", "./vim", "-e", "-s", "+set ts=3", "+q!") != 0 {
		s.echo("  lfonly       the control :set ts=3 failed")
		return harness.ErrReported
	}
	if vimRC(d, "", "./vim", "-e", "-s", "+set ff=dos", "+q!") == 0 {
		s.echo("  lfonly       :set ff=dos was accepted")
		return harness.ErrReported
	}
	c := filepath.Join(d, "crlf.txt")
	put(c, "one\r\ntwo\r\n")
	vimRC(d, "", "./vim", "-e", "-s", "+%s/$/X/", "+wq", "crlf.txt")
	if odC(c) != `one\rX\ntwo\rX\n` {
		s.echo("  lfonly       a CR LF file was not edited as LF text: %s", odCs(c))
		return harness.ErrReported
	}
	n := filepath.Join(d, "noeol.txt")
	put(n, "one\ntwo")
	vimRC(d, "", "./vim", "-e", "-s", "+w", "+q!", "noeol.txt")
	if odC(n) != `one\ntwo\n` {
		s.echo("  lfonly       a last line was written without LF: %s", odCs(n))
		return harness.ErrReported
	}
	s.echo("  lfonly       -b unknown, ff refused, CR is text, and every line ends with LF")
	return nil
}

func Whim51(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim51", args)
	if err != nil {
		return err
	}
	if !s.goneW("  keepbytes    ", `\b%s\b`, gERE, gERE, true, nil, "get_bad_opt", "bad_char_behavior", "b_bad_char", "BAD_REPLACE") {
		return harness.ErrReported
	}
	s.echo("  keepbytes    nothing replaces, drops or chooses what to do with an invalid byte")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	u := filepath.Join(d, "u.txt")
	put(u, "caf\303\251\n")
	inD(d, "-e", "-s", `+s/\%u00e9/E/`, "+wq", "u.txt")
	if catS(u) != "cafE" {
		s.echo("  keepbytes    the control failed: a UTF-8 edit gave '%s'", catS(u))
		return harness.ErrReported
	}
	ill := filepath.Join(d, "ill.txt")
	put(ill, "ok\n\377 bad\n")
	inD(d, "-e", "-s", "+1s/ok/OK/", "+wq", "ill.txt")
	if odC(ill) != `OK\n377bad\n` {
		s.echo("  keepbytes    an invalid byte was not written back unchanged: %s", odCs(ill))
		return harness.ErrReported
	}
	out, _ := vimOut(d, d, "./vim", true, "-e", "-s", "+set ro?", "+q!", "ill.txt")
	ro := strings.NewReplacer(" ", "", "\n", "").Replace(out)
	if ro != "noreadonly" {
		s.echo("  keepbytes    reading an invalid byte made the buffer '%s'", ro)
		return harness.ErrReported
	}
	if inD(d, "-e", "-s", "+e ++bad=keep ill.txt", "+q!") == 0 {
		s.echo("  keepbytes    ++bad=keep was accepted")
		return harness.ErrReported
	}
	s.echo("  keepbytes    an invalid byte is written back unchanged, the buffer stays writable, ++bad is refused")
	return nil
}

func Whim52(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim52", args)
	if err != nil {
		return err
	}
	if !s.goneW("  utf8only     ", `\b%s\b`, gERE, gERE, true, nil, "enc_utf8", "has_mbyte", "enc_dbcs", "enc_unicode", "enc_latin1like", "__T__", "__F__", "__Z__") {
		return harness.ErrReported
	}
	s.echo("  utf8only     no encoding flag is asked, and %d DBCS call sites are left", grepC(s.src(), `\bdbcs_[a-z_0-9]+\(`, gERE))
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	u := filepath.Join(d, "u.txt")
	put(u, "\303\240\303\251\n")
	inD(d, "-e", "-s", "+1normal! gUU", "+wq", "u.txt")
	if odX(u) != "c380c3890a" {
		s.echo("  utf8only     gUU over a-grave e-acute gave %s", odXs(u))
		return harness.ErrReported
	}
	x := filepath.Join(d, "x.txt")
	put(x, "a\346\227\245b\n")
	inD(d, "-e", "-s", "+1normal! 0lx", "+wq", "x.txt")
	if catS(x) != "ab" {
		s.echo("  utf8only     x on a three-byte character left '%s'", catS(x))
		return harness.ErrReported
	}
	s.echo("  utf8only     gUU and x work on multibyte characters")
	return nil
}

func Whim53(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim53", args)
	if err != nil {
		return err
	}
	if !s.goneW("  noconv       ", `\b%s\b`, gERE, gERE, true, nil, "need_conversion", "get_fio_flags", "check_for_bom", "next_fenc", "set_forced_fenc", "enc_canonize",
		"force_enc", "p_enc", "iconv_fd", "ucs2bytes", "mb_ptr2len", "mb_head_off", "mb_ptr2char", "latin_ptr2len",
		"dbcs_head_off", "dbcs_ptr2len", "get_encoding_name", "get_bad_name", "get_fileformat_name",
		"input_conv", "output_conv", "convert_setup", "string_convert", "convert_input_safe", "p_menc", "b_p_menc", "did_set_encoding") {
		return harness.ErrReported
	}
	s.echo("  noconv       no conversion, no 'encoding', no mb_* pointer, no DBCS path")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	if inD(d, "-e", "-s", "+set ts=3", "+q!") != 0 {
		s.echo("  noconv       the control :set ts=3 failed")
		return harness.ErrReported
	}
	if inD(d, "-e", "-s", "+set enc?", "+q!") == 0 {
		s.echo("  noconv       :set enc? was accepted")
		return harness.ErrReported
	}
	if inD(d, "-e", "-s", "+set menc?", "+q!") == 0 {
		s.echo("  noconv       :set menc? was accepted")
		return harness.ErrReported
	}
	put(filepath.Join(d, "e.txt"), "x\n")
	if inD(d, "-e", "-s", "+e ++enc=latin1 e.txt", "+q!") == 0 {
		s.echo("  noconv       ++enc was accepted")
		return harness.ErrReported
	}
	u := filepath.Join(d, "u.txt")
	put(u, "\303\240\303\251\n")
	inD(d, "-e", "-s", "+1normal! gUU", "+wq", "u.txt")
	if odX(u) != "c380c3890a" {
		s.echo("  noconv       gUU over a-grave e-acute gave %s", odXs(u))
		return harness.ErrReported
	}
	ill := filepath.Join(d, "ill.txt")
	put(ill, "ok\n\377 bad\n")
	inD(d, "-e", "-s", "+1s/ok/OK/", "+wq", "ill.txt")
	if odC(ill) != `OK\n377bad\n` {
		s.echo("  noconv       an invalid byte was not kept: %s", odCs(ill))
		return harness.ErrReported
	}
	s.echo("  noconv       :set enc, :set menc and ++enc refused; UTF-8 edits and a kept invalid byte unchanged")
	return nil
}

// unknownOpts is the scratch-copy half of whims 55 to 62: the control
// `:set sw=3` must work and every named option must be refused.
func (s *wsh) unknownOpts(d, prefix string, opts ...string) bool {
	if inD(d, "-e", "-s", "+set sw=3", "+q!") != 0 {
		s.echo("%sthe control :set sw=3 failed", prefix)
		return false
	}
	for _, o := range opts {
		if inD(d, "-e", "-s", "+set "+o+"?", "+q!") == 0 {
			s.echo("%s:set %s? was accepted", prefix, o)
			return false
		}
	}
	return true
}

func Whim55(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim55", args)
	if err != nil {
		return err
	}
	if !s.goneW("  unusedopts   ", `\b%s\b`, gERE, gERE, true, nil, "p_act", "p_cdh", "p_cdpath", "p_cto", "p_imcmdline", "p_secure", "p_shcf", "p_stmp", "p_sxe", "p_sxq", "p_sn", "b_p_sn",
		"p_tbi", "p_warn", "p_xtermcodes", "p_cms", "b_p_cms", "p_cfc", "cfc_flags", "p_cia", "cia_flags", "p_hf", "p_lop", "b_p_lop",
		"p_opfunc", "opfunc_cb", "did_set_commentstring", "did_set_completefuzzycollect", "did_set_completeitemalign",
		"did_set_helpfile", "did_set_lispoptions", "did_set_operatorfunc") {
		return harness.ErrReported
	}
	s.echo("  unusedopts   no variable, flag set or callback of the 36 is left")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	if !s.unknownOpts(d, "  unusedopts   ", "shelltemp", "commentstring", "t_EI") {
		return harness.ErrReported
	}
	s.echo("  unusedopts   :set sw works; :set shelltemp, commentstring and t_EI are unknown")
	return nil
}

func Whim56(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim56", args)
	if err != nil {
		return err
	}
	if !s.goneW("  noshellrtp   ", `\b%s\b`, gERE, gERE, true, nil, "p_kp", "b_p_kp", "p_sh", "p_shq", "p_srr", "p_rtp", "p_pp", "get_isolated_shell_name", "csh_like_shell", "ExpandRTDir",
		"ExpandPackAddDir", "expand_runtime_cmd", "set_context_in_runtime_cmd", "did_set_shellpipe_redir") {
		return harness.ErrReported
	}
	s.echo("  noshellrtp   no shell, runtime-path or keyword-program option or reader is left")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	if !s.unknownOpts(d, "  noshellrtp   ", "shell", "shellquote", "shellredir", "runtimepath", "packpath", "keywordprg") {
		return harness.ErrReported
	}
	s.echo("  noshellrtp   :set sw works; the six are unknown")
	return nil
}

func Whim57(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim57", args)
	if err != nil {
		return err
	}
	if !s.goneW("  nolisp       ", `\b%s\b`, gERE, gERE, true, nil, "b_p_lisp", "p_lisp", "b_p_lw", "p_lispwords", "get_lisp_indent", "lisp_match", "use_indentexpr_for_lisp", "did_set_lisp", "lispcomm", "CPO_LISP", "BV_LISP", "BV_LW") {
		return harness.ErrReported
	}
	s.echo("  nolisp       no lisp option, indenter, word list or match mode is left")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	if !s.unknownOpts(d, "  nolisp       ", "lisp", "lispwords") {
		return harness.ErrReported
	}
	m := filepath.Join(d, "m.txt")
	put(m, "(a ; b)\n")
	inD(d, "-e", "-s", "+1normal! 0%x", "+wq", "m.txt")
	if catS(m) != "(a ; b" {
		s.echo("  nolisp       %% across ';' left '%s'", catS(m))
		return harness.ErrReported
	}
	s.echo("  nolisp       :set sw works; lisp and lispwords are unknown; %% matches across ';'")
	return nil
}

func Whim58(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim58", args)
	if err != nil {
		return err
	}
	if !s.goneW("  nolangmap    ", `\b%s\b`, gERE, gERE, true, nil, "b_p_iminsert", "b_p_imsearch", "p_iminsert", "p_imsearch", "B_IMODE_NONE", "B_IMODE_LMAP", "B_IMODE_LAST", "MODE_LANGMAP",
		"ins_ctrl_hat", "cmdline_toggle_langmap", "set_iminsert_global", "set_imsearch_global", "did_set_iminsert", "did_set_imsearch",
		"get_keymap_str", "b_im_ptr", "langmap_active") {
		return harness.ErrReported
	}
	s.echo("  nolangmap    no language-mapping mode, toggle or option is left")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	if !s.unknownOpts(d, "  nolangmap    ", "iminsert", "imsearch") {
		return harness.ErrReported
	}
	if inD(d, "-e", "-s", "+lmap a b", "+q!") == 0 {
		s.echo("  nolangmap    :lmap was accepted")
		return harness.ErrReported
	}
	h := filepath.Join(d, "h.txt")
	put(h, "x\n")
	inD(d, "-e", "-s", "+1normal! Ia\036b", "+wq", "h.txt")
	if catS(h) != "abx" {
		s.echo("  nolangmap    CTRL-^ in Insert mode left '%s'", catS(h))
		return harness.ErrReported
	}
	s.echo("  nolangmap    :set sw works; iminsert, imsearch and :lmap are unknown; CTRL-^ inserts nothing")
	return nil
}
