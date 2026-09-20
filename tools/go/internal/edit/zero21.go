package edit

import (
	"bytes"
	"io"
	"regexp"
	"strings"
)

func init() { register("zero21", Zero21) }

var z21Stmt = regexp.MustCompile(`(?m)^\s*(?:printf|fprintf|fflush)\(`)

// Zero21 makes the messages the editor's and the writing the host's: twenty
// output statements in five functions become eight calls through one
// vim_host_message(msg, len, err) the launcher installs, with <stdio.h> and
// seven symbols going with them.
func Zero21(text []byte, w io.Writer) ([]byte, error) {
	p := ph{"message", w}
	t := text

	mentions := func(text []byte, name string) int {
		return len(regexp.MustCompile(`\b`+name+`\b`).FindAll(text, -1))
	}
	// sub is the heredoc's own, and its refusal quotes the needle's FIRST
	// line stripped and truncated at 70 -- which is what makes a refusal
	// readable when the needle is a fifteen-line function body.
	sub := func(old, new string, n int, tag string) error {
		c := bytes.Count(t, []byte(old))
		if c != n {
			head := strings.SplitN(strings.TrimSpace(old), "\n", 2)[0]
			if len(head) > 70 {
				head = head[:70]
			}
			return p.die("%s: `%s` occurs %d times, expected %d", tag, head, c, n)
		}
		t = bytes.ReplaceAll(t, []byte(old), []byte(new))
		return nil
	}

	linesBefore := p.lines(t)
	runsBefore := p.blankRuns(t)

	// ---- 0. this is the file the phase was written against ---------------
	// Counted on the INPUT, so a later phase that moved one of these fails
	// here and not in the middle of a cut.  `fprintf` is 16 and not the
	// brief's 17, and `stderr` 17 and not 18, because phase 20 took nv_esc's
	// with the out_redir arm.
	for _, x := range []struct {
		name string
		want int
	}{
		{"fprintf", 16}, {"stderr", 17}, {"fflush", 1}, {"printf", 13},
		{"errno", 3}, {"msg_use_printf", 6}, {"msg_puts_printf", 3},
		{"info_message", 9}, {"vim_host_exit", 3}, {"host_exit", 2},
		{"FILE", 0}, {"stdout", 0},
	} {
		if k := mentions(t, x.name); k != x.want {
			return nil, p.die("the input has %d mentions of `%s`, expected %d -- this is not the "+
				"tree this phase was written against", k, x.name, x.want)
		}
	}
	for _, name := range []string{"vim_host_message", "host_message", "message_fn"} {
		if k := mentions(t, name); k != 0 {
			return nil, p.die("`%s` already has %d mentions -- a name this phase introduces is "+
				"taken", name, k)
		}
	}
	if k := len(z21Stmt.FindAll(t, -1)); k != 20 {
		return nil, p.die("%d statements begin with printf(, fprintf( or fflush(, expected the 20 "+
			"the inventory names -- 4 in msg_puts_printf, 2 in exit_scroll, 7 in "+
			"report_term_error, 1 in set_termname and 6 in mainerr", k)
	}
	if bytes.Count(t, []byte("#include <stdio.h>\n")) != 1 {
		return nil, p.die("<stdio.h> is not included exactly once, so the directive this phase " +
			"removes is not the one it was written against")
	}
	p.say("the input is r20: 20 statements put bytes on a stream -- `fprintf` 16, " +
		"`printf` 13 words of which THREE are calls, `fflush` 1 -- and `FILE` and " +
		"`stdout` are both at 0, which phase 13 is what left")

	// ---- 1. the pointer, at the top, because its readers are scattered ---
	// A file-scope OBJECT and not a prototype: CLAUDE.md's rule is that
	// objects do not inherit linkage from a declaration, so the keyword is
	// written here and is why `nm --extern-only` still prints one name.
	// Phase 19 put `vim_host_exit` immediately above its one reader; this one
	// has EIGHT, the earliest of them 37,000 lines up, so it goes with the
	// two musl_ prototypes that are already the file's boundary declarations.
	if err := sub("static int musl_towupper(int a);\nstatic int musl_towlower(int a);\n",
		"static int musl_towupper(int a);\nstatic int musl_towlower(int a);\n\n"+
			"static void (*vim_host_message)(const char *msg, int len, int err);\n",
		1, "P1"); err != nil {
		return nil, err
	}

	// ---- 2. msg_puts_printf, four sites, one for one ---------------------
	// The `if (info_message)` shape is KEPT rather than folded to
	// `!info_message`, so this phase changes which primitive writes and
	// nothing about which stream is chosen.  It is also what keeps
	// `info_message` at 9 mentions, which is the anchor that says so.
	if err := sub(`                if (info_message)
                {
                     printf("%s", ((char *)buf)) ;
                }
                else
                {
                     fprintf(stderr, "%s", ((char *)buf)) ;
                }
`, `                if (info_message)
                {
                    vim_host_message((char *)buf, -1, FALSE);
                }
                else
                {
                    vim_host_message((char *)buf, -1, TRUE);
                }
`, 1, "M1"); err != nil {
		return nil, err
	}
	if err := sub(`            if (info_message)
            {
                 printf("%s", ((char *)p)) ;
            }
            else
            {
                 fprintf(stderr, "%s", ((char *)p)) ;
            }
`, `            if (info_message)
            {
                vim_host_message((char *)p, -1, FALSE);
            }
            else
            {
                vim_host_message((char *)p, -1, TRUE);
            }
`, 1, "M2"); err != nil {
		return nil, err
	}

	// ---- 3. exit_scroll, two sites, one for one --------------------------
	if err := sub(`            if (info_message)
            {
                 printf("%s", ("\n")) ;
            }
            else
            {
                 fprintf(stderr, "%s", ("\r\n")) ;
            }
`, `            if (info_message)
            {
                vim_host_message("\n", -1, FALSE);
            }
            else
            {
                vim_host_message("\r\n", -1, TRUE);
            }
`, 1, "E1"); err != nil {
		return nil, err
	}

	// ---- 4. report_term_error, seven statements into one -----------------
	// It runs from set_termname from termcapinit, which is the function that
	// sets `full_screen = TRUE` afterwards -- so this message is emitted
	// while there is no screen at all, which is the literal reading of
	// ZERO-PLAN.md 4c's "the messages that appear before there is a screen".
	if err := sub(`report_term_error(char *error_msg, char_u *term)
{
     fprintf(stderr, "%s", ("\r\n")) ;
    if (error_msg != NULL)
    {
         fprintf(stderr, "%s", (error_msg)) ;
         fprintf(stderr, "%s", ("\r\n")) ;
    }
     fprintf(stderr, "%s", ("'")) ;
     fprintf(stderr, "%s", ((char *)term)) ;
     fprintf(stderr, "%s", (_("' not known, defaulting to 'xterm'"))) ;
     fprintf(stderr, "%s", ("\r\n")) ;
}
`, `report_term_error(char *error_msg, char_u *term)
{
    char        buf[1024];

    if (error_msg != NULL)
    {
        vim_snprintf(buf, sizeof(buf), "\r\n%s\r\n'%s%s\r\n", error_msg, (char *)term, _("' not known, defaulting to 'xterm'"));
    }
    else
    {
        vim_snprintf(buf, sizeof(buf), "\r\n'%s%s\r\n", (char *)term, _("' not known, defaulting to 'xterm'"));
    }
    vim_host_message(buf, -1, TRUE);
}
`, 1, "R1"); err != nil {
		return nil, err
	}

	// ---- 5. the fflush, which is NOT where a reader expects it -----------
	// It is in set_termname, eleven lines BELOW the report_term_error() call
	// and after set_string_option_direct("term", ...).  A phase that read
	// "seven fprintf and one fflush in report_term_error" would edit the
	// wrong function; it is anchored on its neighbour above so that it cannot
	// be taken from anywhere else.
	if err := sub(`                set_string_option_direct((char_u *)"term", -1, term, OPT_FREE, 0);
                 fflush(stderr) ;
`, `                set_string_option_direct((char_u *)"term", -1, term, OPT_FREE, 0);
`, 1, "F1"); err != nil {
		return nil, err
	}

	// ---- 6. mainerr, six statements into one -----------------------------
	// A LOCAL buffer and not IObuff: mainerr runs from command_line_scan,
	// after common_init_1/common_init_2, and IObuff's state there is not this
	// phase's business.  The blank line after the opening brace becomes the
	// declaration, which is what CLAUDE.md's "no blank line after an opening
	// brace" wanted anyway.
	if err := sub(`mainerr(int         n, char_u      *str)
{

    init_longVersion();
     fprintf(stderr, "%s", (longVersion)) ;
     fprintf(stderr, "%s", ("\n")) ;
     fprintf(stderr, "%s", (_(main_errors[n]))) ;
    if (str != NULL)
    {
         fprintf(stderr, "%s", (": \"")) ;
         fprintf(stderr, "%s", ((char *)str)) ;
         fprintf(stderr, "%s", ("\"")) ;
    }

    mch_exit(1);
}
`, `mainerr(int         n, char_u      *str)
{
    char        buf[1024];

    init_longVersion();
    if (str != NULL)
    {
        vim_snprintf(buf, sizeof(buf), "%s\n%s: \"%s\"", longVersion, _(main_errors[n]), (char *)str);
    }
    else
    {
        vim_snprintf(buf, sizeof(buf), "%s\n%s", longVersion, _(main_errors[n]));
    }
    vim_host_message(buf, -1, TRUE);

    mch_exit(1);
}
`, 1, "A1"); err != nil {
		return nil, err
	}

	// ---- 7. the host installs it, through a parameter and not a global ---
	if err := sub(`    static int
vim_main(int argc, char **argv, void (*exit_fn)(int))
{

    vim_host_exit = exit_fn;
`, `    static int
vim_main(int argc, char **argv, void (*exit_fn)(int), void (*message_fn)(const char *, int, int))
{

    vim_host_exit = exit_fn;
    vim_host_message = message_fn;
`, 1, "V1"); err != nil {
		return nil, err
	}

	// ---- 8. the launcher -------------------------------------------------
	// host_message() goes beside host_exit(), which is where phase 19 put the
	// other half of this boundary, and main() stays the last thing in the
	// file (CLAUDE.md).  `len < 0` means NUL-terminated; every one of today's
	// eight call sites passes -1, and the parameter is there because the host
	// should not have to scan and because vim_snprintf returns the exact
	// length for free at the two sites that assemble.  THE LAUNCHER MAY CALL
	// musl_strlen: it is in the same translation unit, it is the host's own
	// code, and at the split it goes into the host file with it.
	const old = `static void *host_jump[5];
static int host_code;

    static void
host_exit(int r)
{
    host_code = r;
    __builtin_longjmp(host_jump, 1);
}

    int
main(int argc, char **argv)
{
    if (__builtin_setjmp(host_jump) != 0)
    {
        return host_code;
    }
    return vim_main(argc, argv, host_exit);
}
`
	const new = `static void *host_jump[5];
static int host_code;

    static void
host_exit(int r)
{
    host_code = r;
    __builtin_longjmp(host_jump, 1);
}

    static void
host_message(const char *msg, int len, int err)
{
    int         n = len;
    int         off = 0;

    if (n < 0)
    {
        n = (int)musl_strlen(msg);
    }
    while (off < n)
    {
        int w = (int)write(err ? 2 : 1, msg + off, (size_t)(n - off));

        if (w <= 0)
        {
            return;
        }
        off += w;
    }
}

    int
main(int argc, char **argv)
{
    if (__builtin_setjmp(host_jump) != 0)
    {
        return host_code;
    }
    return vim_main(argc, argv, host_exit, host_message);
}
`
	if !bytes.HasSuffix(t, []byte(old)) {
		return nil, p.die("zero-vim.c does not end with phase 19's twenty-line launcher, so this " +
			"is not the file this phase was written against")
	}
	t = append(append([]byte(nil), t[:len(t)-len(old)]...), new...)

	// ---- 9. the header the symbols came from -----------------------------
	// ZERO-GOAL.md's charter: a phase may REMOVE a directive and may never add
	// one.  This is the second removal in the pipeline; phase 16 was the
	// first, and made the argument.
	if err := sub("#include <stdio.h>\n", "", 1, "H1"); err != nil {
		return nil, err
	}

	// ---- what the file is now --------------------------------------------
	for _, name := range []string{"fprintf", "stderr", "fflush"} {
		if k := mentions(t, name); k != 0 {
			return nil, p.die("`%s` still has %d mentions", name, k)
		}
	}
	if len(z21Stmt.FindAll(t, -1)) > 0 {
		return nil, p.die("a statement still begins with printf(, fprintf( or fflush(")
	}
	for _, x := range []struct {
		name string
		want int
		why  string
	}{
		{"printf", 10, "the counting trap: nine `format(printf, ...)` attributes and " +
			"the string \"E767: Too many arguments for printf()\".  NONE is a " +
			"call, and `assert printf at 0` fails on a correct phase"},
		{"vim_host_message", 10, "the declaration, the installation in vim_main and the " +
			"EIGHT call sites -- 4 in msg_puts_printf, 2 in " +
			"exit_scroll, 1 in report_term_error, 1 in mainerr"},
		{"host_message", 2, "the launcher's definition and the argument main() passes.  " +
			"`vim_host_message` is a DIFFERENT word and \\b does not " +
			"match inside it, which is why these two counts are " +
			"separate -- phase 19 learnt that with host_exit"},
		{"vim_host_exit", 3, "phase 19's, untouched"},
		{"host_exit", 2, "phase 19's, untouched"},
		{"msg_use_printf", 6, "a prototype, a definition and four call sites -- " +
			"UNTOUCHED, and deliberately: it returns TRUE 23 times in " +
			"106 records"},
		{"msg_puts_printf", 3, "a prototype, a definition and one call -- all 75 lines " +
			"stay, and only what they call changes"},
		{"info_message", 9, "untouched, because the four sites that read it kept their " +
			"`if (info_message)` shape"},
		{"errno", 3, "phase 21 is not the errno phase: the #include and two uses, both " +
			"inside phase 20's host block"},
		{"vim_snprintf", 73, "FOUR more than the input -- the two multi-part speakers " +
			"each assemble in two arms, with the only formatter the " +
			"file has had since phase 14"},
		{"musl_strlen", 134, "one more than the input: host_message's, in the len < 0 " +
			"arm"},
	} {
		if k := mentions(t, x.name); k != x.want {
			return nil, p.die("`%s` has %d mentions, expected %d -- %s", x.name, k, x.want, x.why)
		}
	}
	var d [][]byte
	for _, l := range bytes.Split(t, []byte{'\n'}) {
		if bytes.HasPrefix(l, []byte("#")) {
			d = append(d, l)
		}
	}
	okInc := len(d) == 11
	for _, l := range d {
		if !bytes.HasPrefix(l, []byte("#include <")) {
			okInc = false
		}
	}
	if !okInc {
		return nil, p.die("the output does not have exactly ELEVEN #include directives and nothing " +
			"else -- this phase removes <stdio.h> and adds none")
	}
	if k := p.blankRuns(t); k != runsBefore {
		return nil, p.die("the edit left %d runs of two blank lines where there were %d",
			k, runsBefore)
	}
	p.sayf("%d -> %d lines.  Every byte that leaves this editor other than the screen "+
		"goes through one `vim_host_message(msg, len, err)` the launcher installs; "+
		"<stdio.h> is gone and the directive count is 11", linesBefore, p.lines(t))
	return t, nil
}
