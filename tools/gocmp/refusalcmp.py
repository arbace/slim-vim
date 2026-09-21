#!/usr/bin/env python3
"""Did every refusal survive the port?

Usage: python3 tools/gocmp/refusalcmp.py <pipeline> <phase> <rev>
       python3 tools/gocmp/refusalcmp.py zero 26 HEAD~3

WHY THIS IS THE LAYER THAT MATTERS.  An edit port is gated by comparing a tree
AND a report.  A check returns no tree, so the gate collapses to the report and
the exit status -- and both are produced by the PASSING path.  Measured on
zero's checks, a passing report reaches none of the refusal sites:

    zero26-check.sh   511 lines, 25 refusal sites
    zero34-check.sh   829 lines, 28
    zero44-check.sh   614 lines, 34
    zero45-check.sh   750 lines, 37

roughly thirty per file, six hundred across a half.  So the dominant porting
failure is OMISSION -- an assertion that was not carried across -- and an
omitted assertion is invisible to a passing report by construction and to every
dynamic test that does not happen to trigger it.  A mutation corpus and the
`apart` lines reach maybe one site per case.  This reaches all of them, because
it does not run anything: it compares what the two implementations SAY.

WHAT IT PROVES AND WHAT IT DOES NOT.  That each refusal exists in the port and
is worded the same.  NOT that its condition is right -- a Go assertion that
carries the message and tests the wrong thing passes here and is caught only by
running it.  This is the cheap layer that covers the population; the dynamic
layers are the dear ones that cover the behaviour.

BOTH HALVES ARE AT RISK, and the first version of this tool said otherwise.
It reasoned that the port rewrites the heredocs and leaves the shell, so an
`echo ...; exit 1` is the same bytes either side.  That was true of the PROBE,
which left pipes/zero16-check.sh in place and gated a Go that duplicated it.
It is false of the port, where the shell becomes a thin dispatcher --
`exec tools/st.sh check zero26 "$work" "$state"` -- so the shell's report moves
into Go with everything else.  Measured when the hole was found: 335 shell
`exit 1` sites across zero 25-45 against ~630 heredoc sites, and for a file
like whim54, whose heredoc only prints a number, the shell is 100% of the risk.
`whim54` answered "no heredoc, so there is nothing to have been ported" while
being fully ported, which is how it surfaced.

THE SHELL HALF EXTRACTS EVERY REPORT LINE, not every refusal, and that is a
deliberate widening.  Associating a message with its `exit 1` is not reliable:
the message may be three lines back, the intervening line may be a variable
dump (`printf '%s\n' "$marks_new" | sed ...`), and a bare `exit 1` after a
`then` has its message elsewhere entirely.  Since the whole shell report moves
into Go, the honest statement is that every line the check can PRINT survives
the port -- which covers the refusals without a heuristic, and overlaps
harmlessly with the report comparison for the passing ones.

A report line is recognised by the tag format this tree writes everywhere:
two spaces, a tag, whitespace, text.  A shell literal that is not in that
shape is a command argument, a path or a pattern, and is not a report.

AST AND NOT REGEX.  The heredoc is valid Python by construction -- it runs --
so `ast` gives the exact argument of every `die(...)`, `sys.exit(...)` and
`fail.append(...)`, including implicit concatenation across lines and the
left-hand side of a `%`.  A regex would approximate all three and would have to
be tuned per file.

THE COMPARISON IS ON FRAGMENTS, NOT WHOLE MESSAGES, and the reason is the Go.
A port writes

    return nil, p.die("the file has %d preprocessor directives and this "+
        "phase was written against 11", n)

so the message exists in the source as two literals joined by `+` across a line
break.  Both sides are normalised -- adjacent literals concatenated, whitespace
collapsed -- and then the longest placeholder-free run of each message is what
is searched for.  A fragment is used rather than the whole string because a
port may legitimately reorder `%s` arguments or split a sentence differently;
it may not silently drop the sentence.
"""
import ast
import os
import re
import subprocess
import sys

MIN = 24          # a fragment shorter than this is not distinctive enough to
                  # prove anything; those messages are reported as UNTESTABLE
                  # rather than quietly counted as passes.
CALLS = ("die", "sys.exit", "fail.append", "bad")


def sh(*args):
    return subprocess.run(args, capture_output=True, text=True).stdout


def heredocs(text):
    """Every `python3 - ... <<'PY' ... PY` body, in order."""
    out, cur, inside = [], [], False
    for line in text.split("\n"):
        if not inside and re.match(r"^python3 - .*<<'PY'$", line):
            inside, cur = True, []
            continue
        if inside and line == "PY":
            out.append("\n".join(cur))
            inside = False
            continue
        if inside:
            cur.append(line)
    return out


def called(node):
    f = node.func
    if isinstance(f, ast.Name):
        return f.id
    if isinstance(f, ast.Attribute):
        base = f.value.id if isinstance(f.value, ast.Name) else ""
        return "%s.%s" % (base, f.attr) if base else f.attr
    return ""


def literal(node):
    """The format string of a refusal's argument, or None.

    Handles a plain string, implicit concatenation (which ast has already
    folded into one Constant), and `'...' % (...)`, whose left side is the
    format string.
    """
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Mod):
        return literal(node.left)
    if isinstance(node, ast.JoinedStr):          # an f-string
        return "".join(p.value for p in node.values
                       if isinstance(p, ast.Constant) and isinstance(p.value, str))
    return None


def successes(body):
    """Every REPORT line a heredoc prints on its passing path.

    The first version of this tool extracted refusals only -- `die`,
    `sys.exit`, `fail.append` -- and so could not see a success line written
    in different words.  The other session found it on zero11: five success
    lines rewritten from memory, same facts, tidier words, and this tool
    passed them, correctly, because it was scoped to refusals on purpose.
    Only the report-identity gate caught them, which made success lines the
    one class that only the EXPENSIVE gate protected.

    A report line is a `print` whose format string opens with the tag format
    `  %-12s`, which is what every check in this tree writes.  A `print` that
    does not is a debugging aid or a value, and is not a report.
    """
    try:
        tree = ast.parse(body)
    except SyntaxError:
        return []
    out = []
    # A heredoc that defines its own `say(what)` -- which prints `'  %-12s %s'
    # % (TAG, what)` -- reports its passing path through it, and its argument
    # is the whole report line without the tag.  zero42 and zero43 write most
    # of their success lines that way, and the print rule saw none of them.
    says = any(isinstance(n, ast.FunctionDef) and n.name == "say" for n in ast.walk(tree))
    for n in ast.walk(tree):
        if not isinstance(n, ast.Call) or not n.args:
            continue
        if called(n) == "print":
            s = literal(n.args[0])
            if s is not None and re.match(r"^ {2}%-12s ", s):
                out.append((n.lineno, s))
        elif says and called(n) == "say":
            s = literal(n.args[0])
            if s is not None:
                out.append((n.lineno, s))
    return out


def refusals(body):
    """Every refusal message in one heredoc, with its line."""
    try:
        tree = ast.parse(body)
    except SyntaxError as e:
        print("refusalcmp: a heredoc does not parse: %s" % e, file=sys.stderr)
        return []
    out = []
    for n in ast.walk(tree):
        if not isinstance(n, ast.Call) or called(n) not in CALLS:
            continue
        if not n.args:
            continue
        s = literal(n.args[0])
        # `die('tag', 'msg')` -- two-argument form, where the message is second.
        if s is not None and len(s) < MIN and len(n.args) > 1:
            t = literal(n.args[1])
            if t is not None:
                s = t
        if s is not None:
            out.append((n.lineno, s))
    return out


def norm(s):
    return re.sub(r"\s+", " ", s).strip()


def outside(text):
    """The shell, with every PY heredoc body removed."""
    out, inside = [], False
    for line in text.split("\n"):
        if not inside and re.match(r"^python3 - .*<<'PY'$", line):
            inside = True
            continue
        if inside and line == "PY":
            inside = False
            continue
        if not inside:
            out.append(line)
    return out


REPORT = re.compile(r"^ {2,}[A-Za-z][\w-]*\s{2,}\S")


def literals(line):
    """Every quoted string in one shell line -- a SCANNER, not a regex.

    A double-quoted shell string may contain `"` inside a `$( ... )`
    substitution, and the regex this replaced ended the literal at that inner
    quote.  On zero16 it truncated

        "  includes     ... $new_size bytes and make produced $(stat -c%s "$bin"): ..."

    at `$(stat -c%s ` and reported the sentence MISSING from a port that has
    it.  When the language nests, a regex is the wrong tool -- which is the
    same finding the cutters made about RE2 and lookaround, one language over.

    So: `$( )` spans are tracked with a depth counter and their contents are
    copied through, quotes and all.  Single-quoted strings admit no expansion
    and are taken literally.
    """
    out, i, n = [], 0, len(line)
    while i < n:
        c = line[i]
        if c == "'":
            j = line.find("'", i + 1)
            if j < 0:
                break
            out.append(line[i + 1:j])
            i = j + 1
            continue
        if c == '"':
            buf, j, depth = [], i + 1, 0
            while j < n:
                d = line[j]
                if d == "\\" and j + 1 < n:
                    buf.append(line[j:j + 2]); j += 2; continue
                if d == "$" and j + 1 < n and line[j + 1] == "(":
                    depth += 1; buf.append("$("); j += 2; continue
                if depth and d == ")":
                    depth -= 1; buf.append(")"); j += 1; continue
                if d == '"' and depth == 0:
                    break
                buf.append(d); j += 1
            out.append("".join(buf))
            i = j + 1
            continue
        i += 1
    return out


def shellmsgs(text):
    """Every report line the shell can print, with its line number.

    Literals are taken from lines that run `echo` or `printf`, and kept only
    if they are in the tag format -- two spaces, a tag, whitespace, text.
    That is what separates a report from a path, a pattern or a flag.
    """
    out = []
    # A SCRIPT THAT REPORTS THROUGH ITS OWN `die`/`say` puts the tag in the
    # function and the text in the argument -- `die "the edit left no ..."` --
    # so the echo/printf rule above never sees a message at all: zero42's check
    # read as 0 shell refusals while it holds 73.  When the script defines
    # either name as a function, every double-quoted argument to it is a
    # message, taken whole (there is no tag in it to strip).
    reporters = set(re.findall(r"^(die|say)\(\)\s*\{", text, re.M))
    for i, line in enumerate(outside(text), 1):
        if reporters and re.search(r"(?:^|[;&|{(]\s*|\s)(%s)\s+\"" % "|".join(reporters), line) \
                and not re.match(r"^\s*(die|say)\(\)", line):
            for lit in literals(line):
                if lit:
                    out.append((i, lit))
            continue
        if not re.search(r"\b(echo|printf)\b", line):
            continue
        for lit in literals(line):
            if lit and REPORT.match(lit):
                # THE TAG IS STRIPPED, and this is not cosmetic.  The shell
                # writes the tag INSIDE the literal -- `echo "  includes     the
                # libc surface moved..."` -- while the Go supplies it from the
                # report struct and the literal holds the text alone.  Left in,
                # the fragment begins `includes the libc surface moved` and is
                # reported MISSING from a port that carries the sentence
                # verbatim.  Measured on zero16: 2 false MISSING of 10 before
                # this, 0 after, and both were the tag.
                out.append((i, re.sub(r"^ {2,}[A-Za-z][\w-]*\s{2,}", "", lit)))
    return out


def unsubst(msg):
    r"""`msg` with every `$( ... )` replaced by one NUL, by BALANCED scanning.

    The regex this replaces was `\$\([^)]*\)`, which ends a command
    substitution at its first `)` -- and zero30's

        $(sed -n 's/^hup_clean  *st=[0-9]*  *out=\([0-9]*\).*/\1/p' "$tmp/S.cA")

    has one inside sed's `\)`.  The tail `"$tmp/S.cA")` then read as literal
    text, `$tmp` alone as the hole, and `/S.cA"), the extra eighteen being ...`
    was reported MISSING from a port that carries the sentence.  The scan skips
    backslash pairs and single-quoted strings, which is what the shell does.
    """
    out, i, n = [], 0, len(msg)
    while i < n:
        if msg.startswith("$(", i):
            depth, j = 1, i + 2
            while j < n and depth:
                c = msg[j]
                if c == "\\":
                    j += 2
                    continue
                if c == "'":
                    k = msg.find("'", j + 1)
                    j = n if k < 0 else k + 1
                    continue
                if msg.startswith("$(", j):
                    depth += 1
                    j += 2
                    continue
                # A plain `(` nests too: `$((a - b))` is arithmetic, and
                # counting only `$(` let its first `)` close the whole
                # expansion early -- zero41's `) bytes and the arena is`.
                if c == "(":
                    depth += 1
                    j += 1
                    continue
                if c == ")":
                    depth -= 1
                j += 1
            out.append("\0")
            i = j
            continue
        out.append(msg[i])
        i += 1
    return "".join(out)


def shellfragment(msg):
    """Every run with no shell expansion and no % conversion."""
    return [norm(p) for p in
            re.split(r"\0|\$\{?\w+\}?|%[-+#0-9.]*[a-zA-Z]|\\.", unsubst(msg))]


def fragment(msg):
    """EVERY run with no % placeholder and no backslash escape.

    The first version returned only the LONGEST run, and a control caught it
    failing to fail: rewording `THE BINARY IS BYTE-IDENTICAL` at the head of a
    message whose longest run was its tail left the tool reporting 0 MISSING.
    A fragment covers part of a message, so one fragment guarantees only that
    part.  Every run above the floor is required instead, which covers all of
    the message except the placeholders themselves.
    """
    return [norm(p) for p in re.split(r"%[-+#0-9.]*[a-zA-Z]|\\.", msg)]


def goparts(tag, phase):
    """Every Go file belonging to ONE phase, which is not `<tag><N>*.go`.

    A port may be split -- `zero4.go` beside `zero4probes.go`, because a
    600-line check with a probe table reads better in two -- and reading only
    `<tag><N>.go` called six of zero4's refusals MISSING that were present in
    its sibling.  Six false MISSINGs is worse than none: the reflex is to
    "fix" a port that is correct.

    BUT THE OBVIOUS GLOB IS WRONG, and measurably: `zero4*.go` also matches
    `zero41.go` through `zero45.go`.  That widens the haystack by six unrelated
    phases, so a message genuinely absent from zero4 but present in zero45 --
    and the shared shapes, "the reproducible build of the output failed" and
    its like, repeat across phases -- would be counted as found.  It reads
    correct today only because those six files do not exist yet in the tree
    where the glob was written.
    (Measured: `zero4*.go` -> zero4, zero4probes, zero41..zero45.)

    So a sibling is `<tag><N>` followed by a NON-DIGIT: `zero4probes.go` yes,
    `zero41.go` no.
    """
    d = "tools/go/internal/check"
    base = "%s%s" % (tag, phase)
    out = []
    for n in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        if not n.endswith(".go") or not n.startswith(base):
            continue
        rest = n[len(base):-3]
        if rest == "" or not rest[0].isdigit():
            out.append(os.path.join(d, n))
    return out


def gosource(paths):
    """The Go files with adjacent string literals joined and space collapsed.

    `"a "+\n\t"b"` becomes `"a b"`, which is what makes a fragment search work
    against a port that wrapped a sentence where the Python did not.
    """
    if not paths:
        return None
    t = "\n".join(open(p, errors="surrogateescape").read() for p in paths)
    t = re.sub(r'"\s*\+\s*\n\s*"', "", t)     # joined across a line break
    t = re.sub(r'"\s*\+\s*"', "", t)          # joined on one line
    # AND THE QUOTES ARE UNESCAPED, which is not cosmetic: a Go literal is
    # double-quoted, so a `"` inside it is written `\"`, while the Python it
    # came from was single-quoted and wrote it plainly.  Without this the
    # fragment `... -- "its only user is its own typedef" was not ...` is
    # reported MISSING from a port that carries it verbatim.  Found on this
    # tool's first run, against zero16, whose port was written by hand and is
    # known to have the message -- which is why the first test was run against
    # a port whose answer was already known.
    t = t.replace('\\"', '"')
    # AND A `\n` OR `\t` ESCAPE IS WHITESPACE, for the same reason.  The
    # Python's messages are compared as `ast` gives them -- the VALUE, where a
    # `\n` in the source is a real newline, which norm() then collapses -- while
    # the Go source still spells it as two characters.  zero41's "not
    # faithful:\n               in  %r" was a false MISSING until this.
    t = re.sub(r'(?<!\\)\\[nt]', ' ', t)
    return norm(t)


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__.split("\n")[2].strip())
    pipe, phase, rev = sys.argv[1], sys.argv[2], sys.argv[3]
    tag = {"slim": "slim", "whim": "whim", "zero": "zero"}[pipe]
    prog = "pipes/%s%s-check.sh" % (tag, phase)

    old = sh("git", "show", "%s:%s" % (rev, prog))
    if not old:
        sys.exit("refusalcmp: %s does not exist at %s" % (prog, rev))
    # A CHECK MAY BE ALL SHELL, so an absent heredoc is not an absent port --
    # whim54's heredoc only prints a number and every refusal it has is in the
    # shell.  Refusing here reported a fully ported file as unported.
    bodies = heredocs(old)

    msgs = []
    for b in bodies:
        msgs.extend(refusals(b))
    # Vacuity is still refused, but on the TOTAL of both halves rather than on
    # the Python alone.
    if not msgs and not shellmsgs(old):
        sys.exit("refusalcmp: no message found in %s at %s in either half -- the "
                 "extractor has stopped matching and every result below would "
                 "be vacuous" % (prog, rev))

    go = gosource(goparts(tag, phase))
    if go is None:
        sys.exit("refusalcmp: no tools/go/internal/check/%s%s*.go to compare against"
                 % (tag, phase))

    def compare(items, frag, what):
        missing, weak, found = [], [], 0
        for lineno, m in items:
            # EVERY fragment above the floor must be present, not just one.
            # A message is testable if it has at least one; it PASSES only if
            # all of them are there, so a rewording anywhere in it is caught
            # rather than only a rewording inside the longest run.
            fs = [f for f in frag(m) if len(f) >= MIN]
            if not fs:
                weak.append((lineno, norm(m)[:60]))
                continue
            gone = [f for f in fs if f not in go]
            if gone:
                missing.append((lineno, gone[0][:90]))
            else:
                found += 1
        print("  refusals     %s %s %-6s %d in the source at %s, %d found in the "
              "port, %d MISSING, %d too short to test"
              % (pipe, phase, what, len(items), rev, found, len(missing), len(weak)))
        for lineno, f in missing:
            print("    MISSING    %s:%d  %s" % (prog, lineno, f))
        for lineno, m in weak:
            print("    untestable %s:%d  %s" % (prog, lineno, m))
        return missing

    # BOTH HALVES, ALWAYS.  Reporting only the one a file happens to use is how
    # whim54 came back "nothing to have been ported" while being fully ported.
    bad = compare(msgs, fragment, "python")
    bad += compare(shellmsgs(old), shellfragment, "shell")
    # The success lines, reported apart from the refusals so that the two
    # numbers stay separable -- a port can drop a refusal and paraphrase a
    # success line, and those are different mistakes.
    oks = []
    for b in bodies:
        oks.extend(successes(b))
    bad += compare(oks, fragment, "passes")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
