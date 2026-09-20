package edit

// The multi-line literals pipes/zero4-edit.sh matches on, EXTRACTED from the phase's
// heredoc by tools/gocmp/genlits.py rather than retyped.  They carry BLANK
// LINES, which a filtered read of a phase program does not show, and a
// literal that is 90%% right matches nothing.  See that tool for the
// measurement.
const (
	z4lit3  = "     {'Q', nv_exmode, NV_NCW, 0} ,\n"
	z4lit4  = "     {'Q', nv_error, NV_NCW, 0} ,\n"
	z4lit5  = "    case 'Q':\n        if (!check_text_locked(cap->oap) && !checkclearopq(oap))\n        {\n            do_exmode(TRUE);\n        }\n        break;\n\n"
	z4lit6  = "                exmode_active = EXMODE_NORMAL;\n"
	z4lit7  = "                exmode_active = EXMODE_VIM;\n"
	z4lit8  = "                if (exmode_active)\n                {\n                    silent_mode = TRUE;\n                }\n                else\n                {\n                    mainerr(ME_UNKNOWN_OPTION, (char_u *)argv[0]);\n                }\n"
	z4lit9  = "                exmode_active = 0;\n"
	z4lit10 = "\n    int         exmode_was = exmode_active;\n"
	z4lit12 = "\n                || exmode_active\n"
	z4lit13 = "\n    check_tty();\n"
	z4lit14 = "\n    int         save_silent = silent_mode;\n"
	z4lit15 = "\n    silent_mode = FALSE;\n"
	z4lit16 = "\n    silent_mode = save_silent;\n"
	z4lit17 = "\nstatic int      ex_pressedreturn = FALSE;\n"
	z4lit18 = "\n                ex_pressedreturn = TRUE;\n"
	z4lit19 = "\nstatic int ex_no_reprint  = FALSE ;\n"
	z4lit20 = "\n    ex_no_reprint = TRUE;\n"
	z4lit21 = "\n        ex_no_reprint = TRUE;\n"
	z4lit22 = "\nstatic int      ex_exitval  = 0 ;\n"
	z4lit23 = "\n        ex_exitval = 1;\n\n"
	z4lit24 = "\n    volatile int previous_got_int = FALSE;\n"
	z4lit25 = "\n            previous_got_int = TRUE;\n"
	z4lit26 = "        else\n        {\n            previous_got_int = FALSE;\n        }\n"
	z4lit27 = "\n    int     use_plus_cmd = FALSE;\n"
	z4lit28 = "\nstatic void main_loop(int cmdwin, int noexmode);\n"
	z4lit29 = "\nstatic void main_loop(int cmdwin);\n"
	z4lit30 = "main_loop(int         cmdwin, int         noexmode)\n"
	z4lit31 = "main_loop(int         cmdwin)\n"
	z4lit32 = "\n    main_loop(FALSE, FALSE);\n"
	z4lit33 = "\n    main_loop(FALSE);\n"
	z4lit34 = "\ntheend:\n    current_oap = prev_oap;\n"
	z4lit35 = "\n    current_oap = prev_oap;\n"
)
