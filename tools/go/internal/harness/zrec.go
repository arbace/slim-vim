package harness

import (
	"regexp"
	"strings"
)

// The shape of a zero recording, and the two things that have to be scrubbed.
//
// Every zero harness writes the same sectioned text, so that one comparator
// can be told to ignore a whole dimension of it -- which is what
// pipes/zero.delta's `stderr-moved` and `screen-moved` tokens mean:
//
//	--- exit 0
//	--- bells 1
//	--- stream 2371 sha=dc2753fe11c84d69
//	--- stderr
//	Vim: Warning: Output is not to a terminal
//	--- snap 0 cursor=23,79 bells=0
//	<24 screen lines, right-stripped>
var (
	agoRe    = regexp.MustCompile(`\b\d+ (seconds?|minutes?|hours?|days?) ago`)
	bannerRe = regexp.MustCompile(`compiled [A-Z][a-z]{2} [ \d]\d \d{4} \d\d:\d\d:\d\d`)
)

// screenKinds is what the editor DREW, as opposed to what it returned.
var screenKinds = map[string]bool{"snap": true, "stream": true, "text": true, "msgs": true}

// pad replaces a match with a token PADDED TO THE WIDTH IT REPLACES, because
// the screen is columns: a shorter token moved the ruler into a different one,
// and three runs in eight disagreed until the padding went in.
func pad(match, token string) string {
	if len(token) >= len(match) {
		return token[:len(match)]
	}
	return token + strings.Repeat(" ", len(match)-len(token))
}

// Scrub removes the two things in a recording that are not the editor's
// behaviour: undo saying how long ago a change was made, which comes from the
// clock, and the version banner, which carries __DATE__ and __TIME__ and so
// moves on every rebuild.
func Scrub(s string) string {
	s = agoRe.ReplaceAllStringFunc(s, func(m string) string { return pad(m, "<ago>") })
	return bannerRe.ReplaceAllStringFunc(s, func(m string) string { return pad(m, "<compiled>") })
}

// Section is one section of a record: a header line, and an optional block.
func Section(name string, body *string) string {
	if body == nil {
		return "--- " + name + "\n"
	}
	return "--- " + name + "\n" + *body + "\n"
}

// Part is a header and its body, as Section wrote them.
type Part struct {
	Head, Body string
}

// SplitRecord returns the parts in order.
func SplitRecord(text string) []Part {
	var out []Part
	head := ""
	haveHead := false
	var body []string
	for _, line := range strings.Split(text, "\n") {
		if strings.HasPrefix(line, "--- ") {
			if haveHead {
				out = append(out, Part{head, strings.Join(body, "\n")})
			}
			head, body, haveHead = line[4:], nil, true
		} else if haveHead {
			body = append(body, line)
		}
	}
	if haveHead {
		out = append(out, Part{head, strings.Join(body, "\n")})
	}
	return out
}

func kindOf(head string) string {
	if f := strings.Fields(head); len(f) > 0 {
		return f[0]
	}
	return head
}

// Without is the record with whole dimensions dropped, for a declared token.
//
// `stderr` drops the stderr block; `screen` drops everything the editor DREW
// -- the snapshots, the text and message lines the command sweep keeps, and
// the stream's length and digest, since a changed redraw moves the digest by
// construction.  `exit` and `bells` are NEVER dropped: a phase that changes
// what the editor draws has not licensed it to change what it returns.
func Without(text string, dimensions map[string]bool) string {
	var b strings.Builder
	for _, p := range SplitRecord(text) {
		kind := kindOf(p.Head)
		if kind == "stderr" && dimensions["stderr"] {
			continue
		}
		if screenKinds[kind] && dimensions["screen"] {
			continue
		}
		body := p.Body
		b.WriteString(Section(p.Head, &body))
	}
	return b.String()
}

// Only is just one dimension of a record, for asking whether IT moved.
//
// Without answers "is the difference explained by these tokens"; this answers
// "did this token's dimension really move", which a declaration naming a
// dimension nothing touched would otherwise pass.
func Only(text, dimension string) string {
	var b strings.Builder
	for _, p := range SplitRecord(text) {
		kind := kindOf(p.Head)
		ok := kind == dimension
		if dimension == "screen" {
			ok = screenKinds[kind]
		}
		if ok {
			body := p.Body
			b.WriteString(Section(p.Head, &body))
		}
	}
	return b.String()
}

// Blocks splits a record that holds many, as the command sweep's does.
func Blocks(text, marker string) map[string]string {
	if marker == "" {
		marker = "=== "
	}
	out := map[string]string{}
	name := ""
	haveName := false
	var body []string
	for _, line := range strings.Split(text, "\n") {
		if strings.HasPrefix(line, marker) {
			if haveName {
				out[name] = strings.Join(body, "\n")
			}
			name, body, haveName = strings.TrimSpace(line[len(marker):]), nil, true
		} else if haveName {
			body = append(body, line)
		}
	}
	if haveName {
		out[name] = strings.Join(body, "\n")
	}
	return out
}
