package edit

// The multi-line literals pipes/whim80-edit.sh matches on, EXTRACTED from the phase's
// heredoc by tools/gocmp/genlits.py rather than retyped.  They carry BLANK
// LINES, which a filtered read of a phase program does not show, and a
// literal that is 90%% right matches nothing.  See that tool for the
// measurement.
const (
	w80Head  = "        if ( ((unsigned)(eap->cmd[0]) - 'a' < 26) )\n"
	w80lit1  = "\n"
	w80lit2  = "The lookup this phase writes: a prefix at least as long as the row says.\n\n    A name is letters only now -- the py3 and vim9 digit rules go with every row\n    that needed them -- so the word stops at the first character that is not one.\n    "
	w80lit3  = "    size_t      cmd_namelen;\n"
	w80lit4  = "    int         cmd_minlen;\n"
	w80lit5  = "static int      if_level = 0;\n"
	w80lit6  = "    else if (!eap->skip)\n"
	w80lit7  = "    else\n"
	w80lit8  = "\n\n"
	w80lit9  = "        for (eap->cmdidx = (cmdidx_T)0; (int)eap->cmdidx < (int)CMD_SIZE; eap->cmdidx = (cmdidx_T)((int)eap->cmdidx + 1))\n        {\n            if (len >= cmdnames[(int)eap->cmdidx].cmd_minlen &&  strncmp((char *)(cmdnames[(int)eap->cmdidx].cmd_name), (char *)((char *)eap->cmd), ((size_t)len))  == 0)\n            {\n                break;\n            }\n        }\n"
	w80lit10 = "%s\t%s\n"
	w80lit11 = "\nfind_ex_command("
	w80lit12 = "\n};\n"
)
