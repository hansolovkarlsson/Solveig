-- writer: skip (DELETE is step 5, and WITH RECURSIVE)
-- Deletes. A cell removed leaves a freeblock inside its page; a leaf emptied
-- goes to the freelist, whose trunk page lists the free leaves; and the header
-- at offsets 32 and 36 points at the trunk and counts them. A reader must not
-- walk a free page, and `PRAGMA freelist_count` says how many there are.
PRAGMA page_size = 512;
CREATE TABLE t (n INTEGER, s TEXT);
WITH RECURSIVE seq(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 3000)
INSERT INTO t SELECT i, 'row ' || i FROM seq;
DELETE FROM t WHERE n % 3 = 0;
DELETE FROM t WHERE n > 1000 AND n < 2000;
DELETE FROM t WHERE rowid = 1;
-- queries
SELECT * FROM t;
SELECT * FROM t WHERE rowid = 2;
SELECT * FROM t WHERE rowid = 3;
SELECT * FROM t WHERE rowid = 1500;
SELECT * FROM t WHERE rowid = 2999;
SELECT rowid, n FROM t WHERE n = 2000;
