#!/bin/sh
# Zero phase 10, the check -- the buffer has no name any more.
# See pipes/zero10-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero10-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero10-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old`, the binary this phase was HANDED,
# and `old.c`, the source it was built from: the left-hand side of every
# before-and-after count, and of every probe.
#
# SEVEN THINGS ARE PROVED HERE, and the fifth is the only one that can say what this
# phase is actually for.
#
# 1. THE CUT, WHICH IS THE SWEEP'S AND NOT THE EDIT'S.  SIXTY functions go and the
#    edit names none of them -- the largest number any zero phase has handed the
#    sweep, and all of it computed from four kinds of anchor: a cmdnames[] row, a
#    call site that passes NULL, sixteen folds, and an `if` on a flag no row carries.
#
#    THE TRAPS, ALL MEASURED, that make a copied "every name at zero" loop wrong:
#      * `otherfile` IS ALREADY ZERO.  Phase 8 swept it; `otherfile_buf` is this
#        phase's.  A list copied from ZERO-PLAN.md's P9 row would "prove" a name
#        that went two phases ago.
#      * `E447: Can't find file "%s" in path` REACHES ZERO HERE, and phase 8's check
#        asserts it SURVIVES.  Phase 8 removed the `gf` key; the message belonged to
#        `find_file_name_in_path()`'s search arm, which part G folds away.  The two
#        checks disagree on purpose and `apart 8 10` is not needed for it only
#        because `apart 8 9` and `apart 9 10` already forbid the stage.
#      * `"file"` reaches zero and `E32: No file name` DOES NOT.  `check_fname()`
#        survives, folded to an unconditional emsg, because `get_spec_reg()`'s `%`
#        still calls it.  A check that wanted both gone fails on a correct phase.
#      * `"[No Name]"` occurs TWICE and neither is a leftover: `buf_get_fname()`'s,
#        which is now the only name any buffer has, and `can_unload_buffer()`'s,
#        which part C folded a ternary into.
#      * `fileinfo` goes 4 -> 3 and not to 0: `:file` was one of four callers and
#        CTRL-G, `g CTRL-G` and the startup message are the other three.
#
# 2. WHAT IS LEFT WRITE-ONLY, NAMED, AND HANDED ON.  `BF_NOTEDITED` can never be set
#    -- `setfname()` was its only writer -- and `BF_NEW` never could; both are still
#    READ by `fileinfo()`, so CTRL-G still tests them and neither test can fire.
#    `b_shortname` has the same shape and was already write-only before this phase.
#    Folding any of the three would change the string set for no gain, so they are
#    asserted where they are.  `msg_scrolled_ign` is phase 9's leftover and does not
#    move.
#
# 3. THE LINE AGAINST THE PHASES AFTER THIS ONE, stated as counts so that reaching
#    into one would fail here rather than widen quietly: `check_changed` 4 and
#    `no_write_message` 3 (the `:q` phase's), `p_ur` 2 and `p_ro` 2 WITH their option
#    rows (the options phase's), `read_cmd_fd` 12, `vim_fsync` 3, `scriptin` 8 and
#    `redir_fd` 6 (the terminal's and the FILE* phase's).
#
# 4. THE ENUMERATORS, DUMPED EITHER SIDE.  Seventy-two go and EIGHTY-FIVE RENUMBER,
#    every one of the 85 a `CMD_`.  cmdnames[] is designated, so a row lands at its
#    own enumerator whatever the numbering is -- but nothing in the build would
#    notice if some other family had moved with them, and 85 movers from one family
#    is exactly the case CLAUDE.md says a build is happy to get wrong.  Four seconds
#    a dump, taken concurrently, and worth it.
#
# 5. THE PROBES, ON BOTH BINARIES, BECAUSE THE CORPUS CANNOT SEE A BUFFER BEING
#    NAMED.  The one case it does see is `cmd_file`, which types `:file` with no
#    argument and records the CTRL-G line for `[No Name]` -- so "that case moved" is
#    equally consistent with a phase that changed one message and left `setfname()`
#    reachable.  `file_rename` is the probe that is not: `:file NEWNAME` and then
#    CTRL-G answers `"NEWNAME" [Modified][Not edited] 1 line --100%--` on the binary
#    this phase was handed and `"[No Name]" [Modified] 1 line --100%--` here.  That
#    line, on the OLD binary, is the whole evidence that a buffer could be named.
#
#    AND `cp_missing` IS THE ONE PROBE THAT SHOWS THE OLD BINARY ASKING THE DISK.
#    With `nosuchfile` under the cursor, `: CTRL-R CTRL-P <CR>` was SILENT before --
#    `find_file_in_path()` stat()ed the name, found nothing and yielded NULL, so
#    nothing reached the command line -- and answers `E492: Not an editor command:
#    nosuchfile` now, the word having been extracted and nothing looked up.  Its
#    pair `cp_existing` must NOT move, and that is what says part G removed the
#    lookup and not the extraction: with `keys` under the cursor -- the keystroke
#    file tools/zstream.py always leaves in the run directory -- both binaries
#    answer `E488: Trailing characters: eys`, `:k` being a command of its own.
#    `cf_existing` is the same session with CTRL-F, which never expanded.
#
# 6. THE INHERITANCE CHECK.  `:file`'s row gave its shortest abbreviation as one
#    character, so `:f :fi :fil :file :file!` all reached it; each must answer E492
#    now and none may have answered E492 before.  `:filter` and `:fixdel` are the
#    neighbours that must not move -- CLAUDE.md's `:help` -> `:helpclose` trap.
#
# 7. A REAL TERMINAL, because every probe above went through a pipe: `:file NEWNAME`
#    and CTRL-G on a pty, and an ordinary editing session required to be identical.
#
# A record is built the way `zcases` builds one and scrubbed the same way
# (tools/zrec.py).  tools/zstream.py's session() is not called directly because this
# check needs the raw stream and the snapshot count beside the screens.

# THE BODY IS GO: tools/go/internal/check/zero10.go and tools/go/internal/check/zero10probes.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/enumvals.sh
#   tools/phasecheck.sh
#   tools/st.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero10-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero10-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero10 "$work" "$state"
