package edit

// Every act pipes/zero20-edit.sh performs and every line it says, in SOURCE
// ORDER, EXTRACTED by an AST walk rather than retyped.  The phase is 873 lines
// and the great majority of it is blocks of C; the rule is about retyping and
// not about newlines, so the one-line arguments are lifted too.
//
// The walk descends only into MODULE-LEVEL statements: `cut()` is defined as
// `sub(old, ”, n, tag)`, and a walk of the whole tree picks that up as an act
// with a computed argument.  Measured -- it did.
//
// TWO OPS CARRY nil ARGUMENTS because the Python computes them: the splice of
// z20Host into the launcher region, and the last say(), which reports the line
// count.  The Go writes those two and takes the other seventy-nine and six as
// they are.
const z20Host = "static volatile sig_atomic_t host_winch_pending = FALSE;\nstatic volatile sig_atomic_t host_tstp_pending = FALSE;\nstatic volatile sig_atomic_t host_int_pending = FALSE;\nstatic struct termios host_tty_saved;\nstatic int host_tty_valid = FALSE;\nstatic int host_tty_raw = FALSE;\n\n    static void\nhost_catch(int sig, void (*f)(int))\n{\n    struct sigaction sa;\n\n    sa.sa_handler = f;\n    sigemptyset(&sa.sa_mask);\n    sa.sa_flags = 0;\n    sigaction(sig, &sa, NULL);\n}\n\n    static void\nhost_on_winch(int sigarg  __attribute__((unused)) )\n{\n    host_winch_pending = TRUE;\n}\n\n    static void\nhost_on_tstp(int sigarg  __attribute__((unused)) )\n{\n    host_tstp_pending = TRUE;\n}\n\n    static void\nhost_on_int(int sigarg  __attribute__((unused)) )\n{\n    host_int_pending = TRUE;\n}\n\n    static void\nhost_tty_set(int raw, int sleep)\n{\n    struct termios tnew;\n    int n = 10;\n\n    if (!host_tty_valid)\n    {\n        if (tcgetattr(0, &host_tty_saved) == -1)\n        {\n            return;\n        }\n        host_tty_valid = TRUE;\n    }\n    tnew = host_tty_saved;\n    if (raw)\n    {\n        tnew.c_iflag &= ~(ICRNL | IXON);\n        tnew.c_lflag &= ~(ICANON | ECHO | ISIG | ECHOE | IEXTEN);\n        tnew.c_oflag &= ~(ONLCR | XTABS);\n        tnew.c_cc[VMIN] = 1;\n        tnew.c_cc[VTIME] = 0;\n    }\n    else if (sleep)\n    {\n        tnew.c_lflag &= ~(ICANON | ECHO);\n        tnew.c_cc[VMIN] = 1;\n        tnew.c_cc[VTIME] = 0;\n    }\n    while (tcsetattr(0, TCSANOW, &tnew) == -1 && errno == EINTR && n > 0)\n    {\n        --n;\n    }\n}\n\n    static void\nmusl_host_init(void)\n{\n    host_catch(SIGHUP, deathtrap);\n    host_catch(SIGTERM, deathtrap);\n    host_catch(SIGWINCH, host_on_winch);\n    host_catch(SIGCONT, host_on_winch);\n    host_catch(SIGTSTP, host_on_tstp);\n    host_catch(SIGINT, host_on_int);\n    host_catch(SIGPIPE, SIG_IGN);\n    host_catch(SIGALRM, SIG_IGN);\n}\n\n    static int\nmusl_get_winsize(int *rows, int *cols)\n{\n    struct winsize ws;\n\n    if (ioctl(1, TIOCGWINSZ, &ws) != 0)\n    {\n        return FAIL;\n    }\n    if (ws.ws_row <= 0 || ws.ws_col <= 0)\n    {\n        return FAIL;\n    }\n    *rows = ws.ws_row;\n    *cols = ws.ws_col;\n    return OK;\n}\n\n    static void\nmusl_term_start(void)\n{\n    host_tty_raw = TRUE;\n    host_tty_set(TRUE, FALSE);\n}\n\n    static void\nmusl_term_stop(void)\n{\n    host_tty_raw = FALSE;\n    host_tty_set(FALSE, FALSE);\n}\n\n    static int\nmusl_tty_keys(int fd, int *bs, int *intr, int *cr, int *nlcr)\n{\n    struct termios keys;\n\n    if (tcgetattr(fd, &keys) == -1)\n    {\n        return FAIL;\n    }\n    *bs = (int)keys.c_cc[VERASE];\n    *intr = (int)keys.c_cc[VINTR];\n    *cr = (keys.c_iflag & ICRNL) != 0;\n    *nlcr = (keys.c_oflag & ONLCR) != 0;\n    return OK;\n}\n\n    static void\nmusl_delay(long ms, int interruptible)\n{\n    struct timespec ts;\n    int relax = interruptible && host_tty_raw && ms > 500;\n\n    if (relax)\n    {\n        host_tty_set(FALSE, TRUE);\n    }\n    ts.tv_sec = ms / 1000;\n    ts.tv_nsec = (ms % 1000) * 1000000;\n    (void)nanosleep(&ts, NULL);\n    if (relax)\n    {\n        host_tty_set(TRUE, FALSE);\n    }\n}\n\n    static int\nmusl_wait_for_input(long ms)\n{\n    struct timeval tv;\n    struct timeval *tvp;\n    fd_set rfds;\n    int ret;\n\n    if (ms >= 0)\n    {\n        tv.tv_sec = ms / 1000;\n        tv.tv_usec = (ms % 1000) * 1000;\n        tvp = &tv;\n    }\n    else\n    {\n        tvp = NULL;\n    }\n    for (;;)\n    {\n        if (host_winch_pending || host_tstp_pending || host_int_pending)\n        {\n            return 1;\n        }\n        FD_ZERO(&rfds);\n        FD_SET(0, &rfds);\n        ret = select(1, &rfds, NULL, NULL, tvp);\n        if (ret == -1 && errno == EINTR)\n        {\n            continue;\n        }\n        return ret > 0 && FD_ISSET(0, &rfds);\n    }\n}\n\n    static int\nmusl_read_input(char *buf, int len)\n{\n    if (host_int_pending)\n    {\n        host_int_pending = FALSE;\n        if (len >= 1)\n        {\n            buf[0] = 3;\n            return 1;\n        }\n    }\n    if (host_winch_pending)\n    {\n        int rows = 0;\n        int cols = 0;\n\n        host_winch_pending = FALSE;\n        if (musl_get_winsize(&rows, &cols) == OK && len >= 32)\n        {\n            return vim_snprintf(buf, (size_t)len, \"\\033[48;%d;%d;0;0t\", rows, cols);\n        }\n    }\n    if (host_tstp_pending)\n    {\n        host_tstp_pending = FALSE;\n        if (len >= 5)\n        {\n            musl_memcpy(buf, \"\\033[?1z\", 5);\n            return 5;\n        }\n    }\n    return (int)read(0, buf, (size_t)len);\n}\n\n    static void\nmusl_suspend(void)\n{\n    host_catch(SIGTSTP, SIG_DFL);\n    kill(0, SIGTSTP);\n    host_catch(SIGTSTP, host_on_tstp);\n}\n\n"

// z20Op is one act or one report line, with the heredoc line it came from --
// which is what keeps the table in the order the phase performs them.
type z20Op struct {
	kind string
	args []string
	line int
}

var z20Ops = []z20Op{
	{"say", []string{"the input is r19: `mch_signal` 18, `settmode` 13, `isatty` 4, and NO `\\033[?2048$p` anywhere -- which is what makes the whole mode-2048 negotiation unreachable and this phase half a deletion of code that could never run"}, 72},
	{"sub", []string{"    else if (win_resize_enabled && argc >= 3 && arg[0] == 48)\n", "    else if (argc >= 3 && arg[0] == 48)\n", "1", "R1"}, 77},
	{"sub", []string{"        if (height != Rows || width != Columns)\n        {\n            set_shellsize(width, height, true);\n        }\n", "        set_shellsize(width, height, true);\n", "1", "R2"}, 82},
	{"cut", []string{"                case 2048:\n                    win_resize_setting = setting;\n\n                    term_set_win_resize(true);\n                    break;\n", "1", "R3"}, 88},
	{"sub", []string{"    else if (first == '?' && trail == 'y' && argc == 2 && (arg[0] == 2026 || arg[0] == 2048))\n", "    else if (first == '?' && trail == 'y' && argc == 2 && arg[0] == 2026)\n", "1", "R4"}, 94},
	{"delfunc", []string{"did_set_termresize(optset_T *args  __attribute__((unused)) )", "R5"}, 100},
	{"cut", []string{"static char *did_set_termresize(optset_T *args);\n", "1", "R5b"}, 101},
	{"cut", []string{"    {\"termresize\", \"trz\", P_STRING|P_VI_DEF,\n                            (char_u *)&p_trz, PV_NONE, did_set_termresize, NULL,\n                            {(char_u *)\"\", (char_u *)0}\n                              },\n", "1", "R5c"}, 102},
	{"cut", []string{"static char_u   *p_trz;\n", "1", "R5d"}, 107},
	{"cut", []string{"    term_set_win_resize(false);\n", "1", "R6"}, 108},
	{"delfunc", []string{"term_set_win_resize(bool state)\n{", "R7"}, 109},
	{"cut", []string{"static void term_set_win_resize(bool state);\n", "1", "R7b"}, 110},
	{"cut", []string{"static int win_resize_setting = 0;\n", "1", "R7c"}, 111},
	{"cut", []string{"static bool win_resize_enabled = false;\n", "1", "R7d"}, 112},
	{"say", []string{"the 'termresize' option, term_set_win_resize(), win_resize_setting and win_resize_enabled are gone, and the CSI 48 arm is unconditional and always a full redraw"}, 113},
	{"delfunc", []string{"sig_winch  (int sigarg  __attribute__((unused)) ) ", "W1"}, 118},
	{"cut", []string{"static void sig_winch  (int) ;\n", "1", "W1b"}, 119},
	{"delfunc", []string{"set_sigwinch_handler(void)\n{", "W2"}, 120},
	{"delfunc", []string{"resize_func(int check_only)", "W3"}, 121},
	{"sub", []string{"    return inchar_loop(buf, maxlen, wtime, tb_change_cnt, WaitForChar, resize_func);\n", "    return inchar_loop(buf, maxlen, wtime, tb_change_cnt, WaitForChar, NULL);\n", "1", "W4"}, 124},
	{"delfunc", []string{"handle_resize(void)\n{", "W5"}, 127},
	{"cut", []string{"static void handle_resize(void);\n", "1", "W5b"}, 128},
	{"cut", []string{"static volatile sig_atomic_t do_resize = FALSE;\n", "1", "W6"}, 129},
	{"cut", []string{"            if (do_resize)\n            {\n                handle_resize();\n            }\n\n", "1", "W7"}, 130},
	{"cut", []string{"    {SIGWINCH,      \"WINCH\",    FALSE},\n", "1", "W8"}, 136},
	{"cut", []string{"    mch_signal(SIGWINCH, sig_winch);\n\n", "1", "W9"}, 137},
	{"delfunc", []string{"mch_get_shellsize(void)\n{", "I1"}, 140},
	{"sub", []string{"    int     retval;\n\n        retval = mch_get_shellsize();\n", "    int     retval;\n    int     hrows = 0;\n    int     hcols = 0;\n\n        retval = FAIL;\n        if (musl_get_winsize(&hrows, &hcols) == OK)\n        {\n            Rows = hrows;\n            Columns = hcols;\n            limit_screen_size();\n            retval = OK;\n        }\n", "1", "I2"}, 144},
	{"delfunc", []string{"catch_sigint  (int sigarg  __attribute__((unused)) ) \n{", "S1"}, 162},
	{"cut", []string{"static void catch_sigint  (int) ;\n", "1", "S1b"}, 163},
	{"delfunc", []string{"sig_tstp  (int sigarg  __attribute__((unused)) ) \n{", "S2"}, 164},
	{"cut", []string{"static void sig_tstp  (int) ;\n", "1", "S2b"}, 165},
	{"delfunc", []string{"sigcont_handler  (int sigarg  __attribute__((unused)) ) \n{", "S3"}, 166},
	{"cut", []string{"static void sigcont_handler  (int) ;\n", "2", "S3b"}, 169},
	{"cut", []string{"static volatile sig_atomic_t sigcont_received;\n", "1", "S3c"}, 170},
	{"sub", []string{"static struct signalinfo\n{\n    int     sig;\n    char    *name;\n    char    deadly;\n} signal_info[] =\n{\n    {SIGHUP,        \"HUP\",      TRUE},\n    {SIGTERM,       \"TERM\",     TRUE},\n    {SIGINT,        \"INT\",      FALSE},\n    {SIGTSTP,       \"TSTP\",     FALSE},\n    {-1,            \"Unknown!\", FALSE}\n};\n", "static struct signalinfo\n{\n    int     sig;\n    char    *name;\n} signal_info[] =\n{\n    {SIGHUP,        \"HUP\"},\n    {SIGTERM,       \"TERM\"},\n    {-1,            \"Unknown!\"}\n};\n", "1", "S4"}, 177},
	{"delfunc", []string{"mch_signal(int sig, sighandler_T func)\n{", "S5"}, 201},
	{"cut", []string{"static sighandler_T mch_signal(int sig, sighandler_T func);\n", "1", "S5b"}, 202},
	{"delfunc", []string{"catch_signals(void (*func_deadly)(int), void (*func_other)(int))\n{", "S6"}, 203},
	{"cut", []string{"static void catch_signals(void (*func_deadly)(int), void (*func_other)(int));\n", "1", "S6b"}, 204},
	{"delfunc", []string{"\nset_signals(void)\n{", "S7"}, 206},
	{"cut", []string{"static void set_signals(void);\n", "1", "S7b"}, 207},
	{"delfunc", []string{"reset_signals(void)\n{", "S8"}, 208},
	{"cut", []string{"static void reset_signals(void);\n", "1", "S8b"}, 209},
	{"cut", []string{"    reset_signals();\n", "1", "S8c"}, 210},
	{"delfunc", []string{"catch_int_signal(void)\n{", "S9"}, 211},
	{"cut", []string{"static void catch_int_signal(void);\n", "1", "S9b"}, 212},
	{"sub", []string{"    ignore_sigtstp = SIG_IGN == mch_signal(SIGTSTP, SIG_ERR);\n    set_signals();\n", "    musl_host_init();\n", "1", "S10"}, 213},
	{"cut", []string{"    mch_signal(SIGHUP, SIG_IGN);\n", "1", "S11"}, 220},
	{"cut", []string{"            if (got_tstp && !in_mch_suspend)\n            {\n                exarg_T ea;\n\n                ea.forceit = TRUE;\n                ex_stop(&ea);\n                got_tstp = FALSE;\n            }\n\n", "1", "S12"}, 221},
	{"cut", []string{"static volatile sig_atomic_t got_tstp = FALSE;\n", "1", "S12b"}, 231},
	{"cut", []string{"    if (ignore_sigtstp)\n    {\n        return;\n    }\n\n", "1", "S13"}, 234},
	{"cut", []string{"static int ignore_sigtstp = FALSE;\n", "1", "S13b"}, 240},
	{"say", []string{"mch_signal(), signal_info[]'s three non-deadly rows, catch_signals(), set_signals(), reset_signals(), catch_int_signal(), sig_winch, sig_tstp, catch_sigint and sigcont_handler are gone.  deathtrap and vim_handle_signal STAY and the host installs deathtrap for SIGHUP and SIGTERM -- which is what keeps the terminal restored and the message printed when the editor is killed"}, 241},
	{"sub", []string{"    static void\nmch_suspend(void)\n{\n    in_mch_suspend = TRUE;\n\n    out_flush();\n    settmode(TMODE_COOK);\n    out_flush();\n\n    sigcont_received = FALSE;\n\n    kill(0, SIGTSTP);\n\n    {\n        long wait_time;\n\n        for (wait_time = 0; !sigcont_received && wait_time <= 3L; wait_time++)\n        {\n            mch_delay(wait_time, 0);\n        }\n    }\n    in_mch_suspend = FALSE;\n\n    after_sigcont();\n}\n", "    static void\nmch_suspend(void)\n{\n    out_flush();\n    term_leave();\n    out_flush();\n\n    musl_suspend();\n\n    term_enter();\n}\n", "1", "Y1"}, 252},
	{"delfunc", []string{"after_sigcont(void)\n{", "Y2"}, 289},
	{"cut", []string{"static volatile sig_atomic_t in_mch_suspend = FALSE;\n", "1", "Y3"}, 290},
	{"sub", []string{"static void settmode(tmode_T tmode);\n", "static void term_enter(void);\nstatic void term_leave(void);\nstatic void musl_host_init(void);\nstatic int musl_get_winsize(int *rows, int *cols);\nstatic void musl_term_start(void);\nstatic void musl_term_stop(void);\nstatic int musl_tty_keys(int fd, int *bs, int *intr, int *cr, int *nlcr);\nstatic void musl_delay(long ms, int interruptible);\nstatic int musl_wait_for_input(long ms);\nstatic int musl_read_input(char *buf, int len);\nstatic void musl_suspend(void);\n", "1", "M1"}, 293},
	{"sub", []string{"static tmode_T  cur_tmode  = TMODE_COOK ;", "static int      term_entered = FALSE;", "1", "M2"}, 305},
	{"sub", []string{"    static void\nsettmode(tmode_T tmode)\n{\n    if (!full_screen)\n    {\n        return;\n    }\n\n    if (tmode != cur_tmode)\n    {\n        if (tmode != TMODE_RAW)\n        {\n        }\n\n        if (termcap_active && tmode != TMODE_SLEEP && cur_tmode != TMODE_SLEEP)\n        {\n              ;\n\n            if (tmode != TMODE_RAW)\n            {\n                out_str( ( term_strings[(int)(KS_CBD)] ) );\n                out_str_t_TE();\n            }\n            else\n            {\n                out_str_t_BE();\n                out_str_t_TI();\n            }\n        }\n        out_flush();\n        mch_settmode(tmode);\n        cur_tmode = tmode;\n        if (tmode == TMODE_RAW)\n        {\n        }\n        out_flush();\n    }\n}", "    static void\nterm_enter(void)\n{\n    if (!full_screen || term_entered)\n    {\n        return;\n    }\n\n    if (termcap_active)\n    {\n        out_str_t_BE();\n        out_str_t_TI();\n    }\n    out_flush();\n    musl_term_start();\n    term_entered = TRUE;\n    out_flush();\n}\n\n    static void\nterm_leave(void)\n{\n    if (!full_screen || !term_entered)\n    {\n        return;\n    }\n\n    if (termcap_active)\n    {\n        out_str( ( term_strings[(int)(KS_CBD)] ) );\n        out_str_t_TE();\n    }\n    out_flush();\n    musl_term_stop();\n    term_entered = FALSE;\n    out_flush();\n}", "1", "M3"}, 307},
	{"sub", []string{"    settmode(TMODE_RAW);\n\n    init_history();", "    term_enter();\n\n    init_history();", "1", "M4"}, 383},
	{"sub", []string{"    if (exiting)\n    {\n        settmode(TMODE_RAW);\n    }", "    if (exiting)\n    {\n        term_enter();\n    }", "1", "M5"}, 385},
	{"sub", []string{"            full_screen = TRUE;\n            settmode(TMODE_COOK);\n            full_screen = was_full_screen;", "            full_screen = TRUE;\n            term_leave();\n            full_screen = was_full_screen;", "1", "M6"}, 390},
	{"sub", []string{"    {\n        settmode(TMODE_COOK);\n\n        if (swapping_screen() && !newline_on_exit)", "    {\n        term_leave();\n\n        if (swapping_screen() && !newline_on_exit)", "1", "M7"}, 393},
	{"sub", []string{"    settmode(TMODE_RAW);\n\n    if (need_wait_return || msg_didany)", "    term_enter();\n\n    if (need_wait_return || msg_didany)", "1", "M8"}, 396},
	{"sub", []string{"    TMODE_COOK,\n    TMODE_SLEEP,\n    TMODE_RAW} tmode_T;", "    TMODE_COOK,\n    TMODE_RAW} tmode_T;", "1", "M9"}, 398},
	{"sub", []string{"    tmode_T     old_tmode;\n    int         call_settmode;\n\n    if (flags & MCH_DELAY_IGNOREINPUT)\n    {\n        call_settmode = mch_cur_tmode == TMODE_RAW\n                               && (msec > 500 || (flags & MCH_DELAY_SETTMODE));\n        if (call_settmode)\n        {\n            old_tmode = mch_cur_tmode;\n            settmode(TMODE_SLEEP);\n        }\n\n        {\n            struct timespec ts;\n\n            ts.tv_sec = msec / 1000;\n            ts.tv_nsec = (msec % 1000) * 1000000;\n            (void)nanosleep(&ts, NULL);\n        }\n\n        if (call_settmode)\n        {\n            settmode(old_tmode);\n        }\n    }\n    else\n    {\n        WaitForChar(msec, NULL, FALSE);\n    }", "    if (flags & MCH_DELAY_IGNOREINPUT)\n    {\n        out_flush();\n        musl_delay(msec, TRUE);\n    }\n    else\n    {\n        WaitForChar(msec, NULL, FALSE);\n    }", "1", "D1"}, 405},
	{"sub", []string{"    struct termios keys;\n\n    if (mch_tcgetattr(fd, &keys) != -1)\n    {\n        info->backspace = keys.c_cc[VERASE];\n        info->interrupt = keys.c_cc[VINTR];\n        if (keys.c_iflag & ICRNL)\n        {\n            info->enter = NL;\n        }\n        else\n        {\n            info->enter = CAR;\n        }\n        if (keys.c_oflag & ONLCR)\n        {\n            info->nl_does_cr = TRUE;\n        }\n        else\n        {\n            info->nl_does_cr = FALSE;\n        }\n        return OK;\n    }\n    return FAIL;", "    int bs = 0;\n    int intr = 0;\n    int cr = 0;\n    int nlcr = 0;\n\n    if (musl_tty_keys(fd, &bs, &intr, &cr, &nlcr) == OK)\n    {\n        info->backspace = (char_u)bs;\n        info->interrupt = (char_u)intr;\n        info->enter = cr ? NL : CAR;\n        info->nl_does_cr = nlcr ? TRUE : FALSE;\n        return OK;\n    }\n    return FAIL;", "1", "K2"}, 452},
	{"sub", []string{"if ((mch_cur_tmode == TMODE_RAW || force) && RealWaitForChar(read_cmd_fd, 0L, NULL, NULL))", "if ((term_entered || force) && RealWaitForChar(read_cmd_fd, 0L, NULL, NULL))", "1", "K3"}, 490},
	{"cut", []string{"static tmode_T mch_cur_tmode = TMODE_COOK;\n", "1", "K4"}, 493},
	{"delfunc", []string{"mch_check_win(int argc  __attribute__((unused)) , char **argv  __attribute__((unused)) )", "T1"}, 515},
	{"cut", []string{"    stdout_isatty = (mch_check_win(paramp->argc, paramp->argv) != FAIL);\n\n", "1", "T2"}, 517},
	{"cut", []string{"static int      stdout_isatty  = TRUE ;\n", "1", "T3"}, 519},
	{"cut", []string{"            int out_redir = !stdout_isatty;\n\n", "1", "T4"}, 522},
	{"sub", []string{"                if (out_redir)\n                {\n                     fprintf(stderr, \"%s\", (ms)) ;\n                }\n                else\n                {\n                    msg(ms);\n                }\n", "                msg(ms);\n", "1", "T5"}, 523},
	{"sub", []string{"                if (out_redir)\n                {\n                    got_int = FALSE;\n                    do_cmdline_cmd((char_u *)\"qa\");\n                }\n                else\n                {\n                    msg(_(\"Type  :qa  and press <Enter> to exit Vim\"));\n                }\n", "                msg(_(\"Type  :qa  and press <Enter> to exit Vim\"));\n", "1", "T6"}, 533},
	{"cut", []string{"        if (!did_read_something && !isatty(read_cmd_fd) && read_cmd_fd == 0)\n        {\n            int m = cur_tmode;\n\n            settmode(TMODE_COOK);\n            close(0);\n            vim_ignored = dup(2);\n            settmode(m);\n        }\n", "1", "F1"}, 546},
	{"cut", []string{"    static int  did_read_something = FALSE;\n", "1", "F2"}, 558},
	{"cut", []string{"    if (len > 0)\n    {\n        did_read_something = TRUE;\n    }\n", "1", "F3"}, 559},
	{"sub", []string{"        len = read(read_cmd_fd, (char *)inbuf + inbufcount, readlen);\n", "        len = musl_read_input((char *)inbuf + inbufcount, (int)readlen);\n", "1", "H1"}, 566},
	{"sub", []string{"    else if (argc >= 3 && arg[0] == 48)\n", "    else if (first == '?' && argc == 1 && arg[0] == 1 && trail == 'z')\n    {\n        *slen = csi_len;\n        key_name[0] = (int)KS_EXTRA;\n        key_name[1] = (int)KE_IGNORE;\n        do_cmdline_cmd((char_u *)\"stop\");\n    }\n\n    else if (argc >= 3 && arg[0] == 48)\n", "1", "H2"}, 569},
	{"sub", nil, 813}, // computed by the Go
	{"say", nil, 870}, // computed by the Go
}

// z20Gone are the names that must be at 0 mentions when the edit is done, and
// z20Want the ones it leaves at a stated count with the reason.  Both are the
// phase's own lists, lifted rather than retyped.
var z20Gone = []string{"mch_signal", "set_signals", "reset_signals", "catch_signals", "catch_int_signal", "catch_sigint", "sig_tstp", "sigcont_handler", "sigcont_received", "after_sigcont", "in_mch_suspend", "ignore_sigtstp", "got_tstp", "sig_winch", "set_sigwinch_handler", "handle_resize", "do_resize", "mch_get_shellsize", "win_resize_setting", "win_resize_enabled", "term_set_win_resize", "did_set_termresize", "p_trz", "settmode", "mch_settmode", "mch_tcgetattr", "get_tty_fd", "mch_cur_tmode", "cur_tmode", "mch_check_win", "stdout_isatty", "did_read_something", "isatty", "out_redir"}

var z20Want = []struct {
	name string
	want int
	why  string
}{
	{"resize_func", 6, "inchar_loop's PARAMETER, which stays: the prototype, the definition and the three uses inside it.  The core passes NULL, and inchar_loop tests for it, so this is the interface and not a leftover"},
	{"deathtrap", 4, "a prototype, the definition, and the TWO installations in musl_host_init() -- the host installs the core's handler for SIGHUP and SIGTERM rather than replacing it, and that is what keeps the terminal restored on a deadly signal"},
	{"vim_handle_signal", 5, "a prototype, the definition, deathtrap's call and the two in ui_inchar -- untouched"},
	{"signal_info", 4, "the struct tag, the array, and deathtrap's two reads.  Its five rows are two"},
	{"term_enter", 6, "a prototype, the definition and four call sites"},
	{"term_leave", 5, "a prototype, the definition and three call sites"},
	{"musl_host_init", 3, "its prototype, its definition and the one call, from mch_init()"},
	{"musl_suspend", 3, "its prototype, its definition and mch_suspend()'s call"},
	{"musl_wait_for_input", 3, "its prototype, its definition and RealWaitForChar()'s one call"},
	{"musl_read_input", 3, "its prototype, its definition and fill_input_buf()'s one call"},
	{"musl_get_winsize", 4, "its prototype, its definition, ui_get_shellsize()'s call and musl_read_input()'s"},
	{"musl_delay", 3, "its prototype, its definition and mch_delay()'s one call"},
	{"musl_tty_keys", 3, "its prototype, its definition and get_tty_info()'s one call"},
	{"host_catch", 11, "its definition, eight installations in musl_host_init() and two in musl_suspend()"},
	{"ioctl", 2, "the #include and the host's one TIOCGWINSZ"},
	{"select", 1, "the host's one select(); there is no #include for it -- it arrives transitively through <sys/param.h> (ZERO-PLAN.md 4c)"},
}

// z20RealWait is the three-line RealWaitForChar the phase splices in place of
// the old one.  The Python builds it from four adjacent literals, so it is
// written here once rather than concatenated at the call site.
const z20RealWait = "RealWaitForChar(int fd  __attribute__((unused)) , long msec, int " +
	"*check_for_gpm  __attribute__((unused)) , int *interrupted  " +
	"__attribute__((unused)) )\n{\n    return musl_wait_for_input(msec);\n}" +
	"\n\n"
