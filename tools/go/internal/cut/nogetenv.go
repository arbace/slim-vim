package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

// envCopy is expand_env_esc with the $ arm gone.  Written out rather than cut,
// because what survives is the loop's tail and it reads better as its own
// function than as a `copy_char` flag that is now always true.
const envCopy = `    char_u      *src;
    char_u      *dst_start = dst;

    // $VAR is part of a name, not a place to look one up.  There is no
    // environment to ask, so what is left of this is the escape handling and
    // the bound on dstlen: a name reaches its caller as it was written.
    src = skipwhite(srcp);
    --dstlen;
    while (*src && dstlen > 0)
    {
        if (src[0] == '\\' && src[1] != NUL)
        {
            *dst++ = *src++;
            --dstlen;
        }
        if (dstlen > 0)
        {
            *dst++ = *src++;
            --dstlen;
        }
    }
    *dst = NUL;

    return (size_t)(dst - dst_start);`

const localAdditions = "    fname = gettail(curbuf->b_fname);\n" +
	`    if ( vim_fnamecmp((char_u *)(fname), (char_u *)("help.txt"))  == 0)`

var envLeft = regexp.MustCompile(`\bgetenv\b|\bsetenv\b|\benviron\b`)

// envBody replaces a file-scope definition's body and reports its line count.
func envBody(text []byte, name, replacement string) ([]byte, int, error) {
	o, c, found, balanced := cutil.Body(text, name)
	if !found || !balanced {
		return nil, 0, fmt.Errorf("nogetenv: %s is not defined at file scope", name)
	}
	was := bytes.Count(text[o:c], []byte{'\n'})
	out := make([]byte, 0, len(text))
	out = append(out, text[:o]...)
	out = append(out, "{\n"...)
	out = append(out, replacement...)
	out = append(out, "\n}"...)
	return append(out, text[c+1:]...), was, nil
}

// NoGetEnv takes the environment away: nothing the editor does is decided by a
// variable any more.
func NoGetEnv(text []byte, w io.Writer) ([]byte, error) {
	text, was, err := envBody(text, "expand_env_esc", envCopy)
	if err != nil {
		return nil, err
	}
	fmt.Fprintf(w, "  nogetenv     expand_env_esc was %d lines, and now copies a name\n", was)

	if text, err = cutCounted(text,
		`(?m)^[ \t]*if \(!mch_isFullName\(pat\)\)\n[ \t]*\{\n`+
			`[ \t]*path = vim_getenv\(\(char_u \*\)"PATH", &mustfree\);\n[ \t]*\}\n`,
		"nogetenv", "$PATH in expand_shellcmd", 1); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  nogetenv     $PATH, which was where a command name was looked for")

	// Phase 1 folded `vimruntime` to FALSE inside vim_getenv, so `rt` here has
	// been NULL since then and the block has added nothing.  It goes rather
	// than staying to look like it might.
	blanked := cutil.Blank(text)
	k := bytes.Index(text, []byte(localAdditions))
	if k < 0 {
		return nil, fmt.Errorf("nogetenv: the local-additions scan is not where this expects")
	}
	o := k + 40 + bytes.IndexByte(blanked[k+40:], '{')
	c := cutil.Match(blanked, o)
	if c < 0 {
		return nil, fmt.Errorf("nogetenv: the local-additions scan is unbalanced")
	}
	end := c + bytes.IndexByte(text[c:], '\n') + 1
	fmt.Fprintf(w, "  nogetenv     the local-additions scan, %d lines that $VIMRUNTIME "+
		"being unset had already made a no-op\n", bytes.Count(text[k:end], []byte{'\n'}))
	var buf []byte
	buf = append(buf, text[:k]...)
	text = append(buf, text[end:]...)

	for _, d := range []struct{ name, call string }{
		{"set_init_default_shell", "$SHELL for 'shell'"},
		{"set_init_default_cdpath", "$CDPATH for 'cdpath'"},
	} {
		var ok bool
		if text, ok = cutil.DeleteDefinition(text, d.name); !ok {
			return nil, fmt.Errorf("nogetenv: %s is not defined at file scope", d.name)
		}
		if text, err = cutCounted(text, `(?m)^[ \t]*`+d.name+`\(\);\n`,
			"nogetenv", "the call to "+d.name, 1); err != nil {
			return nil, err
		}
		fmt.Fprintf(w, "  nogetenv     %s\n", d.call)
	}

	if text, err = cutil.DropIf(text,
		`(?m)^[ \t]*if \( \(char_u \*\)getenv\(\(char \*\)\(\(char_u \*\)"VIM_POSIX"\)\)  != NULL\)$`,
		1); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  nogetenv     $VIM_POSIX, which chose a stricter 'cpoptions'")

	// 'backupskip' was $TMPDIR, $TEMP, $TMP and always /tmp.  Three of the four
	// cannot contribute now, so the table goes and the loop runs its one pass;
	// `i` is left for the sweep.
	if text, err = cutCounted(text,
		`(?m)^[ \t]*static char \*\(names\[4\]\) = \{"", "TMPDIR", "TEMP", "TMP"\};\n`,
		"nogetenv", "backupskip's table of environment names", 1); err != nil {
		return nil, err
	}
	// The loop's one surviving pass keeps its braces and its `mustfree`, which
	// the tail of the body still frees: the substitution keeps those two
	// groups rather than deleting the whole match.
	loop := regexp.MustCompile(
		`(?m)[ \t]*for \(i = 0; i < \(int\) \(sizeof\(names\) / sizeof\(\(names\)\[0\]\)\) ; \+\+i\)\n` +
			`([ \t]*\{\n[ \t]*int[ \t]+mustfree = FALSE;\n)` +
			`[ \t]*if \(\*names\[i\] == NUL\)\n[ \t]*\{\n` +
			`([ \t]*p = \(char_u \*\)"/tmp";\n[ \t]*plen = \(int\) \(sizeof\("/tmp" ""\) - 1\) ;\n)` +
			`[ \t]*\}\n[ \t]*else\n[ \t]*\{\n` +
			`[ \t]*p = vim_getenv\(\(char_u \*\)names\[i\], &mustfree\);\n` +
			`[ \t]*plen = 0;\n[ \t]*\}\n`)
	var hit bool
	if text, hit = replaceFirst(loop, text, "${1}${2}"); !hit {
		return nil, fmt.Errorf("nogetenv: backupskip's loop over them is not where this expects")
	}
	fmt.Fprintln(w, "  nogetenv     $TMPDIR, $TEMP and $TMP; 'backupskip' keeps /tmp")

	// vimrc_found() is reached only from do_source_ext(), and every do_source()
	// call in the file passes DOSO_NONE -- so these two arms have been dead
	// since Phase 18 stopped sourcing a vimrc.  They are what keep vim_setenv,
	// export_myvimdir and $MYVIMDIR alive.
	if text, err = cutCounted(text,
		`(?m)[ \t]*if \(is_vimrc == DOSO_VIMRC\)\n[ \t]*\{\n`+
			`[ \t]*vimrc_found\(fname_exp, \(char_u \*\)"MYVIMRC"\);\n[ \t]*\}\n`+
			`[ \t]*else if \(is_vimrc == DOSO_GVIMRC\)\n[ \t]*\{\n`+
			`[ \t]*vimrc_found\(fname_exp, \(char_u \*\)"MYGVIMRC"\);\n[ \t]*\}\n\n?`,
		"nogetenv", "the two DOSO_VIMRC arms of do_source_ext", 1); err != nil {
		return nil, err
	}
	if text, err = cutil.DropIf(text, `(?m)^[ \t]*if \(varp == &p_rtp\)$`, 1); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  nogetenv     $VIM, $VIMRUNTIME and $MYVIMDIR stop being published")

	if text, _, err = envBody(text, "did_set_helpfile", "    return NULL;"); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  nogetenv     'helpfile' stops unsetting what it can no longer set")

	if text, err = cutCounted(text, `(?m)[ \t]*\{EXPAND_ENV_VARS, get_env_name, TRUE, TRUE\},\n`,
		"nogetenv", "the EXPAND_ENV_VARS completion row", 1); err != nil {
		return nil, err
	}
	if text, err = cutil.DropIf(text, `(?m)^[ \t]*if \(\*xp->xp_pattern == '\$'\)$`, 1); err != nil {
		return nil, err
	}
	if text, err = cutCounted(text,
		`(?m)[ \t]*\{\(EXPAND_ENV_VARS\), \{\(\(char_u \*\)"environment"\)[^\n]*\n`,
		"nogetenv", "`:command -complete=environment`", 1); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  nogetenv     $VAR completion, and the one mention of environ")

	// No (?m) here: the Python passes flags=0 for this one.
	if text, err = cutCounted(text,
		` \|\| \(\(p =  \(char_u \*\)getenv\(\(char \*\)\(\(char_u \*\)"COLORFGBG"\)\) \) != NULL`+
			` && \(p = vim_strrchr\(p, ';'\)\) != NULL`+
			` && \(\(p\[1\] >= '0' && p\[1\] <= '6'\) \|\| p\[1\] == '8'\) && p\[2\] == NUL\)`,
		"nogetenv", "$COLORFGBG in term_bg_default", 1); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  nogetenv     $COLORFGBG; 'background' is what the table says")

	// The cache existed to avoid calling tzset() on every timestamp.  musl's
	// localtime_r does the zone setup itself, so the call was the cache's only
	// purpose and both go.  libc still reads $TZ in there; this source does not.
	if text, _, err = envBody(text, "vim_localtime", "    return localtime_r(timep, result);"); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  nogetenv     $TZ, and the tzset cache that existed to avoid it")

	fmt.Fprintf(w, "  nogetenv     %d environment mentions left for the sweep\n",
		len(envLeft.FindAll(text, -1)))
	return text, nil
}
