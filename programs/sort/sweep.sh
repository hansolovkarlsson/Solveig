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

# ---------------------------------------------------------------------------
# The other way in
#
# **Everything above names its input on the command line**, and the reader for a
# pipe is different code: `readUpTo` answers out of a four-kilobyte window, so a
# read boundary falls in the middle of a line whenever the input is longer than
# 4,096 bytes -- and every case above is shorter than that. `oracle.sh` runs the
# corpus beside this file down both routes and is the reason this program's pipe
# route is checked at all, but its cases are a handful of lines each and none of
# them ever reaches a second read.
#
# So: the largest files in the repository, every option form, standard input on
# both sides. `sort` names standard input `-` and so does this one, which is
# what lets the two be compared with no allowance made.
#
# Proved by breaking it on purpose: a fill loop that stops at the first short
# answer -- the shape that ships when `readUpTo`'s contract is read as `fread`'s
# -- is reported here and by nothing else in this file.
comparePipe() {
    input=$1
    shift
    if [ "${1:-}" = "-" ]; then shift; fi

    "$theirs" "$@" < "$input" > "$work/o.out" 2> "$work/o.err"
    ostatus=$?
    $ours "$@" < "$input" > "$work/m.out" 2> "$work/m.err"
    mstatus=$?

    runs=$((runs + 1))
    if ! cmp -s "$work/o.out" "$work/m.out" \
        || ! cmp -s "$work/o.err" "$work/m.err" \
        || [ "$ostatus" -ne "$mstatus" ]; then
        bad=$((bad + 1))
        if [ "$bad" -le 3 ]; then
            printf '  DIFFERS  %s down a pipe  [%s]  exit %s against %s\n' \
                "$input" "$*" "$mstatus" "$ostatus"
            diff -u "$work/o.out" "$work/m.out" | sed -e '1,2d' -e 's/^/           /' | head -10
            diff -u "$work/o.err" "$work/m.err" | sed -e '1,2d' -e 's/^/           /' | head -4
        fi
    fi
}

sweep_forms_piped() {
    while IFS= read -r form; do
        [ -n "$form" ] || continue
        eval "comparePipe \"\$1\" $form"
    done <<FORMS
$forms
FORMS
}

big=$(git ls-files '*.md' '*.sol' '*.c' '*.h' | xargs wc -c 2>/dev/null \
      | awk '$2 != "total" && $1 > 4096 { print $1, $2 }' \
      | sort -rn | head -8 | awk '{ print $2 }')
piped=0
for path in $big; do
    [ -f "$path" ] || continue
    piped=$((piped + 1))
    sweep_forms_piped "$path"
done

# **And one input nothing else here can stand in for.** The files above are past
# one read and their *lines* are not. Measured rather than assumed, over the
# exact sets the halves above draw from: 645 bytes is the longest line the real
# half sees, 1,711 the longest in its whole pattern set, 1,694 in the piped
# eight, and 566 in this program's own corpus. So the branch that fills a second
# time because a piece arrived with no newline in it was reached by nothing.
# Same hole as the one this section closes, one level down.
#
# **The idea was already in the repository and had not reached this program.**
# `programs/tail/agree/chunk-longline.case` is a 9,000-byte line, and its first
# comment line is *one line longer than a chunk, so a record spans two reads*.
# It is kept there rather than copied here because the sweep can put this input
# through all 23 option forms and a case file names one.
#
# 4,095, 4,096 and 4,097 are here because the piece is 4,096 whatever is asked
# for, so those are the three ways a line can sit against the boundary.
#
# Proved by breaking it, and the numbers are the argument: a `fill` that reads
# once per call instead of looping until it has a newline is caught here by
# **23 of the 23 forms**, and by **0 of 23** on `docs/programs.md` down the same
# pipe. The pieces are 4,096 bytes and every line every other input in this file
# holds is shorter, so the defect is invisible to all of them.
awk 'BEGIN {
    n[1] = 30000; n[2] = 12000; n[3] = 5000
    n[4] = 4095;  n[5] = 4096;  n[6] = 4097; n[7] = 1
    w[0] = "alpha"; w[1] = "beta"; w[2] = "gamma"; w[3] = "delta"; w[4] = "eps"
    for (i = 1; i <= 7; i++) {
        line = ""
        while (length(line) < n[i]) line = line w[(length(line) + i) % 5] " "
        print substr(line, 1, n[i])
    }
}' > "$work/long"
piped=$((piped + 1))
sweep_forms_piped "$work/long"

echo "  piped:     $piped inputs past one read x $generated option forms"
echo "             (the last has lines of 30,000 and 4,097 bytes, which is the"
echo "              only place here where a line crosses a read)"

echo
if [ "$bad" -eq 0 ]; then
    echo "nothing disagreed."
    exit 0
fi
echo "$bad disagreeing of $runs."
exit 1
