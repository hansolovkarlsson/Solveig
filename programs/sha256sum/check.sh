#!/bin/sh
#
# check.sh -- sha256sum.sol's `-c` against /sbin/sha256sum's, on a directory of
# files that both of them read.
#
#     sh programs/sha256sum/check.sh
#
# **Checking a list is the half `programs/oracle.sh` cannot run.** That harness
# hands a program one input file and compares the bytes; `-c` needs a list whose
# lines name *other* files, which have to exist, with contents that decide the
# answer. So this builds a directory, writes lists against it, and runs both
# tools over each one.
#
# It compares standard output, standard error and the exit status **separately**,
# which is not fussiness: the two tools flush the two streams differently, so a
# run captured with `2>&1` interleaves them differently and would report a
# difference that is not one. That is written down at the bottom and shown,
# rather than being quietly avoided here.
#
# Two lists, in the shape programs/oracle.sh uses: `same` must match, and
# `differ` must not, with the reason in the case itself.

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

cd "$work" || exit 1
printf 'hello\n'                  > one.txt
printf 'world\n'                  > two.txt
printf 'no newline at the end'    > three.txt
printf ''                         > empty.txt
printf 'spaces in the name\n'     > 'a name with spaces.txt'

$oracle one.txt two.txt three.txt empty.txt > good.sums
$oracle 'a name with spaces.txt'            > spaces.sums
$oracle -b one.txt                          > binary.sums

# One wrong digit in the first digest, and nothing else touched.
awk 'NR == 1 { $0 = ($0 ~ /^f/ ? "0" : "f") substr($0, 2) } { print }' \
    good.sums > one-wrong.sums
awk '{ $0 = ($0 ~ /^f/ ? "0" : "f") substr($0, 2); print }' \
    good.sums > all-wrong.sums

awk '{ print toupper(substr($0, 1, 64)) substr($0, 65) }' good.sums > upper.sums
printf 'this is not a checksum line\n'                          > malformed.sums
head -2 good.sums > mixed.sums
printf 'this is not a checksum line\n' >> mixed.sums
printf '%s  nosuch.txt\n' \
    0000000000000000000000000000000000000000000000000000000000000000 > missing.sums
printf '' > blank.sums
printf '\n\n\n' > only-blanks.sums

# A blank line between two good ones. This is the case that found the defect
# this script exists to find: the first draft dropped every empty piece of the
# split and reported nothing, where the oracle numbers the blank line and
# counts it. `-w` is what makes the number visible.
{ head -1 good.sums; printf '\n'; tail -1 good.sums; } > blank-inside.sums

# A list written with -z, whose entries end in a NUL rather than a newline. One
# entry reads; several do not, in both tools, because both read a list by lines
# and a NUL is not one. The case is here because the *first* draft of this
# program silently answered OK about the right file under a mangled name: a
# Solum string may hold a NUL and a Unix path may not, so everything after the
# first name was carried into `fileExists` and thrown away by C.
$oracle -z one.txt              > z-one.sums
$oracle -z one.txt two.txt      > z-many.sums

bad=0
ok=0

compare() {
    label=$1
    shift
    "$oracle" "$@" > o.out 2> o.err; ostatus=$?
    # shellcheck disable=SC2086
    $sol "$@" > s.out 2> s.err; sstatus=$?

    if cmp -s o.out s.out && cmp -s o.err s.err && [ "$ostatus" = "$sstatus" ]; then
        printf '  same      %s\n' "$label"
        ok=$((ok + 1))
        return 0
    fi
    printf '  DIFFERS   %s\n' "$label"
    [ "$ostatus" = "$sstatus" ] || \
        printf '            status: oracle %s, ours %s\n' "$ostatus" "$sstatus"
    cmp -s o.out s.out || diff -u o.out s.out | sed -e '1,2d' -e 's/^/            out /'
    cmp -s o.err s.err || diff -u o.err s.err | sed -e '1,2d' -e 's/^/            err /'
    bad=$((bad + 1))
    return 1
}

echo
echo "-c, against $oracle"
echo

echo "same -- these must match on stdout, stderr and status"
compare "four files, all of them right"        -c good.sums
compare "a name with spaces in it"             -c spaces.sums
compare "a list written with -b"               -c binary.sums
compare "one of four wrong -- singular WARNING" -c one-wrong.sums
compare "all four wrong -- plural WARNING"     -c all-wrong.sums
compare "digests in upper case"                -c upper.sums
compare "a line that is not a checksum line"   -c malformed.sums
compare "the same, with -w"                    -c -w malformed.sums
compare "two good lines and one that is not"   -c mixed.sums
compare "an empty list"                        -c blank.sums
compare "a list of blank lines"                -c only-blanks.sums
compare "a blank line between two good ones"   -c blank-inside.sums
compare "the same, with -w and its line number" -c -w blank-inside.sums
compare "a list that is not there"             -c nosuch.sums
compare "a -z list of one entry"               -c z-one.sums
compare "a -z list of several, which is one line to both" -c z-many.sums

echo
echo "differ -- these must not, and here is why"

# The counters belong to the `same` list; this case is expected to differ, so
# whichever one `compare` moved is moved back.
if compare "a list naming a file that is gone" -c missing.sums; then
    ok=$((ok - 1))
    printf '  AGREES    the divergence has gone, and this file still claims it\n'
    bad=$((bad + 1))
else
    bad=$((bad - 1))
    cat <<'WHY'
            The oracle writes `sha256sum:  nosuch.txt: ...` with two spaces,
            having kept the separator that stood in front of the name in the
            list. This writes one. Copying that would be copying a defect to
            match bytes, so it is recorded here instead.
WHY
fi

echo
echo "and one difference that is not a difference:"
$oracle -c all-wrong.sums > /dev/null 2>&1
{ $oracle -c all-wrong.sums; } > merged-oracle.out 2>&1
# shellcheck disable=SC2086
{ $sol -c all-wrong.sums; } > merged-ours.out 2>&1
if cmp -s merged-oracle.out merged-ours.out; then
    echo "  the two streams interleave the same way when merged."
else
    cat <<'WHY'
  Captured with 2>&1 the two tools order the WARNING and the per-file lines
  differently: the oracle's standard output is block-buffered when it is a file,
  so its FAILED lines arrive at exit, after the unbuffered warning. Both streams
  are byte-identical when they are kept apart, which is how the checks above
  read them, and neither tool is wrong. It is recorded because a harness that
  merged the streams -- programs/oracle.sh does -- would call it a defect.
WHY
fi

echo
if [ "$bad" -eq 0 ]; then
    echo "$ok agree, and the one divergence is still there: nothing new."
    exit 0
fi
echo "$bad to look at."
exit 1
