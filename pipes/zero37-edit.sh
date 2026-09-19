#!/bin/sh
# Zero phase 37 -- the degenerate unions go.
# See ZERO-GOAL.md, whose charter is that the core is what a transpiler reads, and
# ZERO-PLAN.md 4c, whose rule is that the core's meaning must be on the page.
#
# Usage: pipes/zero37-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# THIS FILE HAS THIRTEEN `union` KEYWORDS AND SIX OF THEM UNION NOTHING WITH ANYTHING.
# They are not a style that was always there: they are LEFTOVERS of cuts this pipeline
# and whim's already made.  `u_header`'s four link fields were a union of a pointer and
# a swapfile block number, and the arm that named a block went with the swapfile;
# `typval_S.vval` was a union of nine arms -- a string, a list, a dictionary, a funcref,
# a float, a blob, a job, a channel and a number -- and the eval layer took eight of
# them; `estack_T.es_info` was a union of a `ufunc_T *` and a `sctx_T *`, and both went
# with the script stack.  What is left in each case is a variant type with ONE variant,
# which is a value with a longer spelling, and an EMPTY union, which is a value with no
# spelling at all.
#
# WHICH SIX IS COMPUTED AND NOT LISTED.  The edit scans the file for `union`, matches the
# braces, counts the member declarations at depth 1 and takes every union with FEWER THAN
# TWO as degenerate.  It must find both kinds -- at least one degenerate and at least one
# genuine -- so a scanner that stopped matching cannot pass by finding nothing.  Measured
# on the input: 1 member for `uh_next`, `uh_prev`, `uh_alt_next`, `uh_alt_prev` and
# `vval`, 0 for `es_info`, and 2 or 3 for `ae_u`, `lv_u`, `os_oldval`, `os_newval`,
# `rs_u`, `se_u` and `rs_un`, which stay exactly as they are.  Thirteen keywords become
# seven, and the seven that remain are the ones that are doing the job a union is for.
#
# THE EMPTY ONE IS THE ONE WITH A DIALECT ARGUMENT.  `union { } es_info;` is a GNU C
# extension: ISO C requires a struct-declaration-list to be non-empty, and gcc accepts it
# only because it accepts empty structs and unions as an extension -- `-Wpedantic` says
# so, and the check measures that the input draws exactly one such diagnostic and the
# output none.  ZERO-GOAL.md's core is meant to be readable by something that is not gcc,
# and a construct the C standard forbids is exactly the kind of latent exotic that costs
# a reader later.  It is also the cheapest possible removal: the field has ZERO uses, one
# mention in the whole file, its own declaration.
#
# WHAT THE REWRITE IS, and it is the same rule twice.  A single-member union becomes its
# member, keeping the UNION's name:
#
#       union {                              u_header_T *uh_next;
#           u_header_T *ptr;         ->
#       } uh_next;
#
# and every `uh_next.ptr` becomes `uh_next`.  The replacement text is the member's OWN
# declaration with the member's name replaced by the union's, so the type, the pointer
# stars and the internal spacing are the input's and not this program's.  The empty union
# is deleted outright, there being no member to promote and no use to rewrite.
#
# A PARTITION AND NOT A COUNT (CLAUDE.md, *Rename a name across the whole file*).  For
# each of the six names, EVERY mention outside a literal must classify as either its own
# declaration or a `.member` access on it, and a mention that is neither REFUSES.  That is
# what makes the rewrite safe rather than merely mechanical: a `uh_next` assigned or
# compared as a whole, a `sizeof(vval)`, a designated initialiser `.vval = `, or another
# struct with a field of the same name and a different member would all land in the
# leftover class and stop the phase.  The counts are read off the text here and nowhere
# written down, so this stays true of a file the phase has never seen -- which is the
# lesson phase 35 was taught when phase 34 moved its counted anchors.
#
# LITERAL-AWARE AND SINGLE-PASS, for the reason phase 23 measured.  The file has no
# preprocessor and no comments, so a string or character literal is exactly a quote and
# the escaped bytes to its match, and the scan is exact; no literal in this file holds any
# of the six names, which is asserted rather than assumed.  And every span -- six
# declarations and every accessor -- is computed against the ORIGINAL text and applied in
# ONE pass, because a second pass would index spans computed on the first pass's output
# and every offset after the first replacement is shifted.
#
# THE BINARY MUST NOT MOVE, AND THAT IS THE WHOLE OF THIS PHASE'S EVIDENCE.  A union of
# one member has the size and alignment of that member and its offset is the union's; an
# empty union contributes no storage.  So no structure layout changes, no expression
# changes value, and `uh_next.ptr` and `uh_next` name the same object at the same address.
# The check rebuilds both sides with SOURCE_DATE_EPOCH=0 and the boundary's own flags and
# requires THE SAME BYTES -- tier 1 of CLAUDE.md's verification table, which subsumes
# every screen case, every Ex-command row, every command line and every pty scenario at
# once, because the program that would be run is literally the same program.  The control
# that makes that `cmp` mean something is in the check and is a layout change of the same
# shape, in the same struct.
set -eu

work=${1:?usage: zero37-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero37-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a second
# time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

python3 - "$f" <<'PY'
import bisect
import re
import sys

TAG = 'unions'
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def say(what):
    print('  %-12s %s' % (TAG, what))


def blank_runs(text):
    L = text.split('\n')
    return sum(1 for i in range(1, len(L)) if L[i] == '' and L[i - 1] == '')


def line_of(text, pos):
    return text.count('\n', 0, pos) + 1


lines = t.split('\n')
runs_before = blank_runs(t)

# ---- 0. the file this edit was written against ----------------------------------------
# The boundary is the first `#include` and nothing else marks it (ZERO-PLAN.md 4c).  This
# phase adds no directive and removes none, and every union it touches is above it, which
# is checked below rather than assumed.
d = [i for i, l in enumerate(lines) if re.match(r'^ *#', l)]
if not d:
    die('the file has no preprocessor directive, so there is no boundary between the '
        'core and the host')
if d != list(range(d[0], d[0] + len(d))):
    die('the %d directives are not on consecutive lines, so the first `#include` is not '
        'a boundary' % len(d))
INC = re.compile(r'^ *# *include <([A-Za-z0-9_/.]+)>$')
if any(not INC.match(lines[i]) for i in d):
    die('a directive is not an `#include <...>` of a system header, and no phase may add '
        'one')
bound = d[0]
say('%d directives on consecutive lines from %d, every one an `#include <...>`; the core '
    'is the %d lines above the first of them' % (len(d), bound + 1, bound))

# ---- 1. the literals, which are the one thing a whole-file rewrite can get wrong -------
# A scanner and not a regex.  This file has no preprocessor and no comments, so a literal
# is exactly a quote, the escaped bytes to the matching quote, and nothing may cross a
# newline -- which is asserted, so a scanner that lost its place refuses rather than
# masking half the file.
def literal_spans(text):
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == '"' or c == "'":
            j = i + 1
            while j < n:
                if text[j] == '\\':
                    j += 2
                    continue
                if text[j] == c or text[j] == '\n':
                    break
                j += 1
            if j >= n or text[j] != c:
                die('an unterminated %s literal at line %d -- the scanner has lost its '
                    'place and every span after it would be wrong'
                    % ('string' if c == '"' else 'character', line_of(text, i)))
            out.append((i, j + 1))
            i = j + 1
        else:
            i += 1
    return out


S = literal_spans(t)
starts = [a for a, _ in S]


def in_literal(p):
    k = bisect.bisect_right(starts, p) - 1
    return k >= 0 and S[k][0] <= p < S[k][1]


say('%d string and character literals scanned, so every span below is over code' % len(S))

# ---- 2. every union in the file, and which of them union nothing -----------------------
# COMPUTED.  The braces are matched and the member declarations counted at depth 1; a
# union with fewer than two members is degenerate.  Nothing here is a name this program
# knows in advance, so it states a property of the file rather than a memory of one.
unions = []
for m in re.finditer(r'\bunion\b', t):
    if in_literal(m.start()):
        die('a literal holds the word `union` at line %d, which no literal in this file '
            'ever has' % line_of(t, m.start()))
    j = m.end()
    while j < len(t) and t[j] in ' \t\n':
        j += 1
    if j >= len(t) or t[j] != '{':
        die('the `union` at line %d is not followed by a brace, so this is a union type '
            'named rather than defined and the scanner cannot classify it'
            % line_of(t, m.start()))
    depth, k, members = 0, j, 0
    while k < len(t):
        c = t[k]
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                break
        elif c == ';' and depth == 1:
            members += 1
        k += 1
    if k >= len(t):
        die('the union at line %d never closes' % line_of(t, m.start()))
    tail = re.match(r'([ \t]*)([A-Za-z_]\w*)[ \t]*;', t[k + 1:])
    if not tail:
        die('the union at line %d does not end `} <name>;`, and this phase rewrites only '
            'a union declared as one named field' % line_of(t, m.start()))
    start = t.rindex('\n', 0, m.start()) + 1
    if t[start:m.start()].strip():
        die('the union at line %d does not begin its line' % line_of(t, m.start()))
    unions.append({
        'line': line_of(t, m.start()),
        'name': tail.group(2),
        'members': members,
        'indent': t[start:m.start()],
        'start': start,
        'body': t[j + 1:k],
        'end': k + 1 + tail.end(),
    })

if any(u['end'] > len('\n'.join(lines[:bound])) for u in unions):
    die('a union is defined below the boundary, in the host, and this phase is about the '
        'CORE')
degenerate = [u for u in unions if u['members'] < 2]
genuine = [u for u in unions if u['members'] >= 2]
if not degenerate or not genuine:
    die('the scan found %d degenerate unions and %d genuine ones, and it must find both '
        '-- a scanner that stopped matching would otherwise pass by finding nothing'
        % (len(degenerate), len(genuine)))
say('%d `union` keywords in the core, every one of them a `union { ... } <name>;` field: '
    '%d with fewer than two members and %d with two or more.  THE SEVEN THAT STAY ARE '
    'DOING THE JOB A UNION IS FOR: %s'
    % (len(unions), len(degenerate), len(genuine),
       ', '.join('%s (%d)' % (u['name'], u['members']) for u in genuine)))
say('THE %d THAT GO UNION NOTHING WITH ANYTHING: %s'
    % (len(degenerate),
       ', '.join('%s (%s)' % (u['name'], 'empty' if not u['members'] else '1 member')
                 for u in degenerate)))

# ---- 3. the partition: every mention is the declaration or a `.member` access -----------
# CLAUDE.md's rule, and the whole of what makes the rewrite safe.  A mention that is
# neither refuses -- a whole-union assignment, a `sizeof`, a designated initialiser, or
# another struct with a field of the same name and a different member.
edits = []
report = []
for u in degenerate:
    if u['members']:
        decl = u['body'].strip()
        mm = re.match(r'^(.*?)([A-Za-z_]\w*)[ \t]*;$', decl, re.S)
        if not mm or '\n' in decl:
            die('the single member of `%s` is not one `<type> <name>;` on one line: %r'
                % (u['name'], decl))
        u['member'] = mm.group(2)
        u['replacement'] = u['indent'] + mm.group(1) + u['name'] + ';'
    else:
        u['member'] = None
        u['replacement'] = None
    acc = 0
    leftover = []
    for m in re.finditer(r'\b%s\b' % u['name'], t):
        if in_literal(m.start()):
            leftover.append((line_of(t, m.start()), 'inside a literal'))
        elif u['start'] <= m.start() < u['end']:
            pass                      # its own declaration, which this edit rewrites
        elif u['member'] and t.startswith('.' + u['member'], m.end()) \
                and not (t[m.end() + 1 + len(u['member']):
                           m.end() + 2 + len(u['member'])] or ' ').isalnum() \
                and t[m.end() + 1 + len(u['member']):
                      m.end() + 2 + len(u['member'])] != '_':
            acc += 1
            edits.append((m.end(), m.end() + 1 + len(u['member']), ''))
        else:
            leftover.append((line_of(t, m.start()),
                             t[max(0, m.start() - 40):m.end() + 40].replace('\n', '|')))
    if leftover:
        die('`%s` has %d mention%s that is neither its own declaration nor a `.%s` access '
            'on it, so this phase may not rewrite it: %s'
            % (u['name'], len(leftover), '' if len(leftover) == 1 else 's',
               u['member'] or '<no member>',
               '; '.join('line %d %r' % x for x in leftover[:4])))
    if u['members'] and not acc:
        die('`%s` has no `.%s` access anywhere, so the field this phase would promote is '
            'read by nothing and belongs to the sweep and not to this edit'
            % (u['name'], u['member']))
    u['accessors'] = acc
    report.append((u['name'], acc))
    if u['members']:
        edits.append((u['start'], u['end'], u['replacement']))
    else:
        if t[u['end']:u['end'] + 1] != '\n':
            die('the empty union `%s` does not end its line, so deleting it would take '
                'code with it' % u['name'])
        edits.append((u['start'], u['end'] + 1, ''))
say('THE PARTITION HOLDS FOR ALL %d: every mention outside a literal is the '
    'declaration or a `.member` access on it, and there is nothing else -- %s'
    % (len(degenerate),
       ', '.join('%s 1 + %d' % (n, a) for n, a in report)))

# ---- 4. the rewrite: one pass over the original text ------------------------------------
# Every span was computed against THIS text and they are applied together, because a
# second pass would index spans computed on the first pass's output and every offset
# after the first replacement is shifted (phase 23 measured five of 437 left behind).
edits.sort()
for (a1, b1, _), (a2, _, _) in zip(edits, edits[1:]):
    if b1 > a2:
        die('two edit spans overlap at offset %d, so applying them in one pass would '
            'corrupt the text' % a2)
parts, last = [], 0
for a, b, rep in edits:
    parts.append(t[last:a])
    parts.append(rep)
    last = b
parts.append(t[last:])
t = ''.join(parts)
say('%d spans rewritten in ONE pass over the original text: %d declarations and %d '
    '`.member` accesses' % (len(edits), len(degenerate), len(edits) - len(degenerate)))

# ---- 5. what the file is now --------------------------------------------------------------
L = t.split('\n')
left = re.findall(r'\bunion\b', t)
if len(left) != len(genuine):
    die('the file has %d `union` keywords and the %d genuine ones are what must remain'
        % (len(left), len(genuine)))
for u in degenerate:
    n = len(re.findall(r'\b%s\b' % u['name'], t))
    want = 1 + u['accessors'] if u['members'] else 0
    if n != want:
        die('`%s` has %d mentions and must have %d -- its own declaration and the %d '
            'accesses that are now plain field references'
            % (u['name'], n, want, u['accessors']))
    if u['members']:
        if t.count(u['replacement'] + '\n') != 1:
            die('`%s` is not declared exactly once as `%s`'
                % (u['name'], u['replacement'].strip()))
        if re.search(r'\b%s\s*\.\s*%s\b' % (u['name'], u['member']), t):
            die('a `%s.%s` access survives' % (u['name'], u['member']))
nd = [i for i, l in enumerate(L) if re.match(r'^ *#', l)]
if len(nd) != len(d):
    die('the file has %d directives and had %d: this phase adds none and removes none'
        % (len(nd), len(d)))
if nd[0] - d[0] != len(L) - len(lines):
    die('the boundary moved by %d lines and the file by %d: every line this phase touches '
        'is above the first `#include`' % (nd[0] - d[0], len(L) - len(lines)))
if blank_runs(t) != runs_before:
    die('the edit left %d runs of two blank lines where there were %d'
        % (blank_runs(t), runs_before))
say('`union` %d -> %d, %d -> %d lines, %d directives unmoved relative to the text, and '
    'the blank-line runs unchanged at %d'
    % (len(unions), len(left), len(lines) - 1, len(L) - 1, len(nd), blank_runs(t)))

open(path, 'w', errors='surrogateescape').write(t)
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  unions       the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  unions       the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from -- a union of ONE member has the size, the alignment and the offset of that member and an EMPTY union contributes no storage, so this phase changes no layout and no code at all, and the check rebuilds the output the same way and requires THE SAME BYTES"

# tools/phaserun.sh sweeps next, then runs pipes/zero37-check.sh.
