-- Every integer width the record format has: serial types 8 and 9 for 0 and 1,
-- then 1, 2, 3, 4, 6 and 8 bytes, positive and negative, and the extremes of a
-- signed 64-bit value. The rowids are chosen too, so the varint reader meets a
-- nine-byte key and a negative one.
CREATE TABLE t (n INTEGER);
INSERT INTO t VALUES (0), (1), (-1), (127), (128), (-128), (-129);
INSERT INTO t VALUES (32767), (32768), (-32768), (-32769);
INSERT INTO t VALUES (8388607), (8388608), (-8388608), (-8388609);
INSERT INTO t VALUES (2147483647), (2147483648), (-2147483648), (-2147483649);
INSERT INTO t VALUES (140737488355327), (140737488355328), (-140737488355328), (-140737488355329);
INSERT INTO t VALUES (9223372036854775807), (-9223372036854775808);
INSERT INTO t (rowid, n) VALUES (-5, 55), (9223372036854775807, 99), (1000000000000, 12);
-- queries
SELECT * FROM t;
SELECT rowid, n FROM t;
SELECT n FROM t WHERE rowid = -5;
SELECT n FROM t WHERE rowid = 9223372036854775807;
SELECT n FROM t WHERE rowid = 1000000000000;
SELECT rowid FROM t WHERE n = 128;
