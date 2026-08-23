; compiler.sol -- Solum compiled by Solum: a tree in, a chunk out.
;
;     @include "compiler.sol".
;     chunk := compiler:compile(source, "prog.sol").
;     system:writeFile("prog.sob", sob:file(chunk)).
;
; Found on the search path, so no program has to say where this lives. See
; docs/REFERENCE.md#the-library.
;
; The back half of [the self-hosting question](../docs/ideas.md#solas-written-in-solum--self-hosting).
; [lexer.sol](lexer.sol) and [parser.sol](parser.sol) turn source into a tree,
; this turns the tree into a chunk, and [sob.sol](sob.sol) writes the chunk out.
; [compile.sol](../programs/compile.sol) is the program that drives all four.
;
; **The test is `cmp` against `solas`.** Not "runs the same" -- the same file.
; That is a harder bar than it sounds, because it means agreeing on everything a
; compiler is otherwise free to choose: which order names are interned in, which
; constants are shared, where one line's run of instructions ends. Every one of
; those had to be arrived at independently and matched.
;
; **It is a library rather than part of the program because the compiler needs
; testing on its own.** The parser runs out of frames before the compiler does
; ([3.5](../docs/ROADMAP.md#35-recursion-is-limited-to-about-62-levels)), so the
; only way to find out how much room the compiler has is to hand it a tree
; nobody parsed -- which needs it reachable without a driver attached.
;
; ---------------------------------------------------------------------------
; What it compiles
;
; **The whole language**: statements, bindings, sends, parentheses, groups,
; arrays, blocks with their parameters and temporaries, slot assignment,
; `@include`, every literal, and the control flow `solas` compiles to jumps --
; `ifTrue`, `ifFalse`, `ifElse`, `and`, `or`, `whileTrue` and `doUntil`, with
; the same restrictions and the same fall back to a real send.
;
; What stops it is not a construct. It is depth: see 3.5 above.
;
; ---------------------------------------------------------------------------
; Which line a byte belongs to
;
; **The C compiler gives every byte the line of the token it had just consumed**,
; not the line the construct began on. For a one-line statement those are the
; same, which is why the first version of this matched `hello.sol` without
; knowing the difference; for a send whose arguments run over three lines they
; are not. So [parser.sol](parser.sol) records, on each node, the line that was
; current at the point the matching instruction would have been emitted, and
; this reads that rather than the line the node starts on.

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
    u:atPut("codeFiles", []).
    u:atPut("files", []).       u:atPut("fileIndex", dictionary:new).
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

; The file a byte came from, interned per chunk in the order the chunk's code
; first mentions each -- the same rule as names and constants, and for the same
; reason.
compiler:file := { path | | u, found |
    u := self:unit.
    found := u:at("fileIndex"):at(path, nil).
    found:isNil:ifElse(
        { u:atPut("files", u:at("files"):add(path)).
          u:at("fileIndex"):atPut(path, u:at("files"):size:dec).
          u:at("files"):size:dec },
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

; Every byte carries the line it came from **and the file that line is in**. A
; chunk is one compiled unit and `@include` puts a library's code into the same
; one, so a line number on its own named a line in a file nobody had recorded --
; and it read as a line of the file being looked at, which is worse than saying
; nothing.
compiler:emit := { byte, line | | u |
    u := self:unit.
    u:atPut("code", u:at("code"):add(byte:bitAnd(#255))).
    u:atPut("codeLines", u:at("codeLines"):add(line)).
    u:atPut("codeFiles", u:at("codeFiles"):add(self:file(self:current))) }.

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
compiler:JUMP     := #13.
compiler:JUMPIF   := #14.      ; jump if false, carrying the selector to blame
compiler:EXITIF   := #15.      ; leave an inlined loop when the condition is false
compiler:CHECKBOOL := #16.
compiler:LOOP     := #17.
compiler:POP      := #18.
compiler:RETURN   := #19.
compiler:HALT     := #20.

; How many bytes each instruction occupies. A dictionary rather than a chain of
; comparisons because it is looked up rather than walked, and because the one
; place this has to agree with the machine byte for byte is a bad place to be
; clever.
compiler:lengths := dictionary:new.
compiler:lengths:atPut(#4, #2).    ; LOCAL      op + slot
compiler:lengths:atPut(#5, #2).    ; SETLOCAL
compiler:lengths:atPut(#6, #3).    ; OUTER      op + depth + slot
compiler:lengths:atPut(#7, #3).    ; SETOUTER
compiler:lengths:atPut(#11, #4).   ; SEND       op + name + argc
compiler:lengths:atPut(#14, #5).   ; JUMPIF     op + offset + name

compiler:opLength := { op | | fixed |
    fixed := self:lengths:at(op, nil).
    fixed:isNil:ifElse(
        { [#0, #2, #3, #8, #9, #10, #12, #13, #15, #16, #17]:indexOf(op)
              :isNil:ifElse({ #1 }, { #3 }) },
        { fixed }) }.

; ---------------------------------------------------------------------------
; Jumps
;
; A forward jump is emitted with a blank offset and pointed at its destination
; once that is known -- the same two-pass-in-one-pass trick every single-pass
; compiler uses, and the reason the offsets are distances rather than addresses.
;
; The distance is measured **from the end of the whole instruction**, which is
; not always the end of the operand being patched: `JUMPIF` carries the selector
; after its offset so that a non-boolean can be blamed on the message it came
; from, and the jump has to clear that too.

compiler:emitJump := { op, line |
    self:emit(op, line).
    self:emit(#255, line).
    self:emit(#255, line).
    self:unit:at("code"):size:dec }.        ; where the offset sits

compiler:patchJump := { slot | | code, distance |
    code := self:unit:at("code").
    distance := code:size:sub(slot):add(#2):sub(self:opLength(code:at(slot:dec))).
    distance:greaterThan(#65535):ifTrue({
        error:raise("conditional is too large to jump over") }).
    code:at_put(slot, distance:bitAnd(#255)).
    code:at_put(slot:inc, distance:shiftRight(#8):bitAnd(#255)) }.

; The only backward jump, and the offset is subtracted rather than added so that
; it stays unsigned like the others.
compiler:emitLoop := { top, line | | distance |
    self:emit(self:LOOP, line).
    distance := self:unit:at("code"):size:add(#2):sub(top).
    distance:greaterThan(#65535):ifTrue({
        error:raise("loop body is too large to jump back over") }).
    self:emit(distance, line).
    self:emit(distance:shiftRight(#8), line) }.

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

; ---------------------------------------------------------------------------
; Control flow compiled to jumps
;
; `ifTrue`, `ifFalse`, `ifElse`, `and`, `or`, `whileTrue` and `doUntil` are
; ordinary messages, and a program can still send them as messages -- through
; `perform`, or with a block held in a variable. Written literally, which is how
; they are almost always written, `solas` emits jumps around the bodies instead
; of allocating a block and entering a frame per branch or per pass, and this
; has to do the same or the files differ.
;
; **It is an optimisation and must not change what the program means**, which is
; where the restrictions come from. Every block involved must be written right
; there with no parameters and no temporaries:
;
;   - a block with parameters is an arity error when `ifElse` calls it with
;     none, and inlining would quietly make it work;
;   - a block's temporaries belong to its own frame, and inlining would declare
;     them in the enclosing one, where they could collide with a name already
;     there -- turning an optimisation into a compile error.
;
; Anything else falls back to a real send, so the slow path stays correct rather
; than merely unused.

compiler:isPlainBlock := { node |
    node:notNil:and({ node:at("kind"):equals('block) })
        :and({ node:at("parameters"):size:equals(#0) })
        :and({ node:at("temporaries"):size:equals(#0) }) }.

; A branch compiles **straight into the enclosing chunk**. Because it is the
; enclosing scope, a name resolves exactly as it would have from inside the
; block, one lexical level nearer -- so the `OUTER` depths come out right
; without anything having to adjust them.
compiler:branch := { node |
    self:bodyWithPops(node:at("body"), node:at("emit")) }.

compiler:conditionals := ["ifTrue", "ifFalse", "ifElse"].

; Answers whether it handled the send. Nothing is emitted when it did not.
;
; A chain rather than a table of blocks, because each arm asks a different
; question of a different part of the node -- and because the order matters:
; `whileTrue` and `doUntil` have to be recognised before anything else, their
; receiver being spliced in rather than compiled.
compiler:inlineSend := { node | | selector, args, wanted |
    selector := node:at("text").
    args := node:at("arguments").

    self:loopShaped(node, "whileTrue"):ifElse(
        { self:inlineWhile(node). true },
        { self:loopShaped(node, "doUntil"):ifElse(
            { self:inlineDoUntil(node). true },
            { wanted := selector:equals("ifElse"):ifElse({ #2 }, { #1 }).
              self:conditionals:indexOf(selector):notNil
                  :and({ self:allPlain(args, wanted) })
                  :ifElse(
                { self:inlineConditional(node, selector, args). true },
                { ["and", "or"]:indexOf(selector):notNil
                      :and({ self:allPlain(args, #1) })
                      :ifElse(
                    { self:inlineLogical(node, selector, args:at(#1)). true },
                    { false }) }) }) }) }.

; `{ ... }:name({ ... })`, both blocks written right there and both plain.
compiler:loopShaped := { node, selector |
    node:at("text"):equals(selector)
        :and({ self:isPlainBlock(node:at("receiver")) })
        :and({ self:allPlain(node:at("arguments"), #1) }) }.

compiler:allPlain := { args, wanted |
    args:size:equals(wanted)
        :and({ args:inject(true, { ok, a | ok:and({ self:isPlainBlock(a) }) }) }) }.

; ---------------------------------------------------------------------------
; The four shapes
;
; The jump layouts are `solas`'s, and the comments there are worth reading
; beside these. What is repeated here is only what this program has to get
; exactly right.

; The condition is already on the stack; `JUMPIF` pops it and branches, carrying
; the selector so that a non-boolean is reported as not understanding the
; message -- which is what the real send would have said.
compiler:inlineConditional := { node, selector, args | | name, open, toElse, toEnd |
    ; The receiver is the condition and is compiled first, exactly where an
    ; ordinary send would have put it -- the selector is interned after it, and
    ; that order is the name table's order.
    self:expression(node:at("receiver")).
    open := node:at("lparenLine").
    name := self:name(selector).
    toElse := self:emitJump(self:JUMPIF, open).
    self:emitU16(name, open).

    selector:equals("ifFalse"):ifElse(
        ; Inverted: the branch that *is* taken runs the body, so falling through
        ; is the true case and answers nil.
        { self:emit(self:NIL, open).
          toEnd := self:emitJump(self:JUMP, open).
          self:patchJump(toElse).
          self:branch(args:at(#1)).
          self:patchJump(toEnd) },
        { self:branch(args:at(#1)).
          toEnd := self:emitJump(self:JUMP, args:at(#1):at("emit")).
          self:patchJump(toElse).
          selector:equals("ifElse"):ifElse(
            { self:branch(args:at(#2)) },
            { self:emit(self:NIL, args:at(#1):at("emit")) }).
          self:patchJump(toEnd) }) }.

; `and` and `or` short-circuit through a block exactly as `ifTrue` does, and
; differ in what comes out: a boolean either way, and on the long path it is
; whatever the block said -- so `CHECKBOOL` refuses anything else, in the same
; words the primitive would have used.
;
; The short-circuit answer is a **constant** rather than the global `true` or
; `false`, which a program can rebind: reading it would make the shortcut and
; the long path disagree about what `and` answers.
compiler:inlineLogical := { node, selector, body | | name, open, toShortcut, toEnd |
    ; The receiver is the condition and is compiled first, exactly where an
    ; ordinary send would have put it -- the selector is interned after it, and
    ; that order is the name table's order.
    self:expression(node:at("receiver")).
    open := node:at("lparenLine").
    name := self:name(selector).
    toShortcut := self:emitJump(self:JUMPIF, open).
    self:emitU16(name, open).

    selector:equals("and"):ifElse(
        { self:branch(body).
          self:emit(self:CHECKBOOL, body:at("emit")).
          self:emitU16(name, body:at("emit")).
          toEnd := self:emitJump(self:JUMP, body:at("emit")).
          self:patchJump(toShortcut).
          self:emit(self:CONST, body:at("emit")).
          self:emitU16(self:constant(#3, false), body:at("emit")).
          self:patchJump(toEnd) },
        ; Inverted, as `ifFalse` is: a true receiver settles `or`, so the branch
        ; that falls through is the shortcut and the one taken runs the block.
        { self:emit(self:CONST, open).
          self:emitU16(self:constant(#3, true), open).
          toEnd := self:emitJump(self:JUMP, open).
          self:patchJump(toShortcut).
          self:branch(body).
          self:emit(self:CHECKBOOL, body:at("emit")).
          self:emitU16(name, body:at("emit")).
          self:patchJump(toEnd) }) }.

; `{ condition }:whileTrue({ body })`. The condition is the receiver and is
; re-run every pass, which is why it is a block in the source and not a value.
compiler:inlineWhile := { node | | top, condition, body, toEnd |
    condition := node:at("receiver").
    body := node:at("arguments"):at(#1).

    top := self:unit:at("code"):size.
    self:branch(condition).
    toEnd := self:emitJump(self:EXITIF, condition:at("emit")).

    self:branch(body).
    self:emit(self:POP, body:at("emit")).
    self:emitLoop(top, body:at("emit")).

    self:patchJump(toEnd).
    self:emit(self:NIL, body:at("emit")) }.

; `{ body }:doUntil({ condition })` -- the body first, then the test, and the
; sense inverted: this leaves when the condition is *true*.
;
; There is no exit-if-true instruction, and `CHECKBOOL` goes in front instead:
; it already carries a name to complain with, so the check errors as `doUntil`
; if the condition answered something other than a boolean, and by the time
; `EXITIF` sees the value it can only be one.
compiler:inlineDoUntil := { node | | top, body, condition, toAgain, toEnd, name |
    body := node:at("receiver").
    condition := node:at("arguments"):at(#1).

    top := self:unit:at("code"):size.
    self:branch(body).
    self:emit(self:POP, body:at("emit")).

    self:branch(condition).
    name := self:name("doUntil").
    self:emit(self:CHECKBOOL, condition:at("emit")).
    self:emitU16(name, condition:at("emit")).

    toAgain := self:emitJump(self:EXITIF, condition:at("emit")).
    toEnd := self:emitJump(self:JUMP, condition:at("emit")).

    self:patchJump(toAgain).
    self:emitLoop(top, condition:at("emit")).

    self:patchJump(toEnd).
    self:emit(self:NIL, condition:at("emit")) }.

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
        self:inlineSend(node):ifFalse({
            self:expression(node:at("receiver")).
            node:at("arguments"):do({ a | self:expression(a) }).
            self:emit(self:SEND, emitAt).
            self:emitU16(self:name(node:at("text")), emitAt).
            self:emit(node:at("arguments"):size, emitAt) }) }).

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

; ---------------------------------------------------------------------------
; @include
;
; A compile-time directive rather than a message: the named file is compiled
; into this chunk at that point, as though its text had been written there.
; Globals are one flat namespace and stay one, so there is nothing to it beyond
; finding the file and not compiling it twice.
;
; **Beside the includer first, then the search path** -- C's rule for a quoted
; include, and for C's reason: your own files are found without saying where
; they are, and a name you do not have locally comes from the library. An
; absolute name is taken as it stands and searches nothing.

compiler:path := "".
compiler:current := "".        ; the file whose statements are being compiled
compiler:search := [].
compiler:included := dictionary:new.
compiler:depth := #0.

compiler:directoryOf := { path | | at |
    at := #0.
    #1:toDo(path:size, { i | path:at(i):equals("/"):ifTrue({ at := i }) }).
    at:equals(#0):ifElse({ "" }, { path:copyFrom(#1, at) }) }.

compiler:resolveAgainst := { including, name | | directory |
    name:copyFrom(#1, #1):equals("/"):ifElse(
        { name },
        { directory := self:directoryOf(including).
          directory:equals(""):ifElse({ name }, { directory:concat(name) }) }) }.

compiler:resolveInclude := { name | | relative, found |
    relative := self:resolveAgainst(self:current, name).
    name:copyFrom(#1, #1):equals("/"):or({ system:fileExists(relative) }):ifElse(
        { relative },
        { found := nil.
          self:search:do({ directory |
              found:isNil:ifTrue({ | candidate |
                  candidate := directory:concat("/"):concat(name).
                  system:fileExists(candidate):ifTrue({ found := candidate }) }) }).
          ; The relative candidate when nothing is found anywhere, so that the
          ; error names the file the program most likely meant.
          found:isNil:ifElse({ relative }, { found }) }) }.

; **Keyed by the resolved path rather than by where the file really is.** `solas`
; calls `realpath`, so two spellings of one file are one file to it; nothing in
; Solum answers that question, so two spellings would be compiled twice here.
; Every include in this repository is reached by one spelling, and the day one is
; not, this is the line that has to change.
compiler:includeFile := { node | | name, path, source, outer, statements |
    name := self:stringOf(node:at("text")).
    name:size:equals(#0):ifTrue({ error:raise("@include needs a file name") }).

    path := self:resolveInclude(name).
    self:included:includes(path):ifFalse({
        self:depth:greaterOrEqual(#64):ifTrue({
            error:raise("includes nested too deeply") }).
        system:fileExists(path):ifFalse({
            error:raise("cannot read the included file '{}', and it is not on "
                :concat("the search path either"):fill([path])) }).

        ; Remembered **before** compiling, so a cycle ends here rather than
        ; recurring.
        self:included:atPut(path, true).
        source := system:readFile(path).

        ; The parser is finished with the outer file by the time this runs --
        ; the whole of it is already a tree -- so re-entering it costs nothing.
        ; What has to be saved is which file the compiler is emitting *for*.
        outer := self:current.
        self:current := path.
        self:depth := self:depth:inc.
        statements := parser:statements(source).
        self:statements(statements).
        self:depth := self:depth:dec.
        self:current := outer }) }.

compiler:slotNames := [].

; A finished unit, plus everything the format wants that is not code: the file
; table, the run-length encodings, and the slot names. Shared by the script and
; by every block, which differ only in what surrounds them.
; A file's statements. A directive emits nothing at all -- it is not an
; expression, so there is no value for a `POP` to discard.
compiler:statements := { statements |
    statements:do({ statement |
        statement:at("kind"):equals('include):ifElse(
            { self:includeFile(statement) },
            { self:expression(statement).
              ; The POP that ends a statement takes the line of the `.` that
              ; ended it.
              self:emit(self:POP, statement:at("dot")) }) }) }.

compiler:chunkOf := { unit, path | | chunk |
    chunk := dictionary:new.
    chunk:atPut("names", unit:at("names")).
    chunk:atPut("constants", unit:at("constants")).
    chunk:atPut("code", unit:at("code")).
    chunk:atPut("lines", self:runsOf(unit:at("codeLines"))).
    chunk:atPut("files", unit:at("files")).
    chunk:atPut("fileRuns", self:runsOf(unit:at("codeFiles"))).
    chunk:atPut("slotNames", self:slotNames).
    chunk:atPut("methods", unit:at("methods")).
    ; A block's own header carries its slot count; the script's goes here.
    chunk:atPut("slots", self:slotNames:size).
    chunk }.

compiler:compile := { source, path | | chunk, scope, statements, endLine |
    self:path := path.
    self:current := path.
    self:included := dictionary:new.
    ; The file being compiled counts as included, so that a file reached through
    ; its own includes is not compiled a second time.
    self:included:atPut(path, true).
    self:depth := #0.
    self:units := [].
    self:scopes := [].
    self:pushUnit.
    self:pushScope(false).
    self:declareLocal("").

    statements := parser:statements(source).
    ; Read before anything is compiled, because an `@include` re-enters the
    ; parser and this would then be the included file's last line.
    endLine := parser:endLine.
    self:statements(statements).

    ; The machine stops at the line after the last one, which is where the
    ; scanner's end-of-file token sits.
    self:emit(self:HALT, endLine).

    scope := self:popScope.
    self:slotNames := scope:at("locals").
    chunk := self:chunkOf(self:popUnit, path).
    chunk }.
