package edit

// The multi-line literals pipes/zero6-edit.sh matches on, EXTRACTED from the phase's
// heredoc by tools/gocmp/genlits.py rather than retyped.  They carry BLANK
// LINES, which a filtered read of a phase program does not show, and a
// literal that is 90%% right matches nothing.  See that tool for the
// measurement.
const (
	z6lit1 = "    if (ea.cmdidx == CMD_write || ea.cmdidx == CMD_update)\n    {\n        if (*ea.arg == '>')\n        {\n            if (*++ea.arg != '>')\n            {\n                errormsg = _(e_use_w_or_w_gt_gt);\n                goto doend;\n            }\n            ea.arg = skipwhite(ea.arg + 1);\n            ea.append = TRUE;\n        }\n        else if (*ea.arg == '!' && ea.cmdidx == CMD_write)\n        {\n            ++ea.arg;\n            ea.usefilter = TRUE;\n        }\n    }\n\n"
)
