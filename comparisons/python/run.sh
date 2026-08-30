#!/bin/sh
# Runs the comparison. From the repository root:
#
#   comparisons/python/run.sh                  # every benchmark
#   comparisons/python/run.sh loop float       # only these
#   RUNS=31 comparisons/python/run.sh          # more rounds per pair
#   SOLVM=/path/to/solvm comparisons/python/run.sh
#
# The numbers on docs/performance.md were taken with an -O2 build, and the
# binaries `make` puts in bin/ are not that -- they carry -g and no optimiser,
# which is 1.9x to 4.1x slower. Build the one being measured on purpose:
#
#   make CFLAGS="-std=c11 -Wall -Wextra -Wpedantic -O2"
#
# Every pair is checked for the same answer before it is timed, because a
# benchmark whose two halves compute different things measures nothing.
set -e

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)

SOLAS=${SOLAS:-$root/bin/solas}
SOLVM=${SOLVM:-$root/bin/solvm}
PYTHON=${PYTHON:-python3}
RUNS=${RUNS:-21}

# bench.sol is the thing doing the measuring, and it is run by whichever solvm
# is in bin/ -- not by the one under test, which would have it competing with
# its own subject for the machine.
BENCH=$root/bin/solvm
BENCH_SOB=$root/programs/bench.sob

[ -x "$SOLAS" ] || { echo "no solas at $SOLAS -- run make first" >&2; exit 1; }
[ -x "$SOLVM" ] || { echo "no solvm at $SOLVM -- run make first" >&2; exit 1; }
[ -f "$BENCH_SOB" ] || "$SOLAS" "$root/programs/bench.sol" -o "$BENCH_SOB"

which=${*:-loop fib array dict strlib strloop float object higher}

echo "solveig: $("$SOLVM" --version)"
echo "python:  $("$PYTHON" --version 2>&1)"
echo "runs:    $RUNS interleaved rounds per pair"
echo

for b in $which; do
    sol=$here/$b.sol
    py=$here/$b.py
    [ -f "$sol" ] && [ -f "$py" ] || { echo "no such benchmark: $b" >&2; exit 1; }

    "$SOLAS" "$sol" -o "$here/$b.sob"

    # The same answer, or the comparison is meaningless. Solveig prints an
    # integer as #45 and Python as 45, so the tag comes off before comparing.
    a=$("$SOLVM" "$here/$b.sob" | tr -d '#')
    e=$("$PYTHON" "$py")
    if [ "$a" != "$e" ]; then
        echo "$b: THE TWO DISAGREE, so there is nothing to time" >&2
        echo "  solveig: $a" >&2
        echo "  python:  $e" >&2
        exit 1
    fi

    echo "########## $b ##########"
    "$BENCH" "$BENCH_SOB" "$RUNS" "$SOLVM" "$here/$b.sob" -- "$PYTHON" "$py"
    echo
done
