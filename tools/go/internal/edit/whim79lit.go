package edit

// The multi-line literals /root/.claude/jobs/107d6bd5/tmp/w79.sh matches on, EXTRACTED from the phase's
// heredoc by tools/gocmp/genlits.py rather than retyped.  They carry BLANK
// LINES, which a filtered read of a phase program does not show, and a
// literal that is 90%% right matches nothing.  See that tool for the
// measurement.
const (
	w79lit1 = "    if (!eap->skip)\n    {\n        ex_ni(eap);\n    }\n    else\n    {\n        vim_free(script_get(eap, eap->arg));\n    }\n"
	w79lit2 = "    if (!eap->skip)\n    {\n        ex_ni(eap);\n    }\n"
	w79lit3 = "                            eap->line2 = eap->addr_type == ADDR_WINDOWS\n                                                  ?  current_win_nr(NULL)  :  current_tab_nr(NULL) ;\n"
	w79lit4 = "                            eap->line2 = 1;\n"
	w79lit5 = "    return frame_minheight(curtab->tp_topframe, NULL) + tabline_height()\n        + MIN_CMDHEIGHT;\n"
	w79lit6 = "    return frame_minheight(curtab->tp_topframe, NULL) + MIN_CMDHEIGHT;\n"
	w79lit7 = "{\n"
)
