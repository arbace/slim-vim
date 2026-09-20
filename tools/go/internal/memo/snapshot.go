package memo

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
)

// snapshotExclude is what a boundary does NOT count.
//
// Build products, because they are not the phase's output; auto/config.log and
// its siblings, because they carry a timestamp and a boundary containing one
// would never equal itself twice; and both built binaries, because version.c
// embeds __DATE__ and __TIME__.  Naming only /vim$ made every whim boundary
// count its own binary, and nothing caught it for eleven phases -- a phase
// replayed from tier 3 copies the recorded digest rather than recomputing it,
// so only a run that recomputes can falsify a boundary.
//
// src/xxd/xxd is excluded for a reason of the same kind: its debug info
// records the directory it was built in, so slim's first two boundaries
// depended on WHERE the phase ran.  A pass that always runs in one place could
// never show that; a verify that runs each phase in a scratch root of its own
// showed it on its first run.
var snapshotExclude = regexp.MustCompile(
	`/objects/|/auto/config\.(log|status|cache)$|\.(o|d)$|/(whim-|zero-)?vim$|/xxd/xxd$`)

// Snapshot writes a boundary: the tar that is the restore point, and the
// digest that is its meaning.
//
// The digest is a sha256 over a manifest of every file's own sha256, so two
// trees agree exactly when every file in them does.  The tar is written
// reproducibly -- sorted, zero mtime, zero ownership -- so that the same tree
// gives the same bytes.
func Snapshot(dir, tarOut, shaOut string, w io.Writer) error {
	if err := os.MkdirAll(filepath.Dir(tarOut), 0o755); err != nil {
		return err
	}

	var paths []string
	err := filepath.Walk(dir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		rel, rerr := filepath.Rel(dir, path)
		if rerr != nil {
			return rerr
		}
		if info.IsDir() {
			if rel == ".git" {
				return filepath.SkipDir
			}
			return nil
		}
		paths = append(paths, "./"+rel)
		return nil
	})
	if err != nil {
		return err
	}
	sort.Strings(paths)

	var manifest []byte
	for _, rel := range paths {
		data, err := os.ReadFile(filepath.Join(dir, rel))
		if err != nil {
			continue
		}
		sum := sha256.Sum256(data)
		// Matched without the newline: grep's $ is end of line, Go's is end of
		// text.  See TreeDigest.
		line := fmt.Sprintf("%s  %s", hex.EncodeToString(sum[:]), rel)
		if snapshotExclude.MatchString(line) {
			continue
		}
		manifest = append(manifest, line...)
		manifest = append(manifest, '\n')
	}
	if err := os.WriteFile(shaOut+".files", manifest, 0o644); err != nil {
		return err
	}
	sum := sha256.Sum256(manifest)
	digest := hex.EncodeToString(sum[:])
	if err := os.WriteFile(shaOut, []byte(digest+"\n"), 0o644); err != nil {
		return err
	}

	cmd := exec.Command("tar", "--create", "--file", tarOut,
		"--sort=name", "--mtime=@0", "--owner=0", "--group=0", "--numeric-owner",
		"--format=gnu", "--exclude=.git", "-C", dir, ".")
	if err := cmd.Run(); err != nil {
		return err
	}

	n := 0
	for _, c := range manifest {
		if c == '\n' {
			n++
		}
	}
	fmt.Fprintf(w, "  %-12s %s  %d files, %s\n", "snapshot", digest[:12], n, humanSize(tarOut))
	return nil
}

// humanSize is `du -h | cut -f1` for one file, close enough for a log line.
func humanSize(path string) string {
	fi, err := os.Stat(path)
	if err != nil {
		return "?"
	}
	n := fi.Size()
	switch {
	case n >= 1<<30:
		return fmt.Sprintf("%.1fG", float64(n)/(1<<30))
	case n >= 1<<20:
		return fmt.Sprintf("%.1fM", float64(n)/(1<<20))
	case n >= 1<<10:
		return fmt.Sprintf("%.1fK", float64(n)/(1<<10))
	}
	return fmt.Sprintf("%d", n)
}
