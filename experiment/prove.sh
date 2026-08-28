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

# The files this compiler cannot read, and the construct in each that it
# predates. **A refusal is only expected when it is on this list**, which is the
# difference between falling behind and being broken -- and it is the whole
# reason the list is a list rather than a count. When `solas` grows a construct,
# add the file and the construct here; when a file *not* named here is refused,
# something has broken and this script says so.
#
# What that guard was worth: `lib/scan.sol` drew an export boundary on
# 2026-08-27 and `lexer.sol` had been reaching past it, so every file here was
# refused for a day and nothing said anything -- the count could not tell 61
# working files from none.
expected_refusal() {
    case "$1" in
    examples/numbers.sol)   echo '$FF hexadecimal literals' ;;
    examples/files.sol)     echo '%1010 binary literals' ;;
    examples/operators.sol) echo '@expr regions' ;;
    *)                      echo '' ;;
    esac
}

same=0
differ=0
failed=0
behind=0

for file in examples/*.sol lib/*.sol programs/*.sol experiment/*.sol; do
    name=$(basename "$file" .sol)
    if ! bin/solvm "$work/gen1.sob" "$file" -o "$work/mine.sob" -I lib >/dev/null 2>&1
    then
        why=$(expected_refusal "$file")
        if [ -n "$why" ]; then
            behind=$((behind + 1))
            echo "   behind   $file -- $why"
        else
            failed=$((failed + 1))
            echo "   REFUSED  $file"
        fi
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

echo "   $same identical, $differ differing, $behind behind the language,\
 $failed refused unexpectedly"

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
    if [ "$behind" -eq 0 ]; then
        echo "the proof holds"
    else
        # The claim is about the files this compiler can read: of those, the
        # bytes are identical and the compiler is a fixpoint. Naming the ones it
        # cannot is what keeps that an honest claim rather than a smaller one
        # pretending to be the same size.
        echo "the proof holds over what this compiler can read;\
 $behind file(s) use constructs it predates"
    fi
else
    echo "the proof does not hold here: $differ differing,\
 $failed refused unexpectedly"
    exit 1
fi
