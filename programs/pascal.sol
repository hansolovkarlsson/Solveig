; pascal.sol -- ISO 7185 Pascal compiled to bytecode. Stage 1.
;
; Run with:  ./bin/solas programs/pascal.sol && ./bin/solvm programs/pascal.sob
; On a file:  ./bin/solvm programs/pascal.sob prog.pas [prog.sob]
;
; The fifteenth program here, and the second that compiles another language.
; Where [sola.sol](sola.sol) had to define its dialect first -- there being no
; standard for a QBasic -- this one has [ISO 7185](../docs/PASCAL.md) and a
; **real compiler to disagree with**: `fpc -Miso`, which
; [programs/pas/oracle.sh](pas/oracle.sh) runs beside this one.
;
; ---------------------------------------------------------------------------
; What stage 1 is
;
;   program       the heading, with or without its file list
;   var           integer, real, char and boolean
;   :=            with the assignment compatibility the standard gives
;   expressions   + - * / div mod, unary -, the six comparisons, and/or/not
;   write         write and writeln, with `:width` and `:width:places`
;   begin end     compound statements
;   if            with and without else
;   while         do
;
; Everything else is a stage, and [PASCAL.md](../docs/PASCAL.md) says which.
;
; ---------------------------------------------------------------------------
; Why a type checker is not optional here
;
; **Solum refuses `#1:add(1.0)`.** There is no implicit conversion anywhere in
; the machine, so a compiler for a language that *has* one cannot avoid knowing
; the type of every expression it emits. Pascal's rule is that an integer
; becomes a real where a real is wanted and never the other way, and `/` is
; always real -- so `i / 2` needs an `asFloat` on `i` and `i div 2` needs none,
; and the compiler has to have decided which before it writes a byte.
;
; That is the difference between this and `sola.sol`, whose header says
; *everything a SolaBasic program computes is a Double*. One numeric type needs
; no analysis. Two need all of it.
;
; ---------------------------------------------------------------------------
; Three things the oracle settled before this file was started
;
; **`mod` is free and `div` is not**, which is the reverse of SolaBasic. ISO
; says `i mod j` is non-negative for positive `j` -- that is a *floored*
; remainder, and SolVM's is floored, so `mod` is one instruction. ISO's `div`
; truncates toward nought where SolVM's floors, so `-3 div 2` is `-1` in Pascal
; and `-2` on the machine, and it is compiled through `abs` and a sign.
;
; **And a divergence that was not one.** `fpc` answers `-1` for `-3 mod 2`, which
; looked like it disagreeing with ISO's non-negative remainder -- and does not.
; Pascal's sign belongs to the whole *term*, so `-3 mod 2` is `-(3 mod 2)` and
; `-1` is right. Asked with a variable holding `-3` it answers `1`, as the
; standard says and as this compiler does. The claim was written down here
; before it was checked and is left as a note, because a compiler for a language
; whose grammar it has read is exactly the place to misread precedence.
;
; **Its `integer` is 32 bits.** `maxint` is 2147483647 there and 2^63-1 here,
; which [PASCAL.md](../docs/PASCAL.md) already listed as a divergence and the
; oracle confirmed on the first run.
;
; ---------------------------------------------------------------------------
; What a write costs, and why the widths are compile-time strings
;
; `fpc` writes an integer in a field of **11**, a boolean in **5**, a char in
; **1**, and a string in its own length. None of that is the standard's doing --
; ISO leaves the default width to the implementation -- but agreement has to be
; checkable, so these are its numbers.
;
; Solum's `asString(spec)` does the padding, and a spec is known while
; compiling: `writeln(i:6)` emits the constant `">6"`. So a write is a `GLOBAL
; system`, the value, one `asString`, and a `SEND write` -- no runtime formatter
; and no prelude, which is the other thing `sola.sol` needed and this does not.

@include "sob.sol".

; ---------------------------------------------------------------------------
; The instruction set, by the order of the enum in solum/include/solum/bytecode.h

CONST    := #0.
NIL      := #1.
GLOBAL   := #2.
SETGLOB  := #3.
LOCAL    := #4.
SETLOCAL := #5.
STRING   := #9.
SEND     := #11.
JUMP     := #13.
JMPF     := #14.
LOOP     := #17.
POP      := #18.
HALT     := #20.

; ---------------------------------------------------------------------------
; Characters

digits := "0123456789".
lower  := "abcdefghijklmnopqrstuvwxyz".

isDigit := { c | c:notNil:and({ digits:indexOf(c):notNil }) }.
isAlpha := { c | c:notNil:and({ | l | l := c:asLowercase.
    lower:indexOf(l):notNil:or({ l:equals("_") }) }) }.
isAlnum := { c | isAlpha:value(c):or({ isDigit:value(c) }) }.
isSpace := { c | c:notNil:and({ c:equals(" "):or({ c:equals("\t") })
    :or({ c:equals("\n") }):or({ c:equals("\r") }) }) }.

; ---------------------------------------------------------------------------
; The compiler

pas := object:new.

pas:src   := "".
pas:path  := "".
pas:pos   := #1.
pas:line  := #1.

; The token: kind is 'name 'int 'real 'text 'punct 'eof, and `text` is the
; spelling -- folded to lower case for a name, since Pascal does not
; distinguish, and left alone inside a string.
pas:kind  := 'eof.
pas:text  := "".
pas:tline := #1.

pas:code      := array:new.
pas:names     := array:new.
pas:nameIndex := dictionary:new.
pas:constants := array:new.
pas:constIndex := dictionary:new.
pas:lineRuns  := array:new.
pas:atLine    := #1.
pas:runLine   := #1.
pas:runLength := #0.

pas:slotNames := array:new.       ; slot 0 is reserved and unnameable
pas:vars      := dictionary:new.  ; name -> [slot, type]

; ---------------------------------------------------------------------------
; Refusing

pas:fail := { message |
    error:raise("{}:{}: {}":fill([self:path, self:tline, message])) }.

; ---------------------------------------------------------------------------
; The scanner
;
; Pascal's two comment forms nest neither in themselves nor in each other, and
; the standard lets `{` be closed by `*)`. That is not a kindness anybody wants
; and it is what the standard says, so it is what happens here.

pas:atEnd := { self:pos:greaterThan(self:src:size) }.
pas:peek  := { self:atEnd:ifElse({ nil }, { self:src:at(self:pos) }) }.
pas:peekAt := { n | | i | i := self:pos:add(n).
    i:greaterThan(self:src:size):ifElse({ nil }, { self:src:at(i) }) }.

pas:step := {
    self:peek:equals("\n"):ifTrue({ self:line := self:line:add(#1) }).
    self:pos := self:pos:add(#1) }.

pas:skipSpace := { | going |
    going := true.
    { going }:whileTrue({
        isSpace:value(self:peek):ifElse({ self:step }, {
            self:peek:equals("{"):or({ self:peek:equals("(")
                :and({ self:peekAt(#1):equals("*") }) }):ifElse({
                self:skipComment }, { going := false }) }) }) }.

pas:skipComment := { | going |
    self:peek:equals("{"):ifElse({ self:step }, { self:step. self:step }).
    going := true.
    { going }:whileTrue({
        self:atEnd:ifTrue({ self:fail("a comment is not closed") }).
        self:peek:equals("}"):ifElse({ self:step. going := false }, {
            self:peek:equals("*"):and({ self:peekAt(#1):equals(")") }):ifElse(
                { self:step. self:step. going := false },
                { self:step }) }) }) }.

; A quoted literal. Two quotes in a row are one quote, which is the only escape
; the language has.
pas:readText := { | out, going |
    self:step.
    out := "". going := true.
    { going }:whileTrue({
        self:atEnd:ifTrue({ self:fail("a string is not closed") }).
        self:peek:equals("'"):ifElse({
            self:peekAt(#1):equals("'"):ifElse(
                { out := out:concat("'"). self:step. self:step },
                { self:step. going := false }) },
          { out := out:concat(self:peek). self:step }) }).
    out }.

pas:readNumber := { | start, isReal |
    start := self:pos.
    isReal := false.
    { isDigit:value(self:peek) }:whileTrue({ self:step }).

    ; A point only continues the number when a digit follows, so `1..5` is a
    ; subrange and not a malformed real. The standard requires the digit.
    self:peek:equals("."):and({ isDigit:value(self:peekAt(#1)) }):ifTrue({
        isReal := true. self:step.
        { isDigit:value(self:peek) }:whileTrue({ self:step }) }).

    self:peek:notNil:and({ self:peek:asLowercase:equals("e") }):ifTrue({ | save |
        save := self:pos.
        self:step.
        self:peek:equals("+"):or({ self:peek:equals("-") }):ifTrue({ self:step }).
        isDigit:value(self:peek):ifElse({
            isReal := true.
            { isDigit:value(self:peek) }:whileTrue({ self:step }) },
          { self:pos := save }) }).

    self:kind := isReal:ifElse({ 'real }, { 'int }).
    self:text := self:src:copyFrom(start, self:pos:sub(#1)).
    nil }.

; The two-character operators come first, or `:=` is a `:` and `<=` is a `<`.
pas:twoChar := [":=", "<=", ">=", "<>", ".."].

pas:next := { | c, start |
    self:skipSpace.
    self:tline := self:line.
    self:atEnd:ifElse({ self:kind := 'eof. self:text := "" }, {
        c := self:peek.
        isAlpha:value(c):ifElse({
            start := self:pos.
            { isAlnum:value(self:peek) }:whileTrue({ self:step }).
            self:kind := 'name.
            self:text := self:src:copyFrom(start, self:pos:sub(#1)):asLowercase },
        { isDigit:value(c):ifElse({ self:readNumber }, {
          c:equals("'"):ifElse({
              self:kind := 'text. self:text := self:readText },
            { | two, found |
              two := self:peekAt(#1):isNil:ifElse({ "" },
                  { c:concat(self:peekAt(#1)) }).
              found := self:twoChar:indexOf(two):notNil.
              found:ifElse(
                  { self:step. self:step. self:kind := 'punct. self:text := two },
                  { self:step. self:kind := 'punct. self:text := c }) }) }) }) }).
    nil }.

; ---------------------------------------------------------------------------
; Asking about the token

pas:isName := { word | self:kind:equals('name):and({ self:text:equals(word) }) }.
pas:isPunct := { p | self:kind:equals('punct):and({ self:text:equals(p) }) }.

pas:accept := { word |
    self:isName(word):ifElse({ self:next. true }, { false }) }.
pas:acceptPunct := { p |
    self:isPunct(p):ifElse({ self:next. true }, { false }) }.

pas:expect := { word |
    self:accept(word):ifFalse({
        self:fail("expected '{}' and found '{}'":fill([word, self:text])) }).
    nil }.
pas:expectPunct := { p |
    self:acceptPunct(p):ifFalse({
        self:fail("expected '{}' and found '{}'":fill([p, self:text])) }).
    nil }.

pas:expectName := { | t |
    self:kind:equals('name):ifFalse({
        self:fail("expected a name and found '{}'":fill([self:text])) }).
    t := self:text. self:next. t }.

; ---------------------------------------------------------------------------
; Emitting
;
; Bytes into an array, operands little-endian, and the whole chunk handed to
; `sob.sol` at the end -- the arrangement `sola.sol` established and the reason
; that file is in `lib/` rather than inside it.

pas:here := { self:code:size }.
pas:byte := { b | self:code:add(b:bitAnd(#255)) }.
pas:u16  := { n | self:byte(n). self:byte(n:shiftRight(#8)) }.

pas:nameFor := { text |
    self:nameIndex:includes(text):ifElse(
        { self:nameIndex:at(text) },
        { | i | i := self:names:size.
                self:names:add(text).
                self:nameIndex:atPut(text, i).
                i }) }.

; Shared by value **and tag**, because `#0` and `0.0` are two constants and
; pushing the wrong one is a program that runs and is wrong.
pas:constFor := { tag, value | | key |
    key := tag:asString:concat(":"):concat(value:asString).
    self:constIndex:includes(key):ifElse(
        { self:constIndex:at(key) },
        { | i | i := self:constants:size.
                self:constants:add([tag, value]).
                self:constIndex:atPut(key, i).
                i }) }.

pas:emitInt    := { n | self:byte(CONST). self:u16(self:constFor(#1, n)) }.
pas:emitReal   := { v | self:byte(CONST). self:u16(self:constFor(#2, v)) }.
pas:emitBool   := { b | self:byte(CONST). self:u16(self:constFor(#3, b)) }.
pas:emitString := { s | self:byte(STRING). self:u16(self:nameFor(s)) }.
pas:emitGlobal := { s | self:byte(GLOBAL). self:u16(self:nameFor(s)) }.
pas:emitLocal    := { slot | self:byte(LOCAL).    self:byte(slot) }.
pas:emitSetLocal := { slot | self:byte(SETLOCAL). self:byte(slot) }.
pas:emitPop      := { self:byte(POP) }.
pas:emitSend := { sel, argc |
    self:byte(SEND). self:u16(self:nameFor(sel)). self:byte(argc) }.

; A forward jump, patched once its landing place is known. `JUMP_IF_FALSE`
; carries the selector it was inlined from as well as its offset -- so that a
; non-boolean complains the way the send it stands for would have.
pas:emitJump := { | at | self:byte(JUMP). at := self:here. self:u16(#0). at }.
pas:emitJumpFalse := { why | | at |
    self:byte(JMPF). at := self:here. self:u16(#0). self:u16(self:nameFor(why)). at }.

; **The offset is measured from the end of the whole instruction**, and that is
; not always the end of the operand being patched: `JUMP_IF_FALSE` carries the
; selector it was inlined from after its offset, so it is five bytes where
; `JUMP` is three. Getting this wrong produces a file the verifier refuses as
; *internally inconsistent*, which is what it did.
pas:patch := { at | | offset, length |
    length := self:code:at(at):equals(JMPF):ifElse({ #5 }, { #3 }).
    offset := self:here:sub(at):add(#1):sub(length).
    offset:greaterThan(#65535):ifTrue({ self:fail("this jump is too long") }).
    self:code:atPut(at:add(#1), offset:bitAnd(#255)).
    self:code:atPut(at:add(#2), offset:shiftRight(#8):bitAnd(#255)).
    nil }.

pas:emitLoop := { top | | offset |
    self:byte(LOOP).
    offset := self:here:add(#2):sub(top).
    offset:greaterThan(#65535):ifTrue({ self:fail("this loop is too long") }).
    self:u16(offset).
    nil }.

; Run-length encoded, one run per line the code came from.
pas:mark := { n |
    n:equals(self:runLine):ifFalse({
        self:runLength:greaterThan(#0):ifTrue({
            self:lineRuns:add([self:runLength, self:runLine]) }).
        self:runLine := n. self:runLength := #0 }).
    nil }.

; ---------------------------------------------------------------------------
; Scratch slots
;
; `div` wants both its operands twice and the machine has no way to duplicate
; the top of the stack, so they go into slots. Handed out by nesting depth, so
; that `(a div b) div c` does not have its inner pair overwritten by its outer
; one -- which is `sola.sol`'s arrangement and its reasoning.

pas:scratchDepth := #0.
pas:scratchMax   := #0.

; Slots are counted from nought, so the highest one a frame of `n` has is
; `n - 1` -- and handing out `slotBase + scratchMax` rather than one less than
; it is a file the verifier refuses, because a `LOCAL` addressed a slot the
; frame does not have. It says *internally inconsistent* and not which slot,
; which is the whole of the debugging story here.
pas:scratchSlot := { n |
    self:scratchDepth:add(n):greaterThan(self:scratchMax):ifTrue({
        self:scratchMax := self:scratchDepth:add(n) }).
    self:slotBase:add(self:scratchDepth):add(n):sub(#1) }.

pas:slotBase := #1.

; ---------------------------------------------------------------------------
; Types
;
; Five, and only four of them are Pascal's: `'text` is what a quoted literal of
; more than one character is, which the standard calls a string and this stage
; can only write out. A one-character literal is a `char`, which is the
; standard's rule and the reason the two are told apart at all.

pas:isNumeric := { t | t:equals('integer):or({ t:equals('real) }) }.

; An integer where a real is wanted, and never the other way -- Pascal's one
; implicit conversion, and the reason this compiler has a type checker at all.
pas:toReal := { t |
    t:equals('integer):ifTrue({ self:emitSend("asFloat", #0) }).
    'real }.

pas:typeName := { t |
    t:equals('text):ifElse({ "string" }, { t:asString }) }.

pas:wantSame := { a, b, what |
    a:equals(b):ifFalse({
        self:fail("'{}' will not take a {} and a {}"
            :fill([what, self:typeName(a), self:typeName(b)])) }).
    nil }.

; ---------------------------------------------------------------------------
; Expressions
;
; Recursive descent over the standard's grammar, and every one of these answers
; the **type** of what it left on the stack. That answer is the whole of the
; type checking: there is no tree to walk afterwards.

pas:relOps := dictionary:new.
pas:relOps:atPut("=", "equals").
pas:relOps:atPut("<>", "notEquals").
pas:relOps:atPut("<", "lessThan").
pas:relOps:atPut("<=", "lessOrEqual").
pas:relOps:atPut(">", "greaterThan").
pas:relOps:atPut(">=", "greaterOrEqual").

pas:factor := { | t, name, v, over |
    self:kind:equals('int):ifElse({
        self:emitInt(self:text:asInteger). self:next. 'integer },
    { self:kind:equals('real):ifElse({
        self:emitReal(self:text:asFloat). self:next. 'real },
    { self:kind:equals('text):ifElse({
        v := self:text. self:next.
        self:emitString(v).
        v:size:equals(#1):ifElse({ 'char }, { 'text }) },
    { self:acceptPunct("("):ifElse({
        t := self:expression.
        self:expectPunct(")").
        t },
    { self:accept("not"):ifElse({
        t := self:factor.
        t:equals('boolean):ifFalse({
            self:fail("'not' wants a boolean and found a {}"
                :fill([self:typeName(t)])) }).
        self:emitSend("not", #0).
        'boolean },
    { self:kind:equals('name):ifElse({
        name := self:text.

        ; The three the standard has as constants rather than as syntax.
        name:equals("true"):or({ name:equals("false") }):ifElse({
            self:next. self:emitBool(name:equals("true")). 'boolean },
        { name:equals("maxint"):ifElse({
            self:next. self:emitInt(#9223372036854775807). 'integer },
          { self:next.
            self:vars:includes(name):ifFalse({
                self:fail("'{}' is not declared":fill([name])) }).
            over := self:vars:at(name).
            self:emitLocal(over:at(#1)).
            over:at(#2) }) }) },
      { self:fail("expected a value and found '{}'":fill([self:text])) }) }) }) }) }) }) }.

; `div` truncates toward nought where the machine floors, so it is compiled
; through `abs` and a sign rather than emitted as one send. See the header.
pas:emitTruncatingDiv := { | sa, sb, over |
    sa := self:scratchSlot(#1).
    sb := self:scratchSlot(#2).

    self:emitSetLocal(sb). self:emitPop.       ; the divisor is on top
    self:emitSetLocal(sa). self:emitPop.

    self:emitLocal(sa). self:emitSend("abs", #0).
    self:emitLocal(sb). self:emitSend("abs", #0).
    self:emitSend("div", #1).

    self:emitLocal(sa). self:emitInt(#0). self:emitSend("lessThan", #1).
    self:emitLocal(sb). self:emitInt(#0). self:emitSend("lessThan", #1).
    self:emitSend("notEquals", #1).
    over := self:emitJumpFalse("div").
    self:emitSend("negated", #0).
    self:patch(over).
    nil }.

pas:term := { | left, op, right, over, past |
    self:scratchDepth := self:scratchDepth:add(#2).
    left := self:factor.
    { self:isPunct("*"):or({ self:isPunct("/") })
        :or({ self:isName("div") }):or({ self:isName("mod") })
        :or({ self:isName("and") }) }:whileTrue({
        op := self:text. self:next.

        op:equals("and"):ifElse({
            left:equals('boolean):ifFalse({
                self:fail("'and' wants booleans") }).
            over := self:emitJumpFalse("and").
            right := self:factor.
            right:equals('boolean):ifFalse({ self:fail("'and' wants booleans") }).
            past := self:emitJump.
            self:patch(over).
            self:emitBool(false).
            self:patch(past).
            left := 'boolean },

        { right := self:factor.
          op:equals("/"):ifElse({
              self:isNumeric(left):and({ self:isNumeric(right) }):ifFalse({
                  self:fail("'/' wants numbers") }).
              ; The divisor is on top, so it is converted first and the
              ; dividend needs the machine's help to be reached at all.
              self:toReal(right).
              left:equals('integer):ifTrue({ self:widenUnder }).
              self:emitSend("div", #1).
              left := 'real },

          { op:equals("div"):or({ op:equals("mod") }):ifElse({
              left:equals('integer):and({ right:equals('integer) }):ifFalse({
                  self:fail("'{}' wants integers":fill([op])) }).
              op:equals("div"):ifElse(
                  { self:emitTruncatingDiv },
                  { self:emitSend("mod", #1) }).
              left := 'integer },

            { self:isNumeric(left):and({ self:isNumeric(right) }):ifFalse({
                  self:fail("'*' wants numbers") }).
              left:equals('real):or({ right:equals('real) }):ifElse({
                  self:toReal(right).
                  left:equals('integer):ifTrue({ self:widenUnder }).
                  self:emitSend("mul", #1).
                  left := 'real },
                { self:emitSend("mul", #1). left := 'integer }) }) }) }) }).
    self:scratchDepth := self:scratchDepth:sub(#2).
    left }.

; The value **under** the top of the stack has to become a real, and there is
; no instruction that reaches past the top. Both go into scratch slots and come
; back in the other order, which is three instructions and no cleverness.
pas:widenUnder := { | sb |
    sb := self:scratchSlot(#2).
    self:emitSetLocal(sb). self:emitPop.
    self:emitSend("asFloat", #0).
    self:emitLocal(sb).
    nil }.

pas:simpleExpression := { | left, op, right, negate, past, skip |
    negate := false.
    self:isPunct("+"):ifTrue({ self:next }).
    self:isPunct("-"):ifTrue({ self:next. negate := true }).

    left := self:term.
    negate:ifTrue({
        self:isNumeric(left):ifFalse({ self:fail("'-' wants a number") }).
        self:emitSend("negated", #0) }).

    { self:isPunct("+"):or({ self:isPunct("-") }):or({ self:isName("or") }) }
        :whileTrue({
        op := self:text. self:next.

        ; `a or b` is a jump and not a send, because the machine's `or` takes a
        ; block. It short-circuits, which the standard permits and does not
        ; require -- evaluation order for these is the implementation's.
        op:equals("or"):ifElse({
            left:equals('boolean):ifFalse({ self:fail("'or' wants booleans") }).
            past := self:emitJumpFalse("or").
            self:emitBool(true).
            skip := self:emitJump.
            self:patch(past).
            right := self:term.
            right:equals('boolean):ifFalse({ self:fail("'or' wants booleans") }).
            self:patch(skip).
            left := 'boolean },

        { right := self:term.
          self:isNumeric(left):and({ self:isNumeric(right) }):ifFalse({
              self:fail("'{}' wants numbers":fill([op])) }).
          left:equals('real):or({ right:equals('real) }):ifElse({
              self:toReal(right).
              left:equals('integer):ifTrue({ self:widenUnder }).
              left := 'real },
            { left := 'integer }).
          self:emitSend(op:equals("+"):ifElse({ "add" }, { "sub" }), #1) }) }).
    left }.

pas:expression := { | left, op, right |
    left := self:simpleExpression.
    self:kind:equals('punct):and({ self:relOps:includes(self:text) }):ifTrue({
        op := self:text. self:next.
        right := self:simpleExpression.

        self:isNumeric(left):and({ self:isNumeric(right) }):ifElse({
            left:equals('real):or({ right:equals('real) }):ifTrue({
                self:toReal(right).
                left:equals('integer):ifTrue({ self:widenUnder }) }) },
          { self:wantSame(left, right, op).
            left:equals('boolean):and({ op:equals("="):or({ op:equals("<>") })
                :not }):ifTrue({
                self:fail("booleans compare with '=' and '<>' in this stage") }) }).

        self:emitSend(self:relOps:at(op), #1).
        left := 'boolean }).
    left }.

; ---------------------------------------------------------------------------
; Writing
;
; Every field width is a compile-time string, which is what makes a write four
; instructions and no runtime formatter. A width computed while running is
; legal Pascal and is stage 8; it is refused by name rather than accepted and
; got wrong.

pas:widthOf := { | sign, v |
    sign := #1.
    self:isPunct("-"):ifTrue({ self:next. sign := #-1 }).
    self:kind:equals('int):ifFalse({
        self:fail("a field width has to be a literal in this stage") }).
    v := self:text:asInteger:mul(sign).
    self:next.
    v }.

; fpc's defaults, adopted so that agreement is checkable: the standard leaves
; every one of these to the implementation.
pas:defaultWidth := dictionary:new.
pas:defaultWidth:atPut("integer", #11).
pas:defaultWidth:atPut("boolean", #5).

pas:writeItem := { | t, width, places |
    t := self:expression.
    width := nil. places := nil.
    self:acceptPunct(":"):ifTrue({
        width := self:widthOf.
        self:acceptPunct(":"):ifTrue({ places := self:widthOf }) }).

    places:notNil:ifTrue({
        t:equals('real):ifFalse({
            self:fail("only a real takes a second field width") }) }).

    t:equals('boolean):ifTrue({ self:emitSend("asString", #0) }).

    t:equals('real):ifElse({
        places:notNil:ifElse({
            self:emitString(">{}.{}":fill([width, places])).
            self:emitSend("asString", #1) },
          { width:isNil:ifElse(
                { self:emitSend("asString", #0) },
                { self:emitSend("asString", #0).
                  self:emitString(">{}":fill([width])).
                  self:emitSend("asString", #1) }) }) },

      { width:isNil:ifElse({
            t:equals('integer):or({ t:equals('boolean) }):ifTrue({
                self:emitString(">{}":fill([
                    self:defaultWidth:at(self:typeName(t))])).
                self:emitSend("asString", #1) }) },
          { t:equals('integer):ifTrue({ self:emitSend("asString", #0) }).
            self:emitString(">{}":fill([width])).
            self:emitSend("asString", #1) }) }).
    nil }.

pas:writeCall := { newline | | more |
    self:acceptPunct("("):ifElse({
        more := true.
        { more }:whileTrue({
            self:emitGlobal("system").
            self:writeItem.
            self:emitSend("write", #1).
            self:emitPop.
            more := self:acceptPunct(",") }).
        self:expectPunct(")") },
      { newline:ifFalse({ self:fail("'write' wants something to write") }) }).

    newline:ifTrue({
        self:emitGlobal("system").
        self:emitString("\n").
        self:emitSend("write", #1).
        self:emitPop }).
    nil }.

; ---------------------------------------------------------------------------
; Statements

pas:statement := { | name, over, past, top, target |
    self:lineMark(self:tline).

    self:isName("begin"):ifElse({ self:compound },

    { self:accept("if"):ifElse({
        self:conditionFor("if").
        self:expect("then").
        over := self:emitJumpFalse("ifTrue").
        self:statement.
        self:accept("else"):ifElse({
            past := self:emitJump.
            self:patch(over).
            self:statement.
            self:patch(past) },
          { self:patch(over) }) },

    { self:accept("while"):ifElse({
        top := self:here.
        self:conditionFor("while").
        self:expect("do").
        over := self:emitJumpFalse("whileTrue").
        self:statement.
        self:emitLoop(top).
        self:patch(over) },

    { self:accept("writeln"):ifElse({ self:writeCall(true) },
    { self:accept("write"):ifElse({ self:writeCall(false) },

    { self:kind:equals('name):ifElse({
        name := self:expectName.
        self:vars:includes(name):ifFalse({
            self:fail("'{}' is not declared":fill([name])) }).
        target := self:vars:at(name).
        self:expectPunct(":=").
        self:assignInto(target, name) },

      ; The empty statement, which the standard has and which is what a `;`
      ; before an `end` produces.
      { nil }) }) }) }) }) }).
    nil }.

pas:conditionFor := { what | | t |
    t := self:expression.
    t:equals('boolean):ifFalse({
        self:fail("'{}' wants a boolean and found a {}"
            :fill([what, self:typeName(t)])) }).
    nil }.

; Pascal's assignment compatibility: an integer may go into a real and nothing
; else converts.
pas:assignInto := { target, name | | want, got |
    want := target:at(#2).
    got := self:expression.
    want:equals('real):and({ got:equals('integer) }):ifTrue({
        self:toReal(got). got := 'real }).
    got:equals(want):ifFalse({
        self:fail("'{}' is a {} and this is a {}"
            :fill([name, self:typeName(want), self:typeName(got)])) }).
    self:emitSetLocal(target:at(#1)).
    self:emitPop.
    nil }.

pas:compound := {
    self:expect("begin").
    self:statement.
    { self:acceptPunct(";") }:whileTrue({ self:statement }).
    self:expect("end").
    nil }.

; ---------------------------------------------------------------------------
; Declarations

pas:typeNamed := { | t |
    t := self:expectName.
    t:equals("integer"):ifElse({ 'integer },
    { t:equals("real"):ifElse({ 'real },
    { t:equals("char"):ifElse({ 'char },
    { t:equals("boolean"):ifElse({ 'boolean },
      { self:fail("'{}' is not a type this stage has":fill([t])) }) }) }) }) }.

pas:declareVar := { name, type | | slot |
    self:vars:includes(name):ifTrue({
        self:fail("'{}' is declared twice":fill([name])) }).
    slot := self:slotNames:size.
    slot:greaterThan(#254):ifTrue({ self:fail("too many variables in one program") }).
    self:slotNames:add(name).
    self:vars:atPut(name, [slot, type]).

    ; **Every variable starts at nought**, which the standard does not promise
    ; and this machine cannot avoid: a slot that was never written holds nil,
    ; and nil understands nothing. So the zero is emitted rather than assumed.
    type:equals('integer):ifTrue({ self:emitInt(#0) }).
    type:equals('real):ifTrue({ self:emitReal(0.0) }).
    type:equals('char):ifTrue({ self:emitString(" ") }).
    type:equals('boolean):ifTrue({ self:emitBool(false) }).
    self:emitSetLocal(slot).
    self:emitPop.
    nil }.

pas:varSection := { | names, type |
    { self:kind:equals('name):and({ self:isName("begin"):not }) }:whileTrue({
        names := array:new.
        names:add(self:expectName).
        { self:acceptPunct(",") }:whileTrue({ names:add(self:expectName) }).
        self:expectPunct(":").
        type := self:typeNamed.
        self:expectPunct(";").
        names:do({ n | self:declareVar(n, type) }) }).
    nil }.

; ---------------------------------------------------------------------------
; A program

pas:lineAt := #0.

pas:lineMark := { n | | grown |
    grown := self:here:sub(self:lineAt).
    grown:greaterThan(#0):ifTrue({
        self:lineRuns:add([grown, self:runLine]).
        self:lineAt := self:here }).
    self:runLine := n.
    nil }.

pas:program := {
    self:expect("program").
    self:expectName.
    self:acceptPunct("("):ifTrue({
        self:expectName.
        { self:acceptPunct(",") }:whileTrue({ self:expectName }).
        self:expectPunct(")") }).
    self:expectPunct(";").

    self:accept("var"):ifTrue({ self:varSection }).

    ; Scratch slots live above the variables, so their numbers are known only
    ; once the declarations are read -- which is why Pascal declaring first is
    ; a convenience to the compiler and not only to the reader.
    self:slotBase := self:slotNames:size.

    self:compound.
    self:expectPunct(".").
    nil }.

pas:compile := { source, path | | chunk, i |
    self:src := source. self:path := path.
    self:pos := #1. self:line := #1.
    self:code := array:new.
    self:names := array:new. self:nameIndex := dictionary:new.
    self:constants := array:new. self:constIndex := dictionary:new.
    self:lineRuns := array:new. self:runLine := #1. self:lineAt := #0.
    self:slotNames := array:new. self:slotNames:add("").
    self:vars := dictionary:new.
    self:scratchDepth := #0. self:scratchMax := #0.

    self:next.
    self:program.
    self:lineMark(self:runLine).
    self:byte(HALT).
    self:lineAt:lessThan(self:here):ifTrue({
        self:lineRuns:add([self:here:sub(self:lineAt), self:runLine]) }).

    i := #0.
    { i:lessThan(self:scratchMax) }:whileTrue({
        self:slotNames:add("scratch"). i := i:add(#1) }).

    chunk := dictionary:new.
    chunk:atPut("slots", self:slotNames:size).
    chunk:atPut("names", self:names).
    chunk:atPut("constants", self:constants).
    chunk:atPut("code", self:code).
    chunk:atPut("lines", self:lineRuns).
    chunk:atPut("files", [path]).
    chunk:atPut("fileRuns", [[self:code:size, #0]]).
    chunk:atPut("slotNames", self:slotNames).
    chunk:atPut("methods", array:new).
    chunk }.

; ---------------------------------------------------------------------------
; Running it

compileFile := { inPath, outPath | | source, chunk |
    source := system:readFile(inPath).
    chunk := pas:compile(source, inPath).
    system:writeFile(outPath, sob:file(chunk)).
    "{} -> {}, {} bytes":fill([inPath, outPath,
        system:fileSize(outPath)]):display.
    "":display.
    "run it:  ./bin/solvm {}":fill([outPath]):display.
    "see it:  ./bin/solvm --dump {}":fill([outPath]):display.
    nil }.

; The demonstration, which every program in this directory has: a Pascal
; program carried here, compiled, and run, so that the compiler says something
; when it is given nothing.
demonstration := "program Demo(output);
var
  i, total : integer;
  average  : real;
  grew     : boolean;
  mark     : char;
begin
  total := 0;
  i := 1;
  while i <= 10 do
    begin
      total := total + i * i;
      i := i + 1
    end;
  writeln('sum of the first ten squares:', total:6);

  average := total / 10;
  writeln('the average:', average:9:2);

  grew := (total > 100) and not (total = 0);
  writeln('bigger than a hundred:', grew:7);

  mark := 'P';
  writeln('a letter:', mark:3);

  writeln(-7 div 2:6, -7 mod 2:6, 7 div 2:6);

  if total > 300 then
    writeln('over three hundred')
  else
    writeln('not over three hundred')
end.
".

args := system:arguments.

args:size:equals(#0):ifTrue({ | chunk, out |
    "pascal.sol -- ISO 7185 Pascal to bytecode. Stage 1.":display.
    "":display.
    demonstration:display.
    out := "build/pascal-demo.sob".
    system:isDirectory("build"):ifFalse({ system:makeDirectory("build") }).
    chunk := pas:compile(demonstration, "demo.pas").
    system:writeFile(out, sob:file(chunk)).
    "-- compiled to {}, {} bytes. Running it:":fill([out,
        system:fileSize(out)]):display.
    "":display.
    system:run(["./bin/solvm", out]).
    nil }).

args:size:greaterOrEqual(#1):ifTrue({ | inPath, outPath |
    inPath := args:at(#1).
    outPath := args:size:greaterOrEqual(#2):ifElse({ args:at(#2) },
        { inPath:concat(".sob") }).
    { compileFile:value(inPath, outPath) }:onError({ e |
        e:message:display.
        system:exit(#1) }).
    nil }).
