package edit

// The multi-line literals pipes/zero11-edit.sh matches on, EXTRACTED from the phase's
// heredoc by tools/gocmp/genlits.py rather than retyped.  They carry BLANK
// LINES, which a filtered read of a phase program does not show, and a
// literal that is 90%% right matches nothing.  See that tool for the
// measurement.
const (
	z11lit1 = "    int save_exiting = exiting;\n    exiting = TRUE;\n    getout(0);\n    not_exiting(save_exiting);\n"
	z11lit2 = "    getout(0);\n"
	z11lit3 = "    bool        w_topline_was_set;\n"
	z11lit4 = "    wp->w_topline_was_set = true;\n"
	z11lit5 = "    int         wi_changelistidx;\n"
	z11lit6 = "        wip->wi_changelistidx = win->w_changelistidx;\n"
)
