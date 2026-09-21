#!/bin/sh
# Zero phase 13, the check -- no `FILE *` that is never opened.
# See pipes/zero13-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero13-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero13-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old`, the binary this phase was HANDED,
# and `old.c`, the source it was built from.
#
# NOTHING THIS PHASE REMOVES IS REACHABLE, so there is no behavioural must-differ
# probe and no dishonest one is offered instead.  It is phase 9's situation and phase
# 9's answer: the source the phase was handed, built TWICE.
#
#   probe  `(void)write(2, "FILESTAR-ENTERED\n", 17);` at FIVE places -- the top of
#          `closescript()`, inside `inchar()`'s `getc(scriptin[curscript])` loop,
#          inside `redir_write()`'s `redirecting()` block, inside `undo_cmdmod`'s,
#          and the top of `vim_fsync()`.  ZERO of the records may carry it -- 106 of
#          them when this phase was written, 122 since zero phase 40 added the
#          memline corpus, and the check counts rather than pins.
#   ctl    the IDENTICAL instrument at the top of `ui_write()`, which is reached by
#          every byte the editor draws.  It must mark almost all of them, and the
#          zero above is worth nothing without it.
#
# FIVE THINGS ARE PROVED.
#
# 1. THE COUNTS, WHICH ARE THE REST OF THE ARGUMENT.  `FILE` at **0 mentions** is the
#    cleanest single assertion this phase has: the type is not named in `zero-vim.c`
#    at all afterwards.  With it go `scriptin`, `curscript`, `NSCRIPT`,
#    `saved_typebuf`, `closescript`, `using_script`, `redir_fd`, `redir_off`,
#    `redir_write`, `redirecting`, `vim_fsync` and the two hand-folded locals
#    `script_char` and `retesc`.
#
#    THE TRAPS, ALL MEASURED:
#      * `may_sync_undo()` AND `is_safe_now()` MUST NOT BE DELETED.  Both survive one
#        conjunct shorter and still do their real work, and a check that expected
#        them at 0 would fail on a correct phase.
#      * `fputs` DOES NOT LEAVE, and ZERO-PLAN.md row 12 says it does.  After this
#        phase the source names it nowhere and `nm -u` still lists it: gcc lowers
#        `fprintf(stderr, "...")` to it, exactly as it lowers `printf` to `fputc`,
#        `fwrite` and `putchar`.  The freed set is asserted as exactly
#        `fclose fsync getc putc`.
#      * `fsync` IS THIS PHASE'S, not the buffer-name phase's: its only caller was
#        `vim_fsync()`, whose only caller was `ui_write()`'s `console` branch.
#      * `retesc` is a LOCAL THAT IS READ AND NEVER WRITTEN after the loop goes. No
#        warning covers it, `deadsweep.py` does not act on it, and leaving it would
#        mean `inchar()` returns an uninitialised value on a path the compiler thinks
#        exists.  `did_return` is the same shape.  Both were folded by hand.
#      * `NSCRIPT` is the one enumerator that leaves, and NOTHING RENUMBERS.
#
# 2. THE LIBC SURFACE, NAMED AS A SET AND NOT AS A COUNT -- `fclose getc putc fsync`
#    and nothing else -- and ZERO-PLAN.md 4b's invariant asserted in its strongest
#    form: `open creat openat stat access fcntl getcwd strerror fopen fdopen opendir`
#    absent from BOTH the source and the undefined set.  After this phase the core
#    has no `open`, no `stat`, no stdio stream and no fourth descriptor: it can only
#    read, write, close and dup fds 0, 1 and 2.
#
# 3. THE INSTRUMENTED PAIR, above.
#
# 4. EIGHTEEN ADVERSARIAL SESSIONS on both instrumented binaries, because "nothing
#    reaches it" is a claim about every input and not about the corpus: `:messages`,
#    `:verbose set ai?`, `:silent echo`, `:history`, `:registers`, `:display`, `ga`,
#    an unknown command, `:set all`, `:marks`, `:undolist`, `:changes`, `:map`,
#    `:highlight`, `:normal ihi`, `:g/a/p`, a recorded-and-replayed register and
#    `:set verbose=9` -- every one of them a way of making the editor PRINT, which is
#    where `redir_write()` sat.  Each must reach `ui_write()` and none may reach any
#    of the five.
#
# 5. AND THE ORDINARY SESSIONS, byte-identical either side, each required to be doing
#    something.  The corpus itself is `tools/zerodelta.sh --phase 13`, which
#    tools/phaserun.sh runs after this check.

# THE BODY IS GO: tools/go/internal/check/zero13.go and tools/go/internal/check/zero13evidence.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/enumvals.sh
#   tools/phasecheck.sh
#   tools/st.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero13-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero13-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero13 "$work" "$state"
