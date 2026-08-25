#!/bin/sh
# prove.sh -- run the self-hosting proof again.
#
# Two claims, both by byte comparison:
#
#   1. every .sol file in the repository compiles to exactly what solas produces
#   2. the compiler compiles its own source, and the result compiles its own
#      source to the same file
#
# This is a script and not a test on purpose. The experiment is parked, so it is
# expected to fall behind the language -- see README.md. Run it when you want to
# know, not on every build.
#
# Run from the repository root, with bin/ built:  ./experiment/prove.sh

set -e

if [ ! -x bin/solas ] || [ ! -x bin/solvm ]; then
    echo "build first: make" >&2
    exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The experiment's own files include each other and are found beside the file
# including them -- but lexer.sol now includes lib/scan.sol, so lib/ has to be
# on the path here too. It did not used to be, and that asymmetry was invisible
# until it was not: a `.sob` records the file each line came from, so finding
# scan.sol as `lib/scan.sol` rather than through the library path beside the
# binary changes the bytes. The fixpoint failed on the file *names*, with both
# compilers agreeing about every instruction.
echo "building the Solum compiler with solas"
bin/solas experiment/compile.sol -I lib -o "$work/gen1.sob"

echo
echo "1. every .sol file, both compilers, byte for byte"

same=0
differ=0
failed=0

for file in examples/*.sol lib/*.sol programs/*.sol experiment/*.sol; do
    name=$(basename "$file" .sol)
    if ! bin/solvm "$work/gen1.sob" "$file" -o "$work/mine.sob" -I lib >/dev/null 2>&1
    then
        failed=$((failed + 1))
        echo "   refused  $file"
        continue
    fi
    bin/solas -I lib "$file" -o "$work/theirs.sob" >/dev/null 2>&1
    if cmp -s "$work/mine.sob" "$work/theirs.sob"; then
        same=$((same + 1))
    else
        differ=$((differ + 1))
        echo "   DIFFERS  $file"
    fi
done

echo "   $same identical, $differ differing, $failed refused"

echo
echo "2. the fixpoint"

bin/solvm "$work/gen1.sob" experiment/compile.sol -o "$work/gen2.sob" -I lib >/dev/null
if cmp -s "$work/gen1.sob" "$work/gen2.sob"; then
    echo "   generation 2 is generation 1, byte for byte"
else
    echo "   GENERATION 2 DIFFERS from generation 1" >&2
    differ=$((differ + 1))
fi

bin/solvm "$work/gen2.sob" experiment/compile.sol -o "$work/gen3.sob" -I lib >/dev/null
if cmp -s "$work/gen2.sob" "$work/gen3.sob"; then
    echo "   generation 3 is generation 2, so it has stopped moving"
else
    echo "   GENERATION 3 DIFFERS from generation 2" >&2
    differ=$((differ + 1))
fi

# And that generation 2 is a working compiler rather than merely an identical
# file: it has to agree with solas on something it did not produce.
bin/solvm "$work/gen2.sob" examples/hello.sol -o "$work/h1.sob" -I lib >/dev/null
bin/solas -I lib examples/hello.sol -o "$work/h2.sob"
if cmp -s "$work/h1.sob" "$work/h2.sob"; then
    echo "   and generation 2 still agrees with solas on other work"
else
    echo "   GENERATION 2 DISAGREES with solas" >&2
    differ=$((differ + 1))
fi

echo
if [ "$differ" -eq 0 ] && [ "$failed" -eq 0 ]; then
    echo "the proof holds"
else
    echo "the proof does not hold here: $differ differing, $failed refused"
    exit 1
fi
