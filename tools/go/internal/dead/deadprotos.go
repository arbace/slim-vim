// Package dead holds the six dead-code tools tools/sweep.sh runs before
// canon, in its order: deadsweep, deadprotos, typereach, funcreach,
// deadfields, deadenums.
//
// They feed each other -- deleting a function orphans a type, deleting a type
// orphans a prototype, deleting a field orphans an enumerator -- so none is
// finished until all are, which is why sweep.sh loops them to a fixpoint on
// the file's digest rather than running each once.
//
// Unlike the canonicalisers, these do not all rewrite unconditionally and do
// not all normalise a trailing newline.  Which is which is part of the
// contract: tools/sweep.sh sees only the file's sha256, so a tool that adds a
// newline the Python would not adds a round to every sweep.
package dead

import (
	"bytes"
	"regexp"
)

// proto is a prototype at file scope: type, name, parameter list, semicolon,
// all on one line -- which the canonicalisers guarantee, having joined every
// parenthesised group onto one line.
var proto = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_ \t*]*?\b(\w+)\s*\([^;]*\)\s*;\s*$`)

var word = regexp.MustCompile(`[A-Za-z_]\w*`)

var define = regexp.MustCompile(`^[ \t]*#[ \t]*define[ \t]+(\w+)`)

// keepBanners are the two former headers whose prototypes must never be
// dropped.  A prototype in this program's own headers naming a function that
// does not exist is simply wrong; these two are not.  osdef.h declares libc
// functions the platform may not have declared and xdiff.h declares the xdiff
// library's interface -- both describe code that lives elsewhere by design,
// and deleting them because nothing here calls them would delete a true
// statement.
var keepBanners = []string{"osdef.h", "xdiff.h"}

// DeadProtos deletes prototypes for functions that no longer exist, and
// returns the names it dropped, in file order.
//
// The dead-code sweep keys on -Wall, and gcc says nothing at all about a
// declaration of a function that is never defined and never called: it is a
// promise about another translation unit, and in a file that IS the whole
// program that promise is false.  They matter for what they keep alive -- a
// prototype is a root for the type sweep, so deleting one can make a type
// unreachable, which is why this runs inside the fixpoint and not once.
//
// The test needs no C parsing: a declaration at file scope whose name appears
// NOWHERE else in the file.  A defined function's name appears at least twice,
// its prototype and its definition; a called one more.  One occurrence means
// nothing refers to it.
func DeadProtos(src []byte) (out []byte, dropped [][]byte) {
	lines := bytes.Split(src, []byte{'\n'})

	// A mention inside a #define body counts only if the MACRO is used.  An
	// unused macro's body is not a reference to anything.  But ignoring every
	// macro body is wrong in the other direction -- some names are mentioned
	// only from macro bodies whose macros are called all over the file -- so
	// live macros contribute their bodies and dead ones do not, and liveness
	// is itself a fixpoint, because a live macro can be what makes another
	// one live.
	//
	// Dead for whim and zero, which have no #define at all; 34,330 captures
	// and 24,385 fixpoint steps on slim, measured.
	seen := map[string]int{}
	type macro struct {
		name string
		line []byte
	}
	var defines []macro
	for _, line := range lines {
		if m := define.FindSubmatch(line); m != nil {
			defines = append(defines, macro{string(m[1]), line})
			continue
		}
		for _, w := range word.FindAll(line, -1) {
			seen[string(w)]++
		}
	}
	live := map[string]bool{}
	for {
		grew := false
		for _, d := range defines {
			if !live[d.name] && seen[d.name] > 0 {
				live[d.name] = true
				for _, w := range word.FindAll(d.line, -1) {
					seen[string(w)]++
				}
				grew = true
			}
		}
		if !grew {
			break
		}
	}

	protected := map[int]bool{}
	inside := ""
	for i, line := range lines {
		if bytes.HasPrefix(line, []byte("// ")) && bytes.Contains(line, []byte("begin ")) {
			inside = ""
			for _, k := range keepBanners {
				if bytes.Contains(line, []byte("begin "+k)) {
					inside = k
					break
				}
			}
		} else if bytes.HasPrefix(line, []byte("// ")) && bytes.Contains(line, []byte("end ")) &&
			inside != "" {
			if bytes.Contains(line, []byte("end "+inside)) {
				inside = ""
			}
		}
		if inside != "" {
			protected[i] = true
		}
	}

	kept := make([][]byte, 0, len(lines))
	for i, line := range lines {
		if !protected[i] {
			if m := proto.FindSubmatch(line); m != nil && seen[string(m[1])] == 1 {
				dropped = append(dropped, m[1])
				continue
			}
		}
		kept = append(kept, line)
	}

	// No trailing-newline normalisation, and the caller writes only when
	// something was dropped: both are this tool's contract and not an
	// oversight.  Joining the fields split on '\n' reproduces the input
	// exactly when nothing is removed.
	return bytes.Join(kept, []byte{'\n'}), dropped
}
