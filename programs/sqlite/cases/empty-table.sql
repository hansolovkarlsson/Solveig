-- A table with no rows. One leaf page with no cells, root at page 2, and
-- `sqlite_schema` with one row. The smallest file `sqlite3` makes: two pages.
CREATE TABLE t (a INTEGER, b TEXT);
-- queries
SELECT * FROM t;
SELECT a FROM t WHERE rowid = 1;
