; disasm.sol -- read a .sob file and say what is in it.
;
; Run with:  ./bin/solas programs/disasm.sol && ./bin/solvm programs/disasm.sob
; Over a file of your own:  ./bin/solvm programs/disasm.sob path/to/file.sob
; Just the header and the tables:  ./bin/solvm programs/disasm.sob file.sob brief
;
; The eighth program here, and the first to read a *binary* format -- which is
; also the first to read one this project defines. `solvm --dump` already
; disassembles, so this is a second implementation of a format that had one,
; and that is the point: a second implementation is how you find out whether the
; specification is true. It was written from
; [design.md](../docs/design.md#the-sob-file-format) for the file layout and
; [BYTECODE.md](../docs/BYTECODE.md) for the instructions, going to the C only
; where those ran out.
;
; They ran out in five places. The first three are the documents being wrong
; rather than thin, and a second implementation is the only thing that finds
; them, because the first implementation has the header.
;
;   1. **BYTECODE.md never says what byte an opcode is.** It describes every
;      instruction -- operands, length, stack effect, what it is for -- and the
;      test suite checks that description against `bytecode.h` in both
;      directions. What no part of it carries is the *number*. The mapping from
;      byte to instruction lives only in the order of a C enum, so a reader with
;      the document in front of them cannot decode one byte of a file.
;
;   2. **design.md contradicts itself about byte order**, and both halves are a
;      hundred lines apart. The instruction-set section says a side-table index
;      "is a big-endian u16", which is true. The .sob section says
;      "little-endian throughout", which is true of every table in the file and
;      false of the two-byte operands inside the code. A reader after the file
;      format lands on the second one, believes it, and decodes every operand
;      backwards -- which is what happened here, and it looks like data
;      corruption rather than like a misreading.
;
;   3. **The format table in design.md is missing three sections and a constant
;      tag.** Between the line runs and the methods there are a file table, a
;      run table saying which file each stretch of code came from, and the slot
;      names -- and a constant may be tagged 3, a boolean, beside the 0, 1 and 2
;      the table lists. Those arrived with COMPLETED 6.27 and 6.28, which bumped
;      the format to 12 and then 13; the table was not bumped with them.
;
;      The table also does not separate the file's header from a chunk's body,
;      so "then that method's chunk, recursively" reads as though all eight rows
;      recur. Only the last five do -- the magic, the version and the script's
;      slot count are written once for the file.
;
;   4. **No shift can produce a negative integer**, there being no unsigned
;      type: `b:shiftLeft(#56)` for a byte of 128 or more is a value larger than
;      an i64 holds, and the language traps rather than wrapping. That trap is
;      right -- see [strictness.sol](../examples/strictness.sol).
;
;      What is *not* true, though this file claimed it for a day, is that such
;      an integer cannot be decoded. Arithmetic gets there where shifting
;      cannot: `(b - 256) * 2^56` is the same number by a route where every step
;      fits. See `readInteger`, which reads INT64_MIN correctly now, and
;      ROADMAP 3.12, which is the note rather than the limitation it started as.
;
;   5. **A float has to be decoded by hand**, one bit-field at a time, because
;      nothing reinterprets the bits of an integer as a float. `asFloat` on an
;      integer converts the value, which is a different thing, and `float` has
;      no bit operations at all. So `readFloat` below is IEEE-754 binary64
;      written out in Solum. It works -- `2.5` comes back `2.5` -- and it is
;      thirty lines that would be a `memcpy` in C.
;
; And one thing that is *not* a gap, though the reference reads as though it
; might be: `system:readFile` handles a binary file exactly as it should. The
; Limits table says strings hold no `\0`, which is about what a *literal* may
; contain -- a string read from a file holds every byte the file had, NULs
; included, and this reads 184 of them before the first instruction.
;
; **Checked against `solvm --dump`**, which is the oracle a second
; implementation wants: identical offsets, opcodes, operands and jump targets
; over eight files and 7,673 instructions, `lib/json.sol` and `lib/html.sol`
; among them.

; ---------------------------------------------------------------------------
; The bytes, and a cursor over them
;
; `at` answers a one-character string and `asByte` its number, which is the
; whole of the language's binary reading. Everything below is built from those
; two and the shifts.

raw := nil.
pos := #1.

atEnd := { pos:greaterThan(raw:size) }.

byte := { | b |
    pos:greaterThan(raw:size):ifTrue({
        error:raise("the file ends in the middle of something") }).
    b := raw:at(pos):asByte.
    pos := pos:add(#1).
    b }.

bytes := { n | | out |
    out := raw:copyFrom(pos, pos:add(n):sub(#1)).
    pos := pos:add(n).
    out }.

; Little-endian throughout, which design.md says and which is the only thing
; about the format that has to be remembered rather than looked up.
u16 := { | lo | lo := byte:value. lo:bitOr(byte:value:shiftLeft(#8)) }.

u32 := { | a, b, c |
    a := byte:value. b := byte:value. c := byte:value.
    a:bitOr(b:shiftLeft(#8)):bitOr(c:shiftLeft(#16))
     :bitOr(byte:value:shiftLeft(#24)) }.

; ---------------------------------------------------------------------------
; The constants
;
; Tag 0 is nil, 1 an i64, 2 an f64 -- design.md again.

; An i64 as eight little-endian bytes. All of them, including the negative ones.
;
; The top byte is where this gets interesting. `b:shiftLeft(#56)` overflows for
; any b of 128 or more -- correctly, since as a *value* that is more than an i64
; holds, and the language traps rather than wrapping. There being no unsigned
; type, no shift can ever produce a number with bit 63 set.
;
; Arithmetic can. `(b - 256) * 2^56` is the same number by a route where every
; step fits: b-256 is between -128 and -1, and the product lands between
; INT64_MIN and -2^56. So the byte contributes its *signed* weight directly
; rather than being shifted into a sign bit that would overflow on the way.
;
; **This file said for a day that it could not be done**, and so did
; docs/programs.md and the changelog, on the strength of the shift failing. That
; was one route failing, not the number being unreachable, and writing the
; limitation down as a roadmap entry is what forced the check that disproved it.
readInteger := { | value, b, i |
    value := #0.
    i := #0.
    { i:lessThan(#7) }:whileTrue({
        value := value:bitOr(byte:value:shiftLeft(i:mul(#8))).
        i := i:add(#1) }).
    b := byte:value.
    b:lessThan(#128):ifElse(
        { value:bitOr(b:shiftLeft(#56)) },
        { value:add(b:sub(#256):mul(#72057594037927936)) })   ; 2^56
}.

; IEEE-754 binary64, by hand.
;
;   sign      1 bit    bit 63
;   exponent  11 bits  bits 62..52, biased by 1023
;   mantissa  52 bits  with an implicit leading 1, unless the exponent is 0
;
; The halves are read as two u32s because a whole u64 would meet the same
; overflow the integer above does. Everything after that is arithmetic.
powerOfTwo := { n | | out, i |
    out := 1.0. i := #0.
    n:greaterOrEqual(#0):ifElse(
        { { i:lessThan(n) }:whileTrue({ out := out:mul(2.0). i := i:add(#1) }) },
        { { i:lessThan(n:negated) }:whileTrue({
              out := out:div(2.0). i := i:add(#1) }) }).
    out }.

readFloat := { | lo, hi, sign, exponent, mantissa, value |
    lo := u32:value.
    hi := u32:value.

    sign     := hi:shiftRight(#31):bitAnd(#1).
    exponent := hi:shiftRight(#20):bitAnd(#2047).
    mantissa := hi:bitAnd(#1048575):mul(#4294967296):add(lo).

    exponent:equals(#2047):ifTrue({
        ; Infinity and NaN, which a compiled constant will not be but a
        ; corrupted file might. Named rather than computed.
        error:raise(mantissa:equals(#0):ifElse({ "infinity" }, { "not a number" })) }).

    value := exponent:equals(#0):ifElse(
        { mantissa:asFloat:div(powerOfTwo:value(#52))
                  :mul(powerOfTwo:value(#0:sub(#1022))) },     ; subnormal
        { 1.0:add(mantissa:asFloat:div(powerOfTwo:value(#52)))
             :mul(powerOfTwo:value(exponent:sub(#1023))) }).

    sign:equals(#1):ifElse({ value:negated }, { value }) }.

; ---------------------------------------------------------------------------
; The instruction set
;
; **Read out of `solum/include/solum/bytecode.h`, counting the enum from zero,
; because BYTECODE.md does not carry the numbers.** Each entry is the name and
; how the operands are shaped; the lengths agree with `sol_op_length` and with
; the Bytes column of the document, which is the half the document does give.
;
;   -       no operands
;   name    u16 into the name table
;   const   u16 into the constant table
;   method  u16 into the method table
;   slot    u8
;   depth   u8 depth then u8 slot
;   send    u16 name then u8 argc
;   jump    u16 offset, forward
;   loop    u16 offset, backward
;   branch  u16 offset then u16 name

opcodes := [
    ["const",     "const"],       ; 0
    ["nil",       "-"],
    ["global",    "name"],
    ["setGlobal", "name"],
    ["local",     "slot"],
    ["setLocal",  "slot"],
    ["outer",     "depth"],
    ["setOuter",  "depth"],
    ["block",     "method"],
    ["string",    "name"],
    ["symbol",    "name"],        ; 10
    ["send",      "send"],
    ["setSlot",   "name"],
    ["jump",      "jump"],
    ["jumpIfFalse", "branch"],
    ["exitIfFalse", "jump"],
    ["checkBool", "name"],
    ["loop",      "loop"],
    ["pop",       "-"],
    ["return",    "-"],
    ["halt",      "-"]            ; 20
].

operandBytes := dictionary:new.
operandBytes:atPut("-", #0).
operandBytes:atPut("slot", #1).
operandBytes:atPut("name", #2).
operandBytes:atPut("const", #2).
operandBytes:atPut("method", #2).
operandBytes:atPut("depth", #2).
operandBytes:atPut("jump", #2).
operandBytes:atPut("loop", #2).
operandBytes:atPut("send", #3).
operandBytes:atPut("branch", #4).

; ---------------------------------------------------------------------------
; A chunk
;
; The format nests: a method owns a chunk and is read the same way, so this is
; one block calling itself. Blocks capture, and a block that calls itself is a
; capturing block, so this is bound to a global rather than kept in a local --
; which is the ordinary way to write recursion here and is why evaluator.sol
; does the same.

readBody := { | chunk, count, i, tag, value, length, line, name, m |
    chunk := dictionary:new.

    ; names
    count := u32:value.
    chunk:atPut("names", array:new).
    i := #0.
    { i:lessThan(count) }:whileTrue({
        chunk:at("names"):add(bytes:value(u16:value)).
        i := i:add(#1) }).

    ; constants
    count := u32:value.
    chunk:atPut("constants", array:new).
    i := #0.
    { i:lessThan(count) }:whileTrue({
        tag := byte:value.
        value := tag:equals(#0):ifElse(
            { nil },
            { tag:equals(#1):ifElse(
                { readInteger:value },
                { tag:equals(#2):ifElse(
                    { { readFloat:value }:onError({ e | e:message }) },
                    { tag:equals(#3):ifElse(
                        { byte:value:equals(#0):not },   ; undocumented tag 3
                        { error:raise("constant tag {} is not one of 0, 1, 2, 3"
                              :fill([tag])) }) }) }) }).
        chunk:at("constants"):add([tag, value]).
        i := i:add(#1) }).

    ; code
    chunk:atPut("code", bytes:value(u32:value)).

    ; lines, run-length encoded: a run length then the line it covers
    count := u32:value.
    chunk:atPut("lines", array:new).
    i := #0.
    { i:lessThan(count) }:whileTrue({
        length := u32:value.
        line := u32:value.
        chunk:at("lines"):add([length, line]).
        i := i:add(#1) }).

    ; Which file each stretch of code came from: the paths, then a run per
    ; stretch. **Not in design.md's format table**, though it has been in the
    ; format since version 12 -- see the note at the top of this program.
    count := u32:value.
    chunk:atPut("files", array:new).
    i := #0.
    { i:lessThan(count) }:whileTrue({
        chunk:at("files"):add(bytes:value(u16:value)).
        i := i:add(#1) }).

    count := u32:value.                 ; runs of code per file, u32 length + id
    chunk:atPut("fileRuns", array:new).
    i := #0.
    { i:lessThan(count) }:whileTrue({
        length := u32:value.
        line := u32:value.
        chunk:at("fileRuns"):add([length, line]).
        i := i:add(#1) }).

    ; What each frame slot is called, in slot order, counted by a u16 rather
    ; than the u32 every other table here uses. **Also not in design.md**, and
    ; in the format since version 13.
    count := u16:value.
    chunk:atPut("slotNames", array:new).
    i := #0.
    { i:lessThan(count) }:whileTrue({
        chunk:at("slotNames"):add(bytes:value(u16:value)).
        i := i:add(#1) }).

    ; methods, and the recursion
    count := u32:value.
    chunk:atPut("methods", array:new).
    i := #0.
    { i:lessThan(count) }:whileTrue({
        m := dictionary:new.
        m:atPut("name",  bytes:value(u16:value)).
        m:atPut("arity", u16:value).
        m:atPut("frame", u16:value).        ; the method's own slot count
        m:atPut("flags", u16:value).
        m:atPut("chunk", readBody:value).   ; the *body*, and not a whole file
        chunk:at("methods"):add(m).
        i := i:add(#1) }).

    chunk }.

; ---------------------------------------------------------------------------
; Saying what an instruction is
;
; The line each instruction is on comes out of the run-length table, which is
; walked rather than expanded -- the runs are in order and so is the code.

lineAt := { chunk, offset | | seen, answer |
    seen := #0. answer := #0.
    chunk:at("lines"):do({ run |
        answer:equals(#0):and({ offset:lessThan(seen:add(run:at(#1))) }):ifTrue({
            answer := run:at(#2) }).
        seen := seen:add(run:at(#1)) }).
    answer }.

; A name from the table, quoted, or a complaint that reads as one. An index out
; of range is what a corrupted file looks like and is not a reason to stop.
nameAt := { chunk, index |
    index:lessThan(chunk:at("names"):size):ifElse(
        { "'":concat(chunk:at("names"):at(index:add(#1))):concat("'") },
        { "<name {} of {}?>":fill([index, chunk:at("names"):size]) }) }.

constantAt := { chunk, index | | entry |
    index:greaterOrEqual(chunk:at("constants"):size):ifTrue({
        error:raise("constant {} of {}":fill([index, chunk:at("constants"):size])) }).
    entry := chunk:at("constants"):at(index:add(#1)).
    entry:at(#1):equals(#0):ifElse(
        { "nil" },
        { entry:at(#2):asString }) }.

; ---------------------------------------------------------------------------
; The disassembly

show := { chunk, title, depth | | indent, code, at, op, entry, shape, text, size |
    indent := "". #1:toDo(depth, { n | indent := indent:concat("    ") }).

    "":display.
    "{}{}  -- {} slots, {} names, {} constants, {} bytes"
        :fill([indent, title, chunk:at("slots"), chunk:at("names"):size,
               chunk:at("constants"):size, chunk:at("code"):size]):display.

    code := chunk:at("code").
    at := #1.
    { at:lessOrEqual(code:size) }:whileTrue({
        op := code:at(at):asByte.

        op:greaterOrEqual(opcodes:size):ifElse(
            { "{}  {} {} <unknown opcode>"
                :fill([indent, (at:sub(#1)):asString(">4"), op:asString(">3")]):display.
              at := at:add(#1) },
            { entry := opcodes:at(op:add(#1)).
              shape := entry:at(#2).
              size  := operandBytes:at(shape):add(#1).

              text := shape:equals("-"):ifElse({ "" }, { | a, b |
                  ; **Big-endian**, unlike every table in the file, and see the
                  ; note at the top for how that reads when you get it wrong.
                  ;
                  ; This and the branch offset below are the only two places the
                  ; order is written down on this side. The C now keeps its own
                  ; in one pair of shifts, and **nothing checks these two
                  ; against it** -- so a flip over there would leave this
                  ; reading backwards and the test suite quiet about it. The
                  ; check that would notice is the one this program already
                  ; earns its keep by: disassembling a fresh file and comparing
                  ; against `solvm --dump`.
                  a := shape:equals("slot"):ifElse(
                      { code:at(at:add(#1)):asByte },
                      { code:at(at:add(#1)):asByte:shiftLeft(#8):bitOr(
                            code:at(at:add(#2)):asByte) }).
                  shape:equals("name"):or({ shape:equals("send") })
                      :or({ shape:equals("branch") })
                      :ifTrue({ a := nameAt:value(chunk, a) }).
                  shape:equals("const"):ifTrue({
                      a := { constantAt:value(chunk, a) }
                               :onError({ e | "<":concat(e:message):concat("?>") }) }).
                  shape:equals("method"):ifTrue({ | m |
                      m := a:add(#1).
                      a := m:greaterThan(chunk:at("methods"):size):ifElse(
                          { "<method {}?>":fill([a]) },
                          { "'":concat(chunk:at("methods"):at(m):at("name"))
                               :concat("'") }) }).
                  shape:equals("jump"):ifTrue({
                      a := "+{} -> {}":fill([a, at:sub(#1):add(#3):add(a)]) }).
                  shape:equals("loop"):ifTrue({
                      a := "-{} -> {}":fill([a, at:sub(#1):add(#3):sub(a)]) }).

                  b := shape:equals("depth"):ifElse(
                      { " ":concat(code:at(at:add(#2)):asByte:asString) },
                      { shape:equals("send"):ifElse(
                          { " ":concat(code:at(at:add(#3)):asByte:asString)
                                :concat(" args") },
                          { shape:equals("branch"):ifElse(
                              { "" },
                              { "" }) }) }).
                  ; A branch carries the offset second, the name having been
                  ; read first above; put it back the way it is written.
                  shape:equals("branch"):ifTrue({ | offset |
                      offset := code:at(at:add(#3)):asByte:shiftLeft(#8):bitOr(
                                    code:at(at:add(#4)):asByte).
                      b := " +{} -> {}":fill([offset,
                              at:sub(#1):add(#5):add(offset)]) }).
                  " ":concat(a:asString):concat(b) }).

              "{}  {} {}{}{}":fill([indent,
                  (at:sub(#1)):asString(">4"),
                  "line ":concat(lineAt:value(chunk, at:sub(#1)):asString("<4")),
                  entry:at(#1):asString("<12"),
                  text]):display.
              at := at:add(size) }) }).

    ; and the methods it owns, each a chunk of its own
    chunk:at("methods"):do({ m |
        m:at("chunk"):atPut("slots", m:at("frame")).
        show:value(m:at("chunk"),
            "{} {} ({} args, {} slots{})"
                :fill([m:at("flags"):bitAnd(#1):equals(#1)
                          :ifElse({ "block" }, { "method" }),
                       "'":concat(m:at("name")):concat("'"),
                       m:at("arity"), m:at("frame"),
                       m:at("flags"):bitAnd(#2):equals(#2)
                          :ifElse({ ", captures" }, { "" })]),
            depth:add(#1)) }) }.

; ---------------------------------------------------------------------------
; Which file

path := system:arguments:size:greaterThan(#0):ifElse(
    { system:arguments:at(#1) },
    { | fallback |
      ; Something to read when given nothing, the way page.sol writes itself a
      ; sample. This one has a compiler to hand, so it compiles a sample rather
      ; than carrying one -- which is also a small demonstration of tools.sol's
      ; point, that a scripting language should ask another program.
      fallback := "build/disasm-sample.sob".
      system:writeFile("build/disasm-sample.sol",
          "greet := { who | \"hello, \":concat(who) }.
count := #0.
{ count:lessThan(#3) }:whileTrue({
    greet:value(\"world\"):display.
    count := count:add(#1) }).
total := #1:add(2.5:truncated).
total:print.
").
      system:run(["./bin/solas", "build/disasm-sample.sol", "-o", fallback])
          :equals(#0):ifFalse({
              "could not compile the sample":display. system:exit(#1) }).
      fallback }).

system:fileExists(path):ifFalse({
    "no such file: {}":fill([path]):display.
    system:exit(#1) }).

raw := system:readFile(path).

; ---------------------------------------------------------------------------
; The header
;
; Refuse before reading anything else, which is what the loader does and for the
; same reason: a file of the wrong version is not a file to guess at.

raw:size:lessThan(#8):ifTrue({
    "{} is too short to be a .sob file":fill([path]):display.
    system:exit(#1) }).

magic := bytes:value(#4).
magic:equals("SOLB"):ifFalse({
    "{} does not begin \"SOLB\" -- it begins {}":fill([path, magic:print]):display.
    system:exit(#1) }).

version := u16:value.

"{}  --  {} bytes, format version {}":fill([path, raw:size, version]):display.
version:equals(#13):ifFalse({
    "  this reader was written against version 13; going on anyway":display }).

; The script's slot count, and it is read *here* rather than in `readBody`
; because it is written here -- once for the file, not once per chunk. See the
; note at the top of this program: the format table in design.md does not
; separate the file's header from a chunk's body, so "then that method's chunk,
; recursively" reads as though all eight rows recurse. Only the last five do.
slots := u16:value.

; A truncated or corrupted file is ordinary input for a program that reads
; files, not a reason to stop with a stack trace -- page.sol's lesson, and the
; same one. What has been read so far is still worth printing, so the failure is
; caught, reported, and the tables that did arrive are shown.
truncated := nil.
top := { readBody:value }:onError({ e |
    truncated := e:message.
    nil }).

top:isNil:ifTrue({
    "  {} -- stopped {} bytes in":fill([truncated, pos:sub(#1)]):display.
    system:exit(#65) }).

top:atPut("slots", slots).

atEnd:value:ifFalse({
    "  {} bytes left over after the last method":fill([raw:size:sub(pos):add(#1)])
        :display }).

; ---------------------------------------------------------------------------
; What to print

brief := system:arguments:size:greaterThan(#1):and({
    system:arguments:at(#2):equals("brief") }).

brief:ifElse(
    { | count |
      count := #0.
      top:at("methods"):do({ m | count := count:add(#1) }).
      "":display.
      "  {} names, {} constants, {} bytes of code, {} methods at the top level"
          :fill([top:at("names"):size, top:at("constants"):size,
                 top:at("code"):size, count]):display.
      "":display.
      "  names:      {}":fill([top:at("names"):join(" ")]):display.
      "  constants:  {}":fill([
          top:at("constants"):collect({ c |
              c:at(#1):equals(#0):ifElse({ "nil" }, { c:at(#2):asString })
          }):join(" ")]):display },
    { show:value(top, "script", #0) }).
