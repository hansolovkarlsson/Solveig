-- Text of every awkward kind: empty, a quote, a newline, a tab, a `|` (the
-- list-mode separator, which `sqlite3` does not escape), UTF-8, and a NUL
-- inside a blob. A string here is bytes, so the round trip is the whole test.
CREATE TABLE t (s TEXT, b BLOB);
INSERT INTO t VALUES ('', X'');
INSERT INTO t VALUES ('it''s', X'00');
INSERT INTO t VALUES ('two
lines', X'0A0D');
INSERT INTO t VALUES ('tab	here', X'09');
INSERT INTO t VALUES ('a|b|c', X'7C');
INSERT INTO t VALUES ('Solveig på fjället', X'C3A5');
INSERT INTO t VALUES ('日本語', X'E697A5');
INSERT INTO t VALUES ('a', X'FF');
-- queries
SELECT * FROM t;
SELECT s FROM t WHERE s = 'it''s';
SELECT rowid FROM t WHERE b = X'7C';
SELECT s FROM t ORDER BY s, rowid;
