; sola.sol -- SolaBasic compiled to bytecode. Stage 3: labels and GOTO.
;
; Run with:  ./bin/solas programs/sola.sol && ./bin/solvm programs/sola.sob
; On a file:  ./bin/solvm programs/sola.sob prog.bas [prog.sob]
;
; The thirteenth program here, and the second that is about another language --
; but where [basic.sol](basic.sol) *interprets* one, this **compiles** one, and
; the file it writes is run by `solvm` with nothing of this program present.
;
; The language is [SolaBasic](../docs/SOLABASIC.md). Stages 2 and 3 of the eight
; that document lists are here, and they were done in that order backwards.
; **Stage 3 went first on purpose** -- it is `GOTO` and labels, the claim the
; whole design rests on, and the document says to reach it in week one rather
; than week six. Stage 2 is the structured half, and it turned out to need
; nothing the first half had not already built.
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
; What is here, and what is stage 4 onwards
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
;   EXIT          `EXIT FOR` and `EXIT DO`
;   assignment    `LET` optional, scalars only
;   PRINT         expressions and strings, `;` and `,`
;   END           stops
;   expressions   `+ - * /`, unary minus, parentheses, and the six comparisons
;   comments      `REM` and `'`
;
; **Not here, and not pretended:** `SUB`, `FUNCTION`, arrays, `INPUT`, files,
; and the whole type system -- every number is a Double, which is SolaBasic's
; default type and the only one these stages have. `PRINT`'s real formatting is
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

keywords := ["PRINT", "GOTO", "IF", "THEN", "ELSE", "ELSEIF", "END", "REM",
             "LET", "SELECT", "CASE", "IS", "TO", "FOR", "STEP", "NEXT",
             "DO", "LOOP", "WHILE", "WEND", "UNTIL", "EXIT"].

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
frame:index := #0.          ; 'for and 'select: which hidden globals are theirs
frame:step := nil.          ; 'for: the step, when it was written as a literal
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
    t:isNil:or({ ["FOR", "DO"]:indexOf(t:text):isNil }):ifTrue({
        m:fail("EXIT takes FOR or DO") }).
    st:target := t:text.
    m:expectEndOfLine("EXIT") }).

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

emitters := dictionary:new.

sola:emitStatement := { st |
    self:atLine := st:line.
    self:mark(st:line).
    st:label:notNil:ifTrue({
        self:labelAt:includes(st:label):ifTrue({
            self:fail("the label '{}' is used twice":fill([st:label])) }).
        self:labelAt:atPut(st:label, self:here) }).
    self:guardSelect(st:kind).
    emitters:at(st:kind):value(self, st) }.

emitters:atPut('rem, { m, st | nil }).
emitters:atPut('end, { m, st | m:byte(HALT) }).
emitters:atPut('goto, { m, st | m:emitJump(st:target) }).
emitters:atPut('print, { m, st | m:emitPrint(st) }).
emitters:atPut('let, { m, st |
    m:emitExpression(st:expr). m:emitStore(st:name). m:emitPop }).

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

sola:selectName := { i | "select ":concat(i:asString) }.

emitters:atPut('select, { m, st | | f |
    m:selectCount := m:selectCount:add(#1).
    m:emitExpression(st:expr).
    m:emitStore(m:selectName(m:selectCount)).
    m:emitPop.
    f := m:pushBlock('select).
    f:index := m:selectCount }).

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
        misses := m:emitAlternative(f:index, st:alternatives:at(i)).
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
sola:emitAlternative := { index, alt | | misses |
    misses := array:new.
    alt:at(#1):equals("value"):ifTrue({
        self:emitGlobal(self:selectName(index)).
        self:emitExpression(alt:at(#2)).
        self:emitSend("equals", #1).
        misses:add(self:branchHole) }).
    alt:at(#1):equals("range"):ifTrue({
        self:emitGlobal(self:selectName(index)).
        self:emitExpression(alt:at(#2)).
        self:emitSend("greaterOrEqual", #1).
        misses:add(self:branchHole).
        self:emitGlobal(self:selectName(index)).
        self:emitExpression(alt:at(#3)).
        self:emitSend("lessOrEqual", #1).
        misses:add(self:branchHole) }).
    alt:at(#1):equals("is"):ifTrue({
        self:emitGlobal(self:selectName(index)).
        self:emitExpression(alt:at(#3)).
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

sola:forLimitName := { i | "for limit ":concat(i:asString) }.
sola:forStepName  := { i | "for step ":concat(i:asString) }.

; **A written-out step fixes the direction at compile time**, which is worth the
; ten lines because it is nearly every loop: `FOR I = 1 TO 10` and
; `FOR I = 10 TO 1 STEP -1` both know which way they run before they start.
sola:literalStep := { n |
    n:isNil:ifElse(
        { 1.0 },
        { n:kind:equals('number):ifElse(
            { n:value },
            { n:kind:equals('negate):and({ n:left:kind:equals('number) }):ifElse(
                { n:left:value:negated },
                { nil }) }) }) }.

emitters:atPut('for, { m, st | | f, step |
    m:forCount := m:forCount:add(#1).
    m:emitExpression(st:expr).  m:emitStore(st:name). m:emitPop.
    m:emitExpression(st:limit). m:emitStore(m:forLimitName(m:forCount)). m:emitPop.

    step := m:literalStep(st:step).
    step:isNil:ifTrue({
        m:emitExpression(st:step).
        m:emitStore(m:forStepName(m:forCount)).
        m:emitPop }).

    f := m:pushBlock('for).
    f:index := m:forCount.
    f:name := st:name.
    f:step := step.
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
        { self:emitGlobal(self:forLimitName(f:index)).
          self:emitGlobal(f:name).
          self:emitSend("sub", #1).
          self:emitGlobal(self:forStepName(f:index)).
          self:emitSend("mul", #1).
          self:emitConst(0.0).
          self:emitSend("greaterOrEqual", #1) },
        { self:emitGlobal(f:name).
          self:emitGlobal(self:forLimitName(f:index)).
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

    self:emitGlobal(f:name).
    f:step:isNil:ifElse(
        { self:emitGlobal(self:forStepName(f:index)) },
        { self:emitConst(f:step) }).
    self:emitSend("add", #1).
    self:emitStore(f:name).
    self:emitPop.
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
    f := m:enclosing(st:target:equals("FOR"):ifElse({ 'for }, { 'do })).
    f:isNil:ifTrue({
        m:fail("EXIT {} with no {} loop around it":fill([st:target, st:target])) }).
    f:exits:add([m:hole, 'jump]) }).

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
    self:blocks := array:new.
    self:forCount := #0.
    self:selectCount := #0.

    self:readStatements(source).
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
