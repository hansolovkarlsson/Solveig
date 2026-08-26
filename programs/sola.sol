; sola.sol -- SolaBasic compiled to bytecode. Stage 3: labels and GOTO.
;
; Run with:  ./bin/solas programs/sola.sol && ./bin/solvm programs/sola.sob
; On a file:  ./bin/solvm programs/sola.sob prog.bas [prog.sob]
;
; The thirteenth program here, and the second that is about another language --
; but where [basic.sol](basic.sol) *interprets* one, this **compiles** one, and
; the file it writes is run by `solvm` with nothing of this program present.
;
; The language is [SolaBasic](../docs/SOLABASIC.md), and there is a
; [reference manual](../docs/SOLABASIC-REFERENCE.md) for people who want to
; write it rather than read about it. Stages 1, 2, 3 and 4 of the eight that
; document lists are here -- everything except arrays, `PRINT`'s real
; formatting, files, and the QuickBASIC comparison harness.
;
; **Stage 3 went first on purpose** -- it is `GOTO` and labels, the claim the
; whole design rests on, and the document says to reach it in week one rather
; than week six. Stage 2, the structured half, then needed nothing the first
; half had not already built. Stage 4 is procedures, and it is the one the
; document called the most expensive item in the language.
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
; What stage 2 cost, which was less than expected
;
; **Every structured statement is jumps and a stack, and the jumps were already
; here.** `GOTO` needed a hole punched in the code and filled in when its label
; turned up; `IF`, `SELECT CASE`, `FOR`, `DO` and `WHILE` need exactly the same
; hole, filled in when their closing line turns up instead. So the whole of
; stage 2 is one stack of open blocks, each frame holding the holes it still
; owes an answer to, and nothing was added to the back end at all.
;
; **The blocks are a stack and the statements stay flat**, which is the one
; design decision here worth arguing about. A parser that built a tree is the
; other way, and it is the wrong way: BASIC's blocks are not written as nesting,
; they are an opening line and a closing line, and half the errors worth
; reporting are about the two not matching. A stack has the mismatch in its
; hand -- `NEXT` closes whatever is on top and says what it found -- where a
; tree would have refused to parse and had less to say about why.
;
; **And it is what makes `EXIT FOR` reach the right loop.** It leaves the
; innermost `FOR`, not the innermost block, so an `EXIT FOR` inside an `IF`
; inside the loop is a search down the stack for the first frame of that kind.
; That is four lines against a tree walk.
;
; ---------------------------------------------------------------------------
; What stage 1 cost, which was the type system and the library
;
; **Types have to be worked out before a single byte is emitted.** A conversion
; is an instruction acting on the top of the stack, so turning an Integer into a
; Double must be emitted *after* that Integer is pushed and *before* the value
; beside it -- and by then it is much too late to discover it was needed. So
; every node learns its type in a pass of its own, and emitting is a second walk
; that already knows where the conversions go. Getting that order wrong is the
; whole difficulty of the stage; everything after it is a table.
;
; **There is no boolean type, and that is BASIC's rule rather than a shortcut.**
; A comparison answers `-1` or `0` when it is used as a number, which is why
; `NOT`, `AND` and `OR` are bit operations and still read correctly. Internally a
; comparison answers the machine's boolean, because that is what a conditional
; jump wants; turning one into `-1` costs a jump, so the jump is emitted only
; where the value really is used as a number -- which is almost nowhere.
;
; **Two operators follow QBasic against the machine.** SolVM's integer `div` and
; `mod` are floored, so `-7 \\ 2` would be `-4` and `-7 MOD 2` would be `1`.
; QBasic says `-3` and `-1`, and going through the float divide and `truncated`
; gets the sign right. What it costs is exactness above 2^53, which is a smaller
; wrong answer than the sign being wrong and is written down rather than left.
;
; **A supplied function is emitted where it is called.** There is nowhere to put
; a library: the `.sob` this writes is the whole program and none of `lib/` is in
; it. So `SGN` is a scratch slot and two conditional jumps, `LEFT$` is two
; comparisons that clamp before `copyFrom` is allowed near it, and `LTRIM$` is a
; loop -- all of it the same jumps a `SELECT CASE` compiles to.
;
; ---------------------------------------------------------------------------
; What stage 4 cost, which was the expensive one
;
; **A SUB is a block and a call is `value`.** That is a close fit rather than a
; contrivance: a block has its own frame, takes its arguments in slots 1..n, and
; answers its last expression. A `FUNCTION` answers by assigning to its own
; name, so the name is a local and the body's last act is to push it.
;
; **It never captures its home frame.** ROADMAP 3.1 says a block that reads the
; frame it was written in cannot outlive it, and that would have been in the way
; -- except that a SolaBasic procedure has no reason to reach outside itself,
; because every name it uses is its own slot or a global. So the flags say
; block-and-not-capturing and the limitation never bites.
;
; **What does bite is 3.5**, exactly as SOLABASIC.md predicted before any of
; this existed: a call is a real frame, so recursion stops around 254 levels.
; The trace names the BASIC procedure and the BASIC line when it does.
;
; **By reference is a box, and the variable *is* the box.** QBasic passes by
; reference -- assigning to a parameter assigns to the caller's variable -- and
; passing by value instead would leave `SWAP`-shaped programs running and
; answering *differently*, which is the one outcome this project does not take.
; The implementation is a one-element array: a variable that is ever passed by
; reference is kept in one everywhere, so the call hands over the array itself
; and the callee's `atPut` reaches the caller's storage. No wrapping at the
; call, no copying back, nothing to keep alive across it, and nothing to get
; wrong when the call is recursive.
;
; **Which parameters are by reference is a fixed point.** A parameter is one
; when the procedure assigns to it, or when it hands it on to somewhere that
; does -- and that second half chains, so it takes as many rounds as the chain
; is long. It settles because a parameter only ever turns from by-value to
; by-reference and never back.
;
; ---------------------------------------------------------------------------
; What is here, and what is stage 5 onwards
;
;   labels        `Name:` at the start of a line, and a bare number, which is a
;                 label and not a line number -- CB80's rule, so it need not be
;                 ordered and nothing here ever sorts one
;   GOTO          forwards and backwards, to any label in the program
;   IF            both shapes: a block with `ELSEIF` and `ELSE`, and the
;                 one-line form, which holds a single statement and an `ELSE`
;   SELECT CASE   value lists, `low TO high`, `CASE IS <op>`, `CASE ELSE`
;   FOR / NEXT    with `STEP`, nested, and `NEXT j, i` closing two at once
;   DO / LOOP     `WHILE` or `UNTIL` at either end, or neither
;   WHILE / WEND  the same loop under its older spelling
;   EXIT          `EXIT FOR`, `EXIT DO`, `EXIT SUB`, `EXIT FUNCTION`
;   SUB           with parameters, called as `CALL S(a)` or `S a`
;   FUNCTION      answering by assignment to its own name, and recursive
;   SHARED        inside a procedure, naming a module variable to use
;   STATIC        a local that survives between calls
;   DECLARE       read and dropped; nothing needs declaring here
;   assignment    `LET` optional, scalars only
;   PRINT         expressions and strings, `;` and `,`
;   END           stops
;   types         Integer, Double and String, by suffix or by `DEF`
;   expressions   `^ * / \\ MOD + -`, the six comparisons, `NOT AND OR XOR`
;   functions     all twenty-seven, compiled where they are called
;   RANDOMIZE     reseeds the one generator
;   comments      `REM` and `'`
;
; **Not here, and not pretended:** arrays, `DIM`, `CONST`, `INPUT` and files. `PRINT`'s real formatting is
; stage 6; here the items of one `PRINT` are joined and shown, with no zones and
; no trailing space, so its output is **not** what a BASIC prints. That is a
; stage, not a divergence, and it is the one thing here most likely to be
; mistaken for a bug.

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
NIL     := #1.
GLOBAL  := #2.
LOCAL   := #4.
SETLOCAL := #5.
SETGLOB := #3.
STRING  := #9.
BLOCK   := #8.
SEND    := #11.
JUMP    := #13.
JMPF    := #14.
LOOP    := #17.
POP     := #18.
RETURN  := #19.
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
selectors:atPut("AND", "bitAnd").     selectors:atPut("OR", "bitOr").
selectors:atPut("XOR", "bitXor").

comparisons := ["=", "<>", "<", "<=", ">", ">="].
additive    := ["+", "-"].
multiplicative := ["*", "/"].
bitwise     := ["AND", "OR", "XOR"].

; The three types, and the fourth that is not one.
;
; `'boolean` is what a comparison answers and is **not a SolaBasic type**: the
; language has no boolean, and `A = B` used as a number is `-1` or `0` as it is
; in every BASIC. It exists here because a condition wants the machine's boolean
; and turning one into `-1` costs a jump -- so the jump is emitted only where the
; value is used as a number, which is almost nowhere.
types := ['integer, 'double, 'string].

; Filled in below, once the emitters they need exist.
builtins := dictionary:new.

suffixTypes := dictionary:new.
suffixTypes:atPut("%", 'integer).  suffixTypes:atPut("&", 'integer).
suffixTypes:atPut("#", 'double).   suffixTypes:atPut("$", 'string).

keywords := ["PRINT", "GOTO", "IF", "THEN", "ELSE", "ELSEIF", "END", "REM",
             "LET", "SELECT", "CASE", "IS", "TO", "FOR", "STEP", "NEXT",
             "DO", "LOOP", "WHILE", "WEND", "UNTIL", "EXIT",
             "SUB", "FUNCTION", "CALL", "SHARED", "STATIC", "DECLARE",
             "AND", "OR", "XOR", "NOT", "MOD",
             "DEFINT", "DEFLNG", "DEFDBL", "DEFSTR", "RANDOMIZE"].

; ---------------------------------------------------------------------------
; A token, and a node

token := object:new.
token:kind := 'word.        ; 'number 'string 'word 'punct
token:text := "".

makeToken := { kind, text | | t |
    t := token:new. t:kind := kind. t:text := text. t }.

node := object:new.
node:kind := 'number.       ; 'number 'string 'variable 'binary 'negate 'call
node:value := nil.
node:name := "".            ; 'variable, 'call
node:op := "".
node:left := nil.
node:right := nil.
node:args := nil.           ; 'call
; The type the value will have, worked out over the whole tree before any of it
; is emitted -- because a conversion has to be inserted *before* the value it
; converts is pushed, and by then it is too late to ask.
node:type := nil.
; What both sides of a binary node have to be turned into before the send. Not
; always the answer's type: `/` answers a Double from two Integers, `\\` answers
; an Integer from two Doubles, and a comparison answers neither.
node:operandType := nil.
; **Whether it was written in brackets**, which matters in exactly one place:
; `CALL Foo((x))` passes a copy where `CALL Foo(x)` passes the variable. That is
; QBasic's own way of spelling by-value and the only one SolaBasic has.
node:grouped := false.

numberNode   := { v, t | | n |
    n := node:new. n:kind := 'number. n:value := v. n:type := t. n }.
stringNode   := { v | | n |
    n := node:new. n:kind := 'string. n:value := v. n:type := 'string. n }.
variableNode := { s | | n | n := node:new. n:kind := 'variable. n:name := s. n }.
negateNode   := { x | | n | n := node:new. n:kind := 'negate. n:left := x. n }.
notNode      := { x | | n | n := node:new. n:kind := 'not. n:left := x. n }.
binaryNode   := { op, l, r | | n |
    n := node:new. n:kind := 'binary. n:op := op. n:left := l. n:right := r. n }.
callNode     := { name, args | | n |
    n := node:new. n:kind := 'call. n:name := name. n:args := args. n }.

; A statement, with the label that stands in front of it and the source line it
; came from -- the line is carried this far because the `.sob` records which
; line each byte belongs to, and a debugger reads that back.
stmt := object:new.
stmt:kind := 'rem.
    ; 'rem 'let 'print 'goto 'end
    ; 'ifline 'ifblock 'elseif 'else 'endif
    ; 'select 'case 'caseelse 'endselect
    ; 'for 'next  'do 'loop  'while 'wend  'exit
stmt:line := #1.
stmt:label := nil.
stmt:name := "".            ; 'let, 'for
stmt:expr := nil.           ; 'let, the condition of every conditional, 'select
stmt:items := nil.          ; 'print, and 'next's list of variables
stmt:target := "".          ; 'goto, and what 'exit leaves
stmt:then := nil.           ; 'ifline: the statement after THEN
stmt:otherwise := nil.      ; 'ifline: the statement after ELSE
stmt:limit := nil.          ; 'for
stmt:step := nil.           ; 'for, nil when none was written
stmt:test := 'none.         ; 'do and 'loop: 'none 'while 'until
stmt:alternatives := nil.   ; 'case
stmt:body := nil.           ; 'sub and 'function: the statements between them

; ---------------------------------------------------------------------------
; A block being compiled
;
; **The statements stay flat and the blocks are a stack.** A parser that built a
; tree would be the other way to do this, and it is the wrong way here: BASIC's
; block structure is not written as nesting, it is written as an opening
; statement and a closing one on lines of their own, with a listing that is
; legal to write and illegal to nest wrongly. Matching them on a stack while
; emitting is the same shape as the source, and it is what makes `EXIT FOR`
; reach the right loop -- the innermost frame of that kind, which is a search up
; a stack and would be a search up a tree.
;
; A frame holds what has to be patched later and what has to be jumped back to,
; and nothing else. Everything in it is a code offset.

frame := object:new.
frame:kind := 'if.          ; 'if 'select 'for 'do 'while
frame:line := #1.           ; where it was opened, for the error if it is not closed
frame:pending := nil.       ; forward holes waiting for the next arm of the block
frame:exits := nil.         ; forward holes waiting for the end of the block
frame:top := #0.            ; a loop: the offset to jump back to
frame:name := "".           ; 'for: the counter, so NEXT can be checked against it
frame:index := #0.          ; 'for: the counter's slot, when the counter is one
frame:limitSlot := #0.      ; 'for: where the limit was put, evaluated once
frame:stepSlot := #0.       ; 'for: where a computed step was put
frame:subject := #0.        ; 'select: where the subject was put, evaluated once
frame:step := nil.          ; 'for: the step, when it was written as a literal
frame:varType := 'double.   ; 'for: the counter's type, which the loop runs in
frame:subjectType := 'double.  ; 'select: the subject's type
frame:seenElse := false.    ; 'if and 'select: whether ELSE has gone by

makeFrame := { kind, line | | f |
    f := frame:new.
    f:kind := kind. f:line := line.
    f:pending := array:new. f:exits := array:new.
    f }.

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
          { c:equals("&") },         { out:add(self:basedToken(s)) },
          { isLetter:value(c) },
            ; REM takes the rest of its line as raw text, which need not be
            ; anything this could tokenise -- `REM don't` is a legal comment and
            ; an unclosed string. So the scanner stops rather than reading it.
            { out:add(self:wordToken(s)).
              out:at(out:size):text:equals("REM"):ifTrue({
                  s:skipWhile({ any | true }) }) },
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
;
; **A type suffix is part of the name.** `A%` and `A$` are two variables, not one
; variable read two ways, which is QBasic's rule -- and it is why the suffix is
; taken here rather than left to the parser as an operator.
sola:wordToken := { s | | text, suffix |
    text := s:takeWhile({ c | isLetter:value(c):or({ isDigit:value(c) }) }):asUppercase.
    s:match("!"):ifTrue({
        self:fail("'{}!' is a SINGLE, and SolaBasic has no SINGLE -- see "
            :concat("docs/SOLABASIC.md. Write {} or {}# for a Double.")
            :fill([text, text, text])) }).
    suffix := ["%", "&", "#", "$"]:select({ mark | s:looksLike(mark) }).
    suffix:size:equals(#0):ifElse(
        { makeToken:value('word, text) },
        { s:step. makeToken:value('word, text:concat(suffix:at(#1))) }) }.

; `&HFF` and `&O17`, which are integers however they are written.
sola:basedToken := { s | | mark, digits |
    s:step.
    mark := s:peek.
    mark:isNil:ifTrue({ self:fail("'&' needs H or O after it") }).
    mark := mark:asUppercase.
    ["H", "O"]:indexOf(mark):isNil:ifTrue({
        self:fail("'&{}' is not a number: write &H for hex or &O for octal"
            :fill([s:peek])) }).
    s:step.
    digits := s:takeWhile({ c |
        isDigit:value(c):or({ c:notNil:and({
            "ABCDEFabcdef":indexOf(c):notNil }) }) }).
    digits:size:equals(#0):ifTrue({ self:fail("'&{}' has no digits":fill([mark])) }).
    makeToken:value('based,
        digits:asInteger(mark:equals("H"):ifElse({ #16 }, { #8 })):asString) }.

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
    "+-*/(),;=<>:^\\":indexOf(c:at(#1)):isNil:ifTrue({
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
; **A one-line IF ends its statement at ELSE**, and there is nowhere else for
; that knowledge to live: `IF c THEN PRINT a ELSE PRINT b` needs PRINT to stop
; at a word it would otherwise have read as another item. The flag is set only
; while the two halves of such an IF are being parsed, so ELSE is an ordinary
; word everywhere else -- including where it opens a block on a line of its own.
sola:stopAtElse := false.

sola:atEndOfLine := {
    self:cursor:greaterThan(self:tokens:size):or({
        self:stopAtElse:and({ self:nextIs("ELSE") }) }) }.

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
    self:stopAtElse := false.
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

; One entry per keyword that opens a statement. A dictionary rather than a nest
; of tests, for the reason lib/control.sol gives and basic.sol's parser found
; first: seventeen alternatives written flat, against seventeen closing braces.
; Anything that is not in here is an assignment.
parsers := dictionary:new.

sola:parseStatement := { st | | t |
    t := self:peekToken.
    t:kind:equals('word):and({ parsers:includes(t:text) }):ifElse(
        { self:takeToken. parsers:at(t:text):value(self, st) },
        { self:parseAssignment(st) }) }.

; The statements a one-line IF may hold. A block cannot go on one, because its
; closing line would have nowhere to be.
inlineKinds := ['let, 'print, 'goto, 'end, 'exit].

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
    self:nextIs("="):ifElse(
        { self:takeToken.
          st:kind := 'let.
          st:name := t:text.
          st:expr := self:parseExpression.
          self:expectEndOfLine("an assignment") },
        { ; Not an assignment, so it is a call written without CALL --
          ; `Greet "world"`, which is how BASIC has always spelt one.
          st:kind := 'call.
          st:name := t:text.
          st:items := self:parseArguments(false).
          self:expectEndOfLine("a call") }) }.

; `IF <condition> THEN GOTO <label>`, and `THEN <label>` for short, which is
; what every BASIC has allowed since there were labels to write.
; ---------------------------------------------------------------------------
; The statements, one block each
;
; Each takes the compiler and the statement being filled in, and reads from the
; cursor the keyword was just taken off.

parsers:atPut("REM", { m, st | st:kind := 'rem }).

parsers:atPut("PRINT", { m, st | m:parsePrint(st) }).

parsers:atPut("GOTO", { m, st | st:kind := 'goto. st:target := m:labelName }).

; `END`, `END IF` and `END SELECT` are one keyword and three statements, which
; is why the bare one is the last arm rather than the first.
parsers:atPut("END", { m, st |
    [ { m:nextIs("IF") },
        { m:takeToken. st:kind := 'endif. m:expectEndOfLine("END IF") },
      { m:nextIs("SELECT") },
        { m:takeToken. st:kind := 'endselect. m:expectEndOfLine("END SELECT") },
      { m:nextIs("SUB") },
        { m:takeToken. st:kind := 'endsub. m:expectEndOfLine("END SUB") },
      { m:nextIs("FUNCTION") },
        { m:takeToken. st:kind := 'endfunction. m:expectEndOfLine("END FUNCTION") },
        { st:kind := 'end. m:expectEndOfLine("END") } ]:ifElseIf }).

; ---------------------------------------------------------------------------
; IF, in both of its shapes
;
; **What follows THEN decides which.** Nothing after it on the line opens a
; block that runs until `END IF`; anything else is the one-line form, which
; holds a single statement and an optional `ELSE`. That is QBasic's rule and
; every BASIC's since labels arrived, and the two forms share nothing but the
; condition.

parsers:atPut("IF", { m, st |
    st:expr := m:parseExpression.
    m:nextIs("THEN"):ifFalse({ m:fail("IF needs THEN") }).
    m:takeToken.
    m:atEndOfLine:ifElse(
        { st:kind := 'ifblock },
        { st:kind := 'ifline.
          m:stopAtElse := true.
          st:then := m:parseInlineStatement.
          m:nextIs("ELSE"):ifTrue({
              m:takeToken.
              st:otherwise := m:parseInlineStatement }).
          m:stopAtElse := false.
          m:expectEndOfLine("a one-line IF") }) }).

parsers:atPut("ELSEIF", { m, st |
    st:kind := 'elseif.
    st:expr := m:parseExpression.
    m:nextIs("THEN"):ifFalse({ m:fail("ELSEIF needs THEN") }).
    m:takeToken.
    m:expectEndOfLine("ELSEIF") }).

parsers:atPut("ELSE", { m, st | st:kind := 'else. m:expectEndOfLine("ELSE") }).

; **A bare label after THEN is a GOTO**, which is what `IF X < 5 THEN Top` has
; meant in every BASIC that had labels, and what `THEN 100` meant in every one
; before that. It is a jump and not an expression statement, because a bare
; name is not a statement in this language and so there is nothing else it
; could be.
sola:parseInlineStatement := { | sub, t, next, lead |
    t := self:peekToken.
    lead := t:isNil:ifElse({ "the end of the line" }, { t:text }).
    sub := stmt:new.
    sub:line := self:atLine.
    next := self:tokenAt(self:cursor:add(#1)).
    t:notNil:and({ t:kind:equals('number):or({
            t:kind:equals('word):and({ parsers:includes(t:text):not }) }) })
        :and({ next:isNil:or({ next:text:equals("ELSE") }) }):ifElse(
        { sub:kind := 'goto. sub:target := self:takeToken:text },
        { self:parseStatement(sub) }).
    inlineKinds:indexOf(sub:kind):isNil:ifTrue({
        self:fail("'{}' opens a block, and a one-line IF holds one statement"
            :fill([lead])) }).
    sub }.

; ---------------------------------------------------------------------------
; SELECT CASE
;
; The subject is evaluated **once** and kept, which is the standard's rule
; everywhere it is written down and the only one that makes sense: a subject
; with a side effect tested against six cases would otherwise happen six times.

parsers:atPut("SELECT", { m, st |
    m:nextIs("CASE"):ifFalse({ m:fail("SELECT needs CASE after it") }).
    m:takeToken.
    st:kind := 'select.
    st:expr := m:parseExpression.
    m:expectEndOfLine("SELECT CASE") }).

parsers:atPut("CASE", { m, st | | more |
    m:nextIs("ELSE"):ifElse(
        { m:takeToken. st:kind := 'caseelse. m:expectEndOfLine("CASE ELSE") },
        { st:kind := 'case.
          st:alternatives := array:new.
          more := true.
          { more }:whileTrue({
              st:alternatives:add(m:parseAlternative).
              m:nextIs(","):ifElse({ m:takeToken }, { more := false }) }).
          m:expectEndOfLine("CASE") }) }).

; One of the three shapes a CASE takes: a value, a range, or a comparison.
sola:parseAlternative := { | op, low |
    self:nextIs("IS"):ifElse(
        { self:takeToken.
          op := self:takeToken.
          op:isNil:or({ comparisons:indexOf(op:text):isNil }):ifTrue({
              self:fail("CASE IS needs one of = <> < <= > >=") }).
          ["is", op:text, self:parseExpression] },
        { low := self:parseExpression.
          self:nextIs("TO"):ifElse(
              { self:takeToken. ["range", low, self:parseExpression] },
              { ["value", low] }) }) }.

; ---------------------------------------------------------------------------
; FOR and NEXT
;
;     FOR <variable> = <expression> TO <expression> [STEP <expression>]
;     NEXT [<variable>[, <variable>]...]
;
; The limit and the step are evaluated **once, when the loop starts**, which is
; the standard's rule rather than an optimisation: `FOR I = 1 TO N` where the
; body assigns to `N` runs the number of times `N` named at the start.

parsers:atPut("FOR", { m, st | | t |
    st:kind := 'for.
    t := m:takeToken.
    t:isNil:or({ t:kind:equals('word):not }):ifTrue({
        m:fail("FOR needs a variable") }).
    st:name := t:text.
    m:nextIs("="):ifFalse({ m:fail("FOR needs an = after the variable") }).
    m:takeToken.
    st:expr := m:parseExpression.
    m:nextIs("TO"):ifFalse({ m:fail("FOR needs TO") }).
    m:takeToken.
    st:limit := m:parseExpression.
    m:nextIs("STEP"):ifTrue({ m:takeToken. st:step := m:parseExpression }).
    m:expectEndOfLine("FOR") }).

; `NEXT`, `NEXT I` and `NEXT J, I` -- the last closing two loops on one line,
; innermost first, which is the order they are written in and the order they
; have to close in.
parsers:atPut("NEXT", { m, st | | t |
    st:kind := 'next.
    st:items := array:new.
    { m:atEndOfLine:not }:whileTrue({
        t := m:takeToken.
        t:kind:equals('word):ifFalse({ m:fail("NEXT takes variable names") }).
        st:items:add(t:text).
        m:atEndOfLine:ifFalse({
            m:nextIs(","):ifFalse({ m:fail("NEXT separates its variables with commas") }).
            m:takeToken.
            m:atEndOfLine:ifTrue({ m:fail("a comma with no variable after it") }) }) }) }).

; ---------------------------------------------------------------------------
; DO, LOOP, WHILE and WEND
;
; `DO` takes its condition at either end or at neither, and **not at both** --
; a loop that tests twice is two loops and the reader cannot tell which one is
; meant. `WHILE`/`WEND` is `DO WHILE`/`LOOP` under another spelling, kept
; because listings have it.

parsers:atPut("DO", { m, st | st:kind := 'do. m:parseLoopTest(st, "DO") }).
parsers:atPut("LOOP", { m, st | st:kind := 'loop. m:parseLoopTest(st, "LOOP") }).

sola:parseLoopTest := { st, what |
    [ { self:nextIs("WHILE") },
        { self:takeToken. st:test := 'while. st:expr := self:parseExpression },
      { self:nextIs("UNTIL") },
        { self:takeToken. st:test := 'until. st:expr := self:parseExpression },
        { st:test := 'none } ]:ifElseIf.
    self:expectEndOfLine(what) }.

parsers:atPut("WHILE", { m, st |
    st:kind := 'while.
    st:expr := m:parseExpression.
    m:expectEndOfLine("WHILE") }).

parsers:atPut("WEND", { m, st | st:kind := 'wend. m:expectEndOfLine("WEND") }).

parsers:atPut("EXIT", { m, st | | t |
    st:kind := 'exit.
    t := m:takeToken.
    t:isNil:or({ ["FOR", "DO", "SUB", "FUNCTION"]:indexOf(t:text):isNil }):ifTrue({
        m:fail("EXIT takes FOR, DO, SUB or FUNCTION") }).
    st:target := t:text.
    m:expectEndOfLine("EXIT") }).

; ---------------------------------------------------------------------------
; SUB and FUNCTION
;
; A procedure is not a statement that runs where it is written. It is collected
; out of the listing before anything is emitted, compiled into a chunk of its
; own, and bound to its name before the module's first line runs -- which is why
; a listing may call something defined below it and `DECLARE` has nothing to do.

parsers:atPut("SUB", { m, st |
    st:kind := 'sub.
    st:name := m:plainName("SUB").
    st:items := m:parseParameters.
    m:expectEndOfLine("SUB") }).

parsers:atPut("FUNCTION", { m, st |
    st:kind := 'function.
    st:name := m:plainName("FUNCTION").
    st:items := m:parseParameters.
    m:expectEndOfLine("FUNCTION") }).

; `DECLARE` is read and dropped. QBasic needs one for a procedure used before it
; is defined and its editor writes them for you; this resolves every name in a
; pass over the whole listing first, so there is nothing for it to say.
parsers:atPut("DECLARE", { m, st |
    st:kind := 'rem.
    m:cursor := m:tokens:size:add(#1) }).

parsers:atPut("CALL", { m, st |
    st:kind := 'call.
    st:name := m:plainName("CALL").
    st:items := m:nextIs("("):ifElse({ m:parseArguments(true) }, { m:parseArguments(false) }).
    m:expectEndOfLine("CALL") }).

parsers:atPut("RANDOMIZE", { m, st |
    st:kind := 'randomize.
    st:expr := m:parseExpression.
    m:expectEndOfLine("RANDOMIZE") }).

parsers:atPut("DEFINT", { m, st | m:parseDefaults(st, 'integer) }).
parsers:atPut("DEFLNG", { m, st | m:parseDefaults(st, 'integer) }).
parsers:atPut("DEFDBL", { m, st | m:parseDefaults(st, 'double) }).
parsers:atPut("DEFSTR", { m, st | m:parseDefaults(st, 'string) }).

; `DEFINT A-N, X` -- the default type for every name starting with one of those
; letters. It applies to the whole listing wherever it is written, which is one
; fewer rule to remember than QBasic's, where it applies from where it stands.
sola:parseDefaults := { st, t | | more, first, last, i |
    st:kind := 'rem.
    more := true.
    { more }:whileTrue({
        first := self:defLetter.
        last := first.
        self:nextIs("-"):ifTrue({ self:takeToken. last := self:defLetter }).
        i := letters:indexOf(first).
        i:greaterThan(letters:indexOf(last)):ifTrue({
            self:fail("{}-{} is not a range of letters":fill([first, last])) }).
        { i:lessOrEqual(letters:indexOf(last)) }:whileTrue({
            self:defaultTypes:atPut(letters:copyFrom(i, i), t).
            i := i:add(#1) }).
        self:nextIs(","):ifElse({ self:takeToken }, { more := false }) }).
    self:expectEndOfLine("a DEF") }.

sola:defLetter := { | t |
    t := self:takeToken.
    t:isNil:or({ t:kind:equals('word):not }):or({ t:text:size:notEquals(#1) })
        :ifTrue({ self:fail("a DEF names single letters, like A-N") }).
    t:text }.

parsers:atPut("SHARED", { m, st |
    st:kind := 'shared. st:items := m:nameList. m:expectEndOfLine("SHARED") }).

parsers:atPut("STATIC", { m, st |
    st:kind := 'static. st:items := m:nameList. m:expectEndOfLine("STATIC") }).

sola:plainName := { what | | t |
    t := self:takeToken.
    t:isNil:or({ t:kind:equals('word):not }):ifTrue({
        self:fail("{} needs a name":fill([what])) }).
    parsers:includes(t:text):or({ builtins:includes(t:text) }):ifTrue({
        self:fail("'{}' is already a keyword or a supplied function"
            :fill([t:text])) }).
    t:text }.

sola:nameList := { | names, more |
    names := array:new.
    more := true.
    { more }:whileTrue({
        names:add(self:plainName("this")).
        self:nextIs(","):ifElse({ self:takeToken }, { more := false }) }).
    names }.

; A parameter list, in brackets or not -- `SUB Greet (name)` and `SUB Greet name`
; are the same declaration, as they are in QBasic.
sola:parseParameters := { | names, more, bracketed |
    names := array:new.
    bracketed := self:nextIs("(").
    bracketed:ifTrue({ self:takeToken }).
    self:atEndOfLine:not:and({ self:nextIs(")"):not }):ifTrue({
        more := true.
        { more }:whileTrue({
            names:add(self:plainName("a parameter")).
            self:nextIs(","):ifElse({ self:takeToken }, { more := false }) }) }).
    bracketed:ifTrue({
        self:nextIs(")"):ifFalse({ self:fail("a '(' was never closed") }).
        self:takeToken }).
    names }.

; The arguments of a statement call.
;
; **Only `CALL`'s brackets are an argument list.** Written without `CALL`, a
; leading `(` belongs to the first argument instead, so `Double (n)` passes a
; *copy* of `n` where `CALL Double(n)` passes `n` itself. That reads like a
; quibble and is the whole of how QBasic spells by-value, so it is kept.
sola:parseArguments := { bracketed | | args, more |
    args := array:new.
    bracketed:ifTrue({
        self:nextIs("("):ifFalse({ self:fail("CALL needs brackets round its arguments") }).
        self:takeToken }).
    self:atEndOfLine:not:and({ self:nextIs(")"):not }):ifTrue({
        more := true.
        { more }:whileTrue({
            args:add(self:parseExpression).
            self:nextIs(","):ifElse({ self:takeToken }, { more := false }) }) }).
    bracketed:ifTrue({
        self:nextIs(")"):ifFalse({ self:fail("a '(' was never closed") }).
        self:takeToken }).
    args }.

; The arguments of a call inside an expression, where they are not optional.
sola:parseCallArguments := { | args, more |
    self:takeToken.
    args := array:new.
    self:nextIs(")"):ifFalse({
        more := true.
        { more }:whileTrue({
            args:add(self:parseExpression).
            self:nextIs(","):ifElse({ self:takeToken }, { more := false }) }) }).
    self:nextIs(")"):ifFalse({ self:fail("a '(' was never closed") }).
    self:takeToken.
    args }.

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

; Ten levels, loosest first, which is BASIC's table:
;
;     OR XOR
;     AND
;     NOT              (unary)
;     = <> < <= > >=
;     + -
;     MOD
;     \\
;     * /
;     -                (unary)
;     ^                (right-associative, and tighter than unary minus, so
;                       -2 ^ 2 is -(2 ^ 2) and not (-2) ^ 2)

sola:parseExpression := { self:parseOr }.

sola:parseOr := { | left, op |
    left := self:parseAnd.
    { self:peekToken:notNil:and({
        ["OR", "XOR"]:indexOf(self:peekToken:text):notNil }) }:whileTrue({
        op := self:takeToken:text.
        left := binaryNode:value(op, left, self:parseAnd) }).
    left }.

sola:parseAnd := { | left |
    left := self:parseNot.
    { self:nextIs("AND") }:whileTrue({
        self:takeToken.
        left := binaryNode:value("AND", left, self:parseNot) }).
    left }.

sola:parseNot := {
    self:nextIs("NOT"):ifElse(
        { self:takeToken. notNode:value(self:parseNot) },
        { self:parseComparison }) }.

sola:parseComparison := { | left, op |
    left := self:parseAdditive.
    { self:peekToken:notNil:and({
        comparisons:indexOf(self:peekToken:text):notNil }) }:whileTrue({
        op := self:takeToken:text.
        left := binaryNode:value(op, left, self:parseAdditive) }).
    left }.

sola:parseAdditive := { | left, op |
    left := self:parseMod.
    { self:peekToken:notNil:and({
        additive:indexOf(self:peekToken:text):notNil }) }:whileTrue({
        op := self:takeToken:text.
        left := binaryNode:value(op, left, self:parseMod) }).
    left }.

sola:parseMod := { | left |
    left := self:parseIntegerDivide.
    { self:nextIs("MOD") }:whileTrue({
        self:takeToken.
        left := binaryNode:value("MOD", left, self:parseIntegerDivide) }).
    left }.

sola:parseIntegerDivide := { | left |
    left := self:parseMultiplicative.
    { self:nextIs("\\") }:whileTrue({
        self:takeToken.
        left := binaryNode:value("\\", left, self:parseMultiplicative) }).
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
        { self:parsePower }) }.

sola:parsePower := { | base |
    base := self:parsePrimary.
    self:nextIs("^"):ifElse(
        { self:takeToken. binaryNode:value("^", base, self:parseUnary) },
        { base }) }.

sola:parsePrimary := { | t, inner |
    t := self:takeToken.
    t:isNil:ifTrue({ self:fail("an expression stops short") }).
    [ { t:kind:equals('number) },
        ; **A literal with no point and no exponent is an Integer**, which is
        ; QBasic's rule and the reason `7 / 2` and `7 \\ 2` differ without
        ; anything being declared.
        { t:text:indexOf("."):isNil
            :and({ t:text:asUppercase:indexOf("E"):isNil }):ifElse(
            { numberNode:value(t:text:asInteger, 'integer) },
            { numberNode:value(t:text:asFloat, 'double) }) },
      { t:kind:equals('based) }, { numberNode:value(t:text:asInteger, 'integer) },
      { t:kind:equals('string) }, { stringNode:value(t:text) },
      { t:text:equals("(") },
        { inner := self:parseExpression.
          self:nextIs(")"):ifFalse({ self:fail("a '(' was never closed") }).
          self:takeToken.
          inner:grouped := true.
          inner },
      { t:kind:equals('word) },
        { self:nextIs("("):ifElse(
            { callNode:value(t:text, self:parseCallArguments) },
            { variableNode:value(t:text) }) },
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
sola:emitNil    := { self:byte(NIL) }.

; An **integer** constant, which this language has only one use for: the
; subscript of a one-element array, which is what a variable passed by
; reference is kept in. Everything a SolaBasic program computes is a Double.
sola:emitIntConst := { n | self:byte(CONST). self:u16(self:constFor(#1, n)) }.

; A numeric constant of whichever type is wanted. `#0` and `0.0` are two
; constants and two types, and pushing the wrong one is a program that runs and
; is wrong -- the trap experiment/compile.sol names in ideas.md.
; The same number as a Double, whichever it arrived as. The compiler holds a
; literal step as whatever the listing wrote, and `#1` and `1.0` are two types
; that do not compare with each other.
sola:asDouble := { v | v:respondsTo('asFloat):ifElse({ v:asFloat }, { v }) }.

sola:emitZero := { t |
    t:equals('string):ifElse({ self:emitString("") }, { self:emitNumber(#0, t) }) }.

sola:emitNumber := { v, t |
    t:equals('integer):ifElse(
        { self:emitIntConst(v:respondsTo('rounded):ifElse({ v:rounded }, { v })) },
        { self:emitConst(self:asDouble(v)) }) }.

; A frame slot. `u8`, because a frame of more than 255 slots is refused before
; it runs and the format says so by giving the operand one byte.
sola:emitLocal    := { slot | self:byte(LOCAL).    self:byte(slot) }.
sola:emitSetLocal := { slot | self:byte(SETLOCAL). self:byte(slot) }.

; ---------------------------------------------------------------------------
; A place to put a value that is needed twice
;
; There is no instruction that duplicates the top of the stack, so anything
; wanting its argument twice -- `SGN`, `MOD`, `INSTR` -- has to put it
; somewhere. A scratch slot is that somewhere, handed out by nesting depth so
; that `SGN(SGN(x))` gets two and two uses in a row share one.

sola:takeScratch := { | slot |
    self:scratchDepth := self:scratchDepth:add(#1).
    self:scratchSlots:size:lessThan(self:scratchDepth):ifTrue({
        self:scratchSlots:add(self:newSlot("scratch")) }).
    self:scratchSlots:at(self:scratchDepth) }.

sola:dropScratch := { self:scratchDepth := self:scratchDepth:sub(#1) }.

; Evaluate something into a scratch slot and leave nothing on the stack.
sola:intoScratchAs := { node, wanted | | slot |
    slot := self:takeScratch.
    self:emitTyped(node, wanted).
    self:emitSetLocal(slot).
    self:emitPop.
    slot }.

; ---------------------------------------------------------------------------
; Types
;
; **A name carries its type.** A suffix says it outright; otherwise the `DEF`
; ranges decide by first letter; otherwise it is a Double. `A%` and `A$` are two
; variables and not one, which is QBasic's rule.

sola:defaultTypes := nil.

sola:typeOfName := { name | | last |
    last := name:copyFrom(name:size, name:size).
    suffixTypes:includes(last):ifElse(
        { suffixTypes:at(last) },
        { self:defaultTypes:at(name:copyFrom(#1, #1), 'double) }) }.

sola:isNumeric := { t | t:notEquals('string) }.

sola:unify := { a, b, where |
    a:equals('string):or({ b:equals('string) }):ifTrue({
        a:equals(b):ifFalse({
            self:fail("{} cannot mix text and numbers":fill([where])) }).
        'string:equals('string) }).
    a:equals('string):ifElse(
        { 'string },
        { a:equals('double):or({ b:equals('double) })
            :or({ a:equals('boolean) }):or({ b:equals('boolean) })
            :ifElse({ 'double }, { 'integer }) }) }.

; ---------------------------------------------------------------------------
; Typing the tree
;
; **This happens before a single byte is emitted, and it has to.** A conversion
; is an instruction that acts on the top of the stack, so turning an Integer into
; a Double must be emitted *after* that Integer is pushed and *before* the value
; beside it -- and by then it is far too late to work out that it was needed. So
; every node learns its type first, and emitting is then a walk that already
; knows where the conversions go.

sola:typeExpression := { n |
    n:kind:equals('number):ifTrue({ n:type }).
    n:kind:equals('string):ifTrue({ n:type := 'string }).
    n:kind:equals('variable):ifTrue({ n:type := self:typeOfName(n:name) }).
    n:kind:equals('call):ifTrue({
        n:args:do({ a | self:typeExpression(a) }).
        n:type := self:typeOfCall(n) }).
    n:kind:equals('negate):ifTrue({
        self:typeExpression(n:left).
        n:left:type:equals('string):ifTrue({ self:fail("text cannot be negated") }).
        n:operandType := n:left:type:equals('boolean):ifElse({ 'integer }, { n:left:type }).
        n:type := n:operandType }).
    n:kind:equals('not):ifTrue({
        self:typeExpression(n:left).
        n:left:type:equals('string):ifTrue({ self:fail("NOT wants a number") }).
        n:operandType := 'integer.
        n:type := 'integer }).
    n:kind:equals('binary):ifTrue({ self:typeBinary(n) }).
    n:type }.

sola:typeBinary := { n | | left, right |
    left := self:typeExpression(n:left).
    right := self:typeExpression(n:right).

    [ { comparisons:indexOf(n:op):notNil },
        { n:operandType := self:unify(left, right, "a comparison").
          n:type := 'boolean },
      { bitwise:indexOf(n:op):notNil },
        { n:operandType := 'integer. n:type := 'integer },
      { n:op:equals("+") },
        { n:operandType := self:unify(left, right, "'+'").
          n:type := n:operandType },
      { n:op:equals("/") },   { n:operandType := 'double.  n:type := 'double },
      { n:op:equals("^") },   { n:operandType := 'double.  n:type := 'double },
      { n:op:equals("\\") }, { n:operandType := 'integer. n:type := 'integer },
      { n:op:equals("MOD") }, { n:operandType := 'integer. n:type := 'integer },
        { n:operandType := self:unify(left, right, "arithmetic").
          n:operandType:equals('string):ifTrue({
              self:fail("text cannot be used with '{}'":fill([n:op])) }).
          n:type := n:operandType } ]:ifElseIf.
    n:type }.

; ---------------------------------------------------------------------------
; Conversions

sola:coerce := { from, to |
    from:equals(to):ifFalse({
        [ { to:equals('string) },
            { from:equals('boolean):ifTrue({ self:materialise('integer) }).
              self:emitSend("asString", #0) },
          { from:equals('string) },
            { self:fail("text cannot be used as a number here -- VAL reads one out of it") },
          { to:equals('boolean) },
            { from:equals('integer):ifElse({ self:emitIntConst(#0) }, { self:emitConst(0.0) }).
              self:emitSend("notEquals", #1) },
          { from:equals('boolean) }, { self:materialise(to) },
          { to:equals('double) },    { self:emitSend("asFloat", #0) },
                                     { self:emitSend("rounded", #0) } ]:ifElseIf }) }.

; **A comparison is `-1` or `0` when it is used as a number**, which is BASIC's
; rule and the reason there is no boolean type in the language. It costs a jump,
; so it is emitted only where the value really is used as a number -- never for
; a condition, which wants the machine's boolean as it stands.
sola:materialise := { to | | zero, done |
    zero := self:branchHole.
    to:equals('integer):ifElse({ self:emitIntConst(#-1) }, { self:emitConst(-1.0) }).
    done := self:hole.
    self:fillBranch(zero).
    to:equals('integer):ifElse({ self:emitIntConst(#0) }, { self:emitConst(0.0) }).
    self:fillJump(done) }.

; Emit a node and leave a value of the wanted type on the stack.
sola:emitTyped := { n, wanted |
    self:emitExpression(n).
    self:coerce(n:type, wanted) }.
;
; Slot 0 is the receiver -- `self` inside a block, and unused in the script,
; which has none. Everything after it is a parameter, a local, or a temporary
; this compiler needed somewhere to put.
;
; **The temporaries are slots and not hidden globals**, and that is a
; correctness matter rather than tidiness. A `FOR` keeps its limit and its step
; somewhere for the life of the loop; if that somewhere were a global, a
; recursive `FUNCTION` containing a `FOR` would have its inner call overwrite
; the outer call's limit. A slot is per-frame, so each call has its own.

sola:newSlot := { name | | slot |
    slot := self:localNames:size.
    slot:greaterThan(#255):ifTrue({
        self:fail("more than 255 names in one procedure, which is a frame the machine will not make") }).
    self:localNames:add(name).
    slot }.

sola:newLocal := { name | | slot |
    slot := self:newSlot(name).
    self:locals:atPut(name, slot).
    slot }.

sola:slotFor := { name |
    self:locals:includes(name):ifElse(
        { self:locals:at(name) },
        { self:newLocal(name) }) }.

; ---------------------------------------------------------------------------
; Where a name lives
;
; Inside a procedure a name is a slot unless `SHARED` sent it back to the module
; or `STATIC` gave it a private global; at module level everything is a global.

sola:isLocalName := { name |
    self:inProcedure:and({ self:shared:indexOf(name):isNil })
        :and({ self:statics:includes(name):not }) }.

sola:globalNameFor := { name |
    self:statics:includes(name):ifElse(
        { self:statics:at(name) }, { name }) }.

; The variable itself, without looking inside it -- which is what a boxed one
; wants when it is being assigned to or passed on by reference.
sola:emitRawVar := { name |
    self:isLocalName(name):ifElse(
        { self:emitLocal(self:slotFor(name)) },
        { self:emitGlobal(self:globalNameFor(name)) }) }.

; ---------------------------------------------------------------------------
; A variable passed by reference lives in a box
;
; **The box is a one-element array, and the variable *is* the box** rather than
; being wrapped at the call and unwrapped after it. That is the whole of the
; by-reference machinery, and choosing it this way is what kept it small:
; passing `a` to a by-reference parameter passes the array, the callee's
; `at(#1)` and `atPut(#1, v)` reach the caller's storage directly, and there is
; no copy back, no temporary to keep alive across the call, and nothing to get
; wrong when the call is recursive.
;
; The cost is one send on every read and every write of a boxed variable, and it
; is paid only by variables that are actually passed by reference somewhere.

sola:isBoxed := { name | self:boxed:indexOf(name):notNil }.

sola:emitLoadVar := { name |
    self:emitRawVar(name).
    self:isBoxed(name):ifTrue({
        self:emitIntConst(#1).
        self:emitSend("at", #1) }) }.

; An assignment is emitted in two halves, because a boxed one puts the box and
; its subscript *before* the value and an ordinary one puts the name after it.
sola:beginAssign := { name |
    self:isBoxed(name):ifTrue({
        self:emitRawVar(name).
        self:emitIntConst(#1) }) }.

sola:endAssign := { name |
    self:isBoxed(name):ifElse(
        { self:emitSend("atPut", #2) },
        { self:isLocalName(name):ifElse(
            { self:emitSetLocal(self:slotFor(name)) },
            { self:emitStore(self:globalNameFor(name)) }) }).
    self:emitPop }.

; ---------------------------------------------------------------------------
; Every variable starts at nought
;
; **That is BASIC's rule and it has to be done rather than assumed**: a global
; this compiler never stored into is an *undefined name* to the machine, not a
; zero, and `PRINT Z` would be an error where every BASIC ever written prints
; ` 0 `. So the names a scope mentions are collected and given their nought
; before its first line runs.
;
; Skipped: parameters, which arrive with values; a FUNCTION's own name, which is
; set up as its answer; anything `SHARED`, which belongs to the module and would
; be wiped by initialising it again on every call; anything `STATIC`, which is
; initialised once at module level and would stop surviving if it were done
; here; and anything boxed, which gets its nought inside its box below.

sola:emitVariableInitialisers := { skip |
    self:variablesIn(self:statementsOfScope):do({ name |
        skip:indexOf(name):isNil
            :and({ self:shared:indexOf(name):isNil })
            :and({ self:statics:includes(name):not })
            :and({ self:isBoxed(name):not }):ifTrue({
            self:emitZero(self:typeOfName(name)).
            self:isLocalName(name):ifElse(
                { self:emitSetLocal(self:slotFor(name)) },
                { self:emitStore(self:globalNameFor(name)) }).
            self:emitPop }) }) }.

sola:statementsOfScope := nil.

; Every name a body uses as a variable, in the order it first appears.
sola:variablesIn := { body | | names |
    names := array:new.
    body:do({ st | self:variablesInStatement(st, names) }).
    names }.

sola:noteName := { names, name |
    names:indexOf(name):isNil:ifTrue({ names:add(name) }) }.

sola:variablesInStatement := { st, names |
    ['let, 'for]:indexOf(st:kind):notNil:ifTrue({ self:noteName(names, st:name) }).
    ['print, 'call]:indexOf(st:kind):notNil:ifTrue({
        st:items:do({ a | self:variablesInExpression(a, names) }) }).
    self:variablesInExpression(st:expr, names).
    self:variablesInExpression(st:limit, names).
    self:variablesInExpression(st:step, names).
    st:alternatives:notNil:ifTrue({
        st:alternatives:do({ alt |
            alt:at(#1):equals("is"):ifElse(
                { self:variablesInExpression(alt:at(#3), names) },
                { self:variablesInExpression(alt:at(#2), names).
                  alt:at(#1):equals("range"):ifTrue({
                      self:variablesInExpression(alt:at(#3), names) }) }) }) }).
    st:then:notNil:ifTrue({ self:variablesInStatement(st:then, names) }).
    st:otherwise:notNil:ifTrue({ self:variablesInStatement(st:otherwise, names) }) }.

sola:variablesInExpression := { n, names |
    n:isNil:ifFalse({
        n:kind:equals('variable):ifTrue({ self:noteName(names, n:name) }).
        n:kind:equals('call):ifTrue({
            n:args:do({ a | self:variablesInExpression(a, names) }) }).
        self:variablesInExpression(n:left, names).
        self:variablesInExpression(n:right, names) }) }.

; Every boxed name is given its box before anything runs, because the first
; thing that happens to it may be a call that assigns through it.
sola:emitBoxes := {
    self:toBox:do({ name |
        self:emitGlobal("array").
        self:emitZero(self:typeOfName(name)).
        self:emitSend("of", #1).
        self:isLocalName(name):ifElse(
            { self:emitSetLocal(self:slotFor(name)) },
            { self:emitStore(self:globalNameFor(name)) }).
        self:emitPop }) }.

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
    [ { n:kind:equals('number) },
        { n:type:equals('integer):ifElse(
            { self:emitIntConst(n:value) }, { self:emitConst(n:value) }) },
      { n:kind:equals('string) },   { self:emitString(n:value) },
      { n:kind:equals('variable) }, { self:emitLoadVar(n:name) },
      { n:kind:equals('call) },     { self:emitCall(n:name, n:args, false) },
      { n:kind:equals('negate) },
        { self:emitTyped(n:left, n:operandType). self:emitSend("negated", #0) },
      { n:kind:equals('not) },
        { self:emitTyped(n:left, 'integer). self:emitSend("bitNot", #0) },
        { self:emitBinary(n) } ]:ifElseIf }.

sola:emitBinary := { n |
    [ { n:op:equals("MOD") }, { self:emitModulo(n) },
      { n:op:equals("\\") },  { self:emitIntegerDivide(n) },
      { n:op:equals("^") },
        { self:emitTyped(n:left, 'double).
          self:emitTyped(n:right, 'double).
          self:emitSend("pow", #1) },
      { n:op:equals("+"):and({ n:operandType:equals('string) }) },
        { self:emitTyped(n:left, 'string).
          self:emitTyped(n:right, 'string).
          self:emitSend("concat", #1) },
        { self:emitTyped(n:left, n:operandType).
          self:emitTyped(n:right, n:operandType).
          self:emitSend(selectors:at(n:op), #1) } ]:ifElseIf }.

; **`\\` truncates towards nought and so does `MOD`'s remainder**, which is
; QBasic's rule and *not* the machine's: SolVM's integer `div` and `mod` are
; floored, so `-7 \\ 2` would be `-4` where QBasic says `-3`. Going through the
; float divide and `truncated` gets the sign right. What it costs is exactness
; above 2^53, where a double can no longer hold every integer -- which is a
; smaller wrong answer than the sign being wrong, and is written down rather
; than left to be found.
sola:emitIntegerDivide := { n |
    self:emitTyped(n:left, 'integer).  self:emitSend("asFloat", #0).
    self:emitTyped(n:right, 'integer). self:emitSend("asFloat", #0).
    self:emitSend("div", #1).
    self:emitSend("truncated", #0) }.

; `a - (a \\ b) * b`, which needs `a` and `b` twice each and so needs somewhere
; to put them: there is no instruction that duplicates the top of the stack.
sola:emitModulo := { n | | a, b |
    a := self:intoScratchAs(n:left, 'integer).
    b := self:intoScratchAs(n:right, 'integer).
    self:emitLocal(a).
    self:emitLocal(a). self:emitSend("asFloat", #0).
    self:emitLocal(b). self:emitSend("asFloat", #0).
    self:emitSend("div", #1).
    self:emitSend("truncated", #0).
    self:emitLocal(b).
    self:emitSend("mul", #1).
    self:emitSend("sub", #1).
    self:dropScratch.
    self:dropScratch }.

; ---------------------------------------------------------------------------
; Statements, into instructions
;
; **Every one of these leaves the stack exactly as it found it**, at depth 0,
; and that is not tidiness -- it is what makes a label a merge point the
; verifier accepts from any number of jumps. An assignment leaves its value
; behind (all four of the machine's stores do, so that `c := b := #45` falls
; out) and the `POP` here is what discards it.

emitters := dictionary:new.

sola:emitStatement := { st |
    self:atLine := st:line.
    self:mark(st:line).
    st:label:notNil:ifTrue({
        self:labelAt:includes(st:label):ifTrue({
            self:fail("the label '{}' is used twice":fill([st:label])) }).
        self:labelAt:atPut(st:label, self:here) }).
    self:guardSelect(st:kind).
    self:typeStatement(st).
    emitters:at(st:kind):value(self, st) }.

; Everything in one statement, typed before any of it is emitted.
sola:typeStatement := { st |
    ['print, 'call]:indexOf(st:kind):notNil:ifTrue({
        st:items:do({ a | self:typeExpression(a) }) }).
    st:expr:notNil:ifTrue({ self:typeExpression(st:expr) }).
    st:limit:notNil:ifTrue({ self:typeExpression(st:limit) }).
    st:step:notNil:ifTrue({ self:typeExpression(st:step) }).
    st:alternatives:notNil:ifTrue({
        st:alternatives:do({ alt |
            alt:at(#1):equals("is"):ifElse(
                { self:typeExpression(alt:at(#3)) },
                { self:typeExpression(alt:at(#2)).
                  alt:at(#1):equals("range"):ifTrue({
                      self:typeExpression(alt:at(#3)) }) }) }) }).
    st:then:notNil:ifTrue({ self:typeStatement(st:then) }).
    st:otherwise:notNil:ifTrue({ self:typeStatement(st:otherwise) }) }.

emitters:atPut('rem, { m, st | nil }).
emitters:atPut('end, { m, st | m:byte(HALT) }).
emitters:atPut('goto, { m, st | m:emitJump(st:target) }).
emitters:atPut('print, { m, st | m:emitPrint(st) }).
emitters:atPut('let, { m, st |
    m:beginAssign(st:name).
    m:emitTyped(st:expr, m:typeOfName(st:name)).
    m:endAssign(st:name) }).

; ---------------------------------------------------------------------------
; Holes
;
; A forward jump is emitted before its target exists, so a hole goes down and
; the frame that owns it remembers where. Two shapes, because two instructions:
; a three-byte `OP_JUMP` and a five-byte `OP_JUMP_IF_FALSE`, whose offset sits
; behind its opcode and in front of the selector name it carries.
;
; **Every hole here is forward.** Backward jumps in these constructs go to a
; place already emitted, so they are written out complete and need no hole at
; all -- which is the difference between a block and a `GOTO`, where the
; direction is not known until the label turns up.

sola:hole := { | at |
    at := self:here. self:byte(#0). self:byte(#0). self:byte(#0). at }.

sola:branchHole := { | at |
    at := self:here.
    self:byte(JMPF). self:u16(#0). self:u16(self:nameFor("ifTrue")).
    at }.

sola:fillJump := { at | self:patchJump(at, JUMP, self:here:sub(at:add(#3))) }.

sola:fillBranch := { at | | offset |
    offset := self:here:sub(at:add(#5)).
    offset:greaterThan(jumpLimit):ifTrue({
        self:fail("a branch of {} bytes: no jump reaches further than {}"
            :fill([offset, jumpLimit])) }).
    self:code:atPut(at:add(#2), offset:bitAnd(#255)).
    self:code:atPut(at:add(#3), offset:shiftRight(#8):bitAnd(#255)) }.

sola:fillAll := { holes |
    holes:do({ h |
        h:at(#2):equals('branch):ifElse(
            { self:fillBranch(h:at(#1)) },
            { self:fillJump(h:at(#1)) }) }) }.

sola:emitLoopTo := { target | | offset |
    offset := self:here:add(#3):sub(target).
    offset:greaterThan(jumpLimit):ifTrue({
        self:fail("a loop of {} bytes: no jump reaches further than {}"
            :fill([offset, jumpLimit])) }).
    self:byte(LOOP).
    self:byte(offset:bitAnd(#255)).
    self:byte(offset:shiftRight(#8):bitAnd(#255)) }.

; ---------------------------------------------------------------------------
; The stack of open blocks

sola:blocks := nil.
sola:forCount := #0.
sola:selectCount := #0.

; ---------------------------------------------------------------------------
; A unit is a chunk being built
;
; A `SUB` compiles to a chunk of its own, held in the module's method table, and
; a chunk owns everything: its code, its own name and constant tables, its own
; frame, its own labels. So the compiler's state is pushed and restored around
; each one rather than being threaded through every routine as an argument.
;
; **Labels are per-unit, which is the language's rule and not an accident of
; this.** SolaBasic says a `GOTO` may not cross between module level and a
; procedure, and it could not if it wanted to: a jump is an offset inside one
; chunk and there is no instruction that leaves a frame and lands somewhere.

sola:localNames := nil.
sola:locals := nil.
sola:varTypes := nil.
sola:scratchSlots := nil.
sola:scratchDepth := #0.
sola:shared := nil.
sola:statics := nil.
sola:boxed := nil.
sola:toBox := nil.
sola:methods := nil.
sola:inProcedure := false.
sola:returnName := "".
sola:unitStack := nil.

sola:pushUnit := { | saved |
    saved := dictionary:new.
    saved:atPut("code", self:code).             saved:atPut("names", self:names).
    saved:atPut("nameIndex", self:nameIndex).   saved:atPut("constants", self:constants).
    saved:atPut("constIndex", self:constIndex). saved:atPut("lineMarks", self:lineMarks).
    saved:atPut("labelAt", self:labelAt).       saved:atPut("fixups", self:fixups).
    saved:atPut("blocks", self:blocks).         saved:atPut("localNames", self:localNames).
    saved:atPut("locals", self:locals).         saved:atPut("shared", self:shared).
    saved:atPut("varTypes", self:varTypes).
    saved:atPut("scratchSlots", self:scratchSlots).
    saved:atPut("scratchDepth", self:scratchDepth).
    saved:atPut("statics", self:statics).       saved:atPut("boxed", self:boxed).
    saved:atPut("toBox", self:toBox).           saved:atPut("methods", self:methods).
    saved:atPut("inProcedure", self:inProcedure).
    saved:atPut("returnName", self:returnName).
    self:unitStack:add(saved).
    self:freshUnit }.

sola:freshUnit := {
    self:code := array:new.        self:names := array:new.
    self:nameIndex := dictionary:new.
    self:constants := array:new.   self:constIndex := dictionary:new.
    self:lineMarks := array:new.   self:labelAt := dictionary:new.
    self:fixups := array:new.      self:blocks := array:new.
    self:localNames := array:new.  self:locals := dictionary:new.
    self:varTypes := dictionary:new.
    self:scratchSlots := array:new. self:scratchDepth := #0.
    self:shared := array:new.      self:statics := dictionary:new.
    self:boxed := array:new.       self:toBox := array:new.
    self:methods := array:new.
    self:inProcedure := false.     self:returnName := "".
    self:newSlot("") }.

sola:popUnit := { | saved |
    saved := self:unitStack:removeLast.
    self:code := saved:at("code").             self:names := saved:at("names").
    self:nameIndex := saved:at("nameIndex").   self:constants := saved:at("constants").
    self:constIndex := saved:at("constIndex"). self:lineMarks := saved:at("lineMarks").
    self:labelAt := saved:at("labelAt").       self:fixups := saved:at("fixups").
    self:blocks := saved:at("blocks").         self:localNames := saved:at("localNames").
    self:locals := saved:at("locals").         self:shared := saved:at("shared").
    self:varTypes := saved:at("varTypes").
    self:scratchSlots := saved:at("scratchSlots").
    self:scratchDepth := saved:at("scratchDepth").
    self:statics := saved:at("statics").       self:boxed := saved:at("boxed").
    self:toBox := saved:at("toBox").           self:methods := saved:at("methods").
    self:inProcedure := saved:at("inProcedure").
    self:returnName := saved:at("returnName") }.

; The chunk the current unit has become. Everything a `.sob` wants about one
; chunk, and the same shape whether it is the script or a procedure.
sola:chunkOfUnit := { | chunk |
    self:resolveJumps.
    chunk := dictionary:new.
    chunk:atPut("slots", self:localNames:size).
    chunk:atPut("names", self:names).
    chunk:atPut("constants", self:constants).
    chunk:atPut("code", self:code).
    chunk:atPut("lines", self:lineRuns).
    chunk:atPut("files", [self:path]).
    chunk:atPut("fileRuns", [[self:code:size, #0]]).
    chunk:atPut("slotNames", self:localNames).
    chunk:atPut("methods", self:methods).
    chunk }.

sola:pushBlock := { kind | | f |
    f := makeFrame:value(kind, self:atLine).
    self:blocks:add(f).
    f }.

sola:innermost := {
    self:blocks:size:equals(#0):ifElse(
        { nil }, { self:blocks:at(self:blocks:size) }) }.

sola:popBlock := { what | | f |
    f := self:innermost.
    f:isNil:ifTrue({ self:fail("{} with no block open":fill([what])) }).
    self:blocks:removeLast.
    f }.

; The innermost frame of one kind, which is what EXIT looks for.
sola:enclosing := { kind | | found, i |
    found := nil.
    i := self:blocks:size.
    { found:isNil:and({ i:greaterOrEqual(#1) }) }:whileTrue({
        self:blocks:at(i):kind:equals(kind):ifTrue({ found := self:blocks:at(i) }).
        i := i:sub(#1) }).
    found }.

sola:openFrame := { what, kind | | f |
    f := self:innermost.
    f:isNil:or({ f:kind:equals(kind):not }):ifTrue({
        self:fail("{} with no {} open":fill([what, self:openerName(kind)])) }).
    f }.

sola:openerName := { kind |
    [ { kind:equals('if) },     { "IF" },
      { kind:equals('select) }, { "SELECT CASE" },
      { kind:equals('for) },    { "FOR" },
      { kind:equals('do) },     { "DO" },
                                { "WHILE" } ]:ifElseIf }.

sola:closerName := { kind |
    [ { kind:equals('if) },     { "END IF" },
      { kind:equals('select) }, { "END SELECT" },
      { kind:equals('for) },    { "NEXT" },
      { kind:equals('do) },     { "LOOP" },
                                { "WEND" } ]:ifElseIf }.

; **Nothing may sit between SELECT CASE and its first CASE.** There is nowhere
; for it to go: the subject has been stored and the next thing control reaches
; has to be a test. QBasic refuses it and so does this, rather than emitting
; something that runs once and looks deliberate.
sola:guardSelect := { kind | | f |
    f := self:innermost.
    f:notNil:and({ f:kind:equals('select) }):and({ f:top:equals(#0) })
        :and({ ['case, 'caseelse, 'endselect]:indexOf(kind):isNil }):ifTrue({
        self:fail("nothing may come between SELECT CASE and its first CASE") }) }.

; ---------------------------------------------------------------------------
; IF
;
; Each arm's test jumps past its own body when it fails, and each body jumps to
; the end when it is done. `pending` is the one test waiting to be told where
; "past this body" is; `exits` are the bodies waiting to be told where the end
; is. An `IF` with no `ELSE` never fills `exits` at all, because the last test
; falls straight out.

emitters:atPut('ifline, { m, st | | over, past |
    m:emitCondition(st:expr).
    over := m:branchHole.
    m:emitStatement(st:then).
    st:otherwise:isNil:ifElse(
        { m:fillBranch(over) },
        { past := m:hole.
          m:fillBranch(over).
          m:emitStatement(st:otherwise).
          m:fillJump(past) }) }).

emitters:atPut('ifblock, { m, st | | f |
    m:emitCondition(st:expr).
    f := m:pushBlock('if).
    f:pending:add([m:branchHole, 'branch]) }).

emitters:atPut('elseif, { m, st | | f |
    f := m:openFrame("ELSEIF", 'if).
    f:seenElse:ifTrue({ m:fail("ELSEIF after ELSE") }).
    f:exits:add([m:hole, 'jump]).
    m:fillAll(f:pending).
    f:pending := array:new.
    m:emitCondition(st:expr).
    f:pending:add([m:branchHole, 'branch]) }).

emitters:atPut('else, { m, st | | f |
    f := m:openFrame("ELSE", 'if).
    f:seenElse:ifTrue({ m:fail("ELSE twice in one IF") }).
    f:exits:add([m:hole, 'jump]).
    m:fillAll(f:pending).
    f:pending := array:new.
    f:seenElse := true }).

emitters:atPut('endif, { m, st | | f |
    f := m:openFrame("END IF", 'if).
    m:popBlock("END IF").
    m:fillAll(f:pending).
    m:fillAll(f:exits) }).

; ---------------------------------------------------------------------------
; SELECT CASE
;
; The subject goes into a global of its own, named with a space in it so that
; nothing a BASIC program can spell will collide with it -- the tokeniser cannot
; produce such a name, which makes the guarantee structural rather than a
; convention about prefixes.

emitters:atPut('select, { m, st | | f, slot |
    m:emitExpression(st:expr).
    slot := m:newSlot("select subject").
    m:emitSetLocal(slot).
    m:emitPop.
    f := m:pushBlock('select).
    f:subject := slot.
    f:subjectType := st:expr:type }).

emitters:atPut('case, { m, st | | f, count, i, misses, toBody |
    f := m:openFrame("CASE", 'select).
    f:seenElse:ifTrue({ m:fail("CASE after CASE ELSE") }).
    m:closeCaseArm(f).

    ; Alternatives are an OR: the first that matches runs the body, and only
    ; when the last one fails does control go on to the next CASE. So every
    ; alternative but the last needs a jump *to* the body, and its failures land
    ; on the alternative after it.
    count := st:alternatives:size.
    toBody := array:new.
    i := #1.
    { i:lessOrEqual(count) }:whileTrue({
        misses := m:emitAlternative(f:subject, f:subjectType,
                                    st:alternatives:at(i)).
        i:equals(count):ifElse(
            { misses:do({ at | f:pending:add([at, 'branch]) }) },
            { toBody:add([m:hole, 'jump]).
              misses:do({ at | m:fillBranch(at) }) }).
        i := i:add(#1) }).
    m:fillAll(toBody) }).

emitters:atPut('caseelse, { m, st | | f |
    f := m:openFrame("CASE ELSE", 'select).
    f:seenElse:ifTrue({ m:fail("CASE ELSE twice in one SELECT") }).
    m:closeCaseArm(f).
    f:seenElse := true }).

; The arm before this one, if there was one, leaves; and the test that sent
; control here is told where here is.
sola:closeCaseArm := { f |
    f:top:notEquals(#0):ifTrue({ f:exits:add([self:hole, 'jump]) }).
    self:fillAll(f:pending).
    f:pending := array:new.
    f:top := #1 }.

emitters:atPut('endselect, { m, st | | f |
    f := m:openFrame("END SELECT", 'select).
    m:popBlock("END SELECT").
    f:top:equals(#0):ifTrue({ m:fail("SELECT CASE with no CASE in it") }).
    m:fillAll(f:pending).
    m:fillAll(f:exits) }).

; A value, a range, or a comparison. Answers the holes to fill when it does
; **not** match -- a range is two of them, because it is an AND and either half
; can refuse.
sola:emitAlternative := { slot, t, alt | | misses |
    misses := array:new.
    alt:at(#1):equals("value"):ifTrue({
        self:emitLocal(slot).
        self:emitTyped(alt:at(#2), t).
        self:emitSend("equals", #1).
        misses:add(self:branchHole) }).
    alt:at(#1):equals("range"):ifTrue({
        self:emitLocal(slot).
        self:emitTyped(alt:at(#2), t).
        self:emitSend("greaterOrEqual", #1).
        misses:add(self:branchHole).
        self:emitLocal(slot).
        self:emitTyped(alt:at(#3), t).
        self:emitSend("lessOrEqual", #1).
        misses:add(self:branchHole) }).
    alt:at(#1):equals("is"):ifTrue({
        self:emitLocal(slot).
        self:emitTyped(alt:at(#3), t).
        self:emitSend(selectors:at(alt:at(#2)), #1).
        misses:add(self:branchHole) }).
    misses }.

; ---------------------------------------------------------------------------
; FOR
;
; The counter is an ordinary global, because that is what a BASIC loop variable
; is: readable after the loop and assignable inside it. The limit and the step
; are globals too, named the way the SELECT subject is, because they are
; evaluated once and the body may change what they were computed from.

; **A written-out step fixes the direction at compile time**, which is worth the
; ten lines because it is nearly every loop: `FOR I = 1 TO 10` and
; `FOR I = 10 TO 1 STEP -1` both know which way they run before they start.
sola:literalStep := { n |
    n:isNil:ifElse(
        { 1.0 },
        { n:kind:equals('number):ifElse(
            { self:asDouble(n:value) },
            { n:kind:equals('negate):and({ n:left:kind:equals('number) }):ifElse(
                { self:asDouble(n:left:value):negated },
                { nil }) }) }) }.

emitters:atPut('for, { m, st | | f, step, t |
    t := m:typeOfName(st:name).
    t:equals('string):ifTrue({ m:fail("a FOR counts, so its variable is a number") }).
    m:beginAssign(st:name). m:emitTyped(st:expr, t). m:endAssign(st:name).

    f := m:pushBlock('for).
    f:name := st:name.
    f:varType := t.
    f:limitSlot := m:newSlot("for limit").
    m:emitTyped(st:limit, t). m:emitSetLocal(f:limitSlot). m:emitPop.

    step := m:literalStep(st:step).
    f:step := step.
    step:isNil:ifTrue({
        f:stepSlot := m:newSlot("for step").
        m:emitTyped(st:step, t). m:emitSetLocal(f:stepSlot). m:emitPop }).

    f:top := m:here.
    m:emitForTest(f).
    f:pending:add([m:branchHole, 'branch]) }).

; **The test is before the body**, so a loop whose range is already empty runs
; no times, which is the standard's rule and the one people rely on.
;
; When the step is not a literal its sign is not known until the loop starts, so
; neither is which comparison to make. Rather than emit both and pick at run
; time, the test becomes `(limit - counter) * step >= 0`, which is `<=` when the
; step is positive and `>=` when it is negative, and runs forever on a step of
; nought exactly as BASIC does. **Where this is not exact** is a product that
; underflows to `-0.0`, which compares as `>= 0` and buys one extra iteration;
; a literal step never takes this path, so it is reachable only from
; `STEP <expression>`.
sola:emitForTest := { f |
    f:step:isNil:ifElse(
        { self:emitLocal(f:limitSlot).
          self:emitLoadVar(f:name).
          self:emitSend("sub", #1).
          self:emitLocal(f:stepSlot).
          self:emitSend("mul", #1).
          self:emitNumber(#0, f:varType).
          self:emitSend("greaterOrEqual", #1) },
        { self:emitLoadVar(f:name).
          self:emitLocal(f:limitSlot).
          self:emitSend(
              f:step:lessThan(0.0):ifElse({ "greaterOrEqual" }, { "lessOrEqual" }),
              #1) }) }.

emitters:atPut('next, { m, st |
    st:items:size:equals(#0):ifElse(
        { m:closeFor(nil) },
        { st:items:do({ name | m:closeFor(name) }) }) }).

sola:closeFor := { name | | f |
    f := self:innermost.
    f:isNil:or({ f:kind:equals('for):not }):ifTrue({
        self:fail(f:isNil:ifElse(
            { "NEXT with no FOR open" },
            { "NEXT closes the {} opened on line {}"
                :fill([self:openerName(f:kind), f:line]) })) }).
    name:notNil:and({ name:equals(f:name):not }):ifTrue({
        self:fail("NEXT {} closes the FOR on {}, which counts {}"
            :fill([name, f:line, f:name])) }).
    self:popBlock("NEXT").

    self:beginAssign(f:name).
    self:emitLoadVar(f:name).
    f:step:isNil:ifElse(
        { self:emitLocal(f:stepSlot) },
        { self:emitNumber(f:step, f:varType) }).
    self:emitSend("add", #1).
    self:endAssign(f:name).
    self:emitLoopTo(f:top).
    self:fillAll(f:pending).
    self:fillAll(f:exits) }.

; ---------------------------------------------------------------------------
; DO, LOOP, WHILE, WEND

emitters:atPut('do, { m, st | | f |
    f := m:pushBlock('do).
    f:top := m:here.
    st:test:equals('none):ifFalse({
        m:emitCondition(st:expr).
        st:test:equals('until):ifTrue({ m:emitSend("not", #0) }).
        f:pending:add([m:branchHole, 'branch]) }) }).

emitters:atPut('loop, { m, st | | f |
    f := m:openFrame("LOOP", 'do).
    m:popBlock("LOOP").
    st:test:equals('none):ifElse(
        { m:emitLoopTo(f:top) },
        { f:pending:size:notEquals(#0):ifTrue({
              m:fail("a DO tests at one end or at neither, not at both") }).
          m:emitCondition(st:expr).
          st:test:equals('until):ifTrue({ m:emitSend("not", #0) }).
          f:pending:add([m:branchHole, 'branch]).
          m:emitLoopTo(f:top) }).
    m:fillAll(f:pending).
    m:fillAll(f:exits) }).

emitters:atPut('while, { m, st | | f |
    f := m:pushBlock('while).
    f:top := m:here.
    m:emitCondition(st:expr).
    f:pending:add([m:branchHole, 'branch]) }).

emitters:atPut('wend, { m, st | | f |
    f := m:openFrame("WEND", 'while).
    m:popBlock("WEND").
    m:emitLoopTo(f:top).
    m:fillAll(f:pending).
    m:fillAll(f:exits) }).

; `EXIT FOR` and `EXIT DO` leave the innermost loop **of that kind**, which is
; why this searches the stack rather than looking at the top of it: an EXIT FOR
; inside an IF inside the loop is the ordinary way to write one.
emitters:atPut('exit, { m, st | | f |
    ["SUB", "FUNCTION"]:indexOf(st:target):notNil:ifElse(
        { m:inProcedure:ifFalse({
              m:fail("EXIT {} outside a {}":fill([st:target, st:target])) }).
          m:emitReturnValue.
          m:byte(RETURN) },
        { f := m:enclosing(st:target:equals("FOR"):ifElse({ 'for }, { 'do })).
          f:isNil:ifTrue({
              m:fail("EXIT {} with no {} loop around it"
                  :fill([st:target, st:target])) }).
          f:exits:add([m:hole, 'jump]) }) }).

emitters:atPut('call, { m, st | m:emitCall(st:name, st:items, true) }).

emitters:atPut('randomize, { m, st |
    m:emitGlobal("random").
    m:emitTyped(st:expr, 'integer).
    m:emitSend("new", #1).
    m:emitStore(randomName).
    m:emitPop }).

; SHARED and STATIC did their work before the body was emitted -- they are in
; force for the whole procedure wherever they are written, so reading them in
; order would be the wrong answer for a listing that puts them at the bottom.
emitters:atPut('shared, { m, st | nil }).
emitters:atPut('static, { m, st | nil }).

; ---------------------------------------------------------------------------
; Procedures
;
; A `SUB` is a **block**, bound to a global with the procedure's name, and a call
; is `value`. That is the whole mapping, and it is a close fit rather than a
; contrivance: a block has its own frame, takes arguments in slots 1..n, and
; answers its last expression, which is what a procedure needs.
;
; **It never captures its home frame**, which matters more than it looks.
; ROADMAP 3.1 says a block that reads the frame it was written in cannot outlive
; it -- and a SolaBasic procedure has no reason to, because every name it uses is
; either its own slot or a global. So the flags say block-and-not-capturing, the
; procedure escapes freely, and the limitation that would have been in the way is
; not.
;
; **What it does meet is 3.5.** Each call is a real frame, so a recursive
; procedure runs out at about 254 levels. SOLABASIC.md predicted exactly that.

routine := object:new.
routine:name := "".
routine:kind := 'sub.
routine:params := nil.
routine:body := nil.
routine:line := #1.
routine:byref := nil.       ; one boolean per parameter

sola:routines := nil.
sola:routineOrder := nil.

; Procedures are lifted out of the listing before anything is emitted, which is
; what makes a call to something defined further down work and DECLARE useless.
sola:extractRoutines := { | rest, current |
    rest := array:new.
    current := nil.
    self:statements:do({ st |
        self:atLine := st:line.
        current:isNil:ifElse(
            { ['sub, 'function]:indexOf(st:kind):notNil:ifElse(
                { current := self:beginRoutine(st) },
                { ['endsub, 'endfunction]:indexOf(st:kind):notNil:ifTrue({
                      self:fail("{} with no procedure open"
                          :fill([st:kind:equals('endsub):ifElse(
                              { "END SUB" }, { "END FUNCTION" })])) }).
                  rest:add(st) }) },
            { ['sub, 'function]:indexOf(st:kind):notNil:ifTrue({
                  self:fail("a procedure cannot be written inside another") }).
              self:closesRoutine(current, st:kind):ifElse(
                  { ; a label on the closing line belongs to the body, so that
                    ; `GOTO Done` where `Done:` is the last line still lands.
                    st:label:notNil:ifTrue({
                        current:body:add(self:labelOnly(st:label, st:line)) }).
                    current := nil },
                  { current:body:add(st) }) }) }).
    current:notNil:ifTrue({
        self:atLine := current:line.
        self:fail("this {} is never closed by its END {}"
            :fill([current:kind:asString:asUppercase,
                   current:kind:asString:asUppercase])) }).
    self:statements := rest }.

sola:beginRoutine := { st | | r |
    self:routines:includes(st:name):ifTrue({
        self:fail("there are two procedures called '{}'":fill([st:name])) }).
    r := routine:new.
    r:name := st:name.
    r:kind := st:kind.
    r:params := st:items.
    r:body := array:new.
    r:line := st:line.
    self:routines:atPut(st:name, r).
    self:routineOrder:add(r).
    r }.

sola:closesRoutine := { r, kind |
    r:kind:equals('sub):ifElse(
        { kind:equals('endsub) }, { kind:equals('endfunction) }) }.

; ---------------------------------------------------------------------------
; Which parameters are by reference
;
; QBasic passes by reference: assigning to a parameter assigns to the caller's
; variable. Passing everything by value instead would leave `SWAP`-shaped
; programs running and answering *differently*, which is the one outcome this
; project does not take -- so the analysis is here.
;
; **A parameter is by reference when the procedure assigns to it, or hands it on
; to somewhere that does.** The second half is why this is a fixed point rather
; than one pass: `A` passes its parameter to `B`, `B` passes it to `C`, and `C`
; assigns to it, so all three are by reference and finding that out takes as
; many rounds as the chain is long. It settles because a parameter only ever
; turns from by-value to by-reference and never back.

sola:analyseByRef := { | changed |
    self:routineOrder:do({ r |
        r:byref := r:params:collect({ p | self:assignsTo(r:body, p) }) }).
    changed := true.
    { changed }:whileTrue({
        changed := false.
        self:routineOrder:do({ r |
            self:callsIn(r:body):do({ c |
                self:propagate(r, c):ifTrue({ changed := true }) }) }) }) }.

sola:propagate := { r, call | | callee, changed, i, arg, at |
    changed := false.
    self:routines:includes(call:at(#1)):ifTrue({
        callee := self:routines:at(call:at(#1)).
        i := #1.
        { i:lessOrEqual(call:at(#2):size)
            :and({ i:lessOrEqual(callee:byref:size) }) }:whileTrue({
            callee:byref:at(i):ifTrue({
                arg := call:at(#2):at(i).
                arg:kind:equals('variable):and({ arg:grouped:not }):ifTrue({
                    at := r:params:indexOf(arg:name).
                    at:notNil:and({ r:byref:at(at):not }):ifTrue({
                        r:byref:atPut(at, true).
                        changed := true }) }) }).
            i := i:add(#1) }) }).
    changed }.

sola:assignsTo := { body, name | | found |
    found := false.
    body:do({ st | self:assignsIn(st, name):ifTrue({ found := true }) }).
    found }.

sola:assignsIn := { st, name |
    st:kind:equals('let):and({ st:name:equals(name) })
        :or({ st:kind:equals('for):and({ st:name:equals(name) }) })
        :or({ st:then:notNil:and({ self:assignsIn(st:then, name) }) })
        :or({ st:otherwise:notNil:and({ self:assignsIn(st:otherwise, name) }) }) }.

; Every call written in a body, statement and expression alike, as
; [name, arguments].
sola:callsIn := { body | | found |
    found := array:new.
    body:do({ st | self:callsInStatement(st, found) }).
    found }.

sola:callsInStatement := { st, found |
    st:kind:equals('call):ifTrue({
        found:add([st:name, st:items]).
        st:items:do({ a | self:callsInExpression(a, found) }) }).
    st:kind:equals('print):ifTrue({
        st:items:do({ a | self:callsInExpression(a, found) }) }).
    self:callsInExpression(st:expr, found).
    self:callsInExpression(st:limit, found).
    self:callsInExpression(st:step, found).
    st:alternatives:notNil:ifTrue({
        st:alternatives:do({ alt |
            alt:at(#1):equals("is"):ifElse(
                { self:callsInExpression(alt:at(#3), found) },
                { self:callsInExpression(alt:at(#2), found).
                  alt:at(#1):equals("range"):ifTrue({
                      self:callsInExpression(alt:at(#3), found) }) }) }) }).
    st:then:notNil:ifTrue({ self:callsInStatement(st:then, found) }).
    st:otherwise:notNil:ifTrue({ self:callsInStatement(st:otherwise, found) }) }.

sola:callsInExpression := { n, found |
    n:isNil:ifFalse({
        n:kind:equals('call):ifTrue({
            found:add([n:name, n:args]).
            n:args:do({ a | self:callsInExpression(a, found) }) }).
        self:callsInExpression(n:left, found).
        self:callsInExpression(n:right, found) }) }.

; The names a body hands to a by-reference parameter as a plain variable. Those
; are the ones that have to live in a box, because the callee will reach into it.
sola:boxesFor := { body | | names |
    names := array:new.
    self:callsIn(body):do({ c |
        self:routines:includes(c:at(#1)):ifTrue({ | callee, i, arg |
            callee := self:routines:at(c:at(#1)).
            i := #1.
            { i:lessOrEqual(c:at(#2):size)
                :and({ i:lessOrEqual(callee:byref:size) }) }:whileTrue({
                callee:byref:at(i):ifTrue({
                    arg := c:at(#2):at(i).
                    arg:kind:equals('variable):and({ arg:grouped:not }):ifTrue({
                        names:indexOf(arg:name):isNil:ifTrue({
                            names:add(arg:name) }) }) }).
                i := i:add(#1) }) }) }).
    names }.

; ---------------------------------------------------------------------------
; A procedure, compiled

; A STATIC survives between calls, so it cannot be a frame slot -- a frame is
; new every call. It is a global of its own instead, named after the procedure
; that owns it and with spaces in the name so that nothing a BASIC program can
; spell will collide with it.
; "1 argument" and "2 arguments", because a message that says "1 argument(s)"
; was written by somebody who did not want to look at it again.
sola:countOf := { n, what |
    n:asString:concat(" "):concat(what):concat(n:equals(#1):ifElse({ "" }, { "s" })) }.

sola:staticName := { routineName, name |
    "static ":concat(routineName):concat(" "):concat(name) }.

; **And it is given its nought before anything runs**, because the first thing a
; counter does is read itself. A global that was never assigned is an undefined
; name, not a zero.
sola:emitStaticInitialisers := {
    self:routineOrder:do({ r |
        r:body:do({ st |
            st:kind:equals('static):ifTrue({
                st:items:do({ n |
                    self:emitZero(self:typeOfName(n)).
                    self:emitStore(self:staticName(r:name, n)).
                    self:emitPop }) }) }) }) }.

; What a call answers: a builtin says so itself, and a FUNCTION says so with
; the suffix on its own name, exactly as a variable does.
sola:typeOfCall := { n | | answers |
    builtins:includes(n:name):ifElse(
        { answers := builtins:at(n:name):at(#2).
          answers:equals('sameAsArg):ifElse(
              { n:args:size:equals(#0):ifElse(
                  { 'double },
                  { n:args:at(#1):type:equals('integer):ifElse(
                      { 'integer }, { 'double }) }) },
              { answers }) },
        { self:routines:includes(n:name):ifElse(
            { self:typeOfName(n:name) },
            { self:fail("there is no SUB or FUNCTION called '{}'":fill([n:name])) }) }) }.

sola:emitReturnValue := {
    self:returnName:equals(""):ifElse(
        { self:emitNil },
        { self:emitLoadVar(self:returnName) }) }.

sola:emitRoutine := { r | | method, index, i |
    self:pushUnit.
    self:inProcedure := true.
    self:atLine := r:line.
    self:returnName := r:kind:equals('function):ifElse({ r:name }, { "" }).

    r:body:do({ st |
        st:kind:equals('shared):ifTrue({
            st:items:do({ n | self:shared:add(n) }) }).
        st:kind:equals('static):ifTrue({
            st:items:do({ n |
                self:statics:atPut(n, self:staticName(r:name, n)) }) }) }).

    ; Slots 1..n are the parameters, in the order they were written, because
    ; that is where a block's arguments arrive.
    r:params:do({ p | self:newLocal(p) }).
    i := #1.
    { i:lessOrEqual(r:params:size) }:whileTrue({
        r:byref:at(i):ifTrue({ self:boxed:add(r:params:at(i)) }).
        i := i:add(#1) }).
    self:boxesFor(r:body):do({ n |
        self:boxed:indexOf(n):isNil:ifTrue({
            self:boxed:add(n).
            self:toBox:add(n) }) }).

    ; A FUNCTION answers by assigning to its own name, so the name is a local
    ; and the body's last act is to push it.
    r:kind:equals('function):ifTrue({ self:newLocal(r:name) }).

    self:mark(r:line).
    r:kind:equals('function):ifTrue({
        self:emitZero(self:typeOfName(r:name)).
        self:emitSetLocal(self:slotFor(r:name)).
        self:emitPop }).
    self:statementsOfScope := r:body.
    self:emitVariableInitialisers(
        r:params:copyFrom(#1, r:params:size):add(r:name)).
    self:emitBoxes.
    r:body:do({ st | self:emitStatement(st) }).
    self:checkBlocksClosed.
    self:mark(self:atLine).
    self:emitReturnValue.
    self:byte(RETURN).

    method := self:chunkOfUnit.
    method:atPut("name", r:name).
    method:atPut("arity", r:params:size).
    ; Flag 1 says block. Flag 2 would say it reaches out of its own frame, and
    ; nothing here ever does -- see the note above about 3.1.
    method:atPut("flags", #1).
    self:popUnit.

    index := self:methods:size.
    self:methods:add(method).
    self:byte(BLOCK).
    self:u16(index).
    self:emitStore(r:name).
    self:emitPop }.

; ---------------------------------------------------------------------------
; A call
;
; The block, then the arguments, then `value`. A by-reference argument that is a
; plain variable hands over **the box itself**, so the callee's `atPut` writes
; the caller's storage and there is nothing to copy back.
;
; An argument at a by-reference position that is *not* a plain variable -- an
; expression, or a name in brackets -- gets a box of its own that nobody keeps.
; That is QBasic's rule and it is what `CALL Foo((x))` is for.

sola:emitCall := { name, args, asStatement | | r, i, arg, wanted |
    builtins:includes(name):ifTrue({
        self:emitBuiltin(name, args).
        asStatement:ifTrue({ self:emitPop }) }).
    builtins:includes(name):ifFalse({
    self:routines:includes(name):ifFalse({
        self:fail("there is no SUB or FUNCTION called '{}'":fill([name])) }).
    r := self:routines:at(name).
    args:size:equals(r:params:size):ifFalse({
        self:fail("{} takes {} and was given {}"
            :fill([name, self:countOf(r:params:size, "argument"),
                   args:size])) }).

    self:emitGlobal(name).
    i := #1.
    { i:lessOrEqual(args:size) }:whileTrue({
        arg := args:at(i).
        wanted := self:typeOfName(r:params:at(i)).
        r:byref:at(i):ifElse(
            { arg:kind:equals('variable):and({ arg:grouped:not }):ifElse(
                { ; The box is handed over as it stands, so the two names have to
                  ; agree about what is in it: the callee writes through it and
                  ; the caller reads back what it wrote.
                  self:typeOfName(arg:name):equals(wanted):ifFalse({
                      self:fail("{} and {}'s {} are different types, and a "
                          :concat("variable passed by reference must match")
                          :fill([arg:name, name, r:params:at(i)])) }).
                  self:emitRawVar(arg:name) },
                { self:emitGlobal("array").
                  self:emitTyped(arg, wanted).
                  self:emitSend("of", #1) }) },
            { self:emitTyped(arg, wanted) }).
        i := i:add(#1) }).
    self:emitSend("value", args:size).
    asStatement:ifTrue({ self:emitPop }) }) }.

; ---------------------------------------------------------------------------
; The supplied functions
;
; **Each one is emitted where it is called rather than being a procedure that is
; called.** There is nowhere to put a library: the `.sob` this compiler writes is
; the whole program, and none of `lib/` is in it. So a builtin is a short
; sequence of instructions, and the ones that need to decide something -- `SGN`,
; `INSTR`, the clamping in `LEFT$` -- decide it with the same jumps a `SELECT
; CASE` uses.
;
; An entry is `[argument types, what it answers, how, detail]`, and
; `'sameAsArg` answers whatever its argument was, which is how `ABS` and `INT`
; keep an Integer an Integer.
;
; **`how` is a symbol and not a block, and that is 3.1's doing.** The first
; version of this had a helper that built the emitting block and stored it --
; and the block read the helper's parameters, so it captured a frame that had
; already returned by the time anything called it.
; [3.1](../docs/ROADMAP.md#31-capturing-blocks-cannot-escape-their-frame) says a
; block that reads its home frame cannot outlive it, and the machine said so
; exactly: *block outlived the frame it was written in*. The blocks further down
; are written at the top level, read nothing but their own parameters, and are
; fine; the two shapes that were not are a symbol and a selector instead.

sola:builtinArg := { args, i, t | self:emitTyped(args:at(i), t) }.

; A builtin of one argument that is one send.
sola:simpleBuiltin := { name, argType, answers, selector |
    builtins:atPut(name, [[argType], answers, 'simple, selector]) }.

sola:simpleBuiltin("ABS",   'double, 'sameAsArg, "abs").
sola:simpleBuiltin("ATN",   'double, 'double, "atan").
sola:simpleBuiltin("COS",   'double, 'double, "cos").
sola:simpleBuiltin("SIN",   'double, 'double, "sin").
sola:simpleBuiltin("TAN",   'double, 'double, "tan").
sola:simpleBuiltin("EXP",   'double, 'double, "exp").
sola:simpleBuiltin("LOG",   'double, 'double, "log").
sola:simpleBuiltin("SQR",   'double, 'double, "sqrt").
sola:simpleBuiltin("LEN",   'string, 'integer, "size").
sola:simpleBuiltin("UCASE$", 'string, 'string, "asUppercase").
sola:simpleBuiltin("LCASE$", 'string, 'string, "asLowercase").
sola:simpleBuiltin("STR$",  'double, 'string, "asString").
sola:simpleBuiltin("CHR$",  'integer, 'string, "asCharacter").

; `ABS` on an Integer must stay an Integer, so the argument is not forced to a
; Double first. The table above says `'double`; this overrides it.
builtins:atPut("ABS", [['numeric], 'sameAsArg, 'block,
    { m, args | m:emitExpression(args:at(#1)). m:emitSend("abs", #0) }]).

; **`VAL` is strict here**, where BASIC's is lenient: the whole string has to be
; a number, and `VAL("12ab")` is an error rather than `12`. Reading a number out
; of the front of a string wants a scanner, and there is not one in the emitted
; program -- see the reference manual, which says so where somebody will look.
builtins:atPut("VAL", [['string], 'double, 'block,
    { m, args | m:builtinArg(args, #1, 'string). m:emitSend("asFloat", #0) }]).

builtins:atPut("ASC", [['string], 'integer, 'block,
    { m, args |
        m:builtinArg(args, #1, 'string).
        m:emitIntConst(#1). m:emitSend("at", #1).
        m:emitSend("asByte", #0) }]).

; `INT` is the floor and `FIX` cuts towards nought, and they differ only for a
; negative: INT(-2.5) is -3 and FIX(-2.5) is -2.
sola:roundingBuiltin := { name, selector |
    builtins:atPut(name, [['numeric], 'sameAsArg, 'rounding, selector]) }.
sola:roundingBuiltin("INT", "floor").
sola:roundingBuiltin("FIX", "truncated").

; `SGN` needs its argument twice and there is no instruction that duplicates the
; top of the stack, so it goes into a scratch slot first.
builtins:atPut("SGN", [['double], 'integer, 'block,
    { m, args | | x, notNegative, isZero, fromNegative, fromPositive |
        x := m:intoScratchAs(args:at(#1), 'double).
        m:emitLocal(x). m:emitConst(0.0). m:emitSend("lessThan", #1).
        notNegative := m:branchHole.
        m:emitIntConst(#-1).
        fromNegative := m:hole.

        m:fillBranch(notNegative).
        m:emitLocal(x). m:emitConst(0.0). m:emitSend("greaterThan", #1).
        isZero := m:branchHole.
        m:emitIntConst(#1).
        fromPositive := m:hole.

        m:fillBranch(isZero).
        m:emitIntConst(#0).

        ; **Three arms and three jumps.** An earlier draft had two arms sharing
        ; one hole, which patched it twice and sent the first arm wherever the
        ; second one landed. The verifier refused the file rather than running
        ; it -- *bytecode is internally inconsistent*, at load, exit 65 -- which
        ; is the whole reason a Solum-emitted `.sob` is checked before it runs.
        m:fillJump(fromNegative).
        m:fillJump(fromPositive).
        m:dropScratch }]).

; **`INSTR` answers 0 when it does not find it**, where the machine answers nil.
builtins:atPut("INSTR", [['string, 'string], 'integer, 'block,
    { m, args | | found, zero, done |
        args:size:equals(#3):ifElse(
            { m:builtinArg(args, #2, 'string).
              m:builtinArg(args, #3, 'string).
              m:builtinArg(args, #1, 'integer).
              m:emitSend("indexOf", #2) },
            { m:builtinArg(args, #1, 'string).
              m:builtinArg(args, #2, 'string).
              m:emitSend("indexOf", #1) }).
        found := m:takeScratch.
        m:emitSetLocal(found). m:emitPop.
        m:emitLocal(found). m:emitSend("notNil", #0).
        zero := m:branchHole.
        m:emitLocal(found).
        done := m:hole.
        m:fillBranch(zero).
        m:emitIntConst(#0).
        m:fillJump(done).
        m:dropScratch }]).

; ---------------------------------------------------------------------------
; The ones that take a piece of a string
;
; `copyFrom` refuses a range outside the string and BASIC clamps, so the bounds
; are pushed into a slot and squared up with two comparisons before they are
; used. That is what most of the length here is.

sola:emitClampLow := { slot, low | | fine |
    self:emitLocal(slot). self:emitIntConst(low). self:emitSend("lessThan", #1).
    fine := self:branchHole.
    self:emitIntConst(low). self:emitSetLocal(slot). self:emitPop.
    self:fillBranch(fine) }.

sola:emitClampToSize := { slot, strSlot | | fine |
    self:emitLocal(slot).
    self:emitLocal(strSlot). self:emitSend("size", #0).
    self:emitSend("greaterThan", #1).
    fine := self:branchHole.
    self:emitLocal(strSlot). self:emitSend("size", #0).
    self:emitSetLocal(slot). self:emitPop.
    self:fillBranch(fine) }.

builtins:atPut("LEFT$", [['string, 'integer], 'string, 'block,
    { m, args | | str, n |
        str := m:intoScratchAs(args:at(#1), 'string).
        n := m:intoScratchAs(args:at(#2), 'integer).
        m:emitClampLow(n, #0).
        m:emitClampToSize(n, str).
        m:emitLocal(str). m:emitIntConst(#1). m:emitLocal(n).
        m:emitSend("copyFrom", #2).
        m:dropScratch. m:dropScratch }]).

builtins:atPut("RIGHT$", [['string, 'integer], 'string, 'block,
    { m, args | | str, n |
        str := m:intoScratchAs(args:at(#1), 'string).
        n := m:intoScratchAs(args:at(#2), 'integer).
        m:emitClampLow(n, #0).
        m:emitClampToSize(n, str).
        ; from = size - n + 1
        m:emitLocal(str). m:emitSend("size", #0).
        m:emitLocal(n). m:emitSend("sub", #1).
        m:emitIntConst(#1). m:emitSend("add", #1).
        m:emitSetLocal(n). m:emitPop.
        m:emitLocal(str). m:emitLocal(n).
        m:emitLocal(str). m:emitSend("size", #0).
        m:emitSend("copyFrom", #2).
        m:dropScratch. m:dropScratch }]).

; `MID$(s, start)` and `MID$(s, start, length)`. A start past the end is the
; empty string rather than an error, which is BASIC's rule.
builtins:atPut("MID$", [['string, 'integer], 'string, 'block,
    { m, args | | str, from, last, empty, done |
        str := m:intoScratchAs(args:at(#1), 'string).
        from := m:intoScratchAs(args:at(#2), 'integer).
        last := m:takeScratch.
        m:emitClampLow(from, #1).

        args:size:equals(#3):ifElse(
            { m:emitLocal(from).
              m:builtinArg(args, #3, 'integer).
              m:emitSend("add", #1).
              m:emitIntConst(#1). m:emitSend("sub", #1) },
            { m:emitLocal(str). m:emitSend("size", #0) }).
        m:emitSetLocal(last). m:emitPop.
        m:emitClampToSize(last, str).

        m:emitLocal(from).
        m:emitLocal(last).
        m:emitSend("greaterThan", #1).
        empty := m:branchHole.
        m:emitString("").
        done := m:hole.
        m:fillBranch(empty).
        m:emitLocal(str). m:emitLocal(from). m:emitLocal(last).
        m:emitSend("copyFrom", #2).
        m:fillJump(done).
        m:dropScratch. m:dropScratch. m:dropScratch }]).

; ---------------------------------------------------------------------------
; The ones that need a loop
;
; A loop in a builtin is the same `LOOP` and `JUMP_IF_FALSE` a `WHILE` compiles
; to, which is why these cost lines here and nothing new in the machine.

sola:emitTrim := { args, fromLeft | | str, i, top, out |
    str := self:intoScratchAs(args:at(#1), 'string).
    i := self:takeScratch.
    fromLeft:ifElse(
        { self:emitIntConst(#1) },
        { self:emitLocal(str). self:emitSend("size", #0) }).
    self:emitSetLocal(i). self:emitPop.

    top := self:here.
    ; while i is in range and the character there is a space
    fromLeft:ifElse(
        { self:emitLocal(i).
          self:emitLocal(str). self:emitSend("size", #0).
          self:emitSend("lessOrEqual", #1) },
        { self:emitLocal(i). self:emitIntConst(#1).
          self:emitSend("greaterOrEqual", #1) }).
    out := self:branchHole.
    self:emitLocal(str). self:emitLocal(i). self:emitSend("at", #1).
    self:emitString(" "). self:emitSend("equals", #1).
    out := [out, self:branchHole].
    self:emitLocal(i).
    self:emitIntConst(fromLeft:ifElse({ #1 }, { #-1 })).
    self:emitSend("add", #1).
    self:emitSetLocal(i). self:emitPop.
    self:emitLoopTo(top).
    self:fillBranch(out:at(#1)).
    self:fillBranch(out:at(#2)).

    fromLeft:ifElse(
        { self:emitLocal(str). self:emitLocal(i).
          self:emitLocal(str). self:emitSend("size", #0) },
        { self:emitLocal(str). self:emitIntConst(#1). self:emitLocal(i) }).
    self:emitSend("copyFrom", #2).
    self:dropScratch. self:dropScratch }.

builtins:atPut("LTRIM$", [['string], 'string, 'block,
    { m, args | m:emitTrim(args, true) }]).
builtins:atPut("RTRIM$", [['string], 'string, 'block,
    { m, args | m:emitTrim(args, false) }]).

; `STRING$(n, s)` is `s`'s first character n times; `SPACE$(n)` is that with a
; space.
sola:emitRepeatString := { countNode, charNode | | out, i, n, top, done |
    n := self:intoScratchAs(countNode, 'integer).
    out := self:takeScratch.
    i := self:takeScratch.
    charNode:isNil:ifElse(
        { self:emitString(" ") },
        { self:emitTyped(charNode, 'string).
          self:emitIntConst(#1). self:emitSend("at", #1) }).
    self:emitSetLocal(out). self:emitPop.
    self:emitString("").
    self:emitSetLocal(i). self:emitPop.

    top := self:here.
    self:emitLocal(n). self:emitIntConst(#0). self:emitSend("greaterThan", #1).
    done := self:branchHole.
    self:emitLocal(i). self:emitLocal(out). self:emitSend("concat", #1).
    self:emitSetLocal(i). self:emitPop.
    self:emitLocal(n). self:emitIntConst(#1). self:emitSend("sub", #1).
    self:emitSetLocal(n). self:emitPop.
    self:emitLoopTo(top).
    self:fillBranch(done).
    self:emitLocal(i).
    self:dropScratch. self:dropScratch. self:dropScratch }.

builtins:atPut("SPACE$", [['integer], 'string, 'block,
    { m, args | m:emitRepeatString(args:at(#1), nil) }]).
builtins:atPut("STRING$", [['integer, 'string], 'string, 'block,
    { m, args | m:emitRepeatString(args:at(#1), args:at(#2)) }]).

; ---------------------------------------------------------------------------
; RND, and the generator it reads from
;
; One generator for the program, made before its first line runs. `RANDOMIZE`
; replaces it with one seeded to repeat.

randomName := "the random generator".

builtins:atPut("RND", [[], 'double, 'block,
    { m, args |
        m:emitGlobal(randomName).
        m:emitSend("fraction", #0) }]).

sola:emitRandomGenerator := {
    self:emitGlobal("random").
    self:emitSend("new", #0).
    self:emitStore(randomName).
    self:emitPop }.

; ---------------------------------------------------------------------------
; Emitting one, and checking it was called properly

sola:emitBuiltin := { name, args | | entry, how |
    entry := builtins:at(name).
    self:checkBuiltinArity(name, args, entry).
    how := entry:at(#3).
    [ { how:equals('simple) },
        { self:builtinArg(args, #1, entry:at(#1):at(#1)).
          self:emitSend(entry:at(#4), #0) },
      { how:equals('rounding) },
        { args:at(#1):type:equals('integer):ifElse(
            { self:emitExpression(args:at(#1)) },
            { self:builtinArg(args, #1, 'double).
              self:emitSend(entry:at(#4), #0).
              self:emitSend("asFloat", #0) }) },
        { entry:at(#4):value(self, args) } ]:ifElseIf }.

sola:checkBuiltinArity := { name, args, entry | | least, most |
    least := entry:at(#1):size.
    most := least.
    ["MID$", "INSTR"]:indexOf(name):notNil:ifTrue({ most := #3 }).
    args:size:lessThan(least):or({ args:size:greaterThan(most) }):ifTrue({
        self:fail("{} takes {} and was given {}"
            :fill([name, self:countOf(least, "argument"), args:size])) }) }.

; `IF <condition> THEN GOTO <label>` is the condition, a conditional jump over
; the `GOTO`, and the `GOTO`.
;
; `OP_JUMP_IF_FALSE` carries the name of the selector it was inlined from so
; that a non-boolean reports the same *does not understand* a real send would.
; There is no real send here to name, so it names `ifTrue` -- which is the
; message a condition that is not a boolean has failed to understand, and is
; what the reader of the error needs to be told.


; A condition that is already a comparison answers a boolean. Anything else is
; a number, and BASIC's rule is that a non-zero number is true -- so it is
; compared with nought rather than handed to the machine, which would refuse it.
sola:emitCondition := { n | self:emitTyped(n, 'boolean) }.

; The items of one PRINT are joined and shown once, so that `PRINT "x = "; x`
; is one line. **This is not BASIC's PRINT**: there are no print zones, no
; leading space in front of a positive number and no trailing space after one,
; and `,` does the same thing as `;`. That is stage 6 and this is stage 3.
sola:emitPrint := { st | | first |
    st:items:size:equals(#0):ifElse(
        { self:emitString("") },
        { first := true.
          st:items:do({ item |
              ; Anything already a string converts for nothing, which is what
              ; keeps a literal from costing a send.
              self:emitTyped(item, 'string).
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

sola:compile := { source, path |
    self:path := path.
    self:statements := array:new.
    self:unitStack := array:new.
    self:routines := dictionary:new.
    self:routineOrder := array:new.
    self:defaultTypes := dictionary:new.
    self:freshUnit.

    self:readStatements(source).
    self:extractRoutines.
    self:analyseByRef.

    self:atLine := #1.
    self:mark(#1).
    self:boxesFor(self:statements):do({ n |
        self:boxed:add(n). self:toBox:add(n) }).

    ; Procedures first, so that every name a call needs is bound before the
    ; module's first line runs.
    self:emitRandomGenerator.
    self:emitStaticInitialisers.
    self:routineOrder:do({ r | self:emitRoutine(r) }).
    self:statementsOfScope := self:statements.
    self:emitVariableInitialisers([]).
    self:emitBoxes.
    self:statements:do({ st | self:emitStatement(st) }).
    self:checkBlocksClosed.

    ; The last instruction of every chunk is a HALT and the verifier requires
    ; it. A label on the line after the last statement is a real thing to
    ; write -- `GOTO Done` where `Done:` is the end of the program -- so the
    ; HALT is where any such label lands, and it is marked before it is emitted.
    self:atLine := self:statements:size:equals(#0):ifElse(
        { #1 }, { self:statements:at(self:statements:size):line:add(#1) }).
    self:mark(self:atLine).
    self:trailingLabels.
    self:needsHalt:ifTrue({ self:byte(HALT) }).

    self:chunkOfUnit }.

; **The chunk's last instruction must be a HALT and the verifier requires it**,
; so one is added -- unless the program already ends in `END`, which is that
; instruction, and nothing is waiting for an offset behind it. A trailing label
; is what makes the difference: `GOTO Done` where `Done:` is the last line of
; the program needs somewhere to land, and that somewhere is the HALT.
sola:needsHalt := {
    self:pendingLabels:size:notEquals(#0):or({
        self:statements:size:equals(#0):or({
            self:statements:at(self:statements:size):kind:notEquals('end) }) }) }.

; **A block left open is reported where it was opened, not at the end of the
; file**, because the end of the file is where you already know something is
; wrong and the opening line is the one you have to go and look at.
sola:checkBlocksClosed := { | f |
    self:blocks:size:notEquals(#0):ifTrue({
        f := self:innermost.
        self:atLine := f:line.
        self:fail("this {} is never closed by its {}"
            :fill([self:openerName(f:kind), self:closerName(f:kind)])) }) }.

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

demo := "' Stage 2's structure and stage 3's jumps, in one program. The GOTO\n"
    :concat("' leaves a block and lands just before NEXT, which is how BASIC\n")
    :concat("' spells what a later language calls `continue`.\n")
    :concat("total = 0\n")
    :concat("FOR i = 1 TO 10\n")
    :concat("  IF i = 7 THEN GOTO Skip\n")
    :concat("  SELECT CASE i\n")
    :concat("  CASE 1, 2, 3\n")
    :concat("    PRINT i; \" small\"\n")
    :concat("  CASE 4 TO 6\n")
    :concat("    PRINT i; \" middle\"\n")
    :concat("  CASE IS >= 9\n")
    :concat("    PRINT i; \" large\"\n")
    :concat("  CASE ELSE\n")
    :concat("    PRINT i; \" none of those\"\n")
    :concat("  END SELECT\n")
    :concat("  total = total + i\n")
    :concat("Skip:\n")
    :concat("NEXT i\n")
    :concat("PRINT \"total \"; total\n")
    :concat("k = 0\n")
    :concat("DO\n")
    :concat("  k = k + 1\n")
    :concat("  IF k = 3 THEN EXIT DO\n")
    :concat("LOOP\n")
    :concat("PRINT \"left the DO at \"; k\n")
    :concat("FUNCTION Triangle (n)\n")
    :concat("  IF n <= 1 THEN\n")
    :concat("    Triangle = 1\n")
    :concat("  ELSE\n")
    :concat("    Triangle = n + Triangle(n - 1)\n")
    :concat("  END IF\n")
    :concat("END FUNCTION\n")
    :concat("PRINT \"the tenth triangular number is \"; Triangle(10)\n")
    :concat("END\n").

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
