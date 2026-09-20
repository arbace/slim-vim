package edit

import (
	"bytes"
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

// emptyFns do nothing at all.  The phase PROVES that before removing a single
// call: if one has acquired a body again, deleting its calls would change
// behaviour.
var emptyFns = []string{
	"clear_chartabsize_arg", "may_trigger_modechanged",
	"may_trigger_win_scrolled_resized", "out_flush_check", "add_b0_fenc",
	"set_b0_dir_flag", "pum_may_redraw", "ml_setname", "ml_preserve",
	"trigger_undo_ftplugin", "set_init_lang_env", "set_init_default_printencoding",
	"set_init_3", "mch_new_shellsize", "mch_early_init",
}

// bodyIsEmpty says whether a definition's body holds nothing but whitespace.
func bodyIsEmpty(text []byte, name string) (bool, bool) {
	a, z, ok := cutil.FindDefinition(text, cutil.Blank(text), name)
	if !ok {
		return false, false
	}
	inner := text[a:z]
	i := bytes.Index(inner, []byte("{"))
	j := bytes.LastIndex(inner, []byte("}"))
	if i < 0 || j <= i {
		return false, false
	}
	return len(bytes.TrimSpace(inner[i+1:j])) == 0, true
}

// Whim78 removes every call to fifteen functions that do nothing, and the
// write-only state five more kept.
func Whim78(text []byte, w io.Writer) ([]byte, error) {
	e := New("nostubs", text, w)

	for _, fn := range emptyFns {
		empty, found := bodyIsEmpty(text, fn)
		if !found || !empty {
			e.Refuse("%s is no longer empty -- removing its calls would change behaviour", fn)
			return e.Done()
		}
	}
	if empty, found := bodyIsEmpty(text, "nv_nop"); !found || !empty {
		e.Refuse("nv_nop is no longer empty; it is the nv_cmds KE_NOP row and must stay empty")
		return e.Done()
	}

	total := 0
	for _, fn := range emptyFns {
		q := regexp.QuoteMeta(fn)
		bare := regexp.MustCompile(`(?m)^[ \t]*(?:\(void\))?` + q + `\([^;\n]*\);[ \t]*\n`)
		allref := len(regexp.MustCompile(`\b`+q+`\b`).FindAll(cutil.Blank(e.Text()), -1))
		nBare := len(bare.FindAll(e.Text(), -1))
		// every mention that is not the prototype, the definition or a bare
		// call is a use this phase cannot simply delete
		nProto := len(regexp.MustCompile(`(?m)^static [^\n]*\b`+q+`\(`).FindAll(e.Text(), -1))
		nDefn := len(regexp.MustCompile(`(?m)^`+q+`\(`).FindAll(e.Text(), -1))
		if allref != nBare+nProto+nDefn {
			e.Refuse("%s has %d mentions but only %d bare calls (+%d proto +%d defn) -- one is inside an expression and a line removal would corrupt it",
				fn, allref, nBare, nProto, nDefn)
			return e.Done()
		}
		e.Set(bare.ReplaceAll(e.Text(), nil))
		total += nBare
	}
	e.say(fmt.Sprintf("every call to the %d functions that do nothing (%d sites)", len(emptyFns), total))

	e.FoldNeverIn2("getcmdline_int", `(?m)^[ \t]*if \(is_state\.winid != curwin->w_id\)$`,
		"the command line re-initialising incremental search for another window", 2)
	e.InFunction("init_incsearch_state", func(e *E) {
		e.Lines(`is_state->winid = curwin->w_id;`, 1, "recording which window the search started in")
	})
	e.Lines(`int[ \t]+winid;`, 1, "the field that recorded it")
	e.InFunction("win_alloc", func(e *E) {
		e.Lines(`new_wp->w_id = \+\+last_win_id;`, 1, "numbering the one window")
	})
	e.Lines(`int[ \t]+w_id;`, 1, "the number it was given")
	e.Lines(`static int last_win_id = LOWEST_WIN_ID - 1;`, 1, "the counter behind it")
	e.Lines(`enum \{ LOWEST_WIN_ID = 1000 \};`, 1, "and where the numbering started")
	e.InFunction("block_autocmds", func(e *E) { e.Lines(`\+\+autocmd_blocked;`, 1, "blocking autocommands") })
	e.InFunction("unblock_autocmds", func(e *E) { e.Lines(`--autocmd_blocked;`, 1, "and unblocking them") })
	e.Lines(`static int[ \t]+autocmd_blocked = 0;`, 1, "the count nothing reads")
	for _, v := range []string{"autocmd_no_enter", "autocmd_no_leave"} {
		v := v
		e.InFunction("create_windows", func(e *E) {
			e.Lines(`\+\+`+v+`;`, 1, fmt.Sprintf("startup suppressing %s", v))
		})
		e.InFunction("create_windows", func(e *E) {
			e.Lines(`--`+v+`;`, 1, "and restoring it")
		})
	}
	e.Lines(`static int[ \t]+autocmd_no_enter  = FALSE ;`, 1, "the enter flag")
	e.Lines(`static int[ \t]+autocmd_no_leave  = FALSE ;`, 1, "the leave flag")
	e.InFunction("redraw_after_callback", func(e *E) {
		e.Lines(`\+\+redrawing_for_callback;`, 1, "marking a callback redraw")
	})
	e.InFunction("redraw_after_callback", func(e *E) {
		e.Lines(`--redrawing_for_callback;`, 1, "and unmarking it")
	})
	e.Lines(`static int redrawing_for_callback  = 0 ;`, 1, "the mark nothing reads")
	e.InFunction("win_enter_ext", func(e *E) {
		e.Lines(`prevwin = curwin;`, 1, "remembering the previous window")
	})
	e.Lines(`static win_T[ \t]+\*prevwin  = NULL ;`, 1, "the window nothing looks back at")
	e.Lines(`int[ \t]+prechar;`, 1, "cmdarg_T.prechar")
	return e.Done()
}

func init() { register("whim78", Whim78) }
