package edit

// The multi-line literals pipes/zero8-edit.sh matches on, EXTRACTED from the phase's
// heredoc by tools/gocmp/genlits.py rather than retyped.  They carry BLANK
// LINES, which a filtered read of a phase program does not show, and a
// literal that is 90%% right matches nothing.  See that tool for the
// measurement.
const (
	z8Head = "    if (cap->nchar == 'f')\n    {\n        nv_gotofile(cap);\n    }\n    else\n    {\n"
	z8lit1 = "    case 'f':\n    case 'F':\n        nv_gotofile(cap);\n        break;\n\n"
	z8lit2 = "    if (ea.argt & EX_ARGOPT)\n    {\n        while (ea.arg[0] == '+' && ea.arg[1] == '+')\n        {\n            if (getargopt(&ea) == FAIL)\n            {\n                errormsg = _(e_invalid_argument);\n                goto doend;\n            }\n        }\n    }\n\n"
	z8lit4 = "    }\n"
)
