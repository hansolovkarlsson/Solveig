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
; **Statements, bindings, sends, parentheses, groups, arrays, blocks with their
; parameters and temporaries, slot assignment, and every literal** -- with the
; frame slots, the lexical capture and the nested chunks all of that needs.
;
; **Not `@include`, and not the inlined control flow.** `ifTrue`, `ifElse`,
; `whileTrue`, `doUntil`, `and` and `or` are compiled to jumps by `solas` when
; they are written literally, and reproducing that exactly is the next piece of
; work. Until then a file using any of them compiles to a real send, which runs
; correctly and compares differently -- so this refuses them rather than
; producing a file that is right and unequal. A construct it cannot compile is
; refused by name.
;
; ---------------------------------------------------------------------------
; Which line a byte belongs to
;
; **The C compiler gives every byte the line of the token it had just consumed**,
; not the line the construct began on. For a one-line statement those are the
; same, which is why the first version of this program matched `hello.sol`
; without knowing the difference; for a send whose arguments run over three
; lines they are not. So [parser.sol](../lib/parser.sol) records, on each node,
; the line that was current at the point the matching instruction would have
; been emitted, and this reads that rather than the line the node starts on.

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

; A chunk under construction. There is a stack of these because a block's code
; goes in a chunk of its own, held in the enclosing chunk's method table -- and
; each has its own name and constant tables, so an index means nothing outside
; the chunk that wrote it.

compiler:units := [].

compiler:unit := { self:units:at(self:units:size) }.

compiler:pushUnit := { | u |
    u := dictionary:new.
    u:atPut("names", []).       u:atPut("nameIndex", dictionary:new).
    u:atPut("constants", []).   u:atPut("constantIndex", dictionary:new).
    u:atPut("code", []).        u:atPut("codeLines", []).
    u:atPut("methods", []).
    self:units := self:units:add(u).
    u }.

compiler:popUnit := { | u |
    u := self:unit.
    self:units := self:units:copyFrom(#1, self:units:size:dec).
    u }.

; **Both tables are first-encounter order**, which is not a detail: it is most
; of what byte-identity turns on. `solas` interns a name when the instruction
; referring to it is emitted, so the order of the name table is the order the
; code mentions things -- and any other order produces a file that runs
; identically and compares differently. The same for constants, which are shared
; when they are equal *and of the same type*: `#45` and `45` are two entries.

compiler:name := { text | | u, found |
    u := self:unit.
    found := u:at("nameIndex"):at(text, nil).
    found:isNil:ifElse(
        { u:atPut("names", u:at("names"):add(text)).
          u:at("nameIndex"):atPut(text, u:at("names"):size:dec).
          u:at("names"):size:dec },
        { found }) }.

; Keyed by tag and by the value's shortest text, which is unique per double and
; per integer -- so this shares exactly what `solas` shares and nothing else.
compiler:constant := { tag, value | | u, key, found |
    u := self:unit.
    key := "{}:{}":fill([tag, value:asString]).
    found := u:at("constantIndex"):at(key, nil).
    found:isNil:ifElse(
        { u:atPut("constants", u:at("constants"):add([tag, value])).
          u:at("constantIndex"):atPut(key, u:at("constants"):size:dec).
          u:at("constants"):size:dec },
        { found }) }.

; ---------------------------------------------------------------------------
; Scopes
;
; A scope is the frame being compiled: its named slots, and whether it is a
; block's frame or the script's. Only parameters and declared temporaries are
; locals -- everything else is a global, which is what lets a block reach out
; and update a name rather than shadowing it.
;
; Slot 0 is reserved and unnameable in every frame. In a block it holds the
; receiver; at the top level it holds nothing, so that a slot index means the
; same thing wherever it is written.

compiler:scopes := [].

compiler:scope := { self:scopes:at(self:scopes:size) }.

compiler:pushScope := { isBlock | | s |
    s := dictionary:new.
    s:atPut("locals", []).
    s:atPut("isBlock", isBlock).
    self:scopes := self:scopes:add(s).
    s }.

compiler:popScope := { | s |
    s := self:scope.
    self:scopes := self:scopes:copyFrom(#1, self:scopes:size:dec).
    s }.

compiler:declareLocal := { name | | s |
    s := self:scope.
    s:at("locals"):indexOf(name):isNil:ifFalse({
        error:raise("that name is already declared here: {}":fill([name])) }).
    s:atPut("locals", s:at("locals"):add(name)).
    s:at("locals"):size:dec }.

; The slot and how many frames out it lives -- `[slot, depth]`, or nil when the
; name is not a local anywhere, which makes it a global. The walk stops at the
; first scope that is not a block, because the top level holds globals.
compiler:resolve := { name | | i, depth, found, s, at |
    i := self:scopes:size.
    depth := #0.
    found := nil.
    { found:isNil:and({ i:greaterOrEqual(#1) }) }:whileTrue({
        s := self:scopes:at(i).
        at := s:at("locals"):indexOf(name).
        at:isNil:ifElse(
            { s:at("isBlock"):ifElse(
                { depth := depth:inc. i := i:dec },
                { i := #0 }) },
            { found := [at:dec, depth] }) }).
    found }.

; ---------------------------------------------------------------------------
; The code
;
; A byte and the line it came from, side by side, so the run-length encoding at
; the end is a fold over one array rather than bookkeeping during emission.

compiler:emit := { byte, line | | u |
    u := self:unit.
    u:atPut("code", u:at("code"):add(byte:bitAnd(#255))).
    u:atPut("codeLines", u:at("codeLines"):add(line)) }.

compiler:emitU16 := { n, line |
    self:emit(n, line).
    self:emit(n:shiftRight(#8), line) }.

; The opcode numbers are the order of the enum in
; solum/include/solum/bytecode.h. Only the ones this subset emits are named --
; the rest arrive with the constructs that need them.
compiler:CONST    := #0.
compiler:NIL      := #1.
compiler:GLOBAL   := #2.
compiler:SETGLOB  := #3.
compiler:LOCAL    := #4.
compiler:SETLOCAL := #5.
compiler:OUTER    := #6.
compiler:SETOUTER := #7.
compiler:BLOCK    := #8.
compiler:STRING   := #9.
compiler:SYMBOL   := #10.
compiler:SEND     := #11.
compiler:SETSLOT  := #12.
compiler:POP      := #18.
compiler:RETURN   := #19.
compiler:HALT     := #20.

; The selectors `solas` compiles to jumps when they are written with literal
; blocks. Until this does the same, a file using one is refused: compiling it as
; a send would be correct and would not compare equal, and an answer that is
; right and unequal is the one thing this program must not produce.
compiler:inlined := ["ifTrue", "ifFalse", "ifElse", "and", "or",
                     "whileTrue", "doUntil"].

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

; Reading or writing a slot: `depth` frames out, `slot` within that frame.
compiler:access := { store, depth, slot, line |
    depth:equals(#0):ifElse(
        { self:emit(store:ifElse({ self:SETLOCAL }, { self:LOCAL }), line).
          self:emit(slot, line) },
        { self:emit(store:ifElse({ self:SETOUTER }, { self:OUTER }), line).
          self:emit(depth, line).
          self:emit(slot, line) }) }.

compiler:expression := { node | | kind, line, emitAt, found |
    kind := node:at("kind").
    line := node:at("line").
    emitAt := node:at("emit", line).

    kind:equals('int):ifTrue({
        self:emit(self:CONST, emitAt).
        self:emitU16(self:constant(#1, self:integerOf(node:at("text"))), emitAt) }).

    kind:equals('float):ifTrue({
        self:emit(self:CONST, emitAt).
        self:emitU16(self:constant(#2, node:at("text"):asFloat), emitAt) }).

    kind:equals('string):ifTrue({
        self:emit(self:STRING, emitAt).
        self:emitU16(self:name(self:stringOf(node:at("text"))), emitAt) }).

    kind:equals('symbol):ifTrue({
        self:emit(self:SYMBOL, emitAt).
        self:emitU16(self:name(self:symbolOf(node:at("text"))), emitAt) }).

    ; `self` is always slot 0 of the frame being compiled, and is not resolved
    ; lexically: which block ends up invoked as a method is not knowable here,
    ; so the VM decides it when the block is made.
    kind:equals('name):ifTrue({
        node:at("text"):equals("self"):ifElse(
            { self:scope:at("isBlock"):ifFalse({
                  error:raise("'self' is only meaningful inside a block") }).
              self:access(false, #0, #0, emitAt) },
            { found := self:resolve(node:at("text")).
              found:isNil:ifElse(
                { self:emit(self:GLOBAL, emitAt).
                  self:emitU16(self:name(node:at("text")), emitAt) },
                { self:access(false, found:at(#2), found:at(#1), emitAt) }) }) }).

    ; A binding never declares. The value is compiled first and the name is
    ; interned after it, which is the order `solas` interns in and therefore the
    ; order the name table ends up in.
    kind:equals('bind):ifTrue({
        self:expression(node:at("value")).
        found := self:resolve(node:at("text")).
        found:isNil:ifElse(
            { self:emit(self:SETGLOB, emitAt).
              self:emitU16(self:name(node:at("text")), emitAt) },
            { self:access(true, found:at(#2), found:at(#1), emitAt) }) }).

    kind:equals('send):ifTrue({
        self:inlined:indexOf(node:at("text")):isNil:ifFalse({
            error:raise("'{}' compiles to jumps and this does not do that yet"
                :fill([node:at("text")])) }).
        self:expression(node:at("receiver")).
        node:at("arguments"):do({ a | self:expression(a) }).
        self:emit(self:SEND, emitAt).
        self:emitU16(self:name(node:at("text")), emitAt).
        self:emit(node:at("arguments"):size, emitAt) }).

    ; `a:b := c`. The selector is interned where the send would have been
    ; emitted -- before the value is compiled -- because that is where `solas`
    ; interns it, having emitted the send and then unemitted it.
    kind:equals('slot):ifTrue({
        self:expression(node:at("receiver")).
        found := self:name(node:at("text")).
        self:expression(node:at("value")).
        self:emit(self:SETSLOT, emitAt).
        self:emitU16(found, emitAt) }).

    ; `[a, b]` is `array:of(a, b)` and compiles to exactly that -- notation, not
    ; a second semantics, which is what design.md asks of every shorthand.
    kind:equals('array):ifTrue({
        self:emit(self:GLOBAL, node:at("openEmit")).
        self:emitU16(self:name("array"), node:at("openEmit")).
        node:at("elements"):do({ e | self:expression(e) }).
        self:emit(self:SEND, emitAt).
        self:emitU16(self:name("of"), emitAt).
        self:emit(node:at("elements"):size, emitAt) }).

    ; A group declares temporaries **of the frame it sits in**, which is the
    ; whole difference between it and a block.
    kind:equals('group):ifTrue({
        node:at("temporaries"):do({ name | self:declareLocal(name) }).
        self:bodyWithPops(node:at("body"), emitAt) }).

    kind:equals('block):ifTrue({ self:blockLiteral(node, emitAt) }).

    ['int, 'float, 'string, 'symbol, 'name, 'bind, 'send, 'slot, 'array,
     'group, 'block]:indexOf(kind):isNil:ifTrue({
            error:raise("this compiler does not do {} yet":fill([kind])) }) }.

; ---------------------------------------------------------------------------
; A block
;
; Its body compiles exactly like a method body, into a chunk of its own held in
; the enclosing chunk's method table. What makes it a block is the `BLOCK`
; instruction, which captures the running frame as the block's home so that
; `self` and the enclosing locals still mean the right thing whenever it is run.

compiler:blockLiteral := { node, closeLine | | unit, scope, method, index |
    self:pushUnit.
    self:pushScope(true).
    self:declareLocal("").
    node:at("parameters"):do({ name | self:declareLocal(name) }).
    node:at("temporaries"):do({ name | self:declareLocal(name) }).

    self:bodyWithPops(node:at("body"), closeLine).
    self:emit(self:RETURN, closeLine).

    scope := self:popScope.
    unit := self:popUnit.

    self:slotNames := scope:at("locals").
    method := self:chunkOf(unit, self:path).
    method:atPut("name", "block").
    method:atPut("arity", node:at("parameters"):size).
    method:atPut("slots", scope:at("locals"):size).
    ; Flag 1 says block; flag 2 says it reaches out of its own frame, which is
    ; what stops it outliving the frame it was written in. A block nested inside
    ; is not consulted -- its depths are counted from its own frame.
    method:atPut("flags", #1:bitOr(
        self:touchesHome(unit:at("code")):ifElse({ #2 }, { #0 }))).

    index := self:unit:at("methods"):size.
    self:unit:atPut("methods", self:unit:at("methods"):add(method)).
    self:emit(self:BLOCK, closeLine).
    self:emitU16(index, closeLine) }.

; Does this code reach out of its own frame? One that does not is independent of
; where it was written and may outlive it.
compiler:touchesHome := { code | | at, found, op |
    at := #1.
    found := false.
    { found:not:and({ at:lessOrEqual(code:size) }) }:whileTrue({
        op := code:at(at).
        op:equals(self:OUTER):or({ op:equals(self:SETOUTER) })
            :ifElse({ found := true }, { at := at:add(self:opLength(op)) }) }).
    found }.

; How many bytes an instruction occupies, which is the one thing about the
; instruction set this program has to know beyond the opcode numbers.
compiler:opLength := { op |
    [self:LOCAL, self:SETLOCAL, self:OUTER, self:SETOUTER]:indexOf(op):isNil
        :ifElse(
        { [self:CONST, self:GLOBAL, self:SETGLOB, self:BLOCK, self:STRING,
           self:SYMBOL, self:SETSLOT]:indexOf(op):isNil:ifElse(
            { op:equals(self:SEND):ifElse({ #4 }, { #1 }) },
            { #3 }) },
        { [self:OUTER, self:SETOUTER]:indexOf(op):isNil:ifElse({ #2 }, { #3 }) }) }.

; Statements with a POP between them, which is what a block body and a group
; body both are.
compiler:bodyWithPops := { statements, closeLine | | n |
    statements:size:equals(#0):ifElse(
        { self:emit(self:NIL, closeLine) },
        { n := #0.
          statements:do({ s |
              n := n:inc.
              n:greaterThan(#1):ifTrue({
                  self:emit(self:POP, statements:at(n:dec):at("dot")) }).
              self:expression(s) }) }) }.

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

compiler:path := "".
compiler:slotNames := [].

; A finished unit, plus everything the format wants that is not code: the file
; table, the run-length encodings, and the slot names. Shared by the script and
; by every block, which differ only in what surrounds them.
compiler:chunkOf := { unit, path | | chunk |
    chunk := dictionary:new.
    chunk:atPut("names", unit:at("names")).
    chunk:atPut("constants", unit:at("constants")).
    chunk:atPut("code", unit:at("code")).
    chunk:atPut("lines", self:runsOf(unit:at("codeLines"))).
    chunk:atPut("files", [path]).
    chunk:atPut("fileRuns", [[unit:at("code"):size, #0]]).
    chunk:atPut("slotNames", self:slotNames).
    chunk:atPut("methods", unit:at("methods")).
    ; A block's own header carries its slot count; the script's goes here.
    chunk:atPut("slots", self:slotNames:size).
    chunk }.

compiler:compile := { source, path | | chunk, scope, statements |
    self:path := path.
    self:units := [].
    self:scopes := [].
    self:pushUnit.
    self:pushScope(false).
    self:declareLocal("").

    statements := parser:statements(source).
    statements:do({ statement |
        self:expression(statement).
        ; The POP that ends a statement takes the line of the `.` that ended it.
        self:emit(self:POP, statement:at("dot")) }).

    ; The machine stops at the line after the last one, which is where the
    ; scanner's end-of-file token sits.
    self:emit(self:HALT, parser:endLine).

    scope := self:popScope.
    self:slotNames := scope:at("locals").
    chunk := self:chunkOf(self:popUnit, path).
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
