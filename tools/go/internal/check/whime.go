package check

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"slimvim.local/tools/internal/harness"
)

func init() {
	register("whim66", Whim66)
	register("whim67", Whim67)
	register("whim68", Whim68)
	register("whim69", Whim69)
	register("whim70", Whim70)
	register("whim71", Whim71)
	register("whim72", Whim72)
	register("whim73", Whim73)
	register("whim74", Whim74)
	register("whim75", Whim75)
	register("whim76", Whim76)
	register("whim77", Whim77)
	register("whim78", Whim78)
	register("whim79", Whim79)
	register("whim82", Whim82)
}

// cnt0 is `n=$(grep -cE "\b$g\b" f); [ "$n" = 0 ] || { echo "PREFIX$g still
// has $n mentions"; exit 1; }` -- the later checks' shorter form of gone.
func (s *wsh) cnt0(prefix string, names ...string) bool {
	for _, g := range names {
		if n := grepC(s.src(), `\b`+g+`\b`, gERE); n != 0 {
			s.echo("%s%s still has %d mentions", prefix, g, n)
			return false
		}
	}
	return true
}

// fnBody is `awk '/^NAME\(/,/^\}$/' f`.
func (s *wsh) fnBody(start string) string { return awkRanges(s.src(), start, `^\}$`) }

// probeFile is the scratch-copy probe most later checks run: write CONTENT,
// run the editor with ARGS on FILE, and read it back through READ.
func probeFile(d, file, content string, args ...string) string {
	put(filepath.Join(d, file), content)
	inD(d, append(append([]string{"-e", "-s"}, args...), file)...)
	return filepath.Join(d, file)
}

func Whim66(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim66", args)
	if err != nil {
		return err
	}
	if !s.goneW("  nopara       ", `\b%s\b`, gERE, gERE, true, nil, "findsent", "findpar", "startPS", "current_sent", "current_par", "nv_brace", "nv_findpar") {
		return harness.ErrReported
	}
	if !s.keptE("  nopara       ", " went too -- it was not the paragraph's", "findmatchlimit", "nv_bracket_block", "current_block", "current_word", "current_quote", "nv_percent", "getnextmark", "nv_brackets") {
		return harness.ErrReported
	}
	s.echo("  nopara       no sentence, paragraph or section is left; brackets and words are")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	const sample = "One two. Three four.\n\nvoid f(void)\n{\n    if (x)\n    {\n        y;\n    }\n}\n#if A\n#endif\n"
	t := filepath.Join(d, "t.txt")
	for _, k := range []string{")ix", "(ix", "}ix", "{ix", "]]ix", "[[ix", "[mix", "]mix", "[#ix", "[/ix", "dapix", "disix"} {
		put(t, sample)
		inD(d, "-e", "-s", "+5", "+normal! "+k, "+wq", "t.txt")
		if readFile(t) != sample {
			s.echo("  nopara       %s changed the file:", k)
			for _, l := range head(lines(readFile(t)), 3) {
				s.echo("               %s", l)
			}
			return harness.ErrReported
		}
	}
	put(t, sample)
	inD(d, "-e", "-s", "+5", "+normal! ix", "+wq", "t.txt")
	if !grepQ(readFile(t), `^    xif (x)$`, gBRE) {
		s.echo("  nopara       the control insert failed")
		return harness.ErrReported
	}
	firstX := func() string { return strings.SplitN(grepNum(t, "X", gBRE), "\n", 2)[0] }
	put(t, sample)
	inD(d, "-e", "-s", "+7", "+normal! [{", "+s/^/X/", "+wq", "t.txt")
	if !grepQ(readFile(t), `^X    {$`, gBRE) {
		s.echo("  nopara       [{ no longer walks out: %s", firstX())
		return harness.ErrReported
	}
	put(t, sample)
	inD(d, "-e", "-s", "+4", "+normal! %", "+s/^/X/", "+wq", "t.txt")
	if !grepQ(readFile(t), `^X}$`, gBRE) {
		s.echo("  nopara       %% no longer matches: %s", firstX())
		return harness.ErrReported
	}
	put(t, sample)
	inD(d, "-e", "-s", "+7", "+normal! di{", "+wq", "t.txt")
	if !grepQ(readFile(t), `^    {$`, gBRE) {
		s.echo("  nopara       i{ took the enclosing braces too")
		return harness.ErrReported
	}
	if grepQ(readFile(t), "y;", gBRE) {
		s.echo("  nopara       i{ no longer selects a block -- y; survived")
		return harness.ErrReported
	}
	put(t, sample)
	inD(d, "-e", "-s", "+'{,'}d", "+wq", "t.txt")
	if !grepQ(readFile(t), `^One two\. Three four\.$`, gBRE) {
		s.echo("  nopara       '{,'} still addressed a paragraph")
		return harness.ErrReported
	}
	s.echo("  nopara       the cut keys do nothing; [{ and %% still move; i{ still selects; '{ is refused")
	return nil
}

func Whim67(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim67", args)
	if err != nil {
		return err
	}
	if !s.goneW("  nomouse      ", `\b%s\b`, gERE, gERE, true, nil, "is_mouse_key", "dragwin", "held_button", "mouse_row", "mouse_col", "old_mouse_row", "old_mouse_col",
		"reset_dragwin", "reset_held_button", "spellvars_T", "spv_has_spell",
		"did_check_timestamps", "did_emsg_syntax", "typebuf_was_empty", "in_mch_delay", "frame_locked",
		"swap_exists_did_quit", "did_swapwrite_msg", "autocmd_nested", "oldtitle_outdated", "deadly_signal",
		"mr_patternlen", "was_safe", "state_no_longer_safe", "mouse_index_found", "looks_like_mouse_start") {
		return harness.ErrReported
	}
	const keys = `\(char_u \*\)\("\w*(Mouse|Drag|Release|Wheel)\w*"\)`
	if n := grepC(s.src(), keys, gERE); n != 0 {
		s.echo("  nomouse      %d mouse key names left in key_names_table", n)
		nums, ls := grepLines(s.src(), keys, gERE)
		for i := 0; i < len(nums) && i < 3; i++ {
			s.echo("%s", cutC(fmt.Sprintf("%d:%s", nums[i], ls[i]), 110))
		}
		return harness.ErrReported
	}
	if !grepQ(s.src(), `\bvim_ignored\b`, gBRE) {
		s.echo("  nomouse      vim_ignored went -- warn_unused_result has nothing to assign to")
		return harness.ErrReported
	}
	if n := grepC(awkRanges(s.src(), `nv_cmds\[\] =`, `^\};`), `KE_(MOUSE|LEFT|MIDDLE|RIGHT|X1|X2)|SCROLLBAR|TABLINE|TABMENU`, gERE); n != 26 {
		s.echo("  nomouse      %d mouse rows left in nv_cmds, expected 26 kept at nv_error", n)
		return harness.ErrReported
	}
	s.echo("  nomouse      no mouse, spell plumbing or write-only flag is left; the nv_cmds rows are")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	t := probeFile(d, "t.txt", "alpha\nbeta\ngamma\n", "+2", "+normal! dd", "+wq")
	if bar(t) != "alpha|gamma|" {
		s.echo("  nomouse      editing broke: '%s'", bar(t))
		return harness.ErrReported
	}
	if inD(d, "-e", "-s", "+map <Home> x", "+q!") != 0 {
		s.echo("  nomouse      mapping a real key name broke")
		return harness.ErrReported
	}
	s.echo("  nomouse      editing works; a real key name still maps")
	return nil
}

func Whim68(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim68", args)
	if err != nil {
		return err
	}
	if !s.goneW("  onewindow    ", `\b%s\b`, gERE, gERE, true, nil, "win_split_ins", "win_alloc_popup_win", "win_init_popup_win", "aucmd_win", "AUCMD_WIN_COUNT", "aucmdwin_T",
		"use_aucmd_win_idx", "win_close", "close_windows", "win_close_othertab", "close_last_window_tabpage",
		"close_tabpage", "free_tabpage", "winframe_remove", "win_equal", "win_equal_rec", "frame2win", "win_altframe",
		"make_snapshot", "restore_snapshot", "clear_snapshot", "clear_snapshot_rec") {
		return harness.ErrReported
	}
	if !s.keptE("  onewindow    ", " went too -- the one window still needs it", "win_comp_pos", "frame_comp_pos", "shell_new_rows", "did_set_laststatus", "last_status", "last_status_rec", "topframe", "curwin", "firstwin", "win_alloc_firstwin") {
		return harness.ErrReported
	}
	s.echo("  onewindow    nothing can add a window or a tabpage; the one window keeps its geometry")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	t := probeFile(d, "t.txt", "alpha\nbeta\ngamma\n", "+2", "+normal! dd", "+wq")
	if bar(t) != "alpha|gamma|" {
		s.echo("  onewindow    editing broke: '%s'", bar(t))
		return harness.ErrReported
	}
	q := probeFile(d, "q.txt", "one\n", "+normal! ix", "+q", "+wq")
	if !grepQ(readFile(q), `^xone$`, gBRE) {
		s.echo("  onewindow    :q on a modified buffer did not refuse")
		return harness.ErrReported
	}
	if inD(d, "-e", "-s", "+set laststatus=2", "+set lines=30 columns=90", "+wq", "t.txt") != 0 {
		s.echo("  onewindow    :set laststatus/lines/columns broke")
		return harness.ErrReported
	}
	s.echo("  onewindow    editing works; :q refuses a modified buffer; laststatus and a resize still compute")
	return nil
}

// loadsEdits is the probe pair nearly every late check opens with: the file
// loads, and a line deletes.  loadWant is what `+$ +s/^/LAST /` leaves.
func (s *wsh) loads(d, prefix, content, want string) bool {
	t := probeFile(d, "t.txt", content, "+$", "+s/^/LAST /", "+wq")
	if bar(t) != want {
		s.echo("%sthe file did not load: '%s'", prefix, bar(t))
		return false
	}
	return true
}

func (s *wsh) edits(d, prefix, file, content, want string) bool {
	e := probeFile(d, file, content, "+2", "+normal! dd", "+wq")
	if bar(e) != want {
		s.echo("%sediting broke: '%s'", prefix, bar(e))
		return false
	}
	return true
}

// switchesE is `:e h2.txt` from h1.txt, with the two refusals a check names.
func (s *wsh) switchesE(d, prefix, a, b, ac, bc, bwant, add string) bool {
	put(filepath.Join(d, a), ac)
	put(filepath.Join(d, b), bc)
	inD(d, "-e", "-s", "+e "+b, add, "+wq", a)
	if catS(filepath.Join(d, a)) != strings.TrimRight(ac, "\n") {
		s.echo("%s:e wrote over the first file: %s", prefix, catS(filepath.Join(d, a)))
		return false
	}
	if catS(filepath.Join(d, b)) != bwant {
		s.echo("%s:e did not load the second file: %s", prefix, catS(filepath.Join(d, b)))
		return false
	}
	return true
}

func Whim69(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim69", args)
	if err != nil {
		return err
	}
	if !s.goneW("  onearg       ", `\b%s\b`, gERE, gERE, true, nil, "ex_next", "ex_previous", "do_argfile", "do_arglist", "arglist_del_files", "alist_set", "alist_clear", "alist_add",
		"alist_name", "alist_init", "editing_arg_idx", "check_arglist_locked", "arglist_locked", "arg_had_last",
		"global_alist", "alist_T", "aentry_T", "w_alist", "w_arg_idx", "w_arg_idx_invalid", "AL_SET", "AL_ADD", "AL_DEL") {
		return harness.ErrReported
	}
	if !s.keptE("  onearg       ", " went too -- the one file would not load", "buflist_add", "buflist_new", "open_buffer", "b_ffname", "readfile", "command_line_scan") {
		return harness.ErrReported
	}
	if !grepQ(s.src(), "buflist_add(p, BLN_CURBUF | BLN_LISTED);", gBRE) {
		s.echo("  onearg       the command line no longer names the buffer")
		return harness.ErrReported
	}
	s.echo("  onearg       one file argument, no argument list, and the name still reaches curbuf")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	if !s.loads(d, "  onearg       ", "l1\nl2\nl3\n", "l1|l2|LAST l3|") || !s.edits(d, "  onearg       ", "e.txt", "a\nb\nc\n", "a|c|") {
		return harness.ErrReported
	}
	put(filepath.Join(d, "g1.txt"), "one\n")
	put(filepath.Join(d, "g2.txt"), "two\n")
	if inD(d, "-e", "-s", "+normal! iX", "+wq", "g1.txt", "g2.txt") == 0 {
		s.echo("  onearg       two file arguments were accepted")
		return harness.ErrReported
	}
	if !(catS(filepath.Join(d, "g1.txt")) == "one" && catS(filepath.Join(d, "g2.txt")) == "two") {
		s.echo("  onearg       a refused command line still wrote")
		return harness.ErrReported
	}
	put(filepath.Join(d, "n.txt"), "n1\n")
	if inD(d, "-e", "-s", "+next", "+q!", "n.txt") == 0 {
		s.echo("  onearg       :next was accepted")
		return harness.ErrReported
	}
	put(filepath.Join(d, "h1.txt"), "h1\n")
	put(filepath.Join(d, "h2.txt"), "h2\n")
	inD(d, "-e", "-s", "+e h2.txt", "+normal! iE", "+wq", "h1.txt")
	if !(catS(filepath.Join(d, "h1.txt")) == "h1" && catS(filepath.Join(d, "h2.txt")) == "Eh2") {
		s.echo("  onearg       :e broke: h1=%s h2=%s", catS(filepath.Join(d, "h1.txt")), catS(filepath.Join(d, "h2.txt")))
		return harness.ErrReported
	}
	s.echo("  onearg       the file loads and edits; a second argument and :next are refused; :e still opens")
	return nil
}

func Whim70(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim70", args)
	if err != nil {
		return err
	}
	if grepQ(s.fnBody(`^fname2fnum\(`), `\bbuflist_new\b`, gERE) {
		s.echo("  onebuffer    fname2fnum can still create a buffer")
		return harness.ErrReported
	}
	if n := grepC(s.src(), `\bfname2fnum\b`, gERE); n != 3 {
		s.echo("  onebuffer    fname2fnum has %d mentions, expected 3 (prototype, call, definition)", n)
		return harness.ErrReported
	}
	ecmd := s.fnBody(`^do_ecmd\(`)
	if grepQ(ecmd, `\bbuflist_new\b|\bbuflist_findnr\b`, gERE) {
		s.echo("  onebuffer    do_ecmd still reaches for another buffer")
		return harness.ErrReported
	}
	if grepQ(ecmd, `close_buffer\(curwin, curbuf, DOBUF_WIPE`, gERE) {
		s.echo("  onebuffer    do_ecmd still wipes the buffer it leaves")
		return harness.ErrReported
	}
	if !s.keptE("  onebuffer    ", " went too -- the one buffer still needs it", "buflist_new", "setfname", "open_buffer", "buf_freeall", "readfile", "do_ecmd") {
		return harness.ErrReported
	}
	s.echo("  onebuffer    :edit reuses the one buffer; nothing creates or wipes another")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	const p = "  onebuffer    "
	if !s.loads(d, p, "a\nb\nc\n", "a|b|LAST c|") || !s.switchesE(d, p, "h1.txt", "h2.txt", "h1\n", "h2\n", "Eh2", "+normal! iE") ||
		!s.edits(d, p, "e.txt", "one\ntwo\nthree\n", "one|three|") {
		return harness.ErrReported
	}
	r := probeFile(d, "r.txt", "keep\n", "+normal! iX", "+e!", "+wq")
	if catS(r) != "keep" {
		s.echo("  onebuffer    :e! did not reload: %s", catS(r))
		return harness.ErrReported
	}
	s.echo("  onebuffer    the file loads and edits; :e opens another; :e! reloads")
	return nil
}

// maps is the buffer-local and global mapping probes.
func (s *wsh) mapsLocal(d, prefix, content, want string) bool {
	m := probeFile(d, "m.txt", content, "+map <buffer> Q A!", "+normal Q", "+wq")
	if catS(m) != want {
		s.echo("%sa buffer-local mapping stopped working: %s", prefix, catS(m))
		return false
	}
	return true
}

func (s *wsh) mapsGlobal(d, prefix string) bool {
	g := probeFile(d, "g.txt", "y\n", "+map Z A?", "+normal Z", "+wq")
	if catS(g) != "y?" {
		s.echo("%sa global mapping stopped working: %s", prefix, catS(g))
		return false
	}
	return true
}

func Whim71(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim71", args)
	if err != nil {
		return err
	}
	const p = "  onebuf       "
	if !grepQ(s.src(), `^[ \t]*buffblock_T \*b_next;`, gERE) {
		s.echo("  onebuf       buffblock_T lost its b_next -- the redo buffer is gone")
		return harness.ErrReported
	}
	if !s.keptE(p, " went -- that was never the buffer list", "bh_first", "redobuff", "readbuf1", "readbuf2") {
		return harness.ErrReported
	}
	if !s.cnt0(p, "firstbuf", "lastbuf", "buf_reuse", "BLN_REUSE", "au_pending_free_buf") {
		return harness.ErrReported
	}
	if nums, ls := grepLines(s.src(), `\b(close_buffer|set_curbuf)\([^;]*DOBUF_WIPE_REUSE`, gERE); len(nums) > 0 {
		for i := range nums {
			s.echo("%d:%s", nums[i], ls[i])
		}
		s.echo("  onebuf       something still asks for a reusable wipe")
		return harness.ErrReported
	}
	if grepQ(awkRanges(s.src(), `^struct file_buffer$`, `^\};$`), `buf_T[ \t]+\*b_(next|prev);`, gERE) {
		s.echo("  onebuf       buf_T still links to another buffer")
		return harness.ErrReported
	}
	if !s.keptE(p, " went too -- the one buffer still needs it", "buflist_new", "buflist_add", "buflist_findnr", "buf_hashtab", "win_alloc_firstwin") {
		return harness.ErrReported
	}
	if !grepQ(s.src(), `for \(bp = curbuf; ; bp = NULL\)`, gERE) {
		s.echo("  onebuf       the mapping scan no longer runs its global pass")
		return harness.ErrReported
	}
	s.echo("  onebuf       one buffer, structurally; the redo chain and the free list untouched")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	if !s.loads(d, p, "a\nb\nc\n", "a|b|LAST c|") || !s.switchesE(d, p, "h1.txt", "h2.txt", "h1\n", "h2\n", "Eh2", "+normal! iE") ||
		!s.edits(d, p, "e.txt", "one\ntwo\nthree\n", "one|three|") || !s.mapsLocal(d, p, "x\n", "x!") || !s.mapsGlobal(d, p) {
		return harness.ErrReported
	}
	alt := probeFile(d, "alt.txt", "z\n", "+normal! A1", "+wq")
	if catS(alt) != "z1" {
		s.echo("  onebuf       editing after the alternate-file cut broke: %s", catS(alt))
		return harness.ErrReported
	}
	s.echo("  onebuf       loads, edits, :e switches, and both mapping passes still fire")
	return nil
}

func Whim72(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim72", args)
	if err != nil {
		return err
	}
	const p = "  onewin       "
	if !s.cnt0(p, "firstwin", "lastwin", "first_tabpage", "w_next", "w_prev", "tp_next", "tp_firstwin", "tp_lastwin",
		"leave_tabpage", "enter_tabpage", "use_tabpage", "valid_tabpage", "win_append", "win_init",
		"borrow_stl_vsep_hl") {
		return harness.ErrReported
	}
	if !s.keptE(p, " went -- the frame layer is not this phase", "topframe", "frame_T", "fr_next", "fr_child", "fr_parent", "new_frame", "win_comp_pos") {
		return harness.ErrReported
	}
	if !grepQ(s.src(), `\bb_nwindows\b`, gERE) {
		s.echo("  onewin       b_nwindows went -- buffer release depends on it")
		return harness.ErrReported
	}
	if !grepQ(s.src(), `buf->b_nwindows <= 0`, gERE) {
		s.echo("  onewin       the 'no longer displayed' test went")
		return harness.ErrReported
	}
	if !s.keptE(p, " went too -- the one window still needs it", "win_alloc", "win_alloc_firstwin", "alloc_tabpage", "curwin", "curtab") {
		return harness.ErrReported
	}
	s.echo("  onewin       one window and one tabpage; the frame layer and b_nwindows intact")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	if !s.loads(d, p, "a\nb\nc\n", "a|b|LAST c|") || !s.edits(d, p, "e.txt", "one\ntwo\nthree\n", "one|three|") ||
		!s.switchesE(d, p, "h1.txt", "h2.txt", "h1\n", "h2\n", "Eh2", "+normal! iE") || !s.mapsLocal(d, p, "x\n", "x!") || !s.mapsGlobal(d, p) {
		return harness.ErrReported
	}
	au := probeFile(d, "au.txt", "p1\np2\n", "+1", "+normal! A-au", "+wq")
	if bar(au) != "p1-au|p2|" {
		s.echo("  onewin       quitting through the rewritten BUFWINLEAVE block broke: '%s'", bar(au))
		return harness.ErrReported
	}
	sc := probeFile(d, "s.txt", "1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n", "+5", "+normal! O-ins", "+wq")
	if sedN(sc, 5) != "-ins" {
		s.echo("  onewin       inserting a line broke the scroll path: %s", sedN(sc, 5))
		return harness.ErrReported
	}
	r := probeFile(d, "r.txt", "r1\nr2\nr3\n", "+%s/^r/R/", "+wq")
	if bar(r) != "R1|R2|R3|" {
		s.echo("  onewin       a whole-buffer range broke: '%s'", bar(r))
		return harness.ErrReported
	}
	s.echo("  onewin       loads, edits, :e switches, mappings fire, autocommands reach the buffer")
	return nil
}

func Whim73(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim73", args)
	if err != nil {
		return err
	}
	const p = "  oneframe     "
	if !s.cnt0(p, "fr_parent", "fr_next", "fr_prev", "fr_child", "frame_fixed_height", "frame_fixed_width", "FR_ROW", "FR_COL") {
		return harness.ErrReported
	}
	if !s.keptE(p, " went -- the one frame still needs it", "frame_T", "topframe", "fr_width", "fr_height", "fr_win", "fr_layout", "FR_LEAF", "new_frame",
		"win_comp_pos", "frame_comp_pos", "frame_minheight", "win_new_height") {
		return harness.ErrReported
	}
	mh := s.fnBody(`^frame_minheight\(`)
	if !grepQ(mh, `\bp_wmh\b`, gERE) || !grepQ(mh, `\bp_wh\b`, gERE) {
		s.echo("  oneframe     frame_minheight lost its arithmetic")
		return harness.ErrReported
	}
	s.echo("  oneframe     one frame; its width, height and the minima kept")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	if !s.loads(d, p, "a\nb\nc\n", "a|b|LAST c|") || !s.edits(d, p, "e.txt", "one\ntwo\nthree\n", "one|three|") ||
		!s.switchesE(d, p, "h1.txt", "h2.txt", "h1\n", "h2\n", "Eh2", "+normal! iE") || !s.mapsLocal(d, p, "x\n", "x!") {
		return harness.ErrReported
	}
	sc := probeFile(d, "s.txt", "1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n", "+5", "+normal! O-ins", "+wq")
	if sedN(sc, 5) != "-ins" {
		s.echo("  oneframe     inserting a line broke the scroll path: %s", sedN(sc, 5))
		return harness.ErrReported
	}
	c := probeFile(d, "c.txt", "c1\nc2\n", "+set cmdheight=2", "+1", "+normal! A-ch", "+wq")
	if bar(c) != "c1-ch|c2|" {
		s.echo("  oneframe     :set cmdheight broke the layout: '%s'", bar(c))
		return harness.ErrReported
	}
	l := probeFile(d, "l.txt", "l1\nl2\n", "+set laststatus=2", "+1", "+normal! A-ls", "+wq")
	if bar(l) != "l1-ls|l2|" {
		s.echo("  oneframe     'laststatus' broke the layout: '%s'", bar(l))
		return harness.ErrReported
	}
	s.echo("  oneframe     loads, edits, :e switches, mappings fire, cmdheight and laststatus resize")
	return nil
}

func Whim74(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim74", args)
	if err != nil {
		return err
	}
	const p = "  nofmark      "
	if !s.cnt0(p, "namedfm", "xfmark_T", "EXTRA_MARKS", "fname2fnum", "fmarks_check_names", "fmarks_check_one", "fm_getname", "buflist_getfile") {
		return harness.ErrReported
	}
	if !grepQ(s.src(), `\bfmark_T\b`, gERE) {
		s.echo("  nofmark      fmark_T went -- the tag stack embeds it")
		return harness.ErrReported
	}
	if !grepQ(s.src(), `fmark_T[ \t]+fmark;`, gERE) {
		s.echo("  nofmark      struct taggy lost its fmark")
		return harness.ErrReported
	}
	if !s.keptE(p, " went -- that was never a file mark", "b_namedm", "b_last_cursor", "b_last_insert", "b_last_change", "b_op_start", "b_op_end",
		"w_pcmark", "w_prev_pcmark", "setpcmark", "getmark", "setmark", "setmark_pos", "check_mark",
		"clrallmarks", "mark_adjust_internal", "mark_col_adjust", "ex_marks", "ex_delmarks") {
		return harness.ErrReported
	}
	if !grepQ(s.src(), `do_join\(long[^)]*int[ \t]+setmark\)`, gERE) {
		s.echo("  nofmark      do_join lost its setmark parameter")
		return harness.ErrReported
	}
	s.echo("  nofmark      no file marks; lowercase, the special marks and the tag stack intact")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	if !s.loads(d, p, "a\nb\nc\n", "a|b|LAST c|") || !s.edits(d, p, "e.txt", "one\ntwo\nthree\n", "one|three|") {
		return harness.ErrReported
	}
	lo := probeFile(d, "lo.txt", "K1\nK2\nK3\n", "+normal! 2Gmb", "+normal! 3G", "+normal! 'bA-kept", "+wq")
	if bar(lo) != "K1|K2-kept|K3|" {
		s.echo("  nofmark      a lowercase mark stopped working: '%s'", bar(lo))
		return harness.ErrReported
	}
	up := probeFile(d, "up.txt", "U1\nU2\nU3\n", "+normal! 1GmA", "+normal! 3G", "+normal! 'AA-up", "+wq")
	if bar(up) != "U1|U2|U3|" {
		s.echo("  nofmark      an uppercase mark still works: '%s'", bar(up))
		return harness.ErrReported
	}
	bt := probeFile(d, "bt.txt", "B1\nB2\nB3\n", "+normal! 2Gmc", "+normal! 3G", "+normal! `cA-bt", "+wq")
	if bar(bt) != "B1|B2-bt|B3|" {
		s.echo("  nofmark      a backtick mark stopped working: '%s'", bar(bt))
		return harness.ErrReported
	}
	mk := probeFile(d, "mk.txt", "M1\n", "+normal! 1Gma", "+marks", "+normal! A-mk", "+wq")
	if catS(mk) != "M1-mk" {
		s.echo("  nofmark      :marks broke the session: %s", catS(mk))
		return harness.ErrReported
	}
	dm := probeFile(d, "dm.txt", "D1\n", "+normal! 1Gma", "+delmarks a", "+normal! A-dm", "+wq")
	if catS(dm) != "D1-dm" {
		s.echo("  nofmark      :delmarks broke the session: %s", catS(dm))
		return harness.ErrReported
	}
	s.echo("  nofmark      lowercase and backtick marks work; uppercase is unset; :marks and :delmarks run")
	return nil
}

func Whim75(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim75", args)
	if err != nil {
		return err
	}
	const p = "  noautocmd    "
	if !s.cnt0(p, "apply_autocmds", "apply_autocmds_exarg", "apply_autocmds_retval", "apply_autocmds_group",
		"aucmd_prepbuf", "aucmd_restbuf", "aco_save_T", "aubuflocal_remove", "au_cleanup",
		"au_remove_pat", "au_del_cmd", "event_nr2name", "auto_next_pat", "getnextac", "first_autopat",
		"last_autopat", "AutoPat", "AutoCmd", "AutoPatCmd_T", "active_apc_list", "au_need_clean",
		"is_autocmd_blocked",
		"has_cursormovedI", "has_textchangedI", "has_textchangedP", "trigger_cmd_autocmd",
		"ins_apply_autocmds", "event_tab", "EVENT_BUFENTER", "NUM_EVENTS") {
		return harness.ErrReported
	}
	if !s.keptE(p, " went -- it has callers that are not autocommand code", "block_autocmds", "unblock_autocmds") {
		return harness.ErrReported
	}
	if n := grepC(s.src(), `\bautocmd_blocked\b`, gERE); n != 3 {
		s.echo("  noautocmd    autocmd_blocked has %d mentions, expected 3 (declaration and the ++/-- pair)", n)
		return harness.ErrReported
	}
	if grepQ(s.src(), `\bis_autocmd_blocked\b`, gERE) {
		s.echo("  noautocmd    autocmd_blocked still has a reader")
		return harness.ErrReported
	}
	cb := s.fnBody(`^close_buffer\(`)
	if grepQ(cb, "aucmd_abort", gERE) {
		s.echo("  noautocmd    close_buffer still has an orphaned abort label")
		return harness.ErrReported
	}
	if !grepQ(cb, "e_autocommands_caused_command_to_abort", gERE) {
		s.echo("  noautocmd    close_buffer lost its abort_if_last arm")
		return harness.ErrReported
	}
	bw := s.fnBody(`^buf_write\(`)
	if !grepQ(bw, `\bbuf_ffname\b`, gERE) {
		s.echo("  noautocmd    buf_write lost buf_ffname -- :w on a renamed buffer would break")
		return harness.ErrReported
	}
	if !grepQ(bw, `\bbuf_fname_s\b`, gERE) {
		s.echo("  noautocmd    buf_write lost buf_fname_s")
		return harness.ErrReported
	}
	if !grepQ(s.fnBody(`^open_buffer\(`), `BF_CHECK_RO \| BF_NEVERLOADED`, gERE) {
		s.echo("  noautocmd    open_buffer lost its flag clearing")
		return harness.ErrReported
	}
	if !s.keptE(p, " went -- that was never the autocommand layer", "close_buffer", "buf_freeall", "buf_write", "readfile", "set_curbuf", "buflist_new", "open_buffer",
		"ins_redraw", "getout", "do_one_cmd", "set_termname", "u_save", "curbufIsChanged") {
		return harness.ErrReported
	}
	s.echo("  noautocmd    no autocommands; the work they were wrapped around is intact")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	if !s.loads(d, p, "a\nb\nc\n", "a|b|LAST c|") {
		return harness.ErrReported
	}
	wt := probeFile(d, "w.txt", "w1\nw2\n", "+1", "+normal! A-w", "+wq")
	if bar(wt) != "w1-w|w2|" {
		s.echo("  noautocmd    writing broke: '%s'", bar(wt))
		return harness.ErrReported
	}
	put(filepath.Join(d, "src.txt"), "x1\n")
	os.Remove(filepath.Join(d, "dst.txt"))
	inD(d, "-e", "-s", "+w dst.txt", "+q!", "src.txt")
	if catS(filepath.Join(d, "dst.txt")) != "x1" {
		s.echo("  noautocmd    :w to another name broke: %s", catS(filepath.Join(d, "dst.txt")))
		return harness.ErrReported
	}
	if !s.switchesE(d, p, "e1.txt", "e2.txt", "e1\n", "e2\n", "e2-E", "+normal! A-E") {
		return harness.ErrReported
	}
	for _, c := range []struct{ file, content, want, what string; args []string }{
		{"g.txt", "keep1\ndrop\nkeep2\n", "keep1|keep2|", ":g broke", []string{"+g/drop/d", "+wq"}},
		{"s.txt", "s1\ns2\n", "S1|S2|", ":s broke", []string{"+%s/^s/S/", "+wq"}},
		{"m.txt", "m1\nm2\nm3\n", "m2|m3|m1|", ":m broke", []string{"+1m$", "+wq"}},
		{"u.txt", "u1\nu2\n", "u1|u2|", "undo broke", []string{"+1", "+normal! dd", "+normal! u", "+wq"}},
	} {
		f := probeFile(d, c.file, c.content, c.args...)
		if bar(f) != c.want {
			s.echo("  noautocmd    %s: '%s'", c.what, bar(f))
			return harness.ErrReported
		}
	}
	i := probeFile(d, "i.txt", "i1\n", "+normal! A-ins", "+wq")
	if catS(i) != "i1-ins" {
		s.echo("  noautocmd    insert-mode editing broke: %s", catS(i))
		return harness.ErrReported
	}
	s.echo("  noautocmd    loads, writes, :w name, :e, :g, :s, :m, undo and insert all work")
	return nil
}

func Whim76(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim76", args)
	if err != nil {
		return err
	}
	const p = "  oneengine    "
	if !s.cnt0(p, "AUTOMATIC_ENGINE", "p_re", "nfa_regprog_T", "nfa_state_T", "nfa_regengine", "regexp_engine") {
		return harness.ErrReported
	}
	if !s.keptE(p, " went -- matching still needs it", "BACKTRACKING_ENGINE", "re_engine", "bt_regengine", "bt_regprog_T", "regprog_T", "regengine_T",
		"vim_regcomp", "vim_regfree", "vim_regexec_string", "vim_regexec_multi", "re_in_use", "re_flags") {
		return harness.ErrReported
	}
	if !grepQ(s.src(), `prog->re_engine = BACKTRACKING_ENGINE;`, gERE) {
		s.echo("  oneengine    the engine is no longer recorded on the program")
		return harness.ErrReported
	}
	s.echo("  oneengine    one engine, no retry; the matcher and its program types intact")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	if !s.loads(d, p, "a\nb\nc\n", "a|b|LAST c|") {
		return harness.ErrReported
	}
	for _, c := range []struct{ file, content, want, what string; args []string }{
		{"s.txt", "alpha\nbeta\ngamma\n", "XlphX|betX|gXmmX|", "a quantified match broke", []string{`+%s/a\+/X/g`, "+wq"}},
		{"d.txt", "one1\ntwo2\nthree3\n", "oneN|twoN|threeN|", ":g over a pattern broke", []string{"+g/[0-9]$/s/[0-9]$/N/", "+wq"}},
		{"r.txt", "foo\nbar\nfoobar\n", "foo|bar|barfoo|", "back-references broke", []string{`+%s/\(foo\)\(bar\)/\2\1/`, "+wq"}},
		{"c.txt", "aaa\nbbb\n", "Za|Zb|", "a counted group broke", []string{`+%s/\%(a\|b\)\{2}/Z/`, "+wq"}},
		{"n.txt", "x\ny\n", "x|y-found|", "search broke", []string{"+/y", "+normal! A-found", "+wq"}},
	} {
		f := probeFile(d, c.file, c.content, c.args...)
		if bar(f) != c.want {
			s.echo("  oneengine    %s: '%s'", c.what, bar(f))
			return harness.ErrReported
		}
	}
	s.echo("  oneengine    quantifiers, :g, back-references, counted groups and search all match")
	return nil
}

func Whim77(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim77", args)
	if err != nil {
		return err
	}
	const p = "  nobufpat     "
	if !s.cnt0(p, "buflist_findpat", "file_pat_to_reg_pat", "buflist_match") {
		return harness.ErrReported
	}
	if !grepQ(s.src(), `\bEX_BUFNAME\b`, gERE) {
		s.echo("  nobufpat     EX_BUFNAME went -- the rows and the count check still name it")
		return harness.ErrReported
	}
	if !grepQ(s.src(), `^[ \t]*ni = \(! \(\(int\)\(ea\.cmdidx\) < 0\)`, gERE) {
		s.echo("  nobufpat     do_one_cmd no longer computes ni")
		return harness.ErrReported
	}
	if n := grepC(s.src(), `!ni\b`, gERE); n < 7 {
		s.echo("  nobufpat     only %d checks still consult ni, expected at least 7", n)
		return harness.ErrReported
	}
	body := s.fnBody(`^do_one_cmd\(`)
	if !grepQ(body, `^doend:$`, gERE) {
		s.echo("  nobufpat     do_one_cmd lost its shared exit label")
		return harness.ErrReported
	}
	if g := grepC(body, `goto doend;`, gERE); g < 5 {
		s.echo("  nobufpat     only %d gotos target doend, expected many -- the label may have been orphaned", g)
		return harness.ErrReported
	}
	if !s.keptE(p, " went -- the Ex dispatcher still needs it", "do_one_cmd", "find_ex_command", "ex_ni", "cmdnames") {
		return harness.ErrReported
	}
	s.echo("  nobufpat     no buffer-name matching; ni, EX_BUFNAME and the doend label intact")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	if !s.loads(d, p, "a\nb\nc\n", "a|b|LAST c|") {
		return harness.ErrReported
	}
	wt := probeFile(d, "w.txt", "p1\np2\n", "+1", "+normal! A-w", "+wq")
	if bar(wt) != "p1-w|p2|" {
		s.echo("  nobufpat     writing broke: '%s'", bar(wt))
		return harness.ErrReported
	}
	if !s.switchesE(d, p, "e1.txt", "e2.txt", "e1\n", "e2\n", "e2-E", "+normal! A-E") {
		return harness.ErrReported
	}
	g := probeFile(d, "g.txt", "k1\ndrop\nk2\n", "+g/drop/d", "+wq")
	if bar(g) != "k1|k2|" {
		s.echo("  nobufpat     :g broke: '%s'", bar(g))
		return harness.ErrReported
	}
	z := probeFile(d, "z.txt", "z\n", "+buffer nosuchname", "+normal! A-ok", "+wq")
	if catS(z) != "z-ok" {
		s.echo("  nobufpat     :buffer with a name broke the session: %s", catS(z))
		return harness.ErrReported
	}
	s.echo("  nobufpat     loads, writes, :e names a file, :g takes a pattern, :buffer still refused")
	return nil
}

func Whim78(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim78", args)
	if err != nil {
		return err
	}
	const p = "  nostubs      "
	if !s.cnt0(p, "autocmd_blocked", "autocmd_no_enter", "autocmd_no_leave", "redrawing_for_callback",
		"prevwin", "last_win_id", "LOWEST_WIN_ID", "w_id", "winid", "prechar",
		"clear_chartabsize_arg", "may_trigger_modechanged", "may_trigger_win_scrolled_resized",
		"out_flush_check", "add_b0_fenc", "set_b0_dir_flag", "pum_may_redraw", "ml_setname",
		"ml_preserve", "trigger_undo_ftplugin", "set_init_lang_env",
		"set_init_default_printencoding", "set_init_3", "mch_new_shellsize", "mch_early_init") {
		return harness.ErrReported
	}
	if !grepQ(s.src(), `\btr_start\b`, gERE) {
		s.echo("  nostubs      tr_start went -- three {STATUS_GET, -1} initialisers supply it")
		return harness.ErrReported
	}
	if n := grepC(s.src(), `termrequest_T [a-z0-9_]+_status =  \{STATUS_GET, -1\} ;`, gERE); n != 3 {
		s.echo("  nostubs      the termrequest_T initialisers changed shape (%d, expected 3)", n)
		return harness.ErrReported
	}
	if !grepQ(s.src(), `\bnv_nop\b`, gERE) {
		s.echo("  nostubs      nv_nop went -- nv_cmd_idx[] is no longer a permutation")
		return harness.ErrReported
	}
	if !grepQ(s.src(), `\+\+breakcheck_count >= BREAKCHECK_SKIP`, gERE) {
		s.echo("  nostubs      breakcheck_count lost its reader")
		return harness.ErrReported
	}
	if !grepQ(s.src(), `\bvim_ignored\b`, gERE) {
		s.echo("  nostubs      vim_ignored went -- it is the deliberate return-value sink")
		return harness.ErrReported
	}
	if !s.keptE(p, " went -- it still has live callers", "block_autocmds", "unblock_autocmds", "init_incsearch_state", "win_enter_ext", "create_windows",
		"redraw_after_callback", "win_alloc", "getcmdline_int") {
		return harness.ErrReported
	}
	s.echo("  nostubs      no empty calls, no unread counters, no window id; nv_nop and the sinks intact")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	if !s.loads(d, p, "a\nb\nc\n", "a|b|LAST c|") {
		return harness.ErrReported
	}
	i := probeFile(d, "i.txt", "i1\n", "+normal! A-ins", "+wq")
	if catS(i) != "i1-ins" {
		s.echo("  nostubs      insert broke: %s", catS(i))
		return harness.ErrReported
	}
	for _, c := range []struct{ file, content, want, what string; args []string }{
		{"g.txt", "one1\ntwo2\n", "oneN|twoN|", ":g broke", []string{"+g/[0-9]$/s/[0-9]$/N/", "+wq"}},
		{"s.txt", "x\ny\n", "x|y-found|", "search broke", []string{"+/y", "+normal! A-found", "+wq"}},
		{"c.txt", "c1\nc2\n", "c1-ch|c2|", ":set cmdheight broke", []string{"+set cmdheight=2", "+1", "+normal! A-ch", "+wq"}},
	} {
		f := probeFile(d, c.file, c.content, c.args...)
		if bar(f) != c.want {
			s.echo("  nostubs      %s: '%s'", c.what, bar(f))
			return harness.ErrReported
		}
	}
	if !s.mapsLocal(d, p, "m1\n", "m1!") {
		return harness.ErrReported
	}
	s.echo("  nostubs      loads, inserts, :g, search, cmdheight and mappings all work")
	return nil
}

func Whim79(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim79", args)
	if err != nil {
		return err
	}
	const p = "  noconstfn    "
	if !s.cnt0(p, "in_vim9script", "tabline_height", "pum_visible", "current_win_nr", "current_tab_nr",
		"check_more", "only_one_window", "check_timestamps", "stl_connected", "pum_under_menu",
		"ins_compl_win_active", "ins_compl_lnum_in_range", "ins_compl_active",
		"has_cursormoved", "wc_use_keyname", "script_get", "pum_redraw_in_same_position",
		"has_textchanged", "has_insertcharpre", "get_cellwidth",
		"check_can_set_curbuf_forceit", "check_can_set_curbuf_disabled",
		"bt_terminal", "bt_quickfix", "bomb_size", "at_ins_compl_key", "append_arg_number",
		"skip_for_popup", "may_have_range", "need_check_timestamps") {
		return harness.ErrReported
	}
	nums, ls := grepLines(s.src(), `\bvim9script\b`, gERE)
	keep := gre(`^(// |    \[CMD_vim9script\] = )`, gERE)
	var stray []string
	for i := range nums {
		if !keep.MatchString(ls[i]) {
			stray = append(stray, fmt.Sprintf("%d:%s", nums[i], ls[i]))
		}
	}
	if len(stray) > 0 {
		s.echo("  noconstfn    the vim9script identifier survives outside the banners and the command row")
		skip := gre(`:(// |    \[CMD_vim9script\] = )`, gERE)
		for i := range nums {
			if l := fmt.Sprintf("%d:%s", nums[i], ls[i]); !skip.MatchString(l) {
				s.echo("%s", l)
			}
		}
		return harness.ErrReported
	}
	if !s.keptE(p, " went -- it returns a variable and must stay", "get_hislen", "is_maphash_valid", "get_search_pat", "get_text_locked_msg") {
		return harness.ErrReported
	}
	if n := grepC(s.src(), `^[ \t]*did_set_number_relativenumber, NULL,$`, gERE); n != 2 {
		s.echo("  noconstfn    the two did_set_number_relativenumber option rows are %d, expected 2", n)
		return harness.ErrReported
	}
	if !grepQ(s.src(), `\bdid_set_number_relativenumber\(optset_T`, gERE) {
		s.echo("  noconstfn    did_set_number_relativenumber lost its definition")
		return harness.ErrReported
	}
	if !s.keptE(p, " went -- :q and :wq still need it", "getout", "ex_quit", "ex_exit", "check_changed", "check_changed_any", "before_quit_autocmds",
		"not_exiting", "do_write", "curbufIsChanged") {
		return harness.ErrReported
	}
	for _, fn := range []string{"ex_quit", "ex_exit"} {
		body := s.fnBody(`^` + fn + `\(exarg_T`)
		if n := grepC(body, `getout\(0\);`, gERE); n != 1 {
			s.echo("  noconstfn    %s has %d getout(0) calls, expected 1", fn, n)
			return harness.ErrReported
		}
		if n := grepC(body, `not_exiting\(save_exiting\);`, gERE); n != 2 {
			s.echo("  noconstfn    %s has %d not_exiting calls, expected 2", fn, n)
			return harness.ErrReported
		}
	}
	s.echo("  noconstfn    28 constants folded, 4 variable-returning stubs intact, quit guards intact")
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, done := s.scratch()
	defer done()
	quit := func(file, add string, args ...string) (int, string) {
		f := filepath.Join(d, file)
		put(f, "a\nb\n")
		rc := inD(d, append(append([]string{"-e", "-s"}, args...), file)...)
		_ = add
		return rc, bar(f)
	}
	if rc, b := quit("q1.txt", "", "+q"); rc != 0 {
		s.echo("  noconstfn    :q on an unmodified file exited %d, expected 0", rc)
		return harness.ErrReported
	} else if b != "a|b|" {
		s.echo("  noconstfn    :q changed the file")
		return harness.ErrReported
	}
	if rc, b := quit("q2.txt", "", "+normal! A-mod", "+q"); rc != 1 {
		s.echo("  noconstfn    :q on a MODIFIED file exited %d, expected 1 -- it must refuse", rc)
		return harness.ErrReported
	} else if b != "a|b|" {
		s.echo("  noconstfn    :q wrote a modified file it should have refused")
		return harness.ErrReported
	}
	if rc, b := quit("q3.txt", "", "+normal! A-mod", "+q!"); rc != 0 {
		s.echo("  noconstfn    :q! exited %d, expected 0", rc)
		return harness.ErrReported
	} else if b != "a|b|" {
		s.echo("  noconstfn    :q! wrote the file")
		return harness.ErrReported
	}
	if rc, b := quit("q4.txt", "", "+1", "+normal! A-wq", "+wq"); rc != 0 {
		s.echo("  noconstfn    :wq exited %d, expected 0", rc)
		return harness.ErrReported
	} else if b != "a-wq|b|" {
		s.echo("  noconstfn    :wq did not write: '%s'", b)
		return harness.ErrReported
	}
	if rc, b := quit("q5.txt", "", "+1", "+normal! A-x", "+x"); rc != 0 {
		s.echo("  noconstfn    :x exited %d, expected 0", rc)
		return harness.ErrReported
	} else if b != "a-x|b|" {
		s.echo("  noconstfn    :x did not write: '%s'", b)
		return harness.ErrReported
	}
	s.echo("  noconstfn    :q refuses a modified file, :q! discards, :wq and :x write and exit")
	t := probeFile(d, "t.txt", "a\nb\nc\n", "+$", "+s/^/LAST /", "+wq")
	if bar(t) != "a|b|LAST c|" {
		s.echo("  noconstfn    a range and a substitution broke: '%s'", bar(t))
		return harness.ErrReported
	}
	g := probeFile(d, "g.txt", "k1\ndrop\nk2\n", "+g/drop/d", "+wq")
	if bar(g) != "k1|k2|" {
		s.echo("  noconstfn    :g broke: '%s'", bar(g))
		return harness.ErrReported
	}
	sw := probeFile(d, "sw.txt", "o1\n", "+set shiftwidth=8", "+normal! >>", "+wq")
	if catS(sw) != "        o1" {
		s.echo("  noconstfn    :set and >> broke: '%s'", catS(sw))
		return harness.ErrReported
	}
	for _, c := range []struct{ file, content, want, what string; args []string }{
		{"w.txt", "q1\nq2\n", "q1-e|q2|", "writing broke", []string{"+1", "+normal! A-e", "+wq"}},
		{"m.txt", "z1\nz2\n", "z1-mk|z2|", "marks broke", []string{"+1", "+normal! ma", "+2", "+normal! 'aA-mk", "+wq"}},
		{"u.txt", "r1\nr2\nr3\n", "r1|r2|r3|", "undo broke", []string{"+2", "+normal! dd", "+normal! u", "+wq"}},
	} {
		f := probeFile(d, c.file, c.content, c.args...)
		if bar(f) != c.want {
			s.echo("  noconstfn    %s: '%s'", c.what, bar(f))
			return harness.ErrReported
		}
	}
	s.echo("  noconstfn    ranges, :g, :set, writing, marks and undo all work")
	return nil
}

func Whim82(w io.Writer, args []string) error {
	s, err := newWsh(w, "whim82", args)
	if err != nil {
		return err
	}
	silent := func(p string) bool {
		out, err := exec.Command("gcc", "-fsyntax-only", "-O0", "-Wall", "-Wextra", "-Wno-unused-parameter", p).CombinedOutput()
		return err == nil && len(out) == 0
	}
	var total int
	fmt.Sscan(readFile(filepath.Join(s.state, "total")), &total)
	keep := len(lines(readFile(filepath.Join(s.state, "keep"))))
	left := grepC(s.src(), `^#include <`, gERE)
	if left != total-keep {
		s.echo("  includes     %d includes left, expected %d", left, total-keep)
		return harness.ErrReported
	}
	if !silent(s.f) {
		s.echo("  includes     the result does not compile silently")
		return harness.ErrReported
	}
	if err := s.phasecheck(); err != nil {
		return err
	}
	if err := s.phasebuild(); err != nil {
		return err
	}
	d, _ := os.MkdirTemp("", "whim82")
	defer os.RemoveAll(d)
	build := func(sub, src string) error {
		dir := filepath.Join(d, sub)
		os.MkdirAll(dir, 0o755)
		put(filepath.Join(dir, "whim-vim.c"), readFile(src))
		c := exec.Command("gcc", "-O0", "-static", "-s", "-o", "vim", "whim-vim.c")
		c.Dir, c.Env = dir, envWith("SOURCE_DATE_EPOCH=0")
		return c.Run()
	}
	if build("old", filepath.Join(s.state, "old", "whim-vim.c")) != nil || build("new", s.f) != nil {
		return harness.ErrReported
	}
	ob, nb := readFile(filepath.Join(d, "old", "vim")), readFile(filepath.Join(d, "new", "vim"))
	if ob != nb {
		s.echo("  includes     the binary changed -- a header was doing more than declaring")
		return harness.ErrReported
	}
	s.echo("  includes     %d includes left; the binary is byte-identical (%d bytes)", left, len(nb))
	return nil
}
