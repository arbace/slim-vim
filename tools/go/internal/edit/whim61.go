package edit

import (
	"fmt"
	"io"
)

var (
	// titleWanted is the flag a change sets to ask for a title update.
	titleWanted = `(?m)^[ \t]*if \(need_maketitle\)$`
	// restoreTitle is the call that puts the terminal's title back.
	restoreTitle = `(?m)^[ \t]*mch_restore_title\( \(SAVE_RESTORE_TITLE \| SAVE_RESTORE_ICON\) \);\n`
)

// Whim61 takes the window title: the flag, the eleven callers that set or
// restored it, and the terminal's title stack.
func Whim61(text []byte, w io.Writer) ([]byte, error) {
	e := New("notitle", text, w)

	for _, fn := range []string{"showruler", "redraw_cmd", "ui_focus_change", "main_loop"} {
		fn := fn
		e.InFunction(fn, func(e *E) {
			e.DropIf(titleWanted, fmt.Sprintf("%s updating the title", fn))
		})
	}
	for _, fn := range []string{"enter_buffer", "buf_name_changed", "do_ecmd", "set_termname", "set_shellsize_inner", "win_enter_ext"} {
		fn := fn
		e.InFunction(fn, func(e *E) {
			e.Cut(`(?m)^[ \t]*maketitle\(\);\n`, 1, fmt.Sprintf("%s updating the title", fn))
		})
	}

	e.InFunction("do_exedit", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(n != curwin->w_arg_idx_invalid\)$`,
			":edit updating the title when the argument index moved")
		e.Cut(`(?m)^[ \t]*n = curwin->w_arg_idx_invalid;\n`, 1,
			":edit remembering the argument index for the title")
		// n has one other use in do_exedit(): saving and restoring readonlymode
		// around :view.  So after the title's assignment and test go, exactly
		// three mentions are left -- the declaration, the save and the restore.
		// Any other count is a use of n nobody accounted for.
		if k := e.Mentions("n"); !e.Failed() && k != 3 {
			e.Refuse("do_exedit mentions n %d times after the title went, expected 3 (declaration, readonlymode save and restore)", k)
		}
	})

	e.InFunction("ex_stop", func(e *E) {
		e.Cut(restoreTitle, 1, ":stop restoring the title")
		e.Cut(`(?m)^[ \t]*maketitle\(\);\n[ \t]*resettitle\(\);\n`, 1, ":stop setting the title again")
	})
	e.InFunction("mch_exit", func(e *E) {
		e.Cut(restoreTitle, 1, "exit restoring the title")
		e.Cut(`(?m)^[ \t]*term_pop_title\( \(SAVE_RESTORE_TITLE \| SAVE_RESTORE_ICON\) \);\n`, 1,
			"exit popping the terminal's title stack")
	})
	e.InFunction("vim_main2", func(e *E) {
		e.Cut(`(?m)^[ \t]*term_push_title\( \(SAVE_RESTORE_TITLE \| SAVE_RESTORE_ICON\) \);\n`, 1,
			"startup pushing the terminal's title stack")
	})
	e.InFunction("clear_termoptions", func(e *E) {
		e.Cut(restoreTitle, 1, "changing terminal restoring the title")
	})
	e.InFunction("value_changed", func(e *E) {
		e.Cut(`(?m)^[ \t]*mch_restore_title\(last == &lasttitle \? SAVE_RESTORE_TITLE : SAVE_RESTORE_ICON\);\n`, 1,
			"a cleared value restoring the title")
	})
	e.InFunction("set_init_3", func(e *E) {
		e.Cut(`(?m)^[ \t]*set_title_defaults\(\);\n`, 1, "startup choosing 'title' and 'icon' defaults")
	})

	// Six: buf_write(), changed_internal(), unchanged(), redraw_titles(), and
	// two that the sweep takes anyway -- maketitle()'s own early return and
	// did_set_titlelen().
	e.Cut(`(?m)^[ \t]*need_maketitle = TRUE;\n`, 6, "changes asking for a title update")
	return e.Done()
}

func init() { register("whim61", Whim61) }
