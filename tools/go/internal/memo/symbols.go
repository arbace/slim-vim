package memo

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

// SymbolCache is where answers are kept, keyed by the source's own content.
const SymbolCache = ".cache/symbols"

// Symbols writes <out>/undefined and <out>/external: the libc surface of a
// source file, and what it defines externally.
//
// A phase asks this twice -- once of its input, to report what the phase cost
// in dependencies, and once of its output, to check it -- and compiling a
// 152,000-line translation unit takes six and a half seconds.  THE INPUT OF
// ONE PHASE IS THE OUTPUT OF THE ONE BEFORE: the same bytes, compiled twice, a
// phase apart.  So the answer is cached under the file's own sha256, the same
// way tier 3 is keyed: not by time, not by path, by content.  A phase's second
// question is the next phase's first, and the second time it is free.  Nothing
// can go stale, because a different file has a different key.
func Symbols(src, out string) error {
	if err := os.MkdirAll(out, 0o755); err != nil {
		return err
	}
	data, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	sum := sha256.Sum256(data)
	sha := hex.EncodeToString(sum[:])[:32]

	if err := os.MkdirAll(SymbolCache, 0o755); err != nil {
		return err
	}
	cu := filepath.Join(SymbolCache, sha+".u")
	cd := filepath.Join(SymbolCache, sha+".d")
	if u, err1 := os.ReadFile(cu); err1 == nil {
		if d, err2 := os.ReadFile(cd); err2 == nil {
			if err := os.WriteFile(filepath.Join(out, "undefined"), u, 0o644); err != nil {
				return err
			}
			return os.WriteFile(filepath.Join(out, "external"), d, 0o644)
		}
	}

	obj := filepath.Join(out, ".symbols.o")
	cmd := exec.Command("gcc", "-c", "-O0", "-o", obj, src)
	cmd.Stderr = nil
	if err := cmd.Run(); err != nil {
		return err
	}
	defer os.Remove(obj)

	undef, err := nmField(obj, []string{"-u"}, 1)
	if err != nil {
		return err
	}
	ext, err := nmField(obj, []string{"--extern-only", "--defined-only"}, -1)
	if err != nil {
		return err
	}

	if err := os.WriteFile(filepath.Join(out, "undefined"), undef, 0o644); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(out, "external"), ext, 0o644); err != nil {
		return err
	}
	if err := os.WriteFile(cu, undef, 0o644); err != nil {
		return err
	}
	return os.WriteFile(cd, ext, 0o644)
}

// nmField runs nm and takes one whitespace-separated field per line: index 1
// for `nm -u` (which prints "U name"), or -1 for the last field.  The result
// is byte-sorted, which is what `sort` does here -- measured, this system's
// sort is C collation and Go's byte order agrees with it.
func nmField(obj string, args []string, field int) ([]byte, error) {
	cmd := exec.Command("nm", append(args, obj)...)
	var stdout bytes.Buffer
	cmd.Stdout = &stdout
	if err := cmd.Run(); err != nil {
		return nil, err
	}
	var names []string
	for _, line := range strings.Split(stdout.String(), "\n") {
		f := strings.Fields(line)
		if len(f) == 0 {
			continue
		}
		i := field
		if i < 0 {
			i = len(f) - 1
		}
		if i >= len(f) {
			continue
		}
		names = append(names, f[i])
	}
	sort.Strings(names)
	var b bytes.Buffer
	for _, n := range names {
		b.WriteString(n)
		b.WriteByte('\n')
	}
	return b.Bytes(), nil
}
