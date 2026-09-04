#!/bin/sh
#
# sweep.sh -- gzip.sol against the gzip on the machine, over files it made.
#
#     sh programs/gzip/sweep.sh
#
# **Every case is a round trip**, which is the strongest shape an oracle check
# here has taken. Elsewhere a corpus holds an input and both tools are asked
# what they make of it; here the oracle *produces* the input, so a disagreement
# cannot be a divergence about what the input meant. The only thing being
# compared is whether the bytes come back.
#
# Three rungs, in the order method.md puts them:
#
#   author    a handful of shapes chosen because they exercise a branch --
#             empty, one byte, a run, incompressible, a name in the header
#   generator random data at every compression level, which is what forces
#             stored blocks and long back-references without anybody choosing
#   real      this repository's own files, which is where the last two defects
#             in `sort` came from and where a generator does not reach
#
# It leaves 1 if anything disagreed, and says what.

set -u

VM=${SOL_RUN:-./bin/solvm}
SOB=${SOL_GZIP:-programs/gzip.sob}
GZIP=${GZIP_TOOL:-/usr/bin/gzip}
if [ ! -f "$VM" ] || [ ! -f "$SOB" ]; then
    echo "build first:  make && ./bin/solas programs/gzip.sol"
    exit 2
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/gzip-sweep.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

cases=0
bad=0

# One file, one level: gzip it, inflate it here, compare with the original.
try() {
    name=$1
    src=$2
    level=$3
    extra=${4:-}
    cases=$((cases + 1))
    $GZIP $extra "-$level" -c "$src" > "$WORK/c.gz" 2>/dev/null || {
        echo "FAIL $name -$level: the oracle would not compress it"
        bad=$((bad + 1))
        return
    }
    if ! $VM "$SOB" -dc "$WORK/c.gz" > "$WORK/out" 2>"$WORK/err"; then
        echo "FAIL $name -$level: gzip.sol left non-zero -- $(cat "$WORK/err")"
        bad=$((bad + 1))
        return
    fi
    if ! cmp -s "$src" "$WORK/out"; then
        echo "FAIL $name -$level: the bytes differ from the original"
        bad=$((bad + 1))
        return
    fi
    # And against the tool's own output, so that a case where both are wrong
    # about the original would still be caught the other way round.
    $GZIP -dc "$WORK/c.gz" > "$WORK/oracle" 2>/dev/null
    cmp -s "$WORK/oracle" "$WORK/out" || {
        echo "FAIL $name -$level: the bytes differ from gzip -dc"
        bad=$((bad + 1))
    }
}

everyLevel() {
    for level in 1 6 9; do
        try "$1" "$2" "$level" "${3:-}"
    done
}

echo "-- shapes chosen by hand"

: > "$WORK/empty"
everyLevel empty "$WORK/empty"

printf 'x' > "$WORK/one"
everyLevel one-byte "$WORK/one"

# A long run of one byte, which is a back-reference with a distance of 1
# overlapping its own source -- the case a block copy gets wrong.
awk 'BEGIN { while (i++ < 40000) printf "a" }' > "$WORK/run"
everyLevel run-of-one "$WORK/run"

# Incompressible, which is what makes gzip emit a stored block.
dd if=/dev/urandom of="$WORK/random" bs=1024 count=64 2>/dev/null
everyLevel incompressible "$WORK/random"

# Longer than the 32 KB window, so distances reach the whole way back.
cat docs/REFERENCE.md docs/REFERENCE.md > "$WORK/twice"
everyLevel over-a-window "$WORK/twice"

# `-n` leaves the name and the modification time out of the header, so the two
# runs take different branches through the optional fields.
everyLevel no-name "$WORK/twice" -n

echo "-- the listing, which is where the ratio is not the obvious one"

# `-l` against `gzip -l`, line for line. The ratio BSD gzip prints is integer
# arithmetic with a floor at -99.9%, and nothing but the tool says so.
listing() {
    cases=$((cases + 1))
    $GZIP -9 -c "$1" > "$WORK/l.gz"
    if ! $VM "$SOB" -l "$WORK/l.gz" > "$WORK/ours" 2>/dev/null; then
        echo "FAIL listing $2: -l left non-zero"
        bad=$((bad + 1))
        return
    fi
    $GZIP -l "$WORK/l.gz" > "$WORK/theirs" 2>/dev/null
    cmp -s "$WORK/ours" "$WORK/theirs" || {
        echo "FAIL listing $2: -l differs from gzip -l"
        diff "$WORK/theirs" "$WORK/ours" | sed 's/^/    /'
        bad=$((bad + 1))
    }
}

listing "$WORK/empty" empty
listing "$WORK/one" one-byte
listing "$WORK/run" run-of-one
listing "$WORK/random" incompressible
listing "$WORK/twice" over-a-window
listing docs/REFERENCE.md a-real-file

echo "-- concatenated members"

cases=$((cases + 1))
$GZIP -9 -c "$WORK/one" > "$WORK/m1.gz"
$GZIP -9 -c "$WORK/run" > "$WORK/m2.gz"
cat "$WORK/m1.gz" "$WORK/m2.gz" > "$WORK/both.gz"
cat "$WORK/one" "$WORK/run" > "$WORK/both"
if $VM "$SOB" -dc "$WORK/both.gz" > "$WORK/out" 2>/dev/null && cmp -s "$WORK/both" "$WORK/out"; then
    :
else
    echo "FAIL concatenated members: cat a.gz b.gz did not come back as both"
    bad=$((bad + 1))
fi

echo "-- damage, which must be refused rather than survived"

# The last four bytes are the length; the four before them are the checksum.
cases=$((cases + 1))
$GZIP -9 -c "$WORK/twice" > "$WORK/dmg.gz"
size=$(wc -c < "$WORK/dmg.gz")
dd if="$WORK/dmg.gz" of="$WORK/bad.gz" bs=1 count=$((size - 5)) 2>/dev/null
printf '\377\377\377\377\377' >> "$WORK/bad.gz"
if $VM "$SOB" -t "$WORK/bad.gz" >/dev/null 2>&1; then
    echo "FAIL damaged trailer: -t said a damaged stream was fine"
    bad=$((bad + 1))
fi

cases=$((cases + 1))
printf 'this is not a gzip file at all\n' > "$WORK/plain.gz"
if $VM "$SOB" -t "$WORK/plain.gz" >/dev/null 2>&1; then
    echo "FAIL not a gzip file: -t accepted it"
    bad=$((bad + 1))
fi

echo "-- generated"

i=0
while [ $i -lt 6 ]; do
    i=$((i + 1))
    # Text-shaped rather than uniform: a generator that only ever produces
    # random bytes never produces a match, and the match finder is the half
    # this program has to read back.
    awk -v seed=$i 'BEGIN {
        srand(seed)
        words[0] = "the"; words[1] = "language"; words[2] = "a"
        words[3] = "program"; words[4] = "and"; words[5] = "window"
        n = int(rand() * 20000) + 100
        for (j = 0; j < n; j++) {
            printf "%s", words[int(rand() * 6)]
            printf (rand() < 0.12) ? "\n" : " "
        }
        printf "\n"
    }' > "$WORK/gen"
    everyLevel "generated-$i" "$WORK/gen"
done

echo "-- this repository's own files"

for f in README.md docs/ideas.md docs/REFERENCE.md programs/gzip.sol \
         bin/solvm lib/re.sol conformance/README.md; do
    [ -f "$f" ] || continue
    everyLevel "$f" "$f"
done

echo
if [ $bad -eq 0 ]; then
    echo "$cases cases, every one of them back to the byte"
    exit 0
fi
echo "$cases cases, $bad of them wrong"
exit 1
