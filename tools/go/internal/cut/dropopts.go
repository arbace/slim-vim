package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"
	"sort"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

var (
	optLabel   = regexp.MustCompile(`^[ \t]*case '(.)':[ \t]*$`)
	optDefault = regexp.MustCompile(`^[ \t]*default:[ \t]*$`)
	switchOnC  = regexp.MustCompile(`\bswitch \(c\)`)
)

type optSwitch struct{ open, close int }

// Switches returns the option switch and the argument switch as offsets into
// fn, with the blanked copy the caller goes on using.
//
// EXACTLY TWO, asserted: command_line_scan has one switch that reads an
// option's letter and one that reads its argument, and a tool that took "the
// first" of some other number would edit whichever one happened to come first.
func Switches(fn []byte) ([]optSwitch, []byte, error) {
	b := cutil.Blank(fn)
	var found []optSwitch
	for _, m := range switchOnC.FindAllIndex(b, -1) {
		rel := bytes.IndexByte(b[m[1]:], '{')
		if rel < 0 {
			continue
		}
		o := m[1] + rel
		found = append(found, optSwitch{o, cutil.Match(b, o)})
	}
	if len(found) != 2 {
		return nil, nil, fmt.Errorf("dropopts: expected the option switch and the "+
			"argument switch, found %d switches on c", len(found))
	}
	return found, b, nil
}

type labelGroup struct {
	labels []int // line indices of the adjacent `case 'x':` labels
	bs, be int   // the body, as a half-open line range
}

// optGroups returns each run of adjacent labels at the switch's OWN depth,
// with the body that follows it.  The depth comes from the blanked lines, so a
// brace inside a string literal cannot move it.
func optGroups(lines, blines []string) []labelGroup {
	depth := 0
	depths := make([]int, len(blines))
	for i, bl := range blines {
		depths[i] = depth
		depth += strings.Count(bl, "{") - strings.Count(bl, "}")
	}
	isLabel := func(k int) bool {
		return k < len(lines) && depths[k] == 0 && optLabel.MatchString(lines[k])
	}
	var out []labelGroup
	for i := 0; i < len(lines); {
		if !isLabel(i) {
			i++
			continue
		}
		var labels []int
		for i < len(lines) && isLabel(i) {
			labels = append(labels, i)
			i++
		}
		j := i
		for j < len(lines) && !(isLabel(j) ||
			(depths[j] == 0 && optDefault.MatchString(lines[j]))) {
			j++
		}
		out = append(out, labelGroup{labels, i, j})
		i = j
	}
	return out
}

func stripped(lines []string) []string {
	var out []string
	for _, l := range lines {
		if s := strings.TrimSpace(l); s != "" {
			out = append(out, s)
		}
	}
	return out
}

// DropShort removes `letters` from one switch and reports which it held.
//
// The two refusals are the whole value of the tool.  A group whose PREVIOUS
// case falls through into it cannot lose its body, because that would change
// what the previous option runs; and a body that does not end in `break;` is
// one that falls through into the NEXT, which is the same hazard from the
// other side.
func DropShort(fn []byte, which int, letters map[string]bool) ([]byte, map[string]bool, error) {
	sw, b, err := Switches(fn)
	if err != nil {
		return nil, nil, err
	}
	o, c := sw[which].open, sw[which].close
	lines := strings.Split(string(fn[o+1:c]), "\n")
	blines := strings.Split(string(b[o+1:c]), "\n")
	gs := optGroups(lines, blines)

	remove := map[int]bool{}
	held := map[string]bool{}
	for n, g := range gs {
		var names []string
		for _, k := range g.labels {
			names = append(names, optLabel.FindStringSubmatch(lines[k])[1])
		}
		var gone []int
		for i, k := range g.labels {
			if letters[names[i]] {
				gone = append(gone, k)
			}
		}
		if len(gone) == 0 {
			continue
		}
		for _, k := range gone {
			held[optLabel.FindStringSubmatch(lines[k])[1]] = true
		}
		if len(gone) < len(g.labels) {
			for _, k := range gone {
				remove[k] = true
			}
			continue
		}
		if n > 0 {
			prev := stripped(lines[gs[n-1].bs:gs[n-1].be])
			if len(prev) > 0 && prev[len(prev)-1] != "break;" {
				return nil, nil, fmt.Errorf("dropopts: -%s -- the case before it falls "+
					"through into it, so removing its body would change what that "+
					"option runs", strings.Join(names, "/-"))
			}
		}
		tail := stripped(lines[g.bs:g.be])
		if len(tail) == 0 || tail[len(tail)-1] != "break;" {
			return nil, nil, fmt.Errorf("dropopts: -%s -- its body does not end in break",
				strings.Join(names, "/-"))
		}
		for k := g.labels[0]; k < g.be; k++ {
			remove[k] = true
		}
	}

	var kept []string
	for k, l := range lines {
		if !remove[k] {
			kept = append(kept, l)
		}
	}
	out := make([]byte, 0, len(fn))
	out = append(out, fn[:o+1]...)
	out = append(out, strings.Join(kept, "\n")...)
	return append(out, fn[c:]...), held, nil
}

// DropLong removes the chain link comparing against "name", KEEPING THE CHAIN
// A CHAIN: if the link removed was the first, whatever followed it has to stop
// being an `else`.
func DropLong(fn []byte, name string) ([]byte, error) {
	sw, _, err := Switches(fn)
	if err != nil {
		return nil, err
	}
	o, c := sw[0].open, sw[0].close
	seg := fn[o+1 : c]
	pat := regexp.MustCompile(fmt.Sprintf(
		`(?m)^[ \t]*(else )?if \([^\n]*\("%s"\)[^\n]*\)\n[ \t]*\{`, regexp.QuoteMeta(name)))
	ms := pat.FindAllSubmatchIndex(seg, -1)
	if len(ms) != 1 {
		return nil, fmt.Errorf("dropopts: --%s -- expected one branch in the option "+
			"switch, found %d", name, len(ms))
	}
	m := ms[0]
	b := cutil.Blank(seg)
	ob := m[1] - 1 + bytes.IndexByte(b[m[1]-1:], '{')
	cb := cutil.Match(b, ob)
	if cb < 0 {
		return nil, fmt.Errorf("dropopts: --%s -- its branch is unbalanced", name)
	}
	end := cb + 1
	if end < len(seg) && seg[end] == '\n' {
		end++
	}
	head, tail := seg[:m[0]], seg[end:]
	if m[2] < 0 { // no `else ` -- this is the FIRST link
		if nxt := regexp.MustCompile(`^([ \t]*)else if\b`).FindSubmatchIndex(tail); nxt != nil {
			var t []byte
			t = append(t, tail[nxt[2]:nxt[3]]...)
			t = append(t, "if"...)
			tail = append(t, tail[nxt[1]:]...)
		} else if regexp.MustCompile(`^[ \t]*else\b`).Match(tail) {
			return nil, fmt.Errorf("dropopts: --%s is the only test before a bare else", name)
		}
	}
	out := make([]byte, 0, len(fn))
	out = append(out, fn[:o+1]...)
	out = append(out, head...)
	out = append(out, tail...)
	return append(out, fn[c:]...), nil
}

var (
	shortOpt  = regexp.MustCompile(`^-[A-Za-z?]$`)
	longOpt   = regexp.MustCompile(`^--[a-z][a-z-]*$`)
	emptyTest = regexp.MustCompile(`(?m)^[ \t]*if \(argv\[-1\]\[2\] == '.'\)\n[ \t]*\{\n[ \t]*\}\n`)
)

// DropOpts is the command line: remove these options from command_line_scan.
func DropOpts(text []byte, args []string, w io.Writer) ([]byte, error) {
	var shorts, longs []string
	for _, a := range args {
		switch {
		case shortOpt.MatchString(a):
			shorts = append(shorts, a[1:])
		case longOpt.MatchString(a):
			longs = append(longs, a[2:])
		default:
			return nil, fmt.Errorf("dropopts: not an option this can remove: %s", cutil.PyRepr(a))
		}
	}

	blanked := cutil.Blank(text)
	a, z, ok := cutil.FindDefinition(text, blanked, "command_line_scan")
	if !ok {
		return nil, fmt.Errorf("dropopts: command_line_scan is not defined at file scope")
	}
	fn := text[a:z]

	want := map[string]bool{}
	for _, s := range shorts {
		want[s] = true
	}
	fn, held, err := DropShort(fn, 0, want)
	if err != nil {
		return nil, err
	}
	var missing []string
	for _, s := range shorts {
		if !held[s] {
			missing = append(missing, "-"+s)
		}
	}
	if len(missing) > 0 {
		sort.Strings(missing)
		return nil, fmt.Errorf("dropopts: no `case` in the option switch for %s -- it has "+
			"gone already, or the switch has moved", strings.Join(missing, " "))
	}
	fn, inArgs, err := DropShort(fn, 1, want)
	if err != nil {
		return nil, err
	}
	for _, n := range longs {
		if fn, err = DropLong(fn, n); err != nil {
			return nil, err
		}
	}

	// A long option that took an argument had a test in the argument switch,
	// and once its branch is gone that test compares against a name nothing
	// can produce.  An EMPTY one is dead whatever it names -- the one left
	// behind by --gui-dialog-file had been empty since the GUI went.
	sw, _, err := Switches(fn)
	if err != nil {
		return nil, err
	}
	o, c := sw[1].open, sw[1].close
	seg := fn[o+1 : c]
	empty := len(emptyTest.FindAll(seg, -1))
	seg = emptyTest.ReplaceAll(seg, nil)
	var rebuilt []byte
	rebuilt = append(rebuilt, fn[:o+1]...)
	rebuilt = append(rebuilt, seg...)
	fn = append(rebuilt, fn[c:]...)

	var dashed, ddashed []string
	for _, s := range shorts {
		dashed = append(dashed, "-"+s)
	}
	for _, n := range longs {
		ddashed = append(ddashed, "--"+n)
	}
	plural := "s"
	if empty == 1 {
		plural = ""
	}
	fmt.Fprintf(w, "  dropopts     %d short (%s), %d of them also in the argument switch; "+
		"%d long (%s); %d empty argument test%s\n",
		len(shorts), strings.Join(dashed, " "), len(inArgs),
		len(longs), strings.Join(ddashed, " "), empty, plural)

	out := make([]byte, 0, len(text))
	out = append(out, text[:a]...)
	out = append(out, fn...)
	return append(out, text[z:]...), nil
}
