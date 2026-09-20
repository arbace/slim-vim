package harness

import "errors"

// ErrReported means the tool has ALREADY written its own diagnostics and the
// caller must add nothing.
//
// The Python these ports follow prints its findings line by line and then
// exits 1 with no summary, so a Go runner that printed the returned error too
// would emit one line the Python does not -- measured on muslcase, where a
// perturbed table gave the identical per-codepoint diagnostic plus a spurious
// "1 disagreements with libc".  A comparison that reads only the first line of
// a refusal would never have seen it.
var ErrReported = errors.New("reported")
