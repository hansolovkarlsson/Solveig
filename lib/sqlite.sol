; sqlite.sol -- an SQLite database file, read and written.
;
;     @include "sqlite.sol".
;
;     d := sqlite:db:open("notes.db").
;     tables := sqlite:loadSchema(d).
;     sqlite:matchingRows(d, tables:at("notes"), []):size:print.
;     d:flush.
;
; Found on the search path, so no program has to say where this lives. See
; docs/REFERENCE.md#the-library.
;
; This file binds one name, `sqlite`, and hangs the engine on it: the bytes,
; the values, the file and its pages, the B-trees, the records, the SQL
; tokenizer that the schema needs, the schema, and one row put in or taken
; out. It reads and writes the file format that `sqlite3` uses, from the
; format's own description and nothing else, and is held against `sqlite3`
; by programs/sql/sweep.sh through programs/sql.sol, the SQL shell over
; it, which is where the statements are parsed and the answers printed in
; the shell's list mode. Until 2026-09-15 the two were one file,
; programs/sqlite.sol; the plan that split them is in ideas.md under *The
; database as objects*, and the engine moved first, unchanged, so that the
; sweep could say the move changed nothing before anything was added.
;
; What the library asks of a caller today is what the shell asks: a
; database `d` from `sqlite:db:open`, its `tables` from `sqlite:loadSchema`,
; and `d:flush` when done, since pages are changed in memory and written
; once. The objects the plan names, a table with `insert` and `where`, a
; row with its columns as slots, are the next step and are not here yet.
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
;   Pages a tree no longer needs are on the freelist: a chain of trunk pages,
;   each a pointer to the next trunk, a count, and that many free page
;   numbers, with the head and the total in the file header at 32 and 36.
;
;   Writing is the same shapes in the other direction, and one more: a page
;   that will not hold its cells splits. A table tree is a B+tree, so a leaf
;   that splits sends up a copy of its last left rowid; an index tree is a
;   B-tree, so a page that splits sends up its middle entry. The page that
;   split keeps its number as the left half, the new page is the right, and
;   the root keeps its number by moving its contents down when it splits,
;   which is how a tree gains a level and why a root page number in the
;   schema never changes. Deleting is the reverse: a leaf that empties is
;   dropped from its parent and freed, and a root left with one child takes
;   its contents. A page below the root left with one child is not replaced
;   by it, since every leaf of a tree stands at one depth and that would
;   leave one shallower: its child's entries are put back into the tree from
;   the root and the pages freed. The same for an index interior cell that
;   loses its child or is itself the entry to go, since an entry cannot
;   stand without a child beside it. SQLite merges siblings instead and so
;   frees more pages; `integrity_check` accepts either, and named the two
;   shapes tried before this one.
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

sqlite := object:new.

; ---------------------------------------------------------------------------
; Bytes
;
; `at` answers a one-character string and `asByte` its number, and everything
; below reads big-endian, which is what this format is throughout.

sqlite:u8 := { s, i | s:at(i):asByte }.
sqlite:u16 := { s, i | s:at(i):asByte:shiftLeft(#8):bitOr(s:at(i:inc):asByte) }.
sqlite:u32 := { s, i |
    s:at(i):asByte:shiftLeft(#24)
        :bitOr(s:at(i:add(#1)):asByte:shiftLeft(#16))
        :bitOr(s:at(i:add(#2)):asByte:shiftLeft(#8))
        :bitOr(s:at(i:add(#3)):asByte) }.

; A varint at `i`: answers the value and the index after it. The ninth byte
; carries eight bits, so the fifty-six above it may already reach bit 55 and
; the shift into bit 63 is the one the language refuses. Arithmetic instead:
; when the value so far has its top bit (of 56) set, it is subtracted from
; 2^56 first, so that the multiplication by 256 lands negative and in range.
sqlite:varint := { s, i | | v, b, n, at |
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
sqlite:signedBytes := { s, i, n | | v, k, b |
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

sqlite:powerOfTwo := { n | | out, i |
    out := 1.0. i := #0.
    n:greaterOrEqual(#0):ifElse(
        { { i:lessThan(n) }:whileTrue({ out := out:mul(2.0). i := i:inc }) },
        { { i:lessThan(n:negated) }:whileTrue({ out := out:div(2.0). i := i:inc }) }).
    out }.

sqlite:floatFromBytes := { s, i | | hi, lo, sign, exponent, mantissa, value, e2 |
    hi := sqlite:u32(s, i).
    lo := sqlite:u32(s, i:add(#4)).
    sign     := hi:shiftRight(#31):bitAnd(#1).
    exponent := hi:shiftRight(#20):bitAnd(#2047).
    mantissa := hi:bitAnd(#1048575):mul(#4294967296):add(lo).
    exponent:equals(#2047):ifTrue({
        error:raise(mantissa:equals(#0):ifElse({ "infinity" }, { "not a number" })) }).
    exponent:equals(#0):ifElse(
        { e2 := #-1074 },                                        ; subnormal
        { e2 := exponent:sub(#1075). mantissa := mantissa:add(#4503599627370496) }).
    value := mantissa:asFloat:mul(sqlite:powerOfTwo(e2)).
    sign:equals(#1):ifTrue({ value := value:negated }).
    [value, sign, mantissa, e2] }.

; The same parts from a float the parser made, for a literal that has to be
; printed or compared as text. Normalised into [1, 2) by halving and doubling,
; as sob:f64 does, and then down into the subnormals where that library stops.
sqlite:floatParts := { x | | sign, exponent, mantissa, y |
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
sqlite:bigTimes := { limbs, factor | | carry, i, v |
    carry := #0. i := #1.
    { i:lessOrEqual(limbs:size) }:whileTrue({
        v := limbs:at(i):mul(factor):add(carry).
        limbs:atPut(i, v:mod(#1000000000)).
        carry := v:div(#1000000000).
        i := i:inc }).
    carry:greaterThan(#0):ifTrue({ limbs:add(carry) }).
    limbs }.

sqlite:bigDigits := { limbs | | out, i, piece |
    out := limbs:at(limbs:size):asString.
    i := limbs:size:dec.
    { i:greaterOrEqual(#1) }:whileTrue({
        piece := limbs:at(i):asString.
        out := out:concat("000000000":copyFrom(#1, #9:sub(piece:size)):concat(piece)).
        i := i:dec }).
    out }.

sqlite:exactDecimal := { mantissa, exponent | | limbs, k, digits, pointAt, lead |
    limbs := [mantissa:mod(#1000000000), mantissa:div(#1000000000)].
    limbs:at(#2):equals(#0):ifTrue({ limbs:removeLast }).
    k := #0.
    exponent:greaterOrEqual(#0):ifElse(
        { { k:lessThan(exponent) }:whileTrue({ sqlite:bigTimes(limbs, #2). k := k:inc }).
          digits := sqlite:bigDigits(limbs).
          pointAt := digits:size },
        { { k:lessThan(exponent:negated) }:whileTrue({ sqlite:bigTimes(limbs, #5). k := k:inc }).
          digits := sqlite:bigDigits(limbs).
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
sqlite:fifteen := { parts | | sign, digits, pointAt, d, carry, i, exp10, out, whole, frac |
    sign := parts:at(#2).
    parts:at(#3):equals(#0):ifElse({ "0.0" }, {
        d := sqlite:exactDecimal(parts:at(#3), parts:at(#4)).
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

sqlite:blob := object:new.
sqlite:blob:bytes := "".
sqlite:blob:of := { s | | b | b := self:new. b:bytes := s. b }.

sqlite:real := object:new.
sqlite:real:value := 0.0.
sqlite:real:parts := nil.
sqlite:real:of := { parts | | r | r := self:new. r:value := parts:at(#1). r:parts := parts. r }.

sqlite:isNumber := { v | v:isKindOf(integer):or({ v:isKindOf(sqlite:real) }) }.
sqlite:asFloatValue := { v | v:isKindOf(integer):ifElse({ v:asFloat }, { v:value }) }.

; Rank for ordering: NULL, then numbers, then text, then blobs.
sqlite:rank := { v |
    v:isNil:ifElse({ #0 },
        { sqlite:isNumber(v):ifElse({ #1 },
            { v:isKindOf(string):ifElse({ #2 }, { #3 }) }) }) }.

; SQLite's order: by rank, then numerically, then by bytes.
sqlite:compare := { a, b | | ra, rb |
    ra := sqlite:rank(a). rb := sqlite:rank(b).
    ra:notEquals(rb):ifElse(
        { ra:lessThan(rb):ifElse({ #-1 }, { #1 }) },
        { ra:equals(#0):ifElse({ #0 },
          { ra:equals(#1):ifElse(
              { a:isKindOf(integer):and({ b:isKindOf(integer) }):ifElse(
                    { a:lessThan(b):ifElse({ #-1 }, { a:greaterThan(b):ifElse({ #1 }, { #0 }) }) },
                    { | x, y | x := sqlite:asFloatValue(a). y := sqlite:asFloatValue(b).
                      x:lessThan(y):ifElse({ #-1 }, { x:greaterThan(y):ifElse({ #1 }, { #0 }) }) }) },
              { | x, y |
                x := ra:equals(#2):ifElse({ a }, { a:bytes }).
                y := ra:equals(#2):ifElse({ b }, { b:bytes }).
                x:lessThan(y):ifElse({ #-1 }, { x:greaterThan(y):ifElse({ #1 }, { #0 }) }) }) }) }) }.

; List mode: nothing for NULL, digits, `%!.15g`, the bytes of a text, and
; the bytes of a blob up to the first NUL, which is where the shell's `%s`
; stops and so where this stops.
sqlite:render := { v | | nul, at |
    v:isNil:ifElse({ "" },
        { v:isKindOf(integer):ifElse({ v:asString },
            { v:isKindOf(sqlite:real):ifElse({ sqlite:fifteen(v:parts) },
                { v:isKindOf(float):ifElse({ sqlite:fifteen(sqlite:floatParts(v)) },
                { v:isKindOf(string):ifElse({ v },
                    { nul := #0:asCharacter.
                      at := v:bytes:indexOf(nul).
                      at:isNil:ifElse({ v:bytes },
                          { at:equals(#1):ifElse({ "" }, { v:bytes:copyFrom(#1, at:dec) }) }) }) }) }) }) }) }.

; ---------------------------------------------------------------------------
; The file

sqlite:db := object:new.
sqlite:db:path := "".
sqlite:db:pageSize := #0.
sqlite:db:usable := #0.
sqlite:db:pageCount := #0.
sqlite:db:cache := nil.
sqlite:db:reads := #0.
sqlite:db:dirty := nil.                ; page number -> page object, to be written
sqlite:db:changes := #0.               ; the file change counter, offset 24
sqlite:db:cookie := #0.                ; the schema cookie, offset 40
sqlite:db:freelistHead := #0.
sqlite:db:freelistCount := #0.
sqlite:db:written := #0.               ; bytes written by flush, for the measurement
sqlite:db:changed := #0.               ; pages that were changed when flush ran
sqlite:db:readBefore := #0.            ; pages read before flush had to read the rest
sqlite:db:tables := nil.               ; lower-cased name -> table, from loadSchema

; A file that is there is opened; one that is not, or one of no bytes, which
; is what sqlite3 leaves after a script that only set a pragma, is a new
; database in memory, one empty schema page, written when something has
; changed.
sqlite:db:open := { path | | d, header |
    d := self:new.
    d:path := path.
    d:cache := dictionary:new.
    d:dirty := dictionary:new.
    (system:fileExists(path):and({ system:fileSize(path):greaterThan(#0) })):ifElse(
        { header := system:readFile(path, #1, #100).
          header:size:lessThan(#100):or({ header:copyFrom(#1, #15):notEquals("SQLite format 3") })
              :ifTrue({ error:raise("file is not a database: ":concat(path)) }).
          d:pageSize := sqlite:u16(header, #17).
          d:pageSize:equals(#1):ifTrue({ d:pageSize := #65536 }).
          d:usable := d:pageSize:sub(sqlite:u8(header, #21)).
          d:changes := sqlite:u32(header, #25).
          d:pageCount := sqlite:u32(header, #29).
          d:freelistHead := sqlite:u32(header, #33).
          d:freelistCount := sqlite:u32(header, #37).
          d:cookie := sqlite:u32(header, #41) },
        { d:pageSize := #4096.
          d:usable := #4096.
          d:pageCount := #1.
          d:dirty:atPut(#1, sqlite:page:of(#13)) }).
    d }.

sqlite:db:isEmpty := { self:pageCount:equals(#1):and({ self:object(#1):cells:size:equals(#0) }) }.

; One page, by number: a page being written, serialised; else the cache; else
; the file. A page from the file is one ranged read, and the count of them is
; the number to watch in a query.
sqlite:db:page := { n | | from, p |
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
sqlite:db:object := { n | | o |
    self:dirty:includes(n):ifElse({ self:dirty:at(n) }, {
        o := sqlite:decodePage(self, self:page(n), n).
        self:dirty:atPut(n, o).
        o }) }.

; A page for a new tree node: the freelist's if it has one, else one more at
; the end of the file. The freelist is a chain of trunk pages, each a pointer
; to the next trunk, a count, and that many free leaf page numbers; the head
; and the total are in the file header at 32 and 36. A leaf is taken from the
; head trunk first, and when a trunk has none left the trunk itself is taken.
sqlite:db:newPage := { kind | | o, n, t |
    self:freelistCount:greaterThan(#0):ifElse(
        { t := self:trunk(self:freelistHead).
          t:leaves:size:greaterThan(#0):ifElse(
              { n := t:leaves:removeLast },
              { n := self:freelistHead. self:freelistHead := t:next. self:dirty:remove(n) }).
          self:freelistCount := self:freelistCount:dec },
        { self:pageCount := self:pageCount:inc. n := self:pageCount }).
    o := sqlite:page:of(kind).
    self:dirty:atPut(n, o).
    n }.

; A page a tree no longer needs joins the freelist: onto the head trunk while
; it has room, else as a new trunk in front of it. What a free leaf page holds
; is nobody's business, so its bytes stay whatever they were.
sqlite:db:freePage := { n | | t |
    self:freelistCount := self:freelistCount:inc.
    (self:freelistHead:equals(#0):or({ self:trunk(self:freelistHead):leaves:size:greaterOrEqual(self:usable:div(#4):sub(#2)) })):ifElse(
        { self:dirty:atPut(n, sqlite:trunk:of(self:freelistHead, [])).
          self:freelistHead := n },
        { self:trunk(self:freelistHead):leaves:add(n) }) }.

; A trunk page as an object to change, decoded from the file on first use.
sqlite:db:trunk := { n | | t, s, count, i |
    self:dirty:includes(n):ifElse({ self:dirty:at(n) }, {
        s := self:page(n).
        count := sqlite:u32(s, #5).
        t := sqlite:trunk:of(sqlite:u32(s, #1), []).
        i := #0.
        { i:lessThan(count) }:whileTrue({ t:leaves:add(sqlite:u32(s, i:mul(#4):add(#9))). i := i:inc }).
        self:dirty:atPut(n, t).
        t }) }.

sqlite:trunk := object:new.
sqlite:trunk:next := #0.
sqlite:trunk:leaves := nil.
sqlite:trunk:of := { next, leaves | | t | t := self:new. t:next := next. t:leaves := leaves. t }.
sqlite:trunk:bytes := { n, d | | out |
    out := [sqlite:u32Bytes(self:next), sqlite:u32Bytes(self:leaves:size)].
    self:leaves:do({ l | out:add(sqlite:u32Bytes(l)) }).
    out:add(sqlite:zeros(d:pageSize:sub(#8):sub(self:leaves:size:mul(#4)))).
    out:join("") }.

; The 100 bytes at the front of page 1.
sqlite:db:fileHeader := {
    ["SQLite format 3":concat(#0:asCharacter),
     sqlite:u16Bytes(self:pageSize:equals(#65536):ifElse({ #1 }, { self:pageSize })),
     #1:asCharacter, #1:asCharacter,                    ; rollback journal, both ways
     self:pageSize:sub(self:usable):asCharacter,        ; reserved bytes a page
     #64:asCharacter, #32:asCharacter, #32:asCharacter, ; the payload fractions, fixed
     sqlite:u32Bytes(self:changes),
     sqlite:u32Bytes(self:pageCount),
     sqlite:u32Bytes(self:freelistHead),
     sqlite:u32Bytes(self:freelistCount),
     sqlite:u32Bytes(self:cookie),
     sqlite:u32Bytes(#4),                                ; schema format
     sqlite:u32Bytes(#0),                                ; default cache size
     sqlite:u32Bytes(#0),                                ; largest root page: no autovacuum
     sqlite:u32Bytes(#1),                                ; UTF-8
     sqlite:u32Bytes(#0), sqlite:u32Bytes(#0), sqlite:u32Bytes(#0),   ; user version, incremental vacuum, application id
     sqlite:zeros(#20),
     sqlite:u32Bytes(self:changes),                      ; version-valid-for
     sqlite:u32Bytes(#0)]:join("") }.                    ; the library that wrote it: none SQLite knows

; The pages that changed, each written where it lives, and the file header
; with them. `writeFile(path, from, text)` is ROADMAP 3.27, raised from this
; program on 2026-09-15 and built the same day: until then the only write the
; language had replaced the file, so three changed pages cost every page
; read and every page written, 100 MB for 12 KB. The whole-file route is
; gone rather than kept as a fallback, since two paths through a writer is
; the shape that hides a defect in the one not taken.
sqlite:db:flush := { | n |
    self:dirty:size:greaterThan(#0):ifTrue({
        self:changes := self:changes:inc.
        self:changed := self:dirty:size.
        self:readBefore := self:reads.
        ; A new file has no page 1 on disk yet; a fresh header goes with the
        ; schema page in either case, since the change counter and the page
        ; count live in it and both moved.
        self:dirty:keysAndValuesDo({ k, o | | bytes |
            bytes := o:bytes(k, self).
            system:writeFile(self:path, k:dec:mul(self:pageSize):inc, bytes).
            self:written := self:written:add(bytes:size).
            self:cache:atPut(k, bytes) }).
        self:dirty:includes(#1):ifFalse({
            system:writeFile(self:path, #1, self:fileHeader).
            self:written := self:written:add(#100).
            self:cache:includes(#1):ifTrue({
                self:cache:atPut(#1, self:fileHeader:concat(self:cache:at(#1):copyFrom(#101, self:pageSize))) }) }).
        self:dirty := dictionary:new }) }.

; ---------------------------------------------------------------------------
; Bytes, written

sqlite:u16Bytes := { n | n:shiftRight(#8):bitAnd(#255):asCharacter:concat(n:bitAnd(#255):asCharacter) }.
sqlite:u32Bytes := { n |
    [n:shiftRight(#24):bitAnd(#255), n:shiftRight(#16):bitAnd(#255),
     n:shiftRight(#8):bitAnd(#255), n:bitAnd(#255)]:collect({ b | b:asCharacter }):join("") }.

sqlite:zeros := { n | | out, piece |
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
sqlite:varintBytes := { v | | out, hi, groups, i |
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
sqlite:intBytes := { v, n | | out, i |
    out := []. i := n:dec.
    { i:greaterOrEqual(#0) }:whileTrue({
        out:add(v:shiftRight(i:mul(#8)):bitAnd(#255):asCharacter). i := i:dec }).
    out:join("") }.

; The serial type an integer takes: 0 and 1 in no bytes, else the fewest
; bytes that hold it.
sqlite:intSerial := { v |
    v:equals(#0):ifElse({ #8 },
    { v:equals(#1):ifElse({ #9 },
    { (v:greaterOrEqual(#-128):and({ v:lessOrEqual(#127) })):ifElse({ #1 },
    { (v:greaterOrEqual(#-32768):and({ v:lessOrEqual(#32767) })):ifElse({ #2 },
    { (v:greaterOrEqual(#-8388608):and({ v:lessOrEqual(#8388607) })):ifElse({ #3 },
    { (v:greaterOrEqual(#-2147483648):and({ v:lessOrEqual(#2147483647) })):ifElse({ #4 },
    { (v:greaterOrEqual(#-140737488355328):and({ v:lessOrEqual(#140737488355327) })):ifElse({ #5 },
    { #6 }) }) }) }) }) }) }) }.
sqlite:serialWidth := [#1, #2, #3, #4, #6, #8].

; Eight bytes of a double from its parts, floatFromBytes inverted: the field
; is the exponent plus 1075, or zero for a subnormal, and the implicit bit is
; taken back off the mantissa.
sqlite:floatBytes := { parts | | sign, mantissa, e2, field, hi, lo |
    sign := parts:at(#2). mantissa := parts:at(#3). e2 := parts:at(#4).
    mantissa:equals(#0):ifElse(
        { field := #0 },
        { mantissa:lessThan(#4503599627370496):ifElse(                     ; 2^52: no implicit bit
              { field := #0 },
              { field := e2:add(#1075). mantissa := mantissa:sub(#4503599627370496) }) }).
    hi := sign:shiftLeft(#31):bitOr(field:shiftLeft(#20)):bitOr(mantissa:shiftRight(#32)).
    lo := mantissa:bitAnd(#4294967295).
    sqlite:u32Bytes(hi):concat(sqlite:u32Bytes(lo)) }.

; A record from an array of values: the header of serial types, its own
; length in front, then the bodies.
sqlite:recordBytes := { values | | types, bodies, headerSize, headerBytes |
    types := []. bodies := [].
    values:do({ v |
        v:isNil:ifTrue({ types:add(#0). bodies:add("") }).
        v:isKindOf(integer):ifTrue({ | t |
            t := sqlite:intSerial(v). types:add(t).
            bodies:add(t:greaterOrEqual(#8):ifElse({ "" }, { sqlite:intBytes(v, sqlite:serialWidth:at(t)) })) }).
        v:isKindOf(sqlite:real):ifTrue({ types:add(#7). bodies:add(sqlite:floatBytes(v:parts)) }).
        v:isKindOf(string):ifTrue({ types:add(v:size:mul(#2):add(#13)). bodies:add(v) }).
        v:isKindOf(sqlite:blob):ifTrue({ types:add(v:bytes:size:mul(#2):add(#12)). bodies:add(v:bytes) }) }).
    headerBytes := types:collect({ t | sqlite:varintBytes(t) }):join("").
    ; The header's length counts its own varint, which is one byte until the
    ; header is 127 bytes long and two after.
    headerSize := headerBytes:size:inc.
    headerSize:greaterThan(#127):ifTrue({ headerSize := headerBytes:size:add(#2) }).
    sqlite:varintBytes(headerSize):concat(headerBytes):concat(bodies:join("")) }.

; ---------------------------------------------------------------------------
; A page being written
;
; Cells in key order, each the raw bytes after any child pointer, with the
; key decoded beside it: a rowid for a table page, the entry's values for an
; index page. Serialised to bytes on demand, from the end of the page down,
; with no freeblocks and no fragments, which is one well-formed page among
; the many `integrity_check` accepts.

sqlite:page := object:new.
sqlite:page:kind := #13.
sqlite:page:cells := nil.
sqlite:page:keys := nil.
sqlite:page:children := nil.          ; interior pages only, parallel to cells
sqlite:page:right := #0.              ; interior pages only

sqlite:page:of := { kind | | p |
    p := self:new.
    p:kind := kind. p:cells := []. p:keys := []. p:children := []. p:right := #0.
    p }.

sqlite:page:isLeaf := { self:kind:equals(#13):or({ self:kind:equals(#10) }) }.
sqlite:page:isTable := { self:kind:equals(#13):or({ self:kind:equals(#5) }) }.
sqlite:page:headerSize := { self:isLeaf:ifElse({ #8 }, { #12 }) }.

; Bytes in use on page `n` of database `d`: the headers, the pointer array
; and every cell with its child pointer.
sqlite:page:used := { n, d | | total, extra |
    extra := self:isLeaf:ifElse({ #0 }, { #4 }).
    total := n:equals(#1):ifElse({ #100 }, { #0 }):add(self:headerSize):add(self:cells:size:mul(#2)).
    self:cells:do({ c | total := total:add(c:size):add(extra) }).
    total }.
sqlite:page:fits := { n, d | self:used(n, d):lessOrEqual(d:usable) }.

sqlite:page:bytes := { n, d | | h, extra, pos, offsets, i, content, pointers, header, free |
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
        self:isLeaf:ifFalse({ content:add(sqlite:u32Bytes(self:children:at(i))) }).
        content:add(self:cells:at(i)).
        i := i:inc }).
    pointers := []. i := offsets:size.
    { i:greaterOrEqual(#1) }:whileTrue({ pointers:add(sqlite:u16Bytes(offsets:at(i))). i := i:dec }).
    header := [self:kind:asCharacter,
               sqlite:u16Bytes(#0),                                       ; no freeblocks
               sqlite:u16Bytes(self:cells:size),
               sqlite:u16Bytes(self:cells:size:equals(#0):ifElse({ d:usable }, { pos }):bitAnd(#65535)),
               #0:asCharacter].                                          ; no fragments
    self:isLeaf:ifFalse({ header:add(sqlite:u32Bytes(self:right)) }).
    free := pos:sub(h):sub(self:headerSize):sub(self:cells:size:mul(#2)).
    free:lessThan(#0):ifTrue({ error:raise("page ":concat(n:asString):concat(" overflowed by ")
        :concat(free:negated:asString):concat(" bytes")) }).
    [n:equals(#1):ifElse({ d:fileHeader }, { "" }),
     header:join(""), pointers:join(""), sqlite:zeros(free), content:join(""),
     sqlite:zeros(d:pageSize:sub(d:usable))]:join("") }.

; A page from its bytes, for changing: every cell copied raw and its key
; decoded. A cell that spills to overflow pages is carried with its pointer,
; which is what keeps a row this program did not write intact when it moves.
sqlite:decodePage := { d, s, n | | o, h, offsets, extra |
    h := sqlite:headerAt(n).
    o := sqlite:page:of(sqlite:u8(s, h)).
    offsets := sqlite:cells(s, n).
    extra := o:isLeaf:ifElse({ #0 }, { #4 }).
    o:isLeaf:ifFalse({ o:right := sqlite:u32(s, h:add(#8)) }).
    offsets:do({ at | | start, v, size, local, rowid, end, key |
        start := at:add(extra).
        o:isLeaf:ifFalse({ o:children:add(sqlite:u32(s, at)) }).
        o:isTable:ifElse(
            { o:isLeaf:ifElse(
                  { v := sqlite:varint(s, start). size := v:at(#1).
                    v := sqlite:varint(s, v:at(#2)). rowid := v:at(#1).
                    local := sqlite:localSize(d, size, false).
                    end := v:at(#2):add(local):dec.
                    local:lessThan(size):ifTrue({ end := end:add(#4) }).
                    key := rowid },
                  { v := sqlite:varint(s, start).
                    end := v:at(#2):dec. key := v:at(#1) }) },
            { v := sqlite:varint(s, start). size := v:at(#1).
              local := sqlite:localSize(d, size, true).
              end := v:at(#2):add(local):dec.
              local:lessThan(size):ifTrue({ end := end:add(#4) }).
              key := sqlite:decodeRecord(sqlite:payload(d, s, v:at(#2), size, true)) }).
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

sqlite:compareEntry := { a, b | | c, i |
    c := #0. i := #1.
    { c:equals(#0):and({ i:lessOrEqual(a:size) }):and({ i:lessOrEqual(b:size) }) }:whileTrue({
        c := sqlite:compare(a:at(i), b:at(i)). i := i:inc }).
    c }.

sqlite:keyLess := { isIndex, a, b |
    isIndex:ifElse({ sqlite:compareEntry(a, b):lessThan(#0) }, { a:lessThan(b) }) }.

; Where a key goes among a page's keys: the first position whose key is
; greater, or one past the end.
sqlite:positionFor := { o, key, isIndex | | i |
    i := #1.
    { i:lessOrEqual(o:keys:size):and({ sqlite:keyLess(isIndex, o:keys:at(i), key):or({
        isIndex:not:and({ o:keys:at(i):equals(key) }) }) }) }:whileTrue({ i := i:inc }).
    i }.

; Which child of an interior page a key descends into: the first whose
; divider is not less than the key. On a table page the divider is the
; largest rowid under that child, so a rowid equal to it goes left, and
; `positionFor`, which steps past an equal rowid to refuse it as a
; duplicate on the leaf, would send it right. A rowid put back after being
; taken out, which is what `update` does, was the first to meet that: the
; divider stays 30 when rowid 30 is deleted, and the row went to the leaf
; after it, where `integrity_check` found it out of order.
sqlite:childFor := { o, key, isIndex | | i |
    i := #1.
    { i:lessOrEqual(o:keys:size):and({ sqlite:keyLess(isIndex, o:keys:at(i), key) }) }:whileTrue({ i := i:inc }).
    i }.

sqlite:insertAt := { arr, i, v | | out, k |
    out := []. k := #1.
    { k:lessThan(i) }:whileTrue({ out:add(arr:at(k)). k := k:inc }).
    out:add(v).
    { k:lessOrEqual(arr:size) }:whileTrue({ out:add(arr:at(k)). k := k:inc }).
    out }.

; Split page `o` (number n) in two: it keeps the left half, a new page takes
; the right, and the divider goes up as [raw, key, newPage]. The split point
; is where the bytes reach half.
sqlite:splitPage := { d, o, n, isIndex | | half, sum, k, right, rn, divider, extra |
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
          divider := [sqlite:varintBytes(o:keys:at(k)), o:keys:at(k), rn].
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
sqlite:insertCell := { d, n, raw, key, isIndex | | o, i, below |
    o := d:object(n).
    o:isLeaf:ifElse(
        { i := sqlite:positionFor(o, key, isIndex).
          ; The position is past any equal rowid, so the one before it is
          ; the duplicate to refuse.
          (isIndex:not:and({ i:greaterThan(#1) }):and({ o:keys:at(i:dec):equals(key) })):ifTrue({
              error:raise("UNIQUE constraint failed: rowid ":concat(key:asString)) }).
          o:cells := sqlite:insertAt(o:cells, i, raw).
          o:keys := sqlite:insertAt(o:keys, i, key) },
        { i := sqlite:childFor(o, key, isIndex).
          below := sqlite:insertCell(d, i:greaterThan(o:children:size):ifElse({ o:right }, { o:children:at(i) }),
                                    raw, key, isIndex).
          below:notNil:ifTrue({
              ; The child at i split: it stays as the left half under the
              ; divider, and the new page takes the child's old place.
              i:greaterThan(o:children:size):ifElse(
                  { o:cells:add(below:at(#1)). o:keys:add(below:at(#2)).
                    o:children:add(o:right). o:right := below:at(#3) },
                  { o:cells := sqlite:insertAt(o:cells, i, below:at(#1)).
                    o:keys := sqlite:insertAt(o:keys, i, below:at(#2)).
                    o:children := sqlite:insertAt(o:children, i, o:children:at(i)).
                    o:children:atPut(i:inc, below:at(#3)) }) }) }).
    o:fits(n, d):ifElse({ nil }, { sqlite:splitPage(d, o, n, isIndex) }) }.

; Insert at a tree's root, which keeps its page number however the tree
; grows: when the root splits, its left half moves to a new page and the root
; becomes an interior page over the two.
sqlite:treeInsert := { d, root, raw, key, isIndex | | divider, o, left, ln |
    divider := sqlite:insertCell(d, root, raw, key, isIndex).
    divider:notNil:ifTrue({
        o := d:object(root).
        ln := d:newPage(o:kind).
        left := d:object(ln).
        left:cells := o:cells. left:keys := o:keys. left:children := o:children. left:right := o:right.
        o:kind := o:isTable:ifElse({ #5 }, { #2 }).
        o:cells := [divider:at(#1)]. o:keys := [divider:at(#2)].
        o:children := [ln]. o:right := divider:at(#3) }) }.

; Removing `key` from the tree under page n. Answers nil when the page
; stands and #0 when it emptied, in which case the parent drops it and frees
; it. Every leaf of a tree is at one depth, and a removal must keep that, so
; nothing here is ever replaced by a shorter subtree: a page left with no
; cells and one child does not hand the child up, it hands the child's
; entries up, onto `again`, to be put back into the tree from the root once
; the removal is done, and the child's pages are freed. The same for an
; index interior cell whose child emptied, since the entry beside the child
; cannot stand without one, and for the case where that cell is itself the
; entry to remove. A table interior cell is a separator and not a row, so it
; just goes. The first draft of this handed a lone child up in place of its
; parent, and `integrity_check` said "Child page depth differs".
sqlite:removeCell := { arr, i | | out, k |
    out := []. k := #1.
    { k:lessOrEqual(arr:size) }:whileTrue({ k:notEquals(i):ifTrue({ out:add(arr:at(k)) }). k := k:inc }).
    out }.

; Every entry of the subtree under page n onto `again`, as [raw, key], and
; every page of it freed. For an index tree the interior cells are entries
; too; for a table tree only the leaves hold rows.
sqlite:collectEntries := { d, n, again, isIndex | | o |
    o := d:object(n).
    (o:isLeaf:or({ isIndex })):ifTrue({
        [#1, o:cells:size]:loop({ i | again:add([o:cells:at(i), o:keys:at(i)]) }) }).
    o:isLeaf:ifFalse({
        o:children:do({ c | sqlite:collectEntries(d, c, again, isIndex) }).
        sqlite:collectEntries(d, o:right, again, isIndex) }).
    d:freePage(n) }.

sqlite:deleteFrom := { d, n, key, isIndex, again, root | | o, i, found, child, below |
    o := d:object(n).
    found := nil. i := #1.
    { found:isNil:and({ i:lessOrEqual(o:keys:size) }) }:whileTrue({
        (isIndex:ifElse({ sqlite:compareEntry(o:keys:at(i), key):greaterOrEqual(#0) }, { o:keys:at(i):greaterOrEqual(key) })):ifTrue({ found := i }).
        found:isNil:ifTrue({ i := i:inc }) }).
    ; found is the first cell at or past the key, or nil for past them all.
    o:isLeaf:ifElse(
        { (found:notNil:and({ isIndex:ifElse({ sqlite:compareEntry(o:keys:at(found), key):equals(#0) }, { o:keys:at(found):equals(key) }) })):ifTrue({
              o:cells := sqlite:removeCell(o:cells, found).
              o:keys := sqlite:removeCell(o:keys, found) }).
          o:cells:size:equals(#0):ifElse({ #0 }, { nil }) },
        { (isIndex:and({ found:notNil }):and({ sqlite:compareEntry(o:keys:at(found), key):equals(#0) })):ifElse(
            { ; The entry is this interior cell: the cell goes, and the child
              ; beside it goes back in from the root.
              sqlite:collectEntries(d, o:children:at(found), again, true).
              o:cells := sqlite:removeCell(o:cells, found).
              o:keys := sqlite:removeCell(o:keys, found).
              o:children := sqlite:removeCell(o:children, found) },
            { child := found:isNil:ifElse({ o:right }, { o:children:at(found) }).
              below := sqlite:deleteFrom(d, child, key, isIndex, again, root).
              below:notNil:ifTrue({
                  ; The child emptied: free it and drop the cell beside it.
                  d:freePage(child).
                  found:isNil:ifElse(
                      { o:cells:size:greaterThan(#0):ifElse(
                            { isIndex:ifTrue({ again:add([o:cells:at(o:cells:size), o:keys:at(o:keys:size)]) }).
                              o:right := o:children:at(o:children:size).
                              o:cells := sqlite:removeCell(o:cells, o:cells:size).
                              o:keys := sqlite:removeCell(o:keys, o:keys:size).
                              o:children := sqlite:removeCell(o:children, o:children:size) },
                            { o:right := #0 }) },
                      { isIndex:ifTrue({ again:add([o:cells:at(found), o:keys:at(found)]) }).
                        o:cells := sqlite:removeCell(o:cells, found).
                        o:keys := sqlite:removeCell(o:keys, found).
                        o:children := sqlite:removeCell(o:children, found) }) }) }).
          ; A page with no cells and one child cannot stay, at any depth but
          ; the root's, which treeDelete handles: its child's entries go back
          ; in from the root, and it reports itself empty.
          (o:cells:size:equals(#0):and({ o:right:notEquals(#0) }):and({ n:notEquals(root) })):ifTrue({
              sqlite:collectEntries(d, o:right, again, isIndex).
              o:right := #0 }).
          o:right:equals(#0):ifElse({ #0 }, { nil }) }) }.

; Remove a key from a tree by its root, which keeps its page number: a root
; left with one child takes that child's contents and frees it, which
; shortens every path by one together; a root left with nothing is an empty
; leaf again. Then whatever the removal displaced goes back in.
sqlite:treeDelete := { d, root, key, isIndex | | again, result, o, child, c |
    again := [].
    result := sqlite:deleteFrom(d, root, key, isIndex, again, root).
    o := d:object(root).
    result:notNil:ifTrue({
        o:kind := o:isTable:ifElse({ #13 }, { #10 }).
        o:cells := []. o:keys := []. o:children := []. o:right := #0 }).
    (o:isLeaf:not:and({ o:cells:size:equals(#0) })):ifTrue({
        child := o:right.
        c := d:object(child).
        o:kind := c:kind. o:cells := c:cells. o:keys := c:keys. o:children := c:children. o:right := c:right.
        d:freePage(child) }).
    again:do({ e | sqlite:treeInsert(d, root, e:at(#1), e:at(#2), isIndex) }) }.

; The largest rowid in a table tree, or nil when it is empty: down the
; right-most path to the last leaf.
sqlite:lastRowid := { d, n | | p, h, offsets, v |
    p := d:page(n). h := sqlite:headerAt(n).
    offsets := sqlite:cells(p, n).
    sqlite:u8(p, h):equals(#13):ifElse(
        { offsets:size:equals(#0):ifElse({ nil },
              { v := sqlite:varint(p, offsets:at(offsets:size)).
                sqlite:varint(p, v:at(#2)):at(#1) }) },
        { sqlite:lastRowid(d, sqlite:u32(p, h:add(#8))) }) }.

; ---------------------------------------------------------------------------
; B-tree pages

; Where a page's header begins: after the file header on page 1.
sqlite:headerAt := { n | n:equals(#1):ifElse({ #101 }, { #1 }) }.

; The cell offsets of a page, as one-based indices into the page string.
sqlite:cells := { p, n | | h, count, first, out, i |
    h := sqlite:headerAt(n).
    count := sqlite:u16(p, h:add(#3)).
    first := h:add(sqlite:u8(p, h):equals(#5):or({ sqlite:u8(p, h):equals(#2) })
        :ifElse({ #12 }, { #8 })).
    out := [].
    i := #0.
    { i:lessThan(count) }:whileTrue({
        out:add(sqlite:u16(p, first:add(i:mul(#2))):inc).
        i := i:inc }).
    out }.

; How much of a payload of `total` bytes stays on the page. A table leaf may
; keep up to U-35 of it; an index page, whose cells are compared on the way
; down, keeps at most a quarter of the usable size so that a page holds at
; least four keys.
sqlite:localSize := { d, total, isIndex | | maxLocal, minLocal, k |
    maxLocal := isIndex:ifElse({ d:usable:sub(#12):mul(#64):div(#255):sub(#23) },
                               { d:usable:sub(#35) }).
    total:lessOrEqual(maxLocal):ifElse({ total }, {
        minLocal := d:usable:sub(#12):mul(#32):div(#255):sub(#23).
        k := minLocal:add(total:sub(minLocal):mod(d:usable:sub(#4))).
        k:lessOrEqual(maxLocal):ifElse({ k }, { minLocal }) }) }.

; A payload of `total` bytes starting at `at` on page `p`: the local part,
; and then the overflow chain, each page a pointer and then bytes.
sqlite:payload := { d, p, at, total, isIndex | | local, out, next, chunk, take, remaining |
    local := sqlite:localSize(d, total, isIndex).
    out := p:copyFrom(at, at:add(local):dec).
    local:lessThan(total):ifTrue({
        next := sqlite:u32(p, at:add(local)).
        remaining := total:sub(local).
        { remaining:greaterThan(#0) }:whileTrue({
            chunk := d:page(next).
            take := remaining:lessThan(d:usable:sub(#4)):ifElse({ remaining }, { d:usable:sub(#4) }).
            out := out:concat(chunk:copyFrom(#5, take:add(#4))).
            remaining := remaining:sub(take).
            next := sqlite:u32(chunk, #1) }) }).
    out }.

; Every row of a table tree, in rowid order: the block is given the rowid and
; the payload. Interior cells are a child and the largest rowid in it; the
; right-most child holds the rest.
sqlite:eachRow := { d, n, block | | p, h, kind, offsets, i, at, v, size, rowid |
    p := d:page(n).
    h := sqlite:headerAt(n).
    kind := sqlite:u8(p, h).
    offsets := sqlite:cells(p, n).
    kind:equals(#13):ifElse(
        { offsets:do({ at |
              v := sqlite:varint(p, at). size := v:at(#1).
              v := sqlite:varint(p, v:at(#2)). rowid := v:at(#1).
              block:value(rowid, sqlite:payload(d, p, v:at(#2), size, false)) }) },
        { kind:equals(#5):ifFalse({
              error:raise("page ":concat(n:asString):concat(" is not a table page")) }).
          offsets:do({ at | sqlite:eachRow(d, sqlite:u32(p, at), block) }).
          sqlite:eachRow(d, sqlite:u32(p, h:add(#8)), block) }) }.

; One row by rowid: descend to the leaf that would hold it, then look. Answers
; the payload or nil.
sqlite:findRow := { d, n, want | | p, h, kind, offsets, found, i, at, v, size, rowid, child |
    p := d:page(n).
    h := sqlite:headerAt(n).
    kind := sqlite:u8(p, h).
    offsets := sqlite:cells(p, n).
    found := nil.
    kind:equals(#13):ifElse(
        { i := #1.
          { found:isNil:and({ i:lessOrEqual(offsets:size) }) }:whileTrue({
              at := offsets:at(i).
              v := sqlite:varint(p, at). size := v:at(#1).
              v := sqlite:varint(p, v:at(#2)). rowid := v:at(#1).
              rowid:equals(want):ifTrue({ found := sqlite:payload(d, p, v:at(#2), size, false) }).
              i := i:inc }).
          found },
        { child := nil. i := #1.
          { child:isNil:and({ i:lessOrEqual(offsets:size) }) }:whileTrue({
              at := offsets:at(i).
              want:lessOrEqual(sqlite:varint(p, at:add(#4)):at(#1)):ifTrue({
                  child := sqlite:u32(p, at) }).
              i := i:inc }).
          child:isNil:ifTrue({ child := sqlite:u32(p, h:add(#8)) }).
          sqlite:findRow(d, child, want) }) }.

; Every entry of an index tree whose first column equals `want`, in index
; order: the block is given the entry's record, whose last value is the rowid.
; An index cell is a record on a leaf, and a child then a record on an interior
; page, where the record is an entry in its own right and everything in the
; child before it is less. So the walk is an in-order traversal that prunes:
; a child is skipped when its cell's key is already below `want`, and the
; walk stops at the first key above it, since equal keys are contiguous.
; Answers whether the walk has passed `want`, so a caller up the tree stops.
sqlite:eachIndexMatch := { d, n, want, block | | p, h, kind, offsets, i, at, v, size, entry, c, past, isLeaf |
    p := d:page(n).
    h := sqlite:headerAt(n).
    kind := sqlite:u8(p, h).
    isLeaf := kind:equals(#10).
    isLeaf:or({ kind:equals(#2) }):ifFalse({
        error:raise("page ":concat(n:asString):concat(" is not an index page")) }).
    offsets := sqlite:cells(p, n).
    past := false. i := #1.
    { past:not:and({ i:lessOrEqual(offsets:size) }) }:whileTrue({
        at := offsets:at(i).
        isLeaf:ifFalse({ at := at:add(#4) }).
        v := sqlite:varint(p, at). size := v:at(#1).
        entry := sqlite:decodeRecord(sqlite:payload(d, p, v:at(#2), size, true)).
        c := sqlite:compare(entry:at(#1), want).
        ; The child before this key can hold equals only when the key is
        ; not already below `want`.
        isLeaf:not:and({ c:greaterOrEqual(#0) }):ifTrue({
            past := sqlite:eachIndexMatch(d, sqlite:u32(p, offsets:at(i)), want, block) }).
        c:equals(#0):ifTrue({ block:value(entry) }).
        c:greaterThan(#0):ifTrue({ past := true }).
        i := i:inc }).
    past:not:and({ isLeaf:not }):ifTrue({
        past := sqlite:eachIndexMatch(d, sqlite:u32(p, h:add(#8)), want, block) }).
    past }.

; ---------------------------------------------------------------------------
; Records

; The values of a record, as an array. Fewer values than the table has
; columns is a table altered since the row was written, and the rest are NULL
; to the caller.
sqlite:decodeRecord := { s | | v, headerSize, at, types, values, bodyAt, t, n |
    v := sqlite:varint(s, #1).
    headerSize := v:at(#1). at := v:at(#2).
    types := [].
    { at:lessOrEqual(headerSize) }:whileTrue({
        v := sqlite:varint(s, at). types:add(v:at(#1)). at := v:at(#2) }).
    values := [].
    bodyAt := headerSize:inc.
    types:do({ t |
        t:equals(#0):ifTrue({ values:add(nil) }).
        t:greaterOrEqual(#1):and({ t:lessOrEqual(#6) }):ifTrue({
            n := [#1, #2, #3, #4, #6, #8]:at(t).
            values:add(sqlite:signedBytes(s, bodyAt, n)).
            bodyAt := bodyAt:add(n) }).
        t:equals(#7):ifTrue({
            values:add(sqlite:real:of(sqlite:floatFromBytes(s, bodyAt))).
            bodyAt := bodyAt:add(#8) }).
        t:equals(#8):ifTrue({ values:add(#0) }).
        t:equals(#9):ifTrue({ values:add(#1) }).
        t:greaterOrEqual(#12):ifTrue({
            n := t:sub(#12):div(#2).
            t:mod(#2):equals(#0):ifElse(
                { values:add(sqlite:blob:of(n:equals(#0):ifElse({ "" }, { s:copyFrom(bodyAt, bodyAt:add(n):dec) }))) },
                { values:add(n:equals(#0):ifElse({ "" }, { s:copyFrom(bodyAt, bodyAt:add(n):dec) })) }).
            bodyAt := bodyAt:add(n) }) }).
    values }.

; ---------------------------------------------------------------------------
; SQL, the tokens
;
; Words, numbers, 'text' with '' inside it, X'hex', "quoted names", and the
; punctuation this file's SQL has. Each token is [kind, text]: 'word, 'number,
; 'text, 'blob, 'name or 'punct.

sqlite:isWordStart := { c | | b | b := c:asByte.
    b:greaterOrEqual(#65):and({ b:lessOrEqual(#90) })
        :or({ b:greaterOrEqual(#97):and({ b:lessOrEqual(#122) }) })
        :or({ c:equals("_") }):or({ b:greaterOrEqual(#128) }) }.
sqlite:isDigit := { c | | b | b := c:asByte. b:greaterOrEqual(#48):and({ b:lessOrEqual(#57) }) }.
sqlite:isWordChar := { c | sqlite:isWordStart(c):or({ sqlite:isDigit(c) }) }.
sqlite:isSpace := { c | c:equals(" "):or({ c:equals("\n") }):or({ c:equals("\t") }):or({ c:equals("\r") }) }.

; A quoted run with the quote doubled inside, the quote already consumed.
sqlite:quoted := { s, q | | out, done |
    out := "". done := false.
    { done:not }:whileTrue({
        s:atEnd:ifTrue({ error:raise("unterminated string") }).
        s:peek:equals(q):ifElse(
            { s:step.
              s:peek:equals(q):ifElse({ out := out:concat(q). s:step }, { done := true }) },
            { out := out:concat(s:next) }) }).
    out }.

sqlite:hexValue := { c | | b | b := c:asByte.
    b:lessOrEqual(#57):ifElse({ b:sub(#48) },
        { b:lessOrEqual(#70):ifElse({ b:sub(#55) }, { b:sub(#87) }) }) }.

sqlite:unhex := { h | | out, i |
    h:size:mod(#2):equals(#1):ifTrue({ error:raise("odd number of hex digits in a blob") }).
    out := []. i := #1.
    { i:lessThan(h:size) }:whileTrue({
        out:add(sqlite:hexValue(h:at(i)):mul(#16):add(sqlite:hexValue(h:at(i:inc))):asCharacter).
        i := i:add(#2) }).
    out:join("") }.

sqlite:tokenize := { text | | s, out, c, word, from, push |
    s := scan:on(text). out := [].
    ; A token is [kind, text, from, to], the last two the positions in the
    ; source, so that a CREATE statement can be stored as it was written.
    push := { kind, t | out:add([kind, t, from, s:pos:dec]) }.
    { s:atEnd:not }:whileTrue({
        c := s:peek. from := s:pos.
        sqlite:isSpace(c):ifElse({ s:step },
        { (c:equals("-"):and({ s:peekAt(#1):equals("-") })):ifElse(
            { s:skipWhile({ ch | ch:notEquals("\n") }) },
        { sqlite:isWordStart(c):ifElse(
            { word := s:takeWhile(sqlite:slotAt('isWordChar)).
              (word:asUppercase:equals("X"):and({ s:peek:equals("'") })):ifElse(
                  { s:step. push:value('blob, sqlite:unhex(sqlite:quoted(s, "'"))) },
                  { push:value('word, word) }) },
        { (sqlite:isDigit(c):or({ c:equals("."):and({ s:peekAt(#1):notNil }):and({ sqlite:isDigit(s:peekAt(#1)) }) })):ifElse(
            { word := s:takeWhile({ ch | sqlite:isDigit(ch):or({ ch:equals(".") }) }).
              (s:peek:notNil:and({ s:peek:asUppercase:equals("E") })):ifTrue({
                  word := word:concat(s:next).
                  (s:peek:equals("+"):or({ s:peek:equals("-") })):ifTrue({ word := word:concat(s:next) }).
                  word := word:concat(s:takeWhile(sqlite:slotAt('isDigit))) }).
              push:value('number, word) },
        { c:equals("'"):ifElse({ s:step. push:value('text, sqlite:quoted(s, "'")) },
        { c:equals("\""):ifElse({ s:step. push:value('name, sqlite:quoted(s, "\"")) },
        { c:equals("`"):ifElse({ s:step. push:value('name, sqlite:quoted(s, "`")) },
        { c:equals("["):ifElse({ s:step. word := s:takeUntil({ ch | ch:equals("]") }). s:step. push:value('name, word) },
        { "(),;*=.<>-":indexOf(c):notNil:ifElse({ s:step. push:value('punct, c) },
            ; Anything else is a byte this SQL has no use for.
            { error:raise("unexpected character: ":concat(c)) }) }) }) }) }) }) }) }) }) }).
    out }.

; Statements: the tokens split at `;`.
sqlite:statements := { tokens | | out, current |
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

sqlite:table := object:new.
sqlite:table:name := "".
sqlite:table:root := #0.
sqlite:table:columns := [].           ; each [name, affinity, isRowid]
sqlite:table:indexes := [].           ; each [name, root, column names], plain ascending BINARY ones
sqlite:table:maxRowid := nil.         ; the largest rowid, once it has been looked for

; The affinity rules, from the declared type: INT anywhere is INTEGER; CHAR,
; CLOB or TEXT is TEXT; BLOB or no type is BLOB; REAL, FLOA or DOUB is REAL;
; anything else NUMERIC.
sqlite:affinityOf := { typeText | | t |
    t := typeText:asUppercase.
    t:indexOf("INT"):notNil:ifElse({ 'integer },
        { t:indexOf("CHAR"):notNil:or({ t:indexOf("CLOB"):notNil }):or({ t:indexOf("TEXT"):notNil }):ifElse({ 'text },
            { t:equals(""):or({ t:indexOf("BLOB"):notNil }):ifElse({ 'blob },
                { t:indexOf("REAL"):notNil:or({ t:indexOf("FLOA"):notNil }):or({ t:indexOf("DOUB"):notNil }):ifElse({ 'real },
                    { 'numeric }) }) }) }) }.

sqlite:constraintWords := ["CONSTRAINT", "PRIMARY", "NOT", "NULL", "UNIQUE", "CHECK", "DEFAULT",
                    "COLLATE", "REFERENCES", "GENERATED", "AS"].
sqlite:isConstraintWord := { w | sqlite:constraintWords:indexOf(w:asUppercase):notNil }.

; The tokens between the outer parentheses of a CREATE TABLE, split at the
; commas that are not inside parentheses of their own.
sqlite:columnsFromSql := { sql | | tokens, i, depth, groups, current, out, name, typeWords, isPk, j, t, inType |
    tokens := sqlite:tokenize(sql).
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
        (g:at(#1):at(#1):equals('word):and({ sqlite:isConstraintWord(g:at(#1):at(#2)) })
            :and({ g:at(#1):at(#2):asUppercase:equals("PRIMARY"):or({ g:at(#1):at(#2):asUppercase:equals("UNIQUE") })
                :or({ g:at(#1):at(#2):asUppercase:equals("CHECK") }):or({ g:at(#1):at(#2):asUppercase:equals("CONSTRAINT") })
                :or({ g:at(#1):at(#2):asUppercase:equals("FOREIGN") }) })):ifFalse({
            name := g:at(#1):at(#2).
            typeWords := []. isPk := false. j := #2. inType := true.
            { j:lessOrEqual(g:size) }:whileTrue({
                t := g:at(j).
                inType:and({ t:at(#1):equals('word) }):and({ sqlite:isConstraintWord(t:at(#2)):not }):ifElse(
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
            out:add([name, sqlite:affinityOf(typeWords:join(" ")), isPk]) }) }).
    out }.

; `CREATE INDEX name ON table (col, col)`. An index this reader can use is on
; plain column names in ascending BINARY order and over the whole table; one
; with DESC, COLLATE, an expression or a WHERE is left alone, since an entry
; in it is not in the order the walk assumes. Answers the column names, or nil.
sqlite:indexColumnsFromSql := { sql | | tokens, i, out, plain, t |
    tokens := sqlite:tokenize(sql).
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

sqlite:schemaTable := { | t |
    t := sqlite:table:new.
    t:name := "sqlite_schema".
    t:root := #1.
    t:columns := [["type", 'text, false], ["name", 'text, false], ["tbl_name", 'text, false],
                  ["rootpage", 'integer, false], ["sql", 'text, false]].
    t }.

; The tables in a database, by lower-cased name.
sqlite:loadSchema := { d | | out, t |
    out := dictionary:new.
    out:atPut("sqlite_schema", sqlite:schemaTable).
    out:atPut("sqlite_master", out:at("sqlite_schema")).
    sqlite:eachRow(d, #1, { rowid, p | | r |
        r := sqlite:decodeRecord(p).
        r:at(#1):equals("table"):ifTrue({
            t := sqlite:table:new.
            t:name := r:at(#2).
            t:root := r:at(#4).
            t:columns := sqlite:columnsFromSql(r:at(#5)).
            t:indexes := [].
            out:atPut(t:name:asLowercase, t) }) }).
    ; Indexes second, since one may precede its table in the schema. An
    ; automatic index has no SQL and is skipped: its columns are in the
    ; table's constraints, which this reader does not follow.
    sqlite:eachRow(d, #1, { rowid, p | | r, cols |
        r := sqlite:decodeRecord(p).
        (r:at(#1):equals("index"):and({ r:at(#5):notNil })):ifTrue({
            cols := sqlite:indexColumnsFromSql(r:at(#5)).
            (cols:notNil:and({ out:includes(r:at(#3):asLowercase) })):ifTrue({
                out:at(r:at(#3):asLowercase):indexes:add([r:at(#2), r:at(#4), cols]) }) }) }).
    out }.



; Which column a name is: an index into the record, or 'rowid. `rowid` and
; its aliases, and an INTEGER PRIMARY KEY column, are the rowid.
sqlite:resolve := { t, name | | found, i, lower |
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
sqlite:affinityAt := { t, which |
    which:equals('rowid):ifElse({ 'integer }, { t:columns:at(which):at(#2) }) }.

; A row's value at a resolved column.
sqlite:valueAt := { rowid, values, which |
    which:equals('rowid):ifElse({ rowid },
        { which:greaterThan(values:size):ifElse({ nil }, { values:at(which) }) }) }.

; Text that is a well-formed number, as a number; else nil. SQLite's rule for
; NUMERIC affinity: an integer literal if it is one and fits, else a real.
sqlite:numberFromText := { s | | t |
    t := s:trim.
    t:equals(""):ifElse({ nil }, {
        { | n | n := t:asInteger. n }:onError({ e |
            { | f | f := t:asFloat. sqlite:real:of(sqlite:floatParts(f)) }:onError({ e2 | nil }) }) }) }.

; Applying an affinity to a literal before a comparison: a column with
; numeric affinity makes a numeric-looking text a number, a column with text
; affinity makes a number text, and nothing happens to a blob or a NULL.
sqlite:applyAffinity := { v, affinity | | n |
    v:isNil:or({ v:isKindOf(sqlite:blob) }):ifElse({ v }, {
        (affinity:equals('integer):or({ affinity:equals('real) }):or({ affinity:equals('numeric) })):ifElse(
            { v:isKindOf(string):ifElse({ n := sqlite:numberFromText(v). n:isNil:ifElse({ v }, { n }) }, { v }) },
            { affinity:equals('text):ifElse(
                { sqlite:isNumber(v):ifElse({ sqlite:render(v) }, { v }) },
                { v }) }) }) }.

; One comparison, SQLite's way: NULL on either side is no match, otherwise
; the order compare gives.
sqlite:holds := { a, op, b | | c |
    a:isNil:or({ b:isNil }):ifElse({ false }, {
        c := sqlite:compare(a, b).
        op:equals("="):ifElse({ c:equals(#0) },
        { op:equals("<"):ifElse({ c:lessThan(#0) },
        { op:equals(">"):ifElse({ c:greaterThan(#0) },
        { op:equals("<="):ifElse({ c:lessOrEqual(#0) }, { c:greaterOrEqual(#0) }) }) }) }) }) }.

; The rows of table t that a WHERE keeps, each [rowid, values] with REAL
; columns turned back into reals. By rowid when a term names it with =;
; through an index when a term is = on its first column; else every row. The
; three answer the same rows, and differ in pages read.
sqlite:matchingRows := { d, t, where | | terms, realColumns, rows, keep, index, rowidTerm, eqTerm |
    ; Terms resolved: [column, op, value with the column's affinity applied].
    terms := where:collect({ w | | which |
        which := sqlite:resolve(t, w:at(#1)).
        [which, w:at(#2), sqlite:applyAffinity(w:at(#3), sqlite:affinityAt(t, which))] }).
    ; A REAL column stores a whole number as an integer to save the bytes, and
    ; it is a real again on the way out: the one place a column's declared
    ; type changes what a record says.
    realColumns := [].
    [#1, t:columns:size]:loop({ i |
        t:columns:at(i):at(#2):equals('real):ifTrue({ realColumns:add(i) }) }).
    rows := [].
    keep := { rowid, values | | ok |
        realColumns:do({ i |
            (i:lessOrEqual(values:size):and({ values:at(i):isKindOf(integer) })):ifTrue({
                values:atPut(i, sqlite:real:of(sqlite:floatParts(values:at(i):asFloat))) }) }).
        ok := true.
        terms:do({ term | ok := ok:and({ sqlite:holds(sqlite:valueAt(rowid, values, term:at(#1)), term:at(#2), term:at(#3)) }) }).
        ok:ifTrue({ rows:add([rowid, values]) }) }.

    rowidTerm := nil. eqTerm := nil. index := nil.
    terms:do({ term |
        term:at(#2):equals("="):ifTrue({
            term:at(#1):equals('rowid):ifTrue({ rowidTerm := term }).
            (term:at(#1):notEquals('rowid):and({ term:at(#3):notNil }):and({ eqTerm:isNil })):ifTrue({
                t:indexes:do({ ix |
                    index:isNil:and({ sqlite:resolve(t, ix:at(#3):at(#1)):equals(term:at(#1)) }):ifTrue({
                        index := ix. eqTerm := term }) }) }) }) }).

    rowidTerm:notNil:ifElse(
        { | v |
          v := rowidTerm:at(#3).
          v:isKindOf(integer):ifTrue({ | p |
              p := sqlite:findRow(d, t:root, v).
              p:notNil:ifTrue({ keep:value(v, sqlite:decodeRecord(p)) }) }).
          v:isKindOf(sqlite:real):ifTrue({ | f, n |
              ; A real equal to an integer finds that rowid; any other finds none.
              f := v:value.
              f:equals(f:floor:asFloat):ifTrue({ | p |
                  n := f:floor.
                  p := sqlite:findRow(d, t:root, n).
                  p:notNil:ifTrue({ keep:value(n, sqlite:decodeRecord(p)) }) }) }) },
        { index:notNil:ifElse(
            { sqlite:eachIndexMatch(d, index:at(#2), eqTerm:at(#3), { entry | | rowid, p |
                  rowid := entry:at(entry:size).
                  p := sqlite:findRow(d, t:root, rowid).
                  p:isNil:ifTrue({ error:raise("index ":concat(index:at(#1)):concat(" names rowid ")
                      :concat(rowid:asString):concat(" and the table has no such row")) }).
                  keep:value(rowid, sqlite:decodeRecord(p)) }) },
            { sqlite:eachRow(d, t:root, { rowid, p | keep:value(rowid, sqlite:decodeRecord(p)) }) }) }).
    rows }.

; A real that is a whole number and fits is stored as the integer; SQLite
; does the same, for NUMERIC affinity as the rule and for REAL as the disk
; trick the reader undoes.
sqlite:integralOf := { v | | f |
    f := v:value.
    ; Strictly inside the integers, both ends: SQLite keeps -2^63 itself a
    ; real. A bound of 9.2e18 here left 9206812213021190144.0 a real that
    ; sqlite3 stores as an integer, on the fifth seed of the sweep.
    (f:lessThan(9223372036854775808.0):and({ f:greaterThan(-9223372036854775808.0) })
        :and({ f:equals(f:floor:asFloat) })):ifElse({ f:floor }, { v }) }.

; The affinity applied to a value on its way into a column: text that reads
; as a number becomes one under a numeric affinity, a number becomes text
; under TEXT, and a blob or a NULL is left alone.
sqlite:storeAffinity := { v, affinity | | n |
    v:isNil:or({ v:isKindOf(sqlite:blob) }):ifElse({ v }, {
        affinity:equals('text):ifElse(
            { sqlite:isNumber(v):ifElse({ sqlite:render(v) }, { v }) },
        { affinity:equals('blob):ifElse({ v }, {
            ; INTEGER, NUMERIC and REAL: a numeric text is read, and a whole real
            ; becomes the integer.
            n := v:isKindOf(string):ifElse({ sqlite:numberFromText(v) }, { v }).
            n:isNil:ifElse({ v },
                { n:isKindOf(sqlite:real):ifElse({ sqlite:integralOf(n) }, { n }) }) }) }) }) }.

; What a value written to the INTEGER PRIMARY KEY column means as a rowid.
sqlite:rowidOf := { v | | n |
    v:isKindOf(integer):ifElse({ v }, {
        n := v:isKindOf(string):ifElse({ sqlite:numberFromText(v) }, { v }).
        n:isKindOf(sqlite:real):ifTrue({ n := sqlite:integralOf(n) }).
        n:isKindOf(integer):ifElse({ n }, { error:raise("datatype mismatch") }) }) }.

; One row into a table and each of its indexes. `values` is one per column,
; affinities applied; the rowid is given or is one past the largest.
sqlite:insertRow := { d, t, values, rowidGiven | | rowid, record, payload, raw, maxLocal |
    rowid := rowidGiven.
    rowid:isNil:ifTrue({
        t:maxRowid:isNil:ifTrue({ t:maxRowid := sqlite:lastRowid(d, t:root) }).
        rowid := t:maxRowid:isNil:ifElse({ #1 }, {
            t:maxRowid:equals(#9223372036854775807):ifTrue({
                error:raise("database or disk is full: no rowid is left to assign") }).
            t:maxRowid:inc }) }).
    ; The rowid column's value in the record is NULL: it is the rowid.
    record := [].
    [#1, t:columns:size]:loop({ i |
        record:add(t:columns:at(i):at(#3):ifElse({ nil }, { i:lessOrEqual(values:size):ifElse({ values:at(i) }, { nil }) })) }).
    payload := sqlite:recordBytes(record).
    maxLocal := d:usable:sub(#35).
    payload:size:greaterThan(maxLocal):ifTrue({
        error:raise("a row of ":concat(payload:size:asString):concat(" bytes needs an overflow page, and this program does not write those (")
            :concat(maxLocal:asString):concat(" fit)")) }).
    raw := sqlite:varintBytes(payload:size):concat(sqlite:varintBytes(rowid)):concat(payload).
    sqlite:treeInsert(d, t:root, raw, rowid, false).
    (t:maxRowid:isNil:or({ rowid:greaterThan(t:maxRowid) })):ifTrue({ t:maxRowid := rowid }).
    t:indexes:do({ ix | | entry |
        entry := ix:at(#3):collect({ name | | which |
            which := sqlite:resolve(t, name).
            which:equals('rowid):ifElse({ rowid }, { values:at(which) }) }).
        entry:add(rowid).
        payload := sqlite:recordBytes(entry).
        maxLocal := d:usable:sub(#12):mul(#64):div(#255):sub(#23).
        payload:size:greaterThan(maxLocal):ifTrue({
            error:raise("an index entry of ":concat(payload:size:asString):concat(" bytes needs an overflow page, and this program does not write those")) }).
        raw := sqlite:varintBytes(payload:size):concat(payload).
        sqlite:treeInsert(d, ix:at(#2), raw, entry, true) }).
    rowid }.

; A row of sqlite_schema, which is a table like any other with page 1 as
; its root and no rowid column of its own.
sqlite:schemaRow := { d, kind, name, tblName, root, sql |
    sqlite:insertRow(d, d:tables:at("sqlite_schema"), [kind, name, tblName, root, sql], nil).
    d:cookie := d:cookie:inc }.

; A table made: `sql` is the CREATE statement as it will be stored, which is
; the statement as written, since sqlite3 keeps what it was given after the
; two words it spells for itself.
sqlite:createTable := { d, name, sql | | t |
    d:tables:includes(name:asLowercase):ifTrue({ error:raise("table ":concat(name):concat(" already exists")) }).
    t := sqlite:table:new.
    t:name := name.
    t:db := d.
    t:columns := sqlite:columnsFromSql(sql).
    t:columns:size:equals(#0):ifTrue({ error:raise("CREATE TABLE ":concat(name):concat(" has no columns")) }).
    t:indexes := []. t:maxRowid := nil.
    t:root := d:newPage(#13).
    sqlite:schemaRow(d, "table", name, name, t:root, sql).
    d:tables:atPut(name:asLowercase, t).
    t }.

; An index made on `cols` of table t, and every row the table already has
; put into it.
sqlite:createIndex := { d, t, name, cols, sql | | root, ix |
    cols:do({ c | sqlite:resolve(t, c) }).
    root := d:newPage(#10).
    sqlite:schemaRow(d, "index", name, t:name, root, sql).
    ix := [name, root, cols].
    t:indexes:add(ix).
    sqlite:eachRow(d, t:root, { rowid, p | | values, entry, payload, raw |
        values := sqlite:decodeRecord(p).
        entry := cols:collect({ c | | which |
            which := sqlite:resolve(t, c).
            which:equals('rowid):ifElse({ rowid }, { which:greaterThan(values:size):ifElse({ nil }, { values:at(which) }) }) }).
        entry:add(rowid).
        payload := sqlite:recordBytes(entry).
        raw := sqlite:varintBytes(payload:size):concat(payload).
        sqlite:treeInsert(d, root, raw, entry, true) }).
    ix }.

; One row out of a table and each of its indexes. The index entries are
; rebuilt from the row's values as they were put in, which is why the values
; come along; `values` here are as stored, REAL columns included, since a
; stored integer and a real that equals it compare as equal anyway.
sqlite:deleteRow := { d, t, rowid, values |
    t:indexes:do({ ix | | entry |
        entry := ix:at(#3):collect({ name | | which |
            which := sqlite:resolve(t, name).
            which:equals('rowid):ifElse({ rowid }, { sqlite:valueAt(rowid, values, which) }) }).
        entry:add(rowid).
        sqlite:treeDelete(d, ix:at(#2), entry, true) }).
    sqlite:treeDelete(d, t:root, rowid, false).
    ; The next rowid assigned is one past the largest that remains, as
    ; SQLite assigns it, so the largest is looked for again.
    t:maxRowid := nil }.

; ---------------------------------------------------------------------------
; The objects
;
; The engine above is functions over a database `d` and a table `t`, and
; the SQL shell was the only thing that called them until 2026-09-15. This
; is the other front, the one the database was wanted for: the database an
; object, each table an object, a query over one, and a row. The shell is a
; client of these now, so the sweep that holds the shell against sqlite3
; holds these too.
;
;     db := sqlite:open("notes.db").
;     notes := db:create("notes", ["title TEXT", "done INTEGER"]).
;     notes:insert(#['title = "milk", 'done = #0]).
;     notes:where(#['done = #0]):each({ n | n:title:display }).
;     n := notes:find(#1). n:done := #1. n:save.
;     notes:filter("done", "=", #1):delete.
;     db:close.
;
; A row is an object whose columns are its slots, spelled as the schema
; spells them, with `rowid`, `table`, `save` and `delete` beside them; a
; REAL comes out as a float and a blob as a `sqlite:blob`. The slots are
; made by `object:new(dictionary)`, which is the one message that makes a
; slot from a name held in a value, and was built for this on 2026-09-15
; after a version of these rows as dictionaries had run through the sweep:
; the plan in ideas.md says why in that order.

; Columns are named by string or symbol, and matched as SQL matches them.
sqlite:nameOf := { key | key:isKindOf(symbol):ifElse({ key:asString }, { key }) }.

; A value as a caller has it, and as the engine stores it: a float is a
; `real` inside, carrying its parts for the exact printer.
sqlite:toStored := { v |
    v:isKindOf(float):ifElse({ sqlite:real:of(sqlite:floatParts(v)) }, { v }) }.
sqlite:toValue := { v |
    v:isKindOf(sqlite:real):ifElse({ v:value }, { v }) }.

; Open a file, or begin one, and read its schema.
sqlite:open := { path | | d |
    d := sqlite:db:open(path).
    d:tables := sqlite:loadSchema(d).
    d:tables:do({ t | t:db := d }).
    d }.

; The tables by name, in the order sqlite_schema has them, which is the
; order they were made in.
sqlite:db:tableNames := { | out |
    out := [].
    sqlite:eachRow(self, #1, { rowid, p | | r |
        r := sqlite:decodeRecord(p).
        r:at(#1):equals("table"):ifTrue({ out:add(r:at(#2)) }) }).
    out }.

; A table by name, or nil. A table whose column is named for one of the
; four messages a row answers is refused here, by name, since a row of it
; could not be saved through the slot its column would shadow.
sqlite:db:table := { name | | t |
    t := self:tables:at(sqlite:nameOf(name):asLowercase, nil).
    t:notNil:ifTrue({ t:checkColumnNames }).
    t }.

; A table made from its columns, each spelled as SQL spells one: "title
; TEXT", "id INTEGER PRIMARY KEY". The schema is SQL text in the file
; whatever this front says, so this is the one place a caller writes some.
sqlite:db:create := { name, columns | | t |
    columns:size:equals(#0):ifTrue({ error:raise("a table needs at least one column") }).
    t := sqlite:createTable(self, name,
        "CREATE TABLE ":concat(name):concat(" ("):concat(columns:join(", ")):concat(")")).
    t:checkColumnNames.
    t }.

; Written and done. `flush` writes without forgetting anything, for a
; program that wants sqlite3 to look before it is finished.
sqlite:db:close := { self:flush. self:tables := nil. self:cache := dictionary:new. nil }.

; ---- a table ------------------------------------------------------------

sqlite:table:db := nil.
sqlite:table:proto := nil.            ; the prototype of this table's rows, once made

sqlite:rowMessages := ["rowid", "table", "save", "delete", "asDictionary"].
sqlite:table:checkColumnNames := {
    self:columns:do({ c |
        sqlite:rowMessages:indexOf(c:at(#1):asLowercase):notNil:ifTrue({
            error:raise("column ":concat(c:at(#1)):concat(" of "):concat(self:name)
                :concat(" is named for a message every row answers, and a row of this table could not be saved through it")) }) }) }.

; The prototype every row of this table delegates to: the table, and the
; four messages a row answers.
sqlite:table:rowProto := {
    self:proto:isNil:ifTrue({
        self:proto := sqlite:row:new.
        self:proto:table := self }).
    self:proto }.

; The column names, in schema order.
sqlite:table:columnNames := { self:columns:collect({ c | c:at(#1) }) }.

; An index on these columns, named.
sqlite:table:index := { name, columns | | cols |
    cols := columns:collect({ c | sqlite:nameOf(c) }).
    sqlite:createIndex(self:db, self, name, cols,
        "CREATE INDEX ":concat(name):concat(" ON "):concat(self:name):concat(" ("):concat(cols:join(", ")):concat(")")) }.

; An engine row, [rowid, values as stored], as a caller's row: an object
; under the table's prototype, a slot a column.
sqlite:table:rowFrom := { r | | slots, row |
    slots := dictionary:new.
    slots:atPut('rowid, r:at(#1)).
    [#1, self:columns:size]:loop({ i | | v |
        v := sqlite:valueAt(r:at(#1), r:at(#2), i).
        ; A REAL column stores a whole number as an integer; it is a float
        ; again on the way out.
        (self:columns:at(i):at(#2):equals('real):and({ v:isKindOf(integer) })):ifTrue({ v := v:asFloat }).
        slots:atPut(self:columns:at(i):at(#1):asSymbol, sqlite:toValue(v)) }).
    self:rowProto:new(slots) }.

; A caller's row, or any dictionary of column names to values, as the
; engine's: [values by column with affinities applied, rowid or nil]. A
; name that is not a column is refused; the INTEGER PRIMARY KEY column and
; 'rowid both name the rowid.
sqlite:table:valuesFrom := { given | | pairs, values, rowidGiven, t |
    t := self.
    pairs := given:isKindOf(sqlite:row):ifElse({ given:asDictionary }, { given }).
    values := [].
    [#1, t:columns:size]:loop({ k | values:add(nil) }).
    rowidGiven := nil.
    pairs:keysAndValuesDo({ k, v | | which |
        which := sqlite:resolve(t, sqlite:nameOf(k)).
        which:equals('rowid):ifElse(
            { v:isNil:ifFalse({ rowidGiven := sqlite:rowidOf(sqlite:toStored(v)) }) },
            { values:atPut(which, sqlite:storeAffinity(sqlite:toStored(v), t:columns:at(which):at(#2))) }) }).
    [values, rowidGiven] }.

; One row in, from a dictionary of column names to values; a column not
; named is NULL, and the rowid is given under 'rowid or the INTEGER PRIMARY
; KEY column or is one past the largest. Answers the row as stored.
sqlite:table:insert := { pairs | | vr, rowid |
    vr := self:valuesFrom(pairs).
    rowid := sqlite:insertRow(self:db, self, vr:at(#1), vr:at(#2)).
    self:rowFrom([rowid, vr:at(#1)]) }.

; The row with that rowid, or nil.
sqlite:table:find := { rowid | | p |
    p := sqlite:findRow(self:db, self:root, rowid).
    p:isNil:ifElse({ nil }, { self:rowFrom([rowid, sqlite:decodeRecord(p)]) }) }.

; A row changed, put back: the one with its 'rowid, with these values. It
; is a delete and an insert under the same rowid, which is what the plan
; said UPDATE was at the page level, and the index entries go with it.
sqlite:table:update := { row | | rowid, p, vr |
    rowid := row:isKindOf(sqlite:row):ifElse({ row:rowid }, { row:at('rowid, nil) }).
    rowid:isNil:ifTrue({ error:raise("update wants a row with a rowid") }).
    p := sqlite:findRow(self:db, self:root, rowid).
    p:isNil:ifTrue({ error:raise("no row ":concat(rowid:asString):concat(" in "):concat(self:name)) }).
    sqlite:deleteRow(self:db, self, rowid, sqlite:decodeRecord(p)).
    vr := self:valuesFrom(row).
    sqlite:insertRow(self:db, self, vr:at(#1), rowid).
    row }.

; A row out, by the row or by its rowid. Answers whether there was one.
sqlite:table:delete := { rowOrId | | rowid, p |
    rowid := rowOrId:isKindOf(integer):ifElse({ rowOrId }, { rowOrId:rowid }).
    p := sqlite:findRow(self:db, self:root, rowid).
    p:isNil:ifElse({ false }, {
        sqlite:deleteRow(self:db, self, rowid, sqlite:decodeRecord(p)). true }) }.

; Queries begin here: every row, or the rows a dictionary of equalities
; keeps, or the rows one comparison keeps.
sqlite:table:all := { sqlite:query:on(self) }.
sqlite:table:where := { pairs | self:all:where(pairs) }.
sqlite:table:filter := { column, op, value | self:all:filter(column, op, value) }.
sqlite:table:orderBy := { columns | self:all:orderBy(columns) }.
sqlite:table:each := { block | self:all:each(block) }.
sqlite:table:count := { self:all:count }.

; ---- a row --------------------------------------------------------------
;
; Every row delegates to its table's prototype, which delegates here. Its
; own slots are its columns and its rowid; these four are the messages. A
; slot assigned is the row's own, as ever, and `save` puts the row back
; under its rowid; to move a row to another rowid, delete it and insert.

sqlite:row := object:new.
sqlite:row:table := nil.
sqlite:row:rowid := nil.
sqlite:row:save := { self:table:update(self). self }.
sqlite:row:delete := { self:table:delete(self:rowid) }.

; The columns and their values, as a dictionary keyed by the column
; symbols, with 'rowid; what `insert` and `where` take.
sqlite:row:asDictionary := { | out |
    out := dictionary:new.
    out:atPut('rowid, self:rowid).
    self:table:columns:do({ c | | s |
        s := c:at(#1):asSymbol.
        out:atPut(s, self:slotAt(s)) }).
    out }.

; ---- a query ------------------------------------------------------------
;
; Narrowed by `where` and `filter`, ordered by `orderBy`, each answering a
; new query so that one can be kept and refined; run by `each`, `all`,
; `first`, `count`, `collect` and `delete`. A comparison is spelled as SQL
; spells it, "=", "<", ">", "<=" or ">=", since that is the file's own
; language and the shell passes it through untouched; the terms are joined
; by AND, and a term on the rowid or on an indexed column is what decides
; the route through the pages, as in the shell.

sqlite:query := object:new.
sqlite:query:table := nil.
sqlite:query:terms := nil.        ; each [column name, op, value as stored]
sqlite:query:order := nil.        ; column names

sqlite:query:on := { t | | q |
    q := self:new. q:table := t. q:terms := []. q:order := []. q }.

sqlite:query:refined := { | q |
    q := sqlite:query:on(self:table).
    q:terms := self:terms:collect({ x | x }).
    q:order := self:order:collect({ x | x }).
    q }.

sqlite:query:where := { pairs | | q |
    q := self:refined.
    pairs:keysAndValuesDo({ k, v | q:terms:add([sqlite:nameOf(k), "=", sqlite:toStored(v)]) }).
    q }.

sqlite:query:filter := { column, op, value | | q |
    (["=", "<", ">", "<=", ">="]:indexOf(op)):isNil:ifTrue({
        error:raise("a comparison is =, <, >, <= or >=, not ":concat(op:asString)) }).
    q := self:refined.
    q:terms:add([sqlite:nameOf(column), op, sqlite:toStored(value)]).
    q }.

; One column or an array of them; ties are broken by rowid, so that an
; ordered query has one answer.
sqlite:query:orderBy := { columns | | q |
    q := self:refined.
    columns:isKindOf(array):ifElse(
        { columns:do({ c | q:order:add(sqlite:nameOf(c)) }) },
        { q:order:add(sqlite:nameOf(columns)) }).
    q }.

; The engine's rows, [rowid, values as stored], in order.
sqlite:query:rows := { | t, rows, orderCols |
    t := self:table.
    rows := sqlite:matchingRows(t:db, t, self:terms).
    self:order:size:greaterThan(#0):ifTrue({
        orderCols := self:order:collect({ c | sqlite:resolve(t, c) }).
        rows := rows:sorted({ a, b | | c, i |
            c := #0. i := #1.
            { c:equals(#0):and({ i:lessOrEqual(orderCols:size) }) }:whileTrue({
                c := sqlite:compare(sqlite:valueAt(a:at(#1), a:at(#2), orderCols:at(i)),
                                    sqlite:valueAt(b:at(#1), b:at(#2), orderCols:at(i))).
                i := i:inc }).
            c:equals(#0):ifTrue({ c := sqlite:compare(a:at(#1), b:at(#1)) }).
            c:lessThan(#0) }) }).
    rows }.

sqlite:query:each := { block | self:rows:do({ r | block:value(self:table:rowFrom(r)) }). self }.
sqlite:query:all := { self:rows:collect({ r | self:table:rowFrom(r) }) }.
sqlite:query:collect := { block | self:all:collect(block) }.
sqlite:query:count := { self:rows:size }.
sqlite:query:first := { | rows |
    rows := self:rows.
    rows:size:equals(#0):ifElse({ nil }, { self:table:rowFrom(rows:at(#1)) }) }.

; The rows this query keeps, taken out: found first and removed after,
; since removing while walking would move the walk's ground. Answers how
; many.
sqlite:query:delete := { | rows, t |
    t := self:table.
    rows := self:rows.
    rows:do({ r | sqlite:deleteRow(t:db, t, r:at(#1), r:at(#2)) }).
    rows:size }.
