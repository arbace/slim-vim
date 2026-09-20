package edit

// The multi-line literals pipes/zero13-edit.sh matches on, EXTRACTED from the phase's
// heredoc by tools/gocmp/genlits.py rather than retyped.  They carry BLANK
// LINES, which a filtered read of a phase program does not show, and a
// literal that is 90%% right matches nothing.  See that tool for the
// measurement.
const (
	z13lit1  = "    if ((!(State & (MODE_INSERT | MODE_CMDLINE)) || arrow_used) && scriptin[curscript] == NULL)\n"
	z13lit2  = "    if (!(State & (MODE_INSERT | MODE_CMDLINE)) || arrow_used)\n"
	z13lit3  = "        && scriptin[curscript] == NULL\n"
	z13lit4  = "    script_char = -1;\n    while (scriptin[curscript] != NULL && script_char < 0)\n    {\n        if (got_int || (script_char = getc(scriptin[curscript])) < 0)\n        {\n            closescript();\n            if (got_int)\n            {\n                retesc = TRUE;\n            }\n            else\n            {\n                return -1;\n            }\n        }\n        else\n        {\n            buf[0] = script_char;\n            len = 1;\n        }\n    }\n\n"
	z13lit5  = "            return retesc;\n"
	z13lit6  = "            return FALSE;\n"
	z13lit7  = "    int         retesc = FALSE;\n"
	z13lit8  = "    int         script_char;\n"
	z13lit9  = "                    redir_write(p, -1);\n"
	z13lit10 = "                redir_write((char_u *)s, -1);\n"
	z13lit11 = "    redir_write((char_u *)str, maxlen);\n"
	z13lit12 = "static void redir_write(char_u *s, int maxlen);\n"
	z13lit13 = "    int         did_return = FALSE;\n"
	z13lit14 = "        did_return = TRUE;\n"
	z13lit15 = "static int  redir_off  = FALSE ;\n"
	z13lit16 = "static void ui_write(char_u *s, int len, int console);\n"
	z13lit17 = "static void ui_write(char_u *s, int len);\n"
	z13lit18 = "ui_write(char_u *s, int len, int console  __attribute__((unused)) )\n{\n\n    mch_write(s, len);\n    if (console && s[len - 1] == '\\n')\n    {\n        vim_fsync(1);\n    }\n\n}\n"
	z13lit19 = "ui_write(char_u *s, int len)\n{\n    mch_write(s, len);\n}\n"
	z13lit20 = "    ui_write(out_buf, len, FALSE);\n"
	z13lit21 = "    ui_write(out_buf, len);\n"
)
