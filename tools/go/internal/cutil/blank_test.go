package cutil

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

// blankRef asks tools/cutil.py for the same answer.  The corpus is pure ASCII,
// measured, so the surrogateescape round trip through a Python str is exact.
const blankRef = `
import sys
sys.path.insert(0, 'tools')
import cutil
d = open(sys.argv[1], encoding='utf-8', errors='surrogateescape').read()
sys.stdout.buffer.write(cutil.blank(d).encode('utf-8', errors='surrogateescape'))
`

// TestBlankAgainstPython requires SLIMTOOLS_REPO (the repository root, where
// tools/cutil.py lives) and SLIMTOOLS_CORPUS (a directory of .c files).  It
// skips without them rather than passing, because a test that silently finds
// no input is the vacuous pass this project keeps rediscovering.
func TestBlankAgainstPython(t *testing.T) {
	repo := os.Getenv("SLIMTOOLS_REPO")
	corpus := os.Getenv("SLIMTOOLS_CORPUS")
	if repo == "" || corpus == "" {
		t.Skip("set SLIMTOOLS_REPO and SLIMTOOLS_CORPUS to run this")
	}
	files, err := filepath.Glob(filepath.Join(corpus, "*.c"))
	if err != nil {
		t.Fatal(err)
	}
	if len(files) == 0 {
		t.Fatalf("no .c files under %s", corpus)
	}

	var checked, bytesChecked int
	for _, f := range files {
		src, err := os.ReadFile(f)
		if err != nil {
			t.Fatalf("%s: %v", f, err)
		}
		cmd := exec.Command("python3", "-c", blankRef, f)
		cmd.Dir = repo
		var ref bytes.Buffer
		cmd.Stdout = &ref
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			t.Fatalf("%s: python: %v", f, err)
		}

		got := Blank(src)
		if len(got) != len(src) {
			t.Fatalf("%s: Blank changed the length: %d -> %d", f, len(src), len(got))
		}
		if !bytes.Equal(got, ref.Bytes()) {
			t.Errorf("%s: differs from cutil.blank%s", filepath.Base(f), firstDiff(ref.Bytes(), got, src))
			continue
		}
		checked++
		bytesChecked += len(src)
	}
	// Reported so that a run which checked nothing cannot look like a pass.
	t.Logf("agreed with cutil.blank on %d of %d files, %d bytes", checked, len(files), bytesChecked)
	if checked == 0 {
		t.Fatal("no file agreed, so nothing was proven")
	}
}

func firstDiff(want, got, src []byte) string {
	n := len(want)
	if len(got) < n {
		n = len(got)
	}
	for i := 0; i < n; i++ {
		if want[i] != got[i] {
			lo := i - 40
			if lo < 0 {
				lo = 0
			}
			hi := i + 40
			if hi > len(src) {
				hi = len(src)
			}
			return " at byte " + itoa(i) + ": python " + quote(want[i]) +
				", go " + quote(got[i]) + "\n  source: " + string(src[lo:hi])
		}
	}
	return " in length only"
}

func quote(c byte) string {
	return "'" + string([]byte{c}) + "'"
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var b []byte
	for n > 0 {
		b = append([]byte{byte('0' + n%10)}, b...)
		n /= 10
	}
	return string(b)
}
