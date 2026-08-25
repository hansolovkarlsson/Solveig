#!/bin/sh
# The NBS Minimal BASIC Test Programs, Version 2 -- 208 programs written at the
# National Bureau of Standards in 1980 to test an implementation against ANSI
# X3.60-1978, the standard ECMA-55 mirrors. A US government work, public domain.
#
# They are not vendored here. They are somebody else's 208 files, this
# repository has never carried a dependency, and the suite is not the sort of
# thing that should be silently forked -- so this fetches them.
#
# It is not part of `make test`: it needs the network and a 20MB clone, and the
# suite is not a pass/fail harness. Each program prints what it is testing and
# what a correct result looks like, for a person to read. What can be judged
# mechanically is what this reports: whether a program was accepted, whether it
# ran to the end, and what was said if not.
#
#   ./programs/basic/conformance.sh            fetch, build, run, summarise
#
# See the "What the conformance suite says" section of programs/basic.sol for
# what it found and where this interpreter is deliberately laxer.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/solveig-nbs
cd "$root"

[ -d "$work" ] || git clone --depth 1 https://git.code.sf.net/p/buraphakit/MB_git "$work"
[ -d "$work/NBS" ] || { echo "conformance: no NBS directory in $work" >&2; exit 1; }

make >/dev/null
./bin/solas programs/basic.sol -o "$work/basic.sob"

ran=0; refused=0; slow=0
for f in "$work"/NBS/P*.BAS; do
    if ./bin/solvm --steps=20000000 "$work/basic.sob" "$f" >/dev/null 2>"$work/err" </dev/null
    then ran=$((ran + 1))
    elif [ $? = 124 ] || grep -q 'step limit' "$work/err"
    then slow=$((slow + 1))
    else refused=$((refused + 1)); printf '%s\t%s\n' "$(basename "$f" .BAS)" "$(head -1 "$work/err")"
    fi
done
echo
echo "ran to the end $ran   refused $refused   over the step limit $slow"
echo "A refusal is not a failure: about half the suite tests errors on purpose."
