-- One row, every storage class in one record: NULL, an integer, a real, a
-- text and a blob. Serial types 0, 1, 7, 13 and up, 12 and up.
CREATE TABLE t (a, b, c, d, e);
INSERT INTO t VALUES (NULL, 7, 1.5, 'seven', X'0001FE');
-- queries
SELECT * FROM t;
SELECT a, b, c, d, e FROM t WHERE rowid = 1;
SELECT rowid, d FROM t;
