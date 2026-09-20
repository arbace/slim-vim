package edit

import (
	"io"
	"sort"
)

// A QueryFunc answers a question about the tree and writes the answer to w.  It
// does NOT rewrite the tree.
//
// Some phase heredocs are not edits at all: `names=$(python3 - "$f" <<'PY' ...
// PY)` computes a list, prints it, and the SHELL uses the output as arguments
// to the next command.  whim2 proves every menu and spell command is already
// ex_ni; whim54 finds every options[] row with no variable and hands the names
// to dropoptions.  Running those through the edit path would rewrite the file
// with identical bytes, which is harmless and dishonest -- a query that writes
// is a query a reader has to check.
type QueryFunc func(text []byte, w io.Writer) error

var queries = map[string]QueryFunc{}

func registerQuery(name string, f QueryFunc) {
	if _, dup := queries[name]; dup {
		panic("edit: query " + name + " registered twice")
	}
	queries[name] = f
}

// LookupQuery returns the query for a phase, and whether there is one.
func LookupQuery(name string) (QueryFunc, bool) {
	f, ok := queries[name]
	return f, ok
}

// QueryNames returns every query, sorted.
func QueryNames() []string {
	out := make([]string, 0, len(queries))
	for k := range queries {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}
