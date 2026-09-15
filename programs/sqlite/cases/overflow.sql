-- Payloads longer than a page spill to overflow pages, chained by a four-byte
-- pointer at the head of each. With a 512-byte page a 2,000-byte text is
-- four or five pages of chain, and a 20,000-byte one is forty. The reader
-- follows the chain; the writer in this program never makes one.
PRAGMA page_size = 512;
CREATE TABLE t (n INTEGER, s TEXT);
INSERT INTO t VALUES (1, 'short');
INSERT INTO t VALUES (2, replace(hex(zeroblob(1000)), '00', 'ab'));
INSERT INTO t VALUES (3, replace(hex(zeroblob(10000)), '00', 'cd'));
INSERT INTO t VALUES (4, 'short again');
INSERT INTO t VALUES (5, replace(hex(zeroblob(250)), '00', 'ef'));
-- queries
SELECT * FROM t WHERE rowid = 3;
SELECT n FROM t WHERE s = 'short again';
SELECT * FROM t;
