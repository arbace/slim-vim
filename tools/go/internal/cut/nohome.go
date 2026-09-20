package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
	"slimvim.local/tools/internal/dead"
)

// homeReplaceCopy is what home_replace becomes: a bounded copy.
const homeReplaceCopy = `    size_t len;

    // A name is shown as what it is.  This was the shortening of a path under
    // $HOME to ~/..., and its thirteen callers are every place that displays a
    // file name to the user; they keep working, and see the name unchanged.
    if (src == NULL)
    {
        *dst = NUL;
        return 0;
    }
    len =  strlen((char *)(src)) ;
    if (len >= (size_t)dstlen)
    {
        len = (size_t)dstlen - 1;
    }
     memmove((char *)(dst), (char *)(src), len) ;
    dst[len] = NUL;
    return len;`

const tildeArmHead = "            if (*src != '~')"

// atStartEdits are the pieces of `at_start`, which existed only to know
// whether ~ began a path.
//
// Scoped to expand_env_esc: `at_start` is ALSO a static in the regexp engine
// and a local in two other functions, and -Wunused-but-set-variable is not a
// shape deadsweep deletes -- it is assigned, so nothing calls it unused.
var atStartEdits = []struct{ pat, what string }{
	{`(?m)^[ \t]*int[ \t]*at_start = TRUE;\n`, "its declaration"},
	{`(?m)^[ \t]*at_start = FALSE;\n`, "the reset"},
	{`(?m)[ \t]*else if \(\(src\[0\] == ' ' \|\| src\[0\] == ','\) && !one\)\n` +
		`[ \t]*\{\n[ \t]*at_start = TRUE;\n[ \t]*\}\n`, "the separator arm"},
	{`(?m)[ \t]*if \(startstr != NULL[^\n]*\n[ \t]*\{\n` +
		`[ \t]*at_start = TRUE;\n[ \t]*\}\n`, "the startstr arm"},
	// startstr_len was computed for that arm alone.  The `startstr` PARAMETER
	// stays -- callers pass it and -Wno-unused-parameter means gcc will not
	// say so -- but the length it was measured for is gone.
	{`(?m)^[ \t]*int[ \t]*startstr_len = 0;\n`, "startstr_len's declaration"},
	{`(?m)^[ \t]*if \(startstr != NULL\)\n[ \t]*\{\n` +
		`[ \t]*startstr_len = \(int\) strlen\(\(char \*\)\(startstr\)\) ;\n` +
		`[ \t]*\}\n\n?`, "startstr_len's one assignment"},
}

var (
	initHomedir  = regexp.MustCompile(`(?m)^[ \t]*init_homedir\(\);\n`)
	tildeArm2    = regexp.MustCompile(`^\n[ \t]*else if \(  src\[1\] == NUL`)
	tildeArm3    = regexp.MustCompile(`^\n[ \t]*else\n`)
	dollarTilde  = regexp.MustCompile(`\(\*src == '\$'\) \|\| \(\*src == '~' && at_start\)`)
	expandUser   = regexp.MustCompile(`[ \t]*\{EXPAND_USER, get_users, TRUE, FALSE\},\n`)
	userNameHead = `^[ \t]*if \(\*xp->xp_pattern == '~'\)$`
)

// NoHome takes $HOME out of the editor: the value, the shortening, the
// expansion and the user database.
func NoHome(text []byte, w io.Writer) ([]byte, error) {
	if !initHomedir.Match(text) {
		return nil, fmt.Errorf("nohome: common_init_2 no longer calls init_homedir")
	}
	text, _ = replaceFirst(initHomedir, text, "")
	fmt.Fprintln(w, "  nohome       $HOME, read once at startup")

	ho, hc, found, _ := cutil.Body(text, "home_replace")
	if !found {
		return nil, fmt.Errorf("nohome: home_replace is not defined at file scope")
	}
	was := bytes.Count(text[ho:hc], []byte{'\n'})
	var hbuf []byte
	hbuf = append(hbuf, text[:ho]...)
	hbuf = append(hbuf, "{\n"...)
	hbuf = append(hbuf, homeReplaceCopy...)
	hbuf = append(hbuf, "\n}"...)
	text = append(hbuf, text[hc+1:]...)
	fmt.Fprintf(w, "  nohome       home_replace was %d lines, and now shows a name as "+
		"it is\n", was)

	// The `$VAR` arm is kept and the two `~` arms go, so the chain
	// `if (*src != '~') A else if (...) B else C` becomes just A.  Brace
	// matched, because each arm holds inner blocks.
	var err error
	blanked := cutil.Blank(text)
	k := bytes.Index(text, []byte(tildeArmHead))
	if k < 0 {
		return nil, fmt.Errorf("nohome: expand_env_esc's ~ chain is not where this expects")
	}
	o1 := k + bytes.IndexByte(blanked[k:], '{')
	c1 := cutil.Match(blanked, o1)
	if c1 < 0 {
		return nil, fmt.Errorf("nohome: expand_env_esc's first arm is unbalanced")
	}
	m2 := tildeArm2.FindIndex(text[c1+1:])
	if m2 == nil {
		return nil, fmt.Errorf("nohome: expand_env_esc's ~ arm is not where this expects")
	}
	o2 := c1 + 1 + m2[1] + bytes.IndexByte(blanked[c1+1+m2[1]:], '{')
	c2 := cutil.Match(blanked, o2)
	if c2 < 0 {
		return nil, fmt.Errorf("nohome: expand_env_esc's ~ arm is unbalanced")
	}
	m3 := tildeArm3.FindIndex(text[c2+1:])
	if m3 == nil {
		return nil, fmt.Errorf("nohome: expand_env_esc's ~user arm is not where this expects")
	}
	o3 := c2 + 1 + m3[1] + bytes.IndexByte(blanked[c2+1+m3[1]:], '{')
	c3 := cutil.Match(blanked, o3)
	if c3 < 0 {
		return nil, fmt.Errorf("nohome: expand_env_esc's ~user arm is unbalanced")
	}
	body := cutil.Dedent4(text[o1+bytes.IndexByte(text[o1:], '\n')+1 : bytes.LastIndexByte(text[:c1], '\n')+1])
	var buf []byte
	buf = append(buf, text[:k]...)
	buf = append(buf, body...)
	text = append(buf, bytes.TrimLeft(text[c3+1:], "\n")...)
	fmt.Fprintln(w, "  nohome       ~/ and ~user in expand_env_esc; its $VAR half stays")

	var ok bool
	if text, ok = replaceFirst(dollarTilde, text, `*src == '$'`); !ok {
		return nil, fmt.Errorf("nohome: the $ / ~ trigger is not where this expects")
	}
	fmt.Fprintln(w, "  nohome       ~ stops starting an expansion at all")

	blanked = cutil.Blank(text)
	defs := dead.FuncDefinitions(text, blanked)
	span, found := defs["expand_env_esc"]
	if !found {
		return nil, fmt.Errorf("nohome: expand_env_esc is not defined at file scope")
	}
	seg := text[span[0]:span[1]]
	for _, e := range atStartEdits {
		var hit bool
		seg, hit = replaceFirst(regexp.MustCompile(e.pat), seg, "")
		if !hit {
			return nil, fmt.Errorf("nohome: at_start -- %s is not where this expects", e.what)
		}
	}
	var rebuilt []byte
	rebuilt = append(rebuilt, text[:span[0]]...)
	rebuilt = append(rebuilt, seg...)
	text = append(rebuilt, text[span[1]:]...)
	fmt.Fprintln(w, "  nohome       at_start, which existed only to know whether ~ began a path")

	if n := len(expandUser.FindAll(text, -1)); n != 1 {
		return nil, fmt.Errorf("nohome: expected one EXPAND_USER completion row, got %d", n)
	}
	text = expandUser.ReplaceAll(text, nil)

	// And the context that reaches it.  Removing the completion row alone
	// leaves match_user() called from set_context_for_wildcard_arg(), and
	// match_user() is what walks the password database -- so the five pw
	// symbols stayed until this went too.
	if text, err = cutil.DropIf(text, "(?m)"+userNameHead, 1); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  nohome       ~user completion, and the context that reaches it")

	// get_user_name() answers who this is, for a swap file's block zero.
	// There are no swap files; the block is still built in memory, and it can
	// be built without a name.  This is the last reader of getpwuid.
	go_, gc, found, _ := cutil.Body(text, "get_user_name")
	if !found {
		return nil, fmt.Errorf("nohome: get_user_name is not defined at file scope")
	}
	var gbuf []byte
	gbuf = append(gbuf, text[:go_]...)
	gbuf = append(gbuf, "{\n    return FAIL;\n}"...)
	text = append(gbuf, text[gc+1:]...)
	fmt.Fprintln(w, "  nohome       who this is, which only a swap file wanted to know")

	fmt.Fprintf(w, "  nohome       %d homedir mentions left for the sweep\n",
		bytes.Count(text, []byte("homedir")))
	return text, nil
}
