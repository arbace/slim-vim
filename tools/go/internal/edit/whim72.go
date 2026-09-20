package edit

import (
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

// THE ONE PATTERN BACKREFERENCE IN ANY EDIT PART, and RE2 has none.
//
// The Python matches a walk with `(?P<v>\w+)` and then requires the SAME name
// at every later position with `(?P=v)`, so a `for` whose variables disagree
// simply does not match.  Go cannot say that, so each position is captured
// SEPARATELY and the equality is asserted afterwards -- the route the Go session
// measured on q71, where NESTED, TABS and WINS give 15, 17 and 23 either way.
//
// The measurement that makes that mean something is the CONTROL, not the
// agreement: on the real tree the equality rejects NOTHING, because every raw
// match already has equal groups, so agreeing shows only that the rewrite loses
// no match.  A synthetic header with mismatched variables is what shows it
// discriminates -- backref finds 0, raw RE2 finds 1, capture-and-compare finds 0.
const (
	nestedWalk = `for \(\((\w+)\) = \(\((\w+)\) == (?:NULL \|\| \((\w+)\) == )?curtab\) *\? firstwin : \((\w+)\)->tp_firstwin; \((\w+)\); \((\w+)\) = \((\w+)\)->w_next\)`
	tabsWalk   = `for \(\((\w+)\) = first_tabpage; \((\w+)\) != NULL; \((\w+)\) = \((\w+)\)->tp_next\)`
	winsWalk   = `for \(\((\w+)\) = firstwin; \((\w+)\) != NULL; \((\w+)\) = \((\w+)\)->w_next\)`
)

// allEqual says whether every named index holds the same non-empty text.  An
// EMPTY capture is skipped rather than failed: NESTED's third group is inside
// `(?:...)?` and is absent when that alternative did not run.
func allEqual(g []string, idx ...int) bool {
	var want string
	for _, i := range idx {
		if i >= len(g) || g[i] == "" {
			continue
		}
		if want == "" {
			want = g[i]
		} else if g[i] != want {
			return false
		}
	}
	return want != ""
}

// foldWalks folds every walk of one shape, back to front so the offsets still to
// be processed stay valid, refusing if any body's break or continue would rebind
// to the loop being removed.
func (e *E) foldWalks(headRe string, ok func([]string) bool, subst func([]string) string, what string) {
	if e.err != nil {
		return
	}
	pat := regexp.MustCompile(`(?m)^([ \t]*)` + headRe + `[ \t]*\n[ \t]*\{\n`)
	var ms [][]int
	for _, m := range pat.FindAllSubmatchIndex(e.text, -1) {
		g := make([]string, len(m)/2)
		for i := range g {
			if m[2*i] >= 0 {
				g[i] = string(e.text[m[2*i]:m[2*i+1]])
			}
		}
		if ok(g) {
			ms = append(ms, m)
		}
	}
	if len(ms) == 0 {
		e.die("%s -- no walk of this shape is left to fold", what)
		return
	}
	var unsafe []int
	total := len(ms)
	for i := len(ms) - 1; i >= 0; i-- {
		m := ms[i]
		b := cutil.Blank(e.text)
		o := indexFrom(e.text, []byte("{"), m[0])
		c := cutil.Match(b, o)
		if c < 0 {
			e.die("%s -- unbalanced block", what)
			return
		}
		raw := e.text[indexFrom(e.text, []byte("\n"), o)+1 : lastNewlineBefore(e.text, c)+1]
		if bindsToWalk(raw) != "" {
			unsafe = append(unsafe, 1+countNewlines(e.text[:m[0]]))
			continue
		}
		g := make([]string, len(m)/2)
		for k := range g {
			if m[2*k] >= 0 {
				g[k] = string(e.text[m[2*k]:m[2*k+1]])
			}
		}
		body := cutil.Dedent4(raw)
		end := indexFrom(e.text, []byte("\n"), c) + 1
		out := append([]byte{}, e.text[:m[0]]...)
		out = append(out, e.text[m[2]:m[3]]...)
		out = append(out, (subst(g) + "\n")...)
		out = append(out, body...)
		e.text = append(out, e.text[end:]...)
	}
	if len(unsafe) > 0 {
		e.die("%s -- %d walk(s) still carry an escaping break/continue and need an explicit rewrite: lines %s",
			what, len(unsafe), joinInts(unsafe))
		return
	}
	e.say(fmt.Sprintf("%s (%d)", what, total))
}

func countNewlines(b []byte) int {
	n := 0
	for _, c := range b {
		if c == '\n' {
			n++
		}
	}
	return n
}

func joinInts(v []int) string {
	// sorted ascending, as the Python prints them
	for i := 0; i < len(v); i++ {
		for j := i + 1; j < len(v); j++ {
			if v[j] < v[i] {
				v[i], v[j] = v[j], v[i]
			}
		}
	}
	out := ""
	for i, n := range v {
		if i > 0 {
			out += " "
		}
		out += fmt.Sprint(n)
	}
	return out
}

// replaceBlock replaces a brace-matched block, anchored on the line that opens it.
func (e *E) replaceBlock(fn, anchorRe, repl, what string) {
	e.InFunction(fn, func(e *E) {
		if e.Failed() {
			return
		}
		m := regexp.MustCompile(anchorRe).FindIndex(e.text)
		if m == nil {
			e.die("%s -- no line matches %s", what, cutil.PyRepr(anchorRe))
			return
		}
		k := lastNewlineBefore(e.text, m[0]) + 1
		b := cutil.Blank(e.text)
		o := indexFrom(e.text, []byte("{"), m[0])
		c := cutil.Match(b, o)
		if c < 0 {
			e.die("%s -- unbalanced block", what)
			return
		}
		out := append([]byte{}, e.text[:k]...)
		out = append(out, repl...)
		e.text = append(out, e.text[indexFrom(e.text, []byte("\n"), c)+1:]...)
	})
	if !e.Failed() {
		e.say(what)
	}
}

// foldNeverIn folds inside one function and reports after, which is this
// phase's own shape -- the say() is outside in_function.
func (e *E) foldNeverIn(fn, pattern, what string, n int) {
	e.InFunction(fn, func(e *E) {
		if e.Failed() {
			return
		}
		out, err := cutil.FoldNever(e.text, pattern, n)
		if err != nil {
			e.die("%s -- %v", what, err)
			return
		}
		e.text = out
	})
	if !e.Failed() {
		e.say(what)
	}
}

// dropWalkIn is whim71's dropWalk with the report after in_function.
func (e *E) dropWalkIn(fn, headRe, repl, what string, n int) {
	e.InFunction(fn, func(e *E) {
		if e.Failed() {
			return
		}
		pat := regexp.MustCompile(`(?m)^[ \t]*` + headRe + `[ \t]*\n[ \t]*\{\n`)
		if k := len(pat.FindAll(e.text, -1)); k != n {
			e.die("%s -- the walk matches %d times, expected %d", what, k, n)
			return
		}
		for i := 0; i < n; i++ {
			m := pat.FindIndex(e.text)
			b := cutil.Blank(e.text)
			o := indexFrom(e.text, []byte("{"), m[0])
			c := cutil.Match(b, o)
			end := indexFrom(e.text, []byte("\n"), c) + 1
			out := append([]byte{}, e.text[:m[0]]...)
			out = append(out, repl...)
			e.text = append(out, e.text[end:]...)
		}
	})
	if !e.Failed() {
		e.say(what)
	}
}

// Whim72 makes one window and one tabpage the layout: every walk over the window
// or tabpage list folds to curwin or curtab, and the list heads themselves go.
func Whim72(text []byte, w io.Writer) ([]byte, error) {
	e := New("onewin", text, w)

	// 1. the constant tests, before anything renames what they compare.
	// ONE_WINDOW, expanded at three sites and missed by phase 68, which only
	// folded the one_window()/last_window()/only_one_window() functions.
	e.LiteralN("(firstwin == lastwin) ", "TRUE ", 3, "ONE_WINDOW, expanded in place")
	e.LiteralN("wp == firstwin", "TRUE", 2, "win_update asking whether this is the top window")
	e.Literal("wp == lastwin", "wp == curwin", "win_redr_ruler asking for the bottom window")

	e.dropWalkIn("aucmd_prepbuf", `for \(\(win\) = firstwin; \(win\) != NULL; \(win\) = \(win\)->w_next\)`,
		w72lit3, "aucmd_prepbuf searching for the window showing a buffer", 1)
	e.dropWalkIn("can_unload_buffer", `for \(\(wp\) = firstwin; \(wp\) != NULL; \(wp\) = \(wp\)->w_next\)`,
		w72lit4, "can_unload_buffer asking whether the buffer is on screen", 1)
	e.Lines(`borrow_stl_vsep_hl\(\);`, 2, "the two calls to the separator-highlight pass")
	e.deleteDefinition("borrow_stl_vsep_hl", "borrow_stl_vsep_hl, which had no window to borrow from")
	e.Body("current_win_nr", w72lit5, "current_win_nr, which counted to the window")
	e.Body("current_tab_nr", w72lit5, "current_tab_nr, which counted to the tabpage")
	e.replaceBlock("getout", `(?m)^[ \t]*for \(tp = first_tabpage; tp != NULL; tp = next_tp\)$`,
		w72lit6, "quitting walking every window of every tabpage")
	e.Body("create_windows", w72lit7, "the startup scan rewinding over the window list")
	e.Body("win_valid", w72lit8, "win_valid, which walked the list for the window it was given")
	e.Body("win_valid_any_tab", w72lit8, "win_valid_any_tab, which walked every tabpage for it")
	e.Body("win_find_by_id", w72lit9, "win_find_by_id, which walked the list by id")
	e.Body("valid_tabpage", w72lit10, "valid_tabpage, which walked the tabpage list")
	e.foldNeverIn("goto_tabpage_tp", `(?m)^[ \t]*if \(tp != curtab && leave_tabpage\(`, "switching to another tabpage", 1)
	e.foldNeverIn("close_buffer", `(?m)^[ \t]*if \(is_curwin && curwin != win && win_valid\)$`, "closing a buffer from another window", 1)
	e.foldNeverIn("buf_freeall", `(?m)^[ \t]*if \(is_curwin && curwin != the_curwin && win_valid_any_tab\(the_curwin\)\)$`,
		"freeing a buffer from another window", 1)
	e.Body("win_alloc_firstwin", w72lit11, "win_alloc_firstwin cloning an existing window")
	e.Body("win_alloc_first", w72lit12, "the first tabpage being the head of a list")
	e.foldNeverIn("win_alloc", `(?m)^[ \t]*if \(!hidden\)$`, "win_alloc appending to the window list", 1)
	e.Body("unuse_tabpage", w72lit13, "a tabpage remembering the ends of its window list")
	e.Body("win_rest_invalid", w72lit14, "win_rest_invalid invalidating every window after one")

	e.foldWalks(nestedWalk,
		func(g []string) bool { return allEqual(g, 2, 6, 7, 8) && allEqual(g, 3, 4, 5) },
		func(g []string) string { return g[2] + " = curwin;" },
		"the window walk inside every tabpage walk")
	e.foldWalks(tabsWalk,
		func(g []string) bool { return allEqual(g, 2, 3, 4, 5) },
		func(g []string) string { return g[2] + " = curtab;" },
		"every walk over the tabpage list")
	e.foldWalks(winsWalk,
		func(g []string) bool { return allEqual(g, 2, 3, 4, 5) },
		func(g []string) string { return g[2] + " = curwin;" },
		"every walk over the window list")

	e.InFunction("win_ins_lines", func(e *E) {
		e.Literal(w72lit16, w72lit17, "scrolling asking whether a window is below")
	})
	e.InFunction("win_ins_lines", func(e *E) {
		e.Literal(w72lit18, "", "scrolling refusing when a window is below")
	})
	e.InFunction("win_ins_lines", func(e *E) {
		e.Literal(w72lit19, w72lit20, "scrolling invalidating the window below")
	})
	e.InFunction("win_del_lines", func(e *E) {
		e.Literal(w72lit21, w72lit22, "deleting lines asking whether a window is below")
	})
	e.InFunction("win_del_lines", func(e *E) {
		e.Literal(w72lit23, w72lit24, "deleting lines invalidating the window below")
	})
	e.InFunction("win_do_lines", func(e *E) {
		e.Literal(w72lit25, "", "'termfastscroll' refusing to scroll a window that has one below")
	})
	e.Lines(`win_T[ \t]+\*w_next;`, 1, "the window list pointer in win_T")

	for _, f := range []struct {
		fn, v string
		n     int
	}{
		{"setfname", "tab", 1}, {"changed_common", "tp", 3},
		{"mark_adjust_internal", "tab", 1}, {"set_options_default", "tp", 1},
		{"did_set_global_listfillchars", "tp", 1},
		{"check_chars_options", "tp", 1}, {"check_lnums_both", "tp", 1},
		{"screenalloc", "tp", 2},
	} {
		f := f
		e.InFunction(f.fn, func(e *E) {
			e.Lines(f.v+` = curtab;`, f.n, fmt.Sprintf("the tabpage %s no longer walks", f.fn))
		})
		e.InFunction(f.fn, func(e *E) {
			e.Lines(`tabpage_T[ \t]+\*`+f.v+`;`, 1, "and the variable that held it")
		})
	}

	// 7. what is left of the two lists
	e.Lines(`static win_T[ \t]+\*firstwin;`, 1, "firstwin")
	e.Lines(`static win_T[ \t]+\*lastwin;`, 1, "lastwin")
	e.Lines(`static tabpage_T[ \t]+\*first_tabpage;`, 1, "first_tabpage")
	if !e.Failed() {
		n := e.Mentions("firstwin") + e.Mentions("lastwin")
		t := regexp.MustCompile(`\bfirstwin\b`).ReplaceAll(e.Text(), []byte("curwin"))
		t = regexp.MustCompile(`\blastwin\b`).ReplaceAll(t, []byte("curwin"))
		e.Set(t)
		e.say(fmt.Sprintf("the list heads read as layout state (%d mentions -> curwin)", n))
	}
	return e.Done()
}

func init() { register("whim72", Whim72) }
