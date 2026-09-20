package edit

// pipes/zero35-edit.sh's own three literals, EXTRACTED by an AST walk rather
// than retyped: the three declarations the phase takes out of the core's block,
// the three prototypes it adds at the end of the core -> host run, and the three
// definitions it puts above the launcher.
var (
	z35Go     = []string{"void *malloc(usize n);", "void free(void *p);", "long write(int fd, const void *buf, usize n);"}
	z35Protos = []string{"static void *host_alloc(usize n);", "static void host_free(void *p);", "static int host_write(const char *s, int len);"}
)

const z35Defs = "    static void *\nhost_alloc(usize n)\n{\n    return malloc(n);\n}\n\n    static void\nhost_free(void *p)\n{\n    free(p);\n}\n\n    static int\nhost_write(const char *s, int len)\n{\n    return (int)write(1, s, (usize)len);\n}\n\n"
