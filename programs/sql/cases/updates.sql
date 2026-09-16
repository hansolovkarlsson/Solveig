-- Updates, written by hand, for the shell's UPDATE and through it the
-- library's `update`: a keyed column changed so that its index entries
-- move, a REAL column given a whole number, a range of rowids changed at
-- once, a row moved to a rowid nothing holds, an update that matches no
-- row, and a NULL written over a value. Forty rows on 512-byte pages, so
-- the table and each index are more than one leaf.
PRAGMA page_size = 512;
CREATE TABLE t (n INTEGER, s TEXT, k TEXT, w REAL);
CREATE INDEX t_k ON t (k);
CREATE INDEX t_n ON t (n);
INSERT INTO t VALUES (1, 'row 1', 'green', 1.5);
INSERT INTO t VALUES (2, 'row 2', 'blue', 2.5);
INSERT INTO t VALUES (3, 'row 3', 'red', 3.5);
INSERT INTO t VALUES (4, 'row 4', 'green', 4.5);
INSERT INTO t VALUES (5, 'row 5', 'blue', 5.5);
INSERT INTO t VALUES (6, 'row 6', 'red', 6.5);
INSERT INTO t VALUES (7, 'row 7', 'green', 7.5);
INSERT INTO t VALUES (8, 'row 8', 'blue', 8.5);
INSERT INTO t VALUES (9, 'row 9', 'red', 9.5);
INSERT INTO t VALUES (10, 'row 10', 'green', 10.5);
INSERT INTO t VALUES (11, 'row 11', 'blue', 11.5);
INSERT INTO t VALUES (12, 'row 12', 'red', 12.5);
INSERT INTO t VALUES (13, 'row 13', 'green', 13.5);
INSERT INTO t VALUES (14, 'row 14', 'blue', 14.5);
INSERT INTO t VALUES (15, 'row 15', 'red', 15.5);
INSERT INTO t VALUES (16, 'row 16', 'green', 16.5);
INSERT INTO t VALUES (17, 'row 17', 'blue', 17.5);
INSERT INTO t VALUES (18, 'row 18', 'red', 18.5);
INSERT INTO t VALUES (19, 'row 19', 'green', 19.5);
INSERT INTO t VALUES (20, 'row 20', 'blue', 20.5);
INSERT INTO t VALUES (21, 'row 21', 'red', 21.5);
INSERT INTO t VALUES (22, 'row 22', 'green', 22.5);
INSERT INTO t VALUES (23, 'row 23', 'blue', 23.5);
INSERT INTO t VALUES (24, 'row 24', 'red', 24.5);
INSERT INTO t VALUES (25, 'row 25', 'green', 25.5);
INSERT INTO t VALUES (26, 'row 26', 'blue', 26.5);
INSERT INTO t VALUES (27, 'row 27', 'red', 27.5);
INSERT INTO t VALUES (28, 'row 28', 'green', 28.5);
INSERT INTO t VALUES (29, 'row 29', 'blue', 29.5);
INSERT INTO t VALUES (30, 'row 30', 'red', 30.5);
INSERT INTO t VALUES (31, 'row 31', 'green', 31.5);
INSERT INTO t VALUES (32, 'row 32', 'blue', 32.5);
INSERT INTO t VALUES (33, 'row 33', 'red', 33.5);
INSERT INTO t VALUES (34, 'row 34', 'green', 34.5);
INSERT INTO t VALUES (35, 'row 35', 'blue', 35.5);
INSERT INTO t VALUES (36, 'row 36', 'red', 36.5);
INSERT INTO t VALUES (37, 'row 37', 'green', 37.5);
INSERT INTO t VALUES (38, 'row 38', 'blue', 38.5);
INSERT INTO t VALUES (39, 'row 39', 'red', 39.5);
INSERT INTO t VALUES (40, 'row 40', 'green', 40.5);
UPDATE t SET k = 'amber' WHERE k = 'red';
UPDATE t SET w = 7 WHERE rowid > 10 AND rowid < 15;
UPDATE t SET n = 1000, s = 'moved' WHERE rowid = 3;
UPDATE t SET rowid = 99 WHERE rowid = 7;
UPDATE t SET s = 'nobody' WHERE k = 'violet';
UPDATE t SET k = NULL WHERE n = 20;
UPDATE t SET w = 0.125 WHERE n >= 38;
-- queries
SELECT rowid, * FROM t ORDER BY rowid;
SELECT rowid FROM t WHERE k = 'amber' ORDER BY rowid;
SELECT rowid FROM t WHERE k = 'red' ORDER BY rowid;
SELECT rowid, s FROM t WHERE n = 1000;
SELECT rowid FROM t WHERE n = 7;
SELECT * FROM t WHERE rowid = 99;
SELECT rowid FROM t WHERE k = NULL;
SELECT type, name, tbl_name FROM sqlite_schema;
