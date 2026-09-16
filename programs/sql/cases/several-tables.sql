-- writer: skip (a UNIQUE column, whose automatic index the writer does not make)
-- `sqlite_schema` with several rows of several kinds: two tables and two
-- indexes, one of them automatic, so the reader meets an `sql` column that is
-- NULL and a name it did not create. Roots are wherever `sqlite3` put them.
CREATE TABLE a (x INTEGER, y TEXT);
CREATE TABLE b (p TEXT UNIQUE, q REAL);
CREATE INDEX a_x ON a (x);
INSERT INTO a VALUES (1, 'one'), (2, 'two'), (3, 'three');
INSERT INTO b VALUES ('p1', 0.5), ('p2', 2.5);
-- queries
SELECT * FROM a;
SELECT * FROM b;
SELECT y FROM a WHERE x = 2;
SELECT q FROM b WHERE p = 'p2';
SELECT type, name, tbl_name, rootpage FROM sqlite_schema;
