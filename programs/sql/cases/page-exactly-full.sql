-- A leaf filled to the last row, and one row more. With a 512-byte page and
-- rows of a known size the first tree is one leaf; the second insert forces
-- the split that the reader's interior-page path exists for.
--
-- Counted, then measured, and the two disagree by one. A cell here is a
-- payload-size varint, a rowid varint, a two-byte record header and fifteen
-- bytes of text, 19 bytes, plus a two-byte pointer: 21 a row, and 504 bytes
-- below the 8-byte page header hold 24 of them exactly. `sqlite3` splits at
-- the 24th, so a leaf holds 23. The writer at step 3 is free to split where
-- it likes, since `integrity_check` accepts any well-formed tree, but the
-- reader's corpus should have both the leaf that is one row short of full
-- and the tree that split, and this file has both: `full` is 23 rows and one
-- leaf, `over` is 24 and two leaves under an interior root.
PRAGMA page_size = 512;
CREATE TABLE full (s TEXT);
CREATE TABLE over (s TEXT);
INSERT INTO full VALUES ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx');
INSERT INTO full VALUES ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx');
INSERT INTO full VALUES ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx');
INSERT INTO full VALUES ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx');
INSERT INTO full VALUES ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx');
INSERT INTO full VALUES ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx');
INSERT INTO over VALUES ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx');
INSERT INTO over VALUES ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx');
INSERT INTO over VALUES ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx');
INSERT INTO over VALUES ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx');
INSERT INTO over VALUES ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx');
INSERT INTO over VALUES ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx'), ('xxxxxxxxxxxxxxx');
INSERT INTO over VALUES ('one more');
-- queries
SELECT * FROM full;
SELECT * FROM over;
SELECT rowid FROM over WHERE rowid = 24;
SELECT rowid FROM over WHERE rowid = 25;
