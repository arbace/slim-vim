package edit

import (
	"io"
	"regexp"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

func init() { register("zero14", Zero14) }

// z14Before is the seventeen as OCCURRENCES.  Nothing here is approximate: a
// rename is only safe if the count of what is about to be renamed is known
// first -- and `grep -c` counts LINES, which gives 125 for strlen where there
// are 127, so a check written against it refuses a correct phase.
var z14Before = map[string]int{
	"memmove": 159, "strlen": 127, "memset": 79, "strncmp": 82, "strcmp": 62,
	"strcpy": 51, "sprintf": 22, "memcpy": 7, "strncasecmp": 13, "strcat": 6,
	"strcasecmp": 6, "strncpy": 4, "strstr": 3, "strchr": 2, "memcmp": 2,
	"memchr": 1, "strpbrk": 2,
	"vim_snprintf": 55, "vim_vsnprintf_typval": 4,
	"tolower": 2, "highlight_arg_to_string": 2, "MAX_ATTR_LEN": 2,
}

var z14After = map[string]int{
	"sprintf": 0, "f_l": 0, "tolower": 2, "vim_snprintf": 68,
	"musl_memmove": 160, "musl_strlen": 133, "musl_memset": 80,
	"musl_strncmp": 83, "musl_strcmp": 63, "musl_strcpy": 53, "musl_memcpy": 8,
	"musl_strncasecmp": 14, "musl_strcat": 7, "musl_strcasecmp": 7,
	"musl_strncpy": 5, "musl_strstr": 4, "musl_strchr": 3, "musl_memcmp": 3,
	"musl_memchr": 2, "musl_strpbrk": 3,
	"musl_fmtnum": 9, "musl_fmtptr": 2, "musl_fmtbase": 5,
}

// z14Names are the sixteen renamed in section C.
var z14Names = []string{"memmove", "strlen", "memset", "strncmp", "strcmp", "strcpy",
	"memcpy", "strncasecmp", "strcat", "strcasecmp", "strncpy", "strstr", "strchr",
	"memcmp", "memchr", "strpbrk"}

const z14Pad = "                                "

// Zero14 vendors the sixteen mem*/str* of <string.h> as local `static musl_*`
// functions, with sprintf moved onto the editor's own vim_snprintf instead.
func Zero14(text []byte, w io.Writer) ([]byte, error) {
	p := ph{"strings", w}
	t := string(text)

	mentions := func(s, name string) int {
		return len(regexp.MustCompile(`\b`+name+`\b`).FindAllString(s, -1))
	}
	// textEdit does NOT report: sections A and B each make many edits and then
	// say one line about all of them.
	textEdit := func(old, new, what string, n int) error {
		k := strings.Count(t, old)
		if k != n {
			return p.die("%s -- the text occurs %d times, expected %d: %s",
				what, k, n, cutil.PyRepr(zHead(old, 70)))
		}
		t = strings.ReplaceAll(t, old, new)
		return nil
	}

	// ---- 0. the shape every anchor below was counted against ------------------
	for _, name := range sortedKeys(z14Before) {
		if k := mentions(t, name); k != z14Before[name] {
			return nil, p.die("%s has %d mentions, expected %d -- the anchors below were counted "+
				"against a different file", name, k, z14Before[name])
		}
	}
	p.say("the seventeen at 606 + 22 occurrences, tolower at 2, vim_snprintf at 55 -- the " +
		"file the anchors below were counted against")

	// ---- THE SINGLE CALLER, COUNTED BEFORE THE BOUND IS CHOSEN ----------------
	// highlight_arg_to_string takes a POINTER, so sizeof(buf) is 8 and the bound
	// has to come from outside the call.
	if k := mentions(t, "highlight_arg_to_string"); k != 2 {
		return nil, p.die("highlight_arg_to_string has %d mentions and not the definition plus ONE "+
			"call: MAX_ATTR_LEN is only its buffer size while highlight_list_arg is its "+
			"only caller", k)
	}
	if strings.Count(t, z14lit5) != 1 {
		return nil, p.die("highlight_list_arg's `char_u buf[MAX_ATTR_LEN];` is not there exactly once, " +
			"and it is where the bound for site 25443 comes from")
	}
	if strings.Count(t, z14lit6) != 1 {
		return nil, p.die("MAX_ATTR_LEN is not the one enumerator this phase reads")
	}
	p.say("highlight_arg_to_string has ONE caller, highlight_list_arg, whose local is " +
		"char_u buf[MAX_ATTR_LEN] with MAX_ATTR_LEN = 120 -- that, and nothing weaker, " +
		"is why the size argument at site 25443 may be a constant from another function")

	// ---- A. the thirteen external sprintf sites -------------------------------
	for _, s := range z14Sites {
		if err := textEdit(s.old, s.new, s.what, 1); err != nil {
			return nil, err
		}
	}
	p.say("thirteen external sprintf call sites are vim_snprintf now, each with the size " +
		"its destination really has -- eight a sizeof() or the constant the buffer was " +
		"allocated with, three the alloc() expression repeated, one MAX_ATTR_LEN from " +
		"the single caller above, and term_font the one that could overflow")

	// ---- B. the nine inside vim_vsnprintf_typval ------------------------------
	// THE BLOCK GOES FIRST: removing the calls and leaving `f` would draw
	// -Wunused-but-set-variable, which is in -Wall.
	if err := textEdit(z14lit2, "",
		"vim_vsnprintf_typval's `char f[6]`, the two-to-five character format "+
			"string it built for the nine calls below", 1); err != nil {
		return nil, err
	}
	if err := textEdit(z14lit3, z14lit4,
		"%p, which musl's own printf renders as `0x` and sixteen zero-padded "+
			"hex digits -- musl vfprintf does `p = MAX(p, 2*sizeof(void*)); t = "+
			"'x'; fl |= ALT_FORM`, so musl_fmtptr reproduces that and not glibc's "+
			"`(nil)`", 1); err != nil {
		return nil, err
	}
	// The eight integer arms.  They differ in their argument and in their trailing
	// indentation, which is why these are eight one-count patterns and not one
	// pattern with a count of eight.
	for _, a := range z14Arms {
		if err := textEdit(z14Pad+"str_arg_l += sprintf(tmp + str_arg_l, f, "+a.arg,
			z14Pad+"str_arg_l += musl_fmtnum(tmp + str_arg_l, "+a.call,
			"the "+a.arg[:len(a.arg)-2]+" arm", 1); err != nil {
			return nil, err
		}
	}
	if mentions(t, "sprintf") > 0 || mentions(t, "f_l") > 0 {
		return nil, p.die("sprintf has %d mentions and f_l %d after the nine went, and both must be 0",
			mentions(t, "sprintf"), mentions(t, "f_l"))
	}
	p.say("the nine calls inside vim_vsnprintf_typval are musl_fmtnum() and musl_fmtptr() " +
		"now, and the char f[6] that fed them is gone -- sprintf at 0 mentions and f_l " +
		"at 0")

	// ---- C. the rename, outside string and character literals -----------------
	// MEASURED: not one literal in this file mentions any of the sixteen, so the
	// literal awareness is belt and braces -- but a rename that did not have it
	// would be a guess.
	pat := regexp.MustCompile(`\b(` + strings.Join(z14Names, "|") + `)\b`)
	var pieces strings.Builder
	renamed := 0
	for _, r := range z14Runs(t) {
		if r.lit {
			if pat.MatchString(r.s) {
				return nil, p.die("a string literal mentions one of the sixteen and the rename would "+
					"change what the editor PRINTS: %s", cutil.PyRepr(zHead(r.s, 60)))
			}
			pieces.WriteString(r.s)
		} else {
			renamed += len(pat.FindAllString(r.s, -1))
			pieces.WriteString(pat.ReplaceAllString(r.s, "musl_$1"))
		}
	}
	t = pieces.String()
	// 606 in the input + 4 that section A's size expressions introduced.  THE
	// ORDER MATTERS: a phase that renamed first and edited sprintf afterwards
	// would leave four bare strlen behind, which would compile and would keep the
	// symbol.
	if renamed != 610 {
		return nil, p.die("%d identifiers were renamed, expected 610 -- 606 in the input plus the four "+
			"strlen the size expressions above introduce", renamed)
	}
	p.say("610 identifiers renamed to musl_*, none of them inside a literal -- 606 of the " +
		"input and the four strlen the size arguments added")

	// ---- D. the definitions, after the eighteen #includes ---------------------
	if err := textEdit(z14Anchor, z14Anchor+strings.TrimLeft(z14Defs, "\n")+"\n",
		"the eighteen definitions go after the eighteenth and last #include, "+
			"before the first enum -- defined ahead of every use, so no prototype "+
			"is added and the prototype block is not touched", 1); err != nil {
		return nil, err
	}

	// ---- E. what the sweep is handed, as counts rather than as trust ----------
	for _, name := range sortedKeys(z14After) {
		if k := mentions(t, name); k != z14After[name] {
			return nil, p.die("%s has %d mentions after the cut, expected %d", name, k, z14After[name])
		}
	}
	// The Python writes `(?<!_)\bname\b`, and the lookbehind never decides
	// anything: `_` is a word character, so `\b` has already refused a match
	// inside `musl_name`.  RE2 has no lookbehind and needs none here.
	for _, name := range append(append([]string{}, z14Names...), "sprintf") {
		if regexp.MustCompile(`\b` + name + `\b`).MatchString(t) {
			return nil, p.die("%s survives as a bare name somewhere", name)
		}
	}
	var directives, bad []string
	for _, l := range strings.Split(t, "\n") {
		if strings.HasPrefix(l, "#") {
			directives = append(directives, l)
			if !strings.HasPrefix(l, "#include <") {
				bad = append(bad, l)
			}
		}
	}
	if len(directives) != 18 || len(bad) > 0 {
		return nil, p.die("the file has %d lines starting with # and they must be the same eighteen "+
			"#includes: this phase adds no preprocessor syntax", len(directives))
	}
	p.say("the cut is done: sprintf and f_l at 0, tolower still at 2 -- the " +
		"character-class phase's and untouched -- vim_snprintf 55 -> 68, the sixteen " +
		"musl_* at their source counts plus their own definitions, musl_fmtnum at 9 and " +
		"musl_fmtptr at 2, and eighteen #include lines and no other directive")
	return []byte(t), nil
}

type z14Run struct {
	lit bool
	s   string
}

// z14Runs is the heredoc's `runs()`: (is_literal, text) pairs.  It is the
// phase's OWN scanner and not literals.go's, and the difference is deliberate --
// this one does not refuse on an unterminated literal, it ends the run at the
// newline, and a port held to its heredoc byte for byte may not swap one for the
// other.
func z14Runs(text string) []z14Run {
	var out []z14Run
	i, n, start := 0, len(text), 0
	for i < n {
		c := text[i]
		if c == '"' || c == '\'' {
			out = append(out, z14Run{false, text[start:i]})
			j := i + 1
			for j < n {
				if text[j] == '\\' {
					j += 2
					continue
				}
				if text[j] == c || text[j] == '\n' {
					if text[j] == c {
						j++
					}
					break
				}
				j++
			}
			out = append(out, z14Run{true, text[i:j]})
			i, start = j, j
		} else {
			i++
		}
	}
	out = append(out, z14Run{false, text[start:]})
	return out
}
