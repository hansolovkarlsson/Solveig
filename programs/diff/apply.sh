#!/bin/sh
#
# apply.sh -- the diff this program writes, applied by patch(1).
#
#     sh programs/diff/apply.sh            # 60 pairs out of this repository's history
#     sh programs/diff/apply.sh 200        # more of them
#
# **The oracle answers a different question from the one this checks.**
# `oracle.sh` asks whether our bytes are the tool's bytes, and where two minimal
# edit scripts exist the tool picks one and we pick another -- so a disagreement
# there is not the same thing as a wrong answer, and neither is agreement proof
# of a right one.
#
# This asks the property instead: **is the diff we wrote the diff from A to B?**
# `patch` is the judge, it was written by somebody else, and it does not care
# which of the minimal scripts it is handed.
#
# ---------------------------------------------------------------------------
# Why it exists, and what it caught
#
# It was written on 2026-09-02, after the corpus and a 2,400-run random sweep
# both reported nothing and **the first real pair of files disagreed** --
# `docs/method.md` at two revisions, where the tool splits an insertion around a
# blank line that also occurs inside the inserted block and we do not. Both
# answers are 33 insertions. Both are right.
#
# **The sweep could not have found it.** Its inputs are lines drawn from a small
# alphabet with mutations applied one at a time; the shape needed is a *block*
# inserted whole into prose, where a line inside the block equals the line at the
# seam. Nobody writes that by accident and a generator does not stumble on it.
#
# It does not reduce, either: no window of thirty lines either side of the seam
# reproduces it, because the tool's algorithm makes a global choice. So it
# cannot be a corpus case, and this is what stands in for one -- a check that
# passes on the pair the corpus cannot hold.
#
# ---------------------------------------------------------------------------
# The pairs
#
# Real files at two revisions of this repository, which is the only source of
# realistic input here that costs nothing. Text files only: `patch` is a text
# tool and so is this.

set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1

want=${1:-60}

if [ ! -f "$root/bin/solvm" ] || [ ! -f "$root/programs/diff.sob" ]; then
    echo "build first:  make && ./bin/solas programs/diff.sol"
    exit 1
fi

if ! command -v patch >/dev/null 2>&1; then
    echo "no patch(1) on this machine, which is the judge here."
    exit 2
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo
echo "our diff -u, applied by $(command -v patch)"
echo

pairs=0
good=0
bad=0
agreed=0
differed=0

# Every revision of every tracked markdown and source file, paired with the one
# before it. `git log` gives the revisions; two `git show`s give the pair.
for path in $(git ls-files '*.md' '*.sol' '*.c' '*.h' '*.sh' | head -80); do
    [ "$pairs" -ge "$want" ] && break
    revs=$(git log --format=%H -3 -- "$path" 2>/dev/null)
    prev=""
    for rev in $revs; do
        [ "$pairs" -ge "$want" ] && break
        if [ -n "$prev" ]; then
            git show "$rev:$path"  > "$work/A" 2>/dev/null || continue
            git show "$prev:$path" > "$work/B" 2>/dev/null || continue
            cmp -s "$work/A" "$work/B" && continue

            pairs=$((pairs + 1))

            ./bin/solvm programs/diff.sob -u "$work/A" "$work/B" > "$work/u" 2>"$work/err"
            status=$?
            if [ "$status" -ne 1 ]; then
                printf '  ERROR    %s @ %s -- exit %s\n' "$path" "$(echo "$rev" | cut -c1-8)" "$status"
                sed 's/^/           /' "$work/err"
                bad=$((bad + 1))
                prev=$rev
                continue
            fi

            cp "$work/A" "$work/P"
            if patch -s "$work/P" < "$work/u" 2>"$work/perr" && cmp -s "$work/P" "$work/B"; then
                good=$((good + 1))
            else
                printf '  WRONG    %s @ %s -- patch did not reproduce it\n' \
                    "$path" "$(echo "$rev" | cut -c1-8)"
                sed 's/^/           /' "$work/perr"
                bad=$((bad + 1))
            fi

            # And whether the tool agreed, which is news either way but is not
            # the thing being checked here.
            /usr/bin/diff -u "$work/A" "$work/B" > "$work/t" 2>/dev/null
            if cmp -s "$work/u" "$work/t"; then
                agreed=$((agreed + 1))
            else
                differed=$((differed + 1))
                printf '  differs  %s @ %s -- ours %s edits, the tool %s\n' \
                    "$path" "$(echo "$rev" | cut -c1-8)" \
                    "$(grep -c '^[-+][^-+]' "$work/u" 2>/dev/null || echo 0)" \
                    "$(grep -c '^[-+][^-+]' "$work/t" 2>/dev/null || echo 0)"
            fi
        fi
        prev=$rev
    done
done

echo
echo "$pairs pairs of real files at two revisions."
echo "  $good applied by patch and reproduced the second file, $bad did not."
echo "  $agreed byte-identical to /usr/bin/diff, $differed not -- see the counts above."
[ "$bad" -eq 0 ] || exit 1
exit 0
