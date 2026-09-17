"""A terminal screen, rebuilt from the bytes the editor wrote.

Zero's instrument is the screen: the core has no file to write and no stream to
print on, so what it did is what it drew.  This replays the escape sequences the
editor emits under `xterm`/`xterm-256color` into a 24x80 matrix -- CUP,
CUU/CUD/CUF/CUB, CHA/VPA, EL, ED, IL, DL, ICH, DCH, ECH, DECSTBM, CR, LF, BS,
TAB, BEL, RI/IND -- and consumes SGR, private modes and OSC without recording
colour.

Two things in here are load-bearing and both were wrong first time.

**A terminal is columns, not characters.**  A CJK glyph occupies two cells and a
combining mark none, so an emulator that counts characters gets every multibyte
case wrong.  Measured against `pyte` on the 102-case corpus: two cases disagreed
until `cellwidth()` went in, and none afterwards.  `unicodedata` is enough and is
in the standard library, which keeps this dependency-free like every other tool
here.

**A redraw ends where the cursor is shown.**  The editor hides the cursor while
it draws and shows it when the screen is settled and it is about to wait for a
key, so `\x1b[?25h` is a step boundary VISIBLE IN THE BYTE STREAM.  Snapshotting
there is what lets a record hold one screen per redraw without a pty and without
timing -- and it is the only way the message line is recordable at all: the keys
that quit the editor wipe it, so a record of the final screen alone showed
`E32: No file name` nowhere (measured: every row of the command sweep read `~`).

Importing does nothing.  Call `render()`, or feed a `Screen`.
"""
import re
import unicodedata


def cellwidth(ch):
    """How many screen cells a character takes: 0, 1 or 2."""
    if unicodedata.combining(ch) or unicodedata.category(ch) in ('Mn', 'Me', 'Cf'):
        return 0
    return 2 if unicodedata.east_asian_width(ch) in ('W', 'F') else 1


class Screen:
    CSI = re.compile(r'\x1b\[([0-9;?>!]*)([@-~])')

    def __init__(self, rows=24, cols=80):
        self.rows, self.cols = rows, cols
        self.buf = [[' '] * cols for _ in range(rows)]
        self.y = self.x = 0
        self.top, self.bot = 0, rows - 1
        self.bells = 0
        self.snaps = []                 # one per redraw; see csi(), '?25h'

    # --- the screen ------------------------------------------------------
    def _blank(self):
        return [' '] * self.cols

    def _clip(self):
        self.y = max(0, min(self.rows - 1, self.y))
        self.x = max(0, min(self.cols - 1, self.x))

    def lf(self):
        if self.y == self.bot:
            del self.buf[self.top]
            self.buf.insert(self.bot, self._blank())
        else:
            self.y = min(self.rows - 1, self.y + 1)

    def ri(self):
        if self.y == self.top:
            del self.buf[self.bot]
            self.buf.insert(self.top, self._blank())
        else:
            self.y = max(0, self.y - 1)

    def put(self, ch):
        w = cellwidth(ch)
        if w == 0:                      # a combining mark joins the cell before it
            x = max(0, self.x - 1)
            self.buf[self.y][x] = self.buf[self.y][x] + ch
            return
        if self.x + w > self.cols:
            self.x = 0
            self.lf()
        self.buf[self.y][self.x] = ch
        for k in range(1, w):           # the second cell of a wide glyph is empty
            self.buf[self.y][self.x + k] = ''
        self.x += w

    def dump(self):
        return '\n'.join(''.join(r).rstrip() for r in self.buf)

    # --- the stream ------------------------------------------------------
    def feed(self, data):
        s = data.decode('utf-8', 'replace')
        i, n = 0, len(s)
        while i < n:
            c = s[i]
            if c == '\x1b':
                m = self.CSI.match(s, i)
                if m:
                    self.csi(m.group(1), m.group(2))
                    i = m.end()
                    continue
                nxt = s[i + 1:i + 2]
                if nxt == 'M':
                    self.ri(); i += 2; continue
                if nxt == 'D':
                    self.lf(); i += 2; continue
                if nxt == ']':                          # OSC ... BEL or ST
                    j, k = s.find('\x07', i), s.find('\x1b\\', i)
                    ends = [x for x in (j, k) if x >= 0]
                    if not ends:
                        return
                    end = min(ends)
                    i = end + (1 if end == j else 2)
                    continue
                if nxt in '()':                         # charset selection
                    i += 3; continue
                i += 2                                  # ESC = , ESC > , ESC 7 ...
                continue
            if c == '\r':
                self.x = 0
            elif c == '\n':
                self.lf()
            elif c == '\b':
                self.x = max(0, self.x - 1)
            elif c == '\t':
                self.x = min(self.cols - 1, (self.x // 8 + 1) * 8)
            elif c == '\x07':
                self.bells += 1
            elif c in '\x0e\x0f':
                pass
            else:
                self.put(c)
            i += 1

    def csi(self, params, final):
        if params[:1] in ('?', '>', '!'):
            # SHOW CURSOR ends a redraw.  Identical consecutive screens are not
            # recorded twice: the editor shows the cursor more often than it
            # changes anything.
            if params == '?25' and final == 'h':
                snap = (self.dump(), self.y, self.x, self.bells)
                if not self.snaps or self.snaps[-1][0] != snap[0]:
                    self.snaps.append(snap)
            return
        ps = [int(x) if x else 0 for x in params.split(';')] if params else []

        def p(i, d=1):
            return ps[i] if i < len(ps) and ps[i] else d

        if final in 'Hf':
            self.y, self.x = p(0) - 1, p(1) - 1
            self._clip()
        elif final == 'A':
            self.y -= p(0); self._clip()
        elif final == 'B':
            self.y += p(0); self._clip()
        elif final == 'C':
            self.x += p(0); self._clip()
        elif final == 'D':
            self.x -= p(0); self._clip()
        elif final == 'G':
            self.x = p(0) - 1; self._clip()
        elif final == 'd':
            self.y = p(0) - 1; self._clip()
        elif final == 'K':
            mode = p(0, 0)
            if mode == 0:
                for x in range(self.x, self.cols):
                    self.buf[self.y][x] = ' '
            elif mode == 1:
                for x in range(0, self.x + 1):
                    self.buf[self.y][x] = ' '
            else:
                self.buf[self.y] = self._blank()
        elif final == 'J':
            mode = p(0, 0)
            if mode == 0:
                for x in range(self.x, self.cols):
                    self.buf[self.y][x] = ' '
                for y in range(self.y + 1, self.rows):
                    self.buf[y] = self._blank()
            elif mode == 1:
                for y in range(0, self.y):
                    self.buf[y] = self._blank()
                for x in range(0, self.x + 1):
                    self.buf[self.y][x] = ' '
            else:
                self.buf = [self._blank() for _ in range(self.rows)]
        elif final == 'L':
            for _ in range(p(0)):
                if self.top <= self.y <= self.bot:
                    del self.buf[self.bot]
                    self.buf.insert(self.y, self._blank())
        elif final == 'M':
            for _ in range(p(0)):
                if self.top <= self.y <= self.bot:
                    del self.buf[self.y]
                    self.buf.insert(self.bot, self._blank())
        elif final == '@':
            for _ in range(p(0)):
                self.buf[self.y].insert(self.x, ' ')
                del self.buf[self.y][self.cols]
        elif final == 'P':
            for _ in range(p(0)):
                del self.buf[self.y][self.x]
                self.buf[self.y].append(' ')
        elif final == 'X':
            for x in range(self.x, min(self.cols, self.x + p(0))):
                self.buf[self.y][x] = ' '
        elif final == 'r':
            self.top = (p(0) - 1) if ps else 0
            self.bot = (p(1, self.rows) - 1) if len(ps) > 1 and ps[1] else self.rows - 1
            self.top = max(0, min(self.rows - 1, self.top))
            self.bot = max(self.top, min(self.rows - 1, self.bot))
            self.y = self.x = 0
        # m, h, l, n, c, t, S, T and the rest: consumed, not recorded


def render(data, rows=24, cols=80):
    s = Screen(rows, cols)
    s.feed(data)
    return s
