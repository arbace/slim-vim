package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

var backupWord = regexp.MustCompile(`\bbackup\b`)

// nobackupBlock deletes the `if` block whose line is `anchor` (a literal), and
// reports how many lines went.  With keepBody it keeps the dedented body.
func nobackupBlock(text []byte, anchor, what string, keepBody bool) ([]byte, int, error) {
	blanked := cutil.Blank(text)
	k := bytes.Index(text, []byte(anchor))
	if k < 0 {
		return nil, 0, fmt.Errorf("nobackup: %s -- not where this expects", what)
	}
	from := k + len(anchor) - 2
	o := from + bytes.IndexByte(blanked[from:], '{')
	c := cutil.Match(blanked, o)
	if c < 0 {
		return nil, 0, fmt.Errorf("nobackup: %s -- unbalanced", what)
	}
	end := c + bytes.IndexByte(text[c:], '\n') + 1
	tail := text[c+1:]
	if len(tail) > 39 {
		tail = tail[:39]
	}
	if regexp.MustCompile(`^[ \t]*\n[ \t]*else\b`).Match(tail) {
		return nil, 0, fmt.Errorf("nobackup: %s -- has an else", what)
	}
	if end < len(text) && text[end] == '\n' {
		end++
	}
	n := bytes.Count(text[k:end], []byte{'\n'})
	k = bytes.LastIndexByte(text[:k], '\n') + 1
	out := make([]byte, 0, len(text))
	out = append(out, text[:k]...)
	if keepBody {
		body := cutil.Dedent4(text[o+bytes.IndexByte(text[o:], '\n')+1 : bytes.LastIndexByte(text[:c], '\n')+1])
		out = append(out, body...)
	}
	return append(out, text[end:]...), n, nil
}

// nobackupSub replaces exact text, counted.
func nobackupSub(text []byte, old, new, what string, count int) ([]byte, error) {
	n := bytes.Count(text, []byte(old))
	if n != count {
		return nil, fmt.Errorf("nobackup: %s -- expected %d, matched %d", what, count, n)
	}
	return bytes.ReplaceAll(text, []byte(old), []byte(new)), nil
}

// pointRowsAtNull replaces a handler name with NULL wherever it appears
// BETWEEN a space-or-comma and a comma -- which is exactly a table row.
//
// The Python writes this as `(?<=[ ,])name(?=,)`, and RE2 HAS NO LOOKAROUND OF
// EITHER KIND.  A capturing form would work here but is not equivalent in
// general: it consumes the delimiters, so two matches sharing one comma would
// lose the second.  Testing the bytes either side is exact and cannot.
//
// A forward declaration has `(` after the name, not `,`, so it is left alone
// for deadprotos to take.
func pointRowsAtNull(text []byte, handler string) ([]byte, int) {
	name := []byte(handler)
	var out []byte
	n, prev := 0, 0
	for i := 0; ; {
		j := bytes.Index(text[i:], name)
		if j < 0 {
			break
		}
		at := i + j
		i = at + len(name)
		if at == 0 || i >= len(text) {
			continue
		}
		before, after := text[at-1], text[i]
		if (before != ' ' && before != ',') || after != ',' {
			continue
		}
		out = append(out, text[prev:at]...)
		out = append(out, "NULL"...)
		prev = i
		n++
	}
	if n == 0 {
		return text, 0
	}
	return append(out, text[prev:]...), n
}

// NoBackup takes the backup file away.
func NoBackup(text []byte, w io.Writer) ([]byte, error) {
	total := 0
	for _, b := range []struct{ anchor, what string }{
		{"    if (!(append && *p_pm == NUL) && !filtering && perm >= 0 && dobackup)",
			"the backup itself"},
		{"    if (*p_pm && dobackup)", "'patchmode'"},
		{"        if (backup != NULL)", "the backup kept or removed after the write"},
		{"    if (!p_bk && backup != NULL && !write_info.bw_conv_error && ",
			"the backup deleted when 'backup' is off"},
	} {
		var n int
		var err error
		text, n, err = nobackupBlock(text, b.anchor, b.what, false)
		if err != nil {
			return nil, err
		}
		total += n
		fmt.Fprintf(w, "  nobackup     %-46s %4d lines\n", b.what, n)
	}

	// The owner carried onto the written file when the backup was a rename.
	// Its `else if` is the branch that now always runs, so the pair collapses
	// to that rather than going -- buf_setino() still has to happen.
	text, err := cutCounted(text,
		`(?m)^[ \t]*if \(backup != NULL && !backup_copy\)\n[ \t]*\{\n`+
			`(?:[^\n]*\n)*?[ \t]*buf_setino\(buf\);\n[ \t]*\}\n`+
			`[ \t]*else (if \(!buf->b_dev_valid\))`,
		"nobackup", "the owner carried to the backup", 1)
	if err != nil {
		return nil, err
	}
	fmt.Fprintf(w, "  nobackup     %-46s %4d lines\n", "the owner carried to the backup", 13)

	var n int
	text, n, err = nobackupBlock(text,
		"                    if (backup != NULL && wfname == fname)",
		"the roll-back to a backup", false)
	if err != nil {
		return nil, err
	}
	total += n
	fmt.Fprintf(w, "  nobackup     %-46s %4d lines\n", "the roll-back to a backup", n)

	for _, s := range []struct{ old, new, what string }{
		{"if (reset_changed && !newfile && overwriting && !(exiting && backup != NULL))",
			"if (reset_changed && !newfile && overwriting)",
			"the `written a backup while exiting` test"},
		{"if (!converted || dobackup)", "if (!converted)", "the conversion test"},
		{"if (overwriting && (!dobackup || backup_copy) && fname == wfname && perm >= 0 && ",
			"if (overwriting && fname == wfname && perm >= 0 && ", "the permissions test"},
	} {
		if text, err = nobackupSub(text, s.old, s.new, s.what, 1); err != nil {
			return nil, err
		}
	}
	if text, _, err = nobackupBlock(text, "        if (!backup_copy)",
		"the ACL put back", true); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  nobackup     thirteen tests that asked whether a backup happened")

	for _, name := range []string{"vim_rename", "vim_copyfile", "set_file_time", "get_bkc_flags"} {
		var ok bool
		if text, ok = cutil.DeleteDefinition(text, name); !ok {
			return nil, fmt.Errorf("nobackup: %s is not defined at file scope", name)
		}
	}
	fmt.Fprintln(w, "  nobackup     vim_rename and vim_copyfile: readlink, symlink, rename")
	fmt.Fprintln(w, "  nobackup     set_file_time: utime")

	for _, name := range []string{"mch_get_acl", "mch_set_acl"} {
		var ok bool
		if text, ok = cutil.DeleteDefinition(text, name); !ok {
			return nil, fmt.Errorf("nobackup: %s is not defined at file scope", name)
		}
	}
	for _, c := range []struct{ pat, what string }{
		{`(?m)^[ \t]*vim_acl_T[ \t]+acl = NULL;\n`, "buf_write's acl"},
		{`(?m)^[ \t]*\{\n[ \t]*acl = mch_get_acl\(fname\);\n[ \t]*\}\n`, "buf_write's mch_get_acl"},
		{`(?m)^[ \t]*mch_set_acl\(wfname, acl\);\n`, "the ACL put back"},
	} {
		if text, err = cutCounted(text, c.pat, "nobackup", c.what, 1); err != nil {
			return nil, err
		}
	}
	var ok bool
	if text, ok = cutil.DeleteDefinition(text, "mch_free_acl"); !ok {
		return nil, fmt.Errorf("nobackup: mch_free_acl is not defined at file scope")
	}
	if text, err = cutCounted(text, `(?m)^[ \t]*mch_free_acl\(acl\);\n`,
		"nobackup", "buf_write's mch_free_acl", 1); err != nil {
		return nil, err
	}
	// Their forward declarations go here rather than in the sweep: the sweep
	// has to compile the file first, and a prototype that names a type this
	// removes is an error, not a warning.
	if text, err = cutCounted(text,
		`(?m)^static vim_acl_T mch_get_acl\(char_u \*fname\);\n`+
			`static void mch_set_acl\(char_u \*fname, vim_acl_T aclent\);\n`+
			`static void mch_free_acl\(vim_acl_T aclent\);\n`,
		"nobackup", "the three ACL declarations", 1); err != nil {
		return nil, err
	}
	if text, err = cutCounted(text, `(?m)^typedef void        \*vim_acl_T;\n`,
		"nobackup", "the vim_acl_T type", 1); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  nobackup     the ACL calls, which were stubs in this build")

	// set_init_default_backupskip() builds 'backupskip' from /tmp at startup
	// and looks the row up BY NAME -- the lookup that returns -1 for a row
	// that is not there, is not checked, and indexes options[-1].
	if text, ok = cutil.DeleteDefinition(text, "set_init_default_backupskip"); !ok {
		return nil, fmt.Errorf("nobackup: set_init_default_backupskip is not defined")
	}
	if text, err = cutCounted(text, `(?m)^[ \t]*set_init_default_backupskip\(\);\n`,
		"nobackup", "its call", 1); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  nobackup     the 'backupskip' default, built at startup by name")

	// An option row is a ROOT for reachability, so did_set_backupcopy()
	// survives the sweep and reads p_bkc, and --strict then refuses to drop
	// the row that is the only thing keeping the reader alive.  The answer is
	// to point the row at NULL first.
	for _, h := range []struct {
		handler string
		rows    int
	}{
		{"did_set_backupcopy", 1},
		{"expand_set_backupcopy", 1},
		{"did_set_backupext_or_patchmode", 2},
	} {
		var got int
		text, got = pointRowsAtNull(text, h.handler)
		if got != h.rows {
			return nil, fmt.Errorf("nobackup: %s is named in %d rows, expected %d",
				h.handler, got, h.rows)
		}
		if text, ok = cutil.DeleteDefinition(text, h.handler); !ok {
			return nil, fmt.Errorf("nobackup: %s is not defined at file scope", h.handler)
		}
	}
	fmt.Fprintln(w, "  nobackup     the three handlers the rows kept reachable")

	if text, err = cutCounted(text,
		`(?m)^[ \t]*\(void\)opt_strings_flags\(p_bkc, p_bkc_values, &bkc_flags, TRUE\);\n`,
		"nobackup", "didset_string_options' p_bkc line", 1); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  nobackup     didset_string_options stops reading 'backupcopy'")

	if text, err = cutil.DropIf(text,
		`(?m)^[ \t]*else if \(\*arg == '>' && varp == \(char_u \*\)&p_bdir\)$`, 1); err != nil {
		return nil, err
	}
	if text, err = nobackupSub(text, "if (p == (char_u *)&p_bdir || p == (char_u *)&p_pp",
		"if (p == (char_u *)&p_pp", "the directory-list test", 1); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  nobackup     the two `is this option a directory?` tests")

	for _, c := range []struct{ pat, what string }{
		{`(?m)^[ \t]*char_u          \*backup = NULL;\n`, "backup"},
		{`(?m)^[ \t]*int             backup_copy = FALSE;\n`, "backup_copy"},
		{`(?m)^[ \t]*int             dobackup;\n`, "dobackup"},
		{`(?m)^[ \t]*char_u          \*backup_ext;\n`, "backup_ext"},
		{`(?m)^[ \t]*unsigned int    bkc = get_bkc_flags\(buf\);\n`, "bkc"},
		{`(?m)^[ \t]*dobackup = \(p_wb \|\| p_bk \|\| \*p_pm != NUL\);\n`, "its one assignment"},
		{`(?m)^[ \t]*vim_free\(backup\);\n`, "the free of backup"},
	} {
		if text, err = cutCounted(text, c.pat, "nobackup", c.what, 1); err != nil {
			return nil, err
		}
	}
	if text, err = cutil.DropIf(text,
		`(?m)^[ \t]*if \(dobackup && \*p_bsk != NUL && match_file_list\(p_bsk, sfname, ffname\)\)$`,
		1); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  nobackup     six locals and the assignment that drove them")

	fmt.Fprintf(w, "  nobackup     %d lines of backup machinery; %d mentions left for "+
		"the sweep\n", total, len(backupWord.FindAll(text, -1)))
	return text, nil
}
