package edit

import "io"

// Whim68 makes one window and one tabpage an invariant: the autocommand window
// goes, one_window(), last_window() and only_one_window() become constant TRUE,
// and everything those tests guarded goes with them.
func Whim68(text []byte, w io.Writer) ([]byte, error) {
	e := New("onewindow", text, w)

	// 1. the autocommand window, the last thing that could add a window
	e.InFunction("aucmd_prepbuf", func(e *E) {
		e.Splice("    win_T *auc_win = NULL;\n", "    aco->save_curwin_id = curwin->w_id;\n",
			"    if (win == NULL)\n    {\n        return;\n    }\n\n",
			"aucmd_prepbuf -- the aucmd_win search was not found before the saved ids")
		if !e.Failed() {
			e.say("aucmd_prepbuf building a window to run autocommands in")
		}
		e.Splice("    if (win != NULL)\n", "    curbuf = buf;\n", "    curwin = win;\n\n",
			"aucmd_prepbuf -- the window choice was not found before curbuf = buf")
		if !e.Failed() {
			e.say("aucmd_prepbuf choosing between that window and the real one")
		}
	})
	// fold_never, not drop_if: this `if` HAS an else -- the same-window restore
	// -- and DropIf refuses that shape on purpose, since deleting the if alone
	// would orphan the else.  FoldNever keeps the else body, which is what is
	// left when the index can never be >= 0.
	e.InFunction("aucmd_restbuf", func(e *E) {
		e.FoldNever(`(?m)^[ \t]*if \(aco->use_aucmd_win_idx >= 0\)$`, "aucmd_restbuf taking that window down again")
	})
	// Both writes to use_aucmd_win_idx went with the branch above, and its only
	// reader went with aucmd_restbuf's folded test, so the field itself follows.
	e.Cut(`(?m)^[ \t]*int[ \t]+use_aucmd_win_idx;\n`, 1, "aco_save_T's window index")
	e.deleteDefinition("win_alloc_popup_win", "win_alloc_popup_win, which only the autocommand window used")
	e.deleteDefinition("win_init_popup_win", "win_init_popup_win, the same")
	e.Cut(`(?m)^static aucmdwin_T aucmd_win\[AUCMD_WIN_COUNT\];\n`, 1, "the aucmd_win[] table")
	// Three places MANAGE that table without ever reading it -- the can_cindent
	// shape again.  Each is guarded by auc_win != NULL, which nothing can make
	// true now.
	e.Lines(`autocmd_init\(\);`, 1, "the call that zeroed the table at startup")
	e.deleteDefinition("autocmd_init", "autocmd_init, whose body was that memset")
	e.Cut(`(?m)^[ \t]*for \(int i = 0; i < AUCMD_WIN_COUNT; \+\+i\)\n[ \t]*\{\n[ \t]*if \(aucmd_win\[i\]\.auc_win != NULL\)\n[ \t]*\{\n[ \t]*win_free_lsize\(aucmd_win\[i\]\.auc_win\);\n[ \t]*\}\n[ \t]*\}\n\n?`, 1,
		"screenalloc freeing the line sizes of windows that do not exist")
	e.Cut(`(?m)^[ \t]*for \(int i = 0; i < AUCMD_WIN_COUNT; \+\+i\)\n[ \t]*\{\n[ \t]*if \(aucmd_win\[i\]\.auc_win != NULL && aucmd_win\[i\]\.auc_win->w_lines == NULL && win_alloc_lines\(aucmd_win\[i\]\.auc_win\) == FAIL\)\n[ \t]*\{\n[ \t]*outofmem = TRUE;\n[ \t]*break;\n[ \t]*\}\n[ \t]*\}\n\n?`, 1,
		"screenalloc allocating lines for them")

	// 2. the invariant: one window, one tabpage
	e.BodyTrue("one_window", "one_window() is constant TRUE")
	e.BodyTrue("last_window", "last_window() is constant TRUE")
	e.BodyTrue("only_one_window", "only_one_window() is constant TRUE")

	// 3. what those tests guarded
	e.InFunction("ex_quit", func(e *E) {
		e.Sub(`(?m)^[ \t]*if \(eap->addr_count > 0\)\n[ \t]*\{\n(?s:.*?)[ \t]*\}\n[ \t]*else\n[ \t]*\{\n[ \t]*wp = curwin;\n[ \t]*\}\n`,
			"    wp = curwin;\n", 1, ":quit with a window count, of which there is one")
	})
	e.InFunction("ex_quit", func(e *E) {
		e.FoldAlways(`(?m)^[ \t]*if \(only_one_window\(\) && \( \(firstwin == lastwin\)  \|\| eap->addr_count == 0\)\)$`,
			":quit leaving the editor")
	})
	e.InFunction("ex_quit", func(e *E) {
		e.Lines(`win_close\(wp, TRUE\);`, 1, ":quit closing a window it can never reach")
	})
	e.InFunction("ex_exit", func(e *E) {
		e.FoldAlways(`(?m)^[ \t]*if \(only_one_window\(\)\)$`, ":xit leaving the editor")
	})
	e.InFunction("ex_exit", func(e *E) {
		e.Lines(`win_close\(curwin, TRUE\);`, 1, ":xit closing a window it can never reach")
	})
	e.InFunction("do_exedit", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(old_curwin != NULL\)$`, ":edit closing the window it came from, which is never given one")
	})
	e.InFunction("set_curbuf", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(unload\)$`, "unloading a buffer closing the windows that show it")
	})
	// only_one_window() is TRUE, so these terms go rather than the tests.
	e.InFunction("check_more", func(e *E) {
		e.Literal("only_one_window() && ", "", "check_more asking how many windows there are")
	})
	e.InFunction("before_quit_autocmds", func(e *E) {
		e.Literal(" && only_one_window()", "", "the quit autocommands asking how many windows there are")
	})
	e.InFunction("create_windows", func(e *E) {
		e.Literal("got_int || only_one_window()", "TRUE", "the swap-file quit asking how many windows there are")
	})
	e.InFunction("close_buffer", func(e *E) {
		e.LiteralN("abort_if_last && one_window()", "abort_if_last", 2,
			"closing a buffer asking whether its window is the last")
	})
	return e.Done()
}

func init() { register("whim68", Whim68) }
