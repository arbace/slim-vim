package edit

// The multi-line literals pipes/zero7-edit.sh matches on, EXTRACTED from the phase's
// heredoc by tools/gocmp/genlits.py rather than retyped.  They carry BLANK
// LINES, which a filtered read of a phase program does not show, and a
// literal that is 90%% right matches nothing.  See that tool for the
// measurement.
const (
	z7lit2 = "    if (ea.cmdidx == CMD_read)\n    {\n        if (ea.forceit)\n        {\n            ea.usefilter = TRUE;\n            ea.forceit = FALSE;\n        }\n        else if (*ea.arg == '!')\n        {\n            ++ea.arg;\n            ea.usefilter = TRUE;\n        }\n    }\n\n"
)
