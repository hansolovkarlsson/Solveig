-- The largest page: 65536 is spelled 1 in the two-byte field at offset 16,
-- the one place in the header where the number is not the number.
PRAGMA page_size = 65536;
CREATE TABLE t (n INTEGER, s TEXT);
WITH RECURSIVE seq(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 4000)
INSERT INTO t SELECT i, 'row ' || i FROM seq;
-- queries
SELECT * FROM t;
SELECT * FROM t WHERE rowid = 4000;
SELECT s FROM t WHERE n = 17;
