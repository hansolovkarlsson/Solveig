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

# **And that it is not the last build.** A `.sob` older than its source runs the
# program as it was, and the difference arrives here as a scenario that DIFFERS
# -- which reads as a fault in the code and is a fault in the build. That cost a
# wrong diagnosis on 2026-09-01, on the first run of a scenario written the same
# minute. `*.sob` is not tracked, so nothing else would catch it.
if [ "$root/programs/tail.sol" -nt "$root/programs/tail.sob" ]; then
    echo "programs/tail.sob is older than tail.sol -- rebuild:"
    echo "  ./bin/solas programs/tail.sol"
    exit 1
fi

settle=1.4          # longer than the oracle's one-second look
same=0
news=0

# Runs one scenario under both tails. $1 names it, $2 is the flags before the
# files, $3 is a shell fragment that writes to them while both are watching, and
# $4 -- optional -- is different flags for the oracle.
#
# **The fourth argument exists because this tail's `-f` is the oracle's `-F`.**
# BSD's `-f` follows the **descriptor**: after a rename it goes on reading the
# renamed file, which `lsof` shows it holding open. This one has only a path to
# poll, so it follows the **name**, which is `-F`'s behaviour and cannot be
# anything else without an open file to keep. Comparing our `-f` against the
# oracle's `-F` for the two rotation scenarios says what is actually claimed;
# comparing it against `-f` and calling the difference expected would not.
scenario() {
    what=$1; flags=$2; script=$3; theirs=${4:-$2}

    for side in oracle ours; do
        rm -rf "$work/run"; mkdir -p "$work/run"
        ( cd "$work/run" && eval "$setup" )

        if [ "$side" = oracle ]; then
            ( cd "$work/run" && eval "$oracle $theirs $files" ) \
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

# The two that were unwritable until a path could be absent without raising.
# Both of these ended the run with `cannot measure` and status 1 before
# ROADMAP 6.41, which is worse than not following a rotation: it is not
# surviving one.

# Both against the oracle's -F, for the reason given at scenario() above. The
# first of these is also the scenario that caught a throwaway measurement of the
# oracle claiming BSD's -f follows the name: run side by side under one harness
# it does not, and `lsof` on the running process settled it.
setup='printf "a\n" > one.txt'
files='one.txt'
scenario "a rotation: renamed away, and a new file at the path" "-f -n 1" \
    'mv one.txt one.txt.1; sleep 0.4; printf "OLD\n" >> one.txt.1;
     sleep 0.4; printf "NEW\n" > one.txt' "-F -n 1"

setup='printf "a\n" > one.txt'
files='one.txt'
scenario "a removal, and the same path created again later" "-f -n 1" \
    'rm one.txt; sleep 0.6; printf "BACK\n" > one.txt' "-F -n 1"

# The one size cannot see. The replacement is written to the *same length* as
# the file it replaces, so every question that could be asked before 6.39 --
# fileSize, modifiedAt -- answers "unchanged", and the next growth was printed
# from an offset into a file that no longer had one. That lost the middle line
# silently: the oracle printed three and this printed two.
setup='printf "AAAA\n" > one.txt'
files='one.txt'
scenario "a replacement of exactly the same size" "-f -n 1" \
    'mv one.txt one.txt.1; printf "BBBB\n" > one.txt;
     sleep 0.6; printf "CCCC\n" >> one.txt' "-F -n 1"

echo
if [ "$news" -eq 0 ]; then
    echo "$same scenarios agree: nothing new."
    exit 0
fi
echo "$news to look at."
exit 1
