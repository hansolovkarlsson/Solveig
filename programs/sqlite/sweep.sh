#!/bin/sh
#
# sweep.sh -- sqlite.sol against the sqlite3 on the machine, over files it made.
#
#     sh programs/sqlite/sweep.sh              # author cases, and 200 generated
#     sh programs/sqlite/sweep.sh 1000         # more generated
#     sh programs/sqlite/sweep.sh keep DIR     # build the corpus into DIR and stop
#
# **The oracle produces every input.** Each case is a SQL script: the
# statements above `-- queries` are given to sqlite3, which builds the
# database file, and the statements below it are run over that file by both
# sqlite3 and this program, and the bytes compared. So a disagreement cannot
# be about what an input meant; sqlite3 wrote the file, and sqlite3 says what
# the file says. This is the shape gzip's sweep has, and it is the strongest
# an oracle check here takes.
#
# Three rungs, in the order method.md puts them:
#
#   author     cases/*.sql, one shape each, chosen because it exercises a path:
#              an empty table, every storage class, every integer width, a
#              leaf one row short of full and the tree that split, three
#              levels, indexes with ties, overflow chains, a freelist, the
#              65536-byte page that is spelled 1. Each file's comment says
#              what it makes, and inspect.py in the scratch confirmed it does.
#   generated  generate.py from a seed: several tables, chosen and assigned
#              rowids, every storage class in every column, deletes, four
#              page sizes. Reproduced by name.
#   real       files somebody made for their own reasons, named in
#              SQLITE_REAL as a space-separated list; none is given by default,
#              since a database on this machine is somebody's data. Every
#              table in each is read whole.
#
# `keep DIR` is for looking at the corpus while writing the reader: the .sql,
# the .db it became and the .q.sql that will be run over it, and nothing is
# compared. It was the first mode written, at step 0 of the plan in ideas.md,
# before there was a program to compare.
#
# What is compared is standard output, standard error and the exit status, on
# both sides, from the same query file on standard input; sqlite3's default
# `list` mode with `|` between columns and nothing for NULL is what the
# program prints. One flag: `-escape off`, because since 3.47 the shell shows
# a control character as `^M` to protect the terminal, and that is the
# terminal's business rather than the file's. With it off the bytes are the
# bytes, and a blob still stops at its first NUL, which is the shell's `%s`
# and is what the program does too. It leaves 1 if anything disagreed, and
# says what.

set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1

LC_ALL=C
export LC_ALL

SQLITE=${SQLITE_TOOL:-/usr/bin/sqlite3}
if [ ! -x "$SQLITE" ]; then
    echo "no sqlite3 at $SQLITE"
    exit 2
fi

keep=
count=200
if [ "${1:-}" = "keep" ]; then
    keep=${2:?keep needs a directory}
    mkdir -p "$keep" || exit 2
    work=$keep
else
    count=${1:-200}
    if [ ! -f bin/solvm ] || [ ! -f programs/sqlite.sob ]; then
        echo "build first:  make && ./bin/solas programs/sqlite.sol"
        exit 2
    fi
    work=$(mktemp -d "${TMPDIR:-/tmp}/sqlite-sweep.XXXXXX")
    trap 'rm -rf "$work"' EXIT INT TERM
fi

ours="./bin/solvm programs/sqlite.sob"
cases=0
bad=0

# One script: split it, have sqlite3 build the file, then run the queries on
# both sides.
prepare() {
    # $1 is the script, $2 the name to build under.
    sed '/^-- queries$/,$d' "$1" > "$work/$2.build.sql"
    sed -n '/^-- queries$/,$p' "$1" | sed '1d' > "$work/$2.q.sql"
    rm -f "$work/$2.db"
    if ! "$SQLITE" -batch "$work/$2.db" < "$work/$2.build.sql" 2> "$work/$2.build.err"; then
        echo "  sqlite3 refused to build $2:"
        sed 's/^/           /' "$work/$2.build.err" | head -3
        return 1
    fi
}

compare() {
    # $1 is the case name; $work/$1.db and $work/$1.q.sql exist.
    "$SQLITE" -batch -escape off "$work/$1.db" < "$work/$1.q.sql" > "$work/o.out" 2> "$work/o.err"
    ostatus=$?
    $ours "$work/$1.db" < "$work/$1.q.sql" > "$work/m.out" 2> "$work/m.err"
    mstatus=$?

    cases=$((cases + 1))
    if ! cmp -s "$work/o.out" "$work/m.out" \
        || ! cmp -s "$work/o.err" "$work/m.err" \
        || [ "$ostatus" -ne "$mstatus" ]; then
        bad=$((bad + 1))
        if [ "$bad" -le 5 ]; then
            printf '  DIFFERS  %s  exit %s against %s\n' "$1" "$mstatus" "$ostatus"
            diff -u "$work/o.out" "$work/m.out" | sed -e '1,2d' -e 's/^/           /' | head -10
            diff -u "$work/o.err" "$work/m.err" | sed -e '1,2d' -e 's/^/           /' | head -4
        fi
    fi
}

run_case() {
    # $1 is the script, $2 the name.
    prepare "$1" "$2" || { bad=$((bad + 1)); return; }
    [ -n "$keep" ] || compare "$2"
}

echo
if [ -n "$keep" ]; then
    echo "building the corpus into $keep"
else
    echo "$SQLITE against programs/sqlite.sob, LC_ALL=C"
fi
echo

# ---------------------------------------------------------------------------
# Author

n=0
for f in programs/sqlite/cases/*.sql; do
    n=$((n + 1))
    run_case "$f" "$(basename "$f" .sql)"
done
echo "  author:    $n cases"

# ---------------------------------------------------------------------------
# Generated
#
# **A redirect rather than a pipe, and this is not style**: a loop fed by a
# pipe runs in a subshell, and every disagreement it counts is lost when the
# subshell exits. sort/sweep.sh shipped that once and says so.

seed=${SQLITE_SEED:-1}
python3 programs/sqlite/generate.py "$work" "$seed" "$count" || exit 2
while IFS= read -r f; do
    run_case "$f" "$(basename "$f" .sql)"
done <<GEN
$(ls "$work"/gen-"$seed"-*.sql)
GEN
echo "  generated: $count cases, seed $seed"

# ---------------------------------------------------------------------------
# Real

n=0
for db in ${SQLITE_REAL:-}; do
    [ -f "$db" ] || continue
    n=$((n + 1))
    name="real-$(basename "$db")"
    cp "$db" "$work/$name.db"
    "$SQLITE" -batch "$work/$name.db" "select name from sqlite_schema where type = 'table'" \
        | sed 's/.*/SELECT * FROM "&";/' > "$work/$name.q.sql"
    [ -n "$keep" ] || compare "$name"
done
if [ "$n" -eq 0 ]; then
    echo "  real:      none given (SQLITE_REAL=\"a.db b.db\")"
else
    echo "  real:      $n files, every table whole"
fi

echo
if [ -n "$keep" ]; then
    ls "$work"/*.db | wc -l | sed 's/^ *//; s/$/ databases, with their .build.sql and .q.sql/'
    exit 0
fi
if [ "$bad" -eq 0 ]; then
    echo "  $cases cases, all agree"
else
    echo "  $cases cases, $bad DIFFER"
    exit 1
fi
