package edit

import (
	"bytes"
	"fmt"
	"io"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

func init() { register("zero16", Zero16) }

var zero16Inc = regexp.MustCompile(`^#include <([A-Za-z0-9_/.]+)>$`)
var zero16StructStat = regexp.MustCompile(`\bstruct\s+stat\b`)

// zero16Gone is the six headers this phase takes, each with why it is dead and
// the identifiers it supplies that the file was MEASURED not to name.
//
// EVERY LIST IS THE MEASURED SET AND NOTHING SPECULATIVE, and there is a trap
// behind that rule.  An obvious "while we are here" addition to the ctype list
// is `isprint`, `isspace`, `isblank`, `isxdigit` -- and `isprint` OCCURS IN
// THIS FILE, as the name of the 'isprint' option in a string literal.  A list
// written from what a header offers rather than from what this file was
// measured to take refuses on a correct phase, and the message would be about
// ctype.
var zero16Gone = []struct{ header, why, ids string }{
	{"sys/stat.h", "nothing: `struct stat` is named once, in a typedef nothing uses",
		"fstat lstat chmod fchmod ftruncate mkdir umask st_mode st_size st_mtim st_ino " +
			"st_dev S_ISDIR S_IFMT S_IRUSR S_IWUSR"},
	{"fcntl.h", "nothing at all -- phase 9 freed the symbol and left the header",
		"fcntl creat openat O_RDONLY O_WRONLY O_RDWR O_CREAT O_TRUNC O_APPEND O_EXCL " +
			"O_NONBLOCK O_NOFOLLOW F_GETFD F_SETFD F_GETFL F_SETFL FD_CLOEXEC AT_FDCWD"},
	{"iconv.h", "nothing at all -- whim removed the conversion layer and left the " +
		"header, and nobody had noticed",
		"iconv iconv_t iconv_open iconv_close"},
	{"string.h", "the sixteen mem*/str* functions, which phase 14 vendored",
		"memchr memcmp memcpy memmove memset strcasecmp strcat strchr strcmp strcpy " +
			"strlen strncasecmp strncmp strncpy strpbrk strstr"},
	{"ctype.h", "TEN identifiers, which phase 15 vendored -- five real calls and the " +
		"five musl MACROS a survey driven by nm -u cannot see",
		"isalnum isalpha iscntrl isdigit isgraph islower ispunct isupper tolower " +
			"toupper"},
	{"wctype.h", "towlower and towupper, vendored by phase 15, and iswupper, which " +
		"phase 15 deleted: a NAME with no symbol, on a line gcc never emitted",
		"iswupper towlower towupper"},
}

var zero16Keep = []string{"stdio.h", "stdlib.h", "unistd.h", "sys/param.h", "time.h",
	"signal.h", "errno.h", "stdint.h", "stdarg.h", "stddef.h", "sys/ioctl.h", "termios.h"}

// Zero16 removes the six `#include`s nothing names, and the stat_T typedef no
// sweep could take.
func Zero16(text []byte, w io.Writer) ([]byte, error) {
	p := ph{"includes", w}

	// ---- 0. the file this edit was written against -----------------------
	// EVERY DIRECTIVE IS AN #include OF A SYSTEM HEADER, they are the first
	// lines of the file, and there are eighteen.  ZERO-GOAL.md's charter is
	// that sentence, and this is where it is checked rather than believed.
	lines := bytes.Split(text, []byte{'\n'})
	var dirIdx []int
	var dirLine []string
	for i, l := range lines {
		if bytes.HasPrefix(l, []byte("#")) {
			dirIdx = append(dirIdx, i)
			dirLine = append(dirLine, string(l))
		}
	}
	if len(dirIdx) != 18 {
		return nil, p.die("the file has %d preprocessor directives, expected 18 -- the charter says "+
			"zero-vim.c inherited eighteen from whim-vim.c and that no phase adds one", len(dirIdx))
	}
	for k, i := range dirIdx {
		if i != k {
			return nil, p.die("the eighteen directives are not the first eighteen lines of the file")
		}
	}
	var headers []string
	for _, l := range dirLine {
		m := zero16Inc.FindStringSubmatch(l)
		if m == nil {
			return nil, p.die("not an #include of a system header, and no phase may add one: %s",
				cutil.PyRepr(l))
		}
		headers = append(headers, m[1])
	}
	if len(uniq(headers)) != 18 {
		s := append([]string(nil), headers...)
		sort.Strings(s)
		return nil, p.die("a header is included twice: %s", strings.Join(s, " "))
	}
	body := bytes.Join(lines[18:], []byte{'\n'})
	p.say("eighteen directives, every one an `#include <...>` of a system header and every " +
		"one of them among the first eighteen lines -- the charter, checked rather than " +
		"believed")

	// ---- 1. what zero-vim.c takes from each of the six, and it must be
	// NOTHING.  This is the pre-flight and not the argument: the argument is
	// the check's loop, which drops every surviving include in turn and
	// requires the compile to fail.  A list of identifiers can go stale and a
	// compile cannot.  The list is here because it says WHY each header is
	// dead, which a compiler error does not.
	for _, g := range zero16Gone {
		line := "#include <" + g.header + ">\n"
		if k := bytes.Count(text, []byte(line)); k != 1 {
			return nil, p.die("`%s` occurs %d times, expected 1", strings.TrimSpace(line), k)
		}
		var live []string
		for _, id := range strings.Fields(g.ids) {
			if n := p.mentions(body, id); n > 0 {
				live = append(live, fmt.Sprintf("%s (%d)", id, n))
			}
		}
		if len(live) > 0 {
			return nil, p.die("<%s> is NOT unused: %s -- this phase removes a header only when "+
				"zero-vim.c names nothing it supplies, and the phase that was to take "+
				"these has not run or did not finish", g.header, strings.Join(live, ", "))
		}
		p.sayf("<%-12s %s", g.header+">", g.why)
	}

	// THE ONE EXCEPTION, and it is the only silent drop in this file.
	// `struct stat` IS named once, by a typedef, and a typedef of an
	// undeclared struct tag compiles cleanly -- it declares a new, incomplete
	// type -- so removing <sys/stat.h> alone would leave a lie that only
	// `sizeof(stat_T)` could expose.
	if k := p.mentions(body, "stat_T"); k != 1 {
		return nil, p.die("stat_T has %d mentions, expected 1 -- its own typedef and no user", k)
	}
	if k := len(zero16StructStat.FindAll(body, -1)); k != 1 {
		return nil, p.die("`struct stat` occurs %d times, expected 1 -- the typedef", k)
	}

	// ---- 2. the twelve that stay, and the one that must not be touched ---
	want := append([]string(nil), zero16Keep...)
	for _, g := range zero16Gone {
		want = append(want, g.header)
	}
	got := append([]string(nil), headers...)
	sort.Strings(got)
	sort.Strings(want)
	if strings.Join(got, "\x00") != strings.Join(want, "\x00") {
		return nil, p.die("the eighteen headers are not the twelve this phase keeps and the six it "+
			"takes: %s", strings.Join(got, " "))
	}
	// TWO OF THE TWELVE ARE HELD BY ALMOST NOTHING, and those are counted
	// exactly, because the count IS the statement: a later phase that took
	// them would find this check's loop reporting a dead include.  The other
	// ten are checked for presence only -- an exact count of `select` or
	// `stderr` here would be a number this phase has no argument for.
	for _, thin := range []struct {
		name string
		want int
	}{{"SIZE_MAX", 1}, {"offsetof", 9}, {"uintptr_t", 1}} {
		if k := p.mentions(body, thin.name); k != thin.want {
			return nil, p.die("%s has %d mentions, expected %d -- it is one of the two or three things "+
				"holding its header, so the count is the statement", thin.name, k, thin.want)
		}
	}
	for _, name := range []string{"MIN", "MAX", "select", "gettimeofday", "va_arg",
		"tcgetattr", "ioctl", "nanosleep", "errno", "malloc", "printf", "sigaction"} {
		if p.mentions(body, name) == 0 {
			return nil, p.die("%s is named nowhere, so a header this phase KEEPS may be dead too -- "+
				"the check drops every survivor in turn and would say which", name)
		}
	}
	p.say("the twelve that stay, each held by something this file still names: <stddef.h> " +
		"by offsetof alone, <stdint.h> by SIZE_MAX and by the uintptr_t phase 14 brought, " +
		"and <sys/param.h> by MIN and " +
		"MAX -- plus, through sys/resource.h -> sys/time.h -> sys/select.h and no other " +
		"header in this file, select, gettimeofday, fd_set, struct timeval and every " +
		"*_MAX.  That chain is musl's and is recorded rather than repaired: repairing it " +
		"means ADDING <limits.h>, <sys/time.h> and <sys/select.h>, and no phase adds a " +
		"directive")

	// ---- 3. the cut: six lines, the typedef, and one blank ---------------
	runsBefore := p.blankRuns(text)
	for _, g := range zero16Gone {
		text = bytes.Replace(text, []byte("#include <"+g.header+">\n"), nil, 1)
	}
	p.say("the six `#include` lines")

	// The typedef AND one of its two blank lines: deleting the line alone
	// leaves a run of two blank lines, which CLAUDE.md states this tree does
	// not have.  canon.sh in the sweep would collapse it; doing it here means
	// the text the sweep is handed is right.
	const old = "\ntypedef struct stat stat_T;\n\n"
	if k := bytes.Count(text, []byte(old)); k != 1 {
		return nil, p.die("the stat_T typedef is not one line between two blank lines, so the blank "+
			"that goes with it cannot be identified: %d matches", k)
	}
	text = bytes.Replace(text, []byte(old), []byte("\n"), 1)
	p.say("and `typedef struct stat stat_T;` with one of its two blank lines -- the sweep " +
		"has never been able to take it, because typereach.py reads the token `stat` in " +
		"the `#include <sys/stat.h>` line itself, and in update_search_stat()'s local " +
		"variable, as roots")

	// ---- 4. what the file is now -----------------------------------------
	lines = bytes.Split(text, []byte{'\n'})
	dirIdx, dirLine = nil, nil
	for i, l := range lines {
		if bytes.HasPrefix(l, []byte("#")) {
			dirIdx = append(dirIdx, i)
			dirLine = append(dirLine, string(l))
		}
	}
	bad := len(dirIdx) != 12
	for k, i := range dirIdx {
		if i != k {
			bad = true
		}
	}
	if bad {
		var at []string
		for _, i := range dirIdx {
			at = append(at, strconv.Itoa(i))
		}
		return nil, p.die("the file does not have exactly twelve directives on its first twelve lines "+
			"after the cut: %d directives at lines %s", len(dirIdx), strings.Join(at, " "))
	}
	var left []string
	for _, l := range dirLine {
		if m := zero16Inc.FindStringSubmatch(l); m != nil {
			left = append(left, m[1])
		} else {
			left = append(left, l)
		}
	}
	if strings.Join(left, "\x00") != strings.Join(zero16Keep, "\x00") {
		return nil, p.die("the twelve that are left are not the twelve this phase keeps, in order")
	}
	body = bytes.Join(lines[12:], []byte{'\n'})
	if p.mentions(body, "stat_T") != 0 {
		return nil, p.die("stat_T survives the cut")
	}
	if zero16StructStat.Match(body) {
		return nil, p.die("`struct stat` survives the cut, and with no <sys/stat.h> it would be an " +
			"incomplete type nothing declares")
	}
	if r := p.blankRuns(text); r != runsBefore {
		return nil, p.die("the cut left %d runs of two blank lines where there were %d", r, runsBefore)
	}
	p.sayf("twelve directives, every one an `#include <...>`, on the first twelve lines; "+
		"stat_T and `struct stat` at zero; and %d runs of two blank lines, exactly as "+
		"before", p.blankRuns(text))
	return text, nil
}

func uniq(in []string) []string {
	seen := map[string]bool{}
	var out []string
	for _, s := range in {
		if !seen[s] {
			seen[s] = true
			out = append(out, s)
		}
	}
	return out
}
