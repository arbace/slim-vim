package edit

// pipes/zero36-edit.sh's own three literals, EXTRACTED by an AST walk rather
// than retyped: the two declarations the phase takes out of the core's block,
// the prototype it adds at the end of the core -> host run, and the definition
// it puts INSIDE the host region.
var z36Go = []string{"int getpid(void);", "int kill(int pid, int sig);"}

const (
	z36Proto = "static void host_raise(int sig);"
	z36Def   = "    static void\nhost_raise(int sig)\n{\n    kill(getpid(), sig);\n}\n\n"
)
