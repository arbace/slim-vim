package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

// nochdirFullName is mch_FullName with the chdir dance gone.
//
// Written as an interpreted string and not a raw one because it CONTAINS
// BACKTICKS, in the comment it carries into the C.  Generated from the
// Python's own constant rather than retyped, so the two cannot drift.
const nochdirFullName = "    int         buflen = 0;\n" +
	"\n" +
	"    // The dance that used to be here chdir'd into the leading directory of a\n" +
	"    // relative name, asked getcwd() where that landed, and chdir'd back -- so\n" +
	"    // that `..` and a symlinked directory were resolved on the way.  Nothing\n" +
	"    // moves this process any more, so a full name is the working directory\n" +
	"    // with the name appended, and a `..` in it survives into the answer.\n" +
	"    //\n" +
	"    // `force` asked for that re-resolution even when the name was already\n" +
	"    // absolute.  There is nothing left to re-resolve, so an absolute name is\n" +
	"    // its own answer -- and prepending the cwd to one was the whole of the\n" +
	"    // first attempt at this, which moved :read, :write and :wq.\n" +
	"    if (!mch_isFullName(fname))\n" +
	"    {\n" +
	"        if (mch_dirname(buf, len) == FAIL)\n" +
	"        {\n" +
	"            *buf = NUL;\n" +
	"            return FAIL;\n" +
	"        }\n" +
	"        buflen = (int) strlen((char *)(buf)) ;\n" +
	"        if (buflen >= len - 1)\n" +
	"        {\n" +
	"            return FAIL;\n" +
	"        }\n" +
	"        if (buflen > 0 && buf[buflen - 1] !=  ((char_u)'/')  && *fname != NUL &&  strcmp((char *)(fname), (char *)(\".\"))  != 0)\n" +
	"        {\n" +
	"             strcpy((char *)(buf + buflen), (char *)( \"/\" )) ;\n" +
	"            buflen += sizeof( ((char_u)'/') );\n" +
	"        }\n" +
	"    }\n" +
	"    else\n" +
	"    {\n" +
	"        *buf = NUL;\n" +
	"    }\n" +
	"\n" +
	"    if ((int)(buflen +  strlen((char *)(fname)) ) >= len)\n" +
	"    {\n" +
	"        return FAIL;\n" +
	"    }\n" +
	"\n" +
	"    if ( strcmp((char *)(fname), (char *)(\".\"))  != 0)\n" +
	"    {\n" +
	"         strcpy((char *)(buf + buflen), (char *)(fname)) ;\n" +
	"    }\n" +
	"\n" +
	"    return OK;"

// nochdirDirname is mch_dirname, asked once.
const nochdirDirname = "    // Asked once.  Nothing can move this process -- :cd, :lcd and :tcd are\n" +
	"    // ex_ni, :! does not fork, and mch_FullName() no longer chdirs -- so every\n" +
	"    // later call is asking the kernel a question whose answer cannot have\n" +
	"    // changed since the first one.\n" +
	"    static char_u   cwd[ PATH_MAX ];\n" +
	"    static int      cwd_len = -1;\n" +
	"\n" +
	"    if (cwd_len < 0)\n" +
	"    {\n" +
	"        if (getcwd((char *)cwd, sizeof(cwd)) == NULL)\n" +
	"        {\n" +
	"             strcpy((char *)(buf), (char *)(strerror(errno))) ;\n" +
	"            return FAIL;\n" +
	"        }\n" +
	"        cwd_len = (int) strlen((char *)(cwd)) ;\n" +
	"    }\n" +
	"    if (cwd_len >= len)\n" +
	"    {\n" +
	"        return FAIL;\n" +
	"    }\n" +
	"     strcpy((char *)(buf), (char *)(cwd)) ;\n" +
	"    return OK;"

// nochdirBody replaces a definition's body and reports its old line count in
// the tool's own column.
func nochdirBody(text []byte, name, replacement, tag string, w io.Writer) ([]byte, error) {
	o, c, found, balanced := cutil.Body(text, name)
	if !found || !balanced {
		return nil, fmt.Errorf("nochdir: %s is not defined at file scope", name)
	}
	fmt.Fprintf(w, "  nochdir      %-14s was %3d lines -- %s\n",
		name, bytes.Count(text[o:c], []byte{'\n'}), tag)
	out := make([]byte, 0, len(text))
	out = append(out, text[:o]...)
	out = append(out, "{\n"...)
	out = append(out, replacement...)
	out = append(out, "\n}"...)
	return append(out, text[c+1:]...), nil
}

// NoChdir stops anything moving this process between directories.
func NoChdir(text []byte, w io.Writer) ([]byte, error) {
	text, err := nochdirBody(text, "mch_FullName", nochdirFullName,
		"nothing moves this process", w)
	if err != nil {
		return nil, err
	}
	text, err = nochdirBody(text, "mch_dirname", nochdirDirname,
		"the answer cannot change", w)
	if err != nil {
		return nil, err
	}

	// The window- and tab-local directory restore.  Its guard can never be
	// true: w_localdir and tp_localdir come only from :lcd and :tcd, and
	// globaldir is assigned only inside this function.
	var ok bool
	if text, ok = cutil.DeleteDefinition(text, "win_fix_current_dir"); !ok {
		return nil, fmt.Errorf("nochdir: win_fix_current_dir is not defined at file scope")
	}
	if text, err = cutil.DropIf(text, `(?m)^[ \t]*if \(awp->w_localdir != NULL\)$`, 1); err != nil {
		return nil, err
	}
	if text, err = cutCounted(text, `(?m)^[ \t]*win_fix_current_dir\(\);\n\n?`,
		"nochdir", "its unconditional call", 1); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  nochdir      win_fix_current_dir, whose guard cannot be true")

	// `globaldir` remembers the directory to come back to when a window-local
	// one is in force.  win_fix_current_dir() was the only thing that ever set
	// it, so what is left is aucmd_prepbuf()/aucmd_restbuf() saving and
	// restoring a pointer that is always NULL.  A STRUCT FIELD IS NOT A
	// VARIABLE -- no warning would report this one -- so it is named here.
	for _, g := range []struct{ pat, what string }{
		{`(?m)^[ \t]*aco->globaldir = globaldir;\n[ \t]*globaldir = NULL;\n`, "the save"},
		{`(?m)^[ \t]*vim_free\(globaldir\);\n[ \t]*globaldir = aco->globaldir;\n`, "the restore"},
		{`(?m)^[ \t]*char_u      \*globaldir;\n`, "the field"},
		{`(?m)^static char_u   \*globaldir  = NULL ;\n`, "the global"},
	} {
		if text, err = cutCounted(text, g.pat, "nochdir", "globaldir -- "+g.what, 1); err != nil {
			return nil, err
		}
	}
	fmt.Fprintln(w, "  nochdir      globaldir, saved and restored and always NULL")

	// edit_buffers() returns to `cwd` between -o windows.  It is passed
	// start_dir, which nothing assigns.
	if text, err = cutil.DropIf(text, `(?m)^[ \t]*if \(cwd != NULL\)$`, 1); err != nil {
		return nil, err
	}
	for _, g := range []struct{ pat, what string }{
		{`(?m)^static char_u \*start_dir = NULL;\n\n?`, "start_dir itself"},
		{`(?m)^[ \t]*vim_free\(start_dir\);\n`, "the free of it"},
	} {
		if text, err = cutCounted(text, g.pat, "nochdir", "start_dir -- "+g.what, 1); err != nil {
			return nil, err
		}
	}
	for _, r := range []struct{ old, new string }{
		{"edit_buffers(&params, start_dir);", "edit_buffers(&params);"},
		{"static void edit_buffers(mparm_T *parmp, char_u *cwd);",
			"static void edit_buffers(mparm_T *parmp);"},
		{"edit_buffers(mparm_T     *parmp, char_u      *cwd)",
			"edit_buffers(mparm_T     *parmp)"},
	} {
		text = bytes.Replace(text, []byte(r.old), []byte(r.new), 1)
	}
	fmt.Fprintln(w, "  nochdir      the -o window walk stops returning to a directory it "+
		"was never given")

	for _, g := range []string{"mch_chdir", "fchdir", "getcwd"} {
		fmt.Fprintf(w, "  nochdir      %-10s %d mentions left for the sweep\n",
			g, len(regexp.MustCompile(`\b`+g+`\b`).FindAll(text, -1)))
	}
	return text, nil
}
