package cutil

// Depths returns the per-byte nesting depth of () [] {} over blanked text.
//
// depth[i] is the depth BEFORE consuming b[i], so an opener sits at the depth
// of its enclosing context and its closer sits one deeper.  That convention is
// what lets a caller ask "is this separator at top level?" by testing
// depth[i] == 0 at the separator itself.
//
// The Python remembers a large answer and hands the same list back, so its
// callers must read and never modify it.  This allocates, because the callers
// that matter compute it once per line or once per file and pass it down, and
// a shared mutable slice is a trap that buys nothing here.
func Depths(b []byte) []int {
	out := make([]int, len(b))
	d := 0
	for i, ch := range b {
		out[i] = d
		switch ch {
		case '(', '[', '{':
			d++
		case ')', ']', '}':
			d--
		}
	}
	return out
}
