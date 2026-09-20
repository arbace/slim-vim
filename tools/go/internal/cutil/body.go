package cutil

import (
	"bytes"
	"fmt"
	"regexp"
)

// ReplaceBody swaps a file-scope function's body, MATCHING BRACES rather than
// scanning for the next line that is only a brace.  It reports how many lines
// the old body spanned, which every caller prints.
//
// A depth count that believes every brace is a brace runs off the end of the
// file: these bodies hold string literals like "*?[{" and shell fragments full
// of them.  Blank() is what makes the count safe, and taking the helper out of
// the tool that happened to need it last is what stops the next caller writing
// a fifth copy -- which is how the lazy `(?:[^\n]*\n)*?\}` bug kept coming
// back.
//
// The error names the function and not the tool, so a caller wraps it with its
// own words.
func ReplaceBody(s []byte, name, body string) ([]byte, int, error) {
	blanked := Blank(s)
	head := regexp.MustCompile(`(?m)^` + regexp.QuoteMeta(name) + `\([^\n]*\n`)
	m := head.FindIndex(s)
	if m == nil {
		return nil, 0, fmt.Errorf("%s is not defined at file scope any more", name)
	}
	rel := bytes.IndexByte(blanked[m[1]:], '{')
	if rel < 0 {
		return nil, 0, fmt.Errorf("%s is unbalanced", name)
	}
	opening := m[1] + rel
	closing := Match(blanked, opening)
	if closing < 0 {
		return nil, 0, fmt.Errorf("%s is unbalanced", name)
	}
	was := bytes.Count(s[opening:closing], []byte{'\n'})
	out := make([]byte, 0, len(s))
	out = append(out, s[:opening]...)
	out = append(out, "{\n"...)
	out = append(out, body...)
	out = append(out, "\n}"...)
	return append(out, s[closing+1:]...), was, nil
}

// FindBody is ReplaceBody's other half, for a caller that has to LOOK at the
// old body before deciding -- nofind refuses a file whose body no longer
// delegates, which is how it tells a file it has not seen from its own output.
func FindBody(s []byte, name string) (opening, closing int, err error) {
	blanked := Blank(s)
	head := regexp.MustCompile(`(?m)^` + regexp.QuoteMeta(name) + `\([^\n]*\n`)
	m := head.FindIndex(s)
	if m == nil {
		return 0, 0, fmt.Errorf("%s is not defined at file scope any more", name)
	}
	rel := bytes.IndexByte(blanked[m[1]:], '{')
	if rel < 0 {
		return 0, 0, fmt.Errorf("%s is unbalanced", name)
	}
	opening = m[1] + rel
	closing = Match(blanked, opening)
	if closing < 0 {
		return 0, 0, fmt.Errorf("%s is unbalanced", name)
	}
	return opening, closing, nil
}

// Body is ReplaceBody and FindBody's primitive, and it carries NO WORDING.
//
// The tools that use it do not agree on their refusals: nostat, nofind,
// noshellout and noglob say "is not defined at file scope any more" and
// nostartup and nohome say "is not defined at file scope", with noglob adding
// a clause of its own.  A helper that supplies the sentence makes every
// caller say the same thing, which is a difference in the tool rather than in
// the cut -- so a caller that needs its own words takes the offsets and
// writes them.
func Body(s []byte, name string) (opening, closing int, found, balanced bool) {
	blanked := Blank(s)
	head := regexp.MustCompile(`(?m)^` + regexp.QuoteMeta(name) + `\([^\n]*\n`)
	m := head.FindIndex(s)
	if m == nil {
		return 0, 0, false, false
	}
	rel := bytes.IndexByte(blanked[m[1]:], '{')
	if rel < 0 {
		return 0, 0, true, false
	}
	opening = m[1] + rel
	closing = Match(blanked, opening)
	return opening, closing, true, closing >= 0
}
