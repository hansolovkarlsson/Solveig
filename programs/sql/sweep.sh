#!/bin/sh
#
# sweep.sh -- sql.sol, the shell over lib/sqlite.sol, against the sqlite3 on
#             the machine, over files it made, and then over files sql.sol made.
#
#     sh programs/sql/sweep.sh              # author cases, and 200 generated
#     sh programs/sql/sweep.sh 1000         # more generated
#     sh programs/sql/sweep.sh keep DIR     # build the corpus into DIR and stop
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
# And then the writer, steps 3 and 4 of the plan, over the same shapes the
# other way round: the program builds the database from the script, or takes
# over a database sqlite3 built from the first half of it, and sqlite3 judges
# the file. Three checks a case, each stricter than the reader's:
#
#   integrity  `PRAGMA integrity_check` over the file this program wrote
#              answers `ok`, which is SQLite's own account of whether the
#              trees, cells and pages are well formed.
#   sqlite3    the queries run by sqlite3 over this program's file answer
#              the same bytes as sqlite3 over its own file from the same
#              script. Two writers, one reader, one answer.
#   itself     the queries run by this program over its own file agree too.
#
# The writer takes the author cases without a `-- writer: skip` line (the
# line says why: WITH RECURSIVE, DELETE, UNIQUE, overflow) and its own
# generated rung, `generate.py ... writable`, which keeps inside the writer's
# scope and puts more rows on the small pages so the splits reach three
# levels. Root page numbers differ between two writers, so no query here
# asks for one.
#
# None of this is in `make test`, which needs nothing outside C11 and `make`
# and this needs sqlite3 and python3. check.sh beside this is the rung the
# suite carries: the writable author cases written and read back by the
# program, held against sqlite3's answer recorded once.
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
    if [ ! -f bin/solvm ] || [ ! -f programs/sql.sob ]; then
        echo "build first:  make && ./bin/solas programs/sql.sol"
        exit 2
    fi
    work=$(mktemp -d "${TMPDIR:-/tmp}/sqlite-sweep.XXXXXX")
    trap 'rm -rf "$work"' EXIT INT TERM
fi

ours="./bin/solvm programs/sql.sob"
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
    echo "$SQLITE against programs/sql.sob, LC_ALL=C"
fi
echo

# ---------------------------------------------------------------------------
# Author

n=0
for f in programs/sql/cases/*.sql; do
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
python3 programs/sql/generate.py "$work" "$seed" "$count" || exit 2
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

# ---------------------------------------------------------------------------
# The writer

ourPages=0
theirPages=0

# Judge a file this program wrote or changed: $1 the case name, $2 the file,
# $3 a word for the report. sqlite3's own file from the whole script is
# $work/$1.db and is the reference.
judge() {
    check=$("$SQLITE" -batch "$2" 'PRAGMA integrity_check' 2>&1)
    cases=$((cases + 1))
    if [ "$check" != "ok" ]; then
        bad=$((bad + 1))
        [ "$bad" -le 5 ] && { printf '  MALFORMED  %s (%s)\n' "$1" "$3"; printf '%s\n' "$check" | sed 's/^/           /' | head -6; }
        return
    fi
    "$SQLITE" -batch -escape off "$work/$1.db" < "$work/$1.q.sql" > "$work/o.out" 2> "$work/o.err"
    "$SQLITE" -batch -escape off "$2" < "$work/$1.q.sql" > "$work/t.out" 2> "$work/t.err"
    $ours "$2" < "$work/$1.q.sql" > "$work/m.out" 2> "$work/m.err"
    if ! cmp -s "$work/o.out" "$work/t.out" || ! cmp -s "$work/o.err" "$work/t.err"; then
        bad=$((bad + 1))
        [ "$bad" -le 5 ] && { printf '  DIFFERS  %s (%s, sqlite3 over the file)\n' "$1" "$3"
            diff -u "$work/o.out" "$work/t.out" | sed -e '1,2d' -e 's/^/           /' | head -10; }
        return
    fi
    if ! cmp -s "$work/o.out" "$work/m.out" || ! cmp -s "$work/o.err" "$work/m.err"; then
        bad=$((bad + 1))
        [ "$bad" -le 5 ] && { printf '  DIFFERS  %s (%s, this program over the file)\n' "$1" "$3"
            diff -u "$work/o.out" "$work/m.out" | sed -e '1,2d' -e 's/^/           /' | head -10; }
        return
    fi
    ourPages=$((ourPages + $("$SQLITE" "$2" 'PRAGMA page_count')))
    theirPages=$((theirPages + $("$SQLITE" "$work/$1.db" 'PRAGMA page_count')))
}

# From nothing: this program builds $work/$1.w.db from the whole script.
write_case() {
    rm -f "$work/$1.w.db"
    if ! $ours "$work/$1.w.db" < "$work/$1.build.sql" > "$work/w.out" 2> "$work/w.err"; then
        cases=$((cases + 1)); bad=$((bad + 1))
        [ "$bad" -le 5 ] && { printf '  REFUSED  %s (writing)\n' "$1"; sed 's/^/           /' "$work/w.err" | head -3; }
        return
    fi
    judge "$1" "$work/$1.w.db" "written"
}

# Into a file that exists, which is step 4 of the plan: sqlite3 runs the
# first half of the statements into $work/$1.h.db and this program runs the
# second half into the same file, so its pages, header and schema were
# sqlite3's before they were changed here. The split is after the middle
# statement; a statement is a line ending in `;` in every writable case.
# The second half may hold a CREATE, so the schema page changes too.
existing_case() {
    total=$(grep -c ';$' "$work/$1.build.sql")
    [ "$total" -ge 2 ] || return
    k=$((total / 2))
    awk -v k="$k" '{ print; if (/;$/) { n++; if (n == k) exit } }' "$work/$1.build.sql" > "$work/$1.h1.sql"
    awk -v k="$k" 'done { print; next } /;$/ { n++; if (n == k) done = 1 }' "$work/$1.build.sql" > "$work/$1.h2.sql"
    rm -f "$work/$1.h.db"
    "$SQLITE" -batch "$work/$1.h.db" < "$work/$1.h1.sql" 2> /dev/null || return
    if ! $ours "$work/$1.h.db" < "$work/$1.h2.sql" > "$work/w.out" 2> "$work/w.err"; then
        cases=$((cases + 1)); bad=$((bad + 1))
        [ "$bad" -le 5 ] && { printf '  REFUSED  %s (into an existing file)\n' "$1"; sed 's/^/           /' "$work/w.err" | head -3; }
        return
    fi
    judge "$1" "$work/$1.h.db" "into an existing file"
}

if [ -z "$keep" ]; then
    echo
    echo "the writer, judged by $SQLITE"
    echo
    n=0
    for f in programs/sql/cases/*.sql; do
        grep -q '^-- writer: skip' "$f" && continue
        n=$((n + 1))
        write_case "$(basename "$f" .sql)"
        existing_case "$(basename "$f" .sql)"
    done
    echo "  author:    $n cases, from nothing and into a file sqlite3 began"
    python3 programs/sql/generate.py "$work" "$seed" "$count" writable || exit 2
    while IFS= read -r f; do
        name=$(basename "$f" .sql)
        prepare "$f" "$name" || { bad=$((bad + 1)); continue; }
        write_case "$name"
        existing_case "$name"
    done <<GEN
$(ls "$work"/gen-w-"$seed"-*.sql)
GEN
    echo "  generated: $count cases, seed $seed, both ways"
    if [ "$theirPages" -gt 0 ]; then
        echo "  pages:     $ourPages written here against $theirPages by sqlite3, over the cases that agreed"
    fi
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
