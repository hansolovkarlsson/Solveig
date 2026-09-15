#!/usr/bin/env python3
#
# generate.py -- SQL scripts nobody chose, for sweep.sh to hand to sqlite3.
#
#     python3 programs/sqlite/generate.py DIR SEED COUNT
#     python3 programs/sqlite/generate.py DIR SEED COUNT writable
#
# Writes DIR/gen-SEED-0001.sql and so on, each in the shape of the files in
# cases/: statements that build a database, a line `-- queries`, and then
# statements to run on both sides. Everything is drawn from one seeded
# generator, so a case that disagreed is reproduced by its name.
#
# `writable` keeps the build inside what sqlite.sol's writer does: no row or
# index entry long enough to need an overflow page, and in exchange more rows
# on the small page sizes, so that the writer's splits reach three levels and
# a DELETE empties pages. The files are named gen-w-SEED-0001.sql.
#
# This is the second of the three authors method.md names. The cases beside it
# are what one person thought of; a generator produces what it was told it
# could produce, and no more, so what it is told is the whole of its worth.
# It is told: several tables, a chosen or an assigned rowid, every storage
# class in every column since a column's declared type is advice, integers at
# every width the record format has, reals that need fifteen digits, texts
# that are empty or hold the list separator or a newline or are longer than a
# page, indexes with many ties, deletes that empty pages, and page sizes small
# enough that a few hundred rows make an interior page. What it is not told is
# anything about the SQL the program does not parse.
#
# Rows are inserted one statement each rather than in a VALUES list, so a
# generated script is also a script the program's own writer can be handed
# at step 3 and compared statement for statement.

import random
import sys


def sql_text(s):
    return "'" + s.replace("'", "''") + "'"


def sql_blob(bs):
    return "X'" + bs.hex().upper() + "'"


def fifteen(x):
    # A real literal with at most fifteen significant digits, kept a real:
    # '%.15g' of 123456.0 is '123456', which SQL reads as an integer.
    s = '%.15g' % x
    if not any(c in s for c in '.en'):
        s += '.0'
    return s


class Gen:
    def __init__(self, seed, writable=False):
        self.r = random.Random(seed)
        self.writable = writable

    def integer(self):
        r = self.r
        pick = r.random()
        if pick < 0.25:
            return r.randint(-5, 20)
        if pick < 0.5:
            return r.choice([0, 1, -1, 127, 128, -128, -129, 255, 256, 32767, 32768,
                             -32768, -32769, 8388607, 8388608, -8388608, -8388609,
                             2147483647, 2147483648, -2147483648, -2147483649,
                             140737488355327, 140737488355328,
                             -140737488355328, -140737488355329,
                             9223372036854775807, -9223372036854775808])
        bits = r.choice([8, 16, 24, 32, 48, 64])
        v = r.getrandbits(bits - 1)
        return -v if r.random() < 0.5 else v

    def real(self):
        r = self.r
        pick = r.random()
        if pick < 0.3:
            return repr(r.choice([0.0, -0.0, 1.0, -1.0, 0.5, 1.5, 0.1, 0.2, 0.3,
                                  0.30000000000000004, 100.0, 1e15, 1e16, 1e20,
                                  1e-20, 123456789012345.0, 1234567890123456.0,
                                  3.14159265358979, 2.718281828459045,
                                  1.7976931348623157e308, 4.9e-324]))
        # Fifteen significant digits at most, and the reason is a finding:
        # sqlite3 prints a REAL with `%!.15g` from an *approximate* decimal
        # expansion, and a double whose exact expansion lies within about
        # 1e-20 of a rounding tie comes out differently from an exact
        # renderer (542.5719435317435 was the first, in the sweep of
        # 2026-09-15). A 15-digit literal is nowhere near a tie, so the
        # question has one answer; the hard cases with 16 and 17 digits are
        # in cases/reals.sql, chosen one at a time and checked.
        if pick < 0.6:
            return fifteen(r.uniform(-1000, 1000))
        if pick < 0.8:
            return fifteen(r.uniform(-1, 1) * 10 ** r.randint(-30, 30))
        return repr(float(r.randint(-100000, 100000)))

    def text(self, page):
        r = self.r
        pick = r.random()
        if pick < 0.1:
            return ''
        if pick < 0.2:
            return r.choice(["it's", 'a|b', 'two\nlines', 'tab\there', 'på', '日本',
                             ' lead', 'trail ', "''", '|', '\\', '0', '1.5', 'NULL'])
        if pick < 0.85:
            n = r.randint(1, 12)
            return ''.join(r.choice('abcdefgxyz  -') for _ in range(n)).strip() or 'z'
        if pick < 0.95 or self.writable:
            # Long, but inside a page; for the writer, well inside it, since
            # five of these have to fit one row.
            return r.choice('abcxyz') * r.randint(20, max(21, page // (12 if self.writable else 3)))
        # Longer than a page: an overflow chain.
        return r.choice('mnop') * r.randint(page + 1, page * r.randint(2, 6))

    def blob(self, page):
        r = self.r
        pick = r.random()
        if pick < 0.2:
            return b''
        if pick < 0.9 or self.writable:
            return bytes(r.randint(0, 255) for _ in range(r.randint(1, 8)))
        return bytes(r.randint(0, 255) for _ in range(r.randint(page, page * 2)))

    def value(self, page):
        r = self.r
        pick = r.random()
        if pick < 0.12:
            return 'NULL'
        if pick < 0.5:
            return str(self.integer())
        if pick < 0.7:
            return self.real()
        if pick < 0.93:
            return sql_text(self.text(page))
        return sql_blob(self.blob(page))

    def key_value(self):
        # A value an index can have many ties on: a small alphabet, one type
        # mostly, so that WHERE col = v answers several rows.
        r = self.r
        pick = r.random()
        if pick < 0.6:
            return sql_text(r.choice(['red', 'green', 'blue', 'a', 'b', '']))
        if pick < 0.9:
            return str(r.randint(0, 6))
        return 'NULL'


def case(seed, number, out, writable=False):
    g = Gen(seed * 100003 + number, writable)
    r = g.r
    page = r.choice([512, 512, 1024, 4096, 4096, 4096, 65536])
    lines = []
    queries = []
    lines.append('-- generated by programs/sqlite/generate.py, seed %d case %d' % (seed, number))
    if page != 4096:
        lines.append('PRAGMA page_size = %d;' % page)

    tables = []
    for t in range(r.randint(1, 3)):
        name = 't%d' % (t + 1)
        ncols = r.randint(1, 5)
        cols = []
        for c in range(ncols):
            cname = 'c%d' % (c + 1)
            ctype = r.choice(['', ' INTEGER', ' TEXT', ' REAL', ' BLOB', ' INTEGER', ''])
            cols.append((cname, ctype))
        pk = None
        if r.random() < 0.3:
            pk = r.randrange(ncols)
            cols[pk] = (cols[pk][0], ' INTEGER PRIMARY KEY')
        key_cols = [i for i in range(ncols) if i != pk and r.random() < 0.4]
        decl = ', '.join(n + ty for n, ty in cols)
        lines.append('CREATE TABLE %s (%s);' % (name, decl))
        indexes = []
        for i in key_cols[:2]:
            iname = '%s_%s' % (name, cols[i][0])
            lines.append('CREATE INDEX %s ON %s (%s);' % (iname, name, cols[i][0]))
            indexes.append(i)
        if len(key_cols) >= 2 and r.random() < 0.5:
            a, b = key_cols[0], key_cols[1]
            lines.append('CREATE INDEX %s_%s%s ON %s (%s, %s);'
                         % (name, cols[a][0], cols[b][0], name, cols[a][0], cols[b][0]))

        # Enough rows to leave one page most of the time on a small page size,
        # and sometimes none at all.
        nrows = r.choice([0, 1, 2, 5, 10, 30, 80, 200, 400])
        if page >= 4096 and r.random() < 0.3:
            nrows = r.choice([300, 800, 1500])
        if writable and page <= 1024 and r.random() < 0.3:
            nrows = r.choice([1000, 2000])
        rowids = set()
        chosen_rowid = r.random() < 0.3
        for n in range(nrows):
            vals = []
            for i, (cn, ty) in enumerate(cols):
                if i == pk:
                    if chosen_rowid:
                        while True:
                            rid = g.integer()
                            if rid not in rowids:
                                break
                        rowids.add(rid)
                        vals.append(str(rid))
                    else:
                        vals.append('NULL')
                elif i in key_cols:
                    vals.append(g.key_value())
                else:
                    vals.append(g.value(page))
            # Every row of a table with chosen rowids chooses one: an assigned
            # rowid is one more than the largest, and lands on a chosen one.
            if chosen_rowid and pk is None:
                while True:
                    rid = g.integer()
                    if rid not in rowids:
                        break
                rowids.add(rid)
                lines.append('INSERT INTO %s (rowid, %s) VALUES (%d, %s);'
                             % (name, ', '.join(cn for cn, _ in cols), rid, ', '.join(vals)))
            else:
                lines.append('INSERT INTO %s VALUES (%s);' % (name, ', '.join(vals)))

        # Deletes: by a key value, by a rowid range, by one rowid. Leaves
        # freeblocks, and on the small page sizes a freelist.
        if nrows > 5 and r.random() < 0.5:
            how = r.random()
            if how < 0.4 and key_cols:
                i = r.choice(key_cols)
                lines.append('DELETE FROM %s WHERE %s = %s;' % (name, cols[i][0], g.key_value()))
            elif how < 0.8:
                lo = r.randint(1, nrows)
                hi = lo + r.randint(0, nrows)
                lines.append('DELETE FROM %s WHERE rowid > %d AND rowid < %d;' % (name, lo, hi))
            else:
                lines.append('DELETE FROM %s WHERE rowid = %d;' % (name, r.randint(1, nrows)))

        tables.append((name, cols, pk, key_cols, nrows))

    # Queries: every table whole; a rowid that is there and one that is not;
    # a lookup on every indexed column and on one that is not indexed; an
    # ORDER BY with rowid as the tiebreak, since ties are the point of
    # key_value and SQLite's sorter does not promise to be stable.
    #
    # Every query that is not ordered by something else is ORDER BY rowid,
    # and the first sweep is why: a query with no ORDER BY answers in whatever
    # order the plan walks, and `SELECT c1 FROM t3` with an index on c1 is a
    # covering-index scan that comes out in c1 order, NULLs first. Neither
    # side was wrong. The generator was asking a question with two right
    # answers, which is a defect in the generator (39 cases of 200 on
    # 2026-09-15), so it stopped asking it.
    for name, cols, pk, key_cols, nrows in tables:
        queries.append('SELECT * FROM %s ORDER BY rowid;' % name)
        queries.append('SELECT rowid, * FROM %s ORDER BY rowid;' % name)
        for _ in range(2):
            queries.append('SELECT * FROM %s WHERE rowid = %d;' % (name, r.randint(-2, nrows + 2)))
        if len(cols) > 1:
            some = [cn for cn, _ in cols if r.random() < 0.5] or [cols[0][0]]
            queries.append('SELECT %s FROM %s ORDER BY rowid;' % (', '.join(some), name))
        for i in key_cols:
            queries.append('SELECT * FROM %s WHERE %s = %s ORDER BY rowid;' % (name, cols[i][0], g.key_value()))
            queries.append('SELECT rowid FROM %s WHERE %s = %s ORDER BY rowid;' % (name, cols[i][0], g.key_value()))
        plain = [i for i in range(len(cols)) if i not in key_cols and i != pk]
        if plain:
            i = r.choice(plain)
            queries.append('SELECT rowid FROM %s WHERE %s = %s ORDER BY rowid;' % (name, cols[i][0], g.value(page)))
        if pk is not None:
            queries.append('SELECT * FROM %s WHERE %s = %d;' % (name, cols[pk][0], r.randint(-2, nrows + 2)))
        i = r.randrange(len(cols))
        queries.append('SELECT * FROM %s ORDER BY %s, rowid;' % (name, cols[i][0]))
    # Without rootpage: two writers put roots on different pages, and the
    # writer rung of the sweep runs these same queries over a file this
    # program wrote.
    queries.append('SELECT type, name, tbl_name FROM sqlite_schema;')

    with open(out, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n-- queries\n' + '\n'.join(queries) + '\n')


def main():
    if len(sys.argv) not in (4, 5) or (len(sys.argv) == 5 and sys.argv[4] != 'writable'):
        sys.stderr.write('usage: generate.py DIR SEED COUNT [writable]\n')
        sys.exit(2)
    d, seed, count = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    writable = len(sys.argv) == 5
    for n in range(1, count + 1):
        if writable:
            case(seed, n, '%s/gen-w-%d-%04d.sql' % (d, seed, n), True)
        else:
            case(seed, n, '%s/gen-%d-%04d.sql' % (d, seed, n))


if __name__ == '__main__':
    main()
