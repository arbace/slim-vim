package harness

import "regexp"

// Exported doors onto harness internals the CHECK package needs.
//
// They are wrappers in a file of their own rather than renames in place, and
// that is a working arrangement rather than a style: two sessions are porting
// checks in parallel and both edit this package's existing files, so a rename
// in muslcase.go or zhostonly.go is the one edit that would collide.  A new
// file cannot.

// MuslCaseLibc is muslcase.libc(): this machine's libc towupper/towlower, as
// two {codepoint: offset} maps.  zero29 re-derives the musl half of the
// case-map union from it rather than from the table the phase deleted.
func MuslCaseLibc() (map[int]int, map[int]int, error) { return muslCaseLibc() }

// MuslCasePlanes is the number of codepoints muslcase walks: all of Unicode.
const MuslCasePlanes = muslCasePlanes

// HostVocab is zhostonly.VOCAB: the words a core that has given its host
// everything must no longer say.  zero36 reads which of them the core above
// the boundary still says.
func HostVocab() *regexp.Regexp { return vocab }

// StripStrings is zhostonly.strip_strings: string and character literals
// blanked, so a word inside a message is not counted as code.
func StripStrings(line string) string { return stripStrings(line) }

// DecodeReplace is bytes.decode('utf-8', 'replace'): ONE U+FFFD PER BAD BYTE,
// which is not what strings.ToValidUTF8 does -- that replaces each run with a
// single one.
func DecodeReplace(b []byte) string { return decodeReplace(b) }
