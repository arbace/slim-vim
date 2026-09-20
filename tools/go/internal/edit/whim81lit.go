package edit

// The multi-line literals /root/.claude/jobs/107d6bd5/tmp/w81.sh matches on, EXTRACTED from the phase's
// heredoc by tools/gocmp/genlits.py rather than retyped.  They carry BLANK
// LINES, which a filtered read of a phase program does not show, and a
// literal that is 90%% right matches nothing.  See that tool for the
// measurement.
const (
	w81lit1 = "    int comment_char = '\"';\n\n    return (c == NUL || c == '|' || c == comment_char || c == '\\n');"
	w81lit2 = "    if (c == NUL || c == '|' || c == '\\n')\n    {\n        return TRUE;\n    }\n    return c == '\"';"
	w81lit3 = "    while (*p != '|' && *p != '\\n')\n"
	w81lit4 = "    while (*p != '\\n')\n"
	w81lit5 = "    if (*s == '|' || *s == '\\n')\n"
	w81lit6 = "    if (*s == '\\n')\n"
	w81lit7 = "    if (*cmd && *cmd != '\"')\n    {\n        set_nextcmd(eap, cmd);"
	w81lit8 = "    if (*cmd)\n    {\n        set_nextcmd(eap, cmd);"
)
