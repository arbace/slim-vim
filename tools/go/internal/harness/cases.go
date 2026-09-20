package harness

// behaviourCases is tools/behaviour.py's CASES, transcribed by a program and
// not by hand: 67 small independent edits, each recorded.
//
// The 16-case harness that preceded it could not see the damage a bad
// constant-fold did, because it never incremented a hex number or stripped
// autoindent.  This one drives the normal-mode and Ex surface broadly.
//
// It is NOT the sweep that finds everything: the one segfault that reached a
// build here -- a version string overflowing a 20-byte buffer, so :intro
// crashed -- was invisible to all 67 of these and to every pty scenario, and
// the mechanical dispatch over every Ex command name found it.  Breadth of
// shape and breadth of entry point are different things.
var behaviourCases = []struct {
	name string
	text string
	cmds []string
}{
	{"incr_hex", "0x0f\n0X0F\n0xff\n", []string{"set nrformats=hex", "%norm! $\x01"}},
	{"incr_bin", "0b0101\n0B11\n", []string{"set nrformats=bin", "%norm! $\x01"}},
	{"incr_oct", "017\n0777\n", []string{"set nrformats=octal", "%norm! $\x01"}},
	{"incr_dec", "42\n-7\n0\n999\n", []string{"set nrformats=", "%norm! $\x01"}},
	{"incr_alpha", "abc\nzed\n", []string{"set nrformats=alpha", "%norm! 0\x01"}},
	{"incr_unsigned", "-7\n42\n", []string{"set nrformats=unsigned", "%norm! $\x01"}},
	{"decr_hex", "0x10\n0x00\n", []string{"set nrformats=hex", "%norm! $\x18"}},
	{"decr_dec", "42\n-7\n", []string{"set nrformats=", "%norm! $\x18"}},
	{"incr_count", "5\n", []string{"set nrformats=", "norm! 10\x01"}},
	{"incr_midword", "ab12cd34\n", []string{"set nrformats=", "norm! 0\x01", "norm! $\x01"}},
	{"autoindent", "    a\n", []string{"set ai", "norm! GA\rb\x1b"}},
	{"ai_empty", "    a\n", []string{"set ai", "norm! GA\r\x1b", "norm! A\rx\x1b"}},
	{"format_gq", "one two three four five six seven eight nine ten eleven\n", []string{"set tw=20", "norm! gqq"}},
	{"format_comment", "// aaa bbb ccc ddd eee fff ggg hhh iii jjj kkk lll\n", []string{"set tw=20 fo=tcq comments=://", "norm! gqq"}},
	{"open_comment", "// hello\n", []string{"set fo=tcqr comments=://", "norm! GA\rx\x1b"}},
	{"smartindent", "if (x) {\n", []string{"set si sw=4", "norm! GA\ry;\x1b"}},
	{"shift_right", "a\nb\n", []string{"set sw=4", "norm! ggVG>"}},
	{"retab", "	a\n", []string{"set ts=8 sw=4 et", "retab"}},
	{"ins_multi", "x\n", []string{"norm! Ahello world\x1b"}},
	{"ins_ctrl_v", "x\n", []string{"norm! A\x16065\x1b"}},
	{"ins_bs", "abc\n", []string{"norm! AZ\x1b"}},
	{"ins_ctrl_w", "x\n", []string{"norm! Afoo barbaz\x1b"}},
	{"ins_tab_et", "x\n", []string{"set et sw=4 ts=8", "norm! I	A\x1b"}},
	{"replace_mode", "abcdef\n", []string{"norm! 0Rxyz\x1b"}},
	{"mb_motion", "café naïve 日本語\n", []string{"norm! 0wdw"}},
	{"mb_dollar_x", "àéîôû\n", []string{"norm! $x"}},
	{"mb_upper", "àéî ǆ ß\n", []string{"norm! gUU"}},
	{"mb_ga_len", "日本\n", []string{"norm! 0x"}},
	{"mb_tilde", "aàBÉ\n", []string{"norm! 0~~~~"}},
	{"mb_incr", "日0x0f本\n", []string{"set nrformats=hex", "norm! 0\x01"}},
	{"subst_magic", "foo123 bar456\n", []string{"%s/\\v(\\a+)(\\d+)/\\2-\\1/g"}},
	{"subst_amp", "aaa\n", []string{"%s/a/[&]/g"}},
	{"subst_case", "hello world\n", []string{"%s/\\w\\+/\\u&/g"}},
	{"subst_nl", "a b\n", []string{"%s/ /\\r/"}},
	{"subst_count", "x\nx\nx\n", []string{"%s/x/y/", "1"}},
	{"global_cmd", "a1\nb2\na3\n", []string{"g/a/s/$/!/"}},
	{"vglobal", "a1\nb2\na3\n", []string{"v/a/d"}},
	{"search_off", "aaa\nbbb\nccc\n", []string{"norm! /bbb\rdd"}},
	{"dw_de_db", "one two three four\n", []string{"norm! 0dwdee"}},
	{"ci_quote", "say \"hello\" now\n", []string{"norm! 0f\"ci\"bye\x1b"}},
	{"da_paren", "f(a, b) end\n", []string{"norm! 0f,da("}},
	{"yank_put", "one\ntwo\n", []string{"norm! ggyyGp"}},
	{"visual_block", "abcd\nefgh\nijkl\n", []string{"norm! gg0\x16jjlx"}},
	{"join_lines", "a\nb\nc\n", []string{"norm! ggJJ"}},
	{"join_gJ", "a\n  b\n", []string{"norm! gggJ"}},
	{"indent_op", "a\nb\nc\n", []string{"set sw=2", "norm! gg3>>"}},
	{"dot_repeat", "a b c d\n", []string{"norm! 0dw..'"}},
	{"macro_q", "1\n1\n1\n", []string{"set nrformats=", "norm! qaA!\x1bjq", "norm! 2@a"}},
	{"undo_redo", "a\nb\nc\n", []string{"norm! ggdddd", "undo", "redo", "undo"}},
	{"undo_block", "abc\n", []string{"norm! 0xxx", "norm! uu"}},
	{"undo_after_ins", "x\n", []string{"norm! Aabc\x1b", "undo"}},
	{"registers", "a\nb\n", []string{"1y r", "$pu r"}},
	{"marks", "a\nb\nc\n", []string{"norm! ggmaGd'a"}},
	{"sort_u", "b\na\nb\nc\n", []string{"sort u"}},
	{"sort_n", "10\n9\n100\n", []string{"sort n"}},
	{"move_copy", "1\n2\n3\n", []string{"2m0", "1t$"}},
	{"normal_range", "a\nb\nc\n", []string{"%normal A!"}},
	{"put_expr", "x\n", []string{"put ='added'"}},
	{"read_cmd", "x\n", []string{"r !echo piped"}},
	{"filter", "c\na\nb\n", []string{"%!sort"}},
	{"hlsearch_opt", "alpha\nbeta\ngamma\n", []string{"set hlsearch", "%s/beta/BETA/"}},
	{"incsearch_opt", "alpha\nbeta\ngamma\n", []string{"set incsearch", "%s/gamma/G/"}},
	{"match_cmd", "alpha\nbeta\ngamma\n", []string{"match Search /beta/", "%s/alpha/A/"}},
	{"nohlsearch", "alpha\nbeta\n", []string{"set hls", "/beta", "nohlsearch", "%s/alpha/A/"}},
	{"ff_dos", "a\nb\n", []string{"set ff=dos"}},
	{"bomb_on", "a\n", []string{"set bomb"}},
	{"binary_mode", "a\nb\n", []string{"set binary"}},
}
