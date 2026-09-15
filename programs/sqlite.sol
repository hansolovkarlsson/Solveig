; sqlite.sol -- an SQLite database file, read, and later written.
;
; Run with:  ./bin/solas programs/sqlite.sol && ./bin/solvm programs/sqlite.sob
; Over a file:  ./bin/solvm programs/sqlite.sob notes.db < queries.sql
; Or one query:  ./bin/solvm programs/sqlite.sob notes.db 'SELECT * FROM t'
; With no arguments it demonstrates itself on a file sqlite3 makes under build/.
;
; The twenty-third program here, and the first of the directions design.md
; lists to be reached. It reads the file format that `sqlite3` writes, from the
; format's own description and nothing else, and answers SELECT over it in the
; shell's default list mode: columns with `|` between them, nothing for NULL,
; one row a line. That is so the two can be compared byte for byte, which is
; what programs/sqlite/sweep.sh does: `sqlite3` builds every database in the
; corpus, and `sqlite3` says what is in it.
;
; The plan is in ideas.md under *An SQLite file, read and then written*, with
; what it predicted written above what it found. This file is steps 1 and 2 of
; it, the reader: tables, then the index trees, which a WHERE on an indexed
; column walks instead of scanning. The SQL it parses is the SQL the plan
; bounds: SELECT of named columns, `rowid` or `*`, from one table, with a
; WHERE of one comparison, and an ORDER BY. Nothing else, and a statement
; outside that is reported as such rather than quietly meaning something
; else. `SQLITE_PAGES=1` in the environment reports how many pages a run
; read, which is the number a query is measured by here.
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
;   implementation shares, since `integrity_check` checks it.
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

db:open := { path | | d, header |
    d := self:new.
    d:path := path.
    d:cache := dictionary:new.
    system:fileExists(path):ifFalse({ error:raise("no such file: ":concat(path)) }).
    header := system:readFile(path, #1, #100).
    header:size:lessThan(#100):or({ header:copyFrom(#1, #15):notEquals("SQLite format 3") })
        :ifTrue({ error:raise("file is not a database: ":concat(path)) }).
    d:pageSize := u16:value(header, #17).
    d:pageSize:equals(#1):ifTrue({ d:pageSize := #65536 }).
    d:usable := d:pageSize:sub(u8:value(header, #21)).
    d:pageCount := u32:value(header, #29).
    d }.

; One page, by number, from the cache or the file. A page is one ranged read,
; and the count of them is the number to watch in a query.
db:page := { n | | from, p |
    self:cache:includes(n):ifElse({ self:cache:at(n) }, {
        from := n:dec:mul(self:pageSize):inc.
        p := system:readFile(self:path, from, self:pageSize).
        p:size:lessThan(self:pageSize):ifTrue({
            error:raise("page ":concat(n:asString):concat(" is not in the file")) }).
        self:reads := self:reads:inc.
        self:cache:atPut(n, p).
        p }) }.

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

tokenize := { text | | s, out, c, word |
    s := scan:on(text). out := [].
    { s:atEnd:not }:whileTrue({
        c := s:peek.
        isSpace:value(c):ifTrue({ s:step }).
        c:equals("-"):and({ s:peekAt(#1):equals("-") }):ifTrue({
            s:skipWhile({ ch | ch:notEquals("\n") }) }).
        isWordStart:value(c):ifTrue({
            word := s:takeWhile(isWordChar).
            (word:asUppercase:equals("X"):and({ s:peek:equals("'") })):ifElse(
                { s:step. out:add(['blob, unhex:value(quoted:value(s, "'"))]) },
                { out:add(['word, word]) }) }).
        isDigit:value(c):or({ c:equals("."):and({ s:peekAt(#1):notNil }):and({ isDigit:value(s:peekAt(#1)) }) }):ifTrue({
            word := s:takeWhile({ ch | isDigit:value(ch):or({ ch:equals(".") }) }).
            s:peek:notNil:and({ s:peek:asUppercase:equals("E") }):ifTrue({
                word := word:concat(s:next).
                s:peek:equals("+"):or({ s:peek:equals("-") }):ifTrue({ word := word:concat(s:next) }).
                word := word:concat(s:takeWhile(isDigit)) }).
            out:add(['number, word]) }).
        c:equals("'"):ifTrue({ s:step. out:add(['text, quoted:value(s, "'")]) }).
        c:equals("\""):ifTrue({ s:step. out:add(['name, quoted:value(s, "\"")]) }).
        c:equals("`"):ifTrue({ s:step. out:add(['name, quoted:value(s, "`")]) }).
        c:equals("["):ifTrue({ s:step. out:add(['name, s:takeUntil({ ch | ch:equals("]") })]). s:step }).
        ("(),;*=.<>":indexOf(c):notNil:and({ c:notEquals(".") })):ifTrue({
            s:step. out:add(['punct, c]) }).
        ; Anything else is a byte this SQL has no use for.
        (isSpace:value(c):or({ c:equals("-") }):or({ isWordStart:value(c) })
            :or({ isDigit:value(c) }):or({ c:equals(".") }):or({ c:equals("'") })
            :or({ c:equals("\"") }):or({ c:equals("`") }):or({ c:equals("[") })
            :or({ "(),;*=<>":indexOf(c):notNil })):ifFalse({
            error:raise("unexpected character: ":concat(c)) }).
        (c:equals("."):and({ s:peekAt(#1):isNil:or({ isDigit:value(s:peekAt(#1)):not }) })):ifTrue({
            s:step. out:add(['punct, "."]) }).
        (c:equals("-"):and({ s:peekAt(#1):notEquals("-") })):ifTrue({
            s:step. out:add(['punct, "-"]) }) }).
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
        (i:lessOrEqual(tokens:size):and({ tok:value(tokens, i):at(#2):equals(",") })):ifElse(
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
            (i:lessOrEqual(tokens:size):and({ tok:value(tokens, i):at(#2):equals(",") })):ifElse(
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
; The demonstration
;
; Every program here runs with no arguments on input it supplies itself. This
; one reads and does not yet write, so until step 3 of the plan the input is
; made by the `sqlite3` on the machine, which is also the oracle: a small
; database under build/, read back here. If there is no sqlite3 it says so.

demonstrate := { | path, status, run |
    system:makeDirectory("build").
    path := "build/sqlite-demo.db".
    system:fileExists(path):ifTrue({ system:remove(path) }).
    status := system:run(["sqlite3", path,
        "CREATE TABLE fruit (name TEXT, count INTEGER, price REAL);
         CREATE INDEX fruit_name ON fruit (name);
         INSERT INTO fruit VALUES ('pear', 3, 0.5), ('apple', 10, 0.25), ('fig', 1, 2.0);
         INSERT INTO fruit VALUES ('banana', 2, 0.3), ('apple', 7, 0.25), (NULL, 0, 1e20);"],
        ["stdout", 'discard, "stderr", 'discard]).
    status:equals(#0):ifFalse({
        error:raise("the demonstration needs sqlite3 on this machine to make its file (exit ":concat(status:asString):concat(")")) }).
    run := { sql |
        "-- ":concat(sql):display.
        statements:value(tokenize:value(sql)):do({ st |
            runSelect:value(demoDb, demoTables, parseSelect:value(st)) }).
        system:write(out:join("")). out := [].
        "":display }.
    demoDb := db:open(path).
    demoTables := loadSchema:value(demoDb).
    run:value("SELECT * FROM fruit").
    run:value("SELECT rowid, name FROM fruit WHERE name = 'apple'").
    run:value("SELECT name, price FROM fruit ORDER BY price, rowid").
    run:value("SELECT count FROM fruit WHERE rowid = 3").
    run:value("SELECT type, name, rootpage FROM sqlite_schema").
    "-- ":concat(demoDb:reads:asString):concat(" pages read, of ")
        :concat(demoDb:pageCount:asString):concat(" in the file"):display }.

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
        { | parsed |
          isWord:value(st, #1, "SELECT"):ifFalse({
              error:raise("only SELECT is read so far; this begins with ":concat(st:at(#1):at(#2))) }).
          parsed := parseSelect:value(st).
          runSelect:value(d, tables, parsed) }
        :onError({ e |
            system:write(out:join("")). out := [].
            system:writeError("Error: ":concat(e:message):concat("\n")).
            status := #1 }) }).
    system:write(out:join("")).
    ; The number to watch, on request: how many pages the whole run read.
    system:environment("SQLITE_PAGES"):notNil:ifTrue({
        system:writeError(d:reads:asString:concat(" pages read of "):concat(d:pageCount:asString):concat("\n")) }).
    system:exit(status) }.

main:value.
