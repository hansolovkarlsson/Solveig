; sola.sol -- SolaBasic compiled to bytecode. Stage 3: labels and GOTO.
;
; Run with:  ./bin/solas programs/sola.sol && ./bin/solvm programs/sola.sob
; On a file:  ./bin/solvm programs/sola.sob prog.bas [prog.sob]
;
; The thirteenth program here, and the second that is about another language --
; but where [basic.sol](basic.sol) *interprets* one, this **compiles** one, and
; the file it writes is run by `solvm` with nothing of this program present.
;
; The language is [SolaBasic](../docs/SOLABASIC.md). This is stage 3 of the
; eight that document lists, and it is deliberately out of order: stage 3 is
; `GOTO` and labels, which is the claim the whole design rests on, and the
; document says to reach it in week one rather than week six.
;
; ---------------------------------------------------------------------------
; Why a compiler at all, when there is already an interpreter
;
; **Because `GOTO` cannot be written in Solum.** Solum has no control-flow
; syntax -- a loop is a message send -- so a translator from BASIC to Solum
; source would have to compile every statement into a block, put the blocks in
; an array, and dispatch on a label variable. That is a full send per BASIC
; statement, which is roughly what `basic.sol` already pays as a tree-walker: it
; would be a slower interpreter wearing a compiler's name.
;
; Emitting bytecode, `GOTO` is `OP_JUMP` and `OP_LOOP`. This is the rare case
; where dropping a level buys a **construct** rather than a constant factor.
;
; **And the verifier cooperates**, which is the part that had to be checked
; rather than assumed. SolVM verifies that the paths into any instruction agree
; on stack height. Every SolaBasic statement here compiles at depth 0 and ends
; with a `POP`, so every label is a depth-0 merge point *by construction* and an
; arbitrary jump between statements needs no analysis at all.
;
; That was measured before this program was written, by hand-assembling a chunk
; with a backward jump to an arbitrary earlier offset, a forward jump over dead
; code, and a conditional between them. It verified and ran. Both ways of
; getting it wrong were checked too, and both are refused **at load**, exit 65,
; as a message rather than a crash:
;
;   a jump into the middle of an instruction   bytecode is internally inconsistent
;   a jump to a different stack depth          bytecode is internally inconsistent
;
; The second is the one that matters, because it is what a compiler that got
; clever would produce -- and it means the depth-0 discipline is load-bearing
; rather than tidy.
;
; ---------------------------------------------------------------------------
; What is here, and what is stage 4 onwards
;
; This stage accepts a deliberately small language, and the smallness is the
; point: enough statements to have somewhere to jump *between*, and nothing
; else.
;
;   labels        `Name:` at the start of a line, and a bare number, which is a
;                 label and not a line number -- CB80's rule, so it need not be
;                 ordered and nothing here ever sorts one
;   GOTO          forwards and backwards, to any label in the program
;   IF ... THEN GOTO   the conditional jump
;   assignment    `LET` optional, scalars only
;   PRINT         expressions and strings, `;` and `,`
;   END           stops
;   expressions   `+ - * /`, unary minus, parentheses, and the six comparisons
;   comments      `REM` and `'`
;
; **Not here, and not pretended:** `SUB`, `FUNCTION`, arrays, `FOR`, `DO`,
; `WHILE`, `SELECT CASE`, `INPUT`, files, and the whole type system -- every
; number is a Double, which is SolaBasic's default type and the only one this
; stage has. `PRINT`'s real formatting is stage 6; here the items of one `PRINT`
; are joined and shown, with no zones and no trailing space, so its output is
; **not** what a BASIC prints. That is a stage, not a divergence, and it is the
; one thing here most likely to be mistaken for a bug.

@include "scan.sol".
@include "control.sol".
@include "sob.sol".

; ---------------------------------------------------------------------------
; The instruction set -- the ten this stage needs
;
; The opcode numbers are the order of the enum in
; solum/include/solum/bytecode.h. BYTECODE.md describes every instruction and
; now gives the byte for each, which it did not when disasm.sol first wanted one.

CONST   := #0.
GLOBAL  := #2.
SETGLOB := #3.
STRING  := #9.
SEND    := #11.
JUMP    := #13.
JMPF    := #14.
LOOP    := #17.
POP     := #18.
HALT    := #20.

; A jump's operand is a u16, so no jump reaches further than this. SolaBasic
; says so in as many words, and this is where it is enforced.
jumpLimit := #65535.

digits  := "0123456789".
letters := "ABCDEFGHIJKLMNOPQRSTUVWXYZ".

isDigit  := { c | c:notNil:and({ digits:indexOf(c):notNil }) }.
isLetter := { c | c:notNil:and({ letters:indexOf(c:asUppercase):notNil }) }.
isSpace  := { c | c:notNil:and({ c:equals(" "):or({ c:equals("\t") }) }) }.

; The operators, and the message each one becomes. There is no arithmetic
; instruction in this machine, so every one of these is an ordinary send -- the
; same send the tree-walker makes, minus the tree.
selectors := dictionary:new.
selectors:atPut("+", "add").          selectors:atPut("-", "sub").
selectors:atPut("*", "mul").          selectors:atPut("/", "div").
selectors:atPut("=", "equals").       selectors:atPut("<>", "notEquals").
selectors:atPut("<", "lessThan").     selectors:atPut(">", "greaterThan").
selectors:atPut("<=", "lessOrEqual"). selectors:atPut(">=", "greaterOrEqual").

comparisons := ["=", "<>", "<", "<=", ">", ">="].
additive    := ["+", "-"].
multiplicative := ["*", "/"].

keywords := ["PRINT", "GOTO", "IF", "THEN", "END", "REM", "LET"].

; ---------------------------------------------------------------------------
; A token, and a node

token := object:new.
token:kind := 'word.        ; 'number 'string 'word 'punct
token:text := "".

makeToken := { kind, text | | t |
    t := token:new. t:kind := kind. t:text := text. t }.

node := object:new.
node:kind := 'number.       ; 'number 'string 'variable 'binary 'negate
node:value := nil.
node:name := "".
node:op := "".
node:left := nil.
node:right := nil.

numberNode   := { v | | n | n := node:new. n:kind := 'number. n:value := v. n }.
stringNode   := { v | | n | n := node:new. n:kind := 'string. n:value := v. n }.
variableNode := { s | | n | n := node:new. n:kind := 'variable. n:name := s. n }.
negateNode   := { x | | n | n := node:new. n:kind := 'negate. n:left := x. n }.
binaryNode   := { op, l, r | | n |
    n := node:new. n:kind := 'binary. n:op := op. n:left := l. n:right := r. n }.

; A statement, with the label that stands in front of it and the source line it
; came from -- the line is carried this far because the `.sob` records which
; line each byte belongs to, and a debugger reads that back.
stmt := object:new.
stmt:kind := 'rem.          ; 'rem 'let 'print 'goto 'ifgoto 'end
stmt:line := #1.
stmt:label := nil.
stmt:name := "".            ; 'let
stmt:expr := nil.           ; 'let, 'ifgoto (the condition)
stmt:items := nil.          ; 'print
stmt:target := "".          ; 'goto, 'ifgoto

; ---------------------------------------------------------------------------
; The compiler

sola := object:new.
sola:path := "prog.bas".
sola:atLine := #0.
sola:statements := nil.

sola:code := nil.
sola:names := nil.
sola:nameIndex := nil.
sola:constants := nil.
sola:constIndex := nil.
sola:labelAt := nil.        ; label -> the code offset it stands in front of
sola:fixups := nil.         ; [at, label, line] for every jump, patched at the end
sola:lineMarks := nil.      ; [offset, line], to be run-length encoded

sola:fail := { message |
    self:atLine:equals(#0):ifElse(
        { error:raise(message) },
        { error:raise("line {}: {}":fill([self:atLine, message])) }) }.

; ---------------------------------------------------------------------------
; Tokenising, one line at a time
;
; Line by line rather than over the whole text, because SolaBasic is
; line-oriented: a statement ends at the end of its line, there is no
; continuation, and `REM` swallows the rest of its line as raw text.

sola:tokenise := { text | | s, out, c |
    s := scan:on(text).
    out := array:new.
    { s:atEnd:not }:whileTrue({
        c := s:peek.
        [ { isSpace:value(c) },      { s:step },
          { c:equals("'") },         { s:skipWhile({ any | true }) },
          { isDigit:value(c):or({ c:equals("."):and({
                isDigit:value(s:peekAt(#1)) }) }) },
                                     { out:add(self:numberToken(s)) },
          { isLetter:value(c) },     { out:add(self:wordToken(s)) },
          { c:equals("\"") },        { out:add(self:quotedToken(s)) },
                                     { out:add(self:punctToken(s)) } ]:ifElseIf }).
    out }.

sola:numberToken := { s | | start |
    start := s:pos.
    s:skipWhile({ c | isDigit:value(c) }).
    s:match("."):ifTrue({ s:skipWhile({ c | isDigit:value(c) }) }).
    s:peek:notNil:and({ s:peek:asUppercase:equals("E") }):ifTrue({
        s:step.
        s:match("+"):ifFalse({ s:match("-") }).
        s:skipWhile({ c | isDigit:value(c) }) }).
    makeToken:value('number, s:since(start)) }.

; Folded to uppercase, so `print x` and `PRINT X` are one program. A string
; literal is not folded, which is why this happens here and not to the line.
sola:wordToken := { s |
    makeToken:value('word,
        s:takeWhile({ c | isLetter:value(c):or({ isDigit:value(c) }) }):asUppercase) }.

sola:quotedToken := { s | | text |
    s:step.
    text := s:takeUntil({ c | c:equals("\"") }).
    s:match("\""):ifFalse({ self:fail("a string was never closed") }).
    makeToken:value('string, text) }.

sola:punctToken := { s | | c |
    c := s:next.
    c:equals("<"):ifTrue({
        s:match("="):ifElse({ c := "<=" }, { s:match(">"):ifTrue({ c := "<>" }) }) }).
    c:equals(">"):ifTrue({ s:match("="):ifTrue({ c := ">=" }) }).
    "+-*/(),;=<>:":indexOf(c:at(#1)):isNil:ifTrue({
        self:fail("'{}' means nothing here":fill([c])) }).
    makeToken:value('punct, c) }.

; ---------------------------------------------------------------------------
; Parsing
;
; A cursor into one line's tokens. `cursor` is where the next unread token is,
; and every parse routine leaves it pointing past what it read.

sola:tokens := nil.
sola:cursor := #1.

sola:peekToken := { self:tokenAt(self:cursor) }.
sola:tokenAt := { i |
    i:lessOrEqual(self:tokens:size):ifElse({ self:tokens:at(i) }, { nil }) }.
sola:takeToken := { | t |
    t := self:peekToken. self:cursor := self:cursor:add(#1). t }.
sola:atEndOfLine := { self:cursor:greaterThan(self:tokens:size) }.

; Is the next token this punctuation or word?
sola:nextIs := { text | | t |
    t := self:peekToken.
    t:notNil:and({ t:text:equals(text) }) }.

; ---------------------------------------------------------------------------
; A line: an optional label, then at most one statement
;
; **A number at the start of a line is a label**, not a line number. That is
; CB80's rule taken over whole -- a label is a string of characters rather than
; a numeric quantity -- and it is what lets an old listing through unaltered
; while nothing in this program ever sorts one or expects them to ascend.

sola:parseLine := { text, line | | st, t |
    self:atLine := line.
    self:tokens := self:tokenise(text).
    self:cursor := #1.
    self:atEndOfLine:ifElse({ nil }, {
        st := stmt:new.
        st:line := line.

        ; A label: `Name:` or a bare number.
        t := self:peekToken.
        t:kind:equals('number):ifTrue({
            st:label := t:text. self:takeToken }).
        t:kind:equals('word):and({ keywords:indexOf(t:text):isNil }):and({
            | n | n := self:tokenAt(self:cursor:add(#1)).
                  n:notNil:and({ n:text:equals(":") }) }):ifTrue({
            st:label := t:text. self:takeToken. self:takeToken }).

        self:atEndOfLine:ifElse({ st:kind := 'rem }, { self:parseStatement(st) }).
        st }) }.

sola:parseStatement := { st | | t |
    t := self:peekToken.
    [ { t:kind:equals('word):and({ t:text:equals("REM") }) },
        { st:kind := 'rem },
      { t:kind:equals('word):and({ t:text:equals("END") }) },
        { self:takeToken. st:kind := 'end. self:expectEndOfLine("END") },
      { t:kind:equals('word):and({ t:text:equals("PRINT") }) },
        { self:takeToken. self:parsePrint(st) },
      { t:kind:equals('word):and({ t:text:equals("GOTO") }) },
        { self:takeToken. st:kind := 'goto. st:target := self:labelName },
      { t:kind:equals('word):and({ t:text:equals("IF") }) },
        { self:takeToken. self:parseIf(st) },
        { self:parseAssignment(st) } ]:ifElseIf }.

; The label a jump names. A word or a number, and nothing else -- the error
; here is worth naming because the mistake is almost always a later BASIC:
; `GOTO` in QBasic takes a label, and in every BASIC before it a line number,
; and here those are the same thing wearing different clothes.
sola:labelName := { | t |
    t := self:takeToken.
    t:isNil:ifTrue({ self:fail("GOTO needs a label to jump to") }).
    t:kind:equals('word):or({ t:kind:equals('number) }):ifFalse({
        self:fail("'{}' is not a label":fill([t:text])) }).
    self:expectEndOfLine("GOTO").
    t:text }.

sola:expectEndOfLine := { what |
    self:atEndOfLine:ifFalse({
        self:fail("{} takes nothing after it, and there is '{}'"
            :fill([what, self:peekToken:text])) }) }.

sola:parseAssignment := { st | | t |
    t := self:takeToken.
    t:text:equals("LET"):ifTrue({ t := self:takeToken }).
    t:isNil:or({ t:kind:equals('word):not }):ifTrue({
        self:fail("a statement starts with a keyword or a variable") }).
    self:nextIs("="):ifFalse({
        self:fail("'{}' is not a statement, and is not followed by '='"
            :fill([t:text])) }).
    self:takeToken.
    st:kind := 'let.
    st:name := t:text.
    st:expr := self:parseExpression.
    self:expectEndOfLine("an assignment") }.

; `IF <condition> THEN GOTO <label>`, and `THEN <label>` for short, which is
; what every BASIC has allowed since there were labels to write.
sola:parseIf := { st |
    st:kind := 'ifgoto.
    st:expr := self:parseExpression.
    self:nextIs("THEN"):ifFalse({ self:fail("IF needs THEN") }).
    self:takeToken.
    self:nextIs("GOTO"):ifTrue({ self:takeToken }).
    st:target := self:labelName }.

sola:parsePrint := { st | | t |
    st:kind := 'print.
    st:items := array:new.
    { self:atEndOfLine:not }:whileTrue({
        st:items:add(self:parseExpression).
        self:atEndOfLine:ifFalse({
            t := self:peekToken.
            t:text:equals(";"):or({ t:text:equals(",") }):ifElse(
                { self:takeToken },
                { self:fail("PRINT separates its items with ';' or ','") }) }) }) }.

; ---------------------------------------------------------------------------
; Expressions
;
; Four levels: comparison, then additive, then multiplicative, then unary minus
; and a primary. Comparison is lowest, which is what lets `IF A + 1 < B THEN`
; read the way it looks.

sola:parseExpression := { | left, op |
    left := self:parseAdditive.
    { self:peekToken:notNil:and({
        comparisons:indexOf(self:peekToken:text):notNil }) }:whileTrue({
        op := self:takeToken:text.
        left := binaryNode:value(op, left, self:parseAdditive) }).
    left }.

sola:parseAdditive := { | left, op |
    left := self:parseMultiplicative.
    { self:peekToken:notNil:and({
        additive:indexOf(self:peekToken:text):notNil }) }:whileTrue({
        op := self:takeToken:text.
        left := binaryNode:value(op, left, self:parseMultiplicative) }).
    left }.

sola:parseMultiplicative := { | left, op |
    left := self:parseUnary.
    { self:peekToken:notNil:and({
        multiplicative:indexOf(self:peekToken:text):notNil }) }:whileTrue({
        op := self:takeToken:text.
        left := binaryNode:value(op, left, self:parseUnary) }).
    left }.

sola:parseUnary := {
    self:nextIs("-"):ifElse(
        { self:takeToken. negateNode:value(self:parseUnary) },
        { self:parsePrimary }) }.

sola:parsePrimary := { | t, inner |
    t := self:takeToken.
    t:isNil:ifTrue({ self:fail("an expression stops short") }).
    [ { t:kind:equals('number) }, { numberNode:value(t:text:asFloat) },
      { t:kind:equals('string) }, { stringNode:value(t:text) },
      { t:text:equals("(") },
        { inner := self:parseExpression.
          self:nextIs(")"):ifFalse({ self:fail("a '(' was never closed") }).
          self:takeToken.
          inner },
      { t:kind:equals('word) },    { variableNode:value(t:text) },
        { self:fail("'{}' cannot start an expression":fill([t:text])) }
    ]:ifElseIf }.

; ---------------------------------------------------------------------------
; Emitting
;
; Bytes go into an array and are handed to `sob.sol` at the end. Every operand
; wider than a byte is little-endian, which is the format's rule since version
; 14 and the reason there was a version 14.

sola:here := { self:code:size }.
sola:byte := { b | self:code:add(b:bitAnd(#255)) }.
sola:u16 := { n | self:byte(n). self:byte(n:shiftRight(#8)) }.

; Names are interned **when the instruction mentioning them is emitted**, so the
; table's order is the order the code refers to things. Selectors, global names
; and string literals all share it, which is the format's doing and not a
; shortcut here.
sola:nameFor := { text |
    self:nameIndex:includes(text):ifElse(
        { self:nameIndex:at(text) },
        { | i | i := self:names:size.
                self:names:add(text).
                self:nameIndex:atPut(text, i).
                i }) }.

; Constants are shared by value **and type**, which matters in a language that
; has both -- though this stage has only floats, so the key carries the tag
; against the day it does not.
sola:constFor := { tag, value | | key |
    key := tag:asString:concat(":"):concat(value:asString).
    self:constIndex:includes(key):ifElse(
        { self:constIndex:at(key) },
        { | i | i := self:constants:size.
                self:constants:add([tag, value]).
                self:constIndex:atPut(key, i).
                i }) }.

sola:emitConst  := { v | self:byte(CONST).   self:u16(self:constFor(#2, v)) }.
sola:emitString := { s | self:byte(STRING).  self:u16(self:nameFor(s)) }.
sola:emitGlobal := { s | self:byte(GLOBAL).  self:u16(self:nameFor(s)) }.
sola:emitStore  := { s | self:byte(SETGLOB). self:u16(self:nameFor(s)) }.
sola:emitSend   := { sel, argc |
    self:byte(SEND). self:u16(self:nameFor(sel)). self:byte(argc) }.
sola:emitPop    := { self:byte(POP) }.

; ---------------------------------------------------------------------------
; The jump, which is the whole of stage 3
;
; **The opcode is not known when the jump is emitted.** A jump forward is
; `OP_JUMP` and a jump backward is `OP_LOOP` -- two opcodes, because the machine
; has no signed offset and the verifier relies on everything else moving
; forwards. Which one a `GOTO` is depends on where its label turns out to be,
; and that is not known until the whole program has been emitted.
;
; They are both three bytes, which is what makes this easy: three zero bytes go
; down as a placeholder and the fixup list remembers where. Nothing has to be
; moved afterwards, so no offset already computed can be invalidated by a later
; patch -- which is the trap in every backpatching scheme that emits a short
; jump and grows it.

sola:emitJump := { label | | at |
    at := self:here.
    self:byte(#0). self:byte(#0). self:byte(#0).
    self:fixups:add([at, label, self:atLine]) }.

sola:patchJump := { at, op, offset |
    offset:greaterThan(jumpLimit):ifTrue({
        self:fail("a jump of {} bytes: no jump reaches further than {}"
            :fill([offset, jumpLimit])) }).
    self:code:atPut(at:add(#1), op).
    self:code:atPut(at:add(#2), offset:bitAnd(#255)).
    self:code:atPut(at:add(#3), offset:shiftRight(#8):bitAnd(#255)) }.

; **A jump to a label that does not exist is reported before anything runs**,
; which is the same rule `basic.sol` keeps for a `GOTO` to a missing line: a
; program that starts, prints, and then discovers it cannot go where it was told
; has already done half its work wrongly.
sola:resolveJumps := {
    self:fixups:do({ f | | at, label, target, after |
        at := f:at(#1).
        label := f:at(#2).
        self:labelAt:includes(label):ifFalse({
            self:atLine := f:at(#3).
            self:fail("there is no label '{}' to jump to":fill([label])) }).
        target := self:labelAt:at(label).
        after := at:add(#3).
        target:greaterOrEqual(after):ifElse(
            { self:patchJump(at, JUMP, target:sub(after)) },
            { self:patchJump(at, LOOP, after:sub(target)) }) }) }.

; ---------------------------------------------------------------------------
; Expressions, into instructions
;
; Left, right, send. There is no arithmetic instruction in this machine, so a
; SolaBasic `+` is exactly one `OP_SEND` -- against the several the tree-walker
; makes per node, which is where the difference between the two comes from.

sola:emitExpression := { n |
    [ { n:kind:equals('number) },   { self:emitConst(n:value) },
      { n:kind:equals('string) },   { self:emitString(n:value) },
      { n:kind:equals('variable) }, { self:emitGlobal(n:name) },
      { n:kind:equals('negate) },
        { self:emitExpression(n:left). self:emitSend("negated", #0) },
        { self:emitExpression(n:left).
          self:emitExpression(n:right).
          self:emitSend(selectors:at(n:op), #1) } ]:ifElseIf }.

; ---------------------------------------------------------------------------
; Statements, into instructions
;
; **Every one of these leaves the stack exactly as it found it**, at depth 0,
; and that is not tidiness -- it is what makes a label a merge point the
; verifier accepts from any number of jumps. An assignment leaves its value
; behind (all four of the machine's stores do, so that `c := b := #45` falls
; out) and the `POP` here is what discards it.

sola:emitStatement := { st |
    self:atLine := st:line.
    self:mark(st:line).
    st:label:notNil:ifTrue({
        self:labelAt:includes(st:label):ifTrue({
            self:fail("the label '{}' is used twice":fill([st:label])) }).
        self:labelAt:atPut(st:label, self:here) }).

    [ { st:kind:equals('rem) },  { nil },
      { st:kind:equals('let) },
        { self:emitExpression(st:expr). self:emitStore(st:name). self:emitPop },
      { st:kind:equals('print) }, { self:emitPrint(st) },
      { st:kind:equals('goto) },  { self:emitJump(st:target) },
      { st:kind:equals('end) },   { self:byte(HALT) },
        { self:emitIfGoto(st) } ]:ifElseIf }.

; `IF <condition> THEN GOTO <label>` is the condition, a conditional jump over
; the `GOTO`, and the `GOTO`.
;
; `OP_JUMP_IF_FALSE` carries the name of the selector it was inlined from so
; that a non-boolean reports the same *does not understand* a real send would.
; There is no real send here to name, so it names `ifTrue` -- which is the
; message a condition that is not a boolean has failed to understand, and is
; what the reader of the error needs to be told.
sola:emitIfGoto := { st |
    self:emitCondition(st:expr).
    self:byte(JMPF). self:u16(#3). self:u16(self:nameFor("ifTrue")).
    self:emitJump(st:target) }.

; A condition that is already a comparison answers a boolean. Anything else is
; a number, and BASIC's rule is that a non-zero number is true -- so it is
; compared with nought rather than handed to the machine, which would refuse it.
sola:emitCondition := { n |
    self:emitExpression(n).
    n:kind:equals('binary):and({ comparisons:indexOf(n:op):notNil }):ifFalse({
        self:emitConst(0.0).
        self:emitSend("notEquals", #1) }) }.

; The items of one PRINT are joined and shown once, so that `PRINT "x = "; x`
; is one line. **This is not BASIC's PRINT**: there are no print zones, no
; leading space in front of a positive number and no trailing space after one,
; and `,` does the same thing as `;`. That is stage 6 and this is stage 3.
sola:emitPrint := { st | | first |
    st:items:size:equals(#0):ifElse(
        { self:emitString("") },
        { first := true.
          st:items:do({ item |
              self:emitExpression(item).
              ; A string literal is already the thing `asString` would answer,
              ; and the send is the most expensive instruction there is.
              item:kind:equals('string):ifFalse({ self:emitSend("asString", #0) }).
              first:ifElse({ first := false }, { self:emitSend("concat", #1) }) }) }).
    self:emitSend("display", #0).
    self:emitPop }.

; ---------------------------------------------------------------------------
; Which line a byte came from
;
; Run-length encoded, because neighbouring instructions almost always share a
; line. A mark is dropped at each statement and the runs are the gaps between
; them, so the total is the size of the code and the loader can rebuild the
; parallel array it wants.

sola:mark := { line |
    self:lineMarks:add([self:here, line]) }.

sola:lineRuns := { | runs, i, at, next, line |
    runs := array:new.
    i := #1.
    { i:lessOrEqual(self:lineMarks:size) }:whileTrue({
        at := self:lineMarks:at(i):at(#1).
        line := self:lineMarks:at(i):at(#2).
        next := i:equals(self:lineMarks:size):ifElse(
            { self:code:size },
            { self:lineMarks:at(i:add(#1)):at(#1) }).
        next:greaterThan(at):ifTrue({
            runs:size:notEquals(#0):and({
                runs:at(runs:size):at(#2):equals(line) }):ifElse(
                { runs:at(runs:size):atPut(#1,
                    runs:at(runs:size):at(#1):add(next:sub(at))) },
                { runs:add([next:sub(at), line]) }) }).
        i := i:add(#1) }).
    runs }.

; ---------------------------------------------------------------------------
; The whole of it

sola:compile := { source, path | | chunk |
    self:path := path.
    self:statements := array:new.
    self:code := array:new.
    self:names := array:new.
    self:nameIndex := dictionary:new.
    self:constants := array:new.
    self:constIndex := dictionary:new.
    self:labelAt := dictionary:new.
    self:fixups := array:new.
    self:lineMarks := array:new.

    self:readStatements(source).
    self:statements:do({ st | self:emitStatement(st) }).

    ; The last instruction of every chunk is a HALT and the verifier requires
    ; it. A label on the line after the last statement is a real thing to
    ; write -- `GOTO Done` where `Done:` is the end of the program -- so the
    ; HALT is where any such label lands, and it is marked before it is emitted.
    self:atLine := self:statements:size:equals(#0):ifElse(
        { #1 }, { self:statements:at(self:statements:size):line:add(#1) }).
    self:mark(self:atLine).
    self:trailingLabels.
    self:needsHalt:ifTrue({ self:byte(HALT) }).

    self:resolveJumps.

    chunk := dictionary:new.
    chunk:atPut("slots", #1).
    chunk:atPut("names", self:names).
    chunk:atPut("constants", self:constants).
    chunk:atPut("code", self:code).
    chunk:atPut("lines", self:lineRuns).
    chunk:atPut("files", [path]).
    chunk:atPut("fileRuns", [[self:code:size, #0]]).
    chunk:atPut("slotNames", [""]).
    chunk:atPut("methods", []).
    chunk }.

; **The chunk's last instruction must be a HALT and the verifier requires it**,
; so one is added -- unless the program already ends in `END`, which is that
; instruction, and nothing is waiting for an offset behind it. A trailing label
; is what makes the difference: `GOTO Done` where `Done:` is the last line of
; the program needs somewhere to land, and that somewhere is the HALT.
sola:needsHalt := {
    self:pendingLabels:size:notEquals(#0):or({
        self:statements:size:equals(#0):or({
            self:statements:at(self:statements:size):kind:notEquals('end) }) }) }.

; A label with no statement after it is a label on the HALT.
sola:trailingLabels := {
    self:pendingLabels:do({ pending |
        self:atLine := pending:at(#2).
        self:labelAt:includes(pending:at(#1)):ifTrue({
            self:fail("the label '{}' is used twice":fill([pending:at(#1)])) }).
        self:labelAt:atPut(pending:at(#1), self:here) }) }.

sola:pendingLabels := nil.

sola:readStatements := { source | | line, st |
    self:pendingLabels := array:new.
    line := #0.
    source:split("\n"):do({ text |
        line := line:add(#1).
        st := self:parseLine(text, line).
        st:notNil:ifTrue({
            ; A bare label on a line of its own belongs to the next statement
            ; there is, which may be none -- in which case it is the HALT's.
            st:kind:equals('rem):and({ st:label:notNil }):ifElse(
                { self:pendingLabels:add([st:label, line]) },
                { self:pendingLabels:do({ pending |
                      self:statements:add(
                          self:labelOnly(pending:at(#1), pending:at(#2))) }).
                  self:pendingLabels := array:new.
                  self:statements:add(st) }) }) }) }.

; A statement that is nothing but a label, so that the label gets an offset.
sola:labelOnly := { label, line | | st |
    st := stmt:new. st:kind := 'rem. st:label := label. st:line := line. st }.

; ---------------------------------------------------------------------------
; The command line

demo := "' A demonstration, and the shape stage 3 was written to prove.\n"
    :concat("i = 0\n")
    :concat("Top:\n")
    :concat("  i = i + 1\n")
    :concat("  PRINT \"i = \"; i\n")
    :concat("  IF i < 5 THEN GOTO Top\n")
    :concat("  GOTO Done\n")
    :concat("  PRINT \"never printed\"\n")
    :concat("Done:\n")
    :concat("  PRINT \"counted to \"; i\n")
    :concat("  END\n").

source := nil.
inPath := "demo.bas".
outPath := "build/sola/demo.sob".

system:arguments:size:equals(#0):ifElse(
    { source := demo },
    { inPath := system:arguments:at(#1).
      source := system:readFile(inPath).
      source:isNil:ifTrue({ error:raise("cannot read {}":fill([inPath])) }).
      outPath := system:arguments:size:greaterOrEqual(#2):ifElse(
          { system:arguments:at(#2) },
          { inPath:concat(".sob") }) }).

system:arguments:size:equals(#0):ifTrue({
    system:isDirectory("build/sola"):ifFalse({
        system:isDirectory("build"):ifFalse({ system:makeDirectory("build") }).
        system:makeDirectory("build/sola") }).
    "":display.
    "compiling the demonstration, which is:":display.
    "":display.
    demo:display }).

bytes := sob:file(sola:compile(source, inPath)).
system:writeFile(outPath, bytes).

"":display.
"{} -> {}, {} bytes":fill([inPath, outPath, bytes:size:asString]):display.
"":display.
"run it:  ./bin/solvm {}":fill([outPath]):display.
"see it:  ./bin/solvm --dump {}":fill([outPath]):display.
"":display.
