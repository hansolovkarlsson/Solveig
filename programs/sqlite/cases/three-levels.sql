-- writer: skip (WITH RECURSIVE)
-- A table tree three levels deep: root, interior, leaves. With 512-byte pages
-- a leaf holds a few dozen rows and an interior page a hundred or so children,
-- so five thousand rows is comfortably past two levels. `WHERE rowid = n`
-- descends twice before it reads a leaf.
PRAGMA page_size = 512;
CREATE TABLE t (n INTEGER, s TEXT);
WITH RECURSIVE seq(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 5000)
INSERT INTO t SELECT i * 7 % 1000, 'row ' || i FROM seq;
-- queries
SELECT * FROM t;
SELECT * FROM t WHERE rowid = 1;
SELECT * FROM t WHERE rowid = 2500;
SELECT * FROM t WHERE rowid = 5000;
SELECT * FROM t WHERE rowid = 5001;
SELECT rowid, s FROM t WHERE n = 7;
