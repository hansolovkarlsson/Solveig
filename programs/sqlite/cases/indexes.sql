-- writer: skip (WITH RECURSIVE, and a UNIQUE index)
-- Index trees: one on a text column with many ties, one on two columns, and a
-- unique one. An index cell is a record whose last column is the rowid. A
-- 512-byte page makes the index interior.
--
-- The lookups are ORDER BY rowid because `k` is in two indexes, and through
-- `t_kn` the rows come out in (k, n, rowid) order: which index the planner
-- takes is its business, and a query that depends on it has two right answers.
PRAGMA page_size = 512;
CREATE TABLE t (k TEXT, n INTEGER, u INTEGER);
CREATE INDEX t_k ON t (k);
CREATE INDEX t_kn ON t (k, n);
CREATE UNIQUE INDEX t_u ON t (u);
WITH RECURSIVE seq(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 1500)
INSERT INTO t SELECT char(97 + i % 7) || 'key', i % 13, i * 3 FROM seq;
-- queries
SELECT * FROM t WHERE k = 'ckey' ORDER BY rowid;
SELECT rowid FROM t WHERE u = 4200;
SELECT rowid FROM t WHERE u = 4201;
SELECT * FROM t WHERE n = 12 ORDER BY rowid;
SELECT k, n FROM t ORDER BY k, rowid;
