package edit

// The multi-line literals pipes/zero12-edit.sh matches on, EXTRACTED from the phase's
// heredoc by tools/gocmp/genlits.py rather than retyped.  They carry BLANK
// LINES, which a filtered read of a phase program does not show, and a
// literal that is 90%% right matches nothing.  See that tool for the
// measurement.
const (
	z12lit2 = "        if (wp->w_buffer->b_p_ro)\n        {\n            plen += vim_snprintf((char *)p + plen,  PATH_MAX  - plen, \"%s\", _(\"[RO]\"));\n        }\n"
	z12lit3 = "static char *did_set_readonly(optset_T *args);\n"
)
