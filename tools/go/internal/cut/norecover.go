package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

const relativeTime = `    // How long ago, not when.  Phase 20 took away every way this editor could
    // be told what zone the clock is in, and undo history does not outlive the
    // process -- :wundo and :rundo are ex_ni -- so every time this formats is
    // within one session, which is exactly what "ago" measures.
    long seconds = (long)(vim_time() - tt);

    vim_snprintf((char *)buf, buflen, NGETTEXT("%ld second ago", "%ld seconds ago", seconds), seconds);`

var recoverymodeWord = regexp.MustCompile(`\brecoverymode\b`)

// recoverBlock returns the start-of-line, opening brace and closing brace for
// the `if` that pattern matches.
func recoverBlock(text []byte, pattern string) (k, o, c int, err error) {
	blanked := cutil.Blank(text)
	m := regexp.MustCompile(pattern).FindIndex(text)
	if m == nil {
		return 0, 0, 0, fmt.Errorf("norecover: no match for %s", cutil.PyRepr(pattern))
	}
	k = bytes.LastIndexByte(text[:m[0]], '\n') + 1
	o = m[1] + bytes.IndexByte(blanked[m[1]:], '{')
	c = cutil.Match(blanked, o)
	if c < 0 {
		return 0, 0, 0, fmt.Errorf("norecover: unbalanced block for %s", cutil.PyRepr(pattern))
	}
	return k, o, c, nil
}

// unwrapIf keeps the body of an `if` whose condition is now always true.
func unwrapIf(text []byte, pattern, what string, w io.Writer) ([]byte, error) {
	k, o, c, err := recoverBlock(text, pattern)
	if err != nil {
		return nil, err
	}
	tail := text[c+1:]
	if len(tail) > 39 {
		tail = tail[:39]
	}
	if regexp.MustCompile(`^[ \t]*\n[ \t]*else\b`).Match(tail) {
		return nil, fmt.Errorf("norecover: %s -- the block has an else", what)
	}
	body := cutil.Dedent4(text[o+bytes.IndexByte(text[o:], '\n')+1 : bytes.LastIndexByte(text[:c], '\n')+1])
	end := c + bytes.IndexByte(text[c:], '\n') + 1
	fmt.Fprintf(w, "  norecover    %s, %d lines that always ran\n",
		what, bytes.Count(text[k:end], []byte{'\n'}))
	out := make([]byte, 0, len(text))
	out = append(out, text[:k]...)
	out = append(out, body...)
	return append(out, text[end:]...), nil
}

// keepElse keeps the `else` body of an `if` whose condition is now always false.
func keepElse(text []byte, pattern, what string, w io.Writer) ([]byte, error) {
	k, _, c, err := recoverBlock(text, pattern)
	if err != nil {
		return nil, err
	}
	m := regexp.MustCompile(`^[ \t]*\n[ \t]*else\n`).FindIndex(text[c+1:])
	if m == nil {
		return nil, fmt.Errorf("norecover: %s -- no else to keep", what)
	}
	blanked := cutil.Blank(text)
	o2 := c + 1 + m[1] + bytes.IndexByte(blanked[c+1+m[1]:], '{')
	c2 := cutil.Match(blanked, o2)
	if c2 < 0 {
		return nil, fmt.Errorf("norecover: %s -- the else block is unbalanced", what)
	}
	body := cutil.Dedent4(text[o2+bytes.IndexByte(text[o2:], '\n')+1 : bytes.LastIndexByte(text[:c2], '\n')+1])
	end := c2 + bytes.IndexByte(text[c2:], '\n') + 1
	fmt.Fprintf(w, "  norecover    %s, and the %d lines it guarded\n",
		what, bytes.Count(text[k:c], []byte{'\n'})+1)
	out := make([]byte, 0, len(text))
	out = append(out, text[:k]...)
	out = append(out, body...)
	return append(out, text[end:]...), nil
}

// NoRecover takes recovery away: nothing can set recoverymode any more.
func NoRecover(text []byte, w io.Writer) ([]byte, error) {
	text, err := cutCounted(text,
		`(?m)[ \t]*case 'r':\n[ \t]*case 'L':\n`+
			`[ \t]*recoverymode = 1;\n[ \t]*break;\n\n?`,
		"norecover", "-r and -L in command_line_scan", 1)
	if err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  norecover    -r and -L, the only two things that set recoverymode")

	for _, name := range []string{"swapfile_info", "recover_names", "ml_recover"} {
		before := bytes.Count(text, []byte{'\n'})
		var ok bool
		if text, ok = cutil.DeleteDefinition(text, name); !ok {
			return nil, fmt.Errorf("norecover: %s is not defined at file scope", name)
		}
		fmt.Fprintf(w, "  norecover    %s, %d lines\n",
			name, before-bytes.Count(text, []byte{'\n'}))
	}

	if text, err = cutil.DropIf(text,
		`(?m)^[ \t]*if \(recoverymode && params\.fname == NULL\)$`, 2); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  norecover    the two `-r with no file` arms of main and vim_main2")

	var hit bool
	if text, hit = replaceFirst(
		regexp.MustCompile(`(?m)if \(params\.edit_type == EDIT_STDIN && !recoverymode\)`),
		text, "if (params.edit_type == EDIT_STDIN)"); !hit {
		return nil, fmt.Errorf("norecover: the stdin arm of vim_main2 is not where this expects")
	}
	fmt.Fprintln(w, "  norecover    reading stdin stops asking whether this is a recovery")

	if text, err = keepElse(text, `(?m)^[ \t]*if \(recoverymode\)$`,
		"the recovery arm of create_windows", w); err != nil {
		return nil, err
	}

	// readfile() had to know whether it was filling a buffer from a swap file
	// rather than from the file itself.  It never is.
	if text, hit = replaceFirst(
		regexp.MustCompile(`(?m)if \(!recoverymode && !filtering && !\(flags & READ_DUMMY\)\)`),
		text, "if (!filtering && !(flags & READ_DUMMY))"); !hit {
		return nil, fmt.Errorf("norecover: readfile's `reading from stdin` message is not " +
			"where this expects")
	}
	if text, err = unwrapIf(text, `(?m)^[ \t]*if \(!recoverymode\)$`,
		"readfile's redraw and line count", w); err != nil {
		return nil, err
	}
	if text, err = unwrapIf(text, `(?m)^[ \t]*if \(!\(recoverymode && error\)\)$`,
		"readfile's return value", w); err != nil {
		return nil, err
	}

	o, c, found, balanced := cutil.Body(text, "add_time")
	if !found || !balanced {
		return nil, fmt.Errorf("norecover: add_time is not defined at file scope")
	}
	var buf []byte
	buf = append(buf, text[:o]...)
	buf = append(buf, "{\n"...)
	buf = append(buf, relativeTime...)
	buf = append(buf, "\n}"...)
	text = append(buf, text[c+1:]...)
	fmt.Fprintln(w, "  norecover    add_time says how long ago, not when; localtime_r and "+
		"strftime go with it")

	fmt.Fprintf(w, "  norecover    %d recoverymode mentions left for the sweep\n",
		len(recoverymodeWord.FindAll(text, -1)))
	return text, nil
}
