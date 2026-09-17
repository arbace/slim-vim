#!/bin/sh
# The packages of a pipeline: the same phases read by concept, checked.
#
# Usage: tools/packages.sh <pipeline>              every package, its phases and stages
#        tools/packages.sh <pipeline> --of <N>     the package containing phase N
#        tools/packages.sh <pipeline> --check      check the packages; silent when they hold
#
# A PACKAGE is a view over pipes/<pipeline>.stages and nothing runs it: no phase,
# stage, boundary or cache key moves when a package does.  The manifest's
# `package NAME P...` lines put every phase in one concept, and its
# `uses A:P B:Q KIND why` lines record that phase P, in package A, relies on phase
# Q, in package B, having run -- KIND `mechanical` when P would fail or cut wrongly
# without Q, `rationale` when Q is only the stated reason P's cut is right.
# tools/stages.sh reads neither kind.
#
# Nothing that runs a phase calls this.  `make whim-verify` and `make whim-tip` run
# --check before they start, from whim.mk, which no implementation digest reads.
#
# This is not a mode of tools/stages.sh on purpose.  tools/phaserun.sh names
# stages.sh, so tools/implhash.sh hashes every byte of it into every stage's key:
# a line added there re-runs the whole whim pass.  Nothing that runs a phase names
# this file, and the manifest is hashed by nobody.
#
# THE CHECK refuses what would make the view a false statement --
#
#   a phase in no package, or in two
#   a phase or package line naming a phase the pipeline does not have
#   phases out of pipeline order inside one package, or a package declared twice
#   a `uses` naming an unknown package, or a phase that is not in the package named
#   a `uses` inside one package, which is the order of the package, not a dependency
#   a `uses` whose dependency runs AFTER its dependent, which cannot be relied on
#   a `uses` whose KIND is not `mechanical` or `rationale`, or with no reason
#
# What it cannot check is that a reason is true: that is the phase programs and
# WHIM-GOAL.md, which every `uses` line is written from.
set -eu

. tools/pipeline.sh "${1:?usage: packages.sh <pipeline> [--of N | --check]}"
mode=${2:-}
manifest=pipes/$IMPL.stages

check() {
    if [ ! -f "$manifest" ]; then
        echo "packages: $PIPE has no $manifest, so no packages" >&2
        return 1
    fi
    awk -v list="$PHASE_LIST" -v manifest="$manifest" '
        function bad(msg) { printf "packages: %s\n", msg > "/dev/stderr"; failed = 1 }
        function ref(s, what,    r) {
            if (s !~ /^[a-z][a-z0-9-]*:[0-9]+$/) { bad(what " " s " is not package:phase"); return 0 }
            split(s, r, ":")
            if (!(r[1] in declared)) { bad(what " " s " names no package"); return 0 }
            if (!((r[2] + 0) in pos)) { bad(what " " s " names no " pipe " phase"); return 0 }
            if (owner[r[2] + 0] != r[1]) {
                bad(what " " s ": phase " r[2] " is in " (owner[r[2] + 0] == "" ? "no package" : owner[r[2] + 0]))
                return 0
            }
            return 1
        }
        BEGIN {
            n = split(list, ph, " ")
            for (i = 1; i <= n; i++) pos[ph[i] + 0] = i
            failed = 0; npk = 0; nuses = 0
        }
        $1 == "package" {
            name = $2
            if (name !~ /^[a-z][a-z0-9-]*$/) { bad("line " NR ": package name \"" name "\" is not lowercase"); next }
            if (name in declared) { bad("package " name " is declared twice"); next }
            declared[name] = 1; order[++npk] = name
            if (NF < 3) bad("package " name " has no phases")
            last = 0
            for (i = 3; i <= NF; i++) {
                if ($i !~ /^[0-9]+$/ || !(($i + 0) in pos)) { bad("package " name ": " $i " is not a " pipe " phase"); continue }
                p = $i + 0
                if (p in owner) bad("phase " p " is in two packages, " owner[p] " and " name)
                else owner[p] = name
                if (pos[p] <= last) bad("package " name ": phase " p " is out of pipeline order")
                last = pos[p]
            }
            next
        }
        $1 == "uses" { u[++nuses] = $0; line[nuses] = NR; next }
        END {
            if (npk == 0) bad(manifest " declares no packages")
            for (i = 1; i <= n; i++)
                if (!((ph[i] + 0) in owner)) bad("phase " ph[i] " is in no package")
            for (k = 1; k <= nuses; k++) {
                nf = split(u[k], f, " ")
                if (nf < 5) { bad("line " line[k] ": a uses line needs a dependent, a dependency, a kind and a reason"); continue }
                if (f[4] != "mechanical" && f[4] != "rationale") {
                    bad("uses " f[2] " " f[3] ": kind \"" f[4] "\" is not mechanical or rationale"); continue }
                if (!ref(f[2], "uses") || !ref(f[3], "uses")) continue
                split(f[2], a, ":"); split(f[3], b, ":")
                if (a[1] == b[1]) { bad("uses " f[2] " " f[3] ": one package, not a cross-package dependency"); continue }
                if (pos[b[2] + 0] >= pos[a[2] + 0]) {
                    bad("uses " f[2] " " f[3] ": phase " b[2] " runs after phase " a[2] ", so " a[2] " cannot rely on it")
                    continue
                }
                if ((f[2] " " f[3]) in seen) bad("uses " f[2] " " f[3] " is declared twice")
                seen[f[2] " " f[3]] = 1
            }
            exit failed
        }' pipe="$PIPE" "$manifest"
}

# Every package, in manifest order: its phases, the stages they fall in, and what
# its phases rely on in other packages, with the kind of each.
show() {
    units=$(tools/stages.sh "$PIPE" | tr '\n' ' ')
    awk -v units="$units" '
        BEGIN {
            nu = split(units, us, " ")
            for (i = 1; i <= nu; i++) {
                a = us[i]; b = us[i]; sub(/-.*/, "", a); sub(/.*-/, "", b)
                for (p = a + 0; p <= b + 0; p++) unit[p] = us[i]
            }
        }
        $1 == "package" {
            order[++npk] = $2; phases = ""; stages = ""; delete had
            for (i = 3; i <= NF; i++) {
                phases = phases (i > 3 ? " " : "") $i
                if (!(unit[$i + 0] in had)) { had[unit[$i + 0]] = 1; stages = stages (stages == "" ? "" : " ") unit[$i + 0] }
            }
            row[$2] = sprintf("%-12s %-28s stages %s", $2, phases, stages)
            next
        }
        $1 == "uses" {
            split($2, a, ":")
            why = $0; sub(/^[ \t]*uses[ \t]+[^ \t]+[ \t]+[^ \t]+[ \t]+[^ \t]+[ \t]+/, "", why)
            dep[a[1]] = dep[a[1]] sprintf("\n             %-3s after %-16s %-10s %s", a[2], $3, $4, why)
            next
        }
        END { for (k = 1; k <= npk; k++) print row[order[k]] dep[order[k]] }' "$manifest"
}

case $mode in
    '')      check && show ;;
    --check) check ;;
    --of)
        n=${3:?usage: packages.sh <pipeline> --of N}
        check
        awk -v n="$n" '$1 == "package" { for (i = 3; i <= NF; i++) if ($i == n) { print $2; found = 1; exit } }
                       END { exit !found }' "$manifest" \
        || { echo "packages: no $PIPE package contains phase $n" >&2; exit 1; } ;;
    *) echo "usage: packages.sh <pipeline> [--of N | --check]" >&2; exit 2 ;;
esac
