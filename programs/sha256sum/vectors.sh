#!/bin/sh
#
# vectors.sh -- sha256sum.sol against the numbers printed in the standard, and
# against the oracle on the bytes a .case file cannot carry.
#
#     sh programs/sha256sum/vectors.sh
#
# **This is the check `sed` and `tail` could not have.** Their only outside
# authority was another implementation, and an oracle can be wrong in the same
# direction as anything derived from it. SHA-256 has published answers: the
# digests below are copied from FIPS 180-4 and from NIST's example pages, they
# were printed before this language existed, and nothing about them can have
# been influenced by what this program does.
#
# So the first half compares against a constant and the second against
# /sbin/sha256sum, and the two halves fail for different reasons -- a wrong
# constant means the algorithm is wrong, and a difference from the oracle on
# these inputs means the *plumbing* is: a NUL lost, a high byte sign-extended,
# a chunk boundary landing in the middle of a block.
#
# Not run by `make test`, which is true of every oracle here: it wants a tool
# that happens to be installed. `sh programs/oracle.sh sha256sum` is the corpus;
# this is what the corpus cannot express.

set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
sol="$root/bin/solvm $root/programs/sha256sum.sob"
oracle=${ORACLE:-/sbin/sha256sum}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if [ ! -f "$root/programs/sha256sum.sob" ]; then
    echo "build first:  make && ./bin/solas programs/sha256sum.sol"
    exit 1
fi

bad=0
ok=0

# ---------------------------------------------------------------------------
# The published vectors. Each is fed on standard input, which is also the route
# that has to be byte-exact -- a program reading a pipe by lines would get the
# empty message and the 56-byte one wrong and nothing else.

vector() {
    want=$1
    what=$2
    got=$($sol - < "$work/in" | awk '{ print $1 }')
    if [ "$got" = "$want" ]; then
        printf '  same      %s\n' "$what"
        ok=$((ok + 1))
    else
        printf '  DIFFERS   %s\n'   "$what"
        printf '            want: %s\n' "$want"
        printf '            got:  %s\n' "$got"
        bad=$((bad + 1))
    fi
}

echo
echo "FIPS 180-4 and NIST, against numbers printed before this language existed"
echo

printf '' > "$work/in"
vector e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 \
    "the empty message"

printf 'abc' > "$work/in"
vector ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad \
    "abc -- one block, FIPS 180-4 appendix B.1"

printf 'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq' > "$work/in"
vector 248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1 \
    "448 bits -- two blocks, appendix B.2"

printf '%s' \
'abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu' \
    > "$work/in"
vector cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1 \
    "896 bits -- the longer NIST example"

awk 'BEGIN { while (i++ < 1000000) printf "a" }' > "$work/in"
vector cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0 \
    "one million times 'a' -- the stress vector, and a megabyte of arithmetic"

# ---------------------------------------------------------------------------
# What a .case file cannot hold.
#
# A case file is a text file read by awk, so it cannot carry a NUL and it should
# not carry seventy kilobytes. Both matter here: NUL is a byte like any other to
# a checksum and is where a program that treats a string as a C string fails,
# and 65536 is this program's chunk size, so a file either side of it is where a
# block split across two reads would show.

against_oracle() {
    what=$1
    want=$($oracle "$work/in" | awk '{ print $1 }')
    got=$($sol "$work/in" | awk '{ print $1 }')
    pipe=$($sol - < "$work/in" | awk '{ print $1 }')
    if [ "$got" = "$want" ] && [ "$pipe" = "$want" ]; then
        printf '  same      %s\n' "$what"
        ok=$((ok + 1))
    else
        printf '  DIFFERS   %s\n' "$what"
        printf '            oracle: %s\n' "$want"
        printf '            file:   %s\n' "$got"
        printf '            pipe:   %s\n' "$pipe"
        bad=$((bad + 1))
    fi
}

echo
echo "against $oracle, on bytes and sizes a .case file cannot carry"
echo

# Every byte value once, in order, so a sign-extended byte or a lost NUL is a
# different digest rather than a rare one.
awk 'BEGIN { for (i = 0; i < 256; i++) printf "%c", i }' > "$work/in"
against_oracle "all 256 byte values, NUL first"

awk 'BEGIN { while (i++ < 400) printf "%c%c%c%c%c", 0, 0, 0, 0, 0 }' > "$work/in"
against_oracle "two thousand NULs and nothing else"

for n in 65535 65536 65537 200000; do
    awk -v n="$n" 'BEGIN { while (i++ < n) printf "%c", 65 + (i % 26) }' > "$work/in"
    against_oracle "$n bytes -- the chunk is 65536"
done

# ---------------------------------------------------------------------------

echo
if [ "$bad" -eq 0 ]; then
    echo "$ok checks, all of them agreeing with something written elsewhere."
    exit 0
fi
echo "$bad to look at."
exit 1
