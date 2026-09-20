package edit

import (
	"io"
	"regexp"
	"sort"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

func init() { register("zero10", Zero10) }

// z10Fields are the three the whole phase is about, and they are NULL for ever
// once part B has run.
var z10Fields = []string{"b_ffname", "b_sfname", "b_fname"}

var z10Before = map[string]int{
	"b_ffname": 32, "b_sfname": 26, "b_fname": 29,
	"CMD_file": 4, "EX_XFILE": 4, "buflist_new": 3, "buflist_name_nr": 3,
	"buf_spname": 7, "buf_get_fname": 3, "fileinfo": 4, "check_fname": 3,
	"readonlymode": 3, "mch_dirname": 5, "shorten_buf_fname": 2,
	"check_changed": 4, "no_write_message": 3,
	"p_ur": 2, "p_ro": 2, "read_cmd_fd": 12, "vim_fsync": 3,
	"scriptin": 8, "redir_fd": 6,
}

var z10After = map[string]int{
	"CMD_file": 0, "EX_XFILE": 1, "buflist_name_nr": 1, "readonlymode": 0,
	"shorten_buf_fname": 1, "check_fname": 3, "buf_get_fname": 3,
	"check_changed": 4, "no_write_message": 3, "p_ur": 2, "p_ro": 2,
	"read_cmd_fd": 12, "vim_fsync": 3, "scriptin": 8, "redir_fd": 6,
}

// z10Writers are the four functions every write to the three fields lives in,
// and z10Readers the five every surviving mention lives in.  Both are computed
// against, not asserted about: a write anywhere else means every fold is a guess.
var z10Writers = []string{"buflist_new", "setfname", "rename_buffer", "shorten_buf_fname"}
var z10Readers = []string{"setfname", "rename_buffer", "otherfile_buf", "buf_setino",
	"eval_vars", "buflist_name_nr"}

var (
	z10CmdRow  = regexp.MustCompile(`(?m)^    \[CMD_file\] = \{.*\n`)
	z10AnyRow  = regexp.MustCompile(`(?m)^    \[CMD_\w+\] = \{.*$`)
	z10ElseTop = regexp.MustCompile(`^[ \t]*else[ \t]*\n[ \t]*\{`)
)

// Zero10 takes the buffer's NAME: `:file`, buflist_new()'s two name parameters,
// sixteen folds of b_ffname/b_sfname/b_fname and three further folds that free
// the last three questions the core asked the filesystem.
func Zero10(text []byte, w io.Writer) ([]byte, error) {
	p := ph{"noname", w}
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
	within := func(t []byte, fn, old, new, what string, n int) ([]byte, error) {
		out, err := inFunction(t, fn, func(s []byte) ([]byte, error) {
			k := strings.Count(string(s), old)
			if k != n {
				return nil, p.die("%s -- %s occurs %d times in %s, expected %d",
					what, cutil.PyRepr(zHead(old, 60)), k, fn, n)
			}
			return []byte(strings.ReplaceAll(string(s), old, new)), nil
		})
		if err != nil {
			return nil, err
		}
		p.say(what)
		return out, nil
	}
	// fold is SCOPED TO ONE DEFINITION, and file-wide would be wrong here rather
	// than merely loose: `if (buf->b_ffname == NULL)` is the whole of
	// close_buffer's fold and the head of set_b0_fname's, written identically at
	// the same indent, so a file-wide count of 1 fails and a count of 2 would
	// fold two different shapes with one rule.
	fold := func(t []byte, fn, how, pattern, what string, n int) ([]byte, error) {
		out, err := inFunction(t, fn, func(s []byte) ([]byte, error) {
			var f func([]byte, string, int) ([]byte, error)
			switch how {
			case "always":
				f = cutil.FoldAlways
			case "never":
				f = cutil.FoldNever
			default:
				f = cutil.DropIf
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
	// foldAlwaysElse keeps A of `if (TRUE) { A } else { B }` inside fn.
	// cutil.FoldAlways refuses a block with an else, deliberately, and this is
	// the shape three sites here have.  The body is dedented four columns.
	foldAlwaysElse := func(t []byte, fn, ifline, what string) ([]byte, error) {
		out, err := inFunction(t, fn, func(sb []byte) ([]byte, error) {
			s := string(sb)
			if k := strings.Count(s, ifline); k != 1 {
				return nil, p.die("%s -- the if line occurs %d times in %s, expected 1", what, k, fn)
			}
			b := cutil.Blank(sb)
			i := strings.Index(s, ifline)
			o := strings.Index(string(b[i+len(ifline)-1:]), "{") + i + len(ifline) - 1
			c := cutil.Match(b, o)
			if c < 0 {
				return nil, p.die("%s -- unbalanced block", what)
			}
			endIf := strings.Index(s[c:], "\n") + c + 1
			m := z10ElseTop.FindStringIndex(s[endIf:])
			if m == nil {
				return nil, p.die("%s -- the block has no else, so cutil.fold_always is the tool", what)
			}
			o2 := endIf + m[1] - 1
			c2 := cutil.Match(b, o2)
			if c2 < 0 {
				return nil, p.die("%s -- unbalanced else block", what)
			}
			body := s[strings.Index(s[o:], "\n")+o+1 : strings.LastIndex(s[:c], "\n")+1]
			for _, l := range z5Lines(body) {
				if !strings.HasPrefix(l, "    ") && strings.TrimSpace(l) != "" {
					return nil, p.die("%s -- the if body is not written one level in, and dedenting it "+
						"would move code to a column it was never at", what)
				}
			}
			var out strings.Builder
			for _, l := range z5Lines(body) {
				if strings.HasPrefix(l, "    ") {
					out.WriteString(l[4:])
				} else {
					out.WriteString(l)
				}
			}
			return []byte(s[:i] + out.String() + s[strings.Index(s[c2:], "\n")+c2+1:]), nil
		})
		if err != nil {
			return nil, err
		}
		p.say(what)
		return out, nil
	}
	// assignments is every write to a field: `x->name =`, and `(x->name) =` as
	// slim spells it.  uses is every mention through `->`, so not its declaration.
	assignments := func(t []byte, name string) []int {
		var out []int
		for _, m := range regexp.MustCompile(`\b`+name+`\b\s*\)?\s*=[^=]`).FindAllIndex(t, -1) {
			out = append(out, m[0])
		}
		return out
	}
	uses := func(t []byte, name string) []int {
		var out []int
		for _, m := range regexp.MustCompile(`->\s*`+name+`\b`).FindAllIndex(t, -1) {
			out = append(out, m[0])
		}
		return out
	}
	functionsHolding := func(t []byte, offsets []int, names []string) ([]string, error) {
		type sp struct {
			a, z int
			name string
		}
		var spans []sp
		b := cutil.Blank(t)
		for _, n := range names {
			if a, z, ok := cutil.FindDefinition(t, b, n); ok {
				spans = append(spans, sp{a, z, n})
			}
		}
		seen := map[string]bool{}
		for _, off := range offsets {
			hit := false
			for _, s := range spans {
				if s.a <= off && off < s.z {
					seen[s.name] = true
					hit = true
					break
				}
			}
			if !hit {
				sorted := append([]string{}, names...)
				sort.Strings(sorted)
				return nil, p.die("a mention at line %d is in none of %s -- this phase was counted "+
					"against a different file",
					strings.Count(string(t[:off]), "\n")+1, strings.Join(sorted, " "))
			}
		}
		out := make([]string, 0, len(seen))
		for n := range seen {
			out = append(out, n)
		}
		sort.Strings(out)
		return out, nil
	}

	// ---- 0. the shape every anchor below was counted against ------------------
	for _, name := range sortedKeys(z10Before) {
		if k := mentions(text, name); k != z10Before[name] {
			return nil, p.die("%s has %d mentions, expected %d -- the anchors below were counted "+
				"against a different file", name, k, z10Before[name])
		}
	}
	p.say("b_ffname 32, b_sfname 26, b_fname 29, CMD_file 4, EX_XFILE 4 -- the file the " +
		"seven parts were counted against")

	var offs []int
	for _, fld := range z10Fields {
		offs = append(offs, assignments(text, fld)...)
	}
	got, err := functionsHolding(text, offs, z10Writers)
	if err != nil {
		return nil, err
	}
	want := append([]string{}, z10Writers...)
	sort.Strings(want)
	if strings.Join(got, " ") != strings.Join(want, " ") {
		return nil, p.die("the writes to %s live in %s, expected exactly %s",
			strings.Join(z10Fields, "/"), strings.Join(got, " "), strings.Join(want, " "))
	}
	p.sayf("%d writes to b_ffname, b_sfname and b_fname, and every one is in buflist_new, "+
		"setfname, rename_buffer or shorten_buf_fname -- the four this phase accounts "+
		"for.  That, and nothing weaker, is why every fold below may take a constant", len(offs))

	// ---- A. :file goes --------------------------------------------------------
	if text, err = textEdit(text, z10lit3, "", "the CMD_file enumerator of enum CMD_index", 1); err != nil {
		return nil, err
	}
	rows := z10CmdRow.FindAllString(string(text), -1)
	if len(rows) != 1 {
		return nil, p.die("the cmdnames[] row for :file matches %d lines, expected 1", len(rows))
	}
	text = []byte(strings.ReplaceAll(string(text), rows[0], ""))
	p.say("the cmdnames[] row [CMD_file] = {...}, one physical line: ex_file has no other " +
		"reference, and rename_buffer and setfname no other caller")
	if text, err = textEdit(text, z10lit4, z10lit5,
		"do_one_cmd's curbuf_locked() exemption: `ea.cmdidx != CMD_file` is "+
			"TRUE for ever, and phase 8 kept it saying this phase would take it", 1); err != nil {
		return nil, err
	}
	if text, err = textEdit(text, z10lit6, "",
		"do_one_cmd's second CMD_file test, deleted as text rather than "+
			"folded: its condition names the enumerator that is going", 1); err != nil {
		return nil, err
	}
	if k := mentions(text, "CMD_file"); k != 0 {
		return nil, p.die("CMD_file still has %d mentions", k)
	}

	// ---- B. buflist_new never names -------------------------------------------
	for _, e := range []struct{ old, new, what string }{
		{z10lit7, z10lit8, "buflist_new's prototype loses both name parameters"},
		{z10lit9, z10lit10, "and so does its definition"},
	} {
		if text, err = textEdit(text, e.old, e.new, e.what, 1); err != nil {
			return nil, err
		}
	}
	for _, e := range []struct{ old, new, what string }{
		{z10lit11, z10lit12, "the two locals the parameters fed, and the stat_T nothing fills now"},
		{z10lit13, "", "the prologue and the lookup: fname_expand() on two NULLs, a stat() the " +
			"`sfname == NULL` disjunct already short-circuited, and the search for " +
			"an existing buffer of the same name, whose guard `ffname != NULL` is " +
			"FALSE -- no buffer can be found by a name that is not given"},
		{z10lit14, z10lit15, "the alloc failure arm's vim_free(ffname): there is no ffname to free"},
		{z10lit16, "", "the assignment that named the buffer -- `ffname != NULL` is FALSE, and " +
			"this is the statement the whole phase is about"},
		{z10lit17, z10lit18, "the failure arm: its first disjunct is FALSE, so only the wininfo " +
			"allocation can fail, and the two names it freed are not there to free"},
		{z10lit19, "", "b_fname = b_sfname, which is NULL = NULL"},
		{z10lit20, z10lit21, "the device block: `st.st_dev` was set to -1 by the prologue that has " +
			"gone, so the TRUE arm is the one that ran and b_dev_valid is false"},
	} {
		if text, err = within(text, "buflist_new", e.old, e.new, e.what, 1); err != nil {
			return nil, err
		}
	}
	if text, err = textEdit(text, z10lit22, z10lit23,
		"the one call site, create_windows', which already passed NULL, NULL", 1); err != nil {
		return nil, err
	}
	a, z, ok := cutil.FindDefinition(text, cutil.Blank(text), "buflist_new")
	if !ok {
		return nil, p.die("buflist_new is not defined")
	}
	for _, gone := range []string{"ffname", "sfname", "st"} {
		if mentions(text[a:z], gone) > 0 {
			return nil, p.die("%s is still named inside buflist_new", gone)
		}
	}
	p.say("buflist_new names nothing: ffname, sfname and st are gone from it")

	// ---- C. the sixteen folds, with the constant each takes -------------------
	if text, err = fold(text, "open_buffer", "never",
		`(?m)^    if \(readonlymode && curbuf->b_ffname != NULL && \(curbuf->b_flags & BF_NEVERLOADED\)\)$`,
		"open_buffer: `b_ffname != NULL` is FALSE, so a buffer can never be made "+
			"read-only for being a never-loaded file -- and this was readonlymode's "+
			"only reader", 1); err != nil {
		return nil, err
	}
	if text, err = textEdit(text, z10lit24, z10lit25,
		"can_unload_buffer: `fname` is NULL either way, so E937 names the "+
			"buffer \"[No Name]\" -- which is what it printed before", 1); err != nil {
		return nil, err
	}
	if text, err = fold(text, "close_buffer", "always", `(?m)^    if \(buf->b_ffname == NULL\)$`,
		"close_buffer: `b_ffname == NULL` is TRUE, so an unloaded buffer is always "+
			"deleted rather than kept for its name", 1); err != nil {
		return nil, err
	}
	if text, err = textEdit(text, "curbuf != NULL && curbuf->b_ffname == NULL && curbuf->b_nwindows <= 1",
		"curbuf != NULL && curbuf->b_nwindows <= 1",
		"curbuf_reusable: `b_ffname == NULL` is TRUE, so the conjunct goes "+
			"rather than being kept with a fixed answer", 1); err != nil {
		return nil, err
	}
	if text, err = textEdit(text, z10lit26, z10lit27,
		"getaltfname: buflist_name_nr() is FAIL ALWAYS, so the alternate file "+
			"is E23 and NULL -- which is what the `#` register already answered", 1); err != nil {
		return nil, err
	}
	if text, err = foldAlwaysElse(text, "fileinfo", z10lit28,
		"fileinfo: buf_spname() never returns NULL now, so CTRL-G "+
			"prints the special name and never a path -- the else arm, "+
			"which read b_fname and b_ffname, cannot be entered"); err != nil {
		return nil, err
	}
	for _, e := range []struct{ old, new, what string }{
		{z10lit29, z10lit30, "buf_spname: `b_fname == NULL` is TRUE, so it answers for every " +
			"buffer and can no longer return NULL"},
		{z10lit31, z10lit32, "buf_get_fname: the same, and \"[No Name]\" is now the only name the " +
			"editor has for a buffer"},
		{z10lit33, z10lit34, "check_changed_any: buf_spname() is non-NULL, so E162 names the " +
			"buffer through it and never through b_fname"},
		{z10lit35, z10lit36, "check_fname: E32 for every buffer, and it stays because the `%` " +
			"register still asks it"},
	} {
		if text, err = textEdit(text, e.old, e.new, e.what, 1); err != nil {
			return nil, err
		}
	}
	if text, err = fold(text, "shorten_buf_fname", "never",
		`(?m)^    if \(buf->b_fname != NULL && !path_with_url\(buf->b_fname\) && \(force \|\| buf->b_sfname == NULL \|\| mch_isFullName\(buf->b_sfname\)\)\)$`,
		"shorten_buf_fname: `b_fname != NULL` is FALSE, so there is no path to "+
			"shorten and the function has nothing left to do", 1); err != nil {
		return nil, err
	}
	if text, err = textEdit(text, z10lit37, z10lit38,
		"file_name_at_cursor: `curbuf->b_ffname` is the NULL it passes now", 1); err != nil {
		return nil, err
	}
	if text, err = foldAlwaysElse(text, "set_b0_fname", z10lit39,
		"set_b0_fname: `b_ffname == NULL` is TRUE, so block zero's "+
			"file name is empty -- and the stat() in the arm that goes is "+
			"one of the two this phase takes"); err != nil {
		return nil, err
	}
	if text, err = textEdit(text, z10lit40, z10lit41,
		"get_spec_reg: the `%` register is `b_fname`, which is NULL -- the "+
			"register already yielded nothing, and check_fname() above it still "+
			"says E32", 1); err != nil {
		return nil, err
	}
	if text, err = fold(text, "ex_display", "never",
		`(?m)^    if \(curbuf->b_fname != NULL && \(arg == NULL \|\| vim_strchr\(arg, '%'\) != NULL\) && !got_int && !message_filtered\(curbuf->b_fname\)\)$`,
		"ex_display: the `\"%` line of :registers needs a buffer name and there is "+
			"none -- it was already never printed", 1); err != nil {
		return nil, err
	}
	if text, err = fold(text, "ex_display", "drop",
		`(?m)^    if \(\(arg == NULL \|\| vim_strchr\(arg, '#'\) != NULL\) && !got_int\)$`,
		"ex_display: and the `\"#` block goes whole, because buflist_name_nr() "+
			"inside it is FAIL ALWAYS and the block holds nothing else -- which is "+
			"what makes that function uncalled and the sweep's", 1); err != nil {
		return nil, err
	}
	if text, err = foldAlwaysElse(text, "get_trans_bufname", z10lit42,
		"get_trans_bufname: buf_spname() is non-NULL, so every window "+
			"and every :ls row reads \"[No Name]\" -- as they already did"); err != nil {
		return nil, err
	}
	if k := mentions(text, "buflist_name_nr"); k != 1 {
		return nil, p.die("buflist_name_nr has %d mentions after both callers were folded, expected "+
			"1 -- its definition, for the sweep", k)
	}

	// ---- D. EX_XFILE reaches zero rows ----------------------------------------
	var left []string
	for _, r := range z10AnyRow.FindAllString(string(text), -1) {
		if strings.Contains(r, "EX_XFILE") {
			left = append(left, r)
		}
	}
	if len(left) > 0 {
		return nil, p.die("%d cmdnames[] rows still carry EX_XFILE, so the fold below would be a "+
			"guess: %s", len(left), zHead(left[0], 60))
	}
	p.say("no cmdnames[] row carries EX_XFILE any more -- :file was the last, as :read " +
		"was EX_ARGOPT's in phase 7 and the :edit family in phase 8")
	if text, err = fold(text, "do_one_cmd", "never",
		`(?m)^    if \(\(ea\.argt & EX_XFILE\) && expand_filename\(&ea, cmdlinep, &errormsg\) == FAIL\)$`,
		"do_one_cmd's expand_filename() call: `ea.argt & EX_XFILE` is 0 for every "+
			"command, so this is the anchor the sweep reads the whole "+
			"filename-expansion layer from", 1); err != nil {
		return nil, err
	}
	if text, err = textEdit(text, z10lit43, z10lit44,
		"separate_nextcmd's CTRL-V test: the EX_XFILE disjunct is 0 for every "+
			"row, and dropping it is what takes the enumerator to zero mentions", 1); err != nil {
		return nil, err
	}
	if k := mentions(text, "EX_XFILE"); k != 1 {
		return nil, p.die("EX_XFILE has %d mentions, expected 1 -- its own definition, for the sweep", k)
	}

	// ---- E. the two write-only leftovers --------------------------------------
	if text, err = fold(text, "did_set_readonly", "drop",
		`(?m)^    if \(!curbuf->b_p_ro && \(args->os_flags & OPT_LOCAL\) == 0\)$`,
		"did_set_readonly's readonlymode write, with the `if` around it: C1 took "+
			"the only reader, and an `if` with an empty body is not something any tool "+
			"here removes", 1); err != nil {
		return nil, err
	}
	if text, err = textEdit(text, z10lit45, "",
		"and the definition of readonlymode, which phase 8 asserted at 5 "+
			"mentions and phase 9 at 3", 1); err != nil {
		return nil, err
	}
	if text, err = within(text, "buflist_new", z10lit21, "",
		"b_dev_valid's one surviving assignment, which part B left: every reader "+
			"is inside a function the sweep takes, and deadfields.py cannot remove a "+
			"field that is still written", 1); err != nil {
		return nil, err
	}

	// ---- F. shorten_fnames stops asking where it is ---------------------------
	if text, err = within(text, "shorten_fnames", z10lit46, "",
		"shorten_fnames: the cwd, and the call to a function with an empty body", 1); err != nil {
		return nil, err
	}
	for _, e := range []struct{ old, new, what string }{
		{z10lit47, z10lit48, "and its prototype takes void, because an unused PARAMETER is what " +
			"tools/sweep.sh's -Wno-unused-parameter cannot see -- phase 9's " +
			"anchor 4 measured that"},
		{z10lit49, z10lit50, "the definition with it"},
		{z10lit51, z10lit52, "and its one call site"},
	} {
		if text, err = textEdit(text, e.old, e.new, e.what, 1); err != nil {
			return nil, err
		}
	}

	// ---- G. nothing looks a name up on a disk ---------------------------------
	if text, err = fold(text, "find_file_name_in_path", "never", `(?m)^    if \(options & FNAME_EXP\)$`,
		"find_file_name_in_path: the `path` search arm goes, so CTRL-F and CTRL-P "+
			"both extract the word under the cursor and neither consults a disk -- "+
			"this is the fold that frees stat()", 1); err != nil {
		return nil, err
	}

	// ---- what the sweep is handed, as a count rather than as trust ------------
	offs = nil
	writes := 0
	for _, fld := range z10Fields {
		offs = append(offs, uses(text, fld)...)
		writes += len(assignments(text, fld))
	}
	got, err = functionsHolding(text, offs, z10Readers)
	if err != nil {
		return nil, err
	}
	want = append([]string{}, z10Readers...)
	sort.Strings(want)
	if strings.Join(got, " ") != strings.Join(want, " ") {
		return nil, p.die("the surviving mentions of the three fields are in %s, expected exactly %s",
			strings.Join(got, " "), strings.Join(want, " "))
	}
	p.sayf("%d mentions of b_ffname, b_sfname and b_fname are left, %d of them writes, and "+
		"every one is inside setfname, rename_buffer, otherfile_buf, buf_setino, "+
		"eval_vars or buflist_name_nr -- none of which has a caller the sweep can "+
		"reach", len(offs), writes)

	for _, name := range sortedKeys(z10After) {
		if k := mentions(text, name); k != z10After[name] {
			return nil, p.die("%s has %d mentions after the cut, expected %d", name, k, z10After[name])
		}
	}
	p.say("the cut is done: CMD_file 0, EX_XFILE 1 (its own definition), buflist_name_nr " +
		"1, readonlymode 0 -- and read_cmd_fd 12, vim_fsync 3, scriptin 8 and redir_fd " +
		"6 untouched, each of them a later phase's")
	return text, nil
}
