#!/bin/sh
#
# oracle.sh -- this Pascal against a real one.
#
# The only check here that can find something nobody thought of. Everything
# else programs/pascal.sol is held to is a transcript recorded by its own
# author, which is exactly the failure basic.sol's header describes: eighty-three
# claims in that file caught none of the seven real defects the NBS suite found,
# because those check what the author thought to check.
#
# There are two kinds of program in oracle/ and the difference is the point:
#
#   agree/    must produce the same bytes under both. A difference here is
#             news, and is either a defect or a divergence nobody had written
#             down yet.
#   differ/   must NOT. Each one exercises a divergence docs/PASCAL.md records,
#             and each says at the top what each side should do. A file here
#             that suddenly agrees is also news -- the divergence has gone and
#             the list should stop claiming it.
#
# So the divergence list stops being prose and becomes something that fails.
#
# Every program in agree/ writes its reals with an explicit field width, because
# the default is the implementation's to choose and ISO says so. That is the
# same discipline sola/oracle.sh keeps about SolaBasic's types.
#
# Not in `make test`. This repository has no dependencies beyond a C11 compiler
# and `make`, and keeps that by saying what it needs rather than fetching it.

set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1

# Homebrew's bin is not on every PATH, and a cask or a keg puts nothing there
# at all -- the same trap sola/oracle.sh documents about DOSBox.
FPC=${FPC:-}
if [ -z "$FPC" ]; then
    for c in fpc /opt/homebrew/bin/fpc /usr/local/bin/fpc; do
        if command -v "$c" >/dev/null 2>&1; then FPC=$c; break; fi
    done
fi

if [ -z "$FPC" ]; then
    echo "oracle.sh: no Free Pascal found."
    echo "  brew install fpc      # 3.2.2; -Miso is ISO 7185 mode"
    echo "  FPC=/path/to/fpc $0   # or say where it is"
    exit 2
fi

work=build/pas-oracle
rm -rf "$work"
mkdir -p "$work" || exit 1

if [ ! -x bin/solas ] || [ ! -x bin/solvm ]; then
    echo "oracle.sh: build the toolchain first -- make"
    exit 2
fi

./bin/solas programs/pascal.sol -o "$work/pascal.sob" || exit 1

same=0; differed=0; failed=0

check () {                       # check <file> <agree|differ>
    src=$1; want=$2
    name=$(basename "$src" .pas)

    # Theirs. -O- so optimisation cannot change what is printed, and the
    # compiler's own chatter goes nowhere.
    ( cd "$work" && cp "$root/$src" . && \
      "$FPC" -Miso -vw -O- "$name.pas" >/dev/null 2>&1 )
    if [ ! -x "$work/$name" ]; then
        echo "  $name: fpc would not compile it"
        failed=$((failed + 1)); return
    fi
    # A program that reads is fed the .in file beside it, and both sides get
    # the same bytes. Without one, standard input is empty rather than the
    # terminal -- a program that reads would otherwise wait for a person.
    stdin=/dev/null
    [ -f "${src%.pas}.in" ] && stdin="$root/${src%.pas}.in"

    ( cd "$work" && ./"$name" < "$stdin" > "$name.theirs" 2>&1 )

    # Ours.
    if ! ./bin/solvm "$work/pascal.sob" "$src" "$work/$name.sob" >/dev/null 2>&1
    then
        echo "  $name: pascal.sol would not compile it"
        ./bin/solvm "$work/pascal.sob" "$src" "$work/$name.sob" 2>&1 | sed 's/^/      /'
        failed=$((failed + 1)); return
    fi
    ( cd "$work" && "$root"/bin/solvm "$name.sob" < "$stdin" > "$name.ours" 2>&1 )

    if cmp -s "$work/$name.theirs" "$work/$name.ours"; then
        if [ "$want" = agree ]; then same=$((same + 1))
        else
            echo "  $name: AGREES, and differ/ says it should not"
            echo "      the divergence has gone -- docs/PASCAL.md is now wrong"
            failed=$((failed + 1))
        fi
    else
        if [ "$want" = differ ]; then differed=$((differed + 1))
        else
            echo "  $name: DIFFERS"
            diff "$work/$name.theirs" "$work/$name.ours" \
                | sed 's/^/      /' | head -20
            failed=$((failed + 1))
        fi
    fi
}

echo "oracle: $($FPC -iV) against programs/pascal.sol"
echo
echo "agree/ -- these must produce the same bytes"
for f in programs/pas/oracle/agree/*.pas; do check "$f" agree; done
echo "differ/ -- these must not"
for f in programs/pas/oracle/differ/*.pas; do check "$f" differ; done

echo
echo "$same agreed, $differed differed as recorded, $failed to look at"
[ "$failed" -eq 0 ] || exit 1
