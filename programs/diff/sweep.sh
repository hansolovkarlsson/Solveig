#!/bin/sh
#
# sweep.sh -- this diff against the tool, on inputs nobody chose.
#
#     sh programs/diff/sweep.sh              # the option sweep
#     sh programs/diff/sweep.sh 400          # more cases
#     sh programs/diff/sweep.sh 400 minimal  # and check the tool's own minimality
#
# **The corpus beside this one is written by the person who wrote the program.**
# This is the second author: file pairs built from a small alphabet, mutated a
# line at a time, run under every output form.
#
# ---------------------------------------------------------------------------
# What it found, and what it could not
#
# It was written on 2026-09-02 as a throwaway and is here because the numbers it
# produced went into five documents -- and
# [method.md](../../docs/method.md#and-a-comparison-whose-two-sides-did-not-run-alike-is-not-one-either)
# says a throwaway that measures something the documents will state is not a
# throwaway, it is a check, and owes the same discipline. Keeping it is the rest
# of paying that.
#
#   **44 disagreements in 1,050 runs** before the empty-range rule was fixed:
#   a unified header writes an empty range at the line it follows *except* at
#   the start of a file that has lines. Twenty-four hand-written cases had
#   passed the wrong rule, and only seven of them could have shown it.
#
#   **2,400 runs, zero** afterwards, over six option forms and files to forty
#   lines -- with `-i` excluded, for the reason below.
#
# **And the first pair of real files disagreed anyway**, an hour later. Where a
# line inside an inserted block equals the line at the seam, an insertion can be
# placed as one run or split around that line for the same number of edits; one
# real pair in five does it. That shape needs a *block* inserted whole and this
# generator mutates one line at a time, so it cannot produce it.
# [apply.sh](apply.sh) is what covers that, by asking the property instead.
#
# **`-i` is left out of the option list on purpose.** The tool disagrees with
# *itself* there -- on input holding no uppercase at all it picks a different
# one of two equally minimal answers than it picks without the flag --
# and `differ/ignore-case-ties.case` pins the minimal example. Including it here
# would report 41 runs in 400 that are not defects.
#
# ---------------------------------------------------------------------------
# `minimal` -- a second question, and a retraction
#
# With `minimal` as the second argument it also computes the true minimum edit
# distance and reports any pair where the tool used **more**. That mode exists
# because of a claim that was made and withdrawn: a shrinker that drifted
# produced a pair where `/usr/bin/diff` appeared to use 232 edits against this
# program's 228, which would have meant the tool was not minimal. **47,991
# generated pairs later it was never above the minimum**, and the input that
# produced the reading was gone.
#
# *Re-running a wrong experiment is not evidence* cuts both ways: a result that
# cannot be re-run is not one either. This is the mode that lets somebody try.

set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1

cases=${1:-200}
mode=${2:-forms}

if [ ! -f "$root/bin/solvm" ] || [ ! -f "$root/programs/diff.sob" ]; then
    echo "build first:  make && ./bin/solas programs/diff.sol"
    exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

theirs=/usr/bin/diff
ours="$root/bin/solvm $root/programs/diff.sob"

echo
echo "$theirs against programs/diff.sob"
echo

runs=0
bad=0

# A pair of files from a seed. Short lines from a small alphabet, so that ties
# and duplicates are common; an empty line is one of the choices, and one pair
# in five loses its final newline.
generate() {
    python3 - "$work" "$1" <<'PY'
import random, sys
w, seed = sys.argv[1], int(sys.argv[2])
r = random.Random(seed)
alphabet = ['a','b','c','d','e','f','g','h','']
a = [r.choice(alphabet) for _ in range(r.randint(0, 25))]
b = list(a)
for _ in range(r.randint(0, 8)):
    if not b or r.random() < 0.4:
        b.insert(r.randint(0, len(b)), r.choice(alphabet))
    elif r.random() < 0.5:
        del b[r.randint(0, len(b) - 1)]
    else:
        b[r.randint(0, len(b) - 1)] = r.choice(alphabet)
for name, lines in (('A', a), ('B', b)):
    text = ''.join(l + '\n' for l in lines)
    if lines and r.random() < 0.2:
        text = text[:-1]
    open(w + '/' + name, 'w').write(text)
PY
}

if [ "$mode" = minimal ]; then
    # The true minimum is `n + m - 2 * LCS`, computed here rather than by either
    # side, so that neither is asked to mark its own work.
    i=1
    while [ "$i" -le "$cases" ]; do
        generate "$i"
        used=$("$theirs" "$work/A" "$work/B" | grep -c '^[<>] ' || true)
        least=$(python3 - "$work" <<'PY'
import sys
w = sys.argv[1]

# **A trailing newline is a terminator and not a line**, and an incomplete last
# line is not equal to a complete one with the same text -- which is exactly
# what `\ No newline at end of file` reports. The first draft of this took
# `read().split()` at face value and reported the tool above the minimum on 55
# pairs of 200, every one of them a file pair differing in its final newline.
# The check was wrong, not the tool.
def lines(path):
    text = open(path).read()
    if text == '':
        return []
    parts = text.split('\n')
    if parts[-1] == '':
        return parts[:-1]
    parts[-1] += '\n'          # a sentinel no line can contain
    return parts

a = lines(w + '/A')
b = lines(w + '/B')
n, m = len(a), len(b)
prev = [0] * (m + 1)
for x in range(1, n + 1):
    cur = [0] * (m + 1)
    for y in range(1, m + 1):
        cur[y] = prev[y-1] + 1 if a[x-1] == b[y-1] else max(prev[y], cur[y-1])
    prev = cur
print(n + m - 2 * prev[m])
PY
)
        runs=$((runs + 1))
        if [ "$used" -gt "$least" ]; then
            bad=$((bad + 1))
            [ "$bad" -le 3 ] && printf '  ABOVE    seed %s: the tool used %s edits, the minimum is %s\n' \
                "$i" "$used" "$least"
        fi
        i=$((i + 1))
    done
    echo
    echo "$cases pairs, the tool above the minimum on $bad."
    [ "$bad" -eq 0 ] && exit 0
    exit 1
fi

# `-i` is not here; see the header.
forms='
-
-u
-U 0
-U 1
-U 7
-q
'

compare() {
    if [ "${1:-}" = "-" ]; then shift; fi
    "$theirs" "$@" "$work/A" "$work/B" > "$work/o.out" 2>&1
    ostatus=$?
    $ours "$@" "$work/A" "$work/B" > "$work/m.out" 2>&1
    mstatus=$?
    runs=$((runs + 1))
    if ! cmp -s "$work/o.out" "$work/m.out" || [ "$ostatus" -ne "$mstatus" ]; then
        bad=$((bad + 1))
        if [ "$bad" -le 3 ]; then
            printf '  DIFFERS  seed %s  [%s]  exit %s against %s\n' \
                "$seed" "$*" "$mstatus" "$ostatus"
            echo "           A:"; sed 's/^/             /' "$work/A"
            echo "           B:"; sed 's/^/             /' "$work/B"
            diff -u "$work/o.out" "$work/m.out" | sed -e '1,2d' -e 's/^/           /' | head -12
        fi
    fi
}

# A redirect rather than a pipe: a `while` loop after a pipe runs in a subshell
# and every count it makes is thrown away, which `sort/sweep.sh` shipped with
# once and which makes a check that cannot fail.
seed=1
while [ "$seed" -le "$cases" ]; do
    generate "$seed"
    while IFS= read -r form; do
        [ -n "$form" ] || continue
        eval "compare $form"
    done <<FORMS
$forms
FORMS
    seed=$((seed + 1))
done

echo "  $cases generated pairs x $(printf '%s\n' "$forms" | grep -c .) option forms"
echo
if [ "$bad" -eq 0 ]; then
    echo "nothing disagreed, over $runs runs."
    exit 0
fi
echo "$bad disagreeing of $runs."
exit 1
