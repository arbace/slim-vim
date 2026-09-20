package edit

import (
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

// An E is one phase's edit in progress: the tree, the tag its report lines
// carry, and the first error that stopped it.
//
// THE TRANSFORMATIONS DO NOT COLLAPSE AND THE SCAFFOLDING DOES.  Measured over
// all 225 heredocs, 94 are bespoke drivers over cutil and exactly one is a
// shape another shares -- so there is no cut to factor out.  But those 94
// drivers each open with the same twenty lines: a die() that prefixes the
// phase's tag, an in_function() that splices one definition back, a count check
// that refuses on anything but the expected number, and fold_never/drop_if/sub
// wrappers that print the act after it succeeds.  That is what this is.  A port
// then reads as the phase's argument and nothing else, which is the only way
// 33,000 lines of these are reviewable.
//
// ERRORS ACCUMULATE rather than returning at every step, so a port reads like
// the Python it replaces -- a sequence of acts, not a sequence of `if err !=
// nil`.  The first failure stops the rest: every later act would be operating
// on a tree the previous one did not produce, and its complaint would describe
// a state that never existed.
//
// ORDER IS OUTPUT.  Each act prints when it succeeds and not before, in the
// order it was asked for, because a phase program's log is what a human reads
// when comparing two phase commits.
type E struct {
	tag  string
	text []byte
	w    io.Writer
	err  error
}

// New starts an edit that reports under tag.
func New(tag string, text []byte, w io.Writer) *E {
	return &E{tag: tag, text: text, w: w}
}

// Done returns the rewritten tree, or the first error.
func (e *E) Done() ([]byte, error) {
	if e.err != nil {
		return nil, e.err
	}
	return e.text, nil
}

// Text is the tree as it now stands, for an act this file does not cover.
func (e *E) Text() []byte { return e.text }

// Set replaces the tree, for the same reason.
func (e *E) Set(text []byte) { e.text = text }

// Failed says whether an act has already refused.
func (e *E) Failed() bool { return e.err != nil }

func (e *E) die(format string, a ...interface{}) {
	if e.err == nil {
		e.err = fmt.Errorf("  %-12s %s", e.tag, fmt.Sprintf(format, a...))
	}
}

func (e *E) say(what string) { fmt.Fprintf(e.w, "  %-12s %s\n", e.tag, what) }

// CountIs refuses unless the pattern matches exactly n times.  It reports
// nothing: it is an assertion about the tree and not an act upon it.
func (e *E) CountIs(pattern string, n int, what string) {
	if e.err != nil {
		return
	}
	re, err := regexp.Compile(pattern)
	if err != nil {
		e.die("%s -- %v", what, err)
		return
	}
	if k := len(re.FindAll(e.text, -1)); k != n {
		e.die("%s -- matched %d times, expected %d", what, k, n)
	}
}

// Sub rewrites the pattern's n matches, refusing on any other count.
func (e *E) Sub(pattern, repl string, n int, what string) {
	if e.err != nil {
		return
	}
	re, err := regexp.Compile(pattern)
	if err != nil {
		e.die("%s -- %v", what, err)
		return
	}
	if k := len(re.FindAll(e.text, -1)); k != n {
		e.die("%s -- matched %d times, expected %d", what, k, n)
		return
	}
	e.text = re.ReplaceAll(e.text, []byte(repl))
	e.say(what)
}

// Cut deletes the pattern's n matches, refusing on any other count.
func (e *E) Cut(pattern string, n int, what string) { e.Sub(pattern, "", n, what) }

// FoldNever takes an `if` whose condition can no longer be true, keeping the
// else arm; DropIf takes one whose condition is now always true, keeping the
// then arm.  Both refuse unless the condition occurs exactly once, because
// these run on a tree every earlier phase has touched and an anchor that has
// stopped matching means the phase is about to fold something else.
func (e *E) FoldNever(pattern, what string) { e.fold(pattern, what, cutil.FoldNever) }

// DropIf is FoldNever's twin; see there.
func (e *E) DropIf(pattern, what string) { e.fold(pattern, what, cutil.DropIf) }

// FoldAlways keeps the then arm of an `if` whose condition is now always true,
// where DropIf removes the test and its braces.
func (e *E) FoldAlways(pattern, what string) { e.fold(pattern, what, cutil.FoldAlways) }

func (e *E) fold(pattern, what string, f func([]byte, string, int) ([]byte, error)) {
	if e.err != nil {
		return
	}
	e.CountIs(pattern, 1, what)
	if e.err != nil {
		return
	}
	out, err := f(e.text, pattern, 1)
	if err != nil {
		e.die("%s -- %v", what, err)
		return
	}
	e.text = out
	e.say(what)
}

// InFunction runs the acts against ONE file-scope definition's body and splices
// it back, which is what every one of these heredocs spells in_function().
// Scoping matters: a pattern that is unique inside one function is very often
// not unique in a 180,000-line file, and a count that passes for the wrong
// reason is the failure this whole construct exists to prevent.
func (e *E) InFunction(name string, acts func(*E)) {
	if e.err != nil {
		return
	}
	a, z, ok := cutil.FindDefinition(e.text, cutil.Blank(e.text), name)
	if !ok {
		e.die("%s is not defined at file scope", name)
		return
	}
	inner := &E{tag: e.tag, text: e.text[a:z], w: e.w}
	acts(inner)
	if inner.err != nil {
		e.err = inner.err
		return
	}
	out := append([]byte{}, e.text[:a]...)
	out = append(out, inner.text...)
	e.text = append(out, e.text[z:]...)
}

// Literal replaces the single occurrence of old with new, refusing on any other
// count.  It is Sub without a regular expression, for the many places where the
// C being matched is full of parentheses and stars and the pattern would be
// mostly backslashes.
func (e *E) Literal(old, new, what string) { e.LiteralN(old, new, 1, what) }

// LiteralN is Literal for a phrase that occurs n times and must be rewritten at
// every one of them.  The count is stated because these edits run on a tree
// every earlier phase has touched: a phrase that has gone from two occurrences
// to one has had a reader removed somewhere else, and rewriting "however many
// there are" would carry that silently into the boundary.
func (e *E) LiteralN(old, new string, n int, what string) {
	if e.err != nil {
		return
	}
	if k := countBytes(e.text, old); k != n {
		e.die("%s -- occurs %d times, expected %d", what, k, n)
		return
	}
	for i := 0; i < n; i++ {
		e.text = replaceBytes(e.text, old, new)
	}
	e.say(what)
}

// Always keeps the body of an `if` whose condition is now always true AND drops
// the `else` that follows it, where cutil.FoldAlways refuses a block that has
// one.
//
// The difference is the whole reason this exists: a condition that has become
// always-true makes its else arm unreachable, so leaving the else behind would
// keep code that can no longer run.  cutil.FoldAlways is right to refuse -- it
// is written for the shape where there is nothing to decide -- and this is the
// other shape, which whim57 met first and spelled out by hand.  An `else if`
// refuses, because what to do with the rest of the chain is a judgement and not
// a rewrite.
func (e *E) Always(pattern, what string) {
	if e.err != nil {
		return
	}
	e.CountIs(pattern, 1, what)
	if e.err != nil {
		return
	}
	re := regexp.MustCompile(pattern)
	m := re.FindIndex(e.text)
	b := cutil.Blank(e.text)
	k, o, c, head, err := cutil.Guarded(e.text, b, m)
	if err != nil {
		e.die("%s -- %v", what, err)
		return
	}
	if head != "if" {
		e.die("%s -- not a plain if", what)
		return
	}
	end := indexFrom(e.text, []byte("\n"), c) + 1
	body := cutil.Dedent4(e.text[indexFrom(e.text, []byte("\n"), o)+1 : lastNewlineBefore(e.text, c)+1])
	rest := e.text[end:]
	if elseIf := regexp.MustCompile(`^[ \t]*else[ \t]+if\b`); elseIf.Match(rest) {
		e.die("%s -- an else if follows", what)
		return
	}
	if nxt := regexp.MustCompile(`^[ \t]*else\b`).FindIndex(rest); nxt != nil {
		o2 := indexFrom(b, []byte("{"), end+nxt[1])
		c2 := cutil.Match(e.text, o2)
		end = indexFrom(e.text, []byte("\n"), c2) + 1
	}
	out := append([]byte{}, e.text[:k]...)
	out = append(out, body...)
	e.text = append(out, e.text[end:]...)
	e.say(what)
}

func lastNewlineBefore(text []byte, i int) int {
	for j := i - 1; j >= 0; j-- {
		if text[j] == '\n' {
			return j
		}
	}
	return -1
}

// FoldNeverN folds n occurrences of the same condition, taking the LAST one
// each time.
//
// Why the last and not the first: cutil.FoldNever is written for a pattern that
// occurs once, so folding several means narrowing the text until it does.
// Splitting at the last match's line start leaves exactly one match in the tail
// and none in the head, and does it without the head's offsets moving under the
// next iteration -- which is the same reason CLAUDE.md gives for rewriting a
// whole file in ONE pass rather than recomputing spans between two.
func (e *E) FoldNeverN(pattern string, n int, what string) {
	e.repeat(pattern, n, what, cutil.FoldNever)
}

// FoldAlwaysN is FoldNeverN for the other arm.
func (e *E) FoldAlwaysN(pattern string, n int, what string) {
	e.repeat(pattern, n, what, cutil.FoldAlways)
}

// FoldNeverRepeat and FoldAlwaysRepeat are FoldNeverN and FoldAlwaysN for the
// phases that report the COUNT -- "writing a no-file buffer refused (3)".
//
// The difference is per phase and not per primitive: whim60's fold-several says
// only what it did, whim62's says how many times.  Both are the heredoc's own
// wording, and the report is the thing this port must reproduce, so the
// distinction is kept rather than harmonised.
func (e *E) FoldNeverRepeat(pattern string, n int, what string) {
	e.repeatSay(pattern, n, what, cutil.FoldNever, true)
}

// FoldAlwaysRepeat is FoldNeverRepeat for the other arm.
func (e *E) FoldAlwaysRepeat(pattern string, n int, what string) {
	e.repeatSay(pattern, n, what, cutil.FoldAlways, true)
}

func (e *E) repeat(pattern string, n int, what string, f func([]byte, string, int) ([]byte, error)) {
	e.repeatSay(pattern, n, what, f, false)
}

func (e *E) repeatSay(pattern string, n int, what string, f func([]byte, string, int) ([]byte, error), withCount bool) {
	if e.err != nil {
		return
	}
	e.CountIs(pattern, n, what)
	if e.err != nil {
		return
	}
	re := regexp.MustCompile(pattern)
	for i := 0; i < n; i++ {
		ms := re.FindAllIndex(e.text, -1)
		if len(ms) == 0 {
			e.die("%s -- ran out of matches after %d of %d", what, i, n)
			return
		}
		var out []byte
		var err error
		if len(ms) == 1 {
			out, err = f(e.text, pattern, 1)
		} else {
			last := ms[len(ms)-1][0]
			start := lastNewlineBefore(e.text, last) + 1
			var tail []byte
			tail, err = f(e.text[start:], pattern, 1)
			if err == nil {
				out = append(append([]byte{}, e.text[:start]...), tail...)
			}
		}
		if err != nil {
			e.die("%s -- %v", what, err)
			return
		}
		e.text = out
	}
	if withCount {
		e.say(fmt.Sprintf("%s (%d)", what, n))
	} else {
		e.say(what)
	}
}

// Refuse stops the edit with a message of the phase's own wording, for the
// assertions that are not a count of a pattern -- "do_exedit mentions n 4 times
// after the title went, expected 3 (declaration, readonlymode save and
// restore)".  CountIs would say the right thing about the wrong subject.
func (e *E) Refuse(format string, a ...interface{}) { e.die(format, a...) }

// Mentions counts whole-word occurrences of a name in the tree as it stands.
func (e *E) Mentions(name string) int {
	return len(regexp.MustCompile(`\b`+regexp.QuoteMeta(name)+`\b`).FindAll(e.text, -1))
}
