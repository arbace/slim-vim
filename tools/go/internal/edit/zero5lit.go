package edit

// The multi-line literals pipes/zero5-edit.sh matches on, EXTRACTED from the phase's
// heredoc by tools/gocmp/genlits.py rather than retyped.  They carry BLANK
// LINES, which a filtered read of a phase program does not show, and a
// literal that is 90%% right matches nothing.  See that tool for the
// measurement.
const (
	z5lit1 = "        else\n        {\n            argv_idx = -1;\n\n            if (parmp->edit_type != EDIT_NONE)\n            {\n                mainerr(ME_TOO_MANY_ARGS, (char_u *)argv[0]);\n            }\n            parmp->edit_type = EDIT_FILE;\n\n            if ((p = vim_strsave((char_u *)argv[0])) == NULL)\n            {\n                mch_exit(2);\n            }\n\n            (void)buflist_add(p, BLN_CURBUF | BLN_LISTED);\n\n        }\n"
	z5lit2 = "        else\n        {\n            mainerr(ME_UNKNOWN_OPTION, (char_u *)argv[0]);\n        }\n"
	z5lit3 = "\n    char_u      *p = NULL;\n"
	z5lit5 = "            case NUL:\n                if (parmp->edit_type != EDIT_NONE)\n                {\n                    mainerr(ME_TOO_MANY_ARGS, (char_u *)argv[0]);\n                }\n                parmp->edit_type = EDIT_STDIN;\n                read_cmd_fd = 2;\n                argv_idx = -1;\n                break;\n\n"
	z5lit6 = "            case '-':\n                if (argv[0][argv_idx])\n                {\n                    mainerr(ME_UNKNOWN_OPTION, (char_u *)argv[0]);\n                }\n                had_minmin = TRUE;\n                argv_idx = -1;\n                break;\n\n"
	z5lit7 = "\n    int         had_minmin = FALSE;\n"
)
