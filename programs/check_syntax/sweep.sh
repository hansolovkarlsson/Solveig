#!/bin/sh
#
# sweep.sh -- solum.bnf against every .sol file that ships.
#
# **Nothing had ever held the grammar to the compiler.** `expect.sol` checks
# GRAMMAR.md against solum.bnf, which is two documents written by hand from one
# understanding -- and this repository's own rule is that a comparison whose two
# sides came from the same source is not a comparison. This is the other side:
# the grammar against the code that actually ships.
#
# **It is not in `make test` and the reason is the clock.** 94 files take about
# 44 seconds, and almost all of it is one file: `sola.sol` is 196 KB and costs
# 6.7 s on its own, where the grammar itself parses in 0.046 s. The cost is
# matching the source, not reading the grammar, so nothing about the harness
# would make it cheaper.
#
# What *is* in `make test` is `syntax/`, one small file per construct, which
# catches the failure this exists for -- a construct added to the language and
# not to the grammar -- in about two seconds. This sweep catches the rest: a
# construct used in a real file in a shape the small one did not have.
#
#   ./programs/check_syntax/sweep.sh            # everything that ships
#   ./programs/check_syntax/sweep.sh lib        # a subdirectory

set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1

grammar="programs/check_syntax/solum.bnf"
checker="programs/check_syntax.sob"

if [ ! -f "$checker" ]; then
    echo "build first:  make && ./bin/solas programs/check_syntax.sol"
    exit 1
fi
if [ "programs/check_syntax.sol" -nt "$checker" ]; then
    echo "$checker is older than its source -- rebuild:"
    echo "  ./bin/solas programs/check_syntax.sol"
    exit 1
fi

scope=${1:-}
files=$(git ls-files '*.sol' | grep "^$scope" 2>/dev/null || git ls-files '*.sol')

echo
echo "solum.bnf against what ships"
echo

ok=0
bad=0
for f in $files; do
    if ./bin/solvm "$checker" "$grammar" "$f" >/dev/null 2>&1; then
        ok=$((ok + 1))
    else
        printf '  REFUSED   %s\n' "$f"
        ./bin/solvm "$checker" "$grammar" "$f" 2>&1 | sed -n '1,3p' | sed 's/^/            /'
        bad=$((bad + 1))
    fi
done

echo
if [ "$bad" -eq 0 ]; then
    echo "$ok files, and the grammar accepts every one."
    exit 0
fi
echo "$bad of $((ok + bad)) refused -- either the grammar is behind, or a file is wrong."
exit 1
