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
	register("whim3", Whim3)
	register("whim8", Whim8)
	register("whim9", Whim9)
	register("whim11", Whim11)
	register("whim12", Whim12)
	register("whim16", Whim16)
	register("whim17", Whim17)
	register("whim18", Whim18)
	register("whim19", Whim19)
	register("whim20", Whim20)
	register("whim21", Whim21)
	register("whim22", Whim22)
	register("whim23", Whim23)
	register("whim24", Whim24)
}

// globalsExtra is what whims 16 to 20 say after a surviving global.
var globalsExtra = []string{
	"               a dropped row leaves its global uninitialised, and a",
	"               reader of it is a segfault before the first keystroke",
}

// symsGone is the `grep -qx SYM undefined` loop: the first still undefined
// refuses.
func (s *wsh) symsGone(syms ...string) bool {
	for _, g := range syms {
		if undefined(g) {
			s.echo("  symbols      %s is still undefined in the object", g)
			return false
		}
	}
	return true
}

func Whim3(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim3", args)
	if err != nil {
		return err
	}
	if !s.gone("  cmdline      ", gERE, gERE, true, nil,
		`\blist_version\b`, `\busage\(`, `\bmaybe_intro_message\b`,
		`\bcompiled_(user|sys)\b`, `\bearly_arg_scan\b`, `\bmake_tabpages\b`,
		`\bset_init_clean_rtp\b`,
		`\bis_not_a_term`, `More info with`, `"-nb"`,
		`"(not-a-term|noplugin|startuptime|gui-dialog-file|nofork|--clean)"`) {
		return harness.ErrReported
	}
	s.echo("  cmdline      nothing the introduction or a dropped option needed is left")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	if !s.st("clicheck", filepath.Join(s.work, "whim-vim")) {
		return harness.ErrReported
	}
	return nil
}

func Whim8(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim8", args)
	if err != nil {
		return err
	}
	if err := s.phasecheck(); err != nil {
		return err
	}
	if symNum("after") >= symNum("before") {
		s.echo("  symbols      this phase must lower the count")
		return harness.ErrReported
	}
	return s.phasebuild()
}

// encodingIn is whims 9 and 12's probe: `:set encoding?` redirected to a file
// in $work, with spaces and newlines taken out.
func (s *wsh) encodingIn(txt, out string) string {
	put(filepath.Join(s.work, txt), "x\n")
	s.inWork("-u", "NONE", "-i", "NONE", "-e", "-s", "-c", "redir! > "+out,
		"-c", "set encoding?", "-c", "redir END", "-c", "qall!", txt)
	e := strings.NewReplacer(" ", "", "\n", "").Replace(readFile(filepath.Join(s.work, out)))
	os.Remove(filepath.Join(s.work, txt))
	os.Remove(filepath.Join(s.work, out))
	return e
}

func Whim9(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim9", args)
	if err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	if enc := s.encodingIn(".enc.txt", ".enc.out"); enc != "encoding=utf-8" {
		s.echo("  encoding     got '%s', expected encoding=utf-8", enc)
		s.echo("               the locale used to supply this; the default must now carry it")
		return harness.ErrReported
	}
	s.echo("  encoding     utf-8 by compiled default, with no locale asked")
	return nil
}

func Whim11(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim11", args)
	if err != nil {
		return err
	}
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d := s.sub(".swtest")
	put(filepath.Join(d, "f.txt"), "a\nb\n")
	vimRC(d, "", "../whim-vim", "-u", "NONE", "-i", "NONE", "-e", "-s", "-c", "normal ohello", "-c", "wq", "f.txt")
	sw := lsA(d)
	os.RemoveAll(d)
	if sw != "f.txt " {
		s.echo("  swapfile     editing left: %s", sw)
		s.echo("               expected f.txt alone -- something still writes beside the file")
		return harness.ErrReported
	}
	s.echo("  swapfile     editing a file leaves the file, and nothing else")
	return nil
}

func Whim12(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim12", args)
	if err != nil {
		return err
	}
	if err := s.phasecheck(); err != nil {
		return err
	}
	if symNum("after") >= symNum("before") {
		s.echo("  symbols      this phase must lower the count")
		return harness.ErrReported
	}
	var left strings.Builder
	for _, l := range lines(readFile(".cache/symbols/last/undefined")) {
		if strings.HasPrefix(l, "iconv") {
			left.WriteString(l + " ")
		}
	}
	if left.Len() > 0 {
		s.echo("  iconv        still linked: %s", left.String())
		s.echo("               a dependency that is never reached is still a dependency")
		return harness.ErrReported
	}
	s.echo("  iconv        no longer linked at all")
	if err := s.phasebuild(); err != nil {
		return err
	}
	if enc := s.encodingIn(".e.txt", ".e.out"); enc != "encoding=utf-8" {
		s.echo("  encoding     got '%s', expected encoding=utf-8", enc)
		return harness.ErrReported
	}
	u := filepath.Join(s.work, ".u.txt")
	put(u, "\303\240\303\251\n")
	s.inWork("-u", "NONE", "-i", "NONE", "-e", "-s", "-c", "normal gUU", "-c", "wq", ".u.txt")
	ok := odX(u)
	os.Remove(u)
	if ok != "c380c3890a" {
		s.echo("  utf-8        gUU over 'a-grave e-acute' gave %s, expected c380c3890a", ok)
		s.echo("               the editor is no longer handling UTF-8 as UTF-8")
		return harness.ErrReported
	}
	s.echo("  utf-8        multibyte case conversion still works, and 'encoding' is utf-8")
	return nil
}

// globalsCheck is whims 16 to 19: a gone loop in `grep -c` with the two
// extra lines, the verdict, then the two tools.
func globalsCheck(name string, count, shown gmode, verdict string, pats ...string) Func {
	return func(w io.Writer, args []string) error {
		s, err := newWsh(w, name, args)
		if err != nil {
			return err
		}
		if !s.gone("  globals      ", count, shown, true, globalsExtra, pats...) {
			return harness.ErrReported
		}
		s.echo("%s", verdict)
		if err := s.phasecheck(); err != nil {
			return err
		}
		return s.phasebuild()
	}
}

func Whim16(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim16", args)
	if err != nil {
		return err
	}
	if !s.goneW("  globals      ", `\b%s\b`, gBRE, gBRE, true, globalsExtra, "p_path", "p_sua", "p_tags", "p_tc", "p_ar", "p_swf") {
		return harness.ErrReported
	}
	s.echo("  globals      none of the six is mentioned anywhere any more")
	if err := s.phasecheck(); err != nil {
		return err
	}
	return s.phasebuild()
}

func Whim17(w io.Writer, args []string) error {
	return globalsCheck("whim17", gBRE, gBRE, "  globals      neither option is named or read anywhere any more",
		"p_fenc", "p_bomb", "b_start_fenc", "b_start_bomb", `"fenc"`, `"bomb"`)(w, args)
}

func Whim18(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim18", args)
	if err != nil {
		return err
	}
	if !s.gone("  globals      ", gBRE, gBRE, true, globalsExtra,
		"p_exrc", "process_env", "set_init_xdg_rtp", "source_startup_scripts", `"VIMINIT"`, `"EXINIT"`, `"XDG_CONFIG_HOME"`) {
		return harness.ErrReported
	}
	s.echo("  startup      no config path, option or environment name is left")
	if !s.gone("  globals      ", gBRE, gBRE, true, globalsExtra,
		"evim_mode", "check_restricted", "EX_RESTRICT", "restricted", `"vif"`) {
		return harness.ErrReported
	}
	s.echo("  options      nothing names the four, or what they set")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	out, rc := s.outWork("-e", "-s", "-c", "qa!")
	if rc != 0 {
		s.echo("  cli          the control failed: -e -s -c qa! exits %d: %s", rc, out)
		return harness.ErrReported
	}
	out, rc = s.outWork("-u", "NONE", "-e", "-s", "-c", "qa!")
	if !strings.Contains(out, "Unknown option argument") {
		s.echo("  cli          -u is not refused as unknown (exit %d): %s", rc, out)
		return harness.ErrReported
	}
	if rc != 1 {
		s.echo("  cli          -u exits %d, expected 1", rc)
		return harness.ErrReported
	}
	s.echo("  cli          -u is an unknown option")
	return nil
}

func Whim19(w io.Writer, args []string) error {
	return globalsCheck("whim19", gBRE, gBRE, "  terminal     nothing asks the environment what terminal this is",
		`getenv((char \*)((char_u \*)"TERM")`, `getenv("LINES")`, `getenv("COLUMNS")`, `getenv((char \*)((char_u \*)"COLORS")`)(w, args)
}

func Whim20(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim20", args)
	if err != nil {
		return err
	}
	if !s.gone("  globals      ", gBRE, gBRE, true, globalsExtra,
		`getenv((char \*)((char_u \*)"HOME")`, "homedir", "init_users", "match_user", "getpwnam") {
		return harness.ErrReported
	}
	s.echo("  home         nothing asks where home is, or who this is")
	if !s.gone("  environment  ", gBREw, gBREw, true, nil, "getenv", "setenv", "unsetenv", "environ", "vim_getenv") {
		return harness.ErrReported
	}
	s.echo("  environment  nothing in the source asks the environment anything")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if !s.symsGone("getenv", "setenv", "unsetenv", "environ") {
		return harness.ErrReported
	}
	s.echo("  symbols      getenv, setenv, unsetenv and environ are gone from nm -u")
	return s.phasebuild()
}

func Whim21(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim21", args)
	if err != nil {
		return err
	}
	if !s.gone("  memfile      ", gBREw, gBREw, true, nil, "mf_fd", "mf_fname", "mf_ffname", "mf_write", "mf_read",
		"mf_release", "total_mem_used", "p_mmt", "p_dir", "mch_total_mem", "mch_get_host_name") {
		return harness.ErrReported
	}
	s.echo("  memfile      no descriptor, no eviction, no memory budget")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if !s.symsGone("getpwuid", "localtime_r", "strftime") {
		return harness.ErrReported
	}
	s.echo("  symbols      getpwuid is gone -- the last of the five password symbols")
	if !s.symsGone("sysinfo", "getrlimit", "uname") {
		return harness.ErrReported
	}
	s.echo("  symbols      sysinfo, getrlimit and uname are gone from nm -u")
	if err := s.phasebuild(); err != nil {
		return err
	}
	d := s.sub(".ovtest")
	put(filepath.Join(d, "a.txt"), "one\n")
	put(filepath.Join(d, "b.txt"), "two\n")
	rc := vimRC(d, "", "../whim-vim", "-e", "-s", "-c", "w! b.txt", "-c", "qa!", "a.txt")
	ov := fmt.Sprintf("%d:%s", rc, catS(filepath.Join(d, "b.txt")))
	os.RemoveAll(d)
	if ov != "0:one" {
		s.echo("  overwrite    :w! over an existing other file gave %s, expected 0:one", ov)
		return harness.ErrReported
	}
	s.echo("  overwrite    :w! over an existing other file writes it")
	return nil
}

func Whim22(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim22", args)
	if err != nil {
		return err
	}
	// Counted with grep -c and shown with grep -nw, as the shell does.
	if !s.gone("  cwd          ", gBRE, gBREw, true, nil,
		"mch_chdir(", "chdir(", "fchdir(", "win_fix_current_dir(", `\bglobaldir\b`, `\bstart_dir\b`) {
		return harness.ErrReported
	}
	if n := grepC(s.src(), `getcwd((char \*)`, gBRE); n != 1 {
		s.echo("  cwd          getcwd is called %d times, expected exactly 1", n)
		return harness.ErrReported
	}
	s.echo("  cwd          nothing moves the process; getcwd is asked once")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if !s.symsGone("chdir", "fchdir") {
		return harness.ErrReported
	}
	s.echo("  symbols      chdir and fchdir are gone from nm -u")
	if err := s.phasebuild(); err != nil {
		return err
	}
	d := s.sub(".reltest")
	os.MkdirAll(filepath.Join(d, "sub"), 0o755)
	put(filepath.Join(d, "sub", "f.txt"), "one\ntwo\n")
	vimRC(d, "", "../whim-vim", "-e", "-s", "-c", "normal Gothree", "-c", "wq", "sub/f.txt")
	vimRC(filepath.Join(d, "sub"), "", "../../whim-vim", "-e", "-s", "-c", "%s/two/2/", "-c", "wq", "../sub/f.txt")
	rel := strings.ReplaceAll(readFile(filepath.Join(d, "sub", "f.txt")), "\n", " ")
	os.RemoveAll(d)
	if rel != "one 2 three " {
		s.echo("  relative     a relative path gave '%s', expected 'one 2 three '", rel)
		return harness.ErrReported
	}
	s.echo("  relative     a relative path with a directory in it opens and writes")
	return nil
}

func Whim23(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim23", args)
	if err != nil {
		return err
	}
	if !s.gone("  libm         ", gBRE, gBRE, true, nil, "ceil(", "floor(", "log10(", "infinity_str", "TYPE_FLOAT", "typename_float") {
		return harness.ErrReported
	}
	s.echo("  libm         nothing calls a floating-point function")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if !s.symsGone("ceil", "floor", "log10") {
		return harness.ErrReported
	}
	s.echo("  symbols      ceil, floor and log10 are gone from nm -u")
	return s.phasebuild()
}

// probeSet is `(cd "$work" && ./whim-vim -e -s -c "set $1" -c 'qa!' ...)`
// and its status.
func (s *wsh) probeSet(opt string) int {
	return s.inWork("-e", "-s", "-c", "set "+opt, "-c", "qa!")
}

func Whim24(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim24", args)
	if err != nil {
		return err
	}
	if !s.gone("  mouse        ", gBRE, gBRE, true, nil, "do_mouse", "jump_to_mouse", "setmouse", "mouse_has", "nv_mouse",
		"check_termcode_mouse", "p_mouse", "ttymouse", `"LeftMouse"`, "ScrollWheelUp", "WaitForCharOrMouse") {
		return harness.ErrReported
	}
	s.echo("  mouse        no handler, no option, no key name, no protocol")
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
	if s.probeSet("mouse=a") == 0 {
		s.echo("  options      :set mouse=a was accepted, so the option is still there")
		return harness.ErrReported
	}
	s.echo("  options      :set mouse=a is refused, :set ignorecase still taken")
	return nil
}

var _ = sort.Strings
