package edit

// The multi-line literals pipes/zero22-edit.sh matches on, EXTRACTED from the phase's
// heredoc by tools/gocmp/genlits.py rather than retyped.  They carry BLANK
// LINES, which a filtered read of a phase program does not show, and a
// literal that is 90%% right matches nothing.  See that tool for the
// measurement.
const (
	z22Helpers = "    static size_t\niobuff_room(void)\n{\n    if (IObuff == NULL)\n    {\n        return 0;\n    }\n    return  (1024+1) ;\n}\n\n    static size_t\nemsg_iobuff_room(void)\n{\n    if (IObuff == NULL || emsg_not_now())\n    {\n        return 0;\n    }\n    return  (1024+1) ;\n}\n\n    static char *\niobuff_or(const char *s)\n{\n    if (IObuff == NULL)\n    {\n        return (char *)s;\n    }\n    return (char *)IObuff;\n}\n\n    static size_t\nsafelen_result(char *str, size_t str_m, int str_l)\n{\n    if (str_m == 0)\n    {\n        return 0;\n    }\n    if (str_l < 0)\n    {\n        *str = NUL;\n        return 0;\n    }\n    return ((size_t)str_l >= str_m) ? str_m - 1 : (size_t)str_l;\n}\n\n    static size_t\nappend_room(char *str, size_t str_m)\n{\n    size_t      len =  musl_strlen((char *)(str)) ;\n\n    if (str_m <= len)\n    {\n        return 0;\n    }\n    return str_m - len;\n}\n\n"
	z22Anchor  = "static int      last_sourcing_lnum = 0;\n"
	z22lit1    = "static int vim_snprintf(char *str, size_t str_m, const char *fmt, ...);\n\n"
	z22lit2    = "static int smsg(const char *, ...)  __attribute__((cold))   __attribute__((format(printf, 1, 2))) ;\n"
	z22lit3    = "static int smsg_attr(int, const char *, ...)  __attribute__((format(printf, 2, 3))) ;\n"
	z22lit4    = "static int semsg(const char *, ...)  __attribute__((cold))   __attribute__((format(printf, 1, 2))) ;\n"
	z22lit5    = "static void siemsg(const char *, ...)  __attribute__((cold))   __attribute__((format(printf, 1, 2))) ;\n"
	z22lit6    = "static int vim_snprintf_add(char *, size_t, const char *, ...)  __attribute__((format(printf, 3, 4))) ;\n"
	z22lit7    = "static size_t vim_snprintf_safelen(char *, size_t, const char *, ...)  __attribute__((format(printf, 3, 4))) ;\n"
	z22lit8    = "static int vim_snprintf(char *, size_t, const char *, ...)  __attribute__((format(printf, 3, 4))) ;\n"
	z22lit9    = "static int vim_snprintf(char *, size_t, const char *, ...)  __attribute__((format(printf, 3, 4))) ;\nstatic int emsg_not_now(void);\nstatic size_t iobuff_room(void);\nstatic size_t emsg_iobuff_room(void);\nstatic char *iobuff_or(const char *s);\nstatic size_t safelen_result(char *str, size_t str_m, int str_l);\nstatic size_t append_room(char *str, size_t str_m);\n"
)
