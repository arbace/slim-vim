package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

const (
	ownTest = "if (forceit && perm >= 0 && !(perm & 0200) && st_old.st_uid == getuid() " +
		"&& vim_strchr(p_cpo, CPO_FWRITE) == NULL)"
	ownTestNew = "if (forceit && perm >= 0 && !(perm & 0200) " +
		"&& vim_strchr(p_cpo, CPO_FWRITE) == NULL)"
	uidGidTest = "                            if (st_old.st_uid != getuid() || " +
		"st_old.st_gid != getgid())"
	unameTest = "            if (get_user_name(uname, B0_UNAME_SIZE) == FAIL"
	flenOld   = "flen = home_replace(NULL, buf->b_ffname, b0p->b0_fname, " +
		"B0_FNAME_SIZE_CRYPT, TRUE);"
	flenNew = "(void)home_replace(NULL, buf->b_ffname, b0p->b0_fname, " +
		"B0_FNAME_SIZE_CRYPT, TRUE);"
)

var identityLeft = regexp.MustCompile(`\bgetuid\b|\bgetgid\b|\bget_user_name\b`)

// keepBodyAt replaces the block opened after `k` with its DEDENTED body,
// dropping the `if` line around it and everything up to `endAfter`.
func keepBodyAt(text, blanked []byte, k, endAfter int) []byte {
	o := k + bytes.IndexByte(blanked[k:], '{')
	c := cutil.Match(blanked, o)
	if c < 0 {
		return nil
	}
	_ = endAfter
	body := cutil.Dedent4(text[o+bytes.IndexByte(text[o:], '\n')+1 : bytes.LastIndexByte(text[:c], '\n')+1])
	end := c + bytes.IndexByte(text[c:], '\n') + 1
	lineStart := bytes.LastIndexByte(text[:k], '\n') + 1
	out := make([]byte, 0, len(text))
	out = append(out, text[:lineStart]...)
	out = append(out, body...)
	return append(out, text[end:]...)
}

// NoOwner stops the editor asking who owns anything.
func NoOwner(text []byte, w io.Writer) ([]byte, error) {
	if !bytes.Contains(text, []byte(ownTest)) {
		return nil, fmt.Errorf("noowner: the `do you own this read-only file` test " +
			"is not where this expects")
	}
	text = bytes.Replace(text, []byte(ownTest), []byte(ownTestNew), 1)
	fmt.Fprintln(w, "  noowner      :w! clears the read-only bit without asking whose it is")

	// The mode masking stays; only the test that guarded it goes.
	blanked := cutil.Blank(text)
	k := bytes.Index(text, []byte(uidGidTest))
	if k < 0 {
		return nil, fmt.Errorf("noowner: the mode masking is not where this expects")
	}
	o := k + bytes.IndexByte(blanked[k:], '{')
	c := cutil.Match(blanked, o)
	if c < 0 {
		return nil, fmt.Errorf("noowner: the mode masking is not where this expects")
	}
	body := cutil.Dedent4(text[o+bytes.IndexByte(text[o:], '\n')+1 : bytes.LastIndexByte(text[:c], '\n')+1])
	if !bytes.Contains(body, []byte("perm &= 0777;")) {
		return nil, fmt.Errorf("noowner: the mode masking is not where this expects")
	}
	text = keepBodyAt(text, blanked, k, 0)
	fmt.Fprintln(w, "  noowner      a written file never carries a setuid bit, whoever wrote it")

	var err error
	text, err = cutil.DropIf(text,
		`(?m)^[ \t]*if \(options\[opt_idx\]\.indir ==   \(idopt_T\)\(PV_BUF \+ \(int\)\(BV_ML\)\)   `+
			`&& getuid\(\) == ROOT_UID\)$`, 1)
	if err != nil {
		return nil, err
	}
	text, err = cutCounted(text, `(?m)^enum \{ ROOT_UID = 0 \};\n`, "noowner", "the ROOT_UID enumerator", 1)
	if err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  noowner      'modeline' stops asking whether this is root")

	text, err = cutCounted(text,
		`(?m)^[ \t]*\(void\)get_user_name\(b0p->b0_uname, B0_UNAME_SIZE\);\n`+
			`[ \t]*b0p->b0_uname\[B0_UNAME_SIZE - 1\] = NUL;\n`,
		"noowner", "block zero's user name", 1)
	if err != nil {
		return nil, err
	}

	// The other caller's `if` was already always true -- get_user_name() has
	// returned FAIL since Phase 20 -- so its `else` has been dead that long.
	blanked = cutil.Blank(text)
	k = bytes.Index(text, []byte(unameTest))
	if k < 0 {
		return nil, fmt.Errorf("noowner: the get_user_name arm is not where this expects")
	}
	nl := k + bytes.IndexByte(text[k:], '\n')
	o = nl + bytes.IndexByte(blanked[nl:], '{')
	c = cutil.Match(blanked, o)
	if c < 0 {
		return nil, fmt.Errorf("noowner: the get_user_name arm is unbalanced")
	}
	m := regexp.MustCompile(`^\n[ \t]*else\n`).FindIndex(text[c+1:])
	if m == nil {
		return nil, fmt.Errorf("noowner: the get_user_name arm has no else")
	}
	o2 := c + 1 + m[1] + bytes.IndexByte(blanked[c+1+m[1]:], '{')
	c2 := cutil.Match(blanked, o2)
	if c2 < 0 {
		return nil, fmt.Errorf("noowner: the get_user_name else arm is unbalanced")
	}
	body = cutil.Dedent4(text[o+bytes.IndexByte(text[o:], '\n')+1 : bytes.LastIndexByte(text[:c], '\n')+1])
	end := c2 + bytes.IndexByte(text[c2:], '\n') + 1
	lineStart := bytes.LastIndexByte(text[:k], '\n') + 1
	var buf []byte
	buf = append(buf, text[:lineStart]...)
	buf = append(buf, body...)
	text = append(buf, text[end:]...)

	// `flen` was the length the user name would have been spliced in front of.
	// -Wunused-but-set-variable is not a shape deadsweep deletes, so the
	// assignment becomes a plain call and the declaration is named here.
	if !bytes.Contains(text, []byte(flenOld)) {
		return nil, fmt.Errorf("noowner: set_b0_fname's home_replace is not where this expects")
	}
	text = bytes.Replace(text, []byte(flenOld), []byte(flenNew), 1)
	if text, err = cutCounted(text, `(?m)^[ \t]*size_t  flen;\n`, "noowner",
		"set_b0_fname's flen", 1); err != nil {
		return nil, err
	}

	// And the field it wrote into.  A STRUCT FIELD IS NOT A VARIABLE: no
	// warning names one that nothing reads, and the dead-code sweep cannot see
	// it.  The layout of block zero does not matter -- nothing writes it to a
	// disk and nothing reads one back -- and there is no assertion on its size.
	if text, err = cutCounted(text, `(?m)^[ \t]*char_u      b0_uname\[B0_UNAME_SIZE\];\n`,
		"noowner", "block zero's b0_uname field", 1); err != nil {
		return nil, err
	}
	if text, err = cutCounted(text, `(?m)^enum \{ B0_UNAME_SIZE = 40 \};\n`,
		"noowner", "B0_UNAME_SIZE", 1); err != nil {
		return nil, err
	}

	var ok bool
	if text, ok = cutil.DeleteDefinition(text, "get_user_name"); !ok {
		return nil, fmt.Errorf("noowner: get_user_name is not defined at file scope")
	}
	fmt.Fprintln(w, "  noowner      who wrote the swap file, a stub since Phase 20")

	fmt.Fprintf(w, "  noowner      %d identity mentions left for the sweep\n",
		len(identityLeft.FindAll(text, -1)))
	return text, nil
}

// cutCounted deletes a pattern `count` times, refusing on any other number.
func cutCounted(text []byte, pattern, tool, what string, count int) ([]byte, error) {
	re := regexp.MustCompile(pattern)
	locs := re.FindAllIndex(text, count)
	if len(locs) != count {
		return nil, fmt.Errorf("%s: %s -- expected %d, matched %d", tool, what, count, len(locs))
	}
	out := make([]byte, 0, len(text))
	prev := 0
	for _, l := range locs {
		out = append(out, text[prev:l[0]]...)
		prev = l[1]
	}
	return append(out, text[prev:]...), nil
}
