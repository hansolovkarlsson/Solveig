; compile.sol -- Solum compiled by Solum, as far as it goes.
;
; Run with:  ./bin/solas programs/compile.sol && ./bin/solvm programs/compile.sob
; A file:    ./bin/solvm programs/compile.sob examples/hello.sol -o hello.sob
;
; The twelfth program, and stage 1 of
; [the self-hosting question](../docs/ideas.md#solas-written-in-solum--self-hosting).
; [emit.sol](emit.sol) proved a `.sob` can be written by hand;
; [lexer.sol](../lib/lexer.sol) and [parser.sol](../lib/parser.sol) turn source
; into a tree; this turns the tree into the bytes.
;
; **The test is `cmp` against `solas`.** Not "runs the same" -- the same file.
; That is a harder bar than it sounds, because it means agreeing on things a
; compiler is free to choose: which order names are interned in, which constants
; are shared, where one line's run of instructions ends. Every one of those is a
; decision this program had to arrive at independently and match.
;
; ---------------------------------------------------------------------------
; What it compiles, and what it does not
;
; **Statements, bindings, sends, parentheses, arrays and every literal.** That
; is the subset [parser.sol](../lib/parser.sol) parses, and it is enough for
; [examples/hello.sol](../examples/hello.sol), which is what stage 1 set out to
; compile.
;
; **Not blocks, temporaries, methods or `@include`.** Those are where slot
; allocation, capture analysis and nested chunks come in -- the half of
; `solas/src/compiler.c` that is genuinely a compiler rather than a translator,
; and stage 2's work. A construct this cannot compile is refused by name rather
; than mis-compiled.

@include "parser.sol".
@include "sob.sol".

compiler := object:new.

; ---------------------------------------------------------------------------
; The tables
;
; **Both are first-encounter order**, which is not a detail: it is most of what
; byte-identity turns on. `solas` interns a name when the instruction referring
; to it is emitted, so the order of the name table is the order the code
; mentions things -- and any other order produces a file that runs identically
; and compares differently. The same for constants, which are shared when they
; are equal *and of the same type*: `#45` and `45` are two entries.

compiler:names := [].
compiler:nameIndex := dictionary:new.

compiler:name := { text | | found |
    found := self:nameIndex:at(text, nil).
    found:isNil:ifElse(
        { self:names := self:names:add(text).
          self:nameIndex:atPut(text, self:names:size:dec).
          self:names:size:dec },
        { found }) }.

compiler:constants := [].
compiler:constantIndex := dictionary:new.

; Keyed by tag and by the value's shortest text, which is unique per double and
; per integer -- so this shares exactly what `solas` shares and nothing else.
compiler:constant := { tag, value | | key, found |
    key := "{}:{}":fill([tag, value:asString]).
    found := self:constantIndex:at(key, nil).
    found:isNil:ifElse(
        { self:constants := self:constants:add([tag, value]).
          self:constantIndex:atPut(key, self:constants:size:dec).
          self:constants:size:dec },
        { found }) }.

; ---------------------------------------------------------------------------
; The code
;
; A byte and the line it came from, side by side, so the run-length encoding at
; the end is a fold over one array rather than bookkeeping during emission.

compiler:code := [].
compiler:codeLines := [].

compiler:emit := { byte, line |
    self:code := self:code:add(byte:bitAnd(#255)).
    self:codeLines := self:codeLines:add(line) }.

compiler:emitU16 := { n, line |
    self:emit(n, line).
    self:emit(n:shiftRight(#8), line) }.

; The opcode numbers are the order of the enum in
; solum/include/solum/bytecode.h. Only the ones this subset emits are named --
; the rest arrive with the constructs that need them.
compiler:CONST   := #0.
compiler:GLOBAL  := #2.
compiler:SETGLOB := #3.
compiler:STRING  := #9.
compiler:SYMBOL  := #10.
compiler:SEND    := #11.
compiler:POP     := #18.
compiler:HALT    := #20.

; ---------------------------------------------------------------------------
; Reading a literal
;
; The scanner keeps a literal's raw source deliberately, so this is where the
; text becomes a value -- and it is one place, which is the reason the scanner
; was left out of it.

; `#45` and `#-5`: the tag is dropped and the digits read.
compiler:integerOf := { text | text:copyFrom(#2, text:size):asInteger }.

; `'foo`: the quote is a prefix, not a delimiter.
compiler:symbolOf := { text | text:copyFrom(#2, text:size) }.

; `"a\nb"`: the quotes come off and the escapes are decoded. Which escapes are
; legal is decided here, in one place, exactly as the C compiler decides it in
; one place -- the scanner only had to know that a backslash claims the next
; character so that `\"` does not end the string.
compiler:escapes := dictionary:new.
compiler:escapes:atPut("n", "\n").
compiler:escapes:atPut("t", "\t").
compiler:escapes:atPut("r", "\r").
compiler:escapes:atPut("\"", "\"").
compiler:escapes:atPut("\\", "\\").

compiler:stringOf := { text | | out, i, c, replacement |
    out := array:new.
    i := #2.                                    ; past the opening quote
    { i:lessThan(text:size) }:whileTrue({       ; stop before the closing one
        c := text:at(i).
        c:equals("\\"):ifElse(
            { i := i:inc.
              replacement := self:escapes:at(text:at(i), nil).
              replacement:isNil:ifTrue({
                  error:raise("unknown escape '\\{}'":fill([text:at(i)])) }).
              out:add(replacement) },
            { out:add(c) }).
        i := i:inc }).
    out:join("") }.

; ---------------------------------------------------------------------------
; An expression, onto the stack
;
; Every one of these leaves exactly one value behind, which is the invariant the
; whole instruction set is built on and the reason a statement is an expression
; followed by a `POP`.

compiler:expression := { node | | kind, line |
    kind := node:at("kind").
    line := node:at("line").

    kind:equals('int):ifTrue({
        self:emit(self:CONST, line).
        self:emitU16(self:constant(#1, self:integerOf(node:at("text"))), line) }).

    kind:equals('float):ifTrue({
        self:emit(self:CONST, line).
        self:emitU16(self:constant(#2, node:at("text"):asFloat), line) }).

    kind:equals('string):ifTrue({
        self:emit(self:STRING, line).
        self:emitU16(self:name(self:stringOf(node:at("text"))), line) }).

    kind:equals('symbol):ifTrue({
        self:emit(self:SYMBOL, line).
        self:emitU16(self:name(self:symbolOf(node:at("text"))), line) }).

    kind:equals('name):ifTrue({
        self:emit(self:GLOBAL, line).
        self:emitU16(self:name(node:at("text")), line) }).

    kind:equals('bind):ifTrue({
        self:expression(node:at("value")).
        self:emit(self:SETGLOB, line).
        self:emitU16(self:name(node:at("text")), line) }).

    kind:equals('send):ifTrue({
        self:expression(node:at("receiver")).
        node:at("arguments"):do({ a | self:expression(a) }).
        self:emit(self:SEND, line).
        self:emitU16(self:name(node:at("text")), line).
        self:emit(node:at("arguments"):size, line) }).

    ; `[a, b]` is `array:of(a, b)` and compiles to exactly that -- notation, not
    ; a second semantics, which is what design.md asks of every shorthand.
    kind:equals('array):ifTrue({
        self:emit(self:GLOBAL, line).
        self:emitU16(self:name("array"), line).
        node:at("elements"):do({ e | self:expression(e) }).
        self:emit(self:SEND, line).
        self:emitU16(self:name("of"), line).
        self:emit(node:at("elements"):size, line) }).

    ['int, 'float, 'string, 'symbol, 'name, 'bind, 'send, 'array]
        :indexOf(kind):isNil:ifTrue({
            error:raise("this compiler does not do {} yet":fill([kind])) }) }.

; ---------------------------------------------------------------------------
; Line runs
;
; Consecutive bytes sharing a line are one run, and the length is in **bytes**
; rather than instructions, which is the format's choice and the one thing about
; this encoding worth reading twice.

compiler:runsOf := { values | | runs, current, length |
    runs := array:new.
    current := nil.
    length := #0.
    values:do({ v |
        v:equals(current):ifElse(
            { length := length:inc },
            { current:isNil:ifFalse({ runs:add([length, current]) }).
              current := v.
              length := #1 }) }).
    current:isNil:ifFalse({ runs:add([length, current]) }).
    runs }.

; ---------------------------------------------------------------------------
; The whole file

compiler:compile := { source, path | | chunk, endLine |
    self:names := [].
    self:nameIndex := dictionary:new.
    self:constants := [].
    self:constantIndex := dictionary:new.
    self:code := [].
    self:codeLines := [].

    parser:statements(source):do({ statement |
        self:expression(statement).
        self:emit(self:POP, statement:at("line")) }).

    ; The machine stops at the line after the last one, which is where the
    ; scanner's end-of-file token sits.
    endLine := parser:endLine.
    self:emit(self:HALT, endLine).

    chunk := dictionary:new.
    chunk:atPut("slots", #1).
    chunk:atPut("names", self:names).
    chunk:atPut("constants", self:constants).
    chunk:atPut("code", self:code).
    chunk:atPut("lines", self:runsOf(self:codeLines)).
    chunk:atPut("files", [path]).
    chunk:atPut("fileRuns", [[self:code:size, #0]]).
    chunk:atPut("slotNames", [""]).
    chunk:atPut("methods", []).
    chunk }.

; ---------------------------------------------------------------------------
; What was asked for
;
; `compile <source.sol> [-o <out.sob>]`, and with nothing at all it compiles the
; example it was written for, which is the convention every program here
; follows.

given := system:arguments.
given:size:equals(#0):ifTrue({
    "":display.
    "no file given, so: examples/hello.sol":display.
    given := ["examples/hello.sol"] }).

source := given:at(#1).
output := nil.
given:indexOf("-o"):isNil:ifElse(
    { output := source:copyFrom(#1, source:size:sub(#4)):concat(".sob") },
    { output := given:at(given:indexOf("-o"):inc) }).

source:size:greaterThan(#4)
    :and({ source:copyFrom(source:size:sub(#3), source:size):equals(".sol") })
    :ifFalse({
        "not a .sol file: {}":fill([source]):display.
        system:exit(#1) }).

system:fileExists(source):ifFalse({
    "no such file: {}":fill([source]):display.
    system:exit(#1) }).

; The path goes into the file's own table, so it is what a stack trace will name
; -- and it has to be spelled the way the compiler being compared against was
; given it, or the bytes differ over nothing else.
text := sob:file(compiler:compile(system:readFile(source), source)).
system:writeFile(output, text).

"":display.
"{}  ->  {}  ({} bytes)":fill([source, output, text:size]):display.
"":display.
