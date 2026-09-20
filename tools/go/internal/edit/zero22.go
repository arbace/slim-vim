package edit

import (
	"fmt"
	"io"
	"regexp"
	"strings"
)

func init() { register("zero22", Zero22) }

// z22Wrap is the seven wrappers that walk a va_list, and their whole-file
// mention totals in r21.  `vim_snprintf`'s OWN count is deliberately NOT
// asserted up front: phase 21 formats its host message with it, so the number
// before the edit is the message layer's business and not this phase's.
var z22Wrap = []struct {
	name string
	want int
}{
	{"smsg", 12}, {"smsg_attr", 4}, {"smsg_attr_keep", 2}, {"semsg", 96},
	{"siemsg", 12}, {"vim_snprintf_add", 3}, {"vim_snprintf_safelen", 13},
}

var z22Room = map[string]string{
	"smsg": "iobuff_room()", "smsg_attr": "iobuff_room()",
	"smsg_attr_keep": "iobuff_room()", "semsg": "emsg_iobuff_room()",
	"siemsg": "emsg_iobuff_room()",
}

var z22Lead = map[string]int{
	"smsg": 0, "smsg_attr": 1, "smsg_attr_keep": 1, "semsg": 0, "siemsg": 0,
}

// Zero22 is the variadic collapse: the seven wrappers expanded at their 129 call
// sites into vim_snprintf plus the tail each already had, so `va_start` appears
// ONCE in the whole file.
func Zero22(text []byte, w io.Writer) ([]byte, error) {
	p := ph{"format", w}
	t := string(text)

	mentions := func(s, name string) int {
		return len(regexp.MustCompile(`\b`+name+`\b`).FindAllString(s, -1))
	}
	sub := func(old, new string, n int, tag string) error {
		c := strings.Count(t, old)
		if c != n {
			return p.die("%s: `%s` occurs %d times, expected %d",
				tag, zHead(strings.Split(strings.TrimSpace(old), "\n")[0], 70), c, n)
		}
		t = strings.ReplaceAll(t, old, new)
		return nil
	}
	// delfunc deletes a whole definition by brace matching from its name line.
	delfunc := func(sigline, tag string) error {
		if k := strings.Count(t, sigline); k != 1 {
			return p.die("%s: the definition line `%s` occurs %d times, expected 1",
				tag, zHead(strings.TrimSpace(sigline), 60), k)
		}
		i := strings.Index(t, sigline)
		k := strings.Index(t[i:], "{") + i
		d := 0
		for {
			if t[k] == '{' {
				d++
			} else if t[k] == '}' {
				d--
				if d == 0 {
					break
				}
			}
			k++
		}
		a := strings.LastIndex(t[:i], "\n")
		st := strings.LastIndex(t[:a], "\n") + 1
		t = t[:st] + t[strings.Index(t[k:], "\n")+k+1:]
		return nil
	}
	linesBefore := len(strings.Split(t, "\n"))

	// ---- 0. this is the file the phase was written against --------------------
	for _, wr := range z22Wrap {
		if k := mentions(t, wr.name); k != wr.want {
			return nil, p.die("the input has %d mentions of `%s`, expected %d -- this is not the tree "+
				"this phase was written against", k, wr.name, wr.want)
		}
	}
	for _, v := range []struct {
		name string
		want int
	}{{"va_start", 8}, {"va_list", 15}, {"va_end", 10}} {
		if k := mentions(t, v.name); k != v.want {
			return nil, p.die("the input has %d mentions of `%s`, expected %d", k, v.name, v.want)
		}
	}
	vsBefore := mentions(t, "vim_snprintf")
	p.say("the input is r21: eight functions call `va_start`, seven of them wrappers over the " +
		"eighth, and their mention totals are 12 4 2 96 12 3 13")

	// ---- 1. the seven definitions ---------------------------------------------
	for _, sig := range []string{
		"smsg(const char *s, ...)", "smsg_attr(int attr, const char *s, ...)",
		"smsg_attr_keep(int attr, const char *s, ...)", "semsg(const char *s, ...)",
		"siemsg(const char *s, ...)",
		"vim_snprintf_add(char *str, size_t str_m, const char *fmt, ...)",
		"vim_snprintf_safelen(char *str, size_t str_m, const char *fmt, ...)",
	} {
		if err := delfunc("\n"+sig+"\n", "D"); err != nil {
			return nil, err
		}
	}

	// ---- 2. the prototypes -----------------------------------------------------
	// Six, not seven: `smsg_attr_keep` never had one.  And `vim_snprintf`'s SECOND
	// prototype, which existed only because the wrappers sit above its definition.
	if err := sub(z22lit1, "", 1, "P0"); err != nil {
		return nil, err
	}
	for _, pr := range []string{z22lit2, z22lit3, z22lit4, z22lit5, z22lit6, z22lit7} {
		if err := sub(pr, "", 1, "P"); err != nil {
			return nil, err
		}
	}
	if err := sub(z22lit8, z22lit9, 1, "P1"); err != nil {
		return nil, err
	}

	// ---- 3. the five helpers, where the message wrappers were -----------------
	if err := sub(z22Anchor, z22Helpers+z22Anchor, 1, "H"); err != nil {
		return nil, err
	}

	// ---- 4. the 129 call sites -------------------------------------------------
	names := make([]string, len(z22Wrap))
	for i, wr := range z22Wrap {
		names[i] = wr.name
	}
	// The Python spells the boundaries `(?<![A-Za-z0-9_])name(?![A-Za-z0-9_])`.
	// RE2 has no lookaround: the trailing one is implied by the `\s*\(` that
	// follows -- `smsg` cannot match inside `smsg_attr(` because `_` is not `(`,
	// and the engine then takes the longer alternative -- and the leading one is
	// the byte before, tested.
	call := regexp.MustCompile(`(` + strings.Join(names, "|") + `)\s*\(`)

	closeParen := func(s string, i int) (int, error) {
		d := 0
		for i < len(s) {
			c := s[i]
			if c == '"' || c == '\'' {
				q := c
				i++
				for s[i] != q {
					if s[i] == '\\' {
						i += 2
					} else {
						i++
					}
				}
			} else if c == '(' {
				d++
			} else if c == ')' {
				d--
				if d == 0 {
					return i, nil
				}
			}
			i++
		}
		return 0, p.die("unbalanced parentheses")
	}
	splitArgs := func(s string) []string {
		var args []string
		var cur strings.Builder
		d, i := 0, 0
		for i < len(s) {
			c := s[i]
			if c == '"' || c == '\'' {
				q := c
				j := i + 1
				for s[j] != q {
					if s[j] == '\\' {
						j += 2
					} else {
						j++
					}
				}
				cur.WriteString(s[i : j+1])
				i = j + 1
				continue
			}
			if c == '(' || c == '[' || c == '{' {
				d++
			} else if c == ')' || c == ']' || c == '}' {
				d--
			}
			if c == ',' && d == 0 {
				args = append(args, strings.TrimSpace(cur.String()))
				cur.Reset()
			} else {
				cur.WriteByte(c)
			}
			i++
		}
		args = append(args, strings.TrimSpace(cur.String()))
		return args
	}

	shapes := map[string]int{"plain": 0, "inline": 0, "value": 0}
	counts := map[string]int{}
	for _, n := range names {
		counts[n] = 0
	}
	pos := 0
	for {
		var m []int
		for {
			mm := call.FindStringSubmatchIndex(t[pos:])
			if mm == nil {
				break
			}
			for i := range mm {
				if mm[i] >= 0 {
					mm[i] += pos
				}
			}
			if mm[0] > 0 && isWordByte(t[mm[0]-1]) {
				pos = mm[0] + 1
				continue
			}
			m = mm
			break
		}
		if m == nil {
			break
		}
		name := t[m[2]:m[3]]
		op := m[1] - 1
		cp, err := closeParen(t, op)
		if err != nil {
			return nil, err
		}
		args := splitArgs(t[op+1 : cp])
		counts[name]++

		var rep string
		switch name {
		case "vim_snprintf_safelen":
			// ALWAYS AN EXPRESSION: the value is consumed at every one of the
			// eleven sites, five of them `+=`, so two statements cannot say this.
			if len(args) < 4 {
				return nil, p.die("vim_snprintf_safelen with %d arguments", len(args))
			}
			rep = fmt.Sprintf("safelen_result(%s, %s, vim_snprintf(%s))",
				args[0], args[1], strings.Join(args, ", "))
			shapes["value"]++
		case "vim_snprintf_add":
			if len(args) < 4 {
				return nil, p.die("vim_snprintf_add with %d arguments", len(args))
			}
			rep = fmt.Sprintf("vim_snprintf(%s +  musl_strlen((char *)(%s)) , append_room(%s, %s), %s)",
				args[0], args[0], args[0], args[1], strings.Join(args[2:], ", "))
			shapes["value"]++
		default:
			nl := z22Lead[name]
			if len(args) < nl+2 {
				return nil, p.die("`%s` with %d arguments -- no site passes zero variadic arguments",
					name, len(args))
			}
			f := args[nl]
			a := fmt.Sprintf("vim_snprintf((char *)IObuff, %s, %s)",
				z22Room[name], strings.Join(append([]string{f}, args[nl+1:]...), ", "))
			var b string
			switch name {
			case "smsg":
				b = fmt.Sprintf("msg(iobuff_or(%s))", f)
			case "smsg_attr":
				b = fmt.Sprintf("msg_attr(iobuff_or(%s), %s)", f, args[0])
			case "smsg_attr_keep":
				b = fmt.Sprintf("msg_attr_keep(iobuff_or(%s), %s, TRUE)", f, args[0])
			case "semsg":
				b = fmt.Sprintf("emsg(iobuff_or(%s))", f)
			default:
				b = fmt.Sprintf("iemsg(iobuff_or(%s))", f)
			}
			if cp+1 < len(t) && t[cp+1] == ';' {
				bol := strings.LastIndex(t[:m[0]], "\n") + 1
				eol := strings.Index(t[cp:], "\n") + cp
				if strings.TrimSpace(t[bol:m[0]]) == "" && strings.TrimSpace(t[cp+2:eol]) == "" {
					rep = a + ";\n" + t[bol:m[0]] + b + ";"
					shapes["plain"]++
				} else {
					// A WHOLE BLOCK ON ONE LINE.  Two lines here would leave a
					// statement in front of the closing brace.
					rep = a + "; " + b + ";"
					shapes["inline"]++
				}
				t = t[:m[0]] + rep + t[cp+2:]
				pos = m[0] + len(rep)
				continue
			}
			// VALUE POSITION: the comma shape the regexp engine already uses.
			rep = fmt.Sprintf("(%s, %s)", a, b)
			shapes["value"]++
		}
		t = t[:m[0]] + rep + t[cp+1:]
		pos = m[0] + len(rep)
	}

	total := 0
	for _, n := range names {
		total += counts[n]
	}
	tally := func() string {
		out := make([]string, len(names))
		for i, n := range names {
			out[i] = fmt.Sprintf("%s %d", n, counts[n])
		}
		return strings.Join(out, " ")
	}
	if total != 129 {
		return nil, p.die("%d call sites, expected 129 -- %s", total, tally())
	}
	for _, wr := range z22Wrap {
		if k := mentions(t, wr.name); k != 0 {
			return nil, p.die("`%s` still has %d mentions after the expansion", wr.name, k)
		}
	}
	for _, v := range []struct {
		name string
		want int
	}{{"va_start", 1}, {"va_list", 8}, {"va_end", 3}} {
		if k := mentions(t, v.name); k != v.want {
			return nil, p.die("`%s` has %d mentions after the expansion, expected %d",
				v.name, k, v.want)
		}
	}
	if k := mentions(t, "vim_snprintf"); k != vsBefore-1+total {
		return nil, p.die("`vim_snprintf` went from %d to %d, expected %d -- one prototype away and one "+
			"mention at each of the %d sites", vsBefore, k, vsBefore-1+total, total)
	}

	commaTally := make([]string, len(names))
	for i, n := range names {
		commaTally[i] = fmt.Sprintf("%s %d", n, counts[n])
	}
	p.sayf("129 call sites expanded: %s", strings.Join(commaTally, ", "))
	p.sayf("%d plain statements (two lines), %d whole blocks on one line (inline), %d in value "+
		"position -- the 18 `return (semsg(...), rc_did_emsg = TRUE, NULL)` comma "+
		"expressions, the 11 safelens whose value is consumed, and the one append",
		shapes["plain"], shapes["inline"], shapes["value"])
	p.sayf("`va_start` 8 -> 1, `va_list` 15 -> 8, `va_end` 10 -> 3; `vim_snprintf` %d -> %d; "+
		"seven definitions and six prototypes gone, five helpers and six declarations in; "+
		"lines %d -> %d",
		vsBefore, mentions(t, "vim_snprintf"), linesBefore, len(strings.Split(t, "\n")))
	return []byte(t), nil
}
