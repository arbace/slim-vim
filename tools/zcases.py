"""Zero's behaviour corpus: keystrokes in, the screens the editor drew out.

Usage: python3 tools/zcases.py <binary> <outdir>

`tools/behaviour.py` is the model -- 67 independent editing cases, one recording
each -- but nothing here can load a file or write one, so a case **types its own
text** and is judged by the screen.  Every case:

  * gets its options and `paste` on the command line, as `+{command}`, which runs
    before the first screen is drawn.  `'paste'` and `+cmd` survive every zero
    phase by decision, exactly so that this stays possible (ZERO-GOAL.md);
  * types its seed text under `'paste'`, which forces `noai`, `noet`, `sts=0`,
    `tw=0`, `wm=0`, `noshowmatch` and no mapping in Insert or Command-line mode,
    so the text lands as written.  Measured: `:set nopaste` restores every one of
    them, including from non-default values;
  * does its real editing after `:set nopaste`, under the compiled-in defaults
    (`ai si et sts=4 ts=4 sw=4` and the four mappings) -- which is the editor's
    real behaviour and part of what the case records.  A case that is ABOUT one
    of those defaults simply types after the switch, as `autoindent` does;
  * ends with ESC and `:q!`, which also dismisses a Press-ENTER prompt.

What is recorded is one screen per redraw (`tools/zscreen.py`), the cursor, the
bell count, the exit status, stderr, and the stdout stream's length and sha256 --
the screens for reading, the digest as a tripwire under them (ZERO-PLAN.md 5.1).
"""
import concurrent.futures
import hashlib
import os
import shutil
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zrec
import zstream

ESC = b'\x1b'
CR = b'\r'
CA, CX, CV, CW, CG, CC, CR_R = b'\x01', b'\x18', b'\x16', b'\x17', b'\x07', b'\x03', b'\x12'
BS = b'\x08'
UP, DOWN, LEFT, RIGHT = ESC + b'[A', ESC + b'[B', ESC + b'[D', ESC + b'[C'
HOME, END = ESC + b'[H', ESC + b'[F'
QUIT = ESC + b':q!' + CR


def case(name, opts, seed, *keys):
    """A case: its `+set` options, the text it types under 'paste', then its keys."""
    args = ['+set ' + o for o in opts]
    typing = []
    if seed is not None:
        args.append('+set paste')
        # A tab still needs CTRL-V: 'paste' clears 'expandtab', but the seed is
        # written here with \t and CTRL-V makes it literal under either setting.
        typing = [b'i' + seed.replace(b'\t', CV + b'\t') + ESC, b':set nopaste' + CR]
    return (name, args, typing + list(keys) + [QUIT])


LINES40 = b'i' + CR.join(b'line%d' % i for i in range(1, 41)) + ESC

CASES = [
    # --- the screen itself, which a file-based harness could not see ---------
    case('startup',        [], None),
    case('ruler_move',     [], b'one two three', b'0ww', b'j'),
    case('showmode_ins',   [], b'x', b'A'),
    case('term_report',    [], None, b':set term? t_Co?' + CR),
    # --- CTRL-A / CTRL-X across every 'nrformats' ---------------------------
    case('incr_hex',       ['nrformats=hex'], b'0x0f', b'$' + CA),
    case('incr_bin',       ['nrformats=bin'], b'0b0101', b'$' + CA),
    case('incr_oct',       ['nrformats=octal'], b'017', b'$' + CA),
    case('incr_dec',       ['nrformats='], b'42', b'$' + CA),
    case('incr_alpha',     ['nrformats=alpha'], b'abc', b'0' + CA),
    case('incr_unsigned',  ['nrformats=unsigned'], b'-7', b'$' + CA),
    case('decr_hex',       ['nrformats=hex'], b'0x10', b'$' + CX),
    case('decr_dec',       ['nrformats='], b'42', b'$' + CX),
    case('incr_count',     ['nrformats='], b'5', b'10' + CA),
    case('incr_midword',   ['nrformats='], b'ab12cd34', b'0' + CA, b'$' + CA),
    # --- indenting and formatting -------------------------------------------
    case('autoindent',     ['ai'], b'    a', b'A' + CR + b'b' + ESC),
    case('ai_empty',       ['ai'], b'    a', b'A' + CR + ESC, b'A' + CR + b'x' + ESC),
    case('format_gq',      ['tw=20'],
         b'one two three four five six seven eight nine ten eleven', b'gqq'),
    case('format_comment', ['tw=20 fo=tcq comments=://'],
         b'// aaa bbb ccc ddd eee fff ggg hhh', b'gqq'),
    case('open_comment',   ['fo=tcqr comments=://'], b'// hello', b'A' + CR + b'x' + ESC),
    case('smartindent',    ['si sw=4'], b'if (x) {', b'A' + CR + b'y;' + ESC),
    case('shift_right',    ['sw=4'], b'a' + CR + b'b', b'ggVG>'),
    case('indent_op',      ['sw=2'], b'a' + CR + b'b' + CR + b'c', b'gg3>>'),
    case('retab_gone',     ['ts=8 sw=4 et'], b'\ta', b':retab' + CR),
    # --- insert mode ---------------------------------------------------------
    case('ins_multi',      [], b'x', b'Ahello world' + ESC),
    case('ins_ctrl_v',     [], b'x', b'A' + CV + b'065' + ESC),
    case('ins_bs',         [], b'abc', b'A' + BS + BS + b'Z' + ESC),
    case('ins_ctrl_w',     [], b'x', b'Afoo bar' + CW + b'baz' + ESC),
    case('ins_tab_et',     ['et sw=4 ts=8'], b'x', b'I\tA' + ESC),
    case('replace_mode',   [], b'abcdef', b'0Rxyz' + ESC),
    case('ins_arrows',     [], b'abcdef', b'0i' + RIGHT + RIGHT + b'Z' + ESC),
    # --- multibyte ------------------------------------------------------------
    case('mb_motion',      [], 'café naïve 日本語'.encode(), b'0wdw'),
    case('mb_dollar_x',    [], 'àéîôû'.encode(), b'$x'),
    case('mb_upper',       [], 'àéî ǆ ß'.encode(), b'gUU'),
    case('mb_tilde',       [], 'aàBÉ'.encode(), b'0~~~~'),
    case('mb_incr',        ['nrformats=hex'], '日0x0f本'.encode(), b'0' + CA),
    case('mb_ga',          [], '日本'.encode(), b'0ga'),
    # --- search and substitute ------------------------------------------------
    case('subst_magic',    [], b'foo123 bar456', br':%s/\v(\a+)(\d+)/\2-\1/g' + CR),
    case('subst_amp',      [], b'aaa', br':%s/a/[&]/g' + CR),
    case('subst_case',     [], b'hello world', br':%s/\w\+/\u&/g' + CR),
    case('subst_nl',       [], b'a b', br':%s/ /\r/' + CR),
    case('subst_count',    [], b'x' + CR + b'x' + CR + b'x', b':%s/x/y/' + CR, b':1' + CR),
    case('global_cmd',     [], b'a1' + CR + b'b2' + CR + b'a3', b':g/a/s/$/!/' + CR),
    case('vglobal',        [], b'a1' + CR + b'b2' + CR + b'a3', b':v/a/d' + CR),
    case('search_off',     [], b'aaa' + CR + b'bbb' + CR + b'ccc', b'gg/bbb' + CR, b'dd'),
    case('search_wrap',    [], b'aaa' + CR + b'bbb', b'gg/aaa' + CR, b'n'),
    # --- operators, motions, text objects -------------------------------------
    case('dw_de_db',       [], b'one two three four', b'0dwdee'),
    case('ci_quote',       [], b'say "hello" now', b'0f"ci"bye' + ESC),
    case('da_paren',       [], b'f(a, b) end', b'0f,da('),
    case('yank_put',       [], b'one' + CR + b'two', b'ggyyGp'),
    case('visual_block',   [], b'abcd' + CR + b'efgh' + CR + b'ijkl', b'gg0' + CV + b'jjlx'),
    case('join_lines',     [], b'a' + CR + b'b' + CR + b'c', b'ggJJ'),
    case('join_gJ',        [], b'a' + CR + b'  b', b'gggJ'),
    case('dot_repeat',     [], b'a b c d', b'0dw..'),
    case('macro_q',        ['nrformats='], b'1' + CR + b'1' + CR + b'1',
         b'ggqaA!' + ESC + b'jq', b'2@a'),
    case('percent_match',  [], b'f(a, b) end', b'0f(%'),
    # --- undo / redo -----------------------------------------------------------
    case('undo_redo',      [], b'a' + CR + b'b' + CR + b'c', b'ggdddd', b'u', CR_R, b'u'),
    case('undo_block',     [], b'abc', b'0xxx', b'uu'),
    case('undo_after_ins', [], b'x', b'Aabc' + ESC, b'u'),
    case('undo_U',         [], b'abc', b'0x', b'U'),
    # --- registers, marks, misc -------------------------------------------------
    case('registers',      [], b'a' + CR + b'b', b'gg"ryy', b'G"rp'),
    case('reg_list',       [], b'a', b'yy', b':registers' + CR),
    case('marks',          [], b'a' + CR + b'b' + CR + b'c', b'ggmaG', b"d'a"),
    case('mark_list',      [], b'a' + CR + b'b', b'ggma', b':marks' + CR),
    case('move_copy',      [], b'1' + CR + b'2' + CR + b'3', b':2m0' + CR, b':1t$' + CR),
    case('normal_range',   [], b'a' + CR + b'b' + CR + b'c', b':%normal A!' + CR),
    case('sort_gone',      [], b'b' + CR + b'a', b':sort u' + CR),
    case('filter_gone',    [], b'c' + CR + b'a', b':%!sort' + CR),
    case('read_cmd_gone',  [], b'x', b':r !echo piped' + CR),
    case('put_expr_gone',  [], b'x', b":put ='added'" + CR),
    case('ff_gone',        [], b'a', b':set ff=dos' + CR),
    case('bomb_gone',      [], b'a', b':set bomb' + CR),
    # --- +extra_search, which is why this build is not plain tiny --------------
    case('hlsearch_opt',   ['hlsearch'], b'alpha' + CR + b'beta' + CR + b'gamma',
         b'gg/beta' + CR),
    case('incsearch_opt',  ['incsearch'], b'alpha' + CR + b'beta' + CR + b'gamma',
         b'gg/gam'),
    case('match_cmd',      [], b'alpha' + CR + b'beta', b':match Search /beta/' + CR),
    case('nohlsearch',     ['hls'], b'alpha' + CR + b'beta', b'gg/beta' + CR,
         b':nohlsearch' + CR),
    case('search_count',   [], b'aa' + CR + b'aa' + CR + b'aa', b'gg/aa' + CR, b'n'),
    # --- what only a terminal can exercise -------------------------------------
    case('nav_arrows',     [], b'l1' + CR + b'l2' + CR + b'l3', b'gg', DOWN + DOWN + RIGHT, b'x'),
    case('nav_home_end',   [], b'abcdef', b'0', END, b'x', HOME, b'x'),
    case('scroll_ctrl_f',  [], None, LINES40, b'gg', b'\x06'),
    case('scroll_zz',      [], None, LINES40, b'20G', b'zz'),
    case('ctrl_g',         [], b'a' + CR + b'b', CG),
    case('ctrl_g_count',   [], b'a' + CR + b'b', b'g' + CG),
    case('visual_show',    [], b'abcdef', b'0vlll'),
    case('set_listing',    [], None, b':set nu list' + CR),
    case('hit_enter',      [], None, b':history' + CR),
    case('unknown_cmd',    [], None, b':nosuchcmd' + CR),
    case('quit_modified',  [], b'x', b':q' + CR),
    case('zz_key',         [], b'x', b'ZZ'),
    # --- the four compiled-in mappings, which the file corpus never tested ------
    case('map_tab_percent', [], b'f(a, b) end', b'0f(', b'\t'),
    case('map_e_acute_undo', [], b'abc', b'0x', 'é'.encode()),
    case('map_in_paste',   [], b'x' + '§'.encode() + b'y'),
    case('map_list',       [], None, b':map' + CR),
    # --- CTRL-C on a stream: it does not cancel, it exits ------------------------
    case('ctrl_c_clean',   [], None, CC),
    case('ctrl_c_changed', [], b'x', CC),
    # --- one case per thing a later phase removes, or its delta is invisible -----
    case('key_Q',          [], b'alpha' + CR + b'beta', b'Q'),
    case('key_gQ',         [], b'alpha' + CR + b'beta', b'gQ'),
    case('cmd_write',      [], b'x', b':write' + CR),
    case('cmd_read',       [], b'x', b':read' + CR),
    case('cmd_edit',       [], b'x', b':edit' + CR),
    case('cmd_file',       [], b'x', b':file' + CR),
    case('key_gf',         [], b'nosuchfile', b'0gf'),
    case('reg_percent',    [], b'x', b'A ' + CR_R + b'%' + ESC),
]


def record(binary, name, args, keys):
    try:
        scr, out, err, rc = zstream.session(binary, keys, args=args)
    except zstream.Blocked:
        return zrec.section('blocked') + zrec.section(
            'why', 'the editor took the input over and did not return')
    text = zrec.section('exit %s' % rc)
    text += zrec.section('bells %d' % scr.bells)
    text += zrec.section('stream %d sha=%s' % (len(out), hashlib.sha256(out).hexdigest()[:16]))
    text += zrec.section('stderr', err.decode('utf-8', 'replace').rstrip('\n'))
    for i, (dump, y, x, bells) in enumerate(scr.snaps):
        text += zrec.section('snap %d cursor=%d,%d bells=%d' % (i, y, x, bells), dump)
    return zrec.scrub(text)


def main():
    binary, outdir = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    shutil.rmtree(outdir, ignore_errors=True)
    os.makedirs(outdir)
    t = time.time()

    def one(c):
        name, args, keys = c
        open(os.path.join(outdir, name), 'w').write(record(binary, name, args, keys))

    with concurrent.futures.ThreadPoolExecutor(
            max_workers=min(len(CASES), (os.cpu_count() or 4) * 2)) as ex:
        list(ex.map(one, CASES))
    print('%d cases -> %s in %.1fs' % (len(CASES), outdir, time.time() - t))


if __name__ == '__main__':
    main()
