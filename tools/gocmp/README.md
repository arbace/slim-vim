# tools/gocmp/ — the evidence for the Go port

Every claim the Go cutover makes about equivalence was produced by a script in
here, run against the Python tool it replaces. They are committed because a
headline the repository cannot reproduce is a recording rather than a rule, and
the numbers below are worth nothing if nobody else can re-derive them.

**Nothing in here is named by any phase program, and that is deliberate.**
`tools/implhash.sh` hashes what a phase names; a comparison harness is not part
of any phase's implementation, and naming one would re-key every pipeline every
time a test changed.

## Build the corpus first

The comparisons need C to run against, and the useful C is not one file but
three populations. `$GOCMP_CORPUS` defaults to `.cache/gocorpus`.

```sh
sh tools/gocorpus.sh                    # recorded boundaries: whim-q*.c, zero-r*.c, slim
sh tools/gocmp/phasecorpus.sh 42-63     # the input each PHASE's edit is handed
sh tools/gocmp/toolinput.sh nostat ...  # the input each TOOL is handed
```

The second and third exist because of a measured failure, and the order of that
discovery is the point. A stage runs its edits in order on text no sweep has
touched since the stage began, so the input to phase 51 is nine edits into stage
42-63 and exists **nowhere on disk**. Comparing `keepbytes` against recorded
boundaries cut nothing at all — 482 inputs, 0 cuts — and the run reported
`VACUOUS` rather than passing. Then `optreaders` was vacuous again for a second
reason: it runs *second* inside `whim3-edit.sh`, so even a per-phase input is
wrong for it, and `toolinput.sh` truncates the edit script at the tool's own
invocation.

`toolinput.sh` looks for the INVOCATION and not the first mention, because
`whim32-edit.sh` names `tools/nocomplkeys.py` in a comment at line 25 and runs
it at line 48. Taking the first match truncated the edit 23 lines early, handed
the tool a tree `nocompl.py` had not cut, and **both implementations then
refused identically** — which is exactly why it surfaced as "0 cut" and not as a
difference. Agreement on a refusal is not agreement about a cut.

## The load-bearing scripts

| script | what it establishes |
| --- | --- |
| `pcutcmp.sh` + `pcutone.sh` | every single-file cutter against its Python, in parallel |
| `pargcmp.sh` + `pargone.sh` | the argument-taking cutters, on the invocations `pipes/` really makes |
| `cutcmp.sh` | the sequential form of the same thing; slower, kept because it is easier to read |
| `foldcmp.sh` | `cutil`'s fold primitives on real patterns from the phases that use them |
| `keyctl.sh` | `implhash` sees the Go implementation — with the controls that say the test can fail |
| `keymove.sh` | every implementation key in all three pipelines, for before/after diffing |
| `genlit.py` | renders a Python module's string constants as Go literals, by IMPORTING the module rather than scraping its source |

The headline: **57 cutters, 32,595 comparisons, 0 differences, 2,230 real cuts.**

## Two rules these encode

**A comparison that cannot fail proves nothing.** `pcutcmp.sh` counts the
comparisons that actually *cut* separately from the ones that refused, and exits
1 if nothing was cut. Both of the vacuous runs above were caught by that guard
and by nothing else.

**Refusals are compared as carefully as successes,** because for most inputs a
cutter's anchors are what is being tested. A third outcome is counted
separately rather than hidden: on 470 of `noterm`'s 482 inputs the Python
*raises* — `cutil.drop_if` throws `ValueError` and no caller catches it — where
the Go refuses with one line. Those two cannot agree textually, and a harness
that called them equal would be lying; what is required of them instead is the
property that matters, that both exit non-zero and neither writes the file.

## What is not here

Some of these are one-off debugging scripts from a single afternoon, kept rather
than pruned so that the set is what was actually run. `one.sh` prints both sides
for a single input and is the one to reach for when a comparison differs.
