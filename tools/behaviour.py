"""A wide behaviour harness: many small independent edits, each recorded.

The 16-case harness could not see the damage a bad constant-fold did, because it
never incremented a hex number or stripped autoindent.  This one drives the
normal-mode and Ex surface broadly.  Every case writes a file; a case that
writes nothing records that fact, so a crash cannot pass as a match.
"""
import os, subprocess, sys, tempfile, shutil

_ARG, OUT = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])

# vim reads its own argv[0]: a basename beginning with 'r' turns on restricted
# mode and every shell-out fails, 'e' selects evim, 'g' the GUI, and "view" and
# "ex" prefixes change the mode too.  A binary saved under a name like "ref" is
# therefore a *different editor*, and comparing it against one called "vim"
# reports differences that are not in the code.  Run everything under the one
# name that means what it says.
_STAGE = tempfile.mkdtemp(prefix="behaviour-bin-")
BIN = os.path.join(_STAGE, "vim")
shutil.copy2(_ARG, BIN)
os.chmod(BIN, 0o755)
CA, CX, CV, ESC, CR = '\001', '\030', '\026', '\033', '\r'

# (name, input text, [ex commands])
CASES = [
 # --- CTRL-A / CTRL-X across every 'nrformats' -----------------------------
 ("incr_hex",     "0x0f\n0X0F\n0xff\n", ["set nrformats=hex", "%norm! $"+CA]),
 ("incr_bin",     "0b0101\n0B11\n",     ["set nrformats=bin", "%norm! $"+CA]),
 ("incr_oct",     "017\n0777\n",        ["set nrformats=octal", "%norm! $"+CA]),
 ("incr_dec",     "42\n-7\n0\n999\n",   ["set nrformats=", "%norm! $"+CA]),
 ("incr_alpha",   "abc\nzed\n",         ["set nrformats=alpha", "%norm! 0"+CA]),
 ("incr_unsigned","-7\n42\n",           ["set nrformats=unsigned", "%norm! $"+CA]),
 ("decr_hex",     "0x10\n0x00\n",       ["set nrformats=hex", "%norm! $"+CX]),
 ("decr_dec",     "42\n-7\n",           ["set nrformats=", "%norm! $"+CX]),
 ("incr_count",   "5\n",                ["set nrformats=", "norm! 10"+CA]),
 ("incr_midword", "ab12cd34\n",         ["set nrformats=", "norm! 0"+CA, "norm! $"+CA]),
 # --- autoindent, formatting, comments -------------------------------------
 ("autoindent",   "    a\n",            ["set ai", "norm! GA"+CR+"b"+ESC]),
 ("ai_empty",     "    a\n",            ["set ai", "norm! GA"+CR+ESC, "norm! A"+CR+"x"+ESC]),
 ("format_gq",    "one two three four five six seven eight nine ten eleven\n",
                                        ["set tw=20", "norm! gqq"]),
 ("format_comment","// aaa bbb ccc ddd eee fff ggg hhh iii jjj kkk lll\n",
                                        ["set tw=20 fo=tcq comments=://", "norm! gqq"]),
 ("open_comment", "// hello\n",         ["set fo=tcqr comments=://", "norm! GA"+CR+"x"+ESC]),
 ("smartindent",  "if (x) {\n",         ["set si sw=4", "norm! GA"+CR+"y;"+ESC]),
 ("shift_right",  "a\nb\n",             ["set sw=4", "norm! ggVG>"]),
 ("retab",        "\ta\n",              ["set ts=8 sw=4 et", "retab"]),
 # --- insert mode ----------------------------------------------------------
 ("ins_multi",    "x\n",                ["norm! Ahello world"+ESC]),
 ("ins_ctrl_v",   "x\n",                ["norm! A"+CV+"065"+ESC]),
 ("ins_bs",       "abc\n",              ["norm! A"+chr(8)+chr(8)+"Z"+ESC]),
 ("ins_ctrl_w",   "x\n",                ["norm! Afoo bar"+chr(23)+"baz"+ESC]),
 ("ins_tab_et",   "x\n",                ["set et sw=4 ts=8", "norm! I\tA"+ESC]),
 ("replace_mode", "abcdef\n",           ["norm! 0Rxyz"+ESC]),
 # --- multibyte ------------------------------------------------------------
 ("mb_motion",    "café naïve 日本語\n", ["norm! 0wdw"]),
 ("mb_dollar_x",  "àéîôû\n",            ["norm! $x"]),
 ("mb_upper",     "àéî ǆ ß\n",          ["norm! gUU"]),
 ("mb_ga_len",    "日本\n",             ["norm! 0x"]),
 ("mb_tilde",     "aàBÉ\n",             ["norm! 0~~~~"]),
 ("mb_incr",      "日0x0f本\n",          ["set nrformats=hex", "norm! 0"+CA]),
 # --- search and substitute -------------------------------------------------
 ("subst_magic",  "foo123 bar456\n",    [r"%s/\v(\a+)(\d+)/\2-\1/g"]),
 ("subst_amp",    "aaa\n",              [r"%s/a/[&]/g"]),
 ("subst_case",   "hello world\n",      [r"%s/\w\+/\u&/g"]),
 ("subst_nl",     "a b\n",              [r"%s/ /\r/"]),
 ("subst_count",  "x\nx\nx\n",          ["%s/x/y/", "1"]),
 ("global_cmd",   "a1\nb2\na3\n",       ["g/a/s/$/!/"]),
 ("vglobal",      "a1\nb2\na3\n",       ["v/a/d"]),
 ("search_off",   "aaa\nbbb\nccc\n",    ["norm! /bbb"+CR+"dd"]),
 # --- operators, motions, text objects --------------------------------------
 ("dw_de_db",     "one two three four\n",["norm! 0dwdee"]),
 ("ci_quote",     'say "hello" now\n',  ['norm! 0f"ci"bye'+ESC]),
 ("da_paren",     "f(a, b) end\n",      ["norm! 0f,da("]),
 ("yank_put",     "one\ntwo\n",         ["norm! ggyyGp"]),
 ("visual_block", "abcd\nefgh\nijkl\n", ["norm! gg0"+CV+"jjlx"]),
 ("join_lines",   "a\nb\nc\n",          ["norm! ggJJ"]),
 ("join_gJ",      "a\n  b\n",           ["norm! gggJ"]),
 ("indent_op",    "a\nb\nc\n",          ["set sw=2", "norm! gg3>>"]),
 ("dot_repeat",   "a b c d\n",          ["norm! 0dw..'"]),
 ("macro_q",      "1\n1\n1\n",          ["set nrformats=", "norm! qaA!"+ESC+"jq", "norm! 2@a"]),
 # --- undo / redo ------------------------------------------------------------
 ("undo_redo",    "a\nb\nc\n",          ["norm! ggdddd", "undo", "redo", "undo"]),
 ("undo_block",   "abc\n",              ["norm! 0xxx", "norm! uu"]),
 ("undo_after_ins","x\n",               ["norm! Aabc"+ESC, "undo"]),
 # --- registers, marks, misc -------------------------------------------------
 ("registers",    "a\nb\n",             ["1y r", "$pu r"]),
 ("marks",        "a\nb\nc\n",          ["norm! ggmaGd'a"]),
 ("sort_u",       "b\na\nb\nc\n",       ["sort u"]),
 ("sort_n",       "10\n9\n100\n",       ["sort n"]),
 ("move_copy",    "1\n2\n3\n",          ["2m0", "1t$"]),
 ("normal_range", "a\nb\nc\n",          ["%normal A!"]),
 ("put_expr",     "x\n",                ["put ='added'"]),
 ("read_cmd",     "x\n",                ["r !echo piped"]),
 ("filter",       "c\na\nb\n",          ["%!sort"]),
 # --- +extra_search ----------------------------------------------------------
 # Deliberately enabled in an otherwise tiny build, so it needs cases of its
 # own; without the feature these three commands fail and the exit code shows
 # it.
 ("hlsearch_opt", "alpha\nbeta\ngamma\n", ["set hlsearch", "%s/beta/BETA/"]),
 ("incsearch_opt","alpha\nbeta\ngamma\n", ["set incsearch", "%s/gamma/G/"]),
 ("match_cmd",    "alpha\nbeta\ngamma\n", ["match Search /beta/", "%s/alpha/A/"]),
 ("nohlsearch",   "alpha\nbeta\n",         ["set hls", "/beta", "nohlsearch", "%s/alpha/A/"]),
 # --- file format / bomb -----------------------------------------------------
 ("ff_dos",       "a\nb\n",             ["set ff=dos"]),
 ("bomb_on",      "a\n",                ["set bomb"]),
 ("binary_mode",  "a\nb\n",             ["set binary"]),
]

shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT)
for name, text, cmds in CASES:
    d = tempfile.mkdtemp()
    src = os.path.join(d, "in.txt"); dst = os.path.join(d, "out.txt")
    open(src, "w").write(text)
    argv = [BIN, "-u", "NONE", "-i", "NONE", "-e", "-s"]
    for c in cmds: argv += ["-c", c]
    argv += ["-c", "w! " + dst, "-c", "q!", src]
    r = subprocess.run(argv, stdin=subprocess.DEVNULL,
                       capture_output=True, cwd=d, timeout=30)
    body = open(dst, "rb").read() if os.path.exists(dst) else b"<NO FILE WRITTEN>"
    with open(os.path.join(OUT, name), "wb") as f:
        f.write(b"exit=%d\n" % r.returncode)
        f.write(b"stdout=" + r.stdout + b"\n")
        f.write(b"stderr=" + r.stderr + b"\n")
        f.write(b"file=" + body)
    shutil.rmtree(d)
shutil.rmtree(_STAGE, ignore_errors=True)
print(len(CASES), "cases ->", OUT)
