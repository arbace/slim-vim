package harness

import (
	"regexp"
	"strconv"
	"strings"
	"unicode/utf8"
)

// cellWidth is how many columns a character occupies.
//
// An emulator that counts CHARACTERS rather than cells gets every multibyte
// line wrong: a combining mark takes none, and an East Asian wide glyph takes
// two.  The tables are generated from the same unicodedata zscreen.py
// consults, so the two agree by construction rather than because a second
// Unicode library happens to match.
func cellWidth(r rune) int {
	if inRanges(zeroWidth, r) {
		return 0
	}
	if inRanges(wideWidth, r) {
		return 2
	}
	return 1
}

func inRanges(rs []rng, r rune) bool {
	lo, hi := 0, len(rs)-1
	for lo <= hi {
		mid := (lo + hi) / 2
		switch {
		case r < rs[mid].lo:
			hi = mid - 1
		case r > rs[mid].hi:
			lo = mid + 1
		default:
			return true
		}
	}
	return false
}

var csiRe = regexp.MustCompile(`^\x1b\[([0-9;?>!]*)([@-~])`)

// Snap is one redraw: the screen as text, the cursor, and how many bells had
// rung.
type Snap struct {
	Text  string
	Y, X  int
	Bells int
}

// Screen is a 24x80 terminal rebuilt from the escape sequences the editor
// wrote.  It is zero's instrument: keystrokes in on stdin, escape sequences
// out on stdout, and a screen per redraw.
type Screen struct {
	Rows, Cols int
	buf        [][]string
	Y, X       int
	top, bot   int
	Bells      int
	Snaps      []Snap
}

func NewScreen(rows, cols int) *Screen {
	s := &Screen{Rows: rows, Cols: cols, top: 0, bot: rows - 1}
	s.buf = make([][]string, rows)
	for i := range s.buf {
		s.buf[i] = s.blank()
	}
	return s
}

func (s *Screen) blank() []string {
	row := make([]string, s.Cols)
	for i := range row {
		row[i] = " "
	}
	return row
}

func (s *Screen) clip() {
	s.Y = max(0, min(s.Rows-1, s.Y))
	s.X = max(0, min(s.Cols-1, s.X))
}

func (s *Screen) lf() {
	if s.Y == s.bot {
		copy(s.buf[s.top:s.bot], s.buf[s.top+1:s.bot+1])
		s.buf[s.bot] = s.blank()
	} else {
		s.Y = min(s.Rows-1, s.Y+1)
	}
}

func (s *Screen) ri() {
	if s.Y == s.top {
		copy(s.buf[s.top+1:s.bot+1], s.buf[s.top:s.bot])
		s.buf[s.top] = s.blank()
	} else {
		s.Y = max(0, s.Y-1)
	}
}

func (s *Screen) put(r rune) {
	w := cellWidth(r)
	if w == 0 {
		// A combining mark joins the cell before it.
		x := max(0, s.X-1)
		s.buf[s.Y][x] += string(r)
		return
	}
	if s.X+w > s.Cols {
		s.X = 0
		s.lf()
	}
	s.buf[s.Y][s.X] = string(r)
	for k := 1; k < w; k++ {
		// The second cell of a wide glyph is empty, not a space.
		s.buf[s.Y][s.X+k] = ""
	}
	s.X += w
}

// Dump is the screen as text, each row right-trimmed.
func (s *Screen) Dump() string {
	rows := make([]string, s.Rows)
	for i, r := range s.buf {
		rows[i] = strings.TrimRight(strings.Join(r, ""), " \t\n\v\f\r")
	}
	return strings.Join(rows, "\n")
}

// Feed consumes the escape stream.
func (s *Screen) Feed(data []byte) {
	str := decodeReplace(data)
	for i := 0; i < len(str); {
		r, size := utf8.DecodeRuneInString(str[i:])
		if r == 0x1b {
			if m := csiRe.FindStringSubmatchIndex(str[i:]); m != nil {
				s.csi(str[i+m[2]:i+m[3]], str[i+m[4]:i+m[5]])
				i += m[1]
				continue
			}
			var next byte
			if i+1 < len(str) {
				next = str[i+1]
			}
			switch next {
			case 'M':
				s.ri()
				i += 2
				continue
			case 'D':
				s.lf()
				i += 2
				continue
			case ']': // OSC ... BEL or ST
				j := strings.IndexByte(str[i:], 0x07)
				k := strings.Index(str[i:], "\x1b\\")
				end := -1
				switch {
				case j >= 0 && k >= 0:
					end = min(j, k)
				case j >= 0:
					end = j
				case k >= 0:
					end = k
				}
				if end < 0 {
					return
				}
				if end == j {
					i += end + 1
				} else {
					i += end + 2
				}
				continue
			case '(', ')': // charset selection
				i += 3
				continue
			}
			i += 2 // ESC = , ESC > , ESC 7 ...
			continue
		}
		switch r {
		case '\r':
			s.X = 0
		case '\n':
			s.lf()
		case '\b':
			s.X = max(0, s.X-1)
		case '\t':
			s.X = min(s.Cols-1, (s.X/8+1)*8)
		case 0x07:
			s.Bells++
		case 0x0e, 0x0f:
		default:
			s.put(r)
		}
		i += size
	}
}

func (s *Screen) csi(params, final string) {
	if len(params) > 0 && (params[0] == '?' || params[0] == '>' || params[0] == '!') {
		// SHOW CURSOR ends a redraw, and is the only reason the message line
		// is recordable at all.  Identical consecutive screens are not
		// recorded twice: the editor shows the cursor far more often than it
		// changes anything.
		if params == "?25" && final == "h" {
			snap := Snap{s.Dump(), s.Y, s.X, s.Bells}
			if len(s.Snaps) == 0 || s.Snaps[len(s.Snaps)-1].Text != snap.Text {
				s.Snaps = append(s.Snaps, snap)
			}
		}
		return
	}
	var ps []int
	if params != "" {
		for _, f := range strings.Split(params, ";") {
			n, _ := strconv.Atoi(f)
			ps = append(ps, n)
		}
	}
	p := func(i, d int) int {
		if i < len(ps) && ps[i] != 0 {
			return ps[i]
		}
		return d
	}

	switch final {
	case "H", "f":
		s.Y, s.X = p(0, 1)-1, p(1, 1)-1
		s.clip()
	case "A":
		s.Y -= p(0, 1)
		s.clip()
	case "B":
		s.Y += p(0, 1)
		s.clip()
	case "C":
		s.X += p(0, 1)
		s.clip()
	case "D":
		s.X -= p(0, 1)
		s.clip()
	case "G":
		s.X = p(0, 1) - 1
		s.clip()
	case "d":
		s.Y = p(0, 1) - 1
		s.clip()
	case "K":
		switch p(0, 0) {
		case 0:
			for x := s.X; x < s.Cols; x++ {
				s.buf[s.Y][x] = " "
			}
		case 1:
			for x := 0; x <= s.X; x++ {
				s.buf[s.Y][x] = " "
			}
		default:
			s.buf[s.Y] = s.blank()
		}
	case "J":
		switch p(0, 0) {
		case 0:
			for x := s.X; x < s.Cols; x++ {
				s.buf[s.Y][x] = " "
			}
			for y := s.Y + 1; y < s.Rows; y++ {
				s.buf[y] = s.blank()
			}
		case 1:
			for y := 0; y < s.Y; y++ {
				s.buf[y] = s.blank()
			}
			for x := 0; x <= s.X; x++ {
				s.buf[s.Y][x] = " "
			}
		default:
			for y := 0; y < s.Rows; y++ {
				s.buf[y] = s.blank()
			}
		}
	case "L":
		for i := 0; i < p(0, 1); i++ {
			if s.top <= s.Y && s.Y <= s.bot {
				copy(s.buf[s.Y+1:s.bot+1], s.buf[s.Y:s.bot])
				s.buf[s.Y] = s.blank()
			}
		}
	case "M":
		for i := 0; i < p(0, 1); i++ {
			if s.top <= s.Y && s.Y <= s.bot {
				copy(s.buf[s.Y:s.bot], s.buf[s.Y+1:s.bot+1])
				s.buf[s.bot] = s.blank()
			}
		}
	case "@":
		for i := 0; i < p(0, 1); i++ {
			row := s.buf[s.Y]
			copy(row[s.X+1:], row[s.X:s.Cols-1])
			row[s.X] = " "
		}
	case "P":
		for i := 0; i < p(0, 1); i++ {
			row := s.buf[s.Y]
			copy(row[s.X:], row[s.X+1:])
			row[s.Cols-1] = " "
		}
	case "X":
		for x := s.X; x < min(s.Cols, s.X+p(0, 1)); x++ {
			s.buf[s.Y][x] = " "
		}
	case "r":
		if len(ps) > 0 {
			s.top = p(0, 1) - 1
		} else {
			s.top = 0
		}
		if len(ps) > 1 && ps[1] != 0 {
			s.bot = p(1, s.Rows) - 1
		} else {
			s.bot = s.Rows - 1
		}
		s.top = max(0, min(s.Rows-1, s.top))
		s.bot = max(s.top, min(s.Rows-1, s.bot))
		s.Y, s.X = 0, 0
	}
	// m, h, l, n, c, t, S, T and the rest: consumed, not recorded.
}

// decodeReplace is bytes.decode('utf-8', 'replace'): invalid sequences become
// U+FFFD, one per bad byte, which is what the screen then draws.
func decodeReplace(b []byte) string {
	if utf8.Valid(b) {
		return string(b)
	}
	var sb strings.Builder
	for i := 0; i < len(b); {
		r, size := utf8.DecodeRune(b[i:])
		if r == utf8.RuneError && size <= 1 {
			sb.WriteRune(utf8.RuneError)
			i++
			continue
		}
		sb.WriteRune(r)
		i += size
	}
	return sb.String()
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}
