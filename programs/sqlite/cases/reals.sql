-- REAL is a big-endian IEEE double, serial type 7, and `sqlite3` prints one
-- with `%!.15g`: fifteen significant digits and always a decimal point. These
-- are the values that make that format earn its keep: integers stored as
-- real, negative zero, large and small exponents, and the classic 0.1 + 0.2.
CREATE TABLE t (x REAL);
INSERT INTO t VALUES (0.0), (-0.0), (1.0), (-1.0), (1.5), (0.1), (0.30000000000000004);
INSERT INTO t VALUES (3.14159265358979), (2.718281828459045), (1e20), (1e-20), (1.5e300), (-2.5e-300);
INSERT INTO t VALUES (123456789012345.0), (1234567890123456.0), (0.000001), (0.0000001), (100.0), (1e15), (1e16);
INSERT INTO t VALUES (9007199254740993.0), (4.9e-324), (1.7976931348623157e308);
-- queries
SELECT * FROM t;
SELECT rowid, x FROM t WHERE x = 1.5;
SELECT x FROM t ORDER BY x, rowid;
