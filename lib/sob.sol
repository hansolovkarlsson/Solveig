; sob.sol -- writing a `.sob` file, which is what a compiler does last.
;
;     @include "sob.sol".
;     system:writeFile("out.sob", sob:file(chunk)).
;
; Found on the search path, so no program has to say where this lives. See
; docs/REFERENCE.md#the-library.
;
; The layout is [solum/include/solum/serialize.h](../solum/include/solum/serialize.h),
; field for field and in its order, and [disasm.sol](../programs/disasm.sol) is
; the same format read rather than written -- the two are checked against each
; other by the test suite, which compiles a file with `solas` and with the Solum
; compiler and compares the bytes.
;
; This is here rather than in one program because two wanted it: `emit.sol`,
; which builds chunks by hand to prove the format can be written at all, and
; `compile.sol`, which builds them from source. `lib/text.sol` exists for the
; same reason and its header makes the same argument.
;
; A chunk is a **dictionary**, because it is data being written out rather than
; behaviour:
;
;   "slots"      an integer, at least #1 -- the frame slot count
;   "names"      strings; selectors, global names and string literals share it
;   "constants"  [tag, value] pairs; tag #0 nil, #1 integer, #2 float, #3 boolean
;   "code"       the instruction bytes, already assembled
;   "lines"      [runLength, lineNumber], run-length encoded over the code
;   "files"      the source paths this chunk's code came from
;   "fileRuns"   [runLength, fileIndex], the same encoding over the same bytes
;   "slotNames"  what each frame slot was called, in slot order
;   "methods"    nested chunks, each with "name", "arity", "slots", "flags"
;
; It binds one global, `sob`, which is the file extension and so is unlikely to
; be a name a program wants for something else.

sob := object:new.

sob:out := [].

; ---------------------------------------------------------------------------
; The bytes
;
; `asCharacter` turns a number into a one-byte string, which is the whole of the
; language's binary writing, the way `at` and `asByte` are the whole of its
; binary reading. Bytes accumulate in an array and are joined **once**, because
; growing a string by `concat` is quadratic and a chunk is not small.

sob:u8 := { n | self:out := self:out:add(n:bitAnd(#255):asCharacter) }.

; Little-endian throughout, matching `disasm.sol` and design.md.
sob:u16 := { n | self:u8(n). self:u8(n:shiftRight(#8)) }.

sob:u32 := { n | | i |
    i := #0.
    { i:lessThan(#4) }:whileTrue({ self:u8(n:shiftRight(i:mul(#8))). i := i:inc }) }.

; An i64, and **the direction that is easy**. Reading one back is where the
; trouble is: `disasm.sol` cannot rebuild the top byte by shifting it left,
; because a byte of 128 or more shifted into bit 63 is a value no i64 holds and
; this language traps rather than wrapping, so that program reconstructs the
; sign by arithmetic instead. Writing has no such problem. `shiftRight` here is
; arithmetic -- `#-1:shiftRight(#56)` is `#-1`, not a large positive -- so
; masking after it lands on the right byte for negatives as readily as for
; positives, and nothing overflows on the way.
sob:i64 := { n | | i |
    i := #0.
    { i:lessThan(#8) }:whileTrue({ self:u8(n:shiftRight(i:mul(#8))). i := i:inc }) }.

; Text with a u16 length in front and no terminator, which is how every name,
; path and method name is stored.
sob:text := { s | self:u16(s:size). #1:toDo(s:size, { i | self:u8(s:at(i):asByte) }) }.

; ---------------------------------------------------------------------------
; A chunk

sob:chunk := { chunk |
    self:u16(chunk:at("slots")).

    self:u32(chunk:at("names"):size).
    chunk:at("names"):do({ name | self:text(name) }).

    self:u32(chunk:at("constants"):size).
    chunk:at("constants"):do({ pair |
        self:u8(pair:at(#1)).
        ; A float would have to be taken apart into sign, exponent and mantissa
        ; by arithmetic, because nothing reinterprets the bits of a float as an
        ; integer -- `readFloat` in disasm.sol is that done in the reading
        ; direction and is the thing to invert. `sob:f64` below is that
        ; inversion.
        pair:at(#1):equals(#1):ifTrue({ self:i64(pair:at(#2)) }).
        pair:at(#1):equals(#2):ifTrue({ self:f64(pair:at(#2)) }).
        pair:at(#1):equals(#3):ifTrue({
            self:u8(pair:at(#2):ifElse({ #1 }, { #0 })) }) }).

    self:u32(chunk:at("code"):size).
    chunk:at("code"):do({ b | self:u8(b) }).

    self:u32(chunk:at("lines"):size).
    chunk:at("lines"):do({ run | self:u32(run:at(#1)). self:u32(run:at(#2)) }).

    self:u32(chunk:at("files"):size).
    chunk:at("files"):do({ path | self:text(path) }).

    self:u32(chunk:at("fileRuns"):size).
    chunk:at("fileRuns"):do({ run | self:u32(run:at(#1)). self:u32(run:at(#2)) }).

    ; A u16 where the others are u32, which is the format's own asymmetry and
    ; not a slip here: a frame has at most 65,535 slots and the compiler says so.
    self:u16(chunk:at("slotNames"):size).
    chunk:at("slotNames"):do({ name | self:text(name) }).

    ; A method is a header and then a chunk, recursively.
    self:u32(chunk:at("methods"):size).
    chunk:at("methods"):do({ m |
        self:text(m:at("name")).
        self:u16(m:at("arity")).
        self:u16(m:at("slots")).
        self:u16(m:at("flags")).
        self:chunk(m) }) }.

; ---------------------------------------------------------------------------
; A double, taken apart by hand
;
; **Nothing reinterprets the bits of a float as an integer**, so the only way to
; write one is to work out what its bits are. `readFloat` in disasm.sol does the
; same thing in the other direction and its comments carry the reasoning; this
; is that inverted.
;
; The exponent is found by comparison rather than by a logarithm, which the
; language does not have either, and which would be the wrong tool: this has to
; be exact, and `log` would be near.

sob:f64 := { x | | sign, exponent, mantissa, scaled, low, high |
    sign := #0.
    x:lessThan(0.0):or({ x:equals(0.0):and({ 1:div(x):lessThan(0.0) }) })
        :ifTrue({ sign := #1. x := x:negated }).

    x:equals(0.0):ifElse(
        { exponent := #0. mantissa := #0 },
        { x:equals(x):ifElse(
            { x:equals(infinity):ifElse(
                { exponent := #2047. mantissa := #0 },
                { ; Normalise into [1, 2) by halving or doubling, counting as it
                  ; goes. Subnormals are not produced here: nothing this
                  ; compiles has a literal that small, and the entry that
                  ; changes is the one that meets one.
                  exponent := #1023.
                  { x:greaterOrEqual(2.0) }:whileTrue({
                      x := x:div(2.0). exponent := exponent:inc }).
                  { x:lessThan(1.0) }:whileTrue({
                      x := x:mul(2.0). exponent := exponent:dec }).
                  ; The 52 bits after the leading 1, which is not stored.
                  mantissa := x:sub(1.0):mul(4503599627370496.0):rounded }) },
            { exponent := #2047. mantissa := #1 }) }).

    ; Assembled as two halves so that nothing has to reach bit 63, which would
    ; overflow on the way in exactly as it does when reading.
    low := mantissa:bitAnd(#4294967295).
    high := mantissa:shiftRight(#32)
        :bitOr(exponent:shiftLeft(#20))
        :bitOr(sign:shiftLeft(#31)).
    self:u32(low).
    self:u32(high) }.

; ---------------------------------------------------------------------------
; The file, which is the magic and the version and then a chunk

sob:version := #14.

sob:file := { chunk |
    self:out := [].
    self:u8(#83). self:u8(#79). self:u8(#76). self:u8(#66).   ; SOLB
    self:u16(self:version).
    self:chunk(chunk).
    self:out:join("") }.
