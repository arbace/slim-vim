package harness

import (
	"fmt"
	"io"
	"os"
	"regexp"
	"sort"
	"strings"
)

// vocab is the host's vocabulary: the words a core that has given its
// terminal, its signals and its clock to a host must no longer say.
var vocab = regexp.MustCompile(
	`\b(?:sigaction|sigemptyset|sigaddset|sigismember|sigprocmask|sighandler_T` +
		`|raise|kill|getpid|ioctl|TIOCGWINSZ|SIG_?[A-Z][A-Z0-9_]*` +
		`|tcgetattr|tcsetattr|nanosleep|select|isatty|close|dup|gettimeofday` +
		`|FD_SET|FD_ZERO|FD_ISSET|fd_set|TCSANOW` +
		`|ICANON|ECHO|ISIG|ECHOE|IEXTEN|ICRNL|IXON|ONLCR|XTABS` +
		`|VMIN|VTIME|VERASE|VINTR|EINTR|errno)\b` +
		`|\bstruct[ \t]+(?:winsize|termios|timespec|timeval)\b`)

var defnHead = regexp.MustCompile(`^([A-Za-z_]\w*)\s*\(`)

// stripStrings blanks string and character literals.
//
// The file contains hash_remove(&buf_hashtab, hi, "close buffer"), and a tool
// that read that as a close() would report the buffer layer as filesystem
// code.
func stripStrings(line string) string {
	var out strings.Builder
	for i := 0; i < len(line); {
		c := line[i]
		if c == '"' || c == '\'' {
			q := c
			out.WriteByte(' ')
			i++
			for i < len(line) {
				if line[i] == '\\' {
					i += 2
					continue
				}
				if line[i] == q {
					break
				}
				i++
			}
			i++
			continue
		}
		out.WriteByte(c)
		i++
	}
	return out.String()
}

// ownersOf returns, for every line, the function definition containing it.
func ownersOf(lines []string) []string {
	out := make([]string, len(lines))
	cur := ""
	for i, line := range lines {
		if m := defnHead.FindStringSubmatch(line); m != nil &&
			i+1 < len(lines) && strings.HasPrefix(lines[i+1], "{") {
			cur = m[1]
		}
		out[i] = cur
		if line == "}" {
			cur = ""
		}
	}
	return out
}

// ZHostOnly asserts a PLACE rather than a count: every mention of every host
// word must be inside the host block.
//
// Inside one translation unit, moving a call from the core into the host frees
// no nm -u symbol -- a symbol leaves when its last CALLER leaves the FILE -- so
// the phase's real claim is where the code is, and this is that claim as an
// assertion.  Like the two floors elsewhere it refuses to pass vacuously: the
// host region must be found, must define all of its functions, and must itself
// mention the words it is supposed to own.
func ZHostOnly(path string, quiet bool, w io.Writer) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	lines := strings.Split(string(data), "\n")
	own := ownersOf(lines)
	var fail []string

	var begins []int
	for i, l := range lines {
		if strings.HasPrefix(l, hostBegin) {
			begins = append(begins, i)
		}
	}
	if len(begins) != 1 {
		// Single quotes, because the Python formats this with %r and the
		// recorded messages carry that spelling.  A port that printed Go's %q
		// would differ on every boundary before the host block exists -- 20 of
		// them, measured, and every difference was the quote character.
		return fmt.Errorf("zhostonly: the host block does not begin exactly once with '%s' -- "+
			"found %d.  A region this tool cannot find would make every check below "+
			"pass by finding nothing", hostBegin, len(begins))
	}
	var lasts []int
	for i, l := range lines {
		if strings.HasPrefix(l, hostLast+"(") {
			lasts = append(lasts, i)
		}
	}
	if len(lasts) != 1 {
		return fmt.Errorf("zhostonly: %s() is not defined exactly once, so the host "+
			"region has no end", hostLast)
	}
	end := lasts[0]
	for end < len(lines) && lines[end] != "}" {
		end++
	}
	if end >= len(lines) {
		return fmt.Errorf("zhostonly: %s() does not close at column 0", hostLast)
	}

	inhost := map[int]bool{}
	for i := begins[0]; i <= end; i++ {
		inhost[i] = true
	}
	defined := map[string]bool{}
	for i := range inhost {
		if own[i] != "" {
			defined[own[i]] = true
		}
	}
	var missing []string
	for _, f := range hostFuncs {
		if !defined[f] {
			missing = append(missing, f)
		}
	}
	if len(missing) > 0 {
		fail = append(fail, fmt.Sprintf("the host region does not define %s -- the region "+
			"is %d lines and this check is only as strong as what is in it",
			strings.Join(missing, " "), len(inhost)))
	}

	type bucket struct{ who, word string }
	hits := map[bucket][]int{}
	spaces := regexp.MustCompile(`[ \t]+`)
	for n, raw := range lines {
		if strings.HasPrefix(raw, "#") {
			continue
		}
		for _, m := range vocab.FindAllString(stripStrings(raw), -1) {
			word := spaces.ReplaceAllString(m, " ")
			if inhost[n] {
				hits[bucket{"<host>", word}] = append(hits[bucket{"<host>", word}], n+1)
				continue
			}
			who := own[n]
			if who == "" {
				who = "<file scope>"
			}
			if who == "<file scope>" {
				lo := n - 12
				if lo < 0 {
					lo = 0
				}
				if strings.Contains(strings.Join(lines[lo:n+1], ""), "signal_info[]") {
					who = "signal_info[]"
				}
			}
			hits[bucket{who, word}] = append(hits[bucket{who, word}], n+1)
		}
	}

	for _, word := range hostMust {
		if _, ok := hits[bucket{"<host>", word}]; !ok {
			fail = append(fail, fmt.Sprintf("the host region does not mention `%s` at all.  "+
				"This tool would then be asserting that the core does not say a word "+
				"nobody says", word))
		}
	}

	want := map[bucket][]int{}
	for _, e := range hostExceptions {
		want[bucket{e.fn, e.word}] = e.counts
	}

	var keys []bucket
	for k := range hits {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		if keys[i].who != keys[j].who {
			return keys[i].who < keys[j].who
		}
		return keys[i].word < keys[j].word
	})
	for _, k := range keys {
		if k.who == "<host>" {
			continue
		}
		ls := hits[k]
		n := len(ls)
		if containsInt(want[k], n) {
			continue
		}
		plural, plural2 := "", ""
		if n != 1 {
			plural, plural2 = "s", "s"
		}
		show := ls
		if len(show) > 6 {
			show = show[:6]
		}
		var nums []string
		for _, x := range show {
			nums = append(nums, fmt.Sprint(x))
		}
		extra := ""
		if cs, ok := want[k]; ok {
			var strs []string
			for _, c := range cs {
				strs = append(strs, fmt.Sprint(c))
			}
			extra = ", where " + strings.Join(strs, " or ") + " was expected"
		}
		fail = append(fail, fmt.Sprintf("%s says `%s` %d time%s (line%s %s)%s",
			k.who, k.word, n, plural, plural2, strings.Join(nums, " "), extra))
	}

	// An exception that stops being true is a fact this tool is meant to
	// notice -- the phase that ends one comes here and writes the new count
	// beside the old.
	var wantKeys []bucket
	for k := range want {
		wantKeys = append(wantKeys, k)
	}
	sort.Slice(wantKeys, func(i, j int) bool {
		if wantKeys[i].who != wantKeys[j].who {
			return wantKeys[i].who < wantKeys[j].who
		}
		return wantKeys[i].word < wantKeys[j].word
	})
	for _, k := range wantKeys {
		n := len(hits[k])
		if containsInt(want[k], n) {
			continue
		}
		var strs []string
		for _, c := range want[k] {
			strs = append(strs, fmt.Sprint(c))
		}
		fail = append(fail, fmt.Sprintf("the named exception `%s` in %s is at %d, and the "+
			"only counts this tool has been told about are %s.  An exception that stops "+
			"being true is a fact this tool is meant to notice -- the phase that ends one "+
			"comes here and writes the new count beside the old",
			k.word, k.who, n, strings.Join(strs, " and ")))
	}

	if len(fail) > 0 {
		for _, line := range fail {
			fmt.Fprintf(w, "  zhostonly    %s\n", line)
		}
		return fmt.Errorf("zhostonly: %d findings", len(fail))
	}
	if !quiet {
		n := 0
		wordSet := map[string]bool{}
		for k, v := range hits {
			if k.who == "<host>" {
				n += len(v)
				wordSet[k.word] = true
			}
		}
		var words []string
		for word := range wordSet {
			words = append(words, word)
		}
		sort.Strings(words)
		fmt.Fprintf(w, "  zhostonly    %d mentions of %d host words, ALL of them inside "+
			"the %d-line host block (%s)\n", n, len(words), len(inhost), strings.Join(words, " "))
		var live []string
		for _, e := range hostExceptions {
			if len(hits[bucket{e.fn, e.word}]) > 0 {
				live = append(live, e.fn+":"+e.word)
			}
		}
		fmt.Fprintf(w, "  %-12s and %d of %d named exceptions LIVE in the core, every one "+
			"of them the deadly-signal message, the signal it re-raises or the clock: %s\n",
			"", len(live), len(hostExceptions), strings.Join(live, ", "))
	}
	return nil
}

func containsInt(xs []int, n int) bool {
	for _, x := range xs {
		if x == n {
			return true
		}
	}
	return false
}
