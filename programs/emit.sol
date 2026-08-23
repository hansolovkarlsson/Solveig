; emit.sol -- a .sob written by Solum, which is disasm.sol backwards.
;
; Run with:  ./bin/solas programs/emit.sol && ./bin/solvm programs/emit.sob
; Somewhere else:  ./bin/solvm programs/emit.sob build/emit
;
; The eleventh program, and the first stage of asking whether **Solas could be
; written in Solum** -- see
; [ideas.md](../docs/ideas.md#solas-written-in-solum--self-hosting). Not a
; compiler. There is no lexer here and no parser: two chunks are written out by
; hand, byte by byte, and handed to the machine.
;
; **That is the whole point of doing this first.** A compiler is a front end and
; a back end, and the front end is ordinary work in any language -- scanning
; characters and building a tree is what `lib/json.sol` and `lib/html.sol`
; already do. The back end is the half that could turn out to be impossible,
; because it has to produce an exact binary file, and a language that cannot
; write a NUL byte or an i64 cannot do it at all. So the back end goes first,
; on the smallest input there is, and either it works or the question is
; answered cheaply.
;
; What it produces is compared against what `solas` produces from the same two
; programs, byte for byte. Not "runs the same" -- the same file.
;
;   "hi":display.     94 bytes    names, code, line runs, files, slot names
;   #45:print.        98 bytes    all of that and the constant table
;
; Between them they exercise every section of the format that a chunk with no
; methods has.

; ---------------------------------------------------------------------------
; The bytes
;
; `asCharacter` turns a number into a one-byte string, which is the whole of the
; language's binary writing, the way `at` and `asByte` are the whole of its
; binary reading. Bytes accumulate in an array and are joined **once**, because
; growing a string by `concat` is quadratic and a chunk is not small.
;
; `system:writeFile` then writes every byte it is given, NUL included. That was
; the one thing about this program that could not be assumed, and it is the
; reason the first thing written here was a file of all 256 byte values read
; back and compared.

out := [].

u8 := { n | out := out:add(n:bitAnd(#255):asCharacter) }.

; Little-endian throughout, matching `disasm.sol` and design.md.
u16 := { n | u8:value(n). u8:value(n:shiftRight(#8)) }.

u32 := { n | | i |
    i := #0.
    { i:lessThan(#4) }:whileTrue({ u8:value(n:shiftRight(i:mul(#8))). i := i:inc }) }.

; An i64, and **the direction that is easy**. Reading one back is where the
; trouble is: `disasm.sol` cannot rebuild the top byte by shifting it left,
; because a byte of 128 or more shifted into bit 63 is a value no i64 holds and
; this language traps rather than wrapping, so that program reconstructs the
; sign by arithmetic instead. Writing has no such problem. `shiftRight` here is
; arithmetic -- `#-1:shiftRight(#56)` is `#-1`, not a large positive -- so
; masking after it lands on the right byte for negatives as readily as for
; positives, and nothing overflows on the way.
i64 := { n | | i |
    i := #0.
    { i:lessThan(#8) }:whileTrue({ u8:value(n:shiftRight(i:mul(#8))). i := i:inc }) }.

; Text with a u16 length in front and no terminator, which is how every name,
; path and method name is stored.
text := { s | u16:value(s:size). #1:toDo(s:size, { i | u8:value(s:at(i):asByte) }) }.

; ---------------------------------------------------------------------------
; A chunk
;
; The layout is solum/include/solum/serialize.h, field for field and in its
; order. A chunk is a dictionary here rather than an object because it is data
; being written out rather than behaviour, and because the next stage will build
; these from a parse rather than by hand.
;
; The one field that is not a list of things is `"slots"`, the frame slot count,
; which sits in the header beside the version.
;
;   "slots"      an integer, at least #1
;   "names"      strings -- selectors and string literals share this table
;   "constants"  [tag, value] pairs; tag #0 nil, #1 integer, #2 float, #3 boolean
;   "code"       the instruction bytes, already assembled
;   "lines"      [runLength, lineNumber], run-length encoded over the code
;   "files"      the source paths this chunk's code came from
;   "fileRuns"   [runLength, fileIndex], the same encoding over the same bytes
;   "slotNames"  what each frame slot was called, in slot order
;   "methods"    nested chunks -- empty here, and the next thing to grow

writeChunk := { chunk |
    u16:value(chunk:at("slots")).

    u32:value(chunk:at("names"):size).
    chunk:at("names"):do({ name | text:value(name) }).

    u32:value(chunk:at("constants"):size).
    chunk:at("constants"):do({ pair |
        u8:value(pair:at(#1)).
        ; Only the integer tag is written here. A float would have to be taken
        ; apart into sign, exponent and mantissa by arithmetic, because nothing
        ; reinterprets the bits of a float as an integer -- `readFloat` in
        ; disasm.sol is that done in the reading direction and is the thing to
        ; invert when a program with a float literal needs compiling.
        pair:at(#1):equals(#1):ifTrue({ i64:value(pair:at(#2)) }) }).

    u32:value(chunk:at("code"):size).
    chunk:at("code"):do({ b | u8:value(b) }).

    u32:value(chunk:at("lines"):size).
    chunk:at("lines"):do({ run | u32:value(run:at(#1)). u32:value(run:at(#2)) }).

    u32:value(chunk:at("files"):size).
    chunk:at("files"):do({ path | text:value(path) }).

    u32:value(chunk:at("fileRuns"):size).
    chunk:at("fileRuns"):do({ run | u32:value(run:at(#1)). u32:value(run:at(#2)) }).

    ; A u16 where the others are u32, which is the format's own asymmetry and
    ; not a slip here: a frame has at most 65,535 slots and the compiler says so.
    u16:value(chunk:at("slotNames"):size).
    chunk:at("slotNames"):do({ name | text:value(name) }).

    u32:value(chunk:at("methods"):size) }.

; The file, which is the magic and the version and then a chunk.
writeFile := { path, chunk |
    out := [].
    u8:value(#83). u8:value(#79). u8:value(#76). u8:value(#66).   ; SOLB
    u16:value(#14).
    writeChunk:value(chunk).
    system:writeFile(path, out:join("")).
    out:size }.

; ---------------------------------------------------------------------------
; The instructions
;
; The opcode numbers are the order of the enum in
; solum/include/solum/bytecode.h, which is the one thing about the format a
; reader cannot look up -- BYTECODE.md describes every instruction and gives no
; byte for any of them, which is ROADMAP 6.x territory and was found by
; disasm.sol. Only the four this program needs are named.

CONST  := #0.
STRING := #9.
SEND   := #11.
POP    := #18.
HALT   := #20.

; A u16 operand inside the code, little-endian since version 14 -- before that
; the tables were little-endian and these were big, which is the whole reason
; there was a version 14.
operand := { n | [n:bitAnd(#255), n:shiftRight(#8):bitAnd(#255)] }.

; ---------------------------------------------------------------------------
; The two programs, by hand
;
; Each is what `solas` produces for one line of Solum. The line numbers are the
; interesting part of the shape: the statement is line 1 and the HALT the
; compiler adds is line 2, which is one past the end of a one-line file.

; "hi":display.
hello := dictionary:new.
hello:atPut("slots", #1).
hello:atPut("names", ["hi", "display"]).
hello:atPut("constants", []).
hello:atPut("code",
    [STRING]:add(operand:value(#0):at(#1)):add(operand:value(#0):at(#2))
        :add(SEND):add(operand:value(#1):at(#1)):add(operand:value(#1):at(#2)):add(#0)
        :add(POP)
        :add(HALT)).
hello:atPut("lines", [[#8, #1], [#1, #2]]).
hello:atPut("files", ["hi.sol"]).
hello:atPut("fileRuns", [[#9, #0]]).
hello:atPut("slotNames", [""]).
hello:atPut("methods", []).

; #45:print.
number := dictionary:new.
number:atPut("slots", #1).
number:atPut("names", ["print"]).
number:atPut("constants", [[#1, #45]]).
number:atPut("code",
    [CONST]:add(operand:value(#0):at(#1)):add(operand:value(#0):at(#2))
        :add(SEND):add(operand:value(#0):at(#1)):add(operand:value(#0):at(#2)):add(#0)
        :add(POP)
        :add(HALT)).
number:atPut("lines", [[#8, #1], [#1, #2]]).
number:atPut("files", ["num.sol"]).
number:atPut("fileRuns", [[#9, #0]]).
number:atPut("slotNames", [""]).
number:atPut("methods", []).

; ---------------------------------------------------------------------------
; Writing them

; **The directory is made if it is not there**, because a program that fails on
; a clean checkout because a build directory is missing is a program nobody can
; run twice.
where := system:arguments:size:equals(#0):ifElse(
    { "build/emit" },
    { system:arguments:at(#1) }).

system:isDirectory(where):ifFalse({ system:makeDirectory(where) }).

"":display.
"writing into {}":fill([where]):display.

[[hello, "hi.sob", "hi.sol"], [number, "num.sob", "num.sol"]]:do({ job |
    | path, size |
    path := where:concat("/"):concat(job:at(#2)).
    size := writeFile:value(path, job:at(#1)).
    "  {}  {} bytes":fill([job:at(#2), size:asString("4")]):display }).

"":display.
"check them against the compiler:":display.
"  printf '\"hi\":display.\\n' > hi.sol && ./bin/solas hi.sol":display.
"  cmp hi.sob {}/hi.sob":fill([where]):display.
"  ./bin/solvm {}/hi.sob":fill([where]):display.
"":display.
