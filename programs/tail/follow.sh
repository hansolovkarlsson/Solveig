#!/bin/sh
#
# follow.sh -- `tail -f` against the tail on the machine.
#
# **The corpus harness cannot check this and that is not a reason to leave it
# unchecked.** programs/oracle.sh runs a program and compares what it wrote;
# `-f` never stops, so there is nothing to wait for and nothing to compare. What
# it needs instead is a deadline: start both, feed the file on a schedule, stop
# them, and compare what each had managed to write.
#
# That is what this is, and it is separate from oracle.sh rather than an option
# on it because the two are different shapes -- one is a corpus of cases and
# this is a handful of scenarios with timing in them.
#
# **stdout only.** BSD tail restarts silently when a file is truncated and GNU
# tail says so; this one says so on **standard error**, which is what that
# stream is for -- a diagnostic about producing the output rather than part of
# it. So the bytes that matter are stdout's, and they must agree exactly.
#
# **The oracle sets the pace.** BSD tail has no `-s` and looks once a second, so
# every stage here waits longer than that. This one is run with `-s 0.1`, which
# changes when it notices and not what it writes.
#
#   ORACLE    the tail to compare against; /usr/bin/tail by default.

set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
oracle=${ORACLE:-/usr/bin/tail}
ours="$root/bin/solvm $root/programs/tail.sob"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if [ ! -f "$root/programs/tail.sob" ]; then
    echo "build first:  make && ./bin/solas programs/tail.sol"
    exit 1
fi

settle=1.4          # longer than the oracle's one-second look
same=0
news=0

# Runs one scenario under both tails. $1 names it, $2 is the flags before the
# files, $3 is a shell fragment that writes to them while both are watching.
scenario() {
    what=$1; flags=$2; script=$3

    for side in oracle ours; do
        rm -rf "$work/run"; mkdir -p "$work/run"
        ( cd "$work/run" && eval "$setup" )

        if [ "$side" = oracle ]; then
            ( cd "$work/run" && eval "$oracle $flags $files" ) \
                > "$work/$side.out" 2> "$work/$side.err" &
        else
            ( cd "$work/run" && eval "$ours -s 0.1 $flags $files" ) \
                > "$work/$side.out" 2> "$work/$side.err" &
        fi
        watcher=$!

        sleep "$settle"
        ( cd "$work/run" && eval "$script" )
        sleep "$settle"

        kill "$watcher" 2>/dev/null
        wait "$watcher" 2>/dev/null
    done

    if cmp -s "$work/oracle.out" "$work/ours.out"; then
        printf '  same      %s\n' "$what"
        same=$((same + 1))
    else
        printf '  DIFFERS   %s\n' "$what"
        diff -u "$work/oracle.out" "$work/ours.out" \
            | sed -e '1,2d' -e 's/^/            /'
        news=$((news + 1))
    fi
}

echo
echo "tail -f against $oracle"
echo

setup='printf "a\nb\nc\n" > one.txt'
files='one.txt'
scenario "what is appended arrives" "-f -n 1" \
    'printf "d\ne\n" >> one.txt; sleep 0.4; printf "f\n" >> one.txt'

setup='printf "a\nb\nc\n" > one.txt'
files='one.txt'
scenario "a file truncated and written again starts over" "-f -n 1" \
    'printf "d\n" >> one.txt; sleep 0.4; : > one.txt; printf "x\ny\n" >> one.txt'

setup='printf "" > one.txt'
files='one.txt'
scenario "a file that is empty when the watching starts" "-f -n 3" \
    'printf "first\nsecond\n" >> one.txt'

setup='printf "a\n" > one.txt; printf "b\n" > two.txt'
files='one.txt two.txt'
scenario "two files, and the heading follows the writing" "-f -n 1" \
    'printf "one-1\n" >> one.txt; sleep 0.4; printf "two-1\n" >> two.txt;
     sleep 0.4; printf "one-2\n" >> one.txt'

setup='printf "a\nb\n" > one.txt'
files='one.txt'
scenario "nothing is appended at all" "-f -n 2" 'true'

setup='printf "a\nb\n" > one.txt'
files='one.txt'
scenario "-v -f puts a blank line before the first heading too" "-v -f -n 1" \
    'printf "c\n" >> one.txt'

echo
if [ "$news" -eq 0 ]; then
    echo "$same scenarios agree: nothing new."
    exit 0
fi
echo "$news to look at."
exit 1
