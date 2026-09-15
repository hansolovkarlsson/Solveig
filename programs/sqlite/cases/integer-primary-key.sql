-- `INTEGER PRIMARY KEY` is the rowid, and the column's value in the record is
-- NULL: the one rule of the record format that a reader has to know rather
-- than read. Also a table whose key column is not first, and a rowid that was
-- chosen rather than assigned.
CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE u (name TEXT, id INTEGER PRIMARY KEY, n INTEGER);
INSERT INTO t VALUES (10, 'ten'), (20, 'twenty'), (5, 'five');
INSERT INTO t (name) VALUES ('assigned');
INSERT INTO u VALUES ('x', 3, 1), ('y', 1, 2), ('z', 2, 3);
-- queries
SELECT * FROM t;
SELECT id, name FROM t WHERE rowid = 20;
SELECT name FROM t WHERE id = 5;
SELECT * FROM u;
SELECT rowid, id FROM u WHERE id = 1;
