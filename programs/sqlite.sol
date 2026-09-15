; sqlite.sol -- an SQLite database file, read and written.
;
; Run with:  ./bin/solas programs/sqlite.sol && ./bin/solvm programs/sqlite.sob
; Over a file:  ./bin/solvm programs/sqlite.sob notes.db < statements.sql
; Or one statement:  ./bin/solvm programs/sqlite.sob notes.db 'SELECT * FROM t'
; With no arguments it demonstrates itself on a file it writes under build/.
;
; The twenty-third program here, and the first of the directions design.md
; lists to be reached. It reads and writes the file format that `sqlite3`
; uses, from the format's own description and nothing else, and answers
; SELECT in the shell's default list mode: columns with `|` between them,
; nothing for NULL, one row a line. That is so the two can be compared byte
; for byte, which is what programs/sqlite/sweep.sh does in both directions:
; `sqlite3` builds every database in the corpus and `sqlite3` says what is in
; it, and then this program builds the same databases and `sqlite3` judges
; the files, with `PRAGMA integrity_check` and by reading them.
;
; The plan is in ideas.md under *An SQLite file, read and then written*, with
; what it predicted written above what it found. This file is steps 1 to 4 of
; it: the reader over tables, then the index trees, which a WHERE on an
; indexed column walks instead of scanning; then the writer from nothing,
; CREATE TABLE, CREATE INDEX and INSERT into a fresh file, pages built in
; memory and the file written whole at the end; then the same into a file
; sqlite3 made, its pages decoded, changed and written back the only way the
; language has, which is whole. That is ROADMAP 3.27, raised from here with
; the measurement `SQLITE_PAGES=1` prints: one INSERT into 100 MB needs four
; pages read and three written, and pays 24,390 of each. The SQL it parses is the SQL
; the plan bounds: SELECT of named columns, `rowid` or `*`, from one table,
; with a WHERE of one comparison and an ORDER BY; CREATE TABLE with plain
; columns; CREATE INDEX on plain columns; INSERT of literals; PRAGMA
; page_size. Nothing else, and a statement outside that is reported as such
; rather than quietly meaning something else. `SQLITE_PAGES=1` in the
; environment reports how many pages a run read and how many bytes it wrote,
; which are the numbers a statement is measured by here.
;
; What the format is, in the amount this file needs:
;
;   The file is pages of one size, numbered from 1. Page 1 begins with a
;   100-byte header: the page size at offset 16 big-endian, spelled 1 when it
;   is 65536; the reserved bytes per page at 20; the page count at 28. After
;   the header, page 1 is the root of the table `sqlite_schema`, whose rows
;   say what else is in the file: type, name, tbl_name, rootpage, sql.
;
;   A B-tree page is a header, then an array of two-byte cell pointers, then
;   free space, then the cells growing up from the end. The header's first
;   byte is the kind: 0x0d a table leaf, 0x05 a table interior, 0x0a an index
;   leaf, 0x02 an index interior. Bytes 3-4 are the cell count; on an interior
;   page bytes 8-11 are the right-most child, and the header is 12 bytes
;   rather than 8.
;
;   A table leaf cell is the payload size as a varint, the rowid as a varint,
;   then the payload; a table interior cell is a four-byte left child and a
;   varint rowid, meaning every rowid in that child is at most this one. An
;   index leaf cell is a payload size and a payload, the payload a record
;   whose last column is the rowid; an index interior cell is a left child
;   and then the same, and that entry counts, with everything in the child
;   before it less. A varint is one to nine bytes, big-endian, seven bits a
;   byte with the high bit saying there is more, and all eight bits of the
;   ninth.
;
;   The payload is a record: a header whose first varint is its own length,
;   then a serial type per column; then the values. 0 is NULL; 1 to 6 are
;   big-endian signed integers of 1, 2, 3, 4, 6 and 8 bytes; 7 is a
;   big-endian IEEE double; 8 and 9 are the integers 0 and 1 stored in no
;   bytes at all; from 12 an even type is a blob of (n-12)/2 bytes and an odd
;   one a text of (n-13)/2. A column declared INTEGER PRIMARY KEY is the
;   rowid, and its value in the record is NULL, which is the one rule of the
;   format that a reader knows rather than reads.
;
;   A payload too long for its page keeps a local part and continues on
;   overflow pages, each a four-byte pointer to the next and then bytes. How
;   much stays local is a formula over the usable page size that every
;   implementation shares, since `integrity_check` checks it. The writer
;   here never makes one: a row that would need one is refused by name.
;
;   Writing is the same shapes in the other direction, and one more: a page
;   that will not hold its cells splits. A table tree is a B+tree, so a leaf
;   that splits sends up a copy of its last left rowid; an index tree is a
;   B-tree, so a page that splits sends up its middle entry. The page that
;   split keeps its number as the left half, the new page is the right, and
;   the root keeps its number by moving its contents down when it splits,
;   which is how a tree gains a level and why a root page number in the
;   schema never changes.
;
; Three things about the language, found here:
;
;   1. **A negative integer from eight bytes**, and from the ninth byte of a
;      varint, cannot be shifted into place: ROADMAP 3.12, met by disasm.sol
;      first. The same arithmetic route is taken here, in `varint` and
;      `signedBytes`: the top byte contributes its signed weight rather than
;      being shifted into a sign bit that does not exist.
;
;   2. **A REAL is printed with `%!.15g`**, fifteen significant digits and
;      always a decimal point, and that format is not in `asString(spec)`.
;      awk.sol wrote `%g` by dividing by a power of ten, which is near rather
;      than exact, and fifteen digits is where near shows. So `decimal` below
;      is exact: the double is taken apart into its 53-bit mantissa and its
;      exponent, and the decimal expansion is computed with a small base-10^9
;      big integer, which is the only way to be sure of the fifteenth digit.
;      Slow for a value like 1e-300, a thousand multiplications by five, and
;      exact for all of them.
;
;   3. **`sob:f64` in the library takes a float apart** the same way, and is
;      not reused: it writes into a buffer of its own and does not produce
;      subnormals, which this file meets in a corpus row of 4.9e-324. The
;      decomposition is twenty lines and is written again, which is the trigger
;      rule counting a second copy.

@include "scan.sol".

; ---------------------------------------------------------------------------
; Bytes
;
; `at` answers a one-character string and `asByte` its number, and everything
; below reads big-endian, which is what this format is throughout.

u8 := { s, i | s:at(i):asByte }.
u16 := { s, i | s:at(i):asByte:shiftLeft(#8):bitOr(s:at(i:inc):asByte) }.
u32 := { s, i |
    s:at(i):asByte:shiftLeft(#24)
        :bitOr(s:at(i:add(#1)):asByte:shiftLeft(#16))
        :bitOr(s:at(i:add(#2)):asByte:shiftLeft(#8))
        :bitOr(s:at(i:add(#3)):asByte) }.

; A varint at `i`: answers the value and the index after it. The ninth byte
; carries eight bits, so the fifty-six above it may already reach bit 55 and
; the shift into bit 63 is the one the language refuses. Arithmetic instead:
; when the value so far has its top bit (of 56) set, it is subtracted from
; 2^56 first, so that the multiplication by 256 lands negative and in range.
varint := { s, i | | v, b, n, at |
    v := #0. n := #0. at := i.
    { n:lessThan(#8):and({ s:at(at):asByte:greaterOrEqual(#128) }) }:whileTrue({
        v := v:shiftLeft(#7):bitOr(s:at(at):asByte:bitAnd(#127)).
        n := n:inc. at := at:inc }).
    n:lessThan(#8):ifElse(
        { v := v:shiftLeft(#7):bitOr(s:at(at):asByte). at := at:inc },
        { b := s:at(at):asByte. at := at:inc.
          v:greaterOrEqual(#36028797018963968):ifTrue({          ; 2^55
              v := v:sub(#72057594037927936) }).                 ; 2^56
          v := v:mul(#256):add(b) }).
    [v, at] }.

; A big-endian signed integer of `n` bytes at `i`, n from 1 to 8. Below eight
; bytes the value fits with room to spare and the sign is a subtraction; at
; eight the top byte is weighted by hand, disasm.sol's route.
signedBytes := { s, i, n | | v, k, b |
    n:equals(#8):ifElse(
        { b := s:at(i):asByte.
          v := #0. k := #1.
          { k:lessThan(#8) }:whileTrue({
              v := v:shiftLeft(#8):bitOr(s:at(i:add(k)):asByte). k := k:inc }).
          b:lessThan(#128):ifElse(
              { v:add(b:mul(#72057594037927936)) },
              { v:add(b:sub(#256):mul(#72057594037927936)) }) },
        { v := #0. k := #0.
          { k:lessThan(n) }:whileTrue({
              v := v:shiftLeft(#8):bitOr(s:at(i:add(k)):asByte). k := k:inc }).
          v:greaterOrEqual(#1:shiftLeft(n:mul(#8):dec)):ifElse(
              { v:sub(#1:shiftLeft(n:mul(#8))) }, { v }) }) }.

; ---------------------------------------------------------------------------
; A double, exactly
;
; The eight bytes of a REAL are a sign, an eleven-bit exponent and fifty-two
; bits of mantissa, and the value is assembled as disasm.sol assembles one.
; The same three parts are also what `decimal` wants, so they are answered
; alongside: [value, sign, mantissa, exponent] with mantissa the full integer
; significand (the implicit bit included) and exponent the power of two it is
; scaled by, so that value = mantissa * 2^exponent exactly.

powerOfTwo := { n | | out, i |
    out := 1.0. i := #0.
    n:greaterOrEqual(#0):ifElse(
        { { i:lessThan(n) }:whileTrue({ out := out:mul(2.0). i := i:inc }) },
        { { i:lessThan(n:negated) }:whileTrue({ out := out:div(2.0). i := i:inc }) }).
    out }.

floatFromBytes := { s, i | | hi, lo, sign, exponent, mantissa, value, e2 |
    hi := u32:value(s, i).
    lo := u32:value(s, i:add(#4)).
    sign     := hi:shiftRight(#31):bitAnd(#1).
    exponent := hi:shiftRight(#20):bitAnd(#2047).
    mantissa := hi:bitAnd(#1048575):mul(#4294967296):add(lo).
    exponent:equals(#2047):ifTrue({
        error:raise(mantissa:equals(#0):ifElse({ "infinity" }, { "not a number" })) }).
    exponent:equals(#0):ifElse(
        { e2 := #-1074 },                                        ; subnormal
        { e2 := exponent:sub(#1075). mantissa := mantissa:add(#4503599627370496) }).
    value := mantissa:asFloat:mul(powerOfTwo:value(e2)).
    sign:equals(#1):ifTrue({ value := value:negated }).
    [value, sign, mantissa, e2] }.

; The same parts from a float the parser made, for a literal that has to be
; printed or compared as text. Normalised into [1, 2) by halving and doubling,
; as sob:f64 does, and then down into the subnormals where that library stops.
floatParts := { x | | sign, exponent, mantissa, y |
    sign := #0. y := x.
    x:lessThan(0.0):or({ x:equals(0.0):and({ 1:div(x):lessThan(0.0) }) })
        :ifTrue({ sign := #1. y := x:negated }).
    y:equals(0.0):ifElse(
        { [x, sign, #0, #-1074] },
        { exponent := #1023.
          { y:greaterOrEqual(2.0) }:whileTrue({ y := y:div(2.0). exponent := exponent:inc }).
          { y:lessThan(1.0):and({ exponent:greaterThan(#1) }) }:whileTrue({
              y := y:mul(2.0). exponent := exponent:dec }).
          y:lessThan(1.0):ifElse(
              { ; Subnormal: exponent field 0, no implicit bit, scaled by 2^-1074.
                mantissa := y:mul(4503599627370496.0):rounded.
                [x, sign, mantissa, #-1074] },
              { mantissa := y:sub(1.0):mul(4503599627370496.0):rounded
                    :add(#4503599627370496).
                [x, sign, mantissa, exponent:sub(#1075)] }) }) }.

; The exact decimal digits of mantissa * 2^exponent, as [digits, pointAt]: the
; digits with no leading zeros, and how many of them stand before the decimal
; point (zero or negative when the value is below 1). A small big-integer in
; base 10^9, least significant limb first: multiplied by two for a positive
; exponent, and by five for a negative one, since m / 2^k = m * 5^k / 10^k.
bigTimes := { limbs, factor | | carry, i, v |
    carry := #0. i := #1.
    { i:lessOrEqual(limbs:size) }:whileTrue({
        v := limbs:at(i):mul(factor):add(carry).
        limbs:atPut(i, v:mod(#1000000000)).
        carry := v:div(#1000000000).
        i := i:inc }).
    carry:greaterThan(#0):ifTrue({ limbs:add(carry) }).
    limbs }.

bigDigits := { limbs | | out, i, piece |
    out := limbs:at(limbs:size):asString.
    i := limbs:size:dec.
    { i:greaterOrEqual(#1) }:whileTrue({
        piece := limbs:at(i):asString.
        out := out:concat("000000000":copyFrom(#1, #9:sub(piece:size)):concat(piece)).
        i := i:dec }).
    out }.

exactDecimal := { mantissa, exponent | | limbs, k, digits, pointAt, lead |
    limbs := [mantissa:mod(#1000000000), mantissa:div(#1000000000)].
    limbs:at(#2):equals(#0):ifTrue({ limbs:removeLast }).
    k := #0.
    exponent:greaterOrEqual(#0):ifElse(
        { { k:lessThan(exponent) }:whileTrue({ bigTimes:value(limbs, #2). k := k:inc }).
          digits := bigDigits:value(limbs).
          pointAt := digits:size },
        { { k:lessThan(exponent:negated) }:whileTrue({ bigTimes:value(limbs, #5). k := k:inc }).
          digits := bigDigits:value(limbs).
          pointAt := digits:size:sub(exponent:negated) }).
    ; Strip leading zeros (the point moves with them) and trailing ones.
    lead := #1.
    { lead:lessThan(digits:size):and({ digits:at(lead):equals("0") }) }:whileTrue({
        lead := lead:inc. pointAt := pointAt:dec }).
    digits := digits:copyFrom(lead, digits:size).
    { digits:size:greaterThan(#1):and({ digits:at(digits:size):equals("0") }) }:whileTrue({
        digits := digits:copyFrom(#1, digits:size:dec) }).
    [digits, pointAt] }.

; `%!.15g`: fifteen significant digits, rounded half up on the exact
; expansion as SQLite's own printf rounds its; trailing zeros dropped but at
; least one digit after the point; exponential form when the decimal exponent
; is below -4 or at least 15, with a sign and at least two digits.
fifteen := { parts | | sign, digits, pointAt, d, carry, i, exp10, out, whole, frac |
    sign := parts:at(#2).
    parts:at(#3):equals(#0):ifElse({ "0.0" }, {
        d := exactDecimal:value(parts:at(#3), parts:at(#4)).
        digits := d:at(#1). pointAt := d:at(#2).
        digits:size:greaterThan(#15):ifTrue({
            carry := digits:at(#16):asByte:greaterOrEqual(#53).      ; "5"
            digits := digits:copyFrom(#1, #15).
            carry:ifTrue({
                i := #15. carry := true.
                { carry:and({ i:greaterOrEqual(#1) }) }:whileTrue({
                    digits:at(i):equals("9"):ifElse(
                        { digits := digits:copyFrom(#1, i:dec):concat("0")
                              :concat(digits:copyFrom(i:inc, digits:size)) },
                        { digits := digits:copyFrom(#1, i:dec)
                              :concat(digits:at(i):asByte:inc:asCharacter)
                              :concat(digits:copyFrom(i:inc, digits:size)).
                          carry := false }).
                    i := i:dec }).
                carry:ifTrue({ digits := "1":concat(digits). pointAt := pointAt:inc }) }).
            { digits:size:greaterThan(#1):and({ digits:at(digits:size):equals("0") }) }:whileTrue({
                digits := digits:copyFrom(#1, digits:size:dec) }) }).
        exp10 := pointAt:dec.
        exp10:lessThan(#-4):or({ exp10:greaterOrEqual(#15) }):ifElse(
            { frac := digits:size:greaterThan(#1):ifElse(
                  { digits:copyFrom(#2, digits:size) }, { "0" }).
              out := digits:at(#1):concat("."):concat(frac):concat("e")
                  :concat(exp10:lessThan(#0):ifElse({ "-" }, { "+" }))
                  :concat(exp10:abs:asString("02")) },
            { pointAt:lessOrEqual(#0):ifElse(
                  { out := "0.":concat("0000":copyFrom(#1, pointAt:negated))
                        :concat(digits) },
                  { pointAt:greaterOrEqual(digits:size):ifElse(
                        { whole := digits:concat("000000000000000"
                              :copyFrom(#1, pointAt:sub(digits:size))).
                          out := whole:concat(".0") },
                        { out := digits:copyFrom(#1, pointAt):concat(".")
                              :concat(digits:copyFrom(pointAt:inc, digits:size)) }) }) }).
        sign:equals(#1):ifElse({ "-":concat(out) }, { out }) }) }.

; ---------------------------------------------------------------------------
; Values
;
; NULL is nil, an integer an integer, a REAL a float, text a string, and a
; blob is a string inside a `blob`, since the format keeps the two apart and
; so must a comparison. A REAL carries its parts too, for printing.

blob := object:new.
blob:bytes := "".
blob:of := { s | | b | b := self:new. b:bytes := s. b }.

real := object:new.
real:value := 0.0.
real:parts := nil.
real:of := { parts | | r | r := self:new. r:value := parts:at(#1). r:parts := parts. r }.

isNumber := { v | v:isKindOf(integer):or({ v:isKindOf(real) }) }.
asFloatValue := { v | v:isKindOf(integer):ifElse({ v:asFloat }, { v:value }) }.

; Rank for ordering: NULL, then numbers, then text, then blobs.
rank := { v |
    v:isNil:ifElse({ #0 },
        { isNumber:value(v):ifElse({ #1 },
            { v:isKindOf(string):ifElse({ #2 }, { #3 }) }) }) }.

; SQLite's order: by rank, then numerically, then by bytes.
compare := { a, b | | ra, rb |
    ra := rank:value(a). rb := rank:value(b).
    ra:notEquals(rb):ifElse(
        { ra:lessThan(rb):ifElse({ #-1 }, { #1 }) },
        { ra:equals(#0):ifElse({ #0 },
          { ra:equals(#1):ifElse(
              { a:isKindOf(integer):and({ b:isKindOf(integer) }):ifElse(
                    { a:lessThan(b):ifElse({ #-1 }, { a:greaterThan(b):ifElse({ #1 }, { #0 }) }) },
                    { | x, y | x := asFloatValue:value(a). y := asFloatValue:value(b).
                      x:lessThan(y):ifElse({ #-1 }, { x:greaterThan(y):ifElse({ #1 }, { #0 }) }) }) },
              { | x, y |
                x := ra:equals(#2):ifElse({ a }, { a:bytes }).
                y := ra:equals(#2):ifElse({ b }, { b:bytes }).
                x:lessThan(y):ifElse({ #-1 }, { x:greaterThan(y):ifElse({ #1 }, { #0 }) }) }) }) }) }.

; List mode: nothing for NULL, digits, `%!.15g`, the bytes of a text, and
; the bytes of a blob up to the first NUL, which is where the shell's `%s`
; stops and so where this stops.
render := { v | | nul, at |
    v:isNil:ifElse({ "" },
        { v:isKindOf(integer):ifElse({ v:asString },
            { v:isKindOf(real):ifElse({ fifteen:value(v:parts) },
                { v:isKindOf(string):ifElse({ v },
                    { nul := #0:asCharacter.
                      at := v:bytes:indexOf(nul).
                      at:isNil:ifElse({ v:bytes },
                          { at:equals(#1):ifElse({ "" }, { v:bytes:copyFrom(#1, at:dec) }) }) }) }) }) }) }.

; ---------------------------------------------------------------------------
; The file

db := object:new.
db:path := "".
db:pageSize := #0.
db:usable := #0.
db:pageCount := #0.
db:cache := nil.
db:reads := #0.
db:dirty := nil.                ; page number -> page object, to be written
db:changes := #0.               ; the file change counter, offset 24
db:cookie := #0.                ; the schema cookie, offset 40
db:freelistHead := #0.
db:freelistCount := #0.
db:written := #0.               ; bytes written by flush, for the measurement
db:changed := #0.               ; pages that were changed when flush ran
db:readBefore := #0.            ; pages read before flush had to read the rest

; A file that is there is opened; one that is not, or one of no bytes, which
; is what sqlite3 leaves after a script that only set a pragma, is a new
; database in memory, one empty schema page, written when something has
; changed.
db:open := { path | | d, header |
    d := self:new.
    d:path := path.
    d:cache := dictionary:new.
    d:dirty := dictionary:new.
    (system:fileExists(path):and({ system:fileSize(path):greaterThan(#0) })):ifElse(
        { header := system:readFile(path, #1, #100).
          header:size:lessThan(#100):or({ header:copyFrom(#1, #15):notEquals("SQLite format 3") })
              :ifTrue({ error:raise("file is not a database: ":concat(path)) }).
          d:pageSize := u16:value(header, #17).
          d:pageSize:equals(#1):ifTrue({ d:pageSize := #65536 }).
          d:usable := d:pageSize:sub(u8:value(header, #21)).
          d:changes := u32:value(header, #25).
          d:pageCount := u32:value(header, #29).
          d:freelistHead := u32:value(header, #33).
          d:freelistCount := u32:value(header, #37).
          d:cookie := u32:value(header, #41) },
        { d:pageSize := #4096.
          d:usable := #4096.
          d:pageCount := #1.
          d:dirty:atPut(#1, page:of(#13)) }).
    d }.

db:isEmpty := { self:pageCount:equals(#1):and({ self:object(#1):cells:size:equals(#0) }) }.

; One page, by number: a page being written, serialised; else the cache; else
; the file. A page from the file is one ranged read, and the count of them is
; the number to watch in a query.
db:page := { n | | from, p |
    self:dirty:includes(n):ifElse({ self:dirty:at(n):bytes(n, self) },
    { self:cache:includes(n):ifElse({ self:cache:at(n) }, {
        from := n:dec:mul(self:pageSize):inc.
        p := system:readFile(self:path, from, self:pageSize).
        p:size:lessThan(self:pageSize):ifTrue({
            error:raise("page ":concat(n:asString):concat(" is not in the file")) }).
        self:reads := self:reads:inc.
        self:cache:atPut(n, p).
        p }) }) }.

; The same page as an object to change, which marks it to be written.
db:object := { n | | o |
    self:dirty:includes(n):ifElse({ self:dirty:at(n) }, {
        o := decodePage:value(self, self:page(n), n).
        self:dirty:atPut(n, o).
        o }) }.

; A fresh page at the end of the file.
db:newPage := { kind | | o |
    self:pageCount := self:pageCount:inc.
    o := page:of(kind).
    self:dirty:atPut(self:pageCount, o).
    self:pageCount }.

; The 100 bytes at the front of page 1.
db:fileHeader := {
    ["SQLite format 3":concat(#0:asCharacter),
     u16Bytes:value(self:pageSize:equals(#65536):ifElse({ #1 }, { self:pageSize })),
     #1:asCharacter, #1:asCharacter,                    ; rollback journal, both ways
     self:pageSize:sub(self:usable):asCharacter,        ; reserved bytes a page
     #64:asCharacter, #32:asCharacter, #32:asCharacter, ; the payload fractions, fixed
     u32Bytes:value(self:changes),
     u32Bytes:value(self:pageCount),
     u32Bytes:value(self:freelistHead),
     u32Bytes:value(self:freelistCount),
     u32Bytes:value(self:cookie),
     u32Bytes:value(#4),                                ; schema format
     u32Bytes:value(#0),                                ; default cache size
     u32Bytes:value(#0),                                ; largest root page: no autovacuum
     u32Bytes:value(#1),                                ; UTF-8
     u32Bytes:value(#0), u32Bytes:value(#0), u32Bytes:value(#0),   ; user version, incremental vacuum, application id
     zeros:value(#20),
     u32Bytes:value(self:changes),                      ; version-valid-for
     u32Bytes:value(#0)]:join("") }.                    ; the library that wrote it: none SQLite knows

; Everything, written whole. Step 3 of the plan writes a fresh file this way
; and step 4 measures what it costs on a file that exists, which is the
; argument the positioned write waits for.
db:flush := { | pieces, n |
    self:dirty:size:greaterThan(#0):ifTrue({
        self:changes := self:changes:inc.
        self:changed := self:dirty:size.
        self:readBefore := self:reads.
        pieces := []. n := #1.
        { n:lessOrEqual(self:pageCount) }:whileTrue({
            pieces:add(self:page(n)). n := n:inc }).
        ; The file header is rewritten whether or not page 1's tree changed:
        ; the page count and the change counter live there, and a file that
        ; grew under an unchanged schema page kept the old count until
        ; integrity_check named page 191 of 187.
        pieces:atPut(#1, self:fileHeader:concat(pieces:at(#1):copyFrom(#101, pieces:at(#1):size))).
        system:writeFile(self:path, pieces:join("")).
        self:written := self:written:add(self:pageCount:mul(self:pageSize)).
        ; What was written is now what the file holds.
        self:dirty:keysAndValuesDo({ k, o | self:cache:atPut(k, o:bytes(k, self)) }).
        self:cache:atPut(#1, pieces:at(#1)).
        self:dirty := dictionary:new }) }.

; ---------------------------------------------------------------------------
; Bytes, written

u16Bytes := { n | n:shiftRight(#8):bitAnd(#255):asCharacter:concat(n:bitAnd(#255):asCharacter) }.
u32Bytes := { n |
    [n:shiftRight(#24):bitAnd(#255), n:shiftRight(#16):bitAnd(#255),
     n:shiftRight(#8):bitAnd(#255), n:bitAnd(#255)]:collect({ b | b:asCharacter }):join("") }.

zeros := { n | | out, piece |
    out := "". piece := #0:asCharacter.
    { n:greaterThan(#0) }:whileTrue({
        n:bitAnd(#1):equals(#1):ifTrue({ out := out:concat(piece) }).
        piece := piece:concat(piece).
        n := n:shiftRight(#1) }).
    out }.

; A varint: seven bits a byte, high bit for more, up to eight bytes, and a
; ninth carrying all eight bits when the value needs sixty-four. The ninth
; byte is the low eight bits of the value and the rest is the value shifted
; right by eight, which for a negative value is an arithmetic shift, masked
; down to fifty-six bits: the two's complement pattern SQLite stores.
varintBytes := { v | | out, hi, groups, i |
    (v:greaterOrEqual(#0):and({ v:lessThan(#72057594037927936) })):ifElse(       ; 2^56
        { out := [v:bitAnd(#127):asCharacter].
          v := v:shiftRight(#7).
          { v:greaterThan(#0) }:whileTrue({
              out:add(v:bitAnd(#127):bitOr(#128):asCharacter).
              v := v:shiftRight(#7) }).
          ; Built low group first; the format wants high first.
          groups := []. i := out:size.
          { i:greaterOrEqual(#1) }:whileTrue({ groups:add(out:at(i)). i := i:dec }).
          groups:join("") },
        { hi := v:shiftRight(#8):bitAnd(#72057594037927935).                     ; 2^56 - 1
          out := []. i := #7.
          { i:greaterOrEqual(#0) }:whileTrue({
              out:add(hi:shiftRight(i:mul(#7)):bitAnd(#127):bitOr(#128):asCharacter).
              i := i:dec }).
          out:add(v:bitAnd(#255):asCharacter).
          out:join("") }) }.

; A signed integer in n big-endian bytes; the shift is arithmetic, so the
; bytes of a negative value come out in two's complement.
intBytes := { v, n | | out, i |
    out := []. i := n:dec.
    { i:greaterOrEqual(#0) }:whileTrue({
        out:add(v:shiftRight(i:mul(#8)):bitAnd(#255):asCharacter). i := i:dec }).
    out:join("") }.

; The serial type an integer takes: 0 and 1 in no bytes, else the fewest
; bytes that hold it.
intSerial := { v |
    v:equals(#0):ifElse({ #8 },
    { v:equals(#1):ifElse({ #9 },
    { (v:greaterOrEqual(#-128):and({ v:lessOrEqual(#127) })):ifElse({ #1 },
    { (v:greaterOrEqual(#-32768):and({ v:lessOrEqual(#32767) })):ifElse({ #2 },
    { (v:greaterOrEqual(#-8388608):and({ v:lessOrEqual(#8388607) })):ifElse({ #3 },
    { (v:greaterOrEqual(#-2147483648):and({ v:lessOrEqual(#2147483647) })):ifElse({ #4 },
    { (v:greaterOrEqual(#-140737488355328):and({ v:lessOrEqual(#140737488355327) })):ifElse({ #5 },
    { #6 }) }) }) }) }) }) }) }.
serialWidth := [#1, #2, #3, #4, #6, #8].

; Eight bytes of a double from its parts, floatFromBytes inverted: the field
; is the exponent plus 1075, or zero for a subnormal, and the implicit bit is
; taken back off the mantissa.
floatBytes := { parts | | sign, mantissa, e2, field, hi, lo |
    sign := parts:at(#2). mantissa := parts:at(#3). e2 := parts:at(#4).
    mantissa:equals(#0):ifElse(
        { field := #0 },
        { mantissa:lessThan(#4503599627370496):ifElse(                     ; 2^52: no implicit bit
              { field := #0 },
              { field := e2:add(#1075). mantissa := mantissa:sub(#4503599627370496) }) }).
    hi := sign:shiftLeft(#31):bitOr(field:shiftLeft(#20)):bitOr(mantissa:shiftRight(#32)).
    lo := mantissa:bitAnd(#4294967295).
    u32Bytes:value(hi):concat(u32Bytes:value(lo)) }.

; A record from an array of values: the header of serial types, its own
; length in front, then the bodies.
recordBytes := { values | | types, bodies, headerSize, headerBytes |
    types := []. bodies := [].
    values:do({ v |
        v:isNil:ifTrue({ types:add(#0). bodies:add("") }).
        v:isKindOf(integer):ifTrue({ | t |
            t := intSerial:value(v). types:add(t).
            bodies:add(t:greaterOrEqual(#8):ifElse({ "" }, { intBytes:value(v, serialWidth:at(t)) })) }).
        v:isKindOf(real):ifTrue({ types:add(#7). bodies:add(floatBytes:value(v:parts)) }).
        v:isKindOf(string):ifTrue({ types:add(v:size:mul(#2):add(#13)). bodies:add(v) }).
        v:isKindOf(blob):ifTrue({ types:add(v:bytes:size:mul(#2):add(#12)). bodies:add(v:bytes) }) }).
    headerBytes := types:collect({ t | varintBytes:value(t) }):join("").
    ; The header's length counts its own varint, which is one byte until the
    ; header is 127 bytes long and two after.
    headerSize := headerBytes:size:inc.
    headerSize:greaterThan(#127):ifTrue({ headerSize := headerBytes:size:add(#2) }).
    varintBytes:value(headerSize):concat(headerBytes):concat(bodies:join("")) }.

; ---------------------------------------------------------------------------
; A page being written
;
; Cells in key order, each the raw bytes after any child pointer, with the
; key decoded beside it: a rowid for a table page, the entry's values for an
; index page. Serialised to bytes on demand, from the end of the page down,
; with no freeblocks and no fragments, which is one well-formed page among
; the many `integrity_check` accepts.

page := object:new.
page:kind := #13.
page:cells := nil.
page:keys := nil.
page:children := nil.          ; interior pages only, parallel to cells
page:right := #0.              ; interior pages only

page:of := { kind | | p |
    p := self:new.
    p:kind := kind. p:cells := []. p:keys := []. p:children := []. p:right := #0.
    p }.

page:isLeaf := { self:kind:equals(#13):or({ self:kind:equals(#10) }) }.
page:isTable := { self:kind:equals(#13):or({ self:kind:equals(#5) }) }.
page:headerSize := { self:isLeaf:ifElse({ #8 }, { #12 }) }.

; Bytes in use on page `n` of database `d`: the headers, the pointer array
; and every cell with its child pointer.
page:used := { n, d | | total, extra |
    extra := self:isLeaf:ifElse({ #0 }, { #4 }).
    total := n:equals(#1):ifElse({ #100 }, { #0 }):add(self:headerSize):add(self:cells:size:mul(#2)).
    self:cells:do({ c | total := total:add(c:size):add(extra) }).
    total }.
page:fits := { n, d | self:used(n, d):lessOrEqual(d:usable) }.

page:bytes := { n, d | | h, extra, pos, offsets, i, content, pointers, header, free |
    extra := self:isLeaf:ifElse({ #0 }, { #4 }).
    h := n:equals(#1):ifElse({ #100 }, { #0 }).
    ; Cells from the end of the usable area downwards, so the last cell sits
    ; highest and the first lowest, and the content area is the cells in
    ; order from the first.
    pos := d:usable. offsets := []. content := []. i := self:cells:size.
    { i:greaterOrEqual(#1) }:whileTrue({
        pos := pos:sub(self:cells:at(i):size):sub(extra).
        offsets:add(pos).
        i := i:dec }).
    i := #1.
    { i:lessOrEqual(self:cells:size) }:whileTrue({
        self:isLeaf:ifFalse({ content:add(u32Bytes:value(self:children:at(i))) }).
        content:add(self:cells:at(i)).
        i := i:inc }).
    pointers := []. i := offsets:size.
    { i:greaterOrEqual(#1) }:whileTrue({ pointers:add(u16Bytes:value(offsets:at(i))). i := i:dec }).
    header := [self:kind:asCharacter,
               u16Bytes:value(#0),                                       ; no freeblocks
               u16Bytes:value(self:cells:size),
               u16Bytes:value(self:cells:size:equals(#0):ifElse({ d:usable }, { pos }):bitAnd(#65535)),
               #0:asCharacter].                                          ; no fragments
    self:isLeaf:ifFalse({ header:add(u32Bytes:value(self:right)) }).
    free := pos:sub(h):sub(self:headerSize):sub(self:cells:size:mul(#2)).
    free:lessThan(#0):ifTrue({ error:raise("page ":concat(n:asString):concat(" overflowed by ")
        :concat(free:negated:asString):concat(" bytes")) }).
    [n:equals(#1):ifElse({ d:fileHeader }, { "" }),
     header:join(""), pointers:join(""), zeros:value(free), content:join(""),
     zeros:value(d:pageSize:sub(d:usable))]:join("") }.

; A page from its bytes, for changing: every cell copied raw and its key
; decoded. A cell that spills to overflow pages is carried with its pointer,
; which is what keeps a row this program did not write intact when it moves.
decodePage := { d, s, n | | o, h, offsets, extra |
    h := headerAt:value(n).
    o := page:of(u8:value(s, h)).
    offsets := cells:value(s, n).
    extra := o:isLeaf:ifElse({ #0 }, { #4 }).
    o:isLeaf:ifFalse({ o:right := u32:value(s, h:add(#8)) }).
    offsets:do({ at | | start, v, size, local, rowid, end, key |
        start := at:add(extra).
        o:isLeaf:ifFalse({ o:children:add(u32:value(s, at)) }).
        o:isTable:ifElse(
            { o:isLeaf:ifElse(
                  { v := varint:value(s, start). size := v:at(#1).
                    v := varint:value(s, v:at(#2)). rowid := v:at(#1).
                    local := localSize:value(d, size, false).
                    end := v:at(#2):add(local):dec.
                    local:lessThan(size):ifTrue({ end := end:add(#4) }).
                    key := rowid },
                  { v := varint:value(s, start).
                    end := v:at(#2):dec. key := v:at(#1) }) },
            { v := varint:value(s, start). size := v:at(#1).
              local := localSize:value(d, size, true).
              end := v:at(#2):add(local):dec.
              local:lessThan(size):ifTrue({ end := end:add(#4) }).
              key := decodeRecord:value(payload:value(d, s, v:at(#2), size, true)) }).
        o:cells:add(s:copyFrom(start, end)).
        o:keys:add(key) }).
    o }.

; ---------------------------------------------------------------------------
; Putting a cell into a tree
;
; A table tree is a B+tree keyed by rowid: rows live in the leaves, and an
; interior cell is a child and the largest rowid in it. An index tree is a
; B-tree: an interior cell is a child and an entry of its own, everything in
; the child less than it. So a table leaf that splits sends up a copy of its
; last left key, and an index page that splits sends up its middle entry.
; Either way the page that split keeps its number as the left half and the
; new page is the right, so a parent has one cell to add and one child to
; repoint. The root keeps its number too, by moving its contents down into a
; new page when it splits, which is how a tree grows a level.

compareEntry := { a, b | | c, i |
    c := #0. i := #1.
    { c:equals(#0):and({ i:lessOrEqual(a:size) }):and({ i:lessOrEqual(b:size) }) }:whileTrue({
        c := compare:value(a:at(i), b:at(i)). i := i:inc }).
    c }.

keyLess := { isIndex, a, b |
    isIndex:ifElse({ compareEntry:value(a, b):lessThan(#0) }, { a:lessThan(b) }) }.

; Where a key goes among a page's keys: the first position whose key is
; greater, or one past the end.
positionFor := { o, key, isIndex | | i |
    i := #1.
    { i:lessOrEqual(o:keys:size):and({ keyLess:value(isIndex, o:keys:at(i), key):or({
        isIndex:not:and({ o:keys:at(i):equals(key) }) }) }) }:whileTrue({ i := i:inc }).
    i }.

insertAt := { arr, i, v | | out, k |
    out := []. k := #1.
    { k:lessThan(i) }:whileTrue({ out:add(arr:at(k)). k := k:inc }).
    out:add(v).
    { k:lessOrEqual(arr:size) }:whileTrue({ out:add(arr:at(k)). k := k:inc }).
    out }.

; Split page `o` (number n) in two: it keeps the left half, a new page takes
; the right, and the divider goes up as [raw, key, newPage]. The split point
; is where the bytes reach half.
splitPage := { d, o, n, isIndex | | half, sum, k, right, rn, divider, extra |
    extra := o:isLeaf:ifElse({ #0 }, { #4 }).
    half := o:used(n, d):div(#2). sum := #0. k := #0.
    { sum:lessThan(half):and({ k:lessThan(o:cells:size:dec) }) }:whileTrue({
        k := k:inc. sum := sum:add(o:cells:at(k):size):add(extra):add(#2) }).
    k:lessThan(#1):ifTrue({ k := #1 }).
    k:greaterOrEqual(o:cells:size):ifTrue({ k := o:cells:size:dec }).
    rn := d:newPage(o:kind).
    right := d:object(rn).
    (o:isLeaf:and({ isIndex:not })):ifElse(
        { ; Table leaf: cells 1..k stay, k+1.. go right, key k is copied up.
          divider := [varintBytes:value(o:keys:at(k)), o:keys:at(k), rn].
          right:cells := o:cells:copyFrom(k:inc, o:cells:size).
          right:keys := o:keys:copyFrom(k:inc, o:keys:size).
          o:cells := o:cells:copyFrom(#1, k).
          o:keys := o:keys:copyFrom(#1, k) },
        { ; Index page, or a table interior: cell k itself goes up.
          divider := [o:cells:at(k), o:keys:at(k), rn].
          right:cells := o:cells:copyFrom(k:inc, o:cells:size).
          right:keys := o:keys:copyFrom(k:inc, o:keys:size).
          o:isLeaf:ifFalse({
              right:children := o:children:copyFrom(k:inc, o:children:size).
              right:right := o:right.
              o:right := o:children:at(k).
              o:children := o:children:copyFrom(#1, k:dec) }).
          o:cells := o:cells:copyFrom(#1, k:dec).
          o:keys := o:keys:copyFrom(#1, k:dec) }).
    divider }.

; Insert `raw` with `key` under page n. Answers nil, or the divider a split
; produced for the parent to place.
insertCell := { d, n, raw, key, isIndex | | o, i, below |
    o := d:object(n).
    o:isLeaf:ifElse(
        { i := positionFor:value(o, key, isIndex).
          ; The position is past any equal rowid, so the one before it is
          ; the duplicate to refuse.
          (isIndex:not:and({ i:greaterThan(#1) }):and({ o:keys:at(i:dec):equals(key) })):ifTrue({
              error:raise("UNIQUE constraint failed: rowid ":concat(key:asString)) }).
          o:cells := insertAt:value(o:cells, i, raw).
          o:keys := insertAt:value(o:keys, i, key) },
        { i := positionFor:value(o, key, isIndex).
          below := insertCell:value(d, i:greaterThan(o:children:size):ifElse({ o:right }, { o:children:at(i) }),
                                    raw, key, isIndex).
          below:notNil:ifTrue({
              ; The child at i split: it stays as the left half under the
              ; divider, and the new page takes the child's old place.
              i:greaterThan(o:children:size):ifElse(
                  { o:cells:add(below:at(#1)). o:keys:add(below:at(#2)).
                    o:children:add(o:right). o:right := below:at(#3) },
                  { o:cells := insertAt:value(o:cells, i, below:at(#1)).
                    o:keys := insertAt:value(o:keys, i, below:at(#2)).
                    o:children := insertAt:value(o:children, i, o:children:at(i)).
                    o:children:atPut(i:inc, below:at(#3)) }) }) }).
    o:fits(n, d):ifElse({ nil }, { splitPage:value(d, o, n, isIndex) }) }.

; Insert at a tree's root, which keeps its page number however the tree
; grows: when the root splits, its left half moves to a new page and the root
; becomes an interior page over the two.
treeInsert := { d, root, raw, key, isIndex | | divider, o, left, ln |
    divider := insertCell:value(d, root, raw, key, isIndex).
    divider:notNil:ifTrue({
        o := d:object(root).
        ln := d:newPage(o:kind).
        left := d:object(ln).
        left:cells := o:cells. left:keys := o:keys. left:children := o:children. left:right := o:right.
        o:kind := o:isTable:ifElse({ #5 }, { #2 }).
        o:cells := [divider:at(#1)]. o:keys := [divider:at(#2)].
        o:children := [ln]. o:right := divider:at(#3) }) }.

; The largest rowid in a table tree, or nil when it is empty: down the
; right-most path to the last leaf.
lastRowid := { d, n | | p, h, offsets, v |
    p := d:page(n). h := headerAt:value(n).
    offsets := cells:value(p, n).
    u8:value(p, h):equals(#13):ifElse(
        { offsets:size:equals(#0):ifElse({ nil },
              { v := varint:value(p, offsets:at(offsets:size)).
                varint:value(p, v:at(#2)):at(#1) }) },
        { lastRowid:value(d, u32:value(p, h:add(#8))) }) }.

; ---------------------------------------------------------------------------
; B-tree pages

; Where a page's header begins: after the file header on page 1.
headerAt := { n | n:equals(#1):ifElse({ #101 }, { #1 }) }.

; The cell offsets of a page, as one-based indices into the page string.
cells := { p, n | | h, count, first, out, i |
    h := headerAt:value(n).
    count := u16:value(p, h:add(#3)).
    first := h:add(u8:value(p, h):equals(#5):or({ u8:value(p, h):equals(#2) })
        :ifElse({ #12 }, { #8 })).
    out := [].
    i := #0.
    { i:lessThan(count) }:whileTrue({
        out:add(u16:value(p, first:add(i:mul(#2))):inc).
        i := i:inc }).
    out }.

; How much of a payload of `total` bytes stays on the page. A table leaf may
; keep up to U-35 of it; an index page, whose cells are compared on the way
; down, keeps at most a quarter of the usable size so that a page holds at
; least four keys.
localSize := { d, total, isIndex | | maxLocal, minLocal, k |
    maxLocal := isIndex:ifElse({ d:usable:sub(#12):mul(#64):div(#255):sub(#23) },
                               { d:usable:sub(#35) }).
    total:lessOrEqual(maxLocal):ifElse({ total }, {
        minLocal := d:usable:sub(#12):mul(#32):div(#255):sub(#23).
        k := minLocal:add(total:sub(minLocal):mod(d:usable:sub(#4))).
        k:lessOrEqual(maxLocal):ifElse({ k }, { minLocal }) }) }.

; A payload of `total` bytes starting at `at` on page `p`: the local part,
; and then the overflow chain, each page a pointer and then bytes.
payload := { d, p, at, total, isIndex | | local, out, next, page, take, remaining |
    local := localSize:value(d, total, isIndex).
    out := p:copyFrom(at, at:add(local):dec).
    local:lessThan(total):ifTrue({
        next := u32:value(p, at:add(local)).
        remaining := total:sub(local).
        { remaining:greaterThan(#0) }:whileTrue({
            page := d:page(next).
            take := remaining:lessThan(d:usable:sub(#4)):ifElse({ remaining }, { d:usable:sub(#4) }).
            out := out:concat(page:copyFrom(#5, take:add(#4))).
            remaining := remaining:sub(take).
            next := u32:value(page, #1) }) }).
    out }.

; Every row of a table tree, in rowid order: the block is given the rowid and
; the payload. Interior cells are a child and the largest rowid in it; the
; right-most child holds the rest.
eachRow := { d, n, block | | p, h, kind, offsets, i, at, v, size, rowid |
    p := d:page(n).
    h := headerAt:value(n).
    kind := u8:value(p, h).
    offsets := cells:value(p, n).
    kind:equals(#13):ifElse(
        { offsets:do({ at |
              v := varint:value(p, at). size := v:at(#1).
              v := varint:value(p, v:at(#2)). rowid := v:at(#1).
              block:value(rowid, payload:value(d, p, v:at(#2), size, false)) }) },
        { kind:equals(#5):ifFalse({
              error:raise("page ":concat(n:asString):concat(" is not a table page")) }).
          offsets:do({ at | eachRow:value(d, u32:value(p, at), block) }).
          eachRow:value(d, u32:value(p, h:add(#8)), block) }) }.

; One row by rowid: descend to the leaf that would hold it, then look. Answers
; the payload or nil.
findRow := { d, n, want | | p, h, kind, offsets, found, i, at, v, size, rowid, child |
    p := d:page(n).
    h := headerAt:value(n).
    kind := u8:value(p, h).
    offsets := cells:value(p, n).
    found := nil.
    kind:equals(#13):ifElse(
        { i := #1.
          { found:isNil:and({ i:lessOrEqual(offsets:size) }) }:whileTrue({
              at := offsets:at(i).
              v := varint:value(p, at). size := v:at(#1).
              v := varint:value(p, v:at(#2)). rowid := v:at(#1).
              rowid:equals(want):ifTrue({ found := payload:value(d, p, v:at(#2), size, false) }).
              i := i:inc }).
          found },
        { child := nil. i := #1.
          { child:isNil:and({ i:lessOrEqual(offsets:size) }) }:whileTrue({
              at := offsets:at(i).
              want:lessOrEqual(varint:value(p, at:add(#4)):at(#1)):ifTrue({
                  child := u32:value(p, at) }).
              i := i:inc }).
          child:isNil:ifTrue({ child := u32:value(p, h:add(#8)) }).
          findRow:value(d, child, want) }) }.

; Every entry of an index tree whose first column equals `want`, in index
; order: the block is given the entry's record, whose last value is the rowid.
; An index cell is a record on a leaf, and a child then a record on an interior
; page, where the record is an entry in its own right and everything in the
; child before it is less. So the walk is an in-order traversal that prunes:
; a child is skipped when its cell's key is already below `want`, and the
; walk stops at the first key above it, since equal keys are contiguous.
; Answers whether the walk has passed `want`, so a caller up the tree stops.
eachIndexMatch := { d, n, want, block | | p, h, kind, offsets, i, at, v, size, entry, c, past, isLeaf |
    p := d:page(n).
    h := headerAt:value(n).
    kind := u8:value(p, h).
    isLeaf := kind:equals(#10).
    isLeaf:or({ kind:equals(#2) }):ifFalse({
        error:raise("page ":concat(n:asString):concat(" is not an index page")) }).
    offsets := cells:value(p, n).
    past := false. i := #1.
    { past:not:and({ i:lessOrEqual(offsets:size) }) }:whileTrue({
        at := offsets:at(i).
        isLeaf:ifFalse({ at := at:add(#4) }).
        v := varint:value(p, at). size := v:at(#1).
        entry := decodeRecord:value(payload:value(d, p, v:at(#2), size, true)).
        c := compare:value(entry:at(#1), want).
        ; The child before this key can hold equals only when the key is
        ; not already below `want`.
        isLeaf:not:and({ c:greaterOrEqual(#0) }):ifTrue({
            past := eachIndexMatch:value(d, u32:value(p, offsets:at(i)), want, block) }).
        c:equals(#0):ifTrue({ block:value(entry) }).
        c:greaterThan(#0):ifTrue({ past := true }).
        i := i:inc }).
    past:not:and({ isLeaf:not }):ifTrue({
        past := eachIndexMatch:value(d, u32:value(p, h:add(#8)), want, block) }).
    past }.

; ---------------------------------------------------------------------------
; Records

; The values of a record, as an array. Fewer values than the table has
; columns is a table altered since the row was written, and the rest are NULL
; to the caller.
decodeRecord := { s | | v, headerSize, at, types, values, bodyAt, t, n |
    v := varint:value(s, #1).
    headerSize := v:at(#1). at := v:at(#2).
    types := [].
    { at:lessOrEqual(headerSize) }:whileTrue({
        v := varint:value(s, at). types:add(v:at(#1)). at := v:at(#2) }).
    values := [].
    bodyAt := headerSize:inc.
    types:do({ t |
        t:equals(#0):ifTrue({ values:add(nil) }).
        t:greaterOrEqual(#1):and({ t:lessOrEqual(#6) }):ifTrue({
            n := [#1, #2, #3, #4, #6, #8]:at(t).
            values:add(signedBytes:value(s, bodyAt, n)).
            bodyAt := bodyAt:add(n) }).
        t:equals(#7):ifTrue({
            values:add(real:of(floatFromBytes:value(s, bodyAt))).
            bodyAt := bodyAt:add(#8) }).
        t:equals(#8):ifTrue({ values:add(#0) }).
        t:equals(#9):ifTrue({ values:add(#1) }).
        t:greaterOrEqual(#12):ifTrue({
            n := t:sub(#12):div(#2).
            t:mod(#2):equals(#0):ifElse(
                { values:add(blob:of(n:equals(#0):ifElse({ "" }, { s:copyFrom(bodyAt, bodyAt:add(n):dec) }))) },
                { values:add(n:equals(#0):ifElse({ "" }, { s:copyFrom(bodyAt, bodyAt:add(n):dec) })) }).
            bodyAt := bodyAt:add(n) }) }).
    values }.

; ---------------------------------------------------------------------------
; SQL, the tokens
;
; Words, numbers, 'text' with '' inside it, X'hex', "quoted names", and the
; punctuation this file's SQL has. Each token is [kind, text]: 'word, 'number,
; 'text, 'blob, 'name or 'punct.

isWordStart := { c | | b | b := c:asByte.
    b:greaterOrEqual(#65):and({ b:lessOrEqual(#90) })
        :or({ b:greaterOrEqual(#97):and({ b:lessOrEqual(#122) }) })
        :or({ c:equals("_") }):or({ b:greaterOrEqual(#128) }) }.
isDigit := { c | | b | b := c:asByte. b:greaterOrEqual(#48):and({ b:lessOrEqual(#57) }) }.
isWordChar := { c | isWordStart:value(c):or({ isDigit:value(c) }) }.
isSpace := { c | c:equals(" "):or({ c:equals("\n") }):or({ c:equals("\t") }):or({ c:equals("\r") }) }.

; A quoted run with the quote doubled inside, the quote already consumed.
quoted := { s, q | | out, done |
    out := "". done := false.
    { done:not }:whileTrue({
        s:atEnd:ifTrue({ error:raise("unterminated string") }).
        s:peek:equals(q):ifElse(
            { s:step.
              s:peek:equals(q):ifElse({ out := out:concat(q). s:step }, { done := true }) },
            { out := out:concat(s:next) }) }).
    out }.

hexValue := { c | | b | b := c:asByte.
    b:lessOrEqual(#57):ifElse({ b:sub(#48) },
        { b:lessOrEqual(#70):ifElse({ b:sub(#55) }, { b:sub(#87) }) }) }.

unhex := { h | | out, i |
    h:size:mod(#2):equals(#1):ifTrue({ error:raise("odd number of hex digits in a blob") }).
    out := []. i := #1.
    { i:lessThan(h:size) }:whileTrue({
        out:add(hexValue:value(h:at(i)):mul(#16):add(hexValue:value(h:at(i:inc))):asCharacter).
        i := i:add(#2) }).
    out:join("") }.

tokenize := { text | | s, out, c, word, from, push |
    s := scan:on(text). out := [].
    ; A token is [kind, text, from, to], the last two the positions in the
    ; source, so that a CREATE statement can be stored as it was written.
    push := { kind, t | out:add([kind, t, from, s:pos:dec]) }.
    { s:atEnd:not }:whileTrue({
        c := s:peek. from := s:pos.
        isSpace:value(c):ifElse({ s:step },
        { (c:equals("-"):and({ s:peekAt(#1):equals("-") })):ifElse(
            { s:skipWhile({ ch | ch:notEquals("\n") }) },
        { isWordStart:value(c):ifElse(
            { word := s:takeWhile(isWordChar).
              (word:asUppercase:equals("X"):and({ s:peek:equals("'") })):ifElse(
                  { s:step. push:value('blob, unhex:value(quoted:value(s, "'"))) },
                  { push:value('word, word) }) },
        { (isDigit:value(c):or({ c:equals("."):and({ s:peekAt(#1):notNil }):and({ isDigit:value(s:peekAt(#1)) }) })):ifElse(
            { word := s:takeWhile({ ch | isDigit:value(ch):or({ ch:equals(".") }) }).
              (s:peek:notNil:and({ s:peek:asUppercase:equals("E") })):ifTrue({
                  word := word:concat(s:next).
                  (s:peek:equals("+"):or({ s:peek:equals("-") })):ifTrue({ word := word:concat(s:next) }).
                  word := word:concat(s:takeWhile(isDigit)) }).
              push:value('number, word) },
        { c:equals("'"):ifElse({ s:step. push:value('text, quoted:value(s, "'")) },
        { c:equals("\""):ifElse({ s:step. push:value('name, quoted:value(s, "\"")) },
        { c:equals("`"):ifElse({ s:step. push:value('name, quoted:value(s, "`")) },
        { c:equals("["):ifElse({ s:step. word := s:takeUntil({ ch | ch:equals("]") }). s:step. push:value('name, word) },
        { "(),;*=.<>-":indexOf(c):notNil:ifElse({ s:step. push:value('punct, c) },
            ; Anything else is a byte this SQL has no use for.
            { error:raise("unexpected character: ":concat(c)) }) }) }) }) }) }) }) }) }) }).
    out }.

; Statements: the tokens split at `;`.
statements := { tokens | | out, current |
    out := []. current := [].
    tokens:do({ t |
        (t:at(#1):equals('punct):and({ t:at(#2):equals(";") })):ifElse(
            { current:size:greaterThan(#0):ifTrue({ out:add(current) }). current := [] },
            { current:add(t) }) }).
    current:size:greaterThan(#0):ifTrue({ out:add(current) }).
    out }.

; ---------------------------------------------------------------------------
; The schema
;
; `sqlite_schema` is the table at page 1, and every other table is a row in
; it with its root page and its CREATE statement. The columns come from
; parsing that statement: a name, a type of zero or more words, and then
; constraints up to the next comma, of which INTEGER PRIMARY KEY is the one
; that changes what a column is.

table := object:new.
table:name := "".
table:root := #0.
table:columns := [].           ; each [name, affinity, isRowid]
table:indexes := [].           ; each [name, root, column names], plain ascending BINARY ones
table:maxRowid := nil.         ; the largest rowid, once it has been looked for

; The affinity rules, from the declared type: INT anywhere is INTEGER; CHAR,
; CLOB or TEXT is TEXT; BLOB or no type is BLOB; REAL, FLOA or DOUB is REAL;
; anything else NUMERIC.
affinityOf := { typeText | | t |
    t := typeText:asUppercase.
    t:indexOf("INT"):notNil:ifElse({ 'integer },
        { t:indexOf("CHAR"):notNil:or({ t:indexOf("CLOB"):notNil }):or({ t:indexOf("TEXT"):notNil }):ifElse({ 'text },
            { t:equals(""):or({ t:indexOf("BLOB"):notNil }):ifElse({ 'blob },
                { t:indexOf("REAL"):notNil:or({ t:indexOf("FLOA"):notNil }):or({ t:indexOf("DOUB"):notNil }):ifElse({ 'real },
                    { 'numeric }) }) }) }) }.

constraintWords := ["CONSTRAINT", "PRIMARY", "NOT", "NULL", "UNIQUE", "CHECK", "DEFAULT",
                    "COLLATE", "REFERENCES", "GENERATED", "AS"].
isConstraintWord := { w | constraintWords:indexOf(w:asUppercase):notNil }.

; The tokens between the outer parentheses of a CREATE TABLE, split at the
; commas that are not inside parentheses of their own.
columnsFromSql := { sql | | tokens, i, depth, groups, current, out, name, typeWords, isPk, j, t, inType |
    tokens := tokenize:value(sql).
    i := #1.
    { i:lessOrEqual(tokens:size):and({ (tokens:at(i):at(#1):equals('punct):and({ tokens:at(i):at(#2):equals("(") })):not }) }:whileTrue({ i := i:inc }).
    i := i:inc.
    depth := #0. groups := []. current := [].
    { i:lessOrEqual(tokens:size):and({ depth:greaterOrEqual(#0) }) }:whileTrue({
        t := tokens:at(i).
        t:at(#1):equals('punct):and({ t:at(#2):equals("(") }):ifTrue({ depth := depth:inc }).
        t:at(#1):equals('punct):and({ t:at(#2):equals(")") }):ifTrue({ depth := depth:dec }).
        depth:greaterOrEqual(#0):ifTrue({
            (t:at(#1):equals('punct):and({ t:at(#2):equals(",") }):and({ depth:equals(#0) })):ifElse(
                { groups:add(current). current := [] },
                { current:add(t) }) }).
        i := i:inc }).
    current:size:greaterThan(#0):ifTrue({ groups:add(current) }).
    out := [].
    groups:do({ g |
        ; A table constraint rather than a column begins with one of the words.
        (g:at(#1):at(#1):equals('word):and({ isConstraintWord:value(g:at(#1):at(#2)) })
            :and({ g:at(#1):at(#2):asUppercase:equals("PRIMARY"):or({ g:at(#1):at(#2):asUppercase:equals("UNIQUE") })
                :or({ g:at(#1):at(#2):asUppercase:equals("CHECK") }):or({ g:at(#1):at(#2):asUppercase:equals("CONSTRAINT") })
                :or({ g:at(#1):at(#2):asUppercase:equals("FOREIGN") }) })):ifFalse({
            name := g:at(#1):at(#2).
            typeWords := []. isPk := false. j := #2. inType := true.
            { j:lessOrEqual(g:size) }:whileTrue({
                t := g:at(j).
                inType:and({ t:at(#1):equals('word) }):and({ isConstraintWord:value(t:at(#2)):not }):ifElse(
                    { typeWords:add(t:at(#2)) },
                    { inType:and({ t:at(#1):equals('punct) }):and({ t:at(#2):notEquals(",") }):ifElse(
                          { nil },                                 ; the (n) of VARCHAR(n)
                          { inType := false }) }).
                inType:not:and({ t:at(#1):equals('word) }):and({ t:at(#2):asUppercase:equals("PRIMARY") }):ifTrue({
                    (j:lessThan(g:size):and({ g:at(j:inc):at(#2):asUppercase:equals("KEY") })):ifTrue({
                        ; INTEGER PRIMARY KEY, exactly that type, is the rowid.
                        typeWords:size:equals(#1):and({ typeWords:at(#1):asUppercase:equals("INTEGER") }):ifTrue({
                            isPk := true }) }) }).
                inType:and({ t:at(#1):equals('number) }):ifTrue({ nil }).
                j := j:inc }).
            out:add([name, affinityOf:value(typeWords:join(" ")), isPk]) }) }).
    out }.

; `CREATE INDEX name ON table (col, col)`. An index this reader can use is on
; plain column names in ascending BINARY order and over the whole table; one
; with DESC, COLLATE, an expression or a WHERE is left alone, since an entry
; in it is not in the order the walk assumes. Answers the column names, or nil.
indexColumnsFromSql := { sql | | tokens, i, out, plain, t |
    tokens := tokenize:value(sql).
    i := #1.
    { i:lessOrEqual(tokens:size):and({ (tokens:at(i):at(#1):equals('punct):and({ tokens:at(i):at(#2):equals("(") })):not }) }:whileTrue({ i := i:inc }).
    i := i:inc.
    out := []. plain := true.
    { i:lessOrEqual(tokens:size):and({ (tokens:at(i):at(#1):equals('punct):and({ tokens:at(i):at(#2):equals(")") })):not }) }:whileTrue({
        t := tokens:at(i).
        (t:at(#1):equals('word):or({ t:at(#1):equals('name) })):ifElse(
            { (t:at(#2):asUppercase:equals("DESC"):or({ t:at(#2):asUppercase:equals("COLLATE") })
                :or({ t:at(#2):asUppercase:equals("ASC") })):ifElse(
                  { t:at(#2):asUppercase:equals("ASC"):ifFalse({ plain := false }) },
                  { out:add(t:at(#2)) }) },
            { (t:at(#1):equals('punct):and({ t:at(#2):equals(",") })):ifFalse({ plain := false }) }).
        i := i:inc }).
    ; Anything after the closing parenthesis is a WHERE, and a partial index.
    i:lessThan(tokens:size):ifTrue({ plain := false }).
    plain:and({ out:size:greaterThan(#0) }):ifElse({ out }, { nil }) }.

schemaTable := { | t |
    t := table:new.
    t:name := "sqlite_schema".
    t:root := #1.
    t:columns := [["type", 'text, false], ["name", 'text, false], ["tbl_name", 'text, false],
                  ["rootpage", 'integer, false], ["sql", 'text, false]].
    t }.

; The tables in a database, by lower-cased name.
loadSchema := { d | | out, t |
    out := dictionary:new.
    out:atPut("sqlite_schema", schemaTable:value).
    out:atPut("sqlite_master", out:at("sqlite_schema")).
    eachRow:value(d, #1, { rowid, p | | r |
        r := decodeRecord:value(p).
        r:at(#1):equals("table"):ifTrue({
            t := table:new.
            t:name := r:at(#2).
            t:root := r:at(#4).
            t:columns := columnsFromSql:value(r:at(#5)).
            t:indexes := [].
            out:atPut(t:name:asLowercase, t) }) }).
    ; Indexes second, since one may precede its table in the schema. An
    ; automatic index has no SQL and is skipped: its columns are in the
    ; table's constraints, which this reader does not follow.
    eachRow:value(d, #1, { rowid, p | | r, cols |
        r := decodeRecord:value(p).
        (r:at(#1):equals("index"):and({ r:at(#5):notNil })):ifTrue({
            cols := indexColumnsFromSql:value(r:at(#5)).
            (cols:notNil:and({ out:includes(r:at(#3):asLowercase) })):ifTrue({
                out:at(r:at(#3):asLowercase):indexes:add([r:at(#2), r:at(#4), cols]) }) }) }).
    out }.

; ---------------------------------------------------------------------------
; SELECT
;
; Parsed into: the columns wanted (each a name, or `*`), the table, the
; WHERE as [column, value] or nil, and the ORDER BY as a list of columns.
; The parser is a cursor over the statement's tokens, and past the end it
; reads an 'end token rather than falling off the array.

tok := { tokens, i | i:greaterThan(tokens:size):ifElse({ ['end, ""] }, { tokens:at(i) }) }.

; Punctuation is matched by kind as well as text: a blob of the one byte
; `)` or the text `','` is a value, and the first sweep of the writer found
; a value list ending at one.
isPunct := { tokens, i, ch | | t | t := tok:value(tokens, i). t:at(#1):equals('punct):and({ t:at(#2):equals(ch) }) }.

expect := { tokens, i, text |
    (i:greaterThan(tokens:size):or({ tok:value(tokens, i):at(#2):asUppercase:notEquals(text:asUppercase) })):ifTrue({
        error:raise("expected ":concat(text):concat(i:greaterThan(tokens:size):ifElse({ " at the end" },
            { " and found ":concat(tokens:at(i):at(#2)) }))) }).
    i:inc }.

isWord := { tokens, i, text |
    i:lessOrEqual(tokens:size):and({ tok:value(tokens, i):at(#1):equals('word) })
        :and({ tok:value(tokens, i):at(#2):asUppercase:equals(text) }) }.

; A literal: a number with an optional sign, text, a blob, or NULL. Answers
; the value and the index after it.
numberLiteral := { text, negative | | signed |
    ; The sign goes on before the digits are read, so that -9223372036854775808
    ; is the integer it is rather than an overflow negated: SQLite reads the
    ; minimum the same way, and a corpus row found the difference.
    signed := negative:ifElse({ "-":concat(text) }, { text }).
    (text:indexOf("."):isNil:and({ text:asUppercase:indexOf("E"):isNil })):ifElse(
        { { signed:asInteger }:onError({ e |
              ; Too large for an integer: SQLite reads it as a real.
              real:of(floatParts:value(signed:asFloat)) }) },
        { real:of(floatParts:value(signed:asFloat)) }) }.

literal := { tokens, i | | t, negative |
    t := tok:value(tokens, i).
    t:at(#1):equals('end):ifTrue({ error:raise("a value is missing at the end") }).
    negative := false.
    (t:at(#1):equals('punct):and({ t:at(#2):equals("-") })):ifTrue({
        negative := true. i := i:inc. t := tok:value(tokens, i) }).
    t:at(#1):equals('number):ifElse({ [numberLiteral:value(t:at(#2), negative), i:inc] },
        { t:at(#1):equals('text):ifElse({ [t:at(#2), i:inc] },
            { t:at(#1):equals('blob):ifElse({ [blob:of(t:at(#2)), i:inc] },
                { (t:at(#1):equals('word):and({ t:at(#2):asUppercase:equals("NULL") })):ifElse(
                    { [nil, i:inc] },
                    { error:raise("not a literal: ":concat(t:at(#2))) }) }) }) }) }.

; A column reference: a name, optionally qualified by the table.
columnRef := { tokens, i | | name |
    name := tok:value(tokens, i):at(#2).
    i := i:inc.
    (i:lessOrEqual(tokens:size):and({ tok:value(tokens, i):at(#1):equals('punct) }):and({ tok:value(tokens, i):at(#2):equals(".") })):ifTrue({
        name := tok:value(tokens, i:inc):at(#2). i := i:add(#2) }).
    [name, i] }.

parseSelect := { tokens | | i, columns, tableName, where, order, r, done |
    i := expect:value(tokens, #1, "SELECT").
    columns := []. done := false.
    { done:not }:whileTrue({
        (tok:value(tokens, i):at(#1):equals('punct):and({ tok:value(tokens, i):at(#2):equals("*") })):ifElse(
            { columns:add("*"). i := i:inc },
            { r := columnRef:value(tokens, i). columns:add(r:at(#1)). i := r:at(#2) }).
        isPunct:value(tokens, i, ","):ifElse(
            { i := i:inc }, { done := true }) }).
    i := expect:value(tokens, i, "FROM").
    tableName := tok:value(tokens, i):at(#2). i := i:inc.
    where := nil. order := [].
    isWord:value(tokens, i, "WHERE"):ifTrue({
        i := i:inc.
        r := columnRef:value(tokens, i). i := r:at(#2).
        i := expect:value(tokens, i, "=").
        where := [r:at(#1), nil].
        r := literal:value(tokens, i). i := r:at(#2).
        where:atPut(#2, r:at(#1)) }).
    isWord:value(tokens, i, "ORDER"):ifTrue({
        i := i:inc.
        i := expect:value(tokens, i, "BY").
        done := false.
        { done:not }:whileTrue({
            r := columnRef:value(tokens, i). i := r:at(#2).
            order:add(r:at(#1)).
            isWord:value(tokens, i, "ASC"):ifTrue({ i := i:inc }).
            isPunct:value(tokens, i, ","):ifElse(
                { i := i:inc }, { done := true }) }) }).
    i:lessOrEqual(tokens:size):ifTrue({
        error:raise("this SELECT goes on past what is understood, at: ":concat(tok:value(tokens, i):at(#2))) }).
    [columns, tableName, where, order] }.

; ---------------------------------------------------------------------------
; Running a SELECT

; Which column a name is: an index into the record, or 'rowid. `rowid` and
; its aliases, and an INTEGER PRIMARY KEY column, are the rowid.
resolve := { t, name | | found, i, lower |
    lower := name:asLowercase.
    found := nil. i := #1.
    { found:isNil:and({ i:lessOrEqual(t:columns:size) }) }:whileTrue({
        t:columns:at(i):at(#1):asLowercase:equals(lower):ifTrue({
            found := t:columns:at(i):at(#3):ifElse({ 'rowid }, { i }) }).
        i := i:inc }).
    found:isNil:ifTrue({
        (lower:equals("rowid"):or({ lower:equals("_rowid_") }):or({ lower:equals("oid") })):ifElse(
            { found := 'rowid },
            { error:raise("no such column: ":concat(name)) }) }).
    found }.

; The affinity of a column reference, for the comparison rules.
affinityAt := { t, which |
    which:equals('rowid):ifElse({ 'integer }, { t:columns:at(which):at(#2) }) }.

; A row's value at a resolved column.
valueAt := { rowid, values, which |
    which:equals('rowid):ifElse({ rowid },
        { which:greaterThan(values:size):ifElse({ nil }, { values:at(which) }) }) }.

; Text that is a well-formed number, as a number; else nil. SQLite's rule for
; NUMERIC affinity: an integer literal if it is one and fits, else a real.
numberFromText := { s | | t |
    t := s:trim.
    t:equals(""):ifElse({ nil }, {
        { | n | n := t:asInteger. n }:onError({ e |
            { | f | f := t:asFloat. real:of(floatParts:value(f)) }:onError({ e2 | nil }) }) }) }.

; Applying an affinity to a literal before a comparison: a column with
; numeric affinity makes a numeric-looking text a number, a column with text
; affinity makes a number text, and nothing happens to a blob or a NULL.
applyAffinity := { v, affinity | | n |
    v:isNil:or({ v:isKindOf(blob) }):ifElse({ v }, {
        (affinity:equals('integer):or({ affinity:equals('real) }):or({ affinity:equals('numeric) })):ifElse(
            { v:isKindOf(string):ifElse({ n := numberFromText:value(v). n:isNil:ifElse({ v }, { n }) }, { v }) },
            { affinity:equals('text):ifElse(
                { isNumber:value(v):ifElse({ render:value(v) }, { v }) },
                { v }) }) }) }.

; Where the output goes: gathered and written once.
out := [].
emit := { line | out:add(line):add("\n") }.

runSelect := { d, tables, parsed | | t, wanted, whereCol, whereVal, orderCols, realColumns, rows, keep, index |
    t := tables:at(parsed:at(#2):asLowercase, nil).
    t:isNil:ifTrue({ error:raise("no such table: ":concat(parsed:at(#2))) }).
    ; The columns to print, resolved; `*` is every column of the table.
    wanted := [].
    parsed:at(#1):do({ c |
        c:equals("*"):ifElse(
            { [#1, t:columns:size]:loop({ i |
                  wanted:add(t:columns:at(i):at(#3):ifElse({ 'rowid }, { i })) }) },
            { wanted:add(resolve:value(t, c)) }) }).
    whereCol := nil. whereVal := nil.
    parsed:at(#3):notNil:ifTrue({
        whereCol := resolve:value(t, parsed:at(#3):at(#1)).
        whereVal := applyAffinity:value(parsed:at(#3):at(#2), affinityAt:value(t, whereCol)) }).
    orderCols := parsed:at(#4):collect({ c | resolve:value(t, c) }).
    ; A REAL column stores a whole number as an integer to save the bytes, and
    ; it is a real again on the way out: the one place a column's declared
    ; type changes what a record says.
    realColumns := [].
    [#1, t:columns:size]:loop({ i |
        t:columns:at(i):at(#2):equals('real):ifTrue({ realColumns:add(i) }) }).

    rows := [].
    keep := { rowid, values |
        realColumns:do({ i |
            (i:lessOrEqual(values:size):and({ values:at(i):isKindOf(integer) })):ifTrue({
                values:atPut(i, real:of(floatParts:value(values:at(i):asFloat))) }) }).
        (whereCol:isNil:or({ whereVal:notNil:and({ compare:value(valueAt:value(rowid, values, whereCol), whereVal):equals(#0) }) })):ifTrue({
            rows:add([rowid, values]) }) }.

    ; An index whose first column is the WHERE's, if there is one.
    index := nil.
    (whereCol:notNil:and({ whereCol:notEquals('rowid) }):and({ whereVal:notNil })):ifTrue({
        t:indexes:do({ ix |
            index:isNil:and({ resolve:value(t, ix:at(#3):at(#1)):equals(whereCol) }):ifTrue({ index := ix }) }) }).

    ; By rowid when the WHERE names it; through the index when one covers the
    ; column, each matching entry's rowid fetched from the table; else every
    ; row. The three answer the same rows, and differ in pages read.
    (whereCol:notNil:and({ whereCol:equals('rowid) })):ifElse(
        { whereVal:isKindOf(integer):ifTrue({ | p |
              p := findRow:value(d, t:root, whereVal).
              p:notNil:ifTrue({ keep:value(whereVal, decodeRecord:value(p)) }) }).
          whereVal:isKindOf(real):ifTrue({ | f, n |
              ; A real equal to an integer finds that rowid; any other finds none.
              f := whereVal:value.
              f:equals(f:floor:asFloat):ifTrue({ | p |
                  n := f:floor.
                  p := findRow:value(d, t:root, n).
                  p:notNil:ifTrue({ keep:value(n, decodeRecord:value(p)) }) }) }) },
        { index:notNil:ifElse(
            { eachIndexMatch:value(d, index:at(#2), whereVal, { entry | | rowid, p |
                  rowid := entry:at(entry:size).
                  p := findRow:value(d, t:root, rowid).
                  p:isNil:ifTrue({ error:raise("index ":concat(index:at(#1)):concat(" names rowid ")
                      :concat(rowid:asString):concat(" and the table has no such row")) }).
                  keep:value(rowid, decodeRecord:value(p)) }) },
            { eachRow:value(d, t:root, { rowid, p | keep:value(rowid, decodeRecord:value(p)) }) }) }).

    orderCols:size:greaterThan(#0):ifTrue({
        rows := rows:sorted({ a, b | | c, i |
            c := #0. i := #1.
            { c:equals(#0):and({ i:lessOrEqual(orderCols:size) }) }:whileTrue({
                c := compare:value(valueAt:value(a:at(#1), a:at(#2), orderCols:at(i)),
                                   valueAt:value(b:at(#1), b:at(#2), orderCols:at(i))).
                i := i:inc }).
            c:equals(#0):ifTrue({ c := compare:value(a:at(#1), b:at(#1)) }).
            c:lessThan(#0) }) }).

    rows:do({ row |
        emit:value(wanted:collect({ w | render:value(valueAt:value(row:at(#1), row:at(#2), w)) }):join("|")) }) }.

; ---------------------------------------------------------------------------
; CREATE TABLE, CREATE INDEX, INSERT, and PRAGMA page_size
;
; Step 3 of the plan: the writer, from nothing. Each statement changes pages
; in memory and the file is written whole at the end, which is enough for a
; fresh file and is what step 4 measures against on a file that exists.

; A statement's text as written, from its first token to its last.
statementText := { text, st | text:copyFrom(st:at(#1):at(#3), st:at(st:size):at(#4)) }.

; A real that is a whole number and fits is stored as the integer; SQLite
; does the same, for NUMERIC affinity as the rule and for REAL as the disk
; trick the reader undoes.
integralOf := { v | | f |
    f := v:value.
    (f:abs:lessThan(9.2e18):and({ f:equals(f:floor:asFloat) })):ifElse({ f:floor }, { v }) }.

; The affinity applied to a value on its way into a column: text that reads
; as a number becomes one under a numeric affinity, a number becomes text
; under TEXT, and a blob or a NULL is left alone.
storeAffinity := { v, affinity | | n |
    v:isNil:or({ v:isKindOf(blob) }):ifElse({ v }, {
        affinity:equals('text):ifElse(
            { isNumber:value(v):ifElse({ render:value(v) }, { v }) },
        { affinity:equals('blob):ifElse({ v }, {
            ; INTEGER, NUMERIC and REAL: a numeric text is read, and a whole real
            ; becomes the integer.
            n := v:isKindOf(string):ifElse({ numberFromText:value(v) }, { v }).
            n:isNil:ifElse({ v },
                { n:isKindOf(real):ifElse({ integralOf:value(n) }, { n }) }) }) }) }) }.

; What a value written to the INTEGER PRIMARY KEY column means as a rowid.
rowidOf := { v | | n |
    v:isKindOf(integer):ifElse({ v }, {
        n := v:isKindOf(string):ifElse({ numberFromText:value(v) }, { v }).
        n:isKindOf(real):ifTrue({ n := integralOf:value(n) }).
        n:isKindOf(integer):ifElse({ n }, { error:raise("datatype mismatch") }) }) }.

; One row into a table and each of its indexes. `values` is one per column,
; affinities applied; the rowid is given or is one past the largest.
insertRow := { d, t, values, rowidGiven | | rowid, record, payload, raw, maxLocal |
    rowid := rowidGiven.
    rowid:isNil:ifTrue({
        t:maxRowid:isNil:ifTrue({ t:maxRowid := lastRowid:value(d, t:root) }).
        rowid := t:maxRowid:isNil:ifElse({ #1 }, {
            t:maxRowid:equals(#9223372036854775807):ifTrue({
                error:raise("database or disk is full: no rowid is left to assign") }).
            t:maxRowid:inc }) }).
    ; The rowid column's value in the record is NULL: it is the rowid.
    record := [].
    [#1, t:columns:size]:loop({ i |
        record:add(t:columns:at(i):at(#3):ifElse({ nil }, { i:lessOrEqual(values:size):ifElse({ values:at(i) }, { nil }) })) }).
    payload := recordBytes:value(record).
    maxLocal := d:usable:sub(#35).
    payload:size:greaterThan(maxLocal):ifTrue({
        error:raise("a row of ":concat(payload:size:asString):concat(" bytes needs an overflow page, and this program does not write those (")
            :concat(maxLocal:asString):concat(" fit)")) }).
    raw := varintBytes:value(payload:size):concat(varintBytes:value(rowid)):concat(payload).
    treeInsert:value(d, t:root, raw, rowid, false).
    (t:maxRowid:isNil:or({ rowid:greaterThan(t:maxRowid) })):ifTrue({ t:maxRowid := rowid }).
    t:indexes:do({ ix | | entry |
        entry := ix:at(#3):collect({ name | | which |
            which := resolve:value(t, name).
            which:equals('rowid):ifElse({ rowid }, { values:at(which) }) }).
        entry:add(rowid).
        payload := recordBytes:value(entry).
        maxLocal := d:usable:sub(#12):mul(#64):div(#255):sub(#23).
        payload:size:greaterThan(maxLocal):ifTrue({
            error:raise("an index entry of ":concat(payload:size:asString):concat(" bytes needs an overflow page, and this program does not write those")) }).
        raw := varintBytes:value(payload:size):concat(payload).
        treeInsert:value(d, ix:at(#2), raw, entry, true) }).
    rowid }.

; A row of sqlite_schema, which is a table like any other with page 1 as
; its root and no rowid column of its own.
schemaRow := { d, tables, kind, name, tblName, root, sql |
    insertRow:value(d, tables:at("sqlite_schema"), [kind, name, tblName, root, sql], nil).
    d:cookie := d:cookie:inc }.

; `text` is the whole source, since the tokens' positions are into it.
createTable := { d, tables, st, text | | name, t, sql |
    st:size:lessThan(#4):ifTrue({ error:raise("CREATE TABLE needs a name and columns") }).
    name := tok:value(st, #3):at(#2).
    tables:includes(name:asLowercase):ifTrue({ error:raise("table ":concat(name):concat(" already exists")) }).
    t := table:new.
    t:name := name.
    t:columns := columnsFromSql:value(statementText:value(text, st)).
    t:columns:size:equals(#0):ifTrue({ error:raise("CREATE TABLE ":concat(name):concat(" has no columns")) }).
    t:indexes := []. t:maxRowid := nil.
    t:root := d:newPage(#13).
    ; Stored as written, after the two words SQLite spells for itself.
    sql := "CREATE TABLE ":concat(text:copyFrom(st:at(#3):at(#3), st:at(st:size):at(#4))).
    schemaRow:value(d, tables, "table", name, name, t:root, sql).
    tables:atPut(name:asLowercase, t) }.

createIndex := { d, tables, st, text | | name, tblName, t, cols, root, sql, ix |
    st:size:lessThan(#7):ifTrue({ error:raise("CREATE INDEX needs a name, a table and columns") }).
    name := tok:value(st, #3):at(#2).
    isWord:value(st, #4, "ON"):ifFalse({ error:raise("expected ON in CREATE INDEX") }).
    tblName := tok:value(st, #5):at(#2).
    t := tables:at(tblName:asLowercase, nil).
    t:isNil:ifTrue({ error:raise("no such table: ":concat(tblName)) }).
    cols := indexColumnsFromSql:value(statementText:value(text, st)).
    cols:isNil:ifTrue({ error:raise("an index with DESC, COLLATE, an expression or a WHERE is not written here") }).
    cols:do({ c | resolve:value(t, c) }).
    root := d:newPage(#10).
    sql := "CREATE INDEX ":concat(text:copyFrom(st:at(#3):at(#3), st:at(st:size):at(#4))).
    schemaRow:value(d, tables, "index", name, t:name, root, sql).
    ix := [name, root, cols].
    t:indexes:add(ix).
    ; A table that already has rows is indexed now.
    eachRow:value(d, t:root, { rowid, p | | values, entry, payload, raw |
        values := decodeRecord:value(p).
        entry := cols:collect({ c | | which |
            which := resolve:value(t, c).
            which:equals('rowid):ifElse({ rowid }, { which:greaterThan(values:size):ifElse({ nil }, { values:at(which) }) }) }).
        entry:add(rowid).
        payload := recordBytes:value(entry).
        raw := varintBytes:value(payload:size):concat(payload).
        treeInsert:value(d, root, raw, entry, true) }) }.

; INSERT INTO t [(cols)] VALUES (v, ...), (v, ...)
insertStatement := { d, tables, st | | i, name, t, which, r, rowValues, values, rowidGiven, done, v, count |
    i := expect:value(st, #1, "INSERT").
    i := expect:value(st, i, "INTO").
    name := tok:value(st, i):at(#2). i := i:inc.
    t := tables:at(name:asLowercase, nil).
    t:isNil:ifTrue({ error:raise("no such table: ":concat(name)) }).
    ; The columns named, resolved; none named is every column in order.
    which := nil.
    isPunct:value(st, i, "("):ifTrue({
        i := i:inc. which := [].
        { isPunct:value(st, i, ")"):not:and({ i:lessOrEqual(st:size) }) }:whileTrue({
            r := columnRef:value(st, i). i := r:at(#2).
            which:add(resolve:value(t, r:at(#1))).
            isPunct:value(st, i, ","):ifTrue({ i := i:inc }) }).
        i := i:inc }).
    which:isNil:ifTrue({
        which := [].
        [#1, t:columns:size]:loop({ k | which:add(t:columns:at(k):at(#3):ifElse({ 'rowid }, { k })) }) }).
    i := expect:value(st, i, "VALUES").
    count := #0.
    done := false.
    { done:not }:whileTrue({
        i := expect:value(st, i, "(").
        rowValues := [].
        { isPunct:value(st, i, ")"):not:and({ i:lessOrEqual(st:size) }) }:whileTrue({
            r := literal:value(st, i). i := r:at(#2).
            rowValues:add(r:at(#1)).
            isPunct:value(st, i, ","):ifTrue({ i := i:inc }) }).
        i := i:inc.
        rowValues:size:notEquals(which:size):ifTrue({
            error:raise("table ":concat(t:name):concat(" has "):concat(which:size:asString)
                :concat(" columns but "):concat(rowValues:size:asString):concat(" values were supplied")) }).
        values := []. rowidGiven := nil.
        [#1, t:columns:size]:loop({ k | values:add(nil) }).
        [#1, which:size]:loop({ k |
            v := rowValues:at(k).
            which:at(k):equals('rowid):ifElse(
                { v:isNil:ifFalse({ rowidGiven := rowidOf:value(v) }) },
                { values:atPut(which:at(k), storeAffinity:value(v, t:columns:at(which:at(k)):at(#2))) }) }).
        insertRow:value(d, t, values, rowidGiven).
        count := count:inc.
        isPunct:value(st, i, ","):ifElse(
            { i := i:inc }, { done := true }) }).
    i:lessOrEqual(st:size):ifTrue({
        error:raise("this INSERT goes on past what is understood, at: ":concat(tok:value(st, i):at(#2))) }).
    count }.

; PRAGMA page_size = N sets the size of a database that is still empty, and
; is ignored on one that is not, as SQLite ignores it. Any other pragma is
; not understood, and says so rather than answering nothing.
pragmaStatement := { d, st | | n |
    (isWord:value(st, #2, "PAGE_SIZE"):and({ isPunct:value(st, #3, "=") })):ifFalse({
        error:raise("only PRAGMA page_size = N is understood") }).
    n := tok:value(st, #4):at(#2):asInteger.
    ([#512, #1024, #2048, #4096, #8192, #16384, #32768, #65536]:indexOf(n)):isNil:ifTrue({
        error:raise("page_size must be a power of two from 512 to 65536") }).
    d:isEmpty:ifTrue({ d:pageSize := n. d:usable := n }) }.

; One statement of any kind this program has.
execute := { d, tables, st, text | | first |
    first := st:at(#1):at(#2):asUppercase.
    first:equals("SELECT"):ifElse({ runSelect:value(d, tables, parseSelect:value(st)) },
    { first:equals("INSERT"):ifElse({ insertStatement:value(d, tables, st) },
    { first:equals("PRAGMA"):ifElse({ pragmaStatement:value(d, st) },
    { (first:equals("CREATE"):and({ isWord:value(st, #2, "TABLE") })):ifElse({ createTable:value(d, tables, st, text) },
    { (first:equals("CREATE"):and({ isWord:value(st, #2, "INDEX") })):ifElse({ createIndex:value(d, tables, st, text) },
    { (first:equals("CREATE"):and({ isWord:value(st, #2, "UNIQUE") })):ifElse(
        { error:raise("a UNIQUE index is not written here; the constraint is not checked") },
        { error:raise("only SELECT, CREATE TABLE, CREATE INDEX, INSERT and PRAGMA page_size are understood; this begins with ":concat(st:at(#1):at(#2))) }) }) }) }) }) }) }.

; ---------------------------------------------------------------------------
; The demonstration
;
; Every program here runs with no arguments on input it supplies itself. This
; one writes a small database under build/, reads it back, and if the sqlite3
; on the machine is there, asks it whether the file is well formed and what
; it reads, since that is the judge the sweep uses. Until step 3 the file
; was made by sqlite3; now it is made here.

demonstrate := { | path, run, verdict |
    system:makeDirectory("build").
    path := "build/sqlite-demo.db".
    system:fileExists(path):ifTrue({ system:remove(path) }).
    demoDb := db:open(path).
    demoTables := loadSchema:value(demoDb).
    run := { sql |
        "-- ":concat(sql):display.
        statements:value(tokenize:value(sql)):do({ st |
            execute:value(demoDb, demoTables, st, sql) }).
        out:size:greaterThan(#0):ifTrue({ system:write(out:join("")). out := []. "":display }) }.
    run:value("CREATE TABLE fruit (name TEXT, count INTEGER, price REAL)").
    run:value("CREATE INDEX fruit_name ON fruit (name)").
    run:value("INSERT INTO fruit VALUES ('pear', 3, 0.5), ('apple', 10, 0.25), ('fig', 1, 2.0)").
    run:value("INSERT INTO fruit VALUES ('banana', 2, 0.3), ('apple', 7, 0.25), (NULL, 0, 1e20)").
    "":display.
    run:value("SELECT * FROM fruit").
    run:value("SELECT rowid, name FROM fruit WHERE name = 'apple'").
    run:value("SELECT name, price FROM fruit ORDER BY price, rowid").
    run:value("SELECT count FROM fruit WHERE rowid = 3").
    run:value("SELECT type, name, rootpage FROM sqlite_schema").
    demoDb:flush.
    "-- ":concat(demoDb:pageCount:asString):concat(" pages of "):concat(demoDb:pageSize:asString)
        :concat(" bytes written to "):concat(path):display.
    verdict := system:capture(["sqlite3", path, "PRAGMA integrity_check; SELECT name, count FROM fruit WHERE name = 'apple'"],
                              ["stderr", 'discard]).
    verdict:at("status"):equals(#0):ifElse(
        { "-- sqlite3 on this machine says: ":concat(verdict:at("output"):trim:split("\n"):join(" / ")):display },
        { "-- no sqlite3 on this machine to judge it":display }) }.

demoDb := nil.
demoTables := nil.

; ---------------------------------------------------------------------------
; Main

main := { | args, d, tables, text, tokens, status |
    args := system:arguments.
    args:size:lessThan(#1):ifTrue({
        { demonstrate:value }:onError({ e |
            system:writeError("sqlite: ":concat(e:message):concat("\n")).
            system:exit(#2) }).
        system:exit(#0) }).
    status := #0.
    { d := db:open(args:at(#1)).
      tables := loadSchema:value(d) }:onError({ e |
        system:writeError("Error: ":concat(e:message):concat("\n")).
        system:exit(#1) }).
    text := args:size:greaterOrEqual(#2):ifElse({ args:at(#2) }, { system:readFile("/dev/stdin") }).
    statements:value(tokenize:value(text)):do({ st |
        { execute:value(d, tables, st, text) }
        :onError({ e |
            system:write(out:join("")). out := [].
            system:writeError("Error: ":concat(e:message):concat("\n")).
            status := #1 }) }).
    system:write(out:join("")).
    ; What changed is written now, whole, as the statements that finished left
    ; it; there is no journal, so a statement that failed half way is in the
    ; file half way, and the sweep judges only files whose script finished.
    { d:flush }:onError({ e |
        system:writeError("Error: ":concat(e:message):concat("\n")).
        status := #1 }).
    ; The numbers to watch, on request: pages read, and for a run that wrote,
    ; how many pages the statements needed against how many the whole-file
    ; write cost, which is the measurement step 4 of the plan exists for.
    system:environment("SQLITE_PAGES"):notNil:ifTrue({
        d:written:equals(#0):ifElse(
            { system:writeError(d:reads:asString:concat(" pages read of "):concat(d:pageCount:asString):concat("\n")) },
            { system:writeError(d:readBefore:asString:concat(" pages read and "):concat(d:changed:asString)
                  :concat(" changed by the statements; writing the file whole read "):concat(d:reads:sub(d:readBefore):asString)
                  :concat(" more and wrote "):concat(d:pageCount:asString):concat(" pages, ")
                  :concat(d:written:asString):concat(" bytes\n")) }) }).
    system:exit(status) }.

main:value.
