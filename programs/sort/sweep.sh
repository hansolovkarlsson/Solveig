#!/bin/sh
#
# sweep.sh -- this sort against the tool, on inputs nobody chose.
#
#     sh programs/sort/sweep.sh              # both halves
#     sh programs/sort/sweep.sh 400          # more generated cases
#
# **The corpus beside this one is written by the person who wrote the program**,
# so it tests what that person thought of. This is the other two authors.
#
#   generated   lines drawn at random from a small alphabet, so that ties,
#               duplicates, empty lines and ragged fields all occur -- run under
#               every option form the program has.
#
#   real        every tracked text file in this repository, sorted whole. Lines
#               somebody wrote for their own reasons, with the repetition, the
#               blank lines and the leading indentation that generated input has
#               to be told to produce.
#
# ---------------------------------------------------------------------------
# Why the second half exists
#
# **`diff` learned this on 2026-09-02 and it cost a published claim.** Its
# corpus reported nothing, a 2,400-run generated sweep reported nothing, and
# the first pair of real files disagreed -- because the generator mutated one
# line at a time where the shape that mattered was a block inserted whole.
# [method.md](../../docs/method.md#a-generator-is-a-second-author-and-it-has-blind-spots-too)
# has the rule: an author's cases test what the author thought of, a generator
# tests what its generator can produce, and neither is the same as data somebody
# made for their own reasons.
#
# So this was written before the claim rather than after it. It found nothing on
# its first run, which is worth exactly as much as it sounds and no more -- but
# the run happened.
#
# ---------------------------------------------------------------------------
# `LC_ALL=C` on both sides, for the reason `oracle.sh` states: a string here is
# bytes and a collating locale is a different question.

set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1

LC_ALL=C
export LC_ALL

cases=${1:-200}

if [ ! -f "$root/bin/solvm" ] || [ ! -f "$root/programs/sort.sob" ]; then
    echo "build first:  make && ./bin/solas programs/sort.sol"
    exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

ours="$root/bin/solvm $root/programs/sort.sob"
theirs=/usr/bin/sort

# Every option form, including the ones that spill: `-S` small is the only way
# the external merge path is exercised at all, and a path that never runs is
# not checked by anything.
forms='
-
-r
-u
-f
-n
-nr
-b
-s
-k1,1
-k2,2
-k2
-k1,1 -k2,2
-t: -k2,2
-t: -k2,2n
-b -k2,2
-k2,2r
-u -k1,1
-s -k1,1
-S 16
-S 16 -u
-S 16 -s -k1,1
-S 16 -r
-c
'

runs=0
bad=0

compare() {
    # $1 is the input file, the rest is the option form.
    input=$1
    shift
    if [ "${1:-}" = "-" ]; then shift; fi

    "$theirs" "$@" "$input" > "$work/o.out" 2> "$work/o.err"
    ostatus=$?
    $ours "$@" "$input" > "$work/m.out" 2> "$work/m.err"
    mstatus=$?

    runs=$((runs + 1))
    if ! cmp -s "$work/o.out" "$work/m.out" \
        || ! cmp -s "$work/o.err" "$work/m.err" \
        || [ "$ostatus" -ne "$mstatus" ]; then
        bad=$((bad + 1))
        if [ "$bad" -le 3 ]; then
            printf '  DIFFERS  %s  [%s]  exit %s against %s\n' \
                "$input" "$*" "$mstatus" "$ostatus"
            diff -u "$work/o.out" "$work/m.out" | sed -e '1,2d' -e 's/^/           /' | head -10
            diff -u "$work/o.err" "$work/m.err" | sed -e '1,2d' -e 's/^/           /' | head -4
        fi
    fi
}

# **A redirect rather than a pipe, and this is not style.** `echo "$forms" |
# while ...` runs the loop in a subshell, so every disagreement `compare` counts
# is thrown away when the subshell exits and the script reports *nothing
# disagreed* whatever happened. That is a check that cannot fail, which is the
# thing [method.md](../../docs/method.md#a-check-that-cannot-fail-is-decoration)
# names first -- and the first draft of this file had it, with a comment
# underneath admitting the counters were lost and doing nothing about it.
#
# Proved by breaking the program on purpose and watching this report it.
sweep_forms() {
    while IFS= read -r form; do
        [ -n "$form" ] || continue
        # `eval` so a form is words rather than one argument, and so that the
        # empty form is no option at all.
        eval "compare \"\$1\" $form"
    done <<FORMS
$forms
FORMS
}

echo
echo "$theirs against programs/sort.sob, LC_ALL=C"
echo

# ---------------------------------------------------------------------------
# Generated

i=1
while [ "$i" -le "$cases" ]; do
    python3 - "$work/in" "$i" <<'PY'
import random, sys
path, seed = sys.argv[1], int(sys.argv[2])
r = random.Random(seed)
# Words short enough to collide, so ties are common; blank lines and ragged
# leading blanks, because both change what a field is.
words = ['a', 'b', 'c', 'ab', 'ba', '', '10', '9', '-2', '0', '1e3', 'x5']
lines = []
for _ in range(r.randint(0, 30)):
    fields = [r.choice(words) for _ in range(r.randint(1, 3))]
    sep = r.choice([' ', '  ', ':', ' '])
    line = sep.join(fields)
    if r.random() < 0.25:
        line = ' ' * r.randint(1, 3) + line
    lines.append(line)
text = ''.join(l + '\n' for l in lines)
if lines and r.random() < 0.15:
    text = text[:-1]
open(path, 'w').write(text)
PY
    sweep_forms "$work/in"
    i=$((i + 1))
done

generated=$(printf '%s\n' "$forms" | grep -c .)
echo "  generated: $cases inputs x $generated option forms"

# ---------------------------------------------------------------------------
# Real

files=$(git ls-files '*.md' '*.sol' '*.c' '*.h' '*.sh' '*.bnf' | head -${2:-40})
count=0
for path in $files; do
    [ -f "$path" ] || continue
    count=$((count + 1))
    sweep_forms "$path"
done
echo "  real:      $count files from this repository x $generated option forms"

echo
if [ "$bad" -eq 0 ]; then
    echo "nothing disagreed."
    exit 0
fi
echo "$bad disagreeing of $runs."
exit 1
