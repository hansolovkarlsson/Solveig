#!/bin/sh
#
# check.sh -- the rung of the sqlite sweep that `make test` can carry: the
#             program writes each database from its script and reads it back,
#             and the answer is held against what sqlite3 said once.
#
#     sh programs/sql/check.sh              # every case with an .expected
#     sh programs/sql/check.sh record       # write the .expected files, with sqlite3
#
# `make test` needs nothing outside C11 and `make`, and sweep.sh needs two
# things outside them: sqlite3, which builds every database and judges every
# file, and python3, which generates two hundred cases a seed. So the sweep
# stays beside the suite, as gzip's and sed's do, and this is what the suite
# gets: the author cases the writer takes, each built by this program from
# the statements above `-- queries` and then read by this program with the
# statements below it, the output diffed against `cases/<name>.expected`,
# which `record` wrote from sqlite3's answer over sqlite3's own file. The
# oracle's answer is frozen in the tree; the oracle is not needed to check
# against it.
#
# What this does not check, and the sweep does: `PRAGMA integrity_check`
# over the file this program wrote, sqlite3 reading that file, the six
# author shapes marked `-- writer: skip` (an overflow chain, a freelist,
# three levels, the indexes with ties, the page size spelled 1, several
# tables), and any generated case. A writer and a reader that are wrong in
# the same way pass here and fail there, which is what the sweep is for.
#
# It leaves 1 if any case differs, and says which.

set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1

LC_ALL=C
export LC_ALL

ours="./bin/solvm programs/sql.sob"
cases=programs/sql/cases

if [ "${1:-}" = "record" ]; then
    SQLITE=${SQLITE_TOOL:-/usr/bin/sqlite3}
    [ -x "$SQLITE" ] || { echo "no sqlite3 at $SQLITE"; exit 2; }
elif [ ! -f bin/solvm ] || [ ! -f programs/sql.sob ]; then
    echo "build first:  make programs/sql.sob"
    exit 2
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/sqlite-check.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM

n=0
bad=0
for f in "$cases"/*.sql; do
    grep -q '^-- writer: skip' "$f" && continue
    name=$(basename "$f" .sql)
    sed '/^-- queries$/,$d' "$f" > "$work/build.sql"
    sed -n '/^-- queries$/,$p' "$f" | sed '1d' > "$work/q.sql"
    if [ "${1:-}" = "record" ]; then
        rm -f "$work/o.db"
        "$SQLITE" -batch "$work/o.db" < "$work/build.sql" || exit 2
        "$SQLITE" -batch -escape off "$work/o.db" < "$work/q.sql" > "$cases/$name.expected" || exit 2
        n=$((n + 1))
        continue
    fi
    [ -f "$cases/$name.expected" ] || continue
    n=$((n + 1))
    rm -f "$work/w.db"
    if ! $ours "$work/w.db" < "$work/build.sql" > "$work/w.out" 2>&1 \
        || ! $ours "$work/w.db" < "$work/q.sql" > "$work/m.out" 2>&1 \
        || ! cmp -s "$cases/$name.expected" "$work/m.out"; then
        bad=$((bad + 1))
        printf '  DIFFERS  %s\n' "$name"
        sed 's/^/           /' "$work/w.out" | head -3
        diff -u "$cases/$name.expected" "$work/m.out" | sed -e '1,2d' -e 's/^/           /' | head -10
    fi
done

if [ "${1:-}" = "record" ]; then
    echo "  $n expected files written by $SQLITE"
    exit 0
fi
if [ "$bad" -eq 0 ]; then
    echo "  sqlite: $n cases written and read back agree with what sqlite3 said"
else
    echo "  sqlite: $n cases, $bad DIFFER"
    exit 1
fi
